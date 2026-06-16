-- Status Icon Bar - ported from mehah PR #1604, adapted for AstraClient
local debug = false

table.clear = table.clear or function(t) for k in pairs(t) do t[k] = nil end end
table.removevalue = table.removevalue or function(t, v) for i = 1, #t do if t[i] == v then table.remove(t, i); return end end end

ConditionsHUD = {}
StatusIconBar = {}

local statusIconPanel = nil
local activeIcons = {}
local conditionLookup = {}
local visibleConditions = {}
local hudRetryEvents = {}

local config = {
    maxIcons = 8,
    topBottomSize = 10,
    baseMarginRight = 8,
    shrinkTime = 220,
    shrinkInterval = 30
}

local SETTINGS_FILE = '/settings_conditions_hud.json'
local NATIVE_SETTINGS_FILE = '/settings.json'
local DECORATIVE_CHILD_COUNT = 2
local nativeVisibleHudOverrides = {}
local nativeHudMasterOverride = nil
local nativeHudVisibilityLoaded = false
local EMBLEM_HUD_ICON_PATH = '/images/arcs/conditions/player-state-guildwar-flag'
local HUNGRY_HUD_ICON_PATH = '/images/arcs/conditions/player-state-flags-client-02'

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

local function getEmblemTooltip(emblem)
    return emblemTooltips[emblem] or 'Guild Emblem'
end

local function getPlayerEmblem(player)
    return safeCall(player or g_game.getLocalPlayer(), 'getEmblem') or (EmblemNone or 0)
end

local function isEmblemActive(emblem)
    return emblem ~= nil and emblem ~= (EmblemNone or 0)
end

local function loadNativeHudVisibility()
    table.clear(nativeVisibleHudOverrides)
    nativeHudVisibilityLoaded = false

    if not g_resources.fileExists(NATIVE_SETTINGS_FILE) then
        return
    end

    local status, decoded = pcall(function()
        return json.decode(g_resources.readFileContents(NATIVE_SETTINGS_FILE))
    end)
    if not status or type(decoded) ~= 'table' or type(decoded.visibleHud) ~= 'table' then
        return
    end

    nativeHudVisibilityLoaded = true
    for conditionId, visible in pairs(decoded.visibleHud) do
        conditionId = tostring(conditionId)
        visible = visible ~= false
        nativeVisibleHudOverrides[conditionId] = visible
    end
end

local function isNativeHudMasterEnabled()
    if nativeHudMasterOverride ~= nil then
        return nativeHudMasterOverride
    end

    if type(getTmpOption) == 'function' then
        local tempValue = getTmpOption('showInHudCheckBox')
        if tempValue ~= nil then
            return tempValue ~= false
        end
    end

    if m_settings and type(m_settings.getOption) == 'function' then
        local value = m_settings.getOption('showInHudCheckBox')
        if value ~= nil then
            return value ~= false
        end
    end

    if GameOptions and type(GameOptions.getOption) == 'function' then
        local ok, value = pcall(function()
            return GameOptions:getOption('showInHudCheckBox')
        end)
        if ok and value ~= nil then
            return value ~= false
        end
    end

    return true
end

local function isStateActive(states, state)
    return state and states and bit.band(states, state) ~= 0
end

local function removeHudRetryEvent(event)
    if not event then return end
    table.removevalue(hudRetryEvents, event)
end

local function cancelHudRetryEvents()
    for _, event in pairs(hudRetryEvents) do
        removeEvent(event)
    end
    table.clear(hudRetryEvents)
end

