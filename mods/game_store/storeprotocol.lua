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
local RESP_CATALOG_CHUNK = 4

local CATALOG_CHUNK_START = 1
local CATALOG_CHUNK_END = 2
local CATALOG_CHUNK_TIMEOUT = 10000

local registered = false
local categories = {}
local offersByCategory = {}
local offersById = {}
local homeBanners = {}
local homeBannerDelay = 10
local pendingStoreRequest = nil
local catalogLoaded = false
local catalogRequestPending = false
local currentCoins = 0
local savedGameFunctions = nil
local highlightRefreshEvent = nil
local catalogNeedsRefresh = false
local lastStoreRequest = nil
local catalogChunkActive = false
local catalogChunkExpectedCategories = 0
local catalogChunkCategoryCount = 0
local catalogChunkStartedAt = nil
local catalogChunkTimeoutEvent = nil
local catalogCategoriesByName = {}
local catalogOfferIndexesByCategory = {}

local HOME_OFFER_LIMIT = 6
local DAILY_OFFER_LIMIT = 2

local function normalizeHighlightState(state, validUntilTimestamp)
  state = tonumber(state) or OFFER_STATE_NONE
  if state < OFFER_STATE_NONE or state > OFFER_STATE_TIMED then
    return OFFER_STATE_NONE
  end

  validUntilTimestamp = tonumber(validUntilTimestamp) or 0
  if (state == OFFER_STATE_SALE or state == OFFER_STATE_TIMED) and
      validUntilTimestamp > 0 and validUntilTimestamp <= os.time() then
    return OFFER_STATE_NONE
  end
  return state
end

local function resetCatalogCache()
  removeEvent(highlightRefreshEvent)
  highlightRefreshEvent = nil
  removeEvent(catalogChunkTimeoutEvent)
  catalogChunkTimeoutEvent = nil
  categories = {}
  offersByCategory = {}
  offersById = {}
  homeBanners = {}
  homeBannerDelay = 10
  pendingStoreRequest = nil
  catalogLoaded = false
  catalogRequestPending = false
  currentCoins = 0
  catalogNeedsRefresh = false
  lastStoreRequest = nil
  catalogChunkActive = false
  catalogChunkExpectedCategories = 0
  catalogChunkCategoryCount = 0
  catalogChunkStartedAt = nil
  catalogCategoriesByName = {}
  catalogOfferIndexesByCategory = {}
end

local function sendStoreMessage(msg)
  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    protocolGame:send(msg)
    return true
  end
  return false
end

local function normalizeOfferType(oftype)
  oftype = tostring(oftype or ""):lower()
  if oftype:find("hireling", 1, true) then
    return CATEGORY_HIRELING
  elseif oftype:find("mount", 1, true) then
    return CATEGORY_MOUNT
  elseif oftype:find("outfit", 1, true) then
    return CATEGORY_OUTFIT
  end
  return CATEGORY_ITEM
end

local function buildOffer(rawOffer, categoryName)
  local offerType = normalizeOfferType(rawOffer.oftype)
  local itemId = offerType == CATEGORY_ITEM and rawOffer.eid or 0
  local tryMode = 0
  if rawOffer.eid > 0 and (offerType == CATEGORY_MOUNT or offerType == CATEGORY_OUTFIT) then
    tryMode = 1
  end

  local validUntilTimestamp = tonumber(rawOffer.saleValidUntilTimestamp) or 0
  local state = normalizeHighlightState(rawOffer.state, validUntilTimestamp)
  local offer = {
    id = rawOffer.id,
    name = rawOffer.name,
    description = rawOffer.description,
    filter = categoryName or "",
    icon = rawOffer.icon or "",
    storeSubtype = tostring(rawOffer.oftype or ""):lower(),
    itemId = itemId,
    offerType = offerType,
    state = state,
    highlightState = tonumber(rawOffer.state) or OFFER_STATE_NONE,
    TimesBought = 0,
    discountPrice = rawOffer.price,
    expireTime = validUntilTimestamp,
    purchased = false,
    mountId = rawOffer.eid,
    type = rawOffer.eid,
    head = 0,
    body = 0,
    legs = 0,
    feet = 0,
    maleOutfit = rawOffer.eid,
    tryMode = tryMode,
    offers = {
      {
        id = rawOffer.id,
        count = rawOffer.count,
        price = rawOffer.price,
        basePrice = rawOffer.basePrice or rawOffer.price,
        coinType = COIN_TYPE_DEFAULT,
        disabledReasons = {},
        disabledReason = "",
        saleValidUntilTimestamp = validUntilTimestamp
      }
    }
  }
  offersById[offer.id] = offer
  return offer
