local window = nil

local appearanceGroup = nil
local colorModeGroup = nil
local colorBoxGroup = nil

local movementCheck = nil
local showFloorCheck = nil
local showOutfitCheck = nil
local showMountCheck = nil
local showAuraCheck = nil
local auraCheck = nil

local previewCreature = nil
local previewFamiliar = nil

local currentColorBox = nil
local globalRandomMount = nil
local lastFocusPreset = nil
local renamePresetWindow = nil
local showFamiliarCheck = nil

ignoreNextOutfitWindow = 0

local presetList = {}
local pendingStoreTryOn = nil

local tempOutfit = {}
local tempFamiliar = {type = 0}
local ServerData = {
  currentOutfit = {},
  outfits = {},
  mounts = {},
  familiars = {},
  wings = {},
  auras = {},
  shaders = {},
  healthBars = {},
  manaBars = {}
}

local AppearanceData = {
  "preset",
  "outfit",
  "mount",
  "familiar",
  "aura"
}

local function normalizeStoreTryOn(data)
  if type(data) ~= "table" then
    return nil
  end

  local kind = data.kind
  local id = tonumber(data.id) or 0
  if id <= 0 or (kind ~= "outfit" and kind ~= "mount") then
    return nil
  end

  return {
    kind = kind,
    id = id,
    offerId = tonumber(data.offerId) or 0,
    name = data.name or (kind == "mount" and "Store Mount" or "Store Outfit"),
    addons = tonumber(data.addons) or 3
  }
end

function setStoreTryOn(data)
  pendingStoreTryOn = normalizeStoreTryOn(data)
end

function clearStoreTryOn()
  pendingStoreTryOn = nil
end

local function consumeStoreTryOn()
  local data = pendingStoreTryOn
  pendingStoreTryOn = nil
  return data
end

local function hasAppearanceEntry(list, id)
  for _, data in ipairs(list or {}) do
    if tonumber(data[1]) == id then
      return true
    end
  end

  return false
end

local function applyStoreTryOn(data)
  if not data then
    return nil
  end

  if data.kind == "outfit" then
    if not hasAppearanceEntry(ServerData.outfits, data.id) then
      table.insert(ServerData.outfits, {data.id, data.name, data.addons, 1, data.offerId})
    end

    tempOutfit.type = data.id
    tempOutfit.addons = data.addons
    return window.appearance.outfitCheck
  end

  if not hasAppearanceEntry(ServerData.mounts, data.id) then
    table.insert(ServerData.mounts, {data.id, data.name, data.offerId})
  end

  tempOutfit.mount = data.id
  showMountCheck:setEnabled(true)
  showMountCheck:setChecked(true)
  if window.appearance.mountCheck then
    window.appearance.mountCheck:setEnabled(true)
  end
  return window.appearance.mountCheck
end

local function getOutfitStoreInfo(data)
  local mode = tonumber(data[4]) or 0
  local offerId = tonumber(data[5]) or 0

  if data[5] == nil then
    offerId = mode
    mode = offerId > 0 and 1 or 0
  end

  return mode, offerId
end

local function getStoreOutfitInfo(outfitId)
  outfitId = tonumber(outfitId) or 0
  for _, data in pairs(ServerData.outfits) do
    if tonumber(data[1]) == outfitId then
      return getOutfitStoreInfo(data)
    end
  end

  return 0, 0
end

local function openStoreOutfit(offerId)
  offerId = tonumber(offerId) or 0
  window:hide()
  g_game.openStore()
  if offerId > 0 then
    g_game.requestStoreOffers(4, "", offerId)
  else
    g_game.requestStoreOffers(2, "Outfits", 0)
  end
end

function init()
  connect(
    g_game,
    {
      onOpenOutfitWindow = create,
      onGameEnd = destroy
    }
  )
end

function terminate()
  disconnect(
    g_game,
    {
      onOpenOutfitWindow = create,
      onGameEnd = destroy
    }
  )
  destroy()
end

function onMovementChange(checkBox, checked)
  previewCreature:setAnimate(checked)
  previewCreature:setIdleAnimate(not checked)
  previewCreature:setStaticWalking(checked)
end

function onShowFloorChange(checkBox, checked)
  if checked then
		window.preview.previewoutfit:setImageSource('/images/game/outfit_ground')
	else
		window.preview.previewoutfit:setImageSource('/game_cyclopedia/images/ui/panel-background')
	end
end

function onShowFamiliarChange(checkBox, checked)
  previewFamiliar:setVisible(checked)
  updatePreview()
  if checked then
    previewCreature:setMarginRight(63)
  else
    previewCreature:setMarginRight(0)
  end
end

function onShowAuraChange(checkBox, checked)
  updatePreview()
end

function onOnlyMineThings()
  if window.appearance.outfitCheck:isChecked() then
    showOutfits()
  elseif window.appearance.mountCheck:isChecked() then
    showMounts()
  end
end

function onMountCheckChange(checkBox, checked)
  showOutfitCheck:setEnabled(checked)
  if checked then
    showAuraCheck:setChecked(false)
  end

  updatePreview()
end

function onShowOutfitCheckChange(checkBox, checked)
  updatePreview(not checked)
end

