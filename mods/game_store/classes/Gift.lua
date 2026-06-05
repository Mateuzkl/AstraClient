if not GiftCoins then
	GiftCoins = {}
	GiftCoins.__index = GiftCoins
end

function GiftCoins:onGiftWindow()
	closeStore()
	local count = Store.transferableCoins or 0
	local coinsPacketSize = Store.coinsPacketSize or 25
	if count < coinsPacketSize then
		return
	end

	giftWindow = g_ui.createWidget('GiftWindow', rootWidget)
	g_client.setInputLockWidget(giftWindow)
	local scrollbar = giftWindow.contentPanel:getChildById('countScrollBar')
	scrollbar:setMaximum(count)
	scrollbar:setMinimum(coinsPacketSize)
	scrollbar:setStep(coinsPacketSize)
	scrollbar:setValue(coinsPacketSize)
	giftWindow.contentPanel.currentAmount:setText(coinsPacketSize)

	local spinbox = giftWindow.contentPanel.spinBox
	spinbox:setMaximum(count)
	spinbox:setMinimum(coinsPacketSize)
	spinbox:setValue(coinsPacketSize)
	spinbox:setStep(coinsPacketSize)
	spinbox:hideButtons()
	spinbox:focus()
	spinbox.firstEdit = true

	giftWindow.contentPanel.totalAmount:setText(count)

	local spinBoxValueChange = function(self, value)
		spinbox.firstEdit = false
		value = math.cround(value, coinsPacketSize)
		scrollbar:setValue(value)
	end
	spinbox.onValueChange = spinBoxValueChange

	local check = function()

	end
	okButton = giftWindow.contentPanel:getChildById('buttonOk')
	cancelButton = giftWindow.contentPanel:getChildById('buttonCancel')

	g_keyboard.bindKeyPress("Up", function() check() spinbox:up() end, spinbox)
	g_keyboard.bindKeyPress("Down", function() check() spinbox:down() end, spinbox)
	g_keyboard.bindKeyPress("Right", function() check() spinbox:up() end, spinbox)
	g_keyboard.bindKeyPress("Left", function() check() spinbox:down() end, spinbox)
	g_keyboard.bindKeyPress("PageUp", function() check() spinbox:setValue(spinbox:getValue()+coinsPacketSize) end, spinbox)
	g_keyboard.bindKeyPress("PageDown", function() check() spinbox:setValue(spinbox:getValue()-coinsPacketSize) end, spinbox)
	g_keyboard.bindKeyPress("Enter", function() moveFunc() end, spinbox)

	scrollbar.onValueChange = function(self, value)
		value = math.cround(value, 25)
		giftWindow.contentPanel.currentAmount:setText(value)
		spinbox.onValueChange = nil
		spinbox:setValue(value)
		spinbox.onValueChange = spinBoxValueChange
	end

	scrollbar.onClick =
		function()
			local mousePos = g_window.getMousePosition()
			check()

			local sliderButton = scrollbar:getChildById('sliderButton')

			scrollbar:setSliderClick(sliderButton, sliderButton:getPosition())
			scrollbar:setSliderPos(sliderButton, sliderButton:getPosition(), {x = mousePos.x - sliderButton:getPosition().x, y = 0})
		end

	giftWindow.onEnter = function() g_client.setInputLockWidget(nil) transferCoins() end
	giftWindow.onEscape = cancelTransferFunc

	okButton.onClick = function() transferCoins() end
	cancelButton.onClick = cancelTransferFunc

	giftWindow.contentPanel.nameText:recursiveFocus(2)
end

function onRecipientTextChange(widget)
	if not giftWindow then
		return
	end

	if #widget:getText() < 2 then
		giftWindow.contentPanel.buttonOk:setEnabled(false)
	else
		giftWindow.contentPanel.buttonOk:setEnabled(true)
	end
end

function transferCoins()
	if not giftWindow then return end
	local amount = 0
	amount = tonumber(giftWindow.contentPanel.currentAmount:getText())
	local recipient = giftWindow.contentPanel.nameText:getText()

	g_game.transferCoins(recipient, amount)
	giftWindow.contentPanel.nameText:setText('')
	giftWindow.contentPanel.currentAmount:setText('0')
	cancelTransferFunc()
end

function cancelTransferFunc()
	giftWindow:destroy()
	giftWindow = nil
	if not StoreWindow:isVisible() then
		g_client.setInputLockWidget(nil)
		showStoreWindow()
	end
end
