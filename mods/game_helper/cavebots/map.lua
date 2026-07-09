-- CaveBot Map Functions
-- Funções de pathfinding e mapa baseado na referência game_bot

CaveBot = CaveBot or {}
CaveBot.Map = {}

-- ============================================================================
-- FUNÇÕES DE MAPA
-- ============================================================================

-- Get spectators around position
CaveBot.Map.getSpectators = function(pos, multifloor)
    if not pos then
        local player = g_game.getLocalPlayer()
        if not player then return {} end
        pos = player:getPosition()
    end
    return g_map.getSpectators(pos, multifloor or false)
end

-- Get creature by ID
CaveBot.Map.getCreatureById = function(id, multifloor)
    if type(id) ~= 'number' then return nil end
    local player = g_game.getLocalPlayer()
    if not player then return nil end

    for _, spec in ipairs(g_map.getSpectators(player:getPosition(), multifloor or false)) do
        if spec:getId() == id then
            return spec
        end
    end
    return nil
end

-- Get creature by name
CaveBot.Map.getCreatureByName = function(name, multifloor)
    if not name then return nil end
    name = name:lower()
    local player = g_game.getLocalPlayer()
    if not player then return nil end

    for _, spec in ipairs(g_map.getSpectators(player:getPosition(), multifloor or false)) do
        if spec:getName():lower() == name then
            return spec
        end
    end
    return nil
end

-- ============================================================================
-- PATHFINDING
-- ============================================================================

-- Find all paths from start position
CaveBot.Map.findAllPaths = function(start, maxDist, params)
    --[[
      Available params:
        ignoreLastCreature
        ignoreCreatures
        ignoreNonPathable
        ignoreNonWalkable
        ignoreStairs
        ignoreCost
        allowUnseen
        allowOnlyVisibleTiles
        maxDistanceFrom
    ]]--
    if type(params) ~= 'table' then
        params = {}
    end

    -- Convert booleans to 0/1 for C++ interface
    for key, value in pairs(params) do
        if value == nil or value == false then
            params[key] = 0
        elseif value == true then
            params[key] = 1
        end
    end

    -- Handle maxDistanceFrom
    if type(params['maxDistanceFrom']) == 'table' then
        if #params['maxDistanceFrom'] == 2 then
            params['maxDistanceFrom'] = params['maxDistanceFrom'][1].x .. "," .. params['maxDistanceFrom'][1].y ..
                "," .. params['maxDistanceFrom'][1].z .. "," .. params['maxDistanceFrom'][2]
        elseif #params['maxDistanceFrom'] == 4 then
            params['maxDistanceFrom'] = params['maxDistanceFrom'][1] .. "," .. params['maxDistanceFrom'][2] ..
                "," .. params['maxDistanceFrom'][3] .. "," .. params['maxDistanceFrom'][4]
        end
    end

    return g_map.findEveryPath(start, maxDist, params)
end

-- Translate path nodes to direction list
CaveBot.Map.translatePathToDirections = function(paths, destPos)
    local predirections = {}
    local directions = {}
    local destPosStr = destPos

    if type(destPos) ~= 'string' then
        destPosStr = destPos.x .. "," .. destPos.y .. "," .. destPos.z
    end

    while destPosStr:len() > 0 do
        local node = paths[destPosStr]
        if not node then break end
        if node[3] < 0 then break end
        table.insert(predirections, node[3])
        destPosStr = node[4]
    end

    -- Reverse
    for i = #predirections, 1, -1 do
        table.insert(directions, predirections[i])
    end

    return directions
end

-- Find path from start to destination
CaveBot.Map.findPath = function(startPos, destPos, maxDist, params)
    --[[
      Available params:
        ignoreLastCreature
        ignoreCreatures
        ignoreNonPathable
        ignoreNonWalkable
        ignoreStairs
        ignoreCost
        allowUnseen
        allowOnlyVisibleTiles
        precision
        marginMin
        marginMax
        maxDistanceFrom
    ]]--
    if not destPos or startPos.z ~= destPos.z then
        return nil
    end

    maxDist = maxDist or 100

    if type(params) ~= 'table' then
        params = {}
    end

    local destPosStr = destPos.x .. "," .. destPos.y .. "," .. destPos.z
    params["destination"] = destPosStr

    local paths = CaveBot.Map.findAllPaths(startPos, maxDist, params)

    -- Handle margin
    local marginMin = params.marginMin or params.minMargin
    local marginMax = params.marginMax or params.maxMargin
    if type(marginMin) == 'number' and type(marginMax) == 'number' then
        local bestCandidate = nil
        local bestCandidatePos = nil
        for x = -marginMax, marginMax do
            for y = -marginMax, marginMax do
                if math.abs(x) >= marginMin or math.abs(y) >= marginMin then
                    local dest = (destPos.x + x) .. "," .. (destPos.y + y) .. "," .. destPos.z
                    local node = paths[dest]
                    if node and (not bestCandidate or bestCandidate[1] > node[1]) then
                        bestCandidate = node
                        bestCandidatePos = dest
                    end
                end
            end
        end
        if bestCandidate then
            return CaveBot.Map.translatePathToDirections(paths, bestCandidatePos)
        end
        return nil
    end

    -- Handle precision
    if not paths[destPosStr] then
        local precision = params.precision
        if type(precision) == 'number' then
            for p = 1, precision do
                local bestCandidate = nil
                local bestCandidatePos = nil
                for x = -p, p do
                    for y = -p, p do
                        local dest = (destPos.x + x) .. "," .. (destPos.y + y) .. "," .. destPos.z
                        local node = paths[dest]
                        if node and (not bestCandidate or bestCandidate[1] > node[1]) then
                            bestCandidate = node
                            bestCandidatePos = dest
                        end
                    end
                end
                if bestCandidate then
                    return CaveBot.Map.translatePathToDirections(paths, bestCandidatePos)
                end
            end
        end
        return nil
    end

    return CaveBot.Map.translatePathToDirections(paths, destPos)
