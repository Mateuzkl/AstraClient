-- g_things.getMonsterList() rebuilds and pushes the full ~2-3k monster map on
-- every call; cache it keyed by client version (assets reload on version switch)
local cachedMonsterList, cachedForVersion
local function getMonsterList()
    local version = g_game.getClientVersion()
    if not cachedMonsterList or cachedForVersion ~= version then
        local list = g_things.getMonsterList()
        -- never pin an empty list (failed staticdata load): retry next call
        if next(list) == nil then
            return list
        end
        cachedMonsterList = list
        cachedForVersion = version
    end
    return cachedMonsterList
end

---------------------------
-- Lua code author: R1ck --
-- Company: VICTOR HUGO PERENHA - JOGOS ON LINE --
---------------------------

BosstiarySlot = {}
BosstiarySlot.__index = BosstiarySlot

slotPanel = nil
bossPointsText = nil

local bossBalance = 0
local requiredPoints = 0
local lootBonus = 0
local nextLootBonus = 0

local filterText = {}
local slotData = {}
local availableBosses = {}

function BosstiarySlot.onSideButtonRedirect()
	Cyclopedia.open()
	onOptionChange(cyclopediaOptionsPanel:recursiveGetChildById('8'))
end

function BosstiarySlot.requestData()
	filterText[1] = ''
	filterText[2] = ''

    g_game.requestResource(ResourceBank)
    g_game.requestResource(ResourceInventary)
	g_game.openBosstiarySlots()
end

function BosstiarySlot.onBosstiarySlotsData(pointsBalance, pointsNext, bonusLoot, bonusNext, slots, unlockedCreatures)
	bossBalance = pointsBalance
	requiredPoints = pointsNext
	lootBonus = bonusLoot
	nextLootBonus = bonusNext

	slotData = slots
	availableBosses = unlockedCreatures
	slotPanel = VisibleCyclopediaPanel

	BosstiarySlot.configureWindow()
end

function BosstiarySlot.configureWindow()
	if not slotPanel or not slotPanel.informationProgress then
		return
	end

    slotPanel.informationProgress.bossPointsProgress.bossPointsText:setText(tr('%s/%s', bossBalance, requiredPoints))
    slotPanel.informationProgress.bossPointsProgress:setPercent(bossBalance * 100 / requiredPoints)
    slotPanel.informationProgress.inforText:setText("Equipment Loot Bonus: " .. lootBonus .. "% Next: " .. nextLootBonus .. "%")

    if lootBonus > 100 and nextLootBonus > 100 then
        slotPanel.informationProgress.bossPointsBg:setWidth(262)
        slotPanel.informationProgress.bossPointsProgress:setWidth(260)
    else
        slotPanel.informationProgress.bossPointsBg:setWidth(278)
        slotPanel.informationProgress.bossPointsProgress:setWidth(276)
    end

    BosstiarySlot.showFirstSlot(slotData[1], filterText[1])
    BosstiarySlot.showSecondSlot(slotData[2], filterText[2])
    BosstiarySlot.showBoostedSlot(slotData[3])
end

