--[[============================================================================
  test_json.lua  --  round-trip + pretty-print checks for the `JSON` namespace.
  ============================================================================
  WHAT IT TESTS
    JSON.encode / JSON.decode (rxi/json under the hood):
      * compact encode of a nested table,
      * a real ROUND-TRIP (encode -> decode -> re-check every field),
      * pretty-print with a numeric indent and with a string indent,
      * decode of hand-written JSON (objects, arrays, numbers, bools, null,
        escaped strings, unicode),
      * that bad input raises (pcall) -- errors propagate like Zerobot.
    Pure data: identical results online or offline.

  HOW TO READ THE OUTPUT
    "[PASS] <name> = <value>" / "[FAIL] <name>". The round-trip section is the
    important one: it proves a table survives encode->decode unchanged. The
    pretty-print checks assert the output CONTAINS newlines/indent (we don't
    pin exact whitespace). Summary at the end.

  SAFE TO RUN ON THE LIVE CLIENT: pure data, no side effects.
============================================================================]]

local pass, fail = 0, 0
local function check(name, cond, extra)
  if cond then
    pass = pass + 1
    print('[PASS] ' .. name .. (extra ~= nil and (' = ' .. tostring(extra)) or ''))
  else
    fail = fail + 1
    print('[FAIL] ' .. name)
  end
end

--==========================================================================
-- 1. Compact encode of a nested structure.
--==========================================================================
local source = {
  name = 'Bubble',
  level = 250,
  premium = true,
  vocation = nil,         -- nil values are simply absent from the object
  skills = { magic = 110, sword = 95 },
  bless = { 1, 2, 3, 4, 5 },
}

local compact = JSON.encode(source)
check('encode returns a string', type(compact) == 'string')
check('compact has no newline', type(compact) == 'string' and not compact:find('\n'))
-- spot-check a couple of substrings are present (order is not guaranteed)
check('compact contains "Bubble"', type(compact) == 'string' and compact:find('Bubble') ~= nil)
check('compact contains the bless array', type(compact) == 'string' and compact:find('%[1,2,3,4,5%]') ~= nil)

--==========================================================================
-- 2. REAL round-trip: encode -> decode -> re-check every field.
--==========================================================================
local decoded = JSON.decode(compact)
check('decode returns a table', type(decoded) == 'table')
check('  name survived', decoded.name == 'Bubble', decoded.name)
check('  level survived (number)', decoded.level == 250, decoded.level)
check('  premium survived (true)', decoded.premium == true, decoded.premium)
check('  nested skills.magic survived', type(decoded.skills) == 'table' and decoded.skills.magic == 110,
      decoded.skills and decoded.skills.magic)
check('  nested skills.sword survived', type(decoded.skills) == 'table' and decoded.skills.sword == 95,
      decoded.skills and decoded.skills.sword)
check('  array length survived', type(decoded.bless) == 'table' and #decoded.bless == 5,
      decoded.bless and #decoded.bless)
check('  array element [3] survived', type(decoded.bless) == 'table' and decoded.bless[3] == 3,
      decoded.bless and decoded.bless[3])
check('  absent (nil) field stays absent', decoded.vocation == nil)

-- Re-encode the decoded table and confirm it decodes again to the same values
-- (idempotent round-trip).
local recompact = JSON.encode(decoded)
local redecoded = JSON.decode(recompact)
check('double round-trip keeps name', redecoded.name == 'Bubble')
check('double round-trip keeps array[5]', redecoded.bless[5] == 5)

--==========================================================================
-- 3. Pretty-print (indent). We accept a number OR a string indent.
--==========================================================================
local pretty = JSON.encode(source, 2) -- 2 spaces per level
check('encode(value, 2) returns a string', type(pretty) == 'string')
check('  pretty output has newlines', type(pretty) == 'string' and pretty:find('\n') ~= nil)
check('  pretty output has indentation', type(pretty) == 'string' and pretty:find('\n  ') ~= nil)
-- pretty must still decode back to the same data
local prettyDecoded = JSON.decode(pretty)
check('  pretty decodes back to same name', prettyDecoded.name == 'Bubble', prettyDecoded.name)
check('  pretty decodes back to same level', prettyDecoded.level == 250, prettyDecoded.level)

-- string indent (tab) is also accepted by this implementation
local prettyTab = JSON.encode(source, '\t')
check('encode(value, "\\t") returns a string', type(prettyTab) == 'string')
check('  tab-indented output contains a tab', type(prettyTab) == 'string' and prettyTab:find('\t') ~= nil)

-- indent of 0 / false / nil -> compact (no newlines)
check('encode(value, 0) is compact', select(2, pcall(function()
  local s = JSON.encode(source, 0)
  return type(s) == 'string' and not s:find('\n')
end)) == true)

--==========================================================================
-- 4. Decode hand-written JSON: types, escapes, unicode, null.
--==========================================================================
local raw = '{"a":1,"b":[true,false,null],"c":"line1\\nline2","d":-3.5,"e":"\\u00e1"}'
local d = JSON.decode(raw)
check('decode literal: object is a table', type(d) == 'table')
check('  a == 1', d.a == 1, d.a)
check('  b[1] == true', d.b[1] == true)
check('  b[2] == false', d.b[2] == false)
-- IMPORTANT rxi behaviour: JSON `null` decodes to Lua `nil`, NOT a sentinel.
-- So the array element after `false` is nil (the array length drops to 2), and
-- a `null` object value is simply ABSENT. We assert that real behaviour here.
check('  b[3] is nil (rxi maps JSON null -> nil)', d.b[3] == nil)
check('  null object value is absent',
      JSON.decode('{"x":null}').x == nil)
check('  c keeps embedded newline escape', type(d.c) == 'string' and d.c:find('\n') ~= nil)
check('  d == -3.5 (negative float)', d.d == -3.5, d.d)
check('  e decoded a unicode escape (non-empty string)', type(d.e) == 'string' and #d.e >= 1, d.e)

--==========================================================================
-- 5. Empty containers round-trip.
--==========================================================================
check('encode({}) is a string', type(JSON.encode({})) == 'string', JSON.encode({}))
local emptyDecoded = JSON.decode(JSON.encode({}))
check('decode(encode({})) is a table', type(emptyDecoded) == 'table')

--==========================================================================
-- 6. Errors propagate (rxi raises on malformed input / non-string).
--==========================================================================
check('decode("not json") raises', pcall(JSON.decode, '{ this is : not json ]') == false)
check('decode(nil) raises', pcall(JSON.decode, nil) == false)
check('decode("") raises', pcall(JSON.decode, '') == false)

print(('--- json: %d passed, %d failed ---'):format(pass, fail))
