equipment_amuletsModule = {}

local equipmentAmuletsWindow = nil
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
            page == equipmentAmuletsWindow and
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
                g_logger.error('[game_minibot] amulet catcher entry failed: ' .. tostring(err))
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

function equipment_amuletsModule.isValidEquipmentEntry(entry)
    if type(entry) ~= 'table' or (tonumber(entry['item']) or 0) <= 0 then
        return false
    end
    return (tonumber(entry['min']) or 0) > 0 or
        (tonumber(entry['max']) or 0) > 0 or
        (tonumber(entry['manaMin']) or 0) > 0 or
        (tonumber(entry['manaMax']) or 0) > 0
end

function equipment_amuletsModule.bindIgnoreEntryRemoval(widget)
    if widget == nil then
        return false
    end
    widget.onMousePress = equipment_amuletsModule.onItemIgnoreDropDownEntryMousePress
    return true
end

local itemList = {
    35609, -- Amethyst Necklace
    3057, -- Amulet of Loss
    30401, -- Amulet of Theurgy
    9301, -- Bornfire Amulet
    3056, -- Bronze Amulet
    45641, -- Candy Necklace
    23542, -- Collar of Blue Plasma
    23543, -- Collar of Green Plasma
    50152, -- Collar of Orange Plasma
    23544, -- Collar of Red Plasma
    3085, -- Dragon Necklace
    3082, -- Elven Amulet
    50154, -- Enchanted Merudri Brooch,
    30344, -- Enchanted Pendulet
    30342, -- Enchanted Sleep Shawl
    39233, -- Enchanted Turtle Amulet
    35523, -- Exotic Amulet
    27565, -- Foxtail Amulet
    3083, -- Garlic Necklace
    21170, -- Gearwheel Chain
    16108, -- Gill Necklace
    815, -- Glacier Amulet
    21183, -- Glooth Amulet
    50195, -- Harmony Amulet
    7532, -- Koshei's Ancient Amulet
    9303, -- Leviathan's Amulet
    816, -- Lightning Pendant
    34158, -- Lion Amulet
    817, -- Magma AMulet
    50156, -- Merudri Brooch
    13990, -- Necklace of the Deep
    22195, -- Onyx Pendant
    3055, -- Platinum Amulet
    16113, -- Prismatic Necklace
    3084, -- Protection Amulet
    30323, -- Rainbow Necklace
    9302, -- Sacred Tree Amulet,
    9304, -- Shockwave Amulet
    3054, -- Silver Amulet
    --3081, -- Stone Skin Amulet
    3045, -- Strange Talisman
    814, -- Terra Amulet
    31631, -- The Cobra Amulet
    41131, -- Elemental Death Amulet
    41141, -- Elemental Ice Amulet
    41139, -- Elemental Holy Amulet
    41137, -- Elemental Fire Amulet
    41135, -- Elemental Energy Amulet
    41133, -- Elemental Earth Amulet
}

local ignoreAppendItemsList = {
    3081, -- Stone Skin Amulet
}

local similaritems = {
    [30401] = { 30401, 30402, 30403 },
    [23542] = { 23542, 23526 },
    [23543] = { 23543, 23527 },
    [50152] = { 50152, 50153 },
    [23544] = { 23544, 23528 },
    [30344] = { 30344, 30345 },
    [30342] = { 30342, 30343 },
    [39233] = { 39233, 39234 },
    [41131] = { 41131, 41114 },
    [41141] = { 41141, 41124 },
    [41139] = { 41139, 41122 },
    [41137] = { 41137, 41120 },
    [41135] = { 41135, 41118 },
    [41133] = { 41133, 41116 },
}

