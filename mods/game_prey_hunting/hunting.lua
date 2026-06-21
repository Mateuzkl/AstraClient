preyTracker = nil
huntingWindow = nil
huntingWindowButton = nil
huuntingMessageWindow = nil

-- Wildcard selection
oldSelectionBGColor = {}
oldSelectionTextColor = {}
wildcardSelectedMonster = {}

rewardGrade = {}
huntingSlots = {}
nextRerollTime = {}
selectedMonster = {}
activeMonsterList = {}
huntingRewardData = {}
huntingMonsterData = {}
currentMonsterList = {}
inactiveSelections = {}
currentWildcardList = {}

local bankBalance = 0
local huntingToken = 0
local invetoryMoney = 0
local wildcardBalance = 0
local goldUpdatePrice = 0
local goldRemovePrice = 0
local wildcardSelectPrice = 0
local rerollWildcardPrice = 0

local updateRerollEvent = nil
local lastSelectedCreature = {}

local PREY_HUNTING_ACTION_LISTREROLL = 0
local PREY_HUNTING_ACTION_BONUSREROLL = 1
local PREY_HUNTING_ACTION_SELECT_WILDCARD = 2
local PREY_HUNTING_ACTION_SELECT = 3
local PREY_HUNTING_ACTION_REMOVE = 4
local PREY_HUNTING_ACTION_COLLECT = 5

local PREY_HUNTING_STATE_LOCKED = 0
local PREY_HUNTING_STATE_EXHAUSTED = 1
local PREY_HUNTING_STATE_SELECT = 2
local PREY_HUNTING_STATE_WILDCARD = 3
local PREY_HUNTING_STATE_ACTIVE = 4
local PREY_HUNTING_STATE_REDEEM = 5
local PREY_HUNTING_BASE_OPCODE = 0xBA
local PREY_HUNTING_DATA_OPCODE = 0xBB

local DESC_TYPE = {
	TYPE_MONSTER_LIST = 1,
	TYPE_MONSTER_SELECTED = 2,
	TYPE_CANCEL_MONSTER = 5,
	TYPE_REWARD_INCREASE = 6,
	TYPE_SELECT_WILDCARD = 7,
	TYPE_LIST_REROLL = 8,
	TYPE_CONFIRM_SELECTION = 9,
	TYPE_WILDCARD_LIST = 10,
	TYPE_CLAIM_REWARD = 11,
	TYPE_SLOT_EXHAUSTED = 12,
	TYPE_SLOT_LOCKED = 13,
	TYPE_SLOT_REROLL = 14
}

-- 0xBA/0xBB are parsed exactly once in ProtocolGame C++. Registering Lua
-- handlers here would consume the packet before that parser and create a
-- second source of truth for the wire format.

function init()
  huntingWindow = g_ui.displayUI('hunting')
  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
	onPreyHuntingPrice = onPreyHuntingPrice,
	onUpdateRerrolTime = onUpdateRerrolTime,
	onResourceBalance = onPreyResourceBalance,
	onHuntingLockedState = onHuntingLockedState,
	onHuntingSelectState = onHuntingSelectState,
	onHuntingActiveState = onHuntingActiveState,
	onPreyHuntingBaseData = onPreyHuntingBaseData,
	onHuntingWildcardState = onHuntingWildcardState,
	onHuntingExhaustedState = onHuntingExhaustedState
  })

  preyTracker = modules.game_prey.preyTracker
  huntingWindowButton = huntingWindow:recursiveGetChildById("huntingTaskButton")

  for i = 1, 3 do
	local slot = huntingWindow:recursiveGetChildById("slot" .. i)
	local inactiveWindow = slot:recursiveGetChildById("inactive")
	local activeWindow = slot:recursiveGetChildById("active")
	local lockedWindow = slot:recursiveGetChildById("locked")
	local wildcardSelection = slot:recursiveGetChildById("selection")
	local exhaustWindow = slot:recursiveGetChildById("exhaust")
	huntingSlots[i] = {window = slot, inactive = inactiveWindow, active = activeWindow, locked = lockedWindow, selection = wildcardSelection, exhaust = exhaustWindow}
  end

  huntingWindow:hide()
end

function terminate()
  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
	onResourceBalance = onPreyResourceBalance,
	onPreyHuntingBaseData = onPreyHuntingBaseData,
	onPreyHuntingPrice = onPreyHuntingPrice,
	onUpdateRerrolTime = onUpdateRerrolTime,
	onHuntingLockedState = onHuntingLockedState,
	onHuntingSelectState = onHuntingSelectState,
	onHuntingActiveState = onHuntingActiveState,
	onHuntingWildcardState = onHuntingWildcardState,
	onHuntingExhaustedState = onHuntingExhaustedState
  })

  g_keyboard.unbindKeyPress('Tab', onSelectPrey, huntingWindow)
end

function close()
  hide()
  g_client.setInputLockWidget(nil)
end

function show(position)
	huntingWindow:show(true)
	huntingWindow:focus()
	g_client.setInputLockWidget(huntingWindow)
	if position ~= nil then
		huntingWindow:setPosition(position)
	end

	local localPlayer = g_game.getLocalPlayer()
	onPreyResourceBalance(ResourceBank, localPlayer:getResourceValue(ResourceBank))
	onPreyResourceBalance(ResourceInventary, localPlayer:getResourceValue(ResourceInventary))
	onPreyResourceBalance(ResourcePreyBonus, localPlayer:getResourceValue(ResourcePreyBonus))
	onPreyResourceBalance(ResourceHuntingTask, localPlayer:getResourceValue(ResourceHuntingTask))

	huntingWindowButton:setChecked(true)
	inactiveSelections = {}

	if updateRerollEvent then
		removeEvent(updateRerollEvent)
	end

	g_keyboard.bindKeyPress('Tab', onSelectPrey, huntingWindow)
	updateRerollEvent = cycleEvent(function() updateVisibleRerollTime() end, 1000)

	for i = 1, 3 do
		local list = huntingSlots[i].inactive.list
		if list and list:isVisible() and list:getChildCount() > 0 then
			modules.game_prey_hunting.onItemBoxChecked(list:getFirstChild())
			inactiveSelections[i] = widget
		end
	end
	onUpdate()
