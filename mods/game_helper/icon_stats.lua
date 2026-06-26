IconStatsModule = {}
IconStatsModule.window = nil
IconStatsModule._suppressGeometry = false
IconStatsModule._visibilityWatchdogEvent = nil
IconStatsModule._presetScrollCooldownMs = 300
IconStatsModule._lastPresetScrollAt = {}

-- OPTIMIZATION: Cached widget references (avoids recursiveGetChildById tree traversal every call)
IconStatsModule._iconCache = {}
IconStatsModule._msgLabelCache = {}

-- The bar belongs to an in-game session: it must never surface on the login
-- screen / character list. Guarded everywhere we open or restore the window.
local function isGameOnline()
    return g_game and g_game.isOnline and g_game.isOnline()
end

local function getIcon(iconId)
    local cached = IconStatsModule._iconCache[iconId]
    if cached then return cached end
    if not IconStatsModule.window then return nil end
    cached = IconStatsModule.window:recursiveGetChildById(iconId)
    if cached then
        IconStatsModule._iconCache[iconId] = cached
    end
    return cached
end

local function getMessageLabel(labelId)
    local cached = IconStatsModule._msgLabelCache[labelId]
    if cached then return cached end
    if modules.game_textmessage and modules.game_textmessage.messagesPanel then
        cached = modules.game_textmessage.messagesPanel:recursiveGetChildById(labelId)
        if cached then
            IconStatsModule._msgLabelCache[labelId] = cached
        end
    end
    return cached
end

local function showToggleMessage(message)
    local label = getMessageLabel("middleCenterLabel")
    if label then
        label:setText(message)
        label:setColor("#FFFFFF")
        label:setVisible(true)
        removeEvent(label.hideEvent)
        label.hideEvent = scheduleEvent(function()
            label:setVisible(false)
        end, 2000)
    end
    scheduleEvent(function()
        if modules.game_interface and modules.game_interface.getRootPanel then
            local rootPanel = modules.game_interface.getRootPanel()
            if rootPanel then
                rootPanel:focus()
            end
        end
    end, 50)
end

-- Icon configuration map - customize the item ID for each feature here
IconStatsModule.iconConfig = {
    healingIcon = {
        itemId = 7643,  -- Health potion (change to your preferred item ID)
        name = "Healing"
    },
    healFriendIcon = {
        itemId = 11604,  -- Health potion (change to your preferred item ID)
        name = "Heal Friend"
    },
    equipmentIcon = {
        -- itemId = 3397,  -- Health potion (change to your preferred item ID)
        itemId = 60353,
        name = "Equipment Swap"
    },
    tankModeIcon = {
        itemId = 61958,  -- Health potion (change to your preferred item ID)
        name = "Tank Mode"
    },
    targetingIcon = {
        itemId = 3278,  -- Health potion (change to your preferred item ID)
        name = "Targeting"
    },
    shooterIcon = {
        itemId = 12809,  -- Health potion (change to your preferred item ID)
        name = "Shooter"
    },
    cavebotIcon = {
        itemId = 19361,  -- Health potion (change to your preferred item ID)
        name = "Cavebot"
    },
    timerIcon = {
        itemId = 2906,  -- Stopwatch/Timer icon
        name = "Timer"
    },
    helperIcon = {
        itemId = 10227,  -- Change to your preferred item ID for Helper toggle
        name = "Helper"
    }
}

local modulePresetKeys = {
    shooter = "selectedShooterProfile",
    healing = "selectedHealingProfile",
    equipment = "selectedEquipmentProfile",
    targeting = "selectedTargetingProfile"
}

local modulePresetIconIds = {
    shooter = "shooterIcon",
    healing = "healingIcon",
    equipment = "equipmentIcon",
    targeting = "targetingIcon"
}

local modulePresetTitles = {
    shooter = "Shooter",
    healing = "Healing",
    equipment = "Equipment",
    targeting = "Targeting"
}

local presetModuleByIconId = {
    shooterIcon = "shooter",
    healingIcon = "healing",
    equipmentIcon = "equipment",
    targetingIcon = "targeting"
}

local function getNowMs()
    if g_clock and g_clock.millis then
        return g_clock.millis()
    end
    return math.floor(os.time() * 1000)
end

local function getCurrentModulePresetName(moduleType)
    local selectedKey = modulePresetKeys[moduleType]
    if not selectedKey then
        return "Preset 1"
    end
    if not helperConfig then
        return "Preset 1"
    end

    local selectedPreset = tostring(helperConfig[selectedKey] or "Preset 1")
    if getModulePresetUiName then
        local displayName = getModulePresetUiName(moduleType, selectedPreset)
        if displayName and displayName ~= "" then
            return tostring(displayName)
        end
    elseif getModulePresetDisplayName then
        local displayName = getModulePresetDisplayName(moduleType, selectedPreset)
        if displayName and displayName ~= "" then
            return tostring(displayName)
        end
    end
    return selectedPreset
end

function IconStatsModule.updateModulePresetTooltip(moduleType)
    if not IconStatsModule.window then
        return
    end

    local iconId = modulePresetIconIds[moduleType]
    if not iconId then
        return
    end

    local icon = getIcon(iconId)
    if not icon then
        return
    end

    local title = modulePresetTitles[moduleType] or "Preset"
    local presetName = getCurrentModulePresetName(moduleType)
    local tooltipText = string.format("%s\nPreset: %s", title, presetName)
    icon:setTooltip(tooltipText)

    -- Force immediate visual refresh if mouse is already over the icon.
    if icon.isHovered and icon:isHovered() and g_tooltip then
        if g_tooltip.onWidgetHoverChange then
            g_tooltip.onWidgetHoverChange(icon, true)
        elseif g_tooltip.display then
            g_tooltip.display(tooltipText)
        end
    end
