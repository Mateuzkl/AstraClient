-- CaveBot Recorder - Auto recording for waypoints
-- Hooks into game_interface to detect item usage

CaveBot.Recorder = {}

local isEnabled = nil
local lastPos = nil
local pendingUseConfirmation = nil
local isSetup = false

-- Store original functions
local originalProcessMouseAction = nil

-- Show confirmation modal for use action
local function showUseConfirmation(actionType, actionValue, pos)
    -- Close any existing confirmation
    if pendingUseConfirmation and pendingUseConfirmation.window then
        pendingUseConfirmation.window:destroy()
        pendingUseConfirmation = nil
    end

    local posStr = pos.x .. ", " .. pos.y .. ", " .. pos.z
    local message = ""
    if actionType == "use" then
        message = "Add USE waypoint at position:\n" .. posStr .. "?"
    else
        message = "Add USE WITH waypoint at position:\n" .. posStr .. "?"
    end

    local confirmCallback = function()
        lastPos = pos
        CaveBot.addAction(actionType, actionValue, true)
        if pendingUseConfirmation and pendingUseConfirmation.window then
            pendingUseConfirmation.window:destroy()
        end
        pendingUseConfirmation = nil
        print("[Recorder] Added " .. actionType .. " waypoint at " .. posStr)
    end

    local cancelCallback = function()
        if pendingUseConfirmation and pendingUseConfirmation.window then
            pendingUseConfirmation.window:destroy()
        end
        pendingUseConfirmation = nil
    end

    -- Use displayGeneralBox if available
    if displayGeneralBox then
        local box = helperDisplayGeneralBox(
            "Add Waypoint",
            message,
            {
                { text = "Yes", callback = confirmCallback },
                { text = "No", callback = cancelCallback }
            },
            cancelCallback
        )
        pendingUseConfirmation = { window = box, actionType = actionType, actionValue = actionValue, pos = pos }
    else
        -- Fallback: add directly without confirmation
        confirmCallback()
    end
end

-- Handler for position changes
local function onPositionChange(newPos, oldPos)
    if CaveBot.isOn() or not isEnabled then return end
    if not newPos or not oldPos then return end

    local function addPosition(pos)
        local nodeDistance = CaveBot.Config.get("nodeDistance") or 2
        CaveBot.addAction("goto", pos.x .. "," .. pos.y .. "," .. pos.z .. "," .. nodeDistance, true)
        lastPos = pos
    end

    if not lastPos then
        addPosition(oldPos)
    elseif newPos.z ~= oldPos.z or math.abs(oldPos.x - newPos.x) > 1 or math.abs(oldPos.y - newPos.y) > 1 then
        addPosition(oldPos)
    elseif math.max(math.abs(lastPos.x - newPos.x), math.abs(lastPos.y - newPos.y)) > 5 then
        addPosition(newPos)
    end
end

-- Track last use action to avoid duplicates
local lastUsePos = nil
local lastUseTime = 0

-- Wrapper for processMouseAction to detect use actions
local function wrappedProcessMouseAction(menuPosition, mouseButton, autoWalkPos, lookThing, useThing, creatureThing, attackCreature)
    -- Call original function first to let the action happen
    local result = false
    if originalProcessMouseAction then
        result = originalProcessMouseAction(menuPosition, mouseButton, autoWalkPos, lookThing, useThing, creatureThing, attackCreature)
    end

    -- Check if recorder is enabled and cavebot is not running
    if not isEnabled or CaveBot.isOn() then
        return result
    end

    -- Only process if the action was handled (result = true means something was done)
    if not result then
        return result
    end

    -- Check if we have a usable thing at a map position
    if useThing and useThing.getPosition then
        local targetPos = useThing:getPosition()

        -- Check if it's a valid map position (not inventory, x != 65535)
        if targetPos and targetPos.x and targetPos.x ~= 65535 then
            -- Avoid duplicate prompts for the same position
            local now = g_clock.millis()
            if lastUsePos and lastUsePos.x == targetPos.x and lastUsePos.y == targetPos.y and lastUsePos.z == targetPos.z then
                if now - lastUseTime < 2000 then
                    return result
                end
            end

            -- Check if the useThing is actually usable (not container, not creature)
            local isUsable = false
            if useThing.isItem and useThing:isItem() then
                -- It's an item - could be usable
                isUsable = true
            elseif useThing.isTile then
                -- It's a tile thing (like stairs, levers, etc)
                isUsable = true
            end

            if isUsable then
                lastUsePos = {x = targetPos.x, y = targetPos.y, z = targetPos.z}
                lastUseTime = now

                local actionValue = targetPos.x .. "," .. targetPos.y .. "," .. targetPos.z

                -- Schedule the confirmation to show after a short delay
                scheduleEvent(function()
                    if isEnabled and not CaveBot.isOn() then
                        showUseConfirmation("use", actionValue, targetPos)
                    end
                end, 200)
            end
        end
    end

    return result
