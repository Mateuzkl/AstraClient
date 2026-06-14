podiumWindow = nil

local monsterList = nil
local previewGround = nil
local previewCreature = nil
local searchField = nil
local currentCreature = nil

local showoffOutfit = {}
local isBossPoduim = nil
local position = nil
local showCreature = nil
local podiumVisible = nil
local podiumDirection = nil
local thingID = nil
local thingStackPos = 0

local podiumItem = nil
local currentOutfit = nil
local lastChecked = nil
local originalShowCreature = nil
local currentRaceID = 0

local bossList = {}
local creatureList = {}

local function findCurrentRaceId(outfit)
	if not outfit then
		return 0
	end

	for raceId, creatureData in pairs(g_things.getMonsterList() or {}) do
		local sameLookType = outfit.type and outfit.type ~= 0 and creatureData[2] == outfit.type
		local sameLookTypeEx = outfit.auxType and outfit.auxType ~= 0 and creatureData[3] == outfit.auxType
		if sameLookType or sameLookTypeEx then
			return raceId
		end
	end
	return 0
end

function init()
  podiumWindow = g_ui.displayUI('mpodium.otui')
  podiumWindow:hide()

  previewGround = podiumWindow:recursiveGetChildById('PreviewGround')
  previewCreature = podiumWindow:recursiveGetChildById('previewCreature')
  monsterList = podiumWindow:recursiveGetChildById('monsterList')
  searchField = podiumWindow:recursiveGetChildById('searchfiltercreatures')

  connect(g_game, {
	onParseMonsterPodium = onParseMonsterPodium
  })
end

function terminate()
  podiumWindow:hide()
  selectedOption = nil
  searchFilterCharmText = ''

  disconnect(g_game, {
  	onParseMonsterPodium = onParseMonsterPodium
  })
end

function hide()
	if previewCreature then
		previewCreature:setVisible(false)
		previewCreature:setOutfit({})
	end
	searchField:clearText()
	currentOutfit = nil
	lastChecked = nil
	currentRaceID = 0
	if podiumWindow and podiumWindow:isVisible() then
		podiumWindow:hide()
	end
end

function requestMonsterData(thing)
	thingID = thing:getId()
	thingStackPos = thing:getStackPos()
	g_game.use(thing)
	monsterList:destroyChildren()
end

function onParseMonsterPodium(currentOutfit, currentID, podiumBoss, bosses, monsters, pos, itemID, stackPos, showPodium, isShowingCreature, direction)
	if not podiumWindow:isVisible() then
		podiumWindow:show()
		podiumWindow:focus()
	end

	currentRaceID = currentID ~= 0 and currentID or findCurrentRaceId(currentOutfit)
	showoffOutfit = currentOutfit
    isBossPoduim = podiumBoss
	position = pos
	thingID = itemID
	thingStackPos = stackPos
	showCreature = isShowingCreature
	originalShowCreature = isShowingCreature
	podiumVisible = showPodium
	podiumDirection = direction

	bossList = bosses
	creatureList = monsters

	previewGround.item:setItemId(itemID)
	podiumItem = previewGround.item:getItem()

	local showFloor = podiumWindow:recursiveGetChildById('ShowFloor')
	showFloor.floor:setChecked(true)

	local creatureShow = podiumWindow:recursiveGetChildById('creatureShow')
	creatureShow:setChecked(showCreature)

	local podiumShow = podiumWindow:recursiveGetChildById('podium')
	podiumShow:setChecked(podiumVisible)

	showMonsterPodium()
end

