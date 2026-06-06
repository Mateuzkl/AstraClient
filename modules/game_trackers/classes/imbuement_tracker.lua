Tracker = Tracker or {}
Tracker.Imbuement = {}

-- Constantes de tempo em segundos
local DURATION_ONE_HOUR = 3600
local DURATION_THREE_HOURS = 10800

-- Ordem dos slots conforme recebido do backend
local IMBUEMENTTRACKER_SLOTS_ORDER = {
    InventorySlotHead,
    InventorySlotBack,
    InventorySlotBody,
    InventorySlotRight,
    InventorySlotLeft,
    InventorySlotFeet
}

local IMBUEMENTTRACKER_SLOTS = {
    INVENTORYSLOT_HEAD = InventorySlotHead,
    INVENTORYSLOT_BACKPACK = InventorySlotBack,
    INVENTORYSLOT_ARMOR = InventorySlotBody,
    INVENTORYSLOT_RIGHT = InventorySlotRight,
    INVENTORYSLOT_LEFT = InventorySlotLeft,
    INVENTORYSLOT_FEET = InventorySlotFeet
}

local IMBUEMENTTRACKER_FILTERS = {
    ["showLessThan1h"] = true,
    ["showBetween1hAnd3h"] = true,
    ["showMoreThan3h"] = true,
    ["showNoImbuements"] = true
}

-- Cache de widgets para evitar recriação e manter posição do scroll
local trackedItemWidgets = {}

local imbuementTracker = nil
local imbuementTrackerButton = nil
local imbuementTrackerMenuButton = nil

local function loadFilters()
    local settings = g_settings.getNode("ImbuementTracker")
    if not settings or not settings['filters'] then
        return IMBUEMENTTRACKER_FILTERS
    end
    return settings['filters']
end

local function saveFilters()
    g_settings.mergeNode('ImbuementTracker', { ['filters'] = loadFilters() })
end

local function getFilter(filter)
    return loadFilters()[filter] or false
end

local function setFilter(filter)
    local filters = loadFilters()
    local value = filters[filter]
    if value == nil then
        return false
    end

    filters[filter] = not value
    g_settings.mergeNode('ImbuementTracker', { ['filters'] = filters })
    g_game.imbuementDurations(imbuementTrackerButton:isOn())
end