local function buildConditionIcons()
    ConditionIcons = ConditionIcons or {}

    local function addCond(cfg)
        if not conditionLookup[cfg.id] then
            table.insert(ConditionIcons, cfg)
            conditionLookup[cfg.id] = cfg
            if not cfg.hidden then
                table.insert(visibleConditions, cfg)
            end
        end
    end

    -- Convert from AstraClient's Icons table format
    if Icons then
        for state, iconData in pairs(Icons) do
            if type(iconData) == 'table' and iconData.id then
                addCond({
                    id = iconData.id,
                    name = iconData.tooltip or iconData.id,
                    tooltip = iconData.tooltip or '',
                    state = type(state) == 'number' and state ~= -1 and state or nil,
                    path = iconData.id == 'condition_hungry' and HUNGRY_HUD_ICON_PATH or iconData.path,
                    clip = iconData.clip,
                    visibleHud = true,
                    visibleBar = true,
                })
            end
        end
    end

    -- Manual additions not in Icons table
    addCond({ id = 'condition_restingarea', name = 'Resting Area', tooltip = 'Resting area protection', state = nil, visibleHud = true, visibleBar = true })
    addCond({ id = 'condition_curse', name = 'Goshnar Curse', tooltip = 'Goshnar Taint', state = nil, visibleHud = true, visibleBar = true })
    addCond({ id = 'emblem', name = 'Guild Emblem', tooltip = 'Guild Emblem', state = nil, path = EMBLEM_HUD_ICON_PATH, visibleHud = false, visibleBar = true })

    -- Skull conditions
    addCond({ id = 'skullgreen', name = 'Green Skull', tooltip = 'Green Skull', skull = 2, visibleHud = true, visibleBar = true })
    addCond({ id = 'skullwhite', name = 'White Skull', tooltip = 'White Skull', skull = 3, visibleHud = true, visibleBar = true })
    addCond({ id = 'skullred', name = 'Red Skull', tooltip = 'Red Skull', skull = 4, visibleHud = true, visibleBar = true })
    addCond({ id = 'skullblack', name = 'Black Skull', tooltip = 'Black Skull', skull = 5, visibleHud = true, visibleBar = true })
    addCond({ id = 'skullorange', name = 'Orange Skull', tooltip = 'Orange Skull', skull = 6, visibleHud = true, visibleBar = true })
    addCond({ id = 'skullyellow', name = 'Yellow Skull', tooltip = 'Yellow Skull', skull = 1, visibleHud = true, visibleBar = true })

    if debug then
        g_logger.info('[StatusIconBar] ConditionIcons count: ' .. #ConditionIcons)
    end
end

local function defaultSettings()
    return { ordered = {}, visibleHud = {}, visibleBar = {}, showInHud = true, showInBar = true }
end

local function normalizeSettings(settings)
    settings = settings or {}
    if type(settings.ordered) ~= 'table' then settings.ordered = {} end
    if type(settings.visibleHud) ~= 'table' then settings.visibleHud = {} end
    if type(settings.visibleBar) ~= 'table' then settings.visibleBar = {} end
    if type(settings.showInHud) ~= 'boolean' then settings.showInHud = true end
    if type(settings.showInBar) ~= 'boolean' then settings.showInBar = true end
    return settings
end

function ConditionsHUD.syncMissingOrderEntries()
    local order = {}
    local seen = {}
    for _, conditionId in ipairs(ConditionsHUD.settings.ordered) do
        local condition = conditionLookup[conditionId]
        if condition and not condition.hidden and not seen[conditionId] then
            table.insert(order, conditionId)
            seen[conditionId] = true
        end
    end
    for _, condition in ipairs(visibleConditions) do
        if not seen[condition.id] then
            table.insert(order, condition.id)
        end
    end
    ConditionsHUD.settings.ordered = order
end

function ConditionsHUD.loadSettings()
    ConditionsHUD.settings = defaultSettings()
    if g_resources.fileExists(SETTINGS_FILE) then
        local status, decoded = pcall(function() return json.decode(g_resources.readFileContents(SETTINGS_FILE)) end)
        if status and type(decoded) == 'table' then
            ConditionsHUD.settings = normalizeSettings(decoded)
        else
            ConditionsHUD.settings = defaultSettings()
        end
    end
    loadNativeHudVisibility()
    ConditionsHUD.syncMissingOrderEntries()
end

function ConditionsHUD.saveSettings()
    local status, encoded = pcall(function() return json.encode(ConditionsHUD.settings, 2) end)
    if status and encoded then
        g_resources.writeFileContents(SETTINGS_FILE, encoded)
    end
end

function ConditionsHUD.getOrderedConditions()
    ConditionsHUD.syncMissingOrderEntries()
    local ordered = {}
    for _, conditionId in ipairs(ConditionsHUD.settings.ordered) do
        local condition = conditionLookup[conditionId]
        if condition and not condition.hidden then
            table.insert(ordered, condition)
        end
    end
    return ordered
end

function ConditionsHUD.isConditionVisible(conditionId, panel)
    local condition = conditionLookup[conditionId]
    if not condition then return false end
    if panel == 'hud' then
        if not isNativeHudMasterEnabled() then return false end
        local nativeValue = nativeVisibleHudOverrides[tostring(conditionId)]
        if nativeValue ~= nil then return nativeValue end
        if nativeHudVisibilityLoaded then return condition.visibleHud ~= false end
        if not ConditionsHUD.settings.showInHud then return false end
        local value = ConditionsHUD.settings.visibleHud[conditionId]
        if value == nil then return condition.visibleHud ~= false end
        return value
    end
    return false
end

function StatusIconBar.isConditionActive(player, condition, states)
    if not condition then return false end

    if condition.skull then
        return player:getSkull() == condition.skull
    end

    if condition.id == 'emblem' then
        return isEmblemActive(getPlayerEmblem(player))
    end

    if condition.id == 'condition_hungry' then
        local regenTime = safeCall(player, 'getRegenerationTime')
        return regenTime ~= nil and regenTime == 0
    end

    if condition.id == 'condition_restingarea' then
        local resting = safeCall(player, 'getRestingAreaProtection')
        if resting ~= nil then return resting end
        return safeCall(player, 'isInRestingArea') or false
    end

    if condition.id == 'condition_curse' then
        return isStateActive(states, PlayerStates.CurseI) or isStateActive(states, PlayerStates.CurseII) or
            isStateActive(states, PlayerStates.CurseIII) or isStateActive(states, PlayerStates.CurseIV) or
            isStateActive(states, PlayerStates.CurseV)
    end

    if condition.state then
        return isStateActive(states, condition.state)
    end

    return false
end

local function applyIconWidgetStyle(container, condition)
    local icon = container and container:getChildById('icon')
    if not icon then return end

    if condition and condition.id == 'emblem' then
        icon:setImageSource(EMBLEM_HUD_ICON_PATH)
    elseif condition and condition.path then
        icon:setImageSource(condition.path)
    elseif condition and condition.clip then
        icon:setImageSource('/images/game/states/player-state-flags')
        local clipX = (condition.clip - 1) * 9
        icon:setImageClip(clipX .. ' 0 9 9')
    else
        icon:setImageSource('/images/game/states/player-state-flags')
    end
end

local function cancelWidgetEvent(widget, eventName)
    if widget and widget[eventName] then
        removeEvent(widget[eventName])
        widget[eventName] = nil
    end
end

local function setWidgetIconOpacity(widget, opacity)
    local icon = widget and widget:getChildById('icon')
    if icon then icon:setOpacity(opacity) end
end

local function removeIconWidget(widget)
    if not widget or not statusIconPanel or not statusIconPanel:hasChild(widget) then return end
    cancelWidgetEvent(widget, 'shrinkInEvent')
    cancelWidgetEvent(widget, 'shrinkOutEvent')
    if widget.conditionId then activeIcons[widget.conditionId] = nil end
    statusIconPanel:removeChild(widget)
    widget:destroy()
    if statusIconPanel:getChildCount() <= DECORATIVE_CHILD_COUNT then
        statusIconPanel:setVisible(false)
    end
    StatusIconBar.updateWidgetHeight()
end

function StatusIconBar.shrinkIn(widget, time)
    if not widget or not statusIconPanel or not statusIconPanel:hasChild(widget) then return end
    cancelWidgetEvent(widget, 'shrinkInEvent')
    cancelWidgetEvent(widget, 'shrinkOutEvent')
    widget.realHeight = widget.realHeight or widget:getHeight()
    local progress = math.min(1, math.max(0, time / config.shrinkTime))
    local height = math.max(1, math.floor(widget.realHeight * progress))
    widget:setHeight(height)
    setWidgetIconOpacity(widget, progress)
    if progress >= 1 then
        cancelWidgetEvent(widget, 'shrinkInEvent')
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
    if not widget or not statusIconPanel or not statusIconPanel:hasChild(widget) then return end
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

function StatusIconBar.clearAll()
    for _, container in pairs(activeIcons) do
        cancelWidgetEvent(container, 'shrinkInEvent')
        cancelWidgetEvent(container, 'shrinkOutEvent')
        if statusIconPanel and statusIconPanel:hasChild(container) then
            container:destroy()
        end
    end
    activeIcons = {}
    if statusIconPanel then statusIconPanel:setVisible(false) end
end

function StatusIconBar.updatePosition()
    if not statusIconPanel or not healthCircle then return end

    local healthX = healthCircle:getX()
    local healthY = healthCircle:getY()
    local healthHeight = imageSizeBroad or healthCircle:getHeight()

    local panelWidth = statusIconPanel:getWidth()
    local panelHeight = statusIconPanel:getHeight()

    local x = healthX - panelWidth - config.baseMarginRight
    local y = healthY + (healthHeight / 2) - (panelHeight / 2)

    if x < 0 then x = 2 end
    if y < 0 then y = 2 end

    statusIconPanel:setX(math.floor(x))
    statusIconPanel:setY(math.floor(y))
end

function StatusIconBar.updateWidgetHeight()
    if not statusIconPanel then return end
    local height = 0
    local childCount = statusIconPanel:getChildCount()
    for i = 1, childCount do
        local child = statusIconPanel:getChildByIndex(i)
        if child then
            height = height + child:getHeight()
            if i > 1 then height = height + 1 end
        end
    end
    statusIconPanel:setHeight(height)
    StatusIconBar.updatePosition()
end

function StatusIconBar.refreshIcons()
    if not statusIconPanel then return end
    if not g_game.isOnline() then StatusIconBar.clearAll(); return end

    local player = g_game.getLocalPlayer()
    if not player then StatusIconBar.clearAll(); return end

    local states = player:getStates() or 0
    local activeConditions = {}

    for _, condition in ipairs(ConditionsHUD.getOrderedConditions()) do
        if ConditionsHUD.isConditionVisible(condition.id, 'hud') and
            StatusIconBar.isConditionActive(player, condition, states) then
            table.insert(activeConditions, condition)
            if #activeConditions >= config.maxIcons then break end
        end
    end

    if debug then
        g_logger.info('[StatusIconBar] states=' .. states .. ' activeConditions=' .. #activeConditions)
    end

    local activeById = {}
    for _, condition in ipairs(activeConditions) do
        activeById[condition.id] = condition
    end

    for conditionId, container in pairs(activeIcons) do
        if not activeById[conditionId] then
            if not container.shrinkOutEvent and statusIconPanel:hasChild(container) then
                StatusIconBar.shrinkOut(container, config.shrinkTime)
            end
        elseif container.shrinkOutEvent then
            cancelWidgetEvent(container, 'shrinkOutEvent')
            local currentHeight = container:getHeight()
            local currentTime = math.floor((currentHeight / math.max(container.realHeight or 1, 1)) * config.shrinkTime)
            StatusIconBar.shrinkIn(container, currentTime)
        end
    end

    for _, condition in ipairs(activeConditions) do
        local container = activeIcons[condition.id]
        if not container then
            container = g_ui.createWidget('StatusIconContainer', statusIconPanel)
            container:setId('stateicon_' .. condition.id)
            container.conditionId = condition.id
            container.realHeight = container:getHeight()
            container:setHeight(1)
            setWidgetIconOpacity(container, 0.0)
            activeIcons[condition.id] = container
            StatusIconBar.shrinkIn(container, 0)
        else
            container.realHeight = container.realHeight or container:getHeight()
        end
        if condition.id == 'emblem' then
            container:setTooltip(getEmblemTooltip(getPlayerEmblem(player)))
        else
            container:setTooltip(condition.tooltip or condition.name or '')
        end
        applyIconWidgetStyle(container, condition)
    end

    for index, condition in ipairs(activeConditions) do
        local container = activeIcons[condition.id]
        if container then
            statusIconPanel:moveChildToIndex(container, index + 1)
        end
    end

    statusIconPanel:setVisible(statusIconPanel:getChildCount() > DECORATIVE_CHILD_COUNT)
    StatusIconBar.updateWidgetHeight()
end

local function ensureHudSetup(retries)
    retries = retries or 0
    if ConditionsHUD.setupHudList and ConditionsHUD.setupHudList() then return end
    if retries > 0 then
        local event
        event = scheduleEvent(function()
            removeHudRetryEvent(event)
            ensureHudSetup(retries - 1)
        end, 200)
        table.insert(hudRetryEvents, event)
    end
end

function StatusIconBar.onStatesChange()
    StatusIconBar.refreshIcons()
end

function StatusIconBar.onSkullChange()
    StatusIconBar.refreshIcons()
end

function StatusIconBar.onEmblemChange()
    StatusIconBar.refreshIcons()
end

function StatusIconBar.onRegenerationChange()
    StatusIconBar.refreshIcons()
end

function StatusIconBar.onGameStart()
    StatusIconBar.refreshIcons()
    StatusIconBar.updatePosition()
    if debug then g_logger.info('[StatusIconBar] Game started, panel visible: ' .. tostring(statusIconPanel and statusIconPanel:isVisible())) end
end

function StatusIconBar.onGameEnd()
    StatusIconBar.clearAll()
end

function StatusIconBar.setNativeHudConditionVisible(conditionId, visible)
    conditionId = tostring(conditionId)
    visible = visible ~= false
    nativeHudVisibilityLoaded = true
    nativeVisibleHudOverrides[conditionId] = visible
    StatusIconBar.refreshIcons()
end

function StatusIconBar.setNativeHudMasterEnabled(visible)
    nativeHudMasterOverride = visible ~= false
    StatusIconBar.refreshIcons()
end

function StatusIconBar.init()
    if debug then g_logger.info('[StatusIconBar] init called') end
    g_ui.importStyle('statusiconbar')
    buildConditionIcons()
    ConditionsHUD.loadSettings()

    local mapPanel = modules.game_interface.getMapPanel()
    if not mapPanel then
        if debug then g_logger.error('[StatusIconBar] mapPanel is nil') end
        return
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
        onStatesChange = StatusIconBar.onStatesChange,
        onSkullChange = StatusIconBar.onSkullChange,
        onEmblemChange = StatusIconBar.onEmblemChange,
        onRegenerationChange = StatusIconBar.onRegenerationChange
    })

    connect(g_game, {
        onGameStart = StatusIconBar.onGameStart,
        onGameEnd = StatusIconBar.onGameEnd
    })

    ensureHudSetup(5)

    if g_game.isOnline() then
        StatusIconBar.onGameStart()
    end

    if debug then g_logger.info('[StatusIconBar] init complete') end
