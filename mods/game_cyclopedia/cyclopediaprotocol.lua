-- Cyclopedia protocol adapter for crystalserver (Canary-style native opcodes).
--
-- This file used to be a shim for a legacy custom server protocol (client->server
-- opcodes 0x48-0x4D with a single 0x48 response opcode). crystalserver speaks the
-- native CIP cyclopedia protocol instead:
--   requests:  0xE1 races+charms, 0xE2 creatures, 0xE3 monster data, 0xE4 charm
--              action, 0x2A tracker toggle, 0xAE bosstiary, 0xAF bosstiary slots,
--              0xB0 bosstiary slot action, 0xE5 character info, 0xAD house auction
--   responses: 0xD5 races, 0xD6 creatures, 0xD7 monster data, 0xD8 charms,
--              0x61 bosstiary thresholds, 0x62 bosstiary slots, 0x73 bosstiary
--              entries, 0xBD boss cooldowns, 0xE6 bosstiary entry changed,
--              0xDA character info (per sub-type), 0xC7 house list, 0xC3 house
--              auction message
-- Response handlers are registered via ProtocolGame.registerOpcode, which takes
-- precedence over the C++ parse switch (ProtocolGame::onOpcode runs first), so the
-- legacy C++ stubs for 0x61/0x62/0x73/0xBD never run while these are registered.
-- The 0xDA handler shadows the C++ parseCyclopedia the same way; for sub-types it
-- does not know it raises an error so the read position is restored and the C++
-- fallback behaves exactly as before this port.
-- All wire layouts below were verified against crystalserver protocolgame.cpp.

local CyclopediaProtocol = {}

-- crystalserver server->client opcodes
local RESP_BESTIARY_RACES   = 0xD5
local RESP_BESTIARY_MONSTERS = 0xD6
local RESP_BESTIARY_MONSTER = 0xD7
local RESP_CHARMS           = 0xD8
local RESP_BOSSTIARY_DATA   = 0x61
local RESP_BOSSTIARY_SLOTS  = 0x62
local RESP_BOSSTIARY_LIST   = 0x73
local RESP_BOSS_COOLDOWN    = 0xBD
local RESP_BOSS_ENTRY_CHANGED = 0xE6
local RESP_CHARACTER_INFO   = 0xDA
local RESP_HOUSE_MESSAGE    = 0xC3
local RESP_HOUSE_LIST       = 0xC7

local registered = false

local function sendMessage(msg)
  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    protocolGame:send(msg)
  end
end

-- {[raceId] = {name, looktype, auxId, head, body, legs, feet, addons}} from staticdata.
-- Cached keyed by client version: the C++ call rebuilds and pushes the full
-- ~2-3k monster map every time, and assets reload on a version switch.
local cachedMonsterList, cachedForVersion
local function monsterInfo(raceId)
  local version = g_game.getClientVersion()
  if not cachedMonsterList or cachedForVersion ~= version then
    local list = g_things.getMonsterList()
    -- never pin an empty list (failed staticdata load): retry next call
    if next(list) ~= nil then
      cachedMonsterList = list
      cachedForVersion = version
    end
  end
  local entry = cachedMonsterList and cachedMonsterList[raceId]
  if not entry then
    return tostring(raceId), {}
  end
  local outfit = {
    type = entry[2] or 0, auxType = entry[3] or 0,
    head = entry[4] or 0, body = entry[5] or 0,
    legs = entry[6] or 0, feet = entry[7] or 0,
    addons = entry[8] or 0
  }
  return entry[1] or tostring(raceId), outfit
end

--------------------------------------------------------------------------------
-- Response parsers (crystalserver wire layouts)
--------------------------------------------------------------------------------

-- 0xD5: race/class list. [U16 raceCount, {String className, U16 total, U16 known}*]
local function parseBestiaryRaces(protocolGame, msg)
  local groups = {}
  local count = msg:getU16()
  for i = 1, count do
    groups[#groups + 1] = {
      name = msg:getString(),
      amount = msg:getU16(),
      know = msg:getU16()
    }
  end
  signalcall(g_game.updateBestiaryGroup, groups)
end

