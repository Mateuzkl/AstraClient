---------------------------
-- Lua code author: R1ck --
-- Company: VICTOR HUGO PERENHA - JOGOS ON LINE --
---------------------------

BestiaryTracker = {}
BestiaryTracker.__index = BestiaryTracker

BestiaryTrackerList = {}

local sortOptions = {}
local firstSection = {}
local secondSection = {}
local renderEvent = nil
local renderGeneration = 0

local sortTypes = {
	NAME = 1,
	COMPLETATION = 2,
	REMAINING_KILLS = 3,
	ASCENDING = 4,
	DESCENDING = 5
}

local function getMonsterList()
	if modules.game_cyclopedia and modules.game_cyclopedia.getCyclopediaMonsterList then
		return modules.game_cyclopedia.getCyclopediaMonsterList()
	end
	return g_things.getMonsterList()
end

local function getMonster(data, monsterList)
	return monsterList[data[1]]
end

function BestiaryTracker.cancelRender()
	renderGeneration = renderGeneration + 1
	if renderEvent then
		removeEvent(renderEvent)
		renderEvent = nil
	end
end

local function scheduleRender(generation, callback)
	renderEvent = scheduleEvent(function()
		renderEvent = nil
		if generation ~= renderGeneration or not bestiaryTrackerWindow or bestiaryTrackerWindow:isDestroyed() then
			return
		end
		callback()
	end, 1)
end

function BestiaryTracker.initSortFields()
	sortOptions[sortTypes.NAME] = true
	sortOptions[sortTypes.COMPLETATION] = false
	sortOptions[sortTypes.REMAINING_KILLS] = false
	sortOptions[sortTypes.ASCENDING] = true
	sortOptions[sortTypes.DESCENDING] = false
end

function BestiaryTracker.updateWidgetTracker(data, widget)
	if not widget then
		return false
	end

	local currentKills = data[2]
	local firstUnlock = data[3]
	local secondUnlock = data[4]
	local thirdUnlock = data[5]

	widget.trackerContainer.killsBar:setTooltip(tr("%s / %s", comma_value(currentKills), comma_value(firstUnlock)))
	widget.trackerContainer1.killsBar1:setTooltip(tr("%s / %s", comma_value(currentKills), comma_value(secondUnlock)))
	widget.trackerContainer2.killsBar2:setTooltip(tr("%s / %s", comma_value(currentKills), comma_value(thirdUnlock)))

	local firstPercent = math.min((currentKills * 100) / firstUnlock, 100)
	widget.trackerContainer.killsBar:setPercent(firstPercent)

	if currentKills > firstUnlock then
		local secondPercent = math.min(((currentKills - firstUnlock) * 100) / (secondUnlock - firstUnlock), 100)
		widget.trackerContainer1.killsBar1:setPercent(secondPercent)
	end

	if currentKills > secondUnlock then
		local thirdPercent = math.min(((currentKills - secondUnlock) * 100) / (thirdUnlock - secondUnlock), 100)
		widget.trackerContainer2.killsBar2:setPercent(thirdPercent)
	end

	if currentKills >= thirdUnlock then
		widget.trackerContainer.killsBar:setImageSource('/game_cyclopedia/images/ui/monster-bar-green')
		widget.trackerContainer1.killsBar1:setImageSource('/game_cyclopedia/images/ui/monster-bar-green')
		widget.trackerContainer2.killsBar2:setImageSource('/game_cyclopedia/images/ui/monster-bar-green')
		widget.trackerContainer.killsBar:setTooltip(widget.trackerContainer.killsBar:getTooltip() .. " (fully unlocked)")
		widget.trackerContainer1.killsBar1:setTooltip(widget.trackerContainer1.killsBar1:getTooltip() .. " (fully unlocked)")
		widget.trackerContainer2.killsBar2:setTooltip(widget.trackerContainer2.killsBar2:getTooltip() .. " (fully unlocked)")
	end

	widget.trackerContainer1.countLabel:setText(comma_value(currentKills))
	return true
end

