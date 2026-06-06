if not Tracker then Tracker = {} end
Tracker.Quest = {}

-- @ windows
local trackerMiniWindow = nil
local trackerButton = nil

-- variable
local settings = {}
local namePlayer = ""
local missionToQuestMap = {}
local file = "/settings/questtracking.json"
local isGameEnding = false

-- =========================================================
-- Local Functions
-- =========================================================

local function load()
    if g_resources.fileExists(file) then
        local status, result = pcall(function()
            return json.decode(g_resources.readFileContents(file))
        end)
        if not status then
            return g_logger.error(
                "Error while reading quest tracking file. To fix this problem you can delete questtracking.json. Details: " ..
                result)
        end
        return result or {}
    end
end

local function save()
    local status, result = pcall(function()
        return json.encode(settings, 2)
    end)
    if not status then
        return g_logger.error("Error while saving quest tracking settings. Data won't be saved. Details: " .. result)
    end
    if result:len() > 100 * 1024 * 1024 then
        return g_logger.error("Something went wrong, file is above 100MB, won't be saved")
    end

    local writeStatus, writeError = pcall(function()
        return g_resources.writeFileContents(file, result)
    end)

    if not writeStatus then
        g_logger.debug("Could not save quest tracking settings: " .. tostring(writeError))
    end
end

local function isIdInTracker(key, id)
    if not settings[key] then
        return false
    end
    return table.findbyfield(settings[key], 1, tonumber(id)) ~= nil
end

local function addUniqueIdQuest(key, questId, missionId, missionName, missionDescription)
    if not settings[key] then
        settings[key] = {}
    end

    if not isIdInTracker(key, missionId) then
        table.insert(settings[key],
            { tonumber(missionId), missionName, missionDescription or missionName, tonumber(questId) })
    end
end

local function removeNumber(key, id)
    if settings[key] then
        table.remove_if(settings[key], function(_, v)
            return v[1] == tonumber(id)
        end)
    end
end

local function sendQuestTracker(listToMap)
    local map = {}
    for _, entry in ipairs(listToMap) do
        map[entry[1]] = entry[2]
    end
    g_game.sendRequestTrackerQuestLog(map)
end

local function autoUntrackCompletedQuests()
    if not settings.autoUntrackCompleted or not settings[namePlayer] or not trackerMiniWindow then
        return
    end

    local removedMissionIds = {}

    if trackerMiniWindow.contentsPanel and trackerMiniWindow.contentsPanel.list then
        for i = trackerMiniWindow.contentsPanel.list:getChildCount(), 1, -1 do
            local trackerLabel = trackerMiniWindow.contentsPanel.list:getChildByIndex(i)
            if trackerLabel and trackerLabel.description then
                local description = trackerLabel.description:getText()
                local missionId = tonumber(trackerLabel:getId())

                local isCompleted = description and (
                    string.find(string.lower(description), "%(completed%)") or
                    (string.find(string.lower(description), "complete") and
                        (string.find(string.lower(description), "quest") or string.find(string.lower(description), "mission")))
                )

                if isCompleted then
                    table.insert(removedMissionIds, missionId)
                    removeNumber(namePlayer, missionId)
                    trackerLabel:destroy()
                end
            end
        end
    end

    if #removedMissionIds > 0 then
        if trackerMiniWindow.contentsPanel and trackerMiniWindow.contentsPanel.list then
            trackerMiniWindow.contentsPanel.list:getLayout():update()
        end
        save()
    end
end

local function rebuildTrackerFromSettings()
    if not trackerMiniWindow or not settings[namePlayer] then
        return
    end

    trackerMiniWindow.contentsPanel.list:destroyChildren()

    for i, entry in ipairs(settings[namePlayer]) do
        local missionId, missionName, missionDescription, questId = unpack(entry)

        if not questId or questId == 0 then
            questId = missionToQuestMap[tonumber(missionId)] or 0
        end

        local trackerLabel = g_ui.createWidget('QuestTrackerLabel', trackerMiniWindow.contentsPanel.list)
        trackerLabel:setId(tostring(missionId))
        trackerLabel.questId = questId
        trackerLabel.missionId = missionId
        trackerLabel.description:setText(missionDescription or missionName)
    end

    if settings[namePlayer] and #settings[namePlayer] > 0 then
        sendQuestTracker(settings[namePlayer])
    end

    scheduleEvent(autoUntrackCompletedQuests, 1000)
end