function equipment_amuletsModule.init(widget)
    cancelCatcherBuild()
    equipmentAmuletsWindow = widget

    equipmentAmuletsWindow.fromText = 'From'
    equipmentAmuletsWindow.toText = 'To'
    local language = modules.game_minibot.getSettingsValue(false, 'language', 'ptbr')
    if language == 'ptbr' then
        equipmentAmuletsWindow.fromText = 'De'
        equipmentAmuletsWindow.toText = 'Ate'
    elseif language == 'enus' then
        equipmentAmuletsWindow.fromText = 'From'
        equipmentAmuletsWindow.toText = 'To'
    end

    equipment_amuletsModule.loadSettings()
end

function equipment_amuletsModule.terminate()
    local page = equipmentAmuletsWindow
    equipment_amuletsModule.closeCatcher()

    if equipmentAmuletsWindow == page then
        equipmentAmuletsWindow = nil
    end
end

function equipment_amuletsModule.reloadLanguage(language)
    if language == 'ptbr' then
        equipmentAmuletsWindow.priority.priorityLabel:setText('Lista de prioridades')
        equipmentAmuletsWindow.priority.listHeader.sourceLabel.label:setText('Fonte')
        equipmentAmuletsWindow.priority.listHeader.healhLabel.label:setText('Vida')
        equipmentAmuletsWindow.priority.listHeader.actionLabel.label:setText('Acao')
        equipmentAmuletsWindow.config.title:setText('Configuracao')
        equipmentAmuletsWindow.config.notSelected:setText('Selecione uma entrada na lista para configurar ou criar uma nova entrada no botao +.')
        equipmentAmuletsWindow.config.panel.save:setText('Aplicar')
        equipmentAmuletsWindow.config.panel.name:setPlaceholder('Digite para pesquisar ou arraste')
        equipmentAmuletsWindow.config.panel.unequip:setText('Desequipar')
        equipmentAmuletsWindow.config.panel.unequip:setTextOffset('-20 -2')
        equipmentAmuletsWindow.config.panel.unequipMask:setMarginLeft(-20)
        equipmentAmuletsWindow.config.panel.maxMpHelp:setTooltip('Voce deve configurar seus requisitos de Mana para que o equipar/desequipar seja acionado:\n\n- \'Min\': Se seu Mana for MAIOR que este valor.\n- \'Max\': Se seu Mana for MENOR que este valor.')
        equipmentAmuletsWindow.config.panel.minHpLabel:setText('Vida:  ')
        equipmentAmuletsWindow.config.panel.maxHpHelp:setTooltip('Voce deve configurar seus requisitos de vida para que o equipar/desequipar seja acionado:\n\n- \'Min\': Se sua vida for MAIOR que este valor.\n- \'Max\': Se sua vida for MENOR que este valor.')
        equipmentAmuletsWindow.config.panel.ignore.check:setText('Ignorar se')
        equipmentAmuletsWindow.config.panel.ignore.help:setTooltip('Voce pode escolher uma lista de itens que, quando equipados, o Assistente ignorara esta entrada de equipar/desequipar.')

    elseif language == 'enus' then
        equipmentAmuletsWindow.priority.priorityLabel:setText('Priority List')
        equipmentAmuletsWindow.priority.listHeader.sourceLabel.label:setText('Source')
        equipmentAmuletsWindow.priority.listHeader.healhLabel.label:setText('Health')
        equipmentAmuletsWindow.priority.listHeader.actionLabel.label:setText('Action')
        equipmentAmuletsWindow.config.title:setText('Configure')
        equipmentAmuletsWindow.config.notSelected:setText('Select an entry on the list to configure or create a band-new entry on the + button.')
        equipmentAmuletsWindow.config.panel.save:setText('Apply')
        equipmentAmuletsWindow.config.panel.name:setPlaceholder('Type to search or drop on slot')
        equipmentAmuletsWindow.config.panel.unequip:setText('Unequip')
        equipmentAmuletsWindow.config.panel.unequip:setTextOffset('0 -2')
        equipmentAmuletsWindow.config.panel.unequipMask:setMarginLeft(0)
        equipmentAmuletsWindow.config.panel.maxMpHelp:setTooltip('You must configure your Mana requirements so the equip/unequip will trigger:\n\n- \'Min\': If your Mana is HIGHER than this value.\n- \'Max\': If your Mana is LOWER this value.')
        equipmentAmuletsWindow.config.panel.minHpLabel:setText('Health:')
        equipmentAmuletsWindow.config.panel.maxHpHelp:setTooltip('You must configure your Health requirements so the equip/unequip will trigger:\n\n- \'Min\': If your health is HIGHER than this value.\n- \'Max\': If your health is LOWER this value.')
        equipmentAmuletsWindow.config.panel.ignore.check:setText('Ignore when')
        equipmentAmuletsWindow.config.panel.ignore.help:setTooltip('')
        equipmentAmuletsWindow.config.panel.ignore.help:setTooltip('You can choose a list of items that, when equipped, the Assistant will ignore this entry equip/unequip.')
    end

    for _, c in ipairs(equipmentAmuletsWindow.priority.list:getChildren()) do
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

