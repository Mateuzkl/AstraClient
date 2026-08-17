-- @docclass UIWidget

function UIWidget:setMargin(...)
  local params = {...}
  if #params == 1 then
    self:setMarginTop(params[1])
    self:setMarginRight(params[1])
    self:setMarginBottom(params[1])
    self:setMarginLeft(params[1])
  elseif #params == 2 then
    self:setMarginTop(params[1])
    self:setMarginRight(params[2])
    self:setMarginBottom(params[1])
    self:setMarginLeft(params[2])
  elseif #params == 4 then
    self:setMarginTop(params[1])
    self:setMarginRight(params[2])
    self:setMarginBottom(params[3])
    self:setMarginLeft(params[4])
  end
end

local copyToClipboardConfirmWindow = nil
local function showCopyToClipboardConfirmWindow(text)
  if copyToClipboardConfirmWindow then
    copyToClipboardConfirmWindow:destroy()
  end

  local confirm = function()
    g_window.setClipboardText(text)
   if copyToClipboardConfirmWindow then
      copyToClipboardConfirmWindow:destroy()
      copyToClipboardConfirmWindow = nil
    end
    return true
  end

  local deny = function()
    if copyToClipboardConfirmWindow then
      copyToClipboardConfirmWindow:destroy()
      copyToClipboardConfirmWindow = nil
    end
    return false
  end

  copyToClipboardConfirmWindow = displayGeneralBox('Link Copy Warning', tr("The text you are trying to copy seems to include a link. Please be very careful when following links sent to you\nby other players as they might be used to hack your account! If you are not sure if the link is safe, do not\ncontinue.\n\nIf you do not want to see this warning again, you can deactivate it in the Options menu.\n\nContinue?"),
    { { text=tr('Yes'), callback=confirm }, { text=tr('No'), callback=deny }
    }, confirm, deny)
end

function UIWidget:onCopyText(text)
  if m_settings.getOption('linkCopyWarning') and hasLink(text) then
    return showCopyToClipboardConfirmWindow(text)
  end
  g_window.setClipboardText(text)
  return true
end

function UIWidget:getEmptySlot(widget)
  local childsSize = 0
  for _, child in pairs(self:getChildren()) do
    if child:isVisible() and widget:getId() ~= child:getId() then
      childsSize = child:getHeight() + childsSize
    end
  end

  return self:getHeight() - childsSize
end

function UIWidget:getChildInPanel()
  local childsSize = 0
  for _, child in pairs(self:getChildren()) do
    if child:isVisible() then
      childsSize = 1 + childsSize
    end
  end

  return childsSize
end

function UIWidget:dispatchLeftClick(mousePos)
    if not self or self:isDestroyed() then
        return false
    end

    local callback = self.onLeftClick
    if type(callback) ~= "function" and type(callback) ~= "table" then
        return false
    end

    return signalcall(callback, self, mousePos)
end

function UIWidget:onClick(mousePos)
  if self and type(self.onClick) == "table" then
    for _, func in pairs(self.onClick) do
      if type(func) == "function" and func ~= UIWidget.onClick then
        func(self, mousePos)
      end
    end
  end

  -- Some imported modules use the donor client's onLeftClick callback.
  -- Astra emits onClick for left/touch releases, so forward it here while
  -- keeping the original onClick function identity stable for connect().
  if self and not self:isDestroyed() then
    self:dispatchLeftClick(mousePos)
  end

  -- Used to release the focus of the widget when clicking outside it
  local focusedWidgets = modules.game_interface.focusReason
  if not focusedWidgets or table.empty(focusedWidgets) then
    return true
  end

  local clickedWidget = rootWidget:recursiveGetChildByPos(mousePos, false)
  if not clickedWidget then
    return true
  end

  local ignorableWidgets = { "searchText", "amountText" }
  if table.contains(ignorableWidgets, clickedWidget:getId()) then
    return true
  end

  modules.game_npctrade.toggleNPCFocus(false)
  return true
end

function g_client.onReleaseFocusedWidgets()
  local focusedWidgets = modules.game_interface.focusReason
  if not focusedWidgets or table.empty(focusedWidgets) then
    return true
  end

  modules.game_interface.toggleInternalFocus()
end

-- single pending focus hand-off. Without this every setInputLockWidget() call
-- left an uncancellable 50ms event holding a strong reference to the widget,
-- which then fired focus() on an already destroyed widget.
local pendingFocusEvent

function g_client.setInputLockWidget(widget)
  if pendingFocusEvent then
    removeEvent(pendingFocusEvent)
    pendingFocusEvent = nil
  end

  if widget ~= nil then
    if not modules.game_interface or not modules.game_interface.isMouseTargetSelectionActive or not modules.game_interface.isMouseTargetSelectionActive() then
      g_mouse.clearGrabber()
    end
  end
  if g_ui.getCustomInputWidget() then
    g_ui.setInputLockWidget(nil)
  end

  if widget and g_game.isOnline() then
    g_client.onReleaseFocusedWidgets()
  end

  g_ui.setInputLockWidget(widget)

  if widget then
    pendingFocusEvent = scheduleEvent(function()
      pendingFocusEvent = nil
      if widget:isDestroyed() then return end
      widget:focus()
    end, 50)
  elseif not widget and g_game.isOnline() then
    pendingFocusEvent = scheduleEvent(function()
      pendingFocusEvent = nil
      if g_game.isOnline() and rootWidget and rootWidget:getChildById("gameRootPanel") then
        rootWidget:getChildById("gameRootPanel"):focus()
      end
    end, 50)
  end
end


function UIWidget:onStyleApply(styleName, styleNode)
  if not g_tooltip then return end
  g_tooltip.onWidgetStyleApply(self, styleName, styleNode)
  for name,value in pairs(styleNode) do
    if name == 'main-window-size' then
      self.main_window_size = tosize(value)
    end
  end
end
