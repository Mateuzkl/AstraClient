local DEFAULT_FILE = "/data/json/default-options.json"
local SAVED_FILE = "/settings/clientoptions.json"

-- A successfully decoded JSON document can still have missing root sections.
local function validOptions(data, isDefault)
  if type(data) ~= "table" or type(data.options) ~= "table" or
      type(data.chatOptions) ~= "table" or type(data.chatOptions.openChannels) ~= "table" then
    return false, "options/chatOptions are missing"
  end
  local buttons = data.controlButtonsOptions
  if type(buttons) ~= "table" or type(buttons.enabledButtons) ~= "table" or
      type(buttons.disabledButtons) ~= "table" then
    return false, "controlButtonsOptions are missing"
  end
  local hotkeys = data.hotkeyOptions
  if type(hotkeys) ~= "table" or type(hotkeys.hotkeySets) ~= "table" or
      type(hotkeys.currentHotkeySetName) ~= "string" or next(hotkeys.hotkeySets) == nil then
    return false, "hotkeyOptions are missing"
  end
  for name, profile in pairs(hotkeys.hotkeySets) do
    if type(name) ~= "string" or type(profile) ~= "table" or
        type(profile.chatOn) ~= "table" or type(profile.chatOff) ~= "table" or
        type(profile.actionBarOptions) ~= "table" or
        type(profile.actionBarOptions.mappings) ~= "table" then
      return false, "invalid hotkey profile: " .. tostring(name)
    end
  end
  if data.profiles ~= nil then
    if type(data.profiles) ~= "table" then return false, "invalid profiles list" end
    for _, name in ipairs(data.profiles) do
      if type(name) ~= "string" or (not hotkeys.hotkeySets[name] and name ~= "Monk") then
        return false, "profiles list references a missing hotkey set"
      end
    end
  end
  if isDefault then
    local dummy = data.DummyProfile
    if type(dummy) ~= "table" or type(dummy.chatOn) ~= "table" or
        type(dummy.chatOff) ~= "table" or type(dummy.actionBarOptions) ~= "table" or
        type(dummy.actionBarOptions.mappings) ~= "table" or
        type(data.profiles) ~= "table" or #data.profiles == 0 or
        not hotkeys.hotkeySets[hotkeys.currentHotkeySetName] then
      return false, "incomplete default profiles"
    end
  end
  return true
end

local function readOptions(path, isDefault)
  if not g_resources.fileExists(path) then return nil, "file missing" end
  local ok, data = pcall(function()
    return json.decode(g_resources.readFileContents(path))
  end)
  if not ok then return nil, "JSON parse failed" end
  local valid, reason = validOptions(data, isDefault)
  if not valid then return nil, reason end
  return data
end

-- Preserve broken user data before loading defaults. Refuse to write otherwise.
local function backupSavedOptions()
  local ok, bytes = pcall(g_resources.readFileContents, SAVED_FILE)
  if not ok or type(bytes) ~= "string" or #bytes > 32 * 1024 * 1024 then return nil end
  for index = 1, 100 do
    local backup = string.format("/settings/clientoptions.corrupt.%d.json", index)
    if not g_resources.fileExists(backup) then
      local written, result = pcall(g_resources.writeFileContents, backup, bytes)
      if written and result == true then
        local checked, copied = pcall(g_resources.readFileContents, backup)
        if checked and copied == bytes then return backup end
      end
      return nil
    end
  end
  return nil
end

function init()
  -- Default assets must be valid even with saved settings: profile resets use them.
  local defaults, errorMessage = readOptions(DEFAULT_FILE, true)
  if not defaults then
    g_logger.fatal("[ClientOptions] Missing/damaged " .. DEFAULT_FILE .. ": " ..
      tostring(errorMessage) .. ". Repair or reinstall the complete client files.")
    return
  end
  Options.settingsReadOnly = false
  Options.actionBar = {}
  local savedExists = g_resources.fileExists(SAVED_FILE)
  if not Options.loadData(SAVED_FILE) then
    if savedExists then
      local backup = backupSavedOptions()
      if backup then
        g_logger.error("[ClientOptions] Invalid player configuration; original backed up: " .. backup)
      else
        Options.settingsReadOnly = true
        g_logger.error("[ClientOptions] Invalid player configuration; could not make backup. " ..
          "Defaults are temporary and saves are disabled to preserve the original.")
      end
    end
    Options.array = defaults
  end
  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline
  })

	Options.profiles = Options.array["profiles"]
	
	-- Force insert monk
	if Options.profiles then
		if not Options.array["hotkeyOptions"]["hotkeySets"]["Monk"] then
      local monk = Options.getDefaultProfile("Monk")
      if monk then
        Options.array["hotkeyOptions"]["hotkeySets"]["Monk"] = monk
        table.insert(Options.profiles, "Monk")
      end
    end
	end

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

	-- Checks for import 13 hotkeys
	if not table.find(Options.array["controlButtonsOptions"]["disabledButtons"], "helperDialog") and not table.find(Options.array["controlButtonsOptions"]["enabledButtons"], "helperDialog") then
		table.insert(Options.array["controlButtonsOptions"]["enabledButtons"], "helperDialog")
	end

	Options.validateAssignedHotkeys()
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
  return Options.loadData(DEFAULT_FILE, true)
end

function Options.getDefaultProfile(name)
  local defaults = readOptions(DEFAULT_FILE, true)
  return defaults and defaults.hotkeyOptions.hotkeySets[name] or nil
end

function Options.loadData(file, isDefault)
  local data, reason = readOptions(file, isDefault)
  if not data then
    if g_resources.fileExists(file) then
      g_logger.error("[ClientOptions] Invalid " .. file .. ": " .. tostring(reason))
    end
    return false
  end
  Options.array = data
  return true
end

function Options.saveData()
  if Options.settingsReadOnly or not Options.array or not Options.chatOptions then
    return false
  end
  Options.validateOpenChannels()
  local file = SAVED_FILE
  local status, result = pcall(function() return json.encode(Options.array) end)
  if not status then
    return onError("Error while saving general options settings. Data won't be saved. Details: " .. result)
  end
  if result:len() > 100 * 1024 * 1024 then
    return onError("Something went wrong, file is above 100MB, won't be saved")
  end
  return g_resources.writeFileContents(file, result)
end

function Options.getDummyProfile()
  local defaults = readOptions(DEFAULT_FILE, true)
  return defaults and defaults.DummyProfile or nil
end

function Options.getDefaultSideButtons()
  local defaults = readOptions(DEFAULT_FILE, true)
  return defaults and defaults.controlButtonsOptions or nil
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
