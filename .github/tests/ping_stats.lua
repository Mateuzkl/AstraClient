local path = arg[1] or 'modules/game_stats/stats.lua'
local options, displayed, hidden = {}, {}, {}
local function label(name)
  return {
    hide = function() hidden[name] = true end,
    setText = function(_, value) displayed[name] = value end,
    setImageSource = function(_, value) displayed[name] = value end
  }
end
local panel = {
  fps = label('fps'), ping = label('ping'), imagePing = label('image'), worldName = label('world'),
  isHidden = function() return false end
}
KeyBind = { getKeyBind = function() return { active = function() end, deactive = function() end } end }
g_ui = { loadUI = function() return panel end }
m_interface = { getMapPanel = function() return {} end }
m_settings = { getOption = function(name) return options[name] end }
scheduleEvent = function() return {} end
removeEvent = function() end
g_app = { getFps = function() return 61 end }
local rtt, queue = 160, -1
g_game = {
  getPing = function() return rtt end, getServerQueueDelay = function() return queue end,
  getWorldName = function() return 'Test' end, getLocalPlayer = function() return nil end,
  isRecord = function() return false end
}
tr = string.format
assert(loadfile(path))()
options.showPing, options.showFps = false, true
init()
assert(hidden.ping and not hidden.fps, 'showPing must control the ping widget')
terminate()
hidden = {}
options.showPing, options.showFps = true, false
init()
assert(hidden.fps and not hidden.ping, 'showFps must control the FPS widget')
update()
assert(displayed.ping == 'Low lag (160 ms)' and displayed.fps == '61 fps')
queue = 82
update()
assert(displayed.ping == 'Low lag (160 ms)\nServer queue: 82 ms')
queue = -1
for _, case in ipairs({{249, 'Low'}, {250, 'Medium'}, {499, 'Medium'}, {500, 'High'}}) do
  rtt = case[1]
  update()
  assert(displayed.ping == string.format('%s lag (%d ms)', case[2], rtt))
end
rtt = -1
update()
assert(displayed.ping == '??')
terminate()
-- Exercise the actual topmenu handler with a deliberately different proxy RTT.
local topmenuPath = arg[2] or 'modules/client_topmenu/topmenu.lua'
assert(loadfile(topmenuPath))()
local pingText
local menu = { pingLabel = {
  setColor = function() end,
  setText = function(_, text) pingText = text end
} }
local index = 1
while debug.getupvalue(updatePing, index) do
  local name = debug.getupvalue(updatePing, index)
  if name == 'topMenu' then debug.setupvalue(updatePing, index, menu); break end
  index = index + 1
end
g_proxy = { getPing = function() return 1 end }
updatePing(320)
assert(pingText == 'Ping: 320 ms', 'Topmenu must retain gameplay RTT, not proxy transport ping')
print('Ping stats UI: all checks passed')
