local onBattlePassMessage
local online
local offline
local openBattlePass
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
    BattlePass.animationEvent = nil
    BattlePass.directionEvent = nil
    BattlePass.startupEvent = nil
    BattlePass.bannerLoadEvent = nil
    BattlePass.viewportLoadEvent = nil
    BattlePass.lastRewardStep = 0
    BattlePass.lastCameraPosition = 0

    -- Common variables
    BattlePass.rewardMinMargin = 195
    BattlePass.rewardMaxMargin = 28600
end

local BATTLEPASS_BANNER_SOURCE = '/images/game/battlepass/battlePass-anim'
local MAP_SOURCE_PREFIX = '/images/game/battlepass/map/battlepass-background_'
local MAP_FRAGMENT_WIDTH = 384
local MAP_FRAGMENT_COUNT = 77
local MAP_LAST_SOURCE_INDEX = 46
local MAP_OVERSCAN = 1
local REWARD_OVERSCAN = 300

local function rewardKey(step, rewardType)
    return rewardType .. ':' .. step
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

local function stopStartupEvent()
    if BattlePass.startupEvent then
        removeEvent(BattlePass.startupEvent)
        BattlePass.startupEvent = nil
    end
end

local function stopBannerLoad()
    if BattlePass.bannerLoadEvent then
        removeEvent(BattlePass.bannerLoadEvent)
        BattlePass.bannerLoadEvent = nil
    end
end

local function stopViewportLoad()
    if BattlePass.viewportLoadEvent then
        removeEvent(BattlePass.viewportLoadEvent)
        BattlePass.viewportLoadEvent = nil
    end
    BattlePass.pendingMapLoads = nil
    BattlePass.pendingMapLoadIndex = nil
    BattlePass.viewportGeneration = (BattlePass.viewportGeneration or 0) + 1
end

local function unloadTexture(source)
    if source and g_textures and g_textures.unload then
        g_textures.unload(source)
    end
end

local function releaseBannerTexture()
    stopBannerLoad()
    if BattlePass.bannerWidget and not BattlePass.bannerWidget:isDestroyed() then
        BattlePass.bannerWidget:setImageSource('')
    end
    if BattlePass.bannerTextureLoaded then
        unloadTexture(BATTLEPASS_BANNER_SOURCE)
        BattlePass.bannerTextureLoaded = false
    end
end

local function scheduleBannerLoad()
    if BattlePass.bannerTextureLoaded or BattlePass.bannerLoadEvent or not BattlePass.bannerWidget then
        return
    end

    BattlePass.bannerLoadEvent = scheduleEvent(function()
        BattlePass.bannerLoadEvent = nil
        if not BattlePass.window or not BattlePass.window:isVisible() or BattlePass.currentMenuId ~= 'challengesMenu' then
            return
        end
        if not BattlePass.bannerWidget or BattlePass.bannerWidget:isDestroyed() then
            return
        end

        BattlePass.bannerWidget:setImageSource(BATTLEPASS_BANNER_SOURCE)
        BattlePass.bannerTextureLoaded = true
    end, 30)
end

local processMapLoadQueue

processMapLoadQueue = function()
    BattlePass.viewportLoadEvent = nil
    local jobs = BattlePass.pendingMapLoads
    local index = BattlePass.pendingMapLoadIndex or 1
    if not jobs or index > #jobs then
        BattlePass.pendingMapLoads = nil
        BattlePass.pendingMapLoadIndex = nil
        return
    end

    local job = jobs[index]
    BattlePass.pendingMapLoadIndex = index + 1
    local widget = job.widget
    if widget and not widget:isDestroyed() and widget.battlePassTargetIndex == job.fragmentIndex and
        job.generation == BattlePass.viewportGeneration then
        widget:setImageSource(job.source)
        widget.battlePassSource = job.source
        BattlePass.loadedMapSources[job.source] = true
    end

    if BattlePass.pendingMapLoadIndex <= #jobs then
        BattlePass.viewportLoadEvent = scheduleEvent(processMapLoadQueue, 10)
    else
        BattlePass.pendingMapLoads = nil
        BattlePass.pendingMapLoadIndex = nil
    end
end

