-- CaveBot Actions Module
-- Sistema de ações registráveis baseado na referência game_bot
-- Inclui ações básicas + ações especiais do usuário

CaveBot = CaveBot or {}
CaveBot.Actions = {}
CaveBot.Extensions = CaveBot.Extensions or {}

-- Estado global para rastrear motivo de saída da hunt
-- Usado para wait_stamina só esperar se saiu por causa de stamina
CaveBot.LeaveReason = {
  stamina = false,
  supplies = false,
  cap = false
}

-- Reset leave reason (chamado quando volta a huntar)
CaveBot.resetLeaveReason = function()
  CaveBot.LeaveReason.stamina = false
  CaveBot.LeaveReason.supplies = false
  CaveBot.LeaveReason.cap = false
end

-- Cavebot decision/action log (visible no modal "Log" do helper).
-- Não fala em chat, só registra em buffer. Silencioso se o módulo não estiver carregado.
CaveBot.log = function(msg, msgType)
  local hr = modules.game_helper and modules.game_helper.hunting_recorderModule
  if hr and hr.cavebotLog then
    hr.cavebotLog(msg, msgType)
  end
end

-- ============================================================================
-- SISTEMA DE REGISTRO DE AÇÕES
-- ============================================================================

--[[
registerAction:
action - string (nome da ação)
color - string (cor para exibição)
callback = function(value, retries, prev)
  - value: string com valor/parâmetros da ação
  - retries: número que incrementa a cada "retry"
  - prev: true se ação anterior foi executada com sucesso

Retornos possíveis:
  - true: ação executada com sucesso, avança para próxima
  - false: ação falhou, avança para próxima
  - "retry": ação pendente, será chamada novamente em 20ms
]]--

CaveBot.registerAction = function(action, color, callback)
  action = action:lower()
  if CaveBot.Actions[action] then
    return error("Duplicated action: " .. action)
  end
  CaveBot.Actions[action] = {
    color = color,
    callback = callback
  }
end

-- ============================================================================
-- FUNÇÕES AUXILIARES
-- ============================================================================

local function parsePosition(value)
  local match = value:match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
  if match then
    local x, y, z = value:match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
    return {x = tonumber(x), y = tonumber(y), z = tonumber(z)}
  end
  return nil
end

local function parsePositionWithPrecision(value)
  local x, y, z, p = value:match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,?%s*(%d*)")
  if x then
    return {
      x = tonumber(x),
      y = tonumber(y),
      z = tonumber(z)
    }, tonumber(p) or 1
  end
  return nil, 1
end

local function getPlayer()
  return g_game.getLocalPlayer()
end

local function getPlayerPos()
  local player = getPlayer()
  return player and player:getPosition()
end

-- ============================================================================
-- Z-RECOVERY: Recuperação automática quando player está no Z errado
-- ============================================================================

local Z_RECOVERY_RANGE = 5           -- raio de busca por tiles de floor change
local Z_RECOVERY_MAX_RETRIES = 15    -- máximo de retries no recovery antes de desistir
local Z_RECOVERY_MAX_DRIFT = 3       -- max sqm de distância da última posição boa
local Z_RECOVERY_INTERVAL = 5000     -- intervalo mínimo entre tentativas (5 segundos)

-- Lookup table de item IDs que são floor change
-- "down" = z+1 (desce), "generic" = pode ser up ou down
local FLOOR_CHANGE_IDS = {
  [166]="down",[167]="down",[293]="down",[294]="down",[369]="down",[370]="down",
  [385]="down",[394]="down",[411]="down",[412]="down",[413]="down",[414]="down",
  [428]="down",[432]="down",[433]="down",[434]="down",[437]="down",[438]="down",
  [469]="down",[476]="down",[482]="down",[483]="down",[484]="down",[485]="down",
  [566]="down",[567]="down",[594]="down",[595]="down",[600]="down",[601]="down",
  [604]="down",[605]="down",[607]="down",[609]="down",[610]="down",[615]="down",
  [855]="generic",[856]="generic",[859]="down",[868]="down",[874]="down",[877]="down",
  [1066]="down",[1067]="down",[1080]="down",[1156]="down",
  [1947]="generic",[1950]="generic",[1952]="generic",[1954]="generic",[1956]="generic",
  [1958]="generic",[1960]="generic",[1962]="generic",[1964]="generic",[1966]="generic",
  [1969]="generic",[1971]="generic",[1973]="generic",[1975]="generic",
  [1977]="generic",[1978]="generic",
  [2192]="generic",[2194]="generic",[2196]="generic",[2198]="generic",
  [4823]="down",[4824]="down",[4825]="down",[4826]="down",
  [5033]="generic",[5035]="generic",[5037]="generic",[5039]="generic",
  [5081]="down",[5257]="generic",[5258]="generic",[5259]="generic",
  [5544]="down",[5691]="down",[5731]="down",[5763]="down",
  [6127]="down",[6128]="down",[6129]="down",[6130]="down",
  [6172]="down",[6173]="down",[6754]="down",[6755]="down",[6756]="down",
  [6909]="generic",[6911]="generic",[6913]="generic",[6915]="generic",
  [6917]="down",[6918]="down",[6919]="down",[6920]="down",
  [6921]="down",[6922]="down",[6923]="down",[6924]="down",
  [7053]="down",[7181]="down",[7182]="down",
  [7476]="down",[7477]="down",[7478]="down",[7479]="down",
  [7515]="down",[7516]="down",[7517]="down",[7518]="down",
  [7520]="down",[7521]="down",[7522]="down",
  [7542]="generic",[7544]="generic",[7546]="generic",[7548]="generic",
  [7729]="down",[7730]="down",[7731]="down",[7732]="down",
  [7733]="down",[7734]="down",[7735]="down",[7736]="down",
  [7737]="down",[7755]="down",[7767]="down",[7768]="down",
  [7881]="generic",[7887]="generic",[7888]="generic",
  [8144]="down",[8657]="generic",[8658]="down",[8690]="down",[8709]="down",
  [8830]="generic",[8831]="generic",[8932]="down",
  [10206]="generic",[11365]="generic",[11707]="generic",[11709]="generic",
  [12203]="down",[12236]="down",[12799]="down",[12961]="down",
  [13341]="generic",[13342]="generic",
  [13559]="generic",[13561]="generic",[13564]="generic",[13567]="generic",
  [13570]="generic",[13573]="generic",[13576]="generic",[13579]="generic",
  [13582]="generic",[13585]="generic",[13588]="generic",[13591]="generic",
  [13716]="generic",[13718]="generic",[13720]="generic",[13722]="generic",
  [14133]="down",[14134]="down",[14135]="down",
  [14932]="generic",[14934]="generic",[14936]="generic",[14938]="generic",
  [15108]="generic",[15110]="generic",[15112]="generic",[15114]="generic",
  [15144]="generic",[15145]="down",[15146]="down",
  [16265]="down",[16266]="down",[16267]="down",[16268]="down",
  [16269]="down",[16270]="down",[16271]="down",[16272]="down",
  [16680]="generic",[16682]="generic",[16684]="generic",[16686]="generic",
  [16688]="generic",[16690]="generic",[16692]="generic",[16694]="generic",
  [16696]="down",[16697]="down",[16698]="down",[16699]="down",
  [16700]="down",[16701]="down",[16702]="down",[16703]="down",
  [16785]="down",[16786]="down",[16787]="down",[16788]="down",
  [16789]="down",[16790]="down",[16791]="down",[16792]="down",
  [17230]="generic",[17239]="down",[17394]="generic",[17395]="generic",
  [18642]="down",[18643]="down",[18644]="down",[18645]="down",
  [18646]="down",[18647]="down",[18648]="down",[18649]="down",
  [18650]="generic",[18652]="generic",[18654]="generic",[18656]="generic",
  [19143]="down",[19220]="down",
  [19590]="generic",[19591]="generic",
  [20124]="generic",[20224]="generic",[20225]="generic",
  [20253]="generic",[20254]="generic",[20255]="generic",[20256]="generic",
  [20259]="down",[20260]="down",[20261]="down",[20262]="down",[20263]="down",
  [20328]="down",[20329]="down",[20330]="down",[20331]="down",[20332]="down",
  [20333]="generic",[20334]="generic",[20335]="generic",[20336]="generic",
  [20344]="down",
  [20469]="down",[20470]="down",[20471]="down",[20472]="down",[20473]="down",
  [20488]="down",[20489]="down",
  [20491]="generic",[20492]="generic",[20494]="generic",[20496]="generic",
  [20750]="generic",[20751]="generic",[20753]="generic",[20755]="generic",
  [21034]="down",[21342]="down",[21344]="down",
  [21564]="generic",[21566]="generic",[21568]="generic",[21570]="generic",
  [21971]="down",[21972]="down",[21973]="down",
  [22156]="generic",[22157]="down",[22517]="generic",
  [22565]="generic",[22566]="generic",[22748]="down",[22749]="generic",
  [23364]="down",
  [23858]="generic",[23860]="generic",[23862]="generic",[23864]="generic",
  [24806]="generic",[24808]="generic",[24810]="generic",[24812]="generic",
  [25016]="generic",[25018]="generic",[25020]="generic",[25022]="generic",
  [27628]="down",[27629]="generic",
  [28357]="generic",[28359]="generic",[28361]="generic",[28363]="generic",
  [28655]="down",
  [29109]="generic",[29111]="generic",[29113]="generic",[29115]="generic",
  [29137]="generic",[29139]="generic",[29141]="generic",[29143]="generic",
  [30452]="down",[30453]="down",
  [30757]="generic",[30759]="generic",[30761]="generic",[30763]="generic",
  [30820]="generic",[30822]="generic",[30824]="generic",[30826]="generic",
  [30904]="generic",[30906]="generic",[30908]="generic",[30910]="generic",
  [30912]="generic",[30914]="generic",[30916]="generic",[30918]="generic",
  [31129]="generic",[31130]="generic",[31168]="down",[31907]="generic",[32020]="down",
  [33175]="generic",[33177]="generic",[33179]="generic",[33181]="generic",
  [33204]="generic",[33206]="generic",[33208]="generic",[33210]="generic",
  [33233]="generic",[33235]="generic",[33237]="generic",[33239]="generic",
  [33256]="generic",[33258]="generic",[33260]="generic",[33262]="generic",
  [33709]="down",[34165]="generic",[34166]="down",[34255]="down",
  [36444]="generic",[36446]="generic",[36448]="generic",[36450]="generic",
  [37964]="generic",[37966]="generic",[37968]="generic",[37970]="generic",
  [38831]="down",[38832]="down",[39721]="generic",[39722]="generic",
  [39919]="generic",[39921]="generic",[39923]="generic",[39925]="generic",
  [40262]="generic",[40263]="generic",[40279]="generic",[40281]="generic",
  [40296]="generic",[40298]="generic",[40302]="generic",
  [40428]="generic",[40430]="generic",[40432]="generic",[40434]="generic",
  [42391]="generic",[42393]="generic",[42395]="generic",[42397]="generic",
  [42619]="generic",[42621]="generic",[42623]="generic",[42632]="generic",
  [42965]="generic",[42967]="generic",[42969]="generic",[42971]="generic",
  [43130]="generic",[43132]="generic",[43134]="generic",[43372]="down",
  [44896]="generic",[44898]="generic",[44900]="generic",[44902]="generic",
  [44942]="generic",[44943]="generic",[44946]="generic",[44948]="generic",
  [45154]="generic",[45156]="generic",[45158]="generic",[45160]="generic",
  [45395]="generic",[45397]="generic",[45399]="generic",[45401]="generic",
  [49161]="down",
  [49657]="generic",[49659]="generic",[49661]="generic",[49663]="generic",
  [49776]="generic",[49777]="generic",[49778]="generic",[49779]="generic",
  [49780]="generic",[49781]="generic",[49782]="generic",[49783]="generic",
  [49937]="generic",[49939]="generic",[49941]="generic",[49943]="generic",
  [50069]="down",[50070]="down",[50071]="down",[50072]="down",
  [50082]="down",[50083]="down",[50084]="down",[50085]="down",[50121]="down",
  [50547]="generic",[50551]="generic",[50553]="generic",[50555]="generic",
  [50613]="down",[51313]="generic",[51366]="down",
  [63923]="generic",[64216]="generic", -- Heroic Dimension portals (solo / party)
}
CaveBot.FLOOR_CHANGE_IDS = FLOOR_CHANGE_IDS

