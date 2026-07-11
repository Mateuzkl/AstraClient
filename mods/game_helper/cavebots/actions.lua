-- CaveBot Actions Module
-- Sistema de ações registráveis baseado na referência game_bot
-- Inclui ações básicas + ações especiais do usuário

CaveBot = CaveBot or {}
CaveBot.Actions = {}
CaveBot.Extensions = CaveBot.Extensions or {}

-- Utils compartilhados (mesma via que move.lua). Necessario para avaliar a
-- condicao de stamina do Goto (acao "gotolabel") em runtime.
local CavebotUtils = dofile("/game_helper/cavebots/utils.lua")

-- Fonte UNICA de verdade "tile muda de andar?" (teleport OU attr 252), exposta no
-- CaveBot global p/ os consumidores fora do dir cavebots (walking pathCrossesFloorChange,
-- map avoidTrap, lure, helper AttackPos, scripting). Zero tabela de ids, zero minimap.
CaveBot.isFloorChangeTile = CavebotUtils.isFloorChangeTile

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
-- OBSTÁCULO POR CRIATURA: distinguir "monstro no caminho" de "parede"
-- ============================================================================

-- Chamado APÓS um walkTo (criaturas = OBSTÁCULO) NÃO ter conseguido andar, ou
-- seja: já sabemos que não há rota contornando as criaturas.
-- Retorna true quando existe rota se IGNORARMOS as criaturas: significa que são
-- criaturas bloqueando o único caminho ⇒ o waypoint deve ser AGUARDADO (o
-- monstro anda / o targeting mata), em vez de pular o waypoint ou empurrar.
-- Retorna false para parede/inalcançável (nem ignorando criaturas há caminho).
-- PERF: um único findPath. No caso "esperando por criatura" o destino é
-- alcançável ignorando criaturas, então o Dijkstra para cedo (barato). Só no
-- caso "parede" (raro, e limitado pelo timeout de desistência) ele varre a área.
local function blockedByCreatureOnly(playerPos, pos, maxDist, precision)
  if not playerPos or not pos then return false end
  local pathIgnoring = CaveBot.Map.findPath(playerPos, pos, maxDist, {
    ignoreNonPathable = true, ignoreCreatures = true, precision = precision
  })
  return pathIgnoring ~= nil and #pathIgnoring > 0
end

-- Log throttled (a cada 3s) de "esperando a criatura sair do caminho".
local lastCreatureWaitLog = 0
local function logWaitingForCreature()
  local now = g_clock.millis()
  if now - lastCreatureWaitLog > 3000 then
    lastCreatureWaitLog = now
    CaveBot.log("Path blocked by a creature - waiting for it to move", "action")
  end
end

-- ============================================================================
-- Z-RECOVERY: Recuperação automática quando player está no Z errado
-- ============================================================================

local Z_RECOVERY_RANGE = 5           -- raio de busca por tiles de floor change
local Z_RECOVERY_MAX_RETRIES = 8     -- máximo de replanejamentos de caminho antes de desistir
local Z_RECOVERY_MAX_DRIFT = 5       -- max sqm de distância da última posição boa
local Z_RECOVERY_INTERVAL = 1000     -- intervalo mínimo entre replanejamentos de caminho (1s)
local Z_SERVER_TIMEOUT = 1200        -- ms aguardando o oráculo do servidor antes do fallback client-side

-- [DIAG z-recovery] Logs por ponto de decisao p/ entender por que o recovery nao roda
-- num cenario. Flip Z_DEBUG=false p/ silenciar (ou remover depois). Escreve no CavebotLog
-- (cat "info"), prefixo [ZREC]. zdbg = uma vez; zdbgT = throttled por chave (ramos que
-- repetem todo tick, sem floodar).
local Z_DEBUG = false
local zdbgLast = {}
local function zdbg(msg)
  if Z_DEBUG and CaveBot.log then CaveBot.log("[ZREC] " .. msg, "info") end
end
local function zdbgT(key, ms, msg)
  if not Z_DEBUG then return end
  local now = g_clock.millis()
  if zdbgLast[key] and (now - zdbgLast[key]) < ms then return end
  zdbgLast[key] = now
  zdbg(msg)
end
-- [DIAG] Dump da varredura ao redor do player (raio Z_RECOVERY_RANGE). Loga cada tile que
-- E floor-change (teleport/attr252) OU tem cor de escada no minimap (210-213) -- assim da
-- p/ ver se ha um SQM de subida/descida perto que o isFloorChangeTile talvez NAO pegue
-- (ex. escada custom sem attr252). fc=verdade-item, tp->z=destino teleport, mc=cor minimap.
local function zScanDump(playerPos, targetZ)
  if not Z_DEBUG or not playerPos then return end
  local range = Z_RECOVERY_RANGE
  local found = 0
  for dist = 0, range do
    for dx = -dist, dist do
      for dy = -dist, dist do
        if dist == 0 or math.abs(dx) == dist or math.abs(dy) == dist then
          local p = { x = playerPos.x + dx, y = playerPos.y + dy, z = playerPos.z }
          local tile = g_map.getTile(p)
          if tile then
            local tpZ = nil
            for _, thing in ipairs(tile:getThings() or {}) do
              if thing and thing:isItem() and thing.getTeleportDestination then
                local ok, d = pcall(thing.getTeleportDestination, thing)
                if ok and d then tpZ = d.z end
              end
            end
            local isFC = CavebotUtils.isFloorChangeTile(p)
            local mc = g_map.getMinimapColor(p)
            local stairsColor = mc and mc >= 210 and mc <= 213
            if isFC or tpZ or stairsColor then
              found = found + 1
              zdbg(string.format("  scan %d,%d,%d fc=%s tp->z=%s mc=%s dist=%d",
                p.x, p.y, p.z, tostring(isFC), tostring(tpZ), tostring(mc), dist))
            end
          end
        end
      end
    end
  end
  zdbg(string.format("SCAN raio %d @ %d,%d,%d (targetZ=%s): %d candidato(s)",
    range, playerPos.x, playerPos.y, playerPos.z, tostring(targetZ), found))
