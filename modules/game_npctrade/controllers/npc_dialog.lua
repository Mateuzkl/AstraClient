local showHighlightedUnderline = false
local NPC_DIALOG_HEADER_COLOR = "white"

local function getHighlightedText(text, color, highlightColor, label)
    color = color or "white"
    highlightColor = highlightColor or "#1f9ffe"

    if g_chat and g_chat.getNewHighlightedText and label then
        return g_chat:getNewHighlightedText(text, color, highlightColor, label)
    end

    local colored = {}
    local firstBrace = text:find("{", 1, true)
    if not firstBrace then
        setStringColor(colored, text, color)
        return colored
    end
    local lastPos = 1
    for startPos, content, endPos in text:gmatch("()%{([^}]*)%}()") do
        if startPos > lastPos then
            setStringColor(colored, text:sub(lastPos, startPos - 1), color)
        end
        local textPart = content:match("([^,]+)") or content
        local trimmed = textPart
        local highlighted = trimmed
        if showHighlightedUnderline then
            highlighted = string.format("[text-event]%s[/text-event]", trimmed)
        else
            highlighted = string.format("[text-event]%s%s[/text-event]", string.char(1), trimmed)
        end
        setStringColor(colored, highlighted, highlightColor)
        lastPos = endPos
    end
    if lastPos <= #text then
        setStringColor(colored, text:sub(lastPos), color)
    end
    return colored
end

local function getNpcConsoleTab()
    local names = { NPC_NAME_CHAT or "NPCs", "NPCs", "NPC" }
    for _, name in ipairs(names) do
        local tab = nil
        if g_chat and g_chat.getTabByName then
            tab = g_chat:getTabByName(name)
        end
        if not tab and modules.game_console and modules.game_console.getTabByName then
            tab = modules.game_console.getTabByName(name)
        end
        if tab then
            return tab
        end
    end
    return nil
end

function controllerNpcTrader:getNpcConsoleTab()
    return getNpcConsoleTab()
end

function controllerNpcTrader:sendNpcConsoleMessage(text)
    if not text or text == "" then
        return false
    end
    if g_game and g_game.talkPrivate and self.creatureName and self.creatureName ~= "" and self.creatureName ~= "Unknown" then
        g_game.talkPrivate(MessageModes.NpcTo, self.creatureName, text)
        return true
    end
    if g_game and g_game.talkChannel then
        g_game.talkChannel(MessageModes.NpcTo, 0, text)
        return true
    end
    return false
end

local function cacheKeywordRanges(label, text)
    if not label then return end
    label.keywords = {}

    local openedIndex = nil
    local charIndex = 1
    for i = 1, #text do
        local char = text:sub(i, i)
        if char == "{" then
            openedIndex = charIndex
        elseif char == "}" and openedIndex then
            table.insert(label.keywords, { openedIndex, charIndex })
            openedIndex = nil
        else
            charIndex = charIndex + 1
        end
    end
end

local function createDialogLabel(consoleBuffer, entry)
    local label = g_ui.createWidget('ConsoleLabel', consoleBuffer)
    label:setId("consoleLabel" .. consoleBuffer:getChildCount())
    label.keywords = {}

    if entry.coloredData then
        label:setColoredText(entry.coloredData)
        label.coloredData = entry.coloredData
    else
        label:setText(entry.text or "")
    end

    if entry.color then
        label:setColor(entry.color)
    end

    if entry.name then
        label.name = entry.name
    end

    if entry.clickable and not label:hasEventListener(EVENT_TEXT_CLICK) then
        label:setEventListener(EVENT_TEXT_CLICK)
        connect(label, {
            onTextClick = function(w, t, index)
                controllerNpcTrader:onConsoleTextClicked(w, t, index)
            end
        })
    end

    return label
end

local function buildTalkingToEntry(npcName, timestamp)
    local prefix = timestamp and (timestamp .. " ") or ""
    return {
        text = prefix .. "talking to " .. npcName,
        color = NPC_DIALOG_HEADER_COLOR
    }
