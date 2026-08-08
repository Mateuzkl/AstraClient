---------------------------
-- Lua code author: R1ck --
-- Company: VICTOR HUGO PERENHA - JOGOS ON LINE --
---------------------------

Bosstiary = {}
Bosstiary.__index = Bosstiary

-- Global fields
baseKillData = {}
baseRewardData = {}

CATEGORY_BANE = 1
CATEGORY_ARCHFOE = 2
CATEGORY_NEMESIS = 3

local bosstiaryCreatures = {}
local bosstiaryCurrentPage = 1

local sortFields = {}

local redirectText = nil

local bosstiaryMonsterPanel = nil
local pageCounter = nil
local previousButton = nil
local nextButton = nil
local searchField = nil
local rawBosstiaryData = nil
local windowDataGeneration = 0
local creatureRenderGeneration = 0
local windowDataEvent = nil
local creatureRenderEvent = nil

function Bosstiary.cancelPendingEvents()
	windowDataGeneration = windowDataGeneration + 1
	creatureRenderGeneration = creatureRenderGeneration + 1
	if windowDataEvent then
		removeEvent(windowDataEvent)
		windowDataEvent = nil
	end
	if creatureRenderEvent then
		removeEvent(creatureRenderEvent)
		creatureRenderEvent = nil
	end
end

local sortTypes = {
	[1] = {name = "Bane", icon = "/game_cyclopedia/images/icons/icon-bosstiary-1"},
	[2] = {name = "Archfoe", icon = "/game_cyclopedia/images/icons/icon-bosstiary-2"},
	[3] = {name = "Nemesis", icon = "/game_cyclopedia/images/icons/icon-bosstiary-3"},
	[4] = {name = ""}, -- mmm
	[5] = {name = ""},	-- mmm
	[6] = {name = "No Kills"},
	[7] = {name = "Few Kills"},
	[8] = {name = "Prowess"},
	[9] = {name = "Expertise"},
	[10] = {name = "Mastery"}
}

BosstiaryReward = {
	[CATEGORY_BANE] = {
		prowess = 5,
		expertise = 15,
		mastery = 30
	},
	[CATEGORY_ARCHFOE] = {
		prowess = 10,
		expertise = 30,
		mastery = 60
	},
	[CATEGORY_NEMESIS] = {
		prowess = 10,
		expertise = 30,
		mastery = 60
	}
}

toolMessages = {
	[1] = "Bane\n\nFor unlocking a level, you will receive the following boss points:\nProwess: %s\nExpertise: %s\nMastery: %s",
	[2] = "Archfoe\n\nFor unlocking a level, you will receive the following boss points:\nProwess: %s\nExpertise: %s\nMastery: %s",
	[3] = "Nemesis\n\nFor unlocking a level, you will receive the following boss points:\nProwess: %s\nExpertise: %s\nMastery: %s",
}

function Bosstiary.reset()
	Bosstiary.cancelPendingEvents()
	sortFields = {}
	bosstiaryCreatures = {}
	bosstiaryCurrentPage = 1
	rawBosstiaryData = nil
end

function Bosstiary.onSideButtonRedirect(text)
	if text ~= nil then
		redirectText = text
	end

	Cyclopedia.open()
	onOptionChange(cyclopediaOptionsPanel:recursiveGetChildById('7'))
end

function Bosstiary.configureBossList(data, text)
	-- reset envoriment
	bosstiaryCreatures = {}
	if type(data) ~= 'table' then
		data = {}
	end

	local monsterList = g_things.getMonsterList()

	-- Insert outfit
	for _, v in pairs(data) do
		v[5] = v[5] or getCyclopediaMonster(v[1]) or monsterList[v[1]] or {}
	end

	table.sort(data, function(a, b)
		local aKills = a[3]
		local bKills = b[3]

		if aKills == 0 and bKills > 0 then
			return false
		elseif aKills > 0 and bKills == 0 then
			return true
		elseif aKills == 0 and bKills == 0 then
			return false
		end
		return tostring((a[5] or {})[1] or '') < tostring((b[5] or {})[1] or '')
	end)

	local tmpPage = 1
	local pageEntries = 0
	for _, v in pairs(data) do
		local _bossID = v[1]
		local _category = v[2]
		local _kills = v[3]
		local _isTracked = v[4]
		local _outfit = v[5]
		if not _outfit then
			goto continue
		end

		if text and #text > 0 then
			if not matchText(text, _outfit[1]) or _kills == 0 then
				goto continue
			end
		end

		-- Sort types
		for i, active in pairs(sortFields) do
			if not active then
				if (i == (_category + 1)) or (i == 6 and _kills == 0) then
					goto continue
				end

				local baseKill = baseKillData[_category + 1]
				if i == 7 and _kills > 0 and _kills < baseKill.firstUnlock then
					goto continue
				end

				if (i == 8 and _kills > 0 and _kills >= baseKill.firstUnlock and _kills < baseKill.secondUnlock) then
					goto continue
				end

				if (i == 9 and _kills > 0 and _kills >= baseKill.secondUnlock and _kills < baseKill.thirdUnlock) or (i == 10 and _kills >= baseKill.thirdUnlock) then
					goto continue
				end
			end
		end

		if pageEntries >= 8 then
			tmpPage = tmpPage + 1
			pageEntries = 0
		end

		if bosstiaryCreatures[tmpPage] == nil then
			bosstiaryCreatures[tmpPage] = {}
		end

		pageEntries = pageEntries + 1
		table.insert(bosstiaryCreatures[tmpPage], {bossID = _bossID, category = _category, kills = _kills, isTracked = _isTracked, outfit = _outfit})
		::continue::
	end
