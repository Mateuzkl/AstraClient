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
  self.shieldWidget = self:getChildById('shield')
  self.emblemWidget = self:getChildById('emblem')
  self.monster1Widget = self:getChildById('monster1')
  self.monster2Widget = self:getChildById('monster2')
  self.monster3Widget = self:getChildById('monster3')
  self.monster4Widget = self:getChildById('monster4')
  self.monster5Widget = self:getChildById('monster5')
  self.creatureIcons = {}
end

function UICreatureButton:update()
  local color = CreatureButtonColors.onIdle
  local show = false
  if self.creature == g_game.getAttackingCreature() then
    color = CreatureButtonColors.onTargeted
  elseif self.creature == g_game.getFollowingCreature() then
    color = CreatureButtonColors.onFollowed
  end
  color = self.isHovered and color.hovered or color.notHovered

  if self.color == color then
    return
  end
  self.color = color

  if color ~= CreatureButtonColors.onIdle.notHovered then
    self.creatureWidget:setBorderWidth(1)
    self.creatureWidget:setBorderColor(color)
    self.labelWidget:setColor(color)
  else
    self.creatureWidget:setBorderWidth(0)
    self.labelWidget:setColor(color)
  end
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
  self:updateShield()
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

  -- The party shield anchors to the skull's left with a 4px gap. That gap is only
  -- real when the skull is actually shown; without a PK skull the shield must hug
  -- the right edge (where the skull would be) instead of inheriting its empty slot.
  if self.shieldWidget then
    self.shieldWidget:setMarginRight(skullId ~= SkullNone and 4 or 0)
  end
end

function UICreatureButton:updateShield()
  if not self.creature or not self.shieldWidget then
    return
  end
  local shieldId = self.creature:getShield()
  if shieldId == self.shieldId then
    return
  end
  self.shieldId = shieldId

  -- getShieldImagePathAndBlink returns nil for ShieldNone/unknown ids; the battle
  -- row shows the party shield statically (no blink), matching skull/emblem here.
  local imagePath = getShieldImagePathAndBlink(shieldId)
  if imagePath then
    self.shieldWidget:setImageSource(imagePath)
    self.shieldWidget:setWidth(11)
    self.shieldWidget:setHeight(11)
  else
    self.shieldWidget:setWidth(0)
  end
end

function UICreatureButton:updateEmblem()
  if not self.creature or not self.emblemWidget then
    return
  end
  local emblemId = self.creature:getEmblem()

  -- Party shield and guild emblem share the same right-hand column, and the party
  -- shield wins: while the player is in a party the emblem yields its slot (so a
  -- partied guild member shows the shield, not the emblem). shieldId was already
  -- refreshed by updateShield(), which runs right before this in creatureSetup, so
  -- the dirty-check also keys on partyActive to re-show the emblem once party ends.
  local partyActive = self.shieldWidget ~= nil and self.shieldId ~= nil
    and getShieldImagePathAndBlink(self.shieldId) ~= nil
  if self.emblemId == emblemId and self.emblemHiddenByParty == partyActive then
    return
  end
  self.emblemId = emblemId
  self.emblemHiddenByParty = partyActive

  local imagePath = not partyActive and getEmblemImagePath(emblemId) or nil
  if imagePath then
    self.emblemWidget:setImageSource(imagePath)
    self.emblemWidget:setWidth(11)
    self.emblemWidget:setHeight(11)
  else
    self.emblemWidget:setWidth(0)
  end
end

function UICreatureButton:updateLifeBarPercent()
  if not self.creature then
    return
  end
  local percent = self.creature:getHealthPercent()
  -- Dirty-check: the battle list calls this ~10x/s per creature; skipping the two
  -- widget setters + the color lookup when the HP% is unchanged is the single biggest
  -- CPU win here. Uses its own field (not self.percent, which updateManaBarPercent
  -- also wrote — they were clobbering each other's cache).
  if self.lifePercent == percent then
    return
  end
  self.lifePercent = percent
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
  elseif self.creature.getManaPercent then
    -- m_manaPercent defaults to -1 (bar hidden); only party members get it set
    -- via 0x8B type 11 (sendPartyPlayerMana — the sender is included in the
    -- broadcast, so the local player's own row renders too).
    percent = self.creature:getManaPercent()
  end

  if percent < 0 then
    self.manaBarWidget:setVisible(false)
    return
  end

  self.manaBarWidget:setVisible(true)
  if self.manaPercent == percent then
    return
  end

  self.manaPercent = percent
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
