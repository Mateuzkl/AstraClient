if not MinimapLoader then
  MinimapLoader = {
    loaded = false,
    otmmLoaded = false
  }
  MinimapLoader.__index = MinimapLoader
end

minimapWidget = nil
minimapWindow = nil
otmm = true
preloaded = false
fullmapView = false
oldZoom = nil
oldPos = nil

local minimapFile = '/minimap.otmm'
local minimapBackupFile = '/minimap.otmm.bak'

local function saveMap()
  if not MinimapLoader.loaded then
    return
  end

  g_minimap.saveOtmm(minimapFile)
  if minimapWidget then
    minimapWidget:save()
  end
end

local keybindMoveEast = KeyBind:getKeyBind("Minimap", "Scroll East")
local keybindMoveNorth = KeyBind:getKeyBind("Minimap", "Scroll North")
local keybindMoveSouth = KeyBind:getKeyBind("Minimap", "Scroll South")
local keybindMoveWest = KeyBind:getKeyBind("Minimap", "Scroll West")
local keybindFloorUp = KeyBind:getKeyBind("Minimap", "One Floor Up")
local keybindFloorDown = KeyBind:getKeyBind("Minimap", "One Floor Down")
local keybindZoomIn = KeyBind:getKeyBind("Minimap", "Zoom In")
local keybindZoomOut = KeyBind:getKeyBind("Minimap", "Zoom Out")
local keybindCenter = KeyBind:getKeyBind("Minimap", "Center")
local keybindShowMinimap = KeyBind:getKeyBind("Minimap", "Show")

local EXPANSION_SETTINGS_PREFIX = 'Minimap_Expansion_'
local EXPANDED_WIDTH = 356
local EXPANDED_HEIGHT = 240
local COLLAPSE_SNAP_MARGIN = 12
local minimapDownloadOperation = nil

local expansion = {
  parent = nil,
  index = nil,
  direction = nil,
  collapsedWidth = nil,
  fixedEdge = nil,
  side = nil,
  baseBoundary = nil,
  reservation = nil,
  verticalExpanded = false,
  collapsedHeight = nil,
  placeholders = {}
}

local expansionRestoreEvent = nil
local expansionRestoreRetries = 8
local expansionRestoreDelay = 250
-- Set while a saved "detached" layout has not been reapplied yet, so an automatic save
-- cannot overwrite the user's preference with the collapsed state we failed to leave.
local expansionRestorePending = false
local saveExpansionConfig
local fitVerticalExpansionToAvailable

local function isWidgetAlive(widget)
  return widget and not widget:isDestroyed()
end

local function getGameRootPanel()
  if m_interface and m_interface.getRootPanel then
    return m_interface.getRootPanel()
  end
  return nil
end

local function releaseExpansionSpace()
  if isWidgetAlive(expansion.reservation) and m_interface and
      m_interface.releaseMinimapExpansionSpace then
    m_interface.releaseMinimapExpansionSpace(expansion.reservation)
  end
  expansion.reservation = nil
end

local function getGameAreaBoundary(side)
  if not m_interface or not m_interface.getMapPanel then
    return nil
  end

  local mapPanel = m_interface.getMapPanel()
  if not isWidgetAlive(mapPanel) then
    return nil
  end

  if side == 'right' then
    return mapPanel:getX() + mapPanel:getWidth()
  end
  return mapPanel:getX()
end

local function updateExpansionSpace()
  if not expansion.parent or not minimapWindow or not expansion.baseBoundary or
      not m_interface or not m_interface.reserveMinimapExpansionSpace then
    return
  end

  local required
  if expansion.side == 'right' then
    required = expansion.baseBoundary - minimapWindow:getX()
  else
    required = minimapWindow:getX() + minimapWindow:getWidth() - expansion.baseBoundary
  end
  required = math.max(0, math.floor(required + 0.5))

  if required > 0 then
    expansion.reservation = m_interface.reserveMinimapExpansionSpace(
      expansion.side, required, expansion.reservation)
  else
    releaseExpansionSpace()
  end
end

local function isSidebarPanel(widget)
  return isWidgetAlive(widget) and widget:getClassName() == 'UIMiniWindowContainer'
end

local function getExpansionDirection(panel)
  local rootPanel = getGameRootPanel()
  if not rootPanel or not panel then
    return -1
  end

  local panelCenter = panel:getX() + panel:getWidth() / 2
  local rootCenter = rootPanel:getX() + rootPanel:getWidth() / 2
  return panelCenter >= rootCenter and -1 or 1
end

local function configureResizeBorder(direction)
  if not minimapWindow then
    return
  end

  local resizeBorder = minimapWindow:getChildById('resizeBorder')
  if not resizeBorder then
    return
  end

  direction = direction or expansion.direction or getExpansionDirection(minimapWindow:getParent())
  resizeBorder:breakAnchors()
  resizeBorder:addAnchor(AnchorTop, 'parent', AnchorTop)
  resizeBorder:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  if direction < 0 then
    resizeBorder:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  else
    resizeBorder:addAnchor(AnchorRight, 'parent', AnchorRight)
  end
end

local function updateExpandButton()
  if not minimapWindow then
    return
  end

  local button = minimapWindow:getChildById('expandMap')
  if not button then
    return
  end

  local expanded = expansion.parent ~= nil
  local direction = expansion.direction or getExpansionDirection(minimapWindow:getParent())
  local pointsLeft = (not expanded and direction < 0) or (expanded and direction > 0)
  button:setImageSource(pointsLeft and '/images/game/actionbar/arrow-left' or
    '/images/game/actionbar/arrow-right')
  button:setTooltip(tr(expanded and 'Collapse minimap' or 'Expand minimap'))