end


-- Retorna o Thing (item) de floor change no tile, ou nil. Diferente de
-- getTopUseThing: garante que usamos o PROPRIO floor-change (buraco/alcapao/teleport)
-- e nao loot/container empilhado por cima no mesmo SQM. Verdade do item (attr 252 ou
-- teleport), sem tabela de ids.
local function getFloorChangeThing(pos)
  if not pos then return nil end
  local tile = g_map.getTile(pos)
  if not tile then return nil end
  local canThingType = g_things and g_things.getThingType
  for _, thing in ipairs(tile:getThings() or {}) do
    if thing and thing:isItem() then
      if thing.getTeleportDestination then
        local ok, dest = pcall(thing.getTeleportDestination, thing)
        if ok and dest then return thing end
      end
      if canThingType then
        local itemType = g_things.getThingType(thing:getId(), ThingCategoryItem)
        if itemType and itemType:hasAttribute(252) then return thing end
      end
    end
  end
  return nil
end

-- Tile com teleport: getTeleportDestination() devolve a posicao destino p/ TP e nil
-- p/ item comum (push_luavalue empurra nil quando !isValid). Pega TP de QUALQUER id,
-- inclusive custom nao catalogado (ex. 56618) -- a MESMA verificacao do recorder.
local function tileHasTeleport(pos)
  local tile = pos and g_map.getTile(pos)
  if not tile then return false end
  for _, thing in ipairs(tile:getThings() or {}) do
    if thing and thing:isItem() and thing.getTeleportDestination then
      local ok, dest = pcall(thing.getTeleportDestination, thing)
      if ok and dest then return true end
    end
  end
  return false
end

-- Waypoint que exige PISAR exatamente no SQM p/ efetivar a travessia: escada/rampa/
-- buraco (attr 252) OU teleport -- a MESMA verdade do isFloorChangeTile (sem cor de
-- minimap). goto/node/stand usam p/ dar precision 0 + allowFloorChangeDest (pisar) e
-- concluir a travessia ao chegar, em vez de parar adjacente (o TP nunca acionava) ou
-- voltar via Z-recovery.
local function tileRequiresStep(pos)
  return CavebotUtils.isFloorChangeTile(pos)
end

-- Encontra o floor-change mais proximo num raio (aneis, de perto p/ longe). Fallback
-- client-side do Z-recovery -- so roda quando o oraculo do servidor esta mudo. Usa a
-- verdade do item (CavebotUtils.isFloorChangeTile), sem tabela de ids.
-- LIMITACAO REAL: o .dat do cliente NAO codifica direcao (up/down) de escada/buraco --
-- so o servidor sabe (por isso o oraculo existe). Entao aqui e DIRECAO-AGNOSTICO para
-- floor-change de .dat: pega o mais proximo e tenta; se for o lado errado, o hop-reset
-- + MAX_RETRIES do walkToFloorChange corrigem/desistem. UNICO sinal de direcao no
-- cliente: TELEPORT carrega destino (getTeleportDestination), entao um TP so e aceito
-- se seu dest.z APROXIMA do targetZ (nunca escolhe TP que afasta).
local function findNearbyFloorChange(origin, range, playerZ, targetZ)
  if not origin then return nil end
  range = range or Z_RECOVERY_RANGE
  local curGap = (targetZ and playerZ) and math.abs(targetZ - playerZ) or nil

  for dist = 0, range do
    for dx = -dist, dist do
      for dy = -dist, dist do
        if dist == 0 or math.abs(dx) == dist or math.abs(dy) == dist then
          local checkPos = {x = origin.x + dx, y = origin.y + dy, z = origin.z}
          local tile = g_map.getTile(checkPos)
          if tile then
            -- TELEPORT: unico com direcao conhecida -- so aceita se aproxima do targetZ.
            local hasTp, tpApproaches = false, false
            for _, thing in ipairs(tile:getThings() or {}) do
              if thing and thing:isItem() and thing.getTeleportDestination then
                local ok, dest = pcall(thing.getTeleportDestination, thing)
                if ok and dest then
                  hasTp = true
                  if not curGap or math.abs(targetZ - dest.z) < curGap then
                    tpApproaches = true
                  end
                end
              end
            end
            if hasTp then
              if tpApproaches then return checkPos end
            elseif CavebotUtils.isFloorChangeTile(checkPos) then
              -- Escada/rampa/buraco (.dat) -- direcao desconhecida no cliente: serve.
              return checkPos
            end
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

-- Travessia por TELEPORT via waypoint. Quando o handler chega/pisa num waypoint cujo
-- tile e teleport, o char pisa e o servidor o teleporta -> o cavebot deve AVANCAR
-- SEQUENCIALMENTE p/ o proximo waypoint. Sem isto ele (a) tentava voltar ao TP de
-- origem (mesmo Z) ou (b) caia no Z-recovery, que reancorava no waypoint mais PROXIMO
-- geometricamente -- nao o proximo da sequencia -- pulando os waypoints do trajeto.
-- Deteccao do salto por DOIS criterios (robusto):
--   armado: o handler viu o waypoint-TP no mesmo Z e registrou o indice; OU
--   origem: o salto saiu do (ou adjacente ao) proprio waypoint atual (`teleportFrom`,
--           conhecido no momento do salto -- cobre o TP sair de vista / salto durante
--           o doWalking, quando o handler nao rodou perto p/ armar o indice).
local awaitingTeleportIdx = nil
local teleportFrom = nil  -- {x,y,z,at} da origem do ultimo salto do player

