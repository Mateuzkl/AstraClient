if not LootAnalyser then
	LootAnalyser = {
		launchTime = 0,
		session = 0,
		goldValue = 0,
		goldHour = 0,
		lootedItems = {},
		-- private
		window = nil,
		event = nil,
	}

	LootAnalyser.__index = LootAnalyser
end

-- Auto-fit do valor de gold: encolhe na notacao (k/kk/kkk) ate caber no espaco
-- entre o label (esquerda) e o icone de gold (direita), evitando que valores
-- altos sobreponham os textos. Os widgets de valor tem text-auto-resize, entao
-- precisam de maxWidth explicito (ver setMoneyAutoFit em corelib/util.lua).
local function fitGold(valueWidget, labelWidget, iconWidget, amount)
	if not valueWidget then return end
	local maxW = 0
	if labelWidget and iconWidget then
		maxW = iconWidget:getX() - (labelWidget:getX() + labelWidget:getWidth()) - 6
	end
	setMoneyAutoFit(valueWidget, amount, maxW)
end

-- Abrevia o total de gold ("Sum") do tooltip em notacao k/kk/kkk a partir de 1000,
-- com virgula decimal (PT-BR) e uma casa truncada (nao arredonda, ao contrario do
-- tokformat): 1000 -> "1k", 1550 -> "1,5k", 1550000 -> "1,5kk". Abaixo de 1000 mostra
-- o inteiro cru.
local function kformat(value)
	value = math.floor(tonumber(value) or 0)
	if value < 1000 then
		return tostring(value)
	end
	local suffix, divisor = 'k', 1000
	while value >= divisor * 1000 do
		suffix = suffix .. 'k'
		divisor = divisor * 1000
	end
	local tenths = math.floor(value * 10 / divisor) -- valor em decimos da unidade abreviada
	local whole, frac = math.floor(tenths / 10), tenths % 10
	return (frac > 0 and string.format('%d,%d', whole, frac) or tostring(whole)) .. suffix
end


function LootAnalyser:create()
	LootAnalyser.launchTime = 0
	LootAnalyser.session = 0
	LootAnalyser.goldValue = 0
	LootAnalyser.goldHour = 0
	LootAnalyser.lootedItems = {}
	LootAnalyser.forceUpdateBalance = false
	LootAnalyser.updateBalance = true

	-- private
	LootAnalyser.window = openedWindows['lootButton']
end


function onLootingExtra(mousePosition)
  if cancelNextRelease then
    cancelNextRelease = false
    return false
  end

	local menu = g_ui.createWidget('PopupMenu')
	menu:setGameMenu(true)
	menu:addOption(tr('Reset Data'), function() LootAnalyser:reset(); return end)
	menu:display(mousePosition)
  return true
end

function LootAnalyser:reset()
	LootAnalyser.launchTime = g_clock.millis()
	LootAnalyser.session = 0
	LootAnalyser.goldValue = 0
	LootAnalyser.goldHour = 0
	LootAnalyser.lootedItems = {}
	LootAnalyser.forceUpdateBalance = false
	LootAnalyser.updateBalance = true

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

function LootAnalyser:checkBalance()
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
		LootAnalyser:updateWindow(false)
		LootAnalyser.updateBalance = false
	end
end

function LootAnalyser:updateWindow(updateScroll, ignoreVisible)
	if not LootAnalyser.window:isVisible() and not ignoreVisible then
		return
	end
	local contentsPanel = LootAnalyser.window.contentsPanel

	fitGold(contentsPanel.gold, contentsPanel.goldLabel, contentsPanel.goldIcon, LootAnalyser.goldValue)
	fitGold(contentsPanel.goldHour, contentsPanel.perHourLabel, contentsPanel.goldHourIcon, math.floor(LootAnalyser.goldHour))

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
				-- O count nativo do UIItem e uint16 (trunca acima de 65535) e, sem GameCountU16,
				-- nunca abrevia: totais grandes vazam da celula de 32px e sao cortados a esquerda.
				-- Suprime e usa um label proprio (tokformat) com o total real. Ver t_market.lua.
				widget:setShowCount(false)
			end
			-- setItemCount ainda define a sprite da pilha (stackables); o numero exibido vem
			-- do countLabel abreviado, imune ao corte e ao truncamento uint16.
			widget:setItemCount(info.count)
			widget.countLabel:setText(info.count > 1 and tokformat(info.count) or "")
			widget:setTooltip(string.format("%s (Value: %dgp, Sum: %s)", string.capitalize(info.name), info.basePrice, kformat(info.basePrice * info.count)))
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

-- Recalcula o gold/hora (label "Per Hour"). Chamado a cada loot e periodicamente pelo
-- Controller. O grafico de Loot Per Hour foi removido, entao aqui so atualizamos o valor.
function LootAnalyser:updateGraphics()
	local uptime = math.floor((g_clock.millis() - LootAnalyser.launchTime)/1000)
	if uptime < 5*60 then
		LootAnalyser.goldHour = LootAnalyser.goldValue
	else
		LootAnalyser.goldHour = math.floor((LootAnalyser.goldValue/uptime)*3600)
	end
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

	LootAnalyser:checkBalance()
	LootAnalyser:updateGraphics()
	LootAnalyser:updateWindow(true)
end
