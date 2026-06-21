taskHuntWindow = nil
taskHuntButton = nil

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

local function syncResourceBalances()
    local player = g_game.getLocalPlayer()
    if not player or not ResourceTypes then return end

    onResourceBalance(ResourceTypes.TASK_HUNTING,
        player:getResourceBalance(ResourceTypes.TASK_HUNTING))
    onResourceBalance(ResourceTypes.BOUNTY_TASK_POINTS,
        player:getResourceBalance(ResourceTypes.BOUNTY_TASK_POINTS))
    onResourceBalance(ResourceTypes.BOUNTY_REROLL_POINTS,
        player:getResourceBalance(ResourceTypes.BOUNTY_REROLL_POINTS))
    onResourceBalance(ResourceTypes.SOULSEAL_POINTS,
        player:getResourceBalance(ResourceTypes.SOULSEAL_POINTS))
end

function openTaskHuntStoreSearch(searchText)
    if not modules.game_store or not modules.game_store.showStoreWindow or not g_game.requestStoreOffers then
        return
    end

    modules.game_store.showStoreWindow()
    g_game.requestStoreOffers(5, searchText, 0)
end

function refreshTrackerData()
    if TaskBounty and TaskBounty.refreshTracker then
        TaskBounty.refreshTracker()
    end
end

function init()
    g_ui.importStyle('styles/bounty-tasks')
    g_ui.importStyle('styles/bounty-preferred')
    g_ui.importStyle('styles/task-shop')
    g_ui.importStyle('styles/weekly-tasks')

    taskHuntWindow = g_ui.displayUI('tasks')
    taskHuntWindow:hide()

    UIModalOverlay.register(taskHuntWindow)

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

    if not taskHuntButton then
        taskHuntButton = modules.game_mainpanel.addToggleButton(
            "taskHuntButton",
            tr("Task Hunt"),
            "/images/options/button_taskboard",
            toggle,
            false,
            1006
        )
    end

    connect(g_game, {
        onResourceBalance = onResourceBalance,
        onTaskHuntingShopData = TaskShop.onShopData,
        onTaskHuntingShopResult = TaskShop.onShopResult,
        onWeeklyTaskData = TaskWeekly.onServerData,
        onBountyTaskData = TaskBounty.onServerData,
        onBountyKillUpdate = TaskBounty.onKillUpdate,
        onWeeklyKillUpdate = TaskWeekly.onKillUpdate,
        onBountyPreferredData = BountyPreferred.onServerData,
        onGameEnd = hide,
    })

    if g_game.isOnline() then
        scheduleEvent(syncResourceBalances, 0)
    end
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

    disconnect(g_game, {
        onResourceBalance = onResourceBalance,
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

function show()
    if not taskHuntWindow then return end
    syncResourceBalances()
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

function onResourceBalance(resourceType, balance)
    if resourceType == nil then
        return
    end

    if resourceType == ResourceTypes.TASK_HUNTING then
        local panel = taskHuntWindow and taskHuntWindow:recursiveGetChildById('taskShopPoints')
        if panel then
            local label = panel:recursiveGetChildById('panelLabel')
            if label then label:setText(comma_value(balance)) end
        end
        TaskShop.updateBalance(balance)
    end

    if resourceType == ResourceTypes.SOULSEAL_POINTS then
        local panel = taskHuntWindow and taskHuntWindow:recursiveGetChildById('soulpitPoints')
        if panel then
            local label = panel:recursiveGetChildById('panelLabel')
            if label then label:setText(comma_value(balance)) end
        end
    end

    if resourceType == ResourceTypes.BOUNTY_TASK_POINTS then
        local panel = taskHuntWindow and taskHuntWindow:recursiveGetChildById('bountyPoints')
        if panel then
            local label = panel:recursiveGetChildById('panelLabel')
            if label then label:setText(comma_value(balance)) end
        end
        BountyPreferred.populateSlots()
    end

    if resourceType == ResourceTypes.BOUNTY_REROLL_POINTS then
        local rerollLabel = taskHuntWindow and taskHuntWindow:recursiveGetChildById('rerollPointsLabel')
        if rerollLabel then rerollLabel:setText(tostring(balance)) end

        local claimLabel = taskHuntWindow and taskHuntWindow:recursiveGetChildById('claimDailyLabel')
        if claimLabel then claimLabel:setText(tostring(balance)) end
    end
end
