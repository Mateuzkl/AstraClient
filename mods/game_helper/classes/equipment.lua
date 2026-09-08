-- Equip Panel Module
-- New dynamic layout with unlimited rules configuration

local equip = {}

-- Export module immediately so it's available for OTUI callbacks
modules.game_helper = modules.game_helper or {}
modules.game_helper.equip = equip

-- Local references
local equipPanel = nil
local helper = nil
local formPanel = nil
local rulesList = nil

-- State variables
local nextRuleId = 1
local editingRuleId = nil -- nil = ADD mode, id = UPDATE mode
local currentFormItem = { id = 0, equippedId = 0, name = "", slotType = "" }
local SKIP_BUTTON_IDS = { 'skipItemButton', 'skipItemButton2', 'skipItemButton3', 'skipItemButton4' }
local skipFormItems = {}
for i = 1, 4 do
  skipFormItems[i] = { id = 0, equippedId = 0, name = "", slotType = "" }
end
local equipEnabled = true -- Equipment system enabled/disabled state

-- Config storage
local equipConfig = {
  rules = {},    -- Dynamic array of rules
  enabled = true -- System enabled state
}

-- Uses shared decay mapping from ItemsDatabase (gamelib/items.lua)
-- Get the equipped version of an item ID
local function getEquippedId(itemId)
  if ItemsDatabase and ItemsDatabase.getEquippedId then
    return ItemsDatabase.getEquippedId(itemId)
  end
  return itemId
end

-- Check if an equipped item matches a config item (considering decay)
local function itemMatchesConfig(equippedItemId, configItemId)
  if ItemsDatabase and ItemsDatabase.itemMatchesDecay then
    return ItemsDatabase.itemMatchesDecay(equippedItemId, configItemId)
  end

  return equippedItemId == configItemId
end

-- Helper function to get equipPanel (lazy initialization)
local function getEquipPanel()
  if equipPanel then return equipPanel end
  local rootWidget = g_ui.getRootWidget()
  if rootWidget then
    local helperWindow = rootWidget:recursiveGetChildById('helperWindow')
    if helperWindow then
      local container = helperWindow:recursiveGetChildById('equipPanelContainer')
      if container then
        equipPanel = container:recursiveGetChildById('equipPanel')
        if equipPanel then
          formPanel = equipPanel:recursiveGetChildById('configFormPanel')
          rulesList = equipPanel:recursiveGetChildById('rulesList')
        end
      end
    end
  end
  return equipPanel
end

-- Local reference for mouse grabber
local mouseGrabberWidget = nil

local function getMouseGrabber()
  if mouseGrabberWidget then return mouseGrabberWidget end
  mouseGrabberWidget = g_ui.createWidget('UIWidget')
  mouseGrabberWidget:setVisible(false)
  mouseGrabberWidget:setFocusable(false)
  return mouseGrabberWidget
end

local function getHelperWindow()
  local rootWidget = g_ui.getRootWidget()
  if rootWidget then
    return rootWidget:recursiveGetChildById('helperWindow')
  end
  return nil
end

-- Get item name from item/thingType
local function getItemName(itemId, item)
  if item and item.getName then
    local name = item:getName()
    if name and name ~= "" then return name end
  end
  local thingType = g_things.getThingType(itemId, ThingCategoryItem)
  if thingType then
    local marketData = thingType:getMarketData()
    if marketData and marketData.name then
      return marketData.name
    end
  end
  return "Item #" .. itemId
end

-- Convert resource string to internal format
function equip.resourceToInternal(resourceStr)
  local lower = resourceStr:lower()
  if lower == "hp%" then return "hp%" end
  if lower == "mp%" then return "mp%" end
  if lower == "hp" then return "hp" end
  if lower == "mp" then return "mp" end
  return "hp%"
end

-- Convert internal format to display string
function equip.resourceToDisplay(resource)
  if resource == "hp%" then return "HP%" end
  if resource == "mp%" then return "MP%" end
  if resource == "hp" then return "HP" end
  if resource == "mp" then return "MP" end
  return "HP%"
end

-- ============================================================
-- FORM HANDLING
-- ============================================================

-- Clear the form to default values
function equip.clearForm()
  if not formPanel then getEquipPanel() end
  if not formPanel then return end

  -- Reset item
  currentFormItem = { id = 0, equippedId = 0, name = "", slotType = "" }
  local itemButton = formPanel:getChildById('itemButton')
  if itemButton then
    local itemWidget = itemButton:getChildById('formItem')
    if itemWidget then itemWidget:destroy() end
    itemButton:setImageSource('/images/game/actionbar/actionbarslot')
    itemButton:setTooltip("")
  end
  local itemNameLabel = formPanel:getChildById('itemNameLabel')
  if itemNameLabel then
    itemNameLabel:setText("(click to select an item)")
    itemNameLabel:setColor("#888888")
  end

  -- Hide clear button
  local clearButton = formPanel:getChildById('clearButton')
  if clearButton then
    clearButton:setVisible(false)
  end

  -- Reset condition 1
  local cond1Resource = formPanel:getChildById('cond1Resource')
  if cond1Resource then cond1Resource:setCurrentOption("HP%") end
  local cond1Operator = formPanel:getChildById('cond1Operator')
  if cond1Operator then cond1Operator:setCurrentOption("<=") end
  local cond1Value = formPanel:getChildById('cond1Value')
  if cond1Value then cond1Value:setText("50") end

  -- Reset logic
  local condLogic = formPanel:getChildById('condLogic')
  if condLogic then condLogic:setCurrentOption("AND") end

  -- Reset condition 2
  local cond2Enable = formPanel:getChildById('cond2Enable')
  if cond2Enable then cond2Enable:setChecked(false) end
  equip.updateCond2State(false)
  local cond2Resource = formPanel:getChildById('cond2Resource')
  if cond2Resource then cond2Resource:setCurrentOption("MP%") end
  local cond2Operator = formPanel:getChildById('cond2Operator')
  if cond2Operator then cond2Operator:setCurrentOption(">=") end
  local cond2Value = formPanel:getChildById('cond2Value')
  if cond2Value then cond2Value:setText("20") end

  -- Reset action
  local actionEquip = formPanel:getChildById('actionEquip')
  if actionEquip then actionEquip:setChecked(true) end
  local actionUnequip = formPanel:getChildById('actionUnequip')
  if actionUnequip then actionUnequip:setChecked(false) end

  -- Reset skip if equipped
  local skipCheck = formPanel:getChildById('skipIfEquippedCheck')
  if skipCheck then skipCheck:setChecked(false) end
  for i = 1, 4 do
    skipFormItems[i] = { id = 0, equippedId = 0, name = "", slotType = "" }
    local btn = formPanel:getChildById(SKIP_BUTTON_IDS[i])
    if btn then
      btn:setEnabled(false)
      local skipWidget = btn:getChildById('skipItem')
      if skipWidget then skipWidget:destroy() end
      btn:setImageSource('/images/game/actionbar/actionbarslot')
      btn:setTooltip("")
    end
  end

  -- Reset player conditions
  for _, condId in ipairs({ 'condRooted', 'condFeared', 'condPz', 'condNonPz', 'condUtamo' }) do
    local checkbox = formPanel:getChildById(condId)
    if checkbox then checkbox:setChecked(false) end
  end

  -- Reset to ADD mode
  editingRuleId = nil
  if not rulesList then getEquipPanel() end
  local rulesListPanel = rulesList and rulesList:getParent()
  if rulesListPanel then
    local addButton = rulesListPanel:getChildById('addButton')
    if addButton then addButton:setText("Add") end
  end

  -- Clear visual selection in the list
  equip.updateRuleSelection()
