if not MinimapLoader then
  MinimapLoader = {
    loaded = false,
    otmmLoaded = false
  }
  MinimapLoader.__index = MinimapLoader
end

minimapWidget = nil
minimapWindow = nil
otmm = true
preloaded = false
fullmapView = false
oldZoom = nil
oldPos = nil

local minimapFile = '/minimap.otmm'
local minimapBackupFile = '/minimap.otmm.bak'

-- HD minimap -----------------------------------------------------------------
-- Optional layer that composites blocks from the real item sprites. It is a pure
-- sidecar: the base minimap.otmm above is never read or written differently
-- because of it, and if anything HD fails the standard minimap is unaffected.
minimapHDToggle = nil

local lastHDWorld = 'unknown'
local lastHDCharacter = 'unknown'

local function sanitizeHDFilePart(value)
  value = tostring(value or '')
  value = value:gsub('[^%w%-_]+', '_'):gsub('^_+', ''):gsub('_+$', '')
  if value == '' then
    return 'unknown'
  end
  return value:lower()
end

-- HD tile data is keyed by client version, world and character so a cache from one
-- world can never be loaded into another. Sanitised because these come from the
-- server. Global so functions defined later can reach it.
function minimapHDFile()
  local version = sanitizeHDFilePart(g_game.getClientVersion())
  local world = sanitizeHDFilePart(g_game.getWorldName and g_game.getWorldName() or nil)
  local character = sanitizeHDFilePart(g_game.getCharacterName and g_game.getCharacterName() or nil)

  -- Logout clears these before offline() runs, so keep the last known values.
  if world ~= 'unknown' then lastHDWorld = world else world = lastHDWorld end
  if character ~= 'unknown' then lastHDCharacter = character else character = lastHDCharacter end

  return string.format('/minimap/minimap_%s_%s_%s_hd.otmm', version, world, character)
end

function isHDEnabled()
  return g_settings.getBoolean('minimapHD', false)
end

-- Never blocks: the engine coalesces a request that arrives while a save runs.
local function saveHDMap()
  if not isHDEnabled() or not MinimapLoader.loaded then
    return
  end
  g_minimap.saveOtmmHD(minimapHDFile())
end

-- The distributed whole-world layer is a raster archive. It contains rendered
-- block images, never the item-id/coordinate records used by the old HD base.
-- A server cache is selected per client version and world; a bundled raster is
-- still supported as an offline fallback.
local HD_BUNDLED_RASTER_FILE = '/data/minimap_hd_raster.hdr'
local HD_BASE_TRANSFER_FILE = '/minimap/server_hd_raster.download'
local activeHDBaseFile = nil

local function attachHDBase()
  if g_minimap.hasHDBase() then
    return true
  end
  local fileName = activeHDBaseFile
  if not fileName or not g_resources.fileExists(fileName) then
    fileName = HD_BUNDLED_RASTER_FILE
  end
  if not g_resources.fileExists(fileName) then
    return false
  end
  return g_minimap.openHDBase(fileName)
end

-- One-off publication tool: renders a raster archive from a server map.
--
-- The .otbm stores SERVER item ids, so items.otb is required to translate them
-- into the client ids the sprites are indexed by. Nothing else in the client
-- loads items.otb, so it is loaded here on demand. Both files must come from the
-- same server as the assets in data/things, otherwise the ids will not line up.
--
--   modules.game_minimap.generateHDBase('/world.otbm', '/items.otb')
function generateHDBase(otbmPath, otbPath)
  otbmPath = otbmPath or '/world.otbm'
  otbPath = otbPath or '/items.otb'

  if not g_resources.fileExists(otbmPath) then
    consoleln('HD baseline: ' .. otbmPath .. ' not found.')
    return false
  end

  if not g_things.isOtbLoaded() then
    if not g_resources.fileExists(otbPath) then
      consoleln('HD baseline: ' .. otbPath .. ' not found, and it is required to map server ids to client ids.')
      return false
    end
    if not g_things.loadOtb(otbPath) then
      consoleln('HD baseline: failed to load ' .. otbPath .. '.')
      return false
    end
    consoleln('HD baseline: loaded ' .. otbPath .. '.')
  end

  consoleln('HD baseline: generating from ' .. otbmPath .. ', this takes a while and the client will freeze...')
  local ok = g_minimap.generateHDFromOtbm(otbmPath, '/minimap_hd_raster.hdr')
  if ok then
    consoleln('HD baseline: done. It is in the write dir; move it to data/ and restart.')
  else
    consoleln('HD baseline: failed, see the log.')
  end
  return ok
end

function applyHDMode(enabled, reload)
  if enabled then
    attachHDBase()
  end
  g_minimap.setHDMode(enabled)
  if minimapHDToggle then
    minimapHDToggle:setOn(enabled)
  end
  if enabled and reload and g_game.isOnline() then
    g_minimap.loadOtmmHD(minimapHDFile())
  end
end

function toggleHD()
  local enabled = not isHDEnabled()
  if not enabled then
    saveHDMap()   -- persist progress before leaving HD mode
  end
  g_settings.set('minimapHD', enabled)
  g_settings.save()
  applyHDMode(enabled, true)
end

-- Debug helper: modules.game_minimap.printHDStats()
function printHDStats()
  consoleln(g_minimap.getHDStats())
end
-------------------------------------------------------------------------------

local function saveMap()
  if not MinimapLoader.loaded then
    return
  end

  g_minimap.saveOtmm(minimapFile)
  saveHDMap()
  if minimapWidget then
    minimapWidget:save()
  end
end

local keybindMoveEast = KeyBind:getKeyBind("Minimap", "Scroll East")
local keybindMoveNorth = KeyBind:getKeyBind("Minimap", "Scroll North")
local keybindMoveSouth = KeyBind:getKeyBind("Minimap", "Scroll South")
local keybindMoveWest = KeyBind:getKeyBind("Minimap", "Scroll West")
local keybindFloorUp = KeyBind:getKeyBind("Minimap", "One Floor Up")
local keybindFloorDown = KeyBind:getKeyBind("Minimap", "One Floor Down")
local keybindZoomIn = KeyBind:getKeyBind("Minimap", "Zoom In")
local keybindZoomOut = KeyBind:getKeyBind("Minimap", "Zoom Out")
local keybindCenter = KeyBind:getKeyBind("Minimap", "Center")
local keybindShowMinimap = KeyBind:getKeyBind("Minimap", "Show")

local EXPANSION_SETTINGS_PREFIX = 'Minimap_Expansion_'
local EXPANDED_WIDTH = 356
local EXPANDED_HEIGHT = 240
local COLLAPSE_SNAP_MARGIN = 12
local minimapDownloadOperation = nil

-- Authenticated server-provided OTMM synchronization. The player map remains a
-- separate layer and the public HTTP download path is intentionally not used.
local SERVER_MINIMAP_DIRECTORY = '/minimap'
local SERVER_MINIMAP_DEFAULT_MAX_BYTES = 64 * 1024 * 1024
local SERVER_MINIMAP_HARD_MAX_BYTES = 256 * 1024 * 1024
local SERVER_HD_MINIMAP_DEFAULT_MAX_BYTES = 256 * 1024 * 1024
local SERVER_HD_MINIMAP_HARD_MAX_BYTES = 512 * 1024 * 1024
local SERVER_MINIMAP_MAX_VERSION_BYTES = 96
local SERVER_MINIMAP_TRANSFER_TIMEOUT = 15000
local SERVER_MINIMAP_REQUEST_RETRIES = 20

local serverMinimapOpcode = nil
local serverMinimapRegistered = false
local serverMinimapRequestEvent = nil
local serverMinimapTimeoutEvent = nil
local serverMinimapRequestAttempts = 0
local serverMinimapTransfer = nil
local serverMinimapCacheLoaded = false
local serverHDMinimapRequestEvent = nil
local serverHDMinimapTimeoutEvent = nil
local serverHDMinimapTransfer = nil
local serverHDMinimapManifestRequested = false
local serverHDMinimapCacheValid = false
local scheduleServerHDMinimapRequest = nil

local function configuredServerMinimapOpcode()
  local opcode = Services and tonumber(Services.serverMinimapOpcode) or nil
  if not opcode or opcode < 0 or opcode > 255 or opcode ~= math.floor(opcode) then
    return nil
  end
  return opcode
end

local function configuredServerMinimapMaxBytes()
  local size = Services and tonumber(Services.serverMinimapMaxBytes) or
    SERVER_MINIMAP_DEFAULT_MAX_BYTES
  size = math.floor(size or SERVER_MINIMAP_DEFAULT_MAX_BYTES)
  return math.max(22, math.min(size, SERVER_MINIMAP_HARD_MAX_BYTES))
end

local function configuredServerHDMinimapMaxBytes()
  local size = Services and tonumber(Services.serverMinimapHDMaxBytes) or
    SERVER_HD_MINIMAP_DEFAULT_MAX_BYTES
  size = math.floor(size or SERVER_HD_MINIMAP_DEFAULT_MAX_BYTES)
  return math.max(18, math.min(size, SERVER_HD_MINIMAP_HARD_MAX_BYTES))
end

local function sanitizeServerMinimapFilePart(value)
  value = tostring(value or ''):gsub('[^%w%._%-]+', '_')
  value = value:gsub('^_+', ''):gsub('_+$', ''):sub(1, 64)
  return value ~= '' and value:lower() or 'unknown'
end

