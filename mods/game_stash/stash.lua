local listItems = {}
gameStashWindown = nil
itemsPanel = nil
countWithdraw = nil
stowContainer = nil

local sellerOption = nil
local stashOption = nil
local otherOption = nil

local supplyStashProtocolRegistered = false
local OPCODE_SUPPLY_STASH_REQUEST = 0x28
local OPCODE_SUPPLY_STASH_SEND = 0x29
local SUPPLY_STASH_DETAILS_MARKER = 0x5354
local ACTION_OPEN = 1
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

local imbuementSources = {
  5877, 5920, 9633, 9635, 9636, 9638, 9639, 9640, 9641, 9644, 9647, 9650, 9654,
  9657, 9660, 9661, 9663, 9665, 9685, 9686, 9691, 9694, 10196, 10281, 10295, 10298,
  10302, 10304, 10307, 10309, 10311, 10405, 10420, 11444, 11447, 11452, 11464, 11466,
  11484, 11489, 11492, 11658, 11702, 11703, 14012, 14079, 14081, 16131, 17458, 17823,
  18993, 18994, 20199, 20200, 20205, 21194, 21200, 21202, 21975, 22007, 22053, 22189,
  22728, 22730, 23507, 23508, 25694, 25702, 28567, 40529, 
}

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
  local itemDetails = details[itemId] or {}
  marketData.name = itemDetails.name or marketData.name or ("Item " .. itemId)
  marketData.category = itemDetails.category or marketData.category or 9
  marketData.categoryName = marketCategoryNames[marketData.category] or "Others"

  local defaultValue = tonumber(itemDetails.defaultValue) or 0
  local marketValue = tonumber(itemDetails.marketValue) or 0
  if ItemsDatabase and ItemsDatabase.registerServerItemValue then
    ItemsDatabase.registerServerItemValue(itemId, math.max(defaultValue, marketValue))
  end

  return {
    itemId = itemId,
    itemCount = row.amount,
    tier = row.tier or 0,
    marketValue = marketValue,
    defaultValue = defaultValue,
    marketData = marketData,
    npcSaleData = {}
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
  { name = "Name (A-Z)", func = function(a, b) return a.marketData.name:lower() < b.marketData.name:lower() end},
  { name = "Name (Z-A)", func = function(a, b) return a.marketData.name:lower() > b.marketData.name:lower() end},
  { name = "Market Value (High to Low)", func = function(a, b) return a.marketValue > b.marketValue end},
  { name = "Market Value (Low to High)", func = function(a, b) return a.marketValue < b.marketValue end},
  { name = "Total Market Value (High t...", func = function(a, b) return (a.marketValue * a.itemCount) > (b.marketValue * b.itemCount) end},
  { name = "Total Market Value (Low t...", func = function(a, b) return (a.marketValue * a.itemCount) < (b.marketValue * b.itemCount) end},
  { name = "Sell To Value (High to Low)", func = function(a, b) return a.defaultValue > b.defaultValue end},
  { name = "Sell To Value (Low to High)", func = function(a, b) return a.defaultValue < b.defaultValue end},
  { name = "Total Sell To Value (High t...", func = function(a, b) return (a.defaultValue * a.itemCount) > (b.defaultValue * b.itemCount) end},
  { name = "Total Sell To Value (Low t...", func = function(a, b) return (a.defaultValue * a.itemCount) < (b.defaultValue * b.itemCount) end},
  { name = "Quantity (High to Low)", func = function(a, b) return a.itemCount > b.itemCount end},
  { name = "Quantity (Low to High)", func = function(a, b) return a.itemCount < b.itemCount end},
}

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

function terminate( ... )
	listItems = {}
	gameStashWindown:destroy()
  disconnect(LocalPlayer, {
    onPositionChange = onPlayerPositionChange
  })
  disconnect(g_game, {
    onParseSupplyStash = showStash,
    onGameStart = registerSupplyStashProtocol,
    onGameEnd = offline
  })
  unregisterSupplyStashProtocol()

  if countWithdraw then
    countWithdraw:destroy()
    countWithdraw = nil
  end

  if stowContainer then
    stowContainer:destroy()
    stowContainer = nil
  end
