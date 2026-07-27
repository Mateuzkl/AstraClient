local keybindBugReport = KeyBind:getKeyBind("Dialogs", "Open Bugreport")

local bugReportWindow = nil
local bugTextEdit = nil
local currentCategory = 0
local currentPosition
local moduleActive = false

function init()
  moduleActive = true
  g_ui.importStyle('bugreport')

  bugReportWindow = g_ui.createWidget('BugReportWindow', rootWidget)
  if not bugReportWindow then return end
  bugReportWindow:hide()

  bugTextEdit = bugReportWindow.contentPanel:getChildById('bugTextEdit')

  keybindBugReport:active(rootWidget)
end

function terminate()
  moduleActive = false
  keybindBugReport:deactive()
  if bugReportWindow then
    bugReportWindow:destroy()
    bugReportWindow = nil
  end
end

function doReport()
  if not moduleActive or not bugTextEdit then return end
  g_game.reportBug(currentCategory, bugTextEdit:getText(), currentPosition)
  bugReportWindow:hide()
  modules.game_textmessage.displayGameMessage(tr('Bug report sent.'))
end

function hide()
  if not bugReportWindow then return end
  bugReportWindow:hide()
end

function show(position, reportType)
  if not moduleActive or not bugReportWindow then return end
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
  if not bugReportWindow then return end
  bugReportWindow:recursiveGetChildById('sendButton'):setEnabled((#text > 5 and true or false))
end
