-- CaveBot Core Module
-- Loop principal baseado na referência game_bot
-- Usa macro(20ms) para processamento de ações

CaveBot = CaveBot or {}

-- ============================================================================
-- ESTADO INTERNO
-- ============================================================================

local cavebotMacro = nil
local actionRetries = 0
local prevActionResult = true
local isEnabled = false
local isPaused = false
local currentActionIndex = 1
local actionList = {}  -- Lista de ações {action, value}
local macroDelay = 0
local walkerCallbacks = nil

-- Throttle do aviso "gotoLabel: label nao encontrada": um waypoint script/
-- function preso em "retry" chamaria gotoLabel a ~50Hz; sem isto o CavebotLog
-- floodaria (e dispararia refreshCavebotLogUI no mesmo ritmo). So reloga quando
-- a label alvo muda ou passa o intervalo.
local lastGotoMissLabel = nil
local lastGotoMissTime = 0
local GOTO_MISS_LOG_INTERVAL = 3000  -- ms

-- ============================================================================
-- LURE STATE FLAGS (escritos pelos loops lentos, lidos pelo loop rápido)
-- ============================================================================

local CREATURE_LOOP_INTERVAL = 100  -- ms
local TRAP_LOOP_INTERVAL = 200      -- ms
local LURE_LOOP_INTERVAL = 100      -- ms

local lureState = {
  -- Set por creatureLoop
  shouldStop = false,
  creatureCount = 0,
  -- Set por trapLoop
  isTrapped = false,
  avoidObstacles = 0,
  -- One-shot: trap loop sets this to release shouldWait for a single
  -- main-loop tick so the active action takes its natural step.
  releaseWait = false,
  -- Set por lureLoop
  shouldWait = false,
  -- Event handles para cleanup
  creatureEvent = nil,
  trapEvent = nil,
  lureEvent = nil,
  -- Guards de re-entrada
  creatureRunning = false,
  trapRunning = false,
  lureRunning = false,
}

-- ============================================================================
-- FUNÇÕES INTERNAS
-- ============================================================================

local function getCurrentAction()
  if #actionList == 0 then return nil end
  if currentActionIndex < 1 or currentActionIndex > #actionList then
    currentActionIndex = 1
  end
  return actionList[currentActionIndex]
end

local function advanceAction()
  currentActionIndex = currentActionIndex + 1
  if currentActionIndex > #actionList then
    currentActionIndex = 1
    -- When the waypoint list wraps, the previous action's walk-step delay
    -- (walkDelay + stepDuration from the final walkTo) is still pending —
    -- it would block mainLoop for up to ~250ms before the new WP1 could
    -- even be evaluated, surfacing as a visible "Processing" pause. Clear
    -- it so the new loop iteration starts immediately; walkTo/doWalking
    -- still gate actual packet emission via the player's own walk state.
    macroDelay = 0
  end
  actionRetries = 0
  prevActionResult = true

  -- Notify UI that waypoint changed
  if walkerCallbacks and walkerCallbacks.onWaypointChanged then
    walkerCallbacks.onWaypointChanged(currentActionIndex)
  end
end

-- Actions that intentionally hold the player in place (combat, NPC trade,
-- waiting stamina, deposit, etc). While one of these is the current action,
-- we mark the main walker as "blocking" so its prolonged-stuck detector and
-- no-step watchdog don't false-trigger and reroute the path.
local blockingActionTypes = {
  stop_to_kill = true,
  wait_lure = true,
  deposit = true,
  withdraw = true,
}

local function processAction()
  local currentAction = getCurrentAction()
  if not currentAction then return end

  local action = CaveBot.Actions[currentAction.action:lower()]
  if not action then
    error("Invalid cavebot action: " .. currentAction.action)
    advanceAction()
    return
  end

  local actionName = currentAction.action:lower()
  local isBlocking = blockingActionTypes[actionName] == true
  if isBlocking and cavebotWalker and cavebotWalker.markBlocking then
    cavebotWalker.markBlocking(actionName)
  end

  -- Índice antes do callback: um salto EXPLÍCITO de waypoint disparado de dentro
  -- da ação (gotoLabel/gotoIndex — via a ação "gotolabel", o CaveBot.GoTo do
  -- scripting, o gotoLabel injetado em script/function, ou o fallback do
  -- Z-recovery) reposiciona o cursor durante a chamada. Precisamos detectá-lo
  -- para NÃO deixar o avanço/retry normal atropelar o salto.
  local indexBefore = currentActionIndex

  local status, result = pcall(function()
    CaveBot.resetWalking()
    return action.callback(currentAction.value, actionRetries, prevActionResult)
  end)

  -- Salto explícito tem precedência sobre o fluxo normal: se o callback moveu o
  -- cursor, respeitar o novo índice em vez de avançar/retryar. Sem isto, um
  -- advanceAction() pularia para "label+1" (perdendo a própria label) e um retorno
  -- "retry" prenderia o cursor na ação já abandonada — era por isso que o
  -- CaveBot.GoTo dentro de um waypoint script/function não parava na label.
  -- O gotoLabel/gotoIndex já notificaram a UI (onWaypointChanged).
  if currentActionIndex ~= indexBefore then
    actionRetries = 0
    prevActionResult = true
    if isBlocking and cavebotWalker and cavebotWalker.unmarkBlocking then
      cavebotWalker.unmarkBlocking()
    end
    if not status then
      error("Error while executing cavebot action (" .. currentAction.action .. "):\n" .. tostring(result))
    end
    return
  end

  if status then
    if result == "retry" then
      actionRetries = actionRetries + 1
    elseif type(result) == "boolean" then
      actionRetries = 0
      prevActionResult = result
      if isBlocking and cavebotWalker and cavebotWalker.unmarkBlocking then
        cavebotWalker.unmarkBlocking()
      end
      advanceAction()
    else
      error("Invalid return from cavebot action (" .. currentAction.action .. "), should be 'retry', false or true, is: " .. tostring(result))
    end
  else
    if isBlocking and cavebotWalker and cavebotWalker.unmarkBlocking then
      cavebotWalker.unmarkBlocking()
    end
    error("Error while executing cavebot action (" .. currentAction.action .. "):\n" .. tostring(result))
    advanceAction()
  end