function create(currentOutfit, outfitList, mountList, familiarList, wingList, auraList, shaderList, healthBarList, manaBarList)
  if ignoreNextOutfitWindow and g_clock.millis() < ignoreNextOutfitWindow + 1000 then
    return
  end

  currentOutfit = currentOutfit or {}
  outfitList = outfitList or {}
  mountList = mountList or {}
  familiarList = familiarList or {}
  wingList = wingList or {}
  auraList = auraList or {}
  shaderList = shaderList or {}
  healthBarList = healthBarList or {}
  manaBarList = manaBarList or {}

  currentOutfit.addons = tonumber(currentOutfit.addons) or 0
  currentOutfit.mount = tonumber(currentOutfit.mount) or 0
  currentOutfit.familiar = tonumber(currentOutfit.familiar) or 0
  currentOutfit.aura = tonumber(currentOutfit.aura) or 0
  currentOutfit.auraCategory = tonumber(currentOutfit.auraCategory) or 0
  currentOutfit.auraId = tonumber(currentOutfit.auraId) or 0

  if window then
    destroy()
  end

  loadSettings()

  for i = 1, #auraList do
    local auraData = auraList[i]
    if auraData[3] == currentOutfit.aura then
      currentOutfit.auraId = auraData[1]
      break
    end
  end

  ServerData = {
    currentOutfit = currentOutfit,
    outfits = outfitList,
    mounts = mountList,
    familiars = familiarList,
    wings = wingList,
    auras = auraList,
    shaders = shaderList,
    healthBars = healthBarList,
    manaBars = manaBarList
  }

  window = g_ui.displayUI("outfitwindow")
  g_client.setInputLockWidget(window)

  for _, appKey in ipairs(AppearanceData) do
    updateAppearanceText(appKey, "None")
  end

  previewCreature = window.preview.previewoutfit.creature
  previewFamiliar = window.preview.previewoutfit.familiar
  previewFamiliar:setVisible(false)

  if currentOutfit.familiar == 0 and not table.empty(familiarList) then
    tempFamiliar = {type = familiarList[1][1]}
    currentOutfit.familiar = familiarList[1][1]
    previewFamiliar:setOutfit(tempFamiliar)
  else
    tempFamiliar = {type = currentOutfit.familiar}
    previewFamiliar:setOutfit(tempFamiliar)
  end

  tempOutfit = table.copy(currentOutfit)

  if g_game.getFeature(GamePlayerMounts) then
    local isMount = g_game.getLocalPlayer():isMounted()
    if isMount then
      window.configure.mount.mountCheck:setEnabled(true)
      window.configure.mount.mountCheck:setChecked(true)
    else
      window.configure.mount.mountCheck:setEnabled(#mountList > 0)
      window.configure.mount.mountCheck:setChecked(isMount and currentOutfit.mount > 0)
    end
  end

  if currentOutfit.addons == 3 then
    window.configure.addon1.addon1Check:setChecked(true)
    window.configure.addon2.addon2Check:setChecked(true)
  elseif currentOutfit.addons == 2 then
    window.configure.addon1.addon1Check:setChecked(false)
    window.configure.addon2.addon2Check:setChecked(true)
  elseif currentOutfit.addons == 1 then
    window.configure.addon1.addon1Check:setChecked(true)
    window.configure.addon2.addon2Check:setChecked(false)
  end
  window.configure.addon1.addon1Check.onCheckChange = onAddonChange
  window.configure.addon2.addon2Check.onCheckChange = onAddonChange

  window.configure.randommount.randomCheck:setChecked(false)
  globalRandomMount = false

  window.configure.randommount.randomCheck.onCheckChange = onRandomMountChange

  configureAddons(currentOutfit.addons)
  local storeTryOn = consumeStoreTryOn()

  movementCheck = window.preview.movement.movementCheck
  showFloorCheck = window.preview.showfloor.showfloorCheck
  showOutfitCheck = window.preview.showoutfit.showoutfitCheck
  showMountCheck = window.configure.mount.mountCheck
  showFamiliarCheck = window.preview.showfamiliar.showfamiliarCheck
  showAuraCheck = window.preview.showAura.showAuraCheck
  auraCheck = window.configure.aura.auraCheck

  showOutfitCheck.onCheckChange = onShowOutfitCheckChange
  showMountCheck.onCheckChange = onMountCheckChange
  movementCheck.onCheckChange = onMovementChange
  showFloorCheck.onCheckChange = onShowFloorChange
  showFamiliarCheck.onCheckChange = onShowFamiliarChange
  showAuraCheck.onCheckChange = onShowAuraChange

  movementCheck:setChecked(false)
  showFloorCheck:setChecked(true)

  showFamiliarCheck:setEnabled(not table.empty(familiarList))
  if table.empty(familiarList) then
    window.appearance.familiarCheck:setEnabled(false)
  else
    window.appearance.familiarCheck:setEnabled(true)
  end

  showAuraCheck:setEnabled(not table.empty(auraList))
  auraCheck:setEnabled(not table.empty(auraList))
  if table.empty(auraList) then
    window.appearance.auraCheck:setEnabled(false)
  else
    window.appearance.auraCheck:setEnabled(true)
  end

  showOutfitCheck:setChecked(true)
  showMountCheck:setChecked(currentOutfit.mount > 0)
  showFamiliarCheck:setChecked(false)
  showAuraCheck:setChecked(currentOutfit.aura > 0)
  window.configure.aura.auraCheck:setChecked(currentOutfit.aura > 0)
  local storeTryOnAppearance = applyStoreTryOn(storeTryOn)

  colorBoxGroup = UIRadioGroup.create()
  for j = 0, 6 do
    for i = 0, 18 do
      local colorBox = g_ui.createWidget("ColorBox", window.appearance.panelcolor)
      local outfitColor = getOutfitColor(j * 19 + i)
      colorBox:setBackgroundColor(outfitColor)
      colorBox:setId("colorBox" .. j * 19 + i)
      colorBox.colorId = j * 19 + i

      if colorBox.colorId == currentOutfit.head then
        currentColorBox = colorBox
        colorBox:setChecked(true)
        currentColorBox:setBorderWidth(1)
        currentColorBox:setBorderColor("white")
      end
      colorBoxGroup:addWidget(colorBox)
    end
  end

  showOutfitCheck:setEnabled(mount)
  colorBoxGroup.onSelectionChange = onColorCheckChange

  appearanceGroup = UIRadioGroup.create()
  appearanceGroup:addWidget(window.appearance.presetCheck)
  appearanceGroup:addWidget(window.appearance.outfitCheck)
  appearanceGroup:addWidget(window.appearance.mountCheck)
  appearanceGroup:addWidget(window.appearance.familiarCheck)
  appearanceGroup:addWidget(window.appearance.auraCheck)

  appearanceGroup.onSelectionChange = onAppearanceChange

  colorModeGroup = UIRadioGroup.create()
  colorModeGroup:addWidget(window.appearance.panelbar.HeadButton)
  colorModeGroup:addWidget(window.appearance.panelbar.PrimaryButton)
  colorModeGroup:addWidget(window.appearance.panelbar.SecondaryButton)
  colorModeGroup:addWidget(window.appearance.panelbar.DetailButton)

  colorModeGroup.onSelectionChange = onColorModeChange
  colorModeGroup:selectWidget(window.appearance.panelbar.HeadButton)

  updatePreview()
  updateAppearanceTexts(currentOutfit)

  if not table.empty(ServerData.auras) then
    if currentOutfit.auraId == 0 then
      local data = ServerData.auras[1]
      currentOutfit.aura = data[3]
      currentOutfit.auraCategory = data[2]
      currentOutfit.auraId = data[1]
      updateAppearanceText("aura", data[4])
    end
  end

  appearanceGroup:selectWidget(storeTryOnAppearance or window.appearance.outfitCheck)
end

function destroy()
  if window then
    g_client.setInputLockWidget()
    window:destroy()
    window = nil

    movementCheck = nil
    showFloorCheck = nil
    showOutfitCheck = nil
    showMountCheck = nil
    showFamiliarCheck = nil
    showAuraCheck = nil

    currentColorBox = nil

    if appearanceGroup then
      appearanceGroup:destroy()
    end
    appearanceGroup = nil
    if colorModeGroup then
      colorModeGroup:destroy()
    end
    colorModeGroup = nil
    if colorBoxGroup then
      colorBoxGroup:destroy()
    end
    colorBoxGroup = nil

    ServerData = {
      currentOutfit = {},
      outfits = {},
      mounts = {},
      familiars = {},
      wings = {},
      auras = {},
      shaders = {},
      healthBars = {},
      manaBars = {},
    }

    saveSettings()
    settings = {}
  end
end

function configureAddons(addons)
  local hasAddon1 = addons == 1 or addons == 3
  local hasAddon2 = addons == 2 or addons == 3
  window.configure.addon1.addon1Check:setEnabled(hasAddon1)
  window.configure.addon2.addon2Check:setEnabled(hasAddon2)

  window.configure.addon1.addon1Check.onCheckChange = nil
  window.configure.addon2.addon2Check.onCheckChange = nil
  window.configure.addon1.addon1Check:setChecked(false)
  window.configure.addon2.addon2Check:setChecked(false)
  if tempOutfit.addons == 3 then
    window.configure.addon1.addon1Check:setChecked(true)
    window.configure.addon2.addon2Check:setChecked(true)
  elseif tempOutfit.addons == 2 then
    window.configure.addon1.addon1Check:setChecked(false)
    window.configure.addon2.addon2Check:setChecked(true)
  elseif tempOutfit.addons == 1 then
    window.configure.addon1.addon1Check:setChecked(true)
    window.configure.addon2.addon2Check:setChecked(false)
  end
  window.configure.addon1.addon1Check.onCheckChange = onAddonChange
  window.configure.addon2.addon2Check.onCheckChange = onAddonChange
end

function newPreset()
  local outfitPreset = presetList["customiseCharacterPresets"]
  outfitPreset[#outfitPreset + 1] = {
    ["mount"] = {
      ["color"] = { ["detail"] = tempOutfit.mountFeet, ["head"] = tempOutfit.mountHead, ["legs"] = tempOutfit.mountLegs, ["torso"] = tempOutfit.mountBody},
      ["id"] = window.configure.mount.mountCheck:isChecked() and tempOutfit.mount or 0
    },
    ["name"] = "Preset",
    ["outfit"] = {
      ["color"] = { ["detail"] = tempOutfit.feet, ["head"] = tempOutfit.head, ["legs"] = tempOutfit.legs, ["torso"] = tempOutfit.body},
      ["id"] = tempOutfit.type,
      ["firstAddOn"] = window.configure.addon1.addon1Check:isChecked(),
      ["secondAddOn"] = window.configure.addon2.addon2Check:isChecked(),
    },
    ["summon"] = { ["id"] = showFamiliarCheck:isChecked() and tempOutfit.familiar or 0}
  }

  showPresets()
end

function deletePreset()
  if not lastFocusPreset then
    return
  end

  local widgetIndex = lastFocusPreset:getActionId()
  table.remove( presetList["customiseCharacterPresets"], widgetIndex)
  window.presetBar.renameButton:setEnabled(false)
  window.presetBar.saveButton:setEnabled(false)
  window.presetBar.deleteButton:setEnabled(false)
  window.okButton:setEnabled(true)
  lastFocusPreset:setBorderColor("alpha")
  lastFocusPreset:setBorderWidth("0")
  updateAppearanceText("preset", "None")
  lastFocusPreset = nil
  showPresets()
end

function renamePreset()
  if not lastFocusPreset then
    return
  end

	window:hide()
	renamePresetWindow = g_ui.loadUI('renamePreset', g_ui.getRootWidget())
	renamePresetWindow:setText("Rename Preset")
	renamePresetWindow.contentPanel.text:setVisible(false)

  renamePresetWindow.contentPanel.target:setText(lastFocusPreset.name:getText())
	renamePresetWindow.contentPanel.okButton.onClick = function()
		local text = renamePresetWindow.contentPanel.target:getText()
		if #text == 0 then
			text = "Preset"
		end

    updateAppearanceText("preset", text)
    lastFocusPreset.name:setText(text)
    presetList["customiseCharacterPresets"][lastFocusPreset:getActionId()]["name"] = text
		renamePresetWindow:destroy()
		window:show()
	end

	renamePresetWindow.contentPanel.cancelButton.onClick = function()
		renamePresetWindow:destroy()
		window:show()
	end
end

function onAppearanceChange(widget, selectedWidget)
  local id = selectedWidget:getId()
  window.filter_outfits.onlyCheck:setChecked(false)

  if id == "presetCheck" then
    showPresets()
  elseif id == "outfitCheck" then
    showOutfits()
  elseif id == "mountCheck" then
    showMounts()
  elseif id == "familiarCheck" then
    showFamiliars()
  elseif id == "auraCheck" then
    showAuras()
  end
end

function onHidePresetWindow()
  window.presetList.selectionList:destroyChildren()
  window.presetList:setVisible(false)
  window.ScrollBar:setVisible(true)
  window.filter_outfits:setVisible(true)
  window.presetBar:setVisible(false)
  window.okButton:setEnabled(true)
  window.presetBar.renameButton:setEnabled(false)
  window.presetBar.saveButton:setEnabled(false)
  window.presetBar.deleteButton:setEnabled(false)
  window.appearance.grayHover:setVisible(false)
end

function showPresets()
  window.ScrollBar.selectionList:destroyChildren()
  window.presetList.selectionList:destroyChildren()
  window.ScrollBar:setVisible(false)
  window.filter_outfits:setVisible(false)
  window.presetList:setVisible(true)
  window.presetBar:setVisible(true)

  local outfitPreset = presetList["customiseCharacterPresets"]
  for i, data in pairs(outfitPreset) do
    local widget = g_ui.createWidget("PresetButton", window.presetList.selectionList)

    widget:setActionId(i)
    widget.outfit:setOutfit(getPresetOutfit(data))
    widget.name:setText(data["name"])

    local summonId = data["summon"] and (tonumber(data["summon"]["id"]) or 0) or 0
    if summonId > 0 then
      widget.outfit:setMarginRight(32)
      widget.familiar:setOutfit({type = summonId})
      widget.familiar:setVisible(true)
    end

    local storeMount = getStoreMount(widget.outfit:getOutfit().mount)
    local storeOutfitMode = getStoreOutfitInfo(widget.outfit:getOutfit().type)
    if storeMount > 0 or storeOutfitMode ~= 0 then
      widget:setImageSource("/images/ui/big-dark-button")
      widget.info:setVisible(true)
    end

    widget.onClick = onPresetSelect
  end

  window.presetList.selectionList:focusChild(nil)
end

function showOutfits(searchText)
  onHidePresetWindow()
  window.ScrollBar.selectionList.onChildFocusChange = nil
  window.ScrollBar.selectionList:destroyChildren()
  window.filter_outfits.onlyCheck:setEnabled(true)

  local onlyMine = window.filter_outfits.onlyCheck:isChecked()

  local availableOutfits = {}
  local lockedOutfits = {}
  for _, data in pairs(ServerData.outfits) do
    local storeMode = getOutfitStoreInfo(data)
    if storeMode == 0 then
        table.insert(availableOutfits, data)
    else
        table.insert(lockedOutfits, data)
    end
  end

  if not onlyMine then
    for _, data in ipairs(lockedOutfits) do
    table.insert(availableOutfits, data)
    end
  end

  local focused = nil
  for _, outfitData in ipairs(availableOutfits) do
    if searchText and not matchText(searchText, outfitData[2]) then
      goto continue
    end

    local button = g_ui.createWidget("SelectionButton", window.ScrollBar.selectionList)
    button:setId(outfitData[1])

    local outfit = table.copy(previewCreature:getOutfit())
    outfit.type = outfitData[1]
    outfit.addons = outfitData[3]
    outfit.mount = 0
    button.outfit:setOutfit(outfit)
    button.name:setText(outfitData[2])

    local storeMode, storeOffer = getOutfitStoreInfo(outfitData)
    if storeMode ~= 0 then
        button:setImageSource("/images/ui/large_blue_button")
        button.storeMode = storeMode
        button.storeOfferId = storeOffer
        if storeOffer > 0 then
          button:setActionId(storeOffer)
        end
    end

    if tempOutfit.type == outfitData[1] then
      focused = outfitData[1]
      configureAddons(outfitData[3])
    end

    :: continue ::
  end

  local focusedWidget = focused and window.ScrollBar.selectionList[focused] or nil

  window.appearance.grayHover:setVisible(false)
  window.ScrollBar.selectionList.onChildFocusChange = onOutfitSelect
  window.ScrollBar.selectionList:show()
  if focusedWidget then
    focusedWidget:focus()
    window.ScrollBar.selectionList:ensureChildVisible(focusedWidget, {x = 0, y = 196})
    onOutfitSelect(window.ScrollBar.selectionList, focusedWidget, nil, KeyboardFocusReason)
  end
end

function showMounts(searchText)
  onHidePresetWindow()
  window.ScrollBar.selectionList.onChildFocusChange = nil
  window.ScrollBar.selectionList:destroyChildren()
  window.filter_outfits.onlyCheck:setEnabled(true)

  local onlyMine = window.filter_outfits.onlyCheck:isChecked()

  local availableMounts = {}
  local lockedMounts = {}
  for _, data in pairs(ServerData.mounts) do
    if (tonumber(data[3]) or 0) == 0 then
      table.insert(availableMounts, data)
    else
      table.insert(lockedMounts, data)
    end
  end

  if not onlyMine then
    for _, data in ipairs(lockedMounts) do
      table.insert(availableMounts, data)
    end
  end

  local focused = nil
  for _, mountData in ipairs(availableMounts) do
    if searchText and not matchText(searchText, mountData[2]) then
      goto continue
    end

    local button = g_ui.createWidget("SelectionButton", window.ScrollBar.selectionList)
    button:setId(mountData[1])

    button.outfit:setOutfit({type = mountData[1]})
    button.outfit:setCenter(true)
    button.name:setText(mountData[2])
    if button.name:isTextWraped() then
      button.outfit:setMarginBottom(18)
    end

    local storeOffer = tonumber(mountData[3]) or 0
    if storeOffer > 0 then
        button:setImageSource("/images/ui/large_blue_button")
        button:setActionId(storeOffer)
    end

    if tempOutfit.mount == mountData[1] then
      focused = mountData[1]
      if not button.outfit:isColoredMount() then
        window.appearance.grayHover:setVisible(true)
      end
    end

    :: continue ::
  end

  if #ServerData.mounts == 1 then
    window.ScrollBar.selectionList:focusChild(nil)
  end

  local focusedWidget = focused and window.ScrollBar.selectionList[focused] or nil

  window.ScrollBar.selectionList.onChildFocusChange = onMountSelect
  window.ScrollBar.selectionList:show()
  if focusedWidget then
    focusedWidget:focus()
    window.ScrollBar.selectionList:ensureChildVisible(focusedWidget, {x = 0, y = 196})
    onMountSelect(window.ScrollBar.selectionList, focusedWidget, nil, KeyboardFocusReason)
  end
end

function showFamiliars()
  onHidePresetWindow()
  window.ScrollBar.selectionList.onChildFocusChange = nil
  window.ScrollBar.selectionList:destroyChildren()
  window.filter_outfits.onlyCheck:setEnabled(false)

  local focused = nil
  for _, mountData in ipairs(ServerData.familiars) do
    local button = g_ui.createWidget("SelectionButton", window.ScrollBar.selectionList)
    button:setId(mountData[1])

    button.outfit:setOutfit({type = mountData[1]})
    button.outfit:setCenter(true)
    button.name:setText(mountData[2])
    if tempOutfit.familiar == mountData[1] then
      focused = mountData[1]
    end
  end

  if #ServerData.familiars == 1 then
    window.ScrollBar.selectionList:focusChild(nil)
  end

  if focused ~= nil then
    local w = window.ScrollBar.selectionList[focused]
    w:focus()
    window.ScrollBar.selectionList:ensureChildVisible(w, {x = 0, y = 196})
  end

  window.appearance.grayHover:setVisible(true)
  window.ScrollBar.selectionList.onChildFocusChange = onFamiliarSelect
  window.ScrollBar.selectionList:show()
end

function showAuras()
  onHidePresetWindow()
  window.ScrollBar.selectionList.onChildFocusChange = nil
  window.ScrollBar.selectionList:destroyChildren()
  window.filter_outfits.onlyCheck:setEnabled(false)

  local focused = nil
  for _, auraData in ipairs(ServerData.auras) do
    local button = g_ui.createWidget("SelectionButton", window.ScrollBar.selectionList)
    button:setId(auraData[1])

    button.aura = auraData[3]
    button.auraCategory = auraData[2]

    local outfit = table.copy(previewCreature:getOutfit())
    outfit.aura = auraData[3]
    outfit.auraCategory = auraData[2]
    button.outfit:setOutfit(outfit)
    button.outfit:setCenter(true)
    button.outfit:setAnimate(true)
    button.name:setText(auraData[4])
    if tempOutfit.aura == auraData[3] then
      focused = auraData[1]
    end
  end

  if #ServerData.auras == 1 then
    window.ScrollBar.selectionList:focusChild(nil)
  end

  window.appearance.grayHover:setVisible(true)
  window.ScrollBar.selectionList.onChildFocusChange = onAuraSelect
  window.ScrollBar.selectionList:show()

  if focused ~= nil then
    local w = window.ScrollBar.selectionList[focused]
    w:focus()
    window.ScrollBar.selectionList:ensureChildVisible(w, {x = 0, y = 196})
  else
    if not table.empty(ServerData.auras) then
      if tempOutfit.aura == 0 then
        updateAppearanceText("aura", ServerData.auras[1][4])
        window.ScrollBar.selectionList:focusChild(window.ScrollBar.selectionList:getFirstChild())
      end
    end
  end

end

function onPresetSelect(widget)
  if not widget then
    return true
  end

  if widget == lastFocusPreset then
    return true
  end

  if lastFocusPreset then
    lastFocusPreset:setBorderColor("alpha")
    lastFocusPreset:setBorderWidth("0")
  end

  lastFocusPreset = widget
  lastFocusPreset:setBorderColor("white")
  lastFocusPreset:setBorderWidth("1")

  tempOutfit = table.copy(widget.outfit:getOutfit())

  if tempOutfit.mount > 0 then
    showMountCheck:setChecked(true)
  else
    showMountCheck:setChecked(false)
  end

  if tempOutfit.familiar > 0 then
    showFamiliarCheck:setChecked(true)
    previewFamiliar:setOutfit({type = tempOutfit.familiar})
  else
    showFamiliarCheck:setChecked(false)
  end

  if tempOutfit.aura > 0 then
    showAuraCheck:setChecked(true)
    previewFamiliar:setOutfit({type = tempOutfit.aura})
  else
    showAuraCheck:setChecked(false)
  end

  local storeMount = getStoreMount(tempOutfit.mount)
  if storeMount > 0 then
    window.appearance.mount:setImageSource("/images/ui/hlarge-blue-button")
    window.appearance.mount.purse:setVisible(true)
    window.appearance.mount.onClick = function() window:hide() g_game.openStore() g_game.requestStoreOffers(4, "", storeMount) end
  else
    window.appearance.mount:setImageSource("/images/ui/pressed-large-button")
    window.appearance.mount.purse:setVisible(false)
    window.appearance.mount.onClick = nil
  end

  local storeOutfitMode, storeOutfit = getStoreOutfitInfo(tempOutfit.type)
  if storeOutfitMode ~= 0 then
    window.appearance.outfit:setImageSource("/images/ui/hlarge-blue-button")
    window.appearance.outfit.purse:setVisible(true)
    window.appearance.outfit.onClick = function() openStoreOutfit(storeOutfit) end
  else
    window.appearance.outfit:setImageSource("/images/ui/pressed-large-button")
    window.appearance.outfit.purse:setVisible(false)
    window.appearance.outfit.onClick = nil
  end

  window.okButton:setEnabled(true)
  if storeMount > 0 or storeOutfit > 0 then
    window.okButton:setEnabled(false)
  end

  window.presetBar.renameButton:setEnabled(true)
  window.presetBar.saveButton:setEnabled(true)
  window.presetBar.deleteButton:setEnabled(true)
  window.appearance.grayHover:setVisible(true)

  updatePreview()
  updateAppearanceTexts(tempOutfit)
  updateAppearanceText("preset", widget.name:getText())
end

function onOutfitSelect(list, focusedChild, unfocusedChild, reason)
  if focusedChild then
    local outfitType = tonumber(focusedChild:getId())
    local outfit = focusedChild.outfit:getOutfit()
    tempOutfit.type = outfit.type
    tempOutfit.addons = outfit.addons
    showOutfitCheck:setChecked(true)

    configureAddons(outfit.addons)
    updatePreview()

    updateAppearanceText("outfit", focusedChild.name:getText())
		window.ScrollBar.selectionList:ensureChildVisible(focusedChild, {x = 0, y = 2})

    local storeMode = tonumber(focusedChild.storeMode) or 0
    local storeOffer = tonumber(focusedChild.storeOfferId) or focusedChild:getActionId() or 0
		if storeMode ~= 0 or storeOffer > 0 then
			window.appearance.outfit:setImageSource("/images/ui/hlarge-blue-button")
      window.appearance.outfit.purse:setVisible(true)
      window.appearance.outfit.onClick = function() openStoreOutfit(storeOffer) end
      window.okButton:setEnabled(false)
		else
			window.appearance.outfit:setImageSource("/images/ui/pressed-large-button")
      window.appearance.outfit.purse:setVisible(false)
      window.appearance.outfit.onClick = nil
      window.okButton:setEnabled(true)
		end
  end

  window.appearance.grayHover:setVisible(false)
end

function onMountSelect(list, focusedChild, unfocusedChild, reason)
  if focusedChild then
    local mountType = tonumber(focusedChild:getId())
    tempOutfit.mount = mountType
    showOutfitCheck:setChecked(true)
    showMountCheck:setEnabled(true)

    if showMountCheck:isChecked() then
      updatePreview()
    end

    updateAppearanceText("mount", focusedChild.name:getText())
    window.ScrollBar.selectionList:ensureChildVisible(focusedChild, {x = 0, y = 2})

		if focusedChild:getActionId() > 0 then
			window.appearance.mount:setImageSource("/images/ui/hlarge-blue-button")
      window.appearance.mount.purse:setVisible(true)
      window.appearance.mount.onClick = function() window:hide() g_game.openStore() g_game.requestStoreOffers(4, "", focusedChild:getActionId()) end
      window.okButton:setEnabled(false)
		else
			window.appearance.mount:setImageSource("/images/ui/pressed-large-button")
      window.appearance.mount.purse:setVisible(false)
      window.appearance.mount.onClick = nil
      window.okButton:setEnabled(true)
		end

    window.appearance.grayHover:setVisible(false)
    if not focusedChild.outfit:isColoredMount() then
      window.appearance.grayHover:setVisible(true)
    end
  end
end

function onFamiliarSelect(list, focusedChild, unfocusedChild, reason)
  if focusedChild then
    local mountType = tonumber(focusedChild:getId())
    tempOutfit.familiar = mountType
    tempFamiliar.type = mountType

    if showFamiliarCheck:isChecked() then
      updatePreview()
    end

    updateAppearanceText("familiar", focusedChild.name:getText())
  end
end

function onAuraSelect(list, focusedChild, unfocusedChild, reason)
  if focusedChild then
    tempOutfit.aura = focusedChild.aura
    tempOutfit.auraCategory = focusedChild.auraCategory
    tempOutfit.auraId = tonumber(focusedChild:getId())

    if showAuraCheck:isChecked() then
      updatePreview()
    end

    updateAppearanceText("aura", focusedChild.name:getText())
  end
end

function updateAppearanceText(widget, text)
  if widget == "preset" and text == "None" or type(text) == number then
    text = "No Preset"
  end

  local wText = window.appearance:recursiveGetChildById(widget).name
  if not wText then
    wText = window.appearance:recursiveGetChildById(widget)
  end

  wText:setText(text)
end

function updateAppearanceTexts(outfit)
  for key, value in pairs(outfit) do
    local newKey = key
    local appKey = key
    if key == "type" then
      newKey = "outfits"
      appKey = "outfit"
    else
      newKey = key .. "s"
      appKey = key
    end

    local dataTable = ServerData[newKey]
    if dataTable then
      for _, data in ipairs(dataTable) do
        if outfit[key] == data[1] or outfit[key] == data[2] then
          updateAppearanceText(appKey, data[2])
        elseif data[4] and not tonumber(data[4]) then
          updateAppearanceText(appKey, data[4])
        elseif appKey == "aura" and outfit[key] ~= 0 then
          updateAppearanceText(appKey, data[4])
        end
      end
    end
  end
end

function onAddonChange(widget, checked)
  local addonId = widget:getParent():getId()

  local addons = tempOutfit.addons
  if addonId == "addon1" then
    addons = checked and addons + 1 or addons - 1
  elseif addonId == "addon2" then
    addons = checked and addons + 2 or addons - 2
  end

  tempOutfit.addons = addons
  updatePreview()
end

function onRandomMountChange(widget, checked)
  globalRandomMount = checked
end

function onColorModeChange(widget, selectedWidget)
  local colorMode = selectedWidget:getId()
  if colorMode == "HeadButton" then
    selectedWidget:getParent():setImageClip("0 0 253 18")
    if appearanceGroup:getSelectedWidget() == window.appearance.mountCheck then
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. tempOutfit.mountHead])
    else
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. tempOutfit.head])
    end
  elseif colorMode == "PrimaryButton" then
    selectedWidget:getParent():setImageClip("0 18 253 18")
    if appearanceGroup:getSelectedWidget() == window.appearance.mountCheck then
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. tempOutfit.mountBody])
    else
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. tempOutfit.body])
    end
  elseif colorMode == "SecondaryButton" then
    selectedWidget:getParent():setImageClip("0 36 253 18")
    if appearanceGroup:getSelectedWidget() == window.appearance.mountCheck then
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. tempOutfit.mountLegs])
    else
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. tempOutfit.legs])
    end
  elseif colorMode == "DetailButton" then
    selectedWidget:getParent():setImageClip("0 54 253 18")
    if appearanceGroup:getSelectedWidget() == window.appearance.mountCheck then
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. tempOutfit.mountFeet])
    else
      colorBoxGroup:selectWidget(window.appearance.panelcolor["colorBox" .. tempOutfit.feet])
    end
  end
