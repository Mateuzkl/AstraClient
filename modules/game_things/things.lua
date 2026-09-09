filename = nil
loaded = false
loading = false
lastError = nil
local successfulLoad = nil

function setFileName(name)
  filename = name
end

function isLoaded()
  return loaded
end

function isLoading()
  return loading
end

function getLoadError()
  return lastError
end

function getMissing860Message()
  return tr('Please place the Tibia 8.60 asset files in data/things/860 (Tibia.dat and Tibia.spr).')
end

local function getVersionFromPath(datPath)
  local version = tostring(datPath):match('[\\/]things[\\/](%d+)[\\/]')
  return tonumber(version)
end

local function hasModernAssetFeatures(datPath)
  local otfiPath = datPath .. '.otfi'
  if not g_resources.fileExists(otfiPath) then
    return false
  end

  local otfi = g_resources.readFileContents(otfiPath)
  if not otfi then
    return false
  end

  return otfi:find('frame%-groups:%s*true') ~= nil or otfi:find('sprite%-data%-size:%s*4096') ~= nil
end

local function enableModernAssetFeatures()
  g_game.enableFeature(GameSpritesU32)
  g_game.enableFeature(GameIdleAnimations)
  g_game.enableFeature(GameEnhancedAnimations)
end

local function getResourceGeneration()
  if g_resources.getGeneration then
    return g_resources.getGeneration()
  end
  return 0
end

local function isSameLoad(left, right)
  return left and
    left.assetVersion == right.assetVersion and
    left.datPath == right.datPath and
    left.sprPath == right.sprPath and
    left.modernAssets == right.modernAssets and
    left.resourceGeneration == right.resourceGeneration
end

local function isNativeStateValid()
  return g_things.isDatLoaded() and g_sprites.isLoaded()
end

function load()
  if loading then
    return
  end

  loading = true
  lastError = nil
  local version = g_game.getClientVersion()
  local things = g_settings.getNode('things')
  
  local datPath, sprPath
  if things and things["data"] ~= nil and things["sprites"] ~= nil then
    datPath = resolvepath('/things/' .. things["data"])
    sprPath = resolvepath('/things/' .. things["sprites"])
  else
    if filename then
      datPath = resolvepath('/things/' .. filename)
      sprPath = resolvepath('/things/' .. filename)
    else
      -- Force loading the 8.60 asset pack used by this server.
      datPath = resolvepath('/things/860/Tibia')
      sprPath = resolvepath('/things/860/Tibia')
    end
  end

  local protocolVersion = g_game.getProtocolVersion()
  local assetVersion = getVersionFromPath(datPath) or version
  local modernAssets = hasModernAssetFeatures(datPath)
  local requestedLoad = {
    assetVersion = assetVersion,
    datPath = datPath,
    sprPath = sprPath,
    modernAssets = modernAssets,
    resourceGeneration = getResourceGeneration()
  }

  if isSameLoad(successfulLoad, requestedLoad) and isNativeStateValid() then
    if successfulLoad.spritesU32 then
      g_game.enableFeature(GameSpritesU32)
    end
    if modernAssets then
      enableModernAssetFeatures()
    end
    loaded = true
    loading = false
    return
  end

  -- From this point native state may be replaced, so an older identity can no
  -- longer be trusted even if this attempt later fails.
  successfulLoad = nil

  if assetVersion ~= version then
    g_logger.info(string.format("Loading assets from %s as client version %d while keeping protocol %d.", datPath, assetVersion, protocolVersion))
    g_game.setClientVersion(assetVersion)
  end

  if modernAssets then
    enableModernAssetFeatures()
  end

  local errorMessage = ''
  local spritesU32 = g_game.getFeature(GameSpritesU32)
  if not g_things.loadDat(datPath) then
    if not g_game.getFeature(GameSpritesU32) then
      g_game.enableFeature(GameSpritesU32)
      spritesU32 = true
      if not g_things.loadDat(datPath) then
        errorMessage = errorMessage .. tr("Unable to load dat file, please place a valid dat in '%s'", datPath) .. '\n'
      end
    else
      errorMessage = errorMessage .. tr("Unable to load dat file, please place a valid dat in '%s'", datPath) .. '\n'
    end
  end
  if not g_sprites.loadSpr(sprPath) then
    errorMessage = errorMessage .. tr("Unable to load spr file, please place a valid spr in '%s'", sprPath)
  end

  local otmlPath = datPath .. '.otml'
  if errorMessage:len() == 0 and g_resources.fileExists(otmlPath) then
    g_things.loadOtml(otmlPath)
  end

  if assetVersion ~= version then
    g_game.setClientVersion(version)
    g_game.setProtocolVersion(protocolVersion)
  end

  loaded = (errorMessage:len() == 0)
  if loaded then
    requestedLoad.spritesU32 = spritesU32
    successfulLoad = requestedLoad
    if spritesU32 then
      g_game.enableFeature(GameSpritesU32)
    end
    if modernAssets then
      enableModernAssetFeatures()
    end
  end
  loading = false

  if errorMessage:len() > 0 then
    local loadError = errorMessage:gsub('%s+$', '')
    lastError = loadError .. '\n\n' .. getMissing860Message()
    g_logger.error(loadError)

    g_game.setClientVersion(0)
    g_game.setProtocolVersion(0)
  end
end
