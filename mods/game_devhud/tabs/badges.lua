--[[
  game_devhud / Badges tab.

  Shows each badge (DAMAGE / EXP / LOOT / POTION / HEAL) as its ITEM sprite with the
  current tier badge, plus an up/down stepper (0..maxTier). Changing the stepper
  applies (dev.setBadge) and repaints the sprite's tier so it always reflects reality.
]]

local w = {}
local maxTier = 10

local LABELS = {
  DAMAGE = "Attack (damage)",
  EXP = "Experience",
  LOOT = "Loot",
  POTION = "Potion",
  HEAL = "Healing",
}

local function makeRow(b)
  local row = g_ui.createWidget('DevHudItemRow', w.list)
  row:setHeight(38)

  local sprite = g_ui.createWidget('Item', row)
  sprite:setVirtual(true)
  if (b.itemId or 0) > 0 then sprite:setItemId(b.itemId) end
  if sprite.setTier then sprite:setTier(b.tier or 0) end
  sprite:setWidth(34)
  sprite:setHeight(34)
  sprite:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  sprite:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  sprite:setMarginLeft(2)

  local spin = g_ui.createWidget('SpinBox', row)
  spin:setId('spin')
  spin:setWidth(72)
  spin:setMinimum(0)
  spin:setMaximum(maxTier)
  spin:addAnchor(AnchorRight, 'parent', AnchorRight)
  spin:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  spin:setMarginRight(6)
  spin:setValue(b.tier or 0, true) -- dontSignal so loading doesn't fire an apply
  spin.onValueChange = function(widget, value)
    Devhud.apply("dev.setBadge", { key = b.key, tier = value }, function(ok)
      if ok and sprite.setTier then sprite:setTier(value) end
    end)
  end

  local label = g_ui.createWidget('DevHudRowLabel', row)
  label:setText(LABELS[b.key] or b.key)
  label:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  label:addAnchor(AnchorRight, 'spin', AnchorLeft)
  label:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  label:setMarginLeft(42)
end

local function rebuild(badges)
  if not w.list then return end
  w.list:destroyChildren()
  if #badges == 0 then
    local none = g_ui.createWidget('DevHudRowLabel', w.list)
    none:setText("No badge bag (or BadgeBag system off).")
    none:setColor("#9a9a9a")
    none:setHeight(20)
    return
  end
  for _, b in ipairs(badges) do makeRow(b) end
  Devhud.setStatus(string.format("%d badge(s).", #badges))
end

local function refresh()
  Devhud.apply("dev.getBadges", {}, function(ok, d)
    if ok and type(d) == "table" then
      if type(d.maxTier) == "number" and d.maxTier > 0 then maxTier = d.maxTier end
      if type(d.badges) == "table" then rebuild(d.badges) end
    end
  end)
end

local function build(self, panel)
  local top = g_ui.createWidget('DevHudRow', panel)
  local hint = g_ui.createWidget('DevHudRowLabel', top)
  hint:setText("Badge tiers (+/- to set, sprite shows the tier):")
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
  id = "badges",
  title = "Badges",
  build = build,
})
