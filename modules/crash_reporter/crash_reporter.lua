-- Crash reporter (Fase 1.6 client side).
--
-- On boot, if the previous run left a crash dump, ASK the player for consent
-- (opt-in, remembered) before uploading. The upload is the minidump + the
-- textual crash report + the crashing process's own log, base64-encoded, POSTed
-- to Services.crash. The log comes from /crashlog.txt, which the crash handler
-- writes from this process's in-memory log buffer at crash time -- per-process,
-- so it stays clean even when several client instances run from the same folder
-- (multi-boxing). Falls back to g_logger.getLastLog() (the boot snapshot of the
-- shared on-disk log, now kept across runs and capped at 1MB) if that file is
-- missing (e.g. an older dump).
-- The dev symbolizes it server-side (cdb + the matching PDB kept
-- privately), since the shipped binary is stripped. See koliseu-aac contract at
-- the bottom of this file.
--
-- Privacy: only the small stack-only minidump (exception.dmp) is sent, never the
-- full-memory dump (exception_full.dmp). Player must opt in.

-- Leading "/" anchors these to the VFS root (the write dir, where the crash
-- handler writes the dumps). Without it, resolvePath() prepends the current Lua
-- script's dir (/modules/crash_reporter) and the files are never found.
local PRIMARY    = "/exception.dmp"           -- stack-only minidump (uploaded)
local DUMP_FILES = {                          -- everything we clean up afterwards
  "/exception.dmp", "/exception2.dmp", "/exception_full.dmp", "/crashreport.log",
  "/crashlog.txt"
}
local CONSENT_KEY = "crashReport.consent"     -- "" (ask) | "always" | "never"

local function cleanup()
  for _, f in ipairs(DUMP_FILES) do
    if g_resources.fileExists(f) then
      pcall(function() g_resources.deleteFile(f) end)
    end
  end
end

local function readIf(f)
  if not g_resources.fileExists(f) then return nil end
  local ok, data = pcall(function() return g_resources.readFileContents(f) end)
  if ok then return data end
  return nil
end

local function send()
  local dump = readIf(PRIMARY)
  if not dump or #dump == 0 then
    cleanup()
    return
  end

  local report = readIf("/crashreport.log") or ""  -- has build revision/commit + stack
  -- Prefer the per-process log the crash handler dumped at crash time (clean
  -- even when multi-boxing). Fall back to the boot snapshot of the shared log.
  local clientLog = readIf("/crashlog.txt") or ""
  if clientLog == "" then
    pcall(function() clientLog = g_logger.getLastLog() or "" end)
  end

  g_logger.info("[crash_reporter] POST " .. tostring(Services.crash) .. " dump=" .. #dump .. "B")
  HTTP.post(Services.crash, {
    version  = APP_VERSION,
    build    = g_app.getVersion(),
    os       = g_app.getOs(),
    platform = g_window.getPlatformType(),
    crash    = base64.encode(dump),       -- minidump; embeds the build id cdb matches on
    report   = base64.encode(report),     -- textual crashreport.log (build commit + stack)
    log      = base64.encode(clientLog),  -- per-process crash-time log (multi-box safe)
  }, function(_, err)
    if err then
      -- Keep the dump on disk so the next boot can retry the upload.
      return g_logger.error("Crash report upload failed: " .. tostring(err))
    end
    cleanup()
  end)
end

local function promptConsent()
  -- Bail if the dump was already handled (e.g. a second module instance).
  if not g_resources.fileExists(PRIMARY) then return end
  g_logger.info("[crash_reporter] showing consent dialog")

  local box
  local function finish(action)
    if box then box:destroy() box = nil end
    action()
  end

  box = displayGeneralBox(tr("Crash Report"),
    tr("The client closed unexpectedly last time.\n\nWould you like to send an anonymous crash report to help us fix the problem?"),
    {
      { text = tr("Send"),       callback = function() finish(send) end },
      { text = tr("Always send"), callback = function() finish(function() g_settings.set(CONSENT_KEY, "always") send() end) end },
      { text = tr("Not now"),    callback = function() finish(cleanup) end },
      { text = tr("Never ask"),  callback = function() finish(function() g_settings.set(CONSENT_KEY, "never") cleanup() end) end },
    },
    function() finish(send) end,      -- Enter = send
    function() finish(cleanup) end)   -- Escape = skip this one

  -- The box is added early (login screen still settling) and locks input to
  -- itself; bring it to the front so it isn't hidden behind the login window.
  if box then
    box:raise()
    box:focus()
  end
end

function init()
  -- Gated by init.lua on Services.crash being a real URL; double-check here.
  if type(Services.crash) ~= 'string' or Services.crash:len() <= 4 then return end
  if not g_resources.fileExists(PRIMARY) then return end

  local consent = g_settings.getString(CONSENT_KEY, "")
  g_logger.info("[crash_reporter] pending crash dump found (consent='" .. tostring(consent) .. "')")
  if consent == "never" then
    cleanup()
  elseif consent == "always" then
    send()
  else
    -- Defer so the login UI (and rootWidget) is ready to show the dialog.
    scheduleEvent(promptConsent, 1500)
  end
end

function terminate()
end

-- koliseu-aac contract (backend, NOT implemented here -- "só lado-cliente por ora"):
--   POST Services.crash  (fields per HTTP.post encoding)
--     version  : APP_VERSION string
--     build    : g_app.getVersion()  (e.g. "3.1")
--     os       : g_app.getOs()
--     platform : g_window.getPlatformType()
--     crash    : base64(exception.dmp)   -- Windows minidump, stack-only
--     report   : base64(crashreport.log) -- text: build revision/commit + backtrace
--     log      : base64(crashing process's own crash-time log; falls back to
--                the boot snapshot of the shared client log if absent)
--
--   Server side (koliseu-aac):
--     1. Store the decoded minidump as <id>.dmp.
--     2. Symbolize:  cdb -z <id>.dmp -y <SYMBOL_VAULT> -c "!analyze -v; kv; q"
--        where SYMBOL_VAULT holds the PDB archived per release by make_release.ps1.
--        The minidump records the module PDB signature/age, so cdb auto-matches the
--        correct PDB -> source file:line. The shipped exe stays stripped.
--     3. The report/build fields let you correlate to the exact source revision.
