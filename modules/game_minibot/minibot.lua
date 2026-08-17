MiniBotMiniWindow           = nil
MiniBotMiniWindowDialog     = nil
MiniBotEditPresetMiniWindow = nil
MiniBotImportPresetMiniWindow = nil
MiniBotGameWindowPanel      = nil
MiniBotToggleButton         = nil

local miniBotversionStr = "1.2.2 Beta"
-- How to set value:
--  000: First three numbers pack is major version
--  000: Second three numbers pack is minor version
--  000: Third three numbers pack is lesser version, used for hotfix
local miniBotVersion = 1002002
local moduleInitialized = false
local signalsConnected = false
local gameSessionStarted = false
local activePageRunning = false
local activePageSessionReady = false
local activePageModule = nil
local reloadGeneration = 0
local activePageGeneration = 0
local deferredPageActions = {}
local deferredPageMethods = {}
local unpackArguments = unpack or table.unpack

local configLimits = {
  maxDepth = 16,
  maxNodes = 20000,
  maxTableEntries = 4096,
  maxCollectionEntries = 256,
  maxListEntries = 512,
  maxWaypoints = 4096,
  maxStringLength = 65536,
  maxNameLength = 128,
  maxKeyLength = 256,
  maxUid = 2147483647,
  maxImportLength = 1024 * 1024
}

local presetObjectRoots = {
  'shortcuts', 'combat_attack', 'combat_shooter', 'combat_timers',
  'equipment_amulets', 'equipment_rings', 'healing_health',
  'healing_mana', 'healing_group', 'healing_groupParty',
  'healing_groupGuild', 'healing_groupTargets', 'support_main',
  'support_manashield', 'combat_pvp', 'explorer'
}

local presetListRoots = {
  'combat_shooter', 'combat_timers', 'equipment_amulets',
  'equipment_rings', 'healing_health', 'healing_mana',
  'healing_group', 'healing_groupParty', 'healing_groupGuild'
}

local presetNestedObjects = {
  combat_attack = { 'ammo_refill' },
  combat_pvp = { 'antiparalyze_settings' },
  support_main = { 'haste', 'change_gold', 'auto_eat', 'auto_training', 'auto_mount' },
  support_manashield = { 'spell_shield', 'item_shield', 'remove_shield' }
}

-- Page loaders compare and concatenate these values without defensive casts.
-- Keep the schema beside the storage boundary so neither persisted corruption
-- nor imported JSON can feed nil/wrongly typed leaves into those loaders.
local presetListEntrySchemas = {
  combat_shooter = {
    item = { kind = 'integer', default = 0 },
    spell = { kind = 'integer', default = 0 },
    health = { kind = 'number', default = 0 },
    mana = { kind = 'number', default = 0 },
    reqmana = { kind = 'number', default = 0 },
    hits = { kind = 'number', default = 1 },
    -- The donor save routine omits max, while its loader treats zero as a
    -- phantom entry. One is therefore the compatible neutral legacy value.
    max = { kind = 'number', default = 1 },
    harmony = { kind = 'number', default = 0 },
    extended = { kind = 'boolean', default = false },
    smart = { kind = 'boolean', default = true },
    ignorePz = { kind = 'boolean', default = true },
    enabled = { kind = 'boolean', default = false }
  },
  combat_timers = {
    item = { kind = 'integer', default = 0 },
    spell = { kind = 'integer', default = 0 },
    reqmana = { kind = 'number', default = 0 },
    min = { kind = 'number', default = 0 },
    max = { kind = 'number', default = 1 },
    manaMin = { kind = 'number', default = 0 },
    manaMax = { kind = 'number', default = 0 },
    hits = { kind = 'number', default = 0 },
    hitsMax = { kind = 'number', default = 0 },
    harmony = { kind = 'number', default = 0 },
    ignorePz = { kind = 'boolean', default = false },
    enabled = { kind = 'boolean', default = false }
  },
  equipment_amulets = {
    item = { kind = 'integer', default = 0 },
    spell = { kind = 'integer', default = 0 },
    reqmana = { kind = 'number', default = 0 },
    min = { kind = 'number', default = 0 },
    max = { kind = 'number', default = 0 },
    manaMin = { kind = 'number', default = 0 },
    manaMax = { kind = 'number', default = 0 },
    harmony = { kind = 'number', default = 0 },
    unequip = { kind = 'boolean', default = false },
    enabled = { kind = 'boolean', default = false },
    ignore_enabled = { kind = 'boolean', default = false },
    ignore = { kind = 'itemList', default = {} }
  },
  equipment_rings = {
    item = { kind = 'integer', default = 0 },
    spell = { kind = 'integer', default = 0 },
    reqmana = { kind = 'number', default = 0 },
    min = { kind = 'number', default = 0 },
    max = { kind = 'number', default = 0 },
    manaMin = { kind = 'number', default = 0 },
    manaMax = { kind = 'number', default = 0 },
    harmony = { kind = 'number', default = 0 },
    unequip = { kind = 'boolean', default = false },
    enabled = { kind = 'boolean', default = false },
    ignore_enabled = { kind = 'boolean', default = false },
    ignore = { kind = 'itemList', default = {} }
  },
  healing_health = {
    item = { kind = 'integer', default = 0 },
    spell = { kind = 'integer', default = 0 },
    reqmana = { kind = 'number', default = 0 },
    min = { kind = 'number', default = 0 },
    max = { kind = 'number', default = 0 },
    manaMin = { kind = 'number', default = 0 },
    manaMax = { kind = 'number', default = 0 },
    harmony = { kind = 'number', default = 0 },
    enabled = { kind = 'boolean', default = false }
  },
  healing_mana = {
    item = { kind = 'integer', default = 0 },
    spell = { kind = 'integer', default = 0 },
    reqmana = { kind = 'number', default = 0 },
    min = { kind = 'number', default = 0 },
    max = { kind = 'number', default = 0 },
    manaMin = { kind = 'number', default = 0 },
    manaMax = { kind = 'number', default = 0 },
    harmony = { kind = 'number', default = 0 },
    enabled = { kind = 'boolean', default = false }
  },
  healing_group = {
    target = { kind = 'string', default = '' },
    item = { kind = 'integer', default = 0 },
    spell = { kind = 'integer', default = 0 },
    reqmana = { kind = 'number', default = 0 },
    min = { kind = 'number', default = 0 },
    max = { kind = 'number', default = 0 },
    manaMin = { kind = 'number', default = 0 },
    manaMax = { kind = 'number', default = 0 },
    enabled = { kind = 'boolean', default = false },
    area = { kind = 'string', default = '' }
  },
  spells = {
    id = { kind = 'integer', minimum = 1, default = 1 },
    priority = { kind = 'integer', minimum = 1, maximum = 5, default = 1 }
  }
}
presetListEntrySchemas.healing_groupParty = presetListEntrySchemas.healing_group
presetListEntrySchemas.healing_groupGuild = presetListEntrySchemas.healing_group

local presetObjectLeafSchemas = {
  shortcuts = {
    shooter_enabled = { kind = 'boolean', default = false },
    healingHealth_enabled = { kind = 'boolean', default = false },
    healingMana_enabled = { kind = 'boolean', default = false },
    healingGroup_enabled = { kind = 'boolean', default = false },
    combatTimers_enabled = { kind = 'boolean', default = false },
    supportHaste_enabled = { kind = 'boolean', default = false },
    autoAttack_enabled = { kind = 'boolean', default = false },
    equipmentAmulet_enabled = { kind = 'boolean', default = false },
    equipmentRing_enabled = { kind = 'boolean', default = false },
    huntingRecorder_enabled = { kind = 'boolean', default = false },
    huntingRecorderTimer_enabled = { kind = 'boolean', default = false },
    huntingExplorer_enabled = { kind = 'boolean', default = false },
    tankMode_enabled = { kind = 'boolean', default = false }
  },
  combat_attack = {
    attackMelee_enabled = { kind = 'boolean', default = false },
    autoAttack_health = { kind = 'boolean', default = false },
    autoAttack_highhealth = { kind = 'boolean', default = false },
    autoAttack_closest = { kind = 'boolean', default = false },
    autoAttack_smartArrow = { kind = 'boolean', default = false }
  },
  explorer = {
    lure = { kind = 'boolean', default = true },
    stop = { kind = 'boolean', default = false },
    lure_until = { kind = 'numericString', default = '' },
    lure_resume = { kind = 'numericString', default = '' },
    stop_until = { kind = 'numericString', default = '' },
    stop_resume = { kind = 'numericString', default = '' }
  }
}

local presetNestedLeafSchemas = {
  combat_attack = {
    ammo_refill = {
      item = { kind = 'integer', default = 0 },
      enabled = { kind = 'boolean', default = false }
    }
  },
  combat_pvp = {
    antiparalyze_settings = {
      enabled = { kind = 'boolean', default = false }
    }
  },
  support_main = {
    haste = {
      spell = { kind = 'integer', default = 0 },
      reqmana = { kind = 'number', default = 0 },
      enabled = { kind = 'boolean', default = false },
      ignorePz = { kind = 'boolean', default = false }
    },
    change_gold = {
      enabled = { kind = 'boolean', default = false }
    },
    auto_eat = {
      item = { kind = 'integer', default = 0 },
      enabled = { kind = 'boolean', default = false }
    },
    auto_training = {
      item1 = { kind = 'integer', default = 0 },
      item2 = { kind = 'integer', default = 0 },
      enabled = { kind = 'boolean', default = false }
    },
    auto_mount = {
      enabled = { kind = 'boolean', default = false }
    }
  },
  support_manashield = {
    spell_shield = {
      enabled = { kind = 'boolean', default = false },
      health = { kind = 'number', default = 0 },
      use_potion = { kind = 'boolean', default = false },
      creatures_enabled = { kind = 'boolean', default = false },
      creatures_value = { kind = 'number', default = 0 },
      recast_enabled = { kind = 'boolean', default = false },
      recast_value = { kind = 'number', default = 0 }
    },
    item_shield = {
      enabled = { kind = 'boolean', default = false },
      health = { kind = 'number', default = 0 },
      use_fear = { kind = 'boolean', default = false },
      creatures_enabled = { kind = 'boolean', default = false },
      creatures_value = { kind = 'number', default = 0 },
      recast_enabled = { kind = 'boolean', default = false },
      recast_value = { kind = 'number', default = 0 }
    },
    remove_shield = {
      enabled = { kind = 'boolean', default = false },
      health = { kind = 'number', default = 0 },
      ignore_fear = { kind = 'boolean', default = false },
      creatures_enabled = { kind = 'boolean', default = false },
      creatures_value = { kind = 'number', default = 0 }
    }
  }
}

local characterBooleanSettings = {
  'show_preset_name', 'autoAttack_gamewindow', 'shooter_gamewindow',
  'combatTimer_gamewindow', 'panel_gamewindow', 'healingHealth_gamewindow',
  'healingMana_gamewindow', 'healingGroup_gamewindow', 'supportHaste_gamewindow',
  'equipmentAmulet_gamewindow', 'equipmentRing_gamewindow',
  'huntingRecorder_gamewindow', 'huntingRecorderTimer_gamewindow',
  'tankMode_gamewindow', 'huntingExplorer_gamewindow'
}

local function isFiniteNumber(value)
  return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

local function isPositiveInteger(value)
  return isFiniteNumber(value) and value > 0 and value <= configLimits.maxUid and value == math.floor(value)
end

local function isValidName(value)
  return type(value) == 'string' and #value > 0 and #value <= configLimits.maxNameLength
end

local function cloneSchemaDefault(value)
  if type(value) ~= 'table' then
    return value
  end
  local copy = {}
  for key, child in pairs(value) do
    copy[key] = cloneSchemaDefault(child)
  end
  return copy
end

local function invalidLeaf(rule, strict, path, reason)
  if strict then
    return nil, path .. ' ' .. reason, false
  end
  return cloneSchemaDefault(rule.default), nil, true
