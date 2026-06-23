local filters = {}

local ContainerConfig = {
  sortContainerFirst = false,
  sortNestedContainers = false,
  moveNestedContainer = false,
  moveManualSort = false,
}

function init()
  connect(Container, { onOpen = onContainerOpen,
                       onClose = onContainerClose,
                       onSizeChange = onContainerChangeSize,
                       onRemoveItem = onRemoveItem,
                       onUpdateItem = onContainerUpdateItem })
  connect(g_game, {
    onGameEnd = clean
  })

  reloadContainers()
end

function terminate()
  disconnect(Container, { onOpen = onContainerOpen,
                          onClose = onContainerClose,
                          onSizeChange = onContainerChangeSize,
                          onRemoveItem = onRemoveItem,
                          onUpdateItem = onContainerUpdateItem })
  disconnect(g_game, {
    onGameEnd = clean
  })
end

function reloadContainers()
  clean()
  for _,container in pairs(g_game.getContainers()) do
    onContainerOpen(container)
  end
end

function updateContainerTitleColor(color)
  for containerid, container in pairs(g_game.getContainers()) do
    if container.window then
      container.window:setColor(color)
    end
  end
end

function clean()
  for containerid,container in pairs(g_game.getContainers()) do
    destroy(container)
  end
end

function destroy(container)
  if container.window then
    container.window:destroy()
    container.window = nil
    container.itemsPanel = nil
  end
end

function refreshContainerItems(container)
  for slot=0,container:getCapacity()-1 do
    local itemWidget = container.itemsPanel:getChildById('item' .. slot)
    local item = container:getItem(slot)
    itemWidget:setItem(item)
    ItemsDatabase.setRarityItem(itemWidget, item)
    ItemsDatabase.setTier(itemWidget, item)
    updateFlags(item, itemWidget)
  end

  if container:hasPages() then
    refreshContainerPages(container)
  end
end

function toggleContainerPages(containerWindow, hasPages)
  if hasPages == containerWindow.pagePanel:isOn() then
    return
  end
  containerWindow.pagePanel:setOn(hasPages)
  if hasPages then
    containerWindow.miniwindowScrollBar:setMarginBottom(30)
    containerWindow.contentsPanel:setMarginBottom(30)
  else
    containerWindow.miniwindowScrollBar:setMarginBottom(5)
    containerWindow.contentsPanel:setMarginBottom(5)
  end
end

function refreshContainerPages(container)
  local currentPage = 1 + math.floor(container:getFirstIndex() / container:getCapacity())
  local pages = 1 + math.floor(math.max(0, (container:getSize() - 1)) / container:getCapacity())
  container.window:recursiveGetChildById('pageLabel'):setText(string.format('Page %i of %i', currentPage, pages))

  local prevPageButton = container.window:recursiveGetChildById('prevPageButton')
  if currentPage == 1 then
    prevPageButton:setVisible(false)
  else
    prevPageButton:setVisible(true)
    prevPageButton.onClick = function() g_game.seekInContainer(container:getId(), container:getFirstIndex() - container:getCapacity()) end
  end

  local nextPageButton = container.window:recursiveGetChildById('nextPageButton')
  if currentPage >= pages then
    nextPageButton:setVisible(false)
  else
    nextPageButton:setVisible(true)
    nextPageButton.onClick = function() g_game.seekInContainer(container:getId(), container:getFirstIndex() + container:getCapacity()) end
  end

  local pagePanel = container.window:recursiveGetChildById('pagePanel')
  if pagePanel then
    pagePanel.onMouseWheel = function(widget, mousePos, mouseWheel)
      if pages == 1 then return end
      if mouseWheel == MouseWheelUp then
        if not prevPageButton.onClick then
          return
        end
        return prevPageButton.onClick()
      else
        if not nextPageButton.onClick then
          return
        end
        return nextPageButton.onClick()
      end
    end
  end
end

