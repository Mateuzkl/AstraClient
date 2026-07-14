local MarketProtocol = {}

-- Standard Tibia/canary market protocol (crystalserver 1525).
--
-- The previous revision spoke a bespoke protocol: every market response was
-- wrapped in a single server opcode 0xDB carrying a sub-response byte, and the
-- client sent non-standard opcodes (0xF4 "open", 0xE0/0xE1 cancel/accept).
-- crystalserver speaks none of that -- it sends the standard opcodes below and
-- the server emitted a raw 0xF6 MarketEnter that hit the C++ default branch
-- ("unhandled opcode 246"), desyncing the connection.
--
-- Server -> client opcodes:
local SERVER_MARKET_ENTER  = 0xF6
local SERVER_MARKET_LEAVE  = 0xF7
local SERVER_MARKET_DETAIL = 0xF8
local SERVER_MARKET_BROWSE = 0xF9

-- Client -> server opcodes:
local CLIENT_MARKET_LEAVE  = 0xF4
local CLIENT_MARKET_BROWSE = 0xF5
local CLIENT_MARKET_CREATE = 0xF6
local CLIENT_MARKET_CANCEL = 0xF7
local CLIENT_MARKET_ACCEPT = 0xF8

-- MarketRequest_t discriminator (first byte of the 0xF9 browse response, and of
-- the client browse request). Mirrors creatures_definitions.hpp.
local MARKETREQUEST_OWN_HISTORY = 1
local MARKETREQUEST_OWN_OFFERS  = 2
local MARKETREQUEST_ITEM_BROWSE = 3

-- The offer side (createOffer's actionType) matches the server's MarketAction_t
-- and the UI's currentActionType directly: 0 = buy, 1 = sell.

local registered = false

local function getProtocolGame()
  return g_game.getProtocolGame()
end

local function sendMessage(msg)
  local protocolGame = getProtocolGame()
  if protocolGame then
    protocolGame:send(msg)
  end
end

local function isOldProtocol()
  return not g_game.getFeature(GameTibia12Protocol)
end

-- The server writes a tier byte for an item only when it has an upgrade
-- classification (Item::items[id].upgradeClassification > 0). The client must
-- read/write the tier byte under the exact same condition or the whole stream
-- desyncs. ThingType::getClassification exposes the appearances
-- upgradeClassification, which is loaded from the same game data as the server.
local function itemHasClassification(itemId)
  local thingType = g_things.getThingType(itemId, ThingCategoryItem)
  return thingType and thingType:getClassification() > 0
end

local function readPrice(msg)
  -- 12+ prices are 64-bit; legacy clients used 32-bit.
  if isOldProtocol() then
    return msg:getU32()
  end
  return msg:getU64()
end

-- =====================================================================
-- Server -> client parsing
-- =====================================================================

-- 0xF6: list of the player's depot/locker items (used to populate the
-- sellable item list). Bank balance is NOT here on 12+ -- it arrives via the
-- ResourceBalance opcode (0xEE) right after, already handled by the core.
local function parseMarketEnter(protocol, msg)
  local offerCount = msg:getU8()
  local itemCount = msg:getU16()

  local items = {}
  for _ = 1, itemCount do
    local itemId = msg:getItemId()
    local tier = 0
    if not isOldProtocol() and itemHasClassification(itemId) then
      tier = msg:getU8()
    end
    local amount = msg:getU16()
    items[#items + 1] = { itemId, tier, amount }
  end

  signalcall(g_game.onMarketEnter, offerCount, items)
  return true
end

local function parseMarketLeave(protocol, msg)
  signalcall(g_game.onMarketLeave)
  return true
end

-- 0xF8: a fixed-order sequence of descriptor strings followed by buy/sale
-- statistics. Each descriptor is a string (empty string == "not applicable").
-- The indices below are 0-based so they line up with the UI, which renders
-- MarketDetailNames[index + 1] (see gamelib/market.lua).
local function readStatistics(msg)
  local statistics = {}
  if msg:getU8() == 1 then
    statistics[1] = {
      numTransactions = msg:getU32(),
      totalPrice = readPrice(msg),
      highestPrice = readPrice(msg),
      lowestPrice = readPrice(msg),
    }
  end
  return statistics
end

local function parseMarketDetail(protocol, msg)
  local itemId = msg:getItemId()
  local tier = 0
  if not isOldProtocol() and itemHasClassification(itemId) then
    tier = msg:getU8()
  end

  local oldProtocol = isOldProtocol()
  local details = {}

  -- Always present (both protocols), in this exact order.
  for i = 0, 14 do
    details[i] = msg:getString() -- 0 armor .. 14 weight
  end

  if not oldProtocol then
    details[15] = msg:getString() -- augments (12+ only)
  end

  details[16] = msg:getString() -- imbuement slots

  if not oldProtocol then
    details[17] = msg:getString() -- magic shield capacity
    details[18] = msg:getString() -- cleave (server keeps this empty)
    details[19] = msg:getString() -- damage reflection
    details[20] = msg:getString() -- perfect shot
    details[21] = msg:getString() -- classification
    details[22] = msg:getString() -- elemental bond
    details[23] = msg:getString() -- mantra
    msg:getString()               -- imbuement effect string: always empty, unnamed
    details[24] = msg:getString() -- tier
  end

  local purchase = readStatistics(msg)
  local sale = readStatistics(msg)

  signalcall(g_game.onMarketDetail, itemId, tier, details, purchase, sale)
  return true
end

-- Offer shape for a specific item browse (0xF9 / ITEM_BROWSE and the
-- single-offer update echoed after accepting an offer).
local function readItemOffer(msg)
  return {
    timestamp = msg:getU32(),
    counter = msg:getU16(),
    amount = msg:getU16(),
    price = readPrice(msg),
    holder = msg:getString(),
  }
end

-- Offer shape for the player's own offers / history (0xF9 / OWN_OFFERS,
-- OWN_HISTORY and the single-offer update echoed after cancelling).
local function readOwnOffer(msg)
  local offer = {
    timestamp = msg:getU32(),
    counter = msg:getU16(),
    itemId = msg:getItemId(),
  }
  offer.itemTier = 0
  if not isOldProtocol() and itemHasClassification(offer.itemId) then
    offer.itemTier = msg:getU8()
  end
  offer.amount = msg:getU16()
  offer.price = readPrice(msg)
  return offer