function equipment_amuletsModule.reloadInternalModule()
    local settings = modules.game_minibot.getPressetSettings()

    local list = {}
    local sList = settings['equipment_amulets'] or {}
    for _, entry in pairs(sList) do
        table.insert(list, entry)
    end

    table.sort(list, function(a, b)
        return a.priority < b.priority
    end)

    g_minibot.resetModule(10) -- Amulets Module type
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

        g_minibot.addModule(10, internal)
    end
end

local function reloadListBackgrounds()
    local isSelected = false

    for _, c in ipairs(equipmentAmuletsWindow.priority.list:getChildren()) do
        if not(c.ignoreBackground) then
            c:setBackgroundColor('alpha')

            if c.mask:isVisible() then
                isSelected = true
            end
        end
    end

    if not(isSelected) then
        equipmentAmuletsWindow.config.notSelected:show()
        equipmentAmuletsWindow.config.panel:hide()
    else
        equipmentAmuletsWindow.config.notSelected:hide()
        equipmentAmuletsWindow.config.panel:show()
    end
end

function equipment_amuletsModule.closeCatcher()
    cancelCatcherBuild()
    local windowCatcher = modules.game_minibot.getDropDownCatcher()
    if widgetAlive(windowCatcher) then
        pcall(function()
            windowCatcher:hide()
            windowCatcher.onLeftClick = nil
        end)
    end

    local page = equipmentAmuletsWindow
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

function equipment_amuletsModule.openCatcher(isIgnore)
    local page = equipmentAmuletsWindow
    if not widgetAlive(page) then
        return
    end

    page.dropDownCatcher:show()
    page.dropDownCatcher.onLeftClick = equipment_amuletsModule.closeCatcher

    local windowCatcher = modules.game_minibot.getDropDownCatcher()
    if widgetAlive(windowCatcher) then
        windowCatcher:show()
        windowCatcher.onLeftClick = equipment_amuletsModule.closeCatcher
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
            local itemWidget = g_ui.createWidget('MiniBotEquipmentAmuletitemDropDownEntry', page.dropDownMenu)
            itemWidget:setItemId(itemType:getId())
            itemWidget:setTooltip(itemType:getName())

            itemWidget.onLeftClick = function()
                if page ~= equipmentAmuletsWindow or not widgetAlive(page) then
                    return
                end
                if isIgnore then
                    local ignoreWidget = g_ui.createWidget('MiniBotEquipmentAmuletitemDropDownEntry', page.config.panel.ignore.list)
                    ignoreWidget:setItemId(itemType:getId())
                    ignoreWidget:setTooltip(itemType:getName())

                    equipment_amuletsModule.bindIgnoreEntryRemoval(ignoreWidget)

                    local ignoreButton = page.config.panel.ignore.list:getChildById('ignoreAdd')
                    if ignoreButton ~= nil then
                        page.config.panel.ignore.list:moveChildToIndex(ignoreButton, page.config.panel.ignore.list:getChildCount())
                    end
                else
                    page.config.panel.item:show()
                    page.config.panel.item:setItemId(itemType:getId())
                    page.config.panel.frameBackground:setTooltip(page.config.panel.item:getItem():getName())
                end

                equipment_amuletsModule.closeCatcher()
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

