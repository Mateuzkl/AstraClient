-- Run from the repository root with LuaJIT. Uses the real option/controller code.
local noop = function() end
local env = setmetatable({}, { __index = _G })
local values, nodes = {}, { Minimap = { zoom = -1, spriteZoom = 2 } }
local saves = 0
env.DEFAULT_LAYOUT = ''
env.g_settings = {
  setDefault = function(key, value) if values[key] == nil then values[key] = value end end,
  getBoolean = function(key) return values[key] == true end,
  getNode = function(key) return nodes[key] end,
  setNode = function(key, value) nodes[key] = value end,
  set = function(key, value) values[key] = value end,
  save = function() saves = saves + 1 end
}
env.g_logger = { info = noop, warning = noop }
env.tr = function(text) return text end
env.scheduleEvent = function(callback) return callback end
env.removeEvent = noop
env.KeyBind = { getKeyBind = function() return {} end }
env.modules = {}
env.UIMinimap = { setSpriteMode = noop }
env.m_interface = { getRootPanel = function() return {} end }
local function load(path)
  return setfenv(assert(loadfile(path)), env)()
end
load('modules/game_minimap/minimap.lua')
env.modules.game_minimap = env
env.GameOptions = { loadedWindows = {}, options = {} }
load('mods/client_settings/classes/GameOptions.lua')
local dataset = load('mods/client_settings/classes/dataset.lua')
env.GameOptions.options.minimapHD = dataset.minimapHD
local options = env.GameOptions
options:setupStart()
assert(options:getOption('minimapHD') == false, 'HD must be opt-in')
options:loadSettings() -- No widget yet: store the preference safely.
assert(values.minimapHD == false)

local widget = { zoom = -1, enabled = false, suspended = false, spriteZoom = 3 }
function widget:getZoom() return self.zoom end
function widget:getMinZoom() return self.enabled and not self.suspended and 1 or -1 end
function widget:getMaxZoom() return 5 end
function widget:setZoom(value)
  if value < self:getMinZoom() or value > 5 then return false end
  self.zoom = value
  if self.enabled and not self.suspended then self.spriteZoom = value end
  return true
end
function widget:isSpriteMode() return self.enabled end
function widget:setSpriteMode(enabled)
  if self.enabled == enabled then return end
  self.enabled = enabled
  if enabled then
    self.classicZoom = self.zoom
    if not self.suspended then self:setZoom(self.spriteZoom) end
  else
    self:setZoom(self.classicZoom)
  end
end
function widget:setSpriteModeSuspended(value)
  self.suspended = value
  if self.zoom < self:getMinZoom() then self:setZoom(3) end
end
function widget:getCameraPosition() return { x = 100, y = 100, z = 7 } end
widget.setCameraPosition, widget.setParent, widget.fill = noop, noop, noop
widget.setAlternativeWidgetsVisible = noop
env.minimapWidget = widget
local hdButton = { enabled = true, on = false }
function hdButton:setEnabled(value) self.enabled = value end
function hdButton:setOn(value) self.on = value end
function hdButton:setTooltip(value) self.tooltip = value end
env.minimapWindow = {
  hide = noop, show = noop,
  getChildById = function(_, id) return id == 'minimapHDButton' and hdButton or nil end
}
local checkbox = { checked = false }
function checkbox:getStyle() return { __class = 'UICheckBox' } end
function checkbox:setChecked(value) self.checked = value end
options.loadedWindows.graphics = {
  recursiveGetChildById = function(_, id) return id == 'minimapHD' and checkbox or nil end
}
env.modules.client_settings = {
  getOption = function(key) return options:getOption(key) end,
  setOption = function(key, value) options:setOption(key, value) end
}

