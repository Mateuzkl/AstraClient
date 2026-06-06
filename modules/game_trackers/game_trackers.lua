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