function equipment_amuletsModule.loadSettings()
    local settings = modules.game_minibot.getPressetSettings()

    local list = {}
    local sList = settings['equipment_amulets'] or {}
    local sSettings = settings['shortcuts'] or {}
    for _, entry in pairs(sList) do
        table.insert(list, entry)
    end

    table.sort(list, function(a, b)
        return a.priority < b.priority
    end)

    local newEntryButton = equipmentAmuletsWindow.priority.list:getChildByIndex(1)
    for _, entry in ipairs(list) do
        if entry['item'] == 0 or table.find(itemList, entry['item']) then
            local newWidget = g_ui.createWidget('MiniBotEquipmentAmuletEntry')
            newWidget:constructEnviorementVariables()

            newWidget.minHp:setText(equipmentAmuletsWindow.fromText .. ' -%')
            newWidget.minMp:setText(equipmentAmuletsWindow.fromText .. ' -%')
            newWidget.maxHp:setText(equipmentAmuletsWindow.toText .. ' -%')
            newWidget.maxMp:setText(equipmentAmuletsWindow.toText .. ' -%')

            equipmentAmuletsWindow.priority.list:insertChild(equipmentAmuletsWindow.priority.list:getChildIndex(newEntryButton), newWidget)
            equipmentAmuletsWindow.priority.list:ensureChildVisible(newWidget)

            local isPhantom = not equipment_amuletsModule.isValidEquipmentEntry(entry)
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
                newWidget.minHp:setText(equipmentAmuletsWindow.fromText .. ' ' .. entry['min'] .. '%')
            end

            if entry['max'] > 0 then
                newWidget.maxHp:setText(equipmentAmuletsWindow.toText .. ' ' .. entry['max'] .. '%')
            end

            if entry['manaMin'] > 0 then
                newWidget.minMp:setText(equipmentAmuletsWindow.fromText .. ' ' .. entry['manaMin'] .. '%')
            end

            if entry['manaMax'] > 0 then
                newWidget.maxMp:setText(equipmentAmuletsWindow.toText .. ' ' .. entry['manaMax'] .. '%')
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

    equipmentAmuletsWindow.priority.enabled.ignoreCallback = true
    equipmentAmuletsWindow.priority.enabled:setChecked(sSettings['equipmentAmulet_enabled'])
    equipmentAmuletsWindow.priority.enabled.ignoreCallback = nil

    equipmentAmuletsWindow.priority.enabled.onCheckChange = function()
        if equipmentAmuletsWindow.priority.enabled.ignoreCallback then
            return
        end

        local panel = modules.game_interface.getMiniBotPanel()
        if panel ~= nil then
            local child = panel:getChildById('equipmentAmulet_gamewindow')
            if child ~= nil then
                child.ignoreCallback = true
                child:setChecked(equipmentAmuletsWindow.priority.enabled:isChecked())
                child.ignoreCallback = nil
            end
        end

        local settings2 = modules.game_minibot.getPressetSettings()
        if settings2['shortcuts'] == nil then
            settings2['shortcuts'] = {}
        end

        settings2['shortcuts']['equipmentAmulet_enabled'] = equipmentAmuletsWindow.priority.enabled:isChecked()
        modules.game_minibot.setPressetSettings(settings2)
        g_minibot.setModuleToggle(10, equipmentAmuletsWindow.priority.enabled:isChecked()) -- Equipment Amulet
    end

    reloadListBackgrounds()
end

