local clientRoot = arg[1] or 'D:/AstraClient'

local function expect(condition, message)
  if not condition then
    error(message, 2)
  end
end

local persisted = {
  presets = true,
  sessions = {},
  sessions_settings = {},
  last_preset = 'broken',
  last_session = 0 / 0,
  Knight = true
}
local writes = 0

g_settings = {
  getNode = function(key)
    expect(key == 'Minibot_Settings', 'unexpected settings key')
    return persisted
  end,
  setNode = function(key, value)
    expect(key == 'Minibot_Settings', 'unexpected persisted settings key')
    persisted = value
    writes = writes + 1
  end
}

g_game = {
  getCharacterName = function()
    return 'Knight'
  end
}

g_logger = {
  warning = function()
  end
}

dofile(clientRoot .. '/modules/game_minibot/minibot.lua')

local loadedPresets = getSettingsValue(false, 'presets', nil)
expect(type(loadedPresets) == 'table', 'presets=true was not repaired')
expect(type(persisted.Knight) == 'table', 'character node=true was not repaired')
expect(type(persisted.sessions) == 'table', 'missing sessions root was not repaired')
expect(type(persisted.sessions_settings) == 'table', 'missing session settings root was not repaired')
expect(writes > 0, 'storage repairs were not persisted')

local writesBeforeMetadataRepair = writes
expect(setSettingsValue(false, 'presets', {
  ['7'] = { name = 'Persisted repair', uid = 7 }
}), 'stored preset update was rejected')
expect(type(persisted.presets['7'].creation) == 'number' and
  persisted.presets['7'].creation == persisted.presets['7'].creation,
  'missing preset creation repair was not persisted')
expect(writes > writesBeforeMetadataRepair, 'metadata repair did not reach g_settings')

local stored, err, changed = validateMiniBotConfigurationData({
  presets = {
    ['1'] = {
      name = 'Recovered',
      uid = 1,
      shortcuts = true,
      combat_attack = { attackMelee_enabled = 'yes', ammo_refill = true },
      support_main = {
        haste = true,
        auto_eat = { item = 'food', enabled = 1 },
        auto_training = { item1 = {}, item2 = math.huge, enabled = 'yes' }
      },
      support_manashield = {
        spell_shield = false,
        item_shield = { enabled = 'yes', health = 1e308, use_fear = 1 }
      },
      combat_pvp = { antiparalyze_settings = true },
      explorer = { lure = 'yes', stop = 1, lure_until = 1e308, stop_resume = {} },
      healing_groupTargets = { party = { Alice = { enabled = 'yes' }, Bob = true } },
      combat_shooter = {
        { priority = 1, item = 'broken', spell = 84, health = {}, enabled = 'yes' },
        { priority = math.huge }
      },
      combat_timers = {
        { priority = 1, item = 7439, max = 'two', ignorePz = 'yes', enabled = true }
      },
      equipment_amulets = {
        { priority = 1, item = 3051, min = 'low', ignore = { 3052, 'bad' }, enabled = true }
      },
      equipment_rings = {
        { priority = 1, item = {}, unequip = 'yes', enabled = true }
      },
      healing_health = {
        { priority = 1, item = 266, max = 'half', enabled = true }
      },
      healing_mana = {
        { priority = 1, item = 26074, min = {}, enabled = {} }
      },
      healing_group = {
        { priority = 1, target = 42, item = '3152', area = {}, enabled = 1 }
      },
      healing_groupParty = {
        { priority = 1, target = {}, spell = 89, max = 50, enabled = true }
      },
      healing_groupGuild = {
        { priority = 1, target = 'Druid', spell = '89', max = 50, enabled = true }
      }
    }
  },
  sessions = {
    ['2'] = { name = 'Recovered route', uid = 2 },
    ['3'] = { name = 'Broken route', uid = 3 }
  },
  sessions_settings = {
    ['2'] = { waypoints = { {
      position = { x = 100, y = 200, z = 7 }, index = 1,
      creatures = 'many', resume = {}, lure = 'yes', speed = 99, teleport = 1
    } } },
    ['3'] = { waypoints = 'broken' }
  },
  language = 'invalid',
  Knight = {
    panel_gamewindow = 'yes',
    huntingExplorer_gamewindow = 1,
    selected_preset = 999,
    selected_recordSession = 999
  }
}, 'settings', 'Knight')

expect(stored ~= nil and err == nil and changed, 'stored settings were not recoverable')
local recovered = stored.presets['1']
expect(type(recovered.creation) == 'number' and recovered.creation == recovered.creation,
  'missing preset creation was not repaired')
expect(type(recovered.shortcuts) == 'table', 'wrong preset root type was not repaired')
expect(recovered.shortcuts.shooter_enabled == false and
  recovered.shortcuts.huntingExplorer_enabled == false,
  'missing shortcut leaves were not normalized to booleans')
expect(recovered.combat_attack.attackMelee_enabled == false,
  'wrong combat-attack leaf was not safely repaired')
expect(type(recovered.combat_attack.ammo_refill) == 'table', 'wrong combat nested type was not repaired')
expect(recovered.combat_attack.ammo_refill.item == 0 and
  recovered.combat_attack.ammo_refill.enabled == false,
  'repaired ammo-refill object did not receive safe leaves')
expect(type(recovered.support_main.haste) == 'table', 'wrong support nested type was not repaired')
expect(recovered.support_main.haste.spell == 0 and recovered.support_main.haste.enabled == false and
  recovered.support_main.auto_eat.item == 0 and recovered.support_main.auto_eat.enabled == false and
  recovered.support_main.auto_training.item1 == 0 and recovered.support_main.auto_training.item2 == 0 and
  recovered.support_main.auto_training.enabled == false,
  'support nested leaves were not safely repaired')
expect(type(recovered.support_manashield.spell_shield) == 'table', 'wrong shield nested type was not repaired')
expect(recovered.support_manashield.spell_shield.enabled == false and
  recovered.support_manashield.item_shield.enabled == false and
  recovered.support_manashield.item_shield.health == 0 and
  recovered.support_manashield.item_shield.use_fear == false,
  'mana-shield leaves were not safely repaired')
expect(type(recovered.combat_pvp.antiparalyze_settings) == 'table' and
  recovered.combat_pvp.antiparalyze_settings.enabled == false,
  'PvP Anti-Paralyze settings were not safely repaired')
expect(recovered.explorer.lure == true and recovered.explorer.stop == false and
  recovered.explorer.lure_until == '' and recovered.explorer.stop_resume == '',
  'explorer leaves were not safely repaired')
