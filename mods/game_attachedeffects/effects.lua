--[[
    register(id, name, thingId, thingType, config)
    config = {
        speed, disableWalkAnimation, shader,
        offset{x, y, onTop}, dirOffset[dir]{x, y, onTop},
        onAttach, onDetach
    }
]] --
AttachedEffectManager.register(1, 'Spoke Lighting', 12, ThingCategoryEffect, {
    speed = 0.5,
    onAttach = function(effect, owner)
        print('onAttach: ', effect:getId(), owner:getName())
    end,
    onDetach = function(effect, oldOwner)
        print('onDetach: ', effect:getId(), oldOwner:getName())
    end
})

-- Use normal rendering: the upstream demo shaders are not registered in Astra.
AttachedEffectManager.register(2, 'Bat Wings', 307, ThingCategoryCreature, {
    speed = 5,
    disableWalkAnimation = true,
    dirOffset = {
        [North] = {0, -10, true},
        [East] = {5, -5},
        [South] = {-5, 0},
        [West] = {-10, -5, true}
    }
})

AttachedEffectManager.register(3, 'Angel Light', 50, ThingCategoryEffect, {})

AttachedEffectManager.register(4, 'Brino - Effect', 2558, ThingCategoryCreature, {
    dirOffset = {
        [North] = {0, 0, true},
        [East] = {0, 0, true},
        [South] = {0, 0, true},
        [West] = {0, 0, true}
    }
})

AttachedEffectManager.register(5, 'Brino - Effect', 2559, ThingCategoryCreature, {
    dirOffset = {
        [North] = {0, 0, false},
        [East] = {0, 0, false},
        [South] = {0, 0, false},
        [West] = {0, 0, false}
    }
})

-- OpenTibiaBR image presets; retain the reference IDs, size and anchor offsets.
AttachedEffectManager.register(7, 'Pentagram Aura', '/images/game/effects/pentagram.png', ThingExternalTexture, {
    size = {128, 128},
    offset = {50, 45}
})

AttachedEffectManager.register(8, 'Ki', '/images/game/effects/ki.png', ThingExternalTexture, {
    size = {140, 110},
    offset = {60, 75, true}
})

AttachedEffectManager.register(9, 'Thunder', '/images/game/effects/thunder.png', ThingExternalTexture, {
    loop = 1,
    offset = {215, 230}
})
