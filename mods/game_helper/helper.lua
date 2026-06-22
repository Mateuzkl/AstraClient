local player = nil
local healingPanel = nil
local toolsPanel = nil
local mouseGrabberWidget = nil
local helper = nil
local helperTracker = nil
local friendListWidget = nil
local granListWidget = nil
local hotkeyHelperStatus = false
local autoTargetOnHold = false
local multiUseExDelay = 0
local afkTime = 180
local autoTargetModes = {
  ["A"] = 1,
  ["B"] = 2,
  ["C"] = 3,
  ["D"] = 4,
  ["E"] = 5,
  ["F"] = 6,
  ["G"] = 7,
  ["H"] = 8,
  ["I"] = 9
}

local function deepCopy(original)
  local copy = {}
  for k, v in pairs(original) do
    if type(v) == "table" then
      copy[k] = deepCopy(v)
    else
      copy[k] = v
    end
  end
  return copy
end

local defaultShooterProfile = {
  spells = {
    { id = 0, percent = 0, creatures = 1, priority = 1, forceCast = false, selfCast = false },
    { id = 0, percent = 0, creatures = 1, priority = 2, forceCast = false, selfCast = false },
    { id = 0, percent = 0, creatures = 1, priority = 3, forceCast = false, selfCast = false },
    { id = 0, percent = 0, creatures = 1, priority = 4, forceCast = false, selfCast = false },
    { id = 0, percent = 0, creatures = 1, priority = 5, forceCast = false, selfCast = false },
  },
  runes = {
    { id = 0, creatures = 1, priority = 6, forceCast = false },
    { id = 0, creatures = 1, priority = 7, forceCast = false },
  },
  autoTargetMode = autoTargetModes['F']
}

local foodConfig = { id = "food", exhaustion = 1000 }
local potionConfig = { id = "potion", exhaustion = 1000 }

local helperEvents = {
  helperCycleEvent = nil,
  helperCycleTimer = 50
}

local timers = {
  checkHealthHealing = 0,
  checkMana = 0,
  routineChecks = 0,
  checkFriendHealing = 0,
  checkAutoHaste = 0,
  checkMagicShooter = 0,
  checkAutoTarget = 0,
  checkExerciseEvent = 0,
  checkUtamoVita = 0,
  checkExanaVita = 0,
  checkShieldPotion = 0
}

local eventTable = {
  checkHealthHealing = { interval = 250, action = nil },
  checkMana = { interval = 100, action = nil },
  routineChecks = { interval = 1000, action = nil },
  checkFriendHealing = { interval = 250, action = nil },
  checkAutoHaste = { interval = 500, action = nil },
  checkMagicShooter = { interval = 100, action = nil },
  checkAutoTarget = { interval = 250, action = nil },
  checkExerciseEvent = { interval = 10000, action = nil },
  checkUtamoVita = { interval = 150, action = nil },
  checkExanaVita = { interval = 300, action = nil },
  checkShieldPotion = { interval = 150, action = nil }
}

local spellsCooldown = {}
local function getSpellCooldown(spellId)
  return spellsCooldown[spellId] or 0
end

local groupsCooldown = {}
local function getGroupSpellCooldown(groupId)
  return groupsCooldown[groupId] or 0
end

local function getDistanceBetween(p1, p2)
  return math.max(math.abs(p1.x - p2.x), math.abs(p1.y - p2.y))
end

local function positionCompare(position1, position2)
  return position1.x == position2.x and position1.y == position2.y and position1.z == position2.z
end

local function playerHasSpell(player, spellId)
  -- LocalPlayer:getSpells is NOT bound to Lua on this 15.24 build. Check the method
  -- EXISTS (cheap field read) instead of pcall-ing an erroring call every cycle:
  -- the shooter calls this per spell, ~20x/s, and generating a Lua error object each
  -- time was a real per-frame cost in a busy hunt. If unavailable, assume known (the
  -- server rejects unknown casts anyway). Proper fix = bind getSpells in C++.
  if not player or not player.getSpells then return true end
  local spells = player:getSpells()
  return type(spells) == 'table' and table.contains(spells, spellId)
end

local function numberToOrdinal(n)
  local lastDigit = n % 10
  local lastTwoDigits = n % 100
  if lastTwoDigits >= 11 and lastTwoDigits <= 13 then
    return tostring(n) .. "th"
  end
  if lastDigit == 1 then
    return tostring(n) .. "st"
  elseif lastDigit == 2 then
    return tostring(n) .. "nd"
  elseif lastDigit == 3 then
    return tostring(n) .. "rd"
  else
    return tostring(n) .. "th"
  end
end

local function isWithinReach(playerPos, targetPos)
  if type(targetPos) ~= "table" then
    return false
  end

  local deltaX = math.abs(playerPos.x - targetPos.x)
  local deltaY = math.abs(playerPos.y - targetPos.y)
  local withinX = deltaX <= 7
  local withinY = deltaY <= 5
  return withinX and withinY and playerPos.z == targetPos.z
end

local spectators = {}

-- Per-cycle shared context. helperCycleEvent bumps tickCycle once per 50ms pass; the
-- getters below memoize their result for that cycle, so multiple events firing in the
-- same pass share a single map scan instead of each rebuilding it. This decouples the
-- events from redundant reads (e.g. friend-heal detection + self-heal's friend-priority
-- probe both need the nearby players, but now scan the map only once per cycle).
local tickCycle = 0
local tickCache = { nearbyCycle = -1, nearby = nil }

-- Nearby player creatures keyed by name, within the castable reach box (7x5). Computed
-- at most once per cycle; callers must only use it from inside a helperCycleEvent pass.
local function tickNearbyPlayers()
  if tickCache.nearbyCycle == tickCycle and tickCache.nearby then
    return tickCache.nearby
  end
  local nearby = {}
  local localPlayer = g_game.getLocalPlayer()
  local position = localPlayer and localPlayer:getPosition()
  if position then
    for _, creature in ipairs(g_map.getSpectatorsInRange(position, false, 7, 5)) do
      if creature:isPlayer() and not creature:isLocalPlayer() then
        nearby[creature:getName()] = creature
      end
    end
  end
  tickCache.nearby = nearby
  tickCache.nearbyCycle = tickCycle
  return nearby
end

helperConfig = {
  spells = {
    { id = 0, percent = 80 },
    { id = 0, percent = 80 },
    { id = 0, percent = 80 }
  },
  potions = {
    { id = 0, percent = 50, priority = 0 },
    { id = 0, percent = 50, priority = 0 },
    { id = 0, percent = 50, priority = 0 }
  },
  training = {
    { id = 0, percent = 0, enabled = false }
  },
  haste = {
    { id = 0, enabled = false, safecast = false }
  },
  -- mode: "PT" (auto party members) | "List" (manual saved names). percent = single
  -- HP% trigger. list = manual List-mode names (ordered = priority). ptOrder = saved
  -- priority order for PT mode (by name; new members appended). See onFriendHealing.
  friendhealing = { mode = "PT", percent = 99, enabled = false, prioritizeFriend = false, list = {}, ptOrder = {} },
  gransiohealing = { mode = "PT", percent = 99, enabled = false, prioritizeFriend = false, list = {}, ptOrder = {} },

  shooterProfiles = {
    ["Default"] = defaultShooterProfile
  },
  selectedShooterProfile = "Default",

  autoEatFood = false,
  autoReconnect = false,
  autoSellLoot = false,
  autoBless = false,
  magicShooterEnabled = false,
  magicShooterOnHold = false,
  autoTargetEnabled = false,
  autoTargetMode = autoTargetModes['F'],
  currentLockedTargetId = 0
}

-- Synced from the koliseuot server (2026-06-13, data/scripts/actions/items/foods.lua):
-- every food that actually feeds. Zero-nutrition items (headache pill, stale mushroom
-- beer) and the infinite buff-foods are intentionally excluded from auto-eat here.
local foodIds = {
  169, 229, 836, 841, 901, 904, 3250, 3577, 3578, 3579,
  3580, 3581, 3582, 3583, 3584, 3585, 3586, 3587, 3588, 3589,
  3590, 3591, 3592, 3593, 3594, 3595, 3596, 3597, 3598, 3599,
  3600, 3601, 3602, 3606, 3607, 3723, 3724, 3725, 3726, 3727,
  3728, 3729, 3730, 3731, 3732, 5096, 5678, 6125, 6277, 6278,
  6392, 6393, 6500, 6541, 6542, 6543, 6544, 6545, 6569, 6574,
  7158, 7159, 7373, 7374, 7375, 7376, 7377, 8010, 8011, 8012,
  8013, 8014, 8015, 8016, 8017, 8019, 8177, 8197, 10219, 10329,
  10453, 11459, 11460, 11461, 11462, 11681, 11682, 11683, 12310, 13992,
  14084, 14085, 14681, 16103, 17457, 17820, 17821, 20310, 21143, 21144,
  21145, 21146, 22185, 22187, 23535, 23545, 24382, 24383, 24396, 24948,
  25692, 30198, 30202, 31560, 32069, 37530, 37531, 37532, 37533, 48116,
  48251, 48252, 48253, 48254, 48255, 48256, 48273, 48508, 48509, 48511,
  48544
}

-- Infinite/permanent buff-foods (server does not consume them) -- eaten first.
local infiniteFoodIds = {
  60023, 60055
}

-- Exercise dummies as a map of item id -> training rate, synced from the koliseuot
-- server (items.xml type=dummy attribute, 2026-06-14). Rate tiers:
--   150 = premium / levelable (undead soldier + skins; each dummy level adds +20 on
--         top, but the level is server-only and invisible to the client),
--   120/130 = house / expert, 100 = public / store.
-- The auto-trainer prefers the highest-rate reachable dummy and falls back down the
-- tiers. (5787/5788 "training dummy" and 15710 "target dummy" are NOT type=dummy on
-- the server -> not trainable, intentionally excluded.)
local dummyRates = {
  [28558]=100, [28561]=120, [28562]=120, [28563]=120, [28564]=120, [28565]=100,
  [57244]=150, [57248]=150, [60009]=150, [60010]=150, [60012]=150, [60013]=150,
  [60014]=150, [60015]=150, [60018]=150, [60019]=150, [60021]=100, [60026]=100,
  [60031]=120, [60032]=120, [60033]=120, [60034]=120, [60062]=120, [60063]=120,
  [60102]=120, [60103]=120, [60127]=120, [60128]=120, [60130]=150, [60131]=150,
  [60139]=120, [60140]=120, [60153]=120, [60154]=120, [60163]=120, [60164]=120,
  [60261]=120, [60262]=120, [60298]=120, [60299]=120, [60308]=150, [60309]=150,
  [60310]=150, [60311]=150, [60453]=120, [60454]=120, [60620]=130, [60621]=130,
  [60856]=150, [60857]=150, [61198]=150, [61199]=150, [62806]=120, [62809]=120,
  [63007]=150, [63008]=150, [63066]=150, [63067]=150, [63068]=150, [63069]=150,
  [63070]=150, [63071]=150, [63571]=150, [63572]=150, [63573]=150, [63574]=150,
  [64198]=150, [64199]=150, [64201]=150, [64202]=150, [64203]=150, [64204]=150,
  [64205]=150, [64206]=150, [64207]=150, [64208]=150, [64209]=150, [64210]=150,
  [64308]=150, [64309]=150
}

-- Exercise weapons (server exerciseWeaponsTable + boosted), server-synced 2026-06-13.
local exercises = {
  28540, 28541, 28542, 28543, 28544, 28545, 28552, 28553, 28554, 28555,
  28556, 28557, 35279, 35280, 35281, 35282, 35283, 35284, 35285, 35286,
  35287, 35288, 35289, 35290, 44064, 44065, 44066, 44067, 50292, 50293,
  50294, 50295, 60640, 60641, 60642, 60643, 60644, 60645, 60646
}

-- Exercise weapons usable from a distance (allowFarUse on the server: rods, wands,
-- bows/distance). Anything else (sword/axe/club/fist/shield) must hit an ADJACENT
-- dummy, so the auto-trainer only considers dummies within 1 sqm for those.
local farUseExercises = {
  [28543]=true, [28544]=true, [28545]=true, [28555]=true, [28556]=true, [28557]=true,
  [35282]=true, [35283]=true, [35284]=true, [35288]=true, [35289]=true, [35290]=true,
  [60644]=true, [60645]=true
}

-- spells that can be cast on both targets and self
local bothCastTypeSpells = {
  258
}


local ignoredSpellsIds = {
  [144] = true, -- Cure Bleeding
  [146] = true, -- Cure Electrification
  [29]  = true, -- Cure Poison
  [145] = true, -- Cure Burning
  [147] = true, -- Cure Curse
  [160] = true, -- Utura Gran
  [159] = true, -- Utura
  [128] = true, -- Utura Mas Sio
  [141] = true, -- utori alguma coisa
  [138] = true, -- utori alguma coisa
  [139] = true, -- utori alguma coisa
  [140] = true, -- utori alguma coisa
  [143] = true, -- utori alguma coisa
  [142] = true, -- utori alguma coisa
  [84]  = true,
  [242] = true,
  [297] = true,
  [274] = true,
  [275] = true,
  [276] = true,
  [296] = true,
}

local ignoredTrainingSpells = {
  [144] = true, -- Cure Bleeding
  [146] = true, -- Cure Electrification
  [29]  = true, -- Cure Poison
  [145] = true, -- Cure Burning
  [147] = true, -- Cure Curse
  [160] = true, -- Utura Gran
  [159] = true, -- Utura
  [128] = true, -- Utura Mas Sio
  [141] = true, -- utori alguma coisa
  [138] = true, -- utori alguma coisa
  [139] = true, -- utori alguma coisa
  [140] = true, -- utori alguma coisa
  [143] = true, -- utori alguma coisa
  [142] = true, -- utori alguma coisa
  [170] = true,
  [123] = true,
  [239] = true,
  [241] = true,
  [242] = true,
  [125] = true,
  [82]  = true,
  [84]  = true,
  [1]   = true,
  [2]   = true,
  [158] = true,
  [172] = true,
  [36]  = true,
  [277] = true,
}

-- Drinkable HP/mana/spirit potions, synced from the koliseuot server (2026-06-13,
-- data/scripts/actions/items/potions.lua). Spirit potions restore both but are
-- classed as "health" (used in the healer's health slot, matching prior behaviour).
local potionWhitelist = {
  -- Mana
  { id = 268,   name = "Mana Potion",            type = "mana" },
  { id = 237,   name = "Strong Mana Potion",     type = "mana" },
  { id = 238,   name = "Great Mana Potion",      type = "mana" },
  { id = 23373, name = "Ultimate Mana Potion",   type = "mana" },
  { id = 60258, name = "Cosmic Mana Potion",     type = "mana" },
  -- Health
  { id = 7876,  name = "Small Health Potion",    type = "health" },
  { id = 266,   name = "Health Potion",          type = "health" },
  { id = 236,   name = "Strong Health Potion",   type = "health" },
  { id = 239,   name = "Great Health Potion",    type = "health" },
  { id = 7643,  name = "Ultimate Health Potion", type = "health" },
  { id = 23375, name = "Supreme Health Potion",  type = "health" },
  { id = 60259, name = "Cosmic Health Potion",   type = "health" },
  -- Spirit (restore both HP and mana)
  { id = 7642,  name = "Great Spirit Potion",    type = "health" },
  { id = 23374, name = "Ultimate Spirit Potion", type = "health" },
  { id = 60260, name = "Cosmic Spirit Potion",   type = "health" }
}

local hasteWhiteList = {
  [9] = { 6, 39 }, -- em
  [8] = { 6, 131 }, -- ek
  [7] = { 6, 134 }, -- rp
  [6] = { 6, 39 }, -- ed
  [5] = { 6, 39 }, -- ms
  [0] = {},       -- rook
}


function init()
  connect(LocalPlayer, {
    onPartyMembersChange = onPartyMembersChange,
  })

  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
    onSpellCooldown = onSpellCooldown,
    onSpellGroupCooldown = onSpellGroupCooldown,
    onUpdateSpellArea = onUpdateSpellArea,
    onPartyDataUpdate = onPartyDataUpdate,
    onPartyDataClear = onPartyDataClear,
    onMultiUseCooldown = onMultiUseCooldown,
    onTextMessage = onExerciseTextMessage,
  })

  connect(Creature, {
    onAppear = onCreatureAppear,
    onDisappear = onCreatureDisappear,
  })

  helper = g_ui.displayUI('styles/helper')
  helperTracker = g_ui.createWidget('HelperTracker')
  helperTracker:setup()
  helperTracker:close()

  player = g_game.getLocalPlayer()
  hide()
  healingPanel = helper.contentPanel:getChildById('healingPanel')
  toolsPanel = helper.contentPanel:getChildById('toolsPanel')
  healingPanel = helper.contentPanel:getChildById('healingPanel')
  potionButton2 = healingPanel:recursiveGetChildById("potionButton2")
  rmvPotionPercentButton2 = healingPanel:recursiveGetChildById("rmvPotionPercentButton2")
  potionPercentBg2 = healingPanel:recursiveGetChildById("potionPercentBg2")
  addPotionPercentButton2 = healingPanel:recursiveGetChildById("addPotionPercentButton2")
  priority2 = healingPanel:recursiveGetChildById("priority2")
  friendHealingPanel = healingPanel:recursiveGetChildById("friendHealingPanel")
  granSioPanel = healingPanel:recursiveGetChildById("granSioPanel")
  spellButton2 = healingPanel:recursiveGetChildById("spellButton2")
  rmvPercentButton2 = healingPanel:recursiveGetChildById("rmvPercentButton2")
  spellPercentBg2 = healingPanel:recursiveGetChildById("spellPercentBg2")
  addPercentButton2 = healingPanel:recursiveGetChildById("addPercentButton2")
  healPanel = helper.contentPanel.healingPanel.healingPanel
  priorityButton1 = healingPanel:recursiveGetChildById("priority0")
  priorityButton2 = healingPanel:recursiveGetChildById("priority1")
  priorityButton3 = healingPanel:recursiveGetChildById("priority2")
  equipPanel = toolsPanel:recursiveGetChildById("equipPanel")
  shooterPanel = helper.contentPanel:getChildById('shooterPanel')
  runePanel = shooterPanel:recursiveGetChildById("runePanel")
  attackSpellPanel3 = shooterPanel:recursiveGetChildById("attackSpellPanel3")
  attackSpellPanel4 = shooterPanel:recursiveGetChildById("attackSpellPanel4")
  spellPanel = shooterPanel:recursiveGetChildById("spellPanel")
  enableButtons = shooterPanel:recursiveGetChildById("enableButtons")
  presetsPanel = shooterPanel:recursiveGetChildById('presetsPanel')
  friendListWidget = healingPanel:recursiveGetChildById('friendList')
  granListWidget = healingPanel:recursiveGetChildById('friendList2')
  helperTabs = helper.contentPanel.optionsTabBar

  botStatus()

  if Cavebot then
    local ok, err = pcall(Cavebot.init, helper)
    if not ok then consoleln('[Cavebot] init error: ' .. tostring(err)) end
  end

  if Scripting then
    local ok, err = pcall(Scripting.init, helper)
    if not ok then consoleln('[Scripting] init error: ' .. tostring(err)) end
  end

  mouseGrabberWidget = g_ui.createWidget('UIWidget')
  mouseGrabberWidget:setVisible(false)
  mouseGrabberWidget:setFocusable(false)

  if g_game.isOnline() then
    online()
  end
end

function terminate()
  disconnect(LocalPlayer, {
    onPartyMembersChange = onPartyMembersChange,
  })

  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
    onSpellCooldown = onSpellCooldown,
    onSpellGroupCooldown = onSpellGroupCooldown,
    onUpdateSpellArea = onUpdateSpellArea,
    onPartyDataUpdate = onPartyDataUpdate,
    onPartyDataClear = onPartyDataClear,
    onMultiUseCooldown = onMultiUseCooldown,
    onTextMessage = onExerciseTextMessage,
  })

  disconnect(Creature, {
    onAppear = onCreatureAppear,
    onDisappear = onCreatureDisappear,
  })

  if Cavebot then Cavebot.terminate() end
  if Scripting then Scripting.terminate() end

  if helper then
    g_keyboard.unbindKeyPress('Tab', toggleNextWindow, helper)
    helper:destroy()
    helper = nil
  end
end

function toggle()
  if helper:isVisible() then
    helper:hide()
  else
    helper:show(true)
    helper:raise()
    helper:focus()
    g_keyboard.bindKeyPress('Tab', toggleNextWindow, helper)
    loadMenu('healingMenu')
  end
end

function hide()
  if helper then
    g_keyboard.unbindKeyPress('Tab', toggleNextWindow, helper)
    helper:hide()
    saveSettings()
  end
end

function show()
  if helper then
    helper:show(true)
    helper:raise()
    helper:focus()
    g_keyboard.bindKeyPress('Tab', toggleNextWindow, helper)
    loadMenu('healingMenu')
  end
end

function helperCycleEvent()
  tickCycle = tickCycle + 1 -- invalidates the per-cycle shared context (tickNearbyPlayers)
  for eventName, eventData in pairs(eventTable) do
    timers[eventName] = timers[eventName] + helperEvents.helperCycleTimer
    if timers[eventName] >= eventData.interval then
      timers[eventName] = 0
      local func = eventData.action
      if func and type(func) == "function" then
        func()
      end
    end
  end
end

-- ===========================================================================
-- Magic Shield suite (MAGE ONLY): utamo vita / exana vita / magic shield potion.
-- Gated by the master helper toggle (hotkeyHelperStatus) + each function's own
-- enabled flag. Only mounted/shown for sorcerers & druids. The on-map combat is
-- unaffected; this just casts the support spells / uses the potion on conditions.
-- ===========================================================================
local MAGIC_SHIELD_SPELL_ID = 44   -- "Magic Shield" (utamo vita)
local MAGIC_SHIELD_GROUP    = 3    -- support-spell cooldown group (utamo/exana vita)
local MAGIC_SHIELD_POTION_ID = 35563 -- Tibia "magic shield potion" client id (locked)
local mageShieldIsMage   = false   -- cached vocation gate
local mageShieldPanel    = nil     -- the tools sub-panel (nil until mounted)
local mageShieldBound    = {}      -- which -> bound key combo (to unbind on rebind)

