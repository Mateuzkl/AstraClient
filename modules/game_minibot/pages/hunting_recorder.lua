hunting_recorderModule = {}

local huntingWaypointsWindow = nil
local huntingWaypointsConfirmationWindow = nil
local virtualFloor = 7
local exportCodeVersion = 1

local function widgetAlive(widget)
    if widget == nil then
        return false
    end
    if g_ui ~= nil and type(g_ui.isWidgetAlive) == 'function' then
        local ok, alive = pcall(g_ui.isWidgetAlive, widget)
        return ok and alive == true
    end
    local ok, destroyed = pcall(function()
        return widget:isDestroyed()
    end)
    return ok and not destroyed
end

local function closeConfirmationWindow(instance)
    local window = instance or huntingWaypointsConfirmationWindow
    if instance ~= nil and huntingWaypointsConfirmationWindow ~= instance then
        return false
    end
    if huntingWaypointsConfirmationWindow == window then
        huntingWaypointsConfirmationWindow = nil
    end
    if widgetAlive(window) then
        pcall(function()
            window:destroy()
        end)
    end
    return window ~= nil
end

local function getDistanceBetween(p1, p2)
    if p1.z ~= p2.z then
        return nil
    end

    return math.max(math.abs(p1.x - p2.x), math.abs(p1.y - p2.y))
end

local function enableWaypointDragBehavior(widget)
    if widget == nil then
        return
    end

    widget:setDraggable(true)
    widget.onDragEnter = function(self)
        if self.waypointDragCursorActive then
            return true
        end

        self.waypointDragCursorActive = true
        g_mouse.pushCursor('target')
        return true
    end

    widget.onDragLeave = function(self)
        if not self.waypointDragCursorActive then
            return true
        end

        g_mouse.popCursor('target')
        self.waypointDragCursorActive = nil
        return true
    end
end

local function createNode(key, position)
    local widget = g_ui.createWidget('UIWidget', huntingWaypointsWindow.map.minimap)
    widget.tilePosition = position
    widget:setWidth(10)
    widget:setHeight(10)
    widget:setImageSource('/images/game_minibot/resources/icons_minibot')
    widget:show()
    widget.keyType = key
    if key == 'walk' then
        widget.originalWaypointClip = torect('234 0 10 10')
    elseif key == 'attack' then
        widget.originalWaypointClip = torect('247 0 10 10')
    elseif key == 'teleport' then
        widget.originalWaypointClip = torect('273 0 10 10')
    elseif key == 'connector' then
        widget.originalWaypointClip = torect('260 0 4 4')
        widget:setWidth(4)
        widget:setHeight(4)
        widget:setPhantom(true)
    else
        widget:destroy()
        return nil
    end

    widget:setImageClip(widget.originalWaypointClip)
    if key ~= 'connector' then
        widget.dragWaypointNode = true
        enableWaypointDragBehavior(widget)
    end
    widget.onMouseRelease = function(_, pos, button)
        local page = huntingWaypointsWindow
        if not widgetAlive(page) or not widgetAlive(widget) then
            return
        end

        local minimap = page.map and page.map.minimap or nil
        if not widgetAlive(minimap) then
            return
        end

        local mapPos = minimap:getTilePosition(pos)
        if not mapPos then
            return
        end

        if button == MouseLeftButton then
            hunting_recorderModule.onClickWaypointOnMap(widget)
        elseif button == MouseRightButton then
            local waypointIndex = widget.waypointIndex
            local menu = g_ui.createWidget('PopupMenu')
            menu:setGameMenu(true)
            menu:addOption('Remove node', function()
                if page ~= huntingWaypointsWindow or not widgetAlive(page) then
                    return
                end

                local cSession = hunting_recorderModule.getSessionSettings()
                if cSession['waypoints'] == nil then
                    cSession['waypoints'] = {}
                end

                local list, restoredWalkIndex =
                    hunting_recorderModule.removeWaypointAndRemapWalkIndex(
                        cSession['waypoints'], waypointIndex,
                        g_minibot.getCurrentWalkIndex())
                if list == nil then
                    return
                end

                cSession['waypoints'] = list
                hunting_recorderModule.setSessionSettings(cSession)
                local sessionList = page.sessions and page.sessions.list or nil
                if not widgetAlive(sessionList) then
                    return
                end
                for _, c in ipairs(sessionList:getChildren()) do
                    if widgetAlive(c) and c.sessionUid == hunting_recorderModule.selectedSessionUid then
                        hunting_recorderModule.selectedSessionUid = nil
                        hunting_recorderModule.onClickSessionEntry(c, restoredWalkIndex)
                        break
                    end
                end
            end)

            menu:display(pos)
        end

        return true
    end

    return widget
end

