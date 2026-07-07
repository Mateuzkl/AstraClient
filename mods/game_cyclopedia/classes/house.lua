---------------------------
-- Lua code author: R1ck --
-- Company: VICTOR HUGO PERENHA - JOGOS ON LINE --
---------------------------

House = {}
House.__index = House

local lastSelectedHouse = nil
local currentHouseList = {}
local houseList = {}

-- Sort fields
local currentStateSort = 1 -- All states
local currentStatusSort = 1 -- Name

local showGuildHalls = false
local currentTownName = ""
local infoWindow = nil

local bidButtonError = {
	[3] = "Characters on the beginner's island are not allowed to rent houses.",
	[7] = "The transfer has already been accepted.",
	[11] = "A character of your account already holds the highest bid for\nanother house. You may only bid for one house at the same time.",
	[12] = "The characters of your account already own 1 houses. You may\nonly own 1 house at the same time.",
	[13] = "A character of this account has already accepted a house transfer.\nYou need to wait until the first transfer has been completed before you can transfer this house."
}

local messageTypes = {
	[1] = { -- bid
		[0] = "Your bid was successful. You are currently holding the highest bid.",
		[1] = "You have successfully placed a bid but you are not holding the highest bid. Another character's bid limit was\nhigher than your maximum."
	},

	[2] = { -- move out
		[0] = "You have successfully initiated your move out."
	},

	[3] = { -- transfer
		[0] = "You have successfully initiated the transfer of your house.",
		[2] = "Setting up a house transfer failed.\nYou are not the owner of this house.",
		[4] = "Setting up a house transfer failed.\nA character with this name does not exist.",
		[8] = "Setting up a house transfer failed.\nA guildhall may only be transferred to a leader of an active guild.",
		[10] = "Setting up a house transfer failed.\nThe characters of this account may not rent more houses.",
		[12] = "Setting up a house transfer failed.\nThis character cannot accept a house transfer because a character of this account is currently bidding for a house.",
		[15] = "Setting up a house transfer failed.\nThe transfer has already been accepted.",
		[16] = "Setting up a house transfer failed.\nCharacters on the beginner's island are not allowed to rent houses.",
		[21] = "Setting up a house transfer failed.\nInternal error."
	},

	[4] = { -- cancel move out
		[0] = "You have successfully cancelled your move out. You will keep the house."
	},

	[5] = { -- cancel transfer
		[0] = "You have successfully cancelled the transfer. You will keep the house.",
		[21] = "An internal error has ocurred."
	},

	[6] = { -- accept transfer
		[0] = "You have successfully accepted the transfer.",
		[2] = "Accepting the transfer failed.\nThis character is not the designated new owner of this house.",
		[3] = "Accepting the transfer failed.\nYou cannot accept a house transfer as long as one of your characters is bidding for a house.",
		[7] = "Accepting the transfer failed.\nThe transfer has already been accepted.",
		[8] = "Accepting the transfer failed.\nCharacters on the beginner's island are not allowed to rent houses.",
		[11] = "Accepting the transfer failed.\nYou may not rent more houses.",
		[21] = "An internal error has ocurred."
	},

	[7] = { -- reject transfer
		[0] = "You rejected the house transfer successfully.\nThe old owner will keep the house.",
		[21] = "An internal error has ocurred."
	}
}

function House.resetWindow()
	showGuildHalls = false
	currentTownName = ""
	infoWindow = nil
	currentStateSort = 1
	currentStatusSort = 1
	lastSelectedHouse = nil
	currentHouseList = {}
	houseList = {}
end

function House.refresh()
	if VisibleCyclopediaPanel.selectedBackground.panelHouse:isVisible() then
		House.selectTown(currentTownName)
	end
end

