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

-- Creature icons (0x8B type 14): magic debuffs (exori kor -> LowerDamageDealt,
-- exori moe -> HigherDamageReceived, TurnedMelee), the Influenced/Fiendish
-- modifiers and quest marks. The engine stores them per creature but the wire
-- order/count is only fully exposed by getCreatureIcons() (build af3a102). Older
-- binaries bind just hasCreatureIcon(id, category), so probe the known ids.
-- category 1 = Modifications (magic debuffs + influenced/fiendish), 0 = Quest.
local MODIFICATION_ICON_IDS = { 1, 2, 3, 4, 5, 6 }
local QUEST_ICON_IDS = {
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12,
  13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24
}

-- Returns a list of { id, category, modification, count } records for every icon
-- currently active on the creature (empty list when none). `modification` is the
-- boolean the battle list and onIconEffectChange key their image folder on.
function Creature:getIcons()
  -- Preferred path: the full list, with the real per-icon count (Fiendish level).
  -- The C++ tuple marshals as a 1-indexed { [1]=id, [2]=category, [3]=count }.
  if self.getCreatureIcons then
    local raw = self:getCreatureIcons()
    local icons = {}
    if raw then
      for _, t in ipairs(raw) do
        local category = t[2]
        icons[#icons + 1] = {
          id = t[1],
          category = category,
          modification = (category == 1),
          count = t[3] or 0
        }
      end
    end
    return icons
  end

  -- Fallback for binaries without the getCreatureIcons binding: probe presence via
  -- hasCreatureIcon. The per-icon count is not recoverable this way, so it is 0.
  if self.hasCreatureIcon then
    local icons = {}
    for _, id in ipairs(MODIFICATION_ICON_IDS) do
      if self:hasCreatureIcon(id, 1) then
        icons[#icons + 1] = { id = id, category = 1, modification = true, count = 0 }
      end
    end
    for _, id in ipairs(QUEST_ICON_IDS) do
      if self:hasCreatureIcon(id, 0) then
        icons[#icons + 1] = { id = id, category = 0, modification = false, count = 0 }
      end
    end
    return icons
  end

  return {}
end

function Creature:isDruid()
  return self:getVocation() == 4 or self:getVocation() == 14
end

function Creature:isSorcerer()
  return self:getVocation() == 3 or self:getVocation() == 13
end

function Creature:isPaladin()
  return self:getVocation() == 2 or self:getVocation() == 12
end

function Creature:isKnight()
  return self:getVocation() == 1 or self:getVocation() == 11
end

function Creature:isMonk()
  return self:getVocation() == 5 or self:getVocation() == 15
end

-- UICreature has no race id in C++; mods (cyclopedia bosstiary/boss slots,
-- prey hunting, monster podium) tag widgets with it, so store it as a Lua field.
function UICreature:setRaceID(raceId)
  self.raceId = raceId
end

function UICreature:getRaceID()
  return self.raceId
end

function g_game.onCreatureIconChange(creatureId)
end
