-- Mehah-style HUD condition bar for Astra's native ConditionsHUD.

StatusIconBar = StatusIconBar or {}

local statusIconPanel
local activeIcons = {}
local refreshEvent
local initialized = false
local mapPanel
local stateByConditionId
local nativeVisibleHudOverrides = {}
local nativeHudMasterOverride = nil
local EMBLEM_HUD_ICON_PATH = '/images/arcs/conditions/player-state-guildwar-flag'
local HUNGRY_HUD_ICON_PATH = '/images/arcs/conditions/player-state-flags-client-02'

local config = {
    maxIcons = 8,
    topBottomSize = 10,
    baseMarginRight = 10,
    defaultArcWidth = 58,
    defaultArcHeight = 211,
    defaultArcDistance = 90,
    distanceScale = 1.2,
    mapPadding = 4,
    shrinkTime = 220,
    shrinkInterval = 30
}

local DECORATIVE_CHILD_COUNT = 2

local function safeCall(obj, method, ...)
    if obj and type(obj[method]) == 'function' then
        return obj[method](obj, ...)
    end
    return nil
end

local emblemIcons = {
    [EmblemGreen or 1] = '/images/game/emblems/emblem_green',
    [EmblemRed or 2] = '/images/game/emblems/emblem_red',
    [EmblemBlue or 3] = '/images/game/emblems/emblem_blue',
    [EmblemMember or 4] = '/images/game/emblems/emblem_member',
    [EmblemOther or 5] = '/images/game/emblems/emblem_other'
}

local emblemTooltips = {
    [EmblemGreen or 1] = 'Green Emblem',
    [EmblemRed or 2] = 'Red Emblem',
    [EmblemBlue or 3] = 'Blue Emblem',
    [EmblemMember or 4] = 'Member Emblem',
    [EmblemOther or 5] = 'Other Emblem'
}

local function getEmblemIconPath(emblem)
    if type(getEmblemImagePath) == 'function' then
        local path = getEmblemImagePath(emblem)
        if path then return path end
    end
    return emblemIcons[emblem]
end

local function getPlayerEmblem()
    return safeCall(g_game.getLocalPlayer(), 'getEmblem') or (EmblemNone or 0)
end

local function isEmblemActive(emblem)
    if emblem == nil then
        return false
    end
    if EmblemGreen ~= nil then
        return emblem == EmblemGreen
    end
    return emblem ~= (EmblemNone or 0)
end

local function getMapPanel()
    if mapPanel and not mapPanel:isDestroyed() then
        return mapPanel
    end

    if modules.game_interface and modules.game_interface.getMapPanel then
        mapPanel = modules.game_interface.getMapPanel()
    end

    return mapPanel
end

local function getOption(key, fallback)
    if m_settings and type(m_settings.getOption) == 'function' then
        local ok, value = pcall(m_settings.getOption, key)
        if ok and value ~= nil then
            return value
        end
    end

    if GameOptions and type(GameOptions.getOption) == 'function' then
        local ok, value = pcall(function()
            return GameOptions:getOption(key)
        end)
        if ok and value ~= nil then
            return value
        end
    end

    return fallback
end

local function getConditionsHUD()
    local hud = nil

    if m_settings and type(m_settings.ConditionsHUD) == 'table' then
        hud = m_settings.ConditionsHUD
    elseif modules and modules.client_settings and type(modules.client_settings.ConditionsHUD) == 'table' then
        hud = modules.client_settings.ConditionsHUD
    elseif type(ConditionsHUD) == 'table' then
        hud = ConditionsHUD
    end

    if type(hud) ~= 'table' or type(hud.specialConditionsOrder) ~= 'table' then
        return nil
    end

    return hud
end

local function getConditionId(condition)
    if condition and type(condition.getId) == 'function' then
        return tostring(condition:getId())
    end
    return condition and condition.id and tostring(condition.id) or nil
end

local function getConditionPath(condition)
    if getConditionId(condition) == 'emblem' then
        return EMBLEM_HUD_ICON_PATH
    end

    if getConditionId(condition) == 'condition_hungry' then
        return HUNGRY_HUD_ICON_PATH
    end

    if condition and type(condition.getPath) == 'function' then
        return condition:getPath()
    end
    return condition and (condition.path or condition.icon) or nil
end

local function getConditionIcon(condition)
    if condition and type(condition.getIcon) == 'function' then
        return condition:getIcon()
    end
    return condition and (condition.icon or condition.path) or nil
