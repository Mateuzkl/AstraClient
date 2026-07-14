-- Highscores protocol adapter for crystalserver
-- (src/server/network/protocol/protocolgame.cpp parseHighscores/sendHighscores,
-- src/game/game.cpp playerHighscores — read-only on WSL).
--
-- There is NO native C++ highscore code in this client (no g_game.highscore
-- sender, no 0xB1 parser). The mod relied on the legacy game_protocol module,
-- which on 15.25 is never loaded (autoload:false, GameTibia12Protocol gated)
-- and whose parser is also wrong for crystalserver (it skips the two bytes that
-- follow the selected world and never fires g_game.onHighscores).
--
-- SEND side: g_game.highscore is a corelib gameNoop (globals.lua), so the
-- sender is installed here over the noop:
--   0xB1 GetHighscores - type/category/vocation/world + paging
--
-- RECEIVE side: a ProtocolGame.registerOpcode handler runs BEFORE the C++ parse
-- switch and fires the Lua event the mod connects to:
--   0xB1 Highscores -> g_game.onHighscores
-- All wire layouts below were verified against the crystalserver source.

local HighscoresProtocol = {}

-- crystalserver client<->server opcode (ClientPackets/ServerPackets)
local OPCODE_HIGHSCORES = 0xB1

-- HighscoreType_t (game_definitions.hpp): paged entries vs "show own rank"
local HIGHSCORE_GETENTRIES = 0

local registered = false

--------------------------------------------------------------------------------
-- Response parser (crystalserver sendHighscores wire layout)
--------------------------------------------------------------------------------

-- 0xB1: [U8 status(0=ok,1=nodata)]. On status==0:
--   [U8 worldCount] worldCount x [String world]
--   [String selectedWorld]
--   [U8 gameWorldCategory][U8 battlEyeWorldType]
--   [U8 vocCount] vocCount x ([U32 id][String name])
--   [U32 selectedVocation]
--   [U8 catCount] catCount x ([U8 id][String name])
--   [U8 selectedCategory]
--   [U16 page][U16 pages]
--   [U8 charCount] charCount x ([U32 rank][String name][String loyaltyTitle]
--     [U8 vocation][String world][U16 level][U8 isPlayer][U64 points])
--   [U8 0xFF][U8 0][U8 1][U32 updateTimer(absolute epoch seconds)]
local function parseHighscores(protocolGame, msg)
  local status = msg:getU8()
  if status == 1 then
    -- No data: clear the UI gracefully (empty rows, page 1/1).
    signalcall(g_game.onHighscores, {}, "", {}, 0, {}, 0, 1, 1, {}, os.time())
    return
  end

  local worlds = {}
  local worldCount = msg:getU8()
  for i = 1, worldCount do
    worlds[i] = msg:getString()
  end

  local selectedWorld = msg:getString()

  msg:getU8() -- gameWorldCategory
  msg:getU8() -- battlEyeWorldType

  local vocations = {}
  local vocCount = msg:getU8()
  for i = 1, vocCount do
    local id = msg:getU32()
    vocations[id] = msg:getString()
  end

  local selectedVocation = msg:getU32()

  local categories = {}
  local catCount = msg:getU8()
  for i = 1, catCount do
    local id = msg:getU8()
    categories[id] = msg:getString()
  end

  local selectedCategory = msg:getU8()

  local page = msg:getU16()
  local pages = msg:getU16()

  local characters = {}
  local charCount = msg:getU8()
  for i = 1, charCount do
    local rank = msg:getU32()
    local name = msg:getString()
    msg:getString() -- loyaltyTitle (unused by the mod)
    local vocation = msg:getU8()
    local world = msg:getString()
    local level = msg:getU16()
    local isPlayer = msg:getU8() ~= 0
    local points = msg:getU64()
    characters[i] = { rank, name, vocation, world, level, isPlayer, points }
  end

  msg:getU8() -- 0xFF
  msg:getU8() -- 0
  msg:getU8() -- 1
  local lastUpdate = msg:getU32()

  signalcall(g_game.onHighscores, worlds, selectedWorld, vocations, selectedVocation,
             categories, selectedCategory, page, pages, characters, lastUpdate)
end

--------------------------------------------------------------------------------
-- Opcode registration
--------------------------------------------------------------------------------

function HighscoresProtocol.register()
  if registered then
    return
  end
  ProtocolGame.unregisterOpcode(OPCODE_HIGHSCORES)
  ProtocolGame.registerOpcode(OPCODE_HIGHSCORES, parseHighscores)
  registered = true
end

function HighscoresProtocol.unregister()
  if not registered then
    return
  end
  ProtocolGame.unregisterOpcode(OPCODE_HIGHSCORES)
  registered = false
end

--------------------------------------------------------------------------------
-- Request (crystalserver client->server opcode)
--------------------------------------------------------------------------------

-- 0xB1: [U8 type][U8 category][U32 vocation][String world]
--   [U8 gameWorldCategory(0)][U8 battlEyeWorldType(0)]
--   if type==HIGHSCORE_GETENTRIES then [U16 page]
--   [U8 entriesPerPage(clamped 5..30)]
-- The mod passes a vestigial 7th stringPvpTypes arg which crystalserver never
-- reads, so it is ignored here.
function HighscoresProtocol.highscore(type, category, vocation, world, page, entriesPerPage)
  local protocolGame = g_game.getProtocolGame()
  if not protocolGame then
    return
  end

  local msg = OutputMessage.create()
  msg:addU8(OPCODE_HIGHSCORES)
  msg:addU8(type or HIGHSCORE_GETENTRIES)
  msg:addU8(category or 0)
  msg:addU32(vocation or 0xFFFFFFFF)
  msg:addString(world or g_game.getWorldName())
  msg:addU8(0) -- gameWorldCategory
  msg:addU8(0) -- battlEyeWorldType
  if (type or HIGHSCORE_GETENTRIES) == HIGHSCORE_GETENTRIES then
    msg:addU16(page or 1)
  end
  msg:addU8(math.max(5, math.min(30, entriesPerPage or 20)))
  protocolGame:send(msg)
end

function initHighscoresProtocol()
  connect(g_game, {
    onGameStart = HighscoresProtocol.register,
    onGameEnd = HighscoresProtocol.unregister
  })

  g_game.highscore = HighscoresProtocol.highscore

  if g_game.isOnline() then
    HighscoresProtocol.register()
  end
end

function terminateHighscoresProtocol()
  disconnect(g_game, {
    onGameStart = HighscoresProtocol.register,
    onGameEnd = HighscoresProtocol.unregister
  })
  HighscoresProtocol.unregister()
end
