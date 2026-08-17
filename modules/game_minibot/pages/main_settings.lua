main_settingsModule = {}

local mainSettingsWindow = nil

function main_settingsModule.resolveVocationName(player)
    if player == nil then
        return ''
    end

    local vocation = nil
    if type(player.getVocation) == 'function' then
        local ok, value = pcall(player.getVocation, player)
        if ok then
            vocation = value
        end
    end

    if vocation ~= nil and g_game ~= nil and type(g_game.getVocationName) == 'function' then
        local ok, name = pcall(g_game.getVocationName, vocation)
        if ok and type(name) == 'string' and name ~= '' then
            return name
        end
    end
    if vocation ~= nil and type(VocationNames) == 'table' then
        local name = VocationNames[vocation]
        if type(name) == 'string' and name ~= '' then
            return name
        end
    end
    return vocation ~= nil and tostring(vocation) or ''
end

local function isBotCheckActive()
    if MiniBotCompat == nil or type(MiniBotCompat.getBotCheckAlarmState) ~= 'function' then
        return false
    end
    local ok, alarmState = pcall(MiniBotCompat.getBotCheckAlarmState)
    return ok and type(alarmState) == 'table' and alarmState.active == true
end

function main_settingsModule.init(widget)
    mainSettingsWindow = widget

    mainSettingsWindow.settings.version:setText('Version: ' .. modules.game_minibot.getVersionStr())

    local player = g_game.getLocalPlayer()
    if player == nil then
        return
    end

    local outfit = player:getOutfit()
    outfit.category = ThingCategoryCreature
    outfit.mount = 0
    mainSettingsWindow.main.creatureBackground.creature:setOutfit(outfit)
    mainSettingsWindow.main.name:setText(player:getName())
    mainSettingsWindow.main.vocation:setText(main_settingsModule.resolveVocationName(player))
    mainSettingsWindow.main.level:setText('Level: ' .. comma_value(player:getLevel()))

    local gameWindow = modules.game_minibot.getSettingsValue(true, 'autoAttack_gamewindow', false)
    main_settingsModule.onGameWindowChange(mainSettingsWindow.settings.keysPanel.autoAttack.button)
    mainSettingsWindow.settings.keysPanel.autoAttack.edit.onLeftClick = function()
        onSelectMinibotHotkeyOptions('controls', 'general', 'Auto-attack Toggle')
    end
    onMiniBotGameWindowChangeKeyCombo('autoAttack', modules.client_options.getGeneralHotkeyCombo('assistantAutoAttackToggle'))

    gameWindow = modules.game_minibot.getSettingsValue(true, 'shooter_gamewindow', false)
    mainSettingsWindow.settings.keysPanel.shooter.button.ignoreCallback = true
    mainSettingsWindow.settings.keysPanel.shooter.button:setChecked(gameWindow)
    main_settingsModule.onGameWindowChange(mainSettingsWindow.settings.keysPanel.shooter.button)
    mainSettingsWindow.settings.keysPanel.shooter.button.ignoreCallback = nil
    mainSettingsWindow.settings.keysPanel.shooter.edit.onLeftClick = function()
        onSelectMinibotHotkeyOptions('controls', 'general', 'Shooter Toggle')
    end
    onMiniBotGameWindowChangeKeyCombo('shooter', modules.client_options.getGeneralHotkeyCombo('assistantShooterToggle'))

    gameWindow = modules.game_minibot.getSettingsValue(true, 'combatTimer_gamewindow', false)
    mainSettingsWindow.settings.keysPanel.combatTimers.button.ignoreCallback = true
    mainSettingsWindow.settings.keysPanel.combatTimers.button:setChecked(gameWindow)
    main_settingsModule.onGameWindowChange(mainSettingsWindow.settings.keysPanel.combatTimers.button)
    mainSettingsWindow.settings.keysPanel.combatTimers.button.ignoreCallback = nil
    mainSettingsWindow.settings.keysPanel.combatTimers.edit.onLeftClick = function()
        onSelectMinibotHotkeyOptions('controls', 'general', 'Combat Timers Toggle')
    end
    onMiniBotGameWindowChangeKeyCombo('combatTimers', modules.client_options.getGeneralHotkeyCombo('assistantCombatTimersToggle'))

    gameWindow = modules.game_minibot.getSettingsValue(true, 'panel_gamewindow', false)
    mainSettingsWindow.main.gameWindowPanelButton.ignoreCallback = true
    mainSettingsWindow.main.gameWindowPanelButton:setChecked(gameWindow)
    main_settingsModule.onGameWindowChange(mainSettingsWindow.main.gameWindowPanelButton)
    mainSettingsWindow.main.gameWindowPanelButton.ignoreCallback = nil

    gameWindow = modules.game_minibot.getSettingsValue(true, 'healingHealth_gamewindow', false)
    mainSettingsWindow.settings.keysPanel.healingHealth.button.ignoreCallback = true
    mainSettingsWindow.settings.keysPanel.healingHealth.button:setChecked(gameWindow)
    main_settingsModule.onGameWindowChange(mainSettingsWindow.settings.keysPanel.healingHealth.button)
    mainSettingsWindow.settings.keysPanel.healingHealth.button.ignoreCallback = nil
    mainSettingsWindow.settings.keysPanel.healingHealth.edit.onLeftClick = function()
        onSelectMinibotHotkeyOptions('controls', 'general', 'Health Healing Toggle')
    end
    onMiniBotGameWindowChangeKeyCombo('healingHealth', modules.client_options.getGeneralHotkeyCombo('assistantHealthHealingToggle'))

    gameWindow = modules.game_minibot.getSettingsValue(true, 'healingMana_gamewindow', false)
    mainSettingsWindow.settings.keysPanel.healingMana.button.ignoreCallback = true
    mainSettingsWindow.settings.keysPanel.healingMana.button:setChecked(gameWindow)
    main_settingsModule.onGameWindowChange(mainSettingsWindow.settings.keysPanel.healingMana.button)
    mainSettingsWindow.settings.keysPanel.healingMana.button.ignoreCallback = nil
    mainSettingsWindow.settings.keysPanel.healingMana.edit.onLeftClick = function()
        onSelectMinibotHotkeyOptions('controls', 'general', 'Mana Healing Toggle')
    end
    onMiniBotGameWindowChangeKeyCombo('healingMana', modules.client_options.getGeneralHotkeyCombo('assistantManaHealingToggle'))

    gameWindow = modules.game_minibot.getSettingsValue(true, 'healingGroup_gamewindow', false)
    mainSettingsWindow.settings.keysPanel.healingGroup.button.ignoreCallback = true
    mainSettingsWindow.settings.keysPanel.healingGroup.button:setChecked(gameWindow)
    main_settingsModule.onGameWindowChange(mainSettingsWindow.settings.keysPanel.healingGroup.button)
    mainSettingsWindow.settings.keysPanel.healingGroup.button.ignoreCallback = nil
    mainSettingsWindow.settings.keysPanel.healingGroup.edit.onLeftClick = function()
        onSelectMinibotHotkeyOptions('controls', 'general', 'Group Healing Toggle')
    end
    onMiniBotGameWindowChangeKeyCombo('healingGroup', modules.client_options.getGeneralHotkeyCombo('assistantGroupHealingToggle'))

    gameWindow = modules.game_minibot.getSettingsValue(true, 'equipmentAmulet_gamewindow', false)
    mainSettingsWindow.settings.keysPanel.equipmentAmulet.button.ignoreCallback = true
    mainSettingsWindow.settings.keysPanel.equipmentAmulet.button:setChecked(gameWindow)
    main_settingsModule.onGameWindowChange(mainSettingsWindow.settings.keysPanel.equipmentAmulet.button)
    mainSettingsWindow.settings.keysPanel.equipmentAmulet.button.ignoreCallback = nil
    mainSettingsWindow.settings.keysPanel.equipmentAmulet.edit.onLeftClick = function()
        onSelectMinibotHotkeyOptions('controls', 'general', 'Equipment Amulet Toggle')
    end
    onMiniBotGameWindowChangeKeyCombo('equipmentAmulet', modules.client_options.getGeneralHotkeyCombo('assistantEquipmentAmuletToggle'))

    gameWindow = modules.game_minibot.getSettingsValue(true, 'equipmentRing_gamewindow', false)
    mainSettingsWindow.settings.keysPanel.equipmentRing.button.ignoreCallback = true
    mainSettingsWindow.settings.keysPanel.equipmentRing.button:setChecked(gameWindow)
    main_settingsModule.onGameWindowChange(mainSettingsWindow.settings.keysPanel.equipmentRing.button)
    mainSettingsWindow.settings.keysPanel.equipmentRing.button.ignoreCallback = nil
    mainSettingsWindow.settings.keysPanel.equipmentRing.edit.onLeftClick = function()
        onSelectMinibotHotkeyOptions('controls', 'general', 'Equipment Ring Toggle')
    end
    onMiniBotGameWindowChangeKeyCombo('equipmentRing', modules.client_options.getGeneralHotkeyCombo('assistantEquipmentRingToggle'))

    gameWindow = modules.game_minibot.getSettingsValue(true, 'tankMode_gamewindow', false)
    mainSettingsWindow.settings.keysPanel.tankMode.button.ignoreCallback = true
    mainSettingsWindow.settings.keysPanel.tankMode.button:setChecked(gameWindow)
    main_settingsModule.onGameWindowChange(mainSettingsWindow.settings.keysPanel.tankMode.button)
    mainSettingsWindow.settings.keysPanel.tankMode.button.ignoreCallback = nil
    mainSettingsWindow.settings.keysPanel.tankMode.edit.onLeftClick = function()
        onSelectMinibotHotkeyOptions('controls', 'general', 'Tank Mode Toggle')
    end
    onMiniBotGameWindowChangeKeyCombo('tankMode', modules.client_options.getGeneralHotkeyCombo('assistantTankModeToggle'))

    gameWindow = modules.game_minibot.getSettingsValue(true, 'huntingRecorder_gamewindow', false)
    mainSettingsWindow.settings.keysPanel.huntingRecorder.button.ignoreCallback = true
    mainSettingsWindow.settings.keysPanel.huntingRecorder.button:setChecked(gameWindow)
    main_settingsModule.onGameWindowChange(mainSettingsWindow.settings.keysPanel.huntingRecorder.button)
    mainSettingsWindow.settings.keysPanel.huntingRecorder.button.ignoreCallback = nil
    mainSettingsWindow.settings.keysPanel.huntingRecorder.edit.onLeftClick = function()
        onSelectMinibotHotkeyOptions('controls', 'general', 'Hunting Recorder Toggle')
    end
    onMiniBotGameWindowChangeKeyCombo('huntingRecorder', modules.client_options.getGeneralHotkeyCombo('assistantHuntingRecorderToggle'))

    gameWindow = modules.game_minibot.getSettingsValue(true, 'huntingRecorderTimer_gamewindow', false)
    mainSettingsWindow.settings.keysPanel.huntingRecorderTimer.button.ignoreCallback = true
    mainSettingsWindow.settings.keysPanel.huntingRecorderTimer.button:setChecked(gameWindow)
    main_settingsModule.onGameWindowChange(mainSettingsWindow.settings.keysPanel.huntingRecorderTimer.button)
    mainSettingsWindow.settings.keysPanel.huntingRecorderTimer.button.ignoreCallback = nil

    gameWindow = modules.game_minibot.getSettingsValue(true, 'huntingExplorer_gamewindow', false)
    mainSettingsWindow.settings.keysPanel.huntingExplorer.button.ignoreCallback = true
    mainSettingsWindow.settings.keysPanel.huntingExplorer.button:setChecked(gameWindow)
    main_settingsModule.onGameWindowChange(mainSettingsWindow.settings.keysPanel.huntingExplorer.button)
    mainSettingsWindow.settings.keysPanel.huntingExplorer.button.ignoreCallback = nil
    mainSettingsWindow.settings.keysPanel.huntingExplorer.edit.onLeftClick = function()
        onSelectMinibotHotkeyOptions('controls', 'general', 'Hunting Auto-Explorer Toggle')
    end
    onMiniBotGameWindowChangeKeyCombo('huntingExplorer', modules.client_options.getGeneralHotkeyCombo('assistantHuntingExplorerToggle'))

    local language = modules.game_minibot.getSettingsValue(false, 'language', 'ptbr')
    mainSettingsWindow.main.ptbrIcon.ignoreCallback = true
    mainSettingsWindow.main.enusIcon.ignoreCallback = true
    if language == 'ptbr' then
        mainSettingsWindow.main.ptbrIcon:setChecked(false)
        mainSettingsWindow.main.ptbrIcon:setChecked(true)
        mainSettingsWindow.main.enusIcon:setChecked(true)
        mainSettingsWindow.main.enusIcon:setChecked(false)
        mainSettingsWindow.main.ptbrIcon:setBorderWidth(1)
    elseif language == 'enus' then
        mainSettingsWindow.main.ptbrIcon:setChecked(true)
        mainSettingsWindow.main.ptbrIcon:setChecked(false)
        mainSettingsWindow.main.enusIcon:setChecked(false)
        mainSettingsWindow.main.enusIcon:setChecked(true)
        mainSettingsWindow.main.enusIcon:setBorderWidth(1)
    end
    mainSettingsWindow.main.ptbrIcon.ignoreCallback = nil
    mainSettingsWindow.main.enusIcon.ignoreCallback = nil
