combat_pvpModule = {}

local combatPvpWindow = nil
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
        pcall(function()
            removeEvent(event)
        end)
    end
end

local function buildCatcherInBatches(page, entries, createEntry)
    cancelCatcherBuild()

    local generation = catcherGeneration
    local index = 1
    local buildBatch

    local function pageIsCurrent()
        return generation == catcherGeneration and
            page == combatPvpWindow and
            widgetAlive(page) and
            widgetAlive(page.dropDownMenu)
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
                g_logger.error('[game_minibot] combat PvP catcher entry failed: ' .. tostring(err))
            end

            if not pageIsCurrent() then
                return
            end
        end

        if index <= #entries then
            queueBatch()
        end
    end

    -- Even the first entries are deferred so opening the catcher never builds
    -- the whole spell catalog inside the click callback.
    queueBatch()
end

local spellsAppend = {
    { id = 6, words = "utani hur", name = "Haste" },
    { id = 39, words = "utani gran hur", name = "Strong Haste" },
    { id = 134, words = "utamo tempo san", name = "Swift Foot" },
    { id = 131, words = "utani tempo hur", name = "Charge" },
    { id = 1, words = "exura", name = "Light Healing" },
    { id = 2, words = "exura gran", name = "Intense Healing" },
    { id = 3, words = "exura vita", name = "Ultimate Healing" },
    { id = 36, words = "exura gran san", name = "Salvation" },
    { id = 82, words = "exura gran mas res", name = "Mass Healing" },
    { id = 123, words = "exura ico", name = "Wound Cleansing" },
    { id = 125, words = "exura san", name = "Divine Healing" },
    { id = 158, words = "exura gran ico", name = "Intense Wound Cleansing" },
    { id = 170, words = "exura infir ico", name = "Bruise Bane" },
    { id = 174, words = "exura infir", name = "Magic Patch" },
    { id = 239, words = "exura med ico", name = "Fair Wound Cleansing" },
    { id = 241, words = "exura max vita", name = "Restoration" },
    { id = 296, words = "exura mas nia", name = "Mass Spirit Mend" },
    { id = 273, words = "exura gran tio", name = "Spirit Mend" },
}

local function canCastSpell(spell)
    if spell == nil then
        return false
    end
    if modules.game_actionbar == nil or
        type(modules.game_actionbar.canSpellCast) ~= 'function' then
        return true
    end
    local ok, canCast = pcall(modules.game_actionbar.canSpellCast, spell)
    return ok and canCast ~= false
end

function combat_pvpModule.getOrderedAntiParalyzeSpellIds(spells)
    local ordered = {}
    for index, block in ipairs(type(spells) == 'table' and spells or {}) do
        local id = tonumber(block.id)
        local priority = tonumber(block.priority)
        if id ~= nil and id > 0 and id == math.floor(id) and
            priority ~= nil and priority > 0 and priority == math.floor(priority) then
            table.insert(ordered, { id = id, priority = priority, order = index })
        end
    end
    table.sort(ordered, function(first, second)
        if first.priority == second.priority then
            return first.order < second.order
        end
        return first.priority < second.priority
    end)

    local result = {}
    local seen = {}
    for _, entry in ipairs(ordered) do
        if not seen[entry.id] and #result < 5 then
            seen[entry.id] = true
            table.insert(result, entry.id)
        end
    end
    return result
end

function combat_pvpModule.normalizeMousePressArguments(button, mousePos)
    if mousePos == MouseRightButton and button ~= MouseRightButton then
        return mousePos, button
    end
    return button, mousePos
end

function combat_pvpModule.init(widget)
    cancelCatcherBuild()
    combatPvpWindow = widget

    combat_pvpModule.loadSettings()

end

function combat_pvpModule.terminate()
    local page = combatPvpWindow
    combat_pvpModule.closeCatcher()
    if combatPvpWindow == page then
        combatPvpWindow = nil
    end
end