function BosstiarySlot.showFirstSlot(data, sortText)
	slotPanel.slot1.selectedBossPanel:setVisible(false)
	slotPanel.slot1.selectBoss:setVisible(false)
	slotPanel.slot1.slot1Text:setVisible(false)

	local state = data.state
	local monsterList = getMonsterList()
	local firstPanel = slotPanel.slot1.selectedBossPanel.panel1.bossSlotMonsterPanel

	if state == 1 then
		if data.raceID == 0 then
			slotPanel.slot1:setText("Slot 1: Select Boss")
			slotPanel.slot1.selectedBossPanel:setVisible(true)
			slotPanel.slot1.selectedBossPanel:recursiveGetChildById("selectBossButton").onClick = function() BosstiarySlot.onSelectBoss(firstPanel) end
			firstPanel:destroyChildren()

			for k, v in pairs(availableBosses) do
				local monster = monsterList[k]
				if not monster then
					goto continue
				end
				local name = string.capitalize(monster[1])
				if sortText and #sortText > 0 then
					if not matchText(sortText, name) then
						goto continue
					end
				end

				local category = v + 1
				local widget = g_ui.createWidget('BossBox', firstPanel)
				widget:setText(short_text(name, 8))
				widget.bossOutfit:setOutfit({type = monster[2], auxType = monster[3], head = monster[4], body = monster[5], legs = monster[6], feet = monster[7], addons = monster[8]})
				widget.bossOutfit:setRaceID(k)
				widget.bossOutfit:setActionId(1)
				widget.bossIcon:setImageSource('/game_cyclopedia/images/icons/icon-bosstiary-' .. category)
				widget.bossIcon:setTooltip(tr(toolMessages[category], BosstiaryReward[category].prowess, BosstiaryReward[category].expertise, BosstiaryReward[category].mastery))

				slotPanel.slot1.selectedBossPanel.searchText:setActionId(1)
				:: continue ::
			end
		else
			local monster = monsterList[data.raceID]
			if not monster then
				-- raceID missing from client staticdata: fall back to locked-style text
				slotPanel.slot1.slot1Text:setVisible(true)
				return
			end
			slotPanel.slot1.selectBoss:setVisible(true)

			local name = string.capitalize(monster[1])
			local baseKill = baseKillData[data.category + 1]
			local baseReward = baseRewardData[data.category + 1]

			slotPanel.slot1:setText(tr("Slot 1: %s", short_text(name, 20)))
			slotPanel.slot1.selectBoss.selectedBoss.outfit:setOutfit({type = monster[2], auxType = monster[3], head = monster[4], body = monster[5], legs = monster[6], feet = monster[7], addons = monster[8]})
			slotPanel.slot1.selectBoss.progressSecond.second.counter:setText(data.kills)

			slotPanel.slot1.selectBoss.progressFirst.first:setTooltip(tr("%s / %s", data.kills, baseKill.firstUnlock))
			slotPanel.slot1.selectBoss.progressSecond.second:setTooltip(tr("%s / %s", data.kills, baseKill.secondUnlock))
			slotPanel.slot1.selectBoss.progressThird.third:setTooltip(tr("%s / %s", data.kills, baseKill.thirdUnlock))

			-- Reset percent bar
			slotPanel.slot1.selectBoss.progressFirst.first:setImageSource("/game_cyclopedia/images/ui/mosnter-bar")
			slotPanel.slot1.selectBoss.progressSecond.second:setImageSource("/game_cyclopedia/images/ui/mosnter-bar")
			slotPanel.slot1.selectBoss.progressThird.third:setImageSource("/game_cyclopedia/images/ui/mosnter-bar")
			slotPanel.slot1.selectBoss.progressFirst.first:setPercent(0)
			slotPanel.slot1.selectBoss.progressSecond.second:setPercent(0)
			slotPanel.slot1.selectBoss.progressThird.third:setPercent(0)
			slotPanel.slot1.selectBoss.starFisrt:setImageSource("/game_cyclopedia/images/icons/star/inative1")
			slotPanel.slot1.selectBoss.starSecond:setImageSource("/game_cyclopedia/images/icons/star/inative2")
			slotPanel.slot1.selectBoss.starThird:setImageSource("/game_cyclopedia/images/icons/star/inative3")

			local firstPercent = data.kills * 100 / baseKill.firstUnlock
			slotPanel.slot1.selectBoss.progressFirst.first:setPercent(firstPercent)

			if firstPercent >= 100 then
				slotPanel.slot1.selectBoss.starFisrt:setImageSource("/game_cyclopedia/images/icons/star/enable1")

				local secondPercent = data.kills * 100 / baseKill.secondUnlock
				slotPanel.slot1.selectBoss.progressSecond.second:setPercent(secondPercent)

				if secondPercent >= 100 then
					slotPanel.slot1.selectBoss.starSecond:setImageSource("/game_cyclopedia/images/icons/star/enable2")

					local thirdPercent = data.kills * 100 / baseKill.thirdUnlock
					slotPanel.slot1.selectBoss.progressThird.third:setPercent(thirdPercent)
					if thirdPercent >= 100 then
						slotPanel.slot1.selectBoss.progressFirst.first:setImageSource('/game_cyclopedia/images/ui/monster-bar-green')
						slotPanel.slot1.selectBoss.progressSecond.second:setImageSource('/game_cyclopedia/images/ui/monster-bar-green')
						slotPanel.slot1.selectBoss.progressThird.third:setImageSource('/game_cyclopedia/images/ui/monster-bar-green')
						slotPanel.slot1.selectBoss.starThird:setImageSource("/game_cyclopedia/images/icons/star/enable3")
					end
				end
			end

			local removeGold = data.removeGold
			if data.isBoosted == 1 then
				removeGold = 0
			end

			local category = data.category + 1
			local bonusText = slotPanel.slot1.selectBoss.selectedBonusText
			bonusText:setText("Equipment loot bonus: " .. tostring(data.bonusLoot) .. "%")
			slotPanel.slot1.selectBoss.gold.text:setText(comma_value(removeGold))
			slotPanel.slot1.selectBoss.iconBosstiary:setImageSource('/game_cyclopedia/images/icons/icon-bosstiary-' .. category)
			slotPanel.slot1.selectBoss.iconBosstiary:setTooltip(tr(toolMessages[category], BosstiaryReward[category].prowess, BosstiaryReward[category].expertise, BosstiaryReward[category].mastery))
			slotPanel.slot1.selectBoss.removeButton:setTooltip(tr("It will cost you %s gold to remove the currently selected boss from this slot.", comma_value(removeGold)))
			slotPanel.slot1.selectBoss.removeButton:setActionId(1)

			local player = g_game.getLocalPlayer()
			local bankMoney = player:getResourceValue(ResourceBank)
			local characterMoney = player:getResourceValue(ResourceInventary)

			if bankMoney + characterMoney < removeGold then
				slotPanel.slot1.selectBoss.removeButton:disable()
				slotPanel.slot1.selectBoss.gold.text:setColor("#d33c3c")
			else
				slotPanel.slot1.selectBoss.removeButton:enable()
				slotPanel.slot1.selectBoss.gold.text:setColor("#c0c0c0")
			end
		end
	else
		-- locked
		slotPanel.slot1.slot1Text:setVisible(true)
	end
