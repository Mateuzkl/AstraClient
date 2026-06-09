GameTrackersController = {}

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
end

function GameTrackersController.onGameEnd()
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