end

local function normalizeSchemaLeaf(value, rule, strict, path)
  if value == nil then
    return cloneSchemaDefault(rule.default), nil, true
  end

  if rule.kind == 'boolean' then
    if type(value) ~= 'boolean' then
      return invalidLeaf(rule, strict, path, 'must be a boolean')
    end
    return value, nil, false
  elseif rule.kind == 'string' then
    if type(value) ~= 'string' or #value > configLimits.maxNameLength then
      return invalidLeaf(rule, strict, path, 'must be a bounded string')
    end
    return value, nil, false
  elseif rule.kind == 'numericString' then
    if type(value) == 'number' and isFiniteNumber(value) and value >= 0 and not strict then
      if value > (rule.maximum or configLimits.maxUid) then
        return invalidLeaf(rule, strict, path, 'exceeds the safe numeric limit')
      end
      return tostring(value), nil, true
    end
    local numeric = type(value) == 'string' and value ~= '' and tonumber(value) or nil
    if type(value) ~= 'string' or #value > configLimits.maxNameLength or
        (value ~= '' and (not isFiniteNumber(numeric) or numeric < 0 or
          numeric > (rule.maximum or configLimits.maxUid))) then
      return invalidLeaf(rule, strict, path, 'must be an empty or non-negative numeric string')
    end
    return value, nil, false
  elseif rule.kind == 'number' or rule.kind == 'integer' then
    local minimum = rule.minimum or 0
    local maximum = rule.maximum or configLimits.maxUid
    local valid = isFiniteNumber(value) and value >= minimum and value <= maximum
    if rule.kind == 'integer' then
      valid = valid and value == math.floor(value)
    end
    if not valid then
      return invalidLeaf(rule, strict, path, 'must be a non-negative ' .. rule.kind)
    end
    return value, nil, false
  elseif rule.kind == 'itemList' then
    if type(value) ~= 'table' then
      return invalidLeaf(rule, strict, path, 'must be a table')
    end

    local normalized = {}
    local count = 0
    local changed = false
    for key, itemId in pairs(value) do
      count = count + 1
      if count > configLimits.maxListEntries then
        if strict then
          return nil, path .. ' exceeds the entry limit', false
        end
        changed = true
        break
      end
      local validKey = type(key) == 'number' and key >= 1 and key == math.floor(key)
      local validItem = isFiniteNumber(itemId) and itemId > 0 and
        itemId == math.floor(itemId) and itemId <= configLimits.maxUid
      if not validKey or not validItem then
        if strict then
          return nil, path .. ' contains an invalid item id', false
        end
        changed = true
      else
        table.insert(normalized, itemId)
        if key ~= #normalized then
          changed = true
        end
      end
    end
    if count ~= #normalized then
      changed = true
    end
    return normalized, nil, changed
  end

  return invalidLeaf(rule, strict, path, 'has an unknown schema type')
end

local function normalizePresetListEntry(root, entry, strict)
  local schema = presetListEntrySchemas[root]
  if schema == nil then
    return entry, nil, false
  end

  local changed = false
  if root == 'combat_shooter' and entry.smart == nil then
    -- Before this port the Smart checkbox was serialized under ignorePz.
    -- Preserve those donor presets once, then keep both concerns independent.
    entry.smart = type(entry.ignorePz) == 'boolean' and entry.ignorePz or true
    changed = true
  end
  for field, rule in pairs(schema) do
    local normalized, err, repaired = normalizeSchemaLeaf(entry[field], rule, strict, root .. '.' .. field)
    if err ~= nil then
      return nil, err, false
    end
    if repaired or normalized ~= entry[field] then
      entry[field] = normalized
      changed = true
    end
  end
  return entry, nil, changed
end

local function normalizeObjectLeafSchema(object, schema, strict, path)
  local changed = false
  for field, rule in pairs(schema) do
    local normalized, err, repaired = normalizeSchemaLeaf(object[field], rule, strict, path .. '.' .. field)
    if err ~= nil then
      return false, err, false
    end
    if repaired or normalized ~= object[field] then
      object[field] = normalized
      changed = true
    end
  end
  return true, nil, changed
end

local function normalizePresetObjectLeaves(entry, strict)
  local changed = false
  for root, schema in pairs(presetObjectLeafSchemas) do
    local object = entry[root]
    if type(object) == 'table' then
      local ok, err, repaired = normalizeObjectLeafSchema(object, schema, strict, root)
      if not ok then
        return false, err, false
      end
      changed = changed or repaired
    end
  end

  for root, nestedSchemas in pairs(presetNestedLeafSchemas) do
    local object = entry[root]
    if type(object) == 'table' then
      for nestedKey, schema in pairs(nestedSchemas) do
        local nestedObject = object[nestedKey]
        if type(nestedObject) == 'table' then
          local ok, err, repaired = normalizeObjectLeafSchema(
            nestedObject, schema, strict, root .. '.' .. nestedKey)
          if not ok then
            return false, err, false
          end
          changed = changed or repaired
        end
      end
    end
  end

  if entry.healing_groupType ~= nil and
      entry.healing_groupType ~= 'custom' and entry.healing_groupType ~= 'party' and
      entry.healing_groupType ~= 'guild' then
    if strict then
      return false, 'healing_groupType must be custom, party or guild', false
    end
    entry.healing_groupType = 'custom'
    changed = true
  end
  return true, nil, changed
end

local function currentCharacterName()
  if g_game == nil or type(g_game.getCharacterName) ~= 'function' then
    return nil
  end
  local name = g_game.getCharacterName()
  if type(name) ~= 'string' or name == '' then
    return nil
  end
  return name
end

