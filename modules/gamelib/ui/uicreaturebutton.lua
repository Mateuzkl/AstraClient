-- @docclass
UICreatureButton = extends(UIWidget, "UICreatureButton")

local CreatureButtonColors = {
  onIdle = {notHovered = '#afafaf', hovered = '#f7f7f7' },
  onTargeted = {notHovered = '#df3f3f', hovered = '#f7a3a3' },
  onFollowed = {notHovered = '#3fdf3f', hovered = '#b3f7b3' }
}

local LifeBarColors = {} -- Must be sorted by percentAbove
table.insert(LifeBarColors, {percentAbove = 94, color = '#00C000' } )
table.insert(LifeBarColors, {percentAbove = 59, color = '#60c060' } )
table.insert(LifeBarColors, {percentAbove = 29, color = '#c0c000' } )
table.insert(LifeBarColors, {percentAbove = 9, color = '#c03030' } )
table.insert(LifeBarColors, {percentAbove = 3, color = '#c00000' } )
table.insert(LifeBarColors, {percentAbove = -1, color = '#600000' } )

local EchoRaidColors = {
  [0] = '#FF3030', -- Echo Warden
  [1] = '#D060D8'  -- currently empowered by the Warden aura
}

function UICreatureButton.create()
  local button = UICreatureButton.internalCreate()
  button:setFocusable(false)
  button.creature = nil
  button.isHovered = false
  return button
end

function UICreatureButton:setCreature(creature)
    self.creature = creature
end

function UICreatureButton:getCreature()
  return self.creature
end

function UICreatureButton:getCreatureId()
    return self.creature:getId()
end

function UICreatureButton:setup(id)
  self.lifeBarWidget = self:getChildById('lifeBar')
  self.manaBarWidget = self:getChildById('manaBar')
  self.creatureWidget = self:getChildById('creature')
  self.labelWidget = self:getChildById('label')
  self.skullWidget = self:getChildById('skull')
  self.emblemWidget = self:getChildById('emblem')
  self.monster1Widget = self:getChildById('monster1')
  self.monster2Widget = self:getChildById('monster2')
  self.monster3Widget = self:getChildById('monster3')
  self.monster4Widget = self:getChildById('monster4')
  self.monster5Widget = self:getChildById('monster5')
  self.creatureIcons = {}
end

function UICreatureButton:update()
  if not self.creature then
    return
  end

  local echoState = self.creature:getEchoRaidVisualState()
  local echoColor = EchoRaidColors[echoState]
  local labelColor = echoColor or (self.isHovered and CreatureButtonColors.onIdle.hovered or CreatureButtonColors.onIdle.notHovered)
  local borderColor = echoColor

  if self.creature == g_game.getAttackingCreature() then
    borderColor = self.isHovered and CreatureButtonColors.onTargeted.hovered or CreatureButtonColors.onTargeted.notHovered
    labelColor = echoColor or borderColor
  elseif self.creature == g_game.getFollowingCreature() then
    borderColor = self.isHovered and CreatureButtonColors.onFollowed.hovered or CreatureButtonColors.onFollowed.notHovered
    labelColor = echoColor or borderColor
  elseif self.isHovered then
    borderColor = CreatureButtonColors.onIdle.hovered
  end

  local styleKey = labelColor .. ':' .. tostring(borderColor)
  if self.color == styleKey then
    return
  end
  self.color = styleKey

  if borderColor then
    self.creatureWidget:setBorderWidth(1)
    self.creatureWidget:setBorderColor(borderColor)
  else
    self.creatureWidget:setBorderWidth(0)
  end
  self.labelWidget:setColor(labelColor)
end

function UICreatureButton:creatureSetup(creature)
  if self.creature ~= creature then
    self.creature = creature
    self.creatureWidget:setCreature(creature)

    local name = creature:getName()
    if #name > 14 then
      self.labelWidget:setText(name:sub(1, 14) .. '...')
      self.labelWidget:setTooltip(name)
    else
      self.labelWidget:setText(name)
      self.labelWidget:removeTooltip()
    end
  end

  self:updateLifeBarPercent()
  self:updateManaBarPercent()
  self:updateSkull()
  self:updateEmblem()
  self:updateIcons()

  self:update()
