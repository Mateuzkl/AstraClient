if not HomeOffer then
	HomeOffer = {}
	HomeOffer.__index = HomeOffer

	HomeOffer.offers = {}
	HomeOffer.dailyOffers = {}
	HomeOffer.homePanel = {}
	HomeOffer.event = nil
	HomeOffer.lastid = 0
	HomeOffer.dailyReroll = 0
	HomeOffer.dailyRerollWindow = nil
end

local function timerEvent(widget, endTime)
	if not widget or not widget:isVisible() or os.time() > endTime then
		return
	end

	local timeLeft = endTime - os.time()
	local hours = math.floor(timeLeft / 3600)
	local minutes = math.floor((timeLeft % 3600) / 60)
	local seconds = timeLeft % 60

	widget:setText(string.format("Ends in: %02d:%02d:%02d", hours, minutes, seconds))
	if hours == 0 and minutes <= 30 then
		widget:setColor("$var-text-cip-store-red")
	end

	scheduleEvent(function()
		timerEvent(widget, endTime)
	end, 1000)
end

function HomeOffer:configure(categoryName, offers, scrolling, homePanel, reasons, dailyOfferPrice, dailyOffers)
	if Offers.displayPanel then
		Offers.displayPanel:destroy()
	end

	Offers:stopAllEvents()

	Offers.displayPanel = g_ui.createWidget('HomePanel', StoreWindow.contentPanel)
	Offers.displayPanel:setId(categoryName)

	Offers.dailyPanel = Offers.displayPanel:recursiveGetChildById('discountOffersPanel')

	highlightWidget = Offers.displayPanel:recursiveGetChildById('borderImage')
	discountOffers = Offers.displayPanel:recursiveGetChildById('discountOffersLabel')
	highlightWidget:setImageShader("text_staff")
	discountOffers:setImageShader("text_staff")

	HomeOffer.offers = offers
	HomeOffer.scrolling = scrolling*1000
	HomeOffer.homePanel = homePanel
	HomeOffer.dailyReroll = dailyOfferPrice
	HomeOffer.dailyOffers = dailyOffers

	Offers.reasons = reasons

	HomeOffer:createOffers()
	HomeOffer.lastid = 0
	HomeOffer:configurePanels()
	if #HomeOffer.homePanel > 1 then
		Offers.displayPanel.prevBanner:setVisible(true)
		Offers.displayPanel.nextBanner:setVisible(true)
		HomeOffer.event = cycleEvent(function()
			HomeOffer:configurePanels()
		end, HomeOffer.scrolling)
	end

	if table.empty(HomeOffer.dailyOffers) then
		Offers.dailyPanel:setVisible(false)
		Offers.displayPanel.mainOffers:setHeight(328)
		highlightWidget:setVisible(false)
		return
	end

	local endTime = dailyOffers[1].expireTime
	timerEvent(Offers.dailyPanel.timerLabel, endTime)

	HomeOffer:createDailyOffers()
	StoreWindow.contentPanel.onVisibilityChange = function(widget, visible)
		if widget:isVisible() and not table.empty(dailyOffers) then
			local endTime = dailyOffers[1].expireTime
			timerEvent(Offers.dailyPanel.timerLabel, endTime)
		end
	end

	local rerollButton = StoreWindow.contentPanel:recursiveGetChildById('discountRerollButton')
	if not rerollButton then
		return
	end

	rerollButton.onClick = function(self) HomeOffer:onRerollDailyOffer(self) end

	rerollButton:setEnabled(Store.transferableCoins >= dailyOfferPrice)
	rerollButton:setTooltip(string.format("Reroll offers for %d Astra Coins", dailyOfferPrice))
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

