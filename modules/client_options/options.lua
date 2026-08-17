local function ensureControlButton(controlButtons, buttonId)
	if type(controlButtons) ~= "table" then
		return false
	end
	local changed = false
	for _, listName in ipairs({ "enabledButtons", "disabledButtons" }) do
		if type(controlButtons[listName]) ~= "table" then
			controlButtons[listName] = {}
			changed = true
		end
	end

	-- A disabled entry is an explicit user choice and wins if an old settings
	-- file somehow contains the button in both lists.
	local disabled = controlButtons.disabledButtons
	local disabledFound = false
	for index = #disabled, 1, -1 do
		if disabled[index] == buttonId then
			if disabledFound then
				table.remove(disabled, index)
				changed = true
			else
				disabledFound = true
			end
		end
	end

	local enabled = controlButtons.enabledButtons
	local enabledFound = false
	for index = #enabled, 1, -1 do
		if enabled[index] == buttonId then
			if disabledFound or enabledFound then
				table.remove(enabled, index)
				changed = true
			else
				enabledFound = true
			end
		end
	end

	if not disabledFound and not enabledFound then
		table.insert(enabled, buttonId)
		changed = true
	end
	return changed
end

local EXPLORER_HOTKEY_ACTION = "assistantHuntingExplorerToggle"
local EXPLORER_DEFAULT_HOTKEY = "Ctrl+Shift+E"
local legacyExplorerHotkeyActions = {
	["HelperHuntingExplorerToggle"] = true,
	["HelperHuntingAutoExplorerToggle"] = true,
	["HuntingExplorerToggle"] = true,
	["assistantAutoExplorerToggle"] = true
}

local function migrateRetiredAssistantSettings()
	local changed = false
	local controlButtons = Options.array and Options.array["controlButtonsOptions"]
	if Options.array and type(controlButtons) ~= "table" then
		controlButtons = { enabledButtons = {}, disabledButtons = {} }
		Options.array["controlButtonsOptions"] = controlButtons
		changed = true
	end
	changed = ensureControlButton(controlButtons, "helperDialog") or changed
	local hotkeySets = Options.array and Options.array["hotkeyOptions"] and Options.array["hotkeyOptions"]["hotkeySets"]
	if type(hotkeySets) ~= "table" then
		return changed
	end

	for _, profile in pairs(hotkeySets) do
		for _, chatMode in ipairs({ "chatOff", "chatOn" }) do
			local mappings = type(profile) == "table" and profile[chatMode]
			if type(mappings) == "table" then
				local hasShowMiniBot = false
				local hasExplorerHotkey = false
				for _, mapping in ipairs(mappings) do
					local actionSetting = type(mapping) == "table" and mapping["actionsetting"]
					if actionSetting and actionSetting["action"] == "ShowMiniBot" then
						hasShowMiniBot = true
					elseif actionSetting and actionSetting["action"] == EXPLORER_HOTKEY_ACTION then
						hasExplorerHotkey = true
					end
				end

				for index = #mappings, 1, -1 do
					local mapping = mappings[index]
					local actionSetting = type(mapping) == "table" and mapping["actionsetting"]
					local action = actionSetting and actionSetting["action"]
					if legacyExplorerHotkeyActions[action] then
						if hasExplorerHotkey then
							table.remove(mappings, index)
						else
							actionSetting["action"] = EXPLORER_HOTKEY_ACTION
							hasExplorerHotkey = true
						end
						changed = true
					elseif action == "ShowHelper" then
						if hasShowMiniBot then
							table.remove(mappings, index)
						else
							actionSetting["action"] = "ShowMiniBot"
							hasShowMiniBot = true
						end
						changed = true
					elseif type(action) == "string" and action:match("^Helper") then
						table.remove(mappings, index)
						changed = true
					end
				end

				if not hasExplorerHotkey then
					local defaultKeyAvailable = true
					for _, mapping in ipairs(mappings) do
						if type(mapping) == "table" and mapping["keysequence"] == EXPLORER_DEFAULT_HOTKEY then
							defaultKeyAvailable = false
							break
						end
					end
					if defaultKeyAvailable then
						table.insert(mappings, {
							["actionsetting"] = { ["action"] = EXPLORER_HOTKEY_ACTION },
							["keysequence"] = EXPLORER_DEFAULT_HOTKEY
						})
						changed = true
					end
				end
			end
		end
	end

	return changed
