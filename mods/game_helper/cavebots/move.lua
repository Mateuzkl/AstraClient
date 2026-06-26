-- Cavebot Walker Move Module
-- Funcoes de movimento, pathfinding e navegacao

local CavebotUtils = dofile("/game_helper/cavebots/utils.lua")

local CavebotMove = {}

-- ============================================================================
-- A* PATHFINDING COM CUSTOS CUSTOMIZADOS
-- Reto = custo 1, Diagonal = custo 3
-- Sempre escolhe o caminho de menor custo total
-- ============================================================================

local LEGACY_MAP_WIDTH = 15
local LEGACY_MAP_HEIGHT = 11
local LEGACY_OFFSET_X = 8
local LEGACY_OFFSET_Y = 6

-- Custos de movimento
local COST_STRAIGHT = 1  -- Norte, Sul, Leste, Oeste
local COST_DIAGONAL = 3  -- NE, SE, SW, NW

-- Direcoes: {dx, dy, custo}
-- Ordem: primeiro os retos (custo menor), depois diagonais
local DIRECTIONS = {
    {0, -1, COST_STRAIGHT},  -- Norte
    {1, 0, COST_STRAIGHT},   -- Leste
    {0, 1, COST_STRAIGHT},   -- Sul
    {-1, 0, COST_STRAIGHT},  -- Oeste
    {1, -1, COST_DIAGONAL},  -- Nordeste
    {1, 1, COST_DIAGONAL},   -- Sudeste
    {-1, 1, COST_DIAGONAL},  -- Sudoeste
    {-1, -1, COST_DIAGONAL}  -- Noroeste
}

-- Heuristica: Manhattan distance (otimista para garantir caminho otimo)
local function heuristic(x1, y1, x2, y2)
    return math.abs(x2 - x1) + math.abs(y2 - y1)
end

-- Gera chave unica para posicao
local function posKey(x, y)
    return x * 10000 + y
end

function CavebotMove.astarFindPath(map, mapW, mapH, startX, startY, goalX, goalY)
    -- Verificar se inicio e fim sao validos
    if startX == goalX and startY == goalY then return {} end
    
    local function isValid(x, y)
        return x > 0 and x <= mapW and y > 0 and y <= mapH and map[x + mapW * y - mapW] == 0
    end
    
    -- Se destino nao e valido, retornar nil
    if not isValid(goalX, goalY) then
        -- Permitir destino invalido (pode ser o waypoint)
    end
    
    -- Open set como priority queue simples
    local openSet = {}
    local openSetMap = {}  -- Para lookup rapido
    local closedSet = {}
    local cameFrom = {}
    local gScore = {}
    local fScore = {}
    
    local startKey = posKey(startX, startY)
    gScore[startKey] = 0
    fScore[startKey] = heuristic(startX, startY, goalX, goalY)
    
    table.insert(openSet, {x = startX, y = startY, f = fScore[startKey]})
    openSetMap[startKey] = true
    
    local iterations = 0
    local maxIterations = 1000
    
    while #openSet > 0 and iterations < maxIterations do
        iterations = iterations + 1
        
        -- Encontrar no com menor fScore
        local lowestIdx = 1
        local lowestF = openSet[1].f
        for i = 2, #openSet do
            if openSet[i].f < lowestF then
                lowestF = openSet[i].f
                lowestIdx = i
            end
        end
        
        local current = openSet[lowestIdx]
        local currentKey = posKey(current.x, current.y)
        
        -- Chegou ao destino?
        if current.x == goalX and current.y == goalY then
            -- Reconstruir caminho
            local path = {}
            local key = currentKey
            while cameFrom[key] do
                local from = cameFrom[key]
                table.insert(path, 1, {x = current.x, y = current.y})
                current = from
                key = posKey(current.x, current.y)
            end
            return path
        end
        
        -- Remover do openSet
        table.remove(openSet, lowestIdx)
        openSetMap[currentKey] = nil
        closedSet[currentKey] = true
        
        -- Explorar vizinhos (primeiro os retos, depois diagonais)
        for _, dir in ipairs(DIRECTIONS) do
            local nx = current.x + dir[1]
            local ny = current.y + dir[2]
            local cost = dir[3]
            local neighborKey = posKey(nx, ny)
            
            -- Pular se ja foi visitado
            if closedSet[neighborKey] then
                goto continue
            end
            
            -- Verificar se e valido (ou se e o destino)
            local isGoal = nx == goalX and ny == goalY
            if not isValid(nx, ny) and not isGoal then
                goto continue
            end
            
            -- Calcular novo gScore
            local tentativeG = gScore[currentKey] + cost
            
            -- Se nao esta no openSet ou encontramos caminho melhor
            if not gScore[neighborKey] or tentativeG < gScore[neighborKey] then
                -- Atualizar caminho
                cameFrom[neighborKey] = {x = current.x, y = current.y}
                gScore[neighborKey] = tentativeG
                fScore[neighborKey] = tentativeG + heuristic(nx, ny, goalX, goalY)
                
                -- Adicionar ao openSet se nao estiver
                if not openSetMap[neighborKey] then
                    table.insert(openSet, {x = nx, y = ny, f = fScore[neighborKey]})
                    openSetMap[neighborKey] = true
                end
            end
            
            ::continue::
        end
    end
    
    -- Nao encontrou caminho
    return nil