local function updateMapViewport(scrollValue)
    if not BattlePass.progressPanelContent or not BattlePass.window or not BattlePass.window:isVisible() or
        BattlePass.currentMenuId ~= 'rewardsMenu' then
        return
    end

    stopViewportLoad()
    BattlePass.mapWidgets = BattlePass.mapWidgets or {}
    BattlePass.loadedMapSources = BattlePass.loadedMapSources or {}

    local viewportWidth = BattlePass.progressScrollArea and BattlePass.progressScrollArea:getWidth() or 970
    local poolSize = math.min(MAP_FRAGMENT_COUNT, math.ceil(viewportWidth / MAP_FRAGMENT_WIDTH) + MAP_OVERSCAN * 2)
    local firstFragment = math.floor((tonumber(scrollValue) or 0) / MAP_FRAGMENT_WIDTH) - MAP_OVERSCAN
    firstFragment = math.max(0, math.min(firstFragment, MAP_FRAGMENT_COUNT - poolSize))
    local center = (tonumber(scrollValue) or 0) + viewportWidth / 2
    local jobs = {}
    local generation = BattlePass.viewportGeneration

    for slot = 1, poolSize do
        local fragmentIndex = firstFragment + slot - 1
        local widget = BattlePass.mapWidgets[slot]
        if not widget or widget:isDestroyed() then
            widget = g_ui.createWidget('MapFragment', BattlePass.progressPanelContent)
            widget:setId('battlePassMapFragment' .. slot)
            BattlePass.mapWidgets[slot] = widget
        end

        widget:setMarginLeft(MAP_FRAGMENT_WIDTH * fragmentIndex)
        widget:setVisible(true)
        widget.battlePassTargetIndex = fragmentIndex
        local source = MAP_SOURCE_PREFIX .. math.min(fragmentIndex, MAP_LAST_SOURCE_INDEX)
        if widget.battlePassSource ~= source then
            widget:setImageSource('')
            widget.battlePassSource = nil
            jobs[#jobs + 1] = {
                widget = widget,
                source = source,
                fragmentIndex = fragmentIndex,
                generation = generation,
                distance = math.abs(MAP_FRAGMENT_WIDTH * (fragmentIndex + 0.5) - center),
            }
        end
    end

    for slot = poolSize + 1, #BattlePass.mapWidgets do
        local widget = BattlePass.mapWidgets[slot]
        if widget and not widget:isDestroyed() then
            widget:setImageSource('')
            widget:setVisible(false)
            widget.battlePassSource = nil
            widget.battlePassTargetIndex = nil
        end
    end

    local desiredSources = {}
    for slot = 1, poolSize do
        local fragmentIndex = firstFragment + slot - 1
        desiredSources[MAP_SOURCE_PREFIX .. math.min(fragmentIndex, MAP_LAST_SOURCE_INDEX)] = true
    end
    for source in pairs(BattlePass.loadedMapSources) do
        if not desiredSources[source] then
            unloadTexture(source)
            BattlePass.loadedMapSources[source] = nil
        end
    end

    if #jobs > 0 then
        table.sort(jobs, function(left, right) return left.distance < right.distance end)
        BattlePass.pendingMapLoads = jobs
        BattlePass.pendingMapLoadIndex = 1
        BattlePass.viewportLoadEvent = scheduleEvent(processMapLoadQueue, 1)
    end
end

local function configureRewardWidget(widget, step, rewardType, reward)
    local available = reward ~= nil and step <= BattlePass.currentRewardStep
    local claimed = reward ~= nil and reward.hasClaimedReward == true
    local premiumLocked = reward ~= nil and not reward.freeReward and not BattlePass.premiumBattlepass
    local enabled = available and not claimed and not premiumLocked
    local text = 'Locked'
    if claimed then
        text = 'Claimed'
    elseif premiumLocked and available then
        text = 'Deluxe'
    elseif available then
        text = 'Claim Reward'
    end

    widget.battlePassStep = step
    widget.battlePassRewardType = rewardType
    widget.battlePassEnabled = enabled
    widget.battlePassLabel:setText(text)
    widget.battlePassBox:setEnabled(enabled)
    widget.battlePassBox:setOpacity(available and 1 or 0.8)

    local image = widget.battlePassImage
    if claimed and rewardType == 'free' then
        image:setImageSource('/images/game/battlepass/free-reward-chest-open')
        image:setImageClip('26 22 38 42')
        image:setSize('38 42')
        image:setMarginTop(-10)
    elseif claimed then
        image:setImageSource('/images/game/battlepass/vip-reward-chest-open')
        image:setImageClip('24 20 40 44')
        image:setSize('40 44')
        image:setMarginTop(-12)
    else
        image:setImageSource(rewardType == 'free' and '/images/game/battlepass/free-reward-chest' or '/images/game/battlepass/vip-reward-chest')
        image:setImageClip('30 32 29 31')
        image:setSize('29 31')
        image:setMarginTop(0)
    end

    local rewardName = rewardType == 'free' and 'Free' or 'Deluxe'
    local stateText = claimed and 'Claimed' or (available and 'Unlocked' or 'Unlock')
    image:setTooltip(string.format('Battle Pass %s Reward\n%s at level %d', rewardName, stateText, step))
