MagicalArchive = {
    dofile("magical_const"),
    summaryButtons = nil,
    combatMenu = nil,
    additionalMenu = nil,
    runeMenu = nil,

    spellList = {},
    learnedSpells = {},
    temporaryFilter = {},

    autoAimStorageData = AutoAimDefaultSpells
}

MagicalArchive.__index = MagicalArchive

local panelStyles = {
    ["combatMenu"] = "spellDataPanel",
    ["additionalMenu"] = "additionalStats",
    ["runeMenu"] = "runeStats"
}

function MagicalArchive.loadSpellsFromJson()
    local spellsFile = "/mods/game_cyclopedia/classes/magical_archive/spells.json"
    local spellsData = {}
    if g_resources.fileExists(spellsFile) then
        local status, result = pcall(function()
            return json.decode(g_resources.readFileContents(spellsFile))
        end)
        if status then
            spellsData = result
        else
            g_logger.error("Error loading spells.json: " .. result)
            return
        end
    else
        g_logger.error("spells.json not found: " .. spellsFile)
        return
    end

    local previewFile = "/mods/game_cyclopedia/classes/magical_archive/spells-preview.json"
    local previewData = {}
    if g_resources.fileExists(previewFile) then
        local status, result = pcall(function()
            return json.decode(g_resources.readFileContents(previewFile))
        end)
        if status then
            previewData = result
        else
            g_logger.error("Error loading spells-preview.json: " .. result)
            return
        end
    else
        g_logger.error("spells-preview.json not found: " .. previewFile)
        return
    end

    local iconIndexToClientId = {}
    for iconName, ids in pairs(SpellIcons) do
        local clientId, tfsId = ids[1], ids[2]
        iconIndexToClientId[tfsId] = clientId
    end


    local combinedSpells = {}
    for _, spell in ipairs(spellsData) do
        local spellId = tostring(spell.spellid or 0)
        local preview = previewData[spellId] or {}
        local allowedVocations = spell.allowedVocations
        if not allowedVocations or type(allowedVocations) ~= "table" then
            allowedVocations = {}
        end

        local combinedSpell = {
            id = spell.spellid or 0,
            name = spell.name or "Unknown",
            words = spell.formulaWithoutParams or "",
            icon = spell.iconIndex or "unknown",
            group = { [spell.spellGroupPrimary or "SPELLGROUP_NONE"] = true },
            vocations = allowedVocations,
            level = spell.minimumCasterLevel or 0,
            premium = spell.premium or false,
            aggressive = spell.aggressive or false,
            castCostMana = spell.castCostMana or 0,
            castCostSoulPoints = spell.castCostSoulPoints or 0,
            cooldownSelf = spell.cooldownSelf or 0,
            cooldownPrimaryGroup = spell.cooldownPrimaryGroup or 0,
            cooldownSecondaryGroup = spell.cooldownSecondaryGroup or 0,
            description = spell.description or "No description available.",
            cities = spell.cities or {},
            goldPrice = spell.goldPrice or 0,
            source = spell.source or "Unknown",
            scaling = spell.scaling or {},
            runeParams = spell.runeParams or {},
            mean = spell.mean or 0,
            damagetype = spell.damagetype or "Unknown",
            range = preview.range or 0,
            timestamps = preview.timestamps or {},
            initActions = preview.initActions or {},
            type = spell.isRune and "Conjure" or "Spell",
            directional = spell.aggressive
        }

        table.insert(combinedSpells, combinedSpell)
    end

    return combinedSpells
end