end

function UICreatureButton:updateSkull()
  if not self.creature then
    return
  end
  local skullId = self.creature:getSkull()
  if skullId == self.skullId then
    return
  end
  self.skullId = skullId

  if skullId ~= SkullNone then
    local imagePath = getSkullImagePath(skullId)
    self.skullWidget:setImageSource(imagePath)
    self.skullWidget:setHeight(11)
    self.skullWidget:setWidth(11)
  else
    self.skullWidget:setWidth(0)
  end
end

function UICreatureButton:updateEmblem()
  if not self.creature then
    return
  end
  local emblemId = self.creature:getEmblem()
  if self.emblemId == emblemId then
    return
  end
  self.emblemId = emblemId

  if emblemId ~= EmblemNone then
    local imagePath = getEmblemImagePath(emblemId)
    self.emblemWidget:setImageSource(imagePath)
  else
    self.emblemWidget:setWidth(0)
    self.emblemWidget:setMarginLeft(0)
  end
end

function UICreatureButton:updateLifeBarPercent()
  if not self.creature then
    return
  end
  local percent = self.creature:getHealthPercent()
  self.percent = percent
  self.lifeBarWidget:setPercent(percent)

  local color
  for i, v in pairs(LifeBarColors) do
    if percent > v.percentAbove then
      color = v.color
      break
    end
  end

  self.lifeBarWidget:setBackgroundColor(color)
end

function UICreatureButton:updateManaBarPercent()
  if not self.creature then
    return
  end
  local percent = -1
  if self.creature.getManaBarPercent then
    percent = self.creature:getManaBarPercent()
  elseif self.creature.getManaPercent and self.creature.isLocalPlayer and self.creature:isLocalPlayer() then
    percent = self.creature:getManaPercent()
  end

  if percent < 0 then
    self.manaBarWidget:setVisible(false)
    return
  end

  self.manaBarWidget:setVisible(true)
  if self.percent == percent then
    return
  end

  self.percent = percent
  self.manaBarWidget:setPercent(percent)
end

function UICreatureButton:updateIcons()
  if not self.creature then
    return
  end

  if self.monster1Widget:getWidth() ~= 0 then
    self.monster1Widget:setWidth(0)
    self.monster1Widget:setMarginLeft(0)
  end

  if self.monster2Widget:getWidth() ~= 0 then
    self.monster2Widget:setWidth(0)
    self.monster2Widget:setMarginLeft(0)
  end

  if self.monster3Widget:getWidth() ~= 0 then
    self.monster3Widget:setWidth(0)
    self.monster3Widget:setMarginLeft(0)
  end

  if self.monster4Widget:getWidth() ~= 0 then
    self.monster4Widget:setWidth(0)
    self.monster4Widget:setMarginLeft(0)
  end

  if not self.creature.getIcons then
    self.creatureIcons = {}
    return
  end

  local icons = self.creature:getIcons() or {}
  if table.compare(icons, self.creatureIcons) then
    return
  end

  self.creatureIcons = icons
  if #icons == 0 then
    return
  end

  if not self.creature:isMonster() then
    return
  end

  local count = 0
  for i, icon in pairs(icons) do

    local imagePath = "/images/game/icons/" .. (icon.modification and "modifications" or "quests") .. "/" .. icon.id
    count = count + 1
    if count == 1 then
      self.monster1Widget:setImageSource(imagePath)
    elseif count == 2 then
      self.monster2Widget:setImageSource(imagePath)
    elseif count == 3 then
      self.monster3Widget:setImageSource(imagePath)
    elseif count == 4 then
      self.monster4Widget:setImageSource(imagePath)
    end
  
    if count > 4 then
      break
    end
  end

end
