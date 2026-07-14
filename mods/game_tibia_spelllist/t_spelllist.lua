t_spelllist = nil

local spellListData = {}
local rootPanel = nil
local lastHighlightWidget = nil
local spellListConfig = {}
local player = nil

function init()
  t_spelllist = g_ui.displayUI('t_spelllist')
  --t_spelllist:setContentMinimumHeight(195)
  t_spelllist:setup()
  t_spelllist:hide()

  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline
  })

  connect(LocalPlayer, {
    onSpellsChange = onSpellsChange,
    onLevelChange = onLevelChange
  })
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
    onLevelChange = onLevelChange
  })
end

function toggle()
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
  local benchmark = g_clock.millis()
  rootPanel = m_interface.getRootPanel()
  player = g_game.getLocalPlayer()

  spellListConfig = modules.game_sidebars.getSpellListConfig()
  if table.empty(spellListConfig) then
    spellListConfig = {
      ["showAttackSpellGroup"] = true,
      ["showDruidSpells"] = true,
      ["showFreeSpells"] = true,
      ["showHealingSpellGroup"] = true,
      ["showKnightSpells"] = true,
      ["showOnlyCurrentLevel"] = false,
      ["showOnlyCurrentVocation"] = false,
      ["showPaladinSpells"] = true,
      ["showPremiumOnlySpells"] = true,
      ["showSorcererSpells"] = true,
      ["showMonkSpells"] = true,
      ["showSupportSpellGroup"] = true,
      ["showUnkownSpells"] = true
    }
  end

  onConfigureList()
  consoleln("Spelllist loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function offline()
  spellListData = {}
  rootPanel = nil
  lastHighlightWidget = nil
  modules.game_sidebars.registerSpellListConfig(spellListConfig)
  modules.game_sidebars.saveConfigJson(true)
  spellListConfig = {}
  t_spelllist:close()
end

function onMiniWindowClose()
  modules.game_sidebuttons.setButtonVisible("spellListWidget", false)
end

function move(panel, height, minimized)
  t_spelllist:setParent(panel)
  t_spelllist:open()

  if minimized then
    t_spelllist:setHeight(height)
    t_spelllist:minimize()
  else
    t_spelllist:maximize()
    t_spelllist:setHeight(height)
  end

  modules.game_sidebuttons.setButtonVisible("spellListWidget", true)

  return t_spelllist
end

function getSpellListData()
  return spellListData
end

function onSpellsChange(player, list)
  spellListData = {}
  for _, spellId in pairs(list) do
    local spell = Spells.getSpellByClientId(spellId)
    if spell then
      spell.name = Spells.getSpellNameByWords(spell.words)
      spellListData[tostring(spellId)] = spell
    end
  end

  if not table.empty(spellListData) then
    onConfigureList()
  end
end

function onUpdateSpellListLevel()
  local player = g_game.getLocalPlayer()
  local list = t_spelllist:recursiveGetChildById("contentsPanel")

  for _, widget in pairs(list:getChildren()) do
    local disabled = widget:recursiveGetChildById('gray')
    disabled:setVisible(player:getLevel() < widget.spellData.level)
  end
end

function onConfigureList()
  local player = g_game.getLocalPlayer()
  local list = t_spelllist:recursiveGetChildById("contentsPanel")
  list.onChildFocusChange = nil

  list:destroyChildren()

  -- spellListData e indexado por tostring(spellId) (chaves string), entao table.sort
  -- direto nele e no-op. Copiamos para um array e ordenamos por nome para a lista sair
  -- em ordem alfabetica (senao as spells saem em ordem de hash e ficam impossiveis de achar).
  local sortedSpells = {}
  for _, spell in pairs(spellListData) do
    table.insert(sortedSpells, spell)
  end
  table.sort(sortedSpells, function(a, b) return (a.name or a.words) < (b.name or b.words) end)

  for _, spell in ipairs(sortedSpells) do
    if not matchFilter(spell) then
      goto continue
    end

    local widget = g_ui.createWidget("SpellListData", list)
    local image = widget:recursiveGetChildById('fixedImage')
    local dragImage = widget:recursiveGetChildById('moveableImage')
    local name = widget:recursiveGetChildById('name')
    local words = widget:recursiveGetChildById('words')
    local disabled = widget:recursiveGetChildById('gray')

    dragImage.onDragEnter = function(self, mousePos) onUpdateDragSpell(self, mousePos) end
    dragImage.onDragLeave = function(self, mousePos) onLeaveDragSpell(self, mousePos, widget) end

    widget.spellData = spell
    dragImage.words = spell.words
    local spellId = SpellIcons[spell.icon][1]
    local source = SpelllistSettings['Default'].iconsFolder
    local clip = Spells.getImageClipNormal(spellId, 'Default')

    image:setImageClip(clip)
    dragImage:setImageClip(clip)

    name:setText(short_text(spell.name, 15))
    if #spell.name > 15 then
      name:setTooltip(spell.name)
    end

    words:setText(short_text(spell.words, 17))
    if #spell.words > 17 then
      words:setTooltip(spell.words)
    end

    disabled:setVisible(player:getLevel() < spell.level)
    :: continue ::
  end

  onSelectedSpell(list, list:getFirstChild(), nil)
  list.onChildFocusChange = onSelectedSpell
end

function onSelectedSpell(list, focused, oldFocus)
  if not focused then
    return
  end

  if oldFocus then
    oldFocus:setBackgroundColor('alpha')
    oldFocus:recursiveGetChildById('words'):setColor("#c0c0c0")
    oldFocus:recursiveGetChildById('name'):setColor("#c0c0c0")
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
  t_spelllist:recursiveGetChildById('price'):setText(focused.spellData.price)

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
  local rootParent = rootPanel:getParent()
  self:setPhantom(true)
  self:setParent(rootParent)

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
end

function onLeaveDragSpell(self, mousePos, originalParent)
  local replacement = g_ui.createWidget("DraggableSpellIcon", originalParent)
  originalParent:moveChildToIndex(replacement, 2)
  replacement:addAnchor(AnchorTop, 'parent', AnchorTop)
  replacement:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  replacement:setImageSource(self:getImageSource())
  replacement:setImageClip(self:getImageClip())
  replacement:setMarginTop(2)
  replacement:setMarginLeft(2)
  replacement.words = self.words

  replacement.onDragEnter = function(self, mousePos) onUpdateDragSpell(self, mousePos) end
  replacement.onDragLeave = function(self, mousePos) onLeaveDragSpell(self, mousePos, originalParent) end
  self:destroy()

  if lastHighlightWidget then
    modules.game_actionbar.onDragSpellLeave(mousePos, replacement.words, lastHighlightWidget)
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

    lastHighlightWidget = nil
  end
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

function matchFilter(spell)
  local player = g_game.getLocalPlayer()
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

  if not canCheckAllVocations() then
    if not getSpellOption("showDruidSpells") then
      if spell.vocations and table.contains(spell.vocations, translateVocation(14)) then
        return false
      end
    end

    if not getSpellOption("showKnightSpells") then
      if spell.vocations and table.contains(spell.vocations, translateVocation(11)) then
        return false
      end
    end

    if not getSpellOption("showSorcererSpells") then
      if spell.vocations and table.contains(spell.vocations, translateVocation(13)) then
        return false
      end
    end

    if not getSpellOption("showPaladinSpells") then
      if spell.vocations and table.contains(spell.vocations, translateVocation(12)) then
        return false
      end
    end

    if not getSpellOption("showMonkSpells") then
      if spell.vocations and table.contains(spell.vocations, translateVocation(15)) then
        return false
      end
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

  if not getSpellOption("showFreeSpells") then
    return false
  end
  return true
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
  if level ~= oldLevel then
    onUpdateSpellListLevel()
  end
end
