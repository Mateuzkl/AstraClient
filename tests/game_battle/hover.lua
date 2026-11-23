-- Run with Run-Hover.ps1 in an isolated client. Only world input and mouse
-- transitions are simulated. Rows, portraits, creatures and squares are native.
g_modules.discoverModules()
g_modules.ensureModuleLoaded('corelib')
g_modules.ensureModuleLoaded('gamelib')
g_modules.ensureModuleLoaded('client_styles')
g_ui.importStyle('/modules/game_battle/battlebutton.otui')
dofile('/modules/game_battle/battle.lua')
dofile('/modules/game_battle/BattleClass.lua')

local function makeList(secondary)
  local list = BattleClass:create()
  list.window = g_ui.createWidget('UIWidget', g_ui.getRootWidget())
  list.panel = list.window
  list.secondary = secondary
  table.insert(battleClasses, list)
  return list, list:createButton()
end

local function makeMonster(name, id, health)
  local creature = Creature.create()
  creature:setName(name)
  creature:setHealthPercent(health)
  creature:setPosition({ x = 100, y = 100, z = 7 })
  creature.getId = function() return id end
  creature.canBeSeen = function() return true end
  creature.isMonster = function() return true end
  return creature
end

local function hover(row, entered)
  -- UIManager changes the widget state before dispatching the Lua callback.
  row.isHovered = function() return entered end
  row:onHoverChange(entered)
end

local function expectColor(color, expected)
  assert(table.compare(color, tocolor(expected)), 'expected color ' .. expected)
end

local main, row = makeList(false)
local secondary, other = makeList(true)
local chicken = makeMonster('Chicken', 1, 100)
local rat = makeMonster('Rat', 2, 42)
local spectators, attack, follow
local player = { getPosition = function() return chicken:getPosition() end }
g_game.isOnline = function() return true end
g_game.getLocalPlayer = function() return player end
g_game.getAttackingCreature = function() return attack end
g_game.getFollowingCreature = function() return follow end
g_map.getSpectatorsInRangeEx = function() return spectators end
m_interface = { getMapPanel = function()
  return { getVisibleDimension = function() return { width = 15, height = 11 } end }
end }

assert(row:getCreature() == nil, 'new row exposed its portrait as a creature')
assert(type(row.isHovered) == 'function', 'row shadows the native hover state')
row:update()
spectators = { chicken }
for cycle = 1, 20 do
  chicken:setHealthPercent(100)
  checkCreatures()
  hover(row, true)
  assert(chicken:isStaticSquareVisible(), 'missing hover on cycle ' .. cycle)
  chicken:setHealthPercent(0)
  checkCreatures()
  assert(row:isHidden() and row:getCreature() == nil and row.creatureWidget:getCreature() == nil)
  assert(not chicken:isStaticSquareVisible(), 'removed creature kept its square')
  hover(row, true)
  hover(row, false)
  row:update()
  assert(not chicken:isStaticSquareVisible())
end

chicken:setHealthPercent(100)
checkCreatures()
hover(row, true)
spectators = { rat }
checkCreatures() -- same hovered widget, no mouse transition
assert(not chicken:isStaticSquareVisible() and rat:isStaticSquareVisible())
assert(row:getCreatureId() == 2 and row.creatureWidget:getCreature() == rat)
assert(row.labelWidget:getText() == 'Rat' and row.lifeBarWidget:getPercent() == 42)
expectColor(row.labelWidget:getColor(), '#f7f7f7')

attack = rat
onTargetStateChange()
expectColor(rat:getStaticSquareColor(), '#f7a3a3')
attack, follow = nil, chicken
onTargetStateChange()
assert(rat:isStaticSquareVisible() and chicken:isStaticSquareVisible())
expectColor(rat:getStaticSquareColor(), '#f7f7f7')
expectColor(chicken:getStaticSquareColor(), '#3fdf3f')
follow = rat
onTargetStateChange()
expectColor(rat:getStaticSquareColor(), '#b3f7b3')
assert(not chicken:isStaticSquareVisible())

rat.getEchoRaidVisualState = function() return 0 end
onTargetStateChange()
expectColor(row.labelWidget:getColor(), '#ff3030')
expectColor(row.creatureWidget:getBorderTopColor(), '#b3f7b3')
follow = nil
rat.getEchoRaidVisualState = function() return 1 end
hover(row, false)
expectColor(row.creatureWidget:getBorderTopColor(), '#d060d8')

hover(row, true)
local filter = g_ui.createWidget('UIWidget', main.window)
filter:setId('showMonsters')
filter:setChecked(false)
main.filterPanel = { buttons = main.window }
checkCreatures()
assert(row:isHidden() and other:isVisible() and not rat:isStaticSquareVisible())
hover(other, true)
hover(row, false) -- late leave from a different list showing the same creature
assert(rat:isStaticSquareVisible())
secondary.window:hide()
checkCreatures()
assert(not rat:isStaticSquareVisible())

filter:setChecked(true)
checkCreatures()
-- The native widget can stay hovered across hide/show without a fresh enter.
row.isHovered = function() return true end
checkCreatures()
assert(rat:isStaticSquareVisible())
attack = rat
filter:setChecked(false)
checkCreatures()
assert(row:isHidden() and rat:isStaticSquareVisible())
expectColor(rat:getStaticSquareColor(), '#df3f3f')
attack = nil
filter:setChecked(true)
checkCreatures()
hover(row, true)
onGameEnd()
assert(row:isHidden() and other:isHidden() and not rat:isStaticSquareVisible())
hover(row, true)
assert(not rat:isStaticSquareVisible())
print('[Battle List] PASS: 20 removal cycles, reuse, filters, secondary list, target/follow, Echo Raid and logout')
scheduleEvent(function() g_app.exit() end, 10)
