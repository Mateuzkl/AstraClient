local opcodeCallbacks = {}
local extendedCallbacks = {}
local extendedJSONCallbacks = {}
local extendedJSONData = {}
local maxPacketSize = 65000

function ProtocolGame:onOpcode(opcode, msg)
  local callback = opcodeCallbacks[opcode]
  if callback then
    callback(self, msg)
    return true
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
    local data = buffer:sub(2)
    if status ~= "E" and status ~= "P" then
      extendedJSONData[opcode] = ""
    end
    if status ~= "S" and status ~= "P" and status ~= "E" then
      extendedJSONData[opcode] = buffer
    else
      extendedJSONData[opcode] = extendedJSONData[opcode] .. data
    end
    if status ~= "S" and status ~= "P" then
      local json_status, json_data = pcall(function() return json.decode(extendedJSONData[opcode]) end)
      extendedJSONData[opcode] = nil
      if not json_status then
        error("Invalid data in extended JSON opcode " .. opcode .. ": " .. tostring(json_data))
        return
      end
      callback(self, opcode, json_data)
    end
  end
end

function ProtocolGame.registerOpcode(opcode, callback)
  if opcodeCallbacks[opcode] then
    error('opcode ' .. opcode .. ' already registered will be overriden')
  end

  opcodeCallbacks[opcode] = callback
  -- Tell C++ a Lua handler exists for this opcode, so parseMessage round-trips into
  -- onOpcode for it (and skips the round-trip for the many opcodes that have none).
  if g_game and g_game.setLuaOpcodeHandler then
    g_game.setLuaOpcodeHandler(opcode, true)
  end
end

function ProtocolGame.unregisterOpcode(opcode)
  opcodeCallbacks[opcode] = nil
  if g_game and g_game.setLuaOpcodeHandler then
    g_game.setLuaOpcodeHandler(opcode, false)
  end
end

function ProtocolGame.registerExtendedOpcode(opcode, callback)
  if not callback or type(callback) ~= 'function' then
    error('Invalid callback.')
  end

  if opcode < 0 or opcode > 255 then
    error('Invalid opcode. Range: 0-255')
  end

  if extendedCallbacks[opcode] then
    error('Opcode is already taken.')
  end

  extendedCallbacks[opcode] = callback
end

function ProtocolGame.unregisterExtendedOpcode(opcode)
  if opcode < 0 or opcode > 255 then
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

  if opcode < 0 or opcode > 255 then
    error('Invalid opcode. Range: 0-255')
  end

  if extendedJSONCallbacks[opcode] then
    error('Opcode is already taken.')
  end

  extendedJSONCallbacks[opcode] = callback
end

function ProtocolGame.unregisterExtendedJSONOpcode(opcode)
  if opcode < 0 or opcode > 255 then
    error('Invalid opcode. Range: 0-255')
  end

  if not extendedJSONCallbacks[opcode] then
    error('Opcode is not registered.')
  end

  extendedJSONCallbacks[opcode] = nil
end

function ProtocolGame:sendExtendedJSONOpcode(opcode, data)
  if opcode < 0 or opcode > 255 then
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
