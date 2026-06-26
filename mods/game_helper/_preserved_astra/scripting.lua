--[[
  Scripting tab for AstraClient (3rd script of game_helper).
  --------------------------------------------------------
  A place for players to drop their own Lua scripts. Scripts are plain .lua FILES
  in the bot scripts folder (the "Open Scripts Folder" button opens it). Each file's
  body runs ONCE when the script is ENABLED ("loaded"); for recurring work the script
  registers Timer(intervalMs, fn) callbacks. It all runs inside a sandbox that exposes
  the shared `bot` API (game + cavebot + helper), the global `Timer`, and a per-script
  persistent `storage` table.

  UI: the tab is just two lists -- "Available" (in the folder, not running) and
  "Running" (loaded). Load/Unload move a script between them. The debug console
  (script print()s + errors) is a separate window.

  Scripts folder: <writeDir>/bot_scripts (shared by all characters). Which files
  are running is persisted per character at /characterdata/<id>/scripts.json.

  The full `bot` API is documented in mods/game_helper/SCRIPTING_API.md (wiki).
]]

Scripting = {}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local helperWindow = nil
local panel        = nil
local disabledListW = nil   -- "Available" list (enabled == false)
local enabledListW  = nil   -- "Running" list (enabled == true)
local statusLabel   = nil
local autoReloadW   = nil   -- "Auto-reload last session scripts" checkbox

local debugWindow  = nil    -- transient debug console window
local debugListW   = nil    -- the debug console's row list (nil while closed)
local debugScrollW = nil    -- its scrollbar (for auto-scroll)
local debugSelectW = nil    -- invisible selectable text overlay (drag-select + copy)

local rescanEvent = nil    -- folder-watch timer (auto-pick-up of dropped files)
local lastFolderSig = nil  -- last seen folder file-set (skip rebuilds when unchanged)
local scripts    = {}      -- name -> { name, code, enabled, fn, events, errors, storage }
local order      = {}      -- display/run order of names
local selName    = nil     -- selected script (in either list)
local runningScript = nil  -- the script currently executing (for Timer registration / log context)
local MAX_ERRORS = 5       -- auto-disable a script after this many runtime errors

-- Per-character "auto-reload last session scripts on login" toggle. autoLoadList is the
-- persisted set of files to re-enable on login; it is updated only when scripts are
-- actually loaded/unloaded (refreshAutoLoadList) so toggling the checkbox or just
-- selecting a row never wipes it. Default ON (matches the prior always-reload behavior).
local autoReload    = true
local autoLoadList  = {}
local suppressAutoReloadSave = false  -- guards setChecked() during load() from re-saving

local debugLines = {}      -- ring buffer of { text, color } for the debug console
local DEBUG_MAX  = 300

-- ---------------------------------------------------------------------------
-- Debug console buffer (errors + script print()/bot.log). Survives the window
-- being closed; opening it replays the buffer.
-- ---------------------------------------------------------------------------
-- Push the full plain log into the invisible selection overlay (so it always matches
-- the visible rows). debugLines is the single source of truth; rebuilding from it is
-- cheap (<= DEBUG_MAX lines) and stays in sync with the ring-buffer trimming.
local function refreshDebugSelection()
  if not debugSelectW then return end
  local parts = {}
  for i = 1, #debugLines do parts[i] = debugLines[i].text end
  debugSelectW:setText(table.concat(parts, '\n'))
end

