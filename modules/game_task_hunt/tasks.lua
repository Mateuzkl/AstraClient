taskHuntWindow = nil
taskHuntButton = nil

local TASK_BOARD_AUX_OPCODE = 205

local tabButtons = {}
local contentPanels = {}

local TAB_INACTIVE_BG = '/images/ui/2pixel_up_frame_borderimage'
local TAB_ACTIVE_BG = '/images/ui/2pixel-up-frame-borderimage-upside-down'

local tabConfig = {
    [1] = {
        buttonId = 'bountyTasksTab',
        contentId = 'bountyContent',
        icon = '/images/game/task_hunt/icon-bountytasks',
        title = 'Bounty Tasks'
    },
    [2] = {
        buttonId = 'weeklyTasksTab',
        contentId = 'weeklyContent',
        icon = '/images/game/task_hunt/icon-weeklytasks',
        title = 'Weekly Tasks'
    },
    [3] = {
        buttonId = 'huntingTaskShopTab',
        contentId = 'shopContent',
        icon = '/images/game/task_hunt/icon-huntingtaskshop',
        title = 'Hunting Task Shop'
    }
}

function init()
    g_ui.importStyle('styles/bounty-tasks')
    g_ui.importStyle('styles/bounty-preferred')
    g_ui.importStyle('styles/task-shop')
    g_ui.importStyle('styles/weekly-tasks')

    taskHuntWindow = g_ui.displayUI('tasks')
    if not taskHuntWindow then
        g_logger.error("[game_task_hunt] Failed to load tasks.otui")
        return
    end
    taskHuntWindow:hide()

    if UIModalOverlay and UIModalOverlay.register then
        UIModalOverlay.register(taskHuntWindow)
    end

    for i, config in ipairs(tabConfig) do
        local btn = taskHuntWindow:recursiveGetChildById(config.buttonId)
        tabButtons[i] = btn

        local tabIcon = btn:recursiveGetChildById('tabIcon')
        if tabIcon then
            tabIcon:setImageSource(config.icon)
        end

        local tabLabel = btn:recursiveGetChildById('tabLabel')
        if tabLabel then
            tabLabel:setText(tr(config.title))
        end

        contentPanels[i] = taskHuntWindow:recursiveGetChildById(config.contentId)
    end

    -- Set custom icons for info panels
    local bountyPanel = taskHuntWindow:recursiveGetChildById('bountyPoints')
    if bountyPanel then
        local icon = bountyPanel:recursiveGetChildById('panelIcon')
        if icon then
            icon:setImageSource('/images/game/task_hunt/icon-currency-bountypoints')
            icon:setSize({ width = 9, height = 9 })
        end
    end

    local soulpitPanel = taskHuntWindow:recursiveGetChildById('soulpitPoints')
    if soulpitPanel then
        local icon = soulpitPanel:recursiveGetChildById('panelIcon')
        if icon then
            icon:setImageSource('/images/game/task_hunt/icon-currency-soulseals')
            icon:setSize({ width = 9, height = 9 })
        end
    end

    TaskBounty.init()
    BountyPreferred.init()
    TaskWeekly.init()

    local shopPanel = contentPanels[3]
    if shopPanel then
        TaskShop.init(shopPanel)
    end

    if not taskHuntButton and modules.client_topmenu and modules.client_topmenu.addRightGameToggleButton then
        taskHuntButton = modules.client_topmenu.addRightGameToggleButton(
            "taskHuntButton",
            tr("Task Hunt"),
            "/images/topbuttons/taskHuntDialog",
            toggle,
            false,
            1006
        )
    end

    if ProtocolGame and ProtocolGame.registerExtendedOpcode then
        ProtocolGame.registerExtendedOpcode(TASK_BOARD_AUX_OPCODE, onTaskBoardAuxOpcode)
    end

    connect(g_game, {
        onResourcesBalanceChange = onResourceBalance,
        onTaskHuntingShopData = TaskShop.onShopData,
        onTaskHuntingShopResult = TaskShop.onShopResult,
        onWeeklyTaskData = TaskWeekly.onServerData,
        onBountyTaskData = TaskBounty.onServerData,
        onBountyKillUpdate = TaskBounty.onKillUpdate,
        onWeeklyKillUpdate = TaskWeekly.onKillUpdate,
        onBountyPreferredData = BountyPreferred.onServerData,
        onGameEnd = hide,
    })
end

