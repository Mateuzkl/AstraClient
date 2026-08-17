-- configs
local LogColors = { [LogDebug] = 'pink',
                    [LogInfo] = 'white',
                    [LogWarning] = 'yellow',
                    [LogError] = 'red' }
local MaxLogLines = 128
local MaxHistory = 1000
local MaxLogLineBytes = 32 * 1024
local MaxLogBytes = 256 * 1024
local TruncatedLineSuffix = '\n... [terminal line truncated]'

local oldenv = getfenv(0)
setfenv(0, _G)
_G.commandEnv = runinsandbox('commands')
setfenv(0, oldenv)

-- private variables
local terminalWindow
local terminalButton
local logLocked = false
local commandTextEdit
local terminalBuffer
local terminalSelectText
local commandHistory = { }
local currentHistoryIndex = 0
local poped = false
local oldPos
local oldSize
local firstShown = false
local flushEvent
local copySelectionEvent
local cachedLines = {}
local disabled = false
local allLines = {}
local allLinesBytes = 0
local nextLineId = 0
local rebindHotkeyEvents = {}

local function bindTerminalHotkey()
  g_keyboard.unbindKeyDown('Ctrl+T', toggle)
  g_keyboard.bindKeyDown('Ctrl+T', toggle)
end

local function scheduleHotkeyRebind(delay)
  table.insert(rebindHotkeyEvents, scheduleEvent(bindTerminalHotkey, delay))
end

-- private functions
local function navigateCommand(step)
  if commandTextEdit:isMultiline() then
    return
  end

  local numCommands = #commandHistory
  if numCommands > 0 then
    currentHistoryIndex = math.min(math.max(currentHistoryIndex + step, 0), numCommands)
    if currentHistoryIndex > 0 then
      local command = commandHistory[numCommands - currentHistoryIndex + 1]
      commandTextEdit:setText(command)
      commandTextEdit:setCursorPos(-1)
    else
      commandTextEdit:clearText()
    end
  end
end

