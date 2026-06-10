local registredOpcodes = nil

local ServerPackets = {
	DailyRewardCollectionState = 0xDE,
	OpenRewardWall = 0xE2,
	CloseRewardWall = 0xE3,
	DailyRewardBasic = 0xE4,
	DailyRewardHistory = 0xE5,
	RestingAreaState = 0xA9,
	BestiaryData = 0xd5,
	BestiaryOverview = 0xd6,
	BestiaryMonsterData = 0xd7,
	BestiaryCharmsData = 0xd8,
	BestiaryTracker = 0xd9,
	BestiaryTrackerTab = 0xB9,
	OpenStashSupply = 0x29,
	UpdateLootTracker = 0xCF,
	UpdateTrackerAnalyzer = 0xCC,
	UpdateSupplyTracker = 0xCE,
	KillTracker = 0xD1,
	SpecialContainer = 0x2A,
	isUpdateCoinBalance = 0xF2,
	UpdateCoinBalance = 0xDF,
	PartyAnalyzer = 0x2B,
	GameNews = 0x98,
	ClientCheck = 0x63,
	LootStats = 0xCF,
	LootContainer = 0xC0,
	TournamentLeaderBoard = 0xC5,
	CyclopediaCharacterInfo = 0xDA,
	Tutorial = 0xDC,
	Highscores = 0xB1,
	Inspection = 0x76,
	TeamFinderList = 0x2D,
	TeamFinderLeader = 0x2C,
	ItemValues = 0xC6,
	ItemDetails = 0xC7
}

local ClientPackets = {
  OpenRewardWall = 0xB4,
  OpenRewardHistory = 0xB5,
  SelectReward = 0xB6,
  Highscores = 0xB1
}

-- Server Types
local DAILY_REWARD_TYPE_ITEM = 1
local DAILY_REWARD_TYPE_STORAGE = 2
local DAILY_REWARD_TYPE_PREY_REROLL = 3
local DAILY_REWARD_TYPE_XP_BOOST = 4

-- Client Types
local DAILY_REWARD_SYSTEM_SKIP = 1
local DAILY_REWARD_SYSTEM_TYPE_ONE = 1
local DAILY_REWARD_SYSTEM_TYPE_TWO = 2
local DAILY_REWARD_SYSTEM_TYPE_OTHER = 1
local DAILY_REWARD_SYSTEM_TYPE_PREY_REROLL = 2
local DAILY_REWARD_SYSTEM_TYPE_XP_BOOST = 3

local function sendDailyRewardPacket(opcode, writer)
  local protocolGame = g_game.getProtocolGame()
  if not protocolGame then
    return false
  end

  local msg = OutputMessage.create()
  msg:addU8(opcode)
  if writer then
    writer(msg)
  end
  protocolGame:send(msg)
  return true
end

function g_game.openDailyReward()
  return sendDailyRewardPacket(ClientPackets.OpenRewardWall)
end

function g_game.dailyRewardHistory()
  return sendDailyRewardPacket(ClientPackets.OpenRewardHistory)
end

