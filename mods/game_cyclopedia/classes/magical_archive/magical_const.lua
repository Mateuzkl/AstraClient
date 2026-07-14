CombatMenuFields = {
    { widget = "manaInfo",        func = getSpellMana },
    { widget = "spellGroupInfo",  func = getSpellGroup },
    { widget = "basePowerInfo",   func = getSpellBasePower },
    { widget = "scalesWithInfo",  func = getSpellScaling },
    { widget = "cdInfo",          func = getSpellCooldown },
    { widget = "groupCdInfo",     func = getSpellGroupCooldown },
    { widget = "magicTypeInfo",   func = getSpellMagicType },
    { widget = "rangeInfo",       func = getSpellRange }
}

AutoAimDefaultSpells = {
    ["13"]  =  true, ["19"] = true, ["22"]  = true, ["23"]  = true,
    ["43"]  =  true, ["59"] = true, ["120"] = true, ["121"] = true,
    ["173"] = true, ["178"] = true, ["240"] = true, ["260"] = true,
    ["271"] = true, ["280"] = true, ["287"] = true, ["289"] = true, ["294"] = true
}

FilterListDefault = {
    ["charVocationFilter"] = true,
    ["charLevelFilter"] = false,
    ["learntSpellFilter"] = false,
    ["druidFilter"] = true,
    ["knightFilter"] = true,
    ["paladinFilter"] = true,
    ["sorcererFilter"] = true,
    ["monkFilter"] = true,
    ["allVocationsFilter"] = true,
    ["attackFilter"] = true,
    ["healingFilter"] = true,
    ["supportFilter"] = true,
    ["allSpellsFilter"] = true,
    ["premmyFilter"] = true,
    ["freeFilter"] = true,
    ["runeSpellsFilter"] = true,
    ["instantFilter"] = true
}

local SpellGroups = {
    ["SPELLGROUP_HEALING"] = "Healing",
    ["SPELLGROUP_ATTACK"] = "Attack",
    ["SPELLGROUP_SUPPORT"] = "Support",
    ["SPELLGROUP_STANCE"] = "Stance",
    ["SPELLGROUP_NONE"] = "None"
}

local MagicTypes = {
    ["DAMAGE_NONE"] = "None",
    ["DAMAGE_HIT"] = "Physical",
    ["DAMAGE_PHYSICAL"] = "Physical",
    ["DAMAGE_ENERGY"] = "Energy",
    ["DAMAGE_EARTH"] = "Earth",
    ["DAMAGE_EARTH_DOT"] = "Earth",
    ["DAMAGE_FIRE"] = "Fire",
    ["DAMAGE_FIRE_DOT"] = "Fire",
    ["DAMAGE_DEATH"] = "Death",
    ["DAMAGE_HOLY"] = "Holy",
    ["DAMAGE_HOLY_DOT"] = "Holy",
    ["DAMAGE_ICE"] = "Ice",
    ["DAMAGE_HEALING"] = "Healing",
}

function getDefaultFilter()
    local filter = {}
    for k, v in pairs(FilterListDefault) do
        filter[k] = v
    end
    return filter
end

function getRestrictedLevel(data)
    if data.level and data.level > 0 then
        return string.format("Level %d", data.level)
    end
    return "No Restriction"
end

function getVocationIconData(vocations)
    local vocationMap = {
        { name = "Knight", index = 0 },
        { name = "Paladin", index = 9 },
        { name = "Sorcerer", index = 18 },
        { name = "Druid", index = 27 },
        { name = "Monk", index = 36 }
    }

    local result = {}
    for _, voc in ipairs(vocationMap) do
        if table.contains(vocations, voc.name) then
            table.insert(result, { index = voc.index, name = voc.name })
        end
    end
    return result
end

function getSpellMana(data)
    if not data or not data.castCostMana then return "-" end
    return string.format("%d", data.castCostMana)
end

function getSpellGroup(data)
    if not data or not data.group then return "-" end
    for k, v in pairs(data.group) do
        return string.format("%s", SpellGroups[k] or k)
    end
    return "-"
end

function getSpellBasePower(data)
    if not data or not data.mean then return "-" end
    return string.format("%d", data.mean)
end

function getSpellScaling(data)
    if not data or not data.scaling then return "-" end
    return table.concat(data.scaling, ", ")
end

