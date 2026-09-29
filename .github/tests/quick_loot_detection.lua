local gameInterfacePath, bindingsPath, uiMapPath = ...
assert(gameInterfacePath and bindingsPath and uiMapPath, 'missing source paths')

local function read(path)
  local file = assert(io.open(path, 'rb'))
  local contents = assert(file:read('*a'))
  file:close()
  return contents
end

local gameInterface = read(gameInterfacePath)
local bindings = read(bindingsPath)
local uiMap = read(uiMapPath)

assert(bindings:find('bindClassMemberFunction<Item>("hasLootHighlight", &Item::hasLootHighlightForLua)', 1, true),
  'Item.hasLootHighlight is not exposed to Lua')

local worldItem = assert(gameInterface:match(
  'local function isWorldGroundItem%b()%s*(.-)%s*end%s*%s*local function hasCorpseLikeName'))
assert(not worldItem:find('isPickupable', 1, true),
  'world corpse candidates must not depend on pickupable DAT metadata')

local corpseDetection = assert(gameInterface:match(
  'local function isQuickLootCorpseThing%b()%s*(.-)%s*end%s*%s*local function isWorldQuickLootContainer'))
local highlightPosition = assert(corpseDetection:find("callThingBool(thing, 'hasLootHighlight')", 1, true))
local datPosition = assert(corpseDetection:find("callThingBool(thing, 'isCorpse')", 1, true))
assert(highlightPosition < datPosition, 'server loot state must take priority over DAT corpse flags')

local quickLootTarget =
  'const bool quickLootTarget = thing->isLyingCorpse() || (item && item->hasLootHighlight());'
local quickLootGate = 'if (thing->isContainer() || quickLootTarget) {'
local targetPosition = assert(uiMap:find(quickLootTarget, 1, true),
  'Quick Loot cursor does not recognize server-highlighted corpses')
local gatePosition = assert(uiMap:find(quickLootGate, 1, true),
  'server-highlighted corpses remain hidden behind the container-only cursor gate')
assert(targetPosition < gatePosition,
  'Quick Loot target detection must run before the cursor gate')

print('quick loot corpse detection: OK')
