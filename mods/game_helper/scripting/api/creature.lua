--[[============================================================================
  scripting/api/creature.lua — Zerobot-compatible `Creature` class.
  ============================================================================

  Builder module (see scripting/scripting.lua CONTRACT). Returns
      function(api, ctx) ... return Creature end
  and is injected into every sandboxed script as the global `Creature`.

  IMPORTANT: this is the SANDBOX's `Creature` (the ZB-dialect handle), a plain
  Lua TABLE built here. It is NOT the engine's C++ `Creature` class — we MUST NOT
  touch the real global `Creature` (doing so would break the whole helper). The
  builder only ever returns a fresh local table.

  `Creature` is a CLASS with a metatable and `__call`, so both spellings work:
      local c = Creature(cid)        -- via __call
      local c = Creature.new(cid)    -- explicit constructor
  An instance stores only `self.cid` (the creature id). Every method RE-RESOLVES
  `g_map.getCreatureById(self.cid)` on each call (NO caching), exactly like ZB:
  the handle stays valid only while the creature exists, and methods return nil
  once it is gone. Constructing an instance never validates existence.

  RULES (CONTRACT):
    * No globals. Only locals + the returned `Creature` table.
    * Cross-namespace refs are LAZY: `api.Enums.translate.X(...)` INSIDE methods.
    * Runs OUTSIDE the sandbox: direct access to g_map is allowed.
    * Typed values go through `api.Enums.translate.*` (creatureType/skull/emblem/
      partyIcon/vocation/direction) — no hardcoded enum numbers.

  ENGINE MAPPING (verified against src/client/luafunctions_client.cpp 606-687,
  modules/gamelib/creature.lua):
    g_map.getCreatureById(id) -> Creature (C++). Methods used: getType/getName/
    getHealthPercent/getEmblem/getShield/getVocation/getDirection/getPosition
    (via Thing)/getSpeed/getOutfit/getSkull/getIcon/hasCreatureIcon. getIcons is a
    stopgap that probes hasCreatureIcon(id, category) across both icon categories
    (the full getCreatureIcons() list is not yet bound, so per-icon count is
    unavailable — see Fase 3 in PLANO_IMPLEMENTACAO_SCRIPTING.md).
============================================================================]]

