-- Exercise the production viewer: Web never launches a shell; native paths stay intact.
local function fixture(osName, files)
  local labels, listed, pipes, closed = {}, 0, {}, 0
  local played, removed
  local list = {}
  function list:destroyChildren() labels = {} end
  function list:getFocusedChild() return labels[1] end
  local window = {contentPanel = {getChildById = function() return list end}}
  for _, method in ipairs({'hide', 'show', 'raise', 'focus', 'destroy'}) do
    window[method] = function() end
  end
  function window:isVisible() return false end
  local env = {
    g_app = {getOs = function() return osName end},
    g_game = {playRecord = function(name) played = name end},
    g_settings = {setNode = function() end},
    connect = function() end, disconnect = function() end,
    g_ui = {
      displayUI = function() return window end,
      createWidget = function(_, parent)
        assert(parent == list)
        local label = {setText = function(self, text) self.text = text end}
        labels[#labels + 1] = label
        return label
      end
    },
    g_resources = {
      listDirectoryFiles = function(path, full, raw)
        assert(osName == 'browser' and path == '/user/records' and not full and raw)
        listed = listed + 1
        return files
      end
    },
    os = {remove = function(name) removed = name end},
    tr = function(text) return text end,
    displayGeneralBox = function(_, _, _, accept)
      return {destroy = function() end, accept = accept}
    end,
    io = {popen = function(command)
      assert(osName ~= 'browser', 'Web must not call popen')
      pipes[#pipes + 1] = command
      local pipe = {}
      function pipe:lines()
        local index = 0
        return function() index = index + 1; return files[index] end
      end
      function pipe:close() closed = closed + 1 end
      return pipe
    end},
    short_text = function(text) return text end,
    table = setmetatable({empty = function(values) return next(values) == nil end}, {__index = table})
  }
  local chunk = assert(loadfile('modules/client_camviewer/client_camviewer.lua'))
  setfenv(chunk, setmetatable(env, {__index = _G})); chunk(); env.init()
  return env, function() return labels, listed, pipes, closed, played, removed end
end

local cam = 'Player_World_20261008120000.cam'
-- The physical directory listing returns regular files only.
local env, state = fixture('browser', {cam, 'extensionless'})
env.toggle()
local labels, listed, pipes = state()
assert(listed == 1 and #pipes == 0 and #labels == 2)
assert(labels[1].camName == cam and labels[1].text == 'Player | World [08/10/2026 | 12:00]')
assert(labels[2].text == 'extensionless')
env.load(); labels = state(); assert(#labels == 2, 'reload must replace, not duplicate labels')
env.playCam()
local _, _, _, _, played = state()
assert(played == cam, 'playback must pass the basename to the packet player')
env.deleteCam(); env.check.accept()
local _, _, _, _, _, removed = state()
assert(removed == '/user/records/' .. cam, 'Web deletion must use the physical recording directory')
env.terminate()

env, state = fixture('browser', {})
env.show(); labels, listed, pipes = state()
assert(listed == 1 and #labels == 0 and #pipes == 0, 'missing/empty recordings must open safely')
env.terminate()

for _, osName in ipairs({'windows', 'linux'}) do
  env, state = fixture(osName, {cam})
  for _ = 1, 20 do env.load() end
  local closed
  labels, listed, pipes, closed = state()
  assert(listed == 0 and #labels == 1 and #pipes == 20 and closed == 20)
  assert(pipes[1] == (osName == 'windows' and 'dir "records" /B /O:N /A:-D' or 'ls -1 records | grep -v /'))
  env.playCam(); env.deleteCam(); env.check.accept()
  local _, _, _, _, played, removed = state()
  assert(played == cam and removed == 'records/' .. cam, 'native recording paths must stay unchanged')
  env.terminate()
end
print('Cam Viewer Web filesystem and native shell lifecycle: PASS')
