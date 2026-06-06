-- Status Icon Bar
-- Draws the active special conditions next to the HP arc using Astra's
-- client_settings ConditionsHUD data.

StatusIconBar = StatusIconBar or {}

local statusIconPanel
local activeIcons = {}
local refreshEvent
local initialized = false

local config = {
    maxIcons = 8,
    baseMarginRight = 10,
    fallbackArcDistance = 90,
    mapPadding = 4
}

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

local function isConditionActive(hud, condition)
    local id = getConditionId(condition)
    if not id or type(hud.actives) ~= 'table' then
        return false
    end

    return hud.actives[id] == true or hud.actives[tonumber(id)] == true
end

local function getActiveConditions()
    local hud = getConditionsHUD()
    if not hud or not isHudMasterEnabled() then
        return {}
    end

    local conditions = {}
    for _, condition in ipairs(hud.specialConditionsOrder or {}) do
        if isConditionVisibleInHud(condition) and isConditionActive(hud, condition) then
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

local function removeIcon(id)
    local widget = activeIcons[id]
    activeIcons[id] = nil

    if widget then
        widget:destroy()
    end
end

local function clearIcons()
    local ids = {}
    for id, _ in pairs(activeIcons) do
        table.insert(ids, id)
    end

    for _, id in ipairs(ids) do
        removeIcon(id)
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
    local y = map:getY() + (map:getHeight() / 2) - (fallbackHeight / 2)
    local x = map:getX() + (map:getWidth() / 2) - config.fallbackArcDistance

    return {
        x = x,
        y = y,
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
    for id, _ in pairs(activeIcons) do
        if not activeById[id] then
            table.insert(removeIds, id)
        end
    end

    for _, id in ipairs(removeIds) do
        removeIcon(id)
    end

    for _, condition in ipairs(activeConditions) do
        local id = getConditionId(condition)
        if id then
            local container = activeIcons[id]
            if not container then
                container = g_ui.createWidget('StatusIconContainer', statusIconPanel)
                container:setId('stateicon_' .. id)
                activeIcons[id] = container
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

    statusIconPanel:setVisible(#activeConditions > 0)
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

    if not mapPanel and modules.game_interface and modules.game_interface.getMapPanel then
        mapPanel = modules.game_interface.getMapPanel()
    end

    if not statusIconPanel then
        statusIconPanel = g_ui.createWidget('StatusIconPanel', mapPanel)
        g_ui.createWidget('StatusIconTop', statusIconPanel)
        g_ui.createWidget('StatusIconBottom', statusIconPanel)
        statusIconPanel:setVisible(false)
        StatusIconBar.updateWidgetHeight()
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
