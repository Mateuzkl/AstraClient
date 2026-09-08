-- ===== HELPER FOLLOW FRIEND =====
-- Keeps the character permanently following one named player.
--
-- The client's follow is a single server-side subscription: g_game.follow(creature)
-- asks the server to walk you after that creature, and the server drops it again on
-- its own the moment anything else claims the walk -- an attack, a manual step, the
-- target leaving the screen or changing floor. There is no "sticky follow" to switch
-- on, which is why this is a poll: every tick it checks whether the client is still
-- following the named friend, and re-subscribes if it is not.
--
-- Spell casting is untouched by any of this. Hotkeys, the Magic Shooter and the heal
-- bot all go out as talk/use packets, none of which cancel a follow -- so the
-- character keeps casting while it walks. Attacking is the one thing that cannot
-- coexist: Game::attack() calls cancelFollow() (and Game::follow() cancels the
-- attack), so Auto Target is held while this is on rather than letting the two cancel
-- each other several times a second.

if not _Helper then
  _Helper = {}
end

_Helper.FollowFriend = {}

-- Re-issuing follow costs one small packet, so this can be brisk; it only sends
-- anything at all when the follow has actually been dropped.
local lastFollowAttempt = 0
local FOLLOW_RETRY_INTERVAL = 250 -- ms between two follow packets
local lastRegisteredTarget = nil
local pendingTransition = nil
local TRANSITION_MAX_DISTANCE = 4
local TRANSITION_TIMEOUT = 3000
local USE_TRANSITION_TIMEOUT = 6000
local USE_RETRY_INTERVAL = 500
local USE_MAX_ATTEMPTS = 10
local LAST_TILE_MAX_AGE = 900
local lastFriendTile = nil
local lastFriendSeenAt = 0
local lastSeenWhileFollowing = false
local lastTileAttemptSeenAt = 0
local observedFriend = nil
local forceRefollow = false
local lastPlayerFloor = nil

local function getConfig()
  return _Helper.getHelperConfig and _Helper.getHelperConfig() or nil
end

