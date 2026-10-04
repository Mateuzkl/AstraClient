-- Run inside a development client with DAT loaded. This exercises real native
-- ownership/callback paths; it is deliberately not a plain-Lua mock/CI test.
assert(g_things and g_things.isDatLoaded(), 'Load a DAT before running this test')
assert(g_things.isValidDatId(100, ThingCategoryItem) and g_things.isValidDatId(1, ThingCategoryEffect),
       'This fixture requires item 100 and effect 1')

local id = 65534 -- Reserved only for this test; existing registrations are never replaced.
local prototype = assert(g_attachedEffects.registerByThing(id, 'native regression', 1, ThingCategoryEffect),
                         'Test ID is already registered; choose an unused ID')
local owner, secondOwner = Item.create(100), Item.create(100)
local clone
local attached, detached = 0, 0
local handlers = {
    onAttach = function() attached = attached + 1 end,
    onDetach = function() detached = detached + 1 end
}
connect(AttachedEffect, handlers)
local ok, failure = xpcall(function()
    owner:attachEffect(prototype)
    local runtime = assert(owner:getAttachedEffectById(id))
    assert(runtime ~= prototype, 'registered prototype became runtime-owned')
    runtime:setSpeed(3)
    runtime:setOpacity(0.25)
    assert(prototype:getSpeed() == 1 and prototype:getOpacity() == 1)
    assert(g_attachedEffects.getById(id):getSpeed() == 1, 'runtime mutated future copies')
    secondOwner:attachEffect(prototype)
    assert(secondOwner:getAttachedEffectById(id) ~= runtime)
    owner:attachEffect(prototype)
    assert(#owner:getAttachedEffects() == 1, 'registered ID was not idempotent')
    local adHocA = assert(AttachedEffect.create(1, ThingCategoryEffect))
    local adHocB = assert(AttachedEffect.create(1, ThingCategoryEffect))
    owner:attachEffect(adHocA)
    owner:attachEffect(adHocB)
    assert(#owner:getAttachedEffects() == 3, 'ID-zero effects were deduplicated')
    local beforeAttach, beforeDetach = attached, detached
    clone = owner:clone()
    assert(#clone:getAttachedEffects() == 3 and attached == beforeAttach,
           'structural item clone invoked onAttach')
    assert(clone:getAttachedEffectById(id) ~= runtime, 'clone shared attachment ownership')
    clone:clearAttachedEffects(false)
    assert(detached == beforeDetach, 'silent structural clone invoked onDetach')
    owner:detachEffect(adHocA)
    assert(detached == beforeDetach + 1, 'normal native detach callback stopped working')
end, debug.traceback)
owner:clearAttachedEffects(true)
secondOwner:clearAttachedEffects(true)
if clone then clone:clearAttachedEffects(true) end
disconnect(AttachedEffect, handlers)
g_attachedEffects.remove(id)
assert(ok, failure)
print('Native attached effects ownership/ID-zero/structural clone regression: OK')
