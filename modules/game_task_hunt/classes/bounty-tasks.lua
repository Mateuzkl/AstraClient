TaskBounty = {}

-- Action types (must match BountyActionType on server)
local ACTION_REROLL = 0
local ACTION_SELECT = 1
local ACTION_CLAIM_REWARD = 2
local ACTION_CHANGE_DIFFICULTY = 3
local ACTION_CLAIM_DAILY = 5

local TALISMAN_ICONS = {
    [1] = '/images/game/task_hunt/icon-bountyring-damageagainstmonster',
    [2] = '/images/game/task_hunt/icon-bountyring-lifeleech',
    [3] = '/images/game/task_hunt/icon-bountyring-moreloot',
    [4] = '/images/game/task_hunt/icon-bountyring-doublebestiarychance',
}

local TALISMAN_TITLES = {
    [1] = 'Damage Against\nCreatures',
    [2] = 'Life Leech',
    [3] = 'More Loot',
    [4] = 'Chance for Double\nBeast Scroll Progress',
}

function TaskBounty.formatPercent(value)
    if value == math.floor(value) then
        return string.format('%.1f', value)
    elseif value * 10 == math.floor(value * 10) then
        return string.format('%.1f', value)
    else
        return string.format('%.2f', value)
    end
end

function TaskBounty.init()
    -- Data will come from server via onServerData
end

local ACTION_REQUEST = 4

function TaskBounty.requestRefresh()
    g_game.bountyTaskAction(ACTION_REQUEST, 0)
end

function TaskBounty.updateTracker(monsters)
    if not Tracker or not Tracker.Bounty then return end

    local activeMonster = nil
    for _, m in ipairs(monsters) do
        if tonumber(m.isActive) == 1 then
            activeMonster = m
            break
        end
    end

    if not activeMonster then
        Tracker.Bounty.setInactive()
        return
    end

    local raceId = tonumber(activeMonster.raceId) or 0
    local currentKills = tonumber(activeMonster.currentKills) or 0
    local totalKills = tonumber(activeMonster.totalKills) or 0
    local isCompleted = (currentKills >= totalKills) and 1 or 0

    Tracker.Bounty.onKillUpdate(raceId, currentKills, totalKills, isCompleted)
end

