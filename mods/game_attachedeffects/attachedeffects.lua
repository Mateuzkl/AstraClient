-- Weak keys do not keep disappeared creatures/items/tiles alive.
local owners = setmetatable({}, {__mode = 'k'})

function onGameEnd()
    for owner in pairs(owners) do owner:clearAttachedEffects(true) end
    owners = setmetatable({}, {__mode = 'k'})
end

function init()
    assert(g_attachedEffects and AttachedEffect, 'Native Attached Effects support is required')
    connect(Creature, {onOutfitChange = onOutfitChange})
    connect(AttachedEffect, {onAttach = onAttach, onDetach = onDetach})
    connect(g_game, {onGameEnd = onGameEnd})
end

function terminate()
    onGameEnd()
    disconnect(Creature, {onOutfitChange = onOutfitChange})
    disconnect(AttachedEffect, {onAttach = onAttach, onDetach = onDetach})
    disconnect(g_game, {onGameEnd = onGameEnd})
    AttachedEffectManager.clear()
end

function onAttach(effect, owner)
    owners[owner] = true
    local category, thingId = AttachedEffectManager.getDataThing(owner)
    local config = AttachedEffectManager.executeThingConfig(effect, category, thingId, true)
    if config and config.onAttach then config.onAttach(effect, owner, config.__onAttach) end
end

function onDetach(effect, owner)
    local category, thingId = AttachedEffectManager.getDataThing(owner)
    local config = AttachedEffectManager.getConfig(effect:getId(), category, thingId)
    if config and config.onDetach then config.onDetach(effect, owner, config.__onDetach) end
    if not owner:hasAttachedEffects() then owners[owner] = nil end
end

function onOutfitChange(creature, outfit)
    for _, effect in ipairs(creature:getAttachedEffects()) do
        AttachedEffectManager.executeThingConfig(effect, ThingCategoryCreature, outfit.type)
    end
end
