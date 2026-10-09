-- Regression for locally damaged default-options.json and player options.
-- Runs with LuaJIT only; no client binary, graphics, or network required.
assert(loadfile('modules/corelib/json.lua'))()
-- Corelib supplies table.find at runtime; mirror it in the isolated test VM.
table.find = table.find or function(array, needle)
  for index, value in ipairs(array) do
    if value == needle then return index end
  end
  return nil
end
local stream = assert(io.open('data/json/default-options.json', 'rb'))
local shipped = stream:read('*a')
stream:close()
local function environment(content, saved, failBackup)
  local files = { ['/data/json/default-options.json'] = content }
  if saved then files['/settings/clientoptions.json'] = saved end
  local state = { connected = false, fatal = nil, failBackup = failBackup, files = files, errors = {} }
  local resources = {
    fileExists = function(p) return files[p] ~= nil end,
    readFileContents = function(p) assert(files[p], 'unreadable ' .. p); return files[p] end,
    writeFileContents = function(p, value)
      if state.failBackup and p:find('clientoptions.corrupt', 1, true) then return false end
      files[p] = value
      return true
    end,
    directoryExists = function() return state.hasDirectory == true end,
    makeDir = function() state.hasDirectory = true; return true end
  }
  local options = {
    array = {}, actionBar = {},
    validateAssignedHotkeys = function() end,
    validateOpenChannels = function() end
  }
  local env = setmetatable({
    Options = options, g_resources = resources, g_game = {},
    g_logger = {
      fatal = function(msg) state.fatal = msg end,
      error = function(msg) table.insert(state.errors, msg) end
    },
    connect = function() state.connected = true end,
    disconnect = function() state.connected = false end
  }, { __index = _G })
  local chunk = assert(loadfile('modules/client_options/options.lua'))
  setfenv(chunk, env)
  chunk()
  return env, state
end
local function check(ok, description) assert(ok, description) end
do
  local env, state = environment(shipped)
  env.init()
  check(not state.fatal and state.connected, 'valid default must initialize')
  check(#env.Options.actionBar == 9, 'nine action bars must initialize')
  check(state.hasDirectory, 'first run must create settings directory')
  env.terminate()
  check(not state.connected, 'terminate must disconnect callbacks')
  env.init()
  check(#env.Options.actionBar == 9, 'reinit must not duplicate action bars')
end
do
  local env, state = environment(shipped:sub(1, 6400))
  env.init()
  check(state.fatal and state.fatal:find('default%-options.json'), 'truncated default must fail early')
  check(not state.connected, 'invalid defaults must not register game callbacks')
  check(not state.files['/settings/clientoptions.json'], 'do not create settings from corrupt defaults')
end
do
  local bad = json.decode(shipped)
  bad.hotkeyOptions = nil
  local env, state = environment(json.encode(bad))
  env.init()
  check(state.fatal and not state.connected, 'parseable partial defaults must fail early')
end
do
  local corrupt = '{ broken player json'
  local env, state = environment(shipped, corrupt)
  env.init()
  check(not state.fatal and state.connected, 'fallback must initialize')
  check(state.files['/settings/clientoptions.corrupt.1.json'] == corrupt, 'must preserve exact user bytes')
  check(env.Options.saveData() == true, 'save allowed after verified backup')
  check(state.files['/settings/clientoptions.json'] ~= corrupt, 'fallback saved after original backup')
end
do
  local corrupt = '{ broken player json'
  local env, state = environment(shipped, corrupt, true)
  env.init()
  check(not state.fatal and state.connected, 'backup failure must still allow temporary play')
  check(env.Options.settingsReadOnly == true, 'failed backup must disable saving')
  check(env.Options.saveData() == false, 'read-only config cannot save')
  check(state.files['/settings/clientoptions.json'] == corrupt, 'original must remain untouched')
end
print('Client options integrity/recovery: OK')
