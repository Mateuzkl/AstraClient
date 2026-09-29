local thingPath, bannerPath, parserPath, senderPath, constPath = ...
assert(thingPath and bannerPath and parserPath and senderPath and constPath, 'missing source paths')

local function read(path)
  local file = assert(io.open(path, 'rb'))
  local contents = assert(file:read('*a'))
  file:close()
  return contents
end

local staticScans = 0
g_things = {
  getMonsterList = function()
    staticScans = staticScans + 1
    return {
      [123] = {'Wrong Creature', 321, 0, 1, 2, 3, 4, 0},
      [500] = {'Legacy Creature', 21, 0, 0, 0, 0, 0, 0},
    }
  end,
}

assert(loadfile(thingPath))()

local cyclopediaUpdates = {}
function cacheCyclopediaMonster(raceId, creature)
  cyclopediaUpdates[raceId] = creature
end

assert(loadfile(bannerPath))()

local bestiary = assert(infobanner.resolveBestiaryNotification(123, 'Correct Creature', {
  type = 900,
  head = 11,
  body = 22,
  legs = 33,
  feet = 44,
  addons = 3,
}))
assert(staticScans == 0, 'authoritative progress events must not rebuild the static monster list')
assert(bestiary.name == 'Correct Creature', 'Bestiary event did not preserve the authoritative name')
assert(bestiary.outfit and bestiary.outfit.type == 900, 'Bestiary event did not preserve the authoritative outfit')
assert(g_things.getRaceData(123).name == 'Correct Creature', 'weak looktype data replaced authoritative race data')
assert(cyclopediaUpdates[123] and cyclopediaUpdates[123].type == 900,
  'Bestiary event did not update the Cyclopedia cache')

local bosstiary = assert(infobanner.resolveBestiaryNotification(700, 'Correct Boss', {
  type = 1200,
  head = 5,
  body = 6,
  legs = 7,
  feet = 8,
  addons = 2,
}))
assert(bosstiary.name == 'Correct Boss', 'Bosstiary event did not preserve the authoritative name')
assert(bosstiary.outfit and bosstiary.outfit.type == 1200,
  'Bosstiary event did not preserve the authoritative outfit')

local missingOutfit = assert(infobanner.resolveBestiaryNotification(701, 'Name Without Outfit', {}))
assert(missingOutfit.name == 'Name Without Outfit', 'missing outfit must not discard the authoritative name')
assert(missingOutfit.outfit == nil, 'missing outfit must use the generic banner icon')

local legacy = assert(infobanner.resolveBestiaryNotification(500, nil, nil))
assert(staticScans == 1, 'legacy fallback should lazily build the static list once')
assert(legacy.name == 'Legacy Creature', 'legacy notification fallback changed unexpectedly')

local parser = read(parserPath)
assert(parser:find('GameAstraBestiaryBannerCreatureData', 1, true),
  'enhanced Bestiary parser is not feature-gated')
assert(parser:find('type, raceId, progressLevel, name, outfit', 1, true),
  'enhanced Bestiary parser does not forward authoritative metadata')
assert(parser:find('type, raceId, progressLevel);', 1, true),
  'legacy Bestiary callback layout is not preserved')

local sender = read(senderPath)
assert(sender:find('ASTRA_CAPABILITY_BESTIARY_BANNER_CREATURE_DATA = 1U << 5', 1, true),
  'Astra login does not advertise enhanced Bestiary banner support')

local constants = read(constPath)
assert(constants:find('GameAstraBestiaryBannerCreatureData = 151', 1, true),
  'enhanced Bestiary feature id changed or is missing')

print('bestiary notification identity: OK')
