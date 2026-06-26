-- CaveBot Extensions Loader
-- Loads all extension modules

CaveBot = CaveBot or {}
CaveBot.Extensions = CaveBot.Extensions or {}

-- Load extensions in order (absolute paths)
dofile("/game_helper/cavebots/extensions/supplies.lua")
dofile("/game_helper/cavebots/extensions/approach_tracker.lua")
dofile("/game_helper/cavebots/extensions/lure.lua")

return CaveBot.Extensions