function BestiaryTracker.updateWidgetShowTracker(data, monsterList)
	local creature = getMonster(data, monsterList)
	if not creature then
		g_logger.warning("[BestiaryTracker]: failed to get outfit for Race " .. data[1])
		return false
	end

	local widget = g_ui.createWidget('BestiPanel', bestiaryTrackerWindow.contentsPanel)
	widget.creature:setOutfit({type = creature[2], auxType = creature[3], head = creature[4], body = creature[5], legs = creature[6], feet = creature[7], addons = creature[8]})
	widget.creature:setAnimate(true)

	local bossName = string.capitalize(creature[1])
	widget.bossName:setText(short_text(bossName, 16))
	widget.redirect:setId(data[1])
	widget:setId(data[1])
	if #bossName >= 16 then
		widget.bossName:setTooltip(bossName)
	end

	local currentKills = data[2]
	local firstUnlock = data[3]
	local secondUnlock = data[4]
	local thirdUnlock = data[5]

	widget.trackerContainer.killsBar:setTooltip(tr("%s / %s", comma_value(currentKills), comma_value(firstUnlock)))
	widget.trackerContainer1.killsBar1:setTooltip(tr("%s / %s", comma_value(currentKills), comma_value(secondUnlock)))
	widget.trackerContainer2.killsBar2:setTooltip(tr("%s / %s", comma_value(currentKills), comma_value(thirdUnlock)))

	local firstPercent = math.min((currentKills * 100) / firstUnlock, 100)
	widget.trackerContainer.killsBar:setPercent(firstPercent)

	if currentKills > firstUnlock then
		local secondPercent = math.min(((currentKills - firstUnlock) * 100) / (secondUnlock - firstUnlock), 100)
		widget.trackerContainer1.killsBar1:setPercent(secondPercent)
	end

	if currentKills > secondUnlock then
		local thirdPercent = math.min(((currentKills - secondUnlock) * 100) / (thirdUnlock - secondUnlock), 100)
		widget.trackerContainer2.killsBar2:setPercent(thirdPercent)
	end

	if currentKills >= thirdUnlock then
		widget.trackerContainer.killsBar:setImageSource('/game_cyclopedia/images/ui/monster-bar-green')
		widget.trackerContainer1.killsBar1:setImageSource('/game_cyclopedia/images/ui/monster-bar-green')
		widget.trackerContainer2.killsBar2:setImageSource('/game_cyclopedia/images/ui/monster-bar-green')
		widget.trackerContainer.killsBar:setTooltip(widget.trackerContainer.killsBar:getTooltip() .. " (fully unlocked)")
		widget.trackerContainer1.killsBar1:setTooltip(widget.trackerContainer1.killsBar1:getTooltip() .. " (fully unlocked)")
		widget.trackerContainer2.killsBar2:setTooltip(widget.trackerContainer2.killsBar2:getTooltip() .. " (fully unlocked)")
	end

	widget.trackerContainer1.countLabel:setText(comma_value(currentKills))

	widget.onMouseRelease = function(widget, mousePos, mouseButton)
		if widget:containsPoint(mousePos) and mouseButton == MouseRightButton then
			local menu = g_ui.createWidget('PopupMenu')
			menu:setGameMenu(true)
			local buttonText = tr("Stop tracking \"%s\"", bossName)
			menu:addOption(tr(buttonText), function() modules.game_cyclopedia.Bestiary.onTrackMonster(false, data[1]) end)
			menu:display(mousePos)
		end
	end

	return true
end

function BestiaryTracker.updateTrackerList()
	local monsterList = getMonsterList()
	table.sort(BestiaryTrackerList, function(a, b)
		local creatureA = getMonster(a, monsterList)
		local creatureB = getMonster(b, monsterList)
		local nameA = creatureA and creatureA[1] or tostring(a[1])
		local nameB = creatureB and creatureB[1] or tostring(b[1])
		local completionA = (a[5] - a[2])
		local completionB = (b[5] - b[2])
    	local percentA = (a[2] / a[5]) * 100
    	local percentB = (b[2] / b[5]) * 100

		if sortOptions[sortTypes.NAME] then
			if sortOptions[sortTypes.ASCENDING] then
				return nameA < nameB
			else
				return nameA > nameB
			end
		end

		if sortOptions[sortTypes.COMPLETATION] then
			if sortOptions[sortTypes.ASCENDING] then
				return percentA < percentB
			else
				return percentA > percentB
			end
		end

		if sortOptions[sortTypes.REMAINING_KILLS] then
			if sortOptions[sortTypes.ASCENDING] then
				return completionA < completionB
			else
				return completionA > completionB
			end
		end
	end)

	for newIndex, data in ipairs(BestiaryTrackerList) do
		local widget = bestiaryTrackerWindow.contentsPanel:getChildById(data[1])
		if widget then
			bestiaryTrackerWindow.contentsPanel:moveChildToIndex(widget, newIndex)
		end
	end

	for _, data in pairs(BestiaryTrackerList) do
		local widget = bestiaryTrackerWindow.contentsPanel:getChildById(data[1])
		BestiaryTracker.updateWidgetTracker(data, widget)
	end
