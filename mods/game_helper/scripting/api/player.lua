--[[============================================================================
  scripting/api/player.lua — Zerobot-compatible `Player` namespace.
  ============================================================================

  Builder module (see scripting/scripting.lua CONTRACT). Returns
      function(api, ctx) ... return Player end
  and is injected into every sandboxed script as the global `Player`.

  `Player` is a PLAIN NAMESPACE TABLE (NOT a class) of static functions, exactly
  like Zerobot's `Player`. Every function operates on the LocalPlayer obtained
  from `g_game.getLocalPlayer()` (helper `lp()` below). When the player is not
  in-game `lp()` is nil and the getters follow Zerobot semantics:
    * number getters  -> 0      (ZB returns last-known/0 when offline)
    * string getters  -> nil    (e.g. getName)
    * table getters   -> nil    (e.g. getInventorySlot/getSkills)

  RULES (CONTRACT):
    * No globals. Only locals + the returned `Player` table.
    * Cross-namespace refs are LAZY: `api.Enums.translate.X(...)` INSIDE a
      function, never `local Enums = api.Enums` at module top.
    * Runs OUTSIDE the sandbox: direct access to g_game/g_map is allowed.
    * Return-value semantics preserved (true/false/nil distinct where it matters).
    * Use `api.Enums.translate.*` for every typed value (vocation/state/...) — no
      hardcoded enum numbers.

  ENGINE MAPPING (verified against src/client/luafunctions_client.cpp 877-964,
  modules/gamelib/player.lua, modules/gamelib/const.lua):
    LocalPlayer extends Player extends Creature; it has rich native getters
    (getHealth/getMana/getLevel/getSkillLevel/getSpecialSkill/getManaShield/
    getResourceValue/getStates/getInventoryItem/getVocation/...). A handful of
    ZB getters have no Fase-1 data source (server-pushed payloads not stored on
    LocalPlayer yet): those are implemented as wrappers returning the best value
    available + a "parcial Fase 2" comment.
============================================================================]]

