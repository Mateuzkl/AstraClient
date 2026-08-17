healing_manaModule = {}

local healingManaWindow = nil

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

local itemList = {
    238, -- Great Mana Potion
    268, -- Mana Potion
    237, -- Great Mana Potion
    23373, -- Ultimate Mana Potion
    7642, -- Great Spirit Potion
    23374, -- Ultimate Spirit Potion
    41096, -- Legendary Spirit Potion
    26074, -- Blessed Acorn
    9086, -- Blessed Steak
    28484, -- Blueberry Cupcake
    29415, -- Consecrated Beef

    40828, -- Mystic Cupcake
}

local regularUseItems = {
    26074, -- Blessed Acorn
    9086, -- Blessed Steak
    28484, -- Blueberry Cupcake
    29415, -- Consecrated Beef

    40828, -- Mystic Cupcake
}

local spellsSelfPlayerParam = {
    84, -- Heal Friend
    242, -- Nature's Embrace
    277, -- Mentor Other
    297, -- Restore Balance
}

local spellsAppend = {
    --{ id = 245, words = "exana vita", name = "Cancel Magic Shield" }
}

function healing_manaModule.init(widget)
    healingManaWindow = widget

    healing_manaModule.loadSettings()
end

function healing_manaModule.terminate()
    local page = healingManaWindow
    if widgetAlive(page) then
        pcall(function()
            local invalidTag = page.config.panel.invalidTag
            if not widgetAlive(invalidTag) then
                return
            end

            local event = invalidTag.eventTicks
            invalidTag.eventTicks = nil
            if event ~= nil then
                pcall(removeEvent, event)
            end
            if widgetAlive(invalidTag) then
                invalidTag:clearText()
            end
        end)
    end

    pcall(healing_manaModule.closeCatcher)

    if healingManaWindow == page then
        healingManaWindow = nil
    end
end

function healing_manaModule.reloadLanguage(language)
    if language == 'ptbr' then
        healingManaWindow.priority.priorityLabel:setText('Lista de prioridades')
        healingManaWindow.priority.listHeader.sourceLabel.label:setText('Fonte')
        healingManaWindow.priority.listHeader.fromMp.label:setText('Do MP')
        healingManaWindow.priority.listHeader.toMp.label:setText('Ate MP')
        healingManaWindow.priority.listHeader.actionLabel.label:setText('Acao')
        healingManaWindow.config.title:setText('Configuracao')
        healingManaWindow.config.notSelected:setText('Selecione uma entrada na lista para configurar ou criar uma nova entrada no botao +.')
        healingManaWindow.config.panel.save:setText('Aplicar')
        healingManaWindow.config.panel.name:setPlaceholder('Digite para pesquisar ou arraste')
        healingManaWindow.config.panel.options.spellCheck:setText('Usar Spell')
        healingManaWindow.config.panel.options.itemCheck:setText('Usar Item')
        healingManaWindow.config.panel.toMpHelp:setTooltip('Se sua porcentagem de vida for INFERIOR a esse valor, a acao pode ser executada.')
        healingManaWindow.config.panel.toMp:setText('Ate MP:')
        healingManaWindow.config.panel.fromMpHelp:setTooltip('Se sua porcentagem de vida for MAIOR que esse valor, a acao pode ser executada.')
        healingManaWindow.config.panel.fromMp:setText('Do MP:')

    elseif language == 'enus' then
        healingManaWindow.priority.priorityLabel:setText('Priority List')
        healingManaWindow.priority.listHeader.sourceLabel.label:setText('Source')
        healingManaWindow.priority.listHeader.fromMp.label:setText('From MP')
        healingManaWindow.priority.listHeader.toMp.label:setText('to MP')
        healingManaWindow.priority.listHeader.actionLabel.label:setText('Action')
        healingManaWindow.config.title:setText('Configure')
        healingManaWindow.config.notSelected:setText('Select an entry on the list to configure or create a band-new entry on the + button.')
        healingManaWindow.config.panel.save:setText('Apply')
        healingManaWindow.config.panel.name:setPlaceholder('Type to search or drop on slot')
        healingManaWindow.config.panel.options.spellCheck:setText('Spell entry')
        healingManaWindow.config.panel.options.itemCheck:setText('Item entry')
        healingManaWindow.config.panel.toMpHelp:setTooltip('If your Health percent is LOWER than this value, the action can be triggered.')
        healingManaWindow.config.panel.toMp:setText('To MP:')
        healingManaWindow.config.panel.fromMpHelp:setTooltip('If your Health percent is HIGHER than this value, the action can be triggered.')
        healingManaWindow.config.panel.fromMp:setText('From MP:')
    end

    for _, c in ipairs(healingManaWindow.priority.list:getChildren()) do
        if c.ignoreBackground then
            if language == 'ptbr' then
                c.text:setText('Nova Entrada')
            elseif language == 'enus' then
                c.text:setText('New Entry')
            end
        else
            if language == 'ptbr' then
                c.noVocation:setTooltip('Sua vocacao nao pode usar esta magia.')
                c.iconTooptip:setTooltip('Sua entrada e invalida, por favor reconfigure-a!')
            elseif language == 'enus' then
                c.noVocation:setTooltip('Your vocation cannot use this spell.')
                c.iconTooptip:setTooltip('Your entry is invalid, please reconfigure it!')
            end
        end
    end
