local showHighlightedUnderline = false
local NPC_DIALOG_HEADER_COLOR = "white"

local function getHighlightedText(text, color, highlightColor)
    color = color or "white"
    highlightColor = highlightColor or "#1f9ffe"
    local parts = {}
    local firstBrace = text:find("{", 1, true)
    if not firstBrace then
        setStringColor(parts, text, color)
        return parts
    end
    local lastPos = 1
    for startPos, content, endPos in text:gmatch("()%{([^}]*)%}()") do
        if startPos > lastPos then
            setStringColor(parts, text:sub(lastPos, startPos - 1), color)
        end
        local textPart = content:match("([^,]+)") or content
        local trimmed = textPart
        local highlighted = trimmed
        if showHighlightedUnderline then
            highlighted = string.format("[text-event]%s[/text-event]", trimmed)
        else
            highlighted = string.format("[text-event]%s%s[/text-event]", string.char(1), trimmed)
        end
        setStringColor(parts, highlighted, highlightColor)
        lastPos = endPos
    end
    if lastPos <= #text then
        setStringColor(parts, text:sub(lastPos), color)
    end
    return parts
end

local function createDialogLabel(consoleBuffer, entry)
    local label = g_ui.createWidget('ConsoleLabel', consoleBuffer)
    label:setId("consoleLabel" .. consoleBuffer:getChildCount())

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
            onTextClick = function(w, t)
                controllerNpcTrader:onConsoleTextClicked(w, t)
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

local function findNpcCreature(name, creaturePos)
    if not name or name == "" then
        return nil
    end

    if creaturePos and g_map.getTile then
        local tile = g_map.getTile(creaturePos)
        if tile and tile.getCreatures then
            for _, creature in ipairs(tile:getCreatures()) do
                if creature and creature.getName and creature:getName() == name then
                    return creature
                end
            end
        end
    end

    local player = g_game.getLocalPlayer()
    if player and g_map.getSpectators then
        local spectators = g_map.getSpectators(player:getPosition(), false) or {}
        for _, creature in ipairs(spectators) do
            if creature and creature.getName and creature:getName() == name then
                return creature
            end
        end
    end

    return nil
end

function controllerNpcTrader:updateNpcIdentity(name, creature)
    if name and name ~= "" and name ~= g_game.getCharacterName() then
        self.creatureName = name
    end

    if creature then
        self.creatureName = creature:getName() or self.creatureName
        self.outfit = creature:getOutfit()
    elseif not self.outfit then
        self.outfit = "/game_npctrade/assets/images/icon-npcdialog-multiplenpcs"
    end

    local title = self:findWidget(".title")
    if title and self.creatureName then
        title:setText(self.creatureName)
    end

    local creatureOutfit = self:findWidget("#creatureOutfit")
    if creatureOutfit and self.outfit then
        if type(self.outfit) == "string" then
            creatureOutfit:setImageSource(self.outfit)
        else
            creatureOutfit:setOutfit(self.outfit)
        end
    end
end

function controllerNpcTrader:ensureDialogHeader(consoleBuffer)
    if not consoleBuffer or consoleBuffer:getChildCount() > 0 or not self.creatureName or self.creatureName == "" or
        self.creatureName == "Unknown" then
        return
    end

    createDialogLabel(consoleBuffer, buildTalkingToEntry(self.creatureName, os.date('%H:%M')))
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

    if consoleBuffer then
        consoleBuffer:destroyChildren()
        self:ensureDialogHeader(consoleBuffer)
        for _, entry in ipairs(self.dialogEntries or {}) do
            createDialogLabel(consoleBuffer, entry)
        end
    end
end

-- temp fix. can't drag the left panel to move the window.
function controllerNpcTrader:setupWindowDragBehavior()
    if not self.ui then
        return
    end
    local dragHandle = self:findWidget("#dragHandle")
    if not dragHandle then
        return
    end
    dragHandle:setDraggable(true)
    dragHandle.onDragEnter = function(widget, mousePos)
        return self.ui:onDragEnter(mousePos)
    end
    dragHandle.onDragMove = function(widget, mousePos, mouseMoved)
        self.ui:onDragMove(mousePos, mouseMoved)
        return true
    end
    dragHandle.onDragLeave = function(widget, droppedWidget, mousePos)
        self.ui:onDragLeave(droppedWidget, mousePos)
        return true
    end
