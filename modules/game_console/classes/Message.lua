
Message = {}
function Message.new()
    local obj = {
        timestamp = 0,
        text = "",
        level = 0,
        mode = 0,
        statement = 0,
        name = "",
        tab = nil,
        label = nil,
    }
    setmetatable(obj, { __index = Message })
    return obj
end

function Message:setup(name, level, mode, text, statement, groupId)
    self.timestamp = os.time()
    self.text = text
    self.level = level
    self.mode = mode
    self.statement = statement
    self.name = name
    self.groupId = groupId or 1
end

function Message:clear()
    self.timestamp = 0
    self.text = ''
    self.level = 0
    self.mode = 0
    self.statement = 0
    self.name = ''
    self.tab = nil
    if self.label and self.label:getChildCount() > 0 then
        self.label:destroyChildren()
    end
    self.label = nil
end

function Message:getText()
    return self.text
end

function Message:format()
    local text = ''
    if m_settings.getOption('showTimestampsInConsole') then
        local formatted = '%H:%M'
        if m_settings.getOption('showSecondTimestampsInConsole') then
            formatted = formatted .. ':%S'
        end
        text = text .. os.date(formatted, self.timestamp)
    end

    if self.name ~= '' then
        text = text .. ' ' .. self.name

        if self.level > 0 and m_settings.getOption('showLevelsInConsole') then
            text = text .. ' [' .. self.level .. ']'
        end

        text = text .. ':'
    end

    text = text .. ' ' .. self.text
    return text
end

function Message:formatcolor()
    local color = 'white'
    local mt = MessageTypes[self.mode]
    if mt then
        color = mt.color
    end

    local text = {}
    if m_settings.getOption('showTimestampsInConsole') then
        local formatted = '%H:%M'
        if m_settings.getOption('showSecondTimestampsInConsole') then
            formatted = formatted .. ':%S'
        end
        formatted = formatted .. ' '
        setStringColor(text, os.date(formatted, self.timestamp), color)
    end

    if self.name ~= '' then
        local t_text = ''
        t_text = t_text .. ' ' .. self.name

        if self.level > 0 then
            t_text = t_text .. ' [' .. self.level .. ']'
        end

        t_text = t_text .. ':'

        setStringColor(text, t_text, color)
    end

    for i = 1, #self.text do
        table.insert(text, self.text[i])
    end

    return text
end


