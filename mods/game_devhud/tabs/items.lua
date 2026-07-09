--[[
  game_devhud / Items tab.

  TOP - Equipment SET editor. The slots load the player's CURRENTLY equipped items.
        Left-click a slot = SELECT it (its info shows on the right; imbuement in a
        later phase). Right-click a slot = EDIT it: opens a picker with a name search,
        a preview, and tier/upgrade steppers that are DISABLED when the item can't take
        them (tier = ThingType classification > 0; upgrade = set piece or weapon).
        "Equip set" hands the player the configured gear (dev.equipSet), then reloads
        the slots from the real inventory.
  BOTTOM - "Give items" list: search by name/id, each row gives X1 / X10 to the backpack.
]]

-- slot layout mirrors the inventory doll; slot number == CONST_SLOT (head=1..ammo=10)
local SET_SLOTS = {
  { slot = 2,  name = "Necklace",  img = "neck",       col = 1, row = 1 },
  { slot = 1,  name = "Head",      img = "head",       col = 2, row = 1 },
  { slot = 3,  name = "Backpack",  img = "back",       col = 3, row = 1 },
  { slot = 6,  name = "Left hand", img = "left-hand",  col = 1, row = 2 },
  { slot = 4,  name = "Armor",     img = "body",       col = 2, row = 2 },
  { slot = 5,  name = "Right hand",img = "right-hand", col = 3, row = 2 },
  { slot = 9,  name = "Ring",      img = "finger",     col = 1, row = 3 },
  { slot = 7,  name = "Legs",      img = "legs",       col = 2, row = 3 },
  { slot = 10, name = "Ammo",      img = "ammo",       col = 3, row = 3 },
  { slot = 8,  name = "Feet",      img = "feet",       col = 2, row = 4 },
}

local SLOT_STEP = 38
local slotWidgets = {}
local w = {}

-- ── helpers ──────────────────────────────────────────────────────────────────
local function slotDef(num)
  for _, d in ipairs(SET_SLOTS) do if d.slot == num then return d end end
end
local function slotName(num) local d = slotDef(num); return d and d.name or "?" end
local function slotBg(num) local d = slotDef(num); return d and ("/images/game/slots/" .. d.img) or "" end

-- client-side support flags for the picker (mirror uiitem.cpp badge logic)
local function supportsTier(id)
  local tt = g_things.getThingType(id, ThingCategoryItem)
  return tt ~= nil and tt:getClassification() > 0
end
local function supportsUpgrade(id)
  local tt = g_things.getThingType(id, ThingCategoryItem)
  if not tt then return false end
  local cloth = tt:getClothSlot()
  local isSetPiece = (cloth == 1 or cloth == 4 or cloth == 7 or cloth == 8)
  local isWeapon = (cloth == 0 and tt:getWeaponType() > 0)
  return isSetPiece or isWeapon
end