function combat_pvpModule.saveSettings()
    local settings = modules.game_minibot.getPressetSettings()
    local sList = settings['combat_pvp'] or {}
    if settings['shortcuts'] == nil then
        settings['shortcuts'] = {}
    end

    -- Tank Mode
    settings['shortcuts']['tankMode_enabled'] = combatPvpWindow.panel.tankMode.check:isChecked()

    -- Auto-remove paralyze
    local apList = {}
    apList['spells'] = {}
    apList['enabled'] = combatPvpWindow.panel.antiParalyze.check:isChecked()
    for i, c in ipairs(combatPvpWindow.panel.antiParalyze.listPanel.list:getChildren())  do
        if c.spellInfoId ~= nil then
            table.insert(apList['spells'], { id = c.spellInfoId, priority = i })
        end
    end
    sList['antiparalyze_settings'] = apList

    settings['combat_pvp'] = sList
    modules.game_minibot.setPressetSettings(settings)
    combat_pvpModule.reloadInternalModule()
end

function combat_pvpModule.closeCatcher()
    cancelCatcherBuild()

    local ok, windowCatcher = pcall(function()
        return modules.game_minibot.getDropDownCatcher()
    end)
    if ok and widgetAlive(windowCatcher) then
        pcall(function()
            windowCatcher:hide()
            windowCatcher.onLeftClick = nil
        end)
    end

    local page = combatPvpWindow
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

function combat_pvpModule.reloadLanguage(language)
    if language == 'ptbr' then
        combatPvpWindow.panel.tankMode.check:setText('Modo Tanque (SSA e Might Ring)')
        combatPvpWindow.panel.tankMode.help:setTooltip('Ao ativar o Modo Tanque, o Assistente equipara automaticamente o Stone Skin Amlet e o Might Ring, se possivel.')
        combatPvpWindow.panel.antiParalyze.check:setText('Auto-remover Paralyze')
        combatPvpWindow.panel.antiParalyze.help:setTooltip('A remocao automatica de Paralyze usara uma das spells selecionados assim que voce for paralisado. A prioridade respeita a ordem da esquerda para a direita.')

    elseif language == 'enus' then
        combatPvpWindow.panel.tankMode.check:setText('Tank mode (SSA and Might Ring)')
        combatPvpWindow.panel.tankMode.help:setTooltip('Enabling Tank Mode the Assistant will automatically equip Stone Skin Amulet and Might Ring if possible.')
        combatPvpWindow.panel.antiParalyze.check:setText('Auto-remove paralyze')
        combatPvpWindow.panel.antiParalyze.help:setTooltip('Auto-remove Paralyze will cast one of the selected spells as soon as you are paralyzed. The priority respect the order from Left to Right.')

    end
end

