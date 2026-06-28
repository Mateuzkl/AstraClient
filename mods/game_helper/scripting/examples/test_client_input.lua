--[[============================================================================
  test_client_input.lua — key polling + hotkey-combo parsing (ZB dialect).
  ============================================================================
  Exercises the input-query surface (read-only):
    * HotkeyManager.parseKeyCombination(combo) -> ok, modifiers, key
        (scripting/api/hotkeymanager.lua — PURE Lua, no side effects)
    * HotkeyManager.keyMapping                  -> name -> engine key code table
    * Client.isKeyPressed(key, flags)           -> bool (polls live keyboard)

  ALL READ-ONLY (polling + parsing) — no mutations, so no RUN_MUTATIONS gate.
  Client.sendHotkey is a STUB on this engine (no key-injection binding); we only
  assert it exists and is callable, never use it to fake input. Safe any time.
============================================================================]]

local pass, fail = 0, 0
local function check(name, cond, extra)
  if cond then
    pass = pass + 1
    print('[PASS] ' .. name .. (extra and (' = ' .. tostring(extra)) or ''))
  else
    fail = fail + 1
    print('[FAIL] ' .. name)
  end
end

-- The sandbox does NOT expose a bit library (no `bit`/`bit32`), so test a single
-- bit (a power-of-two flag) in a bitmask with pure arithmetic instead.
local function hasFlag(mask, flag)
  return type(mask) == 'number' and math.floor(mask / flag) % 2 == 1
end

print('=== HotkeyManager: keyMapping table ===')
check('HotkeyManager.keyMapping is table', type(HotkeyManager.keyMapping) == 'table')
-- A few canonical names should resolve to numeric engine key codes.
for _, name in ipairs({ 'a', 'f1', 'space', 'enter' }) do
  local code = HotkeyManager.keyMapping[name]
  check('keyMapping["' .. name .. '"] is a key code', type(code) == 'number', code)
end

print('=== HotkeyManager: parseKeyCombination ===')

-- Single plain key: ok=true, no modifiers, a numeric key code.
local ok, mods, key = HotkeyManager.parseKeyCombination('f1')
check('parse "f1" ok', ok == true)
check('parse "f1" modifiers == 0', mods == 0, mods)
check('parse "f1" key is number', type(key) == 'number', key)

-- Modifier + key: modifiers must OR-fold to a non-zero bitmask.
local ok2, mods2, key2 = HotkeyManager.parseKeyCombination('ctrl + shift + f2')
check('parse "ctrl+shift+f2" ok', ok2 == true)
check('parse "ctrl+shift+f2" has CONTROL bit',
  hasFlag(mods2, Enums.FlagModifiers.CONTROL), mods2)
check('parse "ctrl+shift+f2" has SHIFT bit',
  hasFlag(mods2, Enums.FlagModifiers.SHIFT), mods2)
check('parse "ctrl+shift+f2" key is number', type(key2) == 'number', key2)

-- Case / spacing tolerance: "Ctrl+A" and "  ctrl +  a " resolve the same.
local _, m3, k3 = HotkeyManager.parseKeyCombination('Ctrl+A')
local _, m4, k4 = HotkeyManager.parseKeyCombination('  ctrl +  a ')
check('parse is case/space tolerant (modifiers match)', m3 == m4, m3)
check('parse is case/space tolerant (key matches)', k3 == k4, k3)

-- Unknown key -> false, nil, nil (ZB failure shape).
local okBad, mBad, kBad = HotkeyManager.parseKeyCombination('ctrl+notarealkey')
check('parse unknown key returns false', okBad == false)
check('parse unknown key modifiers nil', mBad == nil)
check('parse unknown key code nil', kBad == nil)

-- Modifiers-only (no actual key) -> false (nothing to press).
local okMod = HotkeyManager.parseKeyCombination('ctrl+alt')
check('parse modifiers-only returns false', okMod == false)

-- Non-string input -> false (guarded).
check('parse(nil) returns false', (HotkeyManager.parseKeyCombination(nil)) == false)

print('=== Client.isKeyPressed (live poll) ===')
-- isKeyPressed always returns a boolean (never nil), for both a parsed code and a
-- name string. We do NOT assert WHICH state (depends on what is held right now).
if ok and type(key) == 'number' then
  local down = Client.isKeyPressed(key)
  check('Client.isKeyPressed(<f1 code>) returns boolean', type(down) == 'boolean', down)
end
check('Client.isKeyPressed("a") returns boolean', type(Client.isKeyPressed('a')) == 'boolean',
  Client.isKeyPressed('a'))
-- With a modifier flag gate (AND-mask): still a clean boolean.
check('Client.isKeyPressed with modifier flag returns boolean',
  type(Client.isKeyPressed('a', Enums.FlagModifiers.CONTROL)) == 'boolean')

print('=== Client.sendHotkey (stub — existence only) ===')
check('Client.sendHotkey exists', type(Client.sendHotkey) == 'function')
-- Calling it is a documented no-op stub on this engine; do NOT rely on injection.
print('[SKIP] Client.sendHotkey is a no-op stub here (no key-injection binding)')

print(('--- Client input: %d passed, %d failed ---'):format(pass, fail))