end

function onColorCheckChange(widget, selectedWidget)
  local colorId = selectedWidget.colorId

  if currentColorBox then
    currentColorBox:setBorderWidth(0)
    currentColorBox:setBorderColor("alpha")
    currentColorBox:setChecked(false)
  end

  selectedWidget:setBorderWidth(1)
  selectedWidget:setBorderColor("white")
  currentColorBox = selectedWidget

  local colorMode = colorModeGroup:getSelectedWidget():getId()
  if colorMode == "HeadButton" then
    if appearanceGroup:getSelectedWidget() == window.appearance.mountCheck then
      tempOutfit.mountHead = colorId
    else
      tempOutfit.head = colorId
    end
  elseif colorMode == "PrimaryButton" then
    if appearanceGroup:getSelectedWidget() == window.appearance.mountCheck then
      tempOutfit.mountBody = colorId
    else
      tempOutfit.body = colorId
    end
  elseif colorMode == "SecondaryButton" then
    if appearanceGroup:getSelectedWidget() == window.appearance.mountCheck then
      tempOutfit.mountLegs = colorId
    else
      tempOutfit.legs = colorId
    end
  elseif colorMode == "DetailButton" then
    if appearanceGroup:getSelectedWidget() == window.appearance.mountCheck then
      tempOutfit.mountFeet = colorId
    else
      tempOutfit.feet = colorId
    end
  end

  updatePreview()

  if appearanceGroup:getSelectedWidget() == window.appearance.outfitCheck then
    showOutfits()
  elseif appearanceGroup:getSelectedWidget() == window.appearance.mountCheck then
    showMounts()
  end
