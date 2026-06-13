-- Soul Seal (Soul Pit) module - ported from mehah PR #1604

local soulsealWindow = nil
local cachedEntries = {}
local selectedIndex = 0
local cachedBalance = nil

local SOULSEAL_CATEGORIES = {
    [1] = "Harmless",
    [2] = "Trivial",
    [3] = "Easy",
    [4] = "Medium",
    [5] = "Hard",
    [6] = "Challenging",
}

function init()
    connect(g_game, { onSoulsealsData = onSoulsealsData })
end

function terminate()
    disconnect(g_game, { onSoulsealsData = onSoulsealsData })
    hideWindow()
    cachedBalance = nil
end

local function getSoulsealResourceBalance()
    local player = g_game.getLocalPlayer()
    if not player then return 0 end
    if not ResourceTypes or not ResourceTypes.SOULSEAL_POINTS then return 0 end
    return tonumber(player:getResourceBalance(ResourceTypes.SOULSEAL_POINTS)) or 0
end

local function resolveSoulsealBalance(balance)
    local resolved = tonumber(balance)
    if resolved ~= nil then
        return resolved
    end
    return getSoulsealResourceBalance()
end

function onSoulsealsData(entries, balance)
    g_logger.info("[SoulSeal] Received soulseal data from server")
    cachedBalance = resolveSoulsealBalance(balance)

    if type(entries) == "table" then
        cachedEntries = {}
        for _, entry in ipairs(entries) do
            if type(entry) ~= "table" then
                local raceId = tonumber(entry) or 0
                table.insert(cachedEntries, {
                    raceId = raceId,
                    name = "Creature " .. tostring(raceId),
                    points = 0,
                    done = false,
                    category = 0,
                    outfit = nil,
                })
            else
                local raceData = g_things.registerRaceDataFromPacket and g_things.registerRaceDataFromPacket(entry) or nil
                local name = entry.name or ("Creature " .. tostring(entry.raceId or "?"))
                local points = tonumber(entry.cost) or tonumber(entry.soulsealPoints) or 0
                local done = tonumber(entry.mastered) or tonumber(entry.done) or 0
                table.insert(cachedEntries, {
                    raceId = tonumber(entry.raceId) or 0,
                    name = tostring((raceData and raceData.name) or name),
                    points = points,
                    done = done == 1,
                    category = tonumber(entry.stars) or tonumber(entry.category) or 0,
                    outfit = (raceData and raceData.outfit) or entry.outfit,
                })
            end
        end
        showWindow()
    end
end

function showWindow()
    if soulsealWindow and not soulsealWindow:isDestroyed() then
        soulsealWindow:raise()
        soulsealWindow:show()
        refreshList()
        updateBalance(cachedBalance)
        return
    end

    soulsealWindow = g_ui.loadUI("soulseal")
    if not soulsealWindow then return end

    local x = (g_window.getDisplaySize().width - soulsealWindow:getWidth()) / 2
    local y = (g_window.getDisplaySize().height - soulsealWindow:getHeight()) / 2
    soulsealWindow:setX(math.floor(x))
    soulsealWindow:setY(math.floor(y))
    soulsealWindow:show()

    local fightBtn = soulsealWindow:recursiveGetChildById("fightButton")
    if fightBtn then
        fightBtn.onClick = function() doFight() end
    end

    refreshList()
    updateBalance(cachedBalance)
end

function hideWindow()
    if soulsealWindow then
        soulsealWindow:hide()
    end
end

function refreshList()
    if not soulsealWindow or soulsealWindow:isDestroyed() then return end
    local list = soulsealWindow:recursiveGetChildById("creatureList")
    if not list then return end

    list:destroyChildren()
    selectedIndex = 0

    for i, entry in ipairs(cachedEntries) do
        local row = g_ui.createWidget('UIWidget', list)
        row:setHeight(28)
        row:setId("soulseal_" .. i)

        local label = g_ui.createWidget('UILabel', row)
        label:setX(5)
        label:setWidth(200)
        label:setHeight(28)
        label:setTextAlign(AlignLeftCenter)

        local text = entry.name
        local cat = SOULSEAL_CATEGORIES[entry.category] or ""
        if cat ~= "" then text = text .. " [" .. cat .. "]" end
        text = text .. " - " .. entry.points .. " seals"
        if entry.done then text = text .. " (DONE)" end
        label:setText(text)
        label:setColor(entry.done and '#808080' or '#c0c0c0')

        row.onClick = function()
            selectedIndex = i
            updateSelection()
        end

        row.onDoubleClick = function()
            selectedIndex = i
            if not entry.done then doFight() end
        end
    end

    updateSelection()
end

function updateSelection()
    if not soulsealWindow or soulsealWindow:isDestroyed() then return end
    local fightBtn = soulsealWindow:recursiveGetChildById("fightButton")
    if not fightBtn then return end

    if selectedIndex < 1 or selectedIndex > #cachedEntries then
        fightBtn:setEnabled(false)
        return
    end

    local entry = cachedEntries[selectedIndex]
    fightBtn:setEnabled(not entry.done)
end

function updateBalance(balance)
    if not soulsealWindow or soulsealWindow:isDestroyed() then return end
    local pointsLabel = soulsealWindow:recursiveGetChildById("pointsLabel")
    if not pointsLabel then return end

    cachedBalance = resolveSoulsealBalance(balance)
    pointsLabel:setText("Soulseals: " .. tostring(cachedBalance))
end

function doFight()
    if selectedIndex < 1 or selectedIndex > #cachedEntries then return end
    local entry = cachedEntries[selectedIndex]
    if entry.done then return end

    local raceId = entry.raceId
    if raceId <= 0 then return end

    g_logger.info("[SoulSeal] Fighting creature: " .. entry.name .. " (raceId=" .. raceId .. ")")
    g_game.soulsealFightAction(raceId)
    hideWindow()
end

-- Module API
function toggle()
    if soulsealWindow and soulsealWindow:isVisible() then
        hideWindow()
    else
        showWindow()
    end
end