local function getServerMinimapCachePaths()
  local version = sanitizeServerMinimapFilePart(g_game.getClientVersion())
  local world = sanitizeServerMinimapFilePart(
    g_game.getWorldName and g_game.getWorldName() or nil)
  local prefix = string.format('%s/server_%s_%s', SERVER_MINIMAP_DIRECTORY, version, world)
  return prefix .. '.otmm', prefix .. '.version'
end

local function getServerHDMinimapCachePaths()
  local version = sanitizeServerMinimapFilePart(g_game.getClientVersion())
  local world = sanitizeServerMinimapFilePart(
    g_game.getWorldName and g_game.getWorldName() or nil)
  local prefix = string.format('%s/server_hd_%s_%s',
    SERVER_MINIMAP_DIRECTORY, version, world)
  return prefix .. '.hdr', prefix .. '.version'
end

local function isValidServerMinimapVersion(value)
  return type(value) == 'string' and #value > 0 and
    #value <= SERVER_MINIMAP_MAX_VERSION_BYTES and
    value:match('^[%w%._:%-]+$') ~= nil
end

local function localServerMinimapVersion()
  local mapPath, versionPath = getServerMinimapCachePaths()
  if not g_resources.fileExists(mapPath) or not g_resources.fileExists(versionPath) then
    return ''
  end

  local ok, value = pcall(g_resources.readFileContents, versionPath)
  if not ok or not isValidServerMinimapVersion(value) then
    return ''
  end
  return value
end

local function localServerHDMinimapVersion()
  local mapPath, versionPath = getServerHDMinimapCachePaths()
  if not g_resources.fileExists(mapPath) or
      not g_resources.fileExists(versionPath) then
    return ''
  end

  local ok, value = pcall(g_resources.readFileContents, versionPath)
  if not ok or not isValidServerMinimapVersion(value) then
    return ''
  end
  return value
end

local function cancelServerMinimapRequest()
  if serverMinimapRequestEvent then
    removeEvent(serverMinimapRequestEvent)
    serverMinimapRequestEvent = nil
  end
  serverMinimapRequestAttempts = 0
end

local function cancelServerHDMinimapRequest()
  if serverHDMinimapRequestEvent then
    removeEvent(serverHDMinimapRequestEvent)
    serverHDMinimapRequestEvent = nil
  end
end

local function resetServerMinimapTransfer(reason)
  if serverMinimapTimeoutEvent then
    removeEvent(serverMinimapTimeoutEvent)
    serverMinimapTimeoutEvent = nil
  end
  serverMinimapTransfer = nil
  if reason then
    g_logger.warning('[game_minimap] Server minimap transfer stopped: ' .. tostring(reason))
  end
end

local function armServerMinimapTimeout()
  if serverMinimapTimeoutEvent then
    removeEvent(serverMinimapTimeoutEvent)
  end
  serverMinimapTimeoutEvent = scheduleEvent(function()
    serverMinimapTimeoutEvent = nil
    resetServerMinimapTransfer('timeout')
    if scheduleServerHDMinimapRequest then scheduleServerHDMinimapRequest(100) end
  end, SERVER_MINIMAP_TRANSFER_TIMEOUT)
end

local function resetServerHDMinimapTransfer(reason, preserveTemporary)
  if serverHDMinimapTimeoutEvent then
    removeEvent(serverHDMinimapTimeoutEvent)
    serverHDMinimapTimeoutEvent = nil
  end
  local transfer = serverHDMinimapTransfer
  serverHDMinimapTransfer = nil
  if not preserveTemporary and transfer and transfer.temporaryPath and
      g_resources.fileExists(transfer.temporaryPath) then
    g_resources.deleteFile(transfer.temporaryPath)
  end
  if reason then
    g_logger.warning('[game_minimap] Server HD minimap transfer stopped: ' .. tostring(reason))
  end
end

local function armServerHDMinimapTimeout()
  if serverHDMinimapTimeoutEvent then
    removeEvent(serverHDMinimapTimeoutEvent)
  end
  serverHDMinimapTimeoutEvent = scheduleEvent(function()
    serverHDMinimapTimeoutEvent = nil
    resetServerHDMinimapTransfer('timeout')
  end, SERVER_MINIMAP_TRANSFER_TIMEOUT)
end

local function refreshMinimapAfterServerSync()
  if not minimapWidget or minimapWidget:isDestroyed() then
    return
  end

  if minimapWidget.load then
    minimapWidget:load()
  end
  local player = g_game.getLocalPlayer()
  if player then
    local position = player:getPosition()
    if position then
      minimapWidget:setCameraPosition(position)
      minimapWidget:setCrossPosition(position)
    end
  end
end

-- The player map is loaded first and the read-only server cache is applied last.
-- This makes a newly published server snapshot authoritative for overlapping
-- blocks while retaining player-only regions that the snapshot does not contain.
local function reloadMinimapWithServerCache(serverMapPath)
  g_minimap.clean()

  local playerLoaded = false
  if g_resources.fileExists(minimapFile) then
    playerLoaded = g_minimap.loadOtmm(minimapFile)
  end

  local serverLoaded = false
  if serverMapPath and g_resources.fileExists(serverMapPath) then
    serverLoaded = g_minimap.loadOtmm(serverMapPath)
  end

  MinimapLoader.otmmLoaded = serverLoaded or playerLoaded
  MinimapLoader.loaded = true
  refreshMinimapAfterServerSync()
  return serverLoaded
end

local function loadCachedServerMinimap()
  local mapPath, versionPath = getServerMinimapCachePaths()
  if not g_resources.fileExists(mapPath) then
    serverMinimapCacheLoaded = false
    return false
  end

  serverMinimapCacheLoaded = reloadMinimapWithServerCache(mapPath)
  if not serverMinimapCacheLoaded then
    g_resources.deleteFile(versionPath)
    g_logger.warning('[game_minimap] Ignoring an invalid cached server minimap.')
  end
  return serverMinimapCacheLoaded
end

local function installServerMinimap(content, version)
  local mapPath, versionPath = getServerMinimapCachePaths()
  local backupPath = mapPath .. '.bak'
  pcall(g_resources.makeDir, SERVER_MINIMAP_DIRECTORY)

  if g_resources.fileExists(backupPath) then
    g_resources.deleteFile(backupPath)
  end

  local hadPrevious = g_resources.fileExists(mapPath)
  if hadPrevious and not g_resources.copyFile(mapPath, backupPath) then
    return false, 'unable to back up the current server minimap'
  end

  if not g_resources.writeFileContents(mapPath, content) then
    if hadPrevious then g_resources.deleteFile(backupPath) end
    return false, 'unable to write the server minimap cache'
  end

  if not reloadMinimapWithServerCache(mapPath) then
    if hadPrevious then
      g_resources.copyFile(backupPath, mapPath)
    else
      g_resources.deleteFile(mapPath)
    end
    reloadMinimapWithServerCache(hadPrevious and mapPath or nil)
    g_resources.deleteFile(backupPath)
    return false, 'the received OTMM file could not be loaded'
  end

  serverMinimapCacheLoaded = true
  if not g_resources.writeFileContents(versionPath, version) then
    g_logger.warning('[game_minimap] The server minimap was installed, but its cache version could not be saved.')
  end
  g_resources.deleteFile(backupPath)
  return true
end

local function loadCachedServerHDMinimap()
  serverHDMinimapCacheValid = false
  activeHDBaseFile = nil
  local mapPath, versionPath = getServerHDMinimapCachePaths()
  if not g_resources.fileExists(mapPath) then
    return false
  end

  if g_minimap.hasHDBase() then g_minimap.closeHDBase() end

  local opened = g_minimap.openHDBase(mapPath)
  if not opened then
    g_resources.deleteFile(versionPath)
    g_logger.warning('[game_minimap] Ignoring a cached HD base that is not a valid raster archive.')
    return false
  end

  activeHDBaseFile = mapPath
  serverHDMinimapCacheValid = true
  if not isHDEnabled() then
    g_minimap.closeHDBase()
  end
  return true
end

local function installServerHDMinimap(sourcePath, version)
  local mapPath, versionPath = getServerHDMinimapCachePaths()
  local backupPath = mapPath .. '.bak'
  pcall(g_resources.makeDir, SERVER_MINIMAP_DIRECTORY)

  if g_minimap.hasHDBase() then
    g_minimap.closeHDBase()
  end
  if g_resources.fileExists(backupPath) then
    g_resources.deleteFile(backupPath)
  end

  local hadPrevious = g_resources.fileExists(mapPath)
  if hadPrevious and not g_resources.copyFile(mapPath, backupPath) then
    return false, 'unable to back up the current HD minimap'
  end

  if not g_resources.copyFile(sourcePath, mapPath) then
    if hadPrevious then g_resources.deleteFile(backupPath) end
    g_resources.deleteFile(sourcePath)
    return false, 'unable to promote the streamed HD minimap cache'
  end

  if not g_minimap.openHDBase(mapPath) then
    g_resources.deleteFile(mapPath)
    if hadPrevious then
      g_resources.copyFile(backupPath, mapPath)
      if isHDEnabled() then g_minimap.openHDBase(mapPath) end
    end
    g_resources.deleteFile(backupPath)
    g_resources.deleteFile(sourcePath)
    return false, 'the received HD baseline could not be opened'
  end

  activeHDBaseFile = mapPath
  serverHDMinimapCacheValid = true
  if not isHDEnabled() then
    g_minimap.closeHDBase()
  end
  if not g_resources.writeFileContents(versionPath, version) then
    g_logger.warning('[game_minimap] The server HD minimap was installed, but its cache version could not be saved.')
  end
  g_resources.deleteFile(backupPath)
  g_resources.deleteFile(sourcePath)
  return true
