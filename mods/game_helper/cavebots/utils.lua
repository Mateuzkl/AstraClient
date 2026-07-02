-- Cavebot Walker Utils Module
-- Funcoes utilitarias compartilhadas entre os modulos

local CavebotUtils = {}

-- Debug flag (can be enabled for troubleshooting)
CavebotUtils.DEBUG_LOG_ENABLED = false  -- ENABLED FOR STAIR DEBUG

-- ============================================================================
-- WAYPOINT TYPE MAPS
-- ============================================================================

CavebotUtils.waypointTypeMap = {
    [0] = "node", [1] = "stand", [2] = "use", [3] = "rope",
    [4] = "hole", [5] = "lever", [90] = "special", [98] = "goto", [99] = "label"
}

CavebotUtils.waypointTypeSet = {
    node = true, stand = true, use = true, rope = true, hole = true,
    lever = true, special = true, ["goto"] = true, label = true,
    buy_refill = true, stop_to_kill = true,
    deposit = true, bank = true, travel = true, door = true,
    wait_delay = true, levitate = true, stop_cavebot = true,
    script = true,
}

CavebotUtils.standLikeTypes = {
    stand = true, buy_refill = true, stop_to_kill = true,
    deposit = true, bank = true, travel = true,
}

-- ============================================================================
-- CONVERSAO DE WAYPOINT
-- ============================================================================

function CavebotUtils.waypointTypeToString(wpType)
    if type(wpType) == "string" then
        local lowered = wpType:match("^%s*(.-)%s*$"):lower()
        if CavebotUtils.waypointTypeSet[lowered] then return lowered end
        local numeric = tonumber(lowered)
        if numeric and CavebotUtils.waypointTypeMap[numeric] then
            return CavebotUtils.waypointTypeMap[numeric]
        end
        return "node"
    end
    if type(wpType) == "number" then
        return CavebotUtils.waypointTypeMap[wpType] or "node"
    end
    return "node"
end

function CavebotUtils.isStandLikeType(wpType)
    return CavebotUtils.standLikeTypes[CavebotUtils.waypointTypeToString(wpType)] == true
end

function CavebotUtils.normalizeWaypoints(waypoints)
    if not waypoints then return nil end
    local normalized = {}
    for i, wp in ipairs(waypoints) do
        if wp then
            local nwp = {}
            for k, v in pairs(wp) do nwp[k] = v end
            nwp.type = CavebotUtils.waypointTypeToString(wp.type)
            normalized[i] = nwp
        else
            normalized[i] = wp
        end
    end
    return normalized
end

function CavebotUtils.normalizeWalkMode(mode)
    if type(mode) == "string" and mode:lower() == "click" then return "click" end
    if mode == true then return "click" end
    return "walk"
end

function CavebotUtils.normalizeLabelName(labelName)
    if labelName == nil then return nil end
    local trimmed = tostring(labelName):match("^%s*(.-)%s*$")
    return trimmed ~= "" and trimmed or nil
end

function CavebotUtils.isFloorChangeWaypoint(waypoint)
    if not waypoint then return false end
    local wpType = CavebotUtils.waypointTypeToString(waypoint.type)
    return waypoint.teleport or wpType == "use" or wpType == "rope" or wpType == "hole" or wpType == "lever"
end

function CavebotUtils.isGotoConditionMet(waypoint)
    if not waypoint then return false end
    local condition = waypoint.gotoCondition or "none"
    if condition == "none" then return true end

    local player = g_game.getLocalPlayer()
    if not player or not player.getStamina then return false end

    local staminaValue = tonumber(waypoint.gotoStamina)
    if not staminaValue then return false end

    -- getStamina() retorna MINUTOS (0-2520); a UI recebe o limite em HORAS
    -- (0-42). Converte o limite para minutos antes de comparar.
    local currentStamina = player:getStamina()
    local thresholdMinutes = staminaValue * 60
    if condition == "stamina_lt" then return currentStamina < thresholdMinutes end
    if condition == "stamina_gt" then return currentStamina > thresholdMinutes end
    return true
end

-- ============================================================================
-- BLOCKED POSITION (centralizado)
-- ============================================================================

