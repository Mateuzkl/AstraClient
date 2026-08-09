local MINI_BOT_OPCODE = 0xD0

local window = nil
local toggleButton = nil
local authorizationEvent = nil
local updatingUI = false

local pageNames = {
  "dashboard",
  "healing",
  "combat",
  "support",
  "equipment",
  "cavebot"
}

local booleanFields = {
  "masterEnabled",
  "healthSpellEnabled",
  "healthItemEnabled",
  "manaItemEnabled",
  "groupHealEnabled",
  "autoTargetEnabled",
  "attackSpellEnabled",
  "attackRuneEnabled",
  "combatPauseCavebot",
  "hasteEnabled",
  "manaShieldEnabled",
  "antiParalyzeEnabled",
  "manaTrainerEnabled",
  "timerSpellEnabled",
  "equipmentEnabled",
  "cavebotEnabled",
  "cavebotLoop"
}

local numberFields = {
  "healthSpellPercent",
  "healthItemId",
  "healthItemPercent",
  "manaItemId",
  "manaItemPercent",
  "groupHealPercent",
  "attackMinMonsters",
  "attackRange",
  "attackRuneId",
  "manaTrainerPercent",
  "timerSpellInterval",
  "emergencyPercent",
  "emergencyAmuletId",
  "normalAmuletId",
  "emergencyRingId",
  "normalRingId",
  "cavebotStepDelay"
}

local textFields = {
  "healthSpell",
  "groupHealName",
  "groupHealSpell",
  "attackSpell",
  "hasteSpell",
  "manaShieldSpell",
  "antiParalyzeSpell",
  "manaTrainerSpell",
  "timerSpell",
  "cavebotWaypoints"
}

local function getWidget(id)
  return window and window:recursiveGetChildById(id) or nil
end

local function requestServerAuthorization()
  authorizationEvent = nil
  if not g_game.isOnline() then
    return
  end
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(MINI_BOT_OPCODE, "request")
  end
end

local function updateAuthorizationLabel()
  local label = getWidget("authorizationStatus")
  if not label then
    return
  end
  if MiniBotEngine.isServerAuthorized() then
    label:setText(tr("Astra server: MiniBot authorized"))
    label:setColor("#62d273")
  else
    label:setText(tr("Astra server: waiting for authorization"))
    label:setColor("#e6a94d")
  end
end

local function onExtendedOpcode(protocol, opcode, buffer)
  if opcode ~= MINI_BOT_OPCODE then
    return
  end
  MiniBotEngine.setServerAuthorized(buffer == "enabled")
  updateAuthorizationLabel()
end

local function refreshPresetList()
  local combo = getWidget("presetCombo")
  if not combo then
    return
  end
  updatingUI = true
  combo:clearOptions()
  for _, name in ipairs(MiniBotEngine.getPresetNames()) do
    combo:addOption(name)
  end
  combo:setCurrentOption(MiniBotEngine.getActivePreset())
  updatingUI = false
end

function syncUI()
  if not window then
    return
  end
  updatingUI = true
  for _, id in ipairs(booleanFields) do
    local widget = getWidget(id)
    if widget then
      widget:setChecked(MiniBotEngine.get(id) == true)
    end
  end
  for _, id in ipairs(numberFields) do
    local widget = getWidget(id)
    if widget then
      widget:setText(tostring(MiniBotEngine.get(id) or 0))
    end
  end
  for _, id in ipairs(textFields) do
    local widget = getWidget(id)
    if widget then
      widget:setText(tostring(MiniBotEngine.get(id) or ""))
    end
  end
  updatingUI = false
  refreshPresetList()
  updateAuthorizationLabel()
end

local function setupWindow()
  local presetCombo = getWidget("presetCombo")
  if presetCombo then
    presetCombo.onOptionChange = function(widget)
      if updatingUI then
        return
      end
      local option = widget:getCurrentOption()
      if option and MiniBotEngine.selectPreset(option.text) then
        syncUI()
      end
    end
  end
  showPage("dashboard")
  syncUI()
end

