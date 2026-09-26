local datEditorWindow
local datEditorButton
local outfitIdWidget
local mountIdWidget
local offsetXWidget
local offsetYWidget
local previewWidget
local statusWidget
local outfitModeButton
local mountModeButton
local originalOffsets = {}
local updatingWidgets = false
local confirmWindow
local editMode = 'outfit'

local function onDatReload()
  originalOffsets = {}
end

local function setStatus(message, isError)
  if not statusWidget then
    return
  end
  statusWidget:setText(message)
  statusWidget:setColor(isError and '#ff7777' or '#b8d8a8')
  statusWidget:setTooltip(message)
end

local function loadedDatPath()
  if modules.game_things and modules.game_things.getLoadedDatPath then
    return modules.game_things.getLoadedDatPath()
  end
  return nil
end

local function selectedThingType()
  if not outfitIdWidget then
    return nil, 0
  end

  local selectedId = tonumber(editMode == 'mount' and mountIdWidget:getText() or outfitIdWidget:getText()) or 0
  if selectedId < 1 or not g_things.isValidDatId(selectedId, ThingCategoryCreature) then
    return nil, selectedId
  end
  return g_things.getThingType(selectedId, ThingCategoryCreature), selectedId
end

local function rememberOriginal(outfitId, thingType)
  if not originalOffsets[outfitId] then
    originalOffsets[outfitId] = {
      x = thingType:getDisplacementX(),
      y = thingType:getDisplacementY()
    }
  end
end

local function showOutfitPreview()
  if not previewWidget then
    return
  end

  local outfitId = tonumber(outfitIdWidget:getText()) or 0
  local mountId = tonumber(mountIdWidget:getText()) or 0
  if outfitId < 1 or not g_things.isValidDatId(outfitId, ThingCategoryCreature) then
    previewWidget:hide()
    return
  end
  if editMode == 'mount' and
      (mountId < 1 or not g_things.isValidDatId(mountId, ThingCategoryCreature)) then
    previewWidget:hide()
    return
  end

  previewWidget:show()
  previewWidget:setScale(1)
  previewWidget:setAnimate(true)
  previewWidget:setDirection(Directions.South)
  previewWidget:setDrawMountOnly(editMode == 'mount')
  previewWidget:setIgnoreDisplacement(true)
  previewWidget:setOldScaling(true)
  previewWidget:setOutfit({
    type = outfitId,
    head = 78,
    body = 68,
    legs = 58,
    feet = 76,
    addons = 3,
    mount = editMode == 'mount' and mountId or 0
  })
  previewWidget:setCenter(true)
end

function initDatOffsetEditor()
  datEditorWindow = g_ui.displayUI('dat_offset_editor')
  datEditorWindow:hide()
  outfitIdWidget = datEditorWindow:recursiveGetChildById('outfitId')
  mountIdWidget = datEditorWindow:recursiveGetChildById('mountId')
  offsetXWidget = datEditorWindow:recursiveGetChildById('offsetX')
  offsetYWidget = datEditorWindow:recursiveGetChildById('offsetY')
  previewWidget = datEditorWindow:recursiveGetChildById('outfitPreview')
  statusWidget = datEditorWindow:recursiveGetChildById('status')
  outfitModeButton = datEditorWindow:recursiveGetChildById('outfitMode')
  mountModeButton = datEditorWindow:recursiveGetChildById('mountMode')

  connect(g_things, { onLoadDat = onDatReload })

  datEditorButton = modules.client_topmenu.addLeftToggleButton(
    'datOffsetEditorButton',
    tr('DAT Offset Studio') .. ' (Ctrl+Alt+O)',
    '/images/topbuttons/debug',
    toggleDatOffsetEditor)
  datEditorButton:setOn(false)
  g_keyboard.bindKeyDown('Ctrl+Alt+O', toggleDatOffsetEditor)
end

function terminateDatOffsetEditor()
  disconnect(g_things, { onLoadDat = onDatReload })
  if confirmWindow then
    confirmWindow:destroy()
    confirmWindow = nil
  end
  if datEditorWindow then
    datEditorWindow:destroy()
    datEditorWindow = nil
  end
  if datEditorButton then
    datEditorButton:destroy()
    datEditorButton = nil
  end
  g_keyboard.unbindKeyDown('Ctrl+Alt+O')
end

function showDatOffsetEditor()
  if not datEditorWindow then
    return
  end
  if not g_things.isDatLoaded() then
    displayErrorBox(tr('DAT Offset Studio'), tr('Load a DAT file before opening the editor.'))
    return
  end

  local player = g_game.getLocalPlayer()
  if player and player:getOutfit().type > 0 then
    local outfit = player:getOutfit()
    outfitIdWidget:setText(tostring(outfit.type), true)
    mountIdWidget:setText(tostring(outfit.mount or 0), true)
  elseif (tonumber(outfitIdWidget:getText()) or 0) < 1 then
    outfitIdWidget:setText('1', true)
  end

  datEditorWindow:show()
  datEditorWindow:raise()
  datEditorWindow:focus()
  if datEditorButton then
    datEditorButton:setOn(true)
  end
  setDatEditMode(editMode)
end

function hideDatOffsetEditor()
  if datEditorWindow then
    datEditorWindow:hide()
  end
  if datEditorButton then
    datEditorButton:setOn(false)
  end
end

function toggleDatOffsetEditor()
  if not datEditorWindow or not datEditorWindow:isVisible() then
    showDatOffsetEditor()
  else
    hideDatOffsetEditor()
  end
