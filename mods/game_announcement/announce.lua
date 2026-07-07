Announcement = {
	AnnouncementListWindow = nil,
	currentId = 0,
	redirect = '',
	data = {},
	worlds = {},
	lastClickedWidget = nil,
	lastWorldClicked = nil,
	radioGroup = nil,
	tempOptions = {}
}

Announcement.__index = Announcement

local blinkEvent = nil
local announcementWindow = nil
local backgroundPanel = nil
local linkWindow = nil
local pollWindow = nil

function Announcement.init()
	local self = Announcement
	self.AnnouncementListWindow = g_ui.displayUI('announce')
	self.AnnouncementListWindow:hide()

	self.radioGroup = UIRadioGroup.create()
	self.radioGroup:addWidget(self.AnnouncementListWindow:recursiveGetChildById('announcementFilter'))
	self.radioGroup:addWidget(self.AnnouncementListWindow:recursiveGetChildById('createPollFilter'))
	self.radioGroup:addWidget(self.AnnouncementListWindow:recursiveGetChildById('redirectUrlFilter'))

	self.radioGroup:selectWidget(self.AnnouncementListWindow:recursiveGetChildById('announcementFilter'))

	createBackgroundPanel()
	backgroundPanel:hide()

	linkWindow = g_ui.createWidget('SetupLink', rootWidget)
	linkWindow:hide()

	pollWindow = g_ui.createWidget('SetupPool', rootWidget)
	pollWindow:hide()

	connect(g_game, {
		onAnnouncementMessage = onAnnouncementMessage,
		onAnnouncementList = onAnnouncementList
	})
	connect(g_game, { onGameStart = onGameStart })
	connect(g_game, { onGameEnd = onGameEnd })
	connect(self.radioGroup, { onSelectionChange = onSelectionChange })

	if g_game.isOnline() then
		onGameStart()
	end
end

