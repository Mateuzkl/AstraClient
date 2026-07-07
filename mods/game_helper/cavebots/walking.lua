-- CaveBot Walking Module
-- Sistema de movimentação baseado na referência game_bot
-- Usa expectedDirs para sincronização com servidor

CaveBot = CaveBot or {}

-- ============================================================================
-- ESTADO INTERNO
-- ============================================================================

local expectedDirs = {}
local isWalking = false
local walkPath = {}
local walkPathIter = 0

-- ============================================================================
-- SPECIAL AREAS - Tiles bloqueados que não podem ser cruzados
-- ============================================================================

-- Check if a position is in a special area (blocked)
local function isSpecialArea(pos)
  if not pos then return false end

  local specialAreas = CaveBot.Config.get("specialAreas") or {}
  for _, area in ipairs(specialAreas) do
    if area.position then
      if area.position.x == pos.x and area.position.y == pos.y and area.position.z == pos.z then
        return true
      end
    end
  end
  return false
end

-- Direction delta lookup (shared by path-walkers below)
local DIR_DELTAS = {
  [Directions.North] = {dx = 0, dy = -1},
  [Directions.East] = {dx = 1, dy = 0},
  [Directions.South] = {dx = 0, dy = 1},
  [Directions.West] = {dx = -1, dy = 0},
  [Directions.NorthEast] = {dx = 1, dy = -1},
  [Directions.SouthEast] = {dx = 1, dy = 1},
  [Directions.SouthWest] = {dx = -1, dy = 1},
  [Directions.NorthWest] = {dx = -1, dy = -1}
}

-- Check if a tile changes floor (stairs/holes/teleporters/rampas). Duas fontes:
--   1) item catalogado na lookup global FLOOR_CHANGE_IDS (buracos/teleports/alcapoes);
--   2) minimap color 210-213 -- a MESMA faixa que o engine usa p/ detectar "stairs"
--      e que o goto ja usa p/ waypoints de escada. Cobre escadas/rampas custom do
--      servidor que NAO estao na tabela de IDs. Sem (2) o walker PISA nessas escadas
--      ao ir para outro waypoint, troca de andar sem querer e o bot fica oscilando
--      subindo/descendo (o loop reportado).
local function hasFloorChangeItem(pos)
  if not pos then return false end
  local ids = CaveBot.FLOOR_CHANGE_IDS
  if ids then
    local tile = g_map.getTile(pos)
    if tile then
      local things = tile:getThings() or {}
      for _, thing in ipairs(things) do
        if thing and thing:isItem() and ids[thing:getId()] then
          return true
        end
      end
    end
  end
  local mc = g_map.getMinimapColor(pos)
  if mc and mc >= 210 and mc <= 213 then
    return true
  end
  return false
end

-- Check if a path steps onto any floor-change tile.
-- allowDest: se true, o tile final igual a `dest` é permitido (para waypoints STAND).
local function pathCrossesFloorChange(path, startPos, dest, allowDest)
  if not path or #path == 0 or not startPos then return false end
  if not CaveBot.FLOOR_CHANGE_IDS then return false end

  local currentPos = {x = startPos.x, y = startPos.y, z = startPos.z}
  local lastIdx = #path
  for i, dir in ipairs(path) do
    local delta = DIR_DELTAS[dir]
    if delta then
      currentPos = {
        x = currentPos.x + delta.dx,
        y = currentPos.y + delta.dy,
        z = currentPos.z
      }
      local isFinalStep = (i == lastIdx)
      local isDestTile = allowDest and dest
        and currentPos.x == dest.x and currentPos.y == dest.y and currentPos.z == dest.z
      if not (isFinalStep and isDestTile) then
        if hasFloorChangeItem(currentPos) then
          return true
        end
      end
    end
  end
  return false
end

-- Check if a path crosses any special area
local function pathCrossesSpecialArea(path, startPos)
  if not path or #path == 0 then return false end
  if not startPos then return false end

  local specialAreas = CaveBot.Config.get("specialAreas") or {}
  if #specialAreas == 0 then return false end

  -- Convert direction path to positions
  local dirs = {
    [Directions.North] = {dx = 0, dy = -1},
    [Directions.East] = {dx = 1, dy = 0},
    [Directions.South] = {dx = 0, dy = 1},
    [Directions.West] = {dx = -1, dy = 0},
    [Directions.NorthEast] = {dx = 1, dy = -1},
    [Directions.SouthEast] = {dx = 1, dy = 1},
    [Directions.SouthWest] = {dx = -1, dy = 1},
    [Directions.NorthWest] = {dx = -1, dy = -1}
  }

  local currentPos = {x = startPos.x, y = startPos.y, z = startPos.z}
  for _, dir in ipairs(path) do
    local delta = dirs[dir]
    if delta then
      currentPos = {
        x = currentPos.x + delta.dx,
        y = currentPos.y + delta.dy,
        z = currentPos.z
      }
      if isSpecialArea(currentPos) then
        return true
      end
    end
  end

  return false