end

-- Keeps the icon bar just above the game panel — but below everything else
-- (modals, popups, count window, dialogs). Cheap and safe to call from
-- external hotspots that call gameRootPanel:raise() and would otherwise bury
-- the bar under the game panel until the next watchdog tick.
-- Why: Using a raw :raise() would slam the bar on top of modals too, which
-- the user does not want; we only need to stay above the game window itself.
function IconStatsModule.ensureOnTop()
    if not IconStatsModule.window then return end
    if IconStatsModule.window:isDestroyed() then return end
    if not IconStatsModule.window:isVisible() then return end

    local root = g_ui.getRootWidget()
    if not root then return end

    local gameRoot
    if modules and modules.game_interface and modules.game_interface.getRootPanel then
        gameRoot = modules.game_interface.getRootPanel()
    end
    -- No game panel yet (e.g. login screen) — nothing to stay above.
    if not gameRoot or gameRoot:isDestroyed() or gameRoot:getParent() ~= root then
        return
    end

    local gameIdx = root:getChildIndex(gameRoot)
    local ownIdx = root:getChildIndex(IconStatsModule.window)
    if gameIdx <= 0 or ownIdx <= 0 then return end
    -- Already above the game panel; leave sibling z-order alone so open
    -- dialogs/popups that were previously above us keep their natural order.
    if ownIdx > gameIdx then return end

    -- Slot in at the game panel's 1-based index: after the erase-and-insert,
    -- the bar lands directly above the (now shifted-down) game panel.
    root:moveChildToIndex(IconStatsModule.window, gameIdx)
end

-- Global shortcut so non-helper modules can nudge the bar back to the top
-- without having to poke into `IconStatsModule` directly.
_G.ensureIconStatsOnTop = IconStatsModule.ensureOnTop

function IconStatsModule.installDragHooks()
    if IconStatsModule._dragHooksInstalled then return end
    local dragIcon = rawget(_G, "UIDragIcon")
    if not dragIcon then return end

    -- Hooks live on the global UIDragIcon class and outlive this module's
    -- sandbox, so guard the IconStatsModule lookup — after a module reload or
    -- shutdown it resolves to nil and indexing it would crash uiitem.lua.
    local originalDisplay = dragIcon.display
    if originalDisplay then
        dragIcon.display = function(self, item)
            originalDisplay(self, item)
            if IconStatsModule and IconStatsModule.ensureOnTop then
                IconStatsModule.ensureOnTop()
            end
        end
    end

    local originalHide = dragIcon.hide
    if originalHide then
        dragIcon.hide = function(self)
            originalHide(self)
            if IconStatsModule and IconStatsModule.ensureOnTop then
                IconStatsModule.ensureOnTop()
            end
        end
    end

    IconStatsModule._dragHooksInstalled = true
end

function IconStatsModule.installGameEventHooks()
    if IconStatsModule._gameEventsInstalled then return end
    if not connect or not g_game then return end

    connect(g_game, {
        onGameEnd = function()
            if IconStatsModule and IconStatsModule.onLogout then
                IconStatsModule.onLogout()
            end
        end
    })

    IconStatsModule._gameEventsInstalled = true
end

function IconStatsModule.init()
    g_ui.importStyle('styles/icon_stats')

    -- Create window attached to root widget (standalone, not panel)
    IconStatsModule.window = g_ui.createWidget('IconStats', g_ui.getRootWidget())

    -- Install drag hooks once (only first time init runs) so the icon bar is
    -- re-raised immediately when a drag starts/ends, instead of waiting up to
    -- one full second for the visibility watchdog to catch it.
    IconStatsModule.installDragHooks()

    -- Safety net: hide on game end even if helper.lua's offline() aborts
    -- before reaching its IconStatsModule.onLogout() call. Idempotent.
    IconStatsModule.installGameEventHooks()

    -- Initialize all icons
    IconStatsModule.setupIcons()

    -- Setup click handlers
    IconStatsModule.setupClickHandlers()

    -- Initialize border colors based on current state
    IconStatsModule.updateAllIcons()

    -- Setup window move handler to save position only when user releases mouse
    IconStatsModule._isDragging = false

    IconStatsModule.window.onGeometryChange = function()
        if IconStatsModule._suppressGeometry then
            return
        end
        if IconStatsModule.isLocked() then
            IconStatsModule.restorePosition()
            return
        end
        -- Mark as dragging but don't save yet
        IconStatsModule._isDragging = true
    end

    -- Save position when mouse is released
    IconStatsModule.window.onMouseRelease = function()
        if IconStatsModule._isDragging and not IconStatsModule.isLocked() then
            IconStatsModule._isDragging = false
            IconStatsModule.savePosition()
        end
        return false
    end

    -- Keep hidden by default - will show on login if needed
    -- Position will be restored on login when config is loaded
    IconStatsModule.window:hide()

    -- Apply layout and lock state from settings
    if helperConfig and helperConfig.iconStats and helperConfig.iconStats.locked then
        IconStatsModule.setLocked(true)
    end
    if resizeIconStatsWindow then
        resizeIconStatsWindow()
    end

end