-- Chamado por walking.lua onPositionChange (passa oldPos = origem do salto).
function CaveBot.notifyFloorChange(from)
  if not from then return end
  teleportFrom = { x = from.x, y = from.y, z = from.z, at = g_clock.millis() }
  -- [DIAG temporario] confirma que o onPositionChange do walker dispara.
  if CaveBot.isOn and CaveBot.isOn() then
    CaveBot.log(string.format("[TP] floor-change de %d,%d,%d", from.x, from.y, from.z), "info")
  end
end

-- Gerencia a travessia por teleport no topo de goto/node/stand. Retorna:
--   "advance" -> a travessia concluiu (ou timeout): avance (return true)
--   "wait"    -> em cima do TP aguardando o servidor teleportar: aguarde (return "retry")
--   nil       -> nao e um waypoint-teleport relevante agora: siga o fluxo normal
local function teleportCrossing(pos, playerPos, retries)
  local curIdx = (CaveBot.getCurrentIndex and CaveBot.getCurrentIndex()) or 0
  local tf = teleportFrom
  if tf and (g_clock.millis() - tf.at) < 1500 then
    local doneArmed = (awaitingTeleportIdx == curIdx)
    local doneFrom = (tf.z == pos.z)
      and math.max(math.abs(tf.x - pos.x), math.abs(tf.y - pos.y)) <= 1
    if doneArmed or doneFrom then
      awaitingTeleportIdx = nil
      teleportFrom = nil
      CaveBot.log("Teleport atravessado - seguindo para o proximo waypoint", "action")
      return "advance"
    end
  end
  -- Waypoint atual e um teleport e estamos no MESMO Z (indo pisar / em cima): arma o
  -- indice p/ concluir via o ramo acima quando o salto ocorrer.
  if pos.z == playerPos.z and tileHasTeleport(pos) then
    if awaitingTeleportIdx ~= curIdx then
      awaitingTeleportIdx = curIdx
      teleportFrom = nil  -- descarta salto stale ao comecar a aguardar ESTE
    end
    -- Ja em cima do TP: aguarda parado o servidor teleportar (nao avanca/anda -- isso
    -- largaria a travessia no meio). Timeout de seguranca se o TP nao acionar.
    if pos.x == playerPos.x and pos.y == playerPos.y then
      if retries >= 100 then awaitingTeleportIdx = nil; return "advance" end
      return "wait"
    end
  end
  return nil
end

-- Estado do Z-recovery (persistente entre chamadas). Modelo HÍBRIDO: pergunta ao
-- servidor (que conhece o mapa real: cada floor-change, direção, destino de
-- teleport e alcançabilidade) qual floor-change usar; cai na heurística client-
-- side (tabela de IDs) só se o servidor não responder dentro do timeout.
-- IDs de ferramentas do inventário (mesmos das actions "rope"/"hole" do cavebot).
-- Corda p/ subir rope spot; pá p/ cavar buraco e descer. Canivetes multiuso
-- (9594/9596/9598) funcionam como ambos no servidor.
local ROPE_IDS = {3003, 9596, 9598, 9594}
local SHOVEL_IDS = {5710, 9596, 9598, 9594}

local zRecovery = {
  active = false,
  retries = 0,          -- replanejamentos de caminho (throttle-gated)
  lastZ = nil,          -- Z do player quando o episódio começou (detecta hop)
  targetWpZ = nil,      -- Z do waypoint alvo
  lastAttemptTime = 0,  -- timestamp do último replanejamento de caminho
  -- alvo de floor-change resolvido (pelo servidor OU pelo fallback client-side)
  fcPos = nil,          -- {x,y,z} do tile de floor-change
  fcKind = "step",      -- "step" = pisar (escada/rampa/buraco/teleport); "rope" = usar corda (subir buraco)
  fcFallback = false,   -- true = veio do fallback client-side (usa item por ID ao chegar)
  -- oráculo do servidor
  reqId = 0,            -- nonce do request atual (descarta respostas obsoletas)
  reqSentAt = 0,        -- quando pediu ao servidor
  answer = nil,         -- nil = aguardando; false = miss; {x,y,z,kind} = hit
  usingFallback = false,-- true após timeout: ignora o servidor neste episódio
}

local zReqCounter = 0

local function resetZRecovery()
  zRecovery.active = false
  zRecovery.retries = 0
  zRecovery.lastZ = nil
  zRecovery.targetWpZ = nil
  zRecovery.fcPos = nil
  zRecovery.fcKind = "step"
  zRecovery.fcFallback = false
  zRecovery.reqSentAt = 0
  zRecovery.answer = nil
  zRecovery.usingFallback = false
end

-- Reset completo (estado + throttle + última posição boa). Chamado no OFF e na
-- troca de waypoints para não vazar estado stale de uma hunt para a próxima
-- (ex.: um lastGoodPos antigo faria o drift-check abortar o recovery cedo).
function CaveBot.resetZRecoveryState()
  resetZRecovery()
  zRecovery.lastAttemptTime = 0
  lastGoodPos = nil
  awaitingTeleportIdx = nil
  teleportFrom = nil
end

-- Envia o request de floor-change ao servidor (que já sabe a posição do player;
-- só precisa do waypoint alvo). Marca o episódio como aguardando resposta. Sem
-- protocolo, força o fallback client-side imediato.
local function requestServerRecovery(targetPos)
  zReqCounter = zReqCounter + 1
  zRecovery.reqId = zReqCounter
  zRecovery.answer = nil
  zRecovery.reqSentAt = g_clock.millis()
  zdbg(string.format("REQUEST servidor: target=%d,%d,%d n=%d", targetPos.x, targetPos.y, targetPos.z, zRecovery.reqId))

  local proto = g_game.getProtocolGame and g_game.getProtocolGame()
  if not proto then
    zdbg("sem protocolo (getProtocolGame nil) -> fallback client-side")
    zRecovery.usingFallback = true
    return
  end
  local opcode = CAVEBOT_ZRECOVERY_OPCODE or 209
  local ok = pcall(function()
    proto:sendExtendedOpcode(opcode, json.encode({
      x = targetPos.x, y = targetPos.y, z = targetPos.z, n = zRecovery.reqId,
    }))
  end)
  if not ok then
    zdbg("sendExtendedOpcode FALHOU -> fallback client-side")
    zRecovery.usingFallback = true
  end