local function getTrackedItems(items)
    local trackedItems = {}
    for _, item in ipairs(items) do
        if table.contains(IMBUEMENTTRACKER_SLOTS, item['slot']) then
            trackedItems[#trackedItems + 1] = item
        end
    end
    return trackedItems
end

local function setDuration(label, duration)
    if not label then
        return ""
    end
    if duration == 0 then
        label:setVisible(false)
        return ""
    end
    local hours = math.floor(duration / 3600)
    local minutes = math.floor((duration % 3600) / 60)
    local seconds = duration % 60
    local tooltip = tr("Time remaining: %sh %smin", hours, minutes)
    local formatted_minutes = string.format("%02d", minutes)
    local formatted_seconds = string.format("%02d", seconds)
    if hours >= 10 then
        label:setText(hours .. "h")
    elseif hours < 10 and hours >= 1 then
        label:setText(hours .. "h" .. formatted_minutes)
    elseif hours < 1 and minutes >= 10 then
        label:setText(formatted_minutes .. "m")
    elseif minutes < 10 and minutes >= 1 then
        if seconds > 0 then
            label:setText(minutes .. "m" .. formatted_seconds)
            tooltip = tr("Time remaining: %sm %sseconds", minutes, seconds)
        else
            label:setText(minutes .. "m")
            tooltip = tr("Time remaining: %sm", minutes)
        end
    else
        label:setText(formatted_seconds .. "s")
        tooltip = tr("Time remaining: %s seconds", seconds)
    end

    if hours < 1 then
        label:setColor("$var-text-cip-store-red")
    elseif hours < 3 then
        label:setColor("#f8db38")
    end
    label:setVisible(true)

    return tooltip
end

local function updateImbuementSlots(trackedItem, item)
    local maxDuration = 0
    local imbuementSlotsPanel = trackedItem.imbuementSlots

    -- Create a table to track which slots are active
    local activeSlots = {}

    -- Use pairs instead of ipairs to handle non-sequential keys
    for _, imbuementSlot in pairs(item['slots']) do
        if imbuementSlot['id'] ~= nil then
            activeSlots[imbuementSlot['id']] = imbuementSlot
        end
    end

    local totalSlots = item['totalSlots'] or 0

    -- Clear all existing slots first to avoid indexing issues
    local existingChildren = imbuementSlotsPanel:getChildren()
    for _, child in ipairs(existingChildren) do
        child:destroy()
    end

    -- Recreate all slots in order
    for slotIndex = 0, totalSlots - 1 do
        local imbuementSlot = activeSlots[slotIndex]

        if imbuementSlot then
            local tooltip = (imbuementSlot['name'] or "")
            -- Active slot with imbuement
            local slot = g_ui.createWidget('ImbuementSlot')
            slot:setId('slot' .. slotIndex)
            slot:setImageSource("/images/game/imbuing/imbuement-icons-64")
            local iconId = tonumber(imbuementSlot['iconId']) or 1
            slot:setImageClip(getFramePosition(iconId, 64, 64, 21) .. " 64 64")
            slot:setMarginLeft(3)
            imbuementSlotsPanel:addChild(slot)

            -- Set duration AFTER adding to panel to ensure label is fully initialized
            local durationLabel = slot:getChildById('duration')
            if durationLabel then
                tooltip = tooltip .. "\n\n" .. setDuration(durationLabel, imbuementSlot['duration'])
            end

            if imbuementSlot['duration'] > maxDuration then
                maxDuration = imbuementSlot['duration']
            end

            if tooltip ~= "" then
                slot:setTooltip(tooltip)
            end
        else
            -- Inactive slot placeholder
            local inactiveSlot = g_ui.createWidget('ImbuementSlotInactive')
            inactiveSlot:setId('inactiveSlot' .. slotIndex)
            inactiveSlot:setMarginLeft(3)
            imbuementSlotsPanel:addChild(inactiveSlot)
        end
    end

    return maxDuration
end

local function createTrackedItem(item)
    local trackedItem = g_ui.createWidget('InventoryItem')
    trackedItem.item:setItem(item['item'])
    ItemsDatabase.setTier(trackedItem.item, trackedItem.item:getItem())
    trackedItem.item:setVirtual(true)

    local maxDuration = updateImbuementSlots(trackedItem, item)
    return trackedItem, maxDuration
end

local function updateTrackedItem(trackedItem, item)
    trackedItem.item:setItem(item['item'])
    ItemsDatabase.setTier(trackedItem.item, trackedItem.item:getItem())
    return updateImbuementSlots(trackedItem, item)
end

local function shouldShowItem(item, duration)
    -- Count only slots with duration > 0 as truly active
    local activeSlotCount = 0
    for _, slot in pairs(item['slots']) do
        if slot['duration'] and slot['duration'] > 0 then
            activeSlotCount = activeSlotCount + 1
        end
    end

    local hasActiveImbuements = activeSlotCount > 0 and duration > 0
    local hasSlots = (item['totalSlots'] or 0) > 0

    -- Show items based on filters
    if not hasActiveImbuements and hasSlots and not getFilter('showNoImbuements') then
        return false
    elseif not hasActiveImbuements and not hasSlots then
        return false
    elseif duration > 0 and duration < DURATION_ONE_HOUR and not getFilter('showLessThan1h') then
        return false
    elseif duration >= DURATION_ONE_HOUR and duration < DURATION_THREE_HOURS and not getFilter('showBetween1hAnd3h') then
        return false
    elseif duration >= DURATION_THREE_HOURS and not getFilter('showMoreThan3h') then
        return false
    end
    return true
end

local function onUpdateImbuementTracker(items)
    local trackedItems = getTrackedItems(items)
    local currentSlots = {}
    local itemsBySlot = {}

    -- Index items by slot for quick lookup
    for _, item in ipairs(trackedItems) do
        itemsBySlot[item['slot']] = item
    end

    -- Process items in the defined order
    for orderIndex, slot in ipairs(IMBUEMENTTRACKER_SLOTS_ORDER) do
        local item = itemsBySlot[slot]
        if item then
            currentSlots[slot] = true

            local existingWidget = trackedItemWidgets[slot]
            local duration

            if existingWidget then
                -- Update existing widget
                duration = updateTrackedItem(existingWidget, item)
            else
                -- Create new widget
                existingWidget, duration = createTrackedItem(item)
                existingWidget:setId('trackedItem_' .. slot)
                trackedItemWidgets[slot] = existingWidget
            end

            local show = shouldShowItem(item, duration)

            if show then
                local parent = existingWidget:getParent()
                if not parent then
                    -- Find correct position based on order
                    local insertIndex = 1
                    for i = 1, orderIndex - 1 do
                        local prevSlot = IMBUEMENTTRACKER_SLOTS_ORDER[i]
                        local prevWidget = trackedItemWidgets[prevSlot]
                        if prevWidget and prevWidget:getParent() and prevWidget:isVisible() then
                            insertIndex = insertIndex + 1
                        end
                    end
                    imbuementTracker.contentsPanel:insertChild(insertIndex, existingWidget)
                end
                existingWidget:setVisible(true)
            else
                existingWidget:setVisible(false)
            end
        end
    end

    -- Remove widgets for slots that no longer exist
    for slot, widget in pairs(trackedItemWidgets) do
        if not currentSlots[slot] then
            widget:destroy()
            trackedItemWidgets[slot] = nil
        end
    end
end

function Tracker.Imbuement.onMiniWindowOpen()
    if imbuementTrackerButton then
        imbuementTrackerButton:setOn(true)
    end
end

function Tracker.Imbuement.onMiniWindowClose()
    if imbuementTrackerButton then
        imbuementTrackerButton:setOn(false)
    end
end

function Tracker.Imbuement.toggle()
    if imbuementTrackerButton:isOn() then
        imbuementTrackerButton:setOn(false)
        imbuementTracker:close()
    else
        if not imbuementTracker:getParent() then
            local panel = modules.game_interface.findContentPanelAvailable(imbuementTracker,
                imbuementTracker:getMinimumHeight())
            if not panel then
                return
            end

            panel:addChild(imbuementTracker)
        end
        imbuementTracker:open()
        imbuementTrackerButton:setOn(true)
    end
    g_game.imbuementDurations(imbuementTrackerButton:isOn())
end

function Tracker.Imbuement.init()
    connect(g_game, {
        onGameStart = Tracker.Imbuement.onGameStart,
        onGameEnd = Tracker.Imbuement.onGameEnd,
        onUpdateImbuementTracker = onUpdateImbuementTracker
    })

    imbuementTracker = g_ui.createWidget('ImbuementTracker')

    -- Set minimum height for imbuement tracker window
    imbuementTracker:setContentMinimumHeight(55)
    imbuementTracker:setContentMaximumHeight(205)

    -- Hide toggleFilterButton and adjust button positioning
    local toggleFilterButton = imbuementTracker:recursiveGetChildById('toggleFilterButton')
    if toggleFilterButton then
        toggleFilterButton:setVisible(false)
        toggleFilterButton:setOn(false)
    end

    -- Hide newWindowButton
    local newWindowButton = imbuementTracker:recursiveGetChildById('newWindowButton')
    if newWindowButton then
        newWindowButton:setVisible(false)
    end

    -- Make sure contextMenuButton is visible and set up its positioning and click handler
    local contextMenuButton = imbuementTracker:recursiveGetChildById('contextMenuButton')
    local lockButton = imbuementTracker:recursiveGetChildById('lockButton')
    local minimizeButton = imbuementTracker:recursiveGetChildById('minimizeButton')

    if contextMenuButton then
        contextMenuButton:setVisible(true)

        -- Position contextMenuButton where toggleFilterButton was (similar to containers without upButton)
        if minimizeButton then
            contextMenuButton:breakAnchors()
            contextMenuButton:addAnchor(AnchorTop, minimizeButton:getId(), AnchorTop)
            contextMenuButton:addAnchor(AnchorRight, minimizeButton:getId(), AnchorLeft)
            contextMenuButton:setMarginRight(7)
            contextMenuButton:setMarginTop(0)
        end

        -- Position lockButton to the left of contextMenu
        if lockButton then
            lockButton:breakAnchors()
            lockButton:addAnchor(AnchorTop, contextMenuButton:getId(), AnchorTop)
            lockButton:addAnchor(AnchorRight, contextMenuButton:getId(), AnchorLeft)
            lockButton:setMarginRight(2)
            lockButton:setMarginTop(0)
        end

        contextMenuButton.onClick = function(widget, mousePos, mouseButton)
            local menu = g_ui.createWidget('ImbuementTrackerMenu')
            menu:setGameMenu(true)
            for _, choice in ipairs(menu:getChildren()) do
                local choiceId = choice:getId()
                choice:setChecked(getFilter(choiceId))
                choice.onCheckChange = function()
                    setFilter(choiceId)
                    menu:destroy()
                end
            end
            menu:display(mousePos)
            return true
        end
    end

    imbuementTracker:setup()
    imbuementTracker:hide()
end

function Tracker.Imbuement.terminate()
    disconnect(g_game, {
        onGameStart = Tracker.Imbuement.onGameStart,
        onGameEnd = Tracker.Imbuement.onGameEnd,
        onUpdateImbuementTracker = onUpdateImbuementTracker
    })

    -- Clear widget cache
    trackedItemWidgets = {}

    if imbuementTrackerButton then
        imbuementTrackerButton:destroy()
        imbuementTrackerButton = nil
    end
    imbuementTracker:destroy()
end

function Tracker.Imbuement.onGameStart()
    if g_game.getClientVersion() >= 1100 then
        imbuementTrackerButton = modules.game_mainpanel.addToggleButton('imbuementTrackerButton', tr('Imbuement Tracker'),
            '/images/options/button_imbuementtracker', Tracker.Imbuement.toggle, false, 16)

        -- Restore imbuement tracker position from saved settings (with delay to ensure panels are ready)
        scheduleEvent(function()
            if imbuementTracker then
                imbuementTracker:restorePosition()
            end
            g_game.imbuementDurations(imbuementTrackerButton:isOn())
            loadFilters()
        end, 150)
    end
end

function Tracker.Imbuement.onGameEnd()
    -- Clear widget cache
    for slot, widget in pairs(trackedItemWidgets) do
        if widget then
            widget:destroy()
        end
    end
    trackedItemWidgets = {}
    saveFilters()
end
