Options = {}

Options.array = {}

Options.hotkeySets = nil
Options.profiles = nil
Options.pinnedCharacters = nil

Options.currentHotkeySetName = nil
Options.currentHotkeySet = nil
Options.actionBarOptions = nil
Options.actionBarMappings = nil

Options.clientOptions = nil
Options.actionBar = {}

Options.isChatOnEnabled = false
Options.chatOptions = nil

function Options.setChatMode(enabled, temporary)
	-- The temporary chat mode ("Chat On*", opened with Enter while chat is off) only
	-- flips the runtime flag so the hotkey sets swap while the player types; it must not
	-- touch the saved preference, otherwise a single Enter after turning chat off rewrites
	-- chatModeOn back to on and the choice is lost on the next launch. Deliberate toggles
	-- (the Chat On/Off button) omit temporary and persist as before.
	if not temporary then
		Options.chatOptions["chatModeOn"] = enabled
	end
	Options.isChatOnEnabled = enabled
end

function Options.createOrUpdateText(actionBar, slot, words, sendAutomatic)
	local foundEntry = false
	for _, data in pairs(Options.actionBarMappings) do
		if data["actionBar"] == actionBar and data["actionButton"] == slot then
			data["actionsetting"] = {}
			data["actionsetting"]["chatText"] = words
			data["actionsetting"]["sendAutomatically"] = sendAutomatic
			foundEntry = true
			break
		end
	end

	if not foundEntry then
		Options.actionBarMappings[#Options.actionBarMappings + 1] = {
			["actionBar"] = actionBar,
			["actionButton"] = slot,
			["actionsetting"] = {
				["chatText"] = words,
				["sendAutomatically"] = sendAutomatic
			}
		}
	end
end

function Options.createOrUpdatePassive(actionBar, slot, passiveId)
	local foundEntry = false
	for _, data in pairs(Options.actionBarMappings) do
		if data["actionBar"] == actionBar and data["actionButton"] == slot then
			data["actionsetting"] = {}
			data["actionsetting"]["passiveAbility"] = passiveId
			foundEntry = true
			break
		end
	end

	if not foundEntry then
		Options.actionBarMappings[#Options.actionBarMappings + 1] = {
			["actionBar"] = actionBar,
			["actionButton"] = slot,
			["actionsetting"] = {
				["passiveAbility"] = passiveId
			}
		}
	end
end

function Options.removeAction(actionBar, slot)
	for i, data in pairs(Options.actionBarMappings) do
		if data["actionBar"] == actionBar and data["actionButton"] == slot then
			table.remove(Options.actionBarMappings, i)
			break
		end
	end
end

function Options.removeHotkey(buttonId)
	if not buttonId then
		return
	end

	Options.validateHotkeySet()
	if not Options.array or not Options.array["hotkeyOptions"] or not Options.array["hotkeyOptions"]["hotkeySets"] then
		return
	end
	local currentOption = Options.isChatOnEnabled and Options.currentHotkeySet["chatOn"] or Options.currentHotkeySet["chatOff"]
	for i, data in pairs(currentOption) do
		if data["actionsetting"] and data["actionsetting"]["action"] and (data["actionsetting"]["action"] == "TriggerActionButton_" .. buttonId) then
			table.remove(currentOption, i)
			break
		end
	end
end

function Options.getCurrentOption()
  Options.validateHotkeySet()

  if not Options.array then return end

  local hotkeyOptions = Options.array.hotkeyOptions

  if not hotkeyOptions or not hotkeyOptions.hotkeySets then return end

  return Options.isChatOnEnabled and Options.currentHotkeySet.chatOn or Options.currentHotkeySet.chatOff
end

function isCustomAction(data)
  return not data["actionsetting"] or not data["actionsetting"]["action"]
end

