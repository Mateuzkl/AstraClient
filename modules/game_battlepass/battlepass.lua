local onBattlePassMessage
local online
local offline
local openBattlePass
local onCreateRewardContainers
local onResourceBalance
local toggleNextWindow

if not BattlePass then
    BattlePass = {}
    BattlePass.__index = BattlePass

    BattlePass.window = nil
    BattlePass.missionPanel = nil
    BattlePass.progressPanel = nil
    BattlePass.outfitWidget = nil
    BattlePass.scrollBarWidget = nil
    BattlePass.dailyRerollWindow = nil

    BattlePass.beginTime = 0
    BattlePass.endTime = 0
    BattlePass.progressPoints = 0
    BattlePass.dailyRerollPrice = 0
    BattlePass.premiumBattlepass = false
    BattlePass.currentRewardStep = 0
    BattlePass.nextStepPoints = 0
    BattlePass.currentReward = 0
    BattlePass.dailyMissionsBegin = 0
    BattlePass.dailyMissionsExpire = 0
    BattlePass.dailyMissions = {}
    BattlePass.seasonMissions = {}
    BattlePass.shopPoints = 0
    BattlePass.shopUnlocked = false

    BattlePass.isAnimatingWalk = false
    BattlePass.pendingRewardsSchedule = nil
    BattlePass.lastRewardStep = 0
    BattlePass.lastCameraPosition = 0

    -- Common variables
    BattlePass.rewardMinMargin = 195
    BattlePass.rewardMaxMargin = 28600
end

local BattlePassOpcode = {
    Request = 0x36,
    Send = 0x37
}

local BattlePassRequest = {
    GetMissions = 1,
    GetRewards = 2,
    Reroll = 3,
    Redeem = 4,
    BuyPremium = 5,
    GetShop = 6,
    BuyShop = 7,
}

local BattlePassResponse = {
    Missions = 1,
    Rewards = 2,
    Error = 3,
    Shop = 4
}

local battlePassProtocolRegistered = false
BattlePass.opcode = BattlePassOpcode.Request

local battlePassTabs = {
    challengesMenu = {
        title = 'Challenges',
        icon = '/images/game/battlepass/mainIcon1',
    },
    rewardsMenu = {
        title = 'Rewards',
        icon = '/images/game/battlepass/vip-reward-chest',
    },
    shopMenu = {
        title = 'Battle Pass Shop',
        icon = '/images/game/task_hunt/icon-huntingtaskshop',
    },
}

local function getLoadedPlayerId()
    if not LoadedPlayer or not LoadedPlayer.isLoaded or not LoadedPlayer.getId or not LoadedPlayer:isLoaded() then
        return nil
    end

    return LoadedPlayer:getId()
end

local function safePercent(value, maxValue)
    value = tonumber(value) or 0
    maxValue = tonumber(maxValue) or 0
    if maxValue <= 0 then
        return 0
    end
    return math.max(0, math.min(100, value / maxValue * 100))
end

local function getRewardPosition(step)
    return RewardPositions[step] or RewardPositions[0]
end

local function stopUnlockTimer()
    if BattlePass.unlockTimerEvent then
        removeEvent(BattlePass.unlockTimerEvent)
        BattlePass.unlockTimerEvent = nil
    end
end

local function stopPendingRewardsSchedule()
    if BattlePass.pendingRewardsSchedule then
        removeEvent(BattlePass.pendingRewardsSchedule)
        BattlePass.pendingRewardsSchedule = nil
    end
end

local function updateGoldBalance()
    if not BattlePass.window or not BattlePass.window:isVisible() then
        return
    end

    local player = g_game.getLocalPlayer()
    local goldCoinsLabel = BattlePass.window:recursiveGetChildById('rCoins')
    if not player or not goldCoinsLabel then
        return
    end

    local playerBank = player:getResourceValue(ResourceBank)
    local playerInventory = player:getResourceValue(ResourceInventary)
    local moneyTooltip = {}

    setStringColor(moneyTooltip, "Cash: " .. comma_value(playerInventory), "#3f3f3f")
    setStringColor(moneyTooltip, " $", "#f7e6fe")
    setStringColor(moneyTooltip, "\nBank: " .. comma_value(playerBank), "#3f3f3f")
    setStringColor(moneyTooltip, " $", "#f7e6fe")

    goldCoinsLabel:setText(comma_value(playerBank + playerInventory))
    goldCoinsLabel:setTooltip(moneyTooltip)
end

local function sendBattlePassMessage(msg)
    local protocol = g_game.getProtocolGame()
    if not protocol then
        return false
    end

    protocol:send(msg)
    return true
end

local function sendToServer(action, data)
    data = type(data) == "table" and data or {}

    local request = nil
    if action == "getMissions" then
        request = BattlePassRequest.GetMissions
    elseif action == "getRewards" then
        request = BattlePassRequest.GetRewards
    elseif action == "reroll" then
        request = BattlePassRequest.Reroll
    elseif action == "redeem" then
        request = BattlePassRequest.Redeem
    elseif action == "buyPremium" or action == "buyDeluxe" or action == "purchasePremium" then
        request = BattlePassRequest.BuyPremium
    elseif action == "getShop" then
        request = BattlePassRequest.GetShop
    elseif action == "buyShop" then
        request = BattlePassRequest.BuyShop
    end

    if not request then
        return false
    end

    local msg = OutputMessage.create()
    msg:addU8(BattlePassOpcode.Request)
    msg:addU8(request)

    if request == BattlePassRequest.Reroll then
        msg:addString(tostring(data.missionId or ""))
    elseif request == BattlePassRequest.Redeem then
        msg:addU16(tonumber(data.index) or 0)
        msg:addU32(tonumber(data.rewardId) or 0)
        msg:addU32(math.max(0, tonumber(data.objectId) or 0))
    elseif request == BattlePassRequest.BuyShop then
        msg:addU16(math.max(0, tonumber(data.shopId) or 0))
    end

    return sendBattlePassMessage(msg)
end

BattlePass.sendToServer = sendToServer

local function setOutfitStaticWalking(enabled)
    local widget = BattlePass.outfitWidget
    if not widget then
        return
    end

    if widget.setStaticWalking then
        widget:setStaticWalking(enabled)
        return
    end

    local creature = widget.getCreature and widget:getCreature()
    if creature and creature.setStaticWalking then
        creature:setStaticWalking(enabled)
    end