-- Parse functions
function House.onRecvHousesData(houses)
	local staticHouse = g_things.getHouseList()
	if not VisibleCyclopediaPanel or not VisibleCyclopediaPanel.mapViewBackground then
		return true
	end

	local ownPanel = VisibleCyclopediaPanel.selectedBackground.panelHouse
	ownPanel:destroyChildren()

	for _, data in ipairs(House.sortDataByStatus(houses)) do
		local static = staticHouse[data.houseId]
		if not static then
			goto continue
		end

		local guildHall = static[5]
		if (showGuildHalls and not guildHall) or (not showGuildHalls and guildHall) then
			goto continue
		end

		if (currentStateSort == 2 and data.state ~= 0) or currentStateSort == 3 and (data.state ~= 2 and data.state ~= 3 and data.state ~= 4) then
			goto continue
		end

		local widget = g_ui.createWidget('HouseData', ownPanel)
		widget.main:setText(string.capitalize(static[1]))
		widget.main.sizeValueText:setText(static[4] .. " sqm")
		widget.main.maxBedsValueText:setText(static[3])
		widget.main.rentValueText:setText(static[2] / 1000 .. " k")

		if data.state == 0 then
			-- available
			local t = {}
			setStringColor(t, "auctioned ", "#00f000")

			if #data.bidderName == 0 then
				setStringColor(t, "(no bid yet)", "#c0c0c0")
			else
				local timeLeft = data.bidEnd - os.time()
				local hours = math.floor(timeLeft / 3600)
				local minutes = math.floor((timeLeft % 3600) / 60)
				local seconds = timeLeft % 60

				local timeLeftStr = ""
				if hours > 0 then
					timeLeftStr = hours .. "h "
				end

				if hours < 1 then
					timeLeftStr = timeLeftStr .. minutes .. "min " .. seconds .. "s"
				else
					timeLeftStr = timeLeftStr .. minutes .. "min"
				end

				setStringColor(t, "(Bid: " .. comma_value(data.highestBid) .. " Ends in: " .. timeLeftStr .. ")", "#c0c0c0")
			end

			widget.main.statusValueText:setColoredText(t)
		elseif data.state == 2 or data.state == 4 or data.state == 3 then
			widget.main.statusValueText:setText("rented by " .. data.owner)
			local playerName = g_game.getLocalPlayer():getName()
			if data.owner == playerName then
				widget.main.imageOwnHouse:setVisible(true)
			end
		end

		widget.main:setActionId(data.houseId)
		currentHouseList[data.houseId] = {mainData = data, staticData = static};
		:: continue ::
	end

	if #ownPanel:getChildren() == 0 then
		ownPanel:setText("No result.")
		VisibleCyclopediaPanel.mapViewBackground.noSelected:setText("No house selected")
		House.setupMinimap(0)
	else
		if not VisibleCyclopediaPanel.bidHouseWindow:isVisible() then
			House.onSelectHouse(ownPanel:getChildren()[1].main)
			ownPanel:setText("")
		end
	end

	houseList = houses
end

function House.onRecvHouseMessage(houseId, bidType, messageType)
	if infoWindow ~= nil then
		return true
	end

	cyclopediaWindow:hide()
	local okFunction = function() g_game.sendHouseAction(0, currentTownName)
		House.updateHouseView(bidType)
		if bidType == 2 and messageType == 0 then
			VisibleCyclopediaPanel.moveDate:setVisible(false)
			VisibleCyclopediaPanel.selectedBackground:setVisible(true)
		elseif bidType == 3 and messageType == 0 then
			VisibleCyclopediaPanel.configureHouseTransfer:setVisible(false)
			VisibleCyclopediaPanel.selectedBackground:setVisible(true)
		elseif bidType == 4 then
			VisibleCyclopediaPanel.keepHouse:setVisible(false)
			VisibleCyclopediaPanel.selectedBackground:setVisible(true)
		elseif bidType == 5 then
			VisibleCyclopediaPanel.cancelTransferHouse:setVisible(false)
			VisibleCyclopediaPanel.selectedBackground:setVisible(true)

		elseif bidType == 7 and messageType == 0 then
			VisibleCyclopediaPanel.rejectTransferHouse:setVisible(false)
			VisibleCyclopediaPanel.selectedBackground:setVisible(true)
		end

		cyclopediaWindow:show(true)
		infoWindow:destroy()
		infoWindow = nil end

	infoWindow = displayGeneralBox(tr('Summary'), tr("%s", messageTypes[bidType][messageType]), {{text = tr('Ok'), callback = okFunction}}, okFunction, okFunction)
end

function House.updateHouseView(bidType)
	if not lastSelectedHouse then
		return true
	end

	House.onSelectHouse(lastSelectedHouse)
	if bidType == 1 then
		House.onBidButton(nil)
	end
end

function House.selectTown(index)
	if not VisibleCyclopediaPanel or not VisibleCyclopediaPanel.mapViewBackground then
		return true
	end

	House.resetData()
	currentTownName = index
	g_game.sendHouseAction(0, index)
	House.setupMinimap(0)

	lastSelectedHouse = nil
	currentHouseList = {}
	VisibleCyclopediaPanel.mapViewBackground.noSelected:setText("")

	if VisibleCyclopediaPanel.bidHouseWindow:isVisible() then
		VisibleCyclopediaPanel.selectedBackground:setVisible(true)
		VisibleCyclopediaPanel.bidHouseWindow:setVisible(false)
	end
end

function House.setZoom(upper)
	local minimap = VisibleCyclopediaPanel.mapViewBackground.houseView.houseImage
	if not minimap then
		return
	end

	if upper then
		minimap:zoomIn()
	else
		minimap:zoomOut()
	end
end

local function setMinimapView(minimap, housePosZ)
	if housePosZ > 7 then
		minimap.view = "minimap"
		minimap:setCurrentView("minimap")
	else
		minimap.view = "satellite"
		minimap:setCurrentView("satellite")
	end

	local floorWidget = VisibleCyclopediaPanel.mapViewBackground:recursiveGetChildById("floorPosition")
	if floorWidget then
		floorWidget:setImageClip(14 * housePosZ .. " 0 14 67")
	end
