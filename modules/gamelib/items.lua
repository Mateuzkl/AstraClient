ItemsDatabase = ItemsDatabase or {}

ItemsDatabase.rarityColors = ItemsDatabase.rarityColors or {
  gold = '#F0F000',
  yellow = '#F0F000',
  purple = '#FF68FF',
  blue = '#20A0FF',
  green = '#00F000',
  grey = '#AAAAAA',
  white = '#F0F0F0'
}

ItemsDatabase.rarityFrameImage = '/images/ui/rarity_frames'
ItemsDatabase.rarityCornerFrameImage = '/images/ui/containerslot-coloredges'

local function isRarityImageSource(source)
  return type(source) == 'string' and (
    source:find('/images/ui/rarity_', 1, true) or
    source:find('/images/ui/containerslot-coloredges', 1, true)
  )
end

local function getRarityDefaultImageSource(widget)
  if widget.rarityDefaultImageSource ~= nil and not isRarityImageSource(widget.rarityDefaultImageSource) then
    return widget.rarityDefaultImageSource
  end

  if widget.getImageSource then
    local source = widget:getImageSource()
    if source ~= nil and not isRarityImageSource(source) then
      widget.rarityDefaultImageSource = source
      return source
    end
  end

  local className = widget.getClassName and widget:getClassName() or nil
  if className == 'Item' then
    widget.rarityDefaultImageSource = '/images/ui/item'
  elseif className == 'BigItem' then
    widget.rarityDefaultImageSource = '/images/ui/item66'
  else
    widget.rarityDefaultImageSource = ''
  end

  return widget.rarityDefaultImageSource
end

local function isRarityDisabledValue(value)
  return value == false or value == 'false' or value == 0 or value == '0'
end

local function shouldDrawRarityOnWidget(widget)
  local current = widget
  while current do
    if isRarityDisabledValue(current.drawRarity) then
      return false
    end
    current = current.getParent and current:getParent() or nil
  end
  return true
end

function ItemsDatabase.shouldDrawRarity(widget)
  return shouldDrawRarityOnWidget(widget)
end

local function isInventoryRarityWidget(widget)
  local current = widget
  while current do
    if current.getId and current:getId() == 'inventoryWindow' then
      return true
    end
    current = current.getParent and current:getParent() or nil
  end
  return false
end

local function getRarityClipForValue(value)
  value = tonumber(value) or 0

  if value >= 1000000 then
    return '128 0 32 32'
  elseif value >= 100000 then
    return '96 0 32 32'
  elseif value >= 10000 then
    return '64 0 32 32'
  elseif value >= 1000 then
    return '32 0 32 32'
  elseif value >= 50 then
    return '0 0 32 32'
  end

  return nil
end

local function toClipObject(clip)
  if not clip then
    return nil
  end

  local x, y, width, height = clip:match('(%d+) (%d+) (%d+) (%d+)')
  if not x then
    return nil
  end

  return { x = tonumber(x), y = tonumber(y), width = tonumber(width), height = tonumber(height) }
end

ItemsDatabase.fixedValues = ItemsDatabase.fixedValues or {
  [3031] = 1,
  [3035] = 100,
  [3043] = 10000
}

ItemsDatabase.serverValues = ItemsDatabase.serverValues or {}
ItemsDatabase.serverDetails = ItemsDatabase.serverDetails or {}
ItemsDatabase.lootValueState = ItemsDatabase.lootValueState or 1
ItemsDatabase.serverValueCacheLoaded = ItemsDatabase.serverValueCacheLoaded or false
ItemsDatabase.serverValueCacheSaveEvent = ItemsDatabase.serverValueCacheSaveEvent or nil
ItemsDatabase.rarityFrameRefreshEvent = ItemsDatabase.rarityFrameRefreshEvent or nil