function equipment_amuletsModule.reloadEnabledShortcut(_, widget)
    if widget:getId() ~= 'equipmentAmulet_gamewindow' then
        return
    end

    equipmentAmuletsWindow.priority.enabled.ignoreCallback = true
    equipmentAmuletsWindow.priority.enabled:setChecked(widget:isChecked())
    equipmentAmuletsWindow.priority.enabled.ignoreCallback = nil
end

function equipment_amuletsModule.saveSettings()
    local settings = modules.game_minibot.getPressetSettings()

    local values = {}
    for i, c in ipairs(equipmentAmuletsWindow.priority.list:getChildren()) do
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
            value['enabled'] = not(c.icon:isPhantom()) and c.icon:isChecked()
            value['ignore_enabled'] = c.ignoreChecked
            value['ignore'] = c.ignoreList or {}

            if c.minHp:getText() ~= equipmentAmuletsWindow.fromText .. ' -%' then
                local text = c.minHp:getText()
                local numberStr = text:match(equipmentAmuletsWindow.fromText .. "%s+(%d+)%%")
                value['min'] = tonumber(numberStr)
            end

            if c.maxHp:getText() ~= equipmentAmuletsWindow.toText .. ' -%' then
                local text = c.maxHp:getText()
                local numberStr = text:match(equipmentAmuletsWindow.toText .. "%s+(%d+)%%")
                value['max'] = tonumber(numberStr)
            end

            if c.minMp:getText() ~= equipmentAmuletsWindow.fromText .. ' -%' then
                local text = c.minMp:getText()
                local numberStr = text:match(equipmentAmuletsWindow.fromText .. "%s+(%d+)%%")
                value['manaMin'] = tonumber(numberStr)
            end

            if c.maxMp:getText() ~= equipmentAmuletsWindow.toText .. ' -%' then
                local text = c.maxMp:getText()
                local numberStr = text:match(equipmentAmuletsWindow.toText .. "%s+(%d+)%%")
                value['manaMax'] = tonumber(numberStr)
            end

            if c.item:isVisible() then
                value['item'] = c.item:getItemId()
            end

            table.insert(values, value)
        end
    end

    settings['equipment_amulets'] = values
    modules.game_minibot.setPressetSettings(settings)
    equipment_amuletsModule.reloadInternalModule()
end

function equipment_amuletsModule.onIconCheckEntry(widget)
    if widget:isPhantom() then
        widget:setImageClip(torect('50 0 25 25'))
        return
    end

    if widget:isChecked() then
        widget:setImageClip(torect('0 0 25 25'))
    else
        widget:setImageClip(torect('25 0 25 25'))
    end

    equipment_amuletsModule.saveSettings()
end

function equipment_amuletsModule.validateTextHarmony(widget)
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

