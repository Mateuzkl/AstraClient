local masteredRaceIds = {}
local soulsealEntries = {}
local selectedIndex = nil
local soulsealWindow = nil
local gameEvents

local function getSoulsealBalance()
    local player = g_game.getLocalPlayer()
    return player and player:getResourceBalance(ResourceTypes.SOULSEAL_POINTS) or 0
end

local function setSoulsealBalance(balance)
    if soulsealWindow then
        soulsealWindow.balancePanel.balanceLabel:setText(comma_value(balance))
    end
end

function init()
    soulsealWindow = g_ui.displayUI('game_soulseal')
    UIModalOverlay.register(soulsealWindow)
    soulsealWindow:hide()

    soulsealWindow.filterPanel.searchEdit.onTextChange = function()
        refreshList()
    end

    soulsealWindow:recursiveGetChildById('clearSearchBtn').onClick = function()
        soulsealWindow:recursiveGetChildById('searchEdit'):setText('')
    end

    soulsealWindow.filterPanel.categoryCombo.onOptionChange = function()
        refreshList()
    end

    soulsealWindow.selectedPanel.fightBtn.onClick = function()
        if not selectedIndex or not soulsealEntries[selectedIndex] then
            return
        end

        local entry = soulsealEntries[selectedIndex]

        local confirmBox
        local function destroy()
            if confirmBox then
                confirmBox:destroy()
                confirmBox = nil
                show()
            end
        end

        local function onConfirm()
            if confirmBox then
                confirmBox:destroy()
                confirmBox = nil
            end
            g_game.soulsealFightAction(entry.raceId)
            hide()
        end

        hide()
        local msg = string.format('Are you sure you want to fight "%s" for %d soulseal points?',
            string.capitalize(entry.name or "unknown"), entry.soulsealPoints or 0)
        confirmBox = displayGeneralBox('Confirm', msg, {
            { text = 'Ok',     callback = onConfirm },
            { text = 'Cancel', callback = destroy },
            anchor = AnchorHorizontalCenter,
        }, onConfirm, destroy)
    end

    connect(g_game, {
        onGameStart = online,
        onGameEnd = offline,
    })

    if g_game.isOnline() then
        online()
    end
end

function terminate()
    disconnect(g_game, {
        onGameStart = online,
        onGameEnd = offline,
    })

    offline()

    UIModalOverlay.destroy(soulsealWindow)
    soulsealWindow:destroy()
    soulsealWindow = nil
end

function online()
    connect(g_game, gameEvents)
end

function offline()
    disconnect(g_game, gameEvents)
    soulsealEntries = {}
    masteredRaceIds = {}
    selectedIndex = nil
    if soulsealWindow then
        soulsealWindow:hide()
    end
end

function onSoulsealsData(entries, balance)
    selectedIndex = nil
    masteredRaceIds = {}
    soulsealEntries = {}

    if type(entries) == "table" and #entries > 0 then
        for _, entry in ipairs(entries) do
            local raceData = g_things.registerRaceDataFromPacket and g_things.registerRaceDataFromPacket(entry) or nil
            local raceId = tonumber(entry.raceId) or 0
            local name = (raceData and raceData.name) or entry.name or "unknown"
            local cost = tonumber(entry.cost) or 0
            local stars = tonumber(entry.stars) or 0
            local mastered = tonumber(entry.mastered) or tonumber(entry.done) or 0

            if mastered == 1 then
                masteredRaceIds[raceId] = true
            end

            table.insert(soulsealEntries, {
                raceId = raceId,
                name = name,
                soulsealPoints = cost,
                stars = stars,
                category = stars,  -- use stars as category fallback
                done = mastered == 1,
            })
        end
    end

    local currentBalance = tonumber(balance)
    if currentBalance == nil then
        currentBalance = getSoulsealBalance()
    end
    setSoulsealBalance(currentBalance)

    show()
    refreshList()
end

function onResourceBalance(resourceType, balance)
    if resourceType ~= ResourceTypes.SOULSEAL_POINTS then
        return
    end
    setSoulsealBalance(balance)
end

gameEvents = {
    onSoulsealsData = onSoulsealsData,
    onResourceBalance = onResourceBalance,
}

function show()
    soulsealWindow:show()
    soulsealWindow:raise()
    soulsealWindow:focus()
end

function request()
    if g_game.soulsealRequest then
        g_game.soulsealRequest()
    end
end

function hide()
    soulsealWindow.filterPanel.searchEdit:setText('')
    soulsealWindow:hide()
end

local function getFilteredEntries()
    local searchText = soulsealWindow.filterPanel.searchEdit:getText():lower()
    local categoryIndex = soulsealWindow.filterPanel.categoryCombo:getCurrentIndex()

    local filtered = {}
    for i, entry in ipairs(soulsealEntries) do
        local matchSearch = searchText == "" or (entry.name and entry.name:lower():find(searchText, 1, true))
        local matchCategory = categoryIndex == 1 or entry.category == (categoryIndex - 1)
        if matchSearch and matchCategory then
            table.insert(filtered, { index = i, entry = entry })
        end
    end
    table.sort(filtered, function(a, b)
        if a.entry.done ~= b.entry.done then
            return not a.entry.done
        end
        return (a.entry.name or ""):lower() < (b.entry.name or ""):lower()
    end)
    return filtered
end

local function updateSelected()
    local selectedPanel = soulsealWindow.selectedPanel

    local creatureWidget = selectedPanel:recursiveGetChildById('selectedCreature')
    local costLabel = selectedPanel:recursiveGetChildById('costLabel')

    if not selectedIndex or not soulsealEntries[selectedIndex] then
        creatureWidget:setVisible(false)
        costLabel:setText('0')
        selectedPanel.fightBtn:setEnabled(false)
        return
    end

    local entry = soulsealEntries[selectedIndex]

    local raceData = g_things.getRaceData(entry.raceId)
    if raceData and raceData.outfit then
        creatureWidget:setOutfit(raceData.outfit)
        creatureWidget:setVisible(true)
    end

    costLabel:setText(tostring(entry.soulsealPoints or 0))

    local canFight = not entry.done
    selectedPanel.fightBtn:setEnabled(canFight)

    local list = soulsealWindow.listPanel.monsterList
    for childIndex, child in ipairs(list:getChildren()) do
        if child:getId() == 'row_' .. selectedIndex then
            child:setBackgroundColor('#ffffff22')
        else
            child:setBackgroundColor(child.baseColor or '#00000000')
        end
    end
end

local function selectEntry(index)
    selectedIndex = index
    updateSelected()
end

function refreshList()
    local list = soulsealWindow.listPanel.monsterList
    list:destroyChildren()

    local filtered = getFilteredEntries()

    for i, item in ipairs(filtered) do
        if not soulsealWindow then
            break
        end

        local entry = item.entry
        local row = g_ui.createWidget('SoulsealRow', list)
        row:setId('row_' .. item.index)
        row.nameLabel:setText(string.capitalize(entry.name or "unknown"))
        row.pointsLabel:setText(tostring(entry.soulsealPoints or 0))
        row.raceId = entry.raceId

        local color = i % 2 == 0 and '$var-textlist-even' or '$var-textlist-odd'
        row.baseColor = color
        row:setBackgroundColor(color)

        if entry.done then
            row.animusMastery:setVisible(true)
        end

        local idx = item.index
        row.onClick = function()
            selectEntry(idx)
        end

        local raceData = g_things.getRaceData(entry.raceId)
        if raceData and raceData.outfit then
            row.creature:setOutfit(raceData.outfit)
            row.creature:setStaticWalking(true)
        end
    end

    updateSelected()
end
