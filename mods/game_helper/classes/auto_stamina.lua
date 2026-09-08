if not _Helper then _Helper = {} end
_Helper.AutoStaminaFood = {}
local api = _Helper.AutoStaminaFood
local mouseGrabber, checkEvent = nil, nil
local selectionHelperWindow = nil
local itemSelectionActive = false
local loadingUI, lastUse = false, 0
local USE_INTERVAL = 20000

local function config()
  local root = _Helper.getHelperConfig and _Helper.getHelperConfig()
  return root and root.staminaFood
end
local function panel()
  if _Helper.getToolsPanelContainer then return _Helper.getToolsPanelContainer() end
  return _Helper.getToolsPanel and _Helper.getToolsPanel()
end
local function formatMinutes(value)
  value = math.max(0, tonumber(value) or 0)
  return string.format('%02d:%02d', math.floor(value / 60), value % 60)
end
local function setButtonItem(itemId)
  itemId = tonumber(itemId) or 0
  local root = panel()
  local button = root and root:recursiveGetChildById('staminaFoodButton0')
  if not button then return end
  local itemWidget = button:getChildById('staminaFoodItem')
  if itemId ~= 0 and not itemWidget then
    itemWidget = g_ui.createWidget('FoodItem', button)
    itemWidget:setId('staminaFoodItem')
  end
  if itemId ~= 0 then
    button:setImageSource('/images/ui/item')
    itemWidget:setItemId(itemId)
    itemWidget:show()
    itemWidget:raise()
  else
    if itemWidget then itemWidget:destroy() end
    button:setImageSource('/images/game/actionbar/actionbarslot')
    button:setImageClip('0 0 34 34')
  end
  button:setTooltip(itemId ~= 0 and ('Stamina item ID: ' .. itemId .. '\nRight-click to remove') or
      tr('Click, then select the stamina item in game'))
end

local function closeItemSelection(showHelper)
  if mouseGrabber then
    pcall(function() mouseGrabber:ungrabMouse() end)
    mouseGrabber.onMouseRelease = nil
  end
  if itemSelectionActive and g_mouse and g_mouse.popCursor then
    pcall(function() g_mouse.popCursor('target') end)
  end
  itemSelectionActive = false

  local helperWindow = selectionHelperWindow
  selectionHelperWindow = nil
  if showHelper and helperWindow then
    pcall(function() helperWindow:show(); helperWindow:raise() end)
  end
end

function api.updateThreshold(value)
  if loadingUI then return end
  local cfg = config()
  if not cfg then return end
  cfg.thresholdMinutes = math.max(0, math.min(2520, tonumber(value) or 30))
  local root = panel()
  local label = root and root:recursiveGetChildById('staminaThresholdLabel')
  if label then label:setText('Use at: ' .. formatMinutes(cfg.thresholdMinutes)) end
  if _Helper.saveSettings then _Helper.saveSettings() end
end

function api.toggle(checked)
  if loadingUI then return end
  local cfg = config()
  if not cfg then return end
  if checked and (tonumber(cfg.id) or 0) == 0 then
    modules.game_textmessage.displayFailureMessage(tr('Select a stamina item first!'))
    local root = panel()
    local checkbox = root and root:recursiveGetChildById('enableStaminaFood0')
    if checkbox then loadingUI = true; checkbox:setChecked(false); loadingUI = false end
    return
  end
  cfg.enabled = checked == true
  if _Helper.saveSettings then _Helper.saveSettings() end
end

function api.selectItem()
  if not mouseGrabber then
    mouseGrabber = g_ui.createWidget('UIWidget')
    mouseGrabber:setVisible(false)
    mouseGrabber:setFocusable(false)
  end
  mouseGrabber:grabMouse()
  g_mouse.pushCursor('target')
  itemSelectionActive = true
  selectionHelperWindow = g_ui.getRootWidget():recursiveGetChildById('helperWindow')
  if selectionHelperWindow then selectionHelperWindow:hide() end
  mouseGrabber.onMouseRelease = function(self, position)
    closeItemSelection(true)
    local clicked = g_ui.getRootWidget():recursiveGetChildByPos(position, false)
    local itemId = 0
    if clicked and clicked:getClassName() == 'UIItem' and not clicked:isVirtual() then
      local item = clicked:getItem(); itemId = item and item:getId() or 0
    elseif clicked and clicked:getClassName() == 'UIGameMap' then
      local tile = clicked:getTile(position); local thing = tile and tile:getTopUseThing()
      itemId = thing and thing:getId() or 0
    end
    if itemId == 0 then modules.game_textmessage.displayFailureMessage(tr('No item selected!')); return true end
    local cfg = config()
    if cfg then cfg.id = itemId; setButtonItem(itemId); if _Helper.saveSettings then _Helper.saveSettings() end end
    return true
  end
end

function api.check()
  if not g_game.isOnline() or not (_Helper.isHelperAutomaticFunctionsEnabled and _Helper.isHelperAutomaticFunctionsEnabled()) then return end
  local cfg, player = config(), g_game.getLocalPlayer()
  if not cfg or not cfg.enabled or not player or (tonumber(cfg.id) or 0) == 0 then return end
  if player:getStamina() > (tonumber(cfg.thresholdMinutes) or 30) then return end
  local now = g_clock.millis()
  if now - lastUse < USE_INTERVAL or player:getInventoryCount(cfg.id, 0) <= 0 then return end
  if _Helper.safeDoThing then _Helper.safeDoThing(false) end
  g_game.useInventoryItem(cfg.id)
  if _Helper.safeDoThing then _Helper.safeDoThing(true) end
  lastUse = now
end

function api.loadToUI()
  local cfg, root = config(), panel()
  if not cfg or not root then return end
  loadingUI = true; setButtonItem(tonumber(cfg.id) or 0)
  local checkbox = root:recursiveGetChildById('enableStaminaFood0')
  if checkbox then checkbox:setChecked(cfg.enabled == true) end
  local scroll = root:recursiveGetChildById('staminaThresholdScroll')
  local label = root:recursiveGetChildById('staminaThresholdLabel')
  if scroll then scroll:setValue(tonumber(cfg.thresholdMinutes) or 30); scroll.onValueChange = function(_, value) api.updateThreshold(value) end end
  if label then label:setText('Use at: ' .. formatMinutes(cfg.thresholdMinutes)) end
  local button = root:recursiveGetChildById('staminaFoodButton0')
  if button then button.onMouseRelease = function(_, _, mouseButton) if mouseButton == MouseRightButton then api.removeAction(); return true end end end
  loadingUI = false
  if not checkEvent then checkEvent = cycleEvent(api.check, 1000) end
end

function api.removeAction()
  local cfg = config(); if cfg then cfg.id = 0; cfg.enabled = false end
  api.resetButton(); if _Helper.saveSettings then _Helper.saveSettings() end
end
function api.resetButton()
  loadingUI = true; setButtonItem(0)
  local root = panel(); local checkbox = root and root:recursiveGetChildById('enableStaminaFood0')
  if checkbox then checkbox:setChecked(false) end
  loadingUI = false
end

function api.terminate()
  if checkEvent then removeEvent(checkEvent); checkEvent = nil end
  if mouseGrabber then
    closeItemSelection(true)
    mouseGrabber:destroy()
    mouseGrabber = nil
  end
end
