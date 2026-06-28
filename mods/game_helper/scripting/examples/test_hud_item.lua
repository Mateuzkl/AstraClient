--[[============================================================================
  test_hud_item.lua  --  self-test for item / spell-icon / outfit HUDs
  ============================================================================
  WHAT IT COVERS (scripting/api/hud.lua):
    * HUD(x, y, itemId)            item HUD (NUMBER value -> 'item' kind)
    * :setItemId(id)              swap the rendered item sprite
    * HUD.newSpellIcon(x,y,id)    spell-icon HUD (UISprite)
    * :setSpellIconId(id)         swap the sprite id
    * HUD.newOutfit(x,y,outfitId) outfit HUD (UICreature, animated)
    * :setOutfit{...} / :setOutfitId / :setOutfitAddons /
      :setOutfitColors / :setOutfitDirection / :setOutfitMoving
    * :setScale / :setOpacity / :setSize   render tweaks
    * all three handles destroyed at the end

  HOW TO RUN: enable in the Scripting tab WHILE IN GAME. Three little overlays
  appear in a row top-left: an item icon, a spell icon, and an animated outfit.
  They self-destroy after ~4s; the console prints the PASS/FAIL summary.

  NOTE on ids: 3031 is the classic gold-coin item id and 1 is a safe outfit id;
  if a sprite is missing in the loaded assets the widget simply renders blank --
  the API calls still succeed (they are pcall-guarded), which is what we test.

  SAFETY: cosmetic only. All three HUD handles are tracked and destroyed by a 4s
  watchdog Timer (engine also cleans up on unload). No game state is touched.
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

-- ---- item HUD (numeric value selects 'item' kind) -------------------------
local GOLD = 3031
local item = HUD(60, 60, GOLD)
check('item HUD created', item ~= nil)
check('item getId() numeric', type(item:getId()) == 'number')
check('setItemId chainable', item:setItemId(GOLD) == item)
check('setSize chainable', item:setSize(40, 52) == item)
check('setOpacity chainable', item:setOpacity(0.9) == item)

-- ---- spell-icon HUD -------------------------------------------------------
local spell = HUD.newSpellIcon(110, 60, 1)
check('spell-icon HUD created', spell ~= nil)
check('setSpellIconId chainable', spell:setSpellIconId(2) == spell)
check('spell setScale chainable', spell:setScale(1.0) == spell)

-- ---- outfit HUD -----------------------------------------------------------
local outfit = HUD.newOutfit(160, 60, 1)
check('outfit HUD created', outfit ~= nil)
check('setOutfit(table) chainable', outfit:setOutfit({ type = 1, addons = 0 }) == outfit)
check('setOutfitId chainable', outfit:setOutfitId(2) == outfit)
check('setOutfitAddons chainable', outfit:setOutfitAddons(3) == outfit)
check('setOutfitColors chainable', outfit:setOutfitColors(10, 20, 30, 40) == outfit)
check('setOutfitDirection chainable', outfit:setOutfitDirection(2) == outfit)
check('setOutfitMoving chainable', outfit:setOutfitMoving(true) == outfit)

-- Distinct ids prove three independent elements were allocated.
check('three distinct HUD ids',
  item:getId() ~= spell:getId()
    and spell:getId() ~= outfit:getId()
    and item:getId() ~= outfit:getId())

-- A tiny rotation animation on the outfit so the human eye sees it is alive.
local dir = 0
local spin = Timer('test_hud_item.spin', function()
  dir = (dir + 1) % 4
  outfit:setOutfitDirection(dir)
end, 700, true)

-- Watchdog: destroy all three + the spinner after 4s, verify post-destroy
-- safety, print summary.
-- NOTE: this Timer port does NOT pass the instance to the callback, so we
-- capture the handle in `cleanupTimer` and stop THAT (not a `self` arg).
local cleanupTimer
cleanupTimer = Timer('test_hud_item.cleanup', function()
  spin:destroy()
  item:destroy()
  spell:destroy()
  outfit:destroy()
  local okAfter = (item:setItemId(GOLD) == item)
    and (spell:setSpellIconId(1) == spell)
    and (outfit:setOutfitId(1) == outfit)
  check('all methods safe after destroy()', okAfter)
  if cleanupTimer then cleanupTimer:destroy() end
  print(('--- hud_item: %d passed, %d failed ---'):format(pass, fail))
end, 4000, true)

print('[info] test_hud_item.lua: item + spell + outfit HUDs shown; gone in 4s')
