-- Client settings import / export.
--
-- Both features are pure Lua and need no C++ binding. All settings live in a
-- single OTML document, /config.otml, in the client write dir -- see init.lua
-- (g_configs.loadSettings('/config.otml')). g_settings is that very same object
-- (modules/corelib/settings.lua: makesingleton(g_configs.getSettings())).
--
--  * Export flushes the live settings to /config.otml and copies them to a
--    portable file the player can carry to another PC or share with a friend.
--  * Import does the reverse: it overwrites /config.otml with that file and then
--    RELOADS it into the live settings object before restarting. The reload is
--    mandatory: on exit the client saves g_settings back to /config.otml
--    (ConfigManager::terminate -> Config::save), which would otherwise clobber
--    the freshly imported file with the old in-memory values.

ImportConfig = {}
ImportConfig.__index = ImportConfig

-- Shared portable file. Written to (and read from) the client write dir, so
-- g_resources.getWriteDir() points a player at exactly where it lives.
local EXPORT_FILE = '/exported_options.otml'
local SETTINGS_FILE = '/config.otml'

function ImportConfig.export()
    -- Flush any unsaved in-memory changes first so the export mirrors the live
    -- state, then snapshot the config document to the portable file.
    g_settings.save()

    local data = g_resources.readFileContents(SETTINGS_FILE)
    if not data or data:len() == 0 then
        return displayErrorBox(tr("Export All Options"), "Could not read your current settings.")
    end

    g_resources.writeFileContents(EXPORT_FILE, data)

    displayInfoBox(tr("Export All Options"),
        "Your options have been exported to:\n\n" .. g_resources.getWriteDir() .. EXPORT_FILE ..
        "\n\nCopy this file into another computer's client folder and use\n\"Import Koliseu 15 Config\" to load it.")
end

function ImportConfig.import()
    if g_game.isOnline() then
        closeOptions()
        return displayErrorBox(tr("Import Config"), "You can't import your config while you are online.")
    end

    if not g_resources.fileExists(EXPORT_FILE) then
        return displayErrorBox(tr("Import Config"),
            "No exported config file was found at:\n\n" .. g_resources.getWriteDir() .. EXPORT_FILE ..
            "\n\nUse \"Export All Options\" first, or copy an exported file\ninto the client folder.")
    end

    local data = g_resources.readFileContents(EXPORT_FILE)
    if not data or data:len() == 0 then
        return displayErrorBox(tr("Import Config"), "The exported config file is empty or unreadable.")
    end

    -- Overwrite the live config file, then reload it into the settings object so
    -- the on-exit save persists the imported data rather than the old values.
    g_resources.writeFileContents(SETTINGS_FILE, data)
    g_configs.loadSettings(SETTINGS_FILE)

    EnterGame.hide()
    closeOptions()
    scheduleEvent(function() g_app.exit() end, 4000)
    displayNonCloseInfoBox(tr("Import Config"),
        "Your Koliseu 15 config has been imported.\n\nYour client will close soon, please restart your client.")
end
