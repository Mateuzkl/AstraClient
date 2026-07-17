local listItems = {}
gameStashWindown = nil
itemsPanel = nil
countWithdraw = nil
stowContainer = nil

local sellerOption = nil
local stashOption = nil
local otherOption = nil
local refreshStashEvent = nil
local rebuildingOptions = false

local supplyStashProtocolRegistered = false
local OPCODE_SUPPLY_STASH_REQUEST = 0x28
local OPCODE_SUPPLY_STASH_SEND = 0x29
local SUPPLY_STASH_DETAILS_MARKER = 0x5354
local ACTION_STOW_ALL = 2
local ACTION_WITHDRAW = 3

local marketCategoryNames = {
  [1] = "Armors",
  [2] = "Amulets",
  [3] = "Boots",
  [6] = "Food",
  [7] = "Helmets and Hats",
  [8] = "Legs",
  [9] = "Others",
  [10] = "Potions",
  [12] = "Runes",
  [13] = "Shields",
  [14] = "Tools",
  [15] = "Valuables",
  [16] = "Ammunition",
  [17] = "Axes",
  [18] = "Clubs",
  [19] = "Distance Weapons",
  [20] = "Swords",
  [21] = "Wands and Rods",
  [24] = "Creature Products"
}

local imbuementSourceIds = {
  5877, 5920, 9633, 9635, 9636, 9638, 9639, 9640, 9641, 9644, 9647, 9650, 9654,
  9657, 9660, 9661, 9663, 9665, 9685, 9686, 9691, 9694, 10196, 10281, 10295, 10298,
  10302, 10304, 10307, 10309, 10311, 10405, 10420, 11444, 11447, 11452, 11464, 11466,
  11484, 11489, 11492, 11658, 11702, 11703, 14012, 14079, 14081, 16131, 17458, 17823,
  18993, 18994, 20199, 20200, 20205, 21194, 21200, 21202, 21975, 22007, 22053, 22189,
  22728, 22730, 23507, 23508, 25694, 25702, 28567, 40529,
}
local imbuementSources = {}
for _, itemId in ipairs(imbuementSourceIds) do
  imbuementSources[itemId] = true
end

local function sendSupplyStashRequest(action, itemId, count, tier)
  local protocolGame = g_game.getProtocolGame()
  if not protocolGame then
    return
  end

  local msg = OutputMessage.create()
  msg:addU8(OPCODE_SUPPLY_STASH_REQUEST)
  msg:addU8(action)
  if action == ACTION_WITHDRAW then
    msg:addU16(itemId)
    msg:addU32(count)
    msg:addU8(tier or 0)
  end
  protocolGame:send(msg)
end

local function buildStashItem(row, details)
  local itemId = row.itemId
  local item = Item.create(itemId, row.amount)
  if row.tier and item.setTier then
    item:setTier(row.tier)
  end

  local marketData = item:getMarketData() or {}
  local npcSaleData = item:getNPCSaleData() or {}
  local itemDetails = details[itemId] or {}
  marketData.name = itemDetails.name or marketData.name or ("Item " .. itemId)
  marketData.category = itemDetails.category or marketData.category or 9
  marketData.categoryName = marketCategoryNames[marketData.category] or "Others"

  local defaultValue = tonumber(itemDetails.defaultValue) or 0
  local marketValue = tonumber(itemDetails.marketValue) or tonumber(item:getAverageMarketValue()) or 0
  if ItemsDatabase and ItemsDatabase.registerServerItemValue then
    ItemsDatabase.registerServerItemValue(itemId, math.max(defaultValue, marketValue))
  end

  return {
    itemId = itemId,
    itemCount = row.amount,
    tier = row.tier or 0,
    marketValue = marketValue,
    defaultValue = defaultValue,
    lowerName = marketData.name:lower(),
    lowerCategoryName = marketData.categoryName:lower(),
    totalMarketValue = marketValue * row.amount,
    totalDefaultValue = defaultValue * row.amount,
    marketData = marketData,
    npcSaleData = npcSaleData
  }
end

