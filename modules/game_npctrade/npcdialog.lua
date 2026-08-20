local NPC_DIALOG_COLOR = '#5ff7f7'
local PLAYER_DIALOG_COLOR = '#9f9dfd'
local TALKING_TO_COLOR = '#ffffff'
local HIGHLIGHT_COLOR = '#1f9ffe'
local MAX_DIALOG_MESSAGES = 200
local PENDING_MESSAGE_TIMEOUT = 10000
local TRADE_GAP = 2

local npcDialogWindow
local npcDialogBuffer
local npcDialogInput
local npcDialogName
local npcDialogPendingMessages = {}
local npcDialogSuppressed = false
local npcDialogPositioning = false
local npcTradeOriginalHeight
local npcDialogLastActionText
local npcDialogLastActionTime = 0

local npcDialogButtons = {
  { text = 'yes', sprite = 7 },
  { text = 'no', sprite = 8 },
  { text = 'bye', sprite = 9 },
  { text = 'trade', sprite = 0 }
}

local function getNpcDialogRoot()
  if modules.game_interface and modules.game_interface.getRootPanel then
    return modules.game_interface.getRootPanel()
  end
  return g_ui.getRootWidget()
end

local function focusNpcDialogWidget(widget)
  if not widget or widget:isDestroyed() then
    return false
  end

  widget:focus()
  local child = widget
  local parent = child:getParent()
  while parent do
    parent:focusChild(child, 1)
    child = parent
    parent = parent:getParent()
  end
  return true
end

local function getTimestampPrefix()
  if not m_settings.getOption('showTimestampsInConsole') then
    return ''
  end

  local format = '%H:%M'
  if m_settings.getOption('showSecondTimestampsInConsole') then
    format = format .. ':%S'
  end
  return os.date(format) .. ' '
end

local function findNpcCreature(name)
  local player = g_game.getLocalPlayer()
  if not player or not name then
    return nil
  end

  local expectedName = name:lower()
  for _, creature in ipairs(g_map.getSpectators(player:getPosition(), false)) do
    local creatureName = creature:getName()
    if creatureName and creatureName:lower() == expectedName then
      return creature
    end
  end
  return nil
end

local function buildColoredDialogText(text, defaultColor)
  local colored = {}
  local intervals = {}
  local displayedText = ''
  local cursor = 1

  while true do
    local startPos, endPos, word = text:find('{([^}]+)}', cursor)
    if not startPos then
      local tail = text:sub(cursor)
      if tail ~= '' then
        setStringColor(colored, tail, defaultColor)
        displayedText = displayedText .. tail
      end
      break
    end

    local before = text:sub(cursor, startPos - 1)
    if before ~= '' then
      setStringColor(colored, before, defaultColor)
      displayedText = displayedText .. before
    end

    local intervalStart = #displayedText
    setStringColor(colored, word, HIGHLIGHT_COLOR)
    displayedText = displayedText .. word
    table.insert(intervals, {
      first = intervalStart,
      last = #displayedText,
      word = word
    })
    cursor = endPos + 1
  end

  return colored, intervals
end

local function addNpcDialogMessage(text, color, creatureName)
  if not npcDialogBuffer then
    return
  end

  while npcDialogBuffer:getChildCount() >= MAX_DIALOG_MESSAGES do
    npcDialogBuffer:getFirstChild():destroy()
  end

  local label = g_ui.createWidget('NpcDialogLabel', npcDialogBuffer)
  label:setId('npcDialogLabel' .. npcDialogBuffer:getChildCount())
  label.creatureName = creatureName

  local fullText = getTimestampPrefix() .. text
  local colored, intervals = buildColoredDialogText(fullText, color)
  label.highlightedIntervals = intervals
  label:setColoredText(colored)

  function label.onMouseRelease(widget, mousePos, mouseButton)
    if mouseButton == MouseLeftButton then
      return false
    elseif mouseButton == MouseRightButton then
      local menu = g_ui.createWidget('PopupMenu')
      menu:setGameMenu(true)
      if widget.creatureName and widget.creatureName ~= '' then
        menu:addOption(tr('Copy name'), function()
          g_window.setClipboardText(widget.creatureName)
        end)
      end
      menu:addOption(tr('Copy message'), function()
        g_window.setClipboardText(widget:getText())
      end)
      menu:display(mousePos)
      return true
    end
    return false
  end


  if #intervals > 0 then
    label:setEventListener(EVENT_TEXT_CLICK)
    label:setEventListener(EVENT_TEXT_HOVER)

    label.onTextClick = function(widget, _, index)
      for _, interval in ipairs(widget.highlightedIntervals) do
        if index >= interval.first and index < interval.last then
          sendNpcDialogText(interval.word)
          return
        end
      end
    end

    label.onTextHoverChange = function(widget, index, hovered)
      local isHighlighted = false
      for _, interval in ipairs(widget.highlightedIntervals) do
        if index >= interval.first and index < interval.last then
          isHighlighted = true
          break
        end
      end

      if hovered and isHighlighted then
        if not g_mouse.applyNativeCursor('pointer') then
          g_mouse.pushCursor('pointer')
        end
      else
        if not g_mouse.restoreNativeCursor() then
          g_mouse.popCursor('pointer')
        end
      end
    end
  end

  addEvent(function()
    if npcDialogBuffer and not npcDialogBuffer:isDestroyed() and label and not label:isDestroyed() then
      npcDialogBuffer:ensureChildVisible(label)
    end
  end)