-- Limpa todas actions com essa hotkey
function Options.clearHotkey(hotkey)
  local currentOption = Options.getCurrentOption()
  if not currentOption then return end

  for i, data in pairs(currentOption) do
    if isCustomAction(data) then
      if data.keysequence == hotkey then
        data.keysequence = ""
      end
      if data.secondarySequence == hotkey then
        data.secondarySequence = ""
      end

      goto continue
    end

    if data.keysequence == hotkey then
      table.remove(currentOption, i)
    end

    ::continue::
  end
end

function Options.removeSecondHotkey(buttonId)
	Options.validateHotkeySet()
	if not Options.array or not Options.array["hotkeyOptions"] or not Options.array["hotkeyOptions"]["hotkeySets"] then
		return
	end
	local currentOption = Options.isChatOnEnabled and Options.currentHotkeySet["chatOn"] or Options.currentHotkeySet["chatOff"]
	for i, data in pairs(currentOption) do
		if data["secondary"] and data["actionsetting"] and data["actionsetting"]["action"] and (data["actionsetting"]["action"] == "TriggerActionButton_" .. buttonId) then
			print("remove second")
			table.remove(currentOption, i)
			break
		end
	end
end

function Options.removeActionHotkey(chatType, action, isSecondary)
	if isSecondary == nil then
		isSecondary = false
	end

	Options.validateHotkeySet()
	if not Options.array or not Options.array["hotkeyOptions"] or not Options.array["hotkeyOptions"]["hotkeySets"] then
		return
	end
	for i, data in pairs(Options.currentHotkeySet[chatType]) do
		if data["actionsetting"] and data["actionsetting"]["action"] and (data["actionsetting"]["action"] == action) then
			if (not isSecondary and data["secondary"]) or (isSecondary and not data["secondary"]) then
				goto continue
			end
			table.remove(Options.currentHotkeySet[chatType], i)
			break
		end

		:: continue ::
	end
end

function Options.updateActionBarHotkey(buttonDesc, hotkey)
	Options.validateHotkeySet()
	if not Options.array or not Options.array["hotkeyOptions"] or not Options.array["hotkeyOptions"]["hotkeySets"] then
		return
	end

	local foundEntry = false
	local currentOption = Options.isChatOnEnabled and Options.currentHotkeySet["chatOn"] or Options.currentHotkeySet["chatOff"]
	for i, data in pairs(currentOption) do
		if data["actionsetting"] and data["actionsetting"]["action"] and data["actionsetting"]["action"] == buttonDesc then
			data["keysequence"] = hotkey
			foundEntry = true
			break
		end
	end

	if not foundEntry then
		currentOption[#currentOption + 1] = {
			["actionsetting"] = {
				["action"] = buttonDesc
			},
			["keysequence"] = hotkey
		}
	end
end

function Options.updateActionMenuHotkey(isChatOn, buttonDesc, hotkey, isSecondary)
	Options.validateHotkeySet()
	if not Options.array or not Options.array["hotkeyOptions"] or not Options.array["hotkeyOptions"]["hotkeySets"] then
		return
	end
	local foundEntry = false
	local currentOption = isChatOn and Options.currentHotkeySet["chatOn"] or Options.currentHotkeySet["chatOff"]
	for i, data in pairs(currentOption) do
		if data["actionsetting"] and data["actionsetting"]["action"] and (data["actionsetting"]["action"] == buttonDesc) then
			if (not isSecondary and data["secondary"]) or (isSecondary and not data["secondary"]) then
				goto continue
			end

			data["keysequence"] = hotkey
			foundEntry = true
			break
		end

		:: continue ::
	end

	if not foundEntry then
		currentOption[#currentOption + 1] = {
			["actionsetting"] = {
				["action"] = buttonDesc
			},
			["keysequence"] = hotkey,
			["secondary"] = isSecondary
		}
	end
end