end

local function combineHighlightState(current, candidate)
  if candidate == OFFER_STATE_SALE then
    return OFFER_STATE_SALE
  end
  if candidate == OFFER_STATE_TIMED and current ~= OFFER_STATE_SALE then
    return OFFER_STATE_TIMED
  end
  if candidate == OFFER_STATE_NEW and current == OFFER_STATE_NONE then
    return OFFER_STATE_NEW
  end
  return current
end

local function refreshHighlightStates()
  local now = os.time()
  local expired = false
  local activeCategoryStates = {}

  for _, offer in pairs(offersById) do
    local expiresAt = offer.offers[1].saleValidUntilTimestamp or 0
    local refreshedState = normalizeHighlightState(offer.highlightState, expiresAt)
    if offer.state ~= refreshedState and refreshedState == OFFER_STATE_NONE then
      expired = true
    end
    offer.state = refreshedState
    if refreshedState ~= OFFER_STATE_NONE then
      activeCategoryStates[offer.filter] = combineHighlightState(
        activeCategoryStates[offer.filter] or OFFER_STATE_NONE,
        refreshedState
      )
    end
  end

  -- Propagate an active child highlight to its parent category button.
  for _ = 1, #categories do
    local changed = false
    for _, category in ipairs(categories) do
      local childState = activeCategoryStates[category.name]
      if childState and category.parent ~= "" then
        local previous = activeCategoryStates[category.parent] or OFFER_STATE_NONE
        local combined = combineHighlightState(previous, childState)
        if combined ~= previous then
          activeCategoryStates[category.parent] = combined
          changed = true
        end
      end
    end
    if not changed then
      break
    end
  end

  for _, category in ipairs(categories) do
    local originalState = category.highlightState or OFFER_STATE_NONE
    local activeState = activeCategoryStates[category.name] or OFFER_STATE_NONE
    if originalState >= OFFER_STATE_NONE and originalState <= OFFER_STATE_TIMED then
      category.state = combineHighlightState(originalState, activeState)
    else
      category.state = originalState
    end
  end

  return expired
end

local function scheduleHighlightRefresh()
  removeEvent(highlightRefreshEvent)
  highlightRefreshEvent = nil

  local now = os.time()
  local earliestExpiry = nil
  for _, offer in pairs(offersById) do
    local state = offer.highlightState
    local expiresAt = offer.offers[1].saleValidUntilTimestamp or 0
    if (state == OFFER_STATE_SALE or state == OFFER_STATE_TIMED) and expiresAt > now and
        (not earliestExpiry or expiresAt < earliestExpiry) then
      earliestExpiry = expiresAt
    end
  end

  if not earliestExpiry then
    return
  end

  highlightRefreshEvent = scheduleEvent(function()
    highlightRefreshEvent = nil
    refreshHighlightStates()
    catalogNeedsRefresh = true
    if StoreWindow and StoreWindow:isVisible() and g_game.isOnline() then
      local request = lastStoreRequest or { OPEN_HOME, "", 0 }
      StoreProtocol.forceRefresh(request[1], request[2], request[3])
    end
  end, math.max(1, (earliestExpiry - now) * 1000 + 50))
end

