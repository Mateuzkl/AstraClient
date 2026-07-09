--[[
  CommandBridge - generic JSON bus over extended opcode 211.

  Ported from AMON (game_command_bridge). This is the FAITHFUL generic transport
  only: state merge + send/request + on/onState event handlers + chunked (S/P/E)
  payload decode + json. All AMON-specific integrations (infinite supplies overlay,
  system.device_info, staff_check, share/party level requests) were STRIPPED for
  the KoliseuOT/AstraClient port.

  Exposes the global `CommandBridge` with:
    CommandBridge.getState()
    CommandBridge.onState(fn) / CommandBridge.offState(fn)
    CommandBridge.send(action, data, opts)
    CommandBridge.request(action, data, onResponse)
    CommandBridge.on(eventName, fn) / CommandBridge.off(eventName, fn)

  Wire:
    send    -> protocol:sendExtendedOpcode(211, json.encode(payload))
    receive -> ProtocolGame.registerExtendedOpcode(211, onExtendedOpcode)
]]

local COMMAND_OPCODE = 211

CommandBridge = CommandBridge or {}
CommandBridge.OPCODE = COMMAND_OPCODE
CommandBridge.state = CommandBridge.state or {}
CommandBridge.handlers = CommandBridge.handlers or {}
CommandBridge.stateHandlers = CommandBridge.stateHandlers or {}
CommandBridge.pending = CommandBridge.pending or {}
CommandBridge.nextRequestId = CommandBridge.nextRequestId or 1

local function exposeGlobal(name, value)
    local mt = getmetatable(_G)
    local globalEnv = (mt and type(mt.__index) == "table") and mt.__index or _G
    globalEnv[name] = value
    if globalEnv ~= _G then
        rawset(_G, name, value)
    end
end

CommandBridge.Group = {
    PLAYER = 1,
    TUTOR = 2,
    SENIOR_TUTOR = 3,
    GAMEMASTER = 4,
    COMMUNITY_MANAGER = 5,
    GOD = 6,
}

exposeGlobal("CommandBridge", CommandBridge)

local invalidPayloadLogged = false
local chunkBuffer = {}

local function isTerminalCommand()
    if type(getfenv) ~= "function" then
        return false
    end

    local commandEnv = rawget(_G, "commandEnv")
    if type(commandEnv) ~= "table" then
        return false
    end

    return getfenv(2) == commandEnv
end

local function clearTable(t)
    for key in pairs(t) do
        t[key] = nil
    end
end

local function emit(list, ...)
    if not list then
        return
    end

    for i = 1, #list do
        local handler = list[i]
        if handler then
            local ok, err = pcall(handler, ...)
            if not ok and g_logger then
                g_logger.error(string.format("[CommandBridge] handler error: %s", err))
            end
        end
    end
end

local function mergeState(target, patch)
    for key, value in pairs(patch) do
        if type(value) == "table" and type(target[key]) == "table" then
            -- Arrays should be replaced entirely, not merged, to handle removals.
            local isArray = false
            if value[1] ~= nil then
                isArray = true
                local count = 0
                for _ in pairs(value) do count = count + 1 end
                if count ~= #value then
                    isArray = false -- Has non-sequential keys, treat as object.
                end
            elseif next(value) == nil then
                -- Empty table from server should replace (could be empty array).
                isArray = true
            end

            if isArray then
                target[key] = value -- Replace entire array.
            else
                mergeState(target[key], value) -- Merge objects recursively.
            end
        else
            target[key] = value
        end
    end
end

local function decodeIfString(value)
    if type(value) ~= "string" then
        return value
    end
    if not json or not json.decode then
        return value
    end

    local ok, decoded = pcall(json.decode, value)
    if ok then
        return decoded
    end

    return value
end

local function decodePayload(buffer)
    if type(buffer) == "table" then
        return buffer
    end
    if type(buffer) ~= "string" then
        return nil
    end
    if not json or not json.decode then
        return nil
    end

    local ok, decoded = pcall(json.decode, buffer)
    if ok then
        return decoded
    end

    return nil
end

local function decodeChunkedPayload(opcode, buffer)
    if type(buffer) ~= "string" or buffer == "" then
        return nil
    end

    local status = buffer:sub(1, 1)
    if status ~= "S" and status ~= "P" and status ~= "E" then
        return decodePayload(buffer)
    end

    local data = buffer:sub(2)
    if status ~= "E" and status ~= "P" then
        chunkBuffer[opcode] = ""
    end

    chunkBuffer[opcode] = (chunkBuffer[opcode] or "") .. data

    if status == "S" or status == "P" then
        return nil
    end

    local assembled = chunkBuffer[opcode]
    chunkBuffer[opcode] = nil
    return decodePayload(assembled)
end

local function resolveRequestId(data)
    return data.requestId or data.replyTo or data.responseTo
end

local function handleState(data)
    local patch = data.state or data.data or data.payload
    patch = decodeIfString(patch)
    if type(patch) ~= "table" then
        return false
    end

    mergeState(CommandBridge.state, patch)
    emit(CommandBridge.stateHandlers, CommandBridge.state, patch, data)
    return true
end