function Options.updateGeneralHotkey(chatType, buttonDesc, hotkey, isSecondary)
	if isSecondary == nil then
		isSecondary = false
	end

	local foundEntry = false
	Options.validateHotkeySet()
	if not Options.array or not Options.array["hotkeyOptions"] or not Options.array["hotkeyOptions"]["hotkeySets"] then
		return
	end
	for i, data in pairs(Options.currentHotkeySet[chatType]) do
		if data["actionsetting"] and data["actionsetting"]["action"] and (data["actionsetting"]["action"] == buttonDesc) then
			if (not isSecondary and data["secondary"]) or (isSecondary and not data["secondary"]) then
				goto continue
			end

			data["keysequence"] = hotkey
			foundEntry = true
			break
		end

		:: continue ::
	end

	if not foundEntry then
		Options.currentHotkeySet[chatType][#Options.currentHotkeySet[chatType] + 1] = {
			["actionsetting"] = {
				["action"] = buttonDesc
			},
			["keysequence"] = hotkey,
			["secondary"] = isSecondary
		}
	end
end

function Options.createOrUpdateAction(actionBar, slot, useMode, itemId, itemTier, smartMode, upgradeLevel)
	local foundEntry = false
	for _, data in pairs(Options.actionBarMappings) do
		if data["actionBar"] == actionBar and data["actionButton"] == slot then
			data["actionsetting"] = {}
			data["actionsetting"]["upgradeTier"] = itemTier
			data["actionsetting"]["upgradeLevel"] = upgradeLevel
			data["actionsetting"]["useEquipSmartMode"] = smartMode
			data["actionsetting"]["useObject"] = itemId
			data["actionsetting"]["useType"] = useMode
			foundEntry = true
			break
		end
	end

	if foundEntry then
		return
	end

	Options.actionBarMappings[#Options.actionBarMappings + 1] = {
		["actionBar"] = actionBar,
		["actionButton"] = slot,
		["actionsetting"] = {
			["upgradeTier"] = itemTier,
			["upgradeLevel"] = upgradeLevel,
			["useEquipSmartMode"] = smartMode,
			["useObject"] = itemId,
			["useType"] = useMode
		}
	}
end

function Options.createOrUpdatePreset(actionBar, slot, equipmentPreset, icon)
	if not equipmentPreset then
		equipmentPreset = {}
	end

	local foundEntry = false
	for _, data in pairs(Options.actionBarMappings) do
		if data["actionBar"] == actionBar and data["actionButton"] == slot then
			data["actionsetting"] = {}
			data["actionsetting"]["equipmentPreset"] = equipmentPreset
			data["actionsetting"]["equipmentPresetIcon"] = icon
			foundEntry = true
			break
		end
	end

	if foundEntry then
		return
	end

	Options.actionBarMappings[#Options.actionBarMappings + 1] = {
		["actionBar"] = actionBar,
		["actionButton"] = slot,
		["actionsetting"] = {
			["equipmentPreset"] = equipmentPreset,
			["equipmentPresetIcon"] = icon
		}
	}
end

function Options.getAutoSwtichPreset()
	return Options.array["hotkeyOptions"]["autoSwitchHotkeyPreset"]
end

function Options.changeHotkeyProfile(newProfile)
	Options.validateHotkeySet()
    if not Options.array or not Options.array["hotkeyOptions"] or not Options.array["hotkeyOptions"]["hotkeySets"] then
        return
    end

    Options.array["hotkeyOptions"]["currentHotkeySetName"] = newProfile
    Options.currentHotkeySetName = newProfile
    Options.currentHotkeySet = Options.array["hotkeyOptions"]["hotkeySets"][Options.currentHotkeySetName]

    if not Options.currentHotkeySet then
        return
    end

    Options.actionBarOptions = Options.currentHotkeySet["actionBarOptions"]
    if not Options.actionBarOptions then
        return
    end

    Options.actionBarMappings = Options.actionBarOptions["mappings"]
end

