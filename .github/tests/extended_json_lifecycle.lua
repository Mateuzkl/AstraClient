local state = {events = {}, callbacks = {}, decoded = {}, delivered = {}}
local env = setmetatable({}, {__index = _G})
env.ProtocolGame = {}
env.g_game = {}
env.connect = function(_, handlers) state.gameEnd = handlers.onGameEnd end
env.disconnect = function() state.disconnected = true end
env.scheduleEvent = function(f, ms) local e = {f = f, ms = ms}; state.events[#state.events + 1] = e; return e end
env.removeEvent = function(e) e.cancelled = true end
env.g_logger = {warning = function() state.warnings = (state.warnings or 0) + 1 end}
env.json = {decode = function(text)
  if text == 'bad' then error('bad JSON') end
  state.decoded[#state.decoded + 1] = text
  return {text = text}
end}
local function loadProtocol()
  local f = assert(loadfile('modules/gamelib/protocolgame.lua')); setfenv(f, env); f()
end
loadProtocol()
local proto = env.ProtocolGame
local a, b = setmetatable({}, {__index = proto}), setmetatable({}, {__index = proto})
local function deliver(_, opcode, data) state.delivered[#state.delivered + 1] = {opcode, data.text} end
local function bufferTable()
  for i = 1, 50 do
    local name, value = debug.getupvalue(proto.onExtendedOpcode, i)
    if name == 'extendedJSONData' then return value end
  end
  error('assembly registry missing')
end
proto.registerExtendedJSONOpcode(1, deliver)
a:onExtendedOpcode(1, '{"short":1}')
assert(state.delivered[1][2] == '{"short":1}')
a:onExtendedOpcode(1, 'Sfirst'); a:onExtendedOpcode(1, 'Pmiddle'); a:onExtendedOpcode(1, 'Elast')
assert(state.delivered[2][2] == 'firstmiddlelast' and next(bufferTable()) == nil)
assert(state.events[1].cancelled and state.events[1].ms == 30000)
local n = #state.delivered
a:onExtendedOpcode(1, 'Porphan'); a:onExtendedOpcode(1, 'Eorphan')
assert(#state.delivered == n and next(bufferTable()) == nil)
a:onExtendedOpcode(1, 'Sold'); a:onExtendedOpcode(1, 'Snew'); a:onExtendedOpcode(1, 'Eend')
assert(state.delivered[#state.delivered][2] == 'newend')
a:onExtendedOpcode(1, 'SsessionA'); b:onExtendedOpcode(1, 'EsessionB')
assert(next(bufferTable()) == nil and #state.delivered == n + 1)
a:onExtendedOpcode(1, 'Spending')
proto.unregisterExtendedJSONOpcode(1)
assert(next(bufferTable()) == nil and state.events[#state.events].cancelled)
proto.registerExtendedJSONOpcode(1, deliver)
a:onExtendedOpcode(1, 'Sexpired'); local expiry = state.events[#state.events]
expiry.f(); assert(next(bufferTable()) == nil)
a:onExtendedOpcode(1, 'Snewer'); expiry.f()
assert(bufferTable()[1], 'old expiry discarded a new assembly')
state.gameEnd(); assert(next(bufferTable()) == nil)
a:onExtendedOpcode(1, 'bad'); a:onExtendedOpcode(1, '{}')
assert(state.delivered[#state.delivered][2] == '{}', 'bad JSON poisoned the next message')

-- Exact retained-byte boundaries; repeated chunks avoid a single huge wire buffer.
local chunk = string.rep('x', 65536)
a:onExtendedOpcode(1, 'S')
for _ = 1, 128 do a:onExtendedOpcode(1, 'P' .. chunk) end
assert(bufferTable()[1].size == 8 * 1024 * 1024)
a:onExtendedOpcode(1, 'Px'); assert(next(bufferTable()) == nil)
for id = 2, 3 do
  proto.registerExtendedJSONOpcode(id, deliver)
  a:onExtendedOpcode(id, 'S')
  for _ = 1, 128 do a:onExtendedOpcode(id, 'P' .. chunk) end
end
a:onExtendedOpcode(1, 'Sx')
assert(not bufferTable()[1] and bufferTable()[2] and bufferTable()[3])
state.gameEnd(); assert(next(bufferTable()) == nil)
a:onExtendedOpcode(1, 'Sreload')
loadProtocol()
assert(state.disconnected and state.events[#state.events].cancelled)
print('Extended JSON sequence, ownership, expiry, size budget and teardown: OK')