end

local function completeServerMinimapTransfer()
  local transfer = serverMinimapTransfer
  resetServerMinimapTransfer()
  if not transfer then
    return
  end

  if transfer.received ~= transfer.expectedSize then
    g_logger.warning(string.format(
      '[game_minimap] Rejected server minimap: expected %d bytes, received %d.',
      transfer.expectedSize, transfer.received))
    return
  end

  local content = table.concat(transfer.parts)
  if #content ~= transfer.expectedSize or #content < 22 or
      content:sub(1, 4) ~= 'OTMM' or content:byte(7) ~= 1 or content:byte(8) ~= 0 then
    g_logger.warning('[game_minimap] Rejected server minimap: invalid or unsupported OTMM payload.')
    return
  end

  local crcHex = g_crypt.crc32(content, false)
  local crc = tonumber(crcHex, 16)
  if transfer.checksum and crc ~= transfer.checksum then
    g_logger.warning(string.format(
      '[game_minimap] Rejected server minimap: CRC mismatch (expected %u, received %s).',
      transfer.checksum, tostring(crc)))
    return
  end

  local ok, reason = installServerMinimap(content, transfer.version)
  if not ok then
    g_logger.warning('[game_minimap] Failed to install server minimap: ' .. tostring(reason))
    return
  end

  g_logger.info(string.format('[game_minimap] Server minimap %s installed (%d bytes).',
    transfer.version, transfer.expectedSize))
  if scheduleServerHDMinimapRequest then
    scheduleServerHDMinimapRequest(100)
  end
end

local function requestServerMinimapChunk(protocol, transfer)
  protocol:sendExtendedOpcode(serverMinimapOpcode,
    string.format('chunk:%s:%d', transfer.version, transfer.nextChunk))
  armServerMinimapTimeout()
end

local function completeServerHDMinimapTransfer()
  local transfer = serverHDMinimapTransfer
  resetServerHDMinimapTransfer(nil, true)
  if not transfer then
    return
  end

  if transfer.received ~= transfer.expectedSize then
    g_logger.warning(string.format(
      '[game_minimap] Rejected server HD minimap: expected %d bytes, received %d.',
      transfer.expectedSize, transfer.received))
    g_resources.deleteFile(transfer.temporaryPath)
    return
  end

  if not g_resources.validateFileContents(
      transfer.temporaryPath, transfer.expectedSize, transfer.checksum) then
    g_logger.warning('[game_minimap] Rejected server HD minimap: streamed size or CRC mismatch.')
    g_resources.deleteFile(transfer.temporaryPath)
    return
  end

  local ok, reason = installServerHDMinimap(transfer.temporaryPath, transfer.version)
  if not ok then
    g_logger.warning('[game_minimap] Failed to install server HD minimap: ' .. tostring(reason))
    return
  end

  g_logger.info(string.format('[game_minimap] Server HD minimap %s installed (%d bytes).',
    transfer.version, transfer.expectedSize))
end

local function requestServerHDMinimapChunk(protocol, transfer)
  protocol:sendExtendedOpcode(serverMinimapOpcode,
    string.format('hd-chunk:%s:%d', transfer.version, transfer.nextChunk))
  armServerHDMinimapTimeout()
end

local function onServerHDMinimapOpcode(protocol, buffer)
  if buffer:sub(1, 1) == '{' then
    local ok, payload = pcall(json.decode, buffer)
    if not ok or type(payload) ~= 'table' or payload.asset ~= 'hd' then
      resetServerHDMinimapTransfer('invalid HD manifest response')
      return
    end

    if payload.type == 'error' then
      resetServerHDMinimapTransfer(payload.message or 'server rejected the HD minimap request')
      return
    end
    if payload.type ~= 'manifest' then
      resetServerHDMinimapTransfer('unexpected server HD minimap response')
      return
    end

    resetServerHDMinimapTransfer()
    local version = payload.version
    local expectedSize = tonumber(payload.size)
    local checksum = tonumber(payload.checksum)
    local chunkSize = tonumber(payload.chunkSize)
    local expectedChunks = tonumber(payload.chunks)
    local window = tonumber(payload.window) or 1
    if not isValidServerMinimapVersion(version) or not expectedSize or
        expectedSize ~= math.floor(expectedSize) or expectedSize < 18 or
        expectedSize > configuredServerHDMinimapMaxBytes() or not checksum or
        checksum ~= math.floor(checksum) or checksum < 0 or checksum > 4294967295 or
        not chunkSize or chunkSize ~= math.floor(chunkSize) or chunkSize < 1 or
        chunkSize > 65535 or not expectedChunks or
        expectedChunks ~= math.floor(expectedChunks) or expectedChunks < 1 or
        window ~= math.floor(window) or window < 1 or window > 32 or
        expectedChunks ~= math.ceil(expectedSize / chunkSize) or
        payload.encoding ~= 'base64' then
      resetServerHDMinimapTransfer('invalid HD minimap manifest')
      return
    end

    if payload.unchanged == true and version == localServerHDMinimapVersion() and
        (serverHDMinimapCacheValid or loadCachedServerHDMinimap()) then
      g_logger.info('[game_minimap] Cached server HD minimap is current.')
      return
    end

    if payload.unchanged == true then
      resetServerHDMinimapTransfer('server reported an unavailable local HD cache')
      return
    end

    if g_resources.fileExists(HD_BASE_TRANSFER_FILE) then
      g_resources.deleteFile(HD_BASE_TRANSFER_FILE)
    end
    serverHDMinimapTransfer = {
      version = version,
      expectedSize = expectedSize,
      checksum = checksum,
      chunkSize = chunkSize,
      expectedChunks = expectedChunks,
      window = window,
      nextChunk = 0,
      received = 0,
      temporaryPath = HD_BASE_TRANSFER_FILE
    }
    requestServerHDMinimapChunk(protocol, serverHDMinimapTransfer)
    return
  end

  local version, indexText, countText, dataStart =
    buffer:match('^hd%-chunk:([%w%._%-]+):(%d+):(%d+):()')
  local transfer = serverHDMinimapTransfer
  local index = tonumber(indexText)
  local chunkCount = tonumber(countText)
  if not transfer or not dataStart or version ~= transfer.version or
      index ~= transfer.nextChunk or chunkCount ~= transfer.expectedChunks then
    resetServerHDMinimapTransfer('unexpected HD minimap chunk')
    return
  end

  local encoded = buffer:sub(dataStart)
  local decodeOk, data = pcall(g_crypt.base64Decode, encoded)
  local expectedLength = math.min(transfer.chunkSize,
    transfer.expectedSize - (index * transfer.chunkSize))
  if not decodeOk or type(data) ~= 'string' or expectedLength < 1 or
      #data ~= expectedLength or
      transfer.received + #data > configuredServerHDMinimapMaxBytes() then
    resetServerHDMinimapTransfer('invalid HD minimap chunk size')
    return
  end

  local written = index == 0 and
      g_resources.writeFileContents(transfer.temporaryPath, data) or
      g_resources.appendFileContents(transfer.temporaryPath, data)
  if not written then
    resetServerHDMinimapTransfer('unable to stream the HD minimap chunk to disk')
    return
  end
  transfer.received = transfer.received + #data
  transfer.nextChunk = transfer.nextChunk + 1
  if transfer.nextChunk == transfer.expectedChunks then
    completeServerHDMinimapTransfer()
  elseif transfer.nextChunk % transfer.window == 0 then
    requestServerHDMinimapChunk(protocol, transfer)
  end
end

