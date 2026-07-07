--[[
  Task Manager Module - AMON port (KoliseuOT / AstraClient)

  Faithful port of the AMON game_tasks module. All state arrives via CommandBridge
  as state.tasks (extended opcode 211 JSON). Server-driven; INERT until the target
  server implements the 211 task protocol. Set DEMO_MODE = true (below) to populate
  the UI with representative mock data for review without a server.

  Server schema (state.tasks):
    active = {
      { taskId, currentKills, requiredKills, startedAt, flags,
        name, lookType },
      ...
    },
    allTasks       = { { taskId, name, lookType, requiredKills,
                         exp, taskPoints, ... }, ... },  -- optional payload
    renewerFlags   = number,  -- bitmask, bit0=enabled, bit1=owned
    renewerEnabled = bool,
    renewerOwned   = bool,
    points         = number,  -- lifetime task points
    completedToday = number,
    completedTotal = number,
    killMultiplier = number,
    expMultiplier  = number,
    tokenMultiplier= number,

  Client -> server actions:
    task.list            : pull initial active + (optionally) full list
    task.start  {taskId} : start a task
    task.abort  {taskId} : abort a task
    task.finish {taskId} : claim reward
    task.toggleRenewer   : flip auto-renew

  Server events:
    task.completed { name } : show toast on the client
    task.openWindow         : open/raise the main window remotely

  Strings are ASCII only; OTClient fonts mangle Unicode.

  PORT NOTES (deviations from AMON, to fit this client):
    - This client's UIMiniWindow has no setupOnStart()/getSettings(); both calls are
      guarded so the tracker does not crash.
    - CommandBridge integrations are unchanged; the bus itself was stripped of
      AMON-only actions in command_bridge.lua.
    - 0xBC TaskKillTick binary opcode is implemented in Lua via
      ProtocolGame.registerOpcode (runs before the C++ switch; no C++/rebuild). The
      wire contract is documented at OPCODE_TASK_KILL_TICK; inert until the server emits it.
]]

-- ============================================
-- DEMO / MOCK DATA (review aid, OFF by default)
-- ============================================
-- Flip to true to inject a representative state.tasks ~1.5s after the window is
-- first opened IF no real server data has arrived. Fed through applyTasksState,
-- the exact path the server uses, so it never interferes with real data.
local DEMO_MODE = false

-- ============================================
-- Module State
-- ============================================
local window               = nil
local trackerWindow        = nil
local confirmWindow        = nil
local autoRenewConfirmWindow = nil
local autoRenewPendingEnable = nil
local taskPayConfirmWindow = nil
local pendingPayTaskId     = nil  -- taskId aguardando confirmacao de pagamento
local shopBuyConfirmWindow = nil
local pendingShopBuy       = nil  -- { itemId, name, price, amount } aguardando confirmacao
local boostRewardConfirmWindow = nil
local boostSkipConfirm     = false  -- per-character: skip the boost confirm modal

-- Salvamos o callback original de updateInventoryItems pra chainar sem perder
-- outros modulos que tambem patcham (game_actionbar, game_helper).
local previousUpdateInventoryItems = nil
local inventoryItemsUpdateCallback = nil

local selectedTask         = nil
local currentTab           = 'active'
local currentShopTier      = 1   -- which shop tier tab is active (1=common,2=rare,3=legendary)

local activeTasks          = {}
local allTasks             = {}
local shopItems            = {}
local taskState            = {
  points = 0,
  completedToday = 0,
  completedTotal = 0,
  killMultiplier = 1,
  expMultiplier = 1,
  tokenMultiplier = 1,
  renewerEnabled = false,
  renewerOwned = false,
}

local messageEvent         = nil
local trackerVisible       = false
local listRequested        = false
local lastTrackerSignature = ''
local lastCompletedTotal   = nil
local demoEvent            = nil
local demoApplied          = false
local serverDataSeen       = false

-- Max simultaneous active tasks. SERVER-DRIVEN via state.tasks.maxActive; falls back to
-- DEFAULT_MAX_ACTIVE (current KoliseuOT rule = 2) until the server sends the field.
local DEFAULT_MAX_ACTIVE = 2
local TASK_TOKEN_ID  = 66142   -- Common task token (tier 1); see TOKEN_TIERS below.
local debug          = false

-- The three task-token tiers shown in the Shop tab as "<sprite> <qty>", in order
-- common -> rare -> legendary. itemId == 0 hides that tier.
local TOKEN_TIERS = {
  { key = 'common',    itemId = 66142, name = 'Common Task Token'    },
  { key = 'rare',      itemId = 66143, name = 'Rare Task Token'      },
  { key = 'legendary', itemId = 66144, name = 'Legendary Task Token' },
}

-- Max active tasks the player may hold at once (server-driven; see DEFAULT_MAX_ACTIVE).
local function getMaxActiveTasks()
  return tonumber(taskState.maxActive) or DEFAULT_MAX_ACTIVE
end

-- Labels do tipo da task. Server envia taskType como NUMERO (enum TaskType_t):
--   0 = Once, 1 = Daily, 2 = Repeatable.
-- Mapeamos por numero E por string para compat com payloads antigos.
-- Sem limite diario no koliseuot: "Daily" (1) e exibido como "Repeatable" (nenhum texto Daily).
local TYPE_LABELS = {
  [0]        = 'One-time',
  [1]        = 'Repeatable',
  [2]        = 'Repeatable',
  once       = 'One-time',
  daily      = 'Repeatable',
  repeatable = 'Repeatable',
}

-- Formata o tipo da task para exibicao: "Repeatable".
-- Server inconsistente: catalogo usa "type", slot ativo usa "taskType". Lemos ambos.
local function formatTaskTypeLabel(task)
  if not task then return '' end
  local raw = task.taskType or task.type
  return TYPE_LABELS[raw] or tostring(raw or '')
end

-- Renewer flag bits (mirror C++ side).
-- Bits 2 e 3 sao reservados (eram ChannelEnabled e SendPv; ambos removidos em 2026-05).
local RENEWER_FLAG_ENABLED         = 1   -- bit 0
local RENEWER_FLAG_OWNED           = 2   -- bit 1

-- Tasks binary protocol: opcode 0xBC TaskKillTick (server -> client), enviado em
-- throttle ~1500ms no hot path de kills. Implementado 100% em Lua via
-- ProtocolGame.registerOpcode (roda ANTES do switch C++; sem C++/rebuild).
-- Contrato de wire KoliseuOT (o crystalserver deve emitir EXATAMENTE isto):
--   U8  count                    -- numero de tasks neste tick (<= max ativas)
--   count x:
--     U32 taskId
--     U32 currentKills
--     U32 requiredKills
--     U8  flags                  -- bitmask por-task (reservado; 0 por ora)
local OPCODE_TASK_KILL_TICK = 0xBC   -- 188

local function bandSafe(value, mask)
  value = tonumber(value) or 0
  mask = tonumber(mask) or 0
  if bit and bit.band then return bit.band(value, mask) end
  if bit32 and bit32.band then return bit32.band(value, mask) end
  -- Fallback: brute mod-2 walk; mask is tiny so it is fine.
  local result = 0
  local power = 1
  while mask > 0 and value > 0 do
    local mbit = mask % 2
    local vbit = value % 2
    if mbit == 1 and vbit == 1 then result = result + power end
    mask = (mask - mbit) / 2
    value = (value - vbit) / 2
    power = power * 2
  end
  return result
end

-- Monta tabela de outfit completa a partir de uma task. O server envia lookType +
-- lookHead/Body/Legs/Feet/Addons/Mount no JSON CommandBridge (state.tasks.active[i]) -
-- usamos isso para renderizar creature preview com as cores corretas do monstro.
local function buildTaskOutfit(task)
  return {
    type   = task.lookType   or 0,
    head   = task.lookHead   or 0,
    body   = task.lookBody   or 0,
    legs   = task.lookLegs   or 0,
    feet   = task.lookFeet   or 0,
    addons = task.lookAddons or 0,
    mount  = task.lookMount  or 0,
  }
end

-- ============================================
-- Monster looktype resolution (for the 3 overlapping creature previews per card)
-- ============================================
-- g_things.getMonsterList() -> { [raceId] = { name, lookType, lookTypeEx, head,
-- body, legs, feet, addons } } (1-indexed tuple). Tasks here group several monsters
-- and only carry their NAMES (task.races), so we resolve name -> outfit. The call
-- marshals the whole ~2-3k monster table, so build the map ONCE and cache it.
local monsterOutfitByName = nil
local function getMonsterOutfitMap()
  if monsterOutfitByName then return monsterOutfitByName end
  local map = {}
  if g_things and g_things.getMonsterList then
    local ok, list = pcall(function() return g_things.getMonsterList() end)
    if ok and type(list) == 'table' then
      for _, t in pairs(list) do
        local lt = (type(t) == 'table') and tonumber(t[2]) or nil
        if t and t[1] and lt and lt > 0 then
          map[tostring(t[1]):lower()] = {
            type = lt, head = t[4] or 0, body = t[5] or 0,
            legs = t[6] or 0, feet = t[7] or 0, addons = t[8] or 0,
          }
        end
      end
    end
  end
  -- Cache only once populated so an early call (before static data is loaded)
  -- doesn't pin an empty map forever.
  if next(map) then monsterOutfitByName = map end
  return map
end