function IconStatsModule.setupIcons()
    if not IconStatsModule.window then
        return
    end

    -- Set item IDs from configuration map and build icon cache
    for iconId, config in pairs(IconStatsModule.iconConfig) do
        local icon = getIcon(iconId)
        if icon then
            icon:setItemId(config.itemId)
            local presetModule = presetModuleByIconId[iconId]
            if presetModule then
                IconStatsModule.updateModulePresetTooltip(presetModule)
            elseif config.name then
                icon:setTooltip(config.name)
            end
        end
    end
end

local function normalizePresetDirection(direction)
    if direction == MouseWheelDown or direction == -1 then
        return -1
    end
    return 1
end

function IconStatsModule.cyclePresetFromInteraction(moduleType, direction, isScroll)
    local step = normalizePresetDirection(direction)

    if isScroll then
        local now = getNowMs()
        local last = IconStatsModule._lastPresetScrollAt[moduleType] or 0
        local cooldown = tonumber(IconStatsModule._presetScrollCooldownMs) or 300
        if now - last < cooldown then
            IconStatsModule.updateModulePresetTooltip(moduleType)
            return true
        end
        IconStatsModule._lastPresetScrollAt[moduleType] = now
    end

    if moduleType == "shooter" then
        if step > 0 then
            if nextShooterPreset then
                nextShooterPreset()
            else
                return false
            end
        else
            if previousShooterPreset then
                previousShooterPreset()
            else
                return false
            end
        end
        IconStatsModule.updateModulePresetTooltip("shooter")
        return true
    end

    if moduleType == "healing" then
        if step > 0 then
            if nextHealingPreset then
                nextHealingPreset()
            else
                return false
            end
        else
            if previousHealingPreset then
                previousHealingPreset()
            else
                return false
            end
        end
        IconStatsModule.updateModulePresetTooltip("healing")
        return true
    end

    if moduleType == "equipment" then
        if step > 0 then
            if nextEquipmentPreset then
                nextEquipmentPreset()
            else
                return false
            end
        else
            if previousEquipmentPreset then
                previousEquipmentPreset()
            else
                return false
            end
        end
        IconStatsModule.updateModulePresetTooltip("equipment")
        return true
    end

    if moduleType == "targeting" then
        if step > 0 then
            if nextTargetingPreset then
                nextTargetingPreset()
            else
                return false
            end
        else
            if previousTargetingPreset then
                previousTargetingPreset()
            else
                return false
            end
        end
        IconStatsModule.updateModulePresetTooltip("targeting")
        return true
    end

    return false
end

function IconStatsModule.setupClickHandlers()
    if not IconStatsModule.window then
        return
    end

    local function bindPresetInteractions(iconWidget, moduleType, menuId, subTabId)
        if not iconWidget then
            return
        end

        iconWidget.onMouseRelease = function(self, mousePosition, mouseButton)
            if mouseButton == MouseRightButton then
                IconStatsModule.openHelperMenu(menuId, subTabId)
                return true
            end
            if mouseButton == MouseMidButton then
                return IconStatsModule.cyclePresetFromInteraction(moduleType, 1, false)
            end
            return false
        end

        iconWidget.onMouseWheel = function(self, mousePosition, mouseWheel)
            return IconStatsModule.cyclePresetFromInteraction(moduleType, mouseWheel, true)
        end
    end

    -- Healing
    local healingIcon = getIcon('healingIcon')
    if healingIcon then
        healingIcon.onClick = function()
            IconStatsModule.onHealingClick()
        end
        bindPresetInteractions(healingIcon, "healing", "healingMenu", "healing")
    end

    -- Heal Friend
    local healFriendIcon = getIcon('healFriendIcon')
    if healFriendIcon then
        healFriendIcon.onClick = function()
            IconStatsModule.onHealFriendClick()
        end
        healFriendIcon.onMouseRelease = function(self, mousePosition, mouseButton)
            if mouseButton == MouseRightButton then
                IconStatsModule.openHelperMenu("friendMenu")
                return true
            end
            return false
        end
    end

    -- Equipment
    local equipmentIcon = getIcon('equipmentIcon')
    if equipmentIcon then
        equipmentIcon.onClick = function()
            IconStatsModule.onEquipmentClick()
        end
        bindPresetInteractions(equipmentIcon, "equipment", "equipmentMenu", "equipments")
    end

    -- Tank Mode
    local tankModeIcon = getIcon('tankModeIcon')
    if tankModeIcon then
        tankModeIcon.onClick = function()
            IconStatsModule.onTankModeClick()
        end
        tankModeIcon.onMouseRelease = function(self, mousePosition, mouseButton)
            if mouseButton == MouseRightButton then
                IconStatsModule.openHelperMenu("equipmentMenu", "tankMode")
                return true
            end
            return false
        end
    end

    -- Targeting
    local targetingIcon = getIcon('targetingIcon')
    if targetingIcon then
        targetingIcon.onClick = function()
            IconStatsModule.onTargetingClick()
        end
        bindPresetInteractions(targetingIcon, "targeting", "huntingMenu", "targeting")
    end

    -- Shooter
    local shooterIcon = getIcon('shooterIcon')
    if shooterIcon then
        shooterIcon.onClick = function()
            IconStatsModule.onShooterClick()
        end
        bindPresetInteractions(shooterIcon, "shooter", "huntingMenu", "shooter")
    end

    -- Cavebot
    local cavebotIcon = getIcon('cavebotIcon')
    if cavebotIcon then
        cavebotIcon.onClick = function()
            IconStatsModule.onCavebotClick()
        end
        cavebotIcon.onMouseRelease = function(self, mousePosition, mouseButton)
            if mouseButton == MouseRightButton then
                IconStatsModule.openHelperMenu("huntingMenu", "cavebot")
                return true
            end
            return false
        end
    end

    -- Timer
    local timerIcon = getIcon('timerIcon')
    if timerIcon then
        timerIcon.onClick = function()
            IconStatsModule.onTimerClick()
        end
        timerIcon.onMouseRelease = function(self, mousePosition, mouseButton)
            if mouseButton == MouseRightButton then
                IconStatsModule.openHelperMenu("toolsMenu", "timer")
                return true
            end
            return false
        end
    end

    -- Helper
    local helperIcon = getIcon('helperIcon')
    if helperIcon then
        helperIcon.onClick = function()
            IconStatsModule.onHelperClick()
        end
        helperIcon.onMouseRelease = function(self, mousePosition, mouseButton)
            if mouseButton == MouseRightButton then
                IconStatsModule.openHelperMenu("healingMenu")
                return true
            end
            return false
        end
    end

