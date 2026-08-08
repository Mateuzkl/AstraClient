Character = {}
Character.__index = Character

local windowPanel = nil
local lastSelectedItem = nil

local itemSummary = nil
local radioShowType = nil

local Appearances = nil
local radioAppearances = nil
local appearancesList = {}

local RecentDeaths = nil
local RecentPvpKills = nil
local lastSelectedRecentDeath = {}

local inspectItems = {}
local inspectPlayer = {}
local basePlayerData = {}
local combatWidgets = {}

local inventoryList = {}
local storeList = {}
local stashList = {}
local lockerList = {}
local inboxList = {}

local recentDeathPage = 1
local recentDeathMax = 1

local recentPvPPage = 1
local recentPvPMax = 1

local achievementWindow = nil
local achievementsList = {}
local displayAchievements = {}
local achievementRadioGroup = nil

function Character.terminatePanel()
  if achievementRadioGroup then
    achievementRadioGroup:destroy()
    achievementRadioGroup = nil
  end
  if radioAppearances then
    radioAppearances:destroy()
    radioAppearances = nil
  end
  if radioShowType then
    radioShowType:destroy()
    radioShowType = nil
  end

  windowPanel = nil
  lastSelectedItem = nil
  itemSummary = nil
  Appearances = nil
  RecentDeaths = nil
  RecentPvpKills = nil
  achievementWindow = nil
end

local function getAchievementCatalog()
	return ACHIEVEMENTS or {}
end

local SkillNames = {
	[1] = "Magic Level",
	[6] = "Shielding",
	[7] = "Distance",
	[8] = "Sword",
	[9] = "Club",
	[10] = "Axe",
	[11] = "Fist"
}

local items = {
	[1] = {slot = "head", offsettop = 4, offsetleft = 40},
	[2] = {slot = "neck", offsettop = 22, offsetleft = 4},
	[3] = {slot = "back", offsettop = 22, offsetleft = 76},
	[4] = {slot = "body", offsettop = 40, offsetleft = 40},
	[5] = {slot = "right-hand", offsettop = 58, offsetleft = 76},
	[6] = {slot = "left-hand", offsettop = 58, offsetleft = 4},
	[7] = {slot = "legs", offsettop = 76, offsetleft = 40},
	[8] = {slot = "feet", offsettop = 112, offsetleft = 40},
	[9] = {slot = "finger", offsettop = 94, offsetleft = 4},
	[10] = {slot = "ammo", offsettop = 94, offsetleft = 76}
}

local function getWindowPanel()
	if not VisibleCyclopediaPanel or VisibleCyclopediaPanel:isDestroyed() or VisibleCyclopediaPanel:getId() ~= "CharacterDataPanel" then
		windowPanel = nil
		return nil
	end

	windowPanel = VisibleCyclopediaPanel:recursiveGetChildById("windowPanel")
	return windowPanel
end

function Character.loadLocalPlayerData()
	local player = g_game.getLocalPlayer()
	if not player then
		return
	end

	local outfit = player:getOutfit()
	local playerName = player:getName()
	basePlayerData = {
		name = playerName,
		vocation = g_game.getVocationName(player:getVocation()),
		level = player:getLevel(),
		outfit = outfit,
		title = ""
	}
	inspectPlayer = { name = playerName, outfit = outfit, playerData = {} }
	inspectItems = {}

	for slot = InventorySlotFirst, InventorySlotLast do
		local item = player:getInventoryItem(slot)
		if item then
			local itemName = item:getName()
			if not itemName or itemName == "" then
				itemName = getItemServerName(item:getId())
			end
			inspectItems[slot] = {
				item = item,
				itemName = itemName,
				imbuingSlots = {},
				descriptions = {
					{ label = "Description", content = item:getDescription() or "" }
				}
			}
		end
	end
end

function Character.onResourceBalance()
    if not cyclopediaWindow or not cyclopediaWindow:isVisible() then
        return
    end

    local player = g_game.getLocalPlayer()
    local bankMoney = player:getResourceValue(ResourceBank)
    local characterMoney = player:getResourceValue(ResourceInventary)

    local charmBalance = player:getResourceValue(ResourceCharmBalance)
    local echoeBalance = player:getResourceValue(ResourceEchoeBalance)
    local maxCharmBalance = player:getResourceValue(ResourceMaxCharmBalance)
    local maxEchoeBalance = player:getResourceValue(ResourceMaxEchoeBalance)

    cyclopediaWindow:recursiveGetChildById('minorCharmAmount'):setText(echoeBalance.." / "..maxEchoeBalance)
    cyclopediaWindow:recursiveGetChildById('charmAmount'):setText(charmBalance.." / "..maxCharmBalance)
    cyclopediaWindow:recursiveGetChildById('coinsAmount'):setText(comma_value(bankMoney + characterMoney))
end

function Character.initMainWindow()
	if not inspectPlayer.playerData then
		return
	end

	windowPanel = getWindowPanel()
	if not windowPanel then
		return
	end
	
	Character.onResourceBalance()

	if basePlayerData.outfit then
		VisibleCyclopediaPanel.outfitWindow.outfit:setOutfit(basePlayerData.outfit)
	end

	VisibleCyclopediaPanel.outfitWindow.titleLabel:setText(basePlayerData.title)
	VisibleCyclopediaPanel.outfitWindow.nameLabel:setText(basePlayerData.name)
	VisibleCyclopediaPanel.outfitWindow.vocLabel:setText(basePlayerData.vocation)
	VisibleCyclopediaPanel.outfitWindow.levelLabel:setText("Level " .. (basePlayerData.level and basePlayerData.level or 0))

	windowPanel.itemInfor:destroyChildren()
	windowPanel.itemsPanel:destroyChildren()
	local buttonsWindow = g_ui.getRootWidget():recursiveGetChildById('buttonsWindow')
	if not buttonsWindow then
		return
	end
	buttonsWindow.buttonPanel:destroyChildren()

	for _, data in pairs(inspectPlayer.playerData) do
		local widget = g_ui.createWidget("InspectLabel", windowPanel.itemInfor)
		widget.label:setText(data.detail .. ":")
		widget.content:setText(data.description)

		if widget.content:isTextWraped() then
			local wrappedLines = widget.content:getWrappedLinesCount()
			if wrappedLines == 1 then
				widget:setSize(tosize("270 " .. 19 * (wrappedLines + 1)))
			else
				widget:setSize(tosize("270 " .. 21 * (wrappedLines)))
			end
		end
	end

	for k, v in ipairs(items) do
		local slot = g_ui.createWidget('SlotItems', windowPanel.itemsPanel)
		slot:setId(k)
		slot:setMarginTop(v.offsettop)
		slot:setMarginLeft(v.offsetleft)
		slot:setImageSource("/images/game/slots/"..v.slot)
		local slotItem = inspectItems[k]
		if slotItem then
			slot:setImageSource("/data/images/ui/item")
			slot.item:setItem(slotItem.item)
		end
	end

	-- create buttons
	local buttonNames = {"General Stats","Battle Results","Achievements","Item Summary","Appearances","Character Titles"}
	for k, v in pairs(buttonNames) do
		buttonspack[k] = "off"
		local SlotPanel = g_ui.createWidget('OptionsPanel', buttonsWindow.buttonPanel)
		SlotPanel.buttons:setIcon("/game_cyclopedia/images/ui/icon/icon-character-"..k)
		SlotPanel.buttons:setText(v)
		SlotPanel:setId('button'.. k)

		if k <= 2 then
			SlotPanel.buttons.arrowRef:setVisible(true)
			local SlotPanel = g_ui.createWidget('ButtonExtraPanel', SlotPanel)
			SlotPanel:addAnchor(AnchorTop, 'prev', AnchorBottom)
		end

		if k >= 2 then
			SlotPanel:addAnchor(AnchorTop, 'prev', AnchorBottom)
			SlotPanel:setMarginTop(10)
		end

		SlotPanel.buttons.onClick = function()
			modules.game_cyclopedia.Character.onChangeCharacterPanel(k)
		end
	end
end

