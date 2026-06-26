-- ZeroBot profile converter (healing, equipment, magicShooter -> helper format)
-- Reduces local variable count in helper.lua main chunk.
-- Usage: convertZerobotProfileToHelper(zb, env) where env has ensureHealingRule, ensureEquipmentSwapRule, createDefaultEquipmentSwapRule

local ZEROBOT_SLOT_AMULET = 2
local ZEROBOT_SLOT_AMULET_ALT = 3
local ZEROBOT_SLOT_RING = 9
local ZEROBOT_SLOT_RING_ALT = 10
local ZEROBOT_WHEN_HP = 2
local ZEROBOT_WHEN_MP = 3
local ZEROBOT_IS_BELOW = 0
local ZEROBOT_IS_ABOVE = 1

local function presetName(n)
    return string.format("Preset %d", n)
end

local function oneHealingRule(r, i, env)
    local ensureHealingRule = env.ensureHealingRule
    local metric1 = (tonumber(r.whenCondition) == ZEROBOT_WHEN_MP) and "MP%" or "HP%"
    local op1 = (tonumber(r.isCondition) == ZEROBOT_IS_ABOVE) and ">=" or "<="
    local val1 = tonumber(r.isConditionValue) or tonumber(tostring(r.isConditionValue):match("%d+")) or 80
    local metric2 = (tonumber(r.whenSecondCondition) == ZEROBOT_WHEN_MP) and "MP%" or "HP%"
    local op2 = (tonumber(r.isSecondCondition) == ZEROBOT_IS_ABOVE) and ">=" or "<="
    local val2 = tonumber(r.isSecondConditionValue) or 100
    local join = (r.whenConditionAnd == true) and "and" or "none"
    if r.isSecondCondition == nil and r.whenSecondCondition == nil then
        join = "none"
    end
    return ensureHealingRule({
        enabled = true,
        actionType = (r.isItem == true) and "Item" or "Spell",
        spellWords = (r.isItem == true) and "" or (tostring(r.itemSpell or ""):gsub("^%s+", ""):gsub("%s+$", "")),
        itemId = tonumber(r.itemId) or (r.isItem and tonumber(tostring(r.itemSpell):match("%d+")) or 0) or 0,
        itemCount = 0,
        whenMetric1 = metric1,
        whenOperator1 = op1,
        whenValue1 = math.max(0, math.min(100, val1)),
        joinMode = join,
        whenMetric2 = metric2,
        whenOperator2 = op2,
        whenValue2 = math.max(0, math.min(100, val2)),
        manaMin = tonumber(r.manaCost) or 0,
        conditionDrunk = r.drunkCondition == true,
        conditionRooted = r.rootedCondition == true,
        conditionFeared = r.fearedCondition == true,
        dontCastIfTargetingMonster = r.dontCastTargetMonster == true,
        orderPriority = i
    }, i)
end

local function convertHealing(zb, env)
    local h = zb.healing
    if type(h) ~= "table" then
        return nil
    end
    -- Formato novo: healingList com 10 presets; cada list[i] = array de regras
    if type(h.healingList) == "table" then
        local profiles = {}
        local labels = {}
        local selectedIdx = (tonumber(h.profileSelected) or 0) + 1
        local profileNames = type(h.profileNames) == "table" and h.profileNames or {}
        for slot = 1, 10 do
            local arr = h.healingList[slot]
            local rules = {}
            if type(arr) == "table" then
                for i, r in ipairs(arr) do
                    if type(r) == "table" and (r.enabled == true or r.enabled == nil) then
                        table.insert(rules, oneHealingRule(r, i, env))
                    end
                end
            end
            local name = presetName(slot)
            profiles[name] = { healingRules = rules, navigationEnabled = true }
            labels[name] = profileNames[slot] and tostring(profileNames[slot]) or name
        end
        return {
            healingProfiles = profiles,
            healingPresetLabels = labels,
            selectedHealingProfile = presetName(selectedIdx),
            healingRules = profiles[presetName(selectedIdx)] and profiles[presetName(selectedIdx)].healingRules or {}
        }
    end
    -- Formato antigo: healing = array de regras (um so preset)
    local arr = h
    local out = {}
    if type(arr) == "table" then
        for i, r in ipairs(arr) do
            if type(r) == "table" and (r.enabled == true or r.enabled == nil) then
                table.insert(out, oneHealingRule(r, i, env))
            end
        end
    end
    return { healingRules = out }
end

