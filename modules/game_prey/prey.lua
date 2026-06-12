preyWindow = nil
preyButton = nil
preyWindowButton = nil
preyTracker = nil

local timeLeftRerrol = {}

local creatureList = {}
local onWildcardValueChange = nil
local itemListMin = {}
local itemListMax = {}
local itemSize = {}
local maxFitItems = {}
local poolSize = {}
local itemsPool = {}
local currentRaces = {}
local currentSearchRaces = {}
local lastSelectedLabel = {}
local selectedMonster = {}

local updateRerollEvent = nil
local supportWindow = nil
local preyTrackerButton
local monsterList
local bankGold = 0
local inventoryGold = 0
local rerollPrice = 0
local bonusRerolls = 0

local PREY_BONUS_DAMAGE_BOOST = 0
local PREY_BONUS_DAMAGE_REDUCTION = 1
local PREY_BONUS_XP_BONUS = 2
local PREY_BONUS_IMPROVED_LOOT = 3
local PREY_BONUS_NONE = 4

local PREY_ACTION_LISTREROLL = 0
local PREY_ACTION_BONUSREROLL = 1
local PREY_ACTION_MONSTERSELECTION = 2
local PREY_ACTION_REQUEST_ALL_MONSTERS = 3
local PREY_ACTION_CHANGE_FROM_ALL = 4
local PREY_ACTION_LOCK_PREY = 5
local PREY_ACTION_UNLOCK_PERMANENT = 6

local SLOT_STATE_LOCKED = 0
local SLOT_STATE_INACTIVE = 1
local SLOT_STATE_ACTIVE = 2
local SLOT_STATE_SELECTION = 3
local SLOT_STATE_WILDCARD = 4

local PREY_UNLOCK_NONE = 2

local PREY_OPCODE_DATA = 0xE8
local PREY_OPCODE_PRICES = 0xE9

local WILDCARD_LABEL_HEIGHT = 16
local WILDCARD_VISIBLE_LABELS = 11

local preyDescription = {}
local searchFilterText = ''

local function readPreyOutfit(msg)
  local outfit = { type = msg:getU16() }
  if outfit.type == 0 then
    outfit.auxType = msg:getU16()
    return outfit
  end

  outfit.head = msg:getU8()
  outfit.body = msg:getU8()
  outfit.legs = msg:getU8()
  outfit.feet = msg:getU8()
  outfit.addons = msg:getU8()
  return outfit
end

local function readTimeUntilFreeReroll(msg)
  if g_game.getProtocolVersion() >= 1252 then
    return msg:getU32()
  end
  return msg:getU16()
end

local function readPreyLockType(msg)
  if g_game.getFeature(GameTibia12Protocol) then
    return msg:getU8()
  end
  return 0
end

local function parsePreyData(protocol, msg)
  local slot = msg:getU8()
  local state = msg:getU8()

  if state == SLOT_STATE_LOCKED then
    local unlockState = msg:getU8()
    local timeUntilFreeReroll = readTimeUntilFreeReroll(msg)
    local lockType = readPreyLockType(msg)
    local permanentPrice = msg:getU32()
    signalcall(g_game.onPreyLocked, slot, unlockState, timeUntilFreeReroll, lockType, permanentPrice)
  elseif state == SLOT_STATE_INACTIVE then
    local timeUntilFreeReroll = readTimeUntilFreeReroll(msg)
    local lockType = readPreyLockType(msg)
    signalcall(g_game.onPreyInactive, slot, timeUntilFreeReroll, lockType)
  elseif state == SLOT_STATE_ACTIVE then
    local name = msg:getString()
    local outfit = readPreyOutfit(msg)
    local bonusType = msg:getU8()
    local bonusValue = msg:getU16()
    local bonusGrade = msg:getU8()
    local timeLeft = msg:getU16()
    local timeUntilFreeReroll = readTimeUntilFreeReroll(msg)
    local lockType = readPreyLockType(msg)
    signalcall(g_game.onPreyActive, slot, name, outfit, bonusType, bonusValue, bonusGrade, timeLeft, timeUntilFreeReroll, lockType)
  elseif state == SLOT_STATE_SELECTION then
    local names = {}
    local outfits = {}
    local count = msg:getU8()
    for i = 1, count do
      names[i] = msg:getString()
      outfits[i] = readPreyOutfit(msg)
    end
    local timeUntilFreeReroll = readTimeUntilFreeReroll(msg)
    local lockType = readPreyLockType(msg)
    signalcall(g_game.onPreySelection, slot, PREY_BONUS_NONE, -1, -1, names, outfits, timeUntilFreeReroll, lockType)
  else
    g_logger.error("Unknown prey data state: " .. state)
  end
end

local function parsePreyPrices(protocol, msg)
  local price = msg:getU32()
  local wildcard = -1
  local directly = -1
  if g_game.getFeature(GameTibia12Protocol) then
    wildcard = msg:getU8()
    directly = msg:getU8()
  end
  signalcall(g_game.onPreyPrice, price, wildcard, directly)
end

function bonusDescription(bonusType, bonusValue, bonusGrade)
  if bonusType == PREY_BONUS_DAMAGE_BOOST then
    return "Damage bonus (" .. bonusGrade .. "/10)"
  elseif bonusType == PREY_BONUS_DAMAGE_REDUCTION then
    return "Damage reduction bonus (" .. bonusGrade .. "/10)"
  elseif bonusType == PREY_BONUS_XP_BONUS then
    return "XP bonus (" .. bonusGrade .. "/10)"
  elseif bonusType == PREY_BONUS_IMPROVED_LOOT then
    return "Loot bonus (" .. bonusGrade .. "/10)"
  elseif bonusType == PREY_BONUS_DAMAGE_BOOST then
    return "-"
  end
  return "Uknown bonus"
end

function bonusTypeTranslate(bonusType)
   if bonusType == PREY_BONUS_DAMAGE_BOOST then
    return "Damage Boost"
  elseif bonusType == PREY_BONUS_DAMAGE_REDUCTION then
    return "Damage Reduction"
  elseif bonusType == PREY_BONUS_XP_BONUS then
    return "Bonus XP"
  elseif bonusType == PREY_BONUS_IMPROVED_LOOT then
    return "Improved Loot"
  end
  return "None"
end

function bonusTypeTranslateText(bonusType, percent)
  local text = "No active bonus."
  if bonusType == PREY_BONUS_DAMAGE_BOOST then
    text = tr("You deal +%s%s extra damage against your prey creature.", percent, "%")
  elseif bonusType == PREY_BONUS_DAMAGE_REDUCTION then
    text = tr("You take %s%s less damage from your prey creature.", percent, "%")
  elseif bonusType == PREY_BONUS_XP_BONUS then
    text = tr("Killing you prey creature rewards +%s%s extra XP.", percent, "%")
  elseif bonusType == PREY_BONUS_IMPROVED_LOOT then
    text = tr("Your prey creature has a +%s%s chance do drop additional loot.", percent, "%")
  end
  return text
end

function timeleftTranslation(timeleft)
  if timeleft == 0 then
    return tr("Free")
  end
  local hours = string.format("%02.f", math.floor(timeleft/3600))
  local mins = string.format("%02.f", math.floor(timeleft/60 - (hours*60)))
  return hours .. ":" .. mins
end