end

-- ============================================================================
-- HELPERS INTERNOS PARA LOOPS
-- ============================================================================

-- Parseia posição x,y,z do valor de uma ação
local function parseActionPos(actionValue)
  if not actionValue then return nil end
  local x, y, z = actionValue:match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
  if x then
    return {x = tonumber(x), y = tonumber(y), z = tonumber(z)}
  end
  return nil
end

-- Verifica se o waypoint atual é stop_to_kill e se o player está na posição exata
local function getStopToKillState()
  local curAction = getCurrentAction()
  if not curAction then return false, false end
  local isStopToKillWp = curAction.action:lower() == "stop_to_kill"
  if not isStopToKillWp then return false, false end

  local isAtPos = false
  local player = g_game.getLocalPlayer()
  if player and curAction.value then
    local pos = parseActionPos(curAction.value)
    if pos then
      local pp = player:getPosition()
      if pp and pp.x == pos.x and pp.y == pos.y and pp.z == pos.z then
        isAtPos = true
      end
    end
  end
  return isStopToKillWp, isAtPos
end

-- ============================================================================
-- LOOPS LENTOS (eventos independentes com guard de re-entrada)
-- ============================================================================

-- CREATURE LOOP (~100ms): shouldStopForCreatures + getCreatureCount
local function creatureLoop()
  if not isEnabled or isPaused then return end
  if lureState.creatureRunning then return end
  lureState.creatureRunning = true

  local lure = CaveBot.Extensions.lure
  if lure then
    -- Scan once: a mesma contagem SEM filtro de waypoint dirige tanto
    -- shouldStopForCreatures quanto o HUD. Evita dois scans C++ idênticos
    -- por tick (10Hz durante hunt). Passa o valor pré-computado adiante.
    local creatureCount = nil
    if lure.getCreatureCount then
      creatureCount = lure.getCreatureCount(nil, nil, nil, false) or 0
      lureState.creatureCount = creatureCount
    end

    -- Verificar creatures para parar (skip se stop_to_kill)
    local isStopToKillWp = getStopToKillState()
    if not isStopToKillWp and lure.shouldStopForCreatures then
      lureState.shouldStop = lure.shouldStopForCreatures(creatureCount)
    else
      lureState.shouldStop = false
    end
  else
    lureState.shouldStop = false
    lureState.creatureCount = 0
  end

  lureState.creatureRunning = false
  if isEnabled then
    lureState.creatureEvent = scheduleEvent(creatureLoop, CREATURE_LOOP_INTERVAL)
  end
end

-- TRAP LOOP (~200ms): only runs while lure mode is waiting for creatures.
-- Avoid trap is a release-the-wait safety valve INSIDE lure mode: if the
-- player is stopped luring and gets cornered, raise `releaseWait` so the
-- main loop unblocks for one tick and the active action (goto/node/...)
-- takes its natural step toward the next WP. We never emit our own walk.
local function trapLoop()
  if not isEnabled or isPaused then return end
  if lureState.trapRunning then return end
  lureState.trapRunning = true

  lureState.isTrapped = false
  lureState.avoidObstacles = 0

  local lure = CaveBot.Extensions.lure
  local player = g_game.getLocalPlayer()

  -- Gate: lure mode ON, avoid trap ON, currently in lure-wait state.
  -- Outside this combination the avoid is a no-op.
  if player and lure
     and CaveBot.Config.get("lureMode")
     and CaveBot.Config.get("avoidTrap")
     and lureState.shouldWait
     and lure.isPlayerTrapped then
    local _, isAtStopToKillPos = getStopToKillState()

    if not isAtStopToKillPos then
      local trapped, obstacles = lure.isPlayerTrapped()
      lureState.isTrapped = trapped or false
      lureState.avoidObstacles = obstacles or 0
      if trapped then
        lureState.releaseWait = true
      end
    end
  end

  lureState.trapRunning = false
  if isEnabled then
    lureState.trapEvent = scheduleEvent(trapLoop, TRAP_LOOP_INTERVAL)
  end