local function handleResponse(data)
    local requestId = resolveRequestId(data)
    if requestId == nil then
        return false
    end

    local entry = CommandBridge.pending[requestId]
    if not entry then
        return false
    end

    CommandBridge.pending[requestId] = nil
    if entry.callback then
        -- A "throttled" reply means the server rejected this request for rate-limiting and
        -- did NOT act on it. Deliver nil so the caller's standard `type(response) ~= 'table'`
        -- guard simply clears its pending flag and returns, instead of applying an empty
        -- payload as if it were real data. This unlocks request-driven UIs (button/window
        -- pending flags) immediately rather than stranding them until their own watchdog.
        local payload = data
        if type(data) == "table" and data.type == "throttled" then
            payload = nil
        end
        local ok, err = pcall(entry.callback, payload)
        if not ok and g_logger then
            g_logger.error(string.format("[CommandBridge] response handler error: %s", err))
        end
    end

    return true
end

local function handleEvent(data)
    local eventName = data.event or data.action
    if type(eventName) ~= "string" or eventName == "" then
        return false
    end

    local list = CommandBridge.handlers[eventName]
    if not list then
        return false
    end

    emit(list, data)
    return true
end

local function onExtendedOpcode(protocol, opcode, buffer)
    if opcode ~= COMMAND_OPCODE then
        return
    end

    local data = decodeChunkedPayload(opcode, buffer)
    if not data then
        return
    end

    data = decodeIfString(data)
    if type(data) ~= "table" then
        if not invalidPayloadLogged then
            invalidPayloadLogged = true
            if g_logger then
                g_logger.warning(string.format(
                    "[CommandBridge] ignored opcode %d payload; expected table, got %s",
                    opcode,
                    type(data)
                ))
            end
        end
        return
    end

    local handled = false

    if data.type == "state" or data.event == "state" or data.state ~= nil then
        handled = handleState(data) or handled
    end

    if data.type == "response" or data.type == "error" then
        handled = handleResponse(data) or handled
    else
        if handleResponse(data) then
            handled = true
        end
    end

    if not handled then
        handleEvent(data)
    end
end

function CommandBridge.on(eventName, handler)
    if type(eventName) ~= "string" or eventName == "" then
        error("Invalid event name")
    end
    if type(handler) ~= "function" then
        error("Invalid handler")
    end

    local list = CommandBridge.handlers[eventName]
    if not list then
        list = {}
        CommandBridge.handlers[eventName] = list
    end

    table.insert(list, handler)
end

function CommandBridge.off(eventName, handler)
    local list = CommandBridge.handlers[eventName]
    if not list then
        return false
    end

    for i = #list, 1, -1 do
        if list[i] == handler then
            table.remove(list, i)
            return true
        end
    end

    return false
end

function CommandBridge.onState(handler)
    if type(handler) ~= "function" then
        error("Invalid handler")
    end

    table.insert(CommandBridge.stateHandlers, handler)
end

function CommandBridge.offState(handler)
    local list = CommandBridge.stateHandlers
    for i = #list, 1, -1 do
        if list[i] == handler then
            table.remove(list, i)
            return true
        end
    end

    return false
end

function CommandBridge.getState()
    return CommandBridge.state
end

function CommandBridge.send(action, data, opts)
    if type(action) ~= "string" or action == "" then
        error("Invalid action")
    end
    if isTerminalCommand() then
        if g_logger then
            g_logger.warning("[CommandBridge] send blocked from terminal")
        end
        return nil
    end

    local protocol = g_game.getProtocolGame()
    if not protocol then
        return nil
    end

    local payload = { action = action }
    if data ~= nil then
        payload.data = data
    end

    if opts and opts.requestId ~= nil then
        payload.requestId = opts.requestId
    end

    if opts and opts.expectResponse then
        local requestId = payload.requestId
        if requestId == nil then
            requestId = CommandBridge.nextRequestId
            CommandBridge.nextRequestId = CommandBridge.nextRequestId + 1
            payload.requestId = requestId
        end

        CommandBridge.pending[requestId] = {
            callback = opts.onResponse,
            timestamp = (g_clock and g_clock.seconds()) or os.time()
        }
    end

    if json and json.encode then
        protocol:sendExtendedOpcode(COMMAND_OPCODE, json.encode(payload))
    elseif g_logger then
        g_logger.error("[CommandBridge] JSON encoder not available")
    end
    return payload.requestId
end

function CommandBridge.request(action, data, onResponse)
    return CommandBridge.send(action, data, {
        expectResponse = true,
        onResponse = onResponse
    })
end

local function resetState()
    clearTable(CommandBridge.state)
    clearTable(CommandBridge.pending)
    CommandBridge.nextRequestId = 1
end

function init()
    if ProtocolGame and ProtocolGame.registerExtendedOpcode then
        ProtocolGame.registerExtendedOpcode(COMMAND_OPCODE, onExtendedOpcode)
    end

    connect(g_game, {
        onGameEnd = resetState
    })
end

function terminate()
    disconnect(g_game, {
        onGameEnd = resetState
    })

    if ProtocolGame and ProtocolGame.unregisterExtendedOpcode then
        pcall(ProtocolGame.unregisterExtendedOpcode, COMMAND_OPCODE)
    end

    resetState()
end