function equipment_amuletsModule.onClickEntry(widget)
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

    if equipmentAmuletsWindow.config.selectedEntry == widget then
        return
    end

    equipmentAmuletsWindow.config.selectedEntry = widget

    equipmentAmuletsWindow.config.notSelected:hide()
    equipmentAmuletsWindow.config.panel:show()

    equipmentAmuletsWindow.config.panel.name.onTextChange = nil

    equipmentAmuletsWindow.config.panel.unequip:setChecked(widget.unequip:isVisible())
    equipmentAmuletsWindow.config.panel.item:hide()

    if widget.item:isVisible() then
        equipmentAmuletsWindow.config.panel.item:show()
        equipmentAmuletsWindow.config.panel.item:setItemId(widget.item:getItemId())
        equipmentAmuletsWindow.config.panel.frameBackground:setTooltip(widget.item:getItem():getName())
    end

    equipmentAmuletsWindow.config.panel.ignore.check:setChecked(widget.ignoreChecked)
    equipmentAmuletsWindow.config.panel.ignore.list:destroyChildren()
    for _, ignore in pairs(widget.ignoreList) do
        local iType = g_things.getThingType(ignore, ThingCategoryItem)
        if iType ~= nil then
            local itemWidget = g_ui.createWidget('MiniBotEquipmentAmuletitemDropDownEntry', equipmentAmuletsWindow.config.panel.ignore.list)
            itemWidget:setItemId(iType:getId())
            itemWidget:setTooltip(iType:getName())

            itemWidget.onMousePress = equipment_amuletsModule.onItemIgnoreDropDownEntryMousePress
        end
    end

    local newIgnoreItem = g_ui.createWidget('MiniBotEquipmentAmuletitemIgnoreDropDownEntry', equipmentAmuletsWindow.config.panel.ignore.list)
    newIgnoreItem.onLeftClick = function()
        equipment_amuletsModule.openCatcher(true)
    end

    local max = ''
    if widget.maxHp:getText() ~= (equipmentAmuletsWindow.toText .. ' -%') then
        local text = widget.maxHp:getText()
        local numberStr = text:match(equipmentAmuletsWindow.toText .. "%s+(%d+)%%")
        max = numberStr
    end
    equipmentAmuletsWindow.config.panel.maxHp:setText(max)

    max = ''
    if widget.maxMp:getText() ~= (equipmentAmuletsWindow.toText .. ' -%') then
        local text = widget.maxMp:getText()
        local numberStr = text:match(equipmentAmuletsWindow.toText .. "%s+(%d+)%%")
        max = numberStr
    end
    equipmentAmuletsWindow.config.panel.maxMp:setText(max)

    local min = ''
    if widget.minHp:getText() ~= (equipmentAmuletsWindow.fromText .. ' -%') then
        local text = widget.minHp:getText()
        local numberStr = text:match(equipmentAmuletsWindow.fromText .. "%s+(%d+)%%")
        min = numberStr
    end
    equipmentAmuletsWindow.config.panel.minHp:setText(min)

    min = ''
    if widget.minMp:getText() ~= (equipmentAmuletsWindow.fromText .. ' -%') then
        local text = widget.minMp:getText()
        local numberStr = text:match(equipmentAmuletsWindow.fromText .. "%s+(%d+)%%")
        min = numberStr
    end
    equipmentAmuletsWindow.config.panel.minMp:setText(min)

    local function onNameTextChange()
        if equipmentAmuletsWindow.config.panel.name:getText() == '' then
            return
        end

        equipmentAmuletsWindow.config.panel.frameBackground:removeTooltip()

        equipmentAmuletsWindow.config.panel.name.onTextChange = nil
        equipmentAmuletsWindow.config.panel.name.ignoreClear = true
        local items = g_things.findMarketableItemTypesByString(equipmentAmuletsWindow.config.panel.name:getText())
        if items == nil or #items == 0 then
            equipmentAmuletsWindow.config.panel.item:setItemId(0)
            equipmentAmuletsWindow.config.panel.name.onTextChange = onNameTextChange
            equipmentAmuletsWindow.config.panel.name.ignoreClear = nil
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
            equipmentAmuletsWindow.config.panel.item:setItemId(0)
            equipmentAmuletsWindow.config.panel.name.onTextChange = onNameTextChange
            equipmentAmuletsWindow.config.panel.name.ignoreClear = nil
            return
        end

        equipmentAmuletsWindow.config.panel.item:show()

        equipmentAmuletsWindow.config.panel.item:setItemId(found:getId())

        equipmentAmuletsWindow.config.panel.frameBackground:setTooltip(equipmentAmuletsWindow.config.panel.item:getItem():getName())

        equipmentAmuletsWindow.config.panel.name.onTextChange = onNameTextChange
        equipmentAmuletsWindow.config.panel.name.ignoreClear = nil
    end

    equipmentAmuletsWindow.config.panel.frameBackground.onDrop = function(_, droppedWidget, mousePos)
        equipmentAmuletsWindow.config.panel.frameBackground:removeTooltip()

        if droppedWidget:getClassName() == "UIItem" then
            local item = droppedWidget:getItem()
            if item == nil or item:getMarketData() == nil or not(table.find(itemList, droppedWidget:getItemId())) then
                return
            end

            equipmentAmuletsWindow.config.panel.item:setItemId(droppedWidget:getItemId())

            equipmentAmuletsWindow.config.panel.frameBackground:setTooltip(equipmentAmuletsWindow.config.panel.item:getItem():getName())
        end
    end

    equipmentAmuletsWindow.config.panel.frameBackground.onLeftClick = function()
        modules.game_minibot.deferMethod('openCatcher', false)
    end

    equipmentAmuletsWindow.config.panel.name.onTextChange = onNameTextChange

    equipmentAmuletsWindow.config.panel.save.onLeftClick = function()
        local selectedWidget = nil
        for _, c in ipairs(equipmentAmuletsWindow.priority.list:getChildren()) do
            if c.mask:isVisible() then
                selectedWidget = c
                break
            end
        end

        if selectedWidget == nil then
            return
        end

        selectedWidget.harmony:hide()

        if equipmentAmuletsWindow.config.panel.item:getItem() == nil then
            return
        end

        selectedWidget.item:show()
        selectedWidget.unequip:hide()
        selectedWidget.unequip:setVisible(equipmentAmuletsWindow.config.panel.unequip:isChecked())

        selectedWidget.ignoreChecked = equipmentAmuletsWindow.config.panel.ignore.check:isChecked()
        selectedWidget.ignoreList = {}

        for _, c in ipairs(equipmentAmuletsWindow.config.panel.ignore.list:getChildren()) do
            if c.getItem ~= nil then
                table.insert(selectedWidget.ignoreList, c:getItem():getId())
            end
        end

        selectedWidget.item:setItemId(equipmentAmuletsWindow.config.panel.item:getItemId())
        selectedWidget.frameBackground:setTooltip(equipmentAmuletsWindow.config.panel.item:getItem():getName())

        local minHp = equipmentAmuletsWindow.config.panel.minHp:getText()
        local minHpValue = tonumber(minHp) or 0
        if minHp == '' then
            minHp = '-'
        end
        selectedWidget.minHp:setText(equipmentAmuletsWindow.fromText .. ' ' .. minHp .. '%')

        local maxHp = equipmentAmuletsWindow.config.panel.maxHp:getText()
        local maxHpValue = tonumber(maxHp) or 0
        if maxHp == '' then
            maxHp = '-'
        end
        selectedWidget.maxHp:setText(equipmentAmuletsWindow.toText .. ' ' .. maxHp .. '%')

        local minMp = equipmentAmuletsWindow.config.panel.minMp:getText()
        local minMpValue = tonumber(minMp) or 0
        if minMp == '' then
            minMp = '-'
        end
        selectedWidget.minMp:setText(equipmentAmuletsWindow.fromText .. ' ' .. minMp .. '%')

        local maxMp = equipmentAmuletsWindow.config.panel.maxMp:getText()
        local maxMpValue = tonumber(maxMp) or 0
        if maxMp == '' then
            maxMp = '-'
        end
        selectedWidget.maxMp:setText(equipmentAmuletsWindow.toText .. ' ' .. maxMp .. '%')

        local validEntry = equipment_amuletsModule.isValidEquipmentEntry({
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

        equipment_amuletsModule.saveSettings()
    end
end

function equipment_amuletsModule.onRemoveEntry(widget)
    if not widgetAlive(widget) then
        return
    end
    pcall(function()
        widget:destroy()
    end)

    reloadListBackgrounds()

    equipment_amuletsModule.saveSettings()
end

function equipment_amuletsModule.validateTextPercentage(widget)
    if widget:getText() == '' then
        if widget:getId() == 'maxHp' then
            equipmentAmuletsWindow.config.panel.minHp:clearText()
        elseif widget:getId() == 'maxMp' then
            equipmentAmuletsWindow.config.panel.minMp:clearText()
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
        if equipmentAmuletsWindow.config.panel.maxHp:getText() ~= '' then
            if value > (tonumber(equipmentAmuletsWindow.config.panel.maxHp:getText()) or 0) then
                widget:setText(equipmentAmuletsWindow.config.panel.maxHp:getText())
            end
        end
    elseif widget:getId() == 'maxHp' then
        local minValue = tonumber(equipmentAmuletsWindow.config.panel.minHp:getText()) or 0
        if minValue > value then
            equipmentAmuletsWindow.config.panel.minHp:setText(value)
        end
    elseif widget:getId() == 'minMp' then
        if equipmentAmuletsWindow.config.panel.maxMp:getText() ~= '' then
            if value > (tonumber(equipmentAmuletsWindow.config.panel.maxMp:getText()) or 0) then
                widget:setText(equipmentAmuletsWindow.config.panel.maxMp:getText())
            end
        end
    elseif widget:getId() == 'maxMp' then
        local minValue = tonumber(equipmentAmuletsWindow.config.panel.minMp:getText()) or 0
        if minValue > value then
            equipmentAmuletsWindow.config.panel.minMp:setText(value)
        end
    end
end

function equipment_amuletsModule.onMoveUpEntry(widget)
    local index = widget:getParent():getChildIndex(widget)
    if index == 1 then
        return
    end

    widget:getParent():moveChildToIndex(widget, index - 1)
    reloadListBackgrounds()

    widget:onLeftClick()

    equipment_amuletsModule.saveSettings()
end

function equipment_amuletsModule.onMoveDownEntry(widget)
    local index = widget:getParent():getChildIndex(widget)
    if index == (widget:getParent():getChildCount() - 1) then
        return
    end

    widget:getParent():moveChildToIndex(widget, index + 1)
    reloadListBackgrounds()

    widget:onLeftClick()

    equipment_amuletsModule.saveSettings()
end

function equipment_amuletsModule.onNewEntry(widget)
    if widget.isClickFromUiScrollAreaArrow then
        return
    end

    local lastIndex = widget:getParent():getChildIndex(widget)
    local newWidget = g_ui.createWidget('MiniBotEquipmentAmuletEntry')
    newWidget:constructEnviorementVariables()

    newWidget.minHp:setText(equipmentAmuletsWindow.fromText .. ' -%')
    newWidget.minMp:setText(equipmentAmuletsWindow.fromText .. ' -%')
    newWidget.maxHp:setText(equipmentAmuletsWindow.toText .. ' -%')
    newWidget.maxMp:setText(equipmentAmuletsWindow.toText .. ' -%')

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

    equipment_amuletsModule.saveSettings()
end

function equipment_amuletsModule.onIgnoreCheckWhenChange(widget)
    if equipmentAmuletsWindow == nil then
        return
    end

    if not(widget:isChecked()) then
        equipmentAmuletsWindow.config.panel.ignore.list:setOpacity(0.5)
        equipmentAmuletsWindow.config.panel.ignore.list:setPhantom(true)
        equipmentAmuletsWindow.config.panel.ignore.listScrollBar:setOpacity(0.5)
        equipmentAmuletsWindow.config.panel.ignore.listScrollBar:setPhantom(true)
        equipmentAmuletsWindow.config.panel.ignore.block:setPhantom(false)
        equipmentAmuletsWindow.config.panel.ignore.block:show()

    else
        equipmentAmuletsWindow.config.panel.ignore.list:setOpacity(1)
        equipmentAmuletsWindow.config.panel.ignore.list:setPhantom(false)
        equipmentAmuletsWindow.config.panel.ignore.listScrollBar:setOpacity(1)
        equipmentAmuletsWindow.config.panel.ignore.listScrollBar:setPhantom(false)
        equipmentAmuletsWindow.config.panel.ignore.block:setPhantom(true)
        equipmentAmuletsWindow.config.panel.ignore.block:hide()

    end
end

function equipment_amuletsModule.onItemIgnoreDropDownEntryMousePress(widget, mousePos, mouseButton)
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
