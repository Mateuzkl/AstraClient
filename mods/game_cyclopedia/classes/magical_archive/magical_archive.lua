MagicalArchive = {
    dofile("magical_const"),
    summaryButtons = nil,
    combatMenu = nil,
    additionalMenu = nil,
    runeMenu = nil,

    spellList = {},
    learnedSpells = {},
    temporaryFilter = {},

    initialized = false,
    renderEvent = nil,
    renderGeneration = 0,

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
    if not MagicalArchive.initialized then
        local jsonSpells = MagicalArchive.loadSpellsFromJson()
        if type(jsonSpells) ~= "table" then
            return false
        end

        local spellsById = {}
        for _, spell in ipairs(Spells.getSpellList()) do
            spellsById[spell.id] = spell
        end

        MagicalArchive.spellList = {}
        for _, jsonSpell in ipairs(jsonSpells) do
            local matchingSpell = spellsById[jsonSpell.id]
            MagicalArchive.spellList[#MagicalArchive.spellList + 1] = {
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
        end
        table.sort(MagicalArchive.spellList, function(a, b)
            return a.name < b.name
        end)
        MagicalArchive.initialized = true
    end

    MagicalArchive.learnedSpells = modules.game_spells.getSpellListData()

    MagicalArchive.combatMenu = VisibleCyclopediaPanel and VisibleCyclopediaPanel:recursiveGetChildById("combatMenu")
    MagicalArchive.additionalMenu = VisibleCyclopediaPanel and VisibleCyclopediaPanel:recursiveGetChildById("additionalMenu")
    MagicalArchive.runeMenu = VisibleCyclopediaPanel and VisibleCyclopediaPanel:recursiveGetChildById("runeMenu")

    if MagicalArchive.summaryButtons then
        MagicalArchive.summaryButtons:destroy()
    end
    MagicalArchive.summaryButtons = UIRadioGroup.create()
    if MagicalArchive.combatMenu then MagicalArchive.summaryButtons:addWidget(MagicalArchive.combatMenu) end
    if MagicalArchive.additionalMenu then MagicalArchive.summaryButtons:addWidget(MagicalArchive.additionalMenu) end
    if MagicalArchive.runeMenu then MagicalArchive.summaryButtons:addWidget(MagicalArchive.runeMenu) end
    MagicalArchive.summaryButtons.onSelectionChange = MagicalArchive.onSummaryChange

    MagicalArchive.temporaryFilter = getDefaultFilter()
    VisibleCyclopediaPanel:recursiveGetChildById("searchText"):clearText(true)
    return true
end

local function stopPreviewAnimation()
    if MagicalArchive.previewBuildEvent then
        removeEvent(MagicalArchive.previewBuildEvent)
        MagicalArchive.previewBuildEvent = nil
    end
    if MagicalArchive.previewEvent then
        removeEvent(MagicalArchive.previewEvent)
        MagicalArchive.previewEvent = nil
    end
end

function MagicalArchive.cancelRender()
    stopPreviewAnimation()
    MagicalArchive.renderGeneration = MagicalArchive.renderGeneration + 1
    if MagicalArchive.renderEvent then
        removeEvent(MagicalArchive.renderEvent)
        MagicalArchive.renderEvent = nil
    end
end

function MagicalArchive.terminatePanel()
    MagicalArchive.cancelRender()
    if MagicalArchive.summaryButtons then
        MagicalArchive.summaryButtons:destroy()
        MagicalArchive.summaryButtons = nil
    end
    MagicalArchive.combatMenu = nil
    MagicalArchive.additionalMenu = nil
    MagicalArchive.runeMenu = nil
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

function MagicalArchive.showSpellList(spellId)
    if VisibleCyclopediaPanel:getId() ~= "MagicalArchiveDataPanel" then
        return true
    end

    if not MagicalArchive.init() then
        return
    end

    local searchText
    if spellId then
        for _, spell in ipairs(MagicalArchive.spellList) do
            if spell.id == spellId then
                searchText = spell.words
                VisibleCyclopediaPanel:recursiveGetChildById('searchText'):setText(searchText, true)
                break
            end
        end
    end

    MagicalArchive.setupSpellList(searchText, spellId)
end

local function setSpellDetailsVisible(panel, visible)
    panel.spellRuneDataPanel.dataContent:setVisible(visible)
    panel.spellRuneDataPanel.emptyList:setVisible(not visible)
end

function MagicalArchive.setupSpellList(searchText, spellId)
    local player = g_game.getLocalPlayer()
    local panel = VisibleCyclopediaPanel
    if not player or not panel or panel:getId() ~= "MagicalArchiveDataPanel" then
        return
    end

    local playerLevel = player:getLevel()
    local playerVocation = translateVocation(player:getVocation()) -- Retorna vocationId
    local list = panel:recursiveGetChildById("listPanel")
    if not list then
        return
    end

    MagicalArchive.cancelRender()
    local generation = MagicalArchive.renderGeneration
    list.onChildFocusChange = nil
    list:destroyChildren()
    setSpellDetailsVisible(panel, false)
    cyclopediaWindow.aimTargetBox:setVisible(false)
    list.onChildFocusChange = function(widget, focused, oldFocused, reason)
        UIScrollArea.onChildFocusChange(widget, focused, oldFocused, reason)
        MagicalArchive.onSelectSpell(focused, oldFocused)
    end

    local index = 1
    local selectedWidget
    local function renderBatch()
        MagicalArchive.renderEvent = nil
        if generation ~= MagicalArchive.renderGeneration or panel ~= VisibleCyclopediaPanel or panel:isDestroyed() or list:isDestroyed() then
            return
        end

        local lastIndex = math.min(index + 23, #MagicalArchive.spellList)
        for i = index, lastIndex do
            local spell = MagicalArchive.spellList[i]
            local isSelectedSpell = spell.id == spellId
            local matchesSearch = not searchText or #searchText == 0 or
                matchText(searchText, spell.name) or matchText(searchText, spell.words)
            if isSelectedSpell or (matchesSearch and passesVocationFilter(spell.vocations, playerVocation) and
                passesLevelFilter(spell.level, playerLevel) and passesSpellGroupFilter(spell.group)) then
                local widget = g_ui.createWidget("SmallSpellList", list)
                local image = widget:recursiveGetChildById('spellIcon')
                local name = widget:recursiveGetChildById('name')
                local disabled = widget:recursiveGetChildById('gray')
                local spellId = SpellIcons[spell.icon] and SpellIcons[spell.icon][1] or 0

                image:setImageSource(SpelllistSettings['Default'].verySmallIconFolder)
                image:setImageClip(Spells.getImageClipVerySmall(spellId, 'Default'))
                name:setText(short_text(spell.name, 15))
                if #spell.name > 15 then
                    name:setTooltip(spell.name)
                end
                disabled:setVisible(MagicalArchive.spellIsLocked(spell, playerLevel))
                widget.spellData = spell
                if isSelectedSpell then
                    selectedWidget = widget
                end
            end
        end

        index = lastIndex + 1
        if index <= #MagicalArchive.spellList then
            MagicalArchive.renderEvent = scheduleEvent(renderBatch, 1)
            return
        end

        local focusedWidget = selectedWidget or list:getFirstChild()
        if focusedWidget then
            if list:getFocusedChild() == focusedWidget then
                MagicalArchive.onSelectSpell(focusedWidget)
            else
                list:focusChild(focusedWidget, KeyboardFocusReason)
            end
        end
    end

    MagicalArchive.renderEvent = scheduleEvent(renderBatch, 1)
end

function MagicalArchive.onSelectSpell(focused, oldFocused)
    local panel = VisibleCyclopediaPanel
    if not panel or panel:getId() ~= "MagicalArchiveDataPanel" then
        return
    end

    if oldFocused then
        local oldNameLabel = oldFocused:recursiveGetChildById("name")
        if oldNameLabel then
            oldNameLabel:setColor("#c0c0c0")
        end
    end

    local spellData = focused and focused.spellData
    setSpellDetailsVisible(panel, spellData ~= nil)
    if not spellData then
        stopPreviewAnimation()
        cyclopediaWindow.aimTargetBox:setVisible(false)
        return
    end

    local spellPanel = panel.spellRuneDataPanel.dataContent

    local nameLabel = focused:recursiveGetChildById("name")
    if nameLabel then
        nameLabel:setColor("#f4f4f4")
    end

    local spellId = spellData.icon and SpellIcons[spellData.icon] and SpellIcons[spellData.icon][1] or 0
    local source = SpelllistSettings['Default'].iconsFolder
    local clip = Spells.getImageClipNormal(spellId, 'Default')

    local spellNameWidget = spellPanel:recursiveGetChildById("spellName")
    if spellNameWidget then spellNameWidget:setText(spellData.name or "") end
    local spellTypeWidget = spellPanel:recursiveGetChildById("spellType")
    if spellTypeWidget then spellTypeWidget:setText(spellData.words or "") end
    local iconWidget = spellPanel:recursiveGetChildById("spellIcon")
    if iconWidget then
        iconWidget:setImageSource(source)
        iconWidget:setImageClip(clip)
    end
    local magicLevelWidget = spellPanel:recursiveGetChildById("spellMagicLevel")
    if magicLevelWidget then magicLevelWidget:setText(getRestrictedLevel(spellData)) end

    local vocationList = spellPanel:recursiveGetChildById("vocationPanel")
    if vocationList then
        vocationList:destroyChildren()
        for _, vocation in ipairs(getVocationIconData(spellData.vocations or {})) do
            local widget = g_ui.createWidget("VocationIcon", vocationList)
            widget:setImageClip(string.format("%02d 0 9 9", vocation.index))
            widget:setTooltip(vocation.name)
        end
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
    if selectedId ~= "combatMenu" then
        stopPreviewAnimation()
    end
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

local function addPreviewActor(tile, outfit, direction)
    if not outfit then
        return
    end

    local actor = g_ui.createWidget('SpellArchivePreviewActor', tile)
    actor:setOutfit(outfit)
    actor:setDirection(direction)
    return actor
end

local effectFrameMs = 75
local previewPauseMs = 650

local function createPreviewSprites(parent, thing, cellSize, patternX, patternY)
    local width, height = thing:getWidth(), thing:getHeight()
    local patternsX, patternsY = thing:getNumPatternX(), thing:getNumPatternY()
    local patternSize = width * height * thing:getLayers()
    local visual = {
        parts = {},
        sprites = thing:getSprites(),
        offset = ((patternY % patternsY) * patternsX + patternX % patternsX) * patternSize,
        stride = patternSize * patternsX * patternsY * thing:getNumPatternZ()
    }
    local spriteSize = math.max(1, math.floor(cellSize / math.max(width, height)))
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local sprite = g_ui.createWidget('SpellArchivePreviewEffect', parent)
            sprite:setSize({ width = spriteSize, height = spriteSize })
            sprite:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            sprite:addAnchor(AnchorTop, 'parent', AnchorTop)
            sprite:setMarginLeft(math.floor((cellSize - spriteSize * width) / 2) + (width - x - 1) * spriteSize)
            sprite:setMarginTop(math.floor((cellSize - spriteSize * height) / 2) + (height - y - 1) * spriteSize)
            visual.parts[#visual.parts + 1] = sprite
        end
    end
    return visual
end

local function setPreviewFrame(visual, phase)
    if phase == visual.phase then
        return
    end

    visual.phase = phase
    for index, sprite in ipairs(visual.parts) do
        local id = phase >= 0 and visual.sprites[phase * visual.stride + visual.offset + index] or 0
        if id > 0 and id ~= sprite:getSpriteId() then
            sprite:setSpriteId(id)
        end
        sprite:setVisible(id > 0)
    end
end

local function addPreviewEffect(tile, action, cellSize)
    local effectId = action.id
    if not g_sprites.isLoaded() or not g_things.isValidDatId(effectId, ThingCategoryEffect) then
        return
    end

    local effect = g_things.getThingType(effectId, ThingCategoryEffect)
    local frames = effect:getAnimationPhases()
    if frames < 1 then
        return
    end

    local visual = createPreviewSprites(tile, effect, cellSize, 0, 0)
    visual.startMs = action.timestamp
    visual.frameMs = effectId == 33 and effectFrameMs * 4 or effectFrameMs
    visual.endMs = visual.startMs + frames * visual.frameMs
    return visual
end

local function directionPattern(delta)
    if delta < 0 then
        return 0
    end
    return delta == 0 and 1 or 2
end

local function addPreviewMissile(layer, action, cellSize, origin, x, y)
    if not g_sprites.isLoaded() or not g_things.isValidDatId(action.id, ThingCategoryMissile) then
        return
    end

    local missile = g_things.getThingType(action.id, ThingCategoryMissile)
    local widget = g_ui.createWidget('UIWidget', layer)
    widget:setSize({ width = cellSize, height = cellSize })
    widget:setPhantom(true)
    widget:setFocusable(false)

    local visual = createPreviewSprites(widget, missile, cellSize, directionPattern(x), directionPattern(y))
    visual.widget = widget
    visual.origin = origin
    visual.dx, visual.dy = x * (cellSize + 1), y * (cellSize + 1)
    visual.startMs = action.timestamp
    visual.travelMs = math.max(150, math.floor(150 * math.sqrt(math.sqrt(x * x + y * y))))
    visual.endMs = visual.startMs + visual.travelMs
    return visual
end

local function playCastPreview(panel, playback)
    local effects, missiles = playback.effects, playback.missiles
    local duration = 0
    for _, effect in ipairs(effects) do
        duration = math.max(duration, effect.endMs)
    end
    for _, missile in ipairs(missiles) do
        duration = math.max(duration, missile.endMs)
    end
    if duration == 0 then
        return
    end

    local startedAt = g_clock.realMillis()
    local function update()
        if panel:isDestroyed() or not panel:isVisible() then
            stopPreviewAnimation()
            return
        end

        local elapsed = (g_clock.realMillis() - startedAt) % (duration + previewPauseMs)
        for _, effect in ipairs(effects) do
            local phase = elapsed >= effect.startMs and elapsed < effect.endMs
                and math.floor((elapsed - effect.startMs) / effect.frameMs) or -1
            setPreviewFrame(effect, phase)
        end
        for _, missile in ipairs(missiles) do
            if elapsed >= missile.startMs and elapsed < missile.endMs then
                local fraction = (elapsed - missile.startMs) / missile.travelMs
                local position = playback.layer:getPosition()
                missile.widget:setPosition({
                    x = position.x + missile.origin.x + math.floor(missile.dx * fraction),
                    y = position.y + missile.origin.y + math.floor(missile.dy * fraction)
                })
                setPreviewFrame(missile, 0)
            else
                setPreviewFrame(missile, -1)
            end
        end
    end

    update()
    MagicalArchive.previewEvent = cycleEvent(update, 35)
end

local function renderCastArea(panel, spellData)
    local preview = panel.animationPanel
    local grid, layer = preview.previewGrid, preview.previewProjectiles
    local playback = { effects = {}, missiles = {}, layer = layer }
    local minX, maxX, minY, maxY = 0, 0, 0, 0
    local tiles = {}

    local function markTile(action, role, timestamp)
        local x, y = action.x, action.y
        if type(x) ~= 'number' or type(y) ~= 'number' then
            return
        end
        tiles[y] = tiles[y] or {}
        local tile = tiles[y][x] or {}
        tiles[y][x] = tile
        tile[role] = true
        if action.action == 'fieldEffect' and action.effectID then
            tile.effects = tile.effects or {}
            tile.effects[#tile.effects + 1] = { id = action.effectID, timestamp = timestamp }
        elseif action.action == 'missile' and action.missileID then
            tile.missiles = tile.missiles or {}
            tile.missiles[#tile.missiles + 1] = { id = action.missileID, timestamp = timestamp }
        end
        minX, maxX = math.min(minX, x), math.max(maxX, x)
        minY, maxY = math.min(minY, y), math.max(maxY, y)
    end

    for _, action in ipairs(spellData.initActions) do
        if action.action == 'target' then
            markTile(action, 'target')
        elseif action.action == 'objecttype' then
            markTile(action, 'affected')
        end
    end
    for _, step in ipairs(spellData.timestamps) do
        for _, action in ipairs(step.actions or {}) do
            if action.action == 'fieldEffect' or action.action == 'missile'
                or action.action == 'objecttype' or action.action == 'clearField' then
                markTile(action, 'affected', step.timestamp or 0)
            end
        end
    end

    local layout = grid:getLayout()
    layout:disableUpdates()
    grid:destroyChildren()
    layer:destroyChildren()
    local hasPreview = next(tiles) ~= nil
    preview.animationLabel:setVisible(not hasPreview)
    preview.previewTitle:setVisible(hasPreview)
    grid:setVisible(hasPreview)
    layer:setVisible(hasPreview)
    if hasPreview then
        local columns, rows = maxX - minX + 3, maxY - minY + 3
        local cellSize = math.min(38, math.floor((preview:getWidth() - 12) / columns) - 1,
            math.floor((preview:getHeight() - 36) / rows) - 1)
        grid:setSize({ width = columns * (cellSize + 1) - 1, height = rows * (cellSize + 1) - 1 })
        layout:setCellSize({ width = cellSize, height = cellSize })
        layout:setNumColumns(columns)
        local origin = { x = (1 - minX) * (cellSize + 1), y = (1 - minY) * (cellSize + 1) }
        local travelTime = {}

        local casterOutfit, targetOutfit
        local player = g_game.getLocalPlayer()
        local outfit = player and player:getOutfit()
        if outfit and outfit.type > 0 and g_things.isValidDatId(outfit.type, ThingCategoryCreature) then
            casterOutfit = { type = outfit.type, head = outfit.head, body = outfit.body,
                legs = outfit.legs, feet = outfit.feet, addons = outfit.addons }
            targetOutfit = { type = outfit.type, head = outfit.head, body = 88,
                legs = 76, feet = outfit.feet }
        end

        for y = minY - 1, maxY + 1 do
            for x = minX - 1, maxX + 1 do
                local tile = tiles[y] and tiles[y][x]
                local widget = g_ui.createWidget('SpellArchivePreviewTile', grid)
                if tile and tile.affected then
                    widget:setBackgroundColor('#426b75')
                    widget:setTooltip(tr('Affected tile'))
                end
                if x == 0 and y == 0 then
                    if not addPreviewActor(widget, casterOutfit, East) then
                        widget:setText(tr('C'))
                    end
                    widget:setTooltip(tr('Caster'))
                elseif tile and tile.target then
                    if not addPreviewActor(widget, targetOutfit, West) then
                        widget:setText(tr('T'))
                    end
                    widget:setTooltip(tr('Target'))
                end
                if tile then
                    for _, action in ipairs(tile.missiles or {}) do
                        local missile = addPreviewMissile(layer, action, cellSize, origin, x, y)
                        if missile then
                            playback.missiles[#playback.missiles + 1] = missile
                            travelTime[action.timestamp] = math.max(travelTime[action.timestamp] or 0, missile.travelMs)
                        end
                    end
                    for _, action in ipairs(tile.effects or {}) do
                        local effect = addPreviewEffect(widget, action, cellSize)
                        if effect then
                            playback.effects[#playback.effects + 1] = effect
                        end
                    end
                end
            end
        end

        -- Apply each cast step's travel time after collecting all its projectiles.
        for _, effect in ipairs(playback.effects) do
            local delay = travelTime[effect.startMs] or 0
            effect.startMs = effect.startMs + delay
            effect.endMs = effect.endMs + delay
        end
    end
    layout:enableUpdates()
    layout:update()
    preview.spellData = spellData
    preview.playback = playback
    playCastPreview(panel, playback)
end

local function queueCastPreview(panel, spellData)
    stopPreviewAnimation()
    local preview = panel.animationPanel
    if preview.spellData ~= spellData then
        preview.previewGrid:hide()
        preview.previewProjectiles:hide()
        preview.previewTitle:hide()
        preview.animationLabel:hide()
    end

    -- Build the preview outside the radio group's input callback.
    MagicalArchive.previewBuildEvent = addEvent(function()
        MagicalArchive.previewBuildEvent = nil
        if panel:isDestroyed() or not panel:isVisible() then
            return
        end
        if preview.spellData == spellData then
            playCastPreview(panel, preview.playback)
        else
            renderCastArea(panel, spellData)
        end
    end)
end

function MagicalArchive.populateCombatMenu(panel, spellData)
    local runeFields = { spellGroupInfo = true, cdInfo = true, groupCdInfo = true }
    for _, field in ipairs(CombatMenuFields) do
        local infoWidget = panel:recursiveGetChildById(field.widget)
        if infoWidget then
            local text = "-"
            if spellData.type ~= "Conjure" or runeFields[field.widget] then
                text = field.func(spellData) or "-"
            end
            infoWidget:setText(text)
            if field.widget == "scalesWithInfo" then
                infoWidget:setTooltip(text)
            end
        end
    end
    queueCastPreview(panel, spellData)
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
    MagicalArchive.storageDirty = true
    g_game.sendUpdateAutoAimList(spellFocused.spellData.id, checkBox:isChecked())
end

function MagicalArchive.loadJson()
    if not LoadedPlayer:isLoaded() then return end
    MagicalArchive.storageDirty = false

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
    -- Closing an unrelated tab (especially Map) must not serialize/write the
    -- entire auto-aim profile. Only actual edits require persistence.
    if not MagicalArchive.storageDirty or not LoadedPlayer:isLoaded() then return end
    local file = "/characterdata/" .. LoadedPlayer:getId() .. "/aimattargetconfigurationstorage.json"
    local status, result = pcall(function() return json.encode(MagicalArchive.autoAimStorageData, 2) end)
    if not status then
        return g_logger.error("Error while saving auto aim data. Data won't be saved. Details: " .. result)
    end
    if result:len() > 100 * 1024 * 1024 then
        return g_logger.error("Something went wrong, file is above 100MB, won't be saved")
    end
    if g_resources.writeFileContents(file, result) then MagicalArchive.storageDirty = false end
end