-- 0xD6: creatures of a race/search. [String raceName, U16 count, {U16 raceId,
-- U8 progress, if progress>0: U8 occurrence, U16 animusBonus}*, U16 animusPoints]
-- progress 0 = unknown (zero kills); IOBestiary::getKillStatus returns 1..4 otherwise.
local function parseBestiaryMonsters(protocolGame, msg)
  local name = msg:getString()
  local count = msg:getU16()
  local monsters = {}
  for i = 1, count do
    local raceId = msg:getU16()
    local progress = msg:getU8()
    if progress > 0 then
      msg:getU8() -- occurrence
    end
    local animusBonus = msg:getU16() -- (multiplier-1)*1000 -> /10 = percent
    monsters[#monsters + 1] = { raceId, progress, animusBonus / 10 }
  end
  local masteryPoints = msg:getU16()
  signalcall(g_game.updateBestiaryOverview, name, monsters, masteryPoints)
end

-- 0xD7: full bestiary entry for one monster.
local function parseBestiaryMonster(protocolGame, msg)
  local raceId = msg:getU16()
  msg:getString() -- class name
  local currentLevel = msg:getU8()
  local animusBonus = msg:getU16()
  local masteryPoints = msg:getU16()
  local killCounter = msg:getU32()
  local firstUnlock = msg:getU16()
  local secondUnlock = msg:getU16()
  local thirdUnlock = msg:getU16()
  local stars = msg:getU8()
  local occurrence = msg:getU8()

  local bestiaryMonster = {
    loot = {},
    difficultyCharm = 0,
    attackMode = 0,
    health = 0,
    experience = 0,
    speed = 0,
    armor = 0,
    mitigation = 0,
    elements = {},
    location = ""
  }

  local lootCount = msg:getU8()
  for i = 1, lootCount do
    local itemId = msg:getItemId() -- server addItemId, u32
    local difficulty = msg:getU8()
    local specialEvent = msg:getU8()
    local lootName = ""
    local stackable = false
    -- Server sends name+countmax only when the item is visible (itemId != 0).
    if itemId ~= 0 then
      lootName = msg:getString()
      stackable = msg:getU8() == 1
    end
    bestiaryMonster.loot[#bestiaryMonster.loot + 1] = {
      item = itemId,
      difficulty = difficulty,
      specialEvent = specialEvent,
      name = lootName,
      stackable = stackable
    }
  end

  if currentLevel > 1 then
    bestiaryMonster.difficultyCharm = msg:getU16() -- charm points
    bestiaryMonster.attackMode = msg:getU8()
    msg:getU8() -- constant 0x02
    bestiaryMonster.health = msg:getU32()
    bestiaryMonster.experience = msg:getU32()
    bestiaryMonster.speed = msg:getU16()
    bestiaryMonster.armor = msg:getU16()
    bestiaryMonster.mitigation = msg:getDouble()
  end

  if currentLevel > 2 then
    local elementCount = msg:getU8()
    for i = 1, elementCount do
      bestiaryMonster.elements[#bestiaryMonster.elements + 1] = {
        element = msg:getU8(),
        percent = msg:getU16()
      }
    end
    local locationCount = msg:getU16()
    local locations = {}
    for i = 1, locationCount do
      locations[#locations + 1] = msg:getString()
    end
    bestiaryMonster.location = table.concat(locations, "\n")
  end

  signalcall(g_game.updateBestiaryMonsterData, raceId, bestiaryMonster, currentLevel,
    killCounter, firstUnlock, secondUnlock, thirdUnlock, stars, occurrence,
    animusBonus / 10, masteryPoints)
end

-- 0xD8: charms. [U64 resetCost, U8 charmCount, per charm: U8 id, (unlocked: U8 tier,
-- U8 assigned, if assigned: U16 raceId + U32 removeCost | locked: U8 0, U8 0),
-- U8 availableSlots, U16 assignableCount, {U32 raceId}*]. The trailing U32 list is
-- the assignable-creature set (bestiary second unlock reached, minus raceIds already
-- carrying a major+minor charm) and is passed as the 4th onCharmData argument.
-- Note: charm points/echoes arrive separately via the native 0xEE resource packets.
local function parseCharms(protocolGame, msg)
  local resetAllPrice = msg:getU64()
  local charmCount = msg:getU8()
  local charmData = {}

  for i = 1, charmCount do
    local charmId = msg:getU8()
    local tier = msg:getU8()
    local assigned = msg:getU8()
    local assignedRaceId = 0
    local removePrice = 0
    if assigned == 1 then
      assignedRaceId = msg:getU16()
      removePrice = msg:getU32()
    end
    -- tier==0 with no assignment is indistinguishable from locked on the wire;
    -- treat an assignment or tier>0 as unlocked.
    local unlocked = (assigned == 1) or (tier > 0)
    charmData[#charmData + 1] = {
      id = charmId,
      level = unlocked and math.max(tier, 1) or 0,
      creatureId = assignedRaceId,
      removePrice = removePrice
    }
  end

  local emptySlots = msg:getU8()
  local assignable = {}
  local assignableCount = msg:getU16()
  for i = 1, assignableCount do
    assignable[msg:getU32()] = true
  end

  signalcall(g_game.onCharmData, resetAllPrice, charmData, emptySlots, assignable)
end

-- 0x61: bosstiary thresholds. 18x U16: kills {bane, archfoe, nemesis}x3 then
-- points {bane, archfoe, nemesis}x3.
local function parseBosstiaryData(protocolGame, msg)
  local killData = {}
  for i = 1, 3 do
    killData[i] = { msg:getU16(), msg:getU16(), msg:getU16() }
  end
  local rewardData = {}
  for i = 1, 3 do
    rewardData[i] = { msg:getU16(), msg:getU16(), msg:getU16() }
  end
  signalcall(g_game.onBosstiaryBaseData, killData, rewardData)
end

-- helper: the 7 "slot bytes" crystalserver emits for an occupied bosstiary slot.
local function readBosstiarySlotBytes(msg, slot)
  slot.category = msg:getU8()
  slot.kills = msg:getU32()
  slot.bonusLoot = msg:getU16()
  slot.bonusKill = msg:getU8()
  msg:getU8() -- category duplicate
  slot.removeGold = msg:getU32()
  slot.isBoosted = msg:getU8() == 1
end

-- 0x62: bosstiary slots window.
local function parseBosstiarySlots(protocolGame, msg)
  local points = msg:getU32()
  local pointsNext = msg:getU32()
  local bonusLoot = msg:getU16()
  local bonusNext = msg:getU16()

  local slots = {}
  for i = 1, 3 do
    local slot = {
      state = msg:getU8(),
      raceID = msg:getU32(),
      category = 0, kills = 0, bonusLoot = 0, bonusKill = 0,
      removeGold = 0, isBoosted = (i == 3)
    }
    -- Server only writes the slot bytes when the slot is unlocked AND occupied.
    if slot.state == 1 and slot.raceID ~= 0 then
      readBosstiarySlotBytes(msg, slot)
    end
    slots[i] = slot
  end

  local unlockedCreatures = {}
  if msg:getU8() == 1 then
    local count = msg:getU16()
    for i = 1, count do
      local bossId = msg:getU32()
      local category = msg:getU8()
      unlockedCreatures[bossId] = category
    end
  end

  signalcall(g_game.onBosstiarySlotsData, points, pointsNext, bonusLoot, bonusNext,
    slots, unlockedCreatures)
end

-- 0x73: full bosstiary list. [U16 count, {U32 raceId, U8 category, U32 kills,
-- U8 unused, U8 isOnTracker}*]. The window code resolves outfits itself
-- (configureBossList fills entry[5] from g_things.getMonsterList()).
local function parseBosstiaryList(protocolGame, msg)
  local data = {}
  local count = msg:getU16()
  for i = 1, count do
    local bossId = msg:getU32()
    local category = msg:getU8()
    local kills = msg:getU32()
    msg:getU8() -- unused
    local tracked = msg:getU8()
    data[#data + 1] = { bossId, category, kills, tracked }
  end
  signalcall(g_game.onBosstiaryWindowData, data)
end

-- 0xBD: boss cooldowns. [U16 count, {U32 bossRaceId, U64 expiryTimestamp}*].
-- Server timestamps are in milliseconds (OTSYS_TIME); the analyser works in
-- seconds. Name/outfit are resolved locally from staticdata.
local function parseBossCooldown(protocolGame, msg)
  local cooldown = {}
  local count = msg:getU16()
  for i = 1, count do
    local bossId = msg:getU32()
    local expiry = msg:getU64()
    if expiry > 1e12 then -- ms -> s
      expiry = math.floor(expiry / 1000)
    end
    local name, outfit = monsterInfo(bossId)
    cooldown[#cooldown + 1] = { bossId, expiry, name, outfit }
  end
  signalcall(g_game.onBossCooldown, cooldown)
end

-- 0xE6: bosstiary entry changed (sent when a boss kill changes rank). The client
-- maps 0xE6 to a legacy prey opcode in C++, so consuming it here both fixes the
-- would-be desync and exposes the event.
local function parseBossEntryChanged(protocolGame, msg)
  local bossId = msg:getU32()
  signalcall(g_game.onBosstiaryEntryChanged, bossId)
end

--------------------------------------------------------------------------------
-- Character info 0xDA (crystalserver sendCyclopediaCharacter* family)
--
-- Wire: [U8 infoType][U8 errorCode], payload only when errorCode == 0.
-- Sub-types ported here (validated against crystalserver protocolgame.cpp):
--   0 base information, 1 general stats, 3 recent deaths, 4 recent pvp kills,
--   5 achievements, 6 item summary, 7 outfits/mounts, 9 inspection, 11 titles,
--   13 offence stats, 14 defence stats, 15 misc stats.
-- Sub-types deliberately NOT ported (the 0xE5 sender whitelist below never
-- requests them, so their responses can never arrive solicited):
--   2  COMBATSTATS    - unused on the server (replies NoData only)
--   8/10/12           - never requested by the mod (store summary/badges/wheel)
--
-- Unsolicited 0xDA pushes exist server-side: gem-bag moves resend 1/13/14/15 and
-- title changes resend 0/11. All ported sub-types are therefore parsed whenever
-- they arrive (stream integrity), but events for panel-building handlers are only
-- emitted when the mod actually requested that sub-type (pending counters below);
-- 0/1 are safe to emit always (their handlers only store data / have no UI).
--------------------------------------------------------------------------------

-- 13/14/15 percentages come as fractions (0.05 = 5%); the panels print "+X%".
local function pct(v)
  return math.floor(v * 100 * 100 + 0.5) / 100
end

local pendingCharacterInfo = {}

local function takePendingCharacterInfo(infoType)
  local n = pendingCharacterInfo[infoType]
  if n and n > 0 then
    pendingCharacterInfo[infoType] = n - 1
    return true
  end
  return false
end

-- Server AddOutfit(msg, outfit, addMount=false): U16 lookType; lookType != 0 ->
-- head/body/legs/feet/addons U8; else U16 lookTypeEx. No mount bytes.
local function readOutfit(msg)
  local outfit = {type = 0, auxType = 0, head = 0, body = 0, legs = 0, feet = 0, addons = 0, mount = 0}
  outfit.type = msg:getU16()
  if outfit.type ~= 0 then
    outfit.head = msg:getU8()
    outfit.body = msg:getU8()
    outfit.legs = msg:getU8()
    outfit.feet = msg:getU8()
    outfit.addons = msg:getU8()
  else
    outfit.auxType = msg:getU16()
  end
  return outfit
end

-- ids the mod's SkillNames table knows; anything else (e.g. 0 sent for wands)
-- falls back to 1 = Magic Level so the panel's string concat cannot error.
local knownSkillNameIds = {[1] = true, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true, [11] = true}
local function safeSkillId(id)
  if knownSkillNameIds[id] then
    return id
  end
  return 1
end

-- 0xDA/0: [str name][str vocation][U16 level][outfit][U8 flag][str title]
local function parseCharBaseInformation(protocolGame, msg, emit)
  local name = msg:getString()
  local vocation = msg:getString()
  local level = msg:getU16()
  local outfit = readOutfit(msg)
  msg:getU8() -- store summary & character titles flag (server hardcodes 0x01)
  local title = msg:getString()
  -- always emitted: the handler only caches basePlayerData, and unsolicited
  -- resends (title change) keep it fresh
  signalcall(g_game.onCyclopediaBaseInformation, name, vocation, level, outfit, title)
end

-- 0xDA/1: general stats. Mirrors the (already validated) C++ parseCyclopedia
-- consumption; emitted as a single table since no mod handler consumes it yet.
local function parseCharGeneralStats(protocolGame, msg, emit)
  local stats = {}
  stats.experience = msg:getU64()
  stats.level = msg:getU16()
  stats.levelPercent = msg:getU16() / 100
  stats.baseXpGain = msg:getU16()
  stats.lowLevelBonus = msg:getU16()
  stats.xpBoost = msg:getU16()
  stats.staminaMultiplier = msg:getU16()
  stats.xpBoostRemainingTime = msg:getU16()
  stats.canBuyXpBoost = msg:getU8() == 0
  stats.health = msg:getU32()
  stats.maxHealth = msg:getU32()
  stats.mana = msg:getU32()
  stats.maxMana = msg:getU32()
  stats.soul = msg:getU8()
  stats.stamina = msg:getU16()
  stats.food = msg:getU16()
  stats.offlineTraining = msg:getU16()
  stats.speed = msg:getU16()
  stats.baseSpeed = msg:getU16()
  stats.capacity = msg:getU32()
  stats.baseCapacity = msg:getU32()
  stats.freeCapacity = msg:getU32()
  msg:getU8() -- 8 (hardcoded)
  msg:getU8() -- 1 (hardcoded)
  stats.magicLevel = msg:getU16()
  stats.baseMagicLevel = msg:getU16()
  stats.loyaltyMagicLevel = msg:getU16()
  stats.magicLevelPercent = msg:getU16() / 100
  stats.skills = {}
  for _ = 1, 7 do -- hardcoded skill ids {11,9,8,10,7,6,13}
    local skillId = msg:getU8()
    stats.skills[skillId] = {
      level = msg:getU16(),
      base = msg:getU16(),
      loyalty = msg:getU16(),
      percent = msg:getU16() / 100
    }
  end
  stats.specialSkills = {}
  local combatCount = msg:getU8()
  for _ = 1, combatCount do
    local element = msg:getU8()
    stats.specialSkills[element] = msg:getU16()
  end
  signalcall(g_game.onCyclopediaCharacterGeneralStats, stats)
end

-- 0xDA/3: [U16 page][U16 pages][U16 count]{U32 timestamp, str cause}*
-- The mod handler expects deaths as a {timestamp -> cause} map.
local function parseCharRecentDeaths(protocolGame, msg, emit)
  local page = msg:getU16()
  local pages = msg:getU16()
  local count = msg:getU16()
  local deaths = {}
  for _ = 1, count do
    local timestamp = msg:getU32()
    deaths[timestamp] = msg:getString()
  end
  if emit then
    signalcall(g_game.onCyclopediaRecentDeath, page, pages, deaths)
  end
end

-- 0xDA/4: [U16 page][U16 pages][U16 count]{U32 timestamp, str description,
-- U8 status}*. The mod handler expects an array of {timestamp, name, status}.
local function parseCharRecentPvpKills(protocolGame, msg, emit)
  local page = msg:getU16()
  local pages = msg:getU16()
  local count = msg:getU16()
  local kills = {}
  for i = 1, count do
    local timestamp = msg:getU32()
    local description = msg:getString()
    local status = msg:getU8()
    kills[i] = {timestamp, description, status}
  end
  if emit then
    signalcall(g_game.onCyclopediaPvpDeath, page, pages, kills)
  end
end

-- 0xDA/5: achievements (sendCyclopediaCharacterAchievements). [U16 points]
-- [U16 secretsUnlocked][U16 count]{U16 id, U32 timestamp, U8 isSecret,
-- if isSecret==1: str name, str description, U8 grade}*. Non-secret entries
-- carry only id+timestamp; name/description/grade come from staticdata via
-- g_things.getAchievementList(). Result is keyed by id because the panel's
-- locked/all filters index achievementsList[achievement.id].
local function parseCharAchievements(protocolGame, msg, emit)
  local points = msg:getU16()
  local secretsUnlocked = msg:getU16()
  local count = msg:getU16()
  local staticList = g_things.getAchievementList()
  local achievements = {}
  for _ = 1, count do
    local id = msg:getU16()
    local timestamp = msg:getU32()
    local secret = msg:getU8() == 1
    local name, description, grade
    if secret then
      name = msg:getString()
      description = msg:getString()
      grade = msg:getU8()
    else
      local entry = staticList[id]
      if entry then
        name = entry.name
        description = entry.description
        grade = entry.grade
      else
        name = "Achievement #" .. id
        description = ""
        grade = 1
      end
    end
    achievements[id] = {
      id = id, name = name, description = description,
      grade = grade, secret = secret, timestamp = timestamp
    }
  end
  if emit then
    signalcall(g_game.onCyclopediaAchievements, points, secretsUnlocked, achievements)
  end
end

-- 0xDA/6 helper: one item summary section, [U16 count]{U16 itemId, [U8 tier -
-- present ONLY when the item's upgrade classification > 0, the stash section
-- included (the server writes a hardcoded 0x00 there)], U32 count}*. The
-- ThingType classification gate is the same one the live C++ getItem path
-- uses, already proven byte-exact against this server.
local function readItemSummarySection(msg, isStash)
  local entries = {}
  local count = msg:getU16()
  for i = 1, count do
    local itemId = msg:getItemId() -- server addItemId, u32
    local tier = 0
    if g_things.getThingType(itemId):getClassification() > 0 then
      tier = msg:getU8()
    end
    local amount = msg:getU32()
    if isStash then
      -- the panel reads stash entries as {itemId, count} (data[2])
      entries[i] = {itemId, amount}
    else
      -- the panel reads {itemId, tier, count} (data[1]/data[3])
      entries[i] = {itemId, tier, amount}
    end
  end
  return entries
end

-- 0xDA/6: item summary (sendCyclopediaCharacterItemSummary). Five sections in
-- wire order: inventory, store inbox, stash, depot box, inbox.
local function parseCharItemSummary(protocolGame, msg, emit)
  local inventory = readItemSummarySection(msg, false)
  local store = readItemSummarySection(msg, false)
  local stash = readItemSummarySection(msg, true)
  local depot = readItemSummarySection(msg, false)
  local inbox = readItemSummarySection(msg, false)
  if emit then
    signalcall(g_game.onCyclopediaItemSummary, inventory, store, stash, depot, inbox)
  end
end

-- 0xDA/7: appearances (sendCyclopediaCharacterOutfitsMounts).
-- [U16 outfitCount]{U16 lookType, str name, U8 addons, U8 type (0 standard/
-- 1 quest/2 store), U32 1000-if-current-else-0}*, then 4x U8 current outfit
-- colors ONLY when outfitCount > 0; mounts repeat the shape without addons
-- ({U16 clientId, str name, U8 type, U32 1000}* + conditional 4x U8 mount
-- colors); familiars likewise but with no trailing color block at all.
local function parseCharAppearances(protocolGame, msg, emit)
  local outfits = {}
  local outfitCount = msg:getU16()
  for i = 1, outfitCount do
    local lookType = msg:getU16()
    local name = msg:getString()
    local addons = msg:getU8()
    local outfitType = msg:getU8()
    msg:getU32() -- 1000 for the currently worn outfit, 0 otherwise (unused)
    outfits[i] = {lookType, name, addons, outfitType}
  end
  local outfitColors = {}
  if outfitCount > 0 then
    outfitColors[1] = {msg:getU8(), msg:getU8(), msg:getU8(), msg:getU8()}
  end

  local mounts = {}
  local mountCount = msg:getU16()
  for i = 1, mountCount do
    local clientId = msg:getU16()
    local name = msg:getString()
    local mountType = msg:getU8()
    msg:getU32() -- server hardcodes 1000 (unused)
    mounts[i] = {clientId, name, mountType}
  end
  local mountColors = {}
  if mountCount > 0 then
    mountColors[1] = {msg:getU8(), msg:getU8(), msg:getU8(), msg:getU8()}
  end

  local familiars = {}
  local familiarCount = msg:getU16()
  for i = 1, familiarCount do
    local lookType = msg:getU16()
    local name = msg:getString()
    local familiarType = msg:getU8()
    msg:getU32() -- server hardcodes 0 (unused)
    familiars[i] = {lookType, name, familiarType}
  end

  if emit then
    signalcall(g_game.onCyclopediaAppearances, outfits, outfitColors, mounts,
      mountColors, familiars)
  end
end

-- 0xDA/9: inspection. [U8 itemCount]{U8 slot, str name, AddItem, U8 imbCount
-- {U16 icon}*, U8 descCount {str,str}*}* [str playerName][outfit]
-- [U8 infoCount]{str detail, str description}*
-- AddItem is consumed by the C++ ProtocolGame:getItem (Lua-bound), which already
-- mirrors the crystalserver AddItem schema byte-for-byte.
local function parseCharInspection(protocolGame, msg, emit)
  local itemCount = msg:getU8()
  local items = {}
  for _ = 1, itemCount do
    local slot = msg:getU8()
    local name = msg:getString()
    local item = protocolGame:getItem(msg, 0, true)
    local imbuements = {}
    local imbuementCount = msg:getU8()
    for j = 1, imbuementCount do
      imbuements[j] = msg:getU16()
    end
    local descriptions = {}
    local descriptionCount = msg:getU8()
    for j = 1, descriptionCount do
      local key = msg:getString()
      local value = msg:getString()
      descriptions[j] = {key, value}
    end
    items[slot] = {item = item, name = name, imbuements = imbuements, descriptions = descriptions}
  end
  local playerName = msg:getString()
  local outfit = readOutfit(msg)
  local playerInfo = {}
  local infoCount = msg:getU8()
  for i = 1, infoCount do
    local detail = msg:getString()
    local description = msg:getString()
    playerInfo[i] = {detail = detail, description = description}
  end
  if emit then
    signalcall(g_game.onCyclopediaInspect, items, playerName, outfit, playerInfo)
  end
end

-- 0xDA/11: [U8 currentTitle][U8 count]{U8 id, str name, str description,
-- U8 permanent, U8 unlocked}*
local function parseCharTitles(protocolGame, msg, emit)
  local currentTitle = msg:getU8()
  local count = msg:getU8()
  local list = {}
  for i = 1, count do
    local id = msg:getU8()
    local name = msg:getString()
    local description = msg:getString()
    local permanent = msg:getU8() == 1
    local unlocked = msg:getU8() == 1
    list[i] = {id = id, name = name, description = description, permanent = permanent, unlocked = unlocked}
  end
  if emit then
    signalcall(g_game.onCyclopediaTitles, currentTitle, list)
  end
end

-- Server addCyclopediaSkills block: total, [flat (crit only)], equipment,
-- imbuement, wheel, [event (leech) | concoction (crit)] - all doubles.
local function readOffenceSkillBlock(msg, isCrit)
  local block = {fromFlatBonus = 0, fromEvent = 0, fromConcoction = 0}
  block.skillPercent = pct(msg:getDouble())
  if isCrit then
    block.fromFlatBonus = pct(msg:getDouble())
  end
  block.fromEquipment = pct(msg:getDouble())
  block.fromImbuement = pct(msg:getDouble())
  block.fromSkillWheel = pct(msg:getDouble())
  if isCrit then
    block.fromConcoction = pct(msg:getDouble())
  else
    block.fromEvent = pct(msg:getDouble())
  end
  return block
end

-- 0xDA/13: offence stats (sendCyclopediaCharacterOffenceStats). Also pushed
-- unsolicited on gem-bag changes - hence parse always, emit only on request.
local function parseCharOffenceStats(protocolGame, msg, emit)
  local critChance = readOffenceSkillBlock(msg, true)
  local critDamage = readOffenceSkillBlock(msg, true)
  local lifeLeech = readOffenceSkillBlock(msg, false)
  local manaLeech = readOffenceSkillBlock(msg, false)

  -- onslaught (forge weapon tier): total/base/bonus/0 - not displayed by the mod
  msg:getDouble()
  msg:getDouble()
  msg:getDouble()
  msg:getDouble()

  local cleavePercent = pct(msg:getDouble()) -- server hardcodes 0 (system removed)

  local perfectShot = {}
  for range = 1, 7 do
    perfectShot[range] = msg:getU16()
  end

  local flatTotal = msg:getU16()  -- flat damage and healing total
  local flatBase = msg:getU16()   -- from character level
  local flatWheel = msg:getU16()  -- server hardcodes 0

  -- weapon block: identical shape for wand/distance/melee/fist branches
  local attackData = {}
  attackData.value = msg:getU16()
  attackData.valueFlat = msg:getU16()
  attackData.valueEquipment = msg:getU16()
  attackData.valueSkill = safeSkillId(msg:getU8())
  attackData.valueFromSkill = msg:getU16()
  attackData.valueMastery = msg:getU16()
  attackData.valueElement = msg:getU8()
  attackData.valueConverted = pct(msg:getDouble())
  attackData.valueConvertedElement = msg:getU8()

  local distanceFactor = {}
  local accuracyCount = msg:getU8() -- only distance weapons send entries
  for _ = 1, accuracyCount do
    local range = msg:getU8()
    distanceFactor[range] = pct(msg:getDouble())
  end

  -- trailing block: the server hardcodes zeros for everything below (verified in
  -- sendCyclopediaCharacterOffenceStats); consume exactly and hand the panels
  -- empty/zero structures
  msg:getDouble()
  msg:getU16()
  msg:getU8()
  msg:getDouble()
  msg:getDouble()
  msg:getU8()
  msg:getDouble()
  msg:getDouble()
  local healPerks = {
    manaOnHit = msg:getU16(),
    manaOnKill = msg:getU16(),
    healthOnHit = msg:getU16(),
    healthOnKill = msg:getU16()
  }
  msg:getU8()
  msg:getU8()
  msg:getU8()
  -- Winter Update 2025 padding
  msg:getDouble()
  msg:getDouble()
  msg:getDouble()
  msg:getU8()

  if emit then
    signalcall(g_game.onCyclopediaOffence,
      {lifeLeech, manaLeech, critChance, critDamage},
      cleavePercent, perfectShot, flatTotal, flatBase, flatWheel,
      attackData, distanceFactor,
      {powerfulFoeDamage = 0, bestiaryDamage = {}},
      {runeCritical = 0, meleeCritical = 0, elementMap = {}},
      {runeCritical = 0, meleeCritical = 0, elementMap = {}},
      healPerks, {}, {}, {})
  end
end

-- 0xDA/14: defence stats (sendCyclopediaCharacterDefenceStats). Also pushed
-- unsolicited on gem-bag changes.
local function parseCharDefenceStats(protocolGame, msg, emit)
  local dodgeData = {}
  dodgeData.skillPercent = pct(msg:getDouble())
  dodgeData.fromEquipment = pct(msg:getDouble())
  dodgeData.fromAmplification = pct(msg:getDouble())
  dodgeData.fromEvent = pct(msg:getDouble()) -- server hardcodes 0
  dodgeData.fromSkillWheel = pct(msg:getDouble())

  local shieldCapacity = msg:getU32()
  local shieldDirect = msg:getU16()
  local shieldPercentage = pct(msg:getDouble())

  local damageReflect = msg:getU16()
  local armor = msg:getU16()
  local mantra = msg:getU16()

  local defenseData = {}
  defenseData.value = msg:getU16()
  defenseData.valueEquipment = msg:getU16()
  defenseData.valueSkill = safeSkillId(msg:getU8()) -- 0x06 = Shielding
  defenseData.valueFromSkill = msg:getU16()
  defenseData.valueMastery = msg:getU16()
  defenseData.valueCombatTatcis = 0 -- removed from the 15.25 wire payload

  local mitigationData = {}
  mitigationData.skillPercent = pct(msg:getDouble())
  mitigationData.fromDefense = pct(msg:getDouble())
  mitigationData.fromEquipment = pct(msg:getDouble())
  mitigationData.fromShielding = pct(msg:getDouble())
  mitigationData.fromSkillWheel = pct(msg:getDouble())
  mitigationData.fromCombatTatics = 0 -- removed from the 15.25 wire payload

  -- per combat: U8 0x04 marker, U8 cipbia element (0..11), double modifier
  local elementalProtections = {}
  local combats = msg:getU8()
  for _ = 1, combats do
    msg:getU8() -- 0x04 marker
    local element = msg:getU8()
    elementalProtections[element + 1] = pct(msg:getDouble())
  end

  if emit then
    signalcall(g_game.onCyclopediaDefence, dodgeData, shieldCapacity, shieldDirect,
      shieldPercentage, damageReflect, armor, defenseData, mitigationData,
      elementalProtections, mantra)
  end
end

-- 0xDA/15: misc stats (sendCyclopediaCharacterMiscStats). Also pushed
-- unsolicited on gem-bag changes.
local function parseCharMiscStats(protocolGame, msg, emit)
  local momentum = {}
  momentum.skillPercent = pct(msg:getDouble())
  momentum.fromEquipment = pct(msg:getDouble())
  momentum.fromAmplification = pct(msg:getDouble())
  momentum.fromSkillWheel = pct(msg:getDouble())
  momentum.fromEvent = pct(msg:getDouble()) -- server hardcodes 0

  local transcendence = {}
  transcendence.skillPercent = pct(msg:getDouble())
  transcendence.fromEquipment = pct(msg:getDouble())
  transcendence.fromAmplification = pct(msg:getDouble())
  transcendence.fromEvent = pct(msg:getDouble())

  local amplification = {}
  amplification.skillPercent = pct(msg:getDouble())
  amplification.fromEquipment = pct(msg:getDouble())
  amplification.fromEvent = pct(msg:getDouble()) -- server hardcodes 0

  local currentBless = msg:getU8()
  local maxBless = msg:getU8()

  local concoctions = {}
  local concoctionCount = msg:getU8()
  for _ = 1, concoctionCount do
    local itemId = msg:getItemId() -- server addItemId, u32
    msg:getU8() -- constant 0
    msg:getU8() -- constant 0
    concoctions[itemId] = msg:getU32() -- remaining duration
  end

  -- trailing 4 zero bytes (cooldown block placeholder on the server)
  msg:getU8()
  msg:getU8()
  msg:getU8()
  msg:getU8()

  if emit then
    signalcall(g_game.onCyclopediaMisc, momentum, transcendence, amplification,
      currentBless, maxBless, concoctions, {})
  end
end

local characterInfoParsers = {
  [0] = parseCharBaseInformation,
  [1] = parseCharGeneralStats,
  [3] = parseCharRecentDeaths,
  [4] = parseCharRecentPvpKills,
  [5] = parseCharAchievements,
  [6] = parseCharItemSummary,
  [7] = parseCharAppearances,
  [9] = parseCharInspection,
  [11] = parseCharTitles,
  [13] = parseCharOffenceStats,
  [14] = parseCharDefenceStats,
  [15] = parseCharMiscStats,
}

local function parseCharacterInfo(protocolGame, msg)
  local infoType = msg:getU8()
  local errorCode = msg:getU8()
  if errorCode ~= 0 then
    -- [type][error] only: 1 = no data, 2 = not allowed, 3 = no inspect
    takePendingCharacterInfo(infoType)
    return
  end
  local parser = characterInfoParsers[infoType]
  if not parser then
    -- Never requested by us and not pushed by the server for these sub-types.
    -- Raise: callLuaField logs the error and restores the read position, so the
    -- C++ parseCyclopedia fallback handles the opcode exactly as before.
    error("cyclopedia: unhandled 0xDA character info type " .. infoType)
  end
  -- drain a pending request slot first so 0/1 (always emitted) also account
  local emit = takePendingCharacterInfo(infoType)
  if infoType == 0 or infoType == 1 then
    emit = true
  end
  parser(protocolGame, msg, emit)
end

--------------------------------------------------------------------------------
-- Houses (crystalserver house auction)
--------------------------------------------------------------------------------

-- 0xC7: house list (sendCyclopediaHouseList). Per house: U32 clientId, U8 type
-- (server hardcodes 0x01), U8 state (CyclopediaHouseState: 0 available,
-- 2 rented, 3 transfer, 4 move-out), then a state-specific block.
local function parseHouseList(protocolGame, msg)
  local count = msg:getU16()
  local houses = {}
  for i = 1, count do
    local entry = {
      houseId = 0, state = 0, bidderName = "", bidOwner = false, canBidError = 0,
      bidEnd = 0, highestBid = 0, holderLimit = 0, owner = "", ownerError = 0,
      paidUntil = 0, rented = false, scheduleTime = 0, targetPlayer = "",
      transferValue = 0
    }
    entry.houseId = msg:getU32()
    msg:getU8() -- 0x01 = Available, 0x00 = Renovation (server hardcodes 0x01)
    entry.state = msg:getU8()
    if entry.state == 0 then -- available / auctioned
      entry.bidderName = msg:getString()
      entry.bidOwner = msg:getU8() == 1
      entry.canBidError = msg:getU8()
      if #entry.bidderName > 0 then
        entry.bidEnd = msg:getU32()
        entry.highestBid = msg:getU64()
        if entry.bidOwner then
          entry.holderLimit = msg:getU64()
        end
      end
    elseif entry.state == 2 then -- rented
      entry.owner = msg:getString()
      entry.paidUntil = msg:getU32()
      entry.rented = msg:getU8() == 1
      if entry.rented then
        msg:getU8() -- unused
        msg:getU8() -- unused
      end
    elseif entry.state == 3 then -- transfer pending
      entry.owner = msg:getString()
      entry.paidUntil = msg:getU32()
      local isOwner = msg:getU8() == 1
      entry.rented = isOwner
      if isOwner then
        msg:getU8() -- unused
        msg:getU8() -- unused
      end
      entry.scheduleTime = msg:getU32()
      entry.targetPlayer = msg:getString()
      msg:getU8() -- unused
      entry.transferValue = msg:getU64()
      local isNewOwner = msg:getU8() == 1
      if isNewOwner then
        entry.canBidError = msg:getU8() -- accept-transfer disable index
        msg:getU8() -- reject-transfer disable index (server hardcodes 0)
      end
      if isOwner then
        entry.ownerError = msg:getU8() -- cancel-transfer disable index
      end
    elseif entry.state == 4 then -- move out scheduled
      entry.owner = msg:getString()
      entry.paidUntil = msg:getU32()
      local isOwner = msg:getU8() == 1
      entry.rented = isOwner
      if isOwner then
        msg:getU8() -- unused
        msg:getU8() -- unused
        entry.scheduleTime = msg:getU32()
        msg:getU8() -- unused
      else
        entry.scheduleTime = msg:getU32()
      end
    end
    houses[i] = entry
  end
  signalcall(g_game.onRecvHousesData, houses)
end

-- 0xC3: house auction message (sendHouseAuctionMessage). [U32 houseId][U8 type]
-- [U8 index]; for type 1 (bid) a SUCCESS reply prefixes a 0x00 marker before the
-- index ([0x00][0|1]) while failures send the error index directly - bid error
-- indexes are never 0, so a leading 0x00 unambiguously means success.
local function parseHouseMessage(protocolGame, msg)
  local houseId = msg:getU32()
  local messageType = msg:getU8()
  local index = msg:getU8()
  if messageType == 1 and index == 0 then
    index = msg:getU8() -- 0 = holding highest bid, 1 = lower bid
  end
  signalcall(g_game.onRecvHouseMessage, houseId, messageType, index)
end

--------------------------------------------------------------------------------
-- Opcode registration
--------------------------------------------------------------------------------

local opcodeHandlers = {
  [RESP_BESTIARY_RACES] = parseBestiaryRaces,
  [RESP_BESTIARY_MONSTERS] = parseBestiaryMonsters,
  [RESP_BESTIARY_MONSTER] = parseBestiaryMonster,
  [RESP_CHARMS] = parseCharms,
  [RESP_BOSSTIARY_DATA] = parseBosstiaryData,
  [RESP_BOSSTIARY_SLOTS] = parseBosstiarySlots,
  [RESP_BOSSTIARY_LIST] = parseBosstiaryList,
  [RESP_BOSS_COOLDOWN] = parseBossCooldown,
  [RESP_BOSS_ENTRY_CHANGED] = parseBossEntryChanged,
  [RESP_CHARACTER_INFO] = parseCharacterInfo,
  [RESP_HOUSE_LIST] = parseHouseList,
  [RESP_HOUSE_MESSAGE] = parseHouseMessage,
}

function CyclopediaProtocol.register()
  if registered then
    return
  end
  for opcode, handler in pairs(opcodeHandlers) do
    ProtocolGame.unregisterOpcode(opcode)
    ProtocolGame.registerOpcode(opcode, handler)
  end
  pendingCharacterInfo = {}
  registered = true
end

function CyclopediaProtocol.unregister()
  if not registered then
    return
  end
  for opcode in pairs(opcodeHandlers) do
    ProtocolGame.unregisterOpcode(opcode)
  end
  pendingCharacterInfo = {}
  registered = false
end

--------------------------------------------------------------------------------
-- Requests (crystalserver client->server opcodes)
--------------------------------------------------------------------------------

-- 0xE1: request bestiary races; the server replies with 0xD5 and 0xD8.
function CyclopediaProtocol.open()
  local msg = OutputMessage.create()
  msg:addU8(0xE1)
  sendMessage(msg)
end

-- 0xE2 with search=0: creatures of a race by name. Replies 0xD6.
function CyclopediaProtocol.overview(_, className)
  local msg = OutputMessage.create()
  msg:addU8(0xE2)
  msg:addU8(0)
  msg:addString(className or "")
  sendMessage(msg)
end

-- 0xE2 with search=1: creatures by raceId list. Replies 0xD6.
function CyclopediaProtocol.search(list)
  local msg = OutputMessage.create()
  msg:addU8(0xE2)
  msg:addU8(1)
  local ids = {}
  for _, raceId in pairs(list or {}) do
    ids[#ids + 1] = raceId
  end
  msg:addU16(#ids)
  for _, raceId in ipairs(ids) do
    msg:addU16(raceId)
  end
  sendMessage(msg)
end

-- 0xE3: full data for one monster. Replies 0xD7.
function CyclopediaProtocol.monster(raceId)
  local msg = OutputMessage.create()
  msg:addU8(0xE3)
  msg:addU16(raceId)
  sendMessage(msg)
end

-- 0xE4: charm action {U8 action, U8 charmId, U16 raceId}. 0=buy/upgrade,
-- 1=assign, 2=remove, 3=reset all. Server refreshes via a new 0xD8.
local function sendCharmAction(action, charmId, raceId)
  local msg = OutputMessage.create()
  msg:addU8(0xE4)
  msg:addU8(action)
  msg:addU8(charmId)
  msg:addU16(raceId or 0)
  sendMessage(msg)
end

function CyclopediaProtocol.charmUnlock(charmId)
  sendCharmAction(0, charmId, 0)
end

function CyclopediaProtocol.charmSelect(charmId, raceId)
  sendCharmAction(1, charmId, raceId)
end

function CyclopediaProtocol.charmRemove(charmId)
  sendCharmAction(2, charmId, 0)
end

function CyclopediaProtocol.charmResetAll()
  -- the server reads but ignores charmId/raceId for action 3
  sendCharmAction(3, 0, 0)
end

-- 0x2A: toggle bestiary/bosstiary tracker {U16 raceId, U8 enabled}.
function CyclopediaProtocol.tracker(raceId, enabled)
  local msg = OutputMessage.create()
  msg:addU8(0x2A)
  msg:addU16(raceId or 0)
  if enabled == nil then
    enabled = true
  end
  msg:addU8(enabled and 1 or 0)
  sendMessage(msg)
end

-- 0xAE: open bosstiary (replies 0x61 + 0x73).
function CyclopediaProtocol.openBosstiary()
  local msg = OutputMessage.create()
  msg:addU8(0xAE)
  sendMessage(msg)
end

-- 0xAF: open bosstiary slots (replies 0x61 + 0x62).
function CyclopediaProtocol.openBosstiarySlots()
  local msg = OutputMessage.create()
  msg:addU8(0xAF)
  sendMessage(msg)
end

-- 0xB0: bosstiary slot action {U8 slotId, U32 bossId}.
function CyclopediaProtocol.bosstiarySlotAction(slotId, bossId)
  local msg = OutputMessage.create()
  msg:addU8(0xB0)
  msg:addU8(slotId or 0)
  msg:addU32(bossId or 0)
  sendMessage(msg)
end

-- 0xE5: character info request {U32 characterId (0 = self), U8 infoType,
-- [U16 entriesPerPage + U16 page, only for types 3/4]}. Replies 0xDA.
-- HARD RULE: never request a sub-type without a Lua parser for its response -
-- the whitelist is exactly the characterInfoParsers key set, so an unported
-- sub-type results in a blank panel instead of a stream desync.
function CyclopediaProtocol.requestCharacterInfo(infoType, entriesPerPage, page)
  infoType = infoType or 0
  if not characterInfoParsers[infoType] then
    return
  end
  local msg = OutputMessage.create()
  msg:addU8(0xE5)
  msg:addU32(0) -- own character (server substitutes the player id)
  msg:addU8(infoType)
  if infoType == 3 or infoType == 4 then
    -- server clamps entriesPerPage to [5,30] and page to >= 1
    msg:addU16(entriesPerPage or 30)
    msg:addU16(page or 1)
  end
  sendMessage(msg)
  pendingCharacterInfo[infoType] = (pendingCharacterInfo[infoType] or 0) + 1
end

-- 0xAD: house auction action (parseCyclopediaHouseAuction). The mod calls
-- g_game.sendHouseAction(actionType, name, houseId, value):
--   0 town list:        {str townName} ("" = own/bid houses only)
--   1 place bid:        {U32 houseId, U64 bidValue}
--   2 move out:         {U32 houseId, U32 timestamp}
--   3 transfer:         {U32 houseId, U32 timestamp, str newOwner, U64 value}
--   4 cancel move out, 5 cancel transfer, 6 accept transfer,
--   7 reject transfer:  {U32 houseId}
-- The mod's move-out/transfer dialogs are "effective now" (their confirmation
-- text prints os.time()), so that is the timestamp sent.
function CyclopediaProtocol.sendHouseAction(actionType, name, houseId, value)
  actionType = actionType or 0
  local msg = OutputMessage.create()
  msg:addU8(0xAD)
  msg:addU8(actionType)
  if actionType == 0 then
    msg:addString(tostring(name or ""))
  elseif actionType == 1 then
    msg:addU32(houseId or 0)
    msg:addU64(value or 0)
  elseif actionType == 2 then
    msg:addU32(houseId or 0)
    msg:addU32(os.time())
  elseif actionType == 3 then
    msg:addU32(houseId or 0)
    msg:addU32(os.time())
    msg:addString(tostring(name or ""))
    msg:addU64(value or 0)
  elseif actionType >= 4 and actionType <= 7 then
    msg:addU32(houseId or 0)
  else
    return -- unknown action: do not send garbage
  end
  sendMessage(msg)
end

function initCyclopediaProtocol()
  connect(g_game, {
    onGameStart = CyclopediaProtocol.register,
    onGameEnd = CyclopediaProtocol.unregister
  })

  g_game.openCyclopedia = CyclopediaProtocol.open
  g_game.requestCharmData = CyclopediaProtocol.open
  g_game.bestiaryOverview = CyclopediaProtocol.overview
  g_game.bestiaryMonsterData = CyclopediaProtocol.monster
  g_game.bestiarySearch = CyclopediaProtocol.search
  g_game.charmUnlock = CyclopediaProtocol.charmUnlock
  g_game.charmSelect = CyclopediaProtocol.charmSelect
  g_game.charmRemove = CyclopediaProtocol.charmRemove
  g_game.resetAllCharm = CyclopediaProtocol.charmResetAll
  g_game.sendMonsterTracker = CyclopediaProtocol.tracker
  g_game.openBosstiaryWindow = CyclopediaProtocol.openBosstiary
  g_game.openBosstiarySlots = CyclopediaProtocol.openBosstiarySlots
  g_game.sendBosstiarySlotAction = CyclopediaProtocol.bosstiarySlotAction
  g_game.requestCyclopediaData = CyclopediaProtocol.requestCharacterInfo
  g_game.sendHouseAction = CyclopediaProtocol.sendHouseAction

  if g_game.isOnline() then
    CyclopediaProtocol.register()
  end
end

function terminateCyclopediaProtocol()
  disconnect(g_game, {
    onGameStart = CyclopediaProtocol.register,
    onGameEnd = CyclopediaProtocol.unregister
  })
  CyclopediaProtocol.unregister()
end