function combat_pvpModule.onMousePressPvpItemSpell(widget, button, mousePos)
    -- UIWidget emits (widget, mousePos, mouseButton), while this donor helper
    -- historically exposed (widget, mouseButton, mousePos). Accept both forms
    -- so direct callers and engine callbacks agree on right-click behaviour.
    button, mousePos = combat_pvpModule.normalizeMousePressArguments(button, mousePos)
    local hasExtra = false
    for _, c in ipairs(combatPvpWindow.panel.antiParalyze.listPanel.list:getChildren()) do
        if c.leftArrow ~= nil then
            c:setBorderWidth(0)
            c.leftArrow:setWidth(1)
            c.leftArrow:hide()
            c.rightArrow:setWidth(1)
            c.rightArrow:hide()
            c:setWidth(34)
        else
            hasExtra = true
        end
    end

    local extra = 0
    widget:setBorderWidth(1)
    if widget:getParent():getChildIndex(widget) > 1 then
        widget.leftArrow:setWidth(10)
        widget.leftArrow:show()
        extra = extra + 10

        widget.leftArrow.onLeftClick = function()
            widget:getParent():moveChildToIndex(widget, widget:getParent():getChildIndex(widget) - 1)
            combat_pvpModule.onMousePressPvpItemSpell(widget, button, mousePos)
            combat_pvpModule.saveSettings()
        end
    else
        widget.leftArrow.onLeftClick = nil
    end

    if widget:getParent():getChildIndex(widget) < (hasExtra and (combatPvpWindow.panel.antiParalyze.listPanel.list:getChildCount() - 1) or 5) then
        widget.rightArrow:setWidth(10)
        widget.rightArrow:show()
        extra = extra + 10

        widget.rightArrow.onLeftClick = function()
            widget:getParent():moveChildToIndex(widget, widget:getParent():getChildIndex(widget) + 1)
            combat_pvpModule.onMousePressPvpItemSpell(widget, button, mousePos)
            combat_pvpModule.saveSettings()
        end
    else
        widget.rightArrow.onLeftClick = nil
    end

    widget:setWidth(34 + extra)

    if button == MouseRightButton then
        local page = combatPvpWindow
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)

        menu:addOption('Remove', function()
            if page ~= combatPvpWindow or not widgetAlive(page) or not widgetAlive(widget) then
                return
            end

            local parent = widget:getParent()
            if not widgetAlive(parent) then
                return
            end

            local addNewButton = 0
            for _, c in ipairs(parent:getChildren()) do
                if c.spellInfoId ~= nil then
                    addNewButton = addNewButton + 1
                end
            end

            pcall(function()
                widget:destroy()
            end)
            if addNewButton == 5 and page == combatPvpWindow and widgetAlive(page) then
                local newWidget = g_ui.createWidget('MiniBotCombatPvpitemIgnoreDropDownEntry', page.panel.antiParalyze.listPanel.list)
                newWidget:setId('antiParalyzeNewSpell')
                newWidget.onLeftClick = function()
                    modules.game_minibot.deferMethod('openCatcher')
                end
            end
            combat_pvpModule.saveSettings()
        end)

        menu:display(mousePos)
    end

    return true
end

function combat_pvpModule.openCatcher()
    cancelCatcherBuild()

    local page = combatPvpWindow
    if not widgetAlive(page) or
        not widgetAlive(page.dropDownCatcher) or
        not widgetAlive(page.dropDownMenuScrollBar) or
        not widgetAlive(page.dropDownMenu) then
        return
    end

    local function closePageCatcher()
        if page == combatPvpWindow and widgetAlive(page) then
            combat_pvpModule.closeCatcher()
        end
    end

    page.dropDownCatcher:show()
    page.dropDownCatcher.onLeftClick = closePageCatcher

    local ok, windowCatcher = pcall(function()
        return modules.game_minibot.getDropDownCatcher()
    end)
    if ok and widgetAlive(windowCatcher) then
        windowCatcher:show()
        windowCatcher.onLeftClick = closePageCatcher
    end

    page.dropDownMenu:show()
    page.dropDownMenuScrollBar:show()
    page.dropDownMenu:destroyChildren()
    page.dropDownMenu:setMarginTop(75)

    local selectedSpellIds = {}
    for _, child in ipairs(page.panel.antiParalyze.listPanel.list:getChildren()) do
        if child.spellInfoId ~= nil then
            selectedSpellIds[child.spellInfoId] = true
        end
    end

    local entries = {}
    for _, spell in ipairs(spellsAppend) do
        local foundSpell = g_spells.getSpellInfoById(spell.id)
        if foundSpell ~= nil and not selectedSpellIds[spell.id] then
            table.insert(entries, foundSpell)
        end
    end

    buildCatcherInBatches(page, entries, function(foundSpell)
        if page ~= combatPvpWindow or not widgetAlive(page) or not widgetAlive(page.dropDownMenu) then
            return
        end

        local spellWidget = g_ui.createWidget('MiniBotCombatPvpSpellDropDownEntry', page.dropDownMenu)
        spellWidget:constructEnviorementVariables()

        local spellAvailable = canCastSpell(foundSpell)
        if not spellAvailable then
            spellWidget.block:show()
            spellWidget.icon:setOpacity(0.3)
        end

        spellWidget.icon:setImageClip(g_spells.getSpellRegularImageClipById(foundSpell.id))
        spellWidget:setTooltip(foundSpell.name .. '\n\'' .. foundSpell.words .. '\'')

        if spellAvailable then
            spellWidget.onLeftClick = function()
                if page ~= combatPvpWindow or
                    not widgetAlive(page) or
                    not widgetAlive(spellWidget) then
                    return
                end

                local callbackOk, callbackError = pcall(function()
                    local list = page.panel.antiParalyze.listPanel.list
                    if not widgetAlive(list) then
                        return
                    end

                    local addButton = list:getChildById('antiParalyzeNewSpell')
                    combat_pvpModule.closeCatcher()

                    if page ~= combatPvpWindow or not widgetAlive(page) or not widgetAlive(list) then
                        return
                    end

                    local widget = g_ui.createWidget('MiniBotCombatPvpitemSpellDropDownEntry', list)
                    widget:constructEnviorementVariables()
                    widget.spell:setImageClip(g_spells.getSpellRegularImageClipById(foundSpell.id))
                    widget.spellInfoId = foundSpell.id
                    widget:setTooltip(foundSpell.name .. '\n\'' .. foundSpell.words .. '\'')
                    widget.onMousePress = function(w, b, p)
                        if page ~= combatPvpWindow or not widgetAlive(page) or not widgetAlive(w) then
                            return false
                        end
                        return combat_pvpModule.onMousePressPvpItemSpell(w, b, p)
                    end

                    if widgetAlive(addButton) then
                        if list:getChildCount() > 5 then
                            addButton:destroy()
                        else
                            list:moveChildToIndex(addButton, list:getChildCount())
                        end
                    end

                    modules.game_minibot.deferMethod('saveSettings')
                end)

                if not callbackOk then
                    g_logger.error('[game_minibot] combat PvP catcher selection failed: ' .. tostring(callbackError))
                end
            end
        else
            spellWidget.onLeftClick = nil
        end
    end)