end

function controllerNpcTrader:ensureDialogHeader(consoleBuffer)
    if not consoleBuffer or consoleBuffer:getChildCount() > 0 or not self.creatureName or self.creatureName == "" then
        return
    end

    createDialogLabel(consoleBuffer, buildTalkingToEntry(self.creatureName, os.date('%H:%M')))
end

function controllerNpcTrader:onConsoleTextClicked(widget, text, index)
    if type(widget) == "string" and not text then
        text = widget
        widget = nil
    end

    if widget and index and text and widget.keywords then
        for _, range in pairs(widget.keywords) do
            local beginIndex, lastIndex = range[1] - 1, range[2] - 1
            if beginIndex <= index and index < lastIndex then
                text = text:sub(beginIndex + 1, lastIndex)
                break
            end
        end
    end

    if not text or text == "" then
        return
    end

    local sent = self:sendNpcConsoleMessage(text)
    if sent then
        onNpcTalk(g_game.getCharacterName(), 0, MessageModes.NpcTo, text)
    end
    if text == "bye" then
        controllerNpcTrader:onCloseNpcTrade(sent)
    end
end

function controllerNpcTrader:onNpcButtonClick(target)
    local buttonData = target and target.buttonData
    if not buttonData or not buttonData.text then
        return false
    end
    self:onConsoleTextClicked(buttonData.text)
    return true
end

local function getNpcButtonData(widget)
    if not widget then
        return nil
    end
    if widget.buttonData then
        return widget.buttonData
    end
    local ctx = widget.__html_for_ctx
    if not ctx then
        return nil
    end
    return ctx.buttonData or (ctx.values and ctx.values[1]) or nil
end

function controllerNpcTrader:setupNpcButtonHooks()
    if not self.ui or self.ui:isDestroyed() then
        return
    end

    local panel = self.ui:recursiveGetChildById("panelBotons")
    if not panel or panel:isDestroyed() then
        return
    end

    for i = 1, panel:getChildCount() do
        local button = panel:getChildByIndex(i)
        if button and not button:isDestroyed() then
            local buttonData = getNpcButtonData(button)
            if buttonData and buttonData.text then
                button.buttonData = buttonData
                if button.setTooltip then
                    button:setTooltip(buttonData.text)
                end
                button.onClick = function(widget)
                    return controllerNpcTrader:onNpcButtonClick(widget)
                end
            end
        end
    end
end

function controllerNpcTrader:cloneConsoleMessages()
    local consoleBuffer = self:findWidget("#consoleBuffer")

    if consoleBuffer then
        consoleBuffer:destroyChildren()
        self:ensureDialogHeader(consoleBuffer)
    end
end

function controllerNpcTrader:setupWindowDragBehavior()
    if not self.ui or self.ui:isDestroyed() then
        return
    end

    local dragHandle = self:findWidget("#dragHandle")
    if not dragHandle or dragHandle:isDestroyed() then
        return
    end

    if dragHandle.setHeight then
        dragHandle:setHeight(27)
    end
    if dragHandle.setWidth and self.widthConsole then
        dragHandle:setWidth(self.widthConsole)
    end
    if dragHandle.setFocusable then
        dragHandle:setFocusable(false)
    end

    dragHandle:setDraggable(true)
    dragHandle.onDragEnter = function(_, mousePos)
        return self.ui:onDragEnter(mousePos)
    end
    dragHandle.onDragMove = function(_, mousePos, mouseMoved)
        self.ui:onDragMove(mousePos, mouseMoved)
        return true
    end
    dragHandle.onDragLeave = function(_, droppedWidget, mousePos)
        self.ui:onDragLeave(droppedWidget, mousePos)
        return true
    end
end

