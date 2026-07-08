--[[============================================================================
  scripting/api/storage.lua - `Storage` namespace (persistent per-script KV).
  ============================================================================

  Builder module (see scripting/scripting.lua header). Returns
      function(api, ctx) ... return Storage end
  and is injected into every sandboxed script as the global `Storage`.

  A small persistent key/value store, one JSON file per script (keyed by the running
  script's name), living under /bot_scripts/storage. Unlike the in-memory `storage`
  table injected into each script, this SURVIVES relogs and client restarts -- the
  contained way to persist config/state WITHOUT the raw `io` library. Values must be
  JSON-encodable (string/number/boolean/table).

  Surface:
      Storage.get(key [, default]) -> value | default
      Storage.set(key, value)      -> true | false
      Storage.delete(key)          -> true | false
      Storage.all()                -> table (a copy loaded from disk)

  NOTE: each call re-reads/re-writes the script's JSON file -- meant for light config,
  not a per-tick hot path. Runs OUTSIDE the sandbox (CONTRACT SS3): reaches g_resources
  + json, which the script never sees directly.
============================================================================]]

return function(api, ctx)
  local Storage = {}

  local STORAGE_DIR = '/bot_scripts/storage'

  local function ensureDir()
    if not g_resources.directoryExists(STORAGE_DIR) then
      pcall(function() g_resources.makeDir(STORAGE_DIR) end)
    end
  end

  -- One JSON file per script so two scripts never clobber each other. The running
  -- script's name is sanitized into a filename; snippets/no-context fall back to shared.
  local function storagePath()
    local s = ctx.runningScript()
    local name = (s and s.name) or '_shared'
    name = tostring(name):gsub('[^%w%-_%. ]', '_')
    if name == '' then name = '_shared' end
    return STORAGE_DIR .. '/' .. name .. '.json'
  end

  local function loadStore()
    local p = storagePath()
    if not g_resources.fileExists(p) then return {} end
    local ok, content = pcall(function() return g_resources.readFileContents(p) end)
    if not ok or type(content) ~= 'string' or content == '' then return {} end
    local dok, decoded = pcall(function() return json.decode(content) end)
    if dok and type(decoded) == 'table' then return decoded end
    return {}
  end

  local function saveStore(t)
    ensureDir()
    local ok, encoded = pcall(function() return json.encode(t, 2) end)
    if not (ok and encoded) then return false end
    local wok = pcall(function() g_resources.writeFileContents(storagePath(), encoded) end)
    return wok and true or false
  end

  function Storage.get(key, default)
    local v = loadStore()[tostring(key)]
    if v == nil then return default end
    return v
  end

  function Storage.set(key, value)
    local t = loadStore()
    t[tostring(key)] = value
    return saveStore(t)
  end

  function Storage.delete(key)
    local t = loadStore()
    t[tostring(key)] = nil
    return saveStore(t)
  end

  function Storage.all()
    return loadStore()
  end

  return Storage
end
