if not MinimapLoader then
  MinimapLoader = {
    loaded = false
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
  minimapWindow:setHeight(120)

  if not minimapWindow.forceOpen then
    minimapButton = modules.client_topmenu.addRightGameToggleButton('minimapButton',
      tr('Minimap') .. ' (Ctrl+M)', '/images/topbuttons/minimap', toggle)
    minimapButton:setOn(true)
  end
  minimapWidget = minimapWindow:recursiveGetChildById('minimap')

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

  -- Resize border detach/expand support
  local resizeBorder = minimapWindow:getChildById('resizeBorder')
  if resizeBorder then
    resizeBorder.onMousePress = function(self, mousePos, mouseButton)
      local parent = minimapWindow:getParent()
      if parent and parent:getClassName() == 'UIMiniWindowContainer' then
        local pos = minimapWindow:getPosition()
        local size = minimapWindow:getSize()
        local placeholder = g_ui.createWidget('UIWidget')
        placeholder:setHeight(size.height)
        placeholder:setWidth(size.width)
        placeholder:setId('minimapPlaceholder')
        placeholder.save = true
        local index = parent:getChildIndex(minimapWindow)
        parent:insertChild(index, placeholder)
        minimapWindow.placeholder = placeholder
        minimapWindow:setParent(m_interface.getRootPanel())
        minimapWindow:setPosition(pos)
        minimapWindow:setSize(size)
      end
    end

    local origRelease = resizeBorder.onMouseRelease
    resizeBorder.onMouseRelease = function(self, mousePos, mouseButton)
      if origRelease then origRelease(self, mousePos, mouseButton) end
      if minimapWindow:getWidth() < 180 then
        if minimapWindow.placeholder then
          local parent = minimapWindow.placeholder:getParent()
          minimapWindow:setParent(parent)
          local index = parent:getChildIndex(minimapWindow.placeholder)
          parent:insertChild(index, minimapWindow)
          minimapWindow.placeholder:destroy()
          minimapWindow.placeholder = nil
          minimapWindow:setWidth(parent:getWidth() - parent:getPaddingLeft() - parent:getPaddingRight())
        end
      end
    end
  end

  -- Full map view toggle (Ctrl+Shift+M)
  g_keyboard.bindKeyDown('Ctrl+Shift+M', function()
    if not fullmapView then
      fullmapView = true
      minimapWindow:hide()
      minimapWidget:setParent(m_interface.getRootPanel())
      minimapWidget:fill('parent')
      minimapWidget:setAlternativeWidgetsVisible(true)
      oldZoom = minimapWidget:getZoom()
      oldPos = minimapWidget:getCameraPosition()
    else
      fullmapView = false
      minimapWidget:setParent(minimapWindow:getChildById('contentsPanel'))
      minimapWidget:fill('parent')
      minimapWindow:show()
      minimapWidget:setAlternativeWidgetsVisible(false)
      if oldZoom then minimapWidget:setZoom(oldZoom) end
      if oldPos then minimapWidget:setCameraPosition(oldPos) end
    end
  end)

  minimapWindow.floorPosition.onMouseWheel = onMouseWheel
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
  -- Exit full map view before cleanup
  if fullmapView then
    fullmapView = false
    minimapWidget:setParent(minimapWindow:getChildById('contentsPanel'))
    minimapWidget:fill('parent')
    minimapWindow:show()
    minimapWidget:setAlternativeWidgetsVisible(false)
  end

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
  local sideButton = modules.game_sidebuttons.getButtonById("lenshelpFunction")
  if minimapWindow:isVisible() then
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

  if minimapwidget then
    Party.Reset()
  end

  consoleln("Minimap loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function offline()
  if not minimapWidget then
    return
  end

  minimapWidget:resetParty()
  minimapWidget:clearWaypoints()
  minimapWidget:clearRoutePath()

  minimapWidget:save()
end

function loadMap(clean)
  if clean and g_minimap.load then
    g_minimap.load(clean)
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

  if newPosition.z ~= lastPosition.z then
    minimapWindow.floorPosition:setImageClip(player:getPosition().z * 14  .." 0 14 67")
  end
end

function updateFloorImage(posZ)
  minimapWindow.floorPosition:setImageClip((posZ) * 14  .." 0 14 67")
end

function onMouseWheel(widget, mousePos, direction)
  if direction == MouseWheelUp then
    minimapWindow:recursiveGetChildById('minimap'):floorUp(1)
  elseif direction == MouseWheelDown then
    minimapWindow:recursiveGetChildById('minimap'):floorDown(1)
  end

  updateFloorImage(minimapWindow:recursiveGetChildById('minimap'):getCameraPosition().z)
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

  updateFloorImage(minimapWindow:recursiveGetChildById('minimap'):getCameraPosition().z)
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

  if string.find(panel:getId(), "horizontal") then
    addEvent(function()
      minimapWindow:setParent(panel)
      if height then
        minimapWindow:setHeight(height)
      end
    end)
  else
    minimapWindow:setParent(panel)
    if height then
      minimapWindow:setHeight(height)
    end
  end

  minimapWindow:open()
  syncSideButton(true)

  return minimapWindow
end

function onPlayerUnload()
  local index = -1
  local parent = minimapWindow:getParent()
  if parent then
    index = parent:getChildIndex(minimapWindow)
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