-- Pick up to `maxN` outfits from a task's monsters, random but STABLE per task
-- (memoized by id) so the card preview does not reshuffle on every list refresh.
local taskPreviewOutfits = {}
local function resolveTaskPreviewOutfits(task, maxN)
  local id = task.taskId or task.id or task.name
  if id and taskPreviewOutfits[id] then return taskPreviewOutfits[id] end

  local map = getMonsterOutfitMap()
  local pool = {}
  for _, raceName in ipairs(task.races or {}) do
    local o = map[tostring(raceName):lower()]
    if o then pool[#pool + 1] = o end
  end
  -- Fallback to the task's own lookType when no race resolved (or none listed).
  if #pool == 0 and tonumber(task.lookType) and task.lookType > 0 then
    pool[#pool + 1] = buildTaskOutfit(task)
  end
  -- Fisher-Yates shuffle: the previews are a random sample of the task's mobs.
  for i = #pool, 2, -1 do
    local j = math.random(i)
    pool[i], pool[j] = pool[j], pool[i]
  end
  local picked = {}
  for i = 1, math.min(maxN, #pool) do picked[i] = pool[i] end
  if id then taskPreviewOutfits[id] = picked end
  return picked
end

local function debugPrint(...)
  if not debug then return end
  local args = { ... }
  local parts = {}
  for i = 1, #args do parts[#parts + 1] = tostring(args[i]) end
  print('[Tasks Debug] ' .. table.concat(parts, ' '))
end

-- (Favorites feature removed: task cards now show only their type label.)

-- ============================================
-- Lifecycle
-- ============================================
local function isTaskTokenId(id)
  if not id then return false end
  for _, tier in ipairs(TOKEN_TIERS) do
    if (tonumber(tier.itemId) or 0) == id then return true end
  end
  return false
end

-- Container signal handlers: refresh the Shop token balance whenever any task-token
-- tier item enters/leaves/updates a container. O server cache (getInventoryCount) ja
-- vem fresco; so precisamos disparar o redraw da barra.
local function onTokenContainerEvent(_container, _slot, item, oldItem)
  if not window or not window:isVisible() then return end
  local id = item and item:getId() or (oldItem and oldItem:getId())
  if not isTaskTokenId(id) then return end
  if updateShopTiers then updateShopTiers() end
end

local tokenContainerSignals = {
  onAddItem    = onTokenContainerEvent,
  onUpdateItem = onTokenContainerEvent,
  onRemoveItem = onTokenContainerEvent,
}

-- Style/UI loading is order-fragile in this client: g_ui.importStyle/displayUI
-- resolve a RELATIVE name ('styles', 'tasks') against the CALLER's stack frame, which
-- is the wrong frame when these run from an event callback / pcall (the dispatcher)
-- instead of directly from module code. The styles in styles.otui (TaskButton, ...)
-- then silently never register and every displayUI here dies with "'TaskButton' is not
-- a defined style" -> window=nil -> cascade (that was the open-task-dialog error).
-- Fix mirrors game_helper: pre-resolve to an ABSOLUTE path with resolvepath() (whose
-- frame is always THIS file) and (re)import the styles right before each use
-- (importStyle is idempotent, so calling it every time is cheap).
local function ensureStyles()
  g_ui.importStyle(resolvepath('styles'))
  g_ui.importStyle(resolvepath('tasktracker'))
end

local function displayTaskUI(name)
  ensureStyles()
  return g_ui.displayUI(resolvepath(name))
end

function init()
  pcall(function() math.randomseed(os.time()) end)
  ensureStyles()

  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd   = onGameEnd,
  })
  connect(Container, tokenContainerSignals)

  -- Hook no cache de inventario do server (atualizado por pacotes 0xF5).
  -- Disparado em compras NPC/Shop, sells, equip/unequip. Chainamos preservando
  -- o callback anterior (actionbar/helper tambem patcham).
  previousUpdateInventoryItems = g_game.updateInventoryItems
  inventoryItemsUpdateCallback = function(...)
    if previousUpdateInventoryItems then previousUpdateInventoryItems(...) end
    if window and window:isVisible() then updateStats() end
  end
  g_game.updateInventoryItems = inventoryItemsUpdateCallback

  initCommandBridge()

  if g_game.isOnline() then
    onGameStart()
  end
end

function terminate()
  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd   = onGameEnd,
  })
  disconnect(Container, tokenContainerSignals)

  -- Restaura cadeia de updateInventoryItems (so se ainda somos o ultimo elo).
  if inventoryItemsUpdateCallback and g_game.updateInventoryItems == inventoryItemsUpdateCallback then
    g_game.updateInventoryItems = previousUpdateInventoryItems
  end
  previousUpdateInventoryItems = nil
  inventoryItemsUpdateCallback = nil

  terminateCommandBridge()
  -- unbind ocorre em onGameEnd quando window e destruida; aqui so cobre o caso de
  -- recarga do modulo enquanto o player esta logado.
  if window and not window:isDestroyed() then
    g_keyboard.unbindKeyDown('Escape', window)
  end

  destroy()
end

function onGameStart()
  if window then
    window:destroy()
    window = nil
  end

  loadBoostPref()
  listRequested = false
  lastCompletedTotal = nil
  demoApplied = false
  serverDataSeen = false
  if demoEvent then removeEvent(demoEvent); demoEvent = nil end

  window = displayTaskUI('tasks')
  window:hide()

  -- Escape scope na window: so fecha modais/window quando ela esta visivel/focada,
  -- evita competir com Escape global de outros modulos.
  g_keyboard.bindKeyDown('Escape', onEscape, window)

  local searchInput = window:recursiveGetChildById('searchInput')
  if searchInput then searchInput.onTextChange = onSearchChange end

  local taskList = window:recursiveGetChildById('taskList')
  if taskList then taskList.onChildFocusChange = onTaskSelect end

  setTab('active')
  createTracker()

  -- setupOnStart() existe na corelib do AMON mas NAO neste client; guard.
  if trackerWindow and trackerWindow.setupOnStart then
    trackerWindow:setupOnStart()
  end

  -- Apply whatever state already arrived (CommandBridge auto-pushes on login).
  if CommandBridge and CommandBridge.getState then
    local s = CommandBridge.getState()
    if s and s.tasks then
      serverDataSeen = true
      applyTasksState(s.tasks)
      lastCompletedTotal = taskState.completedTotal
    end
  end
end

function onGameEnd()
  destroy()
end

function destroy()
  if messageEvent then
    removeEvent(messageEvent)
    messageEvent = nil
  end
  if demoEvent then
    removeEvent(demoEvent)
    demoEvent = nil
  end

  if modules.game_interface and modules.game_interface.getMapPanel then
    local mapPanel = modules.game_interface.getMapPanel()
    if mapPanel then mapPanel:setEnabled(true) end
  end

  closeConfirmModal()

  if autoRenewConfirmWindow then
    autoRenewConfirmWindow:destroy()
    autoRenewConfirmWindow = nil
  end
  autoRenewPendingEnable = nil

  if taskPayConfirmWindow then
    taskPayConfirmWindow:destroy()
    taskPayConfirmWindow = nil
  end
  pendingPayTaskId = nil

  if shopBuyConfirmWindow then
    shopBuyConfirmWindow:destroy()
    shopBuyConfirmWindow = nil
  end
  pendingShopBuy = nil

  if boostRewardConfirmWindow then
    boostRewardConfirmWindow:destroy()
    boostRewardConfirmWindow = nil
  end

  if window then
    window:destroy()
    window = nil
  end

  if trackerWindow then
    trackerWindow:destroy()
    trackerWindow = nil
  end

  selectedTask         = nil
  activeTasks          = {}
  allTasks             = {}
  shopItems            = {}
  taskState            = {
    points = 0, completedToday = 0, completedTotal = 0,
    killMultiplier = 1, expMultiplier = 1, tokenMultiplier = 1,
    renewerEnabled = false, renewerOwned = false,
  }
  lastTrackerSignature = ''
  listRequested        = false
  lastCompletedTotal   = nil
  demoApplied          = false
  serverDataSeen       = false
end

-- ============================================
-- Window control
-- ============================================
local function resetWindowState()
  selectedTask = nil
  hideDetailsPanel()
end

local function focusGameRoot()
  if not modules.game_interface or not modules.game_interface.getRootPanel then return end
  local root = modules.game_interface.getRootPanel()
  if not root then return end
  scheduleEvent(function()
    if root and not root:isDestroyed() and root:isVisible() then
      -- So focus (devolve o input ao jogo). SEM root:raise(): re-ordenar o painel raiz
      -- do jogo (gigante) no rootWidget forca redraw/re-aplicacao de estilo que "pisca"
      -- a tela ao fechar -- e e desnecessario (o gameRoot ja fica no fundo). Ao abrir o
      -- raise e do window (pequeno), por isso so piscava ao fechar.
      root:focus()
    end
  end, 50)
end

local function closeMainTaskWindow()
  if confirmWindow then
    confirmWindow:destroy()
    confirmWindow = nil
  end
  if autoRenewConfirmWindow then
    autoRenewConfirmWindow:destroy()
    autoRenewConfirmWindow = nil
  end
  autoRenewPendingEnable = nil
  if taskPayConfirmWindow then
    taskPayConfirmWindow:destroy()
    taskPayConfirmWindow = nil
  end
  pendingPayTaskId = nil
  if shopBuyConfirmWindow then
    shopBuyConfirmWindow:destroy()
    shopBuyConfirmWindow = nil
  end
  pendingShopBuy = nil

  if boostRewardConfirmWindow then
    boostRewardConfirmWindow:destroy()
    boostRewardConfirmWindow = nil
  end

  if not window or not window:isVisible() then return end
  resetWindowState()
  window:hide()
  focusGameRoot()
end

-- DEMO: agenda injecao de mock state ~1.5s apos abrir, se nada do server chegou.
local function scheduleDemoState()
  if not DEMO_MODE then return end
  if demoApplied or serverDataSeen then return end
  if demoEvent then return end
  demoEvent = scheduleEvent(function()
    demoEvent = nil
    if not DEMO_MODE then return end
    if serverDataSeen or demoApplied then return end
    if not window or window:isDestroyed() then return end
    loadDemoState()
  end, 1500)
end

local function openMainTaskWindow()
  if not window then return end
  if window:isVisible() then return end
  window:show()
  window:raise()
  window:focus()
  -- Sem window:lock(): a window e filha do rootWidget, entao lock() chama
  -- rootWidget:lockChild -> setEnabled(false) em TODOS os irmaos (a interface inteira
  -- do jogo) e propaga DisabledState recursivamente pela arvore toda -> a tela "pisca"
  -- e engasga ao abrir/fechar. E um painel de gerenciamento (estilo cyclopedia/market),
  -- nao um modal bloqueante; os confirms internos e que dao lock proprio quando abrem.

  -- Pull a fresh list the first time the user opens the window. The active
  -- list is already in CommandBridge state; only the "all tasks" catalog is
  -- pull-on-demand.
  if not listRequested then
    listRequested = true
    requestTaskList()
  end
  if currentTab == 'shop' then
    requestShopList()
  end

  scheduleDemoState()
end

function toggle()
  if not g_game.isOnline() then return end
  if not window then return end
  if window:isVisible() then closeMainTaskWindow() else openMainTaskWindow() end
end

-- forceCloseButton (sidebutton wiring) calls hide() with DOT notation. Self-less.
function hide()
  closeMainTaskWindow()
end

