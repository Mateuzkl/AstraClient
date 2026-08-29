local offsetsWindow = nil
local outfitIdWidget = nil
local offsetXWidget = nil
local offsetYWidget = nil

local offsetTypeTabBar = nil
local offsetsContent = nil

local informationOffsetXWidget = nil
local informationOffsetYWidget = nil
local offsetsById = {}

local creaturesOffsetsPanel = nil

local effectsOffsetsPanel = nil
local creatureTab = nil
local effectsTab = nil

local effectDummy = nil

---- New
local offsetsTable = {}

function init()
    -- Load and apply offsets
    scheduleEvent(loadOffsetsData, 200)

    if not DEVELOPERMODE then
        return
    end

    offsetsWindow = g_ui.displayUI('creature_offsets')

    offsetXWidget = offsetsWindow:recursiveGetChildById('offsetX')
    offsetYWidget = offsetsWindow:recursiveGetChildById('offsetY')
    outfitIdWidget = offsetsWindow:recursiveGetChildById('outfitId')

    offsetsWindow:hide()

    connect(LocalPlayer, {
        onPositionChange = onPositionChange
    })

    g_keyboard.bindKeyDown('Ctrl+Alt+O', function()
        local player = g_game.getLocalPlayer()
        if not player then
            return
        end

        showOffset()
    end)

    connect(g_things, { onLoadDat = loadAll })
end

function loadAll()
    loadOffsets()
    --loadEffectsOffsets()
end

function loadOffsets()
    for _, offset in pairs(Offsets) do
        offsetsById[offset.id] = offset
        local thingType = g_things.getThingType(offset.id, ThingCategoryCreature)
        if thingType then
            --thingType:setDrawOffset(offset.drawOffset)
            --thingType:setDrawInformationOffset(offset.drawInformationOffset)
        end
    end
end

function loadEffectsOffsets()
    for outfitId, directions in pairs(OutfitEffects) do
        for direction, effects in pairs(directions) do
            for effectId, offset in pairs(effects) do
                g_things.setOutfitEffectOffset(outfitId, direction, effectId, offset)
            end
        end
    end
end

function terminate()
    if offsetsWindow then
        offsetsWindow:destroy()
        offsetsWindow = nil
    end
    g_keyboard.unbindKeyDown('Ctrl+Alt+O')

    disconnect(g_things, { onLoadDat = loadAll })

    disconnect(LocalPlayer, {
        onPositionChange = onPositionChange,
        onOutfitChange = onOutfitChange
    })

    removeEffect()
end

function removeEffect()
    if effectDummy then
        g_map.removeThing(effectDummy)
        effectDummy:setLoop(false)
    end
end

function showOffset()
    local creatureList = offsetsWindow:recursiveGetChildById('creaturesOffset')
    creatureList:destroyChildren()

    for k, v in pairs(offsetsTable["OutfitOffset"]) do
        local data = v.data
        if data then
            local widget = g_ui.createWidget('ListLabel', creatureList)
            local color = k % 2 == 0 and '#414141' or '#484848'
            widget:setText(string.format("Look: %s", data.type))
            widget:setBackgroundColor(color)
            widget:setId(data.type)
            widget.data = data
        end
    end

    creatureList.onChildFocusChange = function(self, selected, oldSelection) onSelectOutfit(self, selected, oldSelection) end

    offsetsWindow:show()
end

function hideOffset()
    if not DEVELOPERMODE then
        return
    end

    offsetsWindow:hide()
    removeEffect()
end

function onSelectOutfit(list, selected, oldSelection)
    local player = g_game.getLocalPlayer()
    if not player or not selected then
        return
    end

    if oldSelection then
        local childIndex = list:getChildIndex(oldSelection)
        oldSelection:setBackgroundColor(childIndex % 2 == 0 and '#281b17' or '#2c1e19')
    end

    if not selected.data then
        return
    end

    player:setOutfit({type = selected.data.type})
    offsetXWidget:setText(selected.data.draw.x)
    offsetYWidget:setText(selected.data.draw.y)
    outfitIdWidget:setText(selected.data.type)

    local outfitId = tonumber(selected.data.type)
    local thingType = g_things.getThingType(outfitId, ThingCategoryCreature)
    if not thingType or outfitId == 0 then
        return
    end

    thingType:setDrawOffset(topoint(string.format("%d %d", selected.data.draw.x, selected.data.draw.y)))
