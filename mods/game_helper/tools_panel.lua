-- Tools Panel Module
-- Manages all tools functionality: Gold Change, Exercise Training,
-- Quiver Refill (Paladin), Magic Shield (Sorcerer/Druid)
-- Based on the same pattern as equip_panel.lua

local tools = {}

-- Export module immediately so it's available for OTUI callbacks
modules.game_helper = modules.game_helper or {}
modules.game_helper.tools = tools

-- Local references
local toolsPanel = nil
local paladinPanel = nil
local magePanel = nil
local helper = nil
local automationEvent = nil
local lastActivityAt = 0
local lastActivityPosition = nil
local lastActivityDirection = nil
local applyingAutomationConfig = false

local AUTOMATION_INTERVAL_MS = 1500
local ANTI_IDLE_THRESHOLD_MS = 300000
local ANTI_IDLE_TURN_INTERVAL_MS = 15000
local lastAntiIdleTurnAt = 0
local lastQuillStateQueryAt = 0
local lastQuillSaleAttemptAt = 0
local lastQuillCapacityCheckAt = 0
local quillCapacityAllowsSale = false
local QUILL_QUERY_INTERVAL_MS = 5000
local QUILL_ATTEMPT_INTERVAL_MS = 10000
local QUILL_CAPACITY_CHECK_INTERVAL_MS = 60000

function tools.displayLookItemId(thing)
  local config = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not config or config.showLookItemId ~= true or not thing or
      (thing.isCreature and thing:isCreature()) or not thing.getId then
    return
  end
  local itemId = tonumber(thing:getId())
  if not itemId or itemId <= 0 then return end
  scheduleEvent(function()
    if modules.game_console and modules.game_console.addText then
      modules.game_console.addText(string.format('[Item ID: %d]', itemId), MessageModes.Look, 'Server Log')
    end
  end, 1)
end

-- Exercise dummies IDs


-- Magic Shield constants
local MAGIC_SHIELD_SPELL_ID = 44         -- utamo vita
local CANCEL_MAGIC_SHIELD_SPELL_ID = 245 -- exana vita
local MAGIC_SHIELD_POTION_ID = 35563     -- magic shield potion

-- Local references for mouse grabber
local mouseGrabberWidget = nil

-- Quiver refill state
local isRefillingQuiver = false
local lastQuiverRefillTime = 0   -- Cooldown to prevent spam (in milliseconds)

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

local function getMouseGrabber()
  if mouseGrabberWidget then return mouseGrabberWidget end
  mouseGrabberWidget = g_ui.createWidget('UIWidget')
  mouseGrabberWidget:setVisible(false)
  mouseGrabberWidget:setFocusable(false)
  return mouseGrabberWidget
end

local function getPlayer()
  return g_game.getLocalPlayer()
end

