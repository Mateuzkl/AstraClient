local opcodeCallbacks = {}
local extendedCallbacks = {}
local extendedJSONCallbacks = {}
local extendedJSONData = {}
local maxPacketSize = 65000
local maxJSONMessageSize = 8 * 1024 * 1024
local maxJSONBufferedSize = 16 * 1024 * 1024
local jsonAssemblyTimeout = 30000
local jsonBufferedSize = 0

local function clearJSONAssembly(opcode)
  local assembly = extendedJSONData[opcode]
  if assembly then
    extendedJSONData[opcode] = nil
    jsonBufferedSize = jsonBufferedSize - assembly.size
    if assembly.timeout then removeEvent(assembly.timeout) end
  end
end

local function clearJSONAssemblies()
  for opcode in pairs(extendedJSONData) do clearJSONAssembly(opcode) end
end

local function rejectJSONAssembly(opcode, reason)
  clearJSONAssembly(opcode)
  if g_logger and g_logger.warning then
    g_logger.warning('Invalid extended JSON opcode ' .. opcode .. ': ' .. reason)
  end
end

-- Reload must retire the previous registry's timers and game-end connection.
if ProtocolGame._clearExtendedJSONAssemblies then
  ProtocolGame._clearExtendedJSONAssemblies()
  if g_game and disconnect then
    disconnect(g_game, {onGameEnd = ProtocolGame._clearExtendedJSONAssemblies})
  end
end
ProtocolGame._clearExtendedJSONAssemblies = clearJSONAssemblies
if g_game and connect then
  connect(g_game, {onGameEnd = clearJSONAssemblies})
end

function ProtocolGame:onOpcode(opcode, msg)
  for i, callback in pairs(opcodeCallbacks) do
    if i == opcode then
      callback(self, msg)
      return true
    end
  end
  return false
end

function ProtocolGame:onExtendedOpcode(opcode, buffer)
  local callback = extendedCallbacks[opcode]
  if callback then
    callback(self, opcode, buffer)
  end

  callback = extendedJSONCallbacks[opcode]
  if callback then
    local status = buffer:sub(1,1) -- O - just one message, S - start, P - part, E - end
    local payload
    if status == 'S' or status == 'P' or status == 'E' then
      if status == 'S' then
        clearJSONAssembly(opcode)
        local assembly = {owner = self, callback = callback, chunks = {}, size = 0}
        extendedJSONData[opcode] = assembly
        assembly.timeout = scheduleEvent(function()
          if extendedJSONData[opcode] == assembly then
            rejectJSONAssembly(opcode, 'assembly timed out')
          end
        end, jsonAssemblyTimeout)
      end
      local assembly = extendedJSONData[opcode]
      if not assembly or assembly.owner ~= self or assembly.callback ~= callback then
        rejectJSONAssembly(opcode, 'fragment without a matching start')
        return
      end
      local size = #buffer - 1
      if assembly.size + size > maxJSONMessageSize or jsonBufferedSize + size > maxJSONBufferedSize then
        rejectJSONAssembly(opcode, 'assembly size limit exceeded')
        return
      end
      assembly.chunks[#assembly.chunks + 1] = buffer:sub(2)
      assembly.size = assembly.size + size
      jsonBufferedSize = jsonBufferedSize + size
      if status ~= 'E' then return end
      -- One concatenation, instead of copying the entire prefix for every chunk.
      payload = table.concat(assembly.chunks)
      clearJSONAssembly(opcode)
    else
      clearJSONAssembly(opcode)
      if #buffer > maxJSONMessageSize then
        rejectJSONAssembly(opcode, 'message size limit exceeded')
        return
      end
      payload = buffer
    end
    local ok, data = pcall(json.decode, payload)
    if not ok then
      rejectJSONAssembly(opcode, tostring(data))
      return
    end
    callback(self, opcode, data)
  end
end

function ProtocolGame.registerOpcode(opcode, callback)
  if opcodeCallbacks[opcode] then
    error('opcode ' .. opcode .. ' already registered will be overriden')
  end

  opcodeCallbacks[opcode] = callback
end

function ProtocolGame.unregisterOpcode(opcode)
  opcodeCallbacks[opcode] = nil
end

function ProtocolGame.registerExtendedOpcode(opcode, callback)
  if not callback or type(callback) ~= 'function' then
    error('Invalid callback.')
  end

  if not opcode or type(opcode) ~= 'number' or opcode < 0 or opcode > 255 or math.floor(opcode) ~= opcode then
    error('Invalid opcode. Range: 0-255')
  end

  if extendedCallbacks[opcode] then
    error('Opcode is already taken.')
  end

  extendedCallbacks[opcode] = callback
end

function ProtocolGame.unregisterExtendedOpcode(opcode)
  if not opcode or type(opcode) ~= 'number' or opcode < 0 or opcode > 255 or math.floor(opcode) ~= opcode then
    error('Invalid opcode. Range: 0-255')
  end

  if not extendedCallbacks[opcode] then
    error('Opcode is not registered.')
  end

  extendedCallbacks[opcode] = nil
end

function ProtocolGame.registerExtendedJSONOpcode(opcode, callback)
  if not callback or type(callback) ~= 'function' then
    error('Invalid callback.')
  end

  if not opcode or type(opcode) ~= 'number' or opcode < 0 or opcode > 255 or math.floor(opcode) ~= opcode then
    error('Invalid opcode. Range: 0-255')
  end

  if extendedJSONCallbacks[opcode] then
    error('Opcode is already taken.')
  end

  extendedJSONCallbacks[opcode] = callback
end

function ProtocolGame.unregisterExtendedJSONOpcode(opcode, expectedCallback)
  if not opcode or type(opcode) ~= 'number' or opcode < 0 or opcode > 255 or math.floor(opcode) ~= opcode then
    error('Invalid opcode. Range: 0-255')
  end

  -- An optional owner check makes teardown harmless if another module took over.
  if expectedCallback and extendedJSONCallbacks[opcode] ~= expectedCallback then
    return false
  end
  if not extendedJSONCallbacks[opcode] then
    error('Opcode is not registered.')
  end

  clearJSONAssembly(opcode)
  extendedJSONCallbacks[opcode] = nil
  if expectedCallback then return true end
end

function ProtocolGame:sendExtendedJSONOpcode(opcode, data)
  if not opcode or type(opcode) ~= 'number' or opcode < 0 or opcode > 255 or math.floor(opcode) ~= opcode then
    error('Invalid opcode. Range: 0-255')
  end

  if type(data) ~= "table" then
    error('Invalid data type, should be table')
  end

  local buffer = json.encode(data)
  local s = {}
  for i=1, #buffer, maxPacketSize do
     s[#s+1] = buffer:sub(i,i+maxPacketSize - 1)
  end
  if #s == 1 then
    self:sendExtendedOpcode(opcode, s[1])
    return
  end
  self:sendExtendedOpcode(opcode, "S" .. s[1])
  for i=2,#s - 1 do
    self:sendExtendedOpcode(opcode, "P" .. s[i])
  end
  self:sendExtendedOpcode(opcode, "E" .. s[#s])
end
