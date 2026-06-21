if not Store then
	Store = {}
	Store.__index = Store
end

Store.url = ""
Store.coinsPacketSize = 25
Store.coins = 0
Store.transferableCoins = 0
Store.tournamentCoins = 0
Store.singleCoinBalance = false
Store.displayDescription = 100
Store.requestPerPage = 32
Store.imageRequests = {}
Store.imageCache = Store.imageCache or {}
Store.pendingImageRequests = {}
Store.currentRequest = 0

OPEN_HOME = 0
OPEN_REDIRECT = 1
OPEN_CATEGORY = 2
OPEN_USEFUL_THINGS = 3
OPEN_OFFER = 4
OPEN_SEARCH = 5

OFFER_BUY_TYPE_OTHERS = 0
OFFER_BUY_TYPE_NAMECHANGE = 1
OFFER_BUY_TYPE_TRANSFER = 2
OFFER_BUY_TYPE_HIRELING = 3

SERVICE_HOME = 0
SERVICE_CATEGORY_TYPE = 1
SERVICE_CATEGORY_NAME = 2
SERVICE_OFFER_TYPE = 3
SERVICE_OFFER_ID = 4
SERVICE_OFFER_NAME = 5

if g_game and not g_game.requestStoreOffersLegacy then
	local requestStoreOffers = g_game.requestStoreOffers
	g_game.requestStoreOffersLegacy = requestStoreOffers
	g_game.requestStoreOffers = function(actionOrCategory, valueOrServiceType, serviceType)
		if type(actionOrCategory) == 'number' then
			return requestStoreOffers(tostring(valueOrServiceType or ''), tonumber(serviceType) or 0)
		end

		return requestStoreOffers(tostring(actionOrCategory or ''), tonumber(valueOrServiceType) or 0)
	end
end

CATEGORY_NONE = 0
CATEGORY_MOUNT = 1
CATEGORY_OUTFIT = 2
CATEGORY_ITEM = 3
CATEGORY_HIRELING = 4
CATEGORY_HIRELING_OUTFIT = 6

OFFER_STATE_NONE = 0
OFFER_STATE_NEW = 1
OFFER_STATE_SALE = 2
OFFER_STATE_TIMED = 3

COIN_TYPE_DEFAULT = 0
COIN_TYPE_TRANSFERABLE = 1
COIN_TYPE_TOURNAMENT = 2
COIN_TYPE_RESERVED = 3

local function isWidgetAlive(widget)
	return widget and not widget:isDestroyed()
end

local localImageAliases = {
	["13/xp_boost"] = "/images/icons/xp_boost",
	["64/xp_boost"] = "/images/dailyreward/icon-reward-xpboost",
	xp_boost = "/images/dailyreward/icon-reward-xpboost",
	store_premium = "/images/game/battlepass/mainIcon1",
	prey_wildcard = "/images/game/prey/prey_wildcard"
}

local function resourceImageExists(path)
	return g_resources.fileExists(path) or g_resources.fileExists(path .. ".png")
end

function Store:resolveLocalImage(image)
	local source = tostring(image or "")
	if source == "" then
		return nil
	end

	source = source:gsub("\\", "/"):gsub("%.png$", "")
	if source:sub(1, 1) == "/" and resourceImageExists(source) then
		return source
	end

	local imageName = source:gsub("^%d+/", "")
	local alias = localImageAliases[source] or localImageAliases[imageName]
	if alias and resourceImageExists(alias) then
		return alias
	end

	local candidates = {
		"/images/store/" .. imageName,
		"/images/game/prey/" .. imageName
	}
	for _, candidate in ipairs(candidates) do
		if resourceImageExists(candidate) then
			return candidate
		end
	end

	return nil
end

function Store:profileStep(name, startedAt)
	if not DEVELOPERMODE or not startedAt then
		return
	end

	local elapsed = g_clock.millis() - startedAt
	if elapsed > 16 then
		g_logger.warning(string.format("[Store] %s took %d ms", name, elapsed))
	end
end

local function applyDownloadedImage(request, path)
	local widget = Store.imageRequests[request.requestId]
	if not isWidgetAlive(widget) then
		Store.imageRequests[request.requestId] = nil
		return
	end
	if widget.currentImageRequest and widget.currentImageRequest ~= request.requestId then
		Store.imageRequests[request.requestId] = nil
		return
	end

	widget:setImageSource(path, false)
	widget.imagePath = path
	if request.disabled and widget.disabled then
		widget.disabled:setVisible(true)
	end
	if request.onLoaded then
		request.onLoaded(widget, path)
	end
	Store.imageRequests[request.requestId] = nil
end