end

local function readOfferList(msg, reader)
  local offers = {}
  local count = msg:getU32()
  for _ = 1, count do
    offers[#offers + 1] = reader(msg)
  end
  return offers
end

local function parseMarketBrowse(protocol, msg)
  local requestType
  if isOldProtocol() then
    requestType = msg:getU16()
  else
    requestType = msg:getU8()
  end

  if requestType == MARKETREQUEST_OWN_OFFERS or requestType == 0xFFFE then
    local buyOffers = readOfferList(msg, readOwnOffer)
    local sellOffers = readOfferList(msg, readOwnOffer)
    signalcall(g_game.onParseMyOffers, buyOffers, sellOffers)
    return true
  end

  if requestType == MARKETREQUEST_OWN_HISTORY or requestType == 0xFFFF then
    local function readHistoryOffer(m)
      local offer = readOwnOffer(m)
      offer.state = m:getU8()
      return offer
    end
    local buyOffers = readOfferList(msg, readHistoryOffer)
    local sellOffers = readOfferList(msg, readHistoryOffer)
    signalcall(g_game.onParseMarketHistory, buyOffers, sellOffers)
    return true
  end

  -- ITEM_BROWSE: the browse-id byte is followed by the item id (and tier).
  local itemId = msg:getItemId()
  local tier = 0
  if not isOldProtocol() and itemHasClassification(itemId) then
    tier = msg:getU8()
  end

  local buyOffers = readOfferList(msg, readItemOffer)
  local sellOffers = readOfferList(msg, readItemOffer)
  signalcall(g_game.onMarketBrowse, itemId, tier, buyOffers, sellOffers)
  return true
end

-- =====================================================================
-- Registration
-- =====================================================================

local handlers = {
  [SERVER_MARKET_ENTER] = parseMarketEnter,
  [SERVER_MARKET_LEAVE] = parseMarketLeave,
  [SERVER_MARKET_DETAIL] = parseMarketDetail,
  [SERVER_MARKET_BROWSE] = parseMarketBrowse,
}

function MarketProtocol.register()
  if registered then
    return
  end
  for opcode, handler in pairs(handlers) do
    ProtocolGame.unregisterOpcode(opcode)
    ProtocolGame.registerOpcode(opcode, handler)
  end
  registered = true
end

function MarketProtocol.unregister()
  if not registered then
    return
  end
  for opcode in pairs(handlers) do
    ProtocolGame.unregisterOpcode(opcode)
  end
  registered = false
end

-- =====================================================================
-- Client -> server sending
-- =====================================================================

function MarketProtocol.open()
  -- There is no dedicated "open market" client opcode. The server enters the
  -- player into the market when they use the market terminal (item 12903) next
  -- to a depot, which triggers sendMarketEnter -> onMarketEnter (window shows).
  -- Nothing to send here.
end

function MarketProtocol.leave()
  local msg = OutputMessage.create()
  msg:addU8(CLIENT_MARKET_LEAVE)
  sendMessage(msg)
end

function MarketProtocol.browse(browseType, itemId, tier)
  local msg = OutputMessage.create()
  msg:addU8(CLIENT_MARKET_BROWSE)
  msg:addU8(browseType)
  if browseType == MARKETREQUEST_ITEM_BROWSE then
    msg:addItemId(itemId)
    if not isOldProtocol() and itemHasClassification(itemId) then
      msg:addU8(tier or 0)
    end
  end
  sendMessage(msg)
end

-- Compatibility shim for the UI: action 1 = history, 2 = own offers,
-- 3 = browse a specific item.
function MarketProtocol.action(action, itemId, tier)
  if action == 1 then
    MarketProtocol.browse(MARKETREQUEST_OWN_HISTORY)
  elseif action == 2 then
    MarketProtocol.browse(MARKETREQUEST_OWN_OFFERS)
  elseif action == 3 and itemId then
    MarketProtocol.browse(MARKETREQUEST_ITEM_BROWSE, itemId, tier or 0)
  end
end

function MarketProtocol.createOffer(actionType, itemId, tier, amount, price, anonymous)
  local msg = OutputMessage.create()
  msg:addU8(CLIENT_MARKET_CREATE)
  msg:addU8(actionType) -- MARKETACTION_BUY (0) / MARKETACTION_SELL (1)
  msg:addItemId(itemId)
  if not isOldProtocol() and itemHasClassification(itemId) then
    msg:addU8(tier or 0)
  end
  msg:addU16(amount)
  if isOldProtocol() then
    msg:addU32(price)
  else
    msg:addU64(price)
  end
  msg:addU8(anonymous and 1 or 0)
  sendMessage(msg)
end

function MarketProtocol.cancelOffer(timestamp, counter)
  local msg = OutputMessage.create()
  msg:addU8(CLIENT_MARKET_CANCEL)
  msg:addU32(timestamp)
  msg:addU16(counter)
  sendMessage(msg)
end

function MarketProtocol.acceptOffer(timestamp, counter, amount)
  local msg = OutputMessage.create()
  msg:addU8(CLIENT_MARKET_ACCEPT)
  msg:addU32(timestamp)
  msg:addU16(counter)
  msg:addU16(amount)
  sendMessage(msg)
end

function initMarketProtocol()
  connect(g_game, {
    onGameStart = MarketProtocol.register,
    onGameEnd = MarketProtocol.unregister
  })

  g_game.openMarket = MarketProtocol.open
  g_game.sendMarketLeave = MarketProtocol.leave
  g_game.sendMarketAction = MarketProtocol.action
  g_game.sendMarketCreateOffer = MarketProtocol.createOffer
  g_game.sendMarketCancelOffer = MarketProtocol.cancelOffer
  g_game.sendMarketAcceptOffer = MarketProtocol.acceptOffer

  if g_game.isOnline() then
    MarketProtocol.register()
  end
end

function terminateMarketProtocol()
  disconnect(g_game, {
    onGameStart = MarketProtocol.register,
    onGameEnd = MarketProtocol.unregister
  })
  MarketProtocol.unregister()
end
