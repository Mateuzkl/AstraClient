local CyclopediaProtocol = {}

local OPCODE_INFO = 0x39
local OPCODE_CATEGORY = 0x3A
local OPCODE_MONSTER = 0x3B
local OPCODE_CHARM = 0x3E
local OPCODE_TRACKER = 0x3F
local OPCODE_SEND = 0x39

local RESP_MESSAGE = 0
local RESP_BESTIARY_DATA = 1
local RESP_BESTIARY_OVERVIEW = 2
local RESP_BESTIARY_MONSTER = 3
local RESP_TRACKER = 5
local RESP_BESTIARY_PROGRESS = 6

local registered = false
local monsterCache = {}

local function getStaticCreatureName(raceId)
  local monsters = g_things.getMonsterList()
  local creature = monsters and monsters[tonumber(raceId) or 0]
  return creature and creature[1]
end

local function cacheCreatureInfo(raceId, creature)
  raceId = tonumber(raceId)
  if not raceId or raceId <= 0 or not creature then
    return
  end

  local name = creature.name
  if name == nil or name == "?" then
    local staticName = getStaticCreatureName(raceId)
    if staticName and staticName ~= "" and staticName ~= "?" then
      name = staticName
    end
  end
  name = name or "?"

  monsterCache[raceId] = {
    name,
    creature.type,
    0,
    creature.head,
    creature.body,
    creature.legs,
    creature.feet,
    creature.addons
  }
end

function cacheCyclopediaMonster(raceId, creature)
  if not creature then
    return
  end

  if creature.name then
    cacheCreatureInfo(raceId, creature)
    return
  end

  cacheCreatureInfo(raceId, {
    name = creature[1],
    type = creature[2],
    head = creature[4],
    body = creature[5],
    legs = creature[6],
    feet = creature[7],
    addons = creature[8]
  })
end

function getCyclopediaMonsterList()
  local monsters = g_things.getMonsterList()
  for raceId, creature in pairs(monsterCache) do
    monsters[raceId] = creature
  end
  return monsters
end

function getCyclopediaMonster(raceId)
  return getCyclopediaMonsterList()[tonumber(raceId) or 0]
end

local function sendMessage(msg)
  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    protocolGame:send(msg)
  end
end

local function readCreatureInfo(msg)
  return {
    name = msg:getString(),
    type = msg:getU16(),
    head = msg:getU8(),
    body = msg:getU8(),
    legs = msg:getU8(),
    feet = msg:getU8(),
    addons = msg:getU8()
  }
end

local function parseCharmData(msg)
  local charmBalance = msg:getU32()
  local goldBalance = msg:getU64()
  local charmCount = msg:getU8()
  local charmData = {}
  local monsters = {}

  for i = 1, charmCount do
    local charmId = msg:getU8()
    msg:getString() -- name
    msg:getString() -- description
    msg:getU8() -- type
    msg:getU16() -- price
    local unlocked = msg:getU8() ~= 0
    local assignedRaceId = 0
    local removePrice = 0
    if unlocked then
      local assigned = msg:getU8() ~= 0
      if assigned then
        assignedRaceId = msg:getU16()
        removePrice = msg:getU32()
        cacheCreatureInfo(assignedRaceId, readCreatureInfo(msg))
        monsters[assignedRaceId] = charmId
      end
    else
      msg:getU8()
    end

    charmData[#charmData + 1] = {
      id = charmId,
      level = unlocked and 1 or 0,
      creatureId = assignedRaceId,
      removePrice = removePrice
    }
  end

  msg:getU8()
  local finishedCount = msg:getU16()
  for i = 1, finishedCount do
    local raceId = msg:getU16()
    cacheCreatureInfo(raceId, readCreatureInfo(msg))
  end

  local player = g_game.getLocalPlayer()
  if player and player.setResourceValue then
    player:setResourceValue(ResourceCharmBalance, charmBalance)
    player:setResourceValue(ResourceBank, goldBalance)
  end
  signalcall(g_game.onResourceBalance, ResourceCharmBalance, charmBalance)
  signalcall(g_game.onResourceBalance, ResourceBank, goldBalance)
  signalcall(g_game.onCharmData, 0, charmData, 0xFF, monsters)
end

local function parseBestiaryData(msg)
  local groups = {}
  local count = msg:getU16()
  for i = 1, count do
    groups[#groups + 1] = {
      name = msg:getString(),
      amount = msg:getU16(),
      know = msg:getU16()
    }
  end

  msg:getU8()
  parseCharmData(msg)
  signalcall(g_game.updateBestiaryGroup, groups)
end

