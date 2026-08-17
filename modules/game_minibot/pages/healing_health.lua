healing_healthModule = {}

local healingHealthWindow = nil

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
    239, -- Great Health Potion
    7642, -- Great Spirit Potion
    266, -- Health Potion
    7876, -- Small Health Potion
    236, -- Strong Health Potion
    23375, -- Supreme Health Potion
    7643, -- Ultimate Health Potion
    23374, -- Ultimate Spirit Potion
    41096, -- Legendary Spirit Potion
    3152, -- Intense Healing Rune
    3160, -- Ultimate Healing Rune
    26074, -- Blessed Acorn
    29414, -- Carrionsserole
    11586, -- Pot of Blackjack
    9079, -- Rotworm Stew
    28485, -- Strawberry Cupcake
    35563, -- Magic Shield Potion

    40949, -- Legendary Health Potion
    40829, -- Mystic Strawberry

    40695, -- Medkit Scroll
}

local regularUseItems = {
    26074, -- Blessed Acorn
    29414, -- Carrionsserole
    11586, -- Pot of Blackjack
    9079, -- Rotworm Stew
    28485, -- Strawberry Cupcake
    --35563, -- Magic Shield Potion

    40829, -- Mystic Strawberry

    40695, -- Medkit Scroll
}

local spellsSelfPlayerParam = {
    84, -- Heal Friend
    242, -- Nature's Embrace
    277, -- Mentor Other
    297, -- Restore Balance
}

local spellsAppend = {
    --{ id = 44, words = "utamo vita", name = "Magic Shield" },
}

function healing_healthModule.init(widget)
    healingHealthWindow = widget

    healing_healthModule.loadSettings()
end

function healing_healthModule.terminate()
    local page = healingHealthWindow
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

    pcall(healing_healthModule.closeCatcher)

    if healingHealthWindow == page then
        healingHealthWindow = nil
    end
end

function healing_healthModule.reloadLanguage(language)
    if language == 'ptbr' then
        healingHealthWindow.priority.priorityLabel:setText('Lista de prioridades')
        healingHealthWindow.priority.listHeader.sourceLabel.label:setText('Fonte')
        healingHealthWindow.priority.listHeader.fromHp.label:setText('Do HP')
        healingHealthWindow.priority.listHeader.toHp.label:setText('Ate HP')
        healingHealthWindow.priority.listHeader.actionLabel.label:setText('Acao')
        healingHealthWindow.config.title:setText('Configuracao')
        healingHealthWindow.config.notSelected:setText('Selecione uma entrada na lista para configurar ou criar uma nova entrada no botao +.')
        healingHealthWindow.config.panel.save:setText('Aplicar')
        healingHealthWindow.config.panel.name:setPlaceholder('Digite para pesquisar ou arraste')
        healingHealthWindow.config.panel.options.spellCheck:setText('Usar Spell')
        healingHealthWindow.config.panel.options.itemCheck:setText('Usar Item')
        healingHealthWindow.config.panel.toHpHelp:setTooltip('Se sua porcentagem de vida for INFERIOR a esse valor, a acao pode ser executada.')
        healingHealthWindow.config.panel.toHp:setText('Ate HP:')
        healingHealthWindow.config.panel.fromHpHelp:setTooltip('Se sua porcentagem de vida for MAIOR que esse valor, a acao pode ser executada.')
        healingHealthWindow.config.panel.fromHp:setText('Do HP:')
        healingHealthWindow.config.panel.harmonyHelp:setTooltip('Voce pode definir um nivel minimo de Harmonia para ativar o uso deste item/spell.')
        healingHealthWindow.config.panel.harmonyLabel:setText('Harmonia:')

    elseif language == 'enus' then
        healingHealthWindow.priority.priorityLabel:setText('Priority List')
        healingHealthWindow.priority.listHeader.sourceLabel.label:setText('Source')
        healingHealthWindow.priority.listHeader.fromHp.label:setText('From HP')
        healingHealthWindow.priority.listHeader.toHp.label:setText('to HP')
        healingHealthWindow.priority.listHeader.actionLabel.label:setText('Action')
        healingHealthWindow.config.title:setText('Configure')
        healingHealthWindow.config.notSelected:setText('Select an entry on the list to configure or create a band-new entry on the + button.')
        healingHealthWindow.config.panel.save:setText('Apply')
        healingHealthWindow.config.panel.name:setPlaceholder('Type to search or drop on slot')
        healingHealthWindow.config.panel.options.spellCheck:setText('Spell entry')
        healingHealthWindow.config.panel.options.itemCheck:setText('Item entry')
        healingHealthWindow.config.panel.toHpHelp:setTooltip('If your Health percent is LOWER than this value, the action can be triggered.')
        healingHealthWindow.config.panel.toHp:setText('To HP:')
        healingHealthWindow.config.panel.fromHpHelp:setTooltip('If your Health percent is HIGHER than this value, the action can be triggered.')
        healingHealthWindow.config.panel.fromHp:setText('From HP:')
        healingHealthWindow.config.panel.harmonyHelp:setTooltip('You can set a minimum Harmony level to trigger this item/spell usage.')
        healingHealthWindow.config.panel.harmonyLabel:setText('Harmony:')
    end

    for _, c in ipairs(healingHealthWindow.priority.list:getChildren()) do
        if c.ignoreBackground then
            if language == 'ptbr' then
                c.text:setText('Nova Entrada')
            elseif language == 'enus' then
                c.text:setText('New Entry')
            end
        else
            if language == 'ptbr' then
                c.harmony:setTooltip('Seu requisito de Harmonia selecionado.')
                c.noVocation:setTooltip('Sua vocacao nao pode usar esta magia.')
                c.iconTooptip:setTooltip('Sua entrada e invalida, por favor reconfigure-a!')
            elseif language == 'enus' then
                c.harmony:setTooltip('Your selected Harmony requirement.')
                c.noVocation:setTooltip('Your vocation cannot use this spell.')
                c.iconTooptip:setTooltip('Your entry is invalid, please reconfigure it!')
            end
        end
    end
