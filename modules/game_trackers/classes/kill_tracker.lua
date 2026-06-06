Tracker = Tracker or {}
Tracker.Prey = {}

local preyTracker = nil
local preyTrackerButton = nil
local restorePreyTrackerEvent = nil

local PREY_BONUS_DAMAGE_BOOST = 0
local PREY_BONUS_DAMAGE_REDUCTION = 1
local PREY_BONUS_XP_BONUS = 2
local PREY_BONUS_IMPROVED_LOOT = 3

local SLOT_STATE_LOCKED = 0
local SLOT_STATE_ACTIVE = 2

local function hasValidOutfit(outfit)
    if not outfit then
        return false
    end

    return (tonumber(outfit.type) or tonumber(outfit.lookType) or tonumber(outfit.auxType) or 0) > 0
end

function Tracker.Prey.getSmallIconPath(bonusType)
    local path = "/images/game/prey/"
    if bonusType == PREY_BONUS_DAMAGE_BOOST then
        return path .. "prey_damage"
    elseif bonusType == PREY_BONUS_DAMAGE_REDUCTION then
        return path .. "prey_defense"
    elseif bonusType == PREY_BONUS_XP_BONUS then
        return path .. "prey_xp"
    elseif bonusType == PREY_BONUS_IMPROVED_LOOT then
        return path .. "prey_loot"
    end
    return path .. "prey_no_bonus"
end

function Tracker.Prey.getExtendIcon(lockType)
    local path = "/images/game/prey/"
    local player = g_game.getLocalPlayer()
    if not player then
        return path .. "prey-auto-extend-disabled"
    end

    local balance = player:getResourceBalance(ResourceTypes.PREY_WILDCARDS)
    if lockType == 1 then
        return balance < 1 and (path .. "prey-auto-reroll-enabled-failing") or (path .. "prey-auto-reroll-enabled")
    elseif lockType == 2 then
        return balance < 5 and (path .. "prey-lock-prey-enabled-failing") or (path .. "prey-lock-prey-enabled")
    end
    return path .. "prey-auto-extend-disabled"
end

function Tracker.Prey.bonusTypeTranslate(bonusType)
    if bonusType == PREY_BONUS_DAMAGE_BOOST then
        return "Damage Boost"
    elseif bonusType == PREY_BONUS_DAMAGE_REDUCTION then
        return "Damage Reduction"
    elseif bonusType == PREY_BONUS_XP_BONUS then
        return "Bonus XP"
    elseif bonusType == PREY_BONUS_IMPROVED_LOOT then
        return "Improved Loot"
    end
    return "None"
end

function Tracker.Prey.bonusTypeTranslateText(bonusType, percent)
    local text = "No active bonus."
    if bonusType == PREY_BONUS_DAMAGE_BOOST then
        text = tr("You deal +%s%s extra damage against your prey creature.", percent, "%")
    elseif bonusType == PREY_BONUS_DAMAGE_REDUCTION then
        text = tr("You take %s%s less damage from your prey creature.", percent, "%")
    elseif bonusType == PREY_BONUS_XP_BONUS then
        text = tr("Killing you prey creature rewards +%s%s extra XP.", percent, "%")
    elseif bonusType == PREY_BONUS_IMPROVED_LOOT then
        text = tr("Your prey creature has a +%s%s chance do drop additional loot.", percent, "%")
    end
    return text
end

function Tracker.Prey.timeleftTranslation(timeleft)
    if timeleft == 0 then
        return "Free"
    end
    local hours = string.format('%02.f', math.floor(timeleft / 3600))
    local mins = string.format('%02.f', math.floor(timeleft / 60 - (hours * 60)))
    return hours .. ':' .. mins
end

function Tracker.Prey.getWidget()
    return preyTracker
end

function Tracker.Prey.getButton()
    return preyTrackerButton
end