end

function House.changeFloor(upper)
	local minimap = VisibleCyclopediaPanel.mapViewBackground.houseView.houseImage
	if not minimap then
		return
	end

	local newFloor = g_realMinimap.changeHouseFloor(upper)
	local currentView = minimap:getCameraPosition()
	local housePos = g_realMinimap.getHousePosition()
	if not housePos then
		return
	end

	setMinimapView(minimap, newFloor)
	currentView.z = (newFloor > 7) and newFloor or housePos.z

	RealMap.setCameraPosition(minimap, currentView)
end

function House.setupMinimap(houseId)
	local minimap = VisibleCyclopediaPanel.mapViewBackground.houseView.houseImage
	if not minimap then
		return
	end

	if minimap.setupHouse then
		minimap:setupHouse(houseId)
	end
	if houseId == 0 then
		RealMap.setCameraPosition(minimap, {x = 0, y = 0, z = 0})
		return true
	end

	local house = g_houses.getHouse(houseId)
	local housePos = house and house:getEntry() or g_realMinimap.getHousePosition()
	if not housePos or not housePos.z then
		return true
	end
	setMinimapView(minimap, housePos.z)

	RealMap.setRegion(minimap)
	RealMap.setCameraPosition(minimap, housePos)
	RealMap.hideCross(minimap)
	RealMap.setZoom(minimap, 4)
end

function House.onSelectHouse(widget)
	if lastSelectedHouse then
		lastSelectedHouse:setBorderWidth(0)
		lastSelectedHouse:setBorderColor('alpha')
	end

	lastSelectedHouse = widget
	widget:setBorderWidth(2)
	widget:setBorderColor('white')

	House.setupMinimap(widget:getActionId())

	VisibleCyclopediaPanel.mapViewBackground.noSelected:setText("")

	VisibleCyclopediaPanel.moveDate:setVisible(false)
	VisibleCyclopediaPanel.keepHouse:setVisible(false)
	VisibleCyclopediaPanel.cancelTransferHouse:setVisible(false)
	VisibleCyclopediaPanel.rejectTransferHouse:setVisible(false)
	VisibleCyclopediaPanel.acceptTransferHouse:setVisible(false)
	VisibleCyclopediaPanel.configureHouseTransfer:setVisible(false)
	if not VisibleCyclopediaPanel.selectedBackground:isVisible() then
		VisibleCyclopediaPanel.selectedBackground:setVisible(true)
	end

	House.resetData()
	local dataList = currentHouseList[widget:getActionId()]
	if not dataList then
		return
	end

	local currentInfo = dataList.mainData
	if not currentInfo then
		return
	end

	local panel = VisibleCyclopediaPanel.mapViewBackground:recursiveGetChildById("panelTextsRents")
	panel.rental.imageOwnHouse:setVisible(false)
	if currentInfo.state == 0 then
		panel.bidButton:setOn(true)
		panel.bidButton:setVisible(true)
		panel.bidButton:setTooltip("")

		if currentInfo.canBidError ~= 0 then
			panel.bidButton:setOn(false)
			panel.bidButton:setTooltip(bidButtonError[currentInfo.canBidError])
		end

		if #currentInfo.bidderName > 0 then
			panel.bidInfo:setVisible(true)
			panel.bidInfo.bidderName:setText(short_text(currentInfo.bidderName, 16))
			if #currentInfo.bidderName >= 16 then
				panel.bidInfo.bidderName:setTooltip(currentInfo.bidderName)
			end

			panel.bidInfo.endValue:setText(formatHouseDate(currentInfo.bidEnd))
			panel.bidInfo.highestBidValue:setText(comma_value(currentInfo.highestBid))

			if currentInfo.bidOwner then
				panel.bidInfo.auctionImage:setImageClip("0 0 234 54")
				panel.bidInfo.auctionImage:setSize(tosize("234 54"))
				panel.bidInfo.yourLimitValue:setText(comma_value(currentInfo.holderLimit))
			else
				panel.bidInfo.auctionImage:setImageClip("0 0 234 41")
				panel.bidInfo.auctionImage:setSize(tosize("234 41"))
				panel.bidInfo.yourLimitValue:clearText()
			end
		else
			panel.noBidHouseHeader:setVisible(true)
			panel.noBidHouseText:setVisible(true)
		end

	elseif currentInfo.state == 2 or currentInfo.state == 3 or currentInfo.state == 4 then
		panel.rental:setVisible(true)
		panel.rental.tenantValue:setText(short_text(currentInfo.owner, 16))
		if #currentInfo.owner >= 16 then
			panel.rental.tenantValue:setTooltip(currentInfo.owner)
		end

		panel.rental.moveImage:setVisible(false)
		panel.rental.pendingImage:setVisible(false)

		panel.rental.paidValue:setText(formatHouseDate(currentInfo.paidUntil))
		if currentInfo.state == 4 and currentInfo.owner == g_game.getLocalPlayer():getName() then
			panel.rental.moveImage:setVisible(true)
			panel.rental.moveImage.moveValue:setText(formatHouseDate(currentInfo.scheduleTime))
			panel.rental.keepButton:setVisible(true)
		elseif currentInfo.state == 2 and currentInfo.rented then
			panel.rental.imageOwnHouse:setVisible(true)
			panel.rental.moveButton:setVisible(true)
			panel.rental.transferButton:setVisible(true)
		elseif currentInfo.state == 3 then
			panel.rental.pendingImage:setVisible(true)
			panel.rental.pendingImage.newOwnerValue:setText(short_text(currentInfo.targetPlayer, 16))
			if #currentInfo.targetPlayer >= 16 then
				panel.rental.pendingImage.newOwnerValue:setTooltip(currentInfo.targetPlayer)
			end

			panel.rental.pendingImage.dateValue:setText(formatHouseDate(currentInfo.scheduleTime))
			panel.rental.pendingImage.priceValue:setText(comma_value(currentInfo.transferValue))

			if currentInfo.owner == g_game.getLocalPlayer():getName() then
				panel.rental.cancelTransferButton:setVisible(true)
				panel.rental.cancelTransferButton:setOn(true)
				panel.rental.cancelTransferButton:setTooltip("")
				if currentInfo.ownerError > 0 then
					panel.rental.cancelTransferButton:setOn(false)
					panel.rental.cancelTransferButton:setTooltip(bidButtonError[currentInfo.ownerError])
				end
			elseif currentInfo.targetPlayer == g_game.getLocalPlayer():getName() then
				if currentInfo.canBidError > 0 then
					panel.rental.acceptTransferButton:setOn(false)
					panel.rental.acceptTransferButton:setTooltip(bidButtonError[currentInfo.canBidError])
					panel.rental.rejectTransferButton:setOn(false)
					panel.rental.rejectTransferButton:setTooltip(bidButtonError[currentInfo.canBidError])
				else
					panel.rental.acceptTransferButton:setOn(true)
					panel.rental.acceptTransferButton:setTooltip("")
					panel.rental.rejectTransferButton:setOn(true)
					panel.rental.rejectTransferButton:setTooltip("")
				end

				panel.rental.acceptTransferButton:setVisible(true)
				panel.rental.rejectTransferButton:setVisible(true)
			end
		end
	end