end

-- Handler da resposta do servidor (chamado por onHelperCavebotZRecovery). Só aceita
-- a resposta do request ATUAL (nonce), descartando respostas obsoletas de um
-- episódio já superado por uma troca de andar.
function CaveBot.onZRecoveryResponse(buffer)
  local ok, msg = pcall(function() return json.decode(buffer) end)
  if not ok or type(msg) ~= "table" then zdbg("resposta do servidor INVALIDA (json falhou)"); return end
  if tonumber(msg.n) ~= zRecovery.reqId then
    zdbg(string.format("resposta DESCARTADA: nonce %s != atual %s (obsoleta)", tostring(msg.n), tostring(zRecovery.reqId)))
    return
  end
  if msg.ok and msg.x and msg.y and msg.z then
    -- kind válido do servidor: step (pisar) / rope / shovel / use (ladder).
    -- Qualquer outro (ou ausente) cai em "step" por segurança.
    local k = msg.kind
    if k ~= "rope" and k ~= "shovel" and k ~= "use" then k = "step" end
    zRecovery.answer = {
      x = tonumber(msg.x), y = tonumber(msg.y), z = tonumber(msg.z),
      kind = k,
    }
    CaveBot.log(string.format("Z-Recovery (server): %s at %d,%d,%d",
      zRecovery.answer.kind, zRecovery.answer.x, zRecovery.answer.y, zRecovery.answer.z), "action")
  else
    zRecovery.answer = false
    CaveBot.log("Z-Recovery (server): no reachable floor-change", "action")
  end
end

-- Caminho ÚNICO de desistência do Z-recovery. Em vez de pular cegamente para o
-- próximo waypoint (wp+1), tenta reancorar a rota no waypoint alcançável mais
-- próximo no MESMO Z em que o player está agora. Só pula de fato (com um respiro
-- para não varrer a lista a 50Hz) quando não há âncora possível.
local function giveUpZRecovery(playerPos)
  local wpIdx = findReachableWaypointOnSameZ(playerPos)
  resetZRecovery()
  if wpIdx then
    zdbg(string.format("GIVE UP -> reancora no waypoint #%d (alcancavel no Z atual)", wpIdx))
    CaveBot.gotoIndex(wpIdx)
    return "retry"
  end
  zdbg("GIVE UP -> nenhum waypoint alcancavel no Z atual, PULA (delay 200)")
  CaveBot.delay(200)
  return false
end

-- Exposto para o respawn (hunting_recorder.onRespawnSignal): reposiciona o indice da
-- rota no waypoint alcancavel mais proximo no Z ATUAL do player, em vez de deixar o
-- indice stale apontando pro meio da hunt noutro Z -- o que faria o Z-recovery tentar
-- "corrigir" a partir do templo, subindo/descendo a escada errada e saindo do PZ.
-- Reusa a MESMA verificacao de alcancabilidade do giveUpZRecovery (pathfinding
-- single-floor + gotoIndex). Retorna true se reancorou; false se nao ha waypoint
-- alcancavel neste Z (o caller decide o fallback -- hoje desligar o walker + avisar).
function CaveBot.reanchorToReachableWaypoint(playerPos)
  if not playerPos then return false end
  local idx = findReachableWaypointOnSameZ(playerPos)
  if not idx then return false end
  return CaveBot.gotoIndex(idx) == true
end

-- Aciona o floor-change ao chegar adjacente/em cima. Retorna:
--   "done"    = acionou (usou a ferramenta / usou o item do tile)
--   "noItem"  = falta a ferramenta no inventário (corda/pá) -> desistir
--   "noThing" = tile sem thing usável (sumiu) -> re-resolver
local function triggerFloorChange(target, kind)
  local tile = g_map.getTile(target)
  local thing = tile and tile:getTopUseThing()
  if not thing then return "noThing" end

  if kind == "use" then
    -- Ladder: USAR o próprio item do tile (sobe 1 andar).
    g_game.use(thing)
    CaveBot.delay(CaveBot.Config.get("useDelay") + CaveBot.Config.get("ping"))
    return "done"
  end

  -- rope/shovel: usar a ferramenta do inventário no tile.
  local toolIds = (kind == "shovel") and SHOVEL_IDS or ROPE_IDS
  for _, itemId in ipairs(toolIds) do
    if g_game.findPlayerItem(itemId, -1) then
      g_game.useInventoryItemWith(itemId, thing)
      CaveBot.delay(CaveBot.Config.get("useDelay") + CaveBot.Config.get("ping"))
      return "done"
    end
  end
  return "noItem"
end

