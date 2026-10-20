-- Run from the repository root with LuaJIT; no client/assets/server required.
local sourceFiles = assert(io.popen('git ls-files -- modules mods data init.lua'))
local syntaxCount = 0
for path in sourceFiles:lines() do
  if path:match('%.lua$') then assert(loadfile(path)); syntaxCount = syntaxCount + 1 end
end
assert(sourceFiles:close())
print(string.format('LuaJIT syntax: %d tracked source files passed.', syntaxCount))
local tests = {
  'item_details_opcode_framing.lua modules/game_protocol/protocol.lua src/client/protocolgameparse.cpp',
  'topmenu_lifecycle.lua', 'prey_lifecycle.lua', 'extended_json_lifecycle.lua',
  'follow_friend_lifecycle.lua', 'widget_event_lifecycle.lua',
  'protocol_dispatch.lua',
  'game_bot_auto_recording.lua modules/game_bot/bot.lua modules/game_bot/panels/waypoints.lua',
  'store_catalog_chunks.lua mods/game_store/storeprotocol.lua',
  'npc_dialog_travel.lua modules/game_npctrade/npcdialog.lua',
  'npc_trade_subtypes.lua modules/game_npctrade/npctrade.lua modules/game_npctrade/npcsession.lua modules/game_npctrade/npcsellqueue.lua',
  'quick_loot_detection.lua modules/game_interface/gameinterface.lua src/client/luafunctions_client.cpp src/client/uimap.cpp',
  'bestiary_notification.lua modules/gamelib/thing.lua modules/game_notifications/infobanner.lua src/client/protocolgameparse.cpp src/client/protocolgamesend.cpp src/client/const.h',
  'startup_lifecycle.lua', 'indexed_spr_lifecycle.lua', 'native_splash_config.lua',
  'web_credentials.lua', 'camviewer_files.lua', 'memleak_lifecycle.lua',
  'module_lifecycle.lua', 'wheel_lifecycle.lua',
  'negative_offset.lua modules/game_features/features.lua',
  'dat_offset_spinbox.lua modules/corelib/ui/uispinbox.lua',
}
local failed = 0
for _, command in ipairs(tests) do
  print('RUN ' .. command); io.stdout:flush()
  local ok = os.execute('luajit .github/tests/' .. command)
  if ok ~= 0 and ok ~= true then failed = failed + 1 end
end
assert(failed == 0, tostring(failed) .. ' regression suites failed')
print(string.format('All %d Lua regression suites passed.', #tests))
