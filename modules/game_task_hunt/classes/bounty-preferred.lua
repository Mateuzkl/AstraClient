BountyPreferred = {}

-- Action types (must match BountyPreferredActionType on server)
local ACTION_REQUEST = 0
local ACTION_BUY_SLOT = 1
local ACTION_SET_PREFERRED = 2
local ACTION_SET_UNWANTED = 3
local ACTION_REMOVE_PREFERRED = 4
local ACTION_REMOVE_UNWANTED = 5

local preferredWindow = nil
local cachedSlots = {}
local cachedRemoveCost = 0
local cachedAvailableRaceIds = {}
local selectedRaceId = 0
local monsterListRenderEvent = nil
local monsterListRenderToken = 0

local MONSTER_LIST_BATCH_SIZE = 25

local function cancelMonsterListRender()
    if monsterListRenderEvent then
        removeEvent(monsterListRenderEvent)
        monsterListRenderEvent = nil
    end

    monsterListRenderToken = monsterListRenderToken + 1
    return monsterListRenderToken
end

function BountyPreferred.init()
    if not taskHuntWindow then return end

    local btn = taskHuntWindow:recursiveGetChildById('preferredList')
    if btn then
        btn.onClick = function()
            BountyPreferred.show()
        end
    end
end

function BountyPreferred.show()
    if not preferredWindow then
        preferredWindow = g_ui.createWidget('BountyPreferredWindow', rootWidget)
        preferredWindow:setAutoFocusPolicy(AutoFocusNone)

        -- Center on taskHuntWindow
        if taskHuntWindow then
            local twPos = taskHuntWindow:getPosition()
            local twSize = taskHuntWindow:getSize()
            local pwSize = preferredWindow:getSize()
            local x = twPos.x + math.floor((twSize.width - pwSize.width) / 2)
            local y = twPos.y + math.floor((twSize.height - pwSize.height) / 2)
            preferredWindow:setPosition({ x = x, y = y })
        end

        -- Wire search
        local searchEdit = preferredWindow:recursiveGetChildById('searchEdit')
        if searchEdit then
            searchEdit.onTextChange = function()
                BountyPreferred.populateMonsterList()
            end
        end

        local clearBtn = preferredWindow:recursiveGetChildById('clearSearchBtn')
        if clearBtn then
            clearBtn.onClick = function()
                local edit = preferredWindow:recursiveGetChildById('searchEdit')
                if edit then edit:setText('') end
            end
        end

        -- Wire close
        local closeBtn = preferredWindow:recursiveGetChildById('closeBtn')
        if closeBtn then
            closeBtn.onClick = function()
                BountyPreferred.terminate()
            end
        end

        -- Escape key closes
        connect(preferredWindow, {
            onEscape = function()
                BountyPreferred.terminate()
            end
        })
    end

    -- Request data from server
    g_game.bountyPreferredAction(ACTION_REQUEST, 0, 0)

    preferredWindow:show()
    preferredWindow:raise()
    preferredWindow:focus()
end

function BountyPreferred.hide()
    if preferredWindow then
        preferredWindow:hide()
    end
end

function BountyPreferred.terminate()
    cancelMonsterListRender()

    if preferredWindow then
        preferredWindow:destroy()
        preferredWindow = nil
    end
    selectedRaceId = 0
    cachedSlots = {}
    cachedRemoveCost = 0
    cachedAvailableRaceIds = {}
end

function BountyPreferred.onServerData(slots, removeCost, availableRaceIds)
    cachedSlots = slots or {}
    cachedRemoveCost = removeCost
    if availableRaceIds ~= nil then
        cachedAvailableRaceIds = availableRaceIds
    end

    if preferredWindow and preferredWindow:isVisible() then
        BountyPreferred.populateMonsterList()
        BountyPreferred.populateSlots()
    end
end

-- ─── Left panel: Monster list ─────────────────────────────────────────

