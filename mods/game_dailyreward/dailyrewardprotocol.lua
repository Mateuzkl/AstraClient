-- Daily Reward Wall protocol adapter for crystalserver
-- (data/modules/scripts/daily_reward/daily_reward.lua, modules.xml recvbytes
-- 216/217/218 — read-only on WSL).
--
-- SEND side: g_game.openDailyReward / dailyRewardHistory / dailyRewardConfirm
-- have no native C++ binding (they are corelib gameNoops in globals.lua), so
-- the senders are installed here over the noops:
--   0xD8 OpenRewardWall    - no payload
--   0xD9 OpenRewardHistory - no payload
--   0xDA SelectReward      - target + picked item columns
--
-- RECEIVE side: handlers registered via ProtocolGame.registerOpcode run BEFORE
-- the C++ parse switch (ProtocolGame::onOpcode), shadowing the broken native
-- stubs (parseOpenRewardWall assumes a fixed layout the server never sends and
-- parseDailyReward consumes only the day count — desync), which also fire no
-- Lua event:
--   0xE2 OpenRewardWall     -> g_game.onOpenRewardWall
--   0xE4 DailyRewardBasic   -> g_game.onDailyReward
--   0xE5 DailyRewardHistory -> g_game.onDailyRewardHistory
-- 0xDE DailyRewardCollectionState stays on the C++ side (parseDailyRewardState
-- consumes its single byte correctly and there is no Lua consumer); 0xE3
-- CloseRewardWall is declared by the server script but never sent.
-- All wire layouts below were verified against the crystalserver script.

local DailyRewardProtocol = {}

-- crystalserver client->server opcodes (ClientPackets)
local OPCODE_OPEN_REWARD_WALL    = 0xD8
local OPCODE_OPEN_REWARD_HISTORY = 0xD9
local OPCODE_SELECT_REWARD       = 0xDA

-- crystalserver server->client opcodes (ServerPackets)
local RESP_OPEN_REWARD_WALL      = 0xE2
local RESP_DAILY_REWARD_BASIC    = 0xE4
local RESP_DAILY_REWARD_HISTORY  = 0xE5

local registered = false

local function sendMessage(msg)
  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    protocolGame:send(msg)
  end
end

--------------------------------------------------------------------------------
-- Response parsers (crystalserver wire layouts)
--------------------------------------------------------------------------------

-- 0xE2: Player.sendOpenRewardWall. [U8 shrine][U32 nextRewardTime]
-- [U8 dayStreakDay][U8 taken]; taken==1 -> [String message][U8 hasJokers]
-- [U16 jokers only if hasJokers==1]; taken==0 -> [U8 state(=2)]
-- [U32 availableAt][U16 jokers]; then always [U16 streakLevel].
local function parseOpenRewardWall(protocolGame, msg)
  local shrine = msg:getU8()
  local nextRewardTime = msg:getU32()
  local dayStreakDay = msg:getU8()
  local taken = msg:getU8()
  local message, state, jokers, serverSave
  if taken == 1 then
    message = msg:getString()
    state = msg:getU8() -- 1 = player still has jokers, 0 = none
    if state == 1 then
      jokers = msg:getU16()
    end
  else
    state = msg:getU8() -- always 2 (claimable before server save)
    serverSave = msg:getU32() -- claim deadline (availableAt)
    jokers = msg:getU16()
  end
  local streakLevel = msg:getU16()
  -- fromShrine MUST be a boolean: dailyreward.lua sends 'not gameFromShrine'
  -- as the 0xDA target and Lua's 'not 0' is false — a raw number would invert it.
  signalcall(g_game.onOpenRewardWall, shrine == 1, nextRewardTime, dayStreakDay,
             message or '', state, jokers or 0, serverSave or 0, streakLevel)
end

-- One blob of Player.readDailyReward: [U8 systemType]; systemType==1 (pick
-- items) -> [U8 itemsToPick][U8 n] n x ([U32 itemId][String name][U32 weight]);
-- systemType==2 -> [U8 skip(=1)][U8 subtype], subtype==2 -> [U8 preyCards],
-- subtype==3 -> [U16 xpBoostMinutes].
local function getDailyRewardBlob(msg)
  local reward = { type = msg:getU8(), amount = 0, items = {}, preyCount = 0, xpboost = 0 }
  if reward.type == 1 then
    reward.amount = msg:getU8() -- itemsToPick
    local itemCount = msg:getU8()
    for i = 1, itemCount do
      local itemId = msg:getItemId()
      local name = msg:getString()
      local weight = msg:getU32()
      reward.items[i] = { item = itemId, name = name, oz = weight }
    end
  elseif reward.type == 2 then
    msg:getU8() -- DAILY_REWARD_SYSTEM_SKIP (always 1)
    local subtype = msg:getU8()
    if subtype == 2 then
      reward.preyCount = msg:getU8()
    elseif subtype == 3 then
      reward.xpboost = msg:getU16()
    end
  end
  return reward