local function openTracker()
    if not trackerMiniWindow:getParent() then
        local panel = modules.game_interface
            .findContentPanelAvailable(trackerMiniWindow, trackerMiniWindow:getMinimumHeight())
        if not panel then
            return
        end
        panel:addChild(trackerMiniWindow)
    end
    trackerMiniWindow:open()
    trackerMiniWindow:setVisible(true)
end

local function showQuestTracker(calledFrom)
    if trackerMiniWindow then
        openTracker()
        return
    end
    trackerMiniWindow = g_ui.createWidget('QuestLogTracker')

    -- Hide all standard miniwindow buttons that we don't want
    local toggleFilterButton = trackerMiniWindow:recursiveGetChildById('toggleFilterButton')
    if toggleFilterButton then
        toggleFilterButton:setVisible(false)
    end

    local menuButton = trackerMiniWindow:getChildById('menuButton')
    if menuButton then
        menuButton:setVisible(false)
    end

    local titleWidget = trackerMiniWindow:getChildById('miniwindowTitle')
    if titleWidget then
        titleWidget:setText('Quest Tracker')
    else
        trackerMiniWindow:setText('Quest Tracker')
    end

    local iconWidget = trackerMiniWindow:getChildById('miniwindowIcon')
    if iconWidget then
        iconWidget:setImageSource('/images/topbuttons/icon-questtracker-widget')
    end

    local contextMenuButton = trackerMiniWindow:recursiveGetChildById('contextMenuButton')
    local minimizeButton = trackerMiniWindow:recursiveGetChildById('minimizeButton')

    if contextMenuButton and minimizeButton then
        contextMenuButton:setVisible(true)
        contextMenuButton:breakAnchors()
        contextMenuButton:addAnchor(AnchorTop, minimizeButton:getId(), AnchorTop)
        contextMenuButton:addAnchor(AnchorRight, minimizeButton:getId(), AnchorLeft)
        contextMenuButton:setMarginRight(7)
        contextMenuButton:setMarginTop(0)
        contextMenuButton:setSize({ width = 12, height = 12 })
    end

    local newWindowButton = trackerMiniWindow:recursiveGetChildById('newWindowButton')

    if newWindowButton and contextMenuButton then
        newWindowButton:setVisible(true)
        newWindowButton:breakAnchors()
        newWindowButton:addAnchor(AnchorTop, contextMenuButton:getId(), AnchorTop)
        newWindowButton:addAnchor(AnchorRight, contextMenuButton:getId(), AnchorLeft)
        newWindowButton:setMarginRight(2)
        newWindowButton:setMarginTop(0)
    end

    local lockButton = trackerMiniWindow:recursiveGetChildById('lockButton')

    if lockButton and newWindowButton then
        lockButton:breakAnchors()
        lockButton:addAnchor(AnchorTop, newWindowButton:getId(), AnchorTop)
        lockButton:addAnchor(AnchorRight, newWindowButton:getId(), AnchorLeft)
        lockButton:setMarginRight(2)
        lockButton:setMarginTop(0)
    end

    -- Context menu
    if contextMenuButton then
        contextMenuButton.onClick = function(widget, mousePos)
            local menu = g_ui.createWidget('PopupMenu')
            menu:setGameMenu(true)
            menu:addOption('Remove All quest', function()
                if settings[namePlayer] then
                    table.clear(settings[namePlayer])
                    table.clear(missionToQuestMap)
                    sendQuestTracker(settings[namePlayer])
                    trackerMiniWindow.contentsPanel.list:destroyChildren()

                    -- Update quest log checkbox if open
                    if modules.game_questlog and modules.game_questlog.updateTrackerCheckbox then
                        modules.game_questlog.updateTrackerCheckbox(nil, false)
                    end

                    trackerMiniWindow.contentsPanel.list:getLayout():enableUpdates()
                    trackerMiniWindow.contentsPanel.list:getLayout():update()
                    save()
                end
            end)
            menu:addOption('Remove completed quests', function()
                if settings[namePlayer] then
                    local removedMissionIds = {}

                    for i, entry in ipairs(settings[namePlayer]) do
                        local missionId, missionName, missionDescription, questId = unpack(entry)
                        local isCompleted = false

                        if missionName and string.find(string.lower(missionName), "%(completed%)") then
                            isCompleted = true
                        end

                        if not isCompleted and missionDescription and string.find(string.lower(missionDescription), "%(completed%)") then
                            isCompleted = true
                        end

                        if not isCompleted and trackerMiniWindow.contentsPanel and trackerMiniWindow.contentsPanel.list then
                            local trackerLabel = trackerMiniWindow.contentsPanel.list:getChildById(tostring(missionId))
                            if trackerLabel and trackerLabel.description then
                                local trackerText = trackerLabel.description:getText()
                                if trackerText and string.find(string.lower(trackerText), "%(completed%)") then
                                    isCompleted = true
                                end
                            end
                        end

                        if isCompleted then
                            table.insert(removedMissionIds, missionId)
                        end
                    end

                    if #removedMissionIds > 0 then
                        for j = #settings[namePlayer], 1, -1 do
                            local checkMissionId = settings[namePlayer][j][1]
                            for _, removedId in ipairs(removedMissionIds) do
                                if checkMissionId == removedId then
                                    table.remove(settings[namePlayer], j)
                                    break
                                end
                            end
                        end

                        for _, missionId in ipairs(removedMissionIds) do
                            if missionToQuestMap[tonumber(missionId)] then
                                missionToQuestMap[tonumber(missionId)] = nil
                            end
                        end

                        sendQuestTracker(settings[namePlayer])

                        for _, missionId in ipairs(removedMissionIds) do
                            local trackerLabel = trackerMiniWindow.contentsPanel.list:getChildById(tostring(missionId))
                            if trackerLabel then
                                trackerLabel:destroy()
                            end
                        end

                        trackerMiniWindow.contentsPanel.list:getLayout():enableUpdates()
                        trackerMiniWindow.contentsPanel.list:getLayout():update()
                        save()
                    end
                end
            end)
            menu:addSeparator()
            menu:addCheckBox('Automatically track new quests', settings.autoTrackNewQuests or false,
                function(widget, checked)
                    settings.autoTrackNewQuests = checked
                    save()
                end)
            menu:addCheckBox('Automatically untrack completed quests', settings.autoUntrackCompleted or false,
                function(widget, checked)
                    settings.autoUntrackCompleted = checked
                    save()

                    if checked then
                        scheduleEvent(function()
                            local function periodicAutoUntrack()
                                autoUntrackCompletedQuests()
                                if settings.autoUntrackCompleted then
                                    scheduleEvent(periodicAutoUntrack, 30000)
                                end
                            end
                            periodicAutoUntrack()
                        end, 1000)
                    end
                end)

            menu:display(mousePos)
            return true
        end
    end

    -- Open Quest Log button
    if newWindowButton then
        newWindowButton.onClick = function()
            if modules.game_questlog and modules.game_questlog.show then
                modules.game_questlog.show()
            end
            return true
        end
    end

    trackerMiniWindow:setContentMinimumHeight(80)
    trackerMiniWindow:setup()

    -- Rebuild tracker from saved settings when first created
    if settings[namePlayer] and #settings[namePlayer] > 0 then
        rebuildTrackerFromSettings()
    end

    -- Try to restore position from saved settings first
    local restored = false
    if trackerMiniWindow.restorePosition then
        restored = trackerMiniWindow:restorePosition()
    end

    -- Decide open/close based on saved trackerOpen state
    local shouldOpen = settings.trackerOpen

    if shouldOpen == false then
        trackerMiniWindow:close(true)
    else
        if not restored then
            openTracker()
            -- Retry restorePosition after panels are fully set up
            scheduleEvent(function()
                if trackerMiniWindow and trackerMiniWindow.restorePosition then
                    trackerMiniWindow:restorePosition()
                end
            end, 500)
        else
            trackerMiniWindow:open(true)
        end
    end

    -- Set up periodic auto-untrack check
    if settings.autoUntrackCompleted then
        scheduleEvent(function()
            local function periodicAutoUntrack()
                autoUntrackCompletedQuests()
                if settings.autoUntrackCompleted then
                    scheduleEvent(periodicAutoUntrack, 30000)
                end
            end
            periodicAutoUntrack()
        end, 5000)
    end
