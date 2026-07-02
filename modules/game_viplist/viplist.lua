vipWindow = nil
addVipWindow = nil
addGroupWindow = nil
editVipWindow = nil
stateChange = false
vipGroups = {}
maxVipGroups = nil
editableGroupCount = nil

-- cache
vipCache = {}

local settings = {
  ["contentHeight"] = 0,
  ["contentMaximized"] = true,
  ["hideOfflineVips"] = false,
  ["showGrouped"] = false,
  ["vipSortOrder"] = {}
}

local vipStateNames = {
  [VipState.Online] = "Online",
  [VipState.Offline] = "Offline",
  [VipState.Pending] = "Pending",
  [VipState.Training] = "Exercise Dummy Training",
  [VipState.Prestige] = "Prestige Arena"
}

local keybindOpenVip = KeyBind:getKeyBind("Windows", "Show/hide VIP list")

function init()
  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = clear,
    onAddVip = onAddVip,
    onVipStateChange = onVipStateChange,
    onReceiveVipGroups = onReceiveVipGroups
  })

  keybindOpenVip:active()

  vipWindow = g_ui.loadUI('viplist', m_interface.getRightPanel())
  vipWindow:hide()

  -- this disables scrollbar auto hiding
  local scrollbar = vipWindow:getChildById('miniwindowScrollBar')
  scrollbar:mergeStyle({ ['$!on'] = { }})

  if g_game.isOnline() then
    onGameStart()
  end

  vipWindow:setup()
end

function terminate()
  keybindOpenVip:deactive()
  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = clear,
    onAddVip = onAddVip,
    onVipStateChange = onVipStateChange,
    onReceiveVipGroups = onReceiveVipGroups
  })

  if addVipWindow then
    addVipWindow:destroy()
    addVipWindow = nil
  end

  if addGroupWindow then
    addGroupWindow:destroy()
    addGroupWindow = nil
  end

  if stateChange then
    stateChange = false
  end

  if editVipWindow then
    editVipWindow:destroy()
    editVipWindow = nil
  end

  vipCache = {}
  vipWindow:destroy()
  vipWindow = nil
end

