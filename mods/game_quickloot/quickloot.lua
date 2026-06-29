local selectedContainerId = nil
local selectedContainerIdObtain = false
local mouseGrabberWidget = nil
local OPCODE_ITEM_DETAILS = 0xC7
local requestedItemNameDetails = {}
local pendingItemNameDetails = {}
local itemNameRequestQueue = {}
local itemNameRequestEvent = nil

quickLootWindow = nil
confirmWindow = nil
quickLootContainersPanel = nil
itemList = nil
quickLootCheckBox = nil
clearLootButton = nil
addToButton = nil
scrollBar = nil

quickLootFilter = nil
skippedLoot = nil
acceptedLoot = nil

allContainers = {}
obtainContainers = {}
lootData = {
  listType = "blacklist",
  blacklistTypes = {},
  whitelistTypes = {}
}

local cache = {
  listMin = 0,
  listMax = 0,
  listFit = 0,
  widgetSize = 16,
  listPool = 14,
  listData = {},
  offset = 0,
  scrollDelay = 0
}

local function sendNextItemNameRequest()
  itemNameRequestEvent = nil
  local protocolGame = g_game.getProtocolGame and g_game.getProtocolGame() or nil
  if not protocolGame then
    return
  end

  local itemId = table.remove(itemNameRequestQueue, 1)
  if not itemId then
    return
  end

  local msg = OutputMessage.create()
  msg:addU8(OPCODE_ITEM_DETAILS)
  msg:addU16(itemId)
  protocolGame:send(msg)

  pendingItemNameDetails[itemId] = true
  if #itemNameRequestQueue > 0 then
    itemNameRequestEvent = scheduleEvent(sendNextItemNameRequest, 350)
  end
end

local function requestItemNameDetails(itemId)
  itemId = tonumber(itemId) or 0
  if itemId <= 0 or requestedItemNameDetails[itemId] then
    return
  end

  local itemName = getItemServerName and getItemServerName(itemId) or ""
  if itemName and itemName ~= "" then
    return
  end

  if not (g_game.getProtocolGame and g_game.getProtocolGame()) then
    return
  end

  requestedItemNameDetails[itemId] = true
  table.insert(itemNameRequestQueue, itemId)
  if not itemNameRequestEvent then
    itemNameRequestEvent = scheduleEvent(sendNextItemNameRequest, 1)
  end
  scheduleEvent(function()
    pendingItemNameDetails[itemId] = nil
  end, 2000)
end

local function getQuickLootItemDisplayName(itemId)
  local itemName = getItemServerName and getItemServerName(itemId) or ""
  if itemName and itemName ~= "" then
    return itemName
  end

  requestItemNameDetails(itemId)
  return string.format("Item %d", tonumber(itemId) or 0)
end

function saveData()
  if not LoadedPlayer:isLoaded() then return end

  local file = "/characterdata/" .. LoadedPlayer:getId() .. "/lootBlackWhitelist.json"
  local status, result = pcall(function() return json.encode(lootData, 2) end)
  if not status then
      return g_logger.error("Error while saving profile lootData. Data won't be saved. Details: " .. result)
  end

  if result:len() > 100 * 1024 * 1024 then
      return g_logger.error("Something went wrong, file is above 100MB, won't be saved")
  end
  g_resources.writeFileContents(file, result)
end

function loadData()
  if not LoadedPlayer:isLoaded() then return end

  local file = "/characterdata/" .. LoadedPlayer:getId() .. "/lootBlackWhitelist.json"
  if g_resources.fileExists(file) then
    local status, result = pcall(function()
        return json.decode(g_resources.readFileContents(file))
    end)
    if not status then
        return g_logger.error("Error while reading profiles file. To fix this problem you can delete storage.json. Details: " .. result)
    end
    lootData = result
  else
    -- base
    lootData["blacklistTypes"] = {}
    lootData["listType"] = "blacklist"
    lootData["whitelistTypes"] = {}
  end

  if not lootData["blacklistTypes"] then
    lootData["blacklistTypes"] = {}
  end
  if not lootData["listType"] then
    lootData["listType"] = "blacklist"
  end
  if not lootData["whitelistTypes"] then
    lootData["whitelistTypes"] = {}
  end