-- Executa `fn` como se `profile` + modo de chat fossem o contexto ATIVO, restaurando ao
-- final (mesmo em erro, via pcall). Usado pelos editores de Options (Action Bar/General/
-- Custom Hotkeys): as gravacoes/remocoes (updateActionMenuHotkey, removeHotkey, ...) leem
-- Options.currentHotkeySet + isChatOnEnabled, entao redirecionar esses aqui faz tudo cair
-- no perfil/modo EXIBIDOS (combo + radio), que podem diferir do ativo do jogo, sem mudar
-- cada funcao. Binds "ao vivo" feitos dentro de fn com contexto != ativo sao inofensivos
-- (Options fica com input lock) e closeOptions reaplica tudo do contexto ativo ao fechar.
function Options.withProfileChat(profile, isChatOn, fn)
	local sets = Options.array and Options.array["hotkeyOptions"] and Options.array["hotkeyOptions"]["hotkeySets"]
	local savedName = Options.currentHotkeySetName
	local savedSet = Options.currentHotkeySet
	local savedChat = Options.isChatOnEnabled
	local savedBarOpts = Options.actionBarOptions
	local savedMappings = Options.actionBarMappings

	if profile and sets and sets[profile] then
		Options.currentHotkeySetName = profile
		Options.currentHotkeySet = sets[profile]
		Options.actionBarOptions = sets[profile]["actionBarOptions"]
		Options.actionBarMappings = Options.actionBarOptions and Options.actionBarOptions["mappings"]
	end
	if isChatOn ~= nil then
		Options.isChatOnEnabled = isChatOn
	end

	local ok, err = pcall(fn)

	Options.currentHotkeySetName = savedName
	Options.currentHotkeySet = savedSet
	Options.isChatOnEnabled = savedChat
	Options.actionBarOptions = savedBarOpts
	Options.actionBarMappings = savedMappings

	if not ok then
		error(err)
	end
end

function Options.profileExist(name)
	for _, k in pairs(Options.profiles) do
		if k:lower() == name:lower() then
			return true
		end
	end
	return false
end

function Options.createProfile(name)
	Options.hotkeySets[name] = table.copy(Options.getDummyProfile())
	table.insert(Options.profiles, name)
end

function Options.copyProfile(name, target)
	local targetList = table.recursivecopy(Options.array["hotkeyOptions"]["hotkeySets"][target])

	Options.createProfile(name)
	Options.hotkeySets[name] = targetList
	Options.array["hotkeyOptions"]["hotkeySets"][name] = targetList

	Options.saveData()
end

function Options.renamePreset(newName, oldName)
	Options.validateHotkeySet()
	if not Options.array or not Options.array["hotkeyOptions"] or not Options.array["hotkeyOptions"]["hotkeySets"] then
		return
	end
	for key, value in pairs(Options.hotkeySets) do
		if key == oldName then
			Options.hotkeySets[oldName] = nil
			Options.hotkeySets[newName] = value
			break
		end
	end

	for i, value in pairs(Options.profiles) do
		if value == oldName then
			Options.profiles[i] = newName
			break
		end
	end

	Options.array["hotkeyOptions"]["currentHotkeySetName"] = newName
	Options.currentHotkeySetName = newName
end

function Options.removeProfile(name)
	for key, _ in pairs(Options.array["hotkeyOptions"]["hotkeySets"]) do
		if key == name then
			Options.array["hotkeyOptions"]["hotkeySets"][key] = nil
			break
		end
	end

	for i, value in pairs(Options.profiles) do
		if value == name then
			table.remove(Options.profiles, i)
			break
		end
	end
end

function Options.getActionHotkey(buttonId, profile, isChatOn)
    if not Options.hotkeySets or not Options.hotkeySets[profile] then
        return nil
    end

    local currentOption = isChatOn and Options.hotkeySets[profile]["chatOn"] or Options.hotkeySets[profile]["chatOff"]
    if not currentOption then
        return nil
    end

	for i, data in pairs(currentOption) do
		if not data["secondary"] and data["actionsetting"] and data["actionsetting"]["action"] == ("TriggerActionButton_" .. buttonId) then
			return data["keysequence"]
		end
	end
	return nil
end