end

local function acquireRewardWidget()
    BattlePass.rewardWidgetPool = BattlePass.rewardWidgetPool or {}
    local widget = table.remove(BattlePass.rewardWidgetPool)
    if not widget or widget:isDestroyed() then
        widget = g_ui.createWidget('RewardWidget', BattlePass.progressPanelContent)
        BattlePass.rewardWidgetSerial = (BattlePass.rewardWidgetSerial or 0) + 1
        widget.battlePassPoolId = 'battlePassRewardPool' .. BattlePass.rewardWidgetSerial
        widget.battlePassBox = widget:recursiveGetChildById('rewardBox')
        widget.battlePassLabel = widget:recursiveGetChildById('collectRewardLabel')
        widget.battlePassImage = widget:recursiveGetChildById('rewardBoxImage')
        widget.battlePassBox.onClick = function()
            if not widget.battlePassEnabled then
                return
            end
            BattlePass.scrollBarWidget:setValue(getRewardPosition(widget.battlePassStep).scrollPosition)
            BattlePassRewards:onConfirmClaimReward(widget.battlePassStep, widget.battlePassRewardType)
        end
    end
    return widget
end

local function updateRewardViewport(scrollValue)
    if not BattlePass.progressPanelContent or not BattlePass.window or not BattlePass.window:isVisible() or
        BattlePass.currentMenuId ~= 'rewardsMenu' then
        return
    end

    BattlePass.activeRewardWidgets = BattlePass.activeRewardWidgets or {}
    BattlePass.rewardLookup = BattlePass.rewardLookup or {}
    local viewportWidth = BattlePass.progressScrollArea and BattlePass.progressScrollArea:getWidth() or 970
    local left = (tonumber(scrollValue) or 0) - REWARD_OVERSCAN
    local right = (tonumber(scrollValue) or 0) + viewportWidth + REWARD_OVERSCAN
    local desired = {}

    for step, data in ipairs(RewardPositions) do
        for rewardType, position in pairs(data.positions or {}) do
            if position.marginLeft + 120 >= left and position.marginLeft <= right then
                local key = rewardKey(step, rewardType)
                desired[key] = true
                local widget = BattlePass.activeRewardWidgets[key]
                if not widget then
                    widget = acquireRewardWidget()
                    BattlePass.activeRewardWidgets[key] = widget
                end
                widget:setId(rewardType .. 'RewardWidget' .. step)
                widget:setMarginLeft(position.marginLeft)
                widget:setMarginTop(position.marginTop)
                widget:setVisible(true)
                configureRewardWidget(widget, step, rewardType, BattlePass.rewardLookup[key])
            end
        end
    end

    local stale = {}
    for key in pairs(BattlePass.activeRewardWidgets) do
        if not desired[key] then
            stale[#stale + 1] = key
        end
    end
    for _, key in ipairs(stale) do
        local widget = BattlePass.activeRewardWidgets[key]
        BattlePass.activeRewardWidgets[key] = nil
        widget:setVisible(false)
        widget:setId(widget.battlePassPoolId)
        widget.battlePassEnabled = false
        BattlePass.rewardWidgetPool[#BattlePass.rewardWidgetPool + 1] = widget
    end
end

local function updateProgressViewport(scrollValue)
    updateMapViewport(scrollValue)
    updateRewardViewport(scrollValue)
end

local function rebuildRewardLookup()
    BattlePass.rewardLookup = {}
    for _, step in ipairs(BattlePass.rewardSteps or {}) do
        for _, reward in ipairs(step.rewards or {}) do
            local rewardType = reward.freeReward and 'free' or 'premium'
            BattlePass.rewardLookup[rewardKey(step.stepId, rewardType)] = reward
        end
    end
end

local function releaseProgressTextures()
    stopViewportLoad()
    for _, widget in ipairs(BattlePass.mapWidgets or {}) do
        if widget and not widget:isDestroyed() then
            widget:setImageSource('')
            widget:setVisible(false)
            widget.battlePassSource = nil
            widget.battlePassTargetIndex = nil
        end
    end
    for source in pairs(BattlePass.loadedMapSources or {}) do
        unloadTexture(source)
    end
    BattlePass.loadedMapSources = {}

    for _, widget in pairs(BattlePass.activeRewardWidgets or {}) do
        if widget and not widget:isDestroyed() then
            widget:setVisible(false)
            widget:setId(widget.battlePassPoolId)
            widget.battlePassEnabled = false
            BattlePass.rewardWidgetPool[#BattlePass.rewardWidgetPool + 1] = widget
        end
    end
    BattlePass.activeRewardWidgets = {}
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

local function stopPlayerAnimationEvents()
    if BattlePass.animationEvent then
        removeEvent(BattlePass.animationEvent)
        BattlePass.animationEvent = nil
    end
    if BattlePass.directionEvent then
        removeEvent(BattlePass.directionEvent)
        BattlePass.directionEvent = nil
    end
    BattlePass.isAnimatingWalk = false
    if BattlePass.outfitWidget and not BattlePass.outfitWidget:isDestroyed() then
        setOutfitStaticWalking(false)
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

local function cacheMissionWidget(widget, daily)
    if widget.battlePassFields then
        return widget.battlePassFields
    end

    widget.battlePassFields = {
        name = widget:recursiveGetChildById(daily and 'dailyMissionName' or 'missionName'),
        points = widget:recursiveGetChildById(daily and 'dailyMissionPoints' or 'missionPoints'),
        progress = widget:recursiveGetChildById(daily and 'dailyMissionProgress' or 'missionProgress'),
        progressText = widget:recursiveGetChildById(daily and 'dailyMissionProgressText' or 'missionProgressText'),
        information = widget:recursiveGetChildById(daily and 'dailyMissionInformation' or 'missionInformation'),
        blocked = widget:recursiveGetChildById(daily and 'dailyBlockedMissionIcon' or 'blockedMissionIcon'),
        icon = widget:recursiveGetChildById(daily and 'dailyMissionIconImage' or 'missionIconImage'),
        progressPanel = widget:recursiveGetChildById(daily and 'dailyProgressPanel' or 'progressPanel'),
        completed = widget:recursiveGetChildById(daily and 'dailyCompletedIcon' or 'completedIcon'),
        reroll = daily and widget:recursiveGetChildById('dailyRerollButton') or nil,
        freeIcon = daily and widget:recursiveGetChildById('dailyFreeIcon') or nil,
    }
    return widget.battlePassFields
end

local function prepareBattlePassWindowForSession()
    if not BattlePass.window then
        return false
    end
    if BattlePass.windowSessionPrepared then
        return true
    end

    local dailyMissionsPanel = BattlePass.window:recursiveGetChildById('dailyMissionsBg')
    for i = 1, 2 do
        local widget = dailyMissionsPanel:getChildByIndex(i) or g_ui.createWidget('DailyMissionWidget', dailyMissionsPanel)
        local fields = cacheMissionWidget(widget, true)
        local image = i == 1 and 'daily-free-icon' or 'daily-vip-icon'
        fields.icon:setImageSource('/images/game/battlepass/' .. image)
    end

    local missionsPanel = BattlePass.window:recursiveGetChildById('missionsBackground')
    for index = 1, 26 do
        local widget = missionsPanel:getChildByIndex(index) or g_ui.createWidget('MissionWidget', missionsPanel)
        cacheMissionWidget(widget, false)
    end

    BattlePass:loadPlayerPosition()
    BattlePass.windowSessionPrepared = true
    return true
end

function BattlePass.ensureWindow()
    if BattlePass.window then
        return true
    end

    BattlePass.window = g_ui.displayUI('battlepass')
    if not BattlePass.window then
        return false
    end

    BattlePass.hide()
    setupBattlePassTabs()

    BattlePass.missionPanel = BattlePass.window:recursiveGetChildById('missionPanel')
    BattlePass.progressPanel = BattlePass.window:recursiveGetChildById('progressPanel')
    BattlePass.shopPanel = BattlePass.window:recursiveGetChildById('battlePassShopPanel')
    BattlePass.outfitWidget = BattlePass.window:recursiveGetChildById('playerOutfit')
    BattlePass.scrollBarWidget = BattlePass.window:recursiveGetChildById('progressPanelScrollBar')
    BattlePass.bannerWidget = BattlePass.window:recursiveGetChildById('passBanner')
    BattlePass.progressPanelContent = BattlePass.window:recursiveGetChildById('progressPanelContent')
    BattlePass.progressScrollArea = BattlePass.progressPanel:recursiveGetChildById('rewardScrollArea')

    BattlePass.scrollBarWidget.canChangeValue = function()
        return not BattlePass.isAnimatingWalk
    end

    if BattlePass.progressScrollArea then
        BattlePass.progressScrollArea.onScrollChange = function()
            updateProgressViewport(BattlePass.scrollBarWidget:getValue())
        end
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
    if BattlePassShop then
        BattlePassShop.init(BattlePass.shopPanel)
    end
    return true
end

function BattlePass.init()
    registerBattlePassProtocol()

    connect(g_game, {
        onGameStart = online,
        onGameEnd = offline,
        onResourceBalance = onResourceBalance,
    })

    if g_game.isOnline() then
        stopStartupEvent()
        BattlePass.startupEvent = scheduleEvent(function()
            BattlePass.startupEvent = nil
            if g_game.isOnline() then
                online()
            end
        end, 50)
    end

    g_logger.info("Battle Pass loaded.")
end

function BattlePass.terminate()
    stopStartupEvent()
    stopUnlockTimer()
    stopPlayerAnimationEvents()
    releaseBannerTexture()
    releaseProgressTextures()

    if BattlePass.window then
        g_keyboard.unbindKeyPress('Tab', toggleNextWindow, BattlePass.window)
    end

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
    BattlePass.missionPanel = nil
    BattlePass.progressPanel = nil
    BattlePass.shopPanel = nil
    BattlePass.outfitWidget = nil
    BattlePass.scrollBarWidget = nil
    BattlePass.bannerWidget = nil
    BattlePass.progressPanelContent = nil
    BattlePass.progressScrollArea = nil
    BattlePass.mapWidgets = nil
    BattlePass.rewardWidgetPool = nil
    BattlePass.activeRewardWidgets = nil
    BattlePass.rewardLookup = nil
    BattlePass.windowSessionPrepared = false
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
    end
    BattlePass.missionsRequestPending = false
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
    BattlePass.shopRequestPending = false
    BattlePass.shopLoaded = true
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
            BattlePass.missionsRequestPending = false
            BattlePass.rewardsRequestPending = false
            BattlePass.shopRequestPending = false
            displayErrorBox(tr("Battle Pass"), msg:getString())
        else
            error("unknown response " .. tostring(response))
        end
    end)
    if not ok then
        BattlePass.missionsRequestPending = false
        BattlePass.rewardsRequestPending = false
        BattlePass.shopRequestPending = false
        drainUnreadMessage(msg)
        g_logger.error("[Battle Pass] Failed to parse server message: " .. tostring(err))
    end
    return true
end

online = function()
    registerBattlePassProtocol()

    -- Load battlepass config
    BattlePass:loadConfigJson()
    BattlePass.windowSessionPrepared = false
    BattlePass.missionsRequestPending = false
    BattlePass.rewardsRequestPending = false
    BattlePass.rewardsLoaded = false
    BattlePass.shopRequestPending = false
    BattlePass.shopLoaded = false
    BattlePass.rewardChunkBuffer = nil
    BattlePass.rewardChunkCount = 0
    BattlePass.rewardSteps = {}
    BattlePass.rewardLookup = {}

    if BattlePassRewards.claimRewardWindow then
        BattlePassRewards.claimRewardWindow:destroy()
        BattlePassRewards.claimRewardWindow = nil
    end

end

openBattlePass = function()
    if BattlePass.window and BattlePass.window:isVisible() then
        BattlePass.hide()
    elseif not g_game.isOnline() then
        return
    else
        if not BattlePass.ensureWindow() or not prepareBattlePassWindowForSession() then
            return
        end
        BattlePass.pendingOpen = true
        BattlePass.shouldShow = false
        BattlePass.show()
        BattlePass.loadMenu('challengesMenu')
        if not BattlePass.missionsRequestPending then
            BattlePass.missionsRequestPending = true
            if not sendToServer("getMissions") then
                BattlePass.missionsRequestPending = false
            end
        end
    end
end

function BattlePass.onBattlePassBarClick()
    openBattlePass()
end

offline = function()
    unregisterBattlePassProtocol()
    stopPlayerAnimationEvents()
    BattlePass.pendingOpen = false
    BattlePass.shouldShow = false
    BattlePass.missionsRequestPending = false
    BattlePass.rewardsRequestPending = false
    BattlePass.rewardsLoaded = false
    BattlePass.shopRequestPending = false
    BattlePass.shopLoaded = false
    BattlePass.rewardChunkBuffer = nil
    BattlePass.rewardChunkCount = 0
    BattlePass.rewardSteps = {}
    BattlePass.rewardLookup = {}

    BattlePass.hide()
    BattlePass.lastRewardStep = BattlePass.currentRewardStep
    BattlePass.lastCameraPosition = getRewardPosition(BattlePass.currentRewardStep).scrollPosition
    if BattlePass.outfitWidget then
        BattlePass.outfitWidget:setMarginLeft(165)
    end
    BattlePass:saveConfigJson()
    stopUnlockTimer()
    BattlePass.windowSessionPrepared = false

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
    if not BattlePass.ensureWindow() then
        return
    end
    BattlePass.window:show(true)
    BattlePass.window:raise()
    BattlePass.window:focus()

    g_keyboard.unbindKeyPress('Tab', toggleNextWindow, BattlePass.window)
    g_keyboard.bindKeyPress('Tab', toggleNextWindow, BattlePass.window)
    updateGoldBalance()
    if BattlePass.currentMenuId == 'challengesMenu' then
        scheduleBannerLoad()
    elseif BattlePass.currentMenuId == 'rewardsMenu' then
        updateProgressViewport(BattlePass.scrollBarWidget:getValue())
    end
end

function BattlePass.hide()
    if not BattlePass.window then
        return
    end

    BattlePass.window:hide()
    g_keyboard.unbindKeyPress('Tab', toggleNextWindow, BattlePass.window)
    stopUnlockTimer()
    releaseBannerTexture()
    releaseProgressTextures()
    BattlePass.isDragging = false
end

function BattlePass.loadMenu(menuId)
    BattlePass.currentMenuId = menuId
    if menuId ~= 'challengesMenu' then
        releaseBannerTexture()
    end
    if menuId ~= 'rewardsMenu' then
        releaseProgressTextures()
    end

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
        scheduleBannerLoad()
    elseif menuId == 'rewardsMenu' then
        BattlePass.shopPanel:hide()
        BattlePass.scrollBarWidget:setValue(BattlePass.lastCameraPosition)
        BattlePass.outfitWidget:setDirection(BattlePass.currentRewardStep == 0 and East or North)
        BattlePass.missionPanel:hide()
        BattlePass.progressPanel:show(true)
        BattlePass.window:setHeight(515)
        updateProgressViewport(BattlePass.scrollBarWidget:getValue())
        BattlePass:updatePlayerPosition()
        if not BattlePass.rewardsLoaded and not BattlePass.rewardsRequestPending then
            BattlePass.rewardsRequestPending = true
            if not sendToServer("getRewards") then
                BattlePass.rewardsRequestPending = false
            end
        end
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
    if BattlePass.rewardsLoaded then
        BattlePass:configureRewardPanel()
    end
end

function BattlePass.onBattlePassRewards(rewardSteps)
    if type(rewardSteps) == "table" and rewardSteps.chunk then
        local total = tonumber(rewardSteps.total) or 0
        local first = tonumber(rewardSteps.first) or 1
        local steps = rewardSteps.steps or {}

        if first <= 1 or not BattlePass.rewardChunkBuffer or BattlePass.rewardChunkTotal ~= total then
            BattlePass.rewardChunkBuffer = {}
            BattlePass.rewardChunkCount = 0
            BattlePass.rewardChunkTotal = total
        end

        for _, step in ipairs(steps) do
            local stepId = tonumber(step.stepId)
            if stepId then
                if not BattlePass.rewardChunkBuffer[stepId] then
                    BattlePass.rewardChunkCount = BattlePass.rewardChunkCount + 1
                end
                BattlePass.rewardChunkBuffer[stepId] = step
            end
        end

        if total > 0 and BattlePass.rewardChunkCount < total then
            return
        end

        rewardSteps = BattlePass.rewardChunkBuffer
        BattlePass.rewardChunkBuffer = nil
        BattlePass.rewardChunkCount = 0
        BattlePass.rewardChunkTotal = nil
    end

    BattlePass.rewardSteps = rewardSteps or {}
    BattlePass.rewardsRequestPending = false
    BattlePass.rewardsLoaded = true
    BattlePass:configureRewardPanel()
end

function BattlePass.calculateWeekNumber()
    if (tonumber(BattlePass.beginTime) or 0) <= 0 then
        return 1
    end

    local diffSeconds = os.difftime(os.time(), BattlePass.beginTime)
    if diffSeconds <= 0 then
        return 1
    end

    local weekNumber = math.ceil((diffSeconds + 1) / 604800)
    local seasonWeeks = math.max(1, math.ceil((BattlePass.endTime - BattlePass.beginTime) / 604800))
    return math.max(1, math.min(weekNumber, seasonWeeks))
end

function BattlePass.getNextResetWeek(currentIndex)
    if (tonumber(BattlePass.beginTime) or 0) <= 0 then
        return os.time()
    end

    return BattlePass.beginTime + (7 * currentIndex * 86400)
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
        local fields = cacheMissionWidget(widget, true)

        fields.name:setText(v.missionName or "")
        fields.points:setText(v.rewardPoints or 0)
        fields.progress:setPercent(safePercent(currentProgress, maxProgress))
        fields.progressText:setText(string.format("%s/%s", aggresiveNumberToStr(currentProgress), aggresiveNumberToStr(maxProgress)))
        fields.information:setTooltip(v.missionDescription or "")
        fields.blocked:setVisible(false)
        fields.freeIcon:setVisible(false)
        fields.reroll:setVisible(not completed)
        fields.reroll.onClick = function() if not BattlePass:running() then return true end BattlePass:rerollDailyMission(v) end

        local icon = (k == 1 and "daily-free-icon" or "daily-vip-icon")
        if completed then
            icon = "daily-icon-complete"
        end

        fields.icon:setImageSource("/images/game/battlepass/" .. icon)
        fields.progressPanel:setVisible(not completed)
        fields.completed:setVisible(completed)

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
        local fields = cacheMissionWidget(widget, false)

        fields.name:setText(data.missionName or "")
        fields.points:setText(data.rewardPoints or 0)
        fields.progress:setPercent(safePercent(currentProgress, maxProgress))
        fields.progressText:setText(string.format("%s/%s", aggresiveNumberToStr(currentProgress), aggresiveNumberToStr(maxProgress)))
        fields.information:setTooltip(data.missionDescription or "")
        fields.blocked:setVisible(false)

        local completed = maxProgress > 0 and currentProgress >= maxProgress
        local missionIconBase = MissionRankIcons[data.rewardPoints] or "mission-locked-icon"
        local missionIcon = completed and MissionRankIcons[data.rewardPoints] and missionIconBase .. "-complete" or missionIconBase
        fields.icon:setImageSource("/images/game/battlepass/" .. missionIcon)
        fields.progressPanel:setVisible(not completed)
        fields.completed:setVisible(completed)
        if not BattlePass:running() then
            widget:setEnabled(false)
            widget:setVisible(false)
        end
    end
end

function BattlePass:configureRewardPanel()
    rebuildRewardLookup()
    if BattlePass.currentMenuId == 'rewardsMenu' and BattlePass.window and BattlePass.window:isVisible() then
        updateRewardViewport(BattlePass.scrollBarWidget:getValue())
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
    stopPlayerAnimationEvents()
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

        BattlePass.directionEvent = scheduleEvent(function()
            BattlePass.directionEvent = nil
            if BattlePass.outfitWidget and not BattlePass.outfitWidget:isDestroyed() then
                BattlePass.outfitWidget:setDirection(North)
            end
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
                BattlePass.animationEvent = scheduleEvent(function()
                    BattlePass.animationEvent = nil
                    animateStep()
                end, 25)
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
