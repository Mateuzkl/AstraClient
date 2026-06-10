healthInfoWindow = nil
healthBar = nil
manaBar = nil
experienceBar = nil
soulLabel = nil
capLabel = nil
healthTooltip = 'Your character health is %d out of %d.'
manaTooltip = 'Your character mana is %d out of %d.'
experienceTooltip = 'You have %d%% to advance to level %d.'

overlay = nil
topHealthBar = nil
topManaBar = nil
useManaShield = nil

local currentArcStyle

function init()
  connect(LocalPlayer, { onHealthChange = onHealthChange,
                         onManaChange = onManaChange,
                         onLevelChange = onLevelChange,
                         onStatesChange = onStatesChange,
                         onTaintsChange = onTaintsChange,
                         onSoulChange = onSoulChange,
                         onVocationChange = onVocationChange,
                         onFreeCapacityChange = onFreeCapacityChange })

  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline
  })

  healthInfoWindow = g_ui.loadUI('healthinfo', m_interface.getRightPanel())
  healthInfoWindow:disableResize()

  useManaShield = false

  healthBar = healthInfoWindow:recursiveGetChildById('healthBar')
  manaBar = healthInfoWindow:recursiveGetChildById('manaBar')
  experienceBar = healthInfoWindow:recursiveGetChildById('experienceBar')
  soulLabel = healthInfoWindow:recursiveGetChildById('soulLabel')
  capLabel = healthInfoWindow:recursiveGetChildById('capLabel')

  overlay = g_ui.createWidget('HealthOverlay', m_interface.getMapPanel())
  overlay:insertLuaCall("onGeometryChange")
  overlay:show()

  topHealthBar = overlay:getChildById('topHealthBar')
  topManaBar = overlay:getChildById('topManaBar')

  connect(overlay, { onGeometryChange = onOverlayGeometryChange })

  -- load condition icons
  for _,v in pairs(Icons) do
    g_textures.preload(v.path)
  end

  if g_game.isOnline() then
    local localPlayer = g_game.getLocalPlayer()
    onHealthChange(localPlayer, localPlayer:getHealth(), localPlayer:getMaxHealth())
    onManaChange(localPlayer, localPlayer:getMana(), localPlayer:getMaxMana())
    onLevelChange(localPlayer, localPlayer:getLevel(), localPlayer:getLevelPercent())
    onStatesChange(localPlayer, localPlayer:getStates(), 0)
    onTaintsChange(localPlayer, localPlayer:getTaints(), 0)
    onSoulChange(localPlayer, localPlayer:getSoul())
    onFreeCapacityChange(localPlayer, localPlayer:getFreeCapacity())
  end

  healthInfoWindow:setup()
  healthInfoWindow:open()

  hideLabels()
  hideExperience()

  healthInfoWindow:setHeight(32)

  if g_app.isMobile() then
    healthInfoWindow:close()
    if healthInfoButton then
      healthInfoButton:setOn(false)
    end
  end
end

function terminate()
  disconnect(LocalPlayer, { onHealthChange = onHealthChange,
                            onManaChange = onManaChange,
                            onLevelChange = onLevelChange,
                            onStatesChange = onStatesChange,
                            onTaintsChange = onTaintsChange,
                            onSoulChange = onSoulChange,
                            onFreeCapacityChange = onFreeCapacityChange,
                            onVocationChange = onVocationChange })

  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline
  })
  disconnect(overlay, { onGeometryChange = onOverlayGeometryChange })

  healthInfoWindow:destroy()
  if healthInfoButton then
    healthInfoButton:destroy()
  end
  overlay:destroy()
end

