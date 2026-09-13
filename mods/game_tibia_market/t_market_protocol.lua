local MarketProtocol = {}

local OPCODE_MARKET_OPEN = 0xF4
local OPCODE_MARKET_LEAVE = 0xF5
local OPCODE_MARKET_BROWSE = 0xF6
local OPCODE_MARKET_CREATE = 0xF7
local OPCODE_MARKET_CANCEL = 0xE0
local OPCODE_MARKET_ACCEPT = 0xE1
local OPCODE_MARKET_SEND = 0xDB

local RESP_MESSAGE = 0
local RESP_ENTER = 1
local RESP_LEAVE = 2
local RESP_BROWSE = 3
local RESP_DETAIL = 4

local MARKET_REQUEST_MY_OFFERS = 0xFFFE
local MARKET_REQUEST_MY_HISTORY = 0xFFFF

local registered = false
local enterItems = {}
local lastBrowseTier = 0
local marketOpen = false

local function logMarketProtocolError(message)
  if g_logger and g_logger.error then
    g_logger.error('[MarketProtocol] ' .. message)
  elseif perror then
    perror('[MarketProtocol] ' .. message)
  end
end

local function skipUnread(msg)
  local unread = msg:getUnreadSize()
  if unread and unread > 0 then
    msg:skipBytes(unread)
  end
end

local function getDepotItemKey(itemId, tier)
  return string.format("%d:%d", itemId or 0, tier or 0)
end

local function getProtocolGame()
  return g_game.getProtocolGame()
end

local function sendMessage(msg)
  MarketProtocol.register()
  local protocolGame = getProtocolGame()
  if protocolGame then
    protocolGame:send(msg)
  end
end

local function readOffer(msg)
  return {
    counter = msg:getU32(),
    timestamp = msg:getU32(),
    itemId = msg:getU16(),
    itemTier = msg:getU8(),
    amount = msg:getU16(),
    price = msg:getU32(),
    holder = msg:getString(),
    state = msg:getU8()
  }
end

local function readOfferList(msg)
  local offers = {}
  local count = msg:getU16()
  for i = 1, count do
    offers[#offers + 1] = readOffer(msg)
  end
  return offers
end

local function filterOffersByTier(offers, tier)
  local filtered = {}
  tier = tier or 0
  for _, offer in ipairs(offers) do
    if (offer.itemTier or 0) == tier then
      filtered[#filtered + 1] = offer
    end
  end
  return filtered
end

local function readStatistics(msg)
  local statistics = {}
  local count = msg:getU8()
  for i = 1, count do
    statistics[#statistics + 1] = {
      timestamp = msg:getU32(),
      numTransactions = msg:getU32(),
      totalPrice = msg:getU32(),
      highestPrice = msg:getU32(),
      lowestPrice = msg:getU32()
    }
  end
  return statistics
end

local function parseMarketEnter(msg)
  local balance = msg:getU64()
  local offerCount = msg:getU16()
  local chunkIndex = msg:getU16()
  local lastChunk = msg:getU8() ~= 0
  local chunkCount = msg:getU16()

  if chunkIndex == 0 then
    enterItems = {
      depotItems = {},
      depotTiers = {},
      itemTotals = {}
    }
  end

  for i = 1, chunkCount do
    local itemId = msg:getU16()
    local category = msg:getU8()
    local name = msg:getString()
    local amount = msg:getU16()
    local tier = msg:getU8()
    local classification = msg:getU8()
    local requiredLevel = msg:getU16()
    local restrictVocation = msg:getU16()
    local key = getDepotItemKey(itemId, tier)

    enterItems[#enterItems + 1] = {
      itemId,
      tier,
      amount,
      category = category,
      name = name,
      classification = classification,
      requiredLevel = requiredLevel,
      restrictVocation = restrictVocation
    }
    enterItems.depotItems[key] = (enterItems.depotItems[key] or 0) + amount
    enterItems.depotTiers[key] = tier
    enterItems.itemTotals[itemId] = (enterItems.itemTotals[itemId] or 0) + amount
  end

  local player = g_game.getLocalPlayer()
  if player and player.setResourceValue then
    player:setResourceValue(ResourceBank, balance)
    player:setResourceValue(ResourceInventary, 0)
  end

  if lastChunk then
    marketOpen = true
    signalcall(g_game.onMarketEnter, offerCount, enterItems)
  end
end

local function parseMarketBrowse(msg)
  local browseId = msg:getU16()
  local buyOffers = readOfferList(msg)
  local sellOffers = readOfferList(msg)

  if browseId == MARKET_REQUEST_MY_OFFERS then
    signalcall(g_game.onParseMyOffers, buyOffers, sellOffers)
  elseif browseId == MARKET_REQUEST_MY_HISTORY then
    signalcall(g_game.onParseMarketHistory, buyOffers, sellOffers)
  else
    buyOffers = filterOffersByTier(buyOffers, lastBrowseTier or 0)
    sellOffers = filterOffersByTier(sellOffers, lastBrowseTier or 0)
    signalcall(g_game.onMarketBrowse, browseId, lastBrowseTier or 0, buyOffers, sellOffers)
  end
end

local function parseMarketDetail(msg)
  local itemId = msg:getU16()
  local details = {}
  local detailCount = msg:getU8()
  for i = 1, detailCount do
    local detailType = msg:getU8()
    details[detailType] = msg:getString()
  end

  local purchase = readStatistics(msg)
  local sale = readStatistics(msg)
  signalcall(g_game.onMarketDetail, itemId, lastBrowseTier or 0, details, purchase, sale)
end

local function parseMarketMessage(protocolGame, msg)
  local ok, err = pcall(function()
    local response = msg:getU8()
    if response == RESP_MESSAGE then
      marketOpen = false
      local message = msg:getString()
      if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
        modules.game_textmessage.displayFailureMessage(message)
      else
        displayInfoBox(tr("Market"), message)
      end
    elseif response == RESP_ENTER then
      parseMarketEnter(msg)
    elseif response == RESP_LEAVE then
      marketOpen = false
      signalcall(g_game.onMarketLeave)
    elseif response == RESP_BROWSE then
      parseMarketBrowse(msg)
    elseif response == RESP_DETAIL then
      parseMarketDetail(msg)
    else
      logMarketProtocolError('unknown response ' .. tostring(response))
      marketOpen = false
      skipUnread(msg)
    end
  end)

  if not ok then
    marketOpen = false
    logMarketProtocolError(tostring(err))
    skipUnread(msg)
  end

  return true
end

function MarketProtocol.register()
  ProtocolGame.unregisterOpcode(OPCODE_MARKET_SEND)
  ProtocolGame.registerOpcode(OPCODE_MARKET_SEND, parseMarketMessage)
  registered = true
end

function MarketProtocol.unregister()
  if not registered then
    return
  end
  ProtocolGame.unregisterOpcode(OPCODE_MARKET_SEND)
  registered = false
  enterItems = {}
end

function MarketProtocol.open(force)
  if marketOpen and not force then
    return
  end
  marketOpen = true
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_MARKET_OPEN)
  sendMessage(msg)
end

function MarketProtocol.leave()
  marketOpen = false
  enterItems = {}
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_MARKET_LEAVE)
  sendMessage(msg)
