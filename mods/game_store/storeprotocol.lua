local StoreProtocol = {}

local OPCODE_STORE_TRANSFER = 0xF8
local OPCODE_STORE_HISTORY = 0xFA
local OPCODE_STORE_OPEN = 0xFB
local OPCODE_STORE_BUY = 0xFC
local OPCODE_STORE_SEND = 0xFD

local RESP_ERROR = 0
local RESP_CATALOG = 1
local RESP_SUCCESS = 2
local RESP_HISTORY = 3

local registered = false
local categories = {}
local offersByCategory = {}
local offersById = {}
local homeBanners = {}
local homeBannerDelay = 10
local pendingStoreRequest = nil

local HOME_OFFER_LIMIT = 6

local function sendStoreMessage(msg)
  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    protocolGame:send(msg)
  end
end

local function normalizeOfferType(oftype)
  oftype = tostring(oftype or ""):lower()
  if oftype:find("mount", 1, true) then
    return CATEGORY_MOUNT
  elseif oftype:find("outfit", 1, true) then
    return CATEGORY_OUTFIT
  elseif oftype:find("hireling", 1, true) then
    return CATEGORY_HIRELING
  end
  return CATEGORY_ITEM
end

local function buildOffer(rawOffer, categoryName)
  local offerType = normalizeOfferType(rawOffer.oftype)
  local itemId = offerType == CATEGORY_ITEM and rawOffer.eid or 0
  local offer = {
    id = rawOffer.id,
    name = rawOffer.name,
    description = rawOffer.description,
    filter = categoryName or "",
    icon = rawOffer.icon or "",
    itemId = itemId,
    offerType = offerType,
    state = OFFER_STATE_NONE,
    TimesBought = 0,
    mountId = rawOffer.eid,
    type = rawOffer.eid,
    head = 0,
    body = 0,
    legs = 0,
    feet = 0,
    maleOutfit = rawOffer.eid,
    offers = {
      {
        id = rawOffer.id,
        count = rawOffer.count,
        price = rawOffer.price,
        basePrice = rawOffer.price,
        coinType = COIN_TYPE_DEFAULT,
        disabledReasons = {},
        disabledReason = "",
        saleValidUntilTimestamp = 0
      }
    }
  }
  offersById[offer.id] = offer
  return offer
end