local function collectSet()
  local slots = {}
  for num, sw in pairs(slotWidgets) do
    local id = sw:getItemId()
    if id and id > 0 then
      slots[#slots + 1] = { slot = num, id = id, tier = sw:getTier(), upgrade = sw:getUpgradeLevel() }
    end
  end
  return slots
end

local function clearSlot(num)
  local sw = slotWidgets[num]
  if not sw then return end
  sw:setItem(nil)
  sw:setImageSource(slotBg(num))
end

-- load the player's currently equipped items into the slots
local function loadEquipment()
  local player = g_game.getLocalPlayer()
  if not player then return end
  for _, def in ipairs(SET_SLOTS) do
    local sw = slotWidgets[def.slot]
    if sw then
      local item = player:getInventoryItem(def.slot)
      if item and item:getId() > 0 then
        sw:setItemId(item:getId())
        if sw.setTier then sw:setTier(item:getTier() or 0) end
        if sw.setUpgradeLevel then sw:setUpgradeLevel(item:getUpgradeLevel() or 0) end
      else
        sw:setItem(nil)
        sw:setImageSource(slotBg(def.slot))
      end
    end
  end
end

-- ── right info panel (imbuement goes here in a later phase) ───────────────────
local function updateRightPanel(num)
  if not w.rightInfo then return end
  local sw = slotWidgets[num]
  local id = sw and sw:getItemId() or 0
  if id == 0 then
    w.rightInfo:setText("Slot: " .. slotName(num) .. "\n(empty)\n\nRight-click a slot to set its item.")
  else
    w.rightInfo:setText(string.format(
      "Slot: %s\nItem id: %d\nTier: %d\nUpgrade: +%d\n\nImbuement: coming in the next phase.",
      slotName(num), id, sw:getTier() or 0, sw:getUpgradeLevel() or 0))
  end
end

local function selectSlot(num)
  for sn, sw in pairs(slotWidgets) do
    sw:setBorderColor(sn == num and "#c9761f" or "#2a2a2a")
  end
  updateRightPanel(num)
end

-- ── item picker window (right-click a slot) ──────────────────────────────────
local function openPicker(num)
  local target = slotWidgets[num]
  if w.picker then w.picker:destroy() end
  local pick = g_ui.createWidget('DevHudPickerWindow', g_ui.getRootWidget())
  w.picker = pick
  pick:setText("Select item - " .. slotName(num))

  local search      = pick:getChildById('search')
  local searchBtn   = pick:getChildById('searchBtn')
  local results     = pick:getChildById('results')
  local preview     = pick:getChildById('preview')
  local itemName    = pick:getChildById('itemName')
  local tierSpin    = pick:getChildById('tierSpin')
  local upgradeSpin = pick:getChildById('upgradeSpin')
  local okBtn       = pick:getChildById('okBtn')
  local cancelBtn   = pick:getChildById('cancelBtn')

  tierSpin:setMinimum(0); tierSpin:setMaximum(10)
  upgradeSpin:setMinimum(0); upgradeSpin:setMaximum(50)

  local chosenId = (target and target:getItemId()) or 0

  local function refreshValidation()
    local st = chosenId > 0 and supportsTier(chosenId)
    local su = chosenId > 0 and supportsUpgrade(chosenId)
    tierSpin:setEnabled(st and true or false)
    upgradeSpin:setEnabled(su and true or false)
    if not st then tierSpin:setValue(0) end
    if not su then upgradeSpin:setValue(0) end
  end

  local function setChosen(id)
    chosenId = id or 0
    preview:setItemId(chosenId)
    local nm = (chosenId > 0 and getItemNameById and getItemNameById(chosenId)) or nil
    itemName:setText(chosenId > 0 and (nm ~= nil and nm ~= "" and nm or ("id " .. chosenId)) or "(none)")
    refreshValidation()
  end

  setChosen(chosenId)
  if target then
    if tierSpin:isEnabled() then tierSpin:setValue(target:getTier() or 0) end
    if upgradeSpin:isEnabled() then upgradeSpin:setValue(target:getUpgradeLevel() or 0) end
  end

  local function doSearch()
    local q = search:getText()
    if #q < 2 then Devhud.setStatus("Type at least 2 characters.", true); return end
    Devhud.apply("dev.searchItems", { query = q }, function(ok, d)
      if not (ok and type(d) == "table" and type(d.items) == "table") then return end
      results:destroyChildren()
      for _, it in ipairs(d.items) do
        local row = g_ui.createWidget('DevHudItemRow', results)
        row:setHeight(26)
        local sp = g_ui.createWidget('Item', row)
        sp:setVirtual(true); sp:setItemId(it.id); sp:setWidth(24); sp:setHeight(24)
        sp:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        sp:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
        sp:setMarginLeft(2)
        local nm = g_ui.createWidget('DevHudRowLabel', row)
        nm:setText(string.format("%s (%d)", it.name, it.id))
        nm:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        nm:addAnchor(AnchorRight, 'parent', AnchorRight)
        nm:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
        nm:setMarginLeft(30)
        row.onMouseRelease = function(_, _, button)
          if button == MouseLeftButton then setChosen(it.id); return true end
          return false
        end
      end
    end)
  end
  searchBtn.onClick = doSearch
  search.onEnter = doSearch

  local function close() pick:destroy(); if w.picker == pick then w.picker = nil end end
  okBtn.onClick = function()
    if target and chosenId > 0 then
      target:setItemId(chosenId)
      if target.setTier then target:setTier(tierSpin:isEnabled() and tierSpin:getValue() or 0) end
      if target.setUpgradeLevel then target:setUpgradeLevel(upgradeSpin:isEnabled() and upgradeSpin:getValue() or 0) end
      updateRightPanel(num)
    end
    close()
  end
  cancelBtn.onClick = close
  pick.onEscape = close

  pick:show(); pick:raise(); pick:focus()
end

local function editSlot(num)
  selectSlot(num)
  openPicker(num)
end

-- ── set section ──────────────────────────────────────────────────────────────
local function buildSet(panel)
  local setBox = g_ui.createWidget('Panel', panel)
  setBox:setId('setBox')
  setBox:setHeight(4 * SLOT_STEP + 24)

  local title = g_ui.createWidget('DevHudSection', setBox)
  title:setText("Equipment set  -  left-click: select, right-click: edit")
  title:addAnchor(AnchorTop, 'parent', AnchorTop)
  title:addAnchor(AnchorLeft, 'parent', AnchorLeft)

  for _, def in ipairs(SET_SLOTS) do
    local sw = g_ui.createWidget('DevHudSlot', setBox)
    sw:setId('setSlot' .. def.slot)
    sw:setImageSource("/images/game/slots/" .. def.img)
    sw:addAnchor(AnchorTop, 'parent', AnchorTop)
    sw:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    sw:setMarginTop(18 + (def.row - 1) * SLOT_STEP)
    sw:setMarginLeft((def.col - 1) * SLOT_STEP)
    sw:setTooltip(def.name)
    sw.onMouseRelease = function(_, _, button)
      if button == MouseLeftButton then selectSlot(def.slot); return true end
      if button == MouseRightButton then editSlot(def.slot); return true end
      return false
    end
    slotWidgets[def.slot] = sw
  end

  -- right side: info + actions
  local rp = g_ui.createWidget('Panel', setBox)
  rp:addAnchor(AnchorTop, 'parent', AnchorTop)
  rp:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  rp:addAnchor(AnchorRight, 'parent', AnchorRight)
  rp:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  rp:setMarginTop(18)
  rp:setMarginLeft(3 * SLOT_STEP + 16)

  w.rightInfo = g_ui.createWidget('DevHudRowLabel', rp)
  w.rightInfo:setText("Left-click a slot to select it.")
  w.rightInfo:setColor("#c0c0c0")
  w.rightInfo:addAnchor(AnchorTop, 'parent', AnchorTop)
  w.rightInfo:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  w.rightInfo:addAnchor(AnchorRight, 'parent', AnchorRight)
  w.rightInfo:setHeight(96)

  local ar = g_ui.createWidget('DevHudRow', rp)
  ar:addAnchor(AnchorTop, 'prev', AnchorBottom)
  ar:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  ar:addAnchor(AnchorRight, 'parent', AnchorRight)
  ar:setMarginTop(6)
  local equipBtn = g_ui.createWidget('DevHudButton', ar)
  equipBtn:setId('equip'); equipBtn:setText("Equip set"); equipBtn:setWidth(96)
  equipBtn:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  equipBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  equipBtn.onClick = function()
    local slots = collectSet()
    if #slots == 0 then Devhud.setStatus("Configure at least one slot.", true); return end
    Devhud.apply("dev.equipSet", { slots = slots }, function(ok)
      if ok then scheduleEvent(loadEquipment, 250) end
    end)
  end
  local reloadBtn = g_ui.createWidget('DevHudButton', ar)
  reloadBtn:setId('reload'); reloadBtn:setText("Reload"); reloadBtn:setWidth(80)
  reloadBtn:addAnchor(AnchorLeft, 'equip', AnchorRight)
  reloadBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  reloadBtn:setMarginLeft(6)
  reloadBtn.onClick = loadEquipment
  local clearBtn = g_ui.createWidget('DevHudButton', ar)
  clearBtn:setText("Clear"); clearBtn:setWidth(70)
  clearBtn:addAnchor(AnchorLeft, 'reload', AnchorRight)
  clearBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  clearBtn:setMarginLeft(6)
  clearBtn.onClick = function() for num in pairs(slotWidgets) do clearSlot(num) end end

  loadEquipment()
end

-- ── give-items list ──────────────────────────────────────────────────────────
local function rebuildItemList(items)
  if not w.listContent then return end
  w.listContent:destroyChildren()
  if #items == 0 then
    local none = g_ui.createWidget('DevHudRowLabel', w.listContent)
    none:setText("No items found.")
    none:setColor("#9a9a9a")
    none:setHeight(20)
    return
  end
  for _, it in ipairs(items) do
    local row = g_ui.createWidget('DevHudItemRow', w.listContent)

    local sprite = g_ui.createWidget('Item', row)
    sprite:setVirtual(true)
    sprite:setItemId(it.id)
    sprite:setWidth(34)
    sprite:setHeight(34)
    sprite:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    sprite:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    sprite:setMarginLeft(2)

    local x10 = g_ui.createWidget('DevHudButton', row)
    x10:setId('x10'); x10:setText("X10"); x10:setWidth(48)
    x10:addAnchor(AnchorRight, 'parent', AnchorRight)
    x10:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    x10:setMarginRight(4)
    x10.onClick = function() Devhud.apply("dev.addItem", { id = it.id, count = 10 }) end

    local x1 = g_ui.createWidget('DevHudButton', row)
    x1:setId('x1'); x1:setText("X1"); x1:setWidth(48)
    x1:addAnchor(AnchorRight, 'x10', AnchorLeft)
    x1:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    x1:setMarginRight(4)
    x1.onClick = function() Devhud.apply("dev.addItem", { id = it.id, count = 1 }) end

    local name = g_ui.createWidget('DevHudRowLabel', row)
    name:setText(string.format("%s  (%d)", it.name, it.id))
    name:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    name:addAnchor(AnchorRight, 'x1', AnchorLeft)
    name:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    name:setMarginLeft(40)
    name:setMarginRight(6)
  end
end

local function doSearch()
  if not w.searchInput then return end
  local q = w.searchInput:getText()
  if #q < 2 then Devhud.setStatus("Type at least 2 characters to search.", true); return end
  Devhud.apply("dev.searchItems", { query = q }, function(ok, d)
    if ok and type(d) == "table" and type(d.items) == "table" then
      rebuildItemList(d.items)
      Devhud.setStatus(string.format("%d item(s) found.", #d.items))
    end
  end)
end

local function buildItemsList(panel)
  local section = g_ui.createWidget('DevHudSection', panel)
  section:setText("Give items (to backpack)")

  local searchRow = g_ui.createWidget('DevHudRow', panel)
  searchRow:setHeight(24)
  local searchBtn = g_ui.createWidget('DevHudButton', searchRow)
  searchBtn:setId('sbtn'); searchBtn:setText("Search"); searchBtn:setWidth(80)
  searchBtn:addAnchor(AnchorRight, 'parent', AnchorRight)
  searchBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  searchBtn.onClick = doSearch
  w.searchInput = g_ui.createWidget('TextEdit', searchRow)
  w.searchInput:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  w.searchInput:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  w.searchInput:addAnchor(AnchorRight, 'sbtn', AnchorLeft)
  w.searchInput:setMarginRight(6)
  w.searchInput.onEnter = doSearch

  w.listContent = g_ui.createWidget('DevHudTabPanel', panel)
end

-- ── tab entry ────────────────────────────────────────────────────────────────
local function build(self, panel)
  buildSet(panel)
  buildItemsList(panel)
end

Devhud.registerTab({
  id = "items",
  title = "Items",
  build = build,
  -- The picker floats on the root widget (above the HUD), so it must be torn down
  -- explicitly when the window closes or the session ends, or it orphans on screen.
  onClose = function() if w.picker then w.picker:destroy(); w.picker = nil end end,
})
