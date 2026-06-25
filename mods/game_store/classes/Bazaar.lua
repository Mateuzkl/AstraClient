Bazaar = {}
Bazaar.__index = Bazaar

Bazaar.name = ''
Bazaar.level = 0
Bazaar.vocationId = 0
Bazaar.outfit = {}
Bazaar.worldType = 0
Bazaar.minDuration = 0
Bazaar.maxDuration = 0
Bazaar.minValue = 0
Bazaar.requeriments = {}
Bazaar.characterItems = {}
Bazaar.characterStoreItems = {}
Bazaar.arguments = {}
Bazaar.selectedSlotItem = nil
Bazaar.selectedSlotArgument = nil
Bazaar.selectedArgumentId = -1
Bazaar.setArguments = {}
Bazaar.setItems = {}
Bazaar.tempWidgets = {}
Bazaar.tempWidgetDays = {}
Bazaar.selectedDay = ""
Bazaar.selectedSlotDay = 0
Bazaar.step = 0
Bazaar.sellValue = 0
Bazaar.initialFee = 50

selectedItemRadio = nil

function Bazaar.onCharacterBazarRequeriments(name, level, vocationId, outfit, worldType, minDuration, maxDuration,
																						 minValue, requeriments)
	Bazaar.name = name
	Bazaar.level = level
	Bazaar.vocationId = vocationId
	Bazaar.outfit = outfit
	Bazaar.worldType = worldType
	Bazaar.minDuration = minDuration
	Bazaar.maxDuration = maxDuration
	Bazaar.minValue = minValue
	Bazaar.requeriments = requeriments
	Bazaar.selectedArgumentId = -1
	Bazaar.setArguments = {}
	Bazaar.setItems = {}
	Bazaar.tempWidgets = {}
	Bazaar.selectedDay = ""
	Bazaar.selectedSlotDay = 0
	Bazaar.step = 0
	Bazaar.sellValue = 0

	Bazaar:resetArguments()
	Bazaar:showRules()
end

