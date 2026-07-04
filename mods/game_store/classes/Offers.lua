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
-- True between sending a buy and the purchase resolving. Two jobs: (1) suppress the
-- onCoinBalance list rebuild that lands ~650ms before the delivery screen (flicker);
-- (2) block rapid re-sends (held Enter / fast clicks) that would buy the same offer
-- multiple times during the purchase delay. The authoritative anti-exploit guard is
-- server-side (a purchase cooldown); this is the local UX guard.
Offers.purchasePending = false
Offers.purchasePendingEvent = nil
Offers.clientOffers = {}
-- Descriptions are PUSHED by the server (0xEA) ahead of the offer list, so we
-- cache them by offerId here and render the selected offer's text on demand.
Offers.descriptions = {}

-- Oversized (4x4) mount sprites anchor at their top-left tile, so the mount
-- preview ends up clipped/"outside" its widget. Shift the preview by the mount's
-- configured draw offset (data/json/offsets.json, applied to the ThingType),
-- falling back to one tile for bone-less 4x4 mounts. Pass mountId 0 to reset the
-- offset. Mirrors src/client/outfit.cpp so Store previews match the in-game look.
function Offers.setupMountPreview(widget, mountId)
	if not widget then
		return
	end

	if widget.setCenter then
		widget:setCenter(true)
	end

	if not widget.setDrawOffset then
		return
	end

	local thingType = g_things.getThingType(tonumber(mountId) or 0, ThingCategoryCreature)
	if thingType then
		local off = thingType.getDrawOffset and thingType:getDrawOffset()
		if off and ((off.x or 0) ~= 0 or (off.y or 0) ~= 0) then
			widget:setDrawOffset(off.x, off.y)
			return
		end

		if thingType:getWidth() == 4 and thingType:getHeight() == 4 then
			widget:setDrawOffset(32, 32)
			return
		end
	end

	widget:setDrawOffset(0, 0)
end

-- Inline description icons. The server embeds {info}/{character}/... tokens in
-- offer descriptions; we render them as real inline pictures via the engine's
-- inline-text-image support (g_fonts.registerInlineImage). Each token maps to a
-- control-byte code and a sub-rect of the local sprite sheet store-icons-inline.png
-- (247x13). Codes avoid the whitespace control bytes 9..13 (see fontmanager.cpp),
-- so the placeholder bytes survive the setHTML/setColorText %s trimming.
local INLINE_SHEET = '/images/store/store-icons-inline.png'
local INLINE_SHEET_H = 13
local INLINE_ICONS = {
  info        = { code = 1,  x = 1,   w = 10 },
  character   = { code = 2,  x = 17,  w = 5  },
  usablebyall = { code = 3,  x = 28,  w = 9  },
  box         = { code = 4,  x = 41,  w = 8  },
  storeinbox  = { code = 5,  x = 53,  w = 10 },
  house       = { code = 6,  x = 67,  w = 9  },
  limit       = { code = 7,  x = 80,  w = 10 },
  backtoinbox = { code = 8,  x = 92,  w = 10 },
  activated   = { code = 14, x = 107, w = 8  },
  speedboost  = { code = 15, x = 118, w = 10 },
  timed       = { code = 16, x = 133, w = 7  },
  battlesign  = { code = 17, x = 144, w = 11 },
  capacity    = { code = 18, x = 159, w = 7  },
  useicon     = { code = 19, x = 171, w = 9  },
}
local function ic(name) return string.char(INLINE_ICONS[name].code) end

-- <b>/<i> are intentionally NOT mapped to alternate fonts. The style-font path
-- swapped the label's base font (now TTF, with its own texture) for a bitmap
-- italic/bold font (the shared glyph atlas) mid-string; mixing those two texture
-- spaces rendered garbage in descriptions after the TTF font migration. We strip
-- <b>/<i> to plain text instead (see configureDescription / setHTML), which never
-- breaks. Inline {token} icons stay -- they draw from their own dedicated texture,
-- never the base atlas, so they are unaffected.