end

function BosstiarySlot.showSecondSlot(data, sortText)
	slotPanel.slot2.selectedBossPanel:setVisible(false)
	slotPanel.slot2.selectBoss:setVisible(false)
	slotPanel.slot2.slot1Text:setVisible(false)

	local state = data.state
	local monsterList = getMonsterList()
	local secondPanel = slotPanel.slot2.selectedBossPanel.panel1.bossSlotMonsterPanel

	if state == 1 then
		if data.raceID == 0 then
			slotPanel.slot2:setText("Slot 2: Select Boss")
			slotPanel.slot2.selectedBossPanel:setVisible(true)
			slotPanel.slot2.selectedBossPanel:recursiveGetChildById("selectBossButton").onClick = function() BosstiarySlot.onSelectBoss(secondPanel) end
			secondPanel:destroyChildren()

			for k, v in pairs(availableBosses) do
				local monster = monsterList[k]
				if not monster then
					goto continue
				end

				local name = string.capitalize(monster[1])
				if sortText and #sortText > 0 then
					if not matchText(sortText, name) then
						goto continue
					end
				end

				local category = v + 1
				local widget = g_ui.createWidget('BossBox', secondPanel)
				widget:setText(short_text(name, 8))
				widget.bossOutfit:setOutfit({type = monster[2], auxType = monster[3], head = monster[4], body = monster[5], legs = monster[6], feet = monster[7], addons = monster[8]})
				widget.bossOutfit:setRaceID(k)
				widget.bossOutfit:setActionId(2)
				widget.bossIcon:setImageSource('/game_cyclopedia/images/icons/icon-bosstiary-' .. category)
				widget.bossIcon:setTooltip(tr(toolMessages[category], BosstiaryReward[category].prowess, BosstiaryReward[category].expertise, BosstiaryReward[category].mastery))
				slotPanel.slot2.selectedBossPanel.searchText:setActionId(2)

				:: continue ::
			end
		else
			local monster = monsterList[data.raceID]
			if not monster then
				-- raceID missing from client staticdata: fall back to locked-style text
				slotPanel.slot2.slot1Text:setVisible(true)
				return
			end
			slotPanel.slot2.selectBoss:setVisible(true)

			local name = string.capitalize(monster[1])
			local baseKill = baseKillData[data.category + 1]
			local baseReward = baseRewardData[data.category + 1]

			slotPanel.slot2:setText(tr("Slot 2: %s", short_text(name, 20)))
			slotPanel.slot2.selectBoss.selectedBoss.outfit:setOutfit({type = monster[2], auxType = monster[3], head = monster[4], body = monster[5], legs = monster[6], feet = monster[7], addons = monster[8]})
			slotPanel.slot2.selectBoss.progressSecond.second.counter:setText(data.kills)

			slotPanel.slot2.selectBoss.progressFirst.first:setTooltip(tr("%s / %s", data.kills, baseKill.firstUnlock))
			slotPanel.slot2.selectBoss.progressSecond.second:setTooltip(tr("%s / %s", data.kills, baseKill.secondUnlock))
			slotPanel.slot2.selectBoss.progressThird.third:setTooltip(tr("%s / %s", data.kills, baseKill.thirdUnlock))

			-- Reset percent bar
			slotPanel.slot2.selectBoss.progressFirst.first:setImageSource("/game_cyclopedia/images/ui/mosnter-bar")
			slotPanel.slot2.selectBoss.progressSecond.second:setImageSource("/game_cyclopedia/images/ui/mosnter-bar")
			slotPanel.slot2.selectBoss.progressThird.third:setImageSource("/game_cyclopedia/images/ui/mosnter-bar")
			slotPanel.slot2.selectBoss.progressFirst.first:setPercent(0)
			slotPanel.slot2.selectBoss.progressSecond.second:setPercent(0)
			slotPanel.slot2.selectBoss.progressThird.third:setPercent(0)
			slotPanel.slot2.selectBoss.starFisrt:setImageSource("/game_cyclopedia/images/icons/star/inative1")
			slotPanel.slot2.selectBoss.starSecond:setImageSource("/game_cyclopedia/images/icons/star/inative2")
			slotPanel.slot2.selectBoss.starThird:setImageSource("/game_cyclopedia/images/icons/star/inative3")

			local firstPercent = data.kills * 100 / baseKill.firstUnlock
			slotPanel.slot2.selectBoss.progressFirst.first:setPercent(firstPercent)

			if firstPercent >= 100 then
				slotPanel.slot2.selectBoss.starFisrt:setImageSource("/game_cyclopedia/images/icons/star/enable1")

				local secondPercent = data.kills * 100 / baseKill.secondUnlock
				slotPanel.slot2.selectBoss.progressSecond.second:setPercent(secondPercent)

				if secondPercent >= 100 then
					slotPanel.slot2.selectBoss.starSecond:setImageSource("/game_cyclopedia/images/icons/star/enable2")

					local thirdPercent = data.kills * 100 / baseKill.thirdUnlock
					slotPanel.slot2.selectBoss.progressThird.third:setPercent(thirdPercent)
					if thirdPercent >= 100 then
						slotPanel.slot2.selectBoss.progressFirst.first:setImageSource('/game_cyclopedia/images/ui/monster-bar-green')
						slotPanel.slot2.selectBoss.progressSecond.second:setImageSource('/game_cyclopedia/images/ui/monster-bar-green')
						slotPanel.slot2.selectBoss.progressThird.third:setImageSource('/game_cyclopedia/images/ui/monster-bar-green')
						slotPanel.slot2.selectBoss.starThird:setImageSource("/game_cyclopedia/images/icons/star/enable3")
					end
				end
			end

			local removeGold = data.removeGold
			if data.isBoosted == 1 then
				removeGold = 0
			end

			local category = data.category + 1
			local bonusText = slotPanel.slot2.selectBoss.selectedBonusText
			bonusText:setText("Equipment loot bonus: " .. tostring(data.bonusLoot) .. "%")
			slotPanel.slot2.selectBoss.gold.text:setText(comma_value(removeGold))
			slotPanel.slot2.selectBoss.iconBosstiary:setImageSource('/game_cyclopedia/images/icons/icon-bosstiary-' .. category)
			slotPanel.slot2.selectBoss.iconBosstiary:setTooltip(tr(toolMessages[category], BosstiaryReward[category].prowess, BosstiaryReward[category].expertise, BosstiaryReward[category].mastery))
			slotPanel.slot2.selectBoss.removeButton:setTooltip(tr("It will cost you %s gold to remove the currently selected boss from this slot.", comma_value(removeGold)))
			slotPanel.slot2.selectBoss.removeButton:setActionId(2)

			local player = g_game.getLocalPlayer()
			local bankMoney = player:getResourceValue(ResourceBank)
			local characterMoney = player:getResourceValue(ResourceInventary)

			if bankMoney + characterMoney < removeGold then
				slotPanel.slot2.selectBoss.removeButton:disable()
				slotPanel.slot2.selectBoss.gold:setColor("#d33c3c")
			else
				slotPanel.slot2.selectBoss.removeButton:enable()
				slotPanel.slot2.selectBoss.gold:setColor("#c0c0c0")
			end
		end
	else
		-- locked
		slotPanel.slot2.slot1Text:setVisible(true)
	end