end

local function updateVerticalExpandButton()
  if not minimapWindow then
    return
  end

  local button = minimapWindow:getChildById('expandMapVertical')
  if not button then
    return
  end

  button:setImageSource(expansion.verticalExpanded and
    '/images/game/actionbar/arrow-up' or
    '/images/game/actionbar/arrow-down')
  button:setTooltip(tr(expansion.verticalExpanded and
    'Collapse minimap upward' or 'Expand minimap downward'))
end

-- The sidebar manager may save before the minimap receives onGameEnd. Let the placeholder
-- in the original panel stand in for the detached minimap so its sidebar and order are not
-- lost between sessions.
local function makePlaceholderStandInForMinimap(placeholder)
  placeholder.getType = function() return 'miniMap' end
  placeholder.isOpened = function() return minimapWindow:isOpened() end
  placeholder.isLocked = function() return minimapWindow:isLocked() end
  placeholder.minimized = minimapWindow.minimized
end

local function createPlaceholder(panel, index)
  if not isSidebarPanel(panel) then
    return nil
  end

  local current = expansion.placeholders[panel]
  if isWidgetAlive(current) then
    current:setHeight(minimapWindow:getHeight())
    if panel == expansion.parent then
      makePlaceholderStandInForMinimap(current)
    end
    return current
  end

  local placeholder = g_ui.createWidget('UIWidget')
  placeholder:setId('minimapExpansionPlaceholder_' .. panel:getId())
  placeholder:setHeight(minimapWindow:getHeight())
  placeholder:setWidth(panel:getWidth() - panel:getPaddingLeft() - panel:getPaddingRight())
  placeholder.save = true
  placeholder.close = function() end
  placeholder.saveParentIndex = function() end
  placeholder.saveParentPosition = function() end
  if panel == expansion.parent then
    makePlaceholderStandInForMinimap(placeholder)
  end

  index = math.max(1, math.min(index or 1, panel:getChildCount() + 1))
  panel:insertChild(index, placeholder)
  expansion.placeholders[panel] = placeholder
  return placeholder
end

local function destroyPlaceholder(panel)
  local placeholder = expansion.placeholders[panel]
  if isWidgetAlive(placeholder) then
    placeholder:destroy()
  end
  expansion.placeholders[panel] = nil
end

local function clearPlaceholders()
  local panels = {}
  for panel in pairs(expansion.placeholders) do
    table.insert(panels, panel)
  end
  for _, panel in ipairs(panels) do
    destroyPlaceholder(panel)
  end
end

local function syncExpansionPlaceholders()
  if not expansion.parent or not minimapWindow then
    return
  end

  createPlaceholder(expansion.parent, expansion.index)

  local sidebarGroup = expansion.parent:getParent()
  if not isWidgetAlive(sidebarGroup) then
    return
  end

  local minimapLeft = minimapWindow:getX()
  local minimapRight = minimapLeft + minimapWindow:getWidth()
  local coveredPanels = {[expansion.parent] = true}

  for _, panel in ipairs(sidebarGroup:getChildren()) do
    if panel ~= expansion.parent and isSidebarPanel(panel) and panel:isVisible() then
      local panelLeft = panel:getX()
      local panelRight = panelLeft + panel:getWidth()
      if minimapLeft < panelRight and minimapRight > panelLeft then
        createPlaceholder(panel, expansion.index)
        coveredPanels[panel] = true
      end
    end
  end

  local stalePanels = {}
  for panel in pairs(expansion.placeholders) do
    if not coveredPanels[panel] then
      table.insert(stalePanels, panel)
    end
  end
  for _, panel in ipairs(stalePanels) do
    destroyPlaceholder(panel)
  end
end

local function getPanelHeightLimit(panel, standIn)
  if not isSidebarPanel(panel) then
    return nil
  end

  local occupiedHeight = isWidgetAlive(standIn) and standIn:getHeight() or
    minimapWindow:getHeight()
  return occupiedHeight + panel:getEmptySpaceHeight()
end

local function getMaximumVerticalHeight()
  if not minimapWindow then
    return 0
  end

  local maximum = math.huge
  local rootPanel = getGameRootPanel()
  if isWidgetAlive(rootPanel) then
    maximum = math.min(maximum,
      rootPanel:getY() + rootPanel:getHeight() - minimapWindow:getY())
  end

  if expansion.parent then
    for panel, placeholder in pairs(expansion.placeholders) do
      local panelLimit = getPanelHeightLimit(panel, placeholder)
      if panelLimit then
        maximum = math.min(maximum, panelLimit)
      end
    end
  else
    local parent = minimapWindow:getParent()
    local panelLimit = getPanelHeightLimit(parent, minimapWindow)
    if panelLimit then
      maximum = math.min(maximum, panelLimit)
    end
  end

  if maximum == math.huge then
    maximum = minimapWindow:getHeight()
  end

  -- Never squeeze below the collapsed height: a 1px window would take the collapse
  -- button away with it and leave no way back.
  local floor = expansion.collapsedHeight or minimapWindow:getHeight()
  return math.max(math.floor(floor), math.floor(maximum))
end