function Offers:registerInlineIcons()
  if Offers.inlineIconsRegistered then return end
  if not g_fonts or not g_fonts.registerInlineImage then return end
  for _, icon in pairs(INLINE_ICONS) do
    g_fonts.registerInlineImage(icon.code, INLINE_SHEET, icon.x, 0, icon.w, INLINE_SHEET_H, 0)
  end
  Offers.inlineIconsRegistered = true
end

-- "You don't have coins" is always the LAST entry of Offers.reasons
-- (appended in Offers:configure); server-sent reasonIds are strictly smaller,
-- so reasonId == #Offers.reasons uniquely identifies Lua-added money entries.
local function clearMoneyReason(subOffer)
	local moneyReasonId = #Offers.reasons
	for idx = #subOffer.disabledReasons, 1, -1 do
		if subOffer.disabledReasons[idx].reasonId == moneyReasonId then
			table.remove(subOffer.disabledReasons, idx)
		end
	end
end

local function hasMoneyReason(subOffer)
	local moneyReasonId = #Offers.reasons
	for _, entry in pairs(subOffer.disabledReasons) do
		if entry.reasonId == moneyReasonId then
			return true
		end
	end
	return false
end

function Offers:stopAllEvents()
	if HomeOffer.event then
		HomeOffer.event:cancel()
	end

	if Offers.gotoEvent then
		Offers.gotoEvent:cancel()
	end

	if Offers.coinCheck then
		Offers.coinCheck:cancel()
	end
end

-- Marks a purchase as in-flight: blocks further buys and the onCoinBalance flicker
-- until it resolves. The safety timeout clears the lock even if the resolution never
-- arrives (e.g. the server silently drops a duplicate buy via its purchase cooldown),
-- so the store can never get stuck unable to buy.
function Offers:beginPurchase()
	Offers.purchasePending = true
	if Offers.purchasePendingEvent then
		Offers.purchasePendingEvent:cancel()
	end
	Offers.purchasePendingEvent = scheduleEvent(function()
		Offers.purchasePending = false
		Offers.purchasePendingEvent = nil
	end, 5000)
end

function Offers:endPurchase()
	Offers.purchasePending = false
	if Offers.purchasePendingEvent then
		Offers.purchasePendingEvent:cancel()
		Offers.purchasePendingEvent = nil
	end
end