local function onServerMinimapOpcode(protocol, opcode, buffer)
  if opcode ~= serverMinimapOpcode or type(buffer) ~= 'string' or #buffer == 0 then
    return
  end

  if buffer:sub(1, 9) == 'hd-chunk:' then
    onServerHDMinimapOpcode(protocol, buffer)
    return
  end
  if buffer:sub(1, 1) == '{' then
    local decoded, payload = pcall(json.decode, buffer)
    if decoded and type(payload) == 'table' and payload.asset == 'hd' then
      onServerHDMinimapOpcode(protocol, buffer)
      return
    end
  end

  if buffer:sub(1, 1) == '{' then
    local ok, payload = pcall(json.decode, buffer)
    if not ok or type(payload) ~= 'table' then
      resetServerMinimapTransfer('invalid manifest response')
      return
    end

    if payload.type == 'error' then
      resetServerMinimapTransfer(payload.message or 'server rejected the minimap request')
      if scheduleServerHDMinimapRequest then scheduleServerHDMinimapRequest(100) end
      return
    end

    if payload.type ~= 'manifest' then
      resetServerMinimapTransfer('unexpected server minimap response')
      return
    end

    resetServerMinimapTransfer()
    local version = payload.version
    local expectedSize = tonumber(payload.size)
    local checksum = tonumber(payload.checksum)
    local chunkSize = tonumber(payload.chunkSize)
    local expectedChunks = tonumber(payload.chunks)
    if not isValidServerMinimapVersion(version) or not expectedSize or
        expectedSize ~= math.floor(expectedSize) or expectedSize < 22 or
        expectedSize > configuredServerMinimapMaxBytes() or not checksum or
        checksum ~= math.floor(checksum) or checksum < 0 or checksum > 4294967295 or
        not chunkSize or chunkSize ~= math.floor(chunkSize) or chunkSize < 1 or
        chunkSize > 65535 or not expectedChunks or
        expectedChunks ~= math.floor(expectedChunks) or expectedChunks < 1 or
        expectedChunks ~= math.ceil(expectedSize / chunkSize) or
        payload.encoding ~= 'base64' then
      resetServerMinimapTransfer('invalid minimap manifest')
      return
    end

    if payload.unchanged == true and version == localServerMinimapVersion() and
        (serverMinimapCacheLoaded or loadCachedServerMinimap()) then
      g_logger.info('[game_minimap] Cached server minimap is current.')
      if scheduleServerHDMinimapRequest then scheduleServerHDMinimapRequest(100) end
      return
    end

    if payload.unchanged == true then
      resetServerMinimapTransfer('server reported an unavailable local cache')
      if scheduleServerHDMinimapRequest then scheduleServerHDMinimapRequest(100) end
      return
    end

    serverMinimapTransfer = {
      version = version,
      expectedSize = expectedSize,
      checksum = checksum,
      chunkSize = chunkSize,
      expectedChunks = expectedChunks,
      nextChunk = 0,
      received = 0,
      parts = {}
    }
    requestServerMinimapChunk(protocol, serverMinimapTransfer)
    return
  end

  local version, indexText, countText, dataStart =
    buffer:match('^chunk:([%w%._%-]+):(%d+):(%d+):()')
  local transfer = serverMinimapTransfer
  local index = tonumber(indexText)
  local chunkCount = tonumber(countText)
  if not transfer or not dataStart or version ~= transfer.version or
      index ~= transfer.nextChunk or chunkCount ~= transfer.expectedChunks then
    resetServerMinimapTransfer('unexpected minimap chunk')
    return
  end

  local encoded = buffer:sub(dataStart)
  local decodeOk, data = pcall(g_crypt.base64Decode, encoded)
  local expectedLength = math.min(transfer.chunkSize,
    transfer.expectedSize - (index * transfer.chunkSize))
  if not decodeOk or type(data) ~= 'string' or expectedLength < 1 or
      #data ~= expectedLength or
      transfer.received + #data > configuredServerMinimapMaxBytes() then
    resetServerMinimapTransfer('invalid minimap chunk size')
    return
  end

  transfer.parts[#transfer.parts + 1] = data
  transfer.received = transfer.received + #data
  transfer.nextChunk = transfer.nextChunk + 1
  if transfer.nextChunk == transfer.expectedChunks then
    completeServerMinimapTransfer()
  else
    requestServerMinimapChunk(protocol, transfer)
  end
end

local requestServerMinimap
requestServerMinimap = function()
  serverMinimapRequestEvent = nil
  if not serverMinimapRegistered or not g_game.isOnline() then
    return
  end

  local protocol = g_game.getProtocolGame()
  if not protocol then
    serverMinimapRequestAttempts = serverMinimapRequestAttempts + 1
    if serverMinimapRequestAttempts < SERVER_MINIMAP_REQUEST_RETRIES then
      serverMinimapRequestEvent = scheduleEvent(requestServerMinimap, 500)
    else
      g_logger.warning('[game_minimap] Server minimap request stopped: protocol unavailable.')
    end
    return
  end

  serverMinimapRequestAttempts = 0
  local version = localServerMinimapVersion()
  protocol:sendExtendedOpcode(serverMinimapOpcode, 'manifest:' .. version)
end

local function scheduleServerMinimapRequest()
  cancelServerMinimapRequest()
  serverMinimapRequestEvent = scheduleEvent(requestServerMinimap, 1000)
end

local function requestServerHDMinimap()
  serverHDMinimapRequestEvent = nil
  if serverHDMinimapManifestRequested or not serverMinimapRegistered or
      not g_game.isOnline() then
    return
  end

  local protocol = g_game.getProtocolGame()
  if not protocol then
    serverHDMinimapRequestEvent = scheduleEvent(requestServerHDMinimap, 500)
    return
  end

  serverHDMinimapManifestRequested = true
  protocol:sendExtendedOpcode(serverMinimapOpcode,
    'hd-manifest:' .. localServerHDMinimapVersion())
end

scheduleServerHDMinimapRequest = function(delay)
  cancelServerHDMinimapRequest()
  if serverHDMinimapManifestRequested then
    return
  end
  serverHDMinimapRequestEvent = scheduleEvent(requestServerHDMinimap, delay or 100)
end

local expansion = {
  parent = nil,
  index = nil,
  direction = nil,
  collapsedWidth = nil,
  fixedEdge = nil,
  side = nil,
  baseBoundary = nil,
  reservation = nil,
  verticalExpanded = false,
  collapsedHeight = nil,
  placeholders = {}
}

local expansionRestoreEvent = nil
local expansionRestoreRetries = 8
local expansionRestoreDelay = 250
-- Set while a saved "detached" layout has not been reapplied yet, so an automatic save
-- cannot overwrite the user's preference with the collapsed state we failed to leave.
local expansionRestorePending = false
local saveExpansionConfig
local fitVerticalExpansionToAvailable

local function isWidgetAlive(widget)
  return widget and not widget:isDestroyed()
end

local function getGameRootPanel()
  if m_interface and m_interface.getRootPanel then
    return m_interface.getRootPanel()
  end
  return nil
end

local function releaseExpansionSpace()
  if isWidgetAlive(expansion.reservation) and m_interface and
      m_interface.releaseMinimapExpansionSpace then
    m_interface.releaseMinimapExpansionSpace(expansion.reservation)
  end
  expansion.reservation = nil
end

local function getGameAreaBoundary(side)
  if not m_interface or not m_interface.getMapPanel then
    return nil
  end

  local mapPanel = m_interface.getMapPanel()
  if not isWidgetAlive(mapPanel) then
    return nil
  end

  if side == 'right' then
    return mapPanel:getX() + mapPanel:getWidth()
  end
  return mapPanel:getX()
end

local function updateExpansionSpace()
  if not expansion.parent or not minimapWindow or not expansion.baseBoundary or
      not m_interface or not m_interface.reserveMinimapExpansionSpace then
    return
  end

  local required
  if expansion.side == 'right' then
    required = expansion.baseBoundary - minimapWindow:getX()
  else
    required = minimapWindow:getX() + minimapWindow:getWidth() - expansion.baseBoundary
  end
  required = math.max(0, math.floor(required + 0.5))

  if required > 0 then
    expansion.reservation = m_interface.reserveMinimapExpansionSpace(
      expansion.side, required, expansion.reservation)
  else
    releaseExpansionSpace()
  end
end

local function isSidebarPanel(widget)
  return isWidgetAlive(widget) and widget:getClassName() == 'UIMiniWindowContainer'
end

local function getExpansionDirection(panel)
  local rootPanel = getGameRootPanel()
  if not rootPanel or not panel then
    return -1
  end

  local panelCenter = panel:getX() + panel:getWidth() / 2
  local rootCenter = rootPanel:getX() + rootPanel:getWidth() / 2
  return panelCenter >= rootCenter and -1 or 1
end

local function configureResizeBorder(direction)
  if not minimapWindow then
    return
  end

  local resizeBorder = minimapWindow:getChildById('resizeBorder')
  if not resizeBorder then
    return
  end

  direction = direction or expansion.direction or getExpansionDirection(minimapWindow:getParent())
  resizeBorder:breakAnchors()
  resizeBorder:addAnchor(AnchorTop, 'parent', AnchorTop)
  resizeBorder:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  if direction < 0 then
    resizeBorder:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  else
    resizeBorder:addAnchor(AnchorRight, 'parent', AnchorRight)
  end
end

local function updateExpandButton()
  if not minimapWindow then
    return
  end

  local button = minimapWindow:getChildById('expandMap')
  if not button then
    return
  end

  local expanded = expansion.parent ~= nil
  local direction = expansion.direction or getExpansionDirection(minimapWindow:getParent())
  local pointsLeft = (not expanded and direction < 0) or (expanded and direction > 0)
  button:setImageSource(pointsLeft and '/images/game/actionbar/arrow-left' or
    '/images/game/actionbar/arrow-right')
  button:setTooltip(tr(expanded and 'Collapse minimap' or 'Expand minimap'))
end

local function updateVerticalExpandButton()
  if not minimapWindow then
    return
  end

  local button = minimapWindow:getChildById('expandMapVertical')
  if not button then
    return
  end

  button:setImageSource(expansion.verticalExpanded and
    '/images/game/actionbar/arrow-up' or
    '/images/game/actionbar/arrow-down')
  button:setTooltip(tr(expansion.verticalExpanded and
    'Collapse minimap upward' or 'Expand minimap downward'))
end

-- The sidebar manager may save before the minimap receives onGameEnd. Let the placeholder
-- in the original panel stand in for the detached minimap so its sidebar and order are not
-- lost between sessions.
local function makePlaceholderStandInForMinimap(placeholder)
  placeholder.getType = function() return 'miniMap' end
  placeholder.isOpened = function() return minimapWindow:isOpened() end
  placeholder.isLocked = function() return minimapWindow:isLocked() end
  placeholder.minimized = minimapWindow.minimized
end

local function createPlaceholder(panel, index)
  if not isSidebarPanel(panel) then
    return nil
  end

  local current = expansion.placeholders[panel]
  if isWidgetAlive(current) then
    current:setHeight(minimapWindow:getHeight())
    if panel == expansion.parent then
      makePlaceholderStandInForMinimap(current)
    end
    return current
  end

  local placeholder = g_ui.createWidget('UIWidget')
  placeholder:setId('minimapExpansionPlaceholder_' .. panel:getId())
  placeholder:setHeight(minimapWindow:getHeight())
  placeholder:setWidth(panel:getWidth() - panel:getPaddingLeft() - panel:getPaddingRight())
  placeholder.save = true
  placeholder.close = function() end
  placeholder.saveParentIndex = function() end
  placeholder.saveParentPosition = function() end
  if panel == expansion.parent then
    makePlaceholderStandInForMinimap(placeholder)
  end

  index = math.max(1, math.min(index or 1, panel:getChildCount() + 1))
  panel:insertChild(index, placeholder)
  expansion.placeholders[panel] = placeholder
  return placeholder
end

local function destroyPlaceholder(panel)
  local placeholder = expansion.placeholders[panel]
  if isWidgetAlive(placeholder) then
    placeholder:destroy()
  end
  expansion.placeholders[panel] = nil
end

local function clearPlaceholders()
  local panels = {}
  for panel in pairs(expansion.placeholders) do
    table.insert(panels, panel)
  end
  for _, panel in ipairs(panels) do
    destroyPlaceholder(panel)
  end
end

local function syncExpansionPlaceholders()
  if not expansion.parent or not minimapWindow then
    return
  end

  createPlaceholder(expansion.parent, expansion.index)

  local sidebarGroup = expansion.parent:getParent()
  if not isWidgetAlive(sidebarGroup) then
    return
  end

  local minimapLeft = minimapWindow:getX()
  local minimapRight = minimapLeft + minimapWindow:getWidth()
  local coveredPanels = {[expansion.parent] = true}

  for _, panel in ipairs(sidebarGroup:getChildren()) do
    if panel ~= expansion.parent and isSidebarPanel(panel) and panel:isVisible() then
      local panelLeft = panel:getX()
      local panelRight = panelLeft + panel:getWidth()
      if minimapLeft < panelRight and minimapRight > panelLeft then
        createPlaceholder(panel, expansion.index)
        coveredPanels[panel] = true
      end
    end
  end

  local stalePanels = {}
  for panel in pairs(expansion.placeholders) do
    if not coveredPanels[panel] then
      table.insert(stalePanels, panel)
    end
  end
  for _, panel in ipairs(stalePanels) do
    destroyPlaceholder(panel)
  end
end

local function getPanelHeightLimit(panel, standIn)
  if not isSidebarPanel(panel) then
    return nil
  end

  local occupiedHeight = isWidgetAlive(standIn) and standIn:getHeight() or
    minimapWindow:getHeight()
  return occupiedHeight + panel:getEmptySpaceHeight()
end

local function getMaximumVerticalHeight()
  if not minimapWindow then
    return 0
  end

  local maximum = math.huge
  local rootPanel = getGameRootPanel()
  if isWidgetAlive(rootPanel) then
    maximum = math.min(maximum,
      rootPanel:getY() + rootPanel:getHeight() - minimapWindow:getY())
  end

  if expansion.parent then
    for panel, placeholder in pairs(expansion.placeholders) do
      local panelLimit = getPanelHeightLimit(panel, placeholder)
      if panelLimit then
        maximum = math.min(maximum, panelLimit)
      end
    end
  else
    local parent = minimapWindow:getParent()
    local panelLimit = getPanelHeightLimit(parent, minimapWindow)
    if panelLimit then
      maximum = math.min(maximum, panelLimit)
    end
  end

  if maximum == math.huge then
    maximum = minimapWindow:getHeight()
  end

  -- Never squeeze below the collapsed height: a 1px window would take the collapse
  -- button away with it and leave no way back.
  local floor = expansion.collapsedHeight or minimapWindow:getHeight()
  return math.max(math.floor(floor), math.floor(maximum))
end

fitVerticalExpansionToAvailable = function()
  if not expansion.verticalExpanded or not minimapWindow then
    return
  end

  local maximum = getMaximumVerticalHeight()
  if minimapWindow:getHeight() > maximum then
    minimapWindow:setHeight(maximum)
    if expansion.parent then
      syncExpansionPlaceholders()
    end
  end
end

local function detachMinimap()
  if expansion.parent or not minimapWindow or fullmapView then
    return expansion.parent ~= nil
  end

  local parent = minimapWindow:getParent()
  local rootPanel = getGameRootPanel()
  if not isSidebarPanel(parent) or not rootPanel then
    return false
  end

  releaseExpansionSpace()
  local position = minimapWindow:getPosition()
  local size = minimapWindow:getSize()
  expansion.parent = parent
  expansion.index = parent:getChildIndex(minimapWindow)
  expansion.direction = getExpansionDirection(parent)
  expansion.collapsedWidth = size.width
  expansion.fixedEdge = expansion.direction < 0 and position.x + size.width or position.x
  expansion.side = expansion.direction < 0 and 'right' or 'left'
  expansion.baseBoundary = getGameAreaBoundary(expansion.side)

  createPlaceholder(parent, expansion.index)
  minimapWindow:setParent(rootPanel)
  minimapWindow:setPosition(position)
  minimapWindow:setSize(size)
  minimapWindow:raise()
  configureResizeBorder(expansion.direction)
  updateExpandButton()
  return true
end

local function setExpandedWidth(width)
  if not expansion.parent or not minimapWindow then
    return
  end

  local rootPanel = getGameRootPanel()
  if not rootPanel then
    return
  end

  local rootLeft = rootPanel:getX()
  local rootRight = rootLeft + rootPanel:getWidth()
  local minimum = expansion.collapsedWidth or 120
  local maximum
  if expansion.direction < 0 then
    maximum = expansion.fixedEdge - rootLeft
  else
    maximum = rootRight - expansion.fixedEdge
  end

  width = math.max(minimum, math.min(width, maximum))
  if expansion.direction < 0 then
    minimapWindow:setX(expansion.fixedEdge - width)
  else
    minimapWindow:setX(expansion.fixedEdge)
  end
  minimapWindow:setWidth(width)
  updateExpansionSpace()
  syncExpansionPlaceholders()
  fitVerticalExpansionToAvailable()
end

local function restoreMinimap(saveConfig)
  if not expansion.parent or not minimapWindow then
    return false
  end

  local parent = expansion.parent
  local direction = expansion.direction
  local placeholder = expansion.placeholders[parent]
  local index = expansion.index or 1
  if isWidgetAlive(placeholder) then
    index = parent:getChildIndex(placeholder)
  end

  if isSidebarPanel(parent) then
    minimapWindow:setParent(parent)
    parent:moveChildToIndex(minimapWindow, math.max(1, math.min(index, parent:getChildCount())))
    minimapWindow:setWidth(parent:getWidth() - parent:getPaddingLeft() - parent:getPaddingRight())
  end

  clearPlaceholders()
  releaseExpansionSpace()
  expansion.parent = nil
  expansion.index = nil
  expansion.direction = nil
  expansion.collapsedWidth = nil
  expansion.fixedEdge = nil
  expansion.side = nil
  expansion.baseBoundary = nil

  configureResizeBorder(direction or getExpansionDirection(minimapWindow:getParent()))
  updateExpandButton()

  if saveConfig ~= false and saveExpansionConfig then
    saveExpansionConfig(false)
  end
  return true
end

saveExpansionConfig = function(detached)
  local player = g_game.getLocalPlayer()
  if not player or not minimapWindow then
    return
  end

  if detached == nil then
    detached = expansion.parent ~= nil
  end

  -- A restore that never managed to run must not be recorded as "the user collapsed it".
  if not detached and expansionRestorePending then
    return
  end

  local parent = detached and expansion.parent or minimapWindow:getParent()
  local settings = {
    detached = detached,
    width = minimapWindow:getWidth(),
    height = minimapWindow:getHeight(),
    verticalExpanded = expansion.verticalExpanded,
    collapsedHeight = expansion.collapsedHeight,
    parentId = parent and parent:getId() or nil,
    direction = expansion.direction
  }
  g_settings.setNode(EXPANSION_SETTINGS_PREFIX .. player:getName(), settings)
end

local function scheduleExpansionRestore(settings, retries)
  if expansionRestoreEvent then
    removeEvent(expansionRestoreEvent)
    expansionRestoreEvent = nil
  end

  if not settings then
    local player = g_game.getLocalPlayer()
    if not player then
      return
    end

    settings = g_settings.getNode(EXPANSION_SETTINGS_PREFIX .. player:getName())
    if not settings or (not settings.detached and not settings.verticalExpanded) then
      expansionRestorePending = false
      updateExpandButton()
      updateVerticalExpandButton()
      return
    end

    expansionRestorePending = true
    retries = expansionRestoreRetries
  end

  expansionRestoreEvent = scheduleEvent(function()
    expansionRestoreEvent = nil
    if not minimapWindow or not g_game.isOnline() then
      -- Nothing else will retry, so stop shielding the saved state or a later manual
      -- collapse could never be persisted.
      expansionRestorePending = false
      return
    end

    if not isSidebarPanel(minimapWindow:getParent()) and settings.parentId then
      local savedParent = rootWidget:recursiveGetChildById(settings.parentId)
      if isSidebarPanel(savedParent) then
        minimapWindow:setParent(savedParent)
      end
    end

    local needsHorizontalRestore = settings.detached == true
    local needsVerticalRestore = settings.verticalExpanded == true
    local parentReady = isSidebarPanel(minimapWindow:getParent())

    -- The sidebar is built by another module and may not be there yet; keep trying for a
    -- bounded number of ticks instead of silently dropping the saved layout.
    if not parentReady or (needsHorizontalRestore and not detachMinimap()) then
      if retries > 0 then
        scheduleExpansionRestore(settings, retries - 1)
      else
        expansionRestorePending = false
      end
      return
    end

    expansion.verticalExpanded = needsVerticalRestore
    if needsVerticalRestore then
      local collapsedHeight = tonumber(settings.collapsedHeight)
      if not collapsedHeight or collapsedHeight < 1 then
        collapsedHeight = math.min(minimapWindow:getHeight(),
          tonumber(settings.height) or minimapWindow:getHeight())
      end
      expansion.collapsedHeight = collapsedHeight
    else
      expansion.collapsedHeight = nil
    end

    if settings.height then
      local height = math.max(1, tonumber(settings.height) or minimapWindow:getHeight())
      if needsVerticalRestore then
        height = math.min(height, getMaximumVerticalHeight())
      end
      minimapWindow:setHeight(height)
    end
    if needsHorizontalRestore then
      setExpandedWidth(settings.width or EXPANDED_WIDTH)
    end
    fitVerticalExpansionToAvailable()
    updateVerticalExpandButton()
    expansionRestorePending = false
    saveExpansionConfig(needsHorizontalRestore)
  end, expansionRestoreDelay)
end

function toggleExpanded()
  if fullmapView or not minimapWindow then
    return
  end

  if expansion.parent then
    restoreMinimap(true)
    return
  end

  if detachMinimap() then
    local targetWidth = math.max(EXPANDED_WIDTH, (expansion.collapsedWidth or 178) * 2)
    setExpandedWidth(targetWidth)
    saveExpansionConfig(true)
  end
end

function toggleVerticalExpanded()
  if fullmapView or not minimapWindow then
    return
  end

  if expansion.verticalExpanded then
    local collapsedHeight = expansion.collapsedHeight or minimapWindow:getHeight()
    expansion.verticalExpanded = false
    expansion.collapsedHeight = nil
    minimapWindow:setHeight(math.max(1, collapsedHeight))
  else
    local collapsedHeight = minimapWindow:getHeight()
    local targetHeight = math.max(EXPANDED_HEIGHT, collapsedHeight * 2)
    targetHeight = math.min(targetHeight, getMaximumVerticalHeight())
    if targetHeight <= collapsedHeight then
      updateVerticalExpandButton()
      return
    end

    expansion.collapsedHeight = collapsedHeight
    expansion.verticalExpanded = true
    minimapWindow:setHeight(targetHeight)
  end

  if expansion.parent then
    syncExpansionPlaceholders()
  end
  updateVerticalExpandButton()
  saveExpansionConfig(expansion.parent ~= nil)
end

function isExpanded()
  return expansion.parent ~= nil
end

function isVerticalExpanded()
  return expansion.verticalExpanded
end

function toggleFullMap()
  if not minimapWidget or not minimapWindow then
    return
  end

  if not fullmapView then
    -- Without a root panel the widget would be reparented to nil while the window is
    -- already hidden, leaving no minimap at all and no way back.
    local rootPanel = getGameRootPanel()
    if not rootPanel then
      return
    end

    oldZoom = minimapWidget:getZoom()
    oldPos = minimapWidget:getCameraPosition()
    fullmapView = true
    minimapWindow:hide()
    minimapWidget:setParent(rootPanel)
    minimapWidget:fill('parent')
    minimapWidget:setAlternativeWidgetsVisible(true)
  else
    fullmapView = false
    minimapWidget:setParent(minimapWindow)
    minimapWidget:fill('parent')
    minimapWindow:show()
    minimapWidget:setAlternativeWidgetsVisible(false)
    if oldZoom then minimapWidget:setZoom(oldZoom) end
    if oldPos then minimapWidget:setCameraPosition(oldPos) end
  end
end

local function getDownloadMapButton()
  if not minimapWindow or minimapWindow:isDestroyed() then
    return nil
  end
  return minimapWindow:getChildById('downloadMapButton')
end

local function setDownloadMapButtonState(downloading)
  local button = getDownloadMapButton()
  if not button or button:isDestroyed() then
    return
  end

  button:setEnabled(not downloading)
  button:setText(tr(downloading and 'Downloading...' or 'Download Map'))
end

local function displayMapDownloadFailure(details)
  g_logger.error('[game_minimap] Failed to download full map: ' .. tostring(details))
  if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
    modules.game_textmessage.displayFailureMessage(tr('Failed to download the map.'))
  end
end

-- Snapshots the installed map so a bad OTMM can be rolled back. Returns false when the
-- snapshot failed, in which case the caller must leave the current map untouched.
-- A nil snapshot means there was no map installed yet.
local function backupMinimapFile()
  -- A snapshot left behind by an interrupted run must not be mistaken for this one's.
  if g_resources.fileExists(minimapBackupFile) then
    g_resources.deleteFile(minimapBackupFile)
  end

  if not g_resources.fileExists(minimapFile) then
    return true, nil
  end

  if g_resources.copyFile then
    if not g_resources.copyFile(minimapFile, minimapBackupFile) then
      return false, nil
    end
    return true, { file = minimapBackupFile }
  end

  -- Binary without the native copy: fall back to holding the old map in memory.
  local ok, contents = pcall(g_resources.readFileContents, minimapFile)
  if not ok or type(contents) ~= 'string' then
    return false, nil
  end
  return true, { contents = contents }
end

local function rollbackMinimapFile(backup)
  if not backup then
    g_resources.deleteFile(minimapFile)
    return false
  end

  if backup.file then
    return g_resources.copyFile(backup.file, minimapFile) and true or false
  end
  return g_resources.writeFileContents(minimapFile, backup.contents) and true or false
end

local function discardMinimapBackup(backup)
  if backup and backup.file then
    g_resources.deleteFile(backup.file)
  end
end

function downloadFullMap()
  local url = Services and Services.minimap or nil
  if type(url) ~= 'string' or url == '' then
    displayMapDownloadFailure('Services.minimap URL is not configured.')
    return
  end

  if minimapDownloadOperation then
    return
  end

  setDownloadMapButtonState(true)
  -- HTTP.download may run the callback synchronously on an immediate failure, before it
  -- ever returns a handle. Remember that so the assignment below cannot resurrect an
  -- already finished operation and block every later download.
  local finished = false
  local ok, operation = pcall(function()
    return HTTP.download(url, 'minimap.otmm', function(path, checksum, err)
      finished = true
      minimapDownloadOperation = nil
      setDownloadMapButtonState(false)

      if err then
        displayMapDownloadFailure(err)
        return
      end

      if not path or path == '' then
        displayMapDownloadFailure('the HTTP download returned no file path')
        return
      end

      local downloadPath = path:sub(1, 11) == '/downloads/' and path or '/downloads/' .. path
      local readOk, content = pcall(g_resources.readFileContents, downloadPath)
      if not readOk or type(content) ~= 'string' or #content < 22 then
        displayMapDownloadFailure(readOk and 'the downloaded file is empty' or content)
        return
      end

      if content:sub(1, 4) ~= 'OTMM' or content:byte(7) ~= 1 or content:byte(8) ~= 0 then
        displayMapDownloadFailure('the downloaded file is not a supported OTMM 1.0 map')
        return
      end

      local backupOk, backup = backupMinimapFile()
      if not backupOk then
        displayMapDownloadFailure('unable to back up ' .. minimapFile .. '; the current map was kept')
        return
      end

      if not g_resources.writeFileContents(minimapFile, content) then
        discardMinimapBackup(backup)
        displayMapDownloadFailure('unable to write ' .. minimapFile)
        return
      end

      g_minimap.clean()
      if not g_minimap.loadOtmm(minimapFile) then
        local restored = rollbackMinimapFile(backup)
        discardMinimapBackup(backup)

        g_minimap.clean()
        if restored then
          g_minimap.loadOtmm(minimapFile)
        else
          -- Nothing usable on disk and nothing in memory. Leaving loaded set would let
          -- saveMap() write the emptied minimap over whatever survived.
          MinimapLoader.loaded = false
          MinimapLoader.otmmLoaded = false
        end
        displayMapDownloadFailure('the downloaded OTMM file could not be loaded')
        return
      end

      discardMinimapBackup(backup)
      MinimapLoader.otmmLoaded = true
      MinimapLoader.loaded = true
      if minimapWidget and not minimapWidget:isDestroyed() then
        minimapWidget:load()
        local player = g_game.getLocalPlayer()
        if player then
          local position = player:getPosition()
          minimapWidget:setCameraPosition(position)
          minimapWidget:setCrossPosition(position)
        end
      end

      g_logger.info('[game_minimap] Full map downloaded and loaded successfully.')
      if modules.game_textmessage and modules.game_textmessage.displayGameMessage then
        modules.game_textmessage.displayGameMessage(tr('Map downloaded successfully.'))
      end
    end)
  end)

  if not ok then
    minimapDownloadOperation = nil
    setDownloadMapButtonState(false)
    displayMapDownloadFailure(operation)
    return
  end

  if not finished then
    minimapDownloadOperation = operation
  end
end

local function syncSideButton(state, retries)
  retries = retries or 8
  if modules.game_sidebuttons and modules.game_sidebuttons.setButtonVisible then
    modules.game_sidebuttons.setButtonVisible("lenshelpFunction", state)
    return
  end

  if retries > 0 then
    scheduleEvent(function() syncSideButton(state, retries - 1) end, 250)
  end
end

local function attachMinimapToPanel()
  if not minimapWindow then
    return false
  end

  if minimapWindow:getParent() then
    return true
  end

  if m_interface and m_interface.getRightPanel then
    minimapWindow:setParent(m_interface.getRightPanel())
    return true
  end

  return false
end

function init()
  serverMinimapOpcode = configuredServerMinimapOpcode()
  if serverMinimapOpcode then
    local ok, reason = pcall(ProtocolGame.registerExtendedOpcode,
      serverMinimapOpcode, onServerMinimapOpcode)
    if ok then
      serverMinimapRegistered = true
    else
      g_logger.warning(string.format(
        '[game_minimap] Server minimap sync disabled for opcode %d: %s',
        serverMinimapOpcode, tostring(reason)))
    end
  end

  minimapWindow = g_ui.loadUI('minimap', m_interface.getRightPanel())
  -- The right-hand controls are pinned to the top so vertical expansion only adds map
  -- below them. Compass (46) plus the floor indicator (67) plus the 19px of window
  -- chrome need 132; below that the cyclopedia button falls out of the window.
  minimapWindow:setHeight(140)

  if not minimapWindow.forceOpen then
    minimapButton = modules.client_topmenu.addRightGameToggleButton('minimapButton',
      tr('Minimap') .. ' (Ctrl+M)', '/images/topbuttons/minimap', toggle)
    minimapButton:setOn(true)
  end
  minimapWidget = minimapWindow:recursiveGetChildById('minimap')
  minimapHDToggle = minimapWindow:recursiveGetChildById('minimapHDToggle')
  -- Reflect the persisted preference on the engine and the button. The saved tile
  -- data is only loaded in online(), where the world and character are known.
  applyHDMode(isHDEnabled(), false)
  local downloadMapButton = getDownloadMapButton()
  if downloadMapButton then
    local hasDownloadUrl = Services and type(Services.minimap) == 'string' and Services.minimap ~= ''
    downloadMapButton:setVisible(hasDownloadUrl)
  end

  local gameRootPanel = m_interface.getRootPanel()
  keybindMoveEast:active(gameRootPanel)
  keybindMoveNorth:active(gameRootPanel)
  keybindMoveSouth:active(gameRootPanel)
  keybindMoveWest:active(gameRootPanel)
  keybindFloorUp:active(gameRootPanel)
  keybindFloorDown:active(gameRootPanel)
  keybindZoomIn:active(gameRootPanel)
  keybindZoomOut:active(gameRootPanel)
  keybindCenter:active(gameRootPanel)
  keybindShowMinimap:active(gameRootPanel)


  minimapWindow:setup()
  open()
  if minimapWindow.iconResize then
    minimapWindow:getChildById('iconResize'):hide()
  end

  -- Expand from the edge that faces the game area. The Astra minimap may be
  -- placed on either side, unlike the original implementation.
  local resizeBorder = minimapWindow:getChildById('resizeBorder')
  if resizeBorder then
    resizeBorder.onMousePress = function(self, mousePos, mouseButton)
      if not expansion.parent and not detachMinimap() then
        return false
      end

      local position = minimapWindow:getPosition()
      expansion.fixedEdge = expansion.direction < 0 and
        position.x + minimapWindow:getWidth() or position.x
      return true
    end

    resizeBorder.onMouseMove = function(self, mousePos, mouseMoved)
      if not self:isPressed() or not expansion.parent then
        return false
      end

      if expansion.direction < 0 then
        setExpandedWidth(expansion.fixedEdge - mousePos.x)
      else
        setExpandedWidth(mousePos.x - expansion.fixedEdge)
      end
      return true
    end

    local originalRelease = resizeBorder.onMouseRelease
    resizeBorder.onMouseRelease = function(self, mousePos, mouseButton)
      if originalRelease then originalRelease(self, mousePos, mouseButton) end
      if not expansion.parent then
        return
      end

      local collapseAt = (expansion.collapsedWidth or 178) + COLLAPSE_SNAP_MARGIN
      if minimapWindow:getWidth() <= collapseAt then
        restoreMinimap(true)
      else
        syncExpansionPlaceholders()
        saveExpansionConfig(true)
      end
    end

    resizeBorder.onDoubleClick = function()
      toggleExpanded()
      return true
    end
  end

  configureResizeBorder(getExpansionDirection(minimapWindow:getParent()))
  updateExpandButton()
  updateVerticalExpandButton()
  g_keyboard.bindKeyDown('Ctrl+Shift+M', toggleFullMap)

  local originalHeightChange = minimapWindow.onHeightChange
  minimapWindow.onHeightChange = function(self, height)
    if originalHeightChange then originalHeightChange(self, height) end
    if expansion.parent then
      syncExpansionPlaceholders()
    end
  end

  local floorPosition = minimapWindow:getChildById('floorPosition')
  if floorPosition then
    floorPosition.onMouseWheel = onMouseWheel
  end

  -- Camera changes also happen through Ctrl+wheel, floor controls and reset(), not only
  -- through LocalPlayer.onPositionChange. Preserve UIMinimap's cross update and refresh
  -- the shared floor indicator from the same camera callback.
  local originalCameraPositionChange = minimapWidget.onCameraPositionChange
  minimapWidget.onCameraPositionChange = function(self, cameraPosition, oldPosition)
    if originalCameraPositionChange then
      originalCameraPositionChange(self, cameraPosition, oldPosition)
    end
    if cameraPosition then
      updateFloorImage(cameraPosition.z)
    end
  end
  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
    onPartyDataUpdate = Party.Update,
    onPartyDataClear = Party.Reset,

    onServerTime = onServerTime
  })

  connect(LocalPlayer, {
    onPositionChange = updateCameraPosition
  })

  if g_game.isOnline() then
    online()
  end