fitVerticalExpansionToAvailable = function()
  if not expansion.verticalExpanded or not minimapWindow then
    return
  end

  local maximum = getMaximumVerticalHeight()
  if minimapWindow:getHeight() > maximum then
    minimapWindow:setHeight(maximum)
    if expansion.parent then
      syncExpansionPlaceholders()
    end
  end
end

local function detachMinimap()
  if expansion.parent or not minimapWindow or fullmapView then
    return expansion.parent ~= nil
  end

  local parent = minimapWindow:getParent()
  local rootPanel = getGameRootPanel()
  if not isSidebarPanel(parent) or not rootPanel then
    return false
  end

  releaseExpansionSpace()
  local position = minimapWindow:getPosition()
  local size = minimapWindow:getSize()
  expansion.parent = parent
  expansion.index = parent:getChildIndex(minimapWindow)
  expansion.direction = getExpansionDirection(parent)
  expansion.collapsedWidth = size.width
  expansion.fixedEdge = expansion.direction < 0 and position.x + size.width or position.x
  expansion.side = expansion.direction < 0 and 'right' or 'left'
  expansion.baseBoundary = getGameAreaBoundary(expansion.side)

  createPlaceholder(parent, expansion.index)
  minimapWindow:setParent(rootPanel)
  minimapWindow:setPosition(position)
  minimapWindow:setSize(size)
  minimapWindow:raise()
  configureResizeBorder(expansion.direction)
  updateExpandButton()
  return true
end

local function setExpandedWidth(width)
  if not expansion.parent or not minimapWindow then
    return
  end

  local rootPanel = getGameRootPanel()
  if not rootPanel then
    return
  end

  local rootLeft = rootPanel:getX()
  local rootRight = rootLeft + rootPanel:getWidth()
  local minimum = expansion.collapsedWidth or 120
  local maximum
  if expansion.direction < 0 then
    maximum = expansion.fixedEdge - rootLeft
  else
    maximum = rootRight - expansion.fixedEdge
  end

  width = math.max(minimum, math.min(width, maximum))
  if expansion.direction < 0 then
    minimapWindow:setX(expansion.fixedEdge - width)
  else
    minimapWindow:setX(expansion.fixedEdge)
  end
  minimapWindow:setWidth(width)
  updateExpansionSpace()
  syncExpansionPlaceholders()
  fitVerticalExpansionToAvailable()
end

local function restoreMinimap(saveConfig)
  if not expansion.parent or not minimapWindow then
    return false
  end

  local parent = expansion.parent
  local direction = expansion.direction
  local placeholder = expansion.placeholders[parent]
  local index = expansion.index or 1
  if isWidgetAlive(placeholder) then
    index = parent:getChildIndex(placeholder)
  end

  if isSidebarPanel(parent) then
    minimapWindow:setParent(parent)
    parent:moveChildToIndex(minimapWindow, math.max(1, math.min(index, parent:getChildCount())))
    minimapWindow:setWidth(parent:getWidth() - parent:getPaddingLeft() - parent:getPaddingRight())
  end

  clearPlaceholders()
  releaseExpansionSpace()
  expansion.parent = nil
  expansion.index = nil
  expansion.direction = nil
  expansion.collapsedWidth = nil
  expansion.fixedEdge = nil
  expansion.side = nil
  expansion.baseBoundary = nil

  configureResizeBorder(direction or getExpansionDirection(minimapWindow:getParent()))
  updateExpandButton()

  if saveConfig ~= false and saveExpansionConfig then
    saveExpansionConfig(false)
  end
  return true
end

saveExpansionConfig = function(detached)
  local player = g_game.getLocalPlayer()
  if not player or not minimapWindow then
    return
  end

  if detached == nil then
    detached = expansion.parent ~= nil
  end

  -- A restore that never managed to run must not be recorded as "the user collapsed it".
  if not detached and expansionRestorePending then
    return
  end

  local parent = detached and expansion.parent or minimapWindow:getParent()
  local settings = {
    detached = detached,
    width = minimapWindow:getWidth(),
    height = minimapWindow:getHeight(),
    verticalExpanded = expansion.verticalExpanded,
    collapsedHeight = expansion.collapsedHeight,
    parentId = parent and parent:getId() or nil,
    direction = expansion.direction
  }
  g_settings.setNode(EXPANSION_SETTINGS_PREFIX .. player:getName(), settings)
end

