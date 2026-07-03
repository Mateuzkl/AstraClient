--[[============================================================================
  scripting/api/spells.lua — Zerobot-compatible `Spells` namespace.
  ============================================================================

  Builder module (see scripting/scripting.lua header + scripting/CONTRACT.md).
  Returns `function(api, ctx) ... return Spells end` and is injected into every
  sandboxed script as the global `Spells`.

  Plain namespace (NOT a class). Spell lookup + cooldown/group-cooldown queries.

  NAME CLASH NOTE: the engine ALREADY has a global `Spells` table (gamelib/
  spells.lua) which is the client's spell database. This sandbox namespace is a
  DIFFERENT object that WRAPS that engine table; inside the sandbox `Spells`
  means this wrapper. We reach the engine DB via the file-local `EngineSpells`
  captured below (we run outside the sandbox, so the engine global is in scope).

  Public surface:
    Lookup (engine DB) — the names the client's Zerobot dialect expects,
    returning the SPELL TABLE (or nil), exactly like the engine functions:
      * Spells.getSpellByWords(words) -> spellTable | nil
      * Spells.getSpellByName(name)   -> spellTable | nil
    ZB-spec lookup (numeric id, or -1 — Zerobot spell.lua §5):
      * Spells.getIdByWords(words) -> number   (the spell's icon/client id, -1 if none)
      * Spells.getIdByName(name)   -> number
    Cooldown queries (ZB-spec §5):
      * Spells.isInCooldown(id)              -> bool
      * Spells.getLeftCooldownTime(id)       -> number ms remaining, -1 if none
      * Spells.groupIsInCooldown(groupId)    -> bool   (Enums.SpellGroups)
      * Spells.getLeftGroupCooldownTime(groupId) -> number ms remaining, -1 if none

  SPELL DB SHAPE (verified — gamelib/spells.lua):
    Spells.getSpellByWords(words) -> spell, profile, key   (does words:lower():trim()
      internally, so it ERRORS on a non-string — we guard).
    Spells.getSpellByName(name)   -> SpellInfo[profile][name]   (indexes
      SpellInfo[nil] when the name is unknown -> ERRORS — we guard via
      getSpellProfileByName first).
    A spell record has: .id (the ICON / client id — this is the value the server
    keys spell cooldowns by), .words, .name, .group = { [groupId]=cooldownMs },
    .exhaustion. So a spell's "id" for cooldown purposes is spell.id.

  COOLDOWN SOURCE (verified — capabilities §9 + game.cpp + cooldown.lua):
    The engine fires, on g_game:
      * onSpellCooldown(iconId, durationMs)       — per-spell (iconId == spell.id)
      * onSpellGroupCooldown(groupId, durationMs) — per group
    The built-in cooldown.lua module consumes these for its UI but keeps the
    state in module-local tables we can't read. So this namespace OWNS its own
    cooldown ledger: it connects to those two events ONCE (at module build, i.e.
    engine scope — NOT per script) and records an expiry timestamp
    (g_clock.millis() + duration) per iconId / groupId. Queries compare against
    g_clock.millis(). Expiries are cleared on logout (onGameEnd) so a relog
    starts clean. This connection lives for the whole helper session (it is not
    tied to any one script), so we do NOT register it via ctx.onCleanup.

  RULES (CONTRACT): no globals; cross-namespace refs (api.Enums) are lazy; runs
  OUTSIDE the sandbox (engine Spells DB, g_game, g_clock, connect/disconnect).
  Return semantics: lookup-by-table returns nil when nothing matches; lookup-by-id
  returns -1 (ZB); cooldown getters return -1 when not on cooldown (ZB).
============================================================================]]

return function(api, ctx)
  local Spells = {}

  -- The engine spell database (the OTHER global also named Spells). Capture by a
  -- distinct local so our wrapper methods can call it without self-recursion.
  local EngineSpells = rawget(_G, "Spells")

  -- one-time honest stub notice if the engine DB is missing/partial.
  local warnedNoDb = false
  local function dbMissing()
    if not warnedNoDb then
      warnedNoDb = true
      ctx.log("[Spells] engine spell database unavailable; lookups return nil/-1")
    end
    return nil
  end

  -- ---------------------------------------------------------------------------
  -- Cooldown ledger (ms-expiry keyed by icon id / group id), populated from the
  -- engine's spell-cooldown events. monotonic clock = g_clock.millis().
  -- ---------------------------------------------------------------------------
  local spellExpiry = {}   -- [iconId]  = millis when the spell comes off cooldown
  local groupExpiry = {}   -- [groupId] = millis when the group comes off cooldown

  local function now()
    return g_clock.millis()
  end

  local function onSpellCooldown(iconId, duration)
    if type(iconId) == "number" and type(duration) == "number" then
      spellExpiry[iconId] = now() + duration
    end
  end

  local function onSpellGroupCooldown(groupId, duration)
    if type(groupId) == "number" and type(duration) == "number" then
      groupExpiry[groupId] = now() + duration
    end
  end

  local function onGameEnd()
    -- relog/logout: cooldowns no longer apply.
    spellExpiry = {}
    groupExpiry = {}
  end

  -- Connect ONCE, at engine scope (this module builds once per helper load, not
  -- per script). Guarded so we never double-connect if the builder ever re-runs.
  if not rawget(Spells, "_cdConnected") then
    connect(g_game, {
      onSpellCooldown      = onSpellCooldown,
      onSpellGroupCooldown = onSpellGroupCooldown,
      onGameEnd            = onGameEnd,
    })
    rawset(Spells, "_cdConnected", true)
  end

  -- remaining ms for an expiry entry, or -1 if absent/elapsed (also prunes).
  local function remaining(tbl, key)
    local expiry = tbl[key]
    if not expiry then return -1 end
    local left = expiry - now()
    if left <= 0 then
      tbl[key] = nil
      return -1
    end
    return left
  end

  -- groupExpiry is keyed by the RAW server SpellGroup_t id (onSpellGroupCooldown),
  -- but a script passes an Enums.SpellGroups value whose 9/10 (Beams/Bursts) are
  -- inverted vs this server. Translate ZB -> server id before indexing. Lazy
  -- (api.Enums may build after this module) + guarded so a missing translator
  -- degrades to identity instead of erroring.
  local function toEngineGroup(groupId)
    local t = api.Enums and api.Enums.translate
    if t and type(t.spellGroupToEngine) == "function" then
      return t.spellGroupToEngine(groupId)
    end
    return groupId
  end

  -- ---------------------------------------------------------------------------
  -- Lookup (table-returning; mirrors the engine names used by the Zerobot dialect)
  -- ---------------------------------------------------------------------------

  -- Spells.getSpellByWords(words) -> spellTable | nil
  -- Resolve a spell by its incantation ("exori"). Guards the non-string case the
  -- engine function would crash on, and strips the engine's extra return values
  -- (it returns spell, profile, key) down to just the spell table.
  function Spells.getSpellByWords(words)
    if type(words) ~= "string" or words == "" then return nil end
    if not (EngineSpells and EngineSpells.getSpellByWords) then return dbMissing() end
    local ok, spell = pcall(EngineSpells.getSpellByWords, words)
    if ok and type(spell) == "table" then return spell end
    return nil
  end

  -- Spells.getSpellByName(name) -> spellTable | nil
  -- Resolve a spell by display name ("Berserk"). The engine's getSpellByName
  -- indexes SpellInfo[profile][name] and CRASHES when the name is unknown
  -- (profile == nil), so we resolve the profile first and only call through when
  -- it exists.
  function Spells.getSpellByName(name)
    if type(name) ~= "string" or name == "" then return nil end
    if not (EngineSpells and EngineSpells.getSpellByName) then return dbMissing() end
    -- gate on a known profile to avoid the engine's SpellInfo[nil] crash.
    if EngineSpells.getSpellProfileByName and
       EngineSpells.getSpellProfileByName(name) == nil then
      return nil
    end
    local ok, spell = pcall(EngineSpells.getSpellByName, name)
    if ok and type(spell) == "table" then return spell end
    return nil
  end

  -- ---------------------------------------------------------------------------
  -- Lookup (ZB-spec; numeric icon/client id or -1)
  -- ---------------------------------------------------------------------------

  -- Spells.getIdByWords(words) -> number (spell.id, or -1 if not found)
  function Spells.getIdByWords(words)
    local spell = Spells.getSpellByWords(words)
    if spell and type(spell.id) == "number" then return spell.id end
    return -1
  end

  -- Spells.getIdByName(name) -> number (spell.id, or -1 if not found)
  function Spells.getIdByName(name)
    local spell = Spells.getSpellByName(name)
    if spell and type(spell.id) == "number" then return spell.id end
    return -1
  end

  -- ---------------------------------------------------------------------------
  -- Cooldown queries
  -- ---------------------------------------------------------------------------

  -- Spells.getLeftCooldownTime(id) -> ms remaining on that spell, or -1.
  -- `id` is the spell's icon/client id (the value getIdBy*/spell.id returns and
  -- the value the server reports in onSpellCooldown).
  function Spells.getLeftCooldownTime(id)
    if type(id) ~= "number" then return -1 end
    return remaining(spellExpiry, id)
  end

  -- Spells.isInCooldown(id) -> bool
  function Spells.isInCooldown(id)
    return Spells.getLeftCooldownTime(id) > 0
  end

  -- Spells.getLeftGroupCooldownTime(groupId) -> ms remaining for that spell
  -- group, or -1. groupId is an Enums.SpellGroups value; it is translated to the
  -- server SpellGroup_t id the ledger is keyed by (ZB inverts 9/10 vs this server).
  function Spells.getLeftGroupCooldownTime(groupId)
    if type(groupId) ~= "number" then return -1 end
    return remaining(groupExpiry, toEngineGroup(groupId))
  end

  -- Spells.groupIsInCooldown(groupId) -> bool
  function Spells.groupIsInCooldown(groupId)
    return Spells.getLeftGroupCooldownTime(groupId) > 0
  end

  return Spells
end