end

function onOutfitChange(creature, outfit, oldOutfit)
    if not outfitIdWidget then
        return
    end

    if offsetTypeTabBar:getCurrentTab() == effectsTab then
        local effectOutfitIdWidget = effectsOffsetsPanel:recursiveGetChildById('outfitId')
        onEffectOutfitIdChange(effectOutfitIdWidget, outfit.type)
    else
        onOutfitIdChange(outfitIdWidget, outfit.type)
    end
end

function onOutfitIdChange(widget, outfitId)
    if not offsetXWidget or not offsetYWidget then
        return
    end

    if not tonumber(outfitId) then
        return
    end

    g_game.getLocalPlayer():setOutfit({type = outfitId})
end

function onOffsetChange(widget, offsetX, offsetY)
    if not outfitIdWidget then
        return
    end

    offsetX = tonumber(offsetX) or tonumber(offsetXWidget:getText()) or 0
    offsetY = tonumber(offsetY) or tonumber(offsetYWidget:getText()) or 0

    local outfitId = tonumber(outfitIdWidget:getText())
    local thingType = g_things.getThingType(outfitId, ThingCategoryCreature)
    if not thingType or outfitId == 0 then
        return
    end

    thingType:setDrawOffset(topoint(string.format("%d %d", offsetX, offsetY)))
end

function onInformationOffsetChange(widget, x, y)
    if not informationOffsetXWidget or not informationOffsetYWidget then
        return
    end

    x = tonumber(x) or 0
    y = tonumber(y) or 0

    local outfitId = tonumber(outfitIdWidget:getText())
    local thingType = g_things.getThingType(outfitId, ThingCategoryCreature)

    local drawInformationOffset = thingType:getDrawInformationOffset()
    drawInformationOffset.x = x and x or drawInformationOffset.x
    drawInformationOffset.y = y and y or drawInformationOffset.y

    thingType:setDrawInformationOffset(drawInformationOffset)

    if not offsetsById[outfitId] then
        offsetsById[outfitId] = {
            id = outfitId,
            drawOffset = { x = 0, y = 0 },
            drawInformationOffset = drawInformationOffset,
        }
    else
        offsetsById[outfitId].drawInformationOffset = drawInformationOffset
    end
end

function onDirectionChange(widget, value)
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end
    player:setDirection(tonumber(value) or 0)

    updateOffsets()
end

function updateOffsets()
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    if not effectsOffsetsPanel then
        return
    end

    if offsetTypeTabBar:getCurrentTab() ~= effectsTab then
        return
    end

    local effectOffsetXWidget = effectsOffsetsPanel:recursiveGetChildById('offsetX')
    local effectOffsetYWidget = effectsOffsetsPanel:recursiveGetChildById('offsetY')

    local effectId = tonumber(effectsOffsetsPanel:recursiveGetChildById('effectId'):getText())
    local outfitEffects = g_things.getOutfitsEffectsOffsets()
    local direction = player:getDirection()
    local outfitId = player:getOutfit().type

    local offset = outfitEffects[outfitId] and outfitEffects[outfitId][direction] and outfitEffects[outfitId][direction][effectId] or { x = 0, y = 0 }

    effectOffsetXWidget:setText(offset.x, true)
    effectOffsetYWidget:setText(offset.y, true)
end

function onEffectOutfitIdChange(widget, outfitId)
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    outfitId = tonumber(outfitId)
    if not outfitId then
        return
    end

    if not effectsOffsetsPanel then
        return
    end

    if offsetTypeTabBar:getCurrentTab() ~= effectsTab then
        return
    end

    player:setOutfit({type = outfitId})

    updateOffsets()
end

