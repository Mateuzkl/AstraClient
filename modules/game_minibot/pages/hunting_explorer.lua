hunting_explorerModule = {}

local huntingExplorer = nil

function hunting_explorerModule.init(widget)
    huntingExplorer = widget

    hunting_explorerModule.loadSettings()
end

function hunting_explorerModule.terminate()
    huntingExplorer = nil

end

function hunting_explorerModule.reloadInternalModule()
    local settings = modules.game_minibot.getPressetSettings()
    local sList = settings['explorer'] or {}
    local sShortcut = settings['shortcuts'] or {}

    local value = {
        findCreatures = 0,
        resumeCreatures = 0,
        lureCreatures = false
    }

    if sList['stop'] then
        value.findCreatures = tonumber(sList['stop_until'] or '') or 0
        value.resumeCreatures = tonumber(sList['stop_resume'] or '') or 0
    else
        value.findCreatures = tonumber(sList['lure_until'] or '') or 0
        value.resumeCreatures = tonumber(sList['lure_resume'] or '') or 0
        value.lureCreatures = true
    end

    g_minibot.setExplorerWalker(value)
    g_minibot.setModuleToggle(21, sShortcut['huntingExplorer_enabled'] == true)
end

function hunting_explorerModule.reloadLanguage(language)
    if language == 'ptbr' then
        huntingExplorer.panel.title:setText('Explorador Automatico')
        huntingExplorer.panel.lureTab.lure:setText('Lurar')
        huntingExplorer.panel.lureTab.lureHelp:setTooltip('Ativando a opcao de Lurar, o personagem andara poucos SQMs por vez, levando no seu movimento os monstros pelo caminho e matando distancia. Caso nenhuma criatura se encontre na visao do jogador, o movimento sera feito com mais rapidez.')
        huntingExplorer.panel.lureTab.untilLabel:setText('Parar se encontrar X monstros:')
        huntingExplorer.panel.lureTab.untilHelp:setTooltip('Configurar quantidade de monstros minimo para o Assistente parar o movimento e atacar os monstros. Valor 0 desativa parada, fazendo o Lure ser continuo.')
        huntingExplorer.panel.lureTab.resumeLabel:setText('Apos parada, andar se X monstros:')
        huntingExplorer.panel.lureTab.resumeHelp:setTooltip('Apos ter parado pela configuracao de parada, pode configurar quantidade de monstros maxima para o Assistente continuar atacando os monstros. Valor 0 faz com que ele respeite o valor acima de parada.')
        huntingExplorer.panel.stopFightTab.stop:setText('Correr e parar')
        huntingExplorer.panel.stopFightTab.stopHelp:setTooltip('Ativando a opcao de Correr e parar, o personagem continuara andando na velocidade normal ate encontrar a quantidade de monstros configurada abaixo. Nao configurar valores abaixo fara com que o personagem ande sem rumo e objetivo pela area.')
        huntingExplorer.panel.stopFightTab.untilLabel:setText('Parar se encontrar X monstros:')
        huntingExplorer.panel.stopFightTab.untilHelp:setTooltip('Configurar quantidade de monstros minimo para o Assistente parar o movimento e atacar os monstros. Valor 0 desativa parada, fazendo o personagem correr pela area sem objetivo.')
        huntingExplorer.panel.stopFightTab.resumeLabel:setText('Apos parada, andar se X monstros:')
        huntingExplorer.panel.stopFightTab.resumeHelp:setTooltip('Apos ter parado pela configuracao de parada, pode configurar quantidade de monstros maxima para o Assistente continuar atacando os monstros. Valor 0 faz com que ele respeite o valor acima de parada.')

    elseif language == 'enus' then
        huntingExplorer.panel.title:setText('Auto Explorer')
        huntingExplorer.panel.lureTab.lure:setText('Lure')
        huntingExplorer.panel.lureTab.lureHelp:setTooltip('By activating the Lure option, the character will move a few SQMs at a time, taking monsters along the way and killing them from distance. If no creatures are in the player\'s line of sight, the movement will be faster.')
        huntingExplorer.panel.lureTab.untilLabel:setText('Stop if find X monsters:')
        huntingExplorer.panel.lureTab.untilHelp:setTooltip('Set the minimum number of monsters for the Assistant to stop movement and attack the monsters. A value of 0 disables stopping, making the Lure continuous.')
        huntingExplorer.panel.lureTab.resumeLabel:setText('After stop, walk if X monsters:')
        huntingExplorer.panel.lureTab.resumeHelp:setTooltip('After stopping using the stop setting, you can set the maximum number of monsters for the Assistant to continue attacking. A value of 0 causes it to respect the above stop value.')
        huntingExplorer.panel.stopFightTab.stop:setText('Run and stop')
        huntingExplorer.panel.stopFightTab.stopHelp:setTooltip('By enabling the Run and Stop option, the character will continue walking at normal speed until encountering the number of monsters set below. Not setting the values below will cause the character to wander aimlessly through the area.')
        huntingExplorer.panel.stopFightTab.untilLabel:setText('Stop if find X monsters:')
        huntingExplorer.panel.stopFightTab.untilHelp:setTooltip('Set the minimum number of monsters for the Assistant to stop movement and attack the monsters. A value of 0 disables stopping, causing the character to run aimlessly through the area.')
        huntingExplorer.panel.stopFightTab.resumeLabel:setText('After stop, walk if X monsters:')
        huntingExplorer.panel.stopFightTab.resumeHelp:setTooltip('After stopping using the stop setting, you can set the maximum number of monsters for the Assistant to continue attacking. A value of 0 causes it to respect the above stop value.')

    end
