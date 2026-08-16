if not LootAnalyser then
	LootAnalyser = {
		launchTime = 0,
		session = 0,
		goldValue = 0,
		goldHour = 0,
		target = 0,
		gaugeVisible = true,
		graphVisible = true,
		lootedItems = {},
		-- private
		window = nil,
		event = nil,
		eventGraph = nil,
		pendingWindowUpdate = nil,
	}

	LootAnalyser.__index = LootAnalyser
end

local targetMaxMargin = 142


function LootAnalyser:create()
	LootAnalyser:cancelPendingWindowUpdate()
	LootAnalyser.launchTime = 0
	LootAnalyser.session = 0
	LootAnalyser.goldValue = 0
	LootAnalyser.goldHour = 0
	LootAnalyser.target = 0
	LootAnalyser.gaugeVisible = true
	LootAnalyser.graphVisible = true
	LootAnalyser.lootedItems = {}
	LootAnalyser.forceUpdateBalance = false
	LootAnalyser.updateBalance = true

	-- private
	LootAnalyser.window = openedWindows['lootButton']
	LootAnalyser.eventGraph = nil
end

function LootAnalyser:queueWindowUpdate()
	if LootAnalyser.pendingWindowUpdate then
		return
	end

	LootAnalyser.pendingWindowUpdate = scheduleEvent(function()
		LootAnalyser.pendingWindowUpdate = nil
		if not LootAnalyser.window then
			return
		end

		LootAnalyser:checkBalance(true)
		-- Keep the gold/h figure current for the labels, but leave the graph sample to the
		-- Controller's 60s cycle: the graph is a time series, so appending a point per kill
		-- would both distort it and touch a widget on every kill.
		LootAnalyser:refreshGoldHour()
		if LootAnalyser.window:isVisible() then
			LootAnalyser:updateWindow(true, true)
		end
	end, 1)
end

function LootAnalyser:cancelPendingWindowUpdate()
	if LootAnalyser.pendingWindowUpdate then
		removeEvent(LootAnalyser.pendingWindowUpdate)
		LootAnalyser.pendingWindowUpdate = nil
	end
end


function onLootingExtra(mousePosition)
  if cancelNextRelease then
    cancelNextRelease = false
    return false
  end

	local menu = g_ui.createWidget('PopupMenu')
	menu:setGameMenu(true)
	menu:addOption(tr('Reset Data'), function() LootAnalyser:reset(); return end)
	menu:addSeparator()
	menu:addOption(tr('Set Loot Per Hour Target'), function() LootAnalyser:openTargetConfig() return end)
	menu:addCheckBoxOption(tr('Loot Per Hour Gauge'), function() LootAnalyser:setLootPerHourGauge(not LootAnalyser.window.contentsPanel.targetLabel:isVisible()) end, "", LootAnalyser.window.contentsPanel.targetLabel:isVisible())
	menu:addCheckBoxOption(tr('Loot Per Hour Graph'), function() LootAnalyser:setLootPerHourGraph(not LootAnalyser.window.contentsPanel.graphPanel:isVisible()) end, "", LootAnalyser.window.contentsPanel.graphPanel:isVisible())
	menu:display(mousePosition)
  return true
end

function LootAnalyser:reset()
	LootAnalyser:cancelPendingWindowUpdate()
	LootAnalyser.launchTime = g_clock.millis()
	LootAnalyser.session = 0
	LootAnalyser.goldValue = 0
	LootAnalyser.goldHour = 0
	LootAnalyser.target = 0
	LootAnalyser.lootedItems = {}
	LootAnalyser.forceUpdateBalance = false
	LootAnalyser.updateBalance = true

	LootAnalyser.window.contentsPanel.graphPanel:clear()
	LootAnalyser.window.contentsPanel.graphPanel:addValue(0)

	LootAnalyser:updateWindow(true)
end

function LootAnalyser:updateBasePriceFromLootedItems(itemId, newPriceValue)
	local itemInfo = self.lootedItems[itemId]
	if itemInfo then
		if not newPriceValue then
			-- in case we dont have the value already
			-- lets create a dummy item just to retrieve
			-- the price value
			local itemPtr = Item.create(itemId, 1)
			newPriceValue = itemPtr:getPriceValue()
			itemPtr = nil
		end

		if itemInfo.basePrice ~= newPriceValue then
			itemInfo.basePrice = newPriceValue
			LootAnalyser.forceUpdateBalance = true
			LootAnalyser:updateWindow(true)
		end
	end
end

function LootAnalyser:checkBalance(deferWindowUpdate)
	local oldBalance = LootAnalyser.goldValue
	if LootAnalyser.forceUpdateBalance then
		local loot = 0
		for itemId, itemInfo in pairs(LootAnalyser.lootedItems) do
			local count = itemInfo.count
			local price = count * itemInfo.basePrice

			loot = loot + price
		end

		LootAnalyser.goldValue = loot
		LootAnalyser.forceUpdateBalance = false
	end

	if LootAnalyser.updateBalance or oldBalance ~= LootAnalyser.goldValue then
		if not deferWindowUpdate then
			LootAnalyser:updateWindow(false)
		end
		LootAnalyser.updateBalance = false
	end
end