function onEffectIdChange(widget, id)
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    if not effectsOffsetsPanel then
        return
    end

    local effectId = tonumber(id)
    if not effectId then
        return
    end

    if not effectDummy then
        effectDummy = Effect.create()
    end

    effectDummy:setId(effectId)
    effectDummy:setCreatureId(player:getId())

    updateOffsets()
    playEffect() -- Hack to fix the effect not removing
end

function onEffectOffsetChange(widget, offsetX, offsetY)
    if not effectsOffsetsPanel then
        return
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    if not effectDummy then
        return
    end

    offsetX = tonumber(offsetX) or tonumber(effectsOffsetsPanel:recursiveGetChildById('offsetX'):getText()) or 0
    offsetY = tonumber(offsetY) or tonumber(effectsOffsetsPanel:recursiveGetChildById('offsetY'):getText()) or 0

    if offsetX == 0 and offsetY == 0 then
        removeEffect()
        return
    end

    local effectId = effectDummy:getId()
    local outfitId = player:getOutfit().type
    local direction = player:getDirection()
    local offset = { x = offsetX, y = offsetY }

    g_things.setOutfitEffectOffset(outfitId, direction, effectId, offset)
end

function playEffect()
    if not effectDummy then
        return
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local position = player:getPosition()
    g_map.removeThing(effectDummy)
    effectDummy:setLoop(true)
    g_map.addThing(effectDummy, position, 255)
end

function saveOffsets()
    local saveFormat = "\t{\n\t\tid = %d,\n\t\tdrawOffset = { x = %d, y = %d },\n\t\tdrawInformationOffset = { x = %d, y = %d }\n\t},\n"

    local file, err = io.open('modules/game_offsets/variables.lua', 'w')
    if not file then
        print("Error opening file", err)
        return
    end

    file:write("Offsets = {\n")
    for _, offset in pairs(offsetsById) do
        file:write(saveFormat:format(offset.id, offset.drawOffset.x, offset.drawOffset.y, offset.drawInformationOffset.x, offset.drawInformationOffset.y))
    end
    file:write("}\n")
    file:close()
    print("Offsets saved")

    modules.game_offsets.hideOffset()
end

function onPositionChange(creature, newPosition, oldPosition)
    removeEffect()
end

function saveEffectsOffsets()
    local outfitEffects = g_things.getOutfitsEffectsOffsets()
    local filePath = g_resources.getRealDir() .. '/game_offsets/effects_offsets.lua'
    local file, err = io.open(filePath, 'w')
    if not file then
        print("Error opening file", err)
        return
    end

    local output = {"OutfitEffects = {\n"}

    for outfitId, directions in pairs(outfitEffects) do
        table.insert(output, string.format("\t[%d] = {\n", outfitId))
        for direction, effects in pairs(directions) do
            table.insert(output, string.format("\t\t[%d] = {\n", direction))
            for effectId, offset in pairs(effects) do
                table.insert(output, string.format("\t\t\t[%d] = { x = %d, y = %d },\n", effectId, offset.x, offset.y))
            end
            table.insert(output, "\t\t},\n")
        end
        table.insert(output, "\t},\n")
    end

    table.insert(output, "}\n")
    file:write(table.concat(output))
    file:close()

    print("Effects offsets saved")
end

function loadOffsetsData()
    offsetsTable = loadJsonStruct("/data/json/offsets.json", false)
    if not offsetsTable or not offsetsTable["OutfitOffset"] then
        return
    end

    for _, v in ipairs(offsetsTable["OutfitOffset"]) do
        local data = v.data
        if data then
            local thingType = g_things.getThingType(data.type, ThingCategoryCreature)
            if thingType then
                if data.draw then
                    thingType:setDrawOffset(topoint(string.format("%s %s", data.draw.x, data.draw.y)))
                end

                if data.animated then
                    thingType:setAnimatedTextOffset(topoint(string.format("%s %s", data.animated.x, data.animated.y)))
                end

                if data.marktarget ~= nil then
                    thingType:setCanBeMarked(data.marktarget)
                end

                if data.circletarget ~= nil then
                    thingType:setCircleTargetFrame(data.circletarget)
                end

                if data.collision ~= nil then
                    thingType:setServerCollisionSquare(data.collision)
                end
            end
        end
    end
end