function CavebotUtils.isBlockedPosition(pos, blockedPositions)
    if not pos or not blockedPositions then return false end
    local key = string.format("%d,%d,%d", pos.x, pos.y, pos.z)
    return blockedPositions[key] == true
end

function CavebotUtils.posToKey(pos)
    return string.format("%d,%d,%d", pos.x, pos.y, pos.z)
end

-- ============================================================================
-- PROTECTION ZONE
-- ============================================================================

function CavebotUtils.isInProtectionZone()
    local player = g_game.getLocalPlayer()
    if not player then return false end
    if player.isInProtectionZone then return player:isInProtectionZone() end
    if PlayerStates and player.getStates then
        return bit.band(player:getStates(), PlayerStates.Pz) > 0
    end
    return false
end

-- ============================================================================
-- TILE FUNCTIONS
-- ============================================================================

function CavebotUtils.isTileWalkable(pos, ignoreCreatures)
    if not pos then return false end
    local tile = g_map.getTile(pos)
    if not tile then return false end
    return tile:isWalkable(ignoreCreatures or false)
end

function CavebotUtils.isBlockingItem(thing)
    if not thing or not thing.isItem or not thing:isItem() then return false end
    if not g_things or not g_things.getThingType then return false end
    local itemType = g_things.getThingType(thing:getId(), ThingCategoryItem)
    if not itemType then return false end
    -- Apenas isNotWalkable (unpass) bloqueia, isNotPathable (avoid) não bloqueia
    return itemType:isNotWalkable()
end

function CavebotUtils.isTileBlockedByAssets(tile, ignoreFloorChange)
    if not tile then return true end
    local ground = tile:getGround()
    if not ground then return true end
    if CavebotUtils.isBlockingItem(ground) then return true end

    local items = tile:getItems()
    if items then
        for _, item in ipairs(items) do
            if item and item ~= ground and CavebotUtils.isBlockingItem(item) then
                return true
            end
        end
    end
    if tile.isWalkable and not tile:isWalkable(true) then return true end
    
    -- Verificar floor change (não andável para nodes, a menos que seja ignorado)
    if not ignoreFloorChange then
        local pos = tile:getPosition()
        if pos and CavebotUtils.isFloorChangeTile(pos) then
            return true
        end
    end
    
    return false
end

function CavebotUtils.isFloorChangeTile(pos)
    if not pos then return false end
    local THING_ATTR_FLOOR_CHANGE = 252
    local tile = g_map.getTile(pos)
    if not tile then return false end

    local things = tile:getThings() or {}
    for _, thing in ipairs(things) do
        if thing and thing:isItem() then
            local itemType = g_things.getThingType(thing:getId(), ThingCategoryItem)
            if itemType then
                -- Check for floor change attribute
                if itemType:hasAttribute(THING_ATTR_FLOOR_CHANGE) then
                    return true
                end
                -- Also check for elevation (stairs usually have this)
                if itemType:hasElevation() then
                    return true
                end
            end
        end
    end
    
    -- Also check if tile itself has floor change properties
    -- Some tiles have isFloorChange method
    if tile.hasFloorChange and tile:hasFloorChange() then
        return true
    end
    
    return false
end

function CavebotUtils.findNearbyFloorChangeTile(origin, range)
    if not origin then return nil end
    local bestPos, bestDist = nil, nil
    range = range or 2

    for dx = -range, range do
        for dy = -range, range do
            local checkPos = {x = origin.x + dx, y = origin.y + dy, z = origin.z}
            if CavebotUtils.isFloorChangeTile(checkPos) then
                local dist = math.max(math.abs(dx), math.abs(dy))
                if not bestDist or dist < bestDist then
                    bestDist, bestPos = dist, checkPos
                    if dist == 0 then return bestPos end
                end
            end
        end
    end
    return bestPos
end

function CavebotUtils.getUsableThing(tile)
    if not tile then return nil end
    local thing = tile:getTopUseThing()
    if not thing then thing = tile:getTopMultiUseThing() end
    if not thing then thing = tile:getTopThing() end
    return thing