end

function init()
  quickLootWindow = g_ui.displayUI('quickloot')
  quickLootWindow:hide()

  mouseGrabberWidget = g_ui.createWidget('UIWidget')
  mouseGrabberWidget:setVisible(false)
  mouseGrabberWidget:setFocusable(false)
  mouseGrabberWidget.onMouseRelease = onChooseItemMouseRelease

  skippedLoot    = quickLootWindow:getChildById('quickLootButtonsPanel'):getChildById('blacklist')
  acceptedLoot   = quickLootWindow:getChildById('quickLootButtonsPanel'):getChildById('whitelist')
  clearLootButton   = quickLootWindow:getChildById('quickLootButtonsPanel'):getChildById('clearLootButton')
  addToButton   = quickLootWindow:getChildById('quickLootButtonsPanel'):getChildById('addToButton')
  scrollBar = quickLootWindow:recursiveGetChildById('itemsScroll')

  quickLootFilter = UIRadioGroup.create()
  quickLootFilter:addWidget(skippedLoot)
  quickLootFilter:addWidget(acceptedLoot)

  quickLootContainersPanel = quickLootWindow:getChildById('quickLootContainers'):getChildById('quickLootContainersPanel')
  itemList = quickLootWindow:recursiveGetChildById('itemList')
  quickLootCheckBox = quickLootWindow:getChildById('quickLootFallback'):getChildById('quickLootFallbackToMainContainer')

  local count = 0
  for _, i in pairs(ObjectCategoryOrder) do
    if getObjectCategoryName(i) ~= '' then
      count = count + 1
      local widget = g_ui.createWidget('QuicklootContainerBox', quickLootContainersPanel)
      local color = (count % 2) == 0 and '#414141' or '#484848'

      widget:setId(i)
      widget:setBackgroundColor(color)
      widget:getChildById('containerType'):setText(getObjectCategoryName(i))
      widget:getChildById('buttonSelect').onClick = function()
        startChooseItem(i, false)
      end
      widget:getChildById('buttonClear').onClick = function()
        g_game.removeLootContainer(i)
        allContainers[i] = 0
        addEvent(refreshList, 500)
      end
      widget:getChildById('obtainButtonSelect').onClick = function()
        startChooseItem(i, true)
      end
      widget:getChildById('obtainButtonClear').onClick = function()
        g_game.removeObtainContainer(i)
        obtainContainers[i] = 0
        addEvent(refreshList, 500)
      end

      widget:getChildById('containerId'):setItem(Item.create(allContainers[i] or 0, 1))
      widget:getChildById('obtainContainerId'):setItem(Item.create(obtainContainers[i] or 0, 1))
    end
  end

  connect(g_game, { onGameEnd = finish })
  connect(g_game, { onGameStart = start })
  connect(g_game, { onParseLootContainers = onParseLootContainers })
  connect(g_game, { onItemDetails = onQuickLootItemDetails })

  connect(quickLootFilter, { onSelectionChange = onSelectionChange })
end

function terminate()
  if itemNameRequestEvent then
    removeEvent(itemNameRequestEvent)
    itemNameRequestEvent = nil
  end
  itemNameRequestQueue = {}
  requestedItemNameDetails = {}
  pendingItemNameDetails = {}

  quickLootCheckBox = nil
  quickLootContainersPanel = nil
  clearLootButton = nil
  addToButton = nil
  lootData = {
    listType = "blacklist",
    blacklistTypes = {},
    whitelistTypes = {}
  }

  if mouseGrabberWidget then
    mouseGrabberWidget:destroy()
    mouseGrabberWidget = nil
  end

  if quickLootWindow then
    quickLootWindow:destroy()
    quickLootWindow = nil
  end

  disconnect(g_game, { onGameEnd = finish })
  disconnect(g_game, { onGameStart = start })
  disconnect(g_game, { onParseLootContainers = onParseLootContainers })
  disconnect(g_game, { onItemDetails = onQuickLootItemDetails })
  disconnect(quickLootFilter, { onSelectionChange = onSelectionChange })