end

-- =========================================================
-- Server event handlers
-- =========================================================

local function onQuestTracker(remainingQuests, missions)
    if not trackerMiniWindow then
        showQuestTracker("onQuestTracker")
    end

    if not missions or type(missions[1]) ~= "table" then
        if settings[namePlayer] and #settings[namePlayer] > 0 then
            return
        end
        trackerMiniWindow.contentsPanel.list:destroyChildren()
        return
    end

    for index, mission in ipairs(missions) do
        local questId, missionId, questName, missionName, missionDesc = unpack(mission)

        missionToQuestMap[tonumber(missionId)] = tonumber(questId)

        local isTracked = false
        if settings[namePlayer] then
            for _, entry in ipairs(settings[namePlayer]) do
                if entry[1] == tonumber(missionId) then
                    isTracked = true
                    break
                end
            end
        end

        if isTracked then
            local trackerLabel = trackerMiniWindow.contentsPanel.list:getChildById(tostring(missionId))

            if not trackerLabel then
                trackerLabel = g_ui.createWidget('QuestTrackerLabel', trackerMiniWindow.contentsPanel.list)
                trackerLabel:setId(tostring(missionId))
            end

            trackerLabel.questId = questId
            trackerLabel.missionId = missionId
            trackerLabel.description:setText(missionDesc or missionName)

            for i, entry in ipairs(settings[namePlayer]) do
                if entry[1] == tonumber(missionId) then
                    settings[namePlayer][i] = { tonumber(missionId), missionName, missionDesc or missionName, questId }
                    break
                end
            end
            save()
        end
    end

    if settings.autoUntrackCompleted then
        scheduleEvent(autoUntrackCompletedQuests, 500)
    end
