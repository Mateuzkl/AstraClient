GameTrackersController = {}

local taskTrackerRefreshEvent = nil
local TASK_TRACKER_REFRESH_INTERVAL = 1000

local function stopTaskTrackerRefresh()
    if taskTrackerRefreshEvent then
        removeEvent(taskTrackerRefreshEvent)
        taskTrackerRefreshEvent = nil
    end
end

local function scheduleTaskTrackerRefresh(delay)
    stopTaskTrackerRefresh()
    if not g_game.isOnline() then return end

    taskTrackerRefreshEvent = scheduleEvent(function()
        taskTrackerRefreshEvent = nil
        if not g_game.isOnline() then return end

        local taskHunt = modules.game_task_hunt
        if taskHunt and taskHunt.refreshTrackerData then
            taskHunt.refreshTrackerData()
        end
        scheduleTaskTrackerRefresh(TASK_TRACKER_REFRESH_INTERVAL)
    end, delay or TASK_TRACKER_REFRESH_INTERVAL)
end

function GameTrackersController:init()
    g_ui.importStyle('styles/kill_tracker')
    g_ui.importStyle('styles/imbuement_tracker')
    g_ui.importStyle('styles/quest_tracker')
    Tracker.Prey.init()
    Tracker.Imbuement.init()
    Tracker.Quest.init()

    connect(g_game, {
        onGameStart = GameTrackersController.onGameStart,
        onGameEnd = GameTrackersController.onGameEnd,
    })

    if g_game.isOnline() then
        GameTrackersController.onGameStart()
    end
end

function GameTrackersController:terminate()
    stopTaskTrackerRefresh()

    disconnect(g_game, {
        onGameStart = GameTrackersController.onGameStart,
        onGameEnd = GameTrackersController.onGameEnd,
    })

    Tracker.Prey.terminate()
    Tracker.Imbuement.terminate()
    Tracker.Quest.terminate()
end

function GameTrackersController.onGameStart()
    Tracker.Prey.check()
    Tracker.Quest.onGameStart()
    scheduleTaskTrackerRefresh(100)
end

function GameTrackersController.onGameEnd()
    stopTaskTrackerRefresh()
    Tracker.Prey.hide()
    Tracker.Quest.onGameEnd()
end

local function ensureKillTrackerReady()
    if not Tracker or not Tracker.Prey then
        return false
    end

    if Tracker.Prey.getWidget and Tracker.Prey.getWidget() then
        return true
    end

    local okStyle, styleError = pcall(function()
        g_ui.importStyle('styles/kill_tracker')
    end)
    if not okStyle then
        perror('Kill Tracker style load failed: ' .. tostring(styleError))
        return false
    end

    local okInit, initError = pcall(function()
        Tracker.Prey.init()
        if g_game.isOnline() then
            Tracker.Prey.check()
            scheduleTaskTrackerRefresh()
        end
    end)
    if not okInit then
        perror('Kill Tracker init failed: ' .. tostring(initError))
        return false
    end

    return Tracker.Prey.getWidget and Tracker.Prey.getWidget() ~= nil
end

function toggleKillTracker()
    if ensureKillTrackerReady() then
        Tracker.Prey.toggle()
    end
end

function showKillTracker()
    if ensureKillTrackerReady() and Tracker.Prey.ensureVisible then
        return Tracker.Prey.ensureVisible()
    end
    return false
end

function getKillTrackerDebug()
    local widget = Tracker and Tracker.Prey and Tracker.Prey.getWidget and Tracker.Prey.getWidget() or nil
    return {
        tracker = Tracker ~= nil,
        prey = Tracker and Tracker.Prey ~= nil or false,
        widget = widget ~= nil,
        parent = widget and widget:getParent() and widget:getParent():getId() or nil,
        visible = widget and widget:isVisible() or false,
        online = g_game.isOnline(),
        rootPanel = m_interface.getRootPanel and m_interface.getRootPanel() ~= nil or false,
        rightPanel = m_interface.getRightPanel and m_interface.getRightPanel() ~= nil or false
    }
end