end

function onSelectMinibotHotkeyOptions(id, sub, input)
    if m_settings ~= nil and m_settings.openOptions ~= nil then
        m_settings:openOptions('generalHotkeys', input)
        return
    end

    if modules.client_options.show == nil or modules.client_options.getOptionsTab == nil then
        modules.game_textmessage.displayStatusMessage('Hotkey settings are unavailable.', true)
        return
    end

    modules.client_options.show()

    local tab, panel = modules.client_options.getOptionsTab(id)
    if tab ~= nil then
        tab:onClick()
        local subTab, subPanel = modules.client_options.getOptionsTab(sub)
        if subTab ~= nil then
            subTab:onClick()
            if subPanel ~= nil then
                local search = subPanel:recursiveGetChildById('searchEditbox')
                if search ~= nil then
                    search:setText(input)
                end
            end
        end
    end
end

function reloadMinibotGameWindowCombos()
    if mainSettingsWindow == nil then
        return
    end

    onMiniBotGameWindowChangeKeyCombo('autoAttack', modules.client_options.getGeneralHotkeyCombo('assistantAutoAttackToggle'))
    onMiniBotGameWindowChangeKeyCombo('shooter', modules.client_options.getGeneralHotkeyCombo('assistantShooterToggle'))
    onMiniBotGameWindowChangeKeyCombo('combatTimers', modules.client_options.getGeneralHotkeyCombo('assistantCombatTimersToggle'))
    onMiniBotGameWindowChangeKeyCombo('healingHealth', modules.client_options.getGeneralHotkeyCombo('assistantHealthHealingToggle'))
    onMiniBotGameWindowChangeKeyCombo('healingMana', modules.client_options.getGeneralHotkeyCombo('assistantManaHealingToggle'))
    onMiniBotGameWindowChangeKeyCombo('healingGroup', modules.client_options.getGeneralHotkeyCombo('assistantGroupHealingToggle'))
    onMiniBotGameWindowChangeKeyCombo('equipmentAmulet', modules.client_options.getGeneralHotkeyCombo('assistantEquipmentAmuletToggle'))
    onMiniBotGameWindowChangeKeyCombo('equipmentRing', modules.client_options.getGeneralHotkeyCombo('assistantEquipmentRingToggle'))
    onMiniBotGameWindowChangeKeyCombo('tankMode', modules.client_options.getGeneralHotkeyCombo('assistantTankModeToggle'))
    onMiniBotGameWindowChangeKeyCombo('huntingRecorder', modules.client_options.getGeneralHotkeyCombo('assistantHuntingRecorderToggle'))
    onMiniBotGameWindowChangeKeyCombo('huntingExplorer', modules.client_options.getGeneralHotkeyCombo('assistantHuntingExplorerToggle'))
