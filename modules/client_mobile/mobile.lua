-- Clean-room Classic Dark-Charcoal Mobile HUD, Analog Joystick, Real Spell/Item Hotkey Grid,
-- Top-Right Toolbar + Equipment/Containers Sync, On-Demand Chat & Scrollable Mobile Settings.
local overlay
local keypad
local leftQuickCluster
local rightControls
local mobileVitalsHud
local mobileTargetBar
local mobileTopRightBar
local mobileMenuPanel
local mobileLoginSettingsBtn
local settingsDrawer
local touchStart = 0
local touchOrigin = { x = 0, y = 0 }
local updateCursorEvent
local initScaleEvent
local statusTickerEvent
local zoomInButton
local zoomOutButton
local keypadButton
local keypadEvent
local keypadActive = false
local keypadTouchButton = nil
local keypadMousePos = { x = 0.5, y = 0.5 }
local keypadTicks = 0
local controlsVisible = true
local controlScale = 1.0
local joystickSide = 'left'
local drawLightsEnabled = true
local floorFadingEnabled = true
local actionMode = nil -- nil | 'use' | 'look'
local hotkeyPage = 1   -- 1..4 (7 slots per page = 28 touch hotkeys)
local lastPingMs = -1
local activeSlotSpecs = {} -- slot 1..7 -> { kind='hotkey'|'spell'|'item', combo, words, itemId, subType, useType }

local DEADZONE = 0.16
local LONG_PRESS_MS = 450
local SLOTS_PER_PAGE = 7
local TOTAL_HOTKEY_PAGES = 4

local function clamp(value, minVal, maxVal)
  if value < minVal then return minVal end
  if value > maxVal then return maxVal end
  return value
end

local function computeAutoScale()
  local size = g_window.getSize()
  if not size or size.width <= 0 or size.height <= 0 then
    return 1.0
  end
  -- Target crisp 1:1 CSS logical units (min ~360 logical height so 640x360, 800x360, 844x390 & tablets stay clean).
  local dpr = (g_window.getDisplayDensity and g_window.getDisplayDensity()) or 1.0
  local maxByHeight = size.height / 360.0
  local maxByWidth = size.width / 640.0
  local autoScale = math.min(dpr, maxByHeight, maxByWidth)
  autoScale = clamp(math.floor(autoScale * 4 + 0.5) / 4, 1.0, 2.0)
  return autoScale
end

local function clampSettingsDrawerToViewport()
  if not settingsDrawer then return end
  local root = g_ui.getRootWidget()
  if not root then return end
  local rw = root:getWidth()
  local rh = root:getHeight()
  if rw <= 0 or rh <= 0 then return end
  local maxW = math.min(372, math.max(292, rw - 24))
  local maxH = math.min(306, math.max(210, rh - 24))
  settingsDrawer:setSize({ width = maxW, height = maxH })
end

local applyingScale = false
local lastAppliedScale = 0

local function applyResponsiveScale()
  if applyingScale then return end
  applyingScale = true
  local target = computeAutoScale()
  if math.abs(target - lastAppliedScale) > 0.001 then
    lastAppliedScale = target
    g_app.scale(target)
  end
  clampSettingsDrawerToViewport()
  if modules.game_interface and modules.game_interface.updateMobileLiteMapGeometry then
    modules.game_interface.updateMobileLiteMapGeometry()
  end
  applyingScale = false
end

local function getMapPanel()
  if modules.game_interface and modules.game_interface.getMapPanel then
    return modules.game_interface.getMapPanel()
  end
  return nil
end

local function isWidgetDescendantOf(widget, ancestor)
  local cur = widget
  while cur do
    if cur == ancestor then return true end
    cur = cur:getParent()
  end
  return false
end

local function isPointDirectlyOnMap(pos)
  local mapPanel = getMapPanel()
  if not mapPanel or not mapPanel:isVisible() then return false end
  local root = g_ui.getRootWidget()
  if not root then return false end
  local hit = root:recursiveGetChildByPos(pos, false)
  if not hit then return false end
  return isWidgetDescendantOf(hit, mapPanel)
end

local function countPlayerItem(itemId)
  if not itemId or itemId <= 0 then return 0 end
  local total = 0
  local player = g_game.getLocalPlayer()
  if player then
    if player.getInventoryCount then
      local c = tonumber(player:getInventoryCount(itemId, 0)) or 0
      if c > 0 then return c end
    end
    for slot = InventorySlotFirst, InventorySlotLast do
      local eq = player:getInventoryItem(slot)
      if eq and eq:getId() == itemId then
        total = total + math.max(1, eq:getCount() or 1)
      end
    end
  end
  if g_game.getContainers then
    for _, container in pairs(g_game.getContainers()) do
      if container and container.getItems then
        for _, item in ipairs(container:getItems()) do
          if item and item:getId() == itemId then
            total = total + math.max(1, item:getCount() or 1)
          end
        end
      end
    end
  end
  return total
end

