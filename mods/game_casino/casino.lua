--[[
  game_casino - Casino window (the "RouletteWindow") over CommandBridge (opcode 211).

  Hosts multiple casino games (roulette-coin, roulette-kkk, slot machine) in one
  client window, replacing the old server-side "watch the reel spin on the map
  SQMs" experience. The draw stays SERVER-AUTHORITATIVE: the server rolls,
  persists and delivers the prize; this window is pure presentation of a result
  the server already decided. If the window closes mid-spin the prize is already
  in the store inbox.

  Loads as a normal module (casino.otmod is autoload:true). The roll is still
  server-authoritative and gated server-side (CASINO_ENABLED in the bridge).

  Games register themselves through Casino.registerGame{...} (see games/*.lua),
  so adding a game later is one more file - the shell here never changes.

  Protocol (CommandBridge, casino.* actions - disjoint from craft.*/task.*):
    server -> client  { event = "casino.open",  data = <catalog> }             (push)
    client -> server  { action = "casino.state", data = {},              requestId }
    client -> server  { action = "casino.play",  data = { game, package }, requestId }
    server -> client  { requestId, type = "response", data = { plays, ... } }
    server -> client  { requestId, type = "error",    message = "..." }

  <catalog> = { games = { { id, title, icon, currency, balance, packages, ... }, ... } }
]]

Casino = Casino or {}
Casino.games = Casino.games or {}          -- ordered list of registered game defs
Casino.gamesById = Casino.gamesById or {}  -- id -> game def

local window            -- the CasinoWindow (nil when closed)
local selectorPanel     -- game selector bar
local gameArea          -- content area where the active game draws
local activeGameId      -- currently shown game id
local lastCatalog       -- last catalog received from the server
local openHandler       -- CommandBridge "casino.open" handler ref
local pzConnected = false

-- ============================================================================
-- game registry (expansibility hook)
-- ============================================================================

-- def = {
--   id, title, icon, currency,          -- identity + display
--   build(self, parent)  -> widget,     -- lazy-builds the game's panel once
--   onCatalog(self, entry),             -- server data for this game (balance, packages, prizes)
--   onResult(self, data),               -- casino.play response payload
--   onPzChange(self, inPz),             -- enable/disable the spin button
--   onShow(self), onHide(self),
-- }
function Casino.registerGame(def)
  if type(def) ~= "table" or type(def.id) ~= "string" or def.id == "" then
    return
  end
  if Casino.gamesById[def.id] then
    return -- already registered (survives module reload)
  end
  def.panel = nil
  Casino.gamesById[def.id] = def
  table.insert(Casino.games, def)
  -- If the window is already open (hot-registered), rebuild the selector.
  if window then Casino.rebuildSelector() end
end

function Casino.getGame(id)
  return id and Casino.gamesById[id] or nil
end

-- ============================================================================
-- PZ gate (client UX only; the server re-validates PZ authoritatively)
-- ============================================================================

function Casino.isInPz()
  local p = g_game.getLocalPlayer()
  return p ~= nil and p:isInProtectionZone()
end

local function updatePzGate()
  if not window then return end
  local inPz = Casino.isInPz()
  local game = activeGameId and Casino.gamesById[activeGameId]
  if game and game.onPzChange then
    pcall(game.onPzChange, game, inPz)
  end
end
Casino.updatePzGate = updatePzGate

-- LocalPlayer state bitmask changed (includes entering/leaving a protection zone).
function onStatesChange(localPlayer, now, old)
  if window then updatePzGate() end
end

-- ============================================================================
-- request helper (games call this to spin)
-- ============================================================================