end

function main_settingsModule.reloadLanguage(language)
    if language == 'ptbr' then
        mainSettingsWindow.main.title:setText('Aparencia')
        mainSettingsWindow.main.gameWindowPanelButton:setTooltip('Mostrar/Esconder o painel de atalhos do Assistente da janela de jogo.')
        mainSettingsWindow.settings.title:setText('Atalhos de janela de jogo')
        mainSettingsWindow.settings.version:setText('Versao: ' .. modules.game_minibot.getVersionStr())
        mainSettingsWindow.settings.keysPanel.autoAttack.label:setText('Auto-ataque:')
        mainSettingsWindow.settings.keysPanel.autoAttack.key:setPlaceholder('nenhum')
        mainSettingsWindow.settings.keysPanel.autoAttack.edit:setTooltip('Escolher uma Hotkey para ativar/desativar a funcao do Auto-atack.')
        mainSettingsWindow.settings.keysPanel.autoAttack.button:setTooltip('Mostrar/Esconder o atalho do Auto-attack na janela do jogo.')
        mainSettingsWindow.settings.keysPanel.shooter.label:setText('Shooter:')
        mainSettingsWindow.settings.keysPanel.shooter.key:setPlaceholder('nenhum')
        mainSettingsWindow.settings.keysPanel.shooter.edit:setTooltip('Escolher uma Hotkey para ativar/desativar a funcao do Shooter.')
        mainSettingsWindow.settings.keysPanel.shooter.button:setTooltip('Mostrar/Esconder o atalho do Shooter na janela do jogo.')
        mainSettingsWindow.settings.keysPanel.healingHealth.label:setText('Cura de HP:')
        mainSettingsWindow.settings.keysPanel.healingHealth.key:setPlaceholder('nenhum')
        mainSettingsWindow.settings.keysPanel.healingHealth.edit:setTooltip('Escolher uma Hotkey para ativar/desativar a funcao da Cura de Hit Points.')
        mainSettingsWindow.settings.keysPanel.healingHealth.button:setTooltip('Mostrar/Esconder o atalho da Cura de Hit Points na janela do jogo.')
        mainSettingsWindow.settings.keysPanel.healingGroup.label:setText('Cura de grupo:')
        mainSettingsWindow.settings.keysPanel.healingGroup.key:setPlaceholder('nenhum')
        mainSettingsWindow.settings.keysPanel.healingGroup.edit:setTooltip('Escolher uma Hotkey para ativar/desativar a funcao da Cura de grupo.')
        mainSettingsWindow.settings.keysPanel.healingGroup.button:setTooltip('Mostrar/Esconder o atalho da Cura de grupo na janela do jogo.')
        mainSettingsWindow.settings.keysPanel.healingMana.label:setText('Cura de MP:')
        mainSettingsWindow.settings.keysPanel.healingMana.key:setPlaceholder('nenhum')
        mainSettingsWindow.settings.keysPanel.healingMana.edit:setTooltip('Escolher uma Hotkey para ativar/desativar a funcao da Cura de Mana Points.')
        mainSettingsWindow.settings.keysPanel.healingMana.button:setTooltip('Mostrar/Esconder o atalho da Cura de Mana Points na janela do jogo.')
        mainSettingsWindow.settings.keysPanel.combatTimers.label:setText('Temp. de Combate:')
        mainSettingsWindow.settings.keysPanel.combatTimers.key:setPlaceholder('nenhum')
        mainSettingsWindow.settings.keysPanel.combatTimers.edit:setTooltip('Escolher uma Hotkey para ativar/desativar a funcao do Temporizador de Combate.')
        mainSettingsWindow.settings.keysPanel.combatTimers.button:setTooltip('Mostrar/Esconder o atalho do Temporizador de Combate na janela do jogo.')
        mainSettingsWindow.settings.keysPanel.equipmentAmulet.label:setText('Equip. de Amuletos:')
        mainSettingsWindow.settings.keysPanel.equipmentAmulet.key:setPlaceholder('nenhum')
        mainSettingsWindow.settings.keysPanel.equipmentAmulet.edit:setTooltip('Escolher uma Hotkey para ativar/desativar a funcao do Equipamento de Amuletos.')
        mainSettingsWindow.settings.keysPanel.equipmentAmulet.button:setTooltip('Mostrar/Esconder o atalho do Equipamento de Amuletos na janela do jogo.')
        mainSettingsWindow.settings.keysPanel.equipmentRing.label:setText('Equip. de Aneis:')
        mainSettingsWindow.settings.keysPanel.equipmentRing.key:setPlaceholder('nenhum')
        mainSettingsWindow.settings.keysPanel.equipmentRing.edit:setTooltip('Escolher uma Hotkey para ativar/desativar a funcao do Equipamento de Aneis.')
        mainSettingsWindow.settings.keysPanel.equipmentRing.button:setTooltip('Mostrar/Esconder o atalho do Equipamento de Aneis na janela do jogo.')
        mainSettingsWindow.settings.keysPanel.tankMode.label:setText('Modo Tanque:')
        mainSettingsWindow.settings.keysPanel.tankMode.key:setPlaceholder('nenhum')
        mainSettingsWindow.settings.keysPanel.tankMode.edit:setTooltip('Escolher uma Hotkey para ativar/desativar a funcao do Modo Tanque.')
        mainSettingsWindow.settings.keysPanel.tankMode.button:setTooltip('Mostrar/Esconder o atalho do Modo Tanque na janela do jogo.')
        mainSettingsWindow.settings.keysPanel.huntingRecorder.label:setText('Cave Bot:')
        mainSettingsWindow.settings.keysPanel.huntingRecorder.key:setPlaceholder('nenhum')
        mainSettingsWindow.settings.keysPanel.huntingRecorder.edit:setTooltip('Escolher uma Hotkey para ativar/desativar a funcao do Cave Bot.')
        mainSettingsWindow.settings.keysPanel.huntingRecorder.button:setTooltip('Mostrar/Esconder o atalho do Cave Bot na janela do jogo.')
        mainSettingsWindow.settings.keysPanel.huntingRecorderTimer.label:setText('Timer do Cave Bot:')
        mainSettingsWindow.settings.keysPanel.huntingRecorderTimer.button:setTooltip('Mostrar/Esconder o contador de tempo do Cave Bot na janela do jogo.')

    elseif language == 'enus' then
        mainSettingsWindow.main.title:setText('Appearance')
        mainSettingsWindow.main.gameWindowPanelButton:setTooltip('Show/Hide the assistant shortcut panel on game window.')
        mainSettingsWindow.settings.title:setText('Game Window Shortcuts')
        mainSettingsWindow.settings.version:setText('Version: ' .. modules.game_minibot.getVersionStr())
        mainSettingsWindow.settings.keysPanel.autoAttack.label:setText('Auto-attack:')
        mainSettingsWindow.settings.keysPanel.autoAttack.key:setPlaceholder('none')
        mainSettingsWindow.settings.keysPanel.autoAttack.edit:setTooltip('Set a new hotkey to switch the Auto-attack function.')
        mainSettingsWindow.settings.keysPanel.autoAttack.button:setTooltip('Show Auto-attack switch button on game window.')
        mainSettingsWindow.settings.keysPanel.shooter.label:setText('Shooter:')
        mainSettingsWindow.settings.keysPanel.shooter.key:setPlaceholder('none')
        mainSettingsWindow.settings.keysPanel.shooter.edit:setTooltip('Set a new hotkey to switch the Shooter function.')
        mainSettingsWindow.settings.keysPanel.shooter.button:setTooltip('Show Shooter switch button on game window.')
        mainSettingsWindow.settings.keysPanel.healingHealth.label:setText('Health healing:')
        mainSettingsWindow.settings.keysPanel.healingHealth.key:setPlaceholder('none')
        mainSettingsWindow.settings.keysPanel.healingHealth.edit:setTooltip('Set a new hotkey to switch the Health Healing function.')
        mainSettingsWindow.settings.keysPanel.healingHealth.button:setTooltip('Show Healing Health switch button on game window.')
        mainSettingsWindow.settings.keysPanel.healingGroup.label:setText('Group healing:')
        mainSettingsWindow.settings.keysPanel.healingGroup.key:setPlaceholder('none')
        mainSettingsWindow.settings.keysPanel.healingGroup.edit:setTooltip('Set a new hotkey to switch the Group Healing function.')
        mainSettingsWindow.settings.keysPanel.healingGroup.button:setTooltip('Show Healing Group switch button on game window.')
        mainSettingsWindow.settings.keysPanel.healingMana.label:setText('Mana healing:')
        mainSettingsWindow.settings.keysPanel.healingMana.key:setPlaceholder('none')
        mainSettingsWindow.settings.keysPanel.healingMana.edit:setTooltip('Set a new hotkey to switch the Mana Healing function.')
        mainSettingsWindow.settings.keysPanel.healingMana.button:setTooltip('Show Healing Mana switch button on game window.')
        mainSettingsWindow.settings.keysPanel.combatTimers.label:setText('Combat timers:')
        mainSettingsWindow.settings.keysPanel.combatTimers.key:setPlaceholder('none')
        mainSettingsWindow.settings.keysPanel.combatTimers.edit:setTooltip('Set a new hotkey to switch the Mana Healing function.')
        mainSettingsWindow.settings.keysPanel.combatTimers.button:setTooltip('Show Combat Timer switch button on game window.')
        mainSettingsWindow.settings.keysPanel.equipmentAmulet.label:setText('Equipment Amulet:')
        mainSettingsWindow.settings.keysPanel.equipmentAmulet.key:setPlaceholder('none')
        mainSettingsWindow.settings.keysPanel.equipmentAmulet.edit:setTooltip('Set a new hotkey to switch the Equipment Amulet function.')
        mainSettingsWindow.settings.keysPanel.equipmentAmulet.button:setTooltip('Show Equipment Amulet switch button on game window.')
        mainSettingsWindow.settings.keysPanel.equipmentRing.label:setText('Equipment Ring:')
        mainSettingsWindow.settings.keysPanel.equipmentRing.key:setPlaceholder('none')
        mainSettingsWindow.settings.keysPanel.equipmentRing.edit:setTooltip('Set a new hotkey to switch the Equipment Ring function.')
        mainSettingsWindow.settings.keysPanel.equipmentRing.button:setTooltip('Show Equipment Ring switch button on game window.')
        mainSettingsWindow.settings.keysPanel.tankMode.label:setText('Tank Mode:')
        mainSettingsWindow.settings.keysPanel.tankMode.key:setPlaceholder('none')
        mainSettingsWindow.settings.keysPanel.tankMode.edit:setTooltip('Set a new hotkey to switch the Tank Mode function.')
        mainSettingsWindow.settings.keysPanel.tankMode.button:setTooltip('Show Tank Mode switch button on game window.')
        mainSettingsWindow.settings.keysPanel.huntingRecorder.label:setText('Cave bot:')
        mainSettingsWindow.settings.keysPanel.huntingRecorder.key:setPlaceholder('none')
        mainSettingsWindow.settings.keysPanel.huntingRecorder.edit:setTooltip('Set a new hotkey to switch the Cave Bot funtion.')
        mainSettingsWindow.settings.keysPanel.huntingRecorder.button:setTooltip('Show Cave Bot switch button on game window.')
        mainSettingsWindow.settings.keysPanel.huntingRecorderTimer.label:setText('Cave Bot timer:')
        mainSettingsWindow.settings.keysPanel.huntingRecorderTimer.button:setTooltip('Show/Hide the Cave Bot timer on the game window.')
    end
