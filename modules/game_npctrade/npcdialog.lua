local NPC_DIALOG_COLOR = '#5ff7f7'
local PLAYER_DIALOG_COLOR = '#9f9dfd'
local TALKING_TO_COLOR = '#ffffff'
local HIGHLIGHT_COLOR = '#1f9ffe'
local MAX_DIALOG_MESSAGES = 200
local MAX_PENDING_MESSAGES = 20
local PENDING_MESSAGE_TIMEOUT = 10000
local TRADE_GAP = 2

local npcDialogWindow
local npcDialogBuffer
local npcDialogInput
local npcDialogName
local npcDialogPendingMessages = {}
local npcDialogSuppressed = false
local npcDialogPositioning = false
local npcDialogFailureRegistered = false
local npcDialogScrollEvent
local npcDialogFocusEvent
local npcDialogTradePositionEvent
local npcTradeOriginalState

local npcDialogButtons = {
  { text = 'yes', sprite = 7 },
  { text = 'no', sprite = 8 },
  { text = 'bye', sprite = 9 },
  { text = 'trade', sprite = 0 }
}

local function isWidgetAlive(widget)
  return widget and not widget:isDestroyed()
end

local function removeNpcDialogEvent(event)
  if event then
    removeEvent(event)
  end
end

local function cancelNpcDialogEvents()
  removeNpcDialogEvent(npcDialogScrollEvent)
  removeNpcDialogEvent(npcDialogFocusEvent)
  removeNpcDialogEvent(npcDialogTradePositionEvent)
  npcDialogScrollEvent = nil
  npcDialogFocusEvent = nil
  npcDialogTradePositionEvent = nil
end

local function releaseLabelPointerCursor(label)
  if not label or not label.pointerCursorActive then
    return
  end

  if label.pointerCursorNative then
    g_mouse.restoreNativeCursor()
  else
    g_mouse.popCursor('pointer')
  end
  label.pointerCursorActive = false
  label.pointerCursorNative = nil
end

local function releaseNpcDialogCursors()
  if not isWidgetAlive(npcDialogBuffer) then
    return
  end

  for _, label in ipairs(npcDialogBuffer:getChildren()) do
    releaseLabelPointerCursor(label)
  end
end

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
  local hasHighlights = false
  local cursor = 1

  while true do
    local startPos, endPos, word = text:find('{([^}]+)}', cursor)
    if not startPos then
      local tail = text:sub(cursor)
      if tail ~= '' then
        setStringColor(colored, tail, defaultColor)
      end
      break
    end

    local before = text:sub(cursor, startPos - 1)
    if before ~= '' then
      setStringColor(colored, before, defaultColor)
    end

    setStringColor(colored, '[text-event]' .. word .. '[/text-event]', HIGHLIGHT_COLOR)
    hasHighlights = true
    cursor = endPos + 1
  end

  return colored, hasHighlights
end

local function addNpcDialogMessage(text, color, creatureName)
  if not isWidgetAlive(npcDialogBuffer) then
    return
  end

  while npcDialogBuffer:getChildCount() >= MAX_DIALOG_MESSAGES do
    local firstChild = npcDialogBuffer:getFirstChild()
    releaseLabelPointerCursor(firstChild)
    firstChild:destroy()
  end

  local label = g_ui.createWidget('NpcDialogLabel', npcDialogBuffer)
  label:setId('npcDialogLabel' .. npcDialogBuffer:getChildCount())
  label.creatureName = creatureName

  local fullText = getTimestampPrefix() .. text
  local colored, hasHighlights = buildColoredDialogText(fullText, color)

  function label.onMouseRelease(widget, mousePos, mouseButton)
    if mouseButton == MouseLeftButton then
      return false
    elseif mouseButton == MouseRightButton then
      local copiedName = widget.creatureName
      local copiedMessage = widget:getText()
      local menu = g_ui.createWidget('PopupMenu')
      menu:setGameMenu(true)
      if copiedName and copiedName ~= '' then
        menu:addOption(tr('Copy name'), function()
          g_window.setClipboardText(copiedName)
        end)
      end
      menu:addOption(tr('Copy message'), function()
        g_window.setClipboardText(copiedMessage)
      end)
      menu:display(mousePos)
      return true
    end
    return false
  end

  if hasHighlights then
    label:setEventListener(EVENT_TEXT_CLICK)
    label:setEventListener(EVENT_TEXT_HOVER)

    label.onTextClick = function(_, word)
      sendNpcDialogText(word)
    end

    label.onTextHoverChange = function(widget, _, hovered)
      if hovered then
        if not widget.pointerCursorActive then
          widget.pointerCursorNative = g_mouse.applyNativeCursor('pointer')
          if not widget.pointerCursorNative then
            g_mouse.pushCursor('pointer')
          end
          widget.pointerCursorActive = true
        end
      else
        releaseLabelPointerCursor(widget)
      end
    end

    label.onDestroy = function(widget)
      releaseLabelPointerCursor(widget)
    end
  end

  label:setColoredText(colored)

  removeNpcDialogEvent(npcDialogScrollEvent)
  npcDialogScrollEvent = addEvent(function()
    npcDialogScrollEvent = nil
    if g_game.isOnline() and isWidgetAlive(npcDialogBuffer) and isWidgetAlive(label) then
      npcDialogBuffer:ensureChildVisible(label)
    end
  end)