function controllerNpcTrader:focusNpcTextInput(widget)
    if not widget or widget:isDestroyed() then
        return false
    end

    if self._npcInputLockWidget == widget then
        if g_ui and g_ui.setInputLockWidget then
            g_ui.setInputLockWidget(widget)
        end
        if widget.grabKeyboard then
            widget:grabKeyboard()
        end
        if widget.focus then
            widget:focus()
        end
        return false
    end

    local previous = nil
    if g_ui and g_ui.getCustomInputWidget then
        local ok, current = pcall(function()
            return g_ui.getCustomInputWidget()
        end)
        if ok then
            previous = current
        end
    end
    if previous and previous ~= widget and previous.ungrabKeyboard then
        pcall(function() previous:ungrabKeyboard() end)
    end

    if g_mouse and g_mouse.clearGrabber then
        g_mouse.clearGrabber()
    end
    if g_ui and g_ui.setInputLockWidget then
        g_ui.setInputLockWidget(widget)
    end
    self._npcInputLockWidget = widget

    if widget.setFocusable then
        widget:setFocusable(true)
    end
    if widget.setPhantom then
        widget:setPhantom(false)
    end
    if widget.grabKeyboard then
        widget:grabKeyboard()
    end
    if modules.game_npctrade and modules.game_npctrade.toggleNPCFocus then
        modules.game_npctrade.toggleNPCFocus(true)
    end
    if widget.focus then
        widget:focus()
    end
    return false
end

function controllerNpcTrader:releaseNpcTextInput(widget)
    widget = widget or self._npcInputLockWidget
    if not widget then
        return
    end
    if widget and self._npcInputLockWidget ~= widget then
        return
    end

    local lockedWidget = nil
    if g_ui and g_ui.getCustomInputWidget then
        local ok, current = pcall(function()
            return g_ui.getCustomInputWidget()
        end)
        if ok then
            lockedWidget = current
        end
    end

    if not lockedWidget or lockedWidget == widget then
        if widget.ungrabKeyboard then
            pcall(function() widget:ungrabKeyboard() end)
        end
        if g_ui and g_ui.setInputLockWidget then
            g_ui.setInputLockWidget(nil)
        end
    end
    self._npcInputLockWidget = nil
end

function controllerNpcTrader:setupNpcTextInputHooks()
    if not self.ui or self.ui:isDestroyed() then
        return
    end

    local ids = { "chatInput", "tradeSearchInput", "tradeAmountInput" }
    for _, id in ipairs(ids) do
        local input = self.ui:recursiveGetChildById(id)
        if input and not input:isDestroyed() then
            input.onMousePress = function(widget)
                return controllerNpcTrader:focusNpcTextInput(widget)
            end
            input.onClick = function(widget)
                controllerNpcTrader:focusNpcTextInput(widget)
                return false
            end
        end
    end
end

function controllerNpcTrader:syncNpcDialogLayout()
    if not self.ui or self.ui:isDestroyed() then
        return
    end

    if WidgetWatch and WidgetWatch.update then
        WidgetWatch.update()
    end

    if self.ui.updateParentLayout then self.ui:updateParentLayout() end
    if self.ui.updateLayout then self.ui:updateLayout() end
    self:setupWindowDragBehavior()
    self:setupNpcButtonHooks()
    self:setupNpcTextInputHooks()
    if self.setupTradeControlHooks then
        self:setupTradeControlHooks()
    end
    if self.setupTradeAmountInputHooks then
        self:setupTradeAmountInputHooks()
    end
    if self.centerHtmlWindow then
        self:centerHtmlWindow(self.ui)
    elseif self.ui.raise then
        self.ui:raise()
    end
end

function controllerNpcTrader:findNearestNpc()
    local player = g_game.getLocalPlayer()
    if not player then return nil end
    local pos = player:getPosition()
    local spectators = g_map.getSpectatorsInRangeEx(pos, false, 4, 4, 4, 4)
    local nearest = nil
    local nearestDist = math.huge
    for _, spec in ipairs(spectators) do
        if spec:isNpc() then
            local spos = spec:getPosition()
            local dist = math.abs(spos.x - pos.x) + math.abs(spos.y - pos.y)
            if dist < nearestDist then
                nearestDist = dist
                nearest = spec
            end
        end
    end
    return nearest