function Bazaar.onCharacterBazarItems(characterItems)
	Bazaar.characterItems = characterItems
	local content = bazaarWindow.contentPanel.characterPanel:recursiveGetChildById('content')
	content.itemButton0:setEnabled(#Bazaar.characterItems > 0)
	content.itemButton1:setEnabled(#Bazaar.characterItems > 0)
	content.itemButton2:setEnabled(#Bazaar.characterItems > 0)
	content.itemButton3:setEnabled(#Bazaar.characterItems > 0)
end

function Bazaar.onCharacterBazarStoreItems(characterStoreItems)
	Bazaar.characterStoreItems = characterStoreItems
end

function Bazaar.onCharacterBazarInformations(arguments)
	Bazaar.arguments = arguments
end

function closeBazar()
	bazaarWindow:hide()
	showStoreWindow()
end

function Bazaar:showRules()
	bazaarWindow.contentPanel.rulesPanel:setVisible(true)
	bazaarWindow.contentPanel.characterPanel:setVisible(false)

	bazaarWindow:setText(tr('Character Auction Settings (1/3)'))
	bazaarWindow:focus()

	local panel = bazaarWindow.contentPanel.rulesPanel.bazaarPanel.rules
	panel:destroyChildren()
	local canNextPage = true
	for requeriment, valid in pairs(Bazaar.requeriments) do
		local ui = g_ui.createWidget('RulesText', panel)
		ui.text:setText(requeriment)
		ui.icon:setImageSource('/images/store/icon-' .. (valid and 'yes' or 'no'))
		if not valid then
			canNextPage = false
		end
	end

	if canNextPage then
		g_game.doThing(false)
		g_game.requestCharacterInformation()
		g_game.doThing(true)
	end

	g_game.doThing(false)
	g_game.requestCharacterCheckInformations()
	g_game.doThing(true)

	bazaarWindow.contentPanel.rulesPanel.next:setEnabled(canNextPage)
	bazaarWindow.contentPanel.rulesPanel.next.onClick = function()
		Bazaar:showCharacterInfo()
	end
end

local function getVocationString(id)
	if id == 1 then
		return "Knight"
	elseif id == 2 then
		return "Paladin"
	elseif id == 3 then
		return "Sorcerer"
	elseif id == 4 then
		return "Druid"
	elseif id == 5 then
		return "Monk"
	end
	return "None"
end

function Bazaar:showCharacterInfo()
	bazaarWindow.contentPanel.rulesPanel:setVisible(false)
	bazaarWindow.contentPanel.characterPanel:setVisible(true)

	bazaarWindow:setText(tr('Character Auction Settings (2/3)'))

	local title = bazaarWindow:recursiveGetChildById('title')
	local titleFormat = string.format("%s (%d) | %s | WorldType", Bazaar.name, Bazaar.level,
		getVocationString(Bazaar.vocationId))
	title:setText(titleFormat)

	local creature = bazaarWindow:recursiveGetChildById('outfitPlaceholder')
	creature:setOutfit(Bazaar.outfit)

	local priceInputBox = bazaarWindow:recursiveGetChildById('priceInputBox')
	priceInputBox:setText(Bazaar.minValue)

	local cest_time = os.date("!*t", Bazaar.minDuration)
	cest_time.hour = cest_time.hour + 2

	local localDateTimeLabel = bazaarWindow:recursiveGetChildById('localDateTimeLabel')
	localDateTimeLabel:setText(os.date("%Y-%m-%d, %H:%M CEST", os.time(cest_time)))

	local auctionEndDateTimeLabel = bazaarWindow:recursiveGetChildById('auctionEndDateTimeLabel')
	auctionEndDateTimeLabel:setText(os.date("%Y-%m-%d, %H:%M", Bazaar.maxDuration))

	Bazaar:showInfo()

	bazaarWindow.contentPanel.characterPanel.next:setEnabled(true)
	bazaarWindow.contentPanel.characterPanel.previous:setEnabled(true)
end

function Bazaar:showInfo()
	bazaarWindow:recursiveGetChildById('infoLabel'):setVisible(true)
	bazaarWindow:recursiveGetChildById('calendarPanel'):setVisible(false)
	bazaarWindow:recursiveGetChildById('characterItens'):setVisible(false)
	bazaarWindow:recursiveGetChildById('characterArguments'):setVisible(false)
	bazaarWindow:recursiveGetChildById('bazaarConfirmation'):setVisible(false)

	-- unlock all
	Bazaar:setEditEnabled(true)

	bazaarWindow.contentPanel.characterPanel.previous:setEnabled(true)
	bazaarWindow.contentPanel.characterPanel.previous:setVisible(true)
	bazaarWindow.contentPanel.characterPanel.previous.onClick = function() Bazaar:showRules() end
	bazaarWindow.contentPanel.characterPanel.next:setText('Next')
	bazaarWindow.contentPanel.characterPanel.next:setImageSource('/images/ui/buttons')
	bazaarWindow.contentPanel.characterPanel.next.onClick = function() Bazaar:openConfirmation() end
	bazaarWindow.contentPanel.characterPanel.cancel.onClick = function() closeBazar(); end

	bazaarWindow:setText(tr('Character Auction Settings (2/3)'))

	local value = bazaarWindow:recursiveGetChildById('priceInputBox'):getText()
	Bazaar:checkPriceInput(value)
end

function Bazaar:openCalendar()
	bazaarWindow:recursiveGetChildById('infoLabel'):setVisible(false)
	bazaarWindow:recursiveGetChildById('calendarPanel'):setVisible(true)
	bazaarWindow:recursiveGetChildById('characterItens'):setVisible(false)
	bazaarWindow:recursiveGetChildById('characterArguments'):setVisible(false)
	bazaarWindow:recursiveGetChildById('bazaarConfirmation'):setVisible(false)

	-- lock all
	Bazaar:setEditEnabled(false)

	bazaarWindow.contentPanel.characterPanel:recursiveGetChildById('searchInputBox'):setText('', false)
	bazaarWindow.contentPanel.characterPanel.previous:setVisible(false)

	bazaarWindow.contentPanel.characterPanel.next:setEnabled(true)
	bazaarWindow.contentPanel.characterPanel.next:setText('Ok')
	bazaarWindow.contentPanel.characterPanel.next.onClick = Bazaar.addDayArgument
	bazaarWindow.contentPanel.characterPanel.cancel.onClick = function() Bazaar:showInfo() end

	local time = os.date("*t", Bazaar.maxDuration)
	if Bazaar.selectedDay == "" then
		Bazaar.selectedDay = time.day .. "." .. time.month .. "." .. time.year
		Bazaar.selectedSlotDay = Bazaar.maxDuration
	end
	Bazaar:makeCalendar(Bazaar.selectedSlotDay)

	bazaarWindow:recursiveGetChildById('dateLimitLabel'):setText(os.date("%Y-%m-%d, %H:%M", Bazaar.minDuration) ..
	" and " .. os.date("%Y-%m-%d, %H:%M", Bazaar.maxDuration))
end

function Bazaar:hasSetItem(id)
	for _, itemId in pairs(Bazaar.setItems) do
		if itemId == id then
			return true
		end
	end
	return false
end

function Bazaar:openItemArgument(value)
	Bazaar.selectedSlotItem = value
	bazaarWindow:recursiveGetChildById('infoLabel'):setVisible(false)
	bazaarWindow:recursiveGetChildById('calendarPanel'):setVisible(false)
	bazaarWindow:recursiveGetChildById('characterItens'):setVisible(true)
	bazaarWindow:recursiveGetChildById('characterArguments'):setVisible(false)
	bazaarWindow:recursiveGetChildById('bazaarConfirmation'):setVisible(false)


	-- lock all
	Bazaar:setEditEnabled(false)

	if selectedItemRadio then
		selectedItemRadio:destroy()
	end

	selectedItemRadio = UIRadioGroup.create()

	selectedItemRadio:clearSelected()
	connect(selectedItemRadio, { onSelectionChange = Bazaar.onSelectionChange })


	local itemPanel = bazaarWindow:recursiveGetChildById('characterItens').itemCheckList
	itemPanel:destroyChildren()
	for _, i in pairs(Bazaar.characterItems) do
		if not Bazaar:hasSetItem(i[1]) then
			local uiitem = g_ui.createWidget("CharacterBazarItem", itemPanel)
			uiitem:setItemId(i[1])
			uiitem:setId(i[1])
			if i[2] ~= 0 then
				uiitem:setTier(i[2])
			end
			uiitem:setItemCount(i[3])

			uiitem.onDoubleClick = Bazaar.addItemArgument

			selectedItemRadio:addWidget(uiitem)
			if not selectedItemRadio.selectedWidget then
				selectedItemRadio:selectWidget(uiitem)
			end
		end
	end

	bazaarWindow.contentPanel.characterPanel:recursiveGetChildById('searchInputBox'):setText('', false)
	bazaarWindow.contentPanel.characterPanel.previous:setVisible(false)
	if selectedItemRadio.selectedWidget then
		bazaarWindow.contentPanel.characterPanel.next:setEnabled(true)
		bazaarWindow.contentPanel.characterPanel.next:setText('Ok')
		bazaarWindow.contentPanel.characterPanel.next.onClick = Bazaar.addItemArgument
		bazaarWindow.contentPanel.characterPanel.cancel.onClick = function() Bazaar:showInfo() end
	end
end

function Bazaar:onSearchItem(text)
	local tosearch = #text < 3 and '' or text
	local itemPanel = bazaarWindow:recursiveGetChildById('characterItens').itemCheckList
	for _, ui in pairs(itemPanel:getChildren()) do
		local itemName = getItemServerName(ui:getItemId())
		if tosearch ~= '' and not string.find(itemName, tosearch) then
			ui:setVisible(false)
		else
			ui:setVisible(true)
		end
	end
end

function Bazaar:addItemArgument()
	local item = bazaarWindow:recursiveGetChildById('itemButton' .. Bazaar.selectedSlotItem - 1)
	if item then
		item:setItemId(selectedItemRadio.selectedWidget:getItemId())
		item:setTier(selectedItemRadio.selectedWidget:getTier())
		item:setItemCount(selectedItemRadio.selectedWidget:getItemCount())
		item:setImageSource('/images/ui/34-button')
		item:setImageClip('0 0 34 34')
		Bazaar.setItems[Bazaar.selectedSlotItem] = item:getItemId()
		item.onClick = function() end
	end
	local id = Bazaar.selectedSlotItem
	local trash = bazaarWindow:recursiveGetChildById('trash' .. Bazaar.selectedSlotItem - 1)
	if trash then
		trash:setVisible(true)
		trash.onClick = function() Bazaar:deleteItemArgument(id) end
	end

	Bazaar:showInfo()
end

function Bazaar:deleteItemArgument(selectedSlotItem)
	local item = bazaarWindow:recursiveGetChildById('itemButton' .. selectedSlotItem - 1)
	if item then
		item:setTier(0)
		item:setItemCount(0)
		item:setItemId(0)
		item:setImageSource('/images/store/bazaar-add-item')
		item:setImageClip('0 0 34 34')
		item.onClick = function() Bazaar:openItemArgument(selectedSlotItem) end
	end

	local trash = bazaarWindow:recursiveGetChildById('trash' .. selectedSlotItem - 1)
	if trash then
		trash:setVisible(false)
		trash.onClick = function() end
	end

	Bazaar.setItems[selectedSlotItem] = nil
end

function Bazaar:resetArguments()
	for i = 1, 4 do
		Bazaar:deleteItemArgument(i)
	end

	Bazaar.setItems = {}
	Bazaar.selectedArgumentId = -1
	Bazaar.setArguments = {}
	for i = 1, 5 do
		Bazaar:removeSlotArgument(i)
	end

	Bazaar.selectedSlotDay = 0
end

function Bazaar:openCharacterArgument(value)
	Bazaar.selectedSlotArgument = value
	bazaarWindow:recursiveGetChildById('infoLabel'):setVisible(false)
	bazaarWindow:recursiveGetChildById('calendarPanel'):setVisible(false)
	bazaarWindow:recursiveGetChildById('characterItens'):setVisible(false)
	bazaarWindow:recursiveGetChildById('characterArguments'):setVisible(true)
	bazaarWindow:recursiveGetChildById('bazaarConfirmation'):setVisible(false)

	-- lock all
	Bazaar:setEditEnabled(false)

	bazaarWindow.contentPanel.characterPanel:recursiveGetChildById('searchInputBox'):setText('', false)
	bazaarWindow.contentPanel.characterPanel.previous:setVisible(false)

	bazaarWindow.contentPanel.characterPanel.next:setEnabled(true)
	bazaarWindow.contentPanel.characterPanel.next:setText('Ok')
	bazaarWindow.contentPanel.characterPanel.next.onClick = Bazaar.addArgument
	bazaarWindow.contentPanel.characterPanel.cancel.onClick = function() Bazaar:showInfo() end

	local characterArguments = bazaarWindow:recursiveGetChildById('characterArguments')
	local argumentList = characterArguments:recursiveGetChildById('itemCheckList')
	argumentList:destroyChildren()

	table.sort(Bazaar.arguments, function(a, b) return a[2] < b[2] end)

	Bazaar.tempWidgets = {}
	for _, argument in ipairs(Bazaar.arguments) do
		local argumentName = argument[2]
		local argumentWidgetName = 'ArgumentBestiary'
		if argumentName == 'Skills' then
			argumentWidgetName = 'ArgumentSkills'
		elseif argumentName == 'Gold' then
			argumentWidgetName = 'ArgumentGold'
		elseif argumentName == 'Blessings' then
			argumentWidgetName = 'ArgumentBlessing'
		elseif argumentName == 'Bestiary' then
			argumentWidgetName = 'ArgumentBestiary'
		elseif argumentName == 'Exaltation Forge' then
			argumentWidgetName = 'ArgumentForge'
		elseif argumentName == 'Bosstiary' then
			argumentWidgetName = 'ArgumentBosstiary'
		end

		local argumentWidget = g_ui.createWidget(argumentWidgetName, argumentList)
		local height = 42
		for argumentId, value in pairs(argument[3]) do
			if not Bazaar:hasSetArgument(argumentId) then
				local ui = g_ui.createWidget('ArgumentLabel', argumentWidget.list)
				ui.icon:setImageClip(argument[1] * 10 .. " 0 10 10")
				ui.text:setText(value)
				height = height + ui:getHeight()
				ui:setId("Argument_" .. argumentId)
				ui:setActionId(argumentId)
				if Bazaar.selectedArgumentId == -1 then
					Bazaar.selectedArgumentId = argumentId
					ui:setBackgroundColor('#585858')
				end
			end
		end

		argumentWidget:setHeight(height - 14)
		if height == 42 then
			argumentWidget:destroy()
			argumentWidget = nil
		else
			table.insert(Bazaar.tempWidgets, argumentWidget)
		end
	end
end

function Bazaar.onSelectionChange(self, selectedWidget, previousSelectedWidget)
	if previousSelectedWidget and previousSelectedWidget ~= selectedWidget then
		previousSelectedWidget:setBorderWidth(0)
	end

	selectedWidget:setBorderWidth(1)
	selectedWidget:setBorderColor("white")
end

function Bazaar:setEditEnabled(value)
	local content = bazaarWindow.contentPanel.characterPanel:recursiveGetChildById('content')
	content.itemButton0:setEnabled(value)
	content.itemButton1:setEnabled(value)
	content.itemButton2:setEnabled(value)
	content.itemButton3:setEnabled(value)
	content.trash0:setEnabled(value)
	content.trash1:setEnabled(value)
	content.trash2:setEnabled(value)
	content.trash3:setEnabled(value)
	content.priceInputBox:setEnabled(value)
	content.dateTimeButton:setEnabled(value)
	content.salesArgumentButton1:setEnabled(value)
	content.salesArgumentButton2:setEnabled(value)
	content.salesArgumentButton3:setEnabled(value)
	content.salesArgumentButton4:setEnabled(value)
	content.salesArgumentButton5:setEnabled(value)
	content.salesArgumentLabel1:setEnabled(value)
	content.salesArgumentLabel2:setEnabled(value)
	content.salesArgumentLabel3:setEnabled(value)
	content.salesArgumentLabel4:setEnabled(value)
	content.salesArgumentLabel5:setEnabled(value)
end

function clearSearchButton(widgetId)
	if widgetId == 'searchInputBox' then
		bazaarWindow.contentPanel.characterPanel:recursiveGetChildById(widgetId):setText('')
	end
end

function Bazaar:selectArgumentId(argumentId)
	if Bazaar.selectedArgumentId ~= -1 then
		local previousWidget = bazaarWindow:recursiveGetChildById('Argument_' .. Bazaar.selectedArgumentId)
		if previousWidget then
			previousWidget:setBackgroundColor('#484848')
		end
	end

	local widget = bazaarWindow:recursiveGetChildById('Argument_' .. argumentId)
	if widget then
		Bazaar.selectedArgumentId = argumentId
		widget:setBackgroundColor('#585858')
	end
end

function Bazaar:getArgumentById(id)
	for _, argument in ipairs(Bazaar.arguments) do
		for argumentId, value in pairs(argument[3]) do
			if argumentId == id then
				return argument
			end
		end
	end

	return {}
end

function Bazaar:hasSetArgument(id)
	for _, argument in ipairs(Bazaar.setArguments) do
		if argument == id then
			return true
		end
	end
	return false
end

function Bazaar:addArgument()
	local slot = bazaarWindow:recursiveGetChildById('salesArgumentLabel' .. Bazaar.selectedSlotArgument)
	if slot then
		local previousWidget = bazaarWindow:recursiveGetChildById('Argument_' .. Bazaar.selectedArgumentId)
		if not previousWidget then
			Bazaar.selectedSlotArgument = -1
			Bazaar:showInfo()
			return
		end
		slot:setText('')
		slot:setTextAutoResize(false)
		slot:setSize("420 20")
		local argument = Bazaar:getArgumentById(Bazaar.selectedArgumentId)
		slot:setHTML('<img src="/images/store/icons-charactertrade-highlights" width="10" height="10" clip="' ..
		argument[1] * 10 .. ' 0 10 10" offset="0 4" />' .. previousWidget.text:getText())

		Bazaar.setArguments[Bazaar.selectedSlotArgument] = Bazaar.selectedArgumentId
	end

	local id = Bazaar.selectedSlotArgument
	local button = bazaarWindow:recursiveGetChildById('salesArgumentButton' .. Bazaar.selectedSlotArgument)
	if button then
		button:setImageSource('/images/store/trash-button')
		button.onClick = function() Bazaar:removeSlotArgument(id) end
	end

	Bazaar.selectedSlotArgument = -1
	Bazaar:showInfo()
end

function Bazaar:removeSlotArgument(id)
	local slot = bazaarWindow:recursiveGetChildById('salesArgumentLabel' .. id)
	if slot then
		slot:setText('Add sales argument #' .. id)
		slot:setTextAutoResize(true)
		slot:setHTML('')
	end

	local button = bazaarWindow:recursiveGetChildById('salesArgumentButton' .. id)
	if button then
		button:setImageSource('/images/store/augments-button')
		button.onClick = function() Bazaar:openCharacterArgument(id) end
	end

	Bazaar.setArguments[id] = nil
end

function Bazaar:onSearchArgument(text)
	local tosearch = #text < 3 and '' or text
	for _, argumentWidget in pairs(Bazaar.tempWidgets) do
		local title = string.searchEscape(argumentWidget.title:getText():lower())
		if tosearch ~= '' and not string.find(title, tosearch:lower()) then
			-- check children
			local height = 42
			for _, widget in pairs(argumentWidget.list:getChildren()) do
				local widgetText = widget.text:getText():lower()
				if not string.find(string.searchEscape(widgetText), tosearch:lower()) then
					widget:setVisible(false)
				else
					widget:setVisible(true)
					height = height + widget:getHeight()
				end
			end

			if height == 42 then
				argumentWidget:setVisible(false)
			else
				argumentWidget:setHeight(height - 14)
				argumentWidget:setVisible(true)
			end
		else
			argumentWidget:setVisible(true)
			local height = 42
			for _, widget in pairs(argumentWidget.list:getChildren()) do
				widget:setVisible(true)
				height = height + widget:getHeight()
			end

			argumentWidget:setHeight(height - 14)
		end
	end
end

-------------------------- calendario --------------------------
local function getFirstDay(time)
	local d = os.date("*t", time)
	return d.wday
end

function Bazaar:makeCalendar(newTime)
	local time = os.date("*t", newTime)
	time.day = 1
	local firstDay = getFirstDay(os.time { year = time.year, month = time.month, day = 1 }) - 1
	if firstDay == 0 then
		firstDay = 8
	end

	bazaarWindow:recursiveGetChildById('DaysButton'):destroyChildren()
	bazaarWindow:recursiveGetChildById('monthName'):setText(os.date("%B %Y", newTime))

	local currentDay = 1
	local recount = 1
	local month = time.month
	local year = time.year

	for i = 1, 42 do
		local widgetDay = g_ui.createWidget("DaysButton", bazaarWindow:recursiveGetChildById('DaysButton'))

		if month == time.month and dayExistsInMonth(currentDay, month, year) then
			widgetDay:setImageClip("0 26 36 26")
			if i == firstDay then
				widgetDay.day:setText(currentDay)
				widgetDay:setId(string.format("%d.%d.%d", currentDay, month, year))
				if Bazaar.selectedDay == string.format("%d.%d.%d", currentDay, month, year) then
					widgetDay:setImageClip("0 0 36 26")
				end
				widgetDay.time = os.time { year = time.year, month = month, day = currentDay }
				widgetDay:setActionId(widgetDay.time)
				currentDay = currentDay + 1

				if widgetDay.time > Bazaar.maxDuration or widgetDay.time < Bazaar.minDuration then
					widgetDay:setEnabled(false)
				end
			elseif currentDay ~= 1 and dayExistsInMonth(currentDay, month, year) then
				if Bazaar.selectedDay == string.format("%d.%d.%d", currentDay, month, year) then
					widgetDay:setImageClip("0 0 36 26")
				end
				widgetDay.time = os.time { year = time.year, month = month, day = currentDay }
				widgetDay.day:setText(currentDay)
				widgetDay:setId(string.format("%d.%d.%d", currentDay, month, year))
				widgetDay:setActionId(widgetDay.time)
				currentDay = currentDay + 1

				if widgetDay.time > Bazaar.maxDuration or widgetDay.time < Bazaar.minDuration then
					widgetDay:setEnabled(false)
				end
			else
				-- Equivalente ao mes anterior
				local otherMonth = os.time { year = year, month = month, day = currentDay } - ((firstDay - i) * 86400)
				widgetDay:setId(os.date("%d.%m.%Y", otherMonth))
				widgetDay.time = otherMonth
				widgetDay:setActionId(otherMonth)
				widgetDay.day:setText(os.date("%d", otherMonth))
				widgetDay:setImageClip("0 52 36 26")

				if widgetDay.time > Bazaar.minDuration then
					widgetDay:setEnabled(true)
					widgetDay.onClick = function()
						Bazaar:setSelectedDay(widgetDay)
						Bazaar:makeCalendar(widgetDay.time)
					end
				else
					widgetDay:setEnabled(false)
				end
			end
		else
			-- setando mes posterior
			if not dayExistsInMonth(currentDay, month, year) then
				currentDay = 1
				month = month + 1
				if month > 12 then
					month = 1
					year = year + 1
				end
			end

			local otherMonth = os.time { year = year, month = month, day = currentDay } + (recount * 86400)
			widgetDay:setId(string.format("%d.%d.%d", recount, month, year))
			widgetDay:setActionId(otherMonth)
			widgetDay.day:setText(recount)
			recount = recount + 1
			widgetDay:setImageClip("0 52 36 26")
			widgetDay.time = otherMonth


			if widgetDay.time < Bazaar.maxDuration then
				widgetDay:setEnabled(true)
				widgetDay.onClick = function()
					Bazaar:setSelectedDay(widgetDay)
					Bazaar:makeCalendar(widgetDay.time)
				end
			else
				widgetDay:setEnabled(false)
			end
		end
	end
end

function dayExistsInMonth(day, month, year)
	local date = os.time({ year = year, month = month, day = day })

	-- Use the os.date function to check if the date is valid
	local t = os.date("*t", date)

	-- If the year, month, and day fields in the table t match the provided values, the day is valid
	return t.year == year and t.month == month and t.day == day
end

function Bazaar:setSelectedDay(widget)
	local lastTime = Bazaar.selectedDay
	if widget then
		Bazaar.selectedDay = widget:getId()
		Bazaar.selectedSlotDay = widget:getActionId()
	end

	Bazaar:refreshCalendar(lastTime)
end

function Bazaar:refreshCalendar(lastTime)
	local lastWidget = bazaarWindow:recursiveGetChildById(lastTime)
	if lastWidget then
		lastWidget:setImageClip("0 26 36 26")
	end

	local newWidget = bazaarWindow:recursiveGetChildById(Bazaar.selectedDay)
	if newWidget then
		newWidget:setImageClip("0 0 36 26")
	end
end

function Bazaar:nextMonth()
	local time = os.date("*t")
	Bazaar.step = Bazaar.step + 1
	local month = time.month + Bazaar.step
	local year = time.year
	if month > 12 then
		month = month - 12
		year = year + 1
	end
	local newTime = os.time { day = 1, year = year, month = month }
	Bazaar:makeCalendar(newTime)
end

function Bazaar:backMonth()
	local time = os.date("*t")
	Bazaar.step = Bazaar.step - 1
	local month = time.month + Bazaar.step
	local year = time.year
	if month < 1 then
		month = month + 12
		year = year - 1
	end
	local newTime = os.time { day = time.day, year = time.year, month = month }

	Bazaar:makeCalendar(newTime)
end

function Bazaar:addDayArgument()
	local slot = bazaarWindow:recursiveGetChildById('dateTimeButton')

	local minutes = tonumber(bazaarWindow:recursiveGetChildById('minute'):getCurrentOption().text) or 30
	local hours = tonumber(bazaarWindow:recursiveGetChildById('hour'):getCurrentOption().text) or 14

	local b = os.date("*t", Bazaar.selectedSlotDay)
	Bazaar.selectedSlotDay = os.time { year = b.year, month = b.month, day = b.day, hour = hours, min = minutes }

	local auctionEndDateTimeLabel = bazaarWindow:recursiveGetChildById('auctionEndDateTimeLabel')
	auctionEndDateTimeLabel:setText(os.date("%Y-%m-%d, %H:%M", Bazaar.selectedSlotDay))

	Bazaar.selectedDay = os.date("%d.%m.%Y", Bazaar.selectedSlotDay)

	Bazaar:showInfo()
end

function Bazaar:checkPriceInput(value)
	value = tonumber(value) or 0
	bazaarWindow.contentPanel.characterPanel.next:setEnabled(value >= Bazaar.initialFee)
	bazaarWindow:recursiveGetChildById('priceInputBox'):setColor(value >= Bazaar.initialFee and '$var-text-cip-color-white' or
	'$var-text-cip-store-red')

	Bazaar.sellValue = value
end

function Bazaar:openConfirmation()
	bazaarWindow:setText(tr('Character Auction Settings (3/3)'))
	bazaarWindow:recursiveGetChildById('infoLabel'):setVisible(false)
	bazaarWindow:recursiveGetChildById('calendarPanel'):setVisible(false)
	bazaarWindow:recursiveGetChildById('characterItens'):setVisible(false)
	bazaarWindow:recursiveGetChildById('characterArguments'):setVisible(false)
	bazaarWindow:recursiveGetChildById('bazaarConfirmation'):setVisible(true)
	if Bazaar.selectedSlotDay == 0 then
		Bazaar.selectedSlotDay = Bazaar.maxDuration
	end
	-- lock all
	Bazaar:setEditEnabled(false)

	bazaarWindow.contentPanel.characterPanel.previous:setVisible(false)

	bazaarWindow.contentPanel.characterPanel.next:setEnabled(true)
	bazaarWindow.contentPanel.characterPanel.next:setText('Confirm')
	bazaarWindow.contentPanel.characterPanel.next:setImageSource('/images/ui/buttons-blue')
	bazaarWindow.contentPanel.characterPanel.next.onClick = function()
		local items = {}
		local storeItems = {}
		local saleArguments = {}
		for i = 1, 4 do
			local itemWidget = bazaarWindow:recursiveGetChildById('itemButton' .. i - 1)
			if itemWidget then
				local item = itemWidget:getItem()
				if item then
					table.insert(items, item)
				end
			end
		end

		for i = 1, 5 do
			local argument = Bazaar.setArguments[i]
			if argument then
				table.insert(saleArguments, argument)
			end
		end
		g_game.sendCharacterAuctionConfirm(Bazaar.sellValue, Bazaar.selectedSlotDay, items, storeItems, saleArguments)
	end
	bazaarWindow.contentPanel.characterPanel.cancel.onClick = function() Bazaar:showInfo() end


	local checkList = bazaarWindow:recursiveGetChildById('checkList')
	checkList:destroyChildren()

	local stringFormat =
	'<table><tbody><tr><td style="padding-right: 5px;"><img src="%s" width="12" height="12" offset="2 2" /></td><td>%s</td></tr></tbody></table>'
	local check1 = g_ui.createWidget('Label', checkList)
	check1:setId('check1')
	check1:setColor("$var-text-cip-color")
	check1:setSize("715 15")
	local firstLabel = ' You will be auctioning your character<font color="white">' ..
	Bazaar.name ..
	'</font> with a starting price of<font color="white">' ..
	Bazaar.sellValue ..
	' </font><img src="/images/store/icon-tibiacointransferable" width="12" height="12" offset="0 2" />.'
	check1:setHTML(string.format(stringFormat, '/images/store/icon-yes', firstLabel))

	local check2 = g_ui.createWidget('Label', checkList)
	check2:setId('check2')
	check2:setColor("$var-text-cip-color")
	check2:setSize("715 15")
	local secondLabel = ' The auction will start at the next server save and end on<font color="white">' ..
	os.date("%Y-%m-%d, %H:%M", Bazaar.selectedSlotDay) .. '</font>'
	check2:setHTML(string.format(stringFormat, '/images/store/icon-yes', secondLabel))

	local check3 = g_ui.createWidget('Label', checkList)
	check3:setId('check3')
	check3:setColor("$var-text-cip-color")
	check3:setSize("715 45")

	local secondLabel = ' By confirming the auction, an auction fee of ' ..
	Bazaar.initialFee ..
	'<img src="/images/store/icon-tibiacointransferable" width="12" height="12" offset="0 2" /> becomes due which will be deducted from your account\'s<p>Koliseu Coins balance. Further, 8% of the auction\'s sales revenue will be kept by Koliseu as commission.</p>'
	check3:setHTML(string.format(stringFormat, '/images/store/icon-yes', secondLabel))

	local check4 = g_ui.createWidget('Label', checkList)
	check4:setId('check4')
	check4:setColor("$var-text-cip-color")
	check4:setSize("715 15")

	local stringFormat =
	'<table><tbody><tr><td style="padding-right: 5px;"><img src="%s" width="4" height="9" offset="2 2" /></td><td>%s</td></tr></tbody></table>'
	local secondLabel =
	'  Important: Note that the Koliseu Coins you receive for selling your character may be partly or completely non-transferable up to 120 days after the auction has ended. Non-transferable Koliseu Coins cannot be sold in the Market or gifted to other accounts.\n'
	check4:setHTML(string.format(stringFormat, '/images/store/icon-exclamationmark', secondLabel))

	local check5 = g_ui.createWidget('Label', checkList)
	check5:setId('check5')
	check5:setColor("$var-text-cip-color")
	check5:setSize("715 15")

	local stringFormat =
	'<table><tbody><tr><td style="padding-right: 5px;"><img src="%s" width="4" height="9" offset="2 2" /></td><td>%s</td></tr></tbody></table>'
	local secondLabel =
	'  The 14 days refund period for certain services purchased in the Store expires by putting this character on auction.\n'
	check5:setHTML(string.format(stringFormat, '/images/store/icon-exclamationmark', secondLabel))

	local check6 = g_ui.createWidget('Label', checkList)
	check6:setId('check6')
	check6:setColor("$var-text-cip-color")
	check6:setSize("715 15")

	local stringFormat =
	'<table><tbody><tr><td style="padding-right: 5px;"><img src="%s" width="4" height="9" offset="2 2" /></td><td>%s</td></tr></tbody></table>'
	local secondLabel =
	'  Finally, make sure to remove all items (e.g., letters or other writable documents) with sensitive data (addresses, passwords, etc.) your character may have in its depot or inventory before you confirm the auction.\n'
	check6:setHTML(string.format(stringFormat, '/images/store/icon-exclamationmark', secondLabel))
end
