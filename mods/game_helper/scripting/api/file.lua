--[[============================================================================
  scripting/api/file.lua - `File` namespace (jailed text I/O, SAFE-mode).
  ============================================================================

  Builder module (see scripting/scripting.lua header). Returns
      function(api, ctx) ... return File end
  and is injected into every sandboxed script as the global `File`.

  Lets scripts read/write text files WITHOUT the raw `io` library, so it works with
  the sandbox FULLY CLOSED (advanced mode OFF). All paths are resolved through
  g_resources (PhysFS -- already jailed to the client's write dir) AND fenced here to
  stay UNDER /bot_scripts: no absolute paths, no drive letters, no '..'. This is the
  contained alternative to `io` for the "load a config / persist a list" case.

  Surface (all names are RELATIVE to the scripts folder):
      File.read(name)        -> string | nil, err
      File.write(name, data) -> true | false, err        (overwrites)
      File.append(name, data)-> true | false, err
      File.exists(name)      -> boolean
      File.delete(name)      -> true | false, err
      File.list()            -> array of file names in /bot_scripts

  Runs OUTSIDE the sandbox (CONTRACT SS3), so it reaches g_resources; the script never
  sees g_resources itself.
============================================================================]]

return function(api, ctx)
  local File = {}

  local SCRIPTS_DIR = '/bot_scripts'

  -- Resolve a caller name to a virtual path UNDER base, rejecting any escape. PhysFS is
  -- already jailed to the write dir; this is a second, explicit fence.
  local function jail(name)
    name = tostring(name or '')
    if name == '' then return nil, 'empty name' end
    name = name:gsub('\\', '/')                       -- normalize separators
    if name:match('^/') or name:match('^%a:') then return nil, 'absolute paths not allowed' end
    if name:match('%.%.') then return nil, '".." not allowed' end
    if name:match('[%z\1-\31]') then return nil, 'control chars not allowed' end
    return SCRIPTS_DIR .. '/' .. name
  end

  local function ensureScriptsDir()
    if not g_resources.directoryExists(SCRIPTS_DIR) then
      pcall(function() g_resources.makeDir(SCRIPTS_DIR) end)
    end
  end

  function File.read(name)
    local vp, err = jail(name)
    if not vp then return nil, err end
    if not g_resources.fileExists(vp) then return nil, 'not found' end
    local ok, content = pcall(function() return g_resources.readFileContents(vp) end)
    if not ok then return nil, tostring(content) end
    return content
  end

  function File.write(name, data)
    local vp, err = jail(name)
    if not vp then return false, err end
    ensureScriptsDir()
    local ok, e = pcall(function() g_resources.writeFileContents(vp, tostring(data or '')) end)
    if not ok then return false, tostring(e) end
    return true
  end

  function File.append(name, data)
    local vp, err = jail(name)
    if not vp then return false, err end
    ensureScriptsDir()
    local prev = ''
    if g_resources.fileExists(vp) then
      local ok, c = pcall(function() return g_resources.readFileContents(vp) end)
      if ok and type(c) == 'string' then prev = c end
    end
    local ok, e = pcall(function() g_resources.writeFileContents(vp, prev .. tostring(data or '')) end)
    if not ok then return false, tostring(e) end
    return true
  end

  function File.exists(name)
    local vp = jail(name)
    return (vp ~= nil and g_resources.fileExists(vp)) and true or false
  end

  function File.delete(name)
    local vp, err = jail(name)
    if not vp then return false, err end
    if not g_resources.fileExists(vp) then return false, 'not found' end
    local ok = pcall(function() g_resources.deleteFile(vp) end)
    return ok and true or false
  end

  function File.list()
    local out = {}
    local ok, list = pcall(function() return g_resources.listDirectoryFiles(SCRIPTS_DIR) end)
    if ok and type(list) == 'table' then
      for _, n in ipairs(list) do if type(n) == 'string' then out[#out + 1] = n end end
    end
    return out
  end

  return File
end
