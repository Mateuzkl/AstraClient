healing_groupModule = {}

local healingGroupWindow = nil

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

function healing_groupModule.resolveRequiredMana(entry, spell)
    local configured = type(entry) == 'table' and tonumber(entry['reqmana']) or nil
    if configured ~= nil and configured > 0 then
        return configured
    end
    return spell ~= nil and (tonumber(spell.mana) or 0) or 0
end
local maxHealingGroupOnList = 20

function healing_groupModule.getSettingsListKey(selectedType)
    if selectedType == 'party' then
        return 'healing_groupParty'
    elseif selectedType == 'guild' then
        return 'healing_groupGuild'
    end
    return 'healing_group'
end

function healing_groupModule.canAddToSelectedList(settings)
    settings = type(settings) == 'table' and settings or {}
    local key = healing_groupModule.getSettingsListKey(settings['healing_groupType'])
    local list = type(settings[key]) == 'table' and settings[key] or {}
    local entries = 0
    for _ in pairs(list) do
        entries = entries + 1
    end
    return entries < maxHealingGroupOnList, key, entries
end

local itemList = {
    3152, -- Intense Healing Rune
    3160, -- Ultimate Healing Rune
}

local spellsAppend = {
    { id = 84, words = "exura sio", name = "Heal Friend" },
    { id = 242, words = "exura gran sio", name = "Nature's Embrace" },
    { id = 297, words = "exura tio sio", name = "Restore Balance" },
}

local virtueSpells = {
    297
}

function healing_groupModule.init(widget)
    healingGroupWindow = widget

    healing_groupModule.loadSettings()
end

function healing_groupModule.terminate()
    local page = healingGroupWindow
    pcall(healing_groupModule.closeCatcher)

    if healingGroupWindow == page then
        healingGroupWindow = nil
    end
end

function healing_groupModule.reloadLanguage(language)
    if language == 'ptbr' then
        healingGroupWindow.priority.priorityLabel:setText('Lista de prioridades')
        healingGroupWindow.priority.listHeader.sourceLabel.label:setText('Fonte')
        healingGroupWindow.priority.listHeader.actionLabel.label:setText('Acao')
        healingGroupWindow.config.title:setText('Configuracao')
        healingGroupWindow.config.notSelected:setText('Selecione uma entrada na lista para configurar ou criar uma nova entrada no botao +.')
        healingGroupWindow.config.panel.save:setText('Aplicar')
        healingGroupWindow.config.panel.name:setPlaceholder('Digite para pesquisar ou arraste')
        healingGroupWindow.config.panel.options.spellCheck:setText('Usar Spell')
        healingGroupWindow.config.panel.options.itemCheck:setText('Usar Item')
        healingGroupWindow.config.panel.hpHelp:setTooltip('Se sua porcentagem de vida for INFERIOR a esse valor, a acao pode ser axecutada.')
        healingGroupWindow.config.panel.target:setPlaceholder('Digite o nome do jogador')
        healingGroupWindow.config.panel.virtueOfSustain:setText('Usar Virtude')
        healingGroupWindow.config.panel.virtueOfSustain:setTextOffset('-15 -2')
        healingGroupWindow.config.panel.virtueOfSustainMask:setTooltip('Usar automaticamente a Virtue of Sustain antes de conjurar esta magia.')
        healingGroupWindow.priority.listHelp:setTooltip('Voce deve selecionar uma lista pre-definida para configurar sua prioridade de cura em grupo.')
        healingGroupWindow.priority.typeLabel:setText('Lista:')

    elseif language == 'enus' then
        healingGroupWindow.priority.priorityLabel:setText('Priority List')
        healingGroupWindow.priority.listHeader.sourceLabel.label:setText('Source')
        healingGroupWindow.priority.listHeader.actionLabel.label:setText('Action')
        healingGroupWindow.config.title:setText('Configure')
        healingGroupWindow.config.notSelected:setText('Select an entry on the list to configure or create a band-new entry on the + button.')
        healingGroupWindow.config.panel.save:setText('Apply')
        healingGroupWindow.config.panel.name:setPlaceholder('Type to search or drop on slot')
        healingGroupWindow.config.panel.options.spellCheck:setText('Spell entry')
        healingGroupWindow.config.panel.options.itemCheck:setText('Item entry')
        healingGroupWindow.config.panel.hpHelp:setTooltip('If your Health percent is LOWER than this value, the action can be triggered.')
        healingGroupWindow.config.panel.target:setPlaceholder('Type player name')
        healingGroupWindow.config.panel.virtueOfSustain:setText('Use Virtue')
        healingGroupWindow.config.panel.virtueOfSustain:setTextOffset('0 -2')
        healingGroupWindow.config.panel.virtueOfSustainMask:setTooltip('Auto use Virtue of Sustain before casting this spell.')
        healingGroupWindow.priority.listHelp:setTooltip('You must select a pre-selected list to configure your group healing priority.')
        healingGroupWindow.priority.typeLabel:setText('List:')

    end

    for _, c in ipairs(healingGroupWindow.priority.list:getChildren()) do
        if c.ignoreBackground then
            if language == 'ptbr' then
                c.text:setText('Nova Entrada')
            elseif language == 'enus' then
                c.text:setText('New Entry')
            end
        else
            if language == 'ptbr' then
                c.noVocation:setTooltip('Sua vocacao nao pode usar esta magia.')
                c.virtue:setTooltip('Voce conjurara automaticamente Virtue of Sustain antes de ativar esta magia.')
                c.iconTooptip:setTooltip('Sua entrada e invalida, por favor reconfigure-a!')
            elseif language == 'enus' then
                c.noVocation:setTooltip('Your vocation cannot use this spell.')
                c.virtue:setTooltip('You will auto-cast Virtue of Sustain before triggering this spell.')
                c.iconTooptip:setTooltip('Your entry is invalid, please reconfigure it!')
            end
        end
    end
