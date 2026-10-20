local path = assert(arg[1], 'missing items.lua')
local events, handlers = {}, {}
local function schedule(fn)
  local event = {fn = fn}
  events[#events + 1] = event
  return event
end
addEvent, scheduleEvent = schedule, schedule
removeEvent = function(event) if event then event.cancelled = true end end
g_game = {getFeature = function() return true end}
GameColorizedLootValue = 1
connect = function(object, signals)
  if object == g_game then handlers = signals; return end
  local state = rawget(object, 'state')
  state.hooks[#state.hooks + 1] = signals.onDestroy
end
assert(loadfile(path))()
local lookupsAfterDestroy = 0
local function facade(state)
  local methods = {
    isDestroyed = function() return state.destroyed end,
    getItem = function() state.reads = state.reads + 1; return state.item end,
    getParent = function() return nil end,
    getId = function() return 'slot' end,
    getClassName = function() return 'Item' end,
    getImageSource = function() return state.image end,
    setImageSource = function(_, value) state.image = value end,
    setImageClip = function(_, value) state.clip = value end,
    getWeakReference = function()
      return function() if state.alive then return facade(state) end end
    end
  }
  return setmetatable({state = state}, {
    __index = function(_, key)
      if state.destroyed then lookupsAfterDestroy = lookupsAfterDestroy + 1; error('stale native __index') end
      return state.fields[key] or methods[key]
    end,
    __newindex = function(_, key, value) state.fields[key] = value end
  })
end
local function newWidget()
  local state = {alive = true, destroyed = false, image = '/images/ui/item', fields = {}, hooks = {}, reads = 0,
                 item = {getId = function() return 2160 end}}
  return state, facade(state)
end
local function flush()
  local event = ItemsDatabase.rarityFrameRefreshEvent
  assert(event and not event.cancelled, 'missing refresh')
  event.fn()
end
local function count(values) local n = 0; for _ in pairs(values) do n = n + 1 end; return n end
ItemsDatabase.serverValues[2160] = 1000
local state, widget = newWidget()
ItemsDatabase.setRarityItem(widget, state.item)
assert(state.image == ItemsDatabase.rarityFrameImage)
g_game.setLootValueState(2); flush()
assert(state.image == ItemsDatabase.rarityCornerFrameImage, 'Corners requires reopening the container')
g_game.setLootValueState(0); flush()
assert(state.image == '/images/ui/item', 'None did not restore the original image')
g_game.setLootValueState(1); flush()
assert(state.image == ItemsDatabase.rarityFrameImage, 'Frames did not update live')
ItemsDatabase.setRarityItem(facade(state), state.item)
assert(#state.hooks == 1 and count(ItemsDatabase.rarityWidgetItemIds) == 1, 'userdata alias duplicated tracking')
local weak = setmetatable({widget}, {__mode = 'v'})
widget = nil
collectgarbage(); collectgarbage()
assert(weak[1] == nil, 'registry retained transient Lua userdata')
g_game.setLootValueState(2); flush()
assert(state.image == ItemsDatabase.rarityCornerFrameImage, 'Lua GC lost a still-live native widget')

ItemsDatabase.scheduleRarityFrameRefresh()
state.destroyed = true
for _, hook in ipairs(state.hooks) do hook(facade(state)) end
flush()
assert(lookupsAfterDestroy == 0, 'destroyed userdata was indexed')
assert(count(ItemsDatabase.rarityWidgetItemIds) == 0, 'destroyed record was retained')

handlers.onGameStart()
local staleLoad = ItemsDatabase.serverValueCacheLoadEvent
ItemsDatabase.serverValues[2160] = 1000
ItemsDatabase.markServerValueCacheDirty()
local staleSave = ItemsDatabase.serverValueCacheSaveEvent
local outgoing, oldWidget = newWidget()
ItemsDatabase.setRarityItem(oldWidget, outgoing.item)
ItemsDatabase.scheduleRarityFrameRefresh()
local stale = ItemsDatabase.rarityFrameRefreshEvent
handlers.onGameEnd()
handlers.onGameStart()
local currentLoad = ItemsDatabase.serverValueCacheLoadEvent
ItemsDatabase.markServerValueCacheDirty()
local currentSave = ItemsDatabase.serverValueCacheSaveEvent
ItemsDatabase.serverValues[2160] = 1000
local incoming, newItemWidget = newWidget()
ItemsDatabase.setRarityItem(newItemWidget, incoming.item)
ItemsDatabase.scheduleRarityFrameRefresh()
local current = ItemsDatabase.rarityFrameRefreshEvent
local reads = outgoing.reads
stale.fn() -- Simulate a callback already dequeued before cancellation.
staleLoad.fn()
staleSave.fn()
assert(ItemsDatabase.serverValueCacheLoadEvent == currentLoad and ItemsDatabase.serverValueCacheSaveEvent == currentSave,
       'old cache callback cleared the new session events')
assert(ItemsDatabase.rarityFrameRefreshEvent == current and outgoing.reads == reads,
       'old character callback touched the new session')
flush()
incoming.alive = false
ItemsDatabase.scheduleRarityFrameRefresh(); flush()
assert(count(ItemsDatabase.rarityWidgetItemIds) == 0, 'expired native weak reference was retained')
assert(lookupsAfterDestroy == 0)
print('Rarity live settings, native weak references, userdata aliases and relog lifecycle: OK')
