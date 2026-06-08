--[[
  UI Modal Overlay - alternativa ao lock() de janela.

  Cria um overlay transparente para bloquear interacao com widgets abaixo.

  Uso:
    UIModalOverlay.show(myWindow)
    UIModalOverlay.hide(myWindow)
    UIModalOverlay.destroy(myWindow)
]]

if not UIModalOverlay then
  UIModalOverlay = {
    activeOverlays = {},
    registeredWindows = {}
  }
end

local function getOverlayKey(window, customId)
  local windowId = window and window:getId() or "global"
  local id = customId or "default"
  return windowId .. "_" .. id
end

function UIModalOverlay.show(window, customId, options)
  options = options or {}
  local key = getOverlayKey(window, customId)

  if UIModalOverlay.activeOverlays[key] then
    local overlay = UIModalOverlay.activeOverlays[key]
    overlay:raise()
    overlay:show()
    if window then
      window:raise()
    end
    return overlay
  end

  local parent = nil
  if window then
    parent = window:getParent()
  end
  if not parent then
    parent = g_ui.getRootWidget()
  end
  if not parent then return nil end

  local overlay = g_ui.createWidget('UIWidget', parent)
  if not overlay then return nil end

  overlay:setId('modalOverlay_' .. key)
  overlay:fill('parent')
  overlay:setPhantom(false)
  overlay:setFocusable(false)
  overlay:setBackgroundColor(options.backgroundColor or '#00000001')

  overlay.onMousePress = function(widget, mousePos, mouseButton)
    if options.onClick then
      options.onClick(widget, mousePos, mouseButton)
    end
    return true
  end

  overlay.onMouseRelease = function()
    return true
  end

  UIModalOverlay.activeOverlays[key] = overlay

  overlay:raise()
  overlay:show()
  if window then
    window:raise()
  end

  return overlay
end

function UIModalOverlay.hide(window, customId)
  local key = getOverlayKey(window, customId)
  local overlay = UIModalOverlay.activeOverlays[key]

  if overlay then
    overlay:hide()
  end
end

function UIModalOverlay.destroy(window, customId)
  local key = getOverlayKey(window, customId)
  local overlay = UIModalOverlay.activeOverlays[key]

  if overlay then
    overlay:destroy()
    UIModalOverlay.activeOverlays[key] = nil
  end
end

function UIModalOverlay.destroyAll()
  for _, overlay in pairs(UIModalOverlay.activeOverlays) do
    if overlay and overlay.destroy then
      overlay:destroy()
    end
  end
  UIModalOverlay.activeOverlays = {}
end

function UIModalOverlay.isActive(window, customId)
  local key = getOverlayKey(window, customId)
  local overlay = UIModalOverlay.activeOverlays[key]
  return overlay and overlay:isVisible()
end

function UIModalOverlay.register(window, options)
  if not window then return false end

  local uniqueKey = tostring(window)
  if UIModalOverlay.registeredWindows[uniqueKey] then
    return true
  end

  local originalShow = window.show
  local originalHide = window.hide
  local originalDestroy = window.destroy

  window.show = function(self, ...)
    if originalShow then
      originalShow(self, ...)
    end
    if self:isVisible() then
      UIModalOverlay.show(self, nil, options)
    end
  end

  window.hide = function(self, ...)
    UIModalOverlay.hide(self)
    if originalHide then
      originalHide(self, ...)
    end
  end

  window.destroy = function(self, ...)
    UIModalOverlay.unregister(self)
    UIModalOverlay.destroy(self)
    if originalDestroy then
      originalDestroy(self, ...)
    end
  end

  UIModalOverlay.registeredWindows[uniqueKey] = {
    window = window,
    originalShow = originalShow,
    originalHide = originalHide,
    originalDestroy = originalDestroy,
    options = options
  }

  return true
end

function UIModalOverlay.unregister(window)
  if not window then return end

  local uniqueKey = tostring(window)
  local registration = UIModalOverlay.registeredWindows[uniqueKey]

  if registration then
    window.show = registration.originalShow
    window.hide = registration.originalHide
    window.destroy = registration.originalDestroy
    UIModalOverlay.registeredWindows[uniqueKey] = nil
  end
end

function UIModalOverlay.hasVisibleOverlay()
  for _, overlay in pairs(UIModalOverlay.activeOverlays) do
    if overlay and overlay:isVisible() then
      return true
    end
  end
  return false
end

function UIModalOverlay.isRegistered(window)
  if not window then return false end
  local uniqueKey = tostring(window)
  return UIModalOverlay.registeredWindows[uniqueKey] ~= nil
end