local function scheduleExpansionRestore(settings, retries)
  if expansionRestoreEvent then
    removeEvent(expansionRestoreEvent)
    expansionRestoreEvent = nil
  end

  if not settings then
    local player = g_game.getLocalPlayer()
    if not player then
      return
    end

    settings = g_settings.getNode(EXPANSION_SETTINGS_PREFIX .. player:getName())
    if not settings or (not settings.detached and not settings.verticalExpanded) then
      expansionRestorePending = false
      updateExpandButton()
      updateVerticalExpandButton()
      return
    end

    expansionRestorePending = true
    retries = expansionRestoreRetries
  end

  expansionRestoreEvent = scheduleEvent(function()
    expansionRestoreEvent = nil
    if not minimapWindow or not g_game.isOnline() then
      -- Nothing else will retry, so stop shielding the saved state or a later manual
      -- collapse could never be persisted.
      expansionRestorePending = false
      return
    end

    if not isSidebarPanel(minimapWindow:getParent()) and settings.parentId then
      local savedParent = rootWidget:recursiveGetChildById(settings.parentId)
      if isSidebarPanel(savedParent) then
        minimapWindow:setParent(savedParent)
      end
    end

    local needsHorizontalRestore = settings.detached == true
    local needsVerticalRestore = settings.verticalExpanded == true
    local parentReady = isSidebarPanel(minimapWindow:getParent())

    -- The sidebar is built by another module and may not be there yet; keep trying for a
    -- bounded number of ticks instead of silently dropping the saved layout.
    if not parentReady or (needsHorizontalRestore and not detachMinimap()) then
      if retries > 0 then
        scheduleExpansionRestore(settings, retries - 1)
      else
        expansionRestorePending = false
      end
      return
    end

    expansion.verticalExpanded = needsVerticalRestore
    if needsVerticalRestore then
      local collapsedHeight = tonumber(settings.collapsedHeight)
      if not collapsedHeight or collapsedHeight < 1 then
        collapsedHeight = math.min(minimapWindow:getHeight(),
          tonumber(settings.height) or minimapWindow:getHeight())
      end
      expansion.collapsedHeight = collapsedHeight
    else
      expansion.collapsedHeight = nil
    end

    if settings.height then
      local height = math.max(1, tonumber(settings.height) or minimapWindow:getHeight())
      if needsVerticalRestore then
        height = math.min(height, getMaximumVerticalHeight())
      end
      minimapWindow:setHeight(height)
    end
    if needsHorizontalRestore then
      setExpandedWidth(settings.width or EXPANDED_WIDTH)
    end
    fitVerticalExpansionToAvailable()
    updateVerticalExpandButton()
    expansionRestorePending = false
    saveExpansionConfig(needsHorizontalRestore)
  end, expansionRestoreDelay)
end

function toggleExpanded()
  if fullmapView or not minimapWindow then
    return
  end

  if expansion.parent then
    restoreMinimap(true)
    return
  end

  if detachMinimap() then
    local targetWidth = math.max(EXPANDED_WIDTH, (expansion.collapsedWidth or 178) * 2)
    setExpandedWidth(targetWidth)
    saveExpansionConfig(true)
  end
end

function toggleVerticalExpanded()
  if fullmapView or not minimapWindow then
    return
  end

  if expansion.verticalExpanded then
    local collapsedHeight = expansion.collapsedHeight or minimapWindow:getHeight()
    expansion.verticalExpanded = false
    expansion.collapsedHeight = nil
    minimapWindow:setHeight(math.max(1, collapsedHeight))
  else
    local collapsedHeight = minimapWindow:getHeight()
    local targetHeight = math.max(EXPANDED_HEIGHT, collapsedHeight * 2)
    targetHeight = math.min(targetHeight, getMaximumVerticalHeight())
    if targetHeight <= collapsedHeight then
      updateVerticalExpandButton()
      return
    end

    expansion.collapsedHeight = collapsedHeight
    expansion.verticalExpanded = true
    minimapWindow:setHeight(targetHeight)
  end

  if expansion.parent then
    syncExpansionPlaceholders()
  end
  updateVerticalExpandButton()
  saveExpansionConfig(expansion.parent ~= nil)
end

function isExpanded()
  return expansion.parent ~= nil
end

function isVerticalExpanded()
  return expansion.verticalExpanded
end

function toggleFullMap()
  if not minimapWidget or not minimapWindow then
    return
  end

  if not fullmapView then
    -- Without a root panel the widget would be reparented to nil while the window is
    -- already hidden, leaving no minimap at all and no way back.
    local rootPanel = getGameRootPanel()
    if not rootPanel then
      return
    end

    oldZoom = minimapWidget:getZoom()
    oldPos = minimapWidget:getCameraPosition()
    fullmapView = true
    minimapWindow:hide()
    minimapWidget:setParent(rootPanel)
    minimapWidget:fill('parent')
    minimapWidget:setAlternativeWidgetsVisible(true)
  else
    fullmapView = false
    minimapWidget:setParent(minimapWindow)
    minimapWidget:fill('parent')
    minimapWindow:show()
    minimapWidget:setAlternativeWidgetsVisible(false)
    if oldZoom then minimapWidget:setZoom(oldZoom) end
    if oldPos then minimapWidget:setCameraPosition(oldPos) end
  end
end

local function getDownloadMapButton()
  if not minimapWindow or minimapWindow:isDestroyed() then
    return nil
  end
  return minimapWindow:getChildById('downloadMapButton')
end

local function setDownloadMapButtonState(downloading)
  local button = getDownloadMapButton()
  if not button or button:isDestroyed() then
    return
  end

  button:setEnabled(not downloading)
  button:setText(tr(downloading and 'Downloading...' or 'Download Map'))
end

local function displayMapDownloadFailure(details)
  g_logger.error('[game_minimap] Failed to download full map: ' .. tostring(details))
  if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
    modules.game_textmessage.displayFailureMessage(tr('Failed to download the map.'))
  end
end

-- Snapshots the installed map so a bad OTMM can be rolled back. Returns false when the
-- snapshot failed, in which case the caller must leave the current map untouched.
-- A nil snapshot means there was no map installed yet.
local function backupMinimapFile()
  -- A snapshot left behind by an interrupted run must not be mistaken for this one's.
  if g_resources.fileExists(minimapBackupFile) then
    g_resources.deleteFile(minimapBackupFile)
  end

  if not g_resources.fileExists(minimapFile) then
    return true, nil
  end

  if g_resources.copyFile then
    if not g_resources.copyFile(minimapFile, minimapBackupFile) then
      return false, nil
    end
    return true, { file = minimapBackupFile }
  end

  -- Binary without the native copy: fall back to holding the old map in memory.
  local ok, contents = pcall(g_resources.readFileContents, minimapFile)
  if not ok or type(contents) ~= 'string' then
    return false, nil
  end
  return true, { contents = contents }
