local SideBars = {
	npcTradeOptions = {},
	xpAnalyserWidgetOptions = {},
	unjustifiedPointsOptions = {},
	partyHuntAnalyserOptions = {},
	preyWidgetOptions = {},
	questTrackerWidgetOptions = {},
	bestiaryTrackerWidgetOptions = {},
	vipWidgetOptions = {},
	battleListsOptions = {},
	supplyAnalyserWidgetOptions = {},
	bossTrackerWidgetOptions = {},
	sidebarPanelsOptions = {},
	bosstiaryTrackerWidgetOptions = {},
	containersOptions = {},
	damageInputAnalyserWidgetOptions = {},
	deoptSearchWidgetOptions = {},
	spellListWidgetOptions = {},
	huntingSessionAnalyserWidgetOptions = {},
	imbuementTrackerWidgetOptions = {},
	analyticsSelectorOptions = {},
	sidebarWidgetsMangerOptions = {},
	sidebarPanelsMangerOptions = {},
	skillsWidgetOptions = {},
	impactAnalyserWidgetOptions = {},
	lootAnalyserWidgetOptions = {},
	lootTrackerWidgetOptions = {},
	minimapOptions = {},
	horizontalLeftOptions = {},
	horizontalRightOptions = {},
	partyListsOptions = {},
	channelsOpen = {
		[1] = {name = LOCAL_CHAT_NAME, channel = 0},
		[2] = {name = SERVER_LOG_NAME, channel = 0},
		[3] = {name = SPELL_CHANNEL_NAME, channel = SPELL_CHANNEL_ID},
	},
}

function init( ... )
  connect(g_game, {
    onGameStart = onGameStart,
	onEnterGame = onEnterGame
  })
end

function terminate( ... )
  disconnect(g_game, {
    onGameStart = onGameStart,
	onEnterGame = onEnterGame
  })
end

