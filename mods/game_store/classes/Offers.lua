if not Offers then
	Offers = {}
	Offers.__index = Offers
end

Offers.displayPanel = nil
Offers.redirect = nil
Offers.displayOffer = nil
Offers.offers = nil
Offers.currentFilter = ''
Offers.reasons = {}
Offers.selectedWidget = nil
Offers.preBuySelectedName = nil
Offers.event = nil
Offers.completePurchaseEvent = nil
Offers.gotoEvent = nil
Offers.coinCheck = nil
Offers.loadOffersEvent = nil
Offers.clientOffers = {}
Offers.buildGeneration = 0
Offers.renderKey = nil
Offers.configureKey = nil

local OFFER_BUILD_CHUNK_SIZE = 10
local INSUFFICIENT_COINS_MESSAGE = "You don't have enough coins"

local function removeBuyTooltipOverlay(id)
	if not Offers.displayPanel then
		return
	end

	local overlay = Offers.displayPanel:recursiveGetChildById(id)
	if overlay then
		overlay:destroy()
	end
end

local function clearWidgetImageRequest(widget)
	if widget and widget.currentImageRequest ~= nil then
		Store.imageRequests[widget.currentImageRequest] = nil
		widget.currentImageRequest = nil
	end
end

local function getTryOnData(offer)
	if not offer or (tonumber(offer.tryMode) or 0) <= 0 then
		return nil
	end

	if offer.offerType == CATEGORY_OUTFIT then
		local outfitId = tonumber(offer.maleOutfit) or 0
		if outfitId <= 0 then
			outfitId = tonumber(offer.type) or 0
		end

		if outfitId > 0 then
			return {
				kind = "outfit",
				id = outfitId,
				offerId = tonumber(offer.id) or 0,
				name = offer.name or tr("Store Outfit"),
				addons = tonumber(offer.addons) or 3
			}
		end
	elseif offer.offerType == CATEGORY_MOUNT then
		local mountId = tonumber(offer.mountId) or 0
		if mountId > 0 then
			return {
				kind = "mount",
				id = mountId,
				offerId = tonumber(offer.id) or 0,
				name = offer.name or tr("Store Mount")
			}
		end
	end

	return nil
end

function Offers:clearSelectionState()
	Offers.selectedWidget = nil

	if Offers.event then
		Offers.event:cancel()
		Offers.event = nil
	end

	removeEvent(Offers.gotoEvent)
	Offers.gotoEvent = nil

	local panel = Offers.displayPanel
	if not panel or panel:isDestroyed() then
		return
	end

	removeBuyTooltipOverlay('buy1TooltipOverlay')
	removeBuyTooltipOverlay('buy2TooltipOverlay')

	if panel.offerName then
		panel.offerName:setText("")
	end

	if panel.infopanel then
		if panel.infopanel.outfit then
			panel.infopanel.outfit:setCreature(nil)
		end
		if panel.infopanel.item then
			panel.infopanel.item:setItem(nil)
		end
		if panel.infopanel.image then
			clearWidgetImageRequest(panel.infopanel.image)
			panel.infopanel.image:setImageSource('')
		end
	end

	if panel.tryOn then
		panel.tryOn.onClick = function() end
		panel.tryOn:setVisible(false)
	end

	if panel.buy1 then
		panel.buy1.onClick = function() end
		panel.buy1:setOn(false)
		panel.buy1:setTooltip('')
		panel.buy1:disable()
	end

	if panel.buy2 then
		panel.buy2.onClick = function() end
		panel.buy2:setOn(false)
		panel.buy2:setTooltip('')
		panel.buy2:setVisible(false)
		panel.buy2:disable()
	end
end

local function createBuyTooltipOverlay(button, id, disabledReason, rawMessage)
	removeBuyTooltipOverlay(id)

	if not Offers.displayPanel or not button or not disabledReason or disabledReason == '' then
		return
	end

	local tooltipText = disabledReason
	if rawMessage then
		tooltipText = string.format("[color=#ff0000]%s[/color]", disabledReason)
	else
		local message = tr("The product is not available for this character:\n\n%s", disabledReason)
		tooltipText = string.format("[color=#ff0000]%s[/color]", message)
	end

	local overlay = g_ui.createWidget('UIWidget', Offers.displayPanel)
	overlay:setId(id)
	overlay:setFocusable(false)
	overlay:setSize(button:getSize())
	overlay:setPosition(button:getPosition())
	overlay:parseColoreDisplayToolTip(tooltipText)
	overlay:setOpacity(0)
	overlay:addAnchor(AnchorLeft, button:getId(), AnchorLeft)
	overlay:addAnchor(AnchorTop, button:getId(), AnchorTop)
	overlay:raise()
end

local function getCoinsBalance(subOffer)
	if not subOffer then
		return 0
	end

	if subOffer.coinType == COIN_TYPE_TRANSFERABLE then
		return Store.transferableCoins or 0
	elseif subOffer.coinType == COIN_TYPE_TOURNAMENT then
		return Store.tournamentCoins or 0
	end

	if Store.singleCoinBalance then
		return Store.coins or 0
	end

	return (Store.coins or 0) + (Store.transferableCoins or 0)
end

local function hasEnoughCoins(subOffer)
	if not subOffer then
		return false
	end

	return getCoinsBalance(subOffer) >= (subOffer.price or 0)
end

