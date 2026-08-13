local questOptions = {}
local questsData = {}
local trackedData = {}

local questlog = nil
local trackerWindow = nil

local freeTrackerSlots = 0

local showHiddenButton = nil
local showCompletedButton = nil
local filterWidget = nil
local trackerButton = nil

function init()
	questlog = g_ui.displayUI('questlog')
	trackerWindow = g_ui.createWidget('QuestTracker', m_interface.getRightPanel())

	local scrollbar = trackerWindow:getChildById('miniwindowScrollBar')
	scrollbar:mergeStyle({ ['$!on'] = { }})

	questlog:hide()
	trackerWindow:setup()
	trackerWindow:hide()

	connect(g_game, {
		onQuestLog = onGameQuestLog,
		onQuestLine = onGameQuestLine,
		onQuestTracker = onQuestTracker,
		onUpdateQuestTracker = onUpdateQuestTracker,
		onGameEnd = offline,
		onGameStart = online
	})

	showCompletedButton = questlog:recursiveGetChildById("showCompleted")
	showHiddenButton = questlog:recursiveGetChildById("showHidden")
	filterWidget = questlog:recursiveGetChildById("filterQuests")
	trackerButton = questlog:recursiveGetChildById("showInTracker")
end

function terminate()
	disconnect(g_game, {
		onQuestLog = onGameQuestLog,
		onQuestLine = onGameQuestLine,
		onQuestTracker = onQuestTracker,
		onUpdateQuestTracker = onUpdateQuestTracker,
		onGameEnd = offline,
		onGameStart = online
	})

	if questlog then
		questlog:destroy()
		questlog = nil
	end

	if trackerWindow then
		trackerWindow:destroy()
		trackerWindow = nil
	end

	showCompletedButton = nil
	showHiddenButton = nil
	filterWidget = nil
	trackerButton = nil
end

function toggle()
	if questlog:isVisible() then
		hide()
	else
		show()
	end
end