end

-- ============================================================================
-- CREATURE FUNCTIONS
-- ============================================================================

function CavebotUtils.isPlayerSummon(creature)
    if not creature then return false end
    if creature.getType then
        local cType = creature:getType()
        if cType == CreatureTypeSummonOwn or cType == CreatureTypeSummonOther then return true end
    end
    if creature.getMasterId then
        local masterId = creature:getMasterId()
        -- Any master = summon (incl. monster summons como necromancer_raise_dead).
        if masterId and masterId > 0 then return true end
    end
    return false
end

function CavebotUtils.shouldIgnoreCreature(creature, ignoredCreatures)
    if CavebotUtils.isPlayerSummon(creature) then return true end
    if not ignoredCreatures or #ignoredCreatures == 0 then return false end

    local creatureName = creature:getName():lower()
    for _, ignoredName in ipairs(ignoredCreatures) do
        if creatureName == ignoredName:lower() then return true end
    end
    return false
end

-- ============================================================================
-- NPC FUNCTIONS (centralizado)
-- ============================================================================

function CavebotUtils.findNearestNpc()
    local npcs = CreatureCache.getNpcs()
    if not npcs or #npcs == 0 then return nil end

    local nearestNpc, minDist = nil, math.huge
    for _, entry in ipairs(npcs) do
        if entry.sameFloor then
            local dist = math.max(entry.dx, entry.dy)
            if dist < minDist then
                minDist = dist
                nearestNpc = entry.creature
            end
        end
    end
    return nearestNpc
end

function CavebotUtils.sendNpcMessage(message)
    local npc = CavebotUtils.findNearestNpc()
    local npcName = npc and npc:getName() or ""
    g_game.talkPrivate(MessageModes.NpcTo, npcName, message)
end

-- ============================================================================
-- ITEM COUNT (centralizado)
-- ============================================================================

function CavebotUtils.getItemCount(itemId)
    if modules.game_helper and modules.game_helper.getItemCountAnywhere then
        return modules.game_helper.getItemCountAnywhere(itemId)
    end
    return 0
end

-- ============================================================================
-- STEP DURATION
-- ============================================================================

function CavebotUtils.getStepDuration(direction, playerPos, config)
    local player = g_game.getLocalPlayer()
    if not player then return config.walkDelay or 20 end

    local speedA, speedB, speedC = 2057.36, 261.29, -4000
    local playerSpeed = player:getSpeed() or 0
    local calculatedStepSpeed = math.max(math.floor((speedA * math.log(playerSpeed + speedB) + speedC) + 0.5), 1)
    if playerSpeed <= -speedB then calculatedStepSpeed = 1 end

    local groundSpeed = 150
    if direction and playerPos then
        local nextPos = CavebotUtils.translatePosition(playerPos, direction)
        if nextPos then
            local tile = g_map.getTile(nextPos)
            if tile and tile.getGroundSpeed then
                groundSpeed = tile:getGroundSpeed()
                if groundSpeed == 0 then groundSpeed = 150 end
            end
        end
    end

    local duration = math.floor(1000 * groundSpeed / calculatedStepSpeed)
    local stepDuration = math.ceil(duration / 50)
    if stepDuration == 1 then stepDuration = 0 end

    local ping = g_game.getPing() or 15
    stepDuration = stepDuration + (config.walkDelay or 0) + (ping / 10)
    return math.floor(math.max(1, math.min(10000, stepDuration)))
end

-- ============================================================================
-- DIRECTION AND POSITION
-- ============================================================================

function CavebotUtils.translatePosition(pos, direction)
    if not pos then return nil end
    local nextPos = {x = pos.x, y = pos.y, z = pos.z}
    local offsets = {
        [0] = {0, -1}, [1] = {1, 0}, [2] = {0, 1}, [3] = {-1, 0},
        [4] = {1, -1}, [5] = {1, 1}, [6] = {-1, 1}, [7] = {-1, -1}
    }
    local dir = direction
    if Directions then
        if direction == Directions.North then dir = 0
        elseif direction == Directions.East then dir = 1
        elseif direction == Directions.South then dir = 2
        elseif direction == Directions.West then dir = 3
        elseif direction == Directions.NorthEast then dir = 4
        elseif direction == Directions.SouthEast then dir = 5
        elseif direction == Directions.SouthWest then dir = 6
        elseif direction == Directions.NorthWest then dir = 7 end
    end
    local offset = offsets[dir]
    if offset then
        nextPos.x = nextPos.x + offset[1]
        nextPos.y = nextPos.y + offset[2]
    end
    return nextPos
