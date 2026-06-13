TaskWeekly = {}

local difficultyModal = nil

-- Action types for g_game.weeklyTaskAction(actionType, param)
local ACTION_SELECT_DIFFICULTY = 0
local ACTION_DELIVER_ITEM = 1
local ACTION_REFRESH_DATA = 2

local THRESHOLDS = { 0, 4, 8, 12, 16, 18 }
local SECTIONS = #THRESHOLDS - 1

function TaskWeekly.requestRefresh()
    g_game.weeklyTaskAction(ACTION_REFRESH_DATA, 0)
end

function TaskWeekly.hasModal()
    return difficultyModal ~= nil
end

function TaskWeekly.destroyModal()
    if difficultyModal then
        difficultyModal:destroy()
        difficultyModal = nil
    end

    if taskHuntWindow then
        local bg = taskHuntWindow:recursiveGetChildById('weeklyBackground')
        if bg then bg:setVisible(false) end
    end
end

function TaskWeekly.init()
    -- Soul seals icon
    local rewardSoulPanel = taskHuntWindow:recursiveGetChildById('rewardSoulSealsPanel')
    if rewardSoulPanel then
        local icon = rewardSoulPanel:recursiveGetChildById('panelIcon')
        if icon then
            icon:setImageSource('/images/game/task_hunt/icon-currency-soulseals')
            icon:setSize({ width = 9, height = 9 })
        end
    end
end

-- ─── Server data handler ─────────────────────────────────────────────