end

function offline()
  unregisterSupplyStashProtocol()
  if countWithdraw then
    countWithdraw:destroy()
    countWithdraw = nil
  end
  if stowContainer then
    stowContainer:destroy()
    stowContainer = nil
  end
  gameStashWindown:hide()
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

	countWithdraw = nil
  listItems = items

  local currentOption = stashOption:getCurrentOption() and stashOption:getCurrentOption().text or nil
  local currentSeller = sellerOption:getCurrentOption() and sellerOption:getCurrentOption().text or nil
  local currentOhter = otherOption:getCurrentOption() and otherOption:getCurrentOption().text or nil

  stashOption:clearOptions()
  stashOption:addOption("Show All")

  local currentList = {}
  for key, data in pairs(listItems) do
    if not table.contains(currentList, data.marketData.categoryName) then
      table.insert(currentList, data.marketData.categoryName)
    end
  end

  table.insert(currentList, "Imbuement Items")
  table.sort(currentList, function(a, b) return a < b end)
  for _, v in pairs(currentList) do
    stashOption:addOption("Show " .. v)
  end

  otherOption:clearOptions()
  for _, v in pairs(otherOptions) do
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

  if currentOhter ~= nil then
    otherOption:setCurrentOption(currentOhter, true)
  end

  if not prevOpen then
    stashOption:setCurrentOption("Show All", true)
    sellerOption:setCurrentOption("No Trader Selected", true)
    gameStashWindown.searchText:clearText(true)
  end
	refreshStashItems(gameStashWindown.searchText:getText())
end

function hideStash()
  local layout = itemsPanel:getLayout()
  layout:disableUpdates()
  itemsPanel:destroyChildren()
  layout:enableUpdates()
  layout:update()
  if gameStashWindown:isVisible() then
    g_client.setInputLockWidget(nil)
    gameStashWindown:hide()
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
  if not itemsPanel then
    return true
  end

  local layout = itemsPanel:getLayout()
  layout:disableUpdates()
  itemsPanel:destroyChildren()

  local additionalSort = otherOptions[otherOption.currentIndex]
  if additionalSort then
    table.sort(listItems, additionalSort.func)
  end

  for key, itemData in pairs(listItems) do
    local stashItem = Item.create(itemData.itemId, itemData.itemCount)
    local tier = itemData.tier or 0
    if stashItem and tier > 0 and stashItem.setTier then
      stashItem:setTier(tier)
    end
    if searchText and #searchText > 0 and not matchText(searchText, itemData.marketData.name) then
      goto continue
    end

    if sellerOption.currentIndex ~= 1 then
      local foundSeller = false
      for _, v in pairs(itemData.npcSaleData) do
        if string.find(sellerOption:getCurrentOption().text:lower(), v.name:lower()) then
          foundSeller = true
          break
        end
      end

      if not foundSeller then
        goto continue
      end
    end

    if stashOption.currentIndex ~= 1 then
      if stashOption:getCurrentOption().text == "Show Imbuement Items" then
        if not table.contains(imbuementSources, itemData.itemId) then
          goto continue
        end
      else
        if not string.find(stashOption:getCurrentOption().text:lower(), itemData.marketData.categoryName:lower()) then
          goto continue
        end
      end
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
  if creature == g_game.getLocalPlayer() then
  	hideStash()
  end
end

function showStashWithdraw()
  if countWithdraw then
    countWithdraw:destroy()
  end
  countWithdraw = nil
  gameStashWindown:show(true)
  g_client.setInputLockWidget(gameStashWindown)
end

function hideStashWithdraw()
  gameStashWindown:hide()
  countWithdraw = nil
  g_client.setInputLockWidget(nil)
end