function Options.getSecondaryActionHotkey(buttonId, profile, isChatOn)
	if not Options.hotkeySets or not Options.hotkeySets[profile] then
        return nil
    end

	local currentOption = isChatOn and Options.hotkeySets[profile]["chatOn"] or Options.hotkeySets[profile]["chatOff"]
    if not currentOption then
        return nil
    end

	for i, data in pairs(currentOption) do
		if (data["secondary"] and data["secondary"] == true) and data["actionsetting"] and data["actionsetting"]["action"] == ("TriggerActionButton_" .. buttonId) then
			return data["keysequence"]
		end
	end
	return nil
end

function Options.managePinnedCharacters(name, addCharacter)
  if not addCharacter then
    for i, character in pairs(Options.pinnedCharacters) do
      if name:lower() == character:lower() then
        table.remove(Options.pinnedCharacters, i)
        break
      end
    end
    Options.saveData()
    return
  end

  table.insert(Options.pinnedCharacters, name)
  Options.saveData()
end

function Options.setOption(option, value)
  Options.array[option] = value
  Options.saveData()
end

function Options.getOption(option)
  return Options.array[option]
end

function Options.getActiveWidgets()
  return Options.array["controlButtonsOptions"]["enabledButtons"]
end

function Options.getInactiveWidgets()
  return Options.array["controlButtonsOptions"]["disabledButtons"]
end

function Options.updateControlButtons(list, buttons)
  Options.array["controlButtonsOptions"][list] = buttons
end

function Options.resetControlButtons()
  Options.array["controlButtonsOptions"] = Options.getDefaultSideButtons()
  Options.saveData()
end

function Options.resetToDefault()
  Options.array["hotkeyOptions"]["hotkeySets"][Options.currentHotkeySetName] = Options.getDummyProfile()
  Options.currentHotkeySet = Options.array["hotkeyOptions"]["hotkeySets"][Options.currentHotkeySetName]
  Options.saveData()
end

function Options.getCustomHotkeys(chatType, profileName)
	local customHotkeys = {}
	if not Options.hotkeySets or not Options.hotkeySets[profileName] or not Options.hotkeySets[profileName][chatType] then
	  return customHotkeys
	end

	local currentOption = Options.hotkeySets[profileName][chatType]
	for i, data in pairs(currentOption) do
	  if data["actionsetting"] and data["actionsetting"]["action"] ~= nil then
		goto continue
	  end

	  table.insert(customHotkeys, data)
	  :: continue ::
	end
	return customHotkeys
  end

function Options.createOrUpdateCustomText(newWord, oldWord, sendAutomatic, hotkey, isChatOn)
	if not Options.currentHotkeySet then
		return
	end

	Options.validateHotkeySet()
	if not Options.array or not Options.array["hotkeyOptions"] or not Options.array["hotkeyOptions"]["hotkeySets"] then
		return
	end
	local foundEntry = false
	local currentOption = isChatOn and Options.currentHotkeySet["chatOn"] or Options.currentHotkeySet["chatOff"]
	for i, data in pairs(currentOption) do
    if #oldWord == 0 then
      break
    end

		if data["actionsetting"] and not data["actionsetting"]["action"] and data["actionsetting"]["chatText"] and string.find(data["actionsetting"]["chatText"], oldWord) then
      		data["actionsetting"]["chatText"] = newWord
      		data["actionsetting"]["sendAutomatically"] = sendAutomatic
			data["keysequence"] = hotkey
			foundEntry = true
			break
		end
	end

	if not foundEntry then
		currentOption[#currentOption + 1] = {
			["actionsetting"] = {
				["chatText"] = newWord,
        ["sendAutomatically"] = sendAutomatic
			},
			["keysequence"] = hotkey
		}
	end

  Options.saveData()
  Options.currentHotkeySet = Options.array["hotkeyOptions"]["hotkeySets"][Options.currentHotkeySetName]
end