end

local function rollbackMinimapFile(backup)
  if not backup then
    g_resources.deleteFile(minimapFile)
    return false
  end

  if backup.file then
    return g_resources.copyFile(backup.file, minimapFile) and true or false
  end
  return g_resources.writeFileContents(minimapFile, backup.contents) and true or false
end

local function discardMinimapBackup(backup)
  if backup and backup.file then
    g_resources.deleteFile(backup.file)
  end
end

function downloadFullMap()
  local url = Services and Services.minimap or nil
  if type(url) ~= 'string' or url == '' then
    displayMapDownloadFailure('Services.minimap URL is not configured.')
    return
  end

  if minimapDownloadOperation then
    return
  end

  setDownloadMapButtonState(true)
  -- HTTP.download may run the callback synchronously on an immediate failure, before it
  -- ever returns a handle. Remember that so the assignment below cannot resurrect an
  -- already finished operation and block every later download.
  local finished = false
  local ok, operation = pcall(function()
    return HTTP.download(url, 'minimap.otmm', function(path, checksum, err)
      finished = true
      minimapDownloadOperation = nil
      setDownloadMapButtonState(false)

      if err then
        displayMapDownloadFailure(err)
        return
      end

      if not path or path == '' then
        displayMapDownloadFailure('the HTTP download returned no file path')
        return
      end

      local downloadPath = path:sub(1, 11) == '/downloads/' and path or '/downloads/' .. path
      local readOk, content = pcall(g_resources.readFileContents, downloadPath)
      if not readOk or type(content) ~= 'string' or #content < 22 then
        displayMapDownloadFailure(readOk and 'the downloaded file is empty' or content)
        return
      end

      if content:sub(1, 4) ~= 'OTMM' or content:byte(7) ~= 1 or content:byte(8) ~= 0 then
        displayMapDownloadFailure('the downloaded file is not a supported OTMM 1.0 map')
        return
      end

      local backupOk, backup = backupMinimapFile()
      if not backupOk then
        displayMapDownloadFailure('unable to back up ' .. minimapFile .. '; the current map was kept')
        return
      end

      if not g_resources.writeFileContents(minimapFile, content) then
        discardMinimapBackup(backup)
        displayMapDownloadFailure('unable to write ' .. minimapFile)
        return
      end

      g_minimap.clean()
      if not g_minimap.loadOtmm(minimapFile) then
        local restored = rollbackMinimapFile(backup)
        discardMinimapBackup(backup)

        g_minimap.clean()
        if restored then
          g_minimap.loadOtmm(minimapFile)
        else
          -- Nothing usable on disk and nothing in memory. Leaving loaded set would let
          -- saveMap() write the emptied minimap over whatever survived.
          MinimapLoader.loaded = false
          MinimapLoader.otmmLoaded = false
        end
        displayMapDownloadFailure('the downloaded OTMM file could not be loaded')
        return
      end

      discardMinimapBackup(backup)
      MinimapLoader.otmmLoaded = true
      MinimapLoader.loaded = true
      if minimapWidget and not minimapWidget:isDestroyed() then
        minimapWidget:load()
        local player = g_game.getLocalPlayer()
        if player then
          local position = player:getPosition()
          minimapWidget:setCameraPosition(position)
          minimapWidget:setCrossPosition(position)
        end
      end

      g_logger.info('[game_minimap] Full map downloaded and loaded successfully.')
      if modules.game_textmessage and modules.game_textmessage.displayGameMessage then
        modules.game_textmessage.displayGameMessage(tr('Map downloaded successfully.'))
      end
    end)
  end)

  if not ok then
    minimapDownloadOperation = nil
    setDownloadMapButtonState(false)
    displayMapDownloadFailure(operation)
    return
  end

  if not finished then
    minimapDownloadOperation = operation
  end
end

local function syncSideButton(state, retries)
  retries = retries or 8
  if modules.game_sidebuttons and modules.game_sidebuttons.setButtonVisible then
    modules.game_sidebuttons.setButtonVisible("lenshelpFunction", state)
    return
  end

  if retries > 0 then
    scheduleEvent(function() syncSideButton(state, retries - 1) end, 250)
  end
end

local function attachMinimapToPanel()
  if not minimapWindow then
    return false
  end

  if minimapWindow:getParent() then
    return true
  end

  if m_interface and m_interface.getRightPanel then
    minimapWindow:setParent(m_interface.getRightPanel())
    return true
  end

  return false
end