-- Checa se um tile tem floor change (via lookup de item IDs)
-- Retorna: "down", "generic" ou false
local function getFloorChangeType(pos)
  if not pos then return false end
  local tile = g_map.getTile(pos)
  if not tile then return false end

  local things = tile:getThings() or {}
  for _, thing in ipairs(things) do
    if thing and thing:isItem() then
      local fcType = FLOOR_CHANGE_IDS[thing:getId()]
      if fcType then
        return fcType
      end
    end
  end
  return false
end

-- Encontra o tile de floor change mais próximo num raio
-- Busca em anéis expandindo de perto para longe (dist 0, 1, 2, ...)
-- targetZ: Z do waypoint alvo (para filtrar direção do floor change)
-- playerZ: Z atual do player
local function findNearbyFloorChange(origin, range, playerZ, targetZ)
  if not origin then return nil end
  range = range or Z_RECOVERY_RANGE

  -- Determinar direção necessária: se targetZ > playerZ -> precisa descer ("down")
  -- se targetZ < playerZ -> precisa subir (não "down")
  -- "generic" serve para ambos
  local needDown = targetZ and playerZ and (targetZ > playerZ)
  local needUp = targetZ and playerZ and (targetZ < playerZ)

  for dist = 0, range do
    for dx = -dist, dist do
      for dy = -dist, dist do
        if dist == 0 or math.abs(dx) == dist or math.abs(dy) == dist then
          local checkPos = {x = origin.x + dx, y = origin.y + dy, z = origin.z}
          local fcType = getFloorChangeType(checkPos)
          if fcType then
            -- "generic" sempre serve
            if fcType == "generic" then
              return checkPos
            end
            -- "down" serve se precisa descer OU se não sabe a direção
            if fcType == "down" and (needDown or (not needDown and not needUp)) then
              return checkPos
            end
            -- Se precisa subir e o item é "down", pular (down não sobe)
            -- Se precisa descer e o item é "down", ok
          end
        end
      end
    end
  end
  return nil
end

-- Procura o waypoint alcançável mais próximo no mesmo Z do player
-- Retorna o índice do waypoint ou nil
local function findReachableWaypointOnSameZ(playerPos)
  if not playerPos then return nil end

  local actions = CaveBot.getActions()
  if not actions or #actions == 0 then return nil end

  local count = #actions
  local bestIdx = nil
  local bestDist = math.huge

  for i = 1, count do
    local action = actions[i]
    local actionType = action.action:lower()

    -- Só considerar node/goto/stand que têm posição
    if actionType == "node" or actionType == "goto" or actionType == "stand" then
      local pos = parsePosition(action.value)
      if pos and pos.z == playerPos.z then
        local dx = math.abs(pos.x - playerPos.x)
        local dy = math.abs(pos.y - playerPos.y)
        local dist = math.max(dx, dy)

        -- Verificar se é alcançável via pathfinding (distância razoável)
        if dist <= 50 then
          local path = CaveBot.Map.findPath(playerPos, pos, dist * 2, {
            ignoreNonPathable = true,
            ignoreCreatures = true,
            precision = 2
          })
          if path and #path > 0 and dist < bestDist then
            bestDist = dist
            bestIdx = i
          end
        end
      end
    end
  end

  return bestIdx
end

-- Última posição conhecida no Z correto (atualizada sempre que node/goto roda no Z certo)
local lastGoodPos = nil

-- Estado do Z-recovery (persistente entre chamadas)
local zRecovery = {
  active = false,
  targetPos = nil,      -- tile de floor change alvo
  retries = 0,
  lastZ = nil,          -- Z do player quando recovery começou
  targetWpZ = nil,      -- Z do waypoint alvo
  wpFallbackIdx = nil,  -- índice do waypoint fallback no mesmo Z
  lastAttemptTime = 0,  -- timestamp da última tentativa
}

local function resetZRecovery()
  zRecovery.active = false
  zRecovery.targetPos = nil
  zRecovery.retries = 0
  zRecovery.lastZ = nil
  zRecovery.targetWpZ = nil
  zRecovery.wpFallbackIdx = nil
end

-- Tenta recuperar o Z do player
-- Retorna: "retry" se está tentando, false se desistiu
local function tryZRecovery(playerPos, waypointZ)
  if not CaveBot.Config.get("zRecovery") then
    return false
  end

  -- Throttle: só tentar a cada 5 segundos
  local now = g_clock.millis()
  if now - zRecovery.lastAttemptTime < Z_RECOVERY_INTERVAL then
    return "retry"
  end
  zRecovery.lastAttemptTime = now

  -- Verificar se player está perto da última posição boa (max ±3 em X e ±3 em Y)
  if lastGoodPos then
    local driftX = math.abs(playerPos.x - lastGoodPos.x)
    local driftY = math.abs(playerPos.y - lastGoodPos.y)
    if driftX > Z_RECOVERY_MAX_DRIFT or driftY > Z_RECOVERY_MAX_DRIFT then
      resetZRecovery()
      return false
    end
  end

  -- Se o Z mudou (recovery funcionou), resetar
  if zRecovery.active and zRecovery.lastZ and playerPos.z ~= zRecovery.lastZ then
    resetZRecovery()
    return false
  end

  -- Limite de retries — fallback para waypoint no mesmo Z
  if zRecovery.retries >= Z_RECOVERY_MAX_RETRIES then
    if not zRecovery.wpFallbackIdx then
      zRecovery.wpFallbackIdx = findReachableWaypointOnSameZ(playerPos)
    end
    if zRecovery.wpFallbackIdx then
      CaveBot.gotoIndex(zRecovery.wpFallbackIdx)
      resetZRecovery()
      return "retry"
    end
    resetZRecovery()
    return false
  end

  -- Iniciar recovery se não ativo
  if not zRecovery.active then
    local floorTile = findNearbyFloorChange(playerPos, Z_RECOVERY_RANGE, playerPos.z, waypointZ)
    if floorTile then
      zRecovery.active = true
      zRecovery.targetPos = floorTile
      zRecovery.retries = 0
      zRecovery.lastZ = playerPos.z
      zRecovery.targetWpZ = waypointZ
    else
      local wpIdx = findReachableWaypointOnSameZ(playerPos)
      if wpIdx then
        CaveBot.gotoIndex(wpIdx)
        resetZRecovery()
        return "retry"
      end
      return false
    end
  end

  zRecovery.retries = zRecovery.retries + 1

  local dx = math.abs(zRecovery.targetPos.x - playerPos.x)
  local dy = math.abs(zRecovery.targetPos.y - playerPos.y)
  local dist = math.max(dx, dy)

  -- Se já está no tile, usar o item
  if dist == 0 then
    local tile = g_map.getTile(zRecovery.targetPos)
    if tile then
      local thing = tile:getTopUseThing()
      if thing then
        g_game.use(thing)
      end
    end
    return "retry"
  end

  -- Caminhar até o tile de floor change
  if CaveBot.walkTo(zRecovery.targetPos, dist * 2, { ignoreNonPathable = true, precision = 0, allowFloorChangeDest = true }) then
    return "retry"
  end

  CaveBot.walkTo(zRecovery.targetPos, dist * 2, { ignoreNonPathable = true, ignoreCreatures = true, precision = 0, allowFloorChangeDest = true })
  return "retry"