end

function updatePreview(onlyMount)
  local direction = previewCreature and previewCreature:getDirection() or 0
  local previewOutfit = tempOutfit and table.copy(tempOutfit) or {}
  local previewOFamiliar = tempFamiliar and table.copy(tempFamiliar) or {}

  if previewCreature then
    previewCreature:show()
  end

  if showMountCheck and not showMountCheck:isChecked() then
    previewOutfit.mount = 0
  end

  if showFamiliarCheck and showFamiliarCheck:isChecked() == false then
    previewOFamiliar.type = 0
    previewOFamiliar.familiar = 0
  elseif tempOutfit then
    local tempFamiliar = {type = tempOutfit.familiar}
    if previewFamiliar then
      previewFamiliar:setOutfit(tempFamiliar)
    end
  end

  if showAuraCheck and showAuraCheck:isChecked() then
    previewOutfit.aura = ServerData.currentOutfit.aura
    previewOutfit.auraCategory = ServerData.currentOutfit.auraCategory
    previewOutfit.auraId = ServerData.currentOutfit.auraId
    if previewCreature then
      previewCreature:setIdleAnimate(true)
      previewCreature:setAnimate(false)
    end
    if showMountCheck and showMountCheck:isChecked() then
      showMountCheck:setChecked(false)
    end
  else
    previewOutfit.aura = 0
    previewOutfit.auraCategory = 0
    previewOutfit.auraId = 0
  end

  if onlyMount and previewCreature then
    local tmpOutfit = table.copy(previewOutfit)
    tmpOutfit.type = tmpOutfit.mount
    tmpOutfit.mount = 0
    previewCreature:setOutfit(tmpOutfit)
  elseif previewCreature then
    previewCreature:setOutfit(previewOutfit)
  end

  if previewCreature then
    previewCreature:setDirection(direction)
  end

  if movementCheck and previewCreature then
    previewCreature:setAnimate(movementCheck:isChecked())
    previewCreature:setIdleAnimate(not movementCheck:isChecked())
    previewCreature:setStaticWalking(movementCheck:isChecked())
  end

  if showAuraCheck and showAuraCheck:isChecked() and previewCreature then
    previewCreature:setAnimate(true)
  end