end

function House.onBidButton(button)
	if not lastSelectedHouse or (button and not button:isOn()) then
		return true
	end

	local selectHouseId = lastSelectedHouse:getActionId()
	local static = currentHouseList[selectHouseId].staticData
	local currentInfo = currentHouseList[selectHouseId].mainData
	if not static or not currentInfo then
		return true
	end

	local bidWindow = VisibleCyclopediaPanel.bidHouseWindow

	bidWindow.limitBox:setText(0)
	bidWindow.nameValue:setText(string.capitalize(static[1]))
	bidWindow.sizeValue:setText(static[4] .. " sqm")
	bidWindow.bedsValue:setText(static[3])
	bidWindow.rentValue:setText(static[2] / 1000 .. " k")

	if #currentInfo.bidderName == 0 then
		bidWindow.currentAcution:setVisible(false)
		bidWindow.thereFar:setVisible(true)
		bidWindow.limitText:setMarginTop(5)
	else
		bidWindow.thereFar:setVisible(false)
		bidWindow.currentAcution:setVisible(true)
		bidWindow.currentAcution.highestBidder:setText(currentInfo.bidderName)
		bidWindow.currentAcution.endTime:setText(formatHouseDate(currentInfo.bidEnd))
		bidWindow.currentAcution.highestBid:setText(comma_value(currentInfo.highestBid))

		if currentInfo.bidOwner then
			bidWindow.currentAcution.bidLimitBid:setText(comma_value(currentInfo.holderLimit))
			bidWindow.limitBox:setText(currentInfo.holderLimit)
			bidWindow.currentAcution:setImageClip("0 0 217 54")
			bidWindow.currentAcution:setSize(tosize("217 54"))
			bidWindow.limitText:setMarginTop(47)
		else
			bidWindow.currentAcution:setImageClip("0 0 217 41")
			bidWindow.currentAcution:setSize(tosize("217 41"))
			bidWindow.limitText:setMarginTop(31)
		end
	end

	VisibleCyclopediaPanel.bidHouseWindow:setVisible(true)
	VisibleCyclopediaPanel.selectedBackground:setVisible(false)
end