function Character.onChangeCharacterPanel(buttonId)
	local button1 = g_ui.getRootWidget():recursiveGetChildById('button1')
	local button2 = g_ui.getRootWidget():recursiveGetChildById('button2')
	local button3 = g_ui.getRootWidget():recursiveGetChildById('button3')
	local button4 = g_ui.getRootWidget():recursiveGetChildById('button4')
	local button5 = g_ui.getRootWidget():recursiveGetChildById('button5')
	local button6 = g_ui.getRootWidget():recursiveGetChildById('button6')
	local buttons = {button1, button2, button3, button4, button5, button6}

	for i, btn in ipairs(buttons) do
		btn.buttons:setOn(false)
		btn:setHeight(22)
		buttonspack[i] = "off"
		button1.buttons.arrowRef:setVisible(true)
		button2.buttons.arrowRef:setVisible(true)
		button1.ButtonExtraPanel.buttonsExtra1:setVisible(false)
		button1.ButtonExtraPanel.buttonsExtra2:setVisible(false)
		button2.ButtonExtraPanel.buttonsExtra1:setVisible(false)
		button2.ButtonExtraPanel.buttonsExtra2:setVisible(false)
		button1.ButtonExtraPanel.buttonsExtra1:setText("")
		button1.ButtonExtraPanel.buttonsExtra2:setText("")
		button2.ButtonExtraPanel.buttonsExtra1:setText("")
		button2.ButtonExtraPanel.buttonsExtra2:setText("")
		if i > 2 then
			buttons[i].buttons.arrowRef:setVisible(false)
		end
	end

	if buttonId == 1 then
		windowPanel:destroyChildren()
		Character.showStats()
		buttons[buttonId]:setHeight(102)
		buttonspack[buttonId] = "on"
		button1.buttons.arrowRef:setVisible(false)
	
		local widgets = {
			{name = "Character Stats", icon = 11},
			{name = "Offence Stats", icon = 12},
			{name = "Defence Stats", icon = 13},
			{name = "Misc. Stats", icon = 14},
		}

		for i = 1, #widgets do
			local button = button1.ButtonExtraPanel:recursiveGetChildById("buttonsExtra" .. i)
			button:setVisible(true)
			button:setOn(i == 1)
			button:setText(widgets[i].name)
			button.arrowRef:setVisible(i == 1)
			button:setIcon("/game_cyclopedia/images/ui/icon/icon-character-".. widgets[i].icon)
		end
	end

	if buttonId == 2 then
		windowPanel:destroyChildren()
		Character.initRecentDeaths()
		g_game.requestCyclopediaData(3, 30, 1)
		buttons[buttonId]:setHeight(62)
		buttonspack[buttonId] = "on"
		button2.buttons.arrowRef:setVisible(false)
		button2.ButtonExtraPanel.buttonsExtra1.arrowRef:setVisible(true)
		button2.ButtonExtraPanel.buttonsExtra2.arrowRef:setVisible(false)
		button2.ButtonExtraPanel.buttonsExtra1:setVisible(true)
		button2.ButtonExtraPanel.buttonsExtra2:setVisible(true)
		button2.ButtonExtraPanel.buttonsExtra1:setOn(true)
		button2.ButtonExtraPanel.buttonsExtra2:setOn(false)
		button2.ButtonExtraPanel.buttonsExtra1:setIcon("/game_cyclopedia/images/ui/icon/icon-character-"..21)
		button2.ButtonExtraPanel.buttonsExtra2:setIcon("/game_cyclopedia/images/ui/icon/icon-character-"..22)
		button2.ButtonExtraPanel.buttonsExtra1:setText("Recent Deaths")
		button2.ButtonExtraPanel.buttonsExtra2:setText("Recent PvP Kills")
	end

	if buttonId >= 3 and buttonId <= 6 then
		buttons[buttonId].buttons:setOn(true)
		buttons[buttonId].buttons.arrowRef:setImageSource("/game_cyclopedia/images/ui/arrow-right")
		buttons[buttonId].buttons.arrowRef:setVisible(true)
		if buttonId == 3 then windowPanel:destroyChildren() g_game.requestCyclopediaData(5) Character.initAchievements()
		elseif buttonId == 4 then windowPanel:destroyChildren() Character.initSummary() g_game.requestCyclopediaData(6)
		elseif buttonId == 5 then windowPanel:destroyChildren() Character.initAppearences() g_game.requestCyclopediaData(7)
		elseif buttonId == 6 then windowPanel:destroyChildren() Titles.initPanel() g_game.requestCyclopediaData(11) end
	end

	-- BUTTON 1 DO PANEL 1 --
	button1.ButtonExtraPanel.buttonsExtra1.onClick = function()
		windowPanel:destroyChildren()
		Character.showStats()
		button1.ButtonExtraPanel.buttonsExtra1:setOn(true)
		button1.ButtonExtraPanel.buttonsExtra2:setOn(false)
		button1.ButtonExtraPanel.buttonsExtra3:setOn(false)
		button1.ButtonExtraPanel.buttonsExtra4:setOn(false)
		button1.ButtonExtraPanel.buttonsExtra1.arrowRef:setVisible(true)
		button1.ButtonExtraPanel.buttonsExtra2.arrowRef:setVisible(false)
		button1.ButtonExtraPanel.buttonsExtra3.arrowRef:setVisible(false)
		button1.ButtonExtraPanel.buttonsExtra4.arrowRef:setVisible(false)
	end

	-- BUTTON 2 DO PANEL 1 --
	button1.ButtonExtraPanel.buttonsExtra2.onClick = function()
		if button1.ButtonExtraPanel.buttonsExtra2.arrowRef:isVisible() then
			return true
		end

		windowPanel:destroyChildren()
		g_game.requestCyclopediaData(13)
		button1.ButtonExtraPanel.buttonsExtra1:setOn(false)
		button1.ButtonExtraPanel.buttonsExtra2:setOn(true)
		button1.ButtonExtraPanel.buttonsExtra3:setOn(false)
		button1.ButtonExtraPanel.buttonsExtra4:setOn(false)
		button1.ButtonExtraPanel.buttonsExtra1.arrowRef:setVisible(false)
		button1.ButtonExtraPanel.buttonsExtra2.arrowRef:setVisible(true)
		button1.ButtonExtraPanel.buttonsExtra3.arrowRef:setVisible(false)
		button1.ButtonExtraPanel.buttonsExtra4.arrowRef:setVisible(false)
	end

	-- BUTTON 3 DO PANEL 1 --
	button1.ButtonExtraPanel.buttonsExtra3.onClick = function()
		if button1.ButtonExtraPanel.buttonsExtra3.arrowRef:isVisible() then
			return true
		end

		windowPanel:destroyChildren()
		g_game.requestCyclopediaData(14)
		button1.ButtonExtraPanel.buttonsExtra1:setOn(false)
		button1.ButtonExtraPanel.buttonsExtra2:setOn(false)
		button1.ButtonExtraPanel.buttonsExtra3:setOn(true)
		button1.ButtonExtraPanel.buttonsExtra4:setOn(false)
		button1.ButtonExtraPanel.buttonsExtra1.arrowRef:setVisible(false)
		button1.ButtonExtraPanel.buttonsExtra2.arrowRef:setVisible(false)
		button1.ButtonExtraPanel.buttonsExtra3.arrowRef:setVisible(true)
		button1.ButtonExtraPanel.buttonsExtra4.arrowRef:setVisible(false)
	end

	-- BUTTON 4 DO PANEL 1 --
	button1.ButtonExtraPanel.buttonsExtra4.onClick = function()
		if button1.ButtonExtraPanel.buttonsExtra4.arrowRef:isVisible() then
			return true
		end

		windowPanel:destroyChildren()
		g_game.requestCyclopediaData(15)
		button1.ButtonExtraPanel.buttonsExtra1:setOn(false)
		button1.ButtonExtraPanel.buttonsExtra2:setOn(false)
		button1.ButtonExtraPanel.buttonsExtra3:setOn(false)
		button1.ButtonExtraPanel.buttonsExtra4:setOn(true)
		button1.ButtonExtraPanel.buttonsExtra1.arrowRef:setVisible(false)
		button1.ButtonExtraPanel.buttonsExtra2.arrowRef:setVisible(false)
		button1.ButtonExtraPanel.buttonsExtra3.arrowRef:setVisible(false)
		button1.ButtonExtraPanel.buttonsExtra4.arrowRef:setVisible(true)
	end

	-- BUTTON 1 DO PANEL 2 --
	button2.ButtonExtraPanel.buttonsExtra1.onClick = function()
		windowPanel:destroyChildren()
		Character.initRecentDeaths()
		g_game.requestCyclopediaData(3, 30, 1)
		button2.ButtonExtraPanel.buttonsExtra2:setOn(false)
		button2.ButtonExtraPanel.buttonsExtra1:setOn(true)
		button2.ButtonExtraPanel.buttonsExtra1.arrowRef:setVisible(true)
		button2.ButtonExtraPanel.buttonsExtra2.arrowRef:setVisible(false)
	end

	-- BUTTON 2 DO PANEL 2 --
	button2.ButtonExtraPanel.buttonsExtra2.onClick = function()
		windowPanel:destroyChildren()
		Character.initPvPDeaths()
		g_game.requestCyclopediaData(4, 30, 1)
		button2.ButtonExtraPanel.buttonsExtra1:setOn(false)
		button2.ButtonExtraPanel.buttonsExtra2:setOn(true)
		button2.ButtonExtraPanel.buttonsExtra1.arrowRef:setVisible(false)
		button2.ButtonExtraPanel.buttonsExtra2.arrowRef:setVisible(true)
	end
end

function Character.inspectSelectedItem(widget)
	if not widget.item:getItem() then
		return
	end

	windowPanel = getWindowPanel()
	if not windowPanel then
		return
	end

	if lastSelectedItem then
		lastSelectedItem:setBorderWidth(0)
	end

	widget:setBorderWidth(1)
	widget:setBorderColor("white")
	lastSelectedItem = widget

	windowPanel.itemInfor:destroyChildren()
	local slot = inspectItems[tonumber(widget:getId())]
	if not slot then
		return
	end

	windowPanel.itemText:setText("You are inspecting: " .. slot.itemName)
	windowPanel.imbuementPanel:destroyChildren()

	for k, v in ipairs(slot.imbuingSlots) do
		local widget = g_ui.createWidget("Slot", windowPanel.imbuementPanel)
		if v.imbuimentId > 0 then
		  	widget:setImageSource("/images/game/imbuing/imbuement-icons-64")
		  	widget:setImageClip(getFramePosition(v.imbuimentId, 64, 64, 21) .. " 64 64")
		end
	  end

	for _, str in ipairs(slot.descriptions) do
		local widget = g_ui.createWidget('InspectLabel', windowPanel.itemInfor)
		widget.label:setText(str.label .. ":")
		widget.content:setText(str.content)

		if widget.content:isTextWraped() then
			local wrappedLines = widget.content:getWrappedLinesCount()
			if wrappedLines == 1 then
				widget:setSize(tosize("270 " .. 19 * (wrappedLines + 1)))
			else
				widget:setSize(tosize("270 " .. 22 * (wrappedLines)))
			end
		end
	end
end

function Character.toggleInspectCharacter(widget)
	windowPanel = getWindowPanel()
	if not windowPanel then
		return
	end

	windowPanel.charButton:setVisible(false)
	windowPanel.backpackButton:setVisible(true)

	windowPanel.itemsPanel:destroyChildren()
	windowPanel.itemInfor:destroyChildren()
	local widget = g_ui.createWidget('InspectCreature', windowPanel.itemsPanel)
	local outfit = inspectPlayer.outfit or basePlayerData.outfit
	if outfit then
		widget:setOutfit(outfit)
	end

	windowPanel.itemText:setText("You are inspecting: " .. (inspectPlayer.name or basePlayerData.name or ""))
	for _, str in pairs(inspectPlayer.playerData or {}) do
		local widget = g_ui.createWidget('InspectLabel', windowPanel.itemInfor)
		widget.label:setText(str.detail .. ":")
		widget.content:setText(str.description)

		if widget.content:isTextWraped() then
			local wrappedLines = widget.content:getWrappedLinesCount()
			if wrappedLines == 1 then
				widget:setSize(tosize("270 " .. 19 * (wrappedLines + 1)))
			else
				widget:setSize(tosize("270 " .. 21 * (wrappedLines)))
			end
		end
	end
end

function Character.toggleInspectItems(widget)
	windowPanel = getWindowPanel()
	if not windowPanel then
		return
	end

	windowPanel.backpackButton:setVisible(false)
	windowPanel.charButton:setVisible(true)

	windowPanel.itemsPanel:destroyChildren()
	Character.initMainWindow()
end

-------------------------------

function Character.rebuildPanel()
	VisibleCyclopediaPanel:destroyChildren()
	VisibleCyclopediaPanel = g_ui.createWidget('CharacterDataPanel', cyclopediaWindow.optionsCharacterPanel)
	VisibleCyclopediaPanel:setId("CharacterDataPanel")
	Character.initMainWindow()
end

-------------------------------------