end

-- Debounce: várias chamadas (onNpcChatWindow + onNpcTalk) viram uma única abertura no próximo tick.
local function _flushNpcWindowOpen()
    controllerNpcTrader._openScheduled = false
    local pending = controllerNpcTrader._pendingOpen
    if not pending then return end
    controllerNpcTrader._pendingOpen = nil
    controllerNpcTrader:initNpcWindow(pending.creature, pending.buttons)
end

function controllerNpcTrader:requestOpenNpcWindow(creature, buttons)
    if self.ui and not self.ui:isDestroyed() then
        return
    end
    local prev = self._pendingOpen
    self._pendingOpen = {
        creature = creature or (prev and prev.creature),
        buttons = buttons or (prev and prev.buttons)
    }
    if not self._openScheduled then
        self._openScheduled = true
        scheduleEvent(_flushNpcWindowOpen, 0)
    end
end

function controllerNpcTrader:initNpcWindow(creature, buttons)
    self.widthConsole = self.DEFAULT_CONSOLE_WIDTH
    self.isTradeOpen = false
    if not creature then
        creature = self:findNearestNpc()
    end
    if creature then
        self.creatureName = creature:getName() or "Unknown"
        self.outfit = creature:getOutfit()
    else
        self.creatureName = "Unknown"
        self.outfit = "/game_npctrade/assets/images/icon-npcdialog-multiplenpcs"
    end
    if buttons then
        self.buttons = buttons
        self._detectedButtonIds = {}
        for _, btn in ipairs(buttons) do
            self._detectedButtonIds[btn.id] = true
        end
    elseif not self.buttons then
        self.buttons = {}
        self._detectedButtonIds = {}

        local npcNameLower = self.creatureName:lower()
        local preset = self.npcButtonPresets[npcNameLower]
        if not preset and npcNameLower:find("^hireling") then
            preset = self.npcButtonPresets["hireling"]
        end
        for _, btn in ipairs(self.buttonsDefault) do
            if not self._detectedButtonIds[btn.id] then
                table.insert(self.buttons, btn)
                self._detectedButtonIds[btn.id] = true
            end
        end

        if preset then
            for _, btn in ipairs(preset) do
                if not self._detectedButtonIds[btn.id] then
                    table.insert(self.buttons, btn)
                    self._detectedButtonIds[btn.id] = true
                end
            end
        end
    end

    -- Modo clássico: sem HTML; conversa no canal NPC da consola; trade em janela legacy.
    if not self:useNewNpcDialog() then
        self._classicNpcMode = true
        if self.ui and not self.ui:isDestroyed() then
            pcall(function() self:unloadHtml() end)
        end
        self.ui = nil
        self.htmlId = nil
        self._initNpcWindowInProgress = false
        return
    end
    self._classicNpcMode = false

    self:updateChatButton()
    -- Evita duplicata: (1) já existe janela válida OU (2) outra chamada já está criando (onNpcChatWindow + onNpcTalk no mesmo tick).
    local haveValidWindow = (self.ui and not self.ui:isDestroyed()) or (self._initNpcWindowInProgress == true)
    if not haveValidWindow then
        self._initNpcWindowInProgress = true
        if self.ui then
            pcall(function() self:unloadHtml() end)
        end
        self:loadHtml('templates/game_npctrader.html')
        if self.syncPublicWidgets then
            self:syncPublicWidgets()
            addEvent(function()
                if controllerNpcTrader and controllerNpcTrader.syncPublicWidgets then
                    controllerNpcTrader:syncPublicWidgets()
                end
            end)
        end
        self._initNpcWindowInProgress = false
    end
    self:setupWindowDragBehavior()
    local creatureOutfit = self:findWidget("#creatureOutfit")
    if creatureOutfit then
        if type(self.outfit) == "string" then
            creatureOutfit:setImageSource(self.outfit)
        else
            creatureOutfit:setOutfit(self.outfit)
        end
    end

    local inputConsole = self:findWidget(".inputConsole")
    if inputConsole then
        inputConsole.onFocusChange = function(widget, focused)
            if focused then
                controllerNpcTrader:focusNpcTextInput(widget)
            else
                controllerNpcTrader:releaseNpcTextInput(widget)
            end
        end
        inputConsole.onKeyPress = function(widget, keyCode, keyboardModifiers, autoRepeatTicks)
            if keyCode == KeyEnter then
                local raw = widget:getText()
                local text = raw and raw:match("^%s*(.-)%s*$") or ""
                if #text > 0 then
                    controllerNpcTrader:onConsoleTextClicked(nil, text)
                    widget:clearText()
                end
                return true
            end
            return false
        end
    end

    self:setupNpcTextInputHooks()
    self:setupNpcButtonHooks()
    if self.setupTradeControlHooks then
        self:setupTradeControlHooks()
    end
    self:cloneConsoleMessages()
    self:syncNpcDialogLayout()
    scheduleEvent(function()
        if not controllerNpcTrader or not controllerNpcTrader.setupTradeAmountInputHooks then return end
        if not controllerNpcTrader.ui or controllerNpcTrader.ui:isDestroyed() then return end
        controllerNpcTrader:setupNpcTextInputHooks()
        controllerNpcTrader:setupNpcButtonHooks()
        if controllerNpcTrader.setupTradeControlHooks then
            controllerNpcTrader:setupTradeControlHooks()
        end
        controllerNpcTrader:setupTradeAmountInputHooks()
    end, 0)