end

function healing_manaModule.reloadInternalModule()
    local settings = modules.game_minibot.getPressetSettings()

    local list = {}
    local sList = settings['healing_mana'] or {}
    for _, entry in pairs(sList) do
        table.insert(list, entry)
    end

    table.sort(list, function(a, b)
        return a.priority < b.priority
    end)

    g_minibot.resetModule(2) -- Healing Mana Module type
    for _, entry in ipairs(list) do
        local internal = {
            item = tonumber(entry['item']),
            use = table.find(regularUseItems, tonumber(entry['item'])),
            min = tonumber(entry['min']),
            max = tonumber(entry['max']),
            enabled = entry['enabled'],
            spell = "",
            reqmana = tonumber(entry['reqmana']) or 0,

            spellGroup = {},
            spellId = {},

            area = "",
            target = "",
            health = 0,
            mana = 0,
            hits = 0,
            harmony = 0,
            itemGroup = {},
        }

        local canCast = true

        local spell = g_spells.getSpellInfoById(entry['spell'])
        if spell ~= nil then
            internal.spell = spell.words
            if table.find(spellsSelfPlayerParam, spell.id) then
                internal.spell = internal.spell .. ' \"' .. g_game.getCharacterName()
            end

            if not(modules.game_actionbar.canSpellCast(spell)) then
                canCast = false
            end

            table.insert(internal.spellId, spell.id)
            for _, group in ipairs(spell.groups) do
                table.insert(internal.spellGroup, group)
            end
        end

        if internal.item ~= 0 then
            table.insert(internal.itemGroup, 255) -- Multiuse
        end

        if canCast then
            g_minibot.addModule(2, internal)
        end
    end
end

local function reloadListBackgrounds()
    local isSelected = false

    for _, c in ipairs(healingManaWindow.priority.list:getChildren()) do
        if not(c.ignoreBackground) then
            c:setBackgroundColor('alpha')

            if c.mask:isVisible() then
                isSelected = true
            end
        end
    end

    if not(isSelected) then
        healingManaWindow.config.notSelected:show()
        healingManaWindow.config.panel:hide()
    else
        healingManaWindow.config.notSelected:hide()
        healingManaWindow.config.panel:show()
    end
end

function healing_manaModule.closeCatcher()
    local windowCatcher = nil
    pcall(function()
        windowCatcher = modules.game_minibot.getDropDownCatcher()
    end)
    if widgetAlive(windowCatcher) then
        pcall(function()
            windowCatcher:hide()
            windowCatcher.onLeftClick = nil
        end)
    end

    local page = healingManaWindow
    if not widgetAlive(page) then
        return
    end

    pcall(function()
        local options = page.config.panel.options
        if widgetAlive(options) then
            options:show()
        end
    end)
    pcall(function()
        local catcher = page.dropDownCatcher
        if widgetAlive(catcher) then
            catcher:hide()
            catcher.onLeftClick = nil
        end
    end)
    pcall(function()
        local scrollBar = page.dropDownMenuScrollBar
        if widgetAlive(scrollBar) then
            scrollBar:hide()
        end
    end)
    pcall(function()
        local menu = page.dropDownMenu
        if widgetAlive(menu) then
            menu:hide()
        end
    end)