function onGameStart()
	local benchmark = g_clock.millis()
	loadConfigJson()
	m_interface.onPlayerLoad(SideBars.sidebarWidgetsMangerOptions)
	scheduleEvent(function() modules.game_console.onPlayerLoad(SideBars.channelsOpen) end, 1500)
	consoleln("Sidebars loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function onEnterGame()
	-- m_interface.onPlayerLoad(SideBars.sidebarWidgetsMangerOptions)
end

function resetConfigs()
	SideBars.npcTradeOptions = {}
	SideBars.xpAnalyserWidgetOptions = {}
	SideBars.unjustifiedPointsOptions = {}
	SideBars.partyHuntAnalyserOptions = {}
	SideBars.preyWidgetOptions = {}
	SideBars.questTrackerWidgetOptions = {}
	SideBars.bestiaryTrackerWidgetOptions = {}
	SideBars.vipWidgetOptions = {}
	SideBars.battleListsOptions = {}
	SideBars.partyListsOptions = {}
	SideBars.supplyAnalyserWidgetOptions = {}
	SideBars.bossTrackerWidgetOptions = {}
	SideBars.sidebarPanelsOptions = {}
	SideBars.bosstiaryTrackerWidgetOptions = {}
	SideBars.containersOptions = {}
	SideBars.damageInputAnalyserWidgetOptions = {}
	SideBars.deoptSearchWidgetOptions = {}
	SideBars.spellListWidgetOptions = {}
	SideBars.huntingSessionAnalyserWidgetOptions = {}
	SideBars.imbuementTrackerWidgetOptions = {}
	SideBars.analyticsSelectorOptions = {}
	SideBars.sidebarWidgetsMangerOptions = {}
	SideBars.sidebarPanelsMangerOptions = {}
	SideBars.skillsWidgetOptions = {}
	SideBars.impactAnalyserWidgetOptions = {}
	SideBars.lootAnalyserWidgetOptions = {}
	SideBars.lootTrackerWidgetOptions = {}
	SideBars.minimapOptions = {}
	SideBars.horizontalLeftOptions = {}
	SideBars.horizontalRightOptions = {}
	SideBars.channelsOpen = {
		[1] = {name = LOCAL_CHAT_NAME, channel = 0},
		[2] = {name = SERVER_LOG_NAME, channel = 0},
		[3] = {name = SPELL_CHANNEL_NAME, channel = SPELL_CHANNEL_ID},
	}
end

local function isTypePresent(widgetList, widgetType)
	for _, widget in ipairs(widgetList) do
		if widget["type"] == widgetType then
			return true
		end
	end
	return false
end

local function ensureWidgetsPresent()
    local requiredWidgets = {
        {["height"] = 200, ["type"] = "miniMap"},
        {["height"] = 32, ["type"] = "healthInfo"},
        {["height"] = 167, ["type"] = "inventoryWindow"}, -- always visible
        {["height"] = 136, ["type"] = "mainButtons"} -- always visible
    }
    
    if table.empty(SideBars.sidebarWidgetsMangerOptions) then
        SideBars.sidebarWidgetsMangerOptions = {["openWidgetsOrderPerSidebar"] = {requiredWidgets}}
        return true
    end
    
    local function widgetExists(widgetType, widgetsArray)
        for _, widget in pairs(widgetsArray) do
            if widget.type == widgetType then
                return true
            end
        end
        return false
    end

    if not SideBars.sidebarWidgetsMangerOptions.openWidgetsOrderPerSidebar then
        SideBars.sidebarWidgetsMangerOptions.openWidgetsOrderPerSidebar = {}
    end
    
    if #SideBars.sidebarWidgetsMangerOptions.openWidgetsOrderPerSidebar == 0 then
        table.insert(SideBars.sidebarWidgetsMangerOptions.openWidgetsOrderPerSidebar, {})
    end
    
    local firstWidgetsArray = SideBars.sidebarWidgetsMangerOptions.openWidgetsOrderPerSidebar[1]
    
    for _, requiredWidget in pairs(requiredWidgets) do
        local found = false

        for _, widgetsArray in pairs(SideBars.sidebarWidgetsMangerOptions.openWidgetsOrderPerSidebar) do
            if widgetExists(requiredWidget.type, widgetsArray) then
                found = true
                break
            end
        end
        
        if not found and (requiredWidget.type == "inventoryWindow" or requiredWidget.type == "mainButtons") then
			local widgetCopy = {}
			for key, value in pairs(requiredWidget) do
				widgetCopy[key] = value
			end
			table.insert(firstWidgetsArray, widgetCopy)
        end
    end
end

function loadConfigJson()
  local config = SideBars

  if not LoadedPlayer:isLoaded() then
  	return
  end

  local file = "/characterdata/" .. LoadedPlayer:getId() .. "/sidebars.json"
  if g_resources.fileExists(file) then
    local status, result = pcall(function()
      return json.decode(g_resources.readFileContents(file))
    end)

    if not status then
      return false
    end

    SideBars = result
  end

  ensureWidgetsPresent()
  m_interface.onLoadHorizontalPanels(SideBars.horizontalLeftOptions, SideBars.horizontalRightOptions)
  modules.game_viplist.onPlayerLoad(SideBars.vipWidgetOptions)
  modules.game_battle.onPlayerLoad(SideBars.battleListsOptions)
  if modules.game_party_list and modules.game_party_list.onPlayerLoad then
    modules.game_party_list.onPlayerLoad(SideBars.partyListsOptions)
  end
  if modules.game_trackers and modules.game_trackers.onPlayerLoad then
    modules.game_trackers.onPlayerLoad(SideBars.bestiaryTrackerWidgetOptions, SideBars.bossTrackerWidgetOptions)
  end
end

function saveConfigJson(callUnload)
  if not LoadedPlayer:isLoaded() then return end

  if not callUnload then
    if modules.game_battle and modules.game_battle.onPlayerUnload then modules.game_battle.onPlayerUnload() end
    if modules.game_analyser and modules.game_analyser.onPlayerUnload then modules.game_analyser.onPlayerUnload() end
    if modules.game_minimap and modules.game_minimap.onPlayerUnload then modules.game_minimap.onPlayerUnload() end
    if modules.game_trackers and modules.game_trackers.onPlayerUnload then modules.game_trackers.onPlayerUnload() end
    if modules.game_console and modules.game_console.onPlayerUnload then modules.game_console.onPlayerUnload() end
    if modules.game_skills and modules.game_skills.onPlayerUnload then modules.game_skills.onPlayerUnload() end
  end

  local config = SideBars
  local file = "/characterdata/" .. LoadedPlayer:getId() .. "/sidebars.json"
  local status, result = pcall(function() return json.encode(config, 2) end)
  if not status then
    return g_logger.error("Error while saving profile characterdata sidebars. Data won't be saved. Details: " .. result)
  end

  if result:len() > 100 * 1024 * 1024 then
    return g_logger.error("Something went wrong, file is above 100MB, won't be saved")
  end
  g_resources.writeFileContents(file, result)
end

function registerBattleWindow(battleId, configs)
	SideBars.battleListsOptions[battleId] = configs
end
function registerPartyWindow(configs)
	SideBars.partyListsOptions = configs
end

function registerHorizontalPanels(left, right)
	SideBars.horizontalLeftOptions.contentHeight = left
	SideBars.horizontalRightOptions.contentHeight = right
end

function registerSideBarWidgetsManager(configs)
	SideBars.sidebarWidgetsMangerOptions = configs
end
function registerVipListConfig(configs)
  SideBars.vipWidgetOptions = configs
end
function registerMinimapConfig(configs)
  SideBars.minimapOptions = configs
end
function registerSkillWidgetsConfig(configs)
	SideBars.skillsWidgetOptions = configs
end
function registerSpellListConfig(configs)
	SideBars.spellListWidgetOptions = configs
end
function registerImbuementTrackerConfig(configs)
	SideBars.imbuementTrackerWidgetOptions = configs
end

function getMinimapConfig()
  return SideBars.minimapOptions
end

function getSkillsWidgetConfig()
	return SideBars.skillsWidgetOptions
end

function getSpellListConfig()
	return SideBars.spellListWidgetOptions
end

function getImbuementTrackerConfig()
	return SideBars.imbuementTrackerWidgetOptions
end

function setBestiaryTrackerOptions(option)
	SideBars.bestiaryTrackerWidgetOptions = option
end

function setBosstiaryTrackerOptions(option)
	SideBars.bossTrackerWidgetOptions = option
end

function setChannelOptions(option)
	SideBars.channelsOpen = option
end
