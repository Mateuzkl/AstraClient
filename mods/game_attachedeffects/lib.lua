-- Native prototypes + owner-specific configuration. No independent Lua renderer.
local effects, thingConfigs = {}, {}
local function configure(effect, config)
    config = config or {}
    -- Reset every property so an old lookType override cannot leak into a new outfit.
    effect:setSpeed(config.speed or 1)
    effect:setOpacity(config.opacity or 1)
    effect:setCanDrawOnUI(config.drawOnUI ~= false)
    effect:setFollowOwner(config.followOwner ~= false)
    effect:setHideOwner(config.hideOwner == true)
    effect:setTransform(config.transform == true)
    effect:setDisableWalkAnimation(config.disableWalkAnimation == true)
    effect:setPermanent(config.permanent == true)
    effect:setDuration(config.duration or 0)
    effect:setLoop(config.loop == nil and -1 or config.loop)
    effect:setDrawOrder(config.drawOrder or 2)
    effect:setShader(config.shader or '')
    effect:setSize(config.size and {width = config.size.width or config.size[1],
                                   height = config.size.height or config.size[2]} or {width = 0, height = 0})
    effect:setLight(config.light or {color = 215, intensity = 0})
    local bounce, pulse, fade = config.bounce or {}, config.pulse or {}, config.fade or {}
    effect:setBounce(bounce[1] or 0, bounce[2] or 0, bounce[3] or 0)
    effect:setPulse(pulse[1] or 0, pulse[2] or 0, pulse[3] or 0)
    effect:setFade(fade[1] or 0, fade[2] or 0, fade[3] or 0)
    local offset = config.offset or {}
    local x, y, onTop = offset[1] or 0, offset[2] or 0, offset[3] == true
    effect:setOffset(x, y)
    effect:setOnTop(onTop)
    for dir, value in pairs(config.dirOffset or {}) do
        if type(value) == 'boolean' then
            effect:setOnTopByDir(dir, value)
        else
            local top = value[3]
            if top == nil then top = onTop end
            effect:setDirOffset(dir, value[1] or x, value[2] or y, top)
        end
    end
end

AttachedEffectManager = {
    get = function(id) return effects[id] end,
    register = function(id, name, source, category, config)
        if effects[id] then
            g_logger.error('Attached effect already registered: ' .. id)
            return
        end
        local prototype
        if category == ThingExternalTexture then
            prototype = g_attachedEffects.registerByImage(id, name, source, not config or config.smooth ~= false)
        else
            prototype = g_attachedEffects.registerByThing(id, name, source, category)
        end
        if not prototype then return end
        effects[id] = {id = id, name = name, thingId = source, thingCategory = category, config = config or {}}
        configure(prototype, config)
        return prototype
    end,
    create = function(id) return g_attachedEffects.getById(id) end,
    registerThingConfig = function(category, thingId)
        thingConfigs[category] = thingConfigs[category] or {}
        thingConfigs[category][thingId] = thingConfigs[category][thingId] or {}
        local configs = thingConfigs[category][thingId]
        return {set = function(_, id, config)
            local base = effects[id]
            if not base then
                g_logger.error('Unknown attached effect: ' .. id)
                return
            end
            local merged = table.recursivecopy(base.config)
            table.merge(merged, config)
            if config.onAttach then merged.__onAttach = base.config.onAttach end
            if config.onDetach then merged.__onDetach = base.config.onDetach end
            configs[id] = merged
        end}
    end,
    getConfig = function(id, category, thingId)
        local categoryConfigs = thingConfigs[category]
        local configs = categoryConfigs and categoryConfigs[thingId]
        return configs and configs[id] or effects[id] and effects[id].config
    end,
    executeThingConfig = function(effect, category, thingId, attaching)
        local config = AttachedEffectManager.getConfig(effect:getId(), category, thingId)
        local categoryConfigs = thingConfigs[category]
        local overrides = categoryConfigs and categoryConfigs[thingId]
        -- A runtime clone already carries its prototype's configuration. Without
        -- a lookType override, attaching must not erase subsequent native setters.
        if config and (not attaching or overrides and overrides[effect:getId()]) then
            configure(effect, config)
        end
        return config
    end,
    getDataThing = function(owner)
        if owner.isCreature and owner:isCreature() then return ThingCategoryCreature, owner:getOutfit().type end
        if owner.isItem and owner:isItem() then return ThingCategoryItem, owner:getId() end
        return ThingInvalidCategory, 0
    end,
    clear = function()
        for id in pairs(effects) do g_attachedEffects.remove(id) end
        effects, thingConfigs = {}, {}
    end
}
