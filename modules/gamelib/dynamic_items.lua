-- Dynamic items pairing table.
-- Maps the equipped form ID -> unequipped form ID for items that change
-- appearance when worn (rings, amulets, etc).
-- Exposed as a global so any sandboxed module can use it.
DynamicItems = {
    [3086] = 3049,
    [3087] = 3050,
    [3088] = 3051,
    [3089] = 3052,
    [3090] = 3053,
    [3094] = 3091,
    [3095] = 3092,
    [3096] = 3093,
    [3099] = 3097,
    [3100] = 3098,
    [3549] = 6529,
    [6300] = 6299,
    [9018] = 9019,
    [9392] = 9393,
    [16264] = 16114,
    [22134] = 22061,
    [23476] = 23477,
    [23530] = 23529,
    [23532] = 23531,
    [23534] = 23533,
    [23526] = 23542,
    [23527] = 23543,
    [23528] = 23544,
    [30343] = 30342,
    [30345] = 30344,
    [30402] = 30403,
    [31616] = 31557,
    [32635] = 32621,
    [39178] = 39177,
    [39181] = 39180,
    [39184] = 39183,
    [39187] = 39186,
    [39234] = 39233,
    [50148] = 50147,
    [50151] = 50150,
    [50153] = 50152,
    [50155] = 50154,
    [23475] = 23474
}

-- Reverse lookup: unequipped ID -> equipped ID
DynamicItemsReverse = {}
for equippedId, unequippedId in pairs(DynamicItems) do
    DynamicItemsReverse[unequippedId] = equippedId
end

-- Returns the paired item ID (equipped<->unequipped), or nil if no pair exists.
function getDynamicPairId(itemId)
    if not itemId then return nil end
    if DynamicItems[itemId] then
        return DynamicItems[itemId]
    end
    if DynamicItemsReverse[itemId] then
        return DynamicItemsReverse[itemId]
    end
    return nil
end

-- Returns the equipped form ID for the given item ID.
-- If itemId is already an equipped form, returns itself.
function getEquippedItemId(itemId)
    if not itemId then return nil end
    if DynamicItems[itemId] then
        return itemId
    end
    return DynamicItemsReverse[itemId] or itemId
end

-- Returns the unequipped form ID for the given item ID.
-- If itemId is already an unequipped form, returns itself.
function getUnequippedItemId(itemId)
    if not itemId then return nil end
    if DynamicItemsReverse[itemId] then
        return itemId
    end
    return DynamicItems[itemId] or itemId
end

-- True if both IDs refer to the same logical item (equipped or unequipped form).
function isDynamicItemMatch(a, b)
    if not a or not b then return false end
    if a == b then return true end
    if DynamicItems[a] == b then return true end
    if DynamicItems[b] == a then return true end
    return false
end
