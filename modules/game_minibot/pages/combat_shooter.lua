combat_shooterModule = {}

local combatShooterWindow = nil
local previewBuildEvent = nil
local previewGeneration = 0
local PREVIEW_BATCH_SIZE = 2
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

local function cancelPreviewBuild()
    previewGeneration = previewGeneration + 1
    if previewBuildEvent ~= nil then
        local event = previewBuildEvent
        previewBuildEvent = nil
        pcall(removeEvent, event)
    end
end

local function cancelCatcherBuild()
    catcherGeneration = catcherGeneration + 1
    if catcherBuildEvent ~= nil then
        local event = catcherBuildEvent
        catcherBuildEvent = nil
        pcall(removeEvent, event)
    end
end

local function buildCatcherInBatches(entries, createEntry)
    cancelCatcherBuild()
    local generation = catcherGeneration
    local page = combatShooterWindow
    local index = 1

    if not widgetAlive(page) then
        return
    end

    local buildBatch
    local function scheduleBatch()
        if generation ~= catcherGeneration or combatShooterWindow ~= page or not widgetAlive(page) then
            return
        end

        local event
        event = scheduleEvent(function()
            if catcherBuildEvent == event then
                catcherBuildEvent = nil
            end
            buildBatch()
        end, 1)
        catcherBuildEvent = event
    end

    buildBatch = function()
        if generation ~= catcherGeneration or combatShooterWindow ~= page or not widgetAlive(page) then
            return
        end

        local lastIndex = math.min(#entries, index + CATCHER_BATCH_SIZE - 1)
        while index <= lastIndex do
            if generation ~= catcherGeneration or combatShooterWindow ~= page or not widgetAlive(page) then
                return
            end

            local entry = entries[index]
            index = index + 1
            local ok, err = pcall(createEntry, entry)
            if not ok then
                g_logger.error('[game_minibot] shooter catalog entry failed: ' .. tostring(err))
            end
        end

        if index <= #entries then
            scheduleBatch()
        end
    end

    scheduleBatch()
end

local itemList = {
    3161, -- Avalanche Rune
    3200, -- Explosion Rune
    3189, -- Fireball Rune
    3191, -- Great Fireball Rune
    3198, -- Heavy Magic Missile Rune
    3182, --- Holy Missile Rune
    3158, -- Icicle Rune 
    3174, -- Light Magic Missile Rune
    3195, -- Soulfire Rune
    3179, -- Stalagmite Rune
    3175, -- Stone Shower Rune
    3155, -- Sudden Death Rune
    3202, -- Thunderstorm Rune

    40936, -- Avalanche Rune (Rune Station)
    40939, -- Greater Fireball Rune (Rune Station)
    40941, -- Sudden Death Rune (Rune Station)
    40942, -- Stone Shower Rune (Rune Station)
    40943, -- Thunderstorm Rune (Rune Station)
}

local spellsAppend = {
    
}

function combat_shooterModule.applyAutoRotateVisibility(selectedWidget, visible)
    if selectedWidget == nil or selectedWidget.autoRotate == nil or
        type(selectedWidget.autoRotate.setVisible) ~= 'function' then
        return false
    end
    selectedWidget.autoRotate:setVisible(visible == true)
    return true
end

local function setSourceModeSilently(isItem)
    if combatShooterWindow == nil then
        return
    end

    local panel = combatShooterWindow.config.panel
    local itemCheck = panel.options.itemCheck
    local spellCheck = panel.options.spellCheck
    local previousItemIgnore = itemCheck.ignoreCallback
    local previousSpellIgnore = spellCheck.ignoreCallback
    local itemMode = isItem == true

    itemCheck.ignoreCallback = true
    spellCheck.ignoreCallback = true
    itemCheck:setChecked(itemMode)
    spellCheck:setChecked(not itemMode)
    itemCheck.ignoreCallback = previousItemIgnore
    spellCheck.ignoreCallback = previousSpellIgnore

    panel.item:setVisible(itemMode)
    panel.spell:setVisible(not itemMode)
end

local itemAreas = {
    [3161] = "fill_circle_3",
    [3200] = "cross_1",
    [3189] = "target",
    [3191] = "fill_circle_3",
    [3198] = "target",
    [3182] = "target",
    [3158] = "target",
    [3174] = "target",
    [3195] = "target",
    [3179] = "target",
    [3175] = "fill_circle_3",
    [3155] = "target",
    [3202] = "fill_circle_3",

    [40936] = "fill_circle_3",
    [40939] = "fill_circle_3",
    [40941] = "target",
    [40942] = "fill_circle_3",
    [40943] = "fill_circle_3",
}

local spellAreas = {
    [13] = "hammer_5_dir",
    [19] = "wave_4_dir",
    [22] = "beam_5_dir",
    [23] = "beam_7_dir",
    [24] = "fill_circle_10_center",
    [43] = "hammer_3_dir",
    [56] = "fill_circle_10_center",
    [57] = "target",
    [59] = "hammer_1_dir",
    [61] = "target",
    [62] = "target",
    [80] = "fill_circle_1_center",
    [87] = "target",
    [88] = "target",
    [89] = "target",
    [105] = "fill_circle_1_center",
    [106] = "fill_circle_3_center",
    [107] = "target",
    [111] = "target",
    [112] = "target",
    [113] = "target",
    [118] = "fill_circle_10_center",
    [119] = "fill_circle_10_center",
    [120] = "hammer_5_dir",
    [121] = "wave_4_dir",
    [122] = "target",
    [124] = "fill_circle_3_center",
    [138] = "target",
    [139] = "target",
    [140] = "target",
    [141] = "target",
    [142] = "target",
    [143] = "target",
    [148] = "target",
    [149] = "target",
    [150] = "target",
    [151] = "target",
    [152] = "target",
    [153] = "target",
    [154] = "target",
    [155] = "target",
    [156] = "target",
    [157] = "target",
    [167] = "wave_4_dir",
    [169] = "target",
    [172] = "target",
    [173] = "target",
    [177] = "target",
    [178] = "wave_4_dir",
    [240] = "wave_5_dir",
    [258] = "fill_circle_3_center",
    [260] = "beam_6_dir",
    [261] = "target",
    [262] = "ring_circle_3_center",
    [263] = "ring_circle_3_center",
    [288] = "target",
    [293] = "target",
    [285] = "target",
    [287] = "spear_3_dir",
    [286] = "target",
    [289] = "spear_3_dir",
    [292] = "target",
    [290] = "target",
    [295] = "target",
    [294] = "spear_line_4_dir",
    [284] = "target",
    [291] = "target",
    [271] = "target",
    [272] = "hammer_1_dir",
}

function combat_shooterModule.init(widget)
    combatShooterWindow = widget
    combatShooterWindow.previewBuildPending = false
    combatShooterWindow.previewRequestedAreaStr = nil
    combatShooterWindow.previewConfigured = false

    combatShooterWindow.healthText = 'Health:'
    local language = modules.game_minibot.getSettingsValue(false, 'language', 'ptbr')
    if language == 'ptbr' then
        combatShooterWindow.healthText = 'Vida:'
    elseif language == 'enus' then
        combatShooterWindow.healthText = 'Health:'
    end

    combat_shooterModule.loadSettings()
end

function combat_shooterModule.terminate()
    local page = combatShooterWindow
    combat_shooterModule.closeCatcher()
    cancelPreviewBuild()

    if widgetAlive(page) then
        page.previewBuildPending = false
        page.previewRequestedAreaStr = nil
        page.previewConfigured = false

        local ok, pulseEffect = pcall(function()
            return page.pulseEffect
        end)
        if ok and pulseEffect ~= nil then
            pcall(removeEvent, pulseEffect)
            pcall(function()
                if page.pulseEffect == pulseEffect then
                    page.pulseEffect = nil
                end
            end)
        end
    end

    if combatShooterWindow == page then
        combatShooterWindow = nil
    end

end

function combat_shooterModule.reloadInternalModule()
    local settings = modules.game_minibot.getPressetSettings()

    local list = {}
    local sList = settings['combat_shooter'] or {}
    for _, entry in pairs(sList) do
        table.insert(list, entry)
    end

    table.sort(list, function(a, b)
        return a.priority < b.priority
    end)

    g_minibot.resetModule(0) -- Healing Attack Module type
    for _, entry in ipairs(list) do
        local internal = {
            item = tonumber(entry['item']),
            use = false,
            enabled = entry['enabled'],
            ignorePz = true,
            smart = entry['smart'] == true,
            health = tonumber(entry['health']),
            mana = tonumber(entry['mana']),
            hits = tonumber(entry['hits']),
            area = "",
            target = "",
            reqmana = tonumber(entry['reqmana']) or 0,
            spell = "",
            harmony = tonumber(entry['harmony']) or 0,

            itemGroup = {},
            spellGroup = {},
            spellId = {},

            min = 0,
            max = 0,
        }

        local canCast = true

        local spell = g_spells.getSpellInfoById(entry['spell'])
        if spell ~= nil then
            internal.spell = spell.words
            if spellAreas[spell.id] ~= 'target' then
                internal.area = spellAreas[spell.id]
            end

            if not(modules.game_actionbar.canSpellCast(spell)) then
                canCast = false
            end

            table.insert(internal.spellId, spell.id)
            for _, group in ipairs(spell.groups) do
                table.insert(internal.spellGroup, group)
            end
        end

        if internal.item ~= 0 and itemAreas[internal.item] ~= 'target' then
            internal.area = itemAreas[internal.item]
            table.insert(internal.itemGroup, 255) -- Multiuse
            table.insert(internal.itemGroup, SpellGroup.Attack) -- Attack
        end

        if canCast then
            g_minibot.addModule(0, internal)
        end
    end
end

local function reloadListBackgrounds()
    local isSelected = false

    for _, c in ipairs(combatShooterWindow.priority.list:getChildren()) do
        if not(c.ignoreBackground) then
            c:setBackgroundColor('alpha')

            if c.mask:isVisible() then
                isSelected = true
            end
        end
    end

    if not(isSelected) then
        combatShooterWindow.config.notSelected:show()
        combatShooterWindow.config.panel:hide()
    else
        combatShooterWindow.config.notSelected:hide()
        combatShooterWindow.config.panel:show()
    end
end

function combat_shooterModule.validateTextHarmony(widget)
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

function combat_shooterModule.validateTextPercentage(widget)
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

function combat_shooterModule.loadSettings()
    local settings = modules.game_minibot.getPressetSettings()

    local list = {}
    local sList = settings['combat_shooter'] or {}
    local sSettings = settings['shortcuts'] or {}
    for _, entry in pairs(sList) do
        table.insert(list, entry)
    end

    table.sort(list, function(a, b)
        return a.priority < b.priority
    end)

    local newEntryButton = combatShooterWindow.priority.list:getChildByIndex(1)
    for _, entry in ipairs(list) do
        local newWidget = g_ui.createWidget('MiniBotCombatShooterEntry')
        newWidget:constructEnviorementVariables()

        newWidget.healthPercent:setText(combatShooterWindow.healthText .. ' -%')

        combatShooterWindow.priority.list:insertChild(combatShooterWindow.priority.list:getChildIndex(newEntryButton), newWidget)
        combatShooterWindow.priority.list:ensureChildVisible(newWidget)

        local isPhantom = (entry['item'] == 0 and entry['spell'] == 0) or entry['max'] == 0
        if isPhantom then
            newWidget.icon:setPhantom(true)
            newWidget.icon:setImageClip(torect('50 0 25 25'))
        else
            newWidget.icon:setChecked(entry['enabled'])
        end

        newWidget.extendedArea:setVisible(entry['extended'])

        newWidget.autoRotate:setVisible(entry['smart'] == true)

        if entry['item'] > 0 then
            newWidget.item:show()
            newWidget.item:setItemId(entry['item'])
            newWidget.frameBackground:setTooltip(newWidget.item:getItem():getName())
        end

        newWidget.harmony:hide()
        newWidget.harmony:setImageClip(torect(tostring((entry['harmony'] or 0) * 10) .. " 0 10 39"))

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
                end
            else
                newWidget.frameBackground:setTooltip('Unknown spell')
            end
        end

        if entry['health'] > 0 then
            newWidget.healthPercent:setText(combatShooterWindow.healthText .. ' ' .. entry['health'] .. '%')
        end

        if entry['mana'] > 0 then
            newWidget.manaPercent:setText('Mana: ' .. entry['mana'] .. '%')
        end

        if entry['hits'] > 0 then
            newWidget.range:setText(entry['hits'] .. '+')
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

    combatShooterWindow.priority.enabled.ignoreCallback = true
    combatShooterWindow.priority.enabled:setChecked(sSettings['shooter_enabled'])
    combatShooterWindow.priority.enabled.ignoreCallback = nil

    combatShooterWindow.priority.enabled.onCheckChange = function()
        if combatShooterWindow.priority.enabled.ignoreCallback then
            return
        end

        local panel = modules.game_interface.getMiniBotPanel()
        if panel ~= nil then
            local child = panel:getChildById('shooter_gamewindow')
            if child ~= nil then
                child.ignoreCallback = true
                child:setChecked(combatShooterWindow.priority.enabled:isChecked())
                child.ignoreCallback = nil
            end
        end

        local settings2 = modules.game_minibot.getPressetSettings()
        if settings2['shortcuts'] == nil then
            settings2['shortcuts'] = {}
        end

        settings2['shortcuts']['shooter_enabled'] = combatShooterWindow.priority.enabled:isChecked()
        modules.game_minibot.setPressetSettings(settings2)
        g_minibot.setModuleToggle(0, combatShooterWindow.priority.enabled:isChecked()) -- Shooter (Attack)
    end

    reloadListBackgrounds()
end

function combat_shooterModule.reloadEnabledShortcut(_, widget)
    if widget:getId() ~= 'shooter_gamewindow' then
        return
    end

    combatShooterWindow.priority.enabled.ignoreCallback = true
    combatShooterWindow.priority.enabled:setChecked(widget:isChecked())
    combatShooterWindow.priority.enabled.ignoreCallback = nil
end

function combat_shooterModule.reloadLanguage(language)
    if language == 'ptbr' then
        combatShooterWindow.priority.priorityLabel:setText('Lista de prioridades')
        combatShooterWindow.priority.listHeader.sourceLabel.label:setText('Fonte')
        combatShooterWindow.priority.listHeader.targetsLabel.label:setText('Alvos')
        combatShooterWindow.priority.listHeader.optionsLabel.label:setText('Opcoes')
        combatShooterWindow.priority.listHeader.actionLabel.label:setText('Acao')
        combatShooterWindow.config.title:setText('Configuracao')
        combatShooterWindow.config.notSelected:setText('Selecione uma entrada na lista para configurar ou criar uma nova entrada no botao +.')
        combatShooterWindow.config.panel.save:setText('Aplicar')
        combatShooterWindow.config.panel.name:setPlaceholder('Digite para pesquisar ou arraste')
        combatShooterWindow.config.panel.extendedArea:setText('Area extendida')
        combatShooterWindow.config.panel.extendedArea:setTextOffset('-5 -2')
        combatShooterWindow.config.panel.extendedAreaMask:setMarginLeft(-5)
        combatShooterWindow.config.panel.extendedAreaMask:setTooltip('Algumas spells tem sua area estendida ao usar certos bonus na Roda do Destino.')
        combatShooterWindow.config.panel.autoRotate:setText('Ataque inteligente')
        combatShooterWindow.config.panel.autoRotate:setTextOffset('-25 -2')
        combatShooterWindow.config.panel.autoRotate:setMarginRight(17)
        combatShooterWindow.config.panel.autoRotateMask:setWidth(140)
        combatShooterWindow.config.panel.autoRotateMask:setTooltip('Algumas spells sao orientadas pela direcao do personagem, ao ativar essa opcao o Assistente ira girar o personagem para encontrar a direcao que ira atingir a maior quantidade de alvos.')
        combatShooterWindow.config.panel.options.spellCheck:setText('Usar Spell')
        combatShooterWindow.config.panel.options.itemCheck:setText('Usar Item')
        combatShooterWindow.config.panel.harmonyLabel:setText('Harmonia:')
        combatShooterWindow.config.panel.preview:setTooltip('Verifique a area afetada pela spell/runa selecionada.')
        combatShooterWindow.config.panel.rangeHelp:setTooltip('Selecionando um numero nesta caixa, quando um numero especifico de criaturas estiver dentro desta area de efeito de spell/runa, a acao sera executada.')
        combatShooterWindow.config.panel.maxLabel:setText('Alvos no alcance:')
        combatShooterWindow.config.panel.maxLabel:setText('Alvos no alcance:')
        combatShooterWindow.config.panel.healthHelp:setTooltip('Voce pode escolher sua porcentagem minima de Vida para usar esta Spell. Se sua porcentagem de Vida for INFERIOR a esse valor, a spell sera ativada.')
        combatShooterWindow.config.panel.minLabel:setText('Vida:')
        combatShooterWindow.config.panel.manaHelp:setTooltip('Voce pode escolher sua porcentagem minima de Mana para conjurar esta spell. Se sua porcentagem de Mana for MAIOR que esse valor, a spell sera ativada.')

    elseif language == 'enus' then
        combatShooterWindow.priority.priorityLabel:setText('Priority List')
        combatShooterWindow.priority.listHeader.sourceLabel.label:setText('Source')
        combatShooterWindow.priority.listHeader.targetsLabel.label:setText('Targets')
        combatShooterWindow.priority.listHeader.optionsLabel.label:setText('Options')
        combatShooterWindow.priority.listHeader.actionLabel.label:setText('Action')
        combatShooterWindow.config.title:setText('Configure')
        combatShooterWindow.config.notSelected:setText('Select an entry on the list to configure or create a band-new entry on the + button.')
        combatShooterWindow.config.panel.save:setText('Apply')
        combatShooterWindow.config.panel.name:setPlaceholder('Type to search or drop on slot')
        combatShooterWindow.config.panel.extendedArea:setText('Extended area')
        combatShooterWindow.config.panel.extendedArea:setTextOffset('0 -2')
        combatShooterWindow.config.panel.extendedAreaMask:setMarginLeft(0)
        combatShooterWindow.config.panel.extendedAreaMask:setTooltip('Some spells has it area extended when using certain slots on the Wheel of Destiny.')
        combatShooterWindow.config.panel.autoRotate:setText('Smart attack')
        combatShooterWindow.config.panel.autoRotate:setTextOffset('10 -2')
        combatShooterWindow.config.panel.autoRotate:setMarginRight(17)
        combatShooterWindow.config.panel.autoRotateMask:setWidth(105)
        combatShooterWindow.config.panel.autoRotateMask:setTooltip('Some spells are oriented by the characters direction, when activating this option the assistant will rotate the character to find a direction that will hit a greater number of targets.')
        combatShooterWindow.config.panel.options.spellCheck:setText('Spell entry')
        combatShooterWindow.config.panel.options.itemCheck:setText('Item entry')
        combatShooterWindow.config.panel.harmonyLabel:setText('Harmony:')
        combatShooterWindow.config.panel.preview:setTooltip('Check your selected spell/rune affected area.')
        combatShooterWindow.config.panel.rangeHelp:setTooltip('Selecting a number on this box, when a specific number of creatures is inside of this spell/rune area affect, the action will trigger.')
        combatShooterWindow.config.panel.maxLabel:setText('Creatures on range:')
        combatShooterWindow.config.panel.healthHelp:setTooltip('You can choose your minimum Health percent to cast this spell. If your health percent is LOWER than this number, the spell will trigger.')
        combatShooterWindow.config.panel.minLabel:setText('Health:')
        combatShooterWindow.config.panel.manaHelp:setTooltip('You can choose your minimum Mana percent to cast this spell. If your mana percent is HIGHER than this number, the spell will trigger.')

    end

    for _, c in ipairs(combatShooterWindow.priority.list:getChildren()) do
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
                c.autoRotate:setTooltip('Ataque inteligente')
            elseif language == 'enus' then
                c.harmony:setTooltip('Your selected Harmony requirement.')
                c.noVocation:setTooltip('Your vocation cannot use this spell.')
                c.iconTooptip:setTooltip('Your entry is invalid, please reconfigure it!')
                c.autoRotate:setTooltip('Smart attack')
            end
        end
    end
end

function combat_shooterModule.saveSettings()
    local settings = modules.game_minibot.getPressetSettings()

    local values = {}
    for i, c in ipairs(combatShooterWindow.priority.list:getChildren()) do
        if not(c.ignoreBackground) then
            local value = {}
            value['priority'] = i
            value['item'] = 0
            value['spell'] = 0
            value['health'] = 0
            value['mana'] = 0
            value['reqmana'] = 0
            value['hits'] = 1
            value['extended'] = c.extendedArea:isVisible()
            value['smart'] = c.autoRotate:isVisible()
            value['ignorePz'] = true
            value['enabled'] = not(c.icon:isPhantom()) and c.icon:isChecked()
            value['harmony'] = 0

            if c.healthPercent:getText() ~= (combatShooterWindow.healthText .. ' -%') then
                local numberStr = c.healthPercent:getText():match(combatShooterWindow.healthText .. "%s+(%d+)%%")
                value['health'] = tonumber(numberStr)
            end

            if c.manaPercent:getText() ~= 'Mana: -%' then
                value['mana'] = tonumber(string.sub(c.manaPercent:getText(), 7, -2))
            end

            if c.range:getText() ~= '1+' then
                value['hits'] = tonumber(string.sub(c.range:getText(), 1, -2))
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

    settings['combat_shooter'] = values
    modules.game_minibot.setPressetSettings(settings)
    combat_shooterModule.reloadInternalModule()
end

function combat_shooterModule.onIconCheckEntry(widget)
    if widget:isPhantom() then
        widget:setImageClip(torect('50 0 25 25'))
        return
    end

    if widget:isChecked() then
        widget:setImageClip(torect('0 0 25 25'))
    else
        widget:setImageClip(torect('25 0 25 25'))
    end

    combat_shooterModule.saveSettings()
end

function combat_shooterModule.onMoveUpEntry(widget)
    local index = widget:getParent():getChildIndex(widget)
    if index == 1 then
        return
    end

    widget:getParent():moveChildToIndex(widget, index - 1)
    reloadListBackgrounds()

    widget:onLeftClick()

    combat_shooterModule.saveSettings()
end

function combat_shooterModule.onMoveDownEntry(widget)
    local index = widget:getParent():getChildIndex(widget)
    if index == (widget:getParent():getChildCount() - 1) then
        return
    end

    widget:getParent():moveChildToIndex(widget, index + 1)
    reloadListBackgrounds()

    widget:onLeftClick()

    combat_shooterModule.saveSettings()
end

function combat_shooterModule.onNewEntry(widget)
    if widget.isClickFromUiScrollAreaArrow then
        return
    end

    local lastIndex = widget:getParent():getChildIndex(widget)
    local newWidget = g_ui.createWidget('MiniBotCombatShooterEntry')
    newWidget:constructEnviorementVariables()

    newWidget.healthPercent:setText(combatShooterWindow.healthText .. ' -%')

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

    combat_shooterModule.saveSettings()
end

function combat_shooterModule.closeCatcher()
    cancelCatcherBuild()
    local windowCatcher = modules.game_minibot.getDropDownCatcher()
    if widgetAlive(windowCatcher) then
        pcall(function()
            windowCatcher:hide()
            windowCatcher.onLeftClick = nil
        end)
    end

    local page = combatShooterWindow
    if not widgetAlive(page) then
        return
    end

    pcall(function()
        page.config.panel.options:show()
        page.config.panel.maxLabel:show()
        page.config.panel.minLabel:show()

        page.dropDownCatcher:hide()
        page.dropDownMenuScrollBar:hide()
        page.dropDownMenu:hide()
    end)
end

function combat_shooterModule.openCatcher(isItem)
    local page = combatShooterWindow
    if not widgetAlive(page) then
        return
    end

    cancelCatcherBuild()
    local function closePageCatcher()
        if combatShooterWindow == page and widgetAlive(page) then
            combat_shooterModule.closeCatcher()
        end
    end

    page.dropDownCatcher:show()
    page.dropDownCatcher.onLeftClick = closePageCatcher

    local windowCatcher = modules.game_minibot.getDropDownCatcher()
    if widgetAlive(windowCatcher) then
        windowCatcher:show()
        windowCatcher.onLeftClick = closePageCatcher
    end

    page.dropDownMenu:show()
    page.dropDownMenuScrollBar:show()
    page.dropDownMenu:destroyChildren()

    page.config.panel.options:hide()
    page.config.panel.maxLabel:hide()
    page.config.panel.minLabel:hide()

    if isItem then
        buildCatcherInBatches(itemList, function(item)
            local itemType = g_things.getThingType(item, ThingCategoryItem)
            if itemType then
                local itemWidget = g_ui.createWidget('MiniBotCombatShooteritemDropDownEntry', page.dropDownMenu)
                itemWidget:setItemId(item)
                itemWidget:setTooltip(itemType:getName())

                itemWidget.onLeftClick = function()
                    if combatShooterWindow ~= page or not widgetAlive(page) then
                        return
                    end

                    setSourceModeSilently(true)

                    page.config.panel.item:setItemId(item)
                    page.config.panel.frameBackground:setTooltip(page.config.panel.item:getItem():getName())
                    combat_shooterModule.configurePreview(itemAreas[item])
                    combat_shooterModule.closeCatcher()

                    page.config.panel.autoRotate:setEnabled(false)
                    page.config.panel.autoRotate:setChecked(true)

                    page.config.panel.harmonyLabel:hide()
                    page.config.panel.harmonyValue:hide()
                end
            end
        end)
    else
        local spells = g_spells.getSpellsByGroup(SpellGroup.Attack) or {}
        for _, spell in ipairs(spellsAppend) do
            local foundSpell = g_spells.getSpellInfoById(spell.id)
            if foundSpell ~= nil then
                table.insert(spells, foundSpell)
            end
        end

        buildCatcherInBatches(spells, function(spell)
            local spellWidget = g_ui.createWidget('MiniBotCombatShooterSpellDropDownEntry', page.dropDownMenu)
            spellWidget:constructEnviorementVariables()

            spellWidget.icon:setImageClip(g_spells.getSpellRegularImageClipById(spell.id))
            spellWidget:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')

            if not(modules.game_actionbar.canSpellCast(spell)) then
                spellWidget.block:show()
                spellWidget.icon:setOpacity(0.3)
            end

            spellWidget.onLeftClick = function()
                if combatShooterWindow ~= page or not widgetAlive(page) then
                    return
                end

                setSourceModeSilently(false)

                page.config.panel.spell:setImageClip(g_spells.getSpellRegularImageClipById(spell.id))
                page.config.panel.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
                combat_shooterModule.configurePreview(spellAreas[spell.id])
                combat_shooterModule.closeCatcher()

                if spell.needDirection then
                    page.config.panel.autoRotate:setEnabled(true)
                    page.config.panel.autoRotate:setChecked(true)
                else
                    page.config.panel.autoRotate:setEnabled(false)
                    page.config.panel.autoRotate:setChecked(true)
                end

                if table.find(spell.vocations, "Monk") then
                    page.config.panel.harmonyLabel:show()
                    page.config.panel.harmonyValue:show()
                else
                    page.config.panel.harmonyLabel:hide()
                    page.config.panel.harmonyValue:hide()
                end
            end
        end)
    end
end

function combat_shooterModule.onClickEntry(widget)
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

    if combatShooterWindow.config.selectedEntry == widget then
        return
    end

    combatShooterWindow.config.selectedEntry = widget

    combatShooterWindow.config.notSelected:hide()
    combatShooterWindow.config.panel:show()

    combatShooterWindow.config.panel.options.itemCheck.onCheckChange = nil
    combatShooterWindow.config.panel.options.spellCheck.onCheckChange = nil
    combatShooterWindow.config.panel.name.onTextChange = nil

    combatShooterWindow.config.panel.options.itemCheck:setChecked(false)
    combatShooterWindow.config.panel.options.spellCheck:setChecked(false)

    combatShooterWindow.config.panel.autoRotate:setEnabled(false)
    combatShooterWindow.config.panel.autoRotate:setChecked(true)

    combatShooterWindow.config.panel.item:hide()
    combatShooterWindow.config.panel.spell:hide()

    combatShooterWindow.config.panel.harmonyValue:clearText()
    combatShooterWindow.config.panel.harmonyLabel:hide()
    combatShooterWindow.config.panel.harmonyValue:hide()

    local area = nil
    if widget.item:isVisible() then
        combatShooterWindow.config.panel.options.itemCheck:setChecked(true)
        combatShooterWindow.config.panel.item:show()
        combatShooterWindow.config.panel.item:setItemId(widget.item:getItemId())
        combatShooterWindow.config.panel.frameBackground:setTooltip(widget.item:getItem():getName())
        area = itemAreas[widget.item:getItemId()]
    end

    if widget.spell:isVisible() then
        combatShooterWindow.config.panel.options.spellCheck:setChecked(true)
        combatShooterWindow.config.panel.spell:show()
        combatShooterWindow.config.panel.spell:setImageClip(widget.spell:getImageClip())

        local spell = g_spells.getSpellInfoById(g_spells.getSpellRegularIdByImageClipX(widget.spell:getImageClip().x))
        if spell ~= nil then
            combatShooterWindow.config.panel.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
            area = spellAreas[spell.id]

            if table.find(spell.vocations, "Monk") then
                combatShooterWindow.config.panel.harmonyLabel:show()
                combatShooterWindow.config.panel.harmonyValue:show()
                local harmony = widget.harmony:getImageClip().x / 10
                if harmony > 0 then
                    combatShooterWindow.config.panel.harmonyValue:setText(tostring(harmony))
                end
            end

            if spell.needDirection then
                combatShooterWindow.config.panel.autoRotate:setEnabled(true)
                combatShooterWindow.config.panel.autoRotate:setChecked(widget.autoRotate:isVisible())
            end
        else
            combatShooterWindow.config.panel.frameBackground:setTooltip('Unknown spell')
        end
    end

    combat_shooterModule.configurePreview(area)

    local health = ''
    if widget.healthPercent:getText() ~= (combatShooterWindow.healthText .. ' -%') then
        local numberStr = widget.healthPercent:getText():match(combatShooterWindow.healthText .. "%s+(%d+)%%")
        health = numberStr
    end
    combatShooterWindow.config.panel.healthPercent:setText(health)

    local mana = ''
    if widget.manaPercent:getText() ~= 'Mana: -%' then
        mana = string.sub(widget.manaPercent:getText(), 7, -2)
    end
    combatShooterWindow.config.panel.manaPercent:setText(mana)

    local range = ''
    if widget.range:getText() ~= '1+' then
        range = string.sub(widget.range:getText(), 1, -2)
    end
    combatShooterWindow.config.panel.range:setText(range)

    if not(widget.item:isVisible()) and not(widget.spell:isVisible()) then
        combatShooterWindow.config.panel.options.itemCheck:setChecked(true)
    end

    local function onNameTextChange()
        if combatShooterWindow.config.panel.name:getText() == '' then
            return
        end

        combatShooterWindow.config.panel.frameBackground:removeTooltip()

        combatShooterWindow.config.panel.name.onTextChange = nil
        combatShooterWindow.config.panel.name.ignoreClear = true
        if combatShooterWindow.config.panel.options.itemCheck:isChecked() then
            local items = g_things.findMarketableItemTypesByString(combatShooterWindow.config.panel.name:getText())
            if items == nil or #items == 0 then
                combatShooterWindow.config.panel.item:setItemId(0)
                combatShooterWindow.config.panel.name.onTextChange = onNameTextChange
                combatShooterWindow.config.panel.name.ignoreClear = nil
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
                combatShooterWindow.config.panel.item:setItemId(0)
                combatShooterWindow.config.panel.name.onTextChange = onNameTextChange
                combatShooterWindow.config.panel.name.ignoreClear = nil
                combat_shooterModule.configurePreview(nil)
                return
            end

            setSourceModeSilently(true)

            combatShooterWindow.config.panel.item:setItemId(found:getId())
            combat_shooterModule.configurePreview(itemAreas[found:getId()])

            combatShooterWindow.config.panel.frameBackground:setTooltip(combatShooterWindow.config.panel.item:getItem():getName())
        elseif combatShooterWindow.config.panel.options.spellCheck:isChecked() then
            local strToFind = combatShooterWindow.config.panel.name:getText()
            local foundList = g_spells.findSpellsByString(strToFind, SpellGroup.Attack) or {}
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
                combatShooterWindow.config.panel.spell:setImageClip(torect('0 0 32 32'))
                combatShooterWindow.config.panel.name.onTextChange = onNameTextChange
                combatShooterWindow.config.panel.name.ignoreClear = nil
                combat_shooterModule.configurePreview(nil)
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
                combatShooterWindow.config.panel.spell:setImageClip(torect('0 0 32 32'))
                combatShooterWindow.config.panel.name.onTextChange = onNameTextChange
                combatShooterWindow.config.panel.name.ignoreClear = nil
                combat_shooterModule.configurePreview(nil)
                return
            end

            setSourceModeSilently(false)

            combatShooterWindow.config.panel.spell:setImageClip(g_spells.getSpellRegularImageClipById(found.id))

            combatShooterWindow.config.panel.frameBackground:setTooltip(found.name .. '\n\'' .. found.words .. '\'')
            combat_shooterModule.configurePreview(spellAreas[found.id])
        end

        combatShooterWindow.config.panel.name.onTextChange = onNameTextChange
        combatShooterWindow.config.panel.name.ignoreClear = nil
    end

    combatShooterWindow.config.panel.options.itemCheck.onCheckChange = function(tmpWidget)
        if tmpWidget.ignoreCallback then
            return
        end

        if not(tmpWidget:isChecked()) then
            tmpWidget.ignoreCallback = true
            tmpWidget:setChecked(true)
            tmpWidget.ignoreCallback = nil
            return
        end

        combatShooterWindow.config.panel.harmonyLabel:hide()
        combatShooterWindow.config.panel.harmonyValue:hide()

        combatShooterWindow.config.panel.options.spellCheck.ignoreCallback = true
        combatShooterWindow.config.panel.options.spellCheck:setChecked(false)
        combatShooterWindow.config.panel.options.spellCheck.ignoreCallback = nil

        combatShooterWindow.config.panel.autoRotate:setEnabled(false)
        combatShooterWindow.config.panel.autoRotate:setChecked(true)

        combatShooterWindow.config.panel.spell:hide()
        combatShooterWindow.config.panel.item:show()

        if not(combatShooterWindow.config.panel.name.ignoreClear) then
            combatShooterWindow.config.panel.name.onTextChange = nil
            combatShooterWindow.config.panel.name:clearText()
            combatShooterWindow.config.panel.name.onTextChange = onNameTextChange
        end

        if combatShooterWindow.config.panel.item:getItem() ~= nil then
            combatShooterWindow.config.panel.frameBackground:setTooltip(combatShooterWindow.config.panel.item:getItem():getName())
            combat_shooterModule.configurePreview(itemAreas[combatShooterWindow.config.panel.item:getItem():getId()])
        else
            combatShooterWindow.config.panel.frameBackground:removeTooltip()
            combat_shooterModule.configurePreview(itemAreas[nil])
        end
    end

    combatShooterWindow.config.panel.options.spellCheck.onCheckChange = function(tmpWidget)
        if tmpWidget.ignoreCallback then
            return
        end

        if not(tmpWidget:isChecked()) then
            tmpWidget.ignoreCallback = true
            tmpWidget:setChecked(true)
            tmpWidget.ignoreCallback = nil
            return
        end

        combatShooterWindow.config.panel.harmonyLabel:hide()
        combatShooterWindow.config.panel.harmonyValue:hide()

        combatShooterWindow.config.panel.options.itemCheck.ignoreCallback = true
        combatShooterWindow.config.panel.options.itemCheck:setChecked(false)
        combatShooterWindow.config.panel.options.itemCheck.ignoreCallback = nil

        combatShooterWindow.config.panel.autoRotate:setEnabled(false)
        combatShooterWindow.config.panel.autoRotate:setChecked(true)

        combatShooterWindow.config.panel.spell:show()
        combatShooterWindow.config.panel.item:hide()

        if not(combatShooterWindow.config.panel.name.ignoreClear) then
            combatShooterWindow.config.panel.name.onTextChange = nil
            combatShooterWindow.config.panel.name:clearText()
            combatShooterWindow.config.panel.name.onTextChange = onNameTextChange
        end

        local spell = g_spells.getSpellInfoById(g_spells.getSpellRegularIdByImageClipX(combatShooterWindow.config.panel.spell:getImageClip().x))
        if spell ~= nil then
            combatShooterWindow.config.panel.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
            combat_shooterModule.configurePreview(spellAreas[spell.id])

            if table.find(spell.vocations, "Monk") then
                combatShooterWindow.config.panel.harmonyLabel:show()
                combatShooterWindow.config.panel.harmonyValue:show()
            end

            if spell.needDirection then
                combatShooterWindow.config.panel.autoRotate:setEnabled(true)
                combatShooterWindow.config.panel.autoRotate:setChecked(widget.autoRotate:isVisible())
            end
        else
            combatShooterWindow.config.panel.frameBackground:setTooltip('Unknown spell')
            combat_shooterModule.configurePreview(nil)
        end
    end

    combatShooterWindow.config.panel.frameBackground.onDrop = function(_, droppedWidget, mousePos)
        combatShooterWindow.config.panel.frameBackground:removeTooltip()

        if droppedWidget:getClassName() == "UIItem" then
            local item = droppedWidget:getItem()
            if item == nil or item:getMarketData() == nil or not(table.find(itemList, droppedWidget:getItemId())) then
                return
            end

            setSourceModeSilently(true)

            combatShooterWindow.config.panel.autoRotate:setEnabled(false)
            combatShooterWindow.config.panel.autoRotate:setChecked(true)

            combatShooterWindow.config.panel.item:setItemId(droppedWidget:getItemId())

            combat_shooterModule.configurePreview(itemAreas[droppedWidget:getItemId()])
            combatShooterWindow.config.panel.frameBackground:setTooltip(combatShooterWindow.config.panel.item:getItem():getName())
        end

        if droppedWidget.spellEntry and droppedWidget.spellId ~= nil and droppedWidget.spellId > 0 then
            local spell = g_spells.getSpellInfoById(droppedWidget.spellId)
            if spell == nil or not(table.find(spell.groups, SpellGroup.Attack)) then
                return
            end

            setSourceModeSilently(false)

            if spell.needDirection then
                combatShooterWindow.config.panel.autoRotate:setEnabled(true)
                combatShooterWindow.config.panel.autoRotate:setChecked(widget.autoRotate:isVisible())
            else
                combatShooterWindow.config.panel.autoRotate:setEnabled(false)
                combatShooterWindow.config.panel.autoRotate:setChecked(true)
            end

            combatShooterWindow.config.panel.spell:setImageClip(g_spells.getSpellRegularImageClipById(spell.id))

            combat_shooterModule.configurePreview(spellAreas[spell.id])
            combatShooterWindow.config.panel.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
        end
    end

    combatShooterWindow.config.panel.frameBackground.onLeftClick = function()
        if combatShooterWindow.config.panel.options.itemCheck:isChecked() then
            modules.game_minibot.deferMethod('openCatcher', true)
        elseif combatShooterWindow.config.panel.options.spellCheck:isChecked() then
            modules.game_minibot.deferMethod('openCatcher', false)
        end
    end

    combatShooterWindow.config.panel.name.onTextChange = onNameTextChange

    combatShooterWindow.config.panel.save.onLeftClick = function()
        local selectedWidget = nil
        for _, c in ipairs(combatShooterWindow.priority.list:getChildren()) do
            if c.mask:isVisible() then
                selectedWidget = c
                break
            end
        end

        if selectedWidget == nil then
            return
        end

        selectedWidget.harmony:hide()
        local harmony = tonumber(combatShooterWindow.config.panel.harmonyValue:getText()) or 0
        selectedWidget.harmony:setImageClip(torect(tostring(harmony * 10) .. " 0 10 39"))

        if combatShooterWindow.config.panel.options.itemCheck:isChecked() then
            if combatShooterWindow.config.panel.item:getItem() == nil then
                combat_shooterModule.configurePreview(nil)
                return
            end

            selectedWidget.spell:hide()
            selectedWidget.item:show()
            selectedWidget.noVocation:hide()

            combat_shooterModule.applyAutoRotateVisibility(selectedWidget, true)
            selectedWidget.item:setItemId(combatShooterWindow.config.panel.item:getItemId())
            selectedWidget.frameBackground:setTooltip(combatShooterWindow.config.panel.item:getItem():getName())
            combat_shooterModule.configurePreview(itemAreas[selectedWidget.item:getItemId()])
        elseif combatShooterWindow.config.panel.options.spellCheck:isChecked() then
            selectedWidget.spell:show()
            selectedWidget.item:hide()

            selectedWidget.spell:setImageClip(combatShooterWindow.config.panel.spell:getImageClip())

            local spell = g_spells.getSpellInfoById(g_spells.getSpellRegularIdByImageClipX(combatShooterWindow.config.panel.spell:getImageClip().x))
            if spell ~= nil then
                selectedWidget.frameBackground:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
                combat_shooterModule.configurePreview(spellAreas[spell.id])
                if not(modules.game_actionbar.canSpellCast(spell)) then
                    selectedWidget.noVocation:show()
                else
                    selectedWidget.noVocation:hide()
                end

                if table.find(spell.vocations, "Monk") then
                    selectedWidget.harmony:show()
                end

                combat_shooterModule.applyAutoRotateVisibility(
                    selectedWidget, combatShooterWindow.config.panel.autoRotate:isChecked())
            else
                selectedWidget.frameBackground:setTooltip('Unknown spell')
                combat_shooterModule.configurePreview(nil)
                selectedWidget.noVocation:hide()
            end
        else
            selectedWidget.icon:setChecked(true)
            selectedWidget.icon:setImageClip(torect('50 0 25 25'))
            selectedWidget.icon:setPhantom(true)
            combat_shooterModule.configurePreview(nil)
            selectedWidget.noVocation:hide()
            return
        end

        local health = combatShooterWindow.config.panel.healthPercent:getText()
        if health == '' then
            health = '100'
        end
        local healthValue = tonumber(health) or 100
        selectedWidget.healthPercent:setText(combatShooterWindow.healthText .. ' ' .. health .. '%')

        local mana = combatShooterWindow.config.panel.manaPercent:getText()
        local manaValue = tonumber(mana) or 0
        if mana == '' then
            mana = '-'
        end
        selectedWidget.manaPercent:setText('Mana: ' .. mana .. '%')

        local range = combatShooterWindow.config.panel.range:getText()
        if range == '' then
            range = '1'
        end
        local rangeValue = tonumber(range) or 1
        selectedWidget.range:setText(range .. '+')

        if (selectedWidget.item:isVisible() and selectedWidget.item:getItem()) or selectedWidget.spell:isVisible() then
            if selectedWidget.icon:isPhantom() then
                selectedWidget.icon:setPhantom(false)
                selectedWidget.icon:setImageClip(torect('25 0 25 25'))
            end
        elseif not(selectedWidget.icon:isPhantom()) then
            selectedWidget.icon:setPhantom(true)
            selectedWidget.icon:setImageClip(torect('50 0 25 25'))
        end

        combat_shooterModule.saveSettings()
    end
end

function combat_shooterModule.onRemoveEntry(widget)
    if not widgetAlive(widget) then
        return
    end
    pcall(function()
        widget:destroy()
    end)

    reloadListBackgrounds()

    combat_shooterModule.saveSettings()
end

function combat_shooterModule.configurePreview(areaStr)
    local page = combatShooterWindow
    if not widgetAlive(page) then
        return
    end

    if page.previewConfigured and page.previewAreaStr == areaStr then
        return
    end
    if page.previewBuildPending and page.previewRequestedAreaStr == areaStr then
        return
    end

    cancelPreviewBuild()
    page.previewConfigured = false
    page.previewBuildPending = true
    page.previewRequestedAreaStr = areaStr

    local preview = page.config.panel.preview
    local panel = preview.panel

    local pulseEffect = page.pulseEffect
    if pulseEffect ~= nil then
        page.pulseEffect = nil
        pcall(removeEvent, pulseEffect)
    end

    local function showEmptyPreview()
        panel:hide()
        preview.background:hide()
        preview.icon:show()
    end

    local function commitEmptyPreview(value)
        showEmptyPreview()
        page.previewAreaStr = value
        page.previewRequestedAreaStr = nil
        page.previewBuildPending = false
        page.previewConfigured = true
    end

    if areaStr == nil then
        commitEmptyPreview(nil)
        return
    end

    local okArea, area = pcall(g_minibot.getAreaCoordinates, areaStr)
    if not okArea then
        g_logger.error('[game_minibot] shooter preview area failed: ' .. tostring(area))
        commitEmptyPreview(areaStr)
        return
    end
    if type(area) ~= 'table' or #area == 0 or type(area[1]) ~= 'table' or #area[1] == 0 then
        commitEmptyPreview(areaStr)
        return
    end

    panel:show()
    preview.background:show()
    preview.icon:hide()

    local lines = #area
    local rows = #(area[1])
    local singleTilePreview = lines == 1 and rows == 1
    local largest = math.max(lines, rows)
    local previewSize = math.max(preview:getWidth(), preview:getHeight()) - 10
    local factor = previewSize / (largest * 32)

    panel:setWidth((rows * 32 * factor) - rows)
    panel:setHeight((lines * 32 * factor) - lines)

    page.previewTiles = page.previewTiles or {}
    local tiles = page.previewTiles
    for _, tile in ipairs(tiles) do
        if widgetAlive(tile) then
            tile:hide()
            tile.mask:hide()
            tile.mask:setOpacity(0.3)
            tile.mask.effectDirection = nil
        end
    end

    local creatureWidget = page.previewCreature
    local targetWidget = page.previewTarget
    if widgetAlive(creatureWidget) then
        creatureWidget:hide()
    else
        page.previewCreature = nil
        creatureWidget = nil
    end
    if widgetAlive(targetWidget) then
        targetWidget:hide()
    else
        page.previewTarget = nil
        targetWidget = nil
    end

    local activeMasks = {}
    local totalTiles = lines * rows
    local tileIndex = 1
    local generation = previewGeneration

    local function pageIsCurrent()
        return generation == previewGeneration and combatShooterWindow == page and widgetAlive(page)
    end

    local function invalidatePreview(err)
        if not pageIsCurrent() then
            return
        end

        page.previewAreaStr = nil
        page.previewRequestedAreaStr = nil
        page.previewBuildPending = false
        page.previewConfigured = false
        pcall(showEmptyPreview)
        if err ~= nil then
            g_logger.error('[game_minibot] shooter preview build failed: ' .. tostring(err))
        end
    end

    local function configureCreature(fieldName, outfit, tile, x, y)
        local widget = page[fieldName]
        if not widgetAlive(widget) then
            widget = g_ui.createWidget('UICreature', panel)
            page[fieldName] = widget
        end

        widget:show()
        widget:breakAnchors()
        widget:setMarginTop(0)
        widget:setMarginLeft(0)
        widget:setOutfit(outfit)

        if singleTilePreview then
            widget:setWidth(64)
            widget:setHeight(64)
            widget:centerIn('parent')
            widget:setCenter(true)
        else
            widget:setCenter(false)
            widget:addAnchor(AnchorTop, 'parent', AnchorTop)
            widget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            widget:setWidth(tile:getWidth() * 2)
            widget:setHeight(tile:getHeight() * 2)
            widget:setMarginTop(((y - 2) * 32 * factor) - (y - 2))
            widget:setMarginLeft(((x - 2) * 32 * factor) - (x - 2))
        end

        return widget
    end

    local function finishPreview()
        if not pageIsCurrent() then
            return
        end

        page.previewAreaStr = areaStr
        page.previewRequestedAreaStr = nil
        page.previewBuildPending = false
        page.previewConfigured = true

        targetWidget = page.previewTarget
        creatureWidget = page.previewCreature
        if widgetAlive(targetWidget) and targetWidget:isVisible() then
            panel:moveChildToIndex(targetWidget, panel:getChildCount())
        end
        if widgetAlive(creatureWidget) and creatureWidget:isVisible() then
            panel:moveChildToIndex(creatureWidget, panel:getChildCount())
        end

        if #activeMasks == 0 then
            return
        end

        local pulseEvent
        pulseEvent = cycleEvent(function()
            if not pageIsCurrent() then
                pcall(removeEvent, pulseEvent)
                if widgetAlive(page) then
                    pcall(function()
                        if page.pulseEffect == pulseEvent then
                            page.pulseEffect = nil
                        end
                    end)
                end
                return
            end

            for _, mask in ipairs(activeMasks) do
                if widgetAlive(mask) then
                    pcall(function()
                        local opacity = mask:getOpacity()
                        if mask.effectDirection == nil or mask.effectDirection == 'down' then
                            if opacity <= 0.2 then
                                mask.effectDirection = 'up'
                                mask:setOpacity(opacity + 0.01)
                            else
                                mask:setOpacity(opacity - 0.01)
                            end
                        elseif opacity >= 0.4 then
                            mask.effectDirection = 'down'
                            mask:setOpacity(opacity - 0.01)
                        else
                            mask:setOpacity(opacity + 0.01)
                        end
                    end)
                end
            end
        end, 50)
        page.pulseEffect = pulseEvent
    end

    local buildPreviewBatch
    local function schedulePreviewBatch()
        if not pageIsCurrent() then
            return
        end

        local event
        event = scheduleEvent(function()
            if previewBuildEvent == event then
                previewBuildEvent = nil
            end
            buildPreviewBatch()
        end, 1)
        previewBuildEvent = event
    end

    buildPreviewBatch = function()
        if not pageIsCurrent() then
            return
        end

        local ok, err = pcall(function()
            local lastIndex = math.min(totalTiles, tileIndex + PREVIEW_BATCH_SIZE - 1)
            while tileIndex <= lastIndex do
                if not pageIsCurrent() then
                    return
                end

                local index = tileIndex
                tileIndex = tileIndex + 1
                local y = math.floor((index - 1) / rows) + 1
                local x = ((index - 1) % rows) + 1
                local tile = tiles[index]
                if not widgetAlive(tile) then
                    tile = g_ui.createWidget('MiniBotCombatShooterTile', panel)
                    tile:constructEnviorementVariables()
                    tile.ground:setItemId(409)
                    tiles[index] = tile
                end

                tile:show()
                tile:setWidth(32 * factor)
                tile:setHeight(32 * factor)
                tile:setMarginTop(((y - 1) * 32 * factor) - (y - 1))
                tile:setMarginLeft(((x - 1) * 32 * factor) - (x - 1))
                tile.mask:hide()
                tile.mask:setOpacity(0.3)
                tile.mask.effectDirection = nil

                local sqm = area[y][x]
                if sqm == 1 or sqm == 3 then
                    tile.mask:setBackgroundColor('red')
                    tile.mask:show()
                elseif sqm == 4 then
                    tile.mask:setBackgroundColor('lightGray2')
                    tile.mask:show()
                elseif sqm == 2 then
                    tile.mask:setBackgroundColor('green')
                    tile.mask:show()
                end
                if tile.mask:isVisible() then
                    table.insert(activeMasks, tile.mask)
                end

                if sqm == 2 then
                    local player = g_game.getLocalPlayer()
                    if player ~= nil then
                        local outfit = player:getOutfit()
                        outfit.category = ThingCategoryCreature
                        creatureWidget = configureCreature('previewCreature', outfit, tile, x, y)
                        creatureWidget:setDirection(areaStr:ends('_dir') and 0 or player:getDirection())
                    end
                elseif sqm == 3 then
                    local outfit = {
                        type = 34, auxType = 0, category = ThingCategoryCreature,
                        addons = 0, head = 0, body = 0, legs = 0, feet = 0,
                        mount = 0, wings = 0, aura = 0, shader = '',
                        healthBar = 0, manaBar = 0,
                    }
                    targetWidget = configureCreature('previewTarget', outfit, tile, x, y)
                end
            end
        end)

        if not ok then
            invalidatePreview(err)
            return
        end
        if not pageIsCurrent() then
            return
        end

        if tileIndex <= totalTiles then
            schedulePreviewBatch()
        else
            finishPreview()
        end
    end

    schedulePreviewBatch()
end