function onEscape()
  if boostRewardConfirmWindow and not boostRewardConfirmWindow:isDestroyed() and boostRewardConfirmWindow:isVisible() then
    cancelBoostReward()
    return
  end
  if shopBuyConfirmWindow and not shopBuyConfirmWindow:isDestroyed() and shopBuyConfirmWindow:isVisible() then
    cancelShopBuy()
    return
  end
  if taskPayConfirmWindow and not taskPayConfirmWindow:isDestroyed() and taskPayConfirmWindow:isVisible() then
    cancelPayTask()
    return
  end
  if autoRenewConfirmWindow and not autoRenewConfirmWindow:isDestroyed() and autoRenewConfirmWindow:isVisible() then
    cancelAutoRenew()
    return
  end
  if confirmWindow and not confirmWindow:isDestroyed() and confirmWindow:isVisible() then
    closeConfirmModal()
    return
  end
  closeMainTaskWindow()
end

-- ============================================
-- CommandBridge wiring
-- ============================================
local stateHandler        = nil
local taskCompletedHandler = nil
local taskOpenWindowHandler = nil
local taskOpenStoreHandler  = nil

-- ============================================
-- Binary protocol handler (opcode oficial 0xBC TaskKillTick) - DEFERRED.
-- Dormente: o connect existe para forward-compat mas o sinal nunca dispara
-- enquanto nao houver o parser C++ + suporte de server. Full state continua
-- chegando via CommandBridge JSON -> applyTasksState.
-- ============================================

-- onTaskKillTick(ticks)
--   ticks = { { taskId, currentKills, requiredKills, flags }, ... }  -- 1-indexed tuples
local function onTaskKillTick(ticks)
  if type(ticks) ~= 'table' then return end
  if #ticks == 0 then return end

  -- Atualiza so kills das tasks ja conhecidas (full state fornece name/lookType/etc).
  local byId = {}
  for _, t in ipairs(activeTasks) do
    if t.taskId then byId[t.taskId] = t end
  end

  for _, tick in ipairs(ticks) do
    local taskId        = tick[1]
    local currentKills  = tick[2]
    local requiredKills = tick[3]
    local flags         = tick[4]
    local existing = byId[taskId]
    if existing then
      existing.currentKills  = currentKills
      existing.requiredKills = requiredKills
      existing.flags         = flags
    elseif g_logger and g_logger.warning then
      g_logger.warning(string.format('[game_tasks] kill tick para taskId desconhecido %s (current=%s/%s)',
        tostring(taskId), tostring(currentKills), tostring(requiredKills)))
    end
  end

  if updateUI then updateUI() end
end

