-- Exercise the production Lua configuration/lifecycle without a client build.
local libPath = arg[1] or 'mods/game_attachedeffects/lib.lua'
local modulePath = arg[2] or 'mods/game_attachedeffects/attachedeffects.lua'
dofile('modules/corelib/table.lua')

ThingCategoryItem, ThingCategoryCreature, ThingCategoryEffect = 0, 1, 2
ThingInvalidCategory, ThingExternalTexture = 4, 5
Creature, AttachedEffect, g_game = {}, {}, {}
g_logger = {error = function(message) error(message) end}

local prototypes, connections = {}, {}
local properties = {
    setSpeed = 'speed', setOpacity = 'opacity', setCanDrawOnUI = 'drawOnUI',
    setFollowOwner = 'followOwner', setHideOwner = 'hideOwner', setTransform = 'transform',
    setDisableWalkAnimation = 'disableWalkAnimation', setPermanent = 'permanent',
    setDuration = 'duration', setLoop = 'loop', setDrawOrder = 'drawOrder',
    setShader = 'shader', setSize = 'size', setLight = 'light'
}
local function makeEffect(id, values)
    local effect = {id = id, values = table.recursivecopy(values or {}), directions = {}}
    function effect:getId() return self.id end
    for method, property in pairs(properties) do
        effect[method] = function(self, value) self.values[property] = value end
    end
    for _, name in ipairs({'Bounce', 'Pulse', 'Fade'}) do
        effect['set' .. name] = function(self, a, b, c) self.values[name] = {a, b, c} end
    end
    function effect:setOffset(x, y) self.values.offset = {x, y}; self.directions = {} end
    function effect:setOnTop(value) self.values.onTop = value end
    function effect:setOnTopByDir(dir, value) self.directions[dir] = {onTop = value} end
    function effect:setDirOffset(dir, x, y, top) self.directions[dir] = {x = x, y = y, onTop = top} end
    return effect
end
g_attachedEffects = {
    registerByThing = function(id)
        assert(not prototypes[id], 'duplicate native registration')
        prototypes[id] = makeEffect(id)
        return prototypes[id]
    end,
    registerByImage = function(id)
        return g_attachedEffects.registerByThing(id)
    end,
    getById = function(id)
        return prototypes[id] and makeEffect(id, prototypes[id].values)
    end,
    remove = function(id) prototypes[id] = nil end
}
function connect(target, handlers)
    assert(not connections[target], 'duplicate connection')
    connections[target] = handlers
end
function disconnect(target, handlers)
    local previous = assert(connections[target], 'disconnect without connection')
    for name, handler in pairs(previous) do assert(handlers[name] == handler, 'mismatched disconnect') end
    for name, handler in pairs(handlers) do assert(previous[name] == handler, 'extra disconnect handler') end
    connections[target] = nil
end

dofile(libPath)
dofile(modulePath)
init()
assert(connections[Creature].onSetEffects == nil and onSetEffects == nil, 'dead snapshot hook retained')
for id, config in pairs({[10] = {}, [11] = {permanent = false, followOwner = false},
                         [12] = {permanent = true, followOwner = true}}) do
    AttachedEffectManager.register(id, 'default contract', 12, ThingCategoryEffect, config)
end
assert(prototypes[10].values.permanent == true and prototypes[10].values.followOwner == false)
assert(prototypes[11].values.permanent == false and prototypes[11].values.followOwner == false)
assert(prototypes[12].values.permanent == true and prototypes[12].values.followOwner == true)
AttachedEffectManager.register(13, 'oscillation defaults', 12, ThingCategoryEffect,
    {bounce = {0, 10}, pulse = {0, 20}, fade = {0, 100}, onTop = true})
assert(prototypes[13].values.Bounce[3] == 1000 and prototypes[13].values.Pulse[3] == 1000
       and prototypes[13].values.Fade[3] == 1000 and prototypes[13].values.onTop == true)
local attached, detached = 0, 0
AttachedEffectManager.register(1, 'test effect', 12, ThingCategoryEffect, {
    speed = 2, disableWalkAnimation = true, offset = {5, -7, true},
    onAttach = function() attached = attached + 1 end,
    onDetach = function() detached = detached + 1 end
})
AttachedEffectManager.registerThingConfig(ThingCategoryCreature, 618):set(1, {
    speed = 0.5, disableWalkAnimation = false, offset = {0, 0, false},
    dirOffset = {[0] = {0, 0, false}}
})

local owner = {outfit = {type = 100}, effects = {}, silentClears = 0}
function owner:isCreature() return true end
function owner:getOutfit() return self.outfit end
function owner:getAttachedEffects() return self.effects end
function owner:hasAttachedEffects() return #self.effects > 0 end
function owner:clearAttachedEffects(silent)
    assert(silent == true, 'shutdown must suppress callbacks')
    self.effects = {}
    self.silentClears = self.silentClears + 1
end
local function attach(effect)
    owner.effects[#owner.effects + 1] = effect
    connections[AttachedEffect].onAttach(effect, owner)
end

local first, second = AttachedEffectManager.create(1), AttachedEffectManager.create(1)
assert(first ~= second, 'runtime instances must not share mutable state')
first:setSpeed(3.5)
first:setDuration(2500)
first:setOpacity(0.42)
first:setPermanent(true)
first:setShader('runtime shader')
first:setOffset(-4, 9)
attach(first)
assert(first.values.speed == 3.5 and first.values.duration == 2500 and first.values.opacity == 0.42
       and first.values.permanent == true, 'attach erased explicit runtime setters')
assert(first.values.shader == 'runtime shader' and first.values.offset[1] == -4
       and first.values.offset[2] == 9, 'attach erased shader/offset setters')
assert(second.values.speed == 2 and prototypes[1].values.speed == 2, 'runtime edit leaked into prototype')
assert(attached == 1, 'base callback was not invoked')

owner.outfit.type = 618
connections[Creature].onOutfitChange(owner, owner.outfit)
assert(first.values.speed == 0.5 and first.values.disableWalkAnimation == false)
assert(first.values.offset[1] == 0 and first.values.offset[2] == 0 and first.values.onTop == false)
assert(first.directions[0].onTop == false, 'false direction override was lost')
owner.outfit.type = 100
connections[Creature].onOutfitChange(owner, owner.outfit)
assert(first.values.speed == 2 and first.values.disableWalkAnimation == true)
assert(first.values.offset[1] == 5 and first.values.onTop == true, 'lookType override was not reset')

owner.effects = {}
connections[AttachedEffect].onDetach(first, owner)
assert(detached == 1)
attach(second)
connections[g_game].onGameEnd()
assert(not owner:hasAttachedEffects() and owner.silentClears == 1)
assert(detached == 1, 'logout unexpectedly invoked detach callbacks')
terminate()
assert(next(connections) == nil and next(prototypes) == nil, 'module unload left state/connections')
init()
assert(AttachedEffectManager.register(1, 'reload', 12, ThingCategoryEffect), 'reload retained registrations')
terminate()
for cycle = 1, 1000 do
    init()
    assert(AttachedEffectManager.register(1, 'reload cycle', 12, ThingCategoryEffect))
    terminate()
    assert(next(connections) == nil and next(prototypes) == nil, 'reload retained state')
end
print('Attached effects Lua configuration/lifecycle: OK')