options:setOption('minimapHD', true)
assert(widget.enabled and widget.zoom == 2, 'HD should restore its own saved zoom')
assert(hdButton.enabled and hdButton.on and checkbox.checked, 'Option changes must sync both controls')
assert(hdButton.tooltip:find('classic', 1, true), 'Active button must explain how to disable HD')
assert(values.minimapHD == true, 'The checkbox must be persisted')
options:flushSettingsSave()
assert(saves == 1)
widget:setZoom(4)
env.toggleFullMap()
assert(widget.suspended and widget.enabled, 'Full map suspends drawing, not capture')
assert(widget:setZoom(-1), 'Classic full map allows zooming out')
env.toggleFullMap()
assert(not widget.suspended and widget.zoom == 4, 'Full map must restore HD zoom')
env.toggleFullMap()
widget:setZoom(0)
options:setOption('minimapHD', false)
assert(widget.zoom == 0, 'Toggling the option should not change full-map zoom')
env.toggleFullMap()
assert(not widget.enabled and widget.zoom == -1, 'Disabling HD in full map must restore classic zoom')
env.toggleFullMap()
widget:setZoom(0)
options:setOption('minimapHD', true)
assert(widget.zoom == 0, 'Enabling HD should preserve the full-map view')
env.toggleFullMap()
assert(widget.enabled and widget.zoom == 2, 'Enabling HD in full map must restore HD zoom')
options:setOption('minimapHD', false)
assert(not widget.enabled and widget.zoom == -1, 'Classic zoom must be restored')
assert(values.minimapHD == false)

assert(not hdButton.on and not checkbox.checked)
env.toggleMinimapHD()
assert(widget.enabled and values.minimapHD and checkbox.checked and hdButton.on,
       'Quick button must enable, persist and update the Graphics checkbox')
env.toggleMinimapHD()
assert(not widget.enabled and not values.minimapHD and not checkbox.checked and not hdButton.on,
       'Quick button must return to classic through the shared option')
assert(hdButton.tooltip:find('Enable HD', 1, true))

values.minimapHD = true
options:loadSettings()
assert(widget.enabled and hdButton.on and checkbox.checked, 'Saved HD must sync both controls on reload')
env.minimapWidget = nil
assert(env.setMinimapHD(true), 'Preference is safe before widget initialization')
assert(not hdButton.enabled and not hdButton.on)
env.minimapWidget = { } -- Older native executable: do not call missing methods.
assert(not env.setMinimapHD(true))
assert(env.setMinimapHD(false))
assert(not hdButton.enabled and not hdButton.on)
assert(hdButton.tooltip:find('updated client', 1, true))
env.toggleMinimapHD()
assert(values.minimapHD, 'Legacy button must not change the saved preference')

env.UIMinimap = {}
assert(not dataset.minimapHD.apply(true))
assert(dataset.minimapHD.apply(false))

local ui = { UIMinimap = {}, connect = noop, disconnect = noop,
  g_settings = env.g_settings }
setmetatable(ui, { __index = _G })
setfenv(assert(loadfile('modules/gamelib/ui/uiminimap.lua')), ui)()
local savedWidget = { flags = {} }
function savedWidget:getZoom() return 5 end
function savedWidget:getClassicZoom() return -1 end
function savedWidget:getSpriteZoom() return 4 end
ui.UIMinimap.save(savedWidget)
assert(nodes.Minimap.zoom == -1 and nodes.Minimap.spriteZoom == 4,
       'HD and classic zooms must be saved independently')
savedWidget.getClassicZoom, savedWidget.getSpriteZoom = nil, nil
ui.UIMinimap.save(savedWidget)
assert(nodes.Minimap.zoom == 5, 'Saving still supports older executables')

for _, path in ipairs({
  'modules/game_minimap/minimap.lua', 'modules/gamelib/ui/uiminimap.lua',
  'mods/client_settings/classes/dataset.lua', 'mods/client_settings/settings.lua'
}) do
  assert(loadfile(path))
end
print('PASS: opt-in, quick toggle/checkbox sync, persistence, zoom restore, full-map round trip, legacy fallback, Lua syntax')