end

function healing_healthModule.reloadInternalModule()
    local settings = modules.game_minibot.getPressetSettings()

    local list = {}
    local sList = settings['healing_health'] or {}
    for _, entry in pairs(sList) do
        table.insert(list, entry)
    end

    table.sort(list, function(a, b)
        return a.priority < b.priority
    end)

    g_minibot.resetModule(1) -- Healing Health Module type
    for _, entry in ipairs(list) do
        local internal = {
            item = tonumber(entry['item']),
            use = table.find(regularUseItems, tonumber(entry['item'])),
            min = tonumber(entry['min']),
            max = tonumber(entry['max']),
            enabled = entry['enabled'],
            spell = "",
            reqmana = tonumber(entry['reqmana']) or 0,
            harmony = tonumber(entry['harmony']) or 0,

            spellGroup = {},
            spellId = {},

            area = "",
            target = "",
            health = 0,
            mana = 0,
            hits = 0,
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
            g_minibot.addModule(1, internal)
        end
    end
end

local function reloadListBackgrounds()
    local isSelected = false

    for _, c in ipairs(healingHealthWindow.priority.list:getChildren()) do
        if not(c.ignoreBackground) then
            c:setBackgroundColor('alpha')

            if c.mask:isVisible() then
                isSelected = true
            end
        end
    end

    if not(isSelected) then
        healingHealthWindow.config.notSelected:show()
        healingHealthWindow.config.panel:hide()
    else
        healingHealthWindow.config.notSelected:hide()
        healingHealthWindow.config.panel:show()
    end
end

function healing_healthModule.closeCatcher()
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

    local page = healingHealthWindow
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

function healing_healthModule.openCatcher(isItem)
    healingHealthWindow.dropDownCatcher:show()
    healingHealthWindow.dropDownCatcher.onLeftClick = healing_healthModule.closeCatcher

    local windowCatcher = modules.game_minibot.getDropDownCatcher()
    if windowCatcher ~= nil then
        windowCatcher:show()
        windowCatcher.onLeftClick = healing_healthModule.closeCatcher
    end

    healingHealthWindow.dropDownMenu:show()
    healingHealthWindow.dropDownMenuScrollBar:show()
    healingHealthWindow.dropDownMenu:destroyChildren()

    healingHealthWindow.config.panel.options:hide()

    if isItem then
        for _, item in ipairs(itemList) do
            local itemType = g_things.getThingType(item, ThingCategoryItem)
            if itemType then
                local itemWidget = g_ui.createWidget('MiniBotHealingHealthitemDropDownEntry', healingHealthWindow.dropDownMenu)
                itemWidget:setItemId(item)
                itemWidget:setTooltip(itemType:getName())

                itemWidget.onLeftClick = function()
                    healingHealthWindow.config.panel.options.spellCheck:setChecked(true)
                    healingHealthWindow.config.panel.options.itemCheck:setChecked(true)

                    healingHealthWindow.config.panel.item:setItemId(item)
                    healingHealthWindow.config.panel.frameBackground:setTooltip(healingHealthWindow.config.panel.item:getItem():getName())
                    healing_healthModule.closeCatcher()

                    healingHealthWindow.config.panel.harmonyHelp:hide()
                    healingHealthWindow.config.panel.harmonyValue:hide()
                    healingHealthWindow.config.panel.harmonyLabel:hide()
                end
            end
        end
    else
        local spells = g_spells.getSpellsByGroup(SpellGroup.Healing)
        for _, spell in ipairs(spells) do
            local spellWidget = g_ui.createWidget('MiniBotHealingHealthSpellDropDownEntry', healingHealthWindow.dropDownMenu)
            spellWidget:constructEnviorementVariables()

            if not(modules.game_actionbar.canSpellCast(spell)) then
                spellWidget.block:show()
                spellWidget.icon:setOpacity(0.3)
            end

            spellWidget.icon:setImageClip(g_spells.getSpellRegularImageClipById(spell.id))
            spellWidget:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')

            spellWidget.onLeftClick = function()
                healingHealthWindow.config.panel.options.itemCheck:setChecked(true)
                healingHealthWindow.config.panel.options.spellCheck:setChecked(true)

                healingHealthWindow.config.panel.spell:setImageClip(g_spells.getSpellRegularImageClipById(spell.id))
                healingHealthWindow.config.panel.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
                healing_healthModule.closeCatcher()

                healingHealthWindow.config.panel.harmonyHelp:hide()
                healingHealthWindow.config.panel.harmonyValue:hide()
                healingHealthWindow.config.panel.harmonyLabel:hide()

                if table.find(spell.vocations, "Monk") then
                    healingHealthWindow.config.panel.harmonyHelp:show()
                    healingHealthWindow.config.panel.harmonyValue:show()
                    healingHealthWindow.config.panel.harmonyLabel:show()
                end
            end
        end
        for _, spell in ipairs(spellsAppend) do
            local foundSpell = g_spells.getSpellInfoById(spell.id)
            if spellsAppend ~= nil then
                local spellWidget = g_ui.createWidget('MiniBotHealingHealthSpellDropDownEntry', healingHealthWindow.dropDownMenu)
                spellWidget:constructEnviorementVariables()

                if not(modules.game_actionbar.canSpellCast(foundSpell)) then
                    spellWidget.block:show()
                    spellWidget.icon:setOpacity(0.3)
                end

                spellWidget.icon:setImageClip(g_spells.getSpellRegularImageClipById(foundSpell.id))
                spellWidget:setTooltip(foundSpell.name .. '\n\'' .. foundSpell.words .. '\'')

                spellWidget.onLeftClick = function()
                    healingHealthWindow.config.panel.options.itemCheck:setChecked(true)
                    healingHealthWindow.config.panel.options.spellCheck:setChecked(true)

                    healingHealthWindow.config.panel.spell:setImageClip(g_spells.getSpellRegularImageClipById(foundSpell.id))
                    healingHealthWindow.config.panel.frameBackground:setTooltip(foundSpell.name .. '\n\'' .. foundSpell.words .. '\'')
                    healing_healthModule.closeCatcher()

                    healingHealthWindow.config.panel.harmonyHelp:hide()
                    healingHealthWindow.config.panel.harmonyValue:hide()
                    healingHealthWindow.config.panel.harmonyLabel:hide()

                    if table.find(foundSpell.vocations, "Monk") then
                        healingHealthWindow.config.panel.harmonyHelp:show()
                        healingHealthWindow.config.panel.harmonyValue:show()
                        healingHealthWindow.config.panel.harmonyLabel:show()
                    end
                end
            end
        end
    end
end

function healing_healthModule.loadSettings()
    local settings = modules.game_minibot.getPressetSettings()

    local list = {}
    local sList = settings['healing_health'] or {}
    local sSettings = settings['shortcuts'] or {}
    for _, entry in pairs(sList) do
        table.insert(list, entry)
    end

    table.sort(list, function(a, b)
        return a.priority < b.priority
    end)

    local newEntryButton = healingHealthWindow.priority.list:getChildByIndex(1)
    for _, entry in ipairs(list) do
        local newWidget = g_ui.createWidget('MiniBotHealingHealthEntry')
        newWidget:constructEnviorementVariables()

        healingHealthWindow.priority.list:insertChild(healingHealthWindow.priority.list:getChildIndex(newEntryButton), newWidget)
        healingHealthWindow.priority.list:ensureChildVisible(newWidget)

        local isPhantom = (entry['item'] == 0 and entry['spell'] == 0) or entry['max'] == 0
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

        if entry['spell'] > 0 then
            newWidget.spell:show()
            newWidget.spell:setImageClip(g_spells.getSpellRegularImageClipById(entry['spell']))

            local spell = g_spells.getSpellInfoById(entry['spell'])
            if spell ~= nil then
                newWidget.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
                if not(modules.game_actionbar.canSpellCast(spell)) then
                    newWidget.noVocation:show()
                end

                if table.find(spell.vocations, "Monk") then
                    newWidget.harmony:show()
                    newWidget.harmony:setImageClip(torect(tostring((entry['harmony'] or 0) * 10) .. " 0 10 39"))
                end
            else
                newWidget.frameBackground:setTooltip('Unknown spell')
            end
        end

        if entry['min'] > 0 then
            newWidget.minHp:setText(entry['min'] .. '%')
        end

        if entry['max'] > 0 then
            newWidget.maxHp:setText(entry['max'] .. '%')
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

    healingHealthWindow.priority.enabled.ignoreCallback = true
    healingHealthWindow.priority.enabled:setChecked(sSettings['healingHealth_enabled'])
    healingHealthWindow.priority.enabled.ignoreCallback = nil

    healingHealthWindow.priority.enabled.onCheckChange = function()
        if healingHealthWindow.priority.enabled.ignoreCallback then
            return
        end

        local panel = modules.game_interface.getMiniBotPanel()
        if panel ~= nil then
            local child = panel:getChildById('healingHealth_gamewindow')
            if child ~= nil then
                child.ignoreCallback = true
                child:setChecked(healingHealthWindow.priority.enabled:isChecked())
                child.ignoreCallback = nil
            end
        end

        local settings2 = modules.game_minibot.getPressetSettings()
        if settings2['shortcuts'] == nil then
            settings2['shortcuts'] = {}
        end

        settings2['shortcuts']['healingHealth_enabled'] = healingHealthWindow.priority.enabled:isChecked()
        modules.game_minibot.setPressetSettings(settings2)
        g_minibot.setModuleToggle(1, healingHealthWindow.priority.enabled:isChecked()) -- Healing Health
    end

    reloadListBackgrounds()
end

function healing_healthModule.reloadEnabledShortcut(_, widget)
    if widget:getId() ~= 'healingHealth_gamewindow' then
        return
    end

    healingHealthWindow.priority.enabled.ignoreCallback = true
    healingHealthWindow.priority.enabled:setChecked(widget:isChecked())
    healingHealthWindow.priority.enabled.ignoreCallback = nil
end

function healing_healthModule.saveSettings()
    local settings = modules.game_minibot.getPressetSettings()

    local values = {}
    for i, c in ipairs(healingHealthWindow.priority.list:getChildren()) do
        if not(c.ignoreBackground) then
            local value = {}
            value['priority'] = i
            value['item'] = 0
            value['spell'] = 0
            value['reqmana'] = 0
            value['min'] = 0
            value['max'] = 0
            value['manaMax'] = 0
            value['manaMin'] = 0
            value['harmony'] = 0
            value['enabled'] = not(c.icon:isPhantom()) and c.icon:isChecked()

            if c.minHp:getText() ~= '-%' then
                value['min'] = tonumber(string.sub(c.minHp:getText(), 1, -2))
            end

            if c.maxHp:getText() ~= '-%' then
                value['max'] = tonumber(string.sub(c.maxHp:getText(), 1, -2))
            end

            if c.item:isVisible() then
                value['item'] = c.item:getItemId()
            elseif c.spell:isVisible() then
                local spellId = g_spells.getSpellRegularIdByImageClipX(c.spell:getImageClip().x)
                local spell = g_spells.getSpellInfoById(spellId)
                if spell ~= nil then
                    value['spell'] = math.max(0, spellId)
                    value['reqmana'] = spell.mana

                    if table.find(spell.vocations, "Monk") then
                        value['harmony'] = c.harmony:getImageClip().x / 10
                    end
                end
            end

            table.insert(values, value)
        end
    end

    settings['healing_health'] = values
    modules.game_minibot.setPressetSettings(settings)
    healing_healthModule.reloadInternalModule()
end

function healing_healthModule.onIconCheckEntry(widget)
    if widget:isPhantom() then
        widget:setImageClip(torect('50 0 25 25'))
        return
    end

    if widget:isChecked() then
        widget:setImageClip(torect('0 0 25 25'))
    else
        widget:setImageClip(torect('25 0 25 25'))
    end

    healing_healthModule.saveSettings()
end

function healing_healthModule.validateTextHarmony(widget)
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

function healing_healthModule.onClickEntry(widget)
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

    if healingHealthWindow.config.selectedEntry == widget then
        return
    end

    healingHealthWindow.config.selectedEntry = widget

    healingHealthWindow.config.notSelected:hide()
    healingHealthWindow.config.panel:show()

    healingHealthWindow.config.panel.options.itemCheck.onCheckChange = nil
    healingHealthWindow.config.panel.options.spellCheck.onCheckChange = nil
    healingHealthWindow.config.panel.name.onTextChange = nil

    healingHealthWindow.config.panel.options.itemCheck:setChecked(false)
    healingHealthWindow.config.panel.options.spellCheck:setChecked(false)

    healingHealthWindow.config.panel.harmonyHelp:hide()
    healingHealthWindow.config.panel.harmonyValue:hide()
    healingHealthWindow.config.panel.harmonyLabel:hide()
    healingHealthWindow.config.panel.harmonyValue:clearText()

    healingHealthWindow.config.panel.item:hide()
    healingHealthWindow.config.panel.spell:hide()

    if widget.item:isVisible() then
        healingHealthWindow.config.panel.options.itemCheck:setChecked(true)
        healingHealthWindow.config.panel.item:show()
        healingHealthWindow.config.panel.item:setItemId(widget.item:getItemId())
        healingHealthWindow.config.panel.frameBackground:setTooltip(widget.item:getItem():getName())
    end

    if widget.spell:isVisible() then
        healingHealthWindow.config.panel.options.spellCheck:setChecked(true)
        healingHealthWindow.config.panel.spell:show()
        healingHealthWindow.config.panel.spell:setImageClip(widget.spell:getImageClip())

        local spell = g_spells.getSpellInfoById(g_spells.getSpellRegularIdByImageClipX(widget.spell:getImageClip().x))
        if spell ~= nil then
            healingHealthWindow.config.panel.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')

            if table.find(spell.vocations, "Monk") then
                healingHealthWindow.config.panel.harmonyHelp:show()
                healingHealthWindow.config.panel.harmonyValue:show()
                healingHealthWindow.config.panel.harmonyLabel:show()
                healingHealthWindow.config.panel.harmonyValue:clearText()

                local harmony = widget.harmony:getImageClip().x / 10
                if harmony > 0 then
                    healingHealthWindow.config.panel.harmonyValue:setText(tostring(widget.harmony:getImageClip().x / 10))
                end
            end
        else
            healingHealthWindow.config.panel.frameBackground:setTooltip('Unknown spell')
        end
    end

    local max = ''
    if widget.maxHp:getText() ~= '-%' then
        max = string.sub(widget.maxHp:getText(), 1, -2)
    end
    healingHealthWindow.config.panel.maxHp:setText(max)

    local min = ''
    if widget.minHp:getText() ~= '-%' then
        min = string.sub(widget.minHp:getText(), 1, -2)
    end
    healingHealthWindow.config.panel.minHp:setText(min)

    if not(widget.item:isVisible()) and not(widget.spell:isVisible()) then
        healingHealthWindow.config.panel.options.itemCheck:setChecked(true)
    end

    if healingHealthWindow.config.panel.invalidTag.eventTicks ~= nil then
        removeEvent(healingHealthWindow.config.panel.invalidTag.eventTicks)
        healingHealthWindow.config.panel.invalidTag.eventTicks = nil
        healingHealthWindow.config.panel.invalidTag:clearText()
    end

    local function onNameTextChange()
        if healingHealthWindow.config.panel.name:getText() == '' then
            return
        end

        healingHealthWindow.config.panel.frameBackground:removeTooltip()

        healingHealthWindow.config.panel.name.onTextChange = nil
        healingHealthWindow.config.panel.name.ignoreClear = true
        if healingHealthWindow.config.panel.options.itemCheck:isChecked() then
            local items = g_things.findMarketableItemTypesByString(healingHealthWindow.config.panel.name:getText())
            if items == nil or #items == 0 then
                healingHealthWindow.config.panel.item:setItemId(0)
                healingHealthWindow.config.panel.name.onTextChange = onNameTextChange
                healingHealthWindow.config.panel.name.ignoreClear = nil
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
                healingHealthWindow.config.panel.item:setItemId(0)
                healingHealthWindow.config.panel.name.onTextChange = onNameTextChange
                healingHealthWindow.config.panel.name.ignoreClear = nil
                return
            end

            healingHealthWindow.config.panel.options.spellCheck:setChecked(true)
            healingHealthWindow.config.panel.options.itemCheck:setChecked(true)

            healingHealthWindow.config.panel.options.spellCheck.ignoreCallback = true
            healingHealthWindow.config.panel.options.spellCheck:setChecked(false)
            healingHealthWindow.config.panel.options.spellCheck.ignoreCallback = nil

            healingHealthWindow.config.panel.spell:hide()
            healingHealthWindow.config.panel.item:show()

            if healingHealthWindow.config.panel.invalidTag.eventTicks ~= nil then
                removeEvent(healingHealthWindow.config.panel.invalidTag.eventTicks)
                healingHealthWindow.config.panel.invalidTag.eventTicks = nil
                healingHealthWindow.config.panel.invalidTag:clearText()
            end

            healingHealthWindow.config.panel.item:setItemId(found:getId())

            healingHealthWindow.config.panel.frameBackground:setTooltip(healingHealthWindow.config.panel.item:getItem():getName())
        elseif healingHealthWindow.config.panel.options.spellCheck:isChecked() then
            local strToFind = healingHealthWindow.config.panel.name:getText()
            local foundList = g_spells.findSpellsByString(strToFind, SpellGroup.Healing)
            for _, spell in ipairs(spellsAppend) do
                if spell.name:lower():contains(strToFind:lower()) then
                    local foundSpell = g_spells.getSpellInfoById(spell.id)
                    if foundSpell ~= nil then
                        table.insert(foundList, { block = foundSpell, type = 'name' })
                    end
                end
                if spell.words:lower():contains(strToFind:lower()) then
                    local foundSpell = g_spells.getSpellInfoById(spell.id)
                    if foundSpell ~= nil then
                        table.insert(foundList, { block = foundSpell, type = 'words' })
                    end
                end
            end
            if foundList == nil or #foundList == 0 then
                healingHealthWindow.config.panel.spell:setImageClip(torect('0 0 32 32'))
                healingHealthWindow.config.panel.name.onTextChange = onNameTextChange
                healingHealthWindow.config.panel.name.ignoreClear = nil
                return
            end

            local found = nil
            for _, foundIt in ipairs(foundList) do
                if found == nil then
                    found = foundIt.block
                elseif (foundIt.type == 'name' and #(foundIt.block.name) < #(found.name)) or (foundIt.type == 'words' and #(foundIt.block.words) < #(found.words)) then
                    found = foundIt.block
                end
            end

            if found == nil then
                healingHealthWindow.config.panel.spell:setImageClip(torect('0 0 32 32'))
                healingHealthWindow.config.panel.name.onTextChange = onNameTextChange
                healingHealthWindow.config.panel.name.ignoreClear = nil
                return
            end

            if healingHealthWindow.config.panel.invalidTag.eventTicks ~= nil then
                removeEvent(healingHealthWindow.config.panel.invalidTag.eventTicks)
                healingHealthWindow.config.panel.invalidTag.eventTicks = nil
                healingHealthWindow.config.panel.invalidTag:clearText()
            end

            healingHealthWindow.config.panel.options.itemCheck:setChecked(true)
            healingHealthWindow.config.panel.options.spellCheck:setChecked(true)

            healingHealthWindow.config.panel.options.itemCheck.ignoreCallback = true
            healingHealthWindow.config.panel.options.itemCheck:setChecked(false)
            healingHealthWindow.config.panel.options.itemCheck.ignoreCallback = nil

            healingHealthWindow.config.panel.spell:show()
            healingHealthWindow.config.panel.item:hide()

            healingHealthWindow.config.panel.spell:setImageClip(g_spells.getSpellRegularImageClipById(found.id))

            healingHealthWindow.config.panel.frameBackground:setTooltip(found.name .. '\n\'' .. found.words .. '\'')
        end

        healingHealthWindow.config.panel.name.onTextChange = onNameTextChange
        healingHealthWindow.config.panel.name.ignoreClear = nil
    end

    healingHealthWindow.config.panel.options.itemCheck.onCheckChange = function(tmpWidget)
        if tmpWidget.ignoreCallback then
            return
        end

        if not(tmpWidget:isChecked()) then
            tmpWidget.ignoreCallback = true
            tmpWidget:setChecked(true)
            tmpWidget.ignoreCallback = nil
            return
        end

        healingHealthWindow.config.panel.options.spellCheck.ignoreCallback = true
        healingHealthWindow.config.panel.options.spellCheck:setChecked(false)
        healingHealthWindow.config.panel.options.spellCheck.ignoreCallback = nil

        healingHealthWindow.config.panel.spell:hide()
        healingHealthWindow.config.panel.item:show()

        if not(healingHealthWindow.config.panel.name.ignoreClear) then
            healingHealthWindow.config.panel.name.onTextChange = nil
            healingHealthWindow.config.panel.name:clearText()
            healingHealthWindow.config.panel.name.onTextChange = onNameTextChange
        end

        if healingHealthWindow.config.panel.item:getItem() ~= nil then
            healingHealthWindow.config.panel.frameBackground:setTooltip(healingHealthWindow.config.panel.item:getItem():getName())
        else
            healingHealthWindow.config.panel.frameBackground:removeTooltip()
        end

        healingHealthWindow.config.panel.harmonyHelp:hide()
        healingHealthWindow.config.panel.harmonyValue:hide()
        healingHealthWindow.config.panel.harmonyLabel:hide()
        healingHealthWindow.config.panel.harmonyValue:clearText()
    end

    healingHealthWindow.config.panel.options.spellCheck.onCheckChange = function(tmpWidget)
        if tmpWidget.ignoreCallback then
            return
        end

        if not(tmpWidget:isChecked()) then
            tmpWidget.ignoreCallback = true
            tmpWidget:setChecked(true)
            tmpWidget.ignoreCallback = nil
            return
        end

        healingHealthWindow.config.panel.options.itemCheck.ignoreCallback = true
        healingHealthWindow.config.panel.options.itemCheck:setChecked(false)
        healingHealthWindow.config.panel.options.itemCheck.ignoreCallback = nil

        healingHealthWindow.config.panel.spell:show()
        healingHealthWindow.config.panel.item:hide()

        if not(healingHealthWindow.config.panel.name.ignoreClear) then
            healingHealthWindow.config.panel.name.onTextChange = nil
            healingHealthWindow.config.panel.name:clearText()
            healingHealthWindow.config.panel.name.onTextChange = onNameTextChange
        end

        local spell = g_spells.getSpellInfoById(g_spells.getSpellRegularIdByImageClipX(healingHealthWindow.config.panel.spell:getImageClip().x))
        if spell ~= nil then
            healingHealthWindow.config.panel.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
        else
            healingHealthWindow.config.panel.frameBackground:setTooltip('Unknown spell')
        end

        healingHealthWindow.config.panel.harmonyHelp:hide()
        healingHealthWindow.config.panel.harmonyValue:hide()
        healingHealthWindow.config.panel.harmonyLabel:hide()
        healingHealthWindow.config.panel.harmonyValue:clearText()
    end

    healingHealthWindow.config.panel.frameBackground.onDrop = function(_, droppedWidget, mousePos)
        healingHealthWindow.config.panel.frameBackground:removeTooltip()

        if droppedWidget:getClassName() == "UIItem" then
            local item = droppedWidget:getItem()
            if item == nil or item:getMarketData() == nil or not(table.find(itemList, droppedWidget:getItemId())) then
                return
            end

            healingHealthWindow.config.panel.options.spellCheck:setChecked(true)
            healingHealthWindow.config.panel.options.itemCheck:setChecked(true)

            healingHealthWindow.config.panel.item:setItemId(droppedWidget:getItemId())

            healingHealthWindow.config.panel.frameBackground:setTooltip(healingHealthWindow.config.panel.item:getItem():getName())

            healingHealthWindow.config.panel.harmonyHelp:hide()
            healingHealthWindow.config.panel.harmonyValue:hide()
            healingHealthWindow.config.panel.harmonyLabel:hide()
            healingHealthWindow.config.panel.harmonyValue:clearText()
        end

        if droppedWidget.spellEntry and droppedWidget.spellId ~= nil and droppedWidget.spellId > 0 then
            local spell = g_spells.getSpellInfoById(droppedWidget.spellId)
            if spell == nil or not(table.find(spell.groups, SpellGroup.Healing)) then
                return
            end

            healingHealthWindow.config.panel.options.itemCheck:setChecked(true)
            healingHealthWindow.config.panel.options.spellCheck:setChecked(true)

            healingHealthWindow.config.panel.spell:setImageClip(g_spells.getSpellRegularImageClipById(spell.id))

            healingHealthWindow.config.panel.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')

            healingHealthWindow.config.panel.harmonyHelp:hide()
            healingHealthWindow.config.panel.harmonyValue:hide()
            healingHealthWindow.config.panel.harmonyLabel:hide()
            healingHealthWindow.config.panel.harmonyValue:clearText()

            if table.find(spell.vocations, "Monk") then
                healingHealthWindow.config.panel.harmonyHelp:show()
                healingHealthWindow.config.panel.harmonyValue:show()
                healingHealthWindow.config.panel.harmonyLabel:show()
                healingHealthWindow.config.panel.harmonyValue:setText(tostring(widget.harmony:getImageClip().x / 10))
            end
        end
    end

    healingHealthWindow.config.panel.frameBackground.onLeftClick = function()
        if healingHealthWindow.config.panel.options.itemCheck:isChecked() then
            modules.game_minibot.deferMethod('openCatcher', true)
        elseif healingHealthWindow.config.panel.options.spellCheck:isChecked() then
            modules.game_minibot.deferMethod('openCatcher', false)
        end
    end

    healingHealthWindow.config.panel.name.onTextChange = onNameTextChange

    healingHealthWindow.config.panel.save.onLeftClick = function()
        local selectedWidget = nil
        for _, c in ipairs(healingHealthWindow.priority.list:getChildren()) do
            if c.mask:isVisible() then
                selectedWidget = c
                break
            end
        end

        if selectedWidget == nil then
            return
        end

        selectedWidget.harmony:hide()

        if healingHealthWindow.config.panel.options.itemCheck:isChecked() then
            if healingHealthWindow.config.panel.item:getItem() == nil then
                return
            end

            selectedWidget.spell:hide()
            selectedWidget.item:show()
            selectedWidget.noVocation:hide()

            selectedWidget.item:setItemId(healingHealthWindow.config.panel.item:getItemId())
            selectedWidget.frameBackground:setTooltip(healingHealthWindow.config.panel.item:getItem():getName())
        elseif healingHealthWindow.config.panel.options.spellCheck:isChecked() then
            selectedWidget.spell:show()
            selectedWidget.item:hide()

            selectedWidget.spell:setImageClip(healingHealthWindow.config.panel.spell:getImageClip())

            local spell = g_spells.getSpellInfoById(g_spells.getSpellRegularIdByImageClipX(healingHealthWindow.config.panel.spell:getImageClip().x))
            if spell ~= nil then
                selectedWidget.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
                if not(modules.game_actionbar.canSpellCast(spell)) then
                    selectedWidget.noVocation:show()
                else
                    selectedWidget.noVocation:hide()
                end

                if table.find(spell.vocations, "Monk") then
                    selectedWidget.harmony:show()
                    selectedWidget.harmony:setImageClip(torect(tostring((tonumber(healingHealthWindow.config.panel.harmonyValue:getText()) or 0) * 10) .. " 0 10 39"))
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

        local min = healingHealthWindow.config.panel.minHp:getText()
        local minValue = tonumber(min) or 0
        if min == '' then
            min = '-'
        end
        selectedWidget.minHp:setText(min .. '%')

        local max = healingHealthWindow.config.panel.maxHp:getText()
        local maxValue = tonumber(max) or 0
        if max == '' then
            max = '-'
        end
        selectedWidget.maxHp:setText(max .. '%')

        if maxValue > 0 and ((selectedWidget.item:isVisible() and selectedWidget.item:getItem()) or selectedWidget.spell:isVisible()) then
            if selectedWidget.icon:isPhantom() then
                selectedWidget.icon:setPhantom(false)
                selectedWidget.icon:setImageClip(torect('25 0 25 25'))
            end
        elseif not(selectedWidget.icon:isPhantom()) then
            selectedWidget.icon:setPhantom(true)
            selectedWidget.icon:setImageClip(torect('50 0 25 25'))
        end

        healing_healthModule.saveSettings()
    end
end

function healing_healthModule.onRemoveEntry(widget)
    if not widgetAlive(widget) then
        return
    end
    pcall(function()
        widget:destroy()
    end)

    reloadListBackgrounds()

    healing_healthModule.saveSettings()
end

function healing_healthModule.validateTextPercentage(widget)
    if widget:getText() == '' then
        if widget:getId() == 'maxHp' then
            healingHealthWindow.config.panel.minHp:clearText()
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
        if healingHealthWindow.config.panel.maxHp:getText() ~= '' then
            if value > (tonumber(healingHealthWindow.config.panel.maxHp:getText()) or 0) then
                widget:setText(healingHealthWindow.config.panel.maxHp:getText())
            end
        end
    elseif widget:getId() == 'maxHp' then
        local minValue = tonumber(healingHealthWindow.config.panel.minHp:getText()) or 0
        if minValue > value then
            healingHealthWindow.config.panel.minHp:setText(value)
        end
    end

end

function healing_healthModule.onMoveUpEntry(widget)
    local index = widget:getParent():getChildIndex(widget)
    if index == 1 then
        return
    end

    widget:getParent():moveChildToIndex(widget, index - 1)
    reloadListBackgrounds()

    widget:onLeftClick()

    healing_healthModule.saveSettings()
end

function healing_healthModule.onMoveDownEntry(widget)
    local index = widget:getParent():getChildIndex(widget)
    if index == (widget:getParent():getChildCount() - 1) then
        return
    end

    widget:getParent():moveChildToIndex(widget, index + 1)
    reloadListBackgrounds()

    widget:onLeftClick()

    healing_healthModule.saveSettings()
end

function healing_healthModule.onNewEntry(widget)
    if widget.isClickFromUiScrollAreaArrow then
        return
    end

    local lastIndex = widget:getParent():getChildIndex(widget)
    local newWidget = g_ui.createWidget('MiniBotHealingHealthEntry')
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

    healing_healthModule.saveSettings()
end
