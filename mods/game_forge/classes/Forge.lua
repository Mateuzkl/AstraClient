ForgeSystem = {}
ForgeSystem.__index = ForgeSystem


ForgeSystem.classPrice = {}
ForgeSystem.transferMap = {}
ForgeSystem.fusionPrices = {}
ForgeSystem.transferPrices = {}
ForgeSystem.baseMultipier = 0
ForgeSystem.slivers = 0
ForgeSystem.totalSlivers = 0
ForgeSystem.dustCost = 0
ForgeSystem.dustPrice = 0
ForgeSystem.maxDust = 0
ForgeSystem.dustFusion = 0
ForgeSystem.convergenceDustFusion = 0
ForgeSystem.dustTransfer = 0
ForgeSystem.convergenceDustTransfer = 0
ForgeSystem.success = 0
ForgeSystem.improveRateSuccess = 0
ForgeSystem.tierLoss = 0
ForgeSystem.inForgeFusion = false
ForgeSystem.fusionPrice = 0
ForgeSystem.exaltedCoreCount = 0
ForgeSystem.fusionTier = 0

ForgeSystem.fusionData = {}
ForgeSystem.fusionConvergenceData = {}
ForgeSystem.transferData = {}
ForgeSystem.transferConvergenceData = {}
ForgeSystem.maxPlayerDust = 100

local FORGE_LIST_BATCH_SIZE = 24
local forgeListBuildEvent = nil
local forgeListBuildGeneration = 0
local forgeAnimationEvent = nil
local forgeResultLabelEvent = nil

local function cancelListBuild()
	forgeListBuildGeneration = forgeListBuildGeneration + 1
	if forgeListBuildEvent then
		removeEvent(forgeListBuildEvent)
		forgeListBuildEvent = nil
	end
end

local function cancelAnimation()
	if forgeAnimationEvent then
		removeEvent(forgeAnimationEvent)
		forgeAnimationEvent = nil
	end
	if forgeResultLabelEvent then
		removeEvent(forgeResultLabelEvent)
		forgeResultLabelEvent = nil
	end
end

local function scheduleAnimation(callback, delay)
	if forgeAnimationEvent then
		removeEvent(forgeAnimationEvent)
		forgeAnimationEvent = nil
	end
	forgeAnimationEvent = scheduleEvent(function()
		forgeAnimationEvent = nil
		callback()
	end, delay)
end

local function resetSecondaryRadio(callback)
	if selectedItemFusionConvectionRadio then
		selectedItemFusionConvectionRadio:destroy()
		selectedItemFusionConvectionRadio = nil
	end
	selectedItemFusionConvectionRadio = UIRadioGroup.create()
	selectedItemFusionConvectionRadio:clearSelected()
	connect(selectedItemFusionConvectionRadio, { onSelectionChange = callback })
end

function ForgeSystem.cancelPendingEvents()
	cancelListBuild()
	cancelAnimation()
	ForgeSystem.inForgeFusion = false
end

function ForgeSystem.destroyRadioGroups()
	if selectedItemFusionRadio then
		selectedItemFusionRadio:destroy()
	end
	if selectedConvergenceFusionRadio then
		selectedConvergenceFusionRadio:destroy()
	end
	if selectedItemFusionConvectionRadio then
		selectedItemFusionConvectionRadio:destroy()
	end
	selectedItemFusionRadio = nil
	selectedConvergenceFusionRadio = nil
	selectedItemFusionConvectionRadio = nil
end

local function getClassPrice(classification, tier)
	local classPrices = ForgeSystem.classPrice[classification]
	local fusionPrices = classPrices and classPrices[2]
	return (fusionPrices and fusionPrices[tier]) or 0
end

local function setupForgeItemBox(widget, item, count)
	local amount = tonumber(count) or 0
	widget.item:setItem(item)
	widget.item:setItemCount(amount)
	widget.forgeCount = amount

	local countLabel = widget:getChildById('count')
	if countLabel then
		countLabel:setText(tostring(amount))
		countLabel:setVisible(amount > 1)
	end
end