function init()
  minimapWindow = g_ui.loadUI('minimap', m_interface.getRightPanel())
  -- The right-hand controls are pinned to the top so vertical expansion only adds map
  -- below them. Compass (46) plus the floor indicator (67) plus the 19px of window
  -- chrome need 132; below that the cyclopedia button falls out of the window.
  minimapWindow:setHeight(140)

  if not minimapWindow.forceOpen then
    minimapButton = modules.client_topmenu.addRightGameToggleButton('minimapButton',
      tr('Minimap') .. ' (Ctrl+M)', '/images/topbuttons/minimap', toggle)
    minimapButton:setOn(true)
  end
  minimapWidget = minimapWindow:recursiveGetChildById('minimap')
  local downloadMapButton = getDownloadMapButton()
  if downloadMapButton then
    local hasDownloadUrl = Services and type(Services.minimap) == 'string' and Services.minimap ~= ''
    downloadMapButton:setVisible(hasDownloadUrl)
  end

  local gameRootPanel = m_interface.getRootPanel()
  keybindMoveEast:active(gameRootPanel)
  keybindMoveNorth:active(gameRootPanel)
  keybindMoveSouth:active(gameRootPanel)
  keybindMoveWest:active(gameRootPanel)
  keybindFloorUp:active(gameRootPanel)
  keybindFloorDown:active(gameRootPanel)
  keybindZoomIn:active(gameRootPanel)
  keybindZoomOut:active(gameRootPanel)
  keybindCenter:active(gameRootPanel)
  keybindShowMinimap:active(gameRootPanel)


  minimapWindow:setup()
  open()
  if minimapWindow.iconResize then
    minimapWindow:getChildById('iconResize'):hide()
  end

  -- Expand from the edge that faces the game area. The Astra minimap may be
  -- placed on either side, unlike the original implementation.
  local resizeBorder = minimapWindow:getChildById('resizeBorder')
  if resizeBorder then
    resizeBorder.onMousePress = function(self, mousePos, mouseButton)
      if not expansion.parent and not detachMinimap() then
        return false
      end

      local position = minimapWindow:getPosition()
      expansion.fixedEdge = expansion.direction < 0 and
        position.x + minimapWindow:getWidth() or position.x
      return true
    end

    resizeBorder.onMouseMove = function(self, mousePos, mouseMoved)
      if not self:isPressed() or not expansion.parent then
        return false
      end

      if expansion.direction < 0 then
        setExpandedWidth(expansion.fixedEdge - mousePos.x)
      else
        setExpandedWidth(mousePos.x - expansion.fixedEdge)
      end
      return true
    end

    local originalRelease = resizeBorder.onMouseRelease
    resizeBorder.onMouseRelease = function(self, mousePos, mouseButton)
      if originalRelease then originalRelease(self, mousePos, mouseButton) end
      if not expansion.parent then
        return
      end

      local collapseAt = (expansion.collapsedWidth or 178) + COLLAPSE_SNAP_MARGIN
      if minimapWindow:getWidth() <= collapseAt then
        restoreMinimap(true)
      else
        syncExpansionPlaceholders()
        saveExpansionConfig(true)
      end
    end

    resizeBorder.onDoubleClick = function()
      toggleExpanded()
      return true
    end
  end

  configureResizeBorder(getExpansionDirection(minimapWindow:getParent()))
  updateExpandButton()
  updateVerticalExpandButton()
  g_keyboard.bindKeyDown('Ctrl+Shift+M', toggleFullMap)

  local originalHeightChange = minimapWindow.onHeightChange
  minimapWindow.onHeightChange = function(self, height)
    if originalHeightChange then originalHeightChange(self, height) end
    if expansion.parent then
      syncExpansionPlaceholders()
    end
  end

  local floorPosition = minimapWindow:getChildById('floorPosition')
  if floorPosition then
    floorPosition.onMouseWheel = onMouseWheel
  end

  -- Camera changes also happen through Ctrl+wheel, floor controls and reset(), not only
  -- through LocalPlayer.onPositionChange. Preserve UIMinimap's cross update and refresh
  -- the shared floor indicator from the same camera callback.
  local originalCameraPositionChange = minimapWidget.onCameraPositionChange
  minimapWidget.onCameraPositionChange = function(self, cameraPosition, oldPosition)
    if originalCameraPositionChange then
      originalCameraPositionChange(self, cameraPosition, oldPosition)
    end
    if cameraPosition then
      updateFloorImage(cameraPosition.z)
    end
  end
  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
    onPartyDataUpdate = Party.Update,
    onPartyDataClear = Party.Reset,

    onServerTime = onServerTime
  })

  connect(LocalPlayer, {
    onPositionChange = updateCameraPosition
  })

  if g_game.isOnline() then
    online()
  end
end

function terminate()
  if minimapDownloadOperation then
    HTTP.cancel(minimapDownloadOperation)
    minimapDownloadOperation = nil
  end

  if expansionRestoreEvent then
    removeEvent(expansionRestoreEvent)
    expansionRestoreEvent = nil
  end

  if g_game.isOnline() then
    saveExpansionConfig()
    saveMap()
  end

  -- Exit full map view before cleanup
  if fullmapView then
    fullmapView = false
    minimapWidget:setParent(minimapWindow)
    minimapWidget:fill('parent')
    minimapWindow:show()
    minimapWidget:setAlternativeWidgetsVisible(false)
  end

  restoreMinimap(false)

  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
    onPartyDataUpdate = Party.Update,
    onPartyDataClear = Party.Reset,

    onServerTime = onServerTime
  })

  disconnect(LocalPlayer, {
    onPositionChange = updateCameraPosition
  })

  keybindMoveEast:deactive()
  keybindMoveNorth:deactive()
  keybindMoveSouth:deactive()
  keybindMoveWest:deactive()
  keybindFloorUp:deactive()
  keybindFloorDown:deactive()
  keybindZoomIn:deactive()
  keybindZoomOut:deactive()
  keybindShowMinimap:deactive()

  g_keyboard.unbindKeyDown('Ctrl+Shift+M')

  minimapWindow:destroy()
  if minimapButton then
    minimapButton:destroy()
  end
end