end

local function updateMonsterName(monsterName)
	local maxCharacters = 14
	local finalName = "Boosted Boss: "

	if string.len(monsterName) > maxCharacters then
	  finalName = finalName .. string.sub(monsterName, 1, maxCharacters) .. "..."
	else
	  finalName = finalName .. monsterName
	end

	slotPanel.slot3:setText(string.capitalize(finalName))
end

function BosstiarySlot.showBoostedSlot(data)
	-- boosted raceID may be absent from client staticdata (custom boss/asset gap)
	-- or 0; keep the slot in its default OTUI state instead of erroring out
	local monster = getMonsterList()[data.raceID]
	if not monster then
		return
	end
	local baseKill = baseKillData[data.category + 1]
	local baseReward = baseRewardData[data.category + 1]

	updateMonsterName(monster[1])
	slotPanel.slot3.monster.outfit:setOutfit({type = monster[2], auxType = monster[3], head = monster[4], body = monster[5], legs = monster[6], feet = monster[7], addons = monster[8]})
    slotPanel.slot3.monster.outfit:setAnimate(true)

	slotPanel.slot3.first:setTooltip(data.kills .. " / " .. baseKill.firstUnlock)
	slotPanel.slot3.second:setTooltip(data.kills .. " / " .. baseKill.secondUnlock)
	slotPanel.slot3.third:setTooltip(data.kills .. " / " .. baseKill.thirdUnlock)

	local percent = data.kills * 100 / baseKill.firstUnlock
	slotPanel.slot3.first:setPercent(percent)
	if percent >= 100 then
		slotPanel.slot3.starFisrt:setImageSource("/game_cyclopedia/images/icons/star/enable1")
		percent = data.kills * 100 / baseKill.secondUnlock
		slotPanel.slot3.second:setPercent(percent)

		if percent >= 100 then
			slotPanel.slot3.starSecond:setImageSource("/game_cyclopedia/images/icons/star/enable2")
			percent = data.kills * 100 / baseKill.thirdUnlock
			slotPanel.slot3.third:setPercent(percent)

			if percent >= 100 then
				slotPanel.slot3.first:setImageSource('/game_cyclopedia/images/ui/monster-bar-green')
				slotPanel.slot3.second:setImageSource('/game_cyclopedia/images/ui/monster-bar-green')
				slotPanel.slot3.third:setImageSource('/game_cyclopedia/images/ui/monster-bar-green')
				slotPanel.slot3.starThird:setImageSource("/game_cyclopedia/images/icons/star/enable3")
			end
		end
	end

	local category = data.category + 1
	slotPanel.slot3.second.counter:setText(data.kills)
	slotPanel.slot3.iconBosstiary:setImageSource('/game_cyclopedia/images/icons/icon-bosstiary-' .. data.category + 1)
	slotPanel.slotCenterText:setText("Equipment loot bonus: " .. data.bonusLoot .. "%\n            Kill bonus: " .. data.bonusKill .. "x")
	slotPanel.slot3.iconBosstiary:setTooltip(tr(toolMessages[category], BosstiaryReward[category].prowess, BosstiaryReward[category].expertise, BosstiaryReward[category].mastery))
