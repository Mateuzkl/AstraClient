DailyReward = {}
DailyReward.__index = DailyReward

DailyReward.freeRewards = {}
DailyReward.premiumRewards = {}
DailyReward.descriptions = {}
DailyReward.configureEvent = nil
DailyReward.configureGeneration = 0

local rewardFreeBase = "Rewards for Free Account: %s"
local rewardPremiumBase = "Rewards for Premium Account: %s"
local potionList = "\nPick %d item from the list. Among \nother items it contains: %s"
local preyText = "<li>%dx Prey Wildcard</li>"
local boostText = "<li>%d minutes 50%% XP Boost</li>"
local makeDailyRewardText

local function onRewardHover(selfWidget, hovered)
  dailyRewardWindow.Description.tooltipTodo:setText("")
  dailyRewardWindow.Description.freeDesc.freeDescLabel:setText("")
  dailyRewardWindow.Description.freeDesc.freeDescLabel:setFormatedText("")
  dailyRewardWindow.Description.premDesc.premiumDescLabel:setText("")
  dailyRewardWindow.Description.premDesc.premiumDescLabel:setFormatedText("")
  if hovered then
    dailyRewardWindow.Description.freeDesc.freeDescLabel:setFormatedText(string.format(rewardFreeBase, makeDailyRewardText(selfWidget.freeRewards)))
    dailyRewardWindow.Description.premDesc.premiumDescLabel:setFormatedText(string.format(rewardPremiumBase, makeDailyRewardText(selfWidget.premiumRewards)))
  end
end

local function onBonusHover(selfWidget, hovered)
  dailyRewardWindow.Description.tooltipTodo:setText("")
  dailyRewardWindow.Description.freeDesc.freeDescLabel:setText("")
  dailyRewardWindow.Description.premDesc.premiumDescLabel:setText("")
  dailyRewardWindow.Description.premDesc.premiumDescLabel:setFormatedText("")
  if hovered then
    dailyRewardWindow.Description.tooltipTodo:setText(selfWidget.textTooltip)
  end
end

makeDailyRewardText = function(dailyReward)
  local text = ''
  if dailyReward.type == 1 then
    local ss = ''
    for i, items in pairs(dailyReward.items) do
      if ss == '' then
        ss = '\n' .. items.name
      elseif i < 3 then
        ss = ss .. ', ' .. (i % 2 == 0 and '\n' or '') .. items.name
      else
        ss = ss .. '...'
        break
      end
    end

    return string.format(potionList, dailyReward.amount, ss)
  else
    if dailyReward.preyCount > 0 then
      return string.format(preyText, dailyReward.preyCount)
    elseif dailyReward.xpboost > 0 then
      return string.format(boostText, dailyReward.xpboost)
    end
  end
  return text
end

function DailyReward:onDailyReward(freeRewards, premiumRewards, descriptions )
    DailyReward.freeRewards = freeRewards
    DailyReward.premiumRewards = premiumRewards
    DailyReward.descriptions = descriptions

    DailyReward:configureRewardDescriptions()
end

function DailyReward:cancelConfiguration()
    DailyReward.configureGeneration = DailyReward.configureGeneration + 1
    if DailyReward.configureEvent then
        removeEvent(DailyReward.configureEvent)
        DailyReward.configureEvent = nil
    end
end

function DailyReward:configureRewardDescriptions()
    DailyReward:cancelConfiguration()
    if not dailyRewardWindow or dailyRewardWindow:isDestroyed() then
        return
    end

    local generation = DailyReward.configureGeneration
    local rewardIndex = 0
    local bonusIndex = 0
    local rewardRoot = dailyRewardWindow.miniWindowDailyReward.dailyReward
    local bonusRoot = dailyRewardWindow.miniWindowBonuses.preyBonus
    local configureBonus

    local function scheduleStep(callback)
        DailyReward.configureEvent = scheduleEvent(function()
            DailyReward.configureEvent = nil
            if generation ~= DailyReward.configureGeneration or not dailyRewardWindow or dailyRewardWindow:isDestroyed() then
                return
            end
            callback()
        end, 1)
    end

    local function configureReward()
        local i = rewardIndex
        local widget = rewardRoot:recursiveGetChildById("dailyButton_".. i)
        if widget then
            widget.freeRewards = DailyReward.freeRewards[i + 1]
            widget.premiumRewards = DailyReward.premiumRewards[i + 1]

            if widget.freeRewards.type == 1 then
                widget:setIcon("/images/dailyreward/icon-reward-pickitems")
            else
                if widget.freeRewards.preyCount > 0 then
                    widget:setIcon("/images/dailyreward/icon-reward-fixeditems")
                elseif widget.freeRewards.xpboost > 0 then
                    widget:setIcon("/images/dailyreward/icon-reward-xpboost")
                end
            end


            widget.onHoverChange = onRewardHover
        end

        rewardIndex = rewardIndex + 1
        scheduleStep(rewardIndex <= 6 and configureReward or configureBonus)
    end

    configureBonus = function()
        local i = bonusIndex
        local widget = bonusRoot:recursiveGetChildById("bonusStreak_".. i)
        if widget then
            widget.textTooltip = DailyReward.descriptions[i + 1]
            widget.onHoverChange = onBonusHover
        end

        bonusIndex = bonusIndex + 1
        if bonusIndex <= 5 then
            scheduleStep(configureBonus)
        else
            DailyReward.configureEvent = nil
        end
    end

    scheduleStep(configureReward)
end

function DailyReward:onOpenRewardWall(fromShrine, nextRewardTime, currentIndex, message, jokerToken, serverSave, dayStreakLevel)
end