local function cloneSafeConfigValue(value, repair, state, depth)
  local valueType = type(value)
  if valueType == 'nil' or valueType == 'boolean' then
    return value
  elseif valueType == 'number' then
    if not isFiniteNumber(value) then
      return nil, 'non-finite number'
    end
    return value
  elseif valueType == 'string' then
    if #value > configLimits.maxStringLength then
      return nil, 'string exceeds the configuration limit'
    end
    return value
  elseif valueType ~= 'table' then
    return nil, 'unsupported value type: ' .. valueType
  end

  state = state or { active = {}, nodes = 0, changed = false }
  depth = depth or 0
  if depth > configLimits.maxDepth then
    return nil, 'configuration exceeds the maximum depth'
  end
  if state.active[value] then
    return nil, 'cyclic table'
  end

  state.nodes = state.nodes + 1
  if state.nodes > configLimits.maxNodes then
    return nil, 'configuration exceeds the maximum size'
  end

  if getmetatable(value) ~= nil then
    if not repair then
      return nil, 'tables with metatables are not accepted'
    end
    state.changed = true
  end

  state.active[value] = true
  local result = {}
  local entryCount = 0
  for key, child in pairs(value) do
    entryCount = entryCount + 1
    if entryCount > configLimits.maxTableEntries then
      if not repair then
        state.active[value] = nil
        return nil, 'table exceeds the entry limit'
      end
      state.changed = true
      break
    end

    local keyType = type(key)
    local validKey = (keyType == 'string' and #key <= configLimits.maxKeyLength) or
      (keyType == 'number' and isFiniteNumber(key))
    if not validKey then
      if not repair then
        state.active[value] = nil
        return nil, 'invalid table key'
      end
      state.changed = true
    else
      local clonedChild, childError = cloneSafeConfigValue(child, repair, state, depth + 1)
      if childError ~= nil then
        if not repair then
          state.active[value] = nil
          return nil, childError
        end
        state.changed = true
      else
        result[key] = clonedChild
      end
    end
  end
  state.active[value] = nil
  return result, nil, state.changed
end

local function repairOrRejectObject(container, key, strict)
  local value = container[key]
  if value == nil or type(value) == 'table' then
    return true, nil, false
  end
  if strict then
    return false, key .. ' must be a table', false
  end
  container[key] = {}
  return true, nil, true
end

local function normalizePriorityList(container, key, strict)
  local list = container[key]
  if list == nil then
    return true, nil, false
  end
  if type(list) ~= 'table' then
    if strict then
      return false, key .. ' must be a table', false
    end
    container[key] = {}
    return true, nil, true
  end

  local records = {}
  local changed = false
  local total = 0
  for listKey, entry in pairs(list) do
    total = total + 1
    if total > configLimits.maxListEntries then
      if strict then
        return false, key .. ' exceeds the list limit', false
      end
      changed = true
      break
    end

    if type(entry) ~= 'table' or not isFiniteNumber(entry.priority) then
      if strict then
        return false, key .. ' contains an invalid priority entry', false
      end
      changed = true
    else
      local normalizedEntry, entryError, entryChanged = normalizePresetListEntry(key, entry, strict)
      if normalizedEntry == nil then
        if strict then
          return false, entryError, false
        end
        changed = true
      else
        table.insert(records, { value = normalizedEntry, priority = normalizedEntry.priority, order = total })
        changed = changed or entryChanged
      end
      if type(listKey) ~= 'number' or listKey ~= math.floor(listKey) or listKey < 1 then
        changed = true
      end
    end
  end

  table.sort(records, function(first, second)
    if first.priority == second.priority then
      return first.order < second.order
    end
    return first.priority < second.priority
  end)

  local normalized = {}
  for index, record in ipairs(records) do
    normalized[index] = record.value
    if list[index] ~= record.value then
      changed = true
    end
  end
  if total ~= #records then
    changed = true
  end
  container[key] = normalized
  return true, nil, changed
end

local function normalizeHealingTargets(entry, strict)
  local targets = entry.healing_groupTargets
  if targets == nil then
    return true, nil, false
  end

  local changed = false
  for _, targetType in ipairs({ 'custom', 'party', 'guild' }) do
    local blocks = targets[targetType]
    if blocks ~= nil then
      if type(blocks) ~= 'table' then
        if strict then
          return false, 'healing_groupTargets.' .. targetType .. ' must be a table', false
        end
        targets[targetType] = {}
        changed = true
      else
        local normalized = {}
        local count = 0
        for target, block in pairs(blocks) do
          count = count + 1
          if count > configLimits.maxListEntries then
            if strict then
              return false, 'healing_groupTargets.' .. targetType .. ' exceeds the entry limit', false
            end
            changed = true
            break
          end
          if type(block) ~= 'table' then
            if strict then
              return false, 'healing_groupTargets.' .. targetType .. ' contains a non-table block', false
            end
            changed = true
          else
            local ok, blockError, blockChanged = normalizeObjectLeafSchema(block, {
              enabled = { kind = 'boolean', default = false }
            }, strict, 'healing_groupTargets.' .. targetType .. '.' .. tostring(target))
            if not ok then
              return false, blockError, false
            end
            normalized[target] = block
            changed = changed or blockChanged
          end
        end
        targets[targetType] = normalized
      end
    end
  end
  return true, nil, changed
end

local function normalizeAntiParalyzeSettings(entry, strict)
  local pvp = entry.combat_pvp
  local settings = type(pvp) == 'table' and pvp.antiparalyze_settings or nil
  if type(settings) ~= 'table' then
    return true, nil, false
  end

  local ok, err, changed = normalizePriorityList(settings, 'spells', strict)
  if not ok then
    return false, 'combat_pvp.antiparalyze_settings.' .. err, false
  end

  local spells = settings.spells
  if type(spells) ~= 'table' then
    return true, nil, changed
  end
  if #spells > 5 then
    if strict then
      return false, 'combat_pvp.antiparalyze_settings.spells exceeds 5 entries', false
    end
    for index = #spells, 6, -1 do
      table.remove(spells, index)
    end
    changed = true
  end

  local seen = {}
  local normalized = {}
  for _, block in ipairs(spells) do
    if not seen[block.id] then
      seen[block.id] = true
      local priority = #normalized + 1
      if block.priority ~= priority then
        block.priority = priority
        changed = true
      end
      table.insert(normalized, block)
    elseif strict then
      return false, 'combat_pvp.antiparalyze_settings.spells contains a duplicate spell', false
    else
      changed = true
    end
  end
  if #normalized ~= #spells then
    settings.spells = normalized
  end
  return true, nil, changed
end

local function normalizePresetEntry(entry, strict, fallbackUid)
  if type(entry) ~= 'table' then
    return nil, 'preset entry must be a table', false
  end

  local changed = false
  if not isPositiveInteger(entry.uid) then
    if strict or not isPositiveInteger(fallbackUid) then
      return nil, 'preset uid must be a positive integer', false
    end
    entry.uid = fallbackUid
    changed = true
  end
  if not isValidName(entry.name) then
    if strict then
      return nil, 'preset name must be a non-empty string', false
    end
    entry.name = 'Preset #' .. entry.uid
    changed = true
  end
  if not isFiniteNumber(entry.creation) then
    if strict then
      return nil, 'preset creation must be finite', false
    end
    entry.creation = os.time()
    changed = true
  end

  for _, root in ipairs(presetObjectRoots) do
    local ok, err, repaired = repairOrRejectObject(entry, root, strict)
    if not ok then
      return nil, err, false
    end
    changed = changed or repaired
  end

  for root, nestedKeys in pairs(presetNestedObjects) do
    local object = entry[root]
    if object ~= nil then
      for _, nestedKey in ipairs(nestedKeys) do
        local ok, err, repaired = repairOrRejectObject(object, nestedKey, strict)
        if not ok then
          return nil, root .. '.' .. err, false
        end
        changed = changed or repaired
      end
    end
  end

  local objectLeavesOk, objectLeavesError, objectLeavesRepaired = normalizePresetObjectLeaves(entry, strict)
  if not objectLeavesOk then
    return nil, objectLeavesError, false
  end
  changed = changed or objectLeavesRepaired

  local ok, err, repaired = normalizeHealingTargets(entry, strict)
  if not ok then
    return nil, err, false
  end
  changed = changed or repaired

  ok, err, repaired = normalizeAntiParalyzeSettings(entry, strict)
  if not ok then
    return nil, err, false
  end
  changed = changed or repaired

  for _, root in ipairs(presetListRoots) do
    ok, err, repaired = normalizePriorityList(entry, root, strict)
    if not ok then
      return nil, err, false
    end
    changed = changed or repaired
  end
  return entry, nil, changed
end

local function normalizeSessionEntry(entry, strict, fallbackUid)
  if type(entry) ~= 'table' then
    return nil, 'session entry must be a table', false
  end

  local changed = false
  if not isPositiveInteger(entry.uid) then
    if strict or not isPositiveInteger(fallbackUid) then
      return nil, 'session uid must be a positive integer', false
    end
    entry.uid = fallbackUid
    changed = true
  end
  if not isValidName(entry.name) then
    if strict then
      return nil, 'session name must be a non-empty string', false
    end
    entry.name = 'Session #' .. entry.uid
    changed = true
  end
  if not isFiniteNumber(entry.creation) then
    if strict then
      return nil, 'session creation must be finite', false
    end
    entry.creation = os.time()
    changed = true
  end
  return entry, nil, changed
end

local function normalizeWaypoints(container, strict, required)
  local waypoints = container.waypoints
  if waypoints == nil then
    if strict and required then
      return false, 'waypoints are required', false
    end
    container.waypoints = {}
    return true, nil, true
  end
  if type(waypoints) ~= 'table' then
    if strict then
      return false, 'waypoints must be a table', false
    end
    container.waypoints = {}
    return true, nil, true
  end

  local records = {}
  local changed = false
  local total = 0
  for waypointKey, waypoint in pairs(waypoints) do
    total = total + 1
    if total > configLimits.maxWaypoints then
      if strict then
        return false, 'waypoints exceed the entry limit', false
      end
      changed = true
      break
    end

    local position = type(waypoint) == 'table' and waypoint.position or nil
    local valid = type(waypoint) == 'table' and type(position) == 'table' and
      isFiniteNumber(position.x) and position.x >= 0 and position.x <= 65535 and position.x == math.floor(position.x) and
      isFiniteNumber(position.y) and position.y >= 0 and position.y <= 65535 and position.y == math.floor(position.y) and
      isFiniteNumber(position.z) and position.z >= 0 and position.z <= 15 and position.z == math.floor(position.z) and
      isPositiveInteger(waypoint.index) and waypoint.index <= configLimits.maxWaypoints
    if not valid then
      if strict then
        return false, 'waypoint position and index must be finite', false
      end
      changed = true
    else
      local ok, waypointError, waypointChanged = normalizeObjectLeafSchema(waypoint, {
        creatures = { kind = 'number', default = 0 },
        resume = { kind = 'number', default = 0 },
        lure = { kind = 'boolean', default = false },
        speed = { kind = 'number', default = 5, minimum = 1, maximum = 20 },
        teleport = { kind = 'boolean', default = false }
      }, strict, 'waypoint')
      if not ok then
        if strict then
          return false, waypointError, false
        end
        changed = true
      else
        table.insert(records, { value = waypoint, index = waypoint.index, order = total })
        changed = changed or waypointChanged
        if type(waypointKey) ~= 'number' or waypointKey ~= math.floor(waypointKey) or waypointKey < 1 then
          changed = true
        end
      end
    end
  end

  table.sort(records, function(first, second)
    if first.index == second.index then
      return first.order < second.order
    end
    return first.index < second.index
  end)
  local normalized = {}
  for index, record in ipairs(records) do
    normalized[index] = record.value
    if waypoints[index] ~= record.value then
      changed = true
    end
  end
  if total ~= #records then
    changed = true
  end
  container.waypoints = normalized
  return true, nil, changed
end

local function normalizeCollection(settings, key, entryNormalizer)
  local source = settings[key]
  if type(source) ~= 'table' then
    settings[key] = {}
    return {}, true, 0
  end

  local normalized = {}
  local changed = false
  local maxUid = 0
  local total = 0
  for sourceKey, sourceEntry in pairs(source) do
    total = total + 1
    if total > configLimits.maxCollectionEntries then
      changed = true
      break
    end

    local fallbackUid = tonumber(sourceKey)
    local entry, _, repaired = entryNormalizer(sourceEntry, false, fallbackUid)
    if entry == nil or normalized[tostring(entry.uid)] ~= nil then
      changed = true
    else
      local targetKey = tostring(entry.uid)
      normalized[targetKey] = entry
      maxUid = math.max(maxUid, entry.uid)
      if sourceKey ~= targetKey or source[targetKey] ~= entry then
        changed = true
      end
      changed = changed or repaired
    end
  end
  settings[key] = normalized
  return normalized, changed, maxUid
end

local function sanitizeCounter(settings, key, minimum)
  local value = settings[key]
  if not isFiniteNumber(value) or value < 0 or value ~= math.floor(value) or value > configLimits.maxUid then
    settings[key] = minimum
    return true
  end
  if value < minimum then
    settings[key] = minimum
    return true
  end
  return false
end

local function sanitizeStoredSettings(value, characterName)
  local changed = false
  local settings
  if type(value) ~= 'table' then
    settings = {}
    changed = true
  else
    local state = { active = {}, nodes = 0, changed = false }
    settings = cloneSafeConfigValue(value, true, state, 0)
    if settings == nil then
      settings = {}
      changed = true
    else
      changed = state.changed
    end
  end

  local presets, repaired, maxPresetUid = normalizeCollection(settings, 'presets', normalizePresetEntry)
  changed = changed or repaired
  local sessions, sessionsRepaired, maxSessionUid = normalizeCollection(settings, 'sessions', normalizeSessionEntry)
  changed = changed or sessionsRepaired

  local sessionSettingsSource = settings.sessions_settings
  if type(sessionSettingsSource) ~= 'table' then
    sessionSettingsSource = {}
    changed = true
  end
  local normalizedSessionSettings = {}
  local sourceCount = 0
  for _ in pairs(sessionSettingsSource) do
    sourceCount = sourceCount + 1
  end
  local normalizedCount = 0
  for sessionKey in pairs(sessions) do
    local sessionSettings = sessionSettingsSource[sessionKey] or sessionSettingsSource[tonumber(sessionKey)]
    if type(sessionSettings) ~= 'table' then
      sessionSettings = {}
      changed = true
    end
    local ok, _, waypointsRepaired = normalizeWaypoints(sessionSettings, false, false)
    if not ok then
      sessionSettings = { waypoints = {} }
      waypointsRepaired = true
    end
    normalizedSessionSettings[sessionKey] = sessionSettings
    normalizedCount = normalizedCount + 1
    changed = changed or waypointsRepaired or sessionSettingsSource[sessionKey] ~= sessionSettings
  end
  if sourceCount ~= normalizedCount then
    changed = true
  end
  settings.sessions_settings = normalizedSessionSettings

  changed = sanitizeCounter(settings, 'last_preset', maxPresetUid) or changed
  changed = sanitizeCounter(settings, 'last_session', maxSessionUid) or changed

  if settings.language ~= 'ptbr' and settings.language ~= 'enus' then
    settings.language = 'ptbr'
    changed = true
  end

  if type(characterName) == 'string' and characterName ~= '' then
    local characterSettings = settings[characterName]
    if type(characterSettings) ~= 'table' then
      characterSettings = {}
      settings[characterName] = characterSettings
      changed = true
    end
    for _, key in ipairs(characterBooleanSettings) do
      if type(characterSettings[key]) ~= 'boolean' then
        characterSettings[key] = false
        changed = true
      end
    end

    local selectedPreset = characterSettings.selected_preset
    if selectedPreset ~= nil and
        (not isPositiveInteger(selectedPreset) or presets[tostring(selectedPreset)] == nil) then
      characterSettings.selected_preset = nil
      changed = true
    end
    local selectedSession = characterSettings.selected_recordSession
    if selectedSession ~= nil and
        (not isPositiveInteger(selectedSession) or sessions[tostring(selectedSession)] == nil) then
      characterSettings.selected_recordSession = nil
      changed = true
    end
  end

  return settings, changed, presets
end

local function validatePresetImport(value)
  if type(value) ~= 'table' then
    return nil, 'preset import must decode to a table'
  end
  local clean, err = cloneSafeConfigValue(value, false, { active = {}, nodes = 0, changed = false }, 0)
  if clean == nil then
    return nil, err
  end
  if clean.DeusOT_Assistant_Preset_Export ~= true then
    return nil, 'invalid preset export marker'
  end
  if not isFiniteNumber(clean.version) or clean.version <= 0 then
    return nil, 'invalid preset export version'
  end
  local normalized, normalizeError = normalizePresetEntry(clean, true)
  if normalized == nil then
    return nil, normalizeError
  end
  return normalized
end

local function validateRecorderImport(value)
  if type(value) ~= 'table' then
    return nil, 'recorder import must decode to a table'
  end
  local clean, err = cloneSafeConfigValue(value, false, { active = {}, nodes = 0, changed = false }, 0)
  if clean == nil then
    return nil, err
  end
  if not isFiniteNumber(clean.version) or clean.version <= 0 then
    return nil, 'invalid recorder export version'
  end
  local normalized, normalizeError = normalizeSessionEntry(clean, true)
  if normalized == nil then
    return nil, normalizeError
  end
  local ok, waypointError = normalizeWaypoints(normalized, true, true)
  if not ok then
    return nil, waypointError
  end
  return normalized
end

-- Single validation entry point shared by storage recovery, both import paths,
-- and the isolated smoke test. Imports are strict; stored settings are repaired.
function validateMiniBotConfigurationData(value, kind, characterName)
  if kind == 'settings' then
    local settings, changed = sanitizeStoredSettings(value, characterName)
    return settings, nil, changed
  elseif kind == 'preset-import' then
    return validatePresetImport(value)
  elseif kind == 'recorder-import' then
    return validateRecorderImport(value)
  end
  return nil, 'unknown validation kind'
end

local function resourcesAreEncrypted()
  return g_resources ~= nil and type(g_resources.isEncrypted) == 'function' and
    g_resources.isEncrypted()
end

local _miniBotSettingsCache = nil
local function _loadMiniBotSettings()
  if _miniBotSettingsCache == nil then
    local node = g_settings.getNode('Minibot_Settings')
    local repairedNode, _, changed = validateMiniBotConfigurationData(node, 'settings', currentCharacterName())
    _miniBotSettingsCache = repairedNode
    if changed then
      g_settings.setNode('Minibot_Settings', _miniBotSettingsCache)
    end
  end
  return _miniBotSettingsCache
end

local function _saveMiniBotSettings()
  if _miniBotSettingsCache ~= nil then
    _miniBotSettingsCache = sanitizeStoredSettings(_miniBotSettingsCache, currentCharacterName())
    g_settings.setNode('Minibot_Settings', _miniBotSettingsCache)
  end
end

function getVersionStr()
  return miniBotversionStr
end

function resolveAutoAttackType(autoAttack, attackSettings)
  if autoAttack ~= true then
    return 0
  end
  attackSettings = type(attackSettings) == 'table' and attackSettings or {}

  local attackType = 1 -- closest/distance
  if attackSettings.autoAttack_smartArrow == true then
    attackType = 200
  elseif attackSettings.autoAttack_health == true then
    attackType = 2
  elseif attackSettings.autoAttack_highhealth == true then
    attackType = 3
  end
  if attackSettings.attackMelee_enabled == true then
    attackType = attackType + 100
  end
  return attackType
end

function disableMovementShortcut(settings, moduleType)
  if type(settings) ~= 'table' then
    return false
  end
  local shortcutKey
  local widgetId
  if moduleType == 5 then
    shortcutKey = 'huntingRecorder_enabled'
    widgetId = 'huntingRecorder_gamewindow'
  elseif moduleType == 21 then
    shortcutKey = 'huntingExplorer_enabled'
    widgetId = 'huntingExplorer_gamewindow'
  else
    return false
  end
  if type(settings.shortcuts) ~= 'table' then
    settings.shortcuts = {}
  end
  settings.shortcuts[shortcutKey] = false
  return true, widgetId
end

function syncDisabledMovementAutomationWidgets(moduleType)
  local widgetIds
  if moduleType == 5 then
    widgetIds = { 'huntingRecorder_gamewindow' }
  elseif moduleType == 21 then
    widgetIds = { 'huntingExplorer_gamewindow' }
  else
    widgetIds = {
      'huntingRecorder_gamewindow',
      'huntingExplorer_gamewindow'
    }
  end
  local panel = modules.game_interface ~= nil and
    type(modules.game_interface.getMiniBotPanel) == 'function' and
    modules.game_interface.getMiniBotPanel() or nil
  local pageModule = getPageModule()

  for _, widgetId in ipairs(widgetIds) do
    local panelWidget = panel ~= nil and panel:getChildById(widgetId) or nil
    if panelWidget ~= nil then
      panelWidget.ignoreCallback = true
      panelWidget:setChecked(false)
      panelWidget.ignoreCallback = nil
    end

    -- The movement page can be open even when its compact shortcut is hidden.
    -- Feed it a read-only unchecked widget so its own synchronization hook can
    -- update the page toggle without invoking an enabling callback.
    if pageModule ~= nil and type(pageModule.reloadEnabledShortcut) == 'function' then
      local uncheckedWidget = {
        getId = function()
          return widgetId
        end,
        isChecked = function()
          return false
        end
      }
      pageModule:reloadEnabledShortcut(uncheckedWidget)
    end
  end
  return true
end

function onMiniBotWalkFailed(code, moduleType)
  if moduleType ~= 5 and moduleType ~= 21 then
    return false
  end

  local settings = getPressetSettings()
  local changed, widgetId = disableMovementShortcut(settings, moduleType)
  if changed then
    setPressetSettings(settings)
  end
  g_minibot.setModuleToggle(moduleType, false)

  local panel = modules.game_interface ~= nil and
    type(modules.game_interface.getMiniBotPanel) == 'function' and
    modules.game_interface.getMiniBotPanel() or nil
  local panelWidget = panel ~= nil and panel:getChildById(widgetId) or nil
  if panelWidget ~= nil then
    panelWidget.ignoreCallback = true
    panelWidget:setChecked(false)
    panelWidget.ignoreCallback = nil
  end

  -- Explorer does not own a signal connection of its own; update its page
  -- when visible. Recorder already receives this same signal while active.
  local pageModule = getPageModule()
  if moduleType == 21 and pageModule ~= nil and pageModule.onWalkFailed ~= nil then
    pageModule.onWalkFailed(code)
  end
  return changed
end

local pages = {
  {
      name = 'Settings',
      identifier = 'settings',
      icon = '143 0 13 13',
      iconSize = '13 13',
      ui = 'main_settings',
      childs = {}
  },
  {
      name = 'Combat',
      identifier = 'combat',
      icon = '156 0 11 13',
      iconSize = '11 13',
      childs = {
        {
          name = 'Attack',
          identifier = 'combat_attack',
          icon = '0 0 11 10',
          iconSize = '11 10',
          ui = 'combat_attack',
          childs = {}
        },
        {
          name = 'Timers',
          identifier = 'combat_timers',
          icon = '169 0 8 13',
          iconSize = '8 13',
          ui = 'combat_timers',
          childs = {}
        },
        {
          name = 'Shooter',
          identifier = 'combat_shooter',
          icon = '130 0 11 12',
          iconSize = '11 12',
          ui = 'combat_shooter',
          childs = {}
        },
        {
          name = 'PvP',
          identifier = 'combat_pvp',
          icon = '403 0 13 13',
          iconSize = '13 13',
          ui = 'combat_pvp',
          childs = {}
        },
      }
  },
  {
      name = 'Equipment',
      identifier = 'equipment',
      icon = '312 0 11 10',
      iconSize = '11 10',
      childs = {
        {
          name = 'Amulets',
          identifier = 'equipment_amulets',
          icon = '325 0 13 13',
          iconSize = '13 13',
          ui = 'equipment_amulets',
          childs = {}
        },
        {
          name = 'Rings',
          identifier = 'equipment_rings',
          icon = '338 0 12 12',
          iconSize = '12 12',
          ui = 'equipment_rings',
          childs = {}
        },
      }
  },
  {
      name = 'Cave Bot',
      identifier = 'cavebot',
      icon = '195 0 10 10',
      iconSize = '10 10',
      childs = {
        {
          name = 'Recorder',
          icon = '429 0 13 13',
          identifier = 'hunting_recorder',
          iconSize = '13 13',
          ui = 'hunting_recorder',
          childs = {}
        },
        {
          name = 'Explorer',
          icon = '221 0 9 13',
          identifier = 'hunting_explorer',
          iconSize = '9 13',
          ui = 'hunting_explorer',
          childs = {}
        },
        --{
        --  name = 'Group Follow',
        --  icon = '221 0 9 13',
        --  iconSize = '9 13',
        --  ui = 'hunting_groupFollow',
        --  childs = {}
        --},
      }
  },
  {
      name = 'Healing',
      identifier = 'healing',
      icon = '13 0 12 12',
      iconSize = '12 12',
      childs = {
        {
            name = 'Health',
            identifier = 'healing_health',
            icon = '78 0 9 12',
            iconSize = '9 12',
            ui = 'healing_health'
        },
        {
            name = 'Mana',
            identifier = 'healing_mana',
            icon = '91 0 9 12',
            iconSize = '9 12',
            ui = 'healing_mana'
        },
        --{
        --    name = 'Conditions',
        --    icon = '299 0 12 9',
        --    iconSize = '12 9',
        --    ui = 'healing_conditions'
        --},
        {
            name = 'Group',
            identifier = 'healing_group',
            icon = '26 0 12 12',
            iconSize = '12 12',
            ui = 'healing_group'
        },
      }
  },
  --{
  --    name = 'Group Healing',
  --    icon = '26 0 12 12',
  --    iconSize = '12 12',
  --    ui = 'main_grouphealing',
  --    childs = {}
  --},
  --{
  --    name = 'Defense Fortify',
  --    icon = '39 0 8 12',
  --    iconSize = '8 12',
  --    ui = 'main_defense',
  --    childs = {}
  --},
  --{
  --    name = 'Strength',
  --    icon = '52 0 13 12',
  --    iconSize = '13 12',
  --    ui = 'main_fortify',
  --    childs = {}
  --},
  {
      name = 'Support',
      identifier = 'support',
      icon = '377 0 13 13',
      iconSize = '13 13',
      childs = {
        {
          name = 'General',
          identifier = 'support_general',
          icon = '65 0 10 10',
          iconSize = '10 10',
          ui = 'support_general',
          childs = {}
        },
        {
          name = 'Mana Shield',
          identifier = 'support_manashield',
          icon = '365 0 11 12',
          iconSize = '11 12',
          ui = 'support_manashield',
          childs = {}
        },
      }
  },
}

local widgetAlive

function getPageModule()
  if not widgetAlive(MiniBotMiniWindow) then
    return activePageModule
  end

  local ok, selectedPage = pcall(function()
    return MiniBotMiniWindow.selectedPage
  end)
  if not ok or selectedPage == nil or selectedPage == '' then
    return activePageModule
  end

  return modules.game_minibot[selectedPage .. 'Module']
end

widgetAlive = function(widget)
  if widget == nil then
    return false
  end

  if g_ui ~= nil and type(g_ui.isWidgetAlive) == 'function' then
    local ok, alive = pcall(g_ui.isWidgetAlive, widget)
    return ok and alive == true
  end

  local ok, destroyed = pcall(function()
    return widget:isDestroyed()
  end)
  return ok and not destroyed
end

local function destroyLiveWidget(widget)
  if widgetAlive(widget) then
    pcall(function()
      widget:destroy()
    end)
  end
end

local function closeDialogWindow(instance)
  local dialog = instance or MiniBotMiniWindowDialog
  if instance ~= nil and MiniBotMiniWindowDialog ~= instance then
    return false
  end
  if MiniBotMiniWindowDialog == dialog then
    MiniBotMiniWindowDialog = nil
  end
  destroyLiveWidget(dialog)
  return dialog ~= nil
end

local function closeEditPresetWindow(instance)
  local window = instance or MiniBotEditPresetMiniWindow
  if instance ~= nil and MiniBotEditPresetMiniWindow ~= instance then
    return false
  end
  if MiniBotEditPresetMiniWindow == window then
    MiniBotEditPresetMiniWindow = nil
  end
  destroyLiveWidget(window)
  return window ~= nil
end

local function closeImportPresetWindow(instance)
  local window = instance or MiniBotImportPresetMiniWindow
  if instance ~= nil and MiniBotImportPresetMiniWindow ~= instance then
    return false
  end
  if MiniBotImportPresetMiniWindow == window then
    MiniBotImportPresetMiniWindow = nil
  end
  destroyLiveWidget(window)
  return window ~= nil
end

local function showMiniBotWindow(focus)
  if not widgetAlive(MiniBotMiniWindow) then
    return false
  end
  MiniBotMiniWindow:show()
  if focus then
    MiniBotMiniWindow:focus()
  end
  return true
end

local function removeOwnedEvent(owner, field)
  if not widgetAlive(owner) then
    return false
  end
  local event = owner[field]
  if event ~= nil then
    removeEvent(event)
    if widgetAlive(owner) then
      owner[field] = nil
    end
  end
  return true
end

local function cancelWidgetEvents(widget)
  if not widgetAlive(widget) then
    return
  end
  for _, child in ipairs(widget:getChildren()) do
    cancelWidgetEvents(child)
  end
  removeOwnedEvent(widget, 'colorChangeEvent')
  removeOwnedEvent(widget, '_miniBotGifEvent')
  removeOwnedEvent(widget, '_miniBotDestroyEvent')
  removeOwnedEvent(widget, 'missileMoveEvent')
  removeOwnedEvent(widget, 'pulseEffect')
  removeOwnedEvent(widget, 'eventTicks')
end

local function cancelScheduledReloads()
  reloadGeneration = reloadGeneration + 1
  if not widgetAlive(MiniBotMiniWindow) then
    return
  end
  if MiniBotMiniWindow.refreshScheduled ~= nil then
    for _, event in ipairs(MiniBotMiniWindow.refreshScheduled) do
      removeEvent(event)
    end
    MiniBotMiniWindow.refreshScheduled = nil
  end
end

local function forgetDeferredPageAction(event)
  for index = #deferredPageActions, 1, -1 do
    if deferredPageActions[index] == event then
      table.remove(deferredPageActions, index)
      return
    end
  end
end

local function cancelDeferredPageActions(flushSave)
  local saveRecord = deferredPageMethods.saveSettings
  activePageGeneration = activePageGeneration + 1
  for _, event in ipairs(deferredPageActions) do
    pcall(removeEvent, event)
  end
  deferredPageActions = {}
  deferredPageMethods = {}

  if flushSave and saveRecord ~= nil and activePageRunning and
     saveRecord.pageModule == activePageModule and
     type(saveRecord.pageModule.saveSettings) == 'function' then
    local ok, err = pcall(saveRecord.pageModule.saveSettings,
        unpackArguments(saveRecord.arguments))
    if not ok then
      g_logger.error('[game_minibot] pending page save failed: ' .. tostring(err))
    end
  end
end

function deferMethod(method, ...)
  local pageModule = getPageModule()
  if pageModule == nil or type(pageModule[method]) ~= 'function' then
    return false
  end

  local generation = activePageGeneration
  local arguments = { ... }
  local pending = deferredPageMethods[method]
  if pending ~= nil and pending.generation == generation and
     pending.pageModule == pageModule then
    pending.arguments = arguments
    return true
  end

  local record = {
    generation = generation,
    pageModule = pageModule,
    arguments = arguments
  }
  local event
  event = addEvent(function()
    forgetDeferredPageAction(event)
    if deferredPageMethods[method] == record then
      deferredPageMethods[method] = nil
    end
    if generation ~= activePageGeneration or not moduleInitialized or
       not activePageRunning or getPageModule() ~= pageModule then
      return
    end

    for _, argument in ipairs(record.arguments) do
      if type(argument) == 'userdata' and not widgetAlive(argument) then
        return
      end
    end

    local ok, err = pcall(pageModule[method], unpackArguments(record.arguments))
    if not ok then
      g_logger.error('[game_minibot] deferred page action failed (' ..
          tostring(method) .. '): ' .. tostring(err))
    end
  end)
  if event ~= nil then
    record.event = event
    deferredPageMethods[method] = record
    table.insert(deferredPageActions, event)
    return true
  end
  return false
end

local function terminateActivePage()
  local rootAlive = widgetAlive(MiniBotMiniWindow)
  local main = rootAlive and MiniBotMiniWindow.main or nil
  local pageWidget = widgetAlive(main) and main:getChildByIndex(1) or nil
  cancelDeferredPageActions(widgetAlive(pageWidget))
  if not activePageRunning then
    return
  end
  if UIPopupMenu ~= nil and type(UIPopupMenu.closeCurrent) == 'function' then
    UIPopupMenu.closeCurrent()
  end
  activePageRunning = false
  activePageSessionReady = false
  -- Restore page-local bindings while every widget is still valid. Some page
  -- terminate hooks release dynamic children or auxiliary windows.
  MiniBotCompat.releaseWidgetTree(pageWidget)
  local pageModule = activePageModule or getPageModule()
  if pageModule ~= nil and pageModule.terminate ~= nil then
    local ok, err = pcall(pageModule.terminate)
    if not ok then
      g_logger.warning('[game_minibot] page terminate failed: ' .. tostring(err))
    end
  end
  activePageModule = nil
  local catcher = rootAlive and MiniBotMiniWindow.dropDownCatcher or nil
  if widgetAlive(catcher) then
    catcher:hide()
    catcher.onLeftClick = nil
  end
end

local function initializeActivePage()
  if activePageRunning or not widgetAlive(MiniBotMiniWindow) then
    return
  end
  local pageModule = getPageModule()
  local pageWidget = MiniBotMiniWindow.main and MiniBotMiniWindow.main:getChildByIndex(1) or nil
  if widgetAlive(pageWidget) then
    MiniBotCompat.prepareWidgetTree(pageWidget)
  end
  if pageModule ~= nil and pageModule.init ~= nil and widgetAlive(pageWidget) then
    pageModule.init(pageWidget)
    activePageModule = pageModule
    activePageRunning = true
    activePageSessionReady = gameSessionStarted and g_game.getLocalPlayer() ~= nil
  end
end

local function callRuntime(method)
  if MiniBotRuntime == nil or MiniBotRuntime[method] == nil then
    error('MiniBotRuntime.' .. method .. ' is unavailable')
  end
  MiniBotRuntime[method]()
end

local function lerp(a, b, t)
  return math.floor(a + (b - a) * t + 0.5)
end

local function interpolateColor(c1, c2, t)
  return {
    r = lerp(c1.r, c2.r, t),
    g = lerp(c1.g, c2.g, t),
    b = lerp(c1.b, c2.b, t)
  }
end

local function setPresetNameOnPanel()
  if not widgetAlive(MiniBotMiniWindow) then
    return
  end

  local presetsPanel = MiniBotMiniWindow.presets
  local presetList = presetsPanel and presetsPanel.list or nil
  if not widgetAlive(presetList) then
    return
  end

  local prefix = 'Current preset:'
  local language = modules.game_minibot.getSettingsValue(false, 'language', 'ptbr')
  if language == 'ptbr' then
    prefix = "Preset selecionado:"
  elseif language == 'enus' then
    prefix = 'Current preset:'
  end

  for _, c in ipairs(presetList:getChildren()) do
    if widgetAlive(c) and c.selectedPreset then
      MiniBotMiniWindow.presetName:setText(prefix .. ' \'' .. c:getText() .. '\'')
      break
    end
  end

  local gameWindowButton = presetsPanel.buttons and presetsPanel.buttons.gamewindow or nil
  if widgetAlive(gameWindowButton) then
    onGameWindowPresetnamgeChange(gameWindowButton, true)
  end
end

function internalAnimateWidgetExtension(widget, settings)
  local alive = widgetAlive(widget)
  if not moduleInitialized or not alive then
    if alive then
      widget.colorChangeEvent = nil
    end
    return
  end

  local t = settings.currentStep / settings.steps
  local color = interpolateColor(settings.fromColor, settings.toColor, t)
  local rgbColor = rgbToHex(color)
  if rgbColor ~= nil and widget.extended ~= nil then
    widget.extended:setColor(rgbToHex(color))
  end

  settings.currentStep = settings.currentStep + settings.direction

  if settings.currentStep >= settings.steps then
    settings.direction = -1
    settings.currentStep = settings.steps
  elseif settings.currentStep <= 0 then
    settings.direction = 1
    settings.currentStep = 0
  end

  widget.colorChangeEvent = scheduleEvent(function()
    internalAnimateWidgetExtension(widget, settings)
  end, settings.duration / settings.steps)
end

function minibotAnimateExtension(widget)
  removeOwnedEvent(widget, 'colorChangeEvent')
  local settings = {
    fromColor = { r = 0xc3, g = 0x65, b = 0x80 },
    toColor   = { r = 0x18, g = 0x72, b = 0xC3 },
    duration = 1000,
    steps = 30,
    direction = 1,
    currentStep = 0
  }

  internalAnimateWidgetExtension(widget, settings)
end

function selectMinibotPanel(primary, secondary)
  local widget = MiniBotMiniWindow.tabs:getChildById('TabButton_' .. primary)
  if widget == nil then
      return
  end

  widget:setChecked(true)
  if secondary == nil then
      return
  end

  local panel = MiniBotMiniWindow.tabs:getChildById('ChildPanel_' .. primary)
  if panel == nil then
      return
  end

  local child = panel:getChildById('ChildButton_' .. secondary)
  if child == nil then
      return
  end

  child:setChecked(true)
end

function init()
  if moduleInitialized then
    return
  end

  MiniBotCompat.init()
  callRuntime('init')
  moduleInitialized = true

  MiniBotMiniWindow = g_ui.displayUI('minibot')
  MiniBotMiniWindow:hide()

  MiniBotMiniWindow:constructEnviorementVariables()
  MiniBotCompat.prepareWidgetTree(MiniBotMiniWindow)

  setupOptionsMainButton()

  loadPresetList()

  for _, page in ipairs(pages) do
    local widget = g_ui.createWidget('MiniBotInfoTab', MiniBotMiniWindow.tabs)
    widget:constructEnviorementVariables()

    widget:setId('TabButton_' .. page.identifier)
    widget:setText(page.name)
    widget:setIconClip(torect(page.icon))
    widget:setIconSize(page.iconSize)
    if resourcesAreEncrypted() and page.disabled then
      widget:setEnabled(false)
      widget.extended:setText('Soon!')
      minibotAnimateExtension(widget)
    end

    if page.childs ~= nil and #(page.childs) > 0 then
      widget.downArrow:show()

      local panel = g_ui.createWidget('MiniBotPanelTab', MiniBotMiniWindow.tabs)
      panel:setId('ChildPanel_' .. page.identifier)
      local totalHeight = 0
      for _, child in ipairs(page.childs) do
        local innerChild = g_ui.createWidget('MiniBotChildInfoTab', panel)
        innerChild:constructEnviorementVariables()

        if resourcesAreEncrypted() and child.disabled then
          innerChild:setEnabled(false)
          innerChild.extended:setText('Soon!')
          minibotAnimateExtension(innerChild)
        end

        innerChild:setId('ChildButton_' .. child.identifier)
        innerChild:setText(child.name)
        innerChild:setIconClip(torect(child.icon))
        innerChild:setIconSize(child.iconSize)

        totalHeight = totalHeight + 20
        innerChild.onCheckChange = function()
          if innerChild.ignoreCallback then
              innerChild.rightArrow:setVisible(innerChild:isChecked())
              return
          end

          if not(innerChild:isChecked()) then
              innerChild.ignoreCallback = true
              innerChild:setChecked(true)
              innerChild.ignoreCallback = nil
              return
          end

          for _, c in ipairs(panel:getChildren()) do
              if c ~= innerChild then
                  c.ignoreCallback = true
                  c:setChecked(false)
                  c.ignoreCallback = nil
              end
          end

          innerChild.rightArrow:setVisible(innerChild:isChecked())

          if innerChild:isChecked() then
              loadMainPanel(child.ui)
          end
        end
      end

      panel:setHeight(totalHeight)
      panel:hide()

      widget.childPanel = panel
      widget.reloadMajorChilds = function()
        if widget:isChecked() then
          panel:show()
          local firstChild = panel:getChildByIndex(1)
          if firstChild ~= nil then
            firstChild:setChecked(true)
          end
          widget:setMarginBottom(0)
        else
          panel:hide()
          for _, c in ipairs(panel:getChildren()) do
            if c ~= innerChild then
              c.ignoreCallback = true
              c:setChecked(false)
              c.ignoreCallback = nil
            end
          end
          widget:setMarginBottom(3)
        end
      end
    else
      widget:setMarginBottom(3)
    end

    widget.onCheckChange = function()
      if widget.ignoreMajorCheck then
          return
      end

      if not(widget:isChecked()) then
          widget.ignoreMajorCheck = true
          widget:setChecked(true)
          widget.ignoreMajorCheck = nil
          return
      end

      if widget:isChecked() then
        for _, c in ipairs(MiniBotMiniWindow.tabs:getChildren()) do
          if c ~= widget then
            if c.childPanel ~= nil then
              c.reloadMajorChilds()
              c.downArrow:setVisible(true)
            else
              c.ignoreMajorCheck = true
              c:setChecked(false)
              if c.rightArrow ~= nil then
                c.rightArrow:setVisible(false)
              end
              c.ignoreMajorCheck = nil
            end
          end
        end
      end

      if page.childs ~= nil and #(page.childs) > 0 then
        widget.downArrow:setVisible(not(widget:isChecked()))
        if widget:isChecked() then
          widget.ignoreMajorCheck = true
          widget.reloadMajorChilds()
          widget:setChecked(false)
          widget.ignoreMajorCheck = nil
        else
          widget.reloadMajorChilds()
        end
      else
        widget.rightArrow:setVisible(widget:isChecked())
        if widget:isChecked() then
          loadMainPanel(page.ui)
        end
      end
    end
  end

  local firstChild = MiniBotMiniWindow.tabs:getChildByIndex(1)
  if firstChild ~= nil then
    firstChild:setChecked(true)
  end

  reloadLanguage()

  connect(g_minibot, {
    onWalkToNextNode = setupMinimapTexts,
    onWalkFailed = onMiniBotWalkFailed,
  })

  connect(g_game, {
    onGameStart = onGameStart,
    onPlayerInfo = onPlayerInfo,
    onGameEnd = onGameEnd,
    onMissileTo = onMissileTo,
    onResourceBalance = onResourceBalance
  })

  connect(LocalPlayer, {
    onPartyMembersName = onPartyMembersName,
    onCaveBotTimestamp = onCaveBotTimestamp
  })
  signalsConnected = true

  if g_game.isOnline() then
    onPlayerInfo()
    toggle()
  end
end

function terminate()
  if not moduleInitialized then
    return
  end
  moduleInitialized = false

  if signalsConnected then
    disconnect(g_minibot, {
      onWalkToNextNode = setupMinimapTexts,
      onWalkFailed = onMiniBotWalkFailed,
    })

    disconnect(g_game, {
      onGameStart = onGameStart,
      onPlayerInfo = onPlayerInfo,
      onGameEnd = onGameEnd,
      onMissileTo = onMissileTo,
      onResourceBalance = onResourceBalance
    })

    disconnect(LocalPlayer, {
      onPartyMembersName = onPartyMembersName,
      onCaveBotTimestamp = onCaveBotTimestamp
    })
    signalsConnected = false
  end

  cancelScheduledReloads()
  terminateActivePage()
  cancelWidgetEvents(MiniBotMiniWindow)
  removeOwnedEvent(MiniBotMiniWindow, 'disableCaveBotEvent')
  removeOwnedEvent(MiniBotMiniWindow, 'eventTicks')

  callRuntime('stop')
  callRuntime('terminate')
  gameSessionStarted = false
  MiniBotCompat.releaseWidgetTree(MiniBotMiniWindow)
  MiniBotCompat.terminate()

  local mainPanel = modules and modules.game_mainpanel
  if mainPanel and mainPanel.removeMiniBotHelper then
    mainPanel.removeMiniBotHelper()
  elseif widgetAlive(MiniBotToggleButton) then
    MiniBotToggleButton:destroy()
  end

  local gameInterface = modules and modules.game_interface
  if gameInterface and gameInterface.resetMiniBotPanels then
    gameInterface.resetMiniBotPanels()
  end

  closeDialogWindow()
  closeEditPresetWindow()
  closeImportPresetWindow()

  if widgetAlive(MiniBotGameWindowPanel) then
    MiniBotGameWindowPanel:destroy()
  end
  MiniBotGameWindowPanel = nil

  if widgetAlive(MiniBotMiniWindow) then
    MiniBotMiniWindow:destroy()
  end

  MiniBotMiniWindow = nil
  MiniBotToggleButton = nil
end

function internalToggle(toggle)
  if widgetAlive(MiniBotMiniWindow) then
    MiniBotMiniWindow:setVisible(toggle)
  end
end

function onMissileTo(...)
  if support_generalModule ~= nil then
    support_generalModule.onMissileTo(...)
  end
end

function onPartyMembersName(_, list)
  if not activePageRunning or not widgetAlive(MiniBotMiniWindow) or
     MiniBotMiniWindow.selectedPage ~= 'healing_group' then
    return
  end
  local pageModule = modules.game_minibot.healing_groupModule
  if pageModule and pageModule.getSelectedListType and pageModule.getSelectedListType() == 'party' then
    pageModule.reloadInternalModule()
  end
end

function getDropDownCatcher()
  if not widgetAlive(MiniBotMiniWindow) then
    return nil
  end
  local catcher = MiniBotMiniWindow.dropDownCatcher
  return widgetAlive(catcher) and catcher or nil
end

function onClose()
  closeEditPresetWindow()
  closeImportPresetWindow()

  if widgetAlive(MiniBotToggleButton) then
    MiniBotToggleButton:setOn(false)
  end
  if widgetAlive(MiniBotMiniWindow) then
    MiniBotMiniWindow:hide()
  end
end

function isVisible()
  return widgetAlive(MiniBotMiniWindow) and MiniBotMiniWindow:isVisible()
end

function toggle()
  if not widgetAlive(MiniBotMiniWindow) then
    return
  end
  if MiniBotMiniWindow:isVisible() then
    onClose()
  else
    show()
  end
end

function show()
  if widgetAlive(MiniBotMiniWindow) and not MiniBotMiniWindow:isVisible() then
    MiniBotMiniWindow.dropDownCatcher:hide()
    MiniBotMiniWindow:show()
    MiniBotMiniWindow:focus()
    if widgetAlive(MiniBotToggleButton) then
      MiniBotToggleButton:setOn(true)
    end
    g_game.resourceRequest(0)
    initializeActivePage()
  end
end

function setupOptionsMainButton()
  if MiniBotToggleButton then
      return
  end

  local mainPanel = modules and modules.game_mainpanel
  if mainPanel and mainPanel.getMiniBotHelper then
    MiniBotToggleButton = mainPanel.getMiniBotHelper(toggle)
  end

  if MiniBotToggleButton == nil then
    local root = g_ui.getRootWidget()
    MiniBotToggleButton = root and root:recursiveGetChildById('miniBotHelper') or nil
    if MiniBotToggleButton ~= nil then
      MiniBotToggleButton.onClick = toggle
    else
      g_logger.warning('[game_minibot] main panel launcher is unavailable')
    end
  end
end

function createBrandnewPreset(uid)
  local lastPreset = uid
  if uid == nil then
    lastPreset = getSettingsValue(false, 'last_preset', 0) + 1
  end

  local entry = {
    name = ('New Preset #' .. lastPreset),
    uid = lastPreset,
    creation = os.time()
  }

  if uid == nil then
    setSettingsValue(false, 'last_preset', lastPreset)
  end

  return entry
end

local function createAndStorePreset()
  local settings = _loadMiniBotSettings()
  local lastPreset = (tonumber(settings.last_preset) or 0) + 1
  local entry = createBrandnewPreset(lastPreset)

  if type(settings.presets) ~= 'table' then
    settings.presets = {}
  end
  settings.last_preset = lastPreset
  settings.presets[tostring(entry.uid)] = entry
  _saveMiniBotSettings()
  return entry
end

function getPressetSettings()
  local settings = _loadMiniBotSettings()

  local currentPreset = nil
  for _, c in ipairs(MiniBotMiniWindow.presets.list:getChildren()) do
    if c.selectedPreset then
      currentPreset = c.presetUid
      break
    end
  end

  if currentPreset == nil then
    return {}
  end

  if type(settings['presets']) ~= 'table' then
    settings['presets'] = {}
    _saveMiniBotSettings()
  end

  local preset = settings['presets'][tostring(currentPreset)]
  if type(preset) ~= 'table' then
    return {}
  end
  local copy, err = cloneSafeConfigValue(preset, false, { active = {}, nodes = 0, changed = false }, 0)
  if copy == nil then
    if g_logger ~= nil and type(g_logger.warning) == 'function' then
      g_logger.warning('[game_minibot] refusing unsafe preset data: ' .. tostring(err))
    end
    return {}
  end
  return copy
end

function setPressetSettings(value)
  local settings = _loadMiniBotSettings()

  local currentPreset = nil
  for _, c in ipairs(MiniBotMiniWindow.presets.list:getChildren()) do
    if c.selectedPreset then
      currentPreset = c.presetUid
      break
    end
  end

  if currentPreset == nil then
    return false
  end

  if type(settings['presets']) ~= 'table' then
    settings['presets'] = {}
  end

  local current = settings['presets'][tostring(currentPreset)]
  if type(current) ~= 'table' then
    return false
  end

  local clean, err = cloneSafeConfigValue(value, false, { active = {}, nodes = 0, changed = false }, 0)
  if clean == nil then
    if g_logger ~= nil and type(g_logger.warning) == 'function' then
      g_logger.warning('[game_minibot] refusing unsafe preset update: ' .. tostring(err))
    end
    return false
  end
  clean.uid = current.uid
  clean.name = current.name
  clean.creation = current.creation
  clean, err = normalizePresetEntry(clean, true)
  if clean == nil then
    if g_logger ~= nil and type(g_logger.warning) == 'function' then
      g_logger.warning('[game_minibot] refusing invalid preset update: ' .. tostring(err))
    end
    return false
  end

  settings['presets'][tostring(currentPreset)] = clean
  _saveMiniBotSettings()
  return true
end

function getSettingsValue(ownPlayer, key, default)
  local settings = _loadMiniBotSettings()

  if not(ownPlayer) then
    local value = settings[key]
    if value == nil then
      return default
    end
    if type(value) == 'table' then
      local copy = cloneSafeConfigValue(value, false, { active = {}, nodes = 0, changed = false }, 0)
      return copy or default
    end
    return value
  end

  local characterName = currentCharacterName()
  if characterName == nil then
    return default
  end

  local cSettings = settings[characterName]
  if type(cSettings) ~= 'table' then
    settings[characterName] = {}
    _saveMiniBotSettings()
    return default
  end

  local value = cSettings[key]
  if value == nil then
    return default
  end
  if type(value) == 'table' then
    local copy = cloneSafeConfigValue(value, false, { active = {}, nodes = 0, changed = false }, 0)
    return copy or default
  end
  return value
end

function setSettingsValue(ownPlayer, key, value)
  local settings = _loadMiniBotSettings()
  local clean, err = cloneSafeConfigValue(value, false, { active = {}, nodes = 0, changed = false }, 0)
  if value ~= nil and clean == nil then
    if g_logger ~= nil and type(g_logger.warning) == 'function' then
      g_logger.warning('[game_minibot] refusing unsafe setting update: ' .. tostring(err))
    end
    return false
  end

  if not(ownPlayer) then
    settings[key] = clean
    _saveMiniBotSettings()
    return true
  end

  local characterName = currentCharacterName()
  if characterName == nil then
    return false
  end
  if type(settings[characterName]) ~= 'table' then
    settings[characterName] = {}
  end

  settings[characterName][key] = clean
  _saveMiniBotSettings()
  return true
end

function onClickPresetEntry(widget, ignoreSave)
  -- Persist the current page while the old preset is still selected. Waiting
  -- until loadMainPanel would make a pending save target the newly selected
  -- preset instead.
  local rootAlive = widgetAlive(MiniBotMiniWindow)
  local main = rootAlive and MiniBotMiniWindow.main or nil
  local pageWidget = widgetAlive(main) and main:getChildByIndex(1) or nil
  cancelDeferredPageActions(widgetAlive(pageWidget))

  for _, c in ipairs(widget:getParent():getChildren()) do
    if c ~= widget then
      c.mask:hide()
      c.selectedPreset = false
    end
  end

  widget.mask:show()
  widget.selectedPreset = true
  setPresetNameOnPanel()

  if not(ignoreSave) then
    setSettingsValue(true, 'selected_preset', widget.presetUid)
  end

  -- A preset reload must rebuild the page-owned widget tree. Re-initializing
  -- the same tree made donor terminate hooks destroy dynamic rows and then
  -- made the parent destroy them a second time on the next page switch.
  if MiniBotMiniWindow.selectedPage ~= nil and MiniBotMiniWindow.selectedPage ~= '' then
    loadMainPanel(MiniBotMiniWindow.selectedPage)
  end

  onGameWindowPresetnamgeChange(MiniBotMiniWindow.presets.buttons.gamewindow, true)
  reloadInternalModules(function()
    if moduleInitialized and gameSessionStarted then
      g_minibot.cycle()
    end
  end)
end

local function deferPresetSelection(widget)
  if not widgetAlive(widget) then
    return false
  end

  local generation = activePageGeneration
  local event
  event = addEvent(function()
    forgetDeferredPageAction(event)
    if generation ~= activePageGeneration or not moduleInitialized or
       not activePageRunning or not widgetAlive(widget) then
      return
    end
    onClickPresetEntry(widget)
  end)
  if event ~= nil then
    table.insert(deferredPageActions, event)
    return true
  end
  return false
end

function createPresetWidget(entry)
  local widget = g_ui.createWidget('MiniBotPresetEntry', MiniBotMiniWindow.presets.list)
  widget:constructEnviorementVariables()

  widget:setText(entry.name)
  widget:setTooltip(entry.name)
  widget.onMousePress = openPresetGameMenu

  widget.presetUid = entry.uid

  widget:setBackgroundColor('alpha')

  widget.onLeftClick = function()
    deferPresetSelection(widget)
  end
end

function loadPresetList()
  local presets = {}
  local sPresets = getSettingsValue(false, 'presets', {})
  for _, entry in pairs(sPresets) do
    table.insert(presets, entry)
  end
  table.sort(presets, function(a, b)
    return a.creation < b.creation
  end)

  if #presets == 0 then
    local newEntry = createAndStorePreset()
    table.insert(presets, newEntry)
  end

  MiniBotMiniWindow.presets.list:destroyChildren()
  for _, entry in ipairs(presets) do
    createPresetWidget(entry)
  end
end

function reloadInternalModules(onComplete)
  cancelScheduledReloads()
  local generation = reloadGeneration
  MiniBotMiniWindow.refreshScheduled = {}
  local targets = {}
  for _, entry in ipairs(pages) do
    if entry.ui ~= nil then
      table.insert(targets, entry.ui)
    elseif entry.childs ~= nil then
      for _, child in ipairs(entry.childs) do
        if child.ui ~= nil then
          table.insert(targets, child.ui)
        end
      end
    end
  end

  for curIndex, moduleName in ipairs(targets) do
    local scheduledIndex = curIndex
    local scheduledModule = moduleName
    table.insert(MiniBotMiniWindow.refreshScheduled, scheduleEvent(function()
      if generation ~= reloadGeneration or not moduleInitialized or not widgetAlive(MiniBotMiniWindow) then
        return
      end

      local pageModule = modules.game_minibot[scheduledModule .. 'Module']
      if pageModule ~= nil and pageModule.reloadInternalModule ~= nil then
        pageModule.reloadInternalModule()
      end

      if scheduledIndex == #targets then
        MiniBotMiniWindow.refreshScheduled = nil
        if onComplete ~= nil then
          onComplete()
        end
      end
    end, 25 * scheduledIndex))
  end
end

function selectNextPreset()
  if MiniBotMiniWindow.presets.list:getChildCount() == 0 then
    return
  end

  local next = nil
  for i = 1, MiniBotMiniWindow.presets.list:getChildCount() do
    local c = MiniBotMiniWindow.presets.list:getChildByIndex(i)
    if c ~= nil and c.selectedPreset then
      next = MiniBotMiniWindow.presets.list:getChildByIndex(i + 1)
      break
    end
  end

  if next == nil then
    next = MiniBotMiniWindow.presets.list:getChildByIndex(1)
  end

  if next == nil or next.selectedPreset then
    return
  end

  next:focus()
  next:onLeftClick()
  modules.game_textmessage.displayStatusMessage('Assistant preset selected: ' .. next:getText(), true)
end

function selectPreviousPreset()
  if MiniBotMiniWindow.presets.list:getChildCount() == 0 then
    return
  end

  local previous = nil
  for i = MiniBotMiniWindow.presets.list:getChildCount(), 1, -1 do
    local c = MiniBotMiniWindow.presets.list:getChildByIndex(i)
    if c ~= nil and c.selectedPreset and i > 1 then
      previous = MiniBotMiniWindow.presets.list:getChildByIndex(i - 1)
      break
    end
  end

  if previous == nil then
    previous = MiniBotMiniWindow.presets.list:getChildByIndex(MiniBotMiniWindow.presets.list:getChildCount())
  end

  if previous == nil or previous.selectedPreset then
    return
  end

  previous:focus()
  previous:onLeftClick()
  modules.game_textmessage.displayStatusMessage('Assistant preset selected: ' .. previous:getText(), true)
end

function onGameStart()
  -- The host emits onGameStart before vocation, spell and full player data are
  -- parsed. Initialization is deliberately deferred to the C++ onPlayerInfo
  -- signal so executor filters cannot be built from default/stale values.
end

function onPlayerInfo()
  if not moduleInitialized or gameSessionStarted or not widgetAlive(MiniBotMiniWindow) or g_game.getLocalPlayer() == nil then
    return
  end

  callRuntime('start')
  gameSessionStarted = true
  MiniBotCompat.onGameStart()
  g_minibot.reset()

  if activePageRunning and not activePageSessionReady then
    terminateActivePage()
  end

  local reloadQueued = false
  local selectedPreset = getSettingsValue(true, 'selected_preset', nil)
  for index, c in ipairs(MiniBotMiniWindow.presets.list:getChildren()) do
    if selectedPreset == nil or c.presetUid == selectedPreset or index == MiniBotMiniWindow.presets.list:getChildCount() then
      onClickPresetEntry(c, true)
      reloadQueued = true
      break
    end
  end

  initializeActivePage()

  if not reloadQueued then
    reloadInternalModules(function()
      if moduleInitialized and gameSessionStarted then
        g_minibot.cycle()
      end
    end)
  end

  MiniBotMiniWindow.presets.buttons.gamewindow:setChecked(getSettingsValue(true, 'show_preset_name', false))
end

function onGameEnd()
  if not moduleInitialized then
    return
  end

  gameSessionStarted = false
  cancelScheduledReloads()
  terminateActivePage()
  cancelWidgetEvents(MiniBotMiniWindow)
  callRuntime('stop')
  MiniBotCompat.onGameEnd()

  local gameInterface = modules and modules.game_interface
  if gameInterface and gameInterface.resetMiniBotPanels then
    gameInterface.resetMiniBotPanels()
  end

  closeEditPresetWindow()
  closeImportPresetWindow()

  removeOwnedEvent(MiniBotMiniWindow, 'disableCaveBotEvent')
  removeOwnedEvent(MiniBotMiniWindow, 'eventTicks')

  if widgetAlive(MiniBotMiniWindow) then
    MiniBotMiniWindow:hide()
  end
end

function onClickNewPreset()
  local entry = createAndStorePreset()
  createPresetWidget(entry)
end

function onClickRemovePreset(widget)
  if not widgetAlive(MiniBotMiniWindow) or not widgetAlive(widget) then
    return
  end

  local presetList = MiniBotMiniWindow.presets and MiniBotMiniWindow.presets.list or nil
  if not widgetAlive(presetList) or presetList:getChildCount() <= 1 then
    return
  end

  local presetUid = widget.presetUid
  local presets = {}
  local sPresets = getSettingsValue(false, 'presets', {})
  for _, entry in pairs(sPresets) do
    if entry.uid ~= presetUid then
      presets[tostring(entry.uid)] = entry
    end
  end

  setSettingsValue(false, 'presets', presets)
  loadPresetList()

  local firstChild = widgetAlive(presetList) and presetList:getChildByIndex(1) or nil
  if widgetAlive(firstChild) then
    firstChild:onLeftClick()
  end
end

function loadMainPanel(ui)
  terminateActivePage()

  MiniBotMiniWindow.selectedPage = ui
  cancelWidgetEvents(MiniBotMiniWindow.main)
  MiniBotCompat.releaseWidgetTree(MiniBotMiniWindow.main)
  MiniBotMiniWindow.main:destroyChildren()
  g_ui.loadUI('/modules/game_minibot/pages/' .. ui, MiniBotMiniWindow.main)

  initializeActivePage()
  local pageModule = getPageModule()
  if pageModule ~= nil and activePageRunning then

      if pageModule.reloadLanguage ~= nil then
        pageModule.reloadLanguage(modules.game_minibot.getSettingsValue(false, 'language', 'ptbr'))
      end
  end
end

function callMethod(method, ...)
  local pageModule = getPageModule()
  if pageModule ~= nil then
      if pageModule[method] == nil then
          print('Invalid MiniBot Info method:', method)
          return false
      end

      return (pageModule[method])(...)
  end
  return false
end

function openEditPresetNameWindow(name, onOkEditPreset, onCloseEditPreset)
  local forceClose = onCloseEditPreset == nil
  local externalClose = onCloseEditPreset

  closeEditPresetWindow()
  closeImportPresetWindow()
  if widgetAlive(MiniBotMiniWindow) then
    MiniBotMiniWindow:hide()
  end

  local editWindow = g_ui.displayUI('minibot_editpreset')
  MiniBotEditPresetMiniWindow = editWindow
  if not widgetAlive(editWindow) then
    closeEditPresetWindow(editWindow)
    showMiniBotWindow(false)
    return false
  end

  local function closeCurrentEditWindow()
    if MiniBotEditPresetMiniWindow ~= editWindow then
      return false
    end
    closeEditPresetWindow(editWindow)
    if externalClose ~= nil then
      externalClose()
    end
    showMiniBotWindow(false)
    return true
  end

  local function submitEditWindow()
    if MiniBotEditPresetMiniWindow ~= editWindow or not widgetAlive(editWindow) then
      return
    end
    if not editWindow.ok:isEnabled() then
      return
    end
    local input = editWindow.name:getText()
    onOkEditPreset(input)
    if forceClose then
      closeCurrentEditWindow()
    end
  end

  editWindow:show()
  editWindow:constructEnviorementVariables()
  editWindow.name:setText(name)
  editWindow.onEscape = closeCurrentEditWindow
  editWindow.cancel.onLeftClick = closeCurrentEditWindow
  editWindow.name.onTextChange = function()
    if MiniBotEditPresetMiniWindow ~= editWindow or not widgetAlive(editWindow) then
      return
    end
    local input = editWindow.name:getText()
    if input == '' then
      editWindow.ok:setEnabled(false)
      editWindow.warn:setPhantom(false)
      return
    end

    editWindow.ok:setEnabled(input ~= name)
    editWindow.warn:setPhantom(editWindow.ok:isEnabled())
  end
  editWindow.ok.onLeftClick = submitEditWindow
  editWindow.onEnter = submitEditWindow
  return true
end

function openPresetGameMenu(widget, mousePos, mouseButton)
  if mouseButton ~= MouseRightButton or not widgetAlive(widget) then
    return
  end

  local presetUid = widget.presetUid
  local presetName = widget:getText()
  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)

  menu:addOption("Edit '" .. presetName .. "' name", function()
    if not moduleInitialized or not widgetAlive(MiniBotMiniWindow) then
      return
    end

    local function onOkEditPreset(input)
      local presets = {}
      local sPresets = getSettingsValue(false, 'presets', {})
      for _, entry in pairs(sPresets) do
        if entry.uid ~= presetUid then
          presets[tostring(entry.uid)] = entry
        else
          entry.name = input
          presets[tostring(entry.uid)] = entry
        end
      end

      setSettingsValue(false, 'presets', presets)

      if widgetAlive(widget) and widget.presetUid == presetUid then
        widget:setText(input)
        if widget.selectedPreset then
          setPresetNameOnPanel()
        end
      end
    end

    openEditPresetNameWindow(presetName, onOkEditPreset)
  end)

  menu:addOption("Remove '" .. presetName .. "'", function()
    if widgetAlive(widget) and widget.presetUid == presetUid then
      modules.game_minibot.onClickRemovePreset(widget)
    end
  end)

  menu:display(mousePos)
  return true