function toggle()
  if not minimapButton then return end
  if fullmapView then
    toggleFullMap()
  end
  local sideButton = modules.game_sidebuttons.getButtonById("lenshelpFunction")
  if minimapWindow:isVisible() then
    -- Collapse for the close, but keep the persisted expansion state: closing the minimap
    -- is not the user asking for it to come back collapsed next session.
    restoreMinimap(false)
    minimapWindow:close()
    minimapButton:setOn(false)
    syncSideButton(false)
    if sideButton then
      sideButton.highlight:setVisible(true)
    end
  else
    if attachMinimapToPanel() then
      minimapWindow:open()
      if sideButton then
        sideButton.highlight:setVisible(false)
      end
    end
    minimapButton:setOn(true)
    syncSideButton(true)
  end
end

function open()
  if not minimapWindow then
    return
  end

  attachMinimapToPanel()
  minimapWindow:open()

  if minimapButton then
    minimapButton:setOn(true)
  end

  syncSideButton(true)
end

function isOpen()
  return minimapWindow and minimapWindow:isVisible()
end

function preload()
  loadMap(false)
  preloaded = true
end

function online()
  local benchmark = g_clock.millis()
  if not MinimapLoader.loaded then
    loadMap(not preloaded)
  end
  updateCameraPosition({x = 0, y = 0, z = 0}, {x = 0, y = 0, z = 1})
  if minimapWidget then
    -- The camera has no position until the first setCameraPosition, which does not
    -- happen when the player has no position yet at this point in the login.
    local cameraPosition = minimapWidget:getCameraPosition()
    if cameraPosition then
      updateFloorImage(cameraPosition.z)
    end
  end
  scheduleExpansionRestore()

  if minimapwidget then
    Party.Reset()
  end

  consoleln("Minimap loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function offline()
  if not minimapWidget then
    return
  end

  if expansionRestoreEvent then
    removeEvent(expansionRestoreEvent)
    expansionRestoreEvent = nil
  end

  saveExpansionConfig()
  restoreMinimap(false)
  saveMap()

  minimapWidget:resetParty()
  minimapWidget:clearWaypoints()
  minimapWidget:clearRoutePath()
end

function loadMap(clean)
  if clean then
    g_minimap.clean()
  end

  if not MinimapLoader.otmmLoaded then
    if g_resources.fileExists(minimapFile) then
      g_minimap.loadOtmm(minimapFile)
    end
    MinimapLoader.otmmLoaded = true
  end

  -- LoadTibiaMap()
  if minimapWidget and minimapWidget.load then
    minimapWidget:load()
  end
  attachMinimapToPanel()
  MinimapLoader.loaded = true
end

function updateCameraPosition(newPosition, lastPosition)
  local player = g_game.getLocalPlayer()
  if not player then return end
  local pos = player:getPosition()
  if not pos then return end
  if not minimapWidget:isDragging() then
    if not fullmapView then
      minimapWidget:setCameraPosition(player:getPosition())
    end
    minimapWidget:setCrossPosition(player:getPosition())
  end

  if oldPos and newPosition.z ~= oldPos.z then
    Party.UpdateFloor(newPosition.z)
  end

  if #Party.Members >= 1 then
    Party.SendUpdate(newPosition)
  end

end

function updateFloorImage(posZ)
  if not minimapWindow or minimapWindow:isDestroyed() then
    return
  end

  local floorPosition = minimapWindow:getChildById('floorPosition')
  if not floorPosition or floorPosition:isDestroyed() then
    return
  end

  local floorZ = math.max(0, math.min(15, tonumber(posZ) or 7))
  floorPosition:setImageClip((floorZ * 14) .. ' 0 14 67')
end

function onMouseWheel(widget, mousePos, direction)
  if direction == MouseWheelUp then
    minimapWindow:recursiveGetChildById('minimap'):floorUp(1)
  elseif direction == MouseWheelDown then
    minimapWindow:recursiveGetChildById('minimap'):floorDown(1)
  end

  return true
end

function zoom(bool)
  if bool then
    minimapWindow:recursiveGetChildById('minimap'):zoomIn()
  else
    minimapWindow:recursiveGetChildById('minimap'):zoomOut()
  end
end

function floor(bool)
  if bool then
    minimapWindow:recursiveGetChildById('minimap'):floorUp(1)
  else
    minimapWindow:recursiveGetChildById('minimap'):floorDown(1)
  end

end

function center()
  minimapWindow:recursiveGetChildById('minimap'):reset()
end

function checkXByHour(x)
  local y0 = 62
  local incremento = y0 / 12
  local result = math.floor(y0 + (x * incremento))
  if result > 124 then
    result = result - 124
  end

  return result
end

function LoadTibiaMap()
  g_minimap.clean()

  -- Função para verificar se um arquivo deve ser carregado
  local function shouldLoadFile(file)
    return not file:lower():find('waypointcost') and file:match(".*%.png$")
  end

  -- Carregar as imagens de forma assíncrona
  local function asyncLoadImage(file)
    local fileNoExt = file:sub(1, -5)
    local pos = fileNoExt:split("_")
    if #pos >= 3 then
      local x, y, z = tonumber(pos[#pos - 2]), tonumber(pos[#pos - 1]), tonumber(pos[#pos])
      if x and y and z then
        g_minimap.loadImage('/minimap/' .. file, { x = x, y = y, z = z }, 1.0)
      end
    end
  end

  -- Caching para imagens já carregadas
  local loadedImages = {}

  -- Função para carregar imagens visíveis
  local function loadVisibleImages()
    local files = g_resources.listDirectoryFiles("/minimap", false, true)
    for _, file in ipairs(files) do
      if shouldLoadFile(file) and not loadedImages[file] then
        asyncLoadImage(file)
        loadedImages[file] = true
      end
    end
  end

  -- Chamada inicial para carregar imagens visíveis
  loadVisibleImages()
end

function move(panel, height, index)
  if not panel then
    return
  end

  local wasExpanded = expansion.parent ~= nil
  local expandedWidth = wasExpanded and minimapWindow:getWidth() or nil
  local verticalHeight = expansion.verticalExpanded and minimapWindow:getHeight() or nil
  if wasExpanded then
    restoreMinimap(false)
  end

  local function reparentToPanel()
    minimapWindow:setParent(panel)
    if verticalHeight or height then
      minimapWindow:setHeight(verticalHeight or height)
    end
    configureResizeBorder(getExpansionDirection(panel))
    updateExpandButton()
    updateVerticalExpandButton()
    if wasExpanded and detachMinimap() then
      setExpandedWidth(expandedWidth)
    else
      fitVerticalExpansionToAvailable()
    end
  end

  -- The horizontal panels are still being laid out at this point, so they need a frame
  -- before the minimap can measure itself against them.
  if string.find(panel:getId(), "horizontal") then
    addEvent(reparentToPanel)
  else
    reparentToPanel()
  end

  minimapWindow:open()
  syncSideButton(true)

  return minimapWindow
end

function onPlayerUnload()
  local index = -1
  local parent = expansion.parent or minimapWindow:getParent()
  if parent then
    local placeholder = expansion.placeholders[parent]
    index = placeholder and parent:getChildIndex(placeholder) or parent:getChildIndex(minimapWindow)
    modules.game_sidebars.registerMinimapConfig({contentHeight = minimapWindow:getHeight(), index = index})
  end
end

function loadMarks()
  local file = '/data/json/markers.json'
  if g_resources.fileExists(file) then
    local status, result = pcall(function()
      return json.decode(g_resources.readFileContents(file))
    end)

    if not status then
      return g_logger.error("Error while reading marks file. Details: " .. result)
    end

    local iconConfig = {
      ["checkmark"] = 1,
      ["?"] = 2,
      ["!"] = 3,
      ["star"] = 4,
      ["crossmark"] = 5,
      ["cross"] = 7,
      ["mouth"] = 8,
      ["spear"] = 9,
      ["sword"] = 10,
      ["flag"] = 11,
      ["lock"] = 13,
      ["bag"] = 14,
      ["skull"] = 15,
      ["$"] = 16,
      ["red up"] = 17,
      ["red down"] = 19,
      ["red right"] = 20,
      ["red left"] = 21,
      ["up"] = 22,
      ["down"] = 23,
    }

    local function customSort(a, b)
      -- Se ambos os z estão entre 0 e 7, ou ambos estão entre 8 e 14, compara diretamente
      if (a.z >= 0 and a.z <= 7 and b.z >= 0 and b.z <= 7) or (a.z >= 8 and a.z <= 14 and b.z >= 8 and b.z <= 14) then
          return a.z > b.z -- Inverte a comparação para obter 7 a 0 primeiro
      elseif a.z >= 0 and a.z <= 7 then
          return true -- A vem antes se estiver no intervalo 0 a 7, independente do B
      elseif b.z >= 0 and b.z <= 7 then
          return false -- B vem antes se A não estiver no intervalo 0 a 7 e B estiver
      else
          return a.z < b.z -- Caso contrário, compara normalmente para ordenar 8 a 14
      end
  end

  table.sort(result, customSort)

    for i, info in pairs(result) do
      scheduleEvent(
        function()
          if iconConfig[info.icon] and minimapWidget and minimapWidget:isVisible() then
            minimapWidget:addFlag({x = info.x, y = info.y, z = info.z}, '/data/images/game/minimap/icon/'..iconConfig[info.icon], info.description, true)
          end
        end, i*60)
    end
  end

  g_settings.set('seeMapMark', true)
end

function onClose()
  -- Same as toggle(): collapse the widget without persisting a collapsed preference.
  restoreMinimap(false)
end

function onServerTime(minutes, seconds)
  if not minimapWindow then
    return
  end
  minimapWindow.centerMap:setImageClip(checkXByHour(minutes) .. " 0 31 31")
end

function setPath(coordinates)
  if not minimapWidget then
    return
  end

  if table.size(coordinates) == 0 then
      return
  end

  minimapWidget:clearWaypoints()
  minimapWidget:setDrawWaypoints(true)
  for floor, coordinate in pairs(coordinates) do
      if tonumber(floor) then
          minimapWidget:makeWaypoints(coordinate, tonumber(floor))
      end
  end
end

function clearPath()
  minimapWidget:clearWaypoints()
  minimapWidget:setDrawWaypoints(false)
end

function setRoutePath(coordinates)
  if not minimapWidget then
    return
  end

  if table.size(coordinates) == 0 then
      return
  end

  minimapWidget:clearRoutePath()
  minimapWidget:setDrawWaypoints(true)
  for floor, coordinate in pairs(coordinates) do
      if tonumber(floor) then
          minimapWidget:makeRouth(coordinate, tonumber(floor))
      end
  end
end

function clearRoutePath()
  minimapWidget:clearRoutePath()
  minimapWidget:setDrawWaypoints(false)
end