end

-- Update condition 2 enabled state
function equip.updateCond2State(enabled)
  if not formPanel then getEquipPanel() end
  if not formPanel then return end

  local widgets = { 'condLogic', 'cond2Resource', 'cond2Operator', 'cond2Value' }
  for _, id in ipairs(widgets) do
    local widget = formPanel:getChildById(id)
    if widget then widget:setEnabled(enabled) end
  end
end

-- Get form data as a rule config object
function equip.getFormData()
  if not formPanel then getEquipPanel() end
  if not formPanel then return nil end

  local cond1Resource = formPanel:getChildById('cond1Resource')
  local cond1Operator = formPanel:getChildById('cond1Operator')
  local cond1Value = formPanel:getChildById('cond1Value')
  local condLogic = formPanel:getChildById('condLogic')
  local cond2Enable = formPanel:getChildById('cond2Enable')
  local cond2Resource = formPanel:getChildById('cond2Resource')
  local cond2Operator = formPanel:getChildById('cond2Operator')
  local cond2Value = formPanel:getChildById('cond2Value')
  local actionEquip = formPanel:getChildById('actionEquip')
  local skipCheck = formPanel:getChildById('skipIfEquippedCheck')

  local rule = {
    id = editingRuleId or nextRuleId,
    itemId = currentFormItem.id,
    equippedId = currentFormItem.equippedId,
    name = currentFormItem.name,
    slotType = currentFormItem.slotType,

    cond1Resource = equip.resourceToInternal(cond1Resource and cond1Resource:getCurrentOption().text or "HP%"),
    cond1Operator = cond1Operator and cond1Operator:getCurrentOption().text or "<=",
    cond1Value = tonumber(cond1Value and cond1Value:getText() or "50") or 50,

    condLogic = condLogic and condLogic:getCurrentOption().text:lower() or "and",

    cond2Enabled = cond2Enable and cond2Enable:isChecked() or false,
    cond2Resource = equip.resourceToInternal(cond2Resource and cond2Resource:getCurrentOption().text or "MP%"),
    cond2Operator = cond2Operator and cond2Operator:getCurrentOption().text or ">=",
    cond2Value = tonumber(cond2Value and cond2Value:getText() or "20") or 20,

    action = (actionEquip and actionEquip:isChecked()) and "equip" or "unequip",

    skipIfEquipped = skipCheck and skipCheck:isChecked() or false,
    skipItemId = skipFormItems[1].id,
    skipItemName = skipFormItems[1].name,
    skipItemSlotType = skipFormItems[1].slotType,
    skipItems = (function()
      local items = {}
      for i = 1, 4 do
        if skipFormItems[i].id > 0 then
          table.insert(items,
            { id = skipFormItems[i].id, name = skipFormItems[i].name, slotType = skipFormItems[i].slotType })
        end
      end
      return items
    end)(),

    conditions = {
      rooted = formPanel:getChildById('condRooted') and formPanel:getChildById('condRooted'):isChecked() or false,
      feared = formPanel:getChildById('condFeared') and formPanel:getChildById('condFeared'):isChecked() or false,
      pz = formPanel:getChildById('condPz') and formPanel:getChildById('condPz'):isChecked() or false,
      nonPz = formPanel:getChildById('condNonPz') and formPanel:getChildById('condNonPz'):isChecked() or false,
      utamoVita = formPanel:getChildById('condUtamo') and formPanel:getChildById('condUtamo'):isChecked() or false,
    },

    enabled = true
  }

  return rule
end