local function buildHomeOffers()
  refreshHighlightStates()
  local offers = {}
  for _, category in ipairs(categories) do
    local categoryOffers = offersByCategory[category.name] or {}
    for _, offer in ipairs(categoryOffers) do
      -- Recently Added is a semantic NEW-only view. SALE/TIMED entries belong
      -- to Daily Offers and must never be promoted here merely because they
      -- are highlighted.
      if offer.state == OFFER_STATE_NEW then
        offers[#offers + 1] = offer
        if #offers >= HOME_OFFER_LIMIT then
          return offers
        end
      end
    end
  end
  return offers
end

local function buildDailyOffers()
  refreshHighlightStates()
  local offers = {}
  local now = os.time()
  for _, category in ipairs(categories) do
    for _, offer in ipairs(offersByCategory[category.name] or {}) do
      local expires = offer.offers[1].saleValidUntilTimestamp or 0
      if (offer.state == OFFER_STATE_SALE or offer.state == OFFER_STATE_TIMED) and expires > now then
        offers[#offers + 1] = offer
      end
    end
  end

  table.sort(offers, function(left, right)
    local leftExpiry = left.offers[1].saleValidUntilTimestamp or 0
    local rightExpiry = right.offers[1].saleValidUntilTimestamp or 0
    if leftExpiry == rightExpiry then
      return left.id < right.id
    end
    return leftExpiry < rightExpiry
  end)
  while #offers > DAILY_OFFER_LIMIT do
    table.remove(offers)
  end
  return offers
end

local function showOffers(actionOrCategory, valueOrServiceType, serviceType)
  lastStoreRequest = { actionOrCategory, valueOrServiceType, serviceType }
  if not catalogLoaded then
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
      buildDailyOffers()
    )
    return
  else
    offers = offersByCategory[categoryName] or {}
  end

  signalcall(g_game.onStoreOffers, categoryName, offers, 0, 0, {}, "", {})
end

local function beginCatalog(coins)
  removeEvent(catalogChunkTimeoutEvent)
  catalogChunkTimeoutEvent = nil
  categories = {}
  offersByCategory = {}
  offersById = {}
  homeBanners = {}
  homeBannerDelay = 10
  catalogCategoriesByName = {}
  catalogOfferIndexesByCategory = {}
  catalogChunkCategoryCount = 0
  catalogLoaded = false
  currentCoins = coins
end

local function parseCatalogCategory(msg)
  local name = msg:getString()
  local icon = msg:getString()
  local parent = msg:getString()
  local description = msg:getString()
  local highlightState = OFFER_STATE_NONE
  if g_game.getFeature(GameIngameStoreHighlights) then
    highlightState = msg:getU8()
  end

  local category = catalogCategoriesByName[name]
  if not category then
    category = {
      name = name,
      icon = icon,
      parent = parent,
      description = description,
      state = normalizeHighlightState(highlightState, 0),
      highlightState = highlightState
    }
    categories[#categories + 1] = category
    offersByCategory[name] = {}
    catalogOfferIndexesByCategory[name] = {}
    catalogCategoriesByName[name] = category
    catalogChunkCategoryCount = catalogChunkCategoryCount + 1
  end

  local offerCount = msg:getU16()
  for i = 1, offerCount do
    local rawOffer = {
      id = msg:getU32(),
      name = msg:getString(),
      icon = msg:getString(),
      price = msg:getU32()
    }
    -- The extra original price has its own negotiated capability. Reusing
    -- the highlights flag would desynchronize mixed client/server versions.
    if g_game.getFeature(GameAstraStoreBasePrice) then
      rawOffer.basePrice = msg:getU32()
    else
      rawOffer.basePrice = rawOffer.price
    end
    rawOffer.eid = msg:getU16()
    rawOffer.count = msg:getU16()
    rawOffer.description = msg:getString()
    rawOffer.oftype = msg:getString()
    if g_game.getFeature(GameIngameStoreHighlights) then
      rawOffer.state = msg:getU8()
      if rawOffer.state == OFFER_STATE_SALE or rawOffer.state == OFFER_STATE_TIMED then
        rawOffer.saleValidUntilTimestamp = msg:getU32()
      end
    end
    local categoryOffers = offersByCategory[name]
    local offerIndexes = catalogOfferIndexesByCategory[name]
    local offer = buildOffer(rawOffer, name)
    local existingIndex = offerIndexes[rawOffer.id]
    if existingIndex then
      categoryOffers[existingIndex] = offer
    else
      categoryOffers[#categoryOffers + 1] = offer
      offerIndexes[rawOffer.id] = #categoryOffers
    end
  end
end

local function parseCatalogBanners(msg)
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
end

local function finishCatalog(coins, startedAt)
  removeEvent(catalogChunkTimeoutEvent)
  catalogChunkTimeoutEvent = nil
  currentCoins = coins
  catalogLoaded = true
  catalogRequestPending = false
  catalogNeedsRefresh = false
  catalogChunkActive = false
  catalogChunkExpectedCategories = 0
  catalogChunkCategoryCount = 0
  catalogChunkStartedAt = nil
  catalogCategoriesByName = {}
  catalogOfferIndexesByCategory = {}
  refreshHighlightStates()
  scheduleHighlightRefresh()

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
  Store:profileStep("parseCatalog", startedAt)
end

local function parseCatalog(msg)
  local startedAt = g_clock.millis()
  local coins = msg:getU32()
  local categoryCount = msg:getU16()
  beginCatalog(coins)

  for i = 1, categoryCount do
    parseCatalogCategory(msg)
  end

  parseCatalogBanners(msg)
  finishCatalog(coins, startedAt)
end

local function parseCatalogChunk(msg)
  local flags = msg:getU8()
  local coins = msg:getU32()
  local expectedCategories = msg:getU16()
  local categoryPartCount = msg:getU16()
  if flags ~= 0 and flags ~= CATALOG_CHUNK_START and flags ~= CATALOG_CHUNK_END and
      flags ~= CATALOG_CHUNK_START + CATALOG_CHUNK_END then
    msg:skipBytes(msg:getUnreadSize())
    resetCatalogCache()
    signalcall(g_game.onStoreError, 0, "Invalid Store catalog chunk flags.")
    return
  end

  local isStart = flags == CATALOG_CHUNK_START or flags == CATALOG_CHUNK_START + CATALOG_CHUNK_END
  local isEnd = flags == CATALOG_CHUNK_END or flags == CATALOG_CHUNK_START + CATALOG_CHUNK_END

  if isStart then
    if catalogChunkActive then
      msg:skipBytes(msg:getUnreadSize())
      resetCatalogCache()
      signalcall(g_game.onStoreError, 0, "Invalid Store catalog chunk sequence.")
      return
    end
    beginCatalog(coins)
    catalogChunkActive = true
    catalogChunkExpectedCategories = expectedCategories
    catalogChunkStartedAt = g_clock.millis()
  elseif not catalogChunkActive or expectedCategories ~= catalogChunkExpectedCategories or coins ~= currentCoins then
    msg:skipBytes(msg:getUnreadSize())
    resetCatalogCache()
    signalcall(g_game.onStoreError, 0, "Invalid Store catalog chunk sequence.")
    return
  end

  for i = 1, categoryPartCount do
    parseCatalogCategory(msg)
  end

  if not isEnd then
    removeEvent(catalogChunkTimeoutEvent)
    catalogChunkTimeoutEvent = scheduleEvent(function()
      catalogChunkTimeoutEvent = nil
      if catalogChunkActive then
        resetCatalogCache()
        signalcall(g_game.onStoreError, 0, "Store catalog transfer timed out. Please reopen the Store.")
      end
    end, CATALOG_CHUNK_TIMEOUT)
    return
  end

  parseCatalogBanners(msg)
  if catalogChunkCategoryCount ~= catalogChunkExpectedCategories then
    resetCatalogCache()
    signalcall(g_game.onStoreError, 0, "Incomplete Store catalog received.")
    return
  end

  finishCatalog(coins, catalogChunkStartedAt)
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
    local message = msg:getString()
    if catalogChunkActive then
      resetCatalogCache()
    else
      catalogRequestPending = false
    end
    signalcall(g_game.onStoreError, 0, message)
  elseif response == RESP_CATALOG then
    parseCatalog(msg)
  elseif response == RESP_CATALOG_CHUNK then
    parseCatalogChunk(msg)
  elseif response == RESP_SUCCESS then
    msg:getU32() -- offer id
    local message = msg:getString()
    local coins = msg:getU32()
    currentCoins = coins
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
  resetCatalogCache()
  ProtocolGame.unregisterOpcode(OPCODE_STORE_SEND)
  ProtocolGame.registerOpcode(OPCODE_STORE_SEND, onStoreMessage)
  registered = true
end

function StoreProtocol.unregister()
  if registered then
    ProtocolGame.unregisterOpcode(OPCODE_STORE_SEND)
    registered = false
  end
  resetCatalogCache()
end

function StoreProtocol.openStore(forceRefresh)
  if not g_game.isOnline() then
    return
  end
  if showStoreWindow then
    showStoreWindow()
  end

  if forceRefresh then
    resetCatalogCache()
  elseif catalogLoaded then
    if catalogNeedsRefresh or refreshHighlightStates() then
      return StoreProtocol.forceRefresh()
    end
    signalcall(g_game.onStoreInit, "", 25)
    signalcall(g_game.onCoinBalance, currentCoins, currentCoins, 0)
    if StoreWindow and Offers and Offers.displayPanel then
      showStoreWindow()
    else
      signalcall(g_game.onStoreCategories, categories)
      showOffers(OPEN_HOME, "", 0)
    end
    return
  elseif catalogRequestPending then
    return
  end

  catalogRequestPending = true
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_STORE_OPEN)
  if not sendStoreMessage(msg) then
    catalogRequestPending = false
  end
end

function StoreProtocol.forceRefresh(actionOrCategory, valueOrServiceType, serviceType)
  local request = actionOrCategory ~= nil and
    { actionOrCategory, valueOrServiceType, serviceType } or
    lastStoreRequest or { OPEN_HOME, "", 0 }
  resetCatalogCache()
  pendingStoreRequest = request
  lastStoreRequest = request
  StoreProtocol.openStore(false)
end

function StoreProtocol.isCatalogLoaded()
  return catalogLoaded
end

function StoreProtocol.getOfferBySubtype(subtype)
  subtype = tostring(subtype or ""):lower()
  for _, offer in pairs(offersById) do
    if offer.storeSubtype == subtype then
      return offer
    end
  end
  return nil
end

function StoreProtocol.requestStoreOffers(actionOrCategory, valueOrServiceType, serviceType)
  showOffers(actionOrCategory, valueOrServiceType, serviceType)
end

function StoreProtocol.requestOfferDescription(offerId)
  local offer = offersById[offerId]
  signalcall(g_game.onStoreDescription, offerId, offer and offer.description or "")
end

function StoreProtocol.buyStoreOffer(offerId, productType, name, unknown)
  local msg = OutputMessage.create()
  msg:addU8(OPCODE_STORE_BUY)
  msg:addU32(offerId)
  if productType == OFFER_BUY_TYPE_HIRELING then
    msg:addString(name or "")
    msg:addU8(tonumber(unknown) or 1)
  elseif productType == OFFER_BUY_TYPE_NAMECHANGE or productType == OFFER_BUY_TYPE_TRANSFER then
    msg:addString(name or "")
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
  Store.singleCoinBalance = true

  savedGameFunctions = savedGameFunctions or {
    openStore = g_game.openStore,
    forceRefreshStore = g_game.forceRefreshStore,
    getStoreOfferBySubtype = g_game.getStoreOfferBySubtype,
    requestStoreOffers = g_game.requestStoreOffers,
    requestOfferDescription = g_game.requestOfferDescription,
    buyStoreOffer = g_game.buyStoreOffer,
    openTransactionHistory = g_game.openTransactionHistory,
    requestTransactionHistory = g_game.requestTransactionHistory,
    transferCoins = g_game.transferCoins
  }

  connect(g_game, {
    onGameStart = StoreProtocol.register,
    onGameEnd = StoreProtocol.unregister
  })

  g_game.openStore = StoreProtocol.openStore
  g_game.forceRefreshStore = StoreProtocol.forceRefresh
  g_game.getStoreOfferBySubtype = StoreProtocol.getOfferBySubtype
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
  Store.singleCoinBalance = false

  disconnect(g_game, {
    onGameStart = StoreProtocol.register,
    onGameEnd = StoreProtocol.unregister
  })
  StoreProtocol.unregister()

  if savedGameFunctions then
    g_game.openStore = savedGameFunctions.openStore
    g_game.forceRefreshStore = savedGameFunctions.forceRefreshStore
    g_game.getStoreOfferBySubtype = savedGameFunctions.getStoreOfferBySubtype
    g_game.requestStoreOffers = savedGameFunctions.requestStoreOffers
    g_game.requestOfferDescription = savedGameFunctions.requestOfferDescription
    g_game.buyStoreOffer = savedGameFunctions.buyStoreOffer
    g_game.openTransactionHistory = savedGameFunctions.openTransactionHistory
    g_game.requestTransactionHistory = savedGameFunctions.requestTransactionHistory
    g_game.transferCoins = savedGameFunctions.transferCoins
    savedGameFunctions = nil
  end
end
