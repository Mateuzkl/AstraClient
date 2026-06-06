-- ===== HELPER EXERCISE TRAINING =====
-- State-driven exercise training module
-- Automatically selects exercises, respects PZ rules, and uses position-based retry logic

-- Ensure _Helper exists
if not _Helper then
  _Helper = {}
end

_Helper.ExerciseTraining = {}

-- ===== STATE CONSTANTS =====
local State = {
  DISABLED = "disabled",         -- Feature is off
  WAITING_PZ = "waiting_pz",     -- Enabled but outside PZ
  WAITING_IDLE = "waiting_idle", -- In PZ, waiting for player to stop moving
  SEARCHING = "searching",       -- Idle complete, searching for dummy
  TRAINING = "training",         -- Actively training on a dummy
  NO_DUMMY = "no_dummy",         -- No dummy found, waiting for position change
}

-- ===== LOCAL STATE VARIABLES =====
local currentState = State.DISABLED
local lastPosition = nil        -- Last recorded position {x, y, z}
local idleStartTime = nil       -- Timestamp when player stopped moving
local lastSearchPosition = nil  -- Position where last dummy search was performed
local checkCycleEvent = nil     -- Cycle event for periodic checks

-- ===== CONFIGURATION =====
local IDLE_REQUIRED_MS = 2000   -- 2 seconds of idle required
local CHECK_INTERVAL_MS = 10000 -- Check interval while waiting/training

-- Exercise weapon IDs (ordered by priority, first found in inventory is used)
-- Customize these IDs to match your server's exercise weapons
ExerciseIds = ExerciseIds or {
    32384, -- Exercise Sword
    32385, -- Exercise Axe
    32386, -- Exercise Club
    32387, -- Exercise Bow
    32388, -- Exercise Rod
    32389, -- Exercise Wand
}

-- Exercise dummy object IDs (the training dummies placed in houses/guildhalls)
-- Customize these IDs to match your server's exercise dummies
ExerciseDummies = ExerciseDummies or {
    32142, -- Exercise Dummy
}

-- ===== UTILITY FUNCTIONS =====

local function getPlayer()
  return g_game.getLocalPlayer()
end

local function positionsEqual(pos1, pos2)
  if not pos1 or not pos2 then return false end
  return pos1.x == pos2.x and pos1.y == pos2.y and pos1.z == pos2.z
end

local function copyPosition(pos)
  if not pos then return nil end
  return { x = pos.x, y = pos.y, z = pos.z }
end

local function getDistanceBetween(p1, p2)
  return math.max(math.abs(p1.x - p2.x), math.abs(p1.y - p2.y))
end

-- Get first available exercise item from inventory
local function findAvailableExercise()
  local player = getPlayer()
  if not player then return nil end

  -- Iterate through ExerciseIds in order, return first available
  for _, itemId in ipairs(ExerciseIds) do
    local count = player:getInventoryCount(itemId, 0)
    if count > 0 then
      return itemId
    end
  end
  return nil
end

-- Find nearest exercise dummy in sight (same as tools_panel but local)
local function findExerciseDummy()
  local player = getPlayer()
  if not player then return nil end

  local playerPos = player:getPosition()
  local itemList = {}

  -- Search for all dummy types within range 5
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

  -- Sort by distance (closest first)
  table.sort(itemList, function(a, b)
    return getDistanceBetween(playerPos, a.position) < getDistanceBetween(playerPos, b.position)
  end)

  -- Return first with clear sight line
  for _, data in pairs(itemList) do
    if g_map.isSightClear(data.position, playerPos) then
      return data.item
    end
  end
  return nil
end

local function safeDoThing(flag)
  if _Helper and _Helper.safeDoThing then
    _Helper.safeDoThing(flag)
  elseif g_game and type(g_game.doThing) == "function" then
    g_game.doThing(flag)
  end
end

-- ===== STATE TRANSITION FUNCTIONS =====

local function setState(newState)
  if currentState ~= newState then
    currentState = newState
  end
end

local function resetIdleTracking()
  idleStartTime = nil
end

local function resetSearchState()
  lastSearchPosition = nil
end

-- ===== CORE LOGIC =====