local function buildHomeOffers()
  local offers = {}
  for _, category in ipairs(categories) do
    local categoryOffers = offersByCategory[category.name] or {}
    for _, offer in ipairs(categoryOffers) do
      offers[#offers + 1] = offer
      if #offers >= HOME_OFFER_LIMIT then
        return offers
      end
    end
  end
  return offers
end

local function showOffers(actionOrCategory, valueOrServiceType, serviceType)
  if #categories == 0 then
    pendingStoreRequest = { actionOrCategory, valueOrServiceType, serviceType }
    StoreProtocol.openStore()
    return
  end

  local categoryName = tostring(actionOrCategory or "")
  if type(actionOrCategory) == "number" then
    if actionOrCategory == OPEN_HOME then
      categoryName = "Home"
    elseif actionOrCategory == OPEN_SEARCH then
      local query = tostring(valueOrServiceType or ""):lower()
      local result = {}
      for _, offer in pairs(offersById) do
        if offer.name:lower():find(query, 1, true) then
          result[#result + 1] = offer
        end
      end
      signalcall(g_game.onStoreSearchOffers, "Search", result, 0, {})
      return
    elseif actionOrCategory == OPEN_OFFER or actionOrCategory == SERVICE_OFFER_ID then
      local offerId = tonumber(serviceType or valueOrServiceType) or 0
      local offer = offersById[offerId]
      signalcall(g_game.onStoreOffers, offer and offer.filter or "Home", offer and { offer } or {}, offerId, 0, {}, "", {})
      return
    else
      categoryName = tostring(valueOrServiceType or "Home")
    end
  end

  local offers = {}
  if categoryName == "" or categoryName == "Home" then
    signalcall(
      g_game.onStoreHomeOffers,
      "Home",
      buildHomeOffers(),
      homeBannerDelay,
      homeBanners,
      {},
      0,
      {}
    )
    return
  else
    offers = offersByCategory[categoryName] or {}
  end

  signalcall(g_game.onStoreOffers, categoryName, offers, 0, 0, {}, "", {})
end

local function parseCatalog(msg)
  local coins = msg:getU32()
  local categoryCount = msg:getU16()
  categories = {}
  offersByCategory = {}
  offersById = {}

  for i = 1, categoryCount do
    local category = {
      name = msg:getString(),
      icon = msg:getString(),
      parent = msg:getString(),
      description = msg:getString()
    }

    categories[#categories + 1] = category
    offersByCategory[category.name] = {}

    local offerCount = msg:getU16()
    for j = 1, offerCount do
      local rawOffer = {
        id = msg:getU32(),
        name = msg:getString(),
        icon = msg:getString(),
        price = msg:getU32(),
        eid = msg:getU16(),
        count = msg:getU16(),
        description = msg:getString(),
        oftype = msg:getString()
      }
      offersByCategory[category.name][#offersByCategory[category.name] + 1] = buildOffer(rawOffer, category.name)
    end
  end

  homeBanners = {}
  local bannerCount = msg:getU8()
  for i = 1, bannerCount do
    homeBanners[#homeBanners + 1] = {
      msg:getString(),
      msg:getU8(),
      msg:getU32()
    }
  end
  homeBannerDelay = msg:getU8()

  signalcall(g_game.onStoreInit, "", 25)
  signalcall(g_game.onCoinBalance, coins, coins, 0)
  signalcall(g_game.onStoreCategories, categories)

  local pending = pendingStoreRequest
  pendingStoreRequest = nil
  if pending then
    showOffers(pending[1], pending[2], pending[3])
  else
    showOffers(OPEN_HOME, "", 0)
  end
end

local function parseHistory(msg)
  local history = {}
  local count = msg:getU16()
  for i = 1, count do
    local date = msg:getString()
    local price = msg:getU32()
    local positive = msg:getU8() ~= 0
    msg:getU8() -- costSecond
    local title = msg:getString()
    local itemCount = msg:getU16()
    history[#history + 1] = {
      name = title,
      description = date .. " - " .. title,
      price = positive and price or -price,
      count = itemCount
    }
  end
  signalcall(g_game.onStoreTransactionHistory, 0, 1, history)
end

local function onStoreMessage(protocolGame, msg)
  local response = msg:getU8()
  if response == RESP_ERROR then
    signalcall(g_game.onStoreError, 0, msg:getString())
  elseif response == RESP_CATALOG then
    parseCatalog(msg)
  elseif response == RESP_SUCCESS then
    msg:getU32() -- offer id
    local message = msg:getString()
    local coins = msg:getU32()
    signalcall(g_game.onCoinBalance, coins, coins, 0)
    signalcall(g_game.onStorePurchase, message)
  elseif response == RESP_HISTORY then
    parseHistory(msg)
  end
  return true
end

function StoreProtocol.register()
  if registered then
    return
  end
  ProtocolGame.unregisterOpcode(OPCODE_STORE_SEND)
  ProtocolGame.registerOpcode(OPCODE_STORE_SEND, onStoreMessage)
  registered = true
end

function StoreProtocol.unregister()
  if not registered then
    return
  end
  ProtocolGame.unregisterOpcode(OPCODE_STORE_SEND)
  registered = false
end

function StoreProtocol.openStore()
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_STORE_OPEN)
  sendStoreMessage(msg)
end

function StoreProtocol.requestStoreOffers(actionOrCategory, valueOrServiceType, serviceType)
  showOffers(actionOrCategory, valueOrServiceType, serviceType)
end

function StoreProtocol.requestOfferDescription(offerId)
  local offer = offersById[offerId]
  signalcall(g_game.onStoreDescription, offerId, offer and offer.description or "")
end

function StoreProtocol.buyStoreOffer(offerId, productType, name, unknown, offerName)
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_STORE_BUY)
  msg:addU32(offerId)
  if name and name ~= "" then
    msg:addString(name)
  elseif offerName and offerName ~= "" then
    msg:addString(offerName)
  end
  sendStoreMessage(msg)
end

function StoreProtocol.requestHistory()
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_STORE_HISTORY)
  sendStoreMessage(msg)
end

function StoreProtocol.transferCoins(recipient, amount)
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_STORE_TRANSFER)
  msg:addString(recipient)
  msg:addU32(amount)
  sendStoreMessage(msg)
end

function initStoreProtocol()
  connect(g_game, {
    onGameStart = StoreProtocol.register,
    onGameEnd = StoreProtocol.unregister
  })

  g_game.openStore = StoreProtocol.openStore
  g_game.requestStoreOffers = StoreProtocol.requestStoreOffers
  g_game.requestOfferDescription = StoreProtocol.requestOfferDescription
  g_game.buyStoreOffer = StoreProtocol.buyStoreOffer
  g_game.openTransactionHistory = StoreProtocol.requestHistory
  g_game.requestTransactionHistory = StoreProtocol.requestHistory
  g_game.transferCoins = StoreProtocol.transferCoins

  if g_game.isOnline() then
    StoreProtocol.register()
  end
end

function terminateStoreProtocol()
  disconnect(g_game, {
    onGameStart = StoreProtocol.register,
    onGameEnd = StoreProtocol.unregister
  })
  StoreProtocol.unregister()
end