local function parseSupplyStash(protocolGame, msg)
  local rows = {}
  local count = msg:getU16()
  for i = 1, count do
    rows[#rows + 1] = {
      itemId = msg:getU16(),
      amount = msg:getU32(),
      tier = msg:getU8()
    }
  end

  local freeSlots = msg:getU16()
  local details = {}
  if msg:getUnreadSize() >= 4 and msg:peekU16() == SUPPLY_STASH_DETAILS_MARKER then
    msg:getU16()
    local detailCount = msg:getU16()
    for i = 1, detailCount do
      local itemId = msg:getU16()
      details[itemId] = {
        name = msg:getString(),
        category = msg:getU16(),
        stackable = msg:getU8() ~= 0,
        defaultValue = msg:getU32()
      }
    end
  end

  local items = {}
  for _, row in ipairs(rows) do
    items[#items + 1] = buildStashItem(row, details)
  end
  showStash(items, freeSlots)
  return true
end

local function registerSupplyStashProtocol()
  if supplyStashProtocolRegistered then
    return
  end
  ProtocolGame.unregisterOpcode(OPCODE_SUPPLY_STASH_SEND)
  ProtocolGame.registerOpcode(OPCODE_SUPPLY_STASH_SEND, parseSupplyStash)
  supplyStashProtocolRegistered = true
end

local function unregisterSupplyStashProtocol()
  if not supplyStashProtocolRegistered then
    return
  end
  ProtocolGame.unregisterOpcode(OPCODE_SUPPLY_STASH_SEND)
  supplyStashProtocolRegistered = false
end

local otherOptions = {
  { name = "Name (A-Z)", func = function(a, b) return a.lowerName < b.lowerName end},
  { name = "Name (Z-A)", func = function(a, b) return a.lowerName > b.lowerName end},
  { name = "Market Value (High to Low)", func = function(a, b) return a.marketValue > b.marketValue end},
  { name = "Market Value (Low to High)", func = function(a, b) return a.marketValue < b.marketValue end},
  { name = "Total Market Value (High t...", func = function(a, b) return a.totalMarketValue > b.totalMarketValue end},
  { name = "Total Market Value (Low t...", func = function(a, b) return a.totalMarketValue < b.totalMarketValue end},
  { name = "Sell To Value (High to Low)", func = function(a, b) return a.defaultValue > b.defaultValue end},
  { name = "Sell To Value (Low to High)", func = function(a, b) return a.defaultValue < b.defaultValue end},
  { name = "Total Sell To Value (High t...", func = function(a, b) return a.totalDefaultValue > b.totalDefaultValue end},
  { name = "Total Sell To Value (Low t...", func = function(a, b) return a.totalDefaultValue < b.totalDefaultValue end},
  { name = "Quantity (High to Low)", func = function(a, b) return a.itemCount > b.itemCount end},
  { name = "Quantity (Low to High)", func = function(a, b) return a.itemCount < b.itemCount end},
}

local function cancelStashRefresh()
  if refreshStashEvent then
    removeEvent(refreshStashEvent)
    refreshStashEvent = nil
  end
end

local function destroyCountWithdraw()
  if countWithdraw then
    countWithdraw:destroy()
    countWithdraw = nil
  end
end

local function destroyStowContainer()
  if stowContainer then
    stowContainer:destroy()
    stowContainer = nil
  end
end

local function closeStashDialogs()
  destroyCountWithdraw()
  destroyStowContainer()
end

function requestStashRefresh(searchText)
  if rebuildingOptions then
    return
  end

  cancelStashRefresh()
  refreshStashEvent = scheduleEvent(function()
    refreshStashEvent = nil
    if not gameStashWindown or not gameStashWindown:isVisible() then
      return
    end
    refreshStashItems(searchText or gameStashWindown.searchText:getText())
  end, 1)
end

function init()
	gameStashWindown = g_ui.displayUI('stash')
	gameStashWindown:hide()

	itemsPanel = gameStashWindown:recursiveGetChildById('itemsPanel')

	g_ui.importStyle('withdraw')
  g_ui.importStyle('stow-container')
  connect(LocalPlayer, {
    onPositionChange = onPlayerPositionChange
  })

  connect(g_game, {
    onParseSupplyStash = showStash,
    onGameStart = registerSupplyStashProtocol,
    onGameEnd = offline
  })

  g_game.stashWithdraw = function(itemId, tier, count)
    sendSupplyStashRequest(ACTION_WITHDRAW, itemId, count or 1, tier or 0)
  end
  g_game.stowItem = function()
    sendSupplyStashRequest(ACTION_STOW_ALL)
  end
  g_game.stowItemContainerStack = function()
    sendSupplyStashRequest(ACTION_STOW_ALL)
  end

  if g_game.isOnline() then
    registerSupplyStashProtocol()
  end
end

function terminate()
  cancelStashRefresh()
  closeStashDialogs()
	listItems = {}
  disconnect(LocalPlayer, {
    onPositionChange = onPlayerPositionChange
  })
  disconnect(g_game, {
    onParseSupplyStash = showStash,
    onGameStart = registerSupplyStashProtocol,
    onGameEnd = offline
  })
  unregisterSupplyStashProtocol()
  g_client.setInputLockWidget(nil)
  if gameStashWindown then
    gameStashWindown:destroy()
    gameStashWindown = nil
  end
  itemsPanel = nil
end

function offline()
  cancelStashRefresh()
  unregisterSupplyStashProtocol()
  closeStashDialogs()
  g_client.setInputLockWidget(nil)
  if gameStashWindown then
    gameStashWindown:hide()
  end
end

function showStash(items, maxSlots)
  local prevOpen = gameStashWindown:isVisible()
  if g_game.isOnline() then
    g_client.setInputLockWidget(gameStashWindown)
    gameStashWindown:show(true)
  end

  gameStashWindown:focus()
  sellerOption = gameStashWindown.sellerOptions
  stashOption = gameStashWindown.stashOptions
  otherOption = gameStashWindown.otherOptions

  cancelStashRefresh()
  destroyCountWithdraw()
  listItems = items

  local currentOption = stashOption:getCurrentOption() and stashOption:getCurrentOption().text or nil
  local currentSeller = sellerOption:getCurrentOption() and sellerOption:getCurrentOption().text or nil
  local currentOther = otherOption:getCurrentOption() and otherOption:getCurrentOption().text or nil

  rebuildingOptions = true
  stashOption:clearOptions()
  stashOption:addOption("Show All")

  local currentList = {}
  local categories = {}
  for _, data in ipairs(listItems) do
    if not categories[data.marketData.categoryName] then
      categories[data.marketData.categoryName] = true
      currentList[#currentList + 1] = data.marketData.categoryName
    end
  end

  table.insert(currentList, "Imbuement Items")
  table.sort(currentList, function(a, b) return a < b end)
  for _, v in ipairs(currentList) do
    stashOption:addOption("Show " .. v)
  end

  otherOption:clearOptions()
  for _, v in ipairs(otherOptions) do
    otherOption:addOption(v.name)
  end

  stashOption:setCurrentOption("Show All", true)
  sellerOption:setCurrentOption("No Trader Selected", true)

  if currentOption ~= nil then
    stashOption:setCurrentOption(currentOption, true)
  end

  if currentSeller ~= nil then
    sellerOption:setCurrentOption(currentSeller, true)
  end

  if currentOther ~= nil then
    otherOption:setCurrentOption(currentOther, true)
  end

  if not prevOpen then
    stashOption:setCurrentOption("Show All", true)
    sellerOption:setCurrentOption("No Trader Selected", true)
    gameStashWindown.searchText:clearText(true)
  end
  rebuildingOptions = false
  refreshStashItems(gameStashWindown.searchText:getText())
end

function hideStash()
  cancelStashRefresh()
  closeStashDialogs()
  if itemsPanel then
    local layout = itemsPanel:getLayout()
    layout:disableUpdates()
    itemsPanel:destroyChildren()
    layout:enableUpdates()
    layout:update()
  end
  g_client.setInputLockWidget(nil)
  if gameStashWindown and gameStashWindown:isVisible() then
    gameStashWindown:hide()
  end
  if m_interface and m_interface.getRootPanel then
    m_interface.getRootPanel():focus()
  end
end

function openQuick()
 	modules.game_stash.hideStash()
  modules.game_quickloot.showQuickLoot()
end

function stowAll()
  sendSupplyStashRequest(ACTION_STOW_ALL)
  -- Note: Reopen is now triggered automatically by parseSupplyStash
  -- when server sends the updated stash data after stow-all completes
end

function refreshStashItems(searchText)
  if not itemsPanel or not sellerOption or not stashOption or not otherOption then
    return true
  end

  local layout = itemsPanel:getLayout()
  layout:disableUpdates()
  itemsPanel:destroyChildren()

  local additionalSort = otherOptions[otherOption.currentIndex]
  if additionalSort then
    table.sort(listItems, additionalSort.func)
  end

  local selectedSeller = sellerOption:getCurrentOption()
  local selectedCategory = stashOption:getCurrentOption()
  local sellerText = selectedSeller and selectedSeller.text:lower() or ""
  local categoryText = selectedCategory and selectedCategory.text:lower() or ""

  for _, itemData in ipairs(listItems) do
    if searchText and #searchText > 0 and not matchText(searchText, itemData.marketData.name) then
      goto continue
    end

    if sellerOption.currentIndex ~= 1 then
      local foundSeller = false
      for _, v in ipairs(itemData.npcSaleData) do
        if v.name and string.find(sellerText, v.name:lower(), 1, true) then
          foundSeller = true
          break
        end
      end

      if not foundSeller then
        goto continue
      end
    end

    if stashOption.currentIndex ~= 1 then
      if categoryText == "show imbuement items" then
        if not imbuementSources[itemData.itemId] then
          goto continue
        end
      else
        if not string.find(categoryText, itemData.lowerCategoryName, 1, true) then
          goto continue
        end
      end
    end

    local stashItem = Item.create(itemData.itemId, itemData.itemCount)
    if not stashItem then
      goto continue
    end
    local tier = itemData.tier or 0
    if tier > 0 and stashItem.setTier then
      stashItem:setTier(tier)
    end

    local itemBox = g_ui.createWidget('StashItemBox', itemsPanel)
    itemBox.item = itemData

    local itemWidget = itemBox:getChildById('item')
    itemWidget:setItem(stashItem)
    if ItemsDatabase and ItemsDatabase.setRarityItem then
      ItemsDatabase.setRarityItem(itemWidget, stashItem)
    end
    if ItemsDatabase and ItemsDatabase.setTier then
      ItemsDatabase.setTier(itemWidget, stashItem)
    end
    itemWidget.stashTier = tier
    itemWidget:setTooltip(itemData.marketData.name)
    itemWidget:setActionId(itemData.itemCount)
    itemWidget.onMouseRelease = function(widget, mousePos, mouseButton)
      if mouseButton ~= MouseRightButton and (mouseButton ~= MouseLeftButton or not g_keyboard.isCtrlPressed()) then
        return false
      end

      local menu = g_ui.createWidget('PopupMenu')
      menu:setGameMenu(true)
      menu:addOption(tr('Retrieve'), function() withdrawItem(itemWidget) end)
      menu:addSeparator()
      menu:addOption(tr('Cyclopedia'), function() hideStash() modules.game_cyclopedia.CyclopediaItems.onRedirect(stashItem:getId()) end)
      if stashItem:isMarketable() and g_game.getLocalPlayer():isInMarket() then
        menu:addSeparator()
        menu:addOption(tr('Show in Market'), function()
          if stashItem:isMarketable() and g_game.getLocalPlayer():isInMarket() then
            hideStash()
            modules.game_tibia_market.onRedirect(stashItem) 
          end
        end)
      end
      menu:addSeparator()
      if not modules.game_quickloot.inWhiteList(stashItem:getId()) then
        menu:addOption(tr('Add to Loot List'), function() modules.game_quickloot.addToQuickLoot(stashItem:getId()) end)
      else
        menu:addOption(tr('Remove from Loot List'), function() modules.game_quickloot.removeItemInList(stashItem:getId()) end)
      end
      if not modules.game_npctrade.inWhiteList(stashItem:getId()) then
        menu:addOption(tr('Add to Quick Sell BlackList'), function() modules.game_npctrade.addToWhitelist(stashItem:getId()) end)
      else
        menu:addOption(tr('Remove from Quick Sell BlackList'), function() modules.game_npctrade.removeItemInList(stashItem:getId()) end)
      end
      menu:display(mousePos)
    end

    :: continue ::
  end

  layout:enableUpdates()
  layout:update()
end

function onPlayerPositionChange(creature, newPos, oldPos)
  if creature == g_game.getLocalPlayer() and
      ((gameStashWindown and gameStashWindown:isVisible()) or countWithdraw or stowContainer) then
    hideStash()
  end
end

function showStashWithdraw()
  destroyCountWithdraw()
  if gameStashWindown and g_game.isOnline() then
    gameStashWindown:show(true)
    gameStashWindown:focus()
    g_client.setInputLockWidget(gameStashWindown)
  end
end

function hideStashWithdraw()
  if gameStashWindown then
    gameStashWindown:hide()
  end
  g_client.setInputLockWidget(nil)
end

function retrieveItem(itemId, count, otherWindow, tier)
  sendSupplyStashRequest(ACTION_WITHDRAW, itemId, count, tier or 0)
  destroyCountWithdraw()

  if otherWindow then
    return
  end
  g_client.setInputLockWidget(nil)
  showStashWithdraw()
end

local function createCountWithdrawWindow(itemId, itemCount, tier, onConfirm, onCancel)
  destroyCountWithdraw()
  countWithdraw = g_ui.createWidget('CountWithdraw', rootWidget)
  local window = countWithdraw
  window.contentPanel.item:setItemId(itemId)
  countWithdraw.contentPanel.item:setItemCount(itemCount)
  if window.contentPanel.item.setTier then
    window.contentPanel.item:setTier(tier or 0)
  end
  g_client.setInputLockWidget(window)

  local scrollbar = window:recursiveGetChildById("countScrollBar")
  scrollbar:setMaximum(itemCount)
  scrollbar:setMinimum(1)
  scrollbar:setValue(itemCount)

  local spinbox = window:recursiveGetChildById('spinBox')
  spinbox:setMaximum(itemCount)
  spinbox:setMinimum(1)
  spinbox:setValue(itemCount)
  spinbox:hideButtons()
  spinbox:focus()
  spinbox.onValueChange = function(self, value)
    scrollbar:setValue(value)
  end

  g_keyboard.bindKeyPress("Left", function() scrollbar:setValue(math.max(scrollbar:getMinimum(), scrollbar:getValue() - 1)) end, window)
  g_keyboard.bindKeyPress("Shift+Left", function() scrollbar:setValue(math.max(scrollbar:getMinimum(), scrollbar:getValue() - 10)) end, window)
  g_keyboard.bindKeyPress("Ctrl+Left", function() scrollbar:setValue(math.max(scrollbar:getMinimum(), scrollbar:getValue() - 100)) end, window)
  g_keyboard.bindKeyPress("Right", function() scrollbar:setValue(math.min(scrollbar:getMaximum(), scrollbar:getValue() + 1)) end, window)
  g_keyboard.bindKeyPress("Shift+Right", function() scrollbar:setValue(math.min(scrollbar:getMaximum(), scrollbar:getValue() + 10)) end, window)
  g_keyboard.bindKeyPress("Ctrl+Right", function() scrollbar:setValue(math.min(scrollbar:getMaximum(), scrollbar:getValue() + 100)) end, window)

  scrollbar.onValueChange = function(self, value)
    if spinbox:getValue() ~= value then
      spinbox:setValue(value)
    end
    window.contentPanel.item:setItemCount(value)
  end

  scrollbar.onClick = function()
    local mousePos = g_window.getMousePosition()
    local sliderButton = scrollbar:getChildById('sliderButton')

    scrollbar:setSliderClick(sliderButton, sliderButton:getPosition())
    scrollbar:setSliderPos(sliderButton, sliderButton:getPosition(), {x = mousePos.x - sliderButton:getPosition().x, y = 0})
  end

  local confirm = function()
    local amount = scrollbar:getValue()
    destroyCountWithdraw()
    g_client.setInputLockWidget(nil)
    onConfirm(amount)
  end
  local cancel = function()
    destroyCountWithdraw()
    g_client.setInputLockWidget(nil)
    if onCancel then
      onCancel()
    end
  end

  window.onEnter = confirm
  window.onEscape = cancel
  window.contentPanel.onEnter = confirm
  window.contentPanel.onEscape = cancel
  window.contentPanel.buttonOk.onClick = confirm
  window.contentPanel.buttonCancel.onClick = cancel
end

function withdrawItem(widget)
  local itemId = widget:getItemId()
  local itemCount = widget:getActionId()
  local tier = widget.stashTier or 0
  if itemCount == 1 then
    retrieveItem(itemId, itemCount, nil, tier)
    return
  end

  hideStashWithdraw()
  createCountWithdrawWindow(itemId, itemCount, tier, function(amount)
    retrieveItem(itemId, amount, nil, tier)
  end, showStashWithdraw)
end

function stowContainerContent(item, toPos, moveItem)
  if stowContainer then
    return
  end

  stowContainer = g_ui.createWidget('StowContainer', rootWidget)
  stowContainer.contentPanel.buttonNo.onClick = function()
    destroyStowContainer()
  end

  stowContainer.contentPanel.buttonYes.onClick = function()
    if moveItem then
      g_game.move(item, toPos, 1)
    else
      g_game.stowItemContainerStack(SUPPLY_STASH_ACTION_STOW_CONTAINER, item:getPosition(), item:getId(), item:getStackPos())
    end

    destroyStowContainer()
  end
end

function withdrawItemID(itemID, itemCount)
  if itemCount == 1 then
    retrieveItem(itemID, itemCount, true)
    return
  end

  createCountWithdrawWindow(itemID, itemCount, 0, function(amount)
    retrieveItem(itemID, amount, true)
  end)
end