end

function main_settingsModule.onLanguageChange(widget)
    if widget.ignoreCallback then
        return
    end

    if not(widget:isChecked()) then
        widget.ignoreCallback = true
        widget:setChecked(true)
        widget.ignoreCallback = nil
        return
    end

    mainSettingsWindow.main.ptbrIcon.ignoreCallback = true
    mainSettingsWindow.main.enusIcon.ignoreCallback = true

    if widget:getId() == 'ptbrIcon' then
        mainSettingsWindow.main.ptbrLabel:setColor('white')
        mainSettingsWindow.main.ptbrIcon:setBorderWidth(1)
        mainSettingsWindow.main.enusLabel:setColor('#C0C0C0')
        mainSettingsWindow.main.enusIcon:setBorderWidth(0)
        mainSettingsWindow.main.enusIcon:setChecked(false)
        modules.game_minibot.setSettingsValue(false, 'language', 'ptbr')
    elseif widget:getId() == 'enusIcon' then
        mainSettingsWindow.main.enusLabel:setColor('white')
        mainSettingsWindow.main.enusIcon:setBorderWidth(1)
        mainSettingsWindow.main.ptbrLabel:setColor('#C0C0C0')
        mainSettingsWindow.main.ptbrIcon:setBorderWidth(0)
        mainSettingsWindow.main.ptbrIcon:setChecked(false)
        modules.game_minibot.setSettingsValue(false, 'language', 'enus')
    end

    mainSettingsWindow.main.ptbrIcon.ignoreCallback = nil
    mainSettingsWindow.main.enusIcon.ignoreCallback = nil

    modules.game_minibot.reloadLanguage()