local function trimText(value)
  return (tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function helperFunctionsEnabled()
  return not _Helper.isHelperAutomaticFunctionsEnabled or _Helper.isHelperAutomaticFunctionsEnabled()
end

local function samePosition(a, b)
  return a and b and a.x == b.x and a.y == b.y and a.z == b.z
end

local function copyPosition(position)
  return position and { x = position.x, y = position.y, z = position.z } or nil
end

local function getAutomationConfig()
  local config = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not config then return nil end
  config.autoParty = config.autoParty or {
    enabled = false,
    acceptEnabled = false,
    sendList = { '', '', '', '' },
    acceptLeader = ''
  }
  config.autoParty.sendList = config.autoParty.sendList or { '', '', '', '' }
  if config.antiIdle == nil then config.antiIdle = false end
  if config.showLookItemId == nil then config.showLookItemId = false end
  if config.autoQuillSell == nil then config.autoQuillSell = false end
  if config.autoQuillSellBelowCap == nil then config.autoQuillSellBelowCap = false end
  config.autoQuillSellCapacity = math.max(0, tonumber(config.autoQuillSellCapacity) or 100)
  config.botHud = config.botHud or {
    enabled = false,
    size = 'Normal',
    showCavebot = true,
    showTargeting = true,
    showEquipment = true,
    showTimers = true,
    showHaste = true,
    showPlayer = true,
    showAutomation = false,
    showWaypoints = true
  }
  return config
end

local function findVisiblePlayer(name)
  local player = getPlayer()
  local wanted = trimText(name):lower()
  if not player or wanted == '' then return nil end
  local spectators = g_map.getSpectators(player:getPosition(), false) or {}
  for _, creature in ipairs(spectators) do
    if creature and creature ~= player and creature.isPlayer and creature:isPlayer() and
        creature.getName and creature:getName():lower() == wanted then
      return creature
    end
  end
  return nil
end

local function runAutoParty(config)
  if not helperFunctionsEnabled() then return end
  local player = getPlayer()
  if not player then return end

  if config.autoParty.acceptEnabled then
    local leader = findVisiblePlayer(config.autoParty.acceptLeader)
    if leader and leader.getShield and leader:getShield() == ShieldWhiteYellow and g_game.partyJoin then
      g_game.partyJoin(leader:getId())
      return
    end
  end

  if not config.autoParty.enabled then return end
  local myName = player:getName():lower()
  for i = 1, 4 do
    local name = trimText(config.autoParty.sendList[i])
    if name ~= '' and name:lower() ~= myName then
      local creature = findVisiblePlayer(name)
      if creature and creature.getShield and creature:getShield() == ShieldNone and g_game.partyInvite then
        g_game.partyInvite(creature:getId())
        return
      end
    end
  end
end

local function runAntiIdle(config, now)
  local player = getPlayer()
  if not player then return end
  local position = player:getPosition()
  local direction = player:getDirection()
  if not samePosition(position, lastActivityPosition) or direction ~= lastActivityDirection then
    lastActivityAt = now
    lastActivityPosition = copyPosition(position)
    lastActivityDirection = direction
  end
  if not config.antiIdle or not helperFunctionsEnabled() then return end
  if now - lastActivityAt < ANTI_IDLE_THRESHOLD_MS or now - lastAntiIdleTurnAt < ANTI_IDLE_TURN_INTERVAL_MS then return end
  local nextDirection = (direction + 1) % 4
  g_game.turn(nextDirection)
  lastAntiIdleTurnAt = now
  lastActivityDirection = nextDirection
end

local function capacityAllowsAutomaticQuillSale(config, now)
  if not config.autoQuillSellBelowCap then return true end
  if lastQuillCapacityCheckAt > 0 and
      now - lastQuillCapacityCheckAt < QUILL_CAPACITY_CHECK_INTERVAL_MS then
    return quillCapacityAllowsSale
  end

  local player = getPlayer()
  quillCapacityAllowsSale = player ~= nil and
      player:getFreeCapacity() < config.autoQuillSellCapacity
  lastQuillCapacityCheckAt = now
  return quillCapacityAllowsSale
end

local function tryAutomaticQuillSale(config, state, now)
  if not config.autoQuillSell or not helperFunctionsEnabled() then return false end
  local player = getPlayer()
  if not player or player:isInProtectionZone() then return false end
  if not capacityAllowsAutomaticQuillSale(config, now) then return false end
  local inventory = modules.game_inventory
  if not inventory or not inventory.requestAutomaticQuillSale then return false end
  state = state or (inventory.getSummonQuillState and inventory.getSummonQuillState() or nil)
  if not state or not state.unlocked or not state.hasLootPouch or (state.cooldown or 0) > 0 then return false end
  if lastQuillSaleAttemptAt > 0 and now - lastQuillSaleAttemptAt < QUILL_ATTEMPT_INTERVAL_MS then return false end

  -- Arm the throttle only when a request actually went out. Arming it up front
  -- meant a rejected attempt -- a cooldown reading that was stale by a moment,
  -- or a sale still pending -- blocked every retry for the full interval.
  local sent = inventory.requestAutomaticQuillSale()
  if sent then lastQuillSaleAttemptAt = now end
  return sent
end

function tools.onSummonQuillStateChanged(state)
  local config = getAutomationConfig()
  if not config then return end
  tryAutomaticQuillSale(config, state, g_clock.millis())
end

local function runAutomationCycle()
  if not g_game.isOnline() then return end
  local config = getAutomationConfig()
  if not config then return end
  local now = g_clock.millis()
  runAntiIdle(config, now)
  runAutoParty(config)
  if config.autoQuillSell and helperFunctionsEnabled() and
      capacityAllowsAutomaticQuillSale(config, now) then
    local inventory = modules.game_inventory
    if inventory then
      if now - lastQuillStateQueryAt >= QUILL_QUERY_INTERVAL_MS and inventory.querySummonQuillState then
        inventory.querySummonQuillState()
        lastQuillStateQueryAt = now
      end
      local state = inventory.getSummonQuillState and inventory.getSummonQuillState() or nil
      tryAutomaticQuillSale(config, state, now)
    end
  end
  local cavebot = modules.game_helper and modules.game_helper.cavebot
  if cavebot and cavebot.refreshBotHud then cavebot.refreshBotHud() end
end

local function startAutomationCycle()
  if automationEvent then return end
  lastActivityAt = g_clock.millis()
  local player = getPlayer()
  lastActivityPosition = player and copyPosition(player:getPosition()) or nil
  lastActivityDirection = player and player:getDirection() or nil
  automationEvent = cycleEvent(function()
    local ok, err = pcall(runAutomationCycle)
    if not ok and g_logger then g_logger.error('[game_helper] automation cycle: ' .. tostring(err)) end
  end, AUTOMATION_INTERVAL_MS)
end

local function stopAutomationCycle()
  if automationEvent then
    removeEvent(automationEvent)
    automationEvent = nil
  end
end

local function getDistanceBetween(p1, p2)
  return math.max(math.abs(p1.x - p2.x), math.abs(p1.y - p2.y))
end

local function safeDoThing(flag)
  if g_game and type(g_game.doThing) == "function" then
    g_game.doThing(flag)
  end
end

-- Helper function to get toolsPanel (lazy initialization)
local function getToolsPanel()
  if toolsPanel then return toolsPanel end
  local rootWidget = g_ui.getRootWidget()
  if rootWidget then
    local helperWindow = rootWidget:recursiveGetChildById('helperWindow')
    if helperWindow then
      local container = helperWindow:recursiveGetChildById('toolsPanelContainer')
      if container then
        toolsPanel = helperWindow
      end
    end
  end
  return toolsPanel
end

-- Helper function to get paladinPanel
local function getPaladinPanel()
  if paladinPanel then return paladinPanel end
  local rootWidget = g_ui.getRootWidget()
  if rootWidget then
    local helperWindow = rootWidget:recursiveGetChildById('helperWindow')
    if helperWindow then
      local container = helperWindow:recursiveGetChildById('toolsPanelContainer')
      if container then
        paladinPanel = container:recursiveGetChildById('paladinPanel')
      end
    end
  end
  return paladinPanel
end

-- Helper function to get magePanel
local function getMagePanel()
  if magePanel then return magePanel end
  local rootWidget = g_ui.getRootWidget()
  if rootWidget then
    local helperWindow = rootWidget:recursiveGetChildById('helperWindow')
    if helperWindow then
      local container = helperWindow:recursiveGetChildById('toolsPanelContainer')
      if container then
        magePanel = container:recursiveGetChildById('magePanel')
      end
    end
  end
  return magePanel
end

local function getHelperWindow()
  local rootWidget = g_ui.getRootWidget()
  if rootWidget then
    return rootWidget:recursiveGetChildById('helperWindow')
  end
  return nil
end

-- Get player vocation ID (normalized to base vocation)
-- Game client IDs: Sorcerer=1, Druid=2, Paladin=3, Knight=4, Monk=9
-- Promoted: MasterSorcerer=5/13, ElderDruid=6/14, RoyalPaladin=7/12, EliteKnight=8/11, ExaltedMonk=10/15
-- Returns normalized ID: Knight=1, Paladin=2, Sorcerer=3, Druid=4, Monk=5
local function getPlayerVocationId()
  local player = getPlayer()
  if not player then return 0 end
  local voc = player:getVocation()
  -- Normalize to base vocation (remove promotion)
  if voc == 4 or voc == 8 or voc == 11 then return 1 end -- Knight / Elite Knight
  if voc == 3 or voc == 7 or voc == 12 then return 2 end -- Paladin / Royal Paladin
  if voc == 1 or voc == 5 or voc == 13 then return 3 end -- Sorcerer / Master Sorcerer
  if voc == 2 or voc == 6 or voc == 14 then return 4 end -- Druid / Elder Druid
  if voc == 9 or voc == 10 or voc == 15 then return 5 end -- Monk / Exalted Monk
  return voc
end

-- Check if player has magic shield state
local function hasMagicShield()
  local player = getPlayer()
  if not player then return false end
  local states = player:getStates()
  if not states then return false end
  local manaShield = bit.bor(PlayerStates.ManaShield or 0, PlayerStates.NewMagicShield or 0)
  return bit.band(states, manaShield) ~= 0
end

-- Get spell cooldown from _Helper
local function getSpellCooldown(spellId)
  if _Helper and _Helper.getSpellCooldown then
    return _Helper.getSpellCooldown(spellId)
  end
  return 0
end

-- Get group spell cooldown from _Helper
local function getGroupSpellCooldown(groupId)
  if _Helper and _Helper.getGroupSpellCooldown then
    return _Helper.getGroupSpellCooldown(groupId)
  end
  return 0
end

-- Check if spell is on cooldown
local function isSpellOnCooldown(spellId)
  local cooldown = getSpellCooldown(spellId)
  return cooldown > g_clock.millis()
end

-- Check if spell group is on cooldown
-- Support group is group 3
local function isGroupOnCooldown(groupId)
  local cooldown = getGroupSpellCooldown(groupId)
  return cooldown > g_clock.millis()
end

-- ============================================================
-- GOLD CHANGE FUNCTIONS
-- ============================================================

local pendingGoldChangeEvent = nil
local goldChangeLoopEvent = nil

-- Gold change speed constants
local GOLD_CHANGE_FAST_DELAY = 50    -- Fast mode: 50ms between uses
local GOLD_CHANGE_NORMAL_DELAY = 100 -- Normal mode: 100ms debounce
local GOLD_CHANGE_STACK_THRESHOLD = 5 -- Threshold to switch to fast mode

-- Find item with minimum count in containers
local function findItemWithMinCount(itemId, minCount)
  for _, container in pairs(g_game.getContainers()) do
    for slot = 0, container:getItemsCount() - 1 do
      local item = container:getItem(slot)
      if item and item:getId() == itemId and item:getCount() >= minCount then
        return item
      end
    end
  end
  return nil
end

-- Count all stacks of 100 items and return first found
local function findAndCount100Stacks(itemId)
  local containers = g_game.getContainers()
  if not containers then
    return nil, 0
  end

  local hasContainer = false
  for _ in pairs(containers) do
    hasContainer = true
    break
  end
  if not hasContainer then
    return nil, 0
  end

  local count = 0
  local firstStack = nil
  local firstContainerId = nil
  local firstSlot = nil

  for containerId, container in pairs(containers) do
    local items = container:getItems()
    if items then
      for slot, item in pairs(items) do
        if item:getId() == itemId and item:getCount() == 100 then
          count = count + 1
          if not firstStack then
            firstStack = item
            firstContainerId = containerId
            firstSlot = slot
          end
        end
      end
    end
  end

  return firstStack, count, firstContainerId, firstSlot
end

-- Find any stack of 100 items
local function findAny100(itemId)
  local stack, count, containerId, slot = findAndCount100Stacks(itemId)
  return stack, containerId, slot, count
end

-- Internal function to change gold (returns stack count for speed control)
local function helper_changeGold()
  local goldId = 3031
  local platinumId = 3035

  local stack, _, _, count = findAny100(platinumId)
  if not stack then
    stack, _, _, count = findAny100(goldId)
  end
  if not stack then
    return 0
  end

  -- Tenta usar normalmente, se falhar, tenta useWith como fallback
  local used = g_game.use(stack)
  if used ~= true and g_game.useWith then
    g_game.useWith(stack, stack)
  end
  return count
end

-- Stop the fast change loop
local function stopGoldChangeLoop()
  if goldChangeLoopEvent then
    removeEvent(goldChangeLoopEvent)
    goldChangeLoopEvent = nil
  end
end

-- Fast change loop for when we have many stacks
local function goldChangeLoop()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local player = getPlayer()

  if not g_game.isOnline() or not player or not helperConfig or not helperConfig.autoChangeGold then
    stopGoldChangeLoop()
    return
  end

  safeDoThing(false)
  local stackCount = helper_changeGold()
  safeDoThing(true)

  -- Continue loop only if we still have 5+ stacks
  if stackCount >= GOLD_CHANGE_STACK_THRESHOLD then
    goldChangeLoopEvent = scheduleEvent(goldChangeLoop, GOLD_CHANGE_FAST_DELAY)
  else
    goldChangeLoopEvent = nil
  end
end

-- Toggle gold change feature
function tools.toggleChangeGold(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.autoChangeGold = checked
  end
  -- Save configuration
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
end

-- Main auto change gold function
function tools.autoChangeGold()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local player = getPlayer()

  if not g_game.isOnline() or not player or not helperConfig or not helperConfig.autoChangeGold then
    return
  end

  -- Count stacks first to decide mode
  local goldId = 3031
  local platinumId = 3035
  local _, platCount = findAndCount100Stacks(platinumId)
  local _, goldCount = findAndCount100Stacks(goldId)
  local totalStacks = platCount + goldCount

  -- If 5+ stacks and no loop running, start fast loop
  if totalStacks >= GOLD_CHANGE_STACK_THRESHOLD and not goldChangeLoopEvent then
    goldChangeLoop()
  elseif totalStacks > 0 and not goldChangeLoopEvent then
    -- Normal single use
    safeDoThing(false)
    helper_changeGold()
    safeDoThing(true)
  end
end

-- Called when resources balance changes (reactive gold change)
function tools.onResourcesBalanceChange(value, oldValue, resourceType)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()

  -- React only to gold equipped changes (coins in inventory/containers)
  if resourceType ~= ResourceTypes.GOLD_EQUIPPED or not helperConfig or not helperConfig.autoChangeGold then
    return
  end

  -- If fast loop is already running, let it handle everything
  if goldChangeLoopEvent then
    return
  end

  -- Only execute if crossed a multiple of 100 (e.g.: 99->100, 199->200)
  local oldHundreds = math.floor(oldValue / 100)
  local newHundreds = math.floor(value / 100)
  if newHundreds > oldHundreds then
    -- Debounce: cancel previous event if exists
    if pendingGoldChangeEvent then
      removeEvent(pendingGoldChangeEvent)
    end
    pendingGoldChangeEvent = scheduleEvent(function()
      pendingGoldChangeEvent = nil
      tools.autoChangeGold()
    end, GOLD_CHANGE_NORMAL_DELAY)
  end
end

-- ============================================================
-- EXERCISE TRAINING FUNCTIONS
-- ============================================================
-- Now delegated to _Helper.ExerciseTraining class for state-driven logic
-- The class handles: PZ detection, idle tracking, automatic exercise selection,
-- and position-based retry logic.

-- Toggle exercise training (called from UI checkbox)
function tools.toggleExerciseTraining(checked)
  if _Helper.ExerciseTraining and _Helper.ExerciseTraining.toggle then
    _Helper.ExerciseTraining.toggle(checked)
  end
end

-- Check exercise event (legacy function for backwards compatibility)
-- Now delegates to the new state-driven class
function tools.checkExerciseEvent()
  -- The new class uses its own cycle event, but we keep this for eventTable compatibility
  if _Helper.ExerciseTraining and _Helper.ExerciseTraining.check then
    _Helper.ExerciseTraining.check()
  end
end

-- Get nearest exercise dummy in sight (kept for potential external use)
function tools.getExerciseDummy()
  local currentPlayer = getPlayer()
  if not currentPlayer then
    return nil
  end
  local playerPos = currentPlayer:getPosition()
  local itemList = {}
  for _, id in pairs(ExerciseDummies) do
    local items = g_map.findItemsById(id, 5)
    if items then
      for pos, ptr in pairs(items) do
        if pos.z == playerPos.z then
          itemList[#itemList + 1] = { position = pos, item = ptr }
        end
      end
    end
  end

  table.sort(itemList, function(a, b)
    return getDistanceBetween(playerPos, a.position) < getDistanceBetween(playerPos, b.position)
  end)

  for _, data in pairs(itemList) do
    if g_map.isSightClear(data.position, playerPos) then
      return data.item
    end
  end
  return nil
end

-- NOTE: Manual exercise item assignment functions removed.
-- Exercise items are now automatically selected from ExerciseIds in inventory.
-- The _Helper.ExerciseTraining class handles automatic selection.

-- ============================================================
-- QUIVER REFILL FUNCTIONS (Paladin Only)
-- ============================================================

-- Assign ammunition item to button
function tools.assignQuiverAmmo(button)
  local grabber = getMouseGrabber()
  local helperWindow = getHelperWindow()

  if g_mouse and g_mouse.updateGrabber then
    g_mouse.updateGrabber(grabber, 'target')
  end
  grabber:grabMouse()
  if helperWindow then helperWindow:hide() end
  g_mouse.pushCursor('target')
  grabber.onMouseRelease = function(self, mousePosition, mouseButton)
    tools.onAssignQuiverAmmo(self, mousePosition, mouseButton, button)
  end
end

-- Handle ammunition item assignment
function tools.onAssignQuiverAmmo(self, mousePosition, mouseButton, button)
  local grabber = getMouseGrabber()
  local helperWindow = getHelperWindow()

  if g_mouse and g_mouse.updateGrabber then
    g_mouse.updateGrabber(grabber, 'target')
  end
  grabber:ungrabMouse()
  g_mouse.popCursor('target')
  grabber.onMouseRelease = nil
  if helperWindow then helperWindow:show() end

  local rootWidget = g_ui.getRootWidget()
  if not rootWidget then
    return true
  end

  local clickedWidget = rootWidget:recursiveGetChildByPos(mousePosition, false)
  if not clickedWidget then
    return true
  end

  local ammoId = 0
  if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
    local item = clickedWidget:getItem()
    if item then
      if item:isAmmo() then
        ammoId = item:getId()
      end
    end
  end

  if ammoId > 0 then
    button:setImageSource('/images/ui/item')
    if not button:getChildById('ammoItem') then
      local itemWidget = g_ui.createWidget('PotionItem', button)
      if itemWidget then
        itemWidget:setId('ammoItem')
      end
    end
    local itemWidget = button:getChildById('ammoItem')
    if itemWidget then
      itemWidget:setItemId(ammoId)
    end
    -- Save to config
    local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
    if helperConfig then
      helperConfig.quiverRefill = helperConfig.quiverRefill or {}
      helperConfig.quiverRefill.itemId = ammoId
      if _Helper.saveSettings then
        _Helper.saveSettings()
      end
    end
  else
    modules.game_textmessage.displayFailureMessage(tr('Invalid ammunition item! Select an arrow, bolt or throwing item.'))
  end
end

-- Toggle quiver refill
function tools.toggleQuiverRefill(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.quiverRefill = helperConfig.quiverRefill or {}
    helperConfig.quiverRefill.enabled = checked
  end
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
end

-- Shared commit logic for the quiver inputs. Reads the current widget text,
-- applies the clamp rule against the companion field, writes back to widget
-- + config, and triggers save. Called when the input loses focus (and when
-- the helper window is hidden via tools.commitQuiverInputs).
local function commitQuiverInput(widget, clampFn, otherValueGetter, configFieldName, isUpdatingRef)
  if not widget then return end
  local value = tonumber(widget:getText())
  if not value or value <= 0 then return end

  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig then return end
  helperConfig.quiverRefill = helperConfig.quiverRefill or {}

  local clamped = clampFn(value, otherValueGetter(helperConfig))
  helperConfig.quiverRefill[configFieldName] = clamped
  if clamped ~= value then
    isUpdatingRef.value = true
    widget:setText(tostring(clamped))
    isUpdatingRef.value = false
  end
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
end

-- References kept so we can commit on helper close, not just on focus loss.
local quiverMinInputWidget = nil
local quiverRefillInputWidget = nil
local quiverMinIsUpdating = { value = false }
local quiverRefillIsUpdating = { value = false }

local function getRefillFromConfig(cfg) return cfg.quiverRefill.refillValue end
local function getMinFromConfig(cfg)    return cfg.quiverRefill.minValue end

-- Setup numeric input for quiver MIN value.
-- Digit filtering is immediate; clamp + save happen on focus loss.
function tools.setupQuiverMinInput()
  local panel = getPaladinPanel()
  if not panel then return end

  local input = panel:recursiveGetChildById('quiverMinValue')
  if not input then return end
  quiverMinInputWidget = input

  input.onTextChange = function(widget, text)
    if quiverMinIsUpdating.value then return end
    -- Filter non-digits immediately — UX blocks invalid chars without
    -- touching the config/clamp. The clamp only happens on focus loss.
    local numericText = text:gsub("[^%d]", "")
    if numericText ~= text then
      quiverMinIsUpdating.value = true
      widget:setText(numericText)
      quiverMinIsUpdating.value = false
    end
  end

  input.onFocusChange = function(widget, focused)
    if not focused then
      commitQuiverInput(widget, tools.clampQuiverMin, getRefillFromConfig, 'minValue', quiverMinIsUpdating)
    end
  end
end

-- Setup numeric input for quiver REFILL (max) value. Same pattern as min.
function tools.setupQuiverRefillInput()
  local panel = getPaladinPanel()
  if not panel then return end

  local input = panel:recursiveGetChildById('quiverRefillValue')
  if not input then return end
  quiverRefillInputWidget = input

  input.onTextChange = function(widget, text)
    if quiverRefillIsUpdating.value then return end
    local numericText = text:gsub("[^%d]", "")
    if numericText ~= text then
      quiverRefillIsUpdating.value = true
      widget:setText(numericText)
      quiverRefillIsUpdating.value = false
    end
  end

  input.onFocusChange = function(widget, focused)
    if not focused then
      commitQuiverInput(widget, tools.clampQuiverRefill, getMinFromConfig, 'refillValue', quiverRefillIsUpdating)
    end
  end
end

-- Commit both quiver inputs unconditionally. Call this when the helper window
-- closes so any pending edit gets saved even if focus wasn't lost first.
function tools.commitQuiverInputs()
  if quiverMinInputWidget then
    commitQuiverInput(quiverMinInputWidget, tools.clampQuiverMin, getRefillFromConfig, 'minValue', quiverMinIsUpdating)
  end
  if quiverRefillInputWidget then
    commitQuiverInput(quiverRefillInputWidget, tools.clampQuiverRefill, getMinFromConfig, 'refillValue', quiverRefillIsUpdating)
  end
end

-- Pure predicates for quiver refill state-machine transitions.
-- Extracted so the rules are testable without mocking the full orchestrator.
local QUIVER_REFILL_COOLDOWN_MS = 500

-- ============================================================
-- INVARIANT: refillValue MUST be strictly greater than minValue.
-- Otherwise the state machine starts (count < min) but never stops
-- (count >= refillValue is impossible while count == min - 1).
--
-- The two clamp functions below enforce this on the field the user is
-- editing — the OTHER field stays put, the edited one snaps to the
-- nearest valid value. Use sanitizeRefillRange at read-time as a
-- belt-and-suspenders defense against legacy configs.
-- ============================================================

-- Clamp a newly-typed minValue against the current refillValue.
-- Snaps to currentRefillValue - 1 if the user typed something >= refill.
function tools.clampQuiverMin(newMin, currentRefillValue)
  if not newMin or newMin < 1 then return 1 end
  if currentRefillValue and newMin >= currentRefillValue then
    return math.max(1, currentRefillValue - 1)
  end
  return newMin
end

-- Clamp a newly-typed refillValue against the current minValue.
-- Snaps to currentMin + 1 if the user typed something <= min.
function tools.clampQuiverRefill(newRefill, currentMin)
  if not newRefill or newRefill < 1 then return 1 end
  if currentMin and newRefill <= currentMin then
    return currentMin + 1
  end
  return newRefill
end

-- Defensive read-time sanitizer. If a stored config violates the invariant
-- (legacy data), bump refillValue to minValue + 1 so the machine works.
function tools.sanitizeRefillRange(minValue, refillValue)
  minValue    = (minValue    and minValue    > 0) and minValue    or 50
  refillValue = (refillValue and refillValue > 0) and refillValue or 100
  if refillValue <= minValue then
    refillValue = minValue + 1
  end
  return minValue, refillValue
end

function tools.shouldStartRefill(quiverCount, minValue, isRefilling)
  return quiverCount < minValue and not isRefilling
end

function tools.shouldStopRefill(quiverCount, refillValue, isRefilling)
  return isRefilling and quiverCount >= refillValue
end

-- Returns (canEquip, reason). Reasons: 'ok', 'no-ammo', 'all-inside', 'cooldown'.
-- 'no-ammo' and 'all-inside' are terminal — caller should clear isRefilling.
-- 'cooldown' is transient — caller should just skip this tick.
function tools.canEquipNow(availableAmmo, quiverCount, now, lastAttempt, cooldown)
  cooldown = cooldown or QUIVER_REFILL_COOLDOWN_MS
  if availableAmmo == 0 then return false, 'no-ammo' end
  if availableAmmo <= quiverCount then return false, 'all-inside' end
  if (now - lastAttempt) < cooldown then return false, 'cooldown' end
  return true, 'ok'
end

-- Quiver Refill is hidden from the Tools tab. Keep its background automation
-- disabled with the panel so a stale saved checkbox cannot run invisibly.
local SHOW_QUIVER_REFILL_PANEL = false

-- Check and refill quiver
function tools.checkQuiverRefill()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()

  if not SHOW_QUIVER_REFILL_PANEL or not helperConfig or not helperConfig.quiverRefill or
      not helperConfig.quiverRefill.enabled then
    isRefillingQuiver = false
    return
  end

  local player = getPlayer()
  if not player then return end

  local itemId = helperConfig.quiverRefill.itemId or 0
  if itemId == 0 then return end

  local minValue, refillValue = tools.sanitizeRefillRange(
    helperConfig.quiverRefill.minValue,
    helperConfig.quiverRefill.refillValue
  )

  -- Get quiver item count from right slot (InventorySlotRight = 5)
  local rightItem = player:getInventoryItem(InventorySlotRight)
  if not rightItem then
    isRefillingQuiver = false
    return
  end

  -- Use getSubType for stackable items count or getContainerItemCount for containers
  local quiverCount = 0
  if rightItem:isContainer() then
    quiverCount = rightItem:getContainerItemCount()
  else
    quiverCount = rightItem:getCount()
  end

  -- Get available ammo count in inventory (excluding quiver)
  local availableAmmo = player:getInventoryCount(itemId, 0)

  -- State transitions via pure predicates.
  if tools.shouldStartRefill(quiverCount, minValue, isRefillingQuiver) then
    isRefillingQuiver = true
  end

  if tools.shouldStopRefill(quiverCount, refillValue, isRefillingQuiver) then
    isRefillingQuiver = false
    return
  end

  if isRefillingQuiver then
    local now = g_clock.millis()
    local canEquip, reason = tools.canEquipNow(availableAmmo, quiverCount, now, lastQuiverRefillTime)

    if not canEquip then
      if reason == 'no-ammo' or reason == 'all-inside' then
        isRefillingQuiver = false
      end
      return
    end

    lastQuiverRefillTime = now
    safeDoThing(false)
    g_game.equipItemId(itemId, 0)
    safeDoThing(true)
  end
end

-- ============================================================
-- MAGIC SHIELD FUNCTIONS (Sorcerer/Druid Only)
-- ============================================================

-- Toggle utamo vita auto-cast
function tools.toggleUtamoVita(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.magicShield = helperConfig.magicShield or {}
    helperConfig.magicShield.utamoEnabled = checked
  end
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
end

-- Toggle exana vita auto-cast
function tools.toggleExanaVita(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.magicShield = helperConfig.magicShield or {}
    helperConfig.magicShield.exanaEnabled = checked
  end
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
end

-- Setup numeric input validation for utamo HP percent (0-100)
function tools.setupUtamoHpInput()
  local panel = getMagePanel()
  if not panel then return end

  local input = panel:recursiveGetChildById('utamoHpPercent')
  if input then
    local isUpdating = false
    input.onTextChange = function(widget, text)
      if isUpdating then return end
      isUpdating = true

      -- Allow only digits and clamp to max 100
      local numericText = text:gsub("[^%d]", "")
      local value = tonumber(numericText) or 0
      if value > 100 then
        numericText = "100"
      end
      if numericText ~= text then
        widget:setText(numericText)
      end

      -- Save value if valid
      if value > 0 and value <= 100 then
        local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
        if helperConfig then
          helperConfig.magicShield = helperConfig.magicShield or {}
          helperConfig.magicShield.utamoHpPercent = value
          if _Helper.saveSettings then
            _Helper.saveSettings()
          end
        end
      end

      isUpdating = false
    end
  end
end

-- Setup numeric input validation for exana HP percent (0-100)
function tools.setupExanaHpInput()
  local panel = getMagePanel()
  if not panel then return end

  local input = panel:recursiveGetChildById('exanaHpPercent')
  if input then
    local isUpdating = false
    input.onTextChange = function(widget, text)
      if isUpdating then return end
      isUpdating = true

      -- Allow only digits and clamp to max 100
      local numericText = text:gsub("[^%d]", "")
      local value = tonumber(numericText) or 0
      if value > 100 then
        numericText = "100"
      end
      if numericText ~= text then
        widget:setText(numericText)
      end

      -- Save value if valid
      if value > 0 and value <= 100 then
        local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
        if helperConfig then
          helperConfig.magicShield = helperConfig.magicShield or {}
          helperConfig.magicShield.exanaHpPercent = value
          if _Helper.saveSettings then
            _Helper.saveSettings()
          end
        end
      end

      isUpdating = false
    end
  end
end

-- Check and manage magic shield
-- Support group ID is 3
local SUPPORT_GROUP_ID = 3

function tools.checkMagicShield()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.magicShield then
    return
  end

  local player = getPlayer()
  if not player then return end

  local health = player:getHealth()
  local maxHealth = player:getMaxHealth()
  if maxHealth == 0 then return end

  local healthPercent = math.floor((health / maxHealth) * 100)
  local hasMShield = hasMagicShield()

  local utamoEnabled = helperConfig.magicShield.utamoEnabled
  local exanaEnabled = helperConfig.magicShield.exanaEnabled
  local utamoHpPercent = helperConfig.magicShield.utamoHpPercent or 80
  local exanaHpPercent = helperConfig.magicShield.exanaHpPercent or 90

  -- Check if we should cast exana vita (cancel magic shield)
  -- HP is ABOVE threshold AND has magic shield active
  if exanaEnabled and healthPercent > exanaHpPercent and hasMShield then
    if not isGroupOnCooldown(SUPPORT_GROUP_ID) then
      safeDoThing(false)
      g_game.talk("exana vita")
      safeDoThing(true)
      return
    end
  end

  -- Check if we should cast utamo vita (enable magic shield)
  -- HP is AT OR BELOW threshold AND does NOT have magic shield active.
  -- The inclusive boundary is important for 100%: otherwise that setting cannot
  -- cast until the player has already lost health.
  if utamoEnabled and healthPercent <= utamoHpPercent and not hasMShield then
    if not isGroupOnCooldown(SUPPORT_GROUP_ID) then
      safeDoThing(false)
      g_game.talk("utamo vita")
      safeDoThing(true)
      return
    end
  end
end

-- Returns true if Magic Shield wants to consume a support-group cast right now.
-- Used by Auto Haste to yield priority — the potion fallback path is ignored
-- because it does not conflict with the haste spell's support cooldown.
function tools.isMagicShieldPending()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.magicShield then return false end

  local player = getPlayer()
  if not player then return false end

  local maxHealth = player:getMaxHealth()
  if maxHealth == 0 then return false end

  local healthPercent = math.floor((player:getHealth() / maxHealth) * 100)
  local hasMShield = hasMagicShield()
  local cfg = helperConfig.magicShield

  if cfg.exanaEnabled and healthPercent > (cfg.exanaHpPercent or 90) and hasMShield then
    return true
  end

  if cfg.utamoEnabled and healthPercent <= (cfg.utamoHpPercent or 80) and not hasMShield then
    return true
  end

  return false
end

-- ============================================================
-- VOCATION PANEL VISIBILITY
-- ============================================================

-- Pure predicates for vocation-gated panel visibility. Testable in isolation.
function tools.shouldShowPaladinPanel(vocationId)
  return SHOW_QUIVER_REFILL_PANEL and vocationId == 2
end

function tools.shouldShowMagePanel(vocationId)
  return vocationId == 3 or vocationId == 4
end

-- Update panel visibility based on vocation
function tools.updateVocationPanels()
  local vocationId = getPlayerVocationId()
  local palPanel = getPaladinPanel()
  local magPanel = getMagePanel()

  if palPanel then
    palPanel:setVisible(tools.shouldShowPaladinPanel(vocationId))
  end

  if magPanel then
    magPanel:setVisible(tools.shouldShowMagePanel(vocationId))
  end
end

-- ============================================================
-- UI LOADING & RESET
-- ============================================================

-- Load gold change checkbox state
function tools.loadChangeGoldToUI()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local panel = getToolsPanel()
  if not helperConfig or not panel then return end

  local changeGold = panel:recursiveGetChildById("changeGold")
  if changeGold then
    changeGold:setChecked(helperConfig.autoChangeGold or false)
  end
end

local function getToolsContainer()
  if helper and helper.contentPanel then
    return helper.contentPanel:getChildById('toolsPanelContainer') or
        helper.contentPanel:recursiveGetChildById('toolsPanelContainer')
  end
  local rootWidget = g_ui.getRootWidget()
  return rootWidget and rootWidget:recursiveGetChildById('toolsPanelContainer') or nil
end

function tools.updateAutoPartySettings()
  if applyingAutomationConfig then return end
  local config = getAutomationConfig()
  local panel = getToolsPanel()
  if not config or not panel then return end
  for i = 1, 4 do
    local edit = panel:recursiveGetChildById('autoPartyPlayer' .. i)
    config.autoParty.sendList[i] = edit and trimText(edit:getText()) or ''
  end
  local leader = panel:recursiveGetChildById('autoPartyLeader')
  config.autoParty.acceptLeader = leader and trimText(leader:getText()) or ''
  if _Helper.saveSettings then _Helper.saveSettings() end
end

function tools.toggleAutoPartyInvite(checked)
  local config = getAutomationConfig()
  if config then
    config.autoParty.enabled = checked == true
    if _Helper.saveSettings then _Helper.saveSettings() end
  end
end

function tools.toggleAutoPartyAccept(checked)
  local config = getAutomationConfig()
  if config then
    config.autoParty.acceptEnabled = checked == true
    if _Helper.saveSettings then _Helper.saveSettings() end
  end
end

function tools.toggleAntiIdle(checked)
  local config = getAutomationConfig()
  if config then
    config.antiIdle = checked == true
    lastActivityAt = g_clock.millis()
    if _Helper.saveSettings then _Helper.saveSettings() end
  end
end

function tools.toggleShowLookItemId(checked)
  local config = getAutomationConfig()
  if config then
    config.showLookItemId = checked == true
    if _Helper.saveSettings then _Helper.saveSettings() end
  end
end

function tools.toggleAutoQuillSell(checked)
  local config = getAutomationConfig()
  if not config then return end
  config.autoQuillSell = checked == true
  local panel = getToolsPanel()
  if panel then
    local belowCap = panel:recursiveGetChildById('autoQuillSellBelowCap')
    local capacity = panel:recursiveGetChildById('autoQuillSellCapacity')
    if belowCap then belowCap:setEnabled(config.autoQuillSell) end
    if capacity then capacity:setEnabled(config.autoQuillSell) end
  end
  lastQuillStateQueryAt = 0
  lastQuillSaleAttemptAt = 0
  lastQuillCapacityCheckAt = 0
  quillCapacityAllowsSale = false
  if config.autoQuillSell and capacityAllowsAutomaticQuillSale(config, g_clock.millis()) and
      modules.game_inventory and modules.game_inventory.querySummonQuillState then
    modules.game_inventory.querySummonQuillState()
  end
  if _Helper.saveSettings then _Helper.saveSettings() end
end

function tools.toggleAutoQuillSellBelowCap(checked)
  if applyingAutomationConfig then return end
  local config = getAutomationConfig()
  if not config then return end
  config.autoQuillSellBelowCap = checked == true
  lastQuillStateQueryAt = 0
  lastQuillSaleAttemptAt = 0
  lastQuillCapacityCheckAt = 0
  quillCapacityAllowsSale = false
  if _Helper.saveSettings then _Helper.saveSettings() end
end

function tools.updateAutoQuillSellCapacity(widget, text)
  if applyingAutomationConfig then return end
  local numericText = tostring(text or ''):gsub('[^%d]', '')
  if widget and numericText ~= text then
    widget:setText(numericText)
    return
  end
  local value = tonumber(numericText)
  if not value then return end
  local config = getAutomationConfig()
  if not config then return end
  config.autoQuillSellCapacity = math.max(0, value)
  lastQuillStateQueryAt = 0
  lastQuillSaleAttemptAt = 0
  lastQuillCapacityCheckAt = 0
  quillCapacityAllowsSale = false
  if _Helper.saveSettings then _Helper.saveSettings() end
end

function tools.updateBotHudSettings()
  if applyingAutomationConfig then return end
  local config = getAutomationConfig()
  local panel = getToolsContainer()
  if not config or not panel then return end
  local hud = config.botHud
  local function checked(id)
    local widget = panel:recursiveGetChildById(id)
    return widget and widget:isChecked() or false
  end
  hud.enabled = checked('enableBotHud')
  hud.showCavebot = checked('hudShowCavebot')
  hud.showTargeting = checked('hudShowTargeting')
  hud.showEquipment = checked('hudShowEquipment')
  hud.showTimers = checked('hudShowTimers')
  hud.showHaste = checked('hudShowHaste')
  hud.showPlayer = checked('hudShowPlayer')
  hud.showAutomation = checked('hudShowAutomation')
  hud.showWaypoints = checked('hudShowWaypoints')
  local size = panel:recursiveGetChildById('botHudSize')
  hud.size = size and size:getCurrentOption().text or 'Normal'
  local cavebot = modules.game_helper and modules.game_helper.cavebot
  if cavebot and cavebot.applyBotHudConfig then cavebot.applyBotHudConfig(hud) end
  if _Helper.saveSettings then _Helper.saveSettings() end
end

function tools.loadBotHudToUI()
  local config = getAutomationConfig()
  local panel = getToolsContainer()
  if not config or not panel then return end
  local hud = config.botHud
  applyingAutomationConfig = true
  local values = {
    enableBotHud = hud.enabled,
    hudShowCavebot = hud.showCavebot,
    hudShowTargeting = hud.showTargeting,
    hudShowEquipment = hud.showEquipment,
    hudShowTimers = hud.showTimers,
    hudShowHaste = hud.showHaste,
    hudShowPlayer = hud.showPlayer,
    hudShowAutomation = hud.showAutomation,
    hudShowWaypoints = hud.showWaypoints
  }
  for id, value in pairs(values) do
    local widget = panel:recursiveGetChildById(id)
    if widget then widget:setChecked(value == true) end
  end
  local size = panel:recursiveGetChildById('botHudSize')
  if size then size:setCurrentOption(hud.size or 'Normal') end
  applyingAutomationConfig = false
  local cavebot = modules.game_helper and modules.game_helper.cavebot
  if cavebot and cavebot.applyBotHudConfig then cavebot.applyBotHudConfig(hud) end
end

function tools.loadAutomationToUI()
  local config = getAutomationConfig()
  local panel = getToolsPanel()
  if not config or not panel then return end
  applyingAutomationConfig = true
  local invite = panel:recursiveGetChildById('autoPartyInvite')
  local accept = panel:recursiveGetChildById('autoPartyAccept')
  local antiIdle = panel:recursiveGetChildById('antiIdle')
  local showLookItemId = panel:recursiveGetChildById('showLookItemId')
  local autoQuillSell = panel:recursiveGetChildById('autoQuillSell')
  local autoQuillSellBelowCap = panel:recursiveGetChildById('autoQuillSellBelowCap')
  local autoQuillSellCapacity = panel:recursiveGetChildById('autoQuillSellCapacity')
  if invite then invite:setChecked(config.autoParty.enabled == true) end
  if accept then accept:setChecked(config.autoParty.acceptEnabled == true) end
  if antiIdle then antiIdle:setChecked(config.antiIdle == true) end
  if showLookItemId then showLookItemId:setChecked(config.showLookItemId == true) end
  if autoQuillSell then autoQuillSell:setChecked(config.autoQuillSell == true) end
  if autoQuillSellBelowCap then autoQuillSellBelowCap:setChecked(config.autoQuillSellBelowCap == true) end
  if autoQuillSellCapacity then autoQuillSellCapacity:setText(tostring(config.autoQuillSellCapacity)) end
  if autoQuillSellBelowCap then autoQuillSellBelowCap:setEnabled(config.autoQuillSell == true) end
  if autoQuillSellCapacity then autoQuillSellCapacity:setEnabled(config.autoQuillSell == true) end
  for i = 1, 4 do
    local edit = panel:recursiveGetChildById('autoPartyPlayer' .. i)
    if edit then edit:setText(config.autoParty.sendList[i] or '') end
  end
  local leader = panel:recursiveGetChildById('autoPartyLeader')
  if leader then leader:setText(config.autoParty.acceptLeader or '') end
  applyingAutomationConfig = false
  tools.loadBotHudToUI()
end

-- Load exercise training UI state
function tools.loadExerciseTrainingToUI()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local panel = getToolsPanel()
  if not helperConfig or not panel then return end

  local config = helperConfig.exerciseTraining or {}

  -- Load enabled state checkbox
  local checkBox = panel:recursiveGetChildById("autoTrainingCheck")
  if checkBox then
    checkBox:setChecked(config.enabled or false)
  end

  -- Also delegate to the class for any additional UI loading
  if _Helper.ExerciseTraining and _Helper.ExerciseTraining.loadToUI then
    _Helper.ExerciseTraining.loadToUI()
  end
end

-- Load quiver refill UI state
function tools.loadQuiverRefillToUI()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local panel = getPaladinPanel()
  if not helperConfig or not panel then return end

  -- Reset quiver refill state variables on load (important for relog)
  isRefillingQuiver = false
  lastQuiverRefillTime = 0

  local config = helperConfig.quiverRefill or {}

  -- Load item
  if config.itemId and config.itemId > 0 then
    local button = panel:recursiveGetChildById("quiverAmmoItem")
    if button then
      button:setImageSource('/images/ui/item')
      if not button:getChildById('ammoItem') then
        local itemWidget = g_ui.createWidget('PotionItem', button)
        if itemWidget then
          itemWidget:setId('ammoItem')
        end
      end
      local itemWidget = button:getChildById('ammoItem')
      if itemWidget then
        itemWidget:setItemId(config.itemId)
      end
    end
  end

  -- Load values
  local minEdit = panel:recursiveGetChildById("quiverMinValue")
  if minEdit then
    minEdit:setText(tostring(config.minValue or 50))
  end

  local refillEdit = panel:recursiveGetChildById("quiverRefillValue")
  if refillEdit then
    refillEdit:setText(tostring(config.refillValue or 100))
  end

  -- Load enabled state
  local enableCheck = panel:recursiveGetChildById("enableQuiverRefill")
  if enableCheck then
    enableCheck:setChecked(config.enabled or false)
  end

  -- Setup numeric input validation
  tools.setupQuiverMinInput()
  tools.setupQuiverRefillInput()
end

-- Load magic shield UI state
function tools.loadMagicShieldToUI()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local panel = getMagePanel()
  if not helperConfig or not panel then return end

  local config = helperConfig.magicShield or {}

  -- Load utamo vita settings
  local utamoCheck = panel:recursiveGetChildById("enableUtamoVita")
  if utamoCheck then
    utamoCheck:setChecked(config.utamoEnabled or false)
  end

  local utamoHp = panel:recursiveGetChildById("utamoHpPercent")
  if utamoHp then
    utamoHp:setText(tostring(config.utamoHpPercent or 80))
  end

  -- Load exana vita settings
  local exanaCheck = panel:recursiveGetChildById("enableExanaVita")
  if exanaCheck then
    exanaCheck:setChecked(config.exanaEnabled or false)
  end

  local exanaHp = panel:recursiveGetChildById("exanaHpPercent")
  if exanaHp then
    exanaHp:setText(tostring(config.exanaHpPercent or 90))
  end

  -- Setup numeric input validation
  tools.setupUtamoHpInput()
  tools.setupExanaHpInput()
end

-- Reset all tools UI elements
function tools.resetUI()
  local panel = getToolsPanel()
  if not panel then return end

  -- Reset gold change
  local changeGold = panel:recursiveGetChildById("changeGold")
  if changeGold then
    changeGold:setChecked(false)
  end

  -- Reset exercise training
  local autoTrainingCheck = panel:recursiveGetChildById("autoTrainingCheck")
  if autoTrainingCheck then
    autoTrainingCheck:setChecked(false)
  end

  local autoQuillSell = panel:recursiveGetChildById("autoQuillSell")
  if autoQuillSell then
    autoQuillSell:setChecked(false)
  end
  local autoQuillSellBelowCap = panel:recursiveGetChildById('autoQuillSellBelowCap')
  if autoQuillSellBelowCap then autoQuillSellBelowCap:setChecked(false) end

  -- Stop exercise training cycle if running
  if _Helper.ExerciseTraining and _Helper.ExerciseTraining.toggle then
    _Helper.ExerciseTraining.toggle(false)
  end

  -- Reset paladin panel
  local palPanel = getPaladinPanel()
  if palPanel then
    local enableQuiver = palPanel:recursiveGetChildById("enableQuiverRefill")
    if enableQuiver then
      enableQuiver:setChecked(false)
    end
    local ammoButton = palPanel:recursiveGetChildById("quiverAmmoItem")
    if ammoButton then
      ammoButton:setImageSource('/images/game/actionbar/actionbarslot')
      local ammoItem = ammoButton:getChildById('ammoItem')
      if ammoItem then
        ammoItem:destroy()
      end
    end
  end

  -- Reset mage panel
  local magPanel = getMagePanel()
  if magPanel then
    local utamoCheck = magPanel:recursiveGetChildById("enableUtamoVita")
    if utamoCheck then utamoCheck:setChecked(false) end
    local exanaCheck = magPanel:recursiveGetChildById("enableExanaVita")
    if exanaCheck then exanaCheck:setChecked(false) end
  end

  -- Reset refilling state
  isRefillingQuiver = false
  lastQuiverRefillTime = 0
end

-- Load all tools states to UI
function tools.loadToUI()
  tools.loadChangeGoldToUI()
  tools.loadAutomationToUI()
  tools.loadExerciseTrainingToUI()
  tools.loadQuiverRefillToUI()
  tools.loadMagicShieldToUI()
  tools.updateVocationPanels()

  -- AutoFood and AutoHaste are handled by their own modules
  if _Helper.AutoFood and _Helper.AutoFood.loadToUI then
    _Helper.AutoFood.loadToUI()
  end
  if _Helper.AutoHaste and _Helper.AutoHaste.loadToUI then
    _Helper.AutoHaste.loadToUI()
  end
  if _Helper.ManaTraining and _Helper.ManaTraining.loadToUI then
    _Helper.ManaTraining.loadToUI()
  end
end

-- ============================================================
-- GETTERS
-- ============================================================

-- Getter for exercise dummies
function tools.getExerciseDummies()
  return ExerciseDummies
end

-- Getter for exercise items
function tools.getExercises()
  return ExerciseIds
end

-- Getter for toolsPanel
function tools.getPanel()
  return getToolsPanel()
end

-- Getter for paladinPanel
function tools.getPaladinPanel()
  return getPaladinPanel()
end

-- Getter for magePanel
function tools.getMagePanel()
  return getMagePanel()
end

-- ============================================================
-- INITIALIZATION & TERMINATION
-- ============================================================

function tools.init(helperWindow)
  helper = helperWindow
  if helper and helper.contentPanel then
    local container = helper.contentPanel:getChildById('toolsPanelContainer')
    if container then
      toolsPanel = helper
      paladinPanel = container:recursiveGetChildById('paladinPanel')
      magePanel = container:recursiveGetChildById('magePanel')
    end
  end
  startAutomationCycle()
end
function tools.terminate()
  stopAutomationCycle()
  lastQuillStateQueryAt = 0
  lastQuillSaleAttemptAt = 0
  lastQuillCapacityCheckAt = 0
  quillCapacityAllowsSale = false
  toolsPanel = nil
  paladinPanel = nil
  magePanel = nil
  helper = nil
  isRefillingQuiver = false
  lastQuiverRefillTime = 0
  if pendingGoldChangeEvent then
    removeEvent(pendingGoldChangeEvent)
    pendingGoldChangeEvent = nil
  end
  if goldChangeLoopEvent then
    removeEvent(goldChangeLoopEvent)
    goldChangeLoopEvent = nil
  end
  if mouseGrabberWidget then
    mouseGrabberWidget:destroy()
    mouseGrabberWidget = nil
  end
end

-- Expose pure helpers for tests (and any external caller that needs them).
tools.getDistanceBetween   = getDistanceBetween
tools.getPlayerVocationId  = getPlayerVocationId
tools.hasMagicShield       = hasMagicShield

return tools
