--[[============================================================================
  test_hud_text.lua  --  self-test for the text variant of the `HUD` API
  ============================================================================
  WHAT IT COVERS (scripting/api/hud.lua):
    * HUD(x, y, 'text')          text HUD (string value -> 'text' kind)
    * :getId()                   stable per-script element id
    * :setText(t)                update caption
    * :setColor(r, g, b)         text color (RGB triple form)
    * :setPos(x, y) / :getPos()  map-relative move + read-back
    * :setVisible / show / hide  visibility toggles (chainable)
    * :setFontSize               documented chainable no-op (parity)
    * :destroy()                 explicit teardown

  HOW TO RUN: enable in the Scripting tab WHILE IN GAME (a HUD needs the game
  map panel). A small text box appears top-left; it changes text/color, nudges
  position, then DISAPPEARS after ~4 seconds. The debug console prints the
  PASS/FAIL summary.

  SAFETY: this is the only kind of script that puts pixels on screen. It stores
  its single HUD handle and a watchdog Timer destroys it after 4s, so it never
  leaves anything on the map. (The engine also destroys a script's HUDs on
  unload.) HUDs do not affect the game world.
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

-- Create the text HUD. A STRING value selects the 'text' kind (a number would
-- make it an item HUD -- covered by test_hud_item.lua).
local h = HUD(60, 60, 'KoliseuOT HUD test')
check('HUD created (non-nil)', h ~= nil)
check('getId() is a number', type(h:getId()) == 'number', h and h:getId())

-- Methods are chainable: each returns the HUD, so calls can be threaded.
check('setText returns self (chainable)', h:setText('hello') == h)
check('setColor returns self (chainable)', h:setColor(0, 255, 0) == h)

-- Position round-trip: setPos stores map-relative coords; getPos reads them back.
h:setPos(120, 90)
local p = h:getPos()
check('getPos returns a table', type(p) == 'table' and p.x ~= nil and p.y ~= nil)
check('setPos x round-trips', p.x == 120, p and p.x)
check('setPos y round-trips', p.y == 90, p and p.y)

-- Visibility toggles are chainable and safe.
check('hide() chainable', h:hide() == h)
check('show() chainable', h:show() == h)
check('setVisible(false) chainable', h:setVisible(false) == h)
h:setVisible(true)

-- setFontSize is a documented no-op kept for Zerobot parity (bitmap font).
check('setFontSize chainable no-op', h:setFontSize(14) == h)

-- A short on-screen demo loop (purely cosmetic) so a human can SEE the HUD.
local frame = 0
local palette = { { 255, 255, 0 }, { 0, 255, 0 }, { 0, 200, 255 }, { 255, 120, 120 } }
local anim = Timer('test_hud_text.anim', function()
  frame = frame + 1
  local c = palette[((frame - 1) % #palette) + 1]
  h:setText('HUD frame ' .. frame)
  h:setColor(c[1], c[2], c[3])
end, 600, true)

-- Watchdog: tear the HUD + animation down after 4s and print the summary. After
-- destroy, methods must stay SAFE (no error) -- assert that explicitly.
-- NOTE: this Timer port does NOT pass the instance to the callback, so we
-- capture the handle in `cleanupTimer` and stop THAT (not a `self` arg).
local cleanupTimer
cleanupTimer = Timer('test_hud_text.cleanup', function()
  anim:destroy()
  h:destroy()
  -- Calling into a destroyed HUD must be a harmless no-op (still chainable).
  local okAfter = (h:setText('gone') == h) and (h:setColor(255, 0, 0) == h)
  check('methods safe after destroy()', okAfter)
  if cleanupTimer then cleanupTimer:destroy() end
  print(('--- hud_text: %d passed, %d failed ---'):format(pass, fail))
end, 4000, true)

print('[info] test_hud_text.lua: a text HUD is on screen; it self-destroys in 4s')
