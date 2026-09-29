ThingCategoryItem = 0
ThingCategoryCreature = 1
ThingCategoryEffect = 2
ThingCategoryMissile = 3
ThingInvalidCategory = 4
ThingLastCategory = ThingInvalidCategory

ThingAttrGround           = 0
ThingAttrGroundBorder     = 1
ThingAttrOnBottom         = 2
ThingAttrOnTop            = 3
ThingAttrContainer        = 4
ThingAttrStackable        = 5
ThingAttrForceUse         = 6
ThingAttrMultiUse         = 7
ThingAttrWritable         = 8
ThingAttrWritableOnce     = 9
ThingAttrFluidContainer   = 10
ThingAttrSplash           = 11
ThingAttrNotWalkable      = 12
ThingAttrNotMoveable      = 13
ThingAttrBlockProjectile  = 14
ThingAttrNotPathable      = 15
ThingAttrPickupable       = 16
ThingAttrHangable         = 17
ThingAttrHookSouth        = 18
ThingAttrHookEast         = 19
ThingAttrRotateable       = 20
ThingAttrLight            = 21
ThingAttrDontHide         = 22
ThingAttrTranslucent      = 23
ThingAttrDisplacement     = 24
ThingAttrElevation        = 25
ThingAttrLyingCorpse      = 26
ThingAttrAnimateAlways    = 27
ThingAttrMinimapColor     = 28
ThingAttrLensHelp         = 29
ThingAttrFullGround       = 30
ThingAttrLook             = 31
ThingAttrCloth            = 32
ThingAttrMarket           = 33
ThingAttrNoMoveAnimation  = 253 -- >= 1010, value = 16
ThingAttrChargeable       = 254 -- deprecated
ThingLastAttr             = 255

SpriteMaskRed = 1
SpriteMaskGreen = 2
SpriteMaskBlue = 3
SpriteMaskYellow = 4

-- Static creature files are keyed by a legacy looktype-derived value, not by an
-- authoritative server Bestiary raceId. Keep server data separate so it always
-- wins and can be registered in O(1) without rebuilding the static list.
local staticRaceDataCache = nil
local authoritativeRaceDataCache = {}

local function normalizeOutfit(outfit)
  if type(outfit) ~= 'table' then
    return nil
  end

  local lookType = tonumber(outfit.type or outfit.lookType or outfit[2]) or 0
  local auxType = tonumber(outfit.auxType or outfit.typeEx or outfit.lookTypeEx or outfit[3]) or 0

  if lookType <= 0 and auxType <= 0 then
    return nil
  end

  return {
    type = lookType,
    auxType = auxType,
    head = tonumber(outfit.head or outfit.lookHead or outfit[4]) or 0,
    body = tonumber(outfit.body or outfit.lookBody or outfit[5]) or 0,
    legs = tonumber(outfit.legs or outfit.lookLegs or outfit[6]) or 0,
    feet = tonumber(outfit.feet or outfit.lookFeet or outfit[7]) or 0,
    addons = tonumber(outfit.addons or outfit.lookAddons or outfit[8]) or 0,
    mount = tonumber(outfit.mount or outfit.lookMount) or 0
  }
end

local function normalizeRaceData(raceId, creature)
  if type(creature) ~= 'table' then
    return nil
  end

  local name = creature.name or creature[1] or ('Creature ' .. tostring(raceId))
  local outfit = normalizeOutfit(creature.outfit or creature)

  return {
    raceId = raceId,
    name = tostring(name),
    outfit = outfit
  }
end

local function rebuildRaceDataCache()
  staticRaceDataCache = {}

  if not g_things or not g_things.getMonsterList then
    return
  end

  local monsterList = g_things.getMonsterList() or {}
  for raceId, creature in pairs(monsterList) do
    local numericRaceId = tonumber(raceId) or 0
    if numericRaceId > 0 then
      local raceData = normalizeRaceData(numericRaceId, creature)
      if raceData then
        staticRaceDataCache[numericRaceId] = raceData
      end
    end
  end

  if not next(staticRaceDataCache) then
    staticRaceDataCache = nil
  end
end

if g_things and not g_things.getRaceData then
  function g_things.clearRaceDataCache()
    staticRaceDataCache = nil
    authoritativeRaceDataCache = {}
  end

  function g_things.registerRaceData(raceId, name, outfit)
    raceId = tonumber(raceId) or 0
    if raceId <= 0 then
      return nil
    end

    local raceData = {
      raceId = raceId,
      name = tostring(name or ('Creature ' .. tostring(raceId))),
      outfit = normalizeOutfit(outfit or {})
    }
    authoritativeRaceDataCache[raceId] = raceData
    return raceData
  end

  function g_things.getRaceData(raceId)
    raceId = tonumber(raceId) or 0
    if raceId <= 0 then
      return nil
    end

    local authoritative = authoritativeRaceDataCache[raceId]
    if authoritative then
      return authoritative
    end

    if not staticRaceDataCache then
      rebuildRaceDataCache()
    end

    local raceData = staticRaceDataCache and staticRaceDataCache[raceId] or nil
    if raceData then
      return raceData
    end

    return {
      raceId = raceId,
      name = 'Creature ' .. tostring(raceId),
      outfit = nil
    }
  end
end

if g_things and not g_things.registerRaceDataFromPacket then
  function g_things.registerRaceDataFromPacket(entry)
    if type(entry) ~= 'table' or not g_things.registerRaceData then
      return nil
    end

    local raceId = tonumber(entry.raceId) or 0
    if raceId <= 0 then
      return nil
    end

    return g_things.registerRaceData(raceId, entry.name, {
      type = tonumber(entry.lookType) or 0,
      head = tonumber(entry.lookHead) or 0,
      body = tonumber(entry.lookBody) or 0,
      legs = tonumber(entry.lookLegs) or 0,
      feet = tonumber(entry.lookFeet) or 0,
      addons = tonumber(entry.lookAddons) or 0
    })
  end
end