end

local function decodeAndValidateImport(text, recorder)
  if type(text) ~= 'string' or text == '' or #text > configLimits.maxImportLength then
    return nil, 'invalid import text length'
  end
  local ok, decoded = pcall(table.unobscure, text)
  if not ok or type(decoded) ~= 'table' then
    return nil, 'import text could not be decoded'
  end
  return validateMiniBotConfigurationData(decoded, recorder and 'recorder-import' or 'preset-import')
end

function importNewPreset(recorder)
  closeEditPresetWindow()
  closeImportPresetWindow()
  if widgetAlive(MiniBotMiniWindow) then
    MiniBotMiniWindow:hide()
  end

  local importWindow = g_ui.displayUI('minibot_importpreset')
  MiniBotImportPresetMiniWindow = importWindow
  if not widgetAlive(importWindow) then
    closeImportPresetWindow(importWindow)
    showMiniBotWindow(false)
    return false
  end

  importWindow:show()
  importWindow:constructEnviorementVariables()

  local function onCloseImportPreset()
    if MiniBotImportPresetMiniWindow ~= importWindow then
      return false
    end
    closeImportPresetWindow(importWindow)
    showMiniBotWindow(false)
    return true
  end

  local function onOkImportPreset()
    if MiniBotImportPresetMiniWindow ~= importWindow or not widgetAlive(importWindow) or
       not importWindow.ok:isEnabled() then
      return
    end

    local newPreset = decodeAndValidateImport(importWindow.name:getText(), recorder)
    if newPreset == nil then
      importWindow.ok:setEnabled(false)
      importWindow.warn:setPhantom(false)
      return
    end

    if recorder then
      if modules.game_minibot.callMethod('onImportCode', newPreset) == false then
        if MiniBotImportPresetMiniWindow == importWindow and widgetAlive(importWindow) then
          importWindow.ok:setEnabled(false)
          importWindow.warn:setPhantom(false)
        end
        return
      end
    else
      local sPresets = getSettingsValue(false, 'presets', {})

      local newUID = getSettingsValue(false, 'last_preset', 0) + 1
      newPreset['uid'] = newUID
      newPreset['creation'] = os.time()
      newPreset['DeusOT_Assistant_Preset_Export'] = nil
      newPreset['version'] = nil
      sPresets[tostring(newUID)] = newPreset
      setSettingsValue(false, 'last_preset', newUID)
      setSettingsValue(false, 'presets', sPresets)

      createPresetWidget(newPreset)
    end
    onCloseImportPreset()
  end

  importWindow.onEscape = onCloseImportPreset
  importWindow.cancel.onLeftClick = onCloseImportPreset
  importWindow.name.onTextChange = function()
    if MiniBotImportPresetMiniWindow ~= importWindow or not widgetAlive(importWindow) then
      return
    end
    importWindow.versionWarn:hide()
    local obscuredCode = decodeAndValidateImport(importWindow.name:getText(), recorder)
    if obscuredCode == nil then
      importWindow.ok:setEnabled(false)
      importWindow.warn:setPhantom(false)
      return
    end

    if recorder then
      if obscuredCode['version'] ~= hunting_recorderModule.getExportCodeVersion() then
        importWindow.ok:setEnabled(false)
        importWindow.versionWarn:show()
        return
      end
    else
      if obscuredCode['version'] ~= miniBotVersion then
        importWindow.versionWarn:show()
      end
    end

    importWindow.warn:setPhantom(true)
    importWindow.ok:setEnabled(true)
  end
  importWindow.ok.onLeftClick = onOkImportPreset
  importWindow.onEnter = onOkImportPreset
  return true
