local BosstiaryProtocol = {}

local OPCODE_DATA = 0x61
local OPCODE_SLOTS = 0x62
local OPCODE_WINDOW = 0x73
local OPCODE_OPEN = 0xAE
local OPCODE_OPEN_SLOTS = 0xAF
local OPCODE_SLOT_ACTION = 0xB0
local OPCODE_TRACKER = 0x2A

local registered = false

local function readCreatureInfo(msg)
  return {
    msg:getString(),
    msg:getU16(),
    0,
    msg:getU8(),
    msg:getU8(),
    msg:getU8(),
    msg:getU8(),
    msg:getU8()
  }
end

local function sendMessage(msg)
  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    protocolGame:send(msg)
  end
end

local function parseData(_, msg)
  local kills = {}
  local rewards = {}
  for category = 1, 3 do
    kills[category] = { msg:getU16(), msg:getU16(), msg:getU16() }
  end
  for category = 1, 3 do
    rewards[category] = { msg:getU16(), msg:getU16(), msg:getU16() }
  end
  signalcall(g_game.onBosstiaryBaseData, kills, rewards)
  return true
end

local function parseWindow(_, msg)
  local bosses = {}
  local count = msg:getU16()
  for index = 1, count do
    bosses[index] = {
      msg:getU32(),
      msg:getU8(),
      msg:getU32(),
      msg:getU8()
    }
    bosses[index][4] = msg:getU8()
    if msg:getUnreadSize() > ((count - index) * 10) then
      bosses[index][5] = readCreatureInfo(msg)
      if cacheCyclopediaMonster then
        cacheCyclopediaMonster(bosses[index][1], bosses[index][5])
      end
    end
  end
  signalcall(g_game.onBosstiaryWindowData, bosses)
  return true
end

local function parseSlot(msg, unlocked, raceId, isBoosted)
  local slot = {
    state = unlocked and 1 or 0,
    raceID = raceId or 0,
    category = 0,
    kills = 0,
    bonusLoot = 0,
    bonusKill = 0,
    isBoosted = isBoosted and 1 or 0,
    removeGold = 0
  }

  if not unlocked or slot.raceID == 0 then
    return slot
  end

  slot.category = msg:getU8()
  slot.kills = msg:getU32()
  slot.bonusLoot = msg:getU16()
  slot.bonusKill = msg:getU8()
  msg:getU8()
  slot.removeGold = msg:getU32()
  slot.inactive = msg:getU8()
  return slot
end

local function readSlotCreatureInfo(msg, slot)
  local hasInfo = msg:getU8() ~= 0
  if not hasInfo then
    return
  end

  local creatureInfo = readCreatureInfo(msg)
  if slot and slot.raceID and slot.raceID > 0 and cacheCyclopediaMonster then
    cacheCyclopediaMonster(slot.raceID, creatureInfo)
  end
end

local function parseSlots(_, msg)
  local pointsBalance = msg:getU32()
  local pointsNext = msg:getU32()
  local bonusLoot = msg:getU16()
  local bonusNext = msg:getU16()
  local slots = {}

  local unlocked = msg:getU8() ~= 0
  local raceId = msg:getU32()
  slots[1] = parseSlot(msg, unlocked, raceId, false)
  readSlotCreatureInfo(msg, slots[1])

  unlocked = msg:getU8() ~= 0
  raceId = msg:getU32()
  slots[2] = parseSlot(msg, unlocked, raceId, false)
  readSlotCreatureInfo(msg, slots[2])

  unlocked = msg:getU8() ~= 0
  raceId = msg:getU32()
  slots[3] = parseSlot(msg, unlocked, raceId, true)
  readSlotCreatureInfo(msg, slots[3])

  local selectable = {}
  if msg:getU8() ~= 0 then
    local count = msg:getU16()
    for _ = 1, count do
      selectable[msg:getU32()] = msg:getU8()
    end
  end

  signalcall(g_game.onBosstiarySlotsData, pointsBalance, pointsNext, bonusLoot, bonusNext, slots, selectable)
  return true
end

function BosstiaryProtocol.register()
  if registered then
    return
  end
  ProtocolGame.unregisterOpcode(OPCODE_DATA)
  ProtocolGame.unregisterOpcode(OPCODE_SLOTS)
  ProtocolGame.unregisterOpcode(OPCODE_WINDOW)
  ProtocolGame.registerOpcode(OPCODE_DATA, parseData)
  ProtocolGame.registerOpcode(OPCODE_SLOTS, parseSlots)
  ProtocolGame.registerOpcode(OPCODE_WINDOW, parseWindow)
  registered = true
end

function BosstiaryProtocol.unregister()
  if not registered then
    return
  end
  ProtocolGame.unregisterOpcode(OPCODE_DATA)
  ProtocolGame.unregisterOpcode(OPCODE_SLOTS)
  ProtocolGame.unregisterOpcode(OPCODE_WINDOW)
  registered = false
end

function BosstiaryProtocol.openWindow()
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_OPEN)
  sendMessage(msg)
end

function BosstiaryProtocol.openSlots()
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_OPEN_SLOTS)
  sendMessage(msg)
end

function BosstiaryProtocol.slotAction(slot, raceId)
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_SLOT_ACTION)
  msg:addU8(slot or 0)
  msg:addU32(raceId or 0)
  sendMessage(msg)
end

function BosstiaryProtocol.tracker(raceId, enabled)
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_TRACKER)
  msg:addU32(raceId or 0)
  msg:addU8(enabled and 1 or 0)
  sendMessage(msg)
end

function BosstiaryProtocol.onGameStart()
  BosstiaryProtocol.register()
  BosstiaryProtocol.openWindow()
end

function initBosstiaryProtocol()
  connect(g_game, {
    onGameStart = BosstiaryProtocol.onGameStart,
    onGameEnd = BosstiaryProtocol.unregister
  })

  g_game.openBosstiaryWindow = BosstiaryProtocol.openWindow
  g_game.openBosstiarySlots = BosstiaryProtocol.openSlots
  g_game.sendBosstiarySlotAction = BosstiaryProtocol.slotAction
  g_game.sendBosstiaryTracker = BosstiaryProtocol.tracker

  if g_game.isOnline() then
    BosstiaryProtocol.onGameStart()
  end
end

function terminateBosstiaryProtocol()
  disconnect(g_game, {
    onGameStart = BosstiaryProtocol.onGameStart,
    onGameEnd = BosstiaryProtocol.unregister
  })
  BosstiaryProtocol.unregister()
end
