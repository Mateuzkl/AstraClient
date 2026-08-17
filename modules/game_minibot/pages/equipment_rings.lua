equipment_ringsModule = {}

local equipmentRingsWindow = nil
local catcherBuildEvent = nil
local catcherGeneration = 0
local CATCHER_BATCH_SIZE = 2

local function widgetAlive(widget)
    if widget == nil then
        return false
    end

    if g_ui ~= nil and type(g_ui.isWidgetAlive) == 'function' then
        local ok, alive = pcall(g_ui.isWidgetAlive, widget)
        return ok and alive == true
    end

    local ok, destroyed = pcall(function()
        return widget:isDestroyed()
    end)
    return ok and not destroyed
end

local function cancelCatcherBuild()
    catcherGeneration = catcherGeneration + 1
    local event = catcherBuildEvent
    catcherBuildEvent = nil
    if event ~= nil then
        pcall(removeEvent, event)
    end
end

local function buildCatcherInBatches(page, entries, createEntry)
    cancelCatcherBuild()
    local generation = catcherGeneration
    local index = 1
    local buildBatch

    local function pageIsCurrent()
        return generation == catcherGeneration and
            page == equipmentRingsWindow and
            widgetAlive(page) and widgetAlive(page.dropDownMenu)
    end

    local function queueBatch()
        if not pageIsCurrent() then
            return
        end

        local event
        event = scheduleEvent(function()
            if catcherBuildEvent ~= event then
                return
            end
            catcherBuildEvent = nil
            buildBatch()
        end, 1)
        catcherBuildEvent = event
    end

    buildBatch = function()
        if not pageIsCurrent() then
            return
        end

        local lastIndex = math.min(#entries, index + CATCHER_BATCH_SIZE - 1)
        while index <= lastIndex do
            local entry = entries[index]
            index = index + 1
            local ok, err = pcall(createEntry, entry)
            if not ok then
                g_logger.error('[game_minibot] ring catcher entry failed: ' .. tostring(err))
            end
            if not pageIsCurrent() then
                return
            end
        end

        if index <= #entries then
            queueBatch()
        end
    end

    queueBatch()
end

function equipment_ringsModule.isValidEquipmentEntry(entry)
    if type(entry) ~= 'table' or (tonumber(entry['item']) or 0) <= 0 then
        return false
    end
    return (tonumber(entry['min']) or 0) > 0 or
        (tonumber(entry['max']) or 0) > 0 or
        (tonumber(entry['manaMin']) or 0) > 0 or
        (tonumber(entry['manaMax']) or 0) > 0
end

function equipment_ringsModule.bindIgnoreEntryRemoval(widget)
    if widget == nil then
        return false
    end
    widget.onMousePress = equipment_ringsModule.onItemIgnoreDropDownEntryMousePress
    return true
end

local itemList = {
    -- Falta o blister ring

    39188, -- Arboreal Ring
    39185, -- Arcanomancer Sigil
    3092, -- Axe Ring
    39182, -- Alicorn Ring
    --31621, -- Blister Ring
    25698, -- Butterfly Ring
    39180, -- Charged Alicorn Ring
    3093, -- Club Ring
    6299, -- Death Ring
    3097, -- Dwarven Ring
    --31557, -- Enchanted Blister Ring
    32621, -- Enchanted Ring of Souls
    3051, -- Energy Ring
    50149, -- Ethereal Ring
    50147, -- Charged Ethereal Ring
    3052, -- Life Ring
    --3048, -- Might Ring
    3050, -- power ring
    16114, -- Prismatic Ring
    23529, -- Ring of Blue Plasma
    23531, -- Ring of Green Plasma
    3098, -- Ring of Healing
    50150, -- Ring of Orange Plasma
    23533, -- Ring of Red Plasma
    45642, -- Ring of Temptation
    39177, -- Spiritthorn Ring
    12669, -- Star Ring
    3049, -- Stealth Ring
    3091, -- Sword Ring
    3053, -- Time Ring
    41136, -- Elemental Energy Ring
    41134, -- Elemental Earth Ring
    41132, -- Elemental Death Ring
    41142, -- Elemental Ice Ring
    41140, -- Elemental Holy Ring
    41138, -- Elemental Fire Ring
}

local ignoreAppendItemsList = {
    3048, -- Might Ring
}

local similaritems = {
    [39177] = { 39177, 39178, 39179 },
    [39180] = { 39180, 39181, 39182 },
    [39185] = { 39183, 39184, 39185 },
    [39188] = { 39186, 39187, 39188 },
    [3092] = { 3092, 3095 },
    [50149] = { 50147, 50149 },
    [3093] = { 3093, 3096 },
    [6299] = { 6299, 6300 },
    [3097] = { 3097, 3099 },
    [32621] = { 32621, 32636 },
    [3051] = { 3051, 3088 },
    [3052] = { 3052, 3089 },
    [3050] = { 3050, 3087 },
    [16114] = { 16114, 16264 },
    [23529] = { 23529, 23530 },
    [23531] = { 23531, 23532 },
    [3098] = { 3098, 3100 },
    [50150] = { 50150, 50151 },
    [23533] = { 23533, 23534 },
    [12669] = { 12669, 12670 },
    [3049] = { 3049, 3086 },
    [3091] = { 3091, 3094 },
    [3053] = { 3053, 3090 },
    [41136] = { 41136, 41104 },
    [41134] = { 41134, 41102 },
    [41132] = { 41132, 41100 },
    [41142] = { 41142, 41110 },
    [41140] = { 41140, 41108 },
    [41138] = { 41138, 41106 },
}

function equipment_ringsModule.init(widget)
    cancelCatcherBuild()
    equipmentRingsWindow = widget

    equipmentRingsWindow.fromText = 'From'
    equipmentRingsWindow.toText = 'To'
    local language = modules.game_minibot.getSettingsValue(false, 'language', 'ptbr')
    if language == 'ptbr' then
        equipmentRingsWindow.fromText = 'De'
        equipmentRingsWindow.toText = 'Ate'
    elseif language == 'enus' then
        equipmentRingsWindow.fromText = 'From'
        equipmentRingsWindow.toText = 'To'
    end

    equipment_ringsModule.loadSettings()
end

function equipment_ringsModule.terminate()
    local page = equipmentRingsWindow
    equipment_ringsModule.closeCatcher()

    if equipmentRingsWindow == page then
        equipmentRingsWindow = nil
    end
end

function equipment_ringsModule.reloadInternalModule()
    local settings = modules.game_minibot.getPressetSettings()

    local list = {}
    local sList = settings['equipment_rings'] or {}
    for _, entry in pairs(sList) do
        table.insert(list, entry)
    end

    table.sort(list, function(a, b)
        return a.priority < b.priority
    end)

    g_minibot.resetModule(11) -- Rings Module type
    for _, entry in ipairs(list) do
        local internal = {
            item = tonumber(entry['item']),
            min = tonumber(entry['min']),
            max = tonumber(entry['max']),
            manaMin = tonumber(entry['manaMin']),
            manaMax = tonumber(entry['manaMax']),
            enabled = entry['enabled'],
            spell = "",
            reqmana = tonumber(entry['reqmana']) or 0,
            harmony = tonumber(entry['harmony']) or 0,
            use = entry['unequip'],

            spellGroup = {},
            spellId = {},

            area = "",
            target = "",
            health = 0,
            mana = 0,
            hits = 0,
            itemGroup = {},
        }

        if entry['ignore_enabled'] then
            for _, ignore in pairs(entry['ignore'] or {}) do
                local similar = similaritems[ignore]
                if similar ~= nil then
                    for _, id in ipairs(similar) do
                        table.insert(internal.spellGroup, id)
                    end
                else
                    table.insert(internal.spellGroup, ignore)
                end
            end
        end

        local similar = similaritems[internal.item]
        if similar ~= nil then
            for _, id in ipairs(similar) do
                table.insert(internal.itemGroup, id)
            end
        end

        g_minibot.addModule(11, internal)
    end
end

local function reloadListBackgrounds()
    local isSelected = false

    for _, c in ipairs(equipmentRingsWindow.priority.list:getChildren()) do
        if not(c.ignoreBackground) then
            c:setBackgroundColor('alpha')

            if c.mask:isVisible() then
                isSelected = true
            end
        end
    end

    if not(isSelected) then
        equipmentRingsWindow.config.notSelected:show()
        equipmentRingsWindow.config.panel:hide()
    else
        equipmentRingsWindow.config.notSelected:hide()
        equipmentRingsWindow.config.panel:show()
    end
end

function equipment_ringsModule.closeCatcher()
    cancelCatcherBuild()
    local windowCatcher = modules.game_minibot.getDropDownCatcher()
    if widgetAlive(windowCatcher) then
        pcall(function()
            windowCatcher:hide()
            windowCatcher.onLeftClick = nil
        end)
    end

    local page = equipmentRingsWindow
    if not widgetAlive(page) then
        return
    end

    pcall(function()
        if widgetAlive(page.dropDownCatcher) then
            page.dropDownCatcher:hide()
            page.dropDownCatcher.onLeftClick = nil
        end
        if widgetAlive(page.dropDownMenuScrollBar) then
            page.dropDownMenuScrollBar:hide()
        end
        if widgetAlive(page.dropDownMenu) then
            page.dropDownMenu:hide()
        end
    end)
end

function equipment_ringsModule.openCatcher(isIgnore)
    local page = equipmentRingsWindow
    if not widgetAlive(page) then
        return
    end

    page.dropDownCatcher:show()
    page.dropDownCatcher.onLeftClick = equipment_ringsModule.closeCatcher

    local windowCatcher = modules.game_minibot.getDropDownCatcher()
    if widgetAlive(windowCatcher) then
        windowCatcher:show()
        windowCatcher.onLeftClick = equipment_ringsModule.closeCatcher
    end

    page.dropDownMenu:show()
    page.dropDownMenuScrollBar:show()
    page.dropDownMenu:destroyChildren()

    if isIgnore then
        page.dropDownMenu:setMarginLeft(4)
    else
        page.dropDownMenu:setMarginLeft(50)
    end

    local function createItemEntry(item)
        local itemType = g_things.getThingType(item, ThingCategoryItem)
        if itemType then
            local itemWidget = g_ui.createWidget('MiniBotEquipmentRingitemDropDownEntry', page.dropDownMenu)
            itemWidget:setItemId(itemType:getId())
            itemWidget:setTooltip(itemType:getName())

            itemWidget.onLeftClick = function()
                if page ~= equipmentRingsWindow or not widgetAlive(page) then
                    return
                end
                if isIgnore then
                    local ignoreWidget = g_ui.createWidget('MiniBotEquipmentRingitemDropDownEntry', page.config.panel.ignore.list)
                    ignoreWidget:setItemId(itemType:getId())
                    ignoreWidget:setTooltip(itemType:getName())

                    equipment_ringsModule.bindIgnoreEntryRemoval(ignoreWidget)

                    local ignoreButton = page.config.panel.ignore.list:getChildById('ignoreAdd')
                    if ignoreButton ~= nil then
                        page.config.panel.ignore.list:moveChildToIndex(ignoreButton, page.config.panel.ignore.list:getChildCount())
                    end
                else
                    page.config.panel.item:show()
                    page.config.panel.item:setItemId(itemType:getId())
                    page.config.panel.frameBackground:setTooltip(page.config.panel.item:getItem():getName())
                end

                equipment_ringsModule.closeCatcher()
            end
        end
    end

    local entries = {}
    for _, item in ipairs(itemList) do
        entries[#entries + 1] = item
    end
    if isIgnore then
        for _, item in ipairs(ignoreAppendItemsList) do
            entries[#entries + 1] = item
        end
    end
    buildCatcherInBatches(page, entries, createItemEntry)
end

function equipment_ringsModule.loadSettings()
    local settings = modules.game_minibot.getPressetSettings()

    local list = {}
    local sList = settings['equipment_rings'] or {}
    local sSettings = settings['shortcuts'] or {}
    for _, entry in pairs(sList) do
        table.insert(list, entry)
    end

    table.sort(list, function(a, b)
        return a.priority < b.priority
    end)

    local newEntryButton = equipmentRingsWindow.priority.list:getChildByIndex(1)
    for _, entry in ipairs(list) do
        if entry['item'] == 0 or table.find(itemList, entry['item']) then
            local newWidget = g_ui.createWidget('MiniBotEquipmentRingEntry')
            newWidget:constructEnviorementVariables()

            newWidget.minHp:setText(equipmentRingsWindow.fromText .. ' -%')
            newWidget.minMp:setText(equipmentRingsWindow.fromText .. ' -%')
            newWidget.maxHp:setText(equipmentRingsWindow.toText .. ' -%')
            newWidget.maxMp:setText(equipmentRingsWindow.toText .. ' -%')

            equipmentRingsWindow.priority.list:insertChild(equipmentRingsWindow.priority.list:getChildIndex(newEntryButton), newWidget)
            equipmentRingsWindow.priority.list:ensureChildVisible(newWidget)

            local isPhantom = not equipment_ringsModule.isValidEquipmentEntry(entry)
            if isPhantom then
                newWidget.icon:setPhantom(true)
                newWidget.icon:setImageClip(torect('50 0 25 25'))
            else
                newWidget.icon:setChecked(entry['enabled'])
            end

            if entry['item'] > 0 then
                newWidget.item:show()
                newWidget.item:setItemId(entry['item'])
                newWidget.frameBackground:setTooltip(newWidget.item:getItem():getName())
            end

            if entry['min'] > 0 then
                newWidget.minHp:setText(equipmentRingsWindow.fromText .. ' ' .. entry['min'] .. '%')
            end

            if entry['max'] > 0 then
                newWidget.maxHp:setText(equipmentRingsWindow.toText .. ' ' .. entry['max'] .. '%')
            end

            if entry['manaMin'] > 0 then
                newWidget.minMp:setText(equipmentRingsWindow.fromText .. ' ' .. entry['manaMin'] .. '%')
            end

            if entry['manaMax'] > 0 then
                newWidget.maxMp:setText(equipmentRingsWindow.toText .. ' ' .. entry['manaMax'] .. '%')
            end

            if entry['unequip'] then
                newWidget.unequip:show()
            end

            newWidget.ignoreChecked = entry['ignore_enabled'] or false
            newWidget.ignoreList = entry['ignore'] or {}

            newWidget.onLeftClick = function()
                modules.game_minibot.callMethod('onClickEntry', newWidget)
            end

            newWidget.icon.onCheckChange = function()
                modules.game_minibot.callMethod('onIconCheckEntry', newWidget.icon:getParent())
            end

            newWidget.icon.onLeftClick = function()
                modules.game_minibot.callMethod('onClickEntry', newWidget.icon:getParent())
            end

            newWidget.unequip.onLeftClick = function()
                modules.game_minibot.callMethod('onClickEntry', newWidget.unequip:getParent())
            end

            newWidget.frameBackground.onLeftClick = function()
                modules.game_minibot.callMethod('onClickEntry', newWidget.frameBackground:getParent())
            end
        end
    end

    equipmentRingsWindow.priority.enabled.ignoreCallback = true
    equipmentRingsWindow.priority.enabled:setChecked(sSettings['equipmentRing_enabled'])
    equipmentRingsWindow.priority.enabled.ignoreCallback = nil

    equipmentRingsWindow.priority.enabled.onCheckChange = function()
        if equipmentRingsWindow.priority.enabled.ignoreCallback then
            return
        end

        local panel = modules.game_interface.getMiniBotPanel()
        if panel ~= nil then
            local child = panel:getChildById('equipmentRing_gamewindow')
            if child ~= nil then
                child.ignoreCallback = true
                child:setChecked(equipmentRingsWindow.priority.enabled:isChecked())
                child.ignoreCallback = nil
            end
        end

        local settings2 = modules.game_minibot.getPressetSettings()
        if settings2['shortcuts'] == nil then
            settings2['shortcuts'] = {}
        end

        settings2['shortcuts']['equipmentRing_enabled'] = equipmentRingsWindow.priority.enabled:isChecked()
        modules.game_minibot.setPressetSettings(settings2)
        g_minibot.setModuleToggle(11, equipmentRingsWindow.priority.enabled:isChecked()) -- Equipment Ring
    end

    reloadListBackgrounds()
end

function equipment_ringsModule.reloadLanguage(language)
    if language == 'ptbr' then
        equipmentRingsWindow.priority.priorityLabel:setText('Lista de prioridades')
        equipmentRingsWindow.priority.listHeader.sourceLabel.label:setText('Fonte')
        equipmentRingsWindow.priority.listHeader.healhLabel.label:setText('Vida')
        equipmentRingsWindow.priority.listHeader.actionLabel.label:setText('Acao')
        equipmentRingsWindow.config.title:setText('Configuracao')
        equipmentRingsWindow.config.notSelected:setText('Selecione uma entrada na lista para configurar ou criar uma nova entrada no botao +.')
        equipmentRingsWindow.config.panel.save:setText('Aplicar')
        equipmentRingsWindow.config.panel.name:setPlaceholder('Digite para pesquisar ou arraste')
        equipmentRingsWindow.config.panel.unequip:setText('Desequipar')
        equipmentRingsWindow.config.panel.unequip:setTextOffset('-20 -2')
        equipmentRingsWindow.config.panel.unequipMask:setMarginLeft(-20)
        equipmentRingsWindow.config.panel.maxMpHelp:setTooltip('Voce deve configurar seus requisitos de Mana para que o equipar/desequipar seja acionado:\n\n- \'Min\': Se seu Mana for MAIOR que este valor.\n- \'Max\': Se seu Mana for MENOR que este valor.')
        equipmentRingsWindow.config.panel.minHpLabel:setText('Vida:  ')
        equipmentRingsWindow.config.panel.maxHpHelp:setTooltip('Voce deve configurar seus requisitos de vida para que o equipar/desequipar seja acionado:\n\n- \'Min\': Se sua vida for MAIOR que este valor.\n- \'Max\': Se sua vida for MENOR que este valor.')
        equipmentRingsWindow.config.panel.ignore.check:setText('Ignorar se')
        equipmentRingsWindow.config.panel.ignore.help:setTooltip('Voce pode escolher uma lista de itens que, quando equipados, o Assistente ignorara esta entrada de equipar/desequipar.')

    elseif language == 'enus' then
        equipmentRingsWindow.priority.priorityLabel:setText('Priority List')
        equipmentRingsWindow.priority.listHeader.sourceLabel.label:setText('Source')
        equipmentRingsWindow.priority.listHeader.healhLabel.label:setText('Health')
        equipmentRingsWindow.priority.listHeader.actionLabel.label:setText('Action')
        equipmentRingsWindow.config.title:setText('Configure')
        equipmentRingsWindow.config.notSelected:setText('Select an entry on the list to configure or create a band-new entry on the + button.')
        equipmentRingsWindow.config.panel.save:setText('Apply')
        equipmentRingsWindow.config.panel.name:setPlaceholder('Type to search or drop on slot')
        equipmentRingsWindow.config.panel.unequip:setText('Unequip')
        equipmentRingsWindow.config.panel.unequip:setTextOffset('0 -2')
        equipmentRingsWindow.config.panel.unequipMask:setMarginLeft(0)
        equipmentRingsWindow.config.panel.maxMpHelp:setTooltip('You must configure your Mana requirements so the equip/unequip will trigger:\n\n- \'Min\': If your Mana is HIGHER than this value.\n- \'Max\': If your Mana is LOWER this value.')
        equipmentRingsWindow.config.panel.minHpLabel:setText('Health:')
        equipmentRingsWindow.config.panel.maxHpHelp:setTooltip('You must configure your Health requirements so the equip/unequip will trigger:\n\n- \'Min\': If your health is HIGHER than this value.\n- \'Max\': If your health is LOWER this value.')
        equipmentRingsWindow.config.panel.ignore.check:setText('Ignore when')
        equipmentRingsWindow.config.panel.ignore.help:setTooltip('')
        equipmentRingsWindow.config.panel.ignore.help:setTooltip('You can choose a list of items that, when equipped, the Assistant will ignore this entry equip/unequip.')
    end

    for _, c in ipairs(equipmentRingsWindow.priority.list:getChildren()) do
        if c.ignoreBackground then
            if language == 'ptbr' then
                c.text:setText('Nova Entrada')
            elseif language == 'enus' then
                c.text:setText('New Entry')
            end
        else
            if language == 'ptbr' then
                c.harmony:setTooltip('Seu requisito de Harmonia selecionado.')
                c.unequip:setTooltip('Este item esta configurado apenas para desequipar.')
                c.iconTooptip:setTooltip('Sua entrada e invalida, por favor reconfigure-a!')
            elseif language == 'enus' then
                c.harmony:setTooltip('Your selected Harmony requirement.')
                c.unequip:setTooltip('This item is set to unequip only.')
                c.iconTooptip:setTooltip('Your entry is invalid, please reconfigure it!')
            end
        end
    end
end

function equipment_ringsModule.reloadEnabledShortcut(_, widget)
    if widget:getId() ~= 'equipmentRing_gamewindow' then
        return
    end

    equipmentRingsWindow.priority.enabled.ignoreCallback = true
    equipmentRingsWindow.priority.enabled:setChecked(widget:isChecked())
    equipmentRingsWindow.priority.enabled.ignoreCallback = nil
end

function equipment_ringsModule.saveSettings()
    local settings = modules.game_minibot.getPressetSettings()

    local values = {}
    for i, c in ipairs(equipmentRingsWindow.priority.list:getChildren()) do
        if not(c.ignoreBackground) then
            local value = {}
            value['priority'] = i
            value['item'] = 0
            value['spell'] = 0
            value['reqmana'] = 0
            value['min'] = 0
            value['manaMax'] = 0
            value['manaMin'] = 0
            value['max'] = 0
            value['harmony'] = 0
            value['unequip'] = c.unequip:isVisible()
            -- The widget phantom flag is set once at row creation and never
            -- cleared, so gating on it kept saving enabled=false forever.
            value['enabled'] = c.icon:isChecked()
            value['ignore_enabled'] = c.ignoreChecked
            value['ignore'] = c.ignoreList or {}

            if c.minHp:getText() ~= equipmentRingsWindow.fromText .. ' -%' then
                local text = c.minHp:getText()
                local numberStr = text:match(equipmentRingsWindow.fromText .. "%s+(%d+)%%")
                value['min'] = tonumber(numberStr)
            end

            if c.maxHp:getText() ~= equipmentRingsWindow.toText .. ' -%' then
                local text = c.maxHp:getText()
                local numberStr = text:match(equipmentRingsWindow.toText .. "%s+(%d+)%%")
                value['max'] = tonumber(numberStr)
            end

            if c.minMp:getText() ~= equipmentRingsWindow.fromText .. ' -%' then
                local text = c.minMp:getText()
                local numberStr = text:match(equipmentRingsWindow.fromText .. "%s+(%d+)%%")
                value['manaMin'] = tonumber(numberStr)
            end

            if c.maxMp:getText() ~= equipmentRingsWindow.toText .. ' -%' then
                local text = c.maxMp:getText()
                local numberStr = text:match(equipmentRingsWindow.toText .. "%s+(%d+)%%")
                value['manaMax'] = tonumber(numberStr)
            end

            if c.item:isVisible() then
                value['item'] = c.item:getItemId()
            end

            table.insert(values, value)
        end
    end

    settings['equipment_rings'] = values
    modules.game_minibot.setPressetSettings(settings)
    equipment_ringsModule.reloadInternalModule()
end

function equipment_ringsModule.onIconCheckEntry(widget)
    if widget:isPhantom() then
        widget:setImageClip(torect('50 0 25 25'))
        return
    end

    if widget:isChecked() then
        widget:setImageClip(torect('0 0 25 25'))
    else
        widget:setImageClip(torect('25 0 25 25'))
    end

    equipment_ringsModule.saveSettings()
end

function equipment_ringsModule.validateTextHarmony(widget)
    local value = tonumber(widget:getText())
    if value == nil or value < 0 then
        widget:clearText()
        return
    end

    if value > 5 then
        widget:setText(5)
        return
    end
end

function equipment_ringsModule.onClickEntry(widget)
    for _, c in ipairs(widget:getParent():getChildren()) do
        if not(c.ignoreBackground) then
            c.mask:hide()
            c.buttons:hide()
        end
    end

    widget.mask:show()
    widget.buttons:show()

    local index = widget:getParent():getChildIndex(widget)
    if index == 1 then
        widget.buttons.upper:setEnabled(false)
    else
        widget.buttons.upper:setEnabled(true)
    end
    if index == (widget:getParent():getChildCount() - 1) then
        widget.buttons.lower:setEnabled(false)
    else
        widget.buttons.lower:setEnabled(true)
    end

    if equipmentRingsWindow.config.selectedEntry == widget then
        return
    end

    equipmentRingsWindow.config.selectedEntry = widget

    equipmentRingsWindow.config.notSelected:hide()
    equipmentRingsWindow.config.panel:show()

    equipmentRingsWindow.config.panel.name.onTextChange = nil

    equipmentRingsWindow.config.panel.unequip:setChecked(widget.unequip:isVisible())
    equipmentRingsWindow.config.panel.item:hide()

    if widget.item:isVisible() then
        equipmentRingsWindow.config.panel.item:show()
        equipmentRingsWindow.config.panel.item:setItemId(widget.item:getItemId())
        equipmentRingsWindow.config.panel.frameBackground:setTooltip(widget.item:getItem():getName())
    end

    equipmentRingsWindow.config.panel.ignore.check:setChecked(widget.ignoreChecked)
    equipmentRingsWindow.config.panel.ignore.list:destroyChildren()
    for _, ignore in pairs(widget.ignoreList) do
        local iType = g_things.getThingType(ignore, ThingCategoryItem)
        if iType ~= nil then
            local itemWidget = g_ui.createWidget('MiniBotEquipmentRingitemDropDownEntry', equipmentRingsWindow.config.panel.ignore.list)
            itemWidget:setItemId(iType:getId())
            itemWidget:setTooltip(iType:getName())

            itemWidget.onMousePress = equipment_ringsModule.onItemIgnoreDropDownEntryMousePress
        end
    end

    local newIgnoreItem = g_ui.createWidget('MiniBotEquipmentRingitemIgnoreDropDownEntry', equipmentRingsWindow.config.panel.ignore.list)
    newIgnoreItem.onLeftClick = function()
        equipment_ringsModule.openCatcher(true)
    end

    local max = ''
    if widget.maxHp:getText() ~= equipmentRingsWindow.toText .. ' -%' then
        local text = widget.maxHp:getText()
        local numberStr = text:match(equipmentRingsWindow.toText .. "%s+(%d+)%%")
        max = numberStr
    end
    equipmentRingsWindow.config.panel.maxHp:setText(max)

    max = ''
    if widget.maxMp:getText() ~= equipmentRingsWindow.toText .. ' -%' then
        local text = widget.maxMp:getText()
        local numberStr = text:match(equipmentRingsWindow.toText .. "%s+(%d+)%%")
        max = numberStr
    end
    equipmentRingsWindow.config.panel.maxMp:setText(max)

    local min = ''
    if widget.minHp:getText() ~= equipmentRingsWindow.fromText .. ' -%' then
        local text = widget.minHp:getText()
        local numberStr = text:match(equipmentRingsWindow.fromText .. "%s+(%d+)%%")
        min = numberStr
    end
    equipmentRingsWindow.config.panel.minHp:setText(min)

    min = ''
    if widget.minMp:getText() ~= equipmentRingsWindow.fromText .. ' -%' then
        local text = widget.minMp:getText()
        local numberStr = text:match(equipmentRingsWindow.fromText .. "%s+(%d+)%%")
        min = numberStr
    end
    equipmentRingsWindow.config.panel.minMp:setText(min)

    local function onNameTextChange()
        if equipmentRingsWindow.config.panel.name:getText() == '' then
            return
        end

        equipmentRingsWindow.config.panel.frameBackground:removeTooltip()

        equipmentRingsWindow.config.panel.name.onTextChange = nil
        equipmentRingsWindow.config.panel.name.ignoreClear = true
        local items = g_things.findMarketableItemTypesByString(equipmentRingsWindow.config.panel.name:getText())
        if items == nil or #items == 0 then
            equipmentRingsWindow.config.panel.item:setItemId(0)
            equipmentRingsWindow.config.panel.name.onTextChange = onNameTextChange
            equipmentRingsWindow.config.panel.name.ignoreClear = nil
            return
        end

        local found = nil
        for _, item in ipairs(items) do
            if table.find(itemList, item:getId()) then
                found = item
                break
            end
        end

        if found == nil then
            equipmentRingsWindow.config.panel.item:setItemId(0)
            equipmentRingsWindow.config.panel.name.onTextChange = onNameTextChange
            equipmentRingsWindow.config.panel.name.ignoreClear = nil
            return
        end

        equipmentRingsWindow.config.panel.item:show()

        equipmentRingsWindow.config.panel.item:setItemId(found:getId())

        equipmentRingsWindow.config.panel.frameBackground:setTooltip(equipmentRingsWindow.config.panel.item:getItem():getName())

        equipmentRingsWindow.config.panel.name.onTextChange = onNameTextChange
        equipmentRingsWindow.config.panel.name.ignoreClear = nil
    end

    equipmentRingsWindow.config.panel.frameBackground.onDrop = function(_, droppedWidget, mousePos)
        equipmentRingsWindow.config.panel.frameBackground:removeTooltip()

        if droppedWidget:getClassName() == "UIItem" then
            local item = droppedWidget:getItem()
            if item == nil or item:getMarketData() == nil or not(table.find(itemList, droppedWidget:getItemId())) then
                return
            end

            equipmentRingsWindow.config.panel.item:setItemId(droppedWidget:getItemId())

            equipmentRingsWindow.config.panel.frameBackground:setTooltip(equipmentRingsWindow.config.panel.item:getItem():getName())
        end
    end

    equipmentRingsWindow.config.panel.frameBackground.onLeftClick = function()
        modules.game_minibot.deferMethod('openCatcher', false)
    end

    equipmentRingsWindow.config.panel.name.onTextChange = onNameTextChange

    equipmentRingsWindow.config.panel.save.onLeftClick = function()
        local selectedWidget = nil
        for _, c in ipairs(equipmentRingsWindow.priority.list:getChildren()) do
            if c.mask:isVisible() then
                selectedWidget = c
                break
            end
        end

        if selectedWidget == nil then
            return
        end

        selectedWidget.harmony:hide()

        if equipmentRingsWindow.config.panel.item:getItem() == nil then
            return
        end

        selectedWidget.item:show()
        selectedWidget.unequip:hide()
        selectedWidget.unequip:setVisible(equipmentRingsWindow.config.panel.unequip:isChecked())

        selectedWidget.ignoreChecked = equipmentRingsWindow.config.panel.ignore.check:isChecked()
        selectedWidget.ignoreList = {}

        for _, c in ipairs(equipmentRingsWindow.config.panel.ignore.list:getChildren()) do
            if c.getItem ~= nil then
                table.insert(selectedWidget.ignoreList, c:getItem():getId())
            end
        end

        selectedWidget.item:setItemId(equipmentRingsWindow.config.panel.item:getItemId())
        selectedWidget.frameBackground:setTooltip(equipmentRingsWindow.config.panel.item:getItem():getName())

        local minHp = equipmentRingsWindow.config.panel.minHp:getText()
        local minHpValue = tonumber(minHp) or 0
        if minHp == '' then
            minHp = '-'
        end
        selectedWidget.minHp:setText(equipmentRingsWindow.fromText .. ' ' .. minHp .. '%')

        local maxHp = equipmentRingsWindow.config.panel.maxHp:getText()
        local maxHpValue = tonumber(maxHp) or 0
        if maxHp == '' then
            maxHp = '-'
        end
        selectedWidget.maxHp:setText(equipmentRingsWindow.toText .. ' ' .. maxHp .. '%')

        local minMp = equipmentRingsWindow.config.panel.minMp:getText()
        local minMpValue = tonumber(minMp) or 0
        if minMp == '' then
            minMp = '-'
        end
        selectedWidget.minMp:setText(equipmentRingsWindow.fromText .. ' ' .. minMp .. '%')

        local maxMp = equipmentRingsWindow.config.panel.maxMp:getText()
        local maxMpValue = tonumber(maxMp) or 0
        if maxMp == '' then
            maxMp = '-'
        end
        selectedWidget.maxMp:setText(equipmentRingsWindow.toText .. ' ' .. maxMp .. '%')

        local validEntry = equipment_ringsModule.isValidEquipmentEntry({
            item = selectedWidget.item:getItemId(),
            min = minHpValue,
            max = maxHpValue,
            manaMin = minMpValue,
            manaMax = maxMpValue
        })
        if validEntry and (selectedWidget.item:isVisible() and selectedWidget.item:getItem()) then
            if selectedWidget.icon:isPhantom() then
                selectedWidget.icon:setPhantom(false)
                selectedWidget.icon:setImageClip(torect('25 0 25 25'))
            end
        elseif not(selectedWidget.icon:isPhantom()) then
            selectedWidget.icon:setPhantom(true)
            selectedWidget.icon:setImageClip(torect('50 0 25 25'))
        end

        equipment_ringsModule.saveSettings()
    end
end

function equipment_ringsModule.onRemoveEntry(widget)
    if not widgetAlive(widget) then
        return
    end
    pcall(function()
        widget:destroy()
    end)

    reloadListBackgrounds()

    equipment_ringsModule.saveSettings()
end

function equipment_ringsModule.validateTextPercentage(widget)
    if widget:getText() == '' then
        if widget:getId() == 'maxHp' then
            equipmentRingsWindow.config.panel.minHp:clearText()
        elseif widget:getId() == 'maxMp' then
            equipmentRingsWindow.config.panel.minMp:clearText()
        end

        return
    end

    local value = tonumber(widget:getText())
    if value == nil or value == 0 then
        widget:clearText()
        return
    end

    if value > 100 then
        widget:setText(100)
        return
    end

    if widget:getId() == 'minHp' then
        if equipmentRingsWindow.config.panel.maxHp:getText() ~= '' then
            if value > (tonumber(equipmentRingsWindow.config.panel.maxHp:getText()) or 0) then
                widget:setText(equipmentRingsWindow.config.panel.maxHp:getText())
            end
        end
    elseif widget:getId() == 'maxHp' then
        local minValue = tonumber(equipmentRingsWindow.config.panel.minHp:getText()) or 0
        if minValue > value then
            equipmentRingsWindow.config.panel.minHp:setText(value)
        end
    elseif widget:getId() == 'minMp' then
        if equipmentRingsWindow.config.panel.maxMp:getText() ~= '' then
            if value > (tonumber(equipmentRingsWindow.config.panel.maxMp:getText()) or 0) then
                widget:setText(equipmentRingsWindow.config.panel.maxMp:getText())
            end
        end
    elseif widget:getId() == 'maxMp' then
        local minValue = tonumber(equipmentRingsWindow.config.panel.minMp:getText()) or 0
        if minValue > value then
            equipmentRingsWindow.config.panel.minMp:setText(value)
        end
    end
end

function equipment_ringsModule.onMoveUpEntry(widget)
    local index = widget:getParent():getChildIndex(widget)
    if index == 1 then
        return
    end

    widget:getParent():moveChildToIndex(widget, index - 1)
    reloadListBackgrounds()

    widget:onLeftClick()

    equipment_ringsModule.saveSettings()
end

function equipment_ringsModule.onMoveDownEntry(widget)
    local index = widget:getParent():getChildIndex(widget)
    if index == (widget:getParent():getChildCount() - 1) then
        return
    end

    widget:getParent():moveChildToIndex(widget, index + 1)
    reloadListBackgrounds()

    widget:onLeftClick()

    equipment_ringsModule.saveSettings()
end

function equipment_ringsModule.onNewEntry(widget)
    if widget.isClickFromUiScrollAreaArrow then
        return
    end

    local lastIndex = widget:getParent():getChildIndex(widget)
    local newWidget = g_ui.createWidget('MiniBotEquipmentRingEntry')
    newWidget:constructEnviorementVariables()

    newWidget.minHp:setText(equipmentRingsWindow.fromText .. ' -%')
    newWidget.minMp:setText(equipmentRingsWindow.fromText .. ' -%')
    newWidget.maxHp:setText(equipmentRingsWindow.toText .. ' -%')
    newWidget.maxMp:setText(equipmentRingsWindow.toText .. ' -%')

    newWidget.ignoreList = {}

    newWidget.onLeftClick = function()
        modules.game_minibot.callMethod('onClickEntry', newWidget)
    end

    newWidget.icon.onCheckChange = function()
        modules.game_minibot.callMethod('onIconCheckEntry', newWidget.icon:getParent())
    end

    newWidget.icon.onLeftClick = function()
        modules.game_minibot.callMethod('onClickEntry', newWidget.icon:getParent())
    end

    newWidget.unequip.onLeftClick = function()
        modules.game_minibot.callMethod('onClickEntry', newWidget.unequip:getParent())
    end

    newWidget.frameBackground.onLeftClick = function()
        modules.game_minibot.callMethod('onClickEntry', newWidget.frameBackground:getParent())
    end

    newWidget.icon:setImageClip(torect('50 0 25 25'))
    newWidget.icon:setPhantom(true)

    widget:getParent():insertChild(lastIndex, newWidget)
    widget:getParent():ensureChildVisible(newWidget)

    newWidget:onLeftClick()

    reloadListBackgrounds()

    equipment_ringsModule.saveSettings()
end

function equipment_ringsModule.onIgnoreCheckWhenChange(widget)
    if equipmentRingsWindow == nil then
        return
    end

    if not(widget:isChecked()) then
        equipmentRingsWindow.config.panel.ignore.list:setOpacity(0.5)
        equipmentRingsWindow.config.panel.ignore.list:setPhantom(true)
        equipmentRingsWindow.config.panel.ignore.listScrollBar:setOpacity(0.5)
        equipmentRingsWindow.config.panel.ignore.listScrollBar:setPhantom(true)
        equipmentRingsWindow.config.panel.ignore.block:setPhantom(false)
        equipmentRingsWindow.config.panel.ignore.block:show()

    else
        equipmentRingsWindow.config.panel.ignore.list:setOpacity(1)
        equipmentRingsWindow.config.panel.ignore.list:setPhantom(false)
        equipmentRingsWindow.config.panel.ignore.listScrollBar:setOpacity(1)
        equipmentRingsWindow.config.panel.ignore.listScrollBar:setPhantom(false)
        equipmentRingsWindow.config.panel.ignore.block:setPhantom(true)
        equipmentRingsWindow.config.panel.ignore.block:hide()

    end
end

function equipment_ringsModule.onItemIgnoreDropDownEntryMousePress(widget, mousePos, mouseButton)
  if mouseButton ~= MouseRightButton then
      return
  end

  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)

  menu:addOption("Remove", function()
    if widgetAlive(widget) then
      pcall(function()
        widget:destroy()
      end)
    end
  end)

  menu:display(mousePos)
  return true
end
