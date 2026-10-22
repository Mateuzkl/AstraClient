-- Production helper regression tests, without a GPU or user profile.
local events, callbacks, destroyed = {}, {}, 0
local function widget(shared)
  shared = shared or {rect = {x=0,y=0,width=300,height=200}}
  local methods = {
    isDestroyed=function() return shared.destroyed end,
    destroy=function(self) shared.destroyed=true; destroyed=destroyed+1
      if shared.onDestroy then shared.onDestroy(self) end end,
    setSize=function() end, setId=function() end, raise=function() end, focus=function() end,
    fill=function() end, loadDocument=function() return shared.load ~= false end,
    getContext=function() return {OpenDataModel=function(_, _, data) return data end} end,
    getRect=function() return shared.rect end,
  }
  return setmetatable({}, {__index=function(_, k) return methods[k] or shared[k] end,
    __newindex=function(_, k, v) shared[k]=v end}), shared
end
g_rml = {isReady=function() return true end, supportsAdvancedEffects=function() return true end,
  utf8=function(s) return s end, latin1=function(s) return s end}
g_ui = {importStyle=function() end, createWidget=function() local w=widget(); return w end}
g_logger = {warning=function() end}
function connect(w, signals) for k,v in pairs(signals) do w[k]=v end end
function cycleEvent(f) local e={}; events[e]=f; return e end
function removeEvent(e) events[e]=nil end
function addEvent(f) callbacks[#callbacks+1]=f end
dofile(arg[1] or 'modules/corelib/rml.lua')
assert(Rml.isAvailable() and Rml.hasEffects())
assert(Rml.escape('<hello & world>') == '&lt;hello &amp; world&gt;')
assert(Rml.itemImage(123, 2) == 'item/123@2x.png')
local w, state = widget()
local calls=0
Rml.every(w, 10, function() calls=calls+1 end)
for _, f in pairs(events) do f() end
assert(calls == 1)
-- Two distinct proxies share native fields, as in LuaInterface::pushObject.
local other = widget(state)
assert(other ~= w)
other:destroy()
assert(next(events) == nil, 'destroy via another proxy retained the timer')
local closing, closeState = widget()
local closed=0; closing.rmlOnClose=function() closed=closed+1 end
Rml.close(closing); Rml.close(closing)
assert(#callbacks == 1, 'close queued twice')
callbacks[1]()
assert(closed == 1 and closeState.destroyed)
g_ui.createWidget=function() local failed, s=widget(); s.load=false; return failed end
local before=destroyed
assert(Rml.createPanel(nil, '/missing.rml') == nil)
assert(destroyed == before + 1, 'failed panel retained its widget')
g_rml=nil
assert(not Rml.isAvailable())
print('RmlUi helpers: PASS')
