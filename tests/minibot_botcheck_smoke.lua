local compatPath = (... and ... ~= '') and ... or 'modules/game_minibot/compat.lua'

local counters = {
  cancelAttack = 0,
  flash = 0,
  focus = 0,
  moduleToggle = {},
  panel = {},
  play = 0,
  preload = 0,
  presetWrites = 0,
  removed = {},
  stop = 0,
  visualSync = 0
}
local visualSyncTypes = {}
local authoritativeCavebotStates = {}
local runtimeCavebotEnabled = false
local scheduled = {}
local rawOpcodes = {}
local jsonOpcodes = {}

g_logger = { warning = function() end }
UIWidget = {}
UIMinimap = {}
UIStoreButton = {}
PlayerStates = { Pz = 1 }
SpellGroup = {}
MarketCategory = {}
LocalPlayer = {}
ResourceBank = 0
ResourceInventory = 1
g_things = {}
torect = function(value) return value end
Spells = {
  getSpellDataById = function(id)
    if id == 44 then return { id = 44, name = 'Magic Shield' } end
    if id == 245 then return { id = 245, name = 'Cancel Magic Shield' } end
    if id == 500 then return { id = 500, name = 'Directional Test', directional = true } end
  end,
  getSpellList = function()
    return {
      { id = 44, name = 'Magic Shield' },
      { id = 245, name = 'Cancel Magic Shield' },
      { id = 500, name = 'Directional Test', directional = true }
    }
  end,
  getClientId = function(name)
    if name == 'Magic Shield' then return 124 end
    if name == 'Cancel Magic Shield' then return 147 end
    return 200
  end
}

local consoleEnabled = true
local botProfile = {
  shortcuts = {
    huntingRecorder_enabled = true,
    huntingExplorer_enabled = true,
    autoAttack_enabled = true
  }
}
local consoleWidget = {
  isDestroyed = function() return false end,
  isEnabled = function() return consoleEnabled end,
  focus = function() counters.focus = counters.focus + 1 end
}

local alarmChannel = {
  play = function(_, path, fadeIn, gain)
    assert(path == '/sounds/gm_detected.ogg' and fadeIn == 0 and gain == 1.0)
    counters.play = counters.play + 1
  end,
  setEnabled = function(_, enabled)
    assert(enabled == true)
  end,
  stop = function(_, fadeOut)
    assert(fadeOut == 0)
    counters.stop = counters.stop + 1
  end
}

