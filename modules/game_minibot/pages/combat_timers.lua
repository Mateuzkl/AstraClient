combat_timersModule = {}

function combat_timersModule.normalizeDelayText(value)
    value = type(value) == 'string' and value or ''
    if value == '' then
        value = '1'
    end
    return value, tonumber(value) or 0
end

local combatTimersWindow = nil

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
    9087, -- Carrot Cake
    29409, -- Carrot Pie
    29412, -- Chilli Con Carniphila
    11584, -- Coconut Shrimp Bake
    29411, -- Delicatessen Salad
    11587, -- Demonic Candy Ball
    9085, -- Filled Jalapeño Peppers
    9080, -- Hydra Tongue Salad
    28486, -- Lemon Cupcake
    9088, -- Northern Fishburger
    9081, -- Roasted Dragon Wings
    29408, -- Roasted Wyvern Wings
    29413, -- Svargrond Salmon Filet
    9082, -- Tropical Fried Terrorbird
    29410, -- Tropical Marinated Tiger
    9084, -- Veggie Casserole
    7439, -- Berserk Potion
    7443, -- Bullseye Potion

    36728, -- Bestiary Betterment
    36741, -- Death Amplification
    36734, -- Death Resilience
    36738, -- Earth Amplification
    36731, -- Earth Resilience
    36739, -- Energy Amplification
    36732, -- Energy Resilience
    36736, -- Fire Amplification
    36729, -- Fire Resilience
    36740, -- Holy Amplification
    36733, -- Holy Resistance
    36737, -- Ice Amplification
    36730, -- Ice Resilience
    36723, -- Kooldown-Aid
    7440, -- Mastermind Potion
    36742, -- Physical Amplification
    36735, -- Physical Resilience
    36725, -- Stamina Extension
    36724, -- Strike Enhancement
    49271, -- Transcendence Potion
    36727, -- Wealth Duple
    40611, -- Seller Pouch
    40646, -- Divine Food
    40822, -- Amplification Potion Full
    40823, -- Kooldown of Avatar
    40824, -- Special Wealth Duplex
    40825, -- Resilience Potion Full
    40838, -- Food Skill
    40839, -- Defense Scroll
    40840, -- Defense Scroll

    41060, -- Potion of Critical
    41061, -- Potion of Dodge
    41062, -- Potion of Fatal
    41063, -- Potion of Momentum
    41064, -- Potion of Speed
    41065, -- Potion of Transcendence

    41255, -- Convert Dust
    41254, -- Up Dust

    41433, -- inner force elixir
    41432, -- blade master potion
    6530, -- worn soft boots
    36726, -- charm upgrade
    40700, -- gift of life cooldown scroll
    40701, -- damage boost +10% scroll
    40702, -- damage boost +10% scroll
    40703, -- damage boost +20% scroll
    40705, -- experience +20% scroll
    40704, -- experience +10% scroll
}

local regularUseItems = {
    9087, -- Carrot Cake
    29409, -- Carrot Pie
    29412, -- Chilli Con Carniphila
    11584, -- Coconut Shrimp Bake
    29411, -- Delicatessen Salad
    11587, -- Demonic Candy Ball
    9085, -- Filled Jalapeño Peppers
    9080, -- Hydra Tongue Salad
    28486, -- Lemon Cupcake
    9088, -- Northern Fishburger
    9081, -- Roasted Dragon Wings
    29408, -- Roasted Wyvern Wings
    29413, -- Svargrond Salmon Filet
    9082, -- Tropical Fried Terrorbird
    29410, -- Tropical Marinated Tiger
    9084, -- Veggie Casserole
    7439, -- Berserk Potion
    7443, -- Bullseye Potion

    36728, -- Bestiary Betterment
    36741, -- Death Amplification
    36734, -- Death Resilience
    36738, -- Earth Amplification
    36731, -- Earth Resilience
    36739, -- Energy Amplification
    36732, -- Energy Resilience
    36736, -- Fire Amplification
    36729, -- Fire Resilience
    36740, -- Holy Amplification
    36733, -- Holy Resistance
    36737, -- Ice Amplification
    36730, -- Ice Resilience
    36723, -- Kooldown-Aid
    7440, -- Mastermind Potion
    36742, -- Physical Amplification
    36735, -- Physical Resilience
    36725, -- Stamina Extension
    36724, -- Strike Enhancement
    49271, -- Transcendence Potion
    36727, -- Wealth Duple
    40611, -- Seller Pouch
    40646, -- Divine Food
    40822, -- Amplification Potion Full
    40823, -- Kooldown of Avatar
    40824, -- Special Wealth Duplex
    40825, -- Resilience Potion Full
    40838, -- Food Skill
    40839, -- Defense Scroll
    40840, -- Defense Scroll

    41060, -- Potion of Critical
    41061, -- Potion of Dodge
    41062, -- Potion of Fatal
    41063, -- Potion of Momentum
    41064, -- Potion of Speed
    41065, -- Potion of Transcendence

    41255, -- Convert Dust
    41254, -- Up Dust

    41433, -- inner force elixir
    41432, -- blade master potion
    6530, -- worn soft boots
    36726, -- charm upgrade
    40700, -- gift of life cooldown scroll
    40701, -- damage boost +10% scroll
    40702, -- damage boost +10% scroll
    40703, -- damage boost +20% scroll
    40705, -- experience +20% scroll
    40704, -- experience +10% scroll
}

