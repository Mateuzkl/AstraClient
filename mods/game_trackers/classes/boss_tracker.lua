---------------------------
-- Lua code author: R1ck --
-- Company: VICTOR HUGO PERENHA - JOGOS ON LINE --
---------------------------

BossTracker = {}
BossTracker.__index = BossTracker

BossTrackerList = {}

local sortOptions = {}
local firstSection = {}
local secondSection = {}

local sortFirst = nil
local sortSecond = nil

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

function BossTracker.initSortFields()
	sortOptions[sortTypes.NAME] = true
	sortOptions[sortTypes.COMPLETATION] = false
	sortOptions[sortTypes.REMAINING_KILLS] = false
	sortOptions[sortTypes.ASCENDING] = true
	sortOptions[sortTypes.DESCENDING] = false

	sortFirst = sortTypes.NAME
	sortSecond = sortTypes.ASCENDING
end

function BossTracker.resetWindow()
	if not bossTrackerWindow then
		return
	end

	bossTrackerWindow.contentsPanel:destroyChildren()
end

function BossTracker.showTrackerData()
	-- Same as the bestiary tracker: this is driven by a server push and only builds widgets,
	-- so skip it entirely while the window is closed. toggleBossTracker() re-renders on open.
	if not bossTrackerWindow or not bossTrackerWindow:isVisible() then
		return
	end

	bossTrackerWindow.contentsPanel:destroyChildren()

	if not BossTrackerList or #BossTrackerList == 0 then
		return
	end

	local monsterList = getMonsterList()
	table.sort(BossTrackerList, function(a, b)
		local nameA = monsterList[a[1]] and monsterList[a[1]][1] or tostring(a[1])
		local nameB = monsterList[b[1]] and monsterList[b[1]][1] or tostring(b[1])
		local completionA = (a[5] - a[2])
		local completionB = (b[5] - b[2])
        local percentA = (a[2] / a[5]) * 100
        local percentB = (b[2] / b[5]) * 100

		if sortFirst == sortTypes.NAME then
			if sortSecond == sortTypes.ASCENDING then
				return nameA < nameB
			else
				return nameA > nameB
			end
		end

		if sortFirst == sortTypes.COMPLETATION then
			if sortSecond == sortTypes.ASCENDING then
				return percentA < percentB
			else
				return percentA > percentB
			end
		end

		if sortFirst == sortTypes.REMAINING_KILLS then
			if sortSecond == sortTypes.ASCENDING then
				return completionA < completionB
			else
				return completionA > completionB
			end
		end
	end)
	local layout = bossTrackerWindow.contentsPanel:getLayout()
	layout:disableUpdates()
	for _, data in ipairs(BossTrackerList) do
		local creature = monsterList[data[1]]
		if not creature then
			g_logger.warning("[BossTracker]: failed to get outfit for Race " .. data[1])
			goto continue
		end

		local widget = g_ui.createWidget('BossPanel', bossTrackerWindow.contentsPanel)
		widget.creature:setOutfit({type = creature[2], auxType = creature[3], head = creature[4], body = creature[5], legs = creature[6], feet = creature[7], addons = creature[8]})
		widget:setId(creature[1])

		local bossName = string.capitalize(creature[1])
		widget.bossName:setText(short_text(bossName, 16))
		widget.redirect:setId(bossName)
		if #bossName >= 16 then
			widget.bossName:setTooltip(bossName)
		end

		local currentKills = data[2]
		local firstUnlock = data[3]
		local secondUnlock = data[4]
		local thirdUnlock = data[5]

		local bossName, bossCooldown = modules.game_analyser.BossCooldown:hasCooldown(data[1])
		if not string.empty(bossName) and bossCooldown ~= -1 then
			BossTracker.checkTrackerCooldown(bossName, bossCooldown)
			widget.bossName:setText(short_text(bossName, 14))
			if #bossName >= 14 then
				widget.bossName:setTooltip(bossName)
			end
		end

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

		widget.trackerContainer1.countLabel:setText(data[2])

    	widget.onMouseRelease = function(widget, mousePos, mouseButton)
      		if widget:containsPoint(mousePos) and mouseButton == MouseRightButton then
        		local menu = g_ui.createWidget('PopupMenu')
        		menu:setGameMenu(true)
        		local buttonText = tr("Stop tracking \"%s\"", bossName)
        		menu:addOption(tr(buttonText), function() modules.game_cyclopedia.Bosstiary.checkBosstiaryTrack(nil, false, data[1]) end)
        		menu:display(mousePos)
      		end
    	end

		widget.cooldown:insertLuaCall("onDestroy")
		widget.cooldown.onDestroy = function(self)
			if self.eventCooldown then
				removeEvent(self.eventCooldown)
				self.eventCooldown = nil
			end
		end

		:: continue ::
	end

	layout:enableUpdates()