end

function onExportCurrentPreset()
  local settings = getPressetSettings()
  settings['DeusOT_Assistant_Preset_Export'] = true
  settings['version'] = miniBotVersion
  g_window.setClipboardText(table.obscure(settings))

  local message = ""
  local language = modules.game_minibot.getSettingsValue(false, 'language', 'ptbr')
  if language == 'ptbr' then
      message = "Seu preset '" .. settings['name'] .. "' foi exportada com sucesso para a sua area de transferencia. (CTRL + C)"
  elseif language == 'enus' then
      message = "Your preset '" .. settings['name'] .. "' has been succesfully exported into your clipboard. (CTRL + C)"
  end
  modules.game_minibot.openConfirmationWindow("DeusOT Assistant presets", message)
end

function reloadLanguage()
  local language = modules.game_minibot.getSettingsValue(false, 'language', 'ptbr')
  if language == 'ptbr' then
    MiniBotMiniWindow:setText('Assistente')
    MiniBotMiniWindow.clipboard:setTooltip('Exportar preset para a area de transferencia.')
    MiniBotMiniWindow.presets.buttons.new:setText('Novo')
    MiniBotMiniWindow.presets.buttons.import:setText('Importar')
    MiniBotMiniWindow.presets.buttons.gamewindow:setTooltip('Mostrar nome do preset selecionado na janela de jogo.')
  elseif language == 'enus' then
    MiniBotMiniWindow:setText('Assistant')
    MiniBotMiniWindow.clipboard:setTooltip('Export preset to clipboard.')
    MiniBotMiniWindow.presets.buttons.new:setText('New')
    MiniBotMiniWindow.presets.buttons.import:setText('Import')
    MiniBotMiniWindow.presets.buttons.gamewindow:setTooltip('Show selected preset name on Game Window.')
  end

  setPresetNameOnPanel()

  for _, c in ipairs(MiniBotMiniWindow.tabs:getChildren()) do
      if c.extended ~= nil and c.extended:getText() ~= '' then
        if language == 'ptbr' then
          c.extended:setText('Em breve!')
        elseif language == 'enus' then
          c.extended:setText('Soon!')
        end
      end
  end

  -- Reload modules
  local pageModule = getPageModule()
  if pageModule ~= nil then
      if pageModule.reloadLanguage == nil then
          return
      end

      (pageModule.reloadLanguage)(language)
  end