end

function healing_manaModule.openCatcher(isItem)
    healingManaWindow.dropDownCatcher:show()
    healingManaWindow.dropDownCatcher.onLeftClick = healing_manaModule.closeCatcher

    local windowCatcher = modules.game_minibot.getDropDownCatcher()
    if windowCatcher ~= nil then
        windowCatcher:show()
        windowCatcher.onLeftClick = healing_manaModule.closeCatcher
    end

    healingManaWindow.dropDownMenu:show()
    healingManaWindow.dropDownMenuScrollBar:show()
    healingManaWindow.dropDownMenu:destroyChildren()

    healingManaWindow.config.panel.options:hide()

    if isItem then
        for _, item in ipairs(itemList) do
            local itemType = g_things.getThingType(item, ThingCategoryItem)
            if itemType then
                local itemWidget = g_ui.createWidget('MiniBotHealingManaitemDropDownEntry', healingManaWindow.dropDownMenu)
                itemWidget:setItemId(item)
                itemWidget:setTooltip(itemType:getName())

                itemWidget.onLeftClick = function()
                    healingManaWindow.config.panel.options.spellCheck:setChecked(true)
                    healingManaWindow.config.panel.options.itemCheck:setChecked(true)

                    healingManaWindow.config.panel.item:setItemId(item)
                    healingManaWindow.config.panel.frameBackground:setTooltip(healingManaWindow.config.panel.item:getItem():getName())
                    healing_manaModule.closeCatcher()
                end
            end
        end
    else
        for _, spell in ipairs(spellsAppend) do
            local foundSpell = g_spells.getSpellInfoById(spell.id)
            if foundSpell ~= nil then
                local spellWidget = g_ui.createWidget('MiniBotHealingManaSpellDropDownEntry', healingManaWindow.dropDownMenu)
                spellWidget:constructEnviorementVariables()

                if not(modules.game_actionbar.canSpellCast(foundSpell)) then
                    spellWidget.block:show()
                    spellWidget.icon:setOpacity(0.3)
                end

                spellWidget.icon:setImageClip(g_spells.getSpellRegularImageClipById(foundSpell.id))
                spellWidget:setTooltip(foundSpell.name .. '\n\'' .. foundSpell.words .. '\'')

                spellWidget.onLeftClick = function()
                    healingManaWindow.config.panel.options.itemCheck:setChecked(true)
                    healingManaWindow.config.panel.options.spellCheck:setChecked(true)

                    healingManaWindow.config.panel.spell:setImageClip(g_spells.getSpellRegularImageClipById(foundSpell.id))
                    healingManaWindow.config.panel.frameBackground:setTooltip(foundSpell.name .. '\n\'' .. foundSpell.words .. '\'')
                    healing_manaModule.closeCatcher()
                end
            end
        end
    end
end