return function(api, ctx)
  local Creature = {}
  Creature.__index = Creature

  -- Resolve the live engine creature for this handle, or nil if it no longer
  -- exists. Centralised so every method shares the same "gone -> nil" behaviour.
  local function resolve(self)
    if not self or not self.cid then return nil end
    return g_map.getCreatureById(self.cid)
  end

  --==========================================================================
  -- Construction
  --==========================================================================

  -- Create a handle wrapping a creature id. Does NOT validate existence (ZB
  -- parity); methods return nil while the cid has no live creature.
  function Creature.new(creatureId)
    return setmetatable({ cid = creatureId }, Creature)
  end

  -- `Creature(cid)` sugar for `Creature.new(cid)`.
  setmetatable(Creature, {
    __call = function(_, creatureId)
      return Creature.new(creatureId)
    end,
  })

  --==========================================================================
  -- Methods (instance) — `creature:method()`
  --==========================================================================

  -- The creature id (local; never resolves the engine — matches ZB).
  function Creature:getId()
    return self.cid
  end

  -- Creature type as an Enums.CreatureTypes value, or nil if gone.
  function Creature:getType()
    local c = resolve(self)
    if not c then return nil end
    return api.Enums.translate.creatureTypeFromEngine(c:getType())
  end

  -- ZB-style type predicates. The engine's Thing:isPlayer/isMonster/isNpc bindings
  -- (luafunctions_client.cpp) are the source of truth; they return false (never nil)
  -- for a live creature. A gone creature returns false. Shorthands for
  -- getType() == Enums.CreatureTypes.PLAYER/MONSTER/NPC.
  function Creature:isPlayer()
    local c = resolve(self)
    return c ~= nil and c:isPlayer() == true
  end

  function Creature:isMonster()
    local c = resolve(self)
    return c ~= nil and c:isMonster() == true
  end

  function Creature:isNpc()
    local c = resolve(self)
    return c ~= nil and c:isNpc() == true
  end

  -- Name, or nil if the creature no longer exists.
  function Creature:getName()
    local c = resolve(self)
    if not c then return nil end
    return c:getName()
  end

  -- Health as a 0-100 percent, or nil if gone.
  function Creature:getHealthPercent()
    local c = resolve(self)
    if not c then return nil end
    return c:getHealthPercent()
  end

  -- Guild emblem as an Enums.GuildEmblem value, or nil if gone.
  function Creature:getGuildEmblem()
    local c = resolve(self)
    if not c then return nil end
    return api.Enums.translate.guildEmblemFromEngine(c:getEmblem())
  end

  -- Party icon (party shield) as an Enums.PartyIcons value, or nil if gone.
  function Creature:getPartyIcon()
    local c = resolve(self)
    if not c then return nil end
    return api.Enums.translate.partyIconFromEngine(c:getShield())
  end

  -- Vocation as an Enums.Vocations value. The client now stores the vocation the
  -- server sends for visible PLAYERS (on creature-add and the 0x8B creature-data
  -- update), so this resolves for ANY player it has received -- not only the local
  -- one. Monsters/NPCs carry no vocation (0 -> None). Returns nil if the creature is
  -- gone. The translator collapses promoted clientids (11..15) to the base value.
  -- (The c.getVocation guard keeps an OLD client binary from crashing on a new script.)
  function Creature:getVocation()
    local c = resolve(self)
    if not c then return nil end
    if not c.getVocation then return nil end
    return api.Enums.translate.vocationFromEngine(c:getVocation())
  end

  -- Facing direction as an Enums.Directions value, or nil if gone. Uses the
  -- direction translator (diagonals are remapped between engine and ZB).
  function Creature:getDirection()
    local c = resolve(self)
    if not c then return nil end
    return api.Enums.translate.directionFromEngine(c:getDirection())
  end

  -- Position as a {x,y,z} table, or nil if gone.
  function Creature:getPosition()
    local c = resolve(self)
    if not c then return nil end
    local pos = c:getPosition()
    if not pos then return nil end
    return { x = pos.x, y = pos.y, z = pos.z }
  end

  -- Movement speed, or nil if gone.
  function Creature:getSpeed()
    local c = resolve(self)
    if not c then return nil end
    return c:getSpeed()
  end

  -- Outfit in the ZB shape, or nil if gone:
  --   {type,typeEx,head,body,legs,feet,addons,mountId,mountHead,mountLegs,mountFeet}
  -- The engine outfit is {type,auxType,addons,head,body,legs,feet,mount,mountHead,
  -- mountBody,mountLegs,mountFeet,...} (luavaluecasts_client.cpp push_luavalue(Outfit)).
  -- Map: typeEx<-auxType, mountId<-mount. The dyed mount colours are only present
  -- when the GamePlayerMounts feature is on (else the fields are absent -> 0).
  function Creature:getOutfit()
    local c = resolve(self)
    if not c then return nil end
    local o = c:getOutfit()
    if not o then return nil end
    return {
      type      = o.type      or 0,
      typeEx    = o.auxType   or 0,
      head      = o.head      or 0,
      body      = o.body      or 0,
      legs      = o.legs      or 0,
      feet      = o.feet      or 0,
      addons    = o.addons    or 0,
      mountId   = o.mount     or 0,
      mountHead = o.mountHead or 0,
      mountLegs = o.mountLegs or 0,
      mountFeet = o.mountFeet or 0,
    }
  end

  -- Skull type as an Enums.Skulls value, or nil if gone.
  function Creature:getSkull()
    local c = resolve(self)
    if not c then return nil end
    return api.Enums.translate.skullFromEngine(c:getSkull())
  end

  -- Single creature icon (Enums.CreatureIcons), or nil if gone.
  function Creature:getIcon()
    local c = resolve(self)
    if not c then return nil end
    return c:getIcon()
  end

  -- All creature icons as a list of {id, category, count} records, or nil if gone.
  -- Delegates to the gamelib Creature:getIcons(), which prefers the C++
  -- getCreatureIcons() list (real per-icon count, e.g. Fiendish level) and falls
  -- back to a hasCreatureIcon presence probe on older binaries. We just re-shape its
  -- {id, category, modification, count} records to the ZB {id, category, count}.
  function Creature:getIcons()
    local c = resolve(self)
    if not c then return nil end
    -- Real engine binding: Creature::getCreatureIcons() (luafunctions_client.cpp)
    -- returns a vector of {iconId, category, count} tuples (1-indexed in Lua). The
    -- old code called c:getIcons() (no such binding) so it always returned {}, and the
    -- earlier stopgap could only probe presence with count=0. This reads the real
    -- per-icon count now.
    if not c.getCreatureIcons then return {} end
    local icons = {}
    for _, icon in ipairs(c:getCreatureIcons()) do
      icons[#icons + 1] = { id = icon[1], category = icon[2], count = icon[3] or 0 }
    end
    return icons
  end

  return Creature
end