end

local function getMissionIndex(index)
    return MissionsDisplacement[index]
end

local function aggresiveNumberToStr(n)
    n = tonumber(n) or 0
    if n >= 1000000 then
        return string.format("%.1fM", n / 1000000)
    elseif n >= 1000 then
        return string.format("%.1fK", n / 1000)
    end
    return tostring(n)
end

local function getOrderedMissions(missions)
    if type(missions) ~= "table" then
        missions = {}
    end

    local bronzeMissions = {}
    local silverMissions = {}
    local goldMissions = {}
    local orderedWithIndex = {}

    for _, mission in ipairs(missions) do
        if mission.rewardPoints == 100 then
            table.insert(bronzeMissions, mission)
        elseif mission.rewardPoints == 200 then
            table.insert(silverMissions, mission)
        elseif mission.rewardPoints == 300 then
            table.insert(goldMissions, mission)
        end
    end

    local bronzeIndex = 1
    local silverIndex = 1
    local goldIndex = 1

    for i, missionType in ipairs(MissionTypesOrder) do
        local indexDestino = MissionsDisplacement[i]
        local mission = nil

        if missionType == "bronze" and bronzeMissions[bronzeIndex] then
            mission = bronzeMissions[bronzeIndex]
            bronzeIndex = bronzeIndex + 1
        elseif missionType == "silver" and silverMissions[silverIndex] then
            mission = silverMissions[silverIndex]
            silverIndex = silverIndex + 1
        elseif missionType == "gold" and goldMissions[goldIndex] then
            mission = goldMissions[goldIndex]
            goldIndex = goldIndex + 1
        end

        if mission then
            table.insert(orderedWithIndex, { data = mission, index = indexDestino })
        end
    end
    return orderedWithIndex
end

local function getFormatedTime(dailyEndTime)
    local timeLeft = dailyEndTime - os.time()
    if timeLeft <= 0 then
        return "Expired", "Expired"
    end

    local days = math.floor(timeLeft / 86400)
    local hours = math.floor((timeLeft % 86400) / 3600)
    local minutes = math.floor((timeLeft % 3600) / 60)
    local seconds = timeLeft % 60

    local function formatUnit(value, singular, plural)
        return value == 1 and string.format("%d %s", value, singular) or string.format("%02d %s", value, plural)
    end

    local shortFormat, longFormat
    if days > 0 then
        shortFormat = formatUnit(days, "Day left", "Days left")
        longFormat = formatUnit(days, "Day", "Days") .. string.format(" and %02d hours left", hours)
    elseif hours > 0 then
        shortFormat = formatUnit(hours, "Hour left", "Hours left")
        longFormat = formatUnit(hours, "Hour", "Hours") .. string.format(" and %02d minutes left", minutes)
    elseif minutes > 0 then
        shortFormat = formatUnit(minutes, "Minute left", "Minutes left")
        longFormat = formatUnit(minutes, "Minute", "Minutes") .. string.format(" and %02d seconds left", seconds)
    else
        shortFormat = string.format("%02d Seconds left", seconds)
        longFormat = shortFormat
    end
    return shortFormat, longFormat
end

local function getTimeUntil(timestamp)
    local timeLeft = timestamp - os.time()
    if timeLeft <= 0 then
        return "00:00:00:00"
    end

    local days = math.floor(timeLeft / 86400)
    local hours = math.floor((timeLeft % 86400) / 3600)
    local minutes = math.floor((timeLeft % 3600) / 60)
    local seconds = timeLeft % 60
    return string.format("%02d:%02d:%02d:%02d", days, hours, minutes, seconds)
end

local function timerEvent(widget, endTime)
    if not widget or not widget:isVisible() or os.time() > endTime then
        BattlePass.unlockTimerEvent = nil
        return
    end

    widget:setText(BattlePass:running() and (string.format("New missions available in: %s", getTimeUntil(endTime))) or "                              Expired")
    BattlePass.unlockTimerEvent = scheduleEvent(function()
        timerEvent(widget, endTime)
    end, 1000)
end

function BattlePass.redirectToStore()
    BattlePass.hide()
    g_game.openStore()
    g_game.requestStoreOffers(3, "", 20)
end

local function registerBattlePassProtocol()
    if battlePassProtocolRegistered then
        return
    end

    ProtocolGame.unregisterOpcode(BattlePassOpcode.Send)
    ProtocolGame.registerOpcode(BattlePassOpcode.Send, onBattlePassMessage)
    battlePassProtocolRegistered = true
end

local function unregisterBattlePassProtocol()
    if not battlePassProtocolRegistered then
        return
    end

    ProtocolGame.unregisterOpcode(BattlePassOpcode.Send)
    battlePassProtocolRegistered = false
end

local function setupBattlePassTabs()
    local tabBar = BattlePass.window and BattlePass.window.mainPanel and BattlePass.window.mainPanel.optionsTabBar
    if not tabBar then
        return
    end

    for tabId, config in pairs(battlePassTabs) do
        local button = tabBar:getChildById(tabId)
        if button then
            local icon = button:recursiveGetChildById('tabIcon')
            if icon then
                icon:setImageSource(config.icon)
            end

            local label = button:recursiveGetChildById('tabLabel')
            if label then
                label:setText(tr(config.title))
            end
        end
    end
end