function Options.createOrUpdateCustomAction(itemId, oldItemId, selected, itemTier, smartMode, hotkey, isChatOn)
	Options.validateHotkeySet()
	if not Options.array or not Options.array["hotkeyOptions"] or not Options.array["hotkeyOptions"]["hotkeySets"] then
		return
	end
  	local foundEntry = false
	local currentOption = isChatOn and Options.currentHotkeySet["chatOn"] or Options.currentHotkeySet["chatOff"]
	for i, data in pairs(currentOption) do
    if not data["actionsetting"] or data["actionsetting"]["action"] or not data["actionsetting"]["useObject"] then
      goto continue
    end

	if data["actionsetting"]["useObject"] == itemId and selected == data["actionsetting"]["useType"] or data["actionsetting"]["useObject"] == oldItemId then
		data["actionsetting"]["useObject"] = itemId
		data["actionsetting"]["useType"] = selected
		data["actionsetting"]["upgradeTier"] = itemTier
		data["actionsetting"]["useEquipSmartMode"] = smartMode
		data["keysequence"] = hotkey
		foundEntry = true
		break
	end

    :: continue ::
	end

	if not foundEntry then
		currentOption[#currentOption + 1] = {
			["actionsetting"] = {
        ["upgradeTier"] = itemTier,
        ["useEquipSmartMode"] = smartMode,
        ["useObject"] = itemId,
        ["useType"] = selected
			},
			["keysequence"] = hotkey
		}
	end

  Options.saveData()
  Options.currentHotkeySet = Options.array["hotkeyOptions"]["hotkeySets"][Options.currentHotkeySetName]
end

function Options.updateCustomHotkey(widget, hotkey, isChatOn, isSecondary)
	Options.validateHotkeySet()
	if not Options.array or not Options.array["hotkeyOptions"] or not Options.array["hotkeyOptions"]["hotkeySets"] then
		return
	end
	local currentOption = isChatOn and Options.currentHotkeySet["chatOn"] or Options.currentHotkeySet["chatOff"]
	for i, data in pairs(currentOption) do
	  if not data["actionsetting"] or data["actionsetting"]["action"] then
		goto continue
	  end

	  -- Se for secondaryHotkey, ent�o compara com data["secondarySequence"]
	  -- Se n�o for secondaryHotkey, ent�o compara com data["keysequence"]
	  local keySequence = isSecondary and data["secondarySequence"] or (not isSecondary and data["keysequence"])
	  local widgetText = isSecondary and widget.secondary:getText() or widget.primary:getText()

	  if widget.isItem then
		if data["actionsetting"]["useObject"] == widget.item:getItemId() and data["actionsetting"]["useType"] == widget.actionType then
		  if isSecondary then
			data["secondarySequence"] = hotkey
		  else
			data["keysequence"] = hotkey
		  end
		  break
		end
	  elseif widget.isText or widget.isSpell then
		if hotkey == '' and keySequence ~= '' and widget.words == data["actionsetting"]["chatText"] then
		  if isSecondary then
			data["secondarySequence"] = hotkey
		  else
			data["keysequence"] = hotkey
		  end
		  break
		elseif keySequence and keySequence == widgetText and data["actionsetting"]["chatText"] == widget.words and not data["actionsetting"]["useType"] then
		  if isSecondary then
			data["secondarySequence"] = hotkey
		  else
			data["keysequence"] = hotkey
		  end
		  break
		elseif not keySequence and data["actionsetting"]["chatText"] == widget.words and not data["actionsetting"]["useType"] then
		  if isSecondary then
			data["secondarySequence"] = hotkey
		  else
			data["keysequence"] = hotkey
		  end
		  break
		end
	  end

	  ::continue::
	end

	Options.saveData()
	Options.currentHotkeySet = Options.array["hotkeyOptions"]["hotkeySets"][Options.currentHotkeySetName]
  end

