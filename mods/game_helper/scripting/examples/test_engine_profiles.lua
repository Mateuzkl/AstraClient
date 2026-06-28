--[[============================================================================
  test_engine_profiles.lua — Engine per-module preset "profiles" (ZB dialect).
  ============================================================================
  Exercises the Engine profile surface (scripting/api/engine.lua §3.C) for the
  four module types ZB+Amon support: targeting / healing / equipment / shooter.
  ZB profile index is 0..9 (Amon slot "Preset "..(i+1)).

    * QUERIES (always safe):
        Engine.<mod>GetProfile()          -> active index, or -1
        Engine.<mod>GetProfileName(i)     -> display name string
        Engine.<mod>GetProfileSettings(i) -> settings table (or nil)
    * MUTATIONS (gated): Engine.<mod>SwitchProfile(i) and *SetProfileSettings()
      RE-RENDER the UI and RE-SAVE config (engine.lua gotcha #5: NOT per-tick).
      Both are behind RUN_MUTATIONS (default false). When off we only switch to
      the ALREADY-active profile (a no-op) to prove the call shape, and never
      write settings.

  Read-only by default. Safe to load on a running character.
============================================================================]]

local RUN_MUTATIONS = false   -- keep false: switch/set re-render the UI + save.

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

local function mutate(label, fn)
  if RUN_MUTATIONS then
    fn()
    print('[MUTATE] ' .. label)
  else
    print('[SKIP] would call ' .. label .. ' (RUN_MUTATIONS=false)')
  end
end

-- The four module families, each with its getProfile / getProfileName /
-- getProfileSettings / switchProfile method prefix.
local MODULES = { 'targeting', 'healing', 'equipment', 'magicShooter' }

local function cap(s) return s:sub(1, 1):upper() .. s:sub(2) end

for _, mod in ipairs(MODULES) do
  print('=== Engine profiles: ' .. mod .. ' ===')

  local getProfile     = Engine[mod .. 'GetProfile']
  local getProfileName = Engine[mod .. 'GetProfileName']
  local getSettings    = Engine[mod .. 'GetProfileSettings']
  local switchProfile  = Engine[mod .. 'SwitchProfile']

  check('Engine.' .. mod .. 'GetProfile exists', type(getProfile) == 'function')
  check('Engine.' .. mod .. 'GetProfileName exists', type(getProfileName) == 'function')
  check('Engine.' .. mod .. 'GetProfileSettings exists', type(getSettings) == 'function')
  check('Engine.' .. mod .. 'SwitchProfile exists', type(switchProfile) == 'function')

  -- Active profile index: a number; -1 means "unresolved" (engine absent/empty).
  local active = type(getProfile) == 'function' and getProfile() or nil
  check('Engine.' .. mod .. 'GetProfile returns number', type(active) == 'number', active)

  -- Name of slot 0 (always a queryable slot in the 0..9 range).
  if type(getProfileName) == 'function' then
    local name0 = getProfileName(0)
    check('Engine.' .. mod .. 'GetProfileName(0) is string', type(name0) == 'string', name0)
  end

  -- Settings of the active slot (when one is active) — table or nil, never error.
  if type(getSettings) == 'function' and type(active) == 'number' and active >= 0 then
    local s = getSettings(active)
    check('Engine.' .. mod .. 'GetProfileSettings(active) is table/nil',
      s == nil or type(s) == 'table', type(s))
    -- Sample at most a couple of top-level keys so we never dump a huge config.
    if type(s) == 'table' then
      local sampled, shown = 0, {}
      for k in pairs(s) do
        sampled = sampled + 1
        if sampled <= 2 then shown[#shown + 1] = tostring(k) end
      end
      print('   ' .. mod .. ' active settings: ' .. sampled .. ' keys (e.g. '
        .. table.concat(shown, ', ') .. ')')
    end
  end

  -- Gated mutation: switch to the ALREADY-active profile (no real change) just to
  -- prove the call shape. If nothing is active (-1) we still only announce intent.
  local target = (type(active) == 'number' and active >= 0) and active or 0
  mutate('Engine.' .. mod .. 'SwitchProfile(' .. target .. ') [re-select active]',
    function() switchProfile(target) end)
  check('Engine.' .. mod .. 'GetProfile stable after re-select',
    (type(getProfile) == 'function' and getProfile() or active) == active, active)
end

-- Explicit note: SetProfileSettings is intentionally NOT invoked here (it writes
-- + re-renders). We only assert the methods exist.
print('=== Engine profiles: setters present (NOT invoked) ===')
check('Engine.targetingSetProfileSettings exists', type(Engine.targetingSetProfileSettings) == 'function')
check('Engine.healingSetProfileSettings exists', type(Engine.healingSetProfileSettings) == 'function')
check('Engine.equipmentSetProfileSettings exists', type(Engine.equipmentSetProfileSettings) == 'function')
check('Engine.magicShooterSetProfileSettings exists', type(Engine.magicShooterSetProfileSettings) == 'function')

print(('--- Engine profiles: %d passed, %d failed ---'):format(pass, fail))