function Tracker.Prey.init()
    preyTracker = g_ui.createWidget('PreyTracker')
    preyTracker:setup()

    preyTracker:setContentMinimumHeight(55)
    preyTracker:setContentMaximumHeight(350)

    local contextMenuButton = preyTracker:recursiveGetChildById('contextMenuButton')
    if contextMenuButton then
        contextMenuButton:setVisible(false)
    end
    local newWindowButton = preyTracker:recursiveGetChildById('newWindowButton')
    if newWindowButton then
        newWindowButton:setVisible(false)
    end
    local toggleFilterButton = preyTracker:recursiveGetChildById('toggleFilterButton')
    if toggleFilterButton then
        toggleFilterButton:setVisible(false)
    end

    local lockButton = preyTracker:recursiveGetChildById('lockButton')
    local minimizeButton = preyTracker:recursiveGetChildById('minimizeButton')
    if lockButton and minimizeButton then
        lockButton:setVisible(true)
        lockButton:breakAnchors()
        lockButton:addAnchor(AnchorTop, minimizeButton:getId(), AnchorTop)
        lockButton:addAnchor(AnchorRight, minimizeButton:getId(), AnchorLeft)
        lockButton:setMarginRight(2)
        lockButton:setMarginTop(0)
    end

    preyTracker:close(true)

    -- Initialize bounty slot as inactive
    Tracker.Bounty.setInactive()

    -- Initialize weekly slots as hidden
    Tracker.Weekly.clearAll()

    preyTracker.onOpen = function()
        if preyTrackerButton then
            preyTrackerButton:setOn(true)
        end
    end

    preyTracker.onClose = function()
        if preyTrackerButton then
            preyTrackerButton:setOn(false)
        end
    end

    Keybind.new("Windows", "Show/Hide kill tracker", "", "")
    Keybind.bind("Windows", "Show/Hide kill tracker", {
        {
            type = KEY_DOWN,
            callback = Tracker.Prey.toggle,
        }
    })
end

function Tracker.Prey.terminate()
    if restorePreyTrackerEvent then
        removeEvent(restorePreyTrackerEvent)
        restorePreyTrackerEvent = nil
    end

    Keybind.delete("Windows", "Show/Hide kill tracker")

    if preyTrackerButton then
        preyTrackerButton:destroy()
        preyTrackerButton = nil
    end
    if preyTracker then
        preyTracker:destroy()
        preyTracker = nil
    end
end

function Tracker.Prey.check()
    if g_game.getFeature(GamePrey) then
        if not preyTrackerButton then
            preyTrackerButton = modules.game_mainpanel.addToggleButton('preyTrackerButton', tr('Kill Tracker'),
                '/images/options/button_prey', Tracker.Prey.toggle, false, 9)
        end

        if restorePreyTrackerEvent then
            removeEvent(restorePreyTrackerEvent)
            restorePreyTrackerEvent = nil
        end
        restorePreyTrackerEvent = scheduleEvent(function()
            restorePreyTrackerEvent = nil
            if preyTracker and preyTracker.restorePosition then
                preyTracker:restorePosition()
            end
        end, 150)
    end
end

function Tracker.Prey.hide(dontSave)
    if restorePreyTrackerEvent then
        removeEvent(restorePreyTrackerEvent)
        restorePreyTrackerEvent = nil
    end

    preyTracker:close(dontSave or true)
    preyTracker:setParent(nil)
end

function Tracker.Prey.toggle()
    if preyTracker:isVisible() then
        preyTracker:close()
    else
        if not preyTracker:getParent() then
            local panel = modules.game_interface.findContentPanelAvailable(preyTracker, preyTracker:getMinimumHeight())
            if not panel then
                return
            end
            preyTracker:setParent(panel)
        end
        preyTracker:open()
    end
end

function Tracker.Prey.ensureVisible()
    if not preyTracker then
        return false
    end

    if preyTracker:isVisible() then
        return true
    end

    if not preyTracker:getParent() then
        local panel = modules.game_interface.findContentPanelAvailable(preyTracker, preyTracker:getMinimumHeight())
        if not panel then
            return false
        end
        preyTracker:setParent(panel)
    end

    preyTracker:open()
    return true
end

function Tracker.Prey.move(panel, height, minimized)
    preyTracker:setParent(panel)
    preyTracker:open()

    if minimized then
        preyTracker:setHeight(height)
        preyTracker:minimize()
    else
        preyTracker:maximize()
        preyTracker:setHeight(height)
    end
    return preyTracker
