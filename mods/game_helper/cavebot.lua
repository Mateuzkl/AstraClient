--[[
  Cavebot for AstraClient
  -----------------------
  A waypoint auto-walking bot mounted as a 4th tab inside the game_helper window.

  Design (agreed with the user):
    * Navigation only + pause: walks/uses waypoints and PAUSES when monsters are near.
      Combat is left to the existing Helper (auto-target + shooter).
    * Full waypoint set, including custom Lua scripting.
    * Recording: click on the game map AND "add current position".

  This script shares the (sandboxed) module environment with helper.lua, but it
  CANNOT see helper.lua's file-locals (helper, mouseGrabberWidget, panels, ...).
  Therefore helper.lua hands us the window via Cavebot.init(window) and we create
  our own widgets / mouse grabber. Only `helperConfig` and the global functions
  (loadMenu, consoleln, tr, tosize, ...) are shared.

  Navigation uses the native async pathfinder: player:autoWalk(destPos).
]]

Cavebot = {}

-- ---------------------------------------------------------------------------
-- Module state
-- ---------------------------------------------------------------------------
local helperWindow = nil   -- the game_helper window (passed by helper.lua)
local panel        = nil   -- CavebotPanel
local grabber      = nil   -- our own mouse grabber for map-click recording
local wpList       = nil   -- TextList of waypoints
local statusLabel  = nil
local enableButton = nil
local tabContainer = nil   -- horizontal strip holding the waypoint-tab buttons
local recordButton = nil   -- "Record Path" toggle button

local loopEvent  = nil
local selIndex   = 0       -- currently selected waypoint row (0 = none)
local recording  = false   -- path recorder active?
local lastRecSave = 0      -- throttle disk writes while recording
local gotoChain   = 0      -- consecutive label/goto dispatches (malformed-loop guard)
local hudButton    = nil   -- "HUD: On/Off" toggle
local hotkeyButton = nil   -- "Set Hotkey" button (shows the bound combo)
local hudEvent     = nil   -- cycleEvent that refreshes the on-map waypoint marks
local hudKey       = nil   -- HUD dirty-check key (reset by refreshList on any list change)
local trackerStatusWidget = nil -- the Cavebot row in the Helper Stats mini-window
local hotkeyBound  = nil   -- the key combo currently bound (to unbind it)
local hotkeyWindow = nil   -- transient key-capture window
local settingsWindow = nil -- transient settings modal
local profilesWindow = nil -- transient profiles (export/import) window

local COLOR_GREEN  = '#44ad25'
local COLOR_RED    = '#cc4444'
local COLOR_ORANGE = '#d0902f'

-- Run-speed -> per-node lure wait scale: wait = (100 - speed) * RUN_SPEED_MS ms.
-- 10% -> 2700ms, 50% -> 1500ms, 100% -> 0 (no wait, sprint the route).
local RUN_SPEED_MS = 30

-- When the walk engine stops before reaching a waypoint the next tile is almost always
-- a creature that stepped into the path (routine while a lured pack follows). Re-issue
-- autoWalk on this cadence so the pathfinder routes AROUND the blocker (creatures are
-- obstacles in findPath) instead of standing still until stuckMs. Box (luring) and Cait
-- (kiting) must keep moving smoothly past blockers, so they re-path fast; Single only
-- walks to the next creature, so a calmer cadence is enough.
local LURE_REPATH_MS    = 250
local BLOCKED_REPATH_MS = 600

-- runtime walking state
local rt = {
  index        = 1,
  waitUntil    = 0,
  lastPos      = nil,
  lastTarget   = nil,
  stuckSince   = 0,
  retries      = 0,
  floorExpectZ = nil,  -- target z while verifying a rope/ladder/use floor change
  floorSince   = 0,
  floorRetried = 0,
  recovered    = 0,       -- anti-stuck "return to nearest waypoint" attempts
  recoveryTarget = false, -- is the current index a recovery jump (don't credit as progress)?
  crossFloorSince = 0,    -- dedicated timer for the cross-floor settle wait
  fighting     = false,   -- box/cait hysteresis: are we in the "kill/kite" phase right now?
  repathSince  = 0,       -- timer for re-pathing around a creature blocking the route
  onScreen     = 0,       -- reachable monsters on screen (cached by huntGate for walkTo)
}

local function defaultConfig()
  return {
    enabled  = false,
    selected = 'Default',
    configs  = { ['Default'] = { waypoints = {} } },
    tabOrder = { 'Default' },
    settings = { pauseRange = 4, tolerance = 1, stuckMs = 3000, actionDelay = 600,
                 floorTimeout = 2000, floorRetries = 2, recoverRetries = 2,
                 recordInterval = 3, hud = false,
                 recordType = 'walk',  -- nodes dropped by the recorder: 'walk' | 'stand'
                 runSpeed = 100,       -- 10..100; <100 waits at each node so creatures lure
                 reachRadius = 2,      -- 1 = step on the exact tile, 2 = any adjacent tile, ...
                 huntMode = 'single', -- 'single' | 'box' | 'cait'
                 huntStart = 5,  -- box/cait: engage when reachable monsters on screen >= start
                 huntStop = 0,   -- box/cait: resume walking when reachable monsters on screen <= stop
                 startNearest = false },    -- on enable, jump to the waypoint nearest the player
  }
end

local cfg = defaultConfig()

-- Forward declarations (functions that reference one another)
local refreshList, selectRow, showWaypointMenu, editWaypoint
local moveWaypoint, removeWaypoint, insertWaypoint, captureMapClick
local rebuildTabs, selectTab, syncEnableButton, setStatus
local resetWalkState, advance, gotoLabel, recoverToNearest
local onRecordStep

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
local function chebyshev(a, b)
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

local function isSummon(c)
  if not c.getType then return false end
  local t = c:getType()
  return t == CreatureTypeSummonOwn or t == CreatureTypeSummonOther
end

-- Count of live, REACHABLE monsters roughly on screen (the visible viewport ~15x11;
-- 8x6 covers it with a margin). "Reachable" = line of sight clear (g_map.isSightClear,
-- the same test the Helper uses to decide what it can engage) -> a monster locked in an
-- unreachable room never counts, so the hunt modes don't freeze waiting on it. Used by
-- all hunt modes (Single/Box/Cait).
local function monstersOnScreen(pos)
  local list = g_map.getSpectatorsInRange(pos, false, 8, 6)
  if not list then return 0 end
  local count = 0
  for _, c in ipairs(list) do
    if c and not c:isLocalPlayer() and c:isMonster() and c:getHealthPercent() > 0 and not isSummon(c)
       and g_map.isSightClear(pos, c:getPosition()) then
      count = count + 1
    end
  end
  return count
end

local function currentList()
  local c = cfg.configs[cfg.selected]
  if not c then
    cfg.selected = next(cfg.configs) or 'Default'
    cfg.configs[cfg.selected] = cfg.configs[cfg.selected] or { waypoints = {} }
    c = cfg.configs[cfg.selected]
  end
  c.waypoints = c.waypoints or {}
  return c.waypoints
end

-- Nearest walk/stand waypoint on the player's floor (including the tile under the
-- player), for the "start from nearest waypoint" option on enable.
local function nearestStartIndex(pos)
  local best, bestD
  for i, w in ipairs(currentList()) do
    if (w.type == 'walk' or w.type == 'stand') and w.z == pos.z then
      local d = chebyshev(pos, w)
      if not bestD or d < bestD then best, bestD = i, d end
    end
  end
  return best
end

-- ---------------------------------------------------------------------------
-- Persistence (per-character cavebot.json)
-- ---------------------------------------------------------------------------
local function configPath()
  if not LoadedPlayer or not LoadedPlayer:isLoaded() then return nil end
  return '/characterdata/' .. LoadedPlayer:getId() .. '/cavebot.json'
end

local function save()
  local path = configPath()
  if not path then return end
  local ok, res = pcall(function() return json.encode(cfg, 2) end)
  if ok and res then
    g_resources.writeFileContents(path, res)
  end
end