end

-- Auto walk to destination
CaveBot.Map.autoWalk = function(destination, maxDist, params)
    local player = g_game.getLocalPlayer()
    if not player then return false end

    -- If destination is a list of directions, use directly
    if type(destination) == "table" and #destination > 0 and type(destination[1]) == "number" then
        g_game.autoWalk(destination, {x=0, y=0, z=0})
        return true
    end

    -- Find path to destination
    local path = CaveBot.Map.findPath(player:getPosition(), destination, maxDist, params)
    if not path or #path == 0 then
        return false
    end

    -- Autowalk without prewalk animation
    g_game.autoWalk(path, {x=0, y=0, z=0})
    return true
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Check if creature is trapped
CaveBot.Map.isTrapped = function(creature)
    if not creature then
        creature = g_game.getLocalPlayer()
    end
    if not creature then return false end

    local pos = creature:getPosition()
    local dirs = {{-1,1}, {0,1}, {1,1}, {-1, 0}, {1, 0}, {-1, -1}, {0, -1}, {1, -1}}

    for i = 1, #dirs do
        local tile = g_map.getTile({x = pos.x - dirs[i][1], y = pos.y - dirs[i][2], z = pos.z})
        if tile and tile:isWalkable(false) then
            return false
        end
    end
    return true
end

-- Conta vizinhos walkable (8-dir) de `pos`. `ignorePos` é opcional: tile que
-- não deve ser contado (ex: o tile "de onde estou vindo" — útil ao validar
-- intermediários de um path).
-- Tile contém item de floor change (escada/buraco/teleport/rampa)?
-- Delega ao canonico CaveBot.isFloorChangeTile (verdade do item: teleport OU attr 252),
-- sem tabela de ids nem cor de minimap.
local function tileHasFloorChange(pos)
    if not pos then return false end
    if CaveBot.isFloorChangeTile then return CaveBot.isFloorChangeTile(pos) end
    return false
end

CaveBot.Map.countWalkableNeighbors = function(pos, ignorePos)
    if not pos then return 0 end
    local count = 0
    for dx = -1, 1 do
        for dy = -1, 1 do
            if not (dx == 0 and dy == 0) then
                local p = {x = pos.x + dx, y = pos.y + dy, z = pos.z}
                if not (ignorePos and ignorePos.x == p.x and ignorePos.y == p.y and ignorePos.z == p.z) then
                    local tile = g_map.getTile(p)
                    if tile and tile:isWalkable(true) and not tileHasFloorChange(p) then
                        count = count + 1
                    end
                end
            end
        end
    end
    return count
end

-- Tile é dead-end? Heurística: < minEscapes vizinhos walkable (default 2).
-- Se passar `comingFrom`, esse vizinho não é contado (assume que aquela rota
-- está "atrás" de você — útil pra validar tile intermediário de um path).
CaveBot.Map.isDeadEnd = function(pos, comingFrom, minEscapes)
    return CaveBot.Map.countWalkableNeighbors(pos, comingFrom) < (minEscapes or 2)
end

-- Check if can shoot to position
CaveBot.Map.canShoot = function(pos, distance)
    distance = distance or 5
    local tile = g_map.getTile(pos)
    if tile then
        return tile:canShoot(distance)
    end
    return false
end

-- ============================================================================
-- GLOBAL ALIASES (para compatibilidade com a referência)
-- ============================================================================

-- Expor funções globalmente se não existirem
if not getPath then
    getPath = CaveBot.Map.findPath
end

if not findPath then
    findPath = CaveBot.Map.findPath
end

if not autoWalk then
    autoWalk = CaveBot.Map.autoWalk
end

if not findAllPaths then
    findAllPaths = CaveBot.Map.findAllPaths
end

if not isTrapped then
    isTrapped = CaveBot.Map.isTrapped
end

return CaveBot.Map
