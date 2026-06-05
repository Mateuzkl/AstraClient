
function onGameStart()
    addEvent(function()
        -- g_game.getLocalPlayer():attachEffect(AttachedEffectManager.create(1))
        -- g_game.getLocalPlayer():attachEffect(AttachedEffectManager.create(2))

        -- local angelLight1 = AttachedEffectManager.create(3)
        -- local angelLight2 = AttachedEffectManager.create(3)
        -- local angelLight3 = AttachedEffectManager.create(3)
        -- local angelLight4 = AttachedEffectManager.create(3)

        -- angelLight1:setOffset(-50, 50, true)
        -- angelLight2:setOffset(50, 50, true)
        -- angelLight3:setOffset(50, -50, true)
        -- angelLight4:setOffset(-50, -50, true)


        -- g_game.getLocalPlayer():attachEffect(angelLight1)
        -- g_game.getLocalPlayer():attachEffect(angelLight2)
        -- g_game.getLocalPlayer():attachEffect(angelLight3)
        -- g_game.getLocalPlayer():attachEffect(angelLight4)

        -- local player = g_game.getLocalPlayer()
        -- local outfit = player:getOutfit()

    end)
end

function onGameEnd()
    local player = g_game.getLocalPlayer()
    if player then
        player:clearAttachedEffects()
    end
end

function init()
    connect(LocalPlayer, {
        --onOutfitChange = onOutfitChange
    })

    connect(Creature, {
        --onOutfitChange = onOutfitChange,
        onSetEffects = onSetEffects
    })

    connect(AttachedEffect, {
        onAttach = onAttach,
        onDetach = onDetach
    })

    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    if g_game.isOnline() then
        onGameEnd()
    end

    disconnect(LocalPlayer, {
        --onOutfitChange = onOutfitChange
    })

    disconnect(Creature, {
        onOutfitChange = onOutfitChange,
        onSetEffects = onSetEffects
    })

    disconnect(AttachedEffect, {
        onAttach = onAttach,
        onDetach = onDetach
    })

    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })
end

function onAttach(effect, owner)
    local category, thingId = AttachedEffectManager.getDataThing(owner)
    local config = AttachedEffectManager.getConfig(effect:getId(), category, thingId)

    if not config then
        g_logger.debug(string.format("[AttachedEffect] onAttach: No config found for effect ID %d (category: %d, thingId: %d)", effect:getId(), category, thingId))
        return
    end

    if owner:isCreature() then
        owner:setDisableWalkAnimation(config.disableWalkAnimation or false)
    end

    if config.onAttach then
        config.onAttach(effect, owner, config.__onAttach)
    end
end

function onDetach(effect, oldOwner)
    local category, thingId = AttachedEffectManager.getDataThing(oldOwner)
    local config = AttachedEffectManager.getConfig(effect:getId(), category, thingId)

    if not config then
        g_logger.debug(string.format("[AttachedEffect] onDetach: No config found for effect ID %d (category: %d, thingId: %d)", effect:getId(), category, thingId))
        return
    end

    if oldOwner:isCreature() and config.disableWalkAnimation then
        oldOwner:setDisableWalkAnimation(false)
    end

    if config.onDetach then
        config.onDetach(effect, oldOwner, config.__onDetach)
    end
end

function onOutfitChange(creature, outfit, oldOutfit)
    for _i, effect in pairs(creature:getAttachedEffects()) do
        AttachedEffectManager.executeThingConfig(effect, ThingCategoryCreature, outfit.type)
    end
end

function onSetEffects(creature, effects)
    if #effects == 0 then
        creature:clearAttachedEffects()
        onOutfitChange(creature, creature:getOutfit())
        return
    end

    -- effects = {4, 5}
    creature:clearAttachedEffects()
    for _i, effect in pairs(effects) do
        creature:attachEffect(AttachedEffectManager.create(effect))
    end

    -- onOutfitChange(creature, creature:getOutfit())
end