end

function hunting_explorerModule.onWalkFailed(code)
    if huntingExplorer ~= nil then
        huntingExplorer.panel.enabled:setChecked(false)
    else
        modules.game_minibot.onMiniBotGameWindowChangeFromPanel('huntingExplorer_gamewindow', false)
    end
end

function hunting_explorerModule.loadSettings()
    local settings = modules.game_minibot.getPressetSettings()
    local sList = settings['explorer'] or {}
    local sShortcut = settings['shortcuts'] or {}

    huntingExplorer.panel.enabled.ignoreCallback = true
    huntingExplorer.panel.enabled:setChecked(sShortcut['huntingExplorer_enabled'] or false)
    huntingExplorer.panel.enabled.ignoreCallback = nil
    g_minibot.setModuleToggle(21, huntingExplorer.panel.enabled:isChecked())

    huntingExplorer.panel.enabled.onCheckChange = function()
        if huntingExplorer.panel.enabled.ignoreCallback then
            return
        end

        if huntingExplorer.panel.enabled:isChecked() and MiniBotCompat ~= nil and
            type(MiniBotCompat.getBotCheckAlarmState) == 'function' then
            local ok, alarmState = pcall(MiniBotCompat.getBotCheckAlarmState)
            if ok and type(alarmState) == 'table' and alarmState.active == true then
                huntingExplorer.panel.enabled.ignoreCallback = true
                huntingExplorer.panel.enabled:setChecked(false)
                huntingExplorer.panel.enabled.ignoreCallback = nil
            end
        end

        if huntingExplorer.panel.enabled:isChecked() then
            modules.game_minibot.hunting_recorderModule.onWalkFailed(0)
        end

        local panel = modules.game_interface.getMiniBotPanel()
        if panel ~= nil then
            local child = panel:getChildById('huntingExplorer_gamewindow')
            if child ~= nil then
                child.ignoreCallback = true
                child:setChecked(huntingExplorer.panel.enabled:isChecked())
                child.ignoreCallback = nil
            end
        end

        local settings2 = modules.game_minibot.getPressetSettings()
        if settings2['shortcuts'] == nil then
            settings2['shortcuts'] = {}
        end

        settings2['shortcuts']['huntingExplorer_enabled'] = huntingExplorer.panel.enabled:isChecked()
        modules.game_minibot.setPressetSettings(settings2)
        g_minibot.setModuleToggle(21, huntingExplorer.panel.enabled:isChecked()) -- Hunting Explorer
    end

    huntingExplorer.panel.lureTab.lure.ignoreCallback = true
    huntingExplorer.panel.lureTab.untilBox.ignoreCallback = true
    huntingExplorer.panel.lureTab.resume.ignoreCallback = true
    huntingExplorer.panel.stopFightTab.stop.ignoreCallback = true
    huntingExplorer.panel.stopFightTab.untilBox.ignoreCallback = true
    huntingExplorer.panel.stopFightTab.resume.ignoreCallback = true

    huntingExplorer.panel.lureTab.lure:setChecked(sList['lure'] or false)
    huntingExplorer.panel.stopFightTab.stop:setChecked(sList['stop'] or false)
    huntingExplorer.panel.lureTab.untilBox:setText(sList['lure_until'] or '')
    huntingExplorer.panel.lureTab.resume:setText(sList['lure_resume'] or '')
    huntingExplorer.panel.stopFightTab.untilBox:setText(sList['stop_until'] or '')
    huntingExplorer.panel.stopFightTab.resume:setText(sList['stop_resume'] or '')

    huntingExplorer.panel.lureTab.lure.ignoreCallback = nil
    huntingExplorer.panel.lureTab.untilBox.ignoreCallback = nil
    huntingExplorer.panel.lureTab.resume.ignoreCallback = nil
    huntingExplorer.panel.stopFightTab.stop.ignoreCallback = nil
    huntingExplorer.panel.stopFightTab.untilBox.ignoreCallback = nil
    huntingExplorer.panel.stopFightTab.resume.ignoreCallback = nil

    if huntingExplorer.panel.lureTab.lure:isChecked() then
        huntingExplorer.panel.stopFightTab.untilLabel:setEnabled(false)
        huntingExplorer.panel.stopFightTab.untilBox:setEnabled(false)
        huntingExplorer.panel.stopFightTab.resumeLabel:setEnabled(false)
        huntingExplorer.panel.stopFightTab.resume:setEnabled(false)
        huntingExplorer.panel.lureTab.untilLabel:setEnabled(true)
        huntingExplorer.panel.lureTab.untilBox:setEnabled(true)
        huntingExplorer.panel.lureTab.resumeLabel:setEnabled(true)
        huntingExplorer.panel.lureTab.resume:setEnabled(true)
    elseif huntingExplorer.panel.stopFightTab.stop:isChecked() then
        huntingExplorer.panel.stopFightTab.untilLabel:setEnabled(false)
        huntingExplorer.panel.stopFightTab.untilBox:setEnabled(false)
        huntingExplorer.panel.stopFightTab.resumeLabel:setEnabled(false)
        huntingExplorer.panel.stopFightTab.resume:setEnabled(false)
        huntingExplorer.panel.stopFightTab.untilLabel:setEnabled(true)
        huntingExplorer.panel.stopFightTab.untilBox:setEnabled(true)
        huntingExplorer.panel.stopFightTab.resumeLabel:setEnabled(true)
        huntingExplorer.panel.stopFightTab.resume:setEnabled(true)
    else
        huntingExplorer.panel.lureTab.lure:setChecked(true)
    end