end

function healing_groupModule.getSelectedListType()
    local settings = modules.game_minibot.getPressetSettings()
    return settings['healing_groupType'] or 'custom'
end

function healing_groupModule.reloadInternalModule()
    local settings = modules.game_minibot.getPressetSettings()
    local selectedType = settings['healing_groupType'] or 'custom'

    local list = {}
    local sList = {}
    g_minibot.setModuleToggle(18, false)
    g_minibot.setModuleToggle(19, false)
    g_minibot.setModuleToggle(20, false)
    if selectedType == 'custom' then
        sList = settings['healing_group'] or {}
        g_minibot.setModuleToggle(18, true)
    elseif selectedType == 'party' then
        sList = settings['healing_groupParty'] or {}
        g_minibot.setModuleToggle(19, true)
    elseif selectedType == 'guild' then
        sList = settings['healing_groupGuild'] or {}
        g_minibot.setModuleToggle(20, true)
    end

    for _, entry in pairs(sList) do
        table.insert(list, entry)
    end

    table.sort(list, function(a, b)
        return a.priority < b.priority
    end)

    g_minibot.resetModule(6) -- Healing Group Module type
    for _, entry in ipairs(list) do
        local internal = {
            item = tonumber(entry['item']),
            min = tonumber(entry['min']),
            max = tonumber(entry['max']),
            target = entry['target'],
            enabled = entry['enabled'],
            spell = "",
            reqmana = 0,
            area = entry['area'] or "",

            spellGroup = {},
            spellId = {},

            use = false,
            health = 0,
            mana = 0,
            hits = 0,
            harmony = 0,
            itemGroup = {},
        }

        if selectedType == 'party' or selectedType == 'guild' then
            internal.hits = 0
            if internal.target == 'Knight' then
                internal.hits = 0
            elseif internal.target == 'Paladin' then
                internal.hits = 1
            elseif internal.target == 'Monk' then
                internal.hits = 2
            elseif internal.target == 'Sorcerer' then
                internal.hits = 3
            elseif internal.target == 'Druid' then
                internal.hits = 4
            end
        end

        local canCast = true

        local spell = g_spells.getSpellInfoById(entry['spell'])
        if spell ~= nil then
            internal.spell = spell.words
            internal.reqmana = healing_groupModule.resolveRequiredMana(entry, spell)
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
            g_minibot.addModule(6, internal)
        end
    end
end

local function reloadListBackgrounds()
    local isSelected = false

    for _, c in ipairs(healingGroupWindow.priority.list:getChildren()) do
        if not(c.ignoreBackground) then
            c:setBackgroundColor('alpha')

            if c.mask:isVisible() then
                isSelected = true
            end
        end
    end

    if not(isSelected) then
        healingGroupWindow.config.notSelected:show()
        healingGroupWindow.config.panel:hide()
    else
        healingGroupWindow.config.notSelected:hide()
        healingGroupWindow.config.panel:show()
    end
end

function healing_groupModule.closeCatcher()
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

    local page = healingGroupWindow
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

function healing_groupModule.openCatcher(isItem)
    healingGroupWindow.dropDownCatcher:show()
    healingGroupWindow.dropDownCatcher.onLeftClick = healing_groupModule.closeCatcher

    local windowCatcher = modules.game_minibot.getDropDownCatcher()
    if windowCatcher ~= nil then
        windowCatcher:show()
        windowCatcher.onLeftClick = healing_groupModule.closeCatcher
    end

    healingGroupWindow.dropDownMenu:show()
    healingGroupWindow.dropDownMenuScrollBar:show()
    healingGroupWindow.dropDownMenu:destroyChildren()

    healingGroupWindow.config.panel.options:hide()

    if isItem then
        for _, item in ipairs(itemList) do
            local itemType = g_things.getThingType(item, ThingCategoryItem)
            if itemType then
                local itemWidget = g_ui.createWidget('MiniBotHealingGroupitemDropDownEntry', healingGroupWindow.dropDownMenu)
                itemWidget:setItemId(item)
                itemWidget:setTooltip(itemType:getName())

                itemWidget.onLeftClick = function()
                    healingGroupWindow.config.panel.options.spellCheck:setChecked(true)
                    healingGroupWindow.config.panel.options.itemCheck:setChecked(true)
                    healingGroupWindow.config.panel.virtueOfSustainMask:hide()
                    healingGroupWindow.config.panel.virtueOfSustain:hide()

                    healingGroupWindow.config.panel.item:setItemId(item)
                    healingGroupWindow.config.panel.frameBackground:setTooltip(healingGroupWindow.config.panel.item:getItem():getName())
                    healing_groupModule.closeCatcher()
                end
            end
        end
    else
        for _, spell in ipairs(spellsAppend) do
            local foundSpell = g_spells.getSpellInfoById(spell.id)
            if spellsAppend ~= nil then
                local spellWidget = g_ui.createWidget('MiniBotHealingGroupSpellDropDownEntry', healingGroupWindow.dropDownMenu)
                spellWidget:constructEnviorementVariables()

                if not(modules.game_actionbar.canSpellCast(foundSpell)) then
                    spellWidget.block:show()
                    spellWidget.icon:setOpacity(0.3)
                end

                spellWidget.icon:setImageClip(g_spells.getSpellRegularImageClipById(foundSpell.id))
                spellWidget:setTooltip(foundSpell.name .. '\n\'' .. foundSpell.words .. '\'')

                spellWidget.onLeftClick = function()
                    healingGroupWindow.config.panel.options.itemCheck:setChecked(true)
                    healingGroupWindow.config.panel.options.spellCheck:setChecked(true)
                    healingGroupWindow.config.panel.virtueOfSustainMask:hide()
                    healingGroupWindow.config.panel.virtueOfSustain:hide()

                    healingGroupWindow.config.panel.spell:setImageClip(g_spells.getSpellRegularImageClipById(foundSpell.id))
                    healingGroupWindow.config.panel.frameBackground:setTooltip(foundSpell.name .. '\n\'' .. foundSpell.words .. '\'')
                    healing_groupModule.closeCatcher()

                    if table.find(virtueSpells, spell.id) then
                        healingGroupWindow.config.panel.virtueOfSustainMask:show()
                        healingGroupWindow.config.panel.virtueOfSustain:show()
                    end
                end
            end
        end
    end
