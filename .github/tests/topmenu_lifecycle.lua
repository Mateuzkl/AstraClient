local function fixture(urls)
  local state = {events = {}, requests = {}, cancelled = {}}
  local env = setmetatable({}, {__index = _G})
  local function label()
    return {setText = function(self, value) self.text = value end,
      setFont = function() end, setColor = function() end}
  end
  env.g_game = {isOnline = function() return state.online or false end}
  env.g_ui = {getRootWidget = function() return {} end, createWidget = function()
    local w = {onlineLabel = label()}
    function w:destroy() self.destroyed = true end
    function w:recursiveGetChildById(id) assert(not self.destroyed); return self[id] end
    state.widget = w
    return w
  end}
  env.Services = {status = urls}
  env.HTTP = {
    postJSON = function(_, _, f) state.requests[#state.requests + 1] = f; return #state.requests end,
    cancel = function(id) state.cancelled[id] = true end
  }
  env.scheduleEvent = function(f) local e = {f = f}; state.events[#state.events + 1] = e; return e end
  env.removeEvent = function(e) if e then e.cancelled = true end end
  env.connect, env.disconnect = function() end, function() end
  env.g_logger = {warning = function() end}
  env.tovar = function(s) return s end
  local chunk = assert(loadfile('modules/client_topmenu/topmenu.lua'))
  setfenv(chunk, env); chunk(); env.init()
  return env, state
end
local function pending(s)
  local n = 0
  for _, e in ipairs(s.events) do if not e.cancelled then n = n + 1 end end
  return n
end
do
  local env, s = fixture({'a', 'b'})
  s.requests[1](nil, 'fail'); s.requests[2](nil, 'fail')
  assert(pending(s) == 1, 'more than one retry per failed status round')
  env.terminate(); assert(pending(s) == 0, 'retry survives terminate')
end
do
  local env, s = fixture({'a'})
  env.terminate()
  assert(s.cancelled[1], 'HTTP operation survives terminate')
  s.requests[1]({playersonline = 10}, nil)
  assert(s.widget.destroyed and pending(s) == 0)
end
do
  local env, s = fixture({'a', 'b'})
  env.updateStatus()
  assert(s.cancelled[1] and s.cancelled[2])
  s.requests[1](nil, 'late fail'); s.requests[2]({playersonline = 999}, nil)
  assert(pending(s) == 0 and not s.widget.onlineLabel.text)
  s.requests[4]({playersonline = 5}, nil); s.requests[3]({playersonline = 7}, nil)
  assert(s.widget.onlineLabel.text == '12 players online')
  env.terminate(); env.init()
  s.requests[3](nil, 'previous generation')
  assert(pending(s) == 0)
  env.terminate()
end
do
  local env, s = fixture('https://audit.invalid')
  assert(#s.requests == 1)
  s.requests[1]({online = 'Maintenance'}, nil)
  assert(s.widget.onlineLabel.text == 'Maintenance')
  env.terminate()
end
do
  local env, s = fixture({})
  assert(#s.requests == 0)
  env.terminate()
end
print('TopMenu HTTP ownership, aggregation and retry lifecycle: OK')