end

-- Setup function intercepts
local function setup()
    if isSetup then return end
    isSetup = true

    -- Hook into global processMouseAction function
    if processMouseAction and not originalProcessMouseAction then
        originalProcessMouseAction = processMouseAction
        -- Replace global function
        _G.processMouseAction = wrappedProcessMouseAction
        print("[Recorder] Hooked into processMouseAction")
    else
        print("[Recorder] Warning: Could not hook into processMouseAction (processMouseAction=" .. tostring(processMouseAction) .. ")")
    end

    -- Connect to player position changes
    local function connectPositionCallback()
        local player = g_game.getLocalPlayer()
        if player then
            connect(player, {
                onPositionChange = onPositionChange
            })
        end
    end

    if g_game.isOnline() then
        connectPositionCallback()
    end

    connect(g_game, {
        onGameStart = connectPositionCallback
    })
end

-- Restore original functions
local function cleanup()
    if not isSetup then return end

    -- Restore original processMouseAction
    if originalProcessMouseAction then
        _G.processMouseAction = originalProcessMouseAction
        originalProcessMouseAction = nil
    end

    -- Disconnect player position
    local player = g_game.getLocalPlayer()
    if player then
        disconnect(player, {
            onPositionChange = onPositionChange
        })
    end

    isSetup = false
end

CaveBot.Recorder.isOn = function()
    return isEnabled
end

CaveBot.Recorder.enable = function()
    CaveBot.setOff()
    setup()

    if CaveBot.UI and CaveBot.UI.recordButton then
        CaveBot.UI.recordButton:setOn(true)
    end

    isEnabled = true
    lastPos = nil

    print("[Recorder] Enabled - Walk around to record waypoints. Use items to add USE waypoints.")
end

CaveBot.Recorder.disable = function()
    if isEnabled == true then
        isEnabled = false
    end

    if pendingUseConfirmation and pendingUseConfirmation.window then
        pendingUseConfirmation.window:destroy()
        pendingUseConfirmation = nil
    end

    if CaveBot.UI and CaveBot.UI.recordButton then
        CaveBot.UI.recordButton:setOn(false)
    end

    CaveBot.save()

    print("[Recorder] Disabled - Waypoints saved")
end

CaveBot.Recorder.toggle = function()
    if isEnabled then
        CaveBot.Recorder.disable()
    else
        CaveBot.Recorder.enable()
    end
end

CaveBot.Recorder.reset = function()
    lastPos = nil
end

CaveBot.Recorder.terminate = function()
    CaveBot.Recorder.disable()
    cleanup()
end

-- Manual functions to add use waypoint from current target position
CaveBot.Recorder.addUseWaypoint = function(pos)
    if not pos then
        print("[Recorder] Error: No position provided")
        return false
    end

    local actionValue = pos.x .. "," .. pos.y .. "," .. pos.z
    showUseConfirmation("use", actionValue, pos)
    return true
end

CaveBot.Recorder.addUseWithWaypoint = function(itemId, pos)
    if not pos then
        print("[Recorder] Error: No position provided")
        return false
    end

    local actionValue = (itemId or 0) .. "," .. pos.x .. "," .. pos.y .. "," .. pos.z
    showUseConfirmation("usewith", actionValue, pos)
    return true
end