local function getServerValueCacheFile()
  if not LoadedPlayer or not LoadedPlayer.isLoaded or not LoadedPlayer:isLoaded() then
    return nil
  end

  if not g_resources.directoryExists("/characterdata/") then
    g_resources.makeDir("/characterdata/")
  end

  local directory = "/characterdata/" .. LoadedPlayer:getId() .. "/"
  if not g_resources.directoryExists(directory) then
    g_resources.makeDir(directory)
  end

  return directory .. "itemprices.json"
end

local function readServerValueCache()
  local file = getServerValueCacheFile()
  if not file or not g_resources.fileExists(file) then
    return {}
  end

  local ok, data = pcall(function()
    return json.decode(g_resources.readFileContents(file))
  end)

  if ok and type(data) == 'table' then
    return data
  end
  return {}
end

function ItemsDatabase.loadServerValueCache()
  if ItemsDatabase.serverValueCacheLoaded then
    return
  end

  local data = readServerValueCache()
  for k, value in pairs(data.serverValues or {}) do
    local itemId = tonumber(k)
    local itemValue = tonumber(value)
    if itemId and itemId > 0 and itemValue and itemValue > 0 and not ItemsDatabase.serverValues[itemId] then
      ItemsDatabase.serverValues[itemId] = itemValue
    end
  end

  for k, details in pairs(data.serverDetails or {}) do
    local itemId = tonumber(k)
    if itemId and itemId > 0 and type(details) == 'table' and not ItemsDatabase.serverDetails[itemId] then
      ItemsDatabase.serverDetails[itemId] = details
    end
  end

  ItemsDatabase.serverValueCacheLoaded = true
  ItemsDatabase.scheduleRarityFrameRefresh()
end

function ItemsDatabase.saveServerValueCache()
  local file = getServerValueCacheFile()
  if not file then
    return
  end

  local data = readServerValueCache()
  data.primaryLootValueSources = data.primaryLootValueSources or {}
  data.customSalePrices = data.customSalePrices or {}
  data.serverValues = data.serverValues or {}
  data.serverDetails = data.serverDetails or {}

  for itemId, value in pairs(ItemsDatabase.serverValues or {}) do
    local key = tostring(itemId)
    data.serverValues[key] = tonumber(value) or 0
  end

  for itemId, details in pairs(ItemsDatabase.serverDetails or {}) do
    if type(details) == 'table' then
      data.serverDetails[tostring(itemId)] = {
        name = details.name,
        defaultValue = details.defaultValue,
        defaultBuyPrice = details.defaultBuyPrice,
        averageMarketValue = details.averageMarketValue
      }
    end
  end

  local ok, encoded = pcall(function()
    return json.encode(data, 2)
  end)
  if ok and encoded then
    g_resources.writeFileContents(file, encoded)
  end
end

function ItemsDatabase.scheduleServerValueCacheSave()
  if ItemsDatabase.serverValueCacheSaveEvent then
    return
  end

  ItemsDatabase.serverValueCacheSaveEvent = scheduleEvent(function()
    ItemsDatabase.serverValueCacheSaveEvent = nil
    ItemsDatabase.saveServerValueCache()
  end, 500)
end

if not ItemsDatabase.serverValueCacheConnected then
  ItemsDatabase.serverValueCacheConnected = true
  connect(g_game, {
    onGameStart = function()
      ItemsDatabase.serverValues = {}
      ItemsDatabase.serverDetails = {}
      ItemsDatabase.serverValueCacheLoaded = false
      scheduleEvent(ItemsDatabase.loadServerValueCache, 100)
    end,
    onGameEnd = ItemsDatabase.saveServerValueCache
  })
end

local function clampLootValueState(value)
  value = tonumber(value) or 0
  return math.min(math.max(value, 0), 2)
end

function g_game.setLootValueState(value)
  ItemsDatabase.lootValueState = clampLootValueState(value)
end

g_game.getLootValueState = g_game.getLootValueState or function()
  return ItemsDatabase.lootValueState
end