end

function healing_groupModule.loadSettings()
    local settings = modules.game_minibot.getPressetSettings()
    local selectedType = settings['healing_groupType'] or 'custom'
    healing_groupModule.internalChangeListType(selectedType)

    healingGroupWindow.priority.party.ignoreCallback = true
    healingGroupWindow.priority.guild.ignoreCallback = true
    healingGroupWindow.priority.custom.ignoreCallback = true

    local language = modules.game_minibot.getSettingsValue(false, 'language', 'ptbr')
    if selectedType == 'party' then
        healingGroupWindow.priority.party:setChecked(true)
        healingGroupWindow.priority.guild:setChecked(false)
        healingGroupWindow.priority.custom:setChecked(false)
        healingGroupWindow.config.panel.vocationList:show()
        if language == 'ptbr' then
            healingGroupWindow.config.panel.targetHelp:setTooltip('Escolha o nome da vocacao a ser curada.')
            healingGroupWindow.priority.listHeader.targetLabel.label:setText('Vocacao')
            healingGroupWindow.config.panel.targetLabel:setText('Vocacao:')
        elseif language == 'enus' then
            healingGroupWindow.config.panel.targetHelp:setTooltip('Chose the name of the vocation to be healed.')
            healingGroupWindow.priority.listHeader.targetLabel.label:setText('Vocation')
            healingGroupWindow.config.panel.targetLabel:setText('Vocation:')
        end
    elseif selectedType == 'guild' then
        healingGroupWindow.priority.party:setChecked(false)
        healingGroupWindow.priority.guild:setChecked(true)
        healingGroupWindow.priority.custom:setChecked(false)
        healingGroupWindow.config.panel.vocationList:show()
        if language == 'ptbr' then
            healingGroupWindow.config.panel.targetHelp:setTooltip('Escolha o nome da vocacao a ser curada.')
            healingGroupWindow.priority.listHeader.targetLabel.label:setText('Vocacao')
            healingGroupWindow.config.panel.targetLabel:setText('Vocacao:')
        elseif language == 'enus' then
            healingGroupWindow.config.panel.targetHelp:setTooltip('Chose the name of the vocation to be healed.')
            healingGroupWindow.priority.listHeader.targetLabel.label:setText('Vocation')
            healingGroupWindow.config.panel.targetLabel:setText('Vocation:')
        end
    elseif selectedType == 'custom' then
        healingGroupWindow.priority.party:setChecked(false)
        healingGroupWindow.priority.guild:setChecked(false)
        healingGroupWindow.priority.custom:setChecked(true)
        healingGroupWindow.config.panel.vocationList:hide()
        if language == 'ptbr' then
            healingGroupWindow.config.panel.targetHelp:setTooltip('Digite o nome do jogador a ser curado.')
            healingGroupWindow.priority.listHeader.targetLabel.label:setText('Jogador')
            healingGroupWindow.config.panel.targetLabel:setText('Jogador:')
        elseif language == 'enus' then
            healingGroupWindow.config.panel.targetHelp:setTooltip('Type the player name to be healed.')
            healingGroupWindow.priority.listHeader.targetLabel.label:setText('Player')
            healingGroupWindow.config.panel.targetLabel:setText('Player:')
        end
    end

    healingGroupWindow.priority.party.ignoreCallback = nil
    healingGroupWindow.priority.guild.ignoreCallback = nil
    healingGroupWindow.priority.custom.ignoreCallback = nil
end

function healing_groupModule.reloadEnabledShortcut(_, widget)
    if widget:getId() ~= 'healingGroup_gamewindow' then
        return
    end

    healingGroupWindow.priority.enabled.ignoreCallback = true
    healingGroupWindow.priority.enabled:setChecked(widget:isChecked())
    healingGroupWindow.priority.enabled.ignoreCallback = nil
end

function healing_groupModule.saveSettings()
    local localPlayer = g_game.getLocalPlayer()
    if localPlayer == nil then
        return
    end

    local settings = modules.game_minibot.getPressetSettings()
    local selectedType = settings['healing_groupType'] or 'custom'

    local values = {}
    for i, c in ipairs(healingGroupWindow.priority.list:getChildren()) do
        if not(c.ignoreBackground) then
            local value = {}
            value['priority'] = i
            value['target'] = c.target:getText()
            value['item'] = 0
            value['spell'] = 0
            value['reqmana'] = 0
            value['min'] = 0
            value['max'] = 0
            value['manaMax'] = 0
            value['manaMin'] = 0
            value['enabled'] = not(c.icon:isPhantom()) and c.icon:isChecked()
            value['area'] = ''

            if c.virtue:isVisible() then
                value['area'] = 'utura tio'
            end

            if c.hp:getText() ~= '-%' then
                value['max'] = tonumber(string.sub(c.hp:getText(), 1, -2))
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

    if selectedType == 'custom' then
        settings['healing_group'] = values
    elseif selectedType == 'party' then
        settings['healing_groupParty'] = values
    elseif selectedType == 'guild' then
        settings['healing_groupGuild'] = values
    end

    modules.game_minibot.setPressetSettings(settings)
    healing_groupModule.reloadInternalModule()