end

function rotate(value)
  local direction = previewCreature:getDirection()
  direction = direction + value
  if direction < Directions.North then
    direction = Directions.West
  elseif direction > Directions.West then
    direction = Directions.North
  end
  previewCreature:setDirection(direction)
  if previewFamiliar:isVisible() then
    previewFamiliar:setDirection(direction)
  end
end

function onFilterSearch(widget)
  if window.appearance.outfitCheck:isChecked() then
    showOutfits(widget:getText())
  elseif window.appearance.mountCheck:isChecked() then
    showMounts(widget:getText())
  end
end

function onClearFilterSearch(widget)
  widget:clearText()
  if window.appearance.outfitCheck:isChecked() then
    showOutfits()
  elseif window.appearance.mountCheck:isChecked() then
    showMounts()
  end
end

function saveSettings()
  local player = g_game.getLocalPlayer()
  local characterDataFolder = "/characterdata/".. player:getId() .."/"
  if not g_resources.directoryExists("/characterdata/") then
    g_resources.makeDir("/characterdata/")
  end
  if not g_resources.directoryExists(characterDataFolder) then
    g_resources.makeDir(characterDataFolder)
  end
  local folder = characterDataFolder .. "outfitdialog.json"
	local status, result = pcall(function() return json.encode(presetList, 2) end)
	if not status then
		return onError("Error while saving outfits profile settings. Data won't be saved. Details: " .. result)
	end

	if result:len() > 100 * 1024 * 1024 then
	  return onError("Something went wrong, file is above 100MB, won't be saved")
	end

	g_resources.writeFileContents(folder, result)