-- Set form data from a rule config object (for editing)
function equip.setFormData(rule)
  if not formPanel then getEquipPanel() end
  if not formPanel then return end
  if not rule then return end

  editingRuleId = rule.id

  -- Set item
  currentFormItem = {
    id = rule.itemId,
    equippedId = rule.equippedId,
    name = rule.name,
    slotType = rule.slotType
  }

  local itemButton = formPanel:getChildById('itemButton')
  if itemButton and rule.itemId > 0 then
    itemButton:setImageSource('/images/ui/item')
    local itemWidget = itemButton:getChildById('formItem')
    if not itemWidget then
      itemWidget = g_ui.createWidget('UIItem', itemButton)
      itemWidget:setId('formItem')
      itemWidget:setSize({ width = 32, height = 32 })
      itemWidget:setPhantom(true)
      itemWidget:fill('parent')
    end
    itemWidget:setItemId(rule.itemId)
    itemButton:setTooltip(rule.name .. " (" .. rule.slotType .. ")")
  end

  local itemNameLabel = formPanel:getChildById('itemNameLabel')
  if itemNameLabel and rule.itemId > 0 then
    itemNameLabel:setText(rule.name)
    itemNameLabel:setColor("$var-text-color")
  end

  -- Show clear button when item is selected
  local clearButton = formPanel:getChildById('clearButton')
  if clearButton and rule.itemId > 0 then
    clearButton:setVisible(true)
  end

  -- Set condition 1
  local cond1Resource = formPanel:getChildById('cond1Resource')
  if cond1Resource then cond1Resource:setCurrentOption(equip.resourceToDisplay(rule.cond1Resource)) end
  local cond1Operator = formPanel:getChildById('cond1Operator')
  if cond1Operator then cond1Operator:setCurrentOption(rule.cond1Operator) end
  local cond1Value = formPanel:getChildById('cond1Value')
  if cond1Value then cond1Value:setText(tostring(rule.cond1Value)) end

  -- Set logic
  local condLogic = formPanel:getChildById('condLogic')
  if condLogic then condLogic:setCurrentOption(rule.condLogic:upper()) end

  -- Set condition 2
  local cond2Enable = formPanel:getChildById('cond2Enable')
  if cond2Enable then cond2Enable:setChecked(rule.cond2Enabled) end
  equip.updateCond2State(rule.cond2Enabled)
  local cond2Resource = formPanel:getChildById('cond2Resource')
  if cond2Resource then cond2Resource:setCurrentOption(equip.resourceToDisplay(rule.cond2Resource)) end
  local cond2Operator = formPanel:getChildById('cond2Operator')
  if cond2Operator then cond2Operator:setCurrentOption(rule.cond2Operator) end
  local cond2Value = formPanel:getChildById('cond2Value')
  if cond2Value then cond2Value:setText(tostring(rule.cond2Value)) end

  -- Set action
  local actionEquip = formPanel:getChildById('actionEquip')
  local actionUnequip = formPanel:getChildById('actionUnequip')
  if actionEquip then actionEquip:setChecked(rule.action == "equip") end
  if actionUnequip then actionUnequip:setChecked(rule.action == "unequip") end

  -- Set skip if equipped
  local skipCheck = formPanel:getChildById('skipIfEquippedCheck')
  if skipCheck then skipCheck:setChecked(rule.skipIfEquipped) end

  -- Migrate old format if needed
  local skipItems = rule.skipItems
  if not skipItems or #skipItems == 0 then
    if rule.skipItemId and rule.skipItemId > 0 then
      skipItems = { { id = rule.skipItemId, name = rule.skipItemName or "", slotType = rule.skipItemSlotType or "" } }
    else
      skipItems = {}
    end
  end

  -- Load skip items into form state and buttons
  for i = 1, 4 do
    local si = skipItems[i]
    if si and si.id and si.id > 0 then
      skipFormItems[i] = {
        id = si.id,
        equippedId = getEquippedId(si.id),
        name = si.name or "",
        slotType = si.slotType or ""
      }
    else
      skipFormItems[i] = { id = 0, equippedId = 0, name = "", slotType = "" }
    end

    local btn = formPanel:getChildById(SKIP_BUTTON_IDS[i])
    if btn then
      btn:setEnabled(rule.skipIfEquipped)
      if skipFormItems[i].id > 0 then
        btn:setImageSource('/images/ui/item')
        local skipWidget = btn:getChildById('skipItem')
        if not skipWidget then
          skipWidget = g_ui.createWidget('UIItem', btn)
          skipWidget:setId('skipItem')
          skipWidget:setSize({ width = 24, height = 24 })
          skipWidget:setPhantom(true)
          skipWidget:fill('parent')
        end
        skipWidget:setItemId(skipFormItems[i].id)
        btn:setTooltip(skipFormItems[i].name .. " (" .. skipFormItems[i].slotType .. ")")
      end
    end
  end

  -- Set player conditions
  if rule.conditions then
    local condMap = {
      condRooted = 'rooted',
      condFeared = 'feared',
      condPz = 'pz',
      condNonPz = 'nonPz',
      condUtamo = 'utamoVita'
    }
    for widgetId, condKey in pairs(condMap) do
      local checkbox = formPanel:getChildById(widgetId)
      if checkbox then checkbox:setChecked(rule.conditions[condKey] or false) end
    end
  end

  -- Set to UPDATE mode
  if not rulesList then getEquipPanel() end
  local rulesListPanel = rulesList and rulesList:getParent()
  if rulesListPanel then
    local addButton = rulesListPanel:getChildById('addButton')
    if addButton then addButton:setText("Update") end
  end

  -- Update visual selection
  equip.updateRuleSelection()
end

-- ============================================================
-- ITEM SELECTION
-- ============================================================

function equip.selectItem(targetButton, targetType)
  local grabber = getMouseGrabber()
  local helperWindow = getHelperWindow()

  grabber:grabMouse()
  if helperWindow then helperWindow:hide() end
  g_mouse.pushCursor('target')

  grabber.onMouseRelease = function(self, mousePosition, mouseButton)
    equip.onItemSelected(self, mousePosition, mouseButton, targetButton, targetType)
  end
end