function init()
  ProtocolGame.unregisterOpcode(PREY_OPCODE_DATA)
  ProtocolGame.unregisterOpcode(PREY_OPCODE_PRICES)
  ProtocolGame.registerOpcode(PREY_OPCODE_DATA, parsePreyData)
  ProtocolGame.registerOpcode(PREY_OPCODE_PRICES, parsePreyPrices)

  connect(g_game, {
    onGameStart = check,
    onGameEnd = hide,
    onResourceBalance = onResourceBalance,
    onPreyFreeRolls = onPreyFreeRolls,
    onPreyTimeLeft = onPreyTimeLeft,
    onPreyPrice = onPreyPrice,
    onPreyLocked = onPreyLocked,
    onPreyWildcard = onPreyWildcard,
    onPreyInactive = onPreyInactive,
    onPreyActive = onPreyActive,
    onPreySelection = onPreySelection
  })

  preyWindow = g_ui.displayUI('prey')
  preyWindow:hide()
  preyTracker = g_ui.createWidget('PreyTracker')
  preyTracker:setup()
  preyTracker:setContentMaximumHeight(112)
  preyTracker:setContentMinimumHeight(47)
  preyTracker:close()

  preyWindowButton = preyWindow:recursiveGetChildById("preyWindowButton")

  if g_game.isOnline() then
    check()
  end
  -- setUnsupportedSettings()
end

local descriptionTable = {
  ["shopPermButton"] = "Go to the Store to purchase the Permanent Prey Slot. Once you have completed the purchase, you can activate a prey here, no matter if your character is on a free or a Premium account.",
  ["shopTempButton"] = "You can activate this prey whenever your account has Premium Status.",
  ["preyWindow"] = "",
  ["noBonusIcon"] = "This prey is not available for your character yet.\nCheck the large blue button(s) to learn how to unlock this prey slot",
  ["selectPrey"] = "Click here to get a bonus with a higher value. The bonus for your prey will be selected randomly from one of the following: damage boost, damage reduction, bonus XP, improved loot. Your prey will be active for 2 hours hunting time again. Your prey creature will stay the same.",
  ["pickSpecificPrey"] = "If you like to select another prey creature, click here to choose from all available creatures.\nThe newly selected prey will be active for 2 hours hunting time again.",
  ["rerollButton"] = "If you like to select another prey crature, click here to get a new list with 9 creatures to choose from.\nThe newly selected prey will be active for 2 hours hunting time again.",
  ["rerollButtonBonus"] = "If you like to select another prey crature, click here to get a new list with 9 creatures to choose from.\nThe newly selected prey will be active for 2 hours hunting time again.",
  ["preyCandidate"] = "Select a new prey creature for the next 2 hours hunting time.",
  ["choosePreyButton"] = "Click on this button to confirm selected monsters as your prey creature for the next 2 hours hunting time.",
  ["choosePreyButtonBonus"] = "Click on this button to confirm %s as your prey creature for the next 2 hours hunting time. You will benefit from the following bonus: %s",
  ["selectionList"] = "Select a new prey creature for the next 2 hours hunting time. You will benefit from the following bonus:",
  ["rerollBonus"] = "Click here to get a bonus with a higher value. The bonus for your prey will be selected randomly from one of the following: damage boost, damage reduction, bonus XP, improved loot. Your prey will be active for 2 hours hunting time again. Your prey creature will stay the same.",
  ["autoRerollCheck"] = "If you tick this option, you will automatically roll for a new prey bonus whenever your prey is about to expire. This will also extend the hunting time of your active prey creature for another 2 hours.",
  ["lockPreyCheck"] = "If you tick this option, you will lock your prey creature and prey bonus. This means whenever your prey is about to expire its hunting time is simply extended by another 2 hours.",
  ["time"] = "You will get your next Free List Reroll in %s.\nYou get a Free List Reroll every 20 hours for each slot.",
  ["time_free"] = "Your next List Reroll is free of charge.\nYou get a Free List Reroll every 20 hours for each slot."
}

function onHover(widget)
  if type(widget) == "string" then
    return preyWindow.description:setText(descriptionTable[widget])
  elseif type(widget) == "number" then
    local preySlot = preyWindow["slot" .. (widget + 1)]
    local creatureAndBonus = preySlot.active.creatureAndBonus
    local preyName = preySlot.title:getText()
    local timeleft = timeleftTranslation(preySlot.timeLeft)
    local typeDesc = bonusTypeTranslate(preySlot.bonusType)
    local bonusDescription = bonusTypeTranslateText(preySlot.bonusType, preySlot.bonusValue)
    local starBonus = ""
    for i = 1, 10 do
      if i <= preySlot.bonusGrade then
        starBonus = starBonus .. "^"
      else
        starBonus = starBonus .. ";"
      end
    end

    local text = tr("Creature: %s\nDuration: %s\nValue: %s\nType: %s\n%s", preyName, timeleft, starBonus, typeDesc, bonusDescription)
    return preyWindow.description:setText(text)
  end

  if not widget:isVisible() then
    return false
  end

  local id = widget:getId()
  local desc = descriptionTable[id]
  if not desc then
    return
  end

  if id == "choosePreyButton" and widget:getActionId() > 0 then
    local preySlot = preyWindow["slot" .. widget:getActionId()]
    local bonusType = preySlot.bonusType
    local bonusValue = preySlot.bonusValue
    if bonusType > 0 then
      -- wildcard
      if preySlot.wildcard:isVisible() and preySlot.wildcard.monsterList:getFocusedChild() then
        local name = preySlot.wildcard.monsterList:getFocusedChild():getText()
        local bonusDesc = tr("+%s%s %s", bonusValue, "%", getBonusDescription(bonusType))
        desc = tr(descriptionTable["choosePreyButtonBonus"], name, bonusDesc)
      elseif preySlot.select:isVisible() then
        local focusedChild = preySlot.select.list:getFocusedChild()
        if not focusedChild then
          focusedChild = preySlot.select.list:getFirstChild()
        end
        if focusedChild then
          local bonusDesc = tr("+%s%s %s", bonusValue, "%", getBonusDescription(bonusType))
          desc = tr(descriptionTable["choosePreyButtonBonus"], focusedChild.creature:getTooltip(), bonusDesc)
        end
      end
    end
  elseif id == "time" then
    local widgetText = widget:getText()
    if widgetText == "Free" then
      desc = descriptionTable["time_free"]
    else
      desc = tr(desc, widget:getText())
    end
  end

  preyWindow.description:setText(desc)
end

function onSpecialHover(widget, bonusType, bonusValue)
	local message = descriptionTable[widget]
	if widget == "selectionList" then
    if bonusType == PREY_BONUS_NONE then
      preyWindow.description:setText(descriptionTable["selectPrey"])
    else
      message = tr("%s +%s%s %s", message, bonusValue, "%", getBonusDescription(bonusType))
      preyWindow.description:setText(message)
    end
	end
end