end

function healing_groupModule.onIconCheckEntry(widget)
    if widget:isPhantom() then
        widget:setImageClip(torect('50 0 25 25'))
        return
    end

    if widget:isChecked() then
        widget:setImageClip(torect('0 0 25 25'))
    else
        widget:setImageClip(torect('25 0 25 25'))
    end

    healing_groupModule.saveSettings()
end

function healing_groupModule.isTargetOnCustomList(target)
    local settings = modules.game_minibot.getPressetSettings()
    local sList = settings['healing_group']
    if sList == nil then
        return false
    end

    for _, entry in pairs(sList) do
        if entry['target'] ~= nil and entry['target']:lower() == target:lower() then
            return true
        end
    end

    return false
end

function healing_groupModule.internalInsertTarget(target)
    local selectedType = healing_groupModule.getSelectedListType()
    if selectedType ~= 'custom' then
        return
    end

    local settings = modules.game_minibot.getPressetSettings()
    local sList = settings['healing_group']
    if sList == nil then
        return false
    end

    local values = {}
    local lastPriority = 0
    for _, entry in pairs(sList) do
        table.insert(values, entry)
        lastPriority = math.max(lastPriority, entry['priority'])
    end

    if #values >= maxHealingGroupOnList then
        local language = modules.game_minibot.getSettingsValue(false, 'language', 'ptbr')
        if language == 'ptbr' then
            displayErrorBox("Assistente de Cura em Grupo", "Você ja atingiu o limite de aliados na sua lista de Cura em Grupo")
        elseif language == 'enus' then
            displayErrorBox("Group Healing Assistant", "You already reached the limit of allies on your Group Healing list.")
        end

        return
    end

    local value = {}
    value['priority'] = lastPriority + 1
    value['target'] = target
    value['item'] = 0
    value['spell'] = 0
    value['reqmana'] = 0
    value['min'] = 0
    value['max'] = 90
    value['manaMax'] = 0
    value['manaMin'] = 0
    value['enabled'] = true

    local spell = g_spells.getSpellInfoById(84)
    if spell ~= nil then
        value['spell'] = math.max(0, spell.id)
        value['reqmana'] = spell.mana

        table.insert(values, value)
        settings['healing_group'] = values
        modules.game_minibot.setPressetSettings(settings)

        healing_groupModule.reloadInternalModule()

        if healingGroupWindow ~= nil then
            healing_groupModule.loadSettings()
        end
    end
end

function healing_groupModule.internalRemoveTarget(target)
    local selectedType = healing_groupModule.getSelectedListType()
    if selectedType ~= 'custom' then
        return
    end

    local settings = modules.game_minibot.getPressetSettings()
    local sList = settings['healing_group']
    if sList == nil then
        return false
    end

    local values = {}
    for _, entry in pairs(sList) do
        if entry['target'] ~= nil and entry['target']:lower() ~= target:lower() then
            table.insert(values, entry)
        end
    end

    settings['healing_group'] = values
    modules.game_minibot.setPressetSettings(settings)

    healing_groupModule.reloadInternalModule()

    if healingGroupWindow ~= nil then
        healing_groupModule.loadSettings()
    end
end

function healing_groupModule.internalDisableTarget(target)
    local selectedType = healing_groupModule.getSelectedListType()
    if selectedType ~= 'custom' then
        return
    end

    local settings = modules.game_minibot.getPressetSettings()
    local sList = settings['healing_group']
    if sList == nil then
        return false
    end

    local values = {}
    for _, entry in pairs(sList) do
        if entry['target'] ~= nil and entry['target']:lower() == target:lower() then
            entry['enabled'] = false
        end
        table.insert(values, entry)
    end

    settings['healing_group'] = values
    modules.game_minibot.setPressetSettings(settings)

    healing_groupModule.reloadInternalModule()

    if healingGroupWindow ~= nil then
        healing_groupModule.loadSettings()
    end
end

function healing_groupModule.internalEnableTarget(target)
    local selectedType = healing_groupModule.getSelectedListType()
    if selectedType ~= 'custom' then
        return
    end

    local settings = modules.game_minibot.getPressetSettings()
    local sList = settings['healing_group']
    if sList == nil then
        return false
    end

    local values = {}
    for _, entry in pairs(sList) do
        if entry['target'] ~= nil and entry['target']:lower() == target:lower() then
            entry['enabled'] = true
        end
        table.insert(values, entry)
    end

    settings['healing_group'] = values
    modules.game_minibot.setPressetSettings(settings)

    healing_groupModule.reloadInternalModule()

    if healingGroupWindow ~= nil then
        healing_groupModule.loadSettings()
    end
end

function healing_groupModule.isTargetEnabled(target)
    local selectedType = healing_groupModule.getSelectedListType()
    if selectedType == 'custom' then
        local settings = modules.game_minibot.getPressetSettings()
        local sList = settings['healing_group']
        if sList == nil then
            return false
        end

        for _, entry in pairs(sList) do
            if entry['target'] ~= nil and entry['target']:lower() == target:lower() then
                return entry['enabled']
            end
        end
    elseif selectedType == 'party' then
        local entry = healing_groupModule.getTargetBlockFromType(selectedType, target)
        if entry ~= nil then
            return entry['enabled']
        end
    end

    return false
end