end

function loadSettings()
  local player = g_game.getLocalPlayer()
  local folder = "/characterdata/".. player:getId() .."/outfitdialog.json"
  if g_resources.fileExists(folder) then
		local status, result = pcall(function()
			return json.decode(g_resources.readFileContents(folder))
		end)

		if not status then
			return false
		end
		presetList = result
		return true
  else
    loadDefaultSettings()
	end
end

function loadDefaultSettings()
  presetList = {
    ["configureShowOffSocketPresets"] = {},
    ["customiseCharacterPresets"] = {}
  }

end

function getPresetOutfit(data)
  local firstAddon = data["outfit"]["firstAddOn"]
  local secondAddon = data["outfit"]["secondAddOn"]

  local addons = 0
  if firstAddon and secondAddon then
    addons = 3
  elseif firstAddon and not secondAddon then
    addons = 1
  elseif not firstAddon and secondAddon then
    addons = 2
  end

  local outfit = {
    type = data["outfit"]["id"],
    head = data["outfit"]["color"]["head"],
    body = data["outfit"]["color"]["torso"],
    legs = data["outfit"]["color"]["legs"],
    feet = data["outfit"]["color"]["detail"],
    addons = addons,
    mount = data["mount"]["id"],
    mountBody = data["mount"]["color"]["torso"],
    mountHead = data["mount"]["color"]["head"],
    mountLegs = data["mount"]["color"]["legs"],
    mountFeet = data["mount"]["color"]["detail"],
    familiar = data["summon"]["id"]
  }

  return outfit
end

function getStoreMount(mountId)
  for _, data in pairs(ServerData.mounts) do
    local storeOffer = tonumber(data[3]) or 0
    if storeOffer ~= 0 and data[1] == mountId then
      return storeOffer
    end
  end
  return 0
end

function getStoreOutfit(outfitId)
  local _, storeOffer = getStoreOutfitInfo(outfitId)
  return storeOffer
end

function accept()
  if g_game.getFeature(GamePlayerMounts) then
    local isMountedChecked = window.appearance.mountCheck:isChecked()
    if not isMountedChecked then
      tempOutfit.mount = 0;
    end

    local isAuraChecked = window.configure.aura.auraCheck:isChecked()
    if not isAuraChecked then
      tempOutfit.auraId = 0
    else
      if tempOutfit.auraId == 0 then
        tempOutfit.aura = ServerData.currentOutfit.aura
        tempOutfit.auraCategory = ServerData.currentOutfit.auraCategory
        tempOutfit.auraId = ServerData.currentOutfit.auraId
      end
    end
  end

  g_game.changeOutfit(tempOutfit, globalRandomMount)
  g_client.setInputLockWidget()
  destroy()
end