end

local function addTalkingToMessage(name)
  addNpcDialogMessage(tr('Talking to %s', name), TALKING_TO_COLOR)
end

local function onNpcTradeFailureMessage(_, text)
  if not text or text == '' or not npcDialogWindow or not npcDialogWindow:isVisible() or
      not npcWindow or not npcWindow:isVisible() then
    return
  end

  local prefix = npcDialogName and npcDialogName .. ' says: ' or ''
  addNpcDialogMessage(prefix .. text, NPC_DIALOG_COLOR, npcDialogName)
end

local function flushPendingPlayerMessages()
  local now = g_clock.millis()
  for _, message in ipairs(npcDialogPendingMessages) do
    if now - message.time <= PENDING_MESSAGE_TIMEOUT then
      local playerName = g_game.getCharacterName() or tr('You')
      addNpcDialogMessage(playerName .. ': ' .. message.text, PLAYER_DIALOG_COLOR, playerName)
    end
  end
  npcDialogPendingMessages = {}
end

local function setNpcDialogCreature(name)
  local creature = findNpcCreature(name)
  local outfitWidget = npcDialogWindow:recursiveGetChildById('npcDialogCreature')
  local fallbackWidget = npcDialogWindow:recursiveGetChildById('npcDialogFallback')
  local hasCreature = creature ~= nil

  outfitWidget:setVisible(hasCreature)
  fallbackWidget:setVisible(not hasCreature)
  if creature then
    outfitWidget:setOutfit(creature:getOutfit())
  end
end

local function updateNpcDialogChatMode()
  if not npcDialogWindow then
    return
  end

  local chatEnabled = modules.game_console and modules.game_console.isChatEnabled and
      modules.game_console.isChatEnabled()
  local button = npcDialogWindow:recursiveGetChildById('npcDialogChatMode')
  button:setText(chatEnabled and tr('Chat On') or tr('Chat Off'))
  npcDialogInput:setEnabled(chatEnabled)
end

local function focusNpcDialogInputLater()
  scheduleEvent(function()
    if not npcDialogWindow or npcDialogWindow:isDestroyed() or not npcDialogWindow:isVisible() then
      return
    end

    updateNpcDialogChatMode()
    if npcDialogInput:isEnabled() then
      focusNpcDialogWidget(npcDialogInput)
    else
      focusNpcDialogWidget(npcDialogWindow)
    end
  end, 50)
end

local function placeNpcTradeBesideDialog()
  if not npcDialogWindow or not npcDialogWindow:isVisible() or not npcWindow or not npcWindow:isVisible() then
    return
  end

  local root = getNpcDialogRoot()
  if npcWindow:getParent() ~= root then
    npcWindow:setParent(root, true)
  end

  if not npcTradeOriginalHeight then
    npcTradeOriginalHeight = npcWindow:getHeight()
  end

  npcWindow:setDraggable(false)
  npcWindow:setHeight(npcDialogWindow:getHeight())
  npcWindow:setPosition({
    x = npcDialogWindow:getX() + npcDialogWindow:getWidth() + TRADE_GAP,
    y = npcDialogWindow:getY()
  })
  npcWindow:raise()
end

