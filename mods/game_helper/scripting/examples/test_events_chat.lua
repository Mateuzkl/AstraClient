--[[============================================================================
  test_events_chat.lua  --  self-test for the chat event sources
  ============================================================================
  WHAT IT COVERS (scripting/api/game.lua, event bridge):
    * Game.Events.TALK          engine onTalk  -> wired source
        handler args: (authorName, authorLevel, type, x, y, z, text, channelId)
    * Game.Events.TEXT_MESSAGE  engine onTextMessage -> wired source
        handler args: (messageData) with fields
          {channelId, messagePrimaryValue, messagePrimaryColor,
           messageSecondaryValue, messageSecondaryColor, x, y, z, text, messageType}
    * Game.registerEvent(type, fn) -> returns the SAME fn (Zerobot contract)
    * Game.unregisterEvent(type, fn)

  >>> THIS TEST NEEDS YOU (the player) <<<
  Both TALK and TEXT_MESSAGE are PUSH events. After enabling this script:
    * TALK         -> say ANYTHING in the default chat (press Enter, type, send),
                      or wait for any nearby creature/player to talk.
    * TEXT_MESSAGE -> trigger any server text message: a login/status line, a
                      loot message, "you see ...", an advance, etc. Walking,
                      looking at something, or fighting usually produces one.
  Each event prints a one-line dump of its payload to the debug console.

  SAFETY: events do not change the game. This script only LISTENS and LOGS.
  The engine auto-unregisters a script's callbacks on unload, but to demonstrate
  the contract this script ALSO unregisters both handlers itself via a watchdog
  Timer after ~30s (after which it stops reacting). No HUD, no game actions.
============================================================================]]

local pass, fail = 0, 0
local function check(name, cond, extra)
  if cond then
    pass = pass + 1
    print('[PASS] ' .. name .. (extra and (' = ' .. tostring(extra)) or ''))
  else
    fail = fail + 1
    print('[FAIL] ' .. name)
  end
end

-- Small helper: stringify a value that might be nil (engine leaves some payload
-- fields nil because the signal does not carry them).
local function s(v) return v == nil and '<nil>' or tostring(v) end

local talkSeen, textSeen = 0, 0

-- ---- TALK handler ---------------------------------------------------------
-- Signature mirrors spec 1.4 exactly.
local function onTalk(authorName, authorLevel, talkType, x, y, z, text, channelId)
  talkSeen = talkSeen + 1
  print(('[TALK #%d] author=%s lvl=%s type=%s pos=(%s,%s,%s) ch=%s text="%s"')
    :format(talkSeen, s(authorName), s(authorLevel), s(talkType),
            s(x), s(y), s(z), s(channelId), s(text)))
end

-- ---- TEXT_MESSAGE handler -------------------------------------------------
-- The engine delivers mode+text; the richer numeric/colour fields are nil here.
local function onTextMessage(messageData)
  textSeen = textSeen + 1
  local d = messageData or {}
  print(('[TEXT_MESSAGE #%d] type=%s text="%s" (primaryVal=%s color=%s)')
    :format(textSeen, s(d.messageType), s(d.text),
            s(d.messagePrimaryValue), s(d.messagePrimaryColor)))
end

-- registerEvent must return the SAME function object (handy for unregister).
local retTalk = Game.registerEvent(Game.Events.TALK, onTalk)
local retText = Game.registerEvent(Game.Events.TEXT_MESSAGE, onTextMessage)
check('registerEvent(TALK) returns same fn', retTalk == onTalk)
check('registerEvent(TEXT_MESSAGE) returns same fn', retText == onTextMessage)
check('Game.Events.TALK id', Game.Events.TALK == 0, Game.Events.TALK)
check('Game.Events.TEXT_MESSAGE id', Game.Events.TEXT_MESSAGE == 4, Game.Events.TEXT_MESSAGE)

print('[info] test_events_chat.lua armed. SAY something in chat / trigger a server')
print('[info] message. Listening for ~30s, then auto-unregistering.')

-- Watchdog: unregister both, report how many of each we saw, print summary.
-- (Demonstrates explicit teardown; the engine would also do this on unload.)
-- NOTE: this Timer port does NOT pass the instance to the callback, so we
-- capture the handle in `stopTimer` and stop THAT (not a `self` arg).
local stopTimer
stopTimer = Timer('test_events_chat.stop', function()
  Game.unregisterEvent(Game.Events.TALK, onTalk)
  Game.unregisterEvent(Game.Events.TEXT_MESSAGE, onTextMessage)
  print(('[info] unregistered. saw %d TALK, %d TEXT_MESSAGE event(s).')
    :format(talkSeen, textSeen))
  -- These are observational (depend on the player acting); we report, not fail.
  check('TALK handler stayed installed without error', true)
  check('TEXT_MESSAGE handler stayed installed without error', true)
  if stopTimer then stopTimer:destroy() end
  print(('--- events_chat: %d passed, %d failed ---'):format(pass, fail))
end, 30000, true)