end

-- 0xE4: Player.sendDailyReward. [U8 days(=7)] per day a free and a premium
-- reward blob; then [U8 bonusCount(=6)] bonusCount x ([String text][U8 day]);
-- trailing [U8 unknown(=1)].
local function parseDailyRewardBasic(protocolGame, msg)
  local freeRewards, premiumRewards = {}, {}
  local days = msg:getU8()
  for day = 1, days do
    freeRewards[day] = getDailyRewardBlob(msg)
    premiumRewards[day] = getDailyRewardBlob(msg)
  end
  local descriptions = {}
  local bonusCount = msg:getU8()
  for i = 1, bonusCount do
    descriptions[i] = msg:getString()
    msg:getU8() -- bonus day (2..7)
  end
  msg:getU8() -- unknown
  signalcall(g_game.onDailyReward, freeRewards, premiumRewards, descriptions)
end

-- 0xE5: Player.sendRewardHistory. [U8 n] n x ([U32 timestamp][U8 isPremium]
-- [String description][U16 daystreak]). On an empty history the server sends
-- a 0xED error dialog instead of this opcode.
local function parseDailyRewardHistory(protocolGame, msg)
  local entries = {}
  local count = msg:getU8()
  for i = 1, count do
    local timestamp = msg:getU32()
    local isPremium = msg:getU8()
    local description = msg:getString()
    local daystreak = msg:getU16()
    entries[i] = { timestamp, isPremium, description, daystreak }
  end
  signalcall(g_game.onDailyRewardHistory, entries)
end

--------------------------------------------------------------------------------
-- Opcode registration
--------------------------------------------------------------------------------

local opcodeHandlers = {
  [RESP_OPEN_REWARD_WALL] = parseOpenRewardWall,
  [RESP_DAILY_REWARD_BASIC] = parseDailyRewardBasic,
  [RESP_DAILY_REWARD_HISTORY] = parseDailyRewardHistory,
}

function DailyRewardProtocol.register()
  if registered then
    return
  end
  for opcode, handler in pairs(opcodeHandlers) do
    ProtocolGame.unregisterOpcode(opcode)
    ProtocolGame.registerOpcode(opcode, handler)
  end
  registered = true
end

function DailyRewardProtocol.unregister()
  if not registered then
    return
  end
  for opcode in pairs(opcodeHandlers) do
    ProtocolGame.unregisterOpcode(opcode)
  end
  registered = false
end

--------------------------------------------------------------------------------
-- Requests (crystalserver client->server opcodes)
--------------------------------------------------------------------------------

-- 0xD8: open the reward wall; the server answers with 0xEE x2 (joker 0x15 and
-- collection 0x14 resources), 0xE4, 0xE2 and 0xDE.
function DailyRewardProtocol.openDailyReward()
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_OPEN_REWARD_WALL)
  sendMessage(msg)
end

-- 0xD9: request the reward history; replies 0xE5 (or a 0xED error dialog when
-- the history is empty).
function DailyRewardProtocol.dailyRewardHistory()
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_OPEN_REWARD_HISTORY)
  sendMessage(msg)
end

-- 0xDA: claim the daily reward. Server selectDailyReward reads [U8 target]
-- (0 = shrine, anything else = tibia panel and consumes one collection token);
-- on item days it also reads [U8 columns] columns x ([U32 itemId][U8 count]).
-- On prey/xpboost days the trailing bytes are simply never read — harmless,
-- one opcode per message (same precedent as storeprotocol.lua).
-- items arrives as {[itemId] = count} (dailyreward.lua onClickConfirm).
function DailyRewardProtocol.dailyRewardConfirm(panel, items)
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_SELECT_REWARD)
  msg:addU8((panel == true or panel == 1) and 1 or 0)
  local columns = {}
  for itemId, count in pairs(items or {}) do
    columns[#columns + 1] = { itemId, count }
  end
  msg:addU8(#columns)
  for _, column in ipairs(columns) do
    msg:addItemId(column[1])
    msg:addU8(math.max(0, math.min(255, column[2])))
  end
  sendMessage(msg)
end

function initDailyRewardProtocol()
  connect(g_game, {
    onGameStart = DailyRewardProtocol.register,
    onGameEnd = DailyRewardProtocol.unregister
  })

  g_game.openDailyReward = DailyRewardProtocol.openDailyReward
  g_game.dailyRewardHistory = DailyRewardProtocol.dailyRewardHistory
  g_game.dailyRewardConfirm = DailyRewardProtocol.dailyRewardConfirm

  if g_game.isOnline() then
    DailyRewardProtocol.register()
  end
end

function terminateDailyRewardProtocol()
  disconnect(g_game, {
    onGameStart = DailyRewardProtocol.register,
    onGameEnd = DailyRewardProtocol.unregister
  })
  DailyRewardProtocol.unregister()
end
