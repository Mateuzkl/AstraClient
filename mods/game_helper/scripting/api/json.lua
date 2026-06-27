--[[
  scripting/api/json.lua  ->  namespace `JSON`  (Zerobot dialect)
  ----------------------------------------------------------------------------
  JSON.encode(value, indent?) -> string
  JSON.decode(str)            -> value

  Zerobot's JSON is rxi/json.lua (MIT) -- exactly the library KoliseuClient already
  ships at modules/corelib/json.lua (the engine loads it at boot, so the global
  `json` is present by the time this builder runs). We reuse that single instance
  instead of vendoring a copy: same encode/decode semantics, one code path to keep
  correct, and no I/O surface is exposed (only the two pure functions).

  rxi's json.encode(val) takes ONE argument -- it has no pretty-print/indent mode.
  Zerobot's JSON.encode is likewise compact-only. We still ACCEPT the optional
  `indent` arg (Koliseu's own code calls json.encode(t, 2)) for call-site
  compatibility, and apply a small, dependency-free pretty-printer when an indent
  is requested so the output is human-readable; without it we pass straight through
  to the library (compact, byte-for-byte rxi output).
]]

return function(api, ctx)
  local JSON = {}

  -- Resolve the JSON library once, at build time. Prefer the already-loaded global
  -- `json` (corelib/json.lua, set as a non-local global at boot). Only if it is
  -- somehow absent do we dofile the corelib copy a single time and capture it --
  -- this runs OUTSIDE the sandbox, so dofile is available here.
  local lib = json
  if type(lib) ~= 'table' or type(lib.encode) ~= 'function' then
    local ok, mod = pcall(dofile, '/corelib/json.lua')
    -- corelib/json.lua assigns the global `json` rather than returning a table,
    -- so re-read the global after the dofile (and fall back to its return value).
    if type(json) == 'table' and type(json.encode) == 'function' then
      lib = json
    elseif ok and type(mod) == 'table' then
      lib = mod
    end
  end

  -- Compact encode straight through rxi (the canonical, Zerobot-matching form).
  local function encodeCompact(value)
    return lib.encode(value)
  end

  -- Re-indent a compact JSON string. Walks the text once, respecting string
  -- literals (so braces/commas inside strings are never treated as structure).
  -- `step` is the indent unit (spaces); a number N means N spaces, a string is
  -- used verbatim. This keeps us free of any extra dependency while still giving
  -- pretty output when a caller asks for it.
  local function prettify(compact, step)
    local unit
    if type(step) == 'number' then
      unit = string.rep(' ', math.max(0, math.floor(step)))
    else
      unit = tostring(step)
    end
    if unit == '' then return compact end

    local out = {}
    local depth = 0
    local inStr = false
    local esc = false
    local n = #compact
    local i = 1
    local function pad(d) return string.rep(unit, d) end
    while i <= n do
      local c = compact:sub(i, i)
      if inStr then
        out[#out + 1] = c
        if esc then
          esc = false
        elseif c == '\\' then
          esc = true
        elseif c == '"' then
          inStr = false
        end
      elseif c == '"' then
        inStr = true
        out[#out + 1] = c
      elseif c == '{' or c == '[' then
        -- Empty container: keep on one line ({}/[]) for compactness.
        local nxt = compact:sub(i + 1, i + 1)
        if nxt == '}' or nxt == ']' then
          out[#out + 1] = c .. nxt
          i = i + 1
        else
          depth = depth + 1
          out[#out + 1] = c .. '\n' .. pad(depth)
        end
      elseif c == '}' or c == ']' then
        depth = depth - 1
        out[#out + 1] = '\n' .. pad(depth) .. c
      elseif c == ',' then
        out[#out + 1] = ',\n' .. pad(depth)
      elseif c == ':' then
        out[#out + 1] = ': '
      else
        out[#out + 1] = c
      end
      i = i + 1
    end
    return table.concat(out)
  end

  -- JSON.encode(value, indent?) -> string
  --   indent omitted/false/0  -> compact rxi output.
  --   indent = N (number)     -> pretty-printed with N spaces per level.
  --   indent = string         -> pretty-printed with that string per level.
  -- Errors (circular refs, sparse arrays, mixed key types, NaN/inf) propagate
  -- from rxi exactly as Zerobot's do.
  function JSON.encode(value, indent)
    local compact = encodeCompact(value)
    if indent and indent ~= 0 and indent ~= '' then
      return prettify(compact, indent)
    end
    return compact
  end

  -- JSON.decode(str) -> value. Delegates to rxi (errors with line/col on bad input,
  -- supports unicode/surrogate escapes). Non-string input raises, matching rxi.
  function JSON.decode(str)
    return lib.decode(str)
  end

  -- Library version passthrough (rxi exposes _version), for parity with Zerobot.
  JSON._version = lib._version

  return JSON
end