local function sanitize()
  if type(cfg) ~= 'table' then cfg = defaultConfig() end
  cfg.configs  = cfg.configs or { ['Default'] = { waypoints = {} } }
  if not next(cfg.configs) then cfg.configs['Default'] = { waypoints = {} } end
  for _, c in pairs(cfg.configs) do c.waypoints = c.waypoints or {} end
  if not cfg.selected or not cfg.configs[cfg.selected] then
    cfg.selected = next(cfg.configs)
  end
  -- Tab order: a stable display order for the tab strip. Drop stale/duplicate
  -- names, then append any config missing from it (migrates an old json that
  -- predates tabs). 'Default' stays first when present.
  cfg.tabOrder = cfg.tabOrder or {}
  local seen = {}
  for i = #cfg.tabOrder, 1, -1 do
    local n = cfg.tabOrder[i]
    if type(n) ~= 'string' or not cfg.configs[n] or seen[n] then
      table.remove(cfg.tabOrder, i)
    else
      seen[n] = true
    end
  end
  if cfg.configs['Default'] and not seen['Default'] then
    table.insert(cfg.tabOrder, 1, 'Default'); seen['Default'] = true
  end
  for name in pairs(cfg.configs) do
    if not seen[name] then table.insert(cfg.tabOrder, name); seen[name] = true end
  end
  cfg.settings = cfg.settings or {}
  cfg.settings.pauseRange  = cfg.settings.pauseRange  or 4
  cfg.settings.tolerance   = cfg.settings.tolerance   or 1
  cfg.settings.stuckMs     = cfg.settings.stuckMs     or 3000
  cfg.settings.actionDelay = cfg.settings.actionDelay or 600
  cfg.settings.floorTimeout   = cfg.settings.floorTimeout   or 2000
  cfg.settings.floorRetries   = cfg.settings.floorRetries   or 2
  cfg.settings.recoverRetries = cfg.settings.recoverRetries or 2
  cfg.settings.recordInterval = cfg.settings.recordInterval or 3
  if cfg.settings.recordInterval < 1 then cfg.settings.recordInterval = 1 end
  if cfg.settings.hud == nil then cfg.settings.hud = false end
  -- New cavebot settings (with migration from older json).
  cfg.settings.recordType = (cfg.settings.recordType == 'stand') and 'stand' or 'walk'
  cfg.settings.runSpeed = tonumber(cfg.settings.runSpeed) or 100
  cfg.settings.runSpeed = math.max(10, math.min(100, math.floor(cfg.settings.runSpeed / 10 + 0.5) * 10))
  -- reachRadius: migrate from the old `tolerance` (chebyshev<=tol) -> radius = tol+1.
  cfg.settings.reachRadius = tonumber(cfg.settings.reachRadius) or ((cfg.settings.tolerance or 1) + 1)
  cfg.settings.reachRadius = math.max(1, math.min(10, math.floor(cfg.settings.reachRadius)))
  -- Hunt mode: single | box | cait (migrate the old 'cavebot' normal mode -> single).
  local hm = cfg.settings.huntMode
  if hm == 'cavebot' then hm = 'single' end
  if hm ~= 'box' and hm ~= 'cait' and hm ~= 'single' then hm = 'single' end
  cfg.settings.huntMode = hm
  -- box/cait creature thresholds (Start = engage, Stop = resume), migrated from the old
  -- per-mode boxMax/boxMin. Hysteresis needs Stop < Start so the fight phase can resume.
  cfg.settings.huntStart = math.max(1, math.floor(tonumber(cfg.settings.huntStart or cfg.settings.boxMax) or 5))
  cfg.settings.huntStop  = math.max(0, math.floor(tonumber(cfg.settings.huntStop  or cfg.settings.boxMin) or 0))
  if cfg.settings.huntStop > cfg.settings.huntStart then
    cfg.settings.huntStart, cfg.settings.huntStop = cfg.settings.huntStop, cfg.settings.huntStart
  end
  if cfg.settings.huntStop >= cfg.settings.huntStart then cfg.settings.huntStop = cfg.settings.huntStart - 1 end
  cfg.settings.boxMax, cfg.settings.boxMin, cfg.settings.caitMax, cfg.settings.caitMin = nil, nil, nil, nil
  if cfg.settings.startNearest == nil then cfg.settings.startNearest = false end
  -- Never auto-resume a bot right after login.
  cfg.enabled = false
end

local function load()
  cfg = defaultConfig()
  local path = configPath()
  if path and g_resources.fileExists(path) then
    local ok, res = pcall(function() return json.decode(g_resources.readFileContents(path)) end)
    if ok and type(res) == 'table' then
      cfg = res
    end
  end
  sanitize()
end

-- ---------------------------------------------------------------------------
-- Waypoint label / list rendering
-- ---------------------------------------------------------------------------
local function wpLabel(wp)
  local t = wp.type
  if t == 'walk' then
    return string.format('Walk   [%d, %d, %d]', wp.x, wp.y, wp.z)
  elseif t == 'stand' then
    return string.format('Stand  [%d, %d, %d]', wp.x, wp.y, wp.z)
  elseif t == 'use' then
    return string.format('Use    [%d, %d, %d]', wp.x, wp.y, wp.z)
  elseif t == 'usewith' then
    return string.format('UseW %d [%d, %d, %d]', wp.itemId or 0, wp.x, wp.y, wp.z)
  elseif t == 'label' then
    return 'Label: ' .. tostring(wp.name)
  elseif t == 'goto' then
    return 'Goto: ' .. tostring(wp.label)
  elseif t == 'say' then
    return 'Say: "' .. tostring(wp.text) .. '"'
  elseif t == 'delay' then
    return string.format('Delay %dms', wp.ms or 0)
  elseif t == 'lua' then
    local code = tostring(wp.code or ''):gsub('%s+', ' ')
    return 'Lua: ' .. code:sub(1, 22)
  end
  return tostring(t or '?')
end

refreshList = function()
  hudKey = nil -- the list changed (add/remove/reorder/edit) -> rebuild the HUD marks
  if not wpList then return end
  wpList:destroyChildren()
  local wps = currentList()
  if selIndex > #wps then selIndex = 0 end
  for i, wp in ipairs(wps) do
    local row = g_ui.createWidget('CavebotWaypoint', wpList)
    row:setText(string.format('%02d  %s', i, wpLabel(wp)))
    row.wpIndex = i
    row:setOn(i == selIndex)
    row.onClick = function(self) selectRow(self.wpIndex) end
    row.onMousePress = function(self, mousePos, button)
      if button == MouseRightButton then
        showWaypointMenu(self.wpIndex, mousePos)
        return true
      end
      return false
    end
  end
end

selectRow = function(idx)
  selIndex = idx
  if not wpList then return end
  for _, child in ipairs(wpList:getChildren()) do
    child:setOn(child.wpIndex == idx)
  end
end

showWaypointMenu = function(idx, mousePos)
  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  menu:addOption(tr('Go to here'), function() rt.index = idx; resetWalkState() end)
  menu:addOption(tr('Edit'),       function() editWaypoint(idx) end)
  menu:addOption(tr('Move Up'),    function() moveWaypoint(idx, -1) end)
  menu:addOption(tr('Move Down'),  function() moveWaypoint(idx, 1) end)
  menu:addOption(tr('Remove'),     function() removeWaypoint(idx) end)
  menu:display(mousePos)
end

moveWaypoint = function(idx, delta)
  local wps = currentList()
  local j = idx + delta
  if j < 1 or j > #wps then return end
  wps[idx], wps[j] = wps[j], wps[idx]
  selIndex = j
  resetWalkState() -- the live index may now point at a different waypoint
  refreshList()
  save()
end

removeWaypoint = function(idx)
  local wps = currentList()
  if not wps[idx] then return end
  table.remove(wps, idx)
  if rt.index > #wps then rt.index = math.max(1, #wps) end
  selIndex = 0
  resetWalkState() -- don't carry stale floor/recovery state onto the shifted index
  refreshList()
  save()
end

