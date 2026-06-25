Import13 = {}
Import13.__index = Import13

function Import13.importControls()
    if g_game.isOnline() then
        closeOptions()
        return displayErrorBox("Import Config", "You can't import your config while you are online.")
    end

    local result = g_resources.importConfigData()
    if result then
        EnterGame.hide()
        closeOptions()
        scheduleEvent(function() g_app.exit() end, 4000)
        displayNonCloseInfoBox(tr("Import Config"), "Your Koliseu 13 config has been imported.\n\nYour client will close soon, please restart your client.", function() end)
    end
end