end

function StatusIconBar.terminate()
    disconnect(LocalPlayer, {
        onStatesChange = StatusIconBar.onStatesChange,
        onSkullChange = StatusIconBar.onSkullChange,
        onEmblemChange = StatusIconBar.onEmblemChange,
        onRegenerationChange = StatusIconBar.onRegenerationChange
    })
    disconnect(g_game, {
        onGameStart = StatusIconBar.onGameStart,
        onGameEnd = StatusIconBar.onGameEnd
    })
    cancelHudRetryEvents()
    StatusIconBar.clearAll()
    if statusIconPanel then
        statusIconPanel:destroy()
        statusIconPanel = nil
    end
    ConditionsHUD.listWidget = nil
    ConditionsHUD.upButton = nil
    ConditionsHUD.downButton = nil

    if conditionsWindow then
        conditionsWindow:destroy()
        conditionsWindow = nil
    end
    conditionsList = nil
    ConditionsHUD.upBtn = nil
    ConditionsHUD.downBtn = nil
end

function StatusIconBar.getPanel()
    return statusIconPanel
end

function StatusIconBar.isVisible()
    return statusIconPanel and statusIconPanel:isVisible()
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

-- ConditionsHUD Options Window
local conditionsWindow = nil
local selectedRow = nil

function ConditionsHUD.createConditionRow(condition)
    local row = g_ui.createWidget('UIWidget', conditionsList)
    row:setId(condition.id)
    row:setHeight(24)
    row:setFocusable(true)

    local icon = g_ui.createWidget('UIWidget', row)
    icon:setX(5)
    icon:setWidth(18)
    icon:setHeight(18)
    icon:setY(3)
    if condition.path then
        icon:setImageSource(condition.path)
    else
        icon:setImageSource('/images/game/states/player-state-flags')
        if condition.clip then
            local clipX = (condition.clip - 1) * 9
            icon:setImageClip(clipX .. ' 0 9 9')
        end
    end

    local label = g_ui.createWidget('UILabel', row)
    label:setX(28)
    label:setWidth(150)
    label:setHeight(24)
    label:setText(condition.name or condition.id)
    label:setTextAlign(AlignLeftCenter)
    label:setColor('#c0c0c0')

    local check = g_ui.createWidget('CheckBox', row)
    check:setWidth(20)
    check:setHeight(20)
    check.conditionId = condition.id
    check:setChecked(ConditionsHUD.isConditionVisible(condition.id, 'hud'))
    check:setY(2)
    check.anchorNow = function()
        local p = check:getParent()
        if p then
            check:setX(p:getWidth() - 30)
        end
    end
    addEvent(function() if check.anchorNow then check.anchorNow() end end, 10)

    check.onCheckChange = function(self, checked)
        ConditionsHUD.settings.visibleHud[self.conditionId] = checked
        ConditionsHUD.saveSettings()
        StatusIconBar.setNativeHudConditionVisible(self.conditionId, checked)
    end

    row.onClick = function(self)
        if conditionsList then conditionsList:focusChild(self) end
    end

    row.onFocusChange = function(self, focused)
        if focused then selectedRow = self end
        ConditionsHUD.refreshRowHighlight()
        ConditionsHUD.updateButtons()
    end

    return row