function BountyPreferred.populateMonsterList()
    if not preferredWindow then return end

    local monsterList = preferredWindow:recursiveGetChildById('monsterList')
    if not monsterList then return end

    local renderToken = cancelMonsterListRender()
    monsterList:destroyChildren()
    selectedRaceId = 0
    BountyPreferred.updateAssignButtons()

    -- Get search filter
    local searchEdit = preferredWindow:recursiveGetChildById('searchEdit')
    local filter = ''
    if searchEdit then
        filter = searchEdit:getText():lower()
    end

    -- Collect raceIds already assigned as preferred or unwanted
    local usedRaceIds = {}
    for _, slotData in ipairs(cachedSlots) do
        local prefId = tonumber(slotData.preferred) or 0
        local unwId = tonumber(slotData.unwanted) or 0
        if prefId > 0 then usedRaceIds[prefId] = true end
        if unwId > 0 then usedRaceIds[unwId] = true end
    end

    -- Build sorted list of monsters (excluding already assigned)
    local sortedMonsters = {}
    for _, raceId in ipairs(cachedAvailableRaceIds) do
        if not usedRaceIds[raceId] then
            local raceData = g_things.getRaceData(raceId)
            local name = raceData and raceData.name or 'Unknown'
            name = name:capitalize()

            if filter == '' or name:lower():find(filter, 1, true) then
                table.insert(sortedMonsters, { raceId = raceId, name = name, raceData = raceData })
            end
        end
    end

    table.sort(sortedMonsters, function(a, b) return a.name < b.name end)

    if searchEdit then
        searchEdit:focus()
    end

    local index = 1
    local function appendBatch()
        if renderToken ~= monsterListRenderToken or not preferredWindow or preferredWindow:isDestroyed() or
            not monsterList or monsterList:isDestroyed() then
            return
        end

        local lastIndex = math.min(index + MONSTER_LIST_BATCH_SIZE - 1, #sortedMonsters)
        for i = index, lastIndex do
            local monsterData = sortedMonsters[i]
            local row = g_ui.createWidget('BountyPreferredMonsterRow', monsterList)
            local bgColor = (i % 2 == 1) and '$var-textlist-odd' or '$var-textlist-even'
            row:setBackgroundColor(bgColor)
            row.rowColor = bgColor
            row.raceId = monsterData.raceId

            local creature = row:recursiveGetChildById('creature')
            if creature and monsterData.raceData and monsterData.raceData.outfit then
                creature:setOutfit(monsterData.raceData.outfit)
                creature:setStaticWalking(true)
                creature:setTooltip(monsterData.name)
                creature:setPhantom(false)
            end

            local nameLabel = row:recursiveGetChildById('nameLabel')
            if nameLabel then
                nameLabel:setText(monsterData.name)
            end

            row.onFocusChange = function(widget, focused)
                if focused then
                    widget:setBackgroundColor('$var-textlist-selected')
                    selectedRaceId = widget.raceId
                    BountyPreferred.updateAssignButtons()
                else
                    widget:setBackgroundColor(widget.rowColor)
                end
            end
        end

        index = lastIndex + 1
        if index <= #sortedMonsters then
            monsterListRenderEvent = scheduleEvent(appendBatch, 1)
        else
            monsterListRenderEvent = nil
        end
    end

    appendBatch()
end

function BountyPreferred.updateAssignButtons()
    if not preferredWindow then return end
    local enabled = selectedRaceId > 0
    for i = 1, 5 do
        local slot = preferredWindow:recursiveGetChildById('slot' .. i)
        if slot then
            local btn = slot:recursiveGetChildById('assignPreferredBtn')
            if btn then btn:setEnabled(enabled) end
            btn = slot:recursiveGetChildById('assignUnwantedBtn')
            if btn then btn:setEnabled(enabled) end
        end
    end
end

-- ─── Right panel: Slots ───────────────────────────────────────────────

function BountyPreferred.populateSlots()
    if not preferredWindow or not preferredWindow:isVisible() then return end

    local nextLockedSlot = nil
    local nextLockedPrice = 0
    for _, slotData in ipairs(cachedSlots) do
        if tonumber(slotData.locked) == 1 then
            nextLockedSlot = tonumber(slotData.slot) or 0
            nextLockedPrice = tonumber(slotData.price) or 0
            break
        end
    end

    for _, slotData in ipairs(cachedSlots) do
        local slotNum = tonumber(slotData.slot) or 0
        local locked = tonumber(slotData.locked) == 1
        local preferredId = tonumber(slotData.preferred) or 0
        local unwantedId = tonumber(slotData.unwanted) or 0
        local price = tonumber(slotData.price) or 0

        local slotWidget = preferredWindow:recursiveGetChildById('slot' .. slotNum)
        if not slotWidget then goto continue end

        -- Get all children
        local preferredCol = slotWidget:recursiveGetChildById('preferredCol')
        local unwantedCol = slotWidget:recursiveGetChildById('unwantedCol')
        local lockedContainer = slotWidget:recursiveGetChildById('lockedContainer')

        if locked then
            -- Hide unlocked children, show locked container
            if preferredCol then preferredCol:setVisible(false) end
            if unwantedCol then unwantedCol:setVisible(false) end
            if lockedContainer then
                lockedContainer:setVisible(true)

                local unlockBtn = lockedContainer:recursiveGetChildById('unlockBtn')
                if unlockBtn then
                    local isNextLockedSlot = slotNum == nextLockedSlot
                    unlockBtn.onClick = nil
                    if isNextLockedSlot then
                        local slotToUnlock = nextLockedSlot
                        unlockBtn.onClick = function()
                            g_game.bountyPreferredAction(ACTION_BUY_SLOT, slotToUnlock, 0)
                        end
                    end

                    -- Disable unlock button if player lacks bounty task points
                    local player = g_game.getLocalPlayer()
                    local balance = player and player:getResourceBalance(ResourceTypes.BOUNTY_TASK_POINTS) or 0
                    unlockBtn:setEnabled(isNextLockedSlot and balance >= nextLockedPrice)
                end

                local costLabel = lockedContainer:recursiveGetChildById('unlockCostLabel')
                if costLabel then
                    costLabel:setText(tostring(price))
                end
            end
        else
            -- Hide locked container, show unlocked children
            if lockedContainer then lockedContainer:setVisible(false) end
            if preferredCol then preferredCol:setVisible(true) end
            if unwantedCol then unwantedCol:setVisible(true) end

            -- Preferred column
            BountyPreferred.setupSlotColumn(preferredCol, slotNum, preferredId, 'preferred')

            -- Unwanted column
            BountyPreferred.setupSlotColumn(unwantedCol, slotNum, unwantedId, 'unwanted')
        end

        ::continue::
    end
end

function BountyPreferred.setupSlotColumn(col, slotNum, raceId, colType)
    if not col then return end

    local isPreferred = (colType == 'preferred')
    local prefix = isPreferred and 'preferred' or 'unwanted'

    local creatureFrame = col:recursiveGetChildById(prefix .. 'CreatureFrame')
    local creatureWidget = col:recursiveGetChildById(prefix .. 'Creature')
    local assignBtn = col:recursiveGetChildById('assign' .. (isPreferred and 'Preferred' or 'Unwanted') .. 'Btn')
    local clearBtn = col:recursiveGetChildById('clear' .. (isPreferred and 'Preferred' or 'Unwanted') .. 'Btn')
    local clearCost = col:recursiveGetChildById('clear' .. (isPreferred and 'Preferred' or 'Unwanted') .. 'Cost')

    local hasMonster = raceId > 0

    -- Creature frame: show creature if assigned, empty if not
    if creatureFrame then creatureFrame:setVisible(true) end
    if creatureWidget and hasMonster then
        local raceData = g_things.getRaceData(raceId)
        if raceData and raceData.outfit then
            creatureWidget:setOutfit(raceData.outfit)
        end
        local name = raceData and raceData.name or 'Unknown'
        creatureWidget:setTooltip(name:capitalize())
        creatureWidget:setPhantom(false)
        creatureWidget:setVisible(true)
    elseif creatureWidget then
        creatureWidget:setTooltip('')
        creatureWidget:setVisible(false)
    end

    -- Assign button: visible when no monster assigned, disabled if none selected
    if assignBtn then
        assignBtn:setVisible(not hasMonster)
        assignBtn:setEnabled(selectedRaceId > 0)
        assignBtn.onClick = function()
            if selectedRaceId > 0 then
                local actionType = isPreferred and ACTION_SET_PREFERRED or ACTION_SET_UNWANTED
                g_game.bountyPreferredAction(actionType, slotNum, selectedRaceId)
            end
        end
    end

    -- Clear button: visible when monster assigned, check balance on click
    if clearBtn then
        clearBtn:setVisible(hasMonster)
        local player = g_game.getLocalPlayer()
        local balance = player and player:getResourceBalance(ResourceTypes.BOUNTY_TASK_POINTS) or 0
        local canAfford = balance >= cachedRemoveCost
        clearBtn:setEnabled(canAfford)
        clearBtn.onClick = function()
            local actionType = isPreferred and ACTION_REMOVE_PREFERRED or ACTION_REMOVE_UNWANTED
            g_game.bountyPreferredAction(actionType, slotNum, 0)
        end
    end

    -- Clear cost panel: visible when monster assigned
    if clearCost then
        clearCost:setVisible(hasMonster)
        local costLabel = clearCost:recursiveGetChildById('costLabel')
        if costLabel then
            costLabel:setText(tostring(cachedRemoveCost))
        end
    end
end