function LootAnalyser:updateWindow(updateScroll, ignoreVisible)
	if not LootAnalyser.window:isVisible() and not ignoreVisible then
		return
	end
	local contentsPanel = LootAnalyser.window.contentsPanel

	contentsPanel.gold:setText(formatMoney(LootAnalyser.goldValue, ","))
	contentsPanel.goldHour:setText(formatMoney(math.floor(LootAnalyser.goldHour), ","))
	contentsPanel.goldTarget:setText(formatMoney(LootAnalyser.target, ","))

	if LootAnalyser.target == 0 and LootAnalyser.goldHour == 0 then
		LootAnalyser.window.contentsPanel.lootTargetBG.lootArrow:setMarginLeft(targetMaxMargin / 2)
	else
		local target = math.max(1, LootAnalyser.target)
		local current = LootAnalyser.goldHour
		local percent = (current * 71) / target
		LootAnalyser.window.contentsPanel.lootTargetBG.lootArrow:setMarginLeft(math.min(targetMaxMargin, math.ceil(percent)))
	end

	LootAnalyser.window.contentsPanel.lootTargetBG:setTooltip(string.format("Current: %d\nTarget: %d", LootAnalyser.goldHour, LootAnalyser.target))

	if not updateScroll then
		return
	end

	local numOfItems = 0
	local numOfLines = 0
	if table.empty(LootAnalyser.lootedItems) and #contentsPanel.lootedItems:getChildren() then
		contentsPanel.lootedItems:destroyChildren()
	else
		for itemId, info in pairs(LootAnalyser.lootedItems) do
			local widget = contentsPanel.lootedItems:getChildById(itemId)
			if not widget then
				widget = g_ui.createWidget('LootItem', contentsPanel.lootedItems)
				widget:setId(itemId)
				widget:setItemId(itemId)
			end
			widget:setItemCount(info.count)
			widget:setTooltip(string.format("%s (Value: %dgp, Sum: %dgp)", string.capitalize(info.name), info.basePrice, info.basePrice * info.count))
			numOfItems = numOfItems + 1
			if numOfItems == 4 then
				numOfItems = 0
				numOfLines = numOfLines + 1
			end
		end
	end

	numOfLines = not table.empty(LootAnalyser.lootedItems) and numOfLines + 1 or 0
	contentsPanel.lootedItems:setHeight(35 * (numOfLines + ((numOfLines > 0 and numOfItems == 0) and -1 or 0)))
end

-- Pure arithmetic, no widget access: safe to call while the window is hidden.
function LootAnalyser:refreshGoldHour()
	local uptime = math.floor((g_clock.millis() - LootAnalyser.launchTime)/1000)
	if uptime < 5*60 then
		LootAnalyser.goldHour = LootAnalyser.goldValue
	else
		LootAnalyser.goldHour = math.floor((LootAnalyser.goldValue/uptime)*3600)
	end
end

function LootAnalyser:updateGraphics()
	LootAnalyser:refreshGoldHour()
	LootAnalyser.window.contentsPanel.graphPanel:addValue(LootAnalyser.goldHour)
end

function LootAnalyser:addLootedItems(item, name)
	local itemId = item:getId()
	local itemInfo = LootAnalyser.lootedItems[itemId]
	if not itemInfo then
		LootAnalyser.lootedItems[itemId] = {count = 0, name = name, basePrice = 0}
		itemInfo = LootAnalyser.lootedItems[itemId]
	end

	local count = item:getCount()
	itemInfo.basePrice = modules.game_cyclopedia.CyclopediaItems.getCurrentItemValue(item)
	itemInfo.count = itemInfo.count + count

	-- update balance
	LootAnalyser.goldValue = LootAnalyser.goldValue + (itemInfo.basePrice * count)
	LootAnalyser.updateBalance = true
	LootAnalyser:queueWindowUpdate()
end

function LootAnalyser:setLootPerHourGauge(value)
	LootAnalyser.window.contentsPanel.targetLabel:setVisible(value)
	LootAnalyser.window.contentsPanel.goldLabelIcon:setVisible(value)
	LootAnalyser.window.contentsPanel.goldTarget:setVisible(value)
	LootAnalyser.window.contentsPanel.lootTargetBG:setVisible(value)
	LootAnalyser.window.contentsPanel.separatorGauge:setVisible(value)

	LootAnalyser.gaugeVisible = value

	if value then
		LootAnalyser.window.contentsPanel.lootGraphBG:addAnchor(AnchorTop, 'separatorGauge', AnchorBottom)
	else
		LootAnalyser.window.contentsPanel.lootGraphBG:addAnchor(AnchorTop, 'separatorLootedItems', AnchorBottom)
	end
end

function LootAnalyser:setLootPerHourGraph(value)
	LootAnalyser.window.contentsPanel.lootGraphBG:setVisible(value)
	LootAnalyser.window.contentsPanel.graphPanel:setVisible(value)
	LootAnalyser.window.contentsPanel.graphHorizontal:setVisible(value)

	LootAnalyser.graphVisible = value
end

function LootAnalyser:gaugeIsVisible()
	return LootAnalyser.gaugeVisible
end
function LootAnalyser:graphIsVisible()
	return LootAnalyser.graphVisible
end
function LootAnalyser:getTarget()
	return LootAnalyser.target
end
function LootAnalyser:setTarget(value)
	LootAnalyser.target = tonumber(value)
	LootAnalyser.window.contentsPanel.goldTarget:setText(formatMoney(LootAnalyser.target, ","))
end

function LootAnalyser:openTargetConfig()
	local window = getConfigPopupWindow("lootButton")
	if not window then return end
	window:show()
	window:setText('Set Loot Target')
	window.contentPanel.text:setImageSource('/images/game/analyzer/labels/loot')

	window.onEnter = function()
		local value = window.contentPanel.lootTarget:getText()
		LootAnalyser.target = tonumber(value)
		window:hide()
	end
	window.contentPanel.lootTarget:setText(tonumber(LootAnalyser.target) or '0')

	window.contentPanel.ok.onClick = function()
		local value = window.contentPanel.lootTarget:getText()
		LootAnalyser.target = tonumber(value)
		window:hide()
	end
	window.contentPanel.cancel.onClick = function()
		window:hide()
	end
end