function Message:updateLabel(label, tab)
    label.message = self
    self.label = label
    self.tab = tab
    local speaktype = MessageTypes[self.mode]
    if type(self.text) == 'table' then
        label:setColoredText(self:formatcolor())
    else
        local mt = MessageTypes[self.mode]
        if mt then
            label:setColor(mt.color)
        end
        -- self:format() is plain text (no [color=...] markup), so the whole line must
        -- take the single label color set above via setColor(mt.color). The Lua
        -- setColorText shim (corelib/globals.lua) has no native C++ binding and, for
        -- markup-less text, wraps everything as white [#ffffff] colored fragments,
        -- which override m_color at draw time (uiwidgettext drawText prefers
        -- m_drawTextColors). That turned player say/channel speech white -> looked like
        -- a server message. setText clears m_drawTextColors so mt.color applies, exactly
        -- like the reference client's addTabText (setText + setColor) path.
        label:setText(self:format())
    end

    if label:getChildCount() > 0 then
        label:destroyChildren()
    end

    label.keywords = {}
    label:removeEventListener(EVENT_TEXT_CLICK)
    label:removeEventListener(EVENT_TEXT_HOVER)

    -- speaktype is MessageTypes[self.mode]; guard against an unmapped mode (the
    -- 15.24 mode remap can yield a value not in MessageTypes), which otherwise
    -- threw "attempt to index a nil value (speaktype)" on every NPC chat line.
    if speaktype and speaktype.npcChat and self.level == 0 then
        self:highlightNPCChatText(label)
    end
    label:show()
end

function Message:handleMouseRelease(label, mousePos, mouseButton)
    if label.speaktype and label.speaktype.npcChat then
        if mouseButton == MouseLeftButton then
            local position = label:getTextPos(mousePos)
            if position and label.highlightInfo[position] then
                g_chat:sendMessage(label.highlightInfo[position], self.tab)
            end
        elseif mouseButton == MouseRightButton then
            self:processMessageMenu(mousePos, mouseButton)
        end
    else
        if mouseButton == MouseRightButton then
            self:processMessageMenu(mousePos, mouseButton, label)
        end
    end
end

function Message:processMessageMenu(mousePos, mouseButton, label)
    local isPlayer = self.level > 0
    local tab = self.tab
    local text = label and label:getText() or ''
    if mouseButton == MouseRightButton then
      local menu = g_ui.createWidget('PopupMenu')
      menu:setGameMenu(true)
      if text then
        if (self.name and #self.name > 0) and self.name ~= g_game.getCharacterName() then
          if isPlayer then
            menu:addOption(tr('Message to ' .. self.name), function () g_game.openPrivateChannel(self.name) end)
            if not g_game.getLocalPlayer():hasVip(self.name) then
              menu:addOption(tr('Add ' .. self.name .. ' to VIP list'), function () g_game.addVip(self.name) end)
            end
            if modules.game_console.hasOwnPrivateTab() then
              menu:addSeparator()
              menu:addOption(tr('Invite to private chat'), function() g_game.inviteToOwnChannel(self.name) end)
              menu:addOption(tr('Exclude from private chat'), function() g_game.excludeFromOwnChannel(self.name) end)
            end
            if Communication:isIgnored(self.name) then
              menu:addOption(tr('Unignore') .. ' ' .. self.name, function() Communication:removeIgnoredPlayer(self.name) end)
            else
              menu:addOption(tr('Ignore') .. ' ' .. self.name, function() Communication:addIgnoredPlayer(self.name) end)
            end
            menu:addSeparator()
          end
        end

        local isReadOnly = label.readOnly
        local buffer = isReadOnly and g_chat:getReadOnlyBuffer() or g_chat:getBuffer()
        menu:addOption(tr('Select all'), function()
            g_chat:selectAll(buffer)
        end)

        local selection = buffer.selectionText
        if selection and #selection > 0 then
          menu:addOption(tr('Copy'), function() tab.widget:onCopyText(selection) end)
        end
        menu:addOption(tr('Copy message'), function() tab.widget:onCopyText(label:getText()) end)
        if isPlayer and self.name ~= g_game.getCharacterName() then
          menu:addSeparator()
          menu:addOption(tr('Report Statement'), function() modules.game_report.doReportStatement(self.statement, self.name, label:getText()) end)
          menu:addOption(tr('Report Name'), function() modules.game_report.doReportName(self.name) end)
        elseif self.name ~= g_game.getCharacterName() then
          menu:addSeparator()
          menu:addOption(tr('Report Message'), function() modules.game_bugreport.show(nil, 1) end)
        end

        if (self.name and #self.name > 0) then
          menu:addSeparator()
          menu:addOption(tr('Copy name'), function () tab.widget:onCopyText(self.name) end)
        end
      end

      menu:display({ x = mousePos.x, y = (mousePos.y - menu:getHeight() + 20) })
    end
end

function Message:handleDragMove(label, mousePos)
    local parent = label:getParent()
    local selfIndex = parent:getChildIndex(label)
    local child = self:findChildByPos(label, parent, mousePos, selfIndex)

    if not child then return false end

    local childIndex = parent:getChildIndex(child)

    local buffer = label.readOnly and g_chat:getReadOnlyBuffer() or g_chat:getBuffer()
    g_chat:clearSelection(buffer)
    self:updateSelection(label, mousePos, child, selfIndex, childIndex)
end

function Message:findChildByPos(widget, parent, mousePos, selfIndex)
    if mousePos.y < widget:getY() then
        for index = selfIndex - 1, 1, -1 do
            local label = parent:getChildByIndex(index)
            if label:getY() + label:getHeight() > parent:getPaddingRect().y then
                if (mousePos.y >= label:getY() and mousePos.y <= label:getY() + label:getHeight()) or index == 1 then
                    return label
                end
            else
                return parent:getChildByIndex(index + 1)
            end
        end
    elseif mousePos.y > widget:getY() + widget:getHeight() then
        for index = selfIndex + 1, parent:getChildCount(), 1 do
            local label = parent:getChildByIndex(index)
            if label:getY() < parent:getPaddingRect().y + parent:getPaddingRect().height then
                if (mousePos.y >= label:getY() and mousePos.y <= label:getY() + label:getHeight()) or index == parent:getChildCount() then
                    return label
                end
            else
                return parent:getChildByIndex(index - 1)
            end
        end
    end

    return widget
end

function Message:updateSelection(label, mousePos, child, selfIndex, childIndex)
    local textBegin = label:getTextPos(label:getLastClickPosition())
    local textPos = label:getTextPos(mousePos)
    label:setSelection(textBegin, textPos)

    local buffer = label.readOnly and g_chat:getReadOnlyBuffer() or g_chat:getBuffer()

    buffer.selection = { first = math.min(selfIndex, childIndex), last = math.max(selfIndex, childIndex) }

    if child ~= label then
        for selectionChildIndex = buffer.selection.first + 1, buffer.selection.last - 1 do
            local selectionChild = label:getParent():getChildByIndex(selectionChildIndex)
            if selectionChild then
                selectionChild:selectAll()
            end
        end

        local _textPos = child:getTextPos(mousePos)
        if childIndex > selfIndex then
            child:setSelection(0, _textPos)
        else
            child:setSelection(string.len(child:getText()), _textPos)
        end
    end
end

function Message:handleDragLeave(label)
    -- g_chat:clearSelection()
    local text = {}

    local consoleBuffer = label.readOnly and g_chat:getReadOnlyBuffer() or g_chat:getBuffer()
    if consoleBuffer == nil or consoleBuffer.selection == nil or consoleBuffer.selection.last == nil then return end
    for selectionChildIndex = consoleBuffer.selection.first, consoleBuffer.selection.last do
      local selectionChild = label:getParent():getChildByIndex(selectionChildIndex)
      if selectionChild then
        table.insert(text, selectionChild:getSelection())
      end
    end
    consoleBuffer.selectionText = table.concat(text, '\n')
end

function Message:selectWordFromPos(label, consoleBuffer)
    local text = label:getText()
    local pos = label:getTextPos(label:getLastClickPosition())
    local firstSpace = 0
    local lastSpace = string.len(text)
    local textLength = string.len(text)

    if string.len(text) > 0 then
        local firstSpaceSelected = false
        for i = 0, textLength do
            if i < pos and i < textLength then
                local letter = text:byte(i)
                if letter == string.byte(" ") or letter == string.byte("\t") or letter == string.byte("\n") then
                    firstSpace = i
                    firstSpaceSelected = true
                end
            end
        end
        for i = pos, textLength do
            local letter = text:byte(i)
            if i < textLength and letter == string.byte(" ") or letter == string.byte("\t") or letter == string.byte("\n") then
                lastSpace = i - 1
                break
            end
        end
        if not firstSpaceSelected then
            return
        end
        label:setSelection(firstSpace, lastSpace);
        local texts = {}
        table.insert(texts, label:getSelection())
        consoleBuffer.selectionText = table.concat(texts, '\n')
    end
end

function Message:highlightNPCChatText(label)
    local transformedText = self:format()

    -- Build the [text, color, text, color, ...] fragment list for setColoredText.
    -- Words wrapped in {braces} are the keywords the player can click to say them, so
    -- each is emitted as a [text-event]keyword[/text-event] fragment. When the click/hover
    -- listeners are active, the layout pass (UITextEdit -> getDisplayedText ->
    -- processCodeTags) strips those markers from the rendered text, records the keyword
    -- and its on-screen rect (m_rectToWord), and setColoredText compensates the color
    -- offsets by the 25-char marker overhead. The braces themselves never get drawn.
    local fragments = {}
    local normalColor = TextColors.lightblue
    local keywordColor = TextColors.darkblue
    local buffer = ''
    local hasKeyword = false

    local i, n = 1, #transformedText
    while i <= n do
        local char = transformedText:sub(i, i)
        if char == '{' then
            if #buffer > 0 then
                table.insert(fragments, buffer)
                table.insert(fragments, normalColor)
                buffer = ''
            end
            local keyword = ''
            i = i + 1
            while i <= n do
                local kc = transformedText:sub(i, i)
                if kc == '}' then break end
                keyword = keyword .. kc
                i = i + 1
            end
            if #keyword > 0 then
                table.insert(fragments, '[text-event]' .. keyword .. '[/text-event]')
                table.insert(fragments, keywordColor)
                hasKeyword = true
            end
        else
            buffer = buffer .. char
        end
        i = i + 1
    end
    if #buffer > 0 then
        table.insert(fragments, buffer)
        table.insert(fragments, normalColor)
    end

    -- Listeners must be set *before* setColoredText so processCodeTags runs on the first
    -- layout pass; otherwise the [text-event] markers would render literally.
    if hasKeyword then
        if not label:hasEventListener(EVENT_TEXT_CLICK) then
            label:setEventListener(EVENT_TEXT_CLICK)
        end
        if not label:hasEventListener(EVENT_TEXT_HOVER) then
            label:setEventListener(EVENT_TEXT_HOVER)
        end
        label.onTextClick = onConsoleTextClicked
        label.onTextHoverChange = onTextHoverChange
    end

    label:setColoredText(fragments)
end

function Message:debug()
    print("----DEBUG----")
    print(self.timestamp)
    print(self.text)
    print(self.level)
    print(self.mode)
    print(self.statement)
    print(self.name)
end

-- Fired by the C++ side (UIWidget::onClick -> getTextByPos) with the clicked keyword.
-- `text` is the keyword as registered via [text-event]; clicking it says it to the NPC.
function onConsoleTextClicked(widget, text, mousePos)
    if not text or #text == 0 then
        return
    end
    local npcTab = g_chat:getTabByName(NPC_NAME_CHAT)
    if npcTab then
        g_chat:sendMessage(text, npcTab)
    end
end

-- Fired by the C++ side (UIManager::updateHoveredText) only when the cursor enters or
-- leaves a registered keyword, so each `true` is matched by a later `false`.
function onTextHoverChange(widget, text, hovered)
    if hovered then
        g_mouse.pushCursor("pointer")
    else
        g_mouse.popCursor("pointer")
    end
end