end

function combat_pvpModule.loadSettings()
    local settings = modules.game_minibot.getPressetSettings()
    local sList = settings['combat_pvp'] or {}
    local sShortcut = settings['shortcuts'] or {}

    -- Tank Mode
    combatPvpWindow.panel.tankMode.check.ignoreCallback = true
    combatPvpWindow.panel.tankMode.check:setChecked(sShortcut['tankMode_enabled'] or false)
    combatPvpWindow.panel.tankMode.check.ignoreCallback = nil

    -- Anti paralyze
    local apList = sList['antiparalyze_settings'] or {}
    local apSpells = apList['spells'] or {}
    combatPvpWindow.panel.antiParalyze.check.ignoreCallback = true
    combatPvpWindow.panel.antiParalyze.check:setChecked(apList['enabled'])
    combatPvpWindow.panel.antiParalyze.check.ignoreCallback = nil
    combatPvpWindow.panel.antiParalyze.listPanel.list:destroyChildren()

    if not(apList['enabled']) then
        combatPvpWindow.panel.antiParalyze.listPanel:setOpacity(0.5)
        combatPvpWindow.panel.antiParalyze.listPanel.block:setVisible(true)
    else
        combatPvpWindow.panel.antiParalyze.listPanel:setOpacity(1)
        combatPvpWindow.panel.antiParalyze.listPanel.block:setVisible(false)
    end

    local size = 0
    for _, spellId in ipairs(combat_pvpModule.getOrderedAntiParalyzeSpellIds(apSpells)) do
        local spell = g_spells.getSpellInfoById(spellId)
        if spell ~= nil and size < 5 then
            size = size + 1
            local widget = g_ui.createWidget('MiniBotCombatPvpitemSpellDropDownEntry', combatPvpWindow.panel.antiParalyze.listPanel.list)
            widget:constructEnviorementVariables()
            widget.spell:setImageClip(g_spells.getSpellRegularImageClipById(spell.id))
            widget.spellInfoId = spell.id
            widget:setTooltip(spell.name .. '\n\'' .. spell.words .. '\'')
            widget.onMousePress = function(w, b, p)
                return combat_pvpModule.onMousePressPvpItemSpell(w, b, p)
            end
        end
    end

    if size < 5 then
        local widget = g_ui.createWidget('MiniBotCombatPvpitemIgnoreDropDownEntry', combatPvpWindow.panel.antiParalyze.listPanel.list)
        widget:setId('antiParalyzeNewSpell')
        widget.onLeftClick = function()
            modules.game_minibot.deferMethod('openCatcher')
        end
    end