end

-- Funcao legada para compatibilidade
function CavebotMove.legacyAstarFindPath(map, mapW, mapH, startX, startY, goalX, goalY)
    return CavebotMove.astarFindPath(map, mapW, mapH, startX, startY, goalX, goalY)
end

function CavebotMove.buildAstarDirections(startPos, targetPos, blockedPositions, isTileBlockedFunc)
    if not startPos or not targetPos or startPos.z ~= targetPos.z then return nil end

    local dx = math.abs(startPos.x - targetPos.x)
    local dy = math.abs(startPos.y - targetPos.y)
    if dx > 7 or dy > 5 then return nil end

    local map = {}
    local index = 1
    local goalX, goalY = nil, nil

    for y = -5, 5 do
        for x = -7, 7 do
            local posX, posY = startPos.x + x, startPos.y + y
            local isGoal = posX == targetPos.x and posY == targetPos.y
            if isGoal then
                goalX = x + LEGACY_OFFSET_X
                goalY = y + LEGACY_OFFSET_Y
            end
            local pos = {x = posX, y = posY, z = startPos.z}
            local walkable = false
            if isGoal then
                walkable = true  -- Destino sempre e considerado walkable
            elseif isTileBlockedFunc then
                walkable = not isTileBlockedFunc(pos) and not CavebotUtils.isBlockedPosition(pos, blockedPositions)
            else
                walkable = CavebotUtils.isTileWalkable(pos, false) and not CavebotUtils.isBlockedPosition(pos, blockedPositions)
            end
            map[index] = walkable and 0 or 1
            index = index + 1
        end
    end

    if not goalX or not goalY then return nil end

    local pathList = CavebotMove.astarFindPath(map, LEGACY_MAP_WIDTH, LEGACY_MAP_HEIGHT, LEGACY_OFFSET_X, LEGACY_OFFSET_Y, goalX, goalY)
    if not pathList or #pathList == 0 then return nil end

    local directions = {}
    local prevPos = {x = startPos.x, y = startPos.y, z = startPos.z}
    
    -- pathList ja vem na ordem correta (do inicio ao fim)
    for i = 1, #pathList do
        local node = pathList[i]
        local toPos = {
            x = startPos.x + (node.x - LEGACY_OFFSET_X),
            y = startPos.y + (node.y - LEGACY_OFFSET_Y),
            z = startPos.z
        }
        local dir = CavebotUtils.getDirection(prevPos, toPos)
        if dir and dir ~= Directions.Invalid then
            table.insert(directions, dir)
        end
        prevPos = toPos
    end

    return #directions > 0 and directions or nil
end

-- Alias para compatibilidade
function CavebotMove.buildLegacyAstarDirections(startPos, targetPos, blockedPositions)
    return CavebotMove.buildAstarDirections(startPos, targetPos, blockedPositions, nil)
end

-- ============================================================================
-- PATH OPTIMIZATION
-- Decompoe diagonais em 2 movimentos retos quando possivel
-- Custo: diagonal = 3, 2 retos = 2 (mais barato!)
-- ============================================================================

