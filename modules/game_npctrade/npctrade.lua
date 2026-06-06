BUY = 1
SELL = 2
CURRENCY = 'gold'
CURRENCYID = GOLD_COINS
CURRENCY_DECIMAL = false
WEIGHT_UNIT = 'oz'
LAST_INVENTORY = 10
SORT_BY = 'name'

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
tradeItems = {}
playerItems = {}
selectedItem = nil

quickSellButton = nil

cancelNextRelease = nil

local function normalizeCurrencyId(currencyId)
  return tonumber(currencyId) or GOLD_COINS
end

local function normalizeCurrencyName(currencyName)
  if type(currencyName) == 'string' then
    return currencyName
  end
  return ''
end

local function safeResourceValue(player, resource)
  if not player or not resource or not player.getResourceValue then
    return 0
  end
  return tonumber(player:getResourceValue(resource)) or 0
end

local function makeTradeItem(ptr, name, weight, price)
  return {
    ptr = ptr,
    name = name or '',
    weight = (tonumber(weight) or 0) / 100,
    price = tonumber(price) or 0
  }
end

local function splitNpcTradeItems(items)
  local buyItems = {}
  local sellItems = {}

  if type(items) ~= 'table' then
    return buyItems, sellItems
  end

  for _, item in ipairs(items) do
    if type(item) == 'table' then
      local buyPrice = tonumber(item[4]) or 0
      local sellPrice = tonumber(item[5]) or 0

      if buyPrice > 0 then
        table.insert(buyItems, makeTradeItem(item[1], item[2], item[3], buyPrice))
      end

      if sellPrice > 0 then
        table.insert(sellItems, makeTradeItem(item[1], item[2], item[3], sellPrice))
      end
    end
  end

  return buyItems, sellItems
end

local function normalizeNpcTradeArgs(buyItems, sellItems, currencyId, currencyName)
  if type(sellItems) ~= 'table' then
    local parsedCurrencyId = sellItems
    local parsedCurrencyName = currencyId

    buyItems, sellItems = splitNpcTradeItems(buyItems)
    currencyId = parsedCurrencyId
    currencyName = parsedCurrencyName
  end

  return buyItems or {}, sellItems or {}, normalizeCurrencyId(currencyId), normalizeCurrencyName(currencyName)
end

local function panelHasSpace(panel, widget)
  if not panel or not widget then
    return false
  end

  local childsSize = 0
  for _, child in pairs(panel:getChildren()) do
    if child:isVisible() and widget:getId() ~= child:getId() then
      childsSize = childsSize + child:getHeight()
    end
  end

  local emptySize = panel:getHeight() - childsSize
  return emptySize >= widget:getHeight() or emptySize >= widget:getMinimumHeight()
end

local function addNpcTradeToPanel()
  local panels = {}

  if m_interface.getRightPanel then
    table.insert(panels, m_interface.getRightPanel())
  end
  if m_interface.getLeftPanel then
    local leftPanel = m_interface.getLeftPanel()
    if leftPanel and leftPanel ~= panels[1] then
      table.insert(panels, leftPanel)
    end
  end

  for _, panel in ipairs(panels) do
    if panelHasSpace(panel, npcWindow) then
      return m_interface.addToPanels(npcWindow)
    end
  end

  return false
end

local function showNpcTradeAsWindow()
  local root = g_ui.getRootWidget()
  if not root or not npcWindow then
    return false
  end

  npcWindow:setParent(root)
  npcWindow:breakAnchors()
  npcWindow:show()
  npcWindow.onClose = nil

  local x = math.max(0, math.floor((root:getWidth() - npcWindow:getWidth()) / 2))
  local y = math.max(0, math.floor((root:getHeight() - npcWindow:getHeight()) / 2))
  npcWindow:setPosition({ x = x, y = y })
  return true
end

local function focusNpcTradeWindow()
  if not npcWindow or not npcWindow:isVisible() then
    return
  end

  local parent = npcWindow:getParent()
  if parent and parent.moveChildToIndex then
    parent:moveChildToIndex(npcWindow, #parent:getChildren())
  end

  npcWindow.close = function() closeNpcTrade() end
  npcWindow:raise()
  npcWindow:focus()
  setupPanel:enable()
end

function saveData()

end

function loadData()

end

function removeItemInList(clientId)
  if type(clientId) ~= "number" then
    return
  end
  g_game.removeFromBlacklist(clientId)
end

function inWhiteList(clientId)
  if not clientId then
    return
  end
  return g_game.isInBlacklist(clientId)
end

function addToWhitelist(clientId)
  if type(clientId) ~= "number" then
    return
  end

  g_game.addToBlacklist(clientId)
end

function init()
  npcWindow = g_ui.loadUI('npctrade', m_interface.getContainerPanel())
  npcWindow:show()
  npcWindow:setVisible(false)

  npcWindow:setContentMinimumHeight(175)
  npcWindow:setContentHeight(175)
  npcWindow:setup()

  itemsPanel = npcWindow:recursiveGetChildById('contentsPanel')
  searchText = npcWindow:recursiveGetChildById('searchText')

  setupPanel = npcWindow:recursiveGetChildById('setupPanel')
  quantityScroll = setupPanel:getChildById('quantityScroll')
  amountText = setupPanel:getChildById('amountText')

  priceLabel = setupPanel:getChildById('price')
  currencyMoneyLabel = setupPanel:getChildById('currencyMoneyLabel')
  moneyLabel = setupPanel:getChildById('money')
  itemButton = setupPanel:getChildById('item')
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
    onGameEnd = hide,
    onOpenNpcTrade = onOpenNpcTrade,
    onCloseNpcTrade = onCloseNpcTrade,
    onPlayerGoods = onPlayerGoods
  })

  connect(LocalPlayer, {
    onFreeCapacityChange = onFreeCapacityChange,
    onInventoryChange = onInventoryChange
  })

  initialized = true