end

local function getSortedShooterProfiles()
    local profiles = {}
    if not helperConfig or not helperConfig.shooterProfiles then
        return profiles
    end

    for name, _ in pairs(helperConfig.shooterProfiles) do
        table.insert(profiles, name)
    end

    table.sort(profiles)
    return profiles
end

function IconStatsModule.showCenterGreenMessage(text)
    if displayMessage and MessageModes and MessageModes.Look then
        displayMessage(MessageModes.Look, text)
        return
    end

    local label = getMessageLabel("highCenterLabel")
    if label then
        label:setText(text)
        label:setColor("#00ff00")
        label:setVisible(true)
        removeEvent(label.hideEvent)
        label.hideEvent = scheduleEvent(function()
            label:setVisible(false)
        end, 2000)
    end
end

function IconStatsModule.onShooterRightClick()
    IconStatsModule.openHelperMenu("huntingMenu")
    modules.game_helper.selectHuntingSubTab('shooter')
end

-- Click Handlers (Toggle Functions)

function IconStatsModule.onHealingClick()
    g_logger.info("Healing Icon clicked")

    if not helperConfig then
        g_logger.error("helperConfig not found!")
        return
    end

    -- Toggle auto healing state and call the handler
    local newState = not (helperConfig.autoHealingEnabled or false)

    -- Call the helper module function to update both state and UI
    if modules and modules.game_helper and modules.game_helper.onEnableAutoHealing then
        modules.game_helper.onEnableAutoHealing(newState)
        showToggleMessage(newState and "Healing enabled." or "Healing disabled.")
    else
        g_logger.error("modules.game_helper.onEnableAutoHealing not found!")
    end
end

function IconStatsModule.onHealFriendClick()
    g_logger.info("Heal Friend Icon clicked")

    if not helperConfig then
        g_logger.error("helperConfig not found!")
        return
    end

    -- Toggle the state and call the handler
    local newState = not (helperConfig.healFriendEnabled or false)

    -- Call the helper module function to update both state and UI
    if modules and modules.game_helper and modules.game_helper.onEnableAllFriendHealing then
        modules.game_helper.onEnableAllFriendHealing(newState)
        showToggleMessage(newState and "Heal Friend enabled." or "Heal Friend disabled.")
    else
        g_logger.error("modules.game_helper.onEnableAllFriendHealing not found!")
    end
end

function IconStatsModule.onEquipmentClick()
    g_logger.info("Equipment Icon clicked")

    if not helperConfig then
        g_logger.error("helperConfig not found!")
        return
    end

    -- Toggle equipment swap state and call the handler
    local newState = not (helperConfig.equipmentSwapEnabled or false)

    -- Call the helper module function to update both state and UI
    if modules and modules.game_helper and modules.game_helper.onEnableEquipmentSwap then
        modules.game_helper.onEnableEquipmentSwap(newState)
        showToggleMessage(newState and "Equipment Swap enabled." or "Equipment Swap disabled.")
    else
        g_logger.error("modules.game_helper.onEnableEquipmentSwap not found!")
    end
end

function IconStatsModule.onTankModeClick()
    g_logger.info("Tank Mode Icon clicked")

    if not helperConfig then
        g_logger.error("helperConfig not found!")
        return
    end

    -- Toggle tank mode state and call the handler
    local newState = not (helperConfig.tankModeEnabled or false)

    -- Call the helper module function to update both state and UI
    if modules and modules.game_helper and modules.game_helper.onEnableTankMode then
        modules.game_helper.onEnableTankMode(newState)
        showToggleMessage(newState and "Tank Mode enabled." or "Tank Mode disabled.")
    else
        g_logger.error("modules.game_helper.onEnableTankMode not found!")
    end
end

function IconStatsModule.onTargetingClick()
    g_logger.info("Targeting Icon clicked")

    if not helperConfig then
        g_logger.error("helperConfig not found!")
        return
    end

    -- Get current state before toggle
    local currentState = helperConfig.autoTargetEnabled or false
    local newState = not currentState

    -- Call the main toggle function from helper.lua
    if toggleAutoTarget then
        toggleAutoTarget()
        showToggleMessage(newState and "Targeting enabled." or "Targeting disabled.")
    else
        g_logger.error("toggleAutoTarget function not found!")
    end
end

function IconStatsModule.onShooterClick()
    g_logger.info("Shooter Icon clicked")

    if not helperConfig then
        g_logger.error("helperConfig not found!")
        return
    end

    -- Get current state before toggle
    local currentState = helperConfig.magicShooterEnabled or false
    local newState = not currentState

    -- Call the main toggle function from helper.lua
    if toggleMagicShooter then
        toggleMagicShooter()
        showToggleMessage(newState and "Shooter enabled." or "Shooter disabled.")
    else
        g_logger.error("toggleMagicShooter function not found!")
    end
