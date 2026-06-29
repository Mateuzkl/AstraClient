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

-- configureBossList re-attaches outfits and re-sorts the whole dataset on every
-- call (each keystroke / page change / filter toggle). The outfit attach and the
-- sort order depend only on the dataset (text only filters afterwards), so do them
-- ONCE per dataset: remember the table we already prepared and skip the rework when
-- called again with the same table. A fresh server payload is a new table identity
-- (rawBosstiaryData is reassigned on each 0x73/window-data push), so this re-prepares
-- automatically. table.sort is in place, so the prepared identity is preserved.
local lastSortedData = nil

-- Debounce for the search box so rapid keystrokes coalesce into one rebuild.
local searchDebounceEvent = nil
local SEARCH_DEBOUNCE_MS = 100

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
	sortFields = {}
	bosstiaryCreatures = {}
	bosstiaryCurrentPage = 1
	rawBosstiaryData = nil
	lastSortedData = nil
	if searchDebounceEvent then
		removeEvent(searchDebounceEvent)
		searchDebounceEvent = nil
	end
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

	-- Attach outfits + sort once per dataset (text-independent); reuse on re-search.
	if lastSortedData ~= data then
		local monsterList = getMonsterList()

		-- Insert outfit
		for _, v in pairs(data) do
			-- keep nil for bosses missing from staticdata so the guard below skips them
			v[5] = monsterList[v[1]]
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

		lastSortedData = data
	end

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

-- The 0x73 bosstiary-list resend is reliable (the server always emits it on a
-- boss-track toggle, before the droppable 0xB9 push). Rebuild the boss tracker
-- list from it so marking/unmarking a boss refreshes the tracker window even
-- when the 0xB9 push is dropped server-side (malformed kill stages early-return).
function Bosstiary.rebuildBossTrackerFromList(data)
	if type(data) ~= 'table' then
		return
	end
	-- bossTrackerWindow and BossTrackerList are globals in the SEPARATE
	-- game_trackers sandbox; they do not resolve from this (game_cyclopedia)
	-- sandbox. Reach them through the module registry (modules.game_trackers IS
	-- the game_trackers sandbox env, so the field write below is visible to its
	-- consumers, e.g. BossTracker.showTrackerData reading bare BossTrackerList).
	local trackers = modules.game_trackers
	if not trackers or not trackers.bossTrackerWindow then
		return
	end

	local list = {}
	for _, v in pairs(data) do
		-- v = {bossId, category (0-based), kills, tracked}. The server tracked
		-- flag (v[4]) is authoritative. NEVER drop a tracked boss for a missing
		-- baseKill (0x61 base data may not have populated yet) — fall back to
		-- zero unlock thresholds so opening the panel never wipes the tracker.
		if v[4] == 1 then
			local baseKill = baseKillData[v[2] + 1] or {}
			list[#list + 1] = { v[1], v[3], baseKill.firstUnlock or 0, baseKill.secondUnlock or 0, baseKill.thirdUnlock or 0 }
		end
	end

	trackers.BossTrackerList = list
	trackers.BossTracker.showTrackerData()
end

function Bosstiary.onBosstiaryWindowData(data)
	-- data is the authoritative tracked set; refresh the boss tracker from it
	-- regardless of which branch below stores rawBosstiaryData.
	Bosstiary.rebuildBossTrackerFromList(data)

	-- Init fields
	bosstiaryMonsterPanel = g_ui.getRootWidget():recursiveGetChildById('bosstiaryMonsterPanel')
	pageCounter = g_ui.getRootWidget():recursiveGetChildById('pageCount')
	previousButton = g_ui.getRootWidget():recursiveGetChildById('backListButton')
	nextButton = g_ui.getRootWidget():recursiveGetChildById('nextListButton')
	searchField = g_ui.getRootWidget():recursiveGetChildById('searchBosstiary')
	if rawBosstiaryData then
		-- already opened
		rawBosstiaryData = data
		return
	end

	rawBosstiaryData = data
	sortFields = {}

	Bosstiary.initSortFields()
	if redirectText ~= nil then
		Bosstiary.onSearch(redirectText)
		redirectText = nil
	else
		Bosstiary.configureBossList(rawBosstiaryData)
		Bosstiary.showCreatures()
	end

	cyclopediaWindow.optionsPanel:focus()
	if VisibleCyclopediaPanel then
    	VisibleCyclopediaPanel:focus()
	end

	if searchField then
		searchField:focus()
	end
end

function Bosstiary.showBosstiaryPage(index)
	bosstiaryCurrentPage = index > 0 and bosstiaryCurrentPage + 1 or bosstiaryCurrentPage - 1
	Bosstiary.configureBossList(rawBosstiaryData)
	Bosstiary.showCreatures()
end

function Bosstiary.initSortFields()
	local inforBox = g_ui.getRootWidget():recursiveGetChildById('infoCheckBox')
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

function Bosstiary.showCreatures()
  if not bosstiaryMonsterPanel then
    return true
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

	for _, data in pairs(bosstiaryCreatures[bosstiaryCurrentPage]) do
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
		local firstPercent = math.min((currentKills * 100) / baseKill.firstUnlock, 100)
		monsters.progressFirst.first:setPercent(firstPercent)
		if currentKills >= baseKill.firstUnlock then
			monsters.starFisrt:setImageSource("/game_cyclopedia/images/icons/star/enable1")
			local secondPercent = math.min(((currentKills - baseKill.firstUnlock) * 100) / (baseKill.secondUnlock - baseKill.firstUnlock), 100)
			monsters.progressSecond.second:setPercent(secondPercent)
		end

		if currentKills >= baseKill.secondUnlock then
			monsters.starSecond:setImageSource("/game_cyclopedia/images/icons/star/enable2")
			local thirdPercent = math.min(((currentKills - baseKill.secondUnlock) * 100) / (baseKill.thirdUnlock - baseKill.secondUnlock), 100)
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
		monsters.iconBosstiary:setImageSource('/game_cyclopedia/images/icons/icon-bosstiary-' .. data.category + 1)
		monsters.iconBosstiary:setTooltip(tr(toolMessages[category], BosstiaryReward[category].prowess, BosstiaryReward[category].expertise, BosstiaryReward[category].mastery))
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
	-- Debounce: coalesce rapid keystrokes into a single rebuild. The deferred body
	-- re-reads the live text, so the final result matches the latest input.
	if searchDebounceEvent then
		removeEvent(searchDebounceEvent)
		searchDebounceEvent = nil
	end

	searchDebounceEvent = scheduleEvent(function()
		searchDebounceEvent = nil
		local text = widget:getText()
		if #text == 0 then
			Bosstiary.clearSearch(false)
			return
		end

		bosstiaryCurrentPage = 1
		bosstiaryCreatures = {}
		Bosstiary.configureBossList(rawBosstiaryData, text)
		Bosstiary.showCreatures()
	end, SEARCH_DEBOUNCE_MS)
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
    g_game.sendMonsterTracker(widget:getParent().monster.outfit:getRaceID(), widget:isChecked())
  else
    g_game.sendMonsterTracker(monsterId, checked)
  end
end
