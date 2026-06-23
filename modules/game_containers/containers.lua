local filters = {}

local ContainerConfig = {
  sortContainerFirst = false,
  sortNestedContainers = false,
  moveNestedContainer = false,
  moveManualSort = false,
}

-- Pending "go back to parent" requests, keyed by the container slot id. Set right before
-- g_game.openParent so onContainerOpen can tell a parent-navigation apart from a fresh open.
local parentNavRequest = {}

-- True when both containers refer to the very same container item (same id and position).
-- A page seek (prev/next button) reopens the same container, while descending into a
-- sub-container or going back to the parent reopens a different one. We use this to avoid
-- treating a page change as a navigation (which would corrupt the saved-page stack).
-- Note: getPosition() returns nil for items with an invalid position (e.g. the virtual
-- Store Inbox), so it must be handled carefully or a page seek would throw and the page
-- would never refresh. When the id matches and we have no usable position, assume it is
-- the same container so a seek is never mistaken for a navigation.
local function sameContainerItem(a, b)
  if not a or not b then return false end
  local ia, ib = a:getContainerItem(), b:getContainerItem()
  if not ia or not ib then return false end
  if ia:getId() ~= ib:getId() then return false end
  local pa, pb = ia:getPosition(), ib:getPosition()
  if not pa or not pb then return true end
  return pa.x == pb.x and pa.y == pb.y and pa.z == pb.z
