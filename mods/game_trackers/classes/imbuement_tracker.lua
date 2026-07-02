---------------------------
-- Lua code author: R1ck --
-- Company: VICTOR HUGO PERENHA - JOGOS ON LINE --
---------------------------

ImbuementTracker = {}
ImbuementTracker.__index = ImbuementTracker

local imbuementData = nil
local sortOptions = {}
local characterConfig = {}

-- Throttle handle for the 0x5d duration stream (see onReceiveData).
local refreshEvent = nil

local sortTypes = {
	LESS_THAN_ONE = 1,
	LAST_BETWEEN = 2,
	MORE_THAN_THREE = 3,
	NO_ACTIVE = 4,
}

function ImbuementTracker.onReceiveData(items)
	imbuementData = items
	-- The server streams GameServerImbuementDurations(0x5d) continuously while
	-- the tracker is open (observed ~150x/s). Rebuilding the widget tree on every
	-- packet (destroyChildren + recreate ~hundreds of widgets) burns the Lua/UI
	-- thread and starves the render/worker thread. Throttle to at most one rebuild
	-- per second: the first packet schedules the refresh, later packets only update
	-- the cached payload, and the scheduled refresh renders the latest data when it
	-- fires. A reset-on-each debounce (like the boss/bestiary trackers use for their
	-- bursty 0xB9) would never fire under a continuous stream, so we keep the
	-- pending event instead of rescheduling it.
	if refreshEvent then
		return
	end
	refreshEvent = scheduleEvent(function()
		refreshEvent = nil
		ImbuementTracker.showTrackerData()
	end, 1000)
end

function ImbuementTracker.showTrackerData()
	if not imbuementData or not g_game.isOnline() then
		return
	end

	-- Don't rebuild the widget tree when the tracker is hidden: the server can
	-- keep streaming 0x5d durations even after the window is closed/minimized,
	-- and a rebuild nobody can see is pure wasted work. isVisible() is false when
	-- the window is closed; .minimized covers the collapsed state (the title bar
	-- stays visible but contentsPanel is hidden).
	if not imbuementTrackerWindow:isVisible() or imbuementTrackerWindow.minimized then
		return
	end

	local sortedData = {}
	imbuementTrackerWindow.contentsPanel:destroyChildren()

	for _, data in pairs(imbuementData) do
		-- crystalserver's playerRequestInventoryImbuements (game.cpp) sends EVERY
		-- equipped item, not just imbuement-capable ones; items with no imbuement
		-- slots arrive with totalSlots == 0 and an empty slots map. Such an item is
		-- never imbuement-trackable, so skip it before the duration/active filters
		-- (otherwise it renders an empty ImbuePanel).
		if (data.totalSlots or 0) > 0 then
			-- The C++ dispatch only sends imbued slots in data.slots (empties are
			-- skipped server-side); empties are derived from totalSlots - activeSlots.
			local canShow = true
			local activeSlots = 0
			for _, v in pairs(data.slots) do
				activeSlots = activeSlots + 1

				local hours = math.floor(v.duration / 3600)

				if not sortOptions[sortTypes.LESS_THAN_ONE] and hours < 1 then
					canShow = false
				end

				if not sortOptions[sortTypes.LAST_BETWEEN] and (hours >= 1 and hours <= 3) then
					canShow = false
				end

				if not sortOptions[sortTypes.MORE_THAN_THREE] and hours > 3 then
					canShow = false
				end
			end

			local emptySlots = (data.totalSlots or 0) - activeSlots
			if not sortOptions[sortTypes.NO_ACTIVE] and activeSlots == 0 and emptySlots > 0 then
				canShow = false
			end

			if canShow then
				table.insert(sortedData, data)
			end
		end
	end

	for _, data in pairs(sortedData) do
		local widget = g_ui.createWidget('ImbuePanel', imbuementTrackerWindow.contentsPanel)
		-- UIItem:setItem already renders the (virtual) item icon for a display-only
		-- slot. The old setPosition/setStaticThing dance is unnecessary: setStaticThing
		-- has no Item/Thing binding (it never existed on Item in mehah/koliseu-otc
		-- either), and the x=65535 marker only feeds pattern math (% numPatternX),
		-- which is a no-op for single-pattern equipment. Containers are never
		-- imbuement-trackable, so the updateFlags() branch was dead code.
		widget.itemSlot:setItem(data.item)

		-- The C++ dispatch only sends imbued slots in data.slots (empties are
		-- skipped server-side); each entry's .id is the 0-based slotIndex, so +1
		-- maps to the 1-based panel/imbueContainer numbering. Index the filled
		-- slots by panel index so every slot 1..totalSlots can be rendered, with
		-- the empties falling back to the otui placeholder artwork.
		local filled = {}
		for _, v in pairs(data.slots) do
			filled[v.id + 1] = v
		end

		for panelIndex = 1, data.totalSlots do
			local panel = widget:recursiveGetChildById("panel" .. panelIndex)
			local source = widget:recursiveGetChildById("imbueContainer" .. panelIndex)
			if panel and source then
				source:setVisible(true)
				panel:setVisible(true)

				local v = filled[panelIndex]
				if v then
					local total_seconds = v.duration
					local hours = math.floor(total_seconds / 3600)
					local minutes = math.floor((total_seconds % 3600) / 60)
					local seconds = total_seconds % 60

					local formatted_minutes = string.format("%02d", minutes)
					local formatted_seconds = string.format("%02d", seconds)

					source:setImageSource("/images/game/imbuing/imbuement-icons-64")
        			source:setImageClip(getFramePosition(v.iconId, 64, 64, 21) .. " 64 64")
					source:setTooltip(tr("%s\n\nTime remaining: %sh %smin", v.name, hours, minutes))

					if hours >= 10 then
						source:setText(hours .. "h")
					elseif hours < 10 and hours >= 1 then
						source:setText(hours .. "h" .. formatted_minutes)
					elseif hours < 1 and minutes >= 10 then
						source:setText(formatted_minutes .. "m")
					elseif minutes < 10 and minutes >= 1 then
						source:setText(minutes .. "m" .. formatted_seconds)
						source:setTooltip(tr("%s\n\nTime remaining: %sm %sseconds", v.name, minutes, seconds))
					else
						source:setText(formatted_seconds .. "s")
						source:setTooltip(tr("%s\n\nTime remaining: %s seconds", v.name, seconds))
					end

					if hours < 1 then
						source:setColor("#d33c3c")
					elseif hours < 3 then
						source:setColor("#f8db38")
					end
				else
					-- Empty slot: the inactive-slot art Tibia/mehah uses for an
					-- unfilled imbuement slot (imported from koliseu-otc:
					-- /images/game/imbuing/slot_inactive, 66x66, single frame).
					-- Clear the stale 64x64 imbuement-icons clip and reset
					-- text/color/tooltip to the free-slot defaults.
					source:setImageSource("/images/game/imbuing/slot_inactive")
					source:setImageClip("0 0 66 66")
					source:setText("")
					source:setColor("#ffffff")
					source:setTooltip(tr("Empty slot"))
				end
			end
		end
	end