end

function main_settingsModule.terminate()
    mainSettingsWindow = nil

end

function onMiniBotGameWindowChangeKeyCombo(keyPanelid, combo)
    if mainSettingsWindow == nil then
        return
    end

    local panel = mainSettingsWindow.settings.keysPanel[keyPanelid]
    if panel == nil then
        return
    end

    if combo == nil or combo == '' then
        panel.key:clearText()
    else
        panel.key:setText(combo)
    end
end

function main_settingsModule.reloadInternalModule()
    local player = g_game.getLocalPlayer()
    if player == nil then
        return
    end

    local settings = modules.game_minibot.getPressetSettings()
    local sSettings = settings['shortcuts'] or {}

    local shooterEnabled = sSettings['shooter_enabled']
    local healingHealthEnabled = sSettings['healingHealth_enabled']
    local healingGroupEnabled = sSettings['healingGroup_enabled']
    local healingManaEnabled = sSettings['healingMana_enabled']
    local combatTimersEnabled = sSettings['combatTimers_enabled']
    local supportHasteEnabled = sSettings['supportHaste_enabled']
    local autoAttackEnabled = sSettings['autoAttack_enabled']
    local equipmentAmuletEnabled = sSettings['equipmentAmulet_enabled']
    local tankModeEnabled = sSettings['tankMode_enabled'] == true
    local equipmentRingEnabled = sSettings['equipmentRing_enabled']
    local huntingRecorderEnabled = sSettings['huntingRecorder_enabled']
    local huntingRecorderTimerEnabled = modules.game_minibot.getSettingsValue(true, 'huntingRecorderTimer_gamewindow', false)
    local huntingExplorerEnabled = sSettings['huntingExplorer_enabled'] == true
    if isBotCheckActive() then
        huntingRecorderEnabled = false
        huntingExplorerEnabled = false
    end

    g_minibot.setModuleToggle(0, shooterEnabled) -- Shooter (Attack)
    g_minibot.setModuleToggle(1, healingHealthEnabled) -- Healing Health
    g_minibot.setModuleToggle(2, healingManaEnabled) -- Healing Mana
    g_minibot.setModuleToggle(3, combatTimersEnabled) -- Combat Timers
    g_minibot.setModuleToggle(4, supportHasteEnabled) -- Support Haste
    g_minibot.setModuleToggle(6, healingGroupEnabled) -- Healing Group
    g_minibot.setModuleToggle(10, equipmentAmuletEnabled) -- Equipment Amulet
    g_minibot.setModuleToggle(11, equipmentRingEnabled) -- Equipment Ring
    g_minibot.setModuleToggle(16, tankModeEnabled) -- Tank Mode
    g_minibot.setModuleToggle(5, huntingRecorderEnabled) -- Hunting Recorder
    modules.game_minibot.toggleDisableCavebot()
    g_minibot.setModuleToggle(21, huntingExplorerEnabled) -- Hunting Explorer

    local panel = modules.game_interface.getMiniBotPanel()
    local timerPanel = modules.game_interface.getMiniBotTimerPanel()
    if panel ~= nil and timerPanel ~= nil then
        panel:destroyChildren()

        local gameWindow = modules.game_minibot.getSettingsValue(true, 'panel_gamewindow', false)
        if not(gameWindow) then
            panel:hide()
            modules.game_interface.setMiniBotTimerPanelStatus(false)
        else
            local widget = g_ui.createWidget('MiniBotShortcutButton', panel)
            widget:constructEnviorementVariables()
            widget:setId('combat_gamewindow')
            widget:setWidth(19)
            widget:setHeight(21)
            widget:setIconClip(torect('0 0 11 10'))
            widget:setIconSize('11 10')
            widget:setIconOffset('4 5')
            widget:setTooltip('This shortcut controls the auto attack. If activated, the system will auto select a creature in range as target, following your auto-attack settings.')
            widget.ignoreCallback = true
            widget:setChecked(autoAttackEnabled)
            widget.ignoreCallback = nil
            widget.onMousePress = onMiniBotGameWindowMousePressFromPanel

            gameWindow = modules.game_minibot.getSettingsValue(true, 'shooter_gamewindow', false)
            if gameWindow then
                widget = g_ui.createWidget('MiniBotShortcutButton', panel)
                widget:constructEnviorementVariables()
                widget:setId('shooter_gamewindow')
                widget:setWidth(19)
                widget:setHeight(21)
                widget:setIconClip(torect('130 0 11 12'))
                widget:setIconSize('11 12')
                widget:setIconOffset('4 5')
                widget:setTooltip('Auto shooter can help you with finding the best positions on combat. If activated, the system will start combat following your shooter priority and settings.')
                widget.ignoreCallback = true
                widget:setChecked(shooterEnabled)
                widget.ignoreCallback = nil
                widget.onMousePress = onMiniBotGameWindowMousePressFromPanel
            end

            gameWindow = modules.game_minibot.getSettingsValue(true, 'combatTimer_gamewindow', false)
            if gameWindow then
                widget = g_ui.createWidget('MiniBotShortcutButton', panel)
                widget:constructEnviorementVariables()
                widget:setId('combatTimer_gamewindow')
                widget:setWidth(19)
                widget:setHeight(21)
                widget:setIconClip(torect('169 0 8 13'))
                widget:setIconSize('8 13')
                widget:setIconOffset('4 5')
                widget:setTooltip('You can schedule spells to help you on combat. If activated, the system will use your combat timer list to boost your character strenght during a fight.')
                widget.ignoreCallback = true
                widget:setChecked(combatTimersEnabled)
                widget.ignoreCallback = nil
                widget.onMousePress = onMiniBotGameWindowMousePressFromPanel
            end

            gameWindow = modules.game_minibot.getSettingsValue(true, 'healingHealth_gamewindow', false)
            if gameWindow then
                widget = g_ui.createWidget('MiniBotShortcutButton', panel)
                widget:constructEnviorementVariables()
                widget:setId('healingHealth_gamewindow')
                widget:setWidth(19)
                widget:setHeight(21)
                widget:setIconClip(torect('78 0 9 12'))
                widget:setIconSize('9 12')
                widget:setIconOffset('4 5')
                widget:setTooltip('Health healing can help you with sustain during a fight. If activated, the system will use your healing list to maintain your character alive during a fight.')
                widget.ignoreCallback = true
                widget:setChecked(healingHealthEnabled)
                widget.ignoreCallback = nil
                widget.onMousePress = onMiniBotGameWindowMousePressFromPanel
            end

            gameWindow = modules.game_minibot.getSettingsValue(true, 'healingMana_gamewindow', false)
            if gameWindow then
                widget = g_ui.createWidget('MiniBotShortcutButton', panel)
                widget:constructEnviorementVariables()
                widget:setId('healingMana_gamewindow')
                widget:setWidth(19)
                widget:setHeight(21)
                widget:setIconClip(torect('91 0 9 12'))
                widget:setIconSize('9 12')
                widget:setIconOffset('4 5')
                widget:setTooltip('Mana healing will help you on your spells rotations. If activated, the system will use your healing list to maintain your mana at the desired level.')
                widget.ignoreCallback = true
                widget:setChecked(healingManaEnabled)
                widget.ignoreCallback = nil
                widget.onMousePress = onMiniBotGameWindowMousePressFromPanel
            end

            gameWindow = modules.game_minibot.getSettingsValue(true, 'healingGroup_gamewindow', false)
            if gameWindow then
                widget = g_ui.createWidget('MiniBotShortcutButton', panel)
                widget:constructEnviorementVariables()
                widget:setId('healingGroup_gamewindow')
                widget:setWidth(19)
                widget:setHeight(21)
                widget:setIconClip(torect('25 0 13 12'))
                widget:setIconSize('13 12')
                widget:setIconOffset('4 5')
                widget:setTooltip('Group Health healing will help your pre-selected list to survive the skirmish. If activated, the system will use your group healing list to maintain your team alive.')
                widget.ignoreCallback = true
                widget:setChecked(healingGroupEnabled)
                widget.ignoreCallback = nil
                widget.onMousePress = onMiniBotGameWindowMousePressFromPanel
            end

            gameWindow = modules.game_minibot.getSettingsValue(true, 'supportHaste_gamewindow', false)
            if gameWindow then
                widget = g_ui.createWidget('MiniBotShortcutButton', panel)
                widget:constructEnviorementVariables()
                widget:setId('supportHaste_gamewindow')
                widget:setWidth(19)
                widget:setHeight(21)
                widget:setIconClip(torect('91 0 9 12'))
                widget:setIconSize('9 12')
                widget:setIconOffset('4 5')
                widget:setTooltip('')
                widget.ignoreCallback = true
                widget:setChecked(supportHasteEnabled)
                widget.ignoreCallback = nil
                widget.onMousePress = onMiniBotGameWindowMousePressFromPanel
            end

            gameWindow = modules.game_minibot.getSettingsValue(true, 'equipmentAmulet_gamewindow', false)
            if gameWindow then
                widget = g_ui.createWidget('MiniBotShortcutButton', panel)
                widget:constructEnviorementVariables()
                widget:setId('equipmentAmulet_gamewindow')
                widget:setWidth(19)
                widget:setHeight(21)
                widget:setIconClip(torect('325 0 13 13'))
                widget:setIconSize('13 13')
                widget:setIconOffset('4 5')
                widget:setTooltip('')
                widget.ignoreCallback = true
                widget:setChecked(equipmentAmuletEnabled)
                widget.ignoreCallback = nil
                widget.onMousePress = onMiniBotGameWindowMousePressFromPanel
            end

            gameWindow = modules.game_minibot.getSettingsValue(true, 'equipmentRing_gamewindow', false)
            if gameWindow then
                widget = g_ui.createWidget('MiniBotShortcutButton', panel)
                widget:constructEnviorementVariables()
                widget:setId('equipmentRing_gamewindow')
                widget:setWidth(19)
                widget:setHeight(21)
                widget:setIconClip(torect('338 0 13 12'))
                widget:setIconSize('13 12')
                widget:setIconOffset('4 5')
                widget:setTooltip('')
                widget.ignoreCallback = true
                widget:setChecked(equipmentRingEnabled)
                widget.ignoreCallback = nil
                widget.onMousePress = onMiniBotGameWindowMousePressFromPanel
            end

            gameWindow = modules.game_minibot.getSettingsValue(true, 'tankMode_gamewindow', false)
            if gameWindow then
                widget = g_ui.createWidget('MiniBotShortcutButton', panel)
                widget:constructEnviorementVariables()
                widget:setId('tankMode_gamewindow')
                widget:setWidth(19)
                widget:setHeight(21)
                widget:setIconClip(torect('390 0 13 12'))
                widget:setIconSize('11 12')
                widget:setIconOffset('4 5')
                widget:setTooltip('Tank Mode equips Stone Skin Amulet and Might Ring when available.')
                widget.ignoreCallback = true
                widget:setChecked(tankModeEnabled)
                widget.ignoreCallback = nil
                widget.onMousePress = onMiniBotGameWindowMousePressFromPanel
            end

            gameWindow = modules.game_minibot.getSettingsValue(true, 'huntingRecorder_gamewindow', false)
            if gameWindow then
                widget = g_ui.createWidget('MiniBotShortcutButton', panel)
                widget:constructEnviorementVariables()
                widget:setId('huntingRecorder_gamewindow')
                widget:setWidth(19)
                widget:setHeight(21)
                widget:setIconClip(torect('429 0 13 13'))
                widget:setIconSize('13 13')
                widget:setIconOffset('2 4')
                widget:setTooltip('')
                widget.ignoreCallback = true
                widget:setChecked(huntingRecorderEnabled)
                widget.ignoreCallback = nil
                widget.onMousePress = onMiniBotGameWindowMousePressFromPanel
            end

            gameWindow = modules.game_minibot.getSettingsValue(true, 'huntingExplorer_gamewindow', false)
            if gameWindow then
                widget = g_ui.createWidget('MiniBotShortcutButton', panel)
                widget:constructEnviorementVariables()
                widget:setId('huntingExplorer_gamewindow')
                widget:setWidth(19)
                widget:setHeight(21)
                widget:setIconClip(torect('221 0 9 13'))
                widget:setIconSize('8 13')
                widget:setIconOffset('6 4')
                widget:setTooltip('')
                widget.ignoreCallback = true
                widget:setChecked(huntingExplorerEnabled)
                widget.ignoreCallback = nil
                widget.onMousePress = onMiniBotGameWindowMousePressFromPanel
            end

            if panel:getChildCount() == 0 then
                panel:hide()
                modules.game_interface.setMiniBotTimerPanelStatus(false)
            else
                panel:setHeight(9 + (21 * panel:getChildCount()) + (panel:getChildCount() - 1))
                panel:show()
                modules.game_interface.setMiniBotTimerPanelStatus(huntingRecorderTimerEnabled)
            end
        end
    end