function g_game.dailyRewardConfirm(fromShrine, items)
  return sendDailyRewardPacket(ClientPackets.SelectReward, function(msg)
    msg:addU8(fromShrine and 1 or 0)

    local selectedItems = {}
    for itemId, count in pairs(items or {}) do
      itemId = tonumber(itemId)
      count = tonumber(count)
      if itemId and itemId > 0 and count and count > 0 then
        selectedItems[#selectedItems + 1] = { itemId = itemId, count = math.min(count, 0xFF) }
      end
    end

    table.sort(selectedItems, function(a, b) return a.itemId < b.itemId end)
    msg:addU8(math.min(#selectedItems, 0xFF))
    for i = 1, math.min(#selectedItems, 0xFF) do
      msg:addU16(selectedItems[i].itemId)
      msg:addU8(selectedItems[i].count)
    end
  end)
end

function g_game.highscore(highscoreType, category, vocation, worldName, page, entriesPerPage)
  local protocolGame = g_game.getProtocolGame()
  if not protocolGame then
    return false
  end

  highscoreType = tonumber(highscoreType) or 0
  category = tonumber(category) or 0
  vocation = tonumber(vocation) or 0xFFFFFFFF
  page = math.max(1, tonumber(page) or 1)
  entriesPerPage = math.max(5, math.min(30, tonumber(entriesPerPage) or 20))

  local msg = OutputMessage.create()
  msg:addU8(ClientPackets.Highscores)
  msg:addU8(highscoreType)
  msg:addU8(category)
  msg:addU32(vocation)
  msg:addString(worldName or "")
  msg:addU8(0)
  msg:addU8(0)

  if highscoreType == 0 then
    msg:addU16(page)
  end

  msg:addU8(entriesPerPage)
  protocolGame:send(msg)
  return true
end

function init()
  connect(g_game, { onEnterGame = registerProtocol,
                    onPendingGame = registerProtocol,
                    onGameStart = registerProtocol,
                    onGameEnd = unregisterProtocol })
  registerProtocol()
end

function terminate()
  disconnect(g_game, { onEnterGame = registerProtocol,
                       onPendingGame = registerProtocol,
                       onGameStart = registerProtocol,
                       onGameEnd = unregisterProtocol })

  unregisterProtocol()
end

function registerProtocol()
  if registredOpcodes ~= nil then
    return
  end

  registredOpcodes = {}

  registerOpcode(ServerPackets.ItemValues, function(protocol, msg)
	local size = msg:getU16()
	for i = 1, size do
		local itemId = msg:getU16()
		local value = msg:getU32()
		if ItemsDatabase and ItemsDatabase.registerServerItemValue then
			ItemsDatabase.registerServerItemValue(itemId, value)
		end
	end
  end)

  registerOpcode(ServerPackets.ItemDetails, function(protocol, msg)
	local itemId = msg:getU16()
	local defaultValue = msg:getU32()
	local defaultBuyPrice = msg:getU32()
	local averageMarketValue = msg:getU32()
	local descriptions = {}
	local descriptionCount = msg:getU8()
	for i = 1, descriptionCount do
		descriptions[#descriptions + 1] = {
			detail = msg:getString(),
			description = msg:getString()
		}
	end

	local npcSaleData = {}
	local npcCount = msg:getU16()
	for i = 1, npcCount do
		npcSaleData[#npcSaleData + 1] = {
			name = msg:getString(),
			location = msg:getString(),
			buyPrice = msg:getU32(),
			salePrice = msg:getU32(),
			currencyQuestFlagDisplayName = msg:getString()
		}
	end

	if ItemsDatabase and ItemsDatabase.registerServerItemDetails then
		ItemsDatabase.registerServerItemDetails(itemId, {
			defaultValue = defaultValue,
			defaultBuyPrice = defaultBuyPrice,
			averageMarketValue = averageMarketValue,
			description = descriptions[1] and descriptions[1].description or "",
			descriptions = descriptions,
			npcSaleData = npcSaleData
		})
	end
	signalcall(g_game.onItemDetails, itemId)
  end)

  registerOpcode(ServerPackets.OpenRewardWall, function(protocol, msg)
    local fromShrine = msg:getU8() ~= 0
    local nextRewardTime = msg:getU32()
    local currentIndex = msg:getU8()
    local taken = msg:getU8() ~= 0
    local message = ''
    local dailyState = 2
    local jokerToken = 0
    local serverSave = 0

    if taken then
      dailyState = 0
      message = msg:getString()
      if msg:getU8() ~= 0 then
        jokerToken = msg:getU16()
      end
    else
      dailyState = msg:getU8()
      serverSave = msg:getU32()
      jokerToken = msg:getU16()
    end

    local dayStreakLevel = msg:getU16()
    signalcall(g_game.onOpenRewardWall, fromShrine, nextRewardTime, currentIndex, message, dailyState, jokerToken, serverSave, dayStreakLevel)
  end)

  registerOpcode(ServerPackets.CloseRewardWall, function(protocol, msg)

  end)

  registerOpcode(ServerPackets.DailyRewardBasic, function(protocol, msg)
    local count = msg:getU8()
    local freeRewards = {}
    local premiumRewards = {}
    for i = 1, count do
      freeRewards[i] = readDailyReward(msg)
      premiumRewards[i] = readDailyReward(msg)
    end

    local descriptions = {}
    local maxBonus = msg:getU8()
    for i = 1, maxBonus do
      descriptions[i] = msg:getString()
      msg:getU8()
    end
    msg:getU8()
    signalcall(g_game.onDailyReward, freeRewards, premiumRewards, descriptions)
  end)

  registerOpcode(ServerPackets.DailyRewardHistory, function(protocol, msg)
    local count = msg:getU8()
    local history = {}
    for i=1,count do
      history[i] = {
        msg:getU32(),
        msg:getU8(),
        msg:getString(),
        msg:getU16()
      }
    end
    signalcall(g_game.onDailyRewardHistory, history)
  end)

  registerOpcode(ServerPackets.Highscores, function(protocol, msg)
    local status = msg:getU8()
    if status ~= 0 then
      signalcall(g_game.onHighscores, {}, "All Game Worlds", {[0xFFFFFFFF] = "(all)"}, 0xFFFFFFFF, {[0] = "Experience Points"}, 0, 1, 1, {}, os.time())
      return
    end

    local worlds = {}
    local worldCount = msg:getU8()
    for i = 1, worldCount do
      worlds[i] = msg:getString()
    end

    local selectedWorld = msg:getString()
    msg:getU8() -- Game world category
    msg:getU8() -- BattlEye world type

    local vocations = {}
    local vocationCount = msg:getU8()
    for _ = 1, vocationCount do
      local vocationId = msg:getU32()
      vocations[vocationId] = msg:getString()
    end

    local selectedVocation = msg:getU32()
    local categories = {}
    local categoryCount = msg:getU8()
    for _ = 1, categoryCount do
      local categoryId = msg:getU8()
      categories[categoryId] = msg:getString()
    end

    local selectedCategory = msg:getU8()
    local page = msg:getU16()
    local pages = msg:getU16()
    local characters = {}
    local characterCount = msg:getU8()
    for i = 1, characterCount do
      local rank = msg:getU32()
      local name = msg:getString()
      local title = msg:getString()
      local vocationId = msg:getU8()
      local world = msg:getString()
      local level = msg:getU16()
      local isPlayer = msg:getU8() ~= 0
      local points = msg:getU64()
      characters[i] = {rank, name, vocationId, world, level, isPlayer, points, title}
    end

    msg:getU8()
    msg:getU8()
    msg:getU8()
    local lastUpdate = msg:getU32()
    signalcall(g_game.onHighscores, worlds, selectedWorld, vocations, selectedVocation, categories, selectedCategory, page, pages, characters, lastUpdate)
  end)

  if not g_game.getFeature(GameTibia12Protocol) then
    return
  end

  registerOpcode(ServerPackets.TeamFinderLeader, function(protocol, msg)
	local bool = msg:getU8() -- reset
	if bool > 0 then
		return -- Server internal changes
	end

	msg:getU16() -- Min level
	msg:getU16() -- Max level
	msg:getU8() -- Vocation flag
	msg:getU16() -- Slots
	msg:getU16() -- Free slots
	msg:getU32() -- Timestamp
	local type = msg:getU8() -- Team type
	msg:getU16() -- Type flag
	if type == 2 then
		msg:getU16() -- Hunt area
	end

	local size = msg:getU16() -- Members size
	for i = 1, size do
		msg:getU32() -- Character id
		msg:getString() -- Character name
		msg:getU16() -- Character level
		msg:getU8() -- Vocation
		msg:getU8() -- Member type (Leader == 3)
	end
  end)

  registerOpcode(ServerPackets.TeamFinderList, function(protocol, msg)
	msg:getU8()
	local size = msg:getU32() -- List size
	for i = 1, size do
		msg:getU32() -- Leader Id
		msg:addString() -- Leader name
		msg:getU16() -- Min level
		msg:getU16() -- Max level
		msg:getU8() -- Vocations flag
		msg:getU16() -- Slots
		msg:getU16() -- Used slots
		msg:getU32() -- Timestamp
		local type = msg:getU8() -- Team type [1]: Boss, [2]: Hunt and [3]: Quest
		msg:getU16() -- Type flag
		if type == 2 then
			msg:getU16() -- Hunt area
		end
		msg:getU8() -- Player status
	end
  end)

  registerOpcode(ServerPackets.Inspection, function(protocol, msg)
	local bool = msg:getU8() -- IsPlayer
	if g_game.getProtocolVersion() >= 1230 then
		msg:getU8()
	end
	local size = msg:getU8() -- List
	for i = 1, size do
		if bool > 0 then
			msg:getU8()
		end
		msg:getString() -- Name
		readAddItem(msg)
		local size_2 = msg:getU8() -- Imbuements
		for u = 1, size_2 do
			msg:getU16() -- Imbue
		end
		local size_3 = msg:getU8() -- Details
		for j = 1, size_3 do
			msg:getString() -- Name
			msg:getString() -- Description
		end
	end

	if bool > 0 then
		msg:getString() -- Player name
		local outfit = msg:getU16() -- lookType
		if outfit ~= 0 then
			msg:getU8() -- lookHead
			msg:getU8() -- lookBody
			msg:getU8() -- lookLegs
			msg:getU8() -- lookFeet
			msg:getU8() -- lookAddons
		else
			msg:getU16() -- lookTypeEx
		end
		local size_4 = msg:getU8() -- Detail
		for l = 1, size_4 do
			msg:getString() -- Name
			msg:getString() -- Description
		end
	end
  end)



  registerOpcode(ServerPackets.Tutorial, function(protocol, msg)
	msg:getU8() -- Tutorial id
  end)

  registerOpcode(ServerPackets.CyclopediaCharacterInfo, function(protocol, msg)
	local type = msg:getU8()
	if g_game.getProtocolVersion() >= 1215 then
		local error = msg:getU8()
		if error > 0 then
			-- [1] 'No data available at the moment.'
			-- [2] 'You are not allowed to see this character's data.'
			-- [3] 'You are not allowed to inspect this character.'
		end
	end
	if type == 0 then -- Basic Information
		msg:getString() -- Player name
		msg:getString() -- Vocation
		msg:getU16() -- Level
		local outfit = msg:getU16() -- lookType
		if outfit ~= 0 then
			msg:getU8() -- lookHead
			msg:getU8() -- lookBody
			msg:getU8() -- lookLegs
			msg:getU8() -- lookFeet
			msg:getU8() -- lookAddons
		else
			msg:getU16() -- lookTypeEx
		end
		msg:getU8() -- Hide stamina
		if g_game.getProtocolVersion() >= 1220 then
			msg:getU8() -- Personal habs
			msg:getString() -- Title
		end
	elseif type == 1 then -- Character Stats
		msg:getU64() -- Experience
		msg:getU16() -- Level
		msg:getU8() -- LevelPercent
		msg:getU16() -- BaseXpGain
		msg:getU32() -- Tournament
		msg:getU16() -- Grinding
		msg:getU16() -- Store XP
		msg:getU16() -- Hunting
		msg:getU16() -- Store XP Time
		msg:getU8() -- Show store XP button (bool)
		msg:getU16() -- Health
		msg:getU16() -- Health max
		msg:getU16() -- Mana
		msg:getU16() -- Mana max
		msg:getU8() -- Soul
		msg:getU16() -- Stamina
		msg:getU16() -- Food
		msg:getU16() -- Offline training
		msg:getU16() -- Speed
		msg:getU16() -- Speed base
		msg:getU32() -- Capacity bonus
		msg:getU32() -- Capacity
		msg:getU32() -- Capacity max
		local size = msg:getU8() -- Skills
		for i = 1, size do
			msg:getU8() -- Skill id
			msg:getU16() -- Skill level
			msg:getU16() -- Base skill
			msg:getU16() -- Base skill
			msg:getU16() -- Skill percent
		end
		if g_game.getProtocolVersion() < 1215 then
			msg:getU16()
			msg:getString() -- Player name
			msg:getString() -- Vocation
			msg:getU16() -- Level
			local outfit = msg:getU16() -- lookType
			if outfit ~= 0 then
				msg:getU8() -- lookHead
				msg:getU8() -- lookBody
				msg:getU8() -- lookLegs
				msg:getU8() -- lookFeet
				msg:getU8() -- lookAddons
			else
				msg:getU16() -- lookTypeEx
			end
		end
	elseif type == 2 then -- Combat Stats
		msg:getU16() -- Critical chance base
		msg:getU16() -- Critical chance bonus
		msg:getU16() -- Critical damage base
		msg:getU16() -- Critical damage bonus
		msg:getU16() -- Life leech chance base
		msg:getU16() -- Life leech chance bonus
		msg:getU16() -- Life leech amount base
		msg:getU16() -- Life leech amount bonus
		msg:getU16() -- Mana leech chance base
		msg:getU16() -- Mana leech chance bonus
		msg:getU16() -- Mana leech amount base
		msg:getU16() -- Mana leech amount bonus
		msg:getU8() -- Blessing amount
		msg:getU8() -- Blessing max
		msg:getU16() -- Attack
		msg:getU8() -- Attack type
		msg:getU8() -- Convert damage
		msg:getU8() -- Convert damage type
		msg:getU16() -- Armor
		msg:getU16() -- Defense
		local size = msg:getU8() -- Reductions
		for i = 1, size do
			msg:getU8() -- Element
			msg:getU8() -- Percent
		end
	elseif type == 3 then -- Recent Deaths
		msg:getU16() -- Page
		msg:getU16() -- Page max
		local size = msg:getU16()
		for i = 1, size do
			msg:getU32() -- Timestamp
			msg:getString() -- Cause
		end
	elseif type == 4 then -- Recent PvP Kills
		msg:getU16() -- Page
		msg:getU16() -- Page max
		local size = msg:getU16()
		for i = 1, size do
			msg:getU32() -- Timestamp
			msg:getString() -- Description
			msg:getU8() -- Status
		end
	elseif type == 5 then -- Achievements
		msg:getU16() -- Points
		msg:getU16() -- Secret max
		local size = msg:getU16() -- Unlocked
		for i = 1, size do
			msg:getU16() -- Id
			msg:getU32() -- Timestamp
			local size_2 = msg:getU8() -- Is secret
			if size_2 > 0 then
				msg:getString() -- Name
				msg:getString() -- Description
				msg:getU8() -- Grade
			end
		end
	elseif type == 6 then -- Item Summary
		local size = msg:getU16() -- Item list size
		for i = 1, size do
			msg:getU16() -- Item client Id
			msg:getU32() -- Item count
		end
	elseif type == 7 then -- Outfits and Mounts
		local size = msg:getU16() -- Outfit list size
		for i = 1, size do
			msg:getU16() -- Id
			msg:getString() -- Name
			msg:getU8() -- Addon
			msg:getU8() -- Category 0 = Standard, 1 = Quest, 2 = Store
			msg:getU32() -- Is current ? then 1000 or 0
		end
		msg:getU8() -- lookHead
		msg:getU8() -- lookBody
		msg:getU8() -- lookLegs
		msg:getU8() -- lookFeet

		local size_2 = msg:getU16() -- Mount list size
		for u = 1, size_2 do
			msg:getU16() -- Id
			msg:getString() -- Name
			msg:getU8() -- Addon
			msg:getU8() -- Category 0 = Standard, 1 = Quest, 2 = Store
			msg:getU32() -- Is current ? then 1000 or 0
		end
		if g_game.getProtocolVersion() >= 1260 then
			msg:getU8() -- Mount lookHead
			msg:getU8() -- Mount lookBody
			msg:getU8() -- Mount lookLegs
			msg:getU8() -- Mount lookFeet
		end
	elseif type == 8 then -- Store Summary
		msg:getU32() -- Store XP boost time
		msg:getU32() -- Daily reward XP boost time
		local size = msg:getU8() -- Blessings
		for i = 1, size do
			msg:getString() -- Name
			msg:getU8() -- Amount
		end
		msg:getU8() -- Prey slots
		msg:getU8() -- Prey wildcard
		msg:getU8() -- Instant reward
		msg:getU8() -- Charm expansion
		msg:getU8() -- Hireling
		local size_2 = msg:getU8() -- Hireling jogs
		for u = 1, size_2 do
			msg:getU8() -- Job id
		end
		local size_3 = msg:getU8() -- Hireling outfit
		for j = 1, size_3 do
			msg:getU8() -- Outfit id
		end
		msg:getU16() -- House items
	elseif type == 9 then -- Inspect
		local size = msg:getU8() -- Items
		for i = 1, size do
			msg:getU8() -- Slot index
			msg:getString() -- Item name
			readAddItem(msg)
			local size_2 = msg:getU8() -- Imbuements
			for u = 1, size_2 do
				msg:getU16() -- Imbue
			end
			local size_3 = msg:getU8() -- Detail
			for j = 1, size_3 do
				msg:getString() -- Name
				msg:getString() -- Description
			end
		end
		msg:getString() -- Player name
		local outfit = msg:getU16() -- lookType
		if outfit ~= 0 then
			msg:getU8() -- lookHead
			msg:getU8() -- lookBody
			msg:getU8() -- lookLegs
			msg:getU8() -- lookFeet
			msg:getU8() -- lookAddons
		else
			msg:getU16() -- lookTypeEx
		end
		local size_4 = msg:getU8() -- Player detail
		for k = 1, size_4 do
			msg:getString() -- Name
			msg:getString() -- Description
		end
	elseif type == 10 then -- Badges
		local bool = msg:getU8() -- Show account
		if bool > 0 then
			msg:getU8() -- Is online
			msg:getU8() -- Is premium
			msg:getString() -- Loyality title
			local size = msg:getU8() -- Badges
			for i = 1, size do
				msg:getU32() -- Id
				msg:getString() -- Name
			end
		end
	elseif type == 11 then -- Titles
		msg:getU8() -- Title
		local size = msg:getU8() -- Titles
		for i = 1, size do
			msg:getU8() -- Id
			msg:getString() -- Name
			msg:getString() -- Description
			msg:getU8() -- Permanent
			msg:getU8() -- Unlocked
		end
	end
  end)

  registerOpcode(ServerPackets.TournamentLeaderBoard, function(protocol, msg)
	msg:getU16()
	local capacity = msg:getU8() -- Worlds
	for i = 1, capacity do
		msg:getString() -- World name
	end

	msg:getString() -- World selected
	msg:getU16() -- Refresh rate
	msg:getU16() -- Current page
	msg:getU16() -- Total pages
	local size = msg:getU8() -- Players on page
	for u = 1, size do
		msg:getU32() -- Rank
		msg:getU32() -- Previous rank
		msg:getString() -- Name
		msg:getU8() -- Vocation
		msg:getU64() -- Points
		msg:getU8() -- Rank chance direction (arrow0
		msg:getU8() -- Rank chance bool
	end
	msg:getU8()
	msg:getString() -- Rewards
  end)

  registerOpcode(ServerPackets.LootContainer, function(protocol, msg)
	msg:getU8() -- Fallback
	local size = msg:getU8() -- Quickloot size
	for i = 1, size do
		msg:getU8() -- Category Id
		msg:getU16() -- Client Id
	end

	if g_game.getFeature(GameQuickLootFlags) and msg:getUnreadSize() >= 1 then
		local obtainSize = msg:getU8() -- Managed obtain container size
		for i = 1, obtainSize do
			if msg:getUnreadSize() < 3 then
				break
			end
			msg:getU8() -- Category Id
			msg:getU16() -- Client Id
		end
	end
  end)

  registerOpcode(ServerPackets.ClientCheck, function(protocol, msg)
	local size = msg:getU32() -- Data size
	for i = 1, size do
		msg:getU8() -- Data
	end
  end)

  registerOpcode(ServerPackets.GameNews, function(protocol, msg)
	msg:getU32() -- Category
	msg:getU8() -- Page
  end)

  registerOpcode(ServerPackets.PartyAnalyzer, function(protocol, msg)
	local startTime = msg:getU32()
	local leaderID = msg:getU32()
	local lootType = msg:getU8()
	local memberCount = msg:getU8()
	local membersData = {}
	for i = 1, memberCount do
		local playerId = msg:getU32()
		local highlight = msg:getU8()
		local loot = msg:getU64()
		local supplies = msg:getU64()
		local damage = msg:getU64()
		local healing = msg:getU64()
		membersData[playerId] = {
			[1] = loot, [2] = supplies, [3] = damage, [4] = healing, [5] = highlight,
			loot = loot, supplies = supplies, damage = damage, healing = healing,
		}
	end
	msg:getU8() -- online flag
	local nameCount = msg:getU8()
	local membersName = {}
	for u = 1, nameCount do
		local playerId = msg:getU32()
		membersName[playerId] = msg:getString()
	end
	signalcall(g_game.onPartyAnalyzer, startTime, leaderID, lootType, membersData, membersName)
  end)

  registerOpcode(ServerPackets.UpdateCoinBalance, function(protocol, msg)
	msg:getU8() -- Is updating
	msg:getU32() -- Normal coin
	msg:getU32() -- Transferable coin
	if g_game.getProtocolVersion() >= 1220 then
		msg:getU32() -- Reserved auction coin
		msg:getU32() -- Tournament coin
	end
  end)

  registerOpcode(ServerPackets.isUpdateCoinBalance, function(protocol, msg)
	msg:getU8() -- Is updating
  end)

  registerOpcode(ServerPackets.SpecialContainer, function(protocol, msg)
	local supplyStashMenu = msg:getU8() -- ('Stow item', 'Stow container' ...)
	local marketMenu = msg:getU8() -- ('Show in market')
  end)

  registerOpcode(ServerPackets.OpenStashSupply, function(protocol, msg)
    local count = msg:getU16() -- List size
    for i = 1, count do
      msg:getU16() -- Item client ID
      msg:getU32() -- Item count
    end

	msg:getU16() -- Stash size left (total - used)
  end)

  registerOpcode(ServerPackets.BestiaryTrackerTab, function(protocol, msg)
    local count = msg:getU8()
    for i = 1, count do
      msg:getU16()
      msg:getU32()
      msg:getU16()
      msg:getU16()
      msg:getU16()
      msg:getU8()
    end
  end)


end

function readAddItem(msg)
	msg:getU16() -- Item client ID

	if g_game.getProtocolVersion() < 1150 then
		msg:getU8() -- Unmarked
	end

	local var = msg:getU8()
	if g_game.getProtocolVersion() > 1150 then
		if var == 1 then
			msg:getU32() -- Loot flag
		end

		if g_game.getProtocolVersion() >= 1260 then
			local isQuiver = msg:getU8()
			if isQuiver == 1 then
				msg:getU32() -- Quiver count
			end
		end
	else
		msg:getU8()
	end
end

function readContainerItems(msg, depth)
  depth = depth or 1
  if depth > 4 then
    msg:getU8()
    return
  end

  local itemCount = msg:getU8()
  for i = 1, itemCount do
    local clientId = msg:getU16()
    local thingType = g_things.getThingType(clientId, ThingCategoryItem)
    if thingType and thingType:isContainer() then
      readContainerItems(msg, depth + 1)
    else
      msg:getU8() -- count
      msg:getU16() -- worth
      msg:getString() -- name
    end
  end
end

function unregisterProtocol()
  if registredOpcodes == nil then
    return
  end
  for opcode in pairs(registredOpcodes) do
    ProtocolGame.unregisterOpcode(opcode)
  end
  registredOpcodes = nil
end

function registerOpcode(code, func)
  if registredOpcodes[code] ~= nil then
    error("Duplicated registed opcode: " .. code)
  end
  registredOpcodes[code] = func
  ProtocolGame.registerOpcode(code, func)
end

function readDailyReward(msg)
	local systemType = msg:getU8()
  local reward = {
    type = systemType,
    amount = 0,
    items = {},
    preyCount = 0,
    xpboost = 0
  }

	if (systemType == 1) then
    reward.amount = msg:getU8()
    local count = msg:getU8()
    for i = 1, count do
      reward.items[#reward.items + 1] = {
        item = msg:getU16(),
        name = msg:getString(),
        oz = msg:getU32()
      }
    end
	elseif (systemType == 2) then
    msg:getU8()
    local type = msg:getU8()

		if (type == DAILY_REWARD_SYSTEM_TYPE_PREY_REROLL) then
      reward.preyCount = msg:getU8()
		elseif (type == DAILY_REWARD_SYSTEM_TYPE_XP_BOOST) then
      reward.xpboost = msg:getU16()
		end
	end
  return reward
end