function Options.removeCustomHotkey(widget, isChatOn)
	Options.validateHotkeySet()
	if not Options.array or not Options.array["hotkeyOptions"] or not Options.array["hotkeyOptions"]["hotkeySets"] then
		return
	end
  	local currentOption = isChatOn and Options.currentHotkeySet["chatOn"] or Options.currentHotkeySet["chatOff"]
	for i, data in pairs(currentOption) do
    if not data["actionsetting"] or data["actionsetting"]["action"] then
      goto continue
    end

    if widget.isItem then
      if data["actionsetting"]["useObject"] == widget.item:getItemId() and data["actionsetting"]["useType"] == widget.actionType then
        table.remove(currentOption, i)
        break
      end
    elseif widget.isText or widget.isSpell then
      if data["actionsetting"]["chatText"] == widget.words then
        table.remove(currentOption, i)
        break
      end
    end

    :: continue ::
  end

  Options.saveData()
  Options.currentHotkeySet = Options.array["hotkeyOptions"]["hotkeySets"][Options.currentHotkeySetName]
end

function Options.deleteCustomHotkeys()
	Options.validateHotkeySet()
	if not Options.array or not Options.array["hotkeyOptions"] or not Options.array["hotkeyOptions"]["hotkeySets"] then
		return
	end
	for i, data in pairs(Options.currentHotkeySet["chatOn"]) do
    if data["actionsetting"] and data["actionsetting"]["action"] ~= nil then
      goto continue
    end

    table.remove(Options.currentHotkeySet["chatOn"], i)
    :: continue ::
  end

  for i, data in pairs(Options.currentHotkeySet["chatOff"]) do
    if data["actionsetting"] and data["actionsetting"]["action"] ~= nil then
      goto continue
    end

    table.remove(Options.currentHotkeySet["chatOff"], i)
    :: continue ::
  end

  Options.saveData()
  Options.currentHotkeySet = Options.array["hotkeyOptions"]["hotkeySets"][Options.currentHotkeySetName]
end

function Options.getSavedChannels()
    local uniqueChannels = {}
    local seen = {}

    for _, channelId in ipairs(Options.chatOptions["openChannels"]) do
        if not seen[channelId] then
            table.insert(uniqueChannels, channelId)
            seen[channelId] = true
        end
    end

    Options.chatOptions["openChannels"] = uniqueChannels
    return uniqueChannels
end

function Options.addChannel(channelId)
	if channelId == 0 or channelId == 100 then
		return
	end

	Options.chatOptions.openChannels[#Options.chatOptions.openChannels + 1] = channelId
end

function Options.getChannelIndex(channelId)
	for i, id in pairs(Options.chatOptions.openChannels) do
		if id == channelId then
			return i
		end
	end
	return nil
end

function Options.swapChannel(oldIndex, newIndex)
  local channels = Options.chatOptions.openChannels
  channels[oldIndex], channels[newIndex] = channels[newIndex], channels[oldIndex]
end

function Options.setReadOnlyChannel(name)
  Options.chatOptions.readOnlyChannel = name
end

function Options.getReadOnlyChannel()
  return Options.chatOptions.readOnlyChannel
end

function Options.removeChannel(channelId)
	for i, id in pairs(Options.chatOptions.openChannels) do
		if id == channelId then
			table.remove(Options.chatOptions.openChannels, i)
			break
		end
	end
end

function Options.resetChannels()
	Options.chatOptions.openChannels = {}
end

function Options.validateOpenChannels()
	-- Remove nil values from the array
	local tmpArray = {}
	for i, channelId in pairs(Options.chatOptions.openChannels) do
		if channelId then
			tmpArray[#tmpArray + 1] = channelId
		end
	end
	Options.chatOptions.openChannels = tmpArray
end

function Options.isLootChannelOpen()
	return Options.chatOptions["lootChannelOpen"]
end

function Options.validateHotkeySet()
	if Options.currentHotkeySet then
		return true
	end

	Options.currentHotkeySet = Options.array["hotkeyOptions"]["hotkeySets"][Options.currentHotkeySetName]
end
