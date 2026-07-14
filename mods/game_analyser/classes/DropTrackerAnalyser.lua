if not DropTrackerAnalyser then
	DropTrackerAnalyser = {
		launchTime = 0,
		session = 0,

		trackedItems = {},

		autoTrackAboveValue = 0,

		-- private
		window = nil,
		pendingWindowUpdate = nil,
	}
	DropTrackerAnalyser.__index = DropTrackerAnalyser
end

function DropTrackerAnalyser:create()
	if DropTrackerAnalyser.pendingWindowUpdate then
		removeEvent(DropTrackerAnalyser.pendingWindowUpdate)
		DropTrackerAnalyser.pendingWindowUpdate = nil
	end
	DropTrackerAnalyser.window = openedWindows['dropButton']

	DropTrackerAnalyser.launchTime = g_clock.millis()
	DropTrackerAnalyser.session = 0
	DropTrackerAnalyser.autoTrackAboveValue = 0

	DropTrackerAnalyser.trackedItems = {}
end

function DropTrackerAnalyser:queueWindowUpdate()
	if DropTrackerAnalyser.pendingWindowUpdate then
		return
	end

	DropTrackerAnalyser.pendingWindowUpdate = scheduleEvent(function()
		DropTrackerAnalyser.pendingWindowUpdate = nil
		if DropTrackerAnalyser.window then
			DropTrackerAnalyser:updateWindow()
		end
	end, 1)
end

function DropTrackerAnalyser:cancelPendingWindowUpdate()
	if DropTrackerAnalyser.pendingWindowUpdate then
		removeEvent(DropTrackerAnalyser.pendingWindowUpdate)
		DropTrackerAnalyser.pendingWindowUpdate = nil
	end
end

function DropTrackerAnalyser:checkTracker()
	local needUpdate = false
	local now = os.time()
	for itemId, config in pairs(DropTrackerAnalyser.trackedItems) do
		if not config.persistent and (now - config.recordStartTimestamp > 120) then
			DropTrackerAnalyser.trackedItems[itemId] = nil
			needUpdate = true
		else
			-- Expire data even while the window is hidden. Previously the UI early
			-- return kept these rows in memory until the tracker was opened again.
			for id = #config.monsterDrop, 1, -1 do
				if (now - config.monsterDrop[id].time) > 45 then
					table.remove(config.monsterDrop, id)
					needUpdate = true
				end
			end
		end
	end

	if needUpdate then
		DropTrackerAnalyser:updateWindow()
	end
end

function DropTrackerAnalyser:reset(resetAutoTrack)
	DropTrackerAnalyser.launchTime = g_clock.millis()
	DropTrackerAnalyser.session = 0
	if resetAutoTrack then
		DropTrackerAnalyser.autoTrackAboveValue = 0
	end

	for itemId, config in pairs(DropTrackerAnalyser.trackedItems) do
		if config.monsterDrop then
			config.monsterDrop = {}
		end
	end

	DropTrackerAnalyser:updateWindow()
end

function DropTrackerAnalyser:updateWindow(ignoreVisible)
	if not DropTrackerAnalyser.window:isVisible() and not ignoreVisible then
		return
	end

	local contentsPanel = DropTrackerAnalyser.window.contentsPanel
	-- lets loop through all the items and flag them for removal
	for _, widget in pairs(contentsPanel.dropItems:getChildren()) do
		widget.toBeRemoved = true
		for _, monsterWidget in pairs(widget.dropMonster:getChildren()) do
			monsterWidget.toBeRemoved = true
		end
	end

	for itemId, config in pairs(DropTrackerAnalyser.trackedItems) do
		local widget = contentsPanel.dropItems:getChildById("ItemPanel_" .. itemId)
		if not widget then
			-- unable to find the item, then it most likely is a
			-- new item being tracked, so lets create it
			widget = g_ui.createWidget('ItemPanel', contentsPanel.dropItems)
			widget:setId("ItemPanel_" .. itemId)
			widget.itemSlot:setItemId(itemId)
			widget.itemName:setText(string.capitalize(short_text(getItemServerName(itemId), 13)))
			widget.drops:setText(formatMoney(config.dropCount, ","))

			for _, monsterDrop in ipairs(config.monsterDrop) do
				local monsterWidget = g_ui.createWidget('MonsterPanel', widget.dropMonster)
				monsterWidget.monster:setOutfit(monsterDrop.outfit)
				monsterWidget.name:setText(string.capitalize(monsterDrop.monsterName))
				monsterWidget.drops:setText("(" ..formatMoney(monsterDrop.count, ",") .. ")")
				monsterDrop.widget = monsterWidget
			end

			widget:updateItemPanelSize()
		else
			-- if we found the item, and applied updates to it, must must
			-- check it to not be removed
			widget.drops:setText(formatMoney(config.dropCount, ","))
			widget.toBeRemoved = nil

			local toBeRemoved = {}
			for id, monsterDrop in ipairs(config.monsterDrop) do
				local monsterWidget = monsterDrop.widget
				if not monsterWidget then
					-- if there is no monsterWidget set, then we need to create it
					local monsterWidget = g_ui.createWidget('MonsterPanel', widget.dropMonster)
					monsterWidget.monster:setOutfit(monsterDrop.outfit)
					monsterWidget.name:setText(string.capitalize(monsterDrop.monsterName))
					monsterWidget.drops:setText("(" ..formatMoney(monsterDrop.count, ",") .. ")")
					-- we also save the reference for later on use
					monsterDrop.widget = monsterWidget
				else
					-- if the monsterWidget is already set, then we must check
					-- if it needs to be removed (time > 45s)
					if (os.time() - monsterDrop.time) > 45 then
						-- this is already being done in the
						-- initial part of this function
						-- monsterWidget.toBeRemoved = true

						-- but lets keep track of the ids to
						-- be removed later on (outside of this
						-- loop)
						table.insert(toBeRemoved, id)
					else
						monsterWidget.drops:setText("(" ..formatMoney(monsterDrop.count, ",") .. ")")
						monsterWidget.toBeRemoved = nil
					end
				end
			end

			if #toBeRemoved == 0 then
				-- dont need to do the update of the heights
				-- now, since it will be done later on during
				-- the widget removal
				widget:updateItemPanelSize()
			end

			-- there is no need to keep it on monsterDrop
			-- table if its removal was already scheduled
			-- and by keeping it, it would be re-added eventually
			for id = #toBeRemoved, 1, -1 do
				table.remove(config.monsterDrop, toBeRemoved[id])
			end
		end
	end

	for _, widget in pairs(contentsPanel.dropItems:getChildren()) do
		if widget.toBeRemoved then
			widget:destroy()
		end

		if widget.dropMonster then
			local destroyedAtLeastOne = false
			for _, monsterWidget in pairs(widget.dropMonster:getChildren()) do
				if monsterWidget.toBeRemoved then
					monsterWidget:destroy()
					destroyedAtLeastOne = true
				end
			end

			if destroyedAtLeastOne then
				widget:updateItemPanelSize()
			end
		end
	end