-- Sends casino.play and routes the response to the game's onResult / error UI.
function Casino.requestPlay(gameId, packageId, onDone)
  if not CommandBridge or not CommandBridge.request then return end
  CommandBridge.request("casino.play", { game = gameId, package = packageId },
    function(response)
      if type(response) ~= "table" then return end
      local game = Casino.gamesById[gameId]
      if response.type == "error" then
        local msg = response.message or "The house declined your bet."
        if game and game.onError then pcall(game.onError, game, msg) end
        if onDone then pcall(onDone, false, msg) end
        return
      end
      local data = response.data or response
      if game and game.onResult then pcall(game.onResult, game, data) end
      if onDone then pcall(onDone, true, data) end
    end)
end

-- Claim (collect) the prize for a spin whose animation just finished. The server
-- rolled and persisted it on casino.play but withheld delivery; this hands it over
-- so the item lands as the reel stops, not on the click. onClaimed(data) receives
-- the updated { spinCount } for the progress bar. Fire-and-forget on failure: an
-- unclaimed roll stays persisted server-side and is delivered on next login.
function Casino.claim(uuid, onClaimed)
  if not uuid or not CommandBridge or not CommandBridge.request then return end
  CommandBridge.request("casino.claim", { uuid = uuid }, function(response)
    if type(response) ~= "table" or response.type == "error" then return end
    local data = response.data or response
    if onClaimed then pcall(onClaimed, data) end
  end)
end

-- ============================================================================
-- selector + active-game switching
-- ============================================================================

-- Which games to show: those registered on the client AND enabled by the server
-- catalog. With no catalog (dev/no-server), fall back to every registered game.
local function catalogEntryFor(id)
  if not lastCatalog or type(lastCatalog.games) ~= "table" then return nil end
  for _, entry in ipairs(lastCatalog.games) do
    if entry.id == id then return entry end
  end
  return nil
end

local function isGameAvailable(id)
  if not lastCatalog or type(lastCatalog.games) ~= "table" then
    return true -- no catalog: show all registered games
  end
  return catalogEntryFor(id) ~= nil
end

function Casino.rebuildSelector()
  if not selectorPanel then return end
  selectorPanel:destroyChildren()
  local available = {}
  for _, game in ipairs(Casino.games) do
    if isGameAvailable(game.id) then available[#available + 1] = game end
  end

  -- No tabs when there's only one game: collapse the selector (the game area is
  -- anchored to its bottom, so it just moves up to the top).
  if #available <= 1 then
    selectorPanel:setHeight(0)
    selectorPanel:hide()
  else
    selectorPanel:setHeight(24)
    selectorPanel:show()
    for _, game in ipairs(available) do
      local btn = g_ui.createWidget('CasinoGameTab', selectorPanel)
      btn:setId('tab_' .. game.id)
      btn:setText(game.title or game.id)
      if game.icon and btn.icon then btn.icon:setImageSource(game.icon) end
      btn.onClick = function() Casino.selectGame(game.id) end
    end
  end

  local first = available[1] and available[1].id or nil
  if activeGameId and isGameAvailable(activeGameId) then
    Casino.selectGame(activeGameId)
  elseif first then
    Casino.selectGame(first)
  else
    activeGameId = nil
  end
end

function Casino.selectGame(id)
  local game = Casino.gamesById[id]
  if not game or not gameArea then return end

  -- hide the previously active game
  if activeGameId and activeGameId ~= id then
    local prev = Casino.gamesById[activeGameId]
    if prev then
      if prev.panel then prev.panel:setVisible(false) end
      if prev.onHide then pcall(prev.onHide, prev) end
    end
  end

  -- lazy-build this game's panel once
  if not game.panel and game.build then
    local ok, panel = pcall(game.build, game, gameArea)
    game.panel = ok and panel or nil
  end
  if game.panel then game.panel:setVisible(true) end

  -- feed it the latest server data for this game
  local entry = catalogEntryFor(id)
  if entry and game.onCatalog then pcall(game.onCatalog, game, entry) end

  activeGameId = id

  -- reflect selected state on the tabs
  if selectorPanel then
    for _, child in ipairs(selectorPanel:getChildren()) do
      child:setOn(child:getId() == ('tab_' .. id))
    end
  end

  if game.onShow then pcall(game.onShow, game) end
  updatePzGate()