function onGameStart()
	local benchmark = g_clock.millis()
	if blinkEvent then
		removeEvent(blinkEvent)
		local blinkWarningPanel = rootWidget:recursiveGetChildById('blinkWarningPanel')
		blinkWarningPanel:setVisible(false)
		blinkEvent = nil
	end

	if announcementWindow then
		announcementWindow:destroy()
		announcementWindow = nil
		g_client.setInputLockWidget(nil)
	end

	if Announcement.AnnouncementListWindow:isVisible() then
		Announcement.AnnouncementListWindow:hide()
		g_client.setInputLockWidget(nil)
	end

	Announcement.data = {}

	consoleln("Announcement loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function onClickBlink()
	local blinkWarningPanel = rootWidget:recursiveGetChildById('blinkWarningPanel')
	local data = Announcement.data[1]
	if not data then
		removeEvent(blinkEvent)
		blinkWarningPanel:setVisible(false)
		return
	end
	local newData = {}
	for i = 2, #Announcement.data do
		newData[i - 1] = Announcement.data[i]
	end
	g_game.readAnnouncement(data.id, 0)

	Announcement.data = newData
	if #Announcement.data == 0 then
		removeEvent(blinkEvent)
		blinkWarningPanel:setVisible(false)
	else
		blinkCount:setImageSource('/images/game/items/tier-' .. math.min(10, #Announcement.data))

		local newxtdata = Announcement.data[1]
		if newxtdata and newxtdata.type == 1 then
			blinkWarning:setImageSource('/images/ui/notification/poll-up')
		else
			blinkWarning:setImageSource('/images/ui/notification/notification-up')
		end
	end
	if data.endTime > os.time() then
		showAnnouncementMessage(data)
	end
end

function onGameEnd()
	if blinkEvent then
		removeEvent(blinkEvent)
		blinkWarningPanel:setVisible(false)
		blinkEvent = nil
	end

	if announcementWindow then
		announcementWindow:destroy()
		announcementWindow = nil
		g_client.setInputLockWidget(nil)
	end

	if Announcement.AnnouncementListWindow:isVisible() then
		Announcement.AnnouncementListWindow:hide()
		g_client.setInputLockWidget(nil)
	end
end

function showBlinkWarning()
	local blinkWarningPanel = rootWidget:recursiveGetChildById('blinkWarningPanel')
	blinkWarningPanel:setVisible(true)

	local blinkCount = blinkWarningPanel:recursiveGetChildById('blinkWarningCount')
	local total = math.min(10, #Announcement.data)
	blinkCount:setImageSource('/images/game/items/tier-' .. total)

	local blinkWarning = blinkWarningPanel:getChildById('blinkWarning')

	if Announcement.data[1] and Announcement.data[1].type == 1 then
		blinkWarning:setImageSource('/images/ui/notification/poll-up')
	else
		blinkWarning:setImageSource('/images/ui/notification/notification-up')
	end

	blinkWarning.onClick = onClickBlink
end

function insertLineBreaks(text, maxChars)
    local result = ""
    local length = #text
    local currentPos = 1

    while currentPos <= length do
        local endPos = currentPos + maxChars - 1
        if endPos > length then
            endPos = length
        end

        local chunk = text:sub(currentPos, endPos)

        if endPos < length then
            local lastSpace = chunk:find("([^%s]-)%s*$")
            if lastSpace then
                chunk = text:sub(currentPos, currentPos + lastSpace - 2)
                endPos = currentPos + lastSpace - 2
            end
        end

        result = result .. chunk .. "\n"
        -- Avança a posição para após o trecho
        currentPos = endPos + 1
    end

    if result:sub(-1) == "\n" then
        result = result:sub(1, -2)
    end

    return result
end

function showNormalAnnouncement(data)
	if announcementWindow then
		announcementWindow:destroy()
		announcementWindow = nil
	end

	announcementWindow = g_ui.createWidget("AnnounceWindow", rootWidget)
	g_client.setInputLockWidget(announcementWindow)

	local textWidget = announcementWindow:recursiveGetChildById('announceList')

	textWidget:setText(data.message)

	announcementWindow:show()
	announcementWindow:raise()
	announcementWindow:focus()

	local okFunction = function()
		g_client.setInputLockWidget(nil)
		announcementWindow:destroy()
		announcementWindow = nil
		modules.game_console.getConsole():focus()
	end

	local closeButton = announcementWindow:recursiveGetChildById('closeButton')
	closeButton.onClick = okFunction
	announcementWindow.onEnter = okFunction
	announcementWindow.onEscape = okFunction

	local redirectButton = announcementWindow:recursiveGetChildById('openLinkButton')
	local highlightBorder = announcementWindow:recursiveGetChildById('borderImage')
	redirectButton:setVisible(data.type == 2)
	highlightBorder:setVisible(data.type == 2)
	redirectButton.onClick = function()
		-- send protocol
		if not data.onlyTeste then
			g_game.readAnnouncement(data.id, 2)
		end
		g_platform.openUrl(data.link, false)
		okFunction()
	end
end

function showPollAnnouncement(data)
	if announcementWindow then
		announcementWindow:destroy()
		announcementWindow = nil
	end

	announcementWindow = g_ui.createWidget("PollWindow", rootWidget)
	g_client.setInputLockWidget(announcementWindow)


	local questionList = announcementWindow:recursiveGetChildById('questionList')
	questionList:destroyChildren()

	local label = g_ui.createWidget('VoteLabel', questionList)
	label:setText(insertLineBreaks(data.message, 52))

	local radioGroup = UIRadioGroup.create()
	local answerList = announcementWindow:recursiveGetChildById('answerList')
	answerList:destroyChildren()

	local sorted = data.options
	table.sort(sorted, function(a, b) return a.id > b.id end)
	for _, answer in pairs(sorted) do
		local voteWidget = g_ui.createWidget('VoteOption', answerList)
		voteWidget:setText(answer.option)
		voteWidget:setActionId(answer.id)
		radioGroup:addWidget(voteWidget)

		local descriptionWidget = g_ui.createWidget('VoteLabel', answerList)
		descriptionWidget:setText(insertLineBreaks(answer.description, 52))
	end

	radioGroup.onSelectionChange = function(widget, selectedWidget)
		announcementWindow:recursiveGetChildById('voteButton'):setEnabled(selectedWidget ~= nil)
	end

	local closeButtonAction = function()
		g_client.setInputLockWidget(nil)
		if radioGroup then
			radioGroup:destroy()
			radioGroup = nil
		end
		announcementWindow:destroy()
		announcementWindow = nil

		modules.game_console.getConsole():focus()
		onClickBlink()
	end

	local voteButtonAction = function()
		local selected = radioGroup:getSelectedWidget()
		if not selected then
			return
		end

		if not data.onlyTeste then
			g_game.voteAnnouncement(data.id, selected:getActionId())
		end
		closeButtonAction()
	end

	local closeButton = announcementWindow:recursiveGetChildById('closeButton')
	closeButton.onClick = closeButtonAction
	announcementWindow.onEscape = closeButtonAction

	local voteButton = announcementWindow:recursiveGetChildById('voteButton')
	voteButton.onClick = voteButtonAction
	announcementWindow.onEnter = voteButtonAction
	voteButton:setEnabled(false)
end

function showAnnouncementMessage(data)
	if data.type ~= 1 then
		showNormalAnnouncement(data)
	else
		showPollAnnouncement(data)
	end
end

function onAnnouncementMessage(data)
	Announcement.data = data
	g_window.flash()
	showBlinkWarning()
end

function Announcement.terminate()
	local self = Announcement

	if self.lastClickedWidget then
		self.lastClickedWidget:destroy()
		self.lastClickedWidget = nil
	end

	if self.lastWorldClicked then
		self.lastWorldClicked:destroy()
		self.lastWorldClicked = nil
	end

	if backgroundPanel then
		backgroundPanel:destroy()
		backgroundPanel = nil
	end

	if linkWindow then
		linkWindow:destroy()
		linkWindow = nil
	end

	if pollWindow then
		pollWindow:destroy()
		pollWindow = nil
	end

	disconnect(g_game, {
		onAnnouncementMessage = onAnnouncementMessage,
		onAnnouncementList = onAnnouncementList
	})
	disconnect(g_game, { onGameStart = onGameStart })
	disconnect(g_game, { onGameEnd = onGameEnd })
	disconnect(self.radioGroup, { onSelectionChange = onSelectionChange })

	if self.radioGroup then
		self.radioGroup:destroy()
		self.radioGroup = nil
	end

	if self.AnnouncementListWindow then
		self.AnnouncementListWindow:destroy()
		self.AnnouncementListWindow = nil
		g_client.setInputLockWidget(nil)
	end
end

function moveLabelToDisplayWorlds(label)
	local worldName = label:getText()
	local id = label:getActionId()
	local displayWorlds = Announcement.AnnouncementListWindow:recursiveGetChildById('displayWorlds')
	label:destroy()
	label = nil

	local displayWorldLabels = {}
	table.insert(displayWorldLabels, { worldName = worldName, id = id })
	for _, child in pairs(displayWorlds:getChildren()) do
		local worldName = child:getText()
		local id = child:getActionId()

		table.insert(displayWorldLabels, { worldName = worldName, id = id })
	end

	table.sort(displayWorldLabels, function(a, b) return a.worldName < b.worldName end)
	displayWorlds:destroyChildren()
	for _, data in ipairs(displayWorldLabels) do
		local newlabel = g_ui.createWidget('Label', displayWorlds)
		newlabel:setText(data.worldName)
		newlabel:setActionId(data.id)
		newlabel.onDoubleClick = moveLabelToGameWorld
	end
end

function moveLabelToGameWorld(label)
	local worldName = label:getText()
	local id = label:getActionId()
	label:destroy()
	label = nil

	local gamerWorlds = Announcement.AnnouncementListWindow:recursiveGetChildById('gamerWorlds')
	local gameWorldLabels = {}
	table.insert(gameWorldLabels, { worldName = worldName, id = id })
	for _, child in pairs(gamerWorlds:getChildren()) do
		local worldName = child:getText()
		local id = child:getActionId()

		table.insert(gameWorldLabels, { worldName = worldName, id = id })
	end

	table.sort(gameWorldLabels, function(a, b) return a.worldName < b.worldName end)
	gamerWorlds:destroyChildren()
	for _, data in ipairs(gameWorldLabels) do
		local newlabel = g_ui.createWidget('Label', gamerWorlds)
		newlabel:setText(data.worldName)
		newlabel:setActionId(data.id)

		newlabel.onDoubleClick = moveLabelToDisplayWorlds
		newlabel.onMouseRelease = function(self, mousePos, mouseButton)
			if Announcement.lastWorldClicked then
				Announcement.lastWorldClicked:setBackgroundColor("#414141")
				Announcement.lastWorldClicked:setColor("#FFFFFF")
			end

			newlabel:setBackgroundColor("#585858")
			newlabel:setColor("#FFFFFF")
			Announcement.lastWorldClicked = newlabel
		end
	end
end

function addWorld()
	local displayWorlds = Announcement.AnnouncementListWindow:recursiveGetChildById('displayWorlds')
	displayWorlds:destroyChildren()

	local gamerWorlds = Announcement.AnnouncementListWindow:recursiveGetChildById('gamerWorlds')
	gamerWorlds:destroyChildren()

	local ordernedWorlds = {}
	for id, world in pairs(Announcement.worlds) do
		table.insert(ordernedWorlds, { id = id, world = world })
	end

	table.sort(ordernedWorlds, function(a, b) return a.world < b.world end)

	for id, world in ipairs(ordernedWorlds) do
		local newlabel = g_ui.createWidget('Label', displayWorlds)
		newlabel:setText(world.world)
		newlabel:setActionId(world.id)
		newlabel.onDoubleClick = moveLabelToGameWorld
		newlabel.onMouseRelease = function(self, mousePos, mouseButton)
			if Announcement.lastWorldClicked then
				Announcement.lastWorldClicked:setBackgroundColor("#414141")
				Announcement.lastWorldClicked:setColor("#FFFFFF")
			end

			newlabel:setBackgroundColor("#585858")
			newlabel:setColor("#FFFFFF")
			Announcement.lastWorldClicked = newlabel
		end
	end
end

function onAnnouncementList(announcementList, worlds)
	Announcement.currentId = 0
	Announcement.redirect = ''
	Announcement.worlds = worlds
	backgroundPanel:show()
	setNewAnnouncement()
	Announcement.AnnouncementListWindow:show()
	Announcement.AnnouncementListWindow:recursiveGetChildById('announcementTitle'):recursiveFocus(2)
	local displayWorlds = Announcement.AnnouncementListWindow:recursiveGetChildById('displayWorlds')
	displayWorlds:destroyChildren()

	local gamerWorlds = Announcement.AnnouncementListWindow:recursiveGetChildById('gamerWorlds')
	gamerWorlds:destroyChildren()
	local ordernedWorlds = {}
	for id, world in pairs(worlds) do
		table.insert(ordernedWorlds, { id = id, world = world })
	end

	table.sort(ordernedWorlds, function(a, b) return a.world < b.world end)

	for id, world in ipairs(ordernedWorlds) do
		local label = g_ui.createWidget('Label', gamerWorlds)
		label:setText(world.world)
		label:setActionId(world.id)
		label.onDoubleClick = moveLabelToDisplayWorlds
		label.onMouseRelease = function(self, mousePos, mouseButton)
			if Announcement.lastWorldClicked then
				Announcement.lastWorldClicked:setBackgroundColor("#414141")
				Announcement.lastWorldClicked:setColor("#FFFFFF")
			end

			label:setBackgroundColor("#585858")
			label:setColor("#FFFFFF")
			Announcement.lastWorldClicked = label
		end
	end

	local announcementListPanel = Announcement.AnnouncementListWindow:recursiveGetChildById('historyContent')
	announcementListPanel:destroyChildren()

	table.sort(announcementList, function(a, b) return a.startTime > b.startTime end)
	for _, announcement in ipairs(announcementList) do
		local label = g_ui.createWidget('ListAnnouncementLabel', announcementListPanel)
		label:setId(announcement.id)
		label:setText(short_text(announcement.title, 50))
		local tooltip = ''
		for _, data in pairs(announcement.worldViews) do
			tooltip = string.format("%s%s - %d views\n", tooltip,
				(Announcement.worlds[data.id] and Announcement.worlds[data.id] or 'World' .. data.id), data.count)
		end

		label:setTooltip(tooltip)
		label.onDoubleClick = function()
			configureAnnouncementLabel(announcement, ordernedWorlds)
		end

		label.onMouseRelease = function(self, mousePos, mouseButton)
			if Announcement.lastClickedWidget then
				Announcement.lastClickedWidget:setBackgroundColor("#414141")
				Announcement.lastClickedWidget:setColor("#FFFFFF")
			end

			label:setBackgroundColor("#585858")
			label:setColor("#FFFFFF")
			Announcement.lastClickedWidget = label

			if mouseButton == MouseRightButton then
				local menu = g_ui.createWidget('PopupMenu')
				menu:addOption(tr('Delete'),
					function()
						g_game.sendAnnouncementAction(announcement.id, 0); closeAnnouncementList()
					end)
				menu:addOption(tr('Re-sent'),
					function()
						g_game.sendAnnouncementAction(announcement.id, 1); closeAnnouncementList()
					end)
				menu:display(mousePos)
			end
		end
	end

	g_client.setInputLockWidget(Announcement.AnnouncementListWindow)
end

function updateViewersCount(announcement)
	if not announcement.worldViews then return end

	local viewersCountLabel = Announcement.AnnouncementListWindow:recursiveGetChildById('viewersCountLabel')
	local viewersContent = Announcement.AnnouncementListWindow:recursiveGetChildById('viewersContent')

	local count = 0
	for _, data in pairs(announcement.worldViews) do
		count = count + data.count
	end

	local viewCountText = "Viewers: " .. count
	if announcement.type == 2 then
		local readerCount = 0
		for _, data in pairs(announcement.redirectPlayers) do
			readerCount = readerCount + data.count
		end
		viewCountText = viewCountText .. " - Redirect: " .. readerCount
	end

	viewersCountLabel:setText(viewCountText)

	viewersContent:destroyChildren()
end

function closeAnnouncementList()
	backgroundPanel:hide()
	linkWindow:hide()
	pollWindow:hide()
	Announcement.AnnouncementListWindow:hide()
	setNewAnnouncement()
	g_client.setInputLockWidget(nil)
	modules.game_console.getConsole():recursiveFocus(2)
end

function onEditTimeDate(widget, text, type)
	local number = tonumber(text)

	-- If text isn't a valid number, clear the field
	if not number then
		widget:setText('', false)
		return
	end

	-- If number is negative, clear the field
	if number < 0 then
		widget:setText('', false)
		return
	end

	-- Check based on widget ID
	if type == "hour" then
		if number > 23 then
			widget:setText('23', false)
		end
	elseif type == "minutes" then
		if number > 59 then
			widget:setText('59', false)
		end
	elseif type == "day" then
		if number > 31 then
			widget:setText('31', false)
		end
	elseif type == "month" then
		if number > 12 then
			widget:setText('12', false)
		end
	elseif type == "year" then
		-- Only checking for negative values as per original code
		-- You might want to add an upper limit for year if needed
	end
	widget:setCursorPos(-1)
end

function onEditAnnouncement(text)
	Announcement.AnnouncementListWindow:recursiveGetChildById('sendButton'):setEnabled(#text > 0)
end

function sendAnnouncement()
	local self = Announcement
	local currentTimeTable = os.date('*t')
	local hour = tonumber(self.AnnouncementListWindow:recursiveGetChildById('hour'):getText()) or currentTimeTable.hour
	local minutes = tonumber(self.AnnouncementListWindow:recursiveGetChildById('minute'):getText()) or
		currentTimeTable.min
	local day = tonumber(self.AnnouncementListWindow:recursiveGetChildById('day'):getText()) or currentTimeTable.day
	local month = tonumber(self.AnnouncementListWindow:recursiveGetChildById('month'):getText()) or
		currentTimeTable.month
	local year = tonumber(self.AnnouncementListWindow:recursiveGetChildById('year'):getText()) or currentTimeTable.year

	local startTime = os.time { year = year, month = month, day = day, hour = hour, min = minutes, sec = 0 }

	local endHour = tonumber(self.AnnouncementListWindow:recursiveGetChildById('endHour'):getText()) or
		math.min(23, currentTimeTable.hour + 1)
	local endMinutes = tonumber(self.AnnouncementListWindow:recursiveGetChildById('endMinute'):getText()) or
		math.min(59, currentTimeTable.min + 1)
	local endDay = tonumber(self.AnnouncementListWindow:recursiveGetChildById('endDay'):getText()) or
		currentTimeTable.day
	local endMonth = tonumber(self.AnnouncementListWindow:recursiveGetChildById('endMonth'):getText()) or
		currentTimeTable.month
	local endYear = tonumber(self.AnnouncementListWindow:recursiveGetChildById('endYear'):getText()) or
		currentTimeTable.year

	if endHour < hour then
		endDay = endDay + 1
	elseif endHour == hour and endMinutes <= minutes then
		endDay = endDay + 1
	end

	if endDay > 31 then
		endDay = 31
	end

	if endMonth > 12 then
		endMonth = 12
	end

	local endTime = os.time { year = endYear, month = endMonth, day = endDay, hour = endHour, min = endMinutes, sec = 0 }

	local message = self.AnnouncementListWindow:recursiveGetChildById('announcementContent'):getDisplayedText()

	if #message == 0 then
		return
	end

	if not string.find(message, '\n') then
		message = insertLineBreaks(message, 78)
	end

	local worlds = {}
	local displayWorlds = self.AnnouncementListWindow:recursiveGetChildById('displayWorlds')
	for _, child in pairs(displayWorlds:getChildren()) do
		table.insert(worlds, child:getActionId())
	end

	local title = self.AnnouncementListWindow:recursiveGetChildById('announcementTitle'):getText()

	local type = self.radioGroup:getSelectedWidget():getId()
	if type == 'createPollFilter' then
		type = 1
	elseif type == 'redirectUrlFilter' then
		type = 2
	else
		type = 0
	end

	if type == 1 and #Announcement.tempOptions < 2 then
		modules.game_textmessage.displayGameMessage(tr('You need to add at least two options to create a poll.'))
		return
	end

	local options = {}
	for id, child in ipairs(Announcement.tempOptions) do
		local displayId = child.id or id
		table.insert(options, { id = displayId, option = child.option, description = child.description })
	end

	if Announcement.currentId > 0 then
		g_game.sendEditAnnouncement(Announcement.currentId, type, title, message, Announcement.redirect, startTime, endTime, worlds, options)
	elseif type ~= 1 then
		g_game.sendAnnouncement(type, title, message, Announcement.redirect, startTime, endTime, worlds)
	elseif type == 1 then
		g_game.sendPollAnnouncement(title, message, startTime, endTime, worlds, options)
	end
	closeAnnouncementList()
end

function setNewAnnouncement()
	Announcement.AnnouncementListWindow:recursiveGetChildById('createPollFilter'):setEnabled(true)
	Announcement.AnnouncementListWindow:recursiveGetChildById('redirectUrlFilter'):setEnabled(true)
	Announcement.AnnouncementListWindow:recursiveGetChildById('announcementFilter'):setEnabled(true)

	local currentTimeTable = os.date('*t')
	local hourWidget = Announcement.AnnouncementListWindow:recursiveGetChildById('hour')
	local minuteWidget = Announcement.AnnouncementListWindow:recursiveGetChildById('minute')
	local dayWidget = Announcement.AnnouncementListWindow:recursiveGetChildById('day')
	local monthWidget = Announcement.AnnouncementListWindow:recursiveGetChildById('month')
	local yearWidget = Announcement.AnnouncementListWindow:recursiveGetChildById('year')

	local endTimeTable = os.date('*t', os.time() + 3600)
	local endHourWidget = Announcement.AnnouncementListWindow:recursiveGetChildById('endHour')
	local endMinuteWidget = Announcement.AnnouncementListWindow:recursiveGetChildById('endMinute')
	local endDayWidget = Announcement.AnnouncementListWindow:recursiveGetChildById('endDay')
	local endMonthWidget = Announcement.AnnouncementListWindow:recursiveGetChildById('endMonth')
	local endYearWidget = Announcement.AnnouncementListWindow:recursiveGetChildById('endYear')

	hourWidget:setText(currentTimeTable.hour, false)
	minuteWidget:setText(currentTimeTable.min, false)
	dayWidget:setText(currentTimeTable.day, false)
	monthWidget:setText(currentTimeTable.month, false)
	yearWidget:setText(currentTimeTable.year, false)

	endHourWidget:setText(endTimeTable.hour, false)
	endMinuteWidget:setText(endTimeTable.min, false)
	endDayWidget:setText(endTimeTable.day, false)
	endMonthWidget:setText(endTimeTable.month, false)
	endYearWidget:setText(endTimeTable.year, false)

	Announcement.AnnouncementListWindow:recursiveGetChildById('announcementTitle'):setText('', false)
	Announcement.AnnouncementListWindow:recursiveGetChildById('announcementTitle'):recursiveFocus(2)
	Announcement.AnnouncementListWindow:recursiveGetChildById('announcementContent'):setText('', false)
	Announcement.currentId = 0
	Announcement.redirect = ''
	Announcement.AnnouncementListWindow:recursiveGetChildById('newButton'):setEnabled(false)

	Announcement.tempOptions = {}

	local answerContent = Announcement.AnnouncementListWindow:recursiveGetChildById('answerContent')
	answerContent:destroyChildren()
end

function previewAnnouncement()
	local message = Announcement.AnnouncementListWindow:recursiveGetChildById('announcementContent'):getDisplayedText()
	if #message == 0 then
		return
	end

	local type = Announcement.radioGroup:getSelectedWidget():getId()
	if type == 'createPollFilter' then
		type = 1
	elseif type == 'redirectUrlFilter' then
		type = 2
	else
		type = 0
	end

	local options = {}

	if type == 1 then
		for id, child in ipairs(Announcement.tempOptions) do
			table.insert(options, { id = id, option = child.option, description = child.description })
		end
	end

	local link = Announcement.redirect
	showAnnouncementMessage({ type = type, message = message, options = options, link = link, onlyTeste = true })
end

function setupLinkAnnouncement()
	local typeSelected = Announcement.AnnouncementListWindow:recursiveGetChildById('redirectUrlFilter'):isChecked()
	if not typeSelected then
		return
	end

	Announcement.AnnouncementListWindow:hide()
	linkWindow:show()
	linkWindow:recursiveGetChildById('setupLinkList'):setText(Announcement.redirect)
	g_client.setInputLockWidget(linkWindow)
end

function setRedirectLink()
	local textUI = linkWindow:recursiveGetChildById('setupLinkList')

	Announcement.redirect = textUI:getText()
	closeRedirectLink()
end

function closeRedirectLink()
	linkWindow:recursiveGetChildById('setupLinkList'):setText('')
	linkWindow:hide()
	Announcement.AnnouncementListWindow:show()
	g_client.setInputLockWidget(Announcement.AnnouncementListWindow)
end

function createBackgroundPanel()
	if not backgroundPanel then
		backgroundPanel = g_ui.createWidget('Panel', rootWidget)
		backgroundPanel:setId('blackBackground')
		backgroundPanel:setBackgroundColor('#000000')
		backgroundPanel:setOpacity(0.9)
		backgroundPanel:fill('parent')
		backgroundPanel:hide()
	end
end

function onSelectionChange(widget, selectedWidget)
	if selectedWidget:getId() == 'redirectUrlFilter' then
		Announcement.AnnouncementListWindow:recursiveGetChildById('createPollButton'):setEnabled(false)
		Announcement.AnnouncementListWindow:recursiveGetChildById('linkButton'):setVisible(true)
	elseif selectedWidget:getId() == 'createPollFilter' then
		Announcement.AnnouncementListWindow:recursiveGetChildById('createPollButton'):setEnabled(true)
		Announcement.AnnouncementListWindow:recursiveGetChildById('linkButton'):setVisible(false)
	else
		Announcement.AnnouncementListWindow:recursiveGetChildById('createPollButton'):setEnabled(false)
		Announcement.AnnouncementListWindow:recursiveGetChildById('linkButton'):setVisible(false)
	end
end

function closePollAnnouncement()
	Announcement.AnnouncementListWindow:show()
	pollWindow:hide()
	g_client.setInputLockWidget(Announcement.AnnouncementListWindow)
end

function openPollAnnouncement()
	Announcement.AnnouncementListWindow:hide()
	pollWindow:show()
	g_client.setInputLockWidget(pollWindow)

	local setupOptionList = pollWindow:recursiveGetChildById('setupOptionList')
	setupOptionList:recursiveFocus(2)
	setupOptionList:setText('')

	local insertButton = pollWindow:recursiveGetChildById('insertButton')
	insertButton:setEnabled(false)
	insertButton:setText("Insert")

	local setupDescriptionList = pollWindow:recursiveGetChildById('setupDescriptionList')
	setupDescriptionList:setText('')

	pollWindow.onEscape = closePollAnnouncement

	insertButton.onClick = function()
		local setupOptionList = pollWindow:recursiveGetChildById('setupOptionList')
		local setupDescriptionList = pollWindow:recursiveGetChildById('setupDescriptionList')

		local option = setupOptionList:getText()
		local description = setupDescriptionList:getText()

		if #option == 0 or #description == 0 then
			return
		end

		local answerContent = Announcement.AnnouncementListWindow:recursiveGetChildById('answerContent')
		createAnswerLabel({id = #answerContent:getChildren(), option = option, description = description}, answerContent)

		Announcement.tempOptions[#Announcement.tempOptions + 1] = { option = option, description = description }
		setupOptionList:setText('')
		setupDescriptionList:setText('')
		insertButton:setEnabled(false)
		closePollAnnouncement()
	end
	pollWindow.onEnter = insertButton.onClick
end

function openEditPollOption(option)
	openPollAnnouncement()
	local setupOptionList = pollWindow:recursiveGetChildById('setupOptionList')
	setupOptionList:setText(option.option)
	setupOptionList:setActionId(option.id)

	local setupDescriptionList = pollWindow:recursiveGetChildById('setupDescriptionList')
	setupDescriptionList:setText(option.description)

	local insertButton = pollWindow:recursiveGetChildById('insertButton')
	local setupOptionList = pollWindow:recursiveGetChildById('setupOptionList')
	local setupDescriptionList = pollWindow:recursiveGetChildById('setupDescriptionList')

	local text1 = setupOptionList:getText()
	local text2 = setupDescriptionList:getText()
	insertButton:setEnabled(#text1 > 0 and #text2 > 0)

	insertButton:setText("Update")

	insertButton.onClick = function()
		-- edit option
		for _, data in pairs(Announcement.tempOptions) do
			if data.option == option.option then
				data.option = setupOptionList:getText()
				data.description = setupDescriptionList:getText()
				break
			end
		end

		local answerContent = Announcement.AnnouncementListWindow:recursiveGetChildById('answerContent')
		answerContent:destroyChildren()

		local sorted = Announcement.tempOptions
		for _, answer in pairs(sorted) do
			createAnswerLabel(answer, answerContent)
		end

		closePollAnnouncement()
	end
	pollWindow.onEnter = insertButton.onClick
end

function configureAnnouncementLabel(announcement, ordernedWorlds)
	local displayAnnouncement = Announcement.AnnouncementListWindow

	local displayWorlds = displayAnnouncement:recursiveGetChildById('displayWorlds')
	local gamerWorlds = displayAnnouncement:recursiveGetChildById('gamerWorlds')

	local hourWidget = displayAnnouncement:recursiveGetChildById('hour')
	local minuteWidget = displayAnnouncement:recursiveGetChildById('minute')
	local dayWidget = displayAnnouncement:recursiveGetChildById('day')
	local monthWidget = displayAnnouncement:recursiveGetChildById('month')
	local yearWidget = displayAnnouncement:recursiveGetChildById('year')

	local endHourWidget = displayAnnouncement:recursiveGetChildById('endHour')
	local endMinuteWidget = displayAnnouncement:recursiveGetChildById('endMinute')
	local endDayWidget = displayAnnouncement:recursiveGetChildById('endDay')
	local endMonthWidget = displayAnnouncement:recursiveGetChildById('endMonth')
	local endYearWidget = displayAnnouncement:recursiveGetChildById('endYear')

	local titleWidget = displayAnnouncement:recursiveGetChildById('announcementTitle')

	Announcement.currentId = announcement.id
	Announcement.redirect = announcement.link
	Announcement.tempOptions = announcement.options

	if announcement.type == 1 then
		Announcement.radioGroup:selectWidget(displayAnnouncement:recursiveGetChildById('createPollFilter'))
	elseif announcement.type == 2 then
		Announcement.redirect = announcement.link
		Announcement.radioGroup:selectWidget(displayAnnouncement:recursiveGetChildById('redirectUrlFilter'))
	else
		Announcement.radioGroup:selectWidget(displayAnnouncement:recursiveGetChildById('announcementFilter'))
	end
	displayAnnouncement:recursiveGetChildById('createPollFilter'):setEnabled(false)
	displayAnnouncement:recursiveGetChildById('redirectUrlFilter'):setEnabled(false)
	displayAnnouncement:recursiveGetChildById('announcementFilter'):setEnabled(false)

	titleWidget:setText(announcement.title, false)
	local startTime = os.date('*t', announcement.startTime)

	hourWidget:setText(startTime.hour, false)
	minuteWidget:setText(startTime.min, false)
	dayWidget:setText(startTime.day, false)
	monthWidget:setText(startTime.month, false)
	yearWidget:setText(startTime.year, false)


	local endTime = os.date('*t', announcement.endTime)
	endHourWidget:setText(endTime.hour, false)
	endMinuteWidget:setText(endTime.min, false)
	endDayWidget:setText(endTime.day, false)
	endMonthWidget:setText(endTime.month, false)
	endYearWidget:setText(endTime.year, false)

	displayAnnouncement:recursiveGetChildById('announcementContent'):setText(announcement.message, false)

	displayWorlds:destroyChildren()
	local ordernedDisplayWorlds = {}
	for _, id in pairs(announcement.worldsList) do
		table.insert(ordernedDisplayWorlds, { id = id, world = Announcement.worlds[id] })
	end

	table.sort(ordernedDisplayWorlds, function(a, b) return a.world < b.world end)
	for _, data in ipairs(ordernedDisplayWorlds) do
		local newlabel = g_ui.createWidget('Label', displayWorlds)
		newlabel:setText(data.world)
		newlabel:setActionId(data.id)
		newlabel.onDoubleClick = moveLabelToGameWorld
	end

	gamerWorlds:destroyChildren()
	for id, world in ipairs(ordernedWorlds) do
		if not table.contains(announcement.worldsList, world.id) then
			local newlabel = g_ui.createWidget('Label', gamerWorlds)
			newlabel:setText(world.world)
			newlabel:setActionId(world.id)
			newlabel.onDoubleClick = moveLabelToDisplayWorlds
		end
	end

	local answerContent = displayAnnouncement:recursiveGetChildById('answerContent')
	answerContent:destroyChildren()

	if announcement.type == 1 then
		local sorted = announcement.options
		table.sort(sorted, function(a, b) return a.id > b.id end)
		for _, answer in pairs(sorted) do
			createAnswerLabel(answer, answerContent)
		end
	end

	displayAnnouncement:recursiveGetChildById('newButton'):setEnabled(true)

	updateViewersCount(announcement)
end

function onEditOption()
	local insertButton = pollWindow:recursiveGetChildById('insertButton')
	local setupOptionList = pollWindow:recursiveGetChildById('setupOptionList')
	local setupDescriptionList = pollWindow:recursiveGetChildById('setupDescriptionList')

	local text1 = setupOptionList:getText()
	local text2 = setupDescriptionList:getText()
	insertButton:setEnabled(#text1 > 0 and #text2 > 0)
end

function createAnswerLabel(answer, answerContent)
	local label = g_ui.createWidget('UIWidget', answerContent)
	label:setText(answer.option)
	label:setActionId(answer.id)
	label:setTextAlign(AlignLeft)
	label:setTooltip(insertLineBreaks(answer.description, 52))
	label:setHeight(35)
	label.onDoubleClick = function()
		openEditPollOption(answer)
	end

	label.onMouseRelease = function(self, mousePos, mouseButton)
		if mouseButton == MouseRightButton and Announcement.currentId == 0 then
			local menu = g_ui.createWidget('PopupMenu')
			menu:addOption(tr('Delete'),
				function()
					-- remove from tempOptions
					for i, data in pairs(Announcement.tempOptions) do
						if data.option == answer.option then
							table.remove(Announcement.tempOptions, i)
							break
						end
					end
					-- remove from UI
					label:destroy()
				end)
			menu:display(mousePos)
		end
	end

	return label
end