end

function BestiaryTracker.showTrackerData(update)
	BestiaryTracker.cancelRender()
	if not BestiaryTrackerList or #BestiaryTrackerList == 0 then
		bestiaryTrackerWindow.contentsPanel:destroyChildren()
		return
	end

	local monsterList = getMonsterList()
	table.sort(BestiaryTrackerList, function(a, b)
		local creatureA = getMonster(a, monsterList)
		local creatureB = getMonster(b, monsterList)
		local nameA = creatureA and creatureA[1] or tostring(a[1])
		local nameB = creatureB and creatureB[1] or tostring(b[1])
		local completionA = (a[5] - a[2])
		local completionB = (b[5] - b[2])
    	local percentA = (a[2] / a[5]) * 100
    	local percentB = (b[2] / b[5]) * 100

		if sortOptions[sortTypes.NAME] then
			if sortOptions[sortTypes.ASCENDING] then
				return nameA < nameB
			else
				return nameA > nameB
			end
		end

		if sortOptions[sortTypes.COMPLETATION] then
			if sortOptions[sortTypes.ASCENDING] then
				return percentA < percentB
			else
				return percentA > percentB
			end
		end

		if sortOptions[sortTypes.REMAINING_KILLS] then
			if sortOptions[sortTypes.ASCENDING] then
				return completionA < completionB
			else
				return completionA > completionB
			end
		end
	end)

	local reuseWidgets = #BestiaryTrackerList == bestiaryTrackerWindow.contentsPanel:getChildCount()
	if reuseWidgets then
		for _, data in ipairs(BestiaryTrackerList) do
			if not bestiaryTrackerWindow.contentsPanel:getChildById(data[1]) then
				reuseWidgets = false
				break
			end
		end
	end

	if not reuseWidgets then
		bestiaryTrackerWindow.contentsPanel:destroyChildren()
	end

	local generation = renderGeneration
	local nextIndex = 1
	local function renderBatch()
		local data = BestiaryTrackerList[nextIndex]
		if not data then
			return
		end

		if reuseWidgets then
			local widget = bestiaryTrackerWindow.contentsPanel:getChildById(data[1])
			if not widget then
				return
			end
			bestiaryTrackerWindow.contentsPanel:moveChildToIndex(widget, nextIndex)
			BestiaryTracker.updateWidgetTracker(data, widget)
		else
			BestiaryTracker.updateWidgetShowTracker(data, monsterList)
		end

		nextIndex = nextIndex + 1
		if nextIndex <= #BestiaryTrackerList then
			scheduleRender(generation, renderBatch)
		end
	end

	scheduleRender(generation, renderBatch)
end

function BestiaryTracker.onRedirect(widget, isMonster)
	modules.game_cyclopedia.Cyclopedia.open()
	modules.game_cyclopedia.onOptionChange(modules.game_cyclopedia.cyclopediaOptionsPanel:recursiveGetChildById('2'))
	if isMonster then
    g_game.bestiaryMonsterData(tonumber(widget:getId()))
    scheduleEvent(function() modules.game_cyclopedia.Bestiary.setupBackTrackerButton() end, 300)
	end
end

function BestiaryTracker.onSideButtonRedirect()
	modules.game_cyclopedia.Cyclopedia.open()
	modules.game_cyclopedia.onOptionChange(modules.game_cyclopedia.cyclopediaOptionsPanel:recursiveGetChildById('2'))
end