local function oneEquipmentRule(r, i, ensureEquipmentSwapRule)
    local whenHp = tonumber(r.whenCondition) == 3
    local whenMp = tonumber(r.whenCondition) == 2
    local isAbove = tonumber(r.isCondition) == ZEROBOT_IS_ABOVE
    local val = tonumber(r.isConditionValue) or 95
    val = math.max(0, math.min(100, val))
    local slot = tonumber(r.clothSlot) or 9
    local rule = {
        id = tonumber(r.itemId) or 0,
        percent = val,
        enabled = true,
        priority = i,
        mode = isAbove and "above" or "below",
        sourceType = (tonumber(r.fromType) == 1) and "Backpack" or "Hotkey",
        actionType = (tonumber(r.actionType) == 1) and "Unequip" or "Equip",
        dontExecuteIfEquipped = r.dontExecuteIfEquipped == true,
        dontExecuteItemId = 0,
        dontExecuteItemIds = { 0, 0 },
        tier = tonumber(r.tier) or 0,
        conditionDrunk = r.drunkCondition == true,
        conditionRooted = r.rootedCondition == true,
        conditionFeared = r.fearedCondition == true,
        conditionParalyzed = r.paralyzedCondition == true,
        conditionPz = r.protectionZoneCondition ~= false,
        conditionNonPz = true,
        equipIfHPBelowEnabled = whenHp and not isAbove,
        equipIfHPBelow = whenHp and not isAbove and val or 0,
        equipIfHPAboveEnabled = whenHp and isAbove,
        equipIfHPAbove = whenHp and isAbove and val or 0,
        equipIfMPBelowEnabled = whenMp and not isAbove,
        equipIfMPBelow = whenMp and not isAbove and val or 0,
        equipIfMPAboveEnabled = whenMp and isAbove,
        equipIfMPAbove = whenMp and isAbove and val or 0,
        conditionJoinMode = "none",
        conditionUseAnd = false,
        alwaysEquipIfNone = false,
        excludeAmuletIds = { 0, 0 },
        excludeRingIds = { 0, 0 },
        respectEnergyRing = false
    }
    local rings, amulets = {}, {}
    if slot == ZEROBOT_SLOT_AMULET or slot == ZEROBOT_SLOT_AMULET_ALT then
        table.insert(amulets, ensureEquipmentSwapRule(rule, "amulet", 1))
    elseif slot == ZEROBOT_SLOT_RING or slot == ZEROBOT_SLOT_RING_ALT then
        table.insert(rings, ensureEquipmentSwapRule(rule, "ring", 1))
    end
    return rings, amulets
end

local function convertEquipment(zb, env)
    local eq = zb.equipment
    if type(eq) ~= "table" or type(eq.equipmentList) ~= "table" then
        return nil
    end
    local ensureEquipmentSwapRule = env.ensureEquipmentSwapRule
    local selectedIdx = (tonumber(eq.profileSelected) or 0) + 1
    local profileNames = type(eq.profileNames) == "table" and eq.profileNames or {}
    local profiles = {}
    local labels = {}
    for slot = 1, 10 do
        local list = eq.equipmentList[slot]
        local rings, amulets = {}, {}
        if type(list) == "table" then
            for i, r in ipairs(list) do
                if type(r) == "table" and r.enabled and r.itemId and tonumber(r.itemId) > 0 then
                    local rng, amu = oneEquipmentRule(r, i, ensureEquipmentSwapRule)
                    for _, x in ipairs(rng) do table.insert(rings, x) end
                    for _, x in ipairs(amu) do table.insert(amulets, x) end
                end
            end
        end
        local name = presetName(slot)
        profiles[name] = { rings = rings, amulets = amulets, navigationEnabled = true }
        labels[name] = profileNames[slot] and tostring(profileNames[slot]) or name
    end
    local selName = presetName(selectedIdx)
    local sel = profiles[selName]
    return {
        equipmentProfiles = profiles,
        equipmentPresetLabels = labels,
        selectedEquipmentProfile = selName,
        rings = sel and sel.rings or {},
        amulets = sel and sel.amulets or {}
    }
end

