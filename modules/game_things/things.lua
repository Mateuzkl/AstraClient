local filename = nil
local loaded = false
local loading = false
local lastError = nil

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
  if hasModernAssetFeatures(datPath) then
    enableModernAssetFeatures()
  end

  if assetVersion ~= version then
    g_logger.info(string.format("Loading assets from %s as client version %d while keeping protocol %d.", datPath, assetVersion, protocolVersion))
    g_game.setClientVersion(assetVersion)
  end

  local errorMessage = ''
  if not g_things.loadDat(datPath) then
    if not g_game.getFeature(GameSpritesU32) then
      g_game.enableFeature(GameSpritesU32)
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
  loading = false

  if errorMessage:len() > 0 then
    local loadError = errorMessage:gsub('%s+$', '')
    lastError = loadError .. '\n\n' .. getMissing860Message()
    g_logger.error(loadError)

    g_game.setClientVersion(0)
    g_game.setProtocolVersion(0)
  end
end
