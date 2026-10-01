BUY = 1
SELL = 2
CURRENCY = 'gold'
CURRENCYID = GOLD_COINS
CURRENCY_DECIMAL = false
WEIGHT_UNIT = 'oz'
LAST_INVENTORY = 10
SORT_BY = 'name'
MAX_TRADE_AMOUNT = 100

npcWindow = nil
itemsPanel = nil
radioTabs = nil
radioItems = nil
searchText = nil
setupPanel = nil
quantity = nil
quantityScroll = nil
amountText = nil
idLabel = nil
nameLabel = nil
priceLabel = nil
currencyMoneyLabel = nil
moneyLabel = nil
weightDesc = nil
weightLabel = nil
capacityDesc = nil
capacityLabel = nil
tradeButton = nil
itemButton = nil
headPanel = nil
currencyItem = nil
itemBorder = nil
currencyLabel = nil
buyTab = nil
sellTab = nil
initialized = false

showWeight = true
local buyWithBackpack = false
local ignoreCapacity = false
local ignoreEquipped = true
showAllItems = nil
sellAllButton = nil
sellAllWithDelayButton = nil
playerFreeCapacity = 0
playerMoney = 0
tradeItems = { [BUY] = {}, [SELL] = {} }
playerItems = {}
sellAllWhitelist = {}
selectedItem = nil

quickSellButton = nil

cancelNextRelease = nil
local npcWindowLayoutRefreshScheduled = false
local currentTradeType = BUY
local tradeSession = NpcTradeSession.new(scheduleEvent, removeEvent)
local quickSellWindow
local quickSellRadio
local blacklistWindow
local warningWindow

local function closeQuickSellWindows()
  if quickSellRadio then
    quickSellRadio:destroy()
  end
  for _, widget in pairs({ quickSellWindow, blacklistWindow, warningWindow }) do
    if widget and not widget:isDestroyed() then
      widget:destroy()
    end
  end
  if quickSellWindow or blacklistWindow or warningWindow then
    g_client.setInputLockWidget(nil)
  end
  quickSellWindow, blacklistWindow, warningWindow, quickSellRadio = nil, nil, nil, nil
end

function saveData()
  if not LoadedPlayer:isLoaded() then return end

  local file = "/characterdata/" .. LoadedPlayer:getId() .. "/sellAllWhitelist.json"
  local status, result = pcall(function() return json.encode(sellAllWhitelist, 2) end)
  if not status then
    return g_logger.error("Error while saving profile sellAllWhitelist. Data won't be saved. Details: " .. result)
  end

  if result:len() > 100 * 1024 * 1024 then
    return g_logger.error("Something went wrong, file is above 100MB, won't be saved")
  end
  g_resources.writeFileContents(file, result)
end

function loadData()
  sellAllWhitelist = {}
  if not LoadedPlayer:isLoaded() then return end

  local file = "/characterdata/" .. LoadedPlayer:getId() .. "/sellAllWhitelist.json"
  if g_resources.fileExists(file) then
    local status, result = pcall(function()
      return json.decode(g_resources.readFileContents(file))
    end)
    if not status then
      return g_logger.error(
      "Error while reading profiles file. To fix this problem you can delete storage.json. Details: " .. result)
    end
    if type(result) == 'table' then
      local seen = {}
      for _, id in pairs(result) do
        if type(id) == 'number' and id > 0 and id <= 65535 and id == math.floor(id) and not seen[id] then
          seen[id] = true
          table.insert(sellAllWhitelist, id)
        end
      end
    end
  else
    sellAllWhitelist = {}
  end
end

function removeItemInList(clientId)
  if type(clientId) ~= "number" then
    return
  end
  if not table.contains(sellAllWhitelist, clientId) then
    return
  end
  for k, v in pairs(sellAllWhitelist) do
    if v == clientId then
      table.remove(sellAllWhitelist, k)
      break
    end
  end
end

function inWhiteList(clientId)
  if not clientId then
    clientId = 0
  end
  if not sellAllWhitelist then
    return false
  end

  return table.contains(sellAllWhitelist, clientId)
end

function addToWhitelist(clientId)
  if type(clientId) ~= "number" then
    return
  end

  if table.contains(sellAllWhitelist, clientId) then
    return
  end

  table.insert(sellAllWhitelist, clientId)
end