-- Caminha até o tile de floor-change já resolvido (zRecovery.fcPos) e o aciona
-- conforme o tipo. Reusado pelo caminho servidor e pelo fallback client-side.
--   "step":   anda ATÉ o tile e pisa (escadas/rampas/buracos-down/teleports).
--   "rope":   fica adjacente e usa corda (sobe buraco).
--   "shovel": fica adjacente e usa pá (cava buraco e desce).
--   "use":    fica adjacente e usa a escada/ladder (sobe).
-- fcFallback (client-side): ao chegar em cima do tile, usa o item por ID.
local function walkToFloorChange(playerPos)
  local target = zRecovery.fcPos
  local dx = math.abs(target.x - playerPos.x)
  local dy = math.abs(target.y - playerPos.y)
  local dist = math.max(dx, dy)

  local kind = zRecovery.fcKind
  local needTool = (kind == "rope" or kind == "shovel" or kind == "use")
  local arrived = needTool and (dist <= 1) or (dist == 0)
  zdbgT("walkfc", 500, string.format("walkToFC alvo=%d,%d,%d kind=%s dist=%d arrived=%s retries=%d",
    target.x, target.y, target.z, tostring(kind), dist, tostring(arrived), zRecovery.retries))

  if arrived then
    if needTool then
      local res = triggerFloorChange(target, kind)
      if res == "noThing" then
        resetZRecovery()  -- alvo sumiu: re-resolver no próximo tick
        CaveBot.delay(200)
        return "retry"
      elseif res == "noItem" then
        CaveBot.log("Z-Recovery: missing tool for '" .. kind .. "'", "action")
        return giveUpZRecovery(playerPos)
      end
      -- "done": segue para o guard abaixo (aguarda a troca de andar)
    elseif zRecovery.fcFallback then
      -- Fallback client-side: usar o item por ID (buracos/alçapões que exigem uso).
      local thing = getFloorChangeThing(target)
      if thing then
        g_game.use(thing)
        CaveBot.delay(CaveBot.Config.get("useDelay"))
      else
        resetZRecovery()  -- alvo sem floor-change (mudou/sumiu): re-resolver
        CaveBot.delay(200)
        return "retry"
      end
    else
      -- Servidor "step": escadas/buracos/teleports trocam de andar ao PISAR. Já
      -- estamos em cima; a troca dispara no servidor. Espera o próximo tick.
      zdbgT("fcstep", 500, "EM CIMA do floor-change (step) -- aguardando o servidor trocar de andar")
      CaveBot.delay(100)
    end
    -- Guard anti-travamento: se ficarmos presos sem trocar de andar (desync/
    -- timing/ferramenta que não acionou), contabiliza retry (throttle-gated) para
    -- o MAX eventualmente desistir e reancorar, em vez de loop infinito.
    local nowAt = g_clock.millis()
    if nowAt - zRecovery.lastAttemptTime >= Z_RECOVERY_INTERVAL then
      zRecovery.lastAttemptTime = nowAt
      zRecovery.retries = zRecovery.retries + 1
      if zRecovery.retries > Z_RECOVERY_MAX_RETRIES then
        zdbg("MAX_RETRIES em cima do FC sem trocar de andar -> giveUp")
        return giveUpZRecovery(playerPos)
      end
    end
    return "retry"
  end

  -- Contador de retry throttle-gated (~1/s): so o TETO DE TEMPO p/ desistir/reancorar
  -- (MAX_RETRIES) caso o char oscile sem chegar. NAO gate o walk nisto -- era esse gate
  -- de 1s que fazia o char ir devagar, ~1 SQM por vez, ate a escada. Cada hop reseta.
  local now = g_clock.millis()
  if now - zRecovery.lastAttemptTime >= Z_RECOVERY_INTERVAL then
    zRecovery.lastAttemptTime = now
    zRecovery.retries = zRecovery.retries + 1
    if zRecovery.retries > Z_RECOVERY_MAX_RETRIES then
      zdbg("MAX_RETRIES indo ate o FC (nao chegou) -> giveUp")
      return giveUpZRecovery(playerPos)
    end
  end

  -- Anda ATE o floor-change em TODO tick (sem throttle) -- igual ao goto normal: walkTo
  -- emite o passo e ja seta o proprio delay (walkDelay/mapClickDelay + stepDuration), e o
  -- doWalking (loop principal) / autoWalk nativo carregam o resto do path no ritmo REAL do
  -- char. So anda liso assim. needTool: precision 1 (adjacente); step: precision 0 +
  -- allowFloorChangeDest p/ o passo final cair no floor-change.
  local reach = needTool and 1 or 0
  local params = { ignoreNonPathable = true, precision = reach }
  if not needTool then params.allowFloorChangeDest = true end
  local maxDist = math.max(dist * 2, 40)
  local walked = CaveBot.walkTo(target, maxDist, params)
  if not walked then
    params.ignoreCreatures = true
    walked = CaveBot.walkTo(target, maxDist, params)
  end
  -- Bloqueado (parede/inalcancavel): so aqui um respiro p/ nao re-findPath a 50Hz (em
  -- mapClick o doWalking e no-op, entao processAction repetiria sem isto).
  if not walked then
    zdbgT("fcblock", 700, string.format("walkTo ate o FC FALHOU (bloqueado/inalcancavel) dist=%d", dist))
    CaveBot.delay(100)
  end
  return "retry"
end

-- Fallback client-side (servidor mudo): acha o floor-change pela tabela de IDs.
local function clientSideRecovery(playerPos, waypointPos)
  local floorTile = findNearbyFloorChange(playerPos, Z_RECOVERY_RANGE, playerPos.z, waypointPos.z)
  if not floorTile then
    zdbg("fallback client: NENHUM floor-change no raio -> giveUp")
    return giveUpZRecovery(playerPos)
  end
  zdbg(string.format("fallback client: achou floor-change em %d,%d,%d", floorTile.x, floorTile.y, floorTile.z))
  zRecovery.fcPos = floorTile
  zRecovery.fcKind = "step"
  zRecovery.fcFallback = true  -- heurística: tenta usar o item ao chegar
  zRecovery.retries = 0
  zRecovery.lastAttemptTime = 0
  return walkToFloorChange(playerPos)
end

