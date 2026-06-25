---------------------------
-- Lua code author: R1ck --
-- Company: VICTOR HUGO PERENHA - JOGOS ON LINE  --
---------------------------

Workshop = {}
Workshop.__index = Workshop

fragmentList = {}
currentWorkshopPage = 1

function Workshop.getFragmentList()
	return fragmentList
end

function Workshop.setCurrentPage(index)
	currentWorkshopPage = index
end

function Workshop.getDataByBonus(bonusID, supreme)
	for _, data in pairs(fragmentList) do
		if (supreme and data.supreme and bonusID == data.modID) or (not supreme and not data.supreme and bonusID == data.modID) then
			return data
		end
	end
	return nil
end

function Workshop.createFragments()
	local player = g_game.getLocalPlayer()
	if not player then
		return true
	end

	local vocationId = translateVocation(player:getVocation())

	fragmentList = {}
	for id = 0, #FlatSupremeMods do
		local info = FlatSupremeMods[id]
		if info then
			if id == 4 and vocationId > 6 then
				goto continue
			end

			info.modID = id
			info.supreme = true
			table.insert(fragmentList, info)
			::continue::
		end
	end

	local vocationMods = VocationSupremeMods[vocationId]
	local vocationIDRanges = {
		[8] = { fromID = 6, toID = 24 },
		[7] = { fromID = 23, toID = 41 },
		[5] = { fromID = 42, toID = 58 },
		[6] = { fromID = 59, toID = 75 },
		[9] = { fromID = 76, toID = 93 }
	}

	local idRange = vocationIDRanges[vocationId]
	if idRange then
		for id = idRange.fromID, idRange.toID do
			local info = vocationMods[id]
			if info then
				info.modID = id
				info.supreme = true
				table.insert(fragmentList, info)
			end
		end
	end

	-- BasicMods tem buracos (32/42/43); #BasicMods é indefinido e pode truncar a lista.
	-- Itera o range fixo do enum (0..48) e deixa o guard `if info` pular os buracos.
	for id = 0, 48 do
		local info = BasicMods[id]
		if info then
			info.modID = id
			info.supreme = false
			table.insert(fragmentList, info)
		end
	end
end