end

function IconStatsModule.onTimerClick()
    g_logger.info("Timer Icon clicked")

    if not helperConfig then
        g_logger.error("helperConfig not found!")
        return
    end

    -- Get current state before toggle
    local currentState = helperConfig.timerEnabled or false
    local newState = not currentState

    -- Toggle timer module
    if modules.game_helper and modules.game_helper.onEnableTimerModule then
        modules.game_helper.onEnableTimerModule(newState)
        showToggleMessage(newState and "Timer enabled." or "Timer disabled.")
    else
        g_logger.error("onEnableTimerModule function not found!")
    end
end

function IconStatsModule.onCavebotClick()
    g_logger.info("Cavebot Icon clicked")

    if not helperConfig then
        g_logger.error("helperConfig not found!")
        return
    end

    -- Get current state before toggle
    local currentState = helperConfig.cavebotHelperEnabled or false
    local newState = not currentState

    -- Call the main toggle function from helper.lua
    if toggleCavebotHelper then
        toggleCavebotHelper()
        showToggleMessage(newState and "Cavebot enabled." or "Cavebot disabled.")
    else
        g_logger.error("toggleCavebotHelper function not found!")
    end
end

function IconStatsModule.onHelperClick()
    g_logger.info("Helper Icon clicked")

    -- Get current state before toggle
    local currentState = hotkeyHelperStatus or false
    local newState = not currentState

    -- Call the main helper toggle function from helper.lua
    if botStatus then
        botStatus()
        showToggleMessage(newState and "Helper enabled." or "Helper disabled.")
    else
        g_logger.error("botStatus function not found!")
    end
end

-- Update Functions (called from helper.lua when state changes)

function IconStatsModule.updateHealingIcon(isActive)
    if not IconStatsModule.window then return end

    local icon = getIcon("healingIcon")
    if icon then
        local color = isActive and "#00FF00" or "#FF0000"
        icon:setBorderColor(color)
        icon:setBorderWidth(1)
    end
end

function IconStatsModule.updateHealFriendIcon(isActive)
    if not IconStatsModule.window then return end

    local icon = getIcon("healFriendIcon")
    if icon then
        local color = isActive and "#00FF00" or "#FF0000"
        icon:setBorderColor(color)
        icon:setBorderWidth(1)
    end
end

function IconStatsModule.updateEquipmentIcon(isActive)
    if not IconStatsModule.window then return end

    local icon = getIcon("equipmentIcon")
    if icon then
        local color = isActive and "#00FF00" or "#FF0000"
        icon:setBorderColor(color)
        icon:setBorderWidth(1)
    end
end

function IconStatsModule.updateTankModeIcon(isActive)
    if not IconStatsModule.window then return end

    local icon = getIcon("tankModeIcon")
    if icon then
        local color = isActive and "#00FF00" or "#FF0000"
        icon:setBorderColor(color)
        icon:setBorderWidth(1)
    end
end

function IconStatsModule.updateTargetingIcon(isActive)
    if not IconStatsModule.window then return end

    local icon = getIcon("targetingIcon")
    if icon then
        local color = isActive and "#00FF00" or "#FF0000"
        icon:setBorderColor(color)
        icon:setBorderWidth(1)
    end
end

function IconStatsModule.updateShooterTooltip()
    IconStatsModule.updateModulePresetTooltip("shooter")
end

function IconStatsModule.updateShooterIcon(isActive)
    if not IconStatsModule.window then return end

    local icon = getIcon("shooterIcon")
    if icon then
        local color = isActive and "#00FF00" or "#FF0000"
        icon:setBorderColor(color)
        icon:setBorderWidth(1)
        -- Atualizar tooltip com o preset atual
        IconStatsModule.updateShooterTooltip()
    end
end

function IconStatsModule.updateCavebotIcon(isActive)
    if not IconStatsModule.window then return end

    local icon = getIcon("cavebotIcon")
    if icon then
        local color = isActive and "#00FF00" or "#FF0000"
        icon:setBorderColor(color)
        icon:setBorderWidth(1)
    end
end

function IconStatsModule.updateTimerIcon(isActive)
    if not IconStatsModule.window then return end

    local icon = getIcon("timerIcon")
    if icon then
        local color = isActive and "#00FF00" or "#FF0000"
        icon:setBorderColor(color)
        icon:setBorderWidth(1)
    end
end

function IconStatsModule.updateHelperIcon(isActive)
    if not IconStatsModule.window then return end

    local icon = getIcon("helperIcon")
    if icon then
        local color = isActive and "#00FF00" or "#FF0000"
        icon:setBorderColor(color)
        icon:setBorderWidth(1)
    end
end

function IconStatsModule.updateAllIcons()
    if not helperConfig then return end

    IconStatsModule.updateHealingIcon(helperConfig.autoHealingEnabled or false)
    IconStatsModule.updateHealFriendIcon(helperConfig.healFriendEnabled or false)
    IconStatsModule.updateEquipmentIcon(helperConfig.equipmentSwapEnabled or false)
    IconStatsModule.updateTankModeIcon(helperConfig.tankModeEnabled or false)
    IconStatsModule.updateTargetingIcon(helperConfig.autoTargetEnabled or false)
    IconStatsModule.updateShooterIcon(helperConfig.magicShooterEnabled or false)
    IconStatsModule.updateCavebotIcon(helperConfig.cavebotHelperEnabled or false)
    IconStatsModule.updateTimerIcon(helperConfig.timerEnabled or false)
    IconStatsModule.updateHelperIcon(hotkeyHelperStatus or false)
    IconStatsModule.updateModulePresetTooltip("healing")
    IconStatsModule.updateModulePresetTooltip("equipment")
    IconStatsModule.updateModulePresetTooltip("targeting")
    IconStatsModule.updateModulePresetTooltip("shooter")