expect(recovered.healing_groupTargets.party.Alice.enabled == false and
  type(recovered.healing_groupTargets.party.Bob) == 'nil',
  'healing target blocks were not normalized safely')
expect(#recovered.combat_shooter == 1 and recovered.combat_shooter[1].priority == 1,
  'invalid priority entry was not discarded')
expect(recovered.combat_shooter[1].item == 0 and recovered.combat_shooter[1].health == 0 and
  recovered.combat_shooter[1].max == 1 and recovered.combat_shooter[1].enabled == false,
  'combat shooter leaves were not safely repaired')
expect(recovered.combat_timers[1].max == 1 and recovered.combat_timers[1].ignorePz == false,
  'combat timer leaves were not safely repaired')
expect(recovered.equipment_amulets[1].min == 0 and #recovered.equipment_amulets[1].ignore == 1 and
  recovered.equipment_amulets[1].ignore[1] == 3052,
  'amulet leaves were not safely repaired')
expect(recovered.equipment_rings[1].item == 0 and recovered.equipment_rings[1].unequip == false,
  'ring leaves were not safely repaired')
expect(recovered.healing_health[1].max == 0 and type(recovered.healing_health[1].enabled) == 'boolean',
  'health healing leaves were not safely repaired')
expect(recovered.healing_mana[1].min == 0 and recovered.healing_mana[1].enabled == false,
  'mana healing leaves were not safely repaired')
expect(recovered.healing_group[1].target == '' and recovered.healing_group[1].item == 0 and
  recovered.healing_group[1].area == '' and recovered.healing_group[1].enabled == false,
  'custom group-healing leaves were not safely repaired')
expect(recovered.healing_groupParty[1].target == '' and type(recovered.healing_groupParty[1].spell) == 'number',
  'party group-healing leaves were not safely repaired')
expect(recovered.healing_groupGuild[1].spell == 0 and recovered.healing_groupGuild[1].target == 'Druid',
  'guild group-healing leaves were not safely repaired')
expect(type(stored.sessions['2'].creation) == 'number', 'missing session creation was not repaired')
expect(type(stored.sessions_settings['2'].waypoints) == 'table' and
  #stored.sessions_settings['2'].waypoints == 1 and
  stored.sessions_settings['2'].waypoints[1].creatures == 0 and
  stored.sessions_settings['2'].waypoints[1].resume == 0 and
  stored.sessions_settings['2'].waypoints[1].lure == false and
  stored.sessions_settings['2'].waypoints[1].speed == 5 and
  stored.sessions_settings['2'].waypoints[1].teleport == false,
  'stored waypoint leaves were not safely repaired')
