--[[
  Craft Panel - client-side crafting UI over CommandBridge (extended opcode 211).

  The server (data-koliseu/scripts/custom/craft_otc_bridge.lua) drives everything:
    - pushes a flat catalog via the "craft.open" event when the player uses a
      Crafting Station (or any repointed forge totem),
    - answers craft.list (refresh) and craft.execute requests.

  This module only renders the catalog and relays craft requests. Recipe data,
  material/money checks and the consume+deliver are 100% server-side (reused from
  the existing CraftingSystem). Adapted from the AMON game_craft module, restyled
  to the CipSoft dark theme and reshaped to vocation tabs + a flat recipe list.
]]

local window = nil
local confirmWindow = nil
local recipeGroup = nil

local catalog = { recipes = {}, gold = 0, coins = 0 }
local recipesById = {}

local VOCATIONS = { "knight", "paladin", "sorcerer", "druid", "all" }
local VOC_TAB_ID = {
  knight = "tabKnight", paladin = "tabPaladin", sorcerer = "tabSorcerer",
  druid = "tabDruid", all = "tabAll",
}
local BASE_TO_VOC = { Knight = "knight", Paladin = "paladin", Sorcerer = "sorcerer", Druid = "druid" }

local currentVoc = "knight"
local selectedRecipeId = nil
local pendingCraftId = nil
local openHandler = nil

local OK_COLOR = "#7dd37d"
local MISS_COLOR = "#d37d7d"

-- forward declarations (internal locals referenced across function bodies)
local formatPrice
local recipeMatchesFilter, vocationHasRecipes, firstVocationWithRecipes
local populateInputs, renderDetail, populateList
local applyCatalog, onCraftResponse, openConfirm

-- ============================================================================
-- helpers
-- ============================================================================

-- price is in kk (millions of gold). Mirrors server crafting_lib.formatPrice.
function formatPrice(priceKk)
  priceKk = tonumber(priceKk) or 0
  if priceKk < 1000 then
    return string.format("%d kk", priceKk)
  end
  local kkk = math.floor(priceKk / 1000)
  local remainder = priceKk % 1000
  if remainder == 0 then
    return string.format("%d kkk", kkk)
  end
  return string.format("%d.%03d kkk", kkk, remainder)
end

function recipeMatchesFilter(recipe)
  return recipe.vocation == currentVoc
end

function vocationHasRecipes(voc)
  for _, recipe in ipairs(catalog.recipes) do
    if recipe.vocation == voc then return true end
  end
  return false
end

function firstVocationWithRecipes()
  for _, v in ipairs(VOCATIONS) do
    if vocationHasRecipes(v) then return v end
  end
  return nil
end

-- ============================================================================
-- detail panel
-- ============================================================================

function populateInputs(recipe)
  if not window then return end
  local list = window:recursiveGetChildById('inputListPanel')
  if not list then return end
  list:destroyChildren()
  if not recipe then return end

  for _, input in ipairs(recipe.inputs or {}) do
    local row = g_ui.createWidget('CraftInputRow', list)
    local icon = row:getChildById('inputIcon')
    if icon then icon:setItemId(input.itemId or 0) end
    local name = row:getChildById('inputName')
    if name then name:setText(string.format("%dx %s", input.count or 0, input.name or "?")) end
    local have = row:getChildById('inputHave')
    if have then
      local h = input.have or 0
      have:setText(string.format("%d / %d", h, input.count or 0))
      have:setColor(h >= (input.count or 0) and OK_COLOR or MISS_COLOR)
    end
  end
end