local statsIndexOffsets = {
  [1] = {name = "Level", offsettop = 4, offsetleft = 3},
  [2] = {name = "Experience", offsettop = 30, offsetleft = 3},
  [3] = {name = "XP Gain Rate", offsettop = 48, offsetleft = 3},
  [4] = {name = "Hit Points", offsettop = 87, offsetleft = 3},
  [5] = {name = "Mana", offsettop = 105, offsetleft = 3},
  [6] = {name = "Soul Points", offsettop = 122, offsetleft = 3},
  [7] = {name = "Capacity", offsettop = 141, offsetleft = 3},
  [8] = {name = "Speed", offsettop = 159, offsetleft = 3},
  [9] = {name = "Food", offsettop = 177, offsetleft = 3},
  [10] = {name = "Stamina", offsettop = 195, offsetleft = 3},
  [11] = {name = "Offline Training", offsettop = 223, offsetleft = 3}
}

local statsValueOffsets = {
  [1] = {name = "LevelValue", offsettop = 5, offsetright = 4},
  [2] = {name = "ExperienceValue", offsettop = 30, offsetright = 4},
  [3] = {name = "XPGainRateValue", offsettop = 48, offsetright = 4},
  [4] = {name = "HitPointsValue", offsettop = 87, offsetright = 4},
  [5] = {name = "ManaValue", offsettop = 105, offsetright = 4},
  [6] = {name = "SoulPointsValue", offsettop = 123, offsetright = 4},
  [7] = {name = "CapacityValue", offsettop = 141, offsetright = 4},
  [8] = {name = "SpeedValue", offsettop = 159, offsetright = 4},
  [9] = {name = "FoodValue", offsettop = 177, offsetright = 4},
  [10] = {name = "StaminaValue", offsettop = 195, offsetright = 4},
  [11] = {name = "OfflineTrainingValue", offsettop = 224, offsetright = 4}
}

function Character.showStats()
	windowPanel:setImageSource("/game_cyclopedia/images/ui/panel-background")
	local stats = g_ui.createWidget('CharacterStats', windowPanel)
	stats:setId("CharacterStats")
	local player = g_game.getLocalPlayer()

	for k, v in ipairs(statsIndexOffsets) do
		local id = v.name:gsub(" ", "")
		local indexLabel = g_ui.createWidget('StatsLabelIndex', stats.StatsNmesInfor)
		indexLabel:setId(id)
		indexLabel:setText(v.name)
		indexLabel:setMarginTop(v.offsettop)
		indexLabel:setMarginLeft(v.offsetleft)
	end

	for k, v in ipairs(statsValueOffsets) do
		local valueLabel = g_ui.createWidget('StatsLabelValue', stats.StatsNmesInfor)
		valueLabel:setId(v.name)

		if k == 1 then
			valueLabel:setText(comma_value(player:getLevel()))  -- Level
		elseif k == 2 then
			valueLabel:setText(comma_value(player:getExperience())) -- Experience
		elseif k == 3 then
			local gainRate, tooltip = Character.getExperienceGainRate(player)
			valueLabel:setText(gainRate .. "%")
			-- not working
			valueLabel:setTooltip(tooltip)
			valueLabel:setColor("#44ad25") -- Xp Gain Rate
		elseif k == 4 then
			valueLabel:setText(comma_value(player:getHealth())) -- HitPointsValue
			valueLabel:setTooltip(tr("You have %s of %s Hit Points left", comma_value(player:getHealth()), comma_value(player:getMaxHealth())))
		elseif k == 5 then
			valueLabel:setText(comma_value(player:getMana())) -- Mana
			valueLabel:setTooltip(tr("You have %s of %s Mana left", comma_value(player:getMana()), comma_value(player:getMaxMana())))
		elseif k == 6 then
			valueLabel:setText(player:getSoul()) -- Soul Points
		elseif k == 7 then
			valueLabel:setText(comma_value(math.floor(player:getFreeCapacity()))) -- Capacity
			valueLabel:setTooltip(tr("You have %s of %s Capacity left", comma_value(math.floor(player:getFreeCapacity())), comma_value(math.floor(player:getTotalCapacity() / 100))))
		elseif k == 8 then
			valueLabel:setText(player:getSpeed()) -- Speed
			-- todo
		elseif k == 9 then
			local regenTime = player:getRegenerationTime()
			valueLabel:setText(onRegenerationChange(player, regenTime)) -- Food Time
			local text = "You are hungry.\nEat something to regenerate hit points and mana over time"
			if regenTime > 0 then
				local totalMinutes = math.floor(regenTime / 60)
				local seconds = regenTime % 60
				text = tr("You are regenerating hit points and mana for %s minutes and %s seconds", tostring(tonumber(totalMinutes)), tostring(tonumber(seconds)))
			end
			valueLabel:setTooltip(text)
		elseif k == 10 then
			local text = ''
			local stamina = player:getStamina()
			local hours = math.floor(stamina / 60)
			local minutes = stamina % 60

			if stamina > 2400 then
				text = tr("You have %s hours and %s minutes left and receive ", tostring(tonumber(hours)), tostring(tonumber(minutes))) .. "50% more\nexperience (Premium Only)"
			else
				text = tr("You have %s hours and %s minutes left", tostring(tonumber(hours)), tostring(tonumber(minutes)))
			end

			valueLabel:setTooltip(text)
			valueLabel:setText(onStaminaChange(player, stamina)) -- Stamina
		elseif k == 11 then
			local offline = player:getOfflineTrainingTime()
			local hours = tostring(tonumber(math.floor(offline / 60)))
			local minutes = tostring(tonumber(offline % 60))
			valueLabel:setText(onOfflineTrainingChange(player, offline)) -- Offline Training
			valueLabel:setTooltip(tr("You have %s hours and %s minutes of offline training time left", hours, minutes))
		end

		valueLabel:setMarginTop(v.offsettop)
		valueLabel:setMarginRight(v.offsetright)
	end

	-- Magic level stats
	local magicWidget = stats.StatsNmesInfor2:recursiveGetChildById("MagicValue")
	local magicPercentWidget = stats.StatsNmesInfor2:recursiveGetChildById("MagicProgressBar")
	local magicLevel, tooltip, color = Character.getMagicSkillValue(player)

	magicWidget:setText(magicLevel)
	magicWidget:setTooltip(tooltip)
	magicWidget:setColor(color)
	magicPercentWidget:setPercent(player:getMagicLevelPercent() / 100)
	magicPercentWidget:setTooltip(tooltip)

	-- Skills stats
	for i = 0, 6 do
		local valueWidget = stats.StatsNmesInfor2:recursiveGetChildById('skillValue' .. i)
		local percentWidget = stats.StatsNmesInfor2:recursiveGetChildById('skillProgress' .. i)
		local skillLevel, tooltip, color = Character.getSkillValue(player, i)

		valueWidget:setText(skillLevel)
		valueWidget:setTooltip(tooltip)
		valueWidget:setColor(color)
		percentWidget:setPercent(player:getSkillLevelPercent(i) / 100)
		percentWidget:setTooltip(tooltip)
	end

	if player:canBuyExpBoost() then
		stats.StatsNmesInfor.storeButton:setVisible(true)
	else
		stats.StatsNmesInfor.storeButton:setVisible(false)
	end
end

function onOfflineTrainingChange(localPlayer, offlineTrainingTime)
    if not g_game.getFeature(GameOfflineTrainingTime) then
        return
    end
    local hours = math.floor(offlineTrainingTime / 60)
    local minutes = offlineTrainingTime % 60
    if minutes < 10 then
        minutes = '0' .. minutes
    end
    return tostring(hours..":"..minutes)
end

function onRegenerationChange(localPlayer, regenerationTime)
    if not g_game.getFeature(GamePlayerRegenerationTime) or regenerationTime < 0 then
        return
    end
    local minutes = math.floor(regenerationTime / 60)
    local seconds = regenerationTime % 60
    if minutes < 10 then
      minutes = '0' .. minutes
    end
    if seconds < 10 then
        seconds = '0' .. seconds
    end
    return tostring(minutes..":"..seconds)
end

function onStaminaChange(localPlayer, stamina)
  local hours = math.floor(stamina / 60)
  local minutes = stamina % 60
  if minutes < 10 then
      minutes = '0' .. minutes
  end
  return tostring(hours..":"..minutes)
end

local function updatePanel(panel, values)
	for id, value in pairs(values) do
		local widget = panel:recursiveGetChildById(id)
		if widget then
			widget.value:setText(value.text)
			widget:setVisible(value.visible)
			if value.icon then
				widget.icon:setImageSource(value.icon)
			end

			if value.tooltip then
				widget:setTooltip(value.tooltip)
			end
		end
	end
end

local function updateElementalCritical(elementCriticalChance, crititalType, panel)
	local updateData = {}

	for i = 1, 3 do
		updateData[(crititalType .. i)] = { text = "", visible = false }
	end

	local index = 1
	for elementId, chance in pairs(elementCriticalChance.elementMap) do
		if index > 3 then break end
		local targetText = string.format("+%d%% for %s Spells and Runes", chance, getElementName(elementId))
		updateData[(crititalType .. index)] = {
			text = short_text(targetText, 25),
			tooltip = targetText,
			visible = true
		}
		index = index + 1
	end
	updatePanel(panel:recursiveGetChildById("rightInfoPanel0"), updateData)
end

local function updateDamageBySkill(damageMap, widgetName, targetPanel, panel)
	local updateData = {}

	for i = 1, 3 do
		updateData[(widgetName .. i)] = { text = "", visible = false }
	end

	local index = 1
	local totalDamage = 0
	for skillType, pair in pairs(damageMap) do
		if index > 3 then break end

		local skillName = SkillNames[skillType]
		if skillType ~= 1 and skillType ~= 6 then
			skillName = skillName .. " Fighting"
		end

		local targetText = string.format("%d from %s", pair.second, skillName)
		updateData[(widgetName .. index)] = {
			text = short_text(targetText, 25),
			tooltip = string.format("Spell deal damage equal to %d%% of your %s.", pair.first, skillName),
			visible = true
		}
		index = index + 1
		totalDamage = totalDamage + pair.second
	end
	updatePanel(panel:recursiveGetChildById(targetPanel), updateData)

	return totalDamage
end

local function updateSpecificTargets(damageBoostData, panel)
	local updateData = {}

	for i = 1, 3 do
		updateData["againstBestiary_" .. i] = { text = "", visible = false }
	end

	local index = 1
	for name, chance in pairs(damageBoostData.bestiaryDamage) do
		if index > 3 then break end
		local targetText = string.format("+%d%% against %s", chance, name)
		updateData["againstBestiary_" .. index] = {
			text = short_text(targetText, 25),
			tooltip = targetText,
			visible = true
		}
		index = index + 1
	end

	updateData.againstPowerfulFoes = {
		text = "+" .. damageBoostData.powerfulFoeDamage .. "% against powerful foes",
		visible = damageBoostData.powerfulFoeDamage ~= 0
	}

	updatePanel(panel:recursiveGetChildById("infoPanel5"), updateData)