local function getLastNode()
    local widgets = huntingWaypointsWindow.map.minimap:getAlternatives()
    if widgets == nil or #widgets == 0 then
        return nil
    end

    return widgets[#widgets]
end

local function clonePosition(pos)
    if not pos then
        return nil
    end

    return { x = pos.x, y = pos.y, z = pos.z }
end

local function refreshWaypointListEntries()
    if huntingWaypointsWindow == nil or huntingWaypointsWindow.settings == nil then
        return
    end

    local list = huntingWaypointsWindow.settings.main.waypoints.list
    if list == nil then
        return
    end

    for index, child in ipairs(list:getChildren()) do
        if child.internalWaypointPosition ~= nil then
            local pos = child.internalWaypointPosition
            child:setText(string.format('%d: (%d, %d, %d)', index, pos.x, pos.y, pos.z))
        end

        child:setBackgroundColor('alpha')
    end
end

function hunting_recorderModule.getExportCodeVersion()
    return exportCodeVersion
end

function hunting_recorderModule.init(widget)
    if hunting_recorderModule.initialized then
        hunting_recorderModule.terminate()
    end
    hunting_recorderModule.initialized = true
    huntingWaypointsWindow = widget
    huntingWaypointsWindow.ignoreReloadInformation = true

    closeConfirmationWindow()

    huntingWaypointsWindow.settings.main.noNodeSelected:hide()
    huntingWaypointsWindow.settings.main.selected:hide()
    huntingWaypointsWindow.settings.main.waypoints:show()

    huntingWaypointsWindow.map.minimap:setZoom(2)
    huntingWaypointsWindow.map.minimap:disableAutoWalk()
    huntingWaypointsWindow.map.minimap.allowCallback = false

    local localPlayer = g_game.getLocalPlayer()
    if localPlayer ~= nil then
        local playerPos = localPlayer:getPosition()
        if playerPos ~= nil then
            huntingWaypointsWindow.map.minimap:setCameraPosition(playerPos)
            huntingWaypointsWindow.map.minimap:setCrossPosition(playerPos)
            virtualFloor = playerPos.z
        end
    end

    connect(g_game, {
        onMinibotCavebotTimer = hunting_recorderModule.onMinibotCavebotTimer
    })
    connect(LocalPlayer, {
        onPositionChange = hunting_recorderModule.onPositionChange,
        onAFKPauseChange = hunting_recorderModule.onAFKPauseChange
    })
    connect(g_minibot, {
        onWalkToNextNode = hunting_recorderModule.onWalkToNextNode,
        onWalkFailed = hunting_recorderModule.onWalkFailed
    })
    --huntingWaypointsWindow.map.minimap:load()

    huntingWaypointsWindow.map.minimap.onMouseRelease = function(_, pos, button)
        local page = huntingWaypointsWindow
        if not widgetAlive(page) then
            return false
        end

        local minimap = page.map and page.map.minimap or nil
        if not widgetAlive(minimap) then
            return false
        end

        local mapPos = minimap:getTilePosition(pos)
        if not mapPos then
            return
        end
        if button == MouseLeftButton then
        elseif button == MouseRightButton then
            local waypointPosition = clonePosition(mapPos)
            local menu = g_ui.createWidget('PopupMenu')
            menu:setGameMenu(true)
            menu:addOption('Add walking node', function()
                if page == huntingWaypointsWindow and widgetAlive(page) then
                    hunting_recorderModule.insertWaypointOnPos(waypointPosition, false)
                end
            end)
            menu:addOption('Add stair/teleport node', function()
                if page == huntingWaypointsWindow and widgetAlive(page) then
                    hunting_recorderModule.insertWaypointOnPos(waypointPosition, true)
                end
            end)
            menu:display(pos)
            return true
        end
        return false
    end

    huntingWaypointsWindow.map.minimap.onDrop = function(_, droppedWidget, mousePos)
        return hunting_recorderModule.onMinimapDropWaypoint(droppedWidget, mousePos)
    end

    hunting_recorderModule.loadSettings()
    huntingWaypointsWindow.ignoreReloadInformation = nil
    g_game.afkPause(0)

    if localPlayer ~= nil then
        local language = modules.game_minibot.getSettingsValue(false, 'language', 'ptbr')
        local timestamp = localPlayer:getCaveBotTimestamp()
        if timestamp >= os.time() then
            if language == 'ptbr' then
                huntingWaypointsWindow.map:setText('Por violar regras do servidor, voce esta proibido de utilizar o cavebot ate ' .. os.date("o dia %d/%m/%Y as %H:%M!", timestamp))
            elseif language == 'enus' then
                huntingWaypointsWindow.map:setText('For violating server rules, you are prohibited from using the cavebot until ' .. os.date("the day %d/%m/%Y at %H:%M!", timestamp))
            end
        else
            huntingWaypointsWindow.map.accept:setVisible(not(huntingWaypointsWindow.map.minimap:isExplicitlyVisible()))
        end

        hunting_recorderModule.onMinibotCavebotTimer(localPlayer:getCaveBotTimeLeft(), localPlayer:getCaveBotTotalTimeLeft(), localPlayer:isCaveBotTask(), localPlayer:getCaveBotRenewPrice())
    else
        huntingWaypointsWindow.map.accept:setVisible(true)
    end
end

function hunting_recorderModule.terminate()
    if hunting_recorderModule.recordingEvent ~= nil then
        removeEvent(hunting_recorderModule.recordingEvent)
        hunting_recorderModule.recordingEvent = nil
    end

    if not hunting_recorderModule.initialized then
        huntingWaypointsWindow = nil
        return
    end
    hunting_recorderModule.initialized = false

    disconnect(g_game, {
        onMinibotCavebotTimer = hunting_recorderModule.onMinibotCavebotTimer
    })
    disconnect(LocalPlayer, {
        onPositionChange = hunting_recorderModule.onPositionChange,
        onAFKPauseChange = hunting_recorderModule.onAFKPauseChange
    })
    disconnect(g_minibot, {
        onWalkToNextNode = hunting_recorderModule.onWalkToNextNode,
        onWalkFailed = hunting_recorderModule.onWalkFailed
    })

    closeConfirmationWindow()

    huntingWaypointsWindow = nil

end

function hunting_recorderModule.onWalkToNextNode(index)
    hunting_recorderModule.selectedSessionIndex = index
    if not widgetAlive(huntingWaypointsWindow) then
        return
    end

    local waypointList = huntingWaypointsWindow.settings.main.waypoints.list
    if not widgetAlive(waypointList) then
        return
    end
    for _, c in ipairs(waypointList:getChildren()) do
        if widgetAlive(c) and c.waypointIndex == index then
            hunting_recorderModule.internalSelectWaypoint(nil, index, false, false)
            waypointList:ensureChildVisible(c)
            return
        end
    end
end

function hunting_recorderModule.onMinibotCavebotTimer(timeleft, total, task, renewPrice)
    if not widgetAlive(huntingWaypointsWindow) then
        return
    end

    local language = modules.game_minibot.getSettingsValue(false, 'language', 'ptbr')
    if task then
        if language == 'ptbr' then
            huntingWaypointsWindow.map.titlePanel.taskButton:setText('Ativado')
        elseif language == 'enus' then
            huntingWaypointsWindow.map.titlePanel.taskButton:setText('Activated')
        end
        huntingWaypointsWindow.map.titlePanel.taskButton:setButtonColor('green')
        huntingWaypointsWindow.map.titlePanel.taskButton.onLeftClick = function()
            g_game.afkPause(3)
        end
    else
        if language == 'ptbr' then
            huntingWaypointsWindow.map.titlePanel.taskButton:setText('Desativado')
        elseif language == 'enus' then
            huntingWaypointsWindow.map.titlePanel.taskButton:setText('Deactivated')
        end
        huntingWaypointsWindow.map.titlePanel.taskButton:setButtonColor('red')
        huntingWaypointsWindow.map.titlePanel.taskButton.onLeftClick = function()
            g_game.afkPause(2)
        end
    end

    if modules.game_minibot.getCacheResourceBalance() >= renewPrice and (total - timeleft) >= 900 then
        huntingWaypointsWindow.map.titlePanel.renewButton:setButtonColor('yellow')
        huntingWaypointsWindow.map.titlePanel.renewButton.mark:show()
        huntingWaypointsWindow.map.titlePanel.renewButton:setText("Renovar 1 hora")
        huntingWaypointsWindow.map.titlePanel.renewButton:setColor('#dddddd')
        huntingWaypointsWindow.map.titlePanel.renewButton:setEnabled(true)
        huntingWaypointsWindow.map.titlePanel.renewButton.onLeftClick = function()
            local message = ""
            if language == 'ptbr' then
                message = "Você tem certeza que deseja renovar 1 hora do Cavebot?\nO valor de " .. comma_value(renewPrice) .. " gold coins será cobrado do seu personagem, e 1 hora será adicionada ao tempo disponível do Cavebot.\n\nCaso opte pela renovação sem ter gasto 1 hora do tempo disponível, o tempo extra não será adicionado ao seu personagem,\nmas o valor será cobrado normalmente."
            elseif language == 'enus' then
                message = "Are you sure you want to renew 1 hour of the Cavebot?\nThe amount of " .. comma_value(renewPrice) .. " gold coins will be charged from your character, and 1 hour will be added to the available time of the Cavebot.\n\nIf you choose to renew without having used 1 hour of available time, the extra time will not be added to your character,\nbut the amount will be charged normally."
            end
            modules.game_minibot.openConfirmationWindow("Deusot Cavebot Timer", message, function()
                g_game.afkPause(4)
            end, function()
            
            end)
        end
        if language == 'ptbr' then
            huntingWaypointsWindow.map.titlePanel.helpRenew:setTooltip("Ao utilizar ao menos 15 minutos do Cavebot você poderá renovar 1 hora do tempo disponível.\nO preço para renovar 1 hora do Cavebot é de " .. comma_value(renewPrice) .. " gold coins, aumentando a cada renovação.\n\nCaso opte pela renovação sem ter gasto 1 hora do tempo disponível, o tempo extra não será adicionado ao seu personagem, mas o valor será cobrado normalmente.")
        elseif language == 'enus' then
            huntingWaypointsWindow.map.titlePanel.helpRenew:setTooltip("By using the Cavebot for at least 15 minutes you can renew 1 hour of available time.\nThe price to renew 1 hour of the Cavebot is " .. comma_value(renewPrice) .. " gold coins, increasing with each renewal.\n\nIf you choose to renew without having used 1 hour of available time, the extra time will not be added to your character, but the amount will be charged normally.")
        end
    else
        if modules.game_minibot.getCacheResourceBalance() < renewPrice then
            if language == 'ptbr' then
                huntingWaypointsWindow.map.titlePanel.helpRenew:setTooltip("Você não possui recursos suficientes para renovar o cavebot. Você precisa de " .. comma_value(renewPrice) .. " gold coins para renovar 1 hora.")
            elseif language == 'enus' then
                huntingWaypointsWindow.map.titlePanel.helpRenew:setTooltip("You do not have enough resources to renew the cavebot. You need " .. comma_value(renewPrice) .. " gold coins to renew 1 hour.")
            end
        end
        if (total - timeleft) < 900 then
            if language == 'ptbr' then
                huntingWaypointsWindow.map.titlePanel.helpRenew:setTooltip("Você precisa utilizar o cavebot por pelo menos 15 minutos antes de poder renovar o tempo disponível.")
            elseif language == 'enus' then
                huntingWaypointsWindow.map.titlePanel.helpRenew:setTooltip("You need to use the cavebot for at least 15 minutes before you can renew the available time.")
            end
        end
        huntingWaypointsWindow.map.titlePanel.renewButton:setButtonColor('red')
        huntingWaypointsWindow.map.titlePanel.renewButton.mark:hide()
        huntingWaypointsWindow.map.titlePanel.renewButton:setText("Indisponivel")
        huntingWaypointsWindow.map.titlePanel.renewButton:setColor('#C0C0C0')
        huntingWaypointsWindow.map.titlePanel.renewButton:setEnabled(false)
        huntingWaypointsWindow.map.titlePanel.renewButton.onLeftClick = nil
    end

    local progress = math.max(0, math.min(100, math.ceil((timeleft * 100) / math.max(1, total))))
    local hours = math.floor(timeleft / 3600)
    local minutes = math.floor((timeleft % 3600) / 60)
    local timerKey = hours * 60 + minutes
    local timerText = string.format("%d:%02d", hours, minutes)

    local lines = {}
    if language == 'ptbr' then
        table.insert(lines, "Tempo restante: ")
        table.insert(lines, "#C0C0C0")
        table.insert(lines, timerText .. " horas\n")
        if progress > 75 then
            table.insert(lines, "#6bdd6d")
        elseif progress > 25 then
            table.insert(lines, "#ddd46b")
        else
            table.insert(lines, "#dd6b6b")
        end
        table.insert(lines, "Renovar (1h): ")
        table.insert(lines, "#C0C0C0")
        table.insert(lines, comma_value(renewPrice))
        table.insert(lines, "#c5a52d")
        table.insert(lines, " gold!")
        table.insert(lines, "#C0C0C0")
    elseif language == 'enus' then
        table.insert(lines, "Time left: ")
        table.insert(lines, "#C0C0C0")
        table.insert(lines, timerText .. " hours\n")
        if progress > 75 then
            table.insert(lines, "#6bdd6d")
        elseif progress > 25 then
            table.insert(lines, "#ddd46b")
        else
            table.insert(lines, "#dd6b6b")
        end
        table.insert(lines, "Renew (1h): ")
        table.insert(lines, "#C0C0C0")
        table.insert(lines, comma_value(renewPrice))
        table.insert(lines, "#c5a52d")
        table.insert(lines, " gold!")
        table.insert(lines, "#C0C0C0")
    end
    huntingWaypointsWindow.map.titlePanel.renewTitle:setColoredText(lines)
end

function hunting_recorderModule.onAFKPauseChange(localPlayer, _)
    if not widgetAlive(huntingWaypointsWindow) then
        return
    end

    local timestamp = localPlayer:getAFKPauseTimestamp()
    local language = modules.game_minibot.getSettingsValue(false, 'language', 'ptbr')
    if timestamp <= os.time() then
        if language == 'ptbr' then
            huntingWaypointsWindow.map.titlePanel.button:setText('Disponivel')
        elseif language == 'enus' then
            huntingWaypointsWindow.map.titlePanel.button:setText('Available')
        end
        huntingWaypointsWindow.map.titlePanel.button:setButtonColor('green')
        huntingWaypointsWindow.map.titlePanel.button.onLeftClick = function()
            g_game.afkPause(1)
            modules.game_minibot.toggleDisableCavebot()
        end
    else
        local elapsed = timestamp - os.time()

        local str
        if elapsed < 60 then
            str = "< 1 min"
        else
            local hours = math.floor(elapsed / 3600)
            local minutes = math.floor((elapsed % 3600) / 60)

            local hourLabel
            local minuteLabel = 'min'
            if language == 'ptbr' then
                hourLabel = (hours == 1) and 'hora' or 'horas'
            elseif language == 'enus' then
                hourLabel = (hours == 1) and 'hour' or 'hours'
            else
                hourLabel = (hours == 1) and 'hour' or 'hours'
            end

            if hours > 0 then
                str = string.format('%d %s %d %s', hours, hourLabel, minutes, minuteLabel)
            else
                str = string.format('%d %s', minutes, minuteLabel)
            end
        end
        huntingWaypointsWindow.map.titlePanel.button:setText(str)
        huntingWaypointsWindow.map.titlePanel.button.onLeftClick = nil
        huntingWaypointsWindow.map.titlePanel.button:setButtonColor('red')
    end
end

function hunting_recorderModule.setPreWalk(position)
    if hunting_recorderModule.recordingEvent == nil then
        return
    end

    hunting_recorderModule.recordingPosition = position
end

function hunting_recorderModule.insertTransitionWaypoints(oldPos, newPos)
    if oldPos == nil or newPos == nil then
        return false
    end

    -- A teleport/stair waypoint denotes the tile that must be entered before
    -- the floor jump.  The arrival is an ordinary destination; marking both
    -- ends as teleport makes the executor wait for a second jump at newPos.
    hunting_recorderModule.insertWaypointOnPos(oldPos, true)
    hunting_recorderModule.insertWaypointOnPos(newPos, false)
    return true
end

function hunting_recorderModule.onPositionChange(creature, newPos, oldPos)
    if not widgetAlive(huntingWaypointsWindow) then
        return
    end

    if not(creature:isLocalPlayer()) then
        return
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local pos = player:getPosition()
    if not pos then
        return
    end

    huntingWaypointsWindow.map.minimap:setCameraPosition(pos)
    huntingWaypointsWindow.map.minimap:setCrossPosition(pos)

    if hunting_recorderModule.recordingEvent ~= nil then
        if newPos ~= nil and oldPos ~= nil and (newPos.z ~= oldPos.z or (math.max(math.abs(newPos.x - oldPos.x), math.abs(newPos.y - oldPos.y))> 1)) then
            hunting_recorderModule.insertTransitionWaypoints(oldPos, newPos)
        else
            if hunting_recorderModule.lastPosition ~= nil then
                local distance = getDistanceBetween(hunting_recorderModule.lastPosition, player:getPosition())
                if distance == nil or distance > 3 then
                    hunting_recorderModule.cycleRecord()
                end
            end
        end
    end

    virtualFloor = pos.z
    hunting_recorderModule.refreshVirtualFloorsFullMap()
end

function hunting_recorderModule.loadSessionList()
    local sessions = {}
    local sSessions = modules.game_minibot.getSettingsValue(false, 'sessions', {})
    for _, entry in pairs(sSessions) do
      table.insert(sessions, entry)
    end
    table.sort(sessions, function(a, b)
      return a.creation < b.creation
    end)

    if #sessions == 0 then
      local newEntry = hunting_recorderModule.createBrandnewSession()
      sSessions[tostring(newEntry.uid)] = newEntry
      table.insert(sessions, newEntry)
      modules.game_minibot.setSettingsValue(false, 'sessions', sSessions)
    end

    huntingWaypointsWindow.sessions.list:destroyChildren()
    for _, entry in ipairs(sessions) do
        hunting_recorderModule.createSessionWidget(entry)
    end
end

function hunting_recorderModule.reloadLanguage(language)
    if language == 'ptbr' then
        huntingWaypointsWindow.map.title:setText('Previa do mapa')
        huntingWaypointsWindow.sessions.title:setText('Sessoes')
        huntingWaypointsWindow.settings.title:setText('Configuracoes')
        huntingWaypointsWindow.settings.tab.node:setText('Config.')
        huntingWaypointsWindow.settings.main.noNodeSelected:setText('Voce deve selecionar um waypoint no mapa ou lista para edita-lo.')
        huntingWaypointsWindow.settings.main.selected.stopAtLabel:setText('Parar se:')
        huntingWaypointsWindow.settings.main.selected.resumeAtLabel:setText('Voltar a andar se:')
        huntingWaypointsWindow.settings.main.selected.stopHelp:setTooltip('Configurar um valor para que quando o personagem estiver nesse waypoint, ele podera parar o movimento caso encontre X monstros no seu alcance de visao.')
        huntingWaypointsWindow.settings.main.selected.resumeHelp:setTooltip('Configurar um valor para que quando o personagem estiver parado nesse waypoint pela configuracao anterior, ele podera retomar o movimento caso a quanntidade de monstros no seu alcance de visao seja menor ou igual a esse valor. Deixar o valor 0 fara ele respeitar apenas o valor de parada acima.')
        huntingWaypointsWindow.settings.main.selected.lure:setText('Lurar')
        huntingWaypointsWindow.settings.main.selected.titleLabel:setText('Editando waypoint:')
        huntingWaypointsWindow.settings.main.selected.overwriteToAll:setText('Alterar para todos')
        huntingWaypointsWindow.warningText = 'Aviso!\n\nVoce esta prestes a substituir TODAS as opcoes de waypoints de registro dessa sessao pela configuracao do waypoint #%d.\n\nContinuar mesmo assim?'
        huntingWaypointsWindow.settings.main.selected.lureSpeedLabel:setText('Velocidade de lure:')
        huntingWaypointsWindow.settings.main.selected.lureSpeedHelp:setTooltip('A forca de Lure ira determinar a velocidade e o tempo que o personagem ficara parado entre movimentos quando estiver com a opcao de lure ativado. Quanto MAIOR a velocidade, mais RAPIDO sera a movimentacao do personagem. Quanto MENOR o valor, mais LENTO o personagem ira se movimentar.')
        huntingWaypointsWindow.map.titlePanel.title:setText('Pausa AFK por 5 minutos:')
        huntingWaypointsWindow.map.titlePanel.help:setTooltip('E possivel pausar a verificacao de Cavebot 100% AFK por 5 minutos a cada 2 horas. Com essa pausa, sera visivel para os outros jogadores que voce esta com essa pausa ativa, assim blindando o seu personagem de verificacao anti-bot durante o efeito da pausa.')
        huntingWaypointsWindow.map.titlePanel.taskTitle:setText('Ativar o Modo Task:')
        huntingWaypointsWindow.map.titlePanel.taskHelp:setTooltip('Ao ativar o Modo Task com o Cave-bot ativo, o tempo disponivel de Cave-bot no seu personagem não sera consumido, porém o Loot e experiencia ganha sera reduzido drasticamente!')

    elseif language == 'enus' then
        huntingWaypointsWindow.map.title:setText('Map preview')
        huntingWaypointsWindow.sessions.title:setText('Sessions')
        huntingWaypointsWindow.settings.title:setText('Settings')
        huntingWaypointsWindow.settings.tab.node:setText('Config')
        huntingWaypointsWindow.settings.main.noNodeSelected:setText('You must select a node on the map or list to edit it.')
        huntingWaypointsWindow.settings.main.selected.stopAtLabel:setText('Stop if:')
        huntingWaypointsWindow.settings.main.selected.resumeAtLabel:setText('Walk again if:')
        huntingWaypointsWindow.settings.main.selected.stopHelp:setTooltip('Set a value so that when the character is at this waypoint, he can stop movement if he finds X monsters in his line of sight.')
        huntingWaypointsWindow.settings.main.selected.resumeHelp:setTooltip('Set a value so that when the character is stopped at this waypoint according to the previous configuration, they can resume movement if the number of monsters in their line of sight is less than or equal to this value. Leaving the value at 0 will make it respect only the above stopping value.')
        huntingWaypointsWindow.settings.main.selected.lure:setText('Lure')
        huntingWaypointsWindow.settings.main.selected.titleLabel:setText('Editing waypoint:')
        huntingWaypointsWindow.settings.main.selected.overwriteToAll:setText('Overwrite to all')
        huntingWaypointsWindow.warningText = 'Warning!\n\nYou are about to overwrite ALL of your record waypoints options with the waypoint #%d config.\n\nContinue?'
        huntingWaypointsWindow.settings.main.selected.lureSpeedLabel:setText('Lure speed:')
        huntingWaypointsWindow.settings.main.selected.lureSpeedHelp:setTooltip('Lure strength determines the character\'s speed and the amount of time they will remain waiting between movements when the lure option is activated. The HIGHER the speed, the FASTER the character will move. The LOWER the value, the SLOWER the character will move.')
        huntingWaypointsWindow.map.titlePanel.title:setText('AFK Pause for 5 minutes:')
        huntingWaypointsWindow.map.titlePanel.help:setTooltip('It is possible to pause the 100% AFK Cavebot check for 5 minutes every 2 hours. With this pause, it will be visible to other players that you are on pause, thus shielding your character from anti-bot checks during the pause effect.')
        huntingWaypointsWindow.map.titlePanel.taskTitle:setText('Activate Task Mode:')
        huntingWaypointsWindow.map.titlePanel.taskHelp:setTooltip('When Task Mode is activated with the Cave-bot enabled, the available Cave-bot time on your character will not be consumed, but the loot and experience gained will be drastically reduced.')

    end
end

function hunting_recorderModule.onAcceptRules(widget)
    huntingWaypointsWindow.map.enabled:show()
    huntingWaypointsWindow.map.minimap:show()
    huntingWaypointsWindow.map.layersPanel:show()
    huntingWaypointsWindow.map.titlePanel:show()
    huntingWaypointsWindow.map.accept:hide()
end

function hunting_recorderModule.updateWaypointSpeed(waypoints, waypointIndex, speed)
    if type(waypoints) ~= 'table' or type(waypointIndex) ~= 'number' or type(speed) ~= 'number' then
        return false
    end
    for _, waypoint in pairs(waypoints) do
        if type(waypoint) == 'table' and waypoint['index'] == waypointIndex then
            waypoint['speed'] = speed
            return true
        end
    end
    return false
end

function hunting_recorderModule.updateSelectedWaypointSpeed(waypoints, speed)
    return hunting_recorderModule.updateWaypointSpeed(
        waypoints, hunting_recorderModule.selectedSessionIndex, speed)
end

function hunting_recorderModule.clampWalkIndex(index, waypoints)
    index = tonumber(index) or 0
    if index ~= index or index == math.huge or index == -math.huge then
        index = 0
    end
    index = math.max(0, math.floor(index))

    local maximumIndex = 0
    if type(waypoints) == 'table' then
        for _, waypoint in pairs(waypoints) do
            local waypointIndex = type(waypoint) == 'table' and tonumber(waypoint['index']) or nil
            if waypointIndex ~= nil and waypointIndex == waypointIndex and
                waypointIndex ~= math.huge and waypointIndex ~= -math.huge then
                maximumIndex = math.max(maximumIndex, math.floor(waypointIndex))
            end
        end
    end

    return math.min(index, math.max(0, maximumIndex))
end

function hunting_recorderModule.removeWaypointAndRemapWalkIndex(waypoints, removedIndex, currentWalkIndex)
    if type(waypoints) ~= 'table' then
        return nil, hunting_recorderModule.clampWalkIndex(currentWalkIndex, {})
    end

    removedIndex = tonumber(removedIndex)
    if removedIndex == nil or removedIndex ~= removedIndex or
        removedIndex == math.huge or removedIndex == -math.huge then
        return nil, hunting_recorderModule.clampWalkIndex(currentWalkIndex, waypoints)
    end
    removedIndex = math.floor(removedIndex)

    local list = {}
    local removed = false
    for _, waypoint in pairs(waypoints) do
        if type(waypoint) == 'table' and tonumber(waypoint['index']) == removedIndex then
            removed = true
        else
            table.insert(list, waypoint)
        end
    end
    if not removed then
        return nil, hunting_recorderModule.clampWalkIndex(currentWalkIndex, waypoints)
    end

    table.sort(list, function(a, b)
        return (tonumber(a['index']) or 0) < (tonumber(b['index']) or 0)
    end)
    for index, waypoint in ipairs(list) do
        waypoint['index'] = index
    end

    local restoredWalkIndex = tonumber(currentWalkIndex) or 0
    restoredWalkIndex = math.max(0, math.floor(restoredWalkIndex))
    if removedIndex <= restoredWalkIndex and restoredWalkIndex > 0 then
        restoredWalkIndex = restoredWalkIndex - 1
    end
    return list, hunting_recorderModule.clampWalkIndex(restoredWalkIndex, list)
end

function hunting_recorderModule.reloadInternalModulePreservingWalkIndex(selectedIndex)
    if selectedIndex == nil then
        selectedIndex = g_minibot.getCurrentWalkIndex()
    end
    hunting_recorderModule.reloadInternalModule()
    local cSession = hunting_recorderModule.getSessionSettings()
    local waypoints = type(cSession) == 'table' and cSession['waypoints'] or nil
    local restoredIndex = hunting_recorderModule.clampWalkIndex(selectedIndex, waypoints)
    g_minibot.setCurrentWalkIndex(restoredIndex)
    return restoredIndex
end

function hunting_recorderModule.onLureScrollChange(widget)
    huntingWaypointsWindow.settings.main.selected.lureSpeed:setText(widget:getValue())
    if widget.ignoreCallback then
        return
    end

    local cSession2 = hunting_recorderModule.getSessionSettings()
    if cSession2['waypoints'] == nil then
        cSession2['waypoints'] = {}
    end

    if not hunting_recorderModule.updateSelectedWaypointSpeed(cSession2['waypoints'], widget:getValue()) then
        return
    end

    hunting_recorderModule.setSessionSettings(cSession2)
    hunting_recorderModule.reloadInternalModulePreservingWalkIndex()
end

function hunting_recorderModule.reloadEnabledShortcut(_, widget)
    if not widgetAlive(huntingWaypointsWindow) or widget == nil then
        return
    end

    local widgetType = type(widget)
    if (widgetType == 'userdata' and not widgetAlive(widget)) or
        (widgetType ~= 'userdata' and widgetType ~= 'table') then
        return
    end
    if type(widget.getId) ~= 'function' or type(widget.isChecked) ~= 'function' then
        return
    end

    if widget:getId() ~= 'huntingRecorder_gamewindow' then
        return
    end

    huntingWaypointsWindow.map.enabled.ignoreCallback = true
    huntingWaypointsWindow.map.enabled:setChecked(widget:isChecked())
    huntingWaypointsWindow.map.enabled.ignoreCallback = nil
end

function hunting_recorderModule.onWalkFailed(_, moduleType)
    if moduleType ~= nil and moduleType ~= 5 then
        return
    end
    if widgetAlive(huntingWaypointsWindow) then
        huntingWaypointsWindow.map.enabled:setChecked(false)
    else
        modules.game_minibot.onMiniBotGameWindowChangeFromPanel('huntingRecorder_gamewindow', false)
    end
end

function hunting_recorderModule.loadSettings()
    hunting_recorderModule.loadSessionList()

    local settings = modules.game_minibot.getPressetSettings()
    local sShortcut = settings['shortcuts'] or {}

    huntingWaypointsWindow.map.enabled.ignoreCallback = true
    huntingWaypointsWindow.map.enabled:setChecked(sShortcut['huntingRecorder_enabled'] or false)
    huntingWaypointsWindow.map.enabled.ignoreCallback = nil

    huntingWaypointsWindow.map.enabled.onCheckChange = function()
        if huntingWaypointsWindow.map.enabled.ignoreCallback then
            return
        end

        if huntingWaypointsWindow.map.enabled:isChecked() and MiniBotCompat ~= nil and
            type(MiniBotCompat.getBotCheckAlarmState) == 'function' then
            local ok, alarmState = pcall(MiniBotCompat.getBotCheckAlarmState)
            if ok and type(alarmState) == 'table' and alarmState.active == true then
                huntingWaypointsWindow.map.enabled.ignoreCallback = true
                huntingWaypointsWindow.map.enabled:setChecked(false)
                huntingWaypointsWindow.map.enabled.ignoreCallback = nil
            end
        end

        if huntingWaypointsWindow.map.enabled:isChecked() then
            modules.game_minibot.hunting_explorerModule.onWalkFailed(0)
        end

        local panel = modules.game_interface.getMiniBotPanel()
        if panel ~= nil then
            local child = panel:getChildById('huntingRecorder_gamewindow')
            if child ~= nil then
                child.ignoreCallback = true
                child:setChecked(huntingWaypointsWindow.map.enabled:isChecked())
                child.ignoreCallback = nil
            end
        end

        local settings2 = modules.game_minibot.getPressetSettings()
        if settings2['shortcuts'] == nil then
            settings2['shortcuts'] = {}
        end

        settings2['shortcuts']['huntingRecorder_enabled'] = huntingWaypointsWindow.map.enabled:isChecked()
        modules.game_minibot.setPressetSettings(settings2)
        g_minibot.setModuleToggle(5, huntingWaypointsWindow.map.enabled:isChecked()) -- Hunting Recorder
        modules.game_minibot.toggleDisableCavebot()
    end

    if hunting_recorderModule.selectedSessionUid ~= nil then
        for _, c in ipairs(huntingWaypointsWindow.sessions.list:getChildren()) do
            if c.sessionUid == hunting_recorderModule.selectedSessionUid then
                hunting_recorderModule.selectedSessionUid = nil
                local oldIndex = hunting_recorderModule.selectedSessionIndex
                c.onLeftClick()
                hunting_recorderModule.selectedSessionIndex = oldIndex
                if hunting_recorderModule.selectedSessionIndex ~= nil then
                    for _, c2 in ipairs(huntingWaypointsWindow.settings.main.waypoints.list:getChildren()) do
                        if c2.waypointIndex == hunting_recorderModule.selectedSessionIndex then
                            huntingWaypointsWindow.map.minimap:setCameraPosition(c2.internalWaypointPosition)
                            hunting_recorderModule.internalSelectWaypoint(nil, hunting_recorderModule.selectedSessionIndex, false, false)
                            huntingWaypointsWindow.settings.main.waypoints.list:ensureChildVisible(c2)
                            huntingWaypointsWindow.settings.tab.waypoints:setEnabled(false)
                            huntingWaypointsWindow.settings.tab.node:setEnabled(true)
                            if not g_minibot.isModuleToggle(5) then
                                g_minibot.setCurrentWalkIndex(oldIndex - 1)
                            end
                            break
                        end
                    end
                end
                break
            end
        end
    end
end

function hunting_recorderModule.reloadInternalModule()
    if huntingWaypointsWindow ~= nil and huntingWaypointsWindow.ignoreReloadInformation then
        return
    end

    g_minibot.resetRecorderSession()

    local cSession = hunting_recorderModule.getSessionSettings()
    if cSession['waypoints'] == nil then
        cSession['waypoints'] = {}
    end

    local list = {}
    for _, waypoint in pairs(cSession['waypoints']) do
        table.insert(list, waypoint)
    end
    table.sort(list, function(a, b)
        return a.index < b.index
    end)

    for _, waypoint in ipairs(list) do
        local point = {
            position = { x = waypoint['position']['x'], y = waypoint['position']['y'], z = waypoint['position']['z'] },
            creatures = waypoint['creatures'],
            resume = waypoint['resume'],
            lure = waypoint['lure'],
            index = waypoint['index'],
            teleport = waypoint['teleport'],
            speed = waypoint['speed'] or 5
        }

        g_minibot.registerWalkWaypoint(point)
    end
end

function hunting_recorderModule.onUpMapFloor()
    if virtualFloor == 0 then
        return
    end

    huntingWaypointsWindow.map.minimap:floorUp(1)
    virtualFloor = virtualFloor - 1
    hunting_recorderModule.refreshVirtualFloorsFullMap()
end

function hunting_recorderModule.onDownMapFloor()
    if virtualFloor == 15 then
        return
    end

    huntingWaypointsWindow.map.minimap:floorDown(1)
    virtualFloor = virtualFloor + 1
    hunting_recorderModule.refreshVirtualFloorsFullMap()
end

function hunting_recorderModule.refreshVirtualFloorsFullMap()
    huntingWaypointsWindow.map.layersPanel.layersMark:setMarginTop(((virtualFloor + 1) * 4) - 3)
    huntingWaypointsWindow.map.layersPanel.automapLayers:setImageClip((virtualFloor * 14) .. ' 0 14 67')
end

function hunting_recorderModule.onClickSessionEntry(widget, restoredWalkIndex)
    for _, c in ipairs(widget:getParent():getChildren()) do
      if c ~= widget then
        c.mask:hide()
        c.selectedSession = false
      end
    end

    widget.mask:show()
    widget.selectedSession = true
    if hunting_recorderModule.selectedSessionUid == widget.sessionUid then
        return
    end

    hunting_recorderModule.selectedSessionUid = widget.sessionUid
    modules.game_minibot.setSettingsValue(true, 'selected_recordSession', widget.sessionUid)

    huntingWaypointsWindow.settings.main.waypoints.list:destroyChildren()
    local cSession = hunting_recorderModule.getSessionSettings()
    if cSession['waypoints'] == nil then
        cSession['waypoints'] = {}
    end

    local list = {}
    for _, waypoint in pairs(cSession['waypoints']) do
        table.insert(list, waypoint)
    end
    table.sort(list, function(a, b)
        return a.index < b.index
    end)

    for _, waypoint in ipairs(list) do
        hunting_recorderModule.createBrandNewSessionWaypoint(waypoint['position'], true, waypoint['index'])
    end

    refreshWaypointListEntries()

    huntingWaypointsWindow.map.minimap:destroyAlternatives()
    for _, waypoint in ipairs(list) do
        local cPos = { x = waypoint['position']['x'], y = waypoint['position']['y'], z = waypoint['position']['z'] }
--[[
        local lastNode = getLastNode()
        if lastNode ~= nil then
            local path = g_map.findPath(lastNode.tilePosition, cPos, 200, 0, true)
            if path ~= nil and #path > 0 then
                local currentPos = { x = lastNode.tilePosition.x, y = lastNode.tilePosition.y, z = lastNode.tilePosition.z }
                local ignoreNext = false
                for _, dir in ipairs(path) do
                    if dir == 0 then
                        currentPos.y = currentPos.y - 1
                    elseif dir == 1 then
                        currentPos.x = currentPos.x + 1
                    elseif dir == 2 then
                        currentPos.y = currentPos.y + 1
                    elseif dir == 3 then
                        currentPos.x = currentPos.x - 1
                    elseif dir == 4 then
                        currentPos.y = currentPos.y - 1
                        currentPos.x = currentPos.x + 1
                    elseif dir == 5 then
                        currentPos.x = currentPos.x + 1
                        currentPos.y = currentPos.y + 1
                    elseif dir == 6 then
                        currentPos.x = currentPos.x - 1
                        currentPos.y = currentPos.y + 1
                    elseif dir == 7 then
                        currentPos.x = currentPos.x - 1
                        currentPos.y = currentPos.y - 1
                    end
                    if not ignoreNext then
                        ignoreNext = true
                        local connector = createNode('connector', { x = currentPos.x, y = currentPos.y, z = currentPos.z })
                        huntingWaypointsWindow.map.minimap:addAlternativeWidget(connector, { x = currentPos.x, y = currentPos.y, z = currentPos.z })
                        huntingWaypointsWindow.map.minimap:internalRegisterAlternative(connector)
                    else
                        ignoreNext = false
                    end
                end
                lastNode:raise()
            else
                lastNode.keyType = 'teleport'
                lastNode.originalWaypointClip = torect('273 0 10 10')
                lastNode:setImageClip(lastNode.originalWaypointClip)
            end
        end
]]--
        local nodeWidget = createNode(waypoint['teleport'] and 'teleport' or 'walk', cPos)
        nodeWidget.waypointIndex = waypoint['index']
        nodeWidget:setTooltip('Waypoint ' .. nodeWidget.waypointIndex .. "\nx: " .. cPos.x .. "\ny: " .. cPos.y .. "\nz: " .. cPos.z)
        huntingWaypointsWindow.map.minimap:addAlternativeWidget(nodeWidget, cPos)
        huntingWaypointsWindow.map.minimap:centerInPosition(nodeWidget, nodeWidget.pos)
    end
    huntingWaypointsWindow.map.minimap:getLayout():update()
    if restoredWalkIndex ~= nil then
        hunting_recorderModule.reloadInternalModulePreservingWalkIndex(restoredWalkIndex)
    else
        hunting_recorderModule.reloadInternalModule()
    end
end

function hunting_recorderModule.createBrandnewSession(uid)
    local lastSession = uid
    if uid == nil then
        lastSession = modules.game_minibot.getSettingsValue(false, 'last_session', 0) + 1
    end

    local entry = {
        name = ('New Session #' .. lastSession),
        uid = lastSession,
        creation = os.time()
    }

    if uid == nil then
        modules.game_minibot.setSettingsValue(false, 'last_session', lastSession)
    end

    return entry
end

function hunting_recorderModule.onImportCode(codeTable)
    local validated, validationError = modules.game_minibot.validateMiniBotConfigurationData(codeTable, 'recorder-import')
    if validated == nil then
        if g_logger ~= nil and type(g_logger.warning) == 'function' then
            g_logger.warning('[game_minibot] recorder import rejected: ' .. tostring(validationError))
        end
        return false
    end
    codeTable = validated

    local sSessions = modules.game_minibot.getSettingsValue(false, 'sessions', {})
    codeTable['version'] = nil

    local newWaypoints = table.copy(codeTable['waypoints'])
    codeTable['waypoints'] = nil

    local newEntry = hunting_recorderModule.createBrandnewSession()
    newEntry.name = codeTable['name']
    hunting_recorderModule.createSessionWidget(newEntry)
    sSessions[tostring(newEntry.uid)] = newEntry

    modules.game_minibot.setSettingsValue(false, 'sessions', sSessions)

    local ssSessions = modules.game_minibot.getSettingsValue(false, 'sessions_settings', {})
    ssSessions[tostring(newEntry.uid)] = {
        ['waypoints'] = newWaypoints
    }
    modules.game_minibot.setSettingsValue(false, 'sessions_settings', ssSessions)
    return true
end

function hunting_recorderModule.onClickSessionImport(widget)
    modules.game_minibot.importNewPreset(true)
end

function hunting_recorderModule.onClickSessionExport(widget)
    local cSession = hunting_recorderModule.getSessionSettings()
    if cSession['waypoints'] == nil then
        return
    end

    local currentSession = modules.game_minibot.getSettingsValue(true, 'selected_recordSession', nil)
    if currentSession == nil then
        return {}
    end

    local sSessions = modules.game_minibot.getSettingsValue(false, 'sessions', {})
    for _, entry in pairs(sSessions) do
        if entry.uid == currentSession then
            local message = ""
            local language = modules.game_minibot.getSettingsValue(false, 'language', 'ptbr')
            if language == 'ptbr' then
                message = "Sua sessao '" .. entry.name .. "' foi exportada com sucesso para a sua area de transferencia. (CTRL + C)"
            elseif language == 'enus' then
                message = "Your session '" .. entry.name .. "' has been succesfully exported into your clipboard. (CTRL + C)"
            end

            local copyTable = table.copy(entry)
            copyTable['waypoints'] = cSession['waypoints']
            copyTable['version'] = exportCodeVersion
            g_window.setClipboardText(table.obscure(copyTable))
            modules.game_minibot.openConfirmationWindow("DeusOT Hunting recorder", message)
            return
        end
    end
end

function hunting_recorderModule.createSessionWidget(entry)
    local widget = g_ui.createWidget('MiniBotHuntingRecorderEntry', huntingWaypointsWindow.sessions.list)
    widget:constructEnviorementVariables()

    widget:setText(entry.name)
    widget:setTooltip(entry.name)
    widget.onMousePress = hunting_recorderModule.openSessionGameMenu

    widget.sessionUid = entry.uid

    widget:setBackgroundColor('alpha')

    widget.onLeftClick = function()
        hunting_recorderModule.onClickSessionEntry(widget)
    end
end

function hunting_recorderModule.openSessionGameMenu(widget, mousePos, mouseButton)
    if mouseButton ~= MouseRightButton then
        return
    end

    local page = huntingWaypointsWindow
    if not widgetAlive(page) or not widgetAlive(widget) then
        return
    end

    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)

    menu:addOption("Edit '" .. widget:getText() .. "' name", function()
        if page == huntingWaypointsWindow and widgetAlive(page) and widgetAlive(widget) then
            hunting_recorderModule.onClickEditPreset(widget)
        end
    end)

    menu:addOption("Remove '" .. widget:getText() .. "'", function()
        if page == huntingWaypointsWindow and widgetAlive(page) and widgetAlive(widget) then
            hunting_recorderModule.onClickRemovePreset(widget)
        end
    end)

    menu:display(mousePos)
    return true