function healing_groupModule.internalChangeListType(selectedType)
    local localPlayer = g_game.getLocalPlayer()
    if localPlayer == nil then
        return
    end

    local settings = modules.game_minibot.getPressetSettings()
    settings['healing_groupType'] = selectedType
    modules.game_minibot.setPressetSettings(settings)

    healingGroupWindow.priority.list:destroyChildren()
    local list = {}

    local sList = nil
    if selectedType == 'party' then
        sList = settings['healing_groupParty'] or {}
    elseif selectedType == 'guild' then
        sList = settings['healing_groupGuild'] or {}
    elseif selectedType == 'custom' then
        sList = settings['healing_group'] or {}
    else
        return
    end

    for _, entry in pairs(sList) do
        table.insert(list, entry)
    end

    table.sort(list, function(a, b)
        return a.priority < b.priority
    end)

    for _, entry in ipairs(list) do
        local newWidget = g_ui.createWidget('MiniBotHealingGroupEntry', healingGroupWindow.priority.list)
        newWidget:constructEnviorementVariables()

        healingGroupWindow.priority.list:ensureChildVisible(newWidget)

        local isPhantom = (entry['item'] == 0 and entry['spell'] == 0) or entry['max'] == 0 or entry['target'] == ''
        if isPhantom then
            newWidget.icon:setPhantom(true)
            newWidget.icon:setImageClip(torect('50 0 25 25'))
        else
            newWidget.icon:setChecked(entry['enabled'])
        end

        newWidget.target:setText(entry['target'])
        newWidget.virtue:setVisible(entry['area'] ~= nil and entry['area'] ~= '')

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
            else
                newWidget.frameBackground:setTooltip('Unknown spell')
            end
        end

        if entry['max'] > 0 then
            newWidget.hp:setText(entry['max'] .. '%')
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

    local language = modules.game_minibot.getSettingsValue(false, 'language', 'ptbr')
    local newEntryWidget = g_ui.createWidget('MiniBotHealingGroupNewEntry', healingGroupWindow.priority.list)
    newEntryWidget:constructEnviorementVariables()
    if language == 'ptbr' then
        newEntryWidget.text:setText('Nova Entrada')
    elseif language == 'enus' then
        newEntryWidget.text:setText('New Entry')
    end

    local sSettings = settings['shortcuts'] or {}

    healingGroupWindow.priority.enabled.ignoreCallback = true
    healingGroupWindow.priority.enabled:setChecked(sSettings['healingGroup_enabled'])
    healingGroupWindow.priority.enabled.ignoreCallback = nil

    healingGroupWindow.priority.enabled.onCheckChange = function()
        if healingGroupWindow.priority.enabled.ignoreCallback then
            return
        end

        local panel = modules.game_interface.getMiniBotPanel()
        if panel ~= nil then
            local child = panel:getChildById('healingGroup_gamewindow')
            if child ~= nil then
                child.ignoreCallback = true
                child:setChecked(healingGroupWindow.priority.enabled:isChecked())
                child.ignoreCallback = nil
            end
        end

        local settings2 = modules.game_minibot.getPressetSettings()
        if settings2['shortcuts'] == nil then
            settings2['shortcuts'] = {}
        end

        settings2['shortcuts']['healingGroup_enabled'] = healingGroupWindow.priority.enabled:isChecked()
        modules.game_minibot.setPressetSettings(settings2)
        g_minibot.setModuleToggle(6, healingGroupWindow.priority.enabled:isChecked()) -- Healing Group
    end

    reloadListBackgrounds()
    healing_groupModule.reloadInternalModule()
end

function healing_groupModule.onListTypeChange(widget)
    if healingGroupWindow == nil then
        return
    end

    if widget.ignoreCallback then
        return
    end

    if not(widget:isChecked()) then
        widget.ignoreCallback = true
        widget:setChecked(true)
        widget.ignoreCallback = nil
        return
    end

    healingGroupWindow.priority.party.ignoreCallback = true
    healingGroupWindow.priority.guild.ignoreCallback = true
    healingGroupWindow.priority.custom.ignoreCallback = true

    local language = modules.game_minibot.getSettingsValue(false, 'language', 'ptbr')
    if widget:getId() == 'party' then
        healingGroupWindow.priority.guild:setChecked(false)
        healingGroupWindow.priority.custom:setChecked(false)
        healingGroupWindow.config.panel.vocationList:show()
        healing_groupModule.internalChangeListType('party')
        if language == 'ptbr' then
            healingGroupWindow.config.panel.targetHelp:setTooltip('Escolha o nome da vocacao a ser curada.')
            healingGroupWindow.priority.listHeader.targetLabel.label:setText('Vocacao')
            healingGroupWindow.config.panel.targetLabel:setText('Vocacao:')
        elseif language == 'enus' then
            healingGroupWindow.config.panel.targetHelp:setTooltip('Chose the name of the vocation to be healed.')
            healingGroupWindow.priority.listHeader.targetLabel.label:setText('Vocation')
            healingGroupWindow.config.panel.targetLabel:setText('Vocation:')
        end
    elseif widget:getId() == 'guild' then
        healingGroupWindow.priority.party:setChecked(false)
        healingGroupWindow.priority.custom:setChecked(false)
        healingGroupWindow.config.panel.vocationList:show()
        healing_groupModule.internalChangeListType('guild')
        if language == 'ptbr' then
            healingGroupWindow.config.panel.targetHelp:setTooltip('Escolha o nome da vocacao a ser curada.')
            healingGroupWindow.priority.listHeader.targetLabel.label:setText('Vocacao')
            healingGroupWindow.config.panel.targetLabel:setText('Vocacao:')
        elseif language == 'enus' then
            healingGroupWindow.config.panel.targetHelp:setTooltip('Chose the name of the vocation to be healed.')
            healingGroupWindow.priority.listHeader.targetLabel.label:setText('Vocation')
            healingGroupWindow.config.panel.targetLabel:setText('Vocation:')
        end
    elseif widget:getId() == 'custom' then
        healingGroupWindow.priority.party:setChecked(false)
        healingGroupWindow.priority.guild:setChecked(false)
        healingGroupWindow.config.panel.vocationList:hide()
        healing_groupModule.internalChangeListType('custom')
        if language == 'ptbr' then
            healingGroupWindow.config.panel.targetHelp:setTooltip('Digite o nome do jogador a ser curado.')
            healingGroupWindow.priority.listHeader.targetLabel.label:setText('Jogador')
            healingGroupWindow.config.panel.targetLabel:setText('Jogador:')
        elseif language == 'enus' then
            healingGroupWindow.config.panel.targetHelp:setTooltip('Type the player name to be healed.')
            healingGroupWindow.priority.listHeader.targetLabel.label:setText('Player')
            healingGroupWindow.config.panel.targetLabel:setText('Player:')
        end
    end

    healingGroupWindow.priority.party.ignoreCallback = nil
    healingGroupWindow.priority.guild.ignoreCallback = nil
    healingGroupWindow.priority.custom.ignoreCallback = nil