function House.onMoveOutButton()
	if not lastSelectedHouse then
		return true
	end

	if VisibleCyclopediaPanel.configureHouseTransfer:isVisible() then
		VisibleCyclopediaPanel.configureHouseTransfer:setVisible(false)
	end

	local selectHouseId = lastSelectedHouse:getActionId()
	local static = currentHouseList[selectHouseId].staticData
	local currentInfo = currentHouseList[selectHouseId].mainData
	if not static or not currentInfo then
		return true
	end

	local currentDate = os.date("*t")
	local day, month, year = currentDate.day, currentDate.month, currentDate.year
	local nextDay, nextMonth, nextYear = getNextDay(day, month, year)

	VisibleCyclopediaPanel.moveDate.data.yearBox:addOption(nextYear)
	VisibleCyclopediaPanel.moveDate.data.monthBox:addOption(nextMonth)
	VisibleCyclopediaPanel.moveDate.data.dayBox:addOption(nextDay)
	VisibleCyclopediaPanel.moveDate.data.nameValue:setText(string.capitalize(static[1]))
	VisibleCyclopediaPanel.moveDate.data.sizeValue:setText(static[4] .. " sqm")
	VisibleCyclopediaPanel.moveDate.data.bedsValue:setText(static[3])
	VisibleCyclopediaPanel.moveDate.data.rentValue:setText(static[2] / 1000 .. " k")
	VisibleCyclopediaPanel.moveDate.data.paidUntilDate:setText(formatHouseDate(currentInfo.paidUntil))
	VisibleCyclopediaPanel.moveDate:setVisible(true)
	VisibleCyclopediaPanel.selectedBackground:setVisible(false)
end

function House.onDoMoveOut(moveCancel)
	local selectHouseId = lastSelectedHouse:getActionId()
	local static = currentHouseList[selectHouseId].staticData
	local currentInfo = currentHouseList[selectHouseId].mainData
	if not static or not currentInfo then
		return true
	end

	cyclopediaWindow:hide()

	local actionType = moveCancel and 4 or 2
	local yesFunction = function() g_game.sendHouseAction(actionType, "", selectHouseId) cyclopediaWindow:show() moveOutWindow:destroy() moveOutWindow = nil end
	local noFunction = function() cyclopediaWindow:show() moveOutWindow:destroy() moveOutWindow = nil end

	local message = tr("Do you really want to move out of the house '%s'?\nClick on \"Yes\" to move out on %s", string.capitalize(static[1]), formatHouseDate(os.time()))
	if moveCancel then
		message = tr("Do you really want to keep your house '%s'?\nYou will no longer move out on %s", string.capitalize(static[1]), formatHouseDate(currentInfo.scheduleTime))
	end

	moveOutWindow = displayGeneralBox('Confirm House Action', message,
		{ { text=tr('Yes'), callback=yesFunction }, { text=tr('No'), callback=noFunction }
	}, yesFunction, noFunction)
end

function House.onDoTransfer(cancel)
	local selectHouseId = lastSelectedHouse:getActionId()
	local static = currentHouseList[selectHouseId].staticData
	local currentInfo = currentHouseList[selectHouseId].mainData
	if not static or not currentInfo then
		return true
	end

	cyclopediaWindow:hide()
	local window = VisibleCyclopediaPanel.configureHouseTransfer.data
	local targetName = window.newOwnerName:getText()
	local transferValue = tonumber(window.presetName:getText())

	local message = tr("Do you really want to transfer your house '%s' to %s?\nThe transfer is scheduled for %s.\nYou have set the transfer price to %s gold coins.\nThe transfer will only take place if %s accepts it!\n\nPlease take all your personal belongings out of the house before the daily server save on the day you move\nout. Everything that remains in the house becomes the property of the new owner after the transfer. The only\nexception are items which have been purchased in the Store. They will be wrapped back up and sent to your\ninbox.", string.capitalize(static[1]), targetName, formatHouseDate(os.time()), transferValue, targetName)
	if cancel then
		message = tr("Do you really want to keep your house '%s'?\nYou will no longer transfer the house to %s on %s", string.capitalize(static[1]), currentInfo.targetPlayer, formatHouseDate(currentInfo.scheduleTime))
	end

	local yesFunction = function() if cancel then g_game.sendHouseAction(5, "", selectHouseId) else g_game.sendHouseAction(3, targetName, selectHouseId, transferValue) end cyclopediaWindow:show() transferWindow:destroy() transferWindow = nil end
	local noFunction = function() cyclopediaWindow:show() transferWindow:destroy() transferWindow = nil end

	transferWindow = displayGeneralBox('Confirm House Action', message,
		{ { text=tr('Yes'), callback=yesFunction }, { text=tr('No'), callback=noFunction }
	}, yesFunction, noFunction)

end