end

function onMiniBotGameWindowMousePressFromPanel(widget, _, button)
    if button ~= MouseRightButton then
        return
    end

    local primary = nil
    local secondary = nil
    if widget:getId() == 'combat_gamewindow' then
        primary = 'combat'
        secondary = 'combat_attack'
    elseif widget:getId() == 'shooter_gamewindow' then
        primary = 'combat'
        secondary = 'combat_shooter'
    elseif widget:getId() == 'combatTimer_gamewindow' then
        primary = 'combat'
        secondary = 'combat_timers'
    elseif widget:getId() == 'healingHealth_gamewindow' then
        primary = 'healing'
        secondary = 'healing_health'
    elseif widget:getId() == 'healingMana_gamewindow' then
        primary = 'healing'
        secondary = 'healing_mana'
    elseif widget:getId() == 'healingGroup_gamewindow' then
        primary = 'healing'
        secondary = 'healing_group'
    elseif widget:getId() == 'supportHaste_gamewindow' then
        primary = 'support'
        secondary = 'support_general'
    elseif widget:getId() == 'equipmentAmulet_gamewindow' then
        primary = 'equipment'
        secondary = 'equipment_amulets'
    elseif widget:getId() == 'equipmentRing_gamewindow' then
        primary = 'equipment'
        secondary = 'equipment_rings'
    elseif widget:getId() == 'tankMode_gamewindow' then
        primary = 'combat'
        secondary = 'combat_pvp'
    elseif widget:getId() == 'huntingRecorder_gamewindow' then
        primary = 'cavebot'
        secondary = 'hunting_recorder'
    elseif widget:getId() == 'huntingExplorer_gamewindow' then
        primary = 'cavebot'
        secondary = 'hunting_explorer'
    else
        return
    end

    if primary == nil then
        return
    end

    modules.game_minibot.show()
    modules.game_minibot.selectMinibotPanel(primary, secondary)
