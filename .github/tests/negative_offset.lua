local featuresScript = assert(arg[1], "missing features.lua path")

setmetatable(_G, {
  __index = function(_, key)
    if key:match("^Game") then
      return key
    end
  end
})

local enabledFeatures = {}
local expectedNegativeOffset = false
local assetLoads = 0

g_game = {
  resetFeatures = function()
    enabledFeatures = {}
  end,
  enableFeature = function(feature)
    enabledFeatures[feature] = true
  end
}

modules = {
  game_things = {
    load = function()
      assetLoads = assetLoads + 1
      assert((enabledFeatures[GameNegativeOffset] == true) == expectedNegativeOffset,
        "GameNegativeOffset was not configured before loading assets")
    end
  }
}

connect = function() end
disconnect = function() end

assert(loadfile(featuresScript))()

expectedNegativeOffset = true
updateFeatures(860)
assert(enabledFeatures[GameNegativeOffset], "8.60 did not enable GameNegativeOffset")

expectedNegativeOffset = false
updateFeatures(1524)
assert(not enabledFeatures[GameNegativeOffset], "GameNegativeOffset leaked into another client version")
assert(assetLoads == 2, "unexpected asset load count")

print("negative offset feature: OK")