end

function Character.onCyclopediaOffence(data, cleavePercent, perfectShotData, damageAndHealing, damageAndHealingLevel, damageAndHealingWheel, attackData, distanceFactor,
	damageBoostData, elementCriticalChance, elementCriticalDamage, healPerks, meleePercentDamage, spellPercentDamage, healingPercentBoost)

	windowPanel = getWindowPanel()
	if not windowPanel then
		return
	end
	windowPanel:setImageSource("/game_cyclopedia/images/ui/panel-background")
	local Combatstats = g_ui.createWidget('OffenseStats', windowPanel)

	-- Flat Damage
	updatePanel(
		Combatstats:recursiveGetChildById("infoPanel0"),
		{
			flatDamage = { text = damageAndHealing, visible = true },
			flatFromCharacter = { text = damageAndHealingLevel .. " from Character Level", visible = damageAndHealingLevel ~= 0 and damageAndHealingWheel ~= 0 },
			flatFromWheel = { text = damageAndHealingWheel .. " from Wheel of Destiny", visible = damageAndHealingWheel ~= 0 }
		}
	)

	-- Damage
	updatePanel(
		Combatstats:recursiveGetChildById("infoPanel1"),
		{
			attackValue = { text = attackData.value, visible = true, icon = '/game_cyclopedia/images/icons/stats/element_' .. attackData.valueElement },
			attackFlat = { text = attackData.valueFlat .. " from Flat Bonus", visible = attackData.valueFlat ~= 0 },
			attackEquipment = { text = attackData.valueEquipment .. " from Equipment", visible = attackData.valueEquipment ~= 0 },
			attackSkill = { text = attackData.valueFromSkill .. " from " .. SkillNames[attackData.valueSkill] .. " Fighting", visible = attackData.valueFromSkill ~= 0 },
			attackCombatTatics = { text = attackData.valueMastery .. " from Combat Tatics", visible = attackData.valueMastery ~= 0 },
			convertedDamage = { text = "+" .. attackData.valueConverted .. "%", visible = attackData.valueConverted ~= 0, icon = '/game_cyclopedia/images/icons/stats/element_' .. attackData.valueConvertedElement }
		}
	)

	-- Life Leech
	local lifeLeechData = data[1]
	updatePanel(
		Combatstats:recursiveGetChildById("infoPanel2"),
		{
			lifeValue = { text = "+" .. lifeLeechData.skillPercent .. "%", visible = lifeLeechData.skillPercent ~= 0 },
			lifeEquipment = { text = "+" .. lifeLeechData.fromEquipment .. "% from Equipment", visible = lifeLeechData.fromEquipment ~= 0 },
			lifeImbuement = { text = "+" .. lifeLeechData.fromImbuement .. "% from Imbuement", visible = lifeLeechData.fromImbuement ~= 0 and (lifeLeechData.fromSkillWheel ~= 0 or lifeLeechData.fromEvent ~= 0) },
			lifeWheel = { text = "+" .. lifeLeechData.fromSkillWheel .. "% from Wheel of Destiny", visible = lifeLeechData.fromSkillWheel ~= 0 },
			lifeEvent = { text = "+" .. lifeLeechData.fromEvent .. "% from Event Bonus", visible = lifeLeechData.fromEvent ~= 0 }
		}
	)

	-- Mana Leech
	local manaLeechData = data[2]
	updatePanel(
		Combatstats:recursiveGetChildById("infoPanel3"),
		{
			manaValue = { text = "+" .. manaLeechData.skillPercent .. "%", visible = manaLeechData.skillPercent ~= 0 },
			manaEquipment = { text = "+" .. manaLeechData.fromEquipment .. "% from Equipment", visible = manaLeechData.fromEquipment ~= 0 },
			manaImbuement = { text = "+" .. manaLeechData.fromImbuement .. "% from Imbuement", visible = manaLeechData.fromImbuement ~= 0 and (manaLeechData.fromSkillWheel ~= 0 or manaLeechData.fromEvent ~= 0) },
			manaWheel = { text = "+" .. manaLeechData.fromSkillWheel .. "% from Wheel of Destiny", visible = manaLeechData.fromSkillWheel ~= 0 },
			manaEvent = { text = "+" .. manaLeechData.fromEvent .. "% from Event Bonus", visible = manaLeechData.fromEvent ~= 0 }
		}
	)

	-- Mana Gain
	updatePanel(
		Combatstats:recursiveGetChildById("infoPanel3"),
		{
			manaOnHit = { text = healPerks.manaOnHit, visible = healPerks.manaOnHit ~= 0 },
			manaOnKill = { text = healPerks.manaOnKill, visible = healPerks.manaOnKill ~= 0 },
		}
	)

	-- Life gain
	updatePanel(
		Combatstats:recursiveGetChildById("infoPanel2"),
		{
			lifeOnHit = { text = healPerks.healthOnHit, visible = healPerks.healthOnHit ~= 0 },
			lifeOnKill = { text = healPerks.healthOnKill, visible = healPerks.healthOnKill ~= 0 },
		}
	)

	-- Damage Against Targets
	local specificTargetWidget = Combatstats:recursiveGetChildById("damageAgainst")
	specificTargetWidget:setVisible(damageBoostData.powerfulFoeDamage ~= 0 or table.size(damageBoostData.bestiaryDamage) > 0)
	updateSpecificTargets(damageBoostData, Combatstats)
	
	-- Melee damage percent by skill
	local meleeDamageWidget = Combatstats:recursiveGetChildById("autoAttackExtraDmg")
	local totalDamage = updateDamageBySkill(meleePercentDamage, "fromMeleeSkill_", "infoPanel6", Combatstats)
	meleeDamageWidget:setVisible(not table.empty(meleePercentDamage))
	meleeDamageWidget:getChildById("value"):setText(totalDamage)

	-- Extra Spell Damage percent by skill
	local spellDamageWidget = Combatstats:recursiveGetChildById("spellExtraDmg")
	local totalDamage = updateDamageBySkill(spellPercentDamage, "fromSpellSkill_", "infoPanel7", Combatstats)
	spellDamageWidget:setVisible(not table.empty(spellPercentDamage))
	spellDamageWidget:getChildById("value"):setText(totalDamage)

	-- Extra Healing percent by skill
	local extraHealingWidget = Combatstats:recursiveGetChildById("spellExtraHeal")
	local totalDamage = updateDamageBySkill(healingPercentBoost, "fromHealingSkill_", "infoPanel8", Combatstats)
	extraHealingWidget:setVisible(not table.empty(healingPercentBoost))
	extraHealingWidget:getChildById("value"):setText(totalDamage)

	-- Critical Chance
	local criticalChanceData = data[3]
	local criticalChanceWidget = Combatstats:recursiveGetChildById("criticalData")
	criticalChanceWidget:recursiveGetChildById("chanceValue"):setText("+" .. criticalChanceData.skillPercent .. "%")

	updatePanel(
		Combatstats:recursiveGetChildById("rightInfoPanel0"),
		{
			criticalFlatBonus = { text = "+" .. criticalChanceData.fromFlatBonus .. "% from Flat Bonus", visible = criticalChanceData.fromFlatBonus ~= 0 and (criticalChanceData.fromSkillWheel ~= 0 or criticalChanceData.fromConcoction ~= 0) },
			criticalEquipment = { text = "+" .. criticalChanceData.fromEquipment .. "% from Equipment", visible = criticalChanceData.fromEquipment ~= 0 and (criticalChanceData.fromSkillWheel ~= 0 or criticalChanceData.fromConcoction ~= 0) },
			criticalImbuement = { text = "+" .. criticalChanceData.fromImbuement .. "% from Imbuement", visible = criticalChanceData.fromImbuement ~= 0 and (criticalChanceData.fromSkillWheel ~= 0 or criticalChanceData.fromConcoction ~= 0)},
			criticalWheel = { text = "+" .. criticalChanceData.fromSkillWheel .. "% from Wheel of Destiny", visible = criticalChanceData.fromSkillWheel ~= 0 },
			criticalConcoction = { text = "+" .. criticalChanceData.fromConcoction .. "% from Concoction", visible = criticalChanceData.fromConcoction ~= 0 }
		}
	)

	-- Critical Damage
	local criticalDamageData = data[4]
	local criticalDamageWidget = Combatstats:recursiveGetChildById("criticalExtraDmg")
	criticalDamageWidget:recursiveGetChildById("extraValue"):setText("+" .. criticalDamageData.skillPercent .. "%")

	updatePanel(
		Combatstats:recursiveGetChildById("rightInfoPanel0"),
		{
			criticalFlatBonus = { text = "+" .. criticalDamageData.fromFlatBonus .. "% from Flat Bonus", visible = criticalDamageData.fromFlatBonus ~= 0 and (criticalDamageData.fromSkillWheel ~= 0 or criticalDamageData.fromConcoction ~= 0) },
			criticalEquipment = { text = "+" .. criticalDamageData.fromEquipment .. "% from Equipment", visible = criticalDamageData.fromEquipment ~= 0 and (criticalDamageData.fromSkillWheel ~= 0 or criticalDamageData.fromConcoction ~= 0) },
			criticalImbuement = { text = "+" .. criticalDamageData.fromImbuement .. "% from Imbuement", visible = criticalDamageData.fromImbuement ~= 0 and (criticalDamageData.fromSkillWheel ~= 0 or criticalDamageData.fromConcoction ~= 0)},
			criticalWheel = { text = "+" .. criticalDamageData.fromSkillWheel .. "% from Wheel of Destiny", visible = criticalDamageData.fromSkillWheel ~= 0 },
			criticalConcoction = { text = "+" .. criticalDamageData.fromConcoction .. "% from Concoction", visible = criticalDamageData.fromConcoction ~= 0 }
		}
	)

	-- Critical Chance By Type
	local elementChanceWidget = Combatstats:recursiveGetChildById("criticalChanceType")
	elementChanceWidget:setVisible(elementCriticalChance.runeCritical ~= 0 or elementCriticalChance.meleeCritical ~= 0 or table.size(elementCriticalChance.elementMap) > 0)
	updateElementalCritical(elementCriticalChance, "chanceFromSpells_", Combatstats)
	updatePanel(
		Combatstats:recursiveGetChildById("rightInfoPanel0"),
		{
			chanceFromRunes = { text = "+" .. elementCriticalChance.runeCritical .. "% for Offensive Runes", visible = elementCriticalChance.runeCritical ~= 0 },
			chanceAutoAttack = { text = "+" .. elementCriticalChance.meleeCritical .. "% for Auto-Attack", visible = elementCriticalChance.meleeCritical ~= 0}
		}
	)

	-- Critical Damage By Type
	local elementDamageWidget = Combatstats:recursiveGetChildById("criticalDamageType")
	elementDamageWidget:setVisible(elementCriticalDamage.runeCritical ~= 0 or elementCriticalDamage.meleeCritical ~= 0 or table.size(elementCriticalDamage.elementMap) > 0)
	updateElementalCritical(elementCriticalDamage, "damageFromSpells_", Combatstats)
	updatePanel(
		Combatstats:recursiveGetChildById("rightInfoPanel0"),
		{
			damageFromRunes = { text = "+" .. elementCriticalDamage.runeCritical .. "% for Offensive Runes", visible = elementCriticalDamage.runeCritical ~= 0 },
			damageAutoAttack = { text = "+" .. elementCriticalDamage.meleeCritical .. "% for Auto-Attack", visible = elementCriticalDamage.meleeCritical ~= 0}
		}
	)

	-- Cleave
	updatePanel(
		Combatstats:recursiveGetChildById("rightInfoPanel1"),
		{ cleaveValue = { text = "+" .. cleavePercent .. "%", visible = cleavePercent ~= 0 } }
	)

	-- Distance Accuracy
	local distancePanel = Combatstats:recursiveGetChildById("rightInfoPanel2")
	if #distanceFactor <= 1 then
		local factor = distanceFactor[1] or 0
		updatePanel(distancePanel, { distanceAccuracy = { text = "+" .. factor .. "%", visible = factor ~= 0 } })
	else
		distancePanel:recursiveGetChildById("distanceAccuracy"):setVisible(true)
		distancePanel:recursiveGetChildById("distanceAccuracy"):setMarginBottom(3)
		for k, v in pairs(distanceFactor) do
			local widget = g_ui.createWidget("InfoMidLabel", distancePanel)
			widget.value:setText(v .. "% from Range " .. k)
		end
	end

	-- Perfect Shot
	local perftShotPanel = Combatstats:recursiveGetChildById("rightInfoPanel3")
	for k, v in pairs(perfectShotData) do
		if v ~= 0 then
			perftShotPanel:recursiveGetChildById("perfectShotLabel"):setVisible(true)
			perftShotPanel:recursiveGetChildById("shotValue"):setVisible(true)
			perftShotPanel:recursiveGetChildById("shotValue").value:setText("+" .. v .. " from Range " .. k)
			break
		end
	end