local function showInsufficientCoinsError()
	if buyOfferWindow and buyOfferWindow:isVisible() then
		buyOfferWindow:hide()
		g_client.setInputLockWidget(nil)
	end

	local title = tr('Purchase Error')
	local message = tr(INSUFFICIENT_COINS_MESSAGE)
	if displayErrorBox then
		displayErrorBox(title, message)
		return true
	end

	if showError then
		showError(title, message)
	end

	return true
end

local function setBuyButtonAvailable(button, overlayId, subOffer, onClick)
	removeBuyTooltipOverlay(overlayId)

	if not button then
		return false
	end

	button.onClick = function() end
	button:setImageSource("/images/store/buybutton")
	button:setTooltip('')
	button:setOn(false)
	button:disable()

	if not subOffer then
		return false
	end

	if subOffer.disabledReason and subOffer.disabledReason ~= '' then
		createBuyTooltipOverlay(button, overlayId, subOffer.disabledReason)
		return false
	end

	if not hasEnoughCoins(subOffer) then
		createBuyTooltipOverlay(button, overlayId, tr(INSUFFICIENT_COINS_MESSAGE), true)
		return false
	end

	button:enable()
	button:setOn(true)
	button.onClick = onClick
	return true
end

local function findSubOfferById(offerId)
	for _, offer in ipairs(Offers.displayOffer or {}) do
		for _, subOffer in ipairs(offer.offers or {}) do
			if subOffer.id == offerId then
				return subOffer, offer
			end
		end
	end

	return nil, nil
end

function Offers:stopAllEvents()
	removeEvent(HomeOffer.event)
	removeEvent(HomeOffer.timerEvent)
	removeEvent(Offers.event)
	removeEvent(Offers.gotoEvent)
	removeEvent(Offers.coinCheck)
	removeEvent(Offers.loadOffersEvent)
	HomeOffer.event = nil
	HomeOffer.timerEvent = nil
	Offers.event = nil
	Offers.gotoEvent = nil
	Offers.coinCheck = nil
	Offers.loadOffersEvent = nil
	Offers.buildGeneration = Offers.buildGeneration + 1
end

