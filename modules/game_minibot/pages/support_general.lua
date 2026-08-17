support_generalModule = {}

local supportGeneralWindow = nil

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

local hasteSpells = {
    { id = 6, words = "utani hur", name = "Haste" },
    { id = 39, words = "utani gran hur", name = "Strong Haste" },
    { id = 134, words = "utamo tempo san", name = "Swift Foot" },
    { id = 131, words = "utani tempo hur", name = "Charge" },
}

local foodAppend = {
    
}

local trainingWeapons = {
    40636, -- Daily Exercise Axe
    35280, -- Durable Exercise Axe
    40856, -- Epic Exercise Axe
    28553, -- Exercise Axe
    35286, -- Lasting Exercise Axe
    40863, -- Legend Exercise Axe
    40820, -- Mystic Exercise Axe
    40630, -- Special Exercise Axe
    40687, -- Weak Exercise Axe

    40637, -- Daily Exercise Bow
    35282, -- Durable Exercise Bow
    40857, -- Epic Exercise Bow
    28555, -- Exercise Bow
    35288, -- Lasting Exercise Bow
    40864, -- Legend Exercise Bow
    40821, -- Mystic Exercise Bow
    40632, -- Special Exercise Bow
    40688, -- Weak Exercise Bow

    40638, -- Daily Exercise Club
    35281, -- Durable Exercise Club
    40851, -- Epic Exercise Club
    28554, -- Exercise Club
    35287, -- Lasting Exercise Club
    40858, -- Legend Exercise Club
    40815, -- Mystic Exercise Club
    40631, -- Special Exercise Club
    40689, -- Weak Exercise Club

    40639, -- Daily Exercise Rod
    35283, -- Durable Exercise Rod
    40852, -- Epic Exercise Rod
    28556, -- Exercise Rod
    35289, -- Lasting Exercise Rod
    40859, -- Legend Exercise Rod
    40816, -- Mystic Exercise Rod
    40633, -- Special Exercise Rod
    40690, -- Weak Exercise Rod

    40640, -- Daily Exercise Shield
    44066, -- Durable Exercise Shield
    40853, -- Epic Exercise Shield
    44065, -- Exercise Shield
    44067, -- Lasting Exercise Shield
    40860, -- Legend Exercise Shield
    40817, -- Mystic Exercise Shield
    40635, -- Special Exercise Shield
    40691, -- Weak Exercise Shield

    40641, -- Daily Exercise Sword
    35279, -- Durable Exercise Sword
    40854, -- Epic Exercise Sword
    28552, -- Exercise Sword
    35285, -- Lasting Exercise Sword
    40861, -- Legend Exercise Sword
    40818, -- Mystic Exercise Sword
    40629, -- Special Exercise Sword
    40692, -- Weak Exercise Sword

    40642, -- Daily Exercise Wand
    35284, -- Durable Exercise Wand
    40855, -- Epic Exercise Wand
    28557, -- Exercise Wand
    35290, -- Lasting Exercise Wand
    40862, -- Legend Exercise Wand
    40819, -- Mystic Exercise Wand
    40634, -- Special Exercise Wand
    40693, -- Weak Exercise Wand

    50294, -- Durable Exercise Wraps
    50293, -- Exercise Wraps
    50295, -- Lasting Exercise Wraps
    41021, -- Special Exercise Wraps
    41022, -- Daily Exercise Wraps
    41023, -- Weak Exercise Wraps
    41024, -- Epic Exercise Wraps
    41025, -- Legend Exercise Wraps
    41026, -- Mystic Exercise Wraps
}

local meleeWeapons = {
    40636, -- Daily Exercise Axe
    35280, -- Durable Exercise Axe
    40856, -- Epic Exercise Axe
    28553, -- Exercise Axe
    35286, -- Lasting Exercise Axe
    40863, -- Legend Exercise Axe
    40820, -- Mystic Exercise Axe
    40630, -- Special Exercise Axe
    40687, -- Weak Exercise Axe

    40638, -- Daily Exercise Club
    35281, -- Durable Exercise Club
    40851, -- Epic Exercise Club
    28554, -- Exercise Club
    35287, -- Lasting Exercise Club
    40858, -- Legend Exercise Club
    40815, -- Mystic Exercise Club
    40631, -- Special Exercise Club
    40689, -- Weak Exercise Club

    40640, -- Daily Exercise Shield
    44066, -- Durable Exercise Shield
    40853, -- Epic Exercise Shield
    44065, -- Exercise Shield
    44067, -- Lasting Exercise Shield
    40860, -- Legend Exercise Shield
    40817, -- Mystic Exercise Shield
    40635, -- Special Exercise Shield
    40691, -- Weak Exercise Shield

    40641, -- Daily Exercise Sword
    35279, -- Durable Exercise Sword
    40854, -- Epic Exercise Sword
    28552, -- Exercise Sword
    35285, -- Lasting Exercise Sword
    40861, -- Legend Exercise Sword
    40818, -- Mystic Exercise Sword
    40629, -- Special Exercise Sword
    40692, -- Weak Exercise Sword

    50294, -- Durable Exercise Wraps
    50293, -- Exercise Wraps
    50295, -- Lasting Exercise Wraps
    41021, -- Special Exercise Wraps
    41022, -- Daily Exercise Wraps
    41023, -- Weak Exercise Wraps
    41024, -- Epic Exercise Wraps
    41025, -- Legend Exercise Wraps
    41026, -- Mystic Exercise Wraps
}