end

-- LURE LOOP (~100ms): shouldWaitLure
local function lureLoop()
  if not isEnabled or isPaused then return end
  if lureState.lureRunning then return end
  lureState.lureRunning = true

  lureState.shouldWait = false

  local lure = CaveBot.Extensions.lure
  local player = g_game.getLocalPlayer()

  if player and lure and CaveBot.Config.get("lureMode") and lure.shouldWaitLure then
    local _, isAtStopToKillPos = getStopToKillState()

    if not isAtStopToKillPos then
      local targetPos = parseActionPos(getCurrentAction() and getCurrentAction().value)
      lureState.shouldWait = lure.shouldWaitLure(targetPos) or false
    end
  end

  lureState.lureRunning = false
  if isEnabled then
    lureState.lureEvent = scheduleEvent(lureLoop, LURE_LOOP_INTERVAL)
  end
end

-- ============================================================================
-- START / STOP SLOW LOOPS
-- ============================================================================

local function stopSlowLoops()
  if lureState.creatureEvent then
    removeEvent(lureState.creatureEvent)
    lureState.creatureEvent = nil
  end
  if lureState.trapEvent then
    removeEvent(lureState.trapEvent)
    lureState.trapEvent = nil
  end
  if lureState.lureEvent then
    removeEvent(lureState.lureEvent)
    lureState.lureEvent = nil
  end

  -- Reset flags
  lureState.shouldStop = false
  lureState.creatureCount = 0
  lureState.isTrapped = false
  lureState.releaseWait = false
  lureState.avoidObstacles = 0
  lureState.shouldWait = false
  lureState.creatureRunning = false
  lureState.trapRunning = false
  lureState.lureRunning = false
end

local function startSlowLoops()
  stopSlowLoops()

  if CaveBot.Extensions.lure then
    lureState.creatureEvent = scheduleEvent(creatureLoop, CREATURE_LOOP_INTERVAL)
    lureState.trapEvent = scheduleEvent(trapLoop, TRAP_LOOP_INTERVAL)
    lureState.lureEvent = scheduleEvent(lureLoop, LURE_LOOP_INTERVAL)
  end
end

-- ============================================================================
-- HEARTBEAT (diagnostic log every N seconds while cavebot is on, so the user
-- has a continuous "I'm alive" signal in CavebotLog even when the hunt is
-- just walking through gotos and not hitting any of the special WPs that
-- emit their own log entries).
-- ============================================================================

local HEARTBEAT_INTERVAL = 30000
local heartbeatEvent = nil

