-- Crash reporter (Fase 1.6 client side).
--
-- On boot, if the previous run left a crash dump, upload it automatically and
-- silently -- no dialog, no opt-in, the player is never prompted. The upload is
-- the minidump + the textual crash report + the crashing process's own log,
-- base64-encoded, POSTed to Services.crash. The log comes from /crashlog.txt,
-- which the crash handler writes from this process's in-memory log buffer at
-- crash time -- per-process, so it stays clean even when several client
-- instances run from the same folder (multi-boxing). Falls back to
-- g_logger.getLastLog() (the boot snapshot of the shared on-disk log, now kept
-- across runs and capped at 1MB) if that file is missing (e.g. an older dump).
-- The dev symbolizes it server-side (cdb + the matching PDB kept
-- privately), since the shipped binary is stripped. See koliseu-aac contract at
-- the bottom of this file.
--
-- Privacy: only the small stack-only minidump (exception.dmp) is sent, never the
-- full-memory dump (exception_full.dmp).

-- Leading "/" anchors these to the VFS root (the write dir, where the crash
-- handler writes the dumps). Without it, resolvePath() prepends the current Lua
-- script's dir (/modules/crash_reporter) and the files are never found.
local PRIMARY    = "/exception.dmp"           -- stack-only minidump (uploaded)
local DUMP_FILES = {                          -- everything we clean up afterwards
  "/exception.dmp", "/exception2.dmp", "/exception_full.dmp", "/crashreport.log",
  "/crashlog.txt"
}

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

function init()
  -- Gated by init.lua on Services.crash being a real URL; double-check here.
  if type(Services.crash) ~= 'string' or Services.crash:len() <= 4 then return end
  if not g_resources.fileExists(PRIMARY) then return end

  -- Always upload silently: no consent dialog, the player is never prompted.
  g_logger.info("[crash_reporter] pending crash dump found, uploading automatically")
  send()
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