local function debugAppend(text, color)
  text = '[' .. os.date('%H:%M:%S') .. '] ' .. tostring(text)
  color = color or '#cfcfcf'
  debugLines[#debugLines + 1] = { text = text, color = color }
  if #debugLines > DEBUG_MAX then table.remove(debugLines, 1) end
  if debugListW then
    local row = g_ui.createWidget('ScriptDebugRow', debugListW)
    row:setText(text)
    row:setColor(color)
    local kids = debugListW:getChildren()
    if #kids > DEBUG_MAX then
      local first = debugListW:getChildByIndex(1)
      if first then first:destroy() end
    end
    refreshDebugSelection()
    -- setValue(max) scrolls to newest; it fires onScrollChange, which re-syncs the
    -- overlay's text offset so the (invisible) selection stays aligned with the rows.
    pcall(function() if debugScrollW then debugScrollW:setValue(debugScrollW:getMaximum()) end end)
  end
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------
-- Scripts live as plain .lua files here (one folder shared by all characters).
local SCRIPTS_DIR = '/bot_scripts'   -- virtual path (mounted under the write dir)

local function ensureDir()
  if not g_resources.directoryExists(SCRIPTS_DIR) then
    pcall(function() g_resources.makeDir(SCRIPTS_DIR) end)
  end
end

-- Real OS path of the scripts folder (for g_platform.openDir).
local function scriptsRealDir()
  local wd = g_resources.getWriteDir() or ''
  wd = wd:gsub('[\\/]+$', '')
  -- Backslashes only: explorer.exe treats a '/' in the path as a command-line switch
  -- and ignores the path (which is why it was opening Documents instead of the folder).
  return (wd .. SCRIPTS_DIR):gsub('/', '\\')
end

-- Sorted list of .lua file names in the scripts folder.
local function listScripts()
  ensureDir()
  local files = {}
  local ok, list = pcall(function() return g_resources.listDirectoryFiles(SCRIPTS_DIR) end)
  if ok and type(list) == 'table' then
    for _, name in ipairs(list) do
      if type(name) == 'string' and name:lower():match('%.lua$') then
        files[#files + 1] = name
      end
    end
  end
  table.sort(files, function(a, b) return a:lower() < b:lower() end)
  return files
end

local function readScriptCode(s)
  local vp = SCRIPTS_DIR .. '/' .. s.name
  if not g_resources.fileExists(vp) then return nil, 'file not found' end
  local ok, content = pcall(function() return g_resources.readFileContents(vp) end)
  if not ok then return nil, tostring(content) end
  return content or ''
end

local function configPath()
  if not LoadedPlayer or not LoadedPlayer:isLoaded() then return nil end
  return '/characterdata/' .. LoadedPlayer:getId() .. '/scripts.json'
end

-- The "load on login" set (autoLoadList) tracks which files are running; refreshed only
-- when a script is actually loaded/unloaded, so it survives checkbox/selection saves.
local function refreshAutoLoadList()
  autoLoadList = {}
  for _, name in ipairs(order) do
    if scripts[name] and scripts[name].enabled then autoLoadList[#autoLoadList + 1] = name end
  end
end

-- We only persist WHICH files to auto-load + the toggle (per character); the code lives
-- in the files. autoLoadList is written as-is so toggling auto-reload (or selecting a
-- row) never erases the remembered last-session set.
local function save()
  local p = configPath()
  if not p then return end
  local out = { enabled = autoLoadList, selected = selName, autoReload = autoReload }
  local ok, res = pcall(function() return json.encode(out, 2) end)
  if ok and res then g_resources.writeFileContents(p, res) end
end

local function setStatus(text, color)
  if not statusLabel then return end
  statusLabel:setText(text or '')
  if color then statusLabel:setColor(color) end
end

-- ---------------------------------------------------------------------------
-- Shared bot API (documented in SCRIPTING_API.md). Read it before changing keys.
-- ---------------------------------------------------------------------------
local function lp() return g_game.getLocalPlayer() end

local bot = {}

-- player / state ------------------------------------------------------------
function bot.player() return lp() end
function bot.online() return g_game.isOnline() and lp() ~= nil end
function bot.pos() local p = lp(); return p and p:getPosition() or nil end
function bot.name() local p = lp(); return p and p:getName() or '' end
function bot.hp() local p = lp(); return p and p:getHealth() or 0 end
function bot.maxhp() local p = lp(); return p and p:getMaxHealth() or 0 end
function bot.hpp() local p = lp(); if not p then return 0 end local m = p:getMaxHealth(); return m > 0 and math.floor(p:getHealth() / m * 100) or 0 end
function bot.mp() local p = lp(); return p and p:getMana() or 0 end
function bot.maxmp() local p = lp(); return p and p:getMaxMana() or 0 end
function bot.mpp() local p = lp(); if not p then return 0 end local m = p:getMaxMana(); return m > 0 and math.floor(p:getMana() / m * 100) or 0 end
function bot.cap() local p = lp(); if not p then return 0 end local ok, c = pcall(function() return p:getFreeCapacity() end); return (ok and c) or 0 end
function bot.skull() local p = lp(); return p and p:getSkull() or 0 end

-- movement ------------------------------------------------------------------
function bot.walk(pos) local p = lp(); if p and pos then p:autoWalk(pos) end end
function bot.stopWalk() local p = lp(); if p and p:isAutoWalking() then p:stopAutoWalk() end end
function bot.walking() local p = lp(); return p ~= nil and p:isAutoWalking() end
function bot.dist(a, b)
  a = a or bot.pos()
  if not a or not b then return 9999 end
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- world ---------------------------------------------------------------------
function bot.tile(pos) return pos and g_map.getTile(pos) or nil end
local function spectators(range, want)
  local p = lp(); if not p then return {} end
  local list = g_map.getSpectatorsInRange(p:getPosition(), false, range or 7, range or 7) or {}
  local r = {}
  for _, c in ipairs(list) do
    if c and not c:isLocalPlayer() and c:getHealthPercent() > 0 then
      if (want == 'monster' and c:isMonster()) or (want == 'player' and c:isPlayer()) then
        r[#r + 1] = c
      end
    end
  end
  return r
end
function bot.creatures(range) return spectators(range, 'monster') end
function bot.players(range) return spectators(range, 'player') end
function bot.target() return g_game.getAttackingCreature() end
function bot.attack(c) if c then g_game.attack(c) end end

-- items / actions -----------------------------------------------------------
function bot.itemCount(id) local p = lp(); return (p and id) and p:getInventoryCount(id) or 0 end
function bot.useItem(id) if id then g_game.useInventoryItem(id) end end
function bot.useItemOn(id, target) if id and target then g_game.useInventoryItemWith(id, target, 0) end end
function bot.use(pos)
  local t = pos and g_map.getTile(pos)
  local th = t and t:getTopUseThing()
  if th then g_game.use(th) end
end
function bot.say(text) if text ~= nil then g_game.talk(tostring(text)) end end

-- timing / logging ----------------------------------------------------------
function bot.now() return g_clock.millis() end
function bot.log(...)
  local parts = {}
  for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)) end
  debugAppend((runningScript and (runningScript.name .. ': ') or '') .. table.concat(parts, ' '), '#cfe0ff')
end

-- cavebot control -----------------------------------------------------------
bot.cavebot = {
  enabled = function() return Cavebot ~= nil and Cavebot.isEnabled() end,
  enable  = function() if Cavebot then Cavebot.setEnabled(true) end end,
  disable = function() if Cavebot then Cavebot.setEnabled(false) end end,
  toggle  = function() if Cavebot then Cavebot.setEnabled(not Cavebot.isEnabled()) end end,
  gotoTab = function(name) return Cavebot ~= nil and Cavebot.gotoTab(name) end,
  tab     = function() return Cavebot and Cavebot.currentTab() or '' end,
  tabs    = function() return Cavebot and Cavebot.listTabs() or {} end,
  status  = function() return Cavebot and Cavebot.getStatus() or '' end,
}

-- helper control (pcall-guarded against the helper's globals) ---------------
-- The master on/off lives in helper.lua's local `hotkeyHelperStatus`; read it via
-- the exported isHelperEnabled() and flip it via botStatus() (which updates the UI).
local function helperIsOn() return type(isHelperEnabled) == 'function' and isHelperEnabled() == true end
bot.helper = {
  enabled = function() return helperIsOn() end,
  enable  = function() if not helperIsOn() then pcall(botStatus) end end,
  disable = function() if helperIsOn() then pcall(botStatus) end end,
  toggle  = function() pcall(botStatus) end,
  shooter = function() return helperConfig ~= nil and helperConfig.magicShooterEnabled == true end,
  target  = function() return helperConfig ~= nil and helperConfig.autoTargetEnabled == true end,
  setShooter = function(on)
    pcall(function()
      local cb = shooterPanel:recursiveGetChildById('enableMagicShooter')
      cb:setChecked(on and true or false); toggleMagicShooter(cb)
    end)
  end,
  setTarget = function(on)
    pcall(function()
      local cb = shooterPanel:recursiveGetChildById('enableAutoTarget')
      cb:setChecked(on and true or false); toggleAutoTarget(cb)
    end)
  end,
}

-- forge control -------------------------------------------------------------
-- The conversion ACTIONS are exactly the forge UI buttons (g_game.sendForgeConverter,
-- attached to g_game by the game_forge module at boot). The SERVER validates them:
-- each costs dust/slivers and the dust limit is capped, so they no-op server-side
-- when you can't afford them (or aren't allowed to forge). The read getters report
-- your current forge balances (0 until the forge data is known this session).
local function forgeRes(resType)
  local p = lp()
  if not p or not resType then return 0 end
  local ok, v = pcall(function() return p:getResourceValue(resType) end)
  return (ok and v) or 0
end
bot.forge = {
  increaseDustLimit = function() if g_game.sendForgeConverter then g_game.sendForgeConverter(4) end end,
  dustToSlivers     = function() if g_game.sendForgeConverter then g_game.sendForgeConverter(2) end end,
  sliversToCores    = function() if g_game.sendForgeConverter then g_game.sendForgeConverter(3) end end,
  dust    = function() return forgeRes(ResourceForgeDust) end,
  slivers = function() return forgeRes(ResourceForgeSlivers) end,
  cores   = function() return forgeRes(ResourceForgeExaltedCore) end,
  maxDust = function() return (ForgeSystem and (ForgeSystem.maxPlayerDust or ForgeSystem.maxDust)) or 0 end,
}

-- ---------------------------------------------------------------------------
-- Compile / run
--   A loaded script's FILE BODY runs exactly ONCE (on load). For recurring work
--   the script registers callbacks with Timer(intervalMs, fn): each Timer is its
--   own cycleEvent, tracked on the script and torn down when it unloads/relogs.
-- ---------------------------------------------------------------------------
-- Sandbox globals: a CLOSED table that does NOT chain to the real _G. Scripts get
-- safe stdlib + game READ access (g_game/g_map/g_clock), but NOT file I/O
-- (g_resources), process/URL launch (g_platform), os.execute/remove/exit, loadstring/
-- dofile/require, package/modules/debug, or networking. This is what restricts a
-- (possibly shared) script to game automation only.
local SAFE_STRING = {}
for k, v in pairs(string) do if k ~= 'dump' then SAFE_STRING[k] = v end end
local SANDBOX_GLOBALS = {
  math = math, string = SAFE_STRING, table = table,
  select = select, pairs = pairs, ipairs = ipairs, next = next, type = type,
  tostring = tostring, tonumber = tonumber, unpack = unpack, _VERSION = _VERSION,
  pcall = pcall, xpcall = xpcall, error = error, assert = assert,
  rawget = rawget, rawset = rawset, rawequal = rawequal,
  setmetatable = setmetatable, getmetatable = getmetatable,
  os = { time = os.time, date = os.date, clock = os.clock, difftime = os.difftime },
  g_game = g_game, g_map = g_map, g_clock = g_clock,
}

-- Build a fresh per-chunk environment: a writable top table (the script's own
-- globals + storage/print/Timer/bot) whose reads fall through to the closed
-- SANDBOX_GLOBALS. Shared by the Script tab and the cavebot `lua` waypoint so both
-- are locked down identically.
function Scripting.makeEnv(extra)
  local t = {}
  if extra then for k, v in pairs(extra) do t[k] = v end end
  return setmetatable(t, { __index = SANDBOX_GLOBALS })
end

-- Cancel every recurring Timer a script registered, and destroy every HUD icon
-- it created (both are torn down together when a script unloads/errors/relogs).
local function stopScript(s)
  if s.events then
    for _, h in ipairs(s.events) do
      if h.ev then pcall(removeEvent, h.ev); h.ev = nil end
    end
  end
  s.events = {}
  if s.huds then
    for _, w in pairs(s.huds) do
      if w and (not w.isDestroyed or not w:isDestroyed()) then pcall(function() w:destroy() end) end
    end
    s.huds = {}
  end
end

-- Count a runtime error against a script; auto-disable after MAX_ERRORS (which also
-- kills its Timers, so a broken script can't keep firing).
local function onScriptError(s, err)
  s.errors = (s.errors or 0) + 1
  debugAppend(s.name .. ' runtime error: ' .. tostring(err), '#ff6666')
  if s.errors >= MAX_ERRORS then
    s.enabled = false
    stopScript(s)
    debugAppend(s.name .. ' disabled after ' .. MAX_ERRORS .. ' errors', '#ffaa55')
    Scripting.refreshLists()
    save()
  end
end

-- Run the script's file body ONCE. The body sets up state and registers Timers.
local function runScriptOnce(s)
  if not s.fn then return end
  stopScript(s)            -- clear any Timers left from a previous run
  runningScript = s
  local ok, err = pcall(s.fn)
  runningScript = nil
  if not ok then onScriptError(s, err) end
end

-- Timer(intervalMs, fn): exposed to scripts. Runs `fn` every `intervalMs` (first
-- tick after one interval) while the script stays loaded. Returns a handle whose
-- :stop() cancels just this timer. All of a script's timers are auto-cancelled when
-- it is unloaded, errors out, or you relog.
local function botTimer(interval, fn)
  local s = runningScript
  if not s then
    error('Timer() can only be called while a script is running', 2)
  end
  interval = tonumber(interval)
  if not interval or interval < 1 or type(fn) ~= 'function' then
    error('Timer(intervalMs, fn): expected a positive number and a function', 2)
  end
  local h = {}
  h.ev = cycleEvent(function()
    if not h.ev or not s.enabled or not g_game.isOnline() then return end
    runningScript = s
    local ok, err = pcall(fn)
    runningScript = nil
    if not ok then onScriptError(s, err) end
  end, interval)
  s.events = s.events or {}
  s.events[#s.events + 1] = h
  return { stop = function() if h.ev then pcall(removeEvent, h.ev); h.ev = nil end end }
end

-- ---------------------------------------------------------------------------
-- On-screen HUD (bot.hud.*)
--   Scripts place draggable, clickable icons over the game map. Each icon is
--   tracked on its script (torn down with it, like a Timer) and its position is
--   saved per character so it returns where the player left it.
-- ---------------------------------------------------------------------------
local hudData = {}   -- per-character saved positions: scriptName -> elemId -> {x,y}

local function hudPath()
  if not LoadedPlayer or not LoadedPlayer:isLoaded() then return nil end
  return '/characterdata/' .. LoadedPlayer:getId() .. '/hud.json'
end

local function loadHud()
  hudData = {}
  local p = hudPath()
  if p and g_resources.fileExists(p) then
    local ok, res = pcall(function() return json.decode(g_resources.readFileContents(p)) end)
    if ok and type(res) == 'table' then hudData = res end
  end
end

local function saveHud()
  local p = hudPath()
  if not p then return end
  local ok, res = pcall(function() return json.encode(hudData) end)
  if ok and res then pcall(function() g_resources.writeFileContents(p, res) end) end
end

-- The game map panel (overlay parent); nil when not in game.
local function hudParent()
  local gi = modules.game_interface
  return (gi and gi.getMapPanel) and gi.getMapPanel() or nil
end

local function alive(w) return w ~= nil and (not w.isDestroyed or not w:isDestroyed()) end
local function clampInt(v, d) v = tonumber(v); return v and math.floor(v) or d end

-- Run a script-provided callback (a HUD onClick) with the same run-context and
-- error accounting as a Timer tick.
local function runScriptCallback(s, fn, ...)
  if not s.enabled then return end
  local prev = runningScript
  runningScript = s
  local ok, err = pcall(fn, ...)
  runningScript = prev
  if not ok then onScriptError(s, err) end
end

bot.hud = {}

-- bot.hud.create{ id, image, item, text, color, x, y, width, height, on,
--                 borderColor, borderColorOn, tooltip, draggable, locked, onClick }
--   Creates an on-screen HUD element and returns a handle:
--     :setText/:setImage/:setItem/:setColor/:setBorderColor/:setBorderColorOn
--     :setTooltip/:setOn/:isOn/:show/:hide/:setVisible/:setPos(x,y)/:getPos()
--     :setDraggable(on)/:setLocked(on)/:isLocked()/:destroy
--   The icon is a script `image` OR a real game-item sprite (`item` = item id),
--   with `text` drawn as a caption directly BELOW it. `borderColor`/`borderColorOn`
--   are the element's border in the off/on state. `id` is a stable key used to
--   remember the element's dragged position (and lock) per character; right-clicking
--   it lets the player Lock/Unlock its position.
function bot.hud.create(opts)
  opts = opts or {}
  local s = runningScript
  if not s then error('bot.hud.create can only be called from a script', 2) end
  local parent = hudParent()
  if not parent then error('bot.hud.create: the game map is not available yet', 2) end

  s.huds = s.huds or {}
  s.hudSeq = (s.hudSeq or 0) + 1
  local elemId = tostring(opts.id or ('hud' .. s.hudSeq))
  -- Recreating an element with the same id replaces the old one.
  if alive(s.huds[elemId]) then pcall(function() s.huds[elemId]:destroy() end) end
  s.huds[elemId] = nil

  local w = g_ui.createWidget('ScriptHudIcon', parent)
  w.scriptName, w.elemId = s.name, elemId
  s.huds[elemId] = w

  local iconImage = w:getChildById('iconImage')
  local iconItem  = w:getChildById('iconItem')
  local caption   = w:getChildById('caption')

  -- Caption sits BELOW the icon when there is one, but fills the whole widget (centered)
  -- when the HUD is text-only -- otherwise a text-only HUD would waste the icon's slot.
  local function layoutCaption(hasIcon)
    if not caption then return end
    if hasIcon then
      caption:addAnchor(AnchorTop, 'iconImage', AnchorBottom)
      caption:setMarginTop(1)
    else
      caption:addAnchor(AnchorTop, 'parent', AnchorTop)
      caption:setMarginTop(0)
    end
  end

  -- Icon: a real game item (by id) and a plain image path are mutually exclusive.
  local function showItem(id)
    id = tonumber(id) or 0
    if iconItem then pcall(function() iconItem:setItemId(id) end); iconItem:setVisible(id ~= 0) end
    if iconImage then iconImage:setVisible(false) end
    layoutCaption(id ~= 0)
  end
  local function showImage(img)
    if iconImage then iconImage:setImageSource(tostring(img)); iconImage:setVisible(true) end
    if iconItem then iconItem:setVisible(false) end
    layoutCaption(true)
  end

  w:setSize({ width = clampInt(opts.width, 40), height = clampInt(opts.height, 52) })
  if opts.item then showItem(opts.item)
  elseif opts.image then showImage(opts.image)
  else layoutCaption(false) end
  if opts.text and caption then caption:setText(tostring(opts.text)) end
  if opts.color and caption then pcall(function() caption:setColor(opts.color) end) end
  if opts.tooltip then w:setTooltip(tostring(opts.tooltip)) end

  -- Border colors are driven from Lua (see the ScriptHudIcon style note): off/on
  -- state pick borderOff/borderOn so a script can theme each HUD independently.
  local borderOff = opts.borderColor or '#00000000'
  local borderOn  = opts.borderColorOn or '#44ad25'
  local function applyBorder() if alive(w) then pcall(function() w:setBorderColor(w:isOn() and borderOn or borderOff) end) end end
  w:setOn(opts.on and true or false)
  applyBorder()

  -- Position: a saved (per-character) position overrides the script's default.
  -- Positions are stored relative to the map panel; setPosition uses absolute coords.
  local saved = hudData[s.name] and hudData[s.name][elemId]
  local rx = saved and clampInt(saved.x, 100) or clampInt(opts.x, 100)
  local ry = saved and clampInt(saved.y, 100) or clampInt(opts.y, 100)
  w:setPosition({ x = parent:getX() + rx, y = parent:getY() + ry })
  pcall(function() w:bindRectToParent() end)

  -- Persist this element's per-character position / lock state by MERGING into its
  -- saved entry, so writing one field never wipes the other.
  local function persistField(k, v)
    local pr = hudParent()
    if not pr then return end
    hudData[s.name] = hudData[s.name] or {}
    local e = hudData[s.name][elemId] or {}
    if k then e[k] = v end
    if alive(w) then e.x = w:getX() - pr:getX(); e.y = w:getY() - pr:getY() end
    hudData[s.name][elemId] = e
    saveHud()
  end

  -- Lock = the player froze this element in place (drag disabled). It is persisted
  -- and toggleable from a right-click menu, so the player can lock a HUD where they
  -- want it without touching the script. `draggable` is the script's own default.
  local wantDrag = (opts.draggable ~= false)
  local locked = (saved and saved.locked == true) or (opts.locked == true)
  local function applyDraggable() if alive(w) then w:setDraggable(wantDrag and not locked) end end
  applyDraggable()

  -- Drag to reposition (saved on drop). A drag never also fires onClick, so
  -- dragging the icon won't accidentally trigger its toggle.
  w.onDragEnter = function(self, mousePos)
    self.movingReference = { x = mousePos.x - self:getX(), y = mousePos.y - self:getY() }
    return true
  end
  w.onDragMove = function(self, mousePos)
    if not self.movingReference then return end
    self:setPosition({ x = mousePos.x - self.movingReference.x, y = mousePos.y - self.movingReference.y })
    self:bindRectToParent()
  end
  w.onDragLeave = function(self)
    persistField()
    self.movingReference = nil
    return true
  end

  -- Right-click: let the player lock/unlock this element's position.
  w.onMousePress = function(_, mp, btn)
    if btn == MouseRightButton then
      local menu = g_ui.createWidget('PopupMenu')
      menu:setGameMenu(true)
      menu:addOption(locked and tr('Unlock position') or tr('Lock position'), function()
        locked = not locked
        applyDraggable()
        persistField('locked', locked)
      end)
      menu:display(mp)
      return true
    end
    return false
  end

  -- The handle the script keeps. Every method is safe to call after the icon
  -- (or the whole game UI) was destroyed.
  local handle = { id = elemId }
  function handle:setText(t) if caption and alive(w) then caption:setText(tostring(t)) end return self end
  function handle:setImage(img) if alive(w) then showImage(img) end return self end
  function handle:setItem(id) if alive(w) then showItem(id) end return self end
  function handle:setColor(c) if caption and alive(w) then pcall(function() caption:setColor(c) end) end return self end
  function handle:setBorderColor(c) borderOff = c or borderOff; applyBorder() return self end
  function handle:setBorderColorOn(c) borderOn = c or borderOn; applyBorder() return self end
  function handle:setTooltip(t) if alive(w) then w:setTooltip(tostring(t)) end return self end
  function handle:setOn(on) if alive(w) then w:setOn(on and true or false); applyBorder() end return self end
  function handle:isOn() return alive(w) and w:isOn() or false end
  function handle:setDraggable(on) wantDrag = on and true or false; applyDraggable() return self end
  function handle:setLocked(on) locked = on and true or false; applyDraggable(); persistField('locked', locked) return self end
  function handle:isLocked() return locked end
  function handle:show() if alive(w) then w:show() end return self end
  function handle:hide() if alive(w) then w:hide() end return self end
  function handle:setVisible(v) if alive(w) then w:setVisible(v and true or false) end return self end
  function handle:setPos(x, y)
    local pr = hudParent()
    if pr and alive(w) then
      x, y = clampInt(x, 0), clampInt(y, 0)
      w:setPosition({ x = pr:getX() + x, y = pr:getY() + y }); pcall(function() w:bindRectToParent() end)
      persistField()
    end
    return self
  end
  function handle:getPos()
    local pr = hudParent()
    if pr and alive(w) then return w:getX() - pr:getX(), w:getY() - pr:getY() end
    return 0, 0
  end
  function handle:destroy()
    if alive(w) then pcall(function() w:destroy() end) end
    if s.huds then s.huds[elemId] = nil end
    w = nil
  end

  if type(opts.onClick) == 'function' then
    local cb = opts.onClick
    w.onClick = function() runScriptCallback(s, cb, handle) end
  end

  return handle
end

local function compile(s)
  s.fn = nil
  local code, rerr = readScriptCode(s)
  if not code then
    debugAppend(s.name .. ' read error: ' .. tostring(rerr), '#ff6666')
    return false, rerr
  end
  s.code = code
  if #code == 0 then return true end
  local fn, err = loadstring(code, '@' .. s.name)
  if not fn then
    debugAppend(s.name .. ' compile error: ' .. tostring(err), '#ff6666')
    return false, err
  end
  -- Sandbox: expose `bot`, `Timer`, a persistent `storage`, and `print`=bot.log on
  -- top of the CLOSED SANDBOX_GLOBALS (safe stdlib + g_game/g_map/g_clock only).
  if setfenv then
    setfenv(fn, Scripting.makeEnv({ bot = bot, storage = s.storage, print = bot.log, Timer = botTimer }))
  end
  s.fn = fn
  return true
end

-- ---------------------------------------------------------------------------
-- Enable / disable (= load / unload)
-- ---------------------------------------------------------------------------
local function setEnabled(s, on)
  on = on and true or false
  if on then
    s.errors = 0
    local ok = compile(s)
    if not ok then
      if modules.game_textmessage then
        modules.game_textmessage.displayFailureMessage(tr('Script has a syntax error; see Debug. Not loaded.'))
      end
      return false
    end
    s.enabled = true        -- set before the body runs so its Timers see it enabled
    runScriptOnce(s)        -- run the file body exactly once; it registers Timers
  else
    s.enabled = false
    stopScript(s)
  end
  refreshAutoLoadList()   -- a real load/unload updates the remembered "load on login" set
  save()
  return true
end

-- ---------------------------------------------------------------------------
-- The two lists
-- ---------------------------------------------------------------------------
local function makeRow(listW, name, running)
  if not listW then return end
  local row = g_ui.createWidget('ScriptListRow', listW)
  row:setText(name)
  row:setColor(running and '#9fe08a' or '#cccccc')
  row:setOn(name == selName)
  row.scriptName = name
  -- Select on PRESS, not on release (onClick): inside the helper MainWindow the
  -- release-time onClick is unreliable (same reason the cavebot rows select on press),
  -- so left-clicking a row would silently fail to select it.
  row.onMousePress = function(_, mp, btn)
    if btn == MouseRightButton then Scripting.scriptMenu(name, mp); return true end
    if btn == MouseLeftButton then Scripting.selectScript(name); return true end
    return false
  end
  row.onDoubleClick = function()
    local s = scripts[name]
    if s then setEnabled(s, not s.enabled); Scripting.refreshLists() end
  end
end

function Scripting.refreshLists()
  if disabledListW then disabledListW:destroyChildren() end
  if enabledListW then enabledListW:destroyChildren() end
  for _, name in ipairs(order) do
    local s = scripts[name]
    if s then
      if s.enabled then makeRow(enabledListW, name, true)
      else makeRow(disabledListW, name, false) end
    end
  end
end

function Scripting.selectScript(name)
  if not scripts[name] then return end
  selName = name
  for _, listW in ipairs({ disabledListW, enabledListW }) do
    if listW then
      for _, c in ipairs(listW:getChildren()) do c:setOn(c.scriptName == name) end
    end
  end
  save()
end

-- ---------------------------------------------------------------------------
-- Load / unload (move between the boxes)
-- ---------------------------------------------------------------------------
function Scripting.loadSelected()
  local s = selName and scripts[selName]
  if not s then setStatus(tr('Select a script first.'), '#cc4444'); return end
  if s.enabled then return end
  if setEnabled(s, true) then
    Scripting.refreshLists()
    setStatus(tr('Loaded "%s"', selName), '#44ad25')
  else
    setStatus(tr('Syntax error — see Debug.'), '#cc4444')
  end
end

function Scripting.unloadSelected()
  local s = selName and scripts[selName]
  if not s then setStatus(tr('Select a script first.'), '#cc4444'); return end
  if not s.enabled then return end
  setEnabled(s, false)
  Scripting.refreshLists()
  setStatus(tr('Unloaded "%s"', selName), '#c0c0c0')
end

-- ---------------------------------------------------------------------------
-- Scripts folder
-- ---------------------------------------------------------------------------
function Scripting.openFolder()
  ensureDir()
  local real = scriptsRealDir()
  local ok = pcall(function() g_platform.openDir(real) end)
  if not ok then
    setStatus(tr('Could not open: %s', real), '#cc4444')
  end
  -- Re-scan shortly after, so files added in the folder show up on return.
  scheduleEvent(function() Scripting.rescan() end, 1500)
end

-- Right-click a row: just load/unload (scripts are edited as files in the folder).
function Scripting.scriptMenu(name, mousePos)
  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  local s = scripts[name]
  menu:addOption((s and s.enabled) and tr('Unload') or tr('Load'), function()
    Scripting.selectScript(name)
    if s and s.enabled then Scripting.unloadSelected() else Scripting.loadSelected() end
  end)
  menu:addOption(tr('Open Scripts Folder'), function() Scripting.openFolder() end)
  menu:display(mousePos)
end

-- ---------------------------------------------------------------------------
-- Debug console window
-- ---------------------------------------------------------------------------
function Scripting.openDebug()
  if debugWindow then debugWindow:raise(); debugWindow:focus(); return end
  local w = g_ui.createWidget('ScriptDebugWindow', g_ui.getRootWidget())
  debugWindow = w
  debugListW   = w:recursiveGetChildById('debugList')
  debugScrollW = w:recursiveGetChildById('debugScroll')
  debugSelectW = w:recursiveGetChildById('debugSelectText')

  -- Selection plumbing: keep the invisible overlay scrolled in lock-step with the list
  -- (so the selection sits over the right rows), and let the wheel over the overlay
  -- scroll the list underneath it.
  if debugSelectW and debugListW then
    debugListW.onScrollChange = function(_, offset) debugSelectW:setTextVirtualOffset(offset) end
    debugSelectW.onMouseWheel = function(_, mousePos, dir) return debugListW:onMouseWheel(mousePos, dir) end
  end

  if debugListW then
    for _, line in ipairs(debugLines) do
      local row = g_ui.createWidget('ScriptDebugRow', debugListW)
      row:setText(line.text); row:setColor(line.color)
    end
  end
  refreshDebugSelection()
  pcall(function() if debugScrollW then debugScrollW:setValue(debugScrollW:getMaximum()) end end)

  local function close()
    debugListW = nil; debugScrollW = nil; debugSelectW = nil
    if debugWindow then debugWindow:destroy(); debugWindow = nil end
  end
  w:recursiveGetChildById('closeBtn').onClick = close
  w:recursiveGetChildById('clearBtn').onClick = function()
    debugLines = {}
    if debugListW then debugListW:destroyChildren() end
    if debugSelectW then debugSelectW:setText('') end
  end
  -- Copy All: dump the whole buffer (not just the on-screen selection) to the clipboard.
  w:recursiveGetChildById('copyAllBtn').onClick = function()
    local parts = {}
    for i = 1, #debugLines do parts[i] = debugLines[i].text end
    g_window.setClipboardText(table.concat(parts, '\n'))
  end
end

-- ---------------------------------------------------------------------------
-- Load
-- ---------------------------------------------------------------------------
local function load()
  scripts, order, selName = {}, {}, nil
  -- Per-character: which files were running last session + the auto-reload toggle.
  local enabledSet = {}
  autoLoadList = {}
  autoReload = true
  local p = configPath()
  if p and g_resources.fileExists(p) then
    local ok, res = pcall(function() return json.decode(g_resources.readFileContents(p)) end)
    if ok and type(res) == 'table' then
      for _, name in ipairs(res.enabled or {}) do enabledSet[name] = true; autoLoadList[#autoLoadList + 1] = name end
      selName = res.selected
      autoReload = (res.autoReload ~= false)  -- default ON (absent field == prior always-reload behavior)
    end
  end
  ensureDir()
  local files = listScripts()
  -- Seed a starter script the first time the folder is empty.
  if #files == 0 then
    pcall(function()
      g_resources.writeFileContents(SCRIPTS_DIR .. '/example.lua',
        '-- Example script. The file body runs ONCE when the script is loaded.\n' ..
        '-- For recurring work, register a Timer(intervalMs, function): it runs your\n' ..
        '-- callback every intervalMs while the script stays loaded.\n' ..
        '-- See mods/game_helper/SCRIPTING_API.md for the full bot.* API.\n\n' ..
        'print("script loaded for", bot.name())\n\n' ..
        'Timer(5000, function()\n' ..
        '  print("HP", bot.hpp() .. "%")\n' ..
        'end)\n')
    end)
    files = listScripts()
  end
  for _, name in ipairs(files) do
    scripts[name] = { name = name, enabled = false, storage = {}, errors = 0 }
    order[#order + 1] = name
  end
  -- Re-enable files that were running last session -- but only if auto-reload is on.
  -- (When off, autoLoadList keeps the remembered set so turning it back on restores them.)
  if autoReload then
    for _, name in ipairs(order) do
      if enabledSet[name] then setEnabled(scripts[name], true) end
    end
  end
  if not selName or not scripts[selName] then selName = order[1] end
  -- Reflect the per-character toggle in the checkbox without re-triggering a save.
  if autoReloadW then
    suppressAutoReloadSave = true
    autoReloadW:setChecked(autoReload)
    suppressAutoReloadSave = false
  end
end

-- Re-scan the folder, keeping running scripts running. Picks up files the user
-- added/removed externally; called when the tab is shown and after Open Folder.
function Scripting.rescan()
  if not panel then return end
  ensureDir()
  local files = listScripts()
  local present = {}
  for _, name in ipairs(files) do present[name] = true end
  -- Drop entries whose file vanished (stop them and their Timers if running).
  for name, s in pairs(scripts) do
    if not present[name] then stopScript(s); s.enabled = false; scripts[name] = nil end
  end
  -- Add newly-appeared files.
  for _, name in ipairs(files) do
    if not scripts[name] then
      scripts[name] = { name = name, enabled = false, storage = {}, errors = 0 }
    end
  end
  -- Rebuild order (alphabetical) from what's actually present.
  order = {}
  for _, name in ipairs(files) do order[#order + 1] = name end
  if not selName or not scripts[selName] then selName = order[1] end
  lastFolderSig = table.concat(files, '|')
  Scripting.refreshLists()
  save()
end

-- Folder watch: while the Scripts tab is open, cheaply poll the folder and rescan
-- only when its file set actually changed, so files dropped in show up on their own.
function Scripting.autoRescan()
  if not panel or not panel:isVisible() or not g_game.isOnline() then return end
  local sig = table.concat(listScripts(), '|')
  if sig ~= lastFolderSig then Scripting.rescan() end
end

-- User toggled the "Auto-reload last session scripts" checkbox. Only the flag
-- changes here; autoLoadList (the remembered set) is left intact so the next login
-- still restores it when re-enabled.
local function onAutoReloadChange(_, checked)
  if suppressAutoReloadSave then return end
  autoReload = checked and true or false
  save()
end

-- ---------------------------------------------------------------------------
-- UI mounting (mirrors Cavebot: a panel in the helper content area)
-- ---------------------------------------------------------------------------
local function mountUI(window)
  local contentPanel = window.contentPanel
  panel = g_ui.createWidget('ScriptingPanel', contentPanel)
  if not panel then
    consoleln('[Scripting] ScriptingPanel style not loaded; aborting mount')
    return false
  end
  panel:setId('scriptingPanel')
  panel:addAnchor(AnchorTop, 'optionsTabBar', AnchorBottom)
  panel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  panel:addAnchor(AnchorRight, 'parent', AnchorRight)
  panel:setMarginTop(5)
  panel:hide()

  disabledListW = panel:recursiveGetChildById('disabledList')
  enabledListW  = panel:recursiveGetChildById('enabledList')
  statusLabel   = panel:recursiveGetChildById('scriptingStatus')
  autoReloadW   = panel:recursiveGetChildById('autoReloadCheck')
  if autoReloadW then
    autoReloadW:setChecked(autoReload)
    autoReloadW.onCheckChange = onAutoReloadChange
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Lifecycle (called by helper.lua)
-- ---------------------------------------------------------------------------
function Scripting.init(window)
  helperWindow = window
  if not window or not window.contentPanel then return end
  mountUI(window)
end

function Scripting.online()
  loadHud()  -- restore saved HUD positions BEFORE bodies run (they recreate the icons)
  load()  -- re-enables the scripts that were running last session (runs each body once)
  lastFolderSig = table.concat(order, '|')
  Scripting.refreshLists()
  setStatus(tr('Ready'), '#c0c0c0')
  if rescanEvent then removeEvent(rescanEvent) end
  rescanEvent = cycleEvent(Scripting.autoRescan, 2000) -- folder watch (only while tab visible)
end

function Scripting.offline()
  for _, s in pairs(scripts) do stopScript(s) end  -- cancel every script's Timers
  if rescanEvent then removeEvent(rescanEvent); rescanEvent = nil end
  save()
end

function Scripting.terminate()
  for _, s in pairs(scripts) do stopScript(s) end
  if rescanEvent then removeEvent(rescanEvent); rescanEvent = nil end
  if debugWindow then debugWindow:destroy(); debugWindow = nil end
  debugListW, debugScrollW, debugSelectW = nil, nil, nil
  helperWindow = nil
  panel = nil
end

function Scripting.showPanel()
  if not panel then return end
  panel:show()
  -- Pick up files added/edited in the folder while the tab was hidden.
  if g_game.isOnline() then Scripting.rescan() end
end
function Scripting.hidePanel() if panel then panel:hide() end end

-- Register styles before helper.lua displays its UI.
g_ui.importStyle('styles/scripting')