local spellsSelfPlayerParam = {
    
}

local spellsAppend = {
    { id = 45, words = "utana vid", name = "Invisibility" },
    { id = 93, words = "exeta res", name = "Challenge" },
    { id = 126, words = "utito mas sio", name = "Train Party" },
    { id = 127, words = "utamo mas sio", name = "Protect Party" },
    { id = 128, words = "utura mas sio", name = "Heal Party" },
    { id = 129, words = "utori mas sio", name = "Enchant Party" },
    { id = 132, words = "utamo tempo", name = "Protector" },
    { id = 194, words = "utevo gran res eq", name = "Knight familiar" },
    { id = 195, words = "utevo gran res sac", name = "Paladin familiar" },
    { id = 196, words = "utevo gran res ven", name = "Sorcerer familiar" },
    { id = 197, words = "utevo gran res dru", name = "Druid familiar" },
    { id = 237, words = "exeta amp res", name = "Chivalrous Challenge" },
    { id = 238, words = "exana amp res", name = "Divine Dazzle" },
    { id = 264, words = "uteta res eq", name = "Avatar of Steel" },
    { id = 265, words = "uteta res sac", name = "Avatar of Light" },
    { id = 266, words = "uteta res ven", name = "Avatar of Storm" },
    { id = 267, words = "uteta res dru", name = "Avatar of Storm" },
    { id = 283, words = "uteta res top", name = "Avatar of Balance" },
    { id = 280, words = "exori mas res", name = "Balanced Brawl" },
    { id = 278, words = "utevo mas sio", name = "Enlighten Party" },
    { id = 279, words = "utevo nia", name = "Focus Harmony" },
    { id = 281, words = "utamo tio", name = "Focus Serenity" },
    { id = 277, words = "uteta tio", name = "Mentor Other" },
    { id = 282, words = "utevo gran res tio", name = "Monk familiar" },
    { id = 274, words = "utori virtu", name = "Virtue of Harmony" },
    { id = 275, words = "utito virtu", name = "Virtue of Justice" },
    { id = 276, words = "utura tio", name = "Virtue of Sustain" },
    { id = 135, words = "utito tempo san", name = "Sharpshooter" },
    { id = 268, words = "utevo grav san", name = "Divine Empowerment" },
    { id = 133, words = "utito tempo", name = "Blood Rage" },
    { id = 243, words = "exori moe", name = "Expose Weakness" },
    { id = 244, words = "exori kor", name = "Sap Strength" },

    -- Conjure runes
    { id = 4, words = "adura gran", name = "Intense Healing Rune" },
    { id = 5, words = "adura vita", name = "Ultimate Healing Rune" },
    { id = 7, words = "adori min vis", name = "Light Magic Missile Rune" },
    { id = 8, words = "adori vis", name = "Heavy Magic Missile Rune" },
    { id = 12, words = "adeta sio", name = "Convince Creature Rune" },
    { id = 14, words = "adevo ina", name = "Chameleon Rune" },
    { id = 15, words = "adori flam", name = "Fireball Rune" },
    { id = 16, words = "adori mas flam", name = "Great Fireball Rune" },
    { id = 17, words = "adevo mas flam", name = "Fire Bomb Rune" },
    { id = 18, words = "adevo mas hur", name = "Explosion Rune" },
    { id = 21, words = "adori gran mort", name = "Sudden Death Rune" },
    { id = 25, words = "adevo grav flam", name = "Fire Field Rune" },
    { id = 26, words = "adevo grav pox", name = "Poison Field Rune" },
    { id = 27, words = "adevo grav vis", name = "Energy Field Rune" },
    { id = 28, words = "adevo mas grav flam", name = "Fire Wall Rune" },
    { id = 30, words = "adito grav", name = "Destroy Field Rune" },
    { id = 31, words = "adana pox", name = "Cure Poison Rune" },
    { id = 32, words = "adevo mas grav pox", name = "Poison Wall Rune" },
    { id = 33, words = "adevo mas grav vis", name = "Energy Wall Rune" },
    { id = 50, words = "adevo res flam", name = "Soulfire Rune" },
    { id = 54, words = "adana ani", name = "Paralyse Rune" },
    { id = 55, words = "adevo mas vis", name = "Energy Bomb Rune" },
    { id = 77, words = "adori tera", name = "Stalagmite Rune" },
    { id = 78, words = "adito tera", name = "Disintegrate Rune" },
    { id = 83, words = "adana mort", name = "Animate Dead Rune" },
    { id = 86, words = "adevo grav tera", name = "Magic Wall Rune" },
    { id = 91, words = "adevo mas pox", name = "Poison Bomb Rune" },
    { id = 94, words = "adevo grav vita", name = "Wild Growth Rune" },
    { id = 114, words = "adori frigo", name = "Icicle Rune" },
    { id = 115, words = "adori mas frigo", name = "Avalanche Rune" },
    { id = 116, words = "adori mas tera", name = "Stone Shower Rune" },
    { id = 117, words = "adori mas vis", name = "Thunderstorm Rune" },
    { id = 130, words = "adori san", name = "Holy Missile Rune" },
    { id = 49, words = "exevo con flam", name = "Conjure Explosive Arrow" },
    { id = 51, words = "exevo con", name = "Conjure Arrow" },
    { id = 92, words = "exevo gran mort", name = "Conjure Wand of Darkness" },
}