local function buildForgeItemList(itemPanel, data, includeSubItems)
	cancelListBuild()
	itemPanel:destroyChildren()

	if selectedItemFusionRadio then
		selectedItemFusionRadio:destroy()
	end
	selectedItemFusionRadio = UIRadioGroup.create()
	selectedItemFusionRadio:clearSelected()
	connect(selectedItemFusionRadio, { onSelectionChange = onSelectionChange })

	data = data or {}
	local seenItems = {}
	local generation = forgeListBuildGeneration
	local index = 1
	local function buildBatch()
		forgeListBuildEvent = nil
		if generation ~= forgeListBuildGeneration or not itemPanel or itemPanel:isDestroyed() then
			return
		end

		local lastIndex = math.min(index + FORGE_LIST_BATCH_SIZE - 1, #data)
		for i = index, lastIndex do
			local forgeItem = data[i]
			local itemId = forgeItem[1]
			local tier = forgeItem[2]
			local key = tostring(itemId) .. '.' .. tostring(tier)
			if itemId > 0 and (not includeSubItems or not seenItems[key]) then
				local itemPtr = Item.create(itemId, 1)
				if itemPtr then
					itemPtr:setTier(tier)
					local widget = g_ui.createWidget('FusionItemBox', itemPanel)
					setupForgeItemBox(widget, itemPtr, forgeItem[3])
					widget.itemPtr = itemPtr
					widget.classification = forgeItem[5] or 0
					widget.category = forgeItem[6] or 0
					if includeSubItems then
						widget.subItems = forgeItem[4]
						seenItems[key] = true
					end
					selectedItemFusionRadio:addWidget(widget)
				end
			end
		end

		index = lastIndex + 1
		if index <= #data then
			forgeListBuildEvent = addEvent(buildBatch)
		end
	end

	buildBatch()
end

local function getForgeWidgetCount(widget)
	if widget and widget.forgeCount then
		return tonumber(widget.forgeCount) or 0
	end

	if widget and widget.item and widget.item.getItemCount then
		return tonumber(widget.item:getItemCount()) or 0
	end

	return 0
end

function ForgeSystem.init(classPrice, transferMap, fusionPrices, transferPrices, baseMultipier, slivers, totalSlivers, dustCost, dustPrice, maxDust, dustFusion, convergenceDustFusion, dustTransfer, convergenceDustTransfer, success, improveRateSuccess, tierLoss)
	ForgeSystem.classPrice = classPrice
	ForgeSystem.transferMap = transferMap
	ForgeSystem.fusionPrices = fusionPrices
	ForgeSystem.transferPrices = transferPrices
	ForgeSystem.baseMultipier = baseMultipier
	ForgeSystem.slivers = slivers
	ForgeSystem.totalSlivers = totalSlivers
	ForgeSystem.dustCost = dustCost
	ForgeSystem.dustPrice = dustPrice
	ForgeSystem.maxPlayerDust = dustPrice
	ForgeSystem.maxDust = maxDust
	ForgeSystem.dustFusion = dustFusion
	ForgeSystem.convergenceDustFusion = convergenceDustFusion
	ForgeSystem.dustTransfer = dustTransfer
	ForgeSystem.convergenceDustTransfer = convergenceDustTransfer
	ForgeSystem.success = success
	ForgeSystem.improveRateSuccess = improveRateSuccess
	ForgeSystem.tierLoss = tierLoss

	ForgeSystem.inForgeFusion = false

	fusionMenu.itemsFusion.dustPanel.item:setItemId(37160)
	fusionMenu.converFusion.convergencePanel.dustPanel.item:setItemId(37160)
	fusionMenu.converFusion.convergencePanel.dustCount.dustamount:setText(ForgeSystem.convergenceDustFusion)
	local player = g_game.getLocalPlayer()
	--forgeWindow.dustPanel.dust:setText(player:getResourceValue(ResourceForgeDust) .. '/' ..ForgeSystem.maxDust)
	fusionMenu.itemsFusion.dustCount.dustamount:setText(ForgeSystem.dustFusion)


	fusionMenu.itemsFusion.improveRateSuccessButton:setText('Improve to '.. (ForgeSystem.success + ForgeSystem.improveRateSuccess) ..'%')

	-- configure transfer
	transferMenu.itemsFusion.itemPanel.item:setItem(nil)
	transferMenu.itemsFusion.itemPanel.item.questionMark:setVisible(true)
	transferMenu.itemsFusion.itemCount.value:setText("0 / 1")
	transferMenu.itemsFusion.dustCount.dustamount:setText("0")
	transferMenu.itemsFusion.dustCount.dustamount:setColor("#d33c3c")

	transferMenu.itemsFusion.dustPanel.item:setItemId(37160)
	transferMenu.itemsFusion.dustCount.dustamount:setText(ForgeSystem.dustTransfer)
	transferMenu.itemsFusion.dustCount.dustamount:setColor("#d33c3c")

	transferMenu.itemsFusion.exaltedPanel.item:setItemId(37110)
	transferMenu.itemsFusion.exaltedCount.amount:setText("???")
	transferMenu.itemsFusion.exaltedCount.amount:setColor("#d33c3c")
	-- configure transfer
	transferMenu.converFusion.itemPanel.item:setItem(nil)
	transferMenu.converFusion.itemCount.value:setText("0 / 1")
	transferMenu.converFusion.dustCount.dustamount:setText("0")
	transferMenu.converFusion.dustCount.dustamount:setColor("#d33c3c")

	transferMenu.converFusion.dustPanel.item:setItemId(37160)
	transferMenu.converFusion.dustCount.dustamount:setText(ForgeSystem.convergenceDustTransfer)
	transferMenu.converFusion.dustCount.dustamount:setColor("#d33c3c")

	transferMenu.converFusion.exaltedPanel.item:setItemId(37110)
	transferMenu.converFusion.exaltedCount.amount:setText("???")
	transferMenu.converFusion.exaltedCount.amount:setColor("#d33c3c")

	conversionMenu.windowConvertDust.itemPanel.item:setItemId(37160)
	conversionMenu.windowConvertDust.itemCount.amount:setText(ForgeSystem.slivers * ForgeSystem.baseMultipier)
	conversionMenu.windowConvertDust.itemCount.amount:setColor("#d33c3c")
	conversionMenu.windowConvertDust.dustButton.item:setItemId(37109)
	conversionMenu.windowConvertDust.generateSlivers:setText("Generate ".. ForgeSystem.slivers)

	conversionMenu.windowConvertSlivers.itemPanel.item:setItemId(37109)
	conversionMenu.windowConvertSlivers.itemCount.amount:setText(ForgeSystem.totalSlivers)
	conversionMenu.windowConvertSlivers.itemCount.amount:setColor("#d33c3c")
	conversionMenu.windowConvertSlivers.sliverButton.item:setItemId(37110)

	local totalDustRequired = (100 - ForgeSystem.dustCost) + (ForgeSystem.maxPlayerDust - 100)
	conversionMenu.windowIncreaseDustLimit.itemPanel.item:setItemId(37160)
	conversionMenu.windowIncreaseDustLimit.itemCount.amount:setText(totalDustRequired)
	conversionMenu.windowIncreaseDustLimit.itemCount.amount:setColor("#d33c3c")
	conversionMenu.windowIncreaseDustLimit.increaseButton.item:setItemId(37160)
	conversionMenu.windowIncreaseDustLimit.increaseButton.itemRight:setItemId(37160)
	conversionMenu.windowIncreaseDustLimit.baseText:setText('Raise limit from')
	conversionMenu.windowIncreaseDustLimit.currentDust:setVisible(true)
	conversionMenu.windowIncreaseDustLimit.img1:setVisible(true)
	conversionMenu.windowIncreaseDustLimit.img2:setVisible(true)
	conversionMenu.windowIncreaseDustLimit.currentDust:setText('100')
	conversionMenu.windowIncreaseDustLimit.nextDust:setVisible(true)
	conversionMenu.windowIncreaseDustLimit.nextDust:setText('to 101')
end

function ForgeSystem.onForgeData(fusionData, fusionConvergenceData, transferData, transferConvergenceData, maxPlayerDust)
	ForgeSystem.fusionData = fusionData
	ForgeSystem.fusionConvergenceData = fusionConvergenceData
	ForgeSystem.transferData = transferData
	ForgeSystem.transferConvergenceData = transferConvergenceData
	ForgeSystem.maxPlayerDust = maxPlayerDust
	ForgeSystem.sideButton = false

	local player = g_game.getLocalPlayer()
	if not player or not forgeWindow then
		return
	end

	forgeWindow.dustPanel.dust:setText(player:getResourceValue(ResourceForgeDust) .. '/' ..ForgeSystem.maxPlayerDust)
    fusionMenu.itemFusionPanel.mindPanel.convergenceCheckBox:setChecked(false)
    transferMenu.itemTransferPanel.mindPanel.convergenceCheckBox:setChecked(false)
	if not ForgeSystem.inForgeFusion then
		show()
		if fusionMenu:isVisible() then
			ForgeSystem.updateFusion()
		end
	end
end

-- ################# FUSION
function ForgeSystem.updateFusion()
	ForgeSystem.clearFusion()
	ForgeSystem.clearTransfer()

	local data = ForgeSystem.fusionData
	if fusionMenu.converFusion:isVisible() then
		data = ForgeSystem.fusionConvergenceData
	end
	buildForgeItemList(fusionMenu.itemFusionPanel.itemsPanel, data, false)
end

-- configure panel conversion
local function ConfigureFusionConversionPanel(selectedWidget)
	local itemPtr = selectedWidget.itemPtr
	local itemCount = getForgeWidgetCount(selectedWidget)
	local itemTier = itemPtr:getTier()

	ForgeSystem.fusionItem = itemPtr
	ForgeSystem.fusionItemCount = itemCount

	fusionMenu.itemFusionPanel.nextItem:setItemId(itemPtr:getId())
	fusionMenu.itemFusionPanel.nextItem.questionMark:setVisible(false)
	fusionMenu.itemFusionPanel.nextItem.tierflags:setVisible(true)
	fusionMenu.itemFusionPanel.nextItem.tierflags:setImageClip( itemTier * 18 .." 0 18 16")

	fusionMenu.converFusion.convergencePanel.fusionButton.item:setItemId(itemPtr:getId())
	fusionMenu.converFusion.convergencePanel.fusionButton.item.questionMark:setVisible(false)
	if itemTier > 0 then
		fusionMenu.converFusion.convergencePanel.fusionButton.item.tierflags:setImageClip( (itemTier -1)* 9 .." 0 9 8")
		fusionMenu.converFusion.convergencePanel.fusionButton.item.tierflags:setVisible(true)
	else
		fusionMenu.converFusion.convergencePanel.fusionButton.item.tierflags:setVisible(false)
	end

	fusionMenu.converFusion.convergencePanel.fusionButton.itemTo:setItemId(itemPtr:getId())
	fusionMenu.converFusion.convergencePanel.fusionButton.itemTo.questionMark:setVisible(false)
	fusionMenu.converFusion.convergencePanel.fusionButton.itemTo.tierflags:setVisible(true)
	fusionMenu.converFusion.convergencePanel.fusionButton.itemTo.tierflags:setImageClip( (itemTier) * 9 .." 0 9 8")

	local data = ForgeSystem.fusionConvergenceData
	local itemsConvergencePanel = fusionMenu.converFusion.convergencePanel.itemsConvergencePanel

	itemsConvergencePanel:destroyChildren()

	if selectedItemFusionConvectionRadio then
		selectedItemFusionConvectionRadio:destroy()
	end

	selectedItemFusionConvectionRadio = UIRadioGroup.create()

	ForgeSystem.fusionSelectedItem = 0

	selectedItemFusionConvectionRadio:clearSelected()
	connect(selectedItemFusionConvectionRadio, { onSelectionChange = onSelectionForgeConvection })

	local player = g_game.getLocalPlayer()

	local function createConversionWidget(itemPtr, fusion)
		local itemId = fusion[1]

		if itemId <= 0 then
			return false
		end

		local firstCategory = getItemCategoryBySlot(itemId)
		local secondCategory = getItemCategoryBySlot(itemPtr:getId())

		if (firstCategory == -1 and secondCategory == -1) then
			return false
		end

		if firstCategory ~= secondCategory then
			return false
		end

		if itemId == itemPtr:getId() and fusion[3] == 1 then
			return false
		end

		if fusion[2] ~= itemTier then
			return false
		end

		local showItemCount = fusion[3]

		local widget = g_ui.createWidget('FusionItemBox', itemsConvergencePanel)
		local newItemPtr = Item.create(itemId, 1)
		if newItemPtr then
			newItemPtr:setTier(fusion[2])

			setupForgeItemBox(widget, newItemPtr, showItemCount)
			widget.itemPtr = newItemPtr
			widget.classification = fusion[5] or 0
			widget.category = fusion[6] or 0

			selectedItemFusionConvectionRadio:addWidget(widget)
		end
	end

	for i = 1, #ForgeSystem.fusionConvergenceData do
		local fusion = ForgeSystem.fusionConvergenceData[i]
		createConversionWidget(itemPtr, fusion)
	end

	local dust = player:getResourceValue(ResourceForgeDust)
	fusionMenu.converFusion.convergencePanel.dustCount.dustamount:setColor(dust >= ForgeSystem.convergenceDustFusion and "$var-text-cip-color" or "#d33c3c")

	local classification = itemPtr:getClassification()
	local price = ForgeSystem.fusionPrices[itemTier]

	local messageColor = {}
	ForgeSystem.fusionPrice = price
	setStringColor(messageColor, formatMoney(price, ","), ((player:getResourceValue(ResourceBank) + player:getResourceValue(ResourceInventary)) >= ForgeSystem.fusionPrice and "$var-text-cip-color" or "#d33c3c"))
	setStringColor(messageColor, " $", "#c0c0c0")
	fusionMenu.converFusion.convergencePanel.moneyPanel.gold:setColoredText(messageColor)

	ForgeSystem.checkFusionConversionButton()
end

-- configure normal panel
local function ConfigureFusionPanel(selectedWidget)
	local itemPtr = selectedWidget.itemPtr
	local itemCount = getForgeWidgetCount(selectedWidget)
	local itemTier = itemPtr:getTier()

	ForgeSystem.fusionItem = itemPtr
	ForgeSystem.fusionItemCount = itemCount

	fusionMenu.itemFusionPanel.nextItem:setItemId(itemPtr:getId())
	fusionMenu.itemFusionPanel.nextItem.questionMark:setVisible(false)
	fusionMenu.itemFusionPanel.nextItem.tierflags:setVisible(true)
	fusionMenu.itemFusionPanel.nextItem.tierflags:setImageClip( itemTier * 18 .." 0 18 16")

	fusionMenu.itemsFusion.itemPanel.item:setItemId(itemPtr:getId())
	fusionMenu.itemsFusion.itemPanel.questionMark:setVisible(false)
	fusionMenu.itemsFusion.itemCount.value:setText(itemCount.." / 1")
	fusionMenu.itemsFusion.itemCount.value:setColor(itemCount > 1 and "$var-text-cip-color" or "#d33c3c")

	fusionMenu.itemsFusion.fusionButton.item:setItemId(itemPtr:getId())
	fusionMenu.itemsFusion.fusionButton.item.questionMark:setVisible(false)
	if itemTier > 0 then
		fusionMenu.itemsFusion.fusionButton.item.tierflags:setImageClip( (itemTier - 1) * 9 .." 0 9 8")
		fusionMenu.itemsFusion.fusionButton.item.tierflags:setVisible(true)
	else
		fusionMenu.itemsFusion.fusionButton.item.tierflags:setVisible(false)
	end

	local player = g_game.getLocalPlayer()
	local dust = player:getResourceValue(ResourceForgeDust)
	fusionMenu.itemsFusion.dustCount.dustamount:setColor(dust >= ForgeSystem.dustFusion and "$var-text-cip-color" or "#d33c3c")


	fusionMenu.itemsFusion.fusionButton.itemTo:setItemId(itemPtr:getId())
	fusionMenu.itemsFusion.fusionButton.itemTo.questionMark:setVisible(false)
	fusionMenu.itemsFusion.fusionButton.itemTo.tierflags:setImageClip( itemTier * 9 .." 0 9 8")
	fusionMenu.itemsFusion.fusionButton.itemTo.tierflags:setVisible(true)

	local classification = selectedWidget.classification or itemPtr:getClassification()
	local price = getClassPrice(classification, itemTier)

	ForgeSystem.fusionPrice = price
	local messageColor = {}
	setStringColor(messageColor, formatMoney(price, ","), ((player:getResourceValue(ResourceBank) + player:getResourceValue(ResourceInventary)) >= ForgeSystem.fusionPrice and "$var-text-cip-color" or "#d33c3c"))
	setStringColor(messageColor, " $", "#c0c0c0")
	fusionMenu.itemsFusion.moneyPanel.gold:setColoredText(messageColor)

	ForgeSystem.checkFusionButton()

	ForgeSystem.checkFusionButtons()
	ForgeSystem.checkFusionLabels()
end

-- check if ok buttons is enabled
function ForgeSystem.checkFusionButton()
	fusionMenu.itemsFusion.fusionButton.locked:setVisible(not ForgeSystem.checkFusionState())
	fusionMenu.itemsFusion.fusionButton:setEnabled(ForgeSystem.checkFusionState())
end

-- check if ok buttons is enabled
function ForgeSystem.checkFusionConversionButton()
	fusionMenu.converFusion.convergencePanel.fusionButton.locked:setVisible(not ForgeSystem.checkFusionConversionState())
	fusionMenu.converFusion.convergencePanel.fusionButton:setEnabled(ForgeSystem.checkFusionConversionState())
end

-- check core buttons
function ForgeSystem.checkFusionButtons()
	local player = g_game.getLocalPlayer()
	if not player then
		return
	end

	local exaltedCore = player:getResourceValue(ResourceForgeExaltedCore)
	if ForgeSystem.rateSuccessActive then
		exaltedCore = exaltedCore - 1
		fusionMenu.itemsFusion.improveRateSuccessButton:setEnabled(true)
		fusionMenu.itemsFusion.improveRateSuccessPanel.exaltedcoreamount:setColor("$var-text-cip-color")
	end
	if ForgeSystem.tierLossActive then
		exaltedCore = exaltedCore - 1
		fusionMenu.itemsFusion.tierLossButton:setEnabled(true)
		fusionMenu.itemsFusion.tierLossPanel.exaltedcoreamount:setColor("$var-text-cip-color")
	end

	if exaltedCore < 1 then
		if not ForgeSystem.rateSuccessActive then
			fusionMenu.itemsFusion.improveRateSuccessButton:setEnabled(false)
			fusionMenu.itemsFusion.improveRateSuccessPanel.exaltedcoreamount:setColor("#d33c3c")
		end
		if not ForgeSystem.tierLossActive then
			fusionMenu.itemsFusion.tierLossButton:setEnabled(false)
			fusionMenu.itemsFusion.tierLossPanel.exaltedcoreamount:setColor("#d33c3c")
		end
	else
		if not ForgeSystem.rateSuccessActive then
			fusionMenu.itemsFusion.improveRateSuccessButton:setEnabled(true)
			fusionMenu.itemsFusion.improveRateSuccessPanel.exaltedcoreamount:setColor("$var-text-cip-color")
		end
		if not ForgeSystem.tierLossActive then
			fusionMenu.itemsFusion.tierLossButton:setEnabled(true)
			fusionMenu.itemsFusion.tierLossPanel.exaltedcoreamount:setColor("$var-text-cip-color")
		end
	end
end

-- check if has condition
function ForgeSystem.checkFusionConversionState()
	local player = g_game.getLocalPlayer()
	if not player then
		return false
	end

	local hasDust = player:getResourceValue(ResourceForgeDust) >= ForgeSystem.convergenceDustFusion
	local hasMoney = (player:getResourceValue(ResourceBank) + player:getResourceValue(ResourceInventary)) >= ForgeSystem.fusionPrice

	return hasDust and hasMoney and ForgeSystem.fusionSelectedItem ~= 0 and not ForgeSystem.sideButton
end

-- check if has condition
function ForgeSystem.checkFusionState()
	local player = g_game.getLocalPlayer()
	if not player then
		return false
	end
	local hasItemCount = ForgeSystem.fusionItemCount >= 2
	local hasDust = player:getResourceValue(ResourceForgeDust) >= ForgeSystem.dustFusion
	local hasMoney = (player:getResourceValue(ResourceBank) + player:getResourceValue(ResourceInventary)) >= ForgeSystem.fusionPrice

	return hasItemCount and hasDust and hasMoney and not ForgeSystem.sideButton
end

-- check color label (core)
function ForgeSystem.checkFusionLabels()
	fusionMenu.itemsFusion.successLabel:setText(ForgeSystem.rateSuccessActive and (ForgeSystem.success + ForgeSystem.improveRateSuccess) .. "%" or "50%")
	fusionMenu.itemsFusion.successLabel:setColor(ForgeSystem.rateSuccessActive and "#44ad25" or "#d33c3c")

	fusionMenu.itemsFusion.tierLossLabel:setText(ForgeSystem.tierLossActive and ForgeSystem.tierLoss .. "%" or "100%")
	fusionMenu.itemsFusion.tierLossLabel:setColor(ForgeSystem.tierLossActive and "#44ad25" or "#d33c3c")
end

-- reset variables
function ForgeSystem.clearFusion()
	cancelListBuild()
	if selectedItemFusionConvectionRadio then
		selectedItemFusionConvectionRadio:destroy()
		selectedItemFusionConvectionRadio = nil
	end
	ForgeSystem.fusionItem = nil
	ForgeSystem.fusionItemCount = 0
	ForgeSystem.exaltedCoreCount = 0
	-- ForgeSystem.fusionPrice = 0
	ForgeSystem.fusionSelectedItem = 0
	ForgeSystem.rateSuccessActive = false
	ForgeSystem.tierLossActive = false
	ForgeSystem.fusionTier = 0

	-- fusion convergence
	fusionMenu.converFusion.convergencePanel.itemsConvergencePanel:destroyChildren()
	fusionMenu.converFusion.convergencePanel.dustCount.dustamount:setColor("#d33c3c")
	fusionMenu.converFusion.convergencePanel.fusionButton:setEnabled(false)
	fusionMenu.converFusion.convergencePanel.fusionButton.locked:setVisible(true)
	fusionMenu.converFusion.convergencePanel.fusionButton.item:setItem(nil)
	fusionMenu.converFusion.convergencePanel.fusionButton.item.tierflags:setVisible(false)
	fusionMenu.converFusion.convergencePanel.fusionButton.item.questionMark:setVisible(true)
	fusionMenu.converFusion.convergencePanel.fusionButton.itemTo:setItem(nil)
	fusionMenu.converFusion.convergencePanel.fusionButton.itemTo.tierflags:setVisible(false)
	fusionMenu.converFusion.convergencePanel.fusionButton.itemTo.questionMark:setVisible(true)


	local messageColor = {}
	setStringColor(messageColor, "???", "#d33c3c")
	setStringColor(messageColor, " $", "#c0c0c0")
	fusionMenu.converFusion.convergencePanel.moneyPanel.gold:setColoredText(messageColor)


	-- fusion normal
	fusionMenu.itemFusionPanel.nextItem:setItem(nil)
	fusionMenu.itemFusionPanel.nextItem.tierflags:setVisible(false)
	fusionMenu.itemFusionPanel.nextItem.questionMark:setVisible(true)

	fusionMenu.itemsFusion.itemPanel.item:setItem(nil)
	fusionMenu.itemsFusion.itemPanel.questionMark:setVisible(true)
	fusionMenu.itemsFusion.itemCount.value:setText("0 / 1")
	fusionMenu.itemsFusion.itemCount.value:setColor("#d33c3c")

	fusionMenu.itemsFusion.fusionButton.item:setItem(nil)
	fusionMenu.itemsFusion.fusionButton.item.tierflags:setVisible(false)
	fusionMenu.itemsFusion.fusionButton.item.questionMark:setVisible(true)
	fusionMenu.itemsFusion.dustCount.dustamount:setColor("#d33c3c")

	fusionMenu.itemsFusion.fusionButton.itemTo:setItem(nil)
	fusionMenu.itemsFusion.fusionButton.itemTo.tierflags:setVisible(false)
	fusionMenu.itemsFusion.fusionButton.itemTo.questionMark:setVisible(true)


	local messageColor = {}
	setStringColor(messageColor, "???", "#d33c3c")
	setStringColor(messageColor, " $", "#c0c0c0")
	fusionMenu.itemsFusion.moneyPanel.gold:setColoredText(messageColor)

	fusionMenu.itemsFusion.fusionButton.locked:setVisible(true)
	fusionMenu.itemsFusion.fusionButton:setEnabled(false)
	ForgeSystem.checkFusionButtons()
	ForgeSystem.checkFusionLabels()

	ForgeSystem.checkFusionConversionButton()
end

function ForgeSystem.clearTransfer()
	cancelListBuild()
	if selectedItemFusionConvectionRadio then
		selectedItemFusionConvectionRadio:destroy()
		selectedItemFusionConvectionRadio = nil
	end
	ForgeSystem.fusionItem = nil
	ForgeSystem.fusionItemCount = 0
	-- ForgeSystem.fusionPrice = 0
	ForgeSystem.fusionSelectedItem = 0
	ForgeSystem.exaltedCoreCount = 0
	ForgeSystem.rateSuccessActive = false
	ForgeSystem.tierLossActive = false
	ForgeSystem.fusionTier = 0

	transferMenu.itemTransferPanel.itemsTransferPanel:destroyChildren()

	transferMenu.itemsFusion.itemPanel.item:setItem(nil)
	transferMenu.itemsFusion.itemPanel.item.questionMark:setVisible(true)
	transferMenu.itemsFusion.itemCount.value:setText("0 / 1")
	transferMenu.itemsFusion.itemCount.value:setColor("#d33c3c")
	transferMenu.itemsFusion.itemPanel.item.tierflags:setVisible(false)

	transferMenu.itemsFusion.dustCount.dustamount:setColor("#d33c3c")

	transferMenu.itemsFusion.exaltedCount.amount:setText("???")
	transferMenu.itemsFusion.exaltedCount.amount:setColor("#d33c3c")

	transferMenu.itemsFusion.transferButton.item:setItem(nil)
	transferMenu.itemsFusion.transferButton.item.questionMark:setVisible(true)
	transferMenu.itemsFusion.transferButton.item.tierflags:setVisible(false)

	transferMenu.itemsFusion.transferButton.itemTo:setItem(nil)
	transferMenu.itemsFusion.transferButton.itemTo.questionMark:setVisible(true)
	transferMenu.itemsFusion.transferButton.itemTo.tierflags:setVisible(false)

	local messageColor = {}
	setStringColor(messageColor, "???", "#d33c3c")
	setStringColor(messageColor, " $", "#c0c0c0")
	transferMenu.itemsFusion.moneyPanel.gold:setColoredText(messageColor)

	transferMenu.converFusion.itemPanel.item:setItem(nil)
	transferMenu.converFusion.itemPanel.item.questionMark:setVisible(true)
	transferMenu.converFusion.itemCount.value:setText("0 / 1")
	transferMenu.converFusion.itemCount.value:setColor("#d33c3c")
	transferMenu.converFusion.itemPanel.item.tierflags:setVisible(false)

	transferMenu.converFusion.dustCount.dustamount:setColor("#d33c3c")

	transferMenu.converFusion.exaltedCount.amount:setText("???")
	transferMenu.converFusion.exaltedCount.amount:setColor("#d33c3c")

	transferMenu.converFusion.transferButton.item:setItem(nil)
	transferMenu.converFusion.transferButton.item.questionMark:setVisible(true)
	transferMenu.converFusion.transferButton.item.tierflags:setVisible(false)

	transferMenu.converFusion.transferButton.itemTo:setItem(nil)
	transferMenu.converFusion.transferButton.itemTo.questionMark:setVisible(true)
	transferMenu.converFusion.transferButton.itemTo.tierflags:setVisible(false)

	local messageColor = {}
	setStringColor(messageColor, "???", "#d33c3c")
	setStringColor(messageColor, " $", "#c0c0c0")
	transferMenu.converFusion.moneyPanel.gold:setColoredText(messageColor)

	ForgeSystem.checkTransferConvergenceButton()
end


function onSelectionForgeConvection(widget, selectedWidget)
	local itemPtr = selectedWidget.itemPtr

	ForgeSystem.fusionSelectedItem = itemPtr:getId()

	ForgeSystem.checkFusionConversionButton()
end

function onConvergenceFusionChange(_, isChecked)
	ForgeSystem.clearFusion()
	fusionMenu.itemsFusion:setVisible(not isChecked)
	fusionMenu.converFusion:setVisible(isChecked)
	ForgeSystem.updateFusion()
end

function ForgeSystem.onForgeFusion(convergence, success, otherItem, otherTier, itemId, tier, resultType, itemResult, tierResult, count)
	if not ensureForgeResultWindow() then
		return
	end
	cancelAnimation()
	hideForge()
	resultWindow:show(true)

	resultWindow:setText('Fusion Result')

	resultWindow.contentPanel.resultWindow:setVisible(false)
	resultWindow.contentPanel.bonusWindow:setVisible(false)

	local resultWindowPanel = resultWindow.contentPanel.resultWindow
	ForgeSystem.inForgeFusion = true
	resultWindowPanel:setVisible(true)
	resultWindowPanel.resultLabel:setText('')

	resultWindowPanel.transferItem:setItemId(otherItem)
	resultWindowPanel.transferItem:setItemShader("item_print_white")
	resultWindowPanel.transferItem.tierflags:setImageClip((otherTier -1) * 18 .. " 0 18 16")
	resultWindowPanel.transferItem.tierflags:setVisible(false)

	resultWindowPanel.recvItem:setItemId(itemId)
	resultWindowPanel.recvItem:setItemShader("item_black_white")
	resultWindowPanel.recvItem.tierflags:setImageClip((tier - 1) * 18 .. " 0 18 16")
	resultWindowPanel.recvItem.tierflags:setVisible(false)

	resultWindowPanel.finishButton:setEnabled(false)
	resultWindowPanel.finishButton:setText("Close")
	resultWindowPanel.finishButton.locked:setVisible(true)
	if resultType == 0 then
		resultWindowPanel.finishButton.onClick = function() modules.game_forge.ForgeSystem.closeFinish() end
	else
		resultWindowPanel.finishButton.onClick = function() modules.game_forge.ForgeSystem.openBonusFinish(convergence, ForgeSystem.fusionPrice, resultType, itemResult, tierResult, count) end
		forgeResultLabelEvent = scheduleEvent(function()
			forgeResultLabelEvent = nil
			if resultWindow and not resultWindow:isDestroyed() then
				resultWindowPanel.finishButton:setText("Next")
			end
		end, 3550)
	end

	scheduleAnimation(function() ForgeSystemEventFusionColor(false, success, otherItem, otherTier, itemId, tier, resultType, itemResult, tierResult, count, 1) end, 750)
end

function ForgeSystem.onForgeTransfer(convergence, success, otherItem, otherTier, itemId, tier)
	if not ensureForgeResultWindow() then
		return
	end
	cancelAnimation()
	hideForge()
	resultWindow:show(true)

	resultWindow:setText('Transfer Result')

	resultWindow.contentPanel.resultWindow:setVisible(false)
	resultWindow.contentPanel.bonusWindow:setVisible(false)

	local resultWindowPanel = resultWindow.contentPanel.resultWindow
	ForgeSystem.inForgeFusion = true
	resultWindowPanel:setVisible(true)
	resultWindowPanel.resultLabel:setText('')

	resultWindowPanel.transferItem:setItemId(otherItem)
	resultWindowPanel.transferItem:setItemShader("item_print_white")
	resultWindowPanel.transferItem.tierflags:setImageClip((otherTier - 1) * 18 .. " 0 18 16")
	resultWindowPanel.transferItem.tierflags:setVisible(true)

	resultWindowPanel.recvItem:setItemId(itemId)
	resultWindowPanel.recvItem:setItemShader("item_black_white")
	resultWindowPanel.recvItem.tierflags:setImageClip((tier - 1) * 18 .. " 0 18 16")
	resultWindowPanel.recvItem.tierflags:setVisible(false)

	resultWindowPanel.finishButton:setEnabled(false)
	resultWindowPanel.finishButton:setText("Close")
	resultWindowPanel.finishButton.locked:setVisible(true)
	resultWindowPanel.finishButton.onClick = function() modules.game_forge.ForgeSystem.closeFinish() end

	scheduleAnimation(function() ForgeSystemEventFusionColor(true, success, otherItem, otherTier, itemId, tier, 0, 0, 0, 0, 1) end, 750)
end

function ForgeSystem.sendForgeFusion(convergence)
	ForgeSystem.inForgeFusion = false
	if not convergence then
		g_game.sendForgeFusion(false, ForgeSystem.fusionItem:getId(), ForgeSystem.fusionItem:getTier(), ForgeSystem.fusionItem:getId(), ForgeSystem.rateSuccessActive, ForgeSystem.tierLossActive)
	else
		g_game.sendForgeFusion(true, ForgeSystem.fusionItem:getId(), ForgeSystem.fusionItem:getTier(), ForgeSystem.fusionSelectedItem, false, false)
	end
end

-- ################# FUSION
-- ################# TRANSFER
function ForgeSystem.updateTransfer()
	ForgeSystem.clearFusion()
	ForgeSystem.clearTransfer()

	local data = ForgeSystem.transferData
	if transferMenu.converFusion:isVisible() then
		data = ForgeSystem.transferConvergenceData
	end
	buildForgeItemList(transferMenu.itemTransferPanel.itemsPanel, data, true)
end


local function ConfigureTransferPanel(selectedWidget)
	ForgeSystem.fusionSelectedItem = 0

	local itemPtr = selectedWidget.itemPtr
	local itemCount = getForgeWidgetCount(selectedWidget)
	local itemTier = itemPtr:getTier()
	local subItems = selectedWidget.subItems

	ForgeSystem.fusionItem = itemPtr
	ForgeSystem.fusionItemCount = itemCount
	ForgeSystem.fusionTier = itemTier

	transferMenu.itemTransferPanel.itemsTransferPanel:destroyChildren()
	local itemsTransferPanel = transferMenu.itemTransferPanel.itemsTransferPanel

	resetSecondaryRadio(onSelectionForgeTransfer)


	for item, count in pairs(subItems) do
		if item == itemPtr:getId() or item <= 0 then
			goto continue
		end

		local widget = g_ui.createWidget('FusionItemBox', itemsTransferPanel)
		local newItemPtr = Item.create(item, 1)

		if newItemPtr then
			setupForgeItemBox(widget, newItemPtr, count)
			widget.itemPtr = newItemPtr
			selectedItemFusionConvectionRadio:addWidget(widget)
		end
		::continue::
	end

	transferMenu.itemsFusion.itemPanel.item:setItemId(itemPtr:getId())
	transferMenu.itemsFusion.itemPanel.item.questionMark:setVisible(false)
	transferMenu.itemsFusion.itemCount.value:setText(itemCount.." / 1")
	transferMenu.itemsFusion.itemCount.value:setColor("$var-text-cip-color")

	if itemTier > 0 then
		transferMenu.itemsFusion.itemPanel.item.tierflags:setImageClip( (itemTier - 1) * 18 .." 0 18 16")
		transferMenu.itemsFusion.itemPanel.item.tierflags:setVisible(true)
	else
		transferMenu.itemsFusion.itemPanel.item.tierflags:setVisible(false)
	end

	local player = g_game.getLocalPlayer()
	local dust = player:getResourceValue(ResourceForgeDust)
	transferMenu.itemsFusion.dustCount.dustamount:setColor((dust >= ForgeSystem.dustTransfer and "$var-text-cip-color" or "#d33c3c"))
	forgeWindow.dustPanel.dust:setText(dust .. '/' ..ForgeSystem.maxPlayerDust)

	local exaltedCoreCount = ForgeSystem.transferMap[itemTier - 1] or 1
	transferMenu.itemsFusion.exaltedCount.amount:setText(exaltedCoreCount)
	local exaltedCore = player:getResourceValue(ResourceForgeExaltedCore)
	transferMenu.itemsFusion.exaltedCount.amount:setColor((exaltedCore >= exaltedCoreCount and "$var-text-cip-color" or "#d33c3c"))

	ForgeSystem.exaltedCoreCount = exaltedCoreCount

	transferMenu.itemsFusion.transferButton.item:setItemId(itemPtr:getId())
	transferMenu.itemsFusion.transferButton.item.questionMark:setVisible(false)
	transferMenu.itemsFusion.transferButton.item.tierflags:setVisible(true)
	transferMenu.itemsFusion.transferButton.item.tierflags:setImageClip( (itemTier - 1) * 9 .." 0 9 8")

	local classification = selectedWidget.classification or itemPtr:getClassification()
	local price = getClassPrice(classification, itemTier - 1)
	ForgeSystem.fusionPrice = price

	local messageColor = {}
	setStringColor(messageColor, formatMoney(price, ","), (player:getResourceValue(ResourceBank) + player:getResourceValue(ResourceInventary)) >= ForgeSystem.fusionPrice and "$var-text-cip-color" or "#d33c3c")
	setStringColor(messageColor, " $", "#c0c0c0")
	transferMenu.itemsFusion.moneyPanel.gold:setColoredText(messageColor)


	ForgeSystem.checkTransferButton()
end

local function ConfigureTransferConvergencePanel(selectedWidget)
	ForgeSystem.fusionSelectedItem = 0

	local itemPtr = selectedWidget.itemPtr
	local itemCount = getForgeWidgetCount(selectedWidget)
	local itemTier = itemPtr:getTier()
	local subItems = selectedWidget.subItems

	ForgeSystem.fusionItem = itemPtr
	ForgeSystem.fusionItemCount = itemCount
	ForgeSystem.fusionTier = itemTier

	transferMenu.itemTransferPanel.itemsTransferPanel:destroyChildren()
	local itemsTransferPanel = transferMenu.itemTransferPanel.itemsTransferPanel

	resetSecondaryRadio(onSelectionForgeConversionTransfer)

	for item, count in pairs(subItems) do
		if item == itemPtr:getId() or item <= 0 then
			goto continue
		end

		local widget = g_ui.createWidget('FusionItemBox', itemsTransferPanel)
		local newItemPtr = Item.create(item, 1)

		if newItemPtr then
			setupForgeItemBox(widget, newItemPtr, count)
			widget.itemPtr = newItemPtr
			selectedItemFusionConvectionRadio:addWidget(widget)
		end
		::continue::
	end

	transferMenu.converFusion.itemPanel.item:setItemId(itemPtr:getId())
	transferMenu.converFusion.itemPanel.item.questionMark:setVisible(false)
	transferMenu.converFusion.itemCount.value:setText(itemCount.." / 1")
	transferMenu.converFusion.itemCount.value:setColor("$var-text-cip-color")

	if itemTier > 0 then
		transferMenu.converFusion.itemPanel.item.tierflags:setImageClip( (itemTier - 1) * 18 .." 0 18 16")
		transferMenu.converFusion.itemPanel.item.tierflags:setVisible(true)
	else
		transferMenu.converFusion.itemPanel.item.tierflags:setVisible(false)
	end

	local player = g_game.getLocalPlayer()
	local dust = player:getResourceValue(ResourceForgeDust)
	transferMenu.converFusion.dustCount.dustamount:setColor((dust >= ForgeSystem.convergenceDustTransfer and "$var-text-cip-color" or "#d33c3c"))
	forgeWindow.dustPanel.dust:setText(dust .. '/' ..ForgeSystem.maxPlayerDust)

	local exaltedCoreCount = ForgeSystem.transferMap[itemTier]
	transferMenu.converFusion.exaltedCount.amount:setText(exaltedCoreCount)
	local exaltedCore = player:getResourceValue(ResourceForgeExaltedCore)
	transferMenu.converFusion.exaltedCount.amount:setColor((exaltedCore >= exaltedCoreCount and "$var-text-cip-color" or "#d33c3c"))

	ForgeSystem.exaltedCoreCount = exaltedCoreCount

	transferMenu.converFusion.transferButton.item:setItemId(itemPtr:getId())
	transferMenu.converFusion.transferButton.item.questionMark:setVisible(false)
	transferMenu.converFusion.transferButton.item.tierflags:setVisible(true)
	transferMenu.converFusion.transferButton.item.tierflags:setImageClip( (itemTier - 1) * 9 .." 0 9 8")

	local price = ForgeSystem.transferPrices[itemTier]
	ForgeSystem.fusionPrice = price

	local messageColor = {}
	setStringColor(messageColor, formatMoney(price, ","), (player:getResourceValue(ResourceBank) + player:getResourceValue(ResourceInventary)) >= ForgeSystem.fusionPrice and "$var-text-cip-color" or "#d33c3c")
	setStringColor(messageColor, " $", "#c0c0c0")
	transferMenu.converFusion.moneyPanel.gold:setColoredText(messageColor)


	ForgeSystem.checkTransferButton()
end

function ForgeSystem.checkTransferConvergenceButton()
	transferMenu.converFusion.transferButton.locked:setVisible(not ForgeSystem.checkTransferState())
	transferMenu.converFusion.transferButton:setEnabled(ForgeSystem.checkTransferState())
end

function ForgeSystem.checkTransferButton()
	transferMenu.itemsFusion.transferButton.locked:setVisible(not ForgeSystem.checkTransferState())
	transferMenu.itemsFusion.transferButton:setEnabled(ForgeSystem.checkTransferState())
end

function ForgeSystem.checkTransferState()
	local player = g_game.getLocalPlayer()
	if not player then
		return false
	end
	local hasItemCount = ForgeSystem.fusionSelectedItem ~= 0
	local hasDust = false
	if not transferMenu.converFusion:isVisible() then
		hasDust = player:getResourceValue(ResourceForgeDust) >= ForgeSystem.dustTransfer
	else
		hasDust = player:getResourceValue(ResourceForgeDust) >= ForgeSystem.convergenceDustTransfer
	end

	local hasExalted = player:getResourceValue(ResourceForgeExaltedCore) >= ForgeSystem.exaltedCoreCount
	local hasMoney = (player:getResourceValue(ResourceBank) + player:getResourceValue(ResourceInventary)) >= ForgeSystem.fusionPrice

	return hasItemCount and hasDust and hasMoney and hasExalted and not ForgeSystem.sideButton
end

function ForgeSystem.addSecondTransferItem()
	transferMenu.itemsFusion.transferButton.itemTo:setItemId(ForgeSystem.fusionSelectedItem)
	transferMenu.itemsFusion.transferButton.itemTo.questionMark:setVisible(false)
	transferMenu.itemsFusion.transferButton.itemTo.tierflags:setVisible(true)
	transferMenu.itemsFusion.transferButton.itemTo.tierflags:setImageClip( (ForgeSystem.fusionTier - 2) * 9 .." 0 9 8")
end

function ForgeSystem.addSecondTransferConvergenceItem()
	transferMenu.converFusion.transferButton.itemTo:setItemId(ForgeSystem.fusionSelectedItem)
	transferMenu.converFusion.transferButton.itemTo.questionMark:setVisible(false)
	transferMenu.converFusion.transferButton.itemTo.tierflags:setVisible(true)
	transferMenu.converFusion.transferButton.itemTo.tierflags:setImageClip( (ForgeSystem.fusionTier - 1) * 9 .." 0 9 8")
end

function onSelectionForgeTransfer(widget, selectedWidget)
	local itemPtr = selectedWidget.itemPtr

	ForgeSystem.fusionSelectedItem = itemPtr:getId()

	ForgeSystem.addSecondTransferItem()
	ForgeSystem.checkTransferButton()
end

function onSelectionForgeConversionTransfer(widget, selectedWidget)
	local itemPtr = selectedWidget.itemPtr

	ForgeSystem.fusionSelectedItem = itemPtr:getId()

	ForgeSystem.addSecondTransferConvergenceItem()
	ForgeSystem.checkTransferConvergenceButton()
end

---
function ForgeSystemEventFusionColor(transfer, success, otherItem, otherTier, itemId, tier, resultType, itemResult, tierResult, count, eventCount)
	if not g_game.isOnline() then
		ForgeSystem.inForgeFusion = false
		return
	end

	local resultWindowPanel = resultWindow.contentPanel.resultWindow

	if eventCount == 1 then
		resultWindowPanel.panel.tick1:setImageSource("/images/arrows/icon-arrow-rightlarge-filled")
		resultWindowPanel.panel.tick2:setImageSource("/images/arrows/icon-arrow-rightlarge")
		resultWindowPanel.panel.tick3:setImageSource("/images/arrows/icon-arrow-rightlarge")
	elseif eventCount == 2 then
		resultWindowPanel.panel.tick1:setImageSource("/images/arrows/icon-arrow-rightlarge-filled")
		resultWindowPanel.panel.tick2:setImageSource("/images/arrows/icon-arrow-rightlarge-filled")
		resultWindowPanel.panel.tick3:setImageSource("/images/arrows/icon-arrow-rightlarge")
	elseif eventCount == 3 then
		resultWindowPanel.panel.tick1:setImageSource("/images/arrows/icon-arrow-rightlarge")
		resultWindowPanel.panel.tick2:setImageSource("/images/arrows/icon-arrow-rightlarge-filled")
		resultWindowPanel.panel.tick3:setImageSource("/images/arrows/icon-arrow-rightlarge-filled")
	elseif eventCount == 4 then
		resultWindowPanel.panel.tick1:setImageSource("/images/arrows/icon-arrow-rightlarge")
		resultWindowPanel.panel.tick2:setImageSource("/images/arrows/icon-arrow-rightlarge")
		resultWindowPanel.panel.tick3:setImageSource("/images/arrows/icon-arrow-rightlarge-filled")
	elseif eventCount == 5 then
		resultWindowPanel.panel.tick1:setImageSource("/images/arrows/icon-arrow-rightlarge-filled")
		resultWindowPanel.panel.tick2:setImageSource("/images/arrows/icon-arrow-rightlarge-filled")
		resultWindowPanel.panel.tick3:setImageSource("/images/arrows/icon-arrow-rightlarge-filled")
		ForgeSystem.inForgeFusion = false

		resultWindowPanel.transferItem:setItemShader("")
		if not success then
			resultWindowPanel.recvItem:setItemShader("item_red")
			scheduleAnimation(function()
				resultWindowPanel.recvItem:setItem(nil)
			end, 500)
		else
			resultWindowPanel.transferItem:setItem(nil)
			resultWindowPanel.recvItem:setItemShader("")
			resultWindowPanel.recvItem.tierflags:setVisible(true)
		end

		-- message
		local message = {}
		setStringColor(message, "Your ".. (transfer and "transfer" or "fusion") .." attempt was ", "$var-text-cip-color-grey")
		if not success then
			setStringColor(message, "failed", "#d33c3c")
		else
			setStringColor(message, "successful", "$var-text-cip-color-green")
		end
		setStringColor(message, ".", "$var-text-cip-color-grey")

		resultWindowPanel.resultLabel:setColoredText(message)

		resultWindowPanel.finishButton:setEnabled(true)
		resultWindowPanel.finishButton.locked:setVisible(false)

		return
	end

	scheduleAnimation(function() ForgeSystemEventFusionColor(transfer, success, otherItem, otherTier, itemId, tier, resultType, itemResult, tierResult, count, eventCount + 1) end, 750)
end

function ForgeSystem.openBonusFinish(convergence, price, resultType, itemResult, tierResult, count)
	resultWindow.contentPanel.resultWindow:setVisible(false)
	resultWindow.contentPanel.bonusWindow:setVisible(true)

	local bonusResult = resultWindow.contentPanel.bonusWindow

	bonusResult.bonusItem.tierflags:setVisible(false)
	bonusResult.bonusItem:setItemShader("")
	if resultType == 1 then
		bonusResult.bonusItem:setItemId(37160)
		bonusResult.resultLabel:setText("Near! The used ".. (not convergence and ForgeSystem.dustPrice or ForgeSystem.convergenceDustFusion) .." where not consumed.")
	elseif resultType == 2 then
		bonusResult.bonusItem:setItemId(37110)
		bonusResult.resultLabel:setText("Fantastic! The used ".. count .." where not consumed.")
	elseif resultType == 3 then
		bonusResult.bonusItem:setItemId(3031)
		bonusResult.resultLabel:setText("Awesome! The used ".. formatMoney(price, ",") .." where not consumed.")
	elseif resultType == 4 then
		bonusResult.bonusItem:setItemId(itemResult)
		bonusResult.bonusItem.tierflags:setImageClip((tierResult - 1) * 18 .. " 0 18 16")
		bonusResult.bonusItem.tierflags:setVisible(true)
		bonusResult.resultLabel:setText("What luck! Your item only lost one tier instead of being\n                                     consumed.")
	end
end

function ForgeSystem.closeFinish()
	cancelAnimation()
	resultWindow:hide()
	show()
end

function onSelectionChange(widget, selectedWidget)
	if fusionMenu.itemsFusion:isVisible() then
		ConfigureFusionPanel(selectedWidget)
	elseif fusionMenu.converFusion:isVisible() then
		ConfigureFusionConversionPanel(selectedWidget)
	elseif transferMenu.itemsFusion:isVisible() then
		ConfigureTransferPanel(selectedWidget)
	elseif transferMenu.converFusion:isVisible() then
		ConfigureTransferConvergencePanel(selectedWidget)
	end
end

function ForgeSystem.sendForgeTransfer(convergence)
	ForgeSystem.inForgeFusion = false
	if not convergence then
		g_game.sendForgeTransfer(false, ForgeSystem.fusionItem:getId(), ForgeSystem.fusionItem:getTier(), ForgeSystem.fusionSelectedItem)
	else
		g_game.sendForgeTransfer(true, ForgeSystem.fusionItem:getId(), ForgeSystem.fusionItem:getTier(), ForgeSystem.fusionSelectedItem)
	end

end

-- transfer convergence
function onConvergenceTransferChange(widget, isChecked)
	ForgeSystem.clearTransfer()
	if isChecked then
		transferMenu.itemsFusion:setVisible(false)
		transferMenu.converFusion:setVisible(true)
	else
		transferMenu.itemsFusion:setVisible(true)
		transferMenu.converFusion:setVisible(false)
	end
	ForgeSystem.updateTransfer()
end

function ForgeSystem.updateConversion()
	local player = g_game.getLocalPlayer()
	if not player then
		return false
	end

	local dust = player:getResourceValue(ResourceForgeDust)

	local price1 = ForgeSystem.slivers * ForgeSystem.baseMultipier
	conversionMenu.windowConvertDust.itemCount.amount:setColor(dust >= price1 and "$var-text-cip-color" or "#d33c3c")

	conversionMenu.windowConvertDust.dustButton:setEnabled(dust >= price1)
	conversionMenu.windowConvertDust.dustButton.locked:setVisible(dust < price1)

	conversionMenu.windowConvertSlivers.itemCount.amount:setText(ForgeSystem.totalSlivers)
	conversionMenu.windowConvertSlivers.itemCount.amount:setColor(player:getResourceValue(ResourceForgeSlivers) >= ForgeSystem.totalSlivers and "$var-text-cip-color" or "#d33c3c")
	conversionMenu.windowConvertSlivers.sliverButton:setEnabled(player:getResourceValue(ResourceForgeSlivers) >= ForgeSystem.totalSlivers)
	conversionMenu.windowConvertSlivers.sliverButton.locked:setVisible(player:getResourceValue(ResourceForgeSlivers) < ForgeSystem.totalSlivers)

	local totalDustRequired = (100 - ForgeSystem.dustCost) + (ForgeSystem.maxPlayerDust - 100)
	conversionMenu.windowIncreaseDustLimit.itemCount.amount:setText(totalDustRequired)
	conversionMenu.windowIncreaseDustLimit.itemCount.amount:setColor(dust >= totalDustRequired and "$var-text-cip-color" or "#d33c3c")
	conversionMenu.windowIncreaseDustLimit.currentDust:setText(ForgeSystem.maxPlayerDust)
	conversionMenu.windowIncreaseDustLimit.nextDust:setText('to ' .. math.min(ForgeSystem.maxPlayerDust + 1, ForgeSystem.maxDust))

	if ForgeSystem.maxPlayerDust >= ForgeSystem.maxDust then
		conversionMenu.windowIncreaseDustLimit.baseText:setText('Maximum Reached')
		conversionMenu.windowIncreaseDustLimit.currentDust:setVisible(false)
		conversionMenu.windowIncreaseDustLimit.img1:setVisible(false)
		conversionMenu.windowIncreaseDustLimit.img2:setVisible(false)
		conversionMenu.windowIncreaseDustLimit.nextDust:setVisible(false)
	else
		conversionMenu.windowIncreaseDustLimit.baseText:setText('Raise limit from')
		conversionMenu.windowIncreaseDustLimit.currentDust:setVisible(true)
		conversionMenu.windowIncreaseDustLimit.img1:setVisible(true)
		conversionMenu.windowIncreaseDustLimit.img2:setVisible(true)
		conversionMenu.windowIncreaseDustLimit.nextDust:setVisible(true)
	end

	conversionMenu.windowIncreaseDustLimit.increaseButton:setEnabled(dust >= totalDustRequired and ForgeSystem.maxPlayerDust < ForgeSystem.maxDust)
	conversionMenu.windowIncreaseDustLimit.increaseButton.locked:setVisible(not (dust >= totalDustRequired and ForgeSystem.maxPlayerDust < ForgeSystem.maxDust))
end

function ForgeSystem.onForgeHistory(history)
    historyMenu.historyList:destroyChildren()
    local colors = { '#414141', '#484848' }

    for id, info in ipairs(history) do
        local widget = g_ui.createWidget('HistoryForgePanel', historyMenu.historyList)
		local backgroundColor = colors[((id-1) % #colors) + 1]
        widget:setHeight(30)

		if id == 1 then
            widget:setMarginTop(16)
        end
        widget:setBackgroundColor(backgroundColor)
        widget.date:setText(os.date("%Y-%m-%d, %X", info[1]))
        widget.date:setColor("$var-text-cip-color")
        local actionText
        local actionColor
        if info[2] == 0 then
            actionText = 'Fusion'
            actionColor = "$var-text-cip-color"
        elseif info[2] == 1 then
            actionText = 'Transfer'
            actionColor = "$var-text-cip-color"
        else
            actionText = 'Conversion'
            actionColor = "$var-text-cip-color-blue"
        end
        widget.action:setText(actionText)
        widget.action:setColor(actionColor)
        widget.details:setText(info[3])
        widget.details:setColor("$var-text-cip-color")
    end
end