modules = {
  client_options = {},
  game_actionbar = {},
  game_console = { getConsole = function() return consoleWidget end },
  game_minibot = {
    getPressetSettings = function()
      return botProfile
    end,
    setPressetSettings = function(settings)
      botProfile = settings
      counters.presetWrites = counters.presetWrites + 1
    end,
    disableMovementShortcut = function(settings, moduleType)
      if moduleType == 5 then
        settings.shortcuts.huntingRecorder_enabled = false
      elseif moduleType == 21 then
        settings.shortcuts.huntingExplorer_enabled = false
      else
        return false
      end
      return true
    end,
    syncDisabledMovementAutomationWidgets = function(moduleType)
      counters.visualSync = counters.visualSync + 1
      visualSyncTypes[#visualSyncTypes + 1] = moduleType or 'all'
    end,
    onMiniBotGameWindowChangeFromPanel = function(id, enabled)
      counters.panel[#counters.panel + 1] = { id, enabled }
    end
  }
}

g_sounds = {
  getChannel = function(channel)
    assert(channel == 4)
    return alarmChannel
  end,
  preload = function(path)
    assert(path == '/sounds/gm_detected.ogg')
    counters.preload = counters.preload + 1
  end
}

g_window = {
  flash = function()
    counters.flash = counters.flash + 1
  end
}

g_game = {
  cancelAttack = function()
    counters.cancelAttack = counters.cancelAttack + 1
  end,
  getLocalPlayer = function() return nil end,
  isOnline = function() return false end,
}

function signalcall(callback, ...)
  if callback then callback(...) end
end

g_minibot = {
  applyServerCavebotState = function(enabled)
    authoritativeCavebotStates[#authoritativeCavebotStates + 1] = enabled
    runtimeCavebotEnabled = enabled
    return true
  end,
  isModuleToggle = function(moduleType)
    assert(moduleType == 5)
    return runtimeCavebotEnabled
  end,
  setAutoAttack = function(value)
    assert(value == 0)
    counters.autoAttack = (counters.autoAttack or 0) + 1
  end,
  setModuleToggle = function(moduleType, enabled)
    assert(enabled == false)
    if moduleType == 5 then
      runtimeCavebotEnabled = false
    end
    counters.moduleToggle[#counters.moduleToggle + 1] = moduleType
  end
}

ProtocolGame = {
  registerExtendedOpcode = function(opcode, callback)
    assert(rawOpcodes[opcode] == nil)
    rawOpcodes[opcode] = callback
  end,
  unregisterExtendedOpcode = function(opcode)
    assert(rawOpcodes[opcode] ~= nil)
    rawOpcodes[opcode] = nil
  end,
  registerExtendedJSONOpcode = function(opcode, callback)
    assert(jsonOpcodes[opcode] == nil)
    jsonOpcodes[opcode] = callback
  end,
  unregisterExtendedJSONOpcode = function(opcode)
    assert(jsonOpcodes[opcode] ~= nil)
    jsonOpcodes[opcode] = nil
  end
}

function scheduleEvent(callback, delay)
  assert(delay == 3000)
  local event = { callback = callback, removed = false }
  scheduled[#scheduled + 1] = event
  return event
end

function removeEvent(event)
  event.removed = true
  counters.removed[#counters.removed + 1] = event
end

assert(loadfile(compatPath))()
MiniBotCompat.init()

assert(type(rawOpcodes[230]) == 'function')
assert(type(jsonOpcodes[213]) == 'function')
assert(MiniBotCompat.getBotCheckAlarmState().registered == true)
assert(counters.preload == 1)
assert(type(g_sounds.playAlarm) == 'function' and type(g_sounds.stopAlarm) == 'function')
assert(g_spells.getSpellRegularImageClipById(44) == '3936 0 32 32')
assert(g_spells.getSpellRegularIdByImageClipX(3936) == 44)
assert(g_spells.getSpellRegularImageClipById(245) == '4672 0 32 32')
assert(g_spells.getSpellRegularIdByImageClipX(4672) == 245)
assert(g_spells.getSpellInfoById(500).needDirection == true,
  'directional spell metadata was not normalized to needDirection')

assert(modules.game_console.focusChat() == true)
assert(counters.focus == 1)
consoleEnabled = false
assert(modules.game_console.focusChat() == false)
assert(counters.focus == 1)
consoleEnabled = true

local authorityState = {
  v = 1, action = 'state', enabled = false, task = false,
  timeLeft = 100, total = 100, renewPrice = 0, bannedUntil = 0,
  afkPauseUntil = 0, afkAvailableAt = 0, bankBalance = 0,
  inventoryBalance = 0, botCheckActive = false
}

-- A normal initial OFF snapshot arrives before profile reload. It must update
-- runtime authority without destroying the user's saved ON preference.
jsonOpcodes[213](nil, 213, authorityState)
assert(authoritativeCavebotStates[#authoritativeCavebotStates] == false)
assert(botProfile.shortcuts.huntingRecorder_enabled == true and counters.presetWrites == 0,
  'initial authoritative OFF snapshot erased the saved Recorder preference')
assert(counters.visualSync == 0,
  'initial authoritative OFF snapshot changed Recorder controls before profile reload')

-- A local enable awaiting its server answer is a real rejection even when the
-- server does not include an error string.
runtimeCavebotEnabled = true
local togglesBeforeServerShutdown = #counters.moduleToggle
jsonOpcodes[213](nil, 213, authorityState)
assert(authoritativeCavebotStates[#authoritativeCavebotStates] == false)
assert(botProfile.shortcuts.huntingRecorder_enabled == false and counters.presetWrites == 1,
  'pending cavebot enable rejection was not persisted')
assert(counters.visualSync == 1 and visualSyncTypes[1] == 5,
  'pending cavebot enable rejection did not synchronize Recorder controls')
assert(#counters.moduleToggle == togglesBeforeServerShutdown and #counters.panel == 0,
  'authoritative cavebot rejection was echoed through the user toggle path')

-- Expiration after an accepted ON state is a true ON -> OFF transition and
-- must persist even if runtime application itself is opcode-silent.
botProfile.shortcuts.huntingRecorder_enabled = true
authorityState.enabled = true
jsonOpcodes[213](nil, 213, authorityState)
assert(authoritativeCavebotStates[#authoritativeCavebotStates] == true)
authorityState.enabled = false
authorityState.error = 'cavebot expired'
jsonOpcodes[213](nil, 213, authorityState)
assert(botProfile.shortcuts.huntingRecorder_enabled == false and counters.presetWrites == 2,
  'authoritative cavebot expiration was not persisted')
assert(counters.visualSync == 2 and visualSyncTypes[2] == 5,
  'authoritative cavebot expiration did not synchronize Recorder controls')
assert(#counters.moduleToggle == togglesBeforeServerShutdown and #counters.panel == 0,
  'authoritative cavebot expiration was echoed through the user toggle path')
botProfile.shortcuts.huntingRecorder_enabled = true

rawOpcodes[230](nil, 230, ' start ')
assert(counters.play == 1 and counters.flash == 1)
assert(#counters.panel == 3)
assert(counters.panel[1][1] == 'huntingRecorder_gamewindow' and counters.panel[1][2] == false)
assert(counters.panel[2][1] == 'huntingExplorer_gamewindow' and counters.panel[2][2] == false)
assert(counters.panel[3][1] == 'combat_gamewindow' and counters.panel[3][2] == false)
assert(counters.presetWrites == 3 and
  botProfile.shortcuts.huntingRecorder_enabled == false and
  botProfile.shortcuts.huntingExplorer_enabled == false,
  'bot-check shutdown did not persist both movement shortcuts as disabled')
assert(counters.visualSync == 3 and visualSyncTypes[3] == 'all',
  'bot-check shutdown did not synchronize the open page and compact buttons')
assert(#counters.moduleToggle == 2 and counters.moduleToggle[1] == 5 and counters.moduleToggle[2] == 21)
assert(counters.autoAttack == 1 and counters.cancelAttack == 1)
assert(MiniBotCompat.getBotCheckAlarmState().active == true)
assert(MiniBotCompat.getBotCheckAlarmState().scheduled == true)

local staleEvent = scheduled[#scheduled]
rawOpcodes[230](nil, 230, 'START')
assert(staleEvent.removed == true)
assert(counters.play == 2 and counters.flash == 2)
local currentEvent = scheduled[#scheduled]

-- A removed event that was already queued must not clear or duplicate the new loop.
staleEvent.callback()
assert(#scheduled == 2)
assert(MiniBotCompat.getBotCheckAlarmState().scheduled == true)

currentEvent.callback()
assert(counters.play == 3)
assert(#scheduled == 3)

rawOpcodes[230](nil, 230, 'stop')
assert(MiniBotCompat.getBotCheckAlarmState().active == false)
assert(MiniBotCompat.getBotCheckAlarmState().scheduled == false)
assert(scheduled[3].removed == true)
assert(counters.stop >= 1)
assert(MiniBotCompat.handleBotCheckCommand('invalid') == false)

local serverState = {
  v = 1, action = 'state', enabled = false, task = false,
  timeLeft = 100, total = 100, renewPrice = 0, bannedUntil = 0,
  afkPauseUntil = 0, afkAvailableAt = 0, bankBalance = 0,
  inventoryBalance = 0, botCheckActive = true
}
local playsBeforeState = counters.play
jsonOpcodes[213](nil, 213, serverState)
assert(MiniBotCompat.getBotCheckAlarmState().active == true)
assert(counters.play == playsBeforeState + 1)
jsonOpcodes[213](nil, 213, serverState)
assert(counters.play == playsBeforeState + 1, 'repeated state restarted the alarm')
serverState.botCheckActive = false
jsonOpcodes[213](nil, 213, serverState)
assert(MiniBotCompat.getBotCheckAlarmState().active == false)

MiniBotCompat.terminate()
assert(rawOpcodes[230] == nil and jsonOpcodes[213] == nil)
assert(MiniBotCompat.getBotCheckAlarmState().registered == false)
assert(modules.game_console.focusChat == nil)
assert(g_sounds.playAlarm == nil and g_sounds.stopAlarm == nil)

print('minibot bot-check smoke: OK')