expect(type(stored.sessions_settings['3'].waypoints) == 'table' and
  #stored.sessions_settings['3'].waypoints == 0, 'wrong stored waypoints type was not repaired')
expect(type(stored.Knight) == 'table', 'stored character node was not repaired')
expect(stored.language == 'ptbr', 'invalid global language was not repaired')
expect(stored.Knight.panel_gamewindow == false and stored.Knight.huntingExplorer_gamewindow == false,
  'wrong character UI flags were not repaired')
expect(stored.Knight.selected_preset == nil and stored.Knight.selected_recordSession == nil,
  'stale character selections were not cleared')

local function makeValidPreset()
  return {
    DeusOT_Assistant_Preset_Export = true,
    version = 1002002,
    name = 'Imported preset',
    uid = 1,
    creation = 10,
    shortcuts = {},
    combat_attack = { ammo_refill = {} },
    -- max is intentionally absent: this is the exact legacy shape emitted by
    -- combat_shooter.saveSettings and must normalize to its non-phantom value.
    combat_shooter = { {
      priority = 1, item = 0, spell = 84, health = 100, mana = 0,
      reqmana = 20, hits = 1, extended = false, ignorePz = true,
      enabled = true, harmony = 0
    } },
    combat_timers = { {
      priority = 1, item = 7439, spell = 0, reqmana = 0, min = 0,
      max = 2, manaMin = 0, manaMax = 0, hits = 1, hitsMax = 3,
      harmony = 0, ignorePz = false, enabled = true
    } },
    equipment_amulets = { {
      priority = 1, item = 3051, spell = 0, reqmana = 0, min = 0,
      max = 80, manaMin = 0, manaMax = 100, harmony = 0,
      unequip = false, enabled = true, ignore_enabled = true, ignore = { 3052 }
    } },
    equipment_rings = { {
      priority = 1, item = 3048, spell = 0, reqmana = 0, min = 0,
      max = 70, manaMin = 0, manaMax = 100, harmony = 0,
      unequip = false, enabled = true, ignore_enabled = false, ignore = {}
    } },
    healing_health = { {
      priority = 1, item = 266, spell = 0, reqmana = 0, min = 0,
      max = 50, manaMin = 0, manaMax = 0, harmony = 0, enabled = true
    } },
    healing_mana = { {
      priority = 1, item = 26074, spell = 0, reqmana = 0, min = 0,
      max = 30, manaMin = 0, manaMax = 0, harmony = 0, enabled = true
    } },
    healing_group = { {
      priority = 1, target = 'Alice', item = 3152, spell = 0,
      reqmana = 0, min = 0, max = 50, manaMin = 0, manaMax = 0,
      enabled = true, area = ''
    } },
    healing_groupParty = { {
      priority = 1, target = 'Knight', item = 0, spell = 89,
      reqmana = 70, min = 0, max = 50, manaMin = 0, manaMax = 0,
      enabled = true, area = 'utura tio'
    } },
    healing_groupGuild = { {
      priority = 1, target = 'Druid', item = 0, spell = 89,
      reqmana = 70, min = 0, max = 50, manaMin = 0, manaMax = 0,
      enabled = true, area = ''
    } },
    support_main = { haste = {}, change_gold = {}, auto_eat = {}, auto_training = {}, auto_mount = {} },
    support_manashield = { spell_shield = {}, item_shield = {}, remove_shield = {} },
    combat_pvp = {
      antiparalyze_settings = {
        enabled = true,
        spells = {
          { id = 6, priority = 2 },
          { id = 39, priority = 1 }
        }
      }
    },
    explorer = {
      lure = true, stop = false, lure_until = '', lure_resume = '',
      stop_until = '', stop_resume = ''
    },
    healing_groupTargets = { custom = { Alice = {} }, party = {}, guild = {} }
  }
end

local validPreset = makeValidPreset()
local writesBeforeImports = writes
local normalizedValidPreset = validateMiniBotConfigurationData(validPreset, 'preset-import')
expect(normalizedValidPreset ~= nil, 'valid preset import was rejected')
expect(normalizedValidPreset.combat_shooter[1].max == 1,
  'legacy shooter entry did not receive its compatible max default')
expect(normalizedValidPreset.combat_shooter[1].smart == true,
  'legacy shooter Smart state was not migrated from ignorePz')
expect(normalizedValidPreset.combat_pvp.antiparalyze_settings.enabled == true and
  normalizedValidPreset.combat_pvp.antiparalyze_settings.spells[1].id == 39 and
  normalizedValidPreset.combat_pvp.antiparalyze_settings.spells[1].priority == 1 and
  normalizedValidPreset.combat_pvp.antiparalyze_settings.spells[2].id == 6 and
  normalizedValidPreset.combat_pvp.antiparalyze_settings.spells[2].priority == 2,
  'PvP Anti-Paralyze spell priority was not normalized')
for _, root in ipairs({
  'combat_shooter', 'combat_timers', 'equipment_amulets', 'equipment_rings',
  'healing_health', 'healing_mana', 'healing_group', 'healing_groupParty',
  'healing_groupGuild'
}) do
  expect(type(normalizedValidPreset[root][1].priority) == 'number', root .. ' lost its valid entry')
  expect(type(normalizedValidPreset[root][1].enabled) == 'boolean', root .. ' enabled leaf was not normalized')
end

local invalidName = {}
for key, value in pairs(validPreset) do invalidName[key] = value end
invalidName.name = true
expect(validateMiniBotConfigurationData(invalidName, 'preset-import') == nil,
  'preset import with invalid name was accepted')

local invalidRoot = {}
for key, value in pairs(validPreset) do invalidRoot[key] = value end
invalidRoot.shortcuts = true
expect(validateMiniBotConfigurationData(invalidRoot, 'preset-import') == nil,
  'preset import with invalid root was accepted')

local invalidNested = {}
for key, value in pairs(validPreset) do invalidNested[key] = value end
invalidNested.support_main = { haste = false }
expect(validateMiniBotConfigurationData(invalidNested, 'preset-import') == nil,
  'preset import with invalid nested object was accepted')

local invalidList = {}
for key, value in pairs(validPreset) do invalidList[key] = value end
invalidList.combat_shooter = { { priority = math.huge } }
expect(validateMiniBotConfigurationData(invalidList, 'preset-import') == nil,
  'preset import with non-finite priority was accepted')

local invalidLeafCases = {
  { 'combat_shooter', 'item', '3161' },
  { 'combat_timers', 'max', {} },
  { 'equipment_amulets', 'ignore', { 3052, 'bad' } },
  { 'equipment_rings', 'unequip', 1 },
  { 'healing_health', 'enabled', 'yes' },
  { 'healing_mana', 'max', false },
  { 'healing_group', 'target', {} },
  { 'healing_groupParty', 'item', -1 },
  { 'healing_groupGuild', 'area', true }
}
for _, invalidCase in ipairs(invalidLeafCases) do
  local candidate = makeValidPreset()
  candidate[invalidCase[1]][1][invalidCase[2]] = invalidCase[3]
  expect(validateMiniBotConfigurationData(candidate, 'preset-import') == nil,
    'strict preset import accepted invalid ' .. invalidCase[1] .. '.' .. invalidCase[2])
end

local function expectInvalidPresetMutation(description, mutate)
  local candidate = makeValidPreset()
  mutate(candidate)
  expect(validateMiniBotConfigurationData(candidate, 'preset-import') == nil,
    'strict preset import accepted invalid ' .. description)
end

expectInvalidPresetMutation('combat_attack.ammo_refill.item', function(candidate)
  candidate.combat_attack.ammo_refill.item = '3447'
end)
expectInvalidPresetMutation('combat_attack auto-attack flag', function(candidate)
  candidate.combat_attack.autoAttack_highhealth = 1
end)
expectInvalidPresetMutation('support_main.haste.spell', function(candidate)
  candidate.support_main.haste.spell = 'utani hur'
end)
expectInvalidPresetMutation('support_main.auto_eat.item', function(candidate)
  candidate.support_main.auto_eat.item = {}
end)
expectInvalidPresetMutation('support_main.auto_training.item2', function(candidate)
  candidate.support_main.auto_training.item2 = 1e308
end)
expectInvalidPresetMutation('support_manashield.spell_shield.health', function(candidate)
  candidate.support_manashield.spell_shield.health = 1e308
end)
expectInvalidPresetMutation('support_manashield.remove_shield.ignore_fear', function(candidate)
  candidate.support_manashield.remove_shield.ignore_fear = 1
end)
expectInvalidPresetMutation('combat_pvp.antiparalyze_settings.enabled', function(candidate)
  candidate.combat_pvp.antiparalyze_settings.enabled = 1
end)
expectInvalidPresetMutation('combat_pvp antiparalyze duplicate spell', function(candidate)
  candidate.combat_pvp.antiparalyze_settings.spells = {
    { id = 6, priority = 1 }, { id = 6, priority = 2 }
  }
end)
expectInvalidPresetMutation('combat_pvp antiparalyze sixth spell', function(candidate)
  candidate.combat_pvp.antiparalyze_settings.spells = {}
  for index = 1, 6 do
    candidate.combat_pvp.antiparalyze_settings.spells[index] = { id = index, priority = math.min(index, 5) }
  end
end)
expectInvalidPresetMutation('shortcut flag', function(candidate)
  candidate.shortcuts.huntingExplorer_enabled = 'yes'
end)
expectInvalidPresetMutation('explorer numeric string', function(candidate)
  candidate.explorer.lure_until = 'unbounded'
end)
expectInvalidPresetMutation('explorer boolean', function(candidate)
  candidate.explorer.stop = 1
end)
expectInvalidPresetMutation('healing target enabled leaf', function(candidate)
  candidate.healing_groupTargets.custom.Alice.enabled = 'yes'
end)
expectInvalidPresetMutation('finite but unsafe numeric leaf', function(candidate)
  candidate.combat_timers[1].max = 1e308
end)

local validRecorder = {
  version = 1,
  name = 'Imported route',
  uid = 1,
  creation = 20,
  waypoints = {
    { position = { x = 100, y = 200, z = 7 }, index = 1 }
  }
}
expect(validateMiniBotConfigurationData(validRecorder, 'recorder-import') ~= nil,
  'valid recorder import was rejected')

for _, speed in ipairs({ 1, 10, 20 }) do
  local recorderAtSpeed = {
    version = 1,
    name = 'Recorder speed ' .. speed,
    uid = speed,
    creation = 20,
    waypoints = {
      { position = { x = 100, y = 200, z = 7 }, index = 1, speed = speed }
    }
  }
  local normalizedRecorder = validateMiniBotConfigurationData(recorderAtSpeed, 'recorder-import')
  expect(normalizedRecorder ~= nil and normalizedRecorder.waypoints[1].speed == speed,
    'recorder import did not preserve lure speed ' .. speed)
end

local recorderSpeedAboveSlider = {
  version = 1,
  name = 'Recorder speed 21',
  uid = 21,
  creation = 20,
  waypoints = {
    { position = { x = 100, y = 200, z = 7 }, index = 1, speed = 21 }
  }
}
expect(validateMiniBotConfigurationData(recorderSpeedAboveSlider, 'recorder-import') == nil,
  'recorder import accepted a lure speed above the donor slider range')

local recorderMissing = {
  version = 1, name = 'Missing waypoints', uid = 2, creation = 21
}
expect(validateMiniBotConfigurationData(recorderMissing, 'recorder-import') == nil,
  'recorder import without waypoints was accepted')

local recorderWrongWaypoints = {
  version = 1, name = 'Wrong waypoints', uid = 2, creation = 21, waypoints = true
}
expect(validateMiniBotConfigurationData(recorderWrongWaypoints, 'recorder-import') == nil,
  'recorder import with non-table waypoints was accepted')

local recorderWrongPosition = {
  version = 1,
  name = 'Wrong position',
  uid = 3,
  creation = 22,
  waypoints = { { position = { x = math.huge, y = 2, z = 7 }, index = 1 } }
}
expect(validateMiniBotConfigurationData(recorderWrongPosition, 'recorder-import') == nil,
  'recorder import with invalid position was accepted')

local recorderWrongIndex = {
  version = 1,
  name = 'Wrong index',
  uid = 4,
  creation = 23,
  waypoints = { { position = { x = 1, y = 2, z = 7 }, index = -math.huge } }
}
expect(validateMiniBotConfigurationData(recorderWrongIndex, 'recorder-import') == nil,
  'recorder import with non-finite index was accepted')

for _, recorderCase in ipairs({
  {
    name = 'out-of-range x',
    waypoint = { position = { x = 65536, y = 2, z = 7 }, index = 1 }
  },
  {
    name = 'out-of-range floor',
    waypoint = { position = { x = 1, y = 2, z = 16 }, index = 1 }
  },
  {
    name = 'out-of-range speed',
    waypoint = { position = { x = 1, y = 2, z = 7 }, index = 1, speed = 1e308 }
  },
  {
    name = 'wrong lure leaf',
    waypoint = { position = { x = 1, y = 2, z = 7 }, index = 1, lure = 1 }
  }
}) do
  expect(validateMiniBotConfigurationData({
    version = 1, name = recorderCase.name, uid = 10, creation = 24,
    waypoints = { recorderCase.waypoint }
  }, 'recorder-import') == nil, 'recorder import accepted ' .. recorderCase.name)
end

local cyclic = {
  DeusOT_Assistant_Preset_Export = true,
  version = 1002002,
  name = 'Cycle', uid = 4, creation = 23
}
cyclic.loop = cyclic
expect(validateMiniBotConfigurationData(cyclic, 'preset-import') == nil, 'cyclic import was accepted')

local tooDeep = {
  DeusOT_Assistant_Preset_Export = true,
  version = 1002002,
  name = 'Deep', uid = 5, creation = 24
}
local cursor = tooDeep
for _ = 1, 20 do
  cursor.child = {}
  cursor = cursor.child
end
expect(validateMiniBotConfigurationData(tooDeep, 'preset-import') == nil, 'over-deep import was accepted')

local nonFinite = {
  DeusOT_Assistant_Preset_Export = true,
  version = 1002002,
  name = 'NaN', uid = 6, creation = 25,
  unexpected = 0 / 0
}
expect(validateMiniBotConfigurationData(nonFinite, 'preset-import') == nil, 'NaN import was accepted')
expect(writes == writesBeforeImports, 'import validation persisted data before acceptance')

expect(resolveAutoAttackType(false, {}) == 0, 'disabled auto-attack did not resolve to zero')
expect(resolveAutoAttackType(true, { autoAttack_highhealth = true }) == 3,
  'high-health auto-attack mode did not resolve')
expect(resolveAutoAttackType(true, { autoAttack_health = true, attackMelee_enabled = true }) == 102,
  'health/melee auto-attack mode did not resolve from saved configuration')
expect(resolveAutoAttackType(true, { autoAttack_smartArrow = true, attackMelee_enabled = true }) == 300,
  'smart/melee auto-attack mode did not resolve from saved configuration')

local movementSettings = {
  shortcuts = { huntingRecorder_enabled = true, huntingExplorer_enabled = true }
}
expect(disableMovementShortcut(movementSettings, 21) == true and
  movementSettings.shortcuts.huntingExplorer_enabled == false,
  'Explorer movement shortcut was not disabled')
expect(disableMovementShortcut(movementSettings, 5) == true and
  movementSettings.shortcuts.huntingRecorder_enabled == false,
  'Recorder movement shortcut was not disabled')

-- A freshly saved Support page carries its enabled state in support_main.
-- Reloading the internal module must arm Haste even when no shortcut widget
-- has had a chance to seed shortcuts.supportHaste_enabled yet.
local supportProfile = {
  support_main = {
    haste = { spell = 6, reqmana = 60, enabled = true, ignorePz = false }
  },
  shortcuts = {}
}
local moduleToggles = {}
local supportRules = {}
modules = {
  game_minibot = {
    getPressetSettings = function()
      return supportProfile
    end
  }
}
g_minibot = {
  resetModule = function()
  end,
  addModule = function(moduleType, rule)
    supportRules[moduleType] = rule
    return true
  end,
  setModuleToggle = function(moduleType, enabled)
    moduleToggles[moduleType] = enabled
    return true
  end
}
g_spells = {
  getSpellInfoById = function(spellId)
    if spellId == 6 then
      return { id = 6, words = 'utani hur', mana = 60, groups = { 2 } }
    end
    return nil
  end
}
dofile(clientRoot .. '/modules/game_minibot/pages/support_general.lua')
local hasteCheckState = false
local hasteCheckWidget = {
  setChecked = function(self, checked)
    expect(self.ignoreCallback == true, 'Haste shortcut sync did not suppress callbacks')
    hasteCheckState = checked
  end
}
local hasteShortcutWidget = {
  isChecked = function()
    return true
  end
}
expect(support_generalModule.applyHasteShortcutState(hasteCheckWidget, hasteShortcutWidget) and
  hasteCheckState == true and hasteCheckWidget.ignoreCallback == nil,
  'open Auto Haste page did not synchronize from its compact shortcut')
support_generalModule.reloadInternalModule()
expect(moduleToggles[4] == true, 'fresh-profile Auto Haste did not enable module 4')
expect(supportRules[4] ~= nil and supportRules[4].spell == 'utani hur',
  'castable Auto Haste did not register its spell')
expect(supportProfile.shortcuts.supportHaste_enabled == nil,
  'Auto Haste reload unexpectedly rewrote shortcut UI state')
modules.game_actionbar = {
  canSpellCast = function()
    return false
  end
}
support_generalModule.reloadInternalModule()
expect(supportRules[4] ~= nil and supportRules[4].spell == '',
  'uncastable Auto Haste registered an invalid vocation spell')
supportProfile.support_main.haste.enabled = false
support_generalModule.reloadInternalModule()
expect(moduleToggles[4] == false, 'disabled Auto Haste left module 4 enabled')

-- If the vocation cannot cast Magic Shield, an enabled potion fallback must
-- still register a functional item-only rule instead of an unusable spell.
local manaShieldProfile = {
  support_manashield = {
    spell_shield = {
      enabled = true, health = 50, use_potion = true,
      creatures_enabled = false, creatures_value = 0,
      recast_enabled = false, recast_value = 0
    },
    item_shield = { enabled = false },
    remove_shield = { enabled = false }
  }
}
local moduleRules = {}
modules.game_minibot.getPressetSettings = function()
  return manaShieldProfile
end
modules.game_actionbar = {
  canSpellCast = function()
    return false
  end
}
g_minibot.addModule = function(moduleType, rule)
  moduleRules[moduleType] = rule
  return true
end
g_spells.getSpellInfoById = function(spellId)
  if spellId == 44 then
    return { id = 44, words = 'utamo vita', mana = 50, groups = { 2 } }
  elseif spellId == 245 then
    return { id = 245, words = 'exana vita', mana = 50, groups = { 2 } }
  end
  return nil
end
dofile(clientRoot .. '/modules/game_minibot/pages/support_manashield.lua')
expect(support_manashieldModule.getItemShieldEnabledTooltip('ptbr'):find('Se o Mana Shield', 1, true) == 1,
  'Mana Shield item tooltip did not select Portuguese for ptbr')
expect(support_manashieldModule.getItemShieldEnabledTooltip('enus'):find('If Magic Shield', 1, true) == 1,
  'Mana Shield item tooltip did not select English for enus')
support_manashieldModule.reloadInternalModule()
expect(moduleRules[13] ~= nil and moduleRules[13].spell == '' and
  moduleRules[13].item == 35563 and moduleRules[13].reqmana == 0,
  'uncastable Magic Shield did not retain its potion-only fallback')
manaShieldProfile.support_manashield.remove_shield = {
  enabled = true, health = 70, ignore_fear = false,
  creatures_enabled = false, creatures_value = 0
}
support_manashieldModule.reloadInternalModule()
expect(moduleRules[15] ~= nil and moduleRules[15].spell == '' and moduleRules[15].spellId[1] == nil,
  'uncastable Remove Magic Shield registered an invalid vocation spell')

dofile(clientRoot .. '/modules/game_minibot/pages/healing_group.lua')
expect(healing_groupModule.resolveRequiredMana({}, { mana = 70 }) == 70,
  'group-heal spell mana was not used when legacy reqmana was absent')
expect(healing_groupModule.resolveRequiredMana({ reqmana = 90 }, { mana = 70 }) == 90,
  'explicit group-heal reqmana was not preserved')
local twentyEntries = {}
for index = 1, 20 do
  twentyEntries[index] = { priority = index }
end
local canAdd, selectedKey, selectedCount = healing_groupModule.canAddToSelectedList({
  healing_groupType = 'party',
  healing_group = twentyEntries,
  healing_groupParty = {}
})
expect(canAdd and selectedKey == 'healing_groupParty' and selectedCount == 0,
  'full Custom list incorrectly blocked adding to an empty Party list')
canAdd, selectedKey, selectedCount = healing_groupModule.canAddToSelectedList({
  healing_groupType = 'party',
  healing_group = {},
  healing_groupParty = twentyEntries
})
expect(not canAdd and selectedKey == 'healing_groupParty' and selectedCount == 20,
  'Party list accepted a 21st entry')
canAdd, selectedKey, selectedCount = healing_groupModule.canAddToSelectedList({
  healing_groupType = 'custom', healing_group = twentyEntries, healing_groupParty = {}
})
expect(not canAdd and selectedKey == 'healing_group' and selectedCount == 20,
  'Custom list did not enforce its own 20-entry limit')

dofile(clientRoot .. '/modules/game_minibot/pages/combat_timers.lua')
local defaultDelayText, defaultDelayValue = combat_timersModule.normalizeDelayText('')
expect(defaultDelayText == '1' and defaultDelayValue == 1,
  'empty Combat Timers delay displayed 1s but retained a zero phantom value')
local configuredDelayText, configuredDelayValue = combat_timersModule.normalizeDelayText('7')
expect(configuredDelayText == '7' and configuredDelayValue == 7,
  'configured Combat Timers delay was changed')

dofile(clientRoot .. '/modules/game_minibot/pages/combat_shooter.lua')
local autoRotateVisibility = nil
local shooterEntry = {
  autoRotate = {
    setVisible = function(_, visible)
      autoRotateVisibility = visible
    end
  }
}
expect(combat_shooterModule.applyAutoRotateVisibility(shooterEntry, true) and
  autoRotateVisibility == true,
  'Shooter item Apply did not update the selected row Auto Rotate marker')
expect(combat_shooterModule.applyAutoRotateVisibility(shooterEntry, false) and
  autoRotateVisibility == false,
  'Shooter spell Apply did not update the selected row Auto Rotate marker')
expect(not combat_shooterModule.applyAutoRotateVisibility({}, true),
  'Shooter Auto Rotate helper accepted a row without its child widget')

local pvpProfile = {
  shortcuts = { tankMode_enabled = true },
  combat_pvp = {
    antiparalyze_settings = {
      enabled = true,
      spells = { { id = 6, priority = 2 }, { id = 39, priority = 1 } }
    }
  }
}
local pvpRules = { [16] = {}, [17] = {} }
local pvpToggles = {}
modules.game_minibot.getPressetSettings = function()
  return pvpProfile
end
modules.game_actionbar = {
  canSpellCast = function()
    return true
  end
}
g_spells.getSpellInfoById = function(spellId)
  if spellId == 6 then
    return { id = 6, words = 'utani hur', mana = 60, groups = { 2 } }
  elseif spellId == 39 then
    return { id = 39, words = 'utani gran hur', mana = 100, groups = { 2 } }
  end
end
g_minibot.resetModule = function(moduleType)
  pvpRules[moduleType] = {}
end
g_minibot.addModule = function(moduleType, rule)
  table.insert(pvpRules[moduleType], rule)
  return #pvpRules[moduleType]
end
g_minibot.setModuleToggle = function(moduleType, enabled)
  pvpToggles[moduleType] = enabled == true
  return true
end
dofile(clientRoot .. '/modules/game_minibot/pages/combat_pvp.lua')
combat_pvpModule.reloadInternalModule()
expect(pvpToggles[16] and #pvpRules[16] == 2 and
  pvpRules[16][1].item == 3081 and pvpRules[16][2].item == 3048,
  'PvP Tank Mode did not register SSA and Might Ring as module 16 rules')
expect(pvpToggles[17] and #pvpRules[17] == 2 and
  pvpRules[17][1].spell == 'utani gran hur' and pvpRules[17][1].reqmana == 100 and
  pvpRules[17][2].spell == 'utani hur',
  'PvP Anti-Paralyze did not preserve priority/mana in module 17')
local editableSpells = { { id = 6, priority = 1 }, { id = 39, priority = 2 } }
table.remove(editableSpells, 1)
table.insert(editableSpells, { id = 6, priority = 1 })
editableSpells[1].priority = 2
local reorderedSpellIds = combat_pvpModule.getOrderedAntiParalyzeSpellIds(editableSpells)
expect(reorderedSpellIds[1] == 6 and reorderedSpellIds[2] == 39,
  'PvP Anti-Paralyze add/remove/reprioritize sequence lost its order')
MouseRightButton = 2
local mousePoint = { x = 50, y = 60 }
local mouseButton, normalizedPoint =
  combat_pvpModule.normalizeMousePressArguments(mousePoint, MouseRightButton)
expect(mouseButton == MouseRightButton and normalizedPoint == mousePoint,
  'PvP entry right-click callback did not normalize the engine argument order')

dofile(clientRoot .. '/modules/game_minibot/pages/main_settings.lua')
g_game.getVocationName = function(vocationId)
  expect(vocationId == 4, 'Settings passed an unexpected vocation id')
  return 'Elite Knight'
end
local vocationPlayer = { getVocation = function() return 4 end }
expect(main_settingsModule.resolveVocationName(vocationPlayer) == 'Elite Knight',
  'Settings did not resolve vocation through g_game.getVocationName(id)')
g_game.getVocationName = function()
  error('simulated unavailable vocation lookup')
end
VocationNames = { [4] = 'Knight' }
expect(main_settingsModule.resolveVocationName(vocationPlayer) == 'Knight' and
  main_settingsModule.resolveVocationName(nil) == '',
  'Settings vocation fallback/player guard failed')

LocalPlayer = {}
dofile(clientRoot .. '/modules/gamelib/core/player.lua')
local harmonyPlayer = setmetatable({}, { __index = LocalPlayer })
expect(harmonyPlayer:getHarmony() == 0, 'new LocalPlayer Harmony did not start at 0')
expect(harmonyPlayer:setHarmony(1) == 1 and harmonyPlayer:getHarmony() == 1,
  'LocalPlayer Harmony did not store level 1')
expect(harmonyPlayer:setHarmony(5) == 5 and harmonyPlayer:getHarmony() == 5,
  'LocalPlayer Harmony did not store level 5')
expect(harmonyPlayer:setHarmony(99) == 5 and harmonyPlayer:setHarmony(-1) == 0,
  'LocalPlayer Harmony did not clamp to 0..5')
harmonyPlayer:setHarmony(5)
expect(harmonyPlayer:clearHarmony() == 0 and harmonyPlayer:getHarmony() == 0,
  'LocalPlayer Harmony did not clear on lifecycle reset')

dofile(clientRoot .. '/modules/game_minibot/pages/hunting_recorder.lua')
local recorderFailureSyncs = 0
modules.game_minibot.onMiniBotGameWindowChangeFromPanel = function(widgetId, checked)
  expect(widgetId == 'huntingRecorder_gamewindow' and checked == false,
    'Recorder failure synchronized the wrong compact control')
  recorderFailureSyncs = recorderFailureSyncs + 1
end
hunting_recorderModule.onWalkFailed(1, 21)
expect(recorderFailureSyncs == 0, 'Explorer failure disabled the open Recorder page')
hunting_recorderModule.onWalkFailed(1, 5)
expect(recorderFailureSyncs == 1, 'Recorder path failure did not disable its open page')
local transitionNodes = {}
hunting_recorderModule.insertWaypointOnPos = function(position, teleport)
  transitionNodes[#transitionNodes + 1] = { position = position, teleport = teleport }
end
expect(hunting_recorderModule.insertTransitionWaypoints(
  { x = 10, y = 10, z = 7 }, { x = 10, y = 10, z = 8 }),
  'Recorder rejected a valid floor transition pair')
expect(#transitionNodes == 2 and transitionNodes[1].teleport == true and
  transitionNodes[2].teleport == false,
  'Recorder marked the floor-transition arrival as another teleport origin')
local waypointSpeeds = {
  { position = { x = 1, y = 1, z = 7 }, index = 1, speed = 4 },
  { position = { x = 2, y = 1, z = 7 }, index = 2, speed = 5 }
}
hunting_recorderModule.selectedSessionIndex = 2
expect(hunting_recorderModule.updateSelectedWaypointSpeed(waypointSpeeds, 9),
  'selected waypoint speed update failed')
expect(waypointSpeeds[1].speed == 4 and waypointSpeeds[2].speed == 9,
  'lure-speed edit changed the wrong waypoint')

local recorderReloads = 0
local restoredWalkIndex = nil
local recorderCurrentIndex = 7
g_minibot.getCurrentWalkIndex = function()
  return recorderCurrentIndex
end
g_minibot.setCurrentWalkIndex = function(index)
  restoredWalkIndex = index
end
hunting_recorderModule.reloadInternalModule = function()
  recorderReloads = recorderReloads + 1
end
hunting_recorderModule.getSessionSettings = function()
  return {
    waypoints = {
      { index = 1 },
      { index = 2 },
      { index = 3 }
    }
  }
end
expect(hunting_recorderModule.reloadInternalModulePreservingWalkIndex() == 3 and
  recorderReloads == 1 and restoredWalkIndex == 3,
  'Recorder live reload did not clamp an out-of-range active walk index')
recorderCurrentIndex = 2
restoredWalkIndex = nil
expect(hunting_recorderModule.reloadInternalModulePreservingWalkIndex() == 2 and
  recorderReloads == 2 and restoredWalkIndex == 2,
  'Recorder live reload did not preserve an in-range active walk index')
expect(hunting_recorderModule.clampWalkIndex(4, {}) == 0,
  'Recorder live reload did not reset progress for an empty route')

local function multiFloorRemovalRoute()
  return {
    { position = { x = 100, y = 100, z = 7 }, index = 1, teleport = true },
    { position = { x = 100, y = 100, z = 8 }, index = 2, teleport = false },
    { position = { x = 101, y = 100, z = 8 }, index = 3, teleport = true },
    { position = { x = 101, y = 100, z = 9 }, index = 4, teleport = false }
  }
end

local removedBeforeCursor, cursorAfterEarlierRemoval =
  hunting_recorderModule.removeWaypointAndRemapWalkIndex(multiFloorRemovalRoute(), 2, 3)
expect(#removedBeforeCursor == 3 and cursorAfterEarlierRemoval == 2 and
  removedBeforeCursor[1].index == 1 and removedBeforeCursor[2].index == 2 and
  removedBeforeCursor[3].index == 3 and removedBeforeCursor[2].position.z == 8 and
  removedBeforeCursor[3].position.z == 9,
  'Recorder removal before the active multi-floor cursor did not reindex/decrement safely')

local removedAfterCursor, cursorAfterLaterRemoval =
  hunting_recorderModule.removeWaypointAndRemapWalkIndex(multiFloorRemovalRoute(), 4, 2)
expect(#removedAfterCursor == 3 and cursorAfterLaterRemoval == 2 and
  removedAfterCursor[3].index == 3 and removedAfterCursor[3].position.z == 8,
  'Recorder removal after the active cursor did not preserve/reindex safely')

restoredWalkIndex = nil
expect(hunting_recorderModule.reloadInternalModulePreservingWalkIndex(cursorAfterEarlierRemoval) == 2 and
  recorderReloads == 3 and restoredWalkIndex == 2,
  'Recorder ON removal did not restore the remapped walk cursor after reload')

local compactChecks = {
  huntingRecorder_gamewindow = true,
  huntingExplorer_gamewindow = true
}
local synchronizedPageIds = {}
local compactPanel = {
  getChildById = function(_, id)
    if compactChecks[id] == nil then
      return nil
    end
    return {
      setChecked = function(_, checked)
        compactChecks[id] = checked
      end
    }
  end
}
modules.game_interface = {
  getMiniBotPanel = function()
    return compactPanel
  end
}
getPageModule = function()
  return {
    reloadEnabledShortcut = function(_, widget)
      synchronizedPageIds[#synchronizedPageIds + 1] = widget:getId()
      expect(widget:isChecked() == false, 'movement page received an enabled BotCheck widget')
    end
  }
end
expect(syncDisabledMovementAutomationWidgets(), 'movement widget synchronization failed')
expect(compactChecks.huntingRecorder_gamewindow == false and
  compactChecks.huntingExplorer_gamewindow == false and
  synchronizedPageIds[1] == 'huntingRecorder_gamewindow' and
  synchronizedPageIds[2] == 'huntingExplorer_gamewindow',
  'BotCheck did not synchronize compact and open movement controls')

dofile(clientRoot .. '/modules/game_minibot/pages/equipment_amulets.lua')
dofile(clientRoot .. '/modules/game_minibot/pages/equipment_rings.lua')
for name, pageModule in pairs({
  amulet = equipment_amuletsModule,
  ring = equipment_ringsModule
}) do
  expect(pageModule.isValidEquipmentEntry({ item = 3051, min = 20, max = 0, manaMin = 0, manaMax = 0 }),
    name .. ' rejected a Min HP-only trigger')
  expect(pageModule.isValidEquipmentEntry({ item = 3051, min = 0, max = 80, manaMin = 0, manaMax = 0 }),
    name .. ' rejected a Max HP-only trigger')
  expect(pageModule.isValidEquipmentEntry({ item = 3051, min = 0, max = 0, manaMin = 20, manaMax = 0 }),
    name .. ' rejected a Min MP-only trigger')
  expect(pageModule.isValidEquipmentEntry({ item = 3051, min = 0, max = 0, manaMin = 0, manaMax = 80 }),
    name .. ' rejected a Max MP-only trigger')
  expect(not pageModule.isValidEquipmentEntry({ item = 3051, min = 0, max = 0, manaMin = 0, manaMax = 0 }),
    name .. ' accepted an entry without any trigger range')
  local ignoreWidget = {}
  expect(pageModule.bindIgnoreEntryRemoval(ignoreWidget) and
    type(ignoreWidget.onMousePress) == 'function',
    name .. ' did not attach removal to the newly created Ignore entry')
end

modules.game_minibot.onMiniBotGameWindowChangeFromPanel = function(widgetId)
  if widgetId == 'huntingExplorer_gamewindow' then
    modules.game_minibot.explorerHotkeyCalls = (modules.game_minibot.explorerHotkeyCalls or 0) + 1
  elseif widgetId == 'tankMode_gamewindow' then
    modules.game_minibot.tankHotkeyCalls = (modules.game_minibot.tankHotkeyCalls or 0) + 1
  else
    error('Assistant hotkey toggled the wrong shortcut: ' .. tostring(widgetId))
  end
end
dofile(clientRoot .. '/modules/corelib/keybinds.lua')
local explorerBind = KeyBinds.Hotkeys.Assistant['Hunting Explorer Toggle']
expect(explorerBind ~= nil and explorerBind.jsonName == 'assistantHuntingExplorerToggle',
  'Explorer action is missing from the Assistant hotkey registry')
canPerformAction = function()
  return true
end
explorerBind.bindKeyDown()
expect(modules.game_minibot.explorerHotkeyCalls == 1,
  'Explorer hotkey action did not reach the MiniBot shortcut handler')
local tankBind = KeyBinds.Hotkeys.Assistant['Tank Mode Toggle']
expect(tankBind ~= nil and tankBind.jsonName == 'assistantTankModeToggle',
  'Tank Mode action is missing from the Assistant hotkey registry')
tankBind.bindKeyDown()
expect(modules.game_minibot.tankHotkeyCalls == 1,
  'Tank Mode hotkey action did not reach the MiniBot shortcut handler')

Options = {
  array = {
    controlButtonsOptions = { enabledButtons = {}, disabledButtons = {} },
    hotkeyOptions = {
      hotkeySets = {
        Legacy = {
          chatOff = { {
            actionsetting = { action = 'HelperHuntingExplorerToggle' },
            keysequence = 'Alt+X'
          } },
          chatOn = {}
        },
        Conflict = {
          chatOff = { {
            actionsetting = { action = 'SomeOtherAction' },
            keysequence = 'Ctrl+Shift+E'
          } },
          chatOn = { {
            actionsetting = { action = 'assistantHuntingExplorerToggle' },
            keysequence = 'Alt+Shift+E'
          } }
        }
      }
    }
  }
}
dofile(clientRoot .. '/modules/client_options/options.lua')
expect(Options.migrateRetiredAssistantSettings(), 'Explorer hotkey migration reported no changes')
expect(#Options.array.controlButtonsOptions.enabledButtons == 1 and
  Options.array.controlButtonsOptions.enabledButtons[1] == 'helperDialog' and
  #Options.array.controlButtonsOptions.disabledButtons == 0,
  'Assistant side button was not restored exactly once for migrated settings')
expect(Options.array.hotkeyOptions.hotkeySets.Legacy.chatOff[1].actionsetting.action ==
  'assistantHuntingExplorerToggle' and
  Options.array.hotkeyOptions.hotkeySets.Legacy.chatOff[1].keysequence == 'Alt+X',
  'legacy Explorer hotkey was not migrated while preserving its binding')
expect(#Options.array.hotkeyOptions.hotkeySets.Legacy.chatOn == 1 and
  Options.array.hotkeyOptions.hotkeySets.Legacy.chatOn[1].actionsetting.action ==
    'assistantHuntingExplorerToggle' and
  Options.array.hotkeyOptions.hotkeySets.Legacy.chatOn[1].keysequence == 'Ctrl+Shift+E',
  'missing Explorer binding did not receive its conflict-free default')
expect(#Options.array.hotkeyOptions.hotkeySets.Conflict.chatOff == 1 and
  Options.array.hotkeyOptions.hotkeySets.Conflict.chatOff[1].actionsetting.action == 'SomeOtherAction',
  'Explorer migration overwrote an existing Ctrl+Shift+E binding')
expect(#Options.array.hotkeyOptions.hotkeySets.Conflict.chatOn == 1,
  'Explorer migration duplicated an existing custom binding')

Options.array.controlButtonsOptions.enabledButtons = {}
Options.array.controlButtonsOptions.disabledButtons = { 'helperDialog' }
Options.migrateRetiredAssistantSettings()
expect(#Options.array.controlButtonsOptions.enabledButtons == 0 and
  #Options.array.controlButtonsOptions.disabledButtons == 1 and
  Options.array.controlButtonsOptions.disabledButtons[1] == 'helperDialog',
  'Assistant migration overrode the user-disabled side button choice')
Options.array.controlButtonsOptions.enabledButtons = { 'helperDialog', 'helperDialog' }
Options.array.controlButtonsOptions.disabledButtons = {}
Options.migrateRetiredAssistantSettings()
expect(#Options.array.controlButtonsOptions.enabledButtons == 1 and
  Options.array.controlButtonsOptions.enabledButtons[1] == 'helperDialog',
  'Assistant migration retained duplicate side buttons')

local assistantSideButtonToggles = 0
modules.game_minibot.toggle = function()
  assistantSideButtonToggles = assistantSideButtonToggles + 1
end
dofile(clientRoot .. '/modules/game_sidebuttons/sidebuttons.lua')
local helperParent = { getId = function() return 'helperDialog' end }
executeButtonFunctionality({ getParent = function() return helperParent end })
expect(assistantSideButtonToggles == 1,
  'helperDialog side button did not route to modules.game_minibot.toggle')

local lifecyclePages = {
  'combat_shooter', 'combat_timers', 'equipment_amulets', 'equipment_rings',
  'healing_group', 'healing_health', 'healing_mana'
}
for _, pageName in ipairs(lifecyclePages) do
  local pageFile = assert(io.open(
    clientRoot .. '/modules/game_minibot/pages/' .. pageName .. '.lua', 'rb'))
  local pageText = pageFile:read('*a')
  pageFile:close()
  local terminateStart = assert(pageText:find(
    'function ' .. pageName .. 'Module.terminate()', 1, true))
  local nextFunction = pageText:find('\nfunction ', terminateStart + 1, true) or (#pageText + 1)
  local terminateBody = pageText:sub(terminateStart, nextFunction - 1)
  expect(terminateBody:find(':destroy()', 1, true) == nil,
    pageName .. ' terminate still destroys page-owned rows before the parent')
end
local miniBotLifecycleFile = assert(io.open(
  clientRoot .. '/modules/game_minibot/minibot.lua', 'rb'))
local miniBotLifecycleText = miniBotLifecycleFile:read('*a')
miniBotLifecycleFile:close()
local presetStart = assert(miniBotLifecycleText:find('function onClickPresetEntry', 1, true))
local presetEnd = assert(miniBotLifecycleText:find('\nfunction ', presetStart + 1, true))
local presetBody = miniBotLifecycleText:sub(presetStart, presetEnd - 1)
expect(presetBody:find('loadMainPanel(MiniBotMiniWindow.selectedPage)', 1, true) ~= nil,
  'preset switching still re-initializes a stale page tree instead of rebuilding it')

local defaultsFile = assert(io.open(clientRoot .. '/data/json/default-options.json', 'rb'))
local defaultsText = defaultsFile:read('*a')
defaultsFile:close()
local _, explorerDefaultCount = defaultsText:gsub('"action"%s*:%s*"assistantHuntingExplorerToggle"', '')
expect(explorerDefaultCount == 12 and defaultsText:find('"clientOptionsVersion"%s*:%s*7') ~= nil,
  'default hotkey profiles do not all carry the versioned Explorer binding')
local _, assistantSideButtonDefaults = defaultsText:gsub('"helperDialog"', '')
expect(assistantSideButtonDefaults == 1,
  'default options do not enable exactly one Assistant side button')

print('minibot config hardening smoke: OK')