function getSpellCooldown(data)
    if not data or not data.cooldownSelf then return "-" end
    local totalSeconds = math.floor(data.cooldownSelf)
    local minutes = math.floor(totalSeconds / 60)
    local seconds = totalSeconds % 60
    if minutes > 0 then
        return string.format("%dmin %ds", minutes, seconds)
    else
        return string.format("%ds", seconds)
    end
end

function getSpellGroupCooldown(data)
    if not data or not data.cooldownPrimaryGroup then return "-" end
    local totalSeconds = math.floor(data.cooldownPrimaryGroup)
    local minutes = math.floor(totalSeconds / 60)
    local seconds = totalSeconds % 60
    if minutes > 0 then
        return string.format("%dmin %ds", minutes, seconds)
    else
        return string.format("%ds", seconds)
    end
end

function getSpellMagicType(data)
    if not data or not data.damagetype then
        return "-"
    end
    local magicType = MagicTypes[data.damagetype]
    return magicType or "-"
end

function getSpellRange(data)
    if not data or not data.range or data.range == 0 then return "-" end
    return string.format("%d sqm", data.range)
end

function getSpellSource(data)
    if not data then return "-" end
    if data.goldPrice and data.goldPrice > 0 then
        return "Spell Trainer For " .. data.goldPrice
    end
    if data.source and data.source ~= "" then
        return data.source:gsub("(%a)([%w_']*)", function(first, rest)
            return first:upper() .. rest:lower()
        end):gsub("_", " ")
    end
    return "-"
end

function getSpellLearnIn(data)
    if not data or not data.cities or type(data.cities) ~= "table" or #data.cities == 0 then return "-" end
    return table.concat(data.cities, ", ")
end

function getSpellDescription(data)
    if not data or not data.description then return "-" end
    return tostring(data.description)
end

function getSpellRuneParams(data)
    if not data or not data.runeParams or type(data.runeParams) ~= "table" or not data.runeParams.amount then
        return "-"
    end
    return tostring(data.runeParams.amount)
end

function getSpellManaAndSoul(data)
    if not data then return "-" end
    local mana = data.castCostMana or 0
    local soul = data.castCostSoulPoints or 0
    if mana == 0 and soul == 0 then return "-" end
    return string.format("%d / %d", mana, soul)
end

function getSpellLevel(data)
    if not data or not data.level then return "-" end
    return tostring(data.level)
end

function passesLevelFilter(spellLevel, playerLevel)
    local filter = MagicalArchive.temporaryFilter
    if filter.charLevelFilter then
        return spellLevel <= playerLevel
    end
    return true
end

function passesSpellGroupFilter(group)
    if table.empty(group) then
        return true
    end

    local filter = MagicalArchive.temporaryFilter
    if filter.allSpellsFilter then
        return true
    end

    local spellGroup = "None"
    for k, v in pairs(group) do
        spellGroup = SpellGroups[k] or k
        break
    end

    local activeFilters = {}
    if filter.attackFilter then table.insert(activeFilters, "Attack") end
    if filter.healingFilter then table.insert(activeFilters, "Healing") end
    if filter.supportFilter then table.insert(activeFilters, "Support") end

    return table.contains(activeFilters, spellGroup)
end

function passesVocationFilter(spellVocations, playerVocation)
    local filter = MagicalArchive.temporaryFilter

    local vocationMap = {
        ["Sorcerer"] = {1, 5},
        ["Druid"] = {2, 6},
        ["Paladin"] = {3, 7},
        ["Knight"] = {4, 8},
        ["Monk"] = {9, 10}
    }

    local filterMap = {
        [1] = "sorcererFilter",
        [2] = "druidFilter",
        [3] = "paladinFilter",
        [4] = "knightFilter",
        [5] = "sorcererFilter",
        [6] = "druidFilter",
        [7] = "paladinFilter",
        [8] = "knightFilter",
        [9] = "monkFilter",
        [10] = "monkFilter"
    }

    spellVocations = spellVocations or {}

    if filter.charVocationFilter then
        local playerVocationFilterKey = filterMap[playerVocation]
        if not filter[playerVocationFilterKey] then
            return false
        end

        for _, vocationName in ipairs(spellVocations) do
            local vocationIds = vocationMap[vocationName] or {}
            if table.contains(vocationIds, playerVocation) then
                return true
            end
        end
        return false
    else
        for _, vocationName in ipairs(spellVocations) do
            local vocationIds = vocationMap[vocationName] or {}
            for _, vocationId in ipairs(vocationIds) do
                local key = filterMap[vocationId]
                if filter[key] then
                    return true
                end
            end
        end
        return false
    end
end