function retrieveItem(itemId, count, otherWindow, tier)
  sendSupplyStashRequest(ACTION_WITHDRAW, itemId, count, tier or 0)
  if countWithdraw then
    countWithdraw:destroy()
    countWithdraw = nil
  end

  if otherWindow then
    return
  end
  g_client.setInputLockWidget(nil)
  showStashWithdraw()
  g_client.setInputLockWidget(gameStashWindown)
end

function withdrawItem(widget)
  local itemCount = widget:getActionId()
  if itemCount == 1 then
    retrieveItem(widget:getItemId(), itemCount, nil, widget.stashTier)
    return
  end

  hideStashWithdraw()

  countWithdraw = g_ui.createWidget('CountWithdraw', rootWidget)
  countWithdraw.contentPanel.item:setItemId(widget:getItemId())
  countWithdraw.contentPanel.item:setItemCount(itemCount)
  if countWithdraw.contentPanel.item.setTier then
    countWithdraw.contentPanel.item:setTier(widget.stashTier or 0)
  end
  g_client.setInputLockWidget(countWithdraw)

  local scrollbar = countWithdraw:recursiveGetChildById("countScrollBar")
  scrollbar:setMaximum(itemCount)
  scrollbar:setMinimum(1)
  scrollbar:setValue(itemCount)

  local spinbox = countWithdraw:recursiveGetChildById('spinBox')
  spinbox:setMaximum(itemCount)
  spinbox:setMinimum(0)
  spinbox:setValue(0)
  spinbox:hideButtons()
  spinbox:focus()

  local spinBoxValueChange = function(self, value)
    scrollbar:setValue(value)
  end
  spinbox.onValueChange = spinBoxValueChange

  local check = function()
    if spinbox.firstEdit then
      spinbox:setValue(spinbox:getMaximum())
      spinbox.firstEdit = false
    end
  end

  g_keyboard.bindKeyPress("Left", function() scrollbar:setValue(math.max(scrollbar:getMinimum(), scrollbar:getValue() - 1)) end, countWithdraw)
  g_keyboard.bindKeyPress("Shift+Left", function() scrollbar:setValue(math.max(scrollbar:getMinimum(), scrollbar:getValue() - 10)) end, countWithdraw)
  g_keyboard.bindKeyPress("Ctrl+Left", function() scrollbar:setValue(math.max(scrollbar:getMinimum(), scrollbar:getValue() - 100)) end, countWithdraw)
  g_keyboard.bindKeyPress("Right", function() scrollbar:setValue(math.min(scrollbar:getMaximum(), scrollbar:getValue() + 1)) end, countWithdraw)
  g_keyboard.bindKeyPress("Shift+Right", function() scrollbar:setValue(math.min(scrollbar:getMaximum(), scrollbar:getValue() + 10)) end, countWithdraw)
  g_keyboard.bindKeyPress("Ctrl+Right", function() scrollbar:setValue(math.min(scrollbar:getMaximum(), scrollbar:getValue() + 100)) end, countWithdraw)

  scrollbar.onValueChange = function(self, value)
    countWithdraw.contentPanel.item:setItemCount(value)
  end

  scrollbar.onClick =
    function()
      local mousePos = g_window.getMousePosition()
      local sliderButton = scrollbar:getChildById('sliderButton')

      scrollbar:setSliderClick(sliderButton, sliderButton:getPosition())
      scrollbar:setSliderPos(sliderButton, sliderButton:getPosition(), {x = mousePos.x - sliderButton:getPosition().x, y = 0})
    end

  countWithdraw.onEnter = function() retrieveItem(widget:getItemId(), scrollbar:getValue(), nil, widget.stashTier) end
  countWithdraw.onEscape = function() showStashWithdraw() end
  countWithdraw.contentPanel.buttonOk.onClick =  function() gameStashWindown:show() retrieveItem(widget:getItemId(), scrollbar:getValue(), nil, widget.stashTier) end
  countWithdraw.contentPanel.buttonCancel.onClick = function() showStashWithdraw() end
end