local function refreshRarityWidget(widget)
  if not widget or (widget.isDestroyed and widget:isDestroyed()) then
    return
  end

  if widget.getItem and widget.setImageSource and shouldDrawRarityOnWidget(widget) then
    local ok, item = pcall(function()
      return widget:getItem()
    end)
    if ok then
      ItemsDatabase.setRarityItem(widget, item)
    end
  end

  if not widget.getChildren then
    return
  end

  for _, child in pairs(widget:getChildren()) do
    refreshRarityWidget(child)
  end
end

function ItemsDatabase.refreshVisibleRarityFrames()
  local root = (g_ui and g_ui.getRootWidget and g_ui.getRootWidget()) or rootWidget
  if root then
    refreshRarityWidget(root)
  end
end

function ItemsDatabase.scheduleRarityFrameRefresh()
  if ItemsDatabase.rarityFrameRefreshEvent then
    return
  end

  ItemsDatabase.rarityFrameRefreshEvent = scheduleEvent(function()
    ItemsDatabase.rarityFrameRefreshEvent = nil
    ItemsDatabase.refreshVisibleRarityFrames()
  end, 50)
end

function ItemsDatabase.registerServerItemValue(itemId, value)
  itemId = tonumber(itemId)
  value = tonumber(value)
  if itemId and itemId > 0 and value and value > 0 then
    ItemsDatabase.serverValues[itemId] = value
    ItemsDatabase.scheduleServerValueCacheSave()
    ItemsDatabase.scheduleRarityFrameRefresh()
  end
end

function ItemsDatabase.registerServerItemDetails(itemId, details)
  itemId = tonumber(itemId)
  if not itemId or itemId <= 0 or type(details) ~= 'table' then
    return
  end

  ItemsDatabase.serverDetails[itemId] = details
  ItemsDatabase.scheduleServerValueCacheSave()
  ItemsDatabase.scheduleRarityFrameRefresh()

  local value = tonumber(details.defaultValue) or 0
  if value <= 0 then
    value = tonumber(details.averageMarketValue) or 0
  end
  if value > 0 then
    ItemsDatabase.registerServerItemValue(itemId, value)
  end
end

function ItemsDatabase.getServerItemDetails(itemId)
  return ItemsDatabase.serverDetails[tonumber(itemId) or 0]
end

function ItemsDatabase.hasServerItemDetails(itemId)
  return ItemsDatabase.getServerItemDetails(itemId) ~= nil
end

local function safeCall(object, method)
  if not object or not object[method] then
    return nil
  end

  local ok, value = pcall(function()
    return object[method](object)
  end)

  if ok then
    return tonumber(value) or 0
  end

  return nil
end

local function getNpcPriceValue(item)
  if not item or not item.getNPCSaleData then
    return 0
  end

  local ok, npcData = pcall(function()
    return item:getNPCSaleData()
  end)

  if not ok or type(npcData) ~= 'table' then
    return 0
  end

  local bestBuyPrice = 0
  local bestSellPrice = 0
  for _, offer in pairs(npcData) do
    if type(offer) == 'table' then
      local buyPrice = tonumber(offer.buyPrice or offer.buy or offer.itemBuyPrice) or 0
      local sellPrice = tonumber(offer.salePrice or offer.sellPrice or offer.sell or offer.itemSellPrice) or 0
      bestBuyPrice = math.max(bestBuyPrice, buyPrice)
      bestSellPrice = math.max(bestSellPrice, sellPrice)
    end
  end

  return bestSellPrice > 0 and bestSellPrice or bestBuyPrice
end

function ItemsDatabase.hasColorLootMarkup(text)
  return type(text) == 'string' and text:find('{%d+:?%d*|.-}') ~= nil
end