end

function Character.onCyclopediaDefence(dodgeData, shieldCapacity, shieldDirect, shieldPercentage, damageReflect, armorValueData, defenseData, mitigationData, elementalProtections, mantraDefense)
	windowPanel = getWindowPanel()
	if not windowPanel then
		return
	end
	windowPanel:setImageSource("/game_cyclopedia/images/ui/panel-background")
	local Defensestats = g_ui.createWidget('DefenseStats', windowPanel)

	local function updatePanel(panel, values)
		for id, value in pairs(values) do
			local widget = panel:recursiveGetChildById(id)
			if widget then
				widget.value:setText(value.text)
				widget:setVisible(value.visible)
				if value.icon then
					widget.icon:setImageSource(value.icon)
				end
			end
		end
	end

	-- Defence 
	updatePanel(
		Defensestats:recursiveGetChildById("infoPanel0"),
		{
			defenseValue = { text = defenseData.value, visible = true },
			defenceEquipment = { text = defenseData.valueEquipment .. " from Equipment", visible = defenseData.valueEquipment ~= 0 },
			defenceSkill = { text = defenseData.valueFromSkill .. " from " .. SkillNames[defenseData.valueSkill], visible = defenseData.valueFromSkill ~= 0 },
			defenceWheel = { text = defenseData.valueMastery .. " from Wheel of Destiny", visible = defenseData.valueMastery ~= 0 },
			defenceCombatTatics = { text = defenseData.valueCombatTatcis .. " from Combat Tatics", visible = defenseData.valueCombatTatcis ~= 0 }
		}
	)

	-- Armor
	updatePanel(
		Defensestats:recursiveGetChildById("infoPanel1"),
		{
			armorValue = { text = armorValueData, visible = true },
		}
	)

	-- Mantra
	updatePanel(
		Defensestats:recursiveGetChildById("mantraPanel"),
		{
			mantraValue = { text = mantraDefense, visible = true },
		}
	)

	-- Mitigation
	updatePanel(
		Defensestats:recursiveGetChildById("infoPanel2"),
		{
			mitigationValue = { text = "+" .. mitigationData.skillPercent .. "%", visible = true },
			mitigationDefense = { text = "+" .. mitigationData.fromDefense .. "% from Defence", visible = mitigationData.fromDefense ~= 0 and mitigationData.fromSkillWheel ~= 0 },
			mitigationShielding = { text = "+" .. mitigationData.fromShielding .. "% from Shielding", visible = mitigationData.fromShielding ~= 0 and mitigationData.fromSkillWheel ~= 0 },
			mitigationEquipment = { text = "* " .. mitigationData.fromEquipment .. "% from Equipment", visible = mitigationData.fromEquipment ~= 0 and mitigationData.fromSkillWheel ~= 0 },
			mitigationWheel = { text = "* " .. mitigationData.fromSkillWheel .. "% from Wheel of Destiny", visible = mitigationData.fromSkillWheel ~= 0 },
			mitigationTatics = { text = "* " .. mitigationData.fromCombatTatics .. "% from Combat Tatics", visible = mitigationData.fromCombatTatics ~= 0 and mitigationData.fromSkillWheel ~= 0 }
		}
	)

	-- Magic Shield Capacity
	updatePanel(
		Defensestats:recursiveGetChildById("infoPanel3"),
		{
			magicShield = { text = shieldCapacity, visible = shieldCapacity ~= 0 },
			directBonus = { text = shieldDirect .. " from Direct Bonus", visible = shieldDirect ~= 0 },
			percentBonusBonus = { text = "* " .. shieldPercentage .. "% from Percentage Bo...", visible = shieldPercentage ~= 0 }
		}
	)

	-- Dodge (Ruse)
	updatePanel(
		Defensestats:recursiveGetChildById("infoPanel4"),
		{
			dodgeValue = { text = "+" .. dodgeData.skillPercent .. "%", visible = dodgeData.skillPercent ~= 0 },
			fromEquipment = { text = "+" .. dodgeData.fromEquipment .. "% from Equipment", visible = dodgeData.fromEquipment ~= 0 and (dodgeData.fromSkillWheel ~= 0 or dodgeData.fromAmplification ~= 0) },
			fromAmplification = { text = "+" .. dodgeData.fromAmplification .. "% from Amplification", visible = dodgeData.fromAmplification ~= 0 },
			fromWheel = { text = "+" .. dodgeData.fromSkillWheel .. "% from Wheel of Destiny", visible = dodgeData.fromSkillWheel ~= 0 },
			fromEventBonus = { text = "+" .. dodgeData.fromEvent .. "% from Event Bonus", visible = dodgeData.fromEvent ~= 0 }
		}
	)

	-- Damage Reflection
	updatePanel(
		Defensestats:recursiveGetChildById("infoPanel5"),
		{
			damageReflection = { text = damageReflect, visible = damageReflect ~= 0 },
		}
	)

	-- Combat Defenses
	for i = 0, 11 do
		local value = elementalProtections[i + 1] or 0
		local elementWidget = Defensestats:recursiveGetChildById('element_' .. i)

		if elementWidget then
			local color = "#c0c0c0"
			if value < 0 then
				color = "#ff9854"
			elseif value > 0 then
				color = "#44ad25"
			end

			elementWidget:recursiveGetChildById("value"):setText(value < 0 and (value .. "%") or ("+" .. value .. "%"))
			elementWidget:recursiveGetChildById("value"):setColor(color)

			local effectStr = value < 0 and "increased" or "reduced"
			local noteStr = specialTooltips["protection_note"]
			elementWidget:setTooltip(tr(specialTooltips["protection"], getCombatName(i), effectStr, value, noteStr))

			if i == 9 or i == 10 then
				elementWidget:setVisible(value ~= 0)
			end
		end
	end
end

function Character.onCyclopediaMisc(momentum, transcendence, amplification, currentBless, maxBless, concoctionList, cooldownList)
	windowPanel = getWindowPanel()
	if not windowPanel then
		return
	end
	windowPanel:setImageSource("/game_cyclopedia/images/ui/panel-background")
	local MiscStats = g_ui.createWidget('MiscStats', windowPanel)

	local function updatePanel(panel, values)
		for id, value in pairs(values) do
			local widget = panel:recursiveGetChildById(id)
			if widget then
				widget.value:setText(value.text)
				widget:setVisible(value.visible)
				if value.icon then
					widget.icon:setImageSource(value.icon)
				end
			end
		end
	end

	-- Momentum
	updatePanel(
		MiscStats:recursiveGetChildById("infoPanel0"),
		{
			momentumValue = { text = tr("+%s%%", momentum.skillPercent), visible = momentum.skillPercent ~= 0 },
			momentumEquipment = { text = tr("+%s%% from Equipment", momentum.fromEquipment), visible = momentum.fromEquipment ~= 0 },
			momentumAmplification = { text = tr("+%s%% from Amplification", momentum.fromAmplification), visible = momentum.fromAmplification ~= 0 },
			momentumWheel = { text = tr("+%s%% from Wheel of Destiny", momentum.fromSkillWheel), visible = momentum.fromSkillWheel ~= 0 },
			momentumEvent = { text = tr("+%s%% from Event Bonus", momentum.fromEvent), visible = momentum.fromEvent ~= 0 },
		}
	)

	-- Transcendence
	updatePanel(
		MiscStats:recursiveGetChildById("infoPanel1"),
		{
			transcendenceValue = { text = tr("+%s%%", transcendence.skillPercent), visible = transcendence.skillPercent ~= 0 },
			transcendenceEquipment = { text = tr("+%s%% from Equipment", transcendence.fromEquipment), visible = transcendence.fromEquipment ~= 0 },
			transcendenceAmplification = { text = tr("+%s%% from Amplification", transcendence.fromAmplification), visible = transcendence.fromAmplification ~= 0 },
			transcendenceEvent = { text = tr("+%s%% from Event Bonus", transcendence.fromEvent), visible = transcendence.fromEvent ~= 0 },
		}
	)

	-- Amplification
	updatePanel(
		MiscStats:recursiveGetChildById("infoPanel2"),
		{
			amplificationValue = { text = tr("+%s%%", amplification.skillPercent), visible = amplification.skillPercent ~= 0 },
			amplificationEquipment = { text = tr("+%s%% from Equipment", amplification.fromEquipment), visible = (amplification.fromEquipment ~= 0 and amplification.fromEvent ~= 0) },
			amplificationEvent = { text = tr("+%s%% from Event Bonus", amplification.fromEvent), visible = amplification.fromEvent ~= 0 },
		}
	)

	-- Blessing 
	updatePanel(
		MiscStats:recursiveGetChildById("infoPanel3"),
		{
			blessingValue = { text = tr("%s/%s", currentBless, maxBless), visible = true },
		}
	)

	-- Concoction
	local concoctionPanel = MiscStats:recursiveGetChildById("concoctions")
	concoctionPanel:destroyChildren()
	concoctionPanel:getParent():setVisible(not table.empty(concoctionList))
	for k, v in pairs(concoctionList) do
		local widget = g_ui.createWidget("MiscItems", concoctionPanel)
		widget.item:setItemId(k)
		widget.item:setVirtualTimer(os.time() + v)

		local itemName = g_things.getThingType(k):getMarketData().name
		if not itemName or string.empty(itemName) then
			itemName = "unkown item"
		end

		widget:setTooltip(tr("%s: %s", itemName, getTimeInWords(v)))
	end

	-- Misc Cooldowns
	local cooldownsPanel = MiscStats:recursiveGetChildById("cooldowns")
	cooldownsPanel:destroyChildren()
	cooldownsPanel:getParent():setVisible(not table.empty(cooldownList))
	for k, v in pairs(cooldownList) do
		local widget = g_ui.createWidget("MiscItems", cooldownsPanel)
		widget.item:setItemId(k)
		widget.item:setVirtualTimer(os.time() + v)

		local itemName = g_things.getThingType(k):getMarketData().name
		if not itemName or string.empty(itemName) then
			itemName = "unkown item"
		end

		widget:setTooltip(tr("%s: %s", itemName, getTimeInWords(v)))
	end
