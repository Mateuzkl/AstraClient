-- Exercise the production DAT/SPR orchestration, not a copy of its logic.
local function reset(overrides)
  local state = {version = 740, protocol = 740, features = {}, path = '740/Tibia',
    indexed = true, datCalls = 0, sprCalls = 0, datLoaded = false, sprLoaded = false}
  for key, value in pairs(overrides or {}) do state[key] = value end
  local env = setmetatable({
    GameSpritesU32 = 1, GameIdleAnimations = 2, GameEnhancedAnimations = 3,
    tr = string.format, resolvepath = function(path) return path end,
    g_logger = {info = function() end, error = function() end},
    g_settings = {getNode = function() return {data = state.path, sprites = state.path} end},
    g_resources = {
      getGeneration = function() return 1 end,
      fileExists = function() return state.modern == true end,
      readFileContents = function() return 'frame-groups: true' end,
      guessFilePath = function(path, ext) return path .. '.' .. ext end
    },
    g_game = {
      getClientVersion = function() return state.version end,
      getProtocolVersion = function() return state.protocol end,
      setClientVersion = function(value)
        state.version = value
        if state.profileFeatures then
          state.features = {[1] = state.profileFeatures[value]}
        end
      end,
      setProtocolVersion = function(value) state.protocol = value end,
      getFeature = function(feature) return state.features[feature] == true end,
      enableFeature = function(feature) state.features[feature] = true end,
      disableFeature = function(feature) state.features[feature] = nil end
    },
    g_things = {
      isDatLoaded = function() return state.datLoaded end,
      loadDat = function()
        state.datCalls = state.datCalls + 1
        assert(state.features[1] == state.expectedU32, 'wrong sprite ID width before DAT parsing')
        state.datLoaded = not state.failDat
        return state.datLoaded
      end,
      loadOtml = function() end
    },
    g_sprites = {
      isIndexedSource = function() return state.indexed end,
      isLoaded = function() return state.sprLoaded end,
      loadSpr = function()
        state.sprCalls = state.sprCalls + 1
        assert(state.features[1] == state.expectedU32, 'DAT and SPR widths differ')
        state.sprLoaded = not state.failSpr
        return state.sprLoaded
      end
    }
  }, {__index = _G})
  local chunk = assert(loadfile('modules/game_things/things.lua'))
  setfenv(chunk, env); chunk()
  return state, env
end

do
  local state, env = reset({expectedU32 = true})
  env.load()
  assert(env.isLoaded() and state.features[1], 'indexed source must use U32')
  state.features = {}
  for _ = 1, 20 do env.load() end
  assert(state.datCalls == 1 and state.sprCalls == 1, 'same indexed pack must not reload or duplicate callbacks')
  assert(state.features[1], 'cached indexed source must restore U32')
  state.indexed, state.expectedU32 = false, nil
  env.load() -- Same path, different source: reject the cached indexed identity.
  assert(state.datCalls == 2 and state.sprCalls == 2 and not state.features[1], 'legacy U16 mode not restored')
  env.load()
  assert(state.datCalls == 2 and state.sprCalls == 2, 'legacy reuse must remain intact')
end

do
  local state, env = reset({features = {[1] = true}, expectedU32 = true})
  env.load()
  state.indexed = false
  env.load()
  assert(state.features[1], 'version-configured U32 must not be disabled')
end

do
  local state, env = reset({expectedU32 = true})
  env.load()
  state.version, state.features = 770, {}
  env.load()
  assert(state.datCalls == 1, 'profile reset must reuse the indexed pack')
  state.indexed, state.expectedU32 = false, nil
  env.load()
  assert(not state.features[1], 'cached U32 restoration must belong to the new profile')
end

do
  local state, env = reset({version = 860, features = {[1] = true}, expectedU32 = true,
    profileFeatures = {[740] = false, [860] = true}})
  env.load()
  assert(state.version == 860 and state.features[1], 'protocol profile was not restored')
  state.path, state.indexed = '860/Tibia', false
  env.load()
  assert(state.features[1], 'temporary asset version must not own the restored protocol flag')
end

do
  local state, env = reset({expectedU32 = true})
  env.load()
  state.indexed, state.modern = false, true
  env.load()
  assert(state.features[1] and state.features[2] and state.features[3], 'modern asset flags must be preserved')
end

for _, failure in ipairs({'failDat', 'failSpr'}) do
  local state, env = reset({expectedU32 = true, [failure] = true})
  env.load()
  assert(not env.isLoaded() and not state.features[1], 'failed indexed load leaked its U32 flag')
  state[failure], state.indexed, state.expectedU32 = false, false, nil
  env.load()
  assert(env.isLoaded(), 'legacy retry after indexed failure must work')
end

print('Indexed SPR production lifecycle: OK')