end

-- Window Management Functions

function IconStatsModule.savePosition()
    if not IconStatsModule.window or not helperConfig then
        return
    end

    if IconStatsModule._suppressGeometry then
        return
    end

    if IconStatsModule.isLocked() then
        return
    end

    local pos = IconStatsModule.window:getPosition()
    helperConfig.iconStats = helperConfig.iconStats or {}
    helperConfig.iconStats.x = pos.x
    helperConfig.iconStats.y = pos.y

    if saveIconStatsToClientConfig then
        saveIconStatsToClientConfig()
    end
end

function IconStatsModule.saveVisibility(visible)
    if not helperConfig then
        return
    end

    helperConfig.iconStats = helperConfig.iconStats or {}
    helperConfig.iconStats.visible = visible

    if saveIconStatsToClientConfig then
        saveIconStatsToClientConfig()
    end
end

-- At least this many pixels of the window must remain on-screen to count as
-- "in bounds". Below this threshold we treat the window as lost/off-screen.
local ICON_STATS_MIN_VISIBLE_PIXELS = 20
local ICON_STATS_DEFAULT_X = 100
local ICON_STATS_DEFAULT_Y = 100

local function isIconStatsPositionInBounds(x, y, windowWidth)
    local rootWidget = g_ui.getRootWidget()
    if not rootWidget then
        return true
    end

    local screenWidth = rootWidget:getWidth()
    local screenHeight = rootWidget:getHeight()

    local minX = -windowWidth + ICON_STATS_MIN_VISIBLE_PIXELS
    local maxX = screenWidth - ICON_STATS_MIN_VISIBLE_PIXELS
    local minY = 0
    local maxY = screenHeight - ICON_STATS_MIN_VISIBLE_PIXELS

    return x >= minX and x <= maxX and y >= minY and y <= maxY
end

function IconStatsModule.restorePosition()
    if not IconStatsModule.window or not helperConfig or not helperConfig.iconStats then
        return
    end

    local config = helperConfig.iconStats

    -- Restore only position if valid
    if config.x and config.y then
        local windowWidth = IconStatsModule.window:getWidth()

        if isIconStatsPositionInBounds(config.x, config.y, windowWidth) then
            IconStatsModule._suppressGeometry = true
            IconStatsModule.window:setPosition({x = config.x, y = config.y})
            IconStatsModule._suppressGeometry = false
        else
            -- Reset to default position in config
            helperConfig.iconStats.x = ICON_STATS_DEFAULT_X
            helperConfig.iconStats.y = ICON_STATS_DEFAULT_Y
            IconStatsModule._suppressGeometry = true
            IconStatsModule.window:setPosition({x = ICON_STATS_DEFAULT_X, y = ICON_STATS_DEFAULT_Y})
            IconStatsModule._suppressGeometry = false
            if saveIconStatsToClientConfig then
                saveIconStatsToClientConfig()
            end
        end
    end
end

-- Validates the CURRENT window position against the screen bounds and snaps
-- it back to the default if it has ended up outside the useful area (e.g.
-- after a resolution change or a stale saved position).
-- Returns true when the position was corrected.
function IconStatsModule.ensureWithinBounds()
    if not IconStatsModule.window then
        return false
    end

    local pos = IconStatsModule.window:getPosition()
    if not pos then
        return false
    end

    local windowWidth = IconStatsModule.window:getWidth()

    if isIconStatsPositionInBounds(pos.x, pos.y, windowWidth) then
        return false
    end

    helperConfig = helperConfig or {}
    helperConfig.iconStats = helperConfig.iconStats or {}
    helperConfig.iconStats.x = ICON_STATS_DEFAULT_X
    helperConfig.iconStats.y = ICON_STATS_DEFAULT_Y

    IconStatsModule._suppressGeometry = true
    IconStatsModule.window:setPosition({x = ICON_STATS_DEFAULT_X, y = ICON_STATS_DEFAULT_Y})
    IconStatsModule._suppressGeometry = false

    if saveIconStatsToClientConfig then
        saveIconStatsToClientConfig()
    end
    return true
end

function IconStatsModule.restoreVisibility()
    if not IconStatsModule.window then
        return
    end
    
    -- Check if config exists and has iconStats
    if not helperConfig then
        return
    end
    
    -- Initialize iconStats if missing
    if not helperConfig.iconStats then
        helperConfig.iconStats = {}
    end

    local config = helperConfig.iconStats

    -- Restore visibility - explicitly check for true
    if config.visible == true and isGameOnline() then
        IconStatsModule.window:show()
        IconStatsModule.ensureOnTop()
        IconStatsModule.updateAllIcons()
        if resizeIconStatsWindow then
            resizeIconStatsWindow()
        end
    end
    -- Note: Don't hide if visible is false/nil - let the user control that
    -- This prevents the window from being hidden on every login if config wasn't loaded yet
end

