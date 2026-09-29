local thingPath, bannerPath, parserPath, senderPath, constPath = ...
assert(thingPath and bannerPath and parserPath and senderPath and constPath, 'missing source paths')

local function read(path)
  local file = assert(io.open(path, 'rb'))
  local contents = assert(file:read('*a'))
  file:close()
  return contents
end

local staticScans = 0
local staticMonstersAvailable = true
g_things = {
  getMonsterList = function()
    staticScans = staticScans + 1
    if not staticMonstersAvailable then
      return {}
    end
    return {
      [123] = {'Wrong Creature', 321, 0, 1, 2, 3, 4, 0},
      [500] = {'Legacy Creature', 21, 0, 0, 0, 0, 0, 0},
    }
  end,
}

assert(loadfile(thingPath))()

local cyclopediaUpdates = {}
local cyclopediaClears = 0
function cacheCyclopediaMonster(raceId, creature)
  cyclopediaUpdates[raceId] = creature
end

function clearCyclopediaMonsterCache()
  cyclopediaUpdates = {}
  cyclopediaClears = cyclopediaClears + 1
end

local connectedHandlers
local widgets = {}
local mapPanel = {getWidth = function() return 800 end}

local function createWidget(kind)
  local widget = {kind = kind, visible = true}
  function widget:addAnchor() end
  function widget:setWidth(value) self.width = value end
  function widget:setHeight(value) self.height = value end
  function widget:setPhantom(value) self.phantom = value end
  function widget:setMarginLeft(value) self.marginLeft = value end
  function widget:setMarginTop(value) self.marginTop = value end
  function widget:setImageSource(value) self.imageSource = value end
  function widget:setOpacity(value) self.opacity = value end
  function widget:setFixedCreatureSize(value) self.fixedCreatureSize = value end
  function widget:setStaticWalking(value) self.staticWalking = value end
  function widget:setCenter(value) self.center = value end
  function widget:setOutfit(value) self.outfit = value end
  function widget:setText(value) self.text = value end
  function widget:setTextAlign() end
  function widget:setColor() end
  function widget:setFont() end
  function widget:setTextWrap() end
  function widget:raise() self.raised = true end
  function widget:show() self.visible = true end
  function widget:hide() self.visible = false end
  function widget:isDestroyed() return self.destroyed == true end
  function widget:destroy() self.destroyed = true end
  widgets[#widgets + 1] = widget
  return widget
end

modules = {game_interface = {getMapPanel = function() return mapPanel end}}
g_ui = {createWidget = function(kind) return createWidget(kind) end}
g_game = {}
AnchorLeft = 1
AnchorTop = 2
AlignCenter = 3
connect = function(_, handlers) connectedHandlers = handlers end
disconnect = function() end
scheduleEvent = function() return {} end
removeEvent = function() end

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

staticMonstersAvailable = false
local unavailable = assert(infobanner.resolveBestiaryNotification(999, nil, nil))
assert(unavailable.name == 'Creature 999', 'empty static data must retain the generic fallback')
assert(staticScans == 1, 'empty static data should be queried once per lookup')

staticMonstersAvailable = true
local legacy = assert(infobanner.resolveBestiaryNotification(500, nil, nil))
assert(staticScans == 2, 'an empty static result must be retried after creatures load')
assert(legacy.name == 'Legacy Creature', 'legacy notification fallback changed unexpectedly')

infobanner.init()
assert(connectedHandlers and connectedHandlers.onClientEvent, 'Bestiary event handler was not connected')
connectedHandlers.onClientEvent(7, 702, 2, 'Item Appearance Boss', {
  type = 0,
  auxType = 52831,
})

local renderedOutfit
local renderedIcon
for _, widget in ipairs(widgets) do
  if widget.kind == 'UICreature' and widget.outfit then
    renderedOutfit = widget.outfit
  end
  if widget.imageSource == '/modules/game_notifications/assets/images/nodo/icon-infobanner-unlock.png' then
    renderedIcon = widget.imageSource
  end
end
assert(renderedOutfit and renderedOutfit.auxType == 52831,
  'Bosstiary handler did not render the authoritative item appearance')
assert(renderedIcon, 'Bestiary handler did not retain the gold frame and green background')
assert(cyclopediaUpdates[702] and cyclopediaUpdates[702].auxType == 52831,
  'Bosstiary handler did not cache the authoritative item appearance')

connectedHandlers.onGameEnd()
assert(cyclopediaClears == 1, 'Cyclopedia creature cache was not cleared on game end')
assert(g_things.getRaceData(123).name == 'Wrong Creature',
  'authoritative creature data survived after game end')

local parser = read(parserPath)
assert(parser:find('GameAstraBestiaryBannerCreatureData', 1, true),
  'enhanced Bestiary parser is not feature-gated')
assert(parser:find('type, raceId, progressLevel, name, outfit', 1, true),
  'enhanced Bestiary parser does not forward authoritative metadata')
assert(parser:find('outfit.setAuxId(msg->getU16());', 1, true),
  'enhanced Bestiary parser does not preserve item appearances')
assert(parser:find('type, raceId, progressLevel);', 1, true),
  'legacy Bestiary callback layout is not preserved')

local sender = read(senderPath)
assert(sender:find('ASTRA_CAPABILITY_BESTIARY_BANNER_CREATURE_DATA = 1U << 5', 1, true),
  'Astra login does not advertise enhanced Bestiary banner support')
assert(sender:find('disableFeature(Otc::GameAstraBestiaryBannerCreatureData)', 1, true),
  'custom login data can retain a stale Bestiary banner feature')

local constants = read(constPath)
assert(constants:find('GameAstraBestiaryBannerCreatureData = 151', 1, true),
  'enhanced Bestiary feature id changed or is missing')

print('bestiary notification identity: OK')
