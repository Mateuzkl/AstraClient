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

local CATEGORIES_SHEET = '/images/store/categories'
local categoryIconClips = {
	store_equipment = 1,
	store_weapons = 1,
	store_houses = 2,
	store_consumables = 6,
	store_backpacks = 6,
	store_services = 7,
	store_blessings = 8,
	store_prey = 9,
	xp_boost = 9,
	prey_wildcard = 9,
	store_potions = 10,
	store_mounts = 14,
	store_outfits = 15,
	store_extras = 16,
	store_premium = 20,
	store_cosmetics = 21,
	store_furniture = 22,
	store_beds = 22,
	store_decorations = 23,
	store_upgrades = 2,
}

local function resolveCategoryIconClip(icon, name)
	local key = tostring(icon or ''):lower():gsub('%.png$', '')
	if categoryIconClips[key] then
		return categoryIconClips[key]
	end

	local label = tostring(name or ''):lower()
	if label:find('premium', 1, true) or label:find('battle pass', 1, true) then
		return categoryIconClips.store_premium
	elseif label:find('boost', 1, true) then
		return categoryIconClips.xp_boost
	elseif label:find('consumable', 1, true) then
		return categoryIconClips.store_consumables
	elseif label:find('potion', 1, true) then
		return categoryIconClips.store_potions
	elseif label:find('bless', 1, true) then
		return categoryIconClips.store_blessings
	elseif label:find('prey', 1, true) then
		return categoryIconClips.store_prey
	elseif label:find('weapon', 1, true) then
		return categoryIconClips.store_weapons
	elseif label:find('backpack', 1, true) or label:find('container', 1, true) then
		return categoryIconClips.store_backpacks
	elseif label:find('equipment', 1, true) then
		return categoryIconClips.store_equipment
	elseif label:find('outfit', 1, true) then
		return categoryIconClips.store_outfits
	elseif label:find('mount', 1, true) then
		return categoryIconClips.store_mounts
	elseif label:find('cosmetic', 1, true) then
		return categoryIconClips.store_cosmetics
	elseif label:find('upgrade', 1, true) then
		return categoryIconClips.store_upgrades
	elseif label:find('bed', 1, true) then
		return categoryIconClips.store_beds
	elseif label:find('furniture', 1, true) then
		return categoryIconClips.store_furniture
	elseif label:find('decoration', 1, true) or label:find('decor', 1, true) then
		return categoryIconClips.store_decorations
	elseif label:find('house', 1, true) then
		return categoryIconClips.store_houses
	elseif label:find('extra', 1, true) or label:find('service', 1, true) then
		return categoryIconClips.store_extras
	end

	if key:find('house', 1, true) or key:find('upgrade', 1, true) then
		return categoryIconClips.store_houses
	end
	if key:find('bed', 1, true) then
		return categoryIconClips.store_beds
	end
	if key:find('decor', 1, true) or key:find('furniture', 1, true) or key:find('category_', 1, true) then
		return categoryIconClips.store_furniture
	end

	return nil
end

local function applyCategoryIcon(iconWidget, icon, name)
	if not iconWidget then
		return
	end

	iconWidget:setImageClip('0 0 13 13')

	if name == 'Home' then
		iconWidget:setImageSource('/images/store/icon-store-home')
		return
	end
	if name == 'Search' then
		iconWidget:setImageSource('/images/store/icon-store-search-result')
		return
	end

	local label = tostring(name or ''):lower()
	if label:find('boost', 1, true) then
		iconWidget:setImageSource('/images/icons/xp_boost')
		return
	end

	local clipId = resolveCategoryIconClip(icon, name)
	if clipId then
		iconWidget:setImageSource(CATEGORIES_SHEET)
		iconWidget:setImageClip(string.format('%d 0 13 13', clipId * 13))
		return
	end

	local iconPath = tostring(icon or '')
	if iconPath ~= '' and (g_resources.fileExists(iconPath) or g_resources.fileExists('/images/store/' .. iconPath) or g_resources.fileExists('/images/store/' .. iconPath .. '.png')) then
		if not iconPath:find('/', 1, true) then
			iconPath = '/images/store/' .. iconPath:gsub('%.png$', '')
		end
		iconWidget:setImageSource(iconPath)
		return
	end

	iconWidget:setImageSource(CATEGORIES_SHEET)
	iconWidget:setImageClip(string.format('%d 0 13 13', 13))
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

			applyCategoryIcon(widget.mainButton.icon, cat.icon, cat.name)

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

			applyCategoryIcon(newWidget.icon, child.icon, child.name)

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