end

local function refreshList()

  for i = ObjectCategory.OBJECTCATEGORY_LAST, ObjectCategory.OBJECTCATEGORY_FIRST, -1 do
    if getObjectCategoryName(i) ~= '' then
      local widget = quickLootContainersPanel:getChildById(i)
      if widget then
        widget:getChildById('containerId'):setItem(Item.create(allContainers[i] or 0, 1))
        widget:getChildById('obtainContainerId'):setItem(Item.create(obtainContainers[i] or 0, 1))
      end
    end
  end
end

function showQuickLoot()
  updateLootItems()
  refreshList()
  addEvent(function()
    if quickLootWindow and quickLootWindow:isVisible() then
      refreshList()
    end
  end, 300)
  quickLootWindow.searchText:clearText()
  quickLootWindow:show(true)
  quickLootWindow:focus()
  g_client.setInputLockWidget(quickLootWindow)
end

function hideQuickLoot()
  g_client.setInputLockWidget(nil)
  quickLootWindow:hide()
end

function onChooseItemMouseRelease(self, mousePosition, mouseButton)
  local item = nil
  if mouseButton == MouseLeftButton then
    local clickedWidget = m_interface.getRootPanel():recursiveGetChildByPos(mousePosition, false)
    if clickedWidget then
      if clickedWidget:getClassName() == 'UIGameMap' then
        local tile = clickedWidget:getTile(mousePosition)
        if tile then
          local thing = tile:getTopMoveThing()
          if thing and thing:isItem() then
            item = thing
          end
        end
      elseif clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
        item = clickedWidget:getItem()
      end
    end
  end

  if item and item:isContainer() and (item:getParentContainer() or item:getPosition().x == uint16Max) and item:isPickupable() then
    g_game.updateLootContainer((selectedContainerIdObtain and 4 or 0), selectedContainerId, item:getPosition(), item:getId(), item:getStackPos())
    selectedContainerId = nil
  else
    modules.game_textmessage.displayFailureMessage(tr('Sorry, not possible.'))
  end

  showQuickLoot()
  g_mouse.updateGrabber(mouseGrabberWidget, 'target')
  mouseGrabberWidget:ungrabMouse()
  g_mouse.popCursor('target')
  return true
end

function startChooseItem(id, obtain)
  if g_ui.isMouseGrabbed() then return end
  g_mouse.updateGrabber(mouseGrabberWidget, 'target')
  mouseGrabberWidget:grabMouse()
  g_mouse.pushCursor('target')
  selectedContainerId = id
  selectedContainerIdObtain = obtain
  hideQuickLoot()
end