function equip.onItemSelected(self, mousePosition, mouseButton, targetButton, targetType)
  local grabber = getMouseGrabber()
  local helperWindow = getHelperWindow()

  grabber:ungrabMouse()
  if helperWindow then helperWindow:show() end
  g_mouse.popCursor('target')
  grabber.onMouseRelease = nil

  local rootWidget = g_ui.getRootWidget()
  if not rootWidget then return true end

  local clickedWidget = rootWidget:recursiveGetChildByPos(mousePosition, false)
  if not clickedWidget then return true end

  local itemId = 0
  local item = nil

  if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
    item = clickedWidget:getItem()
    if item then
      itemId = item:getId()
    end
  elseif clickedWidget:getClassName() == 'UIGameMap' then
    local tile = clickedWidget:getTile(mousePosition)
    if tile then
      local topUseThing = tile:getTopUseThing()
      if topUseThing then
        itemId = topUseThing:getId()
        item = topUseThing
      end
    end
  end

  if itemId == 0 then
    modules.game_textmessage.displayFailureMessage(tr('No item selected!'))
    return true
  end

  local slotType = ""

  local thingType = g_things.getThingType(itemId, ThingCategoryItem)
  local clothSlot = thingType and thingType:getClothSlot() or 0

  -- Add rings and necklaces
  -- Neclackes with charges or duration only
  local fallbackSlots = {
    [9301] = "amulet", -- bonfire amulet
    [3056] = "amulet", -- bronze amulet
    [23542] = "amulet", -- collar of blue plasma
    [23543] = "amulet", -- collar of green plasma
    [50152] = "amulet", -- collar of orange plasma
    [23544] = "amulet", -- collar of red plasma
    [3085] = "amulet", -- dragon necklace
    [3082] = "amulet", -- elven amulet
    [50154] = "amulet", -- enchanted merudi brooch
    [30344] = "amulet", -- enchanted pendulet
    [30342] = "amulet", -- enchanted sleep shawl
    [39233] = "amulet", -- enchanted turtle amulet
    [22061] = "amulet", -- enchanted werewolf amulet
    [3083] = "amulet", -- garlic necklace
    [16108] = "amulet", -- gill necklace
    [815] = "amulet", -- glacier amulet
    [21183] = "amulet", -- glooth amulet
    [51275] = "amulet", -- greater garlic necklace 
    [9303] = "amulet", -- levianthan's amulet 
    [816] = "amulet", -- lightning pendant 
    [817] = "amulet", -- magma amulet
    [13990] = "amulet", -- necklace of the deep
    [16113] = "amulet", -- prismatic necklace
    [3084] = "amulet", -- protection amulet
    [9302] = "amulet", -- sacred tree amulet
    [9304] = "amulet", -- shockwave amulet
    [3054] = "amulet", -- silver amulet
    [3081] = "amulet", -- stone skin amulet
    [3045] = "amulet", -- strange talisman
    [814] = "amulet", -- terra amulet
  -- Neclackes for unEquip
    [23526] = "amulet", -- collar of blue plasma (equiped)
    [23527] = "amulet", -- collar of green plasma (equiped)
    [23528] = "amulet", -- collar of red plasma (equiped)
    [50153] = "amulet", -- collar of orange plasma (equiped)
    [50155] = "amulet", -- enchanted merudri brooch (equiped)
    [30345] = "amulet", -- enchanted pendulet (equiped)
    [30343] = "amulet", -- enchanted sleep shawl (equiped)
    [39234] = "amulet", -- enchanted turtle amulet (equiped)
    [22134] = "amulet", -- enchanted werewolf amulet (equiped)


  -- Rings with charges or duration only
    [3092] = "ring",   -- axe ring
    [39180] = "ring",   -- charged alicorn ring
    [39186] = "ring",   -- charged arboreal ring
    [39183] = "ring",   -- charged arcanomancer ring
    [39177] = "ring",   -- charged spitthorn ring
    [3093] = "ring",   -- club ring
    [6299] = "ring",   -- death ring
    [3097] = "ring",   -- dwarven ring
    [31557] = "ring",   -- enchanted blister ring
    [3051] = "ring",   -- energy ring
    [3052] = "ring",   -- life ring
    [3048] = "ring",   -- might ring
    [3050] = "ring",   -- power ring
    [16114] = "ring",   -- prismatic ring
    [23529] = "ring",   -- ring of blue plasma
    [23531] = "ring",   -- ring of green plasma
    [3098] = "ring",   -- ring of healing
    [50150] = "ring",   -- ring of orange plasma
    [23533] = "ring",   -- ring of red plasma
    [32621] = "ring",   -- enchanted ring of souls
    [45642] = "ring",   -- ring of temptation
    [12669] = "ring",   -- star ring
    [3091] = "ring",   -- sword ring
    [3053] = "ring",   -- time ring
  -- Rings for unEquip
    [3095] = "ring",   -- axe ring (equiped)
    [3096] = "ring",   -- club ring (equiped)
    [6300] = "ring",   -- death ring (equiped)
    [3099] = "ring",   -- dwarven ring (equiped)
    [3088] = "ring",   -- energy ring (equiped)
    [3089] = "ring",   -- life ring (equiped)
    [3087] = "ring",   -- power ring (equiped)
    [16264] = "ring",   -- prismatic ring (equiped)
    [23530] = "ring",   -- ring of blue plasma (equiped)
    [23532] = "ring",   -- ring of green plasma (equiped)
    [3100] = "ring",   -- ring of healing (equiped)
    [50151] = "ring",   -- ring of orange plasma (equiped)
    [23534] = "ring",   -- ring of red plasma (equiped)
    [32635] = "ring",   -- enchanted ring of souls (equiped)
    [12670] = "ring",   -- star ring (equiped)
    [3094] = "ring",   -- sword ring (equiped)
    [3090] = "ring",   -- time ring (equiped)
  }

  local slotFinger = InventorySlotFinger or 9
  local slotNeck = InventorySlotNeck or 2

  if clothSlot == slotFinger or fallbackSlots[itemId] == "ring" then
    slotType = "ring"
  elseif clothSlot == slotNeck or fallbackSlots[itemId] == "amulet" then
    slotType = "amulet"
  else
    modules.game_textmessage.displayFailureMessage(tr('This item is not a ring or amulet!'))
    return true
  end

  local itemName = getItemName(itemId, item)

  -- Update the appropriate target
  if targetType == "main" then
    currentFormItem = {
      id = itemId,
      equippedId = getEquippedId(itemId),
      name = itemName,
      slotType = slotType
    }

    targetButton:setImageSource('/images/ui/item')
    local itemWidget = targetButton:getChildById('formItem')
    if not itemWidget then
      itemWidget = g_ui.createWidget('UIItem', targetButton)
      itemWidget:setId('formItem')
      itemWidget:setSize({ width = 32, height = 32 })
      itemWidget:setPhantom(true)
      itemWidget:fill('parent')
    end
    itemWidget:setItemId(itemId)
    targetButton:setTooltip(itemName .. " (" .. slotType .. ")")

    local itemNameLabel = formPanel:getChildById('itemNameLabel')
    if itemNameLabel then
      itemNameLabel:setText(itemName)
      itemNameLabel:setColor("$var-text-color")
    end

    -- Show clear button when item is selected
    local clearButton = formPanel:getChildById('clearButton')
    if clearButton then
      clearButton:setVisible(true)
    end
  elseif targetType:sub(1, 4) == "skip" then
    local skipIndex = tonumber(targetType:sub(5)) or 1
    skipFormItems[skipIndex] = {
      id = itemId,
      equippedId = getEquippedId(itemId),
      name = itemName,
      slotType = slotType
    }

    targetButton:setImageSource('/images/ui/item')
    local skipWidget = targetButton:getChildById('skipItem')
    if not skipWidget then
      skipWidget = g_ui.createWidget('UIItem', targetButton)
      skipWidget:setId('skipItem')
      skipWidget:setSize({ width = 24, height = 24 })
      skipWidget:setPhantom(true)
      skipWidget:fill('parent')
    end
    skipWidget:setItemId(itemId)
    targetButton:setTooltip(itemName .. " (" .. slotType .. ")")
  end

  return true
end

-- ============================================================
-- RULES LIST MANAGEMENT
-- ============================================================

function equip.addOrUpdateRule()
  local rule = equip.getFormData()
  if not rule then return end

  if rule.itemId == 0 then
    modules.game_textmessage.displayFailureMessage(tr('Please select an item first!'))
    return
  end

  if editingRuleId then
    -- Update existing rule, preserving enabled state
    for i, r in ipairs(equipConfig.rules) do
      if r.id == editingRuleId then
        rule.enabled = r.enabled
        rule.id = r.id
        equipConfig.rules[i] = rule
        break
      end
    end
  else
    -- Add new rule
    rule.id = nextRuleId
    nextRuleId = nextRuleId + 1
    table.insert(equipConfig.rules, rule)
  end

  equip.updateRulesList()
  equip.clearForm()

  -- Save configuration
  if saveSettings then
    saveSettings()
  end
end