function IconStatsModule.onLogin()
    -- Restore position first
    IconStatsModule.restorePosition()

    -- Initial restore attempt
    IconStatsModule.restoreVisibility()

    if resizeIconStatsWindow then
        resizeIconStatsWindow()
    end

    -- Delayed restore to ensure helperConfig is fully loaded from file
    -- This handles the case where config is loaded after onLogin is called
    scheduleEvent(function()
        IconStatsModule.restoreVisibility()
        IconStatsModule.updateAllIcons()
        if resizeIconStatsWindow then
            resizeIconStatsWindow()
        end
    end, 500)
    
    -- Second delayed check for safety
    scheduleEvent(function()
        IconStatsModule.restoreVisibility()
        IconStatsModule.updateAllIcons()
    end, 1500)
    
    -- Start visibility watchdog to ensure icons stay visible if they should be
    IconStatsModule.startVisibilityWatchdog()
end

function IconStatsModule.onLogout()
    -- Stop watchdog
    IconStatsModule.stopVisibilityWatchdog()
    
    if IconStatsModule.window then
        IconStatsModule.window:hide()
    end
end

function IconStatsModule.terminate()
    -- Stop watchdog
    IconStatsModule.stopVisibilityWatchdog()

    if IconStatsModule.window then
        IconStatsModule.window:destroy()
        IconStatsModule.window = nil
    end

    -- Clear widget caches (widgets are destroyed with the window)
    IconStatsModule._iconCache = {}
    IconStatsModule._msgLabelCache = {}
end

function IconStatsModule.show()
    if not IconStatsModule.window then
        IconStatsModule.init()
    end

    -- Do not open while offline. The user-facing visibility flag stays as it
    -- was so the bar comes back automatically on the next login.
    if not isGameOnline() then
        return
    end

    -- Snap back to the default position if the window drifted outside the
    -- visible area, so it never comes back invisible or unreachable.
    IconStatsModule.ensureWithinBounds()

    IconStatsModule.window:show()
    IconStatsModule.ensureOnTop()
    IconStatsModule.window:focus()

    -- Update all icons to sync with current state
    IconStatsModule.updateAllIcons()
    if resizeIconStatsWindow then
        resizeIconStatsWindow()
    end

    -- Save visibility state
    IconStatsModule.saveVisibility(true)
end

function IconStatsModule.rebuildWindow()
    local wasVisible = false
    local lastPos = nil

    if IconStatsModule.window then
        wasVisible = IconStatsModule.window:isVisible()
        lastPos = IconStatsModule.window:getPosition()
        IconStatsModule.window:destroy()
        IconStatsModule.window = nil
    end

    -- Clear widget caches before rebuilding (old refs are now invalid)
    IconStatsModule._iconCache = {}
    IconStatsModule._msgLabelCache = {}

    IconStatsModule.init()

    if lastPos and IconStatsModule.window then
        IconStatsModule._suppressGeometry = true
        IconStatsModule.window:setPosition({x = lastPos.x, y = lastPos.y})
        IconStatsModule._suppressGeometry = false
    end

    if applyAllIconStatsVisibility then
        applyAllIconStatsVisibility()
    end

    if wasVisible then
        IconStatsModule.show()
    else
        IconStatsModule.hide()
    end
end

function IconStatsModule.isLocked()
    return helperConfig and helperConfig.iconStats and helperConfig.iconStats.locked == true
end

function IconStatsModule.setLocked(locked)
    if not helperConfig then
        return
    end

    helperConfig.iconStats = helperConfig.iconStats or {}
    helperConfig.iconStats.locked = locked == true

    if IconStatsModule.window and IconStatsModule.window.setDraggable then
        IconStatsModule.window:setDraggable(not locked)
    end
end

function IconStatsModule.hide()
    if IconStatsModule.window then
        IconStatsModule.window:hide()

        -- Save visibility state
        IconStatsModule.saveVisibility(false)
    end
end

function IconStatsModule.toggle()
    if not IconStatsModule.window then
        IconStatsModule.init()
    end

    if IconStatsModule.window:isVisible() then
        -- If the window thinks it is visible but has drifted outside the
        -- useful area, treat the toggle as "bring it back" rather than
        -- flipping to hidden — the user was expecting it to reappear, not
        -- disappear on the next press.
        if IconStatsModule.ensureWithinBounds() then
            IconStatsModule.ensureOnTop()
            IconStatsModule.window:focus()
            return
        end
        IconStatsModule.hide()
    else
        IconStatsModule.show()
    end
end

-- Visibility watchdog: periodically checks if window should be visible but isn't
function IconStatsModule.startVisibilityWatchdog()
    IconStatsModule.stopVisibilityWatchdog()
    
    -- Use cycleEvent if available, otherwise use recursive scheduleEvent
    if cycleEvent then
        IconStatsModule._visibilityWatchdogEvent = cycleEvent(function()
            local ok, err = pcall(IconStatsModule.checkVisibilitySync)
            if not ok then
                g_logger.warning("[IconStats] checkVisibilitySync error: " .. tostring(err))
            end
        end, 1000) -- Check every 1 second
    else
        -- Fallback: use recursive scheduleEvent
        local function watchdogLoop()
            local ok, err = pcall(IconStatsModule.checkVisibilitySync)
            if not ok then
                g_logger.warning("[IconStats] checkVisibilitySync error: " .. tostring(err))
            end
            IconStatsModule._visibilityWatchdogEvent = scheduleEvent(watchdogLoop, 1000)
        end
        IconStatsModule._visibilityWatchdogEvent = scheduleEvent(watchdogLoop, 1000)
    end
end

function IconStatsModule.stopVisibilityWatchdog()
    if IconStatsModule._visibilityWatchdogEvent then
        removeEvent(IconStatsModule._visibilityWatchdogEvent)
        IconStatsModule._visibilityWatchdogEvent = nil
    end
