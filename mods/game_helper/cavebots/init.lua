-- CaveBot Main Loader
-- Entry point that loads all cavebot modules in correct order
-- Based on game_bot reference implementation

-- Initialize CaveBot global table
CaveBot = CaveBot or {}
CaveBot.Actions = CaveBot.Actions or {}
CaveBot.Extensions = CaveBot.Extensions or {}

-- Get the cavebots directory path (absolute)
local cavebotsPath = "/game_helper/cavebots/"

-- Load modules in order of dependencies
-- 1. Configuration system
dofile(cavebotsPath .. "config.lua")

-- 2. Map functions (pathfinding) - must load before walking
dofile(cavebotsPath .. "map.lua")

-- 3. Walking/movement system
dofile(cavebotsPath .. "walking.lua")

-- 3b. Doors data (closed/open/locked door id tables) - usado pela action "door"
dofile(cavebotsPath .. "doors_data.lua")

-- 4. Action system (requires config and walking)
dofile(cavebotsPath .. "actions.lua")

-- 5. Core loop (requires config, walking, actions)
dofile(cavebotsPath .. "core.lua")

-- 6. Recorder (requires actions, core)
dofile(cavebotsPath .. "recorder.lua")

-- 7. Extensions
dofile(cavebotsPath .. "extensions/init.lua")

-- 8. Load utils if exists (backwards compatibility)
local utilsPath = cavebotsPath .. "utils.lua"
if g_resources.fileExists(utilsPath) then
    dofile(utilsPath)
end

-- 9. Load libs if exists (blocked tile IDs, etc)
local libsPath = cavebotsPath .. "libs.lua"
if g_resources.fileExists(libsPath) then
    dofile(libsPath)
end

-- Initialize the cavebot system
local function initialize()
    -- Connect to player position changes
    if onPlayerPositionChange then
        CaveBot._positionCallback = onPlayerPositionChange(function(newPos, oldPos)
            -- This is handled by walking.lua
        end)
    end

    -- Log initialization
    g_logger.info("CaveBot: Initialized")
end

-- Cleanup function
local function terminate()
    -- Disconnect callbacks
    if CaveBot._positionCallback then
        -- Cleanup if needed
    end

    -- Stop cavebot
    if CaveBot.setOff then
        CaveBot.setOff()
    end

    -- Disable recorder
    if CaveBot.Recorder and CaveBot.Recorder.disable then
        CaveBot.Recorder.disable()
    end

    g_logger.info("CaveBot: Terminated")
end

-- Public interface
CaveBot.initialize = initialize
CaveBot.terminate = terminate

-- Version info
CaveBot.version = "2.0.0"
CaveBot.name = "CaveBot"

return CaveBot