function start()
  local benchmark = g_clock.millis()
  loadData()
  local lootType = lootData["listType"]
  if g_game.isOnline() then
    local lootTable = (lootType == "whitelist" and lootData["whitelistTypes"] or lootData["blacklistTypes"])
    g_game.doThing(false)
    g_game.updateLootWhiteList(lootType == "whitelist", lootTable or {})
    g_game.doThing(true)
  end

  updateLootItems()
  if lootType == "whitelist" then
	  quickLootFilter:selectWidget(acceptedLoot)
    clearLootButton:setImageSource("/images/game/quickloot/clear-accepted-button")
    addToButton:setImageSource("/images/game/quickloot/add-accepted-button")
  else
	  quickLootFilter:selectWidget(skippedLoot)
    clearLootButton:setImageSource("/images/game/quickloot/clear-button")
    addToButton:setImageSource("/images/game/quickloot/add-button")
  end
  consoleln("Quick Loot loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function reloadLootWhiteList()
  local lootType = lootData["listType"]
  local lootTable = (lootType == "whitelist" and lootData["whitelistTypes"] or lootData["blacklistTypes"])
  g_game.doThing(false)
  g_game.updateLootWhiteList(lootType == "whitelist", lootTable or {})
  g_game.doThing(true)
end

function finish()
  hideQuickLoot()
  saveData()
  if itemNameRequestEvent then
    removeEvent(itemNameRequestEvent)
    itemNameRequestEvent = nil
  end
  itemNameRequestQueue = {}
  requestedItemNameDetails = {}
  pendingItemNameDetails = {}
  if confirmWindow then
    confirmWindow:destroy()
    confirmWindow = nil
  end
end

function onQuickLootItemDetails(itemId)
  itemId = tonumber(itemId) or 0
  if itemId <= 0 or not requestedItemNameDetails[itemId] then
    return
  end

  pendingItemNameDetails[itemId] = nil
  if quickLootWindow and quickLootWindow:isVisible() then
    local searchText = quickLootWindow.searchText and quickLootWindow.searchText:getText() or nil
    updateLootItems(searchText)
  end
end

function onParseLootContainers(quickLootFallbackToMainContainer, containers, obtainContainer)
  local checked = quickLootFallbackToMainContainer == 1 and true or false
  quickLootCheckBox:setChecked(checked)

  allContainers = containers
  obtainContainers = obtainContainer

  updateLootItems()
  refreshList()
end

function addToQuickLoot(clientId)
  if type(clientId) ~= "number" then
    return
  end

  local lootConfig = lootData["listType"]
  local lootTable = (lootConfig == "whitelist" and lootData["whitelistTypes"] or lootData["blacklistTypes"])
  local filter = lootConfig == "whitelist"
  if not lootTable then
    lootTable = {}
    if lootConfig == "whitelist" then
      lootData.whitelistTypes = lootTable
    else
      lootData.blacklistTypes = lootTable
    end
  end

  if table.contains(lootTable, clientId) then
    return
  end

  table.insert(lootTable, clientId)
  updateLootItems()

  g_game.updateLootWhiteList(filter, lootTable)
end

function updateLootItems(searchText)
  local lootConfig = lootData["listType"]
  local lootTable = (lootConfig == "whitelist" and lootData["whitelistTypes"] or lootData["blacklistTypes"])
  if not lootTable then
    lootTable = {}
  end

  if not scrollBar then
    return
  end

  itemList:destroyChildren()

  cache.listFit = math.floor(itemList:getHeight() / 38) + 2
	cache.listMin = 0
	cache.listPool = {}
	cache.listData = {}

  if not searchText or #searchText == 0 then
    cache.listData = lootTable
  else
    for i, itemId in pairs(lootTable) do
      local itemName = getQuickLootItemDisplayName(itemId)
      if matchText(searchText, itemName) then
        table.insert(cache.listData, itemId)
      end
    end
  end

  local count = 0
  for i, itemId in pairs(cache.listData) do
    if #cache.listPool >= cache.listFit then
      break
    end

    count = count + 1
    local itemName = getQuickLootItemDisplayName(itemId)
    local widget = g_ui.createWidget('QuicklootItemBox', itemList)
    local color = (count % 2) == 0 and '#414141' or '#484848'

    widget:setId(itemId)
    widget:setBackgroundColor(color)
    widget:getChildById('itemType'):setText(itemName)
    widget:getChildById('itemId'):setItemId(itemId)

    widget:getChildById('buttonItemClear').onClick = function()
      removeItemInList(itemId)
    end

    table.insert(cache.listPool, widget)
  end

  cache.listMax = #cache.listData
  scrollBar:setValue(0)
  scrollBar:setMinimum(#cache.listPool > 0 and 1 or 0)
	scrollBar:setMaximum(#cache.listPool < 9 and 0 or math.max(0, cache.listMax - #cache.listPool) + 2)
	scrollBar.onValueChange = function(self, value, delta) onItemListValueChange(self, value, delta) end

	itemList:setVirtualOffset({x = 0, y = 0})
end

function onItemListValueChange(scroll, value, delta)
	local startLabel = math.max(cache.listMin, value)
	local endLabel = startLabel + #cache.listPool - 1
  
	if endLabel > cache.listMax then
	  endLabel = cache.listMax
	  startLabel = endLabel - #cache.listPool + 1
	end

	cache.offset = cache.offset + ((value % 5) * 2)
	if cache.offset > 20 or value <= 1 then
		cache.offset = 0
	end

	if value >= #cache.listData - 8 then
		cache.offset = 43
	end

	itemList:setVirtualOffset({x = 0, y = cache.offset})

	for i, widget in ipairs(cache.listPool) do
	  local index = value > 0 and (startLabel + i - 1) or (startLabel + i)
	  local itemId = cache.listData[index]

    if itemId then
      local color = (index % 2) == 0 and '#414141' or '#484848'
      local itemName = getQuickLootItemDisplayName(itemId)
      widget:setId(itemId)
      widget:setBackgroundColor(color)
      widget:getChildById('itemType'):setText(itemName)
      widget:getChildById('itemId'):setItemId(itemId)

      widget:getChildById('buttonItemClear').onClick = function() removeItemInList(itemId) end
    end
	end
end

function onSelectionChange(widget, selectedWidget)
  lootData["listType"] = selectedWidget:getId()

  if selectedWidget:getId() == "whitelist" then
    clearLootButton:setImageSource("/images/game/quickloot/clear-accepted-button")
    addToButton:setImageSource("/images/game/quickloot/add-accepted-button")
  else
    clearLootButton:setImageSource("/images/game/quickloot/clear-button")
    addToButton:setImageSource("/images/game/quickloot/add-button")
  end

  updateLootItems()

  if g_game.isOnline() then
    local lootConfig = lootData["listType"]
    local lootTable = (lootConfig == "whitelist" and lootData["whitelistTypes"] or lootData["blacklistTypes"])
    local filter = lootConfig == "whitelist"
    g_game.doThing(false)
    g_game.updateLootWhiteList(filter, lootTable or {})
    g_game.doThing(true)
  end
end

function removeItemInList(clientId)
  if type(clientId) ~= "number" then
    return
  end

  local lootConfig = lootData["listType"]
  local lootTable = (lootConfig == "whitelist" and lootData["whitelistTypes"] or lootData["blacklistTypes"])
  if not table.contains(lootTable, clientId) then
    return
  end

  for k, v in pairs(lootTable) do
    if v == clientId then
      table.remove(lootTable, k)
      break
    end
  end

  updateLootItems()
  g_game.updateLootWhiteList(lootConfig == "whitelist", lootTable)
end

function inWhiteList(clientId)
  if not clientId then
    clientId = 0
  end

  local lootConfig = lootData["listType"] or "whitelist"
  local lootTable = (lootConfig == "whitelist" and lootData["whitelistTypes"] or lootData["blacklistTypes"])
  if not lootTable then
	return false
  end

  return table.contains(lootTable, clientId)
end

function GetLootContainers()
  local c = {}
  for _, id in pairs(allContainers) do
    table.insert(c, id)
  end

  return c
end

function clearCurrentList()
  if confirmWindow then
    return
  end

  local okFunc = function()
    local currentList = lootData["listType"]
    if currentList == "whitelist" then
    lootData["whitelistTypes"] = {}
    else
    lootData["blacklistTypes"] = {}
    end
    updateLootItems()
    g_client.setInputLockWidget(nil)
    quickLootWindow:show(true)
    g_client.setInputLockWidget(quickLootWindow)
    confirmWindow:destroy()
    confirmWindow = nil
  end

  local cancelFunc = function()
    g_client.setInputLockWidget(nil)
    quickLootWindow:show(true)
    g_client.setInputLockWidget(quickLootWindow)
    confirmWindow:destroy()
    confirmWindow = nil
  end

  local currentList = lootData["listType"]
  local actionType = currentList == "whitelist" and "Accepted" or "Skipped"
  quickLootWindow:hide()
  g_client.setInputLockWidget(nil)
	confirmWindow = displayGeneralBox(tr("Confirm Clearing of %s Loot List", actionType), tr("You are about to delete all objects from your %s Loot List.\nIf you click on \"Ok\", you will loot all dropped items and gold when using the quick loot function.", actionType),
    { { text=tr('Yes'), callback=okFunc },
    { text=tr('No'), callback=cancelFunc }
  }, okFunc, cancelFunc)
  g_client.setInputLockWidget(confirmWindow)
end

function redirectCyclopedia()
  quickLootWindow:hide()
  g_client.setInputLockWidget(nil)
  modules.game_cyclopedia:toggle()
end
