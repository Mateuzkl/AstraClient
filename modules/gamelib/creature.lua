-- @docclass Creature

-- @docconsts @{

SkullNone = 0
SkullYellow = 1
SkullGreen = 2
SkullWhite = 3
SkullRed = 4
SkullBlack = 5
SkullOrange = 6

ShieldNone = 0
ShieldWhiteYellow = 1
ShieldWhiteBlue = 2
ShieldBlue = 3
ShieldYellow = 4
ShieldBlueSharedExp = 5
ShieldYellowSharedExp = 6
ShieldBlueNoSharedExpBlink = 7
ShieldYellowNoSharedExpBlink = 8
ShieldBlueNoSharedExp = 9
ShieldYellowNoSharedExp = 10

EmblemNone = 0
EmblemGreen = 1
EmblemRed = 2
EmblemBlue = 3

NpcIconNone = 0
NpcIconChat = 1
NpcIconTrade = 2
NpcIconQuest = 3
NpcIconTradeQuest = 4
NpcIconHireling = 7

CreatureTypePlayer = 0
CreatureTypeMonster = 1
CreatureTypeNpc = 2
CreatureTypeSummonOwn = 3
CreatureTypeSummonOther = 4

-- @}

function getNextSkullId(skullId)
  if skullId == SkullRed or skullId == SkullBlack then
    return SkullBlack
  end
  return SkullRed
end

function getSkullImagePath(skullId)
  local path
  if skullId == SkullYellow then
    path = '/images/game/skulls/skull_yellow'
  elseif skullId == SkullGreen then
    path = '/images/game/skulls/skull_green'
  elseif skullId == SkullWhite then
    path = '/images/game/skulls/skull_white'
  elseif skullId == SkullRed then
    path = '/images/game/skulls/skull_red'
  elseif skullId == SkullBlack then
    path = '/images/game/skulls/skull_black'
  elseif skullId == SkullOrange then
    path = '/images/game/skulls/skull_orange'
  end
  return path
end

function getShieldImagePathAndBlink(shieldId)
  local path, blink
  if shieldId == ShieldWhiteYellow then
    path, blink = '/images/game/shields/shield_yellow_white', false
  elseif shieldId == ShieldWhiteBlue then
    path, blink = '/images/game/shields/shield_blue_white', false
  elseif shieldId == ShieldBlue then
    path, blink = '/images/game/shields/shield_blue', false
  elseif shieldId == ShieldYellow then
    path, blink = '/images/game/shields/shield_yellow', false
  elseif shieldId == ShieldBlueSharedExp then
    path, blink = '/images/game/shields/shield_blue_shared', false
  elseif shieldId == ShieldYellowSharedExp then
    path, blink = '/images/game/shields/shield_yellow_shared', false
  elseif shieldId == ShieldBlueNoSharedExpBlink then
    path, blink = '/images/game/shields/shield_blue_not_shared', true
  elseif shieldId == ShieldYellowNoSharedExpBlink then
    path, blink = '/images/game/shields/shield_yellow_not_shared', true
  elseif shieldId == ShieldBlueNoSharedExp then
    path, blink = '/images/game/shields/shield_blue_not_shared', false
  elseif shieldId == ShieldYellowNoSharedExp then
    path, blink = '/images/game/shields/shield_yellow_not_shared', false
  elseif shieldId == ShieldGray then
    path, blink = '/images/game/shields/shield_gray', false
  end
  return path, blink
end

function getEmblemImagePath(emblemId)
  local path
  if emblemId == EmblemGreen then
    path = '/images/game/emblems/emblem_green'
  elseif emblemId == EmblemRed then
    path = '/images/game/emblems/emblem_red'
  elseif emblemId == EmblemBlue then
    path = '/images/game/emblems/emblem_blue'
  elseif emblemId == EmblemMember then
    path = '/images/game/emblems/emblem_member'
  elseif emblemId == EmblemOther then
    path = '/images/game/emblems/emblem_other'
  end
  return path
end