-- Main check function called by cycle event
local function checkExerciseTraining()
  local player = getPlayer()
  if not player then
    setState(State.DISABLED)
    return
  end

  -- If disabled, do nothing
  if currentState == State.DISABLED then
    return
  end

  local currentPos = player:getPosition()
  local isInPz = player:isInProtectionZone()

  -- STATE: WAITING_PZ - Outside protection zone
  if currentState == State.WAITING_PZ then
    if isInPz then
      -- Entered PZ, start idle tracking
      setState(State.WAITING_IDLE)
      lastPosition = copyPosition(currentPos)
      idleStartTime = g_clock.millis()
      resetSearchState()
    end
    return
  end

  -- STATE: WAITING_IDLE - In PZ, waiting for player to be stationary
  if currentState == State.WAITING_IDLE then
    if not isInPz then
      -- Left PZ, go back to waiting
      setState(State.WAITING_PZ)
      resetIdleTracking()
      resetSearchState()
      return
    end

    -- Check if player moved
    if not positionsEqual(currentPos, lastPosition) then
      -- Player moved, reset idle timer
      lastPosition = copyPosition(currentPos)
      idleStartTime = g_clock.millis()
      resetSearchState()
      return
    end

    -- Check if idle time requirement is met
    local currentTime = g_clock.millis()
    if idleStartTime and (currentTime - idleStartTime) >= IDLE_REQUIRED_MS then
      -- Idle requirement met, proceed to search
      setState(State.SEARCHING)
    end
    return
  end

  -- STATE: SEARCHING - Looking for a dummy
  if currentState == State.SEARCHING then
    if not isInPz then
      -- Left PZ
      setState(State.WAITING_PZ)
      resetIdleTracking()
      resetSearchState()
      return
    end

    -- Check if player moved since last search
    if not positionsEqual(currentPos, lastPosition) then
      -- Player moved, reset to idle tracking
      setState(State.WAITING_IDLE)
      lastPosition = copyPosition(currentPos)
      idleStartTime = g_clock.millis()
      resetSearchState()
      return
    end

    -- Check if we already searched from this position
    if positionsEqual(currentPos, lastSearchPosition) then
      -- Already searched here and found nothing, wait for movement
      setState(State.NO_DUMMY)
      return
    end

    -- Find available exercise item
    local exerciseId = findAvailableExercise()
    if not exerciseId then
      -- No exercise items available
      modules.game_textmessage.displayGameMessage("No exercise items available.")
      setState(State.NO_DUMMY)
      lastSearchPosition = copyPosition(currentPos)
      return
    end

    -- Search for dummy
    local dummy = findExerciseDummy()
    if not dummy then
      -- No dummy found at this position
      setState(State.NO_DUMMY)
      lastSearchPosition = copyPosition(currentPos)
      return
    end

    -- Found dummy, start training
    safeDoThing(false)
    g_game.useInventoryItemWith(exerciseId, dummy)
    safeDoThing(true)

    setState(State.TRAINING)
    return
  end

  -- STATE: TRAINING - Currently training
  if currentState == State.TRAINING then
    if not isInPz then
      -- Left PZ, stop training
      setState(State.WAITING_PZ)
      resetIdleTracking()
      resetSearchState()
      return
    end

    -- Check if player moved
    if not positionsEqual(currentPos, lastPosition) then
      -- Player moved, go back to idle tracking
      setState(State.WAITING_IDLE)
      lastPosition = copyPosition(currentPos)
      idleStartTime = g_clock.millis()
      resetSearchState()
      return
    end

    -- Verify we still have exercise items
    local exerciseId = findAvailableExercise()
    if not exerciseId then
      -- No more exercise items
      setState(State.NO_DUMMY)
      return
    end

    -- Verify dummy still exists
    local dummy = findExerciseDummy()
    if not dummy then
      -- Dummy no longer available, search again
      setState(State.SEARCHING)
      return
    end

    -- Continue training - use the exercise on dummy
    safeDoThing(false)
    g_game.useInventoryItemWith(exerciseId, dummy)
    safeDoThing(true)
    return
  end

  -- STATE: NO_DUMMY - No dummy found, waiting for position change
  if currentState == State.NO_DUMMY then
    if not isInPz then
      -- Left PZ
      setState(State.WAITING_PZ)
      resetIdleTracking()
      resetSearchState()
      return
    end

    -- Check if player moved to a new position
    if not positionsEqual(currentPos, lastPosition) then
      -- Player moved, restart the process
      setState(State.WAITING_IDLE)
      lastPosition = copyPosition(currentPos)
      idleStartTime = g_clock.millis()
      resetSearchState()
      return
    end

    -- Still at same position, do nothing (no polling spam)
    return
  end