end

function ImbuementTracker.initSortFields()
	sortOptions[sortTypes.LESS_THAN_ONE] = characterConfig["showAlmostGone"]
	sortOptions[sortTypes.LAST_BETWEEN] = characterConfig["showUsed"]
	sortOptions[sortTypes.MORE_THAN_THREE] = characterConfig["showAlmostNew"]
	sortOptions[sortTypes.NO_ACTIVE] = characterConfig["showEmptySlots"]
end

function ImbuementTracker.onSortButton()
	local sortMenu = g_ui.createWidget('PopupMenu')
    sortMenu:setGameMenu(true)
	sortMenu:addCheckBoxOption(tr('Show imbuements that last less than 1h'), function() ImbuementTracker.sortFilterCheck(sortTypes.LESS_THAN_ONE) end, "", sortOptions[sortTypes.LESS_THAN_ONE])
    sortMenu:addCheckBoxOption(tr('Show imbuements that last between 1h and 3h'), function() ImbuementTracker.sortFilterCheck(sortTypes.LAST_BETWEEN) end, "", sortOptions[sortTypes.LAST_BETWEEN])
    sortMenu:addCheckBoxOption(tr('Show imbuements that last more than 3h'), function() ImbuementTracker.sortFilterCheck(sortTypes.MORE_THAN_THREE) end, "", sortOptions[sortTypes.MORE_THAN_THREE])
    sortMenu:addCheckBoxOption(tr('Show items with no active imbuement'), function() ImbuementTracker.sortFilterCheck(sortTypes.NO_ACTIVE) end, "", sortOptions[sortTypes.NO_ACTIVE])
    sortMenu:display(g_window.getMousePosition())
end

function ImbuementTracker.sortFilterCheck(type)
	sortOptions[type] = not sortOptions[type]
	if type == sortTypes.LESS_THAN_ONE then
		characterConfig["showAlmostGone"] = sortOptions[type]
	elseif type == sortTypes.LAST_BETWEEN then
		characterConfig["showUsed"] = sortOptions[type]
	elseif type == sortTypes.MORE_THAN_THREE then
		characterConfig["showAlmostNew"] = sortOptions[type]
	else
		characterConfig["showEmptySlots"] = sortOptions[type]
	end
	ImbuementTracker.showTrackerData()
end

function ImbuementTracker.online()
	characterConfig = modules.game_sidebars.getImbuementTrackerConfig()
	if table.empty(characterConfig) then
		characterConfig = {
			["contentHeight"] = 0,
			["contentMaximized"] =  true,
			["showAlmostGone"] =  true,
			["showAlmostNew"] =  true,
			["showEmptySlots"] =  true,
			["showUsed"] =  true
		}
	end
end

function ImbuementTracker.offline()
	-- Drop any pending throttled refresh so it can't fire during teardown.
	if refreshEvent then
		removeEvent(refreshEvent)
		refreshEvent = nil
	end
	modules.game_sidebars.registerImbuementTrackerConfig(characterConfig)
end