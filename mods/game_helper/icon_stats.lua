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

-- Apply the active (green) / inactive (red) border in a way that SURVIVES hover.
-- When a UIItem is hovered the engine re-applies its .otui style
-- (uimanager.cpp: updateState(HoverState) -> updateStyle), which drops the
-- border. onHoverChange fires AFTER that re-apply (uimanager.cpp 271-272), so the
-- direct setBorderColor in the guard below always wins. $on still drives the
-- normal (non-hover) display; the guard only re-asserts on hover transitions.
local ICON_ACTIVE_BORDER = "#4dd62a"
local ICON_INACTIVE_BORDER = "#f75f5f"
local ICON_BORDER_WIDTH = 1

local function applyIconState(icon, isActive)
    if not icon then return end
    icon._iconActive = isActive
    icon:setOn(isActive)
    if not icon._borderHoverGuard then
        icon._borderHoverGuard = true
        -- Assigning icon.onHoverChange SHADOWS the class-level handler that
        -- g_tooltip connects to UIWidget, so this guard is the ONLY thing that
        -- runs on hover for sprite icons. Drive the tooltip ourselves from a
        -- PRIVATE field (`_iconTooltip`): gamelib's UIItem:onItemChange() keeps
        -- wiping the native `.tooltip` on every item refresh, so relying on it
        -- (via g_tooltip.onWidgetHoverChange, which reads widget.tooltip) fails.
        icon.onHoverChange = function(self, hovered)
            if self._iconActive ~= nil then
                self:setBorderColor(self._iconActive and ICON_ACTIVE_BORDER or ICON_INACTIVE_BORDER)
                self:setBorderWidth(ICON_BORDER_WIDTH)
            end
            if not g_tooltip then return end
            local pressed = g_mouse and g_mouse.isPressed and g_mouse.isPressed()
            if hovered and self._iconTooltip and self._iconTooltip ~= "" and not pressed then
                g_tooltip.displayText(self._iconTooltip)
            else
                g_tooltip.hide()
            end
        end
    end
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
        itemId = 23375,  -- Supreme Health Potion = self-healing
        name = "Healing"
    },
    healFriendIcon = {
        itemId = 3160,  -- Ultimate Healing Rune (UH) = healing cast on an ally
        name = "Heal Friend"
    },
    equipmentIcon = {
        itemId = 23533,  -- Ring of Red Plasma = equipment swap
        name = "Equipment Swap"
    },
    tankModeIcon = {
        itemId = 3081,  -- Stone Skin Amulet = tank/defense
        name = "Tank Mode"
    },
    targetingIcon = {
        itemId = 3288,  -- Magic Sword = auto-target / melee combat
        name = "Targeting"
    },
    shooterIcon = {
        itemId = 3161,  -- Avalanche Rune = magic shooter
        name = "Shooter"
    },
    cavebotIcon = {
        text = "CB",  -- placeholder text until a good sprite is chosen
        name = "Cavebot"
    },
    timerIcon = {
        itemId = 3053,  -- Time Ring = timer
        name = "Timer"
    },
    helperIcon = {
        name = "Helper"  -- ON/OFF toggle, not an item
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

-- Which helper tool each icon belongs to, shown in the tooltip so the player
-- knows where the feature lives in the Helper window (menu > sub-tab).
IconStatsModule.iconToolInfo = {
    healingIcon    = { title = "Healing",       tool = "Healing" },
    healFriendIcon = { title = "Heal Friend",   tool = "Healing > Friends" },
    equipmentIcon  = { title = "Equipment Swap", tool = "Equipment" },
    tankModeIcon   = { title = "Tank Mode",      tool = "Equipment > Tank Mode" },
    targetingIcon  = { title = "Targeting",      tool = "Hunting > Targeting" },
    shooterIcon    = { title = "Shooter",        tool = "Hunting > Shooter" },
    cavebotIcon    = { title = "Cavebot",        tool = "Hunting > Cavebot" },
    timerIcon      = { title = "Timer",          tool = "Tools > Timer" },
    helperIcon     = { title = "Helper",         tool = "Toggle the bot on/off" },
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

-- Builds the full tooltip for an icon: tool name, where it lives, and (for
-- modules that own presets) the currently selected preset.
function IconStatsModule.buildIconTooltip(iconId)
    local info = IconStatsModule.iconToolInfo[iconId]
    local title = info and info.title or (IconStatsModule.iconConfig[iconId] and IconStatsModule.iconConfig[iconId].name) or "Helper"
    local lines = { title }
    if info and info.tool then
        table.insert(lines, "Tool: " .. info.tool)
    end
    local presetModule = presetModuleByIconId[iconId]
    if presetModule then
        table.insert(lines, "Preset: " .. getCurrentModulePresetName(presetModule))
        table.insert(lines, "Click the arrow to change preset")
    end
    return table.concat(lines, "\n")
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

    local tooltipText = IconStatsModule.buildIconTooltip(iconId)
    icon._iconTooltip = tooltipText
    icon:setTooltip(tooltipText)

    -- Update the active-preset badge: the currently selected preset number.
    local badge = icon:getChildById('presetBadge')
    if badge then
        local meta = modulePresetMeta and modulePresetMeta[moduleType]
        local selectedName = meta and tostring(helperConfig[meta.selectedKey] or getModulePresetSlotName(1))
        local idx = selectedName and getModulePresetSlotIndex and getModulePresetSlotIndex(selectedName)
        if idx then
            badge:setText(tostring(idx))
            badge:setVisible(true)
        else
            badge:setVisible(false)
        end
    end

    -- If the mouse is already over the icon, refresh the shown tooltip now.
    -- Use displayText (not onWidgetHoverChange) so it doesn't depend on the
    -- native .tooltip, which UIItem keeps wiping.
    if icon.isHovered and icon:isHovered() and g_tooltip and g_tooltip.displayText then
        g_tooltip.displayText(tooltipText)
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

    -- Our move can slip the bar above a visible tooltip; keep the tooltip on top.
    local tip = root:getChildById('toolTip')
    if tip and tip:isVisible() then
        tip:raise()
    end
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
        -- A moved/resized bar leaves any open preset flyout stranded; close it.
        IconStatsModule.closePresetFlyout()
        -- Arrows are root children (so clicks outside the bar's rect still land),
        -- so they must be re-pinned as the bar moves/resizes.
        if IconStatsModule.layoutPresetArrows then
            IconStatsModule.layoutPresetArrows()
        end
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

    -- Default UIWindow raises itself to the very TOP on focus, which buries the
    -- tooltip behind the bar the moment the user clicks an icon. Replace it with
    -- a controlled re-assert (stay just above the game panel, re-raise the
    -- tooltip). The lost-focus branch mirrors UIWindow:onFocusChange so the game
    -- window reclaims focus when the bar hides (keeps Escape/movement working).
    IconStatsModule.window.onFocusChange = function(self, focused)
        if focused then
            IconStatsModule.ensureOnTop()
            local root = g_ui.getRootWidget()
            local tip = root and root:getChildById('toolTip')
            if tip then tip:raise() end
            return
        end
        if not self:isDestroyed() and self:isExplicitlyVisible() then
            return
        end
        if not (g_game and g_game.isOnline and g_game.isOnline()) then
            return
        end
        local root = g_ui.getRootWidget()
        local gameWindow = root and root:getChildById('gameRootPanel')
        if gameWindow and gameWindow:isVisible() then
            gameWindow:focus()
        end
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
            if config.text then
                -- Text slot (e.g. cavebot "CB"): a toggle button, no sprite.
                if icon.setText then icon:setText(config.text) end
            elseif iconId ~= "helperIcon" and config.itemId and icon.setItemId then
                icon:setItemId(config.itemId)
                -- CRITICAL: gamelib's UIItem:onItemChange() resets the tooltip to
                -- the item's own (nil for our virtual items) on every item refresh,
                -- wiping our custom tooltip. Override it to re-apply ours instead.
                icon.onItemChange = function(self)
                    local t = IconStatsModule.buildIconTooltip(iconId)
                    self._iconTooltip = t
                    self:setTooltip(t)
                end
            end
            -- _iconTooltip is our own copy that the hover guard reads (the native
            -- .tooltip gets wiped by UIItem:onItemChange); set both.
            local tip = IconStatsModule.buildIconTooltip(iconId)
            icon._iconTooltip = tip
            icon:setTooltip(tip)
        end
    end

    -- Ensure the per-icon preset arrows (shooter/healing/equipment/targeting)
    -- exist and are pinned to their icons for the current orientation.
    IconStatsModule.ensurePresetArrows()
    IconStatsModule.layoutPresetArrows()
end

-- ===================================================================
-- PRESET ARROWS + PRESET PICKER FLYOUT
-- Each module icon that owns presets (shooter/healing/equipment/targeting)
-- gets a small native arrow pinned to its edge. Clicking it opens a flyout
-- with a grid of squares (one per preset slot); the active preset is marked
-- green. The flyout opens on whichever side of the bar has room on screen.
-- ===================================================================

IconStatsModule._presetArrows = IconStatsModule._presetArrows or {}
IconStatsModule._presetFlyout = nil
IconStatsModule._presetFlyoutOverlay = nil
IconStatsModule._presetFlyoutModule = nil

local PRESET_GRID_COLS = 5
local PRESET_OPTION_SIZE = 34
local PRESET_OPTION_SPACING = 3
local PRESET_FLYOUT_PAD_TOP = 20
local PRESET_FLYOUT_PAD_SIDE = 7
local PRESET_FLYOUT_PAD_BOTTOM = 7

local function presetFlyoutSize(count)
    local cols = math.min(PRESET_GRID_COLS, math.max(1, count))
    local rows = math.max(1, math.ceil(count / PRESET_GRID_COLS))
    local w = PRESET_FLYOUT_PAD_SIDE * 2 + cols * PRESET_OPTION_SIZE + (cols - 1) * PRESET_OPTION_SPACING
    local h = PRESET_FLYOUT_PAD_TOP + PRESET_FLYOUT_PAD_BOTTOM + rows * PRESET_OPTION_SIZE + (rows - 1) * PRESET_OPTION_SPACING
    return w, h
end

-- Returns the side the flyout (and, for a vertical bar, the arrows) should use:
-- vertical bar -> "right"/"left"; horizontal bar -> "down"/"up". Chosen by how
-- much room the full flyout needs vs. what is free around the bar on screen.
function IconStatsModule.getPresetFlyoutSide()
    local window = IconStatsModule.window
    local root = g_ui.getRootWidget()
    local horizontal = helperConfig and helperConfig.iconStats and helperConfig.iconStats.horizontal
    if not window or not root then
        return horizontal and "down" or "right"
    end

    local pos = window:getPosition()
    local w, h = presetFlyoutSize(modulePresetSlotCount or 10)
    local screenW = root:getWidth()
    local screenH = root:getHeight()

    if horizontal then
        local spaceBelow = screenH - (pos.y + window:getHeight())
        if spaceBelow >= h then return "down" end
        if pos.y >= h then return "up" end
        return "down"
    end

    local spaceRight = screenW - (pos.x + window:getWidth())
    if spaceRight >= w then return "right" end
    if pos.x >= w then return "left" end
    return "right"
end

-- Arrows live on the ROOT widget, NOT on the bar. A child that pokes past its
-- parent's rect never receives mouse events (uiwidget.cpp recursiveGetChildByPos
-- bails on !containsPaddingPoint), so an arrow parented to the bar and sitting
-- outside its frame would be unclickable. Rooted + absolutely positioned fixes
-- clicks/hover/cursor; layoutPresetArrows keeps them glued to their icons.
function IconStatsModule.ensurePresetArrows()
    local root = g_ui.getRootWidget()
    if not root then return end
    IconStatsModule._presetArrows = IconStatsModule._presetArrows or {}
    for iconId, moduleType in pairs(presetModuleByIconId) do
        local arrow = IconStatsModule._presetArrows[iconId]
        if not arrow or arrow:isDestroyed() then
            arrow = g_ui.createWidget('IconStatsPresetArrow', root)
            arrow:setId(iconId .. 'PresetArrow')
            arrow.moduleType = moduleType
            arrow.iconId = iconId
            arrow.onClick = function(self)
                IconStatsModule.togglePresetFlyout(self.moduleType, getIcon(self.iconId))
            end
            arrow:hide()
            IconStatsModule._presetArrows[iconId] = arrow
        end
    end
end

function IconStatsModule.hidePresetArrows()
    if not IconStatsModule._presetArrows then return end
    for _, arrow in pairs(IconStatsModule._presetArrows) do
        if arrow and not arrow:isDestroyed() then
            arrow:hide()
        end
    end
end

function IconStatsModule.destroyPresetArrows()
    if IconStatsModule._presetArrows then
        for _, arrow in pairs(IconStatsModule._presetArrows) do
            if arrow and not arrow:isDestroyed() then
                arrow:destroy()
            end
        end
    end
    IconStatsModule._presetArrows = {}
end

-- Positions each preset arrow (a root child) just outside its icon, on the side
-- the flyout will open. Vertical bar only. Called after helper.lua lays out the
-- bar's icons, on drag, and on show/hide.
function IconStatsModule.layoutPresetArrows()
    local window = IconStatsModule.window
    if not window then return end
    if not IconStatsModule._presetArrows then
        IconStatsModule.ensurePresetArrows()
    end

    local barVisible = window:isVisible()
    local side = IconStatsModule.getPresetFlyoutSide() -- "right"/"left"
    local gap = 3
    local arrowW, arrowH = 16, 22

    for iconId, arrow in pairs(IconStatsModule._presetArrows) do
        local icon = getIcon(iconId)
        if not barVisible or not icon or not icon:isVisible() then
            arrow:hide()
        else
            local glyph = arrow:getChildById('glyph')
            arrow:setSize({ width = arrowW, height = arrowH })
            if glyph then
                glyph:setSize({ width = 12, height = 21 })
                glyph:setImageSource('/images/ui/arrow_horizontal')
                glyph:setImageClip(side == 'left' and '0 0 12 21' or '12 0 12 21')
            end

            local ipos = icon:getPosition()
            local ay = ipos.y + math.floor((icon:getHeight() - arrowH) / 2)
            local ax
            if side == 'left' then
                ax = ipos.x - gap - arrowW
            else
                ax = ipos.x + icon:getWidth() + gap
            end
            arrow:setPosition({ x = ax, y = ay })
            arrow:show()
            arrow:raise()
        end
    end
end

function IconStatsModule.closePresetFlyout()
    if IconStatsModule._presetFlyout then
        if not IconStatsModule._presetFlyout:isDestroyed() then
            IconStatsModule._presetFlyout:destroy()
        end
        IconStatsModule._presetFlyout = nil
    end
    if IconStatsModule._presetFlyoutOverlay then
        if not IconStatsModule._presetFlyoutOverlay:isDestroyed() then
            IconStatsModule._presetFlyoutOverlay:destroy()
        end
        IconStatsModule._presetFlyoutOverlay = nil
    end
    IconStatsModule._presetFlyoutModule = nil
end

function IconStatsModule.togglePresetFlyout(moduleType, icon)
    if IconStatsModule._presetFlyout and not IconStatsModule._presetFlyout:isDestroyed()
        and IconStatsModule._presetFlyoutModule == moduleType then
        IconStatsModule.closePresetFlyout()
        return true
    end
    IconStatsModule.buildPresetFlyout(moduleType, icon)
    return true
end

function IconStatsModule.buildPresetFlyout(moduleType, icon)
    IconStatsModule.closePresetFlyout()

    local meta = modulePresetMeta and modulePresetMeta[moduleType]
    if not meta then return end
    icon = icon or getIcon(modulePresetIconIds[moduleType])
    if not icon then return end

    local root = g_ui.getRootWidget()
    if not root or not IconStatsModule.window then return end

    if ensureModulePresetConfig then
        ensureModulePresetConfig(moduleType)
    end

    local names = (getSortedModulePresetNames and getSortedModulePresetNames(moduleType)) or {}
    local count = #names
    if count == 0 then return end

    local horizontal = helperConfig and helperConfig.iconStats and helperConfig.iconStats.horizontal
    local side = IconStatsModule.getPresetFlyoutSide()

    -- Full-screen transparent catcher that closes the flyout on any outside click.
    local overlay = g_ui.createWidget('UIWidget', root)
    overlay:setId('iconStatsPresetOverlay')
    overlay:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    overlay:addAnchor(AnchorTop, 'parent', AnchorTop)
    overlay:addAnchor(AnchorRight, 'parent', AnchorRight)
    overlay:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    overlay:setPhantom(false)
    overlay.onMousePress = function()
        scheduleEvent(function() IconStatsModule.closePresetFlyout() end, 1)
        return true
    end
    IconStatsModule._presetFlyoutOverlay = overlay

    local flyout = g_ui.createWidget('IconStatsPresetFlyout', root)
    flyout:setId('iconStatsPresetFlyout')
    IconStatsModule._presetFlyout = flyout
    IconStatsModule._presetFlyoutModule = moduleType

    local w, h = presetFlyoutSize(count)
    flyout:setSize({ width = w, height = h })

    -- Title Label, pinned inside the header strip (see the style).
    local titleLabel = flyout:getChildById('flyoutTitle')
    if titleLabel then
        titleLabel:setText((modulePresetTitles[moduleType] or "Preset") .. " presets")
    end

    local selectedName = tostring(helperConfig[meta.selectedKey] or getModulePresetSlotName(1))

    for i = 1, count do
        local slotName = names[i]
        local slotIndex = (getModulePresetSlotIndex and getModulePresetSlotIndex(slotName)) or i
        local option = g_ui.createWidget('IconStatsPresetOption', flyout)
        option:setId('presetOption' .. i)

        local col = (i - 1) % PRESET_GRID_COLS
        local row = math.floor((i - 1) / PRESET_GRID_COLS)
        option:addAnchor(AnchorTop, 'parent', AnchorTop)
        option:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        -- Flyout has no padding; offset the grid past the header strip + side border.
        option:setMarginTop(PRESET_FLYOUT_PAD_TOP + row * (PRESET_OPTION_SIZE + PRESET_OPTION_SPACING))
        option:setMarginLeft(PRESET_FLYOUT_PAD_SIDE + col * (PRESET_OPTION_SIZE + PRESET_OPTION_SPACING))

        local label = option:getChildById('label')
        if label then
            label:setText(tostring(slotIndex or i))
        end
        local uiName = (getModulePresetUiName and getModulePresetUiName(moduleType, slotName)) or slotName
        option:setTooltip(uiName)

        -- Mark the active preset with the same green as the bar's active icons.
        -- setOn drives the $on border, which survives hover re-apply.
        option:setOn(slotName == selectedName)

        option.slotIndex = slotIndex or i
        option.moduleType = moduleType
        option.onClick = function(self)
            IconStatsModule.onPresetOptionClick(self.moduleType, self.slotIndex)
        end
    end

    -- Place the flyout beside the icon on the chosen side, then clamp on-screen.
    local ipos = icon:getPosition()
    local barPos = IconStatsModule.window:getPosition()
    local fx, fy
    if horizontal then
        if side == 'up' then
            fy = barPos.y - h - 2
        else
            fy = barPos.y + IconStatsModule.window:getHeight() + 2
        end
        fx = ipos.x + math.floor(icon:getWidth() / 2) - math.floor(w / 2)
    else
        if side == 'left' then
            fx = barPos.x - w - 2
        else
            fx = barPos.x + IconStatsModule.window:getWidth() + 2
        end
        fy = ipos.y + math.floor(icon:getHeight() / 2) - math.floor(h / 2)
    end

    local screenW = root:getWidth()
    local screenH = root:getHeight()
    if fx < 2 then fx = 2 end
    if fy < 2 then fy = 2 end
    if fx + w > screenW - 2 then fx = screenW - w - 2 end
    if fy + h > screenH - 2 then fy = screenH - h - 2 end

    flyout:setPosition({ x = fx, y = fy })
    flyout:raise()
end

function IconStatsModule.onPresetOptionClick(moduleType, slotIndex)
    if activateModulePresetBySlot then
        activateModulePresetBySlot(moduleType, slotIndex)
    end
    if IconStatsModule.updateModulePresetTooltip then
        IconStatsModule.updateModulePresetTooltip(moduleType)
    end
    -- Defer destroying the flyout: we're inside a child option's onClick.
    scheduleEvent(function() IconStatsModule.closePresetFlyout() end, 1)
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
        applyIconState(icon, isActive)
    end
end

function IconStatsModule.updateHealFriendIcon(isActive)
    if not IconStatsModule.window then return end

    local icon = getIcon("healFriendIcon")
    if icon then
        applyIconState(icon, isActive)
    end
end

function IconStatsModule.updateEquipmentIcon(isActive)
    if not IconStatsModule.window then return end

    local icon = getIcon("equipmentIcon")
    if icon then
        applyIconState(icon, isActive)
    end
end

function IconStatsModule.updateTankModeIcon(isActive)
    if not IconStatsModule.window then return end

    local icon = getIcon("tankModeIcon")
    if icon then
        applyIconState(icon, isActive)
    end
end

function IconStatsModule.updateTargetingIcon(isActive)
    if not IconStatsModule.window then return end

    local icon = getIcon("targetingIcon")
    if icon then
        applyIconState(icon, isActive)
    end
end

function IconStatsModule.updateShooterTooltip()
    IconStatsModule.updateModulePresetTooltip("shooter")
end

function IconStatsModule.updateShooterIcon(isActive)
    if not IconStatsModule.window then return end

    local icon = getIcon("shooterIcon")
    if icon then
        applyIconState(icon, isActive)
        -- Atualizar tooltip com o preset atual
        IconStatsModule.updateShooterTooltip()
    end
end

function IconStatsModule.updateCavebotIcon(isActive)
    if not IconStatsModule.window then return end

    local icon = getIcon("cavebotIcon")
    if icon then
        -- cavebot is now a text toggle ("CB"); $on drives green/red like the
        -- master toggle. The "CB" text set in setupIcons survives setOn.
        icon:setOn(isActive)
    end
end

function IconStatsModule.updateTimerIcon(isActive)
    if not IconStatsModule.window then return end

    local icon = getIcon("timerIcon")
    if icon then
        applyIconState(icon, isActive)
    end
end

function IconStatsModule.updateHelperIcon(isActive)
    if not IconStatsModule.window then return end

    local icon = getIcon("helperIcon")
    if icon then
        -- Master toggle: ON (green) / OFF (red). $on drives the color; the text
        -- is set here (never in the style) so hover re-apply can't wipe it.
        icon:setOn(isActive)
        if icon.setText then
            icon:setText(isActive and "ON" or "OFF")
        end
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
        -- Re-assign the item sprites now that we are in-game: setupIcons() first
        -- runs in init() at the LOGIN SCREEN (game_helper @onLoad), before
        -- game_things calls g_things.loadAppearances on game-connect. Item sprites
        -- resolve their ThingType live at draw time, but re-running here guarantees
        -- the icons display their item images once the assets are present.
        IconStatsModule.setupIcons()
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

    IconStatsModule.closePresetFlyout()
    IconStatsModule.hidePresetArrows()

    if IconStatsModule.window then
        IconStatsModule.window:hide()
    end
end

function IconStatsModule.terminate()
    -- Stop watchdog
    IconStatsModule.stopVisibilityWatchdog()

    IconStatsModule.closePresetFlyout()

    if IconStatsModule.window then
        IconStatsModule.window:destroy()
        IconStatsModule.window = nil
    end

    -- Clear widget caches (widgets are destroyed with the window)
    IconStatsModule._iconCache = {}
    IconStatsModule._msgLabelCache = {}
    -- Preset arrows are root children, so destroy them explicitly.
    IconStatsModule.destroyPresetArrows()
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

    IconStatsModule.closePresetFlyout()

    if IconStatsModule.window then
        wasVisible = IconStatsModule.window:isVisible()
        lastPos = IconStatsModule.window:getPosition()
        IconStatsModule.window:destroy()
        IconStatsModule.window = nil
    end

    -- Clear widget caches before rebuilding (old refs are now invalid)
    IconStatsModule._iconCache = {}
    IconStatsModule._msgLabelCache = {}
    -- Preset arrows are root children; destroy them so init() recreates fresh ones.
    IconStatsModule.destroyPresetArrows()

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
    IconStatsModule.closePresetFlyout()
    IconStatsModule.hidePresetArrows()
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