local trainingDummies = {
    28558, -- Dummy Trainer (No name)
    28561, -- 28562 -- Demon Exercise Dummy
    40622, -- 40621 -- Deus Dummy
    28559, -- 28560 -- Ferumbras Exercise Dummy
    28563, -- 28564 -- Monk Exercise Dummy
    40648, -- 40647 -- Super Dummy
    41259, -- 41260 -- Future Mage Dummy
}

local dummiesPositions = {
    [28558] = { 28558 }, -- Dummy Trainer (No name)
    [28561] = { 28561, 28562 }, -- Demon Exercise Dummy
    [40622] = { 40622, 40621 }, -- Deus Dummy
    [28559] = { 28559, 28560 }, -- Ferumbras Exercise Dummy
    [28563] = { 28563, 28564 }, -- Monk Exercise Dummy
    [40648] = { 40648, 40647 }, -- Super Dummy
    [41259] = { 41259, 41260 }, -- Future Mage Dummy
}

local catalogBuildEvent = nil
local catalogGeneration = 0
local foodCatalog = nil
local trainingCatalogs = {}
local CATALOG_BATCH_SIZE = 2

local function cancelCatalogBuild()
    catalogGeneration = catalogGeneration + 1
    local event = catalogBuildEvent
    catalogBuildEvent = nil
    if event ~= nil then
        pcall(removeEvent, event)
    end
end

