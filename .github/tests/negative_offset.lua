local featuresScript = assert(arg[1], "missing features.lua path")
local thingTypeSourcePath = assert(arg[2], "missing thingtype.cpp path")
local creatureSourcePath = assert(arg[3], "missing creature.cpp path")

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

local function readFile(path)
  local file = assert(io.open(path, "rb"))
  local contents = assert(file:read("*a"))
  file:close()
  return contents
end

local thingTypeSource = readFile(thingTypeSourcePath)
local unserializeStart = assert(thingTypeSource:find("void ThingType::unserialize", 1, true))
local displacementStart = assert(thingTypeSource:find("case ThingAttrDisplacement:", unserializeStart, true))
local displacementEnd = assert(thingTypeSource:find("case ThingAttrLight:", displacementStart, true))
local displacementBlock = thingTypeSource:sub(displacementStart, displacementEnd - 1)

assert(displacementBlock:find("GameNegativeOffset", 1, true), "signed DAT decoding is not feature-gated")
assert(displacementBlock:find("get16()", 1, true), "negative offsets are not decoded as signed 16-bit values")
assert(displacementBlock:find("getU16()", 1, true), "legacy unsigned displacement decoding was removed")

local creatureSource = readFile(creatureSourcePath)
local getDisplacementStart = assert(creatureSource:find("Point Creature::getDisplacement()", 1, true))
local getDisplacementEnd = assert(creatureSource:find("int Creature::getDisplacementX()", getDisplacementStart, true))
local getDisplacementBlock = creatureSource:sub(getDisplacementStart, getDisplacementEnd - 1)

assert(not getDisplacementBlock:find("GameNegativeOffset", 1, true),
  "negative-offset mode must not erase the visual creature displacement")

print("negative offset feature: OK")