function BattlePass.init()
    BattlePass.window = g_ui.displayUI('battlepass')
    BattlePass.hide()
    setupBattlePassTabs()

    BattlePass.missionPanel = BattlePass.window:recursiveGetChildById('missionPanel')
    BattlePass.progressPanel = BattlePass.window:recursiveGetChildById('progressPanel')
    BattlePass.shopPanel = BattlePass.window:recursiveGetChildById('battlePassShopPanel')
    BattlePass.outfitWidget = BattlePass.window:recursiveGetChildById('playerOutfit')
    BattlePass.scrollBarWidget = BattlePass.window:recursiveGetChildById('progressPanelScrollBar')

    BattlePass.scrollBarWidget.canChangeValue = function()
        return not BattlePass.isAnimatingWalk
    end

    local progressPanelContent = BattlePass.window:recursiveGetChildById('progressPanelContent')
    if progressPanelContent then
        progressPanelContent.onMousePress = function(widget, mousePos, button)
            if button == MouseLeftButton and not BattlePass.isAnimatingWalk then
                BattlePass.isDragging = true
                BattlePass.dragStartX = mousePos.x
                BattlePass.dragStartScrollValue = BattlePass.scrollBarWidget:getValue()
            end
        end

        progressPanelContent.onMouseMove = function(widget, mousePos)
            if BattlePass.isDragging and not BattlePass.isAnimatingWalk then
                local deltaX = mousePos.x - BattlePass.dragStartX
                local scrollChange = -deltaX * 1.5 -- Adjust the multiplier for sensitivity
                local newScrollValue = BattlePass.dragStartScrollValue + scrollChange
                newScrollValue = math.max(BattlePass.scrollBarWidget:getMinimum(), math.min(newScrollValue, BattlePass.scrollBarWidget:getMaximum()))
                BattlePass.scrollBarWidget:setValue(newScrollValue)
            end
        end

        progressPanelContent.onMouseRelease = function(widget, mousePos, button)
            if button == MouseLeftButton then
                BattlePass.isDragging = false
            end
        end
    end

    BattlePass.loadMenu('challengesMenu')
    onCreateRewardContainers()
    if BattlePassShop then
        BattlePassShop.init(BattlePass.shopPanel)
    end

    registerBattlePassProtocol()

    connect(g_game, {
        onGameStart = online,
        onGameEnd = offline,
        onResourceBalance = onResourceBalance,
    })

    if g_game.isOnline() then
        scheduleEvent(online, 50)
    end

    g_logger.info("Battle Pass loaded.")
end

function BattlePass.terminate()
    stopUnlockTimer()

    g_keyboard.unbindKeyPress('Tab', toggleNextWindow, BattlePass.window)

    unregisterBattlePassProtocol()

    disconnect(g_game, {
        onGameStart = online,
        onGameEnd = offline,
        onResourceBalance = onResourceBalance,
    })

    if BattlePass.dailyRerollWindow then
        BattlePass.dailyRerollWindow:destroy()
        BattlePass.dailyRerollWindow = nil
    end

    if BattlePassRewards and BattlePassRewards.claimRewardWindow then
        BattlePassRewards.claimRewardWindow:destroy()
        BattlePassRewards.claimRewardWindow = nil
    end

    if BattlePassRewards and BattlePassRewards.confirmRewardWindow then
        BattlePassRewards.confirmRewardWindow:destroy()
        BattlePassRewards.confirmRewardWindow = nil
    end

    if BattlePassShop then
        BattlePassShop.terminate()
    end

    if BattlePass.window then
        BattlePass.window:destroy()
        BattlePass.window = nil
    end
end

local function readBool(msg)
    return msg:getU8() ~= 0
end

local function getUnreadSize(msg)
    if msg and msg.getUnreadSize then
        return tonumber(msg:getUnreadSize()) or 0
    end
    return 0
end

local function drainUnreadMessage(msg)
    if msg and msg.getUnreadSize and msg.skipBytes then
        local unread = msg:getUnreadSize()
        if unread and unread > 0 then
            msg:skipBytes(unread)
        end
    end
end

local function readOutfit(msg)
    return {
        type = msg:getU16(),
        head = msg:getU8(),
        body = msg:getU8(),
        legs = msg:getU8(),
        feet = msg:getU8(),
        addons = msg:getU8(),
    }
end

local function readMission(msg)
    return {
        missionId = msg:getString(),
        missionName = msg:getString(),
        missionDescription = msg:getString(),
        currentProgress = msg:getU32(),
        maxProgress = msg:getU32(),
        rewardPoints = msg:getU16(),
    }
end