end

function hunting_recorderModule.onClickEditPreset(widget)
    if not widgetAlive(widget) then
        return
    end

    local page = huntingWaypointsWindow
    local sessionUid = widget.sessionUid
    modules.game_minibot.openEditPresetNameWindow(widget:getText(), function(newName)
        local sessions = {}
        local sSessions = modules.game_minibot.getSettingsValue(false, 'sessions', {})
        for _, entry in pairs(sSessions) do
            if entry.uid == sessionUid then
                entry.name = newName
                if page == huntingWaypointsWindow and widgetAlive(page) and widgetAlive(widget) then
                    widget:setText(newName)
                end
            end

            sessions[tostring(entry.uid)] = entry
        end

        modules.game_minibot.setSettingsValue(false, 'sessions', sessions)
    end)
end

function hunting_recorderModule.onClickRemovePreset(widget)
    if not widgetAlive(huntingWaypointsWindow) or not widgetAlive(widget) then
        return
    end

    if huntingWaypointsWindow.sessions.list:getChildCount() <= 1 then
        return
    end

    local sessions = {}
    local sSessions = modules.game_minibot.getSettingsValue(false, 'sessions', {})
    for _, entry in pairs(sSessions) do
        if entry.uid ~= widget.sessionUid then
            sessions[tostring(entry.uid)] = entry
        end
    end

    modules.game_minibot.setSettingsValue(false, 'sessions', sessions)

    local sessionSettings = modules.game_minibot.getSettingsValue(false, 'sessions_settings', {})
    sessionSettings[tostring(widget.sessionUid)] = nil
    modules.game_minibot.setSettingsValue(false, 'sessions_settings', sessionSettings)

    hunting_recorderModule.loadSessionList()

    local firstChild = huntingWaypointsWindow.sessions.list:getChildByIndex(1)
    if firstChild ~= nil then
        firstChild:onLeftClick()
    end
