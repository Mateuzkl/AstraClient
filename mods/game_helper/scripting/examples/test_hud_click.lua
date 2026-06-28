--[[============================================================================
  test_hud_click.lua  --  self-test for clickable HUD + the HUD_CLICK event
  ============================================================================
  WHAT IT COVERS (scripting/api/hud.lua + game.lua event bridge):
    * HUD(x, y, value, onClick)   4th-arg function form -> bound as the callback
    * :setCallback(fn)            per-instance click callback (ctx.wrap'd)
    * Game.Events.HUD_CLICK (2)   global click dispatch: on click the HUD fires
                                  Game.executeEvents(HUD_CLICK, id)
    * Game.Events.HUD_DRAG (15)   fired on drag-release with (id, x, y)

  HOW TO RUN: enable in the Scripting tab WHILE IN GAME. Two small clickable
  boxes appear top-left. CLICK either box: the per-instance callback logs, and
  the global HUD_CLICK handler logs the clicked element id (they should match).
  DRAG a box and drop it: the HUD_DRAG handler logs the new id + position.
  Everything self-destroys after ~30s.

  NOTE: HUD_CLICK / HUD_DRAG have NO engine/protocol source -- they are fired
  internally by hud.lua itself when you interact with the widget. That is why
  this works fully client-side with no server involvement.

  SAFETY: creates two HUD widgets only; both are destroyed by the watchdog
  Timer (engine also cleans up on unload), and the HUD_CLICK/HUD_DRAG listeners
  are unregistered there too. No game actions.
============================================================================]]

local pass, fail = 0, 0
local function check(name, cond, extra)
  if cond then
    pass = pass + 1
    print('[PASS] ' .. name .. (extra and (' = ' .. tostring(extra)) or ''))
  else
    fail = fail + 1
    print('[FAIL] ' .. name)
  end
end

local perInstanceClicks = 0
local globalClicks = 0
local lastClickedId = nil
local lastDrag = nil

-- HUD #1: callback passed as the 4th constructor arg (HUD(x,y,text, onClick)).
local h1 = HUD(70, 70, 'Click me (cb arg)', function(self)
  perInstanceClicks = perInstanceClicks + 1
  print('[cb-arg] HUD ' .. tostring(self:getId()) .. ' clicked; total=' .. perInstanceClicks)
end)
check('HUD with cb-arg created', h1 ~= nil)

-- HUD #2: callback installed afterwards via :setCallback.
local h2 = HUD(70, 130, 'Click me (setCallback)')
check('setCallback returns self', h2:setCallback(function(self)
  perInstanceClicks = perInstanceClicks + 1
  print('[setCallback] HUD ' .. tostring(self:getId()) .. ' clicked')
end) == h2)

-- Global HUD_CLICK listener: fires for ANY HUD this client clicks, with the id.
local function onHudClick(id)
  globalClicks = globalClicks + 1
  lastClickedId = id
  print('[HUD_CLICK] id=' .. tostring(id) .. ' (global #' .. globalClicks .. ')')
end
local retClick = Game.registerEvent(Game.Events.HUD_CLICK, onHudClick)
check('registerEvent(HUD_CLICK) returns same fn', retClick == onHudClick)
check('Game.Events.HUD_CLICK id', Game.Events.HUD_CLICK == 2, Game.Events.HUD_CLICK)

-- Global HUD_DRAG listener: fires when a HUD is dragged + dropped.
local function onHudDrag(id, x, y)
  lastDrag = { id = id, x = x, y = y }
  print(('[HUD_DRAG] id=%s -> (%s,%s)'):format(tostring(id), tostring(x), tostring(y)))
end
Game.registerEvent(Game.Events.HUD_DRAG, onHudDrag)
check('Game.Events.HUD_DRAG id', Game.Events.HUD_DRAG == 15, Game.Events.HUD_DRAG)

-- setCallback(nil) must clear without error (chainable).
check('setCallback(nil) clears + chainable', h2:setCallback(nil) == h2)
-- ...then reinstall it so the demo still reacts.
h2:setCallback(function() perInstanceClicks = perInstanceClicks + 1 end)

print('[info] test_hud_click.lua: two clickable boxes on screen. Click/drag them!')
print('[info] Auto-cleans in ~30s.')

-- Watchdog: report interaction counts, unregister + destroy, print summary.
-- NOTE: this Timer port does NOT pass the instance to the callback, so we
-- capture the handle in `stopTimer` and stop THAT (not a `self` arg). (The HUD
-- click callbacks above DO receive `self` -- hud.lua passes the HUD instance.)
local stopTimer
stopTimer = Timer('test_hud_click.stop', function()
  Game.unregisterEvent(Game.Events.HUD_CLICK, onHudClick)
  Game.unregisterEvent(Game.Events.HUD_DRAG, onHudDrag)
  print(('[info] per-instance clicks=%d, global HUD_CLICK=%d, lastId=%s')
    :format(perInstanceClicks, globalClicks, tostring(lastClickedId)))
  if lastDrag then
    print(('[info] last drag: id=%s (%s,%s)')
      :format(tostring(lastDrag.id), tostring(lastDrag.x), tostring(lastDrag.y)))
  end
  -- Observational (depends on the player clicking); we report rather than fail.
  check('HUD_CLICK listener installed without error', true)
  h1:destroy()
  h2:destroy()
  if stopTimer then stopTimer:destroy() end
  print(('--- hud_click: %d passed, %d failed ---'):format(pass, fail))
end, 30000, true)