function equip.removeRule(ruleId)
  local ruleName = "this rule"
  for _, r in ipairs(equipConfig.rules) do
    if r.id == ruleId then
      ruleName = r.name or "this rule"
      break
    end
  end

  _RuleList.confirmRemove(ruleName, function()
    for i, r in ipairs(equipConfig.rules) do
      if r.id == ruleId then
        table.remove(equipConfig.rules, i)
        break
      end
    end
    equip.updateRulesList()

    if editingRuleId == ruleId then
      equip.clearForm()
    end

    if saveSettings then
      saveSettings()
    end
  end)
end

function equip.toggleRuleEnabled(ruleId, enabled)
  for _, r in ipairs(equipConfig.rules) do
    if r.id == ruleId then
      r.enabled = enabled
      break
    end
  end

  -- Update visual selection (to show red for disabled)
  equip.updateRuleSelection()

  -- Save configuration
  if saveSettings then
    saveSettings()
  end
end

function equip.onRuleClick(ruleId)
  for _, r in ipairs(equipConfig.rules) do
    if r.id == ruleId then
      equip.setFormData(r)
      break
    end
  end
end

function equip.moveRuleUp(ruleId)
  for i, r in ipairs(equipConfig.rules) do
    if r.id == ruleId then
      if _RuleList and _RuleList.swapRule(rulesList, equipConfig.rules, i, -1) then
        if saveSettings then saveSettings() end
        _RuleList.updateArrowButtonStates(rulesList)
      end
      break
    end
  end
end

function equip.moveRuleDown(ruleId)
  for i, r in ipairs(equipConfig.rules) do
    if r.id == ruleId then
      if _RuleList and _RuleList.swapRule(rulesList, equipConfig.rules, i, 1) then
        if saveSettings then saveSettings() end
        _RuleList.updateArrowButtonStates(rulesList)
      end
      break
    end
  end
end

-- Generate line 1 text: item name + action
function equip.getRuleNameLine(rule)
  local action = (rule.action == "equip") and "Equip" or "Unequip"
  local name = rule.name or "Unknown"
  return name .. " - " .. action
end

-- Generate compact summary for line 2 (conditions, player states, skip)
function equip.getRuleSummary(rule)
  local parts = {}

  -- Condition 1
  table.insert(parts, equip.resourceToDisplay(rule.cond1Resource) .. rule.cond1Operator .. rule.cond1Value)

  -- Condition 2
  if rule.cond2Enabled then
    table.insert(parts,
      rule.condLogic:upper() ..
      " " .. equip.resourceToDisplay(rule.cond2Resource) .. rule.cond2Operator .. rule.cond2Value)
  end

  -- Player conditions
  if rule.conditions then
    if rule.conditions.rooted then table.insert(parts, "Rooted") end
    if rule.conditions.feared then table.insert(parts, "Feared") end
    if rule.conditions.pz then table.insert(parts, "PZ") end
    if rule.conditions.nonPz then table.insert(parts, "non-PZ") end
    if rule.conditions.utamoVita then table.insert(parts, "Utamo") end
  end

  -- Skip items indicator
  if rule.skipIfEquipped then
    local skipCount = 0
    if rule.skipItems then
      skipCount = #rule.skipItems
    elseif rule.skipItemId and rule.skipItemId > 0 then
      skipCount = 1
    end
    if skipCount > 0 then
      table.insert(parts, "Skip:" .. skipCount)
    end
  end

  return table.concat(parts, "  ")
end

function equip.updateRulesList()
  if not rulesList then getEquipPanel() end
  if not rulesList then return end

  -- Clear existing items
  rulesList:destroyChildren()

  -- Add rule items
  for _, rule in ipairs(equipConfig.rules) do
    local ruleWidget = g_ui.createWidget('EquipRuleItem', rulesList)
    ruleWidget.ruleId = rule.id

    -- Set type indicator (A for amulet, R for ring)
    local typeIcon = ruleWidget:getChildById('typeIcon')
    if typeIcon then
      if rule.slotType == "amulet" then
        typeIcon:setText("A")
        typeIcon:setColor("#44aaff")
      else
        typeIcon:setText("R")
        typeIcon:setColor("#ff8844")
      end
    end

    -- Set item icon
    local itemIcon = ruleWidget:getChildById('itemIcon')
    if itemIcon and rule.itemId > 0 then
      itemIcon:setImageSource('/images/ui/item')
      local itemWidget = g_ui.createWidget('UIItem', itemIcon)
      itemWidget:setId('ruleItemIcon')
      itemWidget:setSize({ width = 22, height = 22 })
      itemWidget:setPhantom(true)
      itemWidget:fill('parent')
      itemWidget:setItemId(rule.itemId)
    end

    -- Set name (line 1): item name + action
    local nameLabel = ruleWidget:getChildById('ruleName')
    if nameLabel then
      nameLabel:setText(equip.getRuleNameLine(rule))
    end

    -- Set summary (line 2): conditions
    local summaryLabel = ruleWidget:getChildById('ruleSummary')
    if summaryLabel then
      summaryLabel:setText(equip.getRuleSummary(rule))
    end

    -- Set enable checkbox
    local enableCheck = ruleWidget:getChildById('enableCheck')
    if enableCheck then
      enableCheck:setChecked(rule.enabled)
      enableCheck.onCheckChange = function(widget)
        equip.toggleRuleEnabled(rule.id, widget:isChecked())
      end
    end

    _RuleList.setupDoubleClickToggle(ruleWidget)

    -- Apply disabled background color if rule is disabled
    if not rule.enabled then
      ruleWidget:setBackgroundColor('#6a3a3a88')
    end

    -- Set move buttons
    local moveUpButton = ruleWidget:getChildById('moveUpButton')
    if moveUpButton then
      moveUpButton.onClick = function()
        equip.moveRuleUp(rule.id)
      end
    end

    local moveDownButton = ruleWidget:getChildById('moveDownButton')
    if moveDownButton then
      moveDownButton.onClick = function()
        equip.moveRuleDown(rule.id)
      end
    end

    -- Set remove button
    local removeButton = ruleWidget:getChildById('removeButton')
    if removeButton then
      removeButton.onClick = function()
        equip.removeRule(rule.id)
      end
    end

    -- Click on rule to edit (left click) or show context menu (right click)
    local capturedRuleId = rule.id
    local capturedRuleName = rule.name
    ruleWidget.onMouseRelease = function(widget, mousePos, mouseButton)
      if mouseButton == MouseLeftButton then
        local clickedChild = widget:getChildByPos(mousePos)
        if clickedChild then
          local childId = clickedChild:getId()
          if childId == 'enableCheck' or childId == 'removeButton' or childId == 'moveUpButton' or childId == 'moveDownButton' then
            return false
          end
        end
        equip.onRuleClick(capturedRuleId)
        return true
      elseif mouseButton == MouseRightButton then
        equip.showRuleContextMenu(capturedRuleId, capturedRuleName, mousePos)
        return true
      end
      return false
    end
  end

  if _RuleList then
    _RuleList.updateArrowButtonStates(rulesList)
  end
