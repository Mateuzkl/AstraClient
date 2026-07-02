if not SupplyAnalyser then
	SupplyAnalyser = {
		launchTime = 0,
		session = 0,
		goldValue = 0,
		goldHour = 0,
		items = {},
		itemCounts = {},
		-- private
		window = nil,
	}

	SupplyAnalyser.__index = SupplyAnalyser
end

function SupplyAnalyser:create()
	SupplyAnalyser.launchTime = 0
	SupplyAnalyser.session = 0
	SupplyAnalyser.goldValue = 0
	SupplyAnalyser.goldHour = 0
	SupplyAnalyser.items = {}
	SupplyAnalyser.itemCounts = {}
	SupplyAnalyser.forceUpdateBalance = false
	SupplyAnalyser.updateBalance = true

	SupplyAnalyser.window = openedWindows['supplyButton']
end

local function getCurrentPrice(itemPtr)
	local value = itemPtr:getDefaultBuyPrice()
	if value == 0 then
		value = itemPtr:getAverageMarketValue()
	end
	return value
end

function onSupplyExtra(mousePosition)
  if cancelNextRelease then
    cancelNextRelease = false
    return false
  end

	local menu = g_ui.createWidget('PopupMenu')
	menu:setGameMenu(true)
	menu:addOption(tr('Reset Data'), function() SupplyAnalyser:reset() return end)
	menu:display(mousePosition)
  return true
end

function SupplyAnalyser:reset()
	SupplyAnalyser.launchTime = g_clock.millis()
	SupplyAnalyser.session = 0
	SupplyAnalyser.goldValue = 0
	SupplyAnalyser.goldHour = 0
	SupplyAnalyser.items = {}
	SupplyAnalyser.itemCounts = {}
	SupplyAnalyser.forceUpdateBalance = false
	SupplyAnalyser.updateBalance = true

	SupplyAnalyser.window.contentsPanel.lootedItems:setVisible(false)
	SupplyAnalyser.window.contentsPanel.lootedItems:destroyChildren()

	SupplyAnalyser:updateWindow(true)
end

function SupplyAnalyser:checkBalance()
	local oldBalance = SupplyAnalyser.goldValue
	for index, itemInfo in pairs(SupplyAnalyser.items) do
		if itemInfo.time + 3600 < os.time() then
			SupplyAnalyser.items[index] = nil
			local itemId = itemInfo.itemId
			local newCount = (SupplyAnalyser.itemCounts[itemId] or 1) - 1
			SupplyAnalyser.itemCounts[itemId] = newCount > 0 and newCount or nil
			SupplyAnalyser:decreaseWidget(itemId)
		end
	end

	SupplyAnalyser.forceUpdateBalance = false

	if SupplyAnalyser.updateBalance or oldBalance ~= SupplyAnalyser.goldValue then
		SupplyAnalyser:updateWindow(false)
		SupplyAnalyser.updateBalance = false
	end
end

function SupplyAnalyser:updateWindow(updateScroll, ignoreVisible)
	if not SupplyAnalyser.window:isVisible() and not ignoreVisible then
		return
	end

	local goldHour = SupplyAnalyser.goldHour or 0
	local goldValue = SupplyAnalyser.goldValue or 0

	local contentsPanel = SupplyAnalyser.window.contentsPanel
	contentsPanel.gold:setText(formatMoney(goldValue, ","))
	contentsPanel.goldHour:setText(formatMoney(goldHour, ","))

	if not updateScroll then
		return
	end

	local numOfItems = 0
	local numOfLines = 0
	for _, __ in pairs(contentsPanel.lootedItems:getChildren()) do
		numOfItems = numOfItems + 1
		if numOfItems == 4 then
			numOfItems = 0
			numOfLines = numOfLines + 1
		end
	end

	if numOfItems > 0 then
		contentsPanel.lootedItems:setVisible(true)
	end

	numOfLines = not table.empty(SupplyAnalyser.items) and numOfLines + 1 or 0
	contentsPanel.lootedItems:setHeight(35 * numOfLines)
end

-- Recalcula o gasto/hora (label "Per Hour"). Chamado a cada supply e periodicamente
-- pelo Controller. O grafico de Supply Per Hour foi removido, entao aqui so atualizamos
-- o valor.
function SupplyAnalyser:updateGraphics()
	local uptime = math.floor((g_clock.millis() - SupplyAnalyser.launchTime)/1000)
	if uptime < 5*60 then
		SupplyAnalyser.goldHour = SupplyAnalyser.goldValue
	else
		SupplyAnalyser.goldHour = math.ceil((SupplyAnalyser.goldValue/uptime)*3600)
	end
end

function SupplyAnalyser:getItemCount(itemId)
	return SupplyAnalyser.itemCounts[itemId] or 0
end

function SupplyAnalyser:checkDecrease()
end

function SupplyAnalyser:updateWidget(itemId)
	local itemPtr = Item.create(itemId, 1)
	local contentsPanel = SupplyAnalyser.window.contentsPanel
	local widget = contentsPanel.lootedItems:getChildById(tostring(itemId))
	if not widget then
		widget = g_ui.createWidget('LootItem', contentsPanel.lootedItems)
		widget:setId(itemId)
		widget:setItemId(itemId)
		-- count nativo do UIItem e uint16 (trunca > 65535) e nao abrevia sem GameCountU16:
		-- totais grandes vazam da celula e sao cortados. Usa label proprio (ver t_market.lua).
		widget:setShowCount(false)
	end

	local count = SupplyAnalyser:getItemCount(itemId)
	-- setItemCount so define a sprite da pilha; o numero exibido vem do countLabel abreviado.
	widget:setItemCount(count)
	widget.countLabel:setText(count > 1 and tokformat(count) or "")

	local value = getCurrentPrice(itemPtr)
	widget:setTooltip(string.format("%s (Value: %sgp, Sum: %sgp)", getItemServerName(itemId), formatMoney(value, ","), formatMoney(value * count, ",")))
end

function SupplyAnalyser:decreaseWidget(itemId)
	local contentsPanel = SupplyAnalyser.window.contentsPanel
	local count = SupplyAnalyser:getItemCount(itemId)
	local widget = contentsPanel.lootedItems:getChildById(tostring(itemId))
	if count < 1 then
		widget:destroy()
		SupplyAnalyser:updateWindow(true)
		return
	end

	local itemPtr = Item.create(itemId, 1)
	local value = getCurrentPrice(itemPtr)
	widget:setItemCount(count)
	widget.countLabel:setText(count > 1 and tokformat(count) or "")
	widget:setTooltip(string.format("%s (Value: %sgp, Sum: %sgp)", getItemServerName(itemId), formatMoney(value, ","), formatMoney(value * count, ",")))
end

function SupplyAnalyser:addSuppliesItems(itemId)
	SupplyAnalyser.items[#SupplyAnalyser.items + 1] = {itemId = itemId, time = os.time()}
	SupplyAnalyser.itemCounts[itemId] = (SupplyAnalyser.itemCounts[itemId] or 0) + 1

	local itemPtr = Item.create(itemId, 1)
	local value = getCurrentPrice(itemPtr)

	-- update balance
	SupplyAnalyser.goldValue = SupplyAnalyser.goldValue + value
	SupplyAnalyser.updateBalance = true

	SupplyAnalyser:updateWidget(itemId)
	SupplyAnalyser:checkBalance()
	SupplyAnalyser:updateWindow(true)
end