end

function terminate()
  cancelServerMinimapRequest()
  resetServerMinimapTransfer()
  cancelServerHDMinimapRequest()
  resetServerHDMinimapTransfer()
  if serverMinimapRegistered then
    pcall(ProtocolGame.unregisterExtendedOpcode, serverMinimapOpcode)
    serverMinimapRegistered = false
  end

  if minimapDownloadOperation then
    HTTP.cancel(minimapDownloadOperation)
    minimapDownloadOperation = nil
  end

  if expansionRestoreEvent then
    removeEvent(expansionRestoreEvent)
    expansionRestoreEvent = nil
  end

  if g_game.isOnline() then
    saveExpansionConfig()
    saveMap()
  end
  g_minimap.setHDMode(false)

  -- Exit full map view before cleanup
  if fullmapView then
    fullmapView = false
    minimapWidget:setParent(minimapWindow)
    minimapWidget:fill('parent')
    minimapWindow:show()
    minimapWidget:setAlternativeWidgetsVisible(false)
  end

  restoreMinimap(false)

  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
    onPartyDataUpdate = Party.Update,
    onPartyDataClear = Party.Reset,

    onServerTime = onServerTime
  })

  disconnect(LocalPlayer, {
    onPositionChange = updateCameraPosition
  })

  keybindMoveEast:deactive()
  keybindMoveNorth:deactive()
  keybindMoveSouth:deactive()
  keybindMoveWest:deactive()
  keybindFloorUp:deactive()
  keybindFloorDown:deactive()
  keybindZoomIn:deactive()
  keybindZoomOut:deactive()
  keybindShowMinimap:deactive()

  g_keyboard.unbindKeyDown('Ctrl+Shift+M')

  minimapWindow:destroy()
  if minimapButton then
    minimapButton:destroy()
  end
  minimapHDToggle = nil
  minimapWidget = nil
  minimapWindow = nil
  minimapButton = nil