end

function BosstiarySlot.clearSearch(widget, button)
	local textBox = widget:backwardsGetWidgetById('searchText')
	if #textBox:getText() == 0 then
		return
	end

	textBox:clearText()
	BosstiarySlot.onSearchChange(textBox)
end

function BosstiarySlot.onSearchChange(widget)
	filterText[widget:getActionId()] = widget:getText()
	if widget:getActionId() == 1 then
		BosstiarySlot.showFirstSlot(slotData[1], filterText[widget:getActionId()])
	else
		BosstiarySlot.showSecondSlot(slotData[2], filterText[widget:getActionId()])
	end
end

function BosstiarySlot.onSelectBoss(list)
	if list:getChildCount() == 0 then
		return
	end

	local focused = list:getFocusedChild()
	if not focused then
		return
	end

	-- Read the boss data BEFORE touching the search box. Clearing a non-empty
	-- search fires onTextChange -> onSearchChange -> showSlot -> destroyChildren(),
	-- which destroys `focused` and releases its Lua raceId. Reading raceID/actionId
	-- afterwards yielded nil and the slot action was sent with no boss, so selecting
	-- a searched boss silently failed (it only worked with an empty search box).
	local creature = focused:recursiveGetChildById('bossOutfit')
	local actionId = creature:getActionId()
	local raceID = creature:getRaceID()

	local textBox = focused:backwardsGetWidgetById('searchText')
	textBox:setText('', true) -- clear without re-firing onSearchChange/rebuild

	filterText[actionId] = ''
	g_game.sendBosstiarySlotAction(actionId, raceID)
end

function BosstiarySlot.onRemoveCreature(widget)
   g_game.sendBosstiarySlotAction(widget:getActionId(), 0)
end