local function oneShooterPreset(list)
    if type(list) ~= "table" then
        return nil
    end
    local spells = {}
    local runes = {}
    for i, entry in ipairs(list) do
        if type(entry) ~= "table" or not entry.enabled then
            goto continue
        end
        local spellType = tonumber(entry.spellType) or 4
        local runeId = tonumber(entry.runeId) or 0
        local words = tostring(entry.spellWords or ""):gsub("^%s+", ""):gsub("%s+$", "")
        -- ZeroBot: spellType 0 ou 1 = rune; 2, 3, 4 = spell. Quando for rune, id vem de runeId ou de spellWords no formato "NNNNs"
        local isRuneType = (spellType == 0 or spellType == 1)
        if isRuneType then
            if runeId <= 0 and words ~= "" then
                local idFromWords = words:match("^(%d+)s$")
                if idFromWords then runeId = tonumber(idFromWords) or 0 end
            end
        end
        if isRuneType and runeId > 0 then
            table.insert(runes, {
                id = runeId,
                creatures = tonumber(entry.creaturesCount) or 1,
                priority = i,
                forceCast = false,
                enabled = true,
                needTarget = false,
                prioritizeOverPotion = true
            })
        else
            local spellId = 0
            if Spells and (words and words ~= "") and (Spells.getSpellByWords or Spells.getSpellByName) then
                local ok, s = pcall(function()
                    local r = Spells.getSpellByWords and Spells.getSpellByWords(words) or nil
                    if r then return (type(r) == "table" and r) or nil end
                    if Spells.getSpellByName then
                        r = Spells.getSpellByName(words)
                        return (type(r) == "table" and r) or nil
                    end
                    return nil
                end)
                if ok and s and s.id then
                    spellId = s.id
                end
            end
            local isPlaceholder = (words == "" or words == "spell words" or not words:find("%s"))
            if spellId > 0 or (not isPlaceholder and words ~= "") then
                table.insert(spells, {
                    id = spellId ~= 0 and spellId or -1,
                    percent = 100,
                    creatures = tonumber(entry.creaturesCount) or 1,
                    priority = i,
                    forceCast = false,
                    selfCast = false,
                    enabled = true,
                    customText = (spellId == 0 or spellId == -1) and words or "",
                    cooldown = tonumber(entry.delayMs) or 2000,
                    minHarmony = 0,
                    needTarget = entry.targetRequired == true
                })
            end
        end
        ::continue::
    end
    if #spells == 0 and #runes == 0 then
        return nil
    end
    while #spells < 1 do
        table.insert(spells, { id = 0, percent = 100, creatures = 1, priority = #spells + 1, forceCast = false, selfCast = false, enabled = false, customText = "", cooldown = 2000, minHarmony = 0, needTarget = false })
    end
    while #runes < 1 do
        table.insert(runes, {
            id = 0,
            creatures = 1,
            priority = #runes + 1,
            forceCast = false,
            enabled = false,
            needTarget = false,
            prioritizeOverPotion = true
        })
    end
    return { spells = spells, runes = runes, navigationEnabled = true }
end

-- ZeroBot cooldownType: 1 = minutes, 2 = hours
local ZEROBOT_TIMER_MINUTES = 1
local ZEROBOT_TIMER_HOURS = 2

-- ZeroBot autoSio = heal friend (SIO). autoSioList = friend names, autoSioVoc* = vocation settings
local ZEROBOT_VOC_TO_HELPER_BASE = { [4] = "4", [3] = "3", [1] = "1", [2] = "2", [5] = "5" }
local ZEROBOT_VOC_TO_HELPER_PROMO = { [4] = "8", [3] = "7", [1] = "5", [2] = "6", [5] = "5" }

local function convertHealFriend(zb)
    local sio = zb.autoSio
    if type(sio) ~= "table" then
        return nil
    end
    local list = type(sio.autoSioList) == "table" and sio.autoSioList or {}
    local defaultPercent = 90
    local friendhealing = {}
    for i = 1, 5 do
        local name = list[i] and tostring(list[i]):gsub("^%s+", ""):gsub("%s+$", "") or ""
        friendhealing[i] = {
            name = name,
            percent = (name ~= "" and defaultPercent) or 0,
            enabled = name ~= "" and (sio.autoSioEnabled == true)
        }
    end
    local vocationPercent = {}
    local vocationPriority = {}
    for vid = 1, 10 do
        vocationPercent[tostring(vid)] = 90
    end
    for i = 0, 4 do
        local voc = tonumber(sio["autoSioVocVocation" .. i])
        local pct = tonumber(sio["autoSioVocSioPercent" .. i])
        local pri = tonumber(sio["autoSioVocPriority" .. i])
        if voc then
            local base = ZEROBOT_VOC_TO_HELPER_BASE[voc]
            local promo = ZEROBOT_VOC_TO_HELPER_PROMO[voc]
            if base then vocationPercent[base] = (pct and math.max(0, math.min(100, pct))) or 90 end
            if promo then vocationPercent[promo] = (pct and math.max(0, math.min(100, pct))) or 90 end
            if pri and base then vocationPriority[base] = math.max(1, math.min(5, pri)) end
            if pri and promo then vocationPriority[promo] = math.max(1, math.min(5, pri)) end
        end
    end
    return {
        healFriendEnabled = sio.autoSioEnabled == true,
        friendhealing = friendhealing,
        friendhealingParty = false,
        friendhealingGuild = false,
        friendhealingScreen = false,
        friendhealingVocationPercent = vocationPercent,
        friendhealingVocationPriority = vocationPriority
    }
end

local function convertTimers(zb)
    local t = zb.timer
    if type(t) ~= "table" or type(t.timerList) ~= "table" then
        return nil
    end
    local rules = {}
    for i, entry in ipairs(t.timerList) do
        if type(entry) == "table" then
            local cooldown = tonumber(entry.cooldown) or 1
            local cooldownType = tonumber(entry.cooldownType) or ZEROBOT_TIMER_MINUTES
            local intervalSec = cooldown * (cooldownType == ZEROBOT_TIMER_HOURS and 3600 or 60)
            if intervalSec < 1 then intervalSec = 1 end
            if intervalSec > 86400 then intervalSec = 86400 end
            local unit = "Minutes"
            if intervalSec >= 3600 and intervalSec % 3600 == 0 then
                unit = "Hours"
            elseif intervalSec % 60 ~= 0 then
                unit = "Seconds"
            end
            local isItem = entry.isItem == true
            table.insert(rules, {
                enabled = entry.enabled == true,
                interval = intervalSec,
                cooldownUnit = unit,
                actionType = isItem and "Item" or "Texto",
                itemId = isItem and (tonumber(entry.itemId) or 0) or 0,
                itemCount = 0,
                chatText = not isItem and tostring(entry.itemWords or ""):gsub("^%s+", ""):gsub("%s+$", "") or "",
                runInPz = true,
                runOutPz = true,
                lastExecution = 0
            })
        end
    end
    if #rules == 0 then
        return nil
    end
    return {
        timerEnabled = t.timerEnabled == true,
        timers = rules
    }
end

local function convertShooter(zb)
    local ms = zb.magicShooter
    if type(ms) ~= "table" or type(ms.list) ~= "table" then
        return nil
    end
    local selectedIdx = (tonumber(ms.profileSelected) or 0) + 1
    local profileNames = type(ms.profileNames) == "table" and ms.profileNames or {}
    local profiles = {}
    local labels = {}
    for slot = 1, 10 do
        local list = ms.list[slot]
        local preset = oneShooterPreset(list)
        local name = presetName(slot)
        profiles[name] = preset or { spells = {}, runes = {}, navigationEnabled = true }
        labels[name] = profileNames[slot] and tostring(profileNames[slot]) or name
    end
    local selName = presetName(selectedIdx)
    return {
        shooterProfiles = profiles,
        shooterPresetLabels = labels,
        selectedShooterProfile = selName
    }
end

function convertZerobotProfileToHelper(zb, env)
    if type(zb) ~= "table" then
        return nil
    end
    local healingEnabled = (zb.healing and zb.healing.healingEnabled == true) or zb.healingEnabled == true
    local out = {
        healingEnabled = healingEnabled,
        autoHealingEnabled = healingEnabled
    }

    local healingResult = convertHealing(zb, env)
    if healingResult then
        if healingResult.healingProfiles then
            out.healingProfiles = healingResult.healingProfiles
            out.healingPresetLabels = healingResult.healingPresetLabels or {}
            out.selectedHealingProfile = healingResult.selectedHealingProfile or presetName(1)
            out.healingRules = healingResult.healingRules or {}
        else
            out.healingRules = healingResult.healingRules or {}
        end
    end

    local eqResult = convertEquipment(zb, env)
    if eqResult then
        out.equipmentProfiles = eqResult.equipmentProfiles
        out.equipmentPresetLabels = eqResult.equipmentPresetLabels or {}
        out.selectedEquipmentProfile = eqResult.selectedEquipmentProfile or presetName(1)
        out.rings = eqResult.rings or {}
        out.amulets = eqResult.amulets or {}
        if zb.equipment and zb.equipment.equipmentEnabled == true then
            out.equipmentEnabled = true
            out.equipmentSwapEnabled = true
        end
    end

    local shooterResult = convertShooter(zb)
    if shooterResult and (zb.magicShooter == nil or zb.magicShooter.enabled ~= false) then
        out.shooterProfiles = shooterResult.shooterProfiles or {}
        out.shooterPresetLabels = shooterResult.shooterPresetLabels or {}
        out.selectedShooterProfile = shooterResult.selectedShooterProfile or presetName(1)
        out.magicShooterEnabled = true
    end

    local timerResult = convertTimers(zb)
    if timerResult then
        out.timerEnabled = timerResult.timerEnabled
        out.timers = timerResult.timers
    end

    local healFriendResult = convertHealFriend(zb)
    if healFriendResult then
        out.healFriendEnabled = healFriendResult.healFriendEnabled
        out.friendhealing = healFriendResult.friendhealing
        out.friendhealingParty = healFriendResult.friendhealingParty
        out.friendhealingGuild = healFriendResult.friendhealingGuild
        out.friendhealingScreen = healFriendResult.friendhealingScreen
        out.friendhealingVocationPercent = healFriendResult.friendhealingVocationPercent
        out.friendhealingVocationPriority = healFriendResult.friendhealingVocationPriority
    end

    return out
end

return convertZerobotProfileToHelper