end

-- DEATHS --
function Character.initRecentDeaths()
	windowPanel = VisibleCyclopediaPanel:recursiveGetChildById("windowPanel")
	RecentDeaths = g_ui.createWidget('RecentDeaths', windowPanel)
	RecentDeaths:setId("RecentDeaths")
	windowPanel:setImageSource("")
end

function Character.showRecentDeaths(currentPage, totalPages, deaths)
    if not RecentDeaths or RecentDeaths:isDestroyed() or not RecentDeaths:isVisible() then
        return true
    end

    recentDeathPage = (currentPage == 0 and 1 or currentPage)
    recentDeathMax = (totalPages == 0 and 1 or totalPages)
    RecentDeaths.pageText:setText(tr('Page %s / %s', recentDeathPage, recentDeathMax))
    RecentDeaths.listDeaths:destroyChildren()
    lastSelectedRecentDeath = {}

    if recentDeathPage == recentDeathMax then
        RecentDeaths.nextButton:disable()
    else
        RecentDeaths.nextButton:enable()
    end

    if recentDeathPage == 1 then
        RecentDeaths.previousButton:disable()
    else
        RecentDeaths.previousButton:enable()
    end

    local sortedDeaths = {}
    for k, v in pairs(deaths) do
        table.insert(sortedDeaths, {timestamp = k, name = v})
    end

    table.sort(sortedDeaths, function(a, b) return a.timestamp > b.timestamp end)

    local count = 0
    for _, entry in ipairs(sortedDeaths) do
        local widget = g_ui.createWidget('RecentDeath', RecentDeaths.listDeaths)
        if count == 0 then
            Character.onSelectRecentWidget(widget.rank)
        end

        widget.rank:setText(os.date("%Y-%m-%d, %H:%M:%S", entry.timestamp))
        widget.name:setText(short_text(entry.name, 46))
        if #entry.name > 45 then
            widget.name:setTooltip(entry.name)
        end

        local color = ((count % 2 == 0) and '#484848' or '#414141')
        count = count + 1
        widget:setBackgroundColor(color)
    end
end

function Character.changeRecentDeathPage(foward)
	local request = recentDeathPage
	if foward then
		if (request + 1) <= recentDeathMax then
			request = request + 1
		end
	else
		if (request - 1) >= 1 then
			request = request - 1
		end
	end

	g_game.requestCyclopediaData(3, 30, request)
end

function Character.onSelectRecentWidget(self)
	local parent = self:getParent()

	for _, data in pairs(lastSelectedRecentDeath) do
		data.widget:setBackgroundColor(data.color)
		data.widget.rank:setColor("#c0c0c0")
		data.widget.name:setColor("#c0c0c0")
	end

	local oldBackgroundColor = parent:getBackgroundColor()
	parent:setBackgroundColor("#585858")
	parent.rank:setColor("#f4f4f4")
	parent.name:setColor("#f4f4f4")
	lastSelectedRecentDeath = {{widget = parent, color = oldBackgroundColor}}
end

function Character.initPvPDeaths()
	windowPanel = VisibleCyclopediaPanel:recursiveGetChildById("windowPanel")
	RecentPvpKills = g_ui.createWidget('RecentPvpKills', windowPanel)
	RecentPvpKills:setId("RecentPvpKills")
	windowPanel:setImageSource("")
end

function Character.showPvPDeaths(currentPage, totalPages, deaths)
    if not RecentPvpKills or RecentPvpKills:isDestroyed() or not RecentPvpKills:isVisible() then
        return true
    end
    recentPvPPage = (currentPage == 0 and 1 or currentPage)
    recentPvPMax = (totalPages == 0 and 1 or totalPages)
    RecentPvpKills.pageText:setText(tr('Page %s / %s', recentPvPPage, recentPvPMax))

    RecentPvpKills.listDeaths:destroyChildren()
    lastSelectedRecentDeath = {}

    if recentPvPPage == recentPvPMax then
        RecentPvpKills.nextButton:disable()
    else
        RecentPvpKills.nextButton:enable()
    end

    if recentPvPPage == 1 then
        RecentPvpKills.previousButton:disable()
    else
        RecentPvpKills.previousButton:enable()
    end

    local sortedDeaths = {}
    for _, data in pairs(deaths) do
        table.insert(sortedDeaths, {timestamp = data[1], name = data[2], status = data[3]})
    end

    table.sort(sortedDeaths, function(a, b) return a.timestamp > b.timestamp end)

    local count = 0
    for _, entry in ipairs(sortedDeaths) do
        local widget = g_ui.createWidget('RecentPvPDeath', RecentPvpKills.listDeaths)
        if count == 0 then
            Character.onSelectRecentWidget(widget.rank)
        end

        widget.rank:setText(os.date("%Y-%m-%d, %H:%M:%S", entry.timestamp))
        widget.name:setText(short_text(entry.name, 46))
        if #entry.name > 45 then
            widget.name:setTooltip(entry.name)
        end

        local status = entry.status
        if status == 0 then
            widget.status:setText("Justified")
            widget.status:setColor("#44ad25")
        else
            widget.status:setText("Unjustified")
            widget.status:setColor("#d33c3c")
        end

        local color = ((count % 2 == 0) and '#484848' or '#414141')
        count = count + 1
        widget:setBackgroundColor(color)
    end
end

function Character.changePvPDeathPage(foward)
	local request = recentPvPPage
	if foward then
		if (request + 1) <= recentPvPMax then
			request = request + 1
		end
	else
		if (request - 1) >= 1 then
			request = request - 1
		end
	end

	g_game.requestCyclopediaData(4, 30, request)
end

-- DEATHS --

function Character.initAchievements()
  windowPanel = VisibleCyclopediaPanel:recursiveGetChildById("windowPanel")
  achievementWindow = g_ui.createWidget('Achievements', windowPanel)
  achievementWindow:setId("Achievements")
  windowPanel:setImageSource("")

  if achievementRadioGroup then
	achievementRadioGroup:destroy()
	achievementRadioGroup = nil
  end
  achievementRadioGroup = UIRadioGroup.create()
  achievementRadioGroup:addWidget(achievementWindow:recursiveGetChildById('allAchievements'))
  achievementRadioGroup:addWidget(achievementWindow:recursiveGetChildById('lockedAchievements'))
  achievementRadioGroup:addWidget(achievementWindow:recursiveGetChildById('accomplished'))

  achievementRadioGroup:selectWidget(achievementWindow:recursiveGetChildById('accomplished'))

  achievementRadioGroup.onSelectionChange = AchievementSelectionChange
end

function Character.initSummary()
  windowPanel = VisibleCyclopediaPanel:recursiveGetChildById("windowPanel")
  itemSummary = g_ui.createWidget('Summary', windowPanel)
  itemSummary:setId("Summary")
  windowPanel:setImageSource("")
end

function Character.initAppearences()
  windowPanel = VisibleCyclopediaPanel:recursiveGetChildById("windowPanel")
  Appearances = g_ui.createWidget('Appearances', windowPanel)
  Appearances:setId("Appearances")
  windowPanel:setImageSource("")

  if radioAppearances then
    radioAppearances:destroy()
  end
  radioAppearances = UIRadioGroup.create()
  radioAppearances:addWidget(Appearances:recursiveGetChildById('outfits'))
  radioAppearances:addWidget(Appearances:recursiveGetChildById('mounts'))
  radioAppearances:addWidget(Appearances:recursiveGetChildById('familiars'))
  radioAppearances:selectWidget(Appearances:recursiveGetChildById('outfits'))
end



------------------------------
-- Character helper functions
------------------------------
function Character.getExperienceGainRate(player)
	local baseRate = player:getBaseExpRate()
	local lowLevelBonus = player:getLowLevelRate()
	local expBoost = player:getExpBoostRate()
	local staminaMulti = player:getStaminaRate()

	local totalGainRate = (baseRate + lowLevelBonus + expBoost) * staminaMulti / 100
	local tooltip = tr("Your current XP gain rate amounts to %s%s.", totalGainRate, "%") .. "\nYour XP gain rate is calculated as follows:\n" .. tr("- Base XP gain rate: %s%s", baseRate, "%")
	if lowLevelBonus ~= 0 then
		tooltip = tr("%s\n- Low level bonus: +%s%s ", tooltip, lowLevelBonus, "%") .. "(until level 50)"
	end

	if expBoost ~= 0 then
		tooltip = tr("%s\n- XP boost: +%s%s ", tooltip, expBoost, "%") .. tr("(%s h remaining)", formatTimeBySeconds(player:getStoreExpBoostTime()))
	end

	if staminaMulti > 100 then
		local staminaStr = tostring(staminaMulti)
		formattedStr = staminaStr:sub(1, 1) .. "." .. staminaStr:sub(2)
		finalStr = tostring(tonumber(formattedStr))
		tooltip = tr("%s\n- Stamina bonus: x%s ", tooltip, finalStr) .. tr("(%s h remaining)", formatTimeByMinutes(player:getStamina() - 2340))
	end

	return totalGainRate, tooltip