function Workshop.showFragmentList(startUp, nextPage, selectCurrent, searchText, focusIndex)
	if not fragmentWindow then
		return true
	end

	local fragmentPanel = fragmentWindow:recursiveGetChildById('fragmentContent')
	if not fragmentPanel then
		return true
	end

	-- Track the selection by mod identity (modID + supreme), NOT by widget: the 30
	-- grid slots are reused, and a re-render (e.g. the post-Enhance refresh that resets
	-- the sort to "All") can leave a different mod in the previously-focused slot, so the
	-- detail panel would render the wrong mod. Re-resolve the matching widget after render.
	local lastSelectedKey = nil
	if selectCurrent then
		local focused = fragmentPanel:getFocusedChild()
		if focused and focused.cache then
			lastSelectedKey = { modID = focused.cache.modID, supreme = focused.cache.supreme }
		end
	end

	local currentModList = fragmentList
	local equippedBasic, equippedSupreme = Workshop.getEquippedGemBonus()
	local sortBox = fragmentWindow:recursiveGetChildById('affinitiesBox')
	local maxPages = math.ceil(#currentModList / 30)
	local modCount = #currentModList

	if startUp then
		fragmentWindow:recursiveGetChildById('searchText'):clearText(true)
		sortBox:setCurrentOption("All", false)
	end

	if sortBox:getCurrentOption().text ~= "All" then
		currentModList = Workshop.getSortList(sortBox:getCurrentOption(), equippedBasic, equippedSupreme, searchText)
		maxPages = math.ceil(#currentModList / 30)
		modCount = #currentModList
		if currentWorkshopPage > maxPages then
			currentWorkshopPage = maxPages
		end
	elseif searchText and not string.empty(searchText) then
		currentModList = Workshop.searchModifications(searchText)
		maxPages = math.ceil(#currentModList / 30)
		modCount = #currentModList
		if currentWorkshopPage > maxPages then
			currentWorkshopPage = maxPages
		end
	end

	if not startUp and not focusIndex then
		currentWorkshopPage = nextPage and math.min(maxPages, currentWorkshopPage + 1) or math.max(1, currentWorkshopPage - 1)
	end

	local beginList = (currentWorkshopPage - 1) * 30 + 1
	local endList = math.min(beginList + 29, #currentModList)

	local function updateWidget(widget, info, equipped, count)
		local basicMod = widget:recursiveGetChildById('basicMod')
		local supremeMod = widget:recursiveGetChildById('supremeMod')
		local amount = widget:recursiveGetChildById('amountLabel')
		local modTierWidget = widget:recursiveGetChildById('fragmentType')
		local socketed = widget:recursiveGetChildById('socketed')

		widget.cache = info
		socketed:setVisible(false)
		widget:setVisible(true)
		amount:setVisible(false)
		amount:setText("x 0")
		modTierWidget:setImageClip("0 0 50 50")

		if info.supreme then
			basicMod:setVisible(false)
			supremeMod:setVisible(true)
			supremeMod:setImageClip(info.modID * 35 .. " 0 35 35")
			supremeMod:setTooltip(Workshop.getBonusDescription(info))
			local supremeTier = WheelOfDestiny.supremeModsUpgrade[info.modID]
			if supremeTier then
				modTierWidget:setImageClip(supremeTier * 50 .. " 0 50 50")
			end

			if equipped[tostring(info.modID)] then
				socketed:setVisible(true)
			end
		else
			basicMod:setVisible(true)
			supremeMod:setVisible(false)
			basicMod:setImageClip(info.modID * 30 .. " 0 30 30")
			basicMod:setTooltip(Workshop.getBonusDescription(info))
			local basicTier = WheelOfDestiny.basicModsUpgrade[info.modID]
			if basicTier then
				modTierWidget:setImageClip(basicTier * 50 .. " 0 50 50")
			end

			if equipped[tostring(info.modID)] then
				socketed:setVisible(true)
			end
		end

		if count > 0 then
			amount:setText(tr("x %s", count))
			amount:setVisible(true)
			amount:setTooltip(tr(amount:getTooltip(), count))
		end
	end

	for i, widget in ipairs(fragmentPanel:getChildren()) do
		widget:setVisible(false)
		local k = beginList + (i - 1)
		if k <= endList then
			local info = currentModList[k]
			if info then
				local isSupreme = info.supreme
				local count = isSupreme and (WheelOfDestiny.supremeModCount[tostring(info.modID)] or 0) or (WheelOfDestiny.basicModCount[tostring(info.modID)] or 0)
				updateWidget(widget, info, isSupreme and equippedSupreme or equippedBasic, count)
			end
		end
	end

	local infoLabel = fragmentWindow:recursiveGetChildById('pagesLabel')
	if infoLabel then
		infoLabel:setText(tr("Page %s / %s (%s Mods)", currentWorkshopPage, math.max(1, maxPages), modCount))
	end

	local previousPage = fragmentWindow:recursiveGetChildById('rightArrow')
	local nextPage = fragmentWindow:recursiveGetChildById('leftArrow')
	local modGradePanel = fragmentWindow:recursiveGetChildById('modGrade')
	local noModGradePanel = fragmentWindow:recursiveGetChildById('noModGrade')

	modGradePanel:setVisible(#currentModList > 0)
	noModGradePanel:setVisible(#currentModList == 0)

	if previousPage and nextPage then
		if (currentWorkshopPage == maxPages and maxPages == 1) or #currentModList == 0 then
			previousPage:setEnabled(false)
			nextPage:setEnabled(false)
		elseif currentWorkshopPage <= 1 then
			previousPage:setEnabled(false)
			nextPage:setEnabled(true)
		elseif currentWorkshopPage > 1 and currentWorkshopPage < maxPages then
			previousPage:setEnabled(true)
			nextPage:setEnabled(true)
		elseif currentWorkshopPage == maxPages then
			previousPage:setEnabled(true)
			nextPage:setEnabled(false)
		end
	end

	fragmentPanel.onChildFocusChange = Workshop.onSelectChild
	if focusIndex then
		fragmentPanel:focusChild(fragmentPanel:getChildByIndex(focusIndex))
	elseif selectCurrent then
		local target = nil
		if lastSelectedKey then
			for _, w in ipairs(fragmentPanel:getChildren()) do
				if w:isVisible() and w.cache and w.cache.modID == lastSelectedKey.modID and w.cache.supreme == lastSelectedKey.supreme then
					target = w
					break
				end
			end
		end
		if not target then
			target = fragmentPanel:getFirstChild()
		end
		-- Clear any focus the setVisible(false) churn left on a wrong slot, then
		-- focus the correct mod so the detail panel renders it (not a stale neighbour).
		fragmentPanel:focusChild(nil)
		fragmentPanel:focusChild(target)
		Workshop.onSelectChild(nil, target)
	else
		fragmentPanel:focusChild(nil)
		fragmentPanel:focusChild(fragmentPanel:getFirstChild())
	end
end

function Workshop.onSelectChild(list, selected)
    if not selected then
        return true
    end

    local isSupreme = selected.cache.supreme
    local supremeTier = WheelOfDestiny.supremeModsUpgrade[selected.cache.modID] or 0
    local basicTier = WheelOfDestiny.basicModsUpgrade[selected.cache.modID] or 0
    local maxTier = isSupreme and supremeTier or basicTier
    local modID = selected.cache.modID
    local imageClipSize = isSupreme and 35 or 30
    local activeColor = "$var-text-cip-color"
    local inactiveColor = "$var-cip-inactive-color"
	local modDesc = fragmentWindow:recursiveGetChildById("modDesc")

    for i = 0, 3 do
		local basicWidget = fragmentWindow:recursiveGetChildById("basicMod" .. i)
        local supremeWidget = fragmentWindow:recursiveGetChildById("supremeMod" .. i)

        local gradeWidget = fragmentWindow:recursiveGetChildById("grade" .. i)
        local bonusWidget = fragmentWindow:recursiveGetChildById("bonus" .. i)
        local backDrop = fragmentWindow:recursiveGetChildById("fragmentType" .. i)
        local backMidle = fragmentWindow:recursiveGetChildById("modBgAnim" .. i)
        local backLine = fragmentWindow:recursiveGetChildById("lineAnim" .. i)
        -- The static ring/line backdrops are baked green; without this they look
        -- "active" on every tier and hide whether the grade is actually unlocked.
        local backCircle = fragmentWindow:recursiveGetChildById("modBg" .. i)
        local backStaticLine = fragmentWindow:recursiveGetChildById("bgLine" .. i)

		local isActive = maxTier >= i
		if isSupreme then
			basicWidget:setVisible(false)
			supremeWidget:setVisible(true)
			supremeWidget:setImageClip(modID * imageClipSize .. " 0 " .. imageClipSize .. " " .. imageClipSize)
			supremeWidget:setImageShader(isActive and '' or 'image_black_white')
		else
			supremeWidget:setVisible(false)
			basicWidget:setVisible(true)
			basicWidget:setImageClip(modID * imageClipSize .. " 0 " .. imageClipSize .. " " .. imageClipSize)
			basicWidget:setImageShader(isActive and '' or 'image_black_white')
		end

        backDrop:setImageShader(isActive and '' or 'image_black_white')
        gradeWidget:setColor(isActive and activeColor or inactiveColor)
        bonusWidget:setColor(isActive and activeColor or inactiveColor)
        backMidle:setVisible(isActive)
        if backCircle then
            backCircle:setImageShader(isActive and '' or 'image_black_white')
        end
        if backStaticLine then
            backStaticLine:setImageShader(isActive and '' or 'image_black_white')
        end
        if backLine then
            backLine:setVisible(isActive)
        end

        bonusWidget:setText(Workshop.getSideBonusDescription(selected.cache, i))
    end

    local fragmentWidget = fragmentWindow:recursiveGetChildById("fragmentCost")
    local fragmentIcon = fragmentWindow:recursiveGetChildById("fragmentIcon")
    local goldWidget = fragmentWindow:recursiveGetChildById("gold")
    local enhanceButton = fragmentWindow:recursiveGetChildById("enhanceButton")

    if maxTier >= 3 then
        fragmentIcon:getParent():setVisible(false)
        goldWidget:getParent():setVisible(false)
        enhanceButton:setVisible(false)
        return true
    end

    local player = g_game.getLocalPlayer()
    local goldCost = isSupreme and greaterResources[supremeTier].price or lesserResources[basicTier].price
    local fragmentCost = isSupreme and greaterResources[supremeTier].fragment or lesserResources[basicTier].fragment
    local resourceCheck = isSupreme and player:getResourceValue(ResourceGreaterFragment) or player:getResourceValue(ResourceLesserFragment)
    local iconOffset = isSupreme and "0 12 12 12" or "0 0 12 12"
    local iconTooltip = isSupreme and "Greater Fragments" or "Lesser Fragments"

    setMoneyAutoFit(goldWidget, goldCost, 44)
    goldWidget:setTooltip(comma_value(goldCost))
    fragmentWidget:setText(fragmentCost)
    fragmentIcon:setImageClip(iconOffset)
    fragmentIcon:setTooltip(iconTooltip)

    fragmentIcon:getParent():setVisible(true)
    goldWidget:getParent():setVisible(true)
    goldWidget:setOn(true)
    enhanceButton:setVisible(true)
    fragmentWidget:setOn(true)

    local blockedTooltip = ""
    local totalBalance = player:getResourceValue(ResourceBank) + player:getResourceValue(ResourceInventary)
    if totalBalance < goldCost then
        blockedTooltip = tr("You need at least %s gold to enhance mods of this quality.", comma_value(goldCost))
        goldWidget:setOn(false)
    end

    if resourceCheck < fragmentCost then
        if not string.empty(blockedTooltip) then
            blockedTooltip = tr("%s\nYou need at least %s greater fragments to enhance mods of this quality.", blockedTooltip, fragmentCost)
        else
            blockedTooltip = tr("You need at least %s greater fragments to enhance mods of this quality.", fragmentCost)
        end
        fragmentWidget:setOn(false)
    end

    enhanceButton:setTooltip(blockedTooltip)
	enhanceButton:setOn(string.empty(blockedTooltip))
	modDesc:setText(selected.cache.desc or "")
end

function Workshop.onUpgradeModification(button)
	local selected = fragmentWindow:recursiveGetChildById('fragmentContent')
	if not selected or not button:isOn() then
		return true
	end

	local selectedWidget = selected:getFocusedChild()
	if not selectedWidget then
		return true
	end
	-- ImproveGrade: fragment type (Greater=0 for supreme mods, Lesser=1 for basic mods) + mod position
	g_game.sendGemAtelierAction(4, selectedWidget.cache.supreme and 0 or 1, selectedWidget.cache.modID)
end

function Workshop.getBonusDescription(modInfo, relativeTier)
	local description = ""
	if modInfo.desc and modInfo.showDesc then
		description = tr("%s\n", modInfo.desc)
	end

	local targetTier = modInfo.supreme and WheelOfDestiny.supremeModsUpgrade[modInfo.modID] or WheelOfDestiny.basicModsUpgrade[modInfo.modID]
	if relativeTier then
		targetTier = relativeTier
	end

	local step = bonusStep[WheelOfDestiny.vocationId]

	local function getStepBonus(baseStep, stepType)
		if modInfo.type and modInfo.type == "cooldown" then
			if not targetTier or targetTier == 0 then
				return 0
			end

			local specialValue = modInfo.baseII + (modInfo.baseII * (targetTier - 1))
			return (targetTier == 3 and math.round(specialValue) or specialValue)
		elseif not stepType then
			return Workshop.getUpgradeBonus(baseStep, modInfo.modID, modInfo.supreme, relativeTier)
		elseif stepType == "mana" then
			return Workshop.getUpgradeBonus(modInfo.baseStepI * step.mana, modInfo.modID, modInfo.supreme, relativeTier)
		elseif stepType == "health" then
			return Workshop.getUpgradeBonus(modInfo.baseStepI * step.life, modInfo.modID, modInfo.supreme, relativeTier)
		elseif stepType == "capacity" then
			return Workshop.getUpgradeBonus(modInfo.baseStepI * step.capacity, modInfo.modID, modInfo.supreme, relativeTier)
		else
			return Workshop.getUpgradeBonus(baseStep, modInfo.modID, modInfo.supreme, relativeTier)
		end
	end

	local bonusI = getStepBonus(modInfo.baseI, modInfo.stepTypeI)
	local bonusII = modInfo.baseII and getStepBonus(modInfo.baseII, modInfo.stepTypeII)

	local function processTooltip(bonusI, bonusII)
		if modInfo.type == "cooldown" then
			if targetTier == 0 then
				local str = modInfo.tooltip
				local result = str:gsub("\n.*", "")
				return result
			end
			return tr(modInfo.tooltip, bonusII)
		end

		if bonusII then
			return tr(modInfo.tooltip, bonusI, bonusII)
		end
		return tr(modInfo.tooltip, bonusI)
	end
	description = description .. processTooltip(bonusI, bonusII)
	return description
end

function Workshop.getSideBonusDescription(data, targetTier)
	local description = ""
	local step = bonusStep[WheelOfDestiny.vocationId]

	local function calculateSpecialValue(baseII, targetTier)
		local specialValue = baseII + (baseII * (targetTier - 1))
		if targetTier == 3 then
			specialValue = math.round(specialValue)
		end
		return specialValue
	end

	local function getStepBonus(baseStep, stepType)
		if data.type and data.type == "cooldown" then
			if targetTier == 0 then
				return 0
			end

			local specialValue = data.baseII + (data.baseII * (targetTier - 1))
			if targetTier == 3 then
				specialValue = math.round(specialValue)
			end
			return specialValue
		elseif not stepType then
			return Workshop.getUpgradeBonus(baseStep, data.modID, data.supreme, targetTier)
		elseif stepType == "mana" then
			return Workshop.getUpgradeBonus(data.baseStepI * step.mana, data.modID, data.supreme, targetTier)
		elseif stepType == "health" then
			return Workshop.getUpgradeBonus(data.baseStepI * step.life, data.modID, data.supreme, targetTier)
		elseif stepType == "capacity" then
			return Workshop.getUpgradeBonus(data.baseStepI * step.capacity, data.modID, data.supreme, targetTier)
		else
			return Workshop.getUpgradeBonus(baseStep, data.modID, data.supreme, targetTier)
		end
	end

	local bonusI = getStepBonus(data.baseI, data.stepTypeI)
	local bonusII = data.baseII and getStepBonus(data.baseII, data.stepTypeII)

	local function processTooltip(bonusI, bonusII)
		if data.type == "cooldown" then
			if targetTier == 0 then
				local str = data.tooltip
				local result = str:gsub("\n.*", "")
				return result
			end
			return tr(data.tooltip, bonusII)
		end

		if bonusII then
			return tr(data.tooltip, bonusI, bonusII)
		end
		return tr(data.tooltip, bonusI)
	end
	description = description .. processTooltip(bonusI, bonusII)
	return description
end

function Workshop.getBonusValue(modInfo, targetTier, firstBonus)
	if not modInfo then
		return 0
	end

	local step = bonusStep[WheelOfDestiny.vocationId]
	local function getStepBonus(baseStep, stepType)
		if modInfo.type and modInfo.type == "cooldown" then
			if not targetTier or targetTier == 0 then
				return 0
			end

			local specialValue = modInfo.baseII + (modInfo.baseII * (targetTier - 1))
			return (targetTier == 3 and math.round(specialValue) or specialValue)
		elseif not stepType then
			return Workshop.getUpgradeBonus(baseStep, modInfo.modID, modInfo.supreme, targetTier)
		elseif stepType == "mana" then
			return Workshop.getUpgradeBonus(modInfo.baseStepI * step.mana, modInfo.modID, modInfo.supreme, targetTier)
		elseif stepType == "health" then
			return Workshop.getUpgradeBonus(modInfo.baseStepI * step.life, modInfo.modID, modInfo.supreme, targetTier)
		elseif stepType == "capacity" then
			return Workshop.getUpgradeBonus(modInfo.baseStepI * step.capacity, modInfo.modID, modInfo.supreme, targetTier)
		else
			return Workshop.getUpgradeBonus(baseStep, modInfo.modID, modInfo.supreme, targetTier)
		end
	end

	local bonusI = getStepBonus(modInfo.baseI, modInfo.stepTypeI)
	local bonusII = modInfo.baseII and getStepBonus(modInfo.baseII, modInfo.stepTypeII)
	return firstBonus and bonusI or bonusII
end

function Workshop.getGemInformationByBonus(gemBonusID, supremeMod, gemID, gemSlot)
	local gem = GemAtelier.getGemDataById(gemID)
	if not gem then
		return 0
	end

	local effectiveLevel = GemAtelier.getEffectiveLevel(gem, gemBonusID, supremeMod, gemSlot)
	local modInfo = Workshop.getDataByBonus(gemBonusID, supremeMod)
	if not modInfo then
		return "(Unkown)", 0
	end

	local text = Workshop.getBonusDescription(modInfo, effectiveLevel)
	if text:find("Aug.") then
		text = text:gsub("Aug.", "Augmented")
	end

	local translateText = {[0] = "(I)", [1] = "(II)", [2] = "(III)", [3] = "(IV)"}
	text = text .. " " .. translateText[effectiveLevel]
	return text, effectiveLevel
end

function Workshop.getUpgradeBonus(baseBonus, modID, supreme, targetTier)
    local modTier = targetTier and targetTier or (supreme and WheelOfDestiny.supremeModsUpgrade[modID] or WheelOfDestiny.basicModsUpgrade[modID])
    if not modTier then
        return baseBonus
    end

	if modTier == 3 then
		baseBonus = baseBonus + (baseBonus * 50 / 100)
	else
     	baseBonus = baseBonus + (baseBonus * (10 * modTier) / 100)
	end

	baseBonus = roundToTwoDecimalPlaces(baseBonus)
	return baseBonus
end

function Workshop.getEquippedGemBonus()
	local basicMods = {}
	local supremeMods = {}
	local function emplaceEquippedBonus(bonus, bonusType, gemID)
		if bonus ~= -1 then
			bonusType[tostring(bonus)] = gemID
		end
	end

	for _, id in pairs(WheelOfDestiny.equipedGems) do
		local data = GemAtelier.getGemDataById(id)
		if data then
			emplaceEquippedBonus(data.lesserBonus, basicMods, data.gemID)
			emplaceEquippedBonus(data.regularBonus, basicMods, data.gemID)
			emplaceEquippedBonus(data.supremeBonus, supremeMods, data.gemID)
		end
	end
	return basicMods, supremeMods;
end

function Workshop.getSortList(sortOption, equippedBasic, equippedSupreme, text)
    local tmpList = {}
    local sortText = sortOption.text
	local gradesText = { ["Grade II"] = 1, ["Grade III"] = 2, ["Grade IV"] = 3 }

    for _, data in pairs(fragmentList) do
		if text and not matchText(text, data.tooltip) then
			goto continue
		end

        local modIDStr = tostring(data.modID)
        local grade = nil
		if data.supreme then
			grade = WheelOfDestiny.supremeModsUpgrade[data.modID]
		else
			grade = WheelOfDestiny.basicModsUpgrade[data.modID]
		end

        if sortText == "Basic Mods" and not data.supreme then
            table.insert(tmpList, data)
        elseif sortText == "Supreme Mods" and data.supreme then
            table.insert(tmpList, data)
        elseif sortText == "In-Vessel Mods" then
            if (data.supreme and equippedSupreme[modIDStr]) or (not data.supreme and equippedBasic[modIDStr]) then
                table.insert(tmpList, data)
            end
        elseif sortText == "Grade I" then
            if not grade or grade < 1 then
                table.insert(tmpList, data)
            end
        elseif gradesText[sortText] then
            local gradeLevel = gradesText[sortText]
            if grade and grade == gradeLevel then
                table.insert(tmpList, data)
            end
        end

		:: continue ::
    end
    return tmpList
end

function Workshop.searchModifications(text)
	local tmpList = {}
    for _, data in pairs(fragmentList) do
		if matchText(text, data.tooltip) then
        	table.insert(tmpList, data)
		end
    end
    return tmpList
end

function Workshop.onSearchChange(self)
	local text = self:getText()

	if string.empty(text) then
		Workshop.showFragmentList(true, false, false)
		return true
	end

	if #text > 50 then
		return true
	end
	Workshop.showFragmentList(false, false, false, text)
end