function terminate()
    TaskShop.terminate()
    BountyPreferred.terminate()

    if taskHuntButton then
        taskHuntButton:destroy()
        taskHuntButton = nil
    end

    if taskHuntWindow then
        taskHuntWindow:destroy()
        taskHuntWindow = nil
    end

    tabButtons = {}
    contentPanels = {}

    if ProtocolGame and ProtocolGame.unregisterExtendedOpcode then
        ProtocolGame.unregisterExtendedOpcode(TASK_BOARD_AUX_OPCODE)
    end

    disconnect(g_game, {
        onResourcesBalanceChange = onResourceBalance,
        onTaskHuntingShopData = TaskShop.onShopData,
        onTaskHuntingShopResult = TaskShop.onShopResult,
        onWeeklyTaskData = TaskWeekly.onServerData,
        onBountyTaskData = TaskBounty.onServerData,
        onBountyKillUpdate = TaskBounty.onKillUpdate,
        onWeeklyKillUpdate = TaskWeekly.onKillUpdate,
        onBountyPreferredData = BountyPreferred.onServerData,
        onGameEnd = hide,
    })
end

function onTaskBoardAuxOpcode(protocol, opcode, buffer)
    local ok, payload = pcall(json.decode, buffer)
    if not ok or not payload or not payload.action then
        return
    end

    local action = payload.action
    local data = payload.data or {}

    if action == 'shopResult' then
        g_game.onTaskHuntingShopResult(data.itemId or 0, data.result or 0)
    elseif action == 'bountyKillUpdate' then
        g_game.onBountyKillUpdate(data.raceId or 0, data.currentKills or 0, data.totalKills or 0, data.isCompleted or 0)
    elseif action == 'weeklyKillUpdate' then
        g_game.onWeeklyKillUpdate(data.raceId or 0, data.currentKills or 0, data.totalKills or 0, data.isCompleted or 0)
    elseif action == 'soulsealData' then
        g_game.onSoulsealsData(data.entries or {})
    end
end

function show()
    if not taskHuntWindow then return end
    taskHuntWindow:show()
    taskHuntWindow:raise()
    taskHuntWindow:focus()
    if taskHuntButton then
        taskHuntButton:setOn(true)
    end
end

function hide()
    if not taskHuntWindow then return end
    taskHuntWindow:hide()
    TaskShop.resetData()
    BountyPreferred.hide()
    if taskHuntButton then
        taskHuntButton:setOn(false)
    end
end

function toggle()
    if not taskHuntWindow then return end
    if taskHuntWindow:isVisible() then
        hide()
    else
        show()
        if TaskWeekly.pendingData and TaskWeekly.pendingData.selectedTaskDifficulty then
            selectTab(2)
        else
            selectTab(1)
        end
    end
end

function selectTab(tabIndex)
    if tabIndex < 1 or tabIndex > #tabConfig then return end
    -- Block tab switching while summary overlay is active
    if TaskWeekly.hasModal() and tabIndex ~= 2 then return end

    for i = 1, #tabConfig do
        local btn = tabButtons[i]
        local panel = contentPanels[i]

        if i == tabIndex then
            btn:setChecked(true)
            btn:setImageSource(TAB_ACTIVE_BG)
            local label = btn:recursiveGetChildById('tabLabel')
            if label then label:setColor('$var-text-cip-color-white') end
            panel:setVisible(true)
        else
            btn:setChecked(false)
            btn:setImageSource(TAB_INACTIVE_BG)
            local label = btn:recursiveGetChildById('tabLabel')
            if label then label:setColor('$var-text-cip-color') end
            panel:setVisible(false)
        end
    end

    if tabIndex == 1 then
        TaskBounty.requestRefresh()
    elseif tabIndex == 2 then
        TaskWeekly.requestRefresh()
        TaskWeekly.onTabSelected()
    elseif tabIndex == 3 then
        TaskShop.requestRefresh()
    end
end

function onSelectTab(tabIndex)
    selectTab(tabIndex)
end

function onResourceBalance(balance, oldBalance, resourceType)
    if resourceType == nil then
        return
    end

    if resourceType == ResourceTypes.TASK_HUNTING then
        local panel = taskHuntWindow:recursiveGetChildById('taskShopPoints')
        if panel then
            local label = panel:recursiveGetChildById('panelLabel')
            if label then label:setText(comma_value(balance)) end
        end
        TaskShop.updateBalance(balance)
    end

    if resourceType == ResourceTypes.SOULSEALS then
        local panel = taskHuntWindow:recursiveGetChildById('soulpitPoints')
        if panel then
            local label = panel:recursiveGetChildById('panelLabel')
            if label then label:setText(comma_value(balance)) end
        end
    end

    if resourceType == ResourceTypes.BOUNTY_POINTS then
        local panel = taskHuntWindow:recursiveGetChildById('bountyPoints')
        if panel then
            local label = panel:recursiveGetChildById('panelLabel')
            if label then label:setText(comma_value(balance)) end
        end
    end

    if resourceType == ResourceTypes.BOUNTY_REROLL_POINTS then
        local rerollLabel = taskHuntWindow:recursiveGetChildById('rerollPointsLabel')
        if rerollLabel then rerollLabel:setText(tostring(balance)) end

        local claimLabel = taskHuntWindow:recursiveGetChildById('claimDailyLabel')
        if claimLabel then claimLabel:setText(tostring(balance)) end
    end
end
