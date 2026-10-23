-- Exercise production module callbacks and count unnecessary model/list rebuilds.
local created, paletteBuilds = {}, 0
local function createWidget()
    return setmetatable({updates = {}}, {__index = function() return function() end end})
end
local env = setmetatable({
    g_rml = {getBackendName = function() return 'test' end},
    g_game = {isOnline = function() return false end, getClientVersion = function() return 860 end},
    g_settings = {getString = function() return '' end, getInteger = function() return 860 end},
    g_things = {isDatLoaded = function() return false end},
    g_ui = {createWidget = createWidget},
    connect = function(w, events)
        if events.onRmlUpdate then w.updates[#w.updates + 1] = events.onRmlUpdate end
    end,
}, {__index = _G})
local function update(w) for _, callback in ipairs(w.updates) do callback() end end
env.Rml = {
    text = function(s) return s end, fromRml = function(s) return s end,
    itemImage = function(id) return 'item/' .. id end,
    outfitImage = function(o, direction) return 'outfit/' .. o.type .. '/' .. direction end,
    hasEffects = function() return true end, host = function() end, on = function() end,
    every = function(w, _, callback) w.timers[#w.timers + 1] = callback end,
    watch = function(w, _, _, callback) w.watch = callback end,
    colorHex = function(id) return tostring(id) end,
    outfitPalette = function() paletteBuilds = paletteBuilds + 1; return {{id = 0, hex = '#000000'}} end,
    toggle = function(holder, key, open) holder[key] = open() end,
    createWindow = function(opts)
        local w = createWidget()
        w.timers = {}
        local writes = {}
        local model = setmetatable({}, {__index = opts.data, __newindex = function(_, k, v)
            writes[k] = (writes[k] or 0) + 1
            opts.data[k] = v
        end})
        created[#created + 1] = {w = w, model = model, writes = writes, opts = opts}
        return w, model
    end,
}
assert(setfenv(assert(loadfile('modules/client_rmlshowcase/showcase.lua')), env))()
env.toggle()
local s = created[#created]
assert(#s.w.updates == 1, 'showcase registered redundant update callbacks')
assert(#s.model.items == 0 and #s.model.bigItems == 0 and #s.model.slides == 0 and #s.model.examples == 0,
    'unopened tabs eagerly instantiated lists')
update(s.w)
assert(#s.model.items == 0 and #s.model.slides == 0, 'home update instantiated hidden tabs')
for _, timer in ipairs(s.w.timers) do timer() end
assert(s.model.outfitSrc == '', 'hidden outfit kept animating')
s.model.tab = 'sprites'; update(s.w)
assert(#s.model.items == 6 and #s.model.bigItems == 3 and s.model.outfitSrc ~= '')
local items = s.model.items
update(s.w)
assert(s.model.items == items, 'sprite list rebuilt every tick')
s.model.tab = 'images'; update(s.w)
assert(#s.model.slides == 5)
s.model.Slide(nil, 1); assert(s.model.slide == 1)
s.model.tab = 'otui'; update(s.w)
assert(#s.model.examples > 0)
s.model.tab = 'home'; update(s.w)
s.model.tab = 'sprites'; update(s.w)
assert(s.model.items == items, 'returning to a tab rebuilt its list')

assert(setfenv(assert(loadfile('modules/game_rmloutfit/rmloutfit.lua')), env))()
env.toggle()
local outfit = created[#created]
assert(outfit.model.preview ~= '' and #outfit.model.parts == 4 and outfit.model.selectedColor == 78,
    'outfit document loaded with an incomplete initial model')
assert(not next(outfit.writes), 'initial model was dirtied after document load')
local parts = outfit.model.parts
outfit.model.Turn(nil, 1)
assert(outfit.model.parts == parts, 'turning rebuilt unchanged color controls')
outfit.model.Pick(nil, 12)
assert(outfit.model.parts ~= parts and outfit.model.selectedColor == 12)
parts = outfit.model.parts
outfit.w.watch()
assert(outfit.model.parts == parts, 'unchanged watch rebuilt controls')
env.toggle()
assert(paletteBuilds == 1, 'immutable palette rebuilt for every window')

local current = {type=161, head=1, body=2, legs=3, feet=4, addons=0,
    mount=17, familiar=18, wings=19, aura=20, shader='custom', healthBar=21, manaBar=22}
local sent
env.g_game.isOnline = function() return true end
env.g_game.getLocalPlayer = function() return {getOutfit=function() return current end} end
env.g_game.changeOutfit = function(value) sent=value end
env.toggle()
local online = created[#created]
online.model.head, online.model.addon1 = 55, true
-- A server update while the editor is open must not be reverted by Apply.
current.mount = 37
online.model.Apply()
assert(sent ~= current and sent.head == 55 and sent.addons == 1)
for _, key in ipairs({'type', 'body', 'legs', 'feet', 'mount', 'familiar', 'wings', 'aura', 'shader', 'healthBar', 'manaBar'}) do
    assert(sent[key] == current[key], 'Apply lost outfit field: ' .. key)
end
assert(current.head == 1 and current.addons == 0, 'Apply mutated the live outfit')

local originalMap = function() end
local bindings = {['Ctrl+Shift+M'] = originalMap}
env.g_keyboard = {
    bindKeyDown = function(key, callback)
        assert(key ~= 'Ctrl+Shift+M', 'RmlUi replaced the full-map shortcut')
        bindings[key] = callback
    end,
    unbindKeyDown = function(key, callback)
        assert(callback == env.toggle, 'module unload unbound other modules callbacks')
        if bindings[key] == callback then bindings[key] = nil end
    end,
}
local available = false
env.Rml.isAvailable = function() return available end
assert(setfenv(assert(loadfile('modules/game_rmlminimap/rmlminimap.lua')), env))()
env.init()
assert(bindings['Ctrl+Shift+J'] == nil, 'unavailable RmlUi registered a shortcut')
available = true
env.init()
assert(bindings['Ctrl+Shift+J'] == env.toggle)
env.terminate()
assert(bindings['Ctrl+Shift+J'] == nil and bindings['Ctrl+Shift+M'] == originalMap)

local manifest = assert(io.open('modules/client_rmloptions/rmloptions.otmod', 'rb'))
local dependencies = assert(manifest:read('*a'):match('dependencies:%s*%[(.-)%]'))
manifest:close()
local declared = {}
for name in dependencies:gmatch('[%w_]+') do declared[name]=true end
assert(declared.client_options and declared.client_settings, 'options module did not declare its settings API dependency')
local saved, classic = {vsync=false}, 0
env.modules = {client_settings={
    getOption=function(key) return saved[key] end,
    setOption=function(key, value) saved[key]=value end,
    toggle=function() classic=classic+1 end,
}}
env.GameOptions = {getDataSet=function(_, key) return key == 'vsync' and {} or nil end}
assert(setfenv(assert(loadfile('modules/client_rmloptions/rmloptions.lua')), env))()
env.toggle()
local settings = created[#created]
assert(#settings.model.sections[1].options == 1)
for i=1,3 do update(settings.w) end
settings.model.sections[1].options[1].value=true
update(settings.w)
assert(saved.vsync == true, 'RmlUi did not apply through client_settings')
settings.model.OpenClassic()
assert(classic == 1)
print('RmlUi opening: PASS (lazy tabs, rebuild bounds, outfit fields, shortcuts and settings API)')

-- Real signal and keyboard implementations: a module must not erase another
-- owner's binding on the same key, including after repeated load/unload.
dofile('modules/corelib/table.lua')
dofile('modules/corelib/string.lua')
local keys = setmetatable({rootWidget={}, g_logger={error=error, log=function() end}}, {__index=_G})
assert(setfenv(assert(loadfile('modules/corelib/util.lua')), keys))()
assert(setfenv(assert(loadfile('modules/corelib/keyboard.lua')), keys))()
for _, spec in ipairs({
    {'modules/client_rmldemo/rmldemo.lua','Ctrl+Shift+R'},
    {'modules/client_rmloptions/rmloptions.lua','Ctrl+Shift+O'},
    {'modules/client_rmlshowcase/showcase.lua','Ctrl+Shift+U'},
    {'modules/game_rmloutfit/rmloutfit.lua','Ctrl+Shift+F'},
    {'modules/game_rmlminimap/rmlminimap.lua','Ctrl+Shift+J'},
}) do
    local foreignCalls,moduleCalls=0,0
    local foreign=function() foreignCalls=foreignCalls+1 end
    keys.g_keyboard.bindKeyDown(spec[2],foreign)
    local module=setmetatable({
        g_keyboard=keys.g_keyboard, Rml={isAvailable=function() return true end}, g_rml={},
        modules={client_topmenu={addLeftButton=function() return {destroy=function() end} end}},
    },{__index=keys})
    assert(setfenv(assert(loadfile(spec[1])),module))()
    module.toggle=function() moduleCalls=moduleCalls+1 end
    local function fire()
        local signal=keys.rootWidget.boundKeyDownCombos[keys.retranslateKeyComboDesc(spec[2])]
        if type(signal)=='table' then for _,f in ipairs(signal) do f() end
        elseif signal then signal() end
    end
    for cycle=1,2 do
        module.init(); fire()
        assert(moduleCalls==cycle, spec[1]..': duplicate module callback')
        module.terminate(); fire()
        assert(moduleCalls==cycle and foreignCalls==cycle*2, spec[1]..': removed foreign shortcut')
    end
    keys.g_keyboard.unbindKeyDown(spec[2],foreign)
end
print('RmlUi hotkeys: PASS (real keyboard/signals, five modules, shared shortcuts, two reloads)')
