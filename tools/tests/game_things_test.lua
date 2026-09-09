local thingsScript = assert(arg[1], 'usage: lua game_things_test.lua <things.lua>')

local state

local function reset(overrides)
  state = {
    version = 860,
    protocolVersion = 860,
    generation = 1,
    features = {},
    datLoaded = false,
    sprLoaded = false,
    datResults = { true },
    sprResults = { true },
    datCalls = 0,
    sprCalls = 0,
    otmlCalls = 0,
    versionChanges = {}
  }

  for key, value in pairs(overrides or {}) do
    state[key] = value
  end

  GameSpritesU32 = 1
  GameIdleAnimations = 2
  GameEnhancedAnimations = 3

  function tr(formatString, ...)
    return string.format(formatString, ...)
  end

  function resolvepath(path)
    return path
  end

  g_logger = {
    info = function() end,
    error = function() end
  }

  g_settings = {
    getNode = function()
      return state.settings
    end
  }

  g_resources = {
    getGeneration = function()
      return state.generation
    end,
    fileExists = function(path)
      return state.modernOtfi and path:sub(-5) == '.otfi'
    end,
    readFileContents = function()
      return state.modernOtfi and 'frame-groups: true' or nil
    end
  }

  g_game = {
    getClientVersion = function()
      return state.version
    end,
    getProtocolVersion = function()
      return state.protocolVersion
    end,
    setClientVersion = function(version)
      state.version = version
      state.versionChanges[#state.versionChanges + 1] = version
    end,
    setProtocolVersion = function(version)
      state.protocolVersion = version
    end,
    enableFeature = function(feature)
      state.features[feature] = true
    end,
    getFeature = function(feature)
      return state.features[feature] == true
    end
  }

  g_things = {
    isDatLoaded = function()
      return state.datLoaded
    end,
    loadDat = function()
      state.datCalls = state.datCalls + 1
      local result = table.remove(state.datResults, 1)
      if result == nil then
        result = true
      end
      state.datLoaded = result
      return result
    end,
    loadOtml = function()
      state.otmlCalls = state.otmlCalls + 1
      return true
    end
  }

  g_sprites = {
    isLoaded = function()
      return state.sprLoaded
    end,
    loadSpr = function()
      state.sprCalls = state.sprCalls + 1
      local result = table.remove(state.sprResults, 1)
      if result == nil then
        result = true
      end
      state.sprLoaded = result
      return result
    end
  }

  assert(loadfile(thingsScript))()
end

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error(string.format('%s: expected %s, got %s', message, tostring(expected), tostring(actual)), 2)
  end
end

local function testSameIdentityIsReused()
  reset({ features = { [GameSpritesU32 or 1] = true } })
  g_game.enableFeature(GameSpritesU32)
  load()
  assertEqual(state.datCalls, 1, 'first DAT load')
  assertEqual(state.sprCalls, 1, 'first SPR load')

  state.features = {}
  load()
  assertEqual(state.datCalls, 1, 'same identity DAT reuse')
  assertEqual(state.sprCalls, 1, 'same identity SPR reuse')
  assertEqual(state.features[GameSpritesU32], true, 'U32 feature restored on reuse')

  for _ = 1, 20 do
    load()
  end
  assertEqual(state.datCalls, 1, 'repeated relog/reconnect DAT reuse')
  assertEqual(state.sprCalls, 1, 'repeated relog/reconnect SPR reuse')
end

local function testPathAndNativeInvalidationReload()
  reset()
  load()
  state.settings = { data = '1098/Tibia', sprites = '1098/Tibia' }
  load()
  assertEqual(state.datCalls, 2, 'path change reloads DAT')
  assertEqual(state.sprCalls, 2, 'path change reloads SPR')
  assertEqual(state.versionChanges[1], 1098, 'temporary asset version applied')
  assertEqual(state.versionChanges[2], 860, 'client version restored')

  state.settings = nil
  load()
  assertEqual(state.datCalls, 3, 'return to 860 reloads DAT')
  assertEqual(state.sprCalls, 3, 'return to 860 reloads SPR')

  state.sprLoaded = false
  load()
  assertEqual(state.datCalls, 4, 'native invalidation reloads DAT')
  assertEqual(state.sprCalls, 4, 'native invalidation reloads SPR')
end

local function testModuleReloadIsConservative()
  reset()
  load()
  assert(loadfile(thingsScript))()
  load()
  assertEqual(state.datCalls, 2, 'module reload does not inherit stale DAT identity')
  assertEqual(state.sprCalls, 2, 'module reload does not inherit stale SPR identity')
end

local function testResourceRemountReloads()
  reset()
  load()
  state.generation = state.generation + 1
  load()
  assertEqual(state.datCalls, 2, 'resource generation reloads DAT')
  assertEqual(state.sprCalls, 2, 'resource generation reloads SPR')
end

local function testFailedLoadIsNotCached()
  reset({ datResults = { false, false, true }, sprResults = { true, true } })
  load()
  assertEqual(isLoaded(), false, 'failed DAT attempt')
  load()
  assertEqual(state.datCalls, 3, 'failed DAT is retried')
  assertEqual(state.sprCalls, 2, 'SPR is retried after partial failure')
  assertEqual(isLoaded(), true, 'DAT retry succeeds')

  reset({ sprResults = { false, true } })
  load()
  assertEqual(isLoaded(), false, 'failed SPR attempt')
  load()
  assertEqual(state.datCalls, 2, 'DAT reloads after failed SPR')
  assertEqual(state.sprCalls, 2, 'failed SPR is retried')
end

local function testU32FallbackAndModernAssets()
  reset({ datResults = { false, true } })
  load()
  assertEqual(state.datCalls, 2, 'U32 DAT fallback')
  assertEqual(state.features[GameSpritesU32], true, 'U32 enabled after fallback')
  state.features = {}
  load()
  assertEqual(state.datCalls, 2, 'fallback identity reused')
  assertEqual(state.features[GameSpritesU32], true, 'learned U32 restored')

  reset({ modernOtfi = true })
  load()
  assertEqual(state.features[GameSpritesU32], true, 'modern U32 enabled')
  assertEqual(state.features[GameIdleAnimations], true, 'modern idle animations enabled')
  assertEqual(state.features[GameEnhancedAnimations], true, 'modern enhanced animations enabled')
end

testSameIdentityIsReused()
testPathAndNativeInvalidationReload()
testModuleReloadIsConservative()
testResourceRemountReloads()
testFailedLoadIsNotCached()
testU32FallbackAndModernAssets()

print('game_things tests: OK')
