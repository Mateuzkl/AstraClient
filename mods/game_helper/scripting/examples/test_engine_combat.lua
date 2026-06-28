--[[============================================================================
  test_engine_combat.lua — Engine combat feature toggles (Zerobot dialect).
  ============================================================================
  Exercises the Engine.* combat-feature surface (scripting/api/engine.lua):
    * QUERIES (always safe): Engine.is<Feature>Enabled() for every feature flag
      this engine exposes (healing, heal-friend, master bot, targeting, magic
      shooter, cavebot, equipment, timer, + the PvP-ish autoSSA / autoMightRing,
      and the STUB group hold-target/anti-push/rune-max/reconnect).
    * MUTATIONS (gated): Engine.enable<Feature>(bool) flips real combat state in
      the LIVE client, so every enable* call is behind RUN_MUTATIONS (default
      false -> only prints "would call X"). Flip to true ONLY if you actually
      want the bot to toggle healing/targeting/etc. on this character.

  Read-only by default. Safe to load on a running character.
============================================================================]]

local RUN_MUTATIONS = false   -- keep false: enable*() changes live combat state.

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

-- A mutation that only runs when explicitly enabled; otherwise it is announced.
local function mutate(label, fn)
  if RUN_MUTATIONS then
    fn()
    print('[MUTATE] ' .. label)
  else
    print('[SKIP] would call ' .. label .. ' (RUN_MUTATIONS=false)')
  end
end

print('=== Engine combat: feature state queries ===')

-- Every is*Enabled() must return a boolean (true/false), never nil.
local queries = {
  'isHealingEnabled', 'isHealFriendEnabled', 'isBotEnabled', 'isTargetingEnabled',
  'isMagicShooterEnabled', 'isCaveBotEnabled', 'isEquipmentEnabled', 'isTimerEnabled',
  'isAutoSSAEnabled', 'isAutoMightRingEnabled',
  -- STUB group (no Amon backing): must still answer a clean boolean.
  'isHoldTargetEnabled', 'isAntiPushEnabled', 'isRuneMaxEnabled', 'isReconnectEnabled',
}
for _, fnName in ipairs(queries) do
  local fn = Engine[fnName]
  check('Engine.' .. fnName .. ' exists', type(fn) == 'function')
  if type(fn) == 'function' then
    local v = fn()
    check('Engine.' .. fnName .. ' returns boolean', type(v) == 'boolean', v)
  end
end

-- The stub group should specifically be false on this engine (documented).
check('Engine.isHoldTargetEnabled is false (stub)', Engine.isHoldTargetEnabled() == false)
check('Engine.isReconnectEnabled is false (stub)', Engine.isReconnectEnabled() == false)

print('=== Engine combat: feature toggles (gated) ===')

-- enable* setters exist (callable) regardless of the RUN_MUTATIONS gate.
local toggles = {
  'enableHealing', 'enableHealFriend', 'enableTargeting', 'enableMagicShooter',
  'enableEquipment', 'enableTimer', 'enableCaveBot', 'enableBot',
}
for _, fnName in ipairs(toggles) do
  check('Engine.' .. fnName .. ' exists', type(Engine[fnName]) == 'function')
end

-- Demonstrate idempotent SET semantics WITHOUT changing state: read the current
-- value and "re-apply" the SAME value. Under RUN_MUTATIONS this is a no-op flip;
-- with the gate off it only prints intent. We never blindly enable a feature.
local curTargeting = Engine.isTargetingEnabled()
mutate('Engine.enableTargeting(' .. tostring(curTargeting) .. ') [re-apply current]',
  function() Engine.enableTargeting(curTargeting) end)

local curHealing = Engine.isHealingEnabled()
mutate('Engine.enableHealing(' .. tostring(curHealing) .. ') [re-apply current]',
  function() Engine.enableHealing(curHealing) end)

-- After a re-apply of the current value, the query must be unchanged either way.
check('Engine.isTargetingEnabled unchanged after re-apply',
  Engine.isTargetingEnabled() == curTargeting, Engine.isTargetingEnabled())
check('Engine.isHealingEnabled unchanged after re-apply',
  Engine.isHealingEnabled() == curHealing, Engine.isHealingEnabled())

print(('--- Engine combat: %d passed, %d failed ---'):format(pass, fail))