-- parseTaskKillTick(protocolGame, msg): le o pacote binario 0xBC do hot path de kills
-- e repassa pro onTaskKillTick. Registrado via ProtocolGame.registerOpcode, portanto
-- roda antes do switch C++ e dispensa binding nativo. Layout: ver OPCODE_TASK_KILL_TICK.
local function parseTaskKillTick(protocolGame, msg)
  local ticks = {}
  local count = msg:getU8()
  for _ = 1, count do
    local taskId        = msg:getU32()
    local currentKills  = msg:getU32()
    local requiredKills = msg:getU32()
    local flags         = msg:getU8()
    ticks[#ticks + 1] = { taskId, currentKills, requiredKills, flags }
  end
  onTaskKillTick(ticks)
end

function initCommandBridge()
  if not CommandBridge or not CommandBridge.onState then return end

  stateHandler = function(_full, patch)
    if not patch then return end
    if patch.tasks ~= nil then
      serverDataSeen = true
      applyTasksState(patch.tasks)
    end
  end
  CommandBridge.onState(stateHandler)

  taskCompletedHandler = function(data)
    local name = (data and (data.name or (data.data and data.data.name))) or 'Task'
    showCompletionToast(name)
  end
  if CommandBridge.on then
    CommandBridge.on('task.completed', taskCompletedHandler)
  end

  -- task.openWindow: enviado pelo server quando o player aciona o totem ou usa o Task Portable.
  taskOpenWindowHandler = function(_data)
    if window and window:isVisible() then
      if window.raise then window:raise() end
      if window.focus then window:focus() end
      return
    end
    if toggle then toggle() end
  end
  if CommandBridge.on then
    CommandBridge.on('task.openWindow', taskOpenWindowHandler)
  end

  -- task.openStore: server tells the client to send a non-owner to the Store's Task
  -- Enhancement offer (defense for old clients; the toggle also redirects locally).
  taskOpenStoreHandler = function(_data)
    openTaskEnhancementStore()
  end
  if CommandBridge.on then
    CommandBridge.on('task.openStore', taskOpenStoreHandler)
  end

  -- Binary protocol 0xBC (TaskKillTick): handler Lua via ProtocolGame.registerOpcode
  -- (roda antes do switch C++; sem C++/rebuild). unregister defensivo antes pra
  -- sobreviver a reload de modulo / re-login.
  if ProtocolGame and ProtocolGame.registerOpcode then
    ProtocolGame.unregisterOpcode(OPCODE_TASK_KILL_TICK)
    ProtocolGame.registerOpcode(OPCODE_TASK_KILL_TICK, parseTaskKillTick)
  end
end

function terminateCommandBridge()
  if CommandBridge and stateHandler and CommandBridge.offState then
    CommandBridge.offState(stateHandler)
  end
  if CommandBridge and taskCompletedHandler and CommandBridge.off then
    CommandBridge.off('task.completed', taskCompletedHandler)
  end
  if CommandBridge and taskOpenWindowHandler and CommandBridge.off then
    CommandBridge.off('task.openWindow', taskOpenWindowHandler)
  end
  if CommandBridge and taskOpenStoreHandler and CommandBridge.off then
    CommandBridge.off('task.openStore', taskOpenStoreHandler)
  end
  taskOpenWindowHandler = nil
  taskOpenStoreHandler = nil
  if ProtocolGame and ProtocolGame.unregisterOpcode then
    ProtocolGame.unregisterOpcode(OPCODE_TASK_KILL_TICK)
  end
  stateHandler = nil
  taskCompletedHandler = nil
end

function applyTasksState(tasks)
  if type(tasks) ~= 'table' then return end

  if tasks.active ~= nil then
    activeTasks = tasks.active or {}
  end

  -- allTasks catalog is optional in light pushes; only replace when sent.
  if tasks.allTasks ~= nil then
    allTasks = tasks.allTasks or {}
  end

  -- Scalar stats + history map: only overwrite when the field is present.
  local scalars = {
    'points', 'completedToday', 'completedTotal',
    'killMultiplier', 'expMultiplier', 'tokenMultiplier',
    'renewerFlags', 'renewerEnabled', 'renewerOwned',
    'maxActive', 'boostedRewards', 'boostCost',
    'history',
  }
  for _, key in ipairs(scalars) do
    if tasks[key] ~= nil then taskState[key] = tasks[key] end
  end

  -- Derive booleans from renewerFlags when the server sent only the bitmask.
  if tasks.renewerFlags ~= nil then
    local flags = tonumber(tasks.renewerFlags) or 0
    if tasks.renewerEnabled  == nil then taskState.renewerEnabled  = bandSafe(flags, RENEWER_FLAG_ENABLED) ~= 0 end
    if tasks.renewerOwned    == nil then taskState.renewerOwned    = bandSafe(flags, RENEWER_FLAG_OWNED)   ~= 0 end
  end

  -- Detect task completions even without an explicit task.completed event.
  if lastCompletedTotal ~= nil
     and type(taskState.completedTotal) == 'number'
     and taskState.completedTotal > lastCompletedTotal then
    showCompletionToast()
  end
  if type(taskState.completedTotal) == 'number' then
    lastCompletedTotal = taskState.completedTotal
  end

  updateUI()
end

-- ============================================
-- Demo state (mock for review). Fed through applyTasksState (server path).
-- ============================================
function loadDemoState()
  if demoApplied then return end
  if serverDataSeen then return end
  demoApplied = true

  local demo = {
    points         = 1875,
    completedToday = 4,
    completedTotal = 137,
    killMultiplier = 1,
    expMultiplier  = 1.5,
    tokenMultiplier = 1,
    renewerEnabled = true,
    renewerOwned   = true,
    history = {
      [101] = { dailyToday = 1, totalCompletions = 22, lastCompleted = 0 },
      [201] = { dailyToday = 0, totalCompletions = 9,  lastCompleted = 0 },
      [301] = { dailyToday = 2, totalCompletions = 41, lastCompleted = 0 },
    },
    active = {
      {
        taskId = 1001, name = 'Dragon', taskType = 2, difficulty = 'easy',
        currentKills = 73, requiredKills = 100, startedAt = 1, flags = 0,
        lookType = 34, exp = 250000, taskPoints = 5,
        baseTotal = 100, avgExp = 700, levelPick = 20, levelDeliver = 0,
        races = { 'Dragon' },
        rewardItems = {
          { itemId = 3043, count = 5,  name = 'Crystal Coin' },
          { itemId = 66142, count = 10, name = 'Task Token' },
        },
      },
      {
        taskId = 1002, name = 'Demon', taskType = 2, difficulty = 'hard',
        currentKills = 480, requiredKills = 500, startedAt = 1, flags = 0,
        lookType = 35, exp = 6000000, taskPoints = 25,
        baseTotal = 500, avgExp = 6000, levelPick = 100, levelDeliver = 0,
        races = { 'Demon' },
        rewardItems = {
          { itemId = 3043, count = 25,  name = 'Crystal Coin' },
          { itemId = 3035, count = 100, name = 'Platinum Coin' },
          { itemId = 66142, count = 30, name = 'Task Token' },
        },
      },
      {
        taskId = 1003, name = 'Hydra', taskType = 1, difficulty = 'medium',
        currentKills = 150, requiredKills = 150, startedAt = 1, flags = 0,
        lookType = 121, exp = 900000, taskPoints = 12,
        baseTotal = 150, avgExp = 2200, levelPick = 60, levelDeliver = 0,
        -- Lista longa de proposito: exercita o grid de 3 colunas + scroll.
        races = {
          'Hydra', 'Serpent Spawn', 'Medusa', 'Sea Serpent', 'Young Sea Serpent',
          'Quara Predator', 'Quara Constrictor', 'Quara Mantassin', 'Quara Hydromancer',
          'Quara Pincher', 'Deepling Warrior', 'Deepling Spellsinger', 'Deepling Guard',
          'Deepling Scout', 'Deepling Master Librarian', 'Deepling Elite', 'Deepling Tyrant',
          'Deepling Brawler', 'Northern Pike', 'Calamary', 'Toad', 'Frog', 'Crocodile',
          'Carniphila',
        },
        rewardItems = {
          { itemId = 3043, count = 12, name = 'Crystal Coin' },
          { itemId = 66142, count = 15, name = 'Task Token' },
        },
      },
    },
    allTasks = {
      {
        taskId = 101, id = 101, name = 'Rotworm', type = 2, difficulty = 'easy',
        requiredKills = 200, baseTotal = 200, avgExp = 60, exp = 18000, taskPoints = 3,
        lookType = 26, levelPick = 8, levelDeliver = 0, renewPrice = 1000,
        races = { 'Rotworm', 'Carrion Worm' },
      },
      {
        taskId = 201, id = 201, name = 'Cyclops', type = 2, difficulty = 'easy',
        requiredKills = 300, baseTotal = 300, avgExp = 150, exp = 67500, taskPoints = 5,
        lookType = 22, levelPick = 20, levelDeliver = 0, renewPrice = 2500,
        races = { 'Cyclops', 'Cyclops Drone', 'Cyclops Smith' },
      },
      {
        taskId = 301, id = 301, name = 'Dragon Lord', type = 2, difficulty = 'medium',
        requiredKills = 250, baseTotal = 250, avgExp = 2100, exp = 787500, taskPoints = 12,
        lookType = 39, minBoostLevel = 0, levelPick = 60, levelDeliver = 0, renewPrice = 0,
        races = { 'Dragon Lord' },
      },
      {
        taskId = 401, id = 401, name = 'Hellhound', type = 2, difficulty = 'hard',
        requiredKills = 400, baseTotal = 400, avgExp = 5500, exp = 3300000, taskPoints = 22,
        lookType = 246, minBoostLevel = 50, levelPick = 130, levelDeliver = 0, renewPrice = 0,
        races = { 'Hellhound' },
      },
      {
        taskId = 501, id = 501, name = 'Medusa', type = 1, difficulty = 'medium',
        requiredKills = 220, baseTotal = 220, avgExp = 1800, exp = 594000, taskPoints = 10,
        lookType = 211, levelPick = 80, levelDeliver = 0, renewPrice = 0,
        races = { 'Medusa' },
      },
      {
        taskId = 601, id = 601, name = 'Frost Dragon', type = 2, difficulty = 'hard',
        requiredKills = 350, baseTotal = 350, avgExp = 2400, exp = 1260000, taskPoints = 18,
        lookType = 102, levelPick = 90, levelDeliver = 0, renewPrice = 0,
        races = { 'Frost Dragon' },
      },
    },
  }

  applyTasksState(demo)

  -- Mock shop entries (the shop normally comes via request/response).
  shopItems = {
    { itemId = 3043, name = 'Crystal Coin',   price = 50, currencyId = 66142, currencyName = 'Task Token' },
    { itemId = 3035, name = 'Platinum Coin',  price = 5,  currencyId = 3043,  currencyName = 'Crystal Token' },
    { itemId = 2160, name = 'Stack of Gold',  price = 1,  currencyId = 3035,  currencyName = 'Platinum Token' },
    { itemId = 60361, name = 'Task Token Bundle', price = 100, currencyId = 66142, currencyName = 'Task Token' },
  }
  if currentTab == 'shop' then updateShopList() end
end

-- ============================================
-- Server requests
-- ============================================
function requestTaskList()
  if not CommandBridge then return end
  CommandBridge.send('task.list', {})
end

-- Detecta se pegar essa task agora vai cobrar gold (segunda+ vez no dia).
local function shouldConfirmPayment(task)
  if not task then return false, 0 end
  local price = tonumber(task.renewPrice) or 0
  if price <= 0 then return false, 0 end
  -- Field names variam entre catalogo (id/type) e slot ativo (taskId/taskType).
  local typeNum = tonumber(task.taskType or task.type)
  if typeNum ~= 2 then return false, 0 end
  local id = task.taskId or task.id
  if not id then return false, 0 end
  -- Precisa ja ter completado hoje (history.dailyToday > 0) pra cobrar.
  local hist = taskState.history and (taskState.history[id] or taskState.history[tostring(id)])
  local dailyToday = hist and tonumber(hist.dailyToday) or 0
  if dailyToday <= 0 then return false, 0 end
  return true, price
end

local function sendStartTask(id)
  if not CommandBridge then return end
  CommandBridge.send('task.start', { taskId = id })
end

function startSelectedTask()
  if not selectedTask then return end
  local id = tonumber(selectedTask.taskId or selectedTask.id or selectedTask.storage)
  if not id then return end

  local snapshot = selectedTask
  debugPrint('[task.start] id:', tostring(id), '| name:', tostring(snapshot.name))

  local needsConfirm, price = shouldConfirmPayment(snapshot)
  if needsConfirm then
    showPayTaskConfirm(id, snapshot.name, price)
    return
  end

  hideDetailsPanel()
  setTab('active')
  sendStartTask(id)
end

function showPayTaskConfirm(taskId, taskName, price)
  if taskPayConfirmWindow then return end

  pendingPayTaskId = taskId
  taskPayConfirmWindow = displayTaskUI('task_pay_confirm')
  if not taskPayConfirmWindow then
    pendingPayTaskId = nil
    return
  end

  local titleLabel = taskPayConfirmWindow:recursiveGetChildById('taskPayConfirmTitle')
  if titleLabel then
    titleLabel:setText('Renew Task')
    titleLabel:setColor('#c0a040')
  end
  local messageLabel = taskPayConfirmWindow:recursiveGetChildById('taskPayConfirmMessage')
  if messageLabel then
    local nameShort = taskName or 'this task'
    messageLabel:setText(string.format(
      'You already did "%s" today.\nRenew now will cost:\n\n%s gold',
      nameShort, formatGold(price)))
  end

  taskPayConfirmWindow:raise()
  taskPayConfirmWindow:focus()
end

local function closePayTaskModal()
  if taskPayConfirmWindow then
    taskPayConfirmWindow:destroy()
    taskPayConfirmWindow = nil
  end
  if window and not window:isDestroyed() then
    window:show()
    window:raise()
    window:focus()
  end
end

function confirmPayTask()
  local id = pendingPayTaskId
  pendingPayTaskId = nil
  closePayTaskModal()
  if not id then return end
  hideDetailsPanel()
  setTab('active')
  sendStartTask(id)
end

function cancelPayTask()
  pendingPayTaskId = nil
  closePayTaskModal()
end

function abortSelectedTask()
  if not selectedTask then return end
  if confirmWindow then return end

  confirmWindow = displayTaskUI('taskconfirm')
  if confirmWindow then
    confirmWindow:raise()
    confirmWindow:focus()
  end
end

function confirmAbortTask()
  closeConfirmModal()
  doAbortTask()
end

function closeConfirmModal()
  if confirmWindow then
    confirmWindow:destroy()
    confirmWindow = nil
  end
  if window and not window:isDestroyed() and window:isVisible() then
    window:raise()
    window:focus()
  end
end

function doAbortTask()
  if not selectedTask then return end
  local id = tonumber(selectedTask.taskId or selectedTask.id or selectedTask.storage)
  if not id then return end

  debugPrint('[task.abort] id:', tostring(id), '| name:', tostring(selectedTask.name))
  if not CommandBridge then return end
  CommandBridge.send('task.abort', { taskId = id })
end

function finishSelectedTask()
  if not selectedTask then return end
  local id = tonumber(selectedTask.taskId or selectedTask.id or selectedTask.storage)
  if not id then return end

  debugPrint('[task.finish] id:', tostring(id), '| name:', tostring(selectedTask.name))
  if not CommandBridge then return end
  CommandBridge.send('task.finish', { taskId = id })
end

-- Legacy lua/OTUI hooks call startTask/abortTask/finishTask; keep aliases.
function startTask()  startSelectedTask()  end
function abortTask()  abortSelectedTask()  end
function finishTask() finishSelectedTask() end

function refresh()
  if currentTab == 'shop' then
    requestShopList()
  else
    requestTaskList()
  end
end

-- ============================================
-- Hunt-token shop (unchanged contract)
-- ============================================
function requestShopList()
  if not CommandBridge then return end
  CommandBridge.request('task.shop.list', {}, function(resp)
    if not resp then return end
    if resp.type == 'error' then
      showMessage(resp.message or 'Failed to load shop.', 'red')
      return
    end
    local data = resp.data or {}
    shopItems = data.items or {}
    if currentTab == 'shop' then updateShopList() end
  end)
end

function buyShopItem(itemId, amount, index)
  if not CommandBridge then return end
  amount = amount or 1
  CommandBridge.request('task.shop.buy', { itemId = itemId, amount = amount, index = index }, function(resp)
    if not resp then return end
    if resp.type == 'error' then
      showMessage(resp.message or 'Purchase failed.', 'red')
      return
    end
    local data = resp.data or {}
    showMessage(data.message or 'Purchased.', 'green')
    updateStats()
  end)
end

-- Abre modal de confirmacao antes de comprar. Evita clique acidental no card.
function showShopBuyConfirm(entry, amount)
  if not entry or not entry.itemId then return end
  if shopBuyConfirmWindow then return end
  amount = tonumber(amount) or 1

  local price = tonumber(entry.price) or 0
  local totalPrice = price * amount
  local currencyId = tonumber(entry.currencyId or entry.tokenId or entry.currencyItemId) or TASK_TOKEN_ID
  local currencyName = entry.currencyName or 'Task Tokens'

  pendingShopBuy = {
    itemId = entry.itemId,
    index  = entry.index,
    name   = entry.name or 'item',
    price  = price,
    amount = amount,
    currencyId = currencyId,
  }

  shopBuyConfirmWindow = displayTaskUI('shop_buy_confirm')
  if not shopBuyConfirmWindow then
    pendingShopBuy = nil
    return
  end

  local titleLabel = shopBuyConfirmWindow:recursiveGetChildById('shopBuyConfirmTitle')
  if titleLabel then
    titleLabel:setText('Confirm Purchase')
    titleLabel:setColor('#c0a040')
  end

  local messageLabel = shopBuyConfirmWindow:recursiveGetChildById('shopBuyConfirmMessage')
  if messageLabel then
    local have = getTokenCount(currencyId)
    local amountText = amount > 1 and string.format('%dx ', amount) or ''
    messageLabel:setText(string.format(
      'Buy %s"%s" for\n\n%s %s?\n\nYou have: %s',
      amountText, pendingShopBuy.name,
      formatNumber(totalPrice), currencyName, formatNumber(have)))
  end

  shopBuyConfirmWindow:raise()
  shopBuyConfirmWindow:focus()
end

local function closeShopBuyModal()
  if shopBuyConfirmWindow then
    shopBuyConfirmWindow:destroy()
    shopBuyConfirmWindow = nil
  end
end

function confirmShopBuy()
  local pending = pendingShopBuy
  pendingShopBuy = nil
  closeShopBuyModal()
  if not pending then return end
  buyShopItem(pending.itemId, pending.amount or 1, pending.index)
end

function cancelShopBuy()
  pendingShopBuy = nil
  closeShopBuyModal()
end

function updateShopList()
  if not window then return end

  local shopList = window:recursiveGetChildById('shopList')
  if not shopList then return end

  shopList:destroyChildren()

  -- Only show offers payable with the active tier's token (common/rare/legendary).
  local tier   = TOKEN_TIERS[currentShopTier]
  local tierId = tier and (tonumber(tier.itemId) or 0) or 0

  for _, entry in ipairs(shopItems) do
    local currencyId = tonumber(entry.currencyId or entry.tokenId or entry.currencyItemId) or TASK_TOKEN_ID
    if tierId == 0 or currencyId == tierId then
      local card = g_ui.createWidget('ShopCard', shopList)
      if card then
        card.shopData = entry

        local itemWidget = card:recursiveGetChildById('item')
        if itemWidget then
          itemWidget:setItemId(entry.itemId)
          itemWidget:setVirtual(true)
          if entry.name then itemWidget:setTooltip(entry.name) end
        end

        local nameLabel = card:recursiveGetChildById('name')
        if nameLabel then nameLabel:setText(entry.name or '') end

        -- Price = "<sprite> N"; the currency is per-entry (entry.currencyId).
        local priceLabel = card:recursiveGetChildById('price')
        if priceLabel then priceLabel:setText(tostring(entry.price)) end

        local priceIcon = card:recursiveGetChildById('priceIcon')
        if priceIcon then
          priceIcon:setItemId(currencyId)
          priceIcon:setVirtual(true)
          priceIcon:setShowCount(false)
          if entry.currencyName then priceIcon:setTooltip(entry.currencyName) end
        end

        local btnBuy = card:recursiveGetChildById('btnBuy')
        if btnBuy then
          btnBuy.onClick = function() showShopBuyConfirm(entry, 1) end
        end
      end
    end
  end
end

-- Shop tier tabs: each tab shows a token tier's sprite + the player's balance and acts
-- as the filter selector for the offer list. Refreshes sprites/counts/on-state.
function updateShopTiers()
  if not window then return end
  for i, tier in ipairs(TOKEN_TIERS) do
    local tab = window:recursiveGetChildById('shopTier' .. i)
    if tab then
      local id = tonumber(tier.itemId) or 0
      local icon = tab:recursiveGetChildById('icon')
      if icon then
        icon:setItemId(id)
        icon:setVirtual(true)
        icon:setShowCount(false)
      end
      local count = tab:recursiveGetChildById('count')
      if count then count:setText(formatNumber(getTokenCount(id))) end
      tab:setTooltip(tier.name or '')
      tab:setOn(i == currentShopTier)
    end
  end
end

-- Switch the visible shop tier (1=common, 2=rare, 3=legendary) and re-filter the offers.
function setShopTier(idx)
  currentShopTier = tonumber(idx) or 1
  updateShopTiers()
  updateShopList()
end

-- ============================================
-- Task tracker mini window
-- ============================================
function createTracker()
  if trackerWindow then
    trackerWindow:destroy()
    trackerWindow = nil
  end

  ensureStyles()  -- 'TaskTracker' lives in tasktracker.otui; guarantee it is registered first
  trackerWindow = g_ui.createWidget('TaskTracker', modules.game_interface.getRightPanel())
  if not trackerWindow then return end

  trackerWindow:setContentMinimumHeight(80)

  local toggleFilterButton = trackerWindow:recursiveGetChildById('toggleFilterButton')
  if toggleFilterButton then toggleFilterButton:setVisible(false) end

  local newWindowButton = trackerWindow:recursiveGetChildById('newWindowButton')
  if newWindowButton then newWindowButton:setVisible(false) end

  local contextMenuButton = trackerWindow:recursiveGetChildById('contextMenuButton')
  local lockButton        = trackerWindow:recursiveGetChildById('lockButton')
  local minimizeButton    = trackerWindow:recursiveGetChildById('minimizeButton')

  if contextMenuButton then contextMenuButton:setVisible(false) end

  if lockButton and minimizeButton then
    lockButton:breakAnchors()
    lockButton:addAnchor(AnchorTop, minimizeButton:getId(), AnchorTop)
    lockButton:addAnchor(AnchorRight, minimizeButton:getId(), AnchorLeft)
    lockButton:setMarginRight(2)
    lockButton:setMarginTop(0)
  end

  trackerWindow:setup()
  trackerWindow:hide()
  trackerVisible = false
end

function onTrackerOpen()
  trackerVisible = true
  updateTracker()
end

function onTrackerClose()
  trackerVisible = false
end

function toggleTracker()
  if not trackerWindow then createTracker() end
  if not trackerWindow then return end

  if trackerWindow:isVisible() then
    trackerWindow:close()
    trackerVisible = false
  else
    trackerWindow:open()
    modules.game_interface.addToPanels(trackerWindow)
    trackerVisible = true
    updateTracker()
  end
end

local function trackerProgress(task)
  local req = tonumber(task.requiredKills or task.kills) or 0
  local cur = tonumber(task.currentKills  or task.done)  or 0
  return cur, req
end

-- getSettings('height') existe na corelib do AMON mas NAO neste client; guard.
local function trackerSavedHeight()
  if trackerWindow and trackerWindow.getSettings then
    return trackerWindow:getSettings('height')
  end
  return nil
end

function updateTracker()
  if not trackerWindow then return end
  local contentsPanel = trackerWindow:recursiveGetChildById('contentsPanel')
  if not contentsPanel then return end

  local taskCount = #activeTasks
  local newSignature = ''
  for _, task in ipairs(activeTasks) do
    newSignature = newSignature .. tostring(task.taskId or '?') .. ':' .. tostring(task.name or '') .. ';'
  end

  local needsRebuild = (newSignature ~= (lastTrackerSignature or ''))

  if needsRebuild then
    contentsPanel:destroyChildren()
    lastTrackerSignature = newSignature

    if taskCount == 0 then
      local emptyLabel = g_ui.createWidget('Label', contentsPanel)
      if emptyLabel then
        emptyLabel:setText('No active tasks')
        emptyLabel:setTextAlign(AlignCenter)
        emptyLabel:setColor('#888888')
        emptyLabel:setHeight(30)
        emptyLabel.onMouseRelease = function(_, _, mouseButton)
          if mouseButton == MouseLeftButton then toggle() return true end
          return false
        end
      end
      if not trackerSavedHeight() then
        trackerWindow:setHeight(80)
      end
      return
    end

    for i, task in ipairs(activeTasks) do
      local entry = g_ui.createWidget('TaskTrackerEntry', contentsPanel)
      if entry then
        entry:setId('trackerEntry' .. i)
        entry.taskData = task
        entry.onMouseRelease = function(_, _, mouseButton)
          if mouseButton == MouseLeftButton then toggle() return true end
          return false
        end

        local creature = entry:recursiveGetChildById('creature')
        if creature and task.lookType then
          creature:setOutfit(buildTaskOutfit(task))
        end

        local nameWidget = entry:recursiveGetChildById('name')
        if nameWidget then
          local taskName = task.name or 'Unknown'
          if #taskName > 18 then
            local cutPos = 16
            while cutPos > 0 and taskName:byte(cutPos) and taskName:byte(cutPos) >= 128 and taskName:byte(cutPos) < 192 do
              cutPos = cutPos - 1
            end
            taskName = taskName:sub(1, cutPos) .. '..'
          end
          nameWidget:setText(taskName)
        end

        local boostedIcon = entry:recursiveGetChildById('boostedIcon')
        if boostedIcon then boostedIcon:setVisible(false) end
      end
    end

    if not trackerSavedHeight() then
      local contentHeight = taskCount * 60 + 10
      trackerWindow:setHeight(math.min(350, math.max(100, contentHeight + 35)))
    end
  end

  for i, task in ipairs(activeTasks) do
    local entry = contentsPanel:getChildById('trackerEntry' .. i)
    if entry then
      entry.taskData = task

      local done, kills = trackerProgress(task)
      local percent = (kills > 0) and math.floor((done / kills) * 100) or 0

      local progressBar = entry:recursiveGetChildById('progressBar')
      if progressBar then
        -- Cor primeiro; setPercent dispara updateBackground (setBackgroundRect) e
        -- precisa rodar por ultimo pra recortar a barra na largura do progresso.
        -- Gold to match the dialog's progress bars (bosstiary-progress skin); the
        -- tracker bar stays flat (no image) so setPercent can still clip it.
        progressBar:setBackgroundColor('#ad7600')
        progressBar:setPercent(math.min(100, percent))
      end

      local progressLabel = entry:recursiveGetChildById('progressLabel')
      if progressLabel then progressLabel:setText(string.format('%d / %d', done, kills)) end
    end
  end
end

-- ============================================
-- Tab + filter controls
-- ============================================
function setTab(tab)
  currentTab = tab
  if not window then return end

  local tabActive = window:recursiveGetChildById('tabActive')
  local tabAll    = window:recursiveGetChildById('tabAll')
  local tabShop   = window:recursiveGetChildById('tabShop')
  if tabActive then tabActive:setOn(tab == 'active') end
  if tabAll    then tabAll:setOn(tab == 'all')       end
  if tabShop   then tabShop:setOn(tab == 'shop')     end

  local isShop = (tab == 'shop')
  local taskList      = window:recursiveGetChildById('taskList')
  local taskListScroll= window:recursiveGetChildById('taskListScroll')
  local searchPanel   = window:recursiveGetChildById('searchPanel')
  local resultsCount  = window:recursiveGetChildById('resultsCount')
  local shopList      = window:recursiveGetChildById('shopList')
  local shopListScroll= window:recursiveGetChildById('shopListScroll')
  local shopTabs      = window:recursiveGetChildById('shopTabs')

  if taskList       then taskList:setVisible(not isShop)       end
  if taskListScroll then taskListScroll:setVisible(not isShop) end
  if searchPanel    then searchPanel:setVisible(not isShop)    end
  if resultsCount   then resultsCount:setVisible(not isShop)   end
  if shopList       then shopList:setVisible(isShop)           end
  if shopListScroll then shopListScroll:setVisible(isShop)     end
  if shopTabs       then shopTabs:setVisible(isShop)           end

  if isShop then
    selectedTask = nil
    local btnStart  = window:recursiveGetChildById('btnStart')
    local btnAbort  = window:recursiveGetChildById('btnAbort')
    local btnFinish = window:recursiveGetChildById('btnFinish')
    if btnStart  then btnStart:setVisible(false)  end
    if btnAbort  then btnAbort:setVisible(false)  end
    if btnFinish then btnFinish:setVisible(false) end
    requestShopList()
    setShopTier(currentShopTier)
  else
    updateTaskList()
  end
end

function updateTabVisibility()
  if not window then return end

  local tabActive = window:recursiveGetChildById('tabActive')
  local tabAll    = window:recursiveGetChildById('tabAll')
  local hasActive = #activeTasks > 0

  if tabActive then tabActive:setVisible(hasActive) end

  if tabAll then
    tabAll:setText('All Tasks')
    if not hasActive then
      tabAll:breakAnchors()
      tabAll:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      tabAll:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    else
      tabAll:breakAnchors()
      tabAll:addAnchor(AnchorLeft, 'tabActive', AnchorRight)
      tabAll:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
      tabAll:setMarginLeft(4)
    end
  end

  if not hasActive and currentTab == 'active' then setTab('all') end
end

function onSearchChange(_, text)
  scheduleEvent(function() filterTaskList(text) end, 100)
end

function filterTaskList(searchText)
  if not window then return end
  local taskList = window:recursiveGetChildById('taskList')
  if not taskList then return end

  searchText = (searchText or ''):lower():trim()

  local visibleCount = 0
  local totalCount = 0

  for _, child in ipairs(taskList:getChildren()) do
    totalCount = totalCount + 1
    if searchText == '' then
      child:show()
      visibleCount = visibleCount + 1
    else
      local found = false
      -- Match por nome da task
      local nameLabel = child:recursiveGetChildById('name')
      if nameLabel and nameLabel:getText():lower():find(searchText, 1, true) then
        found = true
      end
      -- Match por nome de mob (races) - permite buscar "vex" e achar tasks de "Vexclaw"
      if not found and child.taskData and child.taskData.races then
        for _, raceName in ipairs(child.taskData.races) do
          if type(raceName) == 'string' and raceName:lower():find(searchText, 1, true) then
            found = true
            break
          end
        end
      end
      if found then
        child:show()
        visibleCount = visibleCount + 1
      else
        child:hide()
      end
    end
  end

  -- Atualiza contador de resultados.
  local resultsCount = window:recursiveGetChildById('resultsCount')
  if resultsCount then
    if searchText == '' then
      resultsCount:setText(string.format('%d tasks', totalCount))
    else
      resultsCount:setText(string.format('%d / %d', visibleCount, totalCount))
    end
  end
end

function onTaskSelect(_, focusedChild)
  if not focusedChild then
    selectedTask = nil
    hideDetailsPanel()
    return
  end

  local clicked = focusedChild.taskData
  if not clicked then return end

  local list = (currentTab == 'active') and activeTasks or allTasks
  for _, t in ipairs(list) do
    local sameId   = clicked.taskId  and t.taskId  and clicked.taskId  == t.taskId
    local sameName = clicked.name    and t.name    and clicked.name    == t.name
    if sameId or sameName then
      selectedTask = t
      debugPrint('[onTaskSelect]', t.name, 'taskId:', tostring(t.taskId))
      break
    end
  end

  if selectedTask then updateActionButtons() end
end

-- ============================================
-- Render
-- ============================================
-- Re-resolve selectedTask para o objeto vivo apos applyTasksState (que substitui
-- activeTasks/allTasks por novos arrays). Sem isso, updateDetailsPanel usa o
-- snapshot stale e mostra Today/Total/kills desatualizados depois de cada finish.
local function refreshSelectedTaskRef()
  if not selectedTask then return end
  local id = tonumber(selectedTask.taskId or selectedTask.id)
  local name = selectedTask.name
  if id then
    for _, t in ipairs(activeTasks or {}) do
      if tonumber(t.taskId) == id then selectedTask = t; return end
    end
    for _, t in ipairs(allTasks or {}) do
      if tonumber(t.taskId) == id then selectedTask = t; return end
    end
  end
  if name then
    for _, t in ipairs(allTasks or {}) do
      if t.name == name then selectedTask = t; return end
    end
  end
  -- Task sumiu (provavelmente finalizada sem auto-renew e fora do catalogo atual).
  selectedTask = nil
end

function updateUI()
  if window then
    refreshSelectedTaskRef()
    updateTabVisibility()
    updateStats()
    updateTaskList()

    if selectedTask then
      updateDetailsPanel(selectedTask)
      updateActionButtons()
    end
  end

  if trackerWindow and trackerWindow:isVisible() then
    updateTracker()
  end
end

function updateStats()
  if not window then return end

  local activeCountW    = window:recursiveGetChildById('activeCount')
  local completedTodayW = window:recursiveGetChildById('completedToday')

  if activeCountW then
    local count = #activeTasks
    local maxA  = getMaxActiveTasks()
    activeCountW:setText(string.format('Active: %d/%d', count, maxA))
    activeCountW:setColor(count >= maxA and '#ff4444' or '#44aa44')
  end

  -- Today/Total de conclusoes removidos: koliseuot nao tem limite diario/total.
  if completedTodayW then completedTodayW:hide() end

  -- Task Enhancement toggle (server-side "renewer"; renamed in the UI only).
  local autoRenewToggle = window:recursiveGetChildById('autoRenewToggle')
  if autoRenewToggle then
    local enabled = taskState.renewerEnabled == true
    local owned   = taskState.renewerOwned   == true
    local stateLabel = autoRenewToggle:recursiveGetChildById('autoRenewState')
    if stateLabel then
      -- Owners see ON/OFF; non-owners see BUY (clicking routes them to the Store).
      stateLabel:setText(owned and (enabled and 'ON' or 'OFF') or 'BUY')
      stateLabel:setColor(owned and (enabled and '#44aa44' or '#cc4444') or '#c0a040')
    end
    -- Keep the toggle clickable for everyone: non-owners are steered to the Store by
    -- toggleAutoRenew(); disabling it would swallow the click.
    autoRenewToggle:setEnabled(true)
    autoRenewToggle:setTooltip(owned and '' or 'Purchase Task Enhancement on the store to unlock auto-claim.')
  end

  -- Boosted Rewards counter (server: state.tasks.boostedRewards).
  local boostedRewardsW = window:recursiveGetChildById('boostedRewards')
  if boostedRewardsW then
    local n = tonumber(taskState.boostedRewards) or 0
    boostedRewardsW:setText(string.format('Boosted Rewards: %s', formatNumber(n)))
  end

  updateShopTiers()
end

-- Non-owners can't enable Task Enhancement from here -- it's a Store item. Send them to the
-- Store searching straight for the offer (mirrors game_prey/blessing store redirects).
function openTaskEnhancementStore()
  closeMainTaskWindow()
  if g_game.openStore then g_game.openStore() end
  -- 5 == GameStore.ActionType.OPEN_SEARCH; the server fuzzy-matches the offer name.
  if g_game.requestStoreOffers then
    g_game.requestStoreOffers(5, 'Task Enhancement', 0)
  end
end

function toggleAutoRenew()
  if not CommandBridge then return end
  -- Not owned yet: this is a purchasable Store property, so route to the Store to buy it
  -- instead of toggling (the server also rejects a non-owner toggle as a backstop).
  if not (taskState.renewerOwned == true) then
    openTaskEnhancementStore()
    return
  end
  if autoRenewConfirmWindow then return end

  autoRenewPendingEnable = not (taskState.renewerEnabled == true)

  -- Show the confirm OVER the (still visible) main window, like the pay/shop/boost
  -- confirms. Hiding then re-showing the window reset the runtime setColor on the
  -- 'ON' label, leaving it stuck red after Cancel.
  autoRenewConfirmWindow = displayTaskUI('autorenew_confirm')
  if not autoRenewConfirmWindow then
    autoRenewPendingEnable = nil
    return
  end

  local titleLabel  = autoRenewConfirmWindow:recursiveGetChildById('autoRenewConfirmTitle')
  local messageLabel = autoRenewConfirmWindow:recursiveGetChildById('autoRenewConfirmMessage')

  if autoRenewPendingEnable then
    if titleLabel then
      titleLabel:setText('Enable Task Enhancement')
      titleLabel:setColor('#44aa44')
    end
    if messageLabel then
      messageLabel:setText('Do you want to enable Task Enhancement?\nCompleted tasks will be claimed and restarted automatically.')
    end
  else
    if titleLabel then
      titleLabel:setText('Disable Task Enhancement')
      titleLabel:setColor('#cc4444')
    end
    if messageLabel then
      messageLabel:setText('Do you want to disable Task Enhancement?\nYou will need to claim and restart your tasks manually.')
    end
  end

  autoRenewConfirmWindow:raise()
  autoRenewConfirmWindow:focus()
end

local function closeAutoRenewModal()
  if autoRenewConfirmWindow then
    autoRenewConfirmWindow:destroy()
    autoRenewConfirmWindow = nil
  end
  if window and not window:isDestroyed() then
    window:raise()
    window:focus()
    -- Re-sync the Task Enhancement toggle so its 'ON'/'OFF' label keeps the right
    -- color (green/red) after the modal closes, regardless of any style re-apply.
    updateStats()
  end
end

function confirmAutoRenew()
  local wantToEnable = autoRenewPendingEnable
  autoRenewPendingEnable = nil
  closeAutoRenewModal()
  if wantToEnable == nil then return end
  if not CommandBridge then return end
  -- Server e a fonte da verdade: ele valida renewerOwned e responde com novo state.
  CommandBridge.send('task.toggleRenewer', {})
end

function cancelAutoRenew()
  autoRenewPendingEnable = nil
  closeAutoRenewModal()
end

-- Per-character "skip the boost confirm" preference, persisted next to character data.
function loadBoostPref()
  boostSkipConfirm = false
  local player = g_game.getLocalPlayer()
  if not player then return end
  local file = '/characterdata/' .. player:getId() .. '/taskprefs.json'
  if not g_resources.fileExists(file) then return end
  local ok, result = pcall(function() return json.decode(g_resources.readFileContents(file)) end)
  if ok and type(result) == 'table' then
    boostSkipConfirm = result.boostSkipConfirm == true
  end
end

local function saveBoostPref()
  local player = g_game.getLocalPlayer()
  if not player then return end
  pcall(function() g_resources.makeDir('/characterdata') end)
  pcall(function() g_resources.makeDir('/characterdata/' .. player:getId()) end)
  local ok, encoded = pcall(function() return json.encode({ boostSkipConfirm = boostSkipConfirm }, 2) end)
  if ok and encoded then
    pcall(function()
      g_resources.writeFileContents('/characterdata/' .. player:getId() .. '/taskprefs.json', encoded)
    end)
  end
end

local function sendBoostReward()
  if not CommandBridge then return end
  CommandBridge.send('task.boostReward', {})
end

-- Boost Reward: buys 1 HTP boost charge (gold from bank, server-side). Opens a confirm
-- modal unless the player ticked "don't ask again" (then it buys directly). Counter and
-- per-charge cost come from state.tasks.boostedRewards / state.tasks.boostCost.
function boostReward()
  if not CommandBridge then return end
  if boostSkipConfirm then
    sendBoostReward()
    return
  end
  if boostRewardConfirmWindow then return end

  boostRewardConfirmWindow = displayTaskUI('boost_confirm')
  if not boostRewardConfirmWindow then return end

  local messageLabel = boostRewardConfirmWindow:recursiveGetChildById('boostRewardConfirmMessage')
  if messageLabel then
    local n = tonumber(taskState.boostedRewards) or 0
    local cost = tonumber(taskState.boostCost) or 0
    local costText = (cost > 0) and (formatGold(cost) .. ' gold (from bank)') or 'free'
    messageLabel:setText(string.format(
      'Buy 1 reward boost for %s?\n\nDoubles the HTP of your next completed task.\nCurrent charges: %s',
      costText, formatNumber(n)))
  end

  boostRewardConfirmWindow:raise()
  boostRewardConfirmWindow:focus()
end

local function closeBoostRewardModal()
  if boostRewardConfirmWindow then
    boostRewardConfirmWindow:destroy()
    boostRewardConfirmWindow = nil
  end
  if window and not window:isDestroyed() and window:isVisible() then
    window:raise()
    window:focus()
  end
end

function confirmBoostReward()
  -- Honor the "don't ask again" checkbox before tearing the modal down.
  if boostRewardConfirmWindow and not boostRewardConfirmWindow:isDestroyed() then
    local cb = boostRewardConfirmWindow:recursiveGetChildById('boostRewardSkip')
    if cb and cb:isChecked() then
      boostSkipConfirm = true
      saveBoostPref()
    end
  end
  closeBoostRewardModal()
  sendBoostReward()
end

function cancelBoostReward()
  closeBoostRewardModal()
end

function updateTaskList()
  if not window then return end
  local taskList = window:recursiveGetChildById('taskList')
  if not taskList then return end

  -- Cancel any in-flight incremental build before rebuilding from scratch.
  if taskList.buildEvent then
    removeEvent(taskList.buildEvent)
    taskList.buildEvent = nil
  end
  taskList:destroyChildren()

  local tasks = (currentTab == 'active') and activeTasks or allTasks

  local activeNames = {}
  for _, task in ipairs(activeTasks) do
    if task.name then activeNames[task.name] = true end
  end

  -- Pre-filter so the incremental builder only walks the tasks we will render.
  local toRender = {}
  for _, task in ipairs(tasks) do
    if not (currentTab == 'all' and task.name and activeNames[task.name]) then
      toRender[#toRender + 1] = task
    end
  end

  local isActiveTab = (currentTab == 'active')

  -- Build the cards in small chunks across frames. Each TaskCard spins up 3 UICreature
  -- previews (outfit sprite composition) plus a grid relayout; doing the whole catalog
  -- (the "All Tasks" tab can be hundreds of entries) in a single frame hard-freezes the
  -- client the moment the window opens. Chunking keeps every frame cheap.
  local CHUNK = 12
  local index = 1

  local function finishBuild()
    if not window or window:isDestroyed() then return end
    local searchInput = window:recursiveGetChildById('searchInput')
    if searchInput then filterTaskList(searchInput:getText()) end
    -- Active tab is non-selectable (see createTaskCard); only auto-focus elsewhere.
    if not isActiveTab then
      local firstChild = taskList:getFirstChild()
      if firstChild then taskList:focusChild(firstChild) end
    end
  end

  local function buildChunk()
    taskList.buildEvent = nil
    if not window or window:isDestroyed() or taskList:isDestroyed() then return end
    local stop = math.min(index + CHUNK - 1, #toRender)
    for i = index, stop do
      local card = createTaskCard(toRender[i])
      if card then taskList:addChild(card) end
    end
    index = stop + 1
    if index <= #toRender then
      taskList.buildEvent = scheduleEvent(buildChunk, 1)
    else
      finishBuild()
    end
  end

  buildChunk()
end

local function isTaskActive(task)
  if not task then return false end
  if task.isActive then return true end
  -- Fonte de verdade: a task esta na lista de tasks ativas do servidor (por id ou nome).
  -- NAO depende de kills/startedAt -- uma task recem-pega tem 0 kills e ja esta ativa.
  local id = task.taskId or task.id
  for _, a in ipairs(activeTasks) do
    if (id and (a.taskId == id or a.id == id)) or (task.name and a.name == task.name) then
      return true
    end
  end
  return false
end

function createTaskCard(task)
  -- Active tab: cards highlight on hover only (no selected/focus style).
  local cardStyle = (currentTab == 'active') and 'TaskCardActive' or 'TaskCard'
  local card = g_ui.createWidget(cardStyle)
  if not card then return nil end

  card.taskData = task

  -- Active tab: clicking a card must NOT select/focus it (selecting an active card
  -- glitches the card styling). Selection there happens only via the Details button.
  if currentTab == 'active' then
    card:setFocusable(false)
  end

  local btnDetails = card:recursiveGetChildById('btnDetails')
  if btnDetails then
    btnDetails.onClick = function()
      local tl = window:recursiveGetChildById('taskList')
      if tl and card:isFocusable() then tl:focusChild(card) end
      selectedTask = task
      showDetailsPanel()
      updateDetailsPanel(task)
      updateDetailActionButtons()
    end
  end

  -- Up to 3 overlapping creature previews ("rank"), a random sample of the task's
  -- monsters (slot 1 = center/front, 2 = back-left, 3 = back-right). Unused = hidden.
  local previews = resolveTaskPreviewOutfits(task, 3)
  local creatureSlots = {
    card:recursiveGetChildById('creature'),
    card:recursiveGetChildById('creatureBack1'),
    card:recursiveGetChildById('creatureBack2'),
  }
  for i, slot in ipairs(creatureSlots) do
    if slot then
      local o = previews[i]
      if o then
        slot:setOutfit(o)
        if slot.setStaticWalking then slot:setStaticWalking(true) end
        slot:show()
      else
        slot:hide()
      end
    end
  end

  local nameWidget = card:recursiveGetChildById('name')
  if nameWidget then nameWidget:setText(task.name or 'Unknown') end

  local boostedBadge = card:recursiveGetChildById('boostedBadge')
  if boostedBadge then
    local hasBoost = (tonumber(task.minBoostLevel) or 0) > 0
    boostedBadge:setVisible(hasBoost)
  end

  local typeLabel = card:recursiveGetChildById('typeLabel')
  if typeLabel then
    local rawType = task.taskType or task.type
    typeLabel:setVisible(rawType ~= nil)
    if rawType then typeLabel:setText(TYPE_LABELS[rawType] or tostring(rawType)) end
  end

  local progressBar  = card:recursiveGetChildById('progressBar')
  local progressLabel = card:recursiveGetChildById('progressLabel')

  local req = tonumber(task.requiredKills or task.kills) or 0
  local cur = tonumber(task.currentKills  or task.done)  or 0
  local active = isTaskActive(task)
  local maxWidth = 212

  if active then
    local percent = (req > 0) and (cur / req) or 0
    local barWidth = math.floor(maxWidth * math.min(1, percent))
    if progressBar then
      progressBar:setWidth(barWidth)
      progressBar:setBackgroundColor((cur >= req and req > 0) and '#44aa44' or '#4444aa')
    end
    if progressLabel then progressLabel:setText(string.format('%d/%d', cur, req)) end
  else
    if progressBar then
      progressBar:setWidth(0)
      progressBar:setBackgroundColor('#888888')
    end
    if progressLabel then progressLabel:setText(string.format('0/%d', req)) end
  end

  local rewardLabel = card:recursiveGetChildById('rewardLabel')
  if rewardLabel then
    local rewards = {}
    if task.exp and task.exp > 0 then rewards[#rewards + 1] = formatNumber(task.exp) .. ' exp' end
    rewardLabel:setText(#rewards > 0 and table.concat(rewards, ' + ') or '')
  end

  return card
end

local function setMainContentVisible(visible)
  if not window then return end
  for _, id in ipairs({ 'statsRow', 'topSeparator', 'header', 'resultsCount', 'taskList', 'taskListScroll', 'bottomSeparator', 'footer' }) do
    local w = window:recursiveGetChildById(id)
    if w then w:setVisible(visible) end
  end
end

function showDetailsPanel()
  if not window then return end
  setMainContentVisible(false)
  local detailsPanel = window:recursiveGetChildById('detailsPanel')
  if detailsPanel then detailsPanel:show() end
end

function hideDetailsPanel()
  if not window then return end
  local detailsPanel = window:recursiveGetChildById('detailsPanel')
  if detailsPanel then detailsPanel:hide() end
  setMainContentVisible(true)
end

function updateDetailActionButtons()
  if not window or not selectedTask then return end
  local detailsPanel = window:recursiveGetChildById('detailsPanel')
  if not detailsPanel then return end

  local btnStart  = detailsPanel:recursiveGetChildById('detailBtnStart')
  local btnAbort  = detailsPanel:recursiveGetChildById('detailBtnAbort')
  local btnFinish = detailsPanel:recursiveGetChildById('detailBtnFinish')

  local req = tonumber(selectedTask.requiredKills or selectedTask.kills) or 0
  local cur = tonumber(selectedTask.currentKills  or selectedTask.done)  or 0
  local active   = isTaskActive(selectedTask)
  local complete = active and req > 0 and cur >= req

  if btnStart  then
    btnStart:setVisible(not active)
    local maxA    = getMaxActiveTasks()
    local atLimit = #activeTasks >= maxA
    btnStart:setEnabled(not atLimit)
    btnStart:setTooltip(atLimit
      and string.format('You can only have %d active tasks at the same time.', maxA)
      or '')
  end
  if btnAbort  then btnAbort:setVisible(active) end  -- Abort = task ativa (independe de kills)
  if btnFinish then btnFinish:setVisible(complete) end
end

function updateDetailsPanel(task)
  if not window or not task then return end
  local detailsPanel = window:recursiveGetChildById('detailsPanel')
  if not detailsPanel then return end

  -- 1) Creature preview: ate 3 previews sobrepostos (rank), igual aos cards.
  local previews = resolveTaskPreviewOutfits(task, 3)
  local detailSlots = {
    detailsPanel:recursiveGetChildById('detailCreature'),
    detailsPanel:recursiveGetChildById('detailCreatureBack1'),
    detailsPanel:recursiveGetChildById('detailCreatureBack2'),
  }
  for i, slot in ipairs(detailSlots) do
    if slot then
      local o = previews[i]
      if o then
        slot:setOutfit(o)
        if slot.setStaticWalking then slot:setStaticWalking(true) end
        slot:show()
      else
        slot:hide()
      end
    end
  end

  -- 2) Nome da task
  local detailName = detailsPanel:recursiveGetChildById('detailName')
  if detailName then
    detailName:setText(task.name or 'Unknown Task')
    detailName:setColor('#c0c0c0')
  end

  -- 3) Type: "Repeatable"
  local detailType = detailsPanel:recursiveGetChildById('detailType')
  if detailType then
    detailType:setText(formatTaskTypeLabel(task))
    detailType:setColor('#808080')
    detailType:show()
  end

  -- 4) Boosted level (legacy/futuro - escondido)
  local detailBoostedLevel = detailsPanel:recursiveGetChildById('detailBoostedLevel')
  if detailBoostedLevel then detailBoostedLevel:setVisible(false) end

  -- 5) Min level to pick
  local detailLevelPick = detailsPanel:recursiveGetChildById('detailLevelPick')
  if detailLevelPick then
    local lp = tonumber(task.levelPick) or 0
    if lp > 0 then
      detailLevelPick:setText(string.format('Min level to pick: %d', lp))
      detailLevelPick:setColor('#c0c0c0')
      detailLevelPick:show()
    else
      detailLevelPick:hide()
    end
  end

  -- 6) Min level to deliver
  local detailLevelDeliver = detailsPanel:recursiveGetChildById('detailLevelDeliver')
  if detailLevelDeliver then
    local ld = tonumber(task.levelDeliver) or 0
    if ld > 0 then
      detailLevelDeliver:setText(string.format('Min level to deliver: %d', ld))
      detailLevelDeliver:setColor('#c0c0c0')
      detailLevelDeliver:show()
    else
      detailLevelDeliver:hide()
    end
  end

  -- 7) Progress / Required kills
  local detailProgress = detailsPanel:recursiveGetChildById('detailProgress')
  if detailProgress then
    local req = tonumber(task.requiredKills or task.baseTotal or task.kills) or 0
    local cur = tonumber(task.currentKills or task.done) or 0
    if isTaskActive(task) then
      local percent = req > 0 and math.floor((cur / req) * 100) or 0
      detailProgress:setText(string.format('Progress: %d/%d (%d%%)', cur, req, percent))
    else
      detailProgress:setText(string.format('Required kills: %d', req))
    end
    detailProgress:setColor('#c0c0c0')
    detailProgress:show()
  end

  -- 8) Today/Total por-task removido: sem limite diario/total no servidor koliseuot.
  local detailCompletions = detailsPanel:recursiveGetChildById('detailCompletions')
  if detailCompletions then detailCompletions:hide() end

  -- 9) Reward: exp + task points. Usa os campos diretos do server (exp/taskPoints);
  -- so cai no calculo baseTotal*avgExp quando o server nao mandou o exp pronto (senao
  -- dava 0 e escondia a recompensa inteira).
  local detailReward = detailsPanel:recursiveGetChildById('detailReward')
  if detailReward then
    local parts = {}
    local exp = tonumber(task.exp) or 0
    if exp == 0 then
      local baseTotal = tonumber(task.baseTotal) or 0
      local avgExp = tonumber(task.avgExp) or 0
      local expMult = tonumber(taskState.expMultiplier) or 1
      exp = math.floor(baseTotal * avgExp * expMult)
    end
    if exp > 0 then
      parts[#parts + 1] = formatNumber(exp) .. ' exp'
    end
    local pts = tonumber(task.taskPoints) or 0
    if pts > 0 then
      parts[#parts + 1] = formatNumber(pts) .. ' HTPs'
    end
    if #parts > 0 then
      detailReward:setText('Reward: ' .. table.concat(parts, ' + '))
      detailReward:setColor('#daa520') -- gold accent (matching AMON theme)
      detailReward:show()
    else
      detailReward:hide()
    end
  end

  -- 10) Lista de Creatures (races): grid de labels com nome dos monstros.
  local detailMobsTitle = detailsPanel:recursiveGetChildById('detailMobsTitle')
  local detailMobsGrid  = detailsPanel:recursiveGetChildById('detailMobsGrid')
  if detailMobsGrid then
    detailMobsGrid:destroyChildren()
    local races = task.races or {}
    if #races > 0 then
      if detailMobsTitle then
        detailMobsTitle:setText('Creatures:')
        detailMobsTitle:setColor('#c0c0c0')
        detailMobsTitle:show()
      end
      detailMobsGrid:show()
      for _, raceName in ipairs(races) do
        -- MobEntry = boxed Label (dark fill + 1px border); 3-col grid, scrollable.
        local entry = g_ui.createWidget('MobEntry', detailMobsGrid)
        if entry then
          entry:setText(tostring(raceName))
        end
      end
    else
      if detailMobsTitle then detailMobsTitle:hide() end
      detailMobsGrid:hide()
    end
  end

  -- 11) Cost (legacy - escondido).
  local detailCost = detailsPanel:recursiveGetChildById('detailCost')
  if detailCost then detailCost:hide() end

  -- 12) Rewards: item sprite + qty (count badge) + name. Server envia
  -- task.rewardItems = { { itemId/id, count/amount, name }, ... }. Esconde
  -- quando vazio (inert ate o server mandar a lista).
  local detailRewardsTitle = detailsPanel:recursiveGetChildById('detailRewardsTitle')
  local detailRewardsList  = detailsPanel:recursiveGetChildById('detailRewardsList')
  if detailRewardsList then
    detailRewardsList:destroyChildren()
    local rewards = task.rewardItems or task.rewards or {}
    if #rewards > 0 then
      if detailRewardsTitle then detailRewardsTitle:show() end
      detailRewardsList:show()
      for _, reward in ipairs(rewards) do
        local itemId = tonumber(reward.itemId or reward.id) or 0
        local count  = tonumber(reward.count or reward.amount) or 1
        local chip = g_ui.createWidget('RewardEntry', detailRewardsList)
        if chip then
          local itemWidget = chip:recursiveGetChildById('item')
          if itemWidget and itemId > 0 then
            itemWidget:setItemId(itemId)
            itemWidget:setVirtual(true)
            itemWidget:setItemCount(count)
            itemWidget:setShowCountAlways(count > 1)
            if reward.name then itemWidget:setTooltip(reward.name) end
          end
        end
      end
    else
      if detailRewardsTitle then detailRewardsTitle:hide() end
      detailRewardsList:hide()
    end
  end
