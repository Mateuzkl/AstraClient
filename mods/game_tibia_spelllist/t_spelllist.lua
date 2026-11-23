t_spelllist = nil

local spellListData = {}
local spellRows = {}
local searchQuery = ''
local selectedSpellId = nil
local rootPanel = nil
local lastHighlightWidget = nil
local spellListConfig = {}
local defaultSpellListConfig = {
  showAttackSpellGroup = true,
  showDruidSpells = true,
  showFreeSpells = true,
  showHealingSpellGroup = true,
  showKnightSpells = true,
  showOnlyCurrentLevel = false,
  showOnlyCurrentVocation = false,
  showPaladinSpells = true,
  showPremiumOnlySpells = true,
  showSorcererSpells = true,
  showMonkSpells = true,
  showSupportSpellGroup = true,
  showUnkownSpells = true
}
local vocationFilters = {
  showSorcererSpells = 1,
  showDruidSpells = 2,
  showPaladinSpells = 3,
  showKnightSpells = 4,
  showMonkSpells = 9
}

local function normalizeSearch(text)
  return ((text or ''):lower():gsub('%s+', ' ')):trim()
end

local function setupSpellListSession()
  rootPanel = m_interface.getRootPanel()
  spellListConfig = table.copy(defaultSpellListConfig)
  for option, value in pairs(modules.game_sidebars.getSpellListConfig() or {}) do
    spellListConfig[option] = value
  end
end

function init()
  t_spelllist = g_ui.displayUI('t_spelllist')
  --t_spelllist:setContentMinimumHeight(195)
  t_spelllist:setup()
  t_spelllist:hide()
  t_spelllist.headPanel.spellSearch.onTextChange = onSearchTextChange

  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline
  })

  connect(LocalPlayer, {
    onSpellsChange = onSpellsChange,
    onLevelChange = onLevelChange,
    onVocationChange = onConfigureList
  })

  if g_game.isOnline() then
    online()
  end
end

function terminate()
  if t_spelllist then
    t_spelllist:destroy()
    t_spelllist = nil
  end

  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline
  })

  disconnect(LocalPlayer, {
    onSpellsChange = onSpellsChange,
    onLevelChange = onLevelChange,
    onVocationChange = onConfigureList
  })
end