function renderDetail(recipe)
  if not window then return end
  local detailItem = window:recursiveGetChildById('detailItem')
  local detailName = window:recursiveGetChildById('detailName')
  local detailResult = window:recursiveGetChildById('detailResult')
  local costLabel = window:recursiveGetChildById('costLabel')
  local craftButton = window:recursiveGetChildById('craftButton')
  local statusText = window:recursiveGetChildById('statusText')

  if not recipe then
    if detailItem then detailItem:setItemId(0) end
    if detailName then detailName:setText(tr("Select a recipe")) end
    if detailResult then detailResult:setText("") end
    if costLabel then costLabel:setText("") end
    if craftButton then craftButton:setEnabled(false) end
    populateInputs(nil)
    if statusText then statusText:setText("") end
    return
  end

  if detailItem then detailItem:setItemId(recipe.resultItemId or 0) end
  if detailName then detailName:setText(recipe.title or "?") end
  if detailResult then
    local count = recipe.resultCount or 1
    if count > 1 then
      detailResult:setText(string.format("Produces: %dx %s", count, recipe.title or "?"))
    else
      detailResult:setText(string.format("Produces: %s", recipe.title or "?"))
    end
  end

  populateInputs(recipe)

  if costLabel then
    local lines = {}
    local affordable = true
    if (recipe.price or 0) > 0 then
      lines[#lines + 1] = string.format("Cost: %s gold", formatPrice(recipe.price))
      if (catalog.gold or 0) < recipe.price * 1000000 then affordable = false end
    end
    if (recipe.coins or 0) > 0 then
      lines[#lines + 1] = string.format("%d tibia coins", recipe.coins)
      if (catalog.coins or 0) < recipe.coins then affordable = false end
    end
    costLabel:setText(table.concat(lines, "\n"))
    costLabel:setColor(affordable and OK_COLOR or MISS_COLOR)
  end

  if craftButton then craftButton:setEnabled(recipe.canCraft == true) end
  if statusText then
    if recipe.canCraft then
      statusText:setText("Ready to craft")
      statusText:setColor(OK_COLOR)
    else
      statusText:setText("Missing materials or gold")
      statusText:setColor(MISS_COLOR)
    end
  end
end

-- ============================================================================
-- recipe list
-- ============================================================================

function populateList()
  if not window then return end
  local list = window:recursiveGetChildById('recipeListPanel')
  if not list then return end

  list:destroyChildren()
  if recipeGroup then
    recipeGroup:destroy()
    recipeGroup = nil
  end
  recipeGroup = UIRadioGroup.create()

  local visible = {}
  for _, recipe in ipairs(catalog.recipes) do
    if recipeMatchesFilter(recipe) then
      visible[#visible + 1] = recipe
    end
  end
  -- craftable first, then alphabetical
  table.sort(visible, function(a, b)
    local ac, bc = a.canCraft and true or false, b.canCraft and true or false
    if ac ~= bc then return ac end
    return (a.title or "") < (b.title or "")
  end)

  for _, recipe in ipairs(visible) do
    local row = g_ui.createWidget('CraftRecipeRow', list)
    row.recipeId = recipe.id
    local item = row:getChildById('resultItem')
    if item then item:setItemId(recipe.resultItemId or 0) end
    local name = row:getChildById('resultName')
    if name then name:setText(recipe.title or "?") end
    local status = row:getChildById('statusLabel')
    if status then
      status:setText(recipe.canCraft and "OK" or "X")
      status:setColor(recipe.canCraft and OK_COLOR or MISS_COLOR)
    end
    recipeGroup:addWidget(row)
  end

  recipeGroup.onSelectionChange = function(_, selected)
    if not selected or not selected.recipeId then return end
    selectedRecipeId = selected.recipeId
    renderDetail(recipesById[selectedRecipeId])
  end

  -- keep prior selection if still visible, else select the first visible recipe
  local keep = nil
  if selectedRecipeId then
    for _, recipe in ipairs(visible) do
      if recipe.id == selectedRecipeId then keep = selectedRecipeId break end
    end
  end
  if not keep and #visible > 0 then keep = visible[1].id end

  if keep then
    selectedRecipeId = keep
    for _, row in ipairs(list:getChildren()) do
      if row.recipeId == keep then
        recipeGroup:selectWidget(row)
        break
      end
    end
    renderDetail(recipesById[keep])
  else
    selectedRecipeId = nil
    renderDetail(nil)
  end
end

function applyCatalog(data)
  if type(data) ~= "table" then return end
  catalog.recipes = data.recipes or {}
  catalog.gold = data.gold or 0
  catalog.coins = data.coins or 0
  recipesById = {}
  for _, recipe in ipairs(catalog.recipes) do
    recipesById[recipe.id] = recipe
  end
end

-- ============================================================================
-- craft + confirmation
-- ============================================================================

function openConfirm(recipe)
  closeConfirm()
  confirmWindow = g_ui.createWidget('CraftConfirmWindow', g_ui.getRootWidget())
  if not confirmWindow then return end
  pendingCraftId = recipe.id

  local item = confirmWindow:recursiveGetChildById('confirmItem')
  if item then item:setItemId(recipe.resultItemId or 0) end
  local title = confirmWindow:recursiveGetChildById('confirmTitle')
  if title then title:setText(string.format("Craft %s?", recipe.title or "this item")) end

  local msg = confirmWindow:recursiveGetChildById('confirmMessage')
  if msg then
    local cost = {}
    if (recipe.price or 0) > 0 then cost[#cost + 1] = formatPrice(recipe.price) .. " gold" end
    if (recipe.coins or 0) > 0 then cost[#cost + 1] = recipe.coins .. " tibia coins" end
    local text = "The required materials will be consumed."
    if #cost > 0 then
      text = text .. "\nCost: " .. table.concat(cost, " + ")
    end
    msg:setText(text)
  end

  confirmWindow:show()
  confirmWindow:raise()
  confirmWindow:focus()
  confirmWindow:lockScrim()
end

function onCraftResponse(response)
  if not window then return end
  if type(response) ~= "table" then return end
  if response.type == "error" then
    local statusText = window:recursiveGetChildById('statusText')
    if statusText then
      statusText:setText(response.message or "Craft failed")
      statusText:setColor(MISS_COLOR)
    end
    return
  end

  local data = response.data or response
  applyCatalog(data)
  populateList()

  local statusText = window:recursiveGetChildById('statusText')
  if statusText and data.crafted then
    statusText:setText("Crafted successfully")
    statusText:setColor(OK_COLOR)
  end
end

-- ============================================================================
-- OTUI-facing entry points (modules.game_craft.*)
-- ============================================================================

function selectVocation(voc)
  if not window or not VOC_TAB_ID[voc] then return end
  currentVoc = voc
  for v, id in pairs(VOC_TAB_ID) do
    local btn = window:recursiveGetChildById(id)
    if btn then btn:setOn(v == voc) end
  end
  selectedRecipeId = nil
  populateList()
end

function onCraftClick()
  local recipe = recipesById[selectedRecipeId]
  if recipe then openConfirm(recipe) end
end

function confirmCraft()
  if not pendingCraftId then return end
  if not CommandBridge or not CommandBridge.request then return end
  local id = pendingCraftId
  local yesBtn = confirmWindow and confirmWindow:recursiveGetChildById('confirmYes')
  if yesBtn then yesBtn:setEnabled(false) end
  CommandBridge.request("craft.execute", { id = id }, onCraftResponse)
  closeConfirm()
end

function closeConfirm()
  pendingCraftId = nil
  if confirmWindow then
    confirmWindow:unlockScrim()
    confirmWindow:destroy()
    confirmWindow = nil
  end
end

-- ============================================================================
-- window lifecycle
-- ============================================================================

function show(payload)
  close()
  window = g_ui.createWidget('CraftWindow', g_ui.getRootWidget())
  if not window then return end

  applyCatalog(payload)

  -- default the tab to the player's vocation (fall back to a populated tab)
  local voc = "all"
  local p = g_game.getLocalPlayer()
  if p then voc = BASE_TO_VOC[g_game.getVocationNameBase(p:getVocation())] or "all" end
  if not vocationHasRecipes(voc) then voc = firstVocationWithRecipes() or "all" end
  selectVocation(voc)

  window:show()
  window:raise()
  window:focus()
  window:lockScrim()  -- modal: overlay escuro que captura o mouse atras (sem freeze)
end

-- Open from the side button (no server-pushed event): request a fresh catalog.
function toggle()
  if window then close() return end
  if not CommandBridge or not CommandBridge.request then return end
  CommandBridge.request("craft.list", {}, function(response)
    if type(response) ~= "table" or response.type == "error" then return end
    local data = response.data or response
    if type(data) == "table" and data.recipes then show(data) end
  end)
end

function close()
  closeConfirm()
  if recipeGroup then
    recipeGroup:destroy()
    recipeGroup = nil
  end
  if window then
    window:unlockScrim()
    window:destroy()
    window = nil
  end
  selectedRecipeId = nil
  if modules.game_interface then
    local panel = modules.game_interface.getRootPanel()
    if panel then panel:focus() end
  end
end

function onOpenEvent(data)
  local payload = data and (data.data or data)
  if type(payload) ~= "table" or type(payload.recipes) ~= "table" then return end
  show(payload)
end

-- ============================================================================
-- init / terminate
-- ============================================================================

function onGameStart()
  if not CommandBridge or not CommandBridge.on then return end
  openHandler = onOpenEvent
  CommandBridge.on("craft.open", openHandler)
end

function onGameEnd()
  if openHandler and CommandBridge and CommandBridge.off then
    CommandBridge.off("craft.open", openHandler)
    openHandler = nil
  end
  close()
end

function init()
  g_ui.importStyle(resolvepath('craft'))
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  onGameEnd()
end