function MagicalArchive.init()
    local jsonSpells = MagicalArchive.loadSpellsFromJson()
    local spellsLuaSpells = Spells.getSpellList()
    
    MagicalArchive.spellList = {}
    for _, jsonSpell in ipairs(jsonSpells) do
        local matchingSpell = nil
        for _, spell in ipairs(spellsLuaSpells) do
            if spell.id == jsonSpell.id then
                matchingSpell = spell
                break
            end
        end

        local combinedSpell = {
            id = jsonSpell.id,
            name = jsonSpell.name,
            words = jsonSpell.words,
            icon = matchingSpell and matchingSpell.icon or jsonSpell.icon,
            group = jsonSpell.group,
            vocations = jsonSpell.vocations,
            level = jsonSpell.level,
            premium = jsonSpell.premium,
            aggressive = jsonSpell.aggressive,
            castCostMana = jsonSpell.castCostMana,
            castCostSoulPoints = jsonSpell.castCostSoulPoints,
            cooldownSelf = jsonSpell.cooldownSelf,
            cooldownPrimaryGroup = jsonSpell.cooldownPrimaryGroup,
            cooldownSecondaryGroup = jsonSpell.cooldownSecondaryGroup,
            description = jsonSpell.description,
            cities = jsonSpell.cities,
            goldPrice = jsonSpell.goldPrice,
            source = jsonSpell.source,
            scaling = jsonSpell.scaling,
            runeParams = jsonSpell.runeParams,
            mean = jsonSpell.mean,
            damagetype = jsonSpell.damagetype,
            range = jsonSpell.range,
            timestamps = jsonSpell.timestamps,
            initActions = jsonSpell.initActions,
            type = jsonSpell.type,
            directional = jsonSpell.directional,
            autoaim = matchingSpell and matchingSpell.directional or false,
        }

        table.insert(MagicalArchive.spellList, combinedSpell)
    end

    MagicalArchive.learnedSpells = modules.game_spells.getSpellListData()

    MagicalArchive.combatMenu = VisibleCyclopediaPanel and VisibleCyclopediaPanel:recursiveGetChildById("combatMenu")
    MagicalArchive.additionalMenu = VisibleCyclopediaPanel and VisibleCyclopediaPanel:recursiveGetChildById("additionalMenu")
    MagicalArchive.runeMenu = VisibleCyclopediaPanel and VisibleCyclopediaPanel:recursiveGetChildById("runeMenu")

    MagicalArchive.summaryButtons = UIRadioGroup.create()
    if MagicalArchive.combatMenu then MagicalArchive.summaryButtons:addWidget(MagicalArchive.combatMenu) end
    if MagicalArchive.additionalMenu then MagicalArchive.summaryButtons:addWidget(MagicalArchive.additionalMenu) end
    if MagicalArchive.runeMenu then MagicalArchive.summaryButtons:addWidget(MagicalArchive.runeMenu) end
    MagicalArchive.summaryButtons.onSelectionChange = MagicalArchive.onSummaryChange

    MagicalArchive.temporaryFilter = getDefaultFilter()
    VisibleCyclopediaPanel:recursiveGetChildById("searchText"):clearText(true)
end

function MagicalArchive.spellIsLocked(spell, level)
    if level < spell.level then
        return true
    end

    if spell.maglevel and level < spell.maglevel then
        return true
    end

    if spell.vocations and not table.contains(spell.vocations, translateVocation(g_game.getLocalPlayer():getVocation())) then
        return true
    end

    if not MagicalArchive.learnedSpells[tostring(spell.id)] then
        return true
    end
    return false
end

function MagicalArchive.showSpellList()
    if VisibleCyclopediaPanel:getId() ~= "MagicalArchiveDataPanel" then
        return true
    end

    MagicalArchive.init()
    table.sort(MagicalArchive.spellList, function(a, b)
        return a.name < b.name
    end)

    MagicalArchive.setupSpellList()
end

function MagicalArchive.setupSpellList(searchText)
    local player = g_game.getLocalPlayer()
    local playerLevel = player:getLevel()
    local playerVocation = translateVocation(player:getVocation()) -- Retorna vocationId
    local list = VisibleCyclopediaPanel:recursiveGetChildById("listPanel")
    list:destroyChildren()

    for _, spell in pairs(MagicalArchive.spellList) do
        if searchText and #searchText > 0 then
            if not (matchText(searchText, spell.name) or matchText(searchText, spell.words)) then
                goto continue
            end
        end

        if not passesVocationFilter(spell.vocations, playerVocation) then
            goto continue
        end

        if not passesLevelFilter(spell.level, playerLevel) then
            goto continue
        end

        if not passesSpellGroupFilter(spell.group) then
            goto continue
        end

        local widget = g_ui.createWidget("SmallSpellList", list)
        local image = widget:recursiveGetChildById('spellIcon')
        local name = widget:recursiveGetChildById('name')
        local disabled = widget:recursiveGetChildById('gray')

        local spellId = SpellIcons[spell.icon] and SpellIcons[spell.icon][1] or 0
        local source = SpelllistSettings['Default'].verySmallIconFolder
        local clip = Spells.getImageClipVerySmall(spellId, 'Default')

        image:setImageSource(source)
        image:setImageClip(clip)

        name:setText(short_text(spell.name, 15))
        if #spell.name > 15 then
            name:setTooltip(spell.name)
        end

        disabled:setVisible(MagicalArchive.spellIsLocked(spell, playerLevel))
        widget.spellData = spell

        ::continue::
    end

    cyclopediaWindow.aimTargetBox:setVisible(false)
    list.onChildFocusChange = function(_, focused, oldFocused) 
        MagicalArchive.onSelectSpell(focused, oldFocused)
    end

    local firstWidget = list:getFirstChild()
    if not firstWidget then
        VisibleCyclopediaPanel:recursiveGetChildById("dataContent"):setVisible(false)
        return true
    end

    list:focusChild(firstWidget, KeyboardFocusReason, true)