end

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
    itemWidget:setItem(container:getItem(slot))
    updateFlags(container:getItem(slot), itemWidget)
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

    -- Remember which page we were on as we move between nested containers, so the back
    -- arrow can return to it instead of snapping to page 1. The stack lives on the reused
    -- window widget, so it survives the parent<->child navigation. A plain page seek keeps
    -- the same container item, so it is skipped to avoid corrupting the stack.
    if containerWindow then
      local pageStack = containerWindow.pageStack
      if not pageStack then
        pageStack = {}
        containerWindow.pageStack = pageStack
      end

      local wantParent = parentNavRequest[container:getId()]
      parentNavRequest[container:getId()] = nil

      if not sameContainerItem(previousContainer, container) then
        if wantParent then
          -- Going back to a parent container: restore the page we left it on.
          containerWindow.restoreFirstIndex = table.remove(pageStack)
        else
          -- Descending into a sub-container: remember the page of the one we leave.
          table.insert(pageStack, previousContainer:getFirstIndex())
        end
      end
    end
  else
    containerWindow = g_ui.createWidget('ContainerWindow', m_interface.getContainerPanel())
    -- If this container held a saved slot at logout, restore it there instead of
    -- letting addToPanels drop it in the first panel with free space. The server
    -- reopens containers a poll after the layout was restored, so the placement was
    -- stashed by m_interface and is claimed here when the window finally exists.
    local placement = m_interface.takePendingContainerRestore(container:getId())
    if placement and not m_interface.isRestorePanelUsable(placement.panel) then
      placement = nil
    end
    if CONTAINER_RESTORE_DEBUG then
      g_logger.info(string.format("[BPRESTORE] open id=%s name=%s placementAtCreate=%s",
        tostring(container:getId()), tostring(container:getName()),
        placement and tostring(placement.panel:getId()) or "none"))
    end
    containerWindow.savedPlacement = placement
    if placement and placement.panel then
      containerWindow:setParent(placement.panel)
    else
      if not m_interface.addToPanels(containerWindow) then
        return false
      end

      containerWindow:getParent():moveChildToIndex(containerWindow, #containerWindow:getParent():getChildren())
    end
    -- white border flash effect
    containerWindow:setBorderWidth(2)
    containerWindow:setBorderColor("#FFFFFF")
    scheduleEvent(function()
      if containerWindow then
        -- Don't clobber a restored container's red lock border (set ~100ms after open).
        if containerWindow.isLocked and containerWindow:isLocked() then
          containerWindow:setBorderWidth(1)
          containerWindow:setBorderColor('$var-text-cip-store-red')
        else
          containerWindow:setBorderWidth(0)
        end
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
    -- Dropped on the window chrome (header/border), not directly on a slot. getNearestChild
    -- is not bound on this client, so find the closest slot by center distance and route the
    -- drop there, so moving an item onto the header still works instead of erroring.
    local nearest, nearestDist
    for _, child in ipairs(containerPanel:getChildren()) do
      if child.position then -- only the item slots (they carry a container slot position)
        local cx = child:getX() + child:getWidth() / 2
        local cy = child:getY() + child:getHeight() / 2
        local dx, dy = cx - mousePos.x, cy - mousePos.y
        local dist = dx * dx + dy * dy
        if not nearestDist or dist < nearestDist then
          nearest, nearestDist = child, dist
        end
      end
    end
    if nearest then
      nearest:onDrop(widget, mousePos, true)
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
        parentNavRequest[container:getId()] = true
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
    parentNavRequest[container:getId()] = true
    g_game.openParent(container)
  end
  upButton:setVisible(container:hasParent())

  local filterContainer = containerWindow:getChildById('filterContainer')
  filterContainer.onClick = function()
    onExtraMenu(container:getId())
  end
  
  if container:hasParent() then
    filterContainer:setMarginRight(15)
  else
    filterContainer:setMarginRight(5)
  end

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

  -- We came back to a parent container that the server reopened at page 1; jump back to
  -- the page the user was actually viewing. Only seek when the saved page is still valid.
  if containerWindow.restoreFirstIndex ~= nil then
    local target = containerWindow.restoreFirstIndex
    containerWindow.restoreFirstIndex = nil
    if container:hasPages() and target > 0 and target < container:getSize()
        and container:getFirstIndex() ~= target then
      g_game.seekInContainer(container:getId(), target)
    end
  end

  addEvent(function ()
    local layout = containerPanel:getLayout()
    if not layout then
      containerWindow.savedPlacement = nil
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
    
    local placement = containerWindow.savedPlacement
    if not placement then
      -- Same-poll relog: the container reopened before onPlayerLoad recorded its saved
      -- slot, so nothing was available at creation time and addToPanels placed it by
      -- default. onPlayerLoad's restore pass runs before this deferred block, so the
      -- pending placement exists now; claim it and override the default placement.
      placement = m_interface.takePendingContainerRestore(container:getId())
    end
    if placement and not m_interface.isRestorePanelUsable(placement.panel) then
      placement = nil
    end
    containerWindow.savedPlacement = nil

    if CONTAINER_RESTORE_DEBUG and not previousContainer then
      g_logger.info(string.format("[BPRESTORE] deferred id=%s placementFinal=%s index=%s",
        tostring(container:getId()),
        placement and tostring(placement.panel:getId()) or "addToPanels-default",
        placement and tostring(placement.index) or "-"))
    end

    if not previousContainer then
      -- Detach first: while parented to a (possibly full) panel, growing the window
      -- to its natural height makes the panel's fitAll clamp/cut it before we get to
      -- choose where it really belongs. Detached, it reaches its true height so the
      -- placement step can tell whether it fits a panel WHOLE.
      local curParent = containerWindow:getParent()
      if curParent then
        curParent:removeChild(containerWindow)
      end

      -- 1) Bring the window to the height it will actually render at.
      if placement and placement.minimized then
        if placement.height then
          containerWindow:setHeight(placement.height)
        end
        containerWindow:minimize()
      else
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
      end

      -- 2) Place it where the WHOLE container fits. Keep the saved panel only if it
      --    has room for the full height; otherwise addToPanels searches every panel
      --    and closes a backpack as a last resort - so the container is never pinned
      --    to a full panel and rendered cut off.
      if placement and placement.panel and m_interface.panelCanHost(containerWindow, placement.panel) then
        containerWindow:setParent(placement.panel)
        if placement.panel:hasChild(containerWindow) then
          containerWindow:getParent():moveChildToIndex(containerWindow, math.min(placement.index or 1, placement.panel:getChildCount()))
        end
      else
        if not m_interface.addToPanels(containerWindow, true) then
          return false
        end

        containerWindow:getParent():moveChildToIndex(containerWindow, #containerWindow:getParent():getChildren())
      end
    elseif container:hasPages() and containerWindow:getContentHeight() < 83 then
      containerWindow:setHeight(84)
    end


    containerWindow:setup()
    containerWindow:setColor(ContainerConfig.moveManualSort and "#C28400" or "#909090")

    if placement and placement.locked then
      scheduleEvent(function()
        if containerWindow then
          containerWindow:lock(true)
        end
      end, 100)
    end
    containerWindow.savedPlacement = nil
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