function init()
  npcWindow = g_ui.loadUI('npctrade', m_interface.getContainerPanel())
  npcWindow:show()
  npcWindow:setVisible(false)

  npcWindow:setContentMinimumHeight(175)
  npcWindow:setContentHeight(175)
  npcWindow:setup()
  initNpcDialog()

  itemsPanel = npcWindow:recursiveGetChildById('contentsPanel')
  searchText = npcWindow:recursiveGetChildById('searchText')

  setupPanel = npcWindow:recursiveGetChildById('setupPanel')
  quantityScroll = setupPanel:getChildById('quantityScroll')
  amountText = setupPanel:getChildById('amountText')

  priceLabel = setupPanel:getChildById('price')
  currencyMoneyLabel = setupPanel:getChildById('currencyMoneyLabel')
  moneyLabel = setupPanel:getChildById('money')
  itemButton = setupPanel:getChildById('item')
  itemButton.onMouseRelease = itemPopup
  g_mouse.bindPress(itemButton, function()
    if tradeSession.open and g_keyboard.isShiftPressed() then
      g_game.inspectNpcTrade(itemButton:getItem())
    end
  end)
  tradeButton = npcWindow:recursiveGetChildById('tradeButton')
  headPanel = npcWindow:recursiveGetChildById('headPanel')
  currencyItem = headPanel:getChildById('currencyItem')
  itemBorder = headPanel:getChildById('itemBorder')
  currencyLabel = headPanel:getChildById('currencyLabel')

  buyTab = npcWindow:recursiveGetChildById('buyTab')
  sellTab = npcWindow:recursiveGetChildById('sellTab')

  quickSellButton = npcWindow:recursiveGetChildById('quickSellButton')

  radioTabs = UIRadioGroup.create()
  radioTabs:addWidget(buyTab)
  radioTabs:addWidget(sellTab)
  radioTabs:selectWidget(buyTab)
  radioTabs.onSelectionChange = onTradeTypeChange

  cancelNextRelease = false
  if g_game.isOnline() then
    playerFreeCapacity = g_game.getLocalPlayer():getFreeCapacity()
  end

  connect(g_game, {
    onGameStart = start,
    onGameEnd = onNpcDialogGameEnd,
    onOpenNpcTrade = onOpenNpcTrade,
    onCloseNpcTrade = onCloseNpcTrade,
    onPlayerGoods = onPlayerGoods
  })

  connect(LocalPlayer, {
    onPositionChange = onNpcDialogPositionChange,
    onFreeCapacityChange = onFreeCapacityChange,
    onInventoryChange = onInventoryChange
  })

  initialized = true
end

function terminate()
  hide()
  initialized = false
  disconnect(g_game, {
    onGameStart = start,
    onGameEnd = onNpcDialogGameEnd,
    onOpenNpcTrade = onOpenNpcTrade,
    onCloseNpcTrade = onCloseNpcTrade,
    onPlayerGoods = onPlayerGoods
  })

  disconnect(LocalPlayer, {
    onPositionChange = onNpcDialogPositionChange,
    onFreeCapacityChange = onFreeCapacityChange,
    onInventoryChange = onInventoryChange
  })

  terminateNpcDialog()
  if radioTabs then
    radioTabs:destroy()
    radioTabs = nil
  end
  if npcWindow and not npcWindow:isDestroyed() then
    npcWindow:destroy()
  end
  sellAllWhitelist = {}
end

local function refreshNpcWindowLayout()
  if not npcWindow or not npcWindow:getParent() then
    return
  end

  local parent = npcWindow:getParent()
  if parent:getClassName() == 'UIMiniWindowContainer' and parent.fitAll then
    parent:fitAll(npcWindow)
  end

  if itemsPanel then
    local layout = itemsPanel:getLayout()
    if layout then
      layout:update()
    end
  end
end

local function scheduleNpcWindowLayoutRefresh()
  if npcWindowLayoutRefreshScheduled then
    return
  end

  npcWindowLayoutRefreshScheduled = true
  tradeSession:schedule(refreshNpcWindowLayout)
  tradeSession:schedule(refreshNpcWindowLayout, 50)
  tradeSession:schedule(function()
    refreshNpcWindowLayout()
    npcWindowLayoutRefreshScheduled = false
  end, 150)
end

local function ensureNpcWindowExpanded()
  if not npcWindow then
    return
  end

  npcWindow.save = false
  if npcWindow.minimized and npcWindow.maximize then
    npcWindow:maximize()
  elseif npcWindow:getHeight() < npcWindow:getMinimumHeight() then
    npcWindow:setHeight(npcWindow:getMinimumHeight())
  end
end