function toggleTracker()
	if trackerWindow:isVisible() then
		trackerWindow:close()
		modules.game_sidebuttons.setButtonVisible("questTrackerWidget", false)
	else
		trackerWindow:open()
		if m_interface.addToPanels(trackerWindow) then
			trackerWindow:getParent():moveChildToIndex(trackerWindow, #trackerWindow:getParent():getChildren())
			modules.game_sidebuttons.setButtonVisible("questTrackerWidget", true)
		end
	end
end

function show()
	filterWidget:setCurrentIndex(1, true)
	questlog:show()
	questlog:focus()
	updateQuestList()
	g_client.setInputLockWidget(questlog)
end

function hide()
	if questlog then
		questlog:hide()
	end

	g_client.setInputLockWidget(nil)
end

function move(panel, height, index, minimized)
	trackerWindow:setParent(panel)
  trackerWindow:open()

  if minimized then
    trackerWindow:setHeight(height)
    trackerWindow:minimize()
  else
    trackerWindow:maximize()
    trackerWindow:setHeight(height)
  end

	return trackerWindow
end

function online()
	loadConfigJson()
	if not questOptions["hiddenQuestLines"] then
		questOptions["hiddenQuestLines"] = {}
	end

	if not questOptions["options"] then
		questOptions["options"] = {
			["autoTrackNewQuests"] = true,
			["autoUntrackCompletedQuests"] = true,
			["showCompletedInQuestLog"] = true,
			["showHiddenInQuestLog"] = false
		}
	end

	if not questOptions["pinnedQuestLines"] then
		questOptions["pinnedQuestLines"] = {}
	end

	if not questOptions["trackedQuests"] then
		questOptions["trackedQuests"] = {}
	end

	g_game.doThing(false)
	g_game.requestQuestLog()
	g_game.questTrackerFlags(getTrackedMissions(), getAutomaticTrackQuests(), getAutomaticUntrackQuests())
	g_game.doThing(true)
end

function offline()
	saveConfigJson()
	hide()
	g_ui.setInputLockWidget(nil)
end

function onGameQuestLog(quests)
	questsData = {}
	for k, questEntry in pairs(quests) do
		local id, name, completed = unpack(questEntry)
		table.insert(questsData, {id = id, name = name, completed = completed})
	end

	updateQuestList()
end

function onGameQuestLine(questId, questMissions)
	local missionList = questlog:recursiveGetChildById("missionTitle")
	if not missionList then
		return false
	end

	missionList:destroyChildren()
	table.sort(questMissions, function(a, b) return a[1] < b[1] end)

	for k, questMission in pairs(questMissions) do
		local name, description, missionId = unpack(questMission)
		local widget = g_ui.createWidget("QuestLabel", missionList)

		local completed = string.find(name, "(completed)")
		local replaced = string.gsub(name, "%(completed%)", "")

		widget:setActionId(k)
		widget:setBackgroundColor(k % 2 == 0 and "#414141" or "#484848")
		widget:recursiveGetChildById("noteText"):setText(replaced)
		widget:recursiveGetChildById("completeIcon"):setVisible(completed)

		widget.missionDescription = description
		widget.missionId = missionId
	end

	missionList.onChildFocusChange = function(self, selected, oldFocus) onMissionListFocus(selected, oldFocus) end
	questlog:recursiveGetChildById("missionDesc"):setText("")
	missionList:focusChild(missionList:getFirstChild())
end

function updateQuestList(searchText)
	if not questlog then
		return true
	end

	local questList = questlog:recursiveGetChildById("questContent")
	if not questList then
		return false
	end

	questList:destroyChildren()
	local selectedIndex = filterWidget.currentIndex

    table.sort(questsData, function(a, b)
        if isQuestPinned(a.id) ~= isQuestPinned(b.id) then
            return isQuestPinned(a.id)
        end

        if selectedIndex == 1 then
            return a.name < b.name
        elseif selectedIndex == 2 then
            return a.name > b.name
        elseif selectedIndex == 3 then
            return a.completed and not b.completed
        elseif selectedIndex == 4 then
            return not a.completed and b.completed
        end

        return a.name < b.name
    end)

	local completedCount = 0
	local hiddenCount = 0

	for k, data in pairs(questsData) do
		local isPinned = isQuestPinned(data.id)
		local isHidden = isQuestHidden(data.id)

		if isHidden then
			hiddenCount = hiddenCount + 1
			if not canShowHiddenQuest() then
				goto continue
			end
		end

		if data.completed then
			completedCount = completedCount + 1
			if not canShowCompletedQuest() then
				goto continue
			end
		end

		if searchText and not matchText(searchText, data.name) then
			goto continue
		end

		local widget = g_ui.createWidget("QuestLabel", questList)

		widget:setActionId(k)
		widget:setBackgroundColor(k % 2 == 0 and "#414141" or "#484848")
		widget:recursiveGetChildById("noteText"):setText(data.name)

		widget.questId = data.id
		widget.questName = data.name

		local pinWidget = widget:recursiveGetChildById("pinIcon")
		local hiddenWidget = widget:recursiveGetChildById("hideIcon")
		pinWidget.onClick = function() onPinQuestLine(pinWidget, widget) end
		hiddenWidget.onClick = function() onHideQuestLine(hiddenWidget, widget) end

		pinWidget:setChecked(isPinned, true)
		hiddenWidget:setChecked(isHidden, true)

		if data.completed then
			widget:recursiveGetChildById("completeIcon"):setVisible(true)
		end

		:: continue ::
	end

	if questList:getChildCount() == 0 then
		local missionList = questlog:recursiveGetChildById("missionTitle")
		questlog:recursiveGetChildById("missionDesc"):setText("")
		missionList:destroyChildren()
		trackerButton:setChecked(false, true)
		questlog:recursiveGetChildById("questTitle"):setText("No quest line selected")
	end

	questlog:recursiveGetChildById("completQuestsValue"):setText(completedCount)
	questlog:recursiveGetChildById("hiddenQuestsValue"):setText(hiddenCount)
	questList.onChildFocusChange = function(self, selected, oldFocus) onQuestListFocus(selected, oldFocus) end
	questList:focusChild(questList:getFirstChild())

	showCompletedButton:setChecked(canShowCompletedQuest(), true)
	showHiddenButton:setChecked(canShowHiddenQuest(), true)
end

function onQuestTracker(freeSlotQuestCount, quests, updatePinned)
    local list = trackerWindow:recursiveGetChildById("list")
	if not list then
		return true
	end

    list:destroyChildren()

	trackedData = quests
	freeTrackerSlots = freeSlotQuestCount

	table.sort(trackedData, function(a, b)
		local aPinned = isMissionPinned(a[1])
		local bPinned = isMissionPinned(b[1])
	
		if aPinned ~= bPinned then
			return aPinned
		end
		return a[2] < b[2]
	end)

    for _, questData in ipairs(trackedData) do
        local widget = g_ui.createWidget("QuestTrackerLabel", list)
        local missionId, questName, missionName, missionDescription = unpack(questData)

        local completed = missionName:find("%(completed%)")
        local replacedName = missionName:gsub("%(completed%)", "")
        local questShorted = short_text(questName, 18)
        local missionShorted = short_text(replacedName, 18)

        local questNameWidget = widget:recursiveGetChildById("questName")
        local missionNameWidget = widget:recursiveGetChildById("missionName")
        local descriptionWidget = widget:recursiveGetChildById("description")
        local completeIconWidget = widget:recursiveGetChildById("completeIcon")
        local pinIconWidget = widget:recursiveGetChildById("pinIcon")

        questNameWidget:setText(questShorted)
        missionNameWidget:setText(missionShorted)
        descriptionWidget:setText(missionDescription)

        if completed then
            missionNameWidget:setTextOffset("13 -2")
            completeIconWidget:setVisible(true)
        end

        local tooltipText = string.format("%s / %s", questName, replacedName)
        widget:setTooltip(tooltipText)
        pinIconWidget:setTooltip(tooltipText)
		pinIconWidget:setChecked(isMissionPinned(missionId))
		pinIconWidget:setVisible(isMissionPinned(missionId))
		widget.missionId = missionId
		widget.missionCompleted = completed

		if not updatePinned then
			local colorHighlight = "$var-text-cip-color-highlight"
			missionNameWidget:setColor(colorHighlight)
			descriptionWidget:setColor(colorHighlight)
			scheduleEvent(function() onTimedColorChange(widget) end, 4000)
		end

        widget.onHoverChange = onHoveredWidget
		pinIconWidget.onClick = function () onPinTrackerMission(widget) end
		widget.onDoubleClick = function() toggle() end
    end
end

function onUpdateQuestTracker(missionId, missionName, missionDescription)
	local tracketList = trackerWindow:recursiveGetChildById("list")
	for _, widget in pairs(tracketList:getChildren()) do
		if widget.missionId == missionId then
			local missionNameWidget = widget:recursiveGetChildById("missionName")
			local descriptionWidget = widget:recursiveGetChildById("description")
			local completeIconWidget = widget:recursiveGetChildById("completeIcon")

			local completed = missionName:find("%(completed%)")
			local replacedName = missionName:gsub("%(completed%)", "")
			local missionShorted = short_text(replacedName, 18)

			missionNameWidget:setText(missionShorted)
			descriptionWidget:setText(missionDescription)
	
			if completed then
				missionNameWidget:setTextOffset("13 -2")
				completeIconWidget:setVisible(true)
			end

			local colorHighlight = "$var-text-cip-color-highlight"
			missionNameWidget:setColor(colorHighlight)
			descriptionWidget:setColor(colorHighlight)
			scheduleEvent(function() onTimedColorChange(widget) end, 4000)
			break
		end
	end

	for _, questData in ipairs(trackedData) do
		if questData[1] == missionId then
			questData[3] = missionName
			questData[4] = missionDescription
			break
		end
	end
end

function onHoveredWidget(widget, hovered)
	local pinIcon = widget:recursiveGetChildById("pinIcon")
	local pos = g_window.getMousePosition()
    local clickedWidget = widget:recursiveGetChildByPos(pos, false)
    if clickedWidget ~= pinIcon then
		pinIcon:setVisible(hovered)
    end

	if not hovered and pinIcon:isChecked() then
		pinIcon:setVisible(true)
	end

	g_tooltip.onWidgetHoverChange(widget, hovered)
end

function onTimedColorChange(widget)
	if not widget or not g_game.isOnline() then
		return
	end

	local missionNameWidget = widget:recursiveGetChildById("missionName")
	local descriptionWidget = widget:recursiveGetChildById("description")
	if not missionNameWidget or not descriptionWidget then
		return
	end

	missionNameWidget:setColor("$var-text-cip-color")
	descriptionWidget:setColor("$var-text-cip-color")
end

function onPinTrackerMission(widget)
	local pinIconWidget = widget:recursiveGetChildById("pinIcon")
	pinIconWidget:setChecked(not pinIconWidget:isChecked())
	setPinnedTrackedMission(pinIconWidget:isChecked(), widget.missionId)
	onQuestTracker(freeTrackerSlots, trackedData, true)
end

function onQuestListFocus(selected, oldFocus)
	if oldFocus then
		local oldFocusedIndex = oldFocus:getActionId()
		oldFocus:setBackgroundColor(oldFocusedIndex % 2 == 0 and "#414141" or "#484848")
		oldFocus:recursiveGetChildById("pinIcon"):setVisible(false)
		oldFocus:recursiveGetChildById("hideIcon"):setVisible(false)
		oldFocus:recursiveGetChildById("noteText"):setColor("#c0c0c0")
	end

	if selected then
		selected:recursiveGetChildById("pinIcon"):setVisible(true)
		selected:recursiveGetChildById("hideIcon"):setVisible(true)
		selected:recursiveGetChildById("noteText"):setColor("#f4f4f4")

		g_game.doThing(false)
		g_game.requestQuestLine(selected.questId)
		g_game.doThing(true)

		questlog:recursiveGetChildById("questTitle"):setText(selected.questName)
		trackerButton:setEnabled(freeTrackerSlots > 0)
		trackerButton:setTooltip(freeTrackerSlots == 0 and "You reached the maximum number of tracked quests." or "")
	end
end

function onMissionListFocus(selected, oldFocus)
	if oldFocus then
		local oldFocusedIndex = oldFocus:getActionId()
		oldFocus:setBackgroundColor(oldFocusedIndex % 2 == 0 and "#414141" or "#484848")
		oldFocus:recursiveGetChildById("noteText"):setColor("#c0c0c0")
	end

	if selected then
		selected:recursiveGetChildById("noteText"):setColor("#f4f4f4")
		questlog:recursiveGetChildById("missionDesc"):setText(selected.missionDescription)
	end

	trackerButton:setChecked(isMissionTracked(selected.missionId), true)
end

function onVisibleCheck(widgetId, checked)
	if widgetId == "showCompleted" then
		setCanShowCompletedQuest(checked)
	elseif widgetId == "showHidden" then
		setCanShowHiddenQuest(checked)
	end

	updateQuestList()
end

function onPinQuestLine(widget, questWidget)
	widget:setChecked(not widget:isChecked(), true)

	setPinnedQuestLine(widget:isChecked(), questWidget.questId)
	updateQuestList()
end

function onHideQuestLine(widget, questWidget)
	widget:setChecked(not widget:isChecked(), true)

	setHiddenQuestLine(widget:isChecked(), questWidget.questId)
	updateQuestList()
end

function onSearchQuest(text)
	if string.empty(text) then
		updateQuestList()
	else
		updateQuestList(text)
	end
end

function clearSearchText()
	local searchField = questlog:recursiveGetChildById("searchfilter")
	if not string.empty(searchField:getText()) then
		updateQuestList()
	end
	questlog:recursiveGetChildById("searchfilter"):clearText(true)
end

function onTrackQuest()
	local missionList = questlog:recursiveGetChildById("missionTitle")
	if not missionList then
		return false
	end

	local selectedWidget = missionList:getFocusedChild()
	if not selectedWidget then
		return false
	end

	setTrackedMission(selectedWidget.missionId)
	g_game.questTrackerFlags(getTrackedMissions(), getAutomaticTrackQuests(), getAutomaticUntrackQuests())
end

function onQuestTrackerExtra(mousePosition)
	if cancelNextRelease then
		cancelNextRelease = false
		return false
	end

		local menu = g_ui.createWidget('PopupMenu')
		menu:setGameMenu(true)
		menu:addOption(tr('Remove all quests'), function() removeAllQuests() return end)
		menu:addOption(tr('Remove completed quests'), function() removeCompletedQuests() return end)
		menu:addSeparator()
		menu:addCheckBoxOption(tr('Automatically track new quests'), function() automaticTrackQuests() end, "", getAutomaticTrackQuests())
		menu:addCheckBoxOption(tr('Automatically untrack completed quests'), function() automaticUntrackQuests() end, "", getAutomaticUntrackQuests())
		menu:display(mousePosition)
	return true
end

function removeAllQuests()
	questOptions["trackedQuests"] = {}
	g_game.questTrackerFlags({}, getAutomaticTrackQuests(), getAutomaticUntrackQuests())
end

function removeCompletedQuests()
	local tracketList = trackerWindow:recursiveGetChildById("list")
	for _, widget in pairs(tracketList:getChildren()) do
		if widget.missionCompleted then
			setTrackedMission(widget.missionId)
		end
	end
	g_game.questTrackerFlags(getTrackedMissions(), getAutomaticTrackQuests(), getAutomaticUntrackQuests())
end

function automaticTrackQuests()
	local checked = questOptions["options"]["autoTrackNewQuests"]
	questOptions["options"]["autoTrackNewQuests"] = not checked
end

function automaticUntrackQuests()
	local checked = questOptions["options"]["autoUntrackCompletedQuests"]
	questOptions["options"]["autoUntrackCompletedQuests"] = not checked
end

function getAutomaticTrackQuests()
	return questOptions["options"]["autoTrackNewQuests"]
end

function getAutomaticUntrackQuests()
	return questOptions["options"]["autoUntrackCompletedQuests"]
end

function canShowCompletedQuest()
	return questOptions["options"]["showCompletedInQuestLog"]
end

function canShowHiddenQuest()
	return questOptions["options"]["showHiddenInQuestLog"]
end

function setCanShowCompletedQuest(value)
	questOptions["options"]["showCompletedInQuestLog"] = value
end

function setCanShowHiddenQuest(value)
	questOptions["options"]["showHiddenInQuestLog"] = value
end

function isQuestHidden(questId)
	return table.contains(questOptions["hiddenQuestLines"], questId)
end

function isQuestPinned(questId)
	return table.contains(questOptions["pinnedQuestLines"], questId)
end

function getTrackedMissions()
	local quests = {}
	for _, data in pairs(questOptions["trackedQuests"]) do
		if type(data) == "number" then
			questOptions["trackedQuests"] = {}
			return quests
		end

		table.insert(quests, data["id"])
	end
	return quests
end

function setTrackedMission(missionId)
    for index, quest in ipairs(questOptions["trackedQuests"]) do
        if quest.id == missionId then
            table.remove(questOptions["trackedQuests"], index)
            return
        end
    end
    table.insert(questOptions["trackedQuests"], {id = missionId, isPinned = false})
end

function isMissionTracked(missionId)
	for index, quest in ipairs(questOptions["trackedQuests"]) do
        if quest.id == missionId then
			return true
		end
	end
	return false
end

function isMissionPinned(missionId)
	if table.empty(questOptions["trackedQuests"]) then
		return false
	end

	for index, quest in ipairs(questOptions["trackedQuests"]) do
        if quest.id == missionId and quest.isPinned then
			return true
		end
	end
	return false
end

function setPinnedQuestLine(insert, questId)
	if insert then
		table.insert(questOptions["pinnedQuestLines"], questId)
		return true
	end

	for k, v in pairs(questOptions["pinnedQuestLines"]) do
		if v == questId then
			table.remove(questOptions["pinnedQuestLines"], k)
		end
	end
end

function setHiddenQuestLine(insert, questId)
	if insert then
		table.insert(questOptions["hiddenQuestLines"], questId)
		return true
	end

	for k, v in pairs(questOptions["hiddenQuestLines"]) do
		if v == questId then
			table.remove(questOptions["hiddenQuestLines"], k)
		end
	end
end

function setPinnedTrackedMission(insert, missionId)
	for k, v in pairs(questOptions["trackedQuests"]) do
		if v.id == missionId then
			v.isPinned = insert
		end
	end
end

function loadConfigJson()
	if not LoadedPlayer:isLoaded() then
		return
	end
	
	local file = "/characterdata/" .. LoadedPlayer:getId() .. "/questtracking.json"
	if g_resources.fileExists(file) then
		local status, result = pcall(function()
		return json.decode(g_resources.readFileContents(file))
		end)
	
		if not status then
			return false
		end
	
		questOptions = result
	end
end

function saveConfigJson()
	if not LoadedPlayer:isLoaded() then return end

	local file = "/characterdata/" .. LoadedPlayer:getId() .. "/questtracking.json"
	local status, result = pcall(function() return json.encode(questOptions, 2) end)
	if not status then
		return g_logger.error("Error while saving profile characterdata questtracking. Data won't be saved. Details: " .. result)
	end

	if result:len() > 100 * 1024 * 1024 then
		return g_logger.error("Something went wrong, file is above 100MB, won't be saved")
	end
	g_resources.writeFileContents(file, result)
end
