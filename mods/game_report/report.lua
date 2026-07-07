reportWindow = nil
stepOne = nil
stepTwoName = nil
stepTwoStatement = nil
reportTwoSoftware = nil
stepThreeBot = nil
stepThree = nil

ReportSystemMacro = {}
ReportSystemName = {}
ReportSystemStatement = {}

REPORT_TYPE_NAME = 0
REPORT_TYPE_STATEMENT = 1
REPORT_TYPE_BOT = 2

function init()
  reportWindow = g_ui.displayUI('report')
  stepOne = reportWindow:getChildById('stepOne')
  stepTwoName = reportWindow:getChildById('stepTwoName')
  stepTwoStatement = reportWindow:getChildById('stepTwoStatement')
  reportTwoSoftware = reportWindow:getChildById('stepTwoSoftware')
  stepThreeBot = reportWindow:getChildById('stepThreeBot')
  stepThree = reportWindow:getChildById('stepThree')
  reportWindow.onEnter = function() for _,id in ipairs({'stepOne','stepTwoName','stepTwoStatement','stepTwoSoftware','stepThree','stepThreeBot'}) do local p = reportWindow:recursiveGetChildById(id); if p and p:isVisible() then local b = p:recursiveGetChildById('nextButton'); if b and b:isEnabled() and b.onClick then b.onClick(b) end break end end end
  reportWindow:hide()
  loadReportBot()
  loadReportName()
  loadReportStatement()

  connect(g_game, {onGameEnd = onGameEnd})
end

function terminate()
  if reportWindow then
    reportWindow:destroy()
    reportWindow = nil
  end
  disconnect(g_game, {onGameEnd = onGameEnd})
end

function onGameEnd()
  if reportWindow:isVisible() then
    g_client.setInputLockWidget(nil)
    reportWindow:hide()
  end
end

function toggle()
  if reportWindow:isVisible() then
    reportWindow:hide()
  else
    reportWindow:show()
  end
end

function hide()
  g_client.setInputLockWidget(nil)
  reportWindow:hide()
end

function show()
  g_client.setInputLockWidget(reportWindow)
  reportWindow:show()
end

function loadReportBot()
  local file = "/data/json/report-bot.json"
  if g_resources.fileExists(file) then
    local status, result = pcall(function()
      return json.decode(g_resources.readFileContents(file))
    end)

    if not status then
      return g_logger.error("Error while reading report file. Details: " .. result)
    end

    ReportSystemMacro = result
  end
end

function loadReportName()
  local file = "/data/json/report-name.json"
  if g_resources.fileExists(file) then
    local status, result = pcall(function()
      return json.decode(g_resources.readFileContents(file))
    end)

    if not status then
      return g_logger.error("Error while reading report file. Details: " .. result)
    end

    ReportSystemName = result
  end
end

function loadReportStatement()
  local file = "/data/json/report-statement.json"
  if g_resources.fileExists(file) then
    local status, result = pcall(function()
      return json.decode(g_resources.readFileContents(file))
    end)

    if not status then
      return g_logger.error("Error while reading report file. Details: " .. result)
    end

    ReportSystemStatement = result
  end
end