end

function BossTracker.onRedirect(widget)
	modules.game_cyclopedia.Bosstiary.onSideButtonRedirect(widget:getId())
end

function BossTracker.showSortOptions()
	local sortMenu = g_ui.createWidget('PopupMenu')
    sortMenu:setGameMenu(true)
	local sort1 = sortMenu:addCheckBoxOption(tr('Sort by name'), function() BossTracker.selectFirstSection(sortTypes.NAME) end, "", sortOptions[sortTypes.NAME])
    local sort2 = sortMenu:addCheckBoxOption(tr('Sort by completion percentage'), function() BossTracker.selectFirstSection(sortTypes.COMPLETATION) end, "", sortOptions[sortTypes.COMPLETATION])
    local sort3 = sortMenu:addCheckBoxOption(tr('Sort by remaining kills'), function() BossTracker.selectFirstSection(sortTypes.REMAINING_KILLS) end, "", sortOptions[sortTypes.REMAINING_KILLS])
	sortMenu:addSeparator()
	local sort4 = sortMenu:addCheckBoxOption(tr('Sort ascending'), function() BossTracker.selectSecondSection(sortTypes.ASCENDING) end, "", sortOptions[sortTypes.ASCENDING])
    local sort5 = sortMenu:addCheckBoxOption(tr('Sort descending'), function() BossTracker.selectSecondSection(sortTypes.DESCENDING) end, "", sortOptions[sortTypes.DESCENDING])
    sortMenu:display(g_window.getMousePosition())

	table.insert(firstSection, {type = sortTypes.NAME, widget = sort1})
	table.insert(firstSection, {type = sortTypes.COMPLETATION, widget = sort2})
	table.insert(firstSection, {type = sortTypes.REMAINING_KILLS, widget = sort3})
	table.insert(secondSection, {type = sortTypes.ASCENDING, widget = sort4})
	table.insert(secondSection, {type = sortTypes.DESCENDING, widget = sort5})
end

function BossTracker.selectFirstSection(type)
	if type == sortTypes.NAME and sortOptions[sortTypes.NAME] == true then
		return
	end

	for k, data in pairs(firstSection) do
		if data.type == type then
			sortOptions[data.type] = true
			sortFirst = type
		else
			sortOptions[data.type] = false
		end
	end
	BossTracker.showTrackerData()
end

function BossTracker.selectSecondSection(type)
	if type == sortTypes.ASCENDING and sortOptions[sortTypes.ASCENDING] == true then
		return
	end

	for k, data in pairs(secondSection) do
		if data.type == type then
			sortOptions[data.type] = true
			sortSecond = type
		else
			sortOptions[data.type] = false
		end
	end
	BossTracker.showTrackerData()
end


