local showHighlightedUnderline = false
local function getHighlightedText(text, color, highlightColor)
    color = color or "white"
    highlightColor = highlightColor or "#1f9ffe"
    local firstBrace = text:find("{", 1, true)
    if not firstBrace then
        return string.format("{%s, %s}", text, color)
    end
    local parts = {}
    local lastPos = 1
    if firstBrace > 1 then
        parts[#parts + 1] = string.format("{%s, %s}", text:sub(1, firstBrace - 1), color)
    end
    for startPos, content, endPos in text:gmatch("()%{([^}]*)%}()") do
        local textPart = content:match("([^,]+)") or content
        local trimmed = textPart
        local highlighted = trimmed
        if showHighlightedUnderline then
            highlighted = string.format("[text-event]%s[/text-event]", trimmed)
        else
            highlighted = string.format("[text-event]%s%s[/text-event]", string.char(1), trimmed)
        end
        parts[#parts + 1] = string.format("{%s, %s}", highlighted, highlightColor)
        local nextBrace = text:find("{", endPos, true)
        local afterText = text:sub(endPos, (nextBrace or 0) - 1)
        if afterText ~= "" then
            parts[#parts + 1] = string.format("{%s, %s}", afterText, color)
        end
        lastPos = endPos
    end
    return table.concat(parts)
end

function controllerNpcTrader:onConsoleTextClicked(widget, text)
    if type(widget) == "string" and not text then
        text = widget
        widget = nil
    end

    if not text or text == "" then
        return
    end

    local npcTab = modules.game_console.consoleTabBar:getTab("NPCs")
    if npcTab then
        modules.game_console.sendMessage(text, npcTab)
        onNpcTalk(g_game.getCharacterName(), 0, MessageModes.NpcTo, text)
    end
    if text == "bye" then
        controllerNpcTrader:onCloseNpcTrade()
    end
end

function controllerNpcTrader:cloneConsoleMessages()
    local consoleBuffer = self:findWidget("#consoleBuffer")
    local consoleModule = modules.game_console

    if consoleBuffer and consoleModule then
        local childCount = consoleBuffer:getChildCount()

        if childCount == 0 then
            consoleBuffer:destroyChildren()
            local npcTab = consoleModule.getTab("NPCs")
            if not npcTab then
                npcTab = consoleModule.getTab("NPC")
            end
            if npcTab and consoleModule.consoleTabBar then
                local panel = consoleModule.consoleTabBar:getTabPanel(npcTab)
                if panel then
                    local tabBuffer = panel:getChildById('consoleBuffer')
                    if tabBuffer then
                        for _, child in pairs(tabBuffer:getChildren()) do
                            local label = g_ui.createWidget('ConsoleLabel', consoleBuffer)
                            label:setId(child:getId())
                            if child.coloredData then
                                label:setColoredText(child.coloredData)
                            else
                                label:setText(child:getText())
                            end
                            label:setColor(child:getColor())
                            if not label:hasEventListener(EVENT_TEXT_CLICK) then
                                label:setEventListener(EVENT_TEXT_CLICK)
                                connect(label, {
                                    onTextClick = function(w, t)
                                        controllerNpcTrader:onConsoleTextClicked(w, t)
                                    end
                                })
                            end
                        end
                    end
                end
            end
        end
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
        self.outfit = "/game_npctrader/assets/images/icon-npcdialog-multiplenpcs"
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
        if preset then
            for _, btn in ipairs(preset) do
                if not self._detectedButtonIds[btn.id] then
                    table.insert(self.buttons, btn)
                    self._detectedButtonIds[btn.id] = true
                end
            end
        end

        for _, btn in ipairs(self.buttonsDefault) do
            if not self._detectedButtonIds[btn.id] then
                table.insert(self.buttons, btn)
                self._detectedButtonIds[btn.id] = true
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
        self._initNpcWindowInProgress = false
    end
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

    self:cloneConsoleMessages()
    scheduleEvent(function()
        if not controllerNpcTrader or not controllerNpcTrader.setupTradeAmountInputHooks then return end
        if not controllerNpcTrader.ui or controllerNpcTrader.ui:isDestroyed() then return end
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
    self:loadHtml('templates/game_npctrader.html')
    local creatureOutfit = self:findWidget("#creatureOutfit")
    if creatureOutfit and self.outfit then
        if type(self.outfit) == "string" then
            creatureOutfit:setImageSource(self.outfit)
        else
            creatureOutfit:setOutfit(self.outfit)
        end
    end
    self:cloneConsoleMessages()
    scheduleEvent(function()
        if not controllerNpcTrader or not controllerNpcTrader.setupTradeAmountInputHooks then return end
        if not controllerNpcTrader.ui or controllerNpcTrader.ui:isDestroyed() then return end
        controllerNpcTrader:setupTradeAmountInputHooks()
    end, 0)
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
            local insertPos = #self.buttons - 2
            if insertPos < 1 then insertPos = 1 end
            table.insert(self.buttons, insertPos, btnDef)
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
    local tradeId = KeywordButtonIcon.KEYWORDBUTTONICON_GENERALTRADE
    if not self._detectedButtonIds[tradeId] then
        self._detectedButtonIds[tradeId] = true
        local btnDef = { id = tradeId, text = "trade" }
        local insertPos = #self.buttons - 2
        if insertPos < 1 then insertPos = 1 end
        table.insert(self.buttons, insertPos, btnDef)
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
            local consoleModule = modules.game_console
            local label = g_ui.createWidget('ConsoleLabel', consoleBuffer)
            label:setId("consoleLabel" .. consoleBuffer:getChildCount())
            local SpeakTypes = consoleModule and consoleModule.SpeakTypes or {}
            local color = '#5FF7F7'
            if SpeakTypes[mode] and SpeakTypes[mode].color then
                color = SpeakTypes[mode].color
            end
            local fullText = text
            if mode == MessageModes.NpcFrom or mode == MessageModes.NpcFromStartBlock then
                fullText = name .. " says: " .. text
            elseif mode == MessageModes.NpcTo then
                fullText = name .. ": " .. text
            end
            if getHighlightedText then
                local highlightData = getHighlightedText(fullText, color, "#1f9ffe")
                label:setColoredText(highlightData)
            else
                label:setText(fullText)
            end
            label:setColor(color)
            if not label:hasEventListener(EVENT_TEXT_CLICK) then
                label:setEventListener(EVENT_TEXT_CLICK)
                connect(label, {
                    onTextClick = function(w, t)
                        controllerNpcTrader:onConsoleTextClicked(w, t)
                    end
                })
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