function TaskBounty.onServerData(header, monsters, talisman)
    -- Always update the kill tracker
    TaskBounty.updateTracker(monsters)

    if not taskHuntWindow then return end

    -- Header data
    local rerollPoints = tonumber(header.rerollPoints) or 0
    local claimDaily = tonumber(header.claimDaily) or 0
    -- Populate monster panels
    local container = taskHuntWindow:recursiveGetChildById('bountyTaskContainer')
    if container then
        local monsterCount = #monsters

        if monsterCount == 1 then
            -- Single monster (active task): use center panel (taskPanel2)
            local panel1 = container:recursiveGetChildById('taskPanel1')
            local panel2 = container:recursiveGetChildById('taskPanel2')
            local panel3 = container:recursiveGetChildById('taskPanel3')
            if panel1 then panel1:setVisible(false) end
            if panel3 then panel3:setVisible(false) end
            if panel2 then
                local m = monsters[1]
                TaskBounty.populateTaskPanel(panel2, {
                    raceId = tonumber(m.raceId) or 0,
                    currentKills = tonumber(m.currentKills) or 0,
                    totalKills = tonumber(m.totalKills) or 0,
                    rarity = tonumber(m.rarity) or 0,
                    isCompleted = tonumber(m.isCompleted) == 1,
                    isActive = tonumber(m.isActive) == 1,
                    rewardXp = tonumber(m.rewardXp) or 0,
                    rewardPoints = tonumber(m.rewardPoints) or 0,
                    rewardReroll = tonumber(m.rewardReroll) or 0,
                })
                panel2:setVisible(true)
            end
        else
            -- Multiple monsters: fill panels 1-3 normally
            for i = 1, 3 do
                local panel = container:recursiveGetChildById('taskPanel' .. i)
                if panel then
                    if monsters[i] then
                        local m = monsters[i]
                        TaskBounty.populateTaskPanel(panel, {
                            raceId = tonumber(m.raceId) or 0,
                            currentKills = tonumber(m.currentKills) or 0,
                            totalKills = tonumber(m.totalKills) or 0,
                            rarity = tonumber(m.rarity) or 0,
                            isCompleted = tonumber(m.isCompleted) == 1,
                            isActive = tonumber(m.isActive) == 1,
                            rewardXp = tonumber(m.rewardXp) or 0,
                            rewardPoints = tonumber(m.rewardPoints) or 0,
                            rewardReroll = tonumber(m.rewardReroll) or 0,
                        })
                        panel:setVisible(true)
                    else
                        panel:setVisible(false)
                    end
                end
            end
        end
    end

    -- Populate talisman entries
    local talismanWindow = taskHuntWindow:recursiveGetChildById('bountyTalismanWindow')
    if talismanWindow then
        for i = 1, 4 do
            local entry = talismanWindow:recursiveGetChildById('talismanEntry' .. i)
            if entry and talisman[i] then
                local s = talisman[i]
                local currentValue = (tonumber(s.currentValue) or 0) / 100
                local nextValue = (tonumber(s.nextValue) or 0) / 100
                local upgradeCost = tonumber(s.upgradeCost) or 0
                local isMaxed = nextValue == 0 and upgradeCost == 0

                TaskBounty.populateTalismanEntry(entry, {
                    icon = TALISMAN_ICONS[i],
                    title = TALISMAN_TITLES[i],
                    current = string.format('Current: %s%%', TaskBounty.formatPercent(currentValue)),
                    buttonText = isMaxed and 'MAX' or
                        string.format('Upgrade to %s %%', TaskBounty.formatPercent(nextValue)),
                    cost = upgradeCost,
                    statType = i - 1, -- 0-indexed for server
                    isMaxed = isMaxed,
                })
            end
        end
    end

    -- Claim daily
    local claimLabel = taskHuntWindow:recursiveGetChildById('claimDailyLabel')
    if claimLabel then
        claimLabel:setText(tostring(rerollPoints))
    end

    -- Reroll points
    local rerollLabel = taskHuntWindow:recursiveGetChildById('rerollPointsLabel')
    if rerollLabel then
        rerollLabel:setText(tostring(rerollPoints))
    end

    -- Reroll button (disabled if no reroll points)
    local rerollBtn = taskHuntWindow:recursiveGetChildById('rerollTasks')
    if rerollBtn then
        rerollBtn:setEnabled(rerollPoints > 0)
        rerollBtn.onClick = function()
            TaskBounty.rerollMonsters()
        end
    end

    -- Claim daily warning icon (visible when reroll tokens are capped at 10)
    local claimWarning = taskHuntWindow:recursiveGetChildById('claimDailyWarning')
    if claimWarning then
        claimWarning:setVisible(rerollPoints >= 10)
    end

    -- Claim daily button (enabled if claimDaily available AND reroll points < 10)
    local claimDailyBtn = taskHuntWindow:recursiveGetChildById('claimDaily')
    if claimDailyBtn then
        claimDailyBtn:setEnabled(claimDaily == 1 and rerollPoints < 10)
        claimDailyBtn.onClick = function()
            TaskBounty.claimDaily()
        end
    end

    -- Boost Kills button - opens store searching for the bounty double kill offer
    local boostKillsBtn = taskHuntWindow:recursiveGetChildById('boostKills')
    if boostKillsBtn then
        boostKillsBtn.onClick = function()
            modules.game_store.show()
            scheduleEvent(function()
                local storeUI = modules.game_store.controllerShop and modules.game_store.controllerShop.ui
                if storeUI and storeUI.SearchEdit then
                    storeUI.SearchEdit:setText('Bounty Double Kill Boost')
                    modules.game_store.search()
                end
            end, 500)
        end
    end

    -- Difficulty combobox
    local difficulty = tonumber(header.difficulty) or 1
    local difficultyCombo = taskHuntWindow:recursiveGetChildById('difficultyComboBox')
    if difficultyCombo then
        TaskBounty._updatingDifficulty = true
        difficultyCombo:setCurrentIndex(difficulty)
        TaskBounty._updatingDifficulty = false
        difficultyCombo.onOptionChange = TaskBounty.onDifficultyChanged
    end
end

function TaskBounty.onDifficultyChanged(widget)
    if TaskBounty._updatingDifficulty then return end
    local index = widget:getCurrentIndex()
    if index and index >= 1 then
        TaskBounty.changeDifficulty(index)
    end
end

local RARITY_BACKDROPS = {
    [0] = '/images/game/task_hunt/backdrop_tasksystem_normal_task',
    [1] = '/images/game/task_hunt/backdrop_tasksystem_silver_task',
    [2] = '/images/game/task_hunt/backdrop_tasksystem_gold_task',
}