end

function updateActionButtons()
  if not window or not selectedTask then return end

  local btnStart  = window:recursiveGetChildById('btnStart')
  local btnAbort  = window:recursiveGetChildById('btnAbort')
  local btnFinish = window:recursiveGetChildById('btnFinish')

  local req = tonumber(selectedTask.requiredKills or selectedTask.kills) or 0
  local cur = tonumber(selectedTask.currentKills  or selectedTask.done)  or 0
  local active   = isTaskActive(selectedTask)
  local complete = active and req > 0 and cur >= req

  if btnStart  then
    btnStart:setVisible(not active)
    local maxA    = getMaxActiveTasks()
    local atLimit = #activeTasks >= maxA
    btnStart:setEnabled(not atLimit)
    btnStart:setTooltip(atLimit
      and string.format('You can only have %d active tasks at the same time.', maxA)
      or '')
  end
  if btnAbort  then btnAbort:setVisible(active) end  -- Abort = task ativa (independe de kills)
  if btnFinish then btnFinish:setVisible(complete) end

  updateDetailActionButtons()
end

function showMessage(text, color)
  if not window then return end
  local messageLabel = window:recursiveGetChildById('messageLabel')
  if not messageLabel then return end

  color = color or 'white'
  messageLabel:setText(text or '')
  messageLabel:setColor(color)

  if messageEvent then removeEvent(messageEvent) end
  messageEvent = scheduleEvent(function()
    if messageLabel and not messageLabel:isDestroyed() then
      messageLabel:setText('')
    end
    messageEvent = nil
  end, 5000)