end

local function getConditionTooltip(condition)
    if getConditionId(condition) == 'emblem' then
        if condition and type(condition.getTooltipBar) == 'function' then
            local tooltip = condition:getTooltipBar()
            if tooltip and tooltip ~= '' then
                return tooltip
            end
        end
        return tr('You are in a guild war')
    end

    if condition and type(condition.getTooltipBar) == 'function' then
        local tooltip = condition:getTooltipBar()
        if tooltip and tooltip ~= '' then
            return tooltip
        end
    end

    if condition and type(condition.getTooltip) == 'function' then
        return condition:getTooltip() or ''
    end

    return condition and (condition.tooltipBar or condition.tooltip) or ''
end

local function buildStateIndex()
    stateByConditionId = {}

    for state, icon in pairs(Icons or {}) do
        if type(state) == 'number' and icon and icon.id then
            stateByConditionId[tostring(icon.id)] = state
        end
    end
end

local function getStateByConditionId(id)
    if not stateByConditionId then
        buildStateIndex()
    end
    return stateByConditionId[id]
end

local function isStateActive(states, state)
    return type(states) == 'number' and type(state) == 'number' and state > 0 and bit.band(states, state) ~= 0
end

local function isHudMasterEnabled()
    if nativeHudMasterOverride ~= nil then
        return nativeHudMasterOverride
    end

    local tmp = getTmpOption and getTmpOption('showInHudCheckBox')
    if tmp ~= nil then return tmp end
    return getOption('showInHudCheckBox', true) ~= false
end

local function isConditionVisibleInHud(condition)
    if not condition then
        return false
    end

    local id = getConditionId(condition)
    if id and nativeVisibleHudOverrides[id] ~= nil then
        return nativeVisibleHudOverrides[id]
    end

    if type(condition.isVisibleHud) == 'function' then
        return condition:isVisibleHud()
    end

    return condition.visibleHud ~= false
end

local function isActiveInConditionsHUD(hud, condition)
    local id = getConditionId(condition)
    if not id or type(hud.actives) ~= 'table' then
        return false
    end

    return hud.actives[id] == true or hud.actives[tonumber(id)] == true
end

local function isGoshnarCurseActive(states)
    return PlayerStates and (
        isStateActive(states, PlayerStates.CurseI) or
        isStateActive(states, PlayerStates.CurseII) or
        isStateActive(states, PlayerStates.CurseIII) or
        isStateActive(states, PlayerStates.CurseIV) or
        isStateActive(states, PlayerStates.CurseV)
    )
end

local function getSkullCondition(skull)
    if skull == SkullGreen then
        return 'skullgreen'
    elseif skull == SkullWhite then
        return 'skullwhite'
    elseif skull == SkullRed then
        return 'skullred'
    elseif skull == SkullBlack then
        return 'skullblack'
    elseif skull == SkullOrange then
        return 'skullorange'
    elseif skull == SkullYellow then
        return 'skullyellow'
    end
    return nil
end

local function isPlayerConditionActive(player, condition, states, hud)
    local id = getConditionId(condition)
    if not id then
        return false
    end

    if id == 'condition_hungry' then
        local regenerationTime = safeCall(player, 'getRegenerationTime')
        if regenerationTime ~= nil then
            return regenerationTime == 0
        end
    elseif id == 'condition_restingarea' then
        return isActiveInConditionsHUD(hud, condition)
    elseif id == 'condition_taints' then
        local taints = safeCall(player, 'getTaints')
        if taints ~= nil then
            return taints ~= 0
        end
    elseif id == 'condition_curse' then
        return isGoshnarCurseActive(states)
    elseif id == 'emblem' then
        local emblem = safeCall(player, 'getEmblem')
        return isEmblemActive(emblem)
    elseif id == getSkullCondition(safeCall(player, 'getSkull')) then
        return true
    elseif id == 'condition_new_magic_shield' and PlayerStates then
        return isStateActive(states, PlayerStates.NewMagicShield) or isStateActive(states, PlayerStates.ManaShield)
    end

    local state = getStateByConditionId(id)
    if state then
        return isStateActive(states, state)
    end

    return isActiveInConditionsHUD(hud, condition)
end