end

function hunting_recorderModule.onClickNewSession()
    local sSessions = modules.game_minibot.getSettingsValue(false, 'sessions', {})
    local entry = hunting_recorderModule.createBrandnewSession()
    hunting_recorderModule.createSessionWidget(entry)
    sSessions[tostring(entry.uid)] = entry
    modules.game_minibot.setSettingsValue(false, 'sessions', sSessions)
end

function hunting_recorderModule.onSessionSearchChange(widget)
    local sSessions = modules.game_minibot.getSettingsValue(false, 'sessions', {})
    for _, child in pairs(huntingWaypointsWindow.sessions.list:getChildren()) do
        if child.sessionUid ~= nil and sSessions[tostring(child.sessionUid)] ~= nil then
            local entry = sSessions[tostring(child.sessionUid)]
            if entry.name:lower():find(widget:getText():lower(), 1, true) then
                child:show()
            else
                child:hide()
            end
        end
    end
    
end

function hunting_recorderModule.getSessionSettings()
    local currentSession = modules.game_minibot.getSettingsValue(true, 'selected_recordSession', nil)
    if currentSession == nil then
        return {}
    end

    local sSessions = modules.game_minibot.getSettingsValue(false, 'sessions_settings', {})
    return sSessions[tostring(currentSession)] or {}