end

-- ============================================================================

local function sayNpc(message)
  local player = g_game.getLocalPlayer()
  if not player then return end
  
  local playerPos = player:getPosition()
  if not playerPos then return end
  
  local npc = nil
  local minDist = math.huge
  
  -- Método 1: Usar g_map.getSpectators para encontrar NPC próximo
  local spectators = g_map.getSpectators(playerPos, false)
  if spectators then
    for _, creature in ipairs(spectators) do
      if creature:isNpc() then
        local creaturePos = creature:getPosition()
        if creaturePos and creaturePos.z == playerPos.z then
          local distance = math.max(
            math.abs(playerPos.x - creaturePos.x),
            math.abs(playerPos.y - creaturePos.y)
          )
          if distance <= 3 and distance < minDist then
            minDist = distance
            npc = creature
          end
        end
      end
    end
  end
  
  -- Método 2: Fallback para CreatureCache se disponível
  if not npc and CreatureCache and CreatureCache.getNpcs then
    local npcs = CreatureCache.getNpcs()
    if npcs and #npcs > 0 then
      for _, entry in ipairs(npcs) do
        if entry.sameFloor then
          local dist = math.max(entry.dx or 999, entry.dy or 999)
          if dist <= 3 and dist < minDist then
            minDist = dist
            npc = entry.creature
          end
        end
      end
    end
  end
  
  -- Enviar mensagem
  if npc then
    local npcName = npc:getName()
    if npcName and npcName ~= "" then
      g_game.talkPrivate(MessageModes.NpcTo, npcName, message)
      return
    end
  end
  
  -- Fallback: falar no chat local (NPC ouve se estiver próximo)
  g_game.talk(message)
end

local function getItemCount(itemId)
  if modules.game_helper and modules.game_helper.getItemCountAnywhere then
    return modules.game_helper.getItemCountAnywhere(itemId)
  end
  -- Fallback
  local item = g_game.findPlayerItem(itemId, -1)
  return item and item:getCount() or 0
end

-- ============================================================================
-- AÇÕES BÁSICAS (da referência)
-- ============================================================================

-- Label: marca um ponto de salto (não faz nada)
CaveBot.registerAction("label", "yellow", function(value, retries, prev)
  return true
end)

-- GotoLabel: salta para um label
CaveBot.registerAction("gotolabel", "#FFFF55", function(value, retries, prev)
  return CaveBot.gotoLabel(value)
end)

-- Delay: aguarda X milissegundos
CaveBot.registerAction("delay", "#AAAAAA", function(value, retries, prev)
  if retries == 0 then
    CaveBot.delay(tonumber(value) or 1000)
    return "retry"
  end
  return true
end)

-- Function: executa código Lua
CaveBot.registerAction("function", "red", function(value, retries, prev)
  local prefix = "local retries = " .. retries .. "\n"
  prefix = prefix .. "local prev = " .. tostring(prev) .. "\n"
  prefix = prefix .. "local delay = CaveBot.delay\n"
  prefix = prefix .. "local gotoLabel = CaveBot.gotoLabel\n"

  -- Adicionar extensões como variáveis locais
  for extension, callbacks in pairs(CaveBot.Extensions) do
    prefix = prefix .. "local " .. extension .. " = CaveBot.Extensions." .. extension .. "\n"
  end

  local status, result = pcall(function()
    return assert(load(prefix .. value, "cavebot_function"))()
  end)

  if not status then
    error("Error in cavebot function:\n" .. tostring(result))
    return false
  end
  return result
end)

-- Goto: caminha até uma posição
CaveBot.registerAction("goto", "green", function(value, retries, prev)
  local pos, precision = parsePositionWithPrecision(value)
  if not pos then
    error("Invalid cavebot goto action value. It should be position (x,y,z), is: " .. value)
    return false
  end

  -- Limite de retries
  if CaveBot.Config.get("mapClick") then
    if retries >= 5 then return false end
  else
    if retries >= 100 then return false end
  end

  local playerPos = getPlayerPos()
  if not playerPos then return false end

  -- Verificar floor diferente - tentar Z-recovery
  if pos.z ~= playerPos.z then
    return tryZRecovery(playerPos, pos.z)
  end
  lastGoodPos = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
  resetZRecovery()

  -- Calcular distância (Chebyshev) e maxDist dinâmico
  local dx = math.abs(pos.x - playerPos.x)
  local dy = math.abs(pos.y - playerPos.y)
  local dist = math.max(dx, dy)

  -- Verificar distância máxima (Chebyshev > 100 = inalcançável)
  if dist > 100 then
    return false
  end

  -- maxDist dinâmico: distance * 2 para permitir caminhos mais longos ao redor de obstáculos
  local maxDist = math.max(dist * 2, 40)

  -- Verificar se é escada (minimap color 210-213)
  local minimapColor = g_map.getMinimapColor(pos)
  local stairs = (minimapColor >= 210 and minimapColor <= 213)

  -- Verificar se já chegou
  if stairs then
    if dist == 0 then return true end
  else
    if dist <= (precision or 1) then return true end
  end

  -- Verificar se existe ALGUM caminho possível (ignorando criaturas e campos)
  local testPath = CaveBot.Map.findPath(playerPos, pos, maxDist, { ignoreNonPathable = true, precision = 1, ignoreCreatures = true })
  if not testPath then
    return false
  end

  -- Tentar caminhar sem ignorar campos
  if not CaveBot.Config.get("ignoreFields") and CaveBot.walkTo(pos, maxDist) then
    return "retry"
  end

  -- Tentar caminhar ignorando campos
  if CaveBot.walkTo(pos, maxDist, { ignoreNonPathable = true }) then
    return "retry"
  end

  -- Após 3 tentativas, reduzir precisão
  if retries >= 3 then
    local reducedPrecision = retries - 1
    if stairs then reducedPrecision = 0 end
    if CaveBot.walkTo(pos, maxDist + 10, { ignoreNonPathable = true, precision = reducedPrecision }) then
      return "retry"
    end
  end

  -- Última tentativa: ignorar criaturas, allowUnseen (como waypoints.lua mais novo)
  if retries >= 4 then
    if CaveBot.walkTo(pos, maxDist, { ignoreNonPathable = true, ignoreCreatures = true, precision = 2, allowUnseen = true }) then
      return "retry"
    end
  end

  -- Verificar limite de retries para modo não-mapClick
  if not CaveBot.Config.get("mapClick") and retries >= 5 then
    return false
  end

  -- Se skipBlocked ativo, desistir
  if CaveBot.Config.get("skipBlocked") then
    return false
  end

  -- Último recurso: ignorar tudo
  CaveBot.walkTo(pos, maxDist, { ignoreNonPathable = true, precision = 1, ignoreCreatures = true })
  return "retry"
end)

-- Stand: posição exata (precisão 0)
-- Só avança quando:
-- 1. Player está na coordenada exata
-- 2. O próximo waypoint na sequência é alcançável
CaveBot.registerAction("stand", "#55FF55", function(value, retries, prev)
  local pos = parsePosition(value)
  if not pos then
    error("Invalid cavebot stand action value: " .. value)
    return false
  end

  if retries >= 100 then return false end

  local playerPos = getPlayerPos()
  if not playerPos then return false end

  if pos.z ~= playerPos.z then return false end

  -- Verificar se já está na posição exata
  if pos.x == playerPos.x and pos.y == playerPos.y then
    -- Estamos na posição exata - verificar se próximo waypoint é alcançável
    local actions = CaveBot.getActions()
    local currentIdx = CaveBot.getCurrentIndex()
    local nextIdx = currentIdx + 1

    -- Se não há próximo waypoint (loop para início), verificar primeiro
    if nextIdx > #actions then
      nextIdx = 1
    end

    local nextAction = actions[nextIdx]
    if not nextAction then
      return true
    end

    -- Verificar se próximo waypoint tem posição
    local nextPos = nil
    local nextType = nextAction.action:lower()

    -- Tipos que precisam de verificação de alcançabilidade
    if nextType == "node" or nextType == "stand" or nextType == "goto" or
       nextType == "use" or nextType == "rope" or nextType == "hole" or
       nextType == "lever" or nextType == "door" then
      nextPos = parsePosition(nextAction.value)
    end

    -- Se próximo waypoint não tem posição (label, gotolabel, function, etc), avançar
    if not nextPos then
      return true
    end

    -- Verificar se está no mesmo floor
    if nextPos.z ~= playerPos.z then
      -- Floor diferente - pode ser escada, avançar
      return true
    end

    -- Verificar se próximo waypoint é alcançável via pathfinding
    local path = g_map.findPathJPS(playerPos, nextPos, 40, 0)
    if path and #path > 0 then
      -- Próximo waypoint é alcançável, podemos avançar
      return true
    end

    -- Próximo waypoint NÃO é alcançável - aguardar (talvez tenha obstáculo temporário)
    CaveBot.delay(200)
    return "retry"
  end

  -- Caminhar até a posição (stand pode pisar no tile final mesmo com floor change)
  if CaveBot.walkTo(pos, 40, { ignoreNonPathable = true, allowFloorChangeDest = true }) then
    return "retry"
  end

  return "retry"
end)