function House.onKeepHouseButton()
	if not lastSelectedHouse then
		return true
	end

	local selectHouseId = lastSelectedHouse:getActionId()
	local static = currentHouseList[selectHouseId].staticData
	local currentInfo = currentHouseList[selectHouseId].mainData
	if not static or not currentInfo then
		return true
	end

	VisibleCyclopediaPanel.keepHouse.data.nameValue:setText(string.capitalize(static[1]))
	VisibleCyclopediaPanel.keepHouse.data.sizeValue:setText(static[4] .. " sqm")
	VisibleCyclopediaPanel.keepHouse.data.bedsValue:setText(static[3])
	VisibleCyclopediaPanel.keepHouse.data.rentValue:setText(static[2] / 1000 .. " k")
	VisibleCyclopediaPanel.keepHouse.data.paidUntilDate:setText(formatHouseDate(currentInfo.paidUntil))
	VisibleCyclopediaPanel.keepHouse.data.moveDate:setText(formatHouseDate(currentInfo.scheduleTime))

	VisibleCyclopediaPanel.keepHouse:setVisible(true)
	VisibleCyclopediaPanel.selectedBackground:setVisible(false)
end

function House.onTransferButton()
	if not lastSelectedHouse then
		return true
	end

	if VisibleCyclopediaPanel.moveDate:isVisible() then
		VisibleCyclopediaPanel.moveDate:setVisible(false)
	end

	local selectHouseId = lastSelectedHouse:getActionId()
	local static = currentHouseList[selectHouseId].staticData
	local currentInfo = currentHouseList[selectHouseId].mainData
	if not static or not currentInfo then
		return true
	end

	local currentDate = os.date("*t")
	local day, month, year = currentDate.day, currentDate.month, currentDate.year
	local nextDay, nextMonth, nextYear = getNextDay(day, month, year)

	VisibleCyclopediaPanel.configureHouseTransfer.data.yearBox:addOption(nextYear)
	VisibleCyclopediaPanel.configureHouseTransfer.data.monthBox:addOption(nextMonth)
	VisibleCyclopediaPanel.configureHouseTransfer.data.dayBox:addOption(nextDay)
	VisibleCyclopediaPanel.configureHouseTransfer.data.nameValue:setText(string.capitalize(static[1]))
	VisibleCyclopediaPanel.configureHouseTransfer.data.sizeValue:setText(static[4] .. " sqm")
	VisibleCyclopediaPanel.configureHouseTransfer.data.bedsValue:setText(static[3])
	VisibleCyclopediaPanel.configureHouseTransfer.data.rentValue:setText(static[2] / 1000 .. " k")
	VisibleCyclopediaPanel.configureHouseTransfer.data.paidUntilDate:setText(formatHouseDate(currentInfo.paidUntil))
	VisibleCyclopediaPanel.configureHouseTransfer:setVisible(true)
	VisibleCyclopediaPanel.selectedBackground:setVisible(false)
end

function House.onCancelTransferButton(button)
	if not lastSelectedHouse or not button:isOn() then
		return true
	end

	local selectHouseId = lastSelectedHouse:getActionId()
	local static = currentHouseList[selectHouseId].staticData
	local currentInfo = currentHouseList[selectHouseId].mainData
	if not static or not currentInfo then
		return true
	end

	VisibleCyclopediaPanel.cancelTransferHouse.data.nameValue:setText(static[1])
	VisibleCyclopediaPanel.cancelTransferHouse.data.sizeValue:setText(static[4] .. " sqm")
	VisibleCyclopediaPanel.cancelTransferHouse.data.bedsValue:setText(static[3])
	VisibleCyclopediaPanel.cancelTransferHouse.data.rentValue:setText(static[2] / 1000 .. " k")
	VisibleCyclopediaPanel.cancelTransferHouse.data.paidUntilDate:setText(formatHouseDate(currentInfo.paidUntil))
	VisibleCyclopediaPanel.cancelTransferHouse.data.transferDate:setText(formatHouseDate(currentInfo.scheduleTime))
	VisibleCyclopediaPanel.cancelTransferHouse.data.price:setText(comma_value(currentInfo.transferValue))
	VisibleCyclopediaPanel.cancelTransferHouse.data.newOwner:setText(currentInfo.targetPlayer)
	VisibleCyclopediaPanel.cancelTransferHouse:setVisible(true)
	VisibleCyclopediaPanel.selectedBackground:setVisible(false)
end

function House.onManageTransferButton(button, reject)
	if not lastSelectedHouse or not button:isOn() then
		return true
	end

	local selectHouseId = lastSelectedHouse:getActionId()
	local static = currentHouseList[selectHouseId].staticData
	local currentInfo = currentHouseList[selectHouseId].mainData
	if not static or not currentInfo then
		return true
	end

	if reject and VisibleCyclopediaPanel.acceptTransferHouse:isVisible() then
		VisibleCyclopediaPanel.acceptTransferHouse:setVisible(false)
	end

	if not reject and VisibleCyclopediaPanel.rejectTransferHouse:isVisible() then
		VisibleCyclopediaPanel.rejectTransferHouse:setVisible(false)
	end

	local widget = reject and VisibleCyclopediaPanel.rejectTransferHouse or VisibleCyclopediaPanel.acceptTransferHouse

	widget.data.nameValue:setText(string.capitalize(static[1]))
	widget.data.sizeValue:setText(static[4] .. " sqm")
	widget.data.bedsValue:setText(static[3])
	widget.data.rentValue:setText(static[2] / 1000 .. " k")
	widget.data.paidUntilDate:setText(formatHouseDate(currentInfo.paidUntil))
	widget.data.transferDate:setText(formatHouseDate(currentInfo.scheduleTime))
	widget.data.price:setText(comma_value(currentInfo.transferValue))
	widget.data.newOwner:setText(currentInfo.targetPlayer)
	widget:setVisible(true)
	VisibleCyclopediaPanel.selectedBackground:setVisible(false)