function syncNpcDialogTradePosition()
  if npcDialogPositioning or not npcDialogWindow or not npcDialogWindow:isVisible() then
    return
  end

  npcDialogPositioning = true
  local root = getNpcDialogRoot()
  local tradeVisible = npcWindow and npcWindow:isVisible()
  local tradeWidth = tradeVisible and npcWindow:getWidth() + TRADE_GAP or 0
  local totalWidth = npcDialogWindow:getWidth() + tradeWidth
  local x = math.max(0, math.floor((root:getWidth() - totalWidth) / 2))
  local y = math.max(0, math.floor((root:getHeight() - npcDialogWindow:getHeight()) / 2))

  npcDialogWindow:setPosition({ x = x, y = y })
  placeNpcTradeBesideDialog()
  npcDialogWindow:raise()
  if tradeVisible then
    npcWindow:raise()
  end
  npcDialogPositioning = false
  focusNpcDialogInputLater()
end

function prepareNpcTradeForDialog()
  if not npcDialogWindow or not npcDialogWindow:isVisible() then
    return false
  end

  local root = getNpcDialogRoot()
  if npcWindow:getParent() ~= root then
    npcWindow:setParent(root, true)
  end
  return true
end

function focusNpcDialogInput()
  if not npcDialogWindow or not npcDialogWindow:isVisible() then
    return false
  end

  updateNpcDialogChatMode()
  if npcDialogInput:isEnabled() then
    focusNpcDialogWidget(npcDialogInput)
  else
    focusNpcDialogWidget(npcDialogWindow)
  end
  return true
end

function initNpcDialog()
  if npcDialogWindow then
    return
  end

  npcDialogWindow = g_ui.loadUI('/modules/game_npctrade/npcdialog.otui', getNpcDialogRoot())
  if not npcDialogWindow then
    error('unable to load /modules/game_npctrade/npcdialog.otui')
  end
  npcDialogBuffer = npcDialogWindow:recursiveGetChildById('npcDialogBuffer')
  npcDialogInput = npcDialogWindow:recursiveGetChildById('npcDialogInput')

  local buttonsPanel = npcDialogWindow:recursiveGetChildById('npcDialogButtons')
  for _, data in ipairs(npcDialogButtons) do
    local button = g_ui.createWidget('NpcDialogQuickButton', buttonsPanel)
    local icon = button:getChildById('icon')
    icon:setImageClip(string.format('%d 0 32 32', data.sprite * 32))
    button:setTooltip(data.text)
    local buttonText = data.text
    button.onClick = function()
      sendNpcDialogText(buttonText)
    end
  end

  local closeButton = npcDialogWindow:recursiveGetChildById('closeButton')
  closeButton.onClick = function()
    closeNpcDialog()
  end
  closeButton:raise()

  npcDialogInput.onKeyPress = function(_, keyCode)
    if keyCode == KeyEnter or keyCode == KeyNumEnter then
      sendNpcDialogInput()
      return true
    end
    return false
  end

  npcDialogWindow.onEnter = function()
    sendNpcDialogInput()
  end
  npcDialogWindow.onFocus = function()
    if npcDialogInput:isEnabled() then
      focusNpcDialogWidget(npcDialogInput)
    end
  end
  npcDialogWindow.onMousePress = function(_, mousePos, mouseButton)
    if mouseButton == MouseLeftButton and mousePos.x >= closeButton:getX() and
        mousePos.x < closeButton:getX() + closeButton:getWidth() and
        mousePos.y >= closeButton:getY() and
        mousePos.y < closeButton:getY() + closeButton:getHeight() then
      closeNpcDialog()
      return true
    end

    if mouseButton == MouseLeftButton and npcDialogInput:isEnabled() then
      scheduleEvent(function()
        if npcDialogInput and not npcDialogInput:isDestroyed() and npcDialogInput:isEnabled() then
          focusNpcDialogWidget(npcDialogInput)
        end
      end, 1)
    end
    return false
  end

  npcDialogWindow.onGeometryChange = function()
    if not npcDialogPositioning then
      placeNpcTradeBesideDialog()
    end
  end

  registerMessageMode(MessageModes.Failure, onNpcTradeFailureMessage)
end

function terminateNpcDialog()
  unregisterMessageMode(MessageModes.Failure, onNpcTradeFailureMessage)
  if npcDialogWindow then
    npcDialogWindow:destroy()
  end
  npcDialogWindow = nil
  npcDialogBuffer = nil
  npcDialogInput = nil
  npcDialogName = nil
  npcDialogPendingMessages = {}
end

function resetNpcDialogSession()
  npcDialogSuppressed = false
  npcDialogPendingMessages = {}
  npcDialogName = nil
  if npcDialogBuffer then
    npcDialogBuffer:destroyChildren()
  end
end