end

-- Show context menu for rule
function equip.showRuleContextMenu(ruleId, ruleName, position)
  local menu = g_ui.createWidget('PopupMenu')

  menu:addOption(tr('Edit'), function()
    equip.onRuleClick(ruleId)
  end)

  menu:addSeparator()

  menu:addOption(tr('Move Up'), function()
    equip.moveRuleUp(ruleId)
  end)

  menu:addOption(tr('Move Down'), function()
    equip.moveRuleDown(ruleId)
  end)

  menu:addSeparator()

  menu:addOption(tr('Delete'), function()
    equip.removeRule(ruleId)
  end)

  menu:display(position)
end

-- Update rule selection visual (background colors)
function equip.updateRuleSelection()
  if not rulesList then getEquipPanel() end
  if not rulesList then return end

  -- Build a map of rule IDs to their enabled state
  local ruleEnabledMap = {}
  for _, rule in ipairs(equipConfig.rules) do
    ruleEnabledMap[rule.id] = rule.enabled
  end

  local children = rulesList:getChildren()

  for i, child in ipairs(children) do
    if child.ruleId then
      local isSelected = (child.ruleId == editingRuleId)
      local isEnabled = ruleEnabledMap[child.ruleId]

      -- Apply correct background based on selection and enabled state
      if isSelected then
        child:setBackgroundColor('#3a6a3a88') -- Green for selected
      elseif not isEnabled then
        child:setBackgroundColor('#6a3a3a88') -- Red for disabled
      else
        child:setBackgroundColor('#00000022') -- Default
      end
    end
  end
end

-- ============================================================
-- CONDITION CHECKING
-- ============================================================

-- Check if player has condition (OR logic)
local function checkPlayerConditions(config)
  local player = g_game.getLocalPlayer()
  if not player then return false end

  local states = player:getStates() or 0
  local cond = config.conditions

  -- If no condition is selected, return true
  local hasAny = cond.rooted or cond.feared or cond.pz or cond.nonPz or cond.utamoVita
  if not hasAny then return true end

  -- OR logic: any condition satisfied = true
  if cond.rooted and bit.band(states, PlayerStates.Rooted) ~= 0 then return true end
  if cond.feared and bit.band(states, PlayerStates.Feared) ~= 0 then return true end
  if cond.pz and bit.band(states, PlayerStates.Pz) ~= 0 then return true end
  if cond.nonPz and bit.band(states, PlayerStates.Pz) == 0 then return true end
  local manaShield = bit.bor(PlayerStates.ManaShield or 0, PlayerStates.NewMagicShield or 0)
  if cond.utamoVita and bit.band(states, manaShield) ~= 0 then return true end

  return false
end

-- Check resource condition
local function checkResourceCondition(resource, operator, value)
  local player = g_game.getLocalPlayer()
  if not player then return false end

  local current = 0

  if resource == "hp" then
    current = player:getHealth()
  elseif resource == "mp" then
    current = player:getMana()
  elseif resource == "hp%" then
    local maxHealth = player:getMaxHealth()
    current = maxHealth > 0 and (player:getHealth() / maxHealth) * 100 or 0
  elseif resource == "mp%" then
    local maxMana = player:getMaxMana()
    current = maxMana > 0 and (player:getMana() / maxMana) * 100 or 0
  end

  if operator == ">=" then return current >= value end
  if operator == "<=" then return current <= value end
  if operator == ">" then return current > value end
  if operator == "<" then return current < value end
  return false
end

-- Check all resource conditions of a rule
local function checkRuleConditions(config)
  local cond1Met = checkResourceCondition(config.cond1Resource, config.cond1Operator, config.cond1Value)

  if not config.cond2Enabled then
    return cond1Met
  end

  local cond2Met = checkResourceCondition(config.cond2Resource, config.cond2Operator, config.cond2Value)

  if config.condLogic == "and" then
    return cond1Met and cond2Met
  else
    return cond1Met or cond2Met
  end
end

-- Helper function to find item in containers
local function findItemInContainers(itemId)
  for _, container in pairs(g_game.getContainers()) do
    for slot = 0, container:getItemsCount() - 1 do
      local item = container:getItem(slot)
      if item and item:getId() == itemId then
        return item
      end
    end
  end
  return nil
end

-- Helper function to unequip an item
local function unequipItemToBackpack(item)
  if not item then return false end
  g_game.move(item, { x = 65535, y = InventorySlotBack, z = 0 }, item:getCount())
  return true
end

-- Equip an item based on rule
local function equipItem(rule)
  local player = g_game.getLocalPlayer()
  if not player then return false end

  local inventorySlot = rule.slotType == "ring" and InventorySlotFinger or InventorySlotNeck
  local currentItem = player:getInventoryItem(inventorySlot)

  -- Check if already equipped
  if currentItem and itemMatchesConfig(currentItem:getId(), rule.itemId) then
    return false
  end

  -- Find item in containers
  local foundItem = findItemInContainers(rule.itemId)
  if foundItem then
    g_game.equipItem(foundItem)
    return true
  else
    local hasItem = player:getInventoryCount(rule.itemId) > 0
    if hasItem then
      g_game.equipItemId(rule.itemId, 0)
      return true
    end
  end

  return false
end

-- Unequip an item based on rule
local function unequipItem(rule)
  local player = g_game.getLocalPlayer()
  if not player then return false end

  local inventorySlot = rule.slotType == "ring" and InventorySlotFinger or InventorySlotNeck
  local currentItem = player:getInventoryItem(inventorySlot)

  -- Check if the configured item is equipped
  if currentItem and itemMatchesConfig(currentItem:getId(), rule.itemId) then
    return unequipItemToBackpack(currentItem)
  end

  return false
end

-- ============================================================
-- MAIN CHECK LOOP
-- ============================================================