end

function healing_groupModule.onClickEntry(widget)
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

    local limit = widget:getParent():getChildCount() - 1
    if index == limit then
        widget.buttons.lower:setEnabled(false)
    else
        widget.buttons.lower:setEnabled(true)
    end

    if healingGroupWindow.config.selectedEntry == widget then
        return
    end

    healingGroupWindow.config.selectedEntry = widget

    healingGroupWindow.config.notSelected:hide()
    healingGroupWindow.config.panel:show()

    if healingGroupWindow.priority.party:isChecked() or healingGroupWindow.priority.guild:isChecked() then
        healingGroupWindow.config.panel.vocationList:setCurrentOption(widget.target:getText())
    else
        healingGroupWindow.config.panel.target:setText(widget.target:getText())
    end

    healingGroupWindow.config.panel.options.itemCheck.onCheckChange = nil
    healingGroupWindow.config.panel.options.spellCheck.onCheckChange = nil
    healingGroupWindow.config.panel.name.onTextChange = nil

    healingGroupWindow.config.panel.options.itemCheck:setChecked(false)
    healingGroupWindow.config.panel.options.spellCheck:setChecked(false)

    healingGroupWindow.config.panel.virtueOfSustain:setChecked(widget.virtue:isVisible())

    healingGroupWindow.config.panel.item:hide()
    healingGroupWindow.config.panel.spell:hide()
    healingGroupWindow.config.panel.virtueOfSustainMask:hide()
    healingGroupWindow.config.panel.virtueOfSustain:hide()

    if widget.item:isVisible() then
        healingGroupWindow.config.panel.options.itemCheck:setChecked(true)
        healingGroupWindow.config.panel.item:show()
        healingGroupWindow.config.panel.item:setItemId(widget.item:getItemId())
        healingGroupWindow.config.panel.frameBackground:setTooltip(widget.item:getItem():getName())
    end

    if widget.spell:isVisible() then
        healingGroupWindow.config.panel.options.spellCheck:setChecked(true)
        healingGroupWindow.config.panel.spell:show()
        healingGroupWindow.config.panel.spell:setImageClip(widget.spell:getImageClip())

        local spell = g_spells.getSpellInfoById(g_spells.getSpellRegularIdByImageClipX(widget.spell:getImageClip().x))
        if spell ~= nil then
            healingGroupWindow.config.panel.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')

            if table.find(virtueSpells, spell.id) then
                healingGroupWindow.config.panel.virtueOfSustainMask:show()
                healingGroupWindow.config.panel.virtueOfSustain:show()
            end
        else
            healingGroupWindow.config.panel.frameBackground:setTooltip('Unknown spell')
        end
    end

    local max = ''
    if widget.hp:getText() ~= '-%' then
        max = string.sub(widget.hp:getText(), 1, -2)
    end
    healingGroupWindow.config.panel.hp:setText(max)

    if not(widget.item:isVisible()) and not(widget.spell:isVisible()) then
        healingGroupWindow.config.panel.options.itemCheck:setChecked(true)
    end

    local function onNameTextChange()
        if healingGroupWindow.config.panel.name:getText() == '' then
            return
        end

        healingGroupWindow.config.panel.frameBackground:removeTooltip()

        healingGroupWindow.config.panel.name.onTextChange = nil
        healingGroupWindow.config.panel.name.ignoreClear = true
        if healingGroupWindow.config.panel.options.itemCheck:isChecked() then
            local items = g_things.findMarketableItemTypesByString(healingGroupWindow.config.panel.name:getText())
            if items == nil or #items == 0 then
                healingGroupWindow.config.panel.item:setItemId(0)
                healingGroupWindow.config.panel.name.onTextChange = onNameTextChange
                healingGroupWindow.config.panel.name.ignoreClear = nil
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
                healingGroupWindow.config.panel.item:setItemId(0)
                healingGroupWindow.config.panel.name.onTextChange = onNameTextChange
                healingGroupWindow.config.panel.name.ignoreClear = nil
                return
            end

            healingGroupWindow.config.panel.options.spellCheck:setChecked(true)
            healingGroupWindow.config.panel.options.itemCheck:setChecked(true)

            healingGroupWindow.config.panel.options.spellCheck.ignoreCallback = true
            healingGroupWindow.config.panel.options.spellCheck:setChecked(false)
            healingGroupWindow.config.panel.options.spellCheck.ignoreCallback = nil

            healingGroupWindow.config.panel.spell:hide()
            healingGroupWindow.config.panel.item:show()

            healingGroupWindow.config.panel.item:setItemId(found:getId())

            healingGroupWindow.config.panel.frameBackground:setTooltip(healingGroupWindow.config.panel.item:getItem():getName())
        elseif healingGroupWindow.config.panel.options.spellCheck:isChecked() then
            local strToFind = healingGroupWindow.config.panel.name:getText()
            local foundList = {}
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
                healingGroupWindow.config.panel.spell:setImageClip(torect('0 0 32 32'))
                healingGroupWindow.config.panel.name.onTextChange = onNameTextChange
                healingGroupWindow.config.panel.name.ignoreClear = nil
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
                healingGroupWindow.config.panel.spell:setImageClip(torect('0 0 32 32'))
                healingGroupWindow.config.panel.name.onTextChange = onNameTextChange
                healingGroupWindow.config.panel.name.ignoreClear = nil
                return
            end

            healingGroupWindow.config.panel.options.itemCheck:setChecked(true)
            healingGroupWindow.config.panel.options.spellCheck:setChecked(true)

            healingGroupWindow.config.panel.options.itemCheck.ignoreCallback = true
            healingGroupWindow.config.panel.options.itemCheck:setChecked(false)
            healingGroupWindow.config.panel.options.itemCheck.ignoreCallback = nil

            healingGroupWindow.config.panel.spell:show()
            healingGroupWindow.config.panel.item:hide()

            healingGroupWindow.config.panel.spell:setImageClip(g_spells.getSpellRegularImageClipById(found.id))

            healingGroupWindow.config.panel.frameBackground:setTooltip(found.name .. '\n\'' .. found.words .. '\'')
        end

        healingGroupWindow.config.panel.name.onTextChange = onNameTextChange
        healingGroupWindow.config.panel.name.ignoreClear = nil
    end

    healingGroupWindow.config.panel.options.itemCheck.onCheckChange = function(tmpWidget)
        if tmpWidget.ignoreCallback then
            return
        end

        if not(tmpWidget:isChecked()) then
            tmpWidget.ignoreCallback = true
            tmpWidget:setChecked(true)
            tmpWidget.ignoreCallback = nil
            return
        end

        healingGroupWindow.config.panel.options.spellCheck.ignoreCallback = true
        healingGroupWindow.config.panel.options.spellCheck:setChecked(false)
        healingGroupWindow.config.panel.options.spellCheck.ignoreCallback = nil

        healingGroupWindow.config.panel.spell:hide()
        healingGroupWindow.config.panel.item:show()
        healingGroupWindow.config.panel.virtueOfSustainMask:hide()
        healingGroupWindow.config.panel.virtueOfSustain:hide()

        if not(healingGroupWindow.config.panel.name.ignoreClear) then
            healingGroupWindow.config.panel.name.onTextChange = nil
            healingGroupWindow.config.panel.name:clearText()
            healingGroupWindow.config.panel.name.onTextChange = onNameTextChange
        end

        if healingGroupWindow.config.panel.item:getItem() ~= nil then
            healingGroupWindow.config.panel.frameBackground:setTooltip(healingGroupWindow.config.panel.item:getItem():getName())
        else
            healingGroupWindow.config.panel.frameBackground:removeTooltip()
        end
    end

    healingGroupWindow.config.panel.options.spellCheck.onCheckChange = function(tmpWidget)
        if tmpWidget.ignoreCallback then
            return
        end

        if not(tmpWidget:isChecked()) then
            tmpWidget.ignoreCallback = true
            tmpWidget:setChecked(true)
            tmpWidget.ignoreCallback = nil
            return
        end

        healingGroupWindow.config.panel.options.itemCheck.ignoreCallback = true
        healingGroupWindow.config.panel.options.itemCheck:setChecked(false)
        healingGroupWindow.config.panel.options.itemCheck.ignoreCallback = nil

        healingGroupWindow.config.panel.spell:show()
        healingGroupWindow.config.panel.item:hide()
        healingGroupWindow.config.panel.virtueOfSustainMask:hide()
        healingGroupWindow.config.panel.virtueOfSustain:hide()

        if not(healingGroupWindow.config.panel.name.ignoreClear) then
            healingGroupWindow.config.panel.name.onTextChange = nil
            healingGroupWindow.config.panel.name:clearText()
            healingGroupWindow.config.panel.name.onTextChange = onNameTextChange
        end

        local spell = g_spells.getSpellInfoById(g_spells.getSpellRegularIdByImageClipX(healingGroupWindow.config.panel.spell:getImageClip().x))
        if spell ~= nil then
            healingGroupWindow.config.panel.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
            if table.find(virtueSpells, spell.id) then
                healingGroupWindow.config.panel.virtueOfSustainMask:show()
                healingGroupWindow.config.panel.virtueOfSustain:show()
            end
        else
            healingGroupWindow.config.panel.frameBackground:setTooltip('Unknown spell')
        end
    end

    healingGroupWindow.config.panel.frameBackground.onDrop = function(_, droppedWidget, mousePos)
        healingGroupWindow.config.panel.frameBackground:removeTooltip()

        if droppedWidget:getClassName() == "UIItem" then
            local item = droppedWidget:getItem()
            if item == nil or item:getMarketData() == nil or not(table.find(itemList, droppedWidget:getItemId())) then
                return
            end

            healingGroupWindow.config.panel.options.spellCheck:setChecked(true)
            healingGroupWindow.config.panel.options.itemCheck:setChecked(true)

            healingGroupWindow.config.panel.item:setItemId(droppedWidget:getItemId())

            healingGroupWindow.config.panel.frameBackground:setTooltip(healingGroupWindow.config.panel.item:getItem():getName())
        end

        if droppedWidget.spellEntry and droppedWidget.spellId ~= nil and droppedWidget.spellId > 0 then
            local spell = g_spells.getSpellInfoById(droppedWidget.spellId)
            if spell == nil or not(table.find(spell.groups, SpellGroup.Healing)) then
                return
            end

            healingGroupWindow.config.panel.options.itemCheck:setChecked(true)
            healingGroupWindow.config.panel.options.spellCheck:setChecked(true)

            healingGroupWindow.config.panel.spell:setImageClip(g_spells.getSpellRegularImageClipById(spell.id))

            healingGroupWindow.config.panel.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
        end
    end

    healingGroupWindow.config.panel.frameBackground.onLeftClick = function()
        if healingGroupWindow.config.panel.options.itemCheck:isChecked() then
            modules.game_minibot.deferMethod('openCatcher', true)
        elseif healingGroupWindow.config.panel.options.spellCheck:isChecked() then
            modules.game_minibot.deferMethod('openCatcher', false)
        end
    end

    healingGroupWindow.config.panel.name.onTextChange = onNameTextChange

    healingGroupWindow.config.panel.save.onLeftClick = function()
        local selectedWidget = nil
        for _, c in ipairs(healingGroupWindow.priority.list:getChildren()) do
            if c.mask:isVisible() then
                selectedWidget = c
                break
            end
        end

        if selectedWidget == nil then
            return
        end

        selectedWidget.virtue:setVisible(healingGroupWindow.config.panel.virtueOfSustain:isVisible() and healingGroupWindow.config.panel.virtueOfSustain:isChecked())

        if healingGroupWindow.config.panel.options.itemCheck:isChecked() then
            if healingGroupWindow.config.panel.item:getItem() == nil then
                return
            end

            selectedWidget.spell:hide()
            selectedWidget.item:show()
            selectedWidget.noVocation:hide()

            selectedWidget.item:setItemId(healingGroupWindow.config.panel.item:getItemId())

            selectedWidget.frameBackground:setTooltip(healingGroupWindow.config.panel.item:getItem():getName())
        elseif healingGroupWindow.config.panel.options.spellCheck:isChecked() then
            selectedWidget.spell:show()
            selectedWidget.item:hide()

            selectedWidget.spell:setImageClip(healingGroupWindow.config.panel.spell:getImageClip())

            local spell = g_spells.getSpellInfoById(g_spells.getSpellRegularIdByImageClipX(healingGroupWindow.config.panel.spell:getImageClip().x))
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

        local hp = healingGroupWindow.config.panel.hp:getText()
        local hpValue = tonumber(hp) or 0
        if hp == '' then
            hp = '-'
        end
        selectedWidget.hp:setText(hp .. '%')

        if healingGroupWindow.priority.party:isChecked() or healingGroupWindow.priority.guild:isChecked() then
            selectedWidget.target:setText(healingGroupWindow.config.panel.vocationList:getCurrentOption().text)
        else
            selectedWidget.target:setText(healingGroupWindow.config.panel.target:getText())
        end

        if hpValue > 0 and ((selectedWidget.item:isVisible() and selectedWidget.item:getItem()) or selectedWidget.spell:isVisible()) then
            if selectedWidget.icon:isPhantom() then
                selectedWidget.icon:setPhantom(false)
                selectedWidget.icon:setImageClip(torect('25 0 25 25'))
            end
        elseif not(selectedWidget.icon:isPhantom()) then
            selectedWidget.icon:setPhantom(true)
            selectedWidget.icon:setImageClip(torect('50 0 25 25'))
        end

        healing_groupModule.saveSettings()
    end