end

function hunting_explorerModule.saveSettings()
    local settings = modules.game_minibot.getPressetSettings()
    local sList = settings['explorer'] or {}
    if settings['shortcuts'] == nil then
        settings['shortcuts'] = {}
    end

    local values = {}

    settings['shortcuts']['huntingExplorer_enabled'] = huntingExplorer.panel.enabled:isChecked()

    values['lure'] = huntingExplorer.panel.lureTab.lure:isChecked()
    values['stop'] = huntingExplorer.panel.stopFightTab.stop:isChecked()
    values['lure_until'] = tostring(huntingExplorer.panel.lureTab.untilBox:getText())
    values['lure_resume'] = tostring(huntingExplorer.panel.lureTab.resume:getText())
    values['stop_until'] = tostring(huntingExplorer.panel.stopFightTab.untilBox:getText())
    values['stop_resume'] = tostring(huntingExplorer.panel.stopFightTab.resume:getText())

    settings['explorer'] = values
    modules.game_minibot.setPressetSettings(settings)
    hunting_explorerModule.reloadInternalModule()
end

function hunting_explorerModule.reloadEnabledShortcut(_, widget)
    if widget:getId() ~= 'huntingExplorer_gamewindow' then
        return
    end

    huntingExplorer.panel.enabled.ignoreCallback = true
    huntingExplorer.panel.enabled:setChecked(widget:isChecked())
    huntingExplorer.panel.enabled.ignoreCallback = nil
end

function hunting_explorerModule.onTextOptionChange(widget)
    if widget.ignoreCallback then
        return
    end

    hunting_explorerModule.saveSettings()
end

function hunting_explorerModule.onStopChange(widget)
    if widget.ignoreCallback then
        return
    end

    if not(widget:isChecked()) then
        widget.ignoreCallback = true
        widget:setChecked(true)
        widget.ignoreCallback = nil
        return
    end

    huntingExplorer.panel.lureTab.lure.ignoreCallback = true
    huntingExplorer.panel.lureTab.lure:setChecked(false)
    huntingExplorer.panel.lureTab.lure.ignoreCallback = nil
    huntingExplorer.panel.lureTab.untilLabel:setEnabled(false)
    huntingExplorer.panel.lureTab.untilBox:setEnabled(false)
    huntingExplorer.panel.lureTab.resumeLabel:setEnabled(false)
    huntingExplorer.panel.lureTab.resume:setEnabled(false)

    huntingExplorer.panel.stopFightTab.untilLabel:setEnabled(true)
    huntingExplorer.panel.stopFightTab.untilBox:setEnabled(true)
    huntingExplorer.panel.stopFightTab.resumeLabel:setEnabled(true)
    huntingExplorer.panel.stopFightTab.resume:setEnabled(true)

    hunting_explorerModule.saveSettings()
end

function hunting_explorerModule.onLureChange(widget)
    if widget.ignoreCallback then
        return
    end

    if not(widget:isChecked()) then
        widget.ignoreCallback = true
        widget:setChecked(true)
        widget.ignoreCallback = nil
        return
    end

    huntingExplorer.panel.stopFightTab.stop.ignoreCallback = true
    huntingExplorer.panel.stopFightTab.stop:setChecked(false)
    huntingExplorer.panel.stopFightTab.stop.ignoreCallback = nil
    huntingExplorer.panel.stopFightTab.untilLabel:setEnabled(false)
    huntingExplorer.panel.stopFightTab.untilBox:setEnabled(false)
    huntingExplorer.panel.stopFightTab.resumeLabel:setEnabled(false)
    huntingExplorer.panel.stopFightTab.resume:setEnabled(false)

    huntingExplorer.panel.lureTab.untilLabel:setEnabled(true)
    huntingExplorer.panel.lureTab.untilBox:setEnabled(true)
    huntingExplorer.panel.lureTab.resumeLabel:setEnabled(true)
    huntingExplorer.panel.lureTab.resume:setEnabled(true)

    hunting_explorerModule.saveSettings()
end