end

function Tracker.Prey.updateWidget(slot, state, currentHolderOutfit, preySlot, showCallback)
    local preyTrackerSlot = preyTracker.contentsPanel["slot" .. (slot + 1)]
    if state == SLOT_STATE_LOCKED then
        preyTrackerSlot:setVisible(false)
        return
    end

    if slot == 2 then
        preyTrackerSlot:setVisible(true)
        preyTracker:setContentMaximumHeight(195)
    end

    if state == SLOT_STATE_ACTIVE then
        local creatureAndBonus = preySlot.active.creatureAndBonus
        preyTrackerSlot.creature:setOutfit(currentHolderOutfit)
        preyTrackerSlot.creatureName:setText(short_text(preySlot.title:getText(), 12))
        preyTrackerSlot.time:setPercent(creatureAndBonus.timeLeft:getPercent())
        preyTrackerSlot.preyType:setImageSource(Tracker.Prey.getSmallIconPath(preySlot.bonusType))
        preyTrackerSlot.preyAutoExtend:setImageSource(Tracker.Prey.getExtendIcon(preySlot.lockType))
        preyTrackerSlot.creature:show()
        preyTrackerSlot.noCreature:hide()

        local preyName = preySlot.title:getText()
        local timeleft = Tracker.Prey.timeleftTranslation(preySlot.timeLeft)
        local typeDesc = Tracker.Prey.bonusTypeTranslate(preySlot.bonusType)
        local extendedDesc = preySlot.lockType == 0 and "false" or "true"
        local bonusDescription = Tracker.Prey.bonusTypeTranslateText(preySlot.bonusType, preySlot.bonusValue)
        local starBonus = tr("%d/%d stars", preySlot.bonusGrade, 10)

        local text =
        "Creature: %s\nDuration: %s\nValue: %s\nType: %s\nAutomatic Extend Prey: %s\n%s\n\nClick in this window to open the prey dialog."
        preyTrackerSlot:setTooltip(tr(text, preyName, timeleft, starBonus, typeDesc, extendedDesc, bonusDescription))
        preyTrackerSlot.onClick = function() showCallback() end
    else
        preyTrackerSlot.creature:hide()
        preyTrackerSlot.noCreature:show()
        preyTrackerSlot.creatureName:setText("Inactive")
        preyTrackerSlot.time:setPercent(0)
        preyTrackerSlot.preyAutoExtend:setImageSource(Tracker.Prey.getExtendIcon(preySlot.lockType))
        preyTrackerSlot.preyType:setImageSource(Tracker.Prey.getSmallIconPath(preySlot.bonusType))
        preyTrackerSlot:setTooltip(
            "Inactive Prey. \n\nUse the prey dialog to activate it. You can open the prey dialog by cliking in this window.")
        preyTrackerSlot.onClick = function() showCallback() end
    end
end

function Tracker.Prey.updateTimeLeft(slot, timeLeft)
    local preyTrackerSlot = preyTracker.contentsPanel["slot" .. (slot + 1)]
    local updatedTime = string.gsub(preyTrackerSlot:getTooltip(), "[^\n]*Duration: [^\n]*\n?",
        "Duration: " .. Tracker.Prey.timeleftTranslation(timeLeft) .. "\n")
    preyTrackerSlot:setTooltip(updatedTime)

    local percent = (timeLeft / (2 * 60 * 60)) * 100
    local slotId = "slot" .. (slot + 1)
    local tracker = preyTracker.contentsPanel[slotId]
    tracker.time:setPercent(percent)
end

-- Bounty Task Tracker
Tracker.Bounty = {}

function Tracker.Bounty.getSlot()
    return preyTracker.contentsPanel["bslot1"]
end

function Tracker.Bounty.setInactive()
    local slot = Tracker.Bounty.getSlot()
    if not slot then return end
    slot.creature:hide()
    slot.noCreature:show()
    slot.creatureName:setText("Inactive")
    slot.time:setPercent(0)
    slot.time:setBackgroundColor("#555555")
    slot:setTooltip("No active Bounty Task.\n\nClick to open the Bounty Task panel.")
    slot.onClick = function()
        if modules.game_task_hunt and modules.game_task_hunt.toggle then
            modules.game_task_hunt.toggle()
        end
    end