end

function ConditionsHUD.refreshRowHighlight()
    local list = conditionsList
    if not list then return end
    for i = 1, list:getChildCount() do
        local child = list:getChildByIndex(i)
        if child then
            child:setBackgroundColor(child == selectedRow and '#585858' or ((i % 2 == 0) and '#414141' or '#484848'))
        end
    end
end

function ConditionsHUD.updateButtons()
    local up = ConditionsHUD.upBtn
    local down = ConditionsHUD.downBtn
    local list = conditionsList
    if not up or not down or not list then return end
    if not selectedRow or not list:hasChild(selectedRow) then
        up:setEnabled(false)
        down:setEnabled(false)
        return
    end
    local idx = list:getChildIndex(selectedRow)
    up:setEnabled(idx > 1)
    down:setEnabled(idx < list:getChildCount())
end

function ConditionsHUD.moveCondition(delta)
    local list = conditionsList
    if not list then return end
    local focused = selectedRow
    if not focused or not list:hasChild(focused) then return end
    local idx = list:getChildIndex(focused)
    local target = idx + delta
    if target < 1 or target > list:getChildCount() then return end
    list:moveChildToIndex(focused, target)

    -- Sync order
    local order = {}
    for i = 1, list:getChildCount() do
        local child = list:getChildByIndex(i)
        if child then table.insert(order, child:getId()) end
    end
    ConditionsHUD.settings.ordered = order
    ConditionsHUD.syncMissingOrderEntries()
    ConditionsHUD.saveSettings()
    ConditionsHUD.refreshRowHighlight()
    ConditionsHUD.updateButtons()
    StatusIconBar.refreshIcons()