end

function Options.migrateRetiredAssistantSettings()
	return migrateRetiredAssistantSettings()
end

function init()
	connect(g_game, {
		onGameStart = online,
		onGameEnd = offline
	})

	if not Options.loadData("/settings/clientoptions.json") then
		Options.createDefaultSettings()
	end

	if not Options.array then
		g_logger.error("Failed to load clientoptions.json")
		return true
	end

	Options.profiles = Options.array["profiles"]
	
	-- Force insert monk
	if Options.profiles then
		if not Options.array["hotkeyOptions"]["hotkeySets"]["Monk"] then
			Options.array["hotkeyOptions"]["hotkeySets"]["Monk"] = Options.getDefaultProfile("Monk")
			table.insert(Options.profiles, "Monk")
		end
	end

	Options.pinnedCharacters = Options.array["pinnedCharacters"]
	Options.hotkeySets = Options.array["hotkeyOptions"]["hotkeySets"]
	Options.currentHotkeySetName = Options.array["hotkeyOptions"]["currentHotkeySetName"]
	Options.currentHotkeySet = Options.array["hotkeyOptions"]["hotkeySets"][Options.currentHotkeySetName]

	if not Options.profiles then
		Options.profiles = {}
		for index, k in pairs(Options.hotkeySets) do
			table.insert(Options.profiles, index)
		end
	end

	if not Options.currentHotkeySet then
		Options.array["hotkeyOptions"]["currentHotkeySetName"] = Options.profiles[1]
		Options.currentHotkeySetName = Options.profiles[1]
		Options.currentHotkeySet = Options.array["hotkeyOptions"]["hotkeySets"][Options.profiles[1]]
	end

	Options.actionBarOptions = Options.currentHotkeySet["actionBarOptions"]
	Options.actionBarMappings = Options.actionBarOptions["mappings"]

	Options.clientOptions = Options.array["options"]

	-- Bottom bar
	for i = 1, 3 do
		local show = Options.clientOptions["actionBarShowBottom" .. i]
		local locked = Options.clientOptions["actionBarBottomLocked"]
		Options.actionBar[#Options.actionBar + 1] = {isVisible = show, isLocked = locked}
	end

	-- Left bar
	for i = 1, 3 do
		local show = Options.clientOptions["actionBarShowLeft" .. i]
		local locked = Options.clientOptions["actionBarLeftLocked"]
		Options.actionBar[#Options.actionBar + 1] = {isVisible = show, isLocked = locked}
	end

	-- Right bar
	for i = 1, 3 do
		local show = Options.clientOptions["actionBarShowRight" .. i]
		local locked = Options.clientOptions["actionBarRightLocked"]
		Options.actionBar[#Options.actionBar + 1] = {isVisible = show, isLocked = locked}
	end

	-- load common
	Options.chatOptions = Options.array["chatOptions"]
	Options.isChatOnEnabled = Options.chatOptions["chatModeOn"]

	local settingsMigrated = migrateRetiredAssistantSettings()
	Options.validateAssignedHotkeys()
	if settingsMigrated then
		Options.saveData()
	end
end

function terminate()
  if Options.array and Options.chatOptions then
    Options.saveData()
  end

  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline
  })
end

function online()
	local benchmark = g_clock.millis()
	-- create character dir
	local player = g_game.getLocalPlayer()
	if not g_resources.directoryExists("/characterdata/".. player:getId() .."/") then
		g_resources.makeDir("/characterdata/".. player:getId() .."/")
	end
	consoleln("Options loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function offline()
	Options.saveData()
end

function Options.createDefaultSettings()
	if not g_resources.directoryExists("/settings/") then
		g_resources.makeDir("/settings/")
	end

	Options.loadData("/data/json/default-options.json")
end

function Options.getDefaultProfile(name)
	local file = "/data/json/default-options.json"
	if g_resources.fileExists(file) then
		local status, result = pcall(function()
			return json.decode(g_resources.readFileContents(file))
		end)

		if not status then
			return false
		end
		return result["hotkeyOptions"]["hotkeySets"][name]
	end
end

-- json handlers
function Options.loadData(file)
	if g_resources.fileExists(file) then
		local status, result = pcall(function()
			return json.decode(g_resources.readFileContents(file))
		end)

		if not status then
			return false
		end

		Options.array = result
		return true
	end
	return false
end

function Options.saveData()
	Options.validateOpenChannels()
	local file = "/settings/clientoptions.json"
	local status, result = pcall(function() return json.encode(Options.array) end)
	if not status then
		return onError("Error while saving general options settings. Data won't be saved. Details: " .. result)
	end

	if result:len() > 100 * 1024 * 1024 then
	  return onError("Something went wrong, file is above 100MB, won't be saved")
	end

	g_resources.writeFileContents(file, result)
end

function Options.getDummyProfile()
	local file = "/data/json/default-options.json"
	if g_resources.fileExists(file) then
		local status, result = pcall(function()
			return json.decode(g_resources.readFileContents(file))
		end)

		if not status then
			return false
		end
		return result["DummyProfile"]
	end
end

function Options.getDefaultSideButtons()
	local file = "/data/json/default-options.json"
	if g_resources.fileExists(file) then
		local status, result = pcall(function()
			return json.decode(g_resources.readFileContents(file))
		end)

		if not status then
			return false
		end
		return result["controlButtonsOptions"]
	end
end

local replace = {
	["Ins"] = "Insert",
	["Del"] = "Delete",
	["PgUp"] = "PageUp",
	["PgDown"] = "PageDown",
	["Num+1"] = "N1",
	["Num+2"] = "N2",
	["Num+3"] = "N3",
	["Num+4"] = "N4",
	["Num+5"] = "N5",
	["Num+6"] = "N6",
	["Num+7"] = "N7",
	["Num+8"] = "N8",
	["Num+9"] = "N9",
	["Num+0"] = "N0",
	["Return"] = "Enter",
	["Alt+Return"] = "Alt+Enter",
	["Shift+Return"] = "Shift+Enter",
	["Ctrl+Return"] = "Ctrl+Enter",
	["Alt+PgUp"] = "Alt+PageUp",
	["Alt+PgDown"] = "Alt+PageDown"
}

function Options.validateAssignedHotkeys()
	for _, j in pairs(Options.array["hotkeyOptions"]["hotkeySets"]) do
		for _, k in pairs(j) do

			local lastAction = ""
			local showMapFound = false
			for i, l in pairs(k) do
				if l["actionsetting"] and l["actionsetting"]["action"] then
					local action = l["actionsetting"]["action"]
					if lastAction == l["actionsetting"]["action"] then
						l["secondary"] = true
					end

					if action == "ChatModeTemporaryOn" then
						l["actionsetting"]["action"] = "ChatModeTemporaryOnEnter"
					end

					lastAction = action
				end

				if replace[l["keysequence"]] then
					l["keysequence"] = replace[l["keysequence"]]
				end

				if l["actionsetting"] and l["actionsetting"]["action"] and l["actionsetting"]["action"] == "MinimapShow" then
					showMapFound = true
				end

				if i == #k and not showMapFound then
					k[#k + 1] = {
						["actionsetting"] = { ["action"] = "MinimapShow" },
						["keysequence"] = "Alt+M"
					}
				end
			end
		end
	end
end