local function trim(text)
  return (tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function sendOpcode(opcode, buffer)
  local protocol = g_game.getProtocolGame()
  return protocol and protocol:sendExtendedOpcode(opcode, buffer) or false
end

local function syncServerTarget()
  local active = _Helper.FollowFriend.isActive and _Helper.FollowFriend.isActive()
  local wanted = active and _Helper.FollowFriend.getName() or ''
  local key = wanted:lower()
  if lastRegisteredTarget ~= nil and key == lastRegisteredTarget then
    return
  end

  lastRegisteredTarget = key
  sendOpcode(ExtendedIds.SmartFollow, active and 'on' or 'off')
  sendOpcode(ExtendedIds.FollowTransition, active and ('set ' .. wanted) or 'clear')
end

local function positionDistance(a, b)
  if not a or not b or a.z ~= b.z then return math.huge end
  return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

local function rememberFriendTile(friend, isFollowing)
  local position = friend and friend:getPosition() or nil
  if not position then return end
  lastFriendTile = { x = position.x, y = position.y, z = position.z }
  lastFriendSeenAt = g_clock.millis()
  lastSeenWhileFollowing = isFollowing == true
end

local function onObservedFriendPositionChange(creature, newPosition, oldPosition)
  if creature ~= observedFriend or not _Helper.FollowFriend.isActive() or not newPosition then
    return
  end
  local following = g_game.getFollowingCreature and g_game.getFollowingCreature() or nil
  local isFollowing = following and following:getId() == creature:getId()
  local remembered = newPosition
  if oldPosition and (oldPosition.z ~= newPosition.z or
      math.max(math.abs(oldPosition.x - newPosition.x), math.abs(oldPosition.y - newPosition.y)) > 1) then
    -- For the transition movement itself, oldPosition is the entrance and
    -- newPosition is already the remote destination. The follower needs the entrance.
    remembered = oldPosition
  end
  lastFriendTile = { x = remembered.x, y = remembered.y, z = remembered.z }
  lastFriendSeenAt = g_clock.millis()
  -- Once confirmed, keep this true through the brief server-side follow teardown
  -- that accompanies the friend disappearing on a different floor.
  lastSeenWhileFollowing = lastSeenWhileFollowing or isFollowing
end

local function observeFriend(friend)
  if observedFriend == friend then return end
  if observedFriend then
    pcall(disconnect, observedFriend, { onPositionChange = onObservedFriendPositionChange })
  end
  observedFriend = friend
  if observedFriend then
    connect(observedFriend, { onPositionChange = onObservedFriendPositionChange })
  end
end

local function stopObservingFriend()
  if observedFriend then
    pcall(disconnect, observedFriend, { onPositionChange = onObservedFriendPositionChange })
    observedFriend = nil
  end
end

local function continueToLastFriendTile()
  if not lastFriendTile or not lastSeenWhileFollowing or
      lastTileAttemptSeenAt == lastFriendSeenAt then
    return false
  end

  local now = g_clock.millis()
  local player = g_game.getLocalPlayer()
  local position = player and player:getPosition() or nil
  if not position or now - lastFriendSeenAt > LAST_TILE_MAX_AGE or
      position.z ~= lastFriendTile.z or
      positionDistance(position, lastFriendTile) > TRANSITION_MAX_DISTANCE then
    return false
  end

  -- One attempt for this exact sighting. This handles the small gap between the
  -- friend entering a stair/teleport and the server transition signal arriving,
  -- while preventing repeated walks toward a stale location.
  lastTileAttemptSeenAt = lastFriendSeenAt
  forceRefollow = true
  player:autoWalk({ x = lastFriendTile.x, y = lastFriendTile.y, z = lastFriendTile.z },
    false, PathFindAllowNonPathable)
  return true
end

local function onFollowTransition(_, _, data)
  if type(data) ~= 'table' or data.action ~= 'transition' or
      not _Helper.FollowFriend.isActive() then
    return
  end

  local wanted = _Helper.FollowFriend.getName():lower()
  if tostring(data.targetName or ''):lower() ~= wanted then
    return
  end

  local entry = data.entry
  local destination = data.destination
  local interaction = tostring(data.interaction or 'walk')
  local player = g_game.getLocalPlayer()
  local playerPos = player and player:getPosition() or nil
  if type(entry) ~= 'table' or type(destination) ~= 'table' or not playerPos or
      playerPos.z ~= tonumber(entry.z) or positionDistance(playerPos, entry) > TRANSITION_MAX_DISTANCE then
    return
  end

  pendingTransition = {
    expires = g_clock.millis() +
      (interaction == 'use' and USE_TRANSITION_TIMEOUT or TRANSITION_TIMEOUT),
    entryZ = tonumber(entry.z),
    destination = {
      x = tonumber(destination.x), y = tonumber(destination.y), z = tonumber(destination.z)
    },
    interaction = interaction,
    useAttempts = 0,
    lastUseAttempt = 0,
    entry = { x = tonumber(entry.x), y = tonumber(entry.y), z = tonumber(entry.z) },
  }

  -- This is still an ordinary walk. The destination tile's own stair/teleport
  -- movement and access checks decide whether the player may pass.
  if pendingTransition.interaction == 'use' and positionDistance(playerPos, pendingTransition.entry) <= 1 then
    local tile = g_map.getTile(pendingTransition.entry)
    local thing = tile and tile:getTopUseThing() or nil
    if thing then
      pendingTransition.useAttempts = 1
      pendingTransition.lastUseAttempt = g_clock.millis()
      g_game.use(thing)
    end
  else
    player:autoWalk(pendingTransition.entry, false, PathFindAllowNonPathable)
  end
end

if ProtocolGame and ProtocolGame.registerExtendedJSONOpcode then
  local registered = pcall(ProtocolGame.registerExtendedJSONOpcode,
    ExtendedIds.FollowTransition, onFollowTransition)
  if not registered and ProtocolGame.unregisterExtendedJSONOpcode then
    pcall(ProtocolGame.unregisterExtendedJSONOpcode, ExtendedIds.FollowTransition)
    pcall(ProtocolGame.registerExtendedJSONOpcode,
      ExtendedIds.FollowTransition, onFollowTransition)
  end
end

-- Is Follow Friend switched on AND pointed at somebody?
_Helper.FollowFriend.isActive = function()
  local config = getConfig()
  if not config or not config.followFriendEnabled then
    return false
  end
  return trim(config.followFriendName) ~= ''
end

_Helper.FollowFriend.getName = function()
  local config = getConfig()
  return config and trim(config.followFriendName) or ''
end

-- The named player, if they are on screen right now. Compared case-insensitively:
-- the field is typed by hand and Tibia names are displayed capitalised.
_Helper.FollowFriend.findFriend = function()
  local wanted = _Helper.FollowFriend.getName():lower()
  if wanted == '' then
    return nil
  end

  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then
    return nil
  end

  local spectators = _Helper.getSpectators and _Helper.getSpectators() or nil
  if not spectators or #spectators == 0 then
    local position = localPlayer:getPosition()
    if not position then
      return nil
    end
    spectators = g_map.getSpectators(position, false)
  end

  for _, creature in ipairs(spectators or {}) do
    if creature and creature:isPlayer() and creature:getName():lower() == wanted then
      return creature
    end
  end

  return nil
end

_Helper.FollowFriend.check = function()
  if not _Helper.FollowFriend.isActive() then
    return
  end

  if not g_game.isOnline() then
    return
  end

  syncServerTarget()

  local localPlayer = g_game.getLocalPlayer()
  local localPosition = localPlayer and localPlayer:getPosition() or nil
  if localPosition then
    if lastPlayerFloor ~= nil and localPosition.z ~= lastPlayerFloor then
      forceRefollow = true
    end
    lastPlayerFloor = localPosition.z
  end

  if pendingTransition then
    local player = g_game.getLocalPlayer()
    local position = player and player:getPosition() or nil
    if not position or g_clock.millis() > pendingTransition.expires then
      pendingTransition = nil
    elseif (pendingTransition.destination.z ~= pendingTransition.entryZ and
        position.z == pendingTransition.destination.z) or
        (pendingTransition.destination.z == pendingTransition.entryZ and
        positionDistance(position, pendingTransition.destination) <= 1) then
      pendingTransition = nil
      lastFollowAttempt = 0
      forceRefollow = true
    else
      local now = g_clock.millis()
      if pendingTransition.interaction == 'use' and
          pendingTransition.useAttempts < USE_MAX_ATTEMPTS and
          now - pendingTransition.lastUseAttempt >= USE_RETRY_INTERVAL and
          positionDistance(position, pendingTransition.entry) <= 1 then
        local tile = g_map.getTile(pendingTransition.entry)
        local thing = tile and tile:getTopUseThing() or nil
        if thing then
          pendingTransition.useAttempts = pendingTransition.useAttempts + 1
          pendingTransition.lastUseAttempt = now
          g_game.use(thing)
        end
      end
      -- Do not replace the authorized auto-walk with follow packets while the
      -- friend is temporarily absent on the destination floor.
      return
    end
  end

  local friend = _Helper.FollowFriend.findFriend()
  if not friend then
    -- Out of sight (or not logged in). Nothing to re-subscribe to; the next tick
    -- that sees them picks the follow straight back up, which is what "never
    -- stops" means in practice -- walking off screen does not turn the option off.
    continueToLastFriendTile()
    return
  end

  observeFriend(friend)

  local following = g_game.getFollowingCreature and g_game.getFollowingCreature() or nil
  if following and following:getId() == friend:getId() and not forceRefollow then
    rememberFriendTile(friend, true)
    return
  end

  local now = g_clock.millis()
  if now - lastFollowAttempt < FOLLOW_RETRY_INTERVAL then
    return
  end
  lastFollowAttempt = now

  if forceRefollow and following then
    -- A floor/teleport transition can leave the old creature selected locally
    -- after the server has discarded its follow path. Clear that stale state so
    -- the following packet below always creates a fresh path at the destination.
    g_game.follow(nil)
  end
  g_game.follow(friend)
  forceRefollow = false
  rememberFriendTile(friend, true)
end

-- Called from the checkbox in the targeting panel.
_Helper.FollowFriend.toggle = function(widget)
  local config = getConfig()
  if not config then
    return
  end

  local shooterPanel = _Helper.getShooterPanel and _Helper.getShooterPanel()
  local enableButtons = _Helper.getEnableButtons and _Helper.getEnableButtons()

  if not widget then
    if shooterPanel then
      widget = shooterPanel:recursiveGetChildById('enableFollowFriend')
    elseif enableButtons then
      widget = enableButtons:recursiveGetChildById('enableFollowFriend')
    end
    if not widget then
      return
    end
    widget:setChecked(not widget:isChecked())
  end

  config.followFriendEnabled = widget:isChecked()

  if config.followFriendEnabled then
    -- Follow and attack are mutually exclusive at the protocol level, so drop any
    -- attack now instead of letting the two cancel each other every tick.
    if g_game.isAttacking() then
      g_game.cancelAttack()
    end
    config.currentLockedTargetId = 0
    lastFollowAttempt = 0
    lastRegisteredTarget = nil
    _Helper.FollowFriend.check()
  elseif g_game.isOnline() and g_game.isFollowing and g_game.isFollowing() then
    -- Only let go of a follow this module is responsible for. A follow the player
    -- started by hand on somebody else is left alone.
    local following = g_game.getFollowingCreature and g_game.getFollowingCreature() or nil
    local wanted = _Helper.FollowFriend.getName():lower()
    if following and wanted ~= '' and following:getName():lower() == wanted then
      g_game.follow(nil)
    end
  end

  if not config.followFriendEnabled then
    pendingTransition = nil
    lastFriendTile = nil
    lastFriendSeenAt = 0
    lastSeenWhileFollowing = false
    lastTileAttemptSeenAt = 0
    forceRefollow = false
    lastPlayerFloor = nil
    stopObservingFriend()
    lastRegisteredTarget = nil
    syncServerTarget()
  end

  if saveSettings then
    saveSettings()
  end
end

_Helper.FollowFriend.setName = function(text)
  local config = getConfig()
  if not config then
    return
  end

  local name = trim(text)
  if name == config.followFriendName then
    return
  end

  config.followFriendName = name
  -- Retarget immediately rather than waiting out the retry window, so correcting a
  -- typo takes effect on the next tick instead of feeling stuck on the old name.
  lastFollowAttempt = 0
  lastRegisteredTarget = nil
  pendingTransition = nil
  lastFriendTile = nil
  lastFriendSeenAt = 0
  lastSeenWhileFollowing = false
  lastTileAttemptSeenAt = 0
  forceRefollow = false
  lastPlayerFloor = nil
  stopObservingFriend()

  if g_game.isOnline() then
    syncServerTarget()
  end

  if saveSettings then
    saveSettings()
  end
end

-- Push the saved state back into the widgets after a config load / character switch.
_Helper.FollowFriend.loadToUI = function()
  local config = getConfig()
  local enableButtons = _Helper.getEnableButtons and _Helper.getEnableButtons()
  if not config or not enableButtons then
    return
  end

  local checkbox = enableButtons:recursiveGetChildById('enableFollowFriend')
  if checkbox then
    checkbox:setChecked(config.followFriendEnabled or false)
  end

  local input = enableButtons:recursiveGetChildById('followFriendInput')
  if input then
    input:setText(config.followFriendName or '')
  end
end

_Helper.FollowFriend.reset = function()
  lastFollowAttempt = 0
  lastRegisteredTarget = nil
  pendingTransition = nil
  lastFriendTile = nil
  lastFriendSeenAt = 0
  lastSeenWhileFollowing = false
  lastTileAttemptSeenAt = 0
  forceRefollow = false
  lastPlayerFloor = nil
  stopObservingFriend()
end