end

-- ===== CYCLE EVENT MANAGEMENT =====

_Helper.ExerciseTraining.stopCycle = function()
  if checkCycleEvent then
    removeEvent(checkCycleEvent)
    checkCycleEvent = nil
  end
end

_Helper.ExerciseTraining.startCycle = function()
  -- Already running
  if checkCycleEvent then return end

  checkCycleEvent = cycleEvent(checkExerciseTraining, CHECK_INTERVAL_MS)
end

-- ===== PUBLIC API =====

-- Toggle exercise training on/off
_Helper.ExerciseTraining.toggle = function(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.exerciseTraining = helperConfig.exerciseTraining or {}
    helperConfig.exerciseTraining.enabled = checked
  end

  -- Sync with shortcut panel if available
  if _Helper.Shortcut and _Helper.Shortcut.syncButton then
    _Helper.Shortcut.syncButton('shortcutExerciseTraining', checked)
  end

  if checked then
    -- Enable: determine initial state based on current conditions
    local player = getPlayer()
    if player then
      local currentPos = player:getPosition()
      lastPosition = copyPosition(currentPos)

      if player:isInProtectionZone() then
        setState(State.WAITING_IDLE)
        idleStartTime = g_clock.millis()
      else
        setState(State.WAITING_PZ)
      end
      resetSearchState()
      _Helper.ExerciseTraining.startCycle()
    else
      setState(State.DISABLED)
    end
  else
    -- Disable
    setState(State.DISABLED)
    _Helper.ExerciseTraining.stopCycle()
    resetIdleTracking()
    resetSearchState()
  end

  -- Save settings
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
end

-- Main check function (called by eventTable if needed for backwards compatibility)
_Helper.ExerciseTraining.check = function()
  -- The cycle event handles everything now
  -- This is here for potential integration with the old event system
  checkExerciseTraining()
end

-- Get current state (for debugging/UI)
_Helper.ExerciseTraining.getState = function()
  return currentState
end

-- Check if currently training
_Helper.ExerciseTraining.isTraining = function()
  return currentState == State.TRAINING
end

-- Called when player logs in
_Helper.ExerciseTraining.onLogin = function()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig and helperConfig.exerciseTraining and helperConfig.exerciseTraining.enabled then
    _Helper.ExerciseTraining.toggle(true)
  end
end

-- Called when player logs out
_Helper.ExerciseTraining.onLogout = function()
  _Helper.ExerciseTraining.stopCycle()
  setState(State.DISABLED)
  resetIdleTracking()
  resetSearchState()
end

-- Load UI state from config
_Helper.ExerciseTraining.loadToUI = function()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local toolsPanel = _Helper.getToolsPanel and _Helper.getToolsPanel()
  if not helperConfig or not toolsPanel then return end

  local config = helperConfig.exerciseTraining or {}

  -- Load enabled state to checkbox
  local checkBox = toolsPanel:recursiveGetChildById("autoTrainingCheck")
  if checkBox then
    checkBox:setChecked(config.enabled or false)
  end
end

-- Reset UI elements
_Helper.ExerciseTraining.resetUI = function()
  local toolsPanel = _Helper.getToolsPanel and _Helper.getToolsPanel()
  if not toolsPanel then return end

  local checkBox = toolsPanel:recursiveGetChildById("autoTrainingCheck")
  if checkBox then
    checkBox:setChecked(false)
  end
end

-- Collect current states for save/restore
_Helper.ExerciseTraining.collectStates = function()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.exerciseTraining then
    return { enabled = false }
  end

  return {
    enabled = helperConfig.exerciseTraining.enabled or false
  }
end

-- Restore states
_Helper.ExerciseTraining.saveAndRestoreStates = function(savedStates)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig then return end

  helperConfig.exerciseTraining = helperConfig.exerciseTraining or {}
  helperConfig.exerciseTraining.enabled = savedStates.enabled or false
end

-- ===== FIM HELPER EXERCISE TRAINING =====