-- Tenta recuperar o Z do player. Servidor-autoritativo com fallback client-side.
-- Retorna: "retry" enquanto tenta, false quando desiste (o waypoint é pulado).
local function tryZRecovery(playerPos, waypointPos)
  -- Recovery desligado: sinaliza "pular este waypoint", mas com um respiro para o
  -- motor não varrer a lista inteira a 50Hz quando o player está preso no Z errado.
  if not CaveBot.Config.get("zRecovery") then
    zdbgT("cfgoff", 2000, string.format("config OFF -> pula waypoint (player Z=%d, target Z=%d)", playerPos.z, waypointPos.z))
    CaveBot.delay(200)
    return false
  end

  -- Hop: o Z mudou (pisamos num floor-change) -> reinicia o episódio para o novo
  -- andar. Reancora lastGoodPos na posição atual para o drift abaixo medir a partir
  -- de onde chegamos no novo Z (senão o multi-andar abortaria no 2o hop, medindo
  -- contra o andar de origem). Vem ANTES do drift para resetar antes de desistir.
  if zRecovery.active and zRecovery.lastZ and playerPos.z ~= zRecovery.lastZ then
    zdbg(string.format("HOP: Z mudou %d -> %d (pisou num FC) -> reinicia episodio", zRecovery.lastZ, playerPos.z))
    resetZRecovery()
    lastGoodPos = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
  end

  -- Drift-check REMOVIDO (2026-07-08): media a distancia ao ULTIMO WAYPOINT (lastGoodPos),
  -- NAO a um floor-change alcancavel. Escada a >N sqm do waypoint (caso comum) abortava o
  -- recovery mesmo com a escada logo ao lado do player -> "so sobe se eu chegar perto na
  -- mao" (confirmado por log: DRIFT 6,1 vs escada a 1 sqm do player). O oraculo do servidor
  -- ja faz o check CERTO -- raio 6 DO PLAYER + getPathTo alcancavel -- entao sem floor-change
  -- alcancavel ele responde "nada" -> giveUp. O drift era redundante e nocivo. Quem limita
  -- agora e o MAX_RETRIES + a resposta do servidor.

  -- Início do episódio: pergunta ao servidor (a verdade). Se o script não existir
  -- no servidor, o timeout adiante cai no fallback client-side.
  if not zRecovery.active then
    zdbg(string.format("INICIO episodio: player Z=%d, target Z=%d", playerPos.z, waypointPos.z))
    zScanDump(playerPos, waypointPos.z)
    zRecovery.active = true
    zRecovery.lastZ = playerPos.z
    zRecovery.targetWpZ = waypointPos.z
    zRecovery.retries = 0
    zRecovery.fcPos = nil
    zRecovery.usingFallback = false
    requestServerRecovery(waypointPos)
    return "retry"
  end

  -- Alvo de floor-change já resolvido (servidor ou fallback): executa.
  if zRecovery.fcPos then
    return walkToFloorChange(playerPos)
  end

  -- Ainda resolvendo o alvo pelo servidor:
  if not zRecovery.usingFallback then
    local ans = zRecovery.answer
    if ans == false then
      zdbg("servidor: nada alcancavel -> giveUp")
      return giveUpZRecovery(playerPos)              -- servidor: nada alcançável
    elseif type(ans) == "table" then
      zdbg(string.format("servidor OK: vai p/ %d,%d,%d kind=%s -> walkToFC", ans.x, ans.y, ans.z, tostring(ans.kind)))
      zRecovery.fcPos = { x = ans.x, y = ans.y, z = ans.z }
      zRecovery.fcKind = ans.kind or "step"          -- "step" (pisar) ou "rope" (corda)
      zRecovery.fcFallback = false
      zRecovery.retries = 0
      zRecovery.lastAttemptTime = 0
      return walkToFloorChange(playerPos)
    end
    -- Sem resposta ainda: espera até o timeout, então cai no fallback.
    if (g_clock.millis() - zRecovery.reqSentAt) < Z_SERVER_TIMEOUT then
      zdbgT("waitsrv", 400, string.format("aguardando servidor... (%d/%dms)", g_clock.millis() - zRecovery.reqSentAt, Z_SERVER_TIMEOUT))
      return "retry"
    end
    zdbg("servidor MUDO (timeout) -> fallback client-side")
    zRecovery.usingFallback = true
    CaveBot.log("Z-Recovery: server silent, using local heuristic", "action")
  end

  -- Servidor mudo (timeout): heurística client-side.
  return clientSideRecovery(playerPos, waypointPos)
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

-- Label: marca um ponto de salto (não faz nada no motor). Além disso, notifica os
-- scripts: dispara Game.Events.LABEL (=13, ver scripting/api/game.lua) com o nome
-- do label sempre que o cavebot chega/executa este waypoint -- tanto na travessia
-- normal quanto após um gotoLabel (ambos caem aqui via processAction). O bridge
-- Scripting.emitGameEvent é resolvido em runtime e é no-op barato sem listener.
-- NÃO auto-pausa (congelaria cavebots que usam label só como alvo de salto);
-- scripts que querem o padrão ZB chamam CaveBot.pause()/pause(0) manualmente.
CaveBot.registerAction("label", "yellow", function(value, retries, prev)
  if Scripting and Scripting.emitGameEvent then
    pcall(Scripting.emitGameEvent, 13, value)
  end
  return true
end)