function toggle()
  if g_game.isOnline() then
    online()
  end
  if t_spelllist:isVisible() then
    t_spelllist:close()
  else
    if t_spelllist:getHeight() < t_spelllist:getMinimumHeight() and not t_spelllist.minimized then
      t_spelllist:setHeight(t_spelllist:getMinimumHeight())
    end

    if m_interface.addToPanels(t_spelllist) then
      t_spelllist:getParent():moveChildToIndex(t_spelllist, #t_spelllist:getParent():getChildren())
      t_spelllist:open()
    else
      modules.game_sidebuttons.setButtonVisible("spellListWidget", false)
    end
  end
end

function online()
  if rootPanel then
    return
  end
  local benchmark = g_clock.millis()
  setupSpellListSession()
  local player = g_game.getLocalPlayer()
  if player then
    onSpellsChange(player, player.spellListIds or {})
  end
  consoleln("Spelllist loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function offline()
  local player = g_game.getLocalPlayer()
  if player then
    player.spellListIds = nil
  end
  if rootPanel then
    modules.game_sidebars.registerSpellListConfig(spellListConfig)
    modules.game_sidebars.saveConfigJson(true)
  end
  spellListData = {}
  rootPanel = nil
  lastHighlightWidget = nil
  searchQuery = ''
  t_spelllist.headPanel.spellSearch:clearText()
  rebuildSpellRows()
  spellListConfig = {}
  t_spelllist:close()
end

function onMiniWindowClose()
  modules.game_sidebuttons.setButtonVisible("spellListWidget", false)
end

function move(panel, height, minimized)
  if g_game.isOnline() then
    online()
  end
  t_spelllist:setParent(panel)
  t_spelllist:open()

  if minimized then
    t_spelllist:setHeight(math.max(height, t_spelllist:getMinimumHeight()))
    t_spelllist:minimize()
  else
    t_spelllist:maximize()
    t_spelllist:setHeight(math.max(height, t_spelllist:getMinimumHeight()))
  end

  modules.game_sidebuttons.setButtonVisible("spellListWidget", true)

  return t_spelllist
end

function getSpellListData()
  return spellListData
end

function onSpellsChange(player, list)
  -- Keep the server IDs on this player so a module reload can rebuild the rows.
  player.spellListIds = list
  if not rootPanel and g_game.isOnline() then
    -- The login signal can stop before reaching this module.
    setupSpellListSession()
  end
  spellListData = {}
  for _, spellId in ipairs(list) do
    local spell, _, name = Spells.getSpellByClientId(spellId)
    if spell then
      spell = table.copy(spell)
      spell.name = spell.name or name
      spellListData[tostring(spellId)] = spell
    end
  end

  if rootPanel then
    rebuildSpellRows()
  end
end

function onSearchTextChange(widget)
  local query = normalizeSearch(widget:getText())
  if searchQuery ~= query then
    searchQuery = query
    onConfigureList()
  end
end

function onShowMore()
  if selectedSpellId then
    modules.game_cyclopedia.openSpellDetails(selectedSpellId)
  end
end

local function setupDraggableSpell(icon, row, words)
  icon.words = words
  icon.onDragEnter = onUpdateDragSpell
  icon.onDragMove = onUpdateDragSpell
  icon.onDragLeave = function(self, _, mousePos)
    return onLeaveDragSpell(self, mousePos, row)
  end
end

function rebuildSpellRows()
  local list = t_spelllist.contentsPanel
  list.onChildFocusChange = nil
  local layout = list:getLayout()
  layout:disableUpdates()

  for _, row in ipairs(spellRows) do
    row:destroy()
  end
  spellRows = {}

  local spells = {}
  for _, spell in pairs(spellListData) do
    table.insert(spells, spell)
  end
  table.sort(spells, function(a, b)
    if a.name == b.name then
      return a.id < b.id
    end
    return a.name < b.name
  end)

  for _, spell in ipairs(spells) do
    local widget = g_ui.createWidget("SpellListData", list)
    local image = widget:recursiveGetChildById('fixedImage')
    local dragImage = widget:recursiveGetChildById('moveableImage')
    local name = widget:recursiveGetChildById('name')
    local words = widget:recursiveGetChildById('words')

    widget.spellData = spell
    widget.searchName = normalizeSearch(spell.name)
    widget.searchWords = normalizeSearch(spell.words)
    setupDraggableSpell(dragImage, widget, spell.words)
    local spellId = SpellIcons[spell.icon][1]
    local clip = Spells.getImageClipNormal(spellId, 'Default')

    image:setImageClip(clip)

    name:setText(short_text(spell.name, 15))
    if #spell.name > 15 then
      name:setTooltip(spell.name)
    end

    words:setText(short_text(spell.words, 17))
    if #spell.words > 17 then
      words:setTooltip(spell.words)
    end

    table.insert(spellRows, widget)
  end

  layout:enableUpdates()
  onConfigureList()
end

function onConfigureList()
  local player = rootPanel and g_game.getLocalPlayer()
  local list = t_spelllist.contentsPanel
  local oldFocus = list:getFocusedChild()
  local first, selected
  local layout = list:getLayout()
  list.onChildFocusChange = nil
  layout:disableUpdates()
  for _, row in ipairs(spellRows) do
    local spell = row.spellData
    local matchesQuery = searchQuery == '' or row.searchName:find(searchQuery, 1, true)
      or row.searchWords:find(searchQuery, 1, true)
    local matches = player and matchesQuery and matchFilter(spell, player)
    row:setVisible(matches and true or false)
    if matches then
      row.fixedImage:setImageColor(player:getLevel() < spell.level and '#909090' or 'white')
      first = first or row
      if spell.id == selectedSpellId then
        selected = row
      end
    end
  end
  list.emptySpellList:setText(searchQuery == '' and tr('No spells available') or tr('No matching spells'))
  list.emptySpellList:setVisible(first == nil)
  layout:enableUpdates()
  layout:update()

  selected = selected or first
  list:focusChild(selected, ActiveFocusReason)
  onSelectedSpell(list, selected, oldFocus)
  list.onChildFocusChange = onSelectedSpell
  if selected and list:isVisible() then
    list:ensureChildVisible(selected)
  end
end

function onSelectedSpell(list, focused, oldFocus, reason)
  if oldFocus and oldFocus ~= focused and not oldFocus:isDestroyed() then
    oldFocus:setBackgroundColor('alpha')
    oldFocus:recursiveGetChildById('words'):setColor("#c0c0c0")
    oldFocus:recursiveGetChildById('name'):setColor("#c0c0c0")
  end

  selectedSpellId = focused and focused.spellData.id or nil
  local details = t_spelllist.setupPanel
  for _, widget in ipairs(details:getChildren()) do
    widget:setVisible(focused ~= nil)
  end
  if not focused then
    for _, field in ipairs({ 'spellName', 'formula', 'vocation', 'group', 'type', 'cooldown', 'mana', 'lvlMin', 'premium', 'price' }) do
      details[field]:setText('')
      details[field]:removeTooltip()
    end
    return
  end

  if reason then
    UIScrollArea.onChildFocusChange(list, focused, oldFocus, reason)
  end

  focused:setBackgroundColor('#585858')
  focused:recursiveGetChildById('words'):setColor("#f4f4f4")
  focused:recursiveGetChildById('name'):setColor("#f4f4f4")
  t_spelllist:recursiveGetChildById('spellName'):setText(short_text(focused.spellData.name, 19))
  t_spelllist:recursiveGetChildById('spellName'):setTooltip('')
  if #focused.spellData.name > 18 then
    t_spelllist:recursiveGetChildById('spellName'):setTooltip(focused.spellData.name)
  end

  t_spelllist:recursiveGetChildById('formula'):setText(focused.spellData.words)
  t_spelllist:recursiveGetChildById('type'):setText(focused.spellData.type)
  t_spelllist:recursiveGetChildById('mana'):setText(tr('%s / %s', focused.spellData.mana, focused.spellData.soul))
  t_spelllist:recursiveGetChildById('lvlMin'):setText(focused.spellData.level)
  details.premium:setText(focused.spellData.premium and tr('Yes') or tr('No'))
  details.price:setText(focused.spellData.price or '-')
  details.gold:setVisible(focused.spellData.price ~= nil)

  local cooldownTime = focused.spellData.exhaustion / 1000
  local cooldownDesc = (cooldownTime > 60 and cooldownTime / 60 .. "min 0s" or cooldownTime .. "s")
  local groupDesc= ''
  local vocationDesc = ''

  for i, v in pairs(focused.spellData.group) do
    cooldownDesc = cooldownDesc .. " / " .. (v / 1000) .. "s"
    groupDesc = groupDesc .. SpellGroups[i] .. ", "
  end

  t_spelllist:recursiveGetChildById('cooldown'):setText(short_text(cooldownDesc, 10))
  t_spelllist:recursiveGetChildById('cooldown'):setTooltip('')
  if #cooldownDesc > 10 then
    t_spelllist:recursiveGetChildById('cooldown'):setTooltip(cooldownDesc)
  end

  groupDesc = string.sub(groupDesc, 1, -3)
  t_spelllist:recursiveGetChildById('group'):setTooltip('')
  t_spelllist:recursiveGetChildById('group'):setText(short_text(groupDesc, 9))
  if #cooldownDesc > 9 then
    t_spelllist:recursiveGetChildById('group'):setTooltip(groupDesc)
  end

  local index = 1
  for _, v in pairs(focused.spellData.vocations) do
    local name = VocationNames[v]
    if name then
      vocationDesc = vocationDesc .. name .. ", "
    end
  end

  vocationDesc = string.sub(vocationDesc, 1, -3)
  if #focused.spellData.vocations == 8 then
    vocationDesc = "All"
  end

  t_spelllist:recursiveGetChildById('vocation'):setText(short_text(vocationDesc, 10))
  t_spelllist:recursiveGetChildById('vocation'):setTooltip('')
  if #vocationDesc > 9 then
    t_spelllist:recursiveGetChildById('vocation'):setTooltip(vocationDesc)
  end
end

function onUpdateDragSpell(self, mousePos)
  if not rootPanel then
    return false
  end
  local rootParent = rootPanel:getParent()
  if self:getParent() ~= rootParent then
    local image = self:getParent().fixedImage
    self:setImageSource(image:getImageSource())
    self:setImageClip(image:getImageClip())
    self:setPhantom(true)
    self:setParent(rootParent)
  end

  self:setX(mousePos.x)
  self:setY(mousePos.y)

  if lastHighlightWidget then
    lastHighlightWidget:setBorderWidth(0)
    lastHighlightWidget:setBorderColor('alpha')
  end

  local clickedWidget = rootParent:recursiveGetChildByPos(mousePos, false)
  local dropInWidgetsPatterns = {
    "^item$",
    "^spellButton%d*$",
    "^attackSpellButton%d*$",
    "^spellTrainingButton%d*$",
    "^hasteButton%d*$"
  }

  local function matchesPattern(id, patterns)
    for _, pattern in ipairs(patterns) do
        if string.match(id, pattern) then
            return true
        end
    end
    return false
  end

  if not clickedWidget or not matchesPattern(clickedWidget:getId(), dropInWidgetsPatterns) then
    if lastHighlightWidget and matchesPattern(lastHighlightWidget:getId(), dropInWidgetsPatterns) then
      if lastHighlightWidget:getId() ~= "item" then
        lastHighlightWidget:setBorderColorTop("#1b1b1b")
        lastHighlightWidget:setBorderColorLeft("#1b1b1b")
        lastHighlightWidget:setBorderColorRight("#757575")
        lastHighlightWidget:setBorderColorBottom("#757575")
        lastHighlightWidget:setBorderWidth(1)
      end
    end
    lastHighlightWidget = nil
    return true
  end

  lastHighlightWidget = clickedWidget
  lastHighlightWidget:setBorderWidth(1)
  lastHighlightWidget:setBorderColor('white')
  return true
end

function onLeaveDragSpell(self, mousePos, originalParent)
  local words = self.words
  if not originalParent:isDestroyed() then
    local replacement = g_ui.createWidget("DraggableSpellIcon", originalParent)
    originalParent:moveChildToIndex(replacement, 2)
    replacement:addAnchor(AnchorTop, 'parent', AnchorTop)
    replacement:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    replacement:setMarginTop(2)
    replacement:setMarginLeft(2)
    setupDraggableSpell(replacement, originalParent, words)
  end
  self:destroy()

  if lastHighlightWidget and not lastHighlightWidget:isDestroyed() then
    modules.game_actionbar.onDragSpellLeave(mousePos, words, lastHighlightWidget)
    modules.game_helper.onDropSpell(lastHighlightWidget, words)

    if lastHighlightWidget:getId() == "item" then
      lastHighlightWidget:setBorderWidth(0)
      lastHighlightWidget:setBorderColor('alpha')
    else
      lastHighlightWidget:setBorderColorTop("#1b1b1b")
      lastHighlightWidget:setBorderColorLeft("#1b1b1b")
      lastHighlightWidget:setBorderColorRight("#757575")
      lastHighlightWidget:setBorderColorBottom("#757575")
      lastHighlightWidget:setBorderWidth(1)
    end
  end
  lastHighlightWidget = nil
  return true
end

function onExtraMenu()
  local mousePosition = g_window.getMousePosition()
  if cancelNextRelease then
    cancelNextRelease = false
    return false
  end

  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  menu:addCheckBoxOption('Character Vocation', function() setSpellOption("showOnlyCurrentVocation", not getSpellOption("showOnlyCurrentVocation")) onConfigureList() end, "", spellListConfig["showOnlyCurrentVocation"])
  menu:addCheckBoxOption('Character Level', function() setSpellOption("showOnlyCurrentLevel", not getSpellOption("showOnlyCurrentLevel")) onConfigureList() end, "", spellListConfig["showOnlyCurrentLevel"])
  menu:addCheckBoxOption('Learnt Spells', function() setSpellOption("showUnkownSpells", not getSpellOption("showUnkownSpells")) onConfigureList() end, "", spellListConfig["showUnkownSpells"])
  menu:addSeparator()

  menu:addCheckBoxOption('Druid', function() setSpellOption("showDruidSpells", not getSpellOption("showDruidSpells")) onConfigureList() end, "", spellListConfig["showDruidSpells"])
  menu:addCheckBoxOption('Knight', function() setSpellOption("showKnightSpells", not getSpellOption("showKnightSpells")) onConfigureList() end, "", spellListConfig["showKnightSpells"])
  menu:addCheckBoxOption('Paladin', function() setSpellOption("showPaladinSpells", not getSpellOption("showPaladinSpells")) onConfigureList() end, "", spellListConfig["showPaladinSpells"])
  menu:addCheckBoxOption('Sorcerer', function() setSpellOption("showSorcererSpells", not getSpellOption("showSorcererSpells")) onConfigureList() end, "", spellListConfig["showSorcererSpells"])
  menu:addCheckBoxOption('Monk', function() setSpellOption("showMonkSpells", not getSpellOption("showMonkSpells")) onConfigureList() end, "", spellListConfig["showMonkSpells"])
  menu:addCheckBoxOption('All Vocations', function() checkAllVocations() onConfigureList() end, "", canCheckAllVocations()) -- true se todos tiverem marcados
  menu:addSeparator()

  menu:addCheckBoxOption('Attack', function() setSpellOption("showAttackSpellGroup", not getSpellOption("showAttackSpellGroup")) onConfigureList() end, "", spellListConfig["showAttackSpellGroup"])
  menu:addCheckBoxOption('Healing', function() setSpellOption("showHealingSpellGroup", not getSpellOption("showHealingSpellGroup")) onConfigureList() end, "", spellListConfig["showHealingSpellGroup"])
  menu:addCheckBoxOption('Support', function() setSpellOption("showSupportSpellGroup", not getSpellOption("showSupportSpellGroup")) onConfigureList() end, "", spellListConfig["showSupportSpellGroup"])
  menu:addCheckBoxOption('All Spell Groups', function() checkAllGroups() onConfigureList() end, "", canCheckAllGroups()) -- true se todos tiverem marcados
  menu:addSeparator()
  menu:addCheckBoxOption('Premium Account', function() setSpellOption("showPremiumOnlySpells", not getSpellOption("showPremiumOnlySpells")) onConfigureList() end, "", spellListConfig["showPremiumOnlySpells"])
  menu:addCheckBoxOption('Free Account', function() setSpellOption("showFreeSpells", not getSpellOption("showFreeSpells")) onConfigureList() end, "", spellListConfig["showFreeSpells"])
  menu:display(mousePosition)
  return true
end

function matchFilter(spell, player)
  if getSpellOption("showOnlyCurrentVocation") then
    if spell.vocations and not table.contains(spell.vocations, translateVocation(player:getVocation())) then
      return false
    end
  end

  if getSpellOption("showOnlyCurrentLevel") then
    if player:getLevel() < spell.level then
      return false
    end
  end

  if spell.vocations and next(spell.vocations) and not canCheckAllVocations() then
    local matchesVocation = false
    for option, vocation in pairs(vocationFilters) do
      if getSpellOption(option) and table.contains(spell.vocations, translateVocation(vocation)) then
        matchesVocation = true
        break
      end
    end
    if not matchesVocation then
      return false
    end
  end

  if not canCheckAllGroups() then
    local list = {{name = "showAttackSpellGroup", type = "Attack"}, {name = "showHealingSpellGroup", type = "Healing"}, {name = "showSupportSpellGroup", type = "Support"}}
    for _, k in pairs(list) do
      if not getSpellOption(k.name) then
        local found = false
        for i, v in pairs(spell.group) do
          if SpellGroups[i] == k.type then
            found = true
            break
          end
        end

        if found then
          return false
        end
      end
    end
  end

  if spell.premium then
    return getSpellOption("showPremiumOnlySpells")
  end
  return getSpellOption("showFreeSpells")
end

-- Helpers
function setSpellOption(option, value)
  spellListConfig[option] = value
end

function getSpellOption(option)
  return spellListConfig[option]
end

function canCheckAllVocations()
  local druid = getSpellOption("showDruidSpells")
  local knight = getSpellOption("showKnightSpells")
  local paladin = getSpellOption("showPaladinSpells")
  local sorcerer = getSpellOption("showSorcererSpells")
  local monk = getSpellOption("showMonkSpells")
  return druid and knight and paladin and sorcerer and monk
end

function canCheckAllGroups()
  local attack = getSpellOption("showAttackSpellGroup")
  local healing = getSpellOption("showHealingSpellGroup")
  local support = getSpellOption("showSupportSpellGroup")
  return attack and healing and support
end

function checkAllVocations()
  local canCheck = not canCheckAllVocations()
  setSpellOption("showDruidSpells", canCheck)
  setSpellOption("showKnightSpells", canCheck)
  setSpellOption("showPaladinSpells", canCheck)
  setSpellOption("showSorcererSpells", canCheck)
  setSpellOption("showMonkSpells", canCheck)
end

function checkAllGroups()
  local canCheck = not canCheckAllGroups()
  setSpellOption("showAttackSpellGroup", canCheck)
  setSpellOption("showHealingSpellGroup", canCheck)
  setSpellOption("showSupportSpellGroup", canCheck)
end

function onLevelChange(localPlayer, level, levelPercent, oldLevel, oldLevelPercent)
  if rootPanel and level ~= oldLevel then
    onConfigureList()
  end
end