function healing_manaModule.loadSettings()
    local settings = modules.game_minibot.getPressetSettings()

    local list = {}
    local sList = settings['healing_mana'] or {}
    local sSettings = settings['shortcuts'] or {}
    for _, entry in pairs(sList) do
        table.insert(list, entry)
    end

    table.sort(list, function(a, b)
        return a.priority < b.priority
    end)

    local newEntryButton = healingManaWindow.priority.list:getChildByIndex(1)
    for _, entry in ipairs(list) do
        local newWidget = g_ui.createWidget('MiniBotHealingManaEntry')
        newWidget:constructEnviorementVariables()

        healingManaWindow.priority.list:insertChild(healingManaWindow.priority.list:getChildIndex(newEntryButton), newWidget)
        healingManaWindow.priority.list:ensureChildVisible(newWidget)

        local isPhantom = (entry['item'] == 0 and entry['spell'] == 0) or entry['max'] == 0
        if isPhantom then
            newWidget.icon:setPhantom(true)
            newWidget.icon:setImageClip(torect('50 0 25 25'))
        else
            newWidget.icon:setChecked(entry['enabled'])
        end

        if entry['item'] > 0 then
            newWidget.item:setItemId(entry['item'])
            newWidget.item:show()
            newWidget.frameBackground:setTooltip(newWidget.item:getItem():getName())
        end

        if entry['spell'] > 0 then
            newWidget.spell:show()
            newWidget.spell:setImageClip(g_spells.getSpellRegularImageClipById(entry['spell']))

            local spell = g_spells.getSpellInfoById(entry['spell'])
            if spell ~= nil then
                newWidget.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
                if not(modules.game_actionbar.canSpellCast(spell)) then
                    newWidget.noVocation:show()
                end
            else
                newWidget.frameBackground:setTooltip('Unknown spell')
            end
        end

        if entry['min'] > 0 then
            newWidget.minMP:setText(entry['min'] .. '%')
        end

        if entry['max'] > 0 then
            newWidget.maxMP:setText(entry['max'] .. '%')
        end

        newWidget.onLeftClick = function()
            modules.game_minibot.callMethod('onClickEntry', newWidget)
        end

        newWidget.icon.onCheckChange = function()
            modules.game_minibot.callMethod('onIconCheckEntry', newWidget.icon:getParent())
        end

        newWidget.icon.onLeftClick = function()
            modules.game_minibot.callMethod('onClickEntry', newWidget.icon:getParent())
        end

        newWidget.noVocation.onLeftClick = function()
            modules.game_minibot.callMethod('onClickEntry', newWidget.noVocation:getParent())
        end

        newWidget.frameBackground.onLeftClick = function()
            modules.game_minibot.callMethod('onClickEntry', newWidget.frameBackground:getParent())
        end
    end

    healingManaWindow.priority.enabled.ignoreCallback = true
    healingManaWindow.priority.enabled:setChecked(sSettings['healingMana_enabled'])
    healingManaWindow.priority.enabled.ignoreCallback = nil

    healingManaWindow.priority.enabled.onCheckChange = function()
        if healingManaWindow.priority.enabled.ignoreCallback then
            return
        end

        local panel = modules.game_interface.getMiniBotPanel()
        if panel ~= nil then
            local child = panel:getChildById('healingMana_gamewindow')
            if child ~= nil then
                child.ignoreCallback = true
                child:setChecked(healingManaWindow.priority.enabled:isChecked())
                child.ignoreCallback = nil
            end
        end

        local settings2 = modules.game_minibot.getPressetSettings()
        if settings2['shortcuts'] == nil then
            settings2['shortcuts'] = {}
        end

        settings2['shortcuts']['healingMana_enabled'] = healingManaWindow.priority.enabled:isChecked()
        modules.game_minibot.setPressetSettings(settings2)
        g_minibot.setModuleToggle(2, healingManaWindow.priority.enabled:isChecked()) -- Healing Mana
    end

    reloadListBackgrounds()
end

function healing_manaModule.reloadEnabledShortcut(_, widget)
    if widget:getId() ~= 'healingMana_gamewindow' then
        return
    end

    healingManaWindow.priority.enabled.ignoreCallback = true
    healingManaWindow.priority.enabled:setChecked(widget:isChecked())
    healingManaWindow.priority.enabled.ignoreCallback = nil
end

function healing_manaModule.saveSettings()
    local settings = modules.game_minibot.getPressetSettings()

    local values = {}
    for i, c in ipairs(healingManaWindow.priority.list:getChildren()) do
        if not(c.ignoreBackground) then
            local value = {}
            value['priority'] = i
            value['item'] = 0
            value['spell'] = 0
            value['min'] = 0
            value['max'] = 0
            value['manaMax'] = 0
            value['manaMin'] = 0
            value['reqmana'] = 0
            value['enabled'] = not(c.icon:isPhantom()) and c.icon:isChecked()

            if c.minMP:getText() ~= '-%' then
                value['min'] = tonumber(string.sub(c.minMP:getText(), 1, -2))
            end

            if c.maxMP:getText() ~= '-%' then
                value['max'] = tonumber(string.sub(c.maxMP:getText(), 1, -2))
            end

            if c.item:isVisible() then
                value['item'] = c.item:getItemId()
            elseif c.spell:isVisible() then
                local spellId = g_spells.getSpellRegularIdByImageClipX(c.spell:getImageClip().x)
                local spell = g_spells.getSpellInfoById(spellId)
                if spell ~= nil then
                    value['spell'] = math.max(0, spellId)
                    value['reqmana'] = spell.mana
                end
            end

            table.insert(values, value)
        end
    end

    settings['healing_mana'] = values
    modules.game_minibot.setPressetSettings(settings)
    healing_manaModule.reloadInternalModule()
