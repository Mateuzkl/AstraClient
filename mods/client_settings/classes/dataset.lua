return {
    layout = {
        value = DEFAULT_LAYOUT,
    },

	graphicalCooldown = {
		value = true,
		apply = function(value)
            modules.game_actionbar.toggleCooldownOption()
            return true
        end,
	},

	showSecondTimestampsInConsole = {
		value = true,
		apply = function(value)
            modules.game_console.updateCurrentTab()
            return true
        end,
	},

	displayText = {
		value = true,
		apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawTexts(value)
            return true
        end,
	},

	allActionBar46 = {
		value = false,
		apply = function(value)
            local huds = {"actionBarShowLeft1", "actionBarShowLeft2", "actionBarShowLeft3"}
            for _, actionBar in pairs(huds) do
                local hud = GameOptions:getLoadedWindow("actionsBars"):recursiveGetChildById(actionBar)
                modules.game_actionbar.configureActionBar(actionBar, (value and hud:isChecked()))
            end
            return true
        end,
        tempApply = function(value)
            local huds = {"actionBarShowLeft1", "actionBarShowLeft2", "actionBarShowLeft3"}
            for _, hud in pairs(huds) do
              local actionBar = GameOptions:getLoadedWindow("actionsBars"):recursiveGetChildById(hud)
              if actionBar then
                actionBar:setColor(value and '$var-text-cip-color' or '$var-cip-inactive-color')
              end
            end
            return true
        end,
	},

	timeInventory = {
		value = true,
		apply = function(value) g_game.enableTimerInvetory(value) return true end,
	},

	showOwnHealth = {
		value = true,
		apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawOwnHealth(value)
            gameMapPanel:setDrawHealthBars(value)
            return true
        end,
	},

	storeAskBeforeBuyingProducts = {
		value = true,
	},

	openPrivateMessageInNewTab = {
		value = true,
	},

	showOthersMarks = {
		value = false,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawMarks(value)
            return true
        end,
	},

	showNPC = {
		value = true,
		apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawNpcIcon(value)
            return true
        end,
	},

	prestigeEmblem = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawEmblem(value)
            return true
        end,
	},

	actionBarShowBottom1 = {
		value = true,
        apply = function(value)
            local parent = "allActionBar13"
            local allBox
            if TempOptions:getOption(parent) ~= nil then
              allBox = TempOptions:getOption(parent)
            elseif GameOptions:getOption(parent) ~= nil then
              allBox = GameOptions:getOption(parent)
            else
              allBox = false
            end

            modules.game_actionbar.configureActionBar('actionBarShowBottom1', allBox and value)
            return true
        end,
        tempApply = function(value)
            handleTmpActionBarShow('actionBarShowBottom1', value, "allActionBar13")
            return true
        end
	},

	actionBarShowBottom2 = {
		value = false,
        apply = function(value)
            local parent = "allActionBar13"
            local allBox
            if TempOptions:getOption(parent) ~= nil then
              allBox = TempOptions:getOption(parent)
            elseif GameOptions:getOption(parent) ~= nil then
              allBox = GameOptions:getOption(parent)
            else
              allBox = false
            end

            modules.game_actionbar.configureActionBar('actionBarShowBottom2', allBox and value)
            return true
        end,
        tempApply = function(value)
            handleTmpActionBarShow('actionBarShowBottom2', value, "allActionBar13")
            return true
        end
	},

	actionBarShowBottom3 = {
		value = false,
        apply = function(value)
            local parent = "allActionBar13"
            local allBox
            if TempOptions:getOption(parent) ~= nil then
              allBox = TempOptions:getOption(parent)
            elseif GameOptions:getOption(parent) ~= nil then
              allBox = GameOptions:getOption(parent)
            else
              allBox = false
            end

            modules.game_actionbar.configureActionBar('actionBarShowBottom3', allBox and value)
            return true
        end,
        tempApply = function(value)
            handleTmpActionBarShow('actionBarShowBottom3', value, "allActionBar13")
            return true
        end
	},

  actionBarShowLeft1 = {
		value = false,
        apply = function(value)
            local parent = "allActionBar46"
            local allBox
            if TempOptions:getOption(parent) ~= nil then
              allBox = TempOptions:getOption(parent)
            elseif GameOptions:getOption(parent) ~= nil then
              allBox = GameOptions:getOption(parent)
            else
              allBox = false
            end

            modules.game_actionbar.configureActionBar('actionBarShowLeft1', allBox and value)
            return true
        end,
        tempApply = function(value)
            handleTmpActionBarShow('actionBarShowLeft1', value, "allActionBar46")
            return true
        end
	},

  actionBarShowLeft2 = {
		value = false,
        apply = function(value)
            local parent = "allActionBar46"
            local allBox
            if TempOptions:getOption(parent) ~= nil then
              allBox = TempOptions:getOption(parent)
            elseif GameOptions:getOption(parent) ~= nil then
              allBox = GameOptions:getOption(parent)
            else
              allBox = false
            end

            modules.game_actionbar.configureActionBar('actionBarShowLeft2', allBox and value)
            return true
        end,
        tempApply = function(value)
            handleTmpActionBarShow('actionBarShowLeft2', value, "allActionBar46")
            return true
        end
	},

  actionBarShowLeft3 = {
		value = false,
        apply = function(value)
            local parent = "allActionBar46"
            local allBox
            if TempOptions:getOption(parent) ~= nil then
              allBox = TempOptions:getOption(parent)
            elseif GameOptions:getOption(parent) ~= nil then
              allBox = GameOptions:getOption(parent)
            else
              allBox = false
            end

            modules.game_actionbar.configureActionBar('actionBarShowLeft3', allBox and value)
            return true
        end,
        tempApply = function(value)
            handleTmpActionBarShow('actionBarShowLeft3', value, "allActionBar46")
            return true
        end
	},

  actionBarShowRight1 = {
		value = false,
        apply = function(value)
            local parent = "allActionBar79"
            local allBox
            if TempOptions:getOption(parent) ~= nil then
              allBox = TempOptions:getOption(parent)
            elseif GameOptions:getOption(parent) ~= nil then
              allBox = GameOptions:getOption(parent)
            else
              allBox = false
            end

            modules.game_actionbar.configureActionBar('actionBarShowRight1', allBox and value)
            return true
        end,
        tempApply = function(value)
            handleTmpActionBarShow('actionBarShowRight1', value, "allActionBar79")
            return true
        end
	},

	actionBarShowRight2 = {
		value = false,
        apply = function(value)
            local parent = "allActionBar79"
            local allBox
            if TempOptions:getOption(parent) ~= nil then
              allBox = TempOptions:getOption(parent)
            elseif GameOptions:getOption(parent) ~= nil then
              allBox = GameOptions:getOption(parent)
            else
              allBox = false
            end

            modules.game_actionbar.configureActionBar('actionBarShowRight2', allBox and value)
            return true
        end,
        tempApply = function(value)
            handleTmpActionBarShow('actionBarShowRight2', value, "allActionBar79")
            return true
        end
	},

	actionBarShowRight3 = {
		value = false,
        apply = function(value)
            local parent = "allActionBar79"
            local allBox
            if TempOptions:getOption(parent) ~= nil then
              allBox = TempOptions:getOption(parent)
            elseif GameOptions:getOption(parent) ~= nil then
              allBox = GameOptions:getOption(parent)
            else
              allBox = false
            end

            modules.game_actionbar.configureActionBar('actionBarShowRight3', allBox and value)
            return true
        end,
        tempApply = function(value)
            handleTmpActionBarShow('actionBarShowRight3', value, "allActionBar79")
            return true
        end
	},

	profile = {
		value = "1",
	},

	ambientLight = {
		value = 100,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setMinimumAmbientLight(value/100)
            gameMapPanel:setDrawLights(GameOptions:getOption('enableLights') and value < 100)
            return true
        end,
        tempApply = function(value)
            local graphics = GameOptions:getLoadedWindow('effects')
            local wid = graphics:recursiveGetChildById('enableLights')
            if wid and not wid:isChecked() then
              return true
            end

            local wid = graphics:recursiveGetChildById('ambientLabel')
            if wid then
              wid:setText(tr('Ambient Light: %d %%', value))
            end
            return true
        end,
	},

	hidePlayerBars = {
		value = false,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            local showBars = not value
                          and GameOptions:getOption("ownHUDCharacter")
                          and GameOptions:getOption("showOwnBars")
            gameMapPanel:setDrawPlayerBars(showBars)
            return true
        end,
	},

	storeNotification = {
		value = true,
	},

	containerPanel = {
		value = 8,
	},

	containerMoveToManagedContainerRecursive = {
		value = false,
	},

	showStatusOthersMessagesInConsole = {
		value = true,
	},

	walkTeleportDelay = {
		value = 0,
        apply = function(value)
            local controls = GameOptions:getLoadedWindow('controls')
            local label = controls and controls:recursiveGetChildById('walkTeleportDelayLabel')
            if label then
              label:setText(tr('Walk delay after teleport: %d ms', value))
            end
            if modules.game_walking and modules.game_walking.setWalkDelayOption then
              modules.game_walking.setWalkDelayOption('walkTeleportDelay', value)
            end
            return true
        end,
        tempApply = function(value)
            local controls = GameOptions:getLoadedWindow('controls')
            local label = controls and controls:recursiveGetChildById('walkTeleportDelayLabel')
            if label then
              label:setText(tr('Walk delay after teleport: %d ms', value))
            end
            return true
        end,
	},

	optimizationLevel = {
		value = 1,
        apply = function(value)
            g_adaptiveRenderer.setLevel(value - 2)
            return true
        end,
	},

	musicSoundVolume = {
		value = 100,
        apply = function(value)
            if g_sounds ~= nil then
                g_sounds.getChannel(SoundChannels.Music):setGain(value/100)
            end
            return true
        end,
	},

	hotkeyDelay = {
		value = 5,
        apply = function(value)
            local delayLabel =  GameOptions:getLoadedWindow('controls'):recursiveGetChildById('delayLabel')
            if delayLabel then
              delayLabel:setText(tr('Keyboard Delay: %d ms', value))
              if value < 50 then
                delayLabel:setColor("$var-text-cip-store-red")
              elseif value < 250 then
                delayLabel:setColor("$var-text-cip-color-orange")
              else
                delayLabel:setColor("$var-text-cip-color")
              end

              if not m_settings.getOption('hotkeyDelayNative') then
                rootWidget:getChildById("gameRootPanel"):setAutoRepeatDelay(math.max(0, tonumber(value)))
              end
            end

            if m_settings.getOption('hotkeyDelayNative') then
              delayLabel:setColor("$var-cip-inactive-color")
            end
            return true
        end,
        tempApply = function(value)
            local delayLabel =  GameOptions:getLoadedWindow('controls'):recursiveGetChildById('delayLabel')
            if delayLabel then
              delayLabel:setText(tr('Keyboard Delay: %d ms', value))
              if value < 50 then
                delayLabel:setColor("$var-text-cip-store-red")
              elseif value < 250 then
                delayLabel:setColor("$var-text-cip-color-orange")
              else
                delayLabel:setColor("$var-text-cip-color")
              end

              if not m_settings.getOption('hotkeyDelayNative') then
                rootWidget:getChildById("gameRootPanel"):setAutoRepeatDelay(math.max(0, tonumber(value)))
              end
            end
            return true
        end,
	},

	walkTurnDelay = {
		value = 0,
        apply = function(value)
            local controls = GameOptions:getLoadedWindow('controls')
            local label = controls and controls:recursiveGetChildById('walkTurnDelayLabel')
            if label then
              label:setText(tr('Walk delay after turn: %d ms', value))
            end
            if modules.game_walking and modules.game_walking.setWalkDelayOption then
              modules.game_walking.setWalkDelayOption('walkTurnDelay', value)
            end
            return true
        end,
        tempApply = function(value)
            local controls = GameOptions:getLoadedWindow('controls')
            local label = controls and controls:recursiveGetChildById('walkTurnDelayLabel')
            if label then
              label:setText(tr('Walk delay after turn: %d ms', value))
            end
            return true
        end,
	},

	showLevelsInConsole = {
		value = true,
        apply = function(value)
            modules.game_console.updateCurrentTab()
            return true
        end,
	},

	allActionBar13 = {
		value = false,
        apply = function(value)
            local huds = {"actionBarShowBottom1", "actionBarShowBottom2", "actionBarShowBottom3"}
            for _, actionBar in pairs(huds) do
                local hud = GameOptions:getLoadedWindow("actionsBars"):recursiveGetChildById(actionBar)
                modules.game_actionbar.configureActionBar(actionBar, (value and hud:isChecked()))
            end
            return true
        end,
        tempApply = function(value)
            local huds = {"actionBarShowBottom1", "actionBarShowBottom2", "actionBarShowBottom3"}
            for _, hud in pairs(huds) do
              local actionBar = GameOptions:getLoadedWindow("actionsBars"):recursiveGetChildById(hud)
              if actionBar then
                actionBar:setColor(value and '$var-text-cip-color' or '$var-cip-inactive-color')
              end
            end
            return true
        end,
	},

	cacheMap = {
		value = false,
        apply = function(value)
            m_interface.refreshViewMode()
            return true
        end,
	},

	showRightHorizontalPanel = {
		value = false,
        apply = function(value)
            m_interface.showRightHorizontalPanel(value)
            return true
        end,
	},

	nativeMouseCursor = {
		value = false,
        apply = function(value)
            g_mouse.setUseNativeCursor(value)
            if value then
                g_window.restoreMouseCursor()
            end
            local gameMapPanel = m_interface.getMapPanel()
            if gameMapPanel then
                gameMapPanel:setCursorAnimations(not value and GameOptions:getOption('mouseAnimatedCursor') ~= false)
            end
            return true
        end,
	},

	mouseAnimatedCursor = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            if gameMapPanel then
                gameMapPanel:setCursorAnimations(value and not GameOptions:getOption('nativeMouseCursor'))
            end
            return true
        end,
	},

	autoChaseOverride = {
		value = true,
	},

	talkOnRightClick = {
		value = false,
	},

	stayLoggedInforSession = {
		value = false,
	},

	chatModeOn = {
		value = true,
	},

	ctrlDragCheckBox = {
		value = false,
	},

	alwaysTurnTowardsMoveDirection = {
		value = true,
	},

	actionbarLock = {
		value = false,
	},

	classicView = {
		value = true,
        apply = function(value)
            m_interface.refreshViewMode()
            return true
        end,
	},

	cooldownSecond = {
		value = true,
        apply = function(value)
            modules.game_actionbar.toggleCooldownOption()
            return true
        end,
	},

	hotkeyDelayNative = {
		value = false,
        apply = function(value)
            local controls = GameOptions:getLoadedWindow('controls')
            local delayLabel = controls:recursiveGetChildById('hotkeyDelay')
            if delayLabel then
              delayLabel:setEnabled(not value)
              delayLabel:setColor(not value and '$var-text-cip-color' or '$var-cip-inactive-color')
            end
            local delayLabel = controls:recursiveGetChildById('delayLabel')
            if delayLabel then
              delayLabel:setText(tr('Keyboard Delay: %d ms', getOption('hotkeyDelay')))
              delayLabel:setColor(not value and '$var-text-cip-color' or '$var-cip-inactive-color')
              if not value then
                if getOption('hotkeyDelay') < 50 then
                  delayLabel:setColor("$var-text-cip-store-red")
                elseif getOption('hotkeyDelay') < 250 then
                  delayLabel:setColor("$var-text-cip-color-orange")
                else
                  delayLabel:setColor("$var-text-cip-color")
                end
              end
              rootWidget:getChildById("gameRootPanel"):setAutoRepeatDelay(value and 250 or math.max(0, tonumber(getOption('hotkeyDelay'))))
            end
            return true
        end,
        tempApply = function(value)
            local controls = GameOptions:getLoadedWindow('controls')
            if not controls then return true end
            local delayLabel = controls:recursiveGetChildById('hotkeyDelay')
            if delayLabel then
                delayLabel:setEnabled(not value)
                delayLabel:setColor(not value and '$var-text-cip-color' or '$var-cip-inactive-color')
            end
            local delayLabel = controls:recursiveGetChildById('delayLabel')
            if delayLabel then
                local controls = GameOptions:getLoadedWindow('controls')
                local delay = controls:recursiveGetChildById('hotkeyDelay')
                delayLabel:setText(tr('Keyboard Delay: %d ms', delay:getValue()))
                delayLabel:setColor(not value and '$var-text-cip-color' or '$var-cip-inactive-color')
                if not value then
                    local hotkeyDelayValue = GameOptions:getOption('hotkeyDelay')
                    if hotkeyDelayValue < 50 then
                        delayLabel:setColor("$var-text-cip-store-red")
                    elseif hotkeyDelayValue < 250 then
                        delayLabel:setColor("$var-text-cip-color-orange")
                    else
                        delayLabel:setColor("$var-text-cip-color")
                    end
                end
            end
            return true
        end
	},

	showBoostedMessagesInConsole = {
		value = true,
	},

	opacityArc = {
		value = 70,
        apply = function(value)
            g_map.setArcOpacity(value / 100)
            local wid = GameOptions:getLoadedWindow('hud'):recursiveGetChildById('opacityLabel')
            if wid then
              wid:setText(tr('Opacity: %d%%', value))
            end
            if modules.game_healthcircle and modules.game_healthcircle.setCircleOpacity then
                modules.game_healthcircle.setCircleOpacity(value / 100)
            end
            return true
        end,
        tempApply = function(value)
            local wid = GameOptions:getLoadedWindow('hud'):recursiveGetChildById('opacityLabel')
            if wid then
              wid:setText(tr('Opacity: %d%%', value))
            end
            if modules.game_healthcircle and modules.game_healthcircle.setCircleOpacity then
                modules.game_healthcircle.setCircleOpacity(value / 100)
            end
            return true
        end
	},

	displayNames = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawNames(value)
            return true
        end,
	},

	topHealtManaBar = {
		value = true,
        apply = function(value)
            if not g_app.isMobile() then return true end

            modules.game_healthinfo.topHealthBar:setVisible(value)
            modules.game_healthinfo.topManaBar:setVisible(value)
            return true
        end,
	},

	showTimestampsInConsole = {
		value = true,
        apply = function(value)
            modules.game_console.updateCurrentTab()
            return true
        end,
	},

	leftPanels = {
		value = 0,
        apply = function(value)
            m_interface.refreshViewMode()
            return true
        end,
	},

	altCheckBox = {
		value = false,
        apply = function(value)
            local chatEnabled = Options.isChatOnEnabled
            KeyBinds:setupAndReset(Options.currentHotkeySetName, chatEnabled and "chatOn" or "chatOff")
            modules.game_walking.configureRotateKeys('altCheckBox', value)
            return true
        end,
	},

	showPing = {
		value = true,
        apply = function(value)
            modules.client_topmenu.setPingVisible(value)
            if modules.game_stats and modules.game_stats.ui.ping then
              modules.game_stats.ui.ping:setVisible(value)
            end
            return true
        end,
	},

	textualEffect = {
		value = true,
        apply = function(value)
            g_map.setTextureTextEnabled(value)
            return true
        end,
	},

	containerMoveToManagedContainerRecursiveWarning = {
		value = false,
	},

	containerSortRecursive = {
		value = false,
	},

	timeUnnused = {
		value = true,
        apply = function(value) g_game.enableTimerUnnused(value) return true end,
	},

	showPrivateMessagesInConsole = {
		value = true,
	},

	quickLogin = {
		value = false,
	},

	dontStretchShrink = {
		value = false,
        apply = function(value)
            addEvent(function()
                m_interface.updateStretchShrink()
            end)
            return true
        end,
	},

	showInfoMessagesInConsole = {
		value = true,
	},

	rightPanels = {
		value = 1,
        apply = function(value)
            m_interface.refreshViewMode()
            return true
        end,
	},

	showFps = {
		value = true,
        apply = function(value)
            modules.client_topmenu.setFpsVisible(value)
            if modules.game_stats and modules.game_stats.ui.fps then
              modules.game_stats.ui.fps:setVisible(value)
            end
            return true
        end,
	},

	stackEffects = {
		value = true,
        apply = function(value)
            g_map.enableStackEffects(value)
            return true
        end,
	},

	containerSortBackpacksFirst = {
		value = false,
	},

	lootControl = {
		value = 1,
	},

	showHealthManaCircle = {
    value = false,
    apply = function(value)
        local gameMapPanel = m_interface.getMapPanel()
        gameMapPanel:setShowArcs(value)
        if modules.game_healthcircle then
            modules.game_healthcircle.setHealthCircle(value)
            modules.game_healthcircle.setManaCircle(value)
        end
        return true
    end,
    tempApply = function(value)
        local window = GameOptions:getLoadedWindow("hud")
        if window then
            window:recursiveGetChildById("sizeBox"):setEnabled(value)
            window:recursiveGetChildById("distanceLabel"):setEnabled(value)
            window:recursiveGetChildById("distanceArc"):setEnabled(value)
            window:recursiveGetChildById("opacityLabel"):setEnabled(value)
            window:recursiveGetChildById("opacityArc"):setEnabled(value)

            local healthCheck = window:recursiveGetChildById("harmonyHealth")
            local manaCheck = window:recursiveGetChildById("harmonyMana")
            if healthCheck and manaCheck then
                healthCheck:setEnabled(value)
                manaCheck:setEnabled(value)
                if value then
                    local arcSide = getTmpOption("harmonyArcSide") or getOption("harmonyArcSide")
                    healthCheck:setChecked(arcSide)
                    manaCheck:setChecked(not arcSide)
                    local gameMapPanel = m_interface.getMapPanel()
                    gameMapPanel:setHarmonyLeftDraw(arcSide)
                end
            end
        end
        local gameMapPanel = m_interface.getMapPanel()
        gameMapPanel:setShowArcs(value)
        if modules.game_healthcircle then
            modules.game_healthcircle.setHealthCircle(value)
            modules.game_healthcircle.setManaCircle(value)
        end
        return true
    end
  },

  sizeBox = {
		value = 1,
        apply = function(value)
            if modules.game_healthcircle then
                modules.game_healthcircle.setArcStyle(value - 1)
            end
            if StatusIconBar and type(StatusIconBar.updatePosition) == 'function' then
                StatusIconBar.updatePosition()
            end
            return true
        end,
	},

	trainingProgress = {
		value = true,
	},

	topBar = {
		value = false,
	},

	classicControl = {
		value = 1,
        apply = function(value)
            local window = GameOptions:getLoadedWindow("controls")
            if window then
              window:recursiveGetChildById("lootControl"):setVisible(value == 1)
            end
            return true
        end,
        TempApply = function(value)
            local window = GameOptions:getLoadedWindow("controls")
            if window then
              window:recursiveGetChildById("lootControl"):setVisible(value == 1)
            end
            return true
        end,
	},

	backgroundFrameRate = {
		value = 100,
        apply = function(value)
            if GameOptions:getOption('vsync') or GameOptions:getOption('noFrameCheckBox') then
                g_app.setMaxFps(0)
            else
                local text, v = value, value
                if value <= 0 or value >= 501 then text = 'max' v = 0 end
                g_app.setMaxFps(v)
            end
            return true
        end,
        tempApply = function(value)
            local graphics = GameOptions:getLoadedWindow('graphics')
            local wid = graphics:recursiveGetChildById('noFrameCheckBox')
            if wid and wid:isChecked() then
              return false
            end

            local wid = graphics:recursiveGetChildById('frameRateLabel')
            if wid then
              wid:setText(tr('Frame Rate Limit: %d', value))
            end
            return true
        end,
	},

	showStatusMessagesInConsole = {
		value = true,
	},

	potionSoundEffect = {
		value = true,
	},

	showLootMessagesInConsole = {
		value = true,
        apply = function(value)
            local gameWindow = GameOptions:getLoadedWindow('gameWindow')
            local wid = gameWindow:recursiveGetChildById('showLootMessagesInConsole')
            if wid then
              local v = GameOptions:getOption('showMessages')
              wid:setEnabled(v)
              wid:setColor(v and '$var-text-cip-color' or '$var-cip-inactive-color')
            end
            return true
        end,
        tempApply = function(value)
            local gameWindow = GameOptions:getLoadedWindow('gameWindow')
            local wid = gameWindow:recursiveGetChildById('showLootMessagesInConsole')
            if wid then
              local v = GameOptions:getOption('showMessages')
              wid:setEnabled(v)
              wid:setColor(v and '$var-text-cip-color' or '$var-cip-inactive-color')
            end
            return true
        end,
	},

	displayHealthOnTop = {
		value = false,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawHealthBarsOnTop(value)
            return true
        end,
	},

	floorFading = {
		value = 0,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setFloorFading(value)
            return true
        end,
	},

	showOwnName = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawOwnName(value)
            gameMapPanel:setDrawNames(value)
            return true
        end,
	},

	optimiseConnectionStability = {
		value = false,
	},

	displayHealth = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawHealthBars(value)
            return true
        end,
	},

  engine = {
		value = -1,
        apply = function(value)
            if getOption("engine") ~= -1 and value ~= getOption("engine") then
              displayInfoBox("Info", "You have selected a different graphics engine. Restart ATC for this change to take effect.")
            end
            return true
        end,
	},


	antialiasing = {
		value = 3,
        apply = function(value)
            if value == 2 then
                g_app.setSmooth(true)
            else
                g_app.setSmooth(false)
            end
            return true
        end,
	},

	hdmodeBox = {
		value = true,
        apply = function(value)
            if g_sprites and g_sprites.setScaleFactor then
                g_sprites.setScaleFactor(value and 2 or 1)
            end
            if m_interface then
                m_interface.refreshViewMode()
            end
            return true
        end,
	},

	showSpells = {
		value = true,
        apply = function(value)
            local gameWindow = GameOptions:getLoadedWindow('gameWindow')
            local wid = gameWindow:recursiveGetChildById('showSpells')
            if wid then
              local v = getOption('showMessages')
              wid:setEnabled(v)
              wid:setColor(v and '$var-text-cip-color' or '$var-cip-inactive-color')
            end
            return true
        end,
        tempApply = function(value)
            local gameWindow = GameOptions:getLoadedWindow('gameWindow')
            local wid = gameWindow:recursiveGetChildById('showSpells')
            if wid then
              local v = getOption('showMessages')
              wid:setEnabled(v)
              wid:setColor(v and '$var-text-cip-color' or '$var-cip-inactive-color')
            end
            return true
        end,
	},

	containerMoveToManagedContainerRecursiveShowWarningAgain = {
		value = false,
	},

	timeContainers = {
		value = true,
        apply = function(value)
            g_game.enableTimerContainer(value)
            GameOptions:getLoadedWindow("interface"):recursiveGetChildById("timeUnnused"):setEnabled(true)
            return true
        end,
        tempApply = function(value)
            local interface = GameOptions:getLoadedWindow("interface")
            local unnusedWidget = interface:recursiveGetChildById("timeUnnused")
            unnusedWidget:setEnabled(true)
            unnusedWidget:setColor('$var-text-cip-color')
            if not value and not interface:recursiveGetChildById("timeInventory"):isChecked() then
              unnusedWidget:setEnabled(false)
              unnusedWidget:setColor('$var-cip-inactive-color')
            end
            return true
        end,
	},

	displayMana = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawManaBar(value)
            return true
        end,
	},

	ctrlCheckBox = {
		value = true,
        apply = function(value)
            local chatEnabled = Options.isChatOnEnabled
            KeyBinds:setupAndReset(Options.currentHotkeySetName, chatEnabled and "chatOn" or "chatOff")
            modules.game_walking.configureRotateKeys('ctrlCheckBox', value)
            return true
        end,
	},

	highlightThingsUnderCursor = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setCrosshairVisible(value)
            return true
        end,
	},

	vsync = {
		value = true,
        apply = function(value)
            local graphics = GameOptions:getLoadedWindow('graphics')
            local color = value and '$var-cip-inactive-color' or '$var-text-cip-color'
            graphics:recursiveGetChildById("noFrameCheckBox"):setEnabled(not value)
            graphics:recursiveGetChildById("backgroundFrameRate"):setEnabled(not value)
            graphics:recursiveGetChildById("frameRateLabel"):setColor(color)
            graphics:recursiveGetChildById("noFrameCheckBox"):setColor(color)
            g_window.setVerticalSync(value)
            if value then
              -- VSync already paces rendering at the monitor refresh rate.
              g_app.setMaxFps(0)
            else
              local maxFps = graphics:recursiveGetChildById("backgroundFrameRate"):getValue() or 100
              local noFrameLimit = graphics:recursiveGetChildById("noFrameCheckBox")
              if noFrameLimit and noFrameLimit:isChecked() then
                maxFps = 0
              end
              g_app.setMaxFps(maxFps)
            end
            return true
        end,
        tempApply = function(value)
            local graphics = GameOptions:getLoadedWindow('graphics')
            local color = value and '$var-cip-inactive-color' or '$var-text-cip-color'
            graphics:recursiveGetChildById("noFrameCheckBox"):setEnabled(not value)
            graphics:recursiveGetChildById("backgroundFrameRate"):setEnabled(not value)
            graphics:recursiveGetChildById("frameRateLabel"):setColor(color)
            graphics:recursiveGetChildById("noFrameCheckBox"):setColor(color)
            return true
        end,
	},

	enableMusicSound = {
		value = false,
        apply = function(value)
            if g_sounds ~= nil then
                g_sounds.getChannel(SoundChannels.Music):setEnabled(value)
              end
            return true
        end,
	},

	opacityMissile = {
		value = 100,
        apply = function(value)
            g_client.setMissileAlpha(value/100)
            local effects = GameOptions:getLoadedWindow("effects")
            effects:recursiveGetChildById('opacityMissileLimitLabel'):setText(tr('Opacity Missiles: %s%%', value))
            return true
        end,
        tempApply = function(value)
            local effects = GameOptions:getLoadedWindow("effects")
            effects:recursiveGetChildById('opacityMissileLimitLabel'):setText(tr('Opacity Missiles: %s%%', value))
            return true
        end,
	},

	opacityEffects = {
		value = 100,
        apply = function(value)
            g_client.setEffectAlpha(value/100)
            local effects = GameOptions:getLoadedWindow("effects")
            effects:recursiveGetChildById('opacityEffectLimitLabel'):setText(tr('Opacity Effect: %s%%', value))
            return true
        end,
        tempApply = function(value)
            local effects = GameOptions:getLoadedWindow("effects")
            effects:recursiveGetChildById('opacityEffectLimitLabel'):setText(tr('Opacity Effect: %s%%', value))
            return true
        end,
	},

	ownSpellOpacity = {
		value = 100,
        apply = function(value)
            g_client.setOwnSpellEffectAlpha(value / 100.0)
            local effects = GameOptions:getLoadedWindow("effects")
            effects:recursiveGetChildById('ownSpellEffectLabel'):setText(tr('Own Spells Effect: %s%%', value))
            return true
        end,
        tempApply = function(value)
            local effects = GameOptions:getLoadedWindow("effects")
            effects:recursiveGetChildById('ownSpellEffectLabel'):setText(tr('Own Spells Effect: %s%%', value))
            return true
        end,
	},

	otherSpellOpacity = {
		value = 100,
        apply = function(value)
            g_client.setOtherPlayerSpellEffectAlpha(value / 100.0)
            local effects = GameOptions:getLoadedWindow("effects")
            effects:recursiveGetChildById('otherSpellEffectLabel'):setText(tr('Other Player Spells Effect: %s%%', value))
            return true
        end,
        tempApply = function(value)
            local effects = GameOptions:getLoadedWindow("effects")
            effects:recursiveGetChildById('otherSpellEffectLabel'):setText(tr('Other Player Spells Effect: %s%%', value))
            return true
        end,
	},

	creatureSpellOpacity = {
		value = 100,
        apply = function(value)
            g_client.setCreatureSpellEffectAlpha(value / 100.0)
            local effects = GameOptions:getLoadedWindow("effects")
            effects:recursiveGetChildById('creatureSpellEffectLabel'):setText(tr('Creature Spells Effect: %s%%', value))
            return true
        end,
        tempApply = function(value)
            local effects = GameOptions:getLoadedWindow("effects")
            effects:recursiveGetChildById('creatureSpellEffectLabel'):setText(tr('Creature Spells Effect: %s%%', value))
            return true
        end,
	},

	bossSpellOpacity = {
		value = 100,
        apply = function(value)
            g_client.setBossAreaCreatureEffectAlpha(value / 100.0)
            local effects = GameOptions:getLoadedWindow("effects")
            effects:recursiveGetChildById('bossSpellEffectLabel'):setText(tr('Boss Area Creature Effect: %s%%', value))
            return true
        end,
        tempApply = function(value)
            local effects = GameOptions:getLoadedWindow("effects")
            effects:recursiveGetChildById('bossSpellEffectLabel'):setText(tr('Boss Area Creature Effect: %s%%', value))
            return true
        end,
	},

  ignoreSpecialEffects = {
    value = false,
    apply = function(value)
        g_client.setIgnoreSpecialEffects(value)
        return true
    end,
  },

	showMessages = {
		value = true,
        apply = function(value)
            g_map.setShowMessageEnabled(value)
            local window = GameOptions:getLoadedWindow("gameWindow")
            local widgets = {"showPrivateMessagesOnScreen", "potionSoundEffect", "showSpells", "spellsOthers", "showHotkeyMessagesInConsole", "showLootMessagesInConsole", "showBoostedMessagesInConsole", "trainingProgress", "storeNotification"}
            for _, wid in pairs(widgets) do
              local w = window:recursiveGetChildById(wid)
              if w then
                w:setEnabled(value)
                w:setColor(value and '$var-text-cip-color' or '$var-cip-inactive-color')
              end
            end
            return true
        end,
        tempApply = function(value)
            local window = GameOptions:getLoadedWindow("gameWindow")
            local widgets = {"showPrivateMessagesOnScreen", "potionSoundEffect", "showSpells", "spellsOthers", "showHotkeyMessagesInConsole", "showLootMessagesInConsole", "showBoostedMessagesInConsole", "trainingProgress", "storeNotification"}
            for _, wid in pairs(widgets) do
              local w = window:recursiveGetChildById(wid)
              if w then
                w:setEnabled(value)
                w:setColor(value and '$var-text-cip-color' or '$var-cip-inactive-color')
              end
            end
            return true
        end,
	},

	showOwnMana = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawOwnManaBar(value)
            gameMapPanel:setDrawOwnManaShieldBar(value)
            gameMapPanel:setDrawManaBar(value)
            return true
        end,
	},

  showHarmony = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawHarmonyBar(value)
            return true
        end,
	},

  showMarks = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawOwnMarks(value)
            return true
        end,
	},

	markTargetVisually = {
		value = 1,
        apply = function(value)
            g_game.setHighlightingTarget(value == 1 or value == 3)
            g_game.setFramingTarget(value == 1 or value == 2)
            -- if g_game.isOnline() then
            --   modules.game_battle.updateSquare(value)
            -- end

            return true
        end,
	},

	smartWalk = {
		value = true,
	},

	walkCtrlTurnDelay = {
		value = 0,
        apply = function(value)
            local controls = GameOptions:getLoadedWindow('controls')
            local label = controls and controls:recursiveGetChildById('walkCtrlTurnDelayLabel')
            if label then
              label:setText(tr('Walk delay after ctrl turn: %d ms', value))
            end
            if modules.game_walking and modules.game_walking.setWalkDelayOption then
              modules.game_walking.setWalkDelayOption('walkCtrlTurnDelay', value)
            end
            return true
        end,
        tempApply = function(value)
            local controls = GameOptions:getLoadedWindow('controls')
            local label = controls and controls:recursiveGetChildById('walkCtrlTurnDelayLabel')
            if label then
              label:setText(tr('Walk delay after ctrl turn: %d ms', value))
            end
            return true
        end,
	},

	fullscreen = {
		value = false,
        apply = function(value)
            g_window.setFullscreen(value)
            return true
        end,
	},

	stowContainer = {
		value = true,
	},

	dash = {
		value = true,
        apply = function(value)
            if value then
                g_game.setMaxPreWalkingSteps(2)
            else
                g_game.setMaxPreWalkingSteps(1)
            end
            return true
        end,
	},

	ownHUDCharacter = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawOwnHUD(value)
            local showBars = not GameOptions:getOption("hidePlayerBars")
                          and value
                          and GameOptions:getOption("showOwnBars")
            gameMapPanel:setDrawPlayerBars(showBars)
            return true
        end,
        tempApply = function(value)
            local huds = {"showOwnBars", "showOwnName", "showOwnHealth", "showOwnMana", "showMarks"}
            for _, hud in pairs(huds) do
              local showHud = selectedWindow:recursiveGetChildById(hud)
              if showHud then
                showHud:setEnabled(value)
              end
            end
            return true
        end,
	},

	otherHUDCreatures = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawOtherHUD(value)
            return true
        end,
        tempApply = function(value)
            local huds = {"displayNames", "displayHealth", "showOthersMarks", "showNPC", "prestigeEmblem"}
            for _, hud in pairs(huds) do
              local showHud = selectedWindow:recursiveGetChildById(hud)
              if showHud then
                showHud:setEnabled(value)
              end
            end
            return true
        end,
	},

	combatFrames = {
		value = true,
	},

	showMarks = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawMarks(value)
            return true
        end,
	},

	showLeftHorizontalPanel = {
		value = false,
        apply = function(value)
            m_interface.showLeftHorizontalPanel(value)
            return true
        end,
	},

	distanceArc = {
		value = 15,
        apply = function(value)
            g_map.setArcDistance(value / 100)
            local wid = GameOptions:getLoadedWindow('hud'):recursiveGetChildById('distanceLabel')
            if wid then
              wid:setText(tr('Distance: %d%%', value))
            end
            if modules.game_healthcircle and modules.game_healthcircle.setDistanceFromCenter then
                modules.game_healthcircle.setDistanceFromCenter(value)
            end
            if StatusIconBar and type(StatusIconBar.updatePosition) == 'function' then
                StatusIconBar.updatePosition()
            end
            return true
        end,
        tempApply = function(value)
            local wid = GameOptions:getLoadedWindow('hud'):recursiveGetChildById('distanceLabel')
            if wid then
              wid:setText(tr('Distance: %d%%', value))
            end
            if modules.game_healthcircle and modules.game_healthcircle.setDistanceFromCenter then
                modules.game_healthcircle.setDistanceFromCenter(value)
            end
            if StatusIconBar and type(StatusIconBar.updatePosition) == 'function' then
                StatusIconBar.updatePosition()
            end
            return true
        end,
	},

  harmonyArcSide = {
    value = true,
    apply = function(value)
        local gameMapPanel = m_interface.getMapPanel()
        gameMapPanel:setHarmonyLeftDraw(value)
        return true
    end,
    tempApply = function(value)
        local gameMapPanel = m_interface.getMapPanel()
        gameMapPanel:setHarmonyLeftDraw(value)
        return true
    end,
  },

	showHotkeyMessagesInConsole = {
		value = true,
        tempApply = function(value)
            local gameWindow = GameOptions:getLoadedWindow('gameWindow')
            local wid = gameWindow:recursiveGetChildById('showHotkeyMessagesInConsole')
            if wid then
              local v = getOption('showMessages')
              wid:setEnabled(v)
              wid:setColor(v and '$var-text-cip-color' or '$var-cip-inactive-color')
            end
            return true
        end,
	},

	maxEffects = {
		value = false,
        apply = function(value)
            local effects = GameOptions:getLoadedWindow('effects')
            local wid = effects:recursiveGetChildById('effectLimitLabel')
            if wid and not value then
              wid:setColor("$var-text-cip-color")
              wid:setText(tr('Effects Limits: %d', getOption('limitEffects')))
            elseif wid then
              wid:setText(tr('Effects Limits: %d', getOption('limitEffects')))
              wid:setColor("$var-cip-inactive-color")
            end

            g_map.setUnlimitEffects(value)
            return true
        end,
        tempApply = function(value)
            local effects = GameOptions:getLoadedWindow('effects')
            local wid = effects:recursiveGetChildById('effectLimitLabel')
            local limitEffects = effects:recursiveGetChildById('limitEffects')
            if wid and not value then
              wid:setColor("$var-text-cip-color")
              limitEffects:enable()
            elseif wid then
              wid:setColor("$var-cip-inactive-color")
              limitEffects:disable()
            end
            return true
        end,
	},

	containerSortRecursiveShowWarningAgain = {
		value = false,
	},

	limitEffects = {
		value = 400,
        apply = function(value)
            local effects = GameOptions:getLoadedWindow('effects')
            local value = math.max(10, math.min(value, 1000))
            g_map.setLimitEffects(value)
            local wid = effects:recursiveGetChildById('effectLimitLabel')
            if wid then
              wid:setText(tr('Effects Limits: %d', value))
            end
            return true
        end,
        tempApply = function(value)
            local effects = GameOptions:getLoadedWindow('effects')
            local wid = effects:recursiveGetChildById('maxEffects')
            if wid and wid:isChecked() then
              return false
            end

            local wid = effects:recursiveGetChildById('effectLimitLabel')
            if wid then
              wid:setText(tr('Effects Limits: %d', value))
            end
            return true
        end,
	},

	lootHighlight = {
		value = true,
	},

	spellsOthers = {
		value = false,
        tempApply = function(value)
            local gameWindow = GameOptions:getLoadedWindow('gameWindow')
            local wid = gameWindow:recursiveGetChildById('spellsOthers')
            if wid then
              local v = GameOptions:getOption('showMessages')
              wid:setEnabled(v)
              wid:setColor(v and '$var-text-cip-color' or '$var-cip-inactive-color')
            end
            return true
        end,
	},

	colouriseLootColor = {
		value = 2,
        apply = function(value)
            g_game.setLootValueState(value - 1)
            return true
        end,
	},

	showOwnBars = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawOwnBars(value)
            local showBars = not GameOptions:getOption("hidePlayerBars")
                          and GameOptions:getOption("ownHUDCharacter")
                          and value
            gameMapPanel:setDrawPlayerBars(showBars)
            return true
        end,
	},

	showEventMessagesInConsole = {
		value = true,
	},

	allActionBar79 = {
		value = false,
        apply = function(value)
            local huds = {"actionBarShowRight1", "actionBarShowRight2", "actionBarShowRight3"}
            for _, actionBar in pairs(huds) do
                local hud = GameOptions:getLoadedWindow("actionsBars"):recursiveGetChildById(actionBar)
                modules.game_actionbar.configureActionBar(actionBar, (value and hud:isChecked()))
            end
            return true
        end,
        tempApply = function(value)
            local huds = {"actionBarShowRight1", "actionBarShowRight2", "actionBarShowRight3"}
            for _, hud in pairs(huds) do
              local actionBar = GameOptions:getLoadedWindow("actionsBars"):recursiveGetChildById(hud)
              if actionBar then
                actionBar:setColor(value and '$var-text-cip-color' or '$var-cip-inactive-color')
              end
            end
            return true
        end,
	},

	noFrameCheckBox = {
		value = false,
        apply = function(value)
            local graphics = GameOptions:getLoadedWindow('graphics')
            local wid = graphics:recursiveGetChildById('frameRateLabel')
            if wid and not value then
              wid:setColor("$var-text-cip-color")
            elseif wid then
              wid:setColor("$var-cip-inactive-color")
            end

            if value then
              g_app.setMaxFps(0)
            else
              local vsync = graphics:recursiveGetChildById("vsync")
              if vsync and vsync:isChecked() then
                  g_window.setVerticalSync(true)
                  g_app.setMaxFps(0)
              else
                local currentFps = TempOptions:getOption('backgroundFrameRate') ~= nil and TempOptions:getOption('backgroundFrameRate') or nil
                if not currentFps then
                  currentFps = GameOptions:getOption('backgroundFrameRate') ~= nil and GameOptions:getOption('backgroundFrameRate') or nil
                end
                g_app.setMaxFps(currentFps and currentFps or 100)
              end
            end

            local wid = graphics:recursiveGetChildById('backgroundFrameRate')
            local vsync = graphics:recursiveGetChildById("vsync")
            if wid and not value and not (vsync and vsync:isChecked()) then
              wid:setEnabled(true)
            elseif wid then
              wid:setEnabled(false)
            end

            return true
        end,
        tempApply = function(value)
            local graphics = GameOptions:getLoadedWindow('graphics')
            local wid = graphics:recursiveGetChildById('frameRateLabel')
            if wid and not value then
              wid:setColor("$var-text-cip-color")
            elseif wid then
              wid:setColor("$var-cip-inactive-color")
            end

            local wid = graphics:recursiveGetChildById('backgroundFrameRate')
            local vsync = graphics:recursiveGetChildById("vsync")
            if wid and not value and not (vsync and vsync:isChecked()) then
              wid:setEnabled(true)
            elseif wid then
              wid:setEnabled(false)
            end
            return true
        end
	},

	actionTooltip = {
		value = true,
        apply = function(value)
            modules.game_actionbar.updateVisibleOptions('tooltip', value)
            return true
        end,
	},

	showSpellParameters = {
		value = true,
        apply = function(value)
            modules.game_actionbar.updateVisibleOptions('parameter', value)
            return true
        end,
	},

	showPrivateMessagesOnScreen = {
		value = true,
        tempApply = function(value)
            local gameWindow = GameOptions:getLoadedWindow('gameWindow')
            local wid = gameWindow:recursiveGetChildById('showPrivateMessagesOnScreen')
            if wid then
              local v = getOption('showMessages')
              wid:setEnabled(v)
              wid:setColor(v and '$var-text-cip-color' or '$var-cip-inactive-color')
            end
            return true
        end,
	},

	showHKObjectsBars = {
		value = true,
        apply = function(value)
            modules.game_actionbar.updateVisibleOptions('amount', value)
            return true
        end,
	},

	enableAudio = {
		value = true,
        apply = function(value)
            if g_sounds ~= nil then
                g_sounds.setAudioEnabled(value)
            end
            return true
        end,
	},

	turnDelay = {
		value = 30,
	},

	otherHUDCreatures = {
		value = true,
        apply = function(value)
            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawOtherHUD(value)
            return true
        end,
        tempApply = function(value)
            local huds = {"displayNames", "displayHealth", "showOthersMarks", "showNPC"}
            for _, hud in pairs(huds) do
              local showHud = GameOptions:getLoadedWindow('hud'):recursiveGetChildById(hud)
              if showHud then
                showHud:setEnabled(value)
              end
            end
            return true
        end,
	},

	autoSwitchHotkey = {
		value = false,
        apply = function(value)
            Options.array["hotkeyOptions"]["autoSwitchHotkeyPreset"] = value
            return true
        end,
	},

	pvpFrames = {
		value = true,
	},

	prestigeEmblem = {
		value = true,
        apply = function(value)
            g_game.enableShowPrestigeTexture(value)
            return true
        end,
	},

	walkStairsDelay = {
		value = 0,
        apply = function(value)
            local controls = GameOptions:getLoadedWindow('controls')
            local label = controls and controls:recursiveGetChildById('walkStairsDelayLabel')
            if label then
              label:setText(tr('Walk delay after floor change: %d ms', value))
            end
            if modules.game_walking and modules.game_walking.setWalkDelayOption then
              modules.game_walking.setWalkDelayOption('walkStairsDelay', value)
            end
            return true
        end,
        tempApply = function(value)
            local controls = GameOptions:getLoadedWindow('controls')
            local label = controls and controls:recursiveGetChildById('walkStairsDelayLabel')
            if label then
              label:setText(tr('Walk delay after floor change: %d ms', value))
            end
            return true
        end,
	},

	walkFirstStepDelay = {
		value = 50,
        apply = function(value)
            local controls = GameOptions:getLoadedWindow('controls')
            local label = controls and controls:recursiveGetChildById('walkFirstStepDelayLabel')
            if label then
              label:setText(tr('Walk delay after first step: %d ms', value))
            end
            if modules.game_walking and modules.game_walking.setWalkDelayOption then
              modules.game_walking.setWalkDelayOption('walkFirstStepDelay', value)
            end
            return true
        end,
        tempApply = function(value)
            local controls = GameOptions:getLoadedWindow('controls')
            local label = controls and controls:recursiveGetChildById('walkFirstStepDelayLabel')
            if label then
              label:setText(tr('Walk delay after first step: %d ms', value))
            end
            return true
        end,
	},

	wsadWalking = {
		value = false,
	},

	showAssignedHKButton = {
		value = true,
        apply = function(value)
            modules.game_actionbar.updateVisibleOptions('hotkey', value)
            return true
        end,
	},

	showCooldown = {
		value = true,
        apply = function(value)
            modules.game_cooldown.toggleVisible(value)
            return true
        end,
	},

	shiftCheckBox = {
		value = false,
        apply = function(value)
            local chatEnabled = Options.isChatOnEnabled
            KeyBinds:setupAndReset(Options.currentHotkeySetName, chatEnabled and "chatOn" or "chatOff")
            modules.game_walking.configureRotateKeys('shiftCheckBox', value)
            return true
        end,
	},

	customisableBars = {
		value = true,
        apply = function(value)
            modules.game_topbar.toggle(value)
            return true
        end,
	},

	statusBars = {
		value = true,
        apply = function(value)
            if not g_game.isOnline() then return true end
            if value then
                modules.game_healthinfo.getHealthInfoWindow():show()
              else
                modules.game_healthinfo.getHealthInfoWindow():hide()
              end
            return true
        end,
	},

	linkCopyWarning = {
		value = true,
	},

	enableLights = {
		value = false,
        apply = function(value)
            local effects = GameOptions:getLoadedWindow('effects')
            local wid = effects:recursiveGetChildById('ambientLabel')
            if wid and value then
              wid:setColor("$var-text-cip-color")
            elseif wid then
              wid:setColor("$var-cip-inactive-color")
            end

            local gameMapPanel = m_interface.getMapPanel()
            gameMapPanel:setDrawLights(value and GameOptions:getOption('ambientLight') < 100)
            return true
        end,
        tempApply = function(value)
            local effects = GameOptions:getLoadedWindow('effects')
            local wid = effects:recursiveGetChildById('ambientLabel')
            local ambientSlider = effects:recursiveGetChildById('ambientLight')
            if wid and value then
              wid:setColor("$var-text-cip-color")
              ambientSlider:enable()
            elseif wid then
              wid:setColor("$var-cip-inactive-color")
              ambientSlider:disable()
            end
            return true
        end,
	},

  enableShaders = {
    value = true,
    apply = function(value)
      modules.game_shaders.clearMapShader()
      if value and g_game.isOnline() then
        modules.game_shaders.onPositionChange(_, g_game.getLocalPlayer():getPosition(), _)
      end
      return true
    end,
  },

  autoScreenshot = {
    value = true,
    apply = function(value)
        local screenshotPanel = GameOptions:getLoadedWindow("screenshot")
        if screenshotPanel then
            local checkboxes = screenshotPanel:getChildById("autoScreenshot")
            if checkboxes then
                checkboxes:setEnabled(value)
            end
        end
        return true
    end,
    tempApply = function(value)
        local screenshotPanel = GameOptions:getLoadedWindow("screenshot")
        if screenshotPanel then
            local checkboxes = screenshotPanel:getChildById("autoScreenshot")
            if checkboxes then
                checkboxes:setEnabled(value)
            end
        end
        return true
    end,
  },

  gameWindowScreen = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotLevelUp = {
      value = true,
      apply = function(value)
          return true
      end,
  },

  screenshotSkillUp = {
      value = true,
      apply = function(value)
          return true
      end,
  },

  screenshotAchievement = {
      value = true,
      apply = function(value)
          return true
      end,
  },

  screenshotBestiaryUnlocked = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotBestiaryComplete = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotTreasure = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotValuableLoot = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotBossDefeated = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotDeathPve = {
      value = true,
      apply = function(value)
          return true
      end,
  },

  screenshotDeathPvp = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotPlayerKill = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotPlayerKillAssist = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotPlayerAttacking = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotHighestDamage = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotHighestHealing = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotLowHealth = {
      value = false,
      apply = function(value)
          return true
      end,
  },

  screenshotGiftOfLife = {
      value = true,
      apply = function(value)
          return true
      end,
  },

  -- UI Sounds
  uiSounds = {
      value = true,
      apply = function(value)
        if g_sounds ~= nil then
            g_sounds.getChannel(ENumericSoundType.UI):setEnabled(value)
        end
        return true
      end,
  },

  uiVolumeScrollBar = {
      value = 100,
      apply = function(value)
        if g_sounds ~= nil then
            g_sounds.getChannel(ENumericSoundType.UI):setGain(value/100.0)
        end

        local soundUI = GameOptions:getLoadedWindow("uiSounds")
        if soundUI then
            local wid = soundUI:recursiveGetChildById("uiVolumeLabel")
            if wid then
                wid:setText(tr('UI Volume: %d%%', value))
            end
        end
        return true
      end,
      tempApply = function(value)
        local soundUI = GameOptions:getLoadedWindow("uiSounds")
        if soundUI then
            local wid = soundUI:recursiveGetChildById("uiVolumeLabel")
            if wid then
                wid:setText(tr('UI Volume: %d%%', value))
            end
        end
        return true
      end,
  },

  quickAllCorpses = {
    value = false,
  },

  showInHudCheckBox = {
    value = true,
    apply = function(value)
        local gameMapPanel = m_interface.getMapPanel()
        gameMapPanel:setDrawHUDStatus(value)

        ConditionsHUD:setShowInHudEnabled(value)
        return true
    end,
    tempApply = function(value)
        ConditionsHUD:setShowInHudEnabled(value)
        return true
    end,
  },

  showInBarCheckBox = {
    value = true,
    apply = function(value)
        ConditionsHUD:setShowInBarEnabled(value)
        return true
    end,
    tempApply = function(value)
        ConditionsHUD:setShowInBarEnabled(value)
        return true
    end,
  },

  showSpellChat = {
    value = true,
    apply = function(value)
        local console = modules.game_console
        if value then
          console.openSpellChannel()
        else
          console.closeSpellChannel()
        end
        return true
    end,
    tempApply = function(value)
        return true
    end,
  },
}