end

local function addTalkingToMessage(name)
  addNpcDialogMessage(tr('Talking to %s', name), TALKING_TO_COLOR)
end

local function onNpcTradeFailureMessage(_, text)
  if not text or text == '' or not isWidgetAlive(npcDialogWindow) or not npcDialogWindow:isVisible() or
      not isWidgetAlive(npcWindow) or not npcWindow:isVisible() then
    return
  end

  addNpcDialogMessage(text, TALKING_TO_COLOR)
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

local function addPendingPlayerMessage(text)
  local now = g_clock.millis()
  local pending = {}
  for _, message in ipairs(npcDialogPendingMessages) do
    if now - message.time <= PENDING_MESSAGE_TIMEOUT then
      table.insert(pending, message)
    end
  end
  npcDialogPendingMessages = pending

  while #npcDialogPendingMessages >= MAX_PENDING_MESSAGES do
    table.remove(npcDialogPendingMessages, 1)
  end
  table.insert(npcDialogPendingMessages, { text = text, time = now })
end

local function setNpcDialogCreature(name)
  if not isWidgetAlive(npcDialogWindow) then
    return
  end

  local creature = findNpcCreature(name)
  local outfitWidget = npcDialogWindow:recursiveGetChildById('npcDialogCreature')
  local fallbackWidget = npcDialogWindow:recursiveGetChildById('npcDialogFallback')
  if not isWidgetAlive(outfitWidget) or not isWidgetAlive(fallbackWidget) then
    return
  end
  local hasCreature = creature ~= nil

  outfitWidget:setVisible(hasCreature)
  fallbackWidget:setVisible(not hasCreature)
  if creature then
    outfitWidget:setOutfit(creature:getOutfit())
  end
end

local function updateNpcDialogChatMode()
  if not isWidgetAlive(npcDialogWindow) or not isWidgetAlive(npcDialogInput) then
    return
  end

  local chatEnabled = modules.game_console and modules.game_console.isChatEnabled and
      modules.game_console.isChatEnabled()
  local button = npcDialogWindow:recursiveGetChildById('npcDialogChatMode')
  if isWidgetAlive(button) then
    button:setText(chatEnabled and tr('Chat On') or tr('Chat Off'))
  end
  npcDialogInput:setEnabled(chatEnabled)
end

local function focusNpcDialogInputLater(delay)
  removeNpcDialogEvent(npcDialogFocusEvent)
  npcDialogFocusEvent = scheduleEvent(function()
    npcDialogFocusEvent = nil
    if not g_game.isOnline() or not isWidgetAlive(npcDialogWindow) or
        not npcDialogWindow:isVisible() or not isWidgetAlive(npcDialogInput) then
      return
    end

    updateNpcDialogChatMode()
    if npcDialogInput:isEnabled() then
      focusNpcDialogWidget(npcDialogInput)
    else
      focusNpcDialogWidget(npcDialogWindow)
    end
  end, delay or 50)
end

local function rememberNpcTradeState()
  if npcTradeOriginalState or not isWidgetAlive(npcWindow) then
    return
  end

  local position = npcWindow:getPosition()
  npcTradeOriginalState = {
    parent = npcWindow:getParent(),
    position = { x = position.x, y = position.y },
    height = npcWindow:getHeight(),
    draggable = npcWindow:isDraggable()
  }
end