function TaskWeekly.onServerData(header, monsters, items, difficulties)
    if g_things.registerRaceDataFromPacket then
        for _, monster in ipairs(monsters or {}) do
            g_things.registerRaceDataFromPacket(monster)
        end
    end

    -- Always update the kill tracker
    if Tracker and Tracker.Weekly then
        Tracker.Weekly.loadFromServerData(monsters)
    end

    if monsters and #monsters > 0 and Tracker and Tracker.Prey and Tracker.Prey.ensureVisible then
        Tracker.Prey.ensureVisible()
    end

    if not taskHuntWindow then
        return
    end

    -- Convert string values from C++ map to numbers
    local data = {
        difficulty             = tonumber(header.difficulty) or 0,
        remainingDays          = tonumber(header.remainingDays) or 7,
        totalTaskSlots         = tonumber(header.totalTaskSlots) or 6,
        maxExperience          = tonumber(header.maxExperience) or 0,
        maxDeliveryExperience  = tonumber(header.maxDeliveryExperience) or 0,
        completedKillTasks     = tonumber(header.completedKillTasks) or 0,
        completedDeliveryTasks = tonumber(header.completedDeliveryTasks) or 0,
        killTaskPoints         = tonumber(header.killTaskPoints) or 25,
        deliveryTaskPoints     = tonumber(header.deliveryTaskPoints) or 75,
        soulsealPointsPerTask  = tonumber(header.soulsealPointsPerTask) or 1,
        rewardMultiplier       = tonumber(header.rewardMultiplier) or 1,
        pointsEarned           = tonumber(header.pointsEarned) or 0,
        soulsealsEarned        = tonumber(header.soulsealsEarned) or 0,
        extraSlot              = (tonumber(header.extraSlot) or 0) == 1,
        currentPlayerLevel     = g_game.getLocalPlayer() and g_game.getLocalPlayer():getLevel() or 0,
    }

    -- Convert monster list
    data.monsters = {}
    for _, m in ipairs(monsters) do
        table.insert(data.monsters, {
            type     = "monster",
            raceId   = tonumber(m.raceId) or 0,
            current  = tonumber(m.current) or 0,
            total    = tonumber(m.total) or 0,
            finished = (tonumber(m.state) or 0) == 1,
        })
    end

    -- Convert item list
    data.items = {}
    for _, it in ipairs(items) do
        table.insert(data.items, {
            type      = "item",
            itemId    = tonumber(it.itemId) or 0,
            clientId  = tonumber(it.clientId) or tonumber(it.itemId) or 0,
            current   = tonumber(it.current) or 0,
            total     = tonumber(it.total) or 0,
            delivered = (tonumber(it.claimed) or 0) == 1,
            finished  = (tonumber(it.state) or 0) == 1,
        })
    end

    -- Convert difficulties
    data.difficulties = {}
    for _, d in ipairs(difficulties) do
        table.insert(data.difficulties, {
            id       = tonumber(d.id) or 0,
            name     = d.name or "",
            minLevel = tonumber(d.minLevel) or 0,
        })
    end

    -- First weekly open has no tasks yet; let the player choose difficulty.
    data.selectedTaskDifficulty = (#data.monsters == 0 and #data.items == 0)

    TaskWeekly.loadData(data)
end

-- ─── UI population ───────────────────────────────────────────────────

function TaskWeekly.clearDynamicWidgets()
    if not taskHuntWindow then return end

    -- Remove dynamically created icons from kill cards
    local killGrid = taskHuntWindow:recursiveGetChildById('killTasksGrid')
    if killGrid then
        for i = 1, killGrid:getChildCount() do
            local card = killGrid:getChildByIndex(i)
            if card then
                local icon = card:getChildById('finishedIcon')
                if icon then icon:destroy() end
                local previewPanel = card:recursiveGetChildById('previewPanel')
                if previewPanel then
                    local anyIcon = previewPanel:getChildById('anyCreatureIcon')
                    if anyIcon then anyIcon:destroy() end
                end

                -- Reset visibility
                local currentLabel = card:recursiveGetChildById('currentLabel')
                if currentLabel then currentLabel:setVisible(true) end
                local ofLabel = card:recursiveGetChildById('ofLabel')
                if ofLabel then ofLabel:setVisible(true) end
                local totalLabel = card:recursiveGetChildById('totalLabel')
                if totalLabel then totalLabel:setVisible(true) end
                local creature = card:recursiveGetChildById('creature')
                if creature then creature:setVisible(true) end
            end
        end
    end

    -- Remove dynamically created icons from delivery cards
    local deliveryGrid = taskHuntWindow:recursiveGetChildById('deliveryTasksGrid')
    if deliveryGrid then
        for i = 1, deliveryGrid:getChildCount() do
            local card = deliveryGrid:getChildByIndex(i)
            if card then
                local icon = card:getChildById('deliveredIcon')
                if icon then icon:destroy() end
                local pPanel = card:recursiveGetChildById('previewPanel')
                if pPanel then
                    local qlIcon = pPanel:getChildById('quickLootWarning')
                    if qlIcon then qlIcon:destroy() end
                    local ntIcon = pPanel:getChildById('npcTradeWarning')
                    if ntIcon then ntIcon:destroy() end
                end

                local currentLabel = card:recursiveGetChildById('currentLabel')
                if currentLabel then
                    currentLabel:setVisible(true)
                    currentLabel:setColor('$var-text-cip-color-white')
                end
                local ofLabel = card:recursiveGetChildById('ofLabel')
                if ofLabel then ofLabel:setVisible(true) end
                local totalLabel = card:recursiveGetChildById('totalLabel')
                if totalLabel then totalLabel:setVisible(true) end
                local deliverButton = card:recursiveGetChildById('deliverButton')
                if deliverButton then
                    deliverButton:setVisible(true)
                    deliverButton:setEnabled(false)
                end
            end
        end
    end
end

function TaskWeekly.loadData(data)
    TaskWeekly.clearDynamicWidgets()

    -- Boost Kills button - opens store for Weekly Double Kill Boost
    local boostKillsBtn = taskHuntWindow:recursiveGetChildById('boostKillsWeekly')
    if boostKillsBtn and not boostKillsBtn._bound then
        boostKillsBtn._bound = true
        boostKillsBtn.onClick = function()
            openTaskHuntStoreSearch('Weekly Double Kill Boost (1H)')
        end
    end

    -- Reduce Items button - opens store for Reduced Weekly Bounty Items
    local reduceItemsBtn = taskHuntWindow:recursiveGetChildById('reduceItemsWeekly')
    if reduceItemsBtn and not reduceItemsBtn._bound then
        reduceItemsBtn._bound = true
        reduceItemsBtn.onClick = function()
            openTaskHuntStoreSearch('Reduced Weekly Bounty Items')
        end
    end

    local killPermBtn = taskHuntWindow:recursiveGetChildById('killShopPermButton')
    if killPermBtn and not killPermBtn._bound then
        killPermBtn._bound = true
        killPermBtn.onClick = function()
            openTaskHuntStoreSearch('Permanent Weekly Task Expansion')
        end
    end

    local deliveryPermBtn = taskHuntWindow:recursiveGetChildById('deliveryShopPermButton')
    if deliveryPermBtn and not deliveryPermBtn._bound then
        deliveryPermBtn._bound = true
        deliveryPermBtn.onClick = function()
            openTaskHuntStoreSearch('Permanent Weekly Task Expansion')
        end
    end

    -- Fill kill task cards
    local killGrid = taskHuntWindow:recursiveGetChildById('killTasksGrid')
    if killGrid then
        local monsterCount = #data.monsters

        -- Disable grid layout updates to prevent cascading side effects
        local killLayout = killGrid:getLayout()
        if killLayout then killLayout:disableUpdates() end

        for i = 1, killGrid:getChildCount() do
            local card = killGrid:getChildByIndex(i)
            if not card then break end

            if i > monsterCount then
                card:setVisible(false)
            else
                local monsterData = data.monsters[i]
                card:setVisible(true)
                card.taskRaceId = monsterData.raceId
                card:setText(i)
                local currentLabel = card:recursiveGetChildById('currentLabel')
                if currentLabel then currentLabel:setText(monsterData.current) end
                local totalLabel = card:recursiveGetChildById('totalLabel')
                if totalLabel then totalLabel:setText(monsterData.total) end

                local creature = card:recursiveGetChildById('creature')
                if monsterData.raceId == 0 then
                    -- "Any Creature" slot: hide creature widget, show icon inside previewPanel
                    if creature then creature:setVisible(false) end
                    card:setText('Any Creature')
                    card:setTooltip('Kills from any creature count towards this task')

                    local previewPanel = card:recursiveGetChildById('previewPanel')
                    if previewPanel then
                        local anyIcon = g_ui.createWidget('UIWidget', previewPanel)
                        anyIcon:setId('anyCreatureIcon')
                        anyIcon:setImageSource('/images/game/task_hunt/icon-arbitrarymonster64x64')
                        anyIcon:setSize({ width = 64, height = 64 })
                        anyIcon:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
                        anyIcon:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
                        anyIcon:setPhantom(true)
                    end
                elseif creature and monsterData.raceId then
                    local raceData = g_things.getRaceData(monsterData.raceId)
                    if raceData and raceData.outfit then
                        creature:setOutfit(raceData.outfit)
                        if raceData.name and raceData.name ~= "" then
                            creature:setTooltip(string.capitalize(raceData.name))
                            local name = string.capitalize(raceData.name)
                            card:setText(short_text(name, 20))
                        end
                    end
                end

                if monsterData.finished then
                    if currentLabel then currentLabel:setVisible(false) end
                    local ofLabel = card:recursiveGetChildById('ofLabel')
                    if ofLabel then ofLabel:setVisible(false) end
                    if totalLabel then totalLabel:setVisible(false) end

                    local checkIcon = g_ui.createWidget('UIWidget', card)
                    checkIcon:setId('finishedIcon')
                    checkIcon:setSize({ width = 12, height = 9 })
                    checkIcon:setImageSource('/images/ui/icon-yes')
                    checkIcon:addAnchor(AnchorHorizontalCenter, 'currentLabel', AnchorHorizontalCenter)
                    checkIcon:addAnchor(AnchorVerticalCenter, 'previewPanel', AnchorVerticalCenter)
                    checkIcon:setPhantom(true)
                end
            end
        end

        -- Re-enable layout and trigger a single update
        if killLayout then
            killLayout:enableUpdates()
            killLayout:update()
        end
    end

    -- Fill delivery task cards
    local deliveryGrid = taskHuntWindow:recursiveGetChildById('deliveryTasksGrid')
    if deliveryGrid then
        local itemCount = #data.items

        -- Disable grid layout updates to prevent cascading internalUpdate()
        -- side effects that swap visibility between cards
        local layout = deliveryGrid:getLayout()
        if layout then layout:disableUpdates() end

        for i = 1, deliveryGrid:getChildCount() do
            local card = deliveryGrid:getChildByIndex(i)
            if not card then break end

            if i > itemCount then
                card:setVisible(false)
            else
                local itemData = data.items[i]
                local previewItemId = itemData.clientId > 0 and itemData.clientId or itemData.itemId
                card:setVisible(true)
                card.taskItemId = previewItemId
                local itemName = getItemServerName(previewItemId)
                card:setText(short_text(itemName, 20))
                local currentLabel = card:recursiveGetChildById('currentLabel')
                if currentLabel then currentLabel:setText(itemData.current) end
                local totalLabel = card:recursiveGetChildById('totalLabel')
                if totalLabel then totalLabel:setText(itemData.total) end

                local itemDisplay = card:recursiveGetChildById('itemDisplay')
                if itemDisplay and previewItemId > 0 then
                    itemDisplay:setItemId(previewItemId)
                    if itemName and itemName ~= "" then
                        itemDisplay:setTooltip(itemName)
                    end
                end

                -- Warning icons (top-right corner of previewPanel)
                local previewPanel = card:recursiveGetChildById('previewPanel')
                local quickLootWarning = false
                local quickLootTooltip = ''
                if modules.game_quickloot and modules.game_quickloot.QuickLoot then
                    local ql = modules.game_quickloot.QuickLoot
                    local activeFilter = ql.data and ql.data.filter or 1
                    if activeFilter == 1 and ql.lootExists(previewItemId, 1) then
                        quickLootWarning = true
                        quickLootTooltip = tr('This item is marked as skipped in Quick Loot.')
                    elseif activeFilter == 2 and not ql.lootExists(previewItemId, 2) then
                        quickLootWarning = true
                        quickLootTooltip = tr(
                            'This item is not in the Accepted Loot list\nand will not be automatically looted.')
                    end
                end

                local isNotInNpcBlacklist = modules.game_npctrade
                    and modules.game_npctrade.inWhiteList
                    and not modules.game_npctrade.inWhiteList(previewItemId)

                if previewPanel and quickLootWarning then
                    local redIcon = g_ui.createWidget('UIWidget', previewPanel)
                    redIcon:setId('quickLootWarning')
                    redIcon:setSize({ width = 12, height = 12 })
                    redIcon:setImageSource('/images/skin/show-gui-help-red')
                    redIcon:addAnchor(AnchorTop, 'parent', AnchorTop)
                    redIcon:addAnchor(AnchorLeft, 'parent', AnchorLeft)
                    redIcon:setMarginTop(4)
                    redIcon:setMarginLeft(4)
                    redIcon:setTooltip(quickLootTooltip)
                end

                if previewPanel and isNotInNpcBlacklist then
                    local orangeIcon = g_ui.createWidget('UIWidget', previewPanel)
                    orangeIcon:setId('npcTradeWarning')
                    orangeIcon:setSize({ width = 12, height = 12 })
                    orangeIcon:setImageSource('/images/skin/show-gui-help-orange')
                    orangeIcon:addAnchor(AnchorTop, 'parent', AnchorTop)
                    orangeIcon:addAnchor(AnchorRight, 'parent', AnchorRight)
                    orangeIcon:setMarginTop(4)
                    orangeIcon:setMarginRight(4)
                    orangeIcon:setTooltip(tr("This item can be sold, remember\nto add it to the 'Disable Auto Sell'."))
                end

                -- Right-click context menu on item display
                if itemDisplay then
                    local itemId = previewItemId
                    itemDisplay.onMouseRelease = function(self, mousePos, mouseButton)
                        if mouseButton == MouseRightButton or (mouseButton == MouseLeftButton and g_keyboard.isCtrlPressed()) then
                            local menu = g_ui.createWidget('PopupMenu')
                            menu:setGameMenu(true)

                            local refresh = TaskWeekly.requestRefresh
                            local addToOptions = modules.game_interface.AddToOptions

                            if addToOptions then
                                addToOptions.handleManagerContainer(menu, itemId, refresh)
                                addToOptions.handleQuickSell(menu, itemId, refresh)
                            end

                            menu:display(mousePos)
                            return true
                        end
                        return false
                    end
                end

                local deliverButton = card:recursiveGetChildById('deliverButton')
                if itemData.delivered then
                    if currentLabel then currentLabel:setVisible(false) end
                    local ofLabel = card:recursiveGetChildById('ofLabel')
                    if ofLabel then ofLabel:setVisible(false) end
                    if totalLabel then totalLabel:setVisible(false) end
                    if deliverButton then deliverButton:setVisible(false) end

                    local checkIcon = g_ui.createWidget('UIWidget', card)
                    checkIcon:setId('deliveredIcon')
                    checkIcon:setSize({ width = 12, height = 9 })
                    checkIcon:setImageSource('/images/ui/icon-yes')
                    checkIcon:addAnchor(AnchorHorizontalCenter, 'currentLabel', AnchorHorizontalCenter)
                    checkIcon:addAnchor(AnchorVerticalCenter, 'previewPanel', AnchorVerticalCenter)
                    checkIcon:setPhantom(true)
                elseif deliverButton then
                    local canDeliver = itemData.finished and not itemData.delivered
                    deliverButton:setEnabled(canDeliver)
                    if canDeliver then
                        currentLabel:setColor('#00ff00')
                    end

                    -- Wire deliver button to server action with confirmation
                    local slotIndex = i - 1
                    deliverButton.onClick = function()
                        local msgBox
                        local yesCallback = function()
                            if msgBox then msgBox:destroy() end
                            g_game.weeklyTaskAction(ACTION_DELIVER_ITEM, slotIndex)
                        end
                        local noCallback = function()
                            if msgBox then msgBox:destroy() end
                        end
                        msgBox = displayGeneralBox(tr('Deliver Item'),
                            tr('Do you want to deliver %s?', itemName),
                            { { text = tr('Yes'), callback = yesCallback }, { text = tr('No'), callback = noCallback } },
                            yesCallback, noCallback, taskHuntWindow)
                    end
                end
            end
        end

        -- Re-enable layout and trigger a single update
        if layout then
            layout:enableUpdates()
            layout:update()
        end
    end

    -- XP label
    local xpLabel = taskHuntWindow:recursiveGetChildById('weeklyXpLabel')
    if xpLabel and data.maxExperience > 0 then
        xpLabel:setText(tr('Each kill task rewards you with %s XP and each delivery task will reward you with %s XP.',
            comma_value(data.maxExperience), comma_value(data.maxDeliveryExperience)))
    end

    -- Progress bar
    local totalCompleted = data.completedKillTasks + data.completedDeliveryTasks
    TaskWeekly.updateProgress(totalCompleted)

    local fill = taskHuntWindow:recursiveGetChildById('progressBarFill')
    if fill then
        local tooltip = string.format(
            'Kill Tasks: %d\nDelivery Tasks: %d\nTotal: %d',
            data.completedKillTasks,
            data.completedDeliveryTasks,
            totalCompleted
        )
        fill:setTooltip(tooltip)
    end

    -- Reward tokens
    local totalPoints = data.pointsEarned

    local tokensPanel = taskHuntWindow:recursiveGetChildById('rewardTokensPanel')
    if tokensPanel then
        local label = tokensPanel:recursiveGetChildById('panelLabel')
        if label then label:setText(totalPoints) end
    end

    local tokensInfo = taskHuntWindow:recursiveGetChildById('rewardTokensInfo')
    if tokensInfo then
        local killBase = data.completedKillTasks * data.killTaskPoints
        local deliveryBase = data.completedDeliveryTasks * data.deliveryTaskPoints
        local tooltip = string.format(
            'Hunting Task Points:\n\n   %d * %d  (Kill Tasks)\n+ %d * %d  (Delivery Tasks)\n--------------------------------------\n= %d  base points\nx %d  reward multiplier\n= %d  Hunting Task Points',
            data.completedKillTasks, data.killTaskPoints,
            data.completedDeliveryTasks, data.deliveryTaskPoints,
            killBase + deliveryBase,
            data.rewardMultiplier,
            totalPoints
        )
        tokensInfo:setTooltip(tooltip)
    end

    -- Soul seals
    local soulLabel = taskHuntWindow:recursiveGetChildById('rewardSoulSealsPanel')
    if soulLabel then
        local label = soulLabel:recursiveGetChildById('panelLabel')
        if label then label:setText(data.soulsealsEarned) end
    end

    local soulSealsInfo = taskHuntWindow:recursiveGetChildById('rewardSoulSealsInfo')
    if soulSealsInfo then
        local tooltip = string.format(
            'You receive %d Soulseal for each completed task. Soulseals can be\nused in the Soulpit. Click the obelisk there, then your character to\nopen a menu where you can select a creature you want to\nchallenge on your own.',
            data.soulsealPointsPerTask
        )
        soulSealsInfo:setTooltip(tooltip)
    end

    -- Remaining days
    local remainingLabel = taskHuntWindow:recursiveGetChildById('remainingLabel')
    if remainingLabel then
        remainingLabel:setText(tr('%d day(s) remaining', data.remainingDays))
    end

    -- Extra slot shop buttons
    local hasExtra = data.extraSlot
    local killBtn = taskHuntWindow:recursiveGetChildById('killShopPermButton')
    if killBtn then killBtn:setVisible(not hasExtra) end
    local deliveryBtn = taskHuntWindow:recursiveGetChildById('deliveryShopPermButton')
    if deliveryBtn then deliveryBtn:setVisible(not hasExtra) end

    -- Store data for difficulty modal and show if needed
    TaskWeekly.pendingData = data
    TaskWeekly.onTabSelected()
end

-- ─── Difficulty modal ────────────────────────────────────────────────

function TaskWeekly.onTabSelected()
    if not taskHuntWindow or not taskHuntWindow:isVisible() then return end
    if TaskWeekly.pendingData and TaskWeekly.pendingData.selectedTaskDifficulty then
        if not difficultyModal then
            TaskWeekly.showDifficultyModal(TaskWeekly.pendingData)
        end
    else
        TaskWeekly.destroyModal()
    end
end

function TaskWeekly.showDifficultyModal(data)
    TaskWeekly.destroyModal()

    -- Show dither pattern overlay on weekly content
    local bg = taskHuntWindow:recursiveGetChildById('weeklyBackground')
    if bg then
        bg:setVisible(true)
        bg:raise()
    end

    difficultyModal = g_ui.createWidget('WeeklyDifficultyModal', taskHuntWindow)
    difficultyModal:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    difficultyModal:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    difficultyModal:raise()
    difficultyModal:focus()

    -- Weekly summary (shown when there's previous data)
    if data.completedKillTasks > 0 or data.completedDeliveryTasks > 0 then
        local summaryPanel = difficultyModal:recursiveGetChildById('weeklySummaryPanel')
        if summaryPanel then
            summaryPanel:setVisible(true)
            summaryPanel:setHeight(50)

            local killLabel = summaryPanel:recursiveGetChildById('killSummaryLabel')
            if killLabel then
                killLabel:setText(string.format('You have completed %d / %d kill tasks.', data.completedKillTasks,
                    data.totalTaskSlots))
            end

            local deliveryLabel = summaryPanel:recursiveGetChildById('deliverySummaryLabel')
            if deliveryLabel then
                deliveryLabel:setText(string.format('You have completed %d / %d delivery tasks.',
                    data.completedDeliveryTasks, data.totalTaskSlots))
            end

            local totalLabel = summaryPanel:recursiveGetChildById('totalEarnedLabel')
            if totalLabel then
                totalLabel:setText(string.format('Total earned: %d    and %d   ', data.pointsEarned,
                    data.soulsealsEarned))

                -- Use getTextSize on helper labels to find icon positions
                local helperPrefix = g_ui.createWidget('UILabel', totalLabel)
                helperPrefix:setFont('Verdana Bold-11px')
                helperPrefix:setText(string.format('Total earned: %d', data.pointsEarned))
                helperPrefix:setTextAutoResize(true)
                local prefixWidth = helperPrefix:getWidth() + 1
                helperPrefix:destroy()

                local helperFull = g_ui.createWidget('UILabel', totalLabel)
                helperFull:setFont('Verdana Bold-11px')
                helperFull:setText(string.format('Total earned: %d    and %d', data.pointsEarned,
                    data.soulsealsEarned))
                helperFull:setTextAutoResize(true)
                local fullWidth = helperFull:getWidth() + 1
                helperFull:destroy()

                local totalTextWidget = g_ui.createWidget('UILabel', totalLabel)
                totalTextWidget:setFont('Verdana Bold-11px')
                totalTextWidget:setText(totalLabel:getText())
                totalTextWidget:setTextAutoResize(true)
                local totalTextWidth = totalTextWidget:getWidth()
                totalTextWidget:destroy()

                local labelWidth = totalLabel:getWidth()
                local textStartX = math.floor((labelWidth - totalTextWidth) / 2)

                local pointsIcon = g_ui.createWidget('UIWidget', totalLabel)
                pointsIcon:setSize({ width = 11, height = 11 })
                pointsIcon:setImageSource('/images/game/task_hunt/task-tokens')
                pointsIcon:setPhantom(true)
                pointsIcon:setMarginRight(5)
                pointsIcon:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
                pointsIcon:addAnchor(AnchorLeft, 'parent', AnchorLeft)
                pointsIcon:setMarginLeft(textStartX + prefixWidth)

                local soulIcon = g_ui.createWidget('UIWidget', totalLabel)
                soulIcon:setSize({ width = 9, height = 9 })
                soulIcon:setImageSource('/images/game/task_hunt/icon-currency-soulseals')
                soulIcon:setPhantom(true)
                soulIcon:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
                soulIcon:addAnchor(AnchorLeft, 'parent', AnchorLeft)
                soulIcon:setMarginLeft(textStartX + fullWidth)
            end
        end
    end

    local buttonsPanel = difficultyModal:recursiveGetChildById('difficultyButtonsPanel')
    if not buttonsPanel then return end
    local baseButtonPath = "/images/game/task_hunt/%s-large-button"
    for i, diff in ipairs(data.difficulties) do
        local name = diff.name:lower()
        local imgPath = string.format(baseButtonPath, name)
        local btn = g_ui.createWidget('DifficultyButton', buttonsPanel)
        btn:setImageSource(imgPath)

        local canSelect = data.currentPlayerLevel >= diff.minLevel
        btn:setOn(canSelect)

        if not canSelect then
            btn:setTooltip(string.format('The minimum level to start this difficulty is %d', diff.minLevel))
        end

        btn.onClick = function()
            if not btn:isOn() then return end
            -- Send difficulty selection to server
            g_game.weeklyTaskAction(ACTION_SELECT_DIFFICULTY, (tonumber(diff.id) or 1) - 1)
            TaskWeekly.destroyModal()
        end
    end
end

-- ─── Progress bar ────────────────────────────────────────────────────

function TaskWeekly.updateProgress(completedTasks)
    local track = taskHuntWindow:recursiveGetChildById('progressBarTrack')
    local fill = taskHuntWindow:recursiveGetChildById('progressBarFill')
    if not track or not fill then return end

    local trackWidth = track:getWidth()
    local sectionWidth = trackWidth / SECTIONS

    local sectionIndex = 0
    for i = 1, SECTIONS do
        if completedTasks >= THRESHOLDS[i + 1] then
            sectionIndex = i
        else
            break
        end
    end

    local marginH = fill:getMarginLeft() + fill:getMarginRight()
    local maxFillWidth = trackWidth - marginH

    local fillWidth = 0
    if sectionIndex >= SECTIONS then
        fillWidth = maxFillWidth
    else
        local sectionStart = THRESHOLDS[sectionIndex + 1]
        local sectionEnd = THRESHOLDS[sectionIndex + 2]
        local fraction = (completedTasks - sectionStart) / (sectionEnd - sectionStart)
        fillWidth = math.min(math.floor((sectionIndex + fraction) * sectionWidth), maxFillWidth)
    end

    fill:setWidth(fillWidth)
end

function TaskWeekly.onKillUpdate(raceId, currentKills, totalKills, isCompleted)
    -- Update tracker
    if Tracker and Tracker.Weekly then
        Tracker.Weekly.onKillUpdate(raceId, currentKills, totalKills, isCompleted)
    end

    -- Update weekly tasks panel kill card (if open)
    if not taskHuntWindow then return end

    local killGrid = taskHuntWindow:recursiveGetChildById('killTasksGrid')
    if not killGrid then return end

    for i = 1, killGrid:getChildCount() do
        local card = killGrid:getChildByIndex(i)
        if not card or not card:isVisible() then break end

        local currentLabel = card:recursiveGetChildById('currentLabel')
        if currentLabel and currentLabel:isVisible() and (card.taskRaceId or -1) == raceId then
            currentLabel:setText(currentKills)
            if isCompleted == 1 then
                currentLabel:setVisible(false)
                local ofLabel = card:recursiveGetChildById('ofLabel')
                if ofLabel then ofLabel:setVisible(false) end
                local totalLabel = card:recursiveGetChildById('totalLabel')
                if totalLabel then totalLabel:setVisible(false) end

                local existingIcon = card:getChildById('finishedIcon')
                if existingIcon then
                    existingIcon:destroy()
                end

                local checkIcon = g_ui.createWidget('UIWidget', card)
                checkIcon:setId('finishedIcon')
                checkIcon:setSize({ width = 12, height = 9 })
                checkIcon:setImageSource('/images/ui/icon-yes')
                checkIcon:addAnchor(AnchorHorizontalCenter, 'currentLabel', AnchorHorizontalCenter)
                checkIcon:addAnchor(AnchorVerticalCenter, 'previewPanel', AnchorVerticalCenter)
                checkIcon:setPhantom(true)
            end
            return
        end
    end
end
