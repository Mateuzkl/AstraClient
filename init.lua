-- CONFIG
APP_NAME = "KoliseuClient"
APP_VERSION = 1524
DEFAULT_LAYOUT = ""

-- Global client version: the single source of truth for which Tibia
-- protocol/assets the whole client targets. The client supports exactly one era
-- (legacy multi-version support was removed), so every login path resolves to
-- this value; there is no version selector or host-suffix version to override it.
CLIENT_VERSION = APP_VERSION

-- Distribution/release version of THIS build (semver "x.y.z"), distinct from the
-- protocol version above. It is the single source of truth the login gate uses:
-- the client sends it as `release_version` on login and the login service (koliseu-aac
-- /api/login) rejects the login when it does not match the version published for this
-- environment in the `client_version` table. Baked into the code (and encrypted inside
-- data.zip at release time) so it cannot be tampered with like the launcher's manifest.
-- BUMPED AUTOMATICALLY by tools/make_release.ps1 -- do not hand-edit unless you know why.
CLIENT_RELEASE_VERSION = "1.0.9"

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

-- The C++ profiler (g_stats / AutoStat) is OFF by default so players pay no
-- per-Lua-call / per-opcode profiling cost. Turn it on in developer mode so the
-- Debug Info window and profiler dumps (client_stats, also gated on DEVELOPERMODE)
-- keep working. Guarded for older/stripped builds without the setEnabled binding.
if g_stats and g_stats.setEnabled then
  g_stats.setEnabled(DEVELOPERMODE)
end

-- ---------------------------------------------------------------------------
-- Server endpoint configuration
-- ---------------------------------------------------------------------------
-- Open-source clients ship with a placeholder example.com endpoint set. Copy
-- config.example.lua → config.lua and edit the URLs for your own server, or
-- set the env-variable CLIENT_ENV=dev to use the local development defaults
-- (Koliseu at http://127.0.0.1:3000 for HTTP login).
--
-- Server entry form (this client authenticates over HTTP only; the legacy TCP
-- ProtocolLogin and old-version support were removed):
--   "http(s)://host/path"           Tibia 12+/15.x HTTP login (modern Koliseu)

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
  -- and only then hand the client the game world host/port. So the default
  -- points at the local HTTP login endpoint; override via config.lua for your
  -- own server.
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

-- Diagnostic: log the resolved login endpoint so a misconfigured release is
-- obvious in the client log (e.g. a stray localhost instead of the real host).
do
  local k = Servers and Servers.Koliseu
  local link = (type(k) == 'table' and k.loginLink) or (type(k) == 'string' and k) or '(none)'
  g_logger.info('Active login endpoint: ' .. tostring(link))
end

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
if settings:exists('layout') then
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