end

function MarketProtocol.resetSession()
  marketOpen = false
  enterItems = {}
end

function MarketProtocol.browse(browseId, tier)
  lastBrowseTier = tier or 0
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_MARKET_BROWSE)
  msg:addU16(browseId)
  sendMessage(msg)
end

function MarketProtocol.action(action, itemId, tier)
  if action == 1 then
    MarketProtocol.browse(MARKET_REQUEST_MY_HISTORY, 0)
  elseif action == 2 then
    MarketProtocol.browse(MARKET_REQUEST_MY_OFFERS, 0)
  elseif action == 3 and itemId then
    MarketProtocol.browse(itemId, tier or 0)
  end
end

function MarketProtocol.createOffer(actionType, itemId, tier, amount, price, anonymous)
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_MARKET_CREATE)
  msg:addU8(actionType)
  msg:addU16(itemId)
  msg:addU16(amount)
  msg:addU32(price)
  msg:addU8(anonymous and 1 or 0)
  msg:addU8(tier or 0)
  sendMessage(msg)
end

function MarketProtocol.cancelOffer(timestamp, counter)
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_MARKET_CANCEL)
  msg:addU32(counter)
  sendMessage(msg)
end

local function onGameEnd()
  enterItems = {}
end

function MarketProtocol.acceptOffer(timestamp, counter, amount)
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_MARKET_ACCEPT)
  msg:addU32(counter)
  msg:addU16(amount)
  sendMessage(msg)
end

function initMarketProtocol()
  MarketProtocol.register()

  connect(g_game, {
    onGameStart = MarketProtocol.register,
    onGameEnd = onGameEnd
  })

  g_game.openMarket = MarketProtocol.open
  g_game.sendMarketLeave = MarketProtocol.leave
  g_game.sendMarketAction = MarketProtocol.action
  g_game.sendMarketCreateOffer = MarketProtocol.createOffer
  g_game.sendMarketCancelOffer = MarketProtocol.cancelOffer
  g_game.sendMarketAcceptOffer = MarketProtocol.acceptOffer
  g_game.resetMarketSession = MarketProtocol.resetSession

end

function terminateMarketProtocol()
  disconnect(g_game, {
    onGameStart = MarketProtocol.register,
    onGameEnd = onGameEnd
  })
  MarketProtocol.unregister()
end