-- Check if an unequip rule conditions are met for a given item
-- This is used to block equip actions when unequip conditions are active
local function isUnequipConditionActive(itemId, player)
  for _, rule in ipairs(equipConfig.rules) do
    if rule.action == "unequip" and rule.enabled and rule.itemId > 0 then
      -- Check if it's the same item (considering decay mappings)
      if itemMatchesConfig(rule.itemId, itemId) or itemMatchesConfig(itemId, rule.itemId) then
        -- Check player conditions
        if checkPlayerConditions(rule) then
          -- Check skip if equipped
          local skipActive = false
          if rule.skipIfEquipped and rule.skipItems then
            for _, skipItem in ipairs(rule.skipItems) do
              if skipItem.id and skipItem.id > 0 then
                local slot = skipItem.slotType == "ring" and InventorySlotFinger or InventorySlotNeck
                local equipped = player:getInventoryItem(slot)
                if equipped and itemMatchesConfig(equipped:getId(), skipItem.id) then
                  skipActive = true
                  break
                end
              end
            end
          end

          -- If not skipped, check if unequip conditions are met
          if not skipActive and checkRuleConditions(rule) then
            return true -- Unequip condition is active for this item
          end
        end
      end
    end
  end
  return false
end

-- Helper function to check and execute a single rule
-- Returns true if an action was executed
local function tryExecuteRule(rule, player, blockIfUnequipActive)
  if not rule.enabled or rule.itemId == 0 then
    return false
  end

  -- 1. Check player conditions
  if not checkPlayerConditions(rule) then
    return false
  end

  -- 2. Check skip if equipped
  if rule.skipIfEquipped and rule.skipItems then
    for _, skipItem in ipairs(rule.skipItems) do
      if skipItem.id and skipItem.id > 0 then
        local slot = skipItem.slotType == "ring" and InventorySlotFinger or InventorySlotNeck
        local equipped = player:getInventoryItem(slot)
        if equipped and itemMatchesConfig(equipped:getId(), skipItem.id) then
          return false
        end
      end
    end
  end

  -- 3. For EQUIP actions, check if any unequip rule for this item is active
  if blockIfUnequipActive and rule.action == "equip" then
    if isUnequipConditionActive(rule.itemId, player) then
      return false -- Block equip because unequip condition is active
    end
  end

  -- 4. Check HP/MP conditions
  local conditionsMet = checkRuleConditions(rule)

  -- 5. Determine if action should trigger
  if not conditionsMet then
    return false
  end

  -- 6. Execute action
  if rule.action == "equip" then
    return equipItem(rule)
  else -- "unequip"
    return unequipItem(rule)
  end
end

function equip.checkEquipItems()
  if not g_game.isOnline() then return end

  -- Check if helper automatic functions are enabled
  if _Helper and _Helper.isHelperAutomaticFunctionsEnabled then
    if not _Helper.isHelperAutomaticFunctionsEnabled() then return end
  end

  if not equipEnabled then return end -- Check if system is enabled
  local player = g_game.getLocalPlayer()
  if not player then return end

  -- PRIORITY: Process UNEQUIP rules first
  -- This ensures that if there's a condition to unequip, it takes precedence over equip
  for _, rule in ipairs(equipConfig.rules) do
    if rule.action == "unequip" then
      if tryExecuteRule(rule, player, false) then
        return -- One action per cycle
      end
    end
  end

  -- Then process EQUIP rules (with unequip blocking check)
  for _, rule in ipairs(equipConfig.rules) do
    if rule.action == "equip" then
      if tryExecuteRule(rule, player, true) then
        return -- One action per cycle
      end
    end
  end
end

-- ============================================================
-- PRESET MANAGEMENT
-- ============================================================

function equip.loadProfileByName(profileName)
  local helperConfig = _Helper and _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig then return end

  -- Save current profile first
  local oldProfile = helperConfig.selectedEquipProfile or "Default"
  if not helperConfig.equipProfiles then helperConfig.equipProfiles = {} end
  helperConfig.equipProfiles[oldProfile] = equip.saveConfig()

  -- Load new profile
  helperConfig.selectedEquipProfile = profileName
  local profile = helperConfig.equipProfiles[profileName]
  if profile then
    equip.loadConfig(profile)
  else
    equip.loadConfig({ rules = {}, enabled = true })
  end
  equip.clearForm()
  equip.updateRulesList()
  equip.updateUI()
end

-- Compatibility wrappers delegating to preset_manager
function equip.togglePreset(widget, hideMessage)
  local pm = modules.game_helper and modules.game_helper.presetManager
  if pm then
    local ctx = pm.getEquipContext() or pm.buildEquipContext()
    if ctx then pm.togglePreset(ctx, widget, hideMessage) end
  end
end

function equip.removeProfile()
  local pm = modules.game_helper and modules.game_helper.presetManager
  if pm then
    local ctx = pm.getEquipContext() or pm.buildEquipContext()
    if ctx then pm.removeProfile(ctx) end
  end
end

function equip.loadProfileOptions()
  local pm = modules.game_helper and modules.game_helper.presetManager
  if pm then
    local ctx = pm.getEquipContext()
    if ctx then pm.loadProfileOptions(ctx) end
  end
end

-- ============================================================
-- SYSTEM ENABLE/DISABLE
-- ============================================================

function equip.toggleEquipment(enabled)
  equipEnabled = enabled
  equipConfig.enabled = enabled

  -- Sincronizar com shortcut panel
  if _Helper and _Helper.Shortcut and _Helper.Shortcut.syncButton then
    _Helper.Shortcut.syncButton('shortcutEquipment', enabled)
  end

  -- Save configuration
  if saveSettings then
    saveSettings()
  end
end

function equip.isEnabled()
  return equipEnabled
end

-- ============================================================
-- INITIALIZATION & CONFIG
-- ============================================================

function equip.init(helperWindow)
  helper = helperWindow
  if helper and helper.contentPanel then
    local container = helper.contentPanel:getChildById('equipPanelContainer')
    if container then
      equipPanel = container:recursiveGetChildById('equipPanel')
      if equipPanel then
        formPanel = equipPanel:recursiveGetChildById('configFormPanel')
        rulesList = equipPanel:recursiveGetChildById('rulesList')
      end
    end
  end

  -- Wire preset callbacks via shared preset manager
  local pm = modules.game_helper and modules.game_helper.presetManager
  if pm and equipPanel then
    local presetsSection = equipPanel:recursiveGetChildById('presetsSection')
    if presetsSection then
      local ctx = pm.buildEquipContext()
      if ctx then
        ctx.presetsPanel = presetsSection
        pm.setEquipContext(ctx)
        pm.initPresets(ctx)
      end
    end
  end

  -- Setup event handlers
  equip.setupEventHandlers()
end