function getTypeImagePath(creatureType)
  local path
  if creatureType == CreatureTypeSummonOwn then
    path = '/images/game/creaturetype/summon_own'
  elseif creatureType == CreatureTypeSummonOther then
    path = '/images/game/creaturetype/summon_other'
  end
  return path
end

function getIconImagePath(iconId)
  local path
  if iconId == NpcIconChat then
    path = '/images/game/npcicons/icon_chat'
  elseif iconId == NpcIconTrade then
    path = '/images/game/npcicons/icon_trade'
  elseif iconId == NpcIconQuest then
    path = '/images/game/npcicons/icon_quest'
  elseif iconId == NpcIconTradeQuest then
    path = '/images/game/npcicons/icon_tradequest'
  elseif iconId == NpcIconHireling then
    path = '/images/game/npcicons/icon_hireling'
  end
  return path
end

function Creature:onSkullChange(skullId)
  local imagePath = getSkullImagePath(skullId)
  if imagePath then
    self:setSkullTexture(imagePath)
  end
end

function Creature:onShieldChange(shieldId)
  local imagePath, blink = getShieldImagePathAndBlink(shieldId)
  if imagePath then
    self:setShieldTexture(imagePath, blink)
  end
end

function Creature:onEmblemChange(emblemId)
  local imagePath = getEmblemImagePath(emblemId)
  if imagePath then
    self:setEmblemTexture(imagePath)
  end
end

function Creature:onTypeChange(typeId)
  local imagePath = getTypeImagePath(typeId)
  if imagePath then
    self:setTypeTexture(imagePath)
  end
end

function Creature:onIconChange(iconId)
  local imagePath = getIconImagePath(iconId)
  if imagePath then
    self:setIconTexture(imagePath)
  end
end

function Creature:setOutfitShader(shader)
  local outfit = self:getOutfit()
  outfit.shader = shader
  self:setOutfit(outfit)
end

function Creature:onIconEffectChange(icons)
  for i, icon in pairs(icons) do
    self:updateIconEffectTexture("/images/game/icons/" .. (icon.modification and "modifications" or "quests") .. "/".. icon.id, icon.id)
  end
end

if not Creature.getIcons then
  function Creature:getIcons()
    return {}
  end
end

MonsterIconExposeWeakness = MonsterIconExposeWeakness or 1
MonsterIconSapStrength = MonsterIconSapStrength or 2
MonsterIconTurnedMelee = MonsterIconTurnedMelee or 3
MonsterIconFiendish = MonsterIconFiendish or 5
MonsterIconWeeklyTask = MonsterIconWeeklyTask or 8
MonsterIconBountyTask = MonsterIconBountyTask or 9

if not Creature.hasIcon then
  function Creature:hasIcon(iconId, category)
    category = category or 1
    local icons = self:getIcons()
    if not icons then return false end

    for _, iconData in pairs(icons) do
      local id = iconData
      local iconCategory = category
      if type(iconData) == 'table' then
        id = iconData[1] or iconData.id
        iconCategory = iconData[2] or iconData.category or iconData.cat or category
      end
      if id == iconId and iconCategory == category then
        return true
      end
    end
    return false
  end
end

local function getCreatureVocation(creature)
  if creature and type(creature.getVocation) == 'function' then
    return creature:getVocation()
  end
  return 0
end

function Creature:isDruid()
  local vocation = getCreatureVocation(self)
  return vocation == 2 or vocation == 6 or vocation == 14
end

function Creature:isSorcerer()
  local vocation = getCreatureVocation(self)
  return vocation == 1 or vocation == 5 or vocation == 13
end

function Creature:isPaladin()
  local vocation = getCreatureVocation(self)
  return vocation == 3 or vocation == 7 or vocation == 12
end

function Creature:isKnight()
  local vocation = getCreatureVocation(self)
  return vocation == 4 or vocation == 8 or vocation == 11
end

function Creature:isMonk()
  local vocation = getCreatureVocation(self)
  return vocation == 9 or vocation == 10 or vocation == 15
end

function g_game.onCreatureIconChange(creatureId)
end