function showNpcDialog(name)
  if not npcDialogWindow then
    initNpcDialog()
  end

  local isNewConversation = not npcDialogWindow:isVisible() or npcDialogName ~= name
  npcDialogName = name
  npcDialogWindow:recursiveGetChildById('npcDialogName'):setText(name)
  setNpcDialogCreature(name)

  if isNewConversation then
    npcDialogBuffer:destroyChildren()
    addTalkingToMessage(name)
    flushPendingPlayerMessages()
  end

  npcDialogWindow:show()
  npcDialogWindow:raise()
  syncNpcDialogTradePosition()
end

function hideNpcDialog()
  if npcDialogWindow then
    npcDialogWindow:hide()
  end
  npcDialogName = nil
  npcDialogPendingMessages = {}

  if npcWindow then
    npcWindow:setDraggable(true)
    if npcTradeOriginalHeight then
      npcWindow:setHeight(npcTradeOriginalHeight)
    end
  end
end

function closeNpcDialog()
  if not npcDialogWindow or not npcDialogWindow:isVisible() then
    return
  end

  npcDialogSuppressed = true
  if g_game.isOnline() and modules.game_console and modules.game_console.sendNpcMessage then
    modules.game_console.sendNpcMessage('bye')
  end
  if npcWindow and npcWindow:isVisible() then
    g_game.closeNpcTrade()
    hide()
  end
  if g_game.isOnline() then
    g_game.closeNpcChannel()
  end
  hideNpcDialog()
end

function onNpcDialogGameEnd()
  hide()
  hideNpcDialog()
  resetNpcDialogSession()
end

function onNpcTradeHidden()
  if npcWindow then
    npcWindow:setDraggable(true)
    if npcTradeOriginalHeight then
      npcWindow:setHeight(npcTradeOriginalHeight)
    end
  end
  if npcDialogWindow and npcDialogWindow:isVisible() then
    addEvent(syncNpcDialogTradePosition)
  end
end

function onNpcDialogTradeClosed()
  if not npcDialogWindow or not npcDialogWindow:isVisible() then
    return
  end

  npcDialogSuppressed = true
  hideNpcDialog()
end

function onNpcPlayerTalk(text)
  if not text or text == '' then
    return
  end

  local lowerText = text:lower():trim()
  if lowerText == 'hi' or lowerText == 'hello' then
    npcDialogSuppressed = false
  end

  if npcDialogWindow and npcDialogWindow:isVisible() then
    local playerName = g_game.getCharacterName() or tr('You')
    addNpcDialogMessage(playerName .. ': ' .. text, PLAYER_DIALOG_COLOR, playerName)
  else
    table.insert(npcDialogPendingMessages, { text = text, time = g_clock.millis() })
  end
end

function onNpcConversationAttempt(text)
  if not text then
    return
  end

  local lowerText = text:lower():trim()
  if lowerText == 'hi' or lowerText == 'hello' then
    npcDialogSuppressed = false
  end
end

function onNpcDialogTalk(name, level, mode, text)
  if mode ~= MessageModes.NpcFrom and mode ~= MessageModes.NpcFromStartBlock then
    return
  end

  if npcDialogSuppressed or not name or name == '' then
    return
  end

  showNpcDialog(name)
  addNpcDialogMessage(name .. ' says: ' .. text, NPC_DIALOG_COLOR, name)
end

function isNpcDialogMessageMode(mode)
  return mode == MessageModes.NpcFrom or mode == MessageModes.NpcFromStartBlock
end

function isNpcDialogActive()
  return npcDialogWindow and npcDialogWindow:isVisible() or false
end

function sendNpcDialogText(text)
  if not text or text == '' then
    return
  end

  local now = g_clock.millis()
  if npcDialogLastActionText == text and now - npcDialogLastActionTime < 150 then
    return
  end
  npcDialogLastActionText = text
  npcDialogLastActionTime = now

  local console = modules.game_console
  if not console or not console.sendNpcMessage then
    return
  end

  if not console.sendNpcMessage(text) then
    return
  end
  if text:lower():trim() == 'bye' then
    npcDialogSuppressed = true
    if npcWindow and npcWindow:isVisible() then
      g_game.closeNpcTrade()
      hide()
    end
    hideNpcDialog()
  end
end

function sendNpcDialogInput()
  if not npcDialogInput then
    return
  end

  local text = npcDialogInput:getText()
  if text and text ~= '' then
    npcDialogInput:clearText()
    sendNpcDialogText(text)
  end
end

function toggleNpcDialogChatMode()
  if modules.game_console and modules.game_console.toggleChat then
    modules.game_console.toggleChat()
  end
  updateNpcDialogChatMode()
  focusNpcDialogInputLater()
end