end

function IconStatsModule.checkVisibilitySync()
    if not IconStatsModule.window then
        -- Try to initialize if window doesn't exist
        IconStatsModule.init()
        if not IconStatsModule.window then
            return
        end
    end

    -- Offline (login screen / character list / between-characters): the bar
    -- must stay hidden. Snap it back to hidden if a stale tick fired.
    if not isGameOnline() then
        if IconStatsModule.window:isVisible() then
            IconStatsModule.window:hide()
        end
        return
    end

    local config = helperConfig and helperConfig.iconStats
    if not config then
        return
    end

    local shouldBeVisible = config.visible == true
    local isCurrentlyVisible = IconStatsModule.window:isVisible()

    -- If saved state says visible but window is hidden, show it
    if shouldBeVisible and not isCurrentlyVisible then
        IconStatsModule.window:show()
        IconStatsModule.ensureOnTop()
        IconStatsModule.window:focus()
        IconStatsModule.updateAllIcons()
        if resizeIconStatsWindow then
            resizeIconStatsWindow()
        end
        -- Also restore position in case it's off-screen
        IconStatsModule.restorePosition()
    elseif shouldBeVisible and isCurrentlyVisible then
        -- Safety net: the window is visible but may have drifted outside
        -- the screen (resolution change, stale saved position, etc). Snap
        -- it back silently if needed.
        IconStatsModule.ensureWithinBounds()
        -- Keep the bar directly above the game panel. Other modules
        -- (game_interface item drop, count window, pixshop, battlepass, etc)
        -- call gameRootPanel:raise() which would otherwise bury us under it.
        -- ensureOnTop is a no-op when we are already above the game panel,
        -- so modals/popups/countWindow keep their natural z-order.
        IconStatsModule.ensureOnTop()
    end
end

-- Returns the menuId of the currently checked sideMenu button (real UI state)
function IconStatsModule.getCurrentMenu()
    if not helper or not helper.contentPanel then return nil end
    local sideMenu = helper.contentPanel:getChildById("sideMenu")
    if not sideMenu then return nil end
    local sideMenuButtons = sideMenu:getChildById("sideMenuButtons")
    if not sideMenuButtons then return nil end

    local menuIds = {"healingMenu", "toolsMenu", "huntingMenu", "equipmentMenu", "friendMenu", "profilesMenu", "settingsMenu"}
    for _, id in ipairs(menuIds) do
        local btn = sideMenuButtons:getChildById(id)
        if btn and btn:isChecked() then
            return id
        end
    end
    return nil
end

-- Returns the current sub-tab for the given menu from helperSessionState
function IconStatsModule.getCurrentSubTab(forMenuId)
    if not helperSessionState then return nil end
    if forMenuId == "huntingMenu" then
        return helperSessionState.lastHuntingSubTab
    elseif forMenuId == "equipmentMenu" then
        return helperSessionState.lastEquipmentSubTab
    elseif forMenuId == "toolsMenu" then
        return helperSessionState.lastToolsSubTab
    elseif forMenuId == "healingMenu" then
        return helperSessionState.lastHealingSubTab
    end
    return nil
end

function IconStatsModule.openHelperMenu(menuId, subTabId)
    -- Open helper window and load specific menu/sub-tab
    -- If already visible on the same menu+subtab, close the helper (toggle behavior)
    if not (modules and modules.game_helper and modules.game_helper.toggle) then
        return
    end

    if helper and helper:isVisible() then
        -- Helper is open — detect current menu from the actual checked button
        local currentMenu = IconStatsModule.getCurrentMenu()
        local isSameMenu = (currentMenu == menuId)

        if isSameMenu and subTabId then
            -- Same main menu — check sub-tab
            local currentSubTab = IconStatsModule.getCurrentSubTab(menuId)
            if currentSubTab == subTabId then
                -- Same menu + same sub-tab → close helper
                toggle()
                return
            else
                -- Same menu, different sub-tab → switch sub-tab
                IconStatsModule.selectSubTab(menuId, subTabId)
            end
        elseif isSameMenu and not subTabId then
            -- Same main menu, no sub-tab specified → close helper
            toggle()
            return
        else
            -- Different menu → navigate to it
            loadMenu(menuId)
            if subTabId then
                scheduleEvent(function()
                    IconStatsModule.selectSubTab(menuId, subTabId)
                end, 150)
            end
        end
    else
        -- Helper not visible → open it
        toggle(menuId)
        if subTabId then
            scheduleEvent(function()
                IconStatsModule.selectSubTab(menuId, subTabId)
            end, 200)
        end
    end

    -- Focus game root panel to continue using keyboard
    scheduleEvent(function()
        if modules.game_interface and modules.game_interface.getRootPanel then
            local rootPanel = modules.game_interface.getRootPanel()
            if rootPanel then
                rootPanel:focus()
            end
        end
    end, 50)
end

function IconStatsModule.selectSubTab(menuId, subTabId)
    if not subTabId then return end
    if menuId == "huntingMenu" then
        modules.game_helper.selectHuntingSubTab(subTabId)
    elseif menuId == "equipmentMenu" then
        modules.game_helper.selectEquipmentSubTab(subTabId)
    elseif menuId == "toolsMenu" then
        modules.game_helper.selectToolsSubTab(subTabId)
    elseif menuId == "healingMenu" then
        modules.game_helper.selectHealingSubTab(subTabId)
    elseif menuId == "settingsMenu" then
        modules.game_helper.selectSettingsSubTab(subTabId)
    end
end