function onStartGame()
  if g_game.isOnline() then
    local localPlayer = g_game.getLocalPlayer()
    onHealthChange(localPlayer, localPlayer:getHealth(), localPlayer:getMaxHealth())
    onManaChange(localPlayer, localPlayer:getMana(), localPlayer:getMaxMana())
    onLevelChange(localPlayer, localPlayer:getLevel(), localPlayer:getLevelPercent())
    onStatesChange(localPlayer, localPlayer:getStates(), 0)
    onTaintsChange(localPlayer, localPlayer:getTaints(), 0)
    onSoulChange(localPlayer, localPlayer:getSoul())
    onFreeCapacityChange(localPlayer, localPlayer:getFreeCapacity())
  end
end

function online()
  local benchmark = g_clock.millis()
  scheduleEvent(onStartGame, 100)
  consoleln("HealthInfo loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function offline()
  healthInfoWindow:hide()
end

function toggle()
  if not healthInfoButton then return end
  if healthInfoButton:isOn() then
    healthInfoWindow:close()
    healthInfoButton:setOn(false)
  else
    healthInfoWindow:open()
    healthInfoButton:setOn(true)
  end
end

function toggleIcon(bitChanged)
  local player = g_game.getLocalPlayer()
  if not player then return end

  local content = healthInfoWindow:recursiveGetChildById('conditionPanel')

  local icon = content:getChildById(Icons[bitChanged].id)
  if icon then
    icon:destroy()
    if bitChanged == PlayerStates.Paralyze then
      player:setPreWalkLockedDelay(g_clock.millis() + 2000)
    end
  else
    icon = loadIcon(bitChanged)
    icon:setParent(content)
  end
end

function loadIcon(bitChanged)
  local icon = g_ui.createWidget('ConditionWidget', content)
  icon:setId(Icons[bitChanged].id)
  icon:setImageSource(Icons[bitChanged].path)
  icon:setTooltip(Icons[bitChanged].tooltip)
  return icon
end

-- hooked events
function onMiniWindowClose()
  if healthInfoButton then
    healthInfoButton:setOn(false)
  end
end

function onHealthChange(localPlayer, health, maxHealth)
  if not g_game.isOnline() then return end
  if health > maxHealth then
    maxHealth = health
  end

  if healthInfoWindow and healthInfoWindow:recursiveGetChildById("healthLabel") then
    healthInfoWindow:recursiveGetChildById("healthLabel"):setText(health)
  end

  healthBar:setTooltip(tr(healthTooltip, health, maxHealth))
  healthBar:setValue(health, 0, maxHealth)

  topHealthBar:setText(comma_value(health) .. ' / ' .. comma_value(maxHealth))
  topHealthBar:setTooltip(tr(healthTooltip, health, maxHealth))
  topHealthBar:setValue(health, 0, maxHealth)
end

function onManaChange(localPlayer, mana, maxMana)
  if not g_game.isOnline() then return end
  if mana > maxMana then
    maxMana = mana
  end

  healthInfoWindow:recursiveGetChildById("manaLabel"):setText(mana)

  manaBar:setTooltip(tr(manaTooltip, mana, maxMana))
  manaBar:setValue(mana, 0, maxMana)

  topManaBar:setText(comma_value(mana) .. ' / ' .. comma_value(maxMana))
  topManaBar:setTooltip(tr(manaTooltip, mana, maxMana))
  topManaBar:setValue(mana, 0, maxMana)
end

function onLevelChange(localPlayer, value, percent)
  experienceBar:setText(percent .. '%')
  experienceBar:setTooltip(tr(experienceTooltip, percent, value+1))
  experienceBar:setPercent(percent)
end

function onSoulChange(localPlayer, soul)
  soulLabel:setText(tr('Soul') .. ': ' .. soul)
end

function onFreeCapacityChange(player, freeCapacity)
  capLabel:setText(tr('Cap') .. ': ' .. freeCapacity)
end

function onStatesChange(localPlayer, now, old)
  if now == old then return end

  local bitsChanged = bit32.bxor(now, old)
  for i = 1, 32 do
    local pow = math.pow(2, i-1)
    if pow > bitsChanged then break end
    local bitChanged = bit32.band(bitsChanged, pow)
    if bitChanged ~= 0 then
      toggleIcon(bitChanged)
    end
  end
end

function onTaintsChange(localPlayer, now, old)
  local content = healthInfoWindow:recursiveGetChildById('conditionPanel')
  if not content then return end

  local icon = content:getChildById('condition_taints')
  if icon then
    icon:destroy()
    icon = nil
  end

  if now ~= 0 then
      local icon = g_ui.createWidget('ConditionWidget', content)
      icon:setId('condition_taints')
      icon:setImageSource('/images/game/states/' .. now + 30 )
      icon:setTooltipFont("Verdana Bold-11px-wheel")
      icon:setTooltip(TaintsDescriptions[now])
      icon:setParent(content)
  end
end

-- personalization functions
function hideLabels()
  local content = healthInfoWindow:recursiveGetChildById('conditionPanel')
  local removeHeight = math.max(capLabel:getMarginRect().height, soulLabel:getMarginRect().height) + content:getMarginRect().height - 3
  capLabel:setOn(false)
  soulLabel:setOn(false)
  content:setVisible(false)
  healthInfoWindow:setHeight(math.max(healthInfoWindow.minimizedHeight, healthInfoWindow:getHeight() - removeHeight))
end

function hideExperience()
  local removeHeight = experienceBar:getMarginRect().height
  experienceBar:setOn(false)
  healthInfoWindow:setHeight(math.max(healthInfoWindow.minimizedHeight, healthInfoWindow:getHeight() - removeHeight))
end

function setHealthTooltip(tooltip)
  healthTooltip = tooltip

  local localPlayer = g_game.getLocalPlayer()
  if localPlayer then
    healthBar:setTooltip(tr(healthTooltip, localPlayer:getHealth(), localPlayer:getMaxHealth()))
  end
end

function setManaTooltip(tooltip)
  manaTooltip = tooltip

  local localPlayer = g_game.getLocalPlayer()
  if localPlayer then
    manaBar:setTooltip(tr(manaTooltip, localPlayer:getMana(), localPlayer:getMaxMana()))
  end
end

function setExperienceTooltip(tooltip)
  experienceTooltip = tooltip

  local localPlayer = g_game.getLocalPlayer()
  if localPlayer then
    experienceBar:setTooltip(tr(experienceTooltip, localPlayer:getLevelPercent(), localPlayer:getLevel()+1))
  end
end

function onOverlayGeometryChange()
  if g_app.isMobile() then
    topHealthBar:setMarginTop(35)
    topManaBar:setMarginTop(35)
    local width = overlay:getWidth()
    local margin = width / 3 + 10
    topHealthBar:setMarginLeft(margin)
    topManaBar:setMarginRight(margin)
    return
  end

  local classic = g_settings.getBoolean("classicView")
  local minMargin = 40
  if classic then
    topHealthBar:setMarginTop(15)
    topManaBar:setMarginTop(15)
  else
    topHealthBar:setMarginTop(45 - overlay:getParent():getMarginTop())
    topManaBar:setMarginTop(45 - overlay:getParent():getMarginTop())
    minMargin = 200
  end

  local height = overlay:getHeight()
  local width = overlay:getWidth()

  topHealthBar:setMarginLeft(math.max(minMargin, (width - height + 50) / 2 + 2))
  topManaBar:setMarginRight(math.max(minMargin, (width - height + 50) / 2 + 2))
end

function getHealthInfoWindow()
  return healthInfoWindow
end

function move(panel, index)
  local statusBar =  m_settings.getOption('statusBars')
  if not statusBar then
    healthInfoWindow:hide()
    return
  end

  addEvent(function()
    if not healthInfoWindow:isVisible() then
      healthInfoWindow:show()
    end

    healthInfoWindow:setParent(panel)
  end)

  return healthInfoWindow
end