end

local function onUpdateQuestTracker(questId, missionId, questName, missionName, missionDesc)
    if not trackerMiniWindow then
        return
    end

    local trackerLabel = trackerMiniWindow.contentsPanel.list:getChildById(tostring(missionId))
    if trackerLabel then
        trackerLabel.description:setText(missionDesc or missionName)
        trackerLabel.questId = questId
        trackerLabel.missionId = missionId

        if settings[namePlayer] then
            for i, entry in ipairs(settings[namePlayer]) do
                if entry[1] == tonumber(missionId) then
                    settings[namePlayer][i] = { tonumber(missionId), missionName, missionDesc or missionName, questId }
                    save()
                    break
                end
            end
        end

        if settings.autoUntrackCompleted then
            local isCompleted = missionDesc and (
                string.find(string.lower(missionDesc), "%(completed%)") or
                (string.find(string.lower(missionDesc), "complete") and
                    (string.find(string.lower(missionDesc), "quest") or string.find(string.lower(missionDesc), "mission")))
            )

            if isCompleted then
                removeNumber(namePlayer, missionId)
                save()
                trackerLabel:destroy()
                trackerMiniWindow.contentsPanel.list:getLayout():update()
            end
        end
    end
end

-- =========================================================
-- Public functions (exposed via modules.game_trackers)
-- =========================================================

function onOpenQuestTracker()
    if trackerButton then
        trackerButton:setOn(true)
    end
    settings.trackerOpen = true
    save()
end

function onCloseQuestTracker()
    if trackerButton then
        trackerButton:setOn(false)
    end
    if not isGameEnding then
        settings.trackerOpen = false
        save()
    end
end

function onQuestTrackerDescriptionClick(widget, mousePos, mouseButton)
    if mouseButton == MouseRightButton then
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)
        menu:addOption(tr('remove'), function()
            local missionId = widget:getParent():getId()
            removeNumber(namePlayer, missionId)
            if settings[namePlayer] then
                sendQuestTracker(settings[namePlayer])
            end
            widget:getParent():destroy()
            save()

            if missionToQuestMap[tonumber(missionId)] then
                missionToQuestMap[tonumber(missionId)] = nil
            end

            -- Update quest log checkbox if open
            if modules.game_questlog and modules.game_questlog.updateTrackerCheckbox then
                modules.game_questlog.updateTrackerCheckbox(missionId, false)
            end
        end)
        menu:display(mousePos)
        return true
    elseif mouseButton == MouseLeftButton then
        local trackerLabel = widget:getParent()
        local questId = trackerLabel.questId
        local missionId = trackerLabel.missionId

        if (not questId or questId == 0) and missionId then
            questId = missionToQuestMap[tonumber(missionId)]
            if questId then
                trackerLabel.questId = questId
            end
        end

        -- Open quest log and navigate
        if modules.game_questlog and modules.game_questlog.show then
            modules.game_questlog.show()
        end

        if questId and questId ~= 0 and missionId then
            if modules.game_questlog and modules.game_questlog.navigateToMission then
                modules.game_questlog.navigateToMission(questId, missionId)
            end
        end
        return true
    end
    return false
end

-- =========================================================
-- API for game_questlog integration
-- =========================================================

function Tracker.Quest.getSettings()
    return settings
end

function Tracker.Quest.getNamePlayer()
    return namePlayer
end

function Tracker.Quest.isIdInTracker(key, id)
    return isIdInTracker(key, id)
end

function Tracker.Quest.addQuest(key, questId, missionId, missionName, missionDescription)
    addUniqueIdQuest(key, questId, missionId, missionName, missionDescription)
