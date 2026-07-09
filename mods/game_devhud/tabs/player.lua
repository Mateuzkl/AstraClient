--[[
  game_devhud / Player tab.

  Mutates the local player: level, skills (classic + attack speed, mining, magic,
  reflect, mitigation), stamina and outfit addons. Level / skill / stamina use
  VALIDATED text inputs (digits only, range-checked before sending) so an invalid
  value never reaches the server. Every control sends a dev.* action through
  Devhud.apply; the server echoes a fresh snapshot which onState() reads back.
]]

-- skill picker: caption -> dev.setSkill key. Order drives the combo box.
local SKILLS = {
  { "Fist", "fist" }, { "Club", "club" }, { "Sword", "sword" }, { "Axe", "axe" },
  { "Distance", "distance" }, { "Shielding", "shielding" }, { "Fishing", "fishing" },
  { "Magic Level", "magic" }, { "Attack Speed", "attackSpeed" }, { "Mining", "mining" },
  { "Reflect", "reflect" }, { "Mitigation", "mitigation" },
}

-- widgets we refresh from the server snapshot
local w = {}

-- ── small builders (anchors, not layouts, so rows align cleanly) ─────────────
local function section(panel, text)
  local s = g_ui.createWidget('DevHudSection', panel)
  s:setText(text)
end

local function addLabel(row, text, width)
  local l = g_ui.createWidget('DevHudRowLabel', row)
  l:setId('lbl')
  l:setText(text)
  l:setWidth(width or 110)
  l:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  l:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  return l
end

local function addButtonRight(row, text, width, fn)
  local b = g_ui.createWidget('DevHudButton', row)
  b:setId('btn')
  b:setText(text)
  b:setWidth(width or 60)
  b:addAnchor(AnchorRight, 'parent', AnchorRight)
  b:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  b.onClick = fn
  return b
end

-- label + digits-only text input + apply button
local function labeledInput(panel, labelText, btnText, fn)
  local row = g_ui.createWidget('DevHudRow', panel)
  addLabel(row, labelText)
  addButtonRight(row, btnText, 60, fn)
  local t = g_ui.createWidget('DevHudInput', row)
  t:setId('fld')
  if t.setValidCharacters then t:setValidCharacters('0123456789') end
  t:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  t:addAnchor(AnchorLeft, 'lbl', AnchorRight)
  t:addAnchor(AnchorRight, 'btn', AnchorLeft)
  t:setMarginLeft(6)
  t:setMarginRight(6)
  return t
end

-- read + validate an integer input; on failure flashes the footer and returns nil
local function validated(input, min, max, label)
  local n = tonumber(input:getText())
  if not n then
    Devhud.setStatus(label .. ": enter a number.", true)
    return nil
  end
  n = math.floor(n)
  if n < min or n > max then
    Devhud.setStatus(string.format("%s must be between %d and %d.", label, min, max), true)
    return nil
  end
  return n
end

-- ── snapshot readers ─────────────────────────────────────────────────────────
local function skillCurrentValue(state, key)
  if not state then return 0 end
  if key == "magic" then return state.magic or 0 end
  if key == "reflect" then return state.reflect or 0 end
  if key == "mitigation" then return state.mitigation or 0 end
  return (state.skills and state.skills[key]) or 0
end

local function updateSkillValueField()
  if not w.skillCombo or not w.skillValue then return end
  local opt = w.skillCombo:getCurrentOption()
  if not opt then return end
  w.skillValue:setText(tostring(skillCurrentValue(Devhud.getState(), opt.data)))
end

-- ── build ────────────────────────────────────────────────────────────────────
local function build(self, panel)
  -- Character
  section(panel, "Character")
  w.level = labeledInput(panel, "Level", "Apply", function()
    local n = validated(w.level, 1, 100000, "Level")
    if n then Devhud.apply("dev.setLevel", { level = n }) end
  end)
  w.stamina = labeledInput(panel, "Stamina (min)", "Apply", function()
    local n = validated(w.stamina, 0, 2520, "Stamina")
    if n then Devhud.apply("dev.setStamina", { minutes = n }) end
  end)

  -- Skills (pick one, set its value)
  section(panel, "Skills")
  local srow = g_ui.createWidget('DevHudRow', panel)
  local combo = g_ui.createWidget('ComboBox', srow)
  combo:setId('cmb')
  combo:setWidth(130)
  combo:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  combo:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  for _, s in ipairs(SKILLS) do combo:addOption(s[1], s[2]) end
  w.skillCombo = combo

  addButtonRight(srow, "Apply", 60, function()
    local opt = combo:getCurrentOption()
    if not opt then return end
    local n = validated(w.skillValue, 0, 100000, "Skill")
    if n then Devhud.apply("dev.setSkill", { skill = opt.data, level = n }) end
  end)

  local sval = g_ui.createWidget('DevHudInput', srow)
  sval:setId('fld')
  if sval.setValidCharacters then sval:setValidCharacters('0123456789') end
  sval:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  sval:addAnchor(AnchorLeft, 'cmb', AnchorRight)
  sval:addAnchor(AnchorRight, 'btn', AnchorLeft)
  sval:setMarginLeft(6)
  sval:setMarginRight(6)
  w.skillValue = sval

  combo.onOptionChange = function() updateSkillValueField() end
end

-- ── refresh fields from the authoritative snapshot ───────────────────────────
local function onState(self, state)
  if not state then return end
  if w.level then w.level:setText(tostring(state.level or 1)) end
  if w.stamina then w.stamina:setText(tostring(state.stamina or 0)) end
  updateSkillValueField()
end

Devhud.registerTab({
  id = "player",
  title = "Player",
  build = build,
  onState = onState,
})