-- GotoLabel: salta para um label (opcionalmente condicionado a stamina).
-- O value pode vir como "label" ou "label|stamina_lt|39" / "label|stamina_gt|39"
-- (a condicao e embutida por CaveBot.loadFromWaypoints a partir do waypoint).
CaveBot.registerAction("gotolabel", "#FFFF55", function(value, retries, prev)
  local label, cond, stamina = value:match("^(.*)|(stamina_[lg]t)|(%-?%d+)$")
  if cond then
    -- So salta se a condicao for satisfeita; caso contrario segue o cavebot.
    if not CavebotUtils.isGotoConditionMet({ gotoCondition = cond, gotoStamina = stamina }) then
      return true
    end
  else
    label = value
  end
  return CaveBot.gotoLabel(label)
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

-- Script: executa um trecho Lua no MESMO sandbox da aba Scripting (Player/Map/
-- Game/CaveBot/Creature/Enums/JSON/...). Diferente de "function" (que tem acesso
-- cru a _G: g_game/g_map), aqui o código enxerga exatamente a API do scripting.
-- É position-less: roda quando o cavebot chega neste waypoint na sequência
-- (coloque-o logo após o Goto/Node que leva ao SQM a verificar). O `return` do
-- trecho controla o fluxo: true/nada=avança, false=avança (falhou), "retry"=
-- repete em ~20ms. Helpers extra injetados no env: retries, prev, delay(ms),
-- gotoLabel(name), print(...).
CaveBot.registerAction("script", "#33CCFF", function(value, retries, prev)
  if type(value) ~= "string" or value:match("^%s*$") then return true end
  if not Scripting or type(Scripting.runSnippet) ~= "function" then
    CaveBot.log("Script WP: modulo Scripting indisponivel", "error")
    return false
  end
  local extra = {
    retries = retries,
    prev = prev,
    delay = CaveBot.delay,
    gotoLabel = CaveBot.gotoLabel,
    print = function(...)
      local parts = {}
      for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
      CaveBot.log(table.concat(parts, "\t"), "script")
    end,
  }
  -- Per-waypoint identity so each Script waypoint gets its OWN snippet record
  -- (isolated storage + Timer/HUD names); retries/laps of the SAME waypoint reuse
  -- it (idempotent). Without a distinct key every Script waypoint would collide on
  -- the default "@cavebot_script" record.
  local wpKey = "@cavebot_script#" .. tostring((CaveBot.getCurrentIndex and CaveBot.getCurrentIndex()) or 0)
  local ok, ret = Scripting.runSnippet(value, extra, "@cavebot_script", wpKey)
  if not ok then
    CaveBot.log("Script WP erro: " .. tostring(ret), "error")
    return false
  end
  if ret == "retry" then return "retry" end
  if ret == false then return false end
  return true
end)

-- Goto: caminha até uma posição
CaveBot.registerAction("goto", "green", function(value, retries, prev)
  local pos, precision = parsePositionWithPrecision(value)
  if not pos then
    error("Invalid cavebot goto action value. It should be position (x,y,z), is: " .. value)
    return false
  end

  local playerPos = getPlayerPos()
  if not playerPos then return false end

  -- Travessia por teleport: avanca SEQUENCIALMENTE ao concluir o salto; aguarda parado
  -- em cima do TP ate ele acionar (nao avanca prematuro, que largava a travessia e
  -- fazia o Z-recovery reancorar noutro waypoint -> pulava os waypoints do trajeto).
  local tc = teleportCrossing(pos, playerPos, retries)
  if tc == "advance" then return true end
  if tc == "wait" then CaveBot.delay(100); return "retry" end

  -- Waypoint sobre escada/rampa/teleport? (tileRequiresStep). Avaliado ANTES do check
  -- de andar: se o waypoint exige pisar e já trocamos de andar estando a poucos SQM
  -- dele, a travessia CONCLUIU -- avança em vez de disparar Z-recovery de volta (que
  -- faria o bot oscilar subindo/descendo a mesma escada). Longe daqui é andar errado
  -- de verdade -> Z-recovery normal.
  local stairs = tileRequiresStep(pos)

  -- Verificar floor diferente
  if pos.z ~= playerPos.z then
    if stairs and math.max(math.abs(pos.x - playerPos.x), math.abs(pos.y - playerPos.y)) <= 2 then
      zdbgT("gadv", 1500, string.format("goto: Z-diff (pZ=%d wpZ=%d) em waypoint-escada a <=2 sqm -> AVANCA (travessia, SEM recovery)", playerPos.z, pos.z))
      return true
    end
    zdbgT("gtry", 1500, string.format("goto: Z-diff (pZ=%d wpZ=%d) stairs=%s -> tryZRecovery", playerPos.z, pos.z, tostring(stairs)))
    return tryZRecovery(playerPos, pos)
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

  -- Reach do waypoint: precision embutido no value (default 1). Escada exige SQM exato.
  local reach = precision or 1
  local walkPrecision = stairs and 0 or reach

  -- Verificar se já chegou (dentro do reach)
  if stairs then
    if dist == 0 then return true end
  else
    if dist <= reach then return true end
  end

  -- Anda tratando criaturas como OBSTÁCULO: o pathfinding dá a volta sozinho
  -- quando existe caminho alternativo. Waypoint sobre escada: permite o passo final
  -- cair no floor-change (allowFloorChangeDest) para efetivar a subida/descida.
  local walkParams = { ignoreNonPathable = true, precision = walkPrecision }
  if stairs then walkParams.allowFloorChangeDest = true end
  if CaveBot.walkTo(pos, maxDist, walkParams) then
    return "retry"
  end

  -- Não conseguiu andar. Se o único bloqueio é criatura (há caminho se as
  -- ignorarmos), ESPERAR parado até liberar — não empurra o monstro por cima
  -- nem pula o waypoint (deixa o targeting matar / o monstro andar).
  if blockedByCreatureOnly(playerPos, pos, maxDist, walkPrecision) then
    logWaitingForCreature()
    CaveBot.delay(300)
    return "retry"
  end

  -- Se skipBlocked ativo, desistir assim que não há caminho.
  if CaveBot.Config.get("skipBlocked") then
    return false
  end

  -- Bloqueio permanente (parede/inalcançável): tolera por um tempo e então
  -- desiste (avança) para não prender a rota num waypoint impossível.
  if retries >= 100 then return false end
  CaveBot.delay(100)
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

  local playerPos = getPlayerPos()
  if not playerPos then return false end

  -- Travessia por teleport: avanca SEQUENCIALMENTE ao concluir o salto; aguarda parado
  -- em cima do TP ate ele acionar (evita avanco prematuro e o Z-recovery reancorar
  -- noutro waypoint, que pulava os waypoints do trajeto apos o teleport).
  local tc = teleportCrossing(pos, playerPos, retries)
  if tc == "advance" then return true end
  if tc == "wait" then CaveBot.delay(100); return "retry" end

  -- Waypoint sobre escada/teleport já cruzado: se trocamos de andar/lugar estando a
  -- poucos SQM dele, a travessia concluiu -> avança (nao volta via Z-recovery, o que
  -- oscilaria subindo/descendo).
  local sStairs = tileRequiresStep(pos)

  -- Andar errado: tenta Z-recovery (mesma lógica de goto/node) em vez de pular
  -- direto. giveUpZRecovery reancora a rota ou pula se não houver como voltar.
  if pos.z ~= playerPos.z then
    if sStairs and math.max(math.abs(pos.x - playerPos.x), math.abs(pos.y - playerPos.y)) <= 2 then
      return true
    end
    return tryZRecovery(playerPos, pos)
  end
  lastGoodPos = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
  resetZRecovery()

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

    -- Próximo waypoint NÃO é alcançável agora (obstáculo/criatura temporária).
    -- Aguarda; se demorar demais (bloqueio permanente), avança para não travar a rota.
    if retries >= 100 then return true end
    CaveBot.delay(200)
    return "retry"
  end

  -- Caminhar até a posição (stand pode pisar no tile final mesmo com floor change).
  -- Criaturas são tratadas como OBSTÁCULO: o pathfinding contorna sozinho quando
  -- há volta. Stand é sempre reach exato (precision 0).
  if CaveBot.walkTo(pos, 40, { ignoreNonPathable = true, allowFloorChangeDest = true }) then
    return "retry"
  end

  -- Não conseguiu andar. Se o bloqueio é (só) por criatura — inclusive um monstro
  -- em cima do próprio SQM do stand — ESPERAR parado até liberar, sem pular o
  -- waypoint nem empurrar (deixa o targeting matar / o monstro andar).
  if blockedByCreatureOnly(playerPos, pos, 40, 0) then
    logWaitingForCreature()
    CaveBot.delay(300)
    return "retry"
  end

  -- Bloqueio permanente (parede/inalcançável): tolera por um tempo e então desiste
  -- para não prender a rota num waypoint impossível.
  if retries >= 100 then return false end
  CaveBot.delay(100)
  return "retry"
end)

-- Node: mesma lógica do goto mas usa nodeDistance
CaveBot.registerAction("node", "green", function(value, retries, prev)
  local pos = parsePosition(value)
  if not pos then
    error("Invalid cavebot node action value: " .. value)
    return false
  end

  local playerPos = getPlayerPos()
  if not playerPos then return false end

  -- Travessia por teleport: avanca SEQUENCIALMENTE ao concluir o salto; aguarda parado
  -- em cima do TP ate ele acionar (evita avanco prematuro e o Z-recovery reancorar
  -- noutro waypoint, que pulava os waypoints do trajeto apos o teleport).
  local tc = teleportCrossing(pos, playerPos, retries)
  if tc == "advance" then return true end
  if tc == "wait" then CaveBot.delay(100); return "retry" end

  -- Waypoint sobre escada/teleport já cruzado: avança em vez de voltar via Z-recovery
  -- (evita oscilar subindo/descendo).
  local nStairs = tileRequiresStep(pos)

  if pos.z ~= playerPos.z then
    if nStairs and math.max(math.abs(pos.x - playerPos.x), math.abs(pos.y - playerPos.y)) <= 2 then
      return true
    end
    return tryZRecovery(playerPos, pos)
  end
  lastGoodPos = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
  resetZRecovery()

  local nodeDistance = CaveBot.Config.get("nodeDistance") or 2
  -- Escada/teleport exige PISAR no SQM exato (precision 0 + allowFloorChangeDest);
  -- senao usa nodeDistance normal.
  local nWalkPrecision = nStairs and 0 or nodeDistance
  local dx = math.abs(pos.x - playerPos.x)
  local dy = math.abs(pos.y - playerPos.y)

  -- Chegou dentro do reach. Escada/teleport = SQM exato; senao nodeDistance
  -- (1 = SQM exato; 2 = adjacente; 3 = 2 tiles).
  if nStairs then
    if math.max(dx, dy) == 0 then return true end
  elseif math.max(dx, dy) <= nodeDistance - 1 then
    return true
  end

  -- Anda tratando criaturas como OBSTÁCULO: o pathfinding dá a volta sozinho quando
  -- há caminho alternativo. Escada/teleport: permite o passo final cair no
  -- floor-change (allowFloorChangeDest) p/ efetivar a travessia.
  local nWalkParams = { ignoreNonPathable = true, precision = nWalkPrecision }
  if nStairs then nWalkParams.allowFloorChangeDest = true end
  if CaveBot.walkTo(pos, 40, nWalkParams) then
    return "retry"
  end

  -- Não conseguiu andar. Se o único bloqueio é criatura (há caminho se ignorarmos
  -- criaturas), ESPERAR parado até liberar — não pula o waypoint nem empurra.
  if blockedByCreatureOnly(playerPos, pos, 40, nWalkPrecision) then
    logWaitingForCreature()
    CaveBot.delay(300)
    return "retry"
  end

  -- Bloqueio permanente (parede/inalcançável): tolera por um tempo e então desiste
  -- (avança) para não prender a rota num waypoint impossível.
  if retries >= 100 then return false end
  CaveBot.delay(100)
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
  if CaveBot.setOff then
    CaveBot.setOff()  -- garantia defensiva (stopWalk ja desliga o motor se walking==true)
  end
  -- Reflete OFF tambem na intencao+checkbox, senao a UI fica marcada "ligado" com o
  -- cavebot parado pelo WP (estado ambiguo que a auditoria apontou).
  if hr and hr.markCavebotDisabled then
    hr.markCavebotDisabled()
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