local function emitHeartbeatLog()
  if not CaveBot.log then return end
  local cur = getCurrentAction()
  if not cur then
    CaveBot.log(string.format("Heartbeat - no current WP (list size %d)", #actionList), "info")
    return
  end
  local val = tostring(cur.value or "")
  if #val > 40 then val = val:sub(1, 37) .. "..." end
  local suffix = val ~= "" and (" " .. val) or ""
  CaveBot.log(string.format("Heartbeat - WP %d/%d (%s%s)",
    currentActionIndex, #actionList, tostring(cur.action), suffix), "info")
end

local function heartbeatLoop()
  heartbeatEvent = nil
  if not isEnabled then return end
  emitHeartbeatLog()
  if isEnabled then
    heartbeatEvent = scheduleEvent(heartbeatLoop, HEARTBEAT_INTERVAL)
  end
end

local function startHeartbeat()
  if heartbeatEvent then
    removeEvent(heartbeatEvent)
  end
  heartbeatEvent = scheduleEvent(heartbeatLoop, HEARTBEAT_INTERVAL)
end

local function stopHeartbeat()
  if heartbeatEvent then
    removeEvent(heartbeatEvent)
    heartbeatEvent = nil
  end
end

-- ============================================================================
-- LOOP PRINCIPAL (RÁPIDO - apenas lê flags e processa walking/actions)
-- ============================================================================

local function mainLoop()
  if not isEnabled or isPaused then return end

  -- Auto Blesser hard freeze: never take a step while the safety freeze is on (we died
  -- and are not blessed yet). pause() alone can race with the death/respawn resume and
  -- leak a few residual steps in the temple, so gate the walker here too and drop any
  -- stale path so nothing leaks through until we are blessed again.
  if modules and modules.game_helper and modules.game_helper.isAutoBlesserFreezing
      and modules.game_helper.isAutoBlesserFreezing() then
    CaveBot.resetWalking()
    return
  end

  local player = g_game.getLocalPlayer()
  if not player then return end

  -- Verificar delay
  if macroDelay > 0 and g_clock.millis() < macroDelay then
    return
  end

  -- Verificar TargetBot (trivial, O(1))
  if TargetBot and TargetBot.isActive and TargetBot.isActive() then
    if TargetBot.isCaveBotActionAllowed and not TargetBot.isCaveBotActionAllowed() then
      CaveBot.resetWalking()
      return
    end
  end

  -- Ler flags dos loops lentos (sem chamadas caras aqui)
  if CaveBot.Extensions.lure then
    -- 1. Creature stop (flag do creatureLoop)
    if lureState.shouldStop then
      CaveBot.resetWalking()
      return
    end

    -- 2. Lure wait (flag do lureLoop). The trap loop can raise `releaseWait`
    -- as a one-shot to unblock this gate for a single tick — when consumed,
    -- we fall through to processAction() so the active action takes its
    -- natural step toward the next WP (same as if lure were off).
    if lureState.shouldWait then
      if lureState.releaseWait then
        lureState.releaseWait = false
        -- fall through to walking/action below
      else
        CaveBot.resetWalking()
        CaveBot.delay(20)
        return
      end
    else
      lureState.releaseWait = false
    end
  end

  -- Continuar walking se em andamento (rápido, O(1))
  if CaveBot.doWalking() then
    return
  end

  -- Processar ação atual
  processAction()
end

-- ============================================================================
-- INICIALIZAÇÃO DO MACRO
-- ============================================================================

local function setupMacro()
  if cavebotMacro then return end

  -- Criar macro de 20ms
  if macro then
    cavebotMacro = macro(20, mainLoop)
    cavebotMacro.setOff()
  else
    -- Fallback com scheduleEvent (anti-stacking: só agenda DEPOIS de terminar)
    local function loopWithSchedule()
      if isEnabled then
        mainLoop()
        scheduleEvent(loopWithSchedule, 20)
      end
    end
    cavebotMacro = {
      setOn = function()
        isEnabled = true
        loopWithSchedule()
      end,
      setOff = function()
        isEnabled = false
      end
    }
  end
end

-- ============================================================================
-- API PÚBLICA
-- ============================================================================

CaveBot.isOn = function()
  return isEnabled
end

CaveBot.isOff = function()
  return not isEnabled
end

CaveBot.isPaused = function()
  return isPaused
end

CaveBot.setOn = function(val)
  if val == false then
    return CaveBot.setOff()
  end

  setupMacro()

  if CaveBot.Recorder and CaveBot.Recorder.isOn and CaveBot.Recorder.isOn() then
    CaveBot.Recorder.disable()
  end

  isEnabled = true
  isPaused = false
  actionRetries = 0
  prevActionResult = true
  macroDelay = 0

  if cavebotMacro and cavebotMacro.setOn then
    cavebotMacro.setOn()
  end

  -- Iniciar loops lentos (creature, trap, lure)
  startSlowLoops()

  if CaveBot.log then
    CaveBot.log(string.format("Cavebot ON - %d waypoints loaded", #actionList), "action")
  end
  startHeartbeat()
end

CaveBot.setOff = function(val)
  if val == false then
    return CaveBot.setOn()
  end

  local wasEnabled = isEnabled
  isEnabled = false
  isPaused = false
  CaveBot.resetWalking()

  -- Limpa estado do Z-recovery + última posição boa para não vazar para a
  -- próxima hunt (drift-check com lastGoodPos stale abortaria o recovery cedo).
  if CaveBot.resetZRecoveryState then CaveBot.resetZRecoveryState() end

  -- Parar loops lentos e limpar flags
  stopSlowLoops()
  stopHeartbeat()

  -- Reset lure stopped state
  if CaveBot.Extensions.lure and CaveBot.Extensions.lure.resetStoppedState then
    CaveBot.Extensions.lure.resetStoppedState()
  end

  if cavebotMacro and cavebotMacro.setOff then
    cavebotMacro.setOff()
  end

  -- Tear down any waypoint "script" snippets (their Timers/HUDs/event handlers) so a
  -- manual stop / profile switch never leaks a script waypoint's side-effects. The
  -- Scripting engine owns their lifecycle; logout/unload also call this.
  if Scripting and Scripting.stopSnippets then
    pcall(Scripting.stopSnippets)
  end

  if wasEnabled and CaveBot.log then
    CaveBot.log("Cavebot OFF", "stop")
  end
end

CaveBot.pause = function()
  isPaused = true
end

CaveBot.resume = function()
  isPaused = false
  -- Reiniciar loops lentos que pararam por isPaused
  if isEnabled then
    startSlowLoops()
  end
end

CaveBot.delay = function(value)
  macroDelay = math.max(macroDelay, g_clock.millis() + value)
end

CaveBot.gotoLabel = function(label)
  if not label then return false end
  local target = label
  label = label:lower()

  for index, action in ipairs(actionList) do
    if action.action:lower() == "label" and action.value:lower() == label then
      currentActionIndex = index
      actionRetries = 0
      prevActionResult = true
      -- Notify UI that waypoint changed
      if walkerCallbacks and walkerCallbacks.onWaypointChanged then
        walkerCallbacks.onWaypointChanged(currentActionIndex)
      end
      return true
    end
  end

  -- Label alvo inexistente no actionList: NAO salta. Sem este aviso a falha e
  -- silenciosa -- o gotolabel/script cai no advanceAction normal (avanca +1,
  -- "vazando" do loop pretendido) e nada sinaliza o motivo. Throttle por
  -- (label + intervalo) porque um waypoint script/function preso em "retry"
  -- chamaria isto a ~50Hz.
  if CaveBot.log then
    local now = g_clock.millis()
    if target ~= lastGotoMissLabel or (now - lastGotoMissTime) >= GOTO_MISS_LOG_INTERVAL then
      lastGotoMissLabel = target
      lastGotoMissTime = now
      CaveBot.log("gotoLabel: label '" .. tostring(target) .. "' nao encontrada", "error")
    end
  end
  return false
end

CaveBot.gotoIndex = function(index)
  if index < 1 or index > #actionList then return false end
  currentActionIndex = index
  actionRetries = 0
  prevActionResult = true
  -- Notify UI that waypoint changed
  if walkerCallbacks and walkerCallbacks.onWaypointChanged then
    walkerCallbacks.onWaypointChanged(currentActionIndex)
  end
  return true
end

CaveBot.getCurrentIndex = function()
  return currentActionIndex
end

CaveBot.getActionCount = function()
  return #actionList
end

-- ============================================================================
-- GERENCIAMENTO DE AÇÕES
-- ============================================================================

CaveBot.addAction = function(action, value, focus)
  action = action:lower()

  -- Verificar se ação existe
  if not CaveBot.Actions[action] then
    error("Invalid cavebot action: " .. action)
    return nil
  end

  if type(value) == "number" then
    value = tostring(value)
  end

  local newAction = {
    action = action,
    value = value or ""
  }

  table.insert(actionList, newAction)

  if focus then
    currentActionIndex = #actionList
  end

  return newAction
end

CaveBot.removeAction = function(index)
  if index < 1 or index > #actionList then return false end
  table.remove(actionList, index)
  if currentActionIndex > #actionList then
    currentActionIndex = math.max(1, #actionList)
  end
  return true
end

CaveBot.clearActions = function()
  actionList = {}
  currentActionIndex = 1
  actionRetries = 0
  prevActionResult = true
  -- Troca/recarga de waypoints (load/loadFromWaypoints): zera Z-recovery para o
  -- estado de uma hunt não vazar para a próxima.
  if CaveBot.resetZRecoveryState then CaveBot.resetZRecoveryState() end
end

CaveBot.getActions = function()
  return actionList
end

CaveBot.setActions = function(actions)
  actionList = actions or {}
  currentActionIndex = 1
  actionRetries = 0
  prevActionResult = true
  if CaveBot.resetZRecoveryState then CaveBot.resetZRecoveryState() end
end

-- ============================================================================
-- SAVE / LOAD
-- ============================================================================

CaveBot.save = function()
  local data = {}

  -- Salvar ações
  for _, action in ipairs(actionList) do
    table.insert(data, {action.action, action.value})
  end

  -- Salvar config
  if CaveBot.Config then
    table.insert(data, {"config", json.encode(CaveBot.Config.save())})
  end

  -- Salvar extensões
  local extensionData = {}
  for extension, callbacks in pairs(CaveBot.Extensions) do
    if callbacks.onSave then
      local extData = callbacks.onSave()
      if type(extData) == "table" then
        extensionData[extension] = extData
      end
    end
  end
  table.insert(data, {"extensions", json.encode(extensionData, 2)})

  return data
end

CaveBot.load = function(data)
  CaveBot.clearActions()

  if not data then return end

  local cavebotConfig = nil
  local extensionsData = nil

  for _, v in ipairs(data) do
    if type(v) == "table" and #v == 2 then
      if v[1] == "config" then
        local status, result = pcall(function()
          return json.decode(v[2])
        end)
        if status then
          cavebotConfig = result
        end
      elseif v[1] == "extensions" then
        local status, result = pcall(function()
          return json.decode(v[2])
        end)
        if status then
          extensionsData = result
        end
      else
        -- É uma ação normal
        CaveBot.addAction(v[1], v[2])
      end
    end
  end

  -- Aplicar config
  if CaveBot.Config and cavebotConfig then
    CaveBot.Config.onConfigChange(nil, true, cavebotConfig)
  end

  -- Aplicar extensões
  if extensionsData then
    for extension, callbacks in pairs(CaveBot.Extensions) do
      if callbacks.onConfigChange then
        callbacks.onConfigChange(nil, true, extensionsData[extension])
      end
    end
  end
end

-- ============================================================================
-- CONVERSÃO DE WAYPOINTS LEGACY
-- ============================================================================

CaveBot.loadFromWaypoints = function(waypoints, config)
  CaveBot.clearActions()

  if not waypoints then return end

  -- Mapa de tipos para ações
  local typeToAction = {
    node = "node",
    stand = "stand",
    use = "use",
    rope = "rope",
    hole = "hole",
    lever = "lever",
    label = "label",
    ["goto"] = "gotolabel",
    wait_lure = "wait_lure",
    stop_to_kill = "stop_to_kill",
    wait_delay = "wait_delay",
    stop_cavebot = "stop_cavebot",
    start_lure = "start_lure",
    stop_lure = "stop_lure",
    special = "special",
    deposit = "deposit",
    bank = "bank",
    travel = "travel",
    door = "door",
    levitate = "levitate",
    script = "script"
  }

  for _, wp in ipairs(waypoints) do
    if wp then
      local wpType = wp.type
      if type(wpType) == "number" then
        -- Converter tipo numérico para string
        local typeMap = {
          [0] = "node", [1] = "stand", [2] = "use", [3] = "rope",
          [4] = "hole", [5] = "lever", [90] = "special",
          [98] = "goto", [99] = "label"
        }
        wpType = typeMap[wpType] or "node"
      end

      local action = typeToAction[wpType] or "node"
      local value = ""

      if wp.position then
        value = wp.position.x .. "," .. wp.position.y .. "," .. wp.position.z
      end

      -- Tratamentos especiais por tipo
      if wpType == "label" then
        value = wp.label or ""
      elseif wpType == "script" then
        -- position-less: o value é o código Lua (guardado em wp.label)
        value = wp.label or ""
      elseif wpType == "goto" then
        action = "gotolabel"
        value = wp.label or ""
        -- Embute a condicao de stamina no value ("label|cond|stamina") para o
        -- executor "gotolabel" avaliar em runtime; sem condicao, so o label.
        local cond = wp.gotoCondition or "none"
        if (cond == "stamina_lt" or cond == "stamina_gt") and wp.gotoStamina then
          value = value .. "|" .. cond .. "|" .. tostring(wp.gotoStamina)
        end
      elseif wpType == "wait_delay" then
        -- value format: "x,y,z|delayMs"
        local delayMs = wp.waitDelayMs or 1000
        value = value .. "|" .. tostring(delayMs)
      elseif wpType == "levitate" then
        -- value format: "x,y,z|mode|dir"
        local mode = wp.levitateMode == "down" and "down" or "up"
        local dir = tonumber(wp.levitateDir)
        if not dir or dir < 0 or dir > 3 then dir = 0 end
        value = value .. "|" .. mode .. "|" .. tostring(dir)
      end

      CaveBot.addAction(action, value)
    end
  end

  -- Aplicar config se fornecida
  if config and CaveBot.Config then
    CaveBot.Config.onConfigChange(nil, true, config)
  end
end

-- Inicializar macro
setupMacro()

-- ============================================================================
-- COMPATIBILIDADE COM HUNTING_RECORDER (cavebotWalker)
-- ============================================================================

-- Global para compatibilidade com hunting_recorder.lua
cavebotWalker = cavebotWalker or {}

-- Callbacks do hunting_recorder (walkerCallbacks declared at top of file)
local walkerConfig = nil

cavebotWalker.start = function(waypoints, config, callbacks)
    walkerConfig = config or {}
    walkerCallbacks = callbacks or {}

    -- Aplicar config
    if config and CaveBot.Config then
        CaveBot.Config.onConfigChange(nil, true, config)
    end

    -- Carregar waypoints
    CaveBot.loadFromWaypoints(waypoints, config)

    -- Determinar índice inicial
    local startIndex = 1

    if config then
        if config.startFromNearest then
            -- Encontrar waypoint mais próximo
            local player = g_game.getLocalPlayer()
            if player then
                local playerPos = player:getPosition()
                if playerPos then
                    local nearestIndex = 1
                    local nearestDist = math.huge

                    for i, wp in ipairs(waypoints) do
                        if wp.position and wp.position.z == playerPos.z then
                            local dx = math.abs(wp.position.x - playerPos.x)
                            local dy = math.abs(wp.position.y - playerPos.y)
                            local dist = dx + dy  -- Manhattan distance

                            if dist < nearestDist then
                                nearestDist = dist
                                nearestIndex = i
                            end
                        end
                    end

                    startIndex = nearestIndex
                    print("[CaveBot] Starting from nearest waypoint #" .. startIndex)
                end
            end
        elseif config.startWaypointIndex and config.startWaypointIndex > 0 then
            -- Usar índice especificado
            startIndex = math.min(config.startWaypointIndex, #waypoints)
            print("[CaveBot] Starting from waypoint #" .. startIndex)
        end
    end

    -- Definir índice inicial
    CaveBot.gotoIndex(startIndex)

    -- Iniciar cavebot
    CaveBot.setOn()

    return true
end

-- Reconstrói o actionList a partir dos waypoints SEM reiniciar o cavebot,
-- preservando o waypoint atualmente em execução. Usada quando um waypoint é
-- editado em runtime (ex.: "Edit Script"): loadFromWaypoints copia o codigo/valor
-- (wp.label -> action.value) apenas no start, entao sem re-sincronizar o motor o
-- executor continua lendo o value ANTIGO e a edicao so valia apos parar/reiniciar.
-- No-op se nao ha acoes carregadas (nada rodou ainda -> o proximo start ja monta
-- tudo do zero com os dados novos).
cavebotWalker.reloadWaypoints = function(waypoints)
    if not waypoints or #actionList == 0 then return false end

    -- Reconstroi na MESMA ordem que o start (waypoints ordenados por index, via
    -- pairs p/ aceitar array OU tabela esparsa), para que o currentActionIndex
    -- preservado continue apontando o mesmo waypoint logico.
    local sorted = {}
    for _, wp in pairs(waypoints) do sorted[#sorted + 1] = wp end
    table.sort(sorted, function(a, b) return (a.index or 0) < (b.index or 0) end)

    local savedIndex = currentActionIndex
    -- config nil: NAO reaplica Config (so reconstroi as acoes). clearActions()
    -- interno zera index/retries; restauramos a posicao de execucao logo abaixo.
    CaveBot.loadFromWaypoints(sorted, nil)

    if #actionList > 0 then
        currentActionIndex = math.min(math.max(1, savedIndex), #actionList)
    else
        currentActionIndex = 1
    end
    actionRetries = 0
    prevActionResult = true
    return true
end

cavebotWalker.stop = function()
    CaveBot.setOff()

    -- Chamar callback se existir
    if walkerCallbacks and walkerCallbacks.onStop then
        walkerCallbacks.onStop()
    end
end

cavebotWalker.isActive = function()
    return CaveBot.isOn()
end

cavebotWalker.getCurrentWaypointIndex = function()
    return CaveBot.getCurrentIndex()
end

cavebotWalker.updateConfig = function(newConfig)
    if not newConfig then return end

    -- Atualizar config
    if CaveBot.Config then
        for key, value in pairs(newConfig) do
            CaveBot.Config.set(key, value)
        end
    end
end

cavebotWalker.getCreatureCount = function()
    return lureState.creatureCount or 0
end

-- Compute the cavebot "state" string (Idle/Walking/Killing/...). Shared by the
-- lightweight getStatus() and the heavy getDebugInfo() so both agree exactly.
-- Reads only cached lureState flags + config + one small position match — no
-- spectator scan, no allocation.
local function computeCavebotState()
    if not CaveBot.isOn() then return "Idle" end
    if CaveBot.isPaused() then return "Paused" end

    local lure = CaveBot.Extensions.lure
    local creaturesToStop = CaveBot.Config and CaveBot.Config.get("creaturesToStop") or 99
    local isLureMode = CaveBot.Config and CaveBot.Config.get("lureMode") or false
    local isWalking = CaveBot.isWalking and CaveBot.isWalking() or false

    local creatureCount = lureState.creatureCount or 0
    local isTrapped = lureState.isTrapped or false
    local isStoppedForCreatures = lure and lure.isStoppedForCreatures and lure.isStoppedForCreatures() or false

    -- At stop_to_kill waypoint position? (cheap: one parse + position compare)
    local isAtStopToKill = false
    local actions = CaveBot.getActions()
    local curIdx = CaveBot.getCurrentIndex()
    local curAct = actions and actions[curIdx]
    if curAct and curAct.action:lower() == "stop_to_kill" and curAct.value then
        local sx, sy, sz = curAct.value:match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
        if sx then
            local player = g_game.getLocalPlayer()
            local pp = player and player:getPosition()
            if pp and pp.x == tonumber(sx) and pp.y == tonumber(sy) and pp.z == tonumber(sz) then
                isAtStopToKill = true
            end
        end
    end

    if isAtStopToKill or isStoppedForCreatures or creatureCount >= creaturesToStop then
        return "Killing"
    elseif isTrapped then
        return "Avoiding"
    elseif isLureMode and lureState.shouldWait then
        return "Luring"
    elseif isWalking then
        return "Walking"
    end
    return "Processing"
end

-- Lightweight status for the high-frequency consumers (minimap waypoint label
-- updater @500ms and the external watchdog @3s). Returns ONLY the few fields
-- those callers read, with NO spectator scan and NO ~30-field allocation.
-- The heavy getDebugInfo() below is reserved for the debug popup.
cavebotWalker.getStatus = function()
    return {
        isActive = CaveBot.isOn(),
        state = computeCavebotState(),
        currentWaypoint = CaveBot.getCurrentIndex(),
        totalWaypoints = CaveBot.getActionCount(),
    }
end

cavebotWalker.getDebugInfo = function()
    local lure = CaveBot.Extensions.lure
    local isLureMode = CaveBot.Config and CaveBot.Config.get("lureMode") or false
    local isAvoidMode = CaveBot.Config and CaveBot.Config.get("avoidTrap") or false
    local creaturesToStop = CaveBot.Config and CaveBot.Config.get("creaturesToStop") or 99
    local creaturesToWalk = CaveBot.Config and CaveBot.Config.get("creaturesToWalk") or 99
    local creaturesToAvoid = CaveBot.Config and CaveBot.Config.get("creaturesToAvoid") or 7
    local trapDistance = CaveBot.Config and CaveBot.Config.get("trapDistance") or 1

    -- Estado atual (compartilhado com getStatus via computeCavebotState — assim
    -- ambos nunca divergem). A função lê só flags cacheadas do lureState +
    -- config + uma checagem de posição barata; nenhum scan de spectators.
    local state = computeCavebotState()
    local isWalking = CaveBot.isWalking and CaveBot.isWalking() or false
    local isTrapped = false
    local avoidObstacles = 0
    local creatureCount = 0

    -- Ler do lureState (cache dos loops lentos) em vez de chamar funções caras
    creatureCount = lureState.creatureCount or 0
    isTrapped = lureState.isTrapped or false
    avoidObstacles = lureState.avoidObstacles or 0

    -- Visible-monsters count for the HUD. `creatureCount` is filtered by
    -- waypoint direction + ignore list for lure decisions, so it frequently
    -- zeroes out in dense spawns — not what "Mobs On Screen" should show.
    --
    -- PERF: route through the shared CreatureCache (200ms TTL + native bulk
    -- extraction) instead of an ad-hoc g_map.getSpectators scan with a Lua
    -- per-creature filter on every call. getMonsterCountAround applies the
    -- same alive + same-floor + in-range filter; it additionally excludes
    -- summons (the old raw scan counted them), but this is a display-only HUD
    -- figure that feeds no bot decision, so behavior/feel is unchanged.
    local mobsOnScreenRaw = 0
    do
        local rangeX, rangeY = 7, 5
        if ScreenGrid and ScreenGrid.getConfig then
            local cfg = ScreenGrid.getConfig()
            rangeX, rangeY = cfg.rangeX or rangeX, cfg.rangeY or rangeY
        end
        if CreatureCache and CreatureCache.getMonsterCountAround then
            mobsOnScreenRaw = CreatureCache.getMonsterCountAround(nil, rangeX, rangeY) or 0
        end
    end

    local debugInfo = {
        -- Estado básico
        enabled = CaveBot.isOn(),
        isActive = CaveBot.isOn(),  -- Alias para compatibilidade
        paused = CaveBot.isPaused(),
        state = state,

        -- Waypoints
        currentWaypoint = CaveBot.getCurrentIndex(),
        totalWaypoints = CaveBot.getActionCount(),
        currentAction = CaveBot.getCurrentIndex(),
        totalActions = CaveBot.getActionCount(),
        currentActionName = nil,
        currentActionValue = nil,

        -- Walking
        walking = isWalking,

        -- Lure/Avoid mode
        isLureMode = isLureMode,
        isAvoidMode = isAvoidMode,
        isTrapped = isTrapped,

        -- Creature counts
        creatureCount = creatureCount,          -- reachable mobs (ignore list applied), drives stop/walk thresholds
        mobsOnScreen = mobsOnScreenRaw,         -- raw visible mobs, for HUD display
        mobsReachable = creatureCount,          -- alias for clarity
        mobsToStop = creaturesToStop,
        mobsToWalk = creaturesToWalk,
        waitingMobs = (lure and lure.getWaitingCreatureCount and lure.getWaitingCreatureCount()) or 0,
        ignoredMobs = 0,

        -- Avoid trap settings
        avoidObstacles = avoidObstacles,
        creaturesAround = avoidObstacles,
        creaturesToAvoid = creaturesToAvoid,
        trapDistance = trapDistance
    }

    -- Obter info da ação atual
    local actions = CaveBot.getActions()
    local action = actions[debugInfo.currentAction]
    if action then
        debugInfo.currentActionName = action.action
        debugInfo.currentActionValue = action.value
    end

    -- Contar criaturas em espera (para lure)
    if isLureMode and state == "Luring" then
        debugInfo.waitingMobs = creatureCount
    end

    return debugInfo
end

cavebotWalker.getCurrentPath = function()
    if CaveBot.getCurrentPath then
        return CaveBot.getCurrentPath()
    end
    return nil, nil
end

-- Alias functions
cavebotWalker.pause = function()
    CaveBot.pause()
end

cavebotWalker.resume = function()
    CaveBot.resume()
end

-- Publica CaveBot/cavebotWalker no _G REAL para a API de scripting enxergar. Os
-- arquivos scripting/api/*.lua sao carregados via dofile em runtime, com o fenv
-- resetado para _G (ver astra_compat.lua) -- entao um `CaveBot` bare (que vive no
-- sandbox do modulo) e invisivel a eles, e `_G.CaveBot` dava nil, matando toda a
-- API CaveBot do scripting (GoTo/pause/waypoints/config). Guardado/idempotente.
if _G then
    _G.CaveBot = _G.CaveBot or CaveBot
    _G.cavebotWalker = _G.cavebotWalker or cavebotWalker
end

return CaveBot