end

function MagicalArchive.onSelectSpell(focused, oldFocused)
    if VisibleCyclopediaPanel:getId() ~= "MagicalArchiveDataPanel" then
        return true
    end

    if oldFocused then
        local oldNameLabel = oldFocused:recursiveGetChildById("name")
        if oldNameLabel then
            oldNameLabel:setColor("#c0c0c0")
        end
    end

    if not focused then
        return true
    end

    local spellPanel = VisibleCyclopediaPanel:recursiveGetChildById("dataContent")
    if not spellPanel then
        return true
    end

    spellPanel:setVisible(true)

    local nameLabel = focused:recursiveGetChildById("name")
    if nameLabel then
        nameLabel:setColor("#f4f4f4")
    end

    local spellData = focused.spellData
    if not spellData then
        return true
    end

    local spellId = SpellIcons[spellData.icon] and SpellIcons[spellData.icon][1] or 0
    local source = SpelllistSettings['Default'].iconsFolder
    local clip = Spells.getImageClipNormal(spellId, 'Default')

    spellPanel:recursiveGetChildById("spellName"):setText(spellData.name or "")
    spellPanel:recursiveGetChildById("spellType"):setText(spellData.words or "")
    local iconWidget = spellPanel:recursiveGetChildById("spellIcon")
    iconWidget:setImageSource(source)
    iconWidget:setImageClip(clip)
    spellPanel:recursiveGetChildById("spellMagicLevel"):setText(getRestrictedLevel(spellData))

    local vocationList = spellPanel:recursiveGetChildById("vocationPanel")
    vocationList:destroyChildren()
    for _, vocation in ipairs(getVocationIconData(spellData.vocations or {})) do
        local widget = g_ui.createWidget("VocationIcon", vocationList)
        widget:setImageClip(string.format("%02d 0 9 9", vocation.index))
        widget:setTooltip(vocation.name)
    end

    local isConjure = spellData.type == "Conjure"
    if MagicalArchive.runeMenu then
        MagicalArchive.runeMenu:setVisible(isConjure)
    end

    MagicalArchive.summaryButtons:selectWidget(MagicalArchive.combatMenu, false, true)
    cyclopediaWindow.aimTargetBox:setVisible(spellData.autoaim and true or false)
    cyclopediaWindow.aimTargetBox:setChecked(MagicalArchive.autoAimStorageData[tostring(spellData.id)], true)
end

function MagicalArchive.onSummaryChange(widget, selected, lastSelected)
    if not selected then
        MagicalArchive.summaryButtons:selectWidget(MagicalArchive.combatMenu)
        return true
    end

    if lastSelected then
        local lastSelectedStyle = panelStyles[lastSelected:getId()]
        if lastSelectedStyle then
            local lastPanel = VisibleCyclopediaPanel:recursiveGetChildById(lastSelectedStyle)
            if lastPanel then
                lastPanel:setVisible(false)
            end
        end
    end

    local selectedStyle = panelStyles[selected:getId()]
    if not selectedStyle then
        return true
    end

    local styleWidget = VisibleCyclopediaPanel:recursiveGetChildById(selectedStyle)
    if styleWidget then
        styleWidget:setVisible(true)
    else
        return true
    end

    local spellListWidget = VisibleCyclopediaPanel:recursiveGetChildById("listPanel")
    if not spellListWidget then
        return true
    end

    local spellFocused = spellListWidget:getFocusedChild()
    if not spellFocused then
        return true
    end

    local selectedId = selected:getId()
    local spellData = spellFocused.spellData
    if selectedId == "combatMenu" then
        MagicalArchive.populateCombatMenu(styleWidget, spellData)
    elseif selectedId == "additionalMenu" then
        MagicalArchive.populateAdditionalMenu(styleWidget, spellData)
    elseif selectedId == "runeMenu" then
        if spellData.type == "Conjure" then
            MagicalArchive.populateRuneMenu(styleWidget, spellData)
        else
            MagicalArchive.runeMenu:setVisible(false)
            MagicalArchive.summaryButtons:selectWidget(MagicalArchive.combatMenu, false, true)
            MagicalArchive.populateCombatMenu(styleWidget, spellData)
        end
    end
