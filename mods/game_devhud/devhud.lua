--[[
  game_devhud - Dev/QA HUD shell over CommandBridge (opcode 211).

  A corner "QA" button on the game map opens a tabbed window to mutate the LOCAL
  player (level, skills, attack speed, reflect/mitigation, items, addons). The button
  is created ONLY after the server answers dev.state, which it does only in a test
  environment (serverEnvironment ~= "PRD"). So it never appears in production, and
  even if a tampered client forced it, the server-side bridge rejects every dev.*
  command. Client gating here is pure UX; the security lives in
  data-koliseu/scripts/custom/devhud_otc_bridge.lua.

  Tabs register themselves via Devhud.registerTab{...} (see tabs/*.lua), so adding a
  new tab later is one more file - the shell never changes.
]]

Devhud = Devhud or {}
Devhud.tabs = Devhud.tabs or {}           -- ordered list of tab defs
Devhud.tabsById = Devhud.tabsById or {}   -- id -> def

local launcher            -- corner button (nil until the server enables us)
local window              -- DevHudWindow (built on first open, then reused)
local tabSelector         -- selector bar inside the window
local contentArea         -- where the active tab draws
local statusLabel         -- footer status line
local activeTabId
local serverState         -- last snapshot the server sent (dev.state / mutation reply)
local enabled = false     -- server confirmed a test environment

-- ============================================================================
-- tab registry (expansibility hook — same shape as Casino.registerGame)
-- ============================================================================

-- def = {
--   id, title,            -- identity + tab caption
--   build(self, panel),   -- lazy-builds the tab's controls once, into `panel`
--   onState(self, state), -- (optional) feed the latest server snapshot
-- }
function Devhud.registerTab(def)
  if type(def) ~= "table" or type(def.id) ~= "string" or def.id == "" then return end
  if Devhud.tabsById[def.id] then return end
  def.panel = nil
  Devhud.tabsById[def.id] = def
  table.insert(Devhud.tabs, def)
  if window then Devhud.rebuildSelector() end
end

function Devhud.getState() return serverState end

-- ============================================================================
-- server round-trip (tabs call Devhud.apply to mutate the player)
-- ============================================================================

function Devhud.setStatus(text, isError)
  if statusLabel then
    statusLabel:setText(text or "")
    statusLabel:setColor(isError and "#e05a4d" or "#c0c0c0")
  end
  if g_logger then g_logger.info("[devhud] " .. tostring(text)) end
end

local function refreshTabs()
  for _, def in ipairs(Devhud.tabs) do
    if def.panel and def.onState then pcall(def.onState, def, serverState) end
  end
end
Devhud.refreshTabs = refreshTabs

-- The server echoes a fresh snapshot: dev.state replies with the snapshot directly,
-- dev.setX replies with { ok, value, state = snapshot }. Accept either shape.
local function absorbSnapshot(d)
  local snap = (type(d) == "table" and d.state) or d
  if type(snap) == "table" and type(snap.skills) == "table" then
    serverState = snap
    refreshTabs()
    return true
  end
  return false
end

-- Send dev.<action> and route the reply back into the tabs.
function Devhud.apply(action, data, onDone)
  if not CommandBridge or not CommandBridge.request then return end
  CommandBridge.request(action, data, function(response)
    if type(response) ~= "table" then return end
    if response.type == "error" then
      Devhud.setStatus("ERR: " .. tostring(response.message), true)
      if onDone then pcall(onDone, false, response) end
      return
    end
    local d = response.data or response
    absorbSnapshot(d)
    Devhud.setStatus("OK: " .. tostring(action))
    if onDone then pcall(onDone, true, d) end
  end)
end

-- ============================================================================
-- window build + tab switching
-- ============================================================================

function Devhud.rebuildSelector()
  if not tabSelector then return end
  tabSelector:destroyChildren()
  local first
  for _, def in ipairs(Devhud.tabs) do
    local btn = g_ui.createWidget('DevHudTab', tabSelector)
    btn:setId('tab_' .. def.id)
    btn:setText(def.title or def.id)
    btn.onClick = function() Devhud.selectTab(def.id) end
    first = first or def.id
  end
  if activeTabId and Devhud.tabsById[activeTabId] then
    Devhud.selectTab(activeTabId)
  elseif first then
    Devhud.selectTab(first)
  end
end

function Devhud.selectTab(id)
  local def = Devhud.tabsById[id]
  if not def or not contentArea then return end

  if activeTabId and activeTabId ~= id then
    local prev = Devhud.tabsById[activeTabId]
    if prev and prev.panel then prev.panel:setVisible(false) end
  end

  -- lazy-build this tab's panel once
  if not def.panel then
    local panel = g_ui.createWidget('DevHudTabPanel', contentArea)
    panel:setId('panel_' .. def.id)
    def.panel = panel
    if def.build then
      local ok, err = pcall(def.build, def, panel)
      if not ok and g_logger then g_logger.error("[devhud] tab build failed: " .. tostring(err)) end
    end
    if def.onState and serverState then pcall(def.onState, def, serverState) end
  end
  def.panel:setVisible(true)
  activeTabId = id

  for _, child in ipairs(tabSelector:getChildren()) do
    child:setOn(child:getId() == ('tab_' .. id))
  end
end

-- ============================================================================
-- corner launcher on the game map
-- ============================================================================

local function createLauncher()
  if launcher then return end
  local map = modules.game_interface and modules.game_interface.getMapPanel()
  if not map then return end
  launcher = g_ui.createWidget('DevHudLauncher', map)
  launcher:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  launcher:addAnchor(AnchorRight, 'parent', AnchorRight)
  launcher:setMarginBottom(6)
  launcher:setMarginRight(6)
  launcher.onClick = function() Devhud.toggle() end
  launcher:raise()
end

local function destroyLauncher()
  if launcher then launcher:destroy(); launcher = nil end
end

-- ============================================================================
-- window lifecycle
-- ============================================================================

local function buildWindow()
  if window then return end
  window = g_ui.createWidget('DevHudWindow', g_ui.getRootWidget())
  tabSelector = window:getChildById('tabSelector')
  contentArea = window:getChildById('contentArea')
  statusLabel = window:recursiveGetChildById('statusLabel')
  local closeButton = window:recursiveGetChildById('closeButton')
  if closeButton then closeButton.onClick = function() Devhud.close() end end
  window.onEscape = function() Devhud.close() end
  Devhud.rebuildSelector()
  window:hide()
end

function Devhud.show()
  if not enabled then return end
  buildWindow()
  window:show()
  window:raise()
  window:focus()
  if launcher then launcher:setOn(true) end
  Devhud.apply('dev.state', {}, nil) -- re-sync the snapshot each open
end

function Devhud.close()
  for _, def in ipairs(Devhud.tabs) do if def.onClose then pcall(def.onClose) end end
  if window then window:hide() end
  if launcher then launcher:setOn(false) end
end

function Devhud.toggle()
  if window and window:isVisible() then Devhud.close() else Devhud.show() end
end

-- ============================================================================
-- gate: only a test server answers dev.state
-- ============================================================================

local probeTries = 0
local function probeServer()
  if enabled then return end
  if not g_game.isOnline() then return end
  if CommandBridge and CommandBridge.request then
    CommandBridge.request('dev.state', {}, function(response)
      if type(response) ~= "table" or response.type == "error" then return end
      local d = response.data or response
      if type(d) ~= "table" or type(d.skills) ~= "table" then return end
      serverState = d
      enabled = true
      createLauncher()
    end)
  end
  -- Retry a few times: in PRD there is simply no reply and the button never shows;
  -- in DEV/QAS this covers the case where the extended channel wasn't ready yet.
  probeTries = probeTries + 1
  if probeTries < 4 then
    scheduleEvent(probeServer, 2500)
  end
end

function onGameStart()
  enabled = false
  serverState = nil
  probeTries = 0
  -- Small delay so the extended-opcode channel is up before we probe.
  scheduleEvent(probeServer, 1000)
end

function onGameEnd()
  destroyLauncher()
  for _, def in ipairs(Devhud.tabs) do if def.onClose then pcall(def.onClose) end end
  if window then window:destroy(); window = nil end
  tabSelector = nil
  contentArea = nil
  statusLabel = nil
  activeTabId = nil
  for _, def in ipairs(Devhud.tabs) do def.panel = nil end
  enabled = false
  serverState = nil
end

function init()
  g_ui.importStyle(resolvepath('devhud'))
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  onGameEnd()
end