end

function ConditionsHUD.populateList()
    local list = conditionsList
    if not list then return end
    list:destroyChildren()
    selectedRow = nil

    local ordered = ConditionsHUD.getOrderedConditions()
    for _, condition in ipairs(ordered) do
        ConditionsHUD.createConditionRow(condition)
    end

    local first = list:getChildByIndex(1)
    if first then
        list:focusChild(first)
        selectedRow = first
    end
    ConditionsHUD.refreshRowHighlight()
    ConditionsHUD.updateButtons()
end

function ConditionsHUD.setupOptionsWindow()
    if conditionsWindow then return end
    conditionsWindow = g_ui.loadUI('option_conditions')
    conditionsWindow:hide()

    local masterCheck = conditionsWindow:recursiveGetChildById('hudMasterCheckBox')
    if masterCheck then
        masterCheck:setChecked(ConditionsHUD.settings.showInHud)
        masterCheck.onCheckChange = function(_, checked)
            ConditionsHUD.settings.showInHud = checked
            ConditionsHUD.saveSettings()
            StatusIconBar.setNativeHudMasterEnabled(checked)
        end
    end

    ConditionsHUD.upBtn = conditionsWindow:recursiveGetChildById('upButton')
    ConditionsHUD.downBtn = conditionsWindow:recursiveGetChildById('downButton')
    conditionsList = conditionsWindow:recursiveGetChildById('conditionsScroll') or conditionsWindow:recursiveGetChildById('conditionsList')

    if ConditionsHUD.upBtn then
        ConditionsHUD.upBtn.onClick = function() ConditionsHUD.moveCondition(-1) end
    end
    if ConditionsHUD.downBtn then
        ConditionsHUD.downBtn.onClick = function() ConditionsHUD.moveCondition(1) end
    end

    ConditionsHUD.populateList()
end

function ConditionsHUD.showOptionsWindow()
    ConditionsHUD.setupOptionsWindow()
    if conditionsWindow then
        local displaySize = g_window.getDisplaySize()
        conditionsWindow:setX(math.floor((displaySize.width - conditionsWindow:getWidth()) / 2))
        conditionsWindow:setY(math.floor((displaySize.height - conditionsWindow:getHeight()) / 2))
        conditionsWindow:show()
        conditionsWindow:raise()
        conditionsWindow:focus()
    end
end

function ConditionsHUD.toggleOptionsWindow()
    if conditionsWindow and conditionsWindow:isVisible() then
        conditionsWindow:hide()
    else
        ConditionsHUD.showOptionsWindow()
    end
end