end

function onGameWindowPresetnamgeChange(widget, ignoreSave)
  if widget.ignoreCallback then
    return
  end

  local currentPresetName = nil
  for _, c in ipairs(MiniBotMiniWindow.presets.list:getChildren()) do
    if c.selectedPreset then
      currentPresetName = c:getText()
      break
    end
  end

  if currentPresetName == nil then
    return
  end

  if not(ignoreSave) then
    setSettingsValue(true, 'show_preset_name', widget:isChecked())
  end

  local panel = modules.game_interface.getMiniBotPresetPanel()
  if panel ~= nil then
    if widget:isChecked() then
      panel:show()
      panel:setMarginTop(7)
      panel:setText(currentPresetName)
    else
      panel:hide()
      panel:setMarginTop(0)
      panel:clearText()
    end
  end
end

function setupMinimapTexts()
  local widgets = {}
  local mainPanel = modules and modules.game_mainpanel
  if mainPanel and mainPanel.getMainMinimapPanel then
    local minimap = mainPanel.getMainMinimapPanel()
    if widgetAlive(minimap) then
      table.insert(widgets, minimap)
    end
  end

  local extendedMap = modules and modules.game_extendedmap
  if extendedMap and extendedMap.getExtendedMinimap then
    local minimap = extendedMap.getExtendedMinimap()
    if widgetAlive(minimap) then
      table.insert(widgets, minimap)
    end
  end

  for _, widget in ipairs(widgets) do
    if g_settings.getBoolean('showMinimapMinibotText') and g_minibot.isModuleToggle(5) and g_minibot.getCurrentWalkIndex() > 0 then
      widget:setText("Node: #" .. g_minibot.getCurrentWalkIndex())
    else
      widget:clearText()
    end
  end