end

-- ============================================================================
-- RESET WALKING
-- ============================================================================

CaveBot.resetWalking = function()
  expectedDirs = {}
  walkPath = {}
  isWalking = false
  walkPathIter = 0
end

CaveBot.isWalking = function()
  return isWalking
end

CaveBot.getCurrentPath = function()
  if not isWalking or #walkPath == 0 then
    return nil, nil
  end

  local player = g_game.getLocalPlayer()
  if not player then return nil, nil end

  return walkPath, player:getPosition()
end

-- ============================================================================
-- DO WALKING - Continua caminhada em andamento
-- ============================================================================

CaveBot.doWalking = function()
  -- Se mapClick está ativo, não processa aqui
  if CaveBot.Config.get("mapClick") then
    return false
  end

  -- Sem direções esperadas, nada a fazer
  if #expectedDirs == 0 then
    return false
  end

  -- Se muitas direções pendentes, resetar (dessincronizado)
  if #expectedDirs >= 3 then
    CaveBot.resetWalking()
    return false
  end

  -- Pegar próxima direção do path
  local dir = walkPath[walkPathIter]
  if dir then
    local player = g_game.getLocalPlayer()
    if player then
      -- Verificar se player pode andar (dead, rooted, walk locked, server sync)
      if not player:canWalk() then
        return true -- ainda caminhando, mas aguardando canWalk
      end
      g_game.walk(dir, false)
      table.insert(expectedDirs, dir)
      walkPathIter = walkPathIter + 1
      -- Delay com step duration para sincronizar com velocidade real do personagem
      CaveBot.delay(CaveBot.Config.get("walkDelay") + player:getStepDuration(false, dir))
      return true
    end
  end

  return false
end

-- ============================================================================
-- ON PLAYER POSITION CHANGE - Sincronização com servidor
-- ============================================================================

local function onPositionChange(newPos, oldPos)
  -- Verificar se posições são válidas
  if not oldPos or not newPos then return end
  if not oldPos.x or not oldPos.y or not oldPos.z then return end
  if not newPos.x or not newPos.y or not newPos.z then return end

  local player = g_game.getLocalPlayer()
  if not player then return end

  -- Detectar mudança de floor ou teleport (movimento > 1 tile)
  local dx = math.abs(newPos.x - oldPos.x)
  local dy = math.abs(newPos.y - oldPos.y)
  local floorChanged = newPos.z ~= oldPos.z
  local teleported = dx > 1 or dy > 1

  if floorChanged or teleported then
    -- Floor change ou teleport - resetar walking state
    CaveBot.resetWalking()
    CaveBot.delay(CaveBot.Config.get("ping"))

    -- Reset lure cache
    if CaveBot.Extensions.lure and CaveBot.Extensions.lure.resetCache then
      CaveBot.Extensions.lure.resetCache()
    end
    return
  end

  -- Calcular direção do movimento (mesma lógica do game_bot)
  local dirs = {
    {Directions.NorthWest, Directions.North, Directions.NorthEast},
    {Directions.West, 8, Directions.East},
    {Directions.SouthWest, Directions.South, Directions.SouthEast}
  }

  local moveDy = newPos.y - oldPos.y
  local moveDx = newPos.x - oldPos.x

  local dir = nil
  if moveDy >= -1 and moveDy <= 1 and moveDx >= -1 and moveDx <= 1 then
    local row = dirs[moveDy + 2]
    if row then
      dir = row[moveDx + 2]
    end
  end

  if not dir then
    dir = 8 -- 8 é direção inválida, ok
  end

  -- Se não estamos caminhando ou sem direções esperadas
  -- Movimento externo (escada, empurrão, etc) - esperar com step duration
  if not isWalking or not expectedDirs[1] then
    walkPath = {}
    CaveBot.delay(CaveBot.Config.get("ping") + player:getStepDuration(false, dir) + 150)
    return
  end

  -- Verificar se direção corresponde ao esperado
  if expectedDirs[1] ~= dir then
    -- Direção diferente (movimento externo) - delay com step duration
    if CaveBot.Config.get("mapClick") then
      CaveBot.delay(CaveBot.Config.get("walkDelay") + player:getStepDuration(false, dir))
    else
      CaveBot.delay(CaveBot.Config.get("mapClickDelay") + player:getStepDuration(false, dir))
    end
    return
  end

  -- Direção correta, remover da lista de esperados
  table.remove(expectedDirs, 1)

  -- Se mapClick e ainda tem direções pendentes, aplicar delay
  if CaveBot.Config.get("mapClick") and #expectedDirs > 0 then
    CaveBot.delay(CaveBot.Config.get("mapClickDelay") + player:getStepDuration(false, dir))
  end
end

-- ============================================================================
-- WALK TO - Caminha até destino
-- ============================================================================

