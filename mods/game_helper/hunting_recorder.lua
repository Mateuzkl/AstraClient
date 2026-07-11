hunting_recorderModule = {}
local playerDir = nil
local DEFAULT_WALK_DELAY = 50
local lastCavebotResumeAttempt = 0

-- Minimap zoom level tracking (declared early for use in setupMinimap)
local minimapZoomLevel = 2 -- Default zoom level
local minimapMinZoom = 0
local minimapMaxZoom = 6

-- Minimap drag state tracking
local minimapDragging = false
local minimapDragStartPos = nil
local minimapDragStartCamera = nil

-- Session death counter
local sessionDeathCount = 0
local playerWasAlive = true  -- Track if player was alive (to detect death transition)
local deathLimitBlocked = false  -- Flag to block cavebot when death limit reached

-- Gold balance session tracking
local cavebotGoldInitial = 0            -- Gold when session started
local cavebotGoldAccumTime = 0          -- Accumulated seconds with cavebot ON
local cavebotGoldLastOnTime = nil       -- os.time() when cavebot was last turned ON
local cavebotGoldRefreshEvent = nil     -- Cycle event for requesting balance from server

-- Death detection and cavebot disable functions
function hunting_recorderModule.resetDeathCount()
    sessionDeathCount = 0
    playerWasAlive = true
    -- Clear any stale death-pause flag so a re-started walker isn't left thinking
    -- it's still frozen from a previous death (server opcode 208 handshake).
    hunting_recorderModule._deathPaused = false
end

function hunting_recorderModule.getDeathCount()
    return sessionDeathCount
end

function hunting_recorderModule.isDeathLimitBlocked()
    return deathLimitBlocked
end

function hunting_recorderModule.clearDeathLimitBlock()
    deathLimitBlocked = false
    sessionDeathCount = 0
    playerWasAlive = true
    
    -- Hide the block notification
    if modules.game_notifications and modules.game_notifications.hideTemporaryMessage then
        modules.game_notifications.hideTemporaryMessage()
    end
end

-- Show death limit warning on screen (using game_notifications)
function hunting_recorderModule.showDeathLimitWarning(deaths, limit)
    if modules.game_notifications and modules.game_notifications.showTemporaryMessage then
        local message = string.format("CAVEBOT BLOCKED: %d deaths (limit: %d). Turn OFF and ON to reset.", deaths, limit)
        modules.game_notifications.showTemporaryMessage(message, 15000) -- 15 seconds
    end
end

-- ============================================================================
-- GOLD BALANCE SESSION TRACKING
-- ============================================================================

-- Get total player gold (bank + inventory) using getResourceBalance like prey system
function hunting_recorderModule.getPlayerTotalGold()
    local player = g_game.getLocalPlayer()
    if not player then return 0 end

    if not player.getResourceValue or type(player.getResourceValue) ~= "function" then
        return 0
    end

    local bankGold = player:getResourceValue(0) or 0
    local backpackGold = player:getResourceValue(1) or 0

    return bankGold + backpackGold
end

-- Capture current gold as the session's initial balance
function hunting_recorderModule.captureInitialGoldBalance()
    cavebotGoldInitial = hunting_recorderModule.getPlayerTotalGold()
    cavebotGoldAccumTime = 0
    cavebotGoldLastOnTime = nil
end

-- Get elapsed seconds counting only time with cavebot ON
function hunting_recorderModule.getGoldSessionElapsed()
    local total = cavebotGoldAccumTime
    if cavebotGoldLastOnTime then
        total = total + (os.time() - cavebotGoldLastOnTime)
    end
    return total
end

-- Reset the gold balance session (recapture initial gold)
function hunting_recorderModule.resetGoldBalanceSession()
    if g_game.sendResourceBalance then
        pcall(g_game.sendResourceBalance)
    end
    scheduleEvent(function()
        hunting_recorderModule.captureInitialGoldBalance()
        modules.game_textmessage.displayGameMessage("Gold session reset.")
    end, 500)
end

-- Format gold value with k/kk suffix and sign (negative only gets -)
local function formatGoldBalance(value)
    local sign = ""
    if value < 0 then sign = "-" end

    local absVal = math.abs(value)
    local formatted
    if absVal >= 1000000 then
        formatted = string.format("%.2fkk", absVal / 1000000)
    elseif absVal >= 1000 then
        formatted = string.format("%.1fk", absVal / 1000)
    else
        formatted = tostring(absVal)
    end

    return sign .. formatted
end

-- Start periodic server balance refresh (every 10s)
function hunting_recorderModule.startGoldBalanceRefresh()
    hunting_recorderModule.stopGoldBalanceRefresh()
    -- Request immediately
    if g_game.sendResourceBalance then
        pcall(g_game.sendResourceBalance)
    end
    cavebotGoldRefreshEvent = cycleEvent(function()
        if g_game.isOnline() and g_game.sendResourceBalance then
            pcall(g_game.sendResourceBalance)
        end
    end, 10000)
end

-- Stop periodic server balance refresh
function hunting_recorderModule.stopGoldBalanceRefresh()
    if cavebotGoldRefreshEvent then
        removeEvent(cavebotGoldRefreshEvent)
        cavebotGoldRefreshEvent = nil
    end
end

-- Update the profit label widget (called from debug popup update cycle)
function hunting_recorderModule.updateProfitLabel(label)
    if not label then return end

    local currentGold = hunting_recorderModule.getPlayerTotalGold()
    local balance = currentGold - cavebotGoldInitial

    -- Calculate profit per hour (only counting cavebot ON time)
    local elapsed = hunting_recorderModule.getGoldSessionElapsed()
    local perHour = 0
    if elapsed > 0 then
        perHour = math.floor(balance * 3600 / elapsed)
    end

    label:setText("Profit: " .. formatGoldBalance(balance) .. " [" .. formatGoldBalance(perHour) .. "/h]")

    -- Color: green for profit, red for loss, gray for zero
    if balance > 0 then
        label:setColor("#00FF00")
    elseif balance < 0 then
        label:setColor("#FF4444")
    else
        label:setColor("#C0C0C0")
    end
end

-- Called when health changes - handles death detection (death counter only; the
-- cavebot death/respawn handshake is driven by the server via extended opcode 208,
-- see onDeathSignal / onRespawnSignal).
function hunting_recorderModule.onHealthChange(health)
    if health == 0 then
        -- Player died
        if playerWasAlive then
            playerWasAlive = false
            hunting_recorderModule.onPlayerDeath()
            -- Fail-safe REAL: congela o walker no HP==0 tambem, nao so via opcode
            -- 208 "0" do servidor. Sem isto, se o opcode nao chegar (server sem o
            -- script cavebot_death_otc_bridge / nao recarregado), _deathPaused fica
            -- false e onRespawnSignal abaixo da early-return, nunca aplicando o
            -- "goto label on death". Idempotente com onDeathSignal do opcode
            -- (guarda _deathPaused + checa CaveBot.isOn).
            hunting_recorderModule.onDeathSignal()
        end
    else
        -- Player is alive (respawned or just alive)
        if not playerWasAlive then
            -- Respawn transition. Fail-safe for the server handshake: if the revive
            -- opcode (208) never arrives, HP going back >0 (which only happens after
            -- the death window's "Ok" -> processPendingGame, i.e. already back in the
            -- temple) still resumes the walker and applies "goto label on death".
            -- Idempotent: no-op if the opcode already resumed it.
            hunting_recorderModule.onRespawnSignal()
        end
        playerWasAlive = true
    end
end

-- Cavebot death gate driven by the server death handshake (extended opcode 208),
-- with the HP-based fail-safe above. Only the cavebot walker is paused;
-- targeting/shooter keep running (they already hold fire in the temple PZ). The
-- paused flag lives on the module table to avoid adding a top-level upvalue.

-- Server signalled the player DIED: freeze the walker in place so its index does
-- not advance while the death window is up (otherwise the label we want to resume
-- from gets stepped past before the player even respawns).
function hunting_recorderModule.onDeathSignal()
    -- Acessa CaveBot SEM o prefixo _G. -- no ambiente deste modulo _G.CaveBot e nil
    -- (o _G do modulo nao e a tabela global onde o core registra CaveBot), mas o
    -- acesso direto resolve via o environment do modulo (mesmo padrao de
    -- cavebotWalker/CaveBot.WaypointHud usados no resto do arquivo). O codigo de
    -- morte original usava _G.CaveBot, por isso nunca funcionava.
    local running = hunting_recorderModule.walking == true
    if not running then
        hunting_recorderModule._deathPaused = false
        return
    end
    if hunting_recorderModule._deathPaused then return end
    hunting_recorderModule._deathPaused = true
    if CaveBot and CaveBot.pause then CaveBot.pause() end
end

-- Server confirmed the RESPAWN (player back alive in the temple): resume the
-- walker and, if configured, jump to the "goto label on death" label so the run
-- restarts from there instead of trekking back from where the player died.
function hunting_recorderModule.onRespawnSignal()
    if not hunting_recorderModule._deathPaused then return end
    hunting_recorderModule._deathPaused = false
    if not hunting_recorderModule.walking then return end

    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    local label = cavebotData and cavebotData.config and cavebotData.config.gotoLabelOnDeath

    -- Auto Blesser gate: if the Auto Blesser is holding the automation frozen (we
    -- respawned unblessed), do NOT resume the walker here -- the blesser resumes it
    -- only once we are blessed again. We still ensure the engine is ON and apply the
    -- "goto label on death" below so the index is repositioned; it just stays paused.
    local blesserFreezing = modules.game_helper
        and modules.game_helper.isAutoBlesserFreezing
        and modules.game_helper.isAutoBlesserFreezing()

    -- Acessa CaveBot SEM _G. (ver nota em onDeathSignal). Garante o motor rodando:
    -- se ele estava off, religa preservando o actionList (setOff nao limpa a lista);
    -- senao apenas despausa. Assim o gotoLabel abaixo tem um motor para processar
    -- o novo indice.
    if CaveBot then
        if CaveBot.isOn and not CaveBot.isOn() and CaveBot.setOn then
            CaveBot.setOn()
            -- setOn clears the paused flag; keep it paused if the blesser is freezing.
            if blesserFreezing and CaveBot.pause then CaveBot.pause() end
        elseif blesserFreezing then
            if CaveBot.pause then CaveBot.pause() end
        elseif CaveBot.resume then
            CaveBot.resume()
        end
    end

    -- Reancoragem pos-respawn. Sem isto, o walker retoma com o indice apontando pro
    -- meio da hunt (outro Z) e o Z-recovery tenta "corrigir" a partir do templo ->
    -- sobe/desce a escada errada e sai do PZ (as vezes ainda sem bless). Precedencia:
    --   1) "Goto label on death" configurado E encontrado -> salta pro label (preciso).
    --   2) Sem label OU label inexistente na lista -> reancora no waypoint alcancavel
    --      mais proximo no Z do respawn (fallback automatico).
    --   3) Sem ancora possivel nesse Z -> DESLIGA o walker (preserva a actionList) e
    --      avisa. Um pause() puro seria revertido pelo autoBlesserReleaseFreeze (que so
    --      faz resume/isPaused) e o indice voltaria stale; setOff (isEnabled=false) nao.
    local reanchored = false
    if label and label ~= "" and CaveBot and CaveBot.gotoLabel then
        reanchored = CaveBot.gotoLabel(label)
        if reanchored then
            print(string.format("[Cavebot] Respawn: pulou para a label '%s'", label))
        else
            print(string.format("[Cavebot] Respawn: label '%s' nao encontrada -> fallback reancoragem", label))
        end
    end

    if not reanchored and CaveBot then
        local lp = g_game.getLocalPlayer()
        local pos = lp and lp.getPosition and lp:getPosition()
        if pos and CaveBot.reanchorToReachableWaypoint and CaveBot.reanchorToReachableWaypoint(pos) then
            print("[Cavebot] Respawn: reancorou no waypoint alcancavel mais proximo no Z atual")
        else
            -- Sem ancora no Z do respawn (rota sem waypoint neste andar): desliga o walker
            -- em vez de deixar o Z-recovery agir a partir do templo. setOff preserva a
            -- actionList; o jogador reposiciona/configura o label e religa.
            if CaveBot.setOff then pcall(CaveBot.setOff) end
            print("[Cavebot] Respawn: nenhum waypoint alcancavel no Z atual -> walker DESLIGADO; configure 'Goto label on death'")
            -- Aviso visivel ao jogador. NAO usar modules.game_notifications: esse modulo nao
            -- existe no client, entao o guard falhava silencioso e o walker desligava sem aviso.
            -- Modal com fallback pra mensagem de tela -- mesmo padrao do autoBlesserNoGoldAlert.
            local warnMsg = "CAVEBOT desligado: sem waypoint no andar do templo apos a morte.\nConfigure 'Goto label on death' e religue o cavebot."
            if displayInfoBox then
                pcall(displayInfoBox, "Cavebot", warnMsg)
            elseif modules and modules.game_textmessage and modules.game_textmessage.displayGameMessage then
                pcall(modules.game_textmessage.displayGameMessage, warnMsg)
            end
        end
    end
end

function hunting_recorderModule.onPlayerDeath()
    -- Only count deaths when the cavebot is actively running
    if not hunting_recorderModule.walking then
        return
    end

    sessionDeathCount = sessionDeathCount + 1

    print(string.format("[Cavebot] Death detected! Count: %d", sessionDeathCount))

    -- Get current cavebot config
    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData or not cavebotData.config then
        print("[Cavebot] No cavebot data found")
        return
    end

    local deathsToDisable = cavebotData.config.deathsToDisable or 0

    print(string.format("[Cavebot] Deaths: %d, Limit: %d", sessionDeathCount, deathsToDisable))

    -- If deathsToDisable is 0, feature is disabled
    if deathsToDisable == 0 then
        return
    end

    -- Check if we reached the death limit
    if sessionDeathCount >= deathsToDisable then
        -- Set block flag FIRST
        deathLimitBlocked = true

        -- Stop the cavebot
        if hunting_recorderModule.stopWalk then
            hunting_recorderModule.stopWalk()
        end

        -- Log the event
        print(string.format("[Cavebot] BLOCKED after %d death(s) (limit: %d)", sessionDeathCount, deathsToDisable))

        -- Reflect OFF in config + checkboxes too (nao so o motor), senao a UI fica
        -- marcada "ligado" apos o bloqueio por mortes (estado ambiguo).
        hunting_recorderModule.markCavebotDisabled()

        -- Show warning on screen
        hunting_recorderModule.showDeathLimitWarning(sessionDeathCount, deathsToDisable)
    else
        -- Inform user about death count
        if modules.game_textmessage and modules.game_textmessage.displayGameMessage then
            modules.game_textmessage.displayGameMessage(string.format("Death %d/%d - Cavebot will disable at %d deaths", sessionDeathCount, deathsToDisable, deathsToDisable))
        end
    end
end

-- Initialize widget with basic functionality if needed
local function initializeWidget(widget)
    if widget then
        -- Basic initialization that might be needed
        widget._initialized = true
    end
end

-- Helper functions to safely access modules.game_helper
local function safeGetSettingsValue(_, key, default)
    if not modules.game_helper or not modules.game_helper.getSettingsValue then
        return default
    end
    return modules.game_helper.getSettingsValue(_, key, default)
end

local function safeSetSettingsValue(_, key, value)
    if modules.game_helper and modules.game_helper.setSettingsValue then
        modules.game_helper.setSettingsValue(_, key, value)
    end
end

-- Waypoint type conversion functions (support both string and integer for backwards compatibility)
local function waypointTypeToString(wpType)
    local typeMap = {
        [0] = "node",
        [1] = "stand",
        [2] = "use",
        [3] = "rope",
        [4] = "hole",
        [5] = "lever",
        [90] = "special",
        [98] = "goto",
        [99] = "label"
    }

    local typeSet = {
        node = true,
        stand = true,
        use = true,
        rope = true,
        hole = true,
        lever = true,
        special = true,
        goto = true,
        label = true,
        buy_refill = true,
        stop_to_kill = true,
        wait_delay = true,
        deposit = true,
        bank = true,
        travel = true,
        door = true,
        levitate = true,
        stop_cavebot = true,
        start_lure = true,
        stop_lure = true,
        script = true
    }

    if type(wpType) == "string" then
        local trimmed = wpType:match("^%s*(.-)%s*$")
        local lowered = trimmed:lower()
        -- Preserve special action types
        if lowered == "buy_refill" or lowered == "stop_to_kill" or
           lowered == "wait_delay" or lowered == "deposit" or lowered == "bank" or lowered == "travel" or lowered == "door" or
           lowered == "levitate" or lowered == "stop_cavebot" or lowered == "start_lure" or lowered == "stop_lure" then
            return lowered -- Return original string name
        end
        if typeSet[lowered] then
            return lowered
        end
        local numeric = tonumber(lowered)
        if numeric then
            return typeMap[numeric] or "node"
        end
        return "node"
    end

    if type(wpType) == "number" then
        return typeMap[wpType] or "node"
    end

    return "node"
end

local function waypointTypeToNumber(wpType)
    if type(wpType) == "number" then
        return wpType -- Already a number
    end

    if type(wpType) == "string" then
        local trimmed = wpType:match("^%s*(.-)%s*$")
        local lowered = trimmed:lower()
        local numeric = tonumber(lowered)
        if numeric then
            return numeric
        end

        -- Special action waypoints (buy_refill, stop_to_kill, etc) behave as stand
        if lowered == "buy_refill" or lowered == "stop_to_kill" or lowered == "wait_delay" or lowered == "levitate" or lowered == "stop_cavebot" or lowered == "start_lure" or lowered == "stop_lure" or lowered == "script" then
            return 1 -- Stand behavior
        end

        -- Convert string to number (for backwards compatibility)
        local typeMap = {
            ['node'] = 0,
            ['stand'] = 1,
            ['use'] = 2,
            ['rope'] = 3,
            ['hole'] = 4,
            ['lever'] = 5,
            ['special'] = 90,
            ['goto'] = 98,
            ['label'] = 99
        }
        return typeMap[lowered] or 0
    end

    return 0
end

-- Get waypoint type name for display (returns string name for special action types)
local function waypointTypeToName(wpType)
    -- Check if it's a special action type (string)
    if type(wpType) == "string" then
        local trimmed = wpType:match("^%s*(.-)%s*$")
        local lowered = trimmed:lower()
        if lowered == "buy_refill" then
            return "BUY REFILL"
        elseif lowered == "stop_to_kill" then
            return "STOP TO KILL"
        elseif lowered == "wait_delay" then
            return "WAIT DELAY"
        elseif lowered == "levitate" then
            return "LEVITATE"
        elseif lowered == "stop_cavebot" then
            return "STOP CAVEBOT"
        elseif lowered == "start_lure" then
            return "START LURE"
        elseif lowered == "stop_lure" then
            return "STOP LURE"
        elseif lowered == "door" then
            return "DOOR"
        elseif lowered == "script" then
            return "SCRIPT"
        end
    end

    -- For other types, convert to number and get standard name
    local wpTypeNum = waypointTypeToNumber(wpType)
    if wpTypeNum == 1 then
        return "Stand"
    elseif wpTypeNum == 2 then
        return "Use"
    elseif wpTypeNum == 3 then
        return "Rope"
    elseif wpTypeNum == 4 then
        return "Hole"
    elseif wpTypeNum == 5 then
        return "Lever"
    elseif wpTypeNum == 90 then
        return "Special"
    elseif wpTypeNum == 98 then
        return "Goto"
    elseif wpTypeNum == 99 then
        return "Label"
    else
        return "Node"
    end
end

-- Map special action waypoint types to a distinct minimap flag icon
-- Returns the flag icon number, or nil if the waypoint is not a special action
local function getSpecialActionFlagIcon(wpType)
    if type(wpType) ~= "string" then return nil end
    local lowered = wpType:match("^%s*(.-)%s*$"):lower()
    if lowered == "stop_to_kill" then
        return 2  -- red flag
    elseif lowered == "buy_refill" then
        return 3  -- orange flag (buy/sell)
    elseif lowered == "stop_cavebot" then
        return 2  -- red flag (stop)
    elseif lowered == "door" then
        return 11 -- brown flag (door)
    end
    return nil
end

Keybind.new("Helper", "Enable/Disable Cavebot Helper", "", "")
    Keybind.bind("Helper", "Enable/Disable Cavebot Helper", {
	{ type = KEY_DOWN, callback = function() modules.game_helper.toggleCavebotHelper() end }
})

function hunting_recorderModule.ensureDirectories()
    local player = g_game.getLocalPlayer()
    if not player then
		return nil
	end

    local playerName = player:getName()
    local baseDir = string.format("/characterdata/%s/hunting_sessions/", playerName)

    if not g_resources.directoryExists("/characterdata/") then
        g_resources.makeDir("/characterdata/")
    end

    local playerDir = string.format("/characterdata/%s/", playerName)
    if not g_resources.directoryExists(playerDir) then
        g_resources.makeDir(playerDir)
    end

    if not g_resources.directoryExists(baseDir) then
        g_resources.makeDir(baseDir)
    end

    return baseDir
end

local function getSessionFile(uid)
    local player = g_game.getLocalPlayer()
    if not player then
        return nil
    end
    local playerName = player:getName()
    return string.format("/characterdata/%s/hunting_sessions/session_%d.json", playerName, uid)
end

function hunting_recorderModule.saveSessionToDisk(uid, data, force)
    if not force then
        return
    end

    local filePath = getSessionFile(uid)
    if not filePath then
        return
    end

    -- Debug: Log waypoints before encoding
    if data and data.waypoints then
        for i, wp in ipairs(data.waypoints) do
            if waypointTypeToNumber(wp.type) == 98 then
                g_logger.info(string.format("[SaveDebug] GOTO waypoint #%d: label=%s, condition=%s, stamina=%s",
                    i, tostring(wp.label), tostring(wp.gotoCondition), tostring(wp.gotoStamina)))
            end
        end
    end

    local status, encoded = pcall(function() return json.encode(data or {}, 2) end)
    if not status then
        return
    end

    if encoded:len() > 100 * 1024 * 1024 then
        return
    end

    local playerName = g_game.getLocalPlayer():getName()
    local baseDir = string.format("/characterdata/%s/hunting_sessions/", playerName)
    if not g_resources.directoryExists(baseDir) then
        g_resources.makeDir(baseDir)
    end

    g_resources.writeFileContents(filePath, encoded)
end

function hunting_recorderModule.loadSessionFromDisk(uid)
    local filePath = getSessionFile(uid)
    if not filePath or not g_resources.fileExists(filePath) then
        return nil
    end

    local status, contents = pcall(function() return g_resources.readFileContents(filePath) end)
    if not status or not contents or contents == "" then
        return nil
    end

    local ok, data = pcall(function() return json.decode(contents) end)
    if not ok or type(data) ~= "table" then
        return nil
    end
    return data
end

local huntingWaypointsWindow = nil
local cavebotSettingsWindow = nil
local lureSettingsWindow = nil
local editSessionWindow = nil
local waypointCreatorWindow = nil
local suppliesPopup = nil
local creatorWaypointType = 0 -- 0 = node, 1 = stand
local creatorDirection = nil -- nil = center (current pos), 0-7 = directions
local creatorMode = 'add' -- 'replace', 'add', 'insert'
local virtualFloor = 7
local ensureSpecialAreasTable
local function focusGamePanel()
    if modules.game_interface and modules.game_interface.getRootPanel then
        local root = modules.game_interface.getRootPanel()
        if root then
            root:focus()
        end
    end
end

local function getDistanceBetween(p1, p2)
    if p1.z ~= p2.z then
        return nil
    end

    return math.max(math.abs(p1.x - p2.x), math.abs(p1.y - p2.y))
end

-- Helper function to clear minimap waypoints while preserving player cross
local function clearMinimapWaypoints(minimap)
    if not minimap then
        return
    end

    -- Salvar a posição do player e referência do cross antes de limpar
    local playerPos = nil
    local player = g_game.getLocalPlayer()
    if player then
        playerPos = player:getPosition()
    end

    -- Salvar referência do cross e limpar alternatives ANTES de mexer nos children
    local crossWidget = minimap.cross

    -- clearAlternatives pode remover os waypoints sem destruir o cross
    if minimap.clearAlternatives then
        minimap:clearAlternatives()
    end

    local children = minimap:getChildren()
    if children then
        local totalChildren = #children
        local destroyedCount = 0

        for i, child in ipairs(children) do
            if child and not child:isDestroyed() then
                -- Não destruir o cross (ícone do jogador)
                local isCross = child == crossWidget or
                               (child.getId and child:getId() == 'cross') or
                               (child.getClassName and child:getClassName() == 'UIMinimapCross')

                -- MUDANÇA: Destruir TODOS os widgets que não sejam o cross
                -- Isso garante que waypoints, connectors e qualquer outro widget seja removido
                if not isCross then
                    local widgetInfo = string.format("id=%s class=%s keyType=%s",
                        child.getId and child:getId() or "nil",
                        child.getClassName and child:getClassName() or "nil",
                        tostring(child.keyType))
                    child:destroy()
                    destroyedCount = destroyedCount + 1
                end
            end
        end
    end

    -- Garantir que o cross ainda existe e restaurar a posição do player
    if playerPos then
        if minimap.setCrossPosition then
            minimap:setCrossPosition(playerPos)
        end
    end
end

local function createNode(key, position)
    local widget = g_ui.createWidget('UIWidget', huntingWaypointsWindow.map.minimap)
    widget.tilePosition = position
    widget:setWidth(10)
    widget:setHeight(10)
    widget:setBackgroundColor('#FFCC00')
    widget:show()
    widget.keyType = key

    -- Set zoom properties to avoid errors in uiminimap.lua
    widget.minZoom = 0
    widget.maxZoom = 999

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
    widget.onMouseRelease = function(_, pos, button)
        local mapPos = huntingWaypointsWindow.map.minimap:getTilePosition(pos)
        if not mapPos then
            return
        end

        if button == MouseLeftButton then
            hunting_recorderModule.onClickWaypointOnMap(widget)
        elseif button == MouseRightButton then
            local menu = g_ui.createWidget('HelperPopupMenu')
            menu:setGameMenu(true)
            menu:addOption('Remove node', function()
                local cSession = hunting_recorderModule.getSessionSettings()
                if cSession['waypoints'] == nil then
                    cSession['waypoints'] = {}
                end

                local list = {}
                for _, waypoint in pairs(cSession['waypoints']) do
                    if waypoint['index'] ~= widget.waypointIndex then
                        table.insert(list, waypoint)
                    end
                end

                table.sort(list, function(a, b)
                    return a['index'] < b['index']
                end)
                for index, c in ipairs(list) do
                    c['index'] = index
                end

                cSession['waypoints'] = list
                hunting_recorderModule.setSessionSettings(cSession)
                hunting_recorderModule.saveSessionToDisk(hunting_recorderModule.selectedSessionUid, cSession)
                for _, c in ipairs(huntingWaypointsWindow.sessions.list:getChildren()) do
                    if c.sessionUid == hunting_recorderModule.selectedSessionUid then
                        hunting_recorderModule.selectedSessionUid = nil
                        hunting_recorderModule.onClickSessionEntry(c)
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

local lastWaypointPosition = nil
local lastWaypointType = nil -- Rastreia o ultimo tipo gravado (0 = node, 1 = stand)

local function getLastNode()
    -- Return a fake node object with the last waypoint position for connector drawing
    if not lastWaypointPosition then
        return nil
    end

    return {
        tilePosition = lastWaypointPosition
    }
end

function hunting_recorderModule.init(widget)
    huntingWaypointsWindow = widget

    huntingWaypointsWindow.settings.main.waypoints:show()
    
    -- Initialize tabs visual state
    scheduleEvent(function()
        hunting_recorderModule.updateTabsVisualState(false)
    end, 100)

    local function setupMinimap(retries)
        retries = retries or 0

        local mapContainer = huntingWaypointsWindow:recursiveGetChildById('map')
        if not mapContainer then
            if retries < 20 then
                scheduleEvent(function() setupMinimap(retries + 1) end, 250)
            end
            return
        end

        local minimap = mapContainer:recursiveGetChildById('minimap')
        if not minimap then
            if retries < 20 then
                scheduleEvent(function() setupMinimap(retries + 1) end, 250)
            end
            return
        end

        huntingWaypointsWindow.map = { minimap = minimap }

        local toggleButton = mapContainer:recursiveGetChildById('enabled')
        if toggleButton then
            huntingWaypointsWindow.map.enabled = toggleButton
        else
            huntingWaypointsWindow.map.enabled = {
                setChecked = function() end,
                isChecked = function() return false end,
                ignoreCallback = true
            }
        end

        minimap:disableAutoWalk()
        minimap:setZoom(2)
        minimapZoomLevel = 2  -- Sync with our tracking variable
        minimap.allowCallback = false
        minimap:show()

        -- Override onMouseRelease to show waypoint creation menu on right-click
        local originalOnMouseRelease = minimap.onMouseRelease
        minimap.onMouseRelease = function(self, pos, button)
            if not self.allowNextRelease then
                return true
            end
            self.allowNextRelease = false

            local mapPos = self:getTilePosition(pos)
            if not mapPos then
                return false
            end

            if button == MouseLeftButton then
                -- Do nothing on left click (disable autowalk for cavebot minimap)
                return true
            elseif button == MouseRightButton then
                -- Block waypoint creation if cavebot is enabled
                if helperConfig and helperConfig.cavebotHelperEnabled then
                    modules.game_textmessage.displayFailureMessage("Cannot create waypoints while cavebot is running. Disable cavebot first.")
                    return true
                end
                -- Show waypoint creation menu instead of default flag menu
                hunting_recorderModule.showWaypointCreationMenu(pos, mapPos)
                return true
            end
            return false
        end

        -- Override onMouseWheel to track zoom level
        local originalOnMouseWheel = minimap.onMouseWheel
        minimap.onMouseWheel = function(self, mousePos, direction)
            local keyboardModifiers = g_keyboard.getModifiers()
            if direction == MouseWheelUp and keyboardModifiers == KeyboardNoModifier then
                self:zoomIn()
                minimapZoomLevel = math.max(minimapMinZoom, minimapZoomLevel - 1)
            elseif direction == MouseWheelDown and keyboardModifiers == KeyboardNoModifier then
                self:zoomOut()
                minimapZoomLevel = math.min(minimapMaxZoom, minimapZoomLevel + 1)
            elseif direction == MouseWheelDown and keyboardModifiers == KeyboardCtrlModifier then
                self:floorUp(1)
                virtualFloor = virtualFloor - 1
                hunting_recorderModule.refreshVirtualFloorsFullMap()
            elseif direction == MouseWheelUp and keyboardModifiers == KeyboardCtrlModifier then
                self:floorDown(1)
                virtualFloor = virtualFloor + 1
                hunting_recorderModule.refreshVirtualFloorsFullMap()
            end
        end

        local player = g_game.getLocalPlayer()
        if player then
            local pos = player:getPosition()
            if pos then
                -- Verificações de segurança antes de definir posições no minimap
                if minimap.setCameraPosition then
                    minimap:setCameraPosition(pos)
                end
                if minimap.setCrossPosition then
                    minimap:setCrossPosition(pos)
                end
                virtualFloor = pos.z
            end
        end

        connect(LocalPlayer, {
            onPositionChange = hunting_recorderModule.onPositionChange
        })
        connect(g_minibot, {
            onWalkToNextNode = hunting_recorderModule.onWalkToNextNode,
            onWalkFailed = hunting_recorderModule.onWalkFailed
        })

        hunting_recorderModule.loadSettings()

        -- Load auto record state
        local buttonsPanel = huntingWaypointsWindow:recursiveGetChildById('buttons')
        if buttonsPanel then
            local autoRecordCheckBox = buttonsPanel:recursiveGetChildById('autoRecordCheckBox')
            if autoRecordCheckBox then
                local autoRecordEnabled = safeGetSettingsValue(false, 'cavebot_auto_record', false)
                autoRecordCheckBox.ignoreCallback = true
                autoRecordCheckBox:setChecked(autoRecordEnabled)
                autoRecordCheckBox.ignoreCallback = nil
            end

            -- Load cavebots list
            hunting_recorderModule.refreshMainCavebotsList()
        end

    end

    setupMinimap(0)
end

function hunting_recorderModule.terminate()
    disconnect(LocalPlayer, {
        onPositionChange = hunting_recorderModule.onPositionChange
    })
    disconnect(g_minibot, {
        onWalkToNextNode = hunting_recorderModule.onWalkToNextNode,
        onWalkFailed = hunting_recorderModule.onWalkFailed
    })

    if huntingWaypointsConfirmationWindow ~= nil then
        huntingWaypointsConfirmationWindow:destroy()
        huntingWaypointsConfirmationWindow = nil
    end

    huntingWaypointsWindow = nil

end

function hunting_recorderModule.getWindow()
    return huntingWaypointsWindow
end

-- Track previously selected widget to avoid iterating all children
local previouslySelectedWidget = nil
-- Lookup table: waypointIndex -> widget (for O(1) widget access)
local waypointWidgetLookup = {}

-- Build/rebuild the lookup table from current list children
function hunting_recorderModule.rebuildWaypointLookup()
    waypointWidgetLookup = {}
    if not huntingWaypointsWindow or not huntingWaypointsWindow.settings then return end
    local list = huntingWaypointsWindow.settings.main.waypoints.list
    if not list then return end
    for _, widget in ipairs(list:getChildren()) do
        if widget.waypointIndex then
            waypointWidgetLookup[widget.waypointIndex] = widget
        end
    end
end

-- Register a single widget in the lookup (called during creation)
function hunting_recorderModule.registerWaypointWidget(index, widget)
    waypointWidgetLookup[index] = widget
end

function hunting_recorderModule.onWalkToNextNode(index)
    hunting_recorderModule.selectedSessionIndex = index
    -- NOTE: updateDebugPos is called separately via onWaypointChanged callback (debounced)
    if not huntingWaypointsWindow or not huntingWaypointsWindow.settings then
        return
    end

    local list = huntingWaypointsWindow.settings.main.waypoints.list
    if not list then
        return
    end

    -- Deselect only the previously selected widget (instead of iterating ALL children)
    if previouslySelectedWidget and not previouslySelectedWidget:isDestroyed() then
        if previouslySelectedWidget.mask then previouslySelectedWidget.mask:hide() end
        previouslySelectedWidget.selectedWaypoint = false
        if previouslySelectedWidget.updateOnStates then
            previouslySelectedWidget:updateOnStates()
        end
    end

    -- O(1) lookup for the target widget
    local widget = waypointWidgetLookup[index]
    if widget and not widget:isDestroyed() then
        if widget.mask then widget.mask:show() end
        widget.selectedWaypoint = true
        widget:focus()
        list:ensureChildVisible(widget)
        previouslySelectedWidget = widget
        hunting_recorderModule.internalSelectWaypoint(widget, index, true, false)
        if widget.updateOnStates then
            widget:updateOnStates()
        end
    else
        -- Fallback: rebuild lookup and search linearly (only if widget not found)
        hunting_recorderModule.rebuildWaypointLookup()
        widget = waypointWidgetLookup[index]
        if widget and not widget:isDestroyed() then
            if widget.mask then widget.mask:show() end
            widget.selectedWaypoint = true
            widget:focus()
            list:ensureChildVisible(widget)
            previouslySelectedWidget = widget
            hunting_recorderModule.internalSelectWaypoint(widget, index, true, false)
            if widget.updateOnStates then
                widget:updateOnStates()
            end
        end
    end
end

function hunting_recorderModule.setPreWalk(position)
    if hunting_recorderModule.recordingEvent == nil then
        return
    end

    hunting_recorderModule.recordingPosition = position
end

function hunting_recorderModule.centerOnPlayer()
    if not huntingWaypointsWindow or not huntingWaypointsWindow.map or not huntingWaypointsWindow.map.minimap then
        return
    end

    local player = g_game.getLocalPlayer()
    if not player then return end

    local pos = player:getPosition()
    if not pos then return end

    local minimap = huntingWaypointsWindow.map.minimap
    if minimap.setCameraPosition then
        minimap:setCameraPosition(pos)
    end
    if minimap.setCrossPosition then
        minimap:setCrossPosition(pos)
    end
end

-- Retorna true se o tile em pos contem um item cujo id e de uma porta ABERTA
-- (consulta CavebotDoors, definido em cavebots/doors_data.lua).
function hunting_recorderModule.tileHasOpenDoor(pos)
    if not pos or not CavebotDoors or not CavebotDoors.isOpen then return false end
    local tile = g_map.getTile(pos)
    if not tile then return false end
    local items = tile:getItems()
    if items then
        for _, item in ipairs(items) do
            if item and item.getId and CavebotDoors.isOpen(item:getId()) then
                return true
            end
        end
    end
    return false
end

function hunting_recorderModule.onPositionChange(creature, newPos, oldPos)
    if not creature or not creature:isLocalPlayer() then
        return
    end

    if not huntingWaypointsWindow or not huntingWaypointsWindow.map or not huntingWaypointsWindow.map.minimap then
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

    if newPos and oldPos then
        local distance = math.max(math.abs(newPos.x - oldPos.x), math.abs(newPos.y - oldPos.y))
        if newPos.z ~= oldPos.z or distance > 10 then
            hunting_recorderModule.resumeCavebotIfNeeded()
        end
    end

    -- Verificações de segurança para o minimap
    if not huntingWaypointsWindow or not huntingWaypointsWindow.map or not huntingWaypointsWindow.map.minimap then
        return
    end

    local minimap = huntingWaypointsWindow.map.minimap
    if minimap.setCameraPosition then
        minimap:setCameraPosition(pos)
    end
    if minimap.setCrossPosition then
        minimap:setCrossPosition(pos)
    end

    if hunting_recorderModule.recordingEvent ~= nil then
        -- AUTO-RECORD DOOR: ao pisar num tile com porta ABERTA, gravar um waypoint
        -- 'door' exatamente ali (independente do limiar de distancia do auto-record).
        -- _lastAutoDoorPos evita gravar varias vezes enquanto parado sobre a porta.
        if newPos and hunting_recorderModule.tileHasOpenDoor(newPos) then
            local prev = hunting_recorderModule._lastAutoDoorPos
            local samePrev = prev and prev.x == newPos.x and prev.y == newPos.y and prev.z == newPos.z
            if not samePrev then
                hunting_recorderModule._lastAutoDoorPos = {x = newPos.x, y = newPos.y, z = newPos.z}
                hunting_recorderModule.insertWaypointOnPos(newPos, false, true)
                hunting_recorderModule.lastPosition = {x = newPos.x, y = newPos.y, z = newPos.z}
            end
        else
            hunting_recorderModule._lastAutoDoorPos = nil
        end

        if newPos and oldPos and (newPos.z ~= oldPos.z or math.max(math.abs(newPos.x - oldPos.x), math.abs(newPos.y - oldPos.y)) > 1) then
            -- Only mark OLD position as teleport (the source)
            hunting_recorderModule.insertWaypointOnPos(oldPos, true, true)
            -- New position (destination) is a normal waypoint
            hunting_recorderModule.insertWaypointOnPos(newPos, false, true)
            -- Reset reference to the node after a stand/teleport
            hunting_recorderModule.lastPosition = {x = newPos.x, y = newPos.y, z = newPos.z}
            hunting_recorderModule.positionHistory = {
                pos1 = {x = newPos.x, y = newPos.y, z = newPos.z},
                pos2 = nil,
                pos3 = nil
            }
            forceNextAsNode = false
        else
            if hunting_recorderModule.lastPosition ~= nil then
                local distance = getDistanceBetween(hunting_recorderModule.lastPosition, pos)
                if distance == nil or distance > 4 then
                    hunting_recorderModule.cycleRecord()
                end
            end
        end
    end

    virtualFloor = pos.z
    hunting_recorderModule.refreshVirtualFloorsFullMap()
    
    -- Update debug POS display when player moves or changes floor (if enabled)
    if newPos and oldPos and (newPos.x ~= oldPos.x or newPos.y ~= oldPos.y or newPos.z ~= oldPos.z) then
        -- Check if debug is enabled before updating
        if huntingWaypointsWindow then
            local buttonsPanel = huntingWaypointsWindow:recursiveGetChildById('buttons')
            if buttonsPanel then
                local debugPosCheckBox = buttonsPanel:recursiveGetChildById('debugPosCheckBox')
                if debugPosCheckBox and debugPosCheckBox:isChecked() then
                    -- Clear and rebuild to handle viewport changes
                    hunting_recorderModule.updateDebugPos()
                end
            end
        end
    end
end

function hunting_recorderModule.resumeCavebotIfNeeded()
    if _G.hotkeyHelperStatus ~= true then
        return
    end

    -- Don't resume if blocked by death limit
    if deathLimitBlocked then
        return
    end

    if not helperConfig or not helperConfig.cavebotHelperEnabled then
        return
    end

    if hunting_recorderModule.recordingEvent ~= nil then
        return
    end

    local walkerActive = cavebotWalker and cavebotWalker.isActive and cavebotWalker.isActive() or false
    if walkerActive then
        -- Walker survived reconnect: offline() only paused it and cleared the walking state.
        -- Resume now that the map/position are settled (this runs ~500ms after onGameStart),
        -- with a fresh reset so the first step recomputes the path from where the player ACTUALLY
        -- is instead of replaying the stale pre-disconnect direction. CaveBot bare (see onDeathSignal).
        if CaveBot then
            if CaveBot.resetWalking then pcall(CaveBot.resetWalking) end
            if CaveBot.resume then pcall(CaveBot.resume) end
        end
        -- Walker survived reconnect but popup was hidden by offline(), re-show it
        _G.cavebotManualStop = false
        scheduleEvent(function()
            if modules.game_helper and modules.game_helper.updateDebugPopupVisibility then
                modules.game_helper.updateDebugPopupVisibility()
            end
        end, 500)
        return
    end

    local now = g_clock.millis()
    if now - (lastCavebotResumeAttempt or 0) < 1500 then
        return
    end
    lastCavebotResumeAttempt = now

    if hunting_recorderModule.walking then
        hunting_recorderModule.stopWalk(true)
    end

    scheduleEvent(function()
        if helperConfig and helperConfig.cavebotHelperEnabled then
            hunting_recorderModule.startWalk()

            -- Force debug popup visibility after reconnect to ensure overlay reappears
            scheduleEvent(function()
                hunting_recorderModule.updateDebugPos()
                if modules.game_helper and modules.game_helper.updateDebugPopupVisibility then
                    modules.game_helper.updateDebugPopupVisibility()
                end
            end, 500)
        end
    end, 200)
end

function hunting_recorderModule.loadSessionList()
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local baseDir = hunting_recorderModule.ensureDirectories()
    if not baseDir then
        return
    end

    local sSessions = safeGetSettingsValue(false, 'sessions', {}) or {}
    local sSettings = safeGetSettingsValue(false, 'sessions_settings', {}) or {}

    local files = g_resources.listDirectoryFiles(baseDir)
    if files then
        for _, fileName in ipairs(files) do
            local uid = fileName:match("session_(%d+)%.json$")
            if uid then
                uid = tonumber(uid)
                local data = hunting_recorderModule.loadSessionFromDisk(uid)
                if data then
                    if not sSessions[tostring(uid)] then
                        sSessions[tostring(uid)] = { name = data.name or ("Session " .. uid), uid = uid }
                    end
                    sSettings[tostring(uid)] = data
                end
            end
        end
    end

    safeSetSettingsValue(false, 'sessions', sSessions)
    safeSetSettingsValue(false, 'sessions_settings', sSettings)

    if not huntingWaypointsWindow or not huntingWaypointsWindow.sessions then
        return
    end

    local list = huntingWaypointsWindow.sessions.list
    list:destroyChildren()

    local sorted = {}
    for _, entry in pairs(sSessions) do
        table.insert(sorted, entry)
    end
    table.sort(sorted, function(a, b) return a.uid < b.uid end)

    for _, entry in ipairs(sorted) do
        hunting_recorderModule.createSessionWidget(entry)
    end
end

-- Lure speed is fixed at 5 (moderate) - no UI control needed
-- Lure mode is just ON/OFF via checkbox

function hunting_recorderModule.reloadEnabledShortcut(_, widget)
    if widget:getId() ~= 'huntingRecorder_gamewindow' then
        return
    end

    huntingWaypointsWindow.map.enabled.ignoreCallback = true
    huntingWaypointsWindow.map.enabled:setChecked(widget:isChecked())
    huntingWaypointsWindow.map.enabled.ignoreCallback = nil
end

function hunting_recorderModule.onWalkFailed(code)
    if code == 0 then
        if huntingWaypointsWindow ~= nil then
            huntingWaypointsWindow.map.enabled:setChecked(false)
        else
            modules.game_helper.onMiniBotGameWindowChangeFromPanel('huntingRecorder_gamewindow', false)
        end
    end
end

function hunting_recorderModule.EnableCavebotReal(value)
    if not huntingWaypointsWindow then
        return
    end

    -- Botões internos
    local btn = huntingWaypointsWindow.map and huntingWaypointsWindow.map.enabled
    local caveToggle = huntingWaypointsWindow:recursiveGetChildById("enableCaveBot")

    -- Handle death limit block - user manually enables to clear block and reset counter
    if deathLimitBlocked and value == 1 then
        hunting_recorderModule.clearDeathLimitBlock()
        print("[Cavebot] Death limit block cleared - user manually re-enabled cavebot")
    end

    -- Proibir ligar em expedition, dungeon ou vortex (Area Info)
    if value == 1 and modules.game_helper and modules.game_helper.isInsideRestrictedArea and modules.game_helper.isInsideRestrictedArea() then
        modules.game_textmessage.displayFailureMessage("Cavebot not allowed in expedition, dungeon or vortex.")
        if btn then
            btn.ignoreCallback = true
            btn:setChecked(false)
            btn.ignoreCallback = nil
        end
        if caveToggle then
            caveToggle.ignoreCallback = true
            caveToggle:setChecked(false)
            caveToggle.ignoreCallback = nil
        end
        return
    end

    -- Cavebot atual e waypoints
    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    local waypoints = cavebotData and cavebotData.waypoints or {}
    
    -- Contar waypoints corretamente (pode ser tabela com indices nao sequenciais)
    local waypointCount = 0
    if waypoints then
        for _ in pairs(waypoints) do
            waypointCount = waypointCount + 1
        end
    end

    if value == 1 then
        if not cavebotData or not waypoints or waypointCount < 2 then
            modules.game_textmessage.displayFailureMessage("Cavebot Helper cannot be enabled, no valid cavebot with 2+ waypoints.")
            if btn then
                btn.ignoreCallback = true
                btn:setChecked(false)
                btn.ignoreCallback = nil
            end
            if caveToggle then
                caveToggle:setChecked(false)
            end
            return
        end

        if hunting_recorderModule.recordingEvent ~= nil then
            modules.game_textmessage.displayFailureMessage("Cannot enable Cavebot while recording. Stop recording first.")
            if btn then
                btn.ignoreCallback = true
                btn:setChecked(false)
                btn.ignoreCallback = nil
            end
            if caveToggle then
                caveToggle:setChecked(false)
            end
            return
        end
    end

    -- Estado de ativação/desativação
    if value == 1 then
        helperConfig.cavebotHelperEnabled = true

        -- Nome do cavebot para exibir
        local cavebotName = cavebotData and cavebotData.name or "Unknown"
        modules.game_textmessage.displayGameMessage(
            string.format("Cavebot Helper is enabled.\nCavebot: %s executed successfully.", cavebotName)
        )

        if btn and btn.onCheckChange then
            btn.ignoreCallback = false
            btn:setChecked(true)
            btn.onCheckChange()
        end
        if caveToggle then
            caveToggle:setChecked(true)
        end
        
        -- Start minimap waypoint label updates
        hunting_recorderModule.startMinimapWaypointUpdate()

        -- Start gold balance server refresh (does NOT reset initial balance)
        hunting_recorderModule.startGoldBalanceRefresh()
        -- Mark cavebot ON for elapsed time tracking
        cavebotGoldLastOnTime = os.time()

    elseif value == 2 then
        helperConfig.cavebotHelperEnabled = false
        hunting_recorderModule.stopGoldBalanceRefresh()
        -- Accumulate ON time before stopping
        if cavebotGoldLastOnTime then
            cavebotGoldAccumTime = cavebotGoldAccumTime + (os.time() - cavebotGoldLastOnTime)
            cavebotGoldLastOnTime = nil
        end
        modules.game_textmessage.displayGameMessage("Cavebot Helper is disabled.")

        if btn and btn.onCheckChange then
            btn.ignoreCallback = false
            btn:setChecked(false)
            btn.onCheckChange()
        end
        if caveToggle then
            caveToggle:setChecked(false)
        end
        
        -- Stop minimap waypoint label updates when cavebot is disabled
        hunting_recorderModule.stopMinimapWaypointUpdate()


    end
end

-- Reflete "cavebot desligado" na intencao (helperConfig) e nos checkboxes de UI,
-- SEM disparar callbacks (evita re-entrar no toggle). Usar quando o motor e parado
-- por um caminho que NAO passa pelo checkbox -- o WP "stop_cavebot" e o limite de
-- mortes --, senao a UI fica marcada "ligado" com o cavebot ja parado (o estado
-- ambiguo (cavebotHelperEnabled=true, motor OFF) que a auditoria apontou).
function hunting_recorderModule.markCavebotDisabled()
    if helperConfig then helperConfig.cavebotHelperEnabled = false end
    local caveToggle = huntingWaypointsWindow and huntingWaypointsWindow:recursiveGetChildById("enableCaveBot")
    if caveToggle then
        caveToggle.ignoreCallback = true
        caveToggle:setChecked(false)
        caveToggle.ignoreCallback = nil
    end
    local btn = huntingWaypointsWindow and huntingWaypointsWindow.map and huntingWaypointsWindow.map.enabled
    if btn then
        btn.ignoreCallback = true
        btn:setChecked(false)
        btn.ignoreCallback = nil
    end
end


function hunting_recorderModule.loadSettings()
    hunting_recorderModule.loadSessionList()

    local settings = modules.game_helper.getPressetSettings()
    local sShortcut = settings['shortcuts'] or {}

    if not huntingWaypointsWindow.map then
        huntingWaypointsWindow.map = {}
    end
    if not huntingWaypointsWindow.map.enabled then
        huntingWaypointsWindow.map.enabled = {
            setChecked = function() end,
            isChecked = function() return false end,
            setOn = function() end,
            ignoreCallback = true
        }
    end

    huntingWaypointsWindow.map.enabled.ignoreCallback = true
    huntingWaypointsWindow.map.enabled:setChecked(sShortcut['huntingRecorder_enabled'] or false)
    huntingWaypointsWindow.map.enabled.ignoreCallback = nil

    huntingWaypointsWindow.map.enabled.onCheckChange = function()
        if huntingWaypointsWindow.map.enabled.ignoreCallback then
            return
        end

        local enabled = huntingWaypointsWindow.map.enabled:isChecked()
        g_minibot.setModuleToggle(5, enabled)

        if enabled then
            hunting_recorderModule.startWalk()
        else
            hunting_recorderModule.stopWalk()
        end
    end
end

function hunting_recorderModule.reloadInternalModule()
    g_minibot.resetRecorderSession()

    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    hunting_recorderModule.normalizeCavebotData(cavebotData)
    if not cavebotData.waypoints then
        cavebotData.waypoints = {}
    end

    -- Get cavebot config with defaults
    local sessionConfig = cavebotData.config or {}
    local creatures = sessionConfig.creaturesToStop or 8
    local resume = sessionConfig.creaturesToWalk or 2
    local lure = sessionConfig.lureMode or false
    local speed = sessionConfig.lureSpeed or 5
    local delayWalk = sessionConfig.walkDelay or DEFAULT_WALK_DELAY
    local avoidTrap = sessionConfig.avoidTrap or false
    local trapDistance = sessionConfig.trapDistance or 1
    local creaturesToAvoid = sessionConfig.creaturesToAvoid or 7

    local list = {}
    for _, waypoint in pairs(cavebotData.waypoints) do
        table.insert(list, waypoint)
    end
    table.sort(list, function(a, b)
        return a.index < b.index
    end)

    for _, waypoint in ipairs(list) do
        local point = {
            position = { x = waypoint['position']['x'], y = waypoint['position']['y'], z = waypoint['position']['z'] },
            creatures = creatures,
            resume = resume,
            lure = lure,
            speed = speed,
            delayWalk = delayWalk,
            index = waypoint['index'],
            teleport = waypoint['teleport']
        }
        g_minibot.registerWalkWaypoint(point)
    end
end

function hunting_recorderModule.onUpMapFloor()
    if virtualFloor <= 0 then
        return
    end

    -- Verificação de segurança para o minimap
    if not huntingWaypointsWindow or not huntingWaypointsWindow.map or not huntingWaypointsWindow.map.minimap then
        return
    end

    local minimap = huntingWaypointsWindow.map.minimap
    if minimap and minimap.floorUp then
        minimap:floorUp(1)
        virtualFloor = virtualFloor - 1
        hunting_recorderModule.refreshVirtualFloorsFullMap()
    end
end

function hunting_recorderModule.onDownMapFloor()
    if virtualFloor >= 15 then
        return
    end

    -- Verificação de segurança para o minimap
    if not huntingWaypointsWindow or not huntingWaypointsWindow.map or not huntingWaypointsWindow.map.minimap then
        return
    end

    local minimap = huntingWaypointsWindow.map.minimap
    if minimap and minimap.floorDown then
        minimap:floorDown(1)
        virtualFloor = virtualFloor + 1
        hunting_recorderModule.refreshVirtualFloorsFullMap()
    end
end

function hunting_recorderModule.refreshVirtualFloorsFullMap()
    -- Verificação de segurança completa para o minimap
    if not huntingWaypointsWindow or not huntingWaypointsWindow.map or not huntingWaypointsWindow.map.minimap then
        return
    end
    
    local minimap = huntingWaypointsWindow.map.minimap
    if not minimap then
        return
    end

    local player = g_game.getLocalPlayer()
    if player then
        local pos = player:getPosition()
        if pos then
            -- Verificações de segurança antes de definir posições no minimap
            if minimap.setCameraPosition then
                minimap:setCameraPosition(pos)
            end
            if minimap.setCrossPosition then
                minimap:setCrossPosition(pos)
            end
        end
    end

    local mapContainer = huntingWaypointsWindow:recursiveGetChildById('map')
    if mapContainer then
        local titleLabel = mapContainer:recursiveGetChildById('title')
        if titleLabel then
            titleLabel:setText(string.format('Map Preview [Floor %d]', virtualFloor))
        end
    end
end

-- Minimap waypoint label update event
local minimapWaypointUpdateEvent = nil

-- Update the minimap waypoint label (top-left corner of default minimap)
function hunting_recorderModule.updateMinimapWaypointLabel(currentWaypoint, totalWaypoints, isActive)
    -- Find the minimap window
    local minimapWindow = nil
    if modules.game_minimap and modules.game_minimap.getMinimapWindow then
        minimapWindow = modules.game_minimap.getMinimapWindow()
    end
    
    -- Fallback: try to find it by ID
    if not minimapWindow then
        local rootWidget = g_ui.getRootWidget()
        if rootWidget then
            minimapWindow = rootWidget:recursiveGetChildById('minimapWindow')
        end
    end
    
    if not minimapWindow then
        return
    end
    
    -- Find the panel container
    local waypointPanel = minimapWindow:recursiveGetChildById('cavebotWaypointPanel')
    local waypointLabel = minimapWindow:recursiveGetChildById('cavebotWaypointLabel')
    
    if not waypointLabel then
        return
    end
    
    if isActive and totalWaypoints and totalWaypoints > 0 then
        local text = string.format('%d/%d', currentWaypoint or 0, totalWaypoints)
        waypointLabel:setText(text)
        
        -- Adjust panel width based on text length
        if waypointPanel then
            local textWidth = math.max(42, #text * 7 + 10)
            waypointPanel:setWidth(textWidth)
            waypointPanel:setVisible(true)
        else
            waypointLabel:setVisible(true)
        end
    else
        if waypointPanel then
            waypointPanel:setVisible(false)
        else
            waypointLabel:setVisible(false)
        end
    end
end

-- Hide the minimap waypoint label
function hunting_recorderModule.hideMinimapWaypointLabel()
    -- Find the minimap window
    local minimapWindow = nil
    if modules.game_minimap and modules.game_minimap.getMinimapWindow then
        minimapWindow = modules.game_minimap.getMinimapWindow()
    end
    
    if not minimapWindow then
        local rootWidget = g_ui.getRootWidget()
        if rootWidget then
            minimapWindow = rootWidget:recursiveGetChildById('minimapWindow')
        end
    end
    
    if minimapWindow then
        local waypointPanel = minimapWindow:recursiveGetChildById('cavebotWaypointPanel')
        if waypointPanel then
            waypointPanel:setVisible(false)
        end
        local waypointLabel = minimapWindow:recursiveGetChildById('cavebotWaypointLabel')
        if waypointLabel and not waypointPanel then
            waypointLabel:setVisible(false)
        end
    end
end

-- Start periodic minimap waypoint label updates
function hunting_recorderModule.startMinimapWaypointUpdate()
    if minimapWaypointUpdateEvent then
        return -- Already running
    end
    
    local function updateLoop()
        -- Check if cavebot is active
        if not helperConfig or not helperConfig.cavebotHelperEnabled then
            hunting_recorderModule.hideMinimapWaypointLabel()
            minimapWaypointUpdateEvent = nil
            return
        end
        
        -- Get cavebot status (lightweight: only currentWaypoint/totalWaypoints/
        -- isActive — no spectator scan, no ~30-field alloc like getDebugInfo).
        local statusFn = cavebotWalker and (cavebotWalker.getStatus or cavebotWalker.getDebugInfo)
        if statusFn then
            local ok, info = pcall(statusFn)
            if ok and info then
                hunting_recorderModule.updateMinimapWaypointLabel(info.currentWaypoint, info.totalWaypoints, info.isActive)
            end
        end
        
        -- Schedule next update
        minimapWaypointUpdateEvent = scheduleEvent(updateLoop, 500)
    end
    
    updateLoop()
end

-- Stop periodic minimap waypoint label updates
function hunting_recorderModule.stopMinimapWaypointUpdate()
    if minimapWaypointUpdateEvent then
        removeEvent(minimapWaypointUpdateEvent)
        minimapWaypointUpdateEvent = nil
    end
    hunting_recorderModule.hideMinimapWaypointLabel()
end

function hunting_recorderModule.onMinimapMouseWheel(minimap, mousePos, mouseWheelDirection)
    if not minimap then return true end
    
    -- Zoom in/out based on wheel direction
    if mouseWheelDirection == MouseWheelUp then
        -- Zoom in
        if minimapZoomLevel > minimapMinZoom then
            minimapZoomLevel = minimapZoomLevel - 1
            minimap:setZoom(minimapZoomLevel)
        end
    elseif mouseWheelDirection == MouseWheelDown then
        -- Zoom out
        if minimapZoomLevel < minimapMaxZoom then
            minimapZoomLevel = minimapZoomLevel + 1
            minimap:setZoom(minimapZoomLevel)
        end
    end
    
    return true
end

function hunting_recorderModule.onMinimapMousePress(minimap, mousePos, mouseButton)
    if not minimap then return false end
    
    if mouseButton == MouseLeftButton then
        -- Start dragging
        minimapDragging = true
        minimapDragStartPos = mousePos
        minimapDragStartCamera = minimap:getCameraPosition()
        return true
    end
    
    return false
end

function hunting_recorderModule.onMinimapMouseMove(minimap, mousePos, mouseMoved)
    if not minimap then return false end
    
    if minimapDragging and minimapDragStartPos and minimapDragStartCamera then
        -- Calculate pixel movement
        local dx = mousePos.x - minimapDragStartPos.x
        local dy = mousePos.y - minimapDragStartPos.y
        
        -- Get zoom scale factor (higher zoom = smaller movement needed)
        local zoomScale = math.pow(2, minimapZoomLevel)
        
        -- Calculate tile offset (inverted for natural drag behavior)
        local tileOffsetX = math.floor(-dx / zoomScale)
        local tileOffsetY = math.floor(-dy / zoomScale)
        
        -- Calculate new camera position
        local newCameraPos = {
            x = minimapDragStartCamera.x + tileOffsetX,
            y = minimapDragStartCamera.y + tileOffsetY,
            z = minimapDragStartCamera.z
        }
        
        -- Update camera position
        minimap:setCameraPosition(newCameraPos)
        
        return true
    end
    
    return false
end

function hunting_recorderModule.onMinimapMouseRelease(minimap, mousePos, mouseButton)
    if not minimap then return false end
    
    if mouseButton == MouseLeftButton then
        -- Stop dragging
        minimapDragging = false
        minimapDragStartPos = nil
        minimapDragStartCamera = nil
        return true
    end
    
    if mouseButton == MouseRightButton then
        -- Only show menu if we weren't dragging
        if not minimapDragging then
            -- Get map position from mouse position
            local mapPos = minimap:getTilePosition(mousePos)
            if not mapPos then
                return false
            end
            
            -- Show waypoint creation menu
            hunting_recorderModule.showWaypointCreationMenu(mousePos, mapPos)
        end
        return true
    elseif mouseButton == MouseMiddleButton then
        -- Reset camera to player position
        local player = g_game.getLocalPlayer()
        if player then
            local pos = player:getPosition()
            if pos and minimap.setCameraPosition then
                minimap:setCameraPosition(pos)
            end
        end
        return true
    end
    
    return false
end

function hunting_recorderModule.showWaypointCreationMenu(mousePos, mapPos)
    local menu = g_ui.createWidget('HelperPopupMenu')
    menu:setGameMenu(true)
    
    -- Basic waypoint types
    menu:addOption('Node', function()
        hunting_recorderModule.createWaypointAtPosition(mapPos, 0)
    end)
    
    menu:addOption('Stand', function()
        hunting_recorderModule.createWaypointAtPosition(mapPos, 1)
    end)
    
    menu:addSeparator()
    
    -- Action waypoints
    menu:addOption('Use', function()
        hunting_recorderModule.createWaypointAtPosition(mapPos, 2)
    end)
    
    menu:addOption('Rope', function()
        hunting_recorderModule.createWaypointAtPosition(mapPos, 3)
    end)
    
    menu:addOption('Hole', function()
        hunting_recorderModule.createWaypointAtPosition(mapPos, 4)
    end)
    
    menu:addOption('Lever', function()
        hunting_recorderModule.createWaypointAtPosition(mapPos, 5)
    end)

    menu:addOption('Door', function()
        hunting_recorderModule.createWaypointAtPosition(mapPos, 'door')
    end)

    menu:addSeparator()

    -- Control flow waypoints
    menu:addOption('Label', function()
        hunting_recorderModule.createLabelWaypointAtPosition(mapPos)
    end)
    
    menu:addOption('Goto', function()
        hunting_recorderModule.createGotoWaypointAtPosition(mapPos)
    end)
    
    menu:addSeparator()

    -- Special waypoints
    menu:addOption('Stop to Kill', function()
        hunting_recorderModule.createStopToKillAtPosition(mapPos)
    end)
    
    menu:addOption('Special Area', function()
        hunting_recorderModule.createSpecialAreaAtPosition(mapPos)
    end)
    
    menu:display(mousePos)
end

function hunting_recorderModule.createWaypointAtPosition(pos, waypointType)
    -- Get current cavebot data
    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.waypoints then
        cavebotData.waypoints = {}
    end
    ensureSpecialAreasTable(cavebotData)
    
    -- Convert waypoints to sorted array
    local waypoints = {}
    for _, waypoint in pairs(cavebotData.waypoints) do
        table.insert(waypoints, waypoint)
    end
    table.sort(waypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)
    
    -- Get selected waypoint index for insertion after it
    local selectedIndex = nil
    if huntingWaypointsWindow and huntingWaypointsWindow.settings then
        local waypointsList = huntingWaypointsWindow.settings.main.waypoints.list
        if waypointsList then
            for _, widget in ipairs(waypointsList:getChildren()) do
                if widget.selectedWaypoint and widget.waypointIndex then
                    selectedIndex = widget.waypointIndex
                    break
                end
            end
        end
    end
    
    -- Manual add: zero logic - only position and type that user clicked
    local newWaypoint = {
        position = pos,
        teleport = false,
        type = waypointType,
        index = nil
    }
    
    -- Add after selected or at end
    if selectedIndex then
        local insertPos = nil
        for i, wp in ipairs(waypoints) do
            if wp.index == selectedIndex then
                insertPos = i + 1
                break
            end
        end
        if insertPos then
            newWaypoint.index = selectedIndex + 1
            for i = insertPos, #waypoints do
                waypoints[i].index = waypoints[i].index + 1
            end
            table.insert(waypoints, insertPos, newWaypoint)
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    else
        newWaypoint.index = #waypoints + 1
        table.insert(waypoints, newWaypoint)
    end
    
    -- Reindex all waypoints
    table.sort(waypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)
    for i, wp in ipairs(waypoints) do
        wp.index = i
    end
    
    -- Update cavebot data
    cavebotData.waypoints = {}
    for _, wp in ipairs(waypoints) do
        cavebotData.waypoints[wp.index] = wp
    end
    hunting_recorderModule.setCurrentCavebotData(cavebotData)
    
    -- Reload waypoints in UI
    hunting_recorderModule.refreshWaypointsList(waypoints, pos, newWaypoint.index)

    modules.game_textmessage.displayGameMessage("Waypoint created at " .. pos.x .. ", " .. pos.y .. ", " .. pos.z)
end

function hunting_recorderModule.createLabelWaypointAtPosition(pos)
    local inputWindow = g_ui.displayUI('styles/label_name', modules.game_helper)
    if not inputWindow then return end

    local textEdit = inputWindow:getChildById('nameText')
    local okButton = inputWindow:getChildById('buttonOk')

    okButton.onClick = function()
        local labelName = textEdit:getText()
        if labelName and labelName ~= '' then
            inputWindow:destroy()
            hunting_recorderModule.createWaypointAtPositionWithLabel(pos, 99, labelName)
        else
            modules.game_textmessage.displayFailureMessage("Label name cannot be empty")
        end
    end

    inputWindow:show()
    inputWindow:raise()
    textEdit:focus()
end

function hunting_recorderModule.createGotoWaypointAtPosition(pos)
    -- Load the goto waypoint dialog
    local gotoWindow = g_ui.displayUI('styles/goto_waypoint', modules.game_helper)
    if gotoWindow then
        -- Store position for later use
        gotoWindow.waypointPosition = pos
        
        -- Override OK button to use position-based creation
        local buttonOk = gotoWindow:recursiveGetChildById('buttonOk')
        if buttonOk then
            buttonOk.onClick = function()
                local labelEdit = gotoWindow:recursiveGetChildById('labelEdit')
                local label = labelEdit and labelEdit:getText() or ""
                
                -- Determine condition
                local condition = "none"
                local stamina = 0
                
                local optionNone = gotoWindow:recursiveGetChildById('optionNone')
                local optionLess = gotoWindow:recursiveGetChildById('optionLess')
                local optionGreater = gotoWindow:recursiveGetChildById('optionGreater')
                
                if optionNone and optionNone:isChecked() then
                    condition = "none"
                elseif optionLess and optionLess:isChecked() then
                    condition = "stamina_lt"
                    local staminaLess = gotoWindow:recursiveGetChildById('staminaLess')
                    stamina = staminaLess and tonumber(staminaLess:getText()) or 39
                elseif optionGreater and optionGreater:isChecked() then
                    condition = "stamina_gt"
                    local staminaGreater = gotoWindow:recursiveGetChildById('staminaGreater')
                    stamina = staminaGreater and tonumber(staminaGreater:getText()) or 42
                end
                
                if label ~= "" then
                    hunting_recorderModule.createGotoWaypointAtPositionWithData(pos, label, condition, stamina)
                else
                    modules.game_textmessage.displayFailureMessage("Label name cannot be empty")
                end
                gotoWindow:destroy()
            end
        end
    else
        -- Fallback: create a simple input dialog for the label
        local rootWidget = g_ui.getRootWidget()
        if not rootWidget then return end
        
        local inputWindow = g_ui.createWidget('MainWindow', rootWidget)
        inputWindow:setText('Goto Label')
        inputWindow:setSize({width = 300, height = 120})
        inputWindow:centerIn('parent')

        local panel = g_ui.createWidget('Panel', inputWindow)
        panel:addAnchor(AnchorTop, 'parent', AnchorTop)
        panel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        panel:addAnchor(AnchorRight, 'parent', AnchorRight)
        panel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        panel:setMargin(10)

        local label = g_ui.createWidget('Label', panel)
        label:setText('Enter target label name:')
        label:addAnchor(AnchorTop, 'parent', AnchorTop)
        label:addAnchor(AnchorLeft, 'parent', AnchorLeft)

        local textEdit = g_ui.createWidget('TextEdit', panel)
        textEdit:addAnchor(AnchorTop, 'prev', AnchorBottom)
        textEdit:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        textEdit:addAnchor(AnchorRight, 'parent', AnchorRight)
        textEdit:setMarginTop(5)
        textEdit:setHeight(25)

        local buttonPanel = g_ui.createWidget('Panel', panel)
        buttonPanel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        buttonPanel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        buttonPanel:addAnchor(AnchorRight, 'parent', AnchorRight)
        buttonPanel:setHeight(30)

        local okButton = g_ui.createWidget('Button', buttonPanel)
        okButton:setText('OK')
        okButton:setWidth(70)
        okButton:setHeight(25)
        okButton:addAnchor(AnchorRight, 'parent', AnchorRight)
        okButton:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        okButton.onClick = function()
            local labelName = textEdit:getText()
            if labelName and labelName ~= '' then
                inputWindow:destroy()
                hunting_recorderModule.createGotoWaypointAtPositionWithData(pos, labelName, "none", 0)
            else
                modules.game_textmessage.displayFailureMessage("Label name cannot be empty")
            end
        end

        local cancelButton = g_ui.createWidget('Button', buttonPanel)
        cancelButton:setText('Cancel')
        cancelButton:setWidth(70)
        cancelButton:setHeight(25)
        cancelButton:addAnchor(AnchorRight, 'prev', AnchorLeft)
        cancelButton:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        cancelButton:setMarginRight(5)
        cancelButton.onClick = function()
            inputWindow:destroy()
        end

        inputWindow:show()
        inputWindow:raise()
        textEdit:focus()
    end
end

function hunting_recorderModule.createStopToKillAtPosition(pos)
    -- Get creatures to walk value from settings
    local creaturesToWalk = safeGetSettingsValue(false, 'cavebot_creatures_to_walk', 0)
    
    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.waypoints then
        cavebotData.waypoints = {}
    end
    
    local waypoints = {}
    for _, waypoint in pairs(cavebotData.waypoints) do
        table.insert(waypoints, waypoint)
    end
    table.sort(waypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)
    
    local newWaypoint = {
        position = pos,
        teleport = false,
        type = 'stop_to_kill',
        creaturesToWalk = creaturesToWalk,
        index = #waypoints + 1
    }
    
    table.insert(waypoints, newWaypoint)
    
    cavebotData.waypoints = {}
    for i, wp in ipairs(waypoints) do
        wp.index = i
        cavebotData.waypoints[i] = wp
    end
    hunting_recorderModule.setCurrentCavebotData(cavebotData)
    
    hunting_recorderModule.refreshWaypointsList(waypoints, pos, newWaypoint.index)
    modules.game_textmessage.displayGameMessage("Stop to Kill waypoint created")
end

function hunting_recorderModule.createSpecialAreaAtPosition(pos)
    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    ensureSpecialAreasTable(cavebotData)
    
    -- Check for duplicate position
    for _, area in ipairs(cavebotData.specialAreas) do
        if area.position and isSamePosition(area.position, pos) then
            modules.game_textmessage.displayFailureMessage("A special area already exists at this position")
            return
        end
    end
    
    local newAreaId = getNextSpecialAreaId(cavebotData.specialAreas)
    local newArea = {
        id = newAreaId,
        position = pos,
        type = 90
    }
    table.insert(cavebotData.specialAreas, newArea)
    hunting_recorderModule.setCurrentCavebotData(cavebotData)
    
    if cavebotWalker and cavebotWalker.updateConfig then
        cavebotWalker.updateConfig({specialAreas = cavebotData.specialAreas})
    end
    
    hunting_recorderModule.reloadSpecialAreasList()
    hunting_recorderModule.updateDebugPos()
    
    scheduleEvent(function()
        hunting_recorderModule.selectSpecialAreaById(newAreaId)
    end, 50)
    
    modules.game_textmessage.displayGameMessage("Special area created at " .. pos.x .. ", " .. pos.y .. ", " .. pos.z)
end

function hunting_recorderModule.createWaypointAtPositionWithLabel(pos, waypointType, label)
    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.waypoints then
        cavebotData.waypoints = {}
    end
    
    local waypoints = {}
    for _, waypoint in pairs(cavebotData.waypoints) do
        table.insert(waypoints, waypoint)
    end
    table.sort(waypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)
    
    local newWaypoint = {
        position = pos,
        teleport = false,
        type = waypointType,
        label = label,
        index = #waypoints + 1
    }
    
    table.insert(waypoints, newWaypoint)
    
    cavebotData.waypoints = {}
    for i, wp in ipairs(waypoints) do
        wp.index = i
        cavebotData.waypoints[i] = wp
    end
    hunting_recorderModule.setCurrentCavebotData(cavebotData)
    
    hunting_recorderModule.refreshWaypointsList(waypoints, pos, newWaypoint.index)
    modules.game_textmessage.displayGameMessage("Label waypoint '" .. label .. "' created")
end

function hunting_recorderModule.createGotoWaypointAtPositionWithData(pos, label, condition, stamina)
    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.waypoints then
        cavebotData.waypoints = {}
    end
    
    local waypoints = {}
    for _, waypoint in pairs(cavebotData.waypoints) do
        table.insert(waypoints, waypoint)
    end
    table.sort(waypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)
    
    local newWaypoint = {
        position = pos,
        teleport = false,
        type = 98,
        label = label,
        gotoCondition = condition,
        gotoStamina = stamina,
        index = #waypoints + 1
    }
    
    table.insert(waypoints, newWaypoint)
    
    cavebotData.waypoints = {}
    for i, wp in ipairs(waypoints) do
        wp.index = i
        cavebotData.waypoints[i] = wp
    end
    hunting_recorderModule.setCurrentCavebotData(cavebotData)
    
    hunting_recorderModule.refreshWaypointsList(waypoints, pos, newWaypoint.index)
    modules.game_textmessage.displayGameMessage("Goto waypoint created -> " .. label)
end

function hunting_recorderModule.refreshWaypointsList(waypoints, selectPos, selectIndex)
    if huntingWaypointsWindow and huntingWaypointsWindow.settings then
        -- Update last waypoint position
        if selectPos then
            lastWaypointPosition = { x = selectPos.x, y = selectPos.y, z = selectPos.z }
        end

        -- Use chunked reload with callback to select the new waypoint after all chunks are loaded
        hunting_recorderModule.reloadAllWaypointsUI(waypoints, function()
            if selectIndex then
                scheduleEvent(function()
                    hunting_recorderModule.selectWaypointByIndex(selectIndex)
                end, 50)
            elseif selectPos then
                hunting_recorderModule.selectWaypointByPosition(selectPos, waypoints)
            end
        end)
    end

    hunting_recorderModule.updateDebugPos()
end

-- Deprecated: Sessions removed, use loadSelectedCavebot instead
function hunting_recorderModule.onClickSessionEntry(widget)
    -- Function kept for compatibility but does nothing
    return
end

function hunting_recorderModule.createBrandnewSession(uid)
    local lastSession = uid
    if uid == nil then
        lastSession = safeGetSettingsValue(false, 'last_session', 0) + 1
    end

    local entry = {
        name = ('New Session #' .. lastSession),
        uid = lastSession,
        creation = os.time()
    }

    if uid == nil then
        safeSetSettingsValue(false, 'last_session', lastSession)
    end

    return entry
end

function hunting_recorderModule.createBrandnewSession(uid)
    local lastSession = uid
    if uid == nil then
        lastSession = safeGetSettingsValue(false, 'last_session', 0) + 1
    end

    local entry = {
        name = ('New Session #' .. lastSession),
        uid = lastSession,
        creation = os.time()
    }

    if uid == nil then
        safeSetSettingsValue(false, 'last_session', lastSession)
    end

    return entry
end

function hunting_recorderModule.createSessionWidget(entry)
    local widget = g_ui.createWidget('MiniBotHuntingRecorderEntry', huntingWaypointsWindow.sessions.list)
    initializeWidget(widget)

    widget:setText(entry.name)
    widget:setTooltip(entry.name)
    widget.sessionUid = entry.uid

    if (huntingWaypointsWindow.sessions.list:getChildCount() % 2) == 0 then
        widget:setBackgroundColor('#484848')
    else
        widget:setBackgroundColor('alpha')
    end

    widget:setPhantom(false)
    widget:setFocusable(true)
    widget.onMousePress = nil

    widget.onMouseRelease = function(self, mousePos, mouseButton)
        if mouseButton == MouseLeftButton then
            hunting_recorderModule.onClickSessionEntry(self)
        elseif mouseButton == MouseRightButton then
            hunting_recorderModule.openSessionGameMenu(self, mousePos, mouseButton)
        end
        return true
    end
end

function hunting_recorderModule.openSessionGameMenu(widget, mousePos, mouseButton)
    if mouseButton ~= MouseRightButton then
        return
    end

    local menu = g_ui.createWidget('HelperPopupMenu')
    menu:setGameMenu(true)

    menu:addOption("Edit '" .. widget:getText() .. "' name", function()
        hunting_recorderModule.onClickEditPreset(widget)
    end)

    menu:addOption("Remove '" .. widget:getText() .. "'", function()
        hunting_recorderModule.onClickRemovePreset(widget)
    end)

    menu:display(mousePos)
    return true
end

function hunting_recorderModule.onClickEditPreset(widget)
    if huntingWaypointsWindow.sessions.list:getChildCount() <= 1 then
        return
    end

    if editSessionWindow and not editSessionWindow:isDestroyed() then
        editSessionWindow:destroy()
        editSessionWindow = nil
        return
    end

    local rootWidget = g_ui.getRootWidget()
    if not rootWidget then
        return
    end

    local window = g_ui.loadUI("/mods/game_helper/styles/edit_session.otui", rootWidget)
    if not window then
        return
    end

    editSessionWindow = window
    window.onDestroy = function()
        editSessionWindow = nil
    end

    window:show()
    window:raise()
    window:focus()
    window:lock()
    if _G.helperModalEnter then _G.helperModalEnter(window) end

    window.nameText:setText(widget:getText())
    window.buttonOk:setEnabled(window.nameText:getText():len() > 0)
    window.buttonOk:setText(tr("OK"))
    window.buttonCancel:setText(tr("Cancel"))

    window.nameText.onTextChange = function(self, text)
        window.buttonOk:setEnabled(text:len() > 0)
    end

    local function saveAndClose()
        local newName = window.nameText:getText():trim()
        if newName == "" then
            window:destroy()
            window:unlock()
            return
        end

        local uid = widget.sessionUid
        local sSessions = safeGetSettingsValue(false, 'sessions', {})
        for _, entry in pairs(sSessions) do
            if entry.uid == uid then
                entry.name = newName
                break
            end
        end
        safeSetSettingsValue(false, 'sessions', sSessions)
		
        widget:setText(newName)
        widget:setTooltip(newName)
		
        local sessionData = hunting_recorderModule.loadSessionFromDisk(uid)
        if not sessionData then
            sessionData = {}
        end
        sessionData.name = newName
        hunting_recorderModule.saveSessionToDisk(uid, sessionData)
        local sSettings = safeGetSettingsValue(false, 'sessions_settings', {})
        if not sSettings[tostring(uid)] then
            sSettings[tostring(uid)] = {}
        end
		
        sSettings[tostring(uid)].name = newName
        safeSetSettingsValue(false, 'sessions_settings', sSettings)
        if hunting_recorderModule.selectedSessionUid == uid then
            local titleLabel = huntingWaypointsWindow:recursiveGetChildById('sessionNameLabel')
            if titleLabel then
                titleLabel:setText(newName)
            end
        end

        window:destroy()
        window:unlock()

        modules.game_textmessage.displayGameMessage(string.format("Session renamed to '%s' successfully.", newName))
    end

    local closeWindow = function()
        window:destroy()
        window:unlock()
    end
    window.buttonOk.onClick = saveAndClose
    window.onEnter = saveAndClose
    window.buttonCancel.onClick = closeWindow
    window.onEscape = closeWindow
end

function hunting_recorderModule.onClickRemovePreset(widget)
    if huntingWaypointsWindow.sessions.list:getChildCount() <= 1 then
        return
    end

    local uid = widget.sessionUid
    local path = string.format("%ssession_%d.json", hunting_recorderModule.ensureDirectories(), uid)
    path = path:gsub("\\", "/")

    if g_resources.fileExists(path) then
        local ok = g_resources.deleteFile and g_resources.deleteFile(path)
        if not ok then
            g_resources.writeFileContents(path, "")
        end
    end

    local sSessions = safeGetSettingsValue(false, "sessions", {})
    local newSessions = {}
    for _, entry in pairs(sSessions) do
        if entry.uid ~= uid then
            newSessions[tostring(entry.uid)] = entry
        end
    end
    safeSetSettingsValue(false, "sessions", newSessions)

    local sSettings = safeGetSettingsValue(false, "sessions_settings", {})
    sSettings[tostring(uid)] = nil
    safeSetSettingsValue(false, "sessions_settings", sSettings)

    hunting_recorderModule.loadSessionList()

    local firstChild = huntingWaypointsWindow.sessions.list:getChildByIndex(1)
    if firstChild then
        hunting_recorderModule.onClickSessionEntry(firstChild)
    end

    modules.game_textmessage.displayGameMessage(string.format("Session #%d deleted successfully.", uid))
end

-- Deprecated: Sessions removed, use openCavebotsManager instead
function hunting_recorderModule.onClickNewSession()
    -- Open cavebots manager instead
    hunting_recorderModule.openCavebotsManager()
end

-- Deprecated: Use getCurrentCavebotData instead
function hunting_recorderModule.getSessionSettings()
    return hunting_recorderModule.getCurrentCavebotData()
end

-- Deprecated: Use setCurrentCavebotData instead
function hunting_recorderModule.setSessionSettings(value)
    hunting_recorderModule.setCurrentCavebotData(value)
end

function hunting_recorderModule.internalSelectWaypoint(widget, index, ignoreList, ignoreMap)
    hunting_recorderModule.selectedSessionIndex = index
    if not(ignoreList) then
        -- Deselect only previously selected widget (avoids iterating ALL children)
        if previouslySelectedWidget and not previouslySelectedWidget:isDestroyed() then
            previouslySelectedWidget.mask:hide()
            previouslySelectedWidget.selectedWaypoint = false
            if previouslySelectedWidget.updateOnStates then
                previouslySelectedWidget:updateOnStates()
            end
        end

        -- O(1) lookup for the target widget
        local c = waypointWidgetLookup[index]
        if c and not c:isDestroyed() then
            c.ignoreWaypointCallback = true
            c:onClick()
            huntingWaypointsWindow.settings.main.waypoints.list:ensureChildVisible(c)
            c.ignoreWaypointCallback = nil
            previouslySelectedWidget = c
        end
    end

    if not(ignoreMap) then
        for _, c in ipairs(huntingWaypointsWindow.map.minimap:getChildren()) do
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

    if widget == nil or widget.ignoreCallback then
        return
    end

    if not g_minibot.isModuleToggle(5) then
        g_minibot.setCurrentWalkIndex(index - 1)
    end
end

function hunting_recorderModule.updateWaypointLabel(index)
    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData or not cavebotData.waypoints then return end

    for _, w in ipairs(huntingWaypointsWindow.settings.main.waypoints.list:getChildren()) do
        if w.waypointIndex == index then
            local pos = w.internalWaypointPosition
            local waypointType = w.waypointType or 0
            local typeName = waypointTypeToName(waypointType)
            local waypointTypeNum = waypointTypeToNumber(waypointType)

            -- For label/goto waypoints, show only the label name without coordinates
            if (waypointTypeNum == 99 or waypointTypeNum == 98) and w.waypointLabel then
                w:setText(string.format("%d: [%s] - %s",
                    index,
                    typeName,
                    w.waypointLabel
                ))
            else
                w:setText(string.format("%d: (%d, %d, %d) [%s]",
                    index,
                    pos.x,
                    pos.y,
                    pos.z,
                    typeName
                ))
            end
            break
        end
    end
end

-- Helper function to refresh all waypoint labels with session config
function hunting_recorderModule.refreshAllWaypointLabels()
    if not huntingWaypointsWindow or not huntingWaypointsWindow.settings then return end

    local list = huntingWaypointsWindow.settings.main.waypoints.list
    if not list then return end

    for _, w in ipairs(list:getChildren()) do
        if w.waypointIndex then
            hunting_recorderModule.updateWaypointLabel(w.waypointIndex)
        end
    end
end

function hunting_recorderModule.createBrandNewSessionWaypoint(position, ignoreReload, index, waypointType, label, gotoCondition, gotoStamina, labelHasSupply, labelNoSupply, waitStaminaMinutes, waitDelayMs, levitateMode, levitateDir)
    -- Normalize type to number for internal comparisons (accept both string and number)
    local wpTypeNum = waypointTypeToNumber(waypointType or 0)

    if wpTypeNum == 90 then
        return nil
    end
    local list = huntingWaypointsWindow.settings.main.waypoints.list
    -- Contar filhos antes de criar o novo widget para aplicar cores alternadas
    local visibleIndex = #list:getChildren() + 1
    local widget = g_ui.createWidget('MiniBotHuntingRecorderEntry', list)
    widget.waypointIndex = index
    initializeWidget(widget)
    -- Register in O(1) lookup table
    hunting_recorderModule.registerWaypointWidget(index, widget)
    widget.internalWaypointPosition = position
    widget.waypointType = waypointType or 0 -- Store original type (string or number)
    widget.waypointLabel = label
    widget.gotoCondition = gotoCondition
    widget.gotoStamina = gotoStamina
    widget.labelHasSupply = labelHasSupply
    widget.labelNoSupply = labelNoSupply
    widget.waitStaminaMinutes = waitStaminaMinutes
    widget.waitDelayMs = waitDelayMs
    widget.levitateMode = levitateMode
    widget.levitateDir = levitateDir

    -- Aplicar cores alternadas (zebra striping) - mesmo que cavebot list
    widget.baseBackgroundColor = visibleIndex % 2 == 0 and "#0a0a0a" or "#12121200"
    widget:setBackgroundColor(widget.baseBackgroundColor)
    if widget.updateOnStates then
        widget:updateOnStates()
    end

    local typeName = waypointTypeToName(waypointType)
    local wpTypeStr = waypointTypeToString(waypointType or 0)

    -- For label/goto waypoints, show only the label name without coordinates
    if (wpTypeNum == 99 or wpTypeNum == 98) and label then
        widget:setText(string.format(
            "%d: [%s] - %s",
            index,
            typeName,
            label
        ))
    elseif wpTypeStr == "wait_delay" and waitDelayMs then
        widget:setText(string.format(
            "%d: (%d, %d, %d) [%s] %gms",
            index,
            position.x, position.y, position.z,
            typeName,
            waitDelayMs
        ))
    elseif wpTypeStr == "levitate" then
        local dirNames = { [0] = "N", [1] = "E", [2] = "S", [3] = "W" }
        local dirStr = dirNames[tonumber(levitateDir or -1)] or "?"
        local modeStr = (levitateMode == "down") and "DOWN" or "UP"
        widget:setText(string.format(
            "%d: (%d, %d, %d) [%s %s %s]",
            index,
            position.x, position.y, position.z,
            typeName, modeStr, dirStr
        ))
    else
        widget:setText(string.format(
            "%d: (%d, %d, %d) [%s]",
            index,
            position.x, position.y, position.z,
            typeName
        ))
    end

    -- Build tooltip with goto condition if applicable
    local tooltipText = string.format(
        "Waypoint %d\nPosition: %d, %d, %d\nType: %s",
        index,
        position.x, position.y, position.z,
        typeName
    )

    -- Add goto condition info to tooltip for GOTO waypoints
    if wpTypeNum == 98 then
        tooltipText = tooltipText .. string.format("\nDestino: %s", label or "N/A")

        if gotoCondition then
            if gotoCondition == "none" then
                tooltipText = tooltipText .. "\n\nSalta sempre para o label '" .. (label or "N/A") .. "'\nsem verificar condicoes"
            elseif gotoCondition == "stamina_lt" and gotoStamina then
                tooltipText = tooltipText .. string.format("\n\nSalta para o label '%s'\nquando stamina for menor que %d", label or "N/A", gotoStamina)
            elseif gotoCondition == "stamina_gt" and gotoStamina then
                tooltipText = tooltipText .. string.format("\n\nSalta para o label '%s'\nquando stamina for maior que %d", label or "N/A", gotoStamina)
            end
        else
            tooltipText = tooltipText .. "\n\nSalta sempre para o label '" .. (label or "N/A") .. "'"
        end
    end

    -- Add wait_delay info to tooltip
    if wpTypeStr == "wait_delay" and waitDelayMs then
        local seconds = waitDelayMs / 1000
        tooltipText = tooltipText .. string.format("\n\nEspera %g segundos ao chegar na posicao", seconds)
    end

    -- Add levitate info to tooltip
    if wpTypeStr == "levitate" then
        local dirFull = { [0] = "North", [1] = "East", [2] = "South", [3] = "West" }
        local modeStr = (levitateMode == "down") and "Down" or "Up"
        tooltipText = tooltipText .. string.format(
            "\n\nSpell: exani hur %s\nFacing: %s",
            modeStr:lower(),
            dirFull[tonumber(levitateDir or -1)] or "?"
        )
    end

    widget:setTooltip(tooltipText)

    widget.onClick = function()
        -- Deselect only previously selected widget (avoids iterating ALL children)
        if previouslySelectedWidget and not previouslySelectedWidget:isDestroyed() and previouslySelectedWidget ~= widget then
            previouslySelectedWidget.mask:hide()
            previouslySelectedWidget.selectedWaypoint = false
            if previouslySelectedWidget.updateOnStates then
                previouslySelectedWidget:updateOnStates()
            end
        end
        widget.mask:show()
        widget.selectedWaypoint = true
        widget:focus()
        previouslySelectedWidget = widget

        if widget.ignoreWaypointCallback then return end

        huntingWaypointsWindow.map.minimap:setCameraPosition(widget.internalWaypointPosition)
        hunting_recorderModule.internalSelectWaypoint(widget, index, true, false)
    end

    widget.onMouseRelease = function(_, mousePos, mouseButton)
        if mouseButton == MouseRightButton then
            local menu = g_ui.createWidget('HelperPopupMenu')
            menu:setGameMenu(true)
            menu:addOption("Select Waypoint", function()
                hunting_recorderModule.internalSelectWaypoint(widget, index, false, false)
            end)

            -- Edit options (only when cavebot is stopped)
            local cavebotStopped = not helperConfig or not helperConfig.cavebotHelperEnabled
            if cavebotStopped then
                if wpTypeStr == "wait_delay" then
                    menu:addOption("Edit Wait Delay", function()
                        hunting_recorderModule.editWaitDelayWaypoint(widget)
                    end)
                elseif wpTypeNum == 99 then -- label
                    menu:addOption("Edit Label", function()
                        hunting_recorderModule.editLabelWaypoint(widget)
                    end)
                elseif wpTypeStr == "levitate" then
                    menu:addOption("Edit Levitate", function()
                        hunting_recorderModule.editLevitateWaypoint(widget)
                    end)
                elseif wpTypeStr == "script" then
                    menu:addOption("Edit Script", function()
                        hunting_recorderModule.editScriptWaypoint(widget)
                    end)
                end
            end

            menu:addOption("Delete Waypoint", function()
                local cSession = hunting_recorderModule.getSessionSettings()
                if not cSession['waypoints'] then return end
                local newList = {}
                for _, waypoint in ipairs(cSession['waypoints']) do
                    if waypoint.index ~= index then
                        table.insert(newList, waypoint)
                    end
                end
                for i, w in ipairs(newList) do
                    w.index = i
                end
                cSession['waypoints'] = newList
                hunting_recorderModule.setSessionSettings(cSession)
                hunting_recorderModule.saveSessionToDisk(hunting_recorderModule.selectedSessionUid, cSession)

                -- Reload waypoints in UI (chunked to avoid freeze)
                if huntingWaypointsWindow and huntingWaypointsWindow.settings and huntingWaypointsWindow.settings.main and huntingWaypointsWindow.settings.main.waypoints then
                    local waypointsList = huntingWaypointsWindow.settings.main.waypoints.list
                    if waypointsList then
                        waypointsList:destroyChildren()
                    end

                    -- Clear minimap waypoints
                    if huntingWaypointsWindow.map and huntingWaypointsWindow.map.minimap then
                        clearMinimapWaypoints(huntingWaypointsWindow.map.minimap)
                    end

                    -- Sort and use chunked loading
                    local sorted = {}
                    for _, wp in ipairs(newList) do
                        table.insert(sorted, wp)
                    end
                    table.sort(sorted, function(a, b) return (a.index or 0) < (b.index or 0) end)
                    local nextSelected = math.max(1, math.min((index or 1) - 1, #newList))
                    hunting_recorderModule.loadWaypointsChunked(sorted, newList, function()
                        if #newList > 0 then
                            hunting_recorderModule.selectWaypointByIndex(nextSelected)
                        end
                    end)
                end
            end)
            menu:display(mousePos)
        end
        return true
    end

    return widget
end

function hunting_recorderModule.createSpecialAreaEntry(area)
    if not area or not area.position then
        return nil
    end
    if not huntingWaypointsWindow or not huntingWaypointsWindow.settings then
        return nil
    end

    local specialList = huntingWaypointsWindow.settings.main.waypoints.specialList
    if not specialList then
        return nil
    end

    -- Contar filhos antes de criar o novo widget para aplicar cores alternadas
    local visibleIndex = #specialList:getChildren() + 1
    local widget = g_ui.createWidget('MiniBotHuntingRecorderEntry', specialList)
    widget.specialAreaId = area.id
    widget.internalWaypointPosition = area.position
    initializeWidget(widget)

    widget:setText(string.format(
        "%d: (%d, %d, %d) [Special]",
        area.id or 0,
        area.position.x, area.position.y, area.position.z
    ))

    widget:setTooltip(string.format(
        "Special Area %d\nPosition: %d, %d, %d",
        area.id or 0,
        area.position.x, area.position.y, area.position.z
    ))
    
    -- Aplicar cores alternadas (zebra striping) - mesmo que cavebot list
    widget.baseBackgroundColor = visibleIndex % 2 == 0 and "#0a0a0a" or "#12121200"
    widget:setBackgroundColor(widget.baseBackgroundColor)
    if widget.updateOnStates then
        widget:updateOnStates()
    end

    widget.onClick = function()
        for _, c in ipairs(specialList:getChildren()) do
            c.mask:hide()
            c.selectedSpecialArea = false
            -- Atualizar cores
            if c.updateOnStates then
                c:updateOnStates()
            end
        end
        widget.mask:show()
        widget.selectedSpecialArea = true
        widget:focus()

        if widget.internalWaypointPosition then
            huntingWaypointsWindow.map.minimap:setCameraPosition(widget.internalWaypointPosition)
        end
    end

    return widget
end

function hunting_recorderModule.reloadSpecialAreasList()
    if not huntingWaypointsWindow or not huntingWaypointsWindow.settings then
        return
    end

    local specialList = huntingWaypointsWindow.settings.main.waypoints.specialList
    if not specialList then
        return
    end

    specialList:destroyChildren()

    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    hunting_recorderModule.normalizeCavebotData(cavebotData)
    ensureSpecialAreasTable(cavebotData)

    table.sort(cavebotData.specialAreas, function(a, b) return (a.id or 0) < (b.id or 0) end)
    for _, area in ipairs(cavebotData.specialAreas) do
        hunting_recorderModule.createSpecialAreaEntry(area)
    end
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

function hunting_recorderModule.insertWaypointOnPos(waypointPosition, isTeleport, skipTeleportCheck)
    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.waypoints then
        cavebotData.waypoints = {}
    end

    local list = {}
    for _, waypoint in pairs(cavebotData.waypoints) do
        table.insert(list, waypoint)
    end
    local newIndex = #list + 1

    -- Dedup DOOR: o auto-record por evento (onPositionChange) e o timer
    -- (cycleRecord, 300ms) podem gravar no MESMO SQM. Se o ultimo waypoint ja
    -- esta nesta posicao e o caso envolve uma porta, nao duplicar -- apenas
    -- garante que o existente fique tipado como 'door'.
    do
        local lastWp, maxIdx = nil, -1
        for _, wp in ipairs(list) do
            if wp and (wp.index or 0) > maxIdx then
                maxIdx = wp.index or 0
                lastWp = wp
            end
        end
        if lastWp and lastWp.position
           and lastWp.position.x == waypointPosition.x
           and lastWp.position.y == waypointPosition.y
           and lastWp.position.z == waypointPosition.z then
            local lastIsDoor = (type(lastWp.type) == "string" and lastWp.type:lower() == "door")
            local newIsDoor = hunting_recorderModule.tileHasOpenDoor
                              and hunting_recorderModule.tileHasOpenDoor(waypointPosition)
            if lastIsDoor or newIsDoor then
                if newIsDoor and not lastIsDoor then
                    lastWp.type = 'door'
                end
                return
            end
        end
    end

    -- Check if there's a path from previous waypoint to current
    -- If no path found, consider it a teleport
    if not isTeleport and not skipTeleportCheck and newIndex > 1 then
        local previousWaypoint = list[newIndex - 1]
        if previousWaypoint and previousWaypoint.position then
            local prevPos = previousWaypoint.position
            local currentPos = waypointPosition
            
            -- Try to find path from previous to current
            local path, result = g_map.findPathJPS(prevPos, currentPos, 200, 0)
            
            -- If pathfinding fails or returns no path, it's a teleport
            if result ~= PathFindResults.Ok or not path or #path == 0 then
                -- Also check if it's exactly 1 tile away (g_map.findPath ignores 1-tile destinations)
                local dx = math.abs(currentPos.x - prevPos.x)
                local dy = math.abs(currentPos.y - prevPos.y)
                local dz = math.abs(currentPos.z - prevPos.z)
                local dist = math.max(dx, dy)
                
                -- If not exactly 1 tile away on same floor, it's a teleport
                if not (dist == 1 and dz == 0) then
                    isTeleport = true
                end
            end
        end
    end
    if huntingWaypointsWindow ~= nil then
        local lastNode = hunting_recorderModule.getLastNode and hunting_recorderModule.getLastNode() or nil

        if lastNode and lastNode.tilePosition then
            local path = g_map.findPathJPS(lastNode.tilePosition, waypointPosition, 200, 0, true)
            if path and #path > 0 then
                local currentPos = { x = lastNode.tilePosition.x, y = lastNode.tilePosition.y, z = lastNode.tilePosition.z }
                local ignoreNext = false
                for _, dir in ipairs(path) do
                    if dir == 0 then currentPos.y = currentPos.y - 1
                    elseif dir == 1 then currentPos.x = currentPos.x + 1
                    elseif dir == 2 then currentPos.y = currentPos.y + 1
                    elseif dir == 3 then currentPos.x = currentPos.x - 1
                    elseif dir == 4 then currentPos.y = currentPos.y - 1; currentPos.x = currentPos.x + 1
                    elseif dir == 5 then currentPos.x = currentPos.x + 1; currentPos.y = currentPos.y + 1
                    elseif dir == 6 then currentPos.x = currentPos.x - 1; currentPos.y = currentPos.y + 1
                    elseif dir == 7 then currentPos.x = currentPos.x - 1; currentPos.y = currentPos.y - 1 end
                    if not ignoreNext then
                        ignoreNext = true
                        local connector = createNode('connector', { x = currentPos.x, y = currentPos.y, z = currentPos.z })
                        huntingWaypointsWindow.map.minimap:addAlternativeWidget(connector, { x = currentPos.x, y = currentPos.y, z = currentPos.z })
                    else
                        ignoreNext = false
                    end
                end
            end
        end

        -- Add flag/mark to the minimap preview for this waypoint
        local flagIcon = 9  -- Default: walk waypoint
        if isTeleport then
            -- Check next waypoint to determine teleport direction
            local nextWaypoint = list[newIndex + 1]
            if nextWaypoint and nextWaypoint.position then
                if nextWaypoint.position.z > waypointPosition.z then
                    flagIcon = 19  -- Teleport up (stairs up)
                elseif nextWaypoint.position.z < waypointPosition.z then
                    flagIcon = 18  -- Teleport down (stairs down)
                else
                    flagIcon = 15  -- Same floor teleport
                end
            else
                flagIcon = 15  -- No next waypoint, use default teleport icon
            end
        end
        local flagTypeName = isTeleport and 'Teleport' or 'Node'
        local flagDescription = 'Waypoint ' .. newIndex .. ' (' .. waypointPosition.x .. ', ' .. waypointPosition.y .. ', ' .. waypointPosition.z .. ') [' .. flagTypeName .. ']'
        if huntingWaypointsWindow.map.minimap.addFlag then huntingWaypointsWindow.map.minimap:addFlag(waypointPosition, flagIcon, flagDescription, true) end

        -- Update last waypoint position for connector drawing
        lastWaypointPosition = { x = waypointPosition.x, y = waypointPosition.y, z = waypointPosition.z }
    end

    -- Get waypoint type from settings (default: node)
    -- Teleports/stairs always use Stand, normal waypoints use settings
    local waypointType = 'node' -- Default to node (string format)

    -- REGRA DE ALTERNANCIA TEM PRIORIDADE: Ao gravar um stand, o proximo obrigatoriamente e um node
    -- Mesmo que seja detectado como teleport, deve respeitar a alternancia
    local lastWaypointTypeNum = waypointTypeToNumber(lastWaypointType)
    if lastWaypointTypeNum == 1 or lastWaypointType == 'stand' then
        -- Ultimo waypoint foi Stand, entao este DEVE ser Node (independente de isTeleport)
        waypointType = 'node'
    elseif isTeleport then
        -- Teleports/stairs usam Stand (se nao violar regra de alternancia)
        waypointType = 'stand'
    else
        -- Normal waypoints respect the global settings
        local recorderType = safeGetSettingsValue(false, 'recorder_waypoint_type', 'Node')
        if recorderType == 'Stand' then
            waypointType = 'stand'
        end
    end

    -- DOOR: se o tile gravado contem uma porta ABERTA (id na lista CavebotDoors),
    -- marcar como waypoint 'door'. Quando o cavebot rodar e a porta estiver fechada,
    -- a action 'door' abre e atravessa; se ja aberta, apenas anda.
    if hunting_recorderModule.tileHasOpenDoor and hunting_recorderModule.tileHasOpenDoor(waypointPosition) then
        waypointType = 'door'
    end

    local waypoint = {
        position = { x = waypointPosition.x, y = waypointPosition.y, z = waypointPosition.z },
        teleport = isTeleport,
        type = waypointType, -- String format: 'node', 'stand', etc.
        index = newIndex
    }

    -- IMPROVED: Se estamos inserindo um Stand, verificar se existe um Node duplicado no mesmo SQM
    -- Isso remove nodes desnecessarios que foram gravados automaticamente
    if waypointType == 'stand' or waypointTypeToNumber(waypointType) == 1 then
        local removedIndex = nil
        
        -- Verificar waypoint anterior (1 antes) - se for Node no mesmo SQM, remover
        if newIndex > 1 then
            local prevWp = list[newIndex - 1]
            if prevWp and prevWp.position then
                local prevType = prevWp.type
                local isNode = (prevType == 'node' or prevType == 0 or waypointTypeToNumber(prevType) == 0)
                local samePos = (prevWp.position.x == waypointPosition.x and 
                                prevWp.position.y == waypointPosition.y and 
                                prevWp.position.z == waypointPosition.z)
                if isNode and samePos then
                    -- Remover o node anterior duplicado
                    table.remove(list, newIndex - 1)
                    removedIndex = newIndex - 1
                    newIndex = newIndex - 1
                    waypoint.index = newIndex
                end
            end
        end
        
        -- Verificar waypoint seguinte (1 depois) - se for Node no mesmo SQM, remover
        -- Isso so acontece em edicoes, nao em gravacao sequencial
        if not removedIndex and #list >= newIndex then
            local nextWp = list[newIndex]
            if nextWp and nextWp.position then
                local nextType = nextWp.type
                local isNode = (nextType == 'node' or nextType == 0 or waypointTypeToNumber(nextType) == 0)
                local samePos = (nextWp.position.x == waypointPosition.x and 
                                nextWp.position.y == waypointPosition.y and 
                                nextWp.position.z == waypointPosition.z)
                if isNode and samePos then
                    -- Remover o node seguinte duplicado
                    table.remove(list, newIndex)
                    removedIndex = newIndex
                end
            end
        end
        
        -- Reindexar waypoints se algum foi removido
        if removedIndex then
            for i, wp in ipairs(list) do
                wp.index = i
            end
        end
    end

    table.insert(list, waypoint)
    cavebotData.waypoints = list
    hunting_recorderModule.setCurrentCavebotData(cavebotData)

    local widget = g_ui.createWidget('MiniBotHuntingRecorderEntry', huntingWaypointsWindow.settings.main.waypoints.list)
    widget.waypointIndex = newIndex
    initializeWidget(widget)
    -- Register in O(1) lookup table so selectWaypointByIndex works
    hunting_recorderModule.registerWaypointWidget(newIndex, widget)
    widget.internalWaypointPosition = waypointPosition

    -- Get cavebot config for tooltip
    local sessionConfig = cavebotData.config or {}
    local stopAt = sessionConfig.creaturesToStop or 8
    local resumeAt = sessionConfig.creaturesToWalk or 2
    local delayWalk = sessionConfig.walkDelay or 20
    local lure = sessionConfig.lureMode or false

    -- Get waypoint type name
    local typeName = waypointTypeToName(waypointType)

    widget.waypointType = waypointType -- Store type in widget
    widget:setText(string.format(
        "%d: (%d, %d, %d) [%s]",
        newIndex,
        waypointPosition.x, waypointPosition.y, waypointPosition.z,
        typeName
    ))

    widget:setTooltip(string.format(
        "Waypoint %d\nPosition: %d, %d, %d\nType: %s",
        newIndex,
        waypointPosition.x, waypointPosition.y, waypointPosition.z,
        typeName
    ))

    widget.onClick = function()
        for _, c in ipairs(huntingWaypointsWindow.settings.main.waypoints.list:getChildren()) do
            c.mask:hide()
            c.selectedWaypoint = false
            -- Atualizar cores
            if c.updateOnStates then
                c:updateOnStates()
            end
        end
        widget.mask:show()
        widget.selectedWaypoint = true
        widget:focus()
        huntingWaypointsWindow.map.minimap:setCameraPosition(widget.internalWaypointPosition)
        hunting_recorderModule.internalSelectWaypoint(widget, newIndex, true, false)
    end

    widget.onMouseRelease = function(_, mousePos, mouseButton)
        if mouseButton == MouseRightButton then
            local menu = g_ui.createWidget('HelperPopupMenu')
            menu:setGameMenu(true)
            menu:addOption("Select Waypoint", function()
                hunting_recorderModule.internalSelectWaypoint(widget, newIndex, false, false)
            end)
            menu:addOption("Delete Waypoint", function()
                local cavebotData = hunting_recorderModule.getCurrentCavebotData()
                local newList = {}
                for _, w in ipairs(cavebotData.waypoints or {}) do
                    if w.index ~= newIndex then table.insert(newList, w) end
                end
                for i, w in ipairs(newList) do w.index = i end
                cavebotData.waypoints = newList
                hunting_recorderModule.setCurrentCavebotData(cavebotData)
                
                -- Reload waypoints in UI (chunked to avoid freeze)
                huntingWaypointsWindow.settings.main.waypoints.list:destroyChildren()
                if huntingWaypointsWindow.map and huntingWaypointsWindow.map.minimap then
                    clearMinimapWaypoints(huntingWaypointsWindow.map.minimap)
                end

                -- Sort and use chunked loading
                local sorted = {}
                for _, wp in ipairs(newList) do
                    table.insert(sorted, wp)
                end
                table.sort(sorted, function(a, b) return (a.index or 0) < (b.index or 0) end)
                local nextSelected = math.max(1, math.min((newIndex or 1) - 1, #newList))
                hunting_recorderModule.loadWaypointsChunked(sorted, newList, function()
                    if #newList > 0 then
                        hunting_recorderModule.selectWaypointByIndex(nextSelected)
                    end
                end)
            end)
            menu:display(mousePos)
        end
        return true
    end

    hunting_recorderModule.lastPosition = waypointPosition
    lastWaypointType = waypointType -- Atualizar o ultimo tipo gravado

    -- Register waypoint with session config
    g_minibot.registerWalkWaypoint({
        position = waypoint.position,
        creatures = stopAt,
        resume = resumeAt,
        lure = lure,
        speed = lureSpeed,
        delayWalk = delayWalk,
        index = waypoint.index,
        teleport = waypoint.teleport
    })
    
    -- Selecionar o waypoint recém-criado automaticamente
    local finalIndex = waypoint.index
    scheduleEvent(function()
        hunting_recorderModule.selectWaypointByIndex(finalIndex)
    end, 50)
end

-- Sistema de auto-recording com deteccao automatica de tipo de transicao
-- Mantem 3 posicoes em memoria: atual (pos1), anterior (pos2), mais antiga (pos3)
hunting_recorderModule.positionHistory = {
    pos1 = nil, -- Posicao atual
    pos2 = nil, -- Posicao anterior
    pos3 = nil  -- Posicao mais antiga
}

-- Flag para forcar proximo waypoint como NODE apos adicionar um Stand
local forceNextAsNode = false

-- Funcao auxiliar: calcula distancia entre duas posicoes (Manhattan distance - soma de x e y)
local function calculateDistance(pos1, pos2)
    if not pos1 or not pos2 then
        return 0
    end

    local dx = math.abs(pos1.x - pos2.x)
    local dy = math.abs(pos1.y - pos2.y)

    -- Distancia Manhattan (soma de dx e dy)
    return dx + dy
end

local THING_ATTR_FLOOR_CHANGE = 252

-- Funcao auxiliar: verifica se o sqm exige pisar exatamente (teleport/escada)
local function isSpecialStandTile(pos)
    if not pos then
        return false
    end

    local tile = g_map.getTile(pos)
    if not tile then
        return false
    end

    local things = tile:getThings() or {}
    for _, thing in ipairs(things) do
        if thing and thing:isItem() then
            -- Teleports
            if thing.getTeleportDestination then
                local ok, destination = pcall(thing.getTeleportDestination, thing)
                if ok and destination then
                    return true
                end
            end

            -- Floor change (stairs/holes)
            local itemType = g_things.getThingType(thing:getId(), ThingCategoryItem)
            if itemType and itemType:hasAttribute(THING_ATTR_FLOOR_CHANGE) then
                return true
            end
        end
    end

    return false
end

-- Funcao auxiliar: verifica se e possivel alcancar pos1 a partir de pos2 OU pos3
-- Retorna true se deve gravar STAND, false se deve gravar NODE
local function shouldRecordAsStand(pos1, pos2, pos3)
    if not pos1 then
        return false
    end

    -- Se forceNextAsNode esta ativo, SEMPRE gravar como NODE
    if forceNextAsNode then
        return false
    end

    return isSpecialStandTile(pos1)
end

function hunting_recorderModule.cycleRecord()
    if hunting_recorderModule.recordingEvent ~= nil then
        removeEvent(hunting_recorderModule.recordingEvent)
        hunting_recorderModule.recordingEvent = nil
    end

    local player = g_game.getLocalPlayer()
    if player == nil then
        return
    end

    -- Verificar se o player esta com FEAR
    local playerStates = player:getStates()
    if playerStates and bit.band(playerStates, PlayerStates.Feared) ~= 0 then
        -- Desativar auto record
        if huntingWaypointsWindow then
            local buttonsPanel = huntingWaypointsWindow:recursiveGetChildById('buttons')
            if buttonsPanel then
                local autoRecordCheckBox = buttonsPanel:recursiveGetChildById('autoRecordCheckBox')
                if autoRecordCheckBox and autoRecordCheckBox:isChecked() then
                    autoRecordCheckBox.ignoreCallback = true
                    autoRecordCheckBox:setChecked(false)
                    autoRecordCheckBox.ignoreCallback = nil
                    
                    -- Salvar estado do auto record
                    if modules.game_helper and modules.game_helper.setSettingsValue then
                        modules.game_helper.setSettingsValue(false, 'cavebot_auto_record', false)
                    end
                end
                
                -- Parar gravacao se estiver gravando
                local recordingButton = buttonsPanel:recursiveGetChildById('recordingButton')
                if recordingButton and recordingButton:isChecked() then
                    recordingButton.ignoreCallback = true
                    recordingButton:setChecked(false)
                    recordingButton.ignoreCallback = nil
                end
            end
        end
        
        -- Parar o evento de gravacao
        if hunting_recorderModule.recordingEvent ~= nil then
            removeEvent(hunting_recorderModule.recordingEvent)
            hunting_recorderModule.recordingEvent = nil
        end
        
        -- Exibir mensagem na tela por 5 segundos (usando broadcast para maior visibilidade)
        -- Mensagem com mais de 100 caracteres para garantir 5 segundos de exibicao
        local messageText = "FEAR detectado! Auto Record desativado. Volte a posicao e ligue o record manualmente quando estiver pronto."
        modules.game_textmessage.displayBroadcastMessage(messageText)
        
        return
    end

    local currentPos = player:getPosition()
    if not currentPos then
        hunting_recorderModule.recordingEvent = scheduleEvent(hunting_recorderModule.cycleRecord, 300)
        return
    end

    local history = hunting_recorderModule.positionHistory

    -- Primeira posicao: sempre gravar como NODE
    if not history.pos1 then
        history.pos1 = {x = currentPos.x, y = currentPos.y, z = currentPos.z}
        hunting_recorderModule.insertWaypointOnPos(currentPos, false, true)
        hunting_recorderModule.recordingEvent = scheduleEvent(hunting_recorderModule.cycleRecord, 300)
        return
    end

    -- Atualizar historico de posicoes (shift: pos2->pos3, pos1->pos2, current->pos1)
    if history.pos2 then
        history.pos3 = {x = history.pos2.x, y = history.pos2.y, z = history.pos2.z}
    end
    if history.pos1 then
        history.pos2 = {x = history.pos1.x, y = history.pos1.y, z = history.pos1.z}
    end
    history.pos1 = {x = currentPos.x, y = currentPos.y, z = currentPos.z}

    -- Obter ultima posicao gravada para calcular criterios
    local lastRecordedPos = hunting_recorderModule.lastPosition
    local distanceFromLastRecorded = 0
    if lastRecordedPos then
        distanceFromLastRecorded = calculateDistance(currentPos, lastRecordedPos)
    end

    -- Decisao de gravacao: só grava se soma de |dx| + |dy| >= 3
    local shouldRecord = (distanceFromLastRecorded >= 3)

    -- Gravar waypoint se necessario
    if shouldRecord then
        -- Stand apenas em sqm especiais (teleport/escada)
        local isStand = shouldRecordAsStand(currentPos, history.pos2, history.pos3)

        hunting_recorderModule.insertWaypointOnPos(currentPos, isStand, true)
        hunting_recorderModule.lastPosition = {x = currentPos.x, y = currentPos.y, z = currentPos.z}

        -- Se gravou um STAND, forcar proximo waypoint como NODE e limpar historico
        if isStand then
            forceNextAsNode = true
            history.pos2 = nil
            history.pos3 = nil
        else
            -- Se gravou um NODE, resetar flag
            forceNextAsNode = false
        end
    end

    hunting_recorderModule.recordingEvent = scheduleEvent(hunting_recorderModule.cycleRecord, 300)
end

function hunting_recorderModule.onRecordingChange(widget)
    modules.game_textmessage.displayGameMessage("Recording button clicked!")

    if not(widget:isChecked()) then
        -- Parando gravacao: gravar ultima posicao antes de parar
        local player = g_game.getLocalPlayer()
        if player then
            local currentPos = player:getPosition()
            local lastRecordedPos = hunting_recorderModule.lastPosition
            local history = hunting_recorderModule.positionHistory

            -- Se a posicao atual e diferente da ultima gravada, gravar a posicao final
            if lastRecordedPos and (currentPos.x ~= lastRecordedPos.x or currentPos.y ~= lastRecordedPos.y or currentPos.z ~= lastRecordedPos.z) then
                local isStand = shouldRecordAsStand(currentPos, history.pos2, history.pos3)
                hunting_recorderModule.insertWaypointOnPos(currentPos, isStand, true)
            end
        end

        -- Resetar historico de posicoes
        hunting_recorderModule.positionHistory = {
            pos1 = nil,
            pos2 = nil,
            pos3 = nil
        }

        -- Resetar rastreamento do ultimo tipo de waypoint
        lastWaypointType = nil

        -- Resetar flag de forcar NODE
        forceNextAsNode = false

        if hunting_recorderModule.recordingEvent ~= nil then
            removeEvent(hunting_recorderModule.recordingEvent)
            hunting_recorderModule.recordingEvent = nil
        end
        return
    end

    if hunting_recorderModule.recordingEvent ~= nil then
        removeEvent(hunting_recorderModule.recordingEvent)
        hunting_recorderModule.recordingEvent = nil
    end

    -- If cavebot is enabled, disable it first
    if huntingWaypointsWindow then
        local enableCaveBot = huntingWaypointsWindow:recursiveGetChildById('enableCaveBot')
        if enableCaveBot and enableCaveBot:isChecked() then
            enableCaveBot:setChecked(false)
            modules.game_textmessage.displayGameMessage("Cavebot disabled to start recording")
        end
    end

    -- No longer requires session, can always record

    local player = g_game.getLocalPlayer()
    if not player then
        modules.game_textmessage.displayFailureMessage("Player not found.")
        widget.ignoreCallback = true
        widget:setChecked(false)
        widget.ignoreCallback = nil
        return
    end

    -- Resetar historico de posicoes ao iniciar gravacao
    hunting_recorderModule.positionHistory = {
        pos1 = nil,
        pos2 = nil,
        pos3 = nil
    }

    -- Resetar rastreamento do ultimo tipo de waypoint ao iniciar gravacao
    lastWaypointType = nil

    -- Resetar flag de forcar NODE
    forceNextAsNode = false

    local currentPos = player:getPosition()
    hunting_recorderModule.lastPosition = currentPos

    -- Adicionar primeiro waypoint na posicao atual
    hunting_recorderModule.insertWaypointOnPos(currentPos, false, true)

    hunting_recorderModule.recordingEvent = scheduleEvent(hunting_recorderModule.cycleRecord, 2000)
    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    local cavebotName = (cavebotData and cavebotData.name) or "Cavebot"
    modules.game_textmessage.displayGameMessage("Recording started for " .. cavebotName .. " - First waypoint added")
end

-- Toggle Cavebot with mutual exclusivity with recorder
function hunting_recorderModule.toggleCavebot(widget)
    if not widget then
        return
    end

    -- If cavebot is being enabled and recorder is on, disable recorder first
    if widget:isChecked() then
        if huntingWaypointsWindow then
            local recordingButton = huntingWaypointsWindow:recursiveGetChildById('recordingButton')
            if recordingButton and recordingButton:isChecked() then
                recordingButton:setChecked(false)
                modules.game_textmessage.displayGameMessage("Recording disabled to enable cavebot")
            end
        end
    end

    -- Call the original toggleCavebotHelper function
    if modules.game_helper and modules.game_helper.toggleCavebotHelper then
        modules.game_helper.toggleCavebotHelper(widget)
    end
end

-- Auto Record checkbox handler
function hunting_recorderModule.onAutoRecordChange(widget)
    if widget:isChecked() then
        modules.game_textmessage.displayGameMessage("Auto Record enabled.")
        -- Save auto record state
        if modules.game_helper and modules.game_helper.setSettingsValue then
            modules.game_helper.setSettingsValue(false, 'cavebot_auto_record', true)
        end
    else
        modules.game_textmessage.displayGameMessage("Auto Record disabled.")
        -- Save auto record state
        if modules.game_helper and modules.game_helper.setSettingsValue then
            modules.game_helper.setSettingsValue(false, 'cavebot_auto_record', false)
        end
    end
end

function hunting_recorderModule.loadSessionConfigToUI()
    if not huntingWaypointsWindow or not huntingWaypointsWindow.settings then
        return
    end

    -- Get session-level configuration
    local cSession = hunting_recorderModule.getSessionSettings()
    local sessionConfig = cSession['config'] or {}

    -- Initialize config if it doesn't exist
      if not cSession['config'] then
          cSession['config'] = {
              creaturesToStop = 8,
              creaturesToWalk = 2,
              lureMode = true,
              lureSpeed = 5,
              lureDebug = false,
              lureCheckRangeX = 6,
              lureCheckRangeY = 4,
              walkDelay = 20,
              avoidTrap = true,
              trapDistance = 1,
              creaturesToAvoid = 7
          }
        sessionConfig = cSession['config']
    end

    -- Load stopAt (creaturesToStop)
    if huntingWaypointsWindow.settings.main.selected.stopAt then
        local stopAtWidget = huntingWaypointsWindow.settings.main.selected.stopAt
        stopAtWidget:setCurrentOption(tostring(sessionConfig.creaturesToStop or 8))
    end

    -- Load resumeAt (creaturesToWalk)
    if huntingWaypointsWindow.settings.main.selected.resumeAt then
        local resumeAtWidget = huntingWaypointsWindow.settings.main.selected.resumeAt
        resumeAtWidget:setCurrentOption(tostring(sessionConfig.creaturesToWalk or 2))
    end

    -- Load walkDelay
    if huntingWaypointsWindow.settings.main.selected.delayWalk then
        local delayWalkWidget = huntingWaypointsWindow.settings.main.selected.delayWalk
        delayWalkWidget:setCurrentOption(tostring(sessionConfig.walkDelay or 20))
    end

    -- Load lureMode
    if huntingWaypointsWindow.settings.main.selected.lure then
        local lureWidget = huntingWaypointsWindow.settings.main.selected.lure
        lureWidget.onCheckChange = nil
        lureWidget:setChecked(sessionConfig.lureMode or false)
        lureWidget.onCheckChange = function()
            local cSession2 = hunting_recorderModule.getSessionSettings()
            if not cSession2['config'] then cSession2['config'] = {} end

            local newValue = lureWidget:isChecked()
            cSession2['config'].lureMode = newValue

            hunting_recorderModule.setSessionSettings(cSession2)
            hunting_recorderModule.saveSessionToDisk(hunting_recorderModule.selectedSessionUid, cSession2)

            -- Update walker config in real-time
            if cavebotWalker and cavebotWalker.updateConfig then
                cavebotWalker.updateConfig({lureMode = newValue})
            end

            local selectedIndex = g_minibot.getCurrentWalkIndex()
            hunting_recorderModule.reloadInternalModule()
            if not g_minibot.isModuleToggle(5) then
                g_minibot.setCurrentWalkIndex(selectedIndex)
            end

            -- Update all waypoint labels
            hunting_recorderModule.refreshAllWaypointLabels()
        end
    end

    -- Load avoidTrap
    if huntingWaypointsWindow.settings.main.selected.avoidTrap then
        local avoidTrapWidget = huntingWaypointsWindow.settings.main.selected.avoidTrap
        avoidTrapWidget.onCheckChange = nil
        avoidTrapWidget:setChecked(sessionConfig.avoidTrap or false)
        avoidTrapWidget.onCheckChange = function()
            local cSession2 = hunting_recorderModule.getSessionSettings()
            if not cSession2['config'] then cSession2['config'] = {} end

            local newValue = avoidTrapWidget:isChecked()
            cSession2['config'].avoidTrap = newValue

            hunting_recorderModule.setSessionSettings(cSession2)
            hunting_recorderModule.saveSessionToDisk(hunting_recorderModule.selectedSessionUid, cSession2)

            -- Update walker config in real-time
            if cavebotWalker and cavebotWalker.updateConfig then
                cavebotWalker.updateConfig({avoidTrap = newValue})
            end

            hunting_recorderModule.reloadInternalModule()

            -- Update all waypoint labels
            hunting_recorderModule.refreshAllWaypointLabels()
        end
    end

    -- Load trapDistance
    if huntingWaypointsWindow.settings.main.selected.trapDistance then
        local trapDistanceWidget = huntingWaypointsWindow.settings.main.selected.trapDistance
        trapDistanceWidget:setCurrentOption(tostring(sessionConfig.trapDistance or 1))
    end

    -- Load creaturesToAvoid
    if huntingWaypointsWindow.settings.main.selected.creaturesToAvoid then
        local creaturesToAvoidWidget = huntingWaypointsWindow.settings.main.selected.creaturesToAvoid
        creaturesToAvoidWidget:setCurrentOption(tostring(sessionConfig.creaturesToAvoid or 7))
    end
end


function hunting_recorderModule.onSearchSessionChange(widget)
    if not huntingWaypointsWindow or not huntingWaypointsWindow.sessions or not huntingWaypointsWindow.sessions.list then
        return
    end

    if hunting_recorderModule._searchEvent then
        removeEvent(hunting_recorderModule._searchEvent)
        hunting_recorderModule._searchEvent = nil
    end

    hunting_recorderModule._searchEvent = scheduleEvent(function()
        if not huntingWaypointsWindow or not huntingWaypointsWindow.sessions or not huntingWaypointsWindow.sessions.list then
            return
        end

        local search = widget:getText():lower():trim()

        for _, child in ipairs(huntingWaypointsWindow.sessions.list:getChildren()) do
            local name = child:getText():lower()
            local match = (search == '' or name:find(search, 1, true))
            child:setVisible(match)
        end
    end, 200)
end

function hunting_recorderModule.onGameStart()
    hunting_recorderModule.ensureDirectories()
    hunting_recorderModule.loadSessionList()

    -- Removed auto-opening of cavebots manager - user must click button manually
    -- local sSessions = safeGetSettingsValue(false, 'sessions', {})
    -- if not sSessions or next(sSessions) == nil then
    --     hunting_recorderModule.onClickNewSession()
    -- end

    scheduleEvent(function()
        hunting_recorderModule.resumeCavebotIfNeeded()
    end, 500)
end

connect(g_game, { onGameStart = hunting_recorderModule.onGameStart })

local function createPosition(x, y, z)
    local pos = { x = x, y = y, z = z }
    setmetatable(pos, { __index = Position })
    return pos
end

local function getCardinalDirection(fromPos, toPos)
    local dx = toPos.x - fromPos.x
    local dy = toPos.y - fromPos.y

    if math.abs(dx) > math.abs(dy) then
        if dx > 0 then return 1 elseif dx < 0 then return 3 end
    else
        if dy > 0 then return 2 elseif dy < 0 then return 0 end
    end
    return nil
end

local function stepTo(targetPos, callback)
    local player = g_game.getLocalPlayer()
    if not player then return end
    local startPos = player:getPosition()
    if not startPos then return end

    if startPos.z ~= targetPos.z then
        scheduleEvent(function()
            callback()
        end, 1000)
        return
    end

    local success = player:autoWalk({x = targetPos.x, y = targetPos.y, z = targetPos.z})
    if not success then
        callback()
        return
    end

    local function waitUntilReached()
        if not hunting_recorderModule.walking then
            return
        end

        local newPos = player:getPosition()
        local dist = math.max(math.abs(newPos.x - targetPos.x), math.abs(newPos.y - targetPos.y))

        if newPos.z == targetPos.z and dist <= 1 then
            callback()
            return
        end

        scheduleEvent(waitUntilReached, 150)
    end

    waitUntilReached()
end


function hunting_recorderModule.startWalk()
    if _G.hotkeyHelperStatus ~= true then
        return
    end

    if hunting_recorderModule.walking then
        return
    end

    -- Check if blocked by death limit
    if deathLimitBlocked then
        -- Get config to show popup again
        local cavebotData = hunting_recorderModule.getCurrentCavebotData()
        local deathsToDisable = (cavebotData and cavebotData.config and cavebotData.config.deathsToDisable) or 0
        hunting_recorderModule.showDeathLimitPopup(sessionDeathCount, deathsToDisable)
        return
    end

    -- Reset death count when starting cavebot (only if not blocked)
    hunting_recorderModule.resetDeathCount()

    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    hunting_recorderModule.normalizeCavebotData(cavebotData)
    local waypointsTable = (cavebotData and cavebotData.waypoints) or {}
    
    -- Converter waypoints de tabela para array ordenado
    local waypoints = {}
    if waypointsTable then
        for _, waypoint in pairs(waypointsTable) do
            table.insert(waypoints, waypoint)
        end
        table.sort(waypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)
    end
    
    if not waypoints or #waypoints == 0 then
        modules.game_textmessage.displayFailureMessage("No waypoints configured. Add waypoints before starting.")
        return
    end

    -- Get cavebot config
    local sessionConfig = cavebotData.config or {}
    
    -- Verificar checkbox "Start from nearest"
    local startFromNearest = true
    local startWaypointIndex = 1
    if huntingWaypointsWindow then
        local buttonsPanel = huntingWaypointsWindow:recursiveGetChildById('buttons')
        if buttonsPanel then
            local startFromNearestCheckBox = buttonsPanel:recursiveGetChildById('startFromNearestCheckBox')
            if startFromNearestCheckBox then
                startFromNearest = startFromNearestCheckBox:isChecked()
            end
            
            -- Se nao for start from nearest, encontrar waypoint selecionado
            if not startFromNearest then
                local waypointsList = huntingWaypointsWindow.settings and huntingWaypointsWindow.settings.main and huntingWaypointsWindow.settings.main.waypoints and huntingWaypointsWindow.settings.main.waypoints.list
                if waypointsList then
                    local foundSelected = false
                    local selectedWaypointIndex = nil
                    for _, widget in ipairs(waypointsList:getChildren()) do
                        if widget.selectedWaypoint and widget.waypointIndex then
                            selectedWaypointIndex = widget.waypointIndex
                            foundSelected = true
                            break
                        end
                    end
                    -- Se encontrou waypoint selecionado, mapear para o indice no array ordenado
                    if foundSelected and selectedWaypointIndex then
                        for i, waypoint in ipairs(waypoints) do
                            if waypoint.index == selectedWaypointIndex then
                                startWaypointIndex = i
                                break
                            end
                        end
                    else
                        -- Se nenhum waypoint selecionado, usar o primeiro
                        startWaypointIndex = 1
                    end
                end
            end
        end
    end

    -- Prepare walker configuration
    local walkerConfig = {
        creaturesToStop = sessionConfig.creaturesToStop or 8,
        creaturesToWalk = sessionConfig.creaturesToWalk or 2,
        lureMode = sessionConfig.lureMode or false,
        lureSpeed = sessionConfig.lureSpeed or 5,
        lureDebug = sessionConfig.lureDebug or false,
        lureCheckRangeX = math.min(6, sessionConfig.lureCheckRangeX or 6),
        lureCheckRangeY = math.min(4, sessionConfig.lureCheckRangeY or 4),
        walkDelay = sessionConfig.walkDelay or 20,
        walkMode = sessionConfig.walkMode or "walk",
        mapClick = (sessionConfig.walkMode or "walk") == "click",
        stepDelay = 150,
        avoidTrap = sessionConfig.avoidTrap or false,
        trapDistance = sessionConfig.trapDistance or 1,
        creaturesToAvoid = sessionConfig.creaturesToAvoid or 7,
        ignoredCreatures = sessionConfig.ignoredCreatures or {},
        nodeDistance = sessionConfig.nodeDistance or 2,
        stopToKillDistance = sessionConfig.stopToKillDistance or 2,
        stopToKillMaxWait = sessionConfig.stopToKillMaxWait or 60000,
        finishKillMobCount = sessionConfig.finishKillMobCount or 0,
        finishKillHpPct = sessionConfig.finishKillHpPct or 30,
        startFromNearest = startFromNearest,
        startWaypointIndex = startWaypointIndex,
        specialAreas = cavebotData.specialAreas or {},
        staminaToLeave = sessionConfig.staminaToLeave or 39,
        staminaToReturn = sessionConfig.staminaToReturn or 42,
        capToLeave = sessionConfig.capToLeave or 500,
        deathsToDisable = sessionConfig.deathsToDisable or 0,
    }

    -- Prepare callbacks for UI feedback
    local walkerCallbacks = {
        onWaypointChanged = function(index)
            -- Update widget selection + flag icons (fast O(1) operations)
            if hunting_recorderModule.onWalkToNextNode then
                hunting_recorderModule.onWalkToNextNode(index)
            end
            hunting_recorderModule.updateWaypointFlagIcons(index)
            -- Debounce debug display updates (heavy operations)
            hunting_recorderModule.scheduleDebugPosUpdate()
        end,
        onPauseByCreatures = function(count)
            modules.game_textmessage.displayGameMessage(
                string.format("[Cavebot] Paused - %d creatures nearby", count)
            )
        end,
        onResumeWalking = function()
            modules.game_textmessage.displayGameMessage("[Cavebot] Resuming walk")
        end,
        onPathFailed = function(waypointIndex)
            -- modules.game_textmessage.displayGameMessage(
            --     string.format("[Cavebot] Cannot reach waypoint %d, trying next", waypointIndex)
            -- )
        end,
        onLoopComplete = function()
            -- modules.game_textmessage.displayGameMessage("[Cavebot] Restarting waypoints loop")
        end
    }

    -- Start the walker
    hunting_recorderModule.walking = true
    local success = cavebotWalker.start(waypoints, walkerConfig, walkerCallbacks)

       if not success then
           hunting_recorderModule.walking = false
           modules.game_textmessage.displayGameMessage("[Cavebot] Failed to start walker")
       else
           -- Track start time (only if user manually started, not on auto-restart)
           if _G.cavebotManualStop then
               _G.cavebotStartTime = os.time()
               _G.cavebotManualStop = false
               print("[Cavebot] Usuario iniciou cavebot - iniciando cronometro")
           end

           -- Auto show debug popup when cavebot starts
           if modules.game_helper and modules.game_helper.updateDebugPopupVisibility then
               modules.game_helper.updateDebugPopupVisibility()
           end

           -- Update flag icons to show starting waypoint
           local startIndex = cavebotWalker.getCurrentWaypointIndex()
           if startIndex then
               hunting_recorderModule.updateWaypointFlagIcons(startIndex)
           end
           -- Update debug POS display with a small delay to ensure walker is fully initialized
           scheduleEvent(function()
               hunting_recorderModule.updateDebugPos()
           end, 100)
       end
end

function hunting_recorderModule.stopWalk(isAutomaticRestart)
    if hunting_recorderModule.walking then
        -- Mark as manual stop apenas se NAO for restart automatico
        if not isAutomaticRestart then
            _G.cavebotManualStop = true
            print("[Cavebot] Usuario parou cavebot - parando cronometro")

            -- Auto hide debug popup when cavebot stops
            if modules.game_helper and modules.game_helper.updateDebugPopupVisibility then
                modules.game_helper.updateDebugPopupVisibility()
            end
        else
            print("[Cavebot] Restart automatico - cronometro continua rodando")
        end

        hunting_recorderModule.walking = false
        cavebotWalker.stop()
        -- Reset all flags to their default icons (no current waypoint)
        -- Use full refresh only on stop (not performance critical - happens once)
        hunting_recorderModule.updateAllWaypointFlagIcons()
    end
end

-- Expose creature count from walker for UI updates
function hunting_recorderModule.getCreatureCount()
    if cavebotWalker and cavebotWalker.getCreatureCount then
        return cavebotWalker.getCreatureCount()
    end
    return 0
end

-- Display waypoints on the minimap
-- Display waypoints on minimap - uses chunked loading for large lists
function hunting_recorderModule.displayWaypointsOnMap(waypoints)
    if not huntingWaypointsWindow or not huntingWaypointsWindow.map or not huntingWaypointsWindow.map.minimap then
        return
    end

    if not waypoints or #waypoints == 0 then
        return
    end

    -- Count waypoints
    local count = 0
    for _ in pairs(waypoints) do count = count + 1 end

    -- For large lists (>100 waypoints), use chunked async version
    if count > 100 then
        hunting_recorderModule.displayWaypointsOnMapChunked(waypoints)
        return
    end

    -- Small lists: process synchronously (original behavior for responsiveness)
    local minimap = huntingWaypointsWindow.map.minimap
    local lastPosition = nil

    -- Ordenar waypoints por indice
    local sortedWaypoints = {}
    for _, waypoint in pairs(waypoints) do
        table.insert(sortedWaypoints, waypoint)
    end
    table.sort(sortedWaypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)

    for i, waypoint in ipairs(sortedWaypoints) do
        if waypoint and waypoint.position then
            local pos = waypoint.position
            local isTeleport = waypoint.teleport or false

            -- Adicionar conectores entre waypoints
            if lastPosition then
                local path = g_map.findPathJPS(lastPosition, pos, 200, 0, true)
                if path and #path > 0 then
                    local currentPos = { x = lastPosition.x, y = lastPosition.y, z = lastPosition.z }
                    local ignoreNext = false
                    for _, dir in ipairs(path) do
                        if dir == 0 then currentPos.y = currentPos.y - 1
                        elseif dir == 1 then currentPos.x = currentPos.x + 1
                        elseif dir == 2 then currentPos.y = currentPos.y + 1
                        elseif dir == 3 then currentPos.x = currentPos.x - 1
                        elseif dir == 4 then currentPos.y = currentPos.y - 1; currentPos.x = currentPos.x + 1
                        elseif dir == 5 then currentPos.x = currentPos.x + 1; currentPos.y = currentPos.y + 1
                        elseif dir == 6 then currentPos.x = currentPos.x - 1; currentPos.y = currentPos.y + 1
                        elseif dir == 7 then currentPos.x = currentPos.x - 1; currentPos.y = currentPos.y - 1 end
                        if not ignoreNext then
                            ignoreNext = true
                            local connector = createNode('connector', { x = currentPos.x, y = currentPos.y, z = currentPos.z })
                            minimap:addAlternativeWidget(connector, { x = currentPos.x, y = currentPos.y, z = currentPos.z })
                        else
                            ignoreNext = false
                        end
                    end
                end
            end

            -- Determinar icone do waypoint
            local flagIcon = 9  -- Default: walk waypoint
            if isTeleport then
                -- Verificar proximo waypoint para determinar direcao do teleport
                local nextWaypoint = sortedWaypoints[i + 1]
                if nextWaypoint and nextWaypoint.position then
                    if nextWaypoint.position.z > pos.z then
                        flagIcon = 19  -- Teleport up (stairs up)
                    elseif nextWaypoint.position.z < pos.z then
                        flagIcon = 18  -- Teleport down (stairs down)
                    else
                        flagIcon = 15  -- Same floor teleport
                    end
                else
                    flagIcon = 15  -- No next waypoint, use default teleport icon
                end
            end
            local specialFlagIcon = getSpecialActionFlagIcon(waypoint.type)
            if specialFlagIcon then
                flagIcon = specialFlagIcon
            end

            local flagDescription = 'Waypoint ' .. (waypoint.index or i) .. ' (' .. pos.x .. ', ' .. pos.y .. ', ' .. pos.z .. ') [' .. waypointTypeToName(waypoint.type) .. ']'
            if minimap.addFlag then minimap:addFlag(pos, flagIcon, flagDescription, true) end

            lastPosition = { x = pos.x, y = pos.y, z = pos.z }
        end
    end
end

-- Track previous waypoint index for incremental flag updates
local previousFlagWaypointIndex = nil

-- Helper to get flag icon for a waypoint
local function getWaypointFlagIcon(waypoint, waypointIndex, waypoints, isCurrent)
    if isCurrent then
        return 0  -- Current waypoint (green flag)
    end
    local specialFlagIcon = getSpecialActionFlagIcon(waypoint.type)
    if specialFlagIcon then
        return specialFlagIcon
    end
    local isTeleport = waypoint.teleport or false
    if isTeleport then
        local nextWaypoint = waypoints[waypointIndex + 1]
        if nextWaypoint and nextWaypoint.position then
            if nextWaypoint.position.z > waypoint.position.z then
                return 19
            elseif nextWaypoint.position.z < waypoint.position.z then
                return 18
            else
                return 15
            end
        else
            return 15
        end
    end
    return 9  -- Default: walk waypoint
end

-- Update waypoint flag icons on the minimap
-- OPTIMIZED: Only updates the previous and current waypoint flags (O(1) instead of O(n))
function hunting_recorderModule.updateWaypointFlagIcons(currentWaypointIndex)
    if not huntingWaypointsWindow or not huntingWaypointsWindow.map or not huntingWaypointsWindow.map.minimap then
        return
    end

    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData or not cavebotData.waypoints then
        return
    end

    local minimap = huntingWaypointsWindow.map.minimap
    local waypoints = cavebotData.waypoints

    -- Reset previous waypoint flag to its normal icon
    if previousFlagWaypointIndex and previousFlagWaypointIndex ~= currentWaypointIndex then
        local prevWp = waypoints[previousFlagWaypointIndex]
        if prevWp and prevWp.position then
            local pos = prevWp.position
            if minimap.removeFlag then minimap:removeFlag(pos) end
            local flagIcon = getWaypointFlagIcon(prevWp, previousFlagWaypointIndex, waypoints, false)
            local flagDescription = 'Waypoint ' .. previousFlagWaypointIndex .. ' (' .. pos.x .. ', ' .. pos.y .. ', ' .. pos.z .. ') [' .. waypointTypeToName(prevWp.type) .. ']'
            if minimap.addFlag then minimap:addFlag(pos, flagIcon, flagDescription, true) end
        end
    end

    -- Set current waypoint flag to green
    if currentWaypointIndex then
        local currentWp = waypoints[currentWaypointIndex]
        if currentWp and currentWp.position then
            local pos = currentWp.position
            if minimap.removeFlag then minimap:removeFlag(pos) end
            local flagDescription = '[CURRENT] Waypoint ' .. currentWaypointIndex .. ' (' .. pos.x .. ', ' .. pos.y .. ', ' .. pos.z .. ') [' .. waypointTypeToName(currentWp.type) .. ']'
            if minimap.addFlag then minimap:addFlag(pos, 0, flagDescription, true) end
        end
    end

    -- Track for next call
    previousFlagWaypointIndex = currentWaypointIndex
end

-- Reset the current (green) waypoint flag back to normal on stop
-- Only updates the one previously-green flag instead of iterating all waypoints
function hunting_recorderModule.updateAllWaypointFlagIcons()
    if not huntingWaypointsWindow or not huntingWaypointsWindow.map or not huntingWaypointsWindow.map.minimap then
        return
    end

    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData or not cavebotData.waypoints then
        return
    end

    local minimap = huntingWaypointsWindow.map.minimap
    local waypoints = cavebotData.waypoints

    -- Only reset the previously highlighted waypoint back to normal
    if previousFlagWaypointIndex then
        local prevWp = waypoints[previousFlagWaypointIndex]
        if prevWp and prevWp.position then
            local pos = prevWp.position
            if minimap.removeFlag then minimap:removeFlag(pos) end
            local flagIcon = getWaypointFlagIcon(prevWp, previousFlagWaypointIndex, waypoints, false)
            local flagDescription = 'Waypoint ' .. previousFlagWaypointIndex .. ' (' .. pos.x .. ', ' .. pos.y .. ', ' .. pos.z .. ') [' .. waypointTypeToName(prevWp.type) .. ']'
            if minimap.addFlag then minimap:addFlag(pos, flagIcon, flagDescription, true) end
        end
    end
    previousFlagWaypointIndex = nil
end

-- Forward declarations for helper functions
local saveCavebotToFile
local loadCavebotFromFile
local ensureCavebotsDirectory

function hunting_recorderModule.onWalkModeToggle(widget, otherId)
    if not widget or widget.ignoreCallback then
        return
    end

    local parent = widget:getParent()
    if not parent then
        return
    end

    local other = parent:recursiveGetChildById(otherId)
    if not other then
        return
    end

    if widget:isChecked() then
        other.ignoreCallback = true
        other:setChecked(false)
        other.ignoreCallback = nil
    else
        if not other:isChecked() then
            widget.ignoreCallback = true
            widget:setChecked(true)
            widget.ignoreCallback = nil
        end
    end
end

-- Populate a cavebot "force preset" combo with every preset slot of a module
-- type ("targeting" / "shooter"). First option is always "(do nothing)" with an
-- empty data value; the saved preset (slot name) is selected by data.
local function populateForcePresetCombo(combo, moduleType, savedPreset)
    if not combo then
        return
    end
    if combo.clearOptions then
        combo:clearOptions()
    end
    combo:addOption("(do nothing)", "")

    if ensureModulePresetConfig then
        pcall(ensureModulePresetConfig, moduleType)
    end

    local names = {}
    if getSortedModulePresetNames then
        names = getSortedModulePresetNames(moduleType) or {}
    end
    for _, name in ipairs(names) do
        local uiName = name
        if getModulePresetUiName then
            uiName = getModulePresetUiName(moduleType, name)
        end
        combo:addOption(uiName, name)
    end

    local target = tostring(savedPreset or "")
    if combo.setCurrentOptionByData then
        combo:setCurrentOptionByData(target, true)
    end
end

function modules.game_helper.selectCavebotSettingsTab(tabId)
    if not cavebotSettingsWindow or cavebotSettingsWindow:isDestroyed() then
        return
    end
    if tabId ~= 'movement' and tabId ~= 'combat' and tabId ~= 'presets' then
        tabId = 'movement'
    end
    local movementPanel = cavebotSettingsWindow:recursiveGetChildById('movementTabPanel')
    local combatPanel = cavebotSettingsWindow:recursiveGetChildById('combatTabPanel')
    local presetsPanel = cavebotSettingsWindow:recursiveGetChildById('presetsTabPanel')
    local tabMov = cavebotSettingsWindow:recursiveGetChildById('tabMovement')
    local tabCombat = cavebotSettingsWindow:recursiveGetChildById('tabCombat')
    local tabPre = cavebotSettingsWindow:recursiveGetChildById('tabPresets')
    if movementPanel then movementPanel:setVisible(tabId == 'movement') end
    if combatPanel then combatPanel:setVisible(tabId == 'combat') end
    if presetsPanel then presetsPanel:setVisible(tabId == 'presets') end
    if tabMov then tabMov:setChecked(tabId == 'movement') end
    if tabCombat then tabCombat:setChecked(tabId == 'combat') end
    if tabPre then tabPre:setChecked(tabId == 'presets') end
end


function hunting_recorderModule.openCavebotSettings()
    -- No longer requires session, can always open settings

    if cavebotSettingsWindow and not cavebotSettingsWindow:isDestroyed() then
        cavebotSettingsWindow:destroy()
        cavebotSettingsWindow = nil
        return
    end

    local rootWidget = g_ui.getRootWidget()
    if not rootWidget then
        modules.game_textmessage.displayFailureMessage(htr("Failed to get root widget."))
        return
    end

    local window = g_ui.loadUI("/mods/game_helper/styles/cavebot_settings.otui", rootWidget)
    if not window then
        modules.game_textmessage.displayFailureMessage(htr("Failed to load settings window."))
        return
    end

    cavebotSettingsWindow = window
    window.onDestroy = function()
        cavebotSettingsWindow = nil
    end

    window:show()
    window:raise()
    window:focus()
    if _G.helperModalEnter then _G.helperModalEnter(window) end

    -- Load current cavebot config
    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    local sessionConfig = cavebotData.config or {}

    -- Initialize config if it doesn't exist
      if not cavebotData.config then
          cavebotData.config = {
              nodeDistance = 2,
              stopToKillDistance = 2,
              creaturesToStop = 8,
              creaturesToWalk = 2,
              lureMode = true,
              lureSpeed = 5,
              lureDebug = false,
              lureCheckRangeX = 6,
              lureCheckRangeY = 4,
              walkDelay = 20,
              walkMode = "walk",
              avoidTrap = true,
              trapDistance = 1,
              creaturesToAvoid = 7,
              ignoredCreatures = {},
              startFromNearest = true,
            debugPos = false,
            debugPath = false
        }
        sessionConfig = cavebotData.config
        hunting_recorderModule.setCurrentCavebotData(cavebotData)
    end
    
    -- Ensure new config fields exist (for backward compatibility)
      if sessionConfig.startFromNearest == nil then
          sessionConfig.startFromNearest = true
      end
      if sessionConfig.debugPos == nil then
          sessionConfig.debugPos = false
      end
      if sessionConfig.debugPath == nil then
          sessionConfig.debugPath = false
      end
      if sessionConfig.walkMode == nil then
          sessionConfig.walkMode = "walk"
      end
      if sessionConfig.lureDebug == nil then
          sessionConfig.lureDebug = false
      end
      sessionConfig.lureCheckRangeX = math.min(6, sessionConfig.lureCheckRangeX or 6)
      sessionConfig.lureCheckRangeY = math.min(4, sessionConfig.lureCheckRangeY or 4)

    -- Initialize ignoredCreatures if it doesn't exist
    if not sessionConfig.ignoredCreatures then
        sessionConfig.ignoredCreatures = {}
    end

    -- Load values into UI
    local panel = window:recursiveGetChildById('settingsPanel')
      if panel then
        -- Walker Settings
        local nodeDistanceWidget = panel:recursiveGetChildById('nodeDistance')
        if nodeDistanceWidget then
            local value = tostring(sessionConfig.nodeDistance or 2)
            nodeDistanceWidget:setText(value)
            nodeDistanceWidget.lastValidValue = value
        end
        local stopToKillDistWidget = panel:recursiveGetChildById('stopToKillDistance')
        if stopToKillDistWidget then
            local value = tostring(sessionConfig.stopToKillDistance or 2)
            stopToKillDistWidget:setText(value)
            stopToKillDistWidget.lastValidValue = value
        end
        local stopAtWidget = panel:recursiveGetChildById('stopAt')
        if stopAtWidget then
            local value = tostring(sessionConfig.creaturesToStop or 8)
            stopAtWidget:setText(value)
            stopAtWidget.lastValidValue = value
        end
        local resumeAtWidget = panel:recursiveGetChildById('resumeAt')
        if resumeAtWidget then
            local value = tostring(sessionConfig.creaturesToWalk or 2)
            resumeAtWidget:setText(value)
            resumeAtWidget.lastValidValue = value
        end
        local finishKillCountWidget = panel:recursiveGetChildById('finishKillMobCount')
        if finishKillCountWidget then
            local value = tostring(sessionConfig.finishKillMobCount or 0)
            finishKillCountWidget:setText(value)
            finishKillCountWidget.lastValidValue = value
        end
        local finishKillHpWidget = panel:recursiveGetChildById('finishKillHpPct')
        if finishKillHpWidget then
            local value = tostring(sessionConfig.finishKillHpPct or 30)
            finishKillHpWidget:setText(value)
            finishKillHpWidget.lastValidValue = value
        end
        local stopKillWaitWidget = panel:recursiveGetChildById('stopKillWait')
        if stopKillWaitWidget then
            local ms = sessionConfig.stopToKillMaxWait or 60000
            local secs = math.max(10, math.min(120, math.floor((ms / 1000) + 0.5)))
            local value = tostring(secs)
            stopKillWaitWidget:setText(value)
            stopKillWaitWidget.lastValidValue = value
        end
        local delayWalkWidget = panel:recursiveGetChildById('delayWalk')
        if delayWalkWidget then
            local value = tostring(sessionConfig.walkDelay or 20)
            delayWalkWidget:setText(value)
            delayWalkWidget.lastValidValue = value
        end

        local walkModeWalk = panel:recursiveGetChildById('walkModeWalk')
        local walkModeClick = panel:recursiveGetChildById('walkModeClick')
        if walkModeWalk and walkModeClick then
            local mode = sessionConfig.walkMode or "walk"
            walkModeWalk.ignoreCallback = true
            walkModeClick.ignoreCallback = true
            walkModeWalk:setChecked(mode ~= "click")
            walkModeClick:setChecked(mode == "click")
            walkModeWalk.ignoreCallback = nil
            walkModeClick.ignoreCallback = nil
        end

        -- Try to find lure checkbox using recursiveGetChildById
        local lureCheckbox = panel:recursiveGetChildById('lure')
        if lureCheckbox then
            lureCheckbox:setChecked(sessionConfig.lureMode or false)
        end

        -- Load lure mode settings
        local lureDebugCheckbox = panel:recursiveGetChildById('lureDebug')
        if lureDebugCheckbox then
            lureDebugCheckbox:setChecked(sessionConfig.lureDebug or false)
        end

        -- Load debug path checkbox
        local debugPathCheckbox = panel:recursiveGetChildById('debugPath')
        if debugPathCheckbox then
            debugPathCheckbox:setChecked(sessionConfig.debugPath or false)
        end
        local checkXWidget = panel:recursiveGetChildById('checkX')
        if checkXWidget then
            sessionConfig.lureCheckRangeX = math.min(6, sessionConfig.lureCheckRangeX or 6)
            local value = tostring(sessionConfig.lureCheckRangeX)
            checkXWidget:setText(value)
            checkXWidget.lastValidValue = value
        end
        local checkYWidget = panel:recursiveGetChildById('checkY')
        if checkYWidget then
            sessionConfig.lureCheckRangeY = math.min(4, sessionConfig.lureCheckRangeY or 4)
            local value = tostring(sessionConfig.lureCheckRangeY)
            checkYWidget:setText(value)
            checkYWidget.lastValidValue = value
        end
        local approachIntervalWidget = panel:recursiveGetChildById('approachInterval')
        if approachIntervalWidget then
            local v = tonumber(sessionConfig.lureApproachInterval) or 1500
            v = math.max(500, math.min(5000, v))
            sessionConfig.lureApproachInterval = v
            local value = tostring(v)
            approachIntervalWidget:setText(value)
            approachIntervalWidget.lastValidValue = value
        end

        -- Try to find avoidTrap checkbox using recursiveGetChildById
        local avoidTrapCheckbox = panel:recursiveGetChildById('avoidTrap')
        if avoidTrapCheckbox then
            avoidTrapCheckbox:setChecked(sessionConfig.avoidTrap or false)
        end
        local zRecoveryCheckbox = panel:recursiveGetChildById('zRecovery')
        if zRecoveryCheckbox then
            zRecoveryCheckbox.onCheckChange = nil
            zRecoveryCheckbox:setChecked(sessionConfig.zRecovery ~= false)
            -- Aplica NA HORA no cavebot em execucao. O "auto floor return" e um
            -- interruptor de COMPORTAMENTO: desmarcar tem que valer no ato, nao so no
            -- proximo start. Sem este handler o zRecovery era o UNICO toggle sem apply ao
            -- vivo (avoidTrap/lure ja tem) -> continuava recuperando mesmo desmarcado.
            -- Mantem o cavebotData.config em sincronia p/ o Apply/OK/persistencia baterem.
            zRecoveryCheckbox.onCheckChange = function()
                local newValue = zRecoveryCheckbox:isChecked()
                local cd = hunting_recorderModule.getCurrentCavebotData()
                if cd then
                    if not cd.config then cd.config = {} end
                    cd.config.zRecovery = newValue
                    hunting_recorderModule.setCurrentCavebotData(cd)
                end
                if cavebotWalker and cavebotWalker.updateConfig then
                    cavebotWalker.updateConfig({ zRecovery = newValue })
                end
            end
        end
        local trapDistanceWidget = panel:recursiveGetChildById('trapDistance')
        if trapDistanceWidget then
            local value = tostring(sessionConfig.trapDistance or 1)
            trapDistanceWidget:setText(value)
            trapDistanceWidget.lastValidValue = value
        end
        local creaturesToAvoidWidget = panel:recursiveGetChildById('creaturesToAvoid')
        if creaturesToAvoidWidget then
            local value = tostring(sessionConfig.creaturesToAvoid or 7)
            creaturesToAvoidWidget:setText(value)
            creaturesToAvoidWidget.lastValidValue = value
        end
        local ignoredMobsWidget = panel:recursiveGetChildById('ignoredMobsText')
        if ignoredMobsWidget then
            local ignoredText = ""
            if sessionConfig.ignoredCreatures and #sessionConfig.ignoredCreatures > 0 then
                ignoredText = table.concat(sessionConfig.ignoredCreatures, ", ")
            end
            ignoredMobsWidget:setText(ignoredText)
        end

        -- Load death-limit setting
        local deathsToDisableInput = panel:recursiveGetChildById('deathsToDisable')
        if deathsToDisableInput then
            local value = tostring(sessionConfig.deathsToDisable or 0)
            deathsToDisableInput:setText(value)
        end
        -- Update deaths label with current count
        local deathsToDisableLabel = panel:recursiveGetChildById('deathsToDisableLabel')
        if deathsToDisableLabel then
            local currentDeaths = hunting_recorderModule.getDeathCount() or 0
            deathsToDisableLabel:setText(string.format('Deaths to disable (0-100) (current: %d):', currentDeaths))
        end

        -- Goto label on death: dropdown populated with all existing labels
        local gotoLabelCombo = panel:recursiveGetChildById('gotoLabelOnDeathCombo')
        local savedGotoLabel = sessionConfig.gotoLabelOnDeath or ""
        if gotoLabelCombo then
            gotoLabelCombo:clearOptions()
            gotoLabelCombo:addOption("(none)")
            local seen = {}
            if cavebotData.waypoints then
                local list = {}
                for _, wp in pairs(cavebotData.waypoints) do
                    table.insert(list, wp)
                end
                table.sort(list, function(a, b) return (a.index or 0) < (b.index or 0) end)
                for _, wp in ipairs(list) do
                    local labelName = wp.label
                    local t = wp.type
                    local isLabel = (t == 99) or (t == "99") or (type(t) == "string" and t:lower() == "label")
                    if isLabel and labelName and labelName ~= "" and not seen[labelName] then
                        seen[labelName] = true
                        gotoLabelCombo:addOption(labelName)
                    end
                end
            end
            if savedGotoLabel ~= "" and seen[savedGotoLabel] then
                gotoLabelCombo:setCurrentOption(savedGotoLabel, true)
            else
                gotoLabelCombo:setCurrentOption("(none)", true)
            end
        end

        -- Force Presets (per-cavebot): keep targeting / magic shooter enabled and
        -- optionally lock a specific preset while this cavebot is running.
        local forceTargetingCheck = panel:recursiveGetChildById('forceTargetingCheck')
        if forceTargetingCheck then
            forceTargetingCheck:setChecked(sessionConfig.forceTargeting == true)
        end
        local forceTargetingCombo = panel:recursiveGetChildById('forceTargetingCombo')
        if forceTargetingCombo then
            populateForcePresetCombo(forceTargetingCombo, "targeting", sessionConfig.forceTargetingPreset)
        end
        local forceMagicShooterCheck = panel:recursiveGetChildById('forceMagicShooterCheck')
        if forceMagicShooterCheck then
            forceMagicShooterCheck:setChecked(sessionConfig.forceMagicShooter == true)
        end
        local forceMagicShooterCombo = panel:recursiveGetChildById('forceMagicShooterCombo')
        if forceMagicShooterCombo then
            populateForcePresetCombo(forceMagicShooterCombo, "shooter", sessionConfig.forceMagicShooterPreset)
        end

      end
  end

local suppliesUpdateEvent = nil

-- Coletar supplies do popup antes de salvar
local function collectSuppliesFromPopup()
    local supplies = {}
    local supplySettings = {}
    
    if suppliesPopup and not suppliesPopup:isDestroyed() then
        for i = 1, 10 do
            local button = suppliesPopup:recursiveGetChildById("supplyButton" .. i)
            if button then
                local itemWidget = button:getChildById("supplyItem" .. i)
                if itemWidget then
                    supplies[i] = itemWidget:getItemId() or 0
                else
                    supplies[i] = 0
                end
            else
                supplies[i] = 0
            end
            
            local minSupplyInput = suppliesPopup:recursiveGetChildById("minSupply" .. i)
            local buySupplyInput = suppliesPopup:recursiveGetChildById("buySupply" .. i)
            
            local minValue = 0
            local buyValue = 1
            
            if minSupplyInput then
                minValue = tonumber(minSupplyInput:getText()) or 0
            end
            if buySupplyInput then
                buyValue = tonumber(buySupplyInput:getText()) or 1
            end
            
            supplySettings[i] = {
                minSupply = math.max(0, math.min(10000, minValue)),
                buySupply = math.max(1, math.min(10000, buyValue))
            }
        end
    end
    
    return supplies, supplySettings
end

function hunting_recorderModule.openSuppliesPopup()
    if suppliesPopup and not suppliesPopup:isDestroyed() then
        suppliesPopup:destroy()
        suppliesPopup = nil
        if suppliesUpdateEvent then
            removeEvent(suppliesUpdateEvent)
            suppliesUpdateEvent = nil
        end
        return
    end

    local rootWidget = g_ui.getRootWidget()
    if not rootWidget then
        modules.game_textmessage.displayFailureMessage(htr("Failed to get root widget."))
        return
    end

    local window = g_ui.loadUI("/mods/game_helper/styles/supplies_popup.otui", rootWidget)
    if not window then
        modules.game_textmessage.displayFailureMessage(htr("Failed to load supplies popup."))
        return
    end

    suppliesPopup = window
    window.onDestroy = function()
        -- Salvar supplies antes de fechar o popup (coletar antes de destruir)
        local tempSupplies = {}
        local tempSupplySettings = {}
        
        if window and not window:isDestroyed() then
            for i = 1, 10 do
                local button = window:recursiveGetChildById("supplyButton" .. i)
                if button then
                    local itemWidget = button:getChildById("supplyItem" .. i)
                    if itemWidget then
                        tempSupplies[i] = itemWidget:getItemId() or 0
                    else
                        tempSupplies[i] = 0
                    end
                else
                    tempSupplies[i] = 0
                end
                
                local minSupplyInput = window:recursiveGetChildById("minSupply" .. i)
                local buySupplyInput = window:recursiveGetChildById("buySupply" .. i)
                
                local minValue = 0
                local buyValue = 1
                
                if minSupplyInput then
                    minValue = tonumber(minSupplyInput:getText()) or 0
                end
                if buySupplyInput then
                    buyValue = tonumber(buySupplyInput:getText()) or 1
                end
                
                tempSupplySettings[i] = {
                    minSupply = math.max(0, math.min(10000, minValue)),
                    buySupply = math.max(0, math.min(10000, buyValue))
                }
            end
            
            local cavebotData = hunting_recorderModule.getCurrentCavebotData()
            if cavebotData then
                cavebotData.supplies = tempSupplies
                cavebotData.supplySettings = tempSupplySettings
                hunting_recorderModule.setCurrentCavebotData(cavebotData)
            end
        end
        
        suppliesPopup = nil
        if suppliesUpdateEvent then
            removeEvent(suppliesUpdateEvent)
            suppliesUpdateEvent = nil
        end
    end

    -- Carregar itens salvos
    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.config then
        cavebotData.config = {}
    end
    if not cavebotData.supplies then
        cavebotData.supplies = {}
    end

    -- Inicializar estruturas de dados se nao existirem
    if not cavebotData.supplies then
        cavebotData.supplies = {}
    end
    if not cavebotData.supplySettings then
        cavebotData.supplySettings = {}
    end

    -- Atualizar UI com itens salvos e configuracoes
    for i = 1, 10 do
        local itemId = cavebotData.supplies[i] or 0
        local button = window:recursiveGetChildById("supplyButton" .. i)
        if button then
            if itemId > 0 then
                button:setImageSource("/images/ui/item")
                if not button:getChildById("supplyItem" .. i) then
                    local itemWidget = g_ui.createWidget("RuneItem", button)
                    itemWidget:setId("supplyItem" .. i)
                end
                local itemWidget = button:getChildById("supplyItem" .. i)
                if itemWidget then
                    itemWidget:setItemId(itemId)
                end
            else
                -- Reset button if no item
                button:setImageSource("/images/game/actionbar/slot-actionbar.png")
                local itemWidget = button:getChildById("supplyItem" .. i)
                if itemWidget then
                    itemWidget:destroy()
                end
            end
        end

        -- Carregar valores de minSupply e buySupply
        if not cavebotData.supplySettings[i] then
            cavebotData.supplySettings[i] = {minSupply = 0, buySupply = 1}
        end

        local minSupplyInput = window:recursiveGetChildById("minSupply" .. i)
        if minSupplyInput then
            local minValue = cavebotData.supplySettings[i].minSupply or 0
            minSupplyInput:setText(tostring(minValue))
        end

        local buySupplyInput = window:recursiveGetChildById("buySupply" .. i)
        if buySupplyInput then
            local buyValue = cavebotData.supplySettings[i].buySupply or 1
            buySupplyInput:setText(tostring(buyValue))
        end
    end

    hunting_recorderModule.setCurrentCavebotData(cavebotData)

    -- Atualizar quantidades
    hunting_recorderModule.updateSuppliesCounts()

    -- Iniciar atualizacao periodica de quantidades
    if not suppliesUpdateEvent then
        local function updateCounts()
            if suppliesPopup and not suppliesPopup:isDestroyed() then
                hunting_recorderModule.updateSuppliesCounts()
            else
                if suppliesUpdateEvent then
                    removeEvent(suppliesUpdateEvent)
                    suppliesUpdateEvent = nil
                end
            end
        end
        suppliesUpdateEvent = scheduleEvent(updateCounts, 1000)
    end

    window:show()
    window:raise()
    window:focus()
    if _G.helperModalEnter then _G.helperModalEnter(window) end
end

function hunting_recorderModule.createSupplyMenu(index)
    if not suppliesPopup or suppliesPopup:isDestroyed() then
        return true
    end

    local button = suppliesPopup:recursiveGetChildById("supplyButton" .. index)
    if not button then
        return true
    end

    local menu = g_ui.createWidget('HelperPopupMenu')
    menu:setGameMenu(true)
    
    menu:addOption(tr('Select Item'), function()
        hunting_recorderModule.assignSupplyItemEvent(button, index)
    end)

    menu:addOption(tr('Assign ID'), function()
        modules.game_helper.openAssignItemIdWindow(button, "supply", index)
    end)

    menu:addOption(tr('Assign List'), function()
        modules.game_helper.openAssignItemListWindow(button, "supply", index)
    end)

    if button:getChildById("supplyItem" .. index) then
        menu:addOption(tr('Remove Item'), function()
            hunting_recorderModule.removeSupplyItem(index)
        end)
    end

    local mousePos = g_window.getMousePosition()
    menu:display(mousePos)
    return true
end

function hunting_recorderModule.removeSupplyItem(index)
    if not suppliesPopup or suppliesPopup:isDestroyed() then
        return
    end

    local button = suppliesPopup:recursiveGetChildById("supplyButton" .. index)
    if not button then
        return
    end

    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.config then
        cavebotData.config = {}
    end
    if not cavebotData.supplies then
        cavebotData.supplies = {}
    end

    cavebotData.supplies[index] = 0
    button:setImageSource("/images/game/actionbar/slot-actionbar.png")
    local itemWidget = button:getChildById("supplyItem" .. index)
    if itemWidget then
        itemWidget:destroy()
    end
    local countLabel = suppliesPopup:recursiveGetChildById("supplyCount" .. index)
    if countLabel then
        countLabel:setVisible(false)
    end

    hunting_recorderModule.setCurrentCavebotData(cavebotData)
end

function hunting_recorderModule.assignSupplyItemEvent(button, index)
    local mouseGrabberWidget = modules.game_helper.getMouseGrabberWidget()
    if not mouseGrabberWidget then
        return
    end

    mouseGrabberWidget:grabMouse()
    if suppliesPopup then
        suppliesPopup:hide()
    end
    g_mouse.pushCursor("target")
    mouseGrabberWidget.onMouseRelease = function(self, mousePosition, mouseButton)
        hunting_recorderModule.onAssignSupplyItem(self, mousePosition, mouseButton, button, index)
    end
end

function hunting_recorderModule.onAssignSupplyItem(self, mousePosition, mouseButton, button, index)
    local mouseGrabberWidget = modules.game_helper.getMouseGrabberWidget()
    if not mouseGrabberWidget then
        return true
    end

    mouseGrabberWidget:ungrabMouse()
    if suppliesPopup then
        suppliesPopup:show()
    end
    g_mouse.popCursor("target")
    mouseGrabberWidget.onMouseRelease = nil

    local rootWidget = g_ui.getRootWidget()
    if not rootWidget then
        return true
    end

    local clickedWidget = rootWidget:recursiveGetChildByPos(mousePosition, false)
    if not clickedWidget then
        return true
    end

    local item = nil
    if clickedWidget:getClassName() == "UIItem" and not clickedWidget:isVirtual() then
        item = clickedWidget:getItem()
    elseif clickedWidget:getClassName() == "UIGameMap" then
        local tile = clickedWidget:getTile(mousePosition)
        if tile then
            local topUseThing = tile:getTopUseThing()
            if topUseThing and topUseThing:isItem() then
                item = topUseThing
            end
        end
    end

    if not item then
        modules.game_textmessage.displayFailureMessage(tr("Invalid item!"))
        return false
    end

    local itemId = item:getId()
    button:setImageSource("/images/ui/item")

    if not button:getChildById("supplyItem" .. index) then
        local itemWidget = g_ui.createWidget("RuneItem", button)
        itemWidget:setId("supplyItem" .. index)
    end

    local itemWidget = button:getChildById("supplyItem" .. index)
    if itemWidget then
        itemWidget:setItemId(itemId)
    end

    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.config then
        cavebotData.config = {}
    end
    if not cavebotData.supplies then
        cavebotData.supplies = {}
    end
    cavebotData.supplies[index] = itemId
    hunting_recorderModule.setCurrentCavebotData(cavebotData)

    -- Atualizar quantidade
    hunting_recorderModule.updateSuppliesCounts()

    return true
end

function hunting_recorderModule.applySupplyById(button, itemId, index)
    -- Try to get the popup from different sources
    local popup = suppliesPopup
    if not popup or popup:isDestroyed() then
        local rootWidget = g_ui.getRootWidget()
        if rootWidget then
            popup = rootWidget:recursiveGetChildById("suppliesPopup")
        end
    end

    if not popup or popup:isDestroyed() then
        return
    end

    button:setImageSource("/images/ui/item")

    if not button:getChildById("supplyItem" .. index) then
        local itemWidget = g_ui.createWidget("RuneItem", button)
        itemWidget:setId("supplyItem" .. index)
    end

    local itemWidget = button:getChildById("supplyItem" .. index)
    if itemWidget then
        itemWidget:setItemId(itemId)
    end

    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.config then
        cavebotData.config = {}
    end
    if not cavebotData.supplies then
        cavebotData.supplies = {}
    end
    cavebotData.supplies[index] = itemId
    hunting_recorderModule.setCurrentCavebotData(cavebotData)

    -- Update count
    hunting_recorderModule.updateSuppliesCounts()
end

function hunting_recorderModule.onSupplySettingChange(index, settingType, value)
    if not suppliesPopup or suppliesPopup:isDestroyed() then
        return
    end

    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.config then
        cavebotData.config = {}
    end
    if not cavebotData.supplySettings then
        cavebotData.supplySettings = {}
    end
    if not cavebotData.supplySettings[index] then
        cavebotData.supplySettings[index] = {minSupply = 0, buySupply = 1}
    end

    local numValue = tonumber(value) or 0
    if settingType == 'minSupply' then
        cavebotData.supplySettings[index].minSupply = math.max(0, math.min(10000, numValue))
    elseif settingType == 'buySupply' then
        cavebotData.supplySettings[index].buySupply = math.max(1, math.min(10000, numValue))
    end

    hunting_recorderModule.setCurrentCavebotData(cavebotData)
end

function hunting_recorderModule.updateSuppliesCounts()
    if not suppliesPopup or suppliesPopup:isDestroyed() then
        return
    end

    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData or not cavebotData.supplies then
        return
    end

    for i = 1, 10 do
        local itemId = cavebotData.supplies[i] or 0
        local countLabel = suppliesPopup:recursiveGetChildById("supplyCount" .. i)
        if countLabel then
            if itemId > 0 then
                local count = 0
                if modules.game_helper and modules.game_helper.getItemCountAnywhere then
                    count = modules.game_helper.getItemCountAnywhere(itemId)
                end
                countLabel:setText(tostring(count))
                countLabel:setVisible(true)
            else
                countLabel:setVisible(false)
            end
        end
    end
end

-- Atualizar lista de supplies no popup se estiver aberto
function hunting_recorderModule.refreshSuppliesList()
    if not suppliesPopup or suppliesPopup:isDestroyed() then
        return
    end

    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData then
        return
    end

    -- Garantir que supplies e supplySettings existam
    if not cavebotData.supplies then
        cavebotData.supplies = {}
    end
    if not cavebotData.supplySettings then
        cavebotData.supplySettings = {}
    end

    -- Atualizar UI com itens salvos e configuracoes
    for i = 1, 10 do
        local itemId = cavebotData.supplies[i] or 0
        local button = suppliesPopup:recursiveGetChildById("supplyButton" .. i)
        if button then
            if itemId > 0 then
                button:setImageSource("/images/ui/item")
                if not button:getChildById("supplyItem" .. i) then
                    local itemWidget = g_ui.createWidget("RuneItem", button)
                    itemWidget:setId("supplyItem" .. i)
                end
                local itemWidget = button:getChildById("supplyItem" .. i)
                if itemWidget then
                    itemWidget:setItemId(itemId)
                end
            else
                -- Reset button if no item
                button:setImageSource("/images/game/actionbar/slot-actionbar.png")
                local itemWidget = button:getChildById("supplyItem" .. i)
                if itemWidget then
                    itemWidget:destroy()
                end
            end
        end

        -- Carregar valores de minSupply e buySupply
        if not cavebotData.supplySettings[i] then
            cavebotData.supplySettings[i] = {minSupply = 0, buySupply = 1}
        end

        local minSupplyInput = suppliesPopup:recursiveGetChildById("minSupply" .. i)
        if minSupplyInput then
            local minValue = 0
            if itemId > 0 then
                minValue = cavebotData.supplySettings[i].minSupply or 0
            end
            minSupplyInput:setText(tostring(minValue))
        end

        local buySupplyInput = suppliesPopup:recursiveGetChildById("buySupply" .. i)
        if buySupplyInput then
            local buyValue = 1
            if itemId > 0 then
                buyValue = cavebotData.supplySettings[i].buySupply or 1
            end
            buySupplyInput:setText(tostring(buyValue))
        end
        
        -- Atualizar contagem
        local countLabel = suppliesPopup:recursiveGetChildById("supplyCount" .. i)
        if countLabel then
            if itemId > 0 then
                local count = 0
                if modules.game_helper and modules.game_helper.getItemCountAnywhere then
                    count = modules.game_helper.getItemCountAnywhere(itemId)
                end
                countLabel:setText(tostring(count))
                countLabel:setVisible(true)
            else
                countLabel:setVisible(false)
            end
        end
    end

end

function hunting_recorderModule.openLureSettings()
    if lureSettingsWindow and not lureSettingsWindow:isDestroyed() then
        lureSettingsWindow:destroy()
        lureSettingsWindow = nil
        return
    end

    local rootWidget = g_ui.getRootWidget()
    if not rootWidget then
        modules.game_textmessage.displayFailureMessage(htr("Failed to get root widget."))
        return
    end

    local window = g_ui.loadUI("/mods/game_helper/styles/lure_settings.otui", rootWidget)
    if not window then
        modules.game_textmessage.displayFailureMessage(htr("Failed to load lure settings."))
        return
    end

    lureSettingsWindow = window
    window.onDestroy = function()
        lureSettingsWindow = nil
    end

    window:show()
    window:raise()
    window:focus()
    if _G.helperModalEnter then _G.helperModalEnter(window) end

    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    local sessionConfig = cavebotData.config or {}

    if sessionConfig.lureDebug == nil then
        sessionConfig.lureDebug = false
    end
    sessionConfig.lureCheckRangeX = math.min(6, sessionConfig.lureCheckRangeX or 6)
    sessionConfig.lureCheckRangeY = math.min(4, sessionConfig.lureCheckRangeY or 4)

    local panel = window:recursiveGetChildById('lureSettingsPanel')
    if panel then
        if panel.lureDebug then
            panel.lureDebug:setChecked(sessionConfig.lureDebug or false)
        end
        if panel.checkX then
            panel.checkX:setText(tostring(sessionConfig.lureCheckRangeX))
        end
        if panel.checkY then
            panel.checkY:setText(tostring(sessionConfig.lureCheckRangeY))
        end
    end
end

function hunting_recorderModule.saveLureSettings(window, keepOpen)
    if not window then
        return
    end

    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.config then
        cavebotData.config = {}
    end

    local panel = window:recursiveGetChildById('lureSettingsPanel')
    if not panel then
        return
    end

    if panel.lureDebug then
        cavebotData.config.lureDebug = panel.lureDebug:isChecked()
        -- Start/stop visual lure debug
        if cavebotData.config.lureDebug then
            if _G.startLureDebugVisual then _G.startLureDebugVisual() end
        else
            if _G.stopLureDebugVisual then _G.stopLureDebugVisual() end
        end
    end
    if panel.checkX then
        local value = tonumber(panel.checkX:getText()) or 6
        cavebotData.config.lureCheckRangeX = math.min(6, math.max(1, value))
    end
    if panel.checkY then
        local value = tonumber(panel.checkY:getText()) or 4
        cavebotData.config.lureCheckRangeY = math.min(4, math.max(1, value))
    end

    hunting_recorderModule.setCurrentCavebotData(cavebotData)

    if cavebotWalker and cavebotWalker.updateConfig then
        cavebotWalker.updateConfig({
            lureDebug = cavebotData.config.lureDebug,
            lureCheckRangeX = cavebotData.config.lureCheckRangeX,
            lureCheckRangeY = cavebotData.config.lureCheckRangeY
        })
    end

    -- Debug window is now controlled by a separate button, not automatically opened

    if not keepOpen then
        window:destroy()
    end
end

function hunting_recorderModule.saveCavebotSettings(window, keepOpen)
    if not window then
        return
    end

    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.config then
        cavebotData.config = {}
    end

    -- Get settings panel from window
    local panel = window:recursiveGetChildById('settingsPanel')
    if not panel then
        return
    end

    -- Try to find lure checkbox using different methods
    local lureCheckbox = panel:recursiveGetChildById('lure')
    local avoidTrapCheckbox = panel:recursiveGetChildById('avoidTrap')
    local walkModeWalk = panel:recursiveGetChildById('walkModeWalk')
    local walkModeClick = panel:recursiveGetChildById('walkModeClick')

    -- Save values from UI
    -- Walker Settings (per-cavebot)
    local nodeDistanceWidget = panel:recursiveGetChildById('nodeDistance')
    if nodeDistanceWidget then
        local value = tonumber(nodeDistanceWidget:getText()) or 2
        cavebotData.config.nodeDistance = math.max(1, math.min(3, value))
    end
    local stopToKillDistWidget = panel:recursiveGetChildById('stopToKillDistance')
    if stopToKillDistWidget then
        local value = tonumber(stopToKillDistWidget:getText()) or 2
        cavebotData.config.stopToKillDistance = math.max(1, math.min(3, value))
    end
    local stopAtWidget = panel:recursiveGetChildById('stopAt')
    if stopAtWidget then
        local value = tonumber(stopAtWidget:getText()) or 8
        cavebotData.config.creaturesToStop = math.max(1, math.min(99, value))
    end
    local resumeAtWidget = panel:recursiveGetChildById('resumeAt')
    if resumeAtWidget then
        local value = tonumber(resumeAtWidget:getText()) or 2
        cavebotData.config.creaturesToWalk = math.max(0, math.min(99, value))
    end
    local finishKillCountWidget = panel:recursiveGetChildById('finishKillMobCount')
    if finishKillCountWidget then
        local value = tonumber(finishKillCountWidget:getText()) or 0
        cavebotData.config.finishKillMobCount = math.max(0, math.min(20, value))
    end
    local finishKillHpWidget = panel:recursiveGetChildById('finishKillHpPct')
    if finishKillHpWidget then
        local value = tonumber(finishKillHpWidget:getText()) or 30
        cavebotData.config.finishKillHpPct = math.max(0, math.min(100, value))
    end
    local stopKillWaitWidget = panel:recursiveGetChildById('stopKillWait')
    if stopKillWaitWidget then
        local secs = tonumber(stopKillWaitWidget:getText()) or 60
        secs = math.max(10, math.min(120, secs))
        cavebotData.config.stopToKillMaxWait = secs * 1000
    end
    local delayWalkWidget = panel:recursiveGetChildById('delayWalk')
    if delayWalkWidget then
        local value = tonumber(delayWalkWidget:getText()) or 20
        cavebotData.config.walkDelay = math.max(10, math.min(5000, value))
    end

    local walkMode = "walk"
    if walkModeClick and walkModeClick:isChecked() then
        walkMode = "click"
    elseif walkModeWalk and walkModeWalk:isChecked() then
        walkMode = "walk"
    end
    cavebotData.config.walkMode = walkMode

    -- Use recursiveGetChildById instead of panel.lure
    if lureCheckbox then
        cavebotData.config.lureMode = lureCheckbox:isChecked()
    end

    -- Save lure mode settings
    local lureDebugCheckbox = panel:recursiveGetChildById('lureDebug')
    if lureDebugCheckbox then
        cavebotData.config.lureDebug = lureDebugCheckbox:isChecked()
        -- Start/stop visual lure debug
        if cavebotData.config.lureDebug then
            if _G.startLureDebugVisual then _G.startLureDebugVisual() end
        else
            if _G.stopLureDebugVisual then _G.stopLureDebugVisual() end
        end
    end

    -- Save debug path checkbox
    local debugPathCheckbox = panel:recursiveGetChildById('debugPath')
    if debugPathCheckbox then
        cavebotData.config.debugPath = debugPathCheckbox:isChecked()
    end
    local checkXWidget = panel:recursiveGetChildById('checkX')
    if checkXWidget then
        local value = tonumber(checkXWidget:getText()) or 6
        cavebotData.config.lureCheckRangeX = math.min(6, math.max(1, value))
    end
    local checkYWidget = panel:recursiveGetChildById('checkY')
    if checkYWidget then
        local value = tonumber(checkYWidget:getText()) or 4
        cavebotData.config.lureCheckRangeY = math.min(4, math.max(1, value))
    end
    local approachIntervalWidget = panel:recursiveGetChildById('approachInterval')
    if approachIntervalWidget then
        local value = tonumber(approachIntervalWidget:getText()) or 1500
        cavebotData.config.lureApproachInterval = math.min(5000, math.max(500, value))
    end

    if avoidTrapCheckbox then
        cavebotData.config.avoidTrap = avoidTrapCheckbox:isChecked()
    end
    local zRecoveryCheckbox = panel:recursiveGetChildById('zRecovery')
    if zRecoveryCheckbox then
        cavebotData.config.zRecovery = zRecoveryCheckbox:isChecked()
    end
    local trapDistanceWidget = panel:recursiveGetChildById('trapDistance')
    if trapDistanceWidget then
        local value = tonumber(trapDistanceWidget:getText()) or 1
        cavebotData.config.trapDistance = math.max(1, math.min(3, value))
    end
    local creaturesToAvoidWidget = panel:recursiveGetChildById('creaturesToAvoid')
    if creaturesToAvoidWidget then
        local value = tonumber(creaturesToAvoidWidget:getText()) or 7
        cavebotData.config.creaturesToAvoid = math.max(1, math.min(7, value))
    end
    local ignoredMobsWidget = panel:recursiveGetChildById('ignoredMobsText')
    if ignoredMobsWidget then
        local ignoredText = ignoredMobsWidget:getText():trim()
        local ignoredList = {}
        if ignoredText and ignoredText ~= "" then
            for name in ignoredText:gmatch("([^,]+)") do
                name = name:trim()
                if name ~= "" then
                    table.insert(ignoredList, name)
                end
            end
        end
        cavebotData.config.ignoredCreatures = ignoredList
    end

    -- Save death-limit setting
    local deathsToDisableInput = panel:recursiveGetChildById('deathsToDisable')
    if deathsToDisableInput then
        local value = tonumber(deathsToDisableInput:getText()) or 0
        cavebotData.config.deathsToDisable = math.max(0, math.min(100, value))
    end
    local gotoLabelCombo = panel:recursiveGetChildById('gotoLabelOnDeathCombo')
    if gotoLabelCombo then
        local selected = gotoLabelCombo:getCurrentOption()
        local txt = ""
        if type(selected) == "table" then
            txt = selected.text or ""
        elseif type(selected) == "string" then
            txt = selected
        end
        if txt == "(none)" then txt = "" end
        cavebotData.config.gotoLabelOnDeath = txt
    end

    -- Force Presets (per-cavebot)
    local forceTargetingCheck = panel:recursiveGetChildById('forceTargetingCheck')
    if forceTargetingCheck then
        cavebotData.config.forceTargeting = forceTargetingCheck:isChecked()
    end
    local forceTargetingCombo = panel:recursiveGetChildById('forceTargetingCombo')
    if forceTargetingCombo then
        local opt = forceTargetingCombo:getCurrentOption()
        local data = ""
        if type(opt) == "table" then data = opt.data or "" end
        cavebotData.config.forceTargetingPreset = tostring(data or "")
    end
    local forceMagicShooterCheck = panel:recursiveGetChildById('forceMagicShooterCheck')
    if forceMagicShooterCheck then
        cavebotData.config.forceMagicShooter = forceMagicShooterCheck:isChecked()
    end
    local forceMagicShooterCombo = panel:recursiveGetChildById('forceMagicShooterCombo')
    if forceMagicShooterCombo then
        local opt = forceMagicShooterCombo:getCurrentOption()
        local data = ""
        if type(opt) == "table" then data = opt.data or "" end
        cavebotData.config.forceMagicShooterPreset = tostring(data or "")
    end

    -- Collect checkbox states
    local startFromNearest = true
    local debugPos = false
    if huntingWaypointsWindow then
        local buttonsPanel = huntingWaypointsWindow:recursiveGetChildById('buttons')
        if buttonsPanel then
            local startFromNearestCheckBox = buttonsPanel:recursiveGetChildById('startFromNearestCheckBox')
            if startFromNearestCheckBox then
                startFromNearest = startFromNearestCheckBox:isChecked()
            end
            local debugPosCheckBox = buttonsPanel:recursiveGetChildById('debugPosCheckBox')
            if debugPosCheckBox then
                debugPos = debugPosCheckBox:isChecked()
            end
        end
    end

    -- Save checkbox states to config
    cavebotData.config.startFromNearest = startFromNearest
    cavebotData.config.debugPos = debugPos

    -- Save to current cavebot data
    hunting_recorderModule.setCurrentCavebotData(cavebotData)

    -- Update walker config in real-time
      if cavebotWalker and cavebotWalker.updateConfig then
          cavebotWalker.updateConfig({
              nodeDistance = cavebotData.config.nodeDistance or 2,
              stopToKillDistance = cavebotData.config.stopToKillDistance or 2,
              creaturesToStop = cavebotData.config.creaturesToStop,
              creaturesToWalk = cavebotData.config.creaturesToWalk,
              finishKillMobCount = cavebotData.config.finishKillMobCount,
              finishKillHpPct = cavebotData.config.finishKillHpPct,
              stopToKillMaxWait = cavebotData.config.stopToKillMaxWait,
              walkDelay = cavebotData.config.walkDelay,
              walkMode = cavebotData.config.walkMode,
              mapClick = (cavebotData.config.walkMode or "walk") == "click",
              lureMode = cavebotData.config.lureMode,
              lureDebug = cavebotData.config.lureDebug,
              lureCheckRangeX = cavebotData.config.lureCheckRangeX,
              lureCheckRangeY = cavebotData.config.lureCheckRangeY,
              lureApproachInterval = cavebotData.config.lureApproachInterval,
              avoidTrap = cavebotData.config.avoidTrap,
              zRecovery = cavebotData.config.zRecovery,
              trapDistance = cavebotData.config.trapDistance,
              creaturesToAvoid = cavebotData.config.creaturesToAvoid,
              ignoredCreatures = cavebotData.config.ignoredCreatures,
              staminaToLeave = cavebotData.config.staminaToLeave,
              staminaToReturn = cavebotData.config.staminaToReturn,
              capToLeave = cavebotData.config.capToLeave,
              deathsToDisable = cavebotData.config.deathsToDisable
          })
    end

    -- Debug window is now controlled by a separate button, not automatically opened

    -- Reload internal module
    hunting_recorderModule.reloadInternalModule()
    hunting_recorderModule.updateDebugPos()

    -- Persist settings (including Force Presets) into this cavebot's file so they
    -- survive relog, matching what was selected in the UI.
    local cbName = cavebotData.name
    if cbName and cbName ~= "" and g_resources.fileExists("/helper/cavebots/" .. cbName .. ".json") then
        pcall(saveCavebotToFile, cbName, cavebotData, true)
    end

    -- Apply force presets immediately if the cavebot is already running
    if enforceCavebotForcePresets then
        pcall(enforceCavebotForcePresets)
    end

    -- Close window
    if not keepOpen then
        window:destroy()
    end

    modules.game_textmessage.displayGameMessage("Cavebot settings saved successfully.")
end

-- Cavebot Manager System (replaces sessions)
  local currentCavebotData = {
      name = "",
      waypoints = {},
      specialAreas = {},
      config = {
          nodeDistance = 2,
          stopToKillDistance = 2,
          creaturesToStop = 8,
          creaturesToWalk = 2,
          lureMode = true,
          lureSpeed = 5,
          lureDebug = false,
          lureCheckRangeX = 6,
          lureCheckRangeY = 4,
          walkDelay = 20,
          walkMode = "walk",
          avoidTrap = true,
          zRecovery = true,
          trapDistance = 1,
          creaturesToAvoid = 7,
          ignoredCreatures = {},
        startFromNearest = true,
        debugPos = false
    }
}

local function isSamePosition(posA, posB)
    if not posA or not posB then
        return false
    end
    return posA.x == posB.x and posA.y == posB.y and posA.z == posB.z
end

ensureSpecialAreasTable = function(cavebotData)
    if not cavebotData.specialAreas then
        cavebotData.specialAreas = {}
    end
end

local function getNextSpecialAreaId(specialAreas)
    local maxId = 0
    for _, area in ipairs(specialAreas or {}) do
        if area.id and area.id > maxId then
            maxId = area.id
        end
    end
    return maxId + 1
end

function hunting_recorderModule.normalizeCavebotData(cavebotData)
    if not cavebotData then
        return
    end

    ensureSpecialAreasTable(cavebotData)
    
    -- Inicializar config se nao existir
    if not cavebotData.config then
        cavebotData.config = {}
    end
    
    -- Inicializar valores de stamina se nao existirem
    if cavebotData.config.staminaToLeave == nil then
        cavebotData.config.staminaToLeave = 39
    end
    if cavebotData.config.staminaToReturn == nil then
        cavebotData.config.staminaToReturn = 42
    end
    if cavebotData.config.capToLeave == nil then
        cavebotData.config.capToLeave = 500
    end
    if cavebotData.config.deathsToDisable == nil then
        cavebotData.config.deathsToDisable = 0
    end

    -- Inicializar startFromNearest como true por padrao
    if cavebotData.config.startFromNearest == nil then
        cavebotData.config.startFromNearest = true
    end
    
    -- Inicializar supplies e supplySettings se nao existirem
    if not cavebotData.supplies then
        cavebotData.supplies = {}
    end
    if not cavebotData.supplySettings then
        cavebotData.supplySettings = {}
    end
    
    -- Garantir que existam 10 slots de supplies inicializados
    for i = 1, 10 do
        if cavebotData.supplies[i] == nil then
            cavebotData.supplies[i] = 0
        end
        if not cavebotData.supplySettings[i] then
            cavebotData.supplySettings[i] = {minSupply = 0, buySupply = 1}
        end
    end

    local waypointsTable = cavebotData.waypoints or {}
    local newWaypoints = {}
    local nextSpecialId = getNextSpecialAreaId(cavebotData.specialAreas)

    for _, area in ipairs(cavebotData.specialAreas) do
        if not area.id then
            area.id = nextSpecialId
            nextSpecialId = nextSpecialId + 1
        end
    end

    for _, waypoint in pairs(waypointsTable) do
        if waypoint and waypointTypeToNumber(waypoint.type) == 90 and waypoint.position then
            local exists = false
            for _, area in ipairs(cavebotData.specialAreas) do
                if area.position and isSamePosition(area.position, waypoint.position) then
                    exists = true
                    break
                end
            end
            if not exists then
                table.insert(cavebotData.specialAreas, {
                    id = waypoint.id or nextSpecialId,
                    position = waypoint.position,
                    type = 90
                })
                nextSpecialId = nextSpecialId + 1
            end
        else
            table.insert(newWaypoints, waypoint)
        end
    end

    table.sort(newWaypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)
    for i, wp in ipairs(newWaypoints) do
        wp.index = i
    end
    cavebotData.waypoints = newWaypoints
end

local cavebotsManagerWindow = nil
local selectedCavebotName = nil

-- Ensure cavebots directory exists
ensureCavebotsDirectory = function()
    local cavebotsDir = "/helper/cavebots"
    if not g_resources.directoryExists("/helper/") then
        g_resources.makeDir("/helper/")
    end
    if not g_resources.directoryExists(cavebotsDir) then
        g_resources.makeDir(cavebotsDir)
    end
    return cavebotsDir
end

-- Get current cavebot data (replaces getSessionSettings)
function hunting_recorderModule.getCurrentCavebotData()
    return currentCavebotData
end

-- Set current cavebot data (replaces setSessionSettings)
function hunting_recorderModule.setCurrentCavebotData(data)
    if data then
        ensureSpecialAreasTable(data)
        currentCavebotData = data
    end
end

-- Save cavebot to file
saveCavebotToFile = function(cavebotName, cavebotData, force)
    if not force then
        return false
    end

    local cavebotsDir = ensureCavebotsDirectory()
    if not cavebotsDir then
        return false
    end

    local cavebotFile = cavebotsDir .. "/" .. cavebotName .. ".json"

    local status, result = pcall(function() return json.encode(cavebotData, 2) end)
    if not status then
        g_logger.error("[Cavebot] Erro ao codificar cavebot " .. cavebotName .. ": " .. tostring(result))
        return false
    end

    if result:len() > 100 * 1024 * 1024 then
        g_logger.error("[Cavebot] Cavebot " .. cavebotName .. " muito grande (>100MB)")
        return false
    end

    local writeStatus = g_resources.writeFileContents(cavebotFile, result)
    if not writeStatus then
        g_logger.error("[Cavebot] Erro ao salvar cavebot: " .. cavebotFile)
    end

    return writeStatus
end

-- Publish the file-local saver on the module table so out-of-module callers (the
-- scripting API's CaveBot.saveFile) can persist the active profile; the saver is
-- otherwise unreachable (local upvalue, never exposed on _G).
hunting_recorderModule.saveCavebotToFile = saveCavebotToFile

-- Load cavebot from file
loadCavebotFromFile = function(cavebotName)
    local cavebotsDir = "/helper/cavebots"
    local cavebotFile = cavebotsDir .. "/" .. cavebotName .. ".json"

    if not g_resources.fileExists(cavebotFile) then
        g_logger.warning("[Cavebot] Arquivo de cavebot nao existe: " .. cavebotFile)
        return nil
    end

    local status, result = pcall(function() return json.decode(g_resources.readFileContents(cavebotFile)) end)
    if not status then
        g_logger.error("[Cavebot] Erro ao decodificar cavebot " .. cavebotName .. ": " .. tostring(result))
        return nil
    end
    hunting_recorderModule.normalizeCavebotData(result)
    return result
end

-- Refresh cavebots list
function hunting_recorderModule.refreshCavebotsList()
    if not cavebotsManagerWindow then
        return
    end

    -- Tentar acessar diretamente ou através do painel
    local cavebotsListBox = cavebotsManagerWindow:getChildById("cavebotsListBox")
    if not cavebotsListBox then
        local mainPanel = cavebotsManagerWindow:getChildById("cavebotsMainPanel")
        if mainPanel then
            cavebotsListBox = mainPanel:getChildById("cavebotsListBox")
        end
    end
    
    if not cavebotsListBox then
        cavebotsListBox = cavebotsManagerWindow:recursiveGetChildById("cavebotsListBox")
    end
    
    if not cavebotsListBox then
        return
    end

    cavebotsListBox:destroyChildren()

    -- Ensure directory exists
    ensureCavebotsDirectory()

    local cavebotsDir = "/helper/cavebots"
    if not g_resources.directoryExists(cavebotsDir) then
        ensureCavebotsDirectory()
        return
    end

    local files = g_resources.listDirectoryFiles(cavebotsDir, false, false, false)

    if files then
        local cavebotNames = {}
        for _, fileName in pairs(files) do
            if fileName and fileName:match("%.json$") then
                local cavebotName = fileName:gsub("%.json$", "")
                if cavebotName and cavebotName ~= "" then
                    table.insert(cavebotNames, cavebotName)
                end
            end
        end

        table.sort(cavebotNames)

        local visibleIndex = 0
        for _, name in ipairs(cavebotNames) do
            visibleIndex = visibleIndex + 1
            -- Criar widget customizado para cada cavebot
            local item = g_ui.createWidget('CavebotListEntry', cavebotsListBox)
            item:setText(name)
            item.cavebotName = name
            
            -- Aplicar cores alternadas (zebra striping)
            item.baseBackgroundColor = visibleIndex % 2 == 0 and "#0a0a0a" or "#12121200"
            item:setBackgroundColor(item.baseBackgroundColor)
            item:updateOnStates()
            
            -- Conectar evento de botao direito diretamente no item
            item.onMousePress = function(self, mousePos, mouseButton)
                if mouseButton == MouseRightButton then
                    hunting_recorderModule.showCavebotContextMenu(self, mousePos, name)
                    return true
                end
                return false
            end
        end
    end

    hunting_recorderModule.updateCurrentCavebotLabel()
end

-- Update current cavebot label
function hunting_recorderModule.updateCurrentCavebotLabel()
    if not cavebotsManagerWindow then
        return
    end
    
    local label = cavebotsManagerWindow:recursiveGetChildById("currentCavebotLabel")
    if label then
        local cavebotData = hunting_recorderModule.getCurrentCavebotData()
        local name = (cavebotData and cavebotData.name) or "None"
        label:setText("Cavebot: " .. name)
    end
end

-- Open cavebots manager window
function hunting_recorderModule.openCavebotsManager()
    if cavebotsManagerWindow and not cavebotsManagerWindow:isDestroyed() then
        cavebotsManagerWindow:destroy()
        cavebotsManagerWindow = nil
        return
    end
    
    local rootWidget = g_ui.getRootWidget()
    if not rootWidget then
        modules.game_textmessage.displayFailureMessage(htr("Failed to get root widget."))
        return
    end
    
    local window = g_ui.loadUI("/mods/game_helper/styles/cavebots_manager.otui", rootWidget)
    if not window then
        modules.game_textmessage.displayFailureMessage(htr("Failed to load cavebots manager window."))
        return
    end
    
    cavebotsManagerWindow = window
    window.onDestroy = function()
        cavebotsManagerWindow = nil
    end

    window:show()
    window:raise()
    window:focus()
    if _G.helperModalEnter then _G.helperModalEnter(window) end

    -- Usar scheduleEvent para garantir que a janela esteja totalmente carregada
    scheduleEvent(function()
        hunting_recorderModule.refreshCavebotsList()
    end, 50)
end

-- On cavebot list selection change
function hunting_recorderModule.onCavebotListSelectionChange(item)
    if item then
        selectedCavebotName = item:getText()
    else
        selectedCavebotName = nil
    end
end

-- Confirm new cavebot creation (always asks for confirmation)
function hunting_recorderModule.confirmNewCavebot()
    g_logger.info("[Cavebot] confirmNewCavebot called")
    
    local messageBox
    local onCancel = function()
        if messageBox and not messageBox:isDestroyed() then
            messageBox:destroy()
        end
    end
    local onConfirm = function()
        if messageBox and not messageBox:isDestroyed() then
            messageBox:destroy()
        end
        hunting_recorderModule.clearCurrentCavebot()
    end
    messageBox = helperDisplayGeneralBox(
        "Confirm New Cavebot",
        "Are you sure you want to create a new cavebot?\n\nThis will:\n- Delete all waypoints\n- Delete all minimap markers\n- Delete special waypoints\n- Reset all settings",
        {
            { text = "No", callback = onCancel },
            { text = "Yes", callback = onConfirm }
        },
        onConfirm,
        onCancel
    )
end

function hunting_recorderModule.clearCurrentCavebot()
    g_logger.info("[Cavebot] clearCurrentCavebot called")

    local currentCavebotData = hunting_recorderModule.getCurrentCavebotData()
    local currentName = currentCavebotData and currentCavebotData.name or nil

    if currentName and currentName ~= "" then
        if huntingWaypointsWindow then
            local enableCaveBot = huntingWaypointsWindow:recursiveGetChildById('enableCaveBot')
            if enableCaveBot and enableCaveBot:isChecked() then
                enableCaveBot:setChecked(false)
            end
        end
    end
    
    -- Desativar auto record se estiver ligado
    if huntingWaypointsWindow then
        local buttonsPanel = huntingWaypointsWindow:recursiveGetChildById('buttons')
        if buttonsPanel then
            local autoRecordCheckBox = buttonsPanel:recursiveGetChildById('autoRecordCheckBox')
            if autoRecordCheckBox and autoRecordCheckBox:isChecked() then
                autoRecordCheckBox.ignoreCallback = true
                autoRecordCheckBox:setChecked(false)
                autoRecordCheckBox.ignoreCallback = nil
                -- Salvar estado
                if modules.game_helper and modules.game_helper.setSettingsValue then
                    modules.game_helper.setSettingsValue(false, 'cavebot_auto_record', false)
                end
            end
        end
    end

    currentCavebotData = {
        name = "",
        waypoints = {},
        specialAreas = {},
        config = {
            nodeDistance = 2,
            stopToKillDistance = 2,
            creaturesToStop = 8,
            creaturesToWalk = 2,
            lureMode = true,
            lureSpeed = 5,
            walkDelay = 20,
            avoidTrap = true,
            trapDistance = 1,
            creaturesToAvoid = 7,
            ignoredCreatures = {},
            startFromNearest = true,
            debugPos = false,
            lureDebug = false,
            lureCheckRangeX = 6,
            lureCheckRangeY = 4,
            staminaToLeave = 39,
            staminaToReturn = 42,
            capToLeave = 500,
            deathsToDisable = 0
        },
        supplies = {},
        supplySettings = {}
    }

    print("[CLEAR DEBUG] Limpando cavebot...")

    if huntingWaypointsWindow and huntingWaypointsWindow.settings then
        if huntingWaypointsWindow.settings.main and huntingWaypointsWindow.settings.main.waypoints then
            if huntingWaypointsWindow.settings.main.waypoints.list then
                local wpCount = huntingWaypointsWindow.settings.main.waypoints.list:getChildCount()
                print(string.format("[CLEAR DEBUG] Limpando %d waypoints da lista", wpCount))
                huntingWaypointsWindow.settings.main.waypoints.list:destroyChildren()
            end
            if huntingWaypointsWindow.settings.main.waypoints.specialList then
                local specialCount = huntingWaypointsWindow.settings.main.waypoints.specialList:getChildCount()
                print(string.format("[CLEAR DEBUG] Limpando %d special areas da lista", specialCount))
                huntingWaypointsWindow.settings.main.waypoints.specialList:destroyChildren()
            end
        end

        if huntingWaypointsWindow.map and huntingWaypointsWindow.map.minimap then
            print("[CLEAR DEBUG] Chamando clearMinimapWaypoints...")
            clearMinimapWaypoints(huntingWaypointsWindow.map.minimap)
            print("[CLEAR DEBUG] clearMinimapWaypoints concluido")
        else
            print("[CLEAR DEBUG] ERRO: minimap nao encontrado!")
        end
    else
        print("[CLEAR DEBUG] ERRO: huntingWaypointsWindow nao encontrado!")
    end

    hunting_recorderModule.stopWalk()
    hunting_recorderModule.clearDebugPos()
    if modules.game_helper and modules.game_helper.hideDebugPopup then
        modules.game_helper.hideDebugPopup()
    end

    -- Limpar special areas do walker
    print("[CLEAR DEBUG] Limpando special areas do walker...")
    if cavebotWalker and cavebotWalker.updateConfig then
        cavebotWalker.updateConfig({specialAreas = {}})
        print("[CLEAR DEBUG] Special areas limpas do walker")
    else
        print("[CLEAR DEBUG] ERRO: cavebotWalker nao disponivel!")
    end

    -- Salvar os dados limpos
    hunting_recorderModule.setCurrentCavebotData(currentCavebotData)
    
    selectedCavebotName = nil
    hunting_recorderModule.refreshCavebotsList()
    hunting_recorderModule.refreshMainCavebotsList()
    hunting_recorderModule.updateCurrentCavebotLabel()
    
    -- Atualizar lista de supplies se o popup estiver aberto
    hunting_recorderModule.refreshSuppliesList()
    
    modules.game_textmessage.displayGameMessage("Cavebot cleared")
end

-- Create new cavebot (deletes everything and asks for a name)
function hunting_recorderModule.createNewCavebot()
    g_logger.info("[Cavebot] createNewCavebot called")

    local inputBox
    local okCallback = function(text)
        local cavebotName = text:trim()
        if cavebotName == "" then
            modules.game_textmessage.displayFailureMessage("Cavebot name cannot be empty")
            if inputBox then inputBox:destroy() end
            return
        end

        -- Check if cavebot already exists
        if g_resources.fileExists("/helper/cavebots/" .. cavebotName .. ".json") then
            if inputBox then inputBox:destroy() end
            local messageBox
            local onCancel = function()
                if messageBox and not messageBox:isDestroyed() then
                    messageBox:destroy()
                end
            end
            local onConfirm = function()
                if messageBox and not messageBox:isDestroyed() then
                    messageBox:destroy()
                end
                hunting_recorderModule.createNewCavebotConfirm(cavebotName)
            end
            messageBox = helperDisplayGeneralBox(
                "Overwrite Cavebot?",
                "The cavebot '" .. cavebotName .. "' already exists. Do you want to overwrite it?",
                {
                    { text = "No", callback = onCancel },
                    { text = "Yes", callback = onConfirm }
                },
                onConfirm,
                onCancel
            )
            return
        end

        if inputBox then inputBox:destroy() end
        hunting_recorderModule.createNewCavebotConfirm(cavebotName)
    end

    local cancelCallback = function()
        if inputBox then inputBox:destroy() end
    end

    inputBox = HelperUIInputBox.create("New Cavebot", okCallback, cancelCallback)
    inputBox:addLineEdit("Cavebot Name:", "")
    inputBox:display()
end

function hunting_recorderModule.createNewCavebotConfirm(cavebotName)
    -- Verificar se esta mudando de cavebot e desabilitar Enable Cavebot
    local currentCavebotData = hunting_recorderModule.getCurrentCavebotData()
    local currentName = currentCavebotData and currentCavebotData.name or nil
    
    if currentName and currentName ~= cavebotName then
        -- Desabilitar Enable Cavebot ao mudar de cavebot
        if huntingWaypointsWindow then
            local enableCaveBot = huntingWaypointsWindow:recursiveGetChildById('enableCaveBot')
            if enableCaveBot and enableCaveBot:isChecked() then
                enableCaveBot:setChecked(false)
            end
        end
    end
    
    -- Desativar auto record se estiver ligado
    if huntingWaypointsWindow then
        local buttonsPanel = huntingWaypointsWindow:recursiveGetChildById('buttons')
        if buttonsPanel then
            local autoRecordCheckBox = buttonsPanel:recursiveGetChildById('autoRecordCheckBox')
            if autoRecordCheckBox and autoRecordCheckBox:isChecked() then
                autoRecordCheckBox.ignoreCallback = true
                autoRecordCheckBox:setChecked(false)
                autoRecordCheckBox.ignoreCallback = nil
                -- Salvar estado
                if modules.game_helper and modules.game_helper.setSettingsValue then
                    modules.game_helper.setSettingsValue(false, 'cavebot_auto_record', false)
                end
            end
        end
    end
    
    -- Clear current cavebot data
    currentCavebotData = {
        name = cavebotName,
        waypoints = {},
        specialAreas = {},
        config = {
            nodeDistance = 2,
            stopToKillDistance = 2,
            creaturesToStop = 8,
            creaturesToWalk = 2,
            lureMode = true,
            lureSpeed = 5,
            walkDelay = 20,
            avoidTrap = true,
            trapDistance = 1,
            creaturesToAvoid = 7,
            ignoredCreatures = {},
            startFromNearest = true,
            debugPos = false,
            lureDebug = false,
            lureCheckRangeX = 6,
            lureCheckRangeY = 4,
            staminaToLeave = 39,
            staminaToReturn = 42,
            capToLeave = 500,
            deathsToDisable = 0
        },
        supplies = {},
        supplySettings = {}
    }
    
    -- Clear waypoints from UI
    if huntingWaypointsWindow and huntingWaypointsWindow.settings then
        if huntingWaypointsWindow.settings.main and huntingWaypointsWindow.settings.main.waypoints then
            if huntingWaypointsWindow.settings.main.waypoints.list then
                huntingWaypointsWindow.settings.main.waypoints.list:destroyChildren()
            end
            if huntingWaypointsWindow.settings.main.waypoints.specialList then
                huntingWaypointsWindow.settings.main.waypoints.specialList:destroyChildren()
            end
        end
        
        -- Clear minimap
        if huntingWaypointsWindow.map and huntingWaypointsWindow.map.minimap then
            clearMinimapWaypoints(huntingWaypointsWindow.map.minimap)
        end
    end

    -- Stop any active walk
    hunting_recorderModule.stopWalk()

    -- Reset waypoint index
    hunting_recorderModule.selectedSessionIndex = 0

    selectedCavebotName = cavebotName
    hunting_recorderModule.refreshCavebotsList()
    hunting_recorderModule.refreshMainCavebotsList()
    
    -- Atualizar lista de supplies se o popup estiver aberto
    hunting_recorderModule.refreshSuppliesList()
    
    modules.game_textmessage.displayGameMessage("New cavebot created: " .. cavebotName)
end

-- Load selected cavebot (clears everything first)
function hunting_recorderModule.loadSelectedCavebot()
    g_logger.info("[Cavebot] loadSelectedCavebot called")

    -- Get selected item from list
    if cavebotsManagerWindow then
        local cavebotsListBox = cavebotsManagerWindow:recursiveGetChildById("cavebotsListBox")
        if cavebotsListBox then
            local selectedItem = cavebotsListBox:getFocusedChild()
            if selectedItem then
                selectedCavebotName = selectedItem:getText()
            end
        end
    end

    if not selectedCavebotName or selectedCavebotName == "" then
        modules.game_textmessage.displayFailureMessage("Select a cavebot to load.")
        return
    end
    
    -- Verificar se esta mudando de cavebot e desabilitar Enable Cavebot (antes de limpar)
    local currentCavebotData = hunting_recorderModule.getCurrentCavebotData()
    local currentName = currentCavebotData and currentCavebotData.name or nil
    
    if currentName and currentName ~= selectedCavebotName then
        -- Desabilitar Enable Cavebot ao mudar de cavebot
        if huntingWaypointsWindow then
            local enableCaveBot = huntingWaypointsWindow:recursiveGetChildById('enableCaveBot')
            if enableCaveBot and enableCaveBot:isChecked() then
                enableCaveBot:setChecked(false)
            end
        end
    end

    -- Cancel any in-progress chunked loading
    hunting_recorderModule.cancelChunkedLoad()
    hunting_recorderModule.cancelMapChunkedLoad()

    -- Stop any active walk first
    hunting_recorderModule.stopWalk()
    
    -- Clear debug widgets when changing cavebot
    hunting_recorderModule.clearDebugPos()

    -- Clear current cavebot data completely
    currentCavebotData = {
        name = "",
        waypoints = {},
        specialAreas = {},
        config = {
            nodeDistance = 2,
            stopToKillDistance = 2,
            creaturesToStop = 8,
            creaturesToWalk = 2,
            lureMode = true,
            lureSpeed = 5,
            walkDelay = 20,
            avoidTrap = true,
            trapDistance = 1,
            creaturesToAvoid = 7,
            ignoredCreatures = {},
            startFromNearest = true,
            debugPos = false,
            lureDebug = false,
            lureCheckRangeX = 6,
            lureCheckRangeY = 4,
            staminaToLeave = 39,
            staminaToReturn = 42,
            capToLeave = 500,
            deathsToDisable = 0
        },
        supplies = {},
        supplySettings = {}
    }

    -- Clear waypoints from UI
    if huntingWaypointsWindow and huntingWaypointsWindow.settings then
        if huntingWaypointsWindow.settings.main and huntingWaypointsWindow.settings.main.waypoints then
            if huntingWaypointsWindow.settings.main.waypoints.list then
                huntingWaypointsWindow.settings.main.waypoints.list:destroyChildren()
            end
            if huntingWaypointsWindow.settings.main.waypoints.specialList then
                huntingWaypointsWindow.settings.main.waypoints.specialList:destroyChildren()
            end
        end

        -- Clear minimap
        if huntingWaypointsWindow.map and huntingWaypointsWindow.map.minimap then
            local minimap = huntingWaypointsWindow.map.minimap
            clearMinimapWaypoints(minimap)
        end
    end

    -- Now load the selected cavebot
    local cavebotData = loadCavebotFromFile(selectedCavebotName)
    if not cavebotData then
        modules.game_textmessage.displayFailureMessage("Failed to load cavebot: " .. selectedCavebotName)
        return
    end

    -- Load cavebot data
    currentCavebotData = cavebotData
    currentCavebotData.name = selectedCavebotName
    hunting_recorderModule.normalizeCavebotData(currentCavebotData)
    
    -- Garantir que os dados sejam salvos corretamente
    hunting_recorderModule.setCurrentCavebotData(currentCavebotData)
    
    -- Clear and reload waypoints in UI
    if huntingWaypointsWindow and huntingWaypointsWindow.settings then
        if huntingWaypointsWindow.settings.main and huntingWaypointsWindow.settings.main.waypoints then
            if huntingWaypointsWindow.settings.main.waypoints.list then
                huntingWaypointsWindow.settings.main.waypoints.list:destroyChildren()
            end
        end
        
        -- Clear minimap
        if huntingWaypointsWindow.map and huntingWaypointsWindow.map.minimap then
            local minimap = huntingWaypointsWindow.map.minimap
            clearMinimapWaypoints(minimap)
        end
        
        -- Reload waypoints (chunked async to avoid freezing)
        if currentCavebotData.waypoints then
            local sortedWaypoints = {}
            for _, waypoint in pairs(currentCavebotData.waypoints) do
                table.insert(sortedWaypoints, waypoint)
            end
            table.sort(sortedWaypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)

            -- Use chunked loading for large waypoint lists
            hunting_recorderModule.loadWaypointsChunked(sortedWaypoints, currentCavebotData.waypoints)
        end
        hunting_recorderModule.reloadSpecialAreasList()
    end
    
    -- Update checkboxes from config
    if huntingWaypointsWindow then
        local buttonsPanel = huntingWaypointsWindow:recursiveGetChildById('buttons')
        if buttonsPanel then
            local config = currentCavebotData.config or {}
            local startFromNearestCheckBox = buttonsPanel:recursiveGetChildById('startFromNearestCheckBox')
            if startFromNearestCheckBox then
                startFromNearestCheckBox:setChecked(config.startFromNearest ~= false) -- Default to true
            end
            local debugPosCheckBox = buttonsPanel:recursiveGetChildById('debugPosCheckBox')
            if debugPosCheckBox then
                debugPosCheckBox:setChecked(config.debugPos == true) -- Default to false
                -- Sincroniza o HUD nativo de waypoints com a config carregada
                if CaveBot and CaveBot.WaypointHud and CaveBot.WaypointHud.setEnabled then
                    CaveBot.WaypointHud.setEnabled(config.debugPos == true)
                end
            end
        end
    end
    
    hunting_recorderModule.updateCurrentCavebotLabel()
    hunting_recorderModule.refreshMainCavebotsList()
    
    -- Atualizar lista de supplies se o popup estiver aberto
    hunting_recorderModule.refreshSuppliesList()
    
    modules.game_textmessage.displayGameMessage("Cavebot loaded: " .. selectedCavebotName)

    -- Reset gold balance session when switching scripts
    hunting_recorderModule.captureInitialGoldBalance()
end

-- ============================================================================
-- CHUNKED ASYNC LOADING (prevents freezing with large waypoint lists)
-- ============================================================================

-- Cancel any ongoing chunked loading
local chunkedLoadEvent = nil
local chunkedLoadCancelled = false

function hunting_recorderModule.cancelChunkedLoad()
    chunkedLoadCancelled = true
    if chunkedLoadEvent then
        removeEvent(chunkedLoadEvent)
        chunkedLoadEvent = nil
    end
end

-- Load waypoints in batches to avoid freezing
-- CHUNK_SIZE controls how many waypoints are created per frame tick
local WAYPOINT_CHUNK_SIZE = 50
local MAP_CHUNK_SIZE = 30

function hunting_recorderModule.loadWaypointsChunked(sortedWaypoints, rawWaypoints, onComplete)
    -- Cancel any previous chunked load in progress
    hunting_recorderModule.cancelChunkedLoad()
    chunkedLoadCancelled = false

    local totalWaypoints = #sortedWaypoints
    if totalWaypoints == 0 then
        if onComplete then onComplete() end
        return
    end

    local currentIndex = 1

    local function processNextChunk()
        if chunkedLoadCancelled then return end

        -- Safety: check UI still exists
        if not huntingWaypointsWindow or not huntingWaypointsWindow.settings then return end
        if not huntingWaypointsWindow.settings.main or not huntingWaypointsWindow.settings.main.waypoints then return end
        if not huntingWaypointsWindow.settings.main.waypoints.list then return end

        local endIndex = math.min(currentIndex + WAYPOINT_CHUNK_SIZE - 1, totalWaypoints)

        for i = currentIndex, endIndex do
            local waypoint = sortedWaypoints[i]
            if waypoint and waypoint.position then
                hunting_recorderModule.createBrandNewSessionWaypoint(
                    waypoint.position, true,
                    waypoint.index or 1,
                    waypoint.type or 0,
                    waypoint.label,
                    waypoint.gotoCondition,
                    waypoint.gotoStamina,
                    waypoint.labelHasSupply,
                    waypoint.labelNoSupply,
                    waypoint.waitStaminaMinutes,
                    waypoint.waitDelayMs,
                    waypoint.levitateMode,
                    waypoint.levitateDir
                )
            end
        end

        currentIndex = endIndex + 1

        if currentIndex <= totalWaypoints then
            -- Schedule next chunk - yield to event loop so UI stays responsive
            chunkedLoadEvent = scheduleEvent(processNextChunk, 5)
        else
            -- All waypoints loaded - now load map display in chunks too
            chunkedLoadEvent = nil
            g_logger.info(string.format("[Cavebot] All %d waypoint widgets created (chunked)", totalWaypoints))
            hunting_recorderModule.displayWaypointsOnMapChunked(rawWaypoints)
            if onComplete then onComplete() end
        end
    end

    g_logger.info(string.format("[Cavebot] Starting chunked load of %d waypoints (chunks of %d)", totalWaypoints, WAYPOINT_CHUNK_SIZE))
    processNextChunk()
end

-- ============================================================================
-- CHUNKED MAP DISPLAY (lazy pathfinding - avoids freezing with many waypoints)
-- ============================================================================

local mapChunkedEvent = nil

function hunting_recorderModule.cancelMapChunkedLoad()
    if mapChunkedEvent then
        removeEvent(mapChunkedEvent)
        mapChunkedEvent = nil
    end
end

function hunting_recorderModule.displayWaypointsOnMapChunked(waypoints)
    hunting_recorderModule.cancelMapChunkedLoad()

    if not huntingWaypointsWindow or not huntingWaypointsWindow.map or not huntingWaypointsWindow.map.minimap then
        return
    end

    if not waypoints or #waypoints == 0 then
        return
    end

    local minimap = huntingWaypointsWindow.map.minimap

    -- Sort waypoints by index
    local sortedWaypoints = {}
    for _, waypoint in pairs(waypoints) do
        table.insert(sortedWaypoints, waypoint)
    end
    table.sort(sortedWaypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)

    local totalWaypoints = #sortedWaypoints
    local currentIndex = 1
    local lastPosition = nil

    local function processNextMapChunk()
        if chunkedLoadCancelled then return end

        -- Safety: check UI still exists
        if not huntingWaypointsWindow or not huntingWaypointsWindow.map or not huntingWaypointsWindow.map.minimap then
            return
        end

        local endIndex = math.min(currentIndex + MAP_CHUNK_SIZE - 1, totalWaypoints)

        for i = currentIndex, endIndex do
            local waypoint = sortedWaypoints[i]
            if waypoint and waypoint.position then
                local pos = waypoint.position

                -- Add connectors between waypoints (pathfinding)
                -- Skip pathfinding for large scripts to avoid freeze - only add flags
                if lastPosition and totalWaypoints <= 500 then
                    local path = g_map.findPathJPS(lastPosition, pos, 200, 0, true)
                    if path and #path > 0 then
                        local currentPos = { x = lastPosition.x, y = lastPosition.y, z = lastPosition.z }
                        local ignoreNext = false
                        for _, dir in ipairs(path) do
                            if dir == 0 then currentPos.y = currentPos.y - 1
                            elseif dir == 1 then currentPos.x = currentPos.x + 1
                            elseif dir == 2 then currentPos.y = currentPos.y + 1
                            elseif dir == 3 then currentPos.x = currentPos.x - 1
                            elseif dir == 4 then currentPos.y = currentPos.y - 1; currentPos.x = currentPos.x + 1
                            elseif dir == 5 then currentPos.x = currentPos.x + 1; currentPos.y = currentPos.y + 1
                            elseif dir == 6 then currentPos.x = currentPos.x - 1; currentPos.y = currentPos.y + 1
                            elseif dir == 7 then currentPos.x = currentPos.x - 1; currentPos.y = currentPos.y - 1 end
                            if not ignoreNext then
                                ignoreNext = true
                                local connector = createNode('connector', { x = currentPos.x, y = currentPos.y, z = currentPos.z })
                                minimap:addAlternativeWidget(connector, { x = currentPos.x, y = currentPos.y, z = currentPos.z })
                            else
                                ignoreNext = false
                            end
                        end
                    end
                end

                -- Determine waypoint icon
                local isTeleport = waypoint.teleport or false
                local flagIcon = 9  -- Default: walk waypoint
                if isTeleport then
                    local nextWaypoint = sortedWaypoints[i + 1]
                    if nextWaypoint and nextWaypoint.position then
                        if nextWaypoint.position.z > pos.z then
                            flagIcon = 19
                        elseif nextWaypoint.position.z < pos.z then
                            flagIcon = 18
                        else
                            flagIcon = 15
                        end
                    else
                        flagIcon = 15
                    end
                end
                local specialFlagIcon = getSpecialActionFlagIcon(waypoint.type)
                if specialFlagIcon then
                    flagIcon = specialFlagIcon
                end

                local flagDescription = 'Waypoint ' .. (waypoint.index or i) .. ' (' .. pos.x .. ', ' .. pos.y .. ', ' .. pos.z .. ') [' .. waypointTypeToName(waypoint.type) .. ']'
                if minimap.addFlag then minimap:addFlag(pos, flagIcon, flagDescription, true) end

                lastPosition = { x = pos.x, y = pos.y, z = pos.z }
            end
        end

        currentIndex = endIndex + 1

        if currentIndex <= totalWaypoints then
            -- Schedule next chunk
            mapChunkedEvent = scheduleEvent(processNextMapChunk, 5)
        else
            mapChunkedEvent = nil
            if totalWaypoints > 500 then
                g_logger.info(string.format("[Cavebot] Map flags added for %d waypoints (pathfinding connectors skipped for performance - script has >500 waypoints)", totalWaypoints))
            else
                g_logger.info(string.format("[Cavebot] Map display complete for %d waypoints (chunked)", totalWaypoints))
            end
        end
    end

    g_logger.info(string.format("[Cavebot] Starting chunked map display for %d waypoints", totalWaypoints))
    processNextMapChunk()
end

-- ============================================================================
-- HELPER: Reload all waypoints in UI (chunked) - replaces repeated pattern
-- ============================================================================
function hunting_recorderModule.reloadAllWaypointsUI(waypoints, onComplete)
    if not huntingWaypointsWindow or not huntingWaypointsWindow.settings then return end
    if not huntingWaypointsWindow.settings.main or not huntingWaypointsWindow.settings.main.waypoints then return end

    local waypointsList = huntingWaypointsWindow.settings.main.waypoints.list
    if waypointsList then
        waypointsList:destroyChildren()
    end
    previouslySelectedWidget = nil
    waypointWidgetLookup = {}
    hunting_recorderModule.invalidateDebugPosCache()

    -- Clear minimap
    if huntingWaypointsWindow.map and huntingWaypointsWindow.map.minimap then
        clearMinimapWaypoints(huntingWaypointsWindow.map.minimap)
    end

    if not waypoints or #waypoints == 0 then
        if onComplete then onComplete() end
        return
    end

    -- Sort and use chunked loading
    local sorted = {}
    for _, wp in ipairs(waypoints) do
        table.insert(sorted, wp)
    end
    table.sort(sorted, function(a, b) return (a.index or 0) < (b.index or 0) end)
    hunting_recorderModule.loadWaypointsChunked(sorted, waypoints, onComplete)
end

-- Save current cavebot (always asks for name confirmation)
function hunting_recorderModule.saveCurrentCavebot()
    g_logger.info("[Cavebot] saveCurrentCavebot called")

    local currentName = currentCavebotData.name or ""
    if cavebotsManagerWindow and selectedCavebotName and selectedCavebotName ~= "" then
        currentName = selectedCavebotName
    end

    local inputBox
    -- Always ask for name, but pre-load the current name if it exists
    local okCallback = function(text)
        local cavebotName = text:trim()
        if cavebotName == "" then
            modules.game_textmessage.displayFailureMessage("Cavebot name cannot be empty")
            if inputBox then inputBox:destroy() end
            return
        end

        -- Check if file exists and ask to overwrite
        if g_resources.fileExists("/helper/cavebots/" .. cavebotName .. ".json") then
            if inputBox then inputBox:destroy() end
            local messageBox
            local onCancel = function()
                if messageBox and not messageBox:isDestroyed() then
                    messageBox:destroy()
                end
            end
            local onConfirm = function()
                if messageBox and not messageBox:isDestroyed() then
                    messageBox:destroy()
                end
                hunting_recorderModule.saveCavebotWithName(cavebotName)
            end
            messageBox = helperDisplayGeneralBox(
                "Overwrite Cavebot?",
                "The cavebot '" .. cavebotName .. "' already exists. Do you want to overwrite it?",
                {
                    { text = "No", callback = onCancel },
                    { text = "Yes", callback = onConfirm }
                },
                onConfirm,
                onCancel
            )
            return
        end

        if inputBox then inputBox:destroy() end
        hunting_recorderModule.saveCavebotWithName(cavebotName)
    end

    local cancelCallback = function()
        if inputBox then inputBox:destroy() end
    end

    inputBox = HelperUIInputBox.create("Save Cavebot", okCallback, cancelCallback)
    inputBox:addLineEdit("Cavebot Name:", currentName)
    inputBox:display()
end

function hunting_recorderModule.saveCavebotWithName(cavebotName)
    -- Collect current waypoints
    local waypoints = {}
    if huntingWaypointsWindow and huntingWaypointsWindow.settings then
        if huntingWaypointsWindow.settings.main and huntingWaypointsWindow.settings.main.waypoints then
            if huntingWaypointsWindow.settings.main.waypoints.list then
                for _, widget in ipairs(huntingWaypointsWindow.settings.main.waypoints.list:getChildren()) do
                    if widget.waypointIndex and widget.internalWaypointPosition then
                        -- Convert type to string for saving (new format)
                        local wpTypeStr = waypointTypeToString(widget.waypointType or 0)

                        local wp = {
                            index = widget.waypointIndex,
                            position = widget.internalWaypointPosition,
                            teleport = widget.teleport or false,
                            type = wpTypeStr -- Always save as string
                        }

                        -- Save goto parameters for goto waypoints
                        if wpTypeStr == 'goto' then
                            wp.label = widget.waypointLabel or ""
                            wp.gotoCondition = widget.gotoCondition or "none"
                            wp.gotoStamina = widget.gotoStamina or 0
                        -- Save label name for label waypoints
                        elseif wpTypeStr == 'label' then
                            wp.label = widget.waypointLabel or ""
                        -- Save script code for script waypoints (o codigo Lua vive em .label,
                        -- mesmo campo de texto livre do label/goto). Sem este branch o save
                        -- para arquivo reconstruia o waypoint sem o codigo e o script voltava
                        -- em branco ao recarregar.
                        elseif wpTypeStr == 'script' then
                            wp.label = widget.waypointLabel or ""
                        -- Save wait_delay parameters
                        elseif wpTypeStr == 'wait_delay' then
                            wp.waitDelayMs = widget.waitDelayMs
                        elseif wpTypeStr == 'levitate' then
                            wp.levitateMode = widget.levitateMode or "up"
                            wp.levitateDir = tonumber(widget.levitateDir) or 0
                        -- Save buy_refill parameters (same as buy_supply, but different type)
                        elseif wpTypeStr == 'buy_refill' then
                            -- buy_refill doesn't need special parameters, just the type
                        end

                        table.insert(waypoints, wp)
                    end
                end
            end
        end
    end
    
    local specialAreas = currentCavebotData.specialAreas or {}
    if huntingWaypointsWindow and huntingWaypointsWindow.settings then
        local specialList = huntingWaypointsWindow.settings.main.waypoints.specialList
        if specialList then
            specialAreas = {}
            for _, widget in ipairs(specialList:getChildren()) do
                if widget.specialAreaId and widget.internalWaypointPosition then
                    table.insert(specialAreas, {
                        id = widget.specialAreaId,
                        position = widget.internalWaypointPosition,
                        type = 90
                    })
                end
            end
        end
    end
    
    -- Collect checkbox states
    local startFromNearest = true
    local debugPos = false
    if huntingWaypointsWindow then
        local buttonsPanel = huntingWaypointsWindow:recursiveGetChildById('buttons')
        if buttonsPanel then
            local startFromNearestCheckBox = buttonsPanel:recursiveGetChildById('startFromNearestCheckBox')
            if startFromNearestCheckBox then
                startFromNearest = startFromNearestCheckBox:isChecked()
            end
            local debugPosCheckBox = buttonsPanel:recursiveGetChildById('debugPosCheckBox')
            if debugPosCheckBox then
                debugPos = debugPosCheckBox:isChecked()
            end
        end
    end
    
    -- Coletar supplies do popup se estiver aberto, caso contrario usar os dados atuais
    local supplies, supplySettings
    if suppliesPopup and not suppliesPopup:isDestroyed() then
        supplies, supplySettings = collectSuppliesFromPopup()
    else
        -- Se o popup nao estiver aberto, usar os dados atuais
        supplies = currentCavebotData.supplies or {}
        supplySettings = currentCavebotData.supplySettings or {}
    end
    
    -- Garantir que existam 10 slots de supplies
    for i = 1, 10 do
        if supplies[i] == nil then
            supplies[i] = 0
        end
        if not supplySettings[i] then
            supplySettings[i] = {minSupply = 0, buySupply = 1}
        end
    end
    
    -- Update current cavebot data
    currentCavebotData.name = cavebotName
    currentCavebotData.waypoints = waypoints
    currentCavebotData.specialAreas = specialAreas
    currentCavebotData.supplies = supplies
    currentCavebotData.supplySettings = supplySettings
    
    -- Update config with checkbox states
    if not currentCavebotData.config then
        currentCavebotData.config = {}
    end
    currentCavebotData.config.startFromNearest = startFromNearest
    currentCavebotData.config.debugPos = debugPos
    
    -- Normalizar dados antes de salvar
    hunting_recorderModule.normalizeCavebotData(currentCavebotData)
    
    -- Save to file
    local saved = saveCavebotToFile(cavebotName, currentCavebotData, true)
    if saved then
        selectedCavebotName = cavebotName
        hunting_recorderModule.refreshCavebotsList()
        hunting_recorderModule.updateCurrentCavebotLabel()
        hunting_recorderModule.refreshMainCavebotsList()
        modules.game_textmessage.displayGameMessage("Cavebot saved: " .. cavebotName)
    else
        modules.game_textmessage.displayFailureMessage("Failed to save cavebot: " .. cavebotName)
    end
end

-- Delete selected cavebot (removes from list and deletes file)
function hunting_recorderModule.deleteSelectedCavebot()
    g_logger.info("[Cavebot] deleteSelectedCavebot called")

    -- Get selected item from list
    if cavebotsManagerWindow then
        local cavebotsListBox = cavebotsManagerWindow:recursiveGetChildById("cavebotsListBox")
        if cavebotsListBox then
            local selectedItem = cavebotsListBox:getFocusedChild()
            if selectedItem then
                selectedCavebotName = selectedItem:getText()
            end
        end
    end

    if not selectedCavebotName or selectedCavebotName == "" then
        modules.game_textmessage.displayFailureMessage("Select a cavebot to delete.")
        return
    end

    local cavebotName = selectedCavebotName
    local messageBox
    local function closeMessageBox()
        if messageBox then
            messageBox:destroy()
            messageBox = nil
        end
    end

    local function onCancel()
        closeMessageBox()
    end

    local function onConfirm()
        closeMessageBox()
        if not cavebotName or cavebotName == "" then
            modules.game_textmessage.displayFailureMessage("Select a cavebot to delete.")
            return
        end

        local cavebotFile = "/helper/cavebots/" .. cavebotName .. ".json"

        -- Delete the file from disk
        local deleted = g_resources.deleteFile(cavebotFile)
        if not deleted then
            g_logger.warning("[Cavebot] Nao foi possivel deletar o arquivo: " .. cavebotFile)
            modules.game_textmessage.displayFailureMessage("Failed to delete cavebot: " .. cavebotName)
            return
        end

        -- If the deleted cavebot was the current one, clear it
        if currentCavebotData.name == cavebotName then
            currentCavebotData = {
                name = "",
                waypoints = {},
                specialAreas = {},
                config = {
                    nodeDistance = 2,
                    stopToKillDistance = 2,
                    creaturesToStop = 8,
                    creaturesToWalk = 2,
                    lureMode = true,
                    lureSpeed = 5,
                    walkDelay = 20,
                    avoidTrap = true,
                    trapDistance = 1,
                    creaturesToAvoid = 7,
                    ignoredCreatures = {},
                    startFromNearest = true,
                    debugPos = false,
                    lureDebug = false,
            lureCheckRangeX = 6,
            lureCheckRangeY = 4
        },
        supplies = {},
        supplySettings = {}
    }

    -- Clear waypoints from UI
            if huntingWaypointsWindow and huntingWaypointsWindow.settings then
                if huntingWaypointsWindow.settings.main and huntingWaypointsWindow.settings.main.waypoints then
                    if huntingWaypointsWindow.settings.main.waypoints.list then
                        huntingWaypointsWindow.settings.main.waypoints.list:destroyChildren()
                    end
                    if huntingWaypointsWindow.settings.main.waypoints.specialList then
                        huntingWaypointsWindow.settings.main.waypoints.specialList:destroyChildren()
                    end
                end

                -- Clear minimap
                if huntingWaypointsWindow.map and huntingWaypointsWindow.map.minimap then
                    local minimap = huntingWaypointsWindow.map.minimap
                    clearMinimapWaypoints(minimap)
                end
            end
        end

        local deletedName = cavebotName
        selectedCavebotName = nil

        -- Refresh all lists
        hunting_recorderModule.refreshCavebotsList()
        hunting_recorderModule.updateCurrentCavebotLabel()
        hunting_recorderModule.refreshMainCavebotsList()

        modules.game_textmessage.displayGameMessage("Cavebot deleted: " .. deletedName)
    end

    messageBox = helperDisplayGeneralBox(
        "Delete Cavebot",
        "Are you sure you want to delete the cavebot '" .. cavebotName .. "'? This action cannot be undone!",
        {
            { text = "No", callback = onCancel },
            { text = "Yes", callback = onConfirm }
        },
        onConfirm,
        onCancel
    )
end

-- Show context menu for cavebot item
function hunting_recorderModule.showCavebotContextMenu(item, mousePos, cavebotName)
    if not cavebotName or cavebotName == "" then
        return
    end

    selectedCavebotName = cavebotName
    
    -- Focar o item selecionado
    if item and item.focus then
        item:focus()
    end

    local menu = g_ui.createWidget('HelperPopupMenu')
    menu:setGameMenu(true)
    
    menu:addOption(tr('Load'), function()
        hunting_recorderModule.loadSelectedCavebot()
    end)
    
    menu:addOption(tr('Rename'), function()
        hunting_recorderModule.renameCavebot(cavebotName)
    end)
    
    menu:addOption(tr('Delete'), function()
        hunting_recorderModule.deleteSelectedCavebot()
    end)
    
    menu:display(mousePos)
end

-- Handle right click on cavebots list (fallback)
function hunting_recorderModule.onCavebotsListMousePress(widget, mousePos, mouseButton)
    if mouseButton ~= MouseRightButton then
        return false
    end

    -- Get item at mouse position
    local selectedItem = widget:getSelectedItem()
    if not selectedItem then
        -- Try to get focused child as fallback
        selectedItem = widget:getFocusedChild()
    end
    if not selectedItem then
        return false
    end

    local cavebotName = selectedItem:getText()
    if not cavebotName or cavebotName == "" then
        return false
    end

    hunting_recorderModule.showCavebotContextMenu(selectedItem, mousePos, cavebotName)
    
    return true
end

-- Rename cavebot
function hunting_recorderModule.renameCavebot(oldName)
    g_logger.info("[Cavebot] renameCavebot called for: " .. oldName)

    if not oldName or oldName == "" then
        modules.game_textmessage.displayFailureMessage("Invalid cavebot name")
        return
    end

    local inputBox
    local okCallback = function(text)
        local newName = text:trim()
        if newName == "" then
            modules.game_textmessage.displayFailureMessage("Cavebot name cannot be empty")
            if inputBox then inputBox:destroy() end
            return
        end

        if newName == oldName then
            modules.game_textmessage.displayFailureMessage("O novo nome deve ser diferente do nome atual")
            if inputBox then inputBox:destroy() end
            return
        end

        -- Check if new name already exists
        if g_resources.fileExists("/helper/cavebots/" .. newName .. ".json") then
            if inputBox then inputBox:destroy() end
            local messageBox
            local onCancel = function()
                if messageBox and not messageBox:isDestroyed() then
                    messageBox:destroy()
                end
            end
            local onConfirm = function()
                if messageBox and not messageBox:isDestroyed() then
                    messageBox:destroy()
                end
                hunting_recorderModule.renameCavebotConfirm(oldName, newName)
            end
            messageBox = helperDisplayGeneralBox(
                "Overwrite Cavebot?",
                "The cavebot '" .. newName .. "' already exists. Do you want to overwrite it?",
                {
                    { text = "No", callback = onCancel },
                    { text = "Yes", callback = onConfirm }
                },
                onConfirm,
                onCancel
            )
            return
        end

        if inputBox then inputBox:destroy() end
        hunting_recorderModule.renameCavebotConfirm(oldName, newName)
    end

    local cancelCallback = function()
        if inputBox then inputBox:destroy() end
    end

    inputBox = HelperUIInputBox.create("Rename Cavebot", okCallback, cancelCallback)
    inputBox:addLineEdit("New Name:", oldName)
    inputBox:display()
end

-- Confirm rename cavebot
function hunting_recorderModule.renameCavebotConfirm(oldName, newName)
    g_logger.info("[Cavebot] renameCavebotConfirm: " .. oldName .. " -> " .. newName)

    local oldFile = "/helper/cavebots/" .. oldName .. ".json"
    local newFile = "/helper/cavebots/" .. newName .. ".json"

    -- Load old file
    local cavebotData = loadCavebotFromFile(oldName)
    if not cavebotData then
        modules.game_textmessage.displayFailureMessage("Failed to load cavebot: " .. oldName)
        return
    end

    -- Update name in data
    cavebotData.name = newName

    -- Save with new name
    local saved = saveCavebotToFile(newName, cavebotData, true)
    if not saved then
        modules.game_textmessage.displayFailureMessage("Failed to save cavebot with new name: " .. newName)
        return
    end

    -- Delete old file
    local deleted = g_resources.deleteFile(oldFile)
    if not deleted then
        g_logger.warning("[Cavebot] Nao foi possivel deletar o arquivo antigo: " .. oldFile)
        modules.game_textmessage.displayFailureMessage("Cavebot renamed, but could not delete the old file")
    end

    -- If the renamed cavebot was the current one, update it
    if currentCavebotData.name == oldName then
        currentCavebotData.name = newName
        hunting_recorderModule.setCurrentCavebotData(currentCavebotData)
        hunting_recorderModule.updateCurrentCavebotLabel()
    end

    -- Update selected name if it was the renamed one
    if selectedCavebotName == oldName then
        selectedCavebotName = newName
    end

    hunting_recorderModule.refreshCavebotsList()
    hunting_recorderModule.refreshMainCavebotsList()
    modules.game_textmessage.displayGameMessage("Cavebot renamed: " .. oldName .. " -> " .. newName)
end

-- Open cavebots folder
function hunting_recorderModule.openCavebotsFolder()
    g_logger.info("[Cavebot] openCavebotsFolder called")

    local writeDir = g_resources.getWriteDir()
    if not writeDir then
        modules.game_textmessage.displayFailureMessage("Could not get the write directory")
        return
    end

    -- Converter caminho virtual para caminho real do sistema
    local cavebotsDir = writeDir:gsub("[/\\]+", "\\") .. "helper\\cavebots"

    g_logger.info("[Cavebot] Abrindo pasta de cavebots")
    g_logger.info("[Cavebot] Caminho: " .. cavebotsDir)

    local success = g_platform.openDir(cavebotsDir)
    if success then
        modules.game_textmessage.displayGameMessage("Folder opened: " .. cavebotsDir)
    else
        modules.game_textmessage.displayFailureMessage("Failed to open folder: " .. cavebotsDir)
    end
end

-- Reload cavebots list (same as refresh but with user feedback)
function hunting_recorderModule.reloadCavebotsList()
    g_logger.info("[Cavebot] reloadCavebotsList called")

    hunting_recorderModule.refreshCavebotsList()
    modules.game_textmessage.displayGameMessage("Cavebots list reloaded.")
end

-- Refresh cavebots list in main window
function hunting_recorderModule.refreshMainCavebotsList()
    if not huntingWaypointsWindow then
        return
    end

    local buttonsPanel = huntingWaypointsWindow:recursiveGetChildById('buttons')
    if not buttonsPanel then
        return
    end

    local cavebotsList = buttonsPanel:recursiveGetChildById('cavebotsList')
    if not cavebotsList then
        return
    end

    cavebotsList:destroyChildren()

    local cavebotsDir = "/helper/cavebots"
    if not g_resources.directoryExists(cavebotsDir) then
        ensureCavebotsDirectory()
        return
    end

    local files = g_resources.listDirectoryFiles(cavebotsDir, false, false, false)

    if files then
        local cavebotNames = {}
        for _, fileName in pairs(files) do
            if fileName and fileName:match("%.json$") then
                local cavebotName = fileName:gsub("%.json$", "")
                if cavebotName and cavebotName ~= "" then
                    table.insert(cavebotNames, cavebotName)
                end
            end
        end

        table.sort(cavebotNames)

        local visibleIndex = 0
        for _, name in ipairs(cavebotNames) do
            visibleIndex = visibleIndex + 1
            local entry = g_ui.createWidget('CavebotListEntry', cavebotsList)
            entry:setText(name)
            entry.cavebotName = name
            
            -- Aplicar cores alternadas (zebra striping) - mesmo que cavebot list
            entry.baseBackgroundColor = visibleIndex % 2 == 0 and "#0a0a0a" or "#12121200"
            entry:setBackgroundColor(entry.baseBackgroundColor)
            if entry.updateOnStates then
                entry:updateOnStates()
            end

            -- Mark as active if it's the current cavebot
            local cavebotData = hunting_recorderModule.getCurrentCavebotData()
            if cavebotData and cavebotData.name == name then
                entry:setOn(true)
            end
            
            -- Handler de clique esquerdo para atualizar selecao visual
            entry.onClick = function()
                -- Atualizar selecao visual - apenas um deve estar selecionado
                for _, child in ipairs(cavebotsList:getChildren()) do
                    if child.cavebotName == name then
                        child:setOn(true)
                        child:focus()
                    else
                        child:setOn(false)
                    end
                    -- Atualizar cores
                    if child.updateOnStates then
                        child:updateOnStates()
                    end
                end
            end
            
            -- Adicionar menu de contexto no botao direito
            entry.onMouseRelease = function(widget, mousePos, mouseButton)
                if mouseButton == MouseRightButton then
                    local menu = g_ui.createWidget('HelperPopupMenu')
                    menu:setGameMenu(true)
                    menu:addOption("Load", function()
                        hunting_recorderModule.loadCavebotByName(entry.cavebotName)
                    end)
                    menu:display(mousePos)
                end
                return true
            end
        end
    end
end

-- Load cavebot by name (used by context menu)
function hunting_recorderModule.loadCavebotByName(cavebotName)
    if not cavebotName then
        return
    end

    -- Verificar se esta mudando de cavebot e desabilitar Enable Cavebot
    local currentCavebotData = hunting_recorderModule.getCurrentCavebotData()
    local currentName = currentCavebotData and currentCavebotData.name or nil
    
    if currentName and currentName ~= cavebotName then
        -- Desabilitar Enable Cavebot ao mudar de cavebot
        if huntingWaypointsWindow then
            local enableCaveBot = huntingWaypointsWindow:recursiveGetChildById('enableCaveBot')
            if enableCaveBot and enableCaveBot:isChecked() then
                enableCaveBot:setChecked(false)
            end
        end
    end

    -- Load the clicked cavebot
    local cavebotFile = "/helper/cavebots/" .. cavebotName .. ".json"

    if not g_resources.fileExists(cavebotFile) then
        modules.game_textmessage.displayFailureMessage("Cavebot not found: " .. cavebotName)
        return
    end

    local status, result = pcall(function() return json.decode(g_resources.readFileContents(cavebotFile)) end)
    if not status then
        modules.game_textmessage.displayFailureMessage("Failed to load cavebot: " .. cavebotName)
        return
    end

    -- Stop any active walk
    hunting_recorderModule.stopWalk()
    
    -- Clear debug widgets when changing cavebot
    hunting_recorderModule.clearDebugPos()

    -- Load cavebot data
    currentCavebotData = result
    currentCavebotData.name = cavebotName
    
    -- Normalizar dados (inicializa supplies e supplySettings corretamente)
    hunting_recorderModule.normalizeCavebotData(currentCavebotData)
    
    -- Garantir que os dados sejam salvos corretamente
    hunting_recorderModule.setCurrentCavebotData(currentCavebotData)

    -- Clear and reload waypoints in UI (chunked)
    if currentCavebotData.waypoints then
        hunting_recorderModule.reloadAllWaypointsUI(currentCavebotData.waypoints)
    end

    -- Update checkboxes from config
    if huntingWaypointsWindow then
        local buttonsPanel = huntingWaypointsWindow:recursiveGetChildById('buttons')
        if buttonsPanel then
            local config = currentCavebotData.config or {}
            local startFromNearestCheckBox = buttonsPanel:recursiveGetChildById('startFromNearestCheckBox')
            if startFromNearestCheckBox then
                startFromNearestCheckBox:setChecked(config.startFromNearest ~= false) -- Default to true
            end
            local debugPosCheckBox = buttonsPanel:recursiveGetChildById('debugPosCheckBox')
            if debugPosCheckBox then
                debugPosCheckBox:setChecked(config.debugPos == true) -- Default to false
                -- Sincroniza o HUD nativo de waypoints com a config carregada
                if CaveBot and CaveBot.WaypointHud and CaveBot.WaypointHud.setEnabled then
                    CaveBot.WaypointHud.setEnabled(config.debugPos == true)
                end
            end
        end
    end

    -- Refresh the list to update active state
    hunting_recorderModule.refreshMainCavebotsList()
    
    -- Atualizar label do cavebot atual
    hunting_recorderModule.updateCurrentCavebotLabel()
    
    -- Update debug POS display
    hunting_recorderModule.updateDebugPos()
    
    -- Atualizar lista de supplies se o popup estiver aberto
    hunting_recorderModule.refreshSuppliesList()

    modules.game_textmessage.displayGameMessage("Cavebot loaded: " .. cavebotName)

    -- Persist the loaded script name in the profile (allowlisted in isCavebotKey),
    -- so the next profile load re-preloads this same cavebot.
    if _G.helperConfig then
        _G.helperConfig.loadedCavebotName = cavebotName
    end

    -- Reset gold balance session when switching scripts
    hunting_recorderModule.captureInitialGoldBalance()
end

-- Delete selected waypoint
function hunting_recorderModule.deleteSelectedWaypoint()
    if not huntingWaypointsWindow or not huntingWaypointsWindow.settings then
        return
    end
    
    local waypointsList = huntingWaypointsWindow.settings.main.waypoints.list
    if not waypointsList then
        return
    end
    
    -- Find selected waypoint
    local selectedWidget = nil
    local selectedIndex = nil
    for _, widget in ipairs(waypointsList:getChildren()) do
        if widget.selectedWaypoint and widget.waypointIndex then
            selectedWidget = widget
            selectedIndex = widget.waypointIndex
            break
        end
    end
    
    if not selectedIndex then
        modules.game_textmessage.displayFailureMessage("No waypoint selected")
        return
    end
    
    -- Get current cavebot data
    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    local newList = {}
    for _, w in ipairs(cavebotData.waypoints or {}) do
        if w.index ~= selectedIndex then
            table.insert(newList, w)
        end
    end
    
    -- Reindex waypoints
    for i, w in ipairs(newList) do
        w.index = i
    end
    
    -- Update cavebot data
    cavebotData.waypoints = newList
    hunting_recorderModule.setCurrentCavebotData(cavebotData)
    
    -- Reload waypoints in UI (chunked to avoid freeze)
    waypointsList:destroyChildren()
    previouslySelectedWidget = nil
    if huntingWaypointsWindow.map and huntingWaypointsWindow.map.minimap then
        local minimap = huntingWaypointsWindow.map.minimap
        clearMinimapWaypoints(minimap)
    end

    -- Sort and use chunked loading
    local sorted = {}
    for _, wp in ipairs(newList) do
        table.insert(sorted, wp)
    end
    table.sort(sorted, function(a, b) return (a.index or 0) < (b.index or 0) end)
    local nextSelected = math.max(1, math.min((selectedIndex or 1) - 1, #newList))
    hunting_recorderModule.loadWaypointsChunked(sorted, newList, function()
        if #newList > 0 then
            hunting_recorderModule.selectWaypointByIndex(nextSelected)
        end
    end)

    -- Update debug position display
    hunting_recorderModule.updateDebugPos()

    -- Stop walk and disable cavebot
    hunting_recorderModule.stopWalk()
    if huntingWaypointsWindow then
        local enableCaveBot = huntingWaypointsWindow:recursiveGetChildById('enableCaveBot')
        if enableCaveBot and enableCaveBot:isChecked() then
            enableCaveBot:setChecked(false)
        end
    end

    modules.game_textmessage.displayGameMessage("Waypoint " .. selectedIndex .. " deleted")
end

function hunting_recorderModule.updateTabsVisualState(showSpecials)
    if not huntingWaypointsWindow or not huntingWaypointsWindow.settings then
        return
    end

    local waypointsPanel = huntingWaypointsWindow.settings.main.waypoints
    if not waypointsPanel then
        return
    end

    local tabsContainer = waypointsPanel:recursiveGetChildById('tabsContainer')
    if not tabsContainer then
        return
    end

    local waypointsTab = tabsContainer:recursiveGetChildById('waypointsTab')
    local specialsTab = tabsContainer:recursiveGetChildById('specialsTab')

    if waypointsTab and specialsTab then
        if showSpecials then
            waypointsTab:setChecked(false)
            waypointsTab:setBackgroundColor("#404040")
            specialsTab:setChecked(true)
            specialsTab:setBackgroundColor("#ffffff18")
        else
            waypointsTab:setChecked(true)
            waypointsTab:setBackgroundColor("#ffffff18")
            specialsTab:setChecked(false)
            specialsTab:setBackgroundColor("#404040")
        end
    end
end

function hunting_recorderModule.selectLastWaypoint()
    if not huntingWaypointsWindow or not huntingWaypointsWindow.settings then
        return
    end

    local waypointsList = huntingWaypointsWindow.settings.main.waypoints.list
    if not waypointsList then
        return
    end

    local children = waypointsList:getChildren()
    if #children == 0 then
        return
    end

    -- Encontrar o ultimo waypoint (maior index)
    local lastWidget = nil
    local lastIndex = 0
    for _, widget in ipairs(children) do
        if widget.waypointIndex and widget.waypointIndex > lastIndex then
            lastIndex = widget.waypointIndex
            lastWidget = widget
        end
    end

    if lastWidget then
        -- Deselect only previously selected
        if previouslySelectedWidget and not previouslySelectedWidget:isDestroyed() and previouslySelectedWidget ~= lastWidget then
            previouslySelectedWidget.mask:hide()
            previouslySelectedWidget.selectedWaypoint = false
            if previouslySelectedWidget.updateOnStates then
                previouslySelectedWidget:updateOnStates()
            end
        end
        -- Selecionar o ultimo
        lastWidget.mask:show()
        lastWidget.selectedWaypoint = true
        lastWidget:focus()
        waypointsList:ensureChildVisible(lastWidget)
        previouslySelectedWidget = lastWidget
        hunting_recorderModule.internalSelectWaypoint(lastWidget, lastIndex, false, false)
    end
end

function hunting_recorderModule.selectLastSpecialArea()
    if not huntingWaypointsWindow or not huntingWaypointsWindow.settings then
        return
    end

    local specialList = huntingWaypointsWindow.settings.main.waypoints.specialList
    if not specialList then
        return
    end

    local children = specialList:getChildren()
    if #children == 0 then
        return
    end

    -- Encontrar o ultimo special area (maior id)
    local lastWidget = nil
    local lastId = 0
    for _, widget in ipairs(children) do
        if widget.specialAreaId and widget.specialAreaId > lastId then
            lastId = widget.specialAreaId
            lastWidget = widget
        end
    end

    if lastWidget then
        -- Deselecionar todos
        for _, c in ipairs(children) do
            c.mask:hide()
            c.selectedSpecialArea = false
            if c.updateOnStates then
                c:updateOnStates()
            end
        end
        -- Selecionar o ultimo
        lastWidget.mask:show()
        lastWidget.selectedSpecialArea = true
        lastWidget:focus()
        specialList:ensureChildVisible(lastWidget)
        if lastWidget.internalWaypointPosition then
            huntingWaypointsWindow.map.minimap:setCameraPosition(lastWidget.internalWaypointPosition)
        end
    end
end

function hunting_recorderModule.selectWaypointByIndex(index)
    if not huntingWaypointsWindow or not huntingWaypointsWindow.settings then
        return
    end

    local waypointsList = huntingWaypointsWindow.settings.main.waypoints.list
    if not waypointsList then
        return
    end

    -- O(1) lookup
    local widget = waypointWidgetLookup[index]
    if widget and not widget:isDestroyed() then
        -- Deselect only previously selected
        if previouslySelectedWidget and not previouslySelectedWidget:isDestroyed() and previouslySelectedWidget ~= widget then
            previouslySelectedWidget.mask:hide()
            previouslySelectedWidget.selectedWaypoint = false
            if previouslySelectedWidget.updateOnStates then
                previouslySelectedWidget:updateOnStates()
            end
        end
        -- Select the target
        widget.mask:show()
        widget.selectedWaypoint = true
        widget:focus()
        waypointsList:ensureChildVisible(widget)
        previouslySelectedWidget = widget
        hunting_recorderModule.internalSelectWaypoint(widget, index, true, false)
    end
end

function hunting_recorderModule.selectWaypointByPosition(position, waypoints)
    if not position or not waypoints then
        return
    end
    
    -- Encontrar o índice do waypoint pela posição
    local finalIndex = nil
    for _, wp in ipairs(waypoints) do
        if wp.position and wp.position.x == position.x and wp.position.y == position.y and wp.position.z == position.z then
            finalIndex = wp.index
            break
        end
    end
    
    if finalIndex then
        scheduleEvent(function()
            hunting_recorderModule.selectWaypointByIndex(finalIndex)
        end, 50)
    end
end

function hunting_recorderModule.selectSpecialAreaById(id)
    if not huntingWaypointsWindow or not huntingWaypointsWindow.settings then
        return
    end

    local specialList = huntingWaypointsWindow.settings.main.waypoints.specialList
    if not specialList then
        return
    end

    local children = specialList:getChildren()
    for _, widget in ipairs(children) do
        if widget.specialAreaId == id then
            -- Deselecionar todos
            for _, c in ipairs(children) do
                c.mask:hide()
                c.selectedSpecialArea = false
                if c.updateOnStates then
                    c:updateOnStates()
                end
            end
            -- Selecionar o special area encontrado
            widget.mask:show()
            widget.selectedSpecialArea = true
            widget:focus()
            specialList:ensureChildVisible(widget)
            if widget.internalWaypointPosition then
                huntingWaypointsWindow.map.minimap:setCameraPosition(widget.internalWaypointPosition)
            end
            return
        end
    end
end

function hunting_recorderModule.switchToWaypointsTab()
    if not huntingWaypointsWindow or not huntingWaypointsWindow.settings then
        return
    end

    local waypointsPanel = huntingWaypointsWindow.settings.main.waypoints
    if not waypointsPanel then
        return
    end

    local waypointsList = waypointsPanel.list
    local listScroll = waypointsPanel.listScrollBar
    local specialList = waypointsPanel.specialList
    local specialScroll = waypointsPanel.specialListScrollBar
    local waypointButtons = waypointsPanel.waypointButtons
    local specialButtons = waypointsPanel.specialButtons

    if not waypointsList or not specialList or not waypointButtons or not specialButtons then
        return
    end

    specialList:hide()
    if specialScroll then specialScroll:hide() end
    specialButtons:hide()
    waypointsList:show()
    if listScroll then listScroll:show() end
    waypointButtons:show()
    
    hunting_recorderModule.updateTabsVisualState(false)
    
    -- Selecionar o ultimo waypoint ao entrar na aba
    scheduleEvent(function()
        hunting_recorderModule.selectLastWaypoint()
    end, 50)
end

function hunting_recorderModule.switchToSpecialsTab()
    if not huntingWaypointsWindow or not huntingWaypointsWindow.settings then
        return
    end

    local waypointsPanel = huntingWaypointsWindow.settings.main.waypoints
    if not waypointsPanel then
        return
    end

    local waypointsList = waypointsPanel.list
    local listScroll = waypointsPanel.listScrollBar
    local specialList = waypointsPanel.specialList
    local specialScroll = waypointsPanel.specialListScrollBar
    local waypointButtons = waypointsPanel.waypointButtons
    local specialButtons = waypointsPanel.specialButtons

    if not waypointsList or not specialList or not waypointButtons or not specialButtons then
        return
    end

    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    hunting_recorderModule.normalizeCavebotData(cavebotData)
    hunting_recorderModule.setCurrentCavebotData(cavebotData)
    waypointsList:hide()
    if listScroll then listScroll:hide() end
    waypointButtons:hide()
    specialList:show()
    if specialScroll then specialScroll:show() end
    specialButtons:show()
    hunting_recorderModule.reloadSpecialAreasList()
    
    hunting_recorderModule.updateTabsVisualState(true)
    
    -- Selecionar o ultimo special area ao entrar na aba
    scheduleEvent(function()
        hunting_recorderModule.selectLastSpecialArea()
    end, 50)
end

function hunting_recorderModule.toggleSpecialAreasList()
    if not huntingWaypointsWindow or not huntingWaypointsWindow.settings then
        return
    end

    local waypointsPanel = huntingWaypointsWindow.settings.main.waypoints
    if not waypointsPanel then
        return
    end

    local waypointsList = waypointsPanel.list
    local listScroll = waypointsPanel.listScrollBar
    local specialList = waypointsPanel.specialList
    local specialScroll = waypointsPanel.specialListScrollBar
    local waypointButtons = waypointsPanel.waypointButtons
    local specialButtons = waypointsPanel.specialButtons

    if not waypointsList or not specialList or not waypointButtons or not specialButtons then
        return
    end

    local showingSpecials = specialList:isVisible()
    if showingSpecials then
        hunting_recorderModule.switchToWaypointsTab()
    else
        hunting_recorderModule.switchToSpecialsTab()
    end
end

function hunting_recorderModule.deleteSelectedSpecialArea()
    if not huntingWaypointsWindow or not huntingWaypointsWindow.settings then
        return
    end

    local specialList = huntingWaypointsWindow.settings.main.waypoints.specialList
    if not specialList then
        return
    end

    local selectedId = nil
    local deletedIndex = nil
    local children = specialList:getChildren()

    -- Encontrar o special selecionado e seu índice
    for i, widget in ipairs(children) do
        if widget.selectedSpecialArea and widget.specialAreaId then
            selectedId = widget.specialAreaId
            deletedIndex = i
            break
        end
    end

    if not selectedId then
        modules.game_textmessage.displayFailureMessage("No special area selected")
        return
    end

    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    ensureSpecialAreasTable(cavebotData)

    local newList = {}
    for _, area in ipairs(cavebotData.specialAreas) do
        if area.id ~= selectedId then
            table.insert(newList, area)
        end
    end
    cavebotData.specialAreas = newList
    hunting_recorderModule.setCurrentCavebotData(cavebotData)
    if cavebotWalker and cavebotWalker.updateConfig then
        cavebotWalker.updateConfig({specialAreas = cavebotData.specialAreas})
    end

    hunting_recorderModule.reloadSpecialAreasList()
    hunting_recorderModule.updateDebugPos()

    -- Selecionar o special de índice menor após recarregar a lista
    if deletedIndex and deletedIndex > 1 then
        -- Selecionar o anterior (índice deletedIndex - 1)
        scheduleEvent(function()
            if not huntingWaypointsWindow or not huntingWaypointsWindow.settings then
                return
            end
            local newSpecialList = huntingWaypointsWindow.settings.main.waypoints.specialList
            if newSpecialList then
                local newChildren = newSpecialList:getChildren()
                local targetIndex = math.min(deletedIndex - 1, #newChildren)
                if targetIndex > 0 and newChildren[targetIndex] then
                    -- Simular clique no widget anterior
                    if newChildren[targetIndex].onClick then
                        newChildren[targetIndex]:onClick()
                    end
                end
            end
        end, 50)
    end
end

-- Clear all waypoints (with confirmation)
function hunting_recorderModule.clearAllWaypoints()
    if not huntingWaypointsWindow or not huntingWaypointsWindow.settings then
        return
    end
    
    local waypointsList = huntingWaypointsWindow.settings.main.waypoints.list
    if not waypointsList then
        return
    end
    
    -- Check if there are waypoints to clear
    if waypointsList:getChildCount() == 0 then
        modules.game_textmessage.displayGameMessage("No waypoints to clear")
        return
    end
    
    -- Show confirmation dialog
    local messageBox
    local onCancel = function()
        if messageBox and not messageBox:isDestroyed() then
            messageBox:destroy()
        end
    end
    local onConfirm = function()
        -- Get current cavebot data
        local cavebotData = hunting_recorderModule.getCurrentCavebotData()
        cavebotData.waypoints = {}
        hunting_recorderModule.setCurrentCavebotData(cavebotData)

        -- Clear waypoints from UI
        waypointsList:destroyChildren()

        -- Clear minimap
        if huntingWaypointsWindow.map and huntingWaypointsWindow.map.minimap then
            local minimap = huntingWaypointsWindow.map.minimap
            clearMinimapWaypoints(minimap)
        end

        -- Invalidate debug cache and update display
        hunting_recorderModule.invalidateDebugPosCache()
        hunting_recorderModule.updateDebugPos()

        -- Stop walk and disable cavebot
        hunting_recorderModule.stopWalk()
        if huntingWaypointsWindow then
            local enableCaveBot = huntingWaypointsWindow:recursiveGetChildById('enableCaveBot')
            if enableCaveBot and enableCaveBot:isChecked() then
                enableCaveBot:setChecked(false)
            end
        end

        -- Destroy message box after operations
        if messageBox and not messageBox:isDestroyed() then
            messageBox:destroy()
        end

        modules.game_textmessage.displayGameMessage("All waypoints have been deleted")
    end
    messageBox = helperDisplayGeneralBox(
        "Clear All Waypoints?",
        "Are you sure you want to delete all waypoints? This action cannot be undone!",
        {
            { text = "No", callback = onCancel },
            { text = "Yes", callback = onConfirm }
        },
        onConfirm,
        onCancel
    )
end

-- DEBUG POS -> overlay nativo de waypoints (CaveBot.WaypointHud, desenhado em C++
-- via g_map.addCavebotMark). As funcoes abaixo viraram wrappers finos que delegam
-- ao HUD; a implementacao antiga de UIWidgets sobrepostos por tile foi removida.
local pendingDebugPosEvent = nil

-- Debounced version: coalesces rapid calls into one update after 100ms
function hunting_recorderModule.scheduleDebugPosUpdate()
    if pendingDebugPosEvent then
        removeEvent(pendingDebugPosEvent)
        pendingDebugPosEvent = nil
    end
    pendingDebugPosEvent = scheduleEvent(function()
        pendingDebugPosEvent = nil
        hunting_recorderModule.updateDebugPos()
    end, 100)
end

-- DEBUG PATH: Store debug path widgets
local debugPathWidgets = {}

-- Update debug POS display -> delega ao HUD nativo de waypoints (+ Debug Path)
function hunting_recorderModule.updateDebugPos()
    if CaveBot and CaveBot.WaypointHud and CaveBot.WaypointHud.refresh then
        CaveBot.WaypointHud.refresh()
    end
    -- Debug Path (overlay de dev separado) continua acoplado ao DEBUG POS
    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if cavebotData and cavebotData.config and cavebotData.config.debugPath then
        hunting_recorderModule.updateDebugPath()
    end
end

-- Clear debug POS display -> desliga o overlay e limpa o Debug Path
function hunting_recorderModule.clearDebugPos()
    if pendingDebugPosEvent then
        removeEvent(pendingDebugPosEvent)
        pendingDebugPosEvent = nil
    end
    hunting_recorderModule.clearDebugPath()
    -- O HUD nativo se limpa sozinho quando desabilitado; um refresh garante isso.
    if CaveBot and CaveBot.WaypointHud and CaveBot.WaypointHud.refresh then
        CaveBot.WaypointHud.refresh()
    end
end

-- Mantida por compatibilidade: o HUD nativo nao usa cache Lua de waypoints.
function hunting_recorderModule.invalidateDebugPosCache()
end

-- Handler do checkbox DEBUG POS -> liga/desliga o HUD nativo de waypoints
function hunting_recorderModule.onDebugPosChange(widget)
    local enabled = widget:isChecked()
    -- Persiste no cavebot atual (per-cavebot)
    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if cavebotData then
        cavebotData.config = cavebotData.config or {}
        cavebotData.config.debugPos = enabled
    end
    if CaveBot and CaveBot.WaypointHud and CaveBot.WaypointHud.setEnabled then
        CaveBot.WaypointHud.setEnabled(enabled)
    end
    -- Debug Path acompanha o estado do DEBUG POS
    if enabled then
        if cavebotData and cavebotData.config and cavebotData.config.debugPath then
            hunting_recorderModule.updateDebugPath()
        end
    else
        hunting_recorderModule.clearDebugPath()
    end
end

-- Clear debug PATH display
function hunting_recorderModule.clearDebugPath()
    for _, widget in ipairs(debugPathWidgets) do
        if widget then
            pcall(function()
                if not widget:isDestroyed() then
                    if widget.pathPosition then
                        local tile = g_map.getTile(widget.pathPosition)
                        if tile then
                            pcall(function() tile:detachWidget(widget) end)
                        end
                    end
                    if not widget:isDestroyed() then
                        pcall(function() widget:destroy() end)
                    end
                end
            end)
        end
    end
    debugPathWidgets = {}
end

-- Update debug PATH display
function hunting_recorderModule.updateDebugPath()
    -- Remove all existing debug path widgets
    hunting_recorderModule.clearDebugPath()

    -- Check if debug path is enabled
    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData or not cavebotData.config then
        return
    end

    local config = cavebotData.config
    if not config.debugPath then
        return
    end

    -- Check if debug pos is also enabled
    if not huntingWaypointsWindow then
        return
    end

    local buttonsPanel = huntingWaypointsWindow:recursiveGetChildById('buttons')
    if not buttonsPanel then
        return
    end

    local debugPosCheckBox = buttonsPanel:recursiveGetChildById('debugPosCheckBox')
    local debugPosEnabled = false

    if not debugPosCheckBox then
        if not config.debugPos then
            return
        end
        debugPosEnabled = true
    else
        debugPosEnabled = debugPosCheckBox:isChecked()
        if not debugPosEnabled then
            return
        end
    end

    -- Get current path from walker
    if not cavebotWalker or not cavebotWalker.isActive() then
        return
    end

    local path, startPos = cavebotWalker.getCurrentPath()
    if not path or not startPos or #path == 0 then
        return
    end

    -- Get tile size
    local tileSize = 64
    if g_mapView and g_mapView.getTileSize then
        tileSize = g_mapView:getTileSize()
    elseif g_gameConfig and g_gameConfig.getSpriteSize then
        tileSize = g_gameConfig.getSpriteSize() * 2
    end

    -- Convert path directions to positions
    local currentPos = {x = startPos.x, y = startPos.y, z = startPos.z}
    
    -- Function to translate position by direction
    local function translatePosition(pos, direction)
        local nextPos = {x = pos.x, y = pos.y, z = pos.z}
        if direction == Directions.North then
            nextPos.y = nextPos.y - 1
        elseif direction == Directions.East then
            nextPos.x = nextPos.x + 1
        elseif direction == Directions.South then
            nextPos.y = nextPos.y + 1
        elseif direction == Directions.West then
            nextPos.x = nextPos.x - 1
        elseif direction == Directions.NorthEast then
            nextPos.y = nextPos.y - 1
            nextPos.x = nextPos.x + 1
        elseif direction == Directions.SouthEast then
            nextPos.y = nextPos.y + 1
            nextPos.x = nextPos.x + 1
        elseif direction == Directions.SouthWest then
            nextPos.y = nextPos.y + 1
            nextPos.x = nextPos.x - 1
        elseif direction == Directions.NorthWest then
            nextPos.y = nextPos.y - 1
            nextPos.x = nextPos.x - 1
        end
        return nextPos
    end

    -- Create widgets for each position in the path
    for i = 1, #path do
        local direction = path[i]
        currentPos = translatePosition(currentPos, direction)
        
        local tile = g_map.getTile(currentPos)
        if tile then
            local widget = g_ui.createWidget('UIWidget')
            widget:setId('debugPath_' .. i)
            widget.pathPosition = {x = currentPos.x, y = currentPos.y, z = currentPos.z}
            
            widget:setSize({width = tileSize, height = tileSize})
            widget:setPhantom(true)
            widget:setFocusable(false)
            widget:setBackgroundColor('#FF69B4B0') -- IMPROVED: Rosa com mais opacidade (~69% ao invés de ~31%)
            
            if tile.setWidget then tile:setWidget(widget) end
            table.insert(debugPathWidgets, widget)
        end
    end
end

-- Handler for DEBUG PATH checkbox
function hunting_recorderModule.onDebugPathChange(widget)
    if widget:isChecked() then
        hunting_recorderModule.updateDebugPath()
        -- Update debug pos to refresh both
        if hunting_recorderModule.updateDebugPos then
            hunting_recorderModule.updateDebugPos()
        end
    else
        hunting_recorderModule.clearDebugPath()
    end
end

-- Waypoint Creator Functions
_G.waypointCreatorConfig = _G.waypointCreatorConfig or { x = 0, y = 0 }

-- Fundo da janela com transparencia fixa (nao e mais configuravel via UI).
local CREATOR_BG_OPACITY = 30

local function getCreatorBgColor(opacity)
    if opacity <= 0 then
        return '#00000000'
    else
        local hex = string.format('%02X', math.floor(opacity * 2.55))
        return '#000000' .. hex
    end
end

local creatorSavePositionTimer = nil

local function saveCreatorPosition()
    if not waypointCreatorWindow then return end
    local pos = waypointCreatorWindow:getPosition()
    _G.waypointCreatorConfig.x = pos.x
    _G.waypointCreatorConfig.y = pos.y
    g_settings.set('waypointCreatorX', pos.x)
    g_settings.set('waypointCreatorY', pos.y)
end

local function scheduleSaveCreatorPosition()
    if creatorSavePositionTimer then
        removeEvent(creatorSavePositionTimer)
    end
    creatorSavePositionTimer = scheduleEvent(function()
        saveCreatorPosition()
        creatorSavePositionTimer = nil
    end, 500)
end

local function restoreCreatorPosition()
    if not waypointCreatorWindow then return end
    local x = _G.waypointCreatorConfig.x
    local y = _G.waypointCreatorConfig.y

    local savedX = g_settings.getNumber('waypointCreatorX')
    local savedY = g_settings.getNumber('waypointCreatorY')
    if savedX and savedX > 0 then x = savedX end
    if savedY and savedY > 0 then y = savedY end

    -- Se nenhuma posicao salva, centralizar na tela
    if x <= 0 or y <= 0 then
        local rootWidget = g_ui.getRootWidget()
        if rootWidget then
            local screenSize = rootWidget:getSize()
            local windowSize = waypointCreatorWindow:getSize()
            x = math.floor((screenSize.width - windowSize.width) / 2)
            y = math.floor((screenSize.height - windowSize.height) / 2)
        end
    end

    waypointCreatorWindow:setPosition({x = x, y = y})
    waypointCreatorWindow:setBackgroundColor(getCreatorBgColor(CREATOR_BG_OPACITY))
end

function hunting_recorderModule.closeWaypointCreator()
    if waypointCreatorWindow then
        saveCreatorPosition()
        waypointCreatorWindow:destroy()
        waypointCreatorWindow = nil
    end
end

function hunting_recorderModule.openWaypointCreator()
    if waypointCreatorWindow then
        hunting_recorderModule.closeWaypointCreator()
        return
    end
    
    local rootWidget = g_ui.getRootWidget()
    if not rootWidget then
        modules.game_textmessage.displayFailureMessage(htr("Failed to get root widget."))
        return
    end
    
    waypointCreatorWindow = g_ui.createWidget('WaypointCreatorWindow', rootWidget)
    if not waypointCreatorWindow then
        modules.game_textmessage.displayFailureMessage("Failed to load waypoint creator window.")
        return
    end
    
    -- Set onDestroy callback to clean up the global variable
    waypointCreatorWindow.onDestroy = function()
        waypointCreatorWindow = nil
    end

    -- Salvar posicao ao mover
    waypointCreatorWindow.onGeometryChange = function()
        scheduleSaveCreatorPosition()
    end

    -- Estado do hover e timer para delay
    local hoverState = false
    local hoverHideTimer = nil

    local function showHoverEffect()
        local dragArea = waypointCreatorWindow:getChildById('dragArea')
        if not dragArea then return end
        local dragHandle1 = dragArea:getChildById('dragHandle1')
        local dragHandle2 = dragArea:getChildById('dragHandle2')
        if dragHandle1 then dragHandle1:setVisible(true) end
        if dragHandle2 then dragHandle2:setVisible(true) end
        waypointCreatorWindow:setBackgroundColor('#000000AA')
    end

    local function hideHoverEffect()
        local dragArea = waypointCreatorWindow:getChildById('dragArea')
        if not dragArea then return end
        local dragHandle1 = dragArea:getChildById('dragHandle1')
        local dragHandle2 = dragArea:getChildById('dragHandle2')
        if dragHandle1 then dragHandle1:setVisible(false) end
        if dragHandle2 then dragHandle2:setVisible(false) end
        waypointCreatorWindow:setBackgroundColor(getCreatorBgColor(CREATOR_BG_OPACITY))
    end

    local function handleHoverChange(hovered)
        if hovered then
            if hoverHideTimer then
                removeEvent(hoverHideTimer)
                hoverHideTimer = nil
            end
            hoverState = true
            showHoverEffect()
        else
            if hoverHideTimer then
                removeEvent(hoverHideTimer)
            end
            hoverHideTimer = scheduleEvent(function()
                hoverState = false
                hideHoverEffect()
                hoverHideTimer = nil
            end, 50)
        end
    end

    -- Hover no window
    waypointCreatorWindow.onHoverChange = function(widget, hovered)
        handleHoverChange(hovered)
    end

    -- Configurar dragArea para drag manual
    local dragArea = waypointCreatorWindow:getChildById('dragArea')
    if dragArea then
        dragArea.onHoverChange = function(widget, hovered)
            handleHoverChange(hovered)
        end

        local isDragging = false
        local dragStartPos = nil
        local windowStartPos = nil

        dragArea.onMousePress = function(widget, mousePos, button)
            if button == MouseLeftButton then
                isDragging = true
                dragStartPos = mousePos
                windowStartPos = waypointCreatorWindow:getPosition()
                widget:grabMouse()
                return true
            end
            return false
        end

        dragArea.onMouseRelease = function(widget, mousePos, button)
            if button == MouseLeftButton and isDragging then
                isDragging = false
                dragStartPos = nil
                windowStartPos = nil
                widget:ungrabMouse()
                return true
            end
            return false
        end

        dragArea.onMouseMove = function(widget, mousePos, mouseMoved)
            if isDragging and dragStartPos and windowStartPos then
                local delta = {
                    x = mousePos.x - dragStartPos.x,
                    y = mousePos.y - dragStartPos.y
                }
                local newPos = {
                    x = windowStartPos.x + delta.x,
                    y = windowStartPos.y + delta.y
                }
                waypointCreatorWindow:setPosition(newPos)
                return true
            end
            return false
        end

    end

    -- Restaurar posicao salva
    restoreCreatorPosition()

    waypointCreatorWindow:show()
    waypointCreatorWindow:raise()
    waypointCreatorWindow:focus()
    
    -- Reset to defaults
    creatorWaypointType = 0
    creatorDirection = nil
    creatorMode = 'add'
    
    -- Get all checkboxes
    local dirC = waypointCreatorWindow:recursiveGetChildById('dirC')
    local modeAdd = waypointCreatorWindow:recursiveGetChildById('modeAdd')
    local modeReplace = waypointCreatorWindow:recursiveGetChildById('modeReplace')
    local modeInsert = waypointCreatorWindow:recursiveGetChildById('modeInsert')
    
    -- Set default checkbox states (Node and Stand are buttons, not checkboxes)
    if dirC then dirC:setChecked(true) end
    if modeAdd then modeAdd:setChecked(true) end
    if modeReplace then modeReplace:setChecked(false) end
    if modeInsert then modeInsert:setChecked(false) end
    
    -- Store direction checkboxes for group management
    local directionButtons = {
        dirNW = waypointCreatorWindow:recursiveGetChildById('dirNW'),
        dirN = waypointCreatorWindow:recursiveGetChildById('dirN'),
        dirNE = waypointCreatorWindow:recursiveGetChildById('dirNE'),
        dirW = waypointCreatorWindow:recursiveGetChildById('dirW'),
        dirC = dirC,
        dirE = waypointCreatorWindow:recursiveGetChildById('dirE'),
        dirSW = waypointCreatorWindow:recursiveGetChildById('dirSW'),
        dirS = waypointCreatorWindow:recursiveGetChildById('dirS'),
        dirSE = waypointCreatorWindow:recursiveGetChildById('dirSE')
    }
    waypointCreatorWindow.directionButtons = directionButtons
    
    -- Store mode checkboxes for group management
    local modeButtons = {
        modeReplace = modeReplace,
        modeAdd = modeAdd,
        modeInsert = modeInsert
    }
    waypointCreatorWindow.modeButtons = modeButtons

    -- Traduzir textos do Waypoint Creator
    local function trWidget(id, key)
        local w = waypointCreatorWindow:recursiveGetChildById(id)
        if w then w:setText(htr(key)) end
    end
    trWidget('titleLabel', 'Waypoint Creator')
    trWidget('waypointTypeLabel', 'Waypoint Type:')
    trWidget('directionLabel', 'Direction:')
    trWidget('modeLabel', 'Waypoint Mode:')
    trWidget('nodeButton', 'Node')
    trWidget('standButton', 'Stand')
    trWidget('ropeButton', 'Rope')
    trWidget('holeButton', 'Hole')
    trWidget('useButton', 'Use')
    trWidget('leverButton', 'Lever')
    trWidget('doorButton', 'Door')
    trWidget('labelButton', 'Label')
    trWidget('gotoButton', 'Goto')
    trWidget('waitDelayButton', 'Wait Delay')
    trWidget('stopToKillButton', 'STOP TO KILL')
    trWidget('specialAreaButton', 'Special Area')
    trWidget('modeReplace', 'Replace')
    trWidget('modeAdd', 'Add')
    trWidget('modeInsert', 'Insert')
    trWidget('closeButton', 'Close')
end

function hunting_recorderModule.setCreatorWaypointType(type)
    creatorWaypointType = type
    -- Node and Stand are now buttons that directly create waypoints, no need to set checked state
end

function hunting_recorderModule.setCreatorDirection(direction)
    creatorDirection = direction
    
    local window = waypointCreatorWindow
    if window and window.directionButtons then
        -- Uncheck all direction checkboxes
        for _, btn in pairs(window.directionButtons) do
            if btn and not btn:isDestroyed() then
                btn:setChecked(false)
            end
        end
        
        -- Check the selected one
        if direction == nil then
            local dirC = window.directionButtons and window.directionButtons.dirC
            if dirC and not dirC:isDestroyed() then
                dirC:setChecked(true)
            end
        else
            local directions = {
                [0] = 'dirN',
                [1] = 'dirE',
                [2] = 'dirS',
                [3] = 'dirW',
                [4] = 'dirNE',
                [5] = 'dirSE',
                [6] = 'dirSW',
                [7] = 'dirNW'
            }
            local btnId = directions[direction]
            if btnId and window.directionButtons and window.directionButtons[btnId] then
                local btn = window.directionButtons[btnId]
                if btn and not btn:isDestroyed() then
                    btn:setChecked(true)
                end
            end
        end
    end
end

function hunting_recorderModule.setCreatorMode(mode)
    creatorMode = mode
    
    local window = waypointCreatorWindow
    if window and window.modeButtons then
        -- Uncheck all mode checkboxes
        for _, btn in pairs(window.modeButtons) do
            if btn and not btn:isDestroyed() then
                btn:setChecked(false)
            end
        end
        
        -- Check the selected one
        if mode == 'replace' and window.modeButtons.modeReplace then
            local btn = window.modeButtons.modeReplace
            if btn and not btn:isDestroyed() then
                btn:setChecked(true)
            end
        elseif mode == 'add' and window.modeButtons.modeAdd then
            local btn = window.modeButtons.modeAdd
            if btn and not btn:isDestroyed() then
                btn:setChecked(true)
            end
        elseif mode == 'insert' and window.modeButtons.modeInsert then
            local btn = window.modeButtons.modeInsert
            if btn and not btn:isDestroyed() then
                btn:setChecked(true)
            end
        end
    end
end

function hunting_recorderModule.createWaypointFromCreatorWithType(waypointType)
    creatorWaypointType = waypointType
    hunting_recorderModule.createWaypointFromCreator()
end

function hunting_recorderModule.createWaypointFromCreator()
    local player = g_game.getLocalPlayer()
    if not player then
        modules.game_textmessage.displayFailureMessage("Player not found")
        return
    end
    
    local currentPos = player:getPosition()
    if not currentPos then
        modules.game_textmessage.displayFailureMessage("Could not get player position")
        return
    end
    
    -- Calculate new position based on direction
    local newPos = {x = currentPos.x, y = currentPos.y, z = currentPos.z}
    
    if creatorDirection ~= nil then
        -- Direction mapping: 0=N, 1=E, 2=S, 3=W, 4=NE, 5=SE, 6=SW, 7=NW
        if creatorDirection == 0 then -- North
            newPos.y = newPos.y - 1
        elseif creatorDirection == 1 then -- East
            newPos.x = newPos.x + 1
        elseif creatorDirection == 2 then -- South
            newPos.y = newPos.y + 1
        elseif creatorDirection == 3 then -- West
            newPos.x = newPos.x - 1
        elseif creatorDirection == 4 then -- Northeast
            newPos.x = newPos.x + 1
            newPos.y = newPos.y - 1
        elseif creatorDirection == 5 then -- Southeast
            newPos.x = newPos.x + 1
            newPos.y = newPos.y + 1
        elseif creatorDirection == 6 then -- Southwest
            newPos.x = newPos.x - 1
            newPos.y = newPos.y + 1
        elseif creatorDirection == 7 then -- Northwest
            newPos.x = newPos.x - 1
            newPos.y = newPos.y - 1
        end
    end
    -- If direction is nil (Center), use current position as-is
    
    -- Get current cavebot data
    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.waypoints then
        cavebotData.waypoints = {}
    end
    ensureSpecialAreasTable(cavebotData)

    if creatorWaypointType == 90 then
        for _, area in ipairs(cavebotData.specialAreas) do
            if area.position and isSamePosition(area.position, newPos) then
                modules.game_textmessage.displayFailureMessage("A special area already exists at this position")
                return
            end
        end

        local newAreaId = getNextSpecialAreaId(cavebotData.specialAreas)
        local newArea = {
            id = newAreaId,
            position = newPos,
            type = 90
        }
        table.insert(cavebotData.specialAreas, newArea)
        hunting_recorderModule.setCurrentCavebotData(cavebotData)
        if cavebotWalker and cavebotWalker.updateConfig then
            cavebotWalker.updateConfig({specialAreas = cavebotData.specialAreas})
        end
        hunting_recorderModule.reloadSpecialAreasList()
        hunting_recorderModule.updateDebugPos()
        
        -- Selecionar o special area recém-criado
        scheduleEvent(function()
            hunting_recorderModule.selectSpecialAreaById(newAreaId)
        end, 50)
        
        modules.game_textmessage.displayGameMessage("Special area created")
        focusGamePanel()
        return
    end
    
    -- Get selected waypoint index
    local selectedIndex = nil
    if huntingWaypointsWindow and huntingWaypointsWindow.settings then
        local waypointsList = huntingWaypointsWindow.settings.main.waypoints.list
        if waypointsList then
            for _, widget in ipairs(waypointsList:getChildren()) do
                if widget.selectedWaypoint and widget.waypointIndex then
                    selectedIndex = widget.waypointIndex
                    break
                end
            end
        end
    end
    
    -- Convert waypoints to sorted array
    local waypoints = {}
    for _, waypoint in pairs(cavebotData.waypoints) do
        table.insert(waypoints, waypoint)
    end
    table.sort(waypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)
    
    -- Manual add: zero logic - only position and type that user clicked
    local waypointType = creatorWaypointType
    local newWaypoint = {
        position = newPos,
        teleport = false,
        type = waypointType,
        index = nil -- Will be set based on mode
    }
    
    -- Apply mode
    if creatorMode == 'replace' then
        if selectedIndex then
            -- Replace selected waypoint
            for i, wp in ipairs(waypoints) do
                if wp.index == selectedIndex then
                    newWaypoint.index = selectedIndex
                    waypoints[i] = newWaypoint
                    break
                end
            end
        else
            modules.game_textmessage.displayFailureMessage("No waypoint selected for replace")
            return
        end
    elseif creatorMode == 'add' then
        if selectedIndex then
            -- Add after selected waypoint
            local insertPos = nil
            for i, wp in ipairs(waypoints) do
                if wp.index == selectedIndex then
                    insertPos = i + 1
                    break
                end
            end
            if insertPos then
                newWaypoint.index = selectedIndex + 1
                -- Reindex waypoints after selected
                for i = insertPos, #waypoints do
                    waypoints[i].index = waypoints[i].index + 1
                end
                table.insert(waypoints, insertPos, newWaypoint)
            else
                -- Selected not found, add at end
                newWaypoint.index = #waypoints + 1
                table.insert(waypoints, newWaypoint)
            end
        else
            -- Add at end
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    elseif creatorMode == 'insert' then
        if selectedIndex then
            -- Insert before selected waypoint
            local insertPos = nil
            for i, wp in ipairs(waypoints) do
                if wp.index == selectedIndex then
                    insertPos = i
                    break
                end
            end
            if insertPos then
                newWaypoint.index = selectedIndex
                -- Reindex waypoints from selected onwards
                for i = insertPos, #waypoints do
                    waypoints[i].index = waypoints[i].index + 1
                end
                table.insert(waypoints, insertPos, newWaypoint)
            else
                -- Selected not found, insert at beginning
                newWaypoint.index = 1
                for i, wp in ipairs(waypoints) do
                    wp.index = wp.index + 1
                end
                table.insert(waypoints, 1, newWaypoint)
            end
        else
            -- Insert at beginning
            newWaypoint.index = 1
            for i, wp in ipairs(waypoints) do
                wp.index = wp.index + 1
            end
            table.insert(waypoints, 1, newWaypoint)
        end
    end
    
    -- Reindex all waypoints to ensure sequential indices
    table.sort(waypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)
    for i, wp in ipairs(waypoints) do
        wp.index = i
    end
    
    -- Update cavebot data
    cavebotData.waypoints = {}
    for _, wp in ipairs(waypoints) do
        cavebotData.waypoints[wp.index] = wp
    end
    hunting_recorderModule.setCurrentCavebotData(cavebotData)
    
    -- Reload waypoints in UI (chunked) with callback to select new waypoint
    lastWaypointPosition = { x = newPos.x, y = newPos.y, z = newPos.z }
    hunting_recorderModule.reloadAllWaypointsUI(waypoints, function()
        hunting_recorderModule.selectWaypointByPosition(newPos, waypoints)
    end)

    -- Update debug display if enabled
    hunting_recorderModule.updateDebugPos()

    -- Reset direction to Center (C) after creating waypoint
    if creatorDirection ~= nil then
        hunting_recorderModule.setCreatorDirection(nil)
    end

    modules.game_textmessage.displayGameMessage("Waypoint created")
    focusGamePanel()
end

function hunting_recorderModule.createLabelWaypoint()
    local inputWindow = g_ui.displayUI('styles/label_name', modules.game_helper)
    if not inputWindow then return end

    local textEdit = inputWindow:getChildById('nameText')
    local okButton = inputWindow:getChildById('buttonOk')

    okButton.onClick = function()
        local labelName = textEdit:getText()
        if labelName and labelName ~= '' then
            inputWindow:destroy()
            hunting_recorderModule.createLabelWaypointWithName(labelName)
        else
            modules.game_textmessage.displayFailureMessage("Label name cannot be empty")
        end
    end

    inputWindow:show()
    inputWindow:raise()
    textEdit:focus()
end

function hunting_recorderModule.createLabelWaypointWithName(labelName)
    local player = g_game.getLocalPlayer()
    if not player then
        modules.game_textmessage.displayFailureMessage("Player not found")
        return
    end

    local currentPos = player:getPosition()
    if not currentPos then
        modules.game_textmessage.displayFailureMessage("Could not get player position")
        return
    end

    -- Get current cavebot data
    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.waypoints then
        cavebotData.waypoints = {}
    end

    -- Get selected waypoint index
    local selectedIndex = nil
    if huntingWaypointsWindow and huntingWaypointsWindow.settings then
        local waypointsList = huntingWaypointsWindow.settings.main.waypoints.list
        if waypointsList then
            for _, widget in ipairs(waypointsList:getChildren()) do
                if widget.selectedWaypoint and widget.waypointIndex then
                    selectedIndex = widget.waypointIndex
                    break
                end
            end
        end
    end

    -- Convert waypoints to sorted array
    local waypoints = {}
    for _, waypoint in pairs(cavebotData.waypoints) do
        table.insert(waypoints, waypoint)
    end
    table.sort(waypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)

    -- Create new label waypoint
    local newWaypoint = {
        position = currentPos,
        teleport = false,
        type = 99, -- Label type
        label = labelName,
        index = nil
    }

    -- Apply mode (using creatorMode)
    if creatorMode == 'replace' then
        if selectedIndex then
            newWaypoint.index = selectedIndex
            for i, wp in ipairs(waypoints) do
                if wp.index == selectedIndex then
                    waypoints[i] = newWaypoint
                    break
                end
            end
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    elseif creatorMode == 'add' then
        if selectedIndex then
            newWaypoint.index = selectedIndex + 1
            for i = #waypoints, selectedIndex + 1, -1 do
                waypoints[i].index = waypoints[i].index + 1
            end
            table.insert(waypoints, selectedIndex + 1, newWaypoint)
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    elseif creatorMode == 'insert' then
        if selectedIndex then
            newWaypoint.index = selectedIndex
            for i = #waypoints, selectedIndex, -1 do
                waypoints[i].index = waypoints[i].index + 1
            end
            table.insert(waypoints, selectedIndex, newWaypoint)
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    else
        newWaypoint.index = #waypoints + 1
        table.insert(waypoints, newWaypoint)
    end

    -- Save to cavebot data
    cavebotData.waypoints = {}
    for _, wp in ipairs(waypoints) do
        table.insert(cavebotData.waypoints, wp)
    end

    -- Save to session
    if hunting_recorderModule.selectedSessionUid then
        local cSession = hunting_recorderModule.getSessionSettings()
        cSession['waypoints'] = waypoints
        hunting_recorderModule.setSessionSettings(cSession)
        hunting_recorderModule.saveSessionToDisk(hunting_recorderModule.selectedSessionUid, cSession)
    end

    -- Reload UI (chunked)
    hunting_recorderModule.reloadAllWaypointsUI(waypoints, function()
        hunting_recorderModule.selectWaypointByPosition(currentPos, waypoints)
    end)

    modules.game_textmessage.displayGameMessage("Label waypoint created: " .. labelName)
    focusGamePanel()
end

-- Forward declaration: updateWaypointAndReload e uma `local function` definida
-- MAIS ABAIXO (~9831). Como editScriptWaypoint (logo abaixo) vem ANTES dessa
-- definicao, sem este forward-declare o nome resolveria para uma global nil e o
-- "Edit Script" falhava silenciosamente (attempt to call nil) -> a edicao nunca
-- salvava. A definicao abaixo vira `function ...` (sem `local`) p/ atribuir aqui.
local updateWaypointAndReload

-- ============================================================================
-- SCRIPT WAYPOINT — roda Lua no MESMO sandbox da aba Scripting
-- ============================================================================

-- Abre o editor de codigo (popup multiline). Reusado para CRIAR e EDITAR um
-- waypoint "script": initialCode preenche o editor e onConfirm(code) recebe o
-- texto ao clicar OK. Enter insere nova linha (NAO confirma); OK so pelo botao.
function hunting_recorderModule.openScriptEditor(title, initialCode, onConfirm)
    local inputWindow = g_ui.displayUI('styles/script_editor', modules.game_helper)
    if not inputWindow then
        modules.game_textmessage.displayFailureMessage("Failed to open script editor")
        return
    end

    inputWindow:setText(title or "Script Waypoint")

    local descLabel = inputWindow:getChildById('descLabel')
    if descLabel then
        descLabel:setText("Lua com a MESMA API da aba Scripting (Player, Map, Game, CaveBot, Creature, Enums, JSON...).\nRetorne true (avanca), false (falhou) ou 'retry' (repete). Sem return = avanca.")
    end

    -- recursiveGetChildById: buttonOk vive dentro de buttonsPanel (neto), entao
    -- getChildById (so filhos diretos) retornava nil e o OK nunca conectava.
    local codeEdit = inputWindow:recursiveGetChildById('codeEdit')
    local okButton = inputWindow:recursiveGetChildById('buttonOk')
    if codeEdit then codeEdit:setText(initialCode or "") end

    local function confirm()
        local code = codeEdit and codeEdit:getText() or ""
        if code:match("^%s*$") then
            modules.game_textmessage.displayFailureMessage("Script cannot be empty")
            return
        end
        inputWindow:destroy()
        if onConfirm then onConfirm(code) end
    end

    if okButton then okButton.onClick = confirm end
    inputWindow.onEscape = function() inputWindow:destroy() end
    inputWindow:show()
    inputWindow:raise()
    if codeEdit then codeEdit:focus() end
end

-- Botao "Script" do creator: abre o editor vazio e cria o waypoint no OK.
function hunting_recorderModule.createScriptWaypoint()
    hunting_recorderModule.openScriptEditor("New Script Waypoint", "", function(code)
        hunting_recorderModule.createScriptWaypointWithCode(code)
    end)
end

-- Cria um waypoint position-less do tipo "script" no tile atual do player. O
-- codigo Lua e guardado em wp.label (mesmo campo de texto livre do label/goto);
-- CaveBot.loadFromWaypoints converte type=="script" -> action "script",
-- value=wp.label. Espelha createLabelWaypointWithName (mode replace/add/insert).
function hunting_recorderModule.createScriptWaypointWithCode(code)
    local player = g_game.getLocalPlayer()
    if not player then
        modules.game_textmessage.displayFailureMessage("Player not found")
        return
    end

    local currentPos = player:getPosition()
    if not currentPos then
        modules.game_textmessage.displayFailureMessage("Could not get player position")
        return
    end

    -- Get current cavebot data
    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.waypoints then
        cavebotData.waypoints = {}
    end

    -- Get selected waypoint index
    local selectedIndex = nil
    if huntingWaypointsWindow and huntingWaypointsWindow.settings then
        local waypointsList = huntingWaypointsWindow.settings.main.waypoints.list
        if waypointsList then
            for _, widget in ipairs(waypointsList:getChildren()) do
                if widget.selectedWaypoint and widget.waypointIndex then
                    selectedIndex = widget.waypointIndex
                    break
                end
            end
        end
    end

    -- Convert waypoints to sorted array
    local waypoints = {}
    for _, waypoint in pairs(cavebotData.waypoints) do
        table.insert(waypoints, waypoint)
    end
    table.sort(waypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)

    -- Create new script waypoint (position-less; o codigo vive em .label)
    local newWaypoint = {
        position = {x = currentPos.x, y = currentPos.y, z = currentPos.z},
        teleport = false,
        type = "script",
        label = code,
        index = nil
    }

    -- Apply mode (using creatorMode) — identico ao label/lure
    if creatorMode == 'replace' then
        if selectedIndex then
            newWaypoint.index = selectedIndex
            for i, wp in ipairs(waypoints) do
                if wp.index == selectedIndex then
                    waypoints[i] = newWaypoint
                    break
                end
            end
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    elseif creatorMode == 'add' then
        if selectedIndex then
            newWaypoint.index = selectedIndex + 1
            for i = #waypoints, selectedIndex + 1, -1 do
                waypoints[i].index = waypoints[i].index + 1
            end
            table.insert(waypoints, selectedIndex + 1, newWaypoint)
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    elseif creatorMode == 'insert' then
        if selectedIndex then
            newWaypoint.index = selectedIndex
            for i = #waypoints, selectedIndex, -1 do
                waypoints[i].index = waypoints[i].index + 1
            end
            table.insert(waypoints, selectedIndex, newWaypoint)
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    else
        newWaypoint.index = #waypoints + 1
        table.insert(waypoints, newWaypoint)
    end

    -- Save to cavebot data
    cavebotData.waypoints = {}
    for _, wp in ipairs(waypoints) do
        table.insert(cavebotData.waypoints, wp)
    end

    -- Save to session
    if hunting_recorderModule.selectedSessionUid then
        local cSession = hunting_recorderModule.getSessionSettings()
        cSession['waypoints'] = waypoints
        hunting_recorderModule.setSessionSettings(cSession)
        hunting_recorderModule.saveSessionToDisk(hunting_recorderModule.selectedSessionUid, cSession)
    end

    -- Reload UI (chunked)
    hunting_recorderModule.reloadAllWaypointsUI(waypoints, function()
        hunting_recorderModule.selectWaypointByPosition(currentPos, waypoints)
    end)

    modules.game_textmessage.displayGameMessage("Script waypoint created")
    focusGamePanel()
end

-- Menu de contexto "Edit Script": reabre o editor com o codigo atual e salva.
function hunting_recorderModule.editScriptWaypoint(widget)
    hunting_recorderModule.openScriptEditor("Edit Script Waypoint", widget.waypointLabel or "", function(code)
        widget.waypointLabel = code
        updateWaypointAndReload(widget, function(wp)
            wp.label = code
        end)
        modules.game_textmessage.displayGameMessage("Script updated")
    end)
end

function hunting_recorderModule.createGotoWaypoint()
    local rootWidget = g_ui.getRootWidget()
    if not rootWidget then
        modules.game_textmessage.displayFailureMessage(htr("Failed to get root widget."))
        return
    end

    -- Create window from OTUI file
    local window = g_ui.loadUI('styles/goto_waypoint.otui', rootWidget)
    if not window then
        modules.game_textmessage.displayFailureMessage("Failed to load goto waypoint window.")
        return
    end

    -- Get widget references
    local labelEdit = window:recursiveGetChildById('labelEdit')
    local optionNone = window:recursiveGetChildById('optionNone')
    local optionLess = window:recursiveGetChildById('optionLess')
    local optionGreater = window:recursiveGetChildById('optionGreater')
    local staminaLess = window:recursiveGetChildById('staminaLess')
    local staminaGreater = window:recursiveGetChildById('staminaGreater')

    -- Initialize selected mode
    local selectedMode = 'none'

    -- Function to update mode selection
    local function setMode(mode)
        selectedMode = mode
        optionNone:setChecked(mode == 'none')
        optionLess:setChecked(mode == 'lt')
        optionGreater:setChecked(mode == 'gt')
        staminaLess:setEnabled(mode == 'lt')
        staminaGreater:setEnabled(mode == 'gt')
    end

    -- Connect checkbox events
    optionNone.onClick = function() setMode('none') end
    optionLess.onClick = function() setMode('lt') end
    optionGreater.onClick = function() setMode('gt') end

    -- Initialize
    setMode('none')

    -- Store window and mode for use in save function
    window.selectedMode = selectedMode
    window.getSelectedMode = function() return selectedMode end

    window:show()
    window:raise()
    labelEdit:focus()
end

function hunting_recorderModule.saveGotoWaypoint(window)
    if not window then
        modules.game_textmessage.displayFailureMessage("Window not found")
        return
    end

    -- Get widget references
    local labelEdit = window:recursiveGetChildById('labelEdit')
    local optionNone = window:recursiveGetChildById('optionNone')
    local optionLess = window:recursiveGetChildById('optionLess')
    local optionGreater = window:recursiveGetChildById('optionGreater')
    local staminaLess = window:recursiveGetChildById('staminaLess')
    local staminaGreater = window:recursiveGetChildById('staminaGreater')

    -- Validate label name
    local labelName = labelEdit:getText()
    if not labelName or labelName == '' then
        modules.game_textmessage.displayFailureMessage("Label name cannot be empty")
        return
    end

    -- Determine condition and stamina value based on selected option
    local condition = "none"
    local staminaValue = nil

    if optionLess:isChecked() then
        condition = "stamina_lt"
        staminaValue = tonumber(staminaLess:getText())
        if not staminaValue or staminaValue < 0 then
            modules.game_textmessage.displayFailureMessage("Stamina value must be a valid number")
            return
        end
    elseif optionGreater:isChecked() then
        condition = "stamina_gt"
        staminaValue = tonumber(staminaGreater:getText())
        if not staminaValue or staminaValue < 0 then
            modules.game_textmessage.displayFailureMessage("Stamina value must be a valid number")
            return
        end
    end

    -- Close window
    window:destroy()

    -- Create the waypoint with the collected data
    hunting_recorderModule.createGotoWaypointWithData(labelName, condition, staminaValue)
end

function hunting_recorderModule.createGotoWaypointWithData(labelName, condition, staminaValue)
    local player = g_game.getLocalPlayer()
    if not player then
        modules.game_textmessage.displayFailureMessage("Player not found")
        return
    end

    local currentPos = player:getPosition()
    if not currentPos then
        modules.game_textmessage.displayFailureMessage("Could not get player position")
        return
    end

    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.waypoints then
        cavebotData.waypoints = {}
    end

    local selectedIndex = nil
    if huntingWaypointsWindow and huntingWaypointsWindow.settings then
        local waypointsList = huntingWaypointsWindow.settings.main.waypoints.list
        if waypointsList then
            for _, widget in ipairs(waypointsList:getChildren()) do
                if widget.selectedWaypoint and widget.waypointIndex then
                    selectedIndex = widget.waypointIndex
                    break
                end
            end
        end
    end

    local waypoints = {}
    for _, waypoint in pairs(cavebotData.waypoints) do
        table.insert(waypoints, waypoint)
    end
    table.sort(waypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)

    local newWaypoint = {
        position = currentPos,
        teleport = false,
        type = 98, -- Goto type
        label = labelName,
        gotoCondition = condition or "none",
        gotoStamina = staminaValue,
        index = nil
    }

    if creatorMode == 'replace' then
        if selectedIndex then
            newWaypoint.index = selectedIndex
            for i, wp in ipairs(waypoints) do
                if wp.index == selectedIndex then
                    waypoints[i] = newWaypoint
                    break
                end
            end
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    elseif creatorMode == 'add' then
        if selectedIndex then
            newWaypoint.index = selectedIndex + 1
            for i = #waypoints, selectedIndex + 1, -1 do
                waypoints[i].index = waypoints[i].index + 1
            end
            table.insert(waypoints, selectedIndex + 1, newWaypoint)
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    elseif creatorMode == 'insert' then
        if selectedIndex then
            newWaypoint.index = selectedIndex
            for i = #waypoints, selectedIndex, -1 do
                waypoints[i].index = waypoints[i].index + 1
            end
            table.insert(waypoints, selectedIndex, newWaypoint)
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    else
        newWaypoint.index = #waypoints + 1
        table.insert(waypoints, newWaypoint)
    end

    cavebotData.waypoints = {}
    for _, wp in ipairs(waypoints) do
        table.insert(cavebotData.waypoints, wp)
    end

    if hunting_recorderModule.selectedSessionUid then
        local cSession = hunting_recorderModule.getSessionSettings()
        cSession['waypoints'] = waypoints
        hunting_recorderModule.setSessionSettings(cSession)
        hunting_recorderModule.saveSessionToDisk(hunting_recorderModule.selectedSessionUid, cSession)
    end

    -- Reload UI (chunked)
    hunting_recorderModule.reloadAllWaypointsUI(waypoints, function()
        hunting_recorderModule.selectWaypointByPosition(currentPos, waypoints)
    end)

    hunting_recorderModule.updateDebugPos()
    modules.game_textmessage.displayGameMessage("Goto waypoint created: " .. labelName)
    focusGamePanel()
end

function hunting_recorderModule.createUseWaypoint()
    -- Use waypoint is type 2 (only Use, no Stand)
    creatorWaypointType = 2
    hunting_recorderModule.createWaypointFromCreator()
end

function hunting_recorderModule.createSpecialAreaWaypoint()
    creatorWaypointType = 90
    hunting_recorderModule.createWaypointFromCreator()
end

function hunting_recorderModule.createDepositWaypoint()
    creatorWaypointType = "deposit"
    hunting_recorderModule.createWaypointFromCreator()
end

function hunting_recorderModule.createBankWaypoint()
    creatorWaypointType = "bank"
    hunting_recorderModule.createWaypointFromCreator()
end

function hunting_recorderModule.createTravelWaypoint()
    creatorWaypointType = "travel"
    hunting_recorderModule.createWaypointFromCreator()
end

function hunting_recorderModule.createDoorWaypoint()
    creatorWaypointType = "door"
    hunting_recorderModule.createWaypointFromCreator()
end

function hunting_recorderModule.createStopToKill()
    local player = g_game.getLocalPlayer()
    if not player then
        modules.game_textmessage.displayFailureMessage("Player not found")
        return
    end

    local currentPos = player:getPosition()
    if not currentPos then
        modules.game_textmessage.displayFailureMessage("Could not get player position")
        return
    end

    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.waypoints then
        cavebotData.waypoints = {}
    end

    local selectedIndex = nil
    if huntingWaypointsWindow and huntingWaypointsWindow.settings then
        local waypointsList = huntingWaypointsWindow.settings.main.waypoints.list
        if waypointsList then
            for _, widget in ipairs(waypointsList:getChildren()) do
                if widget.selectedWaypoint and widget.waypointIndex then
                    selectedIndex = widget.waypointIndex
                    break
                end
            end
        end
    end

    -- Calculate new position based on direction
    local newPos = {x = currentPos.x, y = currentPos.y, z = currentPos.z}

    if creatorDirection ~= nil then
        -- Direction mapping: 0=N, 1=E, 2=S, 3=W, 4=NE, 5=SE, 6=SW, 7=NW
        if creatorDirection == 0 then -- North
            newPos.y = newPos.y - 1
        elseif creatorDirection == 1 then -- East
            newPos.x = newPos.x + 1
        elseif creatorDirection == 2 then -- South
            newPos.y = newPos.y + 1
        elseif creatorDirection == 3 then -- West
            newPos.x = newPos.x - 1
        elseif creatorDirection == 4 then -- Northeast
            newPos.x = newPos.x + 1
            newPos.y = newPos.y - 1
        elseif creatorDirection == 5 then -- Southeast
            newPos.x = newPos.x + 1
            newPos.y = newPos.y + 1
        elseif creatorDirection == 6 then -- Southwest
            newPos.x = newPos.x - 1
            newPos.y = newPos.y + 1
        elseif creatorDirection == 7 then -- Northwest
            newPos.x = newPos.x - 1
            newPos.y = newPos.y - 1
        end
    end

    -- Convert waypoints to sorted array
    local waypoints = {}
    for _, waypoint in pairs(cavebotData.waypoints) do
        table.insert(waypoints, waypoint)
    end
    table.sort(waypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)

    -- Create new waypoint
    local newWaypoint = {
        position = newPos,
        teleport = false,
        type = "stop_to_kill",
        index = nil
    }

    if creatorMode == 'replace' then
        if selectedIndex then
            newWaypoint.index = selectedIndex
            for i, wp in ipairs(waypoints) do
                if wp.index == selectedIndex then
                    waypoints[i] = newWaypoint
                    break
                end
            end
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    elseif creatorMode == 'add' then
        if selectedIndex then
            newWaypoint.index = selectedIndex + 1
            for i = #waypoints, selectedIndex + 1, -1 do
                waypoints[i].index = waypoints[i].index + 1
            end
            table.insert(waypoints, selectedIndex + 1, newWaypoint)
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    elseif creatorMode == 'insert' then
        if selectedIndex then
            newWaypoint.index = selectedIndex
            for i = #waypoints, selectedIndex, -1 do
                waypoints[i].index = waypoints[i].index + 1
            end
            table.insert(waypoints, selectedIndex, newWaypoint)
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    else
        newWaypoint.index = #waypoints + 1
        table.insert(waypoints, newWaypoint)
    end

    cavebotData.waypoints = {}
    for _, wp in ipairs(waypoints) do
        table.insert(cavebotData.waypoints, wp)
    end

    if hunting_recorderModule.selectedSessionUid then
        local cSession = hunting_recorderModule.getSessionSettings()
        cSession['waypoints'] = waypoints
        hunting_recorderModule.setSessionSettings(cSession)
        hunting_recorderModule.saveSessionToDisk(hunting_recorderModule.selectedSessionUid, cSession)
    end

    -- Reload UI (chunked) with callback to select new waypoint
    hunting_recorderModule.reloadAllWaypointsUI(waypoints, function()
        hunting_recorderModule.selectWaypointByPosition(newPos, waypoints)
    end)

    -- Reset direction to Center (C) after creating waypoint
    if creatorDirection ~= nil then
        creatorDirection = nil
        local window = huntingWaypointsWindow
        if window then
            local creatorWindow = window:recursiveGetChildById('waypointCreatorWindow')
            if creatorWindow then
                local directionPanel = creatorWindow:recursiveGetChildById('directionPanel')
                if directionPanel then
                    for _, child in ipairs(directionPanel:getChildren()) do
                        if child:getStyleName() == 'DirectionButton' then
                            if child:getId() == 'dirCenter' then
                                child:setChecked(true)
                            else
                                child:setChecked(false)
                            end
                        end
                    end
                end
            end
        end
    end

    hunting_recorderModule.updateDebugPos()
    modules.game_textmessage.displayGameMessage("Stop to Kill waypoint created")
    focusGamePanel()
end

function hunting_recorderModule.createWaitDelayWaypoint()
    local player = g_game.getLocalPlayer()
    if not player then
        modules.game_textmessage.displayFailureMessage("Player not found")
        return
    end

    local currentPos = player:getPosition()
    if not currentPos then
        modules.game_textmessage.displayFailureMessage("Could not get player position")
        return
    end

    -- Capture state now (before async popup)
    local capturedDirection = creatorDirection
    local capturedMode = creatorMode

    local selectedIndex = nil
    if huntingWaypointsWindow and huntingWaypointsWindow.settings then
        local waypointsList = huntingWaypointsWindow.settings.main.waypoints.list
        if waypointsList then
            for _, widget in ipairs(waypointsList:getChildren()) do
                if widget.selectedWaypoint and widget.waypointIndex then
                    selectedIndex = widget.waypointIndex
                    break
                end
            end
        end
    end

    -- Calculate position based on direction
    local newPos = {x = currentPos.x, y = currentPos.y, z = currentPos.z}
    if capturedDirection ~= nil then
        if capturedDirection == 0 then newPos.y = newPos.y - 1
        elseif capturedDirection == 1 then newPos.x = newPos.x + 1
        elseif capturedDirection == 2 then newPos.y = newPos.y + 1
        elseif capturedDirection == 3 then newPos.x = newPos.x - 1
        elseif capturedDirection == 4 then newPos.x = newPos.x + 1; newPos.y = newPos.y - 1
        elseif capturedDirection == 5 then newPos.x = newPos.x + 1; newPos.y = newPos.y + 1
        elseif capturedDirection == 6 then newPos.x = newPos.x - 1; newPos.y = newPos.y + 1
        elseif capturedDirection == 7 then newPos.x = newPos.x - 1; newPos.y = newPos.y - 1
        end
    end

    -- Show input popup for delay value
    local inputWindow = g_ui.displayUI('styles/wait_delay', modules.game_helper)
    if not inputWindow then return end

    local delayInput = inputWindow:getChildById('delayInput')
    local okButton = inputWindow:getChildById('buttonOk')

    -- Numeric-only validation (same pattern as healing percent inputs)
    delayInput.onTextChange = function(self, text)
        local sanitized = text:gsub("[^0-9]", "")
        if sanitized ~= text then
            self:setText(sanitized)
            if self.setCursorPos then self:setCursorPos(-1) end
        end
        scheduleNumericInputClamp(self, 0, 60000, nil, nil)
    end

    local function confirmWaitDelay()
        local text = delayInput:getText() or ""
        local delayMs = tonumber(text)
        if not delayMs or delayMs < 0 then delayMs = 1000 end
        if delayMs > 60000 then delayMs = 60000 end
        delayMs = math.floor(delayMs)

        inputWindow:destroy()

        -- Now create the waypoint with the chosen delay
        local cavebotData = hunting_recorderModule.getCurrentCavebotData()
        if not cavebotData.waypoints then
            cavebotData.waypoints = {}
        end

        local waypoints = {}
        for _, waypoint in pairs(cavebotData.waypoints) do
            table.insert(waypoints, waypoint)
        end
        table.sort(waypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)

        local newWaypoint = {
            position = newPos,
            teleport = false,
            type = "wait_delay",
            waitDelayMs = delayMs,
            index = nil
        }

        if capturedMode == 'replace' then
            if selectedIndex then
                newWaypoint.index = selectedIndex
                for i, wp in ipairs(waypoints) do
                    if wp.index == selectedIndex then
                        waypoints[i] = newWaypoint
                        break
                    end
                end
            else
                newWaypoint.index = #waypoints + 1
                table.insert(waypoints, newWaypoint)
            end
        elseif capturedMode == 'add' then
            if selectedIndex then
                newWaypoint.index = selectedIndex + 1
                for i = #waypoints, selectedIndex + 1, -1 do
                    waypoints[i].index = waypoints[i].index + 1
                end
                table.insert(waypoints, selectedIndex + 1, newWaypoint)
            else
                newWaypoint.index = #waypoints + 1
                table.insert(waypoints, newWaypoint)
            end
        elseif capturedMode == 'insert' then
            if selectedIndex then
                newWaypoint.index = selectedIndex
                for i = #waypoints, selectedIndex, -1 do
                    waypoints[i].index = waypoints[i].index + 1
                end
                table.insert(waypoints, selectedIndex, newWaypoint)
            else
                newWaypoint.index = #waypoints + 1
                table.insert(waypoints, newWaypoint)
            end
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end

        cavebotData.waypoints = {}
        for _, wp in ipairs(waypoints) do
            table.insert(cavebotData.waypoints, wp)
        end

        if hunting_recorderModule.selectedSessionUid then
            local cSession = hunting_recorderModule.getSessionSettings()
            cSession['waypoints'] = waypoints
            hunting_recorderModule.setSessionSettings(cSession)
            hunting_recorderModule.saveSessionToDisk(hunting_recorderModule.selectedSessionUid, cSession)
        end

        -- Reload UI (chunked) with callback to select new waypoint
        hunting_recorderModule.reloadAllWaypointsUI(waypoints, function()
            hunting_recorderModule.selectWaypointByPosition(newPos, waypoints)
        end)

        -- Reset direction to Center (C)
        if capturedDirection ~= nil then
            creatorDirection = nil
            local window = huntingWaypointsWindow
            if window then
                local creatorWindow = window:recursiveGetChildById('waypointCreatorWindow')
                if creatorWindow then
                    local directionPanel = creatorWindow:recursiveGetChildById('directionPanel')
                    if directionPanel then
                        for _, child in ipairs(directionPanel:getChildren()) do
                            if child:getStyleName() == 'DirectionButton' then
                                if child:getId() == 'dirCenter' then
                                    child:setChecked(true)
                                else
                                    child:setChecked(false)
                                end
                            end
                        end
                    end
                end
            end
        end

        hunting_recorderModule.updateDebugPos()
        modules.game_textmessage.displayGameMessage("Wait Delay waypoint created (" .. delayMs .. "ms)")
        focusGamePanel()
    end

    okButton.onClick = confirmWaitDelay

    -- Enter key confirms
    inputWindow.onEnter = confirmWaitDelay

    -- Escape key cancels
    inputWindow.onEscape = function()
        inputWindow:destroy()
    end

    delayInput:focus()
end

-- Create Stop Cavebot waypoint. When the cavebot reaches it, the bot stops itself.
function hunting_recorderModule.createStopCavebotWaypoint()
    local player = g_game.getLocalPlayer()
    if not player then
        modules.game_textmessage.displayFailureMessage("Player not found")
        return
    end

    local currentPos = player:getPosition()
    if not currentPos then
        modules.game_textmessage.displayFailureMessage("Could not get player position")
        return
    end

    local capturedDirection = creatorDirection
    local capturedMode = creatorMode

    local selectedIndex = nil
    if huntingWaypointsWindow and huntingWaypointsWindow.settings then
        local waypointsList = huntingWaypointsWindow.settings.main.waypoints.list
        if waypointsList then
            for _, widget in ipairs(waypointsList:getChildren()) do
                if widget.selectedWaypoint and widget.waypointIndex then
                    selectedIndex = widget.waypointIndex
                    break
                end
            end
        end
    end

    local newPos = {x = currentPos.x, y = currentPos.y, z = currentPos.z}
    if capturedDirection ~= nil then
        if capturedDirection == 0 then newPos.y = newPos.y - 1
        elseif capturedDirection == 1 then newPos.x = newPos.x + 1
        elseif capturedDirection == 2 then newPos.y = newPos.y + 1
        elseif capturedDirection == 3 then newPos.x = newPos.x - 1
        elseif capturedDirection == 4 then newPos.x = newPos.x + 1; newPos.y = newPos.y - 1
        elseif capturedDirection == 5 then newPos.x = newPos.x + 1; newPos.y = newPos.y + 1
        elseif capturedDirection == 6 then newPos.x = newPos.x - 1; newPos.y = newPos.y + 1
        elseif capturedDirection == 7 then newPos.x = newPos.x - 1; newPos.y = newPos.y - 1
        end
    end

    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.waypoints then
        cavebotData.waypoints = {}
    end

    local waypoints = {}
    for _, waypoint in pairs(cavebotData.waypoints) do
        table.insert(waypoints, waypoint)
    end
    table.sort(waypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)

    local newWaypoint = {
        position = newPos,
        teleport = false,
        type = "stop_cavebot",
        index = nil
    }

    if capturedMode == 'replace' then
        if selectedIndex then
            newWaypoint.index = selectedIndex
            for i, wp in ipairs(waypoints) do
                if wp.index == selectedIndex then
                    waypoints[i] = newWaypoint
                    break
                end
            end
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    elseif capturedMode == 'add' then
        if selectedIndex then
            newWaypoint.index = selectedIndex + 1
            for i = #waypoints, selectedIndex + 1, -1 do
                waypoints[i].index = waypoints[i].index + 1
            end
            table.insert(waypoints, selectedIndex + 1, newWaypoint)
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    elseif capturedMode == 'insert' then
        if selectedIndex then
            newWaypoint.index = selectedIndex
            for i = #waypoints, selectedIndex, -1 do
                waypoints[i].index = waypoints[i].index + 1
            end
            table.insert(waypoints, selectedIndex, newWaypoint)
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    else
        newWaypoint.index = #waypoints + 1
        table.insert(waypoints, newWaypoint)
    end

    cavebotData.waypoints = {}
    for _, wp in ipairs(waypoints) do
        table.insert(cavebotData.waypoints, wp)
    end

    if hunting_recorderModule.selectedSessionUid then
        local cSession = hunting_recorderModule.getSessionSettings()
        cSession['waypoints'] = waypoints
        hunting_recorderModule.setSessionSettings(cSession)
        hunting_recorderModule.saveSessionToDisk(hunting_recorderModule.selectedSessionUid, cSession)
    end

    hunting_recorderModule.reloadAllWaypointsUI(waypoints, function()
        hunting_recorderModule.selectWaypointByPosition(newPos, waypoints)
    end)

    if capturedDirection ~= nil then
        creatorDirection = nil
        local window = huntingWaypointsWindow
        if window then
            local creatorWindow = window:recursiveGetChildById('waypointCreatorWindow')
            if creatorWindow then
                local directionPanel = creatorWindow:recursiveGetChildById('directionPanel')
                if directionPanel then
                    for _, child in ipairs(directionPanel:getChildren()) do
                        if child:getStyleName() == 'DirectionButton' then
                            if child:getId() == 'dirCenter' then
                                child:setChecked(true)
                            else
                                child:setChecked(false)
                            end
                        end
                    end
                end
            end
        end
    end

    hunting_recorderModule.updateDebugPos()
    modules.game_textmessage.displayGameMessage("Stop Cavebot waypoint created")
    focusGamePanel()
end

-- Create Start/Stop Lure waypoint. Toggles cavebot lureMode on arrival.
-- For these waypoints to take effect, the user must turn OFF the manual
-- lure mode toggle so the waypoints can drive it dynamically.
local function createLureMarkerWaypoint(wpType, displayName)
    local player = g_game.getLocalPlayer()
    if not player then
        modules.game_textmessage.displayFailureMessage("Player not found")
        return
    end

    local currentPos = player:getPosition()
    if not currentPos then
        modules.game_textmessage.displayFailureMessage("Could not get player position")
        return
    end

    local capturedDirection = creatorDirection
    local capturedMode = creatorMode

    local selectedIndex = nil
    if huntingWaypointsWindow and huntingWaypointsWindow.settings then
        local waypointsList = huntingWaypointsWindow.settings.main.waypoints.list
        if waypointsList then
            for _, widget in ipairs(waypointsList:getChildren()) do
                if widget.selectedWaypoint and widget.waypointIndex then
                    selectedIndex = widget.waypointIndex
                    break
                end
            end
        end
    end

    local newPos = {x = currentPos.x, y = currentPos.y, z = currentPos.z}
    if capturedDirection ~= nil then
        if capturedDirection == 0 then newPos.y = newPos.y - 1
        elseif capturedDirection == 1 then newPos.x = newPos.x + 1
        elseif capturedDirection == 2 then newPos.y = newPos.y + 1
        elseif capturedDirection == 3 then newPos.x = newPos.x - 1
        elseif capturedDirection == 4 then newPos.x = newPos.x + 1; newPos.y = newPos.y - 1
        elseif capturedDirection == 5 then newPos.x = newPos.x + 1; newPos.y = newPos.y + 1
        elseif capturedDirection == 6 then newPos.x = newPos.x - 1; newPos.y = newPos.y + 1
        elseif capturedDirection == 7 then newPos.x = newPos.x - 1; newPos.y = newPos.y - 1
        end
    end

    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.waypoints then
        cavebotData.waypoints = {}
    end

    local waypoints = {}
    for _, waypoint in pairs(cavebotData.waypoints) do
        table.insert(waypoints, waypoint)
    end
    table.sort(waypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)

    local newWaypoint = {
        position = newPos,
        teleport = false,
        type = wpType,
        index = nil
    }

    if capturedMode == 'replace' then
        if selectedIndex then
            newWaypoint.index = selectedIndex
            for i, wp in ipairs(waypoints) do
                if wp.index == selectedIndex then
                    waypoints[i] = newWaypoint
                    break
                end
            end
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    elseif capturedMode == 'add' then
        if selectedIndex then
            newWaypoint.index = selectedIndex + 1
            for i = #waypoints, selectedIndex + 1, -1 do
                waypoints[i].index = waypoints[i].index + 1
            end
            table.insert(waypoints, selectedIndex + 1, newWaypoint)
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    elseif capturedMode == 'insert' then
        if selectedIndex then
            newWaypoint.index = selectedIndex
            for i = #waypoints, selectedIndex, -1 do
                waypoints[i].index = waypoints[i].index + 1
            end
            table.insert(waypoints, selectedIndex, newWaypoint)
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    else
        newWaypoint.index = #waypoints + 1
        table.insert(waypoints, newWaypoint)
    end

    cavebotData.waypoints = {}
    for _, wp in ipairs(waypoints) do
        table.insert(cavebotData.waypoints, wp)
    end

    if hunting_recorderModule.selectedSessionUid then
        local cSession = hunting_recorderModule.getSessionSettings()
        cSession['waypoints'] = waypoints
        hunting_recorderModule.setSessionSettings(cSession)
        hunting_recorderModule.saveSessionToDisk(hunting_recorderModule.selectedSessionUid, cSession)
    end

    hunting_recorderModule.reloadAllWaypointsUI(waypoints, function()
        hunting_recorderModule.selectWaypointByPosition(newPos, waypoints)
    end)

    if capturedDirection ~= nil then
        creatorDirection = nil
        local window = huntingWaypointsWindow
        if window then
            local creatorWindow = window:recursiveGetChildById('waypointCreatorWindow')
            if creatorWindow then
                local directionPanel = creatorWindow:recursiveGetChildById('directionPanel')
                if directionPanel then
                    for _, child in ipairs(directionPanel:getChildren()) do
                        if child:getStyleName() == 'DirectionButton' then
                            if child:getId() == 'dirCenter' then
                                child:setChecked(true)
                            else
                                child:setChecked(false)
                            end
                        end
                    end
                end
            end
        end
    end

    hunting_recorderModule.updateDebugPos()
    modules.game_textmessage.displayGameMessage(displayName .. " waypoint created")
    focusGamePanel()
end

function hunting_recorderModule.createStartLureWaypoint()
    createLureMarkerWaypoint("start_lure", "Start Lure")
end

function hunting_recorderModule.createStopLureWaypoint()
    createLureMarkerWaypoint("stop_lure", "Stop Lure")
end

-- Create Levitate waypoint (exani hur up/down).
-- Posição = tile atual do player. Direção = N/E/S/W escolhida no creator (Center não é permitido).
function hunting_recorderModule.createLevitateWaypoint(mode)
    local player = g_game.getLocalPlayer()
    if not player then
        modules.game_textmessage.displayFailureMessage("Player not found")
        return
    end

    local currentPos = player:getPosition()
    if not currentPos then
        modules.game_textmessage.displayFailureMessage("Could not get player position")
        return
    end

    mode = (mode == "down") and "down" or "up"

    local capturedDirection = creatorDirection
    if capturedDirection == nil or capturedDirection < 0 or capturedDirection > 3 then
        modules.game_textmessage.displayFailureMessage("Select a direction (N/E/S/W) before creating a Levitate waypoint")
        return
    end

    local capturedMode = creatorMode
    local newPos = {x = currentPos.x, y = currentPos.y, z = currentPos.z}

    local selectedIndex = nil
    if huntingWaypointsWindow and huntingWaypointsWindow.settings then
        local waypointsList = huntingWaypointsWindow.settings.main.waypoints.list
        if waypointsList then
            for _, widget in ipairs(waypointsList:getChildren()) do
                if widget.selectedWaypoint and widget.waypointIndex then
                    selectedIndex = widget.waypointIndex
                    break
                end
            end
        end
    end

    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.waypoints then
        cavebotData.waypoints = {}
    end

    local waypoints = {}
    for _, waypoint in pairs(cavebotData.waypoints) do
        table.insert(waypoints, waypoint)
    end
    table.sort(waypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)

    local newWaypoint = {
        position = newPos,
        teleport = false,
        type = "levitate",
        levitateMode = mode,
        levitateDir = capturedDirection,
        index = nil
    }

    if capturedMode == 'replace' and selectedIndex then
        newWaypoint.index = selectedIndex
        for i, wp in ipairs(waypoints) do
            if wp.index == selectedIndex then
                waypoints[i] = newWaypoint
                break
            end
        end
    elseif capturedMode == 'add' and selectedIndex then
        newWaypoint.index = selectedIndex + 1
        for i = #waypoints, selectedIndex + 1, -1 do
            waypoints[i].index = waypoints[i].index + 1
        end
        table.insert(waypoints, selectedIndex + 1, newWaypoint)
    elseif capturedMode == 'insert' and selectedIndex then
        newWaypoint.index = selectedIndex
        for i = #waypoints, selectedIndex, -1 do
            waypoints[i].index = waypoints[i].index + 1
        end
        table.insert(waypoints, selectedIndex, newWaypoint)
    else
        newWaypoint.index = #waypoints + 1
        table.insert(waypoints, newWaypoint)
    end

    cavebotData.waypoints = {}
    for _, wp in ipairs(waypoints) do
        table.insert(cavebotData.waypoints, wp)
    end

    if hunting_recorderModule.selectedSessionUid then
        local cSession = hunting_recorderModule.getSessionSettings()
        cSession['waypoints'] = waypoints
        hunting_recorderModule.setSessionSettings(cSession)
        hunting_recorderModule.saveSessionToDisk(hunting_recorderModule.selectedSessionUid, cSession)
    end

    hunting_recorderModule.reloadAllWaypointsUI(waypoints, function()
        hunting_recorderModule.selectWaypointByPosition(newPos, waypoints)
    end)

    if capturedDirection ~= nil then
        hunting_recorderModule.setCreatorDirection(nil)
    end

    hunting_recorderModule.updateDebugPos()
    local dirNames = { [0] = "N", [1] = "E", [2] = "S", [3] = "W" }
    modules.game_textmessage.displayGameMessage(
        string.format("Levitate %s waypoint created (facing %s)", mode:upper(), dirNames[capturedDirection] or "?")
    )
    focusGamePanel()
end

-- ============================================================================
-- EDIT WAYPOINT FUNCTIONS (right-click menu)
-- ============================================================================

-- Helper: update a waypoint field in session data and reload UI
-- NB: `function` (nao `local function`) — atribui ao local forward-declared la
-- em cima (secao SCRIPT WAYPOINT) p/ que editScriptWaypoint, definido ANTES daqui,
-- enxergue esta funcao. Continua sendo o mesmo upvalue local do chunk (nao global).
function updateWaypointAndReload(widgetToEdit, updateFn)
    local cSession = hunting_recorderModule.getSessionSettings()
    if not cSession or not cSession['waypoints'] then return end

    local wpIndex = widgetToEdit.waypointIndex
    if not wpIndex then return end

    -- Find and update the waypoint
    for _, waypoint in ipairs(cSession['waypoints']) do
        if waypoint.index == wpIndex then
            updateFn(waypoint)
            break
        end
    end

    hunting_recorderModule.setSessionSettings(cSession)
    hunting_recorderModule.saveSessionToDisk(hunting_recorderModule.selectedSessionUid, cSession)

    -- Espelha a edicao no MOTOR do cavebot em execucao. O actionList copia o
    -- value do waypoint (wp.label/etc) apenas no start, entao sem re-sincronizar
    -- o executor continua lendo o value ANTIGO -- a edicao de um "script" (ou
    -- label/levitate/wait_delay) so valia apos parar/reiniciar. No-op se o motor
    -- ainda nao tem acoes carregadas.
    if cavebotWalker and cavebotWalker.reloadWaypoints then
        cavebotWalker.reloadWaypoints(cSession['waypoints'])
    end

    -- Reload waypoints in UI (chunked)
    hunting_recorderModule.reloadAllWaypointsUI(cSession['waypoints'])
end

-- Edit Levitate: popup menu to change mode (up/down) and direction (N/E/S/W)
function hunting_recorderModule.editLevitateWaypoint(widget)
    local currentMode = widget.levitateMode == "down" and "down" or "up"
    local currentDir = tonumber(widget.levitateDir) or 0
    local dirNames = { [0] = "N", [1] = "E", [2] = "S", [3] = "W" }

    local menu = g_ui.createWidget('HelperPopupMenu')
    menu:setGameMenu(true)

    local function apply(newMode, newDir)
        widget.levitateMode = newMode
        widget.levitateDir = newDir
        updateWaypointAndReload(widget, function(wp)
            wp.levitateMode = newMode
            wp.levitateDir = newDir
        end)
        modules.game_textmessage.displayGameMessage(
            string.format("Levitate updated: %s %s", newMode:upper(), dirNames[newDir] or "?")
        )
    end

    for _, m in ipairs({ "up", "down" }) do
        for d = 0, 3 do
            local marker = (m == currentMode and d == currentDir) and " (current)" or ""
            local label = string.format("Hur %s - %s%s", m:upper(), dirNames[d], marker)
            menu:addOption(label, function() apply(m, d) end)
        end
        if m == "up" then menu:addSeparator() end
    end

    local mousePos = g_window.getMousePosition()
    menu:display(mousePos)
end

-- Edit Wait Delay: popup to change delay ms
function hunting_recorderModule.editWaitDelayWaypoint(widget)
    local currentDelay = widget.waitDelayMs or 1000

    local inputWindow = g_ui.displayUI('styles/wait_delay', modules.game_helper)
    if not inputWindow then return end

    inputWindow:setText('Edit Wait Delay (ms)')
    local delayInput = inputWindow:getChildById('delayInput')
    local okButton = inputWindow:getChildById('buttonOk')

    delayInput:setText(tostring(currentDelay))

    delayInput.onTextChange = function(self, text)
        local sanitized = text:gsub("[^0-9]", "")
        if sanitized ~= text then
            self:setText(sanitized)
            if self.setCursorPos then self:setCursorPos(-1) end
        end
        scheduleNumericInputClamp(self, 0, 60000, nil, nil)
    end

    local function confirm()
        local text = delayInput:getText() or ""
        local delayMs = tonumber(text)
        if not delayMs or delayMs < 0 then delayMs = 1000 end
        if delayMs > 60000 then delayMs = 60000 end
        delayMs = math.floor(delayMs)

        inputWindow:destroy()

        widget.waitDelayMs = delayMs
        updateWaypointAndReload(widget, function(wp)
            wp.waitDelayMs = delayMs
        end)
        modules.game_textmessage.displayGameMessage("Wait Delay updated to " .. delayMs .. "ms")
    end

    okButton.onClick = confirm
    inputWindow.onEnter = confirm
    inputWindow.onEscape = function() inputWindow:destroy() end
    delayInput:focus()
end

-- Edit Label: popup to change label name
function hunting_recorderModule.editLabelWaypoint(widget)
    local currentLabel = widget.waypointLabel or ""

    local inputWindow = g_ui.createWidget('MainWindow', rootWidget)
    inputWindow:setText('Edit Label')
    inputWindow:setSize({width = 300, height = 120})
    inputWindow:centerIn('parent')

    local contentPanel = g_ui.createWidget('Panel', inputWindow)
    contentPanel:setId('contentPanel')
    contentPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
    contentPanel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    contentPanel:addAnchor(AnchorRight, 'parent', AnchorRight)
    contentPanel:setHeight(35)
    contentPanel:setMarginTop(5)

    local descLabel = g_ui.createWidget('Label', contentPanel)
    descLabel:setId('descLabel')
    descLabel:setText('Label name:')
    descLabel:addAnchor(AnchorTop, 'parent', AnchorTop)
    descLabel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    descLabel:setMarginLeft(5)
    descLabel:setMarginTop(5)
    descLabel:setWidth(80)

    local labelInput = g_ui.createWidget('TextEdit', contentPanel)
    labelInput:setId('labelInput')
    labelInput:setText(currentLabel)
    labelInput:addAnchor(AnchorTop, 'parent', AnchorTop)
    labelInput:addAnchor(AnchorLeft, 'descLabel', AnchorRight)
    labelInput:addAnchor(AnchorRight, 'parent', AnchorRight)
    labelInput:setMarginLeft(5)
    labelInput:setMarginTop(3)
    labelInput:setMarginRight(5)
    labelInput:setHeight(22)
    labelInput:setPaddingTop(3)

    local buttonPanel = g_ui.createWidget('Panel', inputWindow)
    buttonPanel:setId('buttonPanel')
    buttonPanel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    buttonPanel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    buttonPanel:addAnchor(AnchorRight, 'parent', AnchorRight)
    buttonPanel:setHeight(30)
    buttonPanel:setMarginBottom(5)

    local okButton = g_ui.createWidget('Button', buttonPanel)
    okButton:setId('okButton')
    okButton:setText('OK')
    okButton:setSize({width = 60, height = 25})
    okButton:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    okButton:addAnchor(AnchorRight, 'parent', AnchorHorizontalCenter)
    okButton:setMarginRight(5)

    local cancelButton = g_ui.createWidget('Button', buttonPanel)
    cancelButton:setId('cancelButton')
    cancelButton:setText('Cancel')
    cancelButton:setSize({width = 60, height = 25})
    cancelButton:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    cancelButton:addAnchor(AnchorLeft, 'parent', AnchorHorizontalCenter)
    cancelButton:setMarginLeft(5)

    cancelButton.onClick = function()
        inputWindow:destroy()
    end

    local function confirm()
        local labelName = labelInput:getText() or ""
        if labelName == "" then
            modules.game_textmessage.displayFailureMessage("Label name cannot be empty")
            return
        end

        inputWindow:destroy()

        widget.waypointLabel = labelName
        updateWaypointAndReload(widget, function(wp)
            wp.label = labelName
        end)
        modules.game_textmessage.displayGameMessage("Label updated to '" .. labelName .. "'")
    end

    okButton.onClick = confirm
    inputWindow.onEnter = confirm
    inputWindow.onEscape = function() inputWindow:destroy() end
    labelInput:focus()
end

function hunting_recorderModule.createRopeWaypoint()
    local player = g_game.getLocalPlayer()
    if not player then
        modules.game_textmessage.displayFailureMessage("Player not found")
        return
    end

    local currentPos = player:getPosition()
    if not currentPos then
        modules.game_textmessage.displayFailureMessage("Could not get player position")
        return
    end

    -- Calculate new position based on direction
    local newPos = {x = currentPos.x, y = currentPos.y, z = currentPos.z}

    if creatorDirection ~= nil then
        -- Direction mapping: 0=N, 1=E, 2=S, 3=W, 4=NE, 5=SE, 6=SW, 7=NW
        if creatorDirection == 0 then -- North
            newPos.y = newPos.y - 1
        elseif creatorDirection == 1 then -- East
            newPos.x = newPos.x + 1
        elseif creatorDirection == 2 then -- South
            newPos.y = newPos.y + 1
        elseif creatorDirection == 3 then -- West
            newPos.x = newPos.x - 1
        elseif creatorDirection == 4 then -- Northeast
            newPos.x = newPos.x + 1
            newPos.y = newPos.y - 1
        elseif creatorDirection == 5 then -- Southeast
            newPos.x = newPos.x + 1
            newPos.y = newPos.y + 1
        elseif creatorDirection == 6 then -- Southwest
            newPos.x = newPos.x - 1
            newPos.y = newPos.y + 1
        elseif creatorDirection == 7 then -- Northwest
            newPos.x = newPos.x - 1
            newPos.y = newPos.y - 1
        end
    end

    -- Get current cavebot data
    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.waypoints then
        cavebotData.waypoints = {}
    end

    -- Get selected waypoint index
    local selectedIndex = nil
    if huntingWaypointsWindow and huntingWaypointsWindow.settings then
        local waypointsList = huntingWaypointsWindow.settings.main.waypoints.list
        if waypointsList then
            for _, widget in ipairs(waypointsList:getChildren()) do
                if widget.selectedWaypoint and widget.waypointIndex then
                    selectedIndex = widget.waypointIndex
                    break
                end
            end
        end
    end

    -- Convert waypoints to sorted array
    local waypoints = {}
    for _, waypoint in pairs(cavebotData.waypoints) do
        table.insert(waypoints, waypoint)
    end
    table.sort(waypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)

    -- Create new rope waypoint (type 3)
    -- Items: 3003 (rope), 9596, 9598, 9594 (canivetes)
    local newWaypoint = {
        position = newPos,
        teleport = false,
        type = 3, -- Rope type
        useItems = {3003, 9596, 9598, 9594}, -- Rope or knives
        index = nil
    }

    -- Apply mode (using creatorMode)
    if creatorMode == 'replace' then
        if selectedIndex then
            newWaypoint.index = selectedIndex
            for i, wp in ipairs(waypoints) do
                if wp.index == selectedIndex then
                    waypoints[i] = newWaypoint
                    break
                end
            end
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    elseif creatorMode == 'add' then
        if selectedIndex then
            newWaypoint.index = selectedIndex + 1
            for i = #waypoints, selectedIndex + 1, -1 do
                waypoints[i].index = waypoints[i].index + 1
            end
            table.insert(waypoints, selectedIndex + 1, newWaypoint)
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    elseif creatorMode == 'insert' then
        if selectedIndex then
            newWaypoint.index = selectedIndex
            for i = #waypoints, selectedIndex, -1 do
                waypoints[i].index = waypoints[i].index + 1
            end
            table.insert(waypoints, selectedIndex, newWaypoint)
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    else
        newWaypoint.index = #waypoints + 1
        table.insert(waypoints, newWaypoint)
    end

    -- Save to cavebot data
    cavebotData.waypoints = {}
    for _, wp in ipairs(waypoints) do
        table.insert(cavebotData.waypoints, wp)
    end

    -- Save to session
    if hunting_recorderModule.selectedSessionUid then
        local cSession = hunting_recorderModule.getSessionSettings()
        cSession['waypoints'] = waypoints
        hunting_recorderModule.setSessionSettings(cSession)
        hunting_recorderModule.saveSessionToDisk(hunting_recorderModule.selectedSessionUid, cSession)
    end

    -- Reload UI (chunked) with callback to select new waypoint
    hunting_recorderModule.reloadAllWaypointsUI(waypoints, function()
        hunting_recorderModule.selectWaypointByPosition(newPos, waypoints)
    end)

    -- Reset direction to Center (C) after creating waypoint
    if creatorDirection ~= nil then
        hunting_recorderModule.setCreatorDirection(nil)
    end

    modules.game_textmessage.displayGameMessage("Rope waypoint created")
    focusGamePanel()
end

function hunting_recorderModule.createHoleWaypoint()
    local player = g_game.getLocalPlayer()
    if not player then
        modules.game_textmessage.displayFailureMessage("Player not found")
        return
    end

    local currentPos = player:getPosition()
    if not currentPos then
        modules.game_textmessage.displayFailureMessage("Could not get player position")
        return
    end

    -- Calculate new position based on direction
    local newPos = {x = currentPos.x, y = currentPos.y, z = currentPos.z}

    if creatorDirection ~= nil then
        -- Direction mapping: 0=N, 1=E, 2=S, 3=W, 4=NE, 5=SE, 6=SW, 7=NW
        if creatorDirection == 0 then -- North
            newPos.y = newPos.y - 1
        elseif creatorDirection == 1 then -- East
            newPos.x = newPos.x + 1
        elseif creatorDirection == 2 then -- South
            newPos.y = newPos.y + 1
        elseif creatorDirection == 3 then -- West
            newPos.x = newPos.x - 1
        elseif creatorDirection == 4 then -- Northeast
            newPos.x = newPos.x + 1
            newPos.y = newPos.y - 1
        elseif creatorDirection == 5 then -- Southeast
            newPos.x = newPos.x + 1
            newPos.y = newPos.y + 1
        elseif creatorDirection == 6 then -- Southwest
            newPos.x = newPos.x - 1
            newPos.y = newPos.y + 1
        elseif creatorDirection == 7 then -- Northwest
            newPos.x = newPos.x - 1
            newPos.y = newPos.y - 1
        end
    end

    -- Get current cavebot data
    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.waypoints then
        cavebotData.waypoints = {}
    end

    -- Get selected waypoint index
    local selectedIndex = nil
    if huntingWaypointsWindow and huntingWaypointsWindow.settings then
        local waypointsList = huntingWaypointsWindow.settings.main.waypoints.list
        if waypointsList then
            for _, widget in ipairs(waypointsList:getChildren()) do
                if widget.selectedWaypoint and widget.waypointIndex then
                    selectedIndex = widget.waypointIndex
                    break
                end
            end
        end
    end

    -- Convert waypoints to sorted array
    local waypoints = {}
    for _, waypoint in pairs(cavebotData.waypoints) do
        table.insert(waypoints, waypoint)
    end
    table.sort(waypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)

    -- Create new hole waypoint (type 4)
    -- Items: 5710 (shovel), 9596, 9598, 9594 (canivetes)
    -- Hole = Use item + Stand (open hole then walk)
    local newWaypoint = {
        position = newPos,
        teleport = false,
        type = 4, -- Hole type (use shovel/knife + stand)
        useItems = {5710, 9596, 9598, 9594}, -- Shovel or knives
        index = nil
    }

    -- Apply mode (using creatorMode)
    if creatorMode == 'replace' then
        if selectedIndex then
            newWaypoint.index = selectedIndex
            for i, wp in ipairs(waypoints) do
                if wp.index == selectedIndex then
                    waypoints[i] = newWaypoint
                    break
                end
            end
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    elseif creatorMode == 'add' then
        if selectedIndex then
            newWaypoint.index = selectedIndex + 1
            for i = #waypoints, selectedIndex + 1, -1 do
                waypoints[i].index = waypoints[i].index + 1
            end
            table.insert(waypoints, selectedIndex + 1, newWaypoint)
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    elseif creatorMode == 'insert' then
        if selectedIndex then
            newWaypoint.index = selectedIndex
            for i = #waypoints, selectedIndex, -1 do
                waypoints[i].index = waypoints[i].index + 1
            end
            table.insert(waypoints, selectedIndex, newWaypoint)
        else
            newWaypoint.index = #waypoints + 1
            table.insert(waypoints, newWaypoint)
        end
    else
        newWaypoint.index = #waypoints + 1
        table.insert(waypoints, newWaypoint)
    end

    -- Save to cavebot data
    cavebotData.waypoints = {}
    for _, wp in ipairs(waypoints) do
        table.insert(cavebotData.waypoints, wp)
    end

    -- Save to session
    if hunting_recorderModule.selectedSessionUid then
        local cSession = hunting_recorderModule.getSessionSettings()
        cSession['waypoints'] = waypoints
        hunting_recorderModule.setSessionSettings(cSession)
        hunting_recorderModule.saveSessionToDisk(hunting_recorderModule.selectedSessionUid, cSession)
    end

    -- Reload UI (chunked) with callback to select new waypoint
    hunting_recorderModule.reloadAllWaypointsUI(waypoints, function()
        hunting_recorderModule.selectWaypointByPosition(newPos, waypoints)
    end)

    -- Reset direction to Center (C) after creating waypoint
    if creatorDirection ~= nil then
        hunting_recorderModule.setCreatorDirection(nil)
    end

    modules.game_textmessage.displayGameMessage("Hole waypoint created")
    focusGamePanel()
end

function hunting_recorderModule.createLeverWaypoint()
    local player = g_game.getLocalPlayer()
    if not player then
        modules.game_textmessage.displayFailureMessage("Player not found")
        return
    end

    local currentPos = player:getPosition()
    if not currentPos then
        modules.game_textmessage.displayFailureMessage("Could not get player position")
        return
    end

    -- Get current cavebot data
    local cavebotData = hunting_recorderModule.getCurrentCavebotData()
    if not cavebotData.waypoints then
        cavebotData.waypoints = {}
    end

    -- Get selected waypoint index
    local selectedIndex = nil
    if huntingWaypointsWindow and huntingWaypointsWindow.settings then
        local waypointsList = huntingWaypointsWindow.settings.main.waypoints.list
        if waypointsList then
            for _, widget in ipairs(waypointsList:getChildren()) do
                if widget.selectedWaypoint and widget.waypointIndex then
                    selectedIndex = widget.waypointIndex
                    break
                end
            end
        end
    end

    -- Convert waypoints to sorted array
    local waypoints = {}
    for _, waypoint in pairs(cavebotData.waypoints) do
        table.insert(waypoints, waypoint)
    end
    table.sort(waypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)

    -- Create Stand waypoint at current position (before lever)
    local standWaypoint = {
        position = {x = currentPos.x, y = currentPos.y, z = currentPos.z},
        teleport = false,
        type = 1, -- Stand type
        index = nil
    }

    -- Calculate lever position based on direction
    local leverPos = {x = currentPos.x, y = currentPos.y, z = currentPos.z}

    if creatorDirection ~= nil then
        -- Direction mapping: 0=N, 1=E, 2=S, 3=W, 4=NE, 5=SE, 6=SW, 7=NW
        if creatorDirection == 0 then -- North
            leverPos.y = leverPos.y - 1
        elseif creatorDirection == 1 then -- East
            leverPos.x = leverPos.x + 1
        elseif creatorDirection == 2 then -- South
            leverPos.y = leverPos.y + 1
        elseif creatorDirection == 3 then -- West
            leverPos.x = leverPos.x - 1
        elseif creatorDirection == 4 then -- Northeast
            leverPos.x = leverPos.x + 1
            leverPos.y = leverPos.y - 1
        elseif creatorDirection == 5 then -- Southeast
            leverPos.x = leverPos.x + 1
            leverPos.y = leverPos.y + 1
        elseif creatorDirection == 6 then -- Southwest
            leverPos.x = leverPos.x - 1
            leverPos.y = leverPos.y + 1
        elseif creatorDirection == 7 then -- Northwest
            leverPos.x = leverPos.x - 1
            leverPos.y = leverPos.y - 1
        end
    else
        modules.game_textmessage.displayFailureMessage("Please select a direction for the lever")
        return
    end

    -- Create Lever waypoint (type 5)
    -- Store the stand position so the walker knows where to return
    local leverWaypoint = {
        position = leverPos,
        teleport = false,
        type = 5, -- Lever type
        standPosition = {x = currentPos.x, y = currentPos.y, z = currentPos.z}, -- Position to return to before using lever
        index = nil
    }

    -- Apply mode (using creatorMode)
    local insertIndex = selectedIndex
    if creatorMode == 'replace' then
        if selectedIndex then
            standWaypoint.index = selectedIndex
            leverWaypoint.index = selectedIndex + 1
            -- Replace selected waypoint with stand
            for i, wp in ipairs(waypoints) do
                if wp.index == selectedIndex then
                    waypoints[i] = standWaypoint
                    break
                end
            end
            -- Shift all waypoints after selected index
            for i = #waypoints, selectedIndex + 1, -1 do
                waypoints[i].index = waypoints[i].index + 1
            end
            -- Insert lever after stand
            table.insert(waypoints, selectedIndex + 1, leverWaypoint)
        else
            standWaypoint.index = #waypoints + 1
            leverWaypoint.index = #waypoints + 2
            table.insert(waypoints, standWaypoint)
            table.insert(waypoints, leverWaypoint)
        end
    elseif creatorMode == 'add' then
        if selectedIndex then
            standWaypoint.index = selectedIndex + 1
            leverWaypoint.index = selectedIndex + 2
            -- Shift all waypoints after selected index
            for i = #waypoints, selectedIndex + 1, -1 do
                waypoints[i].index = waypoints[i].index + 2
            end
            table.insert(waypoints, selectedIndex + 1, standWaypoint)
            table.insert(waypoints, selectedIndex + 2, leverWaypoint)
        else
            standWaypoint.index = #waypoints + 1
            leverWaypoint.index = #waypoints + 2
            table.insert(waypoints, standWaypoint)
            table.insert(waypoints, leverWaypoint)
        end
    elseif creatorMode == 'insert' then
        if selectedIndex then
            standWaypoint.index = selectedIndex
            leverWaypoint.index = selectedIndex + 1
            -- Shift all waypoints from selected index
            for i = #waypoints, selectedIndex, -1 do
                waypoints[i].index = waypoints[i].index + 2
            end
            table.insert(waypoints, selectedIndex, standWaypoint)
            table.insert(waypoints, selectedIndex + 1, leverWaypoint)
        else
            standWaypoint.index = #waypoints + 1
            leverWaypoint.index = #waypoints + 2
            table.insert(waypoints, standWaypoint)
            table.insert(waypoints, leverWaypoint)
        end
    else
        standWaypoint.index = #waypoints + 1
        leverWaypoint.index = #waypoints + 2
        table.insert(waypoints, standWaypoint)
        table.insert(waypoints, leverWaypoint)
    end

    -- Save to cavebot data
    cavebotData.waypoints = {}
    for _, wp in ipairs(waypoints) do
        table.insert(cavebotData.waypoints, wp)
    end

    -- Save to session
    if hunting_recorderModule.selectedSessionUid then
        local cSession = hunting_recorderModule.getSessionSettings()
        cSession['waypoints'] = waypoints
        hunting_recorderModule.setSessionSettings(cSession)
        hunting_recorderModule.saveSessionToDisk(hunting_recorderModule.selectedSessionUid, cSession)
    end

    -- Reload UI (chunked)
    hunting_recorderModule.reloadAllWaypointsUI(waypoints, function()
        hunting_recorderModule.selectWaypointByPosition(leverPos, waypoints)
    end)

    -- Reset direction to Center (C) after creating waypoint
    if creatorDirection ~= nil then
        hunting_recorderModule.setCreatorDirection(nil)
    end

    modules.game_textmessage.displayGameMessage("Lever waypoints created (Stand + Lever)")
    focusGamePanel()
end

-- Check if cavebot window is open
function modules.game_helper.isCavebotWindowOpen()
    return huntingWaypointsWindow ~= nil and huntingWaypointsWindow:isVisible()
end

-- Show waypoint creation menu when Ctrl + Right Click on map
function modules.game_helper.showCavebotWaypointMenu(mousePosition, autoWalkPos)
    local menu = g_ui.createWidget('HelperPopupMenu')
    menu:setGameMenu(true)

    -- Helper function to create waypoint at clicked position
    local function createWaypointAtPosition(waypointType)
        -- Get current cavebot data
        local cavebotData = hunting_recorderModule.getCurrentCavebotData()
        if not cavebotData.waypoints then
            cavebotData.waypoints = {}
        end

        -- Convert waypoints to sorted array to get next index
        local waypoints = {}
        for _, waypoint in pairs(cavebotData.waypoints) do
            table.insert(waypoints, waypoint)
        end
        table.sort(waypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)

        -- Determine next index (add mode by default)
        local nextIndex = #waypoints + 1

        -- Create new waypoint object
        local newWaypoint = {
            position = {x = autoWalkPos.x, y = autoWalkPos.y, z = autoWalkPos.z},
            type = waypointType,
            index = nextIndex
        }

        -- Add to waypoints array
        table.insert(waypoints, newWaypoint)

        -- Update cavebot data
        cavebotData.waypoints = {}
        for _, wp in ipairs(waypoints) do
            cavebotData.waypoints[wp.index] = wp
        end
        hunting_recorderModule.setCurrentCavebotData(cavebotData)

        -- Reload waypoints in UI (chunked) with callback to select new waypoint
        local selectPos = {x = autoWalkPos.x, y = autoWalkPos.y, z = autoWalkPos.z}
        hunting_recorderModule.reloadAllWaypointsUI(waypoints, function()
            hunting_recorderModule.selectWaypointByPosition(selectPos, waypoints)
        end)

        -- Update debug position display
        hunting_recorderModule.updateDebugPos()

        modules.game_textmessage.displayGameMessage("Waypoint created at position " .. autoWalkPos.x .. ", " .. autoWalkPos.y .. ", " .. autoWalkPos.z)
        focusGamePanel()
    end

    -- Node waypoint (type 0)
    menu:addOption('Node', function()
        createWaypointAtPosition(0)
    end)

    -- Stand waypoint (type 1)
    menu:addOption('Stand', function()
        createWaypointAtPosition(1)
    end)

    -- Use waypoint (type 2)
    menu:addOption('Use', function()
        createWaypointAtPosition(2)
    end)

    -- Rope waypoint (type 3)
    menu:addOption('Rope', function()
        createWaypointAtPosition(3)
    end)

    -- Hole waypoint (type 4)
    menu:addOption('Hole', function()
        createWaypointAtPosition(4)
    end)

    -- Lever waypoint (type 5)
    menu:addOption('Lever', function()
        createWaypointAtPosition(5)
    end)

    menu:display(mousePosition)
end

-- New function to add cavebot options to an existing menu
function modules.game_helper.addCavebotOptionsToMenu(menu, mousePosition, autoWalkPos)
    if not menu or not autoWalkPos then
        return
    end

    -- NÃO mostrar opções se o cavebot estiver rodando
    if helperConfig and helperConfig.cavebotHelperEnabled then
        g_logger.debug("[Cavebot] Menu de criação não mostrado - cavebot está rodando")
        return
    end

    -- Helper function to create waypoint at clicked position
    local function createWaypointAtPosition(waypointType)
        -- Get current cavebot data
        local cavebotData = hunting_recorderModule.getCurrentCavebotData()
        if not cavebotData.waypoints then
            cavebotData.waypoints = {}
        end

        -- Convert waypoints to sorted array to get next index
        local waypoints = {}
        for _, waypoint in pairs(cavebotData.waypoints) do
            table.insert(waypoints, waypoint)
        end
        table.sort(waypoints, function(a, b) return (a.index or 0) < (b.index or 0) end)

        -- Determine next index (add mode by default)
        local nextIndex = #waypoints + 1

        -- Create new waypoint object
        local newWaypoint = {
            position = {x = autoWalkPos.x, y = autoWalkPos.y, z = autoWalkPos.z},
            type = waypointType,
            index = nextIndex
        }

        -- Add to waypoints array
        table.insert(waypoints, newWaypoint)

        -- Update cavebot data
        cavebotData.waypoints = {}
        for _, wp in ipairs(waypoints) do
            cavebotData.waypoints[wp.index] = wp
        end
        hunting_recorderModule.setCurrentCavebotData(cavebotData)

        -- Reload waypoints in UI (chunked) with callback to select new waypoint
        local selectPos = {x = autoWalkPos.x, y = autoWalkPos.y, z = autoWalkPos.z}
        hunting_recorderModule.reloadAllWaypointsUI(waypoints, function()
            hunting_recorderModule.selectWaypointByPosition(selectPos, waypoints)
        end)

        -- Update debug position display
        hunting_recorderModule.updateDebugPos()

        modules.game_textmessage.displayGameMessage("Waypoint created at position " .. autoWalkPos.x .. ", " .. autoWalkPos.y .. ", " .. autoWalkPos.z)
        focusGamePanel()
    end

    -- Add separator before cavebot options
    menu:addSeparator()

    -- Add cavebot waypoint options
    menu:addOption('Cavebot: Node', function()
        createWaypointAtPosition(0)
    end)

    menu:addOption('Cavebot: Stand', function()
        createWaypointAtPosition(1)
    end)

    menu:addOption('Cavebot: Use', function()
        createWaypointAtPosition(2)
    end)

    menu:addOption('Cavebot: Rope', function()
        createWaypointAtPosition(3)
    end)

    menu:addOption('Cavebot: Hole', function()
        createWaypointAtPosition(4)
    end)

    menu:addOption('Cavebot: Lever', function()
        createWaypointAtPosition(5)
    end)
end

-- ============================================================================
-- CAVEBOT LOG (decisões/ações em tempo real)
-- Mostra 5 linhas visíveis, scroll, limitado a 100 mensagens (FIFO).
-- ============================================================================

local CAVEBOT_LOG_MAX = 100
local cavebotLogBuffer = {}
local cavebotLogWindow = nil

local function formatLogTime()
    local s = os.date("%H:%M:%S")
    return s or ""
end

local function colorForLog(entry)
    local t = entry.type or "info"
    if t == "warn" then return "#FFCC66" end
    if t == "error" then return "#FF6666" end
    if t == "lure" then return "#55FFAA" end
    if t == "kill" then return "#FF9999" end
    if t == "stop" then return "#FF6666" end
    if t == "action" then return "#9ECBFF" end
    return "#C0C0C0"
end

-- MAD-13 D4: in-place log refresh.
-- Previously this destroyed ALL children + recreated 100 widgets per cavebot log push
-- (firing at 2-10 Hz). Now it reuses existing widgets and only mutates text/color.
-- Cached widget refs avoid the recursiveGetChildById walks per call.
local function refreshCavebotLogUI()
    if not cavebotLogWindow or cavebotLogWindow:isDestroyed() then
        cavebotLogWindow = nil
        return
    end

    local list = cavebotLogWindow.cachedLogList
    if not list or list:isDestroyed() then
        list = cavebotLogWindow:recursiveGetChildById('logList')
        cavebotLogWindow.cachedLogList = list
    end
    if not list then return end

    local listWidth = list:getWidth() - 12
    local existing = list:getChildren()
    local existingCount = #existing
    local bufferCount = #cavebotLogBuffer

    -- In-place update existing widgets, create only the deficit
    for i = 1, bufferCount do
        local entry = cavebotLogBuffer[i]
        local w = existing[i]
        if not w then
            w = g_ui.createWidget('CavebotLogEntry', list)
            if not w then break end
        end
        if listWidth and listWidth > 0 then
            w:setWidth(listWidth)
        end
        w:setText(string.format("[%s] %s", entry.time, entry.msg))
        w:setColor(colorForLog(entry))
    end

    -- Destroy excess widgets (only on buffer shrink, which is rare; the buffer is
    -- bounded by CAVEBOT_LOG_MAX and stays full in steady state)
    for i = bufferCount + 1, existingCount do
        local w = existing[i]
        if w and not w:isDestroyed() then
            w:destroy()
        end
    end

    local titleLabel = cavebotLogWindow.cachedTitleLabel
    if not titleLabel or titleLabel:isDestroyed() then
        titleLabel = cavebotLogWindow:recursiveGetChildById('titleLabel')
        cavebotLogWindow.cachedTitleLabel = titleLabel
    end
    if titleLabel then
        titleLabel:setText(string.format("Cavebot Log - %d found", bufferCount))
    end

    -- Auto-scroll to bottom
    local sb = cavebotLogWindow.cachedScrollBar
    if not sb or sb:isDestroyed() then
        sb = cavebotLogWindow:recursiveGetChildById('logScrollBar')
        cavebotLogWindow.cachedScrollBar = sb
    end
    if sb and sb.setValue and sb.getMaximum then
        sb:setValue(sb:getMaximum())
    end
end

function hunting_recorderModule.cavebotLog(msg, msgType)
    if not msg then return end
    local entry = {
        time = formatLogTime(),
        msg = tostring(msg),
        type = msgType or "info",
    }
    table.insert(cavebotLogBuffer, entry)
    while #cavebotLogBuffer > CAVEBOT_LOG_MAX do
        table.remove(cavebotLogBuffer, 1)
    end
    if cavebotLogWindow and not cavebotLogWindow:isDestroyed() then
        refreshCavebotLogUI()
    end
end

function hunting_recorderModule.clearCavebotLog()
    cavebotLogBuffer = {}
    refreshCavebotLogUI()
end

function hunting_recorderModule.copyCavebotLog()
    local lines = {}
    for _, entry in ipairs(cavebotLogBuffer) do
        table.insert(lines, string.format("[%s] %s", entry.time, entry.msg))
    end
    local text = table.concat(lines, "\n")
    if g_window and g_window.setClipboardText then
        g_window.setClipboardText(text)
    end
    if modules.game_textmessage and modules.game_textmessage.displayGameMessage then
        modules.game_textmessage.displayGameMessage(string.format("[Cavebot Log] %d lines copied to clipboard", #lines))
    end
end

function hunting_recorderModule.closeCavebotLog()
    if cavebotLogWindow and not cavebotLogWindow:isDestroyed() then
        cavebotLogWindow:destroy()
    end
    cavebotLogWindow = nil
end

local function getCavebotLogDefaultPos()
    local rw = g_ui.getRootWidget()
    local rh = rw and rw:getHeight() or 600
    return {x = 60, y = math.max(60, rh - 260)}
end

local function isCavebotLogOffScreen(pos)
    if not cavebotLogWindow or cavebotLogWindow:isDestroyed() then return false end
    local rw = g_ui.getRootWidget()
    if not rw then return false end
    local screenW, screenH = rw:getWidth(), rw:getHeight()
    local winW = cavebotLogWindow:getWidth()
    local minVisible = 40
    local titleH = 36
    return (pos.x + winW <= minVisible) or
           (pos.x >= screenW - minVisible) or
           (pos.y + titleH <= 0) or
           (pos.y >= screenH - titleH)
end

local function clampCavebotLogPos(pos)
    if not cavebotLogWindow or cavebotLogWindow:isDestroyed() then return pos end
    local rw = g_ui.getRootWidget()
    if not rw then return pos end
    local screenW, screenH = rw:getWidth(), rw:getHeight()
    local winW = cavebotLogWindow:getWidth()
    local minVisible = 40
    local titleH = 36
    return {
        x = math.max(-(winW - minVisible), math.min(pos.x, screenW - minVisible)),
        y = math.max(0, math.min(pos.y, screenH - titleH))
    }
end

function hunting_recorderModule.openCavebotLog()
    if cavebotLogWindow and not cavebotLogWindow:isDestroyed() then
        cavebotLogWindow:raise()
        cavebotLogWindow:focus()
        return
    end
    local rootWidget = g_ui.getRootWidget()
    if not rootWidget then return end
    cavebotLogWindow = g_ui.createWidget('CavebotLogWindow', rootWidget)
    if not cavebotLogWindow then return end

    local initialPos = getCavebotLogDefaultPos()
    if isCavebotLogOffScreen(initialPos) then
        initialPos = getCavebotLogDefaultPos()
    end
    cavebotLogWindow:setPosition(initialPos)
    cavebotLogWindow:raise()
    cavebotLogWindow:focus()

    local dragArea = cavebotLogWindow:recursiveGetChildById('dragArea')
    if dragArea then
        dragArea.onMousePress = function(self, mousePos, mouseButton)
            if mouseButton == MouseLeftButton then
                self.dragging = true
                self.dragStart = mousePos
                self.windowStart = cavebotLogWindow:getPosition()
                return true
            end
        end
        dragArea.onMouseRelease = function(self, mousePos, mouseButton)
            self.dragging = false
            if cavebotLogWindow and not cavebotLogWindow:isDestroyed() then
                local pos = cavebotLogWindow:getPosition()
                if isCavebotLogOffScreen(pos) then
                    cavebotLogWindow:setPosition(getCavebotLogDefaultPos())
                end
            end
            return true
        end
        dragArea.onMouseMove = function(self, mousePos, mouseMoved)
            if self.dragging and self.dragStart and self.windowStart then
                local newX = self.windowStart.x + (mousePos.x - self.dragStart.x)
                local newY = self.windowStart.y + (mousePos.y - self.dragStart.y)
                cavebotLogWindow:setPosition(clampCavebotLogPos({x = newX, y = newY}))
                return true
            end
        end
    end

    refreshCavebotLogUI()
end

-- Export the module globally to ensure it's available
_G.hunting_recorderModule = hunting_recorderModule