end

local function setLayoutVisibility(widget, visible, display)
    if not widget then
        return
    end
    if widget.setDisplay then
        widget:setDisplay(visible and (display or "block") or "none")
    end
    if widget.setOpacity then
        widget:setOpacity(visible and 1 or 0)
    end
    if visible and widget.show then
        widget:show()
    elseif not visible and widget.hide then
        widget:hide()
    end
end

function controllerNpcTrader:updateTradeWindowLayout()
    local tradeVisible = self.isTradeOpen == true
    self.widthConsole = tradeVisible and self.TRADE_CONSOLE_WIDTH or self.DEFAULT_CONSOLE_WIDTH

    if self.ui and self.ui.setWidth then
        self.ui:setWidth(self.widthConsole)
    end

    local dragHandle = self:findWidget("#dragHandle")
    if dragHandle and dragHandle.setWidth then
        dragHandle:setWidth(self.widthConsole)
    end

    setLayoutVisibility(self:findWidget("#tradeSeparator"), tradeVisible)
    setLayoutVisibility(self:findWidget("#rightPanel"), tradeVisible)
    setLayoutVisibility(self:findWidget("#optionsButton"), tradeVisible)
end

function controllerNpcTrader:initNpcWindow(creature, buttons)
    if self:isLegacyMode() then
        return
    end
    self:connectNpcTalkEvent()
    self.dialogEntries = self.dialogEntries or {}
    self.widthConsole = self.isTradeOpen and self.TRADE_CONSOLE_WIDTH or self.DEFAULT_CONSOLE_WIDTH
    self:updateNpcIdentity(nil, creature)
    self.creatureName = (self.creatureName and self.creatureName ~= "") and self.creatureName or "Unknown"
    self.buttons = buttons or self.buttons or self.buttonsDefault
    self:updateChatButton()
    if not self.ui or not self.ui:isVisible() then
        self:loadHtml('templates/game_npctrader.html')
    end
    self:setupWindowDragBehavior()
    self:updateNpcIdentity(self.creatureName, creature)
    self:updateTradeWindowLayout()
    self:cloneConsoleMessages()
end

function onNpcChatWindow(data)
    if controllerNpcTrader:isLegacyMode() then
        controllerNpcTrader:legacy_show()
        return
    end
    if type(data) ~= "table" or type(data.npcIds) ~= "table" or #data.npcIds == 0 then
        return
    end
    local creature = g_map.getCreatureById(data.npcIds[1])
    if creature then
        controllerNpcTrader:initNpcWindow(creature, data.buttons)
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

function onNpcTalk(name, level, mode, text, channelId, creaturePos)
    local isNpcTalk = mode == MessageModes.NpcFrom or mode == MessageModes.NpcFromStartBlock
    local creature = isNpcTalk and findNpcCreature(name, creaturePos) or nil

    if not controllerNpcTrader:isLegacyMode() and
        isNpcTalk and
        (not controllerNpcTrader.ui or not controllerNpcTrader.ui:isVisible()) then
        controllerNpcTrader:updateNpcIdentity(name, creature)
        controllerNpcTrader:initNpcWindow(creature, controllerNpcTrader.buttonsDefault)
    end

    if not controllerNpcTrader.ui or not controllerNpcTrader.ui:isVisible() then
        return
    end

    if mode == MessageModes.NpcTo or mode == MessageModes.NpcFrom or mode == MessageModes.NpcFromStartBlock then
        if isNpcTalk then
            controllerNpcTrader:updateNpcIdentity(name, creature)
        end
        local consoleBuffer = controllerNpcTrader:findWidget("#consoleBuffer")
        if consoleBuffer then
            controllerNpcTrader:ensureDialogHeader(consoleBuffer)
            local consoleModule = modules.game_console
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
            local entry = {
                text = fullText,
                color = color,
                name = mode == MessageModes.NpcTo and g_game.getCharacterName() or name,
                clickable = true
            }
            if getHighlightedText then
                entry.coloredData = getHighlightedText(fullText, color, "#1f9ffe")
            end
            controllerNpcTrader.dialogEntries = controllerNpcTrader.dialogEntries or {}
            table.insert(controllerNpcTrader.dialogEntries, entry)
            createDialogLabel(consoleBuffer, entry)
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