end

function MagicalArchive.onFilterPanel(hideFilter)
    local filterPanel = VisibleCyclopediaPanel:recursiveGetChildById("filterPanel")
    local spellListPanel = VisibleCyclopediaPanel:recursiveGetChildById("spellListPanel")

    filterPanel:setVisible(not hideFilter)
    spellListPanel:setVisible(hideFilter)

    if not hideFilter then
        for k, v in pairs(MagicalArchive.temporaryFilter) do
            local widget = VisibleCyclopediaPanel:recursiveGetChildById(k)
            if widget then
                widget:setChecked(v, true)
            end
        end
    end
end

function MagicalArchive.onSearchTextChange(widget)
    local searchText = widget:getText()
    MagicalArchive.setupSpellList(searchText)
end

function MagicalArchive.onFilterChange(widget)
    local id = widget:getId()
    local isChecked = widget:isChecked()
    local filter = MagicalArchive.temporaryFilter

    filter[id] = isChecked

    local spellTypes = { "attackFilter", "healingFilter", "supportFilter" }
    if id == "allSpellsFilter" then
        for _, type in ipairs(spellTypes) do
            filter[type] = isChecked
        end
    elseif table.contains(spellTypes, id) then
        filter.allSpellsFilter = true
        for _, type in ipairs(spellTypes) do
            if not filter[type] then
                filter.allSpellsFilter = false
                break
            end
        end
    end

    local vocationTypes = { "sorcererFilter", "druidFilter", "paladinFilter", "knightFilter", "monkFilter" }
    if id == "allVocationsFilter" then
        for _, voc in ipairs(vocationTypes) do
            filter[voc] = isChecked
        end
    elseif table.contains(vocationTypes, id) then
        filter.allVocationsFilter = true
        for _, voc in ipairs(vocationTypes) do
            if not filter[voc] then
                filter.allVocationsFilter = false
                break
            end
        end
    end

    for key, value in pairs(filter) do
        local button = VisibleCyclopediaPanel:recursiveGetChildById(key)
        if button then
            button:setChecked(value, true)
        end
    end

    MagicalArchive.setupSpellList()
end

function MagicalArchive.populateCombatMenu(panel, spellData)
    local runeFields = { "spellGroupInfo", "cdInfo", "groupCdInfo" }
    local allFields = { "manaInfo", "spellGroupInfo", "basePowerInfo", "scalesWithInfo", "cdInfo", "groupCdInfo", "magicTypeInfo", "rangeInfo" }

    for _, widgetId in ipairs(allFields) do
        local infoWidget = panel:recursiveGetChildById(widgetId)
        if infoWidget then
            infoWidget:setText("-")
        end
    end

    if spellData.type == "Conjure" then
        for _, field in ipairs(CombatMenuFields) do
            if table.contains(runeFields, field.widget) then
                local infoWidget = panel:recursiveGetChildById(field.widget)
                if infoWidget and type(field.func) == "function" then
                    local text = field.func(spellData)
                    infoWidget:setText(text or "-")
                end
            end
        end
    else
        for _, field in ipairs(CombatMenuFields) do
            local infoWidget = panel:recursiveGetChildById(field.widget)
            if infoWidget and type(field.func) == "function" then
                local text = field.func(spellData)
                infoWidget:setText(text or "-")
                if field.widget == "scalesWithInfo" then
                    infoWidget:setTooltip(text or "-")
                end
            end
        end
    end
end