local function readMissionList(msg)
    local missions = {}
    local count = msg:getU16()
    for i = 1, count do
        missions[#missions + 1] = readMission(msg)
    end
    return missions
end

local function readThingValues(msg)
    local values = {}
    local count = msg:getU16()
    for i = 1, count do
        values[#values + 1] = {
            thingId = msg:getU16(),
            thingName = msg:getString(),
        }
    end
    return values
end

local function readOutfitGroups(msg)
    local groups = {}
    local groupCount = msg:getU8()
    for i = 1, groupCount do
        local groupId = msg:getU8()
        local outfitCount = msg:getU8()
        local outfits = {}
        for j = 1, outfitCount do
            outfits[#outfits + 1] = {
                looktype = msg:getU16(),
                name = msg:getString(),
            }
        end
        groups[groupId] = outfits
    end
    return groups
end

local function readRewardItems(msg)
    local items = {}
    local count = msg:getU16()
    for i = 1, count do
        items[#items + 1] = {
            itemId = msg:getU16(),
            count = msg:getU16(),
            stuck = readBool(msg),
        }
    end
    return items
end

local function readRewardSteps(msg)
    local chunk = readBool(msg)
    -- The server always writes first and total, including empty packets with chunk=false.
    local first = msg:getU16()
    local total = msg:getU16()
    local stepCount = msg:getU16()
    local steps = {}

    for i = 1, stepCount do
        local step = {
            stepId = msg:getU16(),
            rewards = {},
        }

        local rewardCount = msg:getU8()
        for j = 1, rewardCount do
            local reward = {
                rewardId = msg:getU32(),
                rewardType = msg:getU8(),
                freeReward = readBool(msg),
                itemId = msg:getU16(),
                count = msg:getU16(),
                charges = msg:getU16(),
                stuck = readBool(msg),
            }
            local claimed = readBool(msg)
            reward.hasClaimedReward = claimed
            -- Legacy UI code still reads the misspelled field.
            reward.hasClamedReward = claimed
            reward.durationTime = msg:getU32()
            reward.addons = msg:getU8()
            reward.randomValues = readThingValues(msg)
            reward.choosableValues = readThingValues(msg)
            reward.maleOutfit = readOutfitGroups(msg)
            reward.femaleOutfit = readOutfitGroups(msg)
            reward.items = readRewardItems(msg)
            step.rewards[#step.rewards + 1] = reward
        end

        steps[#steps + 1] = step
    end

    if chunk then
        return {
            chunk = true,
            first = first,
            total = total,
            steps = steps,
        }
    end

    return steps
end

local function parseBattlePassMissions(msg)
    local data = {
        playerOutfit = readOutfit(msg),
        beginTime = msg:getU32(),
        endTime = msg:getU32(),
        points = msg:getU32(),
        rerollPrice = msg:getU32(),
        deluxePrice = msg:getU32(),
        battlePassActive = readBool(msg),
        currentRewardStep = msg:getU16(),
        nextStepPoints = msg:getU32(),
        dailyBeginTime = msg:getU32(),
        dailyEndTime = msg:getU32(),
        dailyMissions = readMissionList(msg),
        generalMissions = readMissionList(msg),
    }
    if getUnreadSize(msg) >= 4 then
        data.shopPoints = msg:getU32()
        if getUnreadSize(msg) >= 1 then
            data.shopUnlocked = readBool(msg)
        end
    end

    if BattlePass.pendingOpen then
        BattlePass.pendingOpen = false
        BattlePass.loadMenu('challengesMenu')
    end
    BattlePass.onBattlePassMissionsFromServer(data)
end

local function parseBattlePassShop(msg)
    local data = {
        shopPoints = msg:getU32(),
        unlocked = readBool(msg),
        entries = {},
    }

    local count = msg:getU16()
    for _ = 1, count do
        table.insert(data.entries, {
            id = msg:getU16(),
            title = msg:getString(),
            description = msg:getString(),
            price = msg:getU32(),
            previewType = msg:getU8(),
            repeatable = readBool(msg),
            purchased = readBool(msg),
            itemId = msg:getU16(),
            lookType = msg:getU16(),
            addons = msg:getU8(),
        })
    end

    BattlePass.shopPoints = data.shopPoints
    BattlePass.shopUnlocked = data.unlocked == true
    if BattlePassShop then
        BattlePassShop.onShopData(data)
    end
end

onBattlePassMessage = function(protocol, msg)
    local ok, err = pcall(function()
        local response = msg:getU8()
        if response == BattlePassResponse.Missions then
            parseBattlePassMissions(msg)
        elseif response == BattlePassResponse.Rewards then
            BattlePass.onBattlePassRewards(readRewardSteps(msg))
        elseif response == BattlePassResponse.Shop then
            parseBattlePassShop(msg)
        elseif response == BattlePassResponse.Error then
            displayErrorBox(tr("Battle Pass"), msg:getString())
        else
            error("unknown response " .. tostring(response))
        end
    end)
    if not ok then
        drainUnreadMessage(msg)
        g_logger.error("[Battle Pass] Failed to parse server message: " .. tostring(err))
    end
    return true
end

online = function()
    registerBattlePassProtocol()

    -- Load battlepass config
    BattlePass:loadConfigJson()
    BattlePass:loadPlayerPosition()

    -- Reset daily mission panel
    local dailyMissionsPanel = BattlePass.window:recursiveGetChildById('dailyMissionsBg')
    dailyMissionsPanel:destroyChildren()
    for i = 1, 2 do
        local widget = g_ui.createWidget('DailyMissionWidget', dailyMissionsPanel)
        local imageBackground = widget:recursiveGetChildById('dailyMissionIconImage')
        local image = i == 1 and 'daily-free-icon' or 'daily-vip-icon'
        imageBackground:setImageSource('/images/game/battlepass/' .. image)
    end

    -- Reset mission panel
    local missionsPanel = BattlePass.window:recursiveGetChildById('missionsBackground')
    missionsPanel:destroyChildren()
    for i = 1, 26 do
        g_ui.createWidget('MissionWidget', missionsPanel)
    end

    if BattlePassRewards.claimRewardWindow then
        BattlePassRewards.claimRewardWindow:destroy()
        BattlePassRewards.claimRewardWindow = nil
    end

end

openBattlePass = function()
    if BattlePass.window:isVisible() then
        BattlePass.hide()
    elseif not g_game.isOnline() then
        return
    else
        BattlePass.pendingOpen = true
        BattlePass.shouldShow = true
        sendToServer("getMissions")
    end
end

function BattlePass.onBattlePassBarClick()
    openBattlePass()
end

offline = function()
    unregisterBattlePassProtocol()

    BattlePass.hide()
    BattlePass.lastRewardStep = BattlePass.currentRewardStep
    BattlePass.lastCameraPosition = getRewardPosition(BattlePass.currentRewardStep).scrollPosition
    BattlePass.outfitWidget:setMarginLeft(165)
    BattlePass:saveConfigJson()
    stopUnlockTimer()

    if BattlePassRewards.claimRewardWindow then
        BattlePassRewards.claimRewardWindow:destroy()
        BattlePassRewards.claimRewardWindow = nil
    end

    if BattlePassRewards.confirmRewardWindow then
        BattlePassRewards.confirmRewardWindow:destroy()
        BattlePassRewards.confirmRewardWindow = nil
    end

    if BattlePass.dailyRerollWindow then
        BattlePass.dailyRerollWindow:destroy()
        BattlePass.dailyRerollWindow = nil
    end

end

function BattlePass:showBattlePass()
    BattlePass.show()
end

function BattlePass.show()
    BattlePass.window:show(true)
    BattlePass.window:raise()
    BattlePass.window:focus()

    g_keyboard.unbindKeyPress('Tab', toggleNextWindow, BattlePass.window)
    g_keyboard.bindKeyPress('Tab', toggleNextWindow, BattlePass.window)
    updateGoldBalance()
end

function BattlePass.hide()
    if not BattlePass.window then
        return
    end

    BattlePass.window:hide()
    g_keyboard.unbindKeyPress('Tab', toggleNextWindow, BattlePass.window)
    stopUnlockTimer()
    stopPendingRewardsSchedule()
end

onCreateRewardContainers = function()
    local progressPanelContent = BattlePass.window:recursiveGetChildById('progressPanelContent')
    if not progressPanelContent then return end

    for i, data in ipairs(RewardPositions) do
        for rewardType, position in pairs(data.positions) do
            local rewardWidgetId = rewardType .. "RewardWidget" .. i
            local rewardWidget = g_ui.createWidget('RewardWidget', progressPanelContent)
            rewardWidget:setId(rewardWidgetId)
            rewardWidget:setMarginLeft(position.marginLeft)
            rewardWidget:setMarginTop(position.marginTop)
            rewardWidget:setVisible(false)

            local rewardBoxImage = rewardWidget:recursiveGetChildById("rewardBoxImage")
            if rewardType == "free" then
                rewardBoxImage:setImageSource("/images/game/battlepass/free-reward-chest")
                rewardBoxImage:setImageClip("30 32 29 31")
            else
                rewardBoxImage:setImageSource("/images/game/battlepass/vip-reward-chest")
                rewardBoxImage:setImageClip("30 32 29 31")
            end
            rewardBoxImage:setTooltip(string.format("Battle Pass %s Reward\nUnlocked at level %d", string.capitalize(rewardType), i))

            rewardWidget.rewardBox.onClick = function()
                BattlePass.scrollBarWidget:setValue(RewardPositions[i].scrollPosition)
                BattlePassRewards:onConfirmClaimReward(i, rewardType)
            end

            local blockedRewardId = rewardType .. "BlockedRewardWidget" .. i
            local blockedReward = g_ui.createWidget('BlockedRewardWidget', progressPanelContent)
            blockedReward:setId(blockedRewardId)
            blockedReward:setMarginLeft(position.marginLeft)
            blockedReward:setMarginTop(position.marginTop)
            blockedReward:setVisible(true)
            local lockedBoxImage = blockedReward:recursiveGetChildById("lockedBoxImage")
            if rewardType == "free" then
                lockedBoxImage:setImageSource("/images/game/battlepass/free-reward-chest")
            else
                lockedBoxImage:setImageSource("/images/game/battlepass/vip-reward-chest")
            end
            lockedBoxImage:setTooltip(string.format("Battle Pass %s Reward\nUnlock at level %d", string.capitalize(rewardType), i))
        end
    end
end

function BattlePass.loadMenu(menuId)
    stopPendingRewardsSchedule()
    BattlePass.currentMenuId = menuId

    local buttons = {
        challengesMenuButton = 'challengesMenu',
        rewardsMenuButton = 'rewardsMenu',
        shopMenuButton = 'shopMenu'
    }

    -- if menuId == 'challengesMenu' and not BattlePass:running() then
    --     menuId = 'rewardsMenu'
    -- end

    for buttonName, buttonId in pairs(buttons) do
        local button = BattlePass.window.mainPanel.optionsTabBar:getChildById(buttonId)
        if button then
            button:setChecked(false)
        end
    end

    local selectedButton = BattlePass.window.mainPanel.optionsTabBar:getChildById(menuId)
    if selectedButton then
        selectedButton:setChecked(true)
    end

    local shopPointsPanel = BattlePass.window:recursiveGetChildById('battlePassShopPointsPanel')
    if shopPointsPanel then
        shopPointsPanel:setVisible(true)
    end

    if menuId == 'challengesMenu' then
        BattlePass.missionPanel:show(true)
        BattlePass.shopPanel:hide()
        if g_game.isOnline() and BattlePass.progressPanel:isVisible() then
            local nextUnlock = BattlePass.getNextResetWeek(BattlePass.calculateWeekNumber())
            local unlockInfo = BattlePass.window:recursiveGetChildById("unlockInfo")
            stopUnlockTimer()
            timerEvent(unlockInfo, nextUnlock)
        end

        BattlePass.progressPanel:hide()
        BattlePass.window:setHeight(595)
    elseif menuId == 'rewardsMenu' then
        BattlePass.shopPanel:hide()
        BattlePass.scrollBarWidget:setValue(BattlePass.lastCameraPosition)
        BattlePass.outfitWidget:setDirection(BattlePass.currentRewardStep == 0 and East or North)
        sendToServer("getRewards")

        BattlePass.pendingRewardsSchedule = scheduleEvent(function()
            BattlePass.pendingRewardsSchedule = nil
            if BattlePass.currentMenuId ~= 'rewardsMenu' or not BattlePass.window or not BattlePass.window:isVisible() then
                return
            end

            BattlePass.missionPanel:hide()
            BattlePass.progressPanel:show(true)
            BattlePass.window:setHeight(515)
            BattlePass:updatePlayerPosition()
        end, 50)
    elseif menuId == 'shopMenu' then
        BattlePass.missionPanel:hide()
        BattlePass.progressPanel:hide()
        BattlePass.shopPanel:show(true)
        BattlePass.window:setHeight(515)
        if BattlePassShop then
            BattlePassShop.requestRefresh()
        end
    end

end

toggleNextWindow = function()
    local widgetList = {
        "challengesMenu",
        "rewardsMenu",
        "shopMenu"
    }

    local selectedIndex = nil
    for i, widget in ipairs(widgetList) do
        if widget == BattlePass.currentMenuId then
            selectedIndex = i
            break
        end
    end

    if not selectedIndex then
        selectedIndex = 1
    end

    local nextWidgetId = (selectedIndex == #widgetList and 1 or selectedIndex + 1)
    BattlePass.currentMenuId = widgetList[nextWidgetId]
    BattlePass.loadMenu(BattlePass.currentMenuId)
end

function BattlePass.onBattlePassMissionsFromServer(data)
    -- Converter outfit JSON para formato do client
    if data.playerOutfit then
        local o = data.playerOutfit
        BattlePass.outfitWidget:setOutfit({
            type = o.type or 0,
            head = o.head or 0,
            body = o.body or 0,
            legs = o.legs or 0,
            feet = o.feet or 0,
            addons = o.addons or 0,
        })
    end

    BattlePass.beginTime = data.beginTime or 0
    BattlePass.endTime = data.endTime or 0
    BattlePass.progressPoints = data.points or 0
    BattlePass.dailyRerollPrice = data.rerollPrice or 0
    BattlePass.premiumBattlepass = data.battlePassActive or false
    BattlePass.currentRewardStep = data.currentRewardStep or 0
    BattlePass.nextStepPoints = data.nextStepPoints or 0
    BattlePass.dailyMissionsBegin = data.dailyBeginTime or 0
    BattlePass.dailyMissionsExpire = data.dailyEndTime or 0
    if data.shopPoints ~= nil then
        BattlePass.shopPoints = data.shopPoints
    end
    if data.shopUnlocked ~= nil then
        BattlePass.shopUnlocked = data.shopUnlocked == true
    end

    BattlePass.dailyMissions = data.dailyMissions or {}
    BattlePass.seasonMissions = data.generalMissions or {}

    if BattlePassShop then
        BattlePassShop.updateBalance(BattlePass.shopPoints, BattlePass.shopUnlocked)
    end

    local getVipPassTicketButton = BattlePass.window:recursiveGetChildById('getVipPassTicket')
    local getVipPassTicketBorder = BattlePass.window:recursiveGetChildById('getVipPassTicketBorder')
    if getVipPassTicketButton then
        getVipPassTicketButton:setVisible(not BattlePass.premiumBattlepass)
        getVipPassTicketBorder:setVisible(not BattlePass.premiumBattlepass)
    end

    BattlePass:configureMissionPanel()

    -- Reset player data in case of season ends
    if BattlePass.currentRewardStep == 0 then
        BattlePass.lastCameraPosition = 0
        BattlePass.lastRewardStep = 0
        BattlePass.outfitWidget:setMarginLeft(165)
        BattlePass.scrollBarWidget:setValue(0)
    end
end

function BattlePass.onBattlePassRewards(rewardSteps)
    if type(rewardSteps) == "table" and rewardSteps.chunk then
        local total = tonumber(rewardSteps.total) or 0
        local first = tonumber(rewardSteps.first) or 1
        local steps = rewardSteps.steps or {}

        if first <= 1 or not BattlePass.rewardChunkBuffer then
            BattlePass.rewardChunkBuffer = {}
        end

        for _, step in ipairs(steps) do
            local stepId = tonumber(step.stepId)
            if stepId then
                BattlePass.rewardChunkBuffer[stepId] = step
            end
        end

        if total > 0 then
            for stepId = 1, total do
                if not BattlePass.rewardChunkBuffer[stepId] then
                    return
                end
            end

            local assembledRewards = {}
            for stepId = 1, total do
                table.insert(assembledRewards, BattlePass.rewardChunkBuffer[stepId])
            end

            BattlePass.rewardChunkBuffer = nil
            rewardSteps = assembledRewards
        end
    end

    BattlePass.rewardSteps = rewardSteps or {}
    BattlePass:configureRewardPanel()
end

function BattlePass.calculateWeekNumber()
    if (tonumber(BattlePass.beginTime) or 0) <= 0 then
        return 1
    end

    local targetTime = os.time()
    local begindate = os.time{year=os.date("*t", BattlePass.beginTime).year, month=os.date("*t", BattlePass.beginTime).month, day=os.date("*t", BattlePass.beginTime).day, hour=10, min=0, sec=0}
    local diffSeconds = os.difftime(targetTime, begindate)
    if diffSeconds <= 0 then
        return 1
    end

    local weekNumber = math.ceil(diffSeconds / 604800)
    return math.max(1, weekNumber)
end

function BattlePass.getNextResetWeek(currentIndex)
    if (tonumber(BattlePass.beginTime) or 0) <= 0 then
        return os.time()
    end

    local nextDays = 7 * currentIndex
    local begindate = os.time{year=os.date("*t", BattlePass.beginTime).year, month=os.date("*t", BattlePass.beginTime).month, day=os.date("*t", BattlePass.beginTime).day, hour=10, min=0, sec=0}
    local nextResetTime = begindate + (nextDays * 86400)
    local tableDate = os.date("*t", nextResetTime)
    return os.time{year=tableDate.year, month=tableDate.month, day=tableDate.day, hour=10, min=0, sec=0}
end

function BattlePass:configureMissionPanel()
    if not BattlePass.window:isVisible() and BattlePass.shouldShow then
        BattlePass.shouldShow = false
        BattlePass:showBattlePass(true)
    end

    -- Current reward points
    BattlePass.window:recursiveGetChildById("playerLevel"):setText(BattlePass.currentRewardStep)
    BattlePass.window:recursiveGetChildById("currentlyLevelText"):setText(string.format("%s/%s", BattlePass.progressPoints, BattlePass.nextStepPoints))
    BattlePass.window:recursiveGetChildById("levelProgress"):setPercent(safePercent(BattlePass.progressPoints, BattlePass.nextStepPoints))

    -- BattlePass end time
    local seasonTotalTime = BattlePass.endTime - BattlePass.beginTime
    local timeRemaining = BattlePass.endTime - os.time()
    local seasonPercent = safePercent(timeRemaining, seasonTotalTime)
    local seasonTimeText, seasonTimeTooltip = getFormatedTime(BattlePass.endTime)
    BattlePass.window:recursiveGetChildById("seasonTimeText"):setText(seasonTimeText)
    BattlePass.window:recursiveGetChildById("seasonHourglassIcon"):setTooltip(seasonTimeTooltip)
    BattlePass.window:recursiveGetChildById("seasonTimeProgress"):setPercent(seasonPercent)

    -- Next unlocked missions
    local nextUnlock = BattlePass.getNextResetWeek(BattlePass.calculateWeekNumber())
    local unlockInfo = BattlePass.window:recursiveGetChildById("unlockInfo")
    unlockInfo:setText(string.format("New missions available in: %s", getTimeUntil(nextUnlock)))
    stopUnlockTimer()
    timerEvent(unlockInfo, nextUnlock)

    -- Daily end time
    local dailyTotalTime = BattlePass.dailyMissionsExpire - BattlePass.dailyMissionsBegin
    local dailyTimeRemaining = BattlePass.dailyMissionsExpire - os.time()
    local dailyPercent = safePercent(dailyTimeRemaining, dailyTotalTime)
    local dailyTimeText, dailyTimeTooltip = getFormatedTime(BattlePass.dailyMissionsExpire)
    BattlePass.window:recursiveGetChildById("dailyTimeText"):setText(dailyTimeText)
    BattlePass.window:recursiveGetChildById("hourglassIcon"):setTooltip(dailyTimeTooltip)
    BattlePass.window:recursiveGetChildById("dailyTimeProgress"):setPercent(dailyPercent)

    -- Daily Missions
    local dailyMissionsPanel = BattlePass.window:recursiveGetChildById('dailyMissionsBg')

    for k, v in ipairs(BattlePass.dailyMissions) do
        if k > 2 then
            print(string.format("[WARNING] Daily mission count is higher than 2 missions. (%s)", #BattlePass.dailyMissions))
            break
        end

        local widget = dailyMissionsPanel:getChildByIndex(getMissionIndex(k))
        local currentProgress = tonumber(v.currentProgress) or 0
        local maxProgress = tonumber(v.maxProgress) or 0
        local completed = maxProgress > 0 and currentProgress >= maxProgress

        widget:recursiveGetChildById("dailyMissionName"):setText(v.missionName or "")
        widget:recursiveGetChildById("dailyMissionPoints"):setText(v.rewardPoints or 0)
        widget:recursiveGetChildById("dailyMissionProgress"):setPercent(safePercent(currentProgress, maxProgress))
        widget:recursiveGetChildById("dailyMissionProgressText"):setText(string.format("%s/%s", aggresiveNumberToStr(currentProgress), aggresiveNumberToStr(maxProgress)))
        widget:recursiveGetChildById("dailyMissionInformation"):setTooltip(v.missionDescription or "")
        widget:recursiveGetChildById("dailyBlockedMissionIcon"):setVisible(false)
        widget:recursiveGetChildById("dailyFreeIcon"):setVisible(false)
        widget:recursiveGetChildById("dailyRerollButton"):setVisible(not completed)
        widget:recursiveGetChildById("dailyRerollButton").onClick = function() if not BattlePass:running() then return true end BattlePass:rerollDailyMission(v) end

        local icon = (k == 1 and "daily-free-icon" or "daily-vip-icon")
        if completed then
            icon = "daily-icon-complete"
        end

        widget:recursiveGetChildById("dailyMissionIconImage"):setImageSource("/images/game/battlepass/" .. icon)
        widget:recursiveGetChildById("dailyProgressPanel"):setVisible(not completed)
        widget:recursiveGetChildById("dailyCompletedIcon"):setVisible(completed)

        if not BattlePass:running() then
            widget:setEnabled(false)
            widget:setVisible(false)
        end
    end

    -- General missions
    local missionsPanel = BattlePass.window:recursiveGetChildById('missionsBackground')
    local orderedWithIndex = getOrderedMissions(BattlePass.seasonMissions)

    for k, v in ipairs(orderedWithIndex) do
        local data = v.data
        local widget = missionsPanel:getChildByIndex(v.index)
        if not widget then
            break
        end

        local currentProgress = tonumber(data.currentProgress) or 0
        local maxProgress = tonumber(data.maxProgress) or 0

        widget:recursiveGetChildById("missionName"):setText(data.missionName or "")
        widget:recursiveGetChildById("missionPoints"):setText(data.rewardPoints or 0)
        widget:recursiveGetChildById("missionProgress"):setPercent(safePercent(currentProgress, maxProgress))
        widget:recursiveGetChildById("missionProgressText"):setText(string.format("%s/%s", aggresiveNumberToStr(currentProgress), aggresiveNumberToStr(maxProgress)))
        widget:recursiveGetChildById("missionInformation"):setTooltip(data.missionDescription or "")
        widget:recursiveGetChildById("blockedMissionIcon"):setVisible(false)

        local completed = maxProgress > 0 and currentProgress >= maxProgress
        local missionIconBase = MissionRankIcons[data.rewardPoints] or "mission-locked-icon"
        local missionIcon = completed and MissionRankIcons[data.rewardPoints] and missionIconBase .. "-complete" or missionIconBase
        widget:recursiveGetChildById("missionIconImage"):setImageSource("/images/game/battlepass/" .. missionIcon)
        widget:recursiveGetChildById("progressPanel"):setVisible(not completed)
        widget:recursiveGetChildById("completedIcon"):setVisible(completed)
        if not BattlePass:running() then
            widget:setEnabled(false)
            widget:setVisible(false)
        end
    end
end

function BattlePass:configureRewardPanel()
    local rewardPanel = BattlePass.window:recursiveGetChildById('progressPanelContent')
    if not rewardPanel then
        return
    end

    for k, v in ipairs(BattlePass.rewardSteps) do
        for i, reward in ipairs(v.rewards) do
            local rewardType = reward.freeReward and "free" or "premium"
            local rewardWidget = rewardPanel:getChildById(rewardType .. "RewardWidget" .. v.stepId)
            local blockedReward = rewardPanel:getChildById(rewardType .. "BlockedRewardWidget" .. v.stepId)
            if rewardWidget and blockedReward then
                local availableReward = v.stepId <= BattlePass.currentRewardStep
                blockedReward:setVisible(not availableReward)
                rewardWidget:setVisible(availableReward)

                local enabled = not reward.hasClamedReward
                local text = reward.hasClamedReward and "Claimed" or "Claim Reward"
                if not availableReward then
                    text = "Locked"
                    enabled = false
                elseif not reward.freeReward and not BattlePass.premiumBattlepass and availableReward then
                    text = "Deluxe"
                    enabled = false
                end

                rewardWidget:recursiveGetChildById("collectRewardLabel"):setText(text)
                rewardWidget:recursiveGetChildById("rewardBox"):setEnabled(enabled)
                local rewardBoxImage = rewardWidget:recursiveGetChildById("rewardBoxImage")
                if reward.hasClamedReward then
                    if rewardType == "free" then
                        rewardBoxImage:setImageSource("/images/game/battlepass/free-reward-chest-open")
                        rewardBoxImage:setImageClip("26 22 38 42")
                        rewardBoxImage:setSize("38 42")
                        rewardBoxImage:setMarginTop(-10)
                    else
                        rewardBoxImage:setImageSource("/images/game/battlepass/vip-reward-chest-open")
                        rewardBoxImage:setImageClip("24 20 40 44")
                        rewardBoxImage:setSize("40 44")
                        rewardBoxImage:setMarginTop(-12)
                    end
                else
                    if rewardType == "free" then
                        rewardBoxImage:setImageSource("/images/game/battlepass/free-reward-chest")
                        rewardBoxImage:setImageClip("30 32 29 31")

                    else
                        rewardBoxImage:setImageSource("/images/game/battlepass/vip-reward-chest")
                        rewardBoxImage:setImageClip("30 32 29 31")
                    end
                end
                local rewardTypeText = reward.freeReward and "Free" or "Deluxe"
                rewardBoxImage:setTooltip(string.format("Battle Pass %s Reward\n%s at level %d", string.capitalize(rewardTypeText), (reward.hasClamedReward and "Claimed" or "Unlocked"), v.stepId))

                -- Set lockedBoxImage for blocked rewards (always closed chest)
                local lockedBoxImage = blockedReward:recursiveGetChildById("lockedBoxImage")
                if rewardType == "free" then
                    lockedBoxImage:setImageSource("/images/game/battlepass/free-reward-chest")
                else
                    lockedBoxImage:setImageSource("/images/game/battlepass/vip-reward-chest")
                end
                lockedBoxImage:setTooltip(string.format("Battle Pass %s Reward\nUnlock at level %d", string.capitalize(rewardTypeText), v.stepId))
            end
        end
    end
end

function BattlePass:getStepsToReward(rewardStep)
    rewardStep = tonumber(rewardStep) or 0
    local stepsToReward = 0
    for i, data in ipairs(RewardPositions) do
        if i <= rewardStep then
            stepsToReward = stepsToReward + data.stepsTo
        end
    end
    return stepsToReward
end

function BattlePass:loadPlayerPosition()
    -- First execution
    local stepsToReward = BattlePass:getStepsToReward(BattlePass.lastRewardStep)
    if stepsToReward == 0 then
        return
    end

    local newProgress = BattlePass.rewardMinMargin + stepsToReward * 32
    local playerProgress = math.max(BattlePass.rewardMinMargin, math.min(newProgress, BattlePass.rewardMaxMargin))

    BattlePass.outfitWidget:setMarginLeft(playerProgress)
    BattlePass.scrollBarWidget:setValue(BattlePass.lastCameraPosition)
end

function BattlePass:updatePlayerPosition()
    local stepsToReward = BattlePass:getStepsToReward(BattlePass.currentRewardStep)
    local newProgress = BattlePass.rewardMinMargin + stepsToReward * 32
    local playerProgress = math.max(BattlePass.rewardMinMargin, math.min(newProgress, BattlePass.rewardMaxMargin))

    if playerProgress > 195 then
        BattlePass.lastCameraPosition = getRewardPosition(BattlePass.lastRewardStep).scrollPosition
        BattlePass:doAnimatePlayerMove(playerProgress)
    end

    -- Force save data
    BattlePass:saveConfigJson()
end

function BattlePass:running()
    local timeLeft = BattlePass.endTime - os.time()
    if timeLeft <= 0 then
        return false
    end

    return true
end

function BattlePass:doAnimatePlayerMove(targetMargin)
    if targetMargin == BattlePass.outfitWidget:getMarginLeft() then
        return
    end

    BattlePass.outfitWidget:setDirection(East)
    setOutfitStaticWalking(true)

    BattlePass.isAnimatingWalk = true
    local currentMargin = BattlePass.outfitWidget:getMarginLeft()
    local scrollBar = BattlePass.scrollBarWidget

    local function finishAnimation()
        BattlePass.outfitWidget:setMarginLeft(targetMargin)
        setOutfitStaticWalking(false)
        BattlePass.isAnimatingWalk = false
        BattlePass.lastRewardStep = BattlePass.currentRewardStep
        BattlePass.lastCameraPosition = getRewardPosition(BattlePass.currentRewardStep).scrollPosition

        -- Force save data
        BattlePass:saveConfigJson()

        scheduleEvent(function()
            BattlePass.outfitWidget:setDirection(North)
        end, 150)
    end

    local function animateStep()
        if not BattlePass.outfitWidget:isVisible() then
            finishAnimation()
            return true
        end

        if currentMargin < targetMargin then
            currentMargin = math.min(currentMargin + 3, targetMargin)
            BattlePass.outfitWidget:setMarginLeft(currentMargin)
            if currentMargin < targetMargin then
                scheduleEvent(animateStep, 25)
                if currentMargin >= 350 then
                    scrollBar:setValue(scrollBar:getValue() + 3)
                end
            else
                finishAnimation()
            end
        else
            finishAnimation()
        end
    end

    animateStep()
end

function BattlePass:loadConfigJson()
    local loadedPlayerId = getLoadedPlayerId()
    if not loadedPlayerId then return end

    local file = "/characterdata/" .. loadedPlayerId .. "/battlepass.json"
    if g_resources.fileExists(file) then
        local status, result = pcall(function()
            return json.decode(g_resources.readFileContents(file))
        end)

        if not status then
            return g_logger.error("Error while reading characterdata file. Details: " .. result)
        end

        if type(result) ~= "table" then
            result = {}
        end

        BattlePass.lastRewardStep = result.currentRewardStep or 0
        BattlePass.lastCameraPosition = result.lastCameraPosition or 0
    else
        BattlePass.lastRewardStep = 0
        BattlePass.lastCameraPosition = 0
    end
end

function BattlePass:saveConfigJson()
    local config = { currentRewardStep = BattlePass.lastRewardStep, lastCameraPosition = BattlePass.lastCameraPosition }
    local loadedPlayerId = getLoadedPlayerId()
    if not loadedPlayerId then return end

    local file = "/characterdata/" .. loadedPlayerId .. "/battlepass.json"
    local status, result = pcall(function() return json.encode(config, 2) end)
    if not status then
        return g_logger.error("Error while saving profile Battlepass data. Data won't be saved. Details: " .. result)
    end

    if result:len() > 100 * 1024 * 1024 then
        return g_logger.error("Something went wrong, file is above 100MB, won't be saved")
    end
    g_resources.writeFileContents(file, result)
end

function BattlePass:rerollDailyMission(data)
    if BattlePass.dailyRerollWindow then
        BattlePass.dailyRerollWindow:destroy()
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    BattlePass.hide()

    local okButton = function()
        BattlePass.dailyRerollWindow:destroy()
        BattlePass.dailyRerollWindow = nil
        sendToServer("reroll", { missionId = data.missionId })
    end

    local cancelButton = function()
        BattlePass.dailyRerollWindow:destroy()
        BattlePass.dailyRerollWindow = nil
        BattlePass:showBattlePass()
    end

    local message = string.format("Are you sure you want to reroll the mission %s for %s gold?", data.missionName, comma_value(BattlePass.dailyRerollPrice))

    BattlePass.dailyRerollWindow = displayGeneralBox(tr('Confirm mission reroll'), message, {
        { text=tr('Ok'), callback = okButton },
        { text=tr('Cancel'), callback = cancelButton },
    }, okButton, cancelButton)
end

onResourceBalance = function(resourceType)
    if resourceType and resourceType ~= ResourceBank and resourceType ~= ResourceInventary then
        return
    end

    updateGoldBalance()
end