function CavebotMove.optimizePathForStraightMoves(path, startPos, isTileBlockedForPathfinding, blockedPositions)
    if not path or #path == 0 or not startPos then return path end

    local success, result = pcall(function()
        local optimizedPath = {}
        local currentPos = {x = startPos.x, y = startPos.y, z = startPos.z}

        for i, dir in ipairs(path) do
            if CavebotUtils.isDiagonalDirection(dir) then
                -- Diagonal custa 3, dois retos custam 2 - vale a pena decompor!
                local dir1, dir2 = CavebotUtils.decomposeDiagonal(dir)
                if dir1 and dir2 then
                    local pos1 = CavebotUtils.translatePosition(currentPos, dir1)
                    local pos2 = CavebotUtils.translatePosition(currentPos, dir2)

                    local pos1Ok = pos1 and CavebotUtils.isTileWalkable(pos1, false) and
                                   not CavebotUtils.isBlockedPosition(pos1, blockedPositions) and
                                   not (isTileBlockedForPathfinding and isTileBlockedForPathfinding(pos1))
                    local pos2Ok = pos2 and CavebotUtils.isTileWalkable(pos2, false) and
                                   not CavebotUtils.isBlockedPosition(pos2, blockedPositions) and
                                   not (isTileBlockedForPathfinding and isTileBlockedForPathfinding(pos2))

                    if pos1Ok then
                        -- Decompor: primeiro dir1, depois dir2
                        table.insert(optimizedPath, dir1)
                        currentPos = pos1
                        table.insert(optimizedPath, dir2)
                        currentPos = CavebotUtils.translatePosition(currentPos, dir2)
                    elseif pos2Ok then
                        -- Decompor: primeiro dir2, depois dir1
                        table.insert(optimizedPath, dir2)
                        currentPos = pos2
                        table.insert(optimizedPath, dir1)
                        currentPos = CavebotUtils.translatePosition(currentPos, dir1)
                    else
                        -- Nao pode decompor, manter diagonal
                        table.insert(optimizedPath, dir)
                        currentPos = CavebotUtils.translatePosition(currentPos, dir)
                    end
                else
                    table.insert(optimizedPath, dir)
                    currentPos = CavebotUtils.translatePosition(currentPos, dir)
                end
            else
                -- Movimento reto, manter
                table.insert(optimizedPath, dir)
                currentPos = CavebotUtils.translatePosition(currentPos, dir)
            end
        end
        return optimizedPath
    end)

    return (success and result and #result > 0) and result or path
end

-- ============================================================================
-- PATH VALIDATION
-- ============================================================================

function CavebotMove.pathHitsBlocked(path, startPos, maxSteps, blockedPositions, isTileBlockedForPathfinding, targetWaypoint)
    if not path or #path == 0 or not startPos then return false end

    local checkPos = {x = startPos.x, y = startPos.y, z = startPos.z}
    local limit = maxSteps or #path

    local finalPos = {x = startPos.x, y = startPos.y, z = startPos.z}
    for i = 1, math.min(#path, limit) do
        finalPos = CavebotUtils.translatePosition(finalPos, path[i])
    end

    local isStandDestination = false
    local isStandFloorChange = false
    
    -- DEBUG: Log what targetWaypoint we received
    if CavebotUtils.DEBUG_LOG_ENABLED then
        if targetWaypoint then
            local wpType = CavebotUtils.waypointTypeToString(targetWaypoint.type)
            local isStand = CavebotUtils.isStandLikeType(targetWaypoint.type)
            print(string.format("[CAVEBOT] pathHitsBlocked: targetWaypoint type=%s, isStandLike=%s, hasPos=%s", 
                tostring(wpType), tostring(isStand), tostring(targetWaypoint.position ~= nil)))
        else
            print("[CAVEBOT] pathHitsBlocked: targetWaypoint is NIL!")
        end
    end
    
    if targetWaypoint and targetWaypoint.position then
        local targetPos = targetWaypoint.position
        if CavebotUtils.isStandLikeType(targetWaypoint.type) then
            -- Exact position match = destination
            if finalPos.x == targetPos.x and finalPos.y == targetPos.y and finalPos.z == targetPos.z then
                isStandDestination = true
            end
            -- For stand waypoints: if the FINAL STEP is a floor change tile, ALWAYS allow it
            -- We WANT to step on stairs/teleporters for stand waypoints
            if CavebotUtils.isFloorChangeTile(finalPos) then
                isStandFloorChange = true
                if CavebotUtils.DEBUG_LOG_ENABLED then
                    print(string.format("[CAVEBOT] pathHitsBlocked: Final step (%d,%d,%d) is FLOOR CHANGE for stand WP - ALLOWING", 
                        finalPos.x, finalPos.y, finalPos.z))
                end
            end
        end
    else
        -- If no targetWaypoint provided, but final step is a floor change tile,
        -- check if we're trying to reach ANY stand waypoint at or near this position
        -- This handles cases where pathHitsBlocked is called with nil targetWaypoint
        if CavebotUtils.isFloorChangeTile(finalPos) then
            -- Allow floor change tiles when they might be stand waypoint destinations
            isStandFloorChange = true
            if CavebotUtils.DEBUG_LOG_ENABLED then
                print(string.format("[CAVEBOT] pathHitsBlocked: Final step (%d,%d,%d) is FLOOR CHANGE (no WP info) - ALLOWING", 
                    finalPos.x, finalPos.y, finalPos.z))
            end
        end
    end

    -- DEBUG: Log path validation with all tiles
    local targetWpPos = targetWaypoint and targetWaypoint.position
    if CavebotUtils.DEBUG_LOG_ENABLED then
        -- Build list of all tiles in path
        local pathTiles = {}
        local debugPos = {x = startPos.x, y = startPos.y, z = startPos.z}
        for i = 1, math.min(#path, limit) do
            debugPos = CavebotUtils.translatePosition(debugPos, path[i])
            table.insert(pathTiles, string.format("(%d,%d)", debugPos.x, debugPos.y))
        end
        print(string.format("[CAVEBOT] pathHitsBlocked: %d steps from (%d,%d,%d) -> tiles: %s",
            math.min(#path, limit), startPos.x, startPos.y, startPos.z,
            table.concat(pathTiles, " ")))
    end

    for i = 1, math.min(#path, limit) do
        checkPos = CavebotUtils.translatePosition(checkPos, path[i])
        
        -- DEBUG: Log every tile being checked
        if CavebotUtils.DEBUG_LOG_ENABLED then
            local isFC = CavebotUtils.isFloorChangeTile(checkPos)
            if isFC then
                print(string.format("[CAVEBOT] pathHitsBlocked: step %d (%d,%d,%d) IS FLOOR CHANGE TILE!", 
                    i, checkPos.x, checkPos.y, checkPos.z))
            end
        end
        
        -- Skip block check for final step if it's a stand destination OR a floor change for stand waypoint
        local isFinalStep = (i == math.min(#path, limit))
        local skipBlockCheck = isFinalStep and (isStandDestination or isStandFloorChange)
        
        if not skipBlockCheck then
            if isTileBlockedForPathfinding and isTileBlockedForPathfinding(checkPos) then
                if CavebotUtils.DEBUG_LOG_ENABLED then
                    print(string.format("[CAVEBOT] pathHitsBlocked: BLOCKED at step %d (%d,%d,%d)", 
                        i, checkPos.x, checkPos.y, checkPos.z))
                end
                return true
            elseif CavebotUtils.isBlockedPosition(checkPos, blockedPositions) then
                return true
            end
        elseif CavebotUtils.DEBUG_LOG_ENABLED and isFinalStep then
            print(string.format("[CAVEBOT] pathHitsBlocked: ALLOWING final step %d (%d,%d,%d) - stand/stair destination", 
                i, checkPos.x, checkPos.y, checkPos.z))
        end
    end
    return false
end

-- ============================================================================
-- ALTERNATE TARGET FINDING
-- ============================================================================

function CavebotMove.findAlternateTarget(currentPos, targetPos, maxRadius, blockedPositions, isTileBlockedForPathfinding)
    if not currentPos or not targetPos or currentPos.z ~= targetPos.z then return nil end
    if not CavebotUtils.isBlockedPosition(targetPos, blockedPositions) then return targetPos end

    maxRadius = maxRadius or 2
    local bestPos, bestScore = nil, nil

    for r = 1, maxRadius do
        for dx = -r, r do
            for dy = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local pos = {x = targetPos.x + dx, y = targetPos.y + dy, z = targetPos.z}
                    if CavebotUtils.isTileWalkable(pos, false) and not CavebotUtils.isBlockedPosition(pos, blockedPositions) then
                        local path, result = g_map.findPathJPS(currentPos, pos, 200, 0)
                        if result == PathFindResults.Ok and path and #path > 0 then
                            if not CavebotMove.pathHitsBlocked(path, currentPos, nil, blockedPositions, isTileBlockedForPathfinding, nil) then
                                local distFromTarget = math.max(math.abs(dx), math.abs(dy))
                                local distFromCurrent = math.max(math.abs(currentPos.x - pos.x), math.abs(currentPos.y - pos.y))
                                local score = distFromTarget * 1000 + distFromCurrent
                                if not bestScore or score < bestScore then
                                    bestScore, bestPos = score, pos
                                end
                            end
                        end
                    end
                end
            end
        end
        if bestPos then return bestPos end
    end
    return nil
end

function CavebotMove.findStandApproachTarget(currentPos, targetPos, blockedPositions, isTileBlockedForPathfinding)
    if not currentPos or not targetPos or currentPos.z ~= targetPos.z then return nil end
    if CavebotUtils.isBlockedPosition(targetPos, blockedPositions) then return nil end

    local tile = g_map.getTile(targetPos)
    if not tile or (tile.isWalkable and not tile:isWalkable(true)) then return nil end

    local topCreature = tile:getTopCreature()
    if not topCreature or topCreature:isDead() then return nil end

    local player = g_game.getLocalPlayer()
    if player and topCreature:getId() == player:getId() then return nil end

    local bestPos, bestScore = nil, nil
    for dx = -1, 1 do
        for dy = -1, 1 do
            if not (dx == 0 and dy == 0) then
                local pos = {x = targetPos.x + dx, y = targetPos.y + dy, z = targetPos.z}
                if CavebotUtils.isTileWalkable(pos, false) and not (isTileBlockedForPathfinding and isTileBlockedForPathfinding(pos)) then
                    local path, result = g_map.findPathJPS(currentPos, pos, 200, 0)
                    if result == PathFindResults.Ok and path and #path > 0 then
                        if not CavebotMove.pathHitsBlocked(path, currentPos, nil, blockedPositions, isTileBlockedForPathfinding, nil) then
                            local dist = math.max(math.abs(currentPos.x - pos.x), math.abs(currentPos.y - pos.y))
                            if not bestScore or dist < bestScore then
                                bestScore, bestPos = dist, pos
                            end
                        end
                    end
                end
            end
        end
    end
    return bestPos
end

-- ============================================================================
-- WAYPOINT FINDING
-- ============================================================================

function CavebotMove.findClosestSameZWaypoint(currentPos, waypoints, checkPath)
    if not currentPos then return nil, nil end

    -- Performance limits to prevent freezing
    local MAX_DISTANCE_FOR_PATHFIND = 30   -- Don't pathfind to waypoints beyond this
    local MAX_PATHFIND_STEPS = 50          -- Smaller step limit for quick checks
    local MAX_PATHFIND_CHECKS = 15         -- Limit total pathfinding calls
    local CLOSE_ENOUGH_DISTANCE = 5        -- Early exit if we find something this close

    local closestIndex, closestPos, closestDist = nil, nil, nil
    local closestReachableIndex, closestReachablePos, closestReachableDist = nil, nil, nil
    
    -- First pass: collect all valid waypoints with distances (no pathfinding)
    local candidates = {}
    for i, waypoint in ipairs(waypoints or {}) do
        if waypoint and waypoint.position and CavebotUtils.waypointTypeToString(waypoint.type) ~= "special" then
            local targetPos = CavebotMove.getPathTargetPos(currentPos, waypoint)
            if targetPos and targetPos.z == currentPos.z then
                local dist = math.max(math.abs(currentPos.x - targetPos.x), math.abs(currentPos.y - targetPos.y))
                table.insert(candidates, {index = i, pos = targetPos, dist = dist})
                
                -- Track absolute closest (for fallback)
                if not closestDist or dist < closestDist then
                    closestIndex, closestPos, closestDist = i, targetPos, dist
                end
            end
        end
    end
    
    -- Sort by distance (closest first)
    table.sort(candidates, function(a, b) return a.dist < b.dist end)
    
    -- Second pass: check pathfinding only if needed and with limits
    if checkPath ~= false then
        local pathfindChecks = 0
        for _, candidate in ipairs(candidates) do
            -- Skip pathfinding for distant waypoints
            if candidate.dist > MAX_DISTANCE_FOR_PATHFIND then
                break  -- All remaining are farther, stop checking
            end
            
            if pathfindChecks >= MAX_PATHFIND_CHECKS then
                break  -- Reached limit
            end
            
            pathfindChecks = pathfindChecks + 1
            local testPath, result = g_map.findPathJPS(currentPos, candidate.pos, MAX_PATHFIND_STEPS, 16)
            if result == PathFindResults.Ok and testPath and #testPath > 0 then
                if not closestReachableDist or candidate.dist < closestReachableDist then
                    closestReachableIndex, closestReachablePos, closestReachableDist = candidate.index, candidate.pos, candidate.dist
                    
                    -- Early exit if close enough
                    if candidate.dist <= CLOSE_ENOUGH_DISTANCE then
                        break
                    end
                end
            end
        end
    end
    
    -- Prioritize reachable waypoint, otherwise return closest
    if closestReachableIndex then
        return closestReachableIndex, closestReachablePos
    end
    return closestIndex, closestPos
end

function CavebotMove.findLabelWaypointIndex(labelName, waypoints)
    labelName = CavebotUtils.normalizeLabelName(labelName)
    if not labelName then return nil end

    for index, waypoint in ipairs(waypoints or {}) do
        if waypoint and CavebotUtils.waypointTypeToString(waypoint.type) == "label" and waypoint.label == labelName then
            return index
        end
    end
    return nil
end

function CavebotMove.getPathTargetPos(currentPos, waypoint)
    if not currentPos or not waypoint or not waypoint.position then return nil end

    local targetPos = waypoint.position
    if CavebotUtils.isFloorChangeWaypoint(waypoint) and currentPos.z ~= targetPos.z then
        return {x = targetPos.x, y = targetPos.y, z = currentPos.z}
    end
    return targetPos
end

-- ============================================================================
-- MAP CLICK
-- ============================================================================

function CavebotMove.tryMapClick(targetPos, walkMode, blockedPositions, lastMapClickTime, mapClickCooldown)
    if walkMode ~= "click" then return false, lastMapClickTime end

    local player = g_game.getLocalPlayer()
    if not player or not targetPos then return false, lastMapClickTime end
    if CavebotUtils.isBlockedPosition(targetPos, blockedPositions) then return false, lastMapClickTime end

    local currentTime = g_clock.millis()
    if currentTime - (lastMapClickTime or 0) < (mapClickCooldown or 0) then
        return false, lastMapClickTime
    end

    player:autoWalk(targetPos)
    return true, currentTime
end

-- ============================================================================
-- PLAYER CHECKS
-- ============================================================================

-- Cache for isPlayerBoxed to avoid redundant checks
local boxedCache = {
    lastPos = nil,
    lastResult = false,
    lastTime = 0,
    cacheTimeout = 100  -- Cache valid for 100ms
}

function CavebotMove.isPlayerBoxed(pos, blockedPositions)
    local player = g_game.getLocalPlayer()
    if not player then return false end

    pos = pos or player:getPosition()
    if not pos then return false end

    -- Check cache: if same position and within timeout, return cached result
    local currentTime = g_clock.millis()
    if boxedCache.lastPos and 
       boxedCache.lastPos.x == pos.x and 
       boxedCache.lastPos.y == pos.y and 
       boxedCache.lastPos.z == pos.z and
       (currentTime - boxedCache.lastTime) < boxedCache.cacheTimeout then
        return boxedCache.lastResult
    end

    local directions = {
        {0, -1}, {1, -1}, {1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}
    }

    local blockedCount = 0
    local creatureBlockedCount = 0
    
    for _, dir in ipairs(directions) do
        local checkPos = {x = pos.x + dir[1], y = pos.y + dir[2], z = pos.z}
        if CavebotUtils.isBlockedPosition(checkPos, blockedPositions) then
            blockedCount = blockedCount + 1
        else
            local tile = g_map.getTile(checkPos)
            if not tile then
                blockedCount = blockedCount + 1
            elseif not tile:isWalkable() then
                -- Check if blocked by creature (temporary) vs terrain (permanent)
                local creatures = tile:getCreatures()
                if creatures and #creatures > 0 then
                    -- Creature blocking is temporary, don't count as permanently boxed
                    creatureBlockedCount = creatureBlockedCount + 1
                else
                    blockedCount = blockedCount + 1
                end
            end
        end
    end
    
    -- Only consider truly boxed if ALL 8 tiles are permanently blocked (not by creatures)
    -- Creature blocking is temporary and will clear
    local result = blockedCount >= 8
    
    -- Update cache
    boxedCache.lastPos = {x = pos.x, y = pos.y, z = pos.z}
    boxedCache.lastResult = result
    boxedCache.lastTime = currentTime
    return result
end

-- ============================================================================
-- CREATURE CHECKS
-- ============================================================================

-- Constantes de detecção de criaturas
-- Limita para o campo de visão do servidor (criaturas além disso ainda não "veem" o player)
local CREATURE_DETECT_RANGE_X = 9
local CREATURE_DETECT_RANGE_Y = 7

function CavebotMove.getCreatureCountAround(config, shouldIgnoreCreature)
    if CavebotUtils.isInProtectionZone() then return 0 end

    -- Use global creature cache
    -- Mudança: usar requirePath=true em vez de requireSight=true para detectar criaturas alcançáveis via pathfinding
    return CreatureCache.getMonsterCountAround(
        shouldIgnoreCreature,
        CREATURE_DETECT_RANGE_X,
        CREATURE_DETECT_RANGE_Y,
        false, -- requireSight (desativado)
        true   -- requirePath (usar pathfinding)
    )
end

function CavebotMove.getClosestCreatureDistance(shouldIgnoreCreature)
    -- Use global creature cache
    return CreatureCache.getClosestMonsterDistance(
        shouldIgnoreCreature,
        CREATURE_DETECT_RANGE_X,
        CREATURE_DETECT_RANGE_Y,
        true -- requireSight
    )
end

function CavebotMove.areMonstersFollowing(config, shouldIgnoreCreature, nextDirection)
    local player = g_game.getLocalPlayer()
    if not player then return false, 0 end

    local pos = player:getPosition()
    if not pos then return false, 0 end

    -- Use global creature cache
    local monsters = CreatureCache.getMonsters()
    if not monsters or #monsters == 0 then return false, 0 end

    local rangeX = math.min(6, config.lureCheckRangeX or 6)
    local rangeY = math.min(4, config.lureCheckRangeY or 4)
    local totalMonsters, monstersOk, permIgnoredCount, ignoredCount = 0, 0, 0, 0

    for _, entry in pairs(monsters) do
        if entry.sameFloor and entry.dx <= CREATURE_DETECT_RANGE_X and entry.dy <= CREATURE_DETECT_RANGE_Y then
            if shouldIgnoreCreature(entry.creature) then
                permIgnoredCount = permIgnoredCount + 1
            elseif entry:hasSightClear() then
                totalMonsters = totalMonsters + 1
                local inRange = entry.dx <= rangeX and entry.dy <= rangeY
                local ahead = CavebotUtils.isMonsterAhead(pos, entry.position, nextDirection, rangeX, rangeY)
                if inRange or ahead then
                    monstersOk = monstersOk + 1
                    if not inRange and ahead then ignoredCount = ignoredCount + 1 end
                end
            end
        end
    end

    local totalIgnored = permIgnoredCount + ignoredCount
    return totalMonsters == 0 and false or (monstersOk == totalMonsters), totalIgnored
end

return CavebotMove