end

function hunting_recorderModule.setSessionSettings(value)
    local currentSession = modules.game_minibot.getSettingsValue(true, 'selected_recordSession', nil)
    if currentSession == nil then
        return
    end

    local sSessions = modules.game_minibot.getSettingsValue(false, 'sessions_settings', {})
    sSessions[tostring(currentSession)] = value
    modules.game_minibot.setSettingsValue(false, 'sessions_settings', sSessions)
end

function hunting_recorderModule.moveWaypointToPosition(index, newPosition)
    if huntingWaypointsWindow == nil or index == nil or newPosition == nil then
        return false
    end

    local cSession = hunting_recorderModule.getSessionSettings()
    if cSession['waypoints'] == nil then
        return false
    end

    local updated = false
    for _, waypoint in pairs(cSession['waypoints']) do
        if waypoint['index'] == index then
            waypoint['position'] = waypoint['position'] or {}
            waypoint['position']['x'] = newPosition.x
            waypoint['position']['y'] = newPosition.y
            waypoint['position']['z'] = newPosition.z
            updated = true
            break
        end
    end

    if not updated then
        return false
    end

    hunting_recorderModule.setSessionSettings(cSession)

    local list = huntingWaypointsWindow.settings.main.waypoints.list
    if list ~= nil then
        for _, child in ipairs(list:getChildren()) do
            if child.waypointIndex == index then
                child.internalWaypointPosition = clonePosition(newPosition)
                break
            end
        end
    end

    refreshWaypointListEntries()

    local minimap = huntingWaypointsWindow.map.minimap
    if minimap ~= nil then
        for _, alternative in ipairs(minimap:getAlternatives()) do
            if alternative.waypointIndex == index then
                local updatedPos = clonePosition(newPosition)
                alternative.pos = updatedPos
                alternative.tilePosition = updatedPos
                minimap:centerInPosition(alternative, alternative.pos)
                break
            end
        end
        minimap:getLayout():update()
    end

    if cSession['waypoints'] ~= nil and index == #cSession['waypoints'] then
        hunting_recorderModule.lastPosition = clonePosition(newPosition)
    end

    hunting_recorderModule.reloadInternalModulePreservingWalkIndex()

    return true
