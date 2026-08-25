-- chunkname: @/game_bossdifficulty/game_bossdifficulty.lua

local bossDifficultyWindow

local cachedWidgets = {}
local currentData
local closing = false

local function destroyDialog()
	if bossDifficultyWindow and not bossDifficultyWindow:isDestroyed() then
		bossDifficultyWindow:ungrabKeyboard()
		closing = true
		bossDifficultyWindow:destroy()
		closing = false
	end

	bossDifficultyWindow = nil
	cachedWidgets = {}
	currentData = nil
end

local function cacheWidgets()
	if not bossDifficultyWindow or bossDifficultyWindow:isDestroyed() then
		return
	end

	local ids = {
		"bossName",
		"bossCreature",
		"pedestal",
		"fireLeft",
		"fireRight",
		"difficultyEdit",
		"firstDifficulty",
		"prevDifficulty",
		"nextDifficulty",
		"lastDifficulty",
		"groupHighestValue",
		"personalHighestValue",
		"badLuckValue",
		"negativeModifiersList",
		"positiveModifiersList",
		"startFightButton",
		"cancelButton",
		"bottomPlayerBox",
		"leftPlayerBox1",
		"leftPlayerBox2",
		"rightPlayerBox1",
		"rightPlayerBox2"
	}

	for _, id in ipairs(ids) do
		cachedWidgets[id] = bossDifficultyWindow:recursiveGetChildById(id)
	end
end

local function getWidget(id)
	return cachedWidgets[id]
end

local function updateModifierList(listWidget, itemStyle, modifiers)
	if not listWidget or listWidget:isDestroyed() then
		return
	end

	listWidget:destroyChildren()

	for _, text in ipairs(modifiers or {}) do
		local item = g_ui.createWidget(itemStyle, listWidget)
		local textLabel = item:getChildById("text")

		if textLabel then
			textLabel:setText(text)
		end
	end
end

local function sameModifierList(left, right)
	left = left or {}
	right = right or {}
	if #left ~= #right then
		return false
	end

	for index = 1, #left do
		if left[index] ~= right[index] then
			return false
		end
	end

	return true
end

local function updateDifficultyDisplay()
	if not currentData then
		return
	end

	local edit = getWidget("difficultyEdit")

	if edit and not edit:isDestroyed() then
		edit:setText(tostring(currentData.difficulty))
	end

	local firstBtn = getWidget("firstDifficulty")

	if firstBtn and not firstBtn:isDestroyed() then
		firstBtn:setEnabled(currentData.startEnabled and currentData.difficulty > currentData.difficultyMin)
	end

	local prevBtn = getWidget("prevDifficulty")

	if prevBtn and not prevBtn:isDestroyed() then
		prevBtn:setEnabled(currentData.startEnabled and currentData.difficulty > currentData.difficultyMin)
	end

	local nextBtn = getWidget("nextDifficulty")

	if nextBtn and not nextBtn:isDestroyed() then
		nextBtn:setEnabled(currentData.startEnabled and currentData.difficulty < currentData.difficultyMax)
	end

	local lastBtn = getWidget("lastDifficulty")

	if lastBtn and not lastBtn:isDestroyed() then
		lastBtn:setEnabled(currentData.startEnabled and currentData.difficulty < currentData.difficultyMax)
	end
end

local function updateStats()
	if not currentData then
		return
	end

	local groupHighest = getWidget("groupHighestValue")

	if groupHighest and not groupHighest:isDestroyed() then
		groupHighest:setText(tostring(currentData.difficultyMax))
	end

	local personalHighest = getWidget("personalHighestValue")

	if personalHighest and not personalHighest:isDestroyed() then
		personalHighest:setText(tostring(currentData.personalMax))
	end

	local badLuck = getWidget("badLuckValue")

	if badLuck and not badLuck:isDestroyed() then
		badLuck:setText(tostring(currentData.badLuckDropBonus) .. "%")
	end
end

local function updateModifiers()
	if not currentData then
		return
	end

	updateModifierList(getWidget("negativeModifiersList"), "BossDifficultyConItem", currentData.negativeModifiers)
	updateModifierList(getWidget("positiveModifiersList"), "BossDifficultyProItem", currentData.positiveModifiers)
end

local function setDifficulty(difficulty)
	if not currentData or not currentData.startEnabled then
		return
	end

	difficulty = math.max(currentData.difficultyMin, math.min(currentData.difficultyMax, difficulty))

	if difficulty == currentData.difficulty then
		return
	end

	currentData.difficulty = difficulty

	g_game.sendBossDifficultyAction(2, difficulty)
	updateDifficultyDisplay()
end

function firstDifficulty()
	if currentData then
		setDifficulty(currentData.difficultyMin)
	end