function HomeOffer:onRerollDailyOffer(button)
	if HomeOffer.dailyRerollWindow then
		HomeOffer.dailyRerollWindow:destroy()
	end
	
	StoreWindow:hide()

	local okButton = function()
		HomeOffer.dailyRerollWindow:destroy()
		HomeOffer.dailyRerollWindow = nil
		g_client.setInputLockWidget(nil)
		g_game.buyStoreOffer(0, 11, "", 0, "")
	end

	local cancelButton = function()
		HomeOffer.dailyRerollWindow:destroy()
		HomeOffer.dailyRerollWindow = nil
		StoreWindow:show()
		g_client.setInputLockWidget(StoreWindow)
	end

	local message = string.format("Are you sure you want to reroll the daily offer for %d Astra Coins?", HomeOffer.dailyReroll)

	HomeOffer.dailyRerollWindow = displayGeneralBox(tr('Confirm reroll'), tr(message), {
		{ text=tr('Ok'), callback = okButton },
		{ text=tr('Cancel'), callback = cancelButton },
	}, okButton, cancelButton)

	g_client.setInputLockWidget(HomeOffer.dailyRerollWindow)
end

function HomeOffer:createOffers()
	Offers.displayPanel.mainOffers.offersPanel:destroyChildren()
	for _, offer in ipairs(HomeOffer.offers) do
		local widget = g_ui.createWidget(getOfferUI(offer), Offers.displayPanel.mainOffers.offersPanel)

		-- Setup dimensions
		widget:setImageSource("/images/store/store-offer-box-home")
		widget:setImageClip("0 0 254 82")
		widget:setSize(tosize("254 82"))

		widget:setId(offer.id)
		widget.name:setText(" " .. offer.name)
		local color = '$var-text-cip-color'
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

		widget.onHoverChange = function(self, hovered)
			if Offers.selectedWidget == widget then
				return
			end
			if hovered then
				widget:setBorderWidth(2)
				widget:setBorderColor('white')
			else
				widget:setBorderWidth(0)
			end
		end
		widget.onClick = function()
			g_game.requestStoreOffers(SERVICE_OFFER_ID, "", offer.id)
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
		elseif offer.offerType == 1 then
			local outfit = {
				type = offer.mountId
			}

			widget.creature:setOutfit(outfit)
		elseif offer.offerType == 2 then
			local outfit = {
				type = offer.type,
				head = offer.head,
				body = offer.body,
				legs = offer.legs,
				feet = offer.feet,
				addons = 3,
			}

			widget.creature:setOutfit(outfit)
		end

		-- setup price
		local count = 0
		for i = #offer.offers, 1, -1 do
			local subOffer = offer.offers[i]
			-- check price   subOffer.price

			for _, i in pairs(subOffer.disabledReasons) do
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
				if subOffer.count > 1 then
					widget.count1:setText(subOffer.count .. "x")
					widget.count1:setColor(color)
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
				if subOffer.price > 0 then
					widget.price2:setText(formatMoney(subOffer.price, ","))
				else
					widget.price2:setText("Free")
				end
				if subOffer.count > 1 then
					widget.count2:setVisible(true)
					widget.count2:setText(subOffer.count .. "x")
					widget.count2:setColor(color)
				else
					widget.count2:setVisible(false)
				end
			end

			if #subOffer.disabledReasons > 0 then
				Offers:setDisableShader(widget, subOffer.disabledReason, false, offer.state)
			end

			count = count + 1
		end
	end
end