local function getActiveConditions()
    local hud = getConditionsHUD()
    if not hud or not isHudMasterEnabled() then
        return {}
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return {}
    end

    local states = safeCall(player, 'getStates') or 0
    local conditions = {}

    for _, condition in ipairs(hud.specialConditionsOrder or {}) do
        if isConditionVisibleInHud(condition) and isPlayerConditionActive(player, condition, states, hud) then
            table.insert(conditions, condition)
            if #conditions >= config.maxIcons then
                break
            end
        end
    end

    return conditions
end

local function removeRefreshEvent()
    if refreshEvent then
        removeEvent(refreshEvent)
        refreshEvent = nil
    end
end

local function scheduleRefresh(delay)
    removeRefreshEvent()
    refreshEvent = scheduleEvent(function()
        refreshEvent = nil
        StatusIconBar.refreshIcons()
    end, delay or 1)
end

local function cancelWidgetEvent(widget, eventName)
    if widget and widget[eventName] then
        removeEvent(widget[eventName])
        widget[eventName] = nil
    end
end

local function setWidgetIconOpacity(widget, opacity)
    local icon = widget and widget:getChildById('icon')
    if icon then
        icon:setOpacity(opacity)
    end
end

local function applyIconWidgetStyle(container, condition)
    local icon = container and container:getChildById('icon')
    if not icon then
        return
    end

    icon:setImageSource(getConditionPath(condition) or getConditionIcon(condition) or '/images/game/states/player-state-flags')
end

local function removeIconWidget(widget)
    if not widget or not statusIconPanel or not statusIconPanel:hasChild(widget) then
        return
    end

    cancelWidgetEvent(widget, 'shrinkInEvent')
    cancelWidgetEvent(widget, 'shrinkOutEvent')

    if widget.conditionId then
        activeIcons[widget.conditionId] = nil
    end

    statusIconPanel:removeChild(widget)
    widget:destroy()

    if statusIconPanel:getChildCount() <= DECORATIVE_CHILD_COUNT then
        statusIconPanel:setVisible(false)
    end

    StatusIconBar.updateWidgetHeight()
end

local function clearIcons()
    local widgets = {}
    for _, container in pairs(activeIcons) do
        table.insert(widgets, container)
    end

    activeIcons = {}

    for _, container in ipairs(widgets) do
        cancelWidgetEvent(container, 'shrinkInEvent')
        cancelWidgetEvent(container, 'shrinkOutEvent')
        if statusIconPanel and statusIconPanel:hasChild(container) then
            container:destroy()
        end
    end
end

local function getArcMetrics()
    local healthCircleModule = modules.game_healthcircle
    if healthCircleModule and type(healthCircleModule.getArcMetrics) == 'function' then
        local metrics = healthCircleModule.getArcMetrics()
        if metrics and metrics.width and metrics.height and metrics.width > 0 and metrics.height > 0 then
            return metrics
        end
    end

    local style = tonumber(getOption('sizeBox', 1)) or 1
    local sizes = {
        [1] = { width = 35, height = 126 },
        [2] = { width = 58, height = 211 },
        [3] = { width = 79, height = 292 }
    }

    if style == 0 then
        return { width = config.defaultArcWidth, height = config.defaultArcHeight }
    end

    return sizes[style] or { width = config.defaultArcWidth, height = config.defaultArcHeight }
end

local function getArcAnchor()
    local map = getMapPanel()
    if not map then
        return nil
    end

    local arc = getArcMetrics()
    local distanceOption = tonumber(getOption('distanceArc', 15)) or 15
    local arcDistance = config.defaultArcDistance + (distanceOption * config.distanceScale)
    local centerX = map:getX() + (map:getWidth() / 2)
    local centerY = map:getY() + (map:getHeight() / 2)

    return {
        x = centerX - arcDistance - arc.width,
        y = centerY - (arc.height / 2),
        height = arc.height,
        map = map
    }
end

function StatusIconBar.updatePosition()
    if not statusIconPanel then
        return
    end

    local anchor = getArcAnchor()
    if not anchor then
        return
    end

    local panelWidth = statusIconPanel:getWidth()
    local panelHeight = statusIconPanel:getHeight()
    local x = anchor.x - panelWidth - config.baseMarginRight
    local y = anchor.y + (anchor.height / 2) - (panelHeight / 2)

    local minX = anchor.map:getX() + config.mapPadding
    local maxX = anchor.map:getX() + anchor.map:getWidth() - panelWidth - config.mapPadding
    local minY = anchor.map:getY() + config.mapPadding
    local maxY = anchor.map:getY() + anchor.map:getHeight() - panelHeight - config.mapPadding

    statusIconPanel:setX(math.floor(math.max(minX, math.min(x, maxX))))
    statusIconPanel:setY(math.floor(math.max(minY, math.min(y, maxY))))