function Offers:configure(categoryName, offers, redirect, sortingType, filters, currentFilter, reasons)
	if Offers.displayPanel then
		Offers.displayPanel:destroy()
		Offers.displayPanel = nil
	end

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
	Offers.reasons[#Offers.reasons + 1] = "You don't have coins"
	Offers.clientOffers = {}
	Offers:checkOrder(nil, sortingType, currentFilter)
end

function Offers:checkOrder(self, currentIndex, currentFilter)
	Offers.displayOffer = Offers.offers
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

-- Server push (0xEA): store the description and, if its offer is the one on
-- screen right now, render it immediately. Normally the 0xEA packets all arrive
-- before any offer is selected, so the cache is what calldescription reads back.
function Offers:cacheDescription(offerId, description)
	Offers.descriptions[offerId] = description
	local selected = Offers.selectedWidget
	if selected and selected.offer and selected.offer.id == offerId then
		Offers:configureDescription(offerId, description)
	end
end

function calldescription(offerId)
	if Offers.event then Offers.event:cancel() end
	-- The crystalserver has no "request description" opcode (requestOfferDescription
	-- is a no-op); descriptions were pushed up-front via 0xEA, so render from cache.
	Offers.event = scheduleEvent(function()
		Offers:configureDescription(offerId, Offers.descriptions[offerId])
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

	offerPanel:destroyChildren()

	if Offers.coinCheck then
		Offers.coinCheck:cancel()
	end

	if Offers.loadOffersEvent then
		removeEvent(Offers.loadOffersEvent)
	end

	Offers.loadOffersEvent = scheduleEvent(function()
	-- setando offers
	local offerTotalCount = 0
	for counter, offer in ipairs(displayOffer) do
		if Offers.currentFilter ~= '' and string.lower(Offers.currentFilter) ~= string.lower(offer.filter) then
			goto continue
		end

		local widget = g_ui.createWidget(getOfferUI(offer), offerPanel)
		widget:setId(offer.id)
		widget.name:setText(offer.name)
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
			Offers.setupMountPreview(widget.creature, offer.mountId)
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
			-- subOffer tables are cached and reused across re-renders; drop the
			-- money entry we may have added before and rebuild the reason string
			-- from scratch, otherwise both grow without bound every refresh
			clearMoneyReason(subOffer)
			subOffer.disabledReason = ""
			if subOffer.id == redirect then
				selected = true
			end

			if offer.state == OFFER_STATE_SALE then
				local daysLeft = math.floor((subOffer.saleValidUntilTimestamp - os.time()) / 86400)
				Offers.clientOffers[offer.id] = string.format("<font color=\"#ECAC46\">{star} Valid until %s{star} %d days left<br /></font>", os.date("%Y-%m-%d, %X", subOffer.saleValidUntilTimestamp), daysLeft)
			end

			local changeCount = #Offers.reasons
			-- check price   subOffer.price
			if subOffer.coinType == COIN_TYPE_DEFAULT then -- normal coin
				if Store.coins < subOffer.price then
					subOffer.disabledReasons[#subOffer.disabledReasons + 1] = {reasonId = #Offers.reasons}

					widget:getChildById("price" .. i):setColor("$var-text-cip-store-red")
					widget.coinCheck = true
				end
			elseif subOffer.coinType == COIN_TYPE_TRANSFERABLE then -- transfeable coin
				if Store.transferableCoins < subOffer.price then
					subOffer.disabledReasons[#subOffer.disabledReasons + 1] = {reasonId = #Offers.reasons}
          			local slot = i == 2 and 1 or 2
					widget:getChildById("price" .. slot):setColor("$var-text-cip-store-red")
					widget.coinCheck = true
				end
			elseif subOffer.coinType == COIN_TYPE_TOURNAMENT then -- tournament coin
				if Store.tournamentCoins < subOffer.price then
					subOffer.disabledReasons[#subOffer.disabledReasons + 1] = {reasonId = #Offers.reasons}
					widget:getChildById("price" .. i):setColor("$var-text-cip-store-red")
					widget.coinCheck = true
				end
			end

			local canChange = false
			for _, i in pairs(subOffer.disabledReasons) do
				if changeCount ~= i.reasonId then
					canChange = true
				end
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
		if redirect == 0 and counter == 1 then
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
		::continue::
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

	end, 100)
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

		local color = not string.find(disabledReason, "You don't have coins") and "$var-text-cip-store-disabled" or "$var-text-cip-store-red-disabled"

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
	if Offers.selectedWidget then
		Offers.selectedWidget:setBorderWidth(0)
	end

	Offers.selectedWidget = selectedWidget
	if not selectedWidget or not Offers.displayPanel.offerName then
		return
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
		widget.currentImageRequest = Store.currentRequest
		Store.imageRequests[Store.currentRequest] = widget.image
		Store.currentRequest = Store.currentRequest + 1

		widget:insertLuaCall("onDestroy")
		widget.onDestroy = function()
			Store.imageRequests[widget.currentImageRequest] = nil
		end

		if selectedWidget.image.imagePath then
			widget:setImageSize("126 126")
			widget:setImageSmooth(false)
			widget:setImageSource(selectedWidget.image.imagePath)
		else
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
		Offers.setupMountPreview(Offers.displayPanel.infopanel.outfit, offer.mountId)
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

	if offer.tryMode ~= 0 then
		Offers.displayPanel.tryOn:setVisible(true)
		Offers.displayPanel.tryOn.onClick = function()
			g_client.setInputLockWidget(nil)
			StoreWindow:hide()
			local id = 0
			if offer.maleOutfit ~= 0 then
				id = offer.maleOutfit
				offer.tryMode = 3
			elseif offer.mountId ~= 0 then
				id = offer.mountId
			elseif offer.type ~= 0 then
				id = offer.type
			end
			g_game.requestOutfit(offer.tryMode, id)
		end
	else
		Offers.displayPanel.tryOn:setVisible(false)
	end

	local disabled = false
	Offers.displayPanel.buy1:setImageSource("/images/store/buybutton")
	Offers.displayPanel.buy1:setOn(true)
	Offers.displayPanel.buy1:setTooltip('')
	Offers.displayPanel.buy2:setTooltip('')
	Offers.displayPanel.price1.price:setColor("$var-text-cip-color")
	Offers.displayPanel.price2.price:setColor("$var-text-cip-color")
	if offer.offers[1].disabledReason ~= '' then
		Offers.displayPanel.buy1.onClick = function() end
		local msg = {}
		-- setColoredText casts each color string directly, WITHOUT the OTUI-var
		-- resolution that setColor() gets, so a raw "$var-..." parses as white and
		-- renders invisibly on the light-gray tooltip. Resolve it to hex via tovar().
		local storeRed = tovar("$var-text-cip-store-red")
		setStringColor(msg, "The product is not available for this character:\n", storeRed)
		setStringColor(msg, offer.offers[1].disabledReason, storeRed)
		Offers.displayPanel.buy1:setTooltip(msg)
		Offers.displayPanel.buy1:setImageSource("/images/store/buybutton")
		Offers.displayPanel.buy1:setOn(false)


		if string.find(offer.offers[1].disabledReason, "You don't have coins") then
			Offers.displayPanel.price1.price:setColor("$var-text-cip-store-red")
		end
		disabled = true
	else
		Offers.displayPanel.buy1.onClick = function() buyStoreOffer(offer, offer.offers[1]) end
	end

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
		Offers.displayPanel.buy2:setOn(true)
		if offer.offers[2].disabledReason ~= '' then
			Offers.displayPanel.buy2.onClick = function() end
			local msg = {}
			local storeRed = tovar("$var-text-cip-store-red")
			setStringColor(msg, "The product is not available for this character:\n", storeRed)
			setStringColor(msg, offer.offers[2].disabledReason, storeRed)
			Offers.displayPanel.buy2:setOn(false)
			Offers.displayPanel.buy2:setTooltip(msg)


			if string.find(offer.offers[2].disabledReason, "You don't have coins") then
				Offers.displayPanel.price2.price:setColor("$var-text-cip-store-red")
			end

			disabled = true
		else
			Offers.displayPanel.buy2.onClick = function() buyStoreOffer(offer, offer.offers[2]) end
		end
	else
		Offers.displayPanel.buy2:setVisible(false)
		Offers.displayPanel.price2:setVisible(false)
	end

	if disabled then
		Offers.displayPanel.description.error:setText('The product is currently not available\nfor this character. See the Buy button\ntooltip for details.\n ')
		Offers.displayPanel.description.error:setHeight(60)
		Offers.displayPanel.description.error:setVisible(true)
	else
		Offers.displayPanel.description.error:setText('')
		Offers.displayPanel.description.error:setHeight(0)
		Offers.displayPanel.description.error:setVisible(false)
	end

	-- The description Label vertically auto-resizes to its text (see offers.otui),
	-- so we must NOT pin a tall fixed height here -- that forced the scroll area to
	-- always overflow. The package panel stacks below it in the vertical layout.
	Offers.displayPanel.description.package:destroyChildren()
	Offers.displayPanel.description.package:setHeight(20)
	if #offer.bundles > 0 then
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
				Offers.setupMountPreview(ui.creature, bundles.mountId)
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

	Offers:registerInlineIcons()

	local novo_texto = string.gsub(description, "\n", "<br/>")
	novo_texto = string.gsub(novo_texto, "<br>", "<br/>")
	-- Replace each {token} with its inline-icon control byte (+ the descriptive
	-- text the official store shows next to it). The byte renders as a picture
	-- once the layout reaches it; see Offers:registerInlineIcons / fontmanager.cpp.
	novo_texto = string.gsub(novo_texto, "{info}", ic("info"))
	novo_texto = string.gsub(novo_texto, "{character}", ic("character") .. " only usable by purchasing character")
	novo_texto = string.gsub(novo_texto, "{activated}", ic("activated") .. " activated at purchase")
	novo_texto = string.gsub(novo_texto, "{useicon}", ic("useicon"))
	novo_texto = string.gsub(novo_texto, "{limit|(%d+)}", ic("limit") .. " maximum amount that can be owned by character: %1")
	novo_texto = string.gsub(novo_texto, "{house}", ic("house") .. " can only be unwrapped in a house owned by the purchasing character")
	novo_texto = string.gsub(novo_texto, "{box}", ic("box") .. " comes in a box which can only be unwrapped by purchasing character")
	novo_texto = string.gsub(novo_texto, "{storeinbox}", ic("storeinbox") .. " will be sent to your Store inbox and can only be stored there and in depot box")
	novo_texto = string.gsub(novo_texto, "{usablebyallicon}", ic("usablebyall"))
	novo_texto = string.gsub(novo_texto, "{usablebyall}", ic("usablebyall"))
	novo_texto = string.gsub(novo_texto, "{backtoinbox}", ic("backtoinbox") .. " will be wrapped back and sent to inbox if the purchasing character is no longer the house owner")
	novo_texto = string.gsub(novo_texto, "{storeinboxicon}", ic("backtoinbox"))
	novo_texto = string.gsub(novo_texto, "{capacity}", ic("capacity") .. " cannot be purchased if capacity is exceeded")
	novo_texto = string.gsub(novo_texto, "{speedboost}", ic("speedboost") .. " provides character with a speed boost")
	novo_texto = string.gsub(novo_texto, "{battlesign}", ic("battlesign") .. " cannot be purchased by characters with protection zone block or battle sign")
	novo_texto = string.gsub(novo_texto, "{once}", ic("limit") .. " can only be purchased once")
	-- No matching icon in the local sheet: drop the {star} marker (it previously
	-- pointed at an external image that the shim stripped anyway).
	novo_texto = string.gsub(novo_texto, "{star}", "")

	-- Leave <b>/<i> in place: setHTML strips them to plain text below. We must NOT
	-- swap in bitmap bold/italic fonts here -- their glyphs live in a different
	-- texture than the TTF base font and render as garbage when mixed (that was the
	-- "all bugged" Gem Extender description). Plain text is the robust choice.
	desc.image:setHTML(novo_texto)


	-- Store:getDescription(currentWidget.currentImageRequest, offerId, Offers.clientOffers[offerId] .. novo_texto)
end

function buyStoreOffer(generalOffer, selectedOffer)
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
		Offers.setupMountPreview(buyOfferWindow.icon.creature, generalOffer.mountId)
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
		-- Ignore rapid re-clicks / held Enter while a purchase is still resolving,
		-- so one click == one purchase (the server enforces this too as a backstop).
		if Offers.purchasePending then
			return
		end
		Offers:beginPurchase()
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
end

function onStorePurchase(message)
	SucessOfferWindow:show(true)
	StoreWindow:hide()
	buyOfferWindow:hide()
	g_client.setInputLockWidget(nil)
	SucessOfferWindow.confirm.image:setImageSource('/images/store/purchasecomplete_idle')
	SucessOfferWindow.confirm.image:setImageClip("0 0 108 108")
	SucessOfferWindow.description.message:setText(message)
	scheduleEvent(function() SucessOfferWindow:focus() end, 50)
end

local function animateImage(widget, width, height, frame_init, frame_end, time)
	if not widget then
		return true
	end

    local crop = {}
    local totalframes = frame_end - frame_init + 1
    local nextTime = totalframes * time

    for i = frame_init, frame_end do
        crop[i] = width * (i-1) .. " 0 " .. width .. " " .. height
    end

    for k = frame_init, frame_end do
        scheduleEvent(function()
            widget:setImageClip(crop[k])
        end, time * (k - frame_init + 1))
    end
    return true
end

function completePurchase(widget, immediate)
	if Offers.completePurchaseEvent then
		Offers.completePurchaseEvent:cancel()
	end
	if widget then
		widget.image:setImageSource('/images/store/purchasecomplete_pressed')
		widget.image:setImageClip("0 0 108 108")
		animateImage(widget.image, 108, 108, 1, 13, 100)
	end

	local action = function()
		Offers:endPurchase()
		if SucessOfferWindow:isVisible() then
			SucessOfferWindow:hide()
		end
		if not StoreWindow:isVisible() then
			showStoreWindow()
		end
		-- Force a fresh fetch of the current view so the just-bought offer flips to
		-- disabled and the combo "All ..." price drops, without reopening the store.
		-- (onSelectCategory no-ops on the already-selected category, hence reloadOffers.)
		Store:reloadOffers()
	end

	if immediate then
		action()
	else
		Offers.completePurchaseEvent = scheduleEvent(action, 1000)
	end
end

function Offers:checkOfferValue()
	local panel = Offers.displayPanel.offers
	if not panel then
		return
	end

	for _, widget in pairs(panel:getChildren()) do
		local offer = widget.offer
		for i = #offer.offers, 1, -1 do
			local subOffer = offer.offers[i]
			if subOffer.coinType == COIN_TYPE_DEFAULT then -- normal coin
				if Store.coins < subOffer.price then
					if not hasMoneyReason(subOffer) then
						subOffer.disabledReasons[#subOffer.disabledReasons + 1] = {reasonId = #Offers.reasons}
					end

          local slot = i == 2 and 1 or 2
          if #offer.offers == 1 then
          	slot = 1
          end
          local priceSlot = widget:getChildById("price" .. slot)
					priceSlot:setColor(widget.grayHover:isVisible() and "$var-text-cip-store-red-disabled" or "$var-text-cip-store-red")
					widget.coinCheck = true
				end
			elseif subOffer.coinType == COIN_TYPE_TRANSFERABLE then -- transfeable coin
				if Store.transferableCoins < subOffer.price then
					if not hasMoneyReason(subOffer) then
						subOffer.disabledReasons[#subOffer.disabledReasons + 1] = {reasonId = #Offers.reasons}
					end
          local slot = i == 2 and 1 or 2
          if #offer.offers == 1 then
          	slot = 1
          end
          local priceSlot = widget:getChildById("price" .. slot)
					priceSlot:setColor((widget.grayHover:isVisible() and "$var-text-cip-store-red-disabled" or "$var-text-cip-store-red"))
					widget.coinCheck = true
				end
			elseif subOffer.coinType == COIN_TYPE_TOURNAMENT then -- tournament coin
				if Store.tournamentCoins < subOffer.price then
					if not hasMoneyReason(subOffer) then
						subOffer.disabledReasons[#subOffer.disabledReasons + 1] = {reasonId = #Offers.reasons}
					end
          local slot = i == 2 and 1 or 2
          if #offer.offers == 1 then
          	slot = 1
          end
          local priceSlot = widget:getChildById("price" .. slot)
					priceSlot:setColor(widget.grayHover:isVisible() and "$var-text-cip-store-red-disabled" or "$var-text-cip-store-red")
					widget.coinCheck = true
				end
			end

			if #subOffer.disabledReasons > 0 and not widget.coinCheck then
				Offers:setDisableShader(widget, subOffer.disabledReason, false, offer.state)
			end

		end
	end

	Offers.coinCheck = scheduleEvent(function() Offers:checkOfferValue() end, 1000)
end