end

function House.onDoAcceptTransfer(reject)
	local selectHouseId = lastSelectedHouse:getActionId()
	local static = currentHouseList[selectHouseId].staticData
	local currentInfo = currentHouseList[selectHouseId].mainData
	if not static or not currentInfo then
		return true
	end

	cyclopediaWindow:hide()

	local message = tr("Do you want to accept the house transfer offered by %s for the property '%s'?\nThe transfer is scheduled for %s.\nThe transfer price was set to %s gold coins.\n\nMake sure to have enough gold in your bank account to pay the costs for this house transfer and the next rent.\nRemember to edit the door rights as only the guest list will be reset after the transfer!", currentInfo.owner, string.capitalize(static[1]), formatHouseDate(currentInfo.scheduleTime), comma_value(currentInfo.transferValue))
	if reject then
		message = tr("Do you really want to reject the transfer for the house '%s' offered by %s?\nYou will not get the house. %s will keep the house and can set up a new transfer anytime.", string.capitalize(static[1]), currentInfo.targetPlayer, currentInfo.targetPlayer)
	end

	local packetType = reject and 7 or 6
	local yesFunction = function() g_game.sendHouseAction(packetType, "", selectHouseId) cyclopediaWindow:show() transferWindow:destroy() transferWindow = nil end
	local noFunction = function() cyclopediaWindow:show() transferWindow:destroy() transferWindow = nil end

	transferWindow = displayGeneralBox('Confirm House Action', message,
		{ { text=tr('Yes'), callback=yesFunction }, { text=tr('No'), callback=noFunction }
	}, yesFunction, noFunction)
end

function House.onPlaceBid(button)
	if not button:isOn() then
		return true
	end

	local selectHouseId = lastSelectedHouse:getActionId()
	local static = currentHouseList[selectHouseId].staticData
	local currentInfo = currentHouseList[selectHouseId].mainData
	if not static or not currentInfo then
		return true
	end

	local limit = tonumber(VisibleCyclopediaPanel.bidHouseWindow.limitBox:getText())

	cyclopediaWindow:hide()
	local yesFunction = function() g_game.sendHouseAction(1, "", selectHouseId, limit) cyclopediaWindow:show() placeBidWindow:destroy() placeBidWindow = nil end
	local noFunction = function() cyclopediaWindow:show() placeBidWindow:destroy() placeBidWindow = nil end

	placeBidWindow = displayGeneralBox(tr('Confirm House Action'), tr("Do you really want to bid on the house '%s' ?\n\nYou have set your bid limit to %s.\nWhen the auction ends, the winning bid plus the rent of %s for the first month will be debited from your\nbank account.", string.capitalize(static[1]), limit, (static[2] / 1000 .. " k")),
		{ { text=tr('Yes'), callback=yesFunction }, { text=tr('No'), callback=noFunction }
	}, yesFunction, noFunction)
end

function House.onStateSort(widget, currentIndex)
	currentStateSort = currentIndex;
	House.onRecvHousesData(houseList)
end

function House.onStatusSort(widget, currentIndex)
	currentStatusSort = currentIndex;
	House.onRecvHousesData(houseList)
end

function House.sortDataByStatus(houses)
	local staticHouse = g_things.getHouseList()
	-- entries without static data cannot be compared; the display loop skips them anyway
	local filtered = {}
	for _, data in ipairs(houses) do
		if staticHouse[data.houseId] then
			table.insert(filtered, data)
		end
	end
	table.sort(filtered, function(a, b)
		local a_static = staticHouse[a.houseId]
		local b_static = staticHouse[b.houseId]

		if currentStatusSort == 1 then
			local firstNameA = a_static[1]:split(" ")[1]
			local firstNameB = b_static[1]:split(" ")[1]
			if firstNameA == firstNameB then return a.houseId < b.houseId end
			return firstNameA < firstNameB
		end

		if currentStatusSort == 2 then
			return a_static[4] < b_static[4]
		end

		if currentStatusSort == 3 then
			return a_static[2] < b_static[2]
		end

		if currentStatusSort == 4 then
			return a.highestBid > b.highestBid
		end

		if currentStatusSort == 5 then
			return a.bidEnd > b.bidEnd
		end
		return false
	end)
	return filtered
