local env = setmetatable({ProtocolGame = {}}, {__index = _G})
local chunk = assert(loadfile('modules/gamelib/protocolgame.lua')); setfenv(chunk, env); chunk()
local proto = env.ProtocolGame
local message = {}
local calls = 0
proto.registerOpcode(0, function(self, msg)
  assert(self == proto and msg == message)
  calls = calls + 1
  return false -- A registered callback still means the opcode was handled.
end)
assert(proto:onOpcode(0, message) == true and calls == 1)
assert(proto:onOpcode(255, message) == false)
proto.unregisterOpcode(0)
assert(proto:onOpcode(0, message) == false)
proto.registerOpcode(0, function() calls = calls + 10 end)
assert(proto:onOpcode(0, message) and calls == 11)
proto.unregisterOpcode(0)
print('Protocol dispatcher callback arguments, return value and replacement: OK')

if arg[1] == '--bench' then
  local callbacks, sum = {}, 0
  local function handler() sum = sum + 1 end
  for opcode = 1, 40 do callbacks[opcode] = handler; proto.registerOpcode(opcode, handler) end
  -- Original dispatch algorithm, using the same registrations and callbacks.
  local function legacy(self, opcode, msg)
    for id, callback in pairs(callbacks) do
      if id == opcode then callback(self, msg); return true end
    end
    return false
  end
  local function measure(fn, opcode)
    for _ = 1, 20000 do fn(proto, opcode, message) end
    local samples = {}
    for sample = 1, 5 do
      local start = os.clock()
      for _ = 1, 300000 do fn(proto, opcode, message) end
      samples[sample] = (os.clock() - start) * 1000
    end
    table.sort(samples)
    return samples[3]
  end
  print('300000 dispatches/sample; 5 samples; median CPU ms; 40 registered opcodes')
  for _, opcode in ipairs({1, 20, 40, 255}) do
    local old, new = measure(legacy, opcode), measure(proto.onOpcode, opcode)
    print(string.format('opcode=%d legacy_ms=%.3f direct_ms=%.3f ratio=%.2f', opcode, old, new, old / math.max(new, 0.000001)))
  end
  print('checksum=' .. sum)
end