function HomeOffer:createDailyOffers()
	for _, offer in ipairs(HomeOffer.dailyOffers) do
		local widget = g_ui.createWidget(getOfferUI(offer), Offers.dailyPanel.discountOffers)

		-- Setup dimensions
		widget:setImageSource("/images/store/store-offer-box-home")
		widget:setImageClip("0 0 254 82")
		widget:setSize(tosize("254 82"))

		widget:setId(offer.id)
		widget.name:setText(" " .. offer.name)
		local color = '$var-text-cip-color'
		if offer.state == OFFER_STATE_NEW then
			widget.name:setColor("$var-text-cip-color-green")
			widget.flag:setVisible(true)
			widget.flag:setSize("78 78")
			widget.flag:setImageSource("/images/store/new")
			color = "$var-text-cip-color-green"
		elseif offer.state == OFFER_STATE_SALE then
			widget.name:setColor("$var-text-cip-store-sale")
			widget.flag:setVisible(true)
			widget.flag:setImageSource("/images/store/store-flag-sale")
			color = "$var-text-cip-store-sale"
		elseif offer.state == OFFER_STATE_TIMED then
			widget.name:setColor("$var-text-cip-store-timed")
			widget.flag:setVisible(true)
			widget.flag:setSize("10 15")
			widget.flag:setImageSource("/images/store/store-flag-expires")
			color = "$var-text-cip-store-timed"
		end

		if offer.purchased then
			widget.flag:setVisible(true)
			widget.flag:setSize("78 78")
			widget.flag:setImageSource("/images/store/sold") -- placeholder
		end

		widget.onHoverChange = function(self, hovered)
			if Offers.selectedWidget == widget then
				return
			end
			if hovered then
				widget:setBorderWidth(2)
				widget:setBorderColor('white')
			else
				widget:setBorderWidth(0)
			end
		end

		widget.onClick = function()
			if widget.grayHover:isVisible() then
				return
			end
			HomeOffer:processDailyOfferPurchase(offer.id)
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
		elseif offer.offerType == 1 then
			local outfit = {
				type = offer.mountId
			}

			widget.creature:setOutfit(outfit)
		elseif offer.offerType == 2 then
			local outfit = {
				type = offer.type,
				head = offer.head,
				body = offer.body,
				legs = offer.legs,
				feet = offer.feet,
				addons = 3,
			}

			widget.creature:setOutfit(outfit)
		end

		-- setup price
		local count = 0
		for i = #offer.offers, 1, -1 do
			local subOffer = offer.offers[i]
			-- check price   subOffer.price


			for _, i in pairs(subOffer.disabledReasons) do
				subOffer.disabledReason = string.format("%s* %s\n", subOffer.disabledReason, Offers.reasons[i.reasonId])
			end

			if subOffer.disabledReason ~= '' then
				subOffer.disabledReason = string.sub(subOffer.disabledReason, 1, -2)
			end

			if offer.purchased then
				subOffer.disabledReason = string.format("%s* %s\n", subOffer.disabledReason, "You already bought this offer")
				subOffer.disabledReasons[#subOffer.disabledReasons + 1] = {reasonId = #Offers.reasons}
			end

			if count == 0 then
				if offer.discountPrice > 0 then
					widget.price1:setText(formatMoney(offer.discountPrice, ","))
				else
					widget.price1:setText("Free")
				end
				if subOffer.count > 1 then
					widget.count1:setText(subOffer.count .. "x")
					widget.count1:setColor(color)
				else
					widget.count1:setVisible(false)
				end

				if subOffer.price > 0 and subOffer.price ~= offer.discountPrice then
					widget.priceOff:setVisible(true)
					widget.priceOff:setText(formatMoney(subOffer.price, ","))
				end
			else
				widget.price2:setVisible(true)
				if offer.discountPrice > 0 then
					widget.price2:setText(formatMoney(offer.discountPrice, ","))
				else
					widget.price2:setText("Free")
				end
				if subOffer.count > 1 then
					widget.count2:setVisible(true)
					widget.count2:setText(subOffer.count .. "x")
					widget.count2:setColor(color)
				else
					widget.count2:setVisible(false)
				end
			end

			if #subOffer.disabledReasons > 0 then
				Offers:setDisableShader(widget, subOffer.disabledReason, false, offer.state)
			end

			count = count + 1
		end
	end
end

local function displayHomeBanner(homeInfo)
	if not homeInfo or not homeInfo[1] or homeInfo[1] == "" then
		return
	end

	local displayPanel = Offers.displayPanel
	local bannerWidget = displayPanel and displayPanel.banners
	if not bannerWidget then
		return
	end

	local function applyBanner(path)
		if bannerWidget:isDestroyed() then
			return
		end

		bannerWidget:setImageSource(path)
		bannerWidget.onClick = function()
			if homeInfo[2] == 2 then
				g_game.requestStoreOffers(2, homeInfo[3], 0)
			end
		end
	end

	if homeInfo[1]:sub(1, 1) == "/" then
		applyBanner(homeInfo[1])
		return
	end

	HTTP.downloadImage(Store.url .. homeInfo[1], function(path, err)
		if not err then
			applyBanner(path)
		end
	end)
end

function HomeOffer:configurePanels()
	if #HomeOffer.homePanel == 0 then
		return
	end

	if #HomeOffer.homePanel <= HomeOffer.lastid then
		HomeOffer.lastid = 1
	else
		HomeOffer.lastid = HomeOffer.lastid + 1
	end

	local homeInfo = HomeOffer.homePanel[HomeOffer.lastid]
	displayHomeBanner(homeInfo)
end

function HomeOffer:showNextHomeBanner()
  if #HomeOffer.homePanel == 0 then
    return
  end

  HomeOffer.lastid = HomeOffer.lastid + 1
  if HomeOffer.lastid > #HomeOffer.homePanel then
    HomeOffer.lastid = 1
  end

  local homeInfo = HomeOffer.homePanel[HomeOffer.lastid]
  displayHomeBanner(homeInfo)
end

function HomeOffer:showPrevHomeBanner()
  if #HomeOffer.homePanel == 0 then
    return
  end

  HomeOffer.lastid = HomeOffer.lastid - 1
  if HomeOffer.lastid < 1 then
    HomeOffer.lastid = #HomeOffer.homePanel
  end

  local homeInfo = HomeOffer.homePanel[HomeOffer.lastid]
  displayHomeBanner(homeInfo)
end

function HomeOffer:getDailyOfferById(offerId)
	for _, offer in ipairs(HomeOffer.dailyOffers) do
		if offer.id == offerId then
			return offer
		end
	end
	return nil
end

function HomeOffer:processDailyOfferPurchase(offerId)
	local offer = self:getDailyOfferById(offerId)
	if not offer then
		return
	end

	if buyOfferWindow:isVisible() then
		return true
	end

	StoreWindow:hide()
	g_client.setInputLockWidget(nil)

	buyOfferWindow:show(true)
	g_client.setInputLockWidget(buyOfferWindow)
	buyOfferWindow.productWarning:setText(tr('Do you want to buy the daily offer "%dx %s"?', 1, offer.name))

	buyOfferWindow.description.offerName:setText(tr('%dx %s', offer.offers[1].count, offer.name))
	buyOfferWindow.description.offerPrice:setText(tr('Price: %dx', offer.discountPrice))
	buyOfferWindow.icon.creature:setOutfit({})
	buyOfferWindow.icon.image:setImageSource('')
	buyOfferWindow.icon.item:setItem(nil)

	local askButton = buyOfferWindow:recursiveGetChildById("storeAskBeforeBuyingProducts")
	askButton:setEnabled(false)

	local imageCoin = offer.coinType == COIN_TYPE_DEFAULT and 'tibiacoin' or 'tibiacointransferable'
	buyOfferWindow.description.coinType:setImageSource('/images/store/icon-' .. imageCoin)

	if offer.icon ~= "" then
		local widget = buyOfferWindow.icon.image
		widget.currentImageRequest = Store.currentRequest
		Store.imageRequests[Store.currentRequest] = widget
		Store.currentRequest = Store.currentRequest + 1

		widget:insertLuaCall("onDestroy")
		widget.onDestroy = function()
			Store.imageRequests[widget.currentImageRequest] = nil
		end

		Store:downloadImage(widget.currentImageRequest, "64/"..offer.icon)
	elseif offer.itemId ~= 0 then
		buyOfferWindow.icon.item:setItemId(offer.itemId)
	elseif offer.offerType == 1 then
		local outfit = {
			type = offer.mountId
		}

		buyOfferWindow.icon.creature:setOutfit(outfit)
	elseif offer.offerType == 2 then
		local outfit = {
			type = offer.type,
			head = offer.head,
			body = offer.body,
			legs = offer.legs,
			feet = offer.feet,
			addons = 3,
		}

		buyOfferWindow.icon.creature:setOutfit(outfit)
	end

	buyOfferWindow.okBuyButton.onClick = function()
		modules.game_store.onBuyOffer(buyOfferWindow.okBuyButton, offer.id, 10, "", offer.name)
	end
end