end

function Character.getSkillValue(player, skill)
	local tooltip = ''
	local color = '#bbbbbb'
	local baseValue = player:getSkillBaseLevel(skill)
	local loyalty = player:getSkillLoyalty(skill)
	local value = player:getSkillLevel(skill)
	local percent = player:getSkillLevelPercent(skill)

	local realBase = baseValue + loyalty
	local realValue = value + loyalty

	if value > baseValue or (realBase > baseValue) then
		tooltip = tr("%s = %s", realValue, baseValue)
		if value > baseValue then
			tooltip = tr("%s +%s", tooltip, (value - baseValue))
		    color = "#44ad25"
		end

		if loyalty > 0 then
			tooltip = tr("%s (+%s Loyalty)", tooltip, loyalty)
		end
	elseif value < baseValue then
		color = "#c00000"
		tooltip = (baseValue .. ' ' .. (value - baseValue))
	else
		color = "#bbbbbb" -- default
	end

	if #tooltip == 0 then
		tooltip = tr("You have %s percent to go", convertSkillPercent(10000 - percent))
	else
		tooltip = tr("%s\nYou have %s percent to go", tooltip, convertSkillPercent(10000 - percent))
	end
	return realValue, tooltip, color
end

function Character.getMagicSkillValue(player)
	local tooltip = ''
	local color = '#bbbbbb'
	local baseValue = player:getBaseMagicLevel()
	local loyalty = player:getMagicLoyalty()
	local value = player:getMagicLevel()
	local percent = player:getMagicLevelPercent()

	local realBase = baseValue + loyalty
	local realValue = value + loyalty

	if value > baseValue or (realBase > baseValue) then
		tooltip = tr("%s = %s", realValue, baseValue)
		if value > baseValue then
			tooltip = tr("%s +%s", tooltip, (value - baseValue))
		    color = "#44ad25"
		end

		if loyalty > 0 then
			tooltip = tr("%s (+%s Loyalty)", tooltip, loyalty)
		end
	elseif value < baseValue then
		color = "#c00000"
		skill:setTooltip(baseValue .. ' ' .. (value - baseValue))
	else
		color = "#bbbbbb" -- default
	end

	if #tooltip == 0 then
		tooltip = tr("You have %s percent to go", convertSkillPercent(10000 - percent))
	else
		tooltip = tr("%s\nYou have %s percent to go", tooltip, convertSkillPercent(10000 - percent))
	end
	return realValue, tooltip, color
end

function Character.onCyclopediaBaseInformation(playerName, vocation, level, outfit, currentTitle)
	basePlayerData = {name = playerName, vocation = vocation, level = level, outfit = outfit, title = currentTitle}
end

function Character.onCyclopediaInspect(items, playerName, outfit, playerInfo)
	inspectPlayer = {name = playerName, outfit = outfit, playerData = playerInfo}
	inspectItems = items
end

-- ITEM Summary
function Character.onChangeView()
    if itemSummary:recursiveGetChildById('showasgrid'):isChecked() then
        Character.showItemSummaryGrid()
    else
        Character.showItemSummaryList()
    end

    itemSummary:recursiveGetChildById('searchSummary'):clearText()
end

function Character.onCyclopediaItemSummary(inventory, store, stash, locker, inbox)
	if not itemSummary or itemSummary:isDestroyed() then
		return true
	end

    inventoryList = inventory
    storeList = store
    stashList = stash
    lockerList = locker
    inboxList = inbox
    itemSummary:recursiveGetChildById('inventory'):setChecked(true)
    Character.showItemSummaryList()
    itemSummary:recursiveGetChildById('searchSummary'):clearText()

    if not radioShowType then
        radioShowType = UIRadioGroup.create()
        radioShowType:addWidget(itemSummary:recursiveGetChildById('showaslist'))
        radioShowType:addWidget(itemSummary:recursiveGetChildById('showasgrid'))
        radioShowType:selectWidget(itemSummary:recursiveGetChildById('showaslist'))
    end
end

function Character.showItemSummaryGrid(searchText)
    local inventoryButton = itemSummary:recursiveGetChildById('inventory')
    local depotButton = itemSummary:recursiveGetChildById('depot')
    local inboxButton = itemSummary:recursiveGetChildById('inbox')
    local supplystashButton = itemSummary:recursiveGetChildById('supplystash')
    local storeinboxButton = itemSummary:recursiveGetChildById('storeinbox')

    itemSummary.listView:setVisible(false)
    itemSummary.gridView:setVisible(true)
    itemSummary.gridView.grid:destroyChildren()

    if inventoryButton:isChecked() then
        for _, data in pairs(inventoryList) do
            local itemName = g_things.getThingType(data[1]):getMarketData().name
            if #itemName == 0 then
                itemName = modules.game_actionbar.getItemNameById(data[1])
            end

            if #itemName == 0 or itemName == "this object" then
                itemName = "missing item name"
            end

            if searchText and not matchText(searchText, itemName) then
                goto continue
            end

            local widget = g_ui.createWidget('ItemGridView', itemSummary.gridView.grid)
            widget.item:setItemId(data[1])
            widget.item:setItemCount(data[3])
            widget.item:setTooltip(itemName)

            :: continue ::
        end
    end

    if storeinboxButton:isChecked() then
        for _, data in pairs(storeList) do
            local itemName = g_things.getThingType(data[1]):getMarketData().name
            if #itemName == 0 then
                itemName = modules.game_actionbar.getItemNameById(data[1])
            end

            if #itemName == 0 or itemName == "this object" then
                itemName = "missing item name"
            end

            if searchText and not matchText(searchText, itemName) then
                goto continue
            end

            local widget = g_ui.createWidget('ItemGridView', itemSummary.gridView.grid)
            widget.item:setItemId(data[1])
            widget.item:setItemCount(data[3])
            widget.item:setTooltip(itemName)

            :: continue ::
        end
    end

    if supplystashButton:isChecked() then
        for _, data in pairs(stashList) do
            local itemName = g_things.getThingType(data[1]):getMarketData().name
            if #itemName == 0 then
                itemName = modules.game_actionbar.getItemNameById(data[1])
            end

            if #itemName == 0 or itemName == "this object" then
                itemName = "missing item name"
            end

            if searchText and not matchText(searchText, itemName) then
                goto continue
            end

            local widget = g_ui.createWidget('ItemGridView', itemSummary.gridView.grid)
            widget.item:setItemId(data[1])
            widget.item:setItemCount(data[2])
            widget.item:setTooltip(itemName)

            :: continue ::
        end
    end

    if depotButton:isChecked() then
        for _, data in pairs(lockerList) do
           local itemName = g_things.getThingType(data[1]):getMarketData().name
            if #itemName == 0 then
                itemName = modules.game_actionbar.getItemNameById(data[1])
            end

            if #itemName == 0 or itemName == "this object" then
                itemName = "missing item name"
            end

            if searchText and not matchText(searchText, itemName) then
                goto continue
            end

            local widget = g_ui.createWidget('ItemGridView', itemSummary.gridView.grid)
            widget.item:setItemId(data[1])
            widget.item:setItemCount(data[3])
            widget.item:setTooltip(itemName)

            :: continue ::
        end
    end

    if inboxButton:isChecked() then
        for _, data in pairs(inboxList) do
            local itemName = g_things.getThingType(data[1]):getMarketData().name
            if #itemName == 0 then
                itemName = modules.game_actionbar.getItemNameById(data[1])
            end

            if #itemName == 0 or itemName == "this object" then
                itemName = "missing item name"
            end

            if searchText and not matchText(searchText, itemName) then
                goto continue
            end

            local widget = g_ui.createWidget('ItemGridView', itemSummary.gridView.grid)
            widget.item:setItemId(data[1])
            widget.item:setItemCount(data[3])
            widget.item:setTooltip(itemName)
            :: continue ::
        end
    end
end

function Character.showItemSummaryList(searchText)
    local inventoryButton = itemSummary:recursiveGetChildById('inventory')
    local depotButton = itemSummary:recursiveGetChildById('depot')
    local inboxButton = itemSummary:recursiveGetChildById('inbox')
    local supplystashButton = itemSummary:recursiveGetChildById('supplystash')
    local storeinboxButton = itemSummary:recursiveGetChildById('storeinbox')

    itemSummary.listView:setVisible(true)
    itemSummary.gridView:setVisible(false)
    itemSummary.listView.listSummary:destroyChildren()

    if inventoryButton:isChecked() then
        for _, data in pairs(inventoryList) do
            local itemName = g_things.getThingType(data[1]):getMarketData().name
            if #itemName == 0 then
                itemName = modules.game_actionbar.getItemNameById(data[1])
            end

            if #itemName == 0 or itemName == "this object" then
                itemName = "missing item name"
            end

            if searchText and not matchText(searchText, itemName) then
                goto continue
            end

            local widget = g_ui.createWidget('ItemListView', itemSummary.listView.listSummary)
            widget.name:setText(itemName)
            widget.item:setItemId(data[1])
            widget.count:setText(data[3])

            :: continue ::
        end
    end

    if storeinboxButton:isChecked() then
        for _, data in pairs(storeList) do
            local itemName = g_things.getThingType(data[1]):getMarketData().name
            if #itemName == 0 then
                itemName = modules.game_actionbar.getItemNameById(data[1])
            end

            if #itemName == 0 or itemName == "this object" then
                itemName = "missing item name"
            end

            if searchText and not matchText(searchText, itemName) then
                goto continue
            end

            local widget = g_ui.createWidget('ItemListView', itemSummary.listView.listSummary)
            widget.name:setText(itemName)
            widget.item:setItemId(data[1])
            widget.count:setText(data[3])

            :: continue ::
        end
    end

    if supplystashButton:isChecked() then
        for _, data in pairs(stashList) do
            local itemName = g_things.getThingType(data[1]):getMarketData().name
            if #itemName == 0 then
                itemName = modules.game_actionbar.getItemNameById(data[1])
            end

            if #itemName == 0 or itemName == "this object" then
                itemName = "missing item name"
            end

            if searchText and not matchText(searchText, itemName) then
                goto continue
            end

            local widget = g_ui.createWidget('ItemListView', itemSummary.listView.listSummary)
            widget.name:setText(itemName)
            widget.item:setItemId(data[1])
            widget.count:setText(data[2])

            :: continue ::
        end
    end

    if depotButton:isChecked() then
        for _, data in pairs(lockerList) do
            local itemName = g_things.getThingType(data[1]):getMarketData().name
            if #itemName == 0 then
                itemName = modules.game_actionbar.getItemNameById(data[1])
            end

            if #itemName == 0 or itemName == "this object" then
                itemName = "missing item name"
            end

            if searchText and not matchText(searchText, itemName) then
                goto continue
            end

            local widget = g_ui.createWidget('ItemListView', itemSummary.listView.listSummary)
            widget.name:setText(itemName)
            widget.item:setItemId(data[1])
            widget.count:setText(data[3])

            :: continue ::
        end
    end

    if inboxButton:isChecked() then
        for _, data in pairs(inboxList) do
            local itemName = g_things.getThingType(data[1]):getMarketData().name
            if #itemName == 0 then
                itemName = modules.game_actionbar.getItemNameById(data[1])
            end

            if #itemName == 0 or itemName == "this object" then
                itemName = "missing item name"
            end

            if searchText and not matchText(searchText, itemName) then
                goto continue
            end

            local widget = g_ui.createWidget('ItemListView', itemSummary.listView.listSummary)
            widget.name:setText(itemName)
            widget.item:setItemId(data[1])
            widget.count:setText(data[3])

            :: continue ::
        end
    end