end

function prevDifficulty()
	if currentData then
		setDifficulty(currentData.difficulty - 1)
	end
end

function nextDifficulty()
	if currentData then
		setDifficulty(currentData.difficulty + 1)
	end
end

function lastDifficulty()
	if currentData then
		setDifficulty(currentData.difficultyMax)
	end
end

function startFight()
	if not currentData or not currentData.startEnabled then
		return
	end

	g_game.sendBossDifficultyAction(0, currentData.difficulty)
end

function cancel()
	if closing then
		return
	end

	if currentData and g_game.isOnline() then
		g_game.sendBossDifficultyAction(1, 0)
	end

	destroyDialog()
end

function onBossDifficultyOpen(data)
	destroyDialog()
	if type(data) ~= "table" then
		return
	end

	currentData = data
	bossDifficultyWindow = g_ui.createWidget("BossDifficultyWindow", g_ui.getRootWidget())
	if not bossDifficultyWindow then
		currentData = nil
		g_logger.error("[Boss Difficulty] Unable to create BossDifficultyWindow.")
		return
	end

	cacheWidgets()

	local raceData = g_things.getRaceData(data.bossRaceId) or {}
	local bossName = raceData.name or tr("Unknown Boss")
	local nameLabel = getWidget("bossName")

	if nameLabel and not nameLabel:isDestroyed() then
		nameLabel:setText(bossName)
	end

	local creature = getWidget("bossCreature")

	if creature and not creature:isDestroyed() then
		if raceData.outfit then
			creature:setOutfit(raceData.outfit)
		else
			creature:setOutfit({
				type = 0
			})
		end

		creature:setStaticWalking(true)
	end

	local startBtn = getWidget("startFightButton")

	if startBtn and not startBtn:isDestroyed() then
		startBtn:setEnabled(data.startEnabled)
	end

	local playerBoxIds = {
		"bottomPlayerBox",
		"leftPlayerBox1",
		"rightPlayerBox1",
		"leftPlayerBox2",
		"rightPlayerBox2"
	}

	for i, boxId in ipairs(playerBoxIds) do
		local box = getWidget(boxId)

		if box and not box:isDestroyed() then
			local playerNameLabel = box:getChildById("playerNameLabel")

			if playerNameLabel then
				playerNameLabel:setText(data.playerNames[i] or "")
			end
		end
	end

	updateDifficultyDisplay()
	updateStats()
	updateModifiers()
	bossDifficultyWindow:raise()
	bossDifficultyWindow:focus()
	bossDifficultyWindow:grabKeyboard()
end

function onBossDifficultyClose()
	destroyDialog()
end

function onBossDifficultyUpdate(difficulty, negativeModifiers, positiveModifiers)
	if not currentData then
		return
	end

	negativeModifiers = negativeModifiers or {}
	positiveModifiers = positiveModifiers or {}
	local modifiersChanged = not sameModifierList(currentData.negativeModifiers, negativeModifiers)
		or not sameModifierList(currentData.positiveModifiers, positiveModifiers)

	currentData.difficulty = difficulty
	currentData.negativeModifiers = negativeModifiers
	currentData.positiveModifiers = positiveModifiers

	updateDifficultyDisplay()
	if modifiersChanged then
		updateModifiers()
	end
end

function onEngineBossDifficultySelection(difficultyMin, startEnabled, bossRaceId, difficulty, groupHighest, personalHighest, badLuck, playerNames, negativeModifiers, positiveModifiers)
	onBossDifficultyOpen({
		bossRaceId = bossRaceId,
		difficulty = difficulty,
		difficultyMin = difficultyMin,
		difficultyMax = groupHighest,
		personalMax = personalHighest,
		badLuckDropBonus = math.floor((badLuck or 0) / 10 + 0.5), -- server sends per-mille
		playerNames = playerNames or {},
		startEnabled = startEnabled and true or false,
		negativeModifiers = negativeModifiers or {},
		positiveModifiers = positiveModifiers or {}
	})
end

function init()
	g_ui.importStyle("game_bossdifficulty")
	connect(g_game, {
		onGameEnd = destroyDialog,
		onBossDifficultySelection = onEngineBossDifficultySelection,
		onBossDifficultyClose = onBossDifficultyClose,
		onBossDifficultyUpdate = onBossDifficultyUpdate
	})
end

function terminate()
	disconnect(g_game, {
		onGameEnd = destroyDialog,
		onBossDifficultySelection = onEngineBossDifficultySelection,
		onBossDifficultyClose = onBossDifficultyClose,
		onBossDifficultyUpdate = onBossDifficultyUpdate
	})
	destroyDialog()
end