local function buildCatalogInBatches(entries, createEntry)
    cancelCatalogBuild()
    local page = supportGeneralWindow
    if not widgetAlive(page) then
        return
    end

    local generation = catalogGeneration
    local index = 1
    local buildBatch

    local function scheduleBatch()
        if generation ~= catalogGeneration or page ~= supportGeneralWindow or not widgetAlive(page) then
            return
        end

        local event
        event = scheduleEvent(function()
            if catalogBuildEvent == event then
                catalogBuildEvent = nil
            end

            if generation ~= catalogGeneration or page ~= supportGeneralWindow or not widgetAlive(page) then
                return
            end

            buildBatch()
        end, 1)
        catalogBuildEvent = event
    end

    buildBatch = function()
        if generation ~= catalogGeneration or page ~= supportGeneralWindow or not widgetAlive(page) then
            return
        end

        local lastIndex = math.min(#entries, index + CATALOG_BATCH_SIZE - 1)
        while index <= lastIndex do
            if generation ~= catalogGeneration or page ~= supportGeneralWindow or not widgetAlive(page) then
                return
            end

            local entry = entries[index]
            index = index + 1
            local ok, err = pcall(createEntry, entry)
            if not ok then
                g_logger.error('[game_minibot] support catalog entry failed: ' .. tostring(err))
            end
        end

        if index <= #entries then
            scheduleBatch()
        end
    end

    scheduleBatch()
end

local function appendCatalogThingType(catalog, seen, thingType)
    if thingType == nil then
        return
    end
    local id = thingType:getId()
    if seen[id] then
        return
    end
    seen[id] = true
    table.insert(catalog, { id = id, name = thingType:getName() })
end

local function getFoodCatalog()
    if foodCatalog ~= nil then
        return foodCatalog
    end

    foodCatalog = {}
    local seen = {}
    for _, thingType in ipairs(g_things.findItemTypeByMarketCategory(MarketCategory.Food) or {}) do
        appendCatalogThingType(foodCatalog, seen, thingType)
    end
    for _, id in ipairs(foodAppend) do
        appendCatalogThingType(foodCatalog, seen, g_things.getThingType(id, ThingCategoryItem or 0))
    end
    return foodCatalog
end

local function getTrainingCatalog(catalogType)
    if trainingCatalogs[catalogType] ~= nil then
        return trainingCatalogs[catalogType]
    end

    local catalog = {}
    local seen = {}
    local ids = catalogType == 1 and trainingWeapons or trainingDummies
    for _, id in ipairs(ids) do
        appendCatalogThingType(catalog, seen, g_things.getThingType(id, ThingCategoryItem))
    end
    trainingCatalogs[catalogType] = catalog
    return catalog
end

function support_generalModule.init(widget)
    supportGeneralWindow = widget

    support_generalModule.loadSettings()

    supportGeneralWindow.panel.autoHaste.frameBackground.onLeftClick = function()
        supportGeneralWindow.dropDownMenu:setMarginLeft(48)
        supportGeneralWindow.dropDownMenu:setMarginTop(65)
        modules.game_minibot.deferMethod('openSpellCatcher', supportGeneralWindow.panel.autoHaste)
    end

    supportGeneralWindow.panel.autoEat.frameBackground.onLeftClick = function()
        supportGeneralWindow.dropDownMenu:setMarginLeft(48)
        supportGeneralWindow.dropDownMenu:setMarginTop(175)
        modules.game_minibot.deferMethod('openItemCatcher', supportGeneralWindow.panel.autoEat)
    end

    supportGeneralWindow.panel.autoTraining.frameBackground1.onLeftClick = function()
        supportGeneralWindow.dropDownMenu:setMarginLeft(48)
        supportGeneralWindow.dropDownMenu:setMarginTop(265)
        modules.game_minibot.deferMethod('openItemTrainingCatcher', supportGeneralWindow.panel.autoTraining, 1)
    end

    supportGeneralWindow.panel.autoTraining.frameBackground2.onLeftClick = function()
        supportGeneralWindow.dropDownMenu:setMarginLeft(0)
        supportGeneralWindow.dropDownMenu:setMarginTop(265)
        modules.game_minibot.deferMethod('openItemTrainingCatcher', supportGeneralWindow.panel.autoTraining, 2)
    end
end

function support_generalModule.terminate()
    local page = supportGeneralWindow
    pcall(support_generalModule.closeCatcher)

    if supportGeneralWindow == page then
        supportGeneralWindow = nil
    end
end

function support_generalModule.reloadLanguage(language)
    if language == 'ptbr' then
        supportGeneralWindow.panel.title:setText('Geral')
        supportGeneralWindow.panel.autoHaste.noVocation:setTooltip('Sua vocacao nao pode usar esta spell.')
        supportGeneralWindow.panel.autoHaste.help:setTooltip('O AutoHaste detectara automaticamente quando seu bonus de velocidade acabar e usara a spell selecionada.')
        supportGeneralWindow.panel.autoHaste.ignoreProtection:setText('Ignorar em PZ')
        supportGeneralWindow.panel.autoHaste.ignoreProtection:setTextOffset('-15 0')
        supportGeneralWindow.panel.autoHaste.ignoreProteconMask:setMarginLeft(-15)
        supportGeneralWindow.panel.changeGold.check:setText('Troca de coin automatico')
        supportGeneralWindow.panel.changeGold.help:setTooltip('Todas as suas moedas de gold/platinum serao automaticamente transformadas em sua versao mais valiosa quando acumuladas em 100 unidades.')
        supportGeneralWindow.panel.autoMount.check:setText('Montaria automatica')
        supportGeneralWindow.panel.autoMount.help:setTooltip('Ao sair de uma Protection Zone, o Assistente ira tentar manter sempre a montaria ativa no seu personagem.')
        supportGeneralWindow.panel.autoEat.check:setText('Comer automaticamente')
        supportGeneralWindow.panel.autoEat.help:setTooltip('Voce pode selecionar uma Food especifica para que seu personagem coma periodicamente, para mante-lo satisfeito.')
        supportGeneralWindow.panel.autoTraining.check:setText('Treino automatico')
        supportGeneralWindow.panel.autoTraining.help:setTooltip('Voce pode selecionar uma Exercise Weapon especifica e um Dummy para que o Assistente inicie o treinamento automaticamente.')


    elseif language == 'enus' then
        supportGeneralWindow.panel.title:setText('General')
        supportGeneralWindow.panel.autoHaste.noVocation:setTooltip('Your vocation cannot use this spell.')
        supportGeneralWindow.panel.autoHaste.help:setTooltip('Auto Haste will automatically detect when your haste buff is gone and cast the selected spell.')
        supportGeneralWindow.panel.autoHaste.ignoreProtection:setText('Ignore on PZ')
        supportGeneralWindow.panel.autoHaste.ignoreProtection:setTextOffset('-15 0')
        supportGeneralWindow.panel.autoHaste.ignoreProteconMask:setMarginLeft(-15)
        supportGeneralWindow.panel.changeGold.check:setText('Auto change gold')
        supportGeneralWindow.panel.changeGold.help:setTooltip('All your gold/platinum coins will be automatically transformed into their most valuable version when it stacks into 100 units.')
        supportGeneralWindow.panel.autoMount.check:setText('Auto mount')
        supportGeneralWindow.panel.autoMount.help:setTooltip('When leaving a Protection Zone, the Assistant will try to always keep the mount active on your character.')
        supportGeneralWindow.panel.autoEat.check:setText('Auto eat')
        supportGeneralWindow.panel.autoEat.help:setTooltip('You can select a specific food so that your character will periodically eat it, to maintain you satisfied.')
        supportGeneralWindow.panel.autoTraining.check:setText('Auto training')
        supportGeneralWindow.panel.autoTraining.help:setTooltip('You can select a specific exercise weapon and a dummy type, so that the Assistant will automatically start training.')

    end
end

function support_generalModule.saveSettings()
    local settings = modules.game_minibot.getPressetSettings()
    local sList = settings['support_main'] or {}
    if settings['shortcuts'] == nil then
        settings['shortcuts'] = {}
    end

    -- Haste
    local hasteSettings = {}
    local spellId = g_spells.getSpellRegularIdByImageClipX(supportGeneralWindow.panel.autoHaste.spell:getImageClip().x)
    local spell = g_spells.getSpellInfoById(spellId)
    if spell ~= nil then
        hasteSettings['spell'] = math.max(0, spellId)
        hasteSettings['reqmana'] = spell.mana
    else
        hasteSettings['spell'] = 0
        hasteSettings['reqmana'] = 0
    end
    hasteSettings['enabled'] = supportGeneralWindow.panel.autoHaste.check:isChecked()
    hasteSettings['ignorePz'] = supportGeneralWindow.panel.autoHaste.ignoreProtection:isChecked()
    sList['haste'] = hasteSettings

    -- Change gold
    local changeGoldSettings = {}
    changeGoldSettings['enabled'] = supportGeneralWindow.panel.changeGold.check:isChecked()
    sList['change_gold'] = changeGoldSettings

    -- Auto Eat
    local autoEatSettings = {}
    autoEatSettings['item'] = supportGeneralWindow.panel.autoEat.item:getItemId()
    autoEatSettings['enabled'] = supportGeneralWindow.panel.autoEat.check:isChecked()
    sList['auto_eat'] = autoEatSettings

    -- Auto Mount
    local autoMountSettings = {}
    autoMountSettings['enabled'] = supportGeneralWindow.panel.autoMount.check:isChecked()
    sList['auto_mount'] = autoMountSettings

    -- Auto Training
    local autoTrainingSettings = {}
    autoTrainingSettings['item1'] = supportGeneralWindow.panel.autoTraining.item1:getItemId()
    autoTrainingSettings['item2'] = supportGeneralWindow.panel.autoTraining.item2:getItemId()
    autoTrainingSettings['enabled'] = supportGeneralWindow.panel.autoTraining.check:isChecked()
    sList['auto_training'] = autoTrainingSettings

    settings['support_main'] = sList
    modules.game_minibot.setPressetSettings(settings)
    support_generalModule.reloadInternalModule()
end

function support_generalModule.loadSettings()
    local settings = modules.game_minibot.getPressetSettings()
    local sList = settings['support_main'] or {}
    local sShortcut = settings['shortcuts'] or {}

    -- Haste
    local hasteSettings = sList['haste'] or {}
    supportGeneralWindow.panel.autoHaste.check.ignoreCallback = true
    supportGeneralWindow.panel.autoHaste.check:setChecked(hasteSettings['enabled'] or false)
    supportGeneralWindow.panel.autoHaste.ignoreProtection.ignoreCallback = true
    supportGeneralWindow.panel.autoHaste.ignoreProtection:setChecked(hasteSettings['ignorePz'] or false)
    supportGeneralWindow.panel.autoHaste.ignoreProtection.ignoreCallback = nil
    support_generalModule.onHasteChange(supportGeneralWindow.panel.autoHaste.check)
    supportGeneralWindow.panel.autoHaste.check.ignoreCallback = nil
    local spellId = hasteSettings['spell'] or 0
    if spellId > 0 then
        local spell = g_spells.getSpellInfoById(spellId)
        if spell ~= nil then
            supportGeneralWindow.panel.autoHaste.spell:show()
            supportGeneralWindow.panel.autoHaste.spell:setImageClip(g_spells.getSpellRegularImageClipById(spell.id))
            supportGeneralWindow.panel.autoHaste.name:setText(spell.name)
            supportGeneralWindow.panel.autoHaste.words:setText(spell.words)
            supportGeneralWindow.panel.autoHaste.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
            if not(modules.game_actionbar.canSpellCast(spell)) then
                supportGeneralWindow.panel.autoHaste.noVocation:show()
            else
                supportGeneralWindow.panel.autoHaste.noVocation:hide()
            end
        else
            supportGeneralWindow.panel.autoHaste.spell:hide()
            supportGeneralWindow.panel.autoHaste.noVocation:hide()
        end
    else
        supportGeneralWindow.panel.autoHaste.spell:hide()
        supportGeneralWindow.panel.autoHaste.noVocation:hide()
    end

    -- Change gold
    supportGeneralWindow.panel.changeGold.check.ignoreCallback = true
    supportGeneralWindow.panel.changeGold.check:setChecked(sList['change_gold'] ~= nil and sList['change_gold']['enabled'] or false)
    supportGeneralWindow.panel.changeGold.check.ignoreCallback = nil

    -- Auto Eat
    local autoEatSettings = sList['auto_eat'] or {}
    supportGeneralWindow.panel.autoEat.check.ignoreCallback = true
    supportGeneralWindow.panel.autoEat.check:setChecked(autoEatSettings['enabled'] or false)
    support_generalModule.onAutoEatChange(supportGeneralWindow.panel.autoEat.check)
    supportGeneralWindow.panel.autoEat.check.ignoreCallback = nil
    local item = autoEatSettings['item'] or 0
    if item > 0 then
        supportGeneralWindow.panel.autoEat.item:show()
        supportGeneralWindow.panel.autoEat.item:setItemId(item)
        supportGeneralWindow.panel.autoEat.name:setText(supportGeneralWindow.panel.autoEat.item:getItem():getName())
    else
        supportGeneralWindow.panel.autoEat.item:hide()
    end

    -- Auto Mount
    local autoMountSettings = sList['auto_mount'] or {}
    supportGeneralWindow.panel.autoMount.check.ignoreCallback = true
    supportGeneralWindow.panel.autoMount.check:setChecked(autoMountSettings['enabled'] or false)
    support_generalModule.onAutoMountChange(supportGeneralWindow.panel.autoMount.check)
    supportGeneralWindow.panel.autoMount.check.ignoreCallback = nil

    -- Auto Training
    local autoTrainingSettings = sList['auto_training'] or {}
    supportGeneralWindow.panel.autoTraining.check.ignoreCallback = true
    supportGeneralWindow.panel.autoTraining.check:setChecked(autoTrainingSettings['enabled'] or false)
    support_generalModule.onAutoTrainingChange(supportGeneralWindow.panel.autoTraining.check)
    supportGeneralWindow.panel.autoTraining.check.ignoreCallback = nil
    local item1 = autoTrainingSettings['item1'] or 0
    if item1 > 0 then
        supportGeneralWindow.panel.autoTraining.item1:show()
        supportGeneralWindow.panel.autoTraining.item1:setItemId(item1)
    else
        supportGeneralWindow.panel.autoTraining.item1:hide()
    end
    local item2 = autoTrainingSettings['item2'] or 0
    if item2 > 0 then
        supportGeneralWindow.panel.autoTraining.item2:show()
        supportGeneralWindow.panel.autoTraining.item2:setItemId(item2)
    else
        supportGeneralWindow.panel.autoTraining.item2:hide()
    end
end

function support_generalModule.onChangeGoldChange(widget)
    if widget.ignoreCallback then
        return
    end

    modules.game_minibot.deferMethod('saveSettings')
end

function support_generalModule.onAutoMountChange(widget)
    if widget.ignoreCallback then
        return
    end

    modules.game_minibot.deferMethod('saveSettings')
end

function support_generalModule.onHasteChange(widget)
    if widget:isChecked() then
        supportGeneralWindow.panel.autoHaste.block:hide()
        supportGeneralWindow.panel.autoHaste.spell:setOpacity(1)
        supportGeneralWindow.panel.autoHaste.frameBackground:setPhantom(false)
        supportGeneralWindow.panel.autoHaste.noVocation:setOpacity(1)
        supportGeneralWindow.panel.autoHaste.noVocation:setPhantom(false)
        supportGeneralWindow.panel.autoHaste.name:setOpacity(1)
        supportGeneralWindow.panel.autoHaste.words:setOpacity(1)
        supportGeneralWindow.panel.autoHaste.ignoreProtection:setEnabled(true)
    else
        supportGeneralWindow.panel.autoHaste.block:show()
        supportGeneralWindow.panel.autoHaste.spell:setOpacity(0.3)
        supportGeneralWindow.panel.autoHaste.frameBackground:setPhantom(true)
        supportGeneralWindow.panel.autoHaste.noVocation:setOpacity(0.5)
        supportGeneralWindow.panel.autoHaste.noVocation:setPhantom(true)
        supportGeneralWindow.panel.autoHaste.name:setOpacity(0.3)
        supportGeneralWindow.panel.autoHaste.words:setOpacity(0.3)
        supportGeneralWindow.panel.autoHaste.ignoreProtection:setEnabled(false)
    end

    if widget.ignoreCallback then
        return
    end

    modules.game_minibot.deferMethod('saveSettings')
end

function support_generalModule.onIgnoreProtectionChange(widget)
    if widget.ignoreCallback then
        return
    end

    modules.game_minibot.deferMethod('saveSettings')
end

function support_generalModule.onAutoEatChange(widget)
    if widget:isChecked() then
        supportGeneralWindow.panel.autoEat.block:hide()
        supportGeneralWindow.panel.autoEat.item:setOpacity(1)
        supportGeneralWindow.panel.autoEat.frameBackground:setPhantom(false)
        supportGeneralWindow.panel.autoEat.name:setOpacity(1)
    else
        supportGeneralWindow.panel.autoEat.block:show()
        supportGeneralWindow.panel.autoEat.item:setOpacity(0.3)
        supportGeneralWindow.panel.autoEat.frameBackground:setPhantom(true)
        supportGeneralWindow.panel.autoEat.name:setOpacity(0.3)
    end

    if widget.ignoreCallback then
        return
    end

    modules.game_minibot.deferMethod('saveSettings')
end

function support_generalModule.onAutoTrainingChange(widget)
    if widget:isChecked() then
        supportGeneralWindow.panel.autoTraining.block1:hide()
        supportGeneralWindow.panel.autoTraining.item1:setOpacity(1)
        supportGeneralWindow.panel.autoTraining.item2:setOpacity(1)
        supportGeneralWindow.panel.autoTraining.frameBackground1:setPhantom(false)
        supportGeneralWindow.panel.autoTraining.frameBackground2:setPhantom(false)
    else
        supportGeneralWindow.panel.autoTraining.block1:show()
        supportGeneralWindow.panel.autoTraining.item1:setOpacity(0.3)
        supportGeneralWindow.panel.autoTraining.item2:setOpacity(0.3)
        supportGeneralWindow.panel.autoTraining.frameBackground1:setPhantom(true)
        supportGeneralWindow.panel.autoTraining.frameBackground2:setPhantom(true)
    end

    if widget.ignoreCallback then
        return
    end

    modules.game_minibot.deferMethod('saveSettings')
end

function support_generalModule.reloadInternalModule()
    local settings = modules.game_minibot.getPressetSettings()

    local sList = settings['support_main'] or {}
    local sShortcut = settings['shortcuts'] or {}

    -- Haste
    g_minibot.resetModule(4) -- Healing Haste Module type
    local sHaste = sList['haste']
    if sHaste ~= nil then
        local internal = {
            item = 0,
            use = false,
            min = 0,
            max = 0,
            enabled = sHaste['enabled'],
            ignorePz = sHaste['ignorePz'],
            spell = "",

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
        local spell = g_spells.getSpellInfoById(sHaste['spell'])
        local canCastSpell = spell ~= nil and
            (modules.game_actionbar == nil or type(modules.game_actionbar.canSpellCast) ~= 'function' or
             modules.game_actionbar.canSpellCast(spell))
        if canCastSpell then
            internal.spell = spell.words
            internal.reqmana = spell.mana
            table.insert(internal.spellId, spell.id)
            for _, group in ipairs(spell.groups) do
                table.insert(internal.spellGroup, group)
            end
        end
        g_minibot.addModule(4, internal)
    end
    g_minibot.setModuleToggle(4, sHaste ~= nil and sHaste['enabled'] == true) -- Support Haste

    -- Change Gold
    local changeGoldEnabled = false
    local sChangeGold = sList['change_gold']
    if sChangeGold ~= nil then
        changeGoldEnabled = sChangeGold['enabled']
    end
    g_minibot.setModuleToggle(7, changeGoldEnabled) -- Change Gold Module type

    -- Auto Eat
    g_minibot.resetModule(8) -- Auto Eat Module type
    local sAutoEat = sList['auto_eat']
    if sAutoEat ~= nil then
        local internal = {
            item = sAutoEat['item'],
            use = true,
            enabled = true,

            min = 0,
            max = 0,
            spell = "",
            spellGroup = {},
            spellId = {},
            area = "",
            target = "",
            health = 0,
            mana = 0,
            hits = 0,
            harmony = 0,
            itemGroup = { 255 }, -- Multiuse
        }
        g_minibot.addModule(8, internal)
        g_minibot.setModuleToggle(8, sAutoEat['enabled'])
    else
        g_minibot.setModuleToggle(8, false)
    end

    -- Auto Training
    g_minibot.resetModule(12) -- Auto Training Module type
    local sAutoTraining = sList['auto_training']
    if sAutoTraining ~= nil then
        local internal = {
            item = sAutoTraining['item1'] or 0,
            use = table.find(meleeWeapons, sAutoTraining['item1'] or 0),
            spellGroup = {},
            enabled = true,

            min = 0,
            max = 0,
            hits = 0,
            spell = "",
            spellId = {},
            area = "",
            target = "",
            health = 0,
            mana = 0,
            harmony = 0,
            itemGroup = { 255 }, -- Multiuse
        }

        local variations = dummiesPositions[sAutoTraining['item2'] or 0]
        if variations ~= nil then
            for _, id in ipairs(variations) do
                table.insert(internal.spellGroup, id)
            end
        end

        g_minibot.addModule(12, internal)
        g_minibot.setModuleToggle(12, sAutoTraining['enabled'])
    else
        g_minibot.setModuleToggle(12, false)
    end

    -- Auto Mount
    g_minibot.resetModule(22) -- Auto Mount Module type
    local sAutoMount = sList['auto_mount']
    if sAutoMount ~= nil then
        local internal = {
            enabled = true,

            item = 0,
            use = false,
            min = 0,
            max = 0,
            spell = "",
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
        g_minibot.addModule(22, internal)
        g_minibot.setModuleToggle(22, sAutoMount['enabled'])
    else
        g_minibot.setModuleToggle(22, false)
    end
end

function support_generalModule.closeCatcher()
    cancelCatalogBuild()
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

    local page = supportGeneralWindow
    if not widgetAlive(page) then
        return
    end

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

function support_generalModule.openSpellCatcher(spellBlock)
    cancelCatalogBuild()
    supportGeneralWindow.dropDownCatcher:show()
    supportGeneralWindow.dropDownCatcher.onLeftClick = support_generalModule.closeCatcher

    local windowCatcher = modules.game_minibot.getDropDownCatcher()
    if windowCatcher ~= nil then
        windowCatcher:show()
        windowCatcher.onLeftClick = support_generalModule.closeCatcher
    end

    supportGeneralWindow.dropDownMenu:show()
    supportGeneralWindow.dropDownMenuScrollBar:show()
    supportGeneralWindow.dropDownMenu:destroyChildren()

    local spells = {}
    for _, spell in ipairs(hasteSpells) do
        local foundSpell = g_spells.getSpellInfoById(spell.id)
        if foundSpell ~= nil then
            table.insert(spells, foundSpell)
        end
    end

    buildCatalogInBatches(spells, function(foundSpell)
            local spellWidget = g_ui.createWidget('MiniBotSupportGeneralSpellDropDownEntry', supportGeneralWindow.dropDownMenu)
            spellWidget:constructEnviorementVariables()

            if not(modules.game_actionbar.canSpellCast(foundSpell)) then
                spellWidget.block:show()
                spellWidget.icon:setOpacity(0.3)
            else
                spellWidget.block:hide()
                spellWidget.icon:setOpacity(1)
            end

            spellWidget.icon:setImageClip(g_spells.getSpellRegularImageClipById(foundSpell.id))
            spellWidget:setTooltip(foundSpell.name .. '\n\'' .. foundSpell.words .. '\'')

            spellWidget.onLeftClick = function()
                if spellBlock ~= nil then
                    spellBlock.spell:show()
                    spellBlock.spell:setImageClip(g_spells.getSpellRegularImageClipById(foundSpell.id))
                    spellBlock.name:setText(foundSpell.name)
                    spellBlock.words:setText(foundSpell.words)
                    spellBlock.frameBackground:setTooltip(foundSpell.name .. '\n\'' .. foundSpell.words .. '\'')
                    if not(modules.game_actionbar.canSpellCast(foundSpell)) then
                        spellBlock.noVocation:show()
                    else
                        spellBlock.noVocation:hide()
                    end
                end
                support_generalModule.closeCatcher()
                modules.game_minibot.deferMethod('saveSettings')
            end
    end)
end

function support_generalModule.openItemCatcher(itemBlock)
    cancelCatalogBuild()
    supportGeneralWindow.dropDownCatcher:show()
    supportGeneralWindow.dropDownCatcher.onLeftClick = support_generalModule.closeCatcher

    local windowCatcher = modules.game_minibot.getDropDownCatcher()
    if windowCatcher ~= nil then
        windowCatcher:show()
        windowCatcher.onLeftClick = support_generalModule.closeCatcher
    end

    supportGeneralWindow.dropDownMenu:show()
    supportGeneralWindow.dropDownMenuScrollBar:show()
    supportGeneralWindow.dropDownMenu:destroyChildren()

    buildCatalogInBatches(getFoodCatalog(), function(entry)
        local itemWidget = g_ui.createWidget('MiniBotSupportGeneralItemDropDownEntry', supportGeneralWindow.dropDownMenu)
        itemWidget:constructEnviorementVariables()

        itemWidget.item:setItemId(entry.id)
        itemWidget:setTooltip(entry.name)

        itemWidget.onLeftClick = function()
            if itemBlock ~= nil then
                itemBlock.item:show()
                itemBlock.item:setItemId(entry.id)
                itemBlock.name:setText(entry.name)
                itemBlock.frameBackground:setTooltip(entry.name)
            end
            support_generalModule.closeCatcher()
            modules.game_minibot.deferMethod('saveSettings')
        end
    end)
end

function support_generalModule.openItemTrainingCatcher(itemBlock, catalogType)
    cancelCatalogBuild()
    supportGeneralWindow.dropDownCatcher:show()
    supportGeneralWindow.dropDownCatcher.onLeftClick = support_generalModule.closeCatcher

    local windowCatcher = modules.game_minibot.getDropDownCatcher()
    if windowCatcher ~= nil then
        windowCatcher:show()
        windowCatcher.onLeftClick = support_generalModule.closeCatcher
    end

    supportGeneralWindow.dropDownMenu:show()
    supportGeneralWindow.dropDownMenuScrollBar:show()
    supportGeneralWindow.dropDownMenu:destroyChildren()

    buildCatalogInBatches(getTrainingCatalog(catalogType), function(entry)
        local itemWidget = g_ui.createWidget('MiniBotSupportGeneralItemDropDownEntry', supportGeneralWindow.dropDownMenu)
        itemWidget:constructEnviorementVariables()

        itemWidget.item:setItemId(entry.id)
        itemWidget:setTooltip(entry.name)

        itemWidget.onLeftClick = function()
            local item = itemBlock['item' .. catalogType]
            local frameBackground = itemBlock['frameBackground' .. catalogType]

            item:show()
            item:setItemId(entry.id)
            frameBackground:setTooltip(entry.name)

            support_generalModule.closeCatcher()
            modules.game_minibot.deferMethod('saveSettings')
        end
    end)
end

function support_generalModule.onMissileTo(missile, from, to)
    if not(g_minibot.isModuleToggle(12)) then
        return
    end

    local player = g_game.getLocalPlayer()
    if player == nil or not(player:hasState(PlayerStates.StatePz)) then
        return
    end

    if player:getPosition().x ~= from.x or player:getPosition().y ~= from.y or player:getPosition().z ~= from.z then
        return
    end

    g_minibot.setModuleTimeTick(12, g_clock.millis() + 2200)

    local page = supportGeneralWindow
    if not widgetAlive(page) then
        return
    end

    local widget = g_ui.createWidget("UICreature", page.panel.autoTraining.effects)
    widget:setPhantom(true)
    local outfit = {
        type = 0,
        auxType = missile,
        addons = 0,
        head = 0,
        body = 0,
        legs = 0,
        feet = 0,
        mount = 0,
        wings = 0,
        aura = 0,
        shader = '',
        healthBar = 0,
        manaBar = 0,
        category = ThingCategoryMissile
    }


    widget:setPhantom(true)
    widget:setMarginBottom(12)
    widget:setWidth(48)
    widget:setHeight(48)
    widget:setOutfit(outfit)
    widget:setDirection(5)
    widget:getCreature():setDirection(2)
    widget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    widget:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)

    local speedMultiplier = 3.0
    local duration = (150 * math.floor(page.panel.autoTraining.effects:getWidth() / 32)) / speedMultiplier
    local initialMarginLeft = 0
    local finalMarginLeft = page.panel.autoTraining.effects:getWidth() - 48

    local animationStartTime = g_clock.millis()
    local totalDelta = finalMarginLeft - initialMarginLeft
    local frameInterval = 16

    local function animationCycle()
        if not widgetAlive(widget) then
            return
        end
        if widget.missileMoveEvent ~= nil then
            removeEvent(widget.missileMoveEvent)
            widget.missileMoveEvent = nil
        end

        if page ~= supportGeneralWindow or not widgetAlive(page) then
            pcall(function()
                widget:destroy()
            end)
            return
        end

        local now = g_clock.millis()
        local elapsed = now - animationStartTime

        if elapsed >= duration then
            if widgetAlive(widget) then
                widget:setMarginLeft(finalMarginLeft)
                widget:destroy()
            end

            if page == supportGeneralWindow and widgetAlive(page) then
                local effectWidget = g_ui.createWidget("UICreature", page.panel.autoTraining.effects)
                effectWidget:setPhantom(true)
                local outfit2 = {
                    type = 0,
                    auxType = 10,
                    addons = 0,
                    head = 0,
                    body = 0,
                    legs = 0,
                    feet = 0,
                    mount = 0,
                    wings = 0,
                    aura = 0,
                    shader = '',
                    healthBar = 0,
                    manaBar = 0,
                    category = ThingCategoryEffect
                }

                effectWidget:setPhantom(true)
                effectWidget:setAnimate(true)
                effectWidget:setMarginBottom(16)
                effectWidget:setWidth(64)
                effectWidget:setHeight(64)
                effectWidget:setOutfit(outfit2)
                effectWidget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
                effectWidget:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
                effectWidget:setMarginLeft(finalMarginLeft - 18)

                effectWidget._miniBotDestroyEvent = scheduleEvent(function()
                    if not widgetAlive(effectWidget) then
                        return
                    end
                    effectWidget._miniBotDestroyEvent = nil
                    pcall(function()
                        effectWidget:destroy()
                    end)
                end, 600)
            end

            return
        end

        local progress = elapsed / duration
        local currentMarginLeft = initialMarginLeft + totalDelta * progress

        widget:setMarginLeft(currentMarginLeft)

        widget.missileMoveEvent = scheduleEvent(animationCycle, frameInterval)
    end

    animationCycle()
end

function support_generalModule.applyHasteShortcutState(checkWidget, shortcutWidget)
    if checkWidget == nil or shortcutWidget == nil then
        return false
    end
    checkWidget.ignoreCallback = true
    checkWidget:setChecked(shortcutWidget:isChecked())
    checkWidget.ignoreCallback = nil
    return true
end

function support_generalModule.reloadEnabledShortcut(_, widget)
    if widget:getId() ~= 'supportHaste_gamewindow' or supportGeneralWindow == nil then
        return
    end
    support_generalModule.applyHasteShortcutState(
        supportGeneralWindow.panel.autoHaste.check, widget)
end