-- Node: mesma lógica do goto mas usa nodeDistance
CaveBot.registerAction("node", "green", function(value, retries, prev)
  local pos = parsePosition(value)
  if not pos then
    error("Invalid cavebot node action value: " .. value)
    return false
  end

  if retries >= 100 then return false end

  local playerPos = getPlayerPos()
  if not playerPos then return false end

  if pos.z ~= playerPos.z then
    return tryZRecovery(playerPos, pos.z)
  end
  lastGoodPos = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
  resetZRecovery()

  local nodeDistance = CaveBot.Config.get("nodeDistance") or 2
  local dx = math.abs(pos.x - playerPos.x)
  local dy = math.abs(pos.y - playerPos.y)

  if math.max(dx, dy) <= nodeDistance - 1 then
    return true
  end

  if CaveBot.walkTo(pos, 40, { ignoreNonPathable = true, precision = nodeDistance }) then
    return "retry"
  end

  return "retry"
end)

-- Use: usa objeto em posição ou item por ID
CaveBot.registerAction("use", "#FFB272", function(value, retries, prev)
  -- Tentar como posição
  local pos = parsePosition(value)

  if not pos then
    -- Tentar como item ID
    local itemid = tonumber(value)
    if not itemid then
      error("Invalid cavebot use action value. Should be (x,y,z) or item id: " .. value)
      return false
    end
    g_game.useInventoryItem(itemid)
    return true
  end

  local playerPos = getPlayerPos()
  if not playerPos then return false end

  if pos.z ~= playerPos.z then return false end

  if math.max(math.abs(pos.x - playerPos.x), math.abs(pos.y - playerPos.y)) > 7 then
    return false
  end

  local tile = g_map.getTile(pos)
  if not tile then return false end

  local topThing = tile:getTopUseThing()
  if not topThing then return false end

  g_game.use(topThing)
  CaveBot.delay(CaveBot.Config.get("useDelay") + CaveBot.Config.get("ping"))
  return true
end)

-- UseWith: usa item com objeto em posição
CaveBot.registerAction("usewith", "#EEB292", function(value, retries, prev)
  local itemid, x, y, z = value:match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
  if not itemid then
    error("Invalid cavebot usewith action value. Should be (itemid,x,y,z): " .. value)
    return false
  end

  itemid = tonumber(itemid)
  local pos = {x = tonumber(x), y = tonumber(y), z = tonumber(z)}

  local playerPos = getPlayerPos()
  if not playerPos then return false end

  if pos.z ~= playerPos.z then return false end

  if math.max(math.abs(pos.x - playerPos.x), math.abs(pos.y - playerPos.y)) > 7 then
    return false
  end

  local tile = g_map.getTile(pos)
  if not tile then return false end

  local topThing = tile:getTopUseThing()
  if not topThing then return false end

  g_game.useInventoryItemWith(itemid, topThing)
  CaveBot.delay(CaveBot.Config.get("useDelay") + CaveBot.Config.get("ping"))
  return true
end)

-- Say: fala no chat
CaveBot.registerAction("say", "#FF55FF", function(value, retries, prev)
  g_game.talk(value)
  return true
end)

-- Levitate: stand on exact pos, turn to required direction, then cast exani hur up/down.
-- Value format: "x,y,z|up|dir"  (mode = up|down, dir = 0/1/2/3 = N/E/S/W)
-- Order: pos -> direction -> spell -> wait for floor change
CaveBot.registerAction("levitate", "#AA77FF", function(value, retries, prev)
  if not value or value == "" then return false end

  local posPart, mode, dirStr = value:match("^([^|]+)|([^|]+)|([^|]+)$")
  if not posPart or not mode or not dirStr then
    error("Invalid cavebot levitate action value: " .. tostring(value))
    return false
  end

  local pos = parsePosition(posPart)
  if not pos then return false end

  mode = mode:lower()
  if mode ~= "up" and mode ~= "down" then return false end

  local dir = tonumber(dirStr)
  if not dir or dir < 0 or dir > 3 then return false end

  if retries >= 60 then return false end

  local player = g_game.getLocalPlayer()
  if not player then return false end
  local playerPos = player:getPosition()
  if not playerPos then return false end

  -- Track levitate progress on the action state (via retries-based delays)
  local castState = CaveBot._levitateState or {}
  CaveBot._levitateState = castState

  -- If floor changed (z changed in the expected direction), we're done.
  local zTarget = mode == "up" and (pos.z - 1) or (pos.z + 1)
  if playerPos.z == zTarget then
    castState.casted = nil
    castState.castAt = nil
    return true
  end

  -- 1) Garantir posição exata
  if pos.z ~= playerPos.z or pos.x ~= playerPos.x or pos.y ~= playerPos.y then
    castState.casted = nil
    castState.castAt = nil
    if CaveBot.walkTo(pos, 40, { ignoreNonPathable = true, precision = 0 }) then
      return "retry"
    end
    CaveBot.delay(100)
    return "retry"
  end

  -- 2) Garantir direção
  local currentDir = player:getDirection()
  if currentDir ~= dir then
    g_game.turn(dir)
    castState.casted = nil
    castState.castAt = nil
    CaveBot.delay(150)
    return "retry"
  end

  -- 3) Soltar magia (uma vez), depois aguardar floor change
  local words = "exani hur " .. mode
  local now = g_clock.millis()

  if castState.casted then
    -- Já lançamos; aguardar o servidor mover o player. Se passou muito tempo, tentar de novo.
    if castState.castAt and (now - castState.castAt) > 2000 then
      castState.casted = nil
      castState.castAt = nil
      return "retry"
    end
    CaveBot.delay(150)
    return "retry"
  end

  -- Verificar cooldown
  if Spells and Spells.getSpellByWords then
    local spell = Spells.getSpellByWords("exani hur")
    if spell and isSpellOnCooldown and isSpellOnCooldown(spell) then
      CaveBot.delay(200)
      return "retry"
    end
  end

  g_game.talk(words)
  castState.casted = true
  castState.castAt = now
  CaveBot.delay(200)
  return "retry"
end)

-- ============================================================================
-- AÇÕES ESPECIAIS (do usuário)
-- ============================================================================

-- Rope: usa corda em posição
CaveBot.registerAction("rope", "#FFB272", function(value, retries, prev)
  local pos = parsePosition(value)
  if not pos then
    error("Invalid cavebot rope action value: " .. value)
    return false
  end

  local playerPos = getPlayerPos()
  if not playerPos then return false end

  -- Verificar distância
  if math.max(math.abs(pos.x - playerPos.x), math.abs(pos.y - playerPos.y)) > 1 then
    -- Precisa chegar mais perto primeiro
    if CaveBot.walkTo(pos, 40, { ignoreNonPathable = true, precision = 1 }) then
      return "retry"
    end
    return false
  end

  local tile = g_map.getTile(pos)
  if not tile then return false end

  -- IDs de corda (3003 = rope, 9596/9598/9594 = canivetes que funcionam como rope no server)
  local ropeIds = {3003, 9596, 9598, 9594}
  local target = tile:getTopUseThing()
  if not target then return false end
  for _, itemId in ipairs(ropeIds) do
    if g_game.findPlayerItem(itemId, -1) then
      g_game.useInventoryItemWith(itemId, target)
      CaveBot.delay(CaveBot.Config.get("useDelay") + CaveBot.Config.get("ping"))
      return true
    end
  end

  return false
end)

-- Hole: usa shovel em posição
CaveBot.registerAction("hole", "#FFB272", function(value, retries, prev)
  local pos = parsePosition(value)
  if not pos then
    error("Invalid cavebot hole action value: " .. value)
    return false
  end

  local playerPos = getPlayerPos()
  if not playerPos then return false end

  if math.max(math.abs(pos.x - playerPos.x), math.abs(pos.y - playerPos.y)) > 1 then
    if CaveBot.walkTo(pos, 40, { ignoreNonPathable = true, precision = 1 }) then
      return "retry"
    end
    return false
  end

  local tile = g_map.getTile(pos)
  if not tile then return false end

  -- IDs de shovel
  local shovelIds = {5710, 9596, 9598, 9594}
  local target = tile:getTopUseThing()
  if not target then return false end
  for _, itemId in ipairs(shovelIds) do
    if g_game.findPlayerItem(itemId, -1) then
      g_game.useInventoryItemWith(itemId, target)
      CaveBot.delay(CaveBot.Config.get("useDelay") + CaveBot.Config.get("ping"))
      return true
    end
  end

  return false
end)