end

function terminate()
  initialized = false
  npcWindow:destroy()

  disconnect(g_game, {
    onGameEnd = hide,
    onOpenNpcTrade = onOpenNpcTrade,
    onCloseNpcTrade = onCloseNpcTrade,
    onPlayerGoods = onPlayerGoods
  })

  disconnect(LocalPlayer, {
    onFreeCapacityChange = onFreeCapacityChange,
    onInventoryChange = onInventoryChange
  })
end

function show()
  if g_game.isOnline() then
    if #tradeItems[BUY] > 0 then
      radioTabs:selectWidget(buyTab)
      quickSellButton:setEnabled(false)
    else
      radioTabs:selectWidget(sellTab)
      quickSellButton:setEnabled(true)
    end

    if m_settings.getOption("showNpcDialogInNewWindow") then
      showNpcTradeAsWindow()
    else
      npcWindow:show()
      if not addNpcTradeToPanel() then
        showNpcTradeAsWindow()
      end
    end

    focusNpcTradeWindow()
  end
end

function start()
  loadData()
end

function hide()
  saveData()
  if not npcWindow then
    return
  end

  if not npcWindow:isVisible() then
    return
  end

  saveData()

  npcWindow:hide()

  toggleNPCFocus(false)
  modules.game_console.getConsole():focus()

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
end

function onItemBoxChecked(widget)
  itemButton:setItemId(0)
  quantityScroll:setValue(0)
  if widget:isChecked() then
    local item = widget.item
    selectedItem = item
    refreshItem(item)
    tradeButton:enable()

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

function switchTradeButton(value)
  tradeButton:setText(value)
end

function onTradeTypeChange(radioTabs, selected, deselected)
  tradeButton:setText(selected:getText())
  selected:setOn(true)
  deselected:setOn(false)

  if selected == buyTab then
    quickSellButton:setEnabled(false)
  else
    quickSellButton:setEnabled(true)
  end

  refreshTradeItems()
  refreshPlayerGoods()
end

function onTradeClick()
  if not selectedItem then return end
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
        g_game.setIgnoreEquipped(ignoreEquipped)
      end, "", equippedState)
  end
  menu:addSeparator()
  menu:addCheckBoxOption(tr('Show search field'), function() end, "", true)
  menu:addCheckBoxOption(tr('Do not show a warning when trading large amounts'), function() end, "", false)
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
          g_game.setIgnoreEquipped(ignoreEquipped)
        end, "", equippedState)
    end
    menu:addSeparator()
    menu:addCheckBoxOption(tr('Show search field'), function() end, "", true)
    menu:addCheckBoxOption(tr('Do not show a warning when trading large amounts'), function() end, "", false)
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

function setShowYourCapacity(state)

end

function clearSelectedItem()
  priceLabel:setText("0")
  quantityScroll:setMinimum(0)
  quantityScroll:setMaximum(0)
  quantityScroll:setValue(0)
  quantityScroll:setOn(true)
  amountText:setText('0')
  if selectedItem then
    radioItems:selectWidget(nil)
    selectedItem = nil
  end
end

function getCurrentTradeType()
  if tradeButton:getText() == tr('Buy') then
    return BUY
  else
    return SELL
  end
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