end

function onMiniBotGameWindowChangeFromPanel(widget, forceChecked)
    local localPlayer = g_game.getLocalPlayer()
    if type(widget) == 'string' then
        if forceChecked and widget == 'huntingRecorder_gamewindow' and localPlayer ~= nil and (localPlayer:getCaveBotTimestamp() >= os.time() or localPlayer:getCaveBotTimeLeft() <= 60) then
            return
        end

        local panel = modules.game_interface.getMiniBotPanel()
        if panel ~= nil then
            local foundPanel = panel:getChildById(widget)
            if foundPanel ~= nil then
                if forceChecked ~= nil then
                    foundPanel:setChecked(forceChecked)
                else
                    foundPanel:setChecked(not(foundPanel:isChecked()))
                end
                return
            end
        end
    end

    local settings2 = modules.game_minibot.getPressetSettings()
    local mSettings = settings2['combat_attack'] or {}
    if settings2['shortcuts'] == nil then
        settings2['shortcuts'] = {}
    end

    local widgetId = widget
    local widgetChecked = false
    if type(widget) == 'userdata' then
        widgetId = widget:getId()
        widgetChecked = widget:isChecked()
        if widget:getId() == 'huntingRecorder_gamewindow' and localPlayer ~= nil and (localPlayer:getCaveBotTimestamp() >= os.time() or localPlayer:getCaveBotTimeLeft() <= 60) then
            widgetChecked = false
        end

        if widgetChecked then
            widget:setImageClip(torect('0 46 22 23'))
            widget.mark:show()
        else
            widget:setImageClip(torect('0 0 22 23'))
            widget.mark:hide()
        end

        if widget.ignoreCallback then
            return
        end

        local pageModule = modules.game_minibot.getPageModule()
        if pageModule ~= nil and pageModule.reloadEnabledShortcut ~= nil then
            pageModule:reloadEnabledShortcut(widget)
        end
    else
        if widgetId == 'shooter_gamewindow' then
            widgetChecked = not(settings2['shortcuts']['shooter_enabled'] or false)
        elseif widgetId == 'healingHealth_gamewindow' then
            widgetChecked = not(settings2['shortcuts']['healingHealth_enabled'] or false)
        elseif widgetId == 'healingMana_gamewindow' then
            widgetChecked = not(settings2['shortcuts']['healingMana_enabled'] or false)
        elseif widgetId == 'combat_gamewindow' then
            widgetChecked = not(settings2['shortcuts']['autoAttack_enabled'] or false)
        elseif widgetId == 'combatTimer_gamewindow' then
            widgetChecked = not(settings2['shortcuts']['combatTimers_enabled'] or false)
        elseif widgetId == 'healingGroup_gamewindow' then
            widgetChecked = not(settings2['shortcuts']['healingGroup_enabled'] or false)
        elseif widgetId == 'supportHaste_gamewindow' then
            widgetChecked = not(settings2['shortcuts']['supportHaste_enabled'] or false)
        elseif widgetId == 'equipmentAmulet_gamewindow' then
            widgetChecked = not(settings2['shortcuts']['equipmentAmulet_enabled'] or false)
        elseif widgetId == 'equipmentRing_gamewindow' then
            widgetChecked = not(settings2['shortcuts']['equipmentRing_enabled'] or false)
        elseif widgetId == 'tankMode_gamewindow' then
            widgetChecked = not(settings2['shortcuts']['tankMode_enabled'] or false)
        elseif widgetId == 'huntingRecorder_gamewindow' then
            widgetChecked = not(settings2['shortcuts']['huntingRecorder_enabled'] or false)
        elseif widgetId == 'huntingRecorderTimer_gamewindow' then
            widgetChecked = not(settings2['shortcuts']['huntingRecorderTimer_enabled'] or false)
        elseif widgetId == 'huntingExplorer_gamewindow' then
            widgetChecked = not(settings2['shortcuts']['huntingExplorer_enabled'] or false)
        else
            return
        end

        if forceChecked ~= nil then
            widgetChecked = forceChecked
        end

        if widgetId == 'huntingRecorder_gamewindow' and localPlayer ~= nil and (localPlayer:getCaveBotTimestamp() >= os.time() or localPlayer:getCaveBotTimeLeft() <= 60) then
            widgetChecked = false
        end
    end

    if widgetChecked and (widgetId == 'huntingRecorder_gamewindow' or widgetId == 'huntingExplorer_gamewindow') and isBotCheckActive() then
        widgetChecked = false
        if type(widget) == 'userdata' then
            widget.ignoreCallback = true
            widget:setChecked(false)
            widget.ignoreCallback = nil
        end
    end

    local settings = ''
    local messageName = 'Unknown'
    local messageToggle = 0
    if widgetId == 'shooter_gamewindow' then
        settings = 'shooter_enabled'
        messageName = 'Magic Shooter'
        messageToggle = 0
        g_minibot.setModuleToggle(0, widgetChecked) -- Shooter (Attack)
    elseif widgetId == 'healingHealth_gamewindow' then
        settings = 'healingHealth_enabled'
        messageName = 'Health Healing'
        messageToggle = 1
        g_minibot.setModuleToggle(1, widgetChecked) -- Healing Health
    elseif widgetId == 'healingMana_gamewindow' then
        settings = 'healingMana_enabled'
        messageName = 'Mana Healing'
        messageToggle = 2
        g_minibot.setModuleToggle(2, widgetChecked) -- Healing Mana
    elseif widgetId == 'combat_gamewindow' then
        settings = 'autoAttack_enabled'
        messageName = 'Auto-attack'
    elseif widgetId == 'combatTimer_gamewindow' then
        settings = 'combatTimers_enabled'
        messageName = 'Combat Timers'
        messageToggle = 3
        g_minibot.setModuleToggle(3, widgetChecked) -- Combat Timers
    elseif widgetId == 'healingGroup_gamewindow' then
        settings = 'healingGroup_enabled'
        messageName = 'Group Healing'
        messageToggle = 6
        g_minibot.setModuleToggle(6, widgetChecked) -- Healing Group
    elseif widgetId == 'supportHaste_gamewindow' then
        settings = 'supportHaste_enabled'
        messageName = 'Support Haste'
        messageToggle = 4
        g_minibot.setModuleToggle(4, widgetChecked) -- Support Haste
    elseif widgetId == 'equipmentAmulet_gamewindow' then
        settings = 'equipmentAmulet_enabled'
        messageName = 'Amulet Equip.'
        messageToggle = 10
        g_minibot.setModuleToggle(10, widgetChecked) -- Equipment Amulet
    elseif widgetId == 'equipmentRing_gamewindow' then
        settings = 'equipmentRing_enabled'
        messageName = 'Ring Equip.'
        messageToggle = 11
        g_minibot.setModuleToggle(11, widgetChecked) -- Equipment Ring
    elseif widgetId == 'tankMode_gamewindow' then
        settings = 'tankMode_enabled'
        messageName = 'Tank Mode'
        messageToggle = 16
        g_minibot.setModuleToggle(16, widgetChecked) -- Tank Mode
    elseif widgetId == 'huntingRecorder_gamewindow' then
        settings = 'huntingRecorder_enabled'
        messageName = 'Hunting Recorder'
        messageToggle = 5
        g_minibot.setModuleToggle(5, widgetChecked) -- Hunting Recorder
        modules.game_minibot.toggleDisableCavebot()
        setupMinimapTexts()
    elseif widgetId == 'huntingRecorderTimer_gamewindow' then
        settings = 'huntingRecorderTimer_enabled'
        modules.game_interface.setMiniBotTimerPanelStatus(widgetChecked)
        messageToggle = -1
    elseif widgetId == 'huntingExplorer_gamewindow' then
        settings = 'huntingExplorer_enabled'
        messageName = 'Hunting Explorer'
        messageToggle = 21
        g_minibot.setModuleToggle(21, widgetChecked) -- Hunting Explorer
    else
        return
    end

    settings2['shortcuts'][settings] = widgetChecked
    modules.game_minibot.setPressetSettings(settings2)
    modules.game_console.focusChat()

    if messageToggle > -1 then
        local autoAttack = settings2['shortcuts']['autoAttack_enabled']
        if widgetId == 'tankMode_gamewindow' then
            combat_pvpModule.reloadInternalModule()
        elseif widgetId == 'combat_gamewindow' then
            g_minibot.setAutoAttack(modules.game_minibot.resolveAutoAttackType(autoAttack, mSettings))
        end

        if widgetId == 'combat_gamewindow' then
            messageToggle = g_minibot.getAutoAttack() > 0
        else
            messageToggle = g_minibot.isModuleToggle(messageToggle)
        end

        local stateName = messageToggle and 'enabled' or 'disabled'
        modules.game_textmessage.displayGameMessage(
            messageName .. ' module ' .. stateName .. '.')
    end

    if widgetChecked then
        if widgetId == 'huntingRecorder_gamewindow' then
            modules.game_minibot.onMiniBotGameWindowChangeFromPanel('huntingExplorer_gamewindow', false)
        elseif widgetId == 'huntingExplorer_gamewindow' then
            modules.game_minibot.onMiniBotGameWindowChangeFromPanel('huntingRecorder_gamewindow', false)
        end
    end