end

function combat_pvpModule.onTankModeChange(widget)
    if widget.ignoreCallback then
        return
    end

    local panel = modules.game_interface.getMiniBotPanel()
    if panel ~= nil then
        local child = panel:getChildById('tankMode_gamewindow')
        if child ~= nil then
            child.ignoreCallback = true
            child:setChecked(widget:isChecked())
            child.ignoreCallback = nil
        end
    end

    combat_pvpModule.saveSettings()
end

function combat_pvpModule.onAntiParalyzeChange(widget)
    if widget.ignoreCallback then
        return
    end

    if not(widget:isChecked()) then
        combatPvpWindow.panel.antiParalyze.listPanel:setOpacity(0.5)
        combatPvpWindow.panel.antiParalyze.listPanel.block:setVisible(true)
    else
        combatPvpWindow.panel.antiParalyze.listPanel:setOpacity(1)
        combatPvpWindow.panel.antiParalyze.listPanel.block:setVisible(false)
    end

    combat_pvpModule.saveSettings()
end

function combat_pvpModule.reloadInternalModule()
    local settings = modules.game_minibot.getPressetSettings()

    local sList = settings['combat_pvp'] or {}
    local sShortcut = settings['shortcuts'] or {}

    -- Tank Mode
    g_minibot.resetModule(16) -- Tank Mode Module type
    if sShortcut['tankMode_enabled'] then
        for _, itemId in ipairs({ 3081, 3048 }) do
            g_minibot.addModule(16, {
                item = itemId,
                use = false,
                min = 0,
                max = 0,
                enabled = true,
                ignorePz = false,
                spell = "",
                spellGroup = {},
                spellId = {},
                area = "",
                target = "",
                health = 0,
                mana = 0,
                harmony = 0,
                hits = 0,
                itemGroup = {},
            })
        end

        g_minibot.setModuleToggle(16, true) -- Tank Mode Module type
    else
        g_minibot.setModuleToggle(16, false) -- Tank Mode Module type
    end

    -- Anti Paralyze
    local apList = sList['antiparalyze_settings'] or {}
    local apSpells = apList['spells'] or {}
    g_minibot.resetModule(17) -- Anti Paralyze Module type
    local size = 0
    for _, spellId in ipairs(combat_pvpModule.getOrderedAntiParalyzeSpellIds(apSpells)) do
        local spell = g_spells.getSpellInfoById(spellId)
        if spell ~= nil and canCastSpell(spell) and size < 5 then
            size = size + 1

            local internal = {
                spell = spell.words,
                spellGroup = {},
                spellId = {},
                reqmana = spell.mana,

                item = 0,
                hits = 0,
                use = false,
                min = 0,
                max = 0,
                enabled = true,
                ignorePz = false,
                area = "",
                target = "",
                health = 0,
                mana = 0,
                harmony = 0,
                itemGroup = {},
            }

            table.insert(internal.spellId, spell.id)
            for _, group in ipairs(spell.groups or {}) do
                table.insert(internal.spellGroup, group)
            end

            g_minibot.addModule(17, internal)
        end
    end
    g_minibot.setModuleToggle(17, apList['enabled'] == true and size > 0) -- Anti Paralyze Module type
end

function combat_pvpModule.reloadEnabledShortcut(_, widget)
    if widget:getId() == 'tankMode_gamewindow' then
        -- Tank Mode
        combatPvpWindow.panel.tankMode.check.ignoreCallback = true
        combatPvpWindow.panel.tankMode.check:setChecked(widget:isChecked())
        combatPvpWindow.panel.tankMode.check.ignoreCallback = nil
    end
end