local function parseBestiaryOverview(msg)
  local name = msg:getString()
  local count = msg:getU16()
  local monsters = {}
  for i = 1, count do
    local raceId = msg:getU16()
    local progressMarker = msg:getU8()
    local progress = 0
    if progressMarker > 0 then
      progress = msg:getU8()
      cacheCreatureInfo(raceId, readCreatureInfo(msg))
    end
    monsters[#monsters + 1] = { raceId, progress + 1, 0 }
  end
  signalcall(g_game.updateBestiaryOverview, name, monsters, 0)
end

local function parseBestiaryMonster(msg)
  local raceId = msg:getU16()
  msg:getString() -- class
  cacheCreatureInfo(raceId, readCreatureInfo(msg))
  local currentLevel = msg:getU8()
  local killCounter = msg:getU32()
  local firstUnlock = msg:getU16()
  local secondUnlock = msg:getU16()
  local thirdUnlock = msg:getU16()
  local difficulty = msg:getU8()
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
    bestiaryMonster.loot[#bestiaryMonster.loot + 1] = {
      item = msg:getU16(),
      difficulty = msg:getU8(),
      specialEvent = msg:getU8(),
      name = msg:getString(),
      stackable = msg:getU8() > 1
    }
  end

  bestiaryMonster.difficultyCharm = msg:getU16()
  bestiaryMonster.attackMode = msg:getU8()
  msg:getU8()
  bestiaryMonster.health = msg:getU32()
  bestiaryMonster.experience = msg:getU32()
  bestiaryMonster.speed = msg:getU16()
  bestiaryMonster.armor = msg:getU16()

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

  local hasCharm = msg:getU8() ~= 0
  if hasCharm then
    msg:getU8()
    msg:getU32()
  else
    msg:getU8()
  end

  signalcall(g_game.updateBestiaryMonsterData, raceId, bestiaryMonster, currentLevel, killCounter, firstUnlock, secondUnlock, thirdUnlock, difficulty, occurrence - 1, 0, 0)
end

local function parseBestiaryProgress(msg)
  local raceId = msg:getU16()
  local progress = msg:getU8()
  local killCounter = msg:getU32()
  local firstUnlock = msg:getU16()
  local secondUnlock = msg:getU16()
  local thirdUnlock = msg:getU16()
  cacheCreatureInfo(raceId, readCreatureInfo(msg))
  local charmBalance = msg:getU32()
  local goldBalance = msg:getU32()

  local player = g_game.getLocalPlayer()
  if player and player.setResourceValue then
    player:setResourceValue(ResourceCharmBalance, charmBalance)
    player:setResourceValue(ResourceBank, goldBalance)
  end
  signalcall(g_game.onResourceBalance, ResourceCharmBalance, charmBalance)
  signalcall(g_game.onResourceBalance, ResourceBank, goldBalance)

  if Bestiary and Bestiary.updateBestiaryProgress then
    Bestiary.updateBestiaryProgress(raceId, progress, killCounter, firstUnlock, secondUnlock, thirdUnlock)
  end
end

local function parseTracker(msg)
  local tracker = {}
  local count = msg:getU8()
  for i = 1, count do
    local raceId = msg:getU16()
    cacheCreatureInfo(raceId, readCreatureInfo(msg))
    local kills = msg:getU32()
    local firstUnlock = msg:getU16()
    local secondUnlock = msg:getU16()
    local thirdUnlock = msg:getU16()
    local progress = msg:getU8()
    tracker[#tracker + 1] = { raceId, kills, firstUnlock, secondUnlock, thirdUnlock, progress }
  end
  signalcall(g_game.onMonsterTrackerData, 0, tracker)
end

local function onCyclopediaMessage(protocolGame, msg)
  local response = msg:getU8()
  if response == RESP_MESSAGE then
    displayInfoBox(tr("Cyclopedia"), msg:getString())
  elseif response == RESP_BESTIARY_DATA then
    parseBestiaryData(msg)
  elseif response == RESP_BESTIARY_OVERVIEW then
    parseBestiaryOverview(msg)
  elseif response == RESP_BESTIARY_MONSTER then
    parseBestiaryMonster(msg)
  elseif response == RESP_TRACKER then
    parseTracker(msg)
  elseif response == RESP_BESTIARY_PROGRESS then
    parseBestiaryProgress(msg)
  end
  return true
end

function CyclopediaProtocol.register()
  if registered then
    return
  end
  ProtocolGame.unregisterOpcode(OPCODE_SEND)
  ProtocolGame.registerOpcode(OPCODE_SEND, onCyclopediaMessage)
  registered = true
end

function CyclopediaProtocol.unregister()
  if not registered then
    return
  end
  ProtocolGame.unregisterOpcode(OPCODE_SEND)
  registered = false
end

function CyclopediaProtocol.open()
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_INFO)
  sendMessage(msg)
end

function CyclopediaProtocol.overview(_, className)
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_CATEGORY)
  msg:addU8(0)
  msg:addString(className or "")
  sendMessage(msg)
end

function CyclopediaProtocol.monster(raceId)
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_MONSTER)
  msg:addU16(raceId)
  sendMessage(msg)
end

function CyclopediaProtocol.charmSelect(charmId, raceId)
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_CHARM)
  msg:addU8(charmId)
  msg:addU8(1)
  msg:addU16(raceId)
  sendMessage(msg)
end

function CyclopediaProtocol.charmUnlock(charmId)
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_CHARM)
  msg:addU8(charmId)
  msg:addU8(0)
  msg:addU16(0)
  sendMessage(msg)
end

function CyclopediaProtocol.charmRemove(charmId)
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_CHARM)
  msg:addU8(charmId)
  msg:addU8(2)
  msg:addU16(0)
  sendMessage(msg)
end

function CyclopediaProtocol.tracker(raceId)
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_TRACKER)
  msg:addU16(raceId or 0)
  sendMessage(msg)
end

function CyclopediaProtocol.search(list)
  local monsters = {}
  for _, raceId in pairs(list or {}) do
    monsters[#monsters + 1] = { raceId, 1, 0 }
  end
  signalcall(g_game.updateBestiaryOverview, "Search", monsters, 0)
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
  g_game.charmUnlock = CyclopediaProtocol.charmUnlock
  g_game.charmSelect = CyclopediaProtocol.charmSelect
  g_game.charmRemove = CyclopediaProtocol.charmRemove
  g_game.sendMonsterTracker = CyclopediaProtocol.tracker
  g_game.bestiarySearch = CyclopediaProtocol.search

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
