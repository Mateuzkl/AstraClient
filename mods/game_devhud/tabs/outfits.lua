--[[
  game_devhud / Outfits tab.

  A paged grid of cards, each rendering the outfit preview (UICreature) + a
  Grant/Revoke button. "Give all (+addons)" / "Remove all" re-fetch and repaint the
  whole grid so the cards update instantly (dev.getOutfits / dev.setOutfit / dev.allOutfits).
]]

local w = {}
local PAGE_SIZE = 18
local currentPage = 1
local entries = {}

local function buildCard(o)
  local card = g_ui.createWidget('DevHudCard', w.grid)
  local preview = card:recursiveGetChildById('preview')
  preview:setOutfit({ type = o.lookType, addons = 3, mount = 0 })
  if preview.setAnimate then preview:setAnimate(false) end
  if preview.setIdleAnimate then preview:setIdleAnimate(false) end

  card:recursiveGetChildById('name'):setText(o.name)

  local act = card:recursiveGetChildById('act')
  act:setText(o.has and "Revoke" or "Grant")
  act.onClick = function()
    Devhud.apply("dev.setOutfit", { lookType = o.lookType, add = not o.has, addons = 3 }, function(ok)
      if ok then o.has = not o.has; act:setText(o.has and "Revoke" or "Grant") end
    end)
  end
end

local function renderPage()
  if not w.grid then return end
  w.grid:destroyChildren()
  local totalPages = math.max(1, math.ceil(#entries / PAGE_SIZE))
  currentPage = math.min(math.max(currentPage, 1), totalPages)
  local s = (currentPage - 1) * PAGE_SIZE + 1
  for i = s, math.min(s + PAGE_SIZE - 1, #entries) do buildCard(entries[i]) end
  if w.pageLabel then w.pageLabel:setText(string.format("Page %d / %d", currentPage, totalPages)) end
  if w.prevBtn then w.prevBtn:setEnabled(currentPage > 1) end
  if w.nextBtn then w.nextBtn:setEnabled(currentPage < totalPages) end
end

local function refresh()
  Devhud.apply("dev.getOutfits", {}, function(ok, d)
    if ok and type(d) == "table" and type(d.outfits) == "table" then
      entries = d.outfits
      currentPage = 1
      renderPage()
      Devhud.setStatus(string.format("%d outfit(s).", #entries))
    end
  end)
end

local function build(self, panel)
  -- row 1: give all / remove all / refresh
  local top = g_ui.createWidget('DevHudRow', panel)
  local allBtn = g_ui.createWidget('DevHudButton', top)
  allBtn:setId('all')
  allBtn:setText("Give all (+addons)")
  allBtn:setWidth(150)
  allBtn:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  allBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  allBtn.onClick = function()
    Devhud.apply("dev.allOutfits", { add = true }, function(ok) if ok then refresh() end end)
  end
  local noneBtn = g_ui.createWidget('DevHudButton', top)
  noneBtn:setId('none')
  noneBtn:setText("Remove all")
  noneBtn:setWidth(110)
  noneBtn:addAnchor(AnchorLeft, 'all', AnchorRight)
  noneBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  noneBtn:setMarginLeft(6)
  noneBtn.onClick = function()
    Devhud.apply("dev.allOutfits", { add = false }, function(ok) if ok then refresh() end end)
  end
  local refBtn = g_ui.createWidget('DevHudButton', top)
  refBtn:setText("Refresh")
  refBtn:setWidth(90)
  refBtn:addAnchor(AnchorRight, 'parent', AnchorRight)
  refBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  refBtn.onClick = refresh

  -- row 2: pager
  local nav = g_ui.createWidget('DevHudRow', panel)
  w.nextBtn = g_ui.createWidget('DevHudButton', nav)
  w.nextBtn:setId('pgnext') -- NOT 'next': that is a reserved anchor keyword (next sibling)
  w.nextBtn:setText(">")
  w.nextBtn:setWidth(40)
  w.nextBtn:addAnchor(AnchorRight, 'parent', AnchorRight)
  w.nextBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  w.nextBtn.onClick = function() currentPage = currentPage + 1; renderPage() end
  w.pageLabel = g_ui.createWidget('DevHudRowLabel', nav)
  w.pageLabel:setId('page')
  w.pageLabel:setText("Page 1 / 1")
  w.pageLabel:setWidth(110)
  w.pageLabel:setTextAlign(AlignCenter)
  w.pageLabel:addAnchor(AnchorRight, 'pgnext', AnchorLeft)
  w.pageLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  w.pageLabel:setMarginRight(6)
  w.prevBtn = g_ui.createWidget('DevHudButton', nav)
  w.prevBtn:setId('pgprev') -- NOT 'prev': reserved anchor keyword (previous sibling)
  w.prevBtn:setText("<")
  w.prevBtn:setWidth(40)
  w.prevBtn:addAnchor(AnchorRight, 'page', AnchorLeft)
  w.prevBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  w.prevBtn:setMarginRight(6)
  w.prevBtn.onClick = function() currentPage = currentPage - 1; renderPage() end

  -- grid
  w.grid = g_ui.createWidget('DevHudGrid', panel)
  w.grid:setHeight(500)
  refresh()
end

Devhud.registerTab({
  id = "outfits",
  title = "Outfits",
  build = build,
})