local function msChild(id) return mageShieldPanel and mageShieldPanel:recursiveGetChildById(id) or nil end

-- Reusable +/- percent selector (matches the Auto-Healing widget). Global so the
-- cavebot (2nd script) can use it too. State is stored on the selector widget.
function initPercentSelector(selector, value, minv, maxv, step, suffix, onChange)
  if not selector then return end
  selector.percentMin = minv or 0
  selector.percentMax = maxv or 99
  selector.percentStep = step or 1
  selector.percentSuffix = suffix or '%'
  selector.percentValue = math.max(selector.percentMin, math.min(selector.percentMax, tonumber(value) or 0))
  selector.onPercentChange = onChange
  -- label lives inside the 'bg' child, so it must be looked up recursively
  local lbl = selector:recursiveGetChildById('label')
  if lbl then lbl:setText(selector.percentValue .. selector.percentSuffix) end
end

function onPercentStep(selector, delta)
  if not selector or (selector.isEnabled and not selector:isEnabled()) then return end
  local v = (selector.percentValue or 0) + delta * (selector.percentStep or 1)
  v = math.max(selector.percentMin or 0, math.min(selector.percentMax or 99, v))
  selector.percentValue = v
  local lbl = selector:recursiveGetChildById('label')
  if lbl then lbl:setText(v .. (selector.percentSuffix or '%')) end
  if selector.onPercentChange then selector.onPercentChange(v) end
end

function getPercentValue(selector) return (selector and selector.percentValue) or 0 end

-- Mage-shield checks run as INDEPENDENT eventTable timers (utamo / exana / potion),
-- so each fires on its own schedule and a throttle/condition in one never blocks the
-- others -- and they are fully independent from the healer/shooter checks too.
-- mageCtx() gathers the shared player state once per call (nil = not applicable now).
local function mageCtx()
  if not hotkeyHelperStatus or not mageShieldIsMage then return nil end
  local p = g_game.getLocalPlayer()
  if not p or not g_game.isOnline() then return nil end
  local maxhp = p:getMaxHealth()
  if maxhp <= 0 then return nil end
  local now = g_clock.millis()
  local shieldRem = (p.getManaShield and p:getManaShield()) or 0
  local shieldMax = (p.getMaxManaShield and p:getMaxManaShield()) or 0
  return {
    p = p, now = now,
    life = p:getHealth() / maxhp * 100,
    mana = p:getMana(),
    shieldActive = shieldRem > 0,
    shieldPct = (shieldMax > 0) and (shieldRem / shieldMax * 100) or 0,
    vitaOnCd = getSpellCooldown(MAGIC_SHIELD_SPELL_ID) > now or getGroupSpellCooldown(MAGIC_SHIELD_GROUP) > now,
  }
end

-- 1) Utamo Vita: keep the shield up (cast on low life, or renew when shield is low).
local utamoNextCast = 0
local function checkUtamoVita()
  local u = helperConfig.mageShield and helperConfig.mageShield.utamo
  if not u or not u.enabled then return end
  local c = mageCtx(); if not c then return end
  if c.now < utamoNextCast or c.vitaOnCd or c.mana < 50 then return end
  local cast = c.life <= (u.life or 0)
  if not cast and u.renew and c.shieldActive and c.shieldPct < (u.renewShield or 0) then cast = true end
  if cast then
    g_game.talk('utamo vita')
    utamoNextCast = c.now + 500 -- cover the cooldown-packet latency window
  end
end
eventTable.checkUtamoVita.action = checkUtamoVita

-- 2) Exana Vita: drop the shield when safe (life above threshold AND shield up).
local exanaNextCast = 0
local function checkExanaVita()
  local e = helperConfig.mageShield and helperConfig.mageShield.exana
  if not e or not e.enabled then return end
  local c = mageCtx(); if not c then return end
  if c.now < exanaNextCast or c.vitaOnCd or not c.shieldActive then return end
  if c.life > (e.life or 100) then
    g_game.talk('exana vita')
    exanaNextCast = c.now + 500
  end
end
eventTable.checkExanaVita.action = checkExanaVita

-- 3) Magic Shield Potion: gated by life / shield% / fear, optionally only on vita CD.
local potionNextUse = 0
local function checkShieldPotion()
  local po = helperConfig.mageShield and helperConfig.mageShield.potion
  if not po or not po.enabled then return end
  local c = mageCtx(); if not c then return end
  if c.now < potionNextUse then return end
  local feared = (PlayerStates and PlayerStates.Feared and c.p.hasState and c.p:hasState(PlayerStates.Feared)) or false
  local trigger = false
  if po.forceOnFear and feared then trigger = true end
  if po.life > 0 and c.life <= po.life then trigger = true end
  if po.shield > 0 and c.shieldActive and c.shieldPct < po.shield then trigger = true end
  -- "only on vita CD" only makes sense if Utamo Vita is enabled; otherwise ignore it.
  local onlyVitaCd = po.onlyVitaCd and (helperConfig.mageShield.utamo and helperConfig.mageShield.utamo.enabled)
  if trigger and not (onlyVitaCd and not c.vitaOnCd) then
    g_game.useInventoryItem(MAGIC_SHIELD_POTION_ID)
    potionNextUse = c.now + 1000 -- potions have a ~1s use exhaust
  end
end
eventTable.checkShieldPotion.action = checkShieldPotion

-- Enable/disable toggles (also driven by the hotkeys). Update the checkbox + save.
function toggleUtamoEnabled()
  local u = helperConfig.mageShield.utamo; u.enabled = not u.enabled
  local cb = msChild('msUtamoEnable'); if cb then cb:setChecked(u.enabled) end
  saveSettings()
end
function toggleExanaEnabled()
  local e = helperConfig.mageShield.exana; e.enabled = not e.enabled
  local cb = msChild('msExanaEnable'); if cb then cb:setChecked(e.enabled) end
  saveSettings()
end

-- @onCheckChange / @onValueChange handlers (from the tools panel widgets).
function mageShieldOnCheck(which, checked)
  local ms = helperConfig.mageShield
  if which == 'utamo' then ms.utamo.enabled = checked
  elseif which == 'exana' then ms.exana.enabled = checked
  elseif which == 'potion' then ms.potion.enabled = checked end
  saveSettings()
end
function mageShieldOnLife(which, value)
  value = math.max(0, math.min(99, tonumber(value) or 0))
  if which == 'utamo' then helperConfig.mageShield.utamo.life = value
  elseif which == 'exana' then helperConfig.mageShield.exana.life = value end
  saveSettings()
end

-- Hotkey binding (cavebot-style: own combo, simple g_keyboard bind).
local function bindMageHotkeys()
  local root = g_ui.getRootWidget()
  for which, combo in pairs(mageShieldBound) do
    if combo and #combo > 0 then
      g_keyboard.unbindKeyDown(combo, which == 'utamo' and toggleUtamoEnabled or toggleExanaEnabled, root)
    end
  end
  mageShieldBound = {}
  local cu = helperConfig.mageShield.utamo.hotkey or ''
  local ce = helperConfig.mageShield.exana.hotkey or ''
  if #cu > 0 then g_keyboard.bindKeyDown(cu, toggleUtamoEnabled, root); mageShieldBound.utamo = cu end
  if #ce > 0 then g_keyboard.bindKeyDown(ce, toggleExanaEnabled, root); mageShieldBound.exana = ce end
end

