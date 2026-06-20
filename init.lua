-- CONFIG
APP_NAME = "KoliseuClient"
APP_VERSION = 1524
DEFAULT_LAYOUT = ""

-- Global client version. This is the single source of truth for which Tibia
-- protocol/assets the whole client targets. Every login path (custom server,
-- HTTP/Koliseu, saved config) resolves through this value rather than guessing
-- from a host suffix (ip:port:version) or a stale persisted client-version.
-- When FORCE_CLIENT_VERSION is true, any version coming from a server entry,
-- the version selector, or config.otml is overridden with CLIENT_VERSION.
CLIENT_VERSION = APP_VERSION
FORCE_CLIENT_VERSION = true

-- Optional dev auto-login. Off by default; to use it, set these in config.lua
-- (NOT here — keep real credentials out of version control):
--   AUTO_LOGIN_DEBUG = true
--   AUTO_LOGIN_EMAIL = "you@example.com"
--   AUTO_LOGIN_PASS  = "secret"
--   AUTO_LOGIN_HOST  = "http://127.0.0.1:3000/api/login"  -- optional
--   AUTO_SELECT_CHAR = false  -- optional: stop at the character list
AUTO_LOGIN_DEBUG = false

-- F8 P1: developer flag — modules opt into noisy diagnostics when true
-- (e.g. modules/game_protocol unhandled-opcode reporter). Enables the
-- client_stats profiling window (Ctrl+Alt+D / "Debug Info" top-menu button).
DEVELOPERMODE = true

-- ---------------------------------------------------------------------------
-- Server endpoint configuration
-- ---------------------------------------------------------------------------
-- Open-source clients ship with a placeholder example.com endpoint set. Copy
-- config.example.lua → config.lua and edit the URLs for your own server, or
-- set the env-variable CLIENT_ENV=dev to use the local development defaults
-- (Koliseu at http://127.0.0.1:3000 for HTTP login).
--
-- Servers entry forms:
--   "ip:port:version"               legacy TCP ProtocolLogin (8.60/10.x)
--   "http(s)://host/path"           Tibia 12+ HTTP login (modern Koliseu)
--   "ws(s)://host/path"             WebSocket login (USE_NEW_ENERGAME=true)

local CLIENT_ENV = (os.getenv and os.getenv("CLIENT_ENV")) or "prod"

local function loadConfig()
  -- 1. user-provided config.lua takes precedence
  local ok, userConfig = pcall(dofile, "config.lua")
  if ok and type(userConfig) == "table" and userConfig.Services and userConfig.Servers then
    return userConfig.Services, userConfig.Servers
  end

  -- 2. env-specific defaults
  if CLIENT_ENV == "dev" then
    return {
      website       = "",
      updater       = "",
      stats         = "",
      crash         = "",
      feedback      = "",
      status        = "http://127.0.0.1:3000/api/status",
      createAccount = "http://127.0.0.1:3000/account/register",
      Coins         = "http://127.0.0.1:3000/donate", -- read as Services.Coins (Get Coins)
    }, {
      Koliseu = "http://127.0.0.1:3000/api/login",
    }
  end

  -- 3. open-source placeholder.
  -- Modern servers (Tibia 12+/15.x, e.g. crystalserver) authenticate over HTTP
  -- and only then hand the client the game world host/port. The legacy TCP
  -- ProtocolLogin (ip:port:version on 7171) is for <= 11.00 clients and will
  -- fail a 15.24 handshake ("invalid checksum"). So the default points at the
  -- local HTTP login endpoint; override via config.lua for your own server.
  -- NOTE: client_topmenu.updateStatus iterates Services.status as a LIST
  -- (`for i = 1, #Services.status`), so it must be a table of URLs (or empty),
  -- never a bare string — a string makes #status its char count and feeds
  -- characters to HTTP.postJSON, crashing with a boolean->map cast.
  return {
    website  = "",
    updater  = "",
    stats    = "",
    crash    = "",
    feedback = "",
    status   = {},
  }, {
    Koliseu = "http://127.0.0.1:3000/api/login",
  }
end

Services, Servers = loadConfig()

ALLOW_CUSTOM_SERVERS = true

g_app.setName(APP_NAME)
-- CONFIG END

g_logger.info(os.date("== application started at %b %d %Y %X"))
g_logger.info(g_app.getName() ..
' ' ..
g_app.getVersion() ..
' rev ' ..
g_app.getBuildRevision() ..
' (' ..
g_app.getBuildCommit() ..
') made by ' .. g_app.getAuthor() .. ' built on ' .. g_app.getBuildDate() .. ' for arch ' .. g_app.getBuildArch())

if not g_resources.directoryExists("/data") then
  g_logger.fatal("Data dir doesn't exist.")
end

if not g_resources.directoryExists("/modules") then
  g_logger.fatal("Modules dir doesn't exist.")
end

-- settings
g_configs.loadSettings("/config.otml")

-- set layout
local settings = g_configs.getSettings()
local layout = DEFAULT_LAYOUT
if g_app.isMobile() then
  layout = "mobile"
elseif settings:exists('layout') then
  layout = settings:getValue('layout')
end
if layout:len() > 0 and not g_resources.directoryExists('/layouts/' .. layout) then
  layout = ""
end
g_resources.setLayout(layout)

-- load global HTML/CSS stylesheets (optional, skip if files missing)
local function loadHtmlStyles()
  for _, path in ipairs({'/data/styles/html.css', '/data/styles/custom.css'}) do
    if g_resources.fileExists(path) then
      local ok, err = pcall(function() g_html.addGlobalStyle(path) end)
      if not ok then g_logger.warning('HTML/CSS load failed: ' .. tostring(err)) end
    end
  end
end
loadHtmlStyles()

-- load mods
g_modules.discoverModules()
g_modules.ensureModuleLoaded("corelib")
g_modules.ensureModuleLoaded("modulelib")
local function loadModules()
  -- libraries modules 0-99
  g_modules.autoLoadModules(99)
  g_modules.ensureModuleLoaded("gamelib")

  -- client modules 100-499
  g_modules.autoLoadModules(499)
  g_modules.ensureModuleLoaded("client")

  -- game modules 500-999
  g_modules.autoLoadModules(999)
  g_modules.ensureModuleLoaded("game_interface")

  -- mods 1000-9999
  g_modules.autoLoadModules(9999)
end

-- report crash
if type(Services.crash) == 'string' and Services.crash:len() > 4 and g_modules.getModule("crash_reporter") then
  g_modules.ensureModuleLoaded("crash_reporter")
end

-- run updater, must use data.zip
if type(Services.updater) == 'string' and Services.updater:len() > 4
    and g_resources.isLoadedFromArchive() and g_modules.getModule("updater") then
  g_modules.ensureModuleLoaded("updater")
  return Updater.init(loadModules)
end
loadModules()
