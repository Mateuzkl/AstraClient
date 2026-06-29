-- Hold first batch of helper state as env globals to stay under 200 locals in helper.lua
player = nil
healingPanel = nil
toolsPanel = nil
targetingPanel = nil
shooterPanel = nil
runePanel = nil
knightHelperPanel = nil
mageHelperPanel = nil
paladinHelperPanel = nil
monkHelperPanel = nil
cavePanel = nil
friendHealPanel = nil
friendHealingPanel = nil
timerPanel = nil
profilesPanel = nil
settingsPanel = nil
alarmsPanel = nil
timerEvents = {}
targetModeSelector = nil
granSioPanel = nil
tioSioPanel = nil
uhRunePanel = nil
attackSpellPanel3 = nil
attackSpellPanel4 = nil
equipPanel = nil
equipmentPanel = nil
mouseGrabberWidget = nil
helper = nil
helperRules = nil
friendListWidget = nil
granListWidget = nil
autoLoadRadioGroup = nil
helperSessionState = {
    lastPosition = nil,
    lastMenu = "healingMenu",
    currentCharacter = nil,
    loadedProfile = nil,
    loadedProfileReadOnly = false,
    isSessionActive = false,
    hasValidSnapshot = false,
    dustLimit = nil
}
helperSessionSnapshot = nil
debugPopup = nil
shooterPresetWindow = nil
debugUpdateEvent = nil
SHOOTER_DEBUG = false
shooterDebugWidgets = {}
equipmentSettingsPopup = nil
presetHotkeyLabelsRefreshEvent = nil
presetHotkeyLabelsRefreshRetryEvent = nil
externalWatchdog = {
    event = nil,
    debug = false,
    failCount = 0,
    lastRestart = 0,
    restartCooldown = 5000,
    maxFailCount = 3
}
-- Second batch: shooter/PZ/timers/cave/zerobot state (same file to avoid two inits)
noAreaSpellAttempts = {}
spellNeedLearnBackoff = {}
lastAttemptedShooterSpellId = nil
lastAttemptedShooterSpellWords = nil
helperNeedLearnMessageCallback = nil
shooterDebugClearEvent = nil
lureDebugWidgets = {}
lureDebugUpdateEvent = nil
customSpellTimers = {}
customSpellCheckEvent = nil
pzStateBackup = {
    autoTargetEnabled = false,
    magicShooterEnabled = false,
    magicHelperEnabled = false
}
isInPZ = false
pzCheckEvent = nil
autoTargetOnHold = false
multiUseExDelay = 0
caveRecorderRoot = nil
caveRecorderTab = nil
caveContainer = nil
MAX_FRIENDS = 5
_pressets = _pressets or {}
_settings = _settings or {}
lastUsedType = "spell"
spellAreaCache = {}
spellRangeCache = {}
spellAreasLoaded = false
-- Real (server-side) vocation id, learned via extended opcode 206. The login
-- protocol only carries the client-id vocation, which is identical for a base
-- vocation's 2nd and 3rd promotion (Elite Knight == Titan Knight == client-id 11),
-- so the helper/shooter needs this to size the Titan's larger exori gran AoE.
-- nil until the server replies (see onHelperRealVocation / requestRealVocation).
REAL_VOCATION_OPCODE = 206
TITAN_KNIGHT_VOCATION_ID = 14
helperRealVocationId = nil
zerobotImportDialog = nil