function stowContainerContent(item, toPos, moveItem)
  if stowContainer then
    return
  end

  stowContainer = g_ui.createWidget('StowContainer', rootWidget)
  stowContainer.contentPanel.buttonNo.onClick = function()
    stowContainer:destroy()
    stowContainer = nil
  end

  stowContainer.contentPanel.buttonYes.onClick = function()
    if moveItem then
      g_game.move(item, toPos, 1)
    else
      g_game.stowItemContainerStack(SUPPLY_STASH_ACTION_STOW_CONTAINER, item:getPosition(), item:getId(), item:getStackPos())
    end

    stowContainer:destroy()
    stowContainer = nil
  end
end


function withdrawItemID(itemID, itemCount)
  if itemCount == 1 then
    retrieveItem(itemID, itemCount, true)
    return
  end

  countWithdraw = g_ui.createWidget('CountWithdraw', rootWidget)
  countWithdraw.contentPanel.item:setItemId(itemID)
  countWithdraw.contentPanel.item:setItemCount(itemCount)
  g_client.setInputLockWidget(countWithdraw)

  local scrollbar = countWithdraw:recursiveGetChildById("countScrollBar")
  scrollbar:setMaximum(itemCount)
  scrollbar:setMinimum(1)
  scrollbar:setValue(itemCount)

  local spinbox = countWithdraw:recursiveGetChildById('spinBox')
  spinbox:setMaximum(itemCount)
  spinbox:setMinimum(0)
  spinbox:setValue(0)
  spinbox:hideButtons()
  spinbox:focus()

  local spinBoxValueChange = function(self, value)
    scrollbar:setValue(value)
  end
  spinbox.onValueChange = spinBoxValueChange

  local check = function()
    if spinbox.firstEdit then
      spinbox:setValue(spinbox:getMaximum())
      spinbox.firstEdit = false
    end
  end

  g_keyboard.bindKeyPress("Left", function() scrollbar:setValue(math.max(scrollbar:getMinimum(), scrollbar:getValue() - 1)) end, countWithdraw)
  g_keyboard.bindKeyPress("Shift+Left", function() scrollbar:setValue(math.max(scrollbar:getMinimum(), scrollbar:getValue() - 10)) end, countWithdraw)
  g_keyboard.bindKeyPress("Ctrl+Left", function() scrollbar:setValue(math.max(scrollbar:getMinimum(), scrollbar:getValue() - 100)) end, countWithdraw)
  g_keyboard.bindKeyPress("Right", function() scrollbar:setValue(math.min(scrollbar:getMaximum(), scrollbar:getValue() + 1)) end, countWithdraw)
  g_keyboard.bindKeyPress("Shift+Right", function() scrollbar:setValue(math.min(scrollbar:getMaximum(), scrollbar:getValue() + 10)) end, countWithdraw)
  g_keyboard.bindKeyPress("Ctrl+Right", function() scrollbar:setValue(math.min(scrollbar:getMaximum(), scrollbar:getValue() + 100)) end, countWithdraw)
  g_keyboard.bindKeyPress("Enter", function() retrieveItem(itemID, scrollbar:getValue(), true) end, countWithdraw)

  scrollbar.onValueChange = function(self, value)
    countWithdraw.contentPanel.item:setItemCount(value)
  end

  scrollbar.onClick =
    function()
      local mousePos = g_window.getMousePosition()
      local sliderButton = scrollbar:getChildById('sliderButton')

      scrollbar:setSliderClick(sliderButton, sliderButton:getPosition())
      scrollbar:setSliderPos(sliderButton, sliderButton:getPosition(), {x = mousePos.x - sliderButton:getPosition().x, y = 0})
    end

  countWithdraw.contentPanel.onEnter = function() retrieveItem(itemID, scrollbar:getValue(), true) end
  countWithdraw.contentPanel.onEscape = function()  end
  countWithdraw.contentPanel.buttonOk.onClick =  function() retrieveItem(itemID, scrollbar:getValue(), true) end
  countWithdraw.contentPanel.buttonCancel.onClick = function()end
end
