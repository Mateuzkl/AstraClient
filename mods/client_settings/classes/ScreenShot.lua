if not ScreenShot then
    ScreenShot = {}
    ScreenShot.__index = ScreenShot
end

ScreenShot.ScreenshotType = {
    NONE = 0,
    ACHIEVEMENT = 1,
    BOSS_DEFEATED = 4,
    DEATH_PVE = 5,
    DEATH_PVP = 6,
    LEVEL_UP = 7,
    PLAYER_KILL_ASSIST = 8,
    PLAYER_KILL = 9,
    PLAYER_ATTACKING = 10,
    TREASURE_FOUND = 11,
    SKILL_UP = 12,
    HIGHEST_DAMAGE_DEALT = 13,
    HIGHEST_HEALING_DONE = 14,
    LOW_HEALTH = 15,
    GIFT_OF_LIFE_TRIGGERED = 16,
    VALUABLE_LOOT = -99
}

ScreenShot.AutoScreenshotEvents = {
    [ScreenShot.ScreenshotType.LEVEL_UP]                 = { label = "Level Up",                 settingKey = "screenshotLevelUp" },
    [ScreenShot.ScreenshotType.SKILL_UP]                 = { label = "Skill Up",                 settingKey = "screenshotSkillUp" },
    [ScreenShot.ScreenshotType.ACHIEVEMENT]              = { label = "Achievement",              settingKey = "screenshotAchievement" },
    [ScreenShot.ScreenshotType.TREASURE_FOUND]           = { label = "Treasure Found",           settingKey = "screenshotTreasure" },
    [ScreenShot.ScreenshotType.VALUABLE_LOOT]            = { label = "Valuable Loot",            settingKey = "screenshotValuableLoot" },
    [ScreenShot.ScreenshotType.BOSS_DEFEATED]            = { label = "Boss Defeated",            settingKey = "screenshotBossDefeated" },
    [ScreenShot.ScreenshotType.DEATH_PVE]                = { label = "Death PvE",                settingKey = "screenshotDeathPve" },
    [ScreenShot.ScreenshotType.DEATH_PVP]                = { label = "Death PvP",                settingKey = "screenshotDeathPvp" },
    [ScreenShot.ScreenshotType.PLAYER_KILL]              = { label = "Player Kill",              settingKey = "screenshotPlayerKill" },
    [ScreenShot.ScreenshotType.PLAYER_KILL_ASSIST]       = { label = "Player Kill Assist",       settingKey = "screenshotPlayerKillAssist" },
    [ScreenShot.ScreenshotType.PLAYER_ATTACKING]         = { label = "Player Attacking",         settingKey = "screenshotPlayerAttacking" },
    [ScreenShot.ScreenshotType.HIGHEST_DAMAGE_DEALT]     = { label = "Highest Damage Dealt",     settingKey = "screenshotHighestDamage" },
    [ScreenShot.ScreenshotType.HIGHEST_HEALING_DONE]     = { label = "Highest Healing Done",     settingKey = "screenshotHighestHealing" },
    [ScreenShot.ScreenshotType.LOW_HEALTH]               = { label = "Low Health",               settingKey = "screenshotLowHealth" },
    [ScreenShot.ScreenshotType.GIFT_OF_LIFE_TRIGGERED]   = { label = "Gift of Life Triggered",   settingKey = "screenshotGiftOfLife" }
}

local SCREENSHOT_DIR = "screenshots"
local screenshotScheduleEvent = nil

if not g_resources.directoryExists(SCREENSHOT_DIR) then
    g_resources.makeDir(SCREENSHOT_DIR)
end

local function getUniqueFileName(baseName)
    local fileName = SCREENSHOT_DIR .. "/" .. baseName .. ".png"
    local counter = 0
    while g_resources.fileExists(fileName) do
        fileName = SCREENSHOT_DIR .. "/" .. baseName .. "_" .. counter .. ".png"
        counter = counter + 1
    end
    return fileName
end

local function logScreenshot(fileName, eventLabel)
    local absolutePath = g_platform.getCurrentDir() .. fileName
    local message = string.format("Screenshot%s has been saved to '%s'.",eventLabel and " for " .. eventLabel or "", absolutePath)

    if modules.game_console then
        modules.game_console.addText(message, MessageModes.ChannelManagement, "Server Log")
    end
    return message
end

function takeScreenshot(isMapScreenshot)
    if not g_game.isOnline() then return end

    local player = g_game.getLocalPlayer()
    local baseName = string.format("%s_%d_%s",
        player:getName() or "player",
        player:getLevel() or 1,
        os.date("%Y-%m-%d_%H-%M-%S")
    )

    if screenshotScheduleEvent then
        removeEvent(screenshotScheduleEvent)
    end

    local fileName = getUniqueFileName(baseName)
    screenshotScheduleEvent = scheduleEvent(function()
        (isMapScreenshot and g_app.doMapScreenshot or g_app.doScreenshot)(fileName)
        logScreenshot(fileName, isMapScreenshot and "Map Manual" or "Manual")
    end, 50)
end

function ScreenShot:onScreenShot(type)
    if not getOption("autoScreenshot") or not g_game.isOnline() then
        return
    end

    local player = g_game.getLocalPlayer()
    local baseName = string.format("%s_%d_%s",
        player:getName() or "player",
        player:getLevel() or 1,
        os.date("%Y-%m-%d_%H-%M-%S")
    )

    local event = ScreenShot.AutoScreenshotEvents[type]
    if not event or not getOption(event.settingKey) then
        return
    end

    if screenshotScheduleEvent then
        removeEvent(screenshotScheduleEvent)
    end

    local fileName = getUniqueFileName(baseName)
    screenshotScheduleEvent = scheduleEvent(function()
        if getOption("gameWindowScreen") then
            g_app.doMapScreenshot(fileName)
        else
            g_app.doScreenshot(fileName)
        end

        local message = logScreenshot(fileName, event.label)

        if modules.game_textmessage and modules.game_textmessage.messagesPanel then
            modules.game_textmessage.displayStatusMessage(message)
        end
    end, 50)
end

function openScreenshotFolder()
    g_platform.openDir(SCREENSHOT_DIR)
end