function equip.setupEventHandlers()
  if not formPanel then getEquipPanel() end
  if not formPanel then return end

  -- Item button click
  local itemButton = formPanel:getChildById('itemButton')
  if itemButton then
    itemButton.onClick = function(widget)
      equip.selectItem(widget, "main")
    end
  end

  -- Numeric-only validation for condition value inputs
  if _Helper and _Helper.setupNumericInput then
    _Helper.setupNumericInput(formPanel:getChildById('cond1Value'), 1, 100)
    _Helper.setupNumericInput(formPanel:getChildById('cond2Value'), 1, 100)
  end

  -- Condition 2 enable checkbox
  local cond2Enable = formPanel:getChildById('cond2Enable')
  if cond2Enable then
    cond2Enable.onCheckChange = function(widget)
      local checked = widget:isChecked()
      equip.updateCond2State(checked)
      if checked then
        local cond2Value = formPanel:getChildById('cond2Value')
        if cond2Value then
          cond2Value:focus()
          cond2Value:setCursorPos(cond2Value:getText():len())
        end
      end
    end
  end

  -- Action radio buttons (mutual exclusion)
  local actionEquip = formPanel:getChildById('actionEquip')
  local actionUnequip = formPanel:getChildById('actionUnequip')

  if actionEquip then
    actionEquip.onCheckChange = function(widget)
      if widget:isChecked() and actionUnequip then
        actionUnequip:setChecked(false)
      end
    end
  end
  if actionUnequip then
    actionUnequip.onCheckChange = function(widget)
      if widget:isChecked() and actionEquip then
        actionEquip:setChecked(false)
      end
    end
  end

  -- Skip if equipped checkbox and buttons
  local skipCheck = formPanel:getChildById('skipIfEquippedCheck')
  if skipCheck then
    skipCheck.onCheckChange = function(widget)
      local checked = widget:isChecked()
      for _, btnId in ipairs(SKIP_BUTTON_IDS) do
        local btn = formPanel:getChildById(btnId)
        if btn then btn:setEnabled(checked) end
      end
    end
  end
  for i, btnId in ipairs(SKIP_BUTTON_IDS) do
    local btn = formPanel:getChildById(btnId)
    if btn then
      btn.onClick = function(widget)
        equip.selectItem(widget, "skip" .. i)
      end
    end
  end

  -- Add button (now in rulesListPanel)
  if not rulesList then getEquipPanel() end
  local rulesListPanel = rulesList and rulesList:getParent()
  if rulesListPanel then
    local addButton = rulesListPanel:getChildById('addButton')
    if addButton then
      addButton.onClick = function()
        equip.addOrUpdateRule()
      end
    end
  end

  -- Clear button
  local clearButton = formPanel:getChildById('clearButton')
  if clearButton then
    clearButton.onClick = function()
      equip.clearForm()
    end
  end

  -- Enable Equipment checkbox
  if not equipPanel then getEquipPanel() end
  if equipPanel then
    local enableEquipmentPanel = equipPanel:getChildById('enableEquipmentPanel')
    if enableEquipmentPanel then
      local enableCheckbox = enableEquipmentPanel:getChildById('enableEquipment')
      if enableCheckbox then
        enableCheckbox.onCheckChange = function(widget)
          equip.toggleEquipment(widget:isChecked())
        end
      end
    end
  end
end

function equip.getPanel()
  return equipPanel
end

function equip.getConfig()
  return equipConfig
end

function equip.setConfig(config)
  if config then
    equipConfig = config
  end
end

-- Load saved configuration (supports old format migration)
function equip.loadConfig(savedConfig)
  if not savedConfig then return end

  -- Load enabled state
  if savedConfig.enabled ~= nil then
    equipEnabled = savedConfig.enabled
    equipConfig.enabled = savedConfig.enabled
  else
    equipEnabled = true
    equipConfig.enabled = true
  end

  -- New format: rules array
  if savedConfig.rules then
    equipConfig.rules = savedConfig.rules

    -- Find max id for nextRuleId
    local maxId = 0
    for _, rule in ipairs(equipConfig.rules) do
      if rule.id and rule.id > maxId then
        maxId = rule.id
      end
      -- Ensure conditions table exists
      if not rule.conditions then
        rule.conditions = {
          rooted = false,
          feared = false,
          pz = false,
          nonPz = false,
          utamoVita = false
        }
      end
      -- Migrate old skipItemId to skipItems array
      if rule.skipItemId and rule.skipItemId > 0 and not rule.skipItems then
        rule.skipItems = { { id = rule.skipItemId, name = rule.skipItemName or "", slotType = rule.skipItemSlotType or "" } }
      end
      if not rule.skipItems then
        rule.skipItems = {}
      end
    end
    nextRuleId = maxId + 1

    -- Old format: items array with 8 fixed slots
  elseif savedConfig.items then
    equipConfig.rules = {}
    for i, item in ipairs(savedConfig.items) do
      if item.id and item.id > 0 then
        local rule = {
          id = nextRuleId,
          itemId = item.id,
          equippedId = item.equippedId or getEquippedId(item.id),
          name = item.name or "",
          slotType = item.slotType or "",

          cond1Resource = item.resourceType == "mp" and "mp%" or "hp%",
          cond1Operator = item.condition1 or ">=",
          cond1Value = item.percent1 or 0,

          condLogic = "and",

          cond2Enabled = true,
          cond2Resource = item.resourceType == "mp" and "mp%" or "hp%",
          cond2Operator = item.condition2 or "<=",
          cond2Value = item.percent2 or 100,

          action = item.unequipIfNoMatch and "unequip" or "equip",

          skipIfEquipped = false,
          skipItemId = 0,
          skipItemName = "",
          skipItemSlotType = "",

          conditions = {
            rooted = false,
            feared = false,
            pz = false,
            nonPz = false,
            utamoVita = false
          },

          enabled = item.enabled ~= false
        }
        nextRuleId = nextRuleId + 1
        table.insert(equipConfig.rules, rule)
      end
    end
  end

  equip.updateRulesList()
end

-- Save configuration
function equip.saveConfig()
  return {
    rules = equipConfig.rules,
    enabled = equipConfig.enabled
  }
end

-- Update UI elements (called after loading config)
function equip.updateUI()
  equip.updateRulesList()

  -- Update enable checkbox
  if not equipPanel then getEquipPanel() end
  if equipPanel then
    local enableEquipmentPanel = equipPanel:getChildById('enableEquipmentPanel')
    if enableEquipmentPanel then
      local enableCheckbox = enableEquipmentPanel:getChildById('enableEquipment')
      if enableCheckbox then
        enableCheckbox:setChecked(equipEnabled)
      end
    end
  end
end

-- Terminate module
function equip.terminate()
  if mouseGrabberWidget then
    mouseGrabberWidget:destroy()
    mouseGrabberWidget = nil
  end
  equipPanel = nil
  formPanel = nil
  rulesList = nil
  helper = nil
end

return equip