end

function hunting_recorderModule.onMinimapDropWaypoint(droppedWidget, mousePos)
    if huntingWaypointsWindow == nil or droppedWidget == nil then
        return false
    end

    local isListWidget = droppedWidget.dragWaypointEntry
    local isMapWidget = droppedWidget.dragWaypointNode
    if (not isListWidget and not isMapWidget) or droppedWidget.waypointIndex == nil then
        return false
    end

    local minimap = huntingWaypointsWindow.map.minimap
    local mapPos = minimap:getTilePosition(mousePos)
    if not mapPos then
        return false
    end

    if mapPos.z == nil and droppedWidget.tilePosition ~= nil then
        mapPos.z = droppedWidget.tilePosition.z
    end

    local newPosition = clonePosition(mapPos)
    return hunting_recorderModule.moveWaypointToPosition(droppedWidget.waypointIndex, newPosition)
end

function hunting_recorderModule.internalSelectWaypoint(widget, index, ignoreList, ignoreMap)
    hunting_recorderModule.selectedSessionIndex = index
    -- Select on list
    if not(ignoreList) then
        for _, c in ipairs(huntingWaypointsWindow.settings.main.waypoints.list:getChildren()) do
            if c.waypointIndex == index then
                c.ignoreWaypointCallback = true
                c:onLeftClick()
                huntingWaypointsWindow.settings.main.waypoints.list:ensureChildVisible(c)
                c.ignoreWaypointCallback = nil
            else
                c.mask:hide()
            end
        end
    end

    -- Select on map
    if not(ignoreMap) then
        for _, c in ipairs(huntingWaypointsWindow.map.minimap:getAlternatives()) do
            if c.waypointIndex ~= nil then
                if c.waypointIndex == index then
                    c.ignoreWaypointCallback = true
                    hunting_recorderModule.onClickWaypointOnMap(c)
                    c.ignoreWaypointCallback = nil
                else
                    c:setImageClip(c.originalWaypointClip)
                    c:setWidth(10)
                    c:setHeight(10)
                end
            end
        end
    end

    local cSession = hunting_recorderModule.getSessionSettings()
    if cSession['waypoints'] == nil then
        cSession['waypoints'] = {}
    end

    for _, waypoint in pairs(cSession['waypoints']) do
        if waypoint['index'] == index then
            huntingWaypointsWindow.settings.main.selected.stopAt.onTextChange = nil
            huntingWaypointsWindow.settings.main.selected.stopAt:setText(waypoint['creatures'])
            huntingWaypointsWindow.settings.main.selected.stopAt.onTextChange = function()
                local cSession2 = hunting_recorderModule.getSessionSettings()
                if cSession2['waypoints'] == nil then
                    cSession2['waypoints'] = {}
                end

                local list = {}
                for _, waypoint2 in pairs(cSession2['waypoints']) do
                    if waypoint2['index'] == index then
                        local newValue = 0
                        if huntingWaypointsWindow.settings.main.selected.stopAt:getText() ~= '' then
                            newValue = tonumber(huntingWaypointsWindow.settings.main.selected.stopAt:getText()) or 0
                        end
                        waypoint2['creatures'] = newValue
                    end
                    table.insert(list, waypoint2)
                end

                cSession2['waypoints'] = list
                hunting_recorderModule.setSessionSettings(cSession2)
                hunting_recorderModule.reloadInternalModulePreservingWalkIndex()
            end

            huntingWaypointsWindow.settings.main.selected.resumeAt.onTextChange = nil
            huntingWaypointsWindow.settings.main.selected.resumeAt:setText(waypoint['resume'])
            huntingWaypointsWindow.settings.main.selected.resumeAt.onTextChange = function()
                local cSession2 = hunting_recorderModule.getSessionSettings()
                if cSession2['waypoints'] == nil then
                    cSession2['waypoints'] = {}
                end

                local list = {}
                for _, waypoint2 in pairs(cSession2['waypoints']) do
                    if waypoint2['index'] == index then
                        local newValue = 0
                        if huntingWaypointsWindow.settings.main.selected.resumeAt:getText() ~= '' then
                            newValue = tonumber(huntingWaypointsWindow.settings.main.selected.resumeAt:getText()) or 0
                        end
                        waypoint2['resume'] = newValue
                    end
                    table.insert(list, waypoint2)
                end

                cSession2['waypoints'] = list
                hunting_recorderModule.setSessionSettings(cSession2)
                hunting_recorderModule.reloadInternalModulePreservingWalkIndex()
            end

            huntingWaypointsWindow.settings.main.selected.overwriteToAll.onLeftClick = function()
                modules.game_minibot.internalToggle(false)
                closeConfirmationWindow()
                local page = huntingWaypointsWindow
                if not widgetAlive(page) then
                    modules.game_minibot.internalToggle(true)
                    return
                end

                local confirmationWindow

                local cancelCopy = function()
                    if huntingWaypointsConfirmationWindow ~= confirmationWindow then
                        return false
                    end
                    closeConfirmationWindow(confirmationWindow)
                    modules.game_minibot.internalToggle(true)
                    return true
                end

                local confirmCopy = function()
                    if not cancelCopy() or page ~= huntingWaypointsWindow or not widgetAlive(page) then
                        return
                    end

                    local cSession2 = hunting_recorderModule.getSessionSettings()
                    if cSession2['waypoints'] == nil then
                        cSession2['waypoints'] = {}
                    end

                    local list = {}
                    for _, waypoint2 in pairs(cSession2['waypoints']) do
                        local newValue = 0
                        if page.settings.main.selected.stopAt:getText() ~= '' then
                            newValue = tonumber(page.settings.main.selected.stopAt:getText()) or 0
                        end
                        waypoint2['creatures'] = newValue

                        newValue = 0
                        if page.settings.main.selected.resumeAt:getText() ~= '' then
                            newValue = tonumber(page.settings.main.selected.resumeAt:getText()) or 0
                        end
                        waypoint2['resume'] = newValue

                        waypoint2['lure'] = page.settings.main.selected.lure:isChecked()
                        waypoint2['speed'] = page.settings.main.selected.lureSpeedScroll:getValue()

                        table.insert(list, waypoint2)
                    end

                    cSession2['waypoints'] = list
                    hunting_recorderModule.setSessionSettings(cSession2)
                    hunting_recorderModule.reloadInternalModulePreservingWalkIndex()
                end

                confirmationWindow = displayGeneralBox("Assistant dialog", string.format(page.warningText, index),
                    { { text=tr('No'), callback=cancelCopy },
                    { text=tr('Yes'), callback=confirmCopy },
                    anchor=AnchorHorizontalCenter }, confirmCopy, cancelCopy)
                huntingWaypointsConfirmationWindow = confirmationWindow
                if not widgetAlive(confirmationWindow) then
                    closeConfirmationWindow(confirmationWindow)
                    modules.game_minibot.internalToggle(true)
                end
            end

            huntingWaypointsWindow.settings.main.selected.titleValue:setText('#' .. index)

            huntingWaypointsWindow.settings.main.selected.lureSpeedScroll.ignoreCallback = true
            huntingWaypointsWindow.settings.main.selected.lureSpeedScroll:setValue(waypoint['speed'] or 5)
            huntingWaypointsWindow.settings.main.selected.lureSpeedScroll.ignoreCallback = nil

            huntingWaypointsWindow.settings.main.selected.lure.onCheckChange = nil
            huntingWaypointsWindow.settings.main.selected.lure:setChecked(false)
            huntingWaypointsWindow.settings.main.selected.lure:setChecked(waypoint['lure'])
            huntingWaypointsWindow.settings.main.selected.lure.onCheckChange = function()
                if huntingWaypointsWindow.settings.main.selected.lure:isChecked() then
                    huntingWaypointsWindow.settings.main.selected.stopAtLabel:hide()
                    huntingWaypointsWindow.settings.main.selected.stopAt:hide()
                    huntingWaypointsWindow.settings.main.selected.stopHelp:hide()
                    huntingWaypointsWindow.settings.main.selected.resumeAtLabel:hide()
                    huntingWaypointsWindow.settings.main.selected.resumeAt:hide()
                    huntingWaypointsWindow.settings.main.selected.resumeHelp:hide()
                    huntingWaypointsWindow.settings.main.selected.lureSpeedLabel:show()
                    huntingWaypointsWindow.settings.main.selected.lureSpeedScroll:show()
                    huntingWaypointsWindow.settings.main.selected.lureSpeed:show()
                    huntingWaypointsWindow.settings.main.selected.lureSpeedHelp:show()
                else
                    huntingWaypointsWindow.settings.main.selected.stopAtLabel:show()
                    huntingWaypointsWindow.settings.main.selected.stopAt:show()
                    huntingWaypointsWindow.settings.main.selected.stopHelp:show()
                    huntingWaypointsWindow.settings.main.selected.resumeAtLabel:show()
                    huntingWaypointsWindow.settings.main.selected.resumeAt:show()
                    huntingWaypointsWindow.settings.main.selected.resumeHelp:show()
                    huntingWaypointsWindow.settings.main.selected.lureSpeedLabel:hide()
                    huntingWaypointsWindow.settings.main.selected.lureSpeedScroll:hide()
                    huntingWaypointsWindow.settings.main.selected.lureSpeed:hide()
                    huntingWaypointsWindow.settings.main.selected.lureSpeedHelp:hide()
                end

                local cSession2 = hunting_recorderModule.getSessionSettings()
                if cSession2['waypoints'] == nil then
                    cSession2['waypoints'] = {}
                end

                local list = {}
                for _, waypoint2 in pairs(cSession2['waypoints']) do
                    if waypoint2['index'] == index then
                        waypoint2['lure'] = huntingWaypointsWindow.settings.main.selected.lure:isChecked()
                    end
                    table.insert(list, waypoint2)
                end

                cSession2['waypoints'] = list
                hunting_recorderModule.setSessionSettings(cSession2)
                hunting_recorderModule.reloadInternalModulePreservingWalkIndex()
            end
            if waypoint['lure'] then
                huntingWaypointsWindow.settings.main.selected.stopAtLabel:hide()
                huntingWaypointsWindow.settings.main.selected.stopAt:hide()
                huntingWaypointsWindow.settings.main.selected.stopHelp:hide()
                huntingWaypointsWindow.settings.main.selected.resumeAtLabel:hide()
                huntingWaypointsWindow.settings.main.selected.resumeAt:hide()
                huntingWaypointsWindow.settings.main.selected.resumeHelp:hide()
                huntingWaypointsWindow.settings.main.selected.lureSpeedLabel:show()
                huntingWaypointsWindow.settings.main.selected.lureSpeedScroll:show()
                huntingWaypointsWindow.settings.main.selected.lureSpeed:show()
                huntingWaypointsWindow.settings.main.selected.lureSpeedHelp:show()
            else
                huntingWaypointsWindow.settings.main.selected.stopAtLabel:show()
                huntingWaypointsWindow.settings.main.selected.stopAt:show()
                huntingWaypointsWindow.settings.main.selected.stopHelp:show()
                huntingWaypointsWindow.settings.main.selected.resumeAtLabel:show()
                huntingWaypointsWindow.settings.main.selected.resumeAt:show()
                huntingWaypointsWindow.settings.main.selected.resumeHelp:show()
                huntingWaypointsWindow.settings.main.selected.lureSpeedLabel:hide()
                huntingWaypointsWindow.settings.main.selected.lureSpeedScroll:hide()
                huntingWaypointsWindow.settings.main.selected.lureSpeed:hide()
                huntingWaypointsWindow.settings.main.selected.lureSpeedHelp:hide()
            end

            break
        end
    end

    if widget == nil or widget.ignoreCallback then
        return
    end

    if not g_minibot.isModuleToggle(5) then
        g_minibot.setCurrentWalkIndex(index - 1)
    end
