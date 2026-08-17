if not LoadedPlayer then
  LoadedPlayer = {
    playerId = 0,
    playerName = "",
    playerVocation = 0,
  }
  LoadedPlayer.__index = LoadedPlayer
end

function LoadedPlayer:getId() return self.playerId end
function LoadedPlayer:getName() return self.playerName end
function LoadedPlayer:getVocation() return self.playerVocation end
function LoadedPlayer:isLoaded()
  return self.playerId > 0
end

function LoadedPlayer:setId(playerId)
  self.playerId = playerId
end

function LoadedPlayer:setName(playerName)
  self.playerName = playerName
end

function LoadedPlayer:setVocation(vocationId)
  self.playerVocation = vocationId
end

SUPPLY_STASH_ACTION_STOW_ITEM = 0
SUPPLY_STASH_ACTION_STOW_CONTAINER = 1
SUPPLY_STASH_ACTION_STOW_STACK = 2
SUPPLY_STASH_ACTION_WITHDRAW = 3

local PlayerInfos = {}
local PlayerHarmony = setmetatable({}, { __mode = 'k' })

local function normalizeHarmony(value)
  value = tonumber(value) or 0
  if value ~= value or value == math.huge or value == -math.huge then
    return 0
  end
  return math.max(0, math.min(5, math.floor(value)))
end

function LocalPlayer:hasCondition(condition) return bit.band(self:getStates(), condition) > 0 end

function LocalPlayer:isPoisioned() return self:hasCondition(PlayerStates.Poison) end
function LocalPlayer:isBurning() return self:hasCondition(PlayerStates.Burn) end
function LocalPlayer:isEnergized() return self:hasCondition(PlayerStates.Energy) end
function LocalPlayer:isDrunk() return self:hasCondition(PlayerStates.Drunk) end
function LocalPlayer:hasManaShield() return self:hasCondition(PlayerStates.ManaShield) or self:hasCondition(PlayerStates.NewMagicShield) end
function LocalPlayer:useMagicShield() return self:hasManaShield() end
function LocalPlayer:getMagicShield() return self:getMana() end
function LocalPlayer:getMaxMagicShield() return self:getMaxMana() end
function LocalPlayer:setHarmony(value)
  value = normalizeHarmony(value)
  PlayerHarmony[self] = value
  return value
end
function LocalPlayer:getHarmony() return PlayerHarmony[self] or 0 end
function LocalPlayer:clearHarmony()
  PlayerHarmony[self] = nil
  return 0
end
function LocalPlayer:isSerenity() return false end
function LocalPlayer:isParalyzed() return self:hasCondition(PlayerStates.Paralyze) end
function LocalPlayer:hasHaste() return self:hasCondition(PlayerStates.Haste) end
function LocalPlayer:hasSwords() return self:hasCondition(PlayerStates.Swords) end
function LocalPlayer:isInFight() return self:hasCondition(PlayerStates.Swords) end
function LocalPlayer:canLogout() return not self:hasCondition(PlayerStates.Swords) end
function LocalPlayer:isDrowning() return self:hasCondition(PlayerStates.Drowning) end
function LocalPlayer:isFreezing() return self:hasCondition(PlayerStates.Freezing) end
function LocalPlayer:isDazzled() return self:hasCondition(PlayerStates.Dazzled) end
function LocalPlayer:isCursed() return self:hasCondition(PlayerStates.Cursed) end
function LocalPlayer:hasPartyBuff() return self:hasCondition(PlayerStates.PartyBuff) end
function LocalPlayer:hasPzLock() return self:hasCondition(PlayerStates.PzBlock) end
function LocalPlayer:hasPzBlock() return self:hasCondition(PlayerStates.PzBlock) end
function LocalPlayer:isPzLocked() return self:hasCondition(PlayerStates.PzBlock) end
function LocalPlayer:isPzBlocked() return self:hasCondition(PlayerStates.PzBlock) end
function LocalPlayer:isInProtectionZone() return self:hasCondition(PlayerStates.Pz) end
function LocalPlayer:hasPz() return self:hasCondition(PlayerStates.Pz) end
function LocalPlayer:isInPz() return self:hasCondition(PlayerStates.Pz) end
function LocalPlayer:isBleeding() return self:hasCondition(PlayerStates.Bleeding) end
function LocalPlayer:isHungry() return self:hasCondition(PlayerStates.Hungry) end
function LocalPlayer:isRooted() return self:hasCondition(PlayerStates.Rooted) end


function LocalPlayer:cap() return self:getCapacity() end
function LocalPlayer:freecap() return self:getFreeCapacity() end
function LocalPlayer:maxcap() return self:getTotalCapacity() end
function LocalPlayer:capmax() return self:getTotalCapacity() end
function LocalPlayer:lvl() return self:getLevel() end

isPoisioned = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.Poison) or false
end

isBurning = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.Burn) or false
end

isEnergized = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.Energy) or false
end

isDrunk = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.Drunk) or false
end

hasManaShield = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasManaShield() or false
end

isParalyzed = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.Paralyze) or false
end

hasHaste = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.Haste) or false
end

hasSwords = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.Swords) or false
end

isInFight = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.Swords) or false
end

canLogout = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.Swords) or false
end

isDrowning = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.Drowning) or false
end

isFreezing = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.Freezing) or false
end

isDazzled = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.Dazzled) or false
end

isCursed = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.Cursed) or false
end

hasPartyBuff = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.PartyBuff) or false
end

hasPzLock = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.PzBlock) or false
end

hasPzBlock = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.PzBlock) or false
end

isPzLocked = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.PzBlock) or false
end

isPzBlocked = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.PzBlock) or false
end

isInProtectionZone = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.Pz) or false
end

hasPz = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.Pz) or false
end

isInPz = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.Pz) or false
end

isBleeding = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.Bleeding) or false
end

isHungry = function()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:hasCondition(PlayerStates.Hungry) or false
end

function cap()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:getCapacity() or 0
end

function freecap()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:getFreeCapacity() or 0
end

function maxcap()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:getTotalCapacity() or 0
end

function capmax()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:getTotalCapacity() or 0
end

function lvl()
  local localPlayer = g_game.getLocalPlayer()
  return localPlayer and localPlayer:getLevel() or 0
end

function LocalPlayer:setResourceInfo(type, value)
  PlayerInfos[type] = value
  if self.setResourceValue then
    self:setResourceValue(type, value)
  end
end
function LocalPlayer:getResourceInfo(type)
  return PlayerInfos[type] or 0
end
