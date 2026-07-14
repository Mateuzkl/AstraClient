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

	-- A clientoptions.json from an older schema (or a half-written one left behind by a
	-- boot that crashed) can be missing the whole hotkeyOptions block. Every line below
	-- indexes it unconditionally, so on a fresh PC that turns into a fatal error that
	-- stops the client from opening at all. Fall back to the bundled defaults instead.
	if type(Options.array["hotkeyOptions"]) ~= "table" then
		g_logger.warning("clientoptions.json has no hotkeyOptions block; restoring defaults")
		Options.createDefaultSettings()
	end

	if not Options.array or type(Options.array["hotkeyOptions"]) ~= "table" then
		g_logger.error("Failed to load a valid clientoptions.json (no hotkeyOptions)")
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

	Options.validateAssignedHotkeys()
end

function terminate()
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