local function completeCommand()
  local cursorPos = commandTextEdit:getCursorPos()
  if cursorPos == 0 then return end

  local commandBegin = commandTextEdit:getText():sub(1, cursorPos)
  local possibleCommands = {}

  -- create a list containing all globals
  local allVars = table.copy(_G)
  table.merge(allVars, commandEnv)

  -- match commands
  for k,v in pairs(allVars) do
    if k:sub(1, cursorPos) == commandBegin then
      table.insert(possibleCommands, k)
    end
  end

  -- complete command with one match
  if #possibleCommands == 1 then
    commandTextEdit:setText(possibleCommands[1])
    commandTextEdit:setCursorPos(-1)
  -- show command matches
  elseif #possibleCommands > 0 then
    print('>> ' .. commandBegin)

    -- expand command
    local expandedComplete = commandBegin
    local done = false
    while not done do
      cursorPos = #commandBegin+1
      if #possibleCommands[1] < cursorPos then
        break
      end
      expandedComplete = commandBegin .. possibleCommands[1]:sub(cursorPos, cursorPos)
      for i,v in ipairs(possibleCommands) do
        if v:sub(1, #expandedComplete) ~= expandedComplete then
          done = true
        end
      end
      if not done then
        commandBegin = expandedComplete
      end
    end
    commandTextEdit:setText(commandBegin)
      commandTextEdit:setCursorPos(-1)

    for i,v in ipairs(possibleCommands) do
      print(v)
    end
  end
end

local function doCommand(textWidget)
  local currentCommand = textWidget:getText()
  executeCommand(currentCommand)
  textWidget:clearText()
  return true
end

local function addNewline(textWidget)
  if not textWidget:isOn() then
    textWidget:setOn(true)
  end
  textWidget:appendText('\n')
end

local function onCommandChange(textWidget, newText, oldText)
  local _, newLineCount = string.gsub(newText, '\n', '\n')
  textWidget:setHeight((newLineCount + 1) * textWidget.baseHeight)

  if newLineCount == 0 and textWidget:isOn() then
    textWidget:setOn(false)
  end
end

local function onLog(level, message, time)
  if disabled then return end
  -- avoid logging while reporting logs (would cause a infinite loop)
  if logLocked then return end

  logLocked = true
  addLine(message, LogColors[level])
  logLocked = false
end

local function truncateUtf8Prefix(text, maxBytes)
  if #text <= maxBytes then
    return text
  end
  if maxBytes <= 0 then
    return ''
  end

  local sequenceStart = maxBytes
  while sequenceStart > 0 do
    local byte = string.byte(text, sequenceStart)
    if byte < 128 or byte >= 192 then
      break
    end
    sequenceStart = sequenceStart - 1
  end

  if sequenceStart == 0 then
    return ''
  end

  local lead = string.byte(text, sequenceStart)
  local sequenceLength = 1
  if lead >= 240 and lead < 248 then
    sequenceLength = 4
  elseif lead >= 224 and lead < 240 then
    sequenceLength = 3
  elseif lead >= 192 and lead < 224 then
    sequenceLength = 2
  elseif lead >= 128 then
    return string.sub(text, 1, sequenceStart - 1)
  end

  if sequenceStart + sequenceLength - 1 > maxBytes then
    maxBytes = sequenceStart - 1
  end
  return string.sub(text, 1, maxBytes)
end

local function truncateLogText(text)
  if #text <= MaxLogLineBytes then
    return text
  end

  local prefix = truncateUtf8Prefix(text, MaxLogLineBytes - #TruncatedLineSuffix)
  return prefix .. TruncatedLineSuffix
end

local function normalizeLogText(text)
  text = truncateLogText(tostring(text))
  text = string.gsub(text, '\t', '    ')
  return truncateLogText(text)
end

local function copyTerminalSelection()
  if not commandTextEdit or not terminalSelectText or
     commandTextEdit:hasSelection() or not terminalSelectText:hasSelection() then
    return false
  end

  if copySelectionEvent then
    removeEvent(copySelectionEvent)
    copySelectionEvent = nil
  end

  local selectText = terminalSelectText
  copySelectionEvent = scheduleEvent(function()
    copySelectionEvent = nil
    if terminalSelectText ~= selectText then
      return
    end

    local ok, destroyed = pcall(function()
      return selectText:isDestroyed()
    end)
    if not ok or destroyed or not selectText:hasSelection() then
      return
    end
    selectText:copy()
  end, 1)
  return true
end

-- public functions
function init()
  terminalWindow = g_ui.displayUI('terminal')
  terminalWindow:hide()

  terminalWindow.onDoubleClick = popWindow
  if modules.client_topmenu and modules.client_topmenu.addLeftButton then
    terminalButton = modules.client_topmenu.addLeftButton('terminalButton', tr('Terminal') .. ' (Ctrl + T)', '/images/topbuttons/terminal', toggle)
    terminalButton:setOn(false)
  end
  bindTerminalHotkey()
  scheduleHotkeyRebind(250)
  scheduleHotkeyRebind(1000)

  commandHistory = g_settings.getList('terminal-history')

  commandTextEdit = terminalWindow:getChildById('commandTextEdit')
  commandTextEdit:setHeight(commandTextEdit.baseHeight)
  connect(commandTextEdit, {onTextChange = onCommandChange})
  g_keyboard.bindKeyPress('Up', function() navigateCommand(1) end, commandTextEdit)
  g_keyboard.bindKeyPress('Down', function() navigateCommand(-1) end, commandTextEdit)
  g_keyboard.bindKeyPress('Ctrl+C', copyTerminalSelection, commandTextEdit)
  g_keyboard.bindKeyDown('Tab', completeCommand, commandTextEdit)
  g_keyboard.bindKeyPress('Shift+Enter', addNewline, commandTextEdit)
  g_keyboard.bindKeyDown('Enter', doCommand, commandTextEdit)
  g_keyboard.bindKeyDown('Escape', hide, terminalWindow)

  terminalBuffer = terminalWindow:getChildById('terminalBuffer')
  terminalSelectText = terminalWindow:getChildById('terminalSelectText')
  terminalSelectText.onDoubleClick = popWindow
  terminalSelectText.onMouseWheel = function(a,b,c) terminalBuffer:onMouseWheel(b,c) end
  terminalBuffer.onScrollChange = function(self, value) terminalSelectText:setTextVirtualOffset(value) end

  g_logger.setOnLog(onLog)

  if not g_app.isRunning() then
    g_logger.fireOldMessages()
  elseif _G.terminalLines then
    for _,line in ipairs(_G.terminalLines) do
      addLine(line.text, line.color)
    end
  end
end

function terminate()
  g_settings.setList('terminal-history', commandHistory)

  if flushEvent then
    removeEvent(flushEvent)
    flushEvent = nil
  end
  if copySelectionEvent then
    removeEvent(copySelectionEvent)
    copySelectionEvent = nil
  end
  for _, event in ipairs(rebindHotkeyEvents) do
    removeEvent(event)
  end
  rebindHotkeyEvents = {}

  if poped then
    oldPos = terminalWindow:getPosition()
    oldSize = terminalWindow:getSize()
  end
  local settings = {
    size = oldSize,
    pos = oldPos,
    poped = poped
  }
  g_settings.setNode('terminal-window', settings)

  g_keyboard.unbindKeyDown('Ctrl+T', toggle)
  g_logger.setOnLog(nil)
  if terminalWindow then
    terminalWindow:destroy()
    terminalWindow = nil
  end
  commandTextEdit = nil
  terminalBuffer = nil
  terminalSelectText = nil
  if terminalButton then
    terminalButton:destroy()
    terminalButton = nil
  end
  commandEnv = nil
  _G.terminalLines = allLines
end

function hideButton()
  --terminalButton:hide()
end

function popWindow()
  if poped then
    oldPos = terminalWindow:getPosition()
    oldSize = terminalWindow:getSize()
    terminalWindow:fill('parent')
    terminalWindow:setOn(false)
    terminalWindow:getChildById('bottomResizeBorder'):disable()
    terminalWindow:getChildById('rightResizeBorder'):disable()
    terminalWindow:getChildById('titleBar'):hide()
    terminalWindow:getChildById('terminalScroll'):setMarginTop(0)
    terminalWindow:getChildById('terminalScroll'):setMarginBottom(0)
    terminalWindow:getChildById('terminalScroll'):setMarginRight(0)
    poped = false
  else
    terminalWindow:breakAnchors()
    terminalWindow:setOn(true)
    local size = oldSize or { width = g_window.getWidth()/2.5, height = g_window.getHeight()/4 }
    terminalWindow:setSize(size)
    local pos = oldPos or { x = 0, y = g_window.getHeight() }
    terminalWindow:setPosition(pos)
    terminalWindow:getChildById('bottomResizeBorder'):enable()
    terminalWindow:getChildById('rightResizeBorder'):enable()
    terminalWindow:getChildById('titleBar'):show()
    terminalWindow:getChildById('terminalScroll'):setMarginTop(18)
    terminalWindow:getChildById('terminalScroll'):setMarginBottom(1)
    terminalWindow:getChildById('terminalScroll'):setMarginRight(1)
    terminalWindow:bindRectToParent()
    poped = true
  end
end

function toggle()
  if not terminalWindow then return end
  if terminalWindow:isVisible() then
    hide()
  else
    local layout = terminalBuffer and terminalBuffer:getLayout()
    if layout then
      layout:disableUpdates()
    end

    if not firstShown then
      local settings = g_settings.getNode('terminal-window')
      if settings then
        if settings.size then oldSize = settings.size end
        if settings.pos then oldPos = settings.pos end
        if settings.poped then popWindow() end
      end
      firstShown = true
    end
    show()

    if layout then
      layout:enableUpdates()
      layout:update()
    end
  end
end

function show()
  if not terminalWindow then return end
  terminalWindow:show()
  terminalWindow:raise()
  terminalWindow:focus()
  if terminalButton then
    terminalButton:setOn(true)
  end
end

function hide()
  if not terminalWindow then return end
  terminalWindow:hide()
  if terminalButton then
    terminalButton:setOn(false)
  end
end

function disable()
  --terminalButton:hide()
  g_keyboard.unbindKeyDown('Ctrl+T', toggle)
  disabled = true
end

function bindHotkey()
  bindTerminalHotkey()
end

function flushLines()
  local pendingLines = cachedLines
  cachedLines = {}
  flushEvent = nil

  if not terminalBuffer or not terminalSelectText then
    return
  end

  local layout = terminalBuffer:getLayout()
  if layout then
    layout:disableUpdates()
  end

  for _,line in ipairs(pendingLines) do
    local lineBytes = #line.text
    while #allLines >= MaxLogLines or
          (#allLines > 0 and allLinesBytes + lineBytes > MaxLogBytes) do
      local firstChild = terminalBuffer:getChildByIndex(1)
      if firstChild then
        firstChild:destroy()
      end

      local removedLine = table.remove(allLines, 1)
      if removedLine then
        allLinesBytes = math.max(0, allLinesBytes - #removedLine.text)
      else
        break
      end
    end

    nextLineId = nextLineId + 1
    local label = g_ui.createWidget('TerminalLabel', terminalBuffer)
    label:setId('terminalLabel' .. nextLineId)
    label:setText(line.text)

    if line.color == 'pink' then
      label:setColor('#ff80ff')
    elseif line.color == 'white' then
      label:setColor('#eeeeee')
    elseif line.color == 'yellow' then
      label:setColor('#ffff66')
    elseif line.color == 'red' then
      label:setColor('#ff4444')
    else
      label:setColor(line.color) -- fallback
    end

    table.insert(allLines, {text=line.text,color=line.color})
    allLinesBytes = allLinesBytes + lineBytes
  end

  if layout then
    layout:enableUpdates()
    layout:update()
  end

  local textLines = {}
  for index, line in ipairs(allLines) do
    textLines[index] = line.text
  end
  terminalSelectText:setText(#textLines > 0 and '\n' .. table.concat(textLines, '\n') or '')

end

function addLine(text, color)
  if not flushEvent then
    flushEvent = scheduleEvent(flushLines, 10)
  end

  text = normalizeLogText(text)
  table.insert(cachedLines, {text=text, color=color})
end

function terminalPrint(value)
  if type(value) == "table" then
    return print(json.encode(value, 2))
  end
  print(tostring(value))
end

function executeCommand(command)
  if command == nil or #string.gsub(command, '\n', '') == 0 then return end

  -- add command line
  addLine("> " .. command, "#ffffff")
  if g_game.getFeature(GameNoDebug) then
    addLine("Terminal is disabled on this server", "#ff8888")
    return
  end

  -- reset current history index
  currentHistoryIndex = 0

  -- add new command to history
  if #commandHistory == 0 or commandHistory[#commandHistory] ~= command then
    table.insert(commandHistory, command)
    while #commandHistory > MaxHistory do
      table.remove(commandHistory, 1)
    end
  end

  -- detect and convert commands with simple syntax
  local realCommand
  if string.sub(command, 1, 1) == '=' then
    realCommand = 'modules.client_terminal.terminalPrint(' .. string.sub(command,2) .. ')'
  else
    realCommand = command
  end

  local func, err = loadstring(realCommand, "@")

  -- detect terminal commands
  if not func then
    local command_name = command:match('^([%w_]+)[%s]*.*')
    if command_name then
      local args = string.split(command:match('^[%w_]+[%s]*(.*)'), ' ')
      if commandEnv[command_name] and type(commandEnv[command_name]) == 'function' then
        func = function() modules.client_terminal.commandEnv[command_name](unpack(args)) end
      elseif command_name == command then
        addLine('ERROR: command not found', 'red')
        return
      end
    end
  end

  -- check for syntax errors
  if not func then
    addLine('ERROR: incorrect lua syntax: ' .. err:sub(5), 'red')
    return
  end

  commandEnv['player'] = g_game.getLocalPlayer()

  -- setup func env to commandEnv
  setfenv(func, commandEnv)

  -- execute the command
  local ok, ret = pcall(func)
  if ok then
    -- if the command returned a value, print it
    if ret then addLine(ret, 'white') end
  else
    addLine('ERROR: command failed: ' .. ret, 'red')
  end
end

function clear()
  if flushEvent then
    removeEvent(flushEvent)
    flushEvent = nil
  end
  if copySelectionEvent then
    removeEvent(copySelectionEvent)
    copySelectionEvent = nil
  end
  terminalBuffer:destroyChildren()
  terminalSelectText:setText('')
  cachedLines = {}
  allLines = {}
  allLinesBytes = 0
  nextLineId = 0
end