function BossTracker.onLogout()
	local option = {
		contentHeight = bossTrackerWindow:getHeight(),
		contentMaximized = not bossTrackerWindow.minimizeButton:isOn(),
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

	modules.game_sidebars.setBosstiaryTrackerOptions(option)
end

function BossTracker.onLogin(bossTrackerWidgetOptions)
	sortOptions[sortTypes.ASCENDING] = false
	sortOptions[sortTypes.DESCENDING] = false
	if not bossTrackerWidgetOptions.sortOrder then
		bossTrackerWidgetOptions.sortOrder = "ascending"
	end

	if not bossTrackerWidgetOptions.sortKey then
		bossTrackerWidgetOptions.sortKey = "name"
	end

	if bossTrackerWidgetOptions.sortOrder == "ascending" then
		sortOptions[sortTypes.ASCENDING] = true
		sortSecond = sortTypes.ASCENDING
		BossTracker.selectSecondSection(sortTypes.ASCENDING)
	else
		sortOptions[sortTypes.DESCENDING] = true
		sortSecond = sortTypes.DESCENDING
		BossTracker.selectSecondSection(sortTypes.DESCENDING)
	end

	sortOptions[sortTypes.NAME] = false
	sortOptions[sortTypes.COMPLETATION] = false
	sortOptions[sortTypes.REMAINING_KILLS] = false

	if bossTrackerWidgetOptions.sortKey == "name" then
		sortOptions[sortTypes.NAME] = true
		sortFirst = sortTypes.NAME
		BossTracker.selectFirstSection(sortTypes.NAME)
	elseif bossTrackerWidgetOptions.sortKey == "completion" then
		sortOptions[sortTypes.COMPLETATION] = true
		sortFirst = sortTypes.COMPLETATION
		BossTracker.selectFirstSection(sortTypes.COMPLETATION)
	else
		sortFirst = sortTypes.REMAINING_KILLS
		sortOptions[sortTypes.REMAINING_KILLS] = true
		BossTracker.selectFirstSection(sortTypes.REMAINING_KILLS)
	end
end

function BossTracker.checkTrackerCooldown(name, cooldown)
	local widget = bossTrackerWindow.contentsPanel:recursiveGetChildById(name)
	if not widget then
		return true
	end

	widget.cooldown:setVisible(true)

	widget.bossName:setText(short_text(name, 14))
	if #name >= 14 then
		widget.bossName:setTooltip(name)
	end

	local remainingTime = math.max(0, cooldown - os.time()) 

	if remainingTime == 0 then
		widget.cooldown:setImageSource("/images/icons/icon-cooldown-finished")
		widget.cooldown:setTooltip("No cooldown")
		return true
	end

	if widget.cooldown.eventCooldown then
		removeEvent(widget.cooldown.eventCooldown)
	end

	widget.cooldown:setImageSource("/images/icons/icon-cooldown-running")
	widget.cooldown.eventCooldown = cycleEvent(function() timerCooldown(widget.cooldown, cooldown) end, 1000)
end

function timerCooldown(widget, endTime)
	local remainingText = ""
	local remainingTime = math.max(0, endTime - os.time()) 
	if remainingTime == 0 then
		removeEvent(widget.eventCooldown)
		widget.eventCooldown = nil
		widget:setImageSource("/images/icons/icon-cooldown-finished")
		widget:setTooltip("No cooldown")
		return
	end

	local duration = math.max(1, remainingTime)
	local days = math.floor(duration / 86400)
	local hours = math.floor((duration % 86400) / 3600)
	local minutes = math.floor((duration % 3600) / 60)
	local seconds = math.floor(duration % 60)  -- Calcula os segundos restantes

	if days > 0 then
		remainingText = string.format("%dd %2dh %2dmin", days, hours, minutes)
	elseif hours > 0 then
		remainingText = string.format("%2dh %2dmin", hours, minutes)
	elseif minutes > 0 then
		remainingText = string.format("%2dmin %2ds", minutes, seconds)
	else
		remainingText = string.format("%2ds", seconds)
	end

	widget:setTooltip(remainingText)
end