local function collectUsefulBackpackItems()
  local priority = {}
  local secondary = {}
  local seen = {}
  if not g_game.getContainers then return priority end
  for _, container in pairs(g_game.getContainers()) do
    if container and container.getItems then
      for _, item in ipairs(container:getItems()) do
        if item then
          local id = item:getId()
          if id and id > 0 and not seen[id] and not item:isContainer() then
            seen[id] = true
            local count = countPlayerItem(id)
            local isMulti = item.isMultiUse and item:isMultiUse() or false
            local isStack = item.isStackable and item:isStackable() or false
            local useType = isMulti and HOTKEY_MANAGER_USEWITH or HOTKEY_MANAGER_USEONSELF
            local entry = {
              kind = 'item',
              itemId = id,
              subType = item:getSubType() or 0,
              useType = useType,
              count = count
            }
            if isMulti or (isStack and count > 1) then
              priority[#priority + 1] = entry
            else
              secondary[#secondary + 1] = entry
            end
          end
        end
      end
    end
  end
  local found = {}
  for _, it in ipairs(priority) do
    found[#found + 1] = it
    if #found >= 4 then return found end
  end
  for _, it in ipairs(secondary) do
    found[#found + 1] = it
    if #found >= 4 then return found end
  end
  return found
end

local function getDefaultPage1Specs()
  local specs = {}
  -- Sensible vocation-aware classic Tibia spells (rendered with real spell icons via Spells.getSpellIcon)
  local player = g_game.getLocalPlayer()
  local voc = player and player.getVocation and player:getVocation() or 0
  local baseSpells
  if voc == 1 or voc == 5 then -- Sorcerer
    baseSpells = { 'exura', 'utani hur', 'exori vis', 'exura gran' }
  elseif voc == 2 or voc == 6 then -- Druid
    baseSpells = { 'exura', 'utani hur', 'exori frigo', 'exura gran' }
  elseif voc == 3 or voc == 7 then -- Paladin
    baseSpells = { 'exura', 'utani hur', 'exori con', 'exura san' }
  elseif voc == 4 or voc == 8 then -- Knight
    baseSpells = { 'exura ico', 'utani hur', 'exori hur', 'exori' }
  else
    baseSpells = { 'exura', 'utani hur', 'exori vis', 'exura gran' }
  end

  local bpItems = collectUsefulBackpackItems()
  -- Slots 1..3 (top row): healing/haste/utility spells
  specs[1] = { kind = 'spell', words = baseSpells[1] }
  specs[2] = { kind = 'spell', words = baseSpells[2] }
  specs[3] = { kind = 'spell', words = baseSpells[3] }
  -- Slots 4..7 (middle row): live backpack items (potions/runes/tools with real sprites + counts) + 4th spell
  local idx = 4
  for _, it in ipairs(bpItems) do
    if idx <= 6 then
      specs[idx] = it
      idx = idx + 1
    end
  end
  while idx <= 7 do
    specs[idx] = { kind = 'spell', words = baseSpells[math.min(#baseSpells, idx - 3)] }
    idx = idx + 1
  end
  return specs
end

local function getComboForSlot(page, slotIdx)
  local absoluteIdx = (page - 1) * SLOTS_PER_PAGE + slotIdx
  if absoluteIdx <= 12 then
    return 'F' .. tostring(absoluteIdx)
  elseif absoluteIdx <= 24 then
    return 'Shift+F' .. tostring(absoluteIdx - 12)
  else
    return 'Ctrl+F' .. tostring(absoluteIdx - 24)
  end
end

local function refreshRealHotkeySlots()
  if not rightControls then return end
  local pageBtn = rightControls:recursiveGetChildById('hkPageBtn')
  if pageBtn then
    pageBtn:setText(tostring(hotkeyPage) .. '/' .. tostring(TOTAL_HOTKEY_PAGES))
  end

  local defaults = (hotkeyPage == 1 and g_game.isOnline()) and getDefaultPage1Specs() or {}
  activeSlotSpecs = {}

  for i = 1, SLOTS_PER_PAGE do
    local slot = rightControls:recursiveGetChildById('hkSlot' .. i)
    if slot then
      local combo = getComboForSlot(hotkeyPage, i)
      local entry = (modules.game_hotkeys and modules.game_hotkeys.getHotkeyEntry)
        and modules.game_hotkeys.getHotkeyEntry(combo) or nil

      local itemWidget = slot:getChildById('slotItem')
      local spellWidget = slot:getChildById('slotSpell')
      local fallbackLabel = slot:getChildById('slotFallback')
      local countLabel = slot:getChildById('slotCount')

      if itemWidget then itemWidget:setVisible(false); itemWidget:setItem(nil) end
      if spellWidget then spellWidget:setVisible(false); spellWidget:setImageSource('') end
      if fallbackLabel then fallbackLabel:setText(''); fallbackLabel:setVisible(false) end
      if countLabel then countLabel:setText(''); countLabel:setVisible(false) end

      local spec = nil
      if entry and entry.itemId and entry.itemId > 0 then
        spec = { kind = 'hotkey', combo = combo, itemId = entry.itemId, subType = entry.subType, useType = entry.useType }
      elseif entry and entry.value and entry.value ~= '' then
        spec = { kind = 'hotkey', combo = combo, words = entry.value }
      elseif entry and entry.action then
        spec = { kind = 'hotkey', combo = combo, action = entry.action }
      elseif defaults[i] then
        spec = defaults[i]
        spec.combo = combo
      end

      activeSlotSpecs[i] = spec

      if spec and spec.itemId and spec.itemId > 0 then
        if itemWidget then
          itemWidget:setItemId(spec.itemId)
          itemWidget:setVisible(true)
        end
        local cnt = countPlayerItem(spec.itemId)
        if countLabel and cnt > 0 then
          countLabel:setText(tostring(cnt))
          countLabel:setVisible(true)
        end
      elseif spec and spec.words and spec.words ~= '' then
        local src, clip
        if Spells and Spells.getSpellIcon then
          src, clip = Spells.getSpellIcon(spec.words)
        end
        if src and spellWidget then
          spellWidget:setImageSource(src)
          if clip then spellWidget:setImageClip(clip) end
          spellWidget:setVisible(true)
        elseif fallbackLabel then
          fallbackLabel:setText(spec.words:sub(1, 5))
          fallbackLabel:setVisible(true)
        end
      else
        if fallbackLabel then
          local shortKey = combo:gsub('Shift%+', 'S'):gsub('Ctrl%+', 'C')
          fallbackLabel:setText(shortKey)
          fallbackLabel:setVisible(true)
        end
      end
    end
  end
end

local function executeMobileHotkeySlot(slotIdx)
  if not g_game.isOnline() then return end
  local spec = activeSlotSpecs[slotIdx]
  if not spec then
    if modules.game_hotkeys and modules.game_hotkeys.doKeyCombo then
      modules.game_hotkeys.doKeyCombo(getComboForSlot(hotkeyPage, slotIdx))
    end
    return
  end

  if spec.kind == 'hotkey' and modules.game_hotkeys and modules.game_hotkeys.doKeyCombo then
    modules.game_hotkeys.doKeyCombo(spec.combo)
    return
  end

  if spec.kind == 'spell' and spec.words and spec.words ~= '' then
    if modules.game_console and modules.game_console.sendMessage then
      modules.game_console.sendMessage(spec.words)
    else
      g_game.talk(spec.words)
    end
    return
  end

  if spec.kind == 'item' and spec.itemId and spec.itemId > 0 then
    local player = g_game.getLocalPlayer()
    if spec.useType == HOTKEY_MANAGER_USEONSELF and player then
      g_game.useInventoryItemWith(spec.itemId, player)
    elseif spec.useType == HOTKEY_MANAGER_USEONTARGET then
      local target = g_game.getAttackingCreature()
      if target then
        g_game.useInventoryItemWith(spec.itemId, target)
      elseif player then
        g_game.useInventoryItemWith(spec.itemId, player)
      end
    else
      g_game.useInventoryItem(spec.itemId)
    end
  end
end

local function hasOpenContainers()
  if not g_game.getContainers then return false end
  for _ in pairs(g_game.getContainers()) do
    return true
  end
  return false
end

local function updateTopRightDocking()
  if not mobileTopRightBar then return end
  local rightOffset = hasOpenContainers() and 182 or 4
  mobileTopRightBar:setMarginRight(rightOffset)
  if modules.game_inventory and modules.game_inventory.setMobileRightMargin then
    modules.game_inventory.setMobileRightMargin(rightOffset)
  end
  local eqBtn = mobileTopRightBar:getChildById('topEquipToggle')
  if eqBtn and modules.game_inventory and modules.game_inventory.isOpen then
    eqBtn:setChecked(modules.game_inventory.isOpen())
  end
  local lockBtn = mobileTopRightBar:getChildById('topLockBtn')
  if lockBtn and g_game.isSafeFight then
    lockBtn:setChecked(g_game.isSafeFight())
  end
end

local function applyControlScale()
  if not keypad or not rightControls then return end
  local s = clamp(controlScale, 0.75, 1.5)
  local padSize = math.floor(136 * s)
  local knobSize = math.floor(56 * s)
  keypad:setSize({ width = padSize, height = padSize })
  if keypad.pointer then
    keypad.pointer:setSize({ width = knobSize, height = knobSize })
  end

  local slotSz = math.floor(38 * s)
  local gap = math.max(2, math.floor(3 * s))
  local row4W = slotSz * 4 + gap * 3
  local row5W = slotSz * 5 + gap * 4
  local totalH = slotSz * 3 + gap * 2
  rightControls:setSize({ width = row5W, height = totalH })

  local hkRowTop = rightControls:getChildById('hkRowTop')
  local hkRowMid = rightControls:getChildById('hkRowMid')
  local combatRow = rightControls:getChildById('combatRow')
  if hkRowTop then hkRowTop:setSize({ width = row4W, height = slotSz }) end
  if hkRowMid then hkRowMid:setSize({ width = row4W, height = slotSz }) end
  if combatRow then combatRow:setSize({ width = row5W, height = slotSz }) end

  local pageBtn = rightControls:recursiveGetChildById('hkPageBtn')
  if pageBtn then pageBtn:setSize({ width = slotSz, height = slotSz }) end
  for i = 1, SLOTS_PER_PAGE do
    local slot = rightControls:recursiveGetChildById('hkSlot' .. i)
    if slot then slot:setSize({ width = slotSz, height = slotSz }) end
  end
  for _, id in ipairs({ 'btnLook', 'btnTurn', 'btnFollow', 'btnUse', 'btnAttack' }) do
    local b = rightControls:recursiveGetChildById(id)
    if b then b:setSize({ width = slotSz, height = slotSz }) end
  end

  if leftQuickCluster then
    local utilSz = math.floor(38 * s)
    local uGap = math.max(2, math.floor(4 * s))
    leftQuickCluster:setSize({ width = utilSz * 2 + uGap, height = utilSz * 2 + uGap })
    for _, id in ipairs({ 'quickStanceBtn', 'quickEquipBtn', 'quickBagBtn', 'quickChatBtn' }) do
      local b = leftQuickCluster:getChildById(id)
      if b then b:setSize({ width = utilSz, height = utilSz }) end
    end
  end
end

local function applyJoystickSide()
  if not keypad or not rightControls then return end
  keypad:breakAnchors()
  rightControls:breakAnchors()
  if leftQuickCluster then leftQuickCluster:breakAnchors() end

  if joystickSide == 'right' then
    keypad:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    keypad:addAnchor(AnchorRight, 'parent', AnchorRight)
    keypad:setMarginBottom(8)
    keypad:setMarginRight(10)
    keypad:setMarginLeft(0)

    if leftQuickCluster then
      leftQuickCluster:addAnchor(AnchorBottom, 'parent', AnchorBottom)
      leftQuickCluster:addAnchor(AnchorRight, 'keypad', AnchorLeft)
      leftQuickCluster:setMarginBottom(8)
      leftQuickCluster:setMarginRight(8)
      leftQuickCluster:setMarginLeft(0)
    end

    rightControls:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    rightControls:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    rightControls:setMarginBottom(6)
    rightControls:setMarginLeft(6)
    rightControls:setMarginRight(0)
  else
    keypad:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    keypad:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    keypad:setMarginBottom(8)
    keypad:setMarginLeft(10)
    keypad:setMarginRight(0)

    if leftQuickCluster then
      leftQuickCluster:addAnchor(AnchorBottom, 'parent', AnchorBottom)
      leftQuickCluster:addAnchor(AnchorLeft, 'keypad', AnchorRight)
      leftQuickCluster:setMarginBottom(8)
      leftQuickCluster:setMarginLeft(8)
      leftQuickCluster:setMarginRight(0)
    end

    rightControls:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    rightControls:addAnchor(AnchorRight, 'parent', AnchorRight)
    rightControls:setMarginBottom(6)
    rightControls:setMarginRight(6)
    rightControls:setMarginLeft(0)
  end
end

local function updateVitalsHud()
  if not mobileVitalsHud then return end
  local player = g_game.getLocalPlayer()
  if not player or not g_game.isOnline() then
    mobileVitalsHud:setVisible(false)
    return
  end
  mobileVitalsHud:setVisible(true)

  local hp = math.max(0, player:getHealth() or 0)
  local maxHp = math.max(1, player:getMaxHealth() or 1)
  local mp = math.max(0, player:getMana() or 0)
  local maxMp = math.max(1, player:getMaxMana() or 1)
  local level = player:getLevel() or 1
  local lvlPct = clamp(player:getLevelPercent() or 0, 0, 100)

  local hpTrack = mobileVitalsHud:getChildById('hpTrack')
  local hpFill = mobileVitalsHud:recursiveGetChildById('hpFill')
  local hpText = mobileVitalsHud:getChildById('hpText')
  if hpTrack and hpFill then
    local innerW = math.max(1, hpTrack:getWidth() - 2)
    hpFill:setWidth(math.floor(innerW * clamp(hp / maxHp, 0, 1)))
  end
  if hpText then hpText:setText(tostring(hp)) end

  local mpTrack = mobileVitalsHud:getChildById('mpTrack')
  local mpFill = mobileVitalsHud:recursiveGetChildById('mpFill')
  local mpText = mobileVitalsHud:getChildById('mpText')
  if mpTrack and mpFill then
    local innerW = math.max(1, mpTrack:getWidth() - 2)
    mpFill:setWidth(math.floor(innerW * clamp(mp / maxMp, 0, 1)))
  end
  if mpText then mpText:setText(tostring(mp)) end

  local xpTrack = mobileVitalsHud:getChildById('xpTrack')
  local xpFill = mobileVitalsHud:recursiveGetChildById('xpFill')
  if xpTrack and xpFill then
    local innerW = math.max(1, xpTrack:getWidth() - 2)
    xpFill:setWidth(math.floor(innerW * (lvlPct / 100.0)))
  end

  local metaLabel = mobileVitalsHud:getChildById('statsMetaLabel')
  if metaLabel then
    local fps = g_app.getFps and g_app.getFps() or 0
    local ping = (g_game.getPing and g_game.getPing()) or lastPingMs
    if ping and ping >= 0 then
      metaLabel:setText(string.format('Lv.%d  %dms  %dfps', level, ping, fps))
    else
      metaLabel:setText(string.format('Lv.%d  %dfps', level, fps))
    end
  end
end

local function updateTargetBar()
  if not mobileTargetBar then return end
  local target = g_game.isOnline() and g_game.getAttackingCreature() or nil
  local atkBtn = rightControls and rightControls:recursiveGetChildById('btnAttack') or nil
  if atkBtn then atkBtn:setOn(target ~= nil) end
  if not target then
    mobileTargetBar:setVisible(false)
    return
  end
  mobileTargetBar:setVisible(true)
  local pct = clamp(target:getHealthPercent() or 0, 0, 100)
  local nameLbl = mobileTargetBar:getChildById('targetNameLabel')
  local pctLbl = mobileTargetBar:getChildById('targetPctLabel')
  local track = mobileTargetBar:getChildById('targetHpTrack')
  local fill = mobileTargetBar:recursiveGetChildById('targetHpFill')
  if nameLbl then nameLbl:setText(target:getName() or 'Target') end
  if pctLbl then pctLbl:setText(tostring(pct) .. '%') end
  if track and fill then
    local innerW = math.max(1, track:getWidth() - 2)
    fill:setWidth(math.floor(innerW * (pct / 100.0)))
  end
end

local function updateStanceLabel()
  if not leftQuickCluster then return end
  local btn = leftQuickCluster:getChildById('quickStanceBtn')
  if not btn or not g_game.getFightMode then return end
  local mode = g_game.getFightMode()
  if mode == FightOffensive then
    btn:setText('OFF')
    btn:setColor('#ff8f85')
  elseif mode == FightDefensive then
    btn:setText('DEF')
    btn:setColor('#86c8ff')
  else
    btn:setText('BAL')
    btn:setColor('#f0e6bc')
  end
end

local function cycleCombatStance()
  if not g_game.isOnline() or not g_game.getFightMode or not g_game.setFightMode then return end
  local mode = g_game.getFightMode()
  if mode == FightOffensive then
    g_game.setFightMode(FightBalanced)
  elseif mode == FightBalanced then
    g_game.setFightMode(FightDefensive)
  else
    g_game.setFightMode(FightOffensive)
  end
  updateStanceLabel()
end

local function updateActionButtons()
  if not rightControls then return end
  local useBtn = rightControls:recursiveGetChildById('btnUse')
  local lookBtn = rightControls:recursiveGetChildById('btnLook')
  if useBtn then useBtn:setChecked(actionMode == 'use') end
  if lookBtn then lookBtn:setChecked(actionMode == 'look') end
end

local function syncSettingsHighlights()
  if not settingsDrawer then return end
  local function mark(id, active)
    local w = settingsDrawer:recursiveGetChildById(id)
    if w then w:setOn(active == true) end
  end
  mark('cfgScaleSm', math.abs(controlScale - 0.8) < 0.05)
  mark('cfgScaleMd', math.abs(controlScale - 1.0) < 0.05)
  mark('cfgScaleLg', math.abs(controlScale - 1.25) < 0.05)
  mark('cfgScaleXl', math.abs(controlScale - 1.5) < 0.05)
  mark('cfgJoyLeft', joystickSide == 'left')
  mark('cfgJoyRight', joystickSide == 'right')

  local zOff = (modules.game_interface and modules.game_interface.getMobileZoomOffset)
    and modules.game_interface.getMobileZoomOffset() or 0
  mark('cfgZoomIn', zOff < 0)
  mark('cfgZoomAuto', zOff == 0)
  mark('cfgZoomOut', zOff > 0)

  local fps = g_app.getMaxFps and g_app.getMaxFps() or 45
  mark('cfgFps30', fps <= 32)
  mark('cfgFps45', fps > 32 and fps <= 50)
  mark('cfgFps60', fps > 50)

  local dpr = tonumber(g_settings.getNumber('mobileMaxDpr', 1.75)) or 1.75
  mark('cfgDpr10', math.abs(dpr - 1.0) < 0.1)
  mark('cfgDpr15', math.abs(dpr - 1.5) < 0.1)
  mark('cfgDpr175', math.abs(dpr - 1.75) < 0.1)
  mark('cfgDpr20', math.abs(dpr - 2.0) < 0.1)

  local lightsBtn = settingsDrawer:recursiveGetChildById('cfgLights')
  if lightsBtn then
    lightsBtn:setText(drawLightsEnabled and tr('Lights: On') or tr('Lights: Off'))
    lightsBtn:setOn(drawLightsEnabled)
  end
  local fadeBtn = settingsDrawer:recursiveGetChildById('cfgFade')
  if fadeBtn then
    fadeBtn:setText(floorFadingEnabled and tr('Fade: On') or tr('Fade: Off'))
    fadeBtn:setOn(floorFadingEnabled)
  end
end

local function applyMapPerformanceOptions()
  local mapPanel = getMapPanel()
  if not mapPanel then return end
  if mapPanel.setDrawLights then
    mapPanel:setDrawLights(drawLightsEnabled)
  end
  if mapPanel.setFloorFading then
    mapPanel:setFloorFading(floorFadingEnabled and 250 or 0)
  end
end

local function closeMenuPanel()
  if mobileMenuPanel then mobileMenuPanel:setVisible(false) end
  if mobileTopRightBar then
    local menuBtn = mobileTopRightBar:getChildById('topMenuToggle')
    if menuBtn then menuBtn:setChecked(false) end
  end
end

local function updateOnlineVisibility()
  if not overlay then return end
  local isOnline = g_game.isOnline()
  if mobileLoginSettingsBtn then mobileLoginSettingsBtn:setVisible(not isOnline) end
  if mobileVitalsHud then mobileVitalsHud:setVisible(isOnline) end
  if mobileTopRightBar then mobileTopRightBar:setVisible(isOnline) end
  if not isOnline then
    closeMenuPanel()
    if mobileTargetBar then mobileTargetBar:setVisible(false) end
  end
  if keypad then keypad:setVisible(isOnline and controlsVisible) end
  if leftQuickCluster then leftQuickCluster:setVisible(isOnline and controlsVisible) end
  if rightControls then rightControls:setVisible(isOnline and controlsVisible) end
  if mobileMenuPanel then
    local padBtn = mobileMenuPanel:recursiveGetChildById('hudTogglePad')
    if padBtn then padBtn:setChecked(controlsVisible) end
  end
  if isOnline then
    overlay:raise()
    updateTopRightDocking()
    updateVitalsHud()
    updateTargetBar()
    updateStanceLabel()
    refreshRealHotkeySlots()
  end
end

local function attackNearestOrCycle()
  if not g_game.isOnline() then return end
  if modules.game_battle and modules.game_battle.getAttackableCreatures then
    local list = modules.game_battle.getAttackableCreatures()
    if list and #list > 0 then
      local current = g_game.getAttackingCreature()
      local nextTarget = list[1]
      for i = 1, #list do
        if list[i] == current then
          nextTarget = list[(i % #list) + 1]
          break
        end
      end
      if nextTarget then
        g_game.attack(nextTarget)
        return
      end
    end
  end
  if modules.game_battle and modules.game_battle.chooseNextCreature then
    modules.game_battle.chooseNextCreature()
  end
end

local function turnClockwise()
  if not g_game.isOnline() then return end
  local player = g_game.getLocalPlayer()
  if not player then return end
  local dir = player:getDirection()
  local nextDir = East
  if dir == North then nextDir = East
  elseif dir == East then nextDir = South
  elseif dir == South then nextDir = West
  else nextDir = North end
  g_game.turn(nextDir)
end

local function toggleFollowOrChase()
  if not g_game.isOnline() then return end
  local target = g_game.getAttackingCreature()
  if target then
    if g_game.getFollowingCreature() == target then
      g_game.cancelFollow()
    else
      g_game.follow(target)
    end
    return
  end
  if modules.game_hotkeys and modules.game_hotkeys.toggleChaseMode then
    modules.game_hotkeys.toggleChaseMode()
  elseif g_game.getChaseMode and g_game.setChaseMode then
    local mode = g_game.getChaseMode()
    g_game.setChaseMode(mode == ChaseOpponent and DontChase or ChaseOpponent)
  end
end

local function openMainBackpack()
  if not g_game.isOnline() then return end
  local player = g_game.getLocalPlayer()
  if not player then return end
  local bp = player:getInventoryItem(InventorySlotBack)
  if bp then
    g_game.use(bp)
  elseif modules.game_inventory and modules.game_inventory.toggle then
    modules.game_inventory.toggle()
  end
end

local function triggerTouchActionOnTile(pos)
  local mapPanel = getMapPanel()
  if not mapPanel then return false end
  local tile = mapPanel:getTile(pos)
  if not tile then return false end
  if actionMode == 'look' then
    local thing = tile:getTopLookThing()
    if thing then g_game.look(thing) end
    actionMode = nil
    updateActionButtons()
    return true
  elseif actionMode == 'use' then
    local thing = tile:getTopUseThing()
    if thing then g_game.use(thing) end
    actionMode = nil
    updateActionButtons()
    return true
  end
  return false
end

local function toggleMobileChat()
  if modules.game_console and modules.game_console.toggleMobileChat then
    modules.game_console.toggleMobileChat()
    return
  end
  if modules.game_console and modules.game_console.getConsole then
    local edit = modules.game_console.getConsole()
    if edit then
      edit:enable()
      edit:focus()
      edit:setCursorPos(-1)
    end
  end
end

local function toggleSettingsDrawer()
  if not settingsDrawer then return end
  local show = not settingsDrawer:isVisible()
  if show then closeMenuPanel() end
  settingsDrawer:setVisible(show)
  if show then
    clampSettingsDrawerToViewport()
    if overlay then overlay:raise() end
    settingsDrawer:raise()
    settingsDrawer:focus()
    syncSettingsHighlights()
  end
end

local function toggleMenuPanel()
  if not mobileMenuPanel then return end
  local show = not mobileMenuPanel:isVisible()
  if show and settingsDrawer then settingsDrawer:setVisible(false) end
  mobileMenuPanel:setVisible(show)
  if show then
    if overlay then overlay:raise() end
    mobileMenuPanel:raise()
  end
  if mobileTopRightBar then
    local menuBtn = mobileTopRightBar:getChildById('topMenuToggle')
    if menuBtn then menuBtn:setChecked(show) end
  end
end

local function wireOverlayButtons()
  if mobileLoginSettingsBtn then
    mobileLoginSettingsBtn.onClick = toggleSettingsDrawer
  end

  if mobileTopRightBar then
    local menuBtn = mobileTopRightBar:getChildById('topMenuToggle')
    local lockBtn = mobileTopRightBar:getChildById('topLockBtn')
    local setBtn = mobileTopRightBar:getChildById('topSettingsBtn')
    local eqBtn = mobileTopRightBar:getChildById('topEquipToggle')
    if menuBtn then menuBtn.onClick = toggleMenuPanel end
    if lockBtn then
      lockBtn.onClick = function()
        if g_game.isOnline() and g_game.isSafeFight and g_game.setSafeFight then
          g_game.setSafeFight(not g_game.isSafeFight())
          updateTopRightDocking()
        end
      end
    end
    if setBtn then setBtn.onClick = toggleSettingsDrawer end
    if eqBtn then
      eqBtn.onClick = function()
        closeMenuPanel()
        if modules.game_inventory and modules.game_inventory.toggle then
          modules.game_inventory.toggle()
        end
        updateTopRightDocking()
      end
    end
  end

  if mobileMenuPanel then
    local function bindMenu(id, fn)
      local btn = mobileMenuPanel:recursiveGetChildById(id)
      if btn then
        btn.onClick = function()
          closeMenuPanel()
          fn()
        end
      end
    end
    bindMenu('hudMinimap', function()
      if modules.game_minimap and modules.game_minimap.toggle then modules.game_minimap.toggle() end
    end)
    bindMenu('hudInventory', function()
      if modules.game_inventory and modules.game_inventory.toggle then modules.game_inventory.toggle() end
      updateTopRightDocking()
    end)
    bindMenu('hudBattle', function()
      if modules.game_battle and modules.game_battle.toggle then modules.game_battle.toggle() end
    end)
    bindMenu('hudSkills', function()
      if modules.game_skills and modules.game_skills.toggle then modules.game_skills.toggle() end
    end)
    bindMenu('hudVip', function()
      if modules.game_viplist and modules.game_viplist.toggle then modules.game_viplist.toggle() end
    end)
    bindMenu('hudHotkeys', function()
      if modules.game_hotkeys and modules.game_hotkeys.toggle then modules.game_hotkeys.toggle() end
    end)
    bindMenu('hudChat', toggleMobileChat)
    bindMenu('hudTogglePad', function()
      controlsVisible = not controlsVisible
      g_settings.set('mobileControlsVisible', controlsVisible)
      if keypadButton then keypadButton:setChecked(controlsVisible) end
      updateOnlineVisibility()
    end)
    bindMenu('hudSettings', toggleSettingsDrawer)
    bindMenu('hudLogout', function()
      if modules.game_interface and modules.game_interface.tryLogout then
        modules.game_interface.tryLogout()
      end
    end)
  end

  if leftQuickCluster then
    local stanceBtn = leftQuickCluster:getChildById('quickStanceBtn')
    local equipBtn = leftQuickCluster:getChildById('quickEquipBtn')
    local bagBtn = leftQuickCluster:getChildById('quickBagBtn')
    local chatBtn = leftQuickCluster:getChildById('quickChatBtn')
    if stanceBtn then stanceBtn.onClick = cycleCombatStance end
    if equipBtn then
      equipBtn.onClick = function()
        if modules.game_inventory and modules.game_inventory.toggle then modules.game_inventory.toggle() end
        updateTopRightDocking()
      end
    end
    if bagBtn then bagBtn.onClick = openMainBackpack end
    if chatBtn then chatBtn.onClick = toggleMobileChat end
  end

  if rightControls then
    local function bindAction(id, fn)
      local btn = rightControls:recursiveGetChildById(id)
      if btn then btn.onClick = fn end
    end
    bindAction('btnAttack', attackNearestOrCycle)
    bindAction('btnTurn', turnClockwise)
    bindAction('btnFollow', toggleFollowOrChase)
    bindAction('btnUse', function()
      if actionMode == 'use' then actionMode = nil else actionMode = 'use' end
      updateActionButtons()
    end)
    bindAction('btnLook', function()
      local target = g_game.getAttackingCreature()
      if target and actionMode ~= 'look' then
        g_game.look(target)
        return
      end
      if actionMode == 'look' then actionMode = nil else actionMode = 'look' end
      updateActionButtons()
    end)
    bindAction('hkPageBtn', function()
      hotkeyPage = (hotkeyPage % TOTAL_HOTKEY_PAGES) + 1
      refreshRealHotkeySlots()
    end)
    for i = 1, SLOTS_PER_PAGE do
      local idx = i
      bindAction('hkSlot' .. idx, function()
        executeMobileHotkeySlot(idx)
      end)
    end
  end

  if settingsDrawer then
    local function bindCfg(id, fn)
      local btn = settingsDrawer:recursiveGetChildById(id)
      if btn then btn.onClick = fn end
    end
    local function setScale(val)
      controlScale = val
      g_settings.set('mobileControlScale', val)
      applyControlScale()
      syncSettingsHighlights()
    end
    bindCfg('cfgScaleSm', function() setScale(0.8) end)
    bindCfg('cfgScaleMd', function() setScale(1.0) end)
    bindCfg('cfgScaleLg', function() setScale(1.25) end)
    bindCfg('cfgScaleXl', function() setScale(1.5) end)

    bindCfg('cfgJoyLeft', function()
      joystickSide = 'left'
      g_settings.set('mobileJoystickSide', 'left')
      applyJoystickSide()
      syncSettingsHighlights()
    end)
    bindCfg('cfgJoyRight', function()
      joystickSide = 'right'
      g_settings.set('mobileJoystickSide', 'right')
      applyJoystickSide()
      syncSettingsHighlights()
    end)

    bindCfg('cfgZoomIn', function()
      if modules.game_interface and modules.game_interface.setMobileZoomOffset then
        modules.game_interface.setMobileZoomOffset(-2)
      end
      syncSettingsHighlights()
    end)
    bindCfg('cfgZoomAuto', function()
      if modules.game_interface and modules.game_interface.setMobileZoomOffset then
        modules.game_interface.setMobileZoomOffset(0)
      end
      syncSettingsHighlights()
    end)
    bindCfg('cfgZoomOut', function()
      if modules.game_interface and modules.game_interface.setMobileZoomOffset then
        modules.game_interface.setMobileZoomOffset(2)
      end
      syncSettingsHighlights()
    end)

    local function setFps(val)
      g_settings.set('mobileMaxFps', val)
      if g_app.setMaxFps then g_app.setMaxFps(val) end
      syncSettingsHighlights()
    end
    bindCfg('cfgFps30', function() setFps(30) end)
    bindCfg('cfgFps45', function() setFps(45) end)
    bindCfg('cfgFps60', function() setFps(60) end)

    local function setDpr(val)
      g_settings.set('mobileMaxDpr', val)
      if g_window.setMaxPixelRatio then g_window.setMaxPixelRatio(val) end
      syncSettingsHighlights()
    end
    bindCfg('cfgDpr10', function() setDpr(1.0) end)
    bindCfg('cfgDpr15', function() setDpr(1.5) end)
    bindCfg('cfgDpr175', function() setDpr(1.75) end)
    bindCfg('cfgDpr20', function() setDpr(2.0) end)

    bindCfg('cfgLights', function()
      drawLightsEnabled = not drawLightsEnabled
      g_settings.set('mobileDrawLights', drawLightsEnabled)
      applyMapPerformanceOptions()
      syncSettingsHighlights()
    end)
    bindCfg('cfgFade', function()
      floorFadingEnabled = not floorFadingEnabled
      g_settings.set('mobileFloorFading', floorFadingEnabled)
      applyMapPerformanceOptions()
      syncSettingsHighlights()
    end)

    bindCfg('cfgWebFullscreen', function()
      if g_window.requestWebFullscreen then g_window.requestWebFullscreen() end
    end)
    bindCfg('cfgWebDiag', function()
      if g_window.toggleWebDiagnostics then g_window.toggleWebDiagnostics() end
    end)
    bindCfg('cfgWebDesktop', function()
      if g_window.openWebProfile then g_window.openWebProfile('desktop') end
    end)
    bindCfg('settingsCloseBtn', function()
      settingsDrawer:setVisible(false)
    end)
  end
end

local function onWindowResize()
  if applyingScale then return end
  removeEvent(initScaleEvent)
  initScaleEvent = scheduleEvent(function()
    initScaleEvent = nil
    applyResponsiveScale()
  end, 40)
end

local function onContainerOpened()
  updateTopRightDocking()
  refreshRealHotkeySlots()
end

local function onContainerClosed()
  scheduleEvent(function()
    updateTopRightDocking()
    refreshRealHotkeySlots()
  end, 20)
end

local function onCreatureHealthChange(creature)
  if creature and creature == g_game.getAttackingCreature() then
    updateTargetBar()
  end
end

local function onPingBack(ping)
  lastPingMs = tonumber(ping) or -1
end

local function onStatusTick()
  if not overlay then return end
  if g_game.isOnline() then
    updateVitalsHud()
    updateTargetBar()
    updateTopRightDocking()
    refreshRealHotkeySlots()
  end
  statusTickerEvent = scheduleEvent(onStatusTick, 700)
end

-- public functions
function init()
  if not g_app.isMobile() then return end

  controlScale = clamp(tonumber(g_settings.getNumber('mobileControlScale', 1.0)) or 1.0, 0.75, 1.5)
  local savedSide = g_settings.getString('mobileJoystickSide', 'left')
  joystickSide = (savedSide == 'right') and 'right' or 'left'
  controlsVisible = g_settings.getBoolean('mobileControlsVisible', true)
  drawLightsEnabled = g_settings.getBoolean('mobileDrawLights', true)
  floorFadingEnabled = g_settings.getBoolean('mobileFloorFading', true)

  local savedFps = tonumber(g_settings.getNumber('mobileMaxFps', 45)) or 45
  if g_app.setMaxFps then g_app.setMaxFps(clamp(savedFps, 20, 60)) end
  local savedDpr = tonumber(g_settings.getNumber('mobileMaxDpr', 1.75)) or 1.75
  if g_window.setMaxPixelRatio then g_window.setMaxPixelRatio(clamp(savedDpr, 1.0, 2.0)) end

  overlay = g_ui.displayUI('mobile')
  if not overlay then return end
  keypad = overlay:getChildById('keypad')
  leftQuickCluster = overlay:getChildById('leftQuickCluster')
  rightControls = overlay:getChildById('rightControls')
  mobileVitalsHud = overlay:getChildById('mobileVitalsHud')
  mobileTargetBar = overlay:getChildById('mobileTargetBar')
  mobileTopRightBar = overlay:getChildById('mobileTopRightBar')
  mobileMenuPanel = overlay:getChildById('mobileMenuPanel')
  mobileLoginSettingsBtn = overlay:getChildById('mobileLoginSettingsBtn')
  settingsDrawer = overlay:getChildById('mobileSettingsDrawer')
  overlay:raise()

  applyControlScale()
  applyJoystickSide()
  refreshRealHotkeySlots()
  wireOverlayButtons()
  syncSettingsHighlights()
  updateActionButtons()

  if modules.client_topmenu then
    zoomInButton = modules.client_topmenu.addLeftButton('zoomInButton', 'Zoom In', '/images/topbuttons/zoomin', function()
      g_app.scaleUp()
    end)
    zoomOutButton = modules.client_topmenu.addLeftButton('zoomOutButton', 'Zoom Out', '/images/topbuttons/zoomout', function()
      g_app.scaleDown()
    end)
    keypadButton = modules.client_topmenu.addLeftGameToggleButton('keypadButton', 'Keypad', '/images/topbuttons/keypad', function()
      controlsVisible = not controlsVisible
      g_settings.set('mobileControlsVisible', controlsVisible)
      keypadButton:setChecked(controlsVisible)
      updateOnlineVisibility()
    end)
    if keypadButton then keypadButton:setChecked(controlsVisible) end
  end

  initScaleEvent = scheduleEvent(applyResponsiveScale, 120)
  statusTickerEvent = scheduleEvent(onStatusTick, 700)

  connect(rootWidget, {
    onMousePress = onMousePress,
    onMouseRelease = onMouseRelease,
    onTouchPress = onTouchPress,
    onTouchRelease = onTouchRelease,
    onTouchMove = onGlobalTouchMove,
    onMouseMove = onMouseMove,
    onGeometryChange = onWindowResize
  })
  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd,
    onAttackingCreatureChange = updateTargetBar,
    onFightModeChange = updateStanceLabel,
    onSafeFightChange = updateTopRightDocking,
    onPingBack = onPingBack
  })
  connect(LocalPlayer, {
    onHealthChange = updateVitalsHud,
    onManaChange = updateVitalsHud,
    onLevelChange = updateVitalsHud,
    onInventoryChange = refreshRealHotkeySlots
  })
  connect(Container, {
    onOpen = onContainerOpened,
    onClose = onContainerClosed,
    onUpdateItem = refreshRealHotkeySlots,
    onRemoveItem = refreshRealHotkeySlots
  })
  connect(Creature, {
    onHealthPercentChange = onCreatureHealthChange
  })
  if keypad then
    connect(keypad, {
      onMousePress = onKeypadTouchPress,
      onTouchPress = onKeypadTouchPress,
      onTouchRelease = onKeypadTouchRelease,
      onMouseRelease = onKeypadTouchRelease,
      onMouseMove = onKeypadTouchMove
    })
  end

  updateOnlineVisibility()
end

function terminate()
  if not g_app.isMobile() or not overlay then return end
  removeEvent(keypadEvent)
  removeEvent(updateCursorEvent)
  removeEvent(initScaleEvent)
  removeEvent(statusTickerEvent)
  keypadEvent = nil
  updateCursorEvent = nil
  initScaleEvent = nil
  statusTickerEvent = nil

  disconnect(rootWidget, {
    onMousePress = onMousePress,
    onMouseRelease = onMouseRelease,
    onTouchPress = onTouchPress,
    onTouchRelease = onTouchRelease,
    onTouchMove = onGlobalTouchMove,
    onMouseMove = onMouseMove,
    onGeometryChange = onWindowResize
  })
  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd,
    onAttackingCreatureChange = updateTargetBar,
    onFightModeChange = updateStanceLabel,
    onSafeFightChange = updateTopRightDocking,
    onPingBack = onPingBack
  })
  disconnect(LocalPlayer, {
    onHealthChange = updateVitalsHud,
    onManaChange = updateVitalsHud,
    onLevelChange = updateVitalsHud,
    onInventoryChange = refreshRealHotkeySlots
  })
  disconnect(Container, {
    onOpen = onContainerOpened,
    onClose = onContainerClosed,
    onUpdateItem = refreshRealHotkeySlots,
    onRemoveItem = refreshRealHotkeySlots
  })
  disconnect(Creature, {
    onHealthPercentChange = onCreatureHealthChange
  })
  if keypad then
    disconnect(keypad, {
      onMousePress = onKeypadTouchPress,
      onTouchPress = onKeypadTouchPress,
      onTouchRelease = onKeypadTouchRelease,
      onMouseRelease = onKeypadTouchRelease,
      onMouseMove = onKeypadTouchMove
    })
  end
  if zoomInButton then zoomInButton:destroy(); zoomInButton = nil end
  if zoomOutButton then zoomOutButton:destroy(); zoomOutButton = nil end
  if keypadButton then keypadButton:destroy(); keypadButton = nil end
  overlay:destroy()
  overlay = nil
  keypad = nil
  leftQuickCluster = nil
  rightControls = nil
  mobileVitalsHud = nil
  mobileTargetBar = nil
  mobileTopRightBar = nil
  mobileMenuPanel = nil
  mobileLoginSettingsBtn = nil
  settingsDrawer = nil
end

function hide()
  if overlay then overlay:hide() end
end

function show()
  if overlay then overlay:show() end
end

function onGameStart()
  if not overlay then return end
  if settingsDrawer then settingsDrawer:setVisible(false) end
  closeMenuPanel()
  actionMode = nil
  updateActionButtons()
  applyMapPerformanceOptions()
  updateOnlineVisibility()
  if modules.game_interface and modules.game_interface.updateMobileLiteMapGeometry then
    modules.game_interface.updateMobileLiteMapGeometry()
  end
end

function onGameEnd()
  if not overlay then return end
  resetKeypadState()
  actionMode = nil
  updateActionButtons()
  updateOnlineVisibility()
end

function updateCursor()
  if not overlay or not overlay.cursor then return end
  removeEvent(updateCursorEvent)
  updateCursorEvent = nil
  if not g_mouse.isPressed(MouseTouch) or keypadActive then
    overlay.cursor:hide()
    return
  end
  local delta = g_clock.millis() - touchStart
  if delta > LONG_PRESS_MS then
    overlay.cursor:hide()
    return
  end
  if delta > 140 then
    overlay.cursor:show()
    overlay.cursor:setPercent(clamp(100 - ((delta - 140) * 100 / (LONG_PRESS_MS - 140)), 0, 100))
  end
  updateCursorEvent = scheduleEvent(updateCursor, 25)
end

function onMousePress(widget, pos, button)
  if not overlay then return end
  if button == MouseTouch then
    if keypad and keypad:isVisible() and keypad:containsPoint(pos) then
      return
    end
    touchStart = g_clock.millis()
    touchOrigin = { x = pos.x, y = pos.y }
    if overlay.cursor then
      overlay.cursor:setPosition({ x = pos.x - 26, y = pos.y - 26 })
      updateCursor()
    end
  end
end

function onTouchPress(widget, pos, button)
  if not overlay then return end
  if button ~= MouseTouch and keypad and keypad:isVisible() and keypad:containsPoint(pos) then
    onKeypadTouchPress(keypad, pos, button)
    return
  end
  if button == MouseTouch then
    onMousePress(widget, pos, button)
  end
end

function onMouseRelease(widget, pos, button)
  if not overlay then return end
  if button == MouseTouch then
    if overlay.cursor then overlay.cursor:hide() end
    removeEvent(updateCursorEvent)
    updateCursorEvent = nil
    if keypadActive and keypadTouchButton == MouseTouch then
      resetKeypadState()
      return
    end
    if actionMode and g_game.isOnline() and (g_clock.millis() - touchStart) < LONG_PRESS_MS then
      if isPointDirectlyOnMap(pos) and triggerTouchActionOnTile(pos) then
        if g_window.consumeTouchGesture then g_window.consumeTouchGesture() end
        return
      end
    end
  end
end

function onTouchRelease(widget, pos, button)
  if not overlay then return end
  if keypadActive and button == keypadTouchButton then
    resetKeypadState()
    return
  end
  if button == MouseTouch then
    onMouseRelease(widget, pos, button)
  end
end

function onGlobalTouchMove(widget, pos, moved, button)
  if not overlay then return end
  if keypadActive and button == keypadTouchButton then
    updateKeypadPosition(pos)
  end
end

function onMouseMove(widget, pos, offset)
  if not overlay then return end
  if keypadActive and keypadTouchButton == MouseTouch then
    updateKeypadPosition(pos)
    return
  end
  if overlay.cursor and overlay.cursor:isVisible() then
    local dist = math.max(math.abs(pos.x - touchOrigin.x), math.abs(pos.y - touchOrigin.y))
    if dist > 20 then
      overlay.cursor:hide()
      removeEvent(updateCursorEvent)
      updateCursorEvent = nil
    end
  end
end

function resetKeypadState()
  keypadActive = false
  keypadTouchButton = nil
  keypadMousePos = { x = 0.5, y = 0.5 }
  keypadTicks = 0
  removeEvent(keypadEvent)
  keypadEvent = nil
  if keypad and keypad.pointer then
    keypad.pointer:setMarginTop(0)
    keypad.pointer:setMarginLeft(0)
  end
end

function updateKeypadPosition(pos)
  if not keypad or not keypad:isVisible() then return end
  local w = math.max(1, keypad:getWidth())
  local h = math.max(1, keypad:getHeight())
  local nx = clamp((pos.x - keypad:getX()) / w, 0.0, 1.0)
  local ny = clamp((pos.y - keypad:getY()) / h, 0.0, 1.0)
  keypadMousePos = { x = nx, y = ny }

  local dx = nx - 0.5
  local dy = ny - 0.5
  local dist = math.sqrt(dx * dx + dy * dy)
  local maxR = 0.42
  if dist > maxR then
    dx = dx * (maxR / dist)
    dy = dy * (maxR / dist)
  end
  if keypad.pointer then
    keypad.pointer:setMarginLeft(math.floor(dx * w))
    keypad.pointer:setMarginTop(math.floor(dy * h))
  end
end

function onKeypadTouchPress(widget, pos, button)
  if not keypad or not keypad:isVisible() then return false end
  if button ~= MouseTouch and button ~= MouseTouch2 and button ~= MouseTouch3 and button ~= MouseLeftButton then
    return false
  end
  if button == MouseTouch and g_window.consumeTouchGesture then
    g_window.consumeTouchGesture()
  end
  keypadActive = true
  keypadTouchButton = button
  keypadTicks = 0
  if overlay and overlay.cursor then overlay.cursor:hide() end
  updateKeypadPosition(pos)
  executeWalk()
  return true
end

function onKeypadTouchRelease(widget, pos, button)
  if keypadActive and (button == keypadTouchButton or button == MouseTouch or button == MouseLeftButton) then
    resetKeypadState()
    return true
  end
  return false
end

function onKeypadTouchMove(widget, pos, offset)
  if keypadActive then
    updateKeypadPosition(pos)
    return true
  end
  return false
end

function executeWalk()
  removeEvent(keypadEvent)
  keypadEvent = nil
  if not keypadActive or not keypad or not keypad:isVisible() or not g_game.isOnline() then
    resetKeypadState()
    return
  end

  keypadEvent = scheduleEvent(executeWalk, 50)
  local dx = keypadMousePos.x - 0.5
  local dy = keypadMousePos.y - 0.5
  if math.sqrt(dx * dx + dy * dy) < DEADZONE then
    return
  end

  local angle = math.deg(math.atan2(dy, dx))
  if angle < 0 then angle = angle + 360 end

  local dir
  if angle >= 337.5 or angle < 22.5 then
    dir = East
  elseif angle < 67.5 then
    dir = SouthEast
  elseif angle < 112.5 then
    dir = South
  elseif angle < 157.5 then
    dir = SouthWest
  elseif angle < 202.5 then
    dir = West
  elseif angle < 247.5 then
    dir = NorthWest
  elseif angle < 292.5 then
    dir = North
  else
    dir = NorthEast
  end

  if modules.game_walking and modules.game_walking.walk then
    modules.game_walking.walk(dir, keypadTicks)
  elseif g_game.walk then
    g_game.walk(dir)
  end
  keypadTicks = keypadTicks + 1
end
