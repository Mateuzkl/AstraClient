Titles = {}
Titles.__index = Titles

local TitlesWindow = nil
local optionsBox = nil

local lastSelectedIndex = 0
local currentTitleId = 0
local currentTitleEnabled = false
local currentTitleList = {}

local checkImages = {
	[true] = "/game_cyclopedia/images/ui/check",
	[false] = "/images/store/icon-no",
}

function Titles.terminatePanel()
	if optionsBox then
		optionsBox:destroy()
		optionsBox = nil
	end
	TitlesWindow = nil
end

function Titles.initPanel()
	windowPanel = VisibleCyclopediaPanel:recursiveGetChildById("windowPanel")
	TitlesWindow = g_ui.createWidget('CharacterTitles', windowPanel)
	TitlesWindow:setId("CharacterTitles")
	windowPanel:setImageSource("")

	currentTitleId = 0
	lastSelectedIndex = 0
	currentTitleEnabled = false
	currentTitleLisr = {}

	if optionsBox then
		optionsBox:destroy()
	end

	optionsBox = UIRadioGroup.create()
	optionsBox:addWidget(TitlesWindow:recursiveGetChildById("allBox"))
	optionsBox:addWidget(TitlesWindow:recursiveGetChildById("permanentBox"))
	optionsBox:addWidget(TitlesWindow:recursiveGetChildById("temporaryBox"))
	optionsBox:addWidget(TitlesWindow:recursiveGetChildById("unlockedBox"))
	optionsBox:addWidget(TitlesWindow:recursiveGetChildById("lockedBox"))

	optionsBox:selectWidget(TitlesWindow:recursiveGetChildById("allBox"))
	optionsBox.onSelectionChange = function(_, widget) Titles.show(widget) end
end

function Titles.parseData(currentTitle, list)
	currentTitleId = currentTitle
	currentTitleList = list
	table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
	Titles.show()
end

function Titles.show(selectedOption)
	if not TitlesWindow or TitlesWindow:isDestroyed() then
		return true
	end
	local listPanel = TitlesWindow:recursiveGetChildById("titleListContainer")
	if not listPanel or not TitlesWindow:isVisible() then
		return true
	end

	local currentTitleName = "(No character title selected)"
	local filterOptionId = "allBox"

	if selectedOption then
		filterOptionId = selectedOption:getId()
	end

	local function checkFilter(filter, data)
		if filter == "permanentBox" and not data.permanent then
			return false
		elseif filter == "temporaryBox" and data.permanent then
			return false
		elseif filter == "unlockedBox" and not data.unlocked then
			return false
		elseif filter == "lockedBox" and data.unlocked then
			return false
		end
		return true
	end

	listPanel:destroyChildren()

	local searchField = TitlesWindow:recursiveGetChildById("searchText")
	local searchText = searchField:getText()

	for i, data in pairs(currentTitleList) do
		if type(data) ~= "table" or not checkFilter(filterOptionId, data) then
			goto continue
		end

		if not string.empty(searchText) and not matchText(searchText, data.name) then
			goto continue
		end

		local widget = g_ui.createWidget("TitleLabel", listPanel)
		widget:setBackgroundColor(i % 2 == 0 and "#484848" or "#414141")
		widget.titleData = data

		local nameWidget = widget:recursiveGetChildById("name")
		local descriptionWidget = widget:recursiveGetChildById("description")
		local permanentWidget = widget:recursiveGetChildById("permanent")
		local unlockedWidget = widget:recursiveGetChildById("unlocked")

		nameWidget:setText(data.name)
		descriptionWidget:setTooltip(data.description)
		descriptionWidget:setVisible(false)
		
		permanentWidget:setImageSource(checkImages[data.permanent])
		unlockedWidget:setImageSource(checkImages[data.unlocked])
		if data.id == currentTitleId then
			nameWidget:setColor("#ff9854")
			currentTitleName = data.name
			currentTitleEnabled = data.unlocked
		end

		:: continue ::
	end

	listPanel.onChildFocusChange = Titles.selectTitle

	if lastSelectedIndex ~= 0 and listPanel:getChildCount() >= lastSelectedIndex then
		listPanel:focusChild(listPanel:getChildByIndex(lastSelectedIndex))
	end

	if selectedOption then
		return true
	end

	local titleLabel = TitlesWindow:recursiveGetChildById("titleLabel")
	local removeTitle = TitlesWindow:recursiveGetChildById("removeTitle")
	local infoCircle = TitlesWindow:recursiveGetChildById("info")

	local titleColor = "#f4f4f4"
	if currentTitleId > 0 and not currentTitleEnabled then
		titleColor = "#909090"
	end

	titleLabel:setText(currentTitleName)
	titleLabel:setColor(titleColor)
	removeTitle:setVisible(currentTitleId > 0)
	infoCircle:setVisible(currentTitleId > 0 and not currentTitleEnabled)

	local characterTitle = (currentTitleId > 0 and currentTitleEnabled) and currentTitleName or ""
	VisibleCyclopediaPanel.outfitWindow.titleLabel:setText(characterTitle)
end

function Titles.selectTitle(list, selected, oldSelection)
	if oldSelection then
		local nameWidget = oldSelection:recursiveGetChildById("name")
		local descriptionWidget = oldSelection:recursiveGetChildById("description")
		local editButton = oldSelection:recursiveGetChildById("editButton")
		local textColor = currentTitleId == oldSelection.titleData.id and "#ff9854" or "#c0c0c0"

		nameWidget:setColor(textColor)
		editButton:setVisible(false)
		descriptionWidget:setVisible(false)
		oldSelection:setBackgroundColor(list:getChildIndex(oldSelection) % 2 == 0 and "#484848" or "#414141")
	end

	local nameWidget = selected:recursiveGetChildById("name")
	local descriptionWidget = selected:recursiveGetChildById("description")
	local editButton = selected:recursiveGetChildById("editButton")

	local textColor = currentTitleId == selected.titleData.id and "#ff9854" or "#f4f4f4"
	local buttonEnabled = (not selected.titleData.permanent or selected.titleData.unlocked)

	nameWidget:setColor(textColor)
	descriptionWidget:setVisible(true)
	selected:setBackgroundColor("#585858")
	editButton:setVisible(buttonEnabled)

	lastSelectedIndex = list:getChildIndex(selected)
end

function Titles.onEditTitle()
	local listPanel = TitlesWindow:recursiveGetChildById("titleListContainer")
	if not listPanel or not TitlesWindow:isVisible() then
		return true
	end

	local focusedChild = listPanel:getFocusedChild()
	if not focusedChild then
		return true
	end

	local titleData = focusedChild.titleData
	local equippedTitle = titleData.id == currentTitleId

	local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)
	if equippedTitle then
    	menu:addOption("Remove current character title", function()
			if currentTitleEnabled then
				g_game.updateCharacterTitle(0)
			end

			currentTitleId = 0
			currentTitleEnabled = false
			Titles.show()
	 	end)
	else
		menu:addOption("Set as character title", function()
			if titleData.unlocked then
				g_game.updateCharacterTitle(titleData.id)
			end
			
			currentTitleId = titleData.id
			Titles.show()
	 	end)
	end

    menu:display(mousePos)
end

function Titles.onRemoveTitle()
	g_game.updateCharacterTitle(0)
end

function Titles.onSearchTextChange()
	Titles.show()
end

function Titles.onClearText(widget)
	local textField = widget:getParent()
	if not string.empty(textField:getText()) then
		textField:clearText()
	end
end
