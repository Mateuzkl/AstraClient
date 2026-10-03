local questOptions = {}
local questsData = {}
local questlog = nil

local showHiddenButton = nil
local showCompletedButton = nil
local filterWidget = nil

function init()
	questlog = g_ui.displayUI('questlog')

	questlog:hide()

	connect(g_game, {
		onQuestLog = onGameQuestLog,
		onQuestLine = onGameQuestLine,
		onGameEnd = offline,
		onGameStart = online
	})

	showCompletedButton = questlog:recursiveGetChildById("showCompleted")
	showHiddenButton = questlog:recursiveGetChildById("showHidden")
	filterWidget = questlog:recursiveGetChildById("filterQuests")
end

function terminate()
	disconnect(g_game, {
		onQuestLog = onGameQuestLog,
		onQuestLine = onGameQuestLine,
		onGameEnd = offline,
		onGameStart = online
	})

	-- release the lock only if this module still holds it. Clearing it
	-- unconditionally would unlock the UI while another module's modal is up.
	-- The onDestroy hook in globals.lua already drops the stored reference; this
	-- is what hands focus back to the game panel.
	if g_ui.getCustomInputWidget() == questlog then
		g_client.setInputLockWidget(nil)
	end

	if questlog then
		questlog:destroy()
		questlog = nil
	end

	showCompletedButton = nil
	showHiddenButton = nil
	filterWidget = nil
end

function toggle()
	if questlog:isVisible() then
		hide()
	else
		show()
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

function online()
	loadConfigJson()
	if not questOptions["hiddenQuestLines"] then
		questOptions["hiddenQuestLines"] = {}
	end

	if not questOptions["options"] then
		questOptions["options"] = {
			["showCompletedInQuestLog"] = true,
			["showHiddenInQuestLog"] = false
		}
	end

	if not questOptions["pinnedQuestLines"] then
		questOptions["pinnedQuestLines"] = {}
	end

	g_game.doThing(false)
	g_game.requestQuestLog()
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
		questlog:recursiveGetChildById("questTitle"):setText("No quest line selected")
	end

	questlog:recursiveGetChildById("completQuestsValue"):setText(completedCount)
	questlog:recursiveGetChildById("hiddenQuestsValue"):setText(hiddenCount)
	questList.onChildFocusChange = function(self, selected, oldFocus) onQuestListFocus(selected, oldFocus) end
	questList:focusChild(questList:getFirstChild())

	showCompletedButton:setChecked(canShowCompletedQuest(), true)
	showHiddenButton:setChecked(canShowHiddenQuest(), true)
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
