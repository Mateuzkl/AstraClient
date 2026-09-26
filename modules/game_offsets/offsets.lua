local loadOffsetsEvent

local function loadOffsetsData()
    local offsetsTable = loadJsonStruct('/data/json/offsets.json', false)
    if not offsetsTable or not offsetsTable.OutfitOffset then
        return
    end

    for _, entry in ipairs(offsetsTable.OutfitOffset) do
        local data = entry.data
        if data then
            local thingType = g_things.getThingType(data.type, ThingCategoryCreature)
            if thingType then
                if data.draw then
                    thingType:setDrawOffset(topoint(string.format('%s %s', data.draw.x, data.draw.y)))
                end

                if data.animated then
                    thingType:setAnimatedTextOffset(topoint(string.format('%s %s', data.animated.x, data.animated.y)))
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

function init()
    loadOffsetsEvent = scheduleEvent(function()
        loadOffsetsEvent = nil
        loadOffsetsData()
    end, 200)
    initDatOffsetEditor()
end

function terminate()
    if loadOffsetsEvent then
        removeEvent(loadOffsetsEvent)
        loadOffsetsEvent = nil
    end
    terminateDatOffsetEditor()
end