end

function toggle()
  if not minimapButton then return end
  if fullmapView then
    toggleFullMap()
  end
  local sideButton = modules.game_sidebuttons.getButtonById("lenshelpFunction")
  if minimapWindow:isVisible() then
    -- Collapse for the close, but keep the persisted expansion state: closing the minimap
    -- is not the user asking for it to come back collapsed next session.
    restoreMinimap(false)
    minimapWindow:close()
    minimapButton:setOn(false)
    syncSideButton(false)
    if sideButton then
      sideButton.highlight:setVisible(true)
    end
  else
    if attachMinimapToPanel() then
      minimapWindow:open()
      if sideButton then
        sideButton.highlight:setVisible(false)
      end
    end
    minimapButton:setOn(true)
    syncSideButton(true)
  end
end

function open()
  if not minimapWindow then
    return
  end

  attachMinimapToPanel()
  minimapWindow:open()

  if minimapButton then
    minimapButton:setOn(true)
  end

  syncSideButton(true)
end

function isOpen()
  return minimapWindow and minimapWindow:isVisible()
end

function preload()
  loadMap(false)
  preloaded = true
end

function online()
  local benchmark = g_clock.millis()
  if not MinimapLoader.loaded then
    loadMap(not preloaded)
  end
  if serverMinimapRegistered then
    loadCachedServerMinimap()
    loadCachedServerHDMinimap()
    scheduleServerMinimapRequest()
  end
  applyHDMode(isHDEnabled(), true)
  updateCameraPosition({x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 1})
  if minimapWidget then
    -- The camera has no position until the first setCameraPosition, which does not
    -- happen when the player has no position yet at this point in the login.
    local cameraPosition = minimapWidget:getCameraPosition()
    if cameraPosition then
      updateFloorImage(cameraPosition.z)
    end
  end
  scheduleExpansionRestore()

  if minimapwidget then
    Party.Reset()
  end

  consoleln("Minimap loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function offline()
  cancelServerMinimapRequest()
  resetServerMinimapTransfer()
  cancelServerHDMinimapRequest()
  resetServerHDMinimapTransfer()
  serverMinimapCacheLoaded = false
  serverHDMinimapCacheValid = false
  serverHDMinimapManifestRequested = false

  if not minimapWidget then
    g_minimap.setHDMode(false)
    activeHDBaseFile = nil
    return
  end

  if expansionRestoreEvent then
    removeEvent(expansionRestoreEvent)
    expansionRestoreEvent = nil
  end

  saveExpansionConfig()
  restoreMinimap(false)
  saveMap()
  g_minimap.setHDMode(false)
  activeHDBaseFile = nil

  minimapWidget:resetParty()
  minimapWidget:clearWaypoints()
  minimapWidget:clearRoutePath()
end

function loadMap(clean)
  if clean then
    g_minimap.clean()
  end

  if not MinimapLoader.otmmLoaded then
    if g_resources.fileExists(minimapFile) then
      g_minimap.loadOtmm(minimapFile)
    end
    MinimapLoader.otmmLoaded = true
  end

  -- LoadTibiaMap()
  if minimapWidget and minimapWidget.load then
    minimapWidget:load()
  end
  attachMinimapToPanel()
  MinimapLoader.loaded = true
end

function updateCameraPosition(newPosition, lastPosition)
  local player = g_game.getLocalPlayer()
  if not player then return end
  local pos = player:getPosition()
  if not pos then return end
  if not minimapWidget:isDragging() then
    if not fullmapView then
      minimapWidget:setCameraPosition(player:getPosition())
    end
    minimapWidget:setCrossPosition(player:getPosition())
  end

  if oldPos and newPosition.z ~= oldPos.z then
    Party.UpdateFloor(newPosition.z)
  end

  if #Party.Members >= 1 then
    Party.SendUpdate(newPosition)
  end

end

function updateFloorImage(posZ)
  if not minimapWindow or minimapWindow:isDestroyed() then
    return
  end

  local floorPosition = minimapWindow:getChildById('floorPosition')
  if not floorPosition or floorPosition:isDestroyed() then
    return
  end

  local floorZ = math.max(0, math.min(15, tonumber(posZ) or 7))
  floorPosition:setImageClip((floorZ * 14) .. ' 0 14 67')
end

function onMouseWheel(widget, mousePos, direction)
  if direction == MouseWheelUp then
    minimapWindow:recursiveGetChildById('minimap'):floorUp(1)
  elseif direction == MouseWheelDown then
    minimapWindow:recursiveGetChildById('minimap'):floorDown(1)
  end

  return true
end

function zoom(bool)
  if bool then
    minimapWindow:recursiveGetChildById('minimap'):zoomIn()
  else
    minimapWindow:recursiveGetChildById('minimap'):zoomOut()
  end
end

function floor(bool)
  if bool then
    minimapWindow:recursiveGetChildById('minimap'):floorUp(1)
  else
    minimapWindow:recursiveGetChildById('minimap'):floorDown(1)
  end

end

function center()
  minimapWindow:recursiveGetChildById('minimap'):reset()
end

function checkXByHour(x)
  local y0 = 62
  local incremento = y0 / 12
  local result = math.floor(y0 + (x * incremento))
  if result > 124 then
    result = result - 124
  end

  return result
end

function LoadTibiaMap()
  g_minimap.clean()

  -- FunÃ§Ã£o para verificar se um arquivo deve ser carregado
  local function shouldLoadFile(file)
    return not file:lower():find('waypointcost') and file:match(".*%.png$")
  end

  -- Carregar as imagens de forma assÃ­ncrona
  local function asyncLoadImage(file)
    local fileNoExt = file:sub(1, -5)
    local pos = fileNoExt:split("_")
    if #pos >= 3 then
      local x, y, z = tonumber(pos[#pos - 2]), tonumber(pos[#pos - 1]), tonumber(pos[#pos])
      if x and y and z then
        g_minimap.loadImage('/minimap/' .. file, { x = x, y = y, z = z }, 1.0)
      end
    end
  end

  -- Caching para imagens jÃ¡ carregadas
  local loadedImages = {}

  -- FunÃ§Ã£o para carregar imagens visÃ­veis
  local function loadVisibleImages()
    local files = g_resources.listDirectoryFiles("/minimap", false, true)
    for _, file in ipairs(files) do
      if shouldLoadFile(file) and not loadedImages[file] then
        asyncLoadImage(file)
        loadedImages[file] = true
      end
    end
  end

  -- Chamada inicial para carregar imagens visÃ­veis
  loadVisibleImages()
end

function move(panel, height, index)
  if not panel then
    return
  end

  local wasExpanded = expansion.parent ~= nil
  local expandedWidth = wasExpanded and minimapWindow:getWidth() or nil
  local verticalHeight = expansion.verticalExpanded and minimapWindow:getHeight() or nil
  if wasExpanded then
    restoreMinimap(false)
  end

  local function reparentToPanel()
    minimapWindow:setParent(panel)
    if verticalHeight or height then
      minimapWindow:setHeight(verticalHeight or height)
    end
    configureResizeBorder(getExpansionDirection(panel))
    updateExpandButton()
    updateVerticalExpandButton()
    if wasExpanded and detachMinimap() then
      setExpandedWidth(expandedWidth)
    else
      fitVerticalExpansionToAvailable()
    end
  end

  -- The horizontal panels are still being laid out at this point, so they need a frame
  -- before the minimap can measure itself against them.
  if string.find(panel:getId(), "horizontal") then
    addEvent(reparentToPanel)
  else
    reparentToPanel()
  end

  minimapWindow:open()
  syncSideButton(true)

  return minimapWindow
end

function onPlayerUnload()
  local index = -1
  local parent = expansion.parent or minimapWindow:getParent()
  if parent then
    local placeholder = expansion.placeholders[parent]
    index = placeholder and parent:getChildIndex(placeholder) or parent:getChildIndex(minimapWindow)
    modules.game_sidebars.registerMinimapConfig({contentHeight = minimapWindow:getHeight(), index = index})
  end
end

function loadMarks()
  local file = '/data/json/markers.json'
  if g_resources.fileExists(file) then
    local status, result = pcall(function()
      return json.decode(g_resources.readFileContents(file))
    end)

    if not status then
      return g_logger.error("Error while reading marks file. Details: " .. result)
    end

    local iconConfig = {
      ["checkmark"] = 1,
      ["?"] = 2,
      ["!"] = 3,
      ["star"] = 4,
      ["crossmark"] = 5,
      ["cross"] = 7,
      ["mouth"] = 8,
      ["spear"] = 9,
      ["sword"] = 10,
      ["flag"] = 11,
      ["lock"] = 13,
      ["bag"] = 14,
      ["skull"] = 15,
      ["$"] = 16,
      ["red up"] = 17,
      ["red down"] = 19,
      ["red right"] = 20,
      ["red left"] = 21,
      ["up"] = 22,
      ["down"] = 23,
    }

    local function customSort(a, b)
      -- Se ambos os z estÃ£o entre 0 e 7, ou ambos estÃ£o entre 8 e 14, compara diretamente
      if (a.z >= 0 and a.z <= 7 and b.z >= 0 and b.z <= 7) or (a.z >= 8 and a.z <= 14 and b.z >= 8 and b.z <= 14) then
          return a.z > b.z -- Inverte a comparaÃ§Ã£o para obter 7 a 0 primeiro
      elseif a.z >= 0 and a.z <= 7 then
          return true -- A vem antes se estiver no intervalo 0 a 7, independente do B
      elseif b.z >= 0 and b.z <= 7 then
          return false -- B vem antes se A nÃ£o estiver no intervalo 0 a 7 e B estiver
      else
          return a.z < b.z -- Caso contrÃ¡rio, compara normalmente para ordenar 8 a 14
      end
  end

  table.sort(result, customSort)

    for i, info in pairs(result) do
      scheduleEvent(
        function()
          if iconConfig[info.icon] and minimapWidget and minimapWidget:isVisible() then
            minimapWidget:addFlag({x = info.x, y = info.y, z = info.z}, '/data/images/game/minimap/icon/'..iconConfig[info.icon], info.description, true)
          end
        end, i*60)
    end
  end

  g_settings.set('seeMapMark', true)
end

function onClose()
  -- Same as toggle(): collapse the widget without persisting a collapsed preference.
  restoreMinimap(false)
end

function onServerTime(minutes, seconds)
  if not minimapWindow then
    return
  end
  minimapWindow.centerMap:setImageClip(checkXByHour(minutes) .. " 0 31 31")
end

function setPath(coordinates)
  if not minimapWidget then
    return
  end

  if table.size(coordinates) == 0 then
      return
  end

  minimapWidget:clearWaypoints()
  minimapWidget:setDrawWaypoints(true)
  for floor, coordinate in pairs(coordinates) do
      if tonumber(floor) then
          minimapWidget:makeWaypoints(coordinate, tonumber(floor))
      end
  end
end

function clearPath()
  minimapWidget:clearWaypoints()
  minimapWidget:setDrawWaypoints(false)
end

function setRoutePath(coordinates)
  if not minimapWidget then
    return
  end

  if table.size(coordinates) == 0 then
      return
  end

  minimapWidget:clearRoutePath()
  minimapWidget:setDrawWaypoints(true)
  for floor, coordinate in pairs(coordinates) do
      if tonumber(floor) then
          minimapWidget:makeRouth(coordinate, tonumber(floor))
      end
  end
end

function clearRoutePath()
  minimapWidget:clearRoutePath()
  minimapWidget:setDrawWaypoints(false)
end