-- Lever: usa alavanca em posição
CaveBot.registerAction("lever", "#FFB272", function(value, retries, prev)
  local pos = parsePosition(value)
  if not pos then
    error("Invalid cavebot lever action value: " .. value)
    return false
  end

  if retries >= 60 then return false end

  local playerPos = getPlayerPos()
  if not playerPos then return false end

  if math.max(math.abs(pos.x - playerPos.x), math.abs(pos.y - playerPos.y)) > 1 then
    if CaveBot.walkTo(pos, 40, { ignoreNonPathable = true, precision = 1 }) then
      return "retry"
    end
    return false
  end

  local tile = g_map.getTile(pos)
  if not tile then return false end

  local items = tile:getItems()
  if items and #items > 0 then
    local itemIndex = (retries % #items) + 1
    g_game.use(items[itemIndex])
  else
    local thing = tile:getTopUseThing()
    if thing then g_game.use(thing) end
  end

  CaveBot.delay(150)
  return "retry"
end)

-- Check Supply: verifica supplies, stamina e cap (requer posição exata)
-- value = "x,y,z|labelHasSupply|labelNoSupply" ou "labelHasSupply|labelNoSupply"
local checkSupplyState = { failCount = nil }

CaveBot.registerAction("check_supply", "#00FFFF", function(value, retries, prev)
  local player = getPlayer()
  if not player then return true end

  local playerPos = getPlayerPos()
  if not playerPos then return true end

  -- Parse value - pode ter posição ou não
  local pos, labelHas, labelNo
  local x, y, z, rest = value:match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*|?(.*)")
  if x then
    pos = {x = tonumber(x), y = tonumber(y), z = tonumber(z)}
    -- Parse labels from rest
    labelHas, labelNo = rest:match("([^|]*)|?(.*)")
  else
    -- No position, just labels
    labelHas, labelNo = value:match("([^|]*)|?(.*)")
  end

  labelHas = labelHas and labelHas:match("^%s*(.-)%s*$") or ""
  labelNo = labelNo and labelNo:match("^%s*(.-)%s*$") or ""

  -- Se tem posição, primeiro ir até ela
  if pos then
    if pos.z ~= playerPos.z then return false end

    -- Verificar se está na posição exata
    if pos.x ~= playerPos.x or pos.y ~= playerPos.y then
      -- Caminhar até a posição
      if retries >= 100 then return false end
      if CaveBot.walkTo(pos, 40, { ignoreNonPathable = true }) then
        return "retry"
      end
      return "retry"
    end
  end

  -- Estamos na posição correta - executar lógica de check supply
  if not checkSupplyState.loggedArrive then
    CaveBot.log("Reached Check Supply WP", "action")
    checkSupplyState.loggedArrive = true
  end

  -- Verificar supplies
  local allSuppliesOK = true
  if CaveBot.Extensions.supplies and CaveBot.Extensions.supplies.checkAllSupplies then
    allSuppliesOK = CaveBot.Extensions.supplies.checkAllSupplies()
  end

  -- Verificar stamina
  local staminaOK = true
  local staminaToLeave = CaveBot.Config.get("staminaToLeave") * 60 -- converter para minutos
  if player.getStamina and player:getStamina() < staminaToLeave then
    staminaOK = false
  end

  -- Verificar cap
  local capOK = true
  local capToLeave = CaveBot.Config.get("capToLeave")
  if player.getFreeCapacity and player:getFreeCapacity() < capToLeave then
    capOK = false
  end

  -- Decidir label e salvar motivo de saída
  if not allSuppliesOK or not staminaOK or not capOK then
    -- Verificar 3 vezes antes de sair (aguardar e checar novamente)
    if not checkSupplyState.failCount then
      checkSupplyState.failCount = 0
    end
    checkSupplyState.failCount = checkSupplyState.failCount + 1

    if checkSupplyState.failCount < 3 then
      CaveBot.delay(1000)
      return "retry"
    end

    -- Confirmado 3 vezes - salvar motivo de saída
    checkSupplyState.failCount = nil
    CaveBot.LeaveReason.supplies = not allSuppliesOK
    CaveBot.LeaveReason.stamina = not staminaOK
    CaveBot.LeaveReason.cap = not capOK

    -- Print why is leaving
    local reasons = {}
    if not allSuppliesOK then
      table.insert(reasons, "low supplies")
      local recorderModule = modules.game_helper and modules.game_helper.hunting_recorderModule
      if recorderModule and recorderModule.getCurrentCavebotData then
        local cavebotData = recorderModule.getCurrentCavebotData()
        if cavebotData then
          local supplyItems = cavebotData.supplies or {}
          local supplySettings = cavebotData.supplySettings or {}
          local getCount = modules.game_helper and modules.game_helper.getItemCountAnywhere
          for i = 1, 10 do
            local itemId = supplyItems[i] or 0
            if itemId > 0 then
              local settings = supplySettings[i] or {minSupply = 0}
              local minRequired = settings.minSupply or 0
              local currentCount = getCount and getCount(itemId) or 0
              if currentCount < minRequired then
                table.insert(reasons, string.format("  - item %d: %d/%d", itemId, currentCount, minRequired))
              end
            end
          end
        end
      end
    end
    if not staminaOK then
      local currentStamina = player:getStamina()
      table.insert(reasons, string.format("low stamina: %d min (min: %d min)", math.floor(currentStamina / 60), math.floor(staminaToLeave / 60)))
    end
    if not capOK then
      local currentCap = player:getFreeCapacity()
      table.insert(reasons, string.format("low cap: %.1f (min: %d)", currentCap, capToLeave))
    end
    print("[CaveBot] Leaving cave - " .. table.concat(reasons, ", "))
    CaveBot.log("Leaving cave - " .. table.concat(reasons, " | "), "warn")

    checkSupplyState.loggedArrive = false
    if labelNo ~= "" then
      return CaveBot.gotoLabel(labelNo)
    end
  else
    -- Tudo OK - resetar motivos de saída
    checkSupplyState.failCount = nil
    CaveBot.resetLeaveReason()
    CaveBot.log("Check Supply OK - continuing hunt", "action")

    checkSupplyState.loggedArrive = false
    if labelHas ~= "" then
      return CaveBot.gotoLabel(labelHas)
    end
  end

  return true
end)

-- Buy Supply: compra supplies do NPC (requer posição exata)
-- value = "x,y,z"
-- Lógica: primeiro vai até posição exata, depois envia hi, trade, e compra
local buySupplyState = { atPositionSince = nil }

CaveBot.registerAction("buy_supply", "#FF8800", function(value, retries, prev)
  local player = getPlayer()
  if not player then return true end

  local playerPos = getPlayerPos()
  if not playerPos then return true end

  -- Parse position from value
  local pos = parsePosition(value)
  if not pos then
    return true
  end

  -- Reset state no início
  if retries == 0 then
    buySupplyState.atPositionSince = nil
  end

  -- Verificar mesmo floor
  if pos.z ~= playerPos.z then return false end

  -- Verificar se está na posição exata
  local atPosition = (pos.x == playerPos.x and pos.y == playerPos.y)

  -- Se não está na posição, caminhar primeiro
  if not atPosition then
    buySupplyState.atPositionSince = nil  -- Reset se perdeu posição
    if retries >= 50 then
      return false
    end
    CaveBot.walkTo(pos, 40, { ignoreNonPathable = true })
    CaveBot.delay(200)
    return "retry"
  end

  -- Está na posição - marcar quando chegou
  if not buySupplyState.atPositionSince then
    buySupplyState.atPositionSince = retries
    CaveBot.log("Reached Buy Supply WP - talking to NPC", "action")
  end

  -- Calcular fase NPC baseado em quantos retries desde que chegou na posição
  local npcPhase = retries - buySupplyState.atPositionSince

  -- Executar sequência NPC: hi, trade, comprar
  if npcPhase == 0 then
    sayNpc("hi")
    CaveBot.delay(800)
    return "retry"
  elseif npcPhase == 1 then
    sayNpc("trade")
    CaveBot.delay(1200)
    return "retry"
  elseif npcPhase < 50 then
    -- Fase de compra (npcPhase >= 2)

    -- Verificar janela de trade
    local tradeOpen = false

    -- Get buy items via modules.game_npctrade.getBuyItems() function
    local buyItems = nil
    if modules and modules.game_npctrade and modules.game_npctrade.getBuyItems then
      buyItems = modules.game_npctrade.getBuyItems()
    end

    -- Check if trade is open (has buy items)
    if buyItems and type(buyItems) == "table" and #buyItems > 0 then
      tradeOpen = true
    end

    if not tradeOpen then
      -- Trade não abriu ainda, aguardar mais tempo
      if npcPhase < 15 then
        CaveBot.delay(600)
        return "retry"
      end
      -- Timeout - prosseguir
      buySupplyState.atPositionSince = nil
      return true
    end

    -- Trade aberto - comprar supplies
    if CaveBot.Extensions.supplies and CaveBot.Extensions.supplies.buyAllSupplies then
      local bought = CaveBot.Extensions.supplies.buyAllSupplies()
      if bought then
        CaveBot.delay(400)
        return "retry"
      end
    end

    -- Terminou de comprar
    if g_game.closeNpcTrade then g_game.closeNpcTrade() end
    buySupplyState.atPositionSince = nil
    CaveBot.log("Buy Supply finished", "action")
    return true
  end

  -- Timeout geral
  if g_game.closeNpcTrade then g_game.closeNpcTrade() end
  buySupplyState.atPositionSince = nil
  return true
end)

-- Sell Loot: vende loot para NPC (requer posição exata)
-- value = "x,y,z"
-- Lógica: primeiro vai até posição exata, depois abre trade e usa sellAll
local sellLootState = { atPositionSince = nil }

CaveBot.registerAction("sell_loot", "#FFAA00", function(value, retries, prev)
  local player = getPlayer()
  if not player then return true end

  local playerPos = getPlayerPos()
  if not playerPos then return true end

  -- Parse position from value
  local pos = parsePosition(value)
  if not pos then
    return true
  end

  -- Reset state no início
  if retries == 0 then
    sellLootState.atPositionSince = nil
  end

  -- Verificar mesmo floor
  if pos.z ~= playerPos.z then return false end

  -- Verificar se está na posição exata
  local atPosition = (pos.x == playerPos.x and pos.y == playerPos.y)

  -- Se não está na posição, caminhar primeiro
  if not atPosition then
    sellLootState.atPositionSince = nil  -- Reset se perdeu posição
    if retries >= 50 then
      return false
    end
    CaveBot.walkTo(pos, 40, { ignoreNonPathable = true })
    CaveBot.delay(200)
    return "retry"
  end

  -- Está na posição - marcar quando chegou
  if not sellLootState.atPositionSince then
    sellLootState.atPositionSince = retries
    CaveBot.log("Reached Sell Loot WP - talking to NPC", "action")
  end

  -- Calcular fase NPC baseado em quantos retries desde que chegou na posição
  local npcPhase = retries - sellLootState.atPositionSince

  -- Executar sequência NPC: hi, sell all, bye
  if npcPhase == 0 then
    sayNpc("hi")
    CaveBot.delay(600)
    return "retry"
  elseif npcPhase == 1 then
    sayNpc("sell all")
    CaveBot.delay(600)
    return "retry"
  elseif npcPhase == 2 then
    sayNpc("bye")
    CaveBot.delay(400)
    sellLootState.atPositionSince = nil
    CaveBot.log("Sell Loot finished", "action")
    return true
  end

  sellLootState.atPositionSince = nil
  return true
end)

-- Wait Stamina: aguarda stamina atingir valor (requer posição exata)
-- value = "x,y,z|minutes" ou "x,y,z" ou "minutes" ou vazio
-- SÓ ESPERA se saiu por causa de stamina (CaveBot.LeaveReason.stamina == true)
CaveBot.registerAction("wait_stamina", "#AAFFAA", function(value, retries, prev)
  local player = getPlayer()
  if not player then return true end

  -- Verificar se saiu por causa de stamina
  -- Se não saiu por stamina, pular este waypoint
  if not CaveBot.LeaveReason.stamina then
    return true
  end

  local playerPos = getPlayerPos()
  if not playerPos then return true end

  -- Parse value - pode ter posição e/ou minutos
  local pos = nil
  local targetMinutes = nil

  -- Tentar parse com posição
  local x, y, z, rest = value:match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*|?(.*)")
  if x then
    pos = {x = tonumber(x), y = tonumber(y), z = tonumber(z)}
    if rest and rest ~= "" then
      targetMinutes = tonumber(rest)
    end
  else
    -- Sem posição, apenas minutos
    targetMinutes = tonumber(value)
  end

  -- Default para staminaToReturn da config
  if not targetMinutes then
    targetMinutes = CaveBot.Config.get("staminaToReturn") * 60
  end

  -- Se tem posição, primeiro ir até ela
  if pos then
    if pos.z ~= playerPos.z then return false end

    -- Verificar se está na posição exata
    if pos.x ~= playerPos.x or pos.y ~= playerPos.y then
      -- Caminhar até a posição
      if retries >= 100 then return false end
      if CaveBot.walkTo(pos, 40, { ignoreNonPathable = true }) then
        return "retry"
      end
      return "retry"
    end
  end

  -- Estamos na posição correta - verificar stamina
  if not player.getStamina then return true end

  if player:getStamina() >= targetMinutes then
    -- Stamina OK - resetar flag e continuar
    CaveBot.LeaveReason.stamina = false
    return true
  end

  CaveBot.delay(2000)
  return "retry"
end)

-- Stop to Kill: walks to waypoint position (using stopToKillDistance), then stops while there are creatures
-- Smart mode (default) only counts mobs that are reachable AND approaching,
-- mirroring the lure-mode heuristics so the bot doesn't wait forever for a
-- mob stuck behind a wall or wandering away. The legacy raw count is still
-- available via the `stopToKillSmart = false` config.
local stopToKillState = { clearCount = 0, waitStartedAt = 0, loggedStop = false, clearSince = 0, sawHostile = false }

-- Canonical "hostile mobs around" count used by stop_to_kill.
-- Includes ADJACENT mobs (they're literally hitting the char), excludes:
--   - dead / different floor / out of 7x5 range
--   - creatures in ignoredCreatures list
--   - unreachable mobs (when stopToKillRequirePath is on) — wall-stuck etc.
--   - stuck mobs per ApproachTracker (summons that won't path)
-- Returns: count, hasFarReachable, hasAdjacent
local function countHostileMobsAround(shouldIgnore)
  local player = getPlayer()
  if not player then return 0, false, false end
  local playerPos = player:getPosition()
  if not playerPos then return 0, false, false end

  local requirePath = CaveBot.Config.get("stopToKillRequirePath")
  if requirePath == nil then requirePath = true end
  local stuckTimeout = CaveBot.Config.get("stopToKillStuckTimeout") or 3000
  local ApproachTracker = CaveBot.Extensions and CaveBot.Extensions.approach_tracker
  local now = g_clock.millis()
  local selfId = player:getId()

  -- Collect other players' positions once. Mobs adjacent to another player
  -- are considered "engaged with them" and excluded — we don't compete.
  local otherPlayerPositions = {}
  for _, sp in ipairs(g_map.getSpectators(playerPos, false) or {}) do
    if sp:isPlayer() and sp:getId() ~= selfId then
      local pp = sp:getPosition()
      if pp and pp.z == playerPos.z then
        table.insert(otherPlayerPositions, pp)
      end
    end
  end

  local count, hasFar, hasAdj = 0, false, false
  for _, c in ipairs(g_map.getSpectators(playerPos, false) or {}) do
    if c:isMonster() and not c:isDead() then
      local cp = c:getPosition()
      if cp and cp.z == playerPos.z then
        local dx = math.abs(cp.x - playerPos.x)
        local dy = math.abs(cp.y - playerPos.y)
        if dx <= 7 and dy <= 5 and (not shouldIgnore or not shouldIgnore(c)) then
          -- Engaged with another player? (any non-self player adjacent to the mob)
          local engagedOther = false
          for _, pp in ipairs(otherPlayerPositions) do
            if math.abs(cp.x - pp.x) <= 1 and math.abs(cp.y - pp.y) <= 1 then
              engagedOther = true
              break
            end
          end
          if not engagedOther then
            local isAdjacent = dx <= 1 and dy <= 1
            -- Adjacent mobs are always counted (they're literally hitting us).
            -- Reachability and "stuck" filters only apply to far mobs.
            local reachable = true
            if requirePath and not isAdjacent then
              if ScreenGrid and ScreenGrid.isReachable then
                reachable = ScreenGrid.isReachable(cp, false)
                if reachable == nil then
                  reachable = g_map.isSightClear(playerPos, cp, true)
                end
              else
                reachable = g_map.isSightClear(playerPos, cp, true)
              end
            end
            if reachable then
              local stuck = false
              if ApproachTracker and not isAdjacent then
                stuck = ApproachTracker.classifyStuck(c:getId(), cp, now, stuckTimeout) == 'stuck'
              end
              if not stuck then
                count = count + 1
                if isAdjacent then hasAdj = true else hasFar = true end
              end
            end
          end
        end
      end
    end
  end
  return count, hasFar, hasAdj
end

-- Finish-kill HP gate: counts "weak" valid threats around the player (reachable,
-- not ignored, not stuck, in 7x5 range), including adjacent mobs. Returns
-- (shouldHold, hasAdjacentWeak). Used by stop_to_kill and lure walk-resume to
-- avoid leaving when there are still X mobs below Y% HP — finish them first.
function CaveBot.shouldHoldForFinishKill(shouldIgnore)
  local minCount = CaveBot.Config.get("finishKillMobCount") or 0
  local hpPct = CaveBot.Config.get("finishKillHpPct") or 0
  if minCount <= 0 or hpPct <= 0 then return false, false end

  local ApproachTracker = CaveBot.Extensions and CaveBot.Extensions.approach_tracker
  local player = getPlayer()
  if not player then return false, false end
  local playerPos = player:getPosition()
  if not playerPos then return false, false end

  local stuckTimeout = CaveBot.Config.get("stopToKillStuckTimeout") or 3000
  local now = g_clock.millis()
  local weak, weakAdj = 0, 0
  local spectators = g_map.getSpectators(playerPos, false)
  for _, creature in ipairs(spectators or {}) do
    if creature:isMonster() and not creature:isDead() then
      local cpos = creature:getPosition()
      if cpos and cpos.z == playerPos.z then
        local dx = math.abs(cpos.x - playerPos.x)
        local dy = math.abs(cpos.y - playerPos.y)
        if dx <= 7 and dy <= 5 and (not shouldIgnore or not shouldIgnore(creature)) then
          local isAdjacent = dx <= 1 and dy <= 1
          -- Adjacent mobs bypass reachability/stuck filters (they're on us).
          local reachable = true
          if not isAdjacent then
            if ScreenGrid and ScreenGrid.isReachable then
              reachable = ScreenGrid.isReachable(cpos, false)
              if reachable == nil then
                reachable = g_map.isSightClear(playerPos, cpos, true)
              end
            else
              reachable = g_map.isSightClear(playerPos, cpos, true)
            end
          end
          if reachable then
            local stuck = false
            if ApproachTracker and not isAdjacent then
              stuck = ApproachTracker.classifyStuck(creature:getId(), cpos, now, stuckTimeout) == 'stuck'
            end
            if not stuck and creature:getHealthPercent() <= hpPct then
              weak = weak + 1
              if isAdjacent then weakAdj = weakAdj + 1 end
            end
          end
        end
      end
    end
  end

  if weak >= minCount then return true, weakAdj > 0 end
  return false, false
end

local function makeShouldIgnore()
  local ignoredList = CaveBot.Config.get("ignoredCreatures") or {}
  return function(creature)
    if not creature then return false end
    local name = creature:getName():lower()
    for _, ignored in ipairs(ignoredList) do
      if name == ignored:lower() then return true end
    end
    return false
  end
end

CaveBot.registerAction("stop_to_kill", "#FF5555", function(value, retries, prev)
  local pos = parsePosition(value)

  -- If waypoint has a position, must reach it within stopToKillDistance before stopping
  if pos then
    local playerPos = getPlayerPos()
    if not playerPos then return false end

    if pos.z ~= playerPos.z then return false end

    local stopDist = CaveBot.Config.get("stopToKillDistance") or 2
    local dx = math.abs(pos.x - playerPos.x)
    local dy = math.abs(pos.y - playerPos.y)

    if math.max(dx, dy) > stopDist - 1 then
      if retries >= 100 then return false end
      stopToKillState.clearCount = 0
      if CaveBot.walkTo(pos, 40, { ignoreNonPathable = true, precision = stopDist }) then
        return "retry"
      end
      return "retry"
    end
  end

  -- Timer arms the moment we arrive at the WP (after walk-to-position phase).
  -- waitStartedAt == 0 means "not yet at WP" — start it now.
  if stopToKillState.waitStartedAt == 0 then
    stopToKillState.clearCount = 0
    stopToKillState.waitStartedAt = g_clock.millis()
    stopToKillState.loggedStop = false
    stopToKillState.clearSince = 0
    stopToKillState.sawHostile = false
    local arriveCount = countHostileMobsAround(makeShouldIgnore())
    local cfgLeave = CaveBot.Config.get("creaturesToWalk") or 0
    stopToKillState.startedClock = os.date("%H:%M:%S")
    CaveBot.log(string.format("Reached Stop to Kill WP at %s, current %d/%d on screen",
      stopToKillState.startedClock, arriveCount, cfgLeave), "kill")
  end

  -- Two independent rules can hold the bot in place. Both must clear to leave:
  --   1) COUNT gate:  hostileCount > creaturesToWalk
  --   2) HP gate:     >= finishKillMobCount mobs around with HP <= finishKillHpPct
  -- Either gate triggered → keep waiting until stopToKillMaxWait fires.
  -- Timer starts at WP arrival (above) and keeps running through boxed-in too.
  local creaturesToWalk = CaveBot.Config.get("creaturesToWalk") or 0
  local maxWait = CaveBot.Config.get("stopToKillMaxWait") or 60000
  local shouldIgnore = makeShouldIgnore()
  local hostileCount, hasFar, hasAdj = countHostileMobsAround(shouldIgnore)
  local hpHold, hpAdjWeak = CaveBot.shouldHoldForFinishKill(shouldIgnore)

  local countGate = hostileCount > creaturesToWalk
  local hpGate = hpHold

  -- Both gates released → leave immediately.
  if not countGate and not hpGate then
    stopToKillState.waitStartedAt = 0
    stopToKillState.clearSince = 0
    stopToKillState.sawHostile = false
    local elapsedMs = g_clock.millis() - (stopToKillState.waitStartedAt > 0 and stopToKillState.waitStartedAt or g_clock.millis())
    local startedAt = stopToKillState.startedClock or "?"
    local resumedAt = os.date("%H:%M:%S")
    CaveBot.log(string.format("Leaving Stop to Kill WP, current %d/%d (started %s, resumed %s, %.1fs)",
      hostileCount, creaturesToWalk, startedAt, resumedAt, elapsedMs/1000), "kill")
    stopToKillState.startedClock = nil
    return true
  end

  -- At least one gate is holding. Mark that we did have to kill.
  stopToKillState.clearSince = 0
  if countGate then stopToKillState.sawHostile = true end

  -- maxWait hit: leave UNLESS finish-kill HP gate has an adjacent weak mob
  -- (don't abandon a mob about to die right next to us). Checked BEFORE the
  -- boxed-in branch so the timeout always wins.
  if maxWait > 0 and (g_clock.millis() - stopToKillState.waitStartedAt) >= maxWait then
    if not hpAdjWeak then
      if CaveBot.Extensions and CaveBot.Extensions.lure and CaveBot.Extensions.lure.armCreaturesToStopBypass then
        CaveBot.Extensions.lure.armCreaturesToStopBypass(3000)
      end
      stopToKillState.waitStartedAt = 0
      stopToKillState.clearSince = 0
      CaveBot.log(string.format("Stop to Kill WP timeout (%dms), leaving with %d/%d", maxWait, hostileCount, creaturesToWalk), "warn")
      return true
    end
  end

  -- Boxed-in (count gate, only adjacents reachable): keep slashing,
  -- timer keeps running (started at WP arrival, checked above).
  if countGate and hasAdj and not hasFar then
    CaveBot.delay(400)
    return "retry"
  end

  -- Keep waiting. Tighter cadence when only HP gate is active (mobs nearly dead).
  CaveBot.delay(countGate and 400 or 300)
  return "retry"
end)

-- Wait Lure: espera criaturas se aproximarem (lure mode)
CaveBot.registerAction("wait_lure", "#55FFAA", function(value, retries, prev)
  -- Se lure mode não está ativo, pular
  if not CaveBot.Config.get("lureMode") then
    return true
  end

  -- Verificar se há criaturas para lurar
  local lure = CaveBot.Extensions.lure
  if not lure then return true end

  -- Obter próximo waypoint como destino (para saber a direção)
  local targetPos = nil
  local actions = CaveBot.getActions()
  local currentIdx = CaveBot.getCurrentIndex()
  if actions and currentIdx then
    -- Procurar próximo waypoint com posição
    for i = currentIdx + 1, #actions do
      local action = actions[i]
      if action and (action.action == "node" or action.action == "goto" or action.action == "stand") then
        local x, y, z = action.value:match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)")
        if x then
          targetPos = {x = tonumber(x), y = tonumber(y), z = tonumber(z)}
          break
        end
      end
    end
  end

  -- Verificar se devemos esperar (criaturas atrás de nós)
  if lure.shouldWaitLure(targetPos) then
    CaveBot.delay(20)  -- Reduced from 200ms for faster lure response
    return "retry"
  end

  -- Não precisa esperar - continuar
  return true
end)

-- Wait Delay: walks to waypoint position (like node), waits configured ms, then advances
-- value = "x,y,z|delayMs"
local waitDelayState = { arrivedAt = nil }

CaveBot.registerAction("wait_delay", "#66CCFF", function(value, retries, prev)
  -- Parse position and delay from value
  local x, y, z, rest = value:match("(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*|?(.*)")
  if not x then
    error("Invalid cavebot wait_delay action value: " .. value)
    return false
  end

  local pos = {x = tonumber(x), y = tonumber(y), z = tonumber(z)}
  local delayMs = tonumber(rest) or 1000

  if retries >= 200 then return false end

  local playerPos = getPlayerPos()
  if not playerPos then return false end

  if pos.z ~= playerPos.z then return false end

  -- Check if player reached the waypoint (same as node behavior)
  local nodeDistance = CaveBot.Config.get("nodeDistance") or 2
  local dx = math.abs(pos.x - playerPos.x)
  local dy = math.abs(pos.y - playerPos.y)

  if math.max(dx, dy) > nodeDistance - 1 then
    -- Not arrived yet - walk to position
    waitDelayState.arrivedAt = nil
    if CaveBot.walkTo(pos, 40, { ignoreNonPathable = true, precision = nodeDistance }) then
      return "retry"
    end
    return "retry"
  end

  -- Arrived at position - start counting delay
  if not waitDelayState.arrivedAt then
    waitDelayState.arrivedAt = g_clock.millis()
    CaveBot.log(string.format("Wait Delay WP reached, waiting %dms", delayMs), "action")
  end

  -- Check if delay has elapsed
  local elapsed = g_clock.millis() - waitDelayState.arrivedAt
  if elapsed >= delayMs then
    waitDelayState.arrivedAt = nil
    CaveBot.log("Wait Delay finished", "action")
    return true
  end

  -- Still waiting
  CaveBot.delay(math.min(100, delayMs - elapsed))
  return "retry"
end)

-- Stop Cavebot: when reached, disables the cavebot (turns it off).
-- Position-less marker (just executes the stop on arrival).
CaveBot.registerAction("stop_cavebot", "#FF6666", function(value, retries, prev)
  local hr = modules.game_helper and modules.game_helper.hunting_recorderModule
  if hr and hr.stopWalk then
    hr.stopWalk()
  end
  if modules.game_helper and modules.game_helper.stopCavebotPlaying then
    modules.game_helper.stopCavebotPlaying()
  end
  if CaveBot.setOff then
    CaveBot.setOff()
  end
  if modules.game_textmessage and modules.game_textmessage.displayGameMessage then
    modules.game_textmessage.displayGameMessage("[Cavebot] Stopped by waypoint")
  end
  CaveBot.log("Stop Cavebot WP reached — cavebot OFF", "stop")
  return true
end)

-- Start Lure: ativa o lureMode no backend ao ser alcançado.
-- Para os waypoints start_lure/stop_lure funcionarem o jogador precisa
-- deixar o toggle manual de "Lure Mode" desligado, deixando o cavebot
-- controlar o estado dinamicamente via waypoints.
CaveBot.registerAction("start_lure", "#55FFAA", function(value, retries, prev)
  if CaveBot.Config and CaveBot.Config.set then
    CaveBot.Config.set("lureMode", true)
  end
  local count = countHostileMobsAround(makeShouldIgnore())
  CaveBot.log(string.format("Start Lure Mode WP, current %d creatures on screen", count), "lure")
  return true
end)

-- Stop Lure: desativa o lureMode no backend ao ser alcançado.
CaveBot.registerAction("stop_lure", "#55FFAA", function(value, retries, prev)
  if CaveBot.Config and CaveBot.Config.set then
    CaveBot.Config.set("lureMode", false)
  end
  local count = countHostileMobsAround(makeShouldIgnore())
  CaveBot.log(string.format("End Lure Mode WP, current %d creatures on screen", count), "lure")
  return true
end)

-- Special: área bloqueada (não faz nada, apenas marca)
CaveBot.registerAction("special", "#888888", function(value, retries, prev)
  return true
end)

-- ============================================================================
-- AÇÕES DE CIDADE (Depositer, Bank, Travel)
-- ============================================================================

-- Deposit: deposita itens no depot/stash
-- value = "x,y,z|depot" ou "x,y,z|stash" ou "x,y,z" (default: depot)
CaveBot.registerAction("deposit", "#9966FF", function(value, retries, prev)
  local player = getPlayer()
  if not player then return true end

  local playerPos = getPlayerPos()
  if not playerPos then return true end

  -- Parse value - pode ter posição e tipo
  local pos, depositType
  local parts = value:split("|")
  if parts[1] then
    pos = parsePosition(parts[1])
    depositType = parts[2] and parts[2]:lower() or "depot"
  else
    pos = parsePosition(value)
    depositType = "depot"
  end

  -- Se tem posição, primeiro ir até ela
  if pos then
    if pos.z ~= playerPos.z then return false end

    -- Verificar se está perto o suficiente (1 tile)
    local dx = math.abs(pos.x - playerPos.x)
    local dy = math.abs(pos.y - playerPos.y)
    if math.max(dx, dy) > 1 then
      if retries >= 100 then return false end
      if CaveBot.walkTo(pos, 40, { ignoreNonPathable = true, precision = 1 }) then
        return "retry"
      end
      return "retry"
    end
  end

  -- Estamos na posição correta - executar lógica de deposit
  local depositRetries = retries - 100
  if depositRetries < 0 then depositRetries = 0 end

  -- Abrir depot se necessário
  if depositRetries == 0 then
    -- Procurar depot locker perto
    if pos then
      local tile = g_map.getTile(pos)
      if tile then
        local topThing = tile:getTopUseThing()
        if topThing then
          g_game.use(topThing)
          CaveBot.delay(500)
          return "retry"
        end
      end
    end
    CaveBot.delay(300)
    return "retry"
  end

  -- Verificar se depot está aberto
  local depotContainer = nil
  for _, container in pairs(g_game.getContainers()) do
    local name = container:getName():lower()
    if name:find("depot") or name:find("locker") then
      depotContainer = container
      break
    end
  end

  if not depotContainer then
    if depositRetries < 10 then
      CaveBot.delay(300)
      return "retry"
    end
    return false -- Não conseguiu abrir depot
  end

  -- Depositar itens (usar stash se configurado)
  if depositType == "stash" then
    -- Usar quick loot stash
    if g_game.stashItems then
      g_game.stashItems()
      CaveBot.delay(500)
    end
  else
    -- Depositar itens manualmente - mover itens para depot
    -- TODO: Implementar lógica de mover itens específicos
    -- Por enquanto, usar stash como fallback
    if g_game.stashItems then
      g_game.stashItems()
      CaveBot.delay(500)
    end
  end

  if depositRetries >= 5 then
    return true -- Terminou depositar
  end

  CaveBot.delay(300)
  return "retry"
end)

-- Bank: deposita ou saca gold do banco
-- value = "x,y,z|deposit" ou "x,y,z|withdraw|amount" ou "x,y,z|balance"
CaveBot.registerAction("bank", "#FFD700", function(value, retries, prev)
  local player = getPlayer()
  if not player then return true end

  local playerPos = getPlayerPos()
  if not playerPos then return true end

  -- Parse value
  local parts = value:split("|")
  local pos = parsePosition(parts[1] or value)
  local bankAction = parts[2] and parts[2]:lower() or "deposit"
  local amount = parts[3] and tonumber(parts[3]) or 0

  -- Se tem posição, primeiro ir até ela
  if pos then
    if pos.z ~= playerPos.z then return false end

    local dx = math.abs(pos.x - playerPos.x)
    local dy = math.abs(pos.y - playerPos.y)
    if math.max(dx, dy) > 3 then
      if retries >= 100 then return false end
      if CaveBot.walkTo(pos, 40, { ignoreNonPathable = true, precision = 3 }) then
        return "retry"
      end
      return "retry"
    end
  end

  -- Executar ação do banco
  local bankRetries = retries - 100
  if bankRetries < 0 then bankRetries = 0 end

  if bankRetries == 0 then
    sayNpc("hi")
    CaveBot.delay(600)
    return "retry"
  elseif bankRetries == 1 then
    if bankAction == "deposit" then
      sayNpc("deposit all")
    elseif bankAction == "withdraw" then
      sayNpc("withdraw " .. tostring(amount))
    elseif bankAction == "balance" then
      sayNpc("balance")
    end
    CaveBot.delay(600)
    return "retry"
  elseif bankRetries == 2 then
    sayNpc("yes")
    CaveBot.delay(600)
    return "retry"
  elseif bankRetries >= 3 then
    return true
  end

  return "retry"
end)

-- Travel: viaja usando boat/carpet
-- value = "x,y,z|destination" ou "npcName|destination"
CaveBot.registerAction("travel", "#00CED1", function(value, retries, prev)
  local player = getPlayer()
  if not player then return true end

  local playerPos = getPlayerPos()
  if not playerPos then return true end

  -- Parse value
  local parts = value:split("|")
  local firstPart = parts[1] or ""
  local destination = parts[2] or ""

  -- Verificar se primeiro parte é posição ou nome de NPC
  local pos = parsePosition(firstPart)
  local npcName = nil

  if not pos then
    -- É nome de NPC
    npcName = firstPart
  end

  -- Se tem posição, primeiro ir até ela
  if pos then
    if pos.z ~= playerPos.z then return false end

    local dx = math.abs(pos.x - playerPos.x)
    local dy = math.abs(pos.y - playerPos.y)
    if math.max(dx, dy) > 3 then
      if retries >= 100 then return false end
      if CaveBot.walkTo(pos, 40, { ignoreNonPathable = true, precision = 3 }) then
        return "retry"
      end
      return "retry"
    end
  end

  -- Executar travel
  local travelRetries = retries - 100
  if travelRetries < 0 then travelRetries = 0 end

  if travelRetries == 0 then
    sayNpc("hi")
    CaveBot.delay(600)
    return "retry"
  elseif travelRetries == 1 then
    -- Falar destino
    sayNpc(destination)
    CaveBot.delay(600)
    return "retry"
  elseif travelRetries == 2 then
    sayNpc("yes")
    CaveBot.delay(1000)
    return "retry"
  elseif travelRetries >= 3 then
    -- Verificar se mudou de posição (viajou)
    local newPos = getPlayerPos()
    if newPos and pos then
      if newPos.x ~= pos.x or newPos.y ~= pos.y or newPos.z ~= pos.z then
        return true -- Viajou com sucesso
      end
    end
    if travelRetries >= 10 then
      return false -- Falhou em viajar
    end
    CaveBot.delay(500)
    return "retry"
  end

  return "retry"
end)

-- Door: abre a porta na posicao e atravessa.
-- Consulta CavebotDoors (doors_data.lua): se o tile tem um id de porta FECHADA,
-- da use e aguarda virar id de porta ABERTA; quando aberta (ou walkable), ANDA.
-- value = "x,y,z"
local function getDoorIdOnTile(tile)
  if not tile then return nil end
  -- Preferir o item "de uso" do topo (a propria porta), depois varrer os itens.
  local top = tile:getTopUseThing()
  if top and top.getId and CavebotDoors and CavebotDoors.isKnownDoor(top:getId()) then
    return top:getId()
  end
  local items = tile:getItems()
  if items then
    for _, item in ipairs(items) do
      if item and item.getId and CavebotDoors and CavebotDoors.isKnownDoor(item:getId()) then
        return item:getId()
      end
    end
  end
  return nil
end

CaveBot.registerAction("door", "#8B4513", function(value, retries, prev)
  local pos = parsePosition(value)
  if not pos then
    error("Invalid cavebot door action value: " .. value)
    return false
  end

  if retries >= 40 then return false end

  local playerPos = getPlayerPos()
  if not playerPos then return false end

  if pos.z ~= playerPos.z then return false end

  local dx = math.abs(pos.x - playerPos.x)
  local dy = math.abs(pos.y - playerPos.y)
  local dist = math.max(dx, dy)

  -- Ja estamos em cima do tile da porta (atravessamos) -> concluido.
  if dist == 0 then
    return true
  end

  -- Aproximar ate ficar adjacente (1 sqm) da porta.
  if dist > 1 then
    if CaveBot.walkTo(pos, 40, { ignoreNonPathable = true, precision = 1 }) then
      return "retry"
    end
    return "retry"
  end

  -- Adjacente: inspecionar o estado da porta.
  local tile = g_map.getTile(pos)
  if not tile then return false end

  local doorId = getDoorIdOnTile(tile)

  -- Porta trancada ("It is locked"): nao passa sem chave.
  if doorId and CavebotDoors and CavebotDoors.isLocked(doorId) then
    -- Pode ser que ainda haja outro item util no tile (raro); senao falha.
    CaveBot.log("Door locked at " .. value .. " (id " .. doorId .. ")", "action")
    return false
  end

  -- Porta ABERTA: atravessar andando ate o tile da porta (precision 0).
  if (doorId and CavebotDoors and CavebotDoors.isOpen(doorId)) or
     (not doorId and tile:isWalkable(false)) then
    CaveBot.walkTo(pos, 40, { ignoreNonPathable = true, precision = 0, allowFloorChangeDest = true })
    return "retry"  -- volta no proximo tick; quando dist==0 retorna true
  end

  -- Porta FECHADA conhecida (ou item de porta nao mapeado): dar use para abrir.
  local topThing = tile:getTopUseThing()
  if topThing then
    g_game.use(topThing)
    CaveBot.delay(CaveBot.Config.get("useDelay") + CaveBot.Config.get("ping"))
  end
  return "retry"
end)

return CaveBot.Actions