end

function onNpcChatWindow(data)
    if not controllerNpcTrader:useNewNpcDialog() then
        return
    end
    if data and data.npcIds and data.npcIds[1] then
        local creature = g_map.getCreatureById(data.npcIds[1])
        controllerNpcTrader:requestOpenNpcWindow(creature, data.buttons)
    else
        controllerNpcTrader:requestOpenNpcWindow(nil, nil)
    end
end

function controllerNpcTrader:onConsoleKeyPress(event)
    if event.value == KeyEnter then
        local input = controllerNpcTrader:findWidget(".inputConsole")
        if input then
            local text = input:getText()
            if text and #text > 0 then
                controllerNpcTrader:onConsoleTextClicked(nil, text)
                input:clearText()
            end
        end
    end
end

local function isNpcFarewellMessage(text)
    if not text or type(text) ~= "string" then return true end
    local lower = text:lower()
    if lower:find("good bye") or lower:find("goodbye") or lower:find("bye and come again") then
        return true
    end
    if lower:find("ate logo") or lower:find("ate a proxima") or lower:find("tchau") then
        return true
    end
    if lower:find("farewell") or lower:find("see you") then
        return true
    end
    return false
end

local function extractKeywordsFromMessage(text)
    local keywords = {}
    for content in text:gmatch("%{([^}]+)%}") do
        local keyword = content:match("([^,]+)")
        if keyword then
            keywords[#keywords + 1] = keyword:lower():match("^%s*(.-)%s*$")
        end
    end
    return keywords
end

function controllerNpcTrader:reloadButtonsUI()
    if not self.ui or not self.ui:isVisible() then return end
    if refreshHtmlFor then
        refreshHtmlFor(self, "panelBotons")
    end
    self:setupNpcButtonHooks()
    self:setupNpcTextInputHooks()
    if self.setupTradeControlHooks then
        self:setupTradeControlHooks()
    end
    if self.setupTradeAmountInputHooks then
        self:setupTradeAmountInputHooks()
    end
    self:syncNpcDialogLayout()
end

function controllerNpcTrader:detectAndAddButtons(text)
    if not text or not self.keywordButtonMap then return end
    if not self._detectedButtonIds then
        self._detectedButtonIds = {}
    end

    local keywords = extractKeywordsFromMessage(text)
    local added = false

    for _, keyword in ipairs(keywords) do
        local btnDef = self.keywordButtonMap[keyword]
        if btnDef and not self._detectedButtonIds[btnDef.id] then
            self._detectedButtonIds[btnDef.id] = true
            table.insert(self.buttons, btnDef)
            added = true
        end
    end

    if added then
        self:reloadButtonsUI()
    end
end

function controllerNpcTrader:addTradeButton()
    if not self:useNewNpcDialog() then
        return
    end
    if not self._detectedButtonIds then
        self._detectedButtonIds = {}
    end
    local tradeId = controllerNpcTrader.KeywordButtonIcon.KEYWORDBUTTONICON_GENERALTRADE
    if not self._detectedButtonIds[tradeId] then
        self._detectedButtonIds[tradeId] = true
        local btnDef = { id = tradeId, text = "trade" }
        table.insert(self.buttons, btnDef)
        self:reloadButtonsUI()
    end
end

function onNpcTalk(name, level, mode, text, channelId, creaturePos)
    if controllerNpcTrader:useNewNpcDialog() then
        if mode == MessageModes.NpcFrom or mode == MessageModes.NpcFromStartBlock then
            if not controllerNpcTrader.ui or not controllerNpcTrader.ui:isVisible() then
                local closedAt = controllerNpcTrader._closedAt or 0
                local elapsed = g_clock.millis() - closedAt
                if elapsed > 2000 and not isNpcFarewellMessage(text) then
                    controllerNpcTrader:requestOpenNpcWindow(nil, nil)
                end
            end
        end

        if not controllerNpcTrader.ui or not controllerNpcTrader.ui:isVisible() then
            return
        end

        if mode == MessageModes.NpcFrom or mode == MessageModes.NpcFromStartBlock then
            controllerNpcTrader:detectAndAddButtons(text)
        end
    else
        -- Consola já mostra NPC via onTalk; não duplicar nem abrir HTML.
        return
    end

    if mode == MessageModes.NpcTo or mode == MessageModes.NpcFrom or mode == MessageModes.NpcFromStartBlock then
        local consoleBuffer = controllerNpcTrader:findWidget("#consoleBuffer")
        if consoleBuffer then
            controllerNpcTrader:ensureDialogHeader(consoleBuffer)
            local color = '#5FF7F7'
            if MessageTypes and MessageTypes[mode] and MessageTypes[mode].color then
                color = MessageTypes[mode].color
            end
            local fullText = text
            if mode == MessageModes.NpcFrom or mode == MessageModes.NpcFromStartBlock then
                fullText = name .. " says: " .. text
            elseif mode == MessageModes.NpcTo then
                fullText = name .. ": " .. text
            end
            local entry = {
                text = fullText,
                color = color,
                name = mode == MessageModes.NpcTo and g_game.getCharacterName() or name,
                clickable = true
            }
            local label = createDialogLabel(consoleBuffer, entry)
            if getHighlightedText then
                cacheKeywordRanges(label, fullText)
                entry.coloredData = getHighlightedText(fullText, color, "#1f9ffe", label)
                label:setColoredText(entry.coloredData)
                label.coloredData = entry.coloredData
            end
        end
    end
end

function controllerNpcTrader:updateChatButton()
    local isChatEnabled = modules.game_console.isChatEnabled()
    self.chatMode = isChatEnabled and tr('Chat On') or tr('Chat Off')
    local inputConsole = self:findWidget(".inputConsole")
    if inputConsole then
        inputConsole:setEnabled(isChatEnabled)
    end
end

function controllerNpcTrader:toggleChatMode()
    modules.game_console.toggleChat()
    self:updateChatButton()
end