function Store:downloadImage(requestId, image, disabled, onLoaded)
	local request = {
		requestId = requestId,
		disabled = disabled,
		onLoaded = onLoaded
	}
	local localPath = Store:resolveLocalImage(image)
	if localPath then
		applyDownloadedImage(request, localPath)
		return
	end

	local imageUrl = Store.url .. image

	local cachedPath = Store.imageCache[imageUrl]
	if cachedPath then
		applyDownloadedImage(request, cachedPath)
		return
	end

	local pending = Store.pendingImageRequests[imageUrl]
	if pending then
		pending[#pending + 1] = request
		return
	end

	Store.pendingImageRequests[imageUrl] = { request }
	HTTP.downloadImage(imageUrl, function(path, err)
		local requests = Store.pendingImageRequests[imageUrl]
		Store.pendingImageRequests[imageUrl] = nil
		if err then
			for _, queuedRequest in ipairs(requests or {}) do
				Store.imageRequests[queuedRequest.requestId] = nil
			end
			if DEVELOPERMODE then
				g_logger.warning("HTTP error: " .. err .. " - " .. imageUrl)
			end
			return
		end

		local startedAt = g_clock.millis()
		Store.imageCache[imageUrl] = path
		for _, queuedRequest in ipairs(requests or {}) do
			applyDownloadedImage(queuedRequest, path)
		end
		Store:profileStep("image download batch", startedAt)
	end)
end

function Store:safeCancelWidgetAnimations(widget)
	if not widget or not widget.storeAnimationEvents then
		return
	end

	for key, event in pairs(widget.storeAnimationEvents) do
		removeEvent(event)
		widget.storeAnimationEvents[key] = nil
	end
end

local function setAnimationEvent(widget, key, event)
	widget.storeAnimationEvents = widget.storeAnimationEvents or {}
	removeEvent(widget.storeAnimationEvents[key])
	widget.storeAnimationEvents[key] = event
end

local function animateValue(widget, key, duration, update, onFinish)
	if not isWidgetAlive(widget) or not widget:isVisible() then
		return
	end

	duration = math.max(1, duration or 120)
	local startedAt = g_clock.millis()
	local function tick()
		if not isWidgetAlive(widget) or not widget:isVisible() then
			return
		end

		local progress = math.min(1, (g_clock.millis() - startedAt) / duration)
		update(progress)
		if progress < 1 then
			setAnimationEvent(widget, key, scheduleEvent(tick, 16))
		else
			widget.storeAnimationEvents[key] = nil
			if onFinish then
				onFinish(widget)
			end
		end
	end
	tick()
end

function Store:safeFadeIn(widget, duration)
	if not isWidgetAlive(widget) then
		return
	end

	widget:setOpacity(0)
	animateValue(widget, "fade", duration, function(progress)
		widget:setOpacity(progress)
	end)
end

function Store:safeFadeOut(widget, duration)
	if not isWidgetAlive(widget) then
		return
	end

	local initialOpacity = widget:getOpacity()
	animateValue(widget, "fade", duration, function(progress)
		widget:setOpacity(initialOpacity * (1 - progress))
	end)
end

function Store:safePulse(widget)
	if not isWidgetAlive(widget) then
		return
	end

	animateValue(widget, "pulse", 90, function(progress)
		widget:setOpacity(1 - (0.12 * progress))
	end, function()
		animateValue(widget, "pulse", 90, function(progress)
			widget:setOpacity(0.88 + (0.12 * progress))
		end)
	end)
end

function Store:safeHoverMove(widget, offsetX, offsetY, duration)
	if not isWidgetAlive(widget) then
		return
	end

	widget.storeBaseMarginLeft = widget.storeBaseMarginLeft or widget:getMarginLeft()
	widget.storeBaseMarginTop = widget.storeBaseMarginTop or widget:getMarginTop()
	local startLeft = widget:getMarginLeft()
	local startTop = widget:getMarginTop()
	local targetLeft = widget.storeBaseMarginLeft + (offsetX or 0)
	local targetTop = widget.storeBaseMarginTop + (offsetY or 0)
	animateValue(widget, "move", duration, function(progress)
		widget:setMarginLeft(math.floor(startLeft + ((targetLeft - startLeft) * progress) + 0.5))
		widget:setMarginTop(math.floor(startTop + ((targetTop - startTop) * progress) + 0.5))
	end)
end

function Store:safeAnimateImage(widget, frameWidth, frameHeight, firstFrame, lastFrame, frameTime, loop)
	if not isWidgetAlive(widget) then
		return
	end

	Store:safeCancelWidgetAnimations(widget)
	local frame = firstFrame
	local function advance()
		if not isWidgetAlive(widget) or not widget:isVisible() then
			return
		end

		widget:setImageClip(string.format("%d 0 %d %d", frameWidth * (frame - 1), frameWidth, frameHeight))
		frame = frame + 1
		if frame > lastFrame then
			if not loop then
				widget.storeAnimationEvents.image = nil
				return
			end
			frame = firstFrame
		end
		setAnimationEvent(widget, "image", scheduleEvent(advance, frameTime))
	end
	advance()
end

function Store:resetSession()
	for _, widget in pairs(Store.imageRequests) do
		if isWidgetAlive(widget) then
			Store:safeCancelWidgetAnimations(widget)
		end
	end
	Store.imageRequests = {}
	Store.pendingImageRequests = {}
	Store.currentRequest = 0
end

function Store:openHome()
	scheduleEvent(function()
		g_game.doThing(false)
		g_game.requestStoreOffers(OPEN_HOME, "", 0);
		g_game.doThing(true)
	end, 100)
end

function Store:getDescription(requestId, offerId, description)
	local data = {
		["description"] = "<b>"..description.."</b>",
		["fontcolor"] = "#f4f4f4",
		["fontsize"] = "11.1px",
		["font"] = "Verdana",
		["id"] = offerId
	}
	HTTP.downloadConditionalImage("https://widget.astra.com/"..offerId, data, function(path, err)
		if err then
			return
		end
		local widget = Store.imageRequests[requestId]
		if widget then
			widget:setImageSource(path, false)
		end
	end)
end