local function restoreNpcTradeState()
  local state = npcTradeOriginalState
  npcTradeOriginalState = nil
  if not state or not isWidgetAlive(npcWindow) then
    return
  end

  npcWindow:setDraggable(state.draggable)
  npcWindow:setHeight(state.height)
  if isWidgetAlive(state.parent) then
    if npcWindow:getParent() ~= state.parent then
      npcWindow:setParent(state.parent, true)
    end
    npcWindow:setPosition(state.position)
  end
end

local function placeNpcTradeBesideDialog()
  if not isWidgetAlive(npcDialogWindow) or not npcDialogWindow:isVisible() or
      not isWidgetAlive(npcWindow) or not npcWindow:isVisible() then
    return
  end

  local root = getNpcDialogRoot()
  if not isWidgetAlive(root) then
    return
  end
  rememberNpcTradeState()
  if npcWindow:getParent() ~= root then
    npcWindow:setParent(root, true)
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
  if npcDialogPositioning or not g_game.isOnline() or not isWidgetAlive(npcDialogWindow) or
      not npcDialogWindow:isVisible() then
    return
  end

  npcDialogPositioning = true
  local root = getNpcDialogRoot()
  if not isWidgetAlive(root) then
    npcDialogPositioning = false
    return
  end
  local tradeVisible = isWidgetAlive(npcWindow) and npcWindow:isVisible()
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

function scheduleNpcDialogTradePosition(delay)
  removeNpcDialogEvent(npcDialogTradePositionEvent)
  npcDialogTradePositionEvent = scheduleEvent(function()
    npcDialogTradePositionEvent = nil
    syncNpcDialogTradePosition()
  end, delay or 0)
end

function prepareNpcTradeForDialog()
  if not isWidgetAlive(npcDialogWindow) or not npcDialogWindow:isVisible() or not isWidgetAlive(npcWindow) then
    return false
  end

  local root = getNpcDialogRoot()
  if not isWidgetAlive(root) then
    return false
  end
  rememberNpcTradeState()
  if npcWindow:getParent() ~= root then
    npcWindow:setParent(root, true)
  end
  return true
end

function focusNpcDialogInput()
  if not isWidgetAlive(npcDialogWindow) or not npcDialogWindow:isVisible() or not isWidgetAlive(npcDialogInput) then
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
  if isWidgetAlive(npcDialogWindow) then
    return
  end
  npcDialogWindow = nil

  local root = getNpcDialogRoot()
  if not isWidgetAlive(root) then
    error('unable to find NPC dialog root panel')
  end

  npcDialogWindow = g_ui.loadUI('/modules/game_npctrade/npcdialog.otui', root)
  if not npcDialogWindow then
    error('unable to load /modules/game_npctrade/npcdialog.otui')
  end
  npcDialogBuffer = npcDialogWindow:recursiveGetChildById('npcDialogBuffer')
  npcDialogInput = npcDialogWindow:recursiveGetChildById('npcDialogInput')

  local buttonsPanel = npcDialogWindow:recursiveGetChildById('npcDialogButtons')
  if not isWidgetAlive(npcDialogBuffer) or not isWidgetAlive(npcDialogInput) or not isWidgetAlive(buttonsPanel) then
    npcDialogWindow:destroy()
    npcDialogWindow = nil
    npcDialogBuffer = nil
    npcDialogInput = nil
    error('NPC dialog UI is missing required widgets')
  end

  for _, data in ipairs(npcDialogButtons) do
    local button = g_ui.createWidget('NpcDialogQuickButton', buttonsPanel)
    local icon = button:getChildById('icon')
    if isWidgetAlive(icon) then
      icon:setImageClip(string.format('%d 0 32 32', data.sprite * 32))
    end
    button:setTooltip(data.text)
    local buttonText = data.text
    button.onClick = function()
      sendNpcDialogText(buttonText)
    end
  end

  npcDialogWindow.onFocus = function()
    if isWidgetAlive(npcDialogInput) and npcDialogInput:isEnabled() then
      focusNpcDialogWidget(npcDialogInput)
    end
  end
  npcDialogWindow.onMousePress = function(_, _, mouseButton)
    if mouseButton == MouseLeftButton and isWidgetAlive(npcDialogInput) and npcDialogInput:isEnabled() then
      focusNpcDialogInputLater(1)
    end
    return false
  end

  npcDialogWindow.onGeometryChange = function()
    if not npcDialogPositioning then
      placeNpcTradeBesideDialog()
    end
  end

  if not npcDialogFailureRegistered then
    registerMessageMode(MessageModes.Failure, onNpcTradeFailureMessage)
    npcDialogFailureRegistered = true
  end