local function syncMageHotkeyButtons()
  local cu = helperConfig.mageShield.utamo.hotkey or ''
  local ce = helperConfig.mageShield.exana.hotkey or ''
  local bu = msChild('msUtamoKey')
  if bu then
    bu:setTooltip((#cu > 0) and tr('Utamo Vita hotkey: %s (click to change)', cu) or tr('Set a hotkey to toggle Utamo Vita'))
  end
  local be = msChild('msExanaKey')
  if be then
    be:setTooltip((#ce > 0) and tr('Exana Vita hotkey: %s (click to change)', ce) or tr('Set a hotkey to toggle Exana Vita'))
  end
end

-- Key-capture window (MageHotkeyWindow). `which` = 'utamo' | 'exana'.
function mageSetKey(which)
  local cfgKey = (which == 'utamo') and helperConfig.mageShield.utamo or helperConfig.mageShield.exana
  local window = g_ui.createWidget('MageHotkeyWindow', g_ui.getRootWidget())
  window:show(); window:raise(); window:focus(); window:grabKeyboard()
  g_client.setInputLockWidget(window)
  window.display:setText(cfgKey.hotkey or '')
  local picked = cfgKey.hotkey or ''
  window.onKeyDown = function(_, keyCode, mods, keyText)
    local combo = determineKeyComboDesc(keyCode, mods, keyText)
    if combo == 'Shift' or combo == 'Ctrl' or combo == 'Alt' then return true end
    picked = combo
    window.display:setText(combo)
    local used = false
    pcall(function() used = (KeyBinds and KeyBinds:isUsedHotkey(combo)) and true or false end)
    window.warning:setVisible(used)
    return true
  end
  local function finish()
    g_client.setInputLockWidget(nil)
    window:destroy()
  end
  window.buttonOk.onClick = function()
    cfgKey.hotkey = picked or ''
    bindMageHotkeys(); syncMageHotkeyButtons(); saveSettings(); finish()
  end
  window.buttonClear.onClick = function()
    cfgKey.hotkey = ''
    bindMageHotkeys(); syncMageHotkeyButtons(); saveSettings(); finish()
  end
  window.buttonClose.onClick = finish
end

-- Settings modals.
function openUtamoSettings()
  local u = helperConfig.mageShield.utamo
  local w = g_ui.createWidget('MageShieldSettings', g_ui.getRootWidget())
  w.renewCheck:setChecked(u.renew and true or false)
  initPercentSelector(w.renewBox, u.renewShield or 50, 1, 99, 1, '%')
  w.cancelButton.onClick = function() w:destroy() end
  w.saveButton.onClick = function()
    u.renew = w.renewCheck:isChecked()
    u.renewShield = getPercentValue(w.renewBox)
    saveSettings(); w:destroy()
  end
end

function openPotionSettings()
  local po = helperConfig.mageShield.potion
  local w = g_ui.createWidget('MageShieldPotionSettings', g_ui.getRootWidget())
  initPercentSelector(w.lifeBox, po.life or 0, 0, 99, 1, '%')
  initPercentSelector(w.shieldBox, po.shield or 0, 0, 99, 1, '%')
  -- "only on vita CD" is only meaningful while Utamo Vita is enabled.
  local utamoOn = (helperConfig.mageShield.utamo and helperConfig.mageShield.utamo.enabled) and true or false
  w.vitaCdCheck:setChecked(po.onlyVitaCd and utamoOn)
  w.vitaCdCheck:setEnabled(utamoOn)
  w.fearCheck:setChecked(po.forceOnFear and true or false)
  w.cancelButton.onClick = function() w:destroy() end
  w.saveButton.onClick = function()
    po.life   = getPercentValue(w.lifeBox)
    po.shield = getPercentValue(w.shieldBox)
    po.onlyVitaCd  = w.vitaCdCheck:isChecked()
    po.forceOnFear = w.fearCheck:isChecked()
    saveSettings(); w:destroy()
  end
end

-- Mount: show only for mages, sync widgets from config, (re)bind hotkeys.
function setupMageShield()
  -- mageShieldPanel is a SIBLING of the inner 'toolsPanel' (both under the ToolsPanel
  -- tab root), so look it up from the content panel, not from toolsPanel.
  mageShieldPanel = helper and helper.contentPanel and helper.contentPanel:recursiveGetChildById('mageShieldPanel') or nil
  local p = g_game.getLocalPlayer()
  local voc = p and p:getVocation() or 0
  -- Vocation may not be synced yet right at onGameStart; retry until it is.
  if voc == 0 then
    if g_game.isOnline() then scheduleEvent(setupMageShield, 1000) end
    return
  end
  local tv = translateVocation(voc)
  mageShieldIsMage = (tv == 5 or tv == 6) -- Sorcerer (ms) or Druid (ed)
  if mageShieldPanel then mageShieldPanel:setVisible(mageShieldIsMage) end
  -- NOTE: the helper window's height is owned by loadMenu(), which resizes per tab on every
  -- open/tab switch (the tools tab already picks a taller size for mages so the Magic Shield
  -- panel fits). Don't set the height here -- it runs on game start regardless of the active
  -- tab and would clobber whatever tab loadMenu just sized.
  if not mageShieldIsMage then return end
  local ms = helperConfig.mageShield
  local function setup(id, fn) local w = msChild(id); if w then fn(w) end end
  setup('msUtamoEnable', function(w) w:setChecked(ms.utamo.enabled and true or false) end)
  initPercentSelector(msChild('msUtamoLife'), ms.utamo.life or 30, 0, 99, 1, '%', function(v) ms.utamo.life = v; saveSettings() end)
  setup('msExanaEnable', function(w) w:setChecked(ms.exana.enabled and true or false) end)
  initPercentSelector(msChild('msExanaLife'), ms.exana.life or 80, 0, 99, 1, '%', function(v) ms.exana.life = v; saveSettings() end)
  setup('msPotionEnable', function(w) w:setChecked(ms.potion.enabled and true or false) end)
  syncMageHotkeyButtons()
  bindMageHotkeys()
end

function online()
  local benchmark = g_clock.millis()
  player = g_game.getLocalPlayer()

  reset()
  loadSettings()
  loadProfileOptions()
  onLoadHelperData()
  setupMageShield() -- mage-only magic-shield tools: show + sync + bind hotkeys

  if Cavebot then Cavebot.online() end
  if Scripting then Scripting.online() end

  helperConfig.currentLockedTargetId = 0
  helperEvents.helperCycleEvent = cycleEvent(helperCycleEvent, helperEvents.helperCycleTimer)

  -- Sync the Friend Healing / Gran Sio panels (radio, enable, %, list) from the
  -- now-loaded config and fill the boxes (PT party members / saved List names).
  setupHealRadio("friend")
  setupHealRadio("gran")
  consoleln("Helper loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function offline()
  if Cavebot then Cavebot.offline() end
  if Scripting then Scripting.offline() end

  -- unbind mage-shield hotkeys for this session
  local root = g_ui.getRootWidget()
  for which, combo in pairs(mageShieldBound) do
    if combo and #combo > 0 then
      g_keyboard.unbindKeyDown(combo, which == 'utamo' and toggleUtamoEnabled or toggleExanaEnabled, root)
    end
  end
  mageShieldBound = {}

  local presets = presetsPanel:recursiveGetChildById('presets')
  if presets then
    presets:clear()
  end
  removeEvent(helperEvents.helperCycleEvent)
  hide()
  helperTracker:close()
  helperTracker:setParent(nil)
end

function onSpellCooldown(spellId, delay)
  spellsCooldown[spellId] = g_clock.millis() + delay
end

function onSpellGroupCooldown(groupId, delay)
  groupsCooldown[groupId] = g_clock.millis() + delay
end

function onMultiUseCooldown(time)
  multiUseExDelay = g_clock.millis() + time
end

function onUpdateSpellArea(energyWaveEnlarged)
  if energyWaveEnlarged then
    SpellInfo.Default["Energy Wave"].area = SpellAreas.AREA_SQUAREWAVE6
  else
    SpellInfo.Default["Energy Wave"].area = SpellAreas.AREA_SQUAREWAVE4
  end
end

function getShooterProfileCount()
  local i = 0
  for n, j in pairs(helperConfig.shooterProfiles) do
    i = i + 1
  end
  return i
end

function getShooterProfile()
  local profile = helperConfig.shooterProfiles[helperConfig.selectedShooterProfile]
  if not profile then
    return defaultShooterProfile
  end
  return profile
end

function loadMenu(menuId)
  local buttons = {
    healMenuButton = 'healingMenu',
    toolsMenuButton = 'toolsMenu',
    shooterMenuButton = 'shooterMenu',
    cavebotMenuButton = 'cavebotMenu',
    scriptingMenuButton = 'scriptingMenu'
  }

  for buttonName, buttonId in pairs(buttons) do
    local button = helper.contentPanel.optionsTabBar:getChildById(buttonId)
    if button then
      button:setChecked(false)
    end
  end

  local selectedButton = helper.contentPanel.optionsTabBar:getChildById(menuId)
  if selectedButton then
    selectedButton:setChecked(true)
  end

  if Cavebot and Cavebot.hidePanel then Cavebot.hidePanel() end
  if Scripting and Scripting.hidePanel then Scripting.hidePanel() end

  local currentPlayer = g_game.getLocalPlayer()
  if not currentPlayer then
    -- If no player, just show default layout
    healingPanel:show(true)
    toolsPanel:hide()
    shooterPanel:hide()
    helper:setSize(tosize("295 240"))
    return
  end

  local vocationId = translateVocation(currentPlayer:getVocation())

  if menuId == 'healingMenu' then
    healingPanel:show(true)
    toolsPanel:hide()
    shooterPanel:hide()
    if vocationId == 8 then -- Knight
      helper:setSize(tosize("295 278"))
      healPanel:setHeight(160)
      friendHealingPanel:setVisible(false)
      granSioPanel:setVisible(false)
      spellButton2:setVisible(true)
      rmvPercentButton2:setVisible(true)
      spellPercentBg2:setVisible(true)
      addPercentButton2:setVisible(true)
      potionButton2:setVisible(true)
      rmvPotionPercentButton2:setVisible(true)
      potionPercentBg2:setVisible(true)
      addPotionPercentButton2:setVisible(true)
      priority2:setVisible(true)
      priorityButton1:setTooltip(
      "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
      priorityButton2:setTooltip(
      "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
      priorityButton3:setTooltip(
      "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
    elseif vocationId == 7 then -- Paladin
      helper:setSize(tosize("295 278"))
      friendHealingPanel:setVisible(false)
      granSioPanel:setVisible(false)
      healPanel:setHeight(160)
      rmvPercentButton2:setVisible(true)
      spellPercentBg2:setVisible(true)
      addPercentButton2:setVisible(true)
      potionButton2:setVisible(true)
      rmvPotionPercentButton2:setVisible(true)
      potionPercentBg2:setVisible(true)
      addPotionPercentButton2:setVisible(true)
      priority2:setVisible(true)
      priorityButton1:setTooltip(
      "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.\nClick on this button to change the potion priority:\n  - Icon: Blue (Mana Priority)\n  - Icon: Red  (Health Priority)")
      priorityButton2:setTooltip(
      "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.\nClick on this button to change the potion priority:\n  - Icon: Blue (Mana Priority)\n  - Icon: Red  (Health Priority)")
      priorityButton3:setTooltip(
      "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.\nClick on this button to change the potion priority:\n  - Icon: Blue (Mana Priority)\n  - Icon: Red  (Health Priority)")
    elseif vocationId == 5 then -- Sorcerer
      helper:setSize(tosize("295 363"))
      healPanel:setHeight(120)
      friendHealingPanel:setVisible(true)
      granSioPanel:setVisible(false)
      rmvPercentButton2:setVisible(false)
      spellPercentBg2:setVisible(false)
      addPercentButton2:setVisible(false)
      potionButton2:setVisible(false)
      rmvPotionPercentButton2:setVisible(false)
      potionPercentBg2:setVisible(false)
      addPotionPercentButton2:setVisible(false)
      priority2:setVisible(false)
      priorityButton1:setTooltip(
      "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
      priorityButton2:setTooltip(
      "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
    elseif vocationId == 6 then -- Druid
      helper:setSize(tosize("295 490"))
      healPanel:setHeight(120)
      friendHealingPanel:setVisible(true)
      granSioPanel:setVisible(true)
      rmvPercentButton2:setVisible(false)
      spellPercentBg2:setVisible(false)
      addPercentButton2:setVisible(false)
      potionButton2:setVisible(false)
      rmvPotionPercentButton2:setVisible(false)
      potionPercentBg2:setVisible(false)
      addPotionPercentButton2:setVisible(false)
      priority2:setVisible(false)
      priorityButton1:setTooltip(
      "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
      priorityButton2:setTooltip(
      "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
    elseif vocationId == 9 then -- Monk
      helper:setSize(tosize("295 405"))
      healPanel:setHeight(160)
      friendHealingPanel:setVisible(true)
      granSioPanel:setVisible(false)
      rmvPercentButton2:setVisible(true)
      spellPercentBg2:setVisible(true)
      addPercentButton2:setVisible(true)
      potionButton2:setVisible(true)
      rmvPotionPercentButton2:setVisible(true)
      potionPercentBg2:setVisible(true)
      addPotionPercentButton2:setVisible(true)
      priority2:setVisible(true)
      priorityButton1:setTooltip(
      "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.\nClick on this button to change the potion priority:\n  - Icon: Blue (Mana Priority)\n  - Icon: Red  (Health Priority)")
      priorityButton2:setTooltip(
      "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.\nClick on this button to change the potion priority:\n  - Icon: Blue (Mana Priority)\n  - Icon: Red  (Health Priority)")
      priorityButton3:setTooltip(
      "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.\nClick on this button to change the potion priority:\n  - Icon: Blue (Mana Priority)\n  - Icon: Red  (Health Priority)")
    else
      helper:setSize(tosize("295 240"))
      healPanel:setHeight(120)
      friendHealingPanel:setVisible(false)
      granSioPanel:setVisible(false)
      rmvPercentButton2:setVisible(false)
      spellPercentBg2:setVisible(false)
      addPercentButton2:setVisible(false)
      potionButton2:setVisible(false)
      rmvPotionPercentButton2:setVisible(false)
      potionPercentBg2:setVisible(false)
      addPotionPercentButton2:setVisible(false)
      priority2:setVisible(false)
      priorityButton1:setTooltip(
      "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
      priorityButton2:setTooltip(
      "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
    end
    applyPotionPriorityButtons() -- reflect each potion's Health/Mana mode (red/blue icon + tooltip)
  elseif menuId == 'toolsMenu' then
    -- Mages get a taller window so the Magic Shield sub-panel fits below the tools box.
    -- The shield panel's bottom sits at window y=437 and the footer separator at ~h-44,
    -- so the window needs >= ~481 to keep them from overlapping; 495 leaves a small gap.
    -- Non-mages have no shield panel, but the toolsPanel frame itself ends at window y=293
    -- (15 margin + 12 + 36 tab bar + 5 + 225 panel). With the footer separator at h-44 the
    -- window needs >= ~337 or the Others Tools column (Auto Bless) collides with the status
    -- block -- the old 275 cut ~30px off the panel. 350 clears it with the same ~14px gap.
    helper:setSize((vocationId == 5 or vocationId == 6) and tosize("295 495") or tosize("295 350"))
    healingPanel:hide()
    shooterPanel:hide()
    toolsPanel:show(true)
  elseif menuId == 'shooterMenu' then
    healingPanel:hide()
    toolsPanel:hide()
    shooterPanel:show(true)
    if vocationId == 8 or vocationId == 9 then -- Knight
      helper:setSize(tosize("295 487"))
      runePanel:setVisible(false)
      spellPanel:setHeight(245)
      attackSpellPanel3:setVisible(true)
      attackSpellPanel4:setVisible(true)
      enableButtons:addAnchor(AnchorTop, 'spellPanel', AnchorBottom)
      enableButtons:setMarginTop(5)
    else
      helper:setSize(tosize("295 533"))
      runePanel:setVisible(true)
      spellPanel:setHeight(163)
      attackSpellPanel3:setVisible(false)
      attackSpellPanel4:setVisible(false)
      enableButtons:addAnchor(AnchorTop, 'prev', AnchorBottom)
      enableButtons:setMarginTop(5)
    end
  elseif menuId == 'cavebotMenu' then
    healingPanel:hide()
    toolsPanel:hide()
    shooterPanel:hide()
    helper:setSize(tosize("295 486"))
    if Cavebot then Cavebot.showPanel() end
  elseif menuId == 'scriptingMenu' then
    healingPanel:hide()
    toolsPanel:hide()
    shooterPanel:hide()
    helper:setSize(tosize("295 486"))
    if Scripting then Scripting.showPanel() end
  end
end

function onCreatureAppear(creature)
  if creature:isPlayer() then return end
  if creature.isSummon and creature:isSummon() then return end
  if creature:getHealthPercent() <= 0 then return end
  if not spectators[creature:getId()] and creature:isMonster() then
    spectators[creature:getId()] = creature
  end
end

function onCreatureDisappear(creature)
  if spectators[creature:getId()] then
    spectators[creature:getId()] = nil
  end
end

--[[ Events ]] --
function assignTrainingSpell(button, isHaste)
  local radio = UIRadioGroup.create()
  window = g_ui.loadUI('styles/spell', g_ui.getRootWidget())
  if not window then
    return true
  end

  window:show(true)
  window:raise()
  window:focus()
  g_client.setInputLockWidget(window)
  helper:hide()

  local windowHeader = isHaste and "Assign Haste Spell" or "Assign Training Spell"
  window:setText(windowHeader)

  local currentPlayer = player or g_game.getLocalPlayer()
  if not currentPlayer then
    return true
  end

  local playerVocation = translateVocation(currentPlayer:getVocation())
  local spells = modules.gamelib.SpellInfo['Default']

  for spellName, spellData in pairs(spells) do
    if isHaste and not table.contains(hasteWhiteList[playerVocation], spellData.id) then
      goto continue
    end

    if not isHaste and not (table.contains(Spells.getGroupIds(spellData), 3) or table.contains(Spells.getGroupIds(spellData), 2)) then
      goto continue
    end

    if not isHaste and table.contains(hasteWhiteList[playerVocation], spellData.id) then
      goto continue
    end

    if table.contains(spellData.vocations, playerVocation) and not ignoredTrainingSpells[spellData.id] then
      local widget = g_ui.createWidget('SpellPreview', window.contentPanel.spellList)
      local spellId = SpellIcons[spellData.icon][1]

      radio:addWidget(widget)
      widget:setId(spellData.id)
      widget:setText(spellName .. "\n" .. spellData.words)
      widget.voc = spellData.vocations
      widget.source = SpelllistSettings['Default'].iconsFolder
      widget.clip = Spells.getImageClipNormal(spellId, 'Default')
      widget.image:setImageSource(widget.source)
      widget.image:setImageClip(widget.clip)

      if spellData.level then
        widget.levelLabel:setVisible(true)
        widget.levelLabel:setText(string.format("Level: %d", spellData.level))
        if player:getLevel() < spellData.level then
          widget.image.gray:setVisible(true)
        end
      end

      local primaryGroup = Spells.getPrimaryGroup(spellData)
      if primaryGroup ~= -1 then
        local offSet = 1
        if primaryGroup == 2 then
          offSet = (23 * (primaryGroup - 1))
        elseif primaryGroup == 3 then
          offSet = (23 * (primaryGroup - 1)) - 1
        end
        widget.imageGroup:setImageClip(offSet .. " 25 20 20")
        widget.imageGroup:setVisible(true)
      end
    end

    ::continue::
  end

  -- Order the spell list
  local widgets = window.contentPanel.spellList:getChildren()
  table.sort(widgets, function(a, b) return a:getText() < b:getText() end)
  for i, widget in ipairs(widgets) do
    window.contentPanel.spellList:moveChildToIndex(widget, i)
  end

  -- Callback of radio
  radio.onSelectionChange = function(widget, selected)
    if selected then
      window.contentPanel.preview:setText(selected:getText())
      window.contentPanel.preview.image:setImageSource(selected.source)
      window.contentPanel.preview.image:setImageClip(selected.clip)
      window.contentPanel.paramLabel:setOn(selected.param)
      window.contentPanel.paramText:setEnabled(selected.param)
      window.contentPanel.paramText:clearText()
      window.contentPanel.spellList:ensureChildVisible(widget)
    end
  end

  if window.contentPanel.spellList:getChildren() then
    radio:selectWidget(window.contentPanel.spellList:getChildren()[1])
  end

  local okFunc = function(destroy)
    local selected = radio:getSelectedWidget()
    if not selected then return end

    local spellIcon = selected.source
    local spellClip = selected.clip
    local spellId = selected:getId()
    local spellName = selected:getText():match("^(.-)\n")
    local spellWords = selected:getText():match("\n(.+)")

    local slotID = tonumber(button:getId():match("%d+"))
    if isHaste then
      helperConfig.haste[1].id = tonumber(spellId)
    else
      helperConfig.training[1].id = tonumber(spellId)
      if helperConfig.training[1].percent == 0 then
        helperConfig.training[1].percent = 100
        updateTrainingPercent('spellTrainingButton0', helperConfig.training[1].percent)
      end
    end

    g_client.setInputLockWidget(nil)
    button:setImageSource(spellIcon)
    button:setImageClip(spellClip)
    button:setBorderColorTop("#1b1b1b")
    button:setBorderColorLeft("#1b1b1b")
    button:setBorderColorRight("#757575")
    button:setBorderColorBottom("#757575")
    button:setBorderWidth(1)
    button:setTooltip("Spell: " .. spellName .. "\nWords: " .. spellWords)

    if destroy then
      helper:show(true)
      window:destroy()
    end
  end

  local cancelFunc = function()
    helper:show(true)
    g_client.setInputLockWidget(nil)
    window:destroy()
  end

  window.contentPanel.buttonOk.onClick = function() okFunc(true) end
  window.contentPanel.buttonApply.onClick = function() okFunc(false) end
  window.contentPanel.buttonClose.onClick = cancelFunc
  window.contentPanel.onEnter = function() okFunc(true) end
  window.onEscape = cancelFunc
end

local function invalidPresetName(name)
  if helperConfig.shooterProfiles[name] then
    return true, "There is already a preset with this name."
  elseif name:len() == 0 then
    return true, "The name cannot be empty."
  elseif name:len() > 7 then
    return true, "The name cannot be longer than 7 characters."
  elseif name:match("[^%w]") then
    return true, "The name cannot contain special characters or spaces."
  end
  return false
end

function sendRenameOrAddWindow(isRename)
  local radio = UIRadioGroup.create()
  window = g_ui.loadUI('styles/shooterPreset', g_ui.getRootWidget())
  if not window then
    return true
  end

  if isRename then
    window:setText("Rename shooter preset")
    window.contentPanel.target:setText(helperConfig.selectedShooterProfile)
  else
    window:setText("Add shooter preset")
    window.contentPanel.target:setText("")
  end


  local options = presetsPanel:recursiveGetChildById('presets')

  window:show(true)
  window:raise()
  window:focus()
  window.contentPanel.target:focus()
  g_client.setInputLockWidget(window)
  helper:hide()

  local onWrite = function()
    local warning = window.contentPanel.warning
    local block = false
    local text = window.contentPanel.target:getText()
    local invalid, message = invalidPresetName(text)
    if invalid then
      warning:setVisible(true)
      warning:setTooltip(message)
    elseif not invalid and warning:isVisible() then
      warning:setVisible(false)
      warning:setTooltip('')
    end
  end

  local renameConfirm = function()
    local input = window.contentPanel.target:getText()
    if input == helperConfig.selectedShooterProfile then
      return
    end

    if invalidPresetName(input) then
      return
    end

    local oldProfileName = helperConfig.selectedShooterProfile
    local profileConfig = helperConfig.shooterProfiles[oldProfileName]
    if profileConfig then
      helperConfig.shooterProfiles[input] = profileConfig
      helperConfig.selectedShooterProfile = input
      options:addOption(input)
      options:setCurrentOption(input)
      helperConfig.shooterProfiles[oldProfileName] = nil
      options:removeOption(oldProfileName)
    end

    helper:show()
    window:destroy()
  end


  local addConfirm = function()
    local input = window.contentPanel.target:getText()
    for profileName, _ in pairs(helperConfig.shooterProfiles) do
      if profileName == input then
        return -- repeated profile
      end
    end

    if invalidPresetName(input) then
      return
    end

    local default = deepCopy(defaultShooterProfile)
    helperConfig.shooterProfiles[input] = default

    options:addOption(input)
    options:setCurrentOption(input)

    helper:show()
    window:destroy()
  end

  local cancel = function()
    helper:show()
    g_client.setInputLockWidget(nil)
    window:destroy()
  end

  window.contentPanel.cancelButton.onClick = cancel
  window.onEscape = cancel
  window.contentPanel.target.onTextChange = function() onWrite() end
  if isRename then
    window.contentPanel.okButton.onClick = function() renameConfirm() end
    window.contentPanel.onEnter = function() renameConfirm() end
  else
    window.contentPanel.okButton.onClick = function() addConfirm() end
    window.contentPanel.onEnter = function() addConfirm() end
  end
end

function assignSpell(button, groupName, groups, tableToAssign)
  local radio = UIRadioGroup.create()
  window = g_ui.loadUI('styles/spell', g_ui.getRootWidget())
  if not window then
    return true
  end

  window:show(true)
  window:raise()
  window:focus()
  g_client.setInputLockWidget(window)
  helper:hide()

  window:setText("Assign " .. groupName .. " Spell")

  local profile = getShooterProfile()
  local playerVocation = translateVocation(player:getVocation())
  local spells = modules.gamelib.SpellInfo['Default']

  for spellName, spellData in pairs(spells) do
    local groupIds = Spells.getGroupIds(spellData)
    local function containsAnyGroup(groups, targetGroups)
      for _, group in ipairs(targetGroups) do
        if table.contains(groups, group) then
          return true
        end
      end
      return false
    end
    if containsAnyGroup(groupIds, groups) and table.contains(spellData.vocations, playerVocation) and not ignoredSpellsIds[spellData.id] then
      if player:getLevel() < spellData.level or not playerHasSpell(player, spellData.id) then
        goto continue
      end
      local widget = g_ui.createWidget('SpellPreview', window.contentPanel.spellList)
      local spellId = SpellIcons[spellData.icon][1]
      radio:addWidget(widget)
      widget:setId(spellData.id)
      widget:setText(spellName .. "\n" .. spellData.words)
      widget.voc = spellData.vocations
      widget.source = SpelllistSettings['Default'].iconsFolder
      widget.clip = Spells.getImageClipNormal(spellId, 'Default')
      widget.image:setImageSource(widget.source)
      widget.image:setImageClip(widget.clip)

      if spellData.level then
        widget.levelLabel:setVisible(true)
        widget.levelLabel:setText(string.format("Level: %d", spellData.level))
        if player:getLevel() < spellData.level then
          widget.image.gray:setVisible(true)
        end
      end

      local primaryGroup = Spells.getPrimaryGroup(spellData)
      if primaryGroup ~= -1 then
        local offSet = 1
        if primaryGroup == 2 then
          offSet = (23 * (primaryGroup - 1))
        elseif primaryGroup == 3 then
          offSet = (23 * (primaryGroup - 1)) - 1
        end
        widget.imageGroup:setImageClip(offSet .. " 25 20 20")
        widget.imageGroup:setVisible(true)
      end
    end
    ::continue::
  end

  -- sort alphabetically
  local widgets = window.contentPanel.spellList:getChildren()
  table.sort(widgets, function(a, b) return a:getText() < b:getText() end)
  for i, widget in ipairs(widgets) do
    window.contentPanel.spellList:moveChildToIndex(widget, i)
  end

  -- callback
  radio.onSelectionChange = function(widget, selected)
    if selected then
      window.contentPanel.preview:setText(selected:getText())
      window.contentPanel.preview.image:setImageSource(selected.source)
      window.contentPanel.preview.image:setImageClip(selected.clip)
      window.contentPanel.paramLabel:setOn(selected.param)
      window.contentPanel.paramText:setEnabled(selected.param)
      window.contentPanel.paramText:clearText()
      window.contentPanel.spellList:ensureChildVisible(widget)
    end
  end

  if window.contentPanel.spellList:getChildren() then
    radio:selectWidget(window.contentPanel.spellList:getChildren()[1])
  end

  window:recursiveGetChildById('tick'):setChecked(true)
  window:recursiveGetChildById('tick'):setEnabled(false)

  local okFunc = function(destroy, profile)
    local selected = radio:getSelectedWidget()
    if not selected then return end

    local profile = getShooterProfile()
    local spellIcon = selected.source
    local spellClip = selected.clip
    local spellId = selected:getId()
    local spellName = selected:getText():match("^(.-)\n")
    local spellWords = selected:getText():match("\n(.+)")

    local slotID = tonumber(button:getId():match("%d+"))
    if button:getId():find("attackSpellButton") then
      profile.spells[slotID + 1].id = tonumber(spellId)
    else
      tableToAssign[slotID + 1].id = tonumber(spellId)
    end

    g_client.setInputLockWidget(nil)
    button:setImageSource(spellIcon)
    button:setImageClip(spellClip)
    button:setBorderColorTop("#1b1b1b")
    button:setBorderColorLeft("#1b1b1b")
    button:setBorderColorRight("#757575")
    button:setBorderColorBottom("#757575")
    button:setBorderWidth(1)
    button:setTooltip("Spell: " .. spellName .. "\nWords: " .. spellWords)

    if button:getId():find("attackSpellButton") then
      local creaturesMin = shooterPanel:recursiveGetChildById("countMinCreature" .. slotID)
      local forceCast = shooterPanel:recursiveGetChildById("conditionSetting" .. slotID)
      local selfCast = shooterPanel:recursiveGetChildById("selfCast" .. slotID)
      local spell = Spells.getSpellByClientId(tonumber(spellId))
      if spell then
        if table.contains(bothCastTypeSpells, spell.id) then   -- divine grenade self cast
          if not selfCast then
            selfCast = g_ui.createWidget('CheckBox', creaturesMin:getParent())
            local style = {
              ["width"] = 12,
              ["anchors.top"] = "countMinCreature" .. slotID .. ".top",
              ["anchors.left"] = "countMinCreature" .. slotID .. ".right",
              ["margin-top"] = 6,
              ["margin-left"] = 5
            }
            selfCast:mergeStyle(style)
            selfCast:setId('selfCast' .. slotID)
            selfCast:setTooltip('Cast on yourself')
            selfCast:setVisible(true)
            selfCast.onCheckChange = function() toggleSelfCast(selfCast:getId():match("%d+"), selfCast:isChecked()) end
          end
        end
        if selfCast and not table.contains(bothCastTypeSpells, spell.id) then
          profile.spells[slotID + 1].selfCast = false
          selfCast:destroy()
        end
        if (spell.range > 0 or not spell.area) and not table.contains(bothCastTypeSpells, spell.id) then
          profile.spells[slotID + 1].creatures = 1
          creaturesMin:setCurrentOption("1+")
          creaturesMin:disable()
          if forceCast then
            forceCast:setChecked(profile.spells[slotID + 1].forceCast)
            forceCast:setVisible(true)
          end
        else
          creaturesMin:enable()
          if forceCast then
            forceCast:setChecked(false)
            forceCast:setVisible(false)
            profile.spells[slotID + 1].forceCast = false
          end
        end
      end
    end
    if destroy then
      helper:show()
      window:destroy()
    end
  end

  local cancelFunc = function()
    helper:show()
    g_client.setInputLockWidget(nil)
    window:destroy()
  end

  window.contentPanel.buttonOk.onClick = function() okFunc(true) end
  window.contentPanel.buttonApply.onClick = function() okFunc(false) end
  window.contentPanel.buttonClose.onClick = cancelFunc
  window.contentPanel.onEnter = function() okFunc(true) end
  window.onEscape = cancelFunc
end

function assignRune(button, groupName, groups, tableToAssign)
  g_mouse.updateGrabber(mouseGrabberWidget, 'target')
  mouseGrabberWidget:grabMouse()
  helper:hide()
  g_mouse.pushCursor('target')
  mouseGrabberWidget.onMouseRelease = function(self, mousePosition, mouseButton)
    onAssignRune(self, mousePosition, mouseButton, button)
  end
end

function onAssignRune(self, mousePosition, mouseButton, button)
  g_mouse.updateGrabber(mouseGrabberWidget, 'target')
  mouseGrabberWidget:ungrabMouse()
  helper:show()
  g_mouse.popCursor('target')
  mouseGrabberWidget.onMouseRelease = nil

  local rootWidget = g_ui.getRootWidget()
  if not rootWidget then
    return true
  end

  local clickedWidget = rootWidget:recursiveGetChildByPos(mousePosition, false)
  if not clickedWidget then
    return true
  end

  local runeId = 0
  if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
    local item = clickedWidget:getItem()
    if item then
      runeId = item:getId()
    end
  elseif clickedWidget:getClassName() == 'UIGameMap' then
    local tile = clickedWidget:getTile(mousePosition)
    if tile then
      local topUseThing = tile:getTopUseThing()
      if topUseThing then
        runeId = topUseThing:getId()
      end
    end
  end

  local rune = Spells.getRuneSpellByItem(runeId)
  if rune and rune.group == 1 then
    if rune.vocations and not table.contains(rune.vocations, translateVocation(player:getVocation())) then
      modules.game_textmessage.displayFailureMessage(tr('Your vocation can not use this rune.'))
      return true
    end
    updateRuneButton(button, runeId, rune)
  else
    modules.game_textmessage.displayFailureMessage(tr('Invalid rune!'))
  end
end

function updateRuneButton(button, runeId, rune)
  button:setImageSource('/images/ui/item')

  if not button:getChildById('runeItem') then
    local itemWidget = g_ui.createWidget('RuneItem', button)
    itemWidget:setId('runeItem')
  end

  local itemWidget = button:getChildById('runeItem')
  itemWidget:setItemId(runeId)

  button:setTooltip(string.format(rune.name .. " %s", rune.area and "(Area Target)" or "(Single Target)"))

  local profile = getShooterProfile()
  local buttonId = button:getId()
  local slotID = tonumber(buttonId:match("%d+"))
  local creaturesMin = runePanel:recursiveGetChildById("countMinCreature" .. slotID)
  local forceCast = runePanel:recursiveGetChildById("conditionSetting" .. slotID)

  profile.runes[slotID + 1].id = runeId
  profile.runes[slotID + 1].creatures = profile.runes[slotID + 1].creatures

  local runeSpell = Spells.getRuneSpellByItem(runeId)
  if runeSpell and not runeSpell.area then
    creaturesMin:setCurrentOption("1+")
    creaturesMin:disable()
    forceCast:setChecked(profile.runes[slotID + 1].forceCast)
    forceCast:setVisible(true)
    profile.runes[slotID + 1].creatures = 1
    return
  end
  profile.runes[slotID + 1].forceCast = false
  forceCast:setChecked(false)
  forceCast:setVisible(false)
  creaturesMin:enable()
end

function getPotionInfoById(itemId)
  for _, potion in pairs(potionWhitelist) do
    if itemId == potion.id then
      return true, potion.name
    end
  end
  return false, "Unknown Potion"
end

function isHealthPotion(potionId)
  for _, potion in ipairs(potionWhitelist) do
    if potion.id == potionId and potion.type == "health" then
      return true
    end
  end
  return false
end

function isManaPotion(potionId)
  for _, potion in ipairs(potionWhitelist) do
    if potion.id == potionId and potion.type == "mana" then
      return true
    end
  end
  return false
end

-- The "I" toggle on each potion row decides which resource its % threshold checks:
-- priority 1 = Health (red icon), priority 2 = Mana (blue icon). A legacy/unset
-- priority (0) falls back to the potion's intrinsic type.
function potionMode(potion)
  if potion.priority == 1 then return "health" end
  if potion.priority == 2 then return "mana" end
  return isManaPotion(potion.id) and "mana" or "health"
end

function usePotion(potionId)
  local player = g_game.getLocalPlayer()
  if not player then
    return
  end

  local cooldown = getSpellCooldown(potionConfig.id)
  if cooldown > g_clock.millis() then
    return true
  end

  if multiUseExDelay > g_clock.millis() then
    return true
  end

  helperConfig.magicShooterOnHold = true

  local potionCount = player:getInventoryCount(potionId)
  if potionCount > 0 then
    g_game.doThing(false)
    g_game.useInventoryItemWith(potionId, player, 0, true)
    g_game.doThing(true)
    spellsCooldown[potionConfig.id] = g_clock.millis() + potionConfig.exhaustion
  end

  helperConfig.magicShooterOnHold = false
end

function assignPotionEvent(button)
  g_mouse.updateGrabber(mouseGrabberWidget, 'target')
  mouseGrabberWidget:grabMouse()
  helper:hide()
  g_mouse.pushCursor('target')
  mouseGrabberWidget.onMouseRelease = function(self, mousePosition, mouseButton)
    onAssignPotion(self, mousePosition, mouseButton, button)
  end
end

function onAssignPotion(self, mousePosition, mouseButton, button)
  g_mouse.updateGrabber(mouseGrabberWidget, 'target')
  mouseGrabberWidget:ungrabMouse()
  helper:show()
  g_mouse.popCursor('target')
  mouseGrabberWidget.onMouseRelease = nil

  local rootWidget = g_ui.getRootWidget()
  if not rootWidget then
    return true
  end

  local clickedWidget = rootWidget:recursiveGetChildByPos(mousePosition, false)
  if not clickedWidget then
    return true
  end

  local potionId = 0
  if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
    local item = clickedWidget:getItem()
    if item then
      potionId = item:getId()
    end
  elseif clickedWidget:getClassName() == 'UIGameMap' then
    local tile = clickedWidget:getTile(mousePosition)
    if tile then
      local topUseThing = tile:getTopUseThing()
      if topUseThing then
        potionId = topUseThing:getId()
      end
    end
  end

  local isPotion, potionName = getPotionInfoById(potionId)
  if isPotion then
    updatePotionButton(button, potionId, potionName)
  else
    modules.game_textmessage.displayFailureMessage(tr('Invalid potion!'))
  end
end

function updatePotionButton(button, potionId, potionName)
  button:setImageSource('/images/ui/item')

  if not button:getChildById('potionItem') then
    local itemWidget = g_ui.createWidget('PotionItem', button)
    itemWidget:setId('potionItem')
  end

  local itemWidget = button:getChildById('potionItem')
  itemWidget:setItemId(potionId)
  itemWidget:setTooltip(potionName)

  local buttonId = button:getId()
  local slotID = tonumber(buttonId:match("%d+"))
  helperConfig.potions[slotID + 1].id = potionId
  helperConfig.potions[slotID + 1].percent = helperConfig.potions[slotID + 1].percent

  -- Initialize the "I" toggle ALWAYS red = Health (threshold checks HP). Flip it to blue
  -- (Mana) by clicking the "I" on the row.
  helperConfig.potions[slotID + 1].priority = 1
  local priorityButton = healingPanel:recursiveGetChildById("priority" .. slotID)
  if priorityButton then
    priorityButton:setImageSource("/images/skin/show-gui-help-red")
    priorityButton:setTooltip("This potion is healing health...")
    priorityButton:setActionId(1)
  end
end

function updateButton(button)
  local profile = getShooterProfile()
  local index = tonumber(button:getId():match("%d+"))
  button.onMousePress = function(self, mousePos, mouseButton)
    if mouseButton == MouseRightButton then
      local menu = g_ui.createWidget('PopupMenu')
      menu:setGameMenu(true)
      local buttonId = button:getId()
      if buttonId:find("runeShooterButton") then
        if profile.runes[index + 1].id > 0 then
          menu:addOption(tr('Edit Rune'), function() assignRune(button) end)
          menu:addOption(tr('Remove'), function() removeAction("rune", button) end)
        else
          menu:addOption(tr('Assign Rune'), function() assignRune(button) end)
        end
      elseif buttonId:find("attackSpellButton") then
        if profile.spells[index + 1].id > 0 then
          menu:addOption(tr('Edit Spell'), function() assignSpell(button, "Aggressive", { 1, 4, 8 }, profile.spells) end)
          menu:addOption(tr('Remove'), function() removeAction("shooter", button) end)
        else
          menu:addOption(tr('Assign Spell'), function() assignSpell(button, "Aggressive", { 1, 4, 8 }, profile.spells) end)
        end
      elseif buttonId:find("spellButton") then
        if helperConfig.spells[index + 1].id > 0 then
          menu:addOption(tr('Edit Spell'), function() assignSpell(button, "Healing", { 2 }, helperConfig.spells) end)
          menu:addOption(tr('Remove'), function() removeAction("spell", button) end)
        else
          menu:addOption(tr('Assign Spell'), function() assignSpell(button, "Healing", { 2 }, helperConfig.spells) end)
        end
      elseif buttonId:find("potionButton") then
        if helperConfig.potions[index + 1].id > 0 then
          menu:addOption(tr('Edit Potion'), function() assignPotionEvent(button) end)
          menu:addOption(tr('Remove'), function() removeAction("potion", button) end)
        else
          menu:addOption(tr('Assign Potion'), function() assignPotionEvent(button) end)
        end
      elseif buttonId:find("spellTrainingButton") then
        if helperConfig.training[index + 1].id > 0 then
          menu:addOption(tr('Edit Training Spell'), function() assignTrainingSpell(button) end)
          menu:addOption(tr('Remove'), function() removeAction("training", button) end)
        else
          menu:addOption(tr('Assign Training Spell'), function() assignTrainingSpell(button) end)
        end
      elseif buttonId:find("hasteButton") then
        if helperConfig.haste[index + 1].id > 0 then
          menu:addOption(tr('Edit Haste Spell'), function() assignTrainingSpell(button, true) end)
          menu:addOption(tr('Remove'), function() removeAction("haste", button) end)
        else
          menu:addOption(tr('Assign Haste Spell'), function() assignTrainingSpell(button, true) end)
        end
      elseif buttonId:find("autoTrainingItem") then
        if not button.potionItem or button.potionItem:getItemId() == 0 then
          menu:addOption(tr('Select exercise weapon'), function() assignExerciseEvent(button) end)
        else
          menu:addOption(tr('Remove'), function() removeAction("exercise", button) end)
        end
      end

      menu:display(mousePos)
      return true
    end
    return false
  end
end

-- ===========================================================================
-- Friend Healing / Exura Gran Sio: PT-or-List priority model.
-- The box IS the priority list (top = highest priority). "PT" auto-fills it with
-- nearby party members; "List" uses a saved manual list edited via the "+" button.
-- A single life-% threshold triggers the spell on the highest-priority listed
-- player that is in range (see onFriendHealing). Both panels reuse the same child
-- ids, so handlers resolve their target by walking up to the owning panel.
-- ===========================================================================
healRadios = {}

local function healKindOf(widget)
  local p = widget
  while p do
    local id = p:getId()
    if id == "friendHealingPanel" then return "friend" end
    if id == "granSioPanel" then return "gran" end
    p = p:getParent()
  end
end

local function healCfgOf(kind)
  return kind == "gran" and helperConfig.gransiohealing or helperConfig.friendhealing
end

local function healListOf(kind)
  return kind == "gran" and granListWidget or friendListWidget
end

local function healPanelOf(kind)
  return kind == "gran" and granSioPanel or friendHealingPanel
end

-- Reflect cfg.percent into the panel's percent label + enable/disable +/- at bounds.
local function setHealPercentLabel(kind)
  local panel = healPanelOf(kind)
  if not panel then return end
  local pct = healCfgOf(kind).percent or 99
  local label = panel:recursiveGetChildById("healPercentLabel")
  if label then label:setText(pct .. "%") end
  local add = panel:recursiveGetChildById("healAddPercent")
  local rmv = panel:recursiveGetChildById("healRmvPercent")
  if add then add:setEnabled(pct < 99) end
  if rmv then rmv:setEnabled(pct > 1) end
end

-- Ordered names to show/heal. List mode -> the saved list. PT mode -> nearby party
-- members ordered by the saved priority (ptOrder), new members appended; the
-- refreshed order is written back so the priority persists across party changes.
local function healOrderedNames(kind)
  local cfg = healCfgOf(kind)
  if cfg.mode == "List" then
    return cfg.list
  end
  -- PT mode needs the local player position synced (getUpcomingPartyMembers distance-
  -- checks against it). Early in online() it isn't ready yet, so bail to the saved
  -- order to avoid crashing; the box refills once party data arrives / the tick runs.
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer or not localPlayer:getPosition() then
    return cfg.ptOrder
  end
  local present = {}
  for _, creature in ipairs(modules.game_party_list.getUpcomingPartyMembers()) do
    if creature:isPlayer() and not creature:isLocalPlayer() then
      present[creature:getName()] = true
    end
  end
  local ordered = {}
  for _, name in ipairs(cfg.ptOrder) do
    if present[name] then
      table.insert(ordered, name)
      present[name] = nil
    end
  end
  for name in pairs(present) do
    table.insert(ordered, name)
  end
  -- Only persist when members are actually present; otherwise a momentary party-less
  -- tick (now that onFriendHealing runs without a party gate) would wipe the saved order.
  if #ordered > 0 then
    cfg.ptOrder = ordered
  end
  return ordered
end

local function granSioOffCooldown()
  local spell = Spells.getSpellByClientId(242) -- exura gran sio
  return spell ~= nil and spell.id ~= 0 and not isSpellOnCooldown(spell)
end

-- Support-cast arbiter: the single support heal that should take this cycle's spell-
-- exhaust window. Decides self-heal vs friend-heal centrally so checkHealthHealing and
-- onFriendHealing stop probing each other's config -- and so "Prioritize heal friend"
-- actually wins (the per-cast checkHealthPriority guard inside useAuto* used to override
-- it). Memoized per cycle; returns "self", "gran", "sio", or nil (no heal wanted ->
-- haste may cast). Priority, high -> low:
--   1. a friend panel flagged prioritizeFriend with an eligible target (gran needs its
--      cooldown free; gran is considered before sio)
--   2. self-heal (a self spell whose HP% threshold is met)
--   3. friend heal not flagged (gran before sio)
local tickSupport = { cycle = -1, tag = nil }
local function topSupportCast()
  if tickSupport.cycle == tickCycle then return tickSupport.tag end
  local tag = nil
  local localPlayer = g_game.getLocalPlayer()
  local position = localPlayer and localPlayer:getPosition()
  if position then
    local fh, gh = helperConfig.friendhealing, helperConfig.gransiohealing
    local nearby = tickNearbyPlayers()
    local function targetPending(cfg, kind)
      if not cfg.enabled then return false end
      for _, name in ipairs(healOrderedNames(kind)) do
        local member = nearby[name]
        if member and member:getHealthPercent() <= cfg.percent
          and isWithinReach(position, member:getPosition())
          and g_map.isSightClear(position, member:getPosition()) then
          return true
        end
      end
      return false
    end
    local granReady = targetPending(gh, "gran") and granSioOffCooldown()
    local sioPending = targetPending(fh, "friend")
    local selfNeeded = (checkHealthPriority() == false)
    if gh.prioritizeFriend and granReady then
      tag = "gran"
    elseif fh.prioritizeFriend and sioPending then
      tag = "sio"
    elseif selfNeeded then
      tag = "self"
    elseif granReady then
      tag = "gran"
    elseif sioPending then
      tag = "sio"
    end
  end
  tickSupport.cycle = tickCycle
  tickSupport.tag = tag
  return tag
end

-- (Re)build a panel's list box from its ordered names, preserving the selection.
function populateHealList(kind)
  local listWidget = healListOf(kind)
  if not listWidget then return end
  local cfg = healCfgOf(kind)
  local focused = listWidget:getFocusedChild()
  local keepName = focused and focused:getText() or nil
  listWidget:destroyChildren()
  for _, name in ipairs(healOrderedNames(kind)) do
    local row = g_ui.createWidget("PlayerName", listWidget)
    row:setText(name)
    if cfg.mode == "List" then
      row:setTooltip(tr("Double-click to remove"))
      row.onDoubleClick = function()
        for i = #cfg.list, 1, -1 do
          if cfg.list[i] == name then table.remove(cfg.list, i) end
        end
        saveSettings()
        populateHealList(kind)
        return true
      end
    end
    if name == keepName then
      row:focus()
    end
  end
end

-- Wire a panel's PT/List radio and sync Enable/percent widgets to the config.
function setupHealRadio(kind)
  local panel = healPanelOf(kind)
  if not panel then return end
  local cfg = healCfgOf(kind)
  local pt = panel:recursiveGetChildById("radioPT")
  local list = panel:recursiveGetChildById("radioList")
  if not pt or not list then return end
  local radio = UIRadioGroup.create()
  radio:addWidget(pt)
  radio:addWidget(list)
  radio.onSelectionChange = function(_, selected)
    if not selected then return end
    cfg.mode = (selected:getId() == "radioList") and "List" or "PT"
    panel:recursiveGetChildById("addNames"):setEnabled(cfg.mode == "List")
    panel:recursiveGetChildById("removeNames"):setEnabled(cfg.mode == "List")
    saveSettings()
    populateHealList(kind)
  end
  healRadios[kind] = radio
  radio:selectWidget(cfg.mode == "List" and list or pt, true) -- dontSignal: sync below
  panel:recursiveGetChildById("addNames"):setEnabled(cfg.mode == "List")
  panel:recursiveGetChildById("removeNames"):setEnabled(cfg.mode == "List")
  panel:recursiveGetChildById("enableHeal"):setChecked(cfg.enabled and true or false)
  panel:recursiveGetChildById("prioritizeFriend"):setChecked(cfg.prioritizeFriend and true or false)
  setHealPercentLabel(kind)
  populateHealList(kind)
end

-- "+" button: add comma-separated names to the List (trim + dedupe). List mode only.
function onAddHealNames(self)
  local kind = healKindOf(self)
  if not kind then return end
  local cfg = healCfgOf(kind)
  if cfg.mode ~= "List" then return end
  local box = UIInputBox.create(tr("Add players to heal list"), function(text)
    if not text then return end
    local added = false
    for raw in text:gmatch("[^,]+") do
      local name = raw:gsub("^%s+", ""):gsub("%s+$", "")
      if name ~= "" and not table.contains(cfg.list, name) then
        table.insert(cfg.list, name)
        added = true
      end
    end
    if added then
      saveSettings()
      populateHealList(kind)
    end
  end, nil)
  box:addLineEdit(tr('Names (separated by ",")'), "", 2000)
  box:display()
end

-- "-" button: remove the selected entry from the List (List mode only).
function onRemoveHealName(self)
  local kind = healKindOf(self)
  if not kind then return end
  local cfg = healCfgOf(kind)
  if cfg.mode ~= "List" then return end
  local listWidget = healListOf(kind)
  local focused = listWidget and listWidget:getFocusedChild()
  if not focused then return end
  local name = focused:getText()
  local removed = false
  for i = #cfg.list, 1, -1 do
    if cfg.list[i] == name then
      table.remove(cfg.list, i)
      removed = true
    end
  end
  if removed then
    saveSettings()
    populateHealList(kind)
  end
end

-- Up/down arrows: move the selected entry within the active ordered list.
function moveHealName(self, dir)
  local kind = healKindOf(self)
  if not kind then return end
  local cfg = healCfgOf(kind)
  local listWidget = healListOf(kind)
  local focused = listWidget:getFocusedChild()
  if not focused then return end
  local name = focused:getText()
  local arr = (cfg.mode == "List") and cfg.list or cfg.ptOrder
  local idx
  for i, n in ipairs(arr) do
    if n == name then idx = i break end
  end
  if not idx then return end
  local j = idx + dir
  if j < 1 or j > #arr then return end
  arr[idx], arr[j] = arr[j], arr[idx]
  saveSettings()
  populateHealList(kind)
end

function onEnableHeal(self, checked)
  local kind = healKindOf(self)
  if not kind then return end
  healCfgOf(kind).enabled = checked and true or false
  saveSettings()
end

-- "Prioritize heal friend": invert the default self > friend order for this panel.
function onPrioritizeFriend(self, checked)
  local kind = healKindOf(self)
  if not kind then return end
  healCfgOf(kind).prioritizeFriend = checked and true or false
  saveSettings()
end

-- +/- stepper buttons (hold-repeat via bindAutoPress): adjust cfg.percent by 1,
-- clamp 1..99, mirroring the Spell Healing selector. self is the clicked +/- button.
function stepHealPercent(self, delta)
  local kind = healKindOf(self)
  if not kind then return end
  local cfg = healCfgOf(kind)
  local newPct = math.max(1, math.min(99, (cfg.percent or 99) + delta))
  if newPct == cfg.percent then return end
  cfg.percent = newPct
  setHealPercentLabel(kind)
  saveSettings()
end

-- Party roster changed: refresh whichever boxes are in PT mode.
function onPartyDataClear()
  if friendHealingPanel and helperConfig.friendhealing.mode == "PT" then populateHealList("friend") end
  if granSioPanel and helperConfig.gransiohealing.mode == "PT" then populateHealList("gran") end
end

function onPartyDataUpdate(members)
  if friendHealingPanel and helperConfig.friendhealing.mode == "PT" then populateHealList("friend") end
  if granSioPanel and helperConfig.gransiohealing.mode == "PT" then populateHealList("gran") end
end

function onEnableTraining(buttonId, checked)
  if helperConfig.haste[1].enabled then
    toolsPanel:recursiveGetChildById("enableHaste0"):setChecked(false)
  end

  local slotIndex = tonumber(buttonId:match("%d+"))
  helperConfig.training[slotIndex + 1].enabled = checked
end

-- Bot functions
function updateHealingPercent(buttonId, newPercent)
  local buttonIndex = string.match(buttonId, "%d+")
  if not buttonIndex then
    return
  end

  buttonIndex = tonumber(buttonIndex)
  local config = helperConfig.spells[buttonIndex + 1]
  if string.find(buttonId, "add") then
    if config.percent + 1 > 99 then
      healingPanel:recursiveGetChildById("addPercentButton" .. buttonIndex):setEnabled(false)
      return
    end

    healingPanel:recursiveGetChildById("rmvPercentButton" .. buttonIndex):setEnabled(true)
    config.percent = config.percent + 1
    local label = healingPanel:recursiveGetChildById("spellPercentLabel" .. buttonIndex)
    label:setText(config.percent .. "%")
  elseif string.find(buttonId, "rmv") then
    if config.percent - 1 < 1 then
      healingPanel:recursiveGetChildById("rmvPercentButton" .. buttonIndex):setEnabled(false)
      return
    end

    healingPanel:recursiveGetChildById("addPercentButton" .. buttonIndex):setEnabled(true)
    config.percent = config.percent - 1
    local label = healingPanel:recursiveGetChildById("spellPercentLabel" .. buttonIndex)
    label:setText(config.percent .. "%")
  end

  cachedSpells = table.copy(helperConfig.spells)
  table.sort(cachedSpells, function(a, b) return a.percent < b.percent end)
end

function updateMagicShooterPercent(buttonId, newPercent)
  local buttonIndex = string.match(buttonId, "%d+")
  if not buttonIndex then
    return
  end

  local profile = getShooterProfile()

  buttonIndex = tonumber(buttonIndex)
  local config = profile.spells[buttonIndex + 1]
  local label = shooterPanel:recursiveGetChildById("spellPercentLabel" .. buttonIndex)

  if string.find(buttonId, "add") then
    if config.percent >= 99 then
      shooterPanel:recursiveGetChildById("addPercentButton" .. buttonIndex):setEnabled(false)
      return
    end

    config.percent = config.percent + 1
    label:setText(config.percent .. "%")

    if config.percent >= 99 then
      shooterPanel:recursiveGetChildById("addPercentButton" .. buttonIndex):setEnabled(false)
    end

    shooterPanel:recursiveGetChildById("rmvPercentButton" .. buttonIndex):setEnabled(true)
  elseif string.find(buttonId, "rmv") then
    if config.percent <= 1 then
      shooterPanel:recursiveGetChildById("rmvPercentButton" .. buttonIndex):setEnabled(false)
      return
    end

    config.percent = config.percent - 1
    label:setText(config.percent .. "%")

    if config.percent <= 1 then
      shooterPanel:recursiveGetChildById("rmvPercentButton" .. buttonIndex):setEnabled(false)
    end

    shooterPanel:recursiveGetChildById("addPercentButton" .. buttonIndex):setEnabled(true)
  end
end

function updateRuneShooterCreatures(name, index, creatures)
  local profile = getShooterProfile()
  profile.runes[index + 1].creatures = tonumber(creatures)
end

function updateRuneShooterPriority(index, priority)
  local profile = getShooterProfile()
  profile.runes[index + 1].priority = tonumber(priority)
end

function updatePotionPercent(buttonId, newPercent)
  local buttonIndex = string.match(buttonId, "%d+")
  if not buttonIndex then
    return
  end

  buttonIndex = tonumber(buttonIndex)
  local config = helperConfig.potions[buttonIndex + 1]
  if string.find(buttonId, "add") then
    if config.percent + 1 > 99 then
      healingPanel:recursiveGetChildById("addPotionPercentButton" .. buttonIndex):setEnabled(false)
      return
    end

    healingPanel:recursiveGetChildById("rmvPotionPercentButton" .. buttonIndex):setEnabled(true)
    config.percent = config.percent + 1
    local label = healingPanel:recursiveGetChildById("potionPercentLabel" .. buttonIndex)
    label:setText(config.percent .. "%")
  elseif string.find(buttonId, "rmv") then
    if config.percent - 1 < 1 then
      healingPanel:recursiveGetChildById("rmvPotionPercentButton" .. buttonIndex):setEnabled(false)
      return
    end

    healingPanel:recursiveGetChildById("addPotionPercentButton" .. buttonIndex):setEnabled(true)
    config.percent = config.percent - 1
    local label = healingPanel:recursiveGetChildById("potionPercentLabel" .. buttonIndex)
    label:setText(config.percent .. "%")
  end
end

function castHealingSpell(spellId)
  local spell = Spells.getSpellByClientId(tonumber(spellId))
  if not spell or spell.id == 0 then
    return false
  end

  if (isSpellOnCooldown(spell)) then
    return false
  end

  if spell.soul > 0 then
    if player:getSoul() < spell.soul then
      return false
    end

    if spell.source and not hasItemInBackpack(spell.source) then
      return false
    end
  end

  g_game.doThing(false)
  g_game.talk(spell.words, true)
  g_game.doThing(true)
  return true
end

function checkHealthHealing()
  if not hotkeyHelperStatus then
    return false
  end

  local health, maxHealth = player:getHealth(), player:getMaxHealth()
  local healthPercent = (health / maxHealth) * 100

  local prioritizedPotions = {}
  for _, potion in pairs(helperConfig.potions) do
    table.insert(prioritizedPotions, potion)
  end
  table.sort(prioritizedPotions, function(a, b)
    if a.percent == b.percent then
      return a.priority < b.priority
    else
      return a.percent < b.percent
    end
  end)

  for _, potion in ipairs(prioritizedPotions) do
    if hasItemInBackpack(potion.id) and potionMode(potion) == "health" and healthPercent <= potion.percent then
      usePotion(potion.id)
    end
  end

  -- The arbiter (topSupportCast) decides self vs friend priority centrally; only cast
  -- the self-heal SPELL if self-heal wins this cycle (the potions above ran as an HP
  -- safety net regardless of the arbiter).
  if topSupportCast() ~= "self" then
    return
  end

  local prioritizedSpells = {}
  for _, spell in pairs(helperConfig.spells) do
    table.insert(prioritizedSpells, spell)
  end

  table.sort(prioritizedSpells, function(a, b)
    if a.percent == b.percent then
      return a.id < b.id
    else
      return a.percent < b.percent
    end
  end)

  for _, spell in ipairs(prioritizedSpells) do
    if ignoredSpellsIds[spell.id] then
      goto skipSpell
    end

    if healthPercent <= spell.percent then
      castHealingSpell(spell.id)
    end

    ::skipSpell::
  end
end

eventTable.checkHealthHealing.action = checkHealthHealing

function hasItemInBackpack(potionId)
  return player and type(player) == "userdata" and player:getInventoryCount(potionId, 0) > 0
end

function checkManaHealing(mana, maxMana)
  local manaPercent = (mana / maxMana) * 100

  for i, potion in ipairs(helperConfig.potions) do
    if isManaPotion(potion.id) then
      helperConfig.potions[i].percent = tonumber(potion.percent) or 0
    end
  end

  local healthPotionPriority = false
  for _, potion in ipairs(helperConfig.potions) do
    local healthPercent = (player:getHealth() / player:getMaxHealth()) * 100
    if hasItemInBackpack(potion.id) and potionMode(potion) == "health" and healthPercent <= potion.percent then
      healthPotionPriority = true
    end
  end

  if healthPotionPriority then
    return
  end

  local prioritizedManaPotions = {}
  for _, potion in ipairs(helperConfig.potions) do
    if potionMode(potion) == "mana" then
      table.insert(prioritizedManaPotions, potion)
    end
  end
  table.sort(prioritizedManaPotions, function(a, b)
    return a.percent < b.percent
  end)

  for _, potion in ipairs(prioritizedManaPotions) do
    if hasItemInBackpack(potion.id) and manaPercent <= potion.percent then
      usePotion(potion.id)
      return
    end
  end
end

function useAutoSio(target)
  local spellId = 84
  local spell = Spells.getSpellByClientId(tonumber(spellId))
  if not spell or spell.id == 0 then
    return false
  end

  if (isSpellOnCooldown(spell)) then
    return false
  end

  g_game.doThing(false)
  g_game.talk(string.format("%s \"%s\"", spell.words, target:getName()), true)
  g_game.doThing(true)
end

function useAutoGranSio(target)
  local spellId = 242
  local spell = Spells.getSpellByClientId(spellId)
  if not spell or spell.id == 0 then
    return false
  end

  if (isSpellOnCooldown(spell)) then
    return false
  end

  g_game.doThing(false)
  g_game.talk(string.format("%s \"%s\"", spell.words, target:getName()), true)
  g_game.doThing(true)
end

function useAutoTioSio(target)
  local spellId = 297
  local spell = Spells.getSpellByClientId(spellId)
  if not spell or spell.id == 0 then
    return false
  end

  if (isSpellOnCooldown(spell)) then
    return false
  end

  g_game.doThing(false)
  g_game.talk(string.format("%s \"%s\"", spell.words, target:getName()), true)
  g_game.doThing(true)
end

function useAutoUH(target)
  local runeId = 3160
  local rune = Spells.getRuneSpellByItem(runeId)
  if not rune then
    return false
  end

  helperConfig.magicShooterOnHold = true

  if hasItemInBackpack(runeId) then
    g_game.doThing(false)
    g_game.useInventoryItemWith(runeId, target, 0, true)
    g_game.doThing(true)
  end

  helperConfig.magicShooterOnHold = false
end

-- toolMenu
function updateTrainingPercent(buttonId, newPercent)
  local buttonIndex = string.match(buttonId, "%d+")
  buttonIndex = tonumber(buttonIndex)
  local trainingConfig = helperConfig.training[buttonIndex + 1]
  if trainingConfig and trainingConfig.percent then
    trainingConfig.percent = tonumber(newPercent)
  end
end

function checkTrainingSpell(mana, maxMana)
  local trainingSpell = helperConfig.training[1]
  if not trainingSpell or not trainingSpell.enabled then
    return false
  end

  local manaPercent = (mana / maxMana) * 100
  if manaPercent < tonumber(trainingSpell.percent) then
    return false
  end

  castHealingSpell(trainingSpell.id)
end

function toggleAutoEat(checked)
  helperConfig.autoEatFood = checked
end

function toggleAutoHaste(checked)
  if helperConfig.training[1].enabled then
    toolsPanel:recursiveGetChildById("enableTraining0"):setChecked(false)
  end

  helperConfig.haste[1].enabled = checked
end

function toggleAutoHastePz(checked)
  helperConfig.haste[1].safecast = checked
end

function toggleAutoSellLoot(checked)
  helperConfig.autoSellLoot = checked
end

function toggleAutoBless(checked)
  helperConfig.autoBless = checked
end

function autoEatFood()
  if not g_game.isOnline() or not player or not helperConfig.autoEatFood then
    return
  end

  local cooldown = getSpellCooldown(foodConfig.id)
  if cooldown >= g_clock.millis() then
    return true
  end

  for _, id in pairs(infiniteFoodIds) do
    if player:getInventoryCount(id) > 0 then
      g_game.doThing(false)
      g_game.useInventoryItem(id)
      g_game.doThing(true)
      spellsCooldown[foodConfig.id] = g_clock.millis() + foodConfig.exhaustion
      return
    end
  end

  for _, id in pairs(foodIds) do
    if player:getInventoryCount(id) > 0 then
      g_game.doThing(false)
      g_game.useInventoryItem(id)
      g_game.doThing(true)
      spellsCooldown[foodConfig.id] = g_clock.millis() + foodConfig.exhaustion
      break
    end
  end
end

-- "Loot Seller" store item (KoliseuOT id 60257). Using it sells the loot pouch.
-- Auto Sell Loot fires a use-by-id packet when free capacity drops below the threshold;
-- selling at an NPC stays manual. The item lives locked in the Store Inbox, which is a
-- player inventory slot (CONST_SLOT_STORE_INBOX) server-side, so the server's use-by-id
-- search (findItemOfType, depthSearch) reaches it regardless of whether the Store Inbox
-- window is open on the client. No container lookup needed -- and there's a single id,
-- so blindly sending it (rate-limited) can't flood like the multi-id food gate would.
local LOOT_SELLER_ID = 60257
local LOOT_SELLER_CAP_THRESHOLD = 1000
local LOOT_SELLER_COOLDOWN = 20000 -- only fire every 20s while still overweight (anti-flood)

function autoSellLoot()
  if not g_game.isOnline() or not player or not helperConfig.autoSellLoot then
    return
  end
  -- Only when we're (nearly) full; above the threshold there's nothing to do.
  if player:getFreeCapacity() >= LOOT_SELLER_CAP_THRESHOLD then
    return
  end
  -- Anti-flood: at most one use per cooldown while we stay overweight.
  if getSpellCooldown("lootSeller") >= g_clock.millis() then
    return
  end

  g_game.doThing(false)
  g_game.useInventoryItem(LOOT_SELLER_ID)
  g_game.doThing(true)
  spellsCooldown["lootSeller"] = g_clock.millis() + LOOT_SELLER_COOLDOWN
end

-- Auto Bless: keep the player blessed so an unexpected death never drops items for
-- lack of blessing. STRICT by design -- only fires when the server's bless status
-- byte says the 5 blesses are missing (1 = Disabled/<5). !bless (BuyAllBlesses) is
-- idempotent server-side (no charge when already fully blessed), so this is safe.
function autoBless()
  if not g_game.isOnline() or not player or not helperConfig.autoBless then
    return
  end
  if g_game.isDead() then
    return
  end
  -- Needs the C++ getBlessStatus() (rebuild). Until then this is a safe no-op rather
  -- than blindly spamming !bless (getBlessings() only carries the cosmetic glow flag).
  if not player.getBlessStatus then
    return
  end
  if player:getBlessStatus() ~= 1 then -- 1 = missing the 5 blesses
    return
  end
  if getSpellCooldown("bless") >= g_clock.millis() then
    return
  end

  g_game.talk("!bless")
  spellsCooldown["bless"] = g_clock.millis() + 8000
end

function checkMana()
  if not g_game.isOnline() or not player or not hotkeyHelperStatus then return end
  if not player then
    return
  end

  local mana = player:getMana()
  local maxMana = player:getMaxMana()
  checkManaHealing(mana, maxMana)
  checkTrainingSpell(mana, maxMana)
end

eventTable.checkMana.action = checkMana

-- Convenience tools (eat / sell loot / bless) run independently of the
-- master combat helper toggle (hotkeyHelperStatus): each has its own Enable checkbox,
-- so e.g. Auto Eat should work even with the combat helper Disabled. Combat logic stays
-- gated in its own events (checkHealthHealing, checkMana, ...).
function routineChecks()
  if player then
    if player:getRegenerationTime() <= 500 then
      autoEatFood()
    end

    autoSellLoot()
    autoBless()
  end
end

eventTable.routineChecks.action = routineChecks

function updateMagicShooterPriority(index, priority)
  local profile = getShooterProfile()
  profile.spells[index + 1].priority = tonumber(priority)
end

function updateMagicShooterCreatures(name, index, creatures)
  local profile = getShooterProfile()
  profile.spells[index + 1].creatures = tonumber(creatures)
end

function toggleSelfCast(index, checked)
  local profile = getShooterProfile()
  profile.spells[index + 1].selfCast = checked
end

function toggleForceCast(index, checked)
  local profile = getShooterProfile()
  profile.spells[index + 1].forceCast = checked
end

function toggleForceRuneCast(index, checked)
  local profile = getShooterProfile()
  profile.runes[index + 1].forceCast = checked
end

function isMagicShooterActive()
  return helperConfig.magicShooterEnabled
end

function toggleMagicShooter(widget, message)
  local shooterTracker = helperTracker:recursiveGetChildById("shooterStatus")
  if not widget then
    widget = shooterPanel:recursiveGetChildById("enableMagicShooter")
    widget:setChecked(not widget:isChecked())
  end

  helperConfig.magicShooterEnabled = widget:isChecked()
  modules.game_textmessage.displayGameMessage(message and message or
  string.format("Caster is %s.", (helperConfig.magicShooterEnabled and "enabled" or "disabled")))
  shooterTracker:setText(helperConfig.magicShooterEnabled and "Active" or "Inactive")
  shooterTracker:setColor(helperConfig.magicShooterEnabled and "$var-text-cip-color-green" or "$var-text-cip-store-red")
end

function isAutoTargetActive()
  return helperConfig.autoTargetEnabled
end

function toggleAutoTarget(widget)
  local targetTracker = helperTracker:recursiveGetChildById("targetStatus")
  if not widget then
    widget = shooterPanel:recursiveGetChildById("enableAutoTarget")
    widget:setChecked(not widget:isChecked())
  end
  helperConfig.autoTargetEnabled = widget:isChecked()
  if not helperConfig.autoTargetEnabled and helperConfig.currentLockedTargetId > 0 then
    helperConfig.currentLockedTargetId = 0
    g_game.cancelAttack()
  end
  modules.game_textmessage.displayGameMessage(string.format("Auto Target is %s.",
    (helperConfig.autoTargetEnabled and "enabled" or "disabled")))
  targetTracker:setText(helperConfig.autoTargetEnabled and "Active" or "Inactive")
  targetTracker:setColor(helperConfig.autoTargetEnabled and "$var-text-cip-color-green" or "$var-text-cip-store-red")
end

function toggleShooterPreset(widget, hideMessage)
  local option = ""
  if widget then
    option = widget:getCurrentOption().text
    local profile = helperConfig.shooterProfiles[option]
    if profile then
      loadShooterProfileByName(option)
    end
  elseif not widget then
    widget = presetsPanel:recursiveGetChildById("presets")
    local profiles = {}
    for name, config in pairs(helperConfig.shooterProfiles) do
      table.insert(profiles, name)
    end
    local amount = #profiles
    if amount == 0 then
      return
    end
    local i = 1
    for j, name in ipairs(profiles) do
      if name == helperConfig.selectedShooterProfile then
        i = j
        break
      end
    end
    local nextIndex = i % amount + 1
    option = profiles[nextIndex]
    if not option then
      option = profiles[1]
    end
    widget:setCurrentOption(option, true)
    loadShooterProfileByName(option)
  end
  if not hideMessage then
    modules.game_textmessage.displayGameMessage(string.format("Caster profile switched to %s.", option))
  end
end

function removeProfile()
  local confirmWindow = nil
  local presets = presetsPanel:recursiveGetChildById('presets')

  local cancel = function()
    if confirmWindow then
      confirmWindow:destroy()
    end
  end

  local confirm = function()
    if confirmWindow then
      confirmWindow:destroy()
    end
    if getShooterProfileCount() <= 1 then
      modules.game_textmessage.displayGameMessage(string.format("You can't delete your only preset."))
      return
    end
    local currentProfileName = helperConfig.selectedShooterProfile
    toggleShooterPreset(nil, true)
    helperConfig.shooterProfiles[currentProfileName] = nil
    presets:removeOption(currentProfileName)
    modules.game_textmessage.displayGameMessage(string.format("Preset %s deleted.", currentProfileName))
  end

  confirmWindow = displayGeneralBox('Delete Preset',
    string.format("Are you sure you want to delete preset %s?", helperConfig.selectedShooterProfile),
    { { text = tr('Yes'), callback = confirm }, { text = tr('No'), callback = cancel }
    }, yesFunction, noFunction)
end

function updateAutoTargetMode(mode)
  local modeId = autoTargetModes[mode]
  if not modeId then
    return
  end
  helperConfig.autoTargetMode = modeId
  local profile = getShooterProfile()
  if profile then
    profile.autoTargetMode = modeId
  end
end

local function printArea(area)
  for _, row in ipairs(area) do
    local line = ""
    for _, value in ipairs(row) do
      line = line .. tostring(value) .. " "
    end
    print(line)
  end
  print("\n")
end

local function rotateArea(area, direction)
  local rotatedArea = {}

  local rows = #area
  local cols = #area[1]

  if direction == Directions.North then
    rotatedArea = area
  elseif direction == Directions.South then
    for y = 1, rows do
      rotatedArea[y] = {}
      for x = 1, cols do
        rotatedArea[y][x] = area[rows - y + 1][cols - x + 1]
      end
    end
  elseif direction == Directions.East then
    for x = 1, cols do
      rotatedArea[x] = {}
      for y = 1, rows do
        rotatedArea[x][y] = area[rows - y + 1][x]
      end
    end
  elseif direction == Directions.West then
    for x = 1, cols do
      rotatedArea[x] = {}
      for y = 1, rows do
        rotatedArea[x][y] = area[y][cols - x + 1]
      end
    end
  end

  return rotatedArea
end

local function findPlayerPosition(area)
  for y, row in ipairs(area) do
    for x, value in ipairs(row) do
      if value == 3 or value == 2 then
        return x, y
      end
    end
  end
  return nil, nil
end

function getRelativePosition(targetPos)
  local player = g_game.getLocalPlayer()
  if not player then return targetPos end
  local playerPos = player:getPosition()

  local relativePos = { x = targetPos.x, y = targetPos.y, z = targetPos.z }
  if playerPos.x < targetPos.x and playerPos.y < targetPos.y then
    relativePos.x = relativePos.x - 1;
    relativePos.y = relativePos.y - 1;
  elseif (playerPos.x < targetPos.x and playerPos.y > targetPos.y) or playerPos.x < targetPos.x then
    relativePos.x = relativePos.x - 1;
  elseif (playerPos.x > targetPos.x and playerPos.y < targetPos.y) or playerPos.y < targetPos.y then
    relativePos.y = relativePos.y - 1;
  end
  return relativePos
end

local function countAttackableCreatures(casterPos, direction, area, creatureList, ranged)
  if direction == Directions.SouthEast or direction == Directions.NorthEast then
    direction = Directions.East
  elseif direction == Directions.SouthWest or direction == Directions.NorthWest then
    direction = Directions.West
  end
  local area = rotateArea(area, direction)
  local creatures = 0
  local playerX, playerY = findPlayerPosition(area)
  if not playerX or not playerY then
    return 0
  end
  for yOffset, row in ipairs(area) do
    for xOffset, value in ipairs(row) do
      if value == 1 or (ranged and (value == 3 or value == 2)) then
        local position = {
          x = casterPos.x + (xOffset - playerX),
          y = casterPos.y + (yOffset - playerY),
          z = casterPos.z
        }
        for _, creature in ipairs(creatureList) do
          if positionCompare(creature.position, position) and (g_map.isSightClear(casterPos, creature.position)) then
            creatures = creatures + 1
            break
          end
        end
      end
    end
  end
  return creatures
end

local function sortMagicShooterByPriority(list)
  table.sort(list, function(a, b)
    if a.config.priority and b.config.priority then
      return a.config.priority < b.config.priority
    else
      return false
    end
  end)

  local player = g_game.getLocalPlayer()
  if not player then return list end

  local harmonyCount = player:getHarmony()
  if harmonyCount >= 5 then
    local spenderIndex = nil
    for i, item in ipairs(list) do
      if item.spell and item.spell.spender then
        spenderIndex = i
        break
      end
    end

    if spenderIndex then
      local spenderSpell = table.remove(list, spenderIndex)
      table.insert(list, 1, spenderSpell)
    end
  end
  return list
end

local function findBestTarget(position, direction, area, creatureList, minCreatures)
  local bestTarget = nil
  local maxCreaturesHit = 0

  for _, creatureInfo in pairs(creatureList) do
    if isWithinReach(position, creatureInfo.position) and g_map.isSightClear(position, creatureInfo.position) then
      local creaturesHit = countAttackableCreatures(creatureInfo.position, direction, area, creatureList, true)
      if creaturesHit >= minCreatures then
        if creaturesHit > maxCreaturesHit then
          maxCreaturesHit = creaturesHit
          bestTarget = creatureInfo.creature
        end
      end
    end
  end

  return bestTarget, maxCreaturesHit
end

function isSpellOnCooldown(spell)
  if getSpellCooldown(spell.id) >= g_clock.millis() then
    return true
  end

  if type(spell.group) == "table" then
    for group, _ in pairs(spell.group) do
      if getGroupSpellCooldown(group) >= g_clock.millis() then
        return true
      end
    end
  else
    if getGroupSpellCooldown(spell.group) >= g_clock.millis() then
      return true
    end
  end

  return false
end

function checkMagicShooter()
  if not hotkeyHelperStatus then return end
  if not helperConfig.magicShooterEnabled then return end

  local profile = getShooterProfile()
  local myCharacter = g_game.getLocalPlayer()
  if not myCharacter then return end

  if myCharacter:isInProtectionZone() then
    local caster = enableButtons:recursiveGetChildById("enableMagicShooter")
    if caster then
      caster:setChecked(false)
      toggleMagicShooter(caster, "Entering in a Protection Zone!\nCaster disabled.")
      return
    end
  end

  local timer = g_ui.getActionTimer()
  if timer > afkTime then
    local widget = enableButtons:recursiveGetChildById("enableMagicShooter")
    if widget then
      widget:setChecked(false)
      toggleMagicShooter(widget, "Caster disabled! \nDue to no changes in your actions so far.")
      return
    end
    return
  end

  local following = g_game.getFollowingCreature()
  if following then
    local widget = enableButtons:recursiveGetChildById("enableMagicShooter")
    if widget then
      widget:setChecked(false)
      toggleMagicShooter(widget, "Follow detected!\nCaster disabled.")
      return
    end
  end

  local position, direction = myCharacter:getPosition(), myCharacter:getDirection()
  local creatureList = {}
  local creaturesAround = 0
  for i, creature in pairs(spectators) do
    if creature:getPosition().z == position.z and getDistanceBetween(position, creature:getPosition()) <= 6 then
      creaturesAround = creaturesAround + 1
    end
    table.insert(creatureList, { position = creature:getPosition(), creature = creature })
  end

  local unifiedList = {}

  for i, shooter in ipairs(profile.spells) do
    local spell = shooter.id ~= 0 and Spells.getSpellByClientId(shooter.id) or nil
    if spell then
      table.insert(unifiedList, { type = "spell", spell = spell, config = shooter })
    end
  end

  for i, runeConfig in ipairs(profile.runes) do
    local runeSpell = Spells.getRuneSpellByItem(runeConfig.id)
    if runeSpell then
      table.insert(unifiedList, { type = "rune", rune = runeSpell, config = runeConfig })
    end
  end

  unifiedList = sortMagicShooterByPriority(unifiedList)

  local percentageMana = (player:getMana() / player:getMaxMana()) * 100
  local harmonyCount = player:getHarmony()

  for _, entry in ipairs(unifiedList) do
    if autoTargetOnHold then
      goto continue
    end

    local target = g_game.getAttackingCreature()
    local positionTarget = target and target:getPosition() or { x = 0xFFFF, y = 0xFFFF, z = 0xFF }

    if entry.type == "spell" then
      local castOnFoot = false
      local spell = entry.spell
      local config = entry.config
      local reachableCreatures = 0
      local targetable = (spell.range and spell.range > 0) or table.contains(bothCastTypeSpells, spell.id)

      if player:getMana() < spell.mana or (targetable and not target) then
        goto continue
      elseif not table.contains(spell.vocations, translateVocation(myCharacter:getVocation())) then
        goto continue
      elseif not playerHasSpell(myCharacter, spell.id) then
        goto continue
      elseif spell.spender and harmonyCount < 5 then
        goto continue
      end

      if config and percentageMana >= config.percent then
        if targetable and not config.selfCast then
          if not positionTarget or positionTarget.z ~= position.z or not target:canBeSeen() then
            goto continue
          end
          local range = spell.range or 3

          -- getCollisionSquare doesn't exist on this build (it hard-errored the
          -- shooter on every targeted spell). Guard it: it only offset the area
          -- origin for 2x2 creatures, so skipping it when absent is harmless.
          if target and target.getCollisionSquare and target:getCollisionSquare() > 1 then
            positionTarget = getRelativePosition(positionTarget)
          end

          if target and range >= getDistanceBetween(position, positionTarget) then
            if spell.area then
              reachableCreatures = countAttackableCreatures(positionTarget, 1, spell.area, creatureList, true)
            elseif not spell.area then
              reachableCreatures = 1
            end
          end
        elseif spell.area then
          reachableCreatures = countAttackableCreatures(position, direction, spell.area, creatureList, false)
          if table.contains(bothCastTypeSpells, spell.id) and reachableCreatures >= config.creatures then
            castOnFoot = true
          end
        end

        if reachableCreatures >= config.creatures then
          if not table.contains(bothCastTypeSpells, spell.id) and not config.forceCast and (targetable and creaturesAround > 1) then
            goto continue
          end

          if (isSpellOnCooldown(spell)) then
            goto continue
          end

          g_game.doThing(false)
          g_game.talk(spell.words, true, castOnFoot)
          g_game.doThing(true)

          -- --- precooldown
          onSpellCooldown(spell.id, 500)
          for group, _ in pairs(spell.group) do
            onSpellGroupCooldown(group, 500)
          end
        end
      end
    elseif entry.type == "rune" then
      if helperConfig.magicShooterOnHold then
        goto continue
      end

      local runeSpell = entry.rune
      local config = entry.config
      local runeCount = myCharacter:getInventoryCount(config.id)
      if runeCount > 0 then
        local bestTarget = nil
        local maxCreaturesHit = 0
        if runeSpell.area then
          bestTarget, maxCreaturesHit = findBestTarget(position, direction, runeSpell.area, creatureList,
            config.creatures)
        elseif not runeSpell.area then
          bestTarget = target and
          (isWithinReach(position, positionTarget) and g_map.isSightClear(position, positionTarget)) and target or nil
        end
        if bestTarget then
          if not config.forceCast and (not runeSpell.area and creaturesAround > 1) then
            goto continue
          end

          if isSpellOnCooldown(runeSpell) then
            goto continue
          end

          g_game.doThing(false)
          g_game.useInventoryItemWith(config.id, bestTarget, 0, true)
          g_game.doThing(true)
          -- precooldown
          onSpellGroupCooldown(runeSpell.group, 500)
        end
      end
    end
    ::continue::
  end
end

eventTable.checkMagicShooter.action = checkMagicShooter

function checkAutoTarget()
  if not hotkeyHelperStatus then return end
  if not helperConfig.autoTargetEnabled then return end
  if autoTargetOnHold then return end

  local myCharacter = g_game.getLocalPlayer()
  if not myCharacter then return end

  if myCharacter:isInProtectionZone() then
    local autoTarget = enableButtons:recursiveGetChildById("enableAutoTarget")
    if autoTarget then
      autoTarget:setChecked(false)
      toggleAutoTarget(autoTarget)
      return
    end
  end

  local timer = g_ui.getActionTimer()
  if timer > afkTime then
    local widget = enableButtons:recursiveGetChildById("enableAutoTarget")
    if widget then
      widget:setChecked(false)
      toggleAutoTarget(widget)
      return
    end
    return
  end

  local position = myCharacter:getPosition()

  local currentLockedTarget = helperConfig.currentLockedTargetId ~= 0 and
  g_map.getCreatureById(helperConfig.currentLockedTargetId) or nil
  if currentLockedTarget and not currentLockedTarget:isDead() and isWithinReach(position, currentLockedTarget:getPosition()) then
    return
  end

  local closestTarget = { id = nil, distance = 99 }
  local farthestTarget = { id = nil, distance = -1 }
  local lowestHealthTarget = { id = nil, health = 100 }
  local highestHealthTarget = { id = nil, health = -1 }
  local bestTarget = { id = nil, creatures = 0 }
  local closestLowestHealthTarget = { id = nil, distance = 99, health = 100 }
  local closestHighestHealthTarget = { id = nil, distance = 99, health = -1 }
  local farthestLowestHealthTarget = { id = nil, distance = -1, health = 100 }
  local farthestHighestHealthTarget = { id = nil, distance = -1, health = -1 }

  local area = SpellAreas.AREA_CIRCLE3X3
  if translateVocation(myCharacter:getVocation()) == 7 then
    area = SpellAreas.AREA_CIRCLE2X2
  end

  local creatureList = {}
  for i, creature in pairs(spectators) do
    table.insert(creatureList, { position = creature:getPosition(), creature = creature })
  end

  local monsters = {}
  local maxCreaturesHit = 0

  for i, creatureData in pairs(creatureList) do
    if not isWithinReach(position, creatureData.position) or not g_map.isSightClear(position, creatureData.position) then
      goto continue
    end
    local health = creatureData.creature:getHealthPercent()
    if lowestHealthTarget.id == nil then -- just to make sure it will target someone at 100% health
      lowestHealthTarget = { id = creatureData.creature:getId(), health = health }
    end
    if health < lowestHealthTarget.health then
      lowestHealthTarget = { id = creatureData.creature:getId(), health = health }
    end
    if health > highestHealthTarget.health then
      highestHealthTarget = { id = creatureData.creature:getId(), health = health }
    end
    local creatureDistance = getDistanceBetween(position, creatureData.position)
    if creatureDistance < closestTarget.distance then
      closestTarget = { id = creatureData.creature:getId(), distance = creatureDistance }
    end
    if creatureDistance > farthestTarget.distance then
      farthestTarget = { id = creatureData.creature:getId(), distance = creatureDistance }
    end
    if (creatureDistance < closestLowestHealthTarget.distance) or
        (creatureDistance == closestLowestHealthTarget.distance and health < closestLowestHealthTarget.health) then
      closestLowestHealthTarget = { id = creatureData.creature:getId(), distance = creatureDistance, health = health }
    end
    if (creatureDistance < closestHighestHealthTarget.distance) or
        (creatureDistance == closestHighestHealthTarget.distance and health > closestHighestHealthTarget.health) then
      closestHighestHealthTarget = { id = creatureData.creature:getId(), distance = creatureDistance, health = health }
    end
    if (creatureDistance > farthestLowestHealthTarget.distance) or
        (creatureDistance == farthestLowestHealthTarget.distance and health < farthestLowestHealthTarget.health) then
      farthestLowestHealthTarget = { id = creatureData.creature:getId(), distance = creatureDistance, health = health }
    end
    if (creatureDistance > farthestHighestHealthTarget.distance) or
        (creatureDistance == farthestHighestHealthTarget.distance and health > farthestHighestHealthTarget.health) then
      farthestHighestHealthTarget = { id = creatureData.creature:getId(), distance = creatureDistance, health = health }
    end
    local creaturesHit = countAttackableCreatures(creatureData.position, 1, area, creatureList, true)
    if creaturesHit > maxCreaturesHit then
      maxCreaturesHit = creaturesHit
      bestTarget.id = creatureData.creature:getId()
      bestTarget.creatures = creaturesHit
    end
    table.insert(monsters, creatureData.creature)
    ::continue::
  end


  local currentTarget = g_game.getAttackingCreature()
  local target = nil
  if helperConfig.autoTargetMode == autoTargetModes["A"] then
    target = g_map.getCreatureById(closestTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["B"] then
    target = g_map.getCreatureById(farthestTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["C"] then
    target = g_map.getCreatureById(lowestHealthTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["D"] then
    target = g_map.getCreatureById(highestHealthTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["E"] and bestTarget.id ~= nil then
    target = g_map.getCreatureById(bestTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["F"] then
    target = g_map.getCreatureById(closestLowestHealthTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["G"] then
    target = g_map.getCreatureById(closestHighestHealthTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["H"] then
    target = g_map.getCreatureById(farthestLowestHealthTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["I"] then
    target = g_map.getCreatureById(farthestHighestHealthTarget.id)
  end

  if target and not (currentTarget and currentTarget:getId() == target:getId()) then
    g_game.doThing(false)
    g_game.attack(target)
    g_game.doThing(true)
  end
end

eventTable.checkAutoTarget.action = checkAutoTarget

function checkFriendHealing()
  if not hotkeyHelperStatus then return end
  -- No party gate: List mode heals manually-listed names (who may not be partied),
  -- and PT mode simply resolves to no targets when not in a party. onFriendHealing
  -- early-returns unless a panel is enabled.
  local localPlayer = g_game.getLocalPlayer()
  if localPlayer then
    onFriendHealing(localPlayer)
  end
end

eventTable.checkFriendHealing.action = checkFriendHealing

local lastHaste = 0

function checkAutoHaste()
  if not hotkeyHelperStatus then return end

  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer or helperConfig.haste[1].id == 0 then
    return true
  end

  if not helperConfig.haste[1].enabled then
    return true
  end

  if not helperConfig.haste[1].safecast and player:isInPz() then
    return true
  end

  local spellId = helperConfig.haste[1].id
  local spell = Spells.getSpellByClientId(spellId)
  if not spell or spell.id == 0 then
    return false
  end

  if not checkHealthPriority() then
    return
  end

  local currentMillis = g_clock.millis()
  local nextTime = lastHaste + spell.duration

  if currentMillis < nextTime then
    return
  end

  g_game.doThing(false)
  g_game.talk(spell.words, true)
  g_game.doThing(true)

  lastHaste = currentMillis
end

eventTable.checkAutoHaste.action = checkAutoHaste

function checkHealthPriority()
  if not hotkeyHelperStatus then return end
  for _, spell in ipairs(helperConfig.spells) do
    local healthPercent = (player:getHealth() / player:getMaxHealth()) * 100
    if spell.id ~= 0 and healthPercent <= tonumber(spell.percent) then
      return false
    end
  end
  return true
end

function toggleReconnect(checked)
  local currentCharacterName = g_game.getCharacterName()
  helperConfig.autoReconnect = checked
  saveAutoReconnect(currentCharacterName, checked)
end

function onFriendHealing(localPlayer)
  if not hotkeyHelperStatus then return end

  local fh = helperConfig.friendhealing
  local gh = helperConfig.gransiohealing
  if not (fh.enabled or gh.enabled) then return end

  -- The arbiter (topSupportCast) decides self vs friend priority centrally; act only if
  -- it picked one of our friend heals this cycle. It already verified the target is
  -- pending and, for gran, that the spell is off cooldown.
  local winner = topSupportCast()
  if winner ~= "gran" and winner ~= "sio" then return end

  local position = localPlayer:getPosition()
  local nearby = tickNearbyPlayers()
  local cfg = (winner == "gran") and gh or fh
  local kind = (winner == "gran") and "gran" or "friend"

  -- Heal the FIRST priority-ordered target that is present, in range and below the
  -- threshold (the same eligibility the arbiter used to pick this heal).
  for _, name in ipairs(healOrderedNames(kind)) do
    local member = nearby[name]
    if member and member:getHealthPercent() <= cfg.percent
      and isWithinReach(position, member:getPosition())
      and g_map.isSightClear(position, member:getPosition()) then
      if winner == "gran" then
        useAutoGranSio(member)
      else
        local voc = translateVocation(localPlayer:getVocation())
        if voc == 5 then
          useAutoUH(member)
        elseif voc == 9 then
          useAutoTioSio(member)
        else
          useAutoSio(member)
        end
      end
      return
    end
  end
end

function reset()
  for i = 0, 2 do
    removeAction("spell", healingPanel:recursiveGetChildById("spellButton" .. i))
    removeAction("potion", healingPanel:recursiveGetChildById("potionButton" .. i))
    removeAction("shooter", shooterPanel:recursiveGetChildById("attackSpellButton" .. i))
    if i < 2 then
      removeAction("rune", runePanel:recursiveGetChildById("runeShooterButton" .. i))
    end
  end

  removeAction("training", toolsPanel:recursiveGetChildById("spellTrainingButton0"))
  removeAction("haste", toolsPanel:recursiveGetChildById("hasteButton0"))
end

function removeAction(type, button, keepInfo)
  local slotIndex = tonumber(button:getId():match("%d+"))
  if type == "spell" then
    helperConfig.spells[slotIndex + 1].id = 0
    helperConfig.spells[slotIndex + 1].percent = 80
    local button = healingPanel:recursiveGetChildById("spellButton" .. slotIndex)
    local percent = healingPanel:recursiveGetChildById("spellPercentLabel" .. slotIndex)
    button:setImageSource("/images/game/actionbar/actionbarslot")
    button:setImageClip("0 0 34 34")
    button:setBorderWidth(0)
    button:setTooltip("")
    percent:setText("80%")
  elseif type == "shooter" then
    if not keepInfo then
      local profile = getShooterProfile()
      profile.spells[slotIndex + 1].id = 0
      profile.spells[slotIndex + 1].percent = 80
      profile.spells[slotIndex + 1].creatures = 1
      profile.spells[slotIndex + 1].forceCast = false
      profile.spells[slotIndex + 1].selfCast = false
    end
    local button = shooterPanel:recursiveGetChildById("attackSpellButton" .. slotIndex)
    button:setImageSource("/images/game/actionbar/actionbarslot")
    button:setImageClip("0 0 34 34")
    button:setBorderWidth(0)
    button:setTooltip("")
    local percent = shooterPanel:recursiveGetChildById("spellPercentLabel" .. slotIndex)
    shooterPanel:recursiveGetChildById("rmvPercentButton" .. slotIndex):setEnabled(true)
    shooterPanel:recursiveGetChildById("addPercentButton" .. slotIndex):setEnabled(true)
    percent:setText("80%")
    local forceCast = shooterPanel:recursiveGetChildById("conditionSetting" .. slotIndex)
    forceCast:setChecked(false)
    forceCast:setVisible(false)
    local creaturesMin = shooterPanel:recursiveGetChildById("countMinCreature" .. slotIndex)
    creaturesMin:setCurrentOption("1+")
    creaturesMin:enable()
    local selfCast = shooterPanel:recursiveGetChildById("selfCast" .. slotIndex)
    if selfCast then
      selfCast:destroy()
    end
  elseif type == "potion" then
    if not helperConfig.potions[slotIndex + 1] then
      helperConfig.potions[slotIndex + 1] = {}
    end

    if helperConfig.potions[slotIndex + 1].id == 7642 or helperConfig.potions[slotIndex + 1].id == 23374 then
      helperConfig.potions[slotIndex + 1].priority = 0
      local priorityButton = healingPanel:recursiveGetChildById("priority" .. slotIndex)
      priorityButton:setImageSource("/images/skin/show-gui-help-grey")
      priorityButton:setTooltip(
      "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.\nPaladins can click on this button to change the potion priority:\n  - Icon: Blue (Mana Priority)\n  - Icon: Red  (Health Priority)")
    end

    helperConfig.potions[slotIndex + 1].id = 0
    helperConfig.potions[slotIndex + 1].percent = 50
    local button = healingPanel:recursiveGetChildById("potionButton" .. slotIndex)
    button:setImageSource("/images/game/actionbar/actionbarslot")
    local percent = healingPanel:recursiveGetChildById("potionPercentLabel" .. slotIndex)
    if button.potionItem then
      button.potionItem:destroy()
    end
    percent:setText("50%")
  elseif type == "rune" then
    if not keepInfo then
      local profile = getShooterProfile()
      if not profile.runes[slotIndex + 1] then
        profile.runes[slotIndex + 1] = {}
      end

      profile.runes[slotIndex + 1].id = 0
      profile.runes[slotIndex + 1].creatures = 1
      profile.runes[slotIndex + 1].forceCast = false
    end
    local button = runePanel:recursiveGetChildById("runeShooterButton" .. slotIndex)
    button:setImageSource("/images/game/actionbar/actionbarslot")
    local creaturesMin = runePanel:recursiveGetChildById("countMinCreature" .. slotIndex)
    creaturesMin:setCurrentOption("1+")
    creaturesMin:enable()
    local forceCast = runePanel:recursiveGetChildById("conditionSetting" .. slotIndex)
    forceCast:setVisible(false)
    forceCast:setChecked(false)
    if button.runeItem then
      button.runeItem:destroy()
    end
  elseif type == "training" then
    helperConfig.training[slotIndex + 1].id = 0
    helperConfig.training[slotIndex + 1].percent = 0
    helperConfig.training[slotIndex + 1].enabled = false
    local button = toolsPanel:recursiveGetChildById("spellTrainingButton" .. slotIndex)
    local percentOption = toolsPanel:recursiveGetChildById("spellTrainingPercent" .. slotIndex)
    button:setImageSource("/images/game/actionbar/actionbarslot")
    button:setImageClip("0 0 34 34")
    button:setBorderWidth(0)
    button:setTooltip("")
    percentOption:setCurrentOption("100%")
    toolsPanel:recursiveGetChildById("enableTraining" .. slotIndex):setChecked(false)
  elseif type == "haste" then
    helperConfig.haste[slotIndex + 1].id = 0
    helperConfig.haste[slotIndex + 1].enabled = false
    helperConfig.haste[slotIndex + 1].safecast = false
    local button = toolsPanel:recursiveGetChildById("hasteButton" .. slotIndex)
    button:setImageSource("/images/game/actionbar/actionbarslot")
    button:setImageClip("0 0 34 34")
    button:setBorderWidth(0)
    button:setTooltip("")
    toolsPanel:recursiveGetChildById("enableHaste" .. slotIndex):setChecked(false)
    toolsPanel:recursiveGetChildById("castOnPz"):setChecked(false)
  elseif type == "exercise" then
    local box = toolsPanel:recursiveGetChildById("autoTrainingItem")
    box:setImageSource("/images/game/actionbar/actionbarslot")
    if button.potionItem then
      button.potionItem:destroy()
    end
  end
end

function loadProfileOptions()
  local profile = helperConfig.selectedShooterProfile
  local presets = presetsPanel:recursiveGetChildById('presets')
  if presets then
    if presets:getOptionsCount() > 0 then
      return
    end

    local profileNames = {}

    for profileName, _ in pairs(helperConfig.shooterProfiles) do
      table.insert(profileNames, profileName)
    end

    table.sort(profileNames)

    for _, profileName in ipairs(profileNames) do
      presets:addOption(profileName)
    end

    presets:setCurrentOption(profile)
    presets:updateCurrentOption(profile)
  end
end

function loadShooterProfileByName(profileName)
  helperConfig.selectedShooterProfile = profileName
  local profile = getShooterProfile()
  if not profile then
    return
  end

  local currentPresetLabel = helperTracker:recursiveGetChildById("currentPresetName")
  if currentPresetLabel then
    currentPresetLabel:setText(profileName)
  end

  if profile.autoTargetMode then
    helperConfig.autoTargetMode = profile.autoTargetMode
    local autoTargetMode = enableButtons:recursiveGetChildById("autoTargetMode")
    if autoTargetMode then
      for k, v in pairs(autoTargetModes) do
        if v == profile.autoTargetMode then
          autoTargetMode:setCurrentOption(k)
          break
        end
      end
    end
  end

  for k, v in pairs(profile.spells) do
    if v.id <= 0 then
      removeAction("shooter", shooterPanel:recursiveGetChildById("attackSpellButton" .. k - 1))
    else
      local button = shooterPanel:recursiveGetChildById("attackSpellButton" .. k - 1)
      local minCreatures = shooterPanel:recursiveGetChildById("countMinCreature" .. k - 1)
      local priority = shooterPanel:recursiveGetChildById("priority" .. k - 1)
      local forceCast = shooterPanel:recursiveGetChildById("conditionSetting" .. k - 1)
      local selfCast = shooterPanel:recursiveGetChildById("selfCast" .. k - 1)
      forceCast:setChecked(v.forceCast)
      priority:setCurrentOption(numberToOrdinal(v.priority))
      minCreatures:setCurrentOption(tostring(v.creatures) .. "+")
      local spell = Spells.getSpellDataById(v.id)
      if spell then
        local spellId = SpellIcons[spell.icon][1]
        local source = SpelllistSettings['Default'].iconsFolder
        local clip = Spells.getImageClipNormal(spellId, 'Default')
        button:setImageSource(source)
        button:setImageClip(clip)
        button:setBorderColorTop("#1b1b1b")
        button:setBorderColorLeft("#1b1b1b")
        button:setBorderColorRight("#757575")
        button:setBorderColorBottom("#757575")
        button:setBorderWidth(1)
        button:setTooltip("Spell: " .. Spells.getSpellNameByWords(spell.words) .. "\nWords: " .. spell.words)
        if table.contains(bothCastTypeSpells, spell.id) then
          if not selfCast then
            selfCast = g_ui.createWidget('CheckBox', minCreatures:getParent())
            if selfCast then
              local style = {
                ["width"] = 12,
                ["anchors.top"] = "countMinCreature" .. k - 1 .. ".top",
                ["anchors.left"] = "countMinCreature" .. k - 1 .. ".right",
                ["margin-top"] = 6,
                ["margin-left"] = 5
              }
              selfCast:mergeStyle(style)
              selfCast:setId('selfCast' .. k - 1)
              selfCast:setTooltip('Cast on yourself')
              selfCast:setVisible(true)
              selfCast:setChecked(v.selfCast)
              selfCast.onCheckChange = function() toggleSelfCast(selfCast:getId():match("%d+"), selfCast:isChecked()) end
            end
          end
        end
        if minCreatures and (spell.range > 0 or not spell.area) and not table.contains(bothCastTypeSpells, spell.id) then
          minCreatures:setCurrentOption("1+")
          minCreatures:disable()
          v.creatures = 1
          forceCast:setVisible(true)
        else
          minCreatures:setEnabled(true)
          minCreatures:setCurrentOption(tostring(v.creatures) .. "+")
          forceCast:setVisible(false)
          forceCast:setChecked(false)
        end
      end
      local percentOption = shooterPanel:recursiveGetChildById("spellPercentLabel" .. k - 1)
      percentOption:setText(tostring(v.percent) .. "%")
      if v.percent <= 1 then
        shooterPanel:recursiveGetChildById("rmvPercentButton" .. k - 1):setEnabled(false)
      elseif v.percent >= 99 then
        shooterPanel:recursiveGetChildById("addPercentButton" .. k - 1):setEnabled(false)
      end
    end
  end
  for k, v in pairs(profile.runes) do
    if v.id <= 0 then
      removeAction("rune", runePanel:recursiveGetChildById("runeShooterButton" .. k - 1))
    else
      local button = runePanel:recursiveGetChildById("runeShooterButton" .. k - 1)
      if button.runeItem then
        button.runeItem:destroy()
      end
      local itemWidget = g_ui.createWidget('RuneItem', button)
      itemWidget:setItemId(v.id)
      itemWidget:setId('runeItem')
      local creaturesMin = runePanel:recursiveGetChildById("countMinCreature" .. k - 1)
      creaturesMin:setCurrentOption(tostring(v.creatures) .. "+")
      local forceCast = runePanel:recursiveGetChildById("conditionSetting" .. k - 1)
      forceCast:setVisible(false)
      forceCast:setChecked(v.forceCast)
      local rune = Spells.getRuneSpellByItem(v.id)
      if rune then
        if not rune.area then
          creaturesMin:disable()
          forceCast:setVisible(true)
        else
          creaturesMin:setEnabled(true)
          creaturesMin:setCurrentOption(tostring(v.creatures) .. "+")
          forceCast:setVisible(false)
          forceCast:setChecked(false)
        end
        button:setTooltip(string.format(rune.name .. " %s", rune.area and "(Area Damage)" or "(Single Damage)"))
      end
      local priorityOption = runePanel:recursiveGetChildById("runePriority" .. k - 1)
      priorityOption:setCurrentOption(numberToOrdinal(v.priority))
    end
  end
end

function onLoadHelperData()
  for k, v in pairs(helperConfig.spells) do
    if v.id ~= 0 then
      local button = healingPanel:recursiveGetChildById("spellButton" .. k - 1)
      local spell = Spells.getSpellDataById(v.id)
      if spell then
        local spellId = SpellIcons[spell.icon][1]
        local source = SpelllistSettings['Default'].iconsFolder
        local clip = Spells.getImageClipNormal(spellId, 'Default')
        button:setImageSource(source)
        button:setImageClip(clip)
        button:setBorderColorTop("#1b1b1b")
        button:setBorderColorLeft("#1b1b1b")
        button:setBorderColorRight("#757575")
        button:setBorderColorBottom("#757575")
        button:setBorderWidth(1)
        button:setTooltip("Spell: " .. Spells.getSpellNameByWords(spell.words) .. "\nWords: " .. spell.words)
      end
    end
    local percentOption = healingPanel:recursiveGetChildById("spellPercentLabel" .. k - 1)
    percentOption:setText(tostring(v.percent) .. "%")
  end

  for k, v in pairs(helperConfig.potions) do
    if v.id ~= 0 then
      local button = healingPanel:recursiveGetChildById("potionButton" .. k - 1)
      local itemWidget = g_ui.createWidget('PotionItem', button)
      itemWidget:setItemId(v.id)
      itemWidget:setId('potionItem')
      -- Restore the "I" toggle for EVERY potion (red = Health, blue = Mana). A saved blue
      -- (priority 2) is kept; a legacy/unset priority defaults to red (Health).
      local pr = v.priority
      if pr ~= 1 and pr ~= 2 then pr = 1 end
      helperConfig.potions[k].priority = pr
      local priorityButton = healingPanel:recursiveGetChildById("priority" .. k - 1)
      if priorityButton then
        priorityButton:setImageSource(pr == 2 and "/images/skin/show-gui-help-blue" or "/images/skin/show-gui-help-red")
        priorityButton:setTooltip(pr == 2 and "This potion is healing mana..." or "This potion is healing health...")
        priorityButton:setActionId(pr)
      end
    end

    local percentOption = healingPanel:recursiveGetChildById("potionPercentLabel" .. k - 1)
    percentOption:setText(tostring(v.percent) .. "%")
  end

  for k, v in pairs(helperConfig.training) do
    if v.id ~= 0 then
      local button = toolsPanel:recursiveGetChildById("spellTrainingButton" .. k - 1)
      local spell = Spells.getSpellDataById(v.id)
      if spell then
        local spellId = SpellIcons[spell.icon][1]
        local source = SpelllistSettings['Default'].iconsFolder
        local clip = Spells.getImageClipNormal(spellId, 'Default')
        button:setImageSource(source)
        button:setImageClip(clip)
        button:setBorderColorTop("#1b1b1b")
        button:setBorderColorLeft("#1b1b1b")
        button:setBorderColorRight("#757575")
        button:setBorderColorBottom("#757575")
        button:setBorderWidth(1)
        button:setTooltip("Spell: " .. Spells.getSpellNameByWords(spell.words) .. "\nWords: " .. spell.words)
      end
      local percentOption = toolsPanel:recursiveGetChildById("spellTrainingPercent" .. k - 1)
      percentOption:setCurrentOption(tostring(v.percent) .. "%")
      toolsPanel:recursiveGetChildById("enableTraining" .. k - 1):setChecked(v.enabled)
    end
  end

  for k, v in pairs(helperConfig.haste) do
    if v.id ~= 0 then
      local button = toolsPanel:recursiveGetChildById("hasteButton" .. k - 1)
      local spell = Spells.getSpellDataById(v.id)
      if spell then
        local spellId = SpellIcons[spell.icon][1]
        local source = SpelllistSettings['Default'].iconsFolder
        local clip = Spells.getImageClipNormal(spellId, 'Default')

        button:setImageSource(source)
        button:setImageClip(clip)
        button:setBorderColorTop("#1b1b1b")
        button:setBorderColorLeft("#1b1b1b")
        button:setBorderColorRight("#757575")
        button:setBorderColorBottom("#757575")
        button:setBorderWidth(1)
        button:setTooltip("Spell: " .. Spells.getSpellNameByWords(spell.words) .. "\nWords: " .. spell.words)
      end
      toolsPanel:recursiveGetChildById("enableHaste" .. k - 1):setChecked(v.enabled)
      toolsPanel:recursiveGetChildById("castOnPz"):setChecked(v.safecast)
    end
  end
  loadShooterProfileByName(helperConfig.selectedShooterProfile)
  toolsPanel:recursiveGetChildById("eatFood"):setChecked(helperConfig.autoEatFood)
  toolsPanel:recursiveGetChildById("reconnect"):setChecked(helperConfig.autoReconnect)
  toolsPanel:recursiveGetChildById("sellLoot"):setChecked(helperConfig.autoSellLoot)
  toolsPanel:recursiveGetChildById("autoBless"):setChecked(helperConfig.autoBless)
  enableButtons:recursiveGetChildById("enableMagicShooter"):setChecked(helperConfig.magicShooterEnabled)
  enableButtons:recursiveGetChildById("enableAutoTarget"):setChecked(helperConfig.autoTargetEnabled)
  local autoTargetMode = enableButtons:recursiveGetChildById("autoTargetMode")
  for k, v in pairs(autoTargetModes) do
    if v == helperConfig.autoTargetMode then
      autoTargetMode:setCurrentOption(k)
      break
    end
  end
end

function saveSettings()
  local player = g_game.getLocalPlayer()
  if not player then
    return
  end

  if not LoadedPlayer:isLoaded() then return end

  local folder = "/characterdata/" .. LoadedPlayer:getId() .. "/helper.json"
  local status, result = pcall(function() return json.encode(helperConfig, 2) end)
  if not status then
    return onError("Error while saving helper profile settings. Data won't be saved. Details: " .. result)
  end

  if result:len() > 100 * 1024 * 1024 then
    return onError("Something went wrong, file is above 100MB, won't be saved")
  end

  g_resources.writeFileContents(folder, result)
end

function loadSettings()
  local player = LoadedPlayer:getId()
  local folder = "/characterdata/" .. player .. "/helper.json"

  helperConfig = {
    spells = {
      { id = 0, percent = 80 },
      { id = 0, percent = 80 },
      { id = 0, percent = 80 }
    },
    potions = {
      { id = 0, percent = 50, priority = 0 },
      { id = 0, percent = 50, priority = 0 },
      { id = 0, percent = 50, priority = 0 }
    },
    training = {
      { id = 0, percent = 0, enabled = false }
    },
    haste = {
      { id = 0, enabled = false, safecast = false }
    },
    friendhealing = { mode = "PT", percent = 99, enabled = false, prioritizeFriend = false, list = {}, ptOrder = {} },
    gransiohealing = { mode = "PT", percent = 99, enabled = false, prioritizeFriend = false, list = {}, ptOrder = {} },

    shooterProfiles = {
      ["Default"] = deepCopy(defaultShooterProfile)
    },
    selectedShooterProfile = "Default",

    autoEatFood = false,
    autoReconnect = false,
    autoSellLoot = false,
    autoBless = false,
    magicShooterEnabled = false,
    magicShooterOnHold = false,
    autoTargetEnabled = false,
    autoTargetMode = autoTargetModes["F"],
    currentLockedTargetId = 0,

    -- Mage-only magic-shield suite (utamo vita / exana vita / shield potion).
    mageShield = {
      utamo  = { enabled = false, life = 30, renew = false, renewShield = 50, hotkey = '' },
      exana  = { enabled = false, life = 80, hotkey = '' },
      potion = { enabled = false, life = 0, shield = 0, onlyVitaCd = false, forceOnFear = false, itemId = 0 }
    }
  }

  if g_resources.fileExists(folder) then
    local status, result = pcall(function()
      return json.decode(g_resources.readFileContents(folder))
    end)

    if not status then
      return false
    end

    helperConfig = result

    -- Magic-shield suite migration (older saves predate it).
    helperConfig.mageShield = helperConfig.mageShield or {}
    helperConfig.mageShield.utamo  = helperConfig.mageShield.utamo  or { enabled = false, life = 30, renew = false, renewShield = 50, hotkey = '' }
    helperConfig.mageShield.exana  = helperConfig.mageShield.exana  or { enabled = false, life = 80, hotkey = '' }
    helperConfig.mageShield.potion = helperConfig.mageShield.potion or { enabled = false, life = 0, shield = 0, onlyVitaCd = false, forceOnFear = false, itemId = 0 }

    -- hot-fix para caso ja tenha carregado vazio
    if not result.spells then
      helperConfig.spells = {
        { id = 0, percent = 80 },
        { id = 0, percent = 80 },
        { id = 0, percent = 80 }
      }
    end
    if #helperConfig.spells < 3 then
      table.insert(helperConfig.spells, { id = 0, percent = 0 })
    end
    for _, k in pairs(helperConfig.spells) do
      if k.percent == 0 then
        k.percent = 80
      end
    end
    if not result.potions then
      helperConfig.potions = {
        { id = 0, percent = 50, priority = 0 },
        { id = 0, percent = 50, priority = 0 },
        { id = 0, percent = 50, priority = 0 }
      }
    end
    for _, k in pairs(helperConfig.potions) do
      if k.percent == 0 then
        k.percent = 50
      end

      if not k.priority then
        k.priority = 0
      end
    end
    if not result.training then
      helperConfig.training = {
        { id = 0, percent = 0, enabled = false }
      }
    end
    if not result.haste then
      helperConfig.haste = {
        { id = 0, enabled = false, safecast = false }
      }
    end
    -- Friend/Gran-Sio healing migrated from the old 2-fixed-slot model to the new
    -- PT/List priority-list model. Old saves (array with [1].name) are incompatible,
    -- so reset to the new default when the new `mode` field is missing.
    if type(helperConfig.friendhealing) ~= "table" or helperConfig.friendhealing.mode == nil then
      helperConfig.friendhealing = { mode = "PT", percent = 99, enabled = false, prioritizeFriend = false, list = {}, ptOrder = {} }
    end
    helperConfig.friendhealing.list = helperConfig.friendhealing.list or {}
    helperConfig.friendhealing.ptOrder = helperConfig.friendhealing.ptOrder or {}
    helperConfig.friendhealing.prioritizeFriend = helperConfig.friendhealing.prioritizeFriend or false
    if type(helperConfig.gransiohealing) ~= "table" or helperConfig.gransiohealing.mode == nil then
      helperConfig.gransiohealing = { mode = "PT", percent = 99, enabled = false, prioritizeFriend = false, list = {}, ptOrder = {} }
    end
    helperConfig.gransiohealing.list = helperConfig.gransiohealing.list or {}
    helperConfig.gransiohealing.ptOrder = helperConfig.gransiohealing.ptOrder or {}
    helperConfig.gransiohealing.prioritizeFriend = helperConfig.gransiohealing.prioritizeFriend or false
    if not result.shooterProfiles then
      result.selectedShooterProfile = "Default"
      result.shooterProfiles = {
        ["Default"] = defaultShooterProfile
      }
    end

    for profileName, profile in pairs(helperConfig.shooterProfiles) do
      if not profile.autoTargetMode then
        profile.autoTargetMode = autoTargetModes['F']
      end
    end

    if not result.autoEatFood then
      helperConfig.autoEatFood = false
    end
    if not result.autoReconnect then
      helperConfig.autoReconnect = false
    end
    if not result.autoSellLoot then
      helperConfig.autoSellLoot = false
    end
    if not result.autoBless then
      helperConfig.autoBless = false
    end
    if not result.magicShooterEnabled then
      helperConfig.magicShooterEnabled = false
    end
    if not result.magicShooterOnHold then
      helperConfig.magicShooterOnHold = false
    end
    if not result.autoTargetEnabled then
      helperConfig.autoTargetEnabled = false
    end
    if not result.autoTargetMode then
      helperConfig.autoTargetMode = autoTargetModes["F"]
    end
    if not result.currentLockedTargetId then
      helperConfig.currentLockedTargetId = 0
    end
    return true
  end
end

-- ---------------------------------------------------------------------------
-- Auto-training: pick the best reachable dummy and START on the highest one.
-- Ranking: dummy LEVEL (desc) > rate tier (premium 150 > house 120/130 > public
-- 100) > distance. The level is server-only (a custom attribute) and does NOT come
-- in the normal item data, so we ask the server for it via a custom extended opcode
-- (202): one request returns every nearby dummy's level ("x,y,z,level;..."), which
-- we cache per tile. Training is sticky server-side ("You are already training!"),
-- so we resolve levels and commit to one target before casting. On a server
-- rejection (busy / decoration / wrong house) we blacklist that tile and fall to
-- the next-best, so training never stalls on a full dummy.
-- ---------------------------------------------------------------------------
local DUMMY_LEVELS_OPCODE = 202   -- mirror of data/scripts/.../#extended_opcode.lua on the server
local LEVEL_CACHE_TTL   = 600000  -- dummy levels change very rarely; refresh every 10 min
local MAX_LEVEL_WAIT    = 3000    -- max ms to wait for the level reply before committing

local dummyBlacklist    = {}    -- "x,y,z" -> expiry millis
local lastTriedDummyPos = nil   -- dummy we last issued a train on (so a failure msg blacklists it)
local dummyLevelCache   = {}    -- "x,y,z" -> { level = N, ts = millis } (from the server reply)
local lastLevelRequest  = 0     -- throttle for the dummy-levels request
local currentTrainTarget = nil  -- position we've committed to training on (sticky)
local trainSelectStart   = 0    -- when the current (re)selection began, for the level wait

local function dummyPosKey(pos) return pos.x .. ',' .. pos.y .. ',' .. pos.z end

local function reachFor(weaponId)
  return (weaponId and farUseExercises[weaponId]) and 5 or 1
end

local function isDummyBlacklisted(pos)
  local key = dummyPosKey(pos)
  local expiry = dummyBlacklist[key]
  if not expiry then return false end
  if g_clock.millis() >= expiry then dummyBlacklist[key] = nil; return false end
  return true
end

local function blacklistDummy(pos, ms)
  if not pos then return end
  dummyBlacklist[dummyPosKey(pos)] = g_clock.millis() + (ms or 20000)
end

-- Find the dummy item currently on a tile (positions are stable; item ptrs are not).
local function findDummyOnTile(pos)
  local tile = g_map.getTile(pos)
  if not tile then return nil end
  for _, thing in ipairs(tile:getThings()) do
    if thing:isItem() and dummyRates[thing:getId()] then return thing end
  end
  return nil
end

-- Ask the server (extended opcode 202) for the levels of dummies around us. One
-- round-trip resolves them all (no per-dummy looks, no look-text spam). Throttled;
-- the reply arrives asynchronously in onDummyLevels and fills dummyLevelCache.
local function requestDummyLevels()
  local now = g_clock.millis()
  if now - lastLevelRequest < 800 then return end
  local proto = g_game.getProtocolGame()
  if not proto then return end
  lastLevelRequest = now
  pcall(function() proto:sendExtendedOpcode(DUMMY_LEVELS_OPCODE, "") end)
end

-- Best reachable dummy for the given weapon: highest level, then rate, then nearest.
-- Melee weapons (not far-use) only consider adjacent dummies. The level is resolved
-- via the server (extended opcode) only when there is more than one premium to choose
-- between. Returns (item, position, levelsPending).
function getExerciseDummy(weaponId)
  local playerPos = player:getPosition()
  local reach = reachFor(weaponId)
  local now = g_clock.millis()
  local list, premiums = {}, {}
  -- Scan only the tiles within reach on the player's floor. (g_map.findItemsById would
  -- instead scan the WHOLE loaded map -- all 16 floors -- once PER dummy id; this is a
  -- handful of cheap tile lookups instead.)
  for dx = -reach, reach do
    for dy = -reach, reach do
      local pos = { x = playerPos.x + dx, y = playerPos.y + dy, z = playerPos.z }
      if not isDummyBlacklisted(pos) then
        local tile = g_map.getTile(pos)
        if tile then
          for _, thing in ipairs(tile:getThings()) do
            if thing:isItem() then
              local rate = dummyRates[thing:getId()]
              if rate then
                local entry = { position = pos, item = thing, rate = rate,
                                dist = getDistanceBetween(playerPos, pos), level = 0 }
                list[#list + 1] = entry
                if rate >= 150 then premiums[#premiums + 1] = entry end
                break  -- at most one dummy per tile
              end
            end
          end
        end
      end
    end
  end

  -- Only resolve levels when there is a real choice between premium dummies.
  local pending = false
  if #premiums >= 2 then
    for _, e in ipairs(premiums) do
      local c = dummyLevelCache[dummyPosKey(e.position)]
      if c and (now - c.ts) < LEVEL_CACHE_TTL then
        e.level = c.level
      else
        pending = true
      end
    end
    if pending then requestDummyLevels() end  -- server reply fills the cache (onDummyLevels)
  end

  table.sort(list, function(a, b)
    if a.level ~= b.level then return a.level > b.level end
    if a.rate ~= b.rate then return a.rate > b.rate end
    return a.dist < b.dist
  end)
  for _, data in ipairs(list) do
    if g_map.isSightClear(data.position, playerPos) then
      return data.item, data.position, pending
    end
  end
  return nil, nil, pending
end

-- Issue one training attempt on the committed (or best) dummy. Returns true if a
-- dummy was used. Because training is sticky we keep hitting the same committed
-- target; we only (re)select when it is lost, and we wait briefly for look results
-- so we commit to the HIGHEST-level dummy rather than locking onto a weaker one.
local function issueExerciseTrain(itemId)
  if not player then return false end
  -- Training only works inside a protection zone; skip the whole scan/request/use
  -- (and the server round-trip) entirely while we're outside one.
  if not player:isInProtectionZone() then return false end
  local reach = reachFor(itemId)

  -- 1. Committed target still valid? Re-issue on it (resumes after a weapon swap).
  if currentTrainTarget then
    if not isDummyBlacklisted(currentTrainTarget)
        and getDistanceBetween(player:getPosition(), currentTrainTarget) <= reach then
      local item = findDummyOnTile(currentTrainTarget)
      if item then
        lastTriedDummyPos = currentTrainTarget
        g_game.doThing(false)
        g_game.useInventoryItemWith(itemId, item)
        g_game.doThing(true)
        return true
      end
    end
    currentTrainTarget = nil  -- lost it; reselect
    trainSelectStart = 0
  end

  -- 2. Fresh selection.
  if trainSelectStart == 0 then trainSelectStart = g_clock.millis() end
  local item, pos, pending = getExerciseDummy(itemId)
  if not item then
    lastTriedDummyPos = nil
    trainSelectStart = 0
    return false
  end

  -- 3. Premium levels still resolving: hold off committing (briefly) so we don't
  --    lock onto a lower-level dummy. Retry once the looks come back.
  if pending and (g_clock.millis() - trainSelectStart) < MAX_LEVEL_WAIT then
    scheduleEvent(function()
      local cb = toolsPanel and toolsPanel:recursiveGetChildById("autoTrainingCheck")
      if cb and cb:isChecked() and g_game.isOnline() and player
          and player:getInventoryCount(itemId, 0) > 0 then
        issueExerciseTrain(itemId)
      end
    end, 600)
    return false
  end

  -- 4. Commit to this dummy and train.
  currentTrainTarget = pos
  trainSelectStart = 0
  lastTriedDummyPos = pos
  g_game.doThing(false)
  g_game.useInventoryItemWith(itemId, item)
  g_game.doThing(true)
  return true
end

function checkExerciseEvent()
  local checkBox = toolsPanel:recursiveGetChildById("autoTrainingCheck")
  if not checkBox:isChecked() then
    return
  end

  local itemBox = toolsPanel:recursiveGetChildById("autoTrainingItem").potionItem
  if not itemBox or itemBox:getItemId() == 0 then
    return checkBox:setChecked(false)
  end

  local itemId = itemBox:getItemId()
  if player:getInventoryCount(itemId, 0) == 0 then
    return checkBox:setChecked(false)
  end

  -- No reachable dummy this tick: keep training enabled and just retry next cycle
  -- (the player may walk back into range, or a busy dummy may free up).
  issueExerciseTrain(itemId)
end

-- onTextMessage listener for training rejections: blacklist the tile we just tried
-- and retry the next-best. "Already training!" / "Get closer" / "protection zone"
-- are about the player (not the dummy) and are intentionally ignored.
function onExerciseTextMessage(messageMode, message)
  if not message or not lastTriedDummyPos then return end
  local checkBox = toolsPanel and toolsPanel:recursiveGetChildById("autoTrainingCheck")
  if not checkBox or not checkBox:isChecked() then return end
  local lt = message:lower()
  local ms
  if lt:find('exercise dummy is busy', 1, true) then
    ms = 20000                 -- full: a slot should free up fairly soon
  elseif lt:find('just a decoration', 1, true) then
    ms = 600000                -- decoration dummy: never trainable
  elseif lt:find('inside the house to use this dummy', 1, true) then
    ms = 60000                 -- can't reach it from outside the house
  else
    return
  end
  blacklistDummy(lastTriedDummyPos, ms)
  if currentTrainTarget and dummyPosKey(currentTrainTarget) == dummyPosKey(lastTriedDummyPos) then
    currentTrainTarget = nil   -- our committed dummy went bad; reselect
    trainSelectStart = 0
  end
  lastTriedDummyPos = nil
  -- Try the next-best dummy right away instead of waiting the full 10s cycle.
  local itemBox = toolsPanel:recursiveGetChildById("autoTrainingItem")
  itemBox = itemBox and itemBox.potionItem
  local itemId = itemBox and itemBox:getItemId() or 0
  if itemId > 0 and player and g_game.isOnline() and player:getInventoryCount(itemId, 0) > 0 then
    scheduleEvent(function() issueExerciseTrain(itemId) end, 150)
  end
end

-- Server reply (extended opcode 202) with nearby dummy levels: "x,y,z,level;...".
-- Caches each so the auto-trainer can rank dummies by level. See the server's
-- data/scripts/creaturescripts/others/#extended_opcode.lua.
function onDummyLevels(protocol, opcode, buffer)
  if not buffer then return end
  local now = g_clock.millis()
  for entry in buffer:gmatch('[^;]+') do
    local x, y, z, lvl = entry:match('(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+)')
    if x then
      dummyLevelCache[x .. ',' .. y .. ',' .. z] = { level = tonumber(lvl) or 0, ts = now }
    end
  end
end

-- Register the dummy-levels opcode once (re-register cleanly on a module reload).
pcall(function() ProtocolGame.unregisterExtendedOpcode(DUMMY_LEVELS_OPCODE) end)
pcall(function() ProtocolGame.registerExtendedOpcode(DUMMY_LEVELS_OPCODE, onDummyLevels) end)

eventTable.checkExerciseEvent.action = checkExerciseEvent

function assignExerciseEvent(button)
  g_mouse.updateGrabber(mouseGrabberWidget, 'target')
  mouseGrabberWidget:grabMouse()
  helper:hide()
  g_mouse.pushCursor('target')
  mouseGrabberWidget.onMouseRelease = function(self, mousePosition, mouseButton)
    onAssignExercise(self, mousePosition, mouseButton, button)
  end
end

function onAssignExercise(self, mousePosition, mouseButton, button)
  g_mouse.updateGrabber(mouseGrabberWidget, 'target')
  mouseGrabberWidget:ungrabMouse()
  g_mouse.popCursor('target')
  mouseGrabberWidget.onMouseRelease = nil
  helper:show()

  local rootWidget = g_ui.getRootWidget()
  if not rootWidget then
    return true
  end

  local clickedWidget = rootWidget:recursiveGetChildByPos(mousePosition, false)
  if not clickedWidget then
    return true
  end

  local exerciseId = 0
  if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
    local item = clickedWidget:getItem()
    if item then
      exerciseId = item:getId()
    end
  end

  if table.find(exercises, exerciseId) then
    button:setImageSource('/images/ui/item')
    if not button:getChildById('potionItem') then
      local itemWidget = g_ui.createWidget('PotionItem', button)
      if itemWidget then
        itemWidget:setId('potionItem')
      end
    end
    local itemWidget = button:getChildById('potionItem')
    if itemWidget then
      itemWidget:setItemId(exerciseId)
    end
  else
    modules.game_textmessage.displayFailureMessage(tr('Invalid exercise!'))
  end
end

function onCheckPotionPriority(button)
  local index = tonumber(button:getId():match("%d+"))
  local cfg = helperConfig.potions[index + 1]
  if not cfg or (cfg.id or 0) == 0 then return true end -- empty slot: nothing to toggle

  if button:getActionId() == 1 then -- currently red (Health) -> switch to blue (Mana)
    button:setActionId(2)
    button:setImageSource("/images/skin/show-gui-help-blue")
    button:setTooltip("This potion is healing mana...")
    cfg.priority = 2
  else -- currently blue/unset -> switch to red (Health)
    button:setActionId(1)
    button:setImageSource("/images/skin/show-gui-help-red")
    button:setTooltip("This potion is healing health...")
    cfg.priority = 1
  end
end

-- Reflect each potion row's "I" from the saved priority (red = Health threshold, blue =
-- Mana, grey = empty). Re-applied after the healing menu sets its generic tooltips so the
-- icon + tooltip always match the configured Health/Mana mode.
function applyPotionPriorityButtons()
  if not healingPanel then return end
  for k, v in pairs(helperConfig.potions) do
    local btn = healingPanel:recursiveGetChildById("priority" .. (k - 1))
    if btn then
      if (v.id or 0) == 0 then
        btn:setImageSource("/images/skin/show-gui-help-grey")
        btn:setActionId(0)
      else
        local pr = (v.priority == 2) and 2 or 1
        btn:setImageSource(pr == 2 and "/images/skin/show-gui-help-blue" or "/images/skin/show-gui-help-red")
        btn:setTooltip(pr == 2 and "This potion is healing mana..." or "This potion is healing health...")
        btn:setActionId(pr)
      end
    end
  end
end

-- Read-only accessor for the master helper on/off state (the scripting API's
-- bot.helper.enabled/enable/disable reads this; botStatus() flips it).
function isHelperEnabled()
  return hotkeyHelperStatus == true
end

function botStatus()
  local helperStatus = helper.contentPanel:recursiveGetChildById("helperStatus")
  local helperStatusLabel = helper.contentPanel:recursiveGetChildById("helperStatusLabel")
  local helperTrackerStatus = helperTracker:recursiveGetChildById("helperStatus")

  hotkeyHelperStatus = not hotkeyHelperStatus

  if hotkeyHelperStatus then
    helperStatus:setImageSource("/images/store/icon-yes")
    helperStatusLabel:setText("Enabled")
    helperTrackerStatus:setText("Active")
    helperTrackerStatus:setColor("$var-text-cip-color-green")
    helperStatus:setTooltip(
    " - Helper Status: Enabled\n\nYou can Enable or Disable the helper using\nthe default hotkey (Pause Break).\n\nAlso you can change the hotkey on settings.")
    modules.game_textmessage.displayFailureMessage(tr('Helper Status: Enabled'))
  else
    helperStatus:setImageSource("/images/store/icon-no")
    helperTrackerStatus:setText("Inactive")
    helperStatusLabel:setText("Disabled")
    helperTrackerStatus:setColor("$var-text-cip-store-red")
    helperStatus:setTooltip(
    " - Helper Status: Disabled\n\nYou can Enable or Disable the helper using\nthe default hotkey (Pause Break).\n\nAlso you can change the hotkey on settings.")
    modules.game_textmessage.displayFailureMessage(tr('Helper Status: Disabled'))
  end

  if not helperTracker.clickHandlersSetup then
    if helperTrackerStatus then
      helperTrackerStatus.onClick = function()
        botStatus()
      end
      helperTrackerStatus:setTooltip("Click to toggle Helper status")
    end

    local shooterStatusWidget = helperTracker:recursiveGetChildById("shooterStatus")
    if shooterStatusWidget then
      shooterStatusWidget.onClick = function()
        local widget = shooterPanel:recursiveGetChildById("enableMagicShooter")
        if widget then
          widget:setChecked(not widget:isChecked())
          toggleMagicShooter(widget)
        end
      end
      shooterStatusWidget:setTooltip("Click to toggle Caster")
    end

    local targetStatusWidget = helperTracker:recursiveGetChildById("targetStatus")
    if targetStatusWidget then
      targetStatusWidget.onClick = function()
        local widget = shooterPanel:recursiveGetChildById("enableAutoTarget")
        if widget then
          widget:setChecked(not widget:isChecked())
          toggleAutoTarget(widget)
        end
      end
      targetStatusWidget:setTooltip("Click to toggle Auto Target")
    end

    local currentPresetWidget = helperTracker:recursiveGetChildById("currentPresetName")
    if currentPresetWidget then
      currentPresetWidget.onClick = function()
        toggleShooterPreset()
      end
      currentPresetWidget:setTooltip("Click to cycle through shooter presets")
    end

    helperTracker.clickHandlersSetup = true
  end

  local shooterTracker = helperTracker:recursiveGetChildById("shooterStatus")
  if shooterTracker then
    shooterTracker:setText(helperConfig.magicShooterEnabled and "Active" or "Inactive")
    shooterTracker:setColor(helperConfig.magicShooterEnabled and "$var-text-cip-color-green" or "$var-text-cip-store-red")
  end

  local targetTracker = helperTracker:recursiveGetChildById("targetStatus")
  if targetTracker then
    targetTracker:setText(helperConfig.autoTargetEnabled and "Active" or "Inactive")
    targetTracker:setColor(helperConfig.autoTargetEnabled and "$var-text-cip-color-green" or "$var-text-cip-store-red")
  end

  local currentPresetLabel = helperTracker:recursiveGetChildById("currentPresetName")
  if currentPresetLabel then
    currentPresetLabel:setText(helperConfig.selectedShooterProfile)
    currentPresetLabel:setTooltip("Click to cycle through shooter presets")
  end
end

function toggleNextWindow()
  local widgetList = {
    "healingMenu",
    "toolsMenu",
    "shooterMenu"
  }

  local selectedIndex = nil
  for i, widget in ipairs(widgetList) do
    if widget == menuId then
      selectedIndex = i
      break
    end
  end

  if not selectedIndex then
    selectedIndex = 1
  end

  local nextWidgetId = (selectedIndex == #widgetList and 1 or selectedIndex + 1)
  menuId = widgetList[nextWidgetId]
  loadMenu(menuId)
end

function manageHotkeys(typo)
  helper:hide()
  local assignWindow = g_ui.createWidget('ActionAssignWindow', rootWidget)
  assignWindow:setText("Enable/Disable State")
  assignWindow:grabKeyboard()

  local currentHotkey = ""
  local chatMode = Options.isChatOnEnabled
  local currentBind = KeyBind:getKeyBind("Helper", typo)
  if currentBind then
    currentHotkey = currentBind:getFirstKey()
  end

  assignWindow.display:setText(currentHotkey)
  assignWindow.desc:setText("Assign or edit a hotkey to manage Target/Shooter state.")
  assignWindow:setHeight(190)
  g_client.setInputLockWidget(assignWindow)

  assignWindow.onKeyDown = function(assignWindow, keyCode, keyboardModifiers, keyText)
    local keyCombo = determineKeyComboDesc(keyCode, keyboardModifiers, keyText)
    local resetCombo = { "Shift", "Ctrl", "Alt" }
    if table.contains(resetCombo, keyCombo) then
      assignWindow.display:setText('')
      assignWindow.warning:setVisible(false)
      assignWindow.buttonOk:setEnabled(true)
      return true
    end

    assignWindow.display:setText(keyCombo)
    assignWindow.warning:setVisible(false)
    assignWindow.buttonOk:setEnabled(true)
    if KeyBinds:hotkeyIsUsed(keyCombo) or modules.game_actionbar.isHotkeyUsed(keyCombo, false) or modules.game_actionbar.isHotkeyUsed(keyCombo, true) then
      assignWindow.warning:setVisible(true)
      assignWindow.warning:setText("This hotkey is already in use and will be overwritten.")
    end

    if table.contains(blockedKeys, keyCombo) then
      assignWindow.warning:setVisible(true)
      assignWindow.warning:setText("This hotkey is already in use and cannot be overwritten.")
      assignWindow.buttonOk:setEnabled(false)
    end
    return true
  end

  assignWindow.buttonOk.onClick = function()
    local text = tostring(assignWindow.display:getText())
    if #text == 0 then
      if currentBind then
        Options.removeActionHotkey(chatMode and "chatOn" or "chatOff", currentBind.jsonName, false)
        KeyBinds:setupAndReset(Options.currentHotkeySetName, chatMode and "chatOn" or "chatOff")
      end
      g_client.setInputLockWidget(nil)
      assignWindow:destroy()
      return true
    end

    if KeyBinds:hotkeyIsUsed(text) and text ~= '' then
      local key = KeyBind:getKeyBindByHotkey(text)
      if key then
        g_keyboard.unbindKeyDown(text, nil)
        Options.removeActionHotkey(chatMode and "chatOn" or "chatOff", key.jsonName)
      end
    end

    if modules.game_actionbar.isHotkeyUsedByChat(text, chatMode and "chatOn" or "chatOff") then
      local usedButton = modules.game_actionbar.getUsedHotkeyButton(text)
      if usedButton then
        Options.removeHotkey(usedButton:getId())
        g_keyboard.unbindKeyPress(text, nil, m_interface.getRootPanel())
        g_keyboard.unbindKeyDown(text, nil, m_interface.getRootPanel())
        usedButton.cache.hotkey = nil
        modules.game_actionbar.updateButton(usedButton)
      end
    end

    m_settings.CustomHotkeys.checkAndRemoveUsedHotkey(text, chatMode)
    if currentBind then
      Options.updateGeneralHotkey(chatMode and "chatOn" or "chatOff", currentBind.jsonName, text)
      KeyBinds:setupAndReset(Options.currentHotkeySetName, chatMode and "chatOn" or "chatOff")
      currentBind:setFirstKey(text)
      currentBind.firstKey = text
    end

    assignWindow:destroy()
    g_client.setInputLockWidget(nil)
  end

  assignWindow.buttonClear.onClick = function()
    if currentBind then
      Options.removeActionHotkey(chatMode and "chatOn" or "chatOff", currentBind.jsonName, false)
      KeyBinds:setupAndReset(Options.currentHotkeySetName, chatMode and "chatOn" or "chatOff")
    end

    assignWindow:destroy()
    g_client.setInputLockWidget(nil)
  end

  assignWindow.onDestroy = function(widget) helper:show(true) end
end

function onDropSpell(widget, spellWords)
  local spellData = Spells.getSpellDataByWords(spellWords)
  if not spellData then
    return
  end

  local isHealingPanel = string.match(widget:getId(), "^spellButton%d*")
  local isTrainingPanel = string.match(widget:getId(), "^spellTrainingButton")
  local isHastePanel = string.match(widget:getId(), "^hasteButton")
  local isAttackPanel = string.match(widget:getId(), "^attackSpellButton%d*")
  local profile = getShooterProfile()

  if isHealingPanel then
    onSetupDropSpell(widget, spellData, { 2 }, helperConfig.spells)
  elseif isTrainingPanel or isHastePanel then
    onSetupDropSupport(widget, spellData, isHastePanel)
  elseif isAttackPanel then
    onSetupDropSpell(widget, spellData, { 1, 4, 8 }, profile.spells)
  end
end

function onSetupDropSpell(button, spellData, groups, tableToAssign)
  local groupIds = Spells.getGroupIds(spellData)
  local function containsAnyGroup(groups, targetGroups)
    for _, group in ipairs(targetGroups) do
      if table.contains(groups, group) then
        return true
      end
    end
    return false
  end

  local spellId = SpellIcons[spellData.icon][1]
  local playerVocation = translateVocation(player:getVocation())
  local profile = getShooterProfile()

  if containsAnyGroup(groupIds, groups) and table.contains(spellData.vocations, playerVocation) and not ignoredSpellsIds[spellId] then
    local source = SpelllistSettings['Default'].iconsFolder
    local clip = Spells.getImageClipNormal(spellId, 'Default')
    local spell = Spells.getSpellByClientId(tonumber(spellId))

    button:setImageSource(source)
    button:setImageClip(clip)
    button:setBorderColorTop("#1b1b1b")
    button:setBorderColorLeft("#1b1b1b")
    button:setBorderColorRight("#757575")
    button:setBorderColorBottom("#757575")
    button:setBorderWidth(1)
    button:setTooltip("Spell: " .. spellData.name .. "\nWords: " .. spellData.words)

    local slotID = tonumber(button:getId():match("%d+"))
    if button:getId():find("attackSpellButton") then
      profile.spells[slotID + 1].id = tonumber(spellData.id)
    else
      tableToAssign[slotID + 1].id = tonumber(spellData.id)
    end

    if button:getId():find("attackSpellButton") then
      local creaturesMin = shooterPanel:recursiveGetChildById("countMinCreature" .. slotID)
      local forceCast = shooterPanel:recursiveGetChildById("conditionSetting" .. slotID)
      local selfCast = shooterPanel:recursiveGetChildById("selfCast" .. slotID)
      if table.contains(bothCastTypeSpells, spell.id) then -- divine grenade self cast
        if not selfCast then
          selfCast = g_ui.createWidget('CheckBox', creaturesMin:getParent())
          local style = {
            ["width"] = 12,
            ["anchors.top"] = "countMinCreature" .. slotID .. ".top",
            ["anchors.left"] = "countMinCreature" .. slotID .. ".right",
            ["margin-top"] = 6,
            ["margin-left"] = 5
          }
          selfCast:mergeStyle(style)
          selfCast:setId('selfCast' .. slotID)
          selfCast:setTooltip('Cast on yourself')
          selfCast:setVisible(true)
          selfCast.onCheckChange = function() toggleSelfCast(selfCast:getId():match("%d+"), selfCast:isChecked()) end
        end
      end

      if selfCast and not table.contains(bothCastTypeSpells, spell.id) then
        profile.spells[slotID + 1].selfCast = false
        selfCast:destroy()
      end

      if (spell.range > 0 or not spell.area) and not table.contains(bothCastTypeSpells, spell.id) then
        profile.spells[slotID + 1].creatures = 1
        creaturesMin:setCurrentOption("1+")
        creaturesMin:disable()
        if forceCast then
          forceCast:setChecked(profile.spells[slotID + 1].forceCast)
          forceCast:setVisible(true)
        end
      else
        creaturesMin:enable()
        if forceCast then
          forceCast:setChecked(false)
          forceCast:setVisible(false)
          profile.spells[slotID + 1].forceCast = false
        end
      end
    end
  end
end

function onSetupDropSupport(widget, spellData, hasteSpell)
  local playerVocation = translateVocation(player:getVocation())
  if hasteSpell and not table.contains(hasteWhiteList[playerVocation], spellData.id) then
    return
  end

  if not hasteSpell and not (table.contains(Spells.getGroupIds(spellData), 3) or table.contains(Spells.getGroupIds(spellData), 2)) then
    return
  end

  if not hasteSpell and table.contains(hasteWhiteList[playerVocation], spellData.id) then
    return
  end

  local spellId = SpellIcons[spellData.icon][1]
  if table.contains(spellData.vocations, playerVocation) and not ignoredTrainingSpells[spellData.id] then
    local source = SpelllistSettings['Default'].iconsFolder
    local clip = Spells.getImageClipNormal(spellId, 'Default')

    widget:setImageSource(source)
    widget:setImageClip(clip)
    widget:setBorderColorTop("#1b1b1b")
    widget:setBorderColorLeft("#1b1b1b")
    widget:setBorderColorRight("#757575")
    widget:setBorderColorBottom("#757575")
    widget:setBorderWidth(1)
    widget:setTooltip("Spell: " .. spellData.name .. "\nWords: " .. spellData.words)

    local slotID = tonumber(widget:getId():match("%d+"))
    if hasteSpell then
      helperConfig.haste[1].id = tonumber(spellData.id)
    else
      helperConfig.training[1].id = tonumber(spellData.id)
      if helperConfig.training[1].percent == 0 then
        helperConfig.training[1].percent = 100
        updateTrainingPercent('spellTrainingButton0', helperConfig.training[1].percent)
      end
    end
  end
end

function onSearchTextChange(text)
  local spellList = window:recursiveGetChildById('spellList')
  for _, child in pairs(spellList:getChildren()) do
    local name = child:getText():lower()
    if name:find(text:lower()) or text == '' or #text < 3 then
      child:setVisible(true)
    else
      child:setVisible(false)
    end
  end
end

function onClearSearchText()
  local search = window:recursiveGetChildById('searchText')
  search:setText('')
end

function toggleHelperTracker()
  if helperTracker:isVisible() then
    helperTracker:close()
    helperTracker:setParent(nil)
  else
    helperTracker:open()
    if m_interface.addToPanels(helperTracker) then
      helperTracker:getParent():moveChildToIndex(helperTracker, #helperTracker:getParent():getChildren())
    end
  end
end

function move(panel, height, index, minimized, locked)
  helperTracker:setParent(panel)
  helperTracker:open()
  helperTracker:setHeight(height)

  if minimized then
    helperTracker:minimize()
  end
  if locked then
    helperTracker:lock(true)
  end
  modules.game_sidebuttons.setButtonVisible("helperDialog", true)
  return helperTracker
end