end

function healing_manaModule.onIconCheckEntry(widget)
    if widget:isPhantom() then
        widget:setImageClip(torect('50 0 25 25'))
        return
    end

    if widget:isChecked() then
        widget:setImageClip(torect('0 0 25 25'))
    else
        widget:setImageClip(torect('25 0 25 25'))
    end

    healing_manaModule.saveSettings()
end

function healing_manaModule.onClickEntry(widget)
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

    if healingManaWindow.config.selectedEntry == widget then
        return
    end

    healingManaWindow.config.selectedEntry = widget

    healingManaWindow.config.notSelected:hide()
    healingManaWindow.config.panel:show()

    healingManaWindow.config.panel.options.itemCheck.onCheckChange = nil
    healingManaWindow.config.panel.options.spellCheck.onCheckChange = nil
    healingManaWindow.config.panel.name.onTextChange = nil

    healingManaWindow.config.panel.options.itemCheck:setChecked(false)
    healingManaWindow.config.panel.options.spellCheck:setChecked(false)

    healingManaWindow.config.panel.item:hide()
    healingManaWindow.config.panel.spell:hide()

    if widget.item:isVisible() then
        healingManaWindow.config.panel.options.itemCheck:setChecked(true)
        healingManaWindow.config.panel.item:show()
        healingManaWindow.config.panel.item:setItemId(widget.item:getItemId())
        healingManaWindow.config.panel.frameBackground:setTooltip(widget.item:getItem():getName())
    end

    if widget.spell:isVisible() then
        healingManaWindow.config.panel.options.spellCheck:setChecked(true)
        healingManaWindow.config.panel.spell:show()
        healingManaWindow.config.panel.spell:setImageClip(widget.spell:getImageClip())

        local spell = g_spells.getSpellInfoById(g_spells.getSpellRegularIdByImageClipX(widget.spell:getImageClip().x))
        if spell ~= nil then
            healingManaWindow.config.panel.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
        else
            healingManaWindow.config.panel.frameBackground:setTooltip('Unknown spell')
        end
    end

    local max = ''
    if widget.maxMP:getText() ~= '-%' then
        max = string.sub(widget.maxMP:getText(), 1, -2)
    end
    healingManaWindow.config.panel.maxMP:setText(max)

    local min = ''
    if widget.minMP:getText() ~= '-%' then
        min = string.sub(widget.minMP:getText(), 1, -2)
    end
    healingManaWindow.config.panel.minMP:setText(min)

    if not(widget.item:isVisible()) and not(widget.spell:isVisible()) then
        healingManaWindow.config.panel.options.itemCheck:setChecked(true)
    end

    if healingManaWindow.config.panel.invalidTag.eventTicks ~= nil then
        removeEvent(healingManaWindow.config.panel.invalidTag.eventTicks)
        healingManaWindow.config.panel.invalidTag.eventTicks = nil
        healingManaWindow.config.panel.invalidTag:clearText()
    end

    local function onNameTextChange()
        if healingManaWindow.config.panel.name:getText() == '' then
            return
        end

        healingManaWindow.config.panel.frameBackground:removeTooltip()

        healingManaWindow.config.panel.name.onTextChange = nil
        healingManaWindow.config.panel.name.ignoreClear = true
        if healingManaWindow.config.panel.options.itemCheck:isChecked() then
            local items = g_things.findMarketableItemTypesByString(healingManaWindow.config.panel.name:getText())
            if items == nil or #items == 0 then
                healingManaWindow.config.panel.item:setItemId(0)
                healingManaWindow.config.panel.name.onTextChange = onNameTextChange
                healingManaWindow.config.panel.name.ignoreClear = nil
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
                healingManaWindow.config.panel.item:setItemId(0)
                healingManaWindow.config.panel.name.onTextChange = onNameTextChange
                healingManaWindow.config.panel.name.ignoreClear = nil
                return
            end

            healingManaWindow.config.panel.options.spellCheck:setChecked(true)
            healingManaWindow.config.panel.options.itemCheck:setChecked(true)

            healingManaWindow.config.panel.options.spellCheck.ignoreCallback = true
            healingManaWindow.config.panel.options.spellCheck:setChecked(false)
            healingManaWindow.config.panel.options.spellCheck.ignoreCallback = nil

            healingManaWindow.config.panel.spell:hide()
            healingManaWindow.config.panel.item:show()

            if healingManaWindow.config.panel.invalidTag.eventTicks ~= nil then
                removeEvent(healingManaWindow.config.panel.invalidTag.eventTicks)
                healingManaWindow.config.panel.invalidTag.eventTicks = nil
                healingManaWindow.config.panel.invalidTag:clearText()
            end

            healingManaWindow.config.panel.item:setItemId(found:getId())

            healingManaWindow.config.panel.frameBackground:setTooltip(healingManaWindow.config.panel.item:getItem():getName())
        elseif healingManaWindow.config.panel.options.spellCheck:isChecked() then
            local strToFind = healingManaWindow.config.panel.name:getText()
            local spells = {}
            for _, spell in ipairs(spellsAppend) do
                if spell.name:lower():contains(strToFind:lower()) or spell.words:lower():contains(strToFind:lower()) then
                    local foundSpell = g_spells.getSpellInfoById(spell.id)
                    if foundSpell ~= nil then
                        table.insert(spells, foundSpell)
                    end
                end
            end
            if spells == nil or #spells == 0 then
                healingManaWindow.config.panel.spell:setImageClip(torect('0 0 32 32'))
                healingManaWindow.config.panel.name.onTextChange = onNameTextChange
                healingManaWindow.config.panel.name.ignoreClear = nil
                return
            end

            local found = nil
            for _, spell in ipairs(spells) do
                if found == nil or (#(spell.name) < #(found.name)) then
                    found = spell
                end
            end

            if found == nil then
                healingManaWindow.config.panel.spell:setImageClip(torect('0 0 32 32'))
                healingManaWindow.config.panel.name.onTextChange = onNameTextChange
                healingManaWindow.config.panel.name.ignoreClear = nil
                return
            end

            if healingManaWindow.config.panel.invalidTag.eventTicks ~= nil then
                removeEvent(healingManaWindow.config.panel.invalidTag.eventTicks)
                healingManaWindow.config.panel.invalidTag.eventTicks = nil
                healingManaWindow.config.panel.invalidTag:clearText()
            end

            healingManaWindow.config.panel.options.itemCheck:setChecked(true)
            healingManaWindow.config.panel.options.spellCheck:setChecked(true)

            healingManaWindow.config.panel.options.itemCheck.ignoreCallback = true
            healingManaWindow.config.panel.options.itemCheck:setChecked(false)
            healingManaWindow.config.panel.options.itemCheck.ignoreCallback = nil

            healingManaWindow.config.panel.spell:show()
            healingManaWindow.config.panel.item:hide()

            healingManaWindow.config.panel.spell:setImageClip(g_spells.getSpellRegularImageClipById(found.id))

            healingManaWindow.config.panel.frameBackground:setTooltip(found.name .. '\n\'' .. found.words .. '\'')
        end

        healingManaWindow.config.panel.name.onTextChange = onNameTextChange
        healingManaWindow.config.panel.name.ignoreClear = nil
    end

    healingManaWindow.config.panel.options.itemCheck.onCheckChange = function(tmpWidget)
        if tmpWidget.ignoreCallback then
            return
        end

        if not(tmpWidget:isChecked()) then
            tmpWidget.ignoreCallback = true
            tmpWidget:setChecked(true)
            tmpWidget.ignoreCallback = nil
            return
        end

        healingManaWindow.config.panel.options.spellCheck.ignoreCallback = true
        healingManaWindow.config.panel.options.spellCheck:setChecked(false)
        healingManaWindow.config.panel.options.spellCheck.ignoreCallback = nil

        healingManaWindow.config.panel.spell:hide()
        healingManaWindow.config.panel.item:show()

        if not(healingManaWindow.config.panel.name.ignoreClear) then
            healingManaWindow.config.panel.name.onTextChange = nil
            healingManaWindow.config.panel.name:clearText()
            healingManaWindow.config.panel.name.onTextChange = onNameTextChange
        end

        if healingManaWindow.config.panel.item:getItem() ~= nil then
            healingManaWindow.config.panel.frameBackground:setTooltip(healingManaWindow.config.panel.item:getItem():getName())
        else
            healingManaWindow.config.panel.frameBackground:removeTooltip()
        end
    end

    healingManaWindow.config.panel.options.spellCheck.onCheckChange = function(tmpWidget)
        if tmpWidget.ignoreCallback then
            return
        end

        if not(tmpWidget:isChecked()) then
            tmpWidget.ignoreCallback = true
            tmpWidget:setChecked(true)
            tmpWidget.ignoreCallback = nil
            return
        end

        healingManaWindow.config.panel.options.itemCheck.ignoreCallback = true
        healingManaWindow.config.panel.options.itemCheck:setChecked(false)
        healingManaWindow.config.panel.options.itemCheck.ignoreCallback = nil

        healingManaWindow.config.panel.spell:show()
        healingManaWindow.config.panel.item:hide()

        if not(healingManaWindow.config.panel.name.ignoreClear) then
            healingManaWindow.config.panel.name.onTextChange = nil
            healingManaWindow.config.panel.name:clearText()
            healingManaWindow.config.panel.name.onTextChange = onNameTextChange
        end

        local spell = g_spells.getSpellInfoById(g_spells.getSpellRegularIdByImageClipX(healingManaWindow.config.panel.spell:getImageClip().x))
        if spell ~= nil then
            healingManaWindow.config.panel.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
        else
            healingManaWindow.config.panel.frameBackground:setTooltip('Unknown spell')
        end
    end

    healingManaWindow.config.panel.frameBackground.onDrop = function(_, droppedWidget, mousePos)
        healingManaWindow.config.panel.frameBackground:removeTooltip()

        if droppedWidget:getClassName() == "UIItem" then
            local item = droppedWidget:getItem()
            if item == nil or item:getMarketData() == nil or not(table.find(itemList, droppedWidget:getItemId())) then
                return
            end

            healingManaWindow.config.panel.options.spellCheck:setChecked(true)
            healingManaWindow.config.panel.options.itemCheck:setChecked(true)

            healingManaWindow.config.panel.item:setItemId(droppedWidget:getItemId())

            healingManaWindow.config.panel.frameBackground:setTooltip(healingManaWindow.config.panel.item:getItem():getName())
        end

        if droppedWidget.spellEntry and droppedWidget.spellId ~= nil and droppedWidget.spellId > 0 then
            local spell = g_spells.getSpellInfoById(droppedWidget.spellId)
            if spell == nil then
                return
            end

            healingManaWindow.config.panel.options.itemCheck:setChecked(true)
            healingManaWindow.config.panel.options.spellCheck:setChecked(true)

            healingManaWindow.config.panel.spell:setImageClip(g_spells.getSpellRegularImageClipById(spell.id))

            healingManaWindow.config.panel.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
        end
    end

    healingManaWindow.config.panel.frameBackground.onLeftClick = function()
        if healingManaWindow.config.panel.options.itemCheck:isChecked() then
            modules.game_minibot.deferMethod('openCatcher', true)
        elseif healingManaWindow.config.panel.options.spellCheck:isChecked() then
            modules.game_minibot.deferMethod('openCatcher', false)
        end
    end

    healingManaWindow.config.panel.name.onTextChange = onNameTextChange

    healingManaWindow.config.panel.save.onLeftClick = function()
        local selectedWidget = nil
        for _, c in ipairs(healingManaWindow.priority.list:getChildren()) do
            if c.mask:isVisible() then
                selectedWidget = c
                break
            end
        end

        if selectedWidget == nil then
            return
        end

        if healingManaWindow.config.panel.options.itemCheck:isChecked() then
            if healingManaWindow.config.panel.item:getItem() == nil then
                return
            end

            selectedWidget.spell:hide()
            selectedWidget.item:show()
            selectedWidget.noVocation:hide()

            selectedWidget.item:setItemId(healingManaWindow.config.panel.item:getItemId())
            selectedWidget.frameBackground:setTooltip(healingManaWindow.config.panel.item:getItem():getName())
        elseif healingManaWindow.config.panel.options.spellCheck:isChecked() then
            selectedWidget.spell:show()
            selectedWidget.item:hide()

            selectedWidget.spell:setImageClip(healingManaWindow.config.panel.spell:getImageClip())

            local spell = g_spells.getSpellInfoById(g_spells.getSpellRegularIdByImageClipX(healingManaWindow.config.panel.spell:getImageClip().x))
            if spell ~= nil then
                selectedWidget.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
                if not(modules.game_actionbar.canSpellCast(spell)) then
                    selectedWidget.noVocation:show()
                else
                    selectedWidget.noVocation:hide()
                end
            else
                selectedWidget.frameBackground:setTooltip('Unknown spell')
                selectedWidget.noVocation:hide()
            end
        else
            selectedWidget.icon:setChecked(true)
            selectedWidget.icon:setImageClip(torect('50 0 25 25'))
            selectedWidget.icon:setPhantom(true)
            selectedWidget.noVocation:hide()
            return
        end

        local min = healingManaWindow.config.panel.minMP:getText()
        local minValue = tonumber(min) or 0
        if min == '' then
            min = '-'
        end
        selectedWidget.minMP:setText(min .. '%')

        local max = healingManaWindow.config.panel.maxMP:getText()
        local maxValue = tonumber(max) or 0
        if max == '' then
            max = '-'
        end
        selectedWidget.maxMP:setText(max .. '%')

        if maxValue > 0 and ((selectedWidget.item:isVisible() and selectedWidget.item:getItem()) or selectedWidget.spell:isVisible()) then
            if selectedWidget.icon:isPhantom() then
                selectedWidget.icon:setPhantom(false)
                selectedWidget.icon:setImageClip(torect('25 0 25 25'))
            end
        elseif not(selectedWidget.icon:isPhantom()) then
            selectedWidget.icon:setPhantom(true)
            selectedWidget.icon:setImageClip(torect('50 0 25 25'))
        end

        healing_manaModule.saveSettings()
    end
end

function healing_manaModule.onRemoveEntry(widget)
    if not widgetAlive(widget) then
        return
    end
    pcall(function()
        widget:destroy()
    end)

    reloadListBackgrounds()

    healing_manaModule.saveSettings()
end

function healing_manaModule.validateTextPercentage(widget)
    if widget:getText() == '' then
        if widget:getId() == 'maxMP' then
            healingManaWindow.config.panel.minMP:clearText()
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

    if widget:getId() == 'minMP' then
        if healingManaWindow.config.panel.maxMP:getText() ~= '' then
            if value > (tonumber(healingManaWindow.config.panel.maxMP:getText()) or 0) then
                widget:setText(healingManaWindow.config.panel.maxMP:getText())
            end
        end
    elseif widget:getId() == 'maxMP' then
        local minValue = tonumber(healingManaWindow.config.panel.minMP:getText()) or 0
        if minValue > value then
            healingManaWindow.config.panel.minMP:setText(value)
        end
    end

end

function healing_manaModule.onMoveUpEntry(widget)
    local index = widget:getParent():getChildIndex(widget)
    if index == 1 then
        return
    end

    widget:getParent():moveChildToIndex(widget, index - 1)
    reloadListBackgrounds()

    widget:onLeftClick()

    healing_manaModule.saveSettings()
end

function healing_manaModule.onMoveDownEntry(widget)
    local index = widget:getParent():getChildIndex(widget)
    if index == (widget:getParent():getChildCount() - 1) then
        return
    end

    widget:getParent():moveChildToIndex(widget, index + 1)
    reloadListBackgrounds()

    widget:onLeftClick()

    healing_manaModule.saveSettings()
end

function healing_manaModule.onNewEntry(widget)
    if widget.isClickFromUiScrollAreaArrow then
        return
    end

    local lastIndex = widget:getParent():getChildIndex(widget)
    local newWidget = g_ui.createWidget('MiniBotHealingManaEntry')
    newWidget:constructEnviorementVariables()

    newWidget.onLeftClick = function()
        modules.game_minibot.callMethod('onClickEntry', newWidget)
    end

    newWidget.icon.onCheckChange = function()
        modules.game_minibot.callMethod('onIconCheckEntry', newWidget.icon:getParent())
    end

    newWidget.icon.onLeftClick = function()
        modules.game_minibot.callMethod('onClickEntry', newWidget.icon:getParent())
    end

    newWidget.noVocation.onLeftClick = function()
        modules.game_minibot.callMethod('onClickEntry', newWidget.noVocation:getParent())
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

    healing_manaModule.saveSettings()
end