function getSellQuantity(item)
  if not item or not playerItems[item:getId()] then return 0 end
  local removeAmount = 0
  if ignoreEquipped then
    local localPlayer = g_game.getLocalPlayer()
    for i = 1, LAST_INVENTORY do
      local inventoryItem = localPlayer:getInventoryItem(i)
      if inventoryItem and (inventoryItem:getId() == item:getId() and inventoryItem:getTier() == item:getTier()) then
        removeAmount = removeAmount + inventoryItem:getCount()
      end
    end
  end
  return playerItems[item:getId()] - removeAmount
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
  itemButton.onMouseRelease = itemPopup

  if getCurrentTradeType() == BUY then
    local capacityMaxCount = math.floor(playerFreeCapacity / item.weight)
    if ignoreCapacity then
      capacityMaxCount = uint32Max
    end
    local priceMaxCount = math.floor(getPlayerMoney() / getItemPrice(item, true))
    local finalCount = math.max(0, math.min(getMaxAmount(item), math.min(priceMaxCount, capacityMaxCount)))
    quantityScroll:setMinimum(1)
    quantityScroll:setMaximum(finalCount)
  else
    quantityScroll:setMinimum(1)
    quantityScroll:setMaximum(math.max(0, math.min(getMaxAmount(item), getSellQuantity(item.ptr))))
  end

  local text = tonumber(amountText:getText())
  if not text then
    amountText:setText(quantityScroll:getMinimum())
  elseif text < quantityScroll:getMinimum() then
    amountText:setText(quantityScroll:getMinimum())
  elseif text > quantityScroll:getMaximum() then
    amountText:setText(quantityScroll:getMaximum())
  end

  setupPanel:enable()
  g_mouse.bindPress(itemButton,
    function(mousePos, mouseMoved) if g_keyboard.isShiftPressed() then g_game.inspectNpcTrade(itemButton:getItem()) end end)
end

function refreshTradeItems()
  if not g_game.isOnline() or not itemsPanel:isVisible() then
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
    if getCurrentTradeType() == SELL and not canTradeItem(item) then
      goto continue
    end
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
    itemBox.onMouseRelease = itemPopup

    if (string.len(item.name) > 15) or (string.len(informationText) > 16) then
      itemBox:setTooltip(string.format('%s\n%s', item.name, informationText))
    end

    if not canTradeItem(item) then
      itemBox.nameLabel:setColor('#707070')
    end

    radioItems:addWidget(itemBox)
    ::continue::
  end

  layout:enableUpdates()
  layout:update()
end

function refreshPlayerGoods()
  if not initialized then return end

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
end

function onOpenNpcTrade(buyItems, sellItems, currencyId, currencyName)
  buyItems, sellItems, currencyId, currencyName = normalizeNpcTradeArgs(buyItems, sellItems, currencyId, currencyName)

  CURRENCYID = currencyId
  currencyItem:setItemId(CURRENCYID)
  currencyItem:setVisible(true)
  itemBorder:setVisible(true)
  currencyItem:setItemCount(100)
  currencyItem:setShowCount(false)
  currencyMoneyLabel:setText('Gold:')

  if CURRENCYID ~= GOLD_COINS and currencyName == '' then
    currencyName = getItemServerName(CURRENCYID)
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

  tradeItems[BUY] = buyItems
  tradeItems[SELL] = sellItems

  addEvent(show) -- player goods has not been parsed yet
  scheduleEvent(refreshTradeItems, 50)
  scheduleEvent(refreshPlayerGoods, 50)
  if tradeButton:getText() == "Ok" then
    tradeButton:setText("Buy")
  end
end

function closeNpcTrade()
  g_game.doThing(false)
  g_game.closeNpcTrade()
  g_game.doThing(true)
  addEvent(hide)
end

function onCloseNpcTrade()
  if not npcWindow:isVisible() then
    return
  end

  addEvent(hide)
end

function onPlayerGoods(money, items)
  if type(money) == 'table' and items == nil then
    items = money
    money = nil
  end

  playerMoney = tonumber(money) or playerMoney or 0
  playerItems = {}

  if type(items) == 'table' then
    for id, itemData in pairs(items) do
      local itemId
      local amount

      if type(itemData) == 'table' then
        local ptr = itemData[1]
        if ptr and ptr.getId then
          itemId = ptr:getId()
        else
          itemId = itemData.id or itemData[1]
        end
        amount = itemData[2] or itemData.amount or itemData.count
      elseif type(id) == 'number' and type(itemData) == 'number' then
        itemId = id
        amount = itemData
      end

      itemId = tonumber(itemId)
      amount = tonumber(amount)
      if itemId and amount then
        playerItems[itemId] = (playerItems[itemId] or 0) + amount
      end
    end
  end

  refreshPlayerGoods()
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
  if item and item.ptr:isStackable() then
    return 10000
  end

  return 100
end

function getPlayerMoney()
  local player = g_game.getLocalPlayer()
  local currencyId = normalizeCurrencyId(CURRENCYID)

  if currencyId ~= GOLD_COINS and currencyId > 0 then
    local resourceMoney = safeResourceValue(player, ResourceNpcTrade)
    return resourceMoney > 0 and resourceMoney or playerMoney
  elseif currencyId == 0 then
    local resourceMoney = safeResourceValue(player, ResourceNpcStorageTrade)
    return resourceMoney > 0 and resourceMoney or playerMoney
  elseif playerMoney and playerMoney > 0 then
    return playerMoney
  end

  return safeResourceValue(player, ResourceBank) + safeResourceValue(player, ResourceInventary)
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

function onTradeAllClick()
  doOpenSellAll()
end

function isIgnoreEquipped()
  return ignoreEquipped
end

function isIgnoreCapacity()
  return ignoreCapacity
end

function isBuyWithBackpack()
  return buyWithBackpack
end