function TaskBounty.populateTaskPanel(panel, data)
    local raceId = data.raceId or 0
    local rarity = data.rarity or 0

    -- Backdrop image and size based on rarity
    local backdrop = panel:recursiveGetChildById('backdrop')
    if backdrop then
        backdrop:setImageSource(RARITY_BACKDROPS[rarity] or RARITY_BACKDROPS[0])
        backdrop:setSize({ width = 279, height = rarity > 0 and 44 or 38 })
    end

    local backdropLabel = panel:recursiveGetChildById('backdropLabel')
    if backdropLabel then
        local raceData = g_things.getRaceData(raceId)
        local name = raceData and raceData.name or 'Unknown'
        name = name:capitalize()
        if #name > 20 then
            name = name:sub(1, 20) .. '...'
        end
        backdropLabel:setText(name)
        backdropLabel:setMarginTop(rarity > 0 and 0 or 2)
        backdropLabel:setMarginLeft(rarity > 0 and 20 or 0)
    end

    local previewPanel = panel:recursiveGetChildById('previewPanel')
    if previewPanel then
        -- Adjust margin-top to compensate for taller backdrop on rarity > 0
        previewPanel:setMarginTop(rarity > 0 and 6 or 12)
    end

    local creature = panel:recursiveGetChildById('creature')
    if creature and raceId > 0 then
        local raceData = g_things.getRaceData(raceId)
        if raceData and raceData.outfit then
            creature:setOutfit(raceData.outfit)
        end
        if raceData and raceData.name then
            creature:setTooltip(raceData.name:capitalize())
        end
    end

    local killsLabel = panel:recursiveGetChildById('killsLabel')
    if killsLabel then
        killsLabel:setText(string.format('%d / %d kills', data.currentKills, data.totalKills))
    end

    -- Reward labels
    local rewardXpLabel = panel:recursiveGetChildById('rewardXpLabel')
    if rewardXpLabel then
        rewardXpLabel:setText(string.format('%s XP', comma_value(data.rewardXp) or 0))
    end

    local rewardPointsLabel = panel:recursiveGetChildById('rewardPointsLabel')
    if rewardPointsLabel then
        rewardPointsLabel:setText(tostring(data.rewardPoints or 0))
    end

    local rewardRerollLabel = panel:recursiveGetChildById('rewardRerollLabel')
    if rewardRerollLabel then
        rewardRerollLabel:setText(tostring(data.rewardReroll or 0))
    end

    -- Action button
    local selectBtn = panel:recursiveGetChildById('selectTaskButton')
    if selectBtn then
        if data.isCompleted then
            -- Already completed and reward claimed
            selectBtn:setText('Completed')
            selectBtn:setEnabled(false)
            selectBtn.onClick = nil
        elseif data.isActive and data.currentKills >= data.totalKills then
            -- Task done, ready to claim
            selectBtn:setText('Claim Reward')
            selectBtn:setEnabled(true)
            selectBtn.onClick = function()
                TaskBounty.claimReward(raceId)
            end
        elseif data.isActive then
            -- Active but not finished yet
            selectBtn:setText('Claim Reward')
            selectBtn:setEnabled(false)
            selectBtn.onClick = nil
        else
            -- Not selected yet
            selectBtn:setText('Select Task')
            selectBtn:setEnabled(true)
            selectBtn.onClick = function()
                TaskBounty.selectTask(raceId)
            end
        end
    end
end

function TaskBounty.populateTalismanEntry(entry, data)
    local icon = entry:recursiveGetChildById('entryIcon')
    if icon then
        icon:setImageSource(data.icon)
    end

    local title = entry:recursiveGetChildById('entryTitle')
    if title then
        title:setText(data.title)
    end

    local currentLabel = entry:recursiveGetChildById('entryCurrentLabel')
    if currentLabel then
        currentLabel:setText(data.current)
    end

    local button = entry:recursiveGetChildById('entryUpgradeButton')
    if button then
        button:setText(data.buttonText)
        button:setEnabled(not data.isMaxed)
        if not data.isMaxed then
            button.onClick = function()
                g_game.bountyTalismanUpgrade(data.statType)
            end
        end
    end

    local costLabel = entry:recursiveGetChildById('costLabel')
    if costLabel then
        costLabel:setText(data.isMaxed and '-' or tostring(data.cost))
    end
end

function TaskBounty.onKillUpdate(raceId, currentKills, totalKills, isCompleted)
    -- Update kill tracker
    if Tracker and Tracker.Bounty then
        Tracker.Bounty.onKillUpdate(raceId, currentKills, totalKills, isCompleted)
    end

    -- Update bounty task panel kills label (if open)
    if taskHuntWindow then
        local container = taskHuntWindow:recursiveGetChildById('bountyTaskContainer')
        if container then
            for i = 1, 3 do
                local panel = container:recursiveGetChildById('taskPanel' .. i)
                if panel and panel:isVisible() then
                    local killsLabel = panel:recursiveGetChildById('killsLabel')
                    if killsLabel then
                        killsLabel:setText(string.format('%d / %d kills', currentKills, totalKills))
                    end

                    local selectBtn = panel:recursiveGetChildById('selectTaskButton')
                    if selectBtn and isCompleted == 1 then
                        selectBtn:setText('Claim Reward')
                        selectBtn:setEnabled(true)
                        selectBtn.onClick = function()
                            TaskBounty.claimReward(raceId)
                        end
                    end
                end
            end
        end
    end
end

-- Action helpers for UI buttons
function TaskBounty.rerollMonsters()
    g_game.bountyTaskAction(ACTION_REROLL, 0)
end

function TaskBounty.selectTask(raceId)
    g_game.bountyTaskAction(ACTION_SELECT, raceId)
end

function TaskBounty.claimReward(raceId)
    g_game.bountyTaskAction(ACTION_CLAIM_REWARD, raceId)
end

function TaskBounty.changeDifficulty(difficultyId)
    g_game.bountyTaskAction(ACTION_CHANGE_DIFFICULTY, difficultyId)
end

function TaskBounty.claimDaily()
    g_game.bountyTaskAction(ACTION_CLAIM_DAILY, 0)
end