function ItemsDatabase.getItemValue(itemOrId)
  local item = itemOrId
  local itemId = tonumber(itemOrId)

  if type(itemOrId) ~= 'number' and type(itemOrId) ~= 'string' and itemOrId and itemOrId.getId then
    local ok, id = pcall(function()
      return itemOrId:getId()
    end)

    if ok then
      itemId = tonumber(id)
    end
  end

  if itemId and ItemsDatabase.fixedValues[itemId] then
    return ItemsDatabase.fixedValues[itemId]
  end

  local details = itemId and ItemsDatabase.getServerItemDetails(itemId) or nil
  if details then
    local value = tonumber(details.defaultValue) or 0
    if value > 0 then
      return value
    end
    value = tonumber(details.averageMarketValue) or 0
    if value > 0 then
      return value
    end
  end

  if itemId and ItemsDatabase.serverValues[itemId] then
    return ItemsDatabase.serverValues[itemId]
  end

  local prices = Analyzer and Analyzer.analyzers and Analyzer.analyzers.customPrices or {}
  local customValue = itemId and (prices[tostring(itemId)] or prices[itemId])
  if tonumber(customValue) and tonumber(customValue) > 0 then
    return tonumber(customValue)
  end

  if type(itemOrId) == 'number' or type(itemOrId) == 'string' then
    item = itemId and Item and Item.create and Item.create(itemId, 1) or nil
  end

  local value = safeCall(item, 'getPriceValue')
  if value and value > 0 then
    return value
  end

  value = safeCall(item, 'getAverageMarketValue')
  if value and value > 0 then
    return value
  end

  value = safeCall(item, 'getDefaultValue')
  if value and value > 0 then
    return value
  end

  value = getNpcPriceValue(item)
  if value and value > 0 then
    return value
  end

  local cyclopediaItems = modules and modules.game_cyclopedia and modules.game_cyclopedia.CyclopediaItems
  if cyclopediaItems and cyclopediaItems.getCurrentItemValue and item then
    local ok, currentValue = pcall(function()
      return cyclopediaItems.getCurrentItemValue(item)
    end)

    if ok and tonumber(currentValue) and tonumber(currentValue) > 0 then
      return tonumber(currentValue)
    end
  end

  local thingType = itemId and g_things and g_things.findItemTypeByClientId and g_things.findItemTypeByClientId(itemId)
  value = safeCall(thingType, 'getMeanPrice')
  if value and value > 0 then
    return value
  end

  return 0
end

function ItemsDatabase.getRarityForValue(value)
  value = tonumber(value) or 0

  if value >= 1000000 then
    return 'gold'
  elseif value >= 100000 then
    return 'purple'
  elseif value >= 10000 then
    return 'blue'
  elseif value >= 1000 then
    return 'green'
  elseif value >= 50 then
    return 'white'
  end

  return nil
end

function ItemsDatabase.getColorForValue(value)
  value = tonumber(value) or 0

  if value >= 1000000 then
    return ItemsDatabase.rarityColors.gold
  elseif value >= 100000 then
    return ItemsDatabase.rarityColors.purple
  elseif value >= 10000 then
    return ItemsDatabase.rarityColors.blue
  elseif value >= 1000 then
    return ItemsDatabase.rarityColors.green
  elseif value >= 50 then
    return ItemsDatabase.rarityColors.grey
  end

  return ItemsDatabase.rarityColors.white
end

function ItemsDatabase.getItemColor(itemOrId)
  return ItemsDatabase.getColorForValue(ItemsDatabase.getItemValue(itemOrId))
end

function ItemsDatabase.getRarityFrame(itemOrId, corner)
  local clip, imagePath = ItemsDatabase.getClipAndImagePath(itemOrId, corner)
  return clip and imagePath or nil
end

function ItemsDatabase.getClipAndImagePath(itemOrId, corner, defaultImageSource)
  if not itemOrId then
    return nil, nil, nil
  end

  local state = ItemsDatabase.getLootValueState(corner)
  if state <= 0 then
    return nil, defaultImageSource, nil
  end

  local clip = getRarityClipForValue(ItemsDatabase.getItemValue(itemOrId))
  local imagePath = clip and (state == 2 and ItemsDatabase.rarityCornerFrameImage or ItemsDatabase.rarityFrameImage) or defaultImageSource

  return clip, imagePath, toClipObject(clip)
end