local function getOffersSignature(categoryName, offers, redirect, currentFilter)
	local parts = { tostring(categoryName or ""), tostring(redirect or 0), tostring(currentFilter or "") }
	for _, offer in ipairs(offers or {}) do
		parts[#parts + 1] = tostring(offer.id or 0)
		parts[#parts + 1] = tostring(offer.filter or "")
		for _, subOffer in ipairs(offer.offers or {}) do
			parts[#parts + 1] = string.format("%s:%s:%s", subOffer.id or 0, subOffer.price or 0, subOffer.count or 0)
		end
	end
	return table.concat(parts, "|")
end

function Offers:configure(categoryName, offers, redirect, sortingType, filters, currentFilter, reasons)
	local startedAt = g_clock.millis()
	local configureKey = getOffersSignature(categoryName, offers, redirect, currentFilter)
	if Offers.configureKey == configureKey and Offers.displayPanel and not Offers.displayPanel:isDestroyed() and
		Offers.displayPanel:getId() == categoryName then
		Store:profileStep("Offers:configure cached", startedAt)
		return
	end

	if Offers.displayPanel then
		Offers.displayPanel:destroy()
		Offers.displayPanel = nil
	end
	Offers.selectedWidget = nil

	Offers:stopAllEvents()

	Offers.displayPanel = g_ui.createWidget('GeneralOffersPanel', StoreWindow.contentPanel)
	Offers.displayPanel:setId(categoryName)

	Offers.offers = offers
	Offers.redirect = redirect

	Offers.displayPanel.optionsMaped.customOptions:clearOptions()
	Offers.displayPanel.optionsMaped.customOptions:addOption("Show All")
	for i, pid in pairs(filters) do
		Offers.displayPanel.optionsMaped.customOptions:addOption(pid)
	end

	Offers.displayPanel.optionsMaped.customOptions:setCurrentOption(currentFilter ~= "" and "" or "Show All")

	Offers.currentFilter = currentFilter

	Offers.reasons = reasons
	Offers.clientOffers = {}
	Offers.configureKey = configureKey
	Offers:checkOrder(nil, sortingType, currentFilter)
	Store:profileStep("Offers:configure", startedAt)
end

function Offers:checkOrder(self, currentIndex, currentFilter)
	Offers.displayOffer = {}
	for _, offer in ipairs(Offers.offers or {}) do
		Offers.displayOffer[#Offers.displayOffer + 1] = offer
	end
	if not Offers.displayOffer then
		return Offers:refreshOffers(Offers.displayOffer, Offers.redirect, currentFilter)
	end
	if currentIndex == 1 then
		table.sort(Offers.displayOffer, function (a, b) return a.TimesBought < b.TimesBought end)
	elseif currentIndex == 2 then
		table.sort(Offers.displayOffer, function (a, b) return a.name:upper() < b.name:upper() end)
	end

	Offers:refreshOffers(Offers.displayOffer, Offers.redirect, currentFilter)
end

local function getOfferUI(offer)
	if offer.itemId ~= 0 then
		return 'ItemOffer'
	elseif offer.icon ~= "" then
		return 'ImageOffer'
	elseif offer.offerType >= 1 and offer.offerType <= 4 then
		return 'CreatureOffer'
	else
		return 'ImageOffer'
	end
end

function calldescription(offerId)
	if Offers.event then Offers.event:cancel() end
	Offers.event =  scheduleEvent(function()
		g_game.doThing(false)
		g_game.requestOfferDescription(offerId)
		g_game.doThing(true)
	end, Store.displayDescription)
end

function Offers:refreshOffers(displayOffer, redirect, filter)
	if not displayOffer or not Offers.displayPanel then
		return
	end

	if offerCheckBox then
		offerCheckBox:destroy()
	end

	offerCheckBox:clearSelected()
	local offerPanel = Offers.displayPanel:recursiveGetChildById("offers")
	if not offerPanel then
		return
	end

	local renderKey = getOffersSignature(Offers.displayPanel:getId(), displayOffer, redirect, Offers.currentFilter)
	if Offers.renderKey == renderKey and #offerPanel:getChildren() > 0 then
		return
	end
	Offers.renderKey = renderKey
	local willCreateOffers = false
	for _, offer in ipairs(displayOffer) do
		if Offers.currentFilter == '' or string.lower(Offers.currentFilter) == string.lower(offer.filter) then
			willCreateOffers = true
			break
		end
	end
	if not willCreateOffers then
		Offers:clearSelectionState()
	end
	offerPanel:destroyChildren()

	removeEvent(Offers.coinCheck)
	removeEvent(Offers.loadOffersEvent)
	Offers.coinCheck = nil
	Offers.loadOffersEvent = nil
	Offers.buildGeneration = Offers.buildGeneration + 1
	local generation = Offers.buildGeneration
	local refreshStartedAt = g_clock.millis()
	local offerTotalCount = 0
	local nextOfferIndex = 1

	local function buildNextChunk()
		if generation ~= Offers.buildGeneration or not Offers.displayPanel or Offers.displayPanel:isDestroyed() or
			not offerPanel or offerPanel:isDestroyed() then
			return
		end

		local chunkStartedAt = g_clock.millis()
		local createdInChunk = 0
		while nextOfferIndex <= #displayOffer and createdInChunk < OFFER_BUILD_CHUNK_SIZE do
		local counter = nextOfferIndex
		local offer = displayOffer[counter]
		nextOfferIndex = nextOfferIndex + 1
		local matchesFilter = Offers.currentFilter == '' or
			string.lower(Offers.currentFilter) == string.lower(offer.filter)
		if matchesFilter then

		local widget = g_ui.createWidget(getOfferUI(offer), offerPanel)
		widget:setId(offer.id)
		widget.name:setText(offer.name)
		widget.onHoverChange = function(_, hovered)
			if Offers.selectedWidget == widget then
				return
			end
			widget:setBorderWidth(hovered and 1 or 0)
			if hovered then
				widget:setBorderColor('#B8B8B8')
				Store:safePulse(widget)
			end
		end
		Offers.clientOffers[offer.id] = ""
		local color = ''
		if offer.state == OFFER_STATE_NEW then
			widget.name:setColor("$var-text-cip-color-green")
			widget.flag:setVisible(true)
			widget.flag:setSize("78 78")
			widget.flag:setImageSource("/images/store/new")
			color = "$var-text-cip-color-green"
		elseif offer.state == OFFER_STATE_SALE then
			widget.name:setColor("$var-text-cip-store-sale")
			widget.flag:setVisible(true)
			widget.flag:setSize("28 28")
			widget.flag:setImageSource("/images/store/store-flag-sale")
			color = "$var-text-cip-store-sale"
		elseif offer.state == OFFER_STATE_TIMED then
			widget.name:setColor("$var-text-cip-store-timed")
			widget.flag:setVisible(true)
			widget.flag:setSize("10 15")
			widget.flag:setImageSource("/images/store/store-flag-expires")
			color = "$var-text-cip-store-timed"
		end

		if offerTotalCount == 0 then
			widget.onClick = function()
				calldescription(offer.id)
			end
		end
		if offer.icon ~= "" then
			local currentWidget = widget.image
			currentWidget.currentImageRequest = Store.currentRequest
			Store.imageRequests[Store.currentRequest] = currentWidget
			Store.currentRequest = Store.currentRequest + 1

			currentWidget:insertLuaCall("onDestroy")
			currentWidget.onDestroy = function()
				Store.imageRequests[currentWidget.currentImageRequest] = nil
			end

			Store:downloadImage(currentWidget.currentImageRequest, "64/"..offer.icon)
    	elseif offer.itemId ~= 0 then
			widget.item:setItemId(offer.itemId)
			widget.item:hook()
		elseif offer.offerType == CATEGORY_MOUNT then
			local outfit = {
				type = offer.mountId
			}

			widget.creature:setOutfit(outfit)
		elseif offer.offerType == CATEGORY_OUTFIT then
			local outfit = {
				type = offer.type,
				head = offer.head,
				body = offer.body,
				legs = offer.legs,
				feet = offer.feet,
				addons = 3,
			}

			widget.creature:setOutfit(outfit)
		elseif offer.offerType == CATEGORY_HIRELING then
			local outfit = {
				type = offer.maleOutfit,
				head = offer.head,
				body = offer.body,
				legs = offer.legs,
				feet = offer.feet,
				addons = 3,
			}

			widget.creature:setOutfit(outfit)
		end

		local selected = false
		-- setup price
		local count = 0
		for i = #offer.offers, 1, -1 do
			local subOffer = offer.offers[i]
			if subOffer.id == redirect then
				selected = true
			end

			if offer.state == OFFER_STATE_SALE then
				local daysLeft = math.floor((subOffer.saleValidUntilTimestamp - os.time()) / 86400)
				Offers.clientOffers[offer.id] = string.format("<font color=\"#ECAC46\">{star} Valid until %s{star} %d days left<br /></font>", os.date("%Y-%m-%d, %X", subOffer.saleValidUntilTimestamp), daysLeft)
			end

			-- check price   subOffer.price
			if not hasEnoughCoins(subOffer) then
				local slot = subOffer.coinType == COIN_TYPE_TRANSFERABLE and (i == 2 and 1 or 2) or i
				widget:getChildById("price" .. slot):setColor("$var-text-cip-store-red")
				widget.coinCheck = true
			end

			local canChange = false
			for _, i in pairs(subOffer.disabledReasons) do
				canChange = true
				subOffer.disabledReason = string.format("%s* %s\n", subOffer.disabledReason, Offers.reasons[i.reasonId])
			end

			if subOffer.disabledReason ~= '' then
				subOffer.disabledReason = string.sub(subOffer.disabledReason, 1, -2)
			end

			if count == 0 then
				if subOffer.price > 0 then
					widget.price1:setText(formatMoney(subOffer.price, ","))
				else
					widget.price1:setText("Free")
				end
				if subOffer.count > 1 or #offer.offers > 1 then
					widget.count1:setText(subOffer.count .. "x")
					if not string.empty(color) then
						widget.count1:setColor(color)
					end
				else
					widget.count1:setVisible(false)
				end
				if subOffer.basePrice > 0 and subOffer.basePrice ~= subOffer.price then
					local percentageChange = ((subOffer.price - subOffer.basePrice) / subOffer.basePrice) * 100
					-- Timestamp alvo
					local targetTimestamp = subOffer.saleValidUntilTimestamp
					local currentTimestamp = os.time()
					local differenceInSeconds = targetTimestamp - currentTimestamp

					-- Converter a diferen�a em dias
					local differenceInDays = (differenceInSeconds / (60 * 60 * 24)) - 1

					widget.priceOff:setVisible(true)
					widget.priceOff:setText(formatMoney(subOffer.basePrice, ","))
					widget.priceOff:setTooltip(string.format("%d%%, %d d left", percentageChange, math.ceil(differenceInDays)))
				end
			else
				widget.price2:setVisible(true)
				if subOffer.price == 0 then
					widget.price2:setText("Free")
				else
					widget.price2:setText(formatMoney(subOffer.price, ","))
				end
				if subOffer.count > 1 or #offer.offers > 1 then
					widget.count2:setVisible(true)
					widget.count2:setText(subOffer.count .. "x")
					if not string.empty(color) then
						widget.count2:setColor(color)
					end
				else
					widget.count2:setVisible(false)
				end
			end

			if #subOffer.disabledReasons > 0 and canChange then
				Offers:setDisableShader(widget, subOffer.disabledReason, false, offer.state)
			end

			if subOffer.coinType == COIN_TYPE_TRANSFERABLE then
				widget:setImageClip("0 ".. count * 80 .." 240 82")
			else
				widget:setImageClip("0 ".. (count * 80) + 159 .." 240 82")
			end
			count = count + 1
		end

		widget.offer = offer


		offerCheckBox:addWidget(widget)
		if redirect == 0 and offerTotalCount == 0 then
			Offers.step = offerTotalCount
			widget:focus()
			offerCheckBox:selectWidget(widget)
			Offers.gotoEvent = scheduleEvent(function() Offers:gotoRedirect() end, 300)
			calldescription(offer.id)
		elseif selected then
			Offers.step = offerTotalCount
			widget:focus()
			Offers.gotoEvent = scheduleEvent(function() Offers:gotoRedirect() end, 300)
			offerCheckBox:selectWidget(widget)
			calldescription(offer.id)
		end

		offerTotalCount = offerTotalCount + 1
		createdInChunk = createdInChunk + 1
		end
	end

		Store:profileStep("widget chunk build", chunkStartedAt)
		if nextOfferIndex <= #displayOffer then
			Offers.loadOffersEvent = scheduleEvent(buildNextChunk, 1)
			return
		end

	if offerTotalCount == 0 then
		Offers:clearSelectionState()
	end

	Offers:checkOfferValue()

	if Offers.preBuySelectedName then
		for _,offer in pairs(offerPanel:getChildren()) do
		  if offer.name:getText() == Offers.preBuySelectedName then
			Offers:onSelectionOffer(nil, offer)
		  end
		end
	end
	Offers.preBuySelectedName = nil

		Offers.loadOffersEvent = nil
		Store:profileStep("Offers:refreshOffers", refreshStartedAt)
	end

	Offers.loadOffersEvent = scheduleEvent(buildNextChunk, 1)
end

function Offers:gotoRedirect()
	if not Offers.displayPanel or Offers.displayPanel:getId() == "Home" then
		return
	end

	if not Offers.displayPanel.offerListScrollBar then
		return
	end
	local scroll = Offers.displayPanel.offerListScrollBar
	if scroll then
		scroll:setValue(Offers.step * 80)
	end
end

-- Product_PremiumTime180.png
function Offers:setDisableShader(widget, disabledReason, active, state)
	widget.grayHover:setVisible(not active)

	if widget.image then
		widget.image:setImageShader("image_disabled")
	end

	-- modify strings
	if not active then
		local c_color = "$var-text-cip-store-disabled"
		if state == OFFER_STATE_NEW then
			c_color = "$var-text-cip-color-green-disabled"
		elseif state == OFFER_STATE_SALE then
			c_color = "$var-text-cip-store-sale-disabled"
		elseif state == OFFER_STATE_TIMED then
			c_color = "$var-text-cip-store-timed-disabled"
		end

		widget.name:setColor(c_color)

		local color = "$var-text-cip-store-disabled"

		widget.price1:setColor(color)
		widget.price2:setColor(color)

		widget.count1:setColor(c_color)
		widget.count2:setColor(c_color)
	end
end

function Offers:refreshOptions(widgetId, currentIndex)
	local text = currentIndex.text
	if text == 'Show All' then
		text = ''
	end

	-- evitar criar novas UI
	if text == Offers.currentFilter then
		return
	end

	Offers.currentFilter = text
	Offers:refreshOffers(Offers.displayOffer, Offers.redirect, Offers.currentFilter)
end


function Offers:onSelectionOffer(_, selectedWidget)
	if Offers.selectedWidget and not Offers.selectedWidget:isDestroyed() then
		Offers.selectedWidget:setBorderWidth(0)
	end

	Offers.selectedWidget = selectedWidget
	if not selectedWidget or not Offers.displayPanel.offerName then
		return
	end

	if Offers.displayPanel.tryOn then
		Offers.displayPanel.tryOn.onClick = function() end
		Offers.displayPanel.tryOn:setVisible(false)
	end

	Offers.selectedWidget:setBorderWidth(2)
	Offers.selectedWidget:setBorderColor('#FFFFFF')
	-- configure

	Offers.displayPanel.offerName:setText(selectedWidget.name:getText())

	Offers.displayPanel.infopanel.outfit:setCreature(nil)
	Offers.displayPanel.infopanel.item:setItem(nil)
	Offers.displayPanel.infopanel.image:setImageSource('')

	local offer = Offers.selectedWidget.offer
	calldescription(offer.id)

	if offer.icon ~= "" then
		local widget = Offers.displayPanel.infopanel.image
		if selectedWidget.image.imagePath then
			clearWidgetImageRequest(widget)
			widget:setImageSize("126 126")
			widget:setImageSmooth(false)
			widget:setImageSource(selectedWidget.image.imagePath)
		else
			clearWidgetImageRequest(widget)
			widget.currentImageRequest = Store.currentRequest
			Store.imageRequests[Store.currentRequest] = widget
			Store.currentRequest = Store.currentRequest + 1

			if not widget.storeImageDestroyHook then
				widget:insertLuaCall("onDestroy")
				widget.onDestroy = function()
					clearWidgetImageRequest(widget)
				end
				widget.storeImageDestroyHook = true
			end

			Store:downloadImage(widget.currentImageRequest, "64/"..offer.icon)
		end

	elseif offer.itemId ~= 0 then
		local item = Offers.displayPanel.infopanel.item
		item:setItemId(offer.itemId)
		item:hook()
	elseif offer.offerType == CATEGORY_MOUNT then
		local outfit = {
			type = offer.mountId
		}

		Offers.displayPanel.infopanel.outfit:setOutfit(outfit)
	elseif offer.offerType == CATEGORY_OUTFIT then
		local outfit = {
			type = offer.type,
			head = offer.head,
			body = offer.body,
			legs = offer.legs,
			feet = offer.feet,
			addons = 3,
		}

		Offers.displayPanel.infopanel.outfit:setOutfit(outfit)
	elseif offer.offerType == CATEGORY_HIRELING then
		local outfit = {
			type = offer.maleOutfit,
			head = offer.head,
			body = offer.body,
			legs = offer.legs,
			feet = offer.feet,
			addons = 3,
		}

		Offers.displayPanel.infopanel.outfit:setOutfit(outfit)
	end

	if offer.offers[1].count > 1 then
		Offers.displayPanel.buy1:setText("Buy " .. offer.offers[1].count)
	else
		Offers.displayPanel.buy1:setText("Buy")
	end

	local tryOnData = getTryOnData(offer)
	if tryOnData then
		Offers.displayPanel.tryOn:setVisible(true)
		Offers.displayPanel.tryOn.onClick = function()
			if modules.game_outfit and modules.game_outfit.setStoreTryOn then
				modules.game_outfit.setStoreTryOn(tryOnData)
			end
			g_client.setInputLockWidget(nil)
			StoreWindow:hide()
			g_game.requestOutfit()
		end
	else
		Offers.displayPanel.tryOn:setVisible(false)
	end

	local unavailable = false
	removeBuyTooltipOverlay('buy1TooltipOverlay')
	removeBuyTooltipOverlay('buy2TooltipOverlay')
	Offers.displayPanel.buy1:setTooltip('')
	Offers.displayPanel.buy2:setTooltip('')
	Offers.displayPanel.price1.price:setColor("$var-text-cip-color")
	Offers.displayPanel.price2.price:setColor("$var-text-cip-color")
	local hasBalance1 = hasEnoughCoins(offer.offers[1])
	if not hasBalance1 then
		Offers.displayPanel.price1.price:setColor("$var-text-cip-store-red")
	end

	if offer.offers[1].disabledReason and offer.offers[1].disabledReason ~= '' then
		unavailable = true
	end
	setBuyButtonAvailable(Offers.displayPanel.buy1, 'buy1TooltipOverlay', offer.offers[1], function()
		buyStoreOffer(offer, offer.offers[1])
	end)

	if offer.RequiresConfiguration == 1 then
		Offers.displayPanel.buy1:setText(tr("Configure"))
	end

	if offer.offers[1].price > 0 then
		Offers.displayPanel.price1.price:setText(formatMoney(offer.offers[1].price, ","))
	else
		Offers.displayPanel.price1.price:setText("Free")
	end
	Offers.displayPanel.price1.image:setImageSource(offer.offers[1].coinType ~= COIN_TYPE_TRANSFERABLE and "/images/store/icon-tibiacoin" or "/images/store/icon-tibiacointransferable")

	if offer.offers[1].basePrice > 0 and offer.offers[1].basePrice ~= offer.offers[1].price then
		local percentageChange = ((offer.offers[1].price - offer.offers[1].basePrice) / offer.offers[1].basePrice) * 100
		-- Timestamp alvo
		local targetTimestamp = offer.offers[1].saleValidUntilTimestamp
		local currentTimestamp = os.time()
		local differenceInSeconds = targetTimestamp - currentTimestamp

		-- Converter a diferen?a em dias
		local differenceInDays = (differenceInSeconds / (60 * 60 * 24)) - 1

		local priceOff = Offers.displayPanel.price1.priceOff
		priceOff:setVisible(true)
		if priceOff:isVisible() then
			Offers.displayPanel.price1.image:setMarginLeft(45)
		end
		Offers.displayPanel.price1.priceOff:setText(formatMoney(offer.offers[1].basePrice, ","))
		Offers.displayPanel.price1.priceOff:setTooltip(string.format("%d%%, %d d left", percentageChange, math.ceil(differenceInDays)))
	else
		Offers.displayPanel.price1.priceOff:setVisible(false)
	end

	if #offer.offers > 1 then
		Offers.displayPanel.buy2:setVisible(true)
		Offers.displayPanel.price2:setVisible(true)
		Offers.displayPanel.buy2:setText("Buy " .. offer.offers[2].count)
		if offer.offers[2].price > 0 then
			Offers.displayPanel.price2.price:setText(formatMoney(offer.offers[2].price, ","))
		else
			Offers.displayPanel.price2.price:setText("Free")
		end
		Offers.displayPanel.price2.image:setImageSource(offer.offers[2].coinType ~= COIN_TYPE_TRANSFERABLE and "/images/store/icon-tibiacoin" or "/images/store/icon-tibiacointransferable")

		Offers.displayPanel.buy2:setImageSource("/images/store/buybutton")
		local hasBalance2 = hasEnoughCoins(offer.offers[2])
		if not hasBalance2 then
			Offers.displayPanel.price2.price:setColor("$var-text-cip-store-red")
		end

		if offer.offers[2].disabledReason and offer.offers[2].disabledReason ~= '' then
			unavailable = true
		end
		setBuyButtonAvailable(Offers.displayPanel.buy2, 'buy2TooltipOverlay', offer.offers[2], function()
			buyStoreOffer(offer, offer.offers[2])
		end)
	else
		Offers.displayPanel.buy2:setVisible(false)
		Offers.displayPanel.price2:setVisible(false)
		removeBuyTooltipOverlay('buy2TooltipOverlay')
		Offers.displayPanel.buy2:disable()
	end

	if unavailable then
		Offers.displayPanel.description.error:setText('The product is currently not available\nfor this character. See the Buy button\ntooltip for details.\n ')
		Offers.displayPanel.description.error:setHeight(60)
		Offers.displayPanel.description.error:setVisible(true)
	else
		Offers.displayPanel.description.error:setText('')
		Offers.displayPanel.description.error:setHeight(0)
		Offers.displayPanel.description.error:setVisible(false)
	end

	Offers.displayPanel.description.image:setHeight(600)
	Offers.displayPanel.description.package:destroyChildren()
	Offers.displayPanel.description.package:setHeight(20)
	if offer.bundles and #offer.bundles > 0 then
		Offers.displayPanel.description.image:setHeight(500)
		local size = 0
		g_ui.createWidget('PackageLabel', Offers.displayPanel.description.package)
		size = 30

		for i, bundles in pairs(offer.bundles) do
			size = size + 64
			if bundles.offerType == 3 then
				local ui = g_ui.createWidget('CreatureLabel', Offers.displayPanel.description.package)
				ui.creature:setOutfit({ auxType = bundles.itemId})
				ui.name:setText(bundles.name)
			elseif bundles.offerType == 1 then
				local ui = g_ui.createWidget('CreatureLabel', Offers.displayPanel.description.package)
				ui.creature:setOutfit({type = bundles.mountId})
				ui.name:setText(bundles.name)
			elseif bundles.offerType == 2 then
				local ui = g_ui.createWidget('CreatureLabel', Offers.displayPanel.description.package)
				ui.creature:setOutfit({
					type = bundles.type,
					head = bundles.head,
					body = bundles.body,
					legs = bundles.legs,
					feet = bundles.feet,
					addons = 3,
				})
				ui.name:setText(bundles.name)
			end
		end
		Offers.displayPanel.description.package:setHeight(size)
	end
end

function Offers:configureDescription(offerId, description)
	if not description or not Offers.clientOffers[offerId] then
		return true
	end

	local desc = Offers.displayPanel:recursiveGetChildById("description")
	if not desc or not desc.image then
		return
	end

	if Offers.clientOffers[offerId] ~= "" then
		description = Offers.clientOffers[offerId] .. "\n" .. description
	end

	local novo_texto = string.gsub(description, "\n", "<br/>")
	novo_texto = string.gsub(novo_texto, "<br>", "<br/>")
	novo_texto = string.gsub(novo_texto, "{info}", '<img src="/images/store/store-icons-inline_1.png" width="13" height="13" />')
	novo_texto = string.gsub(novo_texto, "{character}", '<img src="/images/store/store-icons-inline_2.png" width="13" height="13" />only usable by purchasing character')
	novo_texto = string.gsub(novo_texto, "{activated}", '<img src="/images/store/store-icons-inline_11.png" width="13" height="13" />activated at purchase')
	novo_texto = string.gsub(novo_texto, "{useicon}", '<img src="/images/store/store-icons-inline_14.png" width="13" height="13" />')
	novo_texto = string.gsub(novo_texto, "{limit|(%d+)}", '<img src="/images/store/store-icons-inline_7.png" width="13" height="13" />maximum amount that can be owned by character: %1')
	novo_texto = string.gsub(novo_texto, "{house}", '<img src="/images/store/store-icons-inline_6.png" width="13" height="13" />can only be unwrapped in a house owned by the purchasing character')
	novo_texto = string.gsub(novo_texto, "{box}", '<img src="/images/store/store-icons-inline_4.png" width="13" height="13" />comes in a box which can only be unwrapped by purchasing character')
	novo_texto = string.gsub(novo_texto, "{storeinbox}", '<img src="/images/store/store-icons-inline_5.png" width="13" height="13" />will be sent to your Store inbox and can only be stored there and in depot box')
	novo_texto = string.gsub(novo_texto, "{usablebyallicon}", '<img src="/images/store/store-icons-inline_3.png" width="13" height="13" />')
	novo_texto = string.gsub(novo_texto, "{backtoinbox}", '<img src="/images/store/store-icons-inline_8.png" width="13" height="13" />will be wrapped back and sent to inbox if the purchasing character is no longer the house owner')
	novo_texto = string.gsub(novo_texto, "{storeinboxicon}", '<img src="/images/store/store-icons-inline_8.png" width="13" height="13" />')
	novo_texto = string.gsub(novo_texto, "{capacity}", '<img src="/images/store/store-icons-inline_13.png" width="13" height="13" /><i>cannot be purchased if capacity is exceeded</i>')
	novo_texto = string.gsub(novo_texto, "{speedboost}", '<img src="/images/store/store-icons-inline_10.png" width="13" height="13" />provides character with a speed boost')
	novo_texto = string.gsub(novo_texto, "{battlesign}", '<img src="/images/store/store-icons-inline_12.png" width="13" height="13" />cannot be purchased by characters with protection zone block or battle sign')
	novo_texto = string.gsub(novo_texto, "{once}", '<img src="/images/store/store-icons-inline_7.png" width="13" height="13" />can only be purchased once')
	novo_texto = string.gsub(novo_texto, "{star}", '<img src="/images/icons/star_filled.png" width="9" height="10" />')


	desc.image:setHTML(novo_texto)


	-- Store:getDescription(currentWidget.currentImageRequest, offerId, Offers.clientOffers[offerId] .. novo_texto)
end

function buyStoreOffer(generalOffer, selectedOffer)
	if not hasEnoughCoins(selectedOffer) then
		return showInsufficientCoinsError()
	end

	if generalOffer.storeSubtype == "hireling" then
		return modules.game_store.onRequestPurchaseData(selectedOffer.id, OFFER_BUY_TYPE_HIRELING)
	end

	if not m_settings.getOption('storeAskBeforeBuyingProducts') then
		return modules.game_store.onBuyOffer(buyOfferWindow.okBuyButton, selectedOffer.id, generalOffer.offerType)
	end

	if buyOfferWindow:isVisible() then
		return true
	end

	StoreWindow:hide()
	g_client.setInputLockWidget(nil)

	buyOfferWindow:show(true)
	g_client.setInputLockWidget(buyOfferWindow)
	buyOfferWindow.productWarning:setText(tr('Do you want to buy the product "%dx %s"?', selectedOffer.count, generalOffer.name))

	buyOfferWindow.description.offerName:setText(tr('%dx %s', selectedOffer.count, generalOffer.name))
	buyOfferWindow.description.offerPrice:setText(tr('Price: %d', selectedOffer.price))
	buyOfferWindow.icon.creature:setOutfit({})
	buyOfferWindow.icon.image:setImageSource('')
	buyOfferWindow.icon.item:setItem(nil)
	buyOfferWindow.storeSubtype = generalOffer.storeSubtype

	local imageCoin = selectedOffer.coinType == COIN_TYPE_DEFAULT and 'tibiacoin' or 'tibiacointransferable'
	buyOfferWindow.description.coinType:setImageSource('/images/store/icon-' .. imageCoin)

	if generalOffer.icon ~= "" then
		local widget = buyOfferWindow.icon.image
		widget.currentImageRequest = Store.currentRequest
		Store.imageRequests[Store.currentRequest] = widget
		Store.currentRequest = Store.currentRequest + 1

		widget:insertLuaCall("onDestroy")
		widget.onDestroy = function()
			Store.imageRequests[widget.currentImageRequest] = nil
		end

		Store:downloadImage(widget.currentImageRequest, "64/"..generalOffer.icon)
	elseif generalOffer.itemId ~= 0 then
		buyOfferWindow.icon.item:setItemId(generalOffer.itemId)
	elseif generalOffer.offerType == 1 then
		local outfit = {
			type = generalOffer.mountId
		}

		buyOfferWindow.icon.creature:setOutfit(outfit)
	elseif generalOffer.offerType == 2 then
		local outfit = {
			type = generalOffer.type,
			head = generalOffer.head,
			body = generalOffer.body,
			legs = generalOffer.legs,
			feet = generalOffer.feet,
			addons = 3,
		}

		buyOfferWindow.icon.creature:setOutfit(outfit)
	end

	buyOfferWindow.okBuyButton.onClick = function()
		if not hasEnoughCoins(selectedOffer) then
			return showInsufficientCoinsError()
		end

		modules.game_store.onBuyOffer(buyOfferWindow.okBuyButton, selectedOffer.id, generalOffer.offerType)
	end
	return true
end

function onBuyOffer(widget, id, offerType, text, offerName)
	if widget:getId() == 'cancelButton' or text == 'cancelButton' then
		if buyOfferWindow and buyOfferWindow:isVisible() then
			buyOfferWindow:hide()
			g_client.setInputLockWidget(nil)
		end
		if not StoreWindow:isVisible() then
			showStoreWindow()
		end
	elseif widget:getId() == 'okBuyButton' then
		if buyOfferWindow.storeSubtype == "hireling" then
			if buyOfferWindow and buyOfferWindow:isVisible() then
				buyOfferWindow:hide()
				g_client.setInputLockWidget(nil)
			end
			buyOfferWindow.storeSubtype = nil
			return modules.game_store.onRequestPurchaseData(id, OFFER_BUY_TYPE_HIRELING)
		end

		local selectedOffer = findSubOfferById(id)
		if selectedOffer and not hasEnoughCoins(selectedOffer) then
			return showInsufficientCoinsError()
		end

		local productType = offerName and 10 or 0
		g_game.buyStoreOffer(id, productType, "", 0, offerName)
		Offers.preBuySelectedName = Offers.selectedWidget and Offers.selectedWidget.name:getText() or nil

		if buyOfferWindow and buyOfferWindow:isVisible() then
			buyOfferWindow:hide()
			g_client.setInputLockWidget(nil)
		end
	end

	local askButton = buyOfferWindow:recursiveGetChildById("storeAskBeforeBuyingProducts")
	askButton:setEnabled(true)
	buyOfferWindow.storeSubtype = nil
end

function onStorePurchase(message)
	SucessOfferWindow:show(true)
	StoreWindow:hide()
	buyOfferWindow:hide()
	g_client.setInputLockWidget(SucessOfferWindow)
	SucessOfferWindow.confirm.image:setImageSource('/images/store/purchasecomplete_idle')
	SucessOfferWindow.confirm.image:setImageClip("0 0 108 108")
	SucessOfferWindow.description.message:setText(message)
	scheduleEvent(function() SucessOfferWindow:focus() end, 50)
end

local function animateImage(widget, width, height, frame_init, frame_end, time)
	Store:safeAnimateImage(widget, width, height, frame_init, frame_end, time, false)
	return true
end

function completePurchase(widget, immediate)
	removeEvent(Offers.completePurchaseEvent)
	Offers.completePurchaseEvent = nil
	if widget then
		widget.image:setImageSource('/images/store/purchasecomplete_pressed')
		widget.image:setImageClip("0 0 108 108")
		animateImage(widget.image, 108, 108, 1, 13, 100)
	end

	local action = function()
		if SucessOfferWindow:isVisible() then
			SucessOfferWindow:hide()
		end
		g_client.setInputLockWidget(nil)
		showStoreWindow()
		Offers.completePurchaseEvent = nil
	end

	if immediate then
		action()
	else
		Offers.completePurchaseEvent = scheduleEvent(action, 1000)
	end
end

function Offers:checkOfferValue()
	local panel = Offers.displayPanel and Offers.displayPanel.offers
	if not panel then
		return
	end

	for _, widget in pairs(panel:getChildren()) do
		local offer = widget.offer
		widget.coinCheck = false
		for i = #offer.offers, 1, -1 do
			local subOffer = offer.offers[i]
			local slot = i == 2 and 1 or 2
			if #offer.offers == 1 then
				slot = 1
			end
			local priceSlot = widget:getChildById("price" .. slot)
			if priceSlot then
				local enoughCoins = hasEnoughCoins(subOffer)
				local disabled = widget.grayHover:isVisible()
				if enoughCoins then
					priceSlot:setColor(disabled and "$var-text-cip-store-disabled" or "$var-text-cip-color")
				else
					priceSlot:setColor(disabled and "$var-text-cip-store-red-disabled" or "$var-text-cip-store-red")
				end
				widget.coinCheck = widget.coinCheck or not enoughCoins
			end

			if #subOffer.disabledReasons > 0 then
				Offers:setDisableShader(widget, subOffer.disabledReason, false, offer.state)
			end
		end
	end
end

function Offers:updateCoinBalance()
	Offers:checkOfferValue()
	if Offers.selectedWidget and not Offers.selectedWidget:isDestroyed() and
		Offers.displayPanel and Offers.displayPanel.buy1 then
		Offers:onSelectionOffer(nil, Offers.selectedWidget)
	end
end
