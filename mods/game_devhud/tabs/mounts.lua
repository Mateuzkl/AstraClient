--[[
  game_devhud / Mounts tab.

  A paged grid of cards, each rendering the mount preview (a UICreature whose outfit
  type is the mount's client looktype) + a Grant/Revoke button. "Give all" / "Remove
  all" re-fetch and repaint the grid (dev.getMounts / dev.setMount / dev.allMounts).
]]

local w = {}
local PAGE_SIZE = 18
local currentPage = 1
local entries = {}

-- oversized 4x4 mounts anchor at their top-left tile, so shift the lone preview
local function mountDrawOffset(clientId)
  local tt = g_things.getThingType(tonumber(clientId) or 0, ThingCategoryCreature)
  if not tt then return 0, 0 end
  local off = tt:getDrawOffset()
  if off and (off.x ~= 0 or off.y ~= 0) then return off.x, off.y end
  if tt:getWidth() == 4 and tt:getHeight() == 4 then return 32, 32 end
  return 0, 0
end

local function buildCard(m)
  local card = g_ui.createWidget('DevHudCard', w.grid)
  local preview = card:recursiveGetChildById('preview')
  preview:setOutfit({ type = m.clientId or 0 })
  if preview.setCenter then preview:setCenter(true) end
  if preview.setDrawOffset then
    local ox, oy = mountDrawOffset(m.clientId or 0)
    preview:setDrawOffset(ox, oy)
  end
  if preview.setAnimate then preview:setAnimate(false) end
  if preview.setIdleAnimate then preview:setIdleAnimate(false) end

  card:recursiveGetChildById('name'):setText(m.name)

  local act = card:recursiveGetChildById('act')
  act:setText(m.has and "Revoke" or "Grant")
  act.onClick = function()
    Devhud.apply("dev.setMount", { id = m.id, add = not m.has }, function(ok)
      if ok then m.has = not m.has; act:setText(m.has and "Revoke" or "Grant") end
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
  Devhud.apply("dev.getMounts", {}, function(ok, d)
    if ok and type(d) == "table" and type(d.mounts) == "table" then
      entries = d.mounts
      currentPage = 1
      renderPage()
      Devhud.setStatus(string.format("%d mount(s).", #entries))
    end
  end)
end

local function build(self, panel)
  local top = g_ui.createWidget('DevHudRow', panel)
  local allBtn = g_ui.createWidget('DevHudButton', top)
  allBtn:setId('all')
  allBtn:setText("Give all")
  allBtn:setWidth(110)
  allBtn:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  allBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  allBtn.onClick = function()
    Devhud.apply("dev.allMounts", { add = true }, function(ok) if ok then refresh() end end)
  end
  local noneBtn = g_ui.createWidget('DevHudButton', top)
  noneBtn:setId('none')
  noneBtn:setText("Remove all")
  noneBtn:setWidth(110)
  noneBtn:addAnchor(AnchorLeft, 'all', AnchorRight)
  noneBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  noneBtn:setMarginLeft(6)
  noneBtn.onClick = function()
    Devhud.apply("dev.allMounts", { add = false }, function(ok) if ok then refresh() end end)
  end
  local refBtn = g_ui.createWidget('DevHudButton', top)
  refBtn:setText("Refresh")
  refBtn:setWidth(90)
  refBtn:addAnchor(AnchorRight, 'parent', AnchorRight)
  refBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  refBtn.onClick = refresh

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

  w.grid = g_ui.createWidget('DevHudGrid', panel)
  w.grid:setHeight(500)
  refresh()
end

Devhud.registerTab({
  id = "mounts",
  title = "Mounts",
  build = build,
})