function showMonsterPodium(filter)
	podiumItem = previewGround.item:getItem()
	if not podiumItem or not previewCreature then
		return
	end

	if showoffOutfit.type ~= 128 then
		currentOutfit = showoffOutfit
	end

	if showCreature and currentOutfit then
		previewCreature:setVisible(true)
		previewCreature:setOutfit(currentOutfit)
		previewCreature:setDirection(podiumDirection)
	else
		previewCreature:setVisible(false)
	end

	previewGround.item:setVisible(podiumVisible)

	local creatures = g_things.getMonsterList()
	if isBossPoduim then
		for k, v in pairs(bossList) do
			local name = string.capitalize(v)
			if filter and not matchText(filter, name:lower()) then
				goto continue
			end

			local widget = g_ui.createWidget('PodiumCreatureBox', monsterList)
			widget.checkBox.name:setText(name)
			if widget.checkBox.name:isTextWraped() then
				widget.checkBox.name:setMarginTop(32)
			end

			if not creatures[k] then
				widget:destroy()
				goto continue
			end
			widget.checkBox.creature:setRaceID(k)
			widget.checkBox.creature:setOutfit({type = creatures[k][2], auxType = creatures[k][3], head = creatures[k][4], body = creatures[k][5], legs = creatures[k][6], feet = creatures[k][7], addons = creatures[k][8]})

			:: continue ::
		end
	else
		for _, v in pairs(creatureList) do
			local currentRace = creatures[v]
			if not currentRace then
				goto continue
			end
			if filter and not matchText(filter, currentRace[1]:lower()) then
				goto continue
			end

			local widget = g_ui.createWidget('PodiumCreatureBox', monsterList)
			widget.checkBox.name:setText(currentRace[1])
			if widget.checkBox.name:isTextWraped() then
				widget.checkBox.name:setMarginTop(32)
			end

			widget.checkBox.creature:setRaceID(v)
			widget.checkBox.creature:setOutfit({type = currentRace[2], auxType = currentRace[3], head = currentRace[4], body = currentRace[5], legs = currentRace[6], feet = currentRace[7], addons = currentRace[8]})

			:: continue ::
		end
	end
end

--- buttons
function showFloor(checked)
	if checked then
		previewGround:setImageSource('/images/game/outfit_ground')
	else
		previewGround:setImageSource('images/ui/panel-background')
	end
end

function showCreatureOutfit(checked)
	showCreature = checked
	if not previewCreature then
		return
	end

	if checked then
		previewCreature:setVisible(true)
		previewCreature:setOutfit(currentOutfit or {})
		previewCreature:setDirection(podiumDirection)
	else
		previewCreature:setVisible(false)
	end
end

function showPodiumItem(checked)
	podiumVisible = checked
	previewGround.item:setVisible(checked)
end

function onCheckBox(widget, parentClick)
	local current = widget
	if parentClick then
		current = widget:recursiveGetChildById('creature')
		if lastChecked then
			lastChecked:setChecked(false)
		end
		lastChecked = widget
		widget:setChecked(true)
	else
		if lastChecked then
			lastChecked:setChecked(false)
		end
		lastChecked = widget:getParent()
		lastChecked:setChecked(true)
	end

	currentOutfit = current:getOutfit()
	currentRaceID = current:getRaceID()

	previewCreature:setOutfit(current:getOutfit())

	if showCreature then
		previewCreature:setVisible(true)
	end
end

function onChangeDirection(isRight)
	if not previewCreature then
		return
	end
	local currentDirection = podiumDirection or 2

	if isRight then
		if currentDirection == 0 then
			podiumDirection = 3
		else
			podiumDirection = currentDirection - 1
		end
	else
		if currentDirection >= 3 then
			podiumDirection = 0
		else
			podiumDirection = currentDirection + 1
		end
	end
	previewCreature:setDirection(podiumDirection)
end

function onSelectCreature()
	if not podiumItem then
		return
	end

	if not currentRaceID or currentRaceID == 0 then
		previewCreature:setVisible(false)
	end

	if not showCreature then
		currentRaceID = 0
	end

	g_game.sendMonsterPodiumOutfit(currentRaceID, position, thingID, thingStackPos, podiumDirection,
		podiumVisible, showCreature)
	hide()
end

-- Search function
function onSearchChange(self)
	monsterList:destroyChildren()
	if #self:getText() == 0 then
		showMonsterPodium()
		return
	end
	showMonsterPodium(self:getText())
end