end

function StatusIconBar.updateWidgetHeight()
    if not statusIconPanel then
        return
    end

    local height = 0
    local childCount = statusIconPanel:getChildCount()
    for index = 1, childCount do
        local child = statusIconPanel:getChildByIndex(index)
        if child then
            height = height + child:getHeight()
            if index > 1 then
                height = height + 1
            end
        end
    end

    statusIconPanel:setHeight(height)
    StatusIconBar.updatePosition()
end

function StatusIconBar.shrinkIn(widget, time)
    if not widget or not statusIconPanel or not statusIconPanel:hasChild(widget) then
        return
    end

    cancelWidgetEvent(widget, 'shrinkInEvent')
    cancelWidgetEvent(widget, 'shrinkOutEvent')

    widget.realHeight = widget.realHeight or widget:getHeight()

    local progress = math.min(1, math.max(0, time / config.shrinkTime))
    local height = math.max(1, math.floor(widget.realHeight * progress))
    widget:setHeight(height)
    setWidgetIconOpacity(widget, progress)

    if progress >= 1 then
        widget:setHeight(widget.realHeight)
        setWidgetIconOpacity(widget, 1.0)
        StatusIconBar.updateWidgetHeight()
        return
    end

    widget.shrinkInEvent = scheduleEvent(function()
        StatusIconBar.shrinkIn(widget, time + config.shrinkInterval)
    end, config.shrinkInterval)

    StatusIconBar.updateWidgetHeight()
end

function StatusIconBar.shrinkOut(widget, time)
    if not widget or not statusIconPanel or not statusIconPanel:hasChild(widget) then
        return
    end

    cancelWidgetEvent(widget, 'shrinkInEvent')
    cancelWidgetEvent(widget, 'shrinkOutEvent')

    widget.realHeight = widget.realHeight or widget:getHeight()

    local opacity = time / config.shrinkTime
    local height = math.floor(widget.realHeight * math.min((time / config.shrinkTime) * 1.5, 1))
    if opacity <= 0 or height <= 0 then
        removeIconWidget(widget)
        return
    end

    setWidgetIconOpacity(widget, opacity)
    widget:setHeight(height)
    widget.shrinkOutEvent = scheduleEvent(function()
        StatusIconBar.shrinkOut(widget, time - config.shrinkInterval)
    end, config.shrinkInterval)

    StatusIconBar.updateWidgetHeight()
end

function StatusIconBar.refreshIcons()
    if not statusIconPanel then
        return
    end

    if not g_game.isOnline() then
        StatusIconBar.clearAll()
        return
    end

    local activeConditions = getActiveConditions()
    local activeById = {}

    for _, condition in ipairs(activeConditions) do
        local id = getConditionId(condition)
        if id then
            activeById[id] = condition
        end
    end

    local removeIds = {}
    for id, container in pairs(activeIcons) do
        if not activeById[id] then
            table.insert(removeIds, id)
        elseif container.shrinkOutEvent then
            cancelWidgetEvent(container, 'shrinkOutEvent')
            local currentHeight = container:getHeight()
            local currentTime = math.floor((currentHeight / math.max(container.realHeight or 1, 1)) * config.shrinkTime)
            StatusIconBar.shrinkIn(container, currentTime)
        end
    end

    for _, id in ipairs(removeIds) do
        local container = activeIcons[id]
        if container and not container.shrinkOutEvent and statusIconPanel:hasChild(container) then
            StatusIconBar.shrinkOut(container, config.shrinkTime)
        end
    end

    for _, condition in ipairs(activeConditions) do
        local id = getConditionId(condition)
        if id then
            local container = activeIcons[id]
            if not container then
                container = g_ui.createWidget('StatusIconContainer', statusIconPanel)
                container:setId('stateicon_' .. id)
                container.conditionId = id
                container.realHeight = container:getHeight()
                container:setHeight(1)
                setWidgetIconOpacity(container, 0.0)
                activeIcons[id] = container
                StatusIconBar.shrinkIn(container, 0)
            else
                container.realHeight = container.realHeight or container:getHeight()
            end

            container:setTooltip(getConditionTooltip(condition) or '')
            applyIconWidgetStyle(container, condition)
        end
    end

    for index, condition in ipairs(activeConditions) do
        local id = getConditionId(condition)
        local container = id and activeIcons[id]
        if container then
            statusIconPanel:moveChildToIndex(container, index + 1)
        end
    end

    statusIconPanel:setVisible(statusIconPanel:getChildCount() > DECORATIVE_CHILD_COUNT)
    StatusIconBar.updateWidgetHeight()