end

function CavebotUtils.getDirection(from, to)
    local dx = to.x - from.x
    local dy = to.y - from.y
    if dx == 0 and dy == 0 then return Directions.Invalid end

    dx = (dx ~= 0) and (dx / math.abs(dx)) or 0
    dy = (dy ~= 0) and (dy / math.abs(dy)) or 0

    local dirMatrix = {
        {Directions.NorthWest, Directions.North, Directions.NorthEast},
        {Directions.West, Directions.Invalid, Directions.East},
        {Directions.SouthWest, Directions.South, Directions.SouthEast}
    }
    return dirMatrix[dy + 2][dx + 2]
end

function CavebotUtils.isDiagonalDirection(dir)
    return dir == Directions.NorthEast or dir == Directions.SouthEast or
           dir == Directions.SouthWest or dir == Directions.NorthWest or
           dir == 4 or dir == 5 or dir == 6 or dir == 7
end

function CavebotUtils.decomposeDiagonal(dir)
    local decomp = {
        [Directions.NorthEast] = {0, 1}, [4] = {0, 1},
        [Directions.SouthEast] = {2, 1}, [5] = {2, 1},
        [Directions.SouthWest] = {2, 3}, [6] = {2, 3},
        [Directions.NorthWest] = {0, 3}, [7] = {0, 3}
    }
    local d = decomp[dir]
    return d and d[1], d and d[2]
end

function CavebotUtils.isMonsterAhead(origin, target, direction, rangeX, rangeY)
    if not direction or not origin or not target then return false end

    local dx = target.x - origin.x
    local dy = target.y - origin.y
    if dx == 0 and dy == 0 then return false end

    local dir = direction
    if Directions then
        if direction == Directions.North then dir = 0
        elseif direction == Directions.East then dir = 1
        elseif direction == Directions.South then dir = 2
        elseif direction == Directions.West then dir = 3
        elseif direction == Directions.NorthEast then dir = 4
        elseif direction == Directions.SouthEast then dir = 5
        elseif direction == Directions.SouthWest then dir = 6
        elseif direction == Directions.NorthWest then dir = 7 end
    end

    local checks = {
        [0] = function() return dy < 0 end,
        [1] = function() return dx > 0 end,
        [2] = function() return dy > 0 end,
        [3] = function() return dx < 0 end,
        [4] = function() return (dx >= 0 and dy <= 0) and not (dx == 0 and dy == 0) end,
        [5] = function() return (dx >= 0 and dy >= 0) and not (dx == 0 and dy == 0) end,
        [6] = function() return (dx <= 0 and dy >= 0) and not (dx == 0 and dy == 0) end,
        [7] = function() return (dx <= 0 and dy <= 0) and not (dx == 0 and dy == 0) end
    }
    return checks[dir] and checks[dir]() or false
end

-- ============================================================================
-- DISTANCE
-- ============================================================================

function CavebotUtils.getChebyshevDistance(pos1, pos2)
    if not pos1 or not pos2 then return 999, 999 end
    return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y)), math.abs(pos1.z - pos2.z)
end

function CavebotUtils.getManhattanDistance(pos1, pos2)
    if not pos1 or not pos2 then return 999 end
    return math.abs(pos1.x - pos2.x) + math.abs(pos1.y - pos2.y)
end

-- ============================================================================
-- SCHEDULING
-- ============================================================================

function CavebotUtils.scheduleTrackedEvent(callback, delay, scheduledEvents)
    local eventId = scheduleEvent(callback, delay)
    if eventId and scheduledEvents then
        table.insert(scheduledEvents, eventId)
    end
    return eventId
end

return CavebotUtils
