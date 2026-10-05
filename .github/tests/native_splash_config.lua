-- Exercise the actual init.lua switch without graphics or loading real modules.
local file = assert(io.open('init.lua', 'rb'))
local source = file:read('*a')
file:close()
assert(source:find('ENABLE_NATIVE_SPLASH = true', 1, true), 'splash must default to enabled')

local function run(enabled, native)
  local calls, modulesStarted = {}, false
  local app = {
    setName = function() end,
    isMobile = function() return false end,
  }
  for _, name in ipairs({'getName', 'getVersion', 'getBuildRevision', 'getBuildCommit',
                         'getAuthor', 'getBuildDate', 'getBuildArch'}) do
    app[name] = function() return 'test' end
  end
  if native then
    app.setNativeSplashEnabled = function(value)
      assert(not modulesStarted, 'splash choice must precede any module load')
      calls[#calls + 1] = value
    end
  end
  local env = setmetatable({
    g_app = app,
    g_logger = {info = function() end, fatal = error},
    g_resources = {directoryExists = function() return true end, setLayout = function() end},
    g_configs = {
      loadSettings = function() end,
      getSettings = function() return {exists = function() return false end} end,
    },
    g_modules = {
      discoverModules = function() modulesStarted = true end,
      ensureModuleLoaded = function() modulesStarted = true end,
      autoLoadModules = function() modulesStarted = true end,
    },
  }, {__index = _G})
  local configured, count = source:gsub('ENABLE_NATIVE_SPLASH = true', 'ENABLE_NATIVE_SPLASH = ' .. tostring(enabled), 1)
  assert(count == 1)
  local chunk = assert(loadstring(configured, '@init.lua'))
  setfenv(chunk, env)
  chunk()
  assert(modulesStarted, 'normal startup must continue with either setting')
  if native then
    assert(#calls == 1 and calls[1] == enabled, 'init.lua must forward the exact boolean')
  else
    assert(#calls == 0, 'web, Linux and older binaries must not need the Windows hook')
  end
end

run(true, true)
run(false, true)
run(true, false)
run(false, false)
print('Native splash init.lua configuration: ON/OFF and unsupported platforms passed')
