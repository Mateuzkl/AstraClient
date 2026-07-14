if not Categories then
	Categories = {}
	Categories.__index = Categories

	Categories.categoryTable = {}
	Categories.buttonSize = 20
	Categories.selectButton = nil
	Categories.selectTreeItem = nil
	Categories.name = ''
	Categories.signature = nil
	Categories.widgets = {}
	Categories.renderEvent = nil
	Categories.renderGeneration = 0
end

local function getCategoriesSignature(categories)
	local parts = {}
	for _, category in ipairs(categories or {}) do
		parts[#parts + 1] = table.concat({
			tostring(category.name or ""),
			tostring(category.icon or ""),
			tostring(category.parent or ""),
			tostring(category.description or "")
		}, "\31")
	end
	return table.concat(parts, "\30")
end

function Categories:cancelRender()
	removeEvent(Categories.renderEvent)
	Categories.renderEvent = nil
	Categories.renderGeneration = Categories.renderGeneration + 1
end

function Categories:configure(categories)
	local categoryPanel = StoreWindow.categories
	local signature = getCategoriesSignature(categories)
	if Categories.signature == signature and not Categories.renderEvent and #categoryPanel:getChildren() > 0 then
		return
	end

	Categories:cancelRender()
	local generation = Categories.renderGeneration
	local setupStartedAt = g_clock.millis()
	for i, child in pairs(categoryPanel:getChildren()) do
		child:destroy()
	end
	Categories.widgets = {}
	Categories.selectTreeItem = nil

	Categories.categoryTable = {
		[0] = {name = "Home", icon = "/images/store/icon-store-home"},
	}

	local createdCategories = {Home = true}
	local categoryByName = {Home = Categories.categoryTable[0]}

	for _, category in ipairs(categories) do
		if #category.parent == 0 then
			local existing = categoryByName[category.name]
			if existing then
				existing.icon = category.icon
			elseif not createdCategories[category.name] then
				local entry = {name = category.name, icon = category.icon}
				createdCategories[category.name] = true
				categoryByName[category.name] = entry
				Categories.categoryTable[#Categories.categoryTable + 1] = entry
			end
		else
			local parent = categoryByName[category.parent]
			if parent and not createdCategories[category.name] then
				parent.childs = parent.childs or {}
				createdCategories[category.name] = true
				parent.childs[#parent.childs + 1] = {name = category.name, icon = category.icon}
			end
		end
	end

	Categories.categoryTable[#Categories.categoryTable + 1] = {name = "Search", icon = "/images/store/icon-store-search-result", disabled = true}
	Store:profileStep("Categories setup", setupStartedAt)

	local id = 0
	local function renderNextBatch()
		if generation ~= Categories.renderGeneration or categoryPanel:isDestroyed() then
			return
		end

		local batchStartedAt = g_clock.millis()
		local lastId = math.min(id + 2, #Categories.categoryTable)
		while id <= lastId do
			local cat = Categories.categoryTable[id]
			local widget = g_ui.createWidget('TreeItem', categoryPanel)
			widget:setId(id)
			Categories.widgets[id] = widget
			widget.mainButton.text:setText(cat.name)
			if cat.childs and #cat.childs > 0 then
				widget.mainButton.scroll:setVisible(true)
			else
				widget.mainButton.scroll:setHeight(0)
			end

			if cat.disabled then
				widget:setVisible(false)
			end

			if g_resources.fileExists(cat.icon) or table.contains({"Home", "Search"}, cat.name) then
				widget.mainButton.icon:setImageSource(cat.icon)
			else
				local currentWidget = widget.mainButton.icon
				currentWidget.currentImageRequest = Store.currentRequest
				Store.imageRequests[Store.currentRequest] = currentWidget
				Store.currentRequest = Store.currentRequest + 1

				currentWidget:insertLuaCall("onDestroy")
				currentWidget.onDestroy = function()
					Store.imageRequests[currentWidget.currentImageRequest] = nil
				end

				Store:downloadImage(currentWidget.currentImageRequest, "13/"..cat.icon)
			end

			widget.mainButton.onClick = function()
				Categories:onSelectCategory(widget.mainButton)
			end
			id = id + 1
		end

		Store:profileStep("Categories widget batch", batchStartedAt)
		if id <= #Categories.categoryTable then
			Categories.renderEvent = scheduleEvent(renderNextBatch, 1)
			return
		end

		Categories.renderEvent = nil
		Categories.signature = signature
	end

	renderNextBatch()
end


function Categories:onSelectCategory(widget, name)
	if not widget or not widget:getParent() then
		return
	end
	local id = tonumber(widget:getParent():getId())
	local category = Categories.categoryTable[id]
	if not category then
		return
	end

	if Categories.selectTreeItem == widget then
		return true
	end

	if Categories.selectTreeItem and Categories.selectTreeItem:getParent() then
		Categories.selectTreeItem:getParent():setHeight(Categories.buttonSize)
		Categories.selectTreeItem:getParent():getChildById('panel'):setVisible(false)
		Categories.selectTreeItem:getParent():getChildById('panel'):setHeight(0)
		for _, child in pairs(Categories.selectTreeItem:getParent():getChildById('panel'):getChildren()) do
			child:destroy()
		end

		Categories.selectTreeItem = nil
	end

	local printed = false
	local selectedButton = nil
	local isFirstButton = true

	local thisParent = widget:getParent()
	if category.childs and thisParent then
		thisParent:setHeight(Categories.buttonSize+(#category.childs*Categories.buttonSize))
		if #category.childs < 3 then
			thisParent:getChildById('panel'):setHeight((#category.childs*Categories.buttonSize) + 2)
		else
			thisParent:getChildById('panel'):setHeight((#category.childs*Categories.buttonSize) + 1)
		end
		thisParent:getChildById('panel'):setVisible(true)
		thisParent:getChildById('arrow'):setVisible(true)

		for index, child in ipairs(category.childs) do
			local newWidget = g_ui.createWidget('TreeButton', widget:getParent():getChildById('panel'))
			local widgetId = 'TreeButton' .. tostring(index)
			newWidget:setId(widgetId)

			local currentWidget = newWidget.icon
			currentWidget.currentImageRequest = Store.currentRequest
			Store.imageRequests[Store.currentRequest] = currentWidget
			Store.currentRequest = Store.currentRequest + 1

			currentWidget:insertLuaCall("onDestroy")
			currentWidget.onDestroy = function()
				Store.imageRequests[currentWidget.currentImageRequest] = nil
			end

			Store:downloadImage(currentWidget.currentImageRequest, "13/"..child.icon)

			local pos = (index - 1) * 20 + (Categories.buttonSize / 3)
			if not name and not printed then
				printed = true
				thisParent.arrow:setMarginTop(pos)
			end

			newWidget.onClick = function()
				if selectedButton == newWidget then
					return true
				end

				if selectedButton then
					selectedButton:setOn(false)
					selectedButton.text:setColor("$var-text-cip-color")
				end
				selectedButton = newWidget
				selectedButton:setOn(true)
				selectedButton.text:setColor("$var-text-cip-color-highlight")
				thisParent.arrow:setMarginTop(pos)
				g_game.requestStoreOffers(OPEN_CATEGORY, child.name, 0)
			end
			newWidget:getChildById('text'):setText(short_text(child.name, 16))
			if isFirstButton then
				isFirstButton = false
				selectedButton = newWidget
				selectedButton:setOn(true)
				selectedButton.text:setColor("$var-text-cip-color-highlight")
			end
		end
	elseif widget then
		widget.scroll:setHeight(0)
	end

	if not name then
		g_game.doThing(false)
		if category.name == "Home" then
			g_game.requestStoreOffers(OPEN_HOME, "", 0)
		elseif category.childs and #category.childs > 0 then
			g_game.requestStoreOffers(OPEN_CATEGORY, category.childs[1].name, 0)
		else
			g_game.requestStoreOffers(OPEN_CATEGORY, category.name, 0)
		end
		g_game.doThing(true)
	end
	Categories.selectTreeItem = widget
	Categories.name = name
end

function Categories:setupSearch(disabled)
	Categories.categoryTable[#Categories.categoryTable].disabled = disabled
	local searchWidget = Categories.widgets[#Categories.categoryTable]
	if searchWidget and not searchWidget:isDestroyed() then
		searchWidget:setVisible(not disabled)
	end
end

function Categories:reset()
	Categories:cancelRender()
	Categories.signature = nil
	Categories.widgets = {}
	Categories.selectButton = nil
	Categories.selectTreeItem = nil
	Categories.name = ''
end
