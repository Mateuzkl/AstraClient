--[[============================================================================
  scripting/api/http.lua - `HTTP` namespace (async, native, SAFE-mode).
  ============================================================================

  Builder module (see scripting/scripting.lua header). Returns
      function(api, ctx) ... return HTTP end
  and is injected into every sandboxed script as the global `HTTP`.

  Gives user scripts HTTP over the client's NATIVE stack (g_http, via the corelib
  `HTTP` wrapper) -- no LuaSocket / require / DLL, so it works with the sandbox FULLY
  CLOSED (advanced mode OFF). This is the contained way to hit a webhook / REST API
  (the Discord-notifier case) WITHOUT granting a script native-code (RCE) access.

  Surface (callback-based -- g_http is async and the single-thread client can't block):
      HTTP.get(url, cb)            -> opId ; cb(body, err)
      HTTP.getJSON(url, cb)        -> opId ; cb(decodedTable, err)
      HTTP.post(url, data, cb)     -> opId ; data string|table ; cb(body, err)
      HTTP.postJSON(url, data, cb) -> opId ; sends application/json ; cb(body|table, err)
      HTTP.cancel(opId)

  Contained by construction:
    * Every callback is ctx.wrap'd -> runs in the OWNING script's context (error
      accounting + auto-disable + no-op after the script unloads).
    * Every in-flight request is cancelled on script teardown (ctx.onCleanup), so a
      reply never lands on a dead script and operations do not leak.
    * http/https only, a coarse SSRF guard (no loopback / private ranges), and a cap on
      concurrent requests. Set HOST_ALLOWLIST to lock outbound traffic to known hosts.

  Runs OUTSIDE the sandbox (CONTRACT SS3), so it reaches the corelib `HTTP` global (the
  script itself never sees g_http). Returns the operation id, or nil + an error string.
============================================================================]]

return function(api, ctx)
  local HTTP = {}

  local function corelib() return rawget(_G, 'HTTP') end

  -- security knobs -----------------------------------------------------------
  local MAX_INFLIGHT   = 6     -- cap on concurrent requests across all scripts
  local HOST_ALLOWLIST = nil   -- nil = any public host; e.g. { ['discord.com'] = true }
  local inflight = 0

  local function hostOf(u) return tostring(u or ''):match('^%w+://([^/:]+)') end

  -- Coarse SSRF guard: reject loopback / link-local / private IPv4 ranges, plus an
  -- optional allowlist. Not a full URL parser -- a deliberate, blunt safety net.
  local function blockedHost(h)
    if not h then return true end
    h = h:lower()
    if h == 'localhost'
        or h:match('^127%.') or h:match('^10%.')
        or h:match('^192%.168%.') or h:match('^169%.254%.')
        or h:match('^172%.1[6-9]%.') or h:match('^172%.2%d%.') or h:match('^172%.3[01]%.') then
      return true
    end
    if HOST_ALLOWLIST and not HOST_ALLOWLIST[h] then return true end
    return false
  end

  local function validate(url)
    local scheme = tostring(url or ''):match('^(%a[%w+.-]*)://')
    scheme = scheme and scheme:lower() or nil
    if scheme ~= 'http' and scheme ~= 'https' then return false, 'URL must be http(s)://' end
    if blockedHost(hostOf(url)) then return false, 'host not allowed' end
    if inflight >= MAX_INFLIGHT then return false, 'too many in-flight requests' end
    return true
  end

  -- Fire corelib HTTP[method](url[, data], done). Wrap the callback into the owning
  -- script, decrement the in-flight counter EXACTLY once (whichever of the reply or the
  -- teardown-cancel fires first), and cancel a still-pending request on script teardown.
  local function fire(method, url, data, cb)
    local H = corelib()
    if not H or type(H[method]) ~= 'function' then return nil, 'HTTP not available' end
    local ok, err = validate(url)
    if not ok then return nil, err end

    local wrapped = (type(cb) == 'function') and ctx.wrap(cb) or nil
    inflight = inflight + 1
    local settled = false
    local function release()
      if settled then return false end
      settled = true
      inflight = math.max(0, inflight - 1)
      return true
    end

    local okCall, opId = pcall(function()
      local done = function(a, b)
        if release() and wrapped then wrapped(a, b) end
      end
      if data ~= nil then return H[method](url, data, done) end
      return H[method](url, done)
    end)
    if not okCall then
      release()
      return nil, tostring(opId)
    end

    if opId ~= nil then
      ctx.onCleanup(function()
        if release() and type(H.cancel) == 'function' then pcall(H.cancel, opId) end
      end)
    end
    return opId
  end

  function HTTP.get(url, cb)            return fire('get', url, nil, cb) end
  function HTTP.getJSON(url, cb)        return fire('getJSON', url, nil, cb) end
  function HTTP.post(url, data, cb)     return fire('post', url, data, cb) end
  function HTTP.postJSON(url, data, cb) return fire('postJSON', url, data, cb) end

  function HTTP.cancel(opId)
    local H = corelib()
    if H and type(H.cancel) == 'function' then pcall(H.cancel, opId) end
  end

  return HTTP
end