function init()
  MiniBotEngine.init(setRuntimeStatus)
  ProtocolGame.registerExtendedOpcode(MINI_BOT_OPCODE, onExtendedOpcode)

  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline
  })

  toggleButton = modules.client_topmenu.addRightGameToggleButton(
    "deusMiniBotButton",
    tr("DeusOT MiniBot"),
    "/images/topbuttons/bot",
    toggle,
    false,
    99998
  )
  toggleButton:setOn(false)
  toggleButton:hide()

  window = g_ui.displayUI("minibot")
  window:hide()
  setupWindow()

  if g_game.isOnline() then
    online()
  end
end

function terminate()
  if authorizationEvent then
    removeEvent(authorizationEvent)
    authorizationEvent = nil
  end

  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline
  })
  ProtocolGame.unregisterExtendedOpcode(MINI_BOT_OPCODE)
  MiniBotEngine.terminate()

  if window then
    window:destroy()
    window = nil
  end
  if toggleButton then
    toggleButton:destroy()
    toggleButton = nil
  end
end

function online()
  MiniBotEngine.online()
  if toggleButton then
    toggleButton:show()
  end
  if authorizationEvent then
    removeEvent(authorizationEvent)
  end
  authorizationEvent = scheduleEvent(requestServerAuthorization, 250)
  updateAuthorizationLabel()
end

function offline()
  if authorizationEvent then
    removeEvent(authorizationEvent)
    authorizationEvent = nil
  end
  MiniBotEngine.offline()
  if window then
    window:hide()
  end
  if toggleButton then
    toggleButton:setOn(false)
    toggleButton:hide()
  end
  updateAuthorizationLabel()
end

function toggle()
  if not window then
    return
  end
  if window:isVisible() then
    window:hide()
    toggleButton:setOn(false)
  else
    window:show()
    window:raise()
    window:focus()
    toggleButton:setOn(true)
    syncUI()
  end
end

function onWindowClose()
  if toggleButton then
    toggleButton:setOn(false)
  end
end

function showPage(name)
  for _, pageName in ipairs(pageNames) do
    local selected = pageName == name
    local page = getWidget(pageName .. "Page")
    local button = getWidget(pageName .. "Tab")
    if page then
      page:setVisible(selected)
    end
    if button then
      button:setOn(selected)
    end
  end
end

function setRuntimeStatus(text)
  local label = getWidget("runtimeStatus")
  if label then
    label:setText(tr(text))
  end
end

function setBoolean(key, value)
  if updatingUI then
    return
  end
  MiniBotEngine.set(key, value == true)
end

function setNumber(key, value, minimum, maximum)
  if updatingUI then
    return
  end
  value = tonumber(value)
  if not value then
    return
  end
  value = math.floor(math.max(tonumber(minimum) or 0, math.min(tonumber(maximum) or 65535, value)))
  MiniBotEngine.set(key, value)
end

function setText(key, value)
  if updatingUI then
    return
  end
  MiniBotEngine.set(key, tostring(value or ""))
end

function createPreset()
  local editor = getWidget("newPresetName")
  if not editor then
    return
  end
  if MiniBotEngine.createPreset(editor:getText()) then
    editor:setText("")
    syncUI()
    setRuntimeStatus("Preset created")
  else
    setRuntimeStatus("Invalid or duplicate preset name")
  end
end

function deletePreset()
  if MiniBotEngine.deleteActivePreset() then
    syncUI()
    setRuntimeStatus("Preset deleted")
  else
    setRuntimeStatus("The Default preset cannot be deleted")
  end
end

function resetPreset()
  MiniBotEngine.resetActivePreset()
  syncUI()
  setRuntimeStatus("Preset reset")
end

function addCurrentWaypoint()
  if MiniBotEngine.addCurrentWaypoint() then
    syncUI()
    setRuntimeStatus("Current position added to cavebot")
  end
end

function clearWaypoints()
  MiniBotEngine.clearWaypoints()
  syncUI()
  setRuntimeStatus("Cavebot waypoints cleared")
end
