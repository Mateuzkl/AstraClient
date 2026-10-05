local clientInit

function init()
	clientInit = g_ui.displayUI('client_init')
    connect(g_app, { onRun = onLoad })
end

function onLoad()
    clientInit:hide()
    modules.client_background.showPanel()
    g_modules.discoverModule("/modules/client_entergame/entergame.otmod"):load()
end

function terminate()
    disconnect(g_app, { onRun = onLoad })
    if clientInit then
        clientInit:destroy()
        clientInit = nil
    end
end