end

function House.toggleHouseChecked(guildHall)
	local checkHouses = g_ui.getRootWidget():recursiveGetChildById('checkHouses')
	local checkGuildhalls = g_ui.getRootWidget():recursiveGetChildById('checkGuildhalls')

	if guildHall then
		checkHouses:setChecked(false)
		checkGuildhalls:setChecked(true)
		showGuildHalls = true
	else
		checkHouses:setChecked(true)
		checkGuildhalls:setChecked(false)
		showGuildHalls = false
	end
	House.onRecvHousesData(houseList)
end

function House.onBidChangeValue(widget)
	local currentText = widget:getText()
	if #currentText == 0 then
		return
	end

    currentText = currentText:gsub("[^%d]", "")
    widget:setText(currentText)

    if #currentText > 11 then
        currentText = currentText:sub(1, -2)
        widget:setText(currentText)
    end

    local numericValue = tonumber(currentText) or 0
    if numericValue and numericValue >= 99999999999 then
		currentText = "99999999999"
		widget:setText(currentText)
    end

	local bankMoney = g_game.getLocalPlayer():getResourceValue(ResourceBank)
	local bidWindow = VisibleCyclopediaPanel.bidHouseWindow
	local selectHouseId = lastSelectedHouse:getActionId()
	local static = currentHouseList[selectHouseId].staticData
	local currentInfo = currentHouseList[selectHouseId].mainData

	bidWindow.infoRed:setVisible(false)
	bidWindow.infoRed:setTooltip("")
	bidWindow.infoOrange:setVisible(false)
	bidWindow.infoOrange:setTooltip("")
	bidWindow.limitBox:setColor("#c0c0c0")
	bidWindow.bidButtonHouseWindow:setOn(true)
	bidWindow.bidButtonHouseWindow:setTooltip("")

	if tonumber(numericValue) < currentInfo.highestBid then
		bidWindow.infoOrange:setVisible(true)
		bidWindow.infoOrange:setTooltip("Your bid limit must be higher than the current highest bid.")
	end

	if tonumber(numericValue) + static[2] > bankMoney then
		bidWindow.infoRed:setVisible(true)
		bidWindow.infoRed:setTooltip("Your account balance is too low to pay the bid and the rent for the\nfirst month.")
		bidWindow.limitBox:setColor("#d33c3c")
		bidWindow.bidButtonHouseWindow:setOn(false)
		bidWindow.bidButtonHouseWindow:setTooltip("You need to fill in the form correctly")
	end
end

function House.onTransferTarget(widget)
	local transferWindow = VisibleCyclopediaPanel.configureHouseTransfer.data
	local currentText = widget:getText()
	if #currentText == 0 then
		transferWindow.redInfo:setVisible(true)
		return
	end

	transferWindow.redInfo:setVisible(false)
	currentText = currentText:gsub("%d", "")
    widget:setText(currentText)

    if #currentText > 28 then
        currentText = currentText:sub(1, -2)
        widget:setText(currentText)
    end
end

function House.onTransferValue(widget)
	local transferWindow = VisibleCyclopediaPanel.configureHouseTransfer.data
	local currentText = widget:getText()
	if #currentText == 0 then
		transferWindow.redInfo:setVisible(true)
		return
	end

	currentText = currentText:gsub("[^%d]", "")
    widget:setText(currentText)

    if #currentText > 11 then
        currentText = currentText:sub(1, -2)
        widget:setText(currentText)
    end

	local numericValue = tonumber(currentText)
    if numericValue and numericValue >= 99999999999 then
        currentText = "99999999999"
        widget:setText(currentText)
    end
end

function House.resetData()
	if not VisibleCyclopediaPanel or not VisibleCyclopediaPanel.mapViewBackground then
		return true
	end

	local panel = VisibleCyclopediaPanel.mapViewBackground:recursiveGetChildById("panelTextsRents")
	panel.bidButton:setVisible(false)
	panel.noBidHouseHeader:setVisible(false)
	panel.noBidHouseText:setVisible(false)
	panel.rental:setVisible(false)
	panel.bidInfo:setVisible(false)
	panel.rental.moveButton:setVisible(false)
	panel.rental.transferButton:setVisible(false)
	panel.rental.moveImage:setVisible(false)
	panel.rental.keepButton:setVisible(false)
	panel.rental.acceptTransferButton:setVisible(false)
	panel.rental.rejectTransferButton:setVisible(false)
	panel.rental.cancelTransferButton:setVisible(false)
end

function formatHouseDate(timestamp)
    local t = os.date("!*t", timestamp)
    local months = {
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    }
    local month = months[t.month]
    local day = t.day
    local hour = string.format("%02d", t.hour)
    local min = string.format("%02d", t.min)
    hour = string.format("%02d", (t.hour + 1) % 24)
    return month .. " " .. day .. ", " .. hour .. ":" .. min .. " CET"
end