end

function hunting_recorderModule.createBrandNewSessionWaypoint(position, ignoreReload, index)
    local widget = g_ui.createWidget('MiniBotHuntingRecorderEntry', huntingWaypointsWindow.settings.main.waypoints.list)
    widget.waypointIndex = index
    widget:constructEnviorementVariables()

    widget.internalWaypointPosition = clonePosition(position)

    widget.dragWaypointEntry = true
    enableWaypointDragBehavior(widget)

    if not(ignoreReload) then
        refreshWaypointListEntries()
    end

    widget.onLeftClick = function()
        for _, c in ipairs(huntingWaypointsWindow.settings.main.waypoints.list:getChildren()) do
            c.mask:hide()
            c.selectedWaypoint = false
        end
        widget.mask:show()
        widget.selectedWaypoint = true

        if widget.ignoreWaypointCallback then
            return
        end

        huntingWaypointsWindow.map.minimap:setCameraPosition(widget.internalWaypointPosition)
        hunting_recorderModule.internalSelectWaypoint(widget, index, true, false)
    end

    return widget
end

function hunting_recorderModule.onClickWaypointOnMap(widget)
    if widget.keyType == 'connector' or widget.originalWaypointClip.x ~= widget:getImageClip().x then
        return
    end

    for _, c in ipairs(widget:getParent():getChildren()) do
        if c.keyType ~= 'connector' then
            c:setImageClip(c.originalWaypointClip)
            c:setWidth(10)
            c:setHeight(10)
        end
    end

    widget:setImageClip(torect('286 0 12 12'))
    widget:setWidth(12)
    widget:setHeight(12)

    if widget.ignoreWaypointCallback then
        return
    end

    hunting_recorderModule.internalSelectWaypoint(widget, widget.waypointIndex, false, true)