end

function hide()
  for i = 1, 3 do
    for i, widget in pairs(huntingSlots[i].inactive.list:getChildren()) do
	  widget:setChecked(false)
    end
  end

  g_keyboard.unbindKeyPress('Tab', onSelectPrey, huntingWindow)
  huntingWindow:hide()
  g_client.setInputLockWidget(nil)
  huntingWindowButton:setChecked(false)
  huuntingMessageWindow = nil

  if updateRerollEvent then
	removeEvent(updateRerollEvent)
	updateRerollEvent = nil
  end
end

function online()
  local benchmark = g_clock.millis()
  huntingWindow:hide()
  consoleln("Prey Hunting loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function offline()
  huntingWindow:hide()
  g_client.setInputLockWidget(nil)
  huuntingMessageWindow = nil
end

function onSelectPrey()
	hide()
	g_client.setInputLockWidget(nil)
	modules.game_prey.show(huntingWindow:getPosition())
end

function onItemBoxChecked(widget)
	local slot = widget:getActionId()
	local panel = huntingSlots[widget:getActionId()]
	if not panel then
		return
	end

	if inactiveSelections[slot] then
		inactiveSelections[slot]:setChecked(false)
	end

	for i, widget in pairs(huntingSlots[slot].inactive.list:getChildren()) do
		widget:setChecked(false)
	end

	if lastSelectedCreature[slot] then
		local hightlight = lastSelectedCreature[slot]:recursiveGetChildById("highlight")
		if hightlight then
			hightlight:setBackgroundColor("alpha")
		end
	end

	inactiveSelections[slot] = widget
	widget:setChecked(true)
	updateWidgetDescription(slot, DESC_TYPE.TYPE_MONSTER_LIST)
	panel.window:recursiveGetChildById('title'):setText(short_text(tr("Selected: %s", widget.creature:getTooltip()), 26))

	local bestiaryUnlocked = currentMonsterList[slot][widget.creature:getRaceID()]
	local minKill, maxKill = getMinMaxKills(widget.creature:getRaceID())
	panel.inactive.minCount:setText(minKill)
	panel.inactive.maxCount:setText(maxKill)
	panel.inactive.minCount:setActionId(slot)
	panel.inactive.maxCount:setActionId(slot)
	panel.inactive.minCount:setChecked(true)

	if bestiaryUnlocked == 1 then
		panel.inactive.maxCount:setChecked(false)
		panel.inactive.maxCount:enable()
		panel.inactive.maxCount:setColor("#c0c0c0")
	else
		panel.inactive.maxCount:setChecked(false)
		panel.inactive.maxCount:disable()
		panel.inactive.maxCount:setColor("#707070")
	end

	lastSelectedCreature[slot] = widget
	widget.highlight:setBackgroundColor("white")
end

function onHuntingHover(widget, type)
	local slot = widget:getActionId()
	if not slot then
		huntingWindow.description:setText("")
		return
	end
	updateWidgetDescription(slot, type, widget)
end

function updateWidgetDescription(slot, type, widget)
	local text = ""
	if type == DESC_TYPE.TYPE_MONSTER_LIST then
		if inactiveSelections[slot] == nil then
			huntingWindow.description:setText("")
			return
		end

		local raceID = inactiveSelections[slot]:recursiveGetChildById("creature"):getRaceID()
		local bestiaryUnlocked = huntingSlots[slot].inactive.maxCount:isChecked() and 1 or 0

		local kills = getHuntingKills(raceID, bestiaryUnlocked)
		local minReward, maxReward = getMinMaxReward(raceID, bestiaryUnlocked)
		text = tr("Creature: %s\nAmount: %s\nReward: %s (^;;;;;) - %s (^^^^^) Hunting Task Points", inactiveSelections[slot]:recursiveGetChildById("creature"):getTooltip(), kills, minReward, maxReward)
	elseif type == DESC_TYPE.TYPE_MONSTER_SELECTED then
		local slotInfo = selectedMonster[slot]
		if not slotInfo then
			return
		end

		local starText = ";;;;;"
		for i = 1, slotInfo.grade do
			starText = starText:sub(1, i - 1) .. "^" .. starText:sub(i + 1)
		end

		text = tr("Creature: %s\nAmount: %s / %s\nReward: %s / %s Hunting Task Points\nThere is a 10%s chance that you will get 50%s or even 100%s more Hunting Task Points.", slotInfo.currentRace, slotInfo.currentKills, slotInfo.maxKills, starText, slotInfo.reward, "%", "%", "%")
	elseif type == DESC_TYPE.TYPE_CANCEL_MONSTER then
		text = "Click here to cancel the currently active Hunting Task to free the slot. Note that you lose possible\nhigher rewards which you have purchased using Prey Wildcards."
	elseif type == DESC_TYPE.TYPE_REWARD_INCREASE then
		text = "Click here to get higher rewards. While higher rewards are selected, you will get a chance to win\nadditional Hunting Task Points."
	elseif type == DESC_TYPE.TYPE_SELECT_WILDCARD then
		text = "Click here to choose a new Hunting Task creature from the list of available creatures."
	elseif type == DESC_TYPE.TYPE_LIST_REROLL then
		text = "Click here to create a new list of 9 creatures to select a Hunting Task creature from."
	elseif type == DESC_TYPE.TYPE_CONFIRM_SELECTION or type == DESC_TYPE.TYPE_WILDCARD_LIST then
		local slotInfo = inactiveSelections[slot]
		if slotInfo then
			if not slotInfo.creature then
				return
			end

			local raceID = slotInfo.creature:getRaceID()
			if not raceID then
				return
			end

			local bestiaryUnlocked = huntingSlots[slot].inactive.maxCount:isChecked() and 1 or 0
			local monster = g_things.getMonsterList()[raceID]
			if not monster then
				return
			end
			local name = monster[1]
			local kills = getHuntingKills(raceID, bestiaryUnlocked)
			local minReward, maxReward = getMinMaxReward(raceID, bestiaryUnlocked)
			text = tr("Confirm the selected Hunting Task creature and amount to start your Hunting Task.\n\nCreature: %s\nAmount: %s\nReward: %s (^;;;;;) - %s (^^^^^) Hunting Task Points", string.capitalize(name), kills, minReward, maxReward)
		else
			slotInfo = wildcardSelectedMonster[slot]
			if not slotInfo then
				huntingWindow.description:setText("Confirm the selected Hunting Task creature and amount to start your Hunting Task.")
				return
			end

			local raceID = tonumber(slotInfo:getId())
			local bestiaryUnlocked = huntingSlots[slot].selection.maxCount:isChecked() and 1 or 0
			local monster = g_things.getMonsterList()[raceID]
			if not monster then
				return
			end
			local name = monster[1]
			local kills = getHuntingKills(raceID, bestiaryUnlocked)
			local minReward, maxReward = getMinMaxReward(raceID, bestiaryUnlocked)
			local header = (type == DESC_TYPE.TYPE_WILDCARD_LIST and "" or "Confirm the selected Hunting Task creature and amount to start your Hunting Task.\n\n")
			text = tr("%sCreature: %s\nAmount: %s\nReward: %s (^;;;;;) - %s (^^^^^) Hunting Task Points", header, string.capitalize(name), kills, minReward, maxReward)
		end
	elseif type == DESC_TYPE.TYPE_CLAIM_REWARD then
		text = "Finish the Hunting Task to claim your reward."
	elseif type == DESC_TYPE.TYPE_SLOT_EXHAUSTED then
		text = "Exhausted.\n\nyou have to wait until next to use this Hunting Task slot again."
	elseif type == DESC_TYPE.TYPE_SLOT_LOCKED then
		text = "This Hunting Task is not available for your character yet.\nMove the mouse over the large blue button(s) to learn how to unlock this Hunting Task slot."
	elseif type == DESC_TYPE.TYPE_SLOT_REROLL then
		local widgetText = widget:getText()
		if widgetText == "Free" then
			text = "Your next List Reroll is free of charge.\nYou get a Free List Reroll every 20 hours for each slot."
		else
			text = tr("You will get your next Free List Reroll in %s.\nYou get a Free List Reroll every 20 hours for each slot.", widgetText)
		end
	end

	huntingWindow.description:setText(text)
end

function onChangeMonsterCount(button, minWidget, wildcard)
	local panel = huntingSlots[button:getActionId()]
	if not panel then
		return
	end

	local widget = (wildcard and panel.selection or panel.inactive)

	if minWidget then
		widget.minCount:setChecked(true)
		widget.maxCount:setChecked(false)
	else
		widget.minCount:setChecked(false)
		widget.maxCount:setChecked(true)
	end
	updateWidgetDescription(button:getActionId(), DESC_TYPE.TYPE_MONSTER_LIST)
end

function onHuntingCancel(widget)
	local slot = widget:getActionId()
	if selectedMonster[slot + 1] == nil then
		return
	end

	rewardGrade[slot + 1] = nil
	sendHuntingMessageBox(slot, "cancel");
end

function onHuntingRewardIncrease(widget)
	local slot = widget:getActionId()
	if selectedMonster[slot + 1] == nil then
		return
	end

	-- checar saldo de wildcard
	sendHuntingMessageBox(slot, "upgrade")
end

function onSelectWithWildcard(widget)
	local slot = widget:getActionId()
	if currentMonsterList[slot + 1] == nil then
		return
	end

	-- checar saldo de wildcard
	sendHuntingMessageBox(slot, "wildcard")
end

function onConfirmWithWildcard(widget)
	local slot = widget:getActionId()
	if wildcardSelectedMonster[slot] == nil then
		return
	end

	-- checar saldo de wildcard
	sendHuntingMessageBox(slot, "select")
end

function onHuntingListRerrol(widget)
	local slot = widget:getActionId()
	if currentMonsterList[slot + 1] == nil then
		return
	end

	-- checar gold
	sendHuntingMessageBox(slot, "reroll")
end

function sendHuntingMessageBox(slot, type)
	if huuntingMessageWindow then
		return true
	end

	huntingWindow:hide()
	g_client.setInputLockWidget(nil)

	if type == "cancel" then
		local yesFunction = function() activeMonsterList[slot + 1] = nil g_game.preyHuntingAction(slot, PREY_HUNTING_ACTION_REMOVE, false, 0) huntingWindow:show() huuntingMessageWindow:destroy() huuntingMessageWindow = nil g_client.setInputLockWidget(huntingWindow) end
		local noFunction = function() huntingWindow:show() huuntingMessageWindow:destroy() huuntingMessageWindow = nil g_client.setInputLockWidget(huntingWindow) end

		huuntingMessageWindow = displayGeneralBox(tr('Confirmation of Task Cancellation'), tr("Do you want to spend %s gold to cancel the Hunting Task?\nYou currently have %s gold available.", comma_value(goldRemovePrice), comma_value(bankBalance + invetoryMoney)),
			{ { text=tr('Yes'), callback=yesFunction },
			{ text=tr('No'), callback=noFunction }
		}, yesFunction, noFunction)
	elseif type == "upgrade" or type == "wildcard" then
		local action = (type == "upgrade" and PREY_HUNTING_ACTION_BONUSREROLL or PREY_HUNTING_ACTION_SELECT_WILDCARD)
		local required = (type == "upgrade" and rerollWildcardPrice or wildcardSelectPrice)

		local yesFunction = function() g_game.preyHuntingAction(slot, action, false, 0) huntingWindow:show() huuntingMessageWindow:destroy() huuntingMessageWindow = nil g_client.setInputLockWidget(huntingWindow) end
		local noFunction = function() huntingWindow:show() huuntingMessageWindow:destroy() huuntingMessageWindow = nil g_client.setInputLockWidget(huntingWindow) end

		huuntingMessageWindow = displayGeneralBox(tr('Confirmation of Using Prey Wildcards'), tr("Are you sure you want to use %s of your remaning %s Prey Wildcards?", required, wildcardBalance),
			{ { text=tr('Yes'), callback=yesFunction },
			{ text=tr('No'), callback=noFunction }
		}, yesFunction, noFunction)
	elseif type == "select" then
		local yesFunction = function() selectWildcardCreature(slot) huntingWindow:show() huuntingMessageWindow:destroy() huuntingMessageWindow = nil g_client.setInputLockWidget(huntingWindow) end
		local noFunction = function() huntingWindow:show() huuntingMessageWindow:destroy() huuntingMessageWindow = nil g_client.setInputLockWidget(huntingWindow) end
		huuntingMessageWindow = displayGeneralBox(tr('Confirmation of Starting Hunting Task'), "Do you want to start the selected Hunting Task?",
			{ { text=tr('Yes'), callback=yesFunction },
			{ text=tr('No'), callback=noFunction }
		}, yesFunction, noFunction)
	elseif type == "reroll" then
		local yesFunction = function() g_game.preyHuntingAction(slot, PREY_HUNTING_ACTION_LISTREROLL, false, 0) huntingWindow:show() huuntingMessageWindow:destroy() huuntingMessageWindow = nil g_client.setInputLockWidget(huntingWindow) end
		local noFunction = function() huntingWindow:show() huuntingMessageWindow:destroy() huuntingMessageWindow = nil g_client.setInputLockWidget(huntingWindow) end

		local tmp = "Are you sure you want to use the Free List Reroll?"
		local time = nextRerollTime[slot + 1]
		if time and time.timeLeft > 0 then
			tmp = tr("Do you want to spend %s gold for a List Reroll?\nYou currently have %s gold available for the purchase.", comma_value(goldUpdatePrice), comma_value(bankBalance + invetoryMoney))
		end

		huuntingMessageWindow = displayGeneralBox(tr('Confirmation of Using List Reroll'), tmp,
			{ { text=tr('Yes'), callback=yesFunction },
			{ text=tr('No'), callback=noFunction }
		}, yesFunction, noFunction)

	end
	return true
end

function selectWildcardCreature(slot)
	local selection = wildcardSelectedMonster[slot]
	local panel = huntingSlots[slot]
	if not selection or not panel then
		huntingWindow:show()
		return
	end

	local raceID = tonumber(selection:getId())
	local bestiaryUnlocked = huntingSlots[slot].selection.maxCount:isChecked() and true or false

	panel.selection.minCount:setChecked(true)
	panel.selection.minCount:setText("0")
	panel.selection.maxCount:setChecked(false)
	panel.selection.maxCount:setText("0")
	panel.selection.maxCount:disable()
	panel.selection.searchText:setText("")
	panel.selection.panel.creature:hide()

	local chooseButton = panel.selection:recursiveGetChildById('chooseTaskButton')
	chooseButton:setOn(false)

	g_game.preyHuntingAction(slot - 1, PREY_HUNTING_ACTION_SELECT, bestiaryUnlocked, raceID)
end

function onWildcardHuntingChange(panel, selected)
	if not panel then
		return
	end

	local slot = selected:getActionId()

	local chooseButton = panel.selection:recursiveGetChildById('chooseTaskButton')
	chooseButton:setOn(true)
	chooseButton:setActionId(selected:getActionId())

	if wildcardSelectedMonster[slot] and wildcardSelectedMonster[slot] ~= selected then
		wildcardSelectedMonster[slot]:setColor(oldSelectionTextColor[slot])
		wildcardSelectedMonster[slot]:setBackgroundColor(oldSelectionBGColor[slot])
	end

	local creature = g_things.getMonsterList()[tonumber(selected:getId())]
	if not creature then
		return
	end
	panel.window:recursiveGetChildById('title'):setText(short_text(tr("Selected: %s", string.capitalize(creature[1])), 28))
	panel.selection.panel.creature:setOutfit({type = creature[2], auxType = creature[3], head = creature[4], body = creature[5], legs = creature[6], feet = creature[7], addons = creature[8]})
	panel.selection.panel.creature:show()

	local bestiaryUnlocked = currentWildcardList[slot][tonumber(selected:getId())]
	local minKill, maxKill = getMinMaxKills(selected:getId())
	panel.selection.minCount:setText(minKill)
	panel.selection.maxCount:setText(maxKill)
	panel.selection.minCount:setActionId(selected:getActionId())
	panel.selection.maxCount:setActionId(selected:getActionId())
	panel.selection.minCount:setChecked(true)

	if bestiaryUnlocked == 0 then
		panel.selection.maxCount:setChecked(false)
		panel.selection.maxCount:disable()
		panel.selection.maxCount:setColor("#707070")
	else
		panel.selection.maxCount:enable()
		panel.selection.maxCount:setColor("#c0c0c0")
	end

	oldSelectionBGColor[slot] = selected:getBackgroundColor()
	oldSelectionTextColor[slot] = selected:getColor()

	wildcardSelectedMonster[slot] = selected

	wildcardSelectedMonster[slot]:setBackgroundColor("#585858")
	wildcardSelectedMonster[slot]:setColor("#f4f4f4")
end

function onPreyResourceBalance(type, amount)
	if type == nil then
		return
	end

	if type == 0 then -- bank gold
		bankBalance = amount
	elseif type == 1 then -- inventory gold
		invetoryMoney = amount
	elseif type == 10 then -- bonus rerolls
		wildcardBalance = amount
		huntingWindow.wildCards.text:setText(wildcardBalance)
	elseif type == 50 then -- hunting tokens
		huntingToken = amount
		huntingWindow.tasksPoints.text:setText(huntingToken)
	end

	if type == 0 or type == 1 then
		if invetoryMoney == nil then
			invetoryMoney = 0
		end

		if bankBalance == nil then
			bankBalance = 0
		end

		huntingWindow.gold.text:setText(comma_value(bankBalance + invetoryMoney))
	end

	local moneyTooltip = {}
	setStringColor(moneyTooltip, "Cash: " .. comma_value(invetoryMoney), "#3f3f3f")
	setStringColor(moneyTooltip, " $", "#f7e6fe")
	setStringColor(moneyTooltip, "\nBank: " .. comma_value(bankBalance), "#3f3f3f")
	setStringColor(moneyTooltip, " $", "#f7e6fe")
	huntingWindow.gold.text:setTooltip(moneyTooltip)

	onUpdate()
end

function onPreyHuntingPrice(rerollPrice, removePrice, wildcardSelect, rerollWildcard)
	goldUpdatePrice = rerollPrice
	goldRemovePrice = removePrice
	wildcardSelectPrice = wildcardSelect
	rerollWildcardPrice = rerollWildcard
end

function onUpdateRerrolTime(slot, time)
	nextRerollTime[slot + 1] = {timeLeft = time, startTime = os.time()}
	onUpdate()
end

function onPreyHuntingBaseData(monsterInfo, rewardData)
	huntingMonsterData = monsterInfo
	huntingRewardData = rewardData
end

function onHuntingLockedState(slot, lockType, state)
	local panel = huntingSlots[slot + 1]
	if not panel then
		return
	end

	updatePreyWidget(slot, state)

	panel.inactive:setVisible(false)
	panel.active:setVisible(false)
	panel.locked:setVisible(true)
	panel.selection:setVisible(false)
	panel.exhaust:setVisible(false)
	panel.window:recursiveGetChildById('title'):setText("Locked")
	panel.locked.noCreature.placeHolder:setActionId(slot)
end

function onHuntingSelectState(slot, creatureList, state)
	local panel = huntingSlots[slot + 1]
	if not panel then
		return
	end

	updatePreyWidget(slot, state)

	currentMonsterList[slot + 1] = creatureList
	inactiveSelections[slot + 1] = nil
	rewardGrade[slot + 1] = nil

	panel.inactive:setVisible(true)
	panel.active:setVisible(false)
	panel.locked:setVisible(false)
	panel.selection:setVisible(false)
	panel.exhaust:setVisible(false)

	panel.inactive.minCount:setText("0")
	panel.inactive.maxCount:setText("0")
	panel.inactive.minCount:setChecked(true)
	panel.inactive.maxCount:setChecked(false)
	panel.inactive.maxCount:disable()
	panel.inactive.maxCount:setColor("#707070")

	local wildcardButton = panel.inactive:recursiveGetChildById('pickSpecificHunting')
	wildcardButton:setActionId(slot)
	panel.inactive.select.price.text:setText(wildcardSelectPrice)
	panel.inactive.reroll.price.text:setText(convertLongGold(goldUpdatePrice, true))
	panel.inactive.select.price.text:setColor("#c0c0c0")
	wildcardButton:setEnabled(true)
	wildcardButton:setOn(true)

	if wildcardBalance < wildcardSelectPrice then
		panel.inactive.select.price.text:setColor("#d33c3c")
		wildcardButton:setEnabled(false)
		wildcardButton:setOn(false)
	end

	local rerollButton = panel.inactive:recursiveGetChildById('rerollButton')
	rerollButton:setActionId(slot)
	panel.inactive.reroll.price.text:setColor("#c0c0c0")
	rerollButton:setEnabled(true)
	rerollButton:setOn(true)

	local rerollTime = panel.inactive.reroll:recursiveGetChildById('time')
	local nextTime = (nextRerollTime[slot + 1] or {timeLeft = 0, startTime = 0})
	if nextTime.timeLeft == 0 then
		rerollTime:setText("Free")
		panel.inactive.select.price.text:setColor("#c0c0c0")
		panel.inactive.reroll.price.textOff:setVisible(true)
		panel.inactive.reroll.price.text:setText("0")
		panel.inactive.reroll.price.textOff:setText(convertLongGold(goldUpdatePrice, true, true))
	else
		local percent = (nextTime.timeLeft / (20 * 60 * 60)) * 100
		panel.inactive.reroll.price.textOff:setVisible(false)
		rerollTime:setText(modules.game_prey.timeleftTranslation(nextTime.timeLeft))
		rerollTime:setPercent(percent)

		if bankBalance + invetoryMoney < goldUpdatePrice then
			panel.inactive.reroll.price.text:setColor("#d33c3c")
			rerollButton:setEnabled(false)
			rerollButton:setOn(false)
		end
	end

	currentWildcardList[slot + 1] = nil
	selectedMonster[slot + 1] = nil

	panel.inactive.choose.chooseTaskButton:setOn(true)
	panel.inactive.choose.chooseTaskButton:setActionId(slot + 1)

	local firstSelected = false
	local monsterList = panel.inactive.list
	monsterList:destroyChildren()
  	local monsters = g_things.getMonsterList()
	for raceId, _ in pairs(creatureList) do
		local box = g_ui.createWidget("PreyHuntingCreatureBox", monsterList)
		local monster = monsters[raceId]
		if monster then
			box.creature:setOutfit({type = monster[2], auxType = monster[3], head = monster[4], body = monster[5], legs = monster[6], feet = monster[7], addons = monster[8]})
			box.creature:setRaceID(raceId)
			box:setActionId(slot + 1)
			box.creature:setTooltip(string.capitalize(monster[1]))
			box.onHoverChange = function(box, hovered)
				onHuntingHover(box, DESC_TYPE.TYPE_MONSTER_LIST)
			end

			if not firstSelected and not inactiveSelections[slot + 1] then
				onItemBoxChecked(box)
				firstSelected = true
				panel.window:recursiveGetChildById('title'):setText(short_text(tr("Selected: %s", string.capitalize(monster[1])), 28))
			end
		end
	end

	panel.inactive.choose.chooseTaskButton.onClick = function()
		local selection = inactiveSelections[slot + 1]
		if selection and selection:isChecked() and selection.creature then
			local bestiaryUnlocked = huntingSlots[slot + 1].inactive.maxCount:isChecked() and true or false
			return g_game.preyHuntingAction(slot, PREY_HUNTING_ACTION_SELECT, bestiaryUnlocked, selection.creature:getRaceID())
		end
	end
end

function onHuntingActiveState(slot, currentMonster, unlocked, toKill, killed, stars, state)
	local panel = huntingSlots[slot + 1]
	if not panel then
		return
	end

	panel.inactive:setVisible(false)
	panel.active:setVisible(true)
	panel.locked:setVisible(false)
	panel.selection:setVisible(false)
	panel.exhaust:setVisible(false)

	panel.active.removeCreature.price.text:setText(formatMoney(goldRemovePrice, ","))
	panel.active.higherReward.price.text:setText(rerollWildcardPrice)

	currentMonsterList[slot + 1] = nil
	inactiveSelections[slot + 1] = nil
	rewardGrade[slot + 1] = stars

	local cancelButton = panel.active:recursiveGetChildById('removeButton')
	cancelButton:setActionId(slot)
	panel.active.removeCreature.price.text:setColor("#c0c0c0")
	cancelButton:setEnabled(true)
	cancelButton:setOn(true)

	if bankBalance + invetoryMoney < goldRemovePrice then
		panel.active.removeCreature.price.text:setColor("#d33c3c")
		cancelButton:setEnabled(false)
		cancelButton:setOn(false)
	end

	local noWildcard = rerollWildcardPrice > wildcardBalance
	local upgradeButton = panel.active:recursiveGetChildById('pickHigherReward')
	upgradeButton:setActionId(slot)
	panel.active.higherReward.price:setColor("#c0c0c0")
	upgradeButton:setEnabled(true)
	upgradeButton:setOn(true)

	if stars == 5 or noWildcard then
		upgradeButton:setEnabled(false)
		upgradeButton:setOn(false)
		if hasWildcard then
			panel.active.higherReward.price:setColor("#d33c3c")
		end
	end

	local completed = (killed >= toKill)
	local rewardCount = getHuntingRewardPoints(currentMonster, stars, unlocked)
	local reward = panel.active:recursiveGetChildById('rewardPoints')
	reward:setText(rewardCount)

	local counter = panel.active:recursiveGetChildById('killCounter')
	counter:setPercent(killed * 100 / toKill)
	counter:setText(tr("%s / %s", killed, toKill))
	if completed then
		cancelButton:setEnabled(false)
		cancelButton:setOn(false)
		panel.active.pick.inactivePickReward:setVisible(false)
		panel.active.pick.pickReward:setVisible(true)
		panel.active.pick.pickReward:setActionId(slot + 1)
		panel.active.pick.pickReward.onClick = function() g_game.preyHuntingAction(slot, PREY_HUNTING_ACTION_COLLECT, false, 0) end
	else
		panel.active.pick.inactivePickReward:setVisible(true)
		panel.active.pick.pickReward:setVisible(false)
	end

	local creatureWidget = panel.active:recursiveGetChildById('creature')
	local monster = g_things.getMonsterList()[currentMonster]
	if not monster then
		return
	end
  	creatureWidget:setOutfit({type = monster[2], auxType = monster[3], head = monster[4], body = monster[5], legs = monster[6], feet = monster[7], addons = monster[8]})
  	creatureWidget:setCenter(true)
  	creatureWidget:setActionId(slot + 1)

	local titleLabel = panel.window:recursiveGetChildById('title')
	titleLabel:setText(short_text(tr("Currently hunting: %s", string.capitalize(monster[1])), 29))
	titleLabel:setTextAutoResize(true)

	selectedMonster[slot + 1] = {currentRace = monster[1], maxKills = toKill, currentKills = killed, reward = rewardCount, grade = stars}
  	activeMonsterList[slot + 1] = monster[1]

	-- Stars
	local starGrade = panel.active:recursiveGetChildById('grade')
	starGrade:destroyChildren()
	for i = 1, 5 do
		if i <= stars then
			g_ui.createWidget("Star", starGrade)
		else
			g_ui.createWidget("NoStar", starGrade)
		end
	end

	panel.active.monsterName = monster[1]
	panel.active.stars = stars
	panel.active.rewardCount = rewardCount
	updatePreyWidget(slot, state)
end

function onHuntingWildcardState(slot, monsterList, state)
	local panel = huntingSlots[slot + 1]
	if not panel then
		return
	end

	updatePreyWidget(slot, state)

	panel.inactive:setVisible(false)
	panel.active:setVisible(false)
	panel.locked:setVisible(false)
	panel.selection:setVisible(true)
	panel.exhaust:setVisible(false)

	local selectButton = panel.selection:recursiveGetChildById('chooseTaskButton')
	selectButton:setActionId(slot)

	currentWildcardList[slot + 1] = monsterList

	local monsterListWidget = panel.selection:recursiveGetChildById('monsterList')
	monsterListWidget:destroyChildren()
	panel.selection.searchText:setActionId(slot + 1)
	panel.selection.panel.creature:setActionId(slot + 1)

	local count = 0
  	local creatures = g_things.getMonsterList()
	for k, v in pairs(monsterList) do
		local monster = g_ui.createWidget("Panel", monsterListWidget)
		monster:setId(k)
		monster:setActionId(slot + 1)
		monster:setTextAlign(AlignLeft)
		count = count + 1
		local color = ((count % 2 == 0) and '#484848' or '#414141')
		monster:setBackgroundColor(color)
		local creature = creatures[k]
		if creature then
			monster:setText(string.capitalize(creature[1]))
			monster:setColor("#c0c0c0")
			monster:setFont("Verdana Bold-11px")
		end
	end

	monsterListWidget.onChildFocusChange = function(self, selected) onWildcardHuntingChange(panel, selected) end
	monsterListWidget:setActionId(slot + 1)
end

function onHuntingExhaustedState(slot, state)
	local panel = huntingSlots[slot + 1]
	if not panel then
		return
	end

	updatePreyWidget(slot, state)

	panel.inactive:setVisible(false)
	panel.active:setVisible(false)
	panel.locked:setVisible(false)
	panel.selection:setVisible(false)
	panel.exhaust:setVisible(true)
	panel.window:recursiveGetChildById('title'):setText("Exhausted")

	local rerollButton = panel.exhaust:recursiveGetChildById('exhaustRerollButton')
	rerollButton:setActionId(slot)

	local rerollTime = panel.exhaust.exhaustReroll:recursiveGetChildById('time')
	local nextTime = nextRerollTime[slot + 1] or {timeLeft = 0, startTime = 0}
	if nextTime.timeLeft == 0 then
		rerollTime:setText("Free")
	else
		local percent = (nextTime.timeLeft / (20 * 60 * 60)) * 100
		rerollTime:setText(modules.game_prey.timeleftTranslation(nextTime.timeLeft))
		rerollTime:setPercent(percent)
	end

	panel.exhaust.exhaustReroll.price.text:setText(convertLongGold(goldUpdatePrice, true))
	panel.exhaust.exhaustReroll.price.text:setColor("#c0c0c0")
	if bankBalance + invetoryMoney < goldUpdatePrice then
		panel.exhaust.exhaustReroll.price.text:setColor("#d33c3c")
	end

	panel.exhaust.exhaustSelect.price.text:setText(wildcardSelectPrice)
	panel.exhaust.exhaustSelect.price.text:setColor("#c0c0c0")
	if wildcardBalance < wildcardSelectPrice then
		panel.exhaust.exhaustSelect.price.text:setColor("#d33c3c")
	end

	panel.exhaust.exhaustSelect.exhaustSpecificHunting:setActionId(slot)
	panel.exhaust.exhaustReroll.button.exhaustRerollButton:setActionId(slot)
	panel.exhaust.emptyPanel.hoverPlaceholder:setActionId(slot)
	panel.exhaust.bonus.hoverPlaceholder:setActionId(slot)
end

function onSearchChange(widget)
	local text = widget:getText()
	if #text > 0 then
		widget:setColor("#c0c0c0")
	end

	local panel = huntingSlots[widget:getActionId()]
	if not panel then
		return
	end

	local monsterList = panel.selection.monsterList
	if not monsterList then
		return
	end

	if wildcardSelectedMonster[widget:getId()] then
		panel.selection.minCount:setText("0")
		panel.selection.maxCount:setText("0")
		panel.selection.minCount:setChecked(true)
		panel.selection.maxCount:setChecked(false)
		wildcardSelectedMonster[widget:getId()]:setBackgroundColor(oldSelectionBGColor[widget:getId()])
		wildcardSelectedMonster[widget:getId()]:setColor(oldSelectionTextColor[widget:getId()])
		wildcardSelectedMonster[widget:getId()] = nil
		local chooseButton = panel.selection:recursiveGetChildById('chooseTaskButton')
		chooseButton:setOn(false)
		panel.selection.panel.creature:hide()
	end

	local count = 0
	for i, widget in pairs(monsterList:getChildren()) do
		widget:show()
		count = count + 1
		local color = ((count % 2 == 0) and '#484848' or '#414141')
		widget:setBackgroundColor(color)
	end

	count = 0
	for i, widget in pairs(monsterList:getChildren()) do
		if not (text == '' or (string.find(widget:getText():lower(), text:lower()))) then
			widget:hide()
		end

		count = count + 1
		local color = ((count % 2 == 0) and '#484848' or '#414141')
		widget:setBackgroundColor(color)
	end
end

function getMinMaxKills(monsterId)
	local min, max = 0
	local difficulty = getHuntingRewardDifficulty(monsterId)
	if not difficulty then
		return min, max
	end

	for _, k in ipairs(huntingRewardData) do
		if k.difficulty == difficulty then
			min = k.nonBestiaryKills
			max = k.fullBestiaryKills
			break
		end
	end
	return min, max
end

function getMinMaxReward(monsterId, bestiaryUnlocked)
	local min, max = 0
	local difficulty = getHuntingRewardDifficulty(monsterId)
	if not difficulty then
		return min, max
	end

	for _, k in ipairs(huntingRewardData) do
		if k.difficulty == difficulty then
			if k.grade == 1 then
				min = bestiaryUnlocked == 0 and k.nonBestiaryReward or k.fullBestiaryReward
			end

			if k.grade == 5 then
				max = bestiaryUnlocked == 0 and k.nonBestiaryReward or k.fullBestiaryReward
			end
		end
	end
	return min, max
end

function getHuntingKills(monsterId, bestiaryUnlocked)
	local points = 0
	local difficulty = getHuntingRewardDifficulty(monsterId)
	if not difficulty then
		return points
	end

	for _, k in ipairs(huntingRewardData) do
		if k.difficulty == difficulty then
			points = bestiaryUnlocked == 0 and k.nonBestiaryKills or k.fullBestiaryKills
			break
		end
	end
	return points
end

function getHuntingRewardPoints(monsterId, stars, bestiaryUnlocked)
	local points = 0
	local difficulty = getHuntingRewardDifficulty(monsterId)
	if not difficulty then
		return points
	end

	for _, k in ipairs(huntingRewardData) do
		if k.difficulty == difficulty and k.grade == stars then
			points = bestiaryUnlocked == 0 and k.nonBestiaryReward or k.fullBestiaryReward
			break
		end
	end
	return points
end

function getHuntingRewardDifficulty(monsterId)
	local monsterData = huntingMonsterData[tonumber(monsterId)]
	if not monsterData then
		return 0
	end
	return monsterData
end

function onUpdate()
	for i = 1, #huntingSlots do
		local panel = huntingSlots[i]
		if not panel then
			return
		end

		if panel.inactive:isVisible() then
			local wildcardButton = panel.inactive:recursiveGetChildById('pickSpecificHunting')
			if wildcardBalance < wildcardSelectPrice then
				panel.inactive.select.price.text:setColor("#d33c3c")
				wildcardButton:setEnabled(false)
				wildcardButton:setOn(false)
			else
				panel.inactive.select.price:setColor("#c0c0c0")
				wildcardButton:setEnabled(true)
				wildcardButton:setOn(true)
			end

			local nextTime = (nextRerollTime[i] or {timeLeft = 0, startTime = 0})
			local rerollButton = panel.inactive:recursiveGetChildById('rerollButton')
			if nextTime.timeLeft > 0 and (bankBalance + invetoryMoney < goldUpdatePrice) then
				panel.inactive.reroll.price.text:setColor("#d33c3c")
				rerollButton:setEnabled(false)
				rerollButton:setOn(false)
			else
				panel.inactive.reroll.price.text:setColor("#c0c0c0")
				rerollButton:setEnabled(true)
				rerollButton:setOn(true)
			end

			local rerollTime = panel.inactive.reroll:recursiveGetChildById('time')
			if nextTime.timeLeft == 0 then
				rerollTime:setText("Free")
				rerollTime:setPercent(0)
			else
				local percent = (nextTime.timeLeft / (20 * 60 * 60)) * 100
				rerollTime:setText(modules.game_prey.timeleftTranslation(nextTime.timeLeft))
				rerollTime:setPercent(percent)
			end

		elseif panel.active:isVisible() then
			local cancelButton = panel.active:recursiveGetChildById('removeButton')
			if bankBalance + invetoryMoney < goldRemovePrice then
				panel.active.removeCreature.price.text:setColor("#d33c3c")
				cancelButton:setEnabled(false)
				cancelButton:setOn(false)
			else
				panel.active.removeCreature.price.text:setColor("#c0c0c0")

				local counter = panel.active:recursiveGetChildById('killCounter')
				if counter:getPercent() < 100 then
					cancelButton:setEnabled(true)
					cancelButton:setOn(true)
				end
			end

			local upgradeButton = panel.active:recursiveGetChildById('pickHigherReward')
			if rerollWildcardPrice > wildcardBalance or (rewardGrade[i] and rewardGrade[i] == 5) then
				upgradeButton:setEnabled(false)
				upgradeButton:setOn(false)
				if rerollWildcardPrice > wildcardBalance and (rewardGrade[i] and rewardGrade[i] < 5) then
					panel.active.higherReward.price:setColor("#d33c3c")
				end
			else
				panel.active.higherReward.price:setColor("#c0c0c0")
				upgradeButton:setEnabled(true)
				upgradeButton:setOn(true)
			end

		elseif panel.exhaust:isVisible() then
			if bankBalance + invetoryMoney < goldUpdatePrice then
				panel.exhaust.exhaustReroll.price:setColor("#d33c3c")
			else
				panel.exhaust.exhaustReroll.price:setColor("#c0c0c0")
			end

			if wildcardBalance < wildcardSelectPrice then
				panel.exhaust.exhaustSelect.price:setColor("#d33c3c")
			else
				panel.exhaust.exhaustSelect.price:setColor("#c0c0c0")
			end

			local rerollTime = panel.exhaust.exhaustReroll:recursiveGetChildById('time')
			local nextTime = (nextRerollTime[i] or {timeLeft = 0, startTime = 0})
			if nextTime.timeLeft == 0 then
				rerollTime:setText("Free")
			else
				local percent = (nextTime.timeLeft / (20 * 60 * 60)) * 100
				rerollTime:setText(modules.game_prey.timeleftTranslation(nextTime.timeLeft))
				rerollTime:setPercent(percent)
			end
		end
	end

	updateVisibleRerollTime()
end

function getActiveMonsters()
  local monsterList = {}
  for i = 1, 3 do
    if activeMonsterList[i] then
      monsterList[#monsterList + 1] = activeMonsterList[i]:lower()
    end
  end
  return monsterList
end

function isHuntingActive(name)
	for _, v in pairs(activeMonsterList) do
		if v:lower() == name:lower() then return true end
	end
	return false
end

function storeRedirect(offerType)
	g_client.setInputLockWidget(nil)
	huntingWindow:hide()
	g_game.openStore()
	g_game.requestStoreOffers(3, "", offerType)
end

function updatePreyWidget(slot, state)
	local preyTrackerSlot = preyTracker.contentsPanel["hslot" .. (slot + 1)]
	if state == PREY_HUNTING_STATE_LOCKED then
	  preyTrackerSlot:setVisible(false)
	  return
	end

	if slot == 2 then
		preyTrackerSlot:setVisible(true)
	end

	local panel = huntingSlots[slot + 1]
	if state == PREY_HUNTING_STATE_ACTIVE or state == PREY_HUNTING_STATE_REDEEM then
		local creatureWidget = panel.active:recursiveGetChildById('creature')
		local counter = panel.active:recursiveGetChildById('killCounter')
		local preyName = string.capitalize(panel.active.monsterName)

		preyTrackerSlot.creature:setOutfit(creatureWidget:getOutfit())
		preyTrackerSlot.creature:show()
		preyTrackerSlot.noCreature:hide()
		preyTrackerSlot.time:setPercent(counter:getPercent())
		preyTrackerSlot.creatureName:setText(short_text(preyName, 12))

		local stars = panel.active.stars
		local reward = panel.active.rewardCount
		local rewardText = ""
		for i = 1, 5 do
			if i <= stars then
				rewardText = rewardText .. "^"
			else
				rewardText = rewardText .. ";"
			end
		end

		local text = "Creature: %s\nAmount: %s\nReward: %s / %s Hunting Task Points\n\nClick in this window to open the prey dialog."
		preyTrackerSlot:setTooltip(tr(text, preyName, counter:getText(), rewardText, reward))
		preyTrackerSlot.onClick = function() show() end
	else
		preyTrackerSlot:setTooltip("Inactive Hunting Task. \n\nClick in this window to open the Prey dialog. Open the Hunting Tasks tab to select a new task.")
		preyTrackerSlot.noCreature:show()
		preyTrackerSlot.creature:hide()
		preyTrackerSlot.time:setPercent(0)
	end
end

function updateVisibleRerollTime()
	if not g_game.isOnline() or not huntingWindow:isVisible() then
		removeEvent(updateRerollEvent)
		updateRerollEvent = nil
		return
	end

	for slot, data in pairs(nextRerollTime) do
		local startTime = data.startTime
		local currentTime = os.time()
		local elapsedTime = currentTime - startTime
		local elapsedSeconds = math.round(elapsedTime)
		if elapsedSeconds >= 60 then
			setTimeUntilFreeReroll(slot, math.max(0, data.timeLeft - elapsedSeconds))
		end
	end
end

function setTimeUntilFreeReroll(slot, timeUntilFreeReroll)
	local prey = huntingSlots[slot]
	if not prey then
		return
	end

	local percent = (timeUntilFreeReroll / (20 * 60 * 60)) * 100
	local desc = modules.game_prey.timeleftTranslation(timeUntilFreeReroll)

	for i, panel in pairs({prey.inactive}) do
		local reroll = panel.reroll.button.time
		reroll:setPercent(percent)
		reroll:setText(desc)
		local price = panel.reroll.price.text
		if timeUntilFreeReroll > 0 then
			price:setText(convertLongGold(goldUpdatePrice, true))
			panel.reroll.price.textOff:setVisible(false)
		else
			price:setText(0)
			panel.reroll.price.textOff:setText(convertLongGold(goldUpdatePrice, true, true))
			panel.reroll.price.textOff:setVisible(true)
		end
	end
end