function show()
  if g_game.isOnline() and tradeSession.open then
    if #tradeItems[BUY] > 0 then
      radioTabs:selectWidget(buyTab)
      quickSellButton:setEnabled(false)
    else
      radioTabs:selectWidget(sellTab)
      quickSellButton:setEnabled(true)
    end

    ensureNpcWindowExpanded()

    local addedToPanel = prepareNpcTradeForDialog()
    if not addedToPanel and m_interface.addToPanelsWithPriority then
      addedToPanel = m_interface.addToPanelsWithPriority(npcWindow, true)
    elseif not addedToPanel then
      addedToPanel = m_interface.addToPanels(npcWindow)
    end

    if not addedToPanel then
      return false
    end

    npcWindow:show()
    scheduleNpcWindowLayoutRefresh()
    syncNpcDialogTradePosition()
    scheduleNpcDialogTradePosition(50)

    if npcWindow and npcWindow:isVisible() and npcWindow:getParent() then
      local parent = npcWindow:getParent()
      parent:moveChildToIndex(npcWindow, #parent:getChildren())
      npcWindow.close = function() endNpcConversation() end
      npcWindow:focus()
      setupPanel:enable()
    end
  end
end

function start()
  resetNpcDialogSession()
  local benchmark = g_clock.millis()
  loadData()
  consoleln("Sell All Whitelist Loot loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function hide()
  local wasOpen = tradeSession.open or (npcWindow and npcWindow:isVisible())
  tradeSession:finish()
  npcWindowLayoutRefreshScheduled = false
  closeQuickSellWindows()
  if not npcWindow or not wasOpen then
    return
  end

  saveData()

  npcWindow:hide()

  toggleNPCFocus(false)
  if not focusNpcDialogInput() then
    modules.game_console.getConsole():focus()
  end

  local layout = itemsPanel:getLayout()
  layout:disableUpdates()

  clearSelectedItem()

  searchText:clearText()
  setupPanel:disable()
  itemsPanel:destroyChildren()

  if radioItems then
    radioItems:destroy()
    radioItems = nil
  end

  layout:enableUpdates()
  layout:update()
  tradeItems = { [BUY] = {}, [SELL] = {} }
  playerItems = {}
  playerMoney = 0
  onNpcTradeHidden()
end

function isTrading()
  return tradeSession.open
end

function onItemBoxChecked(widget)
  itemButton:setItemId(0)
  quantityScroll:setValue(0)
  if widget:isChecked() then
    local item = widget.item
    selectedItem = item
    refreshItem(item)
    tradeButton:setEnabled(quantityScroll:getMaximum() > 0)

    if getCurrentTradeType() == SELL then
      quantityScroll:setValue(quantityScroll:getMaximum())
      amountText:setText(quantityScroll:getMaximum())
    end
  end
end

function onQuantityValueChange(quantity)
  if selectedItem then
    priceLabel:setText(comma_value(formatCurrency(getItemPrice(selectedItem))))
    amountText:setText(quantity)
  end
end

function onTradeTypeChange(radioTabs, selected, deselected)
  currentTradeType = selected == buyTab and BUY or SELL
  tradeButton:setText(selected:getText())
  selected:setOn(true)
  if deselected then deselected:setOn(false) end

  if selected == buyTab then
    quickSellButton:setEnabled(false)
  else
    quickSellButton:setEnabled(true)
  end

  refreshTradeItems()
  refreshPlayerGoods()
end

function onTradeClick()
  if not tradeSession.open or not selectedItem or quantityScroll:getValue() < 1 then return end
  if tradeSession.sellQueue then
    tradeSession.sellQueue:cancel()
    tradeSession.sellQueue = nil
  end
  if getCurrentTradeType() == BUY then
    g_game.buyItem(selectedItem.ptr, quantityScroll:getValue(), ignoreCapacity, buyWithBackpack)
  else
    g_game.sellItem(selectedItem.ptr, quantityScroll:getValue(), ignoreEquipped)
  end
end

function onSearchTextChange()
  refreshPlayerGoods()
  clearSelectedItem()
end

function onExtraMenu()
  local mousePosition = g_window.getMousePosition()
  if cancelNextRelease then
    cancelNextRelease = false
    return false
  end

  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  menu:addCheckBoxOption(tr('Sort by name'), function()
    SORT_BY = 'name'; refreshPlayerGoods()
  end, "", SORT_BY == 'name')
  menu:addCheckBoxOption(tr('Sort by price'), function()
    SORT_BY = 'price'; refreshPlayerGoods()
  end, "", SORT_BY == 'price')
  menu:addCheckBoxOption(tr('Sort by weight'), function()
    SORT_BY = 'weight'; refreshPlayerGoods()
  end, "", SORT_BY == 'weight')
  menu:addSeparator()
  if getCurrentTradeType() == BUY then
    if CURRENCYID == GOLD_COINS then
      menu:addCheckBoxOption(tr('Buy in shopping bags'),
        function()
          buyWithBackpack = not buyWithBackpack; refreshPlayerGoods()
        end, "", buyWithBackpack)
    end
    menu:addCheckBoxOption(tr('Ignore capacity'), function()
      ignoreCapacity = not ignoreCapacity; refreshPlayerGoods()
    end, "", ignoreCapacity)
  else
    local equippedState = true
    if ignoreEquipped then
      equippedState = false
    end
    menu:addCheckBoxOption(tr('Sell equipped'),
      function()
        ignoreEquipped = not ignoreEquipped; refreshTradeItems(); refreshPlayerGoods()
      end, "", equippedState)
  end
  menu:addSeparator()
  menu:display(mousePosition)
  return true
end

function itemPopup(self, mousePosition, mouseButton)
  if cancelNextRelease then
    cancelNextRelease = false
    return false
  end

  local itemWidget = self:getChildById('item')
  if not itemWidget then
    itemWidget = self
  end

  if mouseButton == MouseRightButton then
    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)
    menu:addOption(tr('Look'), function() return g_game.inspectNpcTrade(itemWidget:getItem()) end)
    menu:addOption(tr('Inspect'), function() g_game.sendInspectionObject(3, itemWidget:getItem():getId(), 1) end)
    menu:addSeparator()
    menu:addCheckBoxOption(tr('Sort by name'), function()
      SORT_BY = 'name'; refreshPlayerGoods()
    end, "", SORT_BY == 'name')
    menu:addCheckBoxOption(tr('Sort by price'), function()
      SORT_BY = 'price'; refreshPlayerGoods()
    end, "", SORT_BY == 'price')
    menu:addCheckBoxOption(tr('Sort by weight'), function()
      SORT_BY = 'weight'; refreshPlayerGoods()
    end, "", SORT_BY == 'weight')
    menu:addSeparator()
    if getCurrentTradeType() == BUY then
      if CURRENCYID == GOLD_COINS then
        menu:addCheckBoxOption(tr('Buy in shopping bags'),
          function()
            buyWithBackpack = not buyWithBackpack; refreshPlayerGoods()
          end, "", buyWithBackpack)
      end
      menu:addCheckBoxOption(tr('Ignore capacity'),
        function()
          ignoreCapacity = not ignoreCapacity; refreshPlayerGoods()
        end, "", ignoreCapacity)
    else
      local equippedState = true
      if ignoreEquipped then
        equippedState = false
      end

      menu:addCheckBoxOption(tr('Sell equipped'),
        function()
          ignoreEquipped = not ignoreEquipped; refreshTradeItems(); refreshPlayerGoods()
        end, "", equippedState)
    end
    menu:addSeparator()
    menu:display(mousePosition)
    return true
  elseif ((g_mouse.isPressed(MouseLeftButton) and mouseButton == MouseRightButton)
        or (g_mouse.isPressed(MouseRightButton) and mouseButton == MouseLeftButton)) then
    cancelNextRelease = true
    g_game.inspectNpcTrade(itemWidget:getItem())
    return true
  end
  return false
end

function onBuyWithBackpackChange()
  if selectedItem then
    refreshItem(selectedItem)
  end
end

function onIgnoreCapacityChange()
  refreshPlayerGoods()
end

function onIgnoreEquippedChange()
  refreshPlayerGoods()
end

function onShowAllItemsChange()
  refreshPlayerGoods()
end

function setCurrency(currency, decimal)
  CURRENCY = currency
  CURRENCY_DECIMAL = decimal
end

function setShowWeight(state)
  showWeight = state
end

function clearSelectedItem()
  priceLabel:setText("0")
  quantityScroll:setMinimum(0)
  quantityScroll:setMaximum(0)
  quantityScroll:setValue(0)
  quantityScroll:setOn(true)
  amountText:setText('0')
  if selectedItem and radioItems then
    radioItems:selectWidget(nil)
  end
  selectedItem = nil
  tradeButton:disable()
end

function getCurrentTradeType()
  return currentTradeType
end

function getItemPrice(item, single)
  local amount = 1
  local single = single or false
  if not single then
    amount = quantityScroll:getValue()
  end
  if getCurrentTradeType() == BUY then
    if buyWithBackpack then
      if item.ptr:isStackable() then
        return item.price * amount + 20
      else
        return item.price * amount + math.ceil(amount / 20) * 20
      end
    end
  end
  return item.price * amount
end

function getSellQuantity(item, excludeEquipped)
  if not item or not playerItems[item:getId()] then return 0 end
  if excludeEquipped == nil then excludeEquipped = ignoreEquipped end
  local removeAmount = 0
  if excludeEquipped then
    local localPlayer = g_game.getLocalPlayer()
    if not localPlayer then return 0 end
    for i = 1, LAST_INVENTORY do
      local inventoryItem = localPlayer:getInventoryItem(i)
      if inventoryItem and inventoryItem:getId() == item:getId() and
          (not item:isFluidContainer() or inventoryItem:getCountOrSubType() == item:getCountOrSubType()) then
        removeAmount = removeAmount + (inventoryItem:isStackable() and inventoryItem:getCount() or 1)
      end
    end
  end
  return math.max(0, playerItems[item:getId()] - removeAmount)
end

function canTradeItem(item)
  if getCurrentTradeType() == BUY then
    return (ignoreCapacity or (not ignoreCapacity and playerFreeCapacity >= item.weight)) and
    getPlayerMoney() >= getItemPrice(item, true)
  else
    return getSellQuantity(item.ptr) > 0
  end
end

function refreshItem(item)
  priceLabel:setText(formatCurrency(getItemPrice(item)))
  itemButton:setItem(item.ptr)
  if ItemsDatabase and ItemsDatabase.setRarityItem then
    ItemsDatabase.setRarityItem(itemButton, item.ptr)
  end
  if ItemsDatabase and ItemsDatabase.setTier then
    ItemsDatabase.setTier(itemButton, item.ptr)
  end
  local finalCount
  if getCurrentTradeType() == BUY then
    local capacityMaxCount = item.weight > 0 and math.floor(playerFreeCapacity / item.weight) or MAX_TRADE_AMOUNT
    if ignoreCapacity then
      capacityMaxCount = uint32Max
    end
    local priceMaxCount = math.floor(getPlayerMoney() / getItemPrice(item, true))
    finalCount = math.max(0, math.min(getMaxAmount(item), math.min(priceMaxCount, capacityMaxCount)))
  else
    finalCount = math.max(0, math.min(getMaxAmount(), getSellQuantity(item.ptr)))
  end
  quantityScroll:setMinimum(0)
  quantityScroll:setMaximum(finalCount)
  quantityScroll:setMinimum(finalCount > 0 and 1 or 0)
  tradeButton:setEnabled(finalCount > 0)

  local text = tonumber(amountText:getText())
  if not text then
    amountText:setText(quantityScroll:getMinimum())
  elseif text < quantityScroll:getMinimum() then
    amountText:setText(quantityScroll:getMinimum())
  elseif text > quantityScroll:getMaximum() then
    amountText:setText(quantityScroll:getMaximum())
  end

  setupPanel:enable()
end

function refreshTradeItems()
  if not g_game.isOnline() or not tradeSession.open then
    return
  end

  local layout = itemsPanel:getLayout()
  layout:disableUpdates()

  clearSelectedItem()

  searchText:clearText()
  itemsPanel:destroyChildren()

  if radioItems then
    radioItems:destroy()
  end
  radioItems = UIRadioGroup.create()

  local currentTradeItems = tradeItems[getCurrentTradeType()]
  for key, item in ipairs(currentTradeItems) do
    local itemBox = g_ui.createWidget('NPCItemBox', itemsPanel)
    itemBox:setId("itemBox_" .. item.name)
    itemBox.item = item
  
    local price = formatCurrency(item.price)
    local informationText = 'Price ' .. price
  
    if showWeight and item.weight > 0 then
      local weight = string.format('%.2f', item.weight) .. ' ' .. WEIGHT_UNIT
      informationText = informationText .. ', ' .. weight
    end

    local description = string.format('%s\n%s', short_text(item.name, 15), short_text(informationText, 16))
    itemBox.nameLabel:setText(description, true)

    local itemWidget = itemBox:getChildById('item')
    itemWidget:setItem(item.ptr)
    if ItemsDatabase and ItemsDatabase.setRarityItem then
      ItemsDatabase.setRarityItem(itemWidget, item.ptr)
    end
    if ItemsDatabase and ItemsDatabase.setTier then
      ItemsDatabase.setTier(itemWidget, item.ptr)
    end
    itemBox.onMouseRelease = itemPopup

    if (string.len(item.name) > 15) or (string.len(informationText) > 16) then
      itemBox:setTooltip(string.format('%s\n%s', item.name, informationText))
    end

    if not canTradeItem(item) then
      itemBox.nameLabel:setColor('#707070')
    end

    radioItems:addWidget(itemBox)
  end

  layout:enableUpdates()
  layout:update()

  if npcWindow and npcWindow:isVisible() then
    scheduleNpcWindowLayoutRefresh()
  end
end

function refreshPlayerGoods()
  if not initialized or not tradeSession.open then return end

  moneyLabel:setText(comma_value(formatCurrency(getPlayerMoney())))

  local currentTradeType = getCurrentTradeType()
  local searchFilter = searchText:getText():lower()
  local foundSelectedItem = false

  local itemWidgets = {}
  local items = itemsPanel:getChildCount()
  for i = 1, items do
    local itemWidget = itemsPanel:getChildByIndex(i)
    table.insert(itemWidgets, itemWidget)
  end

  local function sortByName(a, b)
    return a.item.name:lower() < b.item.name:lower()
  end

  local function sortByPrice(a, b)
    return a.item.price < b.item.price
  end

  local function sortByWeight(a, b)
    return a.item.weight < b.item.weight
  end

  if SORT_BY == "name" then
    table.sort(itemWidgets, sortByName)
  elseif SORT_BY == "price" then
    table.sort(itemWidgets, sortByPrice)
  elseif SORT_BY == "weight" then
    table.sort(itemWidgets, sortByWeight)
  end

  for index, itemWidget in ipairs(itemWidgets) do
    itemsPanel:moveChildToIndex(itemWidget, index)
  end

  for _, itemWidget in ipairs(itemWidgets) do
    local item = itemWidget.item

    local canTrade = canTradeItem(item)
    itemWidget:setOn(canTrade)
    itemWidget.nameLabel:setEnabled(canTrade)
    local searchFilterEscaped = string.searchEscape(searchFilter)
    local searchCondition = (searchFilterEscaped == '') or
    (searchFilterEscaped ~= '' and string.find(item.name:lower(), searchFilterEscaped) ~= nil)
    local showAllItemsCondition = (currentTradeType == BUY) or (currentTradeType == SELL and canTrade)
    itemWidget:setVisible(searchCondition and showAllItemsCondition)

    if selectedItem == item and itemWidget:isEnabled() and itemWidget:isVisible() then
      foundSelectedItem = true
    end
  end

  if not foundSelectedItem then
    clearSelectedItem()
  end

  if selectedItem then
    refreshItem(selectedItem)
  end

  if npcWindow and npcWindow:isVisible() then
    scheduleNpcWindowLayoutRefresh()
  end
end

function onOpenNpcTrade(items)
  hide()
  tradeSession:begin()
  playerFreeCapacity = g_game.getLocalPlayer():getFreeCapacity()
  -- The current 0x7A packet carries no custom-currency metadata. Do not
  -- pretend that optional Lua arguments are supplied by the native parser.
  local currencyId = GOLD_COINS
  local currencyName = ''
  CURRENCYID = currencyId
  currencyItem:setItemId(currencyId)
  currencyItem:setVisible(true)
  itemBorder:setVisible(true)
  currencyItem:setItemCount(100)
  currencyItem:setShowCount(false)
  currencyMoneyLabel:setText('Gold:')

  if currencyId ~= GOLD_COINS and currencyName == '' then
    currencyName = getItemServerName(currencyId)
    buyWithBackpack = false
    currencyMoneyLabel:setText('Stock:')
  elseif currencyName ~= '' then
    currencyItem:setVisible(false)
    itemBorder:setVisible(false)
    currencyMoneyLabel:setText('Stock:')
  end

  local currencyName = currencyName ~= '' and currencyName or 'Gold Coin'
  currencyLabel:setText(short_text(currencyName, 11))
  currencyLabel:removeTooltip()
  if #currencyName > 11 then
    currencyLabel:setTooltip(currencyName)
  end

  tradeItems[BUY] = {}
  tradeItems[SELL] = {}
  for _, item in pairs(items) do
    if item[4] > 0 then
      local newItem = {}
      newItem.ptr = item[1]
      newItem.name = item[2]
      newItem.weight = item[3] / 100
      newItem.price = item[4]
      table.insert(tradeItems[BUY], newItem)
    end

    if item[5] > 0 then
      local newItem = {}
      newItem.ptr = item[1]
      newItem.name = item[2]
      newItem.weight = item[3] / 100
      newItem.price = item[5]
      table.insert(tradeItems[SELL], newItem)
    end
  end

  tradeSession:schedule(show) -- player goods has not been parsed yet
  tradeSession:schedule(refreshTradeItems, 50)
  tradeSession:schedule(refreshPlayerGoods, 50)
end

-- Public/bot API: close only the shop. The window X explicitly ends the
-- conversation instead, so scripts that say "bye" afterward remain valid.
function closeNpcTrade()
  if not tradeSession.open then return end
  g_game.doThing(false)
  g_game.closeNpcTrade()
  g_game.doThing(true)
  hide()
end

function onCloseNpcTrade()
  hide()
end

function onPlayerGoods(money, items)
  if not tradeSession.open then return end
  playerMoney = tonumber(money) or 0
  playerItems = {}
  for _, item in pairs(items or {}) do
    local id = item[1]:getId()
    local amount = item[2]
    if not playerItems[id] then
      playerItems[id] = amount
    else
      playerItems[id] = playerItems[id] + amount
    end
  end

  refreshPlayerGoods()
  if tradeSession.sellQueue then tradeSession.sellQueue:onGoods() end
end

function onFreeCapacityChange(localPlayer, freeCapacity, oldFreeCapacity)
  playerFreeCapacity = freeCapacity

  if npcWindow:isVisible() then
    refreshPlayerGoods()
  end
end

function onInventoryChange(inventory, item, oldItem)
  refreshPlayerGoods()
end

function getTradeItemData(id, type)
  if table.empty(tradeItems[type]) then
    return false
  end

  if type then
    for key, item in pairs(tradeItems[type]) do
      if item.ptr and item.ptr:getId() == id then
        return item
      end
    end
  else
    for _, items in pairs(tradeItems) do
      for key, item in pairs(items) do
        if item.ptr and item.ptr:getId() == id then
          return item
        end
      end
    end
  end
  return false
end

function checkSellAllTooltip()
  sellAllButton:setEnabled(true)
  sellAllButton:removeTooltip()
  sellAllWithDelayButton:setEnabled(true)
  sellAllWithDelayButton:removeTooltip()

  local total = 0
  local info = ''
  local first = true

  for key, amount in pairs(playerItems) do
    local data = getTradeItemData(key, SELL)
    if data then
      amount = getSellQuantity(data.ptr)
      if amount > 0 then
        if data and amount > 0 then
          info = info .. (not first and "\n" or "") ..
              amount .. " " ..
              data.name .. " (" ..
              data.price * amount .. " gold)"

          total = total + (data.price * amount)
          if first then first = false end
        end
      end
    end
  end
  if info ~= '' then
    info = info .. "\nTotal: " .. total .. " gold"
    sellAllButton:setTooltip(info)
    sellAllWithDelayButton:setTooltip(info)
  else
    sellAllButton:setEnabled(false)
    sellAllWithDelayButton:setEnabled(false)
  end
end

function formatCurrency(amount)
  if CURRENCY_DECIMAL then
    return string.format("%.02f", amount / 100.0)
  else
    return amount
  end
end

function getMaxAmount(item)
  return MAX_TRADE_AMOUNT
end

local function startSellQueue(entries, notify)
  if not tradeSession.open or not g_game.isOnline() then return false end
  if tradeSession.sellQueue then tradeSession.sellQueue:cancel() end
  tradeSession.sellQueue = nil
  local generation = tradeSession.generation
  local excludeEquipped = ignoreEquipped
  local saleEntries, seen, subtypes = {}, {}, {}
  for _, entry in ipairs(tradeItems[SELL]) do
    local id = entry.ptr:getId()
    local subtype = entry.ptr:isStackable() and 0 or entry.ptr:getCountOrSubType()
    if subtypes[id] and subtypes[id] ~= subtype then
      subtypes[id] = false -- 0x7B cannot disambiguate two variants of one ID
    elseif subtypes[id] == nil then
      subtypes[id] = subtype
    end
  end
  for _, entry in ipairs(entries) do
    local id = entry.ptr:getId()
    local subtype = entry.ptr:isStackable() and 0 or entry.ptr:getCountOrSubType()
    local key = id .. ':' .. subtype
    if subtypes[id] == false then
      displayInfoBox(tr('Quick Sell'), tr('This shop has multiple subtypes of the same item. Sell those items individually.'))
      return false
    end
    if not seen[key] and getSellQuantity(entry.ptr, excludeEquipped) > 0 then
      seen[key] = true
      table.insert(saleEntries, { ptr = entry.ptr, price = entry.price, key = key })
    end
  end
  table.sort(saleEntries, function(a, b) return a.key < b.key end)
  local queue
  queue = NpcSellQueue.new({
    isValid = function() return tradeSession.open and tradeSession.generation == generation and g_game.isOnline() end,
    quantity = function(entry) return getSellQuantity(entry.ptr, excludeEquipped) end,
    capped = function(entry) return playerItems[entry.ptr:getId()] == 255 end,
    money = getPlayerMoney,
    sell = function(entry, amount) g_game.sellItem(entry.ptr, amount, excludeEquipped) end,
    schedule = function(callback, delay) return tradeSession:schedule(callback, delay) end,
    cancel = removeEvent,
    onFinish = function(sold, proceeds)
      if tradeSession.sellQueue == queue then tradeSession.sellQueue = nil end
      if notify and sold > 0 then
        displayInfoBox(tr('Quick Sell'), tr('The server confirmed %d items sold for %d gold.', sold, proceeds))
      end
    end,
    onError = function(message)
      if tradeSession.sellQueue == queue then tradeSession.sellQueue = nil end
      displayInfoBox(tr('Quick Sell'), tr(message))
    end
  })
  tradeSession.sellQueue = queue
  queue:start(saleEntries)
  return true
end

function sellAll(delayed, exceptions)
  -- Keep the bot API, but both modes now wait for real server updates.
  if type(delayed) == 'table' then exceptions = delayed end
  local excluded = {}
  for _, id in pairs(exceptions or {}) do excluded[id] = true end
  local entries = {}
  for _, entry in ipairs(tradeItems[SELL]) do
    if not excluded[entry.ptr:getId()] then table.insert(entries, entry) end
  end
  return startSellQueue(entries, false)
end

function getPlayerMoney()
  return playerMoney or 0
end

function onAmountEdit(self)
  local text = tonumber(self:getText())
  if not text then
    return
  end

  local minValue = quantityScroll:getMinimum()
  local maxValue = quantityScroll:getMaximum()
  if minValue > text then
    self:setText(minValue, false)
    text = minValue
  elseif maxValue < text then
    self:setText(maxValue, false)
    text = maxValue
  end

  quantityScroll:setValue(text)
  onQuantityValueChange(tonumber(text))
end

function clearSearch()
  searchText:setText('')
  clearSelectedItem()
end

function onTypeFieldsHover(widget, hovered)
  if not npcWindow then
    return true
  end

  if not hovered and npcWindow:getBorderTopWidth() > 0 then
    return
  end

  m_interface.toggleFocus(hovered, "npctrade")
end

function toggleNPCFocus(visible)
  m_interface.toggleFocus(visible, "npctrade")
  if visible then
    npcWindow:setBorderWidth(2)
    npcWindow:setBorderColor('white')
  else
    npcWindow:setBorderWidth(0)
    m_interface.toggleInternalFocus()
  end
end

function checkItemToSell(self)
  local parent = self:getParent()
  local checkBox = parent:recursiveGetChildById('sellCheckbox')
  local gray = parent:recursiveGetChildById('gray')
  if checkBox:isChecked() then
    self:setBackgroundColor("#404040")
    checkBox:setChecked(false)
    gray:setVisible(true)
  else
    self:setBackgroundColor("#585858")
    checkBox:setChecked(true)
    gray:setVisible(false)
  end
end

function SellItemList(items, window)
  if not tradeSession.open or not g_game.isOnline() or not window or window:isDestroyed() or
      window.tradeGeneration ~= tradeSession.generation then
    return
  end
  local entries = {}
  for _, widget in ipairs(items) do
    if widget.sellCheckbox:isChecked() and not inWhiteList(widget.item.ptr:getId()) then
      table.insert(entries, widget.item)
    end
  end
  closeQuickSellWindows()
  startSellQueue(entries, true)
end

local function updateBlacklist(window)
  if not window then
    return
  end

  local list = window:recursiveGetChildById('itemsList')
  if not list then
    return
  end

  list:destroyChildren()

  local count = 0
  for i, itemId in pairs(sellAllWhitelist) do
    count = count + 1
    local widget = g_ui.createWidget('QuickSellItemBox', list)
    local color = (count % 2) == 0 and '#414141' or '#484848'
    widget:setId(itemId)
    widget.itemName:setText(getItemServerName(itemId))
    widget.itemId:setItemId(itemId)
    if ItemsDatabase and ItemsDatabase.setRarityItem then
      ItemsDatabase.setRarityItem(widget.itemId, itemId)
    end
    widget:setBackgroundColor(color)
    widget:getChildById('buttonItemClear').onClick = function()
      removeItemInList(itemId)
      updateBlacklist(window)
    end
  end
end

function openBlacklist()
  if not tradeSession.open then return end
  closeQuickSellWindows()
  blacklistWindow = g_ui.loadUI('styles/blacklist', g_ui.getRootWidget())
  if not blacklistWindow then
    onTradeAllClick()
    return
  end

  blacklistWindow:show()
  blacklistWindow:raise()
  blacklistWindow:focus()

  g_client.setInputLockWidget(blacklistWindow)

  updateBlacklist(blacklistWindow)

  local generation = tradeSession.generation
  local close = function()
    if generation ~= tradeSession.generation then return end
    closeQuickSellWindows()
    if tradeSession.open then onTradeAllClick() end
  end

  blacklistWindow.contentPanel.closeButton.onClick = close
end

function onTradeAllClick()
  if not tradeSession.open or getCurrentTradeType() == BUY then
    return
  end

  closeQuickSellWindows()
  local window = g_ui.loadUI('styles/quicksell', g_ui.getRootWidget())
  if not window then
    return true
  end
  quickSellWindow = window
  window.tradeGeneration = tradeSession.generation
  local generation = tradeSession.generation
  local radio = UIRadioGroup.create()
  quickSellRadio = radio

  window:setText("Quick Sell")
  window:show(true)
  window:raise()
  window:focus()

  local saleValue = 0
  local currentTradeItems = tradeItems[getCurrentTradeType()]
  for key, item in pairs(currentTradeItems) do
    if getCurrentTradeType() == SELL and not canTradeItem(item) then
      goto continue
    elseif inWhiteList(item.ptr:getId()) then
      goto continue
    end

    local itemSquare = g_ui.createWidget('ItemQuickSell', window.contentPanel.itemsList)

    itemSquare:setId("itemSquare_" .. item.name)
    itemSquare.item = item
    itemSquare.nameLabel:setText(getSellQuantity(item.ptr) .. "x " .. item.name, true)
    itemSquare.priceLabel:setText(item.price, true)

    itemSquare.sellCheckbox.onCheckChange = function(self)
      local price = item.price * getSellQuantity(item.ptr)
      saleValue = saleValue + (self:isChecked() and price or -price)
      window.contentPanel.total:setText("Total: " .. formatMoney(saleValue, ",") .. " gps")
    end

    itemSquare.itemButton:setBackgroundColor("#585858")
    itemSquare.sellCheckbox:setChecked(true)

    local itemWidget = itemSquare:getChildById('item')
    itemWidget:setItem(item.ptr)
    if ItemsDatabase and ItemsDatabase.setRarityItem then
      ItemsDatabase.setRarityItem(itemWidget, item.ptr)
    end

    radio:addWidget(itemSquare)
    ::continue::
  end

  local items = window.contentPanel.itemsList:getChildren()
  table.sort(items, function(a, b)
    local priceA = tonumber(a.priceLabel:getText())
    local priceB = tonumber(b.priceLabel:getText())
    return priceA > priceB
  end)
  for i, widget in ipairs(items) do
    window.contentPanel.itemsList:moveChildToIndex(widget, i)
  end

  g_client.setInputLockWidget(window)

  local close = function()
    if generation ~= tradeSession.generation then return end
    closeQuickSellWindows()
  end

  local sell = function()
    if not tradeSession.open or generation ~= tradeSession.generation or window:isDestroyed() then return end
    local selectedItems = {}
    local notWorthItems = {}
    local items = window.contentPanel.itemsList:getChildren()
    for i, widget in ipairs(items) do
      if widget.sellCheckbox:isChecked() then
        table.insert(selectedItems, widget.item)
        if tonumber(widget.priceLabel:getText()) < widget.item.ptr:getAverageMarketValue() then
          table.insert(notWorthItems, widget.item)
        end
      end
    end

    if #selectedItems <= 0 then
      return
    end

    if #notWorthItems > 0 then
      local message = ""
      for i, item in ipairs(notWorthItems) do
        message = message .. string.format("  - %s\n", item.name)
      end
      local yesCallback = function()
        if generation ~= tradeSession.generation then return end
        SellItemList(items, window)
      end
      local noCallback = function()
        if generation ~= tradeSession.generation then return end
        if window then
          window:show()
          g_client.setInputLockWidget(window)
        else
          g_client.setInputLockWidget(nil)
        end
        if warningWindow then
          warningWindow:destroy()
          warningWindow = nil
        end
      end
      window:hide()
      warningWindow = g_ui.createWidget('WarningQuickWindow', g_ui.getRootWidget())
      warningWindow.itemTextWarning:setText(message)
      warningWindow.itemTextWarning:setEditable(false)
      warningWindow.itemTextWarning:setCursorVisible(false)
      warningWindow:getChildById('okButton').onClick = yesCallback
      warningWindow:getChildById('cancelButton').onClick = noCallback
      warningWindow:show()
      warningWindow:focus()
      g_client.setInputLockWidget(warningWindow)
    else
      SellItemList(items, window)
    end
  end

  window.contentPanel.blackListButton.onClick = function()
    close(); openBlacklist()
  end
  window.contentPanel.cancelButton.onClick = close
  window.onEscape = close
  window.contentPanel.okButton.onClick = sell
  window.onEnter = sell
end