end

function terminateNpcDialog()
  if npcDialogFailureRegistered then
    unregisterMessageMode(MessageModes.Failure, onNpcTradeFailureMessage)
    npcDialogFailureRegistered = false
  end
  cancelNpcDialogEvents()
  releaseNpcDialogCursors()
  restoreNpcTradeState()
  if isWidgetAlive(npcDialogWindow) then
    npcDialogWindow:destroy()
  end
  npcDialogWindow = nil
  npcDialogBuffer = nil
  npcDialogInput = nil
  npcDialogName = nil
  npcDialogPendingMessages = {}
  npcDialogSuppressed = false
  npcDialogPositioning = false
end

function resetNpcDialogSession()
  cancelNpcDialogEvents()
  releaseNpcDialogCursors()
  restoreNpcTradeState()
  npcDialogSuppressed = false
  npcDialogPositioning = false
  npcDialogPendingMessages = {}
  npcDialogName = nil
  if isWidgetAlive(npcDialogBuffer) then
    npcDialogBuffer:destroyChildren()
  end
end

function showNpcDialog(name)
  if not name or name == '' then
    return false
  end
  if not isWidgetAlive(npcDialogWindow) then
    initNpcDialog()
  end
  if not isWidgetAlive(npcDialogWindow) or not isWidgetAlive(npcDialogBuffer) then
    return false
  end

  local isNewConversation = not npcDialogWindow:isVisible() or npcDialogName ~= name
  local nameLabel = npcDialogWindow:recursiveGetChildById('npcDialogName')
  if not isWidgetAlive(nameLabel) then
    return false
  end
  npcDialogName = name
  nameLabel:setText(name)
  setNpcDialogCreature(name)

  if isNewConversation then
    releaseNpcDialogCursors()
    npcDialogBuffer:destroyChildren()
    addTalkingToMessage(name)
    flushPendingPlayerMessages()
  end

  npcDialogWindow:show()
  npcDialogWindow:raise()
  syncNpcDialogTradePosition()
  return true
end

function hideNpcDialog()
  cancelNpcDialogEvents()
  releaseNpcDialogCursors()
  if isWidgetAlive(npcDialogWindow) then
    npcDialogWindow:hide()
  end
  npcDialogName = nil
  npcDialogPendingMessages = {}
  npcDialogPositioning = false
  restoreNpcTradeState()
end

function closeNpcDialog()
  if not isWidgetAlive(npcDialogWindow) or not npcDialogWindow:isVisible() then
    return
  end

  npcDialogSuppressed = true
  if g_game.isOnline() and modules.game_console and modules.game_console.sendNpcMessage then
    modules.game_console.sendNpcMessage('bye')
  end
  if isWidgetAlive(npcWindow) and npcWindow:isVisible() then
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
  restoreNpcTradeState()
  if isWidgetAlive(npcDialogWindow) and npcDialogWindow:isVisible() then
    scheduleNpcDialogTradePosition()
  end
end

function onNpcDialogTradeClosed()
  if not isWidgetAlive(npcDialogWindow) or not npcDialogWindow:isVisible() then
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

  if isWidgetAlive(npcDialogWindow) and npcDialogWindow:isVisible() then
    local playerName = g_game.getCharacterName() or tr('You')
    addNpcDialogMessage(playerName .. ': ' .. text, PLAYER_DIALOG_COLOR, playerName)
  else
    addPendingPlayerMessage(text)
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

function tryHandleNpcDialogMessage(name, _, mode, text)
  if mode ~= MessageModes.NpcFrom and mode ~= MessageModes.NpcFromStartBlock then
    return false
  end

  if npcDialogSuppressed or not name or name == '' or not text or text == '' then
    return false
  end

  if not showNpcDialog(name) then
    return false
  end
  addNpcDialogMessage(name .. ' says: ' .. text, NPC_DIALOG_COLOR, name)
  return true
end

function sendNpcDialogText(text)
  if not text or text == '' then
    return
  end

  local console = modules.game_console
  if not console or not console.sendNpcMessage then
    return
  end

  if not console.sendNpcMessage(text) then
    return
  end
  if text:lower():trim() == 'bye' then
    npcDialogSuppressed = true
    if isWidgetAlive(npcWindow) and npcWindow:isVisible() then
      g_game.closeNpcTrade()
      hide()
    end
    hideNpcDialog()
  end
end

function sendNpcDialogInput()
  if not isWidgetAlive(npcDialogInput) then
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