function MagicalArchive.populateAdditionalMenu(panel, spellData)
    local additionalFields = {
        { widget = "sourceInfo", func = getSpellSource },
        { widget = "learnInfo", func = getSpellLearnIn },
        { widget = "aboutInfo", func = getSpellDescription }
    }

    local widgetIds = { "sourceInfo", "learnInfo", "aboutInfo" }
    for _, widgetId in ipairs(widgetIds) do
        local infoWidget
        if widgetId == "aboutInfo" then
            local aboutInfoPanel = panel:recursiveGetChildById("aboutInfoPanel")
            infoWidget = aboutInfoPanel and aboutInfoPanel:getChildById("aboutInfo")
        else
            infoWidget = panel:recursiveGetChildById(widgetId)
        end
        if infoWidget then
            infoWidget:setText("-")
        end
    end

    for _, field in ipairs(additionalFields) do
        local infoWidget
        if field.widget == "aboutInfo" then
            local aboutInfoPanel = panel:recursiveGetChildById("aboutInfoPanel")
            infoWidget = aboutInfoPanel and aboutInfoPanel:getChildById("aboutInfo")
        else
            infoWidget = panel:recursiveGetChildById(field.widget)
        end
        if infoWidget then
            if type(field.func) == "function" then
                local text = field.func(spellData)
                infoWidget:setText(text or "-")
            end
        end
    end
end

function MagicalArchive.populateRuneMenu(panel, spellData)
    local runeFields = {
        { widget = "amountInfo", func = getSpellRuneParams },
        { widget = "manaInfo", func = getSpellManaAndSoul },
        { widget = "restrictionInfo", func = getSpellLevel },
        { widget = "spellGroupInfo", func = getSpellGroup },
        { widget = "cdInfo", func = getSpellCooldown },
        { widget = "groupCdInfo", func = getSpellGroupCooldown }
    }

    local widgetIds = { "amountInfo", "manaInfo", "restrictionInfo", "spellGroupInfo", "cdInfo", "groupCdInfo" }
    for _, widgetId in ipairs(widgetIds) do
        local infoWidget = panel:recursiveGetChildById(widgetId)
        if infoWidget then
            infoWidget:setText("-")
        end
    end

    for _, field in ipairs(runeFields) do
        local infoWidget = panel:recursiveGetChildById(field.widget)
        if infoWidget then
            if type(field.func) == "function" then
                local text = field.func(spellData)
                infoWidget:setText(text or "-")
            end
        end
    end

    local vocationList = panel:recursiveGetChildById("vocationsInfo")
    if vocationList then
        vocationList:destroyChildren()
        for _, vocation in ipairs(getVocationIconData(spellData.vocations or {})) do
            local widget = g_ui.createWidget("VocationIcon", vocationList)
            widget:setImageClip(string.format("%02d 0 9 9", vocation.index))
            widget:setTooltip(vocation.name)
        end
    end
end

function MagicalArchive.onAimTargetChange(checkBox)
    local spellListWidget = VisibleCyclopediaPanel:recursiveGetChildById("listPanel")
    if not spellListWidget then
        return true
    end

    local spellFocused = spellListWidget:getFocusedChild()
    if not spellFocused then
        return true
    end

    MagicalArchive.autoAimStorageData[tostring(spellFocused.spellData.id)] = checkBox:isChecked()
    g_game.sendUpdateAutoAimList(spellFocused.spellData.id, checkBox:isChecked())
end

function MagicalArchive.loadJson()
    if not LoadedPlayer:isLoaded() then return end

    local file = "/characterdata/" .. LoadedPlayer:getId() .. "/aimattargetconfigurationstorage.json"
    if g_resources.fileExists(file) then
        local status, result = pcall(function()
            return json.decode(g_resources.readFileContents(file))
        end)
        if not status then
            return g_logger.error("Error while reading auto aim file. Details: " .. result)
        end
        MagicalArchive.autoAimStorageData = result
    end

    g_game.doThing(false)
    g_game.sendAutoAimList(MagicalArchive.autoAimStorageData)
    g_game.doThing(true)
end

function MagicalArchive.saveJson()
    local file = "/characterdata/" .. LoadedPlayer:getId() .. "/aimattargetconfigurationstorage.json"
    local status, result = pcall(function() return json.encode(MagicalArchive.autoAimStorageData, 2) end)
    if not status then
        return g_logger.error("Error while saving auto aim data. Data won't be saved. Details: " .. result)
    end
    if result:len() > 100 * 1024 * 1024 then
        return g_logger.error("Something went wrong, file is above 100MB, won't be saved")
    end
    g_resources.writeFileContents(file, result)
end