end

function Tracker.Bounty.setActive(name, outfit, killCount, killTarget)
    local slot = Tracker.Bounty.getSlot()
    if not slot then return end
    Tracker.Prey.ensureVisible()
    if hasValidOutfit(outfit) then
        slot.creature:setOutfit(outfit)
        slot.creature:show()
        slot.noCreature:hide()
    else
        slot.creature:hide()
        slot.noCreature:show()
    end
    slot.creatureName:setText(short_text(name, 12))
    local percent = killTarget > 0 and (killCount / killTarget) * 100 or 0
    slot.time:setPercent(percent)
    slot.time:setBackgroundColor("#C28400")
    slot:setTooltip(tr("Bounty Task: %s\nProgress: %d/%d kills\n\nClick to open the Bounty Task panel.", name, killCount,
        killTarget))
    slot.onClick = function()
        if modules.game_task_hunt and modules.game_task_hunt.toggle then
            modules.game_task_hunt.toggle()
        end
    end
end

function Tracker.Bounty.setCompleted(name, outfit, killCount, killTarget)
    local slot = Tracker.Bounty.getSlot()
    if not slot then return end
    Tracker.Prey.ensureVisible()
    if hasValidOutfit(outfit) then
        slot.creature:setOutfit(outfit)
        slot.creature:show()
        slot.noCreature:hide()
    else
        slot.creature:hide()
        slot.noCreature:show()
    end
    slot.creatureName:setText(short_text(name, 12))
    slot.time:setPercent(100)
    slot.time:setBackgroundColor("#00AA00")
    slot:setTooltip(tr("Bounty Task: %s\nProgress: %d/%d kills\nCompleted! Click to claim your reward.", name, killCount,
        killTarget))
    slot.onClick = function()
        if modules.game_task_hunt and modules.game_task_hunt.toggle then
            modules.game_task_hunt.toggle()
        end
    end
end

function Tracker.Bounty.onKillUpdate(raceId, currentKills, totalKills, isCompleted)
    local raceData = g_things.getRaceData(raceId)
    local name = raceData and raceData.name or 'Unknown'
    name = name:capitalize()
    local outfit = raceData and raceData.outfit or {}

    if isCompleted == 1 then
        Tracker.Bounty.setCompleted(name, outfit, currentKills, totalKills)
    else
        Tracker.Bounty.setActive(name, outfit, currentKills, totalKills)
    end
end

-- Weekly Task Tracker
Tracker.Weekly = {}
Tracker.Weekly.slots = {}

function Tracker.Weekly.getSlot(index)
    return preyTracker and preyTracker.contentsPanel["wslot" .. index]
end

function Tracker.Weekly.openWeeklyTab()
    if modules.game_task_hunt then
        if modules.game_task_hunt.show then
            modules.game_task_hunt.show()
        end
        if modules.game_task_hunt.selectTab then
            modules.game_task_hunt.selectTab(2)
        end
    end
end

function Tracker.Weekly.setSectionVisible(visible)
    if not preyTracker then return end
    local label = preyTracker.contentsPanel:recursiveGetChildById('weeklyTasksLabel')
    if label then label:setVisible(visible) end
    local sep = preyTracker.contentsPanel:recursiveGetChildById('weeklyTasksSeparator')
    if sep then sep:setVisible(visible) end
end

function Tracker.Weekly.setSlotInactive(index)
    local slot = Tracker.Weekly.getSlot(index)
    if not slot then return end
    slot.creature:hide()
    slot.anyCreatureIcon:hide()
    slot.noCreature:show()
    slot.creatureName:setText("Inactive")
    slot.time:setPercent(0)
    slot.time:setBackgroundColor("#555555")
    slot:setVisible(false)
end