function terminate()
  ProtocolGame.unregisterOpcode(PREY_OPCODE_DATA)
  ProtocolGame.unregisterOpcode(PREY_OPCODE_PRICES)

  disconnect(g_game, {
    onGameStart = check,
    onGameEnd = hide,
    onResourceBalance = onResourceBalance,
    onPreyFreeRolls = onPreyFreeRolls,
    onPreyTimeLeft = onPreyTimeLeft,
    onPreyPrice = onPreyPrice,
    onPreyLocked = onPreyLocked,
    onPreyWildcard = onPreyWildcard,
    onPreyInactive = onPreyInactive,
    onPreyActive = onPreyActive,
    onPreySelection = onPreySelection
  })

  if preyButton then
    preyButton:destroy()
  end
  if preyTrackerButton then
    preyTrackerButton:destroy()
  end
  preyWindow:destroy()
  preyTracker:destroy()
  if supportWindow then
    supportWindow:destroy()
    supportWindow = nil
  end
end

function setUnsupportedSettings()
  local t = {"slot1", "slot2", "slot3"}
  for i, slot in pairs(t) do
    local panel = preyWindow[slot]
    for j, state in pairs({panel.active, panel.inactive, panel.select}) do
      state.buttonsPanel.select.price.text:setText("5")
      state:recursiveGetChildById("pickSpecificPrey"):setOn(true)
      state.buttonsPanel.select.price.text:setColor("#c0c0c0")
      if bonusRerolls < 5 then
        state.buttonsPanel.select.price.text:setColor("#d33c3c")
        state:recursiveGetChildById("pickSpecificPrey"):setOn(false)
      end

      state:recursiveGetChildById("pickSpecificPrey").onClick = function()
        if not state:recursiveGetChildById("pickSpecificPrey"):isOn() then
          return
        end

        if bonusRerolls - 5 < 0 then
          return
        end
        onConfirmUsingWildcard(i - 1, 5, PREY_ACTION_REQUEST_ALL_MONSTERS)
      end

      state.buttonsPanel.reroll.button.rerollButton:setOn(true)
      state.buttonsPanel.reroll.price.text:setColor("#c0c0c0")
      local progressBar = state.buttonsPanel.reroll.button.time
      if (bankGold + inventoryGold < rerollPrice and progressBar:getText() ~= "Free") then
        state.buttonsPanel.reroll.price.text:setColor("#d33c3c")
        state.buttonsPanel.reroll.button.rerollButton:setOn(false)
      end
      -- hotfix
      progressBar:setPercent(progressBar:getPercent())
    end

    for k, state in pairs({panel.active, panel.inactive}) do
      state.buttonsPanel.choose.price.text:setText("1")
      state.buttonsPanel.choose.price.text:setColor("#c0c0c0")
      state:recursiveGetChildById("rerollBonus"):setOn(true)
      state:recursiveGetChildById("rerollBonus").onClick = function()
        if not state:recursiveGetChildById("rerollBonus"):isOn() then
          return
        end
        onConfirmUsingWildcard(i - 1, 1, PREY_ACTION_BONUSREROLL)
      end

      if bonusRerolls < 1 then
        state.buttonsPanel.choose.price.text:setColor("#d33c3c")
        state:recursiveGetChildById("rerollBonus"):setOn(false)
      end

      state.buttonsPanel.autoRerollPrice.text:setText("1")
      state.buttonsPanel.autoRerollPrice.text:setColor("#c0c0c0")
      if bonusRerolls < 1 then
        state.buttonsPanel.autoRerollPrice.text:setColor("#d33c3c")
      end

      state.buttonsPanel.lockPreyPrice.text:setText("5")
      state.buttonsPanel.lockPreyPrice.text:setColor("#c0c0c0")
      if bonusRerolls < 5 then
        state.buttonsPanel.lockPreyPrice.text:setColor("#d33c3c")
      end

      state.buttonsPanel.autoReroll.autoRerollCheck.onClick = function()
        if state.buttonsPanel.autoReroll.autoRerollCheck:isChecked() then
          g_game.preyAction(i - 1, PREY_ACTION_LOCK_PREY, 0)
        else
          onEnableAutoReroll(i - 1)
        end
      end

      state.buttonsPanel.lockPrey.lockPreyCheck.onClick = function()
        if state.buttonsPanel.lockPrey.lockPreyCheck:isChecked() then
          g_game.preyAction(i - 1, PREY_ACTION_LOCK_PREY, 0)
        else
          onEnableLockPrey(i - 1)
        end
      end

      state.buttonsPanel.autoReroll.autoRerollCheck:setChecked(false)
      state.buttonsPanel.lockPrey.lockPreyCheck:setChecked(false)
      if panel.lockType == 1 then
        state.buttonsPanel.autoReroll.autoRerollCheck:setChecked(true)
      elseif panel.lockType == 2 then
        state.buttonsPanel.lockPrey.lockPreyCheck:setChecked(true)
      end
    end
  end
end

