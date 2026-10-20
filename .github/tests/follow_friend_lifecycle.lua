local env = setmetatable({}, {__index = _G})
env.ProtocolGame = {}
env._Helper = {}
env.ExtendedIds = {FollowTransition = 42}
env.g_game = {}
env.connect, env.disconnect = function() end, function() end
env.g_logger = {warning = function() end}
local function loadProduction(path)
  local f = assert(loadfile(path)); setfenv(f, env); f()
end
loadProduction('modules/gamelib/protocolgame.lua')
local proto = env.ProtocolGame
local function handlers()
  for i = 1, 20 do
    local name, value = debug.getupvalue(proto.onExtendedOpcode, i)
    if name == 'extendedJSONCallbacks' then return value end
  end
  error('production callback table not found')
end
loadProduction('mods/game_helper/classes/follow_friend.lua')
local follow = env._Helper.FollowFriend
assert(not handlers()[42], 'registration must belong to init, not file loading')
for _ = 1, 3 do
  follow.init()
  local callback = assert(handlers()[42])
  follow.init(); assert(handlers()[42] == callback)
  follow.terminate(); assert(not handlers()[42])
  follow.terminate()
end
local replacement = function() end
follow.init()
proto.unregisterExtendedJSONOpcode(42)
proto.registerExtendedJSONOpcode(42, replacement)
follow.terminate()
assert(handlers()[42] == replacement, 'teardown removed another owner')
follow.init(); follow.terminate()
assert(handlers()[42] == replacement, 'failed registration stole the opcode')
proto.unregisterExtendedJSONOpcode(42)
follow.init()
loadProduction('mods/game_helper/classes/follow_friend.lua')
assert(not handlers()[42], 'script reload retained the previous callback')
env._Helper.FollowFriend.init()
env._Helper.FollowFriend.terminate()
assert(not handlers()[42])
print('FollowFriend init, teardown, reload and opcode ownership: OK')
