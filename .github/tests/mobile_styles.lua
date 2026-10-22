-- Load the real resource/style and top menu functions, including stale callbacks.
local function loadProduction(path, env)
  setmetatable(env, {__index = _G})
  local chunk = assert(loadfile(path)); setfenv(chunk, env); chunk()
end
for _, spec in ipairs({
  {'layouts/mobile/styles/40-console.otui', 'ConsolePanel < ConsolePanel'},
  {'layouts/mobile/styles/30-miniwindow.otui', 'MiniWindow < MiniWindow'}
}) do
  local file = assert(io.open(spec[1], 'rb'))
  local source = file:read('*a'); file:close()
  assert(source:find(spec[2], 1, true), 'mobile must inherit the current base widget tree, not replace it')
  assert(not source:find('id:', 1, true), 'scalar mobile overrides must not duplicate the base widget children')
end
for _, layout in ipairs({'', 'mobile'}) do
  local imported = {}
  local dirs = {
    ['/data/styles/'] = {'/data/styles/10-base.otui', '/data/styles/20-topmenu.otui'},
    ['/layouts/mobile/styles/'] = {'/layouts/mobile/styles/10-scrollbars.otui'}
  }
  local env = {g_ui = {importStyle = function(file) imported[#imported+1] = file end},
    g_fonts = {}, g_particles = {}, g_resources = {
      listDirectoryFiles = function(path, full, raw) assert(full and raw); return dirs[path] or {} end,
      isFileType = function(path, extension) return path:sub(-#extension) == extension end,
      directoryExists = function() return false end, getLayout = function() return layout end
    }}
  loadProduction('modules/client_styles/styles.lua', env)
  env.importResources('styles', 'otui')
  assert(imported[2] == '/data/styles/20-topmenu.otui', 'mobile must retain TopMenu and base definitions')
  assert(#imported == (layout == 'mobile' and 3 or 2))
  if layout == 'mobile' then assert(imported[3]:find('/layouts/mobile/', 1, true)) end
end

local events, callbacks, connections = {}, {}, {}
local destroyed, writes = false, 0
local menu
local label = {setText = function() assert(not destroyed); writes = writes + 1 end,
  setFont = function() end, setColor = function() end}
local env = {Services = {status = {'https://example.invalid/status'}},
  g_ui = {getRootWidget = function() return {} end, createWidget = function() return menu end},
  connect = function(_, handlers) for key, fn in pairs(handlers) do connections[key] = fn end end,
  disconnect = function(_, handlers) for key in pairs(handlers) do connections[key] = nil end end,
  g_game = {isOnline = function() return false end}, g_app = {getFps = function() return 60 end},
  HTTP = {postJSON = function(_, _, callback) callbacks[#callbacks+1] = callback end},
  scheduleEvent = function(callback) events[callback] = true; return callback end,
  removeEvent = function(event) if event then events[event] = nil end end,
  tovar = function(value) return value end
}
loadProduction('modules/client_topmenu/topmenu.lua', env)
local ok, message = pcall(env.init)
assert(not ok and message:find('base and active layout styles', 1, true))
assert(next(connections) == nil, 'failed creation must not leave game signal handlers')
for _ = 1, 20 do
  destroyed = false
  menu = {fpsLabel = label, onlineLabel = label,
    recursiveGetChildById = function() return label end,
    destroy = function() assert(not destroyed); destroyed = true end,
    isDestroyed = function() return destroyed end}
  env.init(); assert(next(events))
  local late = callbacks[#callbacks]
  env.terminate(); assert(not next(events) and not next(connections))
  local before = writes
  late({playersonline = 10}); env.updateFps(); env.updatePing(20)
  assert(writes == before, 'late callbacks must not touch destroyed widgets')
end
print('mobile base styles and TopMenu lifecycle: PASS')