function BestiaryTracker.showSortOptions()
	local sortMenu = g_ui.createWidget('PopupMenu')
    sortMenu:setGameMenu(true)
	local sort1 = sortMenu:addCheckBoxOption(tr('Sort by name'), function() BestiaryTracker.selectFirstSection(sortTypes.NAME) end, "", sortOptions[sortTypes.NAME])
    local sort2 = sortMenu:addCheckBoxOption(tr('Sort by completion percentage'), function() BestiaryTracker.selectFirstSection(sortTypes.COMPLETATION) end, "", sortOptions[sortTypes.COMPLETATION])
    local sort3 = sortMenu:addCheckBoxOption(tr('Sort by remaining kills'), function() BestiaryTracker.selectFirstSection(sortTypes.REMAINING_KILLS) end, "", sortOptions[sortTypes.REMAINING_KILLS])
	sortMenu:addSeparator()
	local sort4 = sortMenu:addCheckBoxOption(tr('Sort ascending'), function() BestiaryTracker.selectSecondSection(sortTypes.ASCENDING) end, "", sortOptions[sortTypes.ASCENDING])
    local sort5 = sortMenu:addCheckBoxOption(tr('Sort descending'), function() BestiaryTracker.selectSecondSection(sortTypes.DESCENDING) end, "", sortOptions[sortTypes.DESCENDING])
    sortMenu:display(g_window.getMousePosition())

	table.insert(firstSection, {type = sortTypes.NAME, widget = sort1})
	table.insert(firstSection, {type = sortTypes.COMPLETATION, widget = sort2})
	table.insert(firstSection, {type = sortTypes.REMAINING_KILLS, widget = sort3})
	table.insert(secondSection, {type = sortTypes.ASCENDING, widget = sort4})
	table.insert(secondSection, {type = sortTypes.DESCENDING, widget = sort5})
end

function BestiaryTracker.selectFirstSection(type)
	if type == sortTypes.NAME and sortOptions[sortTypes.NAME] == true then
		return
	end

	for k, data in pairs(firstSection) do
		if data.type == type then
			sortOptions[data.type] = true
		else
			sortOptions[data.type] = false
		end
	end

	BestiaryTracker.showTrackerData(true)
end

function BestiaryTracker.selectSecondSection(type)
	if type == sortTypes.ASCENDING and sortOptions[sortTypes.ASCENDING] == true then
		return
	end

	for k, data in pairs(secondSection) do
		if data.type == type then
			sortOptions[data.type] = true
		else
			sortOptions[data.type] = false
		end
	end
	BestiaryTracker.showTrackerData(true)
end

function BestiaryTracker.onLogout()
	BestiaryTracker.cancelRender()
	local option = {
		contentHeight = bestiaryTrackerWindow:getHeight(),
		contentMaximized = not bestiaryTrackerWindow.minimizeButton:isOn(),
		sortKey = "completion",
		sortOrder = "ascending"
	}

	if sortOptions[sortTypes.NAME] then
		option.sortKey = "name"
	elseif sortOptions[sortTypes.COMPLETATION] then
		option.sortKey = "completion"
	elseif sortOptions[sortTypes.REMAINING_KILLS] then
		option.sortKey = "remaining"
	end

	if sortOptions[sortTypes.ASCENDING] then
		option.sortOrder = "ascending"
	else
		option.sortOrder = "descending"
	end

	modules.game_sidebars.setBestiaryTrackerOptions(option)
end

function BestiaryTracker.onLogin(bestiaryTrackerWidgetOptions)
	sortOptions[sortTypes.ASCENDING] = false
	sortOptions[sortTypes.DESCENDING] = false
	if not bestiaryTrackerWidgetOptions.sortOrder then
		bestiaryTrackerWidgetOptions.sortOrder = "ascending"
	end

	if not bestiaryTrackerWidgetOptions.sortKey then
		bestiaryTrackerWidgetOptions.sortKey = "name"
	end

	if bestiaryTrackerWidgetOptions.sortOrder == "ascending" then
		sortOptions[sortTypes.ASCENDING] = true
		BestiaryTracker.selectSecondSection(sortTypes.ASCENDING)
	else
		sortOptions[sortTypes.DESCENDING] = true
		BestiaryTracker.selectSecondSection(sortTypes.DESCENDING)
	end

	sortOptions[sortTypes.NAME] = false
	sortOptions[sortTypes.COMPLETATION] = false
	sortOptions[sortTypes.REMAINING_KILLS] = false

	if bestiaryTrackerWidgetOptions.sortKey == "name" then
		sortOptions[sortTypes.NAME] = true
		BestiaryTracker.selectFirstSection(sortTypes.NAME)
	elseif bestiaryTrackerWidgetOptions.sortKey == "completion" then
		sortOptions[sortTypes.COMPLETATION] = true
		BestiaryTracker.selectFirstSection(sortTypes.COMPLETATION)
	else
		sortOptions[sortTypes.REMAINING_KILLS] = true
		BestiaryTracker.selectFirstSection(sortTypes.REMAINING_KILLS)
	end

	BestiaryTracker.updateTrackerList()
end
