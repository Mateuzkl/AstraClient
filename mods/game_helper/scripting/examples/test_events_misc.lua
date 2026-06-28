--[[============================================================================
  test_events_misc.lua  --  self-test for the WIRED protocol-window events
  ============================================================================
  Registers listeners for the protocol-backed Game.Events that have a real
  engine source in this build, then logs a short dump when each one fires. None
  of these change the game; they only react to a window/data you open.

  EVENTS LISTENED + HOW TO TRIGGER EACH (do these while the script is enabled):
    STORE_CATEGORIES (16) / STORE_OFFERS (17)
        -> Open the in-game Store, then click any category. Fires on the
           categories list and on each category's offers.
           payload(STORE_OFFERS): {categoryName, offers, redirect, sortingType,
                                   filters, currentFilter, reasons}
    IMBUEMENT_OPEN_WINDOW (8) / IMBUEMENT_DATA (7)
        -> Right-click an imbuable item -> "Imbue". OPEN_WINDOW fires with no
           args; DATA fires with {itemId, slots, availableImbuements[],
           slotImbuements[]}.
    OPEN_STASH (14)
        -> Open your Supply Stash (or a stash chest). Fires with
           {stashItems=[{itemId,count}], freeSlots}. (Hooks the stash mod's
           global showStash; needs game_stash loaded.)
    PARTY_HUNT (12)
        -> Be in a party with the Party Hunt Analyser open/active; it pushes
           {startTime, leaderId, priceType, membersData, membersName} on update.
    OPEN_DAILY_REWARD (18) / DAILY_REWARD_DAYS_DATA (19)
        -> Open the Daily Reward window (or step on a reward shrine). Fires with
           the reward-wall / days-data tables.
    QUEST_LOG (9)
        -> Open the Quest Log (Cyclopedia -> Quests / quest log button). Fires
           with {quests=[{id, name, state}]}. (You can also force it from another
           script via Game.requestQuestLog().)

  SAFETY: pure listeners -- no game actions, no HUD, no writes. The engine
  auto-unregisters every callback when the script unloads; this script keeps
  listening for ~60s and then unregisters them itself (demonstrating the
  contract) before printing its summary.
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

local function s(v) return v == nil and '<nil>' or tostring(v) end
local function count(t) -- length of an array-ish table, nil-safe
  if type(t) ~= 'table' then return 0 end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- A registration record: { eventName, eventId, fn }. We keep them so we can
-- unregister every one at the end in a single loop.
local regs = {}
local seen = {}  -- eventName -> times fired

local function listen(eventName, eventId, handler)
  local fn = function(...)
    seen[eventName] = (seen[eventName] or 0) + 1
    handler(...)
  end
  local ret = Game.registerEvent(eventId, fn)
  regs[#regs + 1] = { name = eventName, id = eventId, fn = fn }
  -- Contract: registerEvent returns the SAME fn it was given.
  check('registerEvent(' .. eventName .. ') returns same fn', ret == fn)
end

-- ---- STORE ----------------------------------------------------------------
listen('STORE_CATEGORIES', Game.Events.STORE_CATEGORIES, function(data)
  print(('[STORE_CATEGORIES] categories=%d'):format(count(data)))
end)
listen('STORE_OFFERS', Game.Events.STORE_OFFERS, function(data)
  data = data or {}
  print(('[STORE_OFFERS] category=%s offers=%d sorting=%s')
    :format(s(data.categoryName), count(data.offers), s(data.sortingType)))
end)

-- ---- IMBUEMENT ------------------------------------------------------------
listen('IMBUEMENT_OPEN_WINDOW', Game.Events.IMBUEMENT_OPEN_WINDOW, function()
  print('[IMBUEMENT_OPEN_WINDOW] (no payload)')
end)
listen('IMBUEMENT_DATA', Game.Events.IMBUEMENT_DATA, function(data)
  data = data or {}
  print(('[IMBUEMENT_DATA] itemId=%s slots=%s available=%d')
    :format(s(data.itemId), s(data.slots), count(data.availableImbuements)))
end)

-- ---- STASH ----------------------------------------------------------------
listen('OPEN_STASH', Game.Events.OPEN_STASH, function(data)
  data = data or {}
  print(('[OPEN_STASH] stashItems=%d freeSlots=%s')
    :format(count(data.stashItems), s(data.freeSlots)))
end)

-- ---- PARTY HUNT -----------------------------------------------------------
listen('PARTY_HUNT', Game.Events.PARTY_HUNT, function(data)
  data = data or {}
  print(('[PARTY_HUNT] leaderId=%s members=%d priceType=%s')
    :format(s(data.leaderId), count(data.membersName), s(data.priceType)))
end)

-- ---- DAILY REWARD ---------------------------------------------------------
listen('OPEN_DAILY_REWARD', Game.Events.OPEN_DAILY_REWARD, function(data)
  data = data or {}
  print(('[OPEN_DAILY_REWARD] state=%s streakDay=%s fromShrine=%s')
    :format(s(data.state), s(data.dayStreakDay), s(data.fromShrine)))
end)
listen('DAILY_REWARD_DAYS_DATA', Game.Events.DAILY_REWARD_DAYS_DATA, function(data)
  data = data or {}
  print(('[DAILY_REWARD_DAYS_DATA] free=%d premium=%d')
    :format(count(data.freeRewards), count(data.premiumRewards)))
end)

-- ---- QUEST LOG ------------------------------------------------------------
listen('QUEST_LOG', Game.Events.QUEST_LOG, function(data)
  data = data or {}
  print(('[QUEST_LOG] quests=%d'):format(count(data.quests)))
end)

-- All event ids must be the exact Zerobot values (sanity-check the enum).
check('STORE_OFFERS id', Game.Events.STORE_OFFERS == 17)
check('IMBUEMENT_DATA id', Game.Events.IMBUEMENT_DATA == 7)
check('OPEN_STASH id', Game.Events.OPEN_STASH == 14)
check('PARTY_HUNT id', Game.Events.PARTY_HUNT == 12)
check('OPEN_DAILY_REWARD id', Game.Events.OPEN_DAILY_REWARD == 18)
check('registered ' .. #regs .. ' listeners', #regs == 9, #regs)

print('[info] test_events_misc.lua armed. Open: Store / Imbue / Stash / Daily')
print('[info] Reward / Quest Log (or be in a Party Hunt). Listening ~60s.')

-- Watchdog: unregister all, report which ones actually fired, print summary.
-- NOTE: this Timer port does NOT pass the instance to the callback, so we
-- capture the handle in `stopTimer` and stop THAT (not a `self` arg).
local stopTimer
stopTimer = Timer('test_events_misc.stop', function()
  for i = 1, #regs do
    Game.unregisterEvent(regs[i].id, regs[i].fn)
  end
  local firedList = {}
  for i = 1, #regs do
    local n = regs[i].name
    firedList[#firedList + 1] = n .. '=' .. tostring(seen[n] or 0)
  end
  print('[info] fired counts: ' .. table.concat(firedList, ', '))
  check('all listeners unregistered cleanly', true)
  if stopTimer then stopTimer:destroy() end
  print(('--- events_misc: %d passed, %d failed ---'):format(pass, fail))
end, 60000, true)
