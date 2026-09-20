DEFAULT_LAYOUT = ''
tr = function(text, ...) return select('#', ...) > 0 and string.format(text, ...) or text end

local saved = {
  vsync = true,
  noFrameCheckBox = false,
  backgroundFrameRate = 144,
  unfocusedFrameRate = 25,
  minimizedFrameRate = 4
}
local pending = {}
local applied = {}

local function widget()
  return {
    setEnabled = function(self, value) self.enabled = value end,
    setColor = function(self, value) self.color = value end,
    setText = function(self, value) self.text = value end
  }
end

local widgets = {
  noFrameCheckBox = widget(),
  backgroundFrameRate = widget(),
  foregroundFrameRateLabel = widget(),
  unfocusedFrameRateLabel = widget(),
  minimizedFrameRateLabel = widget()
}
local graphics = {
  recursiveGetChildById = function(_, id) return widgets[id] end
}

TempOptions = {
  getOption = function(_, key) return pending[key] end
}
GameOptions = {
  loadingSettings = true,
  getLoadedWindow = function(_, id) return id == 'graphics' and graphics or nil end,
  getDataSet = function(self, key) return self.options[key] end,
  getOption = function(self, key) return self.options[key].value end
}
g_settings = {
  getBoolean = function(key) return saved[key] end,
  getNumber = function(key) return saved[key] end
}
g_window = {
  setVerticalSync = function(value) applied.vsync = value end
}
g_app = {
  setVerticalSyncRequested = function(value) applied.vsyncRequested = value end,
  setUnlimitedFps = function(value) applied.unlimited = value end,
  setMaxFps = function(value) applied.foreground = value end,
  setBackgroundFps = function(value) applied.background = value end,
  setMinimizedFps = function(value) applied.minimized = value end
}

GameOptions.options = assert(loadfile(assert(arg[1], 'missing dataset.lua path')))()

assert(GameOptions.options.backgroundFrameRate.value == 200, 'foreground default')
assert(GameOptions.options.unfocusedFrameRate.value == 30, 'background default')
assert(GameOptions.options.minimizedFrameRate.value == 5, 'minimized default')
assert(GameOptions.options.noFrameCheckBox.value == true, 'unlimited default')
assert(GameOptions.options.vsync.value == false, 'vsync default')

GameOptions.options.vsync.apply(saved.vsync)
assert(applied.vsync == true and applied.vsyncRequested == true, 'saved V-Sync applied')
assert(applied.unlimited == false, 'saved capped mode applied')
assert(applied.foreground == 144, 'saved foreground limit applied')
assert(applied.background == 25, 'saved background limit applied')
assert(applied.minimized == 4, 'saved minimized limit applied')

GameOptions.loadingSettings = false
pending = {
  vsync = false,
  noFrameCheckBox = true,
  backgroundFrameRate = 300,
  unfocusedFrameRate = 20,
  minimizedFrameRate = 2
}
GameOptions.options.unfocusedFrameRate.apply(20)
assert(applied.vsync == false and applied.vsyncRequested == false, 'pending V-Sync applied')
assert(applied.unlimited == true, 'pending unlimited mode applied')
assert(applied.foreground == 300, 'pending foreground limit applied')
assert(applied.background == 20, 'pending background limit applied')
assert(applied.minimized == 2, 'pending minimized limit applied')
assert(widgets.backgroundFrameRate.enabled == false, 'foreground slider disabled in unlimited mode')
assert(widgets.noFrameCheckBox.text == 'Frame Rate Mode: Unlimited', 'mode label synchronized')

pending.noFrameCheckBox = false
GameOptions.options.noFrameCheckBox.tempApply(false)
assert(widgets.backgroundFrameRate.enabled == true, 'foreground slider enabled in capped mode')
assert(widgets.noFrameCheckBox.text == 'Frame Rate Mode: Capped', 'capped label synchronized')

print('smart FPS settings: OK')