end

function hunting_recorderModule.insertWaypointOnPos(waypointPosition, isTeleport)
    local cSession = hunting_recorderModule.getSessionSettings()
    if cSession['waypoints'] == nil then
        cSession['waypoints'] = {}
    end

    local list = {}
    for _, waypoint in pairs(cSession['waypoints']) do
        table.insert(list, waypoint)
    end
    local newIndex = #list + 1

    if huntingWaypointsWindow ~= nil then
--[[
        local lastNode = getLastNode()
        if lastNode ~= nil and #list <= 5 then
            local path = g_map.findPath(lastNode.tilePosition, waypointPosition, 200, 0, true)
            if path ~= nil and #path > 0 then
                local currentPos = { x = lastNode.tilePosition.x, y = lastNode.tilePosition.y, z = lastNode.tilePosition.z }
                local ignoreNext = false
                for _, dir in ipairs(path) do
                    if dir == 0 then
                        currentPos.y = currentPos.y - 1
                    elseif dir == 1 then
                        currentPos.x = currentPos.x + 1
                    elseif dir == 2 then
                        currentPos.y = currentPos.y + 1
                    elseif dir == 3 then
                        currentPos.x = currentPos.x - 1
                    elseif dir == 4 then
                        currentPos.y = currentPos.y - 1
                        currentPos.x = currentPos.x + 1
                    elseif dir == 5 then
                        currentPos.x = currentPos.x + 1
                        currentPos.y = currentPos.y + 1
                    elseif dir == 6 then
                        currentPos.x = currentPos.x - 1
                        currentPos.y = currentPos.y + 1
                    elseif dir == 7 then
                        currentPos.x = currentPos.x - 1
                        currentPos.y = currentPos.y - 1
                    end
                    if not ignoreNext then
                        ignoreNext = true
                        local connector = createNode('connector', { x = currentPos.x, y = currentPos.y, z = currentPos.z })
                        huntingWaypointsWindow.map.minimap:addAlternativeWidget(connector, { x = currentPos.x, y = currentPos.y, z = currentPos.z })
                        huntingWaypointsWindow.map.minimap:internalRegisterAlternative(connector)
                    else
                        ignoreNext = false
                    end
                end
                lastNode:raise()
            end
        end
]]--

        local nodeWidget = createNode(isTeleport and 'teleport' or 'walk', waypointPosition)
        nodeWidget.waypointIndex = newIndex
        huntingWaypointsWindow.map.minimap:addAlternativeWidget(nodeWidget, waypointPosition)
        huntingWaypointsWindow.map.minimap:internalRegisterAlternative(nodeWidget)

        hunting_recorderModule.createBrandNewSessionWaypoint(waypointPosition, false, newIndex)
    end


    hunting_recorderModule.lastPosition = waypointPosition

    local waypoint = {}
    waypoint['position'] = {}
    waypoint['position']['x'] = waypointPosition.x
    waypoint['position']['y'] = waypointPosition.y
    waypoint['position']['z'] = waypointPosition.z
    waypoint['creatures'] = 0
    waypoint['resume'] = 0
    waypoint['lure'] = false
    waypoint['speed'] = 5
    waypoint['teleport'] = isTeleport
    waypoint['index'] = newIndex
    table.insert(list, waypoint)

    cSession['waypoints'] = list
    hunting_recorderModule.setSessionSettings(cSession)

    local point = {
        position = { x = waypoint['position']['x'], y = waypoint['position']['y'], z = waypoint['position']['z'] },
        creatures = waypoint['creatures'],
        resume = waypoint['resume'],
        lure = waypoint['lure'],
        speed = waypoint['speed'],
        index = waypoint['index'],
        teleport = waypoint['teleport']
    }

    g_minibot.registerWalkWaypoint(point)
end

function hunting_recorderModule.cycleRecord()
    if hunting_recorderModule.recordingEvent ~= nil then
        removeEvent(hunting_recorderModule.recordingEvent)
        hunting_recorderModule.recordingEvent = nil
    end

    if not widgetAlive(huntingWaypointsWindow) then
        return
    end

    local player = g_game.getLocalPlayer()
    if player == nil then
        return
    end

    local distance = nil
    if hunting_recorderModule.lastPosition ~= nil then
        distance = getDistanceBetween(hunting_recorderModule.lastPosition, player:getPosition())
    end

    if distance == nil then
        -- Change floor
        hunting_recorderModule.recordingEvent = scheduleEvent(hunting_recorderModule.cycleRecord, 2000)
        return
    end

    if distance <= 3 then
        hunting_recorderModule.recordingEvent = scheduleEvent(hunting_recorderModule.cycleRecord, 2000)
        return
    end

    hunting_recorderModule.insertWaypointOnPos(player:getPosition(), false)

    hunting_recorderModule.recordingEvent = scheduleEvent(hunting_recorderModule.cycleRecord, 2000)
end

function hunting_recorderModule.onRecordingChange(widget)
    if not(widget:isChecked()) then
        if hunting_recorderModule.recordingEvent ~= nil then
            removeEvent(hunting_recorderModule.recordingEvent)
            hunting_recorderModule.recordingEvent = nil
        end

        return
    end

    local player = g_game.getLocalPlayer()
    if player == nil then
        if hunting_recorderModule.recordingEvent ~= nil then
            removeEvent(hunting_recorderModule.recordingEvent)
            hunting_recorderModule.recordingEvent = nil
        end

        return
    end

    hunting_recorderModule.lastPosition = player:getPosition()
    hunting_recorderModule.recordingEvent = scheduleEvent(hunting_recorderModule.cycleRecord, 2000)
end

function hunting_recorderModule.onSelectSettingsTab(widget)
    if widget:getId() == 'node' then
        huntingWaypointsWindow.settings.tab.waypoints:setEnabled(true)
        huntingWaypointsWindow.settings.tab.node:setEnabled(false)
    elseif widget:getId() == 'waypoints' then
        huntingWaypointsWindow.settings.tab.waypoints:setEnabled(false)
        huntingWaypointsWindow.settings.tab.node:setEnabled(true)
    end

    if not(huntingWaypointsWindow.settings.tab.waypoints:isEnabled()) then
        huntingWaypointsWindow.settings.main.noNodeSelected:hide()
        huntingWaypointsWindow.settings.main.selected:hide()
        huntingWaypointsWindow.settings.main.waypoints:show()
    elseif not(huntingWaypointsWindow.settings.tab.node:isEnabled()) then
        huntingWaypointsWindow.settings.main.noNodeSelected:hide()
        huntingWaypointsWindow.settings.main.selected:hide()
        huntingWaypointsWindow.settings.main.waypoints:hide()

        local selectedIndex = nil
        for _, c in ipairs(huntingWaypointsWindow.settings.main.waypoints.list:getChildren()) do
            if c.selectedWaypoint then
                selectedIndex = c.waypointIndex
                break
            end
        end

        if selectedIndex == nil then
            huntingWaypointsWindow.settings.main.noNodeSelected:show()
            return
        end

        huntingWaypointsWindow.settings.main.selected:show()
    end
end