end

function main_settingsModule.onGameWindowChange(widget)
    if widget.ignoreCallback then
        return
    end

    local settingsName = ''
    if widget:getParent():getId() == 'shooter' then
        settingsName = 'shooter_gamewindow'
        --
    elseif widget:getParent():getId() == 'healingHealth' then
        settingsName = 'healingHealth_gamewindow'
        --
    elseif widget:getParent():getId() == 'healingMana' then
        settingsName = 'healingMana_gamewindow'
        --
    elseif widget:getParent():getId() == 'healingGroup' then
        settingsName = 'healingGroup_gamewindow'
        --
    elseif widget:getParent():getId() == 'supportHaste' then
        settingsName = 'supportHaste_gamewindow'
        --
    elseif widget:getId() == 'combatButton' then
        settingsName = 'combat_gamewindow'
        --
    elseif widget:getId() == 'gameWindowPanelButton' then
        settingsName = 'panel_gamewindow'
        --
    elseif widget:getParent():getId() == 'combatTimers' then
        settingsName = 'combatTimer_gamewindow'
        --
    elseif widget:getParent():getId() == 'equipmentAmulet' then
        settingsName = 'equipmentAmulet_gamewindow'
        --
    elseif widget:getParent():getId() == 'equipmentRing' then
        settingsName = 'equipmentRing_gamewindow'
        --
    elseif widget:getParent():getId() == 'tankMode' then
        settingsName = 'tankMode_gamewindow'
        --
    elseif widget:getParent():getId() == 'huntingRecorder' then
        settingsName = 'huntingRecorder_gamewindow'
        --
    elseif widget:getParent():getId() == 'huntingRecorderTimer' then
        settingsName = 'huntingRecorderTimer_gamewindow'
        --
    elseif widget:getParent():getId() == 'huntingExplorer' then
        settingsName = 'huntingExplorer_gamewindow'
        --
    else
        return
    end

    modules.game_minibot.setSettingsValue(true, settingsName, widget:isChecked())
    main_settingsModule.reloadInternalModule()
end