CaveBot.walkTo = function(dest, maxDist, params)
  local player = g_game.getLocalPlayer()
  if not player then return false end

  local playerPos = player:getPosition()
  if not playerPos or not dest then return false end

  -- Verificar se destino é uma special area (bloqueado)
  if isSpecialArea(dest) then
    return false
  end

  -- Default: ignorar flag "avoid" (NotPathable) — fields/poças/decor com avoid
  -- são fisicamente passáveis pro player; só "unpass" (isNotWalkable) é
  -- bloqueio real. Caller pode forçar respeito setando ignoreNonPathable=false.
  if type(params) ~= 'table' then params = {} end
  if params.ignoreNonPathable == nil then
    params.ignoreNonPathable = true
  end

  -- Verificar modo de caminhada (mapClick ou walkMode)
  local useMapClick = CaveBot.Config.get("mapClick")
  local walkMode = CaveBot.Config.get("walkMode")
  if walkMode == "click" then
    useMapClick = true
  elseif walkMode == "walk" then
    useMapClick = false
  end

  -- Usar findPath avançado (findEveryPath com precision/margins) como pathfinding primário
  local path = CaveBot.Map.findPath(playerPos, dest, maxDist or 100, params)

  if not path or #path == 0 then
    return false
  end

  -- Verificar se o caminho cruza alguma special area
  if pathCrossesSpecialArea(path, playerPos) then
    return false
  end

  -- Nunca pisar em tiles de floor change (escadas, buracos, teleports).
  -- Exceção: waypoints do tipo STAND podem ter o tile final como destino
  -- (passar params.allowFloorChangeDest = true).
  if pathCrossesFloorChange(path, playerPos, dest, params and params.allowFloorChangeDest) then
    return false
  end

  -- Avoid Trap: tenta achar um path alternativo sem passar por dead-ends. Se
  -- findPath só devolveu esta rota (não há alternativa), andamos mesmo assim
  -- — corredores de 1sqm têm intermediários "dead-end" por natureza e não
  -- devem travar o bot.
  if CaveBot.Config and CaveBot.Config.get("avoidTrap") and CaveBot.Map.isDeadEnd then
    local hasDeadEnd = false
    local cur = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
    local lastIdx = #path
    for i, dir in ipairs(path) do
      local d = DIR_DELTAS[dir]
      if d then
        local nextPos = {x = cur.x + d.dx, y = cur.y + d.dy, z = cur.z}
        local isFinal = (i == lastIdx)
        local isUserDest = isFinal and dest
          and nextPos.x == dest.x and nextPos.y == dest.y and nextPos.z == dest.z
        if not isUserDest and CaveBot.Map.isDeadEnd(nextPos, cur, 2) then
          hasDeadEnd = true
          break
        end
        cur = nextPos
      end
    end

    if hasDeadEnd then
      local altParams = {}
      if type(params) == 'table' then
        for k, v in pairs(params) do altParams[k] = v end
      end
      altParams.avoidDeadEnd = true
      local altPath = CaveBot.Map.findPath(playerPos, dest, maxDist or 100, altParams)
      if altPath and #altPath > 0 and not pathCrossesSpecialArea(altPath, playerPos)
        and not pathCrossesFloorChange(altPath, playerPos, dest, params and params.allowFloorChangeDest) then
        path = altPath
      end
      -- Se não há alternativa válida, segue com o path original.
    end
  end

  local dir = path[1]

  -- Modo mapClick - envia path completo via autoWalk
  if useMapClick then
    local ret = CaveBot.Map.autoWalk(path)
    if ret then
      isWalking = true
      -- Trackear todas as direções esperadas (como o game_bot faz)
      expectedDirs = path
      -- Delay com step duration para sincronizar corretamente
      CaveBot.delay(CaveBot.Config.get("mapClickDelay") + math.max(CaveBot.Config.get("ping") + player:getStepDuration(false, dir), player:getStepDuration(false, dir) * 2))
    end
    return ret
  end

  -- Modo arrow key - verificar se pode andar antes de enviar
  if not player:canWalk() then
    return false
  end
  g_game.walk(dir, false)
  isWalking = true
  walkPath = path
  walkPathIter = 2
  expectedDirs = { dir }

  -- Delay com step duration para sincronizar com velocidade real
  CaveBot.delay(CaveBot.Config.get("walkDelay") + player:getStepDuration(false, dir))
  return true
end

-- ============================================================================
-- REGISTRAR CALLBACK
-- ============================================================================

-- Registrar callback de posição se onPlayerPositionChange estiver disponível
if onPlayerPositionChange then
  onPlayerPositionChange(onPositionChange)
else
  -- Fallback: conectar ao evento do cliente
  local function connectPositionCallback()
    local player = g_game.getLocalPlayer()
    if player then
      connect(player, {
        onPositionChange = onPositionChange
      })
    end
  end

  -- Tentar conectar quando o jogo iniciar
  if g_game.isOnline() then
    connectPositionCallback()
  end

  connect(g_game, {
    onGameStart = connectPositionCallback
  })
end

return CaveBot
