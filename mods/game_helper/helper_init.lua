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

-- Cavebot death/respawn handshake (extended opcode 208). The server owns the
-- ground truth of death (creaturescript onDeath) and tells the client to freeze
-- the cavebot walker in place, so "Goto Label On Death" can reposition on respawn
-- instead of the old HP==0 heuristic corroding the index while the death window
-- is up. State byte: 0 = died (pause walker), 1 = revived (resume + goto label).
-- Client -> server on the death-window "Ok" click; server -> client on death and
-- on revive confirmation. See onHelperCavebotDeathState / hunting_recorder.
CAVEBOT_DEATH_OPCODE = 208

-- Cavebot Z-Recovery server oracle (extended opcode 209). When the cavebot walker
-- ends up on the WRONG floor it asks the server (which knows the real map: every
-- floor-change tile, its direction, teleport destinations, and true reachability)
-- for the best nearby floor-change to head for, instead of guessing from a curated
-- item-id table. Client -> server: JSON {x,y,z,n} (route waypoint + request nonce);
-- server -> client: JSON {ok,x,y,z,dz,use,n}. Falls back to the client-side
-- heuristic if the server script is absent (no reply within the timeout).
-- See CaveBot.onZRecoveryResponse (cavebots/actions.lua) / onHelperCavebotZRecovery.
CAVEBOT_ZRECOVERY_OPCODE = 209

-- Auto Fishing house authorization (extended opcode 215). The client can't see house
-- ownership per tile (the game protocol never sends it), so before fishing a Fishing
-- Basin (26077) the bot asks the server which nearby basins it may fish RIGHT NOW: the
-- player must be inside a house and the basin must be in that SAME house (invited).
-- Client -> server: "x,y,z;x,y,z" (candidate basins); server -> client: the allowed
-- subset. Answer cached per position (see onHelperFishingAuth / requestFishingAuth).
FISHING_BASIN_OPCODE = 215

-- Auto-trainer dummy authorization (extended opcode 216). The dummy search was widened
-- to the whole viewport (X +/-7, Y +/-5), so a dummy in a NEIGHBORING house can now fall
-- in range. The client can't see house ownership per tile, so before training it asks the
-- server which nearby dummies it may train on RIGHT NOW: mirroring exercise_training_weapons
-- onUse, a dummy inside a house needs the player in that SAME house, while a public dummy
-- (no house) is always allowed. Client -> server: "x,y,z;x,y,z" (candidate dummies);
-- server -> client: the allowed subset. Cached per position, keyed to the player's tile so
-- entering/leaving a house re-validates (see onHelperDummyTrainAuth / requestDummyTrainAuth).
DUMMY_TRAIN_OPCODE = 216
dummyAuthCache = {}         -- poskey -> { allowed = bool, ts = ms }
dummyAuthPending = {}       -- poskey -> requestMs (dummies we asked about, awaiting reply)
dummyAuthPlayerPos = nil    -- player poskey the cache is valid for (dropped when it changes)
lastDummyAuthRequestMs = 0  -- throttle for the authorization query
lastExerciseIssuedMs = 0    -- last time checkExerciseEvent actually used a weapon on a dummy
DUMMY_AUTH_TTL = 20000      -- how long a server answer stays fresh (house perms rarely change)
DUMMY_AUTH_TIMEOUT = 3000   -- fail open after this long with no reply (server script absent)