end

function Tracker.Quest.removeQuest(key, id)
    removeNumber(key, id)
end

function Tracker.Quest.save()
    save()
end

function Tracker.Quest.sendToServer()
    if settings[namePlayer] then
        sendQuestTracker(settings[namePlayer])
    end
end

function Tracker.Quest.getMiniWindow()
    return trackerMiniWindow
end

function Tracker.Quest.getMissionToQuestMap()
    return missionToQuestMap
end

function Tracker.Quest.showTracker(calledFrom)
    showQuestTracker(calledFrom)
end

function Tracker.Quest.rebuildFromSettings()
    rebuildTrackerFromSettings()
end

function Tracker.Quest.toggle()
    if not trackerMiniWindow then
        showQuestTracker("Tracker.Quest.toggle")
        return
    end
    if trackerMiniWindow:isVisible() then
        if trackerButton then
            trackerButton:setOn(false)
        end
        return trackerMiniWindow:close()
    end
    if trackerButton then
        trackerButton:setOn(true)
    end
    openTracker()
end

function Tracker.Quest.addTrackerLabel(missionId, questId, missionDescription)
    if not trackerMiniWindow then return end
    local existingLabel = trackerMiniWindow.contentsPanel.list:getChildById(tostring(missionId))
    if not existingLabel then
        local trackerLabel = g_ui.createWidget('QuestTrackerLabel', trackerMiniWindow.contentsPanel.list)
        trackerLabel:setId(tostring(missionId))
        trackerLabel.questId = questId
        trackerLabel.missionId = missionId
        trackerLabel.description:setText(missionDescription)
    else
        existingLabel.questId = questId
        existingLabel.missionId = missionId
        existingLabel.description:setText(missionDescription)
    end
end

function Tracker.Quest.removeTrackerLabel(missionId)
    if not trackerMiniWindow then return end
    local trackerLabel = trackerMiniWindow.contentsPanel.list:getChildById(tostring(missionId))
    if trackerLabel then
        trackerLabel:destroy()
    end
end

function Tracker.Quest.isVisible()
    return trackerMiniWindow and trackerMiniWindow:isVisible()
end

-- =========================================================
-- Init / Terminate / GameStart / GameEnd
-- =========================================================

function Tracker.Quest.init()
    connect(g_game, {
        onQuestTracker = onQuestTracker,
        onUpdateQuestTracker = onUpdateQuestTracker,
    })
end

function Tracker.Quest.terminate()
    disconnect(g_game, {
        onQuestTracker = onQuestTracker,
        onUpdateQuestTracker = onUpdateQuestTracker,
    })

    if trackerMiniWindow then
        trackerMiniWindow:destroy()
        trackerMiniWindow = nil
    end
    if trackerButton then
        trackerButton:destroy()
        trackerButton = nil
    end
end

function Tracker.Quest.onGameStart()
    if g_game.getClientVersion() < 1280 then
        return
    end

    isGameEnding = false
    namePlayer = g_game.getCharacterName():lower()
    settings = load() or {}

    if settings.autoTrackNewQuests == nil then
        settings.autoTrackNewQuests = false
    end
    if settings.autoUntrackCompleted == nil then
        settings.autoUntrackCompleted = false
    end

    if not settings[namePlayer] then
        settings[namePlayer] = {}
    end

    if settings[namePlayer] then
        sendQuestTracker(settings[namePlayer])
    end

    if not trackerButton then
        trackerButton = modules.game_mainpanel.addToggleButton("QuestLogTracker",
            tr("Open QuestLog Tracker"), "/images/options/button_questlog_tracker", function()
                Tracker.Quest.toggle()
            end, false, 18)
    end

    if trackerMiniWindow then
        scheduleEvent(function()
            if trackerMiniWindow and trackerMiniWindow.restorePosition then
                trackerMiniWindow:restorePosition()
            end
        end, 150)
        rebuildTrackerFromSettings()
    elseif settings.trackerOpen == true then
        -- Delay creation to let panels set up and avoid conflict with server's onQuestTracker
        scheduleEvent(function()
            if not trackerMiniWindow then
                showQuestTracker("onGameStart:delayed")
            elseif not trackerMiniWindow:isVisible() then
                openTracker()
            end
        end, 500)
    end
end

function Tracker.Quest.onGameEnd()
    if g_game.getClientVersion() < 1280 then
        return
    end

    isGameEnding = true
    save()

    if trackerMiniWindow then
        trackerMiniWindow:setParent(nil, true)
    end
    missionToQuestMap = {}
end