function onContainerOpen(container, previousContainer)
  local containerWindow
  if previousContainer then
    containerWindow = previousContainer.window
    previousContainer.window = nil
    previousContainer.itemsPanel = nil
  else
    containerWindow = g_ui.createWidget('ContainerWindow', m_interface.getContainerPanel())
    if not m_interface.addToPanels(containerWindow) then
      return false
    end

    containerWindow:getParent():moveChildToIndex(containerWindow, #containerWindow:getParent():getChildren())
    -- white border flash effect
    containerWindow:setBorderWidth(2)
    containerWindow:setBorderColor("#FFFFFF")
    scheduleEvent(function()
      if containerWindow then
        containerWindow:setBorderWidth(0)
      end
    end, 300)
  end

  if not containerWindow then return end

  containerWindow.instance = container:getId()
  containerWindow.isOpen = true
  containerWindow:setId('container' .. container:getId())
  containerWindow.container = container

  local containerPanel = containerWindow:getChildById('contentsPanel')
  local containerItemWidget = containerWindow:getChildById('containerItemWidget')
  containerWindow.onClose = function()
    g_game.doThing(false)
    g_game.close(container)
    g_game.doThing(true)
    containerWindow:close()
  end
  containerWindow.onDrop = function(container, widget, mousePos)
    if containerPanel:getChildByPos(mousePos) then
      return false
    end
    local child = containerPanel.getNearestChild and containerPanel:getNearestChild(mousePos) or containerPanel:getChildByIndex(-1)
    if child then
      child:onDrop(widget, mousePos, true)
    end
  end

  containerWindow.onMousePress = function(widget, mousePos, mouseButton)
    xToleranceLeft = containerWindow:getX() + 5
    xToleranceRight = containerWindow:getX() + containerWindow:getWidth() - 5
    yToleranceTop = containerWindow:getY() + 2
    yToleranceBottom = containerWindow:getY() + containerWindow:getHeight() - 2

    -- hack to ensure we do actually select something - without it you can select "nothing" and throw an error
    if mousePos.x < xToleranceLeft or mousePos.x > xToleranceRight or mousePos.y > yToleranceBottom or mousePos.y < yToleranceTop then
      containerWindow:setDraggable(false)
      return false
    end

    local child = containerWindow:getChildByPos(mousePos)
    if child == containerPanel then
        containerWindow:setDraggable(false)
    end
  end
  containerWindow.onMouseRelease = function(widget, mousePos, mouseButton)
    containerWindow:setDraggable(true)
    if mouseButton == MouseButton4 then
      if container:hasParent() then
        return g_game.openParent(container)
      end
    elseif mouseButton == MouseButton5 then
      for i, item in ipairs(container:getItems()) do
        if item:isContainer() then
          return g_game.open(item, container)
        end
      end
    end
  end

  -- this disables scrollbar auto hiding
  local scrollbar = containerWindow:getChildById('miniwindowScrollBar')
  scrollbar:mergeStyle({ ['$!on'] = { }})

  local searchButton = containerWindow:getChildById('searchButton')
  searchButton:setVisible(container.hasDepotSearch and container:hasDepotSearch() or false)

  local upButton = containerWindow:getChildById('upButton')
  upButton.onClick = function()
    g_game.openParent(container)
  end
  upButton:setVisible(container:hasParent())

  local filterContainer = containerWindow:getChildById('filterContainer')
  filterContainer.onClick = function()
    onExtraMenu(container:getId())
  end
  
  filterContainer:breakAnchors()
  if container:hasParent() then
    filterContainer:addAnchor(AnchorTop, upButton:getId(), AnchorTop)
    filterContainer:addAnchor(AnchorRight, upButton:getId(), AnchorLeft)
  else
    filterContainer:addAnchor(AnchorTop, 'lockButton', AnchorTop)
    filterContainer:addAnchor(AnchorRight, 'lockButton', AnchorLeft)
  end
  filterContainer:setMarginRight(1)
  filterContainer:setMarginTop(0)

  local name = container:getName()
  name = name:gsub("(%a)([%w_']*)", function(first, rest) return first:upper()..rest:lower() end)

  if name:len() > 12 and name ~= 'Your Store Inbox' then
    name = short_text(name, 12)
 end

  containerWindow:setText(name)

  local itemTop = container:getContainerItem()
  containerItemWidget:setItem(itemTop)

  containerPanel:destroyChildren()

  for slot=0,container:getCapacity()-1 do
    local itemWidget = g_ui.createWidget('Item', containerPanel)
    itemWidget:setId('item' .. slot)
    local itemSlot = container:getItem(slot)

    itemWidget:setItem(itemSlot)
    ItemsDatabase.setRarityItem(itemWidget, itemSlot)
    ItemsDatabase.setTier(itemWidget, itemSlot)
    itemWidget:setMargin(0)
    itemWidget.position = container:getSlotPosition(slot)
    updateFlags(itemSlot, itemWidget)
    if isCorpse(itemTop:getId()) and itemSlot then
      itemSlot:setInCorpse(true)
    end

    if not container:isUnlocked() then
      itemWidget:setBorderColor('red')
    end
  end

  container.window = containerWindow
  container.itemsPanel = containerPanel

  toggleContainerPages(containerWindow, container:hasPages())
  refreshContainerPages(container)

  addEvent(function ()
    local layout = containerPanel:getLayout()
    if not layout then
      return
    end

    local cellSize = layout:getCellSize()
    containerWindow:setContentMinimumHeight(cellSize.height)
    containerWindow:setContentMaximumHeight((cellSize.height+3)*layout:getNumLines())

    if container:hasPages() then
      local height = containerWindow.miniwindowScrollBar:getMarginTop() + containerWindow.pagePanel:getHeight()+17
      if containerWindow:getHeight() < height then
        containerWindow:setHeight(height)
      end
    end
    
    if not previousContainer then
      containerWindow:setHeight(30)
      if not m_interface.addToPanels(containerWindow) then
        return false
      end

      containerWindow:getParent():moveChildToIndex(containerWindow, #containerWindow:getParent():getChildren())
    end

    if not previousContainer then
      local filledLines = math.max(math.ceil(container:getItemsCount() / layout:getNumColumns()), 1)
      if filledLines < layout:getNumLines() then
        if container:getItemsCount() ~= 0 then
          containerWindow:setContentHeight(filledLines*(cellSize.height+6)+3)
        else
          containerWindow:setContentHeight(filledLines*(cellSize.height+6)-3)
        end
      else
        containerWindow:setContentHeight(filledLines*(cellSize.height+6))
      end
    elseif container:hasPages() and containerWindow:getContentHeight() < 83 then
      containerWindow:setHeight(84)
    end


    containerWindow:setup()
    containerWindow:setColor(ContainerConfig.moveManualSort and "#C28400" or "#909090")
  end)

end

function onContainerClose(container)
  destroy(container)
end

function onContainerChangeSize(container, size)
  if not container.window then return end
  refreshContainerItems(container)
end

function onContainerUpdateItem(container, slot, item, oldItem)
  if not container.window then return end
  local itemWidget = container.itemsPanel:getChildById('item' .. slot)
  itemWidget:setItem(item)
  ItemsDatabase.setRarityItem(itemWidget, item)
  ItemsDatabase.setTier(itemWidget, item)
  if itemWidget then
    updateFlags(item, itemWidget)
  end
end

local function callOnRemoveItem(container, slot, item)
  if not container.window then return end
  local itemWidget = container.itemsPanel:getChildById('item' .. slot)
  if itemWidget then
    itemWidget.quicklootflags:setVisible(false)
  end

  refreshContainerItems(container)
end

function onRemoveItem(container, slot, item)
  tryCatch(callOnRemoveItem, container, slot, item)
end

function move(instance, panel, height, index, minimized, locked)
  local container = 'container'..instance
  local widget = rootWidget:recursiveGetChildById(container)

  if not widget then return end

  widget:setParent(panel)
  widget:open()

  if minimized then
    widget:setHeight(height)
    widget:minimize()
  else
    widget:maximize()
    widget:setHeight(height)
  end

  if locked then
    scheduleEvent(function()
      if not widget then return end
      widget:lock(true)
    end, 100)
  end

  return widget
end

function onExtraMenu(containerId)
  local mousePosition = g_window.getMousePosition()
  if cancelNextRelease then
    cancelNextRelease = false
    return false
  end

  local menu = g_ui.createWidget('PopupMenu')

  local sortContainerFirst = m_settings.getOption("containerSortBackpacksFirst")
  local sortNestedContainers = m_settings.getOption("containerSortRecursive")
  local moveNestedContainer = m_settings.getOption("containerMoveToManagedContainerRecursive")

  menu:setGameMenu(true)
  menu:addOption('Sort Ascending by Name', function() g_game.sortContainer(containerId, ContainerSortType.ascendingName, sortContainerFirst, sortNestedContainers) end)
  menu:addOption('Sort Descending by Name', function() g_game.sortContainer(containerId, ContainerSortType.descendingName, sortContainerFirst, sortNestedContainers) end)
  menu:addOption('Sort Ascending by Weight', function() g_game.sortContainer(containerId, ContainerSortType.ascendingWeight, sortContainerFirst, sortNestedContainers) end)
  menu:addOption('Sort Descending by Weight', function() g_game.sortContainer(containerId, ContainerSortType.descendingWeight, sortContainerFirst, sortNestedContainers) end)
  menu:addOption('Sort Ascending by Expire', function() g_game.sortContainer(containerId, ContainerSortType.ascendingExpiry, sortContainerFirst, sortNestedContainers) end)
  menu:addOption('Sort Descending by Expire', function() g_game.sortContainer(containerId, ContainerSortType.descendingExpiry, sortContainerFirst, sortNestedContainers) end)
  menu:addOption('Sort Ascending by Stack Size', function() g_game.sortContainer(containerId, ContainerSortType.ascendingStackSize, sortContainerFirst, sortNestedContainers) end)
  menu:addOption('Sort Descending by Stack Size', function() g_game.sortContainer(containerId, ContainerSortType.descendingStackSize, sortContainerFirst, sortNestedContainers) end)
  menu:addSeparator()
  menu:addCheckBoxOption('Sort Containers First', function() m_settings.setOption("containerSortBackpacksFirst", not sortContainerFirst) end, "", sortContainerFirst)
  menu:addCheckBoxOption('Sort Nested Containers', function() m_settings.setOption("containerSortRecursive", not sortNestedContainers) end, "", sortNestedContainers)
  menu:addCheckBoxOption('Use Manual Sort Mode', function()
    toggleManualSort()

    updateContainerTitleColor(ContainerConfig.moveManualSort and "#C28400" or "#909090")
  end, "", ContainerConfig.moveManualSort)
  menu:addSeparator()
  menu:addOption("Move Contents to 'Obtain' Containers", function() g_game.obtainContainer(containerId, moveNestedContainer) end)
  menu:addCheckBoxOption('Move Nested Containers', function() m_settings.setOption("containerMoveToManagedContainerRecursive", not moveNestedContainer) end, "", moveNestedContainer)
  menu:display(mousePosition)
  return true
end

function useManualSort()
  return ContainerConfig.moveManualSort
end

function toggleManualSort()
  ContainerConfig.moveManualSort = not ContainerConfig.moveManualSort
end