end

function StatusIconBar.clearAll()
    clearIcons()

    if statusIconPanel then
        statusIconPanel:setVisible(false)
        StatusIconBar.updateWidgetHeight()
    end
end

function StatusIconBar.onConditionEvent()
    scheduleRefresh(10)
end

function StatusIconBar.onGameStart()
    scheduleRefresh(150)
end

function StatusIconBar.onGameEnd()
    StatusIconBar.clearAll()
end

function StatusIconBar.init()
    if initialized then
        return
    end

    g_ui.importStyle('statusiconbar')
    buildStateIndex()

    local map = getMapPanel()
    if not map then
        return
    end

    statusIconPanel = g_ui.createWidget('StatusIconPanel', map)
    g_ui.createWidget('StatusIconTop', statusIconPanel)
    g_ui.createWidget('StatusIconBottom', statusIconPanel)
    statusIconPanel:setVisible(false)
    statusIconPanel:setHeight(config.topBottomSize * 2 + 1)
    StatusIconBar.updatePosition()

    connect(map, {
        onGeometryChange = StatusIconBar.updatePosition,
        onVisibleDimensionChange = StatusIconBar.updatePosition
    })

    connect(LocalPlayer, {
        onStatesChange = StatusIconBar.onConditionEvent,
        onSkullChange = StatusIconBar.onConditionEvent,
        onTaintsChange = StatusIconBar.onConditionEvent,
        onRegenerationChange = StatusIconBar.onConditionEvent
    })

    connect(Creature, {
        onEmblemChange = StatusIconBar.onConditionEvent
    })

    connect(g_game, {
        onGameStart = StatusIconBar.onGameStart,
        onGameEnd = StatusIconBar.onGameEnd,
        onRestingAreaState = StatusIconBar.onConditionEvent
    })

    initialized = true

    if g_game.isOnline() then
        StatusIconBar.onGameStart()
    end
end

function StatusIconBar.terminate()
    if not initialized then
        return
    end

    initialized = false
    removeRefreshEvent()

    local map = getMapPanel()
    if map then
        disconnect(map, {
            onGeometryChange = StatusIconBar.updatePosition,
            onVisibleDimensionChange = StatusIconBar.updatePosition
        })
    end

    disconnect(LocalPlayer, {
        onStatesChange = StatusIconBar.onConditionEvent,
        onSkullChange = StatusIconBar.onConditionEvent,
        onTaintsChange = StatusIconBar.onConditionEvent,
        onRegenerationChange = StatusIconBar.onConditionEvent
    })

    disconnect(Creature, {
        onEmblemChange = StatusIconBar.onConditionEvent
    })

    disconnect(g_game, {
        onGameStart = StatusIconBar.onGameStart,
        onGameEnd = StatusIconBar.onGameEnd,
        onRestingAreaState = StatusIconBar.onConditionEvent
    })

    StatusIconBar.clearAll()

    if statusIconPanel then
        statusIconPanel:destroy()
        statusIconPanel = nil
    end
end

function StatusIconBar.getPanel()
    return statusIconPanel
end

function StatusIconBar.isVisible()
    return statusIconPanel and statusIconPanel:isVisible()
end

function StatusIconBar.setNativeHudConditionVisible(conditionId, visible)
    if conditionId ~= nil then
        nativeVisibleHudOverrides[tostring(conditionId)] = visible ~= false
    end
    StatusIconBar.refreshIcons()
end

function StatusIconBar.setNativeHudMasterEnabled(visible)
    nativeHudMasterOverride = visible ~= false
    StatusIconBar.refreshIcons()
end

function refreshStatusIcons()
    StatusIconBar.refreshIcons()
end

function setNativeHudConditionVisible(conditionId, visible)
    StatusIconBar.setNativeHudConditionVisible(conditionId, visible)
end

function setNativeHudMasterEnabled(visible)
    StatusIconBar.setNativeHudMasterEnabled(visible)
end
