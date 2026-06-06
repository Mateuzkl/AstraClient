-- Status Icon Bar
-- Mehah-like HUD condition bar, adapted to Astra's ConditionsHUD data.

StatusIconBar = StatusIconBar or {}

local statusIconPanel
local activeIcons = {}
local refreshEvent
local initialized = false
local stateByConditionId

local config = {
    maxIcons = 8,
    topBottomSize = 10,
    baseMarginRight = 10,
    fallbackArcDistance = 90,
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

local function getConditionsHUD()
    if type(ConditionsHUD) ~= 'table' or type(ConditionsHUD.specialConditionsOrder) ~= 'table' then
        return nil
    end
    return ConditionsHUD
end

local function getConditionId(condition)
    if condition and type(condition.getId) == 'function' then
        return tostring(condition:getId())
    end
    return condition and condition.id and tostring(condition.id) or nil
end

local function getConditionPath(condition)
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
    if m_settings and type(m_settings.getOption) == 'function' then
        local ok, value = pcall(m_settings.getOption, 'showInHudCheckBox')
        if ok and type(value) == 'boolean' then
            return value
        end
    end

    if GameOptions and type(GameOptions.getOption) == 'function' then
        local ok, value = pcall(function()
            return GameOptions:getOption('showInHudCheckBox')
        end)
        if ok and type(value) == 'boolean' then
            return value
        end
    end

    return true
end

local function isConditionVisibleInHud(condition)
    if not condition then
        return false
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
        local resting = safeCall(player, 'getRestingAreaProtection')
        if resting ~= nil then
            return resting
        end
    elseif id == 'condition_taints' then
        local taints = safeCall(player, 'getTaints')
        if taints ~= nil then
            return taints ~= 0
        end
    elseif id == 'condition_curse' then
        return isGoshnarCurseActive(states)
    elseif id == 'emblem' then
        local emblem = safeCall(player, 'getEmblem')
        return emblem ~= nil and emblem == EmblemGreen
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

local function applyIconWidgetStyle(container, condition)
    local icon = container and container:getChildById('icon')
    if not icon then
        return
    end

    icon:setImageSource(getConditionPath(condition) or getConditionIcon(condition) or '/images/game/states/player-state-flags')
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

local function getArcAnchor()
    local map = mapPanel or (modules.game_interface and modules.game_interface.getMapPanel and modules.game_interface.getMapPanel())
    if not map then
        return nil
    end

    local arcHeight = imageSizeBroad
    if not arcHeight or arcHeight <= 0 then
        arcHeight = healthCircle and healthCircle:getHeight() or 0
    end

    if healthCircle and arcHeight and arcHeight > 0 then
        return {
            x = healthCircle:getX(),
            y = healthCircle:getY(),
            height = arcHeight,
            map = map
        }
    end

    local fallbackHeight = 120
    return {
        x = map:getX() + (map:getWidth() / 2) - config.fallbackArcDistance,
        y = map:getY() + (map:getHeight() / 2) - (fallbackHeight / 2),
        height = fallbackHeight,
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
    scheduleRefresh(1)
end

function StatusIconBar.onGameStart()
    scheduleRefresh(50)
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

    if not mapPanel and modules.game_interface and modules.game_interface.getMapPanel then
        mapPanel = modules.game_interface.getMapPanel()
    end

    if not statusIconPanel then
        statusIconPanel = g_ui.createWidget('StatusIconPanel', mapPanel)
        g_ui.createWidget('StatusIconTop', statusIconPanel)
        g_ui.createWidget('StatusIconBottom', statusIconPanel)
        statusIconPanel:setVisible(false)
        statusIconPanel:setHeight(config.topBottomSize * 2 + 1)
        StatusIconBar.updatePosition()
    end

    connect(LocalPlayer, {
        onStatesChange = StatusIconBar.onConditionEvent,
        onSkullChange = StatusIconBar.onConditionEvent,
        onEmblemChange = StatusIconBar.onConditionEvent,
        onTaintsChange = StatusIconBar.onConditionEvent,
        onRegenerationChange = StatusIconBar.onConditionEvent
    })

    connect(g_game, {
        onGameStart = StatusIconBar.onGameStart,
        onGameEnd = StatusIconBar.onGameEnd
    })

    initialized = true

    if g_game.isOnline() then
        StatusIconBar.onGameStart()
    end
end

function StatusIconBar.terminate()
    if initialized then
        disconnect(LocalPlayer, {
            onStatesChange = StatusIconBar.onConditionEvent,
            onSkullChange = StatusIconBar.onConditionEvent,
            onEmblemChange = StatusIconBar.onConditionEvent,
            onTaintsChange = StatusIconBar.onConditionEvent,
            onRegenerationChange = StatusIconBar.onConditionEvent
        })

        disconnect(g_game, {
            onGameStart = StatusIconBar.onGameStart,
            onGameEnd = StatusIconBar.onGameEnd
        })
    end

    initialized = false
    removeRefreshEvent()
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