end

function openConfirmationWindow(title, message, yesFunc, noFunc)
  closeDialogWindow()
  if widgetAlive(MiniBotMiniWindow) then
    MiniBotMiniWindow:hide()
  end

  if yesFunc == nil then
    local dialog = displayInfoBox(title, message)
    MiniBotMiniWindowDialog = dialog
    if not widgetAlive(dialog) then
      closeDialogWindow(dialog)
      showMiniBotWindow(true)
      return false
    end
    dialog.ok = function()
      if MiniBotMiniWindowDialog == dialog then
        closeDialogWindow(dialog)
        showMiniBotWindow(true)
      end
      return true
    end

    return true
  end

  local dialog
  local yesCallback = function()
    if MiniBotMiniWindowDialog ~= dialog then
      return
    end
    closeDialogWindow(dialog)
    showMiniBotWindow(true)
    if yesFunc ~= nil then
      yesFunc()
    end
  end

  local noCallback = function()
    if MiniBotMiniWindowDialog ~= dialog then
      return
    end
    closeDialogWindow(dialog)
    showMiniBotWindow(true)
    if noFunc ~= nil then
      noFunc()
    end
  end

  dialog = displayGeneralBox(title, message, {
    { text = 'No', callback = noCallback },
    { text = 'Yes', callback = yesCallback },
    anchor = AnchorHorizontalCenter
  }, yesCallback, noCallback)
  MiniBotMiniWindowDialog = dialog
  if not widgetAlive(dialog) then
    closeDialogWindow(dialog)
    showMiniBotWindow(true)
    return false
  end
  return true