function combat_timersModule.init(widget)
    combatTimersWindow = widget

    combat_timersModule.loadSettings()
end

function combat_timersModule.terminate()
    local page = combatTimersWindow
    pcall(function()
        if not widgetAlive(page) then
            return
        end

        local invalidTag = page.config.panel.invalidTag
        if not widgetAlive(invalidTag) or invalidTag.eventTicks == nil then
            return
        end

        local event = invalidTag.eventTicks
        invalidTag.eventTicks = nil
        removeEvent(event)
        if widgetAlive(invalidTag) then
            invalidTag:clearText()
        end
    end)

    combat_timersModule.closeCatcher()

    if combatTimersWindow == page then
        combatTimersWindow = nil
    end
end

function combat_timersModule.validateTextHarmony(widget)
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

function combat_timersModule.reloadInternalModule()
    local settings = modules.game_minibot.getPressetSettings()

    local list = {}
    local sList = settings['combat_timers'] or {}
    for _, entry in pairs(sList) do
        table.insert(list, entry)
    end

    table.sort(list, function(a, b)
        return a.priority < b.priority
    end)

    g_minibot.resetModule(3) -- Combat Timers Module type
    for _, entry in ipairs(list) do
        local internal = {
            item = tonumber(entry['item']),
            use = table.find(regularUseItems, tonumber(entry['item'])),
            min = tonumber(entry['min']),
            max = tonumber(entry['max']),
            enabled = entry['enabled'],
            ignorePz = entry['ignorePz'],
            spell = "",
            reqmana = tonumber(entry['reqmana']) or 0,
            harmony =  tonumber(entry['harmony']) or 0,
            manaMin = tonumber(entry['hits']) or 0,
            manaMax = tonumber(entry['hitsMax']) or 0,

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
            g_minibot.addModule(3, internal)
        end
    end
end

local function reloadListBackgrounds()
    local isSelected = false

    for _, c in ipairs(combatTimersWindow.priority.list:getChildren()) do
        if not(c.ignoreBackground) then
            c:setBackgroundColor('alpha')

            if c.mask:isVisible() then
                isSelected = true
            end
        end
    end

    if not(isSelected) then
        combatTimersWindow.config.notSelected:show()
        combatTimersWindow.config.panel:hide()
    else
        combatTimersWindow.config.notSelected:hide()
        combatTimersWindow.config.panel:show()
    end
end

function combat_timersModule.reloadLanguage(language)
    if language == 'ptbr' then
        combatTimersWindow.priority.priorityLabel:setText('Lista de prioridades')
        combatTimersWindow.priority.listHeader.sourceLabel.label:setText('Fonte')
        combatTimersWindow.priority.listHeader.actionLabel.label:setText('Acao')
        combatTimersWindow.priority.listHeader.monstersLabel.label:setText('Monstros')
        combatTimersWindow.config.title:setText('Configuracao')
        combatTimersWindow.config.notSelected:setText('Selecione uma entrada na lista para configurar ou criar uma nova entrada no botao +.')
        combatTimersWindow.config.panel.save:setText('Aplicar')
        combatTimersWindow.config.panel.ignoreProtection:setText('Ignorar em PZ')
        combatTimersWindow.config.panel.ignoreProtection:setTextOffset('-10 -2')
        combatTimersWindow.config.panel.ignoreProteconMask:setMarginLeft(-10)
        combatTimersWindow.config.panel.name:setPlaceholder('Digite para pesquisar ou arraste')
        combatTimersWindow.config.panel.options.spellCheck:setText('Usar Spell')
        combatTimersWindow.config.panel.options.itemCheck:setText('Usar Item')
        combatTimersWindow.config.panel.delayHelp:setTooltip('Voce pode definir um tempo de atraso nas ativacoes para evitar o uso desnecessario de spells/itens.')
        combatTimersWindow.config.panel.harmonyHelp:setTooltip('Voce pode definir um nivel minimo de Harmonia para ativar o uso desta spell/item.')
        combatTimersWindow.config.panel.harmonyLabel:setText('Harmonia:')
        combatTimersWindow.config.panel.creaturesHelp:setTooltip('Voce pode definir uma quantidade minimo e maximo de Monstros para ativar o uso desta spell/item.')
        combatTimersWindow.config.panel.creaturesLabel:setText('Monstros na tela:')

    elseif language == 'enus' then
        combatTimersWindow.priority.priorityLabel:setText('Priority List')
        combatTimersWindow.priority.listHeader.sourceLabel.label:setText('Source')
        combatTimersWindow.priority.listHeader.actionLabel.label:setText('Action')
        combatTimersWindow.priority.listHeader.monstersLabel.label:setText('Monsters')
        combatTimersWindow.config.title:setText('Configure')
        combatTimersWindow.config.notSelected:setText('Select an entry on the list to configure or create a band-new entry on the + button.')
        combatTimersWindow.config.panel.save:setText('Apply')
        combatTimersWindow.config.panel.ignoreProtection:setText('Ignore on PZ')
        combatTimersWindow.config.panel.ignoreProtection:setTextOffset('0 -2')
        combatTimersWindow.config.panel.ignoreProteconMask:setMarginLeft(0)
        combatTimersWindow.config.panel.name:setPlaceholder('Type to search or drop on slot')
        combatTimersWindow.config.panel.options.spellCheck:setText('Spell entry')
        combatTimersWindow.config.panel.options.itemCheck:setText('Item entry')
        combatTimersWindow.config.panel.delayHelp:setTooltip('You can set a delay time into casts, to avoid unnecessary spell/item usage.')
        combatTimersWindow.config.panel.harmonyHelp:setTooltip('You can set a minimum Harmony level to trigger this item/spell usage.')
        combatTimersWindow.config.panel.harmonyLabel:setText('Harmony:')
        combatTimersWindow.config.panel.creaturesHelp:setTooltip('You can set a minimum and maximum amount of Monsters to trigger this item/spell usage.')
        combatTimersWindow.config.panel.creaturesLabel:setText('Monsters on screen:')

    end

    for _, c in ipairs(combatTimersWindow.priority.list:getChildren()) do
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
                c.ignorePz:setTooltip('Esta acao sera ignorada quando estiver dentro de uma Zona de Protecao.')
            elseif language == 'enus' then
                c.harmony:setTooltip('Your selected Harmony requirement.')
                c.noVocation:setTooltip('Your vocation cannot use this spell.')
                c.ignorePz:setTooltip('This action will be ignored when inside of a Protection Zone.')
            end
        end
    end
end

function combat_timersModule.closeCatcher()
    local windowCatcher = modules.game_minibot.getDropDownCatcher()
    if widgetAlive(windowCatcher) then
        pcall(function()
            windowCatcher:hide()
            windowCatcher.onLeftClick = nil
        end)
    end

    local page = combatTimersWindow
    if not widgetAlive(page) then
        return
    end

    pcall(function()
        if widgetAlive(page.config.panel.options) then
            page.config.panel.options:show()
        end
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

function combat_timersModule.openCatcher(isItem)
    combatTimersWindow.dropDownCatcher:show()
    combatTimersWindow.dropDownCatcher.onLeftClick = combat_timersModule.closeCatcher

    local windowCatcher = modules.game_minibot.getDropDownCatcher()
    if windowCatcher ~= nil then
        windowCatcher:show()
        windowCatcher.onLeftClick = combat_timersModule.closeCatcher
    end

    combatTimersWindow.dropDownMenu:show()
    combatTimersWindow.dropDownMenuScrollBar:show()
    combatTimersWindow.dropDownMenu:destroyChildren()

    combatTimersWindow.config.panel.options:hide()

    if isItem then
        for _, item in ipairs(itemList) do
            local itemType = g_things.getThingType(item, ThingCategoryItem)
            if itemType then
                local itemWidget = g_ui.createWidget('MiniBotCombatTimersitemDropDownEntry', combatTimersWindow.dropDownMenu)
                itemWidget:setItemId(item)
                itemWidget:setTooltip(itemType:getName())

                itemWidget.onLeftClick = function()
                    combatTimersWindow.config.panel.options.spellCheck:setChecked(true)
                    combatTimersWindow.config.panel.options.itemCheck:setChecked(true)

                    combatTimersWindow.config.panel.item:setItemId(item)
                    combatTimersWindow.config.panel.frameBackground:setTooltip(combatTimersWindow.config.panel.item:getItem():getName())
                    combat_timersModule.closeCatcher()
                end
            end
        end
    else
        for _, spell in ipairs(spellsAppend) do
            local foundSpell = g_spells.getSpellInfoById(spell.id)
            if spellsAppend ~= nil then
                local spellWidget = g_ui.createWidget('MiniBotCombatTimersSpellDropDownEntry', combatTimersWindow.dropDownMenu)
                spellWidget:constructEnviorementVariables()

                if not(modules.game_actionbar.canSpellCast(foundSpell)) then
                    spellWidget.block:show()
                    spellWidget.icon:setOpacity(0.3)
                end

                spellWidget.icon:setImageClip(g_spells.getSpellRegularImageClipById(foundSpell.id))
                spellWidget:setTooltip(foundSpell.name .. '\n\'' .. foundSpell.words .. '\'')

                spellWidget.onLeftClick = function()
                    combatTimersWindow.config.panel.options.itemCheck:setChecked(true)
                    combatTimersWindow.config.panel.options.spellCheck:setChecked(true)

                    combatTimersWindow.config.panel.spell:setImageClip(g_spells.getSpellRegularImageClipById(foundSpell.id))
                    combatTimersWindow.config.panel.frameBackground:setTooltip(foundSpell.name .. '\n\'' .. foundSpell.words .. '\'')
                    combat_timersModule.closeCatcher()
                end
            end
        end
    end
end

function combat_timersModule.loadSettings()
    local settings = modules.game_minibot.getPressetSettings()

    local list = {}
    local sList = settings['combat_timers'] or {}
    local sSettings = settings['shortcuts'] or {}
    for _, entry in pairs(sList) do
        table.insert(list, entry)
    end

    table.sort(list, function(a, b)
        return a.priority < b.priority
    end)

    local newEntryButton = combatTimersWindow.priority.list:getChildByIndex(1)
    for _, entry in ipairs(list) do
        local newWidget = g_ui.createWidget('MiniBotCombatTimersEntry')
        newWidget:constructEnviorementVariables()

        combatTimersWindow.priority.list:insertChild(combatTimersWindow.priority.list:getChildIndex(newEntryButton), newWidget)
        combatTimersWindow.priority.list:ensureChildVisible(newWidget)

        local isPhantom = (entry['item'] == 0 and entry['spell'] == 0) or entry['max'] == 0
        if isPhantom then
            newWidget.icon:setPhantom(true)
            newWidget.icon:setImageClip(torect('50 0 25 25'))
        else
            newWidget.icon:setChecked(entry['enabled'])
        end

        local harmony = entry['harmony'] or 0
        if harmony > 0 then
            newWidget.harmony:show()
            newWidget.harmony:setImageClip(torect(tostring(harmony * 10) .. " 0 10 39"))
        end

        newWidget.ignorePz:setVisible(entry['ignorePz'])
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

        if entry['max'] > 0 then
            newWidget.maxDelay:setText(entry['max'] .. 's')
        end

        if entry['hits'] ~= nil and entry['hits'] > 0 then
            newWidget.creaturesValue:setText('Min: ' .. entry['hits'])
        end

        if entry['hitsMax'] ~= nil and entry['hitsMax'] > 0 then
            newWidget.creaturesMaxValue:setText('Max: ' .. entry['hitsMax'])
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

        newWidget.ignorePz.onLeftClick = function()
            modules.game_minibot.callMethod('onClickEntry', newWidget.ignorePz:getParent())
        end

        newWidget.frameBackground.onLeftClick = function()
            modules.game_minibot.callMethod('onClickEntry', newWidget.frameBackground:getParent())
        end
    end

    combatTimersWindow.priority.enabled.ignoreCallback = true
    combatTimersWindow.priority.enabled:setChecked(sSettings['combatTimers_enabled'])
    combatTimersWindow.priority.enabled.ignoreCallback = nil

    combatTimersWindow.priority.enabled.onCheckChange = function()
        if combatTimersWindow.priority.enabled.ignoreCallback then
            return
        end

        local panel = modules.game_interface.getMiniBotPanel()
        if panel ~= nil then
            local child = panel:getChildById('combatTimer_gamewindow')
            if child ~= nil then
                child.ignoreCallback = true
                child:setChecked(combatTimersWindow.priority.enabled:isChecked())
                child.ignoreCallback = nil
            end
        end

        local settings2 = modules.game_minibot.getPressetSettings()
        if settings2['shortcuts'] == nil then
            settings2['shortcuts'] = {}
        end

        settings2['shortcuts']['combatTimers_enabled'] = combatTimersWindow.priority.enabled:isChecked()
        modules.game_minibot.setPressetSettings(settings2)
        g_minibot.setModuleToggle(3, combatTimersWindow.priority.enabled:isChecked()) -- Combat Timers
    end

    reloadListBackgrounds()
end

function combat_timersModule.reloadEnabledShortcut(_, widget)
    if widget:getId() ~= 'combatTimer_gamewindow' then
        return
    end

    combatTimersWindow.priority.enabled.ignoreCallback = true
    combatTimersWindow.priority.enabled:setChecked(widget:isChecked())
    combatTimersWindow.priority.enabled.ignoreCallback = nil
end

function combat_timersModule.saveSettings()
    local settings = modules.game_minibot.getPressetSettings()

    local values = {}
    for i, c in ipairs(combatTimersWindow.priority.list:getChildren()) do
        if not(c.ignoreBackground) then
            local value = {}
            value['priority'] = i
            value['item'] = 0
            value['spell'] = 0
            value['reqmana'] = 0
            value['min'] = 0
            value['max'] = 1
            value['manaMax'] = 0
            value['manaMin'] = 0
            value['enabled'] = not(c.icon:isPhantom()) and c.icon:isChecked()
            value['ignorePz'] = c.ignorePz:isVisible()
            value['harmony'] = c.harmony:isVisible() and (c.harmony:getImageClip().x / 10) or 0
            value['hits'] = 0

            if c.maxDelay:getText() ~= '1s' then
                value['max'] = tonumber(string.sub(c.maxDelay:getText(), 1, -2))
            end

            if c.creaturesValue:getText() ~= 'Min: 0' then
                value['hits'] = tonumber(string.sub(c.creaturesValue:getText(), 6, -1))
            end

            if c.creaturesMaxValue:getText() ~= 'Max: -' then
                value['hitsMax'] = tonumber(string.sub(c.creaturesMaxValue:getText(), 6, -1))
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

    settings['combat_timers'] = values
    modules.game_minibot.setPressetSettings(settings)
    combat_timersModule.reloadInternalModule()
end

function combat_timersModule.onIconCheckEntry(widget)
    if widget:isPhantom() then
        widget:setImageClip(torect('50 0 25 25'))
        return
    end

    if widget:isChecked() then
        widget:setImageClip(torect('0 0 25 25'))
    else
        widget:setImageClip(torect('25 0 25 25'))
    end

    combat_timersModule.saveSettings()
end

function combat_timersModule.onClickEntry(widget)
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

    if combatTimersWindow.config.selectedEntry == widget then
        return
    end

    combatTimersWindow.config.selectedEntry = widget

    combatTimersWindow.config.notSelected:hide()
    combatTimersWindow.config.panel:show()

    combatTimersWindow.config.panel.harmonyValue:clearText()
    local harmony = widget.harmony:getImageClip().x / 10
    if harmony > 0 then
        combatTimersWindow.config.panel.harmonyValue:setText(tostring(harmony))
    end

    combatTimersWindow.config.panel.creaturesValue:clearText()
    combatTimersWindow.config.panel.creaturesMaxValue:clearText()

    combatTimersWindow.config.panel.ignoreProtection:setChecked(widget.ignorePz:isVisible())

    combatTimersWindow.config.panel.options.itemCheck.onCheckChange = nil
    combatTimersWindow.config.panel.options.spellCheck.onCheckChange = nil
    combatTimersWindow.config.panel.name.onTextChange = nil

    combatTimersWindow.config.panel.options.itemCheck:setChecked(false)
    combatTimersWindow.config.panel.options.spellCheck:setChecked(false)

    combatTimersWindow.config.panel.item:hide()
    combatTimersWindow.config.panel.spell:hide()

    if widget.item:isVisible() then
        combatTimersWindow.config.panel.options.itemCheck:setChecked(true)
        combatTimersWindow.config.panel.item:show()
        combatTimersWindow.config.panel.item:setItemId(widget.item:getItemId())
        combatTimersWindow.config.panel.frameBackground:setTooltip(widget.item:getItem():getName())
    end

    if widget.spell:isVisible() then
        combatTimersWindow.config.panel.options.spellCheck:setChecked(true)
        combatTimersWindow.config.panel.spell:show()
        combatTimersWindow.config.panel.spell:setImageClip(widget.spell:getImageClip())

        local spell = g_spells.getSpellInfoById(g_spells.getSpellRegularIdByImageClipX(widget.spell:getImageClip().x))
        if spell ~= nil then
            combatTimersWindow.config.panel.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
        else
            combatTimersWindow.config.panel.frameBackground:setTooltip('Unknown spell')
        end
    end

    local max = ''
    if widget.maxDelay:getText() ~= '1s' then
        max = string.sub(widget.maxDelay:getText(), 1, -2)
    end
    combatTimersWindow.config.panel.maxDelay:setText(max)

    max = ''
    if widget.creaturesValue:getText() ~= 'Min: 0' then
        max = string.sub(widget.creaturesValue:getText(), 6, -1)
    end
    combatTimersWindow.config.panel.creaturesValue:setText(max)

    max = ''
    if widget.creaturesMaxValue:getText() ~= 'Max: -' then
        max = string.sub(widget.creaturesMaxValue:getText(), 6, -1)
    end
    combatTimersWindow.config.panel.creaturesMaxValue:setText(max)

    if not(widget.item:isVisible()) and not(widget.spell:isVisible()) then
        combatTimersWindow.config.panel.options.itemCheck:setChecked(true)
    end

    if combatTimersWindow.config.panel.invalidTag.eventTicks ~= nil then
        removeEvent(combatTimersWindow.config.panel.invalidTag.eventTicks)
        combatTimersWindow.config.panel.invalidTag.eventTicks = nil
        combatTimersWindow.config.panel.invalidTag:clearText()
    end

    local function onNameTextChange()
        if combatTimersWindow.config.panel.name:getText() == '' then
            return
        end

        combatTimersWindow.config.panel.frameBackground:removeTooltip()

        combatTimersWindow.config.panel.name.onTextChange = nil
        combatTimersWindow.config.panel.name.ignoreClear = true
        if combatTimersWindow.config.panel.options.itemCheck:isChecked() then
            local items = g_things.findMarketableItemTypesByString(combatTimersWindow.config.panel.name:getText())
            if items == nil or #items == 0 then
                combatTimersWindow.config.panel.item:setItemId(0)
                combatTimersWindow.config.panel.name.onTextChange = onNameTextChange
                combatTimersWindow.config.panel.name.ignoreClear = nil
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
                combatTimersWindow.config.panel.item:setItemId(0)
                combatTimersWindow.config.panel.name.onTextChange = onNameTextChange
                combatTimersWindow.config.panel.name.ignoreClear = nil
                return
            end

            combatTimersWindow.config.panel.options.spellCheck:setChecked(true)
            combatTimersWindow.config.panel.options.itemCheck:setChecked(true)

            combatTimersWindow.config.panel.options.spellCheck.ignoreCallback = true
            combatTimersWindow.config.panel.options.spellCheck:setChecked(false)
            combatTimersWindow.config.panel.options.spellCheck.ignoreCallback = nil

            combatTimersWindow.config.panel.spell:hide()
            combatTimersWindow.config.panel.item:show()

            if combatTimersWindow.config.panel.invalidTag.eventTicks ~= nil then
                removeEvent(combatTimersWindow.config.panel.invalidTag.eventTicks)
                combatTimersWindow.config.panel.invalidTag.eventTicks = nil
                combatTimersWindow.config.panel.invalidTag:clearText()
            end

            combatTimersWindow.config.panel.item:setItemId(found:getId())

            combatTimersWindow.config.panel.frameBackground:setTooltip(combatTimersWindow.config.panel.item:getItem():getName())
        elseif combatTimersWindow.config.panel.options.spellCheck:isChecked() then
            local strToFind = combatTimersWindow.config.panel.name:getText()
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
                combatTimersWindow.config.panel.spell:setImageClip(torect('0 0 32 32'))
                combatTimersWindow.config.panel.name.onTextChange = onNameTextChange
                combatTimersWindow.config.panel.name.ignoreClear = nil
                return
            end

            local found = nil
            for _, spell in ipairs(spells) do
                if found == nil or (#(spell.name) < #(found.name)) then
                    found = spell
                end
            end

            if found == nil then
                combatTimersWindow.config.panel.spell:setImageClip(torect('0 0 32 32'))
                combatTimersWindow.config.panel.name.onTextChange = onNameTextChange
                combatTimersWindow.config.panel.name.ignoreClear = nil
                return
            end

            if combatTimersWindow.config.panel.invalidTag.eventTicks ~= nil then
                removeEvent(combatTimersWindow.config.panel.invalidTag.eventTicks)
                combatTimersWindow.config.panel.invalidTag.eventTicks = nil
                combatTimersWindow.config.panel.invalidTag:clearText()
            end

            combatTimersWindow.config.panel.options.itemCheck:setChecked(true)
            combatTimersWindow.config.panel.options.spellCheck:setChecked(true)

            combatTimersWindow.config.panel.options.itemCheck.ignoreCallback = true
            combatTimersWindow.config.panel.options.itemCheck:setChecked(false)
            combatTimersWindow.config.panel.options.itemCheck.ignoreCallback = nil

            combatTimersWindow.config.panel.spell:show()
            combatTimersWindow.config.panel.item:hide()

            combatTimersWindow.config.panel.spell:setImageClip(g_spells.getSpellRegularImageClipById(found.id))

            combatTimersWindow.config.panel.frameBackground:setTooltip(found.name .. '\n\'' .. found.words .. '\'')
        end

        combatTimersWindow.config.panel.name.onTextChange = onNameTextChange
        combatTimersWindow.config.panel.name.ignoreClear = nil
    end

    combatTimersWindow.config.panel.options.itemCheck.onCheckChange = function(tmpWidget)
        if tmpWidget.ignoreCallback then
            return
        end

        if not(tmpWidget:isChecked()) then
            tmpWidget.ignoreCallback = true
            tmpWidget:setChecked(true)
            tmpWidget.ignoreCallback = nil
            return
        end

        combatTimersWindow.config.panel.options.spellCheck.ignoreCallback = true
        combatTimersWindow.config.panel.options.spellCheck:setChecked(false)
        combatTimersWindow.config.panel.options.spellCheck.ignoreCallback = nil

        combatTimersWindow.config.panel.spell:hide()
        combatTimersWindow.config.panel.item:show()

        if not(combatTimersWindow.config.panel.name.ignoreClear) then
            combatTimersWindow.config.panel.name.onTextChange = nil
            combatTimersWindow.config.panel.name:clearText()
            combatTimersWindow.config.panel.name.onTextChange = onNameTextChange
        end

        if combatTimersWindow.config.panel.item:getItem() ~= nil then
            combatTimersWindow.config.panel.frameBackground:setTooltip(combatTimersWindow.config.panel.item:getItem():getName())
        else
            combatTimersWindow.config.panel.frameBackground:removeTooltip()
        end
    end

    combatTimersWindow.config.panel.options.spellCheck.onCheckChange = function(tmpWidget)
        if tmpWidget.ignoreCallback then
            return
        end

        if not(tmpWidget:isChecked()) then
            tmpWidget.ignoreCallback = true
            tmpWidget:setChecked(true)
            tmpWidget.ignoreCallback = nil
            return
        end

        combatTimersWindow.config.panel.options.itemCheck.ignoreCallback = true
        combatTimersWindow.config.panel.options.itemCheck:setChecked(false)
        combatTimersWindow.config.panel.options.itemCheck.ignoreCallback = nil

        combatTimersWindow.config.panel.spell:show()
        combatTimersWindow.config.panel.item:hide()

        if not(combatTimersWindow.config.panel.name.ignoreClear) then
            combatTimersWindow.config.panel.name.onTextChange = nil
            combatTimersWindow.config.panel.name:clearText()
            combatTimersWindow.config.panel.name.onTextChange = onNameTextChange
        end

        local spell = g_spells.getSpellInfoById(g_spells.getSpellRegularIdByImageClipX(combatTimersWindow.config.panel.spell:getImageClip().x))
        if spell ~= nil then
            combatTimersWindow.config.panel.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
        else
            combatTimersWindow.config.panel.frameBackground:setTooltip('Unknown spell')
        end
    end

    combatTimersWindow.config.panel.frameBackground.onDrop = function(_, droppedWidget, mousePos)
        combatTimersWindow.config.panel.frameBackground:removeTooltip()

        if droppedWidget:getClassName() == "UIItem" then
            local item = droppedWidget:getItem()
            if item == nil or item:getMarketData() == nil or not(table.find(itemList, droppedWidget:getItemId())) then
                return
            end

            combatTimersWindow.config.panel.options.spellCheck:setChecked(true)
            combatTimersWindow.config.panel.options.itemCheck:setChecked(true)

            combatTimersWindow.config.panel.item:setItemId(droppedWidget:getItemId())

            combatTimersWindow.config.panel.frameBackground:setTooltip(combatTimersWindow.config.panel.item:getItem():getName())
        end

        if droppedWidget.spellEntry and droppedWidget.spellId ~= nil and droppedWidget.spellId > 0 then
            local spell = g_spells.getSpellInfoById(droppedWidget.spellId)
            if spell == nil then
                return
            end

            combatTimersWindow.config.panel.options.itemCheck:setChecked(true)
            combatTimersWindow.config.panel.options.spellCheck:setChecked(true)

            combatTimersWindow.config.panel.spell:setImageClip(g_spells.getSpellRegularImageClipById(spell.id))

            combatTimersWindow.config.panel.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
        end
    end

    combatTimersWindow.config.panel.frameBackground.onLeftClick = function()
        if combatTimersWindow.config.panel.options.itemCheck:isChecked() then
            modules.game_minibot.deferMethod('openCatcher', true)
        elseif combatTimersWindow.config.panel.options.spellCheck:isChecked() then
            modules.game_minibot.deferMethod('openCatcher', false)
        end
    end

    combatTimersWindow.config.panel.name.onTextChange = onNameTextChange

    combatTimersWindow.config.panel.save.onLeftClick = function()
        local selectedWidget = nil
        for _, c in ipairs(combatTimersWindow.priority.list:getChildren()) do
            if c.mask:isVisible() then
                selectedWidget = c
                break
            end
        end

        if selectedWidget == nil then
            return
        end

        selectedWidget.harmony:hide()
        local harmony = tonumber(combatTimersWindow.config.panel.harmonyValue:getText()) or 0
        if harmony > 0 then
            selectedWidget.harmony:show()
            selectedWidget.harmony:setImageClip(torect(tostring(harmony * 10) .. " 0 10 39"))
        end

        if combatTimersWindow.config.panel.options.itemCheck:isChecked() then
            if combatTimersWindow.config.panel.item:getItem() == nil then
                return
            end

            selectedWidget.spell:hide()
            selectedWidget.item:show()
            selectedWidget.noVocation:hide()

            selectedWidget.item:setItemId(combatTimersWindow.config.panel.item:getItemId())
            selectedWidget.frameBackground:setTooltip(combatTimersWindow.config.panel.item:getItem():getName())
            selectedWidget.ignorePz:setVisible(combatTimersWindow.config.panel.ignoreProtection:isChecked())
        elseif combatTimersWindow.config.panel.options.spellCheck:isChecked() then
            selectedWidget.spell:show()
            selectedWidget.item:hide()
            selectedWidget.ignorePz:setVisible(combatTimersWindow.config.panel.ignoreProtection:isChecked())

            selectedWidget.spell:setImageClip(combatTimersWindow.config.panel.spell:getImageClip())

            local spell = g_spells.getSpellInfoById(g_spells.getSpellRegularIdByImageClipX(combatTimersWindow.config.panel.spell:getImageClip().x))
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
            selectedWidget.ignorePz:setVisible(false)
            return
        end

        local max, maxValue = combat_timersModule.normalizeDelayText(
            combatTimersWindow.config.panel.maxDelay:getText())
        selectedWidget.maxDelay:setText(max .. 's')

        local creaturesStr = combatTimersWindow.config.panel.creaturesValue:getText()
        if creaturesStr == '' then
            creaturesStr = '0'
        end
        selectedWidget.creaturesValue:setText('Min: ' .. creaturesStr)

        creaturesStr = combatTimersWindow.config.panel.creaturesMaxValue:getText()
        if creaturesStr == '' or creaturesStr == '0' then
            creaturesStr = '-'
        end
        selectedWidget.creaturesMaxValue:setText('Max: ' .. creaturesStr)

        if maxValue > 0 and ((selectedWidget.item:isVisible() and selectedWidget.item:getItem()) or selectedWidget.spell:isVisible()) then
            if selectedWidget.icon:isPhantom() then
                selectedWidget.icon:setPhantom(false)
                selectedWidget.icon:setImageClip(torect('25 0 25 25'))
            end
        elseif not(selectedWidget.icon:isPhantom()) then
            selectedWidget.icon:setPhantom(true)
            selectedWidget.icon:setImageClip(torect('50 0 25 25'))
        end

        combat_timersModule.saveSettings()
    end
end

function combat_timersModule.onRemoveEntry(widget)
    if not widgetAlive(widget) then
        return
    end
    pcall(function()
        widget:destroy()
    end)

    reloadListBackgrounds()

    combat_timersModule.saveSettings()
end

function combat_timersModule.onMoveUpEntry(widget)
    local index = widget:getParent():getChildIndex(widget)
    if index == 1 then
        return
    end

    widget:getParent():moveChildToIndex(widget, index - 1)
    reloadListBackgrounds()

    widget:onLeftClick()

    combat_timersModule.saveSettings()
end

function combat_timersModule.onMoveDownEntry(widget)
    local index = widget:getParent():getChildIndex(widget)
    if index == (widget:getParent():getChildCount() - 1) then
        return
    end

    widget:getParent():moveChildToIndex(widget, index + 1)
    reloadListBackgrounds()

    widget:onLeftClick()

    combat_timersModule.saveSettings()
end

function combat_timersModule.onNewEntry(widget)
    if widget.isClickFromUiScrollAreaArrow then
        return
    end

    local lastIndex = widget:getParent():getChildIndex(widget)
    local newWidget = g_ui.createWidget('MiniBotCombatTimersEntry')
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

    combat_timersModule.saveSettings()
end