function onGameStart()
  local benchmark = g_clock.millis()
  refresh()
  consoleln("VIP list loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function refresh()
  if not g_game.isOnline() then
    return
  end

  clear()
  stateChange = false
  for id,vip in pairs(g_game.getVips()) do
    if settings["showGrouped"] then
      local name, state, description, iconId, notify, partyPending, groups = unpack(vip)
      vipCache[tostring(id)] = {playerId = id, playerName = name, vipState = state, vipDesc = description, icon = iconId, hasNotify = notify, partyPending = partyPending, vipGroups = groups}
    else
      onAddVip(id, unpack(vip))
    end
  end

  if settings["showGrouped"] then
    showGroups()
  end

  vipWindow:setContentMinimumHeight(43)
end

function clear()
  local vipList = vipWindow:getChildById('contentsPanel')
  vipList:destroyChildren()

  if not g_game.isOnline() then
    vipCache = {}
    vipGroups = {}
    modules.game_sidebars.registerVipListConfig(settings)
    modules.game_sidebars.saveConfigJson(true)
  end
end

function toggle()
  if vipWindow:isVisible() then
    vipWindow:close()
    modules.game_sidebuttons.setButtonVisible("vipWidget", false)
  else
    if m_interface.addToPanels(vipWindow) then
      modules.game_sidebuttons.setButtonVisible("vipWidget", true)
      vipWindow:getParent():moveChildToIndex(vipWindow, #vipWindow:getParent():getChildren())
      vipWindow:open()
    else
      modules.game_sidebuttons.setButtonVisible("vipWidget", false)
    end
  end
end

function close()
  vipWindow:close()
end

function onMiniWindowClose()
  modules.game_sidebuttons.setButtonVisible("vipWidget", false)
end

function onReceiveVipGroups(groups, maxGroups, editableGroups)
  vipGroups = groups
  maxVipGroups = maxGroups
  editableGroupCount = editableGroups
  refresh()
end

function createAddWindow()
  if not addVipWindow then
    addVipWindow = g_ui.displayUI('addvip')
    g_client.setInputLockWidget(addVipWindow)
  end
end

function createAddGroupWindow()
  if (maxVipGroups or 0) < 1 then
    displayInfoBox(tr("Maximum of User-Created Groups Reached"), "You have already reached the maximum of groups you can create yourself.")
    return
  end

  if not addGroupWindow then
    addGroupWindow = g_ui.displayUI('addgroup')
    addGroupWindow:setText(tr(addGroupWindow:getText(), maxVipGroups))
    g_client.setInputLockWidget(addGroupWindow)
  end
end

function createEditGroupWindow(name, id)
  if addGroupWindow then
    return
  end

  if not addGroupWindow then
    addGroupWindow = g_ui.displayUI('addgroup')
    addGroupWindow:setText("Edit VIP group")
    addGroupWindow.header:setText("Please enter a group name:")
    addGroupWindow.name:setText(name)
    addGroupWindow.onEnter = function() editGroup(id) end
    addGroupWindow.okButton.onClick = function() editGroup(id) end
    g_client.setInputLockWidget(addGroupWindow)
  end
end

function createEditWindow(widget)
  if editVipWindow then
    return
  end

  editVipWindow = g_ui.displayUI('editvip')
  editVipWindow:setHeight(344 + ((editableGroupCount or 0) * 15))
  g_client.setInputLockWidget(editVipWindow)

  local name = widget:getText()
  local id = widget:getId():sub(4)

  editVipWindow.groups:destroyChildren()
  table.sort(vipGroups, function(a, b) return a[1] > b[1] end)
  for _, data in ipairs(vipGroups) do
    local wd = g_ui.createWidget("VipGroupBox", editVipWindow.groups)
    wd:setText(data[2])
    wd.id = data[1]
    if g_game.playerInGroup(id, data[1]) then
      wd:setChecked(true, true)
    end
  end

  local okButton = editVipWindow:getChildById('buttonOK')
  local cancelButton = editVipWindow:getChildById('buttonCancel')

  local nameLabel = editVipWindow:getChildById('nameLabel')
  nameLabel:setText(name)

  local descriptionText = editVipWindow:getChildById('descriptionText')
  descriptionText:appendText(widget.comment)

  local notifyCheckBox = editVipWindow:recursiveGetChildById('checkBoxNotify')
  notifyCheckBox:setChecked(widget.notifyLogin)

  local iconRadioGroup = UIRadioGroup.create()
  for i = VipIconFirst, VipIconLast do
    iconRadioGroup:addWidget(editVipWindow:recursiveGetChildById('icon' .. i))
  end
  iconRadioGroup:selectWidget(editVipWindow:recursiveGetChildById('icon' .. (widget.iconId and widget.iconId or 0)))

  local cancelFunction = function()
    g_client.setInputLockWidget(nil)
    editVipWindow:destroy()
    iconRadioGroup:destroy()
    editVipWindow = nil
  end

  local saveFunction = function()
    local name = widget:getText()
    local state = widget.vipState
    local description = descriptionText:getText()
    local iconId = tonumber(iconRadioGroup:getSelectedWidget():getId():sub(5))
    local notify = notifyCheckBox:isChecked()
    local partyPending = widget.partyPending

    local groups = {}
    for _, child in pairs(editVipWindow.groups:getChildren()) do
      if child:isChecked() then
        table.insert(groups, child.id)
      end
    end

    g_game.editVip(id, description, iconId, notify, groups)

    widget:destroy()
    stateChange = false
    onAddVip(id, name, state, description, iconId, notify, partyPending, groups, nil)

    g_client.setInputLockWidget(nil)
    editVipWindow:destroy()
    iconRadioGroup:destroy()
    editVipWindow = nil
  end

  cancelButton.onClick = cancelFunction
  okButton.onClick = saveFunction

  editVipWindow.onEscape = cancelFunction
  editVipWindow.onEnter = saveFunction
end

function destroyAddWindow()
  g_client.setInputLockWidget(nil)
  addVipWindow:destroy()
  addVipWindow = nil
end

function addVip()
  g_game.addVip(addVipWindow:getChildById('name'):getText():trim())
  destroyAddWindow()
end

function addGroup()
  g_client.setInputLockWidget(nil)
  g_game.sendVipGroup(1, 0, addGroupWindow:getChildById('name'):getText())
  addGroupWindow:destroy()
  addGroupWindow = nil
end

function editGroup(id)
  g_client.setInputLockWidget(nil)
  g_game.sendVipGroup(2, id, addGroupWindow:getChildById('name'):getText())
  addGroupWindow:destroy()
  addGroupWindow = nil
end

function removeVip(widgetOrName)
  if not widgetOrName then
    return
  end

  local widget
  local vipList = vipWindow:getChildById('contentsPanel')
  if type(widgetOrName) == 'string' then
    local entries = vipList:getChildren()
    for i = 1, #entries do
      if entries[i]:getText():lower() == widgetOrName:lower() then
        widget = entries[i]
        break
      end
    end
    if not widget then
      return
    end
  else
    widget = widgetOrName
  end

  if widget then
    local id = widget:getId():sub(4)
    g_game.removeVip(id)
    if settings["showGrouped"] then
      local parentWidget = widget:getParent()
      if parentWidget then
        parentWidget:removeChild(widget)
      end
    else
      vipList:removeChild(widget)
    end

    vipCache[tostring(id)] = nil
    refresh()
  end
end

function hideOffline(state)
  settings["hideOfflineVips"] = state
  refresh()
end

function getSortedBy()
  if not settings["vipSortOrder"] then
    return ''
  end
  return settings["vipSortOrder"][1]
end

function sortBy(state)
  for i, v in ipairs(settings["vipSortOrder"]) do
    if v == state then
      table.remove(settings["vipSortOrder"], i)
      break
    end
  end

  table.insert(settings["vipSortOrder"], 1, state)
  refresh()
end

function canRefreshVipGroups(id, name, state, description, iconId, notify, partyPending, groups)
  local cacheKey = tostring(id)
  local old = vipCache[cacheKey]

  if not old or #old.vipGroups ~= #groups then
    return true
  end

  if old.playerName ~= name or
     old.vipState ~= state or
     old.vipDesc ~= description or
     old.icon ~= iconId or
     old.hasNotify ~= notify or
     old.partyPending ~= partyPending then
    return true
  end

  for i = 1, #groups do
    if old.vipGroups[i] ~= groups[i] then
      return true
    end
  end

  return false
end

function onAddGroupedVip(id, name, state, description, iconId, notify, partyPending, groups)
  local canRefresh = canRefreshVipGroups(id, name, state, description, iconId, notify, partyPending, groups)

  -- Update cache
  vipCache[tostring(id)] = {playerId = id, playerName = name, vipState = state, vipDesc = description, icon = iconId, hasNotify = notify, partyPending = partyPending, vipGroups = groups}

  if canRefresh then
    refresh()
  end
end

function onAddVip(id, name, state, description, iconId, notify, partyPending, groups, stateChange)
	if not name or name:len() == 0 then
		return
	end

  if settings["showGrouped"] then
    onAddGroupedVip(id, name, state, description, iconId, notify, partyPending, groups)
    return
  end

	vipCache[tostring(id)] = {playerId = id, playerName = name, vipState = state, vipDesc = description, icon = iconId, hasNotify = notify, partyPending = partyPending, vipGroups = groups}

	local vipList = vipWindow:getChildById("contentsPanel")
	local childrenCount = vipList:getChildCount()
	if stateChange then
		for i = 1, childrenCount do
			local child = vipList:getChildByIndex(i)
			if child.realName == name then
				setVipState(child, state, step)
        child.partyPending = partyPending
        child.vipState = state 
        child:setTooltip(tr("Name: %s\nStatus: %s", name, vipStateNames[state]))
        if state == VipState.Online then
          child:setVisible(true)
        elseif state == VipState.Offline and settings["hideOfflineVips"] then
          child:setVisible(false)
        end
				return
			end
		end
	end
	for i = 1, childrenCount do
		local child = vipList:getChildByIndex(i)
		if child.realName == name then
      child.partyPending = partyPending
			return
		end
	end

  for i = 1, childrenCount do
		local child = vipList:getChildByIndex(i)
    local childId = string.match(child:getId(), "%d+")
    if tonumber(childId) == id and name ~= child.realName then
      child:setText(short_text(name, 17))
      child.realName = name
      child.partyPending = partyPending
      child:setTooltip(tr("Name: %s\nStatus: %s", name, vipStateNames[state]))
      setVipState(child, state, step)
      return
    end
  end

	local label = g_ui.createWidget("VipListLabel")
	label.onMousePress = onVipListLabelMousePress
	label:setId("vip" .. id)
	label:setText(short_text(name, 17))
  label.realName = name
  label:setTooltip(tr("Name: %s\nStatus: %s", name, vipStateNames[state]))
  label:setImageClip(torect(iconId * 12 .. " 0 12 12"))
  label.iconId = iconId
  label.notifyLogin = notify
  g_mouse.bindPress(label, function(mousePos, mouseMoved) if g_keyboard.isShiftPressed() then g_game.talk(tr("exiva \"%s\"",name)) end end)
	setVipState(label, state, step)
	label.vipState = state
  label.comment = description
  label.partyPending = partyPending
	label:setPhantom(false)
	connect(label, {
		onDoubleClick = function()
      if g_keyboard.isShiftPressed() then
        return true
      end
			g_game.openPrivateChannel(label.realName)
			return true
		end
	})
	if state == VipState.Offline and settings["hideOfflineVips"] then
		label:setVisible(false)
	end
	local nameLower = name:lower()
	local childrenCount = vipList:getChildCount()
	for i = 1, childrenCount do
		local child = vipList:getChildByIndex(i)
		if state == VipState.Online and child.vipState ~= VipState.Online and getSortedBy() == "byState" or label.iconId > child.iconId and getSortedBy() == "byType" then
			vipList:insertChild(i, label)
			return
		end
		if (state ~= VipState.Online and child.vipState ~= VipState.Online or state == VipState.Online and child.vipState == VipState.Online) and getSortedBy() == "byState" or label.iconId == child.iconId and getSortedBy() == "byType" or getSortedBy() == "byName" then
			local childText = (child:getText()):lower()
			local length = math.min(childText:len(), nameLower:len())
			for j = 1, length do
				if nameLower:byte(j) < childText:byte(j) then
					vipList:insertChild(i, label)
					return
				elseif nameLower:byte(j) > childText:byte(j) then
					break
				elseif j == nameLower:len() then
					vipList:insertChild(i, label)
					return
				end
			end
		end
	end
	vipList:insertChild(childrenCount + 1, label)
end

function onVipStateChange(id, state, groups)
  local cache = vipCache[tostring(id)]
  local name = cache.playerName
  local description = cache.vipDesc
  local iconId = cache.icon
  local notify = cache.hasNotify
  local partyPending = cache.partyPending

  onAddVip(id, name, state, description, iconId, notify, partyPending, groups, true)

  if notify then
    if (state == VipState.Online or state == VipState.Offline) then
      modules.game_textmessage.displayFailureMessage(tr('%s has logged %s.', name, (state == VipState.Online and 'in' or 'out')))
    elseif (state == VipState.Training) then
      modules.game_textmessage.displayFailureMessage(tr('%s has started training.', name))
    end
  end

  local function updateVipLabel(label)
    if label then
      setVipState(label, state)
      label:setTooltip(tr("Name: %s\nStatus: %s", name, vipStateNames[state]))
    end
  end
  
  -- Update VIP states
  local vipList = vipWindow:getChildById('contentsPanel')
  if settings["showGrouped"] then
    for _, groupId in pairs(groups) do
      local groupWidget = vipList:recursiveGetChildById("group-" .. groupId)
      if groupWidget then
        for _, label in pairs(groupWidget.panel:getChildren()) do
          if label:getId() == string.format("vip%s", id) then
            updateVipLabel(label)
          end
        end
      end
    end
  else
    local label = vipList:recursiveGetChildById(string.format("vip%s", id))
    updateVipLabel(label)
  end
end

function setVipState(label, state, step)
  local step = step or 0
  if state == VipState.Online then
    if stateChange and step < 1 then
	    label:setColor('#ffffff')
      blinkEvent = scheduleEvent(function() setVipState(label, state, step+1) end, 1000)
    else
	    label:setColor('#5ff75f')
      blinkEvent = nil
    end
  end
  if state == VipState.Pending then
    label:setColor('#ffca38')
  elseif state == VipState.Offline then
    blinkEvent = nil
    label:setColor('#f75f5f')
  elseif state == VipState.Training then
    label:setColor('#9966CC')
  elseif state == VipState.Prestige then
    label:setColor("#00ffff")
  end

end

function onVipListMousePress(widget, mousePos, mouseButton)
  if mouseButton ~= MouseRightButton then return end

  local vipList = vipWindow:getChildById('contentsPanel')

  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  menu:addOption(tr('Add new VIP'), function() createAddWindow() end)
  menu:addSeparator()

  menu:addOption(tr('Add new group'), function() createAddGroupWindow() end)

  menu:addSeparator()
  menu:addOption(tr('Sort by name'), function() sortBy('byName') end)
  menu:addOption(tr('Sort by type'), function() sortBy('byType') end)
  menu:addOption(tr('Sort by status'), function() sortBy('byState') end)

  if not settings["hideOfflineVips"] then
    menu:addOption(tr('Hide offline VIPs'), function() hideOffline(true) end)
  else
    menu:addOption(tr('Show offline VIPs'), function() hideOffline(false) end)
  end

  if not settings["showGrouped"] then
    menu:addOption(tr('Show groups'), function() settings["showGrouped"] = true showGroups() end)
  else
    menu:addOption(tr('Hide groups'), function() settings["showGrouped"] = false refresh() end)
  end

  menu:display(mousePos)
  return true
end

function onVipListLabelMousePress(widget, mousePos, mouseButton)
  if mouseButton ~= MouseRightButton then return end

  local isGroup = string.find(widget:getId(), "group")
  local label = string.find(widget:getId(), "vip")
  local vipList = vipWindow:getChildById('contentsPanel')
  local menu = g_ui.createWidget('PopupMenu')
  local player = g_game.getLocalPlayer()
  menu:setGameMenu(true)

  if not isGroup then
    if label and (widget.vipState == VipState.Online or widget.vipState == VipState.Training) then
      menu:addOption(tr('Exiva %s', widget:getText()), function() g_game.talk(tr("exiva \"%s\"", widget.realName)) end)
    end
    menu:addOption(tr('Edit %s', widget:getText()), function() if widget then createEditWindow(widget) end end)
    menu:addOption(tr('Remove %s', widget:getText()), function() if widget then removeVip(widget) end end)
    if label and (widget.vipState == VipState.Online or widget.vipState == VipState.Training) then
      menu:addOption(tr('Message to %s', widget:getText()), function() g_game.openPrivateChannel(widget.realName) end)
      if not (player:isPartyMember() and not player:isPartyLeader()) and player:getName() ~= widget.realName then
        if player:isPartyLeader() and player:isInSameParty(widget.realName) then
          menu:addOption(tr('Pass Leadership to %s', widget.realName), function() g_game.partyPassLeadership(player:getPartyCreatureId(widget.realName)) end)
        else
          if widget.partyPending then
            menu:addOption(tr('Join %s party', widget.realName), function() g_game.partyJoin(0, widget.realName) end)
          else
            menu:addOption(tr('Invite %s to party', widget.realName), function() g_game.partyInvite(0, widget.realName) end)
          end
        end
      end
    end
  end
  menu:addOption(tr('Add new VIP'), function() createAddWindow() end)

  menu:addSeparator()
  if isGroup and widget.ediatable then
    local name = widget:getTooltip() and widget:getTooltip() or widget.group:getText()
    menu:addOption(tr('Edit group %s', name), function() createEditGroupWindow(name, widget.groupId) end)
    menu:addOption(tr('Remove group %s', name), function() g_game.sendVipGroup(3, widget.groupId, "") end)
  end
  menu:addOption(tr('Add new group'), function() createAddGroupWindow() end)

  menu:addSeparator()
  menu:addOption(tr('Sort by name'), function() sortBy('byName') end)
  menu:addOption(tr('Sort by type'), function() sortBy('byType') end)
  menu:addOption(tr('Sort by status'), function() sortBy('byState') end)

  if not settings["hideOfflineVips"] then
    menu:addOption(tr('Hide offline VIPs'), function() hideOffline(true) end)
  else
    menu:addOption(tr('Show offline VIPs'), function() hideOffline(false) end)
  end

  if not settings["showGrouped"] then
    menu:addOption(tr('Show groups'), function() settings["showGrouped"] = true showGroups() end)
  else
    menu:addOption(tr('Hide groups'), function() settings["showGrouped"] = false refresh() end)
  end

  if not isGroup then
    menu:addSeparator()
    menu:addOption(tr('Report Name'), function() end)

    menu:addSeparator()
    menu:addOption(tr('Copy Name'), function() g_window.setClipboardText(widget.realName) end)
  end

  menu:display(mousePos)
  return true
end

function move(panel, height, minimized)
  vipWindow:setParent(panel)
  vipWindow:open()

  if minimized then
    vipWindow:setHeight(height)
    vipWindow:minimize()
  else
    vipWindow:maximize()
    vipWindow:setHeight(height)
  end

  return vipWindow
end

function showGroups()
  local vipList = vipWindow:getChildById("contentsPanel")
  vipList:destroyChildren()

  table.sort(vipGroups, function(a, b) return a[2] < b[2] end)

  for _, data in pairs(vipGroups) do
    local players = getPlayersByGroup(data[1])
    if #players == 0 then
      goto continue
    end

    local groupWidget = g_ui.createWidget("VipGroupList", vipList)
    groupWidget.group:setText(short_text(data[2], 18))
    if #data[2] >= 18 then
      groupWidget:setTooltip(data[2])
    end
    groupWidget:setId("group-" .. data[1])
    groupWidget.onMousePress = onVipListLabelMousePress
    groupWidget.groupId = data[1]
    groupWidget.ediatable = data[3]

    local visiblePlayers = 0
    for _, k in pairs(players) do
      groupWidget:setSize("156 " .. groupWidget:getHeight() + 16)
      local label = g_ui.createWidget("VipListLabel", groupWidget.panel)
      label.onMousePress = onVipListLabelMousePress
      label:setId("vip" .. k.playerId)
      label:setText(short_text(k.playerName, 17))
      label:setTooltip(tr("Name: %s\nStatus: %s", k.playerName, vipStateNames[k.vipState]))
      label:setImageClip(torect(k.icon * 12 .. " 0 12 12"))
      label.iconId = k.icon
      label.notifyLogin = k.hasNotify
      label.vipState = k.vipState
      label.realName = k.playerName
      label.comment = k.vipDesc
      label.partyPending = k.partyPending

      g_mouse.bindPress(label, function(mousePos, mouseMoved) if g_keyboard.isShiftPressed() then g_game.talk(tr("exiva \"%s\"", k.playerName)) end end)

      setVipState(label, k.vipState, step)
      label:setPhantom(false)
      connect(label, {
        onDoubleClick = function()
          g_game.openPrivateChannel(label.realName)
          return true
        end
      })

      if k.vipState == VipState.Offline and settings["hideOfflineVips"] then
        label:setVisible(false)
        groupWidget:setSize("156 " .. groupWidget:getHeight() - 15)
      else
        visiblePlayers = visiblePlayers + 1
      end

      -- Sort types
      local nameLower = k.playerName:lower()
      local childrenCount = groupWidget.panel:getChildCount()
      local sortedBy = getSortedBy()

      for i = 1, childrenCount do
        local child = groupWidget.panel:getChildByIndex(i)

        local shouldMoveByState = (k.vipState == VipState.Online and child.vipState ~= VipState.Online) and sortedBy == "byState"
        local shouldMoveByType = (label.iconId > child.iconId) and sortedBy == "byType"
        local shouldMoveByName = false

        if sortedBy == "byName" then
          local childText = child:getText():lower()
          if nameLower < childText then
            shouldMoveByName = true
          end
        end

        if shouldMoveByState or shouldMoveByType or shouldMoveByName then
          groupWidget.panel:moveChildToIndex(label, i)
          break
        end
      end
    end

    if visiblePlayers == 0 then
      groupWidget:hide()
    end

    :: continue ::
  end

  local players = getPlayersNoGroup()
  local noGroupWidget = g_ui.createWidget("VipGroupList", vipList)
  noGroupWidget.onMousePress = onVipListLabelMousePress
  noGroupWidget:setId("group")

  local visiblePlayers = 0
  for _, k in pairs(players) do
    noGroupWidget:setSize("156 " .. noGroupWidget:getHeight() + 15)
    local label = g_ui.createWidget("VipListLabel", noGroupWidget.panel)
    label.onMousePress = onVipListLabelMousePress
    label:setId("vip" .. k.playerId)
    label:setText(short_text(k.playerName, 17))
    label:setTooltip(tr("Name: %s\nStatus: %s", k.playerName, vipStateNames[k.vipState]))
    label:setImageClip(torect(k.icon * 12 .. " 0 12 12"))
    label.iconId = k.icon
    label.notifyLogin = k.hasNotify
    label.vipState = k.vipState
    label.realName = k.playerName
    label.comment = k.vipDesc
    label.partyPending = k.partyPending
    g_mouse.bindPress(label, function(mousePos, mouseMoved) if g_keyboard.isShiftPressed() then g_game.talk(tr("exiva \"%s\"", k.playerName)) end end)
    setVipState(label, k.vipState, step)
    label:setPhantom(false)
    connect(label, {
      onDoubleClick = function()
        g_game.openPrivateChannel(label.realName)
        return true
      end
    })

    if k.vipState == VipState.Offline and settings["hideOfflineVips"] then
      label:setVisible(false)
    else
      visiblePlayers = visiblePlayers + 1
    end

    -- Sort types
    local nameLower = k.playerName:lower()
    local childrenCount = noGroupWidget.panel:getChildCount()
    local sortedBy = getSortedBy()

    for i = 1, childrenCount do
      local child = noGroupWidget.panel:getChildByIndex(i)

      local shouldMoveByState = (k.vipState == VipState.Online and child.vipState ~= VipState.Online) and sortedBy == "byState"
      local shouldMoveByType = (label.iconId > child.iconId) and sortedBy == "byType"
      local shouldMoveByName = false

      if sortedBy == "byName" then
        local childText = child:getText():lower()
        if nameLower < childText then
          shouldMoveByName = true
        end
      end

      if shouldMoveByState or shouldMoveByType or shouldMoveByName then
        noGroupWidget.panel:moveChildToIndex(label, i)
        break
      end
    end
  end
  if visiblePlayers == 0 then
    noGroupWidget:hide()
  end
end

---- helper functions
function getPlayersByGroup(groupId)
  local players = {}
  for _, data in pairs(vipCache) do
    if data.vipGroups and table.contains(data.vipGroups, groupId) then
      table.insert(players, data)
    end
  end

  return players
end

function getPlayersNoGroup()
  local players = {}
  for _, data in pairs(vipCache) do
    if not data.vipGroups or #data.vipGroups == 0 then
      table.insert(players, data)
    end
  end
  return players
end

function onPlayerLoad(config)
  if config["contentHeight"] == nil then
    settings = {
      ["contentHeight"] = 0,
      ["contentMaximized"] = 0,
      ["hideOfflineVips"] = false,
      ["showGrouped"] = false,
      ["vipSortOrder"] = {}
    }
  else
    settings = config
  end
end