end

function DropTrackerAnalyser:managerDropItem(itemId, checked)
	if not checked then
		DropTrackerAnalyser.trackedItems[itemId] = nil
		DropTrackerAnalyser:updateWindow()
		return
	end

	if DropTrackerAnalyser.trackedItems[itemId] then
		DropTrackerAnalyser.trackedItems[itemId] = nil
	else
		DropTrackerAnalyser.trackedItems[itemId] = {monsterDrop = {}, recordStartTimestamp = os.time(), dropCount = 0, persistent = true}
	end
	DropTrackerAnalyser:updateWindow()
end

function DropTrackerAnalyser:sendDropedItems(msg, textMessageConsole)
    modules.game_textmessage.messagesPanel.statusLabel:setVisible(true)
    modules.game_textmessage.messagesPanel.statusLabel:setColoredText(msg)
    scheduleEvent(function()
      modules.game_textmessage.messagesPanel.statusLabel:setVisible(false)
    end, 3000)

    local tabName = (modules.game_console.getTabByName("Loot") and "Loot" or "Server Log")
    modules.game_console.addText(textMessageConsole, MessageModes.ChannelManagement, tabName)
end

function DropTrackerAnalyser:tryAddingMonsterDrop(item, monsterName, monsterOutfit, dropedItems, dropedItemIds)
	local itemId = item:getId()
	local tracker = DropTrackerAnalyser.trackedItems[itemId]
	local itemPrice = item:getPriceValue() and item:getPriceValue() or 0
	if not tracker and DropTrackerAnalyser.autoTrackAboveValue == 0 then
		return
	elseif DropTrackerAnalyser.autoTrackAboveValue > 0 and DropTrackerAnalyser.autoTrackAboveValue <= itemPrice then
		tracker = DropTrackerAnalyser.trackedItems[itemId]
		if not tracker then
			DropTrackerAnalyser.trackedItems[itemId] = {monsterDrop = {}, recordStartTimestamp = os.time(), dropCount = 0, persistent = false}
			tracker = DropTrackerAnalyser.trackedItems[itemId]
		end
	elseif not tracker then
		return
	end

	if not dropedItemIds[itemId] then
		dropedItemIds[itemId] = true
		dropedItems[#dropedItems + 1] = itemId
	end

	local now = os.time()
	local itemCount = item:getCount()
	tracker.dropCount = tracker.dropCount + itemCount
	tracker.recordStartTimestamp = now

	-- Reuse the recent row for the same monster instead of creating one widget
	-- per kill. Large hunts used to grow this list rapidly and stall the UI.
	for _, monsterDrop in ipairs(tracker.monsterDrop) do
		if monsterDrop.monsterName == monsterName and (now - monsterDrop.time) <= 45 then
			monsterDrop.count = monsterDrop.count + itemCount
			monsterDrop.time = now
			monsterDrop.outfit = monsterOutfit
			return
		end
	end

	tracker.monsterDrop[#tracker.monsterDrop + 1] = {
		monsterName = monsterName,
		outfit = monsterOutfit,
		time = now,
		count = itemCount
	}
end

function DropTrackerAnalyser:checkMonsterKilled(monsterName, monsterOutfit, dropItems)
	if table.empty(DropTrackerAnalyser.trackedItems) and DropTrackerAnalyser.autoTrackAboveValue == 0 then
		return true
	end

	DropTrackerAnalyser.autoTrackAboveValue = tonumber(DropTrackerAnalyser.autoTrackAboveValue) or 1

	local dropedItems = {}
	local dropedItemIds = {}
	for _, item in pairs(dropItems) do
		DropTrackerAnalyser:tryAddingMonsterDrop(item, monsterName, monsterOutfit, dropedItems, dropedItemIds)
	end

	if #dropedItems ~= 0 then
		local textMessage = {}
		local textMessageConsole = {}
		local first = true
		setStringColor(textMessage, "Valuable loot:", "#f0b400")
		setStringColor(textMessageConsole, " Valuable loot:", "#f0b400")
		for _, itemId in pairs(dropedItems) do
			local name = getItemServerName(itemId)
			if not first then
				setStringColor(textMessage, ",", getItemColor(itemId))
				setStringColor(textMessageConsole, ",", getItemColor(itemId))
			else
				first = false
			end
			setStringColor(textMessage, " "..name, getItemColor(itemId))
			setStringColor(textMessageConsole, " "..name, getItemColor(itemId))
		end

		setStringColor(textMessage, " dropped by "..monsterName.."!", "#f0b400")
		setStringColor(textMessageConsole, " dropped by "..monsterName.."!", "#f0b400")
		scheduleEvent(function()
			DropTrackerAnalyser:sendDropedItems(textMessage, textMessageConsole)
		end, 1)
	end

	-- Widget traversal is the expensive part of the kill callback. Coalesce kills
	-- received in the same frame and update the visible window on the UI queue.
	DropTrackerAnalyser:queueWindowUpdate()
end

function DropTrackerAnalyser:isInDropTracker(itemId)
	local tracker = DropTrackerAnalyser.trackedItems[itemId]
	return tracker and tracker.persistent
end

function onDropTrackerExtra(mousePosition)
	local window = configPopupWindow["dropButton"]
	window:show()
	window:setText('Drop Tracker Configuration')
	window.contentPanel.text:setImageSource('/images/game/analyzer/labels/loot-track')

	window.onEnter = function()
		local value = window.contentPanel.target:getText()
		DropTrackerAnalyser.autoTrackAboveValue = tonumber(value)
		window:hide()
	end
	window.contentPanel.target:setText(tonumber(DropTrackerAnalyser.autoTrackAboveValue) or '0')

	window.contentPanel.ok.onClick = function()
		local value = window.contentPanel.target:getText()
		DropTrackerAnalyser.autoTrackAboveValue = tonumber(value)
		window:hide()
	end
	window.contentPanel.cancel.onClick = function()
		window:hide()
	end
end


function DropTrackerAnalyser:loadConfigJson()
	local config = {
		autoTrackAboveValue = 0,
		trackedItems = {},
	}

	if not LoadedPlayer:isLoaded() then return end

	local file = "/characterdata/" .. LoadedPlayer:getId() .. "/itemtracking.json"
	if g_resources.fileExists(file) then
		local status, result = pcall(function()
			return json.decode(g_resources.readFileContents(file))
		end)

		if not status then
			return g_logger.error("Error while reading characterdata file. Details: " .. result)
		end

		config = result
	end

	-- set droped
  table.clear(DropTrackerAnalyser.trackedItems)
	for _, i in pairs(config.trackedItems) do
		DropTrackerAnalyser.trackedItems[i.objectType] = {monsterDrop = {}, recordStartTimestamp = i.recordStartTimestamp, dropCount = i.dropCount, persistent = true}
	end

	DropTrackerAnalyser.autoTrackAboveValue = config.autoTrackAboveValue
	DropTrackerAnalyser:updateWindow()
end

function DropTrackerAnalyser:saveConfigJson()
	local config = {
		autoTrackAboveValue = DropTrackerAnalyser.autoTrackAboveValue,
		trackedItems = {},
	}

	for itemId, insta in pairs(DropTrackerAnalyser.trackedItems) do
		if insta.persistent then
			config.trackedItems[#config.trackedItems + 1] = {
				dropCount = insta.dropCount,
				objectType = itemId,
				recordStartTimestamp = insta.recordStartTimestamp,
			}
		end
	end

	if not LoadedPlayer:isLoaded() then return end

	local file = "/characterdata/" .. LoadedPlayer:getId() .. "/itemtracking.json"
	local status, result = pcall(function() return json.encode(config, 2) end)
	if not status then
		return g_logger.error("Error while saving profile DropTracker data. Data won't be saved. Details: " .. result)
	end

	if result:len() > 100 * 1024 * 1024 then
		return g_logger.error("Something went wrong, file is above 100MB, won't be saved")
	end

	g_resources.writeFileContents(file, result)
end