function check()
  local benchmark = g_clock.millis()
  creatureList = g_things.getMonsterList()
  if g_game.getFeature(GamePrey) then
    if not preyButton then
      preyButton = modules.client_topmenu.addRightGameToggleButton('preyButton', tr('Prey Dialog'), '/images/icons/icon-preydialogue', toggle)
    end
    if not preyTrackerButton then
      preyTrackerButton = modules.client_topmenu.addRightGameToggleButton("preyTrackerButton", tr('Prey Tracker'), '/images/icons/icon-prey-widget', toggleTracker)
    end
  elseif preyButton then
    preyButton:destroy()
    preyButton = nil
  end
  consoleln("Prey loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function toggleTracker()
  if preyTracker:isVisible() then
    preyTracker:close()
  else
    if not m_interface.addToPanels(preyTracker) then
      modules.game_sidebuttons.setButtonVisible("preyWidget", false)
      return false
    end
    preyTracker:open()
    preyTracker:getParent():moveChildToIndex(preyTracker, #preyTracker:getParent():getChildren())
  end
end

function hide(ignoreTracker)
  creatureList = nil
  preyWindow:hide()
  if not ignoreTracker then
    preyTracker:close()
    preyTracker:setParent(nil)
  end
  g_client.setInputLockWidget(nil)
  preyWindowButton:setChecked(false)
  if supportWindow then
    supportWindow:destroy()
    supportWindow = nil
  end

  if updateRerollEvent then
    removeEvent(updateRerollEvent)
    updateRerollEvent = nil
  end
end

function show(position)
  if not g_game.getFeature(GamePrey) then
    return hide()
  end
  if preyWindow:isVisible() then
    preyWindow:raise()
    preyWindow:focus()
    return
  end
  preyWindowButton:setChecked(true)
  setUnsupportedSettings()
  preyWindow:show(true)
  preyWindow:raise()
  preyWindow:focus()
  g_client.setInputLockWidget(preyWindow)
  if position ~= nil then
    preyWindow:setPosition(position)
  end

  g_game.preyRequest()

	local localPlayer = g_game.getLocalPlayer()
	onResourceBalance(ResourceBank, localPlayer:getResourceValue(ResourceBank))
	onResourceBalance(ResourceInventary, localPlayer:getResourceValue(ResourceInventary))
	onResourceBalance(ResourcePreyBonus, localPlayer:getResourceValue(ResourcePreyBonus))

  if creatureList == nil then
    creatureList = g_things.getMonsterList()
  end
  updateWildCardWindow()

  if updateRerollEvent then
    removeEvent(updateRerollEvent)
  end
  updateRerollEvent = cycleEvent(function() updateRerollTime() end, 1000)
end

function toggle()
  if preyWindow:isVisible() then
    return hide(true)
  end
  show()
end

function onPreyFreeRolls(slot, timeleft)
  local prey = preyWindow["slot" .. (slot + 1)]
  local percent = (timeleft / (20 * 60)) * 100
  local desc = timeleftTranslation(timeleft * 60)
  if not prey then return end
  for i, panel in pairs({prey.active, prey.inactive}) do
    local progressBar = panel.reroll.button.time
    local price = panel.reroll.price.text
    progressBar:setText(desc)
    if timeleft == 0 then
      price:setText("Free")
    end
    progressBar:setPercent(percent)
  end
end

function onPreyTimeLeft(slot, timeLeft)
  -- description
  preyDescription[slot] = preyDescription[slot] or {one = "", two = ""}
  local text = preyDescription[slot].one .. timeleftTranslation(timeLeft) .. preyDescription[slot].two
  -- tracker
  local preyTrackerSlot = preyTracker.contentsPanel["slot" .. (slot + 1)]
  local updatedTime = string.gsub(preyTrackerSlot:getTooltip(), "[^\n]*Duration: [^\n]*\n?", "Duration: " .. timeleftTranslation(timeLeft) .. "\n")
  preyTrackerSlot:setTooltip(updatedTime)

  local percent = (timeLeft / (2 * 60 * 60)) * 100
  slot = "slot" .. (slot + 1)
  local tracker = preyTracker.contentsPanel[slot]
  tracker.time:setPercent(percent)
  for i, element in pairs({tracker.creatureName, tracker.creature, tracker.preyType, tracker.time}) do
    element:setTooltip(text)
    element.onClick = function()
      show()
    end
  end
  -- main window
  local prey = preyWindow[slot]
  if not prey then return end
  local progressbar = prey.active.creatureAndBonus.timeLeft
  local textLabel = prey.active.creatureAndBonus.textLabel
  local desc = timeleftTranslation(timeLeft, true)
  textLabel:setText(desc)
  progressbar:setPercent(percent)
end

function onPreyPrice(price, wildcard, directly)
  rerollPrice = price
  local t = {"slot1", "slot2", "slot3"}
  for i, slot in pairs(t) do
    local panel = preyWindow[slot]
    for j, state in pairs({panel.active, panel.inactive, panel.select}) do
      local priceWidget = state.buttonsPanel.reroll.price.text
      local progressBar = state.buttonsPanel.reroll.button.time
      if progressBar:getText() ~= "Free" then
        local formatedPrice = price < 100000 and comma_value(price) or math.ceil(price / 1000) .. "k"
        priceWidget:setText(formatedPrice)
        state.buttonsPanel.reroll.price.textOff:setVisible(false)
      else
        priceWidget:setText("0")
        state.buttonsPanel.reroll.price.textOff:setVisible(false)
        progressBar:setPercent(0)
      end
    end
  end

  setUnsupportedSettings()
end

function setTimeUntilFreeReroll(slot, timeUntilFreeReroll) -- minutes
  timeLeftRerrol[slot] = {minutesLeft = timeUntilFreeReroll, startTime = os.time()}

  local prey = preyWindow["slot"..(slot + 1)]
  if not prey then return end
  local percent = (timeUntilFreeReroll / (20 * 60)) * 100
  local desc = timeleftTranslation(timeUntilFreeReroll * 60)
  for i, panel in pairs({prey.active, prey.inactive, prey.select}) do
    local reroll = panel.buttonsPanel.reroll.button.time
    reroll:setPercent(percent)
    reroll:setText(desc)
    local price = panel.buttonsPanel.reroll.price.text
    if timeUntilFreeReroll > 0 then
      local formatedPrice = rerollPrice < 100000 and comma_value(rerollPrice) or math.ceil(rerollPrice / 1000) .. "k"
      price:setText(formatedPrice)
      panel.buttonsPanel.reroll.price.textOff:setVisible(false)
    else
      price:setText("0")
      panel.buttonsPanel.reroll.price.textOff:setVisible(false)
    end

    panel.buttonsPanel.reroll.button.rerollButton.onClick = function()
      if not panel.buttonsPanel.reroll.button.rerollButton:isOn() then
        return
      end
      onRerollButtonAction(slot, timeUntilFreeReroll <= 0)
    end
  end
end

function setBonusGradeStars(slot, grade)
  local prey = preyWindow["slot"..(slot + 1)]
  local gradePanel = prey.active.creatureAndBonus.bonus.grade

  gradePanel:destroyChildren()
  for i=1,10 do
    if i <= grade then
      local widget = g_ui.createWidget("Star", gradePanel)
      widget.onHoverChange = function(widget,hovered)
        onHover(slot)
      end
    else
      local widget = g_ui.createWidget("NoStar", gradePanel)
      widget.onHoverChange = function(widget,hovered)
        onHover(slot)
      end
    end
  end
end

function getBigIconPath(bonusType)
  local path = "/images/game/prey/"
  if bonusType == PREY_BONUS_DAMAGE_BOOST then
    return path.."prey_bigdamage"
  elseif bonusType == PREY_BONUS_DAMAGE_REDUCTION then
    return path.."prey_bigdefense"
  elseif bonusType == PREY_BONUS_XP_BONUS then
    return path.."prey_bigxp"
  elseif bonusType == PREY_BONUS_IMPROVED_LOOT then
    return path.."prey_bigloot"
  end
end

function getSmallIconPath(bonusType)
  local path = "/images/game/prey/"
  if bonusType == PREY_BONUS_DAMAGE_BOOST then
    return path.."prey_damage"
  elseif bonusType == PREY_BONUS_DAMAGE_REDUCTION then
    return path.."prey_defense"
  elseif bonusType == PREY_BONUS_XP_BONUS then
    return path.."prey_xp"
  elseif bonusType == PREY_BONUS_IMPROVED_LOOT then
    return path.."prey_loot"
  end
  return path .. "prey_no_bonus"
end

function getExtendIcon(lockType)
  local path = "/images/game/prey/"
  local player = g_game.getLocalPlayer()
  if not player then
    return path .. "prey-auto-extend-disabled"
  end

  local balance = player:getResourceValue(ResourcePreyBonus)
  if lockType == 1 then
    return balance < 1 and (path .. "prey-auto-reroll-enabled-failing") or (path .. "prey-auto-reroll-enabled")
  elseif lockType == 2 then
    return balance < 5 and (path .. "prey-lock-prey-enabled-failing") or (path .. "prey-lock-prey-enabled")
  end
  return path .. "prey-auto-extend-disabled"
end

function getBonusDescription(bonusType)
  if bonusType == PREY_BONUS_DAMAGE_BOOST then
    return "Damage Boost"
  elseif bonusType == PREY_BONUS_DAMAGE_REDUCTION then
    return "Damage Reduction"
  elseif bonusType == PREY_BONUS_XP_BONUS then
    return "XP Bonus"
  elseif bonusType == PREY_BONUS_IMPROVED_LOOT then
    return "Improved Loot"
  end
  return "None"
end

function getTooltipBonusDescription(bonusType, bonusValue)
  if bonusType == PREY_BONUS_DAMAGE_BOOST then
    return "You deal +"..bonusValue.."% extra damage against your prey creature."
  elseif bonusType == PREY_BONUS_DAMAGE_REDUCTION then
    return "You take "..bonusValue.."% less damage from your prey creature."
  elseif bonusType == PREY_BONUS_XP_BONUS then
    return "Killing your prey creature rewards +"..bonusValue.."% extra XP."
  elseif bonusType == PREY_BONUS_IMPROVED_LOOT then
    return "Your creature has a +"..bonusValue.."% chance to drop additional loot."
  end
end

function capitalFormatStr(str)
  local formatted = ""
  str = string.split(str, " ")
  for i, word in ipairs(str) do
    formatted = formatted .. " " .. (string.gsub(word, "^%l", string.upper))
  end
  return formatted:trim()
end

function onItemBoxChecked(widget, lastWidget, slot)
  if not widget then
    return
  end

  if lastWidget and lastWidget.highlight then
    lastWidget.highlight:setBackgroundColor("alpha")
    lastWidget:setBorderWidth(0)
    lastWidget:setBorderColor("alpha")
  end

  if widget.creature then
    local name = tr("Selected: %s", widget.creature:getTooltip())
    preyWindow["slot" .. slot].title:setText(short_text(name, 28))
    preyWindow["slot" .. slot].select:recursiveGetChildById('choosePreyButton'):setOn(true)
    preyWindow["slot" .. slot].select:recursiveGetChildById('choosePreyButton'):setActionId(slot)
  end

  if widget.highlight then
    widget.highlight:setBackgroundColor("white")
    widget:setChecked(true)
  end

  widget:setBorderWidth(1)
  widget:setBorderColor("white")
end

function onResourceBalance(resourceType, balance)
  if resourceType == ResourceBank then -- bank gold
    bankGold = balance
  elseif resourceType == ResourceInventary then -- inventory gold
    inventoryGold = balance
  elseif resourceType == ResourcePreyBonus then -- bonus rerolls
    bonusRerolls = balance
    preyWindow.wildCards.text:setText(bonusRerolls)
  end

  local moneyTooltip = {}
	setStringColor(moneyTooltip, "Cash: " .. comma_value(inventoryGold), "#3f3f3f")
	setStringColor(moneyTooltip, " $", "#f7e6fe")
	setStringColor(moneyTooltip, "\nBank: " .. comma_value(bankGold), "#3f3f3f")
	setStringColor(moneyTooltip, " $", "#f7e6fe")
  preyWindow.gold.text:setTooltip(moneyTooltip)

  setUnsupportedSettings()
  if resourceType == ResourceBank or resourceType == ResourceInventary then
    preyWindow.gold.text:setText(comma_value(bankGold + inventoryGold))
  end
end

function onWildcardChange(prey, selected, lastSelected, slot)
  if not prey then return end

  if not selected then
    prey.wildcard.choose.button.choosePreyButton:setOn(false)
    prey.wildcard.choose.button.choosePreyButton:setActionId(0)
    lastSelectedLabel[slot] = nil
    selectedMonster[slot] = nil
    prey.title:setText("Select your prey creature")
    prey.wildcard.panel.creature:setOutfit({})
    return
  end

  prey.wildcard.choose.button.choosePreyButton:setOn(true)
  prey.wildcard.choose.button.choosePreyButton:setActionId(string.match(prey:getId(), "%d+$"))
  selected:setBackgroundColor("#585858")
  if lastSelected then
    lastSelected:setBackgroundColor(lastSelected.background)
  end

  if lastSelectedLabel[slot] then
    lastSelectedLabel[slot]:setBackgroundColor(lastSelectedLabel[slot].background)
    lastSelectedLabel[slot]:setColor("#c0c0c0")
  end

  lastSelectedLabel[slot] = selected
  selectedMonster[slot] = tonumber(selected:getId())
  local creature = g_things.getMonsterList()[selectedMonster[slot]]
  if not creature then return end
  prey.title:setText("Selected: " .. short_text(creature[1], 18))
  prey.wildcard.panel.creature:setOutfit({type = creature[2], auxType = creature[3], head = creature[4], body = creature[5], legs = creature[6], feet = creature[7], addons = creature[8]})
end

function onTextEdit(widget)
  searchFilterText = widget:getText()
  updateSearchWildcard(widget:getParent():getParent())
end

function move(panel, height, minimized)
  preyTracker:setParent(panel)
  preyTracker:open()

  if minimized then
    preyTracker:setHeight(height)
    preyTracker:minimize()
  else
    preyTracker:maximize()
    preyTracker:setHeight(height)
  end
  return preyTracker
end

function updatePreyWidget(slot, state)
  local preyTrackerSlot = preyTracker.contentsPanel["slot" .. (slot + 1)]
  if state == SLOT_STATE_LOCKED then
    preyTrackerSlot:setVisible(false)
    return
  end

  local preySlot = preyWindow["slot" .. (slot + 1)]
  if slot == 2 then
    preyTrackerSlot:setVisible(true)
    preyTracker:setContentMaximumHeight(112)
  end

  if state == SLOT_STATE_ACTIVE then
    local creatureAndBonus = preySlot.active.creatureAndBonus
    preyTrackerSlot.creature:setOutfit(creatureAndBonus.creature:getOutfit())
    preyTrackerSlot.creatureName:setText(short_text(preySlot.title:getText(), 12))
    preyTrackerSlot.time:setPercent(creatureAndBonus.timeLeft:getPercent())
    preyTrackerSlot.preyType:setImageSource(getSmallIconPath(preySlot.bonusType))
    preyTrackerSlot.preyAutoExtend:setImageSource(getExtendIcon(preySlot.lockType))
    preyTrackerSlot.creature:show()
    preyTrackerSlot.noCreature:hide()

    local preyName = preySlot.title:getText()
    local timeleft = timeleftTranslation(preySlot.timeLeft)
    local typeDesc = bonusTypeTranslate(preySlot.bonusType)
    local extendedDesc = preySlot.lockType == 0 and "false" or "true"
    local bonusDescription = bonusTypeTranslateText(preySlot.bonusType, preySlot.bonusValue)
    local starBonus = ""
    for i = 1, 10 do
      if i <= preySlot.bonusGrade then
        starBonus = starBonus .. "^"
      else
        starBonus = starBonus .. ";"
      end
    end

    local text = "Creature: %s\nDuration: %s\nValue: %s\nType: %s\nAutomatic Extend Prey: %s\n%s\n\nClick in this window to open the prey dialog."
    preyTrackerSlot:setTooltip(tr(text, preyName, timeleft, starBonus, typeDesc, extendedDesc, bonusDescription))
    preyTrackerSlot.onClick = function() show() end

  else
    preyTrackerSlot.creature:hide()
    preyTrackerSlot.noCreature:show()
    preyTrackerSlot.creatureName:setText("Inactive")
    preyTrackerSlot.time:setPercent(0)
    preyTrackerSlot.preyAutoExtend:setImageSource(getExtendIcon(preySlot.lockType))
    preyTrackerSlot.preyType:setImageSource(getSmallIconPath(preySlot.bonusType))
    preyTrackerSlot:setTooltip("Inactive Prey. \n\nUse the prey dialog to activate it. You can open the prey dialog by cliking in this window.")
    preyTrackerSlot.onClick = function() show() end
  end

end

function onRerollButtonAction(slot, freeReroll)
  if supportWindow then
    return
  end

  g_client.setInputLockWidget(nil)
  preyWindow:hide()
  local okFunc = function()
    g_game.preyAction(slot, PREY_ACTION_LISTREROLL, 0)
    supportWindow:destroy()
    supportWindow = nil
    preyWindow:show(true)
    preyWindow:raise()
    preyWindow:focus()
    g_client.setInputLockWidget(preyWindow)
  end

  local cancelFunc = function()
    supportWindow:destroy()
    supportWindow = nil
    preyWindow:show(true)
    preyWindow:raise()
    preyWindow:focus()
    g_client.setInputLockWidget(preyWindow)
  end

  local confirmText = "Are you sure you want to use the Free List Reroll?"
  if not freeReroll then
    confirmText = tr("Do you want to spend %s gold for a List Reroll?\nYou currently have %s gold available for the purchase.", comma_value(rerollPrice), (comma_value(bankGold + inventoryGold)))
  end

	supportWindow = displayGeneralBox(tr("Confirm of Using List Reroll"), confirmText,
    { { text=tr('Yes'), callback=okFunc },
    { text=tr('No'), callback=cancelFunc }
  }, okFunc, cancelFunc)
end

function onConfirmUsingWildcard(slot, price, action)
  if supportWindow then
    return
  end

  g_client.setInputLockWidget(nil)
  preyWindow:hide()

  local okFunc = function()
    g_game.preyAction(slot, action, 0)
    supportWindow:destroy()
    supportWindow = nil
    preyWindow:show(true)
    preyWindow:raise()
    preyWindow:focus()
    g_client.setInputLockWidget(preyWindow)
  end

  local cancelFunc = function()
    supportWindow:destroy()
    supportWindow = nil
    preyWindow:show(true)
    preyWindow:raise()
    preyWindow:focus()
    g_client.setInputLockWidget(preyWindow)
  end

  local confirmText = tr("Are you sure you want to use %s of your remaining %s Prey Wildcards?", price, bonusRerolls)
	supportWindow = displayGeneralBox(tr("Confirmation of Using Prey Wildcards"), confirmText,
    { { text=tr('Yes'), callback=okFunc },
    { text=tr('No'), callback=cancelFunc }
  }, okFunc, cancelFunc)
end

function onUnlockPermanentPreySlot(slot, price)
  if supportWindow then
    return
  end

  g_client.setInputLockWidget(nil)
  preyWindow:hide()

  local okFunc = function()
    g_game.preyAction(slot, PREY_ACTION_UNLOCK_PERMANENT, 0)
    supportWindow:destroy()
    supportWindow = nil
    preyWindow:show(true)
    preyWindow:raise()
    preyWindow:focus()
    g_client.setInputLockWidget(preyWindow)
  end

  local cancelFunc = function()
    supportWindow:destroy()
    supportWindow = nil
    preyWindow:show(true)
    preyWindow:raise()
    preyWindow:focus()
    g_client.setInputLockWidget(preyWindow)
  end

  local confirmText = tr("Do you want to spend %s Tibia Coins to unlock this Prey slot permanently?", comma_value(price))
  supportWindow = displayGeneralBox(tr("Unlock Permanent Prey Slot"), confirmText,
    { { text=tr('Yes'), callback=okFunc },
    { text=tr('No'), callback=cancelFunc }
  }, okFunc, cancelFunc)
end

function onEnableAutoReroll(slot)
  if supportWindow then
    return
  end

  g_client.setInputLockWidget(nil)
  preyWindow:hide()
  local okFunc = function()
    g_game.preyAction(slot, PREY_ACTION_LOCK_PREY, 1)
    supportWindow:destroy()
    supportWindow = nil
    preyWindow:show(true)
    preyWindow:raise()
    preyWindow:focus()
    g_client.setInputLockWidget(preyWindow)
  end

  local cancelFunc = function()
    supportWindow:destroy()
    supportWindow = nil
    preyWindow:show(true)
    preyWindow:raise()
    preyWindow:focus()
    g_client.setInputLockWidget(preyWindow)
  end

  local confirmText = tr("Do you want to enable the Automatic Bonus Reroll?\nEach time the Automatic Bonus Reroll is triggered, 1 of your Prey Wildcards will be consumed.")
	supportWindow = displayGeneralBox(tr("Confirmation of Using Prey Wildcards"), confirmText,
    { { text=tr('Yes'), callback=okFunc },
    { text=tr('No'), callback=cancelFunc }
  }, okFunc, cancelFunc)
end

function onEnableLockPrey(slot)
   if supportWindow then
    return
  end

  g_client.setInputLockWidget(nil)
  preyWindow:hide()
  local okFunc = function()
    g_game.preyAction(slot, PREY_ACTION_LOCK_PREY, 2)
    supportWindow:destroy()
    supportWindow = nil
    preyWindow:show(true)
    preyWindow:raise()
    preyWindow:focus()
    g_client.setInputLockWidget(preyWindow)
  end

  local cancelFunc = function()
    supportWindow:destroy()
    supportWindow = nil
    preyWindow:show(true)
    preyWindow:raise()
    preyWindow:focus()
    g_client.setInputLockWidget(preyWindow)
  end

  local confirmText = tr("Do you want to enable the Lock Prey?\nEach time the Lock Prey is triggered, 5 of your Prey Wildcards will be consumed.")
	supportWindow = displayGeneralBox(tr("Confirmation of Using Prey Wildcards"), confirmText,
    { { text=tr('Yes'), callback=okFunc },
    { text=tr('No'), callback=cancelFunc }
  }, okFunc, cancelFunc)
end

function onPreyActive(slot, currentHolderName, currentHolderOutfit, bonusType, bonusValue, bonusGrade, timeLeft, timeUntilFreeReroll, lockType)
  local prey = preyWindow["slot" .. (slot + 1)]
  if not prey then
    return
  end

  local percent = (timeLeft / (2 * 60 * 60)) * 100
  prey.inactive:hide()
  prey.locked:hide()
  prey.wildcard:hide()
  prey.select:hide()
  prey.active:show()
  prey.title:setText(capitalFormatStr(currentHolderName))
  local creatureAndBonus = prey.active.creatureAndBonus
  creatureAndBonus.creature:setOutfit(currentHolderOutfit)
  setTimeUntilFreeReroll(slot, timeUntilFreeReroll)
  creatureAndBonus.bonus.icon:setImageSource(getBigIconPath(bonusType))

  creatureAndBonus.bonus.icon.onHoverChange = function(widget, hovered)
    onHover(slot)
  end

  setBonusGradeStars(slot, bonusGrade)
  creatureAndBonus.timeLeft:setPercent(percent)
  creatureAndBonus.textLabel:setText(timeleftTranslation(timeLeft))

  prey.active.buttonsPanel.reroll.button.rerollButton.onClick = function()
    if not prey.active.buttonsPanel.reroll.button.rerollButton:isOn() then
      return
    end
    onRerollButtonAction(slot, timeUntilFreeReroll <= 0)
  end

  prey.bonusType = bonusType
  prey.bonusValue = bonusValue
  prey.bonusGrade = bonusGrade
  prey.lockType = lockType
  prey.timeLeft = timeLeft
  setUnsupportedSettings()
  updatePreyWidget(slot, SLOT_STATE_ACTIVE)
end

function onPreySelection(slot, bonusType, bonusValue, bonusGrade, names, outfits, timeUntilFreeReroll, lockType)
  local prey = preyWindow["slot" .. (slot + 1)]
  if not prey then
    return
  end

  prey.active:hide()
  prey.locked:hide()
  prey.wildcard:hide()
  prey.inactive:hide()
  prey.select:show()
  prey.title:setText(tr("Select your prey creature"))

  local list = prey.select.list
  list:destroyChildren()

  prey.select.buttonsPanel.choose.button.choosePreyButton:setOn(false)
  prey.select.buttonsPanel.choose.button.choosePreyButton:setActionId(slot + 1)
  for i, name in ipairs(names) do
    local box = g_ui.createWidget("PreyCreatureBox", list)
    box.onHoverChange = function(box, hovered) onSpecialHover("selectionList", bonusType, bonusValue) end
    name = capitalFormatStr(name)
    box.creature:setTooltip(name)
    box.creature:setOutfit(outfits[i])
    if i == 1 then
      onItemBoxChecked(box, nil, slot + 1)
    end
  end

  list.onChildFocusChange = function(list, selected, lastSelected) 
    if not lastSelected then
      lastSelected = list:getFirstChild()
    end
    onItemBoxChecked(selected, lastSelected, slot + 1)
   end

  prey.select.buttonsPanel.choose.button.choosePreyButton.onClick = function()
    if not prey.select.buttonsPanel.choose.button.choosePreyButton:isOn() then
      return true
    end

    g_game.preyAction(slot, PREY_ACTION_MONSTERSELECTION, list:getChildIndex(list:getFocusedChild()) - 1)
  end

  prey.select.buttonsPanel.reroll.button.rerollButton.onClick = function()
    if not prey.select.buttonsPanel.reroll.button.rerollButton:isOn() then
      return
    end
    onRerollButtonAction(slot, timeUntilFreeReroll <= 0)
  end

  prey.lockType = lockType
  prey.bonusType = bonusType
  prey.bonusValue = bonusValue
  setTimeUntilFreeReroll(slot, timeUntilFreeReroll)
  setUnsupportedSettings()
  updatePreyWidget(slot, SLOT_STATE_SELECTION)
end

function updateSearchWildcard(prey)
  prey.wildcard.monsterList:focusChild(nil)
  if searchFilterText == '' then
    updateWildCardWindow()
    return
  end

  local slot = tonumber(prey:getId():match("%d+")) - 1
  currentSearchRaces[slot] = {}
  for _, raceId in pairs(currentRaces[slot]) do
    local creature = creatureList[raceId]
    local searchFilterTextEscaped = string.searchEscape(searchFilterText:lower())
    if creature and string.find(creature[1]:lower(), searchFilterTextEscaped) then
      table.insert(currentSearchRaces[slot], raceId)
    end
  end

  for i, monsterLabel in ipairs(itemsPool[slot]) do
    if i > #currentSearchRaces[slot] then
      monsterLabel:setBackgroundColor("alpha")
      monsterLabel:setText('')
      monsterLabel.icon:setVisible(false)
      monsterLabel:setFocusable(false)
      goto continue
    end

    local monsterInfo = currentSearchRaces[slot][i]
    local color = ((i % 2 == 0) and '#484848' or '#414141')
    monsterLabel:setFocusable(true)
    monsterLabel:setBackgroundColor(color)
    monsterLabel.background = color
    monsterLabel:setId(monsterInfo)
    monsterLabel:setColor('#c0c0c0')
    local creature = creatureList[monsterInfo]
    if creature then
      monsterLabel:setText(string.capitalize(creature[1]))
    end

    monsterLabel.icon:setVisible(false)
    monsterLabel:setTextOffset("0 0")
    :: continue ::
  end

  local scrollbar = prey.wildcard:recursiveGetChildById('monsterListScrollBar')
  scrollbar:setMinimum(itemListMin[slot])
  scrollbar:setMaximum(#currentSearchRaces[slot])
  scrollbar.onValueChange = function(self, value, delta) onSearchValueChange(self, value, delta, slot) end
end

function onSearchValueChange(scrollbar, value, delta, slot)
  local prey = preyWindow["slot" .. (slot + 1)]
  if not prey then return end
  local startItem = math.max(itemListMin[slot], value)
  local endItem = startItem + maxFitItems[slot] - 1

  if endItem > #currentSearchRaces[slot] then
    endItem = #currentSearchRaces[slot]
    startItem = endItem - maxFitItems[slot] + 1
  end

  for i, monsterLabel in ipairs(itemsPool[slot]) do
    local itemId = value > 0 and (startItem + i - 1) or (startItem + i)
    local monsterInfo = currentSearchRaces[slot][itemId]

    local color = ((itemId % 2 == 0) and '#484848' or '#414141')
    monsterLabel:setBackgroundColor(color)
    monsterLabel.background = color
    monsterLabel:setId(monsterInfo)
    monsterLabel:setColor('#c0c0c0')
    local creature = creatureList[monsterInfo]
    if not creature then
      goto continue
    end

    if creature then
      monsterLabel:setText(string.capitalize(creature[1]))
    end

    if selectedMonster[slot] == monsterInfo then
      prey.wildcard.monsterList:focusChild(monsterLabel)
      monsterLabel:setBackgroundColor('#585858')
      monsterLabel:setColor('#f4f4f4')
      lastSelectedLabel[slot] = monsterLabel
    end

    monsterLabel.icon:setVisible(false)
    monsterLabel:setTextOffset("0 0")
    :: continue ::
  end
end

function onWildcardValueChange(scrollbar, value, delta, slot)
  local prey = preyWindow["slot" .. (slot + 1)]
  if not prey then return end
  local startItem = math.max(itemListMin[slot], value)
  local endItem = startItem + maxFitItems[slot] - 1

  if endItem > itemListMax[slot] then
    endItem = itemListMax[slot]
    startItem = endItem - maxFitItems[slot] + 1
  end

  for i, monsterLabel in ipairs(itemsPool[slot]) do
    local itemId = value > 0 and (startItem + i - 1) or (startItem + i)
    local monsterInfo = currentRaces[slot][itemId]

    local color = ((itemId % 2 == 0) and '#484848' or '#414141')
    monsterLabel:setBackgroundColor(color)
    monsterLabel.background = color
    monsterLabel:setId(monsterInfo)
    monsterLabel:setColor('#c0c0c0')
    local creature = creatureList[monsterInfo]
    if creature then
      monsterLabel:setText(string.capitalize(creature[1]))
    end

    if selectedMonster[slot] == monsterInfo then
      prey.wildcard.monsterList:focusChild(monsterLabel)
      monsterLabel:setBackgroundColor('#585858')
      monsterLabel:setColor('#f4f4f4')
      lastSelectedLabel[slot] = monsterLabel
    end

    monsterLabel.icon:setVisible(false)
    monsterLabel:setTextOffset("0 0")
  end
end

function updateWildCardWindow()
  for i = 0, 2 do
    local prey = preyWindow["slot" .. i + 1]
    if not prey or not prey.wildcard:isVisible() then
      goto continue
    end

    table.sort(currentRaces[i], function(a, b)
      local creatureA = creatureList[a]
      local creatureB = creatureList[b]
      if not creatureA then
          return false
      elseif not creatureB then
          return true
      end
      return creatureA[1] < creatureB[1]
    end)

    itemsPool[i] = {}
    prey.wildcard.monsterList:destroyChildren()

    local count = 0
    for k = 1, poolSize[i] do
      local monsterInfo = currentRaces[i][k]
      if monsterInfo == nil then
        break
      end

      local monster = g_ui.createWidget("WildcardLabel", prey.wildcard.monsterList)
      monster:setId(monsterInfo)
      monster:setActionId(i + 1)
      monster:setTextAlign(AlignLeft)
      count = count + 1
      local color = ((count % 2 == 0) and '#484848' or '#414141')
      monster:setBackgroundColor(color)
      monster.background = color
      local creature = creatureList[monsterInfo]
      if creature then
        monster:setText(string.capitalize(creature[1]))
      end
      monster.icon:setVisible(false)
      monster:setTextOffset("0 0")
      monster.onHoverChange = function(monster, hovered) onSpecialHover("selectionList", bonusType, bonusValue) end
      table.insert(itemsPool[i], monster)
    end

    prey.wildcard:recursiveGetChildById('monsterListScrollBar'):setValue(0)
    maxFitItems[i] = math.floor(prey.wildcard.monsterList:getHeight() / itemSize[i])
    local scrollbar = prey.wildcard:recursiveGetChildById('monsterListScrollBar')
    scrollbar:setMinimum(itemListMin[i])
    scrollbar:setMaximum(itemListMax[i])
    scrollbar.onValueChange = function(self, value, delta) onWildcardValueChange(self, value, delta, i) end
    :: continue ::
  end
end

function onPreyWildcard(slot, races, timeUntilFreeReroll, lockType, bonusType, bonusValue, bonusGrade)
  local prey = preyWindow["slot" .. (slot + 1)]
  if not prey then
    return
  end

  itemListMin[slot] = 0
  itemListMax[slot] = #races
  currentRaces[slot] = races
  currentSearchRaces[slot] = {}
  itemSize[slot] = WILDCARD_LABEL_HEIGHT
  maxFitItems[slot] = 0
  poolSize[slot] = WILDCARD_VISIBLE_LABELS
  itemsPool[slot] = {}

  prey.title:setText("Select your prey creature")
  prey.inactive:hide()
  prey.active:hide()
  prey.locked:hide()
  prey.select:hide()
  prey.wildcard:show()

  prey.wildcard.monsterList:focusChild(nil)
  prey.wildcard.monsterList:destroyChildren()

  local count = 0
  for i = 1, poolSize[slot] do
    g_ui.createWidget("WildcardLabel", prey.wildcard.monsterList)
    table.insert(itemsPool[slot], monster)
  end

  maxFitItems[slot] = math.floor(prey.wildcard.monsterList:getHeight() / itemSize[slot])

  local scrollbar = prey.wildcard:recursiveGetChildById('monsterListScrollBar')
  scrollbar:setMinimum(itemListMin[slot])
  scrollbar:setMaximum(itemListMax[slot])
  scrollbar.onValueChange = function(self, value, delta) onWildcardValueChange(self, value, delta, slot) end

  prey.wildcard:recursiveGetChildById("searchText"):clearText(true)
  prey.wildcard.monsterList.onChildFocusChange = function(self, selected, lastSelected) onWildcardChange(prey, selected, lastSelected, slot) end

  local preyPanel = prey.wildcard.panel
  preyPanel.onHoverChange = function(preyPanel, hovered) onSpecialHover("selectionList", bonusType, bonusValue) end

  monsterList = prey.wildcard.monsterList
  prey.wildcard.choose.button.choosePreyButton:setActionId(slot + 1)
  prey.wildcard.choose.button.choosePreyButton.onClick = function()
    return g_game.preyAction(slot, 4, selectedMonster[slot])
  end

  prey.lockType = lockType
  prey.bonusValue = bonusValue
  prey.bonusType = bonusType
  setUnsupportedSettings()
  updatePreyWidget(slot, SLOT_STATE_WILDCARD)
  updateWildCardWindow()
end

function onPreyLocked(slot, unlockState, timeUntilFreeReroll, lockType, permanentPrice)
  local prey = preyWindow["slot" .. (slot + 1)]
  if not prey then
    return
  end

  permanentPrice = math.max(0, tonumber(permanentPrice) or 0)
  prey.title:setText("Locked")
  prey.inactive:hide()
  prey.active:hide()
  prey.select:hide()
  prey.wildcard:hide()
  prey.locked.perm:setVisible(unlockState ~= PREY_UNLOCK_NONE)
  prey.locked.temp:hide()
  prey.locked.perm.onClick = function()
    onUnlockPermanentPreySlot(slot, permanentPrice)
  end
  prey.locked.perm.onHoverChange = function(_, hovered)
    if hovered then
      preyWindow.description:setText(tr(
        "Unlock this Prey slot permanently for %s Tibia Coins.",
        comma_value(permanentPrice)
      ))
    end
  end
  prey.locked:show()
  setUnsupportedSettings()
  updatePreyWidget(slot, SLOT_STATE_LOCKED)
end

function onPreyInactive(slot, timeUntilFreeReroll, lockType)
  local prey = preyWindow["slot"..(slot + 1)]
  if not prey then
    return
  end

  prey.title:setText("Inactive")
  setTimeUntilFreeReroll(slot, timeUntilFreeReroll)
  prey.active:hide()
  prey.locked:hide()
  prey.wildcard:hide()
  prey.select:hide()
  prey.inactive:show()

  prey.inactive.buttonsPanel.reroll.button.rerollButton.onClick = function()
    if not prey.inactive.buttonsPanel.reroll.button.rerollButton:isOn() then
      return
    end
    onRerollButtonAction(slot, timeUntilFreeReroll <= 0)
  end

  setUnsupportedSettings()
  prey.lockType = lockType
  updatePreyWidget(slot, SLOT_STATE_INACTIVE)
end

function storeRedirect(offerType)
  g_client.setInputLockWidget(nil)
  preyWindow:hide()
  g_game.openStore()
  g_game.requestStoreOffers(3, "", offerType)
end

function focusPrevWildcardLabel(list)
  local c = list:getFocusedChild()
  if not c then return end
  local cIndex = list:getChildIndex(c)

  if cIndex > 1 then
    list:focusPreviousChild(KeyboardFocusReason)
  else
    local scrollbar = list:getParent():recursiveGetChildById('monsterListScrollBar')
    scrollbar:setValue(scrollbar:getValue() - 1)
    if cIndex == 1 then
      list:focusPreviousChild(KeyboardFocusReason)
    end
  end
end

function focusNextWildcardLabel(list)
  local c = list:getFocusedChild()
  local cIndex = list:getChildIndex(c)
  local cCount = list:getChildCount()
  if cIndex < cCount then
    list:focusNextChild(KeyboardFocusReason)
  else
    local scrollbar = list:getParent():recursiveGetChildById('monsterListScrollBar')
    scrollbar:setValue(scrollbar:getValue() + 1)
    if cIndex == cCount then
      list:focusNextChild(KeyboardFocusReason)
    end
  end
end

function updateRerollTime()
  if not g_game.isOnline() or not preyWindow:isVisible() then
    removeEvent(updateRerollEvent)
    updateRerollEvent = nil
    return
  end

  for slot, data in pairs(timeLeftRerrol) do
    local startTime = data.startTime
    local currentTime = os.time()
    local elapsedTime = currentTime - startTime
    local elapsedMinutes = math.round(elapsedTime / 60)
    if elapsedMinutes > 0 then
      setTimeUntilFreeReroll(slot, math.max(0, data.minutesLeft - elapsedMinutes))
    end
  end
end