end

-- ============================================
-- Completion toast
-- ============================================
function showCompletionToast(taskName)
  local headline = 'Task completed!'
  local detail   = taskName and ('Reward claimed: ' .. taskName) or nil

  -- Mensagem central via game_textmessage (sobrevive destroy/restore do modulo).
  if modules.game_textmessage and modules.game_textmessage.displayGameMessage then
    modules.game_textmessage.displayGameMessage(headline)
  end

  -- Also echo into the in-window status line if the player has it open.
  showMessage(detail or headline, 'green')

  -- Soft sound effect (optional). Guarded.
  pcall(function()
    if g_sounds and g_sounds.getChannel and modules.game_sounds then
      -- intentionally no-op stub: server already plays sound; client side soft
    end
  end)
end

-- ============================================
-- Utility
-- ============================================
-- Count a given item id anywhere (server inventory cache + open containers).
function getTokenCount(id)
  id = tonumber(id) or 0
  if id <= 0 then return 0 end
  if modules.game_helper and modules.game_helper.getItemCountAnywhere then
    return modules.game_helper.getItemCountAnywhere(id) or 0
  end
  local player = g_game.getLocalPlayer()
  if not player then return 0 end
  if player.getInventoryCount then
    local ok, result = pcall(player.getInventoryCount, player, id, 0)
    if ok and type(result) == 'number' then return result end
  end
  if player.getItemsCount then
    local ok, result = pcall(player.getItemsCount, player, id)
    if ok and type(result) == 'number' then return result end
  end
  return 0
end

function getTaskTokenCount()
  return getTokenCount(TASK_TOKEN_ID)
end

function formatNumber(num)
  if not num then return '0' end
  local formatted = tostring(num)
  local k = formatted:len()
  while k > 3 do
    k = k - 3
    formatted = formatted:sub(1, k) .. ',' .. formatted:sub(k + 1)
  end
  return formatted
end

-- Formata gold com ponto como separador de milhar (pt-BR: 1.000.000).
function formatGold(num)
  if not num then return '0' end
  local n = tonumber(num) or 0
  local sign = ''
  if n < 0 then sign = '-'; n = -n end
  local formatted = tostring(math.floor(n))
  local k = formatted:len()
  while k > 3 do
    k = k - 3
    formatted = formatted:sub(1, k) .. '.' .. formatted:sub(k + 1)
  end
  return sign .. formatted
end