insertWaypoint = function(wp)
  local wps = currentList()
  local at = (selIndex >= 1 and selIndex <= #wps) and (selIndex + 1) or (#wps + 1)
  table.insert(wps, at, wp)
  selIndex = at
  refreshList()
  save()
end

-- ---------------------------------------------------------------------------
-- Input prompt wrappers (reuse corelib UIInputBox)
-- ---------------------------------------------------------------------------
local function textPrompt(title, label, default, cb)
  local box = UIInputBox.create(title, function(text) cb(text) end, nil)
  box:addLineEdit(label, default or '', 2000)
  box:display()
end

local function numberPrompt(title, label, value, minv, maxv, step, cb)
  local box = UIInputBox.create(title, function(v) cb(tonumber(v) or value or 0) end, nil)
  box:addSpinBox(label, minv, maxv, value, step)
  box:display()
end

local function codePrompt(title, default, cb)
  local box = UIInputBox.create(title, function(code) cb(code) end, nil)
  box:addTextEdit(tr('Lua code'), default or '', 8192, 8)
  box:display()
end

-- ---------------------------------------------------------------------------
-- Map-click capture (mirrors helper.lua assignRune pattern, own grabber)
-- ---------------------------------------------------------------------------
captureMapClick = function(callback)
  if not grabber then return end
  g_mouse.updateGrabber(grabber, 'target')
  grabber:grabMouse()
  if helperWindow then helperWindow:hide() end
  g_mouse.pushCursor('target')
  grabber.onMouseRelease = function(self, mousePosition, mouseButton)
    g_mouse.updateGrabber(grabber, 'target')
    grabber:ungrabMouse()
    if helperWindow then helperWindow:show() end
    g_mouse.popCursor('target')
    grabber.onMouseRelease = nil

    local root = g_ui.getRootWidget()
    local clicked = root and root:recursiveGetChildByPos(mousePosition, false)
    if clicked and clicked:getClassName() == 'UIGameMap' then
      local pos = clicked:getPosition(mousePosition)
      if pos then
        callback(pos)
        return true
      end
    end
    if modules.game_textmessage then
      modules.game_textmessage.displayFailureMessage(tr('Invalid map position!'))
    end
    return true
  end
end

-- ---------------------------------------------------------------------------
-- Toolbar actions (called from cavebot.otui @onClick) -> GLOBAL functions
-- ---------------------------------------------------------------------------
local function playerPos()
  local p = g_game.getLocalPlayer()
  return p and p:getPosition() or nil
end

function cavebotAddWalkHere()
  local pos = playerPos()
  if pos then insertWaypoint({ type = 'walk', x = pos.x, y = pos.y, z = pos.z }) end
end

function cavebotAddByMapClick()
  captureMapClick(function(pos)
    insertWaypoint({ type = 'walk', x = pos.x, y = pos.y, z = pos.z })
  end)
end

function cavebotAddStand()
  captureMapClick(function(pos)
    insertWaypoint({ type = 'stand', x = pos.x, y = pos.y, z = pos.z })
  end)
end

function cavebotAddUse()
  captureMapClick(function(pos)
    insertWaypoint({ type = 'use', x = pos.x, y = pos.y, z = pos.z })
  end)
end

function cavebotAddUseWith()
  captureMapClick(function(pos)
    numberPrompt(tr('Tool Item ID'), tr('Item ID (rope 3003, shovel 3457, ...)'), 3003, 0, 999999, 1, function(id)
      insertWaypoint({ type = 'usewith', itemId = tonumber(id) or 0, x = pos.x, y = pos.y, z = pos.z })
    end)
  end)
end

function cavebotAddLabel()
  textPrompt(tr('Add Label'), tr('Label name'), '', function(name)
    if name and #name > 0 then insertWaypoint({ type = 'label', name = name }) end
  end)
end

function cavebotAddGoto()
  textPrompt(tr('Add Goto'), tr('Target label'), '', function(name)
    if name and #name > 0 then insertWaypoint({ type = 'goto', label = name }) end
  end)
end

function cavebotAddSay()
  textPrompt(tr('Add Say'), tr('Text to say'), '', function(text)
    if text and #text > 0 then insertWaypoint({ type = 'say', text = text }) end
  end)
end

function cavebotAddDelay()
  numberPrompt(tr('Add Delay'), tr('Milliseconds'), 1000, 0, 600000, 100, function(ms)
    insertWaypoint({ type = 'delay', ms = tonumber(ms) or 0 })
  end)
end

function cavebotAddLua()
  codePrompt(tr('Add Lua Waypoint'), '', function(code)
    if code and #code > 0 then insertWaypoint({ type = 'lua', code = code }) end
  end)
end

-- ---------------------------------------------------------------------------
-- Path recorder: append a Walk node every time you step to a new tile
-- ---------------------------------------------------------------------------
local function recordAppend(pos)
  local wps = currentList()
  local last = wps[#wps]
  if last and last.x and last.y and last.z then
    if last.x == pos.x and last.y == pos.y and last.z == pos.z then
      return -- exact same tile
    end
    -- Sparse recording (like real cavebots): on the SAME floor only drop a node
    -- every `recordInterval` sqm (autoWalk pathfinds the gaps). ALWAYS drop one on
    -- a floor change so rope/ladder/stairs transitions are captured exactly.
    if last.z == pos.z and chebyshev(pos, last) < (cfg.settings.recordInterval or 3) then
      return
    end
  end
  local recType = (cfg.settings.recordType == 'stand') and 'stand' or 'walk'
  table.insert(wps, { type = recType, x = pos.x, y = pos.y, z = pos.z })
  selIndex = #wps
  refreshList()
  -- Throttle disk writes (don't write per step) but bound crash loss to ~5s.
  local now = g_clock.millis()
  if now - lastRecSave > 5000 then lastRecSave = now; save() end
end

onRecordStep = function(localPlayer, newPos, oldPos)
  if not recording or not localPlayer or not localPlayer:isLocalPlayer() then return end
  if newPos then recordAppend(newPos) end
end

function cavebotToggleRecord()
  if not g_game.isOnline() then return end
  recording = not recording
  if recording then
    -- Recording the route while the bot auto-walks it makes no sense.
    if cfg.enabled then cfg.enabled = false; syncEnableButton() end
    local pos = playerPos()
    if pos then recordAppend(pos) end -- seed with the tile you start on
  else
    save()
  end
  if recordButton then
    recordButton:setText(recording and tr('Stop Recording') or tr('Record Path'))
    recordButton:setImageColor(recording and '#cc4444' or '#3d7fc2') -- red recording / blue idle
  end
  if recording then
    setStatus(tr('Recording path...'), COLOR_ORANGE)
  else
    syncEnableButton()
  end
end

-- Clear every waypoint of the current config (with a confirm; destructive).
function cavebotClearWaypoints()
  local wps = currentList()
  if #wps == 0 then return end
  local box
  -- The message box does NOT auto-close on a button click; its button callback
  -- must close it (and release the input lock it took). Destroy it from every path.
  local function close()
    if box then box:destroy(); box = nil end
  end
  local function doClear()
    if cfg.enabled then cfg.enabled = false end
    if recording then
      recording = false
      if recordButton then recordButton:setText(tr('Record Path')) end
    end
    local list = currentList()
    for i = #list, 1, -1 do list[i] = nil end
    rt.index = 1
    selIndex = 0
    gotoChain = 0
    resetWalkState()
    refreshList()
    syncEnableButton()
    save()
    close()
  end
  box = displayGeneralBox(tr('Clear Waypoints'),
    tr('Remove all %d waypoints from "%s"?', #wps, tostring(cfg.selected)),
    { { text = tr('Yes'), callback = doClear },
      { text = tr('No'),  callback = close } },
    doClear, close) -- onEnter = Yes, onEscape = close
end

-- ---------------------------------------------------------------------------
-- HUD: mark each waypoint's tile on the game window, colored by action type
-- ---------------------------------------------------------------------------
-- Only positioned waypoints (walk/stand/use/usewith) get a tile marker; label/
-- goto/say/delay/lua have no x,y so they're never on the map. ('goto' is a Lua
-- keyword anyway and can't be a bare table key.)
local HUD_COLORS = {
  walk    = '#33cc33',  -- green
  stand   = '#2f9bff',  -- blue
  use     = '#ff9933',  -- orange
  usewith = '#ffcc33',  -- amber
}

-- Short type names shown in the on-map label, e.g. "31. Walk".
local TYPE_LABEL = { walk = 'Walk', stand = 'Stand', use = 'Use', usewith = 'UseW' }

local hudShown = false -- are any marks currently pushed to the C++ overlay?

local function hudClear()
  g_map.clearCavebotMarks()
  hudShown = false
  hudKey = nil
end

-- Feeds the native map overlay (drawn on TOP of the map, under the UI, following the
-- smooth scroll) with a colored marker + "<order>. <Type>" label for every positioned
-- waypoint on the player's floor within view. The C++ side re-projects each map position
-- every frame, so we only rebuild the LIST when the floor/route/visible-set changes.
local function updateHud()
  if not cfg.settings.hud or not g_game.isOnline() then
    if hudShown then hudClear() end
    return
  end
  local p = g_game.getLocalPlayer()
  if not p then return end
  local pos = p:getPosition()
  -- reach drives the on-map square size, so it's part of the dirty key (changing it in
  -- Settings re-renders the marks). Walk uses radius reach-1; Stand/others = exact tile.
  local reach = math.max(1, math.floor(cfg.settings.reachRadius or 2))
  local key = pos.x .. ',' .. pos.y .. ',' .. pos.z .. '|' .. tostring(cfg.selected) .. '|' .. #currentList() .. '|' .. reach
  if key == hudKey then return end
  hudKey = key
  g_map.clearCavebotMarks()
  local pz = pos.z
  for i, wp in ipairs(currentList()) do
    -- only positioned nodes on this floor AND near the view; the native overlay culls
    -- by floor, and bounding the list near-screen keeps a long route's draw cost low.
    if wp.x and wp.z == pz and chebyshev(pos, wp) <= 10 then
      -- Walk draws the reach square (radius = reachRadius-1: 1->1x1, 2->3x3, 3->5x5);
      -- Stand always demands the exact tile, and use/usewith aren't walked-to with a
      -- tolerance, so both stay 1x1.
      local radius = (wp.type == 'walk') and (reach - 1) or 0
      g_map.addCavebotMark({ x = wp.x, y = wp.y, z = wp.z },
        HUD_COLORS[wp.type] or '#ffffff',
        string.format('%d. %s', i, TYPE_LABEL[wp.type] or tostring(wp.type)),
        radius)
    end
  end
  hudShown = true
end

function cavebotToggleHud()
  cfg.settings.hud = not cfg.settings.hud
  if hudButton then
    hudButton:setText(cfg.settings.hud and tr('HUD: On') or tr('HUD: Off'))
  end
  updateHud()
  save()
end

-- Settings modal: recording, movement/lure and hunt-mode tuning in one place.
-- Min/max/step are set in Lua (the OTUI props apply on a deferred event, after setValue).
function cavebotOpenSettings()
  if settingsWindow then settingsWindow:destroy(); settingsWindow = nil end
  local w = g_ui.createWidget('CavebotSettings', g_ui.getRootWidget())
  settingsWindow = w
  local s = cfg.settings

  -- Recording
  initPercentSelector(w.recIntervalBox, s.recordInterval or 3, 1, 50, 1, '')
  w.recTypeBox:clearOptions()
  w.recTypeBox:addOption('Walk', 'walk')
  w.recTypeBox:addOption('Stand', 'stand')
  w.recTypeBox:setCurrentOption(s.recordType == 'stand' and 'Stand' or 'Walk', true)

  -- Movement (run speed in 10% steps; reach radius / record interval are plain counts)
  initPercentSelector(w.runSpeedBox, s.runSpeed or 100, 10, 100, 10, '%')
  initPercentSelector(w.reachRadiusBox, s.reachRadius or 2, 1, 10, 1, '')
  w.startNearestCheck:setChecked(s.startNearest and true or false)

  -- Hunt mode: Single / Box / Cait. Start/Stop (creature counts) only apply to Box/Cait.
  w.huntModeBox:clearOptions()
  w.huntModeBox:addOption('Single', 'single')
  w.huntModeBox:addOption('Box', 'box')
  w.huntModeBox:addOption('Cait', 'cait')
  w.huntModeBox:setCurrentOption(({ single = 'Single', box = 'Box', cait = 'Cait' })[s.huntMode or 'single'] or 'Single', true)
  initPercentSelector(w.huntStartBox, s.huntStart or 5, 1, 99, 1, '')
  initPercentSelector(w.huntStopBox, s.huntStop or 0, 0, 99, 1, '')
  local function syncHuntFields()
    local m = w.huntModeBox:getCurrentOption()
    local enable = (m and m.data) ~= 'single' -- Single ignores Start/Stop (stops at 1st creature)
    w.huntStartBox:setEnabled(enable)
    w.huntStopBox:setEnabled(enable)
  end
  w.huntModeBox.onOptionChange = syncHuntFields
  syncHuntFields()

  local function close()
    if settingsWindow then settingsWindow:destroy(); settingsWindow = nil end
  end
  w.cancelButton.onClick = close
  w.saveButton.onClick = function()
    s.recordInterval = math.max(1, getPercentValue(w.recIntervalBox))
    local rt2 = w.recTypeBox:getCurrentOption()
    s.recordType = (rt2 and rt2.data) or 'walk'
    s.runSpeed = math.max(10, math.min(100, getPercentValue(w.runSpeedBox)))
    s.reachRadius = math.max(1, math.min(10, getPercentValue(w.reachRadiusBox)))
    s.startNearest = w.startNearestCheck:isChecked()
    local hmo = w.huntModeBox:getCurrentOption()
    s.huntMode = (hmo and hmo.data) or 'single'
    s.huntStart = math.max(1, getPercentValue(w.huntStartBox))
    s.huntStop  = math.max(0, getPercentValue(w.huntStopBox))
    -- Hysteresis needs Stop < Start (engage at the higher count, resume at the lower). If the
    -- user typed them reversed, SWAP so BOTH typed numbers survive instead of silently
    -- collapsing Stop to Start-1; only nudge Stop down when the two are equal.
    if s.huntStop > s.huntStart then s.huntStart, s.huntStop = s.huntStop, s.huntStart end
    if s.huntStop >= s.huntStart then s.huntStop = s.huntStart - 1 end
    -- Apply the new mode to the RUNNING bot right away: drop the fight/kite phase and
    -- the walk state so the next tick re-evaluates under the new mode (and re-issues a
    -- fresh autoWalk), instead of the change only taking effect after a disable/enable.
    rt.fighting = false
    resetWalkState()
    hudKey = nil        -- force the HUD list to rebuild (labels/colors may differ)
    save()
    close()
  end
end

-- ---------------------------------------------------------------------------
-- Hotkey: bind a user key combo to toggle the cavebot on/off
-- ---------------------------------------------------------------------------
local function syncHotkeyButton()
  if not hotkeyButton then return end
  local c = cfg.hotkeyCombo
  hotkeyButton:setText((c and #c > 0) and tr('Key: %s', c) or tr('Set Hotkey'))
end

local function bindHotkey()
  local root = g_ui.getRootWidget()
  if hotkeyBound then
    g_keyboard.unbindKeyDown(hotkeyBound, cavebotToggle, root)
    hotkeyBound = nil
  end
  local c = cfg.hotkeyCombo
  if c and #c > 0 then
    g_keyboard.bindKeyDown(c, cavebotToggle, root)
    hotkeyBound = c
  end
end

function cavebotBindHotkey()
  if hotkeyWindow then hotkeyWindow:destroy(); hotkeyWindow = nil end
  local window = g_ui.createWidget('CavebotHotkeyWindow', g_ui.getRootWidget())
  hotkeyWindow = window
  window:show()
  g_client.setInputLockWidget(window) -- modal: keys go here, not to the game
  window:raise()
  window:focus()
  window:grabKeyboard()

  -- Warn (like the other hotkey windows) when the combo is already bound by the
  -- game keybinds, an action-bar button, or a custom hotkey. KeyBinds:isUsedHotkey
  -- is the shared check those windows use; pcall it so a missing module can't break
  -- capture. (The cavebot's own bind isn't registered there, so re-picking it here
  -- never false-warns.)
  local function updateWarning(combo)
    local used = false
    if combo and #combo > 0 then
      pcall(function() used = (KeyBinds and KeyBinds:isUsedHotkey(combo)) and true or false end)
    end
    window.warning:setVisible(used)
  end

  window.display:setText(cfg.hotkeyCombo or '')
  window.display.combo = cfg.hotkeyCombo
  updateWarning(cfg.hotkeyCombo)

  local function finish()
    g_client.setInputLockWidget(nil)
    if window then window:destroy() end
    hotkeyWindow = nil
  end

  -- Capture into the display field (don't apply yet — Ok confirms, like the
  -- action-bar hotkey window). Escape cancels; a bare modifier keeps waiting.
  window.onKeyDown = function(win, keyCode, keyboardModifiers, keyText)
    if keyCode == KeyEscape then finish(); return true end
    local combo = determineKeyComboDesc(keyCode, keyboardModifiers, keyText)
    if combo == 'Shift' or combo == 'Ctrl' or combo == 'Alt' then return true end
    win.display:setText(combo or '')
    win.display.combo = combo
    updateWarning(combo)
    return true
  end

  window.buttonOk.onClick = function()
    local combo = window.display.combo
    cfg.hotkeyCombo = (combo and #combo > 0) and combo or nil
    bindHotkey()
    syncHotkeyButton()
    save()
    finish()
  end
  window.buttonClear.onClick = function()
    cfg.hotkeyCombo = nil
    bindHotkey()
    syncHotkeyButton()
    save()
    finish()
  end
  window.buttonClose.onClick = finish
end

-- ---------------------------------------------------------------------------
-- Profiles: export/import the WHOLE cavebot (every tab + its waypoints + all
-- settings) to a named JSON file under /cavebots/, so a setup can be saved,
-- swapped between characters and shared. Distinct from the automatic per-character
-- cavebot.json that just persists the live state.
-- ---------------------------------------------------------------------------
local PROFILES_DIR = '/cavebots'

local function profilePath(name) return PROFILES_DIR .. '/' .. name .. '.json' end

local function profileNames()
  local names = {}
  pcall(function()
    for _, f in ipairs(g_resources.listDirectoryFiles(PROFILES_DIR) or {}) do
      local n = tostring(f):match('^(.+)%.json$')
      if n then names[#names + 1] = n end
    end
  end)
  table.sort(names)
  return names
end

local function saveProfile(name)
  if not name or #name == 0 then return false end
  name = name:gsub('[/\\:%*%?"<>|]', '_') -- strip filename-illegal chars
  pcall(function() g_resources.makeDir(PROFILES_DIR) end)
  -- enabled is intentionally omitted: a loaded profile always starts disabled.
  local data = { selected = cfg.selected, configs = cfg.configs, tabOrder = cfg.tabOrder,
                 settings = cfg.settings, hotkeyCombo = cfg.hotkeyCombo }
  local ok, res = pcall(function() return json.encode(data, 2) end)
  if ok and res then
    local wok = pcall(function() g_resources.writeFileContents(profilePath(name), res) end)
    return wok
  end
  return false
end

local function loadProfile(name)
  local path = profilePath(name)
  if not g_resources.fileExists(path) then return false end
  local ok, res = pcall(function() return json.decode(g_resources.readFileContents(path)) end)
  if not ok or type(res) ~= 'table' or type(res.configs) ~= 'table' then return false end
  -- Stop anything in flight before swapping the whole config out from under it.
  recording = false
  if recordButton then recordButton:setText(tr('Record Path')) end
  local pl = g_game.getLocalPlayer()
  if pl and pl.isAutoWalking and pl:isAutoWalking() then pl:stopAutoWalk() end
  cfg = res
  cfg.enabled = false
  sanitize()
  -- Full UI refresh (mirrors Cavebot.online after load()).
  rt.index = 1; rt.fighting = false; gotoChain = 0; hudKey = nil
  resetWalkState()
  rebuildTabs()
  refreshList()
  syncEnableButton()
  syncHotkeyButton()
  bindHotkey()
  if hudButton then hudButton:setText(cfg.settings.hud and tr('HUD: On') or tr('HUD: Off')) end
  save() -- also persist as the live per-character cavebot.json
  return true
end

local function deleteProfile(name)
  pcall(function() g_resources.deleteFile(profilePath(name)) end)
end

-- Reset the WHOLE cavebot to factory defaults (every tab, waypoint and setting).
function cavebotResetConfig()
  local box
  local function dn() if box then box:destroy(); box = nil end end
  box = displayGeneralBox(tr('Reset Cavebot'),
    tr('Reset the ENTIRE cavebot to defaults? This wipes every tab, waypoint and setting.'),
    { { text = tr('Yes'), callback = function()
          recording = false
          if recordButton then recordButton:setText(tr('Record Path')); recordButton:setImageColor('#3d7fc2') end
          local pl = g_game.getLocalPlayer()
          if pl and pl.isAutoWalking and pl:isAutoWalking() then pl:stopAutoWalk() end
          cfg = defaultConfig()
          sanitize()
          rt.index = 1; rt.fighting = false; gotoChain = 0; hudKey = nil
          resetWalkState()
          rebuildTabs(); refreshList(); syncEnableButton(); syncHotkeyButton(); bindHotkey()
          if hudButton then hudButton:setText(cfg.settings.hud and tr('HUD: On') or tr('HUD: Off')) end
          save()
          dn()
        end },
      { text = tr('No'), callback = dn } }, nil, dn)
end

-- Profiles manager window: list saved profiles + Save Current As / Load / Delete.
function cavebotOpenProfiles()
  if profilesWindow then profilesWindow:destroy(); profilesWindow = nil end
  local w = g_ui.createWidget('CavebotProfiles', g_ui.getRootWidget())
  profilesWindow = w
  local listW = w:recursiveGetChildById('profileList')
  local sel = nil

  local function close() if profilesWindow then profilesWindow:destroy(); profilesWindow = nil end end

  local function select(name)
    sel = name
    if listW then for _, c in ipairs(listW:getChildren()) do c:setOn(c.profName == name) end end
  end

  local function doLoad(name)
    if not name then return end
    local box
    local function dn() if box then box:destroy(); box = nil end end
    box = displayGeneralBox(tr('Load Cavebot'),
      tr('Replace the CURRENT cavebot (all tabs, waypoints and settings) with "%s"?', name),
      { { text = tr('Yes'), callback = function() loadProfile(name); dn(); close() end },
        { text = tr('No'),  callback = dn } }, nil, dn)
  end

  local function refresh()
    sel = nil
    if listW then listW:destroyChildren() end
    for _, name in ipairs(profileNames()) do
      local row = g_ui.createWidget('CavebotWaypoint', listW)
      row:setText(name)
      row.profName = name
      -- Select on PRESS (reliable inside a MainWindow, where onClick on release can be
      -- swallowed by the window's own handling); double-click loads directly.
      row.onMousePress = function(_, _, btn)
        if btn == MouseLeftButton then select(name); return true end
        return false
      end
      row.onDoubleClick = function() doLoad(name) end
    end
  end
  refresh()

  w:recursiveGetChildById('closeBtn').onClick = close

  w:recursiveGetChildById('saveAsBtn').onClick = function()
    textPrompt(tr('Save Cavebot'), tr('Profile name'), tostring(cfg.selected or 'cavebot'), function(name)
      if saveProfile(name) then refresh() else
        if modules.game_textmessage then modules.game_textmessage.displayFailureMessage(tr('Could not save the profile.')) end
      end
    end)
  end

  w:recursiveGetChildById('loadBtn').onClick = function() doLoad(sel) end

  w:recursiveGetChildById('deleteBtn').onClick = function()
    if not sel then return end
    local box
    local function dn() if box then box:destroy(); box = nil end end
    box = displayGeneralBox(tr('Delete Profile'), tr('Delete the saved profile "%s"?', sel),
      { { text = tr('Yes'), callback = function() deleteProfile(sel); refresh(); dn() end },
        { text = tr('No'),  callback = dn } }, nil, dn)
  end
end

editWaypoint = function(idx)
  local wp = currentList()[idx]
  if not wp then return end
  local t = wp.type
  if t == 'say' then
    textPrompt(tr('Edit Say'), tr('Text'), wp.text, function(v) wp.text = v; refreshList(); save() end)
  elseif t == 'goto' then
    textPrompt(tr('Edit Goto'), tr('Label'), wp.label, function(v) wp.label = v; refreshList(); save() end)
  elseif t == 'label' then
    textPrompt(tr('Edit Label'), tr('Name'), wp.name, function(v) wp.name = v; refreshList(); save() end)
  elseif t == 'delay' then
    numberPrompt(tr('Edit Delay'), tr('Milliseconds'), wp.ms or 1000, 0, 600000, 100, function(v) wp.ms = tonumber(v) or 0; refreshList(); save() end)
  elseif t == 'usewith' then
    numberPrompt(tr('Edit Tool Item ID'), tr('Item ID'), wp.itemId or 3003, 0, 999999, 1, function(v) wp.itemId = tonumber(v) or 0; refreshList(); save() end)
  elseif t == 'lua' then
    codePrompt(tr('Edit Lua Waypoint'), wp.code, function(v) wp.code = v; refreshList(); save() end)
  elseif t == 'walk' or t == 'stand' or t == 'use' then
    captureMapClick(function(pos) wp.x, wp.y, wp.z = pos.x, pos.y, pos.z; refreshList(); save() end)
  end
end

-- ---------------------------------------------------------------------------
-- Waypoint tabs: each tab is its OWN waypoint list (a "responsibility": hunt,
-- refill, go-home, ...). The active tab loops on its own waypoints; switching
-- tabs switches behavior. Display order lives in cfg.tabOrder.
-- ---------------------------------------------------------------------------
local function tabCount()
  local n = 0
  for _ in pairs(cfg.configs) do n = n + 1 end
  return n
end

local function renameTab(old)
  textPrompt(tr('Rename Tab'), tr('New name'), old, function(name)
    if not name or #name == 0 or name == old or cfg.configs[name] then return end
    cfg.configs[name] = cfg.configs[old]
    cfg.configs[old] = nil
    for i, n in ipairs(cfg.tabOrder) do if n == old then cfg.tabOrder[i] = name end end
    if cfg.selected == old then cfg.selected = name end
    rebuildTabs()
    save()
  end)
end

local function deleteTab(name)
  if tabCount() <= 1 then
    if modules.game_textmessage then
      modules.game_textmessage.displayFailureMessage(tr('You must keep at least one tab.'))
    end
    return
  end
  cfg.configs[name] = nil
  for i, n in ipairs(cfg.tabOrder) do if n == name then table.remove(cfg.tabOrder, i); break end end
  if cfg.selected == name then cfg.selected = cfg.tabOrder[1] or next(cfg.configs) end
  rt.index = 1
  selIndex = 0
  gotoChain = 0
  resetWalkState()
  rebuildTabs()
  refreshList()
  save()
end

local function showTabMenu(name, mousePos)
  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  menu:addOption(tr('Rename'), function() renameTab(name) end)
  if tabCount() > 1 then
    menu:addOption(tr('Delete'), function() deleteTab(name) end)
  end
  menu:display(mousePos)
end

selectTab = function(name)
  if not cfg.configs[name] then return end
  cfg.selected = name
  rt.index = 1
  selIndex = 0
  gotoChain = 0
  resetWalkState()
  rebuildTabs()
  refreshList()
  save()
end

rebuildTabs = function()
  if not tabContainer then return end
  tabContainer:destroyChildren()
  for _, name in ipairs(cfg.tabOrder or {}) do
    if cfg.configs[name] then
      local tab = g_ui.createWidget('CavebotTab', tabContainer)
      tab:setText(name)
      tab:setOn(name == cfg.selected)
      tab.onClick = function() selectTab(name) end
      tab.onMousePress = function(_, mp, btn)
        if btn == MouseRightButton then showTabMenu(name, mp); return true end
        return false
      end
    end
  end
end

-- The "+" button: add a tab with a unique auto name (rename via right-click).
function cavebotNewTab()
  local n, name = 1, nil
  repeat
    n = n + 1
    name = 'Tab ' .. n
  until not cfg.configs[name]
  cfg.configs[name] = { waypoints = {} }
  cfg.tabOrder = cfg.tabOrder or {}
  table.insert(cfg.tabOrder, name)
  selectTab(name)
end

-- ---------------------------------------------------------------------------
-- Status helpers
-- ---------------------------------------------------------------------------
setStatus = function(text, color)
  if statusLabel then
    statusLabel:setText(text)
    if color then statusLabel:setColor(color) end
  end
  -- Mirror onto the "Cavebot" row of the Helper Stats mini-window (a separate
  -- window). Found lazily once it exists, then cached + made click-to-toggle.
  if not trackerStatusWidget and g_game.isOnline() then
    local root = g_ui.getRootWidget()
    trackerStatusWidget = root and root:recursiveGetChildById('cavebotTrackerStatus') or nil
    if trackerStatusWidget then
      trackerStatusWidget.onClick = function() cavebotToggle() end
      trackerStatusWidget:setTooltip(tr('Click to toggle the Cavebot'))
    end
  end
  if trackerStatusWidget then
    trackerStatusWidget:setText(text)
    if color then trackerStatusWidget:setColor(color) end
  end
end

syncEnableButton = function()
  if enableButton then
    enableButton:setText(cfg.enabled and tr('Disable Cavebot') or tr('Enable Cavebot'))
    enableButton:setImageColor(cfg.enabled and '#44ad25' or '#cc4444') -- green on / red off
  end
  if not cfg.enabled then
    setStatus(tr('Inactive'), COLOR_RED)
  else
    setStatus(tr('Active'), COLOR_GREEN)
  end
end

function cavebotToggle()
  if not cfg.enabled and recording then
    if modules.game_textmessage then
      modules.game_textmessage.displayFailureMessage(tr('Stop recording before enabling the cavebot.'))
    end
    return
  end
  cfg.enabled = not cfg.enabled
  if cfg.enabled then
    rt.index = 1
    gotoChain = 0
    rt.fighting = false -- fresh box/cait phase on each enable
    -- Start from the waypoint nearest the player (this tab) when the option is on.
    if cfg.settings.startNearest then
      local pl = g_game.getLocalPlayer()
      local ppos = pl and pl:getPosition()
      local idx = ppos and nearestStartIndex(ppos)
      if idx then rt.index = idx end
    end
    resetWalkState()
  else
    local p = g_game.getLocalPlayer()
    if p and p.isAutoWalking and p:isAutoWalking() then p:stopAutoWalk() end
  end
  syncEnableButton()
  save()
end

-- ---------------------------------------------------------------------------
-- Lua-waypoint sandbox API (callable as bot.xxx inside a Lua waypoint)
-- ---------------------------------------------------------------------------
bot = {
  player    = function() return g_game.getLocalPlayer() end,
  pos       = function() return playerPos() end,
  walkTo    = function(p) local pl = g_game.getLocalPlayer(); if pl and p then pl:autoWalk(p) end end,
  gotoLabel = function(n) gotoLabel(n) end,
  wait      = function(ms) rt.waitUntil = g_clock.millis() + (tonumber(ms) or 0) end,
  say       = function(t) if t then g_game.talk(tostring(t)) end end,
  useId     = function(id, target) if id and target then g_game.useInventoryItemWith(id, target, 0) end end,
  log       = function(s) consoleln('[Cavebot:lua] ' .. tostring(s)) end,
}

-- ---------------------------------------------------------------------------
-- Engine
-- ---------------------------------------------------------------------------
resetWalkState = function()
  rt.lastPos        = nil
  rt.lastTarget     = nil
  rt.stuckSince     = 0
  rt.retries        = 0
  rt.floorExpectZ   = nil
  rt.floorSince     = 0
  rt.floorRetried   = 0
  rt.recoveryTarget = false
  rt.crossFloorSince= 0
  rt.repathSince    = 0
end

advance = function()
  local wps = currentList()
  rt.index = rt.index + 1
  if rt.index > #wps then rt.index = 1 end
  -- NOTE: rt.recovered is intentionally NOT reset here. It is cleared only on a
  -- genuine arrival at a non-recovery waypoint (walkTo), so a reachable "decoy"
  -- node next to an unreachable one cannot keep re-arming recovery forever.
  resetWalkState()
end

gotoLabel = function(name)
  local wps = currentList()
  for i, wp in ipairs(wps) do
    if wp.type == 'label' and wp.name == name then
      rt.index = i
      resetWalkState()
      return true
    end
  end
  return false
end

-- The index of the next Walk/Stand waypoint after `idx` (wrapping), or nil.
local function nextMoveIndex(idx)
  local wps = currentList()
  local n = #wps
  for k = 1, n - 1 do
    local j = ((idx - 1 + k) % n) + 1
    local w = wps[j]
    if w.type == 'walk' or w.type == 'stand' then return j end
  end
  return nil
end

-- The floor (z) of the next Walk/Stand waypoint, used for floor-change detection.
local function nextMoveZ(idx)
  local j = nextMoveIndex(idx)
  return j and currentList()[j].z or nil
end

-- The nearest Walk/Stand waypoint on the same floor as `pos`, excluding `excl`.
local function nearestMoveIndex(pos, excl)
  local wps = currentList()
  local best, bestD
  for i, w in ipairs(wps) do
    if i ~= excl and (w.type == 'walk' or w.type == 'stand') and w.z == pos.z then
      local d = chebyshev(pos, w)
      -- d > 0: never "recover" to the tile we already stand on (no movement, and
      -- it would burn a recovery slot without making progress).
      if d > 0 and (not bestD or d < bestD) then best, bestD = i, d end
    end
  end
  return best
end

-- Anti-stuck recovery: when knocked off the route (chased during combat, snagged
-- on a field), jump to the NEAREST waypoint on this floor and walk there instead
-- of blindly skipping forward. Bounded so a genuinely unreachable spot eventually
-- falls through to a forward-skip by the caller.
recoverToNearest = function(p, pos, now)
  rt.recovered = (rt.recovered or 0) + 1
  if rt.recovered > (cfg.settings.recoverRetries or 2) then
    rt.recovered = 0
    return false
  end
  local idx = nearestMoveIndex(pos, rt.index)
  if not idx then return false end
  local w = currentList()[idx]
  consoleln(string.format('[Cavebot] off route, recovering to nearest waypoint %d', idx))
  rt.index = idx
  resetWalkState()
  rt.recoveryTarget = true  -- arriving here is NOT progress; keep the recovery bound counting
  p:autoWalk({ x = w.x, y = w.y, z = w.z })
  return true
end

local function thingAt(x, y, z)
  local tile = g_map.getTile({ x = x, y = y, z = z })
  if not tile then return nil end
  return tile:getTopUseThing()
end

local function doUse(wp)
  local thing = thingAt(wp.x, wp.y, wp.z)
  if thing then
    g_game.use(thing)
  else
    consoleln(string.format('[Cavebot] use: nothing usable at waypoint %d', rt.index))
  end
end

local function doUseWith(wp)
  local target = thingAt(wp.x, wp.y, wp.z)
  if not target then
    consoleln(string.format('[Cavebot] usewith: no target at waypoint %d', rt.index))
    return
  end
  if wp.itemId and wp.itemId > 0 then
    g_game.useInventoryItemWith(wp.itemId, target, 0)
  end
end

local function runLua(wp)
  if not wp.code or #wp.code == 0 then return end
  local fn, err = loadstring(wp.code, '@cavebot')
  if not fn then
    consoleln('[Cavebot] lua compile error: ' .. tostring(err))
    return
  end
  -- A loadstring chunk defaults to the real _G (file I/O, process launch, loadstring,
  -- ...). Bind it to the SAME closed sandbox the Script tab uses (Scripting.makeEnv:
  -- safe stdlib + g_game/g_map/g_clock only) plus this waypoint's `bot` API, so a
  -- lua waypoint is locked down identically to a loaded script. Fall back to a small
  -- closed env (never the real _G) if the scripting module isn't loaded.
  if setfenv then
    local env
    if Scripting and Scripting.makeEnv then
      env = Scripting.makeEnv({ bot = bot })
    else
      env = setmetatable({ bot = bot }, { __index = {
        g_game = g_game, g_map = g_map, g_clock = g_clock,
        math = math, string = string, table = table, pairs = pairs, ipairs = ipairs,
        tostring = tostring, tonumber = tonumber, pcall = pcall, type = type,
      } })
    end
    setfenv(fn, env)
  end
  local ok, e = pcall(fn)
  if not ok then
    consoleln('[Cavebot] lua runtime error: ' .. tostring(e))
  end
end

-- Reach tolerance (chebyshev) a node accepts: 1 = the exact tile (tol 0), 2 = any adjacent
-- tile (tol 1), ... Stand always demands the exact tile. Single source of truth so the
-- arrival check, node-skip and pre-aim never drift. (reachRadius migrates from `tolerance`.)
local function reachTol(node)
  return (node.type == 'stand') and 0 or math.max(0, (cfg.settings.reachRadius or 2) - 1)
end

local function walkTo(wp, now)
  local p = g_game.getLocalPlayer()
  if not p then return end
  local pos = p:getPosition()
  local dest = { x = wp.x, y = wp.y, z = wp.z }
  local isStand = (wp.type == 'stand')
  local tol = reachTol(wp)

  -- Arrived?
  if pos.z == dest.z and chebyshev(pos, dest) <= tol then
    if not rt.recoveryTarget then rt.recovered = 0 end -- real progress clears the bound
    advance()
    -- Run speed = LURE delay, and luring only makes sense with creatures around. With a
    -- clear screen (0 reachable monsters) there is nothing to outrun, so sprint at 100%
    -- (no per-node wait); the moment 1+ monsters are on screen, apply the configured
    -- pause so the pack follows instead of getting lost. (rt.onScreen is set by huntGate
    -- earlier this same tick.)
    local sp = cfg.settings.runSpeed or 100
    if not isStand and sp < 100 and (rt.onScreen or 0) > 0 then
      rt.waitUntil = now + (100 - sp) * RUN_SPEED_MS
      return
    end
    -- No lure pause: aim at the next positioned node THIS SAME tick instead of idling a
    -- whole loop interval (~200ms) until walkTo re-issues -- that gap is the small stop
    -- felt at each waypoint on a clear screen. Only chain into a same-floor walk/stand we
    -- have not already reached; other node types (use/say/floor change) get handled next
    -- tick, and advance() already reset the walk state (so set lastTarget to match).
    local nwp = currentList()[rt.index]
    if nwp and nwp.x and (nwp.type == 'walk' or nwp.type == 'stand') and nwp.z == pos.z then
      local ntol = reachTol(nwp)
      if chebyshev(pos, nwp) > ntol then
        rt.lastTarget = { x = nwp.x, y = nwp.y, z = nwp.z }
        p:autoWalk(rt.lastTarget)
      end
    end
    return
  end

  -- Node skip: a Walk node is skippable. If we already stand on the IMMEDIATE next
  -- waypoint and it is a move node (we overshot it during combat), jump to it
  -- instead of walking backwards. Limited to the adjacent index so an actionable
  -- waypoint in a gap (use/say/rope/...) is never silently dropped. Stand = never skip.
  if not isStand then
    local n = #currentList()
    local j = (rt.index % n) + 1
    local nx = currentList()[j]
    if nx and (nx.type == 'walk' or nx.type == 'stand') then
      local ntol = reachTol(nx)
      if pos.z == nx.z and chebyshev(pos, nx) <= ntol then
        rt.index = j
        resetWalkState()
        return
      end
    end
  end

  -- Cross-floor: the pathfinder cannot route across floors. Wait (own timer, so
  -- lateral shoving on the wrong floor can't keep resetting it) for a pending
  -- floor change to settle; if it never comes, recover to the nearest same-floor
  -- waypoint (or skip). Do NOT issue a doomed cross-floor auto-walk.
  if pos.z ~= dest.z then
    if rt.crossFloorSince == 0 then rt.crossFloorSince = now end
    if (now - rt.crossFloorSince) >= cfg.settings.floorTimeout then
      if p:isAutoWalking() then p:stopAutoWalk() end
      rt.crossFloorSince = 0
      if not recoverToNearest(p, pos, now) then
        consoleln(string.format('[Cavebot] skipping cross-floor waypoint %d', rt.index))
        advance()
      end
    end
    return
  end
  rt.crossFloorSince = 0

  -- Progress tracking (same floor)
  if rt.lastPos and Position.equals(rt.lastPos, pos) then
    if rt.stuckSince == 0 then rt.stuckSince = now end
  else
    -- The player actually moved: clear both the genuine-stuck timer and the blocked
    -- re-path debounce so a fresh block starts its own short clock.
    rt.lastPos = pos
    rt.stuckSince = 0
    rt.repathSince = 0
  end

  -- (Re)issue auto-walk when the target changes
  local changedTarget = (not rt.lastTarget) or (not Position.equals(rt.lastTarget, dest))
  if changedTarget then
    rt.lastTarget = dest
    rt.retries = 0
    rt.stuckSince = 0
    rt.repathSince = 0
    p:autoWalk(dest)
    return
  end

  -- Blocked re-path: the engine stopped before arriving, so the next tile is almost
  -- always a creature that stepped into the path. Re-issue autoWalk on a short cadence
  -- so the pathfinder routes AROUND it (findPath treats blocking creatures as obstacles)
  -- instead of standing still until stuckMs. This keeps Box LURING and Cait KITING around
  -- a monster/player in front instead of stopping (Box still stands to kill once its
  -- threshold is hit -- huntGate handles that, so walkTo only runs while it should move).
  -- If no detour exists (1-tile corridor) the player never moves, so the genuine-stuck
  -- timer below still recovers.
  if not p:isAutoWalking() then
    local hm = cfg.settings.huntMode
    local repathMs = (hm == 'cait' or hm == 'box') and LURE_REPATH_MS or BLOCKED_REPATH_MS
    if rt.repathSince == 0 then rt.repathSince = now end
    if (now - rt.repathSince) >= repathMs then
      rt.repathSince = 0
      p:autoWalk(dest) -- recomputed from the current tile, so it walks around the blocker
      return
    end
  else
    rt.repathSince = 0
  end

  -- Genuine-stuck handling: the player's own position hasn't changed for stuckMs (walled
  -- in, desynced, or a truly unreachable waypoint). Retry a couple of times, then recover
  -- to the nearest waypoint, and only skip forward if recovery is exhausted.
  if rt.stuckSince > 0 and (now - rt.stuckSince) >= cfg.settings.stuckMs then
    rt.retries = rt.retries + 1
    rt.stuckSince = 0
    rt.repathSince = 0
    p:stopAutoWalk()
    if rt.retries >= 3 then
      if recoverToNearest(p, pos, now) then return end
      consoleln(string.format('[Cavebot] skipping unreachable waypoint %d', rt.index))
      advance()
      return
    end
    p:autoWalk(dest)
  end
end

-- Use / UseWith with floor-change verification. If the next move waypoint is on a
-- different floor (rope up, ladder, use-stairs), keep using and WAIT until the
-- player's z actually changes before advancing, retrying a few times. A same-floor
-- use (lever, or a shovel-then-walk hole whose next node is the same floor) has no
-- floor delta and simply fires once and advances.
local function handleUse(wp, now, t)
  local p = g_game.getLocalPlayer()
  if not p then return end
  local curZ = p:getPosition().z

  -- First entry on this waypoint: fire the action, decide if a floor change is due
  if rt.floorExpectZ == nil then
    if t == 'use' then doUse(wp) else doUseWith(wp) end
    local exp = nextMoveZ(rt.index)
    rt.waitUntil = now + cfg.settings.actionDelay
    if exp and exp ~= curZ then
      rt.floorExpectZ = exp
      rt.floorSince   = now
      rt.floorRetried = 0
    else
      advance()
    end
    return
  end

  -- Verifying the floor change
  if curZ == rt.floorExpectZ then
    advance() -- resetWalkState clears floorExpectZ
    return
  end
  if (now - rt.floorSince) >= cfg.settings.floorTimeout then
    rt.floorRetried = rt.floorRetried + 1
    if rt.floorRetried > cfg.settings.floorRetries then
      consoleln('[Cavebot] floor change did not register; continuing')
      advance()
      return
    end
    if t == 'use' then doUse(wp) else doUseWith(wp) end
    rt.floorSince = now
    rt.waitUntil  = now + cfg.settings.actionDelay
  end
end

-- Hunt-mode gate. Returns true if the bot should STAND this tick (hold for combat).
-- `cnt` is the number of REACHABLE monsters on screen (monstersOnScreen excludes ones
-- with no line of sight, e.g. locked in a closed room, so the bot never freezes on them).
-- Combat itself is always the Helper's job; this only governs the cavebot's walking.
--   single: stop at the FIRST reachable creature, stand until all on screen are dead.
--   box:    lure (walk through) until >= Start reachable, then STAND and kill until <= Stop.
--   cait:   same Start/Stop, but NEVER stand -- keep walking/kiting so the pack stays lured.
local function huntGate(pos)
  local mode = cfg.settings.huntMode or 'single'
  local cnt = monstersOnScreen(pos)
  rt.onScreen = cnt -- cached for walkTo's lure-delay decision (same tick, same pos)
  if mode == 'single' then
    if rt.fighting then
      if cnt == 0 then rt.fighting = false end
    elseif cnt >= 1 then rt.fighting = true end
    if rt.fighting then
      setStatus(tr('Single: killing (%d)', cnt), COLOR_ORANGE)
      return true
    end
    setStatus(tr('Single: clear'), COLOR_GREEN)
    return false
  elseif mode == 'box' then
    if rt.fighting then
      if cnt <= cfg.settings.huntStop then rt.fighting = false end
    elseif cnt >= cfg.settings.huntStart then rt.fighting = true end
    if rt.fighting then
      setStatus(tr('Box: killing (%d)', cnt), COLOR_ORANGE)
      return true
    end
    setStatus(tr('Box: luring (%d)', cnt), COLOR_GREEN)
    return false
  else -- cait
    if rt.fighting then
      if cnt <= cfg.settings.huntStop then rt.fighting = false end
    elseif cnt >= cfg.settings.huntStart then rt.fighting = true end
    setStatus(rt.fighting and tr('Cait: kiting (%d)', cnt) or tr('Cait: luring (%d)', cnt), COLOR_GREEN)
    return false -- cait never stands still
  end
end

local function loop()
  if not cfg.enabled then return end
  local p = g_game.getLocalPlayer()
  if not p or not g_game.isOnline() then return end

  local now = g_clock.millis()
  if now < rt.waitUntil then return end

  local wps = currentList()
  if #wps == 0 then
    setStatus(tr('No waypoints'), COLOR_RED)
    return
  end

  -- Hunt-mode gate: decide whether to STAND (let the Helper kill) or keep moving.
  local pos = p:getPosition()
  if huntGate(pos) then
    if p:isAutoWalking() then p:stopAutoWalk() end
    rt.lastTarget = nil
    rt.stuckSince = 0
    -- Re-anchor the floor/cross-floor settle timers so a fight in the middle of a
    -- rope/ladder/stairs transition doesn't make them fire a retry-burst on resume.
    if rt.floorExpectZ then rt.floorSince = now end
    if rt.crossFloorSince > 0 then rt.crossFloorSince = now end
    return
  end

  if rt.index < 1 or rt.index > #wps then rt.index = 1 end
  local wp = wps[rt.index]
  -- huntGate already set a mode+count status (Single/Box/Cait) for this tick.

  local t = wp.type

  -- Malformed-route guard: a label/goto cycle with no move/wait waypoint between
  -- would spin at full tick cadence forever without moving. If we process more
  -- label/goto dispatches in a row than there are waypoints, it can only be such a
  -- cycle — warn and disable rather than livelock silently.
  if t == 'label' or t == 'goto' then
    gotoChain = gotoChain + 1
    if gotoChain > #wps then
      consoleln('[Cavebot] route loops through labels/gotos with no movement; disabling')
      cfg.enabled = false
      gotoChain = 0
      syncEnableButton()
      return
    end
  else
    gotoChain = 0
  end

  if t == 'walk' or t == 'stand' then
    walkTo(wp, now)
  elseif t == 'label' then
    advance()
  elseif t == 'goto' then
    if not gotoLabel(wp.label) then advance() end
  elseif t == 'delay' then
    rt.waitUntil = now + (tonumber(wp.ms) or 0)
    advance()
  elseif t == 'say' then
    if wp.text and #wp.text > 0 then g_game.talk(wp.text) end
    rt.waitUntil = now + cfg.settings.actionDelay
    advance()
  elseif t == 'use' or t == 'usewith' then
    handleUse(wp, now, t)
  elseif t == 'lua' then
    runLua(wp)
    if now >= rt.waitUntil then rt.waitUntil = now + cfg.settings.actionDelay end
    advance()
  else
    advance()
  end
end

-- ---------------------------------------------------------------------------
-- Panel / tab mounting + button wiring
-- ---------------------------------------------------------------------------
local function mountUI(window)
  local contentPanel = window.contentPanel

  -- The cavebotMenu tab button is now declared statically in helper.otui's
  -- optionsTabBar (image-clip on /images/ui/helper), wired to loadMenu('cavebotMenu').

  -- Panel mounted in the content area, hidden by default
  panel = g_ui.createWidget('CavebotPanel', contentPanel)
  if not panel then
    consoleln('[Cavebot] CavebotPanel style not loaded; aborting mount')
    return false
  end
  panel:setId('cavebotPanel')
  panel:addAnchor(AnchorTop, 'optionsTabBar', AnchorBottom)
  panel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  panel:addAnchor(AnchorRight, 'parent', AnchorRight)
  -- Pin the panel bottom to the helper's footer divider so the Set Hotkey button
  -- (anchored to parent.bottom) sits just above it, instead of covering the footer.
  panel:addAnchor(AnchorBottom, 'separator', AnchorTop)
  panel:setMarginTop(5)
  panel:hide()

  wpList       = panel:recursiveGetChildById('waypointList')
  statusLabel  = panel:recursiveGetChildById('cavebotStatus')
  enableButton = panel:recursiveGetChildById('enableButton')
  tabContainer = panel:recursiveGetChildById('tabContainer')
  recordButton = panel:recursiveGetChildById('recordBtn')
  hudButton    = panel:recursiveGetChildById('hudBtn')
  hotkeyButton = panel:recursiveGetChildById('hotkeyBtn')

  -- Right-click the Record button to set how many sqm apart recorded nodes are.
  if recordButton then
    recordButton.onMousePress = function(_, _, button)
      if button == MouseRightButton then
        numberPrompt(tr('Record Interval'), tr('Drop a node every N sqm'),
          cfg.settings.recordInterval or 3, 1, 50, 1, function(v)
            cfg.settings.recordInterval = math.max(1, tonumber(v) or 3)
            save()
          end)
        return true
      end
      return false
    end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Public lifecycle (called by helper.lua)
-- ---------------------------------------------------------------------------
function Cavebot.init(window)
  helperWindow = window
  if not window or not window.contentPanel then return end

  mountUI(window)

  grabber = g_ui.createWidget('UIWidget')
  grabber:setVisible(false)
  grabber:setFocusable(false)

  -- Path recorder hook: drop a Walk node on every step while recording is on.
  connect(LocalPlayer, { onPositionChange = onRecordStep })
end

function Cavebot.online()
  -- Normalize recorder state so a fresh session never starts mid-record (load()
  -- below replaces the waypoint list, which must not happen under a live recorder).
  recording = false
  lastRecSave = 0
  gotoChain = 0
  trackerStatusWidget = nil -- re-find the Helper Stats row for this session
  if recordButton then recordButton:setText(tr('Record Path')); recordButton:setImageColor('#3d7fc2') end
  load()
  rebuildTabs()
  refreshList()
  syncEnableButton()
  syncHotkeyButton()
  bindHotkey() -- (re)bind the saved toggle hotkey for this session
  if hudButton then
    hudButton:setText(cfg.settings.hud and tr('HUD: On') or tr('HUD: Off'))
  end
  if loopEvent then removeEvent(loopEvent) end
  loopEvent = cycleEvent(loop, 200)
  if hudEvent then removeEvent(hudEvent) end
  hudEvent = cycleEvent(updateHud, 250)
end

function Cavebot.offline()
  if loopEvent then removeEvent(loopEvent); loopEvent = nil end
  if hudEvent then removeEvent(hudEvent); hudEvent = nil end
  hudClear()
  if hotkeyBound then
    g_keyboard.unbindKeyDown(hotkeyBound, cavebotToggle, g_ui.getRootWidget())
    hotkeyBound = nil
  end
  if recording then recording = false
    if recordButton then recordButton:setText(tr('Record Path')) end
  end
  cfg.enabled = false
  save()
end

function Cavebot.terminate()
  disconnect(LocalPlayer, { onPositionChange = onRecordStep })
  if hotkeyBound then
    g_keyboard.unbindKeyDown(hotkeyBound, cavebotToggle, g_ui.getRootWidget())
    hotkeyBound = nil
  end
  if hudEvent then removeEvent(hudEvent); hudEvent = nil end
  hudClear()
  if hotkeyWindow then
    g_client.setInputLockWidget(nil) -- don't leave the game input locked
    hotkeyWindow:destroy(); hotkeyWindow = nil
  end
  if settingsWindow then settingsWindow:destroy(); settingsWindow = nil end
  if profilesWindow then profilesWindow:destroy(); profilesWindow = nil end
  if loopEvent then removeEvent(loopEvent); loopEvent = nil end
  if grabber then grabber:destroy(); grabber = nil end
  helperWindow = nil
  panel = nil
end

function Cavebot.showPanel()
  if panel then panel:show() end
end

function Cavebot.hidePanel()
  if panel then panel:hide() end
end

-- ---------------------------------------------------------------------------
-- Public control API (used by the shared scripting API: bot.cavebot.*)
-- ---------------------------------------------------------------------------
function Cavebot.isEnabled() return cfg.enabled == true end

function Cavebot.setEnabled(b)
  b = b and true or false
  if cfg.enabled == b then return end
  cfg.enabled = b
  if b then
    rt.index = 1
    gotoChain = 0
    resetWalkState()
  else
    local p = g_game.getLocalPlayer()
    if p and p.isAutoWalking and p:isAutoWalking() then p:stopAutoWalk() end
  end
  syncEnableButton()
  save()
end

function Cavebot.gotoTab(name)
  if not cfg.configs[name] then return false end
  selectTab(name)
  return true
end

function Cavebot.currentTab() return cfg.selected end

function Cavebot.listTabs()
  local t = {}
  for _, n in ipairs(cfg.tabOrder or {}) do t[#t + 1] = n end
  return t
end

function Cavebot.getStatus()
  return statusLabel and statusLabel:getText() or ''
end

-- Make sure the styles are registered before helper.lua displays its UI.
g_ui.importStyle('styles/cavebot')