end

function Character.onSummarySearch(widget)
    if itemSummary:recursiveGetChildById('showasgrid'):isChecked() then
        Character.showItemSummaryGrid(widget:getText())
    else
        Character.showItemSummaryList(widget:getText())
    end
end

---------------------------
--------- Appearences

function Character.onCyclopediaAppearances(outfits, oColors, mounts, mColors, familiars)
    if not Appearances or Appearances:isDestroyed() then
        return
    end
    appearancesList = {outfitList = outfits, outfitColors = oColors, mountList = mounts, mountColors = mColors, familiarList = familiars}
    Character.onShowAppearances()
end

function Character.onShowAppearances(onSort)
    local outfit = Appearances:recursiveGetChildById('outfits'):isChecked()
    local mount = Appearances:recursiveGetChildById('mounts'):isChecked()
    local familiar = Appearances:recursiveGetChildById('familiars'):isChecked()
    local currentList = (outfit and appearancesList.outfitList) or (mount and appearancesList.mountList) or appearancesList.familiarList
    if not currentList then
        return true
    end

    if not onSort then
        local options = {
            outfit = {"Show All", "Show Standard Outfits", "Show Quest Outfits", "Show Store Outfits"},
            mount = {"Show All", "Show Quest Mounts", "Show Store Mounts"},
            familiar = {"Show All", "Show Standard Familiars", "Show Quest Familiars"}
        }

        local optionBox = Appearances:recursiveGetChildById('showAllBox')
        optionBox:clear()

        if outfit then
            for _, k in pairs(options.outfit) do
                optionBox:addOption(k, nil, true)
            end
            optionBox:setCurrentOption(options.outfit[1], nil, true)

        elseif mount then
            for _, k in pairs(options.mount) do
                optionBox:addOption(k, nil, true)
            end
            optionBox:setCurrentOption(options.mount[1], nil, true)
        elseif familiar then
            for _, k in pairs(options.familiar) do
                optionBox:addOption(k, nil, true)
            end
            optionBox:setCurrentOption(options.familiar[1], nil, true)
        end
    end

    Appearances.listOutfit:destroyChildren()
    for _, data in pairs(currentList) do
        -- sort check
        if not Character.appearanceSort(data) then
            goto continue
        end

        local widget = g_ui.createWidget('CreatureAppearance', Appearances.listOutfit)
        if outfit or mount then
            widget.outfit:setOutfitId(data[1], data[3])
            widget.name:setText(data[2])

            if outfit then
                widget.store:setVisible(data[4] == 2)
                widget.outfit:setOutfitColors(appearancesList.outfitColors[1][1], appearancesList.outfitColors[1][2], appearancesList.outfitColors[1][3], appearancesList.outfitColors[1][4])
            elseif mount then
                widget.store:setVisible(data[3] == 2)
                widget.outfit:setOutfitColors(appearancesList.mountColors[1][1], appearancesList.mountColors[1][2], appearancesList.mountColors[1][3], appearancesList.mountColors[1][4])
            end
        end

        if familiar then
            widget.outfit:setOutfitId(data[1])
            widget.name:setText(data[2])
            if data[3] == 2 then
                widget.store:setVisible(true)
            end
        end

        :: continue ::
    end
end

function Character.appearanceSort(data)
    local outfit = Appearances:recursiveGetChildById('outfits'):isChecked()
    local mount = Appearances:recursiveGetChildById('mounts'):isChecked()
    local familiar = Appearances:recursiveGetChildById('familiars'):isChecked()
    local optionBox = windowPanel:recursiveGetChildById('showAllBox')
    local selectedOption = optionBox:getCurrentOption()

    if outfit then
        if selectedOption == "Show Standard Outfits" and data[4] ~= 1 then
            return false
        elseif selectedOption == "Show Quest Outfits" and data[4] ~= 1 then
            return false
        elseif selectedOption == "Show Store Outfits" and data[4] ~= 2 then
            return false
        end
    elseif mount then
        if selectedOption == "Show Quest Mounts" and data[3] ~= 1 then
            return false
        elseif selectedOption == "Show Store Mounts" and data[3] ~= 2 then
            return false
        end
    elseif mount then
        if selectedOption == "Show Standard Familiars" and data[3] ~= 0 then
            return false
        elseif selectedOption == "Show Quest Familiars" and data[3] ~= 2 then
            return false
        end
    end
    return true
end

function Character.onCyclopediaAchievements(achievementPoints, achievementSecrets, achievements)
	if not achievementWindow or achievementWindow:isDestroyed() or not achievementRadioGroup then
		return
	end
	achievementRadioGroup:selectWidget(achievementWindow:recursiveGetChildById('accomplished'), true)
	achievementsList = achievements
	for id, achievement in pairs(achievementsList) do
		local definition = getAchievementCatalog()[id]
		if definition and not achievement.secret then
			achievement.name = definition.name
			achievement.description = definition.description
			achievement.grade = definition.grade
		end
	end
	achievementWindow:recursiveGetChildById('achievementpointsvalue'):setText(achievementPoints)
	local achievementsGrade = {0, 0, 0, 0}
	local normalAchievement = 0
	local secretAchievement = 0

	displayAchievements = {}
	for _, achievement in pairs(achievementsList) do
		local grade = achievement.grade
		if not grade or not achievementsGrade[grade] then
			goto continue
		end

		achievementsGrade[grade] = achievementsGrade[grade] + 1
		if achievement.secret then
			secretAchievement = secretAchievement + 1
		else
			normalAchievement = normalAchievement + 1
		end

		displayAchievements[#displayAchievements + 1] = achievement
		:: continue ::
	end

	for i = 1, 4 do
		achievementWindow:recursiveGetChildById('gradevalue' .. i):setText(achievementsGrade[i])
	end

	local totalAchievements = 0
	for _, achievement in pairs(getAchievementCatalog()) do
		if not achievement.secret then
			totalAchievements = totalAchievements + 1
		end
	end
	achievementWindow:recursiveGetChildById('regularLabel'):setText( normalAchievement .. '/' .. totalAchievements)
	local regularProgress = achievementWindow:recursiveGetChildById('regularProgress')
	regularProgress:setPercent(totalAchievements > 0 and (normalAchievement / totalAchievements) * 100 or 0)

	achievementWindow:recursiveGetChildById('secretLabel'):setText(secretAchievement .. '/' .. achievementSecrets)
	local secretProgress = achievementWindow:recursiveGetChildById('secretProgress')
	secretProgress:setPercent(achievementSecrets > 0 and (secretAchievement / achievementSecrets) * 100 or 0)

	Character.createAchievementList(displayAchievements)
end

function Character.createAchievementList(achievements)
	achievementWindow.listAchievements:destroyChildren()

	local sortType = achievementWindow:recursiveGetChildById('sortBox')
	sortType.onOptionChange = function(self, optionText, optionValue)
		displayAchievements = achievements
		if optionText == "Alphabetically" then
			table.sort(displayAchievements, function(a, b) return a.name < b.name end)
		elseif optionText == "By Grade" then
			table.sort(displayAchievements, function(a, b) return a.grade > b.grade end)
		elseif optionText == "By Unlock Date" then
			table.sort(displayAchievements, function(a, b) return a.timestamp > b.timestamp end)
		end

		Character.createAchievementList(displayAchievements)
	end

	for _, achievement in pairs(achievements) do
		local widget = g_ui.createWidget('AchievementBox', achievementWindow.listAchievements)

		local grade = achievement.grade
		for _ = 1, grade do
			g_ui.createWidget('AchievementStar', widget.AchievementsStars)
		end

		widget.achievementName:setText(achievement.name)
		widget.achievementDescription:setText(achievement.description)
		widget.achievementDate:setText(os.date("%Y-%m-%d", achievement.timestamp))
		widget.achievementDate:setVisible(achievement.timestamp > 0)
		widget.achievementSecret:setVisible(achievement.secret)
	end
end

function AchievementSelectionChange(widget, selected)
	if not selected then
		return
	end

	displayAchievements = {}
	if selected:getId() == "accomplished" then
		for _, achievement in pairs(achievementsList) do
			displayAchievements[#displayAchievements + 1] = achievement
		end
		Character.createAchievementList(displayAchievements)
	elseif selected:getId() == "lockedAchievements" then
		for id, achievement in pairs(getAchievementCatalog()) do
			if not achievement.secret and not achievementsList[id] then
				local lockedAchievement = table.copy(achievement)
				lockedAchievement.id = id
				lockedAchievement.timestamp = 0
				displayAchievements[#displayAchievements + 1] = lockedAchievement
			end
		end

		Character.createAchievementList(displayAchievements)
	elseif selected:getId() == "allAchievements" then
		for id, achievement in pairs(getAchievementCatalog()) do
			if achievementsList[id] then
				displayAchievements[#displayAchievements + 1] = achievementsList[id]
			elseif not achievement.secret then
				local lockedAchievement = table.copy(achievement)
				lockedAchievement.id = id
				lockedAchievement.timestamp = 0
				displayAchievements[#displayAchievements + 1] = lockedAchievement
			else
				-- Locked secret achievements must stay hidden.
			end
		end
		Character.createAchievementList(displayAchievements)
	end
end