end

function healing_groupModule.onRemoveEntry(widget)
    if not widgetAlive(widget) then
        return
    end
    pcall(function()
        widget:destroy()
    end)

    reloadListBackgrounds()

    healing_groupModule.saveSettings()
end

function healing_groupModule.getTargetBlockFromType(selectedType, target)
    local settings = modules.game_minibot.getPressetSettings()
    local tList = settings['healing_groupTargets'] or {}
    local stList = tList[selectedType] or {}
    return stList[target:lower()]
end

function healing_groupModule.setTargetBlockFromType(selectedType, target, block)
    local settings = modules.game_minibot.getPressetSettings()
    if settings['healing_groupTargets'] == nil then
        settings['healing_groupTargets'] = {}
    end

    if settings['healing_groupTargets'][selectedType] == nil then
        settings['healing_groupTargets'][selectedType] = {}
    end

    settings['healing_groupTargets'][selectedType][target:lower()] = block
    modules.game_minibot.setPressetSettings(settings)
end

function healing_groupModule.validateTextPercentage(widget)
    if widget:getText() == '' then
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
end

function healing_groupModule.onMoveUpEntry(widget)
    local index = widget:getParent():getChildIndex(widget)
    if index == 1 then
        return
    end

    widget:getParent():moveChildToIndex(widget, index - 1)
    reloadListBackgrounds()

    widget:onLeftClick()

    healing_groupModule.saveSettings()
end

function healing_groupModule.onMoveDownEntry(widget)
    local index = widget:getParent():getChildIndex(widget)
    if index == (widget:getParent():getChildCount() - 1) then
        return
    end

    widget:getParent():moveChildToIndex(widget, index + 1)
    reloadListBackgrounds()

    widget:onLeftClick()

    healing_groupModule.saveSettings()
end

function healing_groupModule.onNewEntry(widget)
    if widget.isClickFromUiScrollAreaArrow then
        return
    end

    local settings = modules.game_minibot.getPressetSettings()
    local canAdd = healing_groupModule.canAddToSelectedList(settings)
    if not canAdd then
        local language = modules.game_minibot.getSettingsValue(false, 'language', 'ptbr')
        if language == 'ptbr' then
            displayErrorBox("Assistente de Cura em Grupo", "Voce ja atingiu o limite de aliados na sua lista de Cura em Grupo")
        elseif language == 'enus' then
            displayErrorBox("Group Healing Assistant", "You already reached the limit of allies on your Group Healing list.")
        end

        return
    end

    local lastIndex = widget:getParent():getChildIndex(widget)
    local newWidget = g_ui.createWidget('MiniBotHealingGroupEntry')
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

    healing_groupModule.saveSettings()
end