end

function Bosstiary.requestData()
	g_game.openBosstiaryWindow()
end

function Bosstiary.onBosstiaryBaseData(killData, rewardData)
	for i = 1, #killData do
		baseKillData[i] = {firstUnlock = killData[i][1], secondUnlock = killData[i][2], thirdUnlock = killData[i][3]}
	end

	for i = 1, #rewardData do
		baseRewardData[i] = {firstUnlock = rewardData[i][1], secondUnlock = rewardData[i][2], thirdUnlock = rewardData[i][3]}
	end
end

function Bosstiary.onBosstiaryWindowData(data)
	windowDataGeneration = windowDataGeneration + 1
	local generation = windowDataGeneration
	local alreadyOpened = rawBosstiaryData ~= nil
	creatureRenderGeneration = creatureRenderGeneration + 1
	rawBosstiaryData = data
	if not alreadyOpened then
		sortFields = {}
	end

	if windowDataEvent then
		removeEvent(windowDataEvent)
	end
	windowDataEvent = scheduleEvent(function()
		windowDataEvent = nil
		if generation ~= windowDataGeneration then
			return
		end

		local panel = VisibleCyclopediaPanel
		if not panel or panel:isDestroyed() then
			Bosstiary.updateTracker()
			return
		end

		bosstiaryMonsterPanel = panel:recursiveGetChildById('bosstiaryMonsterPanel')
		pageCounter = panel:recursiveGetChildById('pageCount')
		previousButton = panel:recursiveGetChildById('backListButton')
		nextButton = panel:recursiveGetChildById('nextListButton')
		searchField = panel:recursiveGetChildById('searchBosstiary')
		if not bosstiaryMonsterPanel or not pageCounter or not previousButton or not nextButton then
			Bosstiary.updateTracker()
			return
		end

		if alreadyOpened then
			local activeSearch = searchField and searchField:getText() or nil
			Bosstiary.configureBossList(rawBosstiaryData, activeSearch)
			bosstiaryCurrentPage = math.max(1, math.min(bosstiaryCurrentPage, #bosstiaryCreatures))
			Bosstiary.showCreatures()
			Bosstiary.updateTracker()
			return
		end

		Bosstiary.initSortFields()
		if redirectText ~= nil then
			Bosstiary.onSearch(redirectText)
			redirectText = nil
		else
			Bosstiary.configureBossList(rawBosstiaryData)
			Bosstiary.showCreatures()
		end

		if cyclopediaWindow then
			cyclopediaWindow.optionsPanel:focus()
		end
		panel:focus()
		if searchField then
			searchField:focus()
		end
		Bosstiary.updateTracker()
	end, 1)
end

function Bosstiary.updateTracker()
	if not rawBosstiaryData then
		return
	end

	local trackerList = {}
	for _, v in ipairs(rawBosstiaryData) do
		local bossID = v[1]
		local category = v[2]
		local kills = v[3]
		local isTracked = v[4]
		if isTracked == 1 then
			local baseKill = baseKillData[category + 1]
			if baseKill then
				table.insert(trackerList, {bossID, kills, baseKill.firstUnlock, baseKill.secondUnlock, baseKill.thirdUnlock})
			end
		end
	end

	if modules.game_trackers then
		modules.game_trackers.BossTrackerList = trackerList
		modules.game_trackers.BossTracker.showTrackerData()
	end
end

function Bosstiary.showBosstiaryPage(index)
	bosstiaryCurrentPage = index > 0 and bosstiaryCurrentPage + 1 or bosstiaryCurrentPage - 1
	Bosstiary.configureBossList(rawBosstiaryData)
	Bosstiary.showCreatures()
end

function Bosstiary.initSortFields()
	local panel = VisibleCyclopediaPanel or cyclopediaWindow or g_ui.getRootWidget()
	local inforBox = panel:recursiveGetChildById('infoCheckBox')
  if not inforBox then
    return
  end

	inforBox:destroyChildren()
	for k, data in ipairs(sortTypes) do
		local infor = g_ui.createWidget('MarkCheckPanel', inforBox)
		infor:setId(k)
		infor.checkMarks:setText(data.name)
		infor.checkMarks:setTextOffset("15 -2")
		infor.checkMarks:setChangeCursorImage(false)
		infor.checkMarks:setChecked(true)
		infor.checkMarks.onCheckChange = Bosstiary.onBosstiryFilterCheck
		infor.checkMarks:setActionId(k)
		if #data.name == 0 then
		  infor.checkMarks:enable(false)
		  infor.checkMarks:setImageSource("")
		end

		if data.icon then
			infor.checkMarks:setIcon(data.icon)
			infor.checkMarks:setTextOffset("29 -2")
			infor.checkMarks:setIconOffset(k == 1 and "-10 0" or "-22 0")
		end
	end
end

local function createCreatureCard(data)
	local monsters = g_ui.createWidget('CyclopediaBosstiaryWindow', bosstiaryMonsterPanel)
	local unlocked = data.kills > 0
	if data.outfit then
		local name = unlocked and string.capitalize(data.outfit[1]) or "?"
		monsters:setText(short_text(name, 17))
		if #name > 17 then
			monsters.monster.outfit:setTooltip(name)
		end

		if unlocked then
			monsters.trackBosstiary:enable()
		else
			monsters.trackBosstiary:disable()
		end

		local hasLookType = data.outfit[2] > 0
		local hasLookTypeEx = data.outfit[3] > 0
		local monsterShader = (unlocked and (hasLookType or hasLookTypeEx) and "" or "outfit_black")
		monsters.monster.outfit:setOutfit({type = data.outfit[2], auxType = data.outfit[3], head = data.outfit[4], body = data.outfit[5], legs = data.outfit[6], feet = data.outfit[7], addons = data.outfit[8], shader = monsterShader})
		monsters.monster.outfit:setRaceID(data.bossID)
		monsters:setId(data.bossID)
	end

	local baseKill = baseKillData[data.category + 1]
	if not baseKill then
		monsters:destroy()
		return
	end
	monsters.progressFirst.first:setPercent(0)
	monsters.progressSecond.second:setPercent(0)
	monsters.progressThird.third:setPercent(0)

	monsters.progressFirst.first:setTooltip(data.kills .. " / " .. baseKill.firstUnlock)
	monsters.progressSecond.second:setTooltip(data.kills .. " / " .. baseKill.secondUnlock)
	monsters.progressThird.third:setTooltip(data.kills .. " / " .. baseKill.thirdUnlock)

	if data.isTracked == 1 then
		monsters.trackBosstiary:setChecked(true)
	end
	monsters.trackBosstiary.onCheckChange = Bosstiary.checkBosstiaryTrack

	local currentKills = data.kills
	local firstPercent = math.min((currentKills * 100) / math.max(baseKill.firstUnlock, 1), 100)
	monsters.progressFirst.first:setPercent(firstPercent)
	if currentKills >= baseKill.firstUnlock then
		monsters.starFisrt:setImageSource("/game_cyclopedia/images/icons/star/enable1")
		local secondRange = math.max(baseKill.secondUnlock - baseKill.firstUnlock, 1)
		local secondPercent = math.min(((currentKills - baseKill.firstUnlock) * 100) / secondRange, 100)
		monsters.progressSecond.second:setPercent(secondPercent)
	end

	if currentKills >= baseKill.secondUnlock then
		monsters.starSecond:setImageSource("/game_cyclopedia/images/icons/star/enable2")
		local thirdRange = math.max(baseKill.thirdUnlock - baseKill.secondUnlock, 1)
		local thirdPercent = math.min(((currentKills - baseKill.secondUnlock) * 100) / thirdRange, 100)
		monsters.progressThird.third:setPercent(thirdPercent)
	end

	if currentKills >= baseKill.thirdUnlock then
		monsters.progressFirst.first:setImageSource('/game_cyclopedia/images/ui/monster-bar-green')
		monsters.progressSecond.second:setImageSource('/game_cyclopedia/images/ui/monster-bar-green')
		monsters.progressThird.third:setImageSource('/game_cyclopedia/images/ui/monster-bar-green')
		monsters.starThird:setImageSource("/game_cyclopedia/images/icons/star/enable3")
	end

	local category = data.category + 1
	monsters.monster.outfit:setAnimate(true)
	monsters.progressSecond.second.killCounterLabel:setText(data.kills)
	monsters.iconBosstiary:setImageSource('/game_cyclopedia/images/icons/icon-bosstiary-' .. category)
	monsters.iconBosstiary:setTooltip(tr(toolMessages[category], BosstiaryReward[category].prowess, BosstiaryReward[category].expertise, BosstiaryReward[category].mastery))
end

function Bosstiary.showCreatures()
	if not bosstiaryMonsterPanel then
		return true
	end
	creatureRenderGeneration = creatureRenderGeneration + 1
	local generation = creatureRenderGeneration
	if creatureRenderEvent then
		removeEvent(creatureRenderEvent)
		creatureRenderEvent = nil
	end

	bosstiaryMonsterPanel:destroyChildren()
	pageCounter:setText(bosstiaryCurrentPage .. " / " .. #bosstiaryCreatures)
	if not bosstiaryCreatures or #bosstiaryCreatures == 1 or #bosstiaryCreatures == 0 then
		nextButton:setEnabled(false)
		previousButton:setEnabled(false)
		pageCounter:setText("1 / 1")
		if not bosstiaryCreatures or #bosstiaryCreatures == 0 then
			return
		end
	end

	previousButton:setEnabled(false)
	nextButton:setEnabled(false)

	if bosstiaryCurrentPage == 1 and #bosstiaryCreatures > 1 then
		previousButton:setEnabled(false)
		nextButton:setEnabled(true)
	elseif bosstiaryCurrentPage > 1 and bosstiaryCurrentPage < #bosstiaryCreatures then
		previousButton:setEnabled(true)
		nextButton:setEnabled(true)
	elseif bosstiaryCurrentPage == #bosstiaryCreatures then
		if #bosstiaryCreatures > 1 then
			previousButton:setEnabled(true)
		end
		nextButton:setEnabled(false)
	end

	local pageEntries = bosstiaryCreatures[bosstiaryCurrentPage] or {}
	local index = 1
	local function renderNextBatch()
		creatureRenderEvent = nil
		if generation ~= creatureRenderGeneration then
			return
		end
		local lastIndex = math.min(index + 1, #pageEntries)
		while index <= lastIndex do
			createCreatureCard(pageEntries[index])
			index = index + 1
		end
		if index <= #pageEntries then
			creatureRenderEvent = scheduleEvent(renderNextBatch, 1)
		end
	end
	if #pageEntries > 0 then
		creatureRenderEvent = scheduleEvent(renderNextBatch, 1)
	end
end

function Bosstiary.clearSearch(button)
	if button and #searchField:getText() == 0 then
		return
	end

	searchField:setText("")
	bosstiaryCurrentPage = 1
	bosstiaryCreatures = {}
	Bosstiary.configureBossList(rawBosstiaryData)
	Bosstiary.showCreatures()
end

function Bosstiary.onSearchChange(widget)
	if #widget:getText() == 0 then
		Bosstiary.clearSearch(false)
		return
	end

	bosstiaryCurrentPage = 1
	bosstiaryCreatures = {}
	Bosstiary.configureBossList(rawBosstiaryData, widget:getText())
	Bosstiary.showCreatures()
end

function Bosstiary.onSearch(text)
	searchField = g_ui.getRootWidget():recursiveGetChildById('searchBosstiary')

	if #text == 0 then
		Bosstiary.clearSearch(false)
		return
	end

	if searchField then
		searchField:setText(text)
	end
	bosstiaryCurrentPage = 1
	bosstiaryCreatures = {}
	Bosstiary.configureBossList(rawBosstiaryData, text)
	Bosstiary.showCreatures()
end

function Bosstiary.onBosstiryFilterCheck(widget, checked)
	sortFields[widget:getActionId()] = checked
	bosstiaryCurrentPage = 1
	bosstiaryCreatures = {}
	Bosstiary.configureBossList(rawBosstiaryData)
	Bosstiary.showCreatures()
end

function Bosstiary.checkBosstiaryTrack(widget, checked, monsterId)
  if monsterId == nil then
    g_game.sendBosstiaryTracker(widget:getParent().monster.outfit:getRaceID(), widget:isChecked())
  else
    g_game.sendBosstiaryTracker(monsterId, checked)
  end
end
