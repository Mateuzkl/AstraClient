local keybindBugReport = KeyBind:getKeyBind("Dialogs", "Open Bugreport")

bugReportWindow = nil
bugTextEdit = nil
local currentCategory = 0
local currentPosition

function init()
  g_ui.importStyle('bugreport')

  bugReportWindow = g_ui.createWidget('BugReportWindow', rootWidget)
  bugReportWindow:hide()

  bugTextEdit = bugReportWindow.contentPanel:getChildById('bugTextEdit')

  -- Enter sends the report, matching the Send button (which stays disabled until the
  -- text is long enough); Escape (wired in bugreport.otui) closes the dialog.
  bugReportWindow.onEnter = function()
    local sendButton = bugReportWindow:recursiveGetChildById('sendButton')
    if sendButton:isEnabled() then
      doReport()
    end
  end

  keybindBugReport:active(gameRootPanel)
end

function terminate()
  keybindBugReport:deactive()
  bugReportWindow:destroy()
end

function doReport()
  g_game.reportBug(currentCategory, bugTextEdit:getText(), currentPosition)
  bugReportWindow:hide()
  modules.game_textmessage.displayGameMessage(tr('Bug report sent.'))
end

function hide()
  bugReportWindow:hide()
end

function show(position, reportType)
  if not reportType then
    reportType = 0
  end
  if g_game.isOnline() then
    if not position then
      position = g_game.getLocalPlayer():getPosition()
    end
    currentPosition = position
    bugTextEdit:setText('')

    if reportType == 0 then
      bugReportWindow:recursiveGetChildById('map'):focus()
    elseif reportType == 1 then
      bugReportWindow:recursiveGetChildById('type'):focus()
    elseif reportType == 2 then
      bugReportWindow:recursiveGetChildById('technical'):focus()
    elseif reportType == 3 then
      bugReportWindow:recursiveGetChildById('other'):focus()
    end

    bugReportWindow:show()
    bugReportWindow:raise()
    bugReportWindow:focus()
  end
end

function updateOnStates(widget, color, category)
  if widget:isFocused() then
    currentCategory = category
  end
  widget:setBackgroundColor(widget:isFocused() and "$var-textlist-selected" or color)
end

function onTextChange(text)
  bugReportWindow:recursiveGetChildById('sendButton'):setEnabled((#text > 5 and true or false))
end
