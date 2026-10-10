-- Load the actual sandbox script without initializing its UI. Profile IO is
-- mocked here; native UI callers are exercised by cyclopedia_test.lua.
table.contains = function(values, wanted)
  for _, value in pairs(values) do if value == wanted then return true end end
  return false
end
local loaded, profile = false, nil
local env = setmetatable({
  LoadedPlayer={isLoaded=function() return loaded end,getId=function() return 1 end},
  g_resources={fileExists=function() return profile ~= nil end,readFileContents=function() return 'fixture' end},
  json={decode=function() return profile end},
}, {__index=_G})
setfenv(assert(loadfile('mods/game_quickloot/quickloot.lua')),env)()
local mode, selected = env.getLootSelection(100)
assert(mode==nil and selected==false and not env.loadData())
loaded=true
profile={listType='whitelist',whitelistTypes={100},blacklistTypes={200}}
assert(env.loadData())
assert(env.getLootSelection(100)=='whitelist')
mode, selected=env.getLootSelection(100); assert(mode=='whitelist' and selected)
mode, selected=env.getLootSelection(200); assert(mode=='whitelist' and not selected)
profile={listType='blacklist',whitelistTypes={},blacklistTypes={200}}
assert(env.loadData())
mode, selected=env.getLootSelection(200); assert(mode=='blacklist' and selected)
env.lootData.listType='invalid'; assert(env.getLootSelection(200)==nil)
env.lootData.listType='blacklist'; env.lootData.blacklistTypes=true; assert(env.getLootSelection(200)==nil)
assert(_G.lootData==nil, 'Sandbox data leaked into another module')
print('PASS: actual quickloot sandbox API, unloaded profile, whitelist, blacklist, malformed list, no global leakage')
