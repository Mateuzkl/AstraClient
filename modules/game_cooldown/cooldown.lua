local ProgressCallback = {
  update = 1,
  finish = 2
}

spellBar = nil
cooldownWindow = nil
cooldownButton = nil
contentsPanel = nil
cooldownPanel = nil

cooldown = {}
cooldowns = {}
groupCooldown = {}

function init()
  local bottomPanel = m_interface.getBottomCooldownPanel()

  spellBar = g_ui.loadUI('cooldown', bottomPanel)
  bottomPanel:moveChildToIndex(spellBar, 1)

  connect(g_game, { onGameStart = online,
                    onGameEnd = offline,
                    onSpellGroupCooldown = onSpellGroupCooldown,
                    onSpellCooldown = onSpellCooldown })

  local files = g_resources.listDirectoryFiles(SpelllistSettings['Default'].iconsFolder)
  for _,file in pairs(files) do
    if g_resources.isFileType(file, 'png') then
      g_textures.preload(SpelllistSettings['Default'].iconsFolder .. file)
    end
  end

  local files = g_resources.listDirectoryFiles(SpelllistSettings['Default'].smallIconsFolder)
  for _,file in pairs(files) do
    if g_resources.isFileType(file, 'png') then
      g_textures.preload(SpelllistSettings['Default'].smallIconsFolder .. file)
    end
  end

  cooldownPanel = spellBar.cooldownPanel

  if g_game.isOnline() then
    online()
  end
end

function terminate()
  if spellBar then
    spellBar:destroy()
  end

  spellBar = nil

  disconnect(g_game, { onGameStart = online,
                       onGameEnd = offline,
                       onSpellGroupCooldown = onSpellGroupCooldown,
                      onSpellCooldown = onSpellCooldown })

  for key, val in pairs(cooldowns) do
    removeCooldown(key)
  end
  cooldowns = {}
  cooldownPanel = nil
end

function loadIcon(iconId)
  local spell, profile, spellName = Spells.getSpellByIcon(iconId)
  if not spellName then return end
  if not profile then return end

  local icon = cooldownPanel:getChildById(iconId)
  if not icon then
    icon = g_ui.createWidget('BarSpellIcon')
    icon:setId(iconId)
  end

  local spellId = SpellIcons[spell.icon][1]
  local spellSettings = SpelllistSettings['Default'].smallIconsFolder
  if g_resources.fileExists(spellSettings .. ".png") then
    icon:setImageSource(spellSettings)
    icon:setImageClip(Spells.getImageClipSmall(spellId, 'Default'))
    icon:setTooltip(spellName .. " (" .. (spell.exhaustion / 1000) .. " sec. cooldown)")
  else
    icon = nil
  end
  -- Return spellName so the caller can reuse it instead of resolving the spell
  -- (Spells.getSpellByIcon) a second time per cooldown event.
  return icon, spellName
end

function offline()
  cooldownPanel:destroyChildren()
end

function removeCooldown(progressRect)
  removeEvent(progressRect.event)
  if progressRect.icon then
    progressRect.icon:destroy()
    progressRect.icon = nil
  end
  cooldowns[progressRect] = nil
  progressRect = nil
end

function turnOffCooldown(progressRect)
  removeEvent(progressRect.event)
  if progressRect.icon then
    progressRect.icon:setOn(false)
    progressRect.icon = nil
  end

  cooldowns[progressRect] = nil
  progressRect = nil
end

function initCooldown(progressRect, updateCallback, finishCallback)
  progressRect:setPercent(100)

  progressRect.callback = {}

  progressRect.callback[ProgressCallback.update] = updateCallback
  progressRect.callback[ProgressCallback.finish] = finishCallback

  updateCallback()
end

function updateCooldown(progressRect, duration)
  progressRect:setPercent(progressRect:getPercent() - 10000/duration)

  if progressRect:getPercent() > 0 then
    removeEvent(progressRect.event)

    progressRect.event = scheduleEvent(function()
      if not progressRect.callback then return end
      progressRect.callback[ProgressCallback.update]()
    end, 100)
  else
    progressRect.callback[ProgressCallback.finish]()
  end
end

function isGroupCooldownIconActive(groupId)
  return groupCooldown[groupId]
end

function isCooldownIconActive(iconId)
  return cooldown[iconId]
end

function onSpellCooldown(iconId, duration)
  local icon, spellName = loadIcon(iconId)
  if not icon then
    return
  end
  icon:setParent(cooldownPanel)

  local progressRect = icon:getChildById(iconId)
  if not progressRect then
    progressRect = g_ui.createWidget('BarSpellProgressRect', icon)
    progressRect:setId(iconId)
    progressRect.icon = icon
    progressRect:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    progressRect:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    progressRect:setMarginBottom(-1)
    progressRect:setMarginLeft(1)
  else
    progressRect:setPercent(0)
  end
  -- spellName was already resolved by loadIcon above; reuse it instead of calling
  -- Spells.getSpellByIcon a second time for the same iconId.
  progressRect:setTooltip(spellName)

  local updateFunc = function()
    updateCooldown(progressRect, duration)
  end
  local finishFunc = function()
    removeCooldown(progressRect)
    cooldown[iconId] = false
  end
  initCooldown(progressRect, updateFunc, finishFunc)
  cooldown[iconId] = true
  cooldowns[progressRect] = true
end


function onSpellGroupCooldown(groupId, duration)
  if not SpellGroups[groupId] then return end

  local icon = spellBar:getChildById('groupIcon' .. SpellGroups[groupId])
  local progressRect = spellBar:getChildById('progressRect' .. SpellGroups[groupId])

  if icon then
    icon:setOn(true)
    removeEvent(icon.event)
  end

  if progressRect then
    progressRect.icon = icon
    removeEvent(progressRect.event)
    local updateFunc = function()
      updateCooldown(progressRect, duration)
    end
    local finishFunc = function()
      turnOffCooldown(progressRect)
      groupCooldown[groupId] = false
    end
    initCooldown(progressRect, updateFunc, finishFunc)
    groupCooldown[groupId] = true
  end
end

function toggleVisible(value)
  spellBar:setVisible(value)
end