return function(api, ctx)
  local Player = {}

  -- The LocalPlayer object, or nil when not in-game. Every getter funnels
  -- through this so "offline" is a single, consistent check.
  local function lp()
    return g_game.getLocalPlayer()
  end

  --==========================================================================
  -- Identity / vitals (all native on LocalPlayer)
  --==========================================================================

  -- Player's unique creature id (0 when not in-game), matching ZB.
  function Player.getId()
    local p = lp()
    if not p then return 0 end
    return p:getId() or 0
  end

  -- Player's name, or nil when not in-game (ZB returns nil offline).
  function Player.getName()
    local p = lp()
    if not p then return nil end
    return p:getName()
  end

  function Player.getHealth()
    local p = lp()
    if not p then return 0 end
    return p:getHealth() or 0
  end

  function Player.getMana()
    local p = lp()
    if not p then return 0 end
    return p:getMana() or 0
  end

  -- Current HP as a 0-100 percent. The engine has no native getHealthPercent on
  -- LocalPlayer that is distinct from the Creature one; derive from current/max
  -- so it is always accurate for the local player.
  function Player.getHealthPercent()
    local p = lp()
    if not p then return 0 end
    local max = p:getMaxHealth() or 0
    if max <= 0 then return 0 end
    return math.floor((p:getHealth() or 0) * 100 / max)
  end

  function Player.getManaPercent()
    local p = lp()
    if not p then return 0 end
    local max = p:getMaxMana() or 0
    if max <= 0 then return 0 end
    return math.floor((p:getMana() or 0) * 100 / max)
  end

  -- Magic shield (utamo vita) current/max — native getManaShield/getMaxManaShield
  -- (memory: vocation-ids-and-manashield-split). The Lua Player:getMagicShield
  -- shim also prefers these, so calling the native getters directly is correct.
  function Player.getMagicShield()
    local p = lp()
    if not p then return 0 end
    return p:getManaShield() or 0
  end

  function Player.getMaxMagicShield()
    local p = lp()
    if not p then return 0 end
    return p:getMaxManaShield() or 0
  end

  -- ZB "capacity" = the spendable/free capacity (getFreeCapacity), not total.
  function Player.getCapacity()
    local p = lp()
    if not p then return 0 end
    return p:getFreeCapacity() or 0
  end

  function Player.getSoulPoints()
    local p = lp()
    if not p then return 0 end
    return p:getSoul() or 0
  end

  -- Current stamina in minutes (engine getStamina returns minutes).
  function Player.getStamina()
    local p = lp()
    if not p then return 0 end
    return p:getStamina() or 0
  end

  --==========================================================================
  -- Level / experience
  --==========================================================================

  function Player.getLevel()
    local p = lp()
    if not p then return 0 end
    return p:getLevel() or 0
  end

  -- The native getLevelPercent already returns a 0-100 value (the C++ side
  -- divides the server's percent*100 — memory: level-percent-and-xphour-scale),
  -- so no extra scaling here.
  function Player.getLevelPercent()
    local p = lp()
    if not p then return 0 end
    return p:getLevelPercent() or 0
  end

  function Player.getExperience()
    local p = lp()
    if not p then return 0 end
    return p:getExperience() or 0
  end

  -- Remaining XP boost time in seconds. The engine stores the STORE xp-boost
  -- timer (getStoreExpBoostTime); that is the closest analogue to ZB's value.
  function Player.getXpBoostTime()
    local p = lp()
    if not p then return 0 end
    if p.getStoreExpBoostTime then
      return p:getStoreExpBoostTime() or 0
    end
    return 0
  end

  --==========================================================================
  -- Skills
  --==========================================================================

  -- ZB shape (exact field set required by ported scripts):
  --   lifeLeechDamage, lifeLeechChance, manaLeechDamage, manaLeechChance,
  --   criticalChance, criticalDamage,
  --   magic, magicPercent, fist, fistPercent, axe, axePercent, club, clubPercent,
  --   sword, swordPercent, distance, distancePercent, shield, shieldPercent,
  --   fishing, fishingPercent.
  -- Backed by getSkillLevel/getSkillLevelPercent (Fist=0..Fishing=6),
  -- getSpecialSkill (CriticalChance=7..ManaLeechAmount=12) and getMagicLevel /
  -- getMagicLevelPercent. Skill enum: modules/gamelib/const.lua `Skill`.
  function Player.getSkills()
    local p = lp()
    if not p then return nil end

    -- Skill enum indices (gamelib/const.lua). Hardcoded here only because they
    -- are engine skill-channel indices, NOT a ZB<->engine enum (no translator
    -- exists for them); they are the arguments getSkillLevel/getSpecialSkill take.
    local SKILL_FIST, SKILL_CLUB, SKILL_SWORD, SKILL_AXE = 0, 1, 2, 3
    local SKILL_DISTANCE, SKILL_SHIELDING, SKILL_FISHING = 4, 5, 6
    local SKILL_CRIT_CHANCE, SKILL_CRIT_DAMAGE          = 7, 8
    local SKILL_LIFELEECH_CHANCE, SKILL_LIFELEECH_AMOUNT = 9, 10
    local SKILL_MANALEECH_CHANCE, SKILL_MANALEECH_AMOUNT = 11, 12

    local function lvl(s)  return p:getSkillLevel(s) or 0 end
    local function pct(s)  return p:getSkillLevelPercent(s) or 0 end
    local function spec(s) return p:getSpecialSkill(s) or 0 end

    return {
      -- leech / crit (special skills)
      lifeLeechChance  = spec(SKILL_LIFELEECH_CHANCE),
      lifeLeechDamage  = spec(SKILL_LIFELEECH_AMOUNT),
      manaLeechChance  = spec(SKILL_MANALEECH_CHANCE),
      manaLeechDamage  = spec(SKILL_MANALEECH_AMOUNT),
      criticalChance   = spec(SKILL_CRIT_CHANCE),
      criticalDamage   = spec(SKILL_CRIT_DAMAGE),
      -- magic (own getters, not part of the skill channel set)
      magic            = p:getMagicLevel() or 0,
      magicPercent     = p:getMagicLevelPercent() or 0,
      -- weapon / utility skills
      fist             = lvl(SKILL_FIST),     fistPercent     = pct(SKILL_FIST),
      axe              = lvl(SKILL_AXE),      axePercent      = pct(SKILL_AXE),
      club             = lvl(SKILL_CLUB),     clubPercent     = pct(SKILL_CLUB),
      sword            = lvl(SKILL_SWORD),    swordPercent    = pct(SKILL_SWORD),
      distance         = lvl(SKILL_DISTANCE), distancePercent = pct(SKILL_DISTANCE),
      shield           = lvl(SKILL_SHIELDING),shieldPercent   = pct(SKILL_SHIELDING),
      fishing          = lvl(SKILL_FISHING),  fishingPercent  = pct(SKILL_FISHING),
    }
  end

  --==========================================================================
  -- Targeting / following
  --==========================================================================

  -- Id of the currently-attacked creature (0 when none) — matches ZB which
  -- returns a number id, not the Creature object.
  function Player.getTargetId()
    local c = g_game.getAttackingCreature()
    if not c then return 0 end
    return c:getId() or 0
  end

  function Player.getFollowId()
    local c = g_game.getFollowingCreature()
    if not c then return 0 end
    return c:getId() or 0
  end

  --==========================================================================
  -- Inventory / state / containers
  --==========================================================================

  -- Item in an inventory slot (Enums.InventorySlot). Returns
  -- {id,count,tier,holdingCount} or nil when the slot is empty / not in-game.
  -- holdingCount mirrors the displayed count/subtype (the engine has no separate
  -- "holding" count on Item, so getCountOrSubType is the best source).
  function Player.getInventorySlot(slot)
    local p = lp()
    if not p then return nil end
    local engSlot = api.Enums.translate.inventorySlotToEngine(slot)
    if not engSlot then return nil end
    local item = p:getInventoryItem(engSlot)
    if not item then return nil end
    local count = item:getCountOrSubType() or item:getCount() or 1
    return {
      id           = item:getId() or 0,
      count        = count,
      tier         = item:getTier() or 0,
      holdingCount = count,
    }
  end

  -- Whether a given ZB state (Enums.States index) is active. Returns nil when not
  -- in-game (ZB returns nil if there is no such state to read); otherwise a bool.
  function Player.getState(index)
    local p = lp()
    if not p then return nil end
    local states = p:getStates()
    if not states then return nil end
    return api.Enums.translate.hasState(states, index)
  end

  -- All open container indexes (keys of g_game.getContainers()), or nil if none.
  function Player.getContainers()
    local conts = g_game.getContainers()
    if not conts then return nil end
    local ids = {}
    for idx in pairs(conts) do
      ids[#ids + 1] = idx
    end
    if #ids == 0 then return nil end
    return ids
  end

  --==========================================================================
  -- Resources (forge dust / gold)
  --==========================================================================

  -- Current exalted (forge) dust. Resource id 70 = ResourceForgeDust
  -- (gamelib/const.lua; helper.lua:16935 reads getResourceValue(70)).
  function Player.getDusts()
    local p = lp()
    if not p then return 0 end
    return p:getResourceValue(70) or 0
  end

  -- Maximum dust ("dust limit"). PARCIAL FASE 2: the dust cap is NOT a resource
  -- value on LocalPlayer; the server pushes it via the forge config packet, which
  -- is not stored here in Fase 1. Returns 0 until a forge-data source exists.
  function Player.getDustsMaximum()
    return 0 -- parcial Fase 2 (forge config packet not stored on LocalPlayer)
  end

  -- Total gold = bank + carried. ResourceBank=0, ResourceInventory=1
  -- (gamelib/const.lua; util.lua:554 / npctrade.lua use exactly this sum).
  function Player.getTotalGoldBalance()
    local p = lp()
    if not p then return 0 end
    return (p:getResourceValue(0) or 0) + (p:getResourceValue(1) or 0)
  end

  --==========================================================================
  -- Party (native g_game.party* primitives)
  --==========================================================================

  -- Accept a pending party invite from targetId.
  function Player.joinParty(targetId)
    g_game.partyJoin(targetId)
  end

  -- Invite a player (by creature id) to your party.
  function Player.inviteParty(targetId)
    g_game.partyInvite(targetId)
  end

  -- Toggle shared experience in the party.
  function Player.enableSharedExpParty(enabled)
    g_game.partyShareExperience(enabled and true or false)
  end

  -- Pass party leadership to another member (by creature id).
  function Player.passLeadershipParty(targetId)
    g_game.partyPassLeadership(targetId)
  end

  -- Leave the current party.
  function Player.leaveParty()
    g_game.partyLeave()
  end

  --==========================================================================
  -- Premium / blessings / monk / serene
  --==========================================================================

  function Player.isPremium()
    local p = lp()
    if not p then return false end
    return p:isPremium() and true or false
  end

  -- Whether basic data (premium/etc) was received from the server.
  -- PARCIAL FASE 2: the engine has no "received basic data" flag; isPremium()
  -- is meaningful once the server sends AddPlayerStats. Best-effort: report true
  -- when in-game (we have a LocalPlayer), false otherwise.
  function Player.hasReceivedBasicData()
    return lp() ~= nil -- parcial Fase 2 (no explicit basic-data gate in engine)
  end

  -- Blessing state as an Enums.BlessingState value
  -- (UNDEFINED=-1, NONE=0, NORMAL=1, FULL=2). Derived from the engine's
  -- getBlessStatus() glow tier (1 = <5 blesses/disabled, 2 = 5-6/normal,
  -- 3 = 7+/green). Maps 3->FULL, 2->NORMAL, else NONE; UNDEFINED when offline.
  function Player.getBlessingState()
    local p = lp()
    local B = api.Enums.BlessingState
    if not p then return B.UNDEFINED end
    local status = (p.getBlessStatus and p:getBlessStatus()) or 0
    if status >= 3 then return B.FULL end
    if status == 2 then return B.NORMAL end
    return B.NONE
  end

  -- Serene state (monk). Backed by the Lua Player:isSerenity() shim
  -- (gamelib/player.lua) which is fed by the server; defaults to false.
  function Player.isSerene()
    local p = lp()
    if not p then return false end
    if p.isSerenity then return p:isSerenity() and true or false end
    return false
  end

  -- Current harmony (monk). Backed by the Lua Player:getHarmony() shim
  -- (gamelib/player.lua), server-fed; PARCIAL FASE 2 until the harmony packet is
  -- wired (returns 0 by default).
  function Player.getHarmony()
    local p = lp()
    if not p then return 0 end
    if p.getHarmony then return p:getHarmony() or 0 end
    return 0 -- parcial Fase 2
  end

  -- Enabled monk passive type (Enums.MonkPassiveType). Native getMonkPassive().
  function Player.getMonkPassiveType()
    local p = lp()
    if not p then return 0 end
    if p.getMonkPassive then return p:getMonkPassive() or 0 end
    return 0
  end

  --==========================================================================
  -- Misc state
  --==========================================================================

  -- Whether the player is hungry. PARCIAL FASE 2: this engine models hunger via
  -- the states-list/icon system (PlayerStates.Hungry = -1 is a sentinel, NOT a
  -- bitmask bit), so it cannot be tested through getStates(). Best-effort: scan
  -- getStatesList() for the hungry sentinel id if present, else false.
  function Player.isHungry()
    local p = lp()
    if not p then return false end
    if p.getStatesList then
      local list = p:getStatesList()
      if type(list) == "table" then
        for _, s in pairs(list) do
          -- PlayerStates.Hungry == -1 (gamelib/player.lua)
          if s == -1 then return true end
        end
      end
    end
    return false -- parcial Fase 2 (hunger not exposed as a queryable bit)
  end

  --==========================================================================
  -- Server-pushed data NOT stored on LocalPlayer in Fase 1.
  -- Each is implemented as the documented wrapper but returns the best value
  -- available (empty/zero) so ported scripts don't crash; see comments.
  --==========================================================================

  -- Unjustified frag progress. PARCIAL FASE 2: delivered by onUnjustifiedPoints
  -- (memory: unjustified-points-redesign) and not cached on LocalPlayer here.
  -- Returns the full ZB shape with zeros so field access is always safe.
  function Player.getUnjustifiedData()
    return {
      dayProgress   = 0, dayLeft   = 0,
      weekProgress  = 0, weekLeft  = 0,
      monthProgress = 0, monthLeft = 0,
      skullDuration = 0,
    } -- parcial Fase 2 (no cached unjustified data on LocalPlayer)
  end

  -- Hunting-task prices. PARCIAL FASE 2: hunting tasks were removed/disabled on
  -- the server (memory: hunting-tasks-removed-from-client); no price data flows.
  function Player.getHuntingTaskPrices()
    return {
      rerollPrice        = 0,
      cancelPrice        = 0,
      selectionListPrice = 0,
      rewardRerollPrice  = 0,
    } -- parcial Fase 2 (hunting tasks disabled server-side)
  end

  -- Current hunting points. PARCIAL FASE 2: see above — no source.
  function Player.getHuntingPoints()
    return 0 -- parcial Fase 2 (hunting tasks disabled server-side)
  end

  -- Current prey wildcards. PARCIAL FASE 2: prey wildcard count arrives in the
  -- prey 0xE9/basic-data packets (modules/game_prey) and is not stored on
  -- LocalPlayer; there is no getResourceValue slot for it. Returns 0.
  function Player.getPreyWildcards()
    return 0 -- parcial Fase 2 (wildcard count not stored on LocalPlayer)
  end

  return Player
end