end

function toggleDisableCavebot()
  if not widgetAlive(MiniBotMiniWindow) then
    return
  end

  if MiniBotMiniWindow.eventTicks ~= nil then
    removeEvent(MiniBotMiniWindow.eventTicks)
    MiniBotMiniWindow.eventTicks = nil
  end

  if not(g_minibot.isModuleToggle(5)) then
    return
  end

  --MiniBotMiniWindow.eventTicks = scheduleEvent(function()
  --  if g_minibot.isModuleToggle(5) then
  --    modules.game_minibot.onMiniBotGameWindowChangeFromPanel('huntingRecorder_gamewindow')
  --  end
  --end, math.random(20, 25) * 60 * 1000)
end

function onCaveBotTimestamp(localPlayer, timestamp)
  if timestamp >= os.time() then
    if g_minibot.isModuleToggle(5) then
      modules.game_minibot.onMiniBotGameWindowChangeFromPanel('huntingRecorder_gamewindow', false)
    end

    return
  end
end

function onResourceBalance(type, balance)
  if not widgetAlive(MiniBotMiniWindow) then
    return
  end

  if MiniBotMiniWindow.cacheBalanceBank == nil then
    MiniBotMiniWindow.cacheBalanceBank = 0
    MiniBotMiniWindow.cacheBalanceInventory = 0
  end

  if type == 0 then
    MiniBotMiniWindow.cacheBalanceBank = balance
    MiniBotMiniWindow.balance.text:setText(comma_value(MiniBotMiniWindow.cacheBalanceBank + MiniBotMiniWindow.cacheBalanceInventory))
  elseif type == 1 then
    MiniBotMiniWindow.cacheBalanceInventory = balance
    MiniBotMiniWindow.balance.text:setText(comma_value(MiniBotMiniWindow.cacheBalanceBank + MiniBotMiniWindow.cacheBalanceInventory))
  end
end

function getCacheResourceBalance()
  if not widgetAlive(MiniBotMiniWindow) then
    return 0
  end

  if MiniBotMiniWindow.cacheBalanceBank == nil then
    MiniBotMiniWindow.cacheBalanceBank = 0
    MiniBotMiniWindow.cacheBalanceInventory = 0
  end

  return MiniBotMiniWindow.cacheBalanceBank + MiniBotMiniWindow.cacheBalanceInventory
end