function Tracker.Weekly.setSlotActive(index, raceId, name, outfit, currentKills, totalKills)
    local slot = Tracker.Weekly.getSlot(index)
    if not slot then return end

    if raceId == 0 then
        -- "Any Creature" slot
        slot.creature:hide()
        slot.anyCreatureIcon:show()
        slot.noCreature:hide()
        slot.creatureName:setText("Any Creature")
    else
        if hasValidOutfit(outfit) then
            slot.creature:setOutfit(outfit)
            slot.creature:show()
            slot.noCreature:hide()
        else
            slot.creature:hide()
            slot.noCreature:show()
        end
        slot.anyCreatureIcon:hide()
        slot.creatureName:setText(short_text(name, 12))
    end

    local percent = totalKills > 0 and (currentKills / totalKills) * 100 or 0
    slot.time:setPercent(percent)
    slot.time:setBackgroundColor("#C28400")
    slot:setTooltip(tr("Weekly Task: %s\nProgress: %d/%d kills", name, currentKills, totalKills))
    slot:setVisible(true)
    slot.onClick = function()
        Tracker.Weekly.openWeeklyTab()
    end
end

function Tracker.Weekly.setSlotCompleted(index, raceId, name, outfit, currentKills, totalKills)
    local slot = Tracker.Weekly.getSlot(index)
    if not slot then return end

    if raceId == 0 then
        slot.creature:hide()
        slot.anyCreatureIcon:show()
        slot.noCreature:hide()
        slot.creatureName:setText("Any Creature")
    else
        if hasValidOutfit(outfit) then
            slot.creature:setOutfit(outfit)
            slot.creature:show()
            slot.noCreature:hide()
        else
            slot.creature:hide()
            slot.noCreature:show()
        end
        slot.anyCreatureIcon:hide()
        slot.creatureName:setText(short_text(name, 12))
    end

    slot.time:setPercent(100)
    slot.time:setBackgroundColor("#00AA00")
    slot:setTooltip(tr("Weekly Task: %s\nProgress: %d/%d kills\nCompleted!", name, currentKills, totalKills))
    slot:setVisible(true)
    slot.onClick = function()
        Tracker.Weekly.openWeeklyTab()
    end
end

function Tracker.Weekly.clearAll()
    Tracker.Weekly.slots = {}
    for i = 1, 9 do
        Tracker.Weekly.setSlotInactive(i)
    end
    Tracker.Weekly.setSectionVisible(false)
end

function Tracker.Weekly.loadFromServerData(monsters)
    Tracker.Weekly.slots = {}
    if not monsters or #monsters == 0 then
        Tracker.Weekly.clearAll()
        return
    end

    Tracker.Prey.ensureVisible()
    Tracker.Weekly.setSectionVisible(true)

    for i, m in ipairs(monsters) do
        if i > 9 then break end
        local raceId = tonumber(m.raceId) or 0
        local current = tonumber(m.current) or 0
        local total = tonumber(m.total) or 0
        local finished = (tonumber(m.state) or 0) == 1

        local name = "Any Creature"
        local outfit = {}
        if raceId > 0 then
            local raceData = g_things.getRaceData(raceId)
            name = raceData and raceData.name or 'Unknown'
            name = name:capitalize()
            outfit = raceData and raceData.outfit or {}
        end

        Tracker.Weekly.slots[i] = { raceId = raceId, name = name, outfit = outfit }

        if finished then
            Tracker.Weekly.setSlotCompleted(i, raceId, name, outfit, current, total)
        else
            Tracker.Weekly.setSlotActive(i, raceId, name, outfit, current, total)
        end
    end

    -- Hide unused slots
    for i = #monsters + 1, 9 do
        local slot = Tracker.Weekly.getSlot(i)
        if slot then slot:setVisible(false) end
    end
end

function Tracker.Weekly.onKillUpdate(raceId, currentKills, totalKills, isCompleted)
    -- Find the slot matching this raceId
    for i, data in pairs(Tracker.Weekly.slots) do
        if data.raceId == raceId then
            if isCompleted == 1 then
                Tracker.Weekly.setSlotCompleted(i, raceId, data.name, data.outfit, currentKills, totalKills)
            else
                Tracker.Weekly.setSlotActive(i, raceId, data.name, data.outfit, currentKills, totalKills)
            end
            return
        end
    end
end
