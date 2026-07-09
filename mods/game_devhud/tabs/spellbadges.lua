--[[
  game_devhud / Spell Badges tab.

  Lists the spell-badge spells of the LOGGED-IN player's vocation (dev.getSpellBadges
  filters SpellBadge.SPELLS by vocation). Each row is the spell name + a "-1 / Lv N / +1"
  stepper: the two buttons upgrade / downgrade that spell's badge level by one (clamped to
  [0, the server's ceiling reported in dev.getSpellBadges]). Clicking applies immediately
  (dev.setSpellBadge -> SpellBadge.setLevel), optimistic: the server clamps identically so
  we paint the new level right away instead of waiting for the reply.
]]

local w = {}
local maxLevel = 100

-- Clamp to [0, maxLevel], repaint the row's level label + button enabled-states, and
-- (optionally) push the new level to the server. Optimistic: the server clamps to the
-- same range, so we don't wait for the reply (keeps rapid -1/+1 clicks responsive and
-- race-free).
local function applyLevel(ctx, newLevel, doSend)
  newLevel = math.max(0, math.min(maxLevel, math.floor(tonumber(newLevel) or 0)))
  ctx.level = newLevel
  ctx.lvl:setText('Lv ' .. newLevel)
  ctx.minus:setEnabled(newLevel > 0)
  ctx.plus:setEnabled(newLevel < maxLevel)
  if doSend then
    Devhud.apply("dev.setSpellBadge", { words = ctx.words, level = newLevel })
  end
end

local function makeRow(spell)
  local row = g_ui.createWidget('DevHudRow', w.list)
  row:setHeight(22)

  local ctx = { words = spell.words }

  -- +1 (rightmost): upgrade this spell's badge by one level
  ctx.plus = g_ui.createWidget('DevHudButton', row)
  ctx.plus:setId('plus')
  ctx.plus:setText('+1')
  ctx.plus:setWidth(34)
  ctx.plus:addAnchor(AnchorRight, 'parent', AnchorRight)
  ctx.plus:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  ctx.plus:setMarginRight(6)

  -- current level, shown between the two steppers
  ctx.lvl = g_ui.createWidget('DevHudRowLabel', row)
  ctx.lvl:setId('lvl')
  ctx.lvl:setWidth(52)
  ctx.lvl:setTextAlign(AlignCenter)
  ctx.lvl:addAnchor(AnchorRight, 'plus', AnchorLeft)
  ctx.lvl:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  ctx.lvl:setMarginRight(4)

  -- -1: downgrade this spell's badge by one level
  ctx.minus = g_ui.createWidget('DevHudButton', row)
  ctx.minus:setId('minus')
  ctx.minus:setText('-1')
  ctx.minus:setWidth(34)
  ctx.minus:addAnchor(AnchorRight, 'lvl', AnchorLeft)
  ctx.minus:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  ctx.minus:setMarginRight(4)

  -- spell name fills the remaining space on the left
  local label = g_ui.createWidget('DevHudRowLabel', row)
  label:setId('lbl')
  label:setText(spell.display)
  label:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  label:addAnchor(AnchorRight, 'minus', AnchorLeft)
  label:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  label:setMarginRight(8)

  ctx.plus.onClick  = function() applyLevel(ctx, ctx.level + 1, true) end
  ctx.minus.onClick = function() applyLevel(ctx, ctx.level - 1, true) end

  applyLevel(ctx, spell.level or 0, false) -- initial paint, no server round-trip
end

local function rebuild(spells)
  if not w.list then return end
  w.list:destroyChildren()
  if #spells == 0 then
    local none = g_ui.createWidget('DevHudRowLabel', w.list)
    none:setText("No spell badges for this vocation (or SpellBadge system off).")
    none:setColor("#9a9a9a")
    none:setHeight(20)
    return
  end
  for _, s in ipairs(spells) do makeRow(s) end
  Devhud.setStatus(string.format("%d spell badge(s), max level %d.", #spells, maxLevel))
end

local function refresh()
  Devhud.apply("dev.getSpellBadges", {}, function(ok, d)
    if ok and type(d) == "table" then
      if type(d.maxLevel) == "number" and d.maxLevel > 0 then maxLevel = d.maxLevel end
      if type(d.spells) == "table" then rebuild(d.spells) end
    end
  end)
end

local function build(self, panel)
  local top = g_ui.createWidget('DevHudRow', panel)
  local hint = g_ui.createWidget('DevHudRowLabel', top)
  hint:setText("Spells of your current vocation (-1 / +1 to downgrade or level up each badge):")
  hint:setColor("#9a9a9a")
  hint:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  hint:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  local refBtn = g_ui.createWidget('DevHudButton', top)
  refBtn:setText("Refresh")
  refBtn:setWidth(90)
  refBtn:addAnchor(AnchorRight, 'parent', AnchorRight)
  refBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  refBtn.onClick = refresh

  w.list = g_ui.createWidget('DevHudTabPanel', panel)
  refresh()
end

Devhud.registerTab({
  id = "spellbadges",
  title = "Spell Badges",
  build = build,
})