end

-- ============================================================================
-- window lifecycle
-- ============================================================================

function Casino.show(catalog)
  Casino.close()
  window = g_ui.createWidget('CasinoWindow', g_ui.getRootWidget())
  if not window then return end
  lastCatalog = (type(catalog) == "table") and catalog or nil

  selectorPanel = window:recursiveGetChildById('gameSelector')
  gameArea = window:recursiveGetChildById('gameArea')

  Casino.rebuildSelector()

  window:show()
  window:raise()
  window:focus()
  window:lockScrim() -- modal dim behind, no full-UI freeze (same as craft)
  updatePzGate()
end

function Casino.close()
  if window then
    -- Tell the server the window closed so it delivers any spins whose reel never
    -- finished (a multi-spin batch abandoned mid-way) instead of holding them until
    -- relog. Fire-and-forget; a no-op server-side if nothing is pending (or offline).
    if CommandBridge and CommandBridge.send then
      pcall(CommandBridge.send, "casino.closed", {})
    end
    window:unlockScrim()
    window:destroy()
    window = nil
  end
  selectorPanel = nil
  gameArea = nil
  -- drop per-game panels so they rebuild fresh next open
  for _, game in ipairs(Casino.games) do
    game.panel = nil
    if game.onClosed then pcall(game.onClosed, game) end
  end
  activeGameId = nil
  if modules.game_interface then
    local panel = modules.game_interface.getRootPanel()
    if panel then panel:focus() end
  end
end

-- Enable/disable the window's Close button. Used to trap the player in the window
-- while a spin animation runs; the @onEscape path is guarded in close() below.
function Casino.lockClose(locked)
  if not window then return end
  local btn = window:recursiveGetChildById('closeButton')
  if btn then btn:setEnabled(not locked) end
end

function Casino.toggle()
  if window then Casino.close() return end
  -- No server push: request a fresh catalog and open when it arrives.
  if not CommandBridge or not CommandBridge.request then return end
  CommandBridge.request("casino.state", {}, function(response)
    if type(response) ~= "table" or response.type == "error" then return end
    local data = response.data or response
    if type(data) == "table" then Casino.show(data) end
  end)
end

-- server push: the physical casino machine was used
local function onOpenEvent(data)
  if g_logger then g_logger.info("[casino] casino.open received from server") end
  local payload = data and (data.data or data)
  Casino.show(type(payload) == "table" and payload or {})
end

-- ============================================================================
-- init / terminate
-- ============================================================================

function onGameStart()
  if CommandBridge and CommandBridge.on then
    openHandler = onOpenEvent
    CommandBridge.on("casino.open", openHandler)
  end
  if not pzConnected then
    connect(LocalPlayer, { onStatesChange = onStatesChange })
    pzConnected = true
  end
end

function onGameEnd()
  if openHandler and CommandBridge and CommandBridge.off then
    CommandBridge.off("casino.open", openHandler)
    openHandler = nil
  end
  if pzConnected then
    disconnect(LocalPlayer, { onStatesChange = onStatesChange })
    pzConnected = false
  end
  Casino.close()
end

-- otui @onClick / @onEscape resolve bare names in the module env (modules.game_casino),
-- where Casino.* methods are NOT visible as bare names. Expose a global wrapper so
-- `modules.game_casino.close()` from casino.otui works. Refuses to close while the
-- active game is mid-spin, so the player must wait for the reels (and each prize
-- claim) to finish - they cannot bail on the animation.
function close()
  local game = activeGameId and Casino.gamesById[activeGameId]
  if game and game.isBusy and game:isBusy() then
    return
  end
  Casino.close()
end

function init()
  if g_logger then g_logger.info("[casino] client module loaded") end
  g_ui.importStyle(resolvepath('casino'))
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  onGameEnd()
end