end

local function refreshSelectedDatType()
  if updatingWidgets then
    return
  end

  showOutfitPreview()
  local thingType, selectedId = selectedThingType()
  if not thingType then
    setStatus(tr('%s ID %d does not exist in the loaded DAT.', editMode == 'mount' and tr('Mount') or tr('Outfit'), selectedId), true)
    return
  end

  rememberOriginal(selectedId, thingType)
  updatingWidgets = true
  offsetXWidget:setText(tostring(thingType:getDisplacementX()), true)
  offsetYWidget:setText(tostring(thingType:getDisplacementY()), true)
  updatingWidgets = false

  local path = loadedDatPath() or tr('unknown DAT')
  setStatus(tr('Editing %s %d  |  %s  |  current: %d, %d', editMode, selectedId, path,
    thingType:getDisplacementX(), thingType:getDisplacementY()), false)
end

function onDatOutfitIdChange()
  if editMode == 'outfit' then
    refreshSelectedDatType()
  else
    showOutfitPreview()
  end
end

function onDatMountIdChange()
  if editMode == 'mount' then
    refreshSelectedDatType()
  else
    showOutfitPreview()
  end
end

function setDatEditMode(mode)
  if mode ~= 'outfit' and mode ~= 'mount' then
    return
  end
  editMode = mode
  outfitModeButton:setText(mode == 'outfit' and tr('[ Outfit ]') or tr('Outfit'))
  mountModeButton:setText(mode == 'mount' and tr('[ Mount ]') or tr('Mount'))
  refreshSelectedDatType()
end

function useCurrentPlayerOutfit()
  local player = g_game.getLocalPlayer()
  if not player then
    setStatus(tr('Log in to copy the current outfit and mount.'), true)
    return
  end
  local outfit = player:getOutfit()
  updatingWidgets = true
  outfitIdWidget:setText(tostring(outfit.type), true)
  mountIdWidget:setText(tostring(outfit.mount or 0), true)
  updatingWidgets = false
  refreshSelectedDatType()
end


function previewDatOutfit()
  refreshSelectedDatType()
end

function applyDatOffsetLive()
  if updatingWidgets then
    return
  end

  local thingType, outfitId = selectedThingType()
  if not thingType then
    setStatus(tr('Select a valid creature outfit.'), true)
    return
  end

  rememberOriginal(outfitId, thingType)
  local x = tonumber(offsetXWidget:getText())
  local y = tonumber(offsetYWidget:getText())
  if not x or not y then
    setStatus(tr('Type complete integer values for X and Y.'), true)
    return
  end
  x = math.floor(x)
  y = math.floor(y)
  if not thingType:setDisplacement(topoint(string.format('%d %d', x, y))) then
    setStatus(tr('Offset is outside the range supported by this DAT format.'), true)
    return
  end

  showOutfitPreview()
  setStatus(tr('Live offset applied in game to %s %d: %d, %d (not saved yet).', editMode, outfitId, x, y), false)
end

function revertDatOffset()
  local thingType, outfitId = selectedThingType()
  local original = originalOffsets[outfitId]
  if not thingType or not original then
    setStatus(tr('There is no original value to restore for this outfit.'), true)
    return
  end

  updatingWidgets = true
  offsetXWidget:setText(tostring(original.x), true)
  offsetYWidget:setText(tostring(original.y), true)
  updatingWidgets = false
  thingType:setDisplacement(topoint(string.format('%d %d', original.x, original.y)))
  showOutfitPreview()
  setStatus(tr('Restored %s %d to %d, %d in memory.', editMode, outfitId, original.x, original.y), false)
end

local function closeConfirmWindow()
  if confirmWindow then
    confirmWindow:destroy()
    confirmWindow = nil
  end
end

local function saveLoadedDat()
  closeConfirmWindow()
  local path = loadedDatPath()
  if not path then
    setStatus(tr('The loaded DAT path is unavailable.'), true)
    return
  end
  if not g_things.saveDatDisplacementToWorkDir then
    setStatus(tr('This client build does not support DAT saving.'), true)
    return
  end

  local thingType, selectedId = selectedThingType()
  if not thingType then
    setStatus(tr('Select a valid %s before saving.', editMode), true)
    return
  end

  if not g_things.saveDatDisplacementToWorkDir(path, selectedId, ThingCategoryCreature) then
    setStatus(tr('DAT save failed. The original file was preserved; check the log.'), true)
    return
  end

  originalOffsets[selectedId] = {
    x = thingType:getDisplacementX(),
    y = thingType:getDisplacementY()
  }
  setStatus(tr('Saved only %s %d to %s (backup: %s.bak).', editMode, selectedId, path, path), false)
end

function confirmSaveDatOffsets()
  local path = loadedDatPath()
  if not path then
    setStatus(tr('The loaded DAT path is unavailable.'), true)
    return
  end

  closeConfirmWindow()
  local _, selectedId = selectedThingType()
  confirmWindow = displayGeneralBox(
    tr('Save DAT offsets'),
    tr('Save only %s %d to %s?\nThe other layer will not be changed. A verified backup will be written to %s.bak first.',
      editMode, selectedId, path, path),
    {
      { text = tr('Save DAT'), callback = saveLoadedDat },
      { text = tr('Cancel'), callback = closeConfirmWindow },
      anchor = AnchorHorizontalCenter
    },
    saveLoadedDat,
    closeConfirmWindow)
end