function ItemsDatabase.getLootValueState(corner)
  if corner ~= nil then
    return corner and 2 or 1
  end

  local state = ItemsDatabase.lootValueState
  if g_game.getLootValueState then
    local ok, value = pcall(function()
      return g_game.getLootValueState()
    end)

    if ok then
      state = value
    end
  end

  return clampLootValueState(state)
end

function ItemsDatabase.setColorLootMessage(text, defaultColor)
  local result = {}
  local lastEnd = 1

  if type(text) == 'string' and (text:find('^Loot of ') or text:find('^Loot de ')) then
    defaultColor = ItemsDatabase.rarityColors.green
  else
    defaultColor = defaultColor or ItemsDatabase.rarityColors.white
  end

  local function add(textPart, color)
    if textPart and textPart ~= '' then
      table.insert(result, textPart)
      table.insert(result, color or defaultColor)
    end
  end

  if type(text) ~= 'string' then
    return result
  end

  for start, itemId, itemValue, itemText, finish in text:gmatch('(){(%d+):?(%d*)|(.-)}()') do
    itemId = tonumber(itemId)
    itemValue = tonumber(itemValue)
    if itemId and itemValue and itemValue > 0 then
      ItemsDatabase.registerServerItemValue(itemId, itemValue)
    end

    add(text:sub(lastEnd, start - 1), defaultColor)
    add(itemText, itemValue and ItemsDatabase.getColorForValue(itemValue) or ItemsDatabase.getItemColor(itemId))
    lastEnd = finish
  end

  add(text:sub(lastEnd), defaultColor)
  return result
end

function ItemsDatabase.setRarityItem(widget, item, corner)
  if not widget or not widget.setImageSource then
    return
  end

  local defaultImageSource = getRarityDefaultImageSource(widget)
  local defaultImageClip = defaultImageSource == '/images/ui/item66' and '0 0 66 66' or '0 0 34 34'

  if not shouldDrawRarityOnWidget(widget) then
    if widget.setImageClip then
      widget:setImageClip(defaultImageClip)
    end
    widget:setImageSource(defaultImageSource or '')
    return
  end

  pcall(function()
    if isInventoryRarityWidget(widget) then
      return
    end

    local enabled = not g_game.getFeature or g_game.getFeature(GameColorizedLootValue)
    local clip, imagePath
    if enabled then
      clip, imagePath = ItemsDatabase.getClipAndImagePath(item, corner, defaultImageSource)
    end

    if widget.setImageClip then
      widget:setImageClip(clip or defaultImageClip)
    end

    widget:setImageSource(imagePath or defaultImageSource or '')
  end)
end

local function clampTier(tier, maxTier)
  tier = tonumber(tier) or 0
  return math.min(math.max(tier, 0), maxTier)
end

function ItemsDatabase.getTierClip(tier, big)
  local width = big and 18 or 9
  local height = big and 16 or 8
  local normalizedTier = clampTier(tier, 10)

  if normalizedTier <= 0 then
    return nil
  end

  return {
    x = (normalizedTier - 1) * width,
    y = 0,
    width = width,
    height = height
  }
end

function ItemsDatabase.setTier(widget, item, big)
  if not widget or not widget.tier then
    return
  end

  if not g_game.getFeature(GameThingUpgradeClassification) and not g_game.getFeature(GameItemTierByte) then
    widget.tier:setVisible(false)
    return
  end

  if big == nil then
    big = widget:getWidth() > 34
  end

  local tier = 0
  if type(item) == 'number' then
    tier = item
  elseif item and item.getTier then
    local ok, itemTier = pcall(function() return item:getTier() end)
    if ok then
      tier = itemTier or 0
    end
  end

  local clip = ItemsDatabase.getTierClip(tier, big)
  if not clip then
    widget.tier:setVisible(false)
    return
  end

  local size = big and '18 16' or '9 8'
  widget.tier:setImageSource(big and '/images/game/items/tiers-strip-big' or '/images/game/items/tiers-strip')
  widget.tier:setImageClip(clip)
  widget.tier:setImageSize(size)
  widget.tier:setSize(size)
  widget.tier:setVisible(true)
end
