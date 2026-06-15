local iconsTable = {
    ["Experience"] = 8,
    ["Magic"] = 0,
    ["Axe"] = 2,
    ["Club"] = 1,
    ["Distance"] = 3,
    ["Fist"] = 4,
    ["Shielding"] = 5,
    ["Sword"] = 6,
    ["Fishing"] = 7
}

local translateID = {
    ["Experience"] = "showExperience",
    ["Magic"] = "showMagicLevel",
    ["Axe"] = "showAxeFighting",
    ["Club"] = "showClubFighting",
    ["Distance"] = "showDistanceFighting",
    ["Fist"] = "showFistFighting",
    ["Shielding"] = "showShielding",
    ["Sword"] = "showSwordFighting",
    ["Fishing"] = "showFishing"
}

local healthBar = nil
local manaBar = nil
local manaBarSecond = nil
local manaShieldBar = nil
local manaShieldText = nil
local manaText = nil
local topBar = nil
local states = nil
local useManaShield = nil
local currentLayout = 'default'
local currentDirection = 'top'

local statusBarData = {}
local lastProficiencyCache = {}
local topBarLoadEvent = nil
local topBarLayoutEvents = {}
local pendingVisibility = nil

local progressPath = '/images/game/topbar/progress/'

local layouts = {
    compact = 'layouts/compact',
    default = 'layouts/default',
    parallel = 'layouts/parallel',
    large = 'layouts/large',
    leftcompact = 'layouts/left-compact',
    leftdefault = 'layouts/left-default',
    leftparallel = 'layouts/left-parallel',
    leftlarge = 'layouts/left-large',
    rightcompact = 'layouts/left-compact',
    rightdefault = 'layouts/left-default',
    rightparallel = 'layouts/left-parallel',
    rightlarge = 'layouts/left-large',
}

local validDirections = {
    top = true,
    bottom = true,
    left = true,
    right = true
}

local validLayouts = {
    compact = true,
    default = true,
    parallel = true,
    large = true
}

local function clearTopBarLoadEvent()
    if topBarLoadEvent then
        removeEvent(topBarLoadEvent)
        topBarLoadEvent = nil
    end
end

local function clearTopBarLayoutEvents()
    for _, event in pairs(topBarLayoutEvents) do
        removeEvent(event)
    end
    topBarLayoutEvents = {}
end

local function clearTopBarWidgetRefs()
    healthBar = nil
    manaBar = nil
    manaBarSecond = nil
    manaShieldBar = nil
    manaShieldText = nil
    manaText = nil
    states = nil
    topBar = nil
end

local function normalizeStatusBarData()
    if not validDirections[currentDirection] then
        currentDirection = 'top'
        statusBarData["position"] = currentDirection
    end

    if not validLayouts[currentLayout] then
        currentLayout = 'default'
        statusBarData["style"] = currentLayout
    end
end

local function isCustomisableBarsEnabled()
    if TempOptions and type(TempOptions.getOption) == 'function' then
        local value = TempOptions:getOption("customisableBars")
        if value ~= nil then
            return toboolean(value)
        end
    end

    if g_settings then
        return g_settings.getBoolean("customisableBars")
    end

    if GameOptions and type(GameOptions.getOption) == 'function' then
        local ok, value = pcall(GameOptions.getOption, GameOptions, "customisableBars")
        if ok and value ~= nil then
            return toboolean(value)
        end
    end

    if m_settings and type(m_settings.getOption) == 'function' then
        local ok, value = pcall(m_settings.getOption, "customisableBars")
        if ok and value ~= nil then
            return toboolean(value)
        end
    end

    return false
end

function init()
    connect(LocalPlayer, {
        onHealthChange = onHealthChange,
        onManaChange = onManaChange,
        onManaShieldChange = onManaShieldChange,
        onLevelChange = onLevelChange,
        onMagicLevelChange = onMagicLevelChange,
        onBaseMagicLevelChange = onBaseMagicLevelChange,
        onSkillChange = onSkillChange,
        onVocationChange = onVocationChange,
        onBaseSkillChange = onBaseSkillChange,
        onHarmonyChange = onHarmonyChange,
        onSerenityChange = onSerenityChange,

    })
    connect(g_game, {onGameStart = online, onGameEnd = offline})

    if g_game.isOnline() then online() end
end

function terminate()
    clearTopBarLoadEvent()
    clearTopBarLayoutEvents()

    disconnect(LocalPlayer, {
        onHealthChange = onHealthChange,
        onManaChange = onManaChange,
        onManaShieldChange = onManaShieldChange,
        onLevelChange = onLevelChange,
        onMagicLevelChange = onMagicLevelChange,
        onBaseMagicLevelChange = onBaseMagicLevelChange,
        onVocationChange = onVocationChange,
        onSkillChange = onSkillChange,
        onBaseSkillChange = onBaseSkillChange,
        onHarmonyChange = onHarmonyChange,
        onSerenityChange = onSerenityChange,
    })
    disconnect(g_game, {onGameStart = online, onGameEnd = offline})
end

local function isLoadedPlayerReady()
    if type(LoadedPlayer.isLoaded) ~= "function" then
        return true
    end
    return LoadedPlayer:isLoaded()
end

local function ensureLoadedPlayer()
    if not LoadedPlayer then
        return false
    end
    if isLoadedPlayerReady() then
        return true
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return false
    end

    local playerId = player:getId()
    if type(LoadedPlayer.setId) == "function" and type(playerId) == "number" and playerId > 0 then
        LoadedPlayer:setId(playerId)
    end

    local playerName = player:getName()
    if type(LoadedPlayer.setName) == "function" and type(playerName) == "string" and playerName ~= "" then
        LoadedPlayer:setName(playerName)
    end

    local playerVocation = type(player.getVocation) == "function" and player:getVocation() or nil
    if type(LoadedPlayer.setVocation) == "function" and type(playerVocation) == "number" and playerVocation >= 0 then
        LoadedPlayer:setVocation(playerVocation)
    end

    return isLoadedPlayerReady()
end

function setupTopBar()
    normalizeStatusBarData()

    local isSideBar = (currentDirection == "left" or currentDirection == "right")
    local direction = isSideBar and (currentDirection .. currentLayout) or currentLayout
    local layout = layouts[direction] or layouts[currentLayout] or layouts.default

    local topPanel = m_interface.getTopBar()
    local leftPanel = m_interface.getLeftBar()
    local rightPanel = m_interface.getRightBar()
    local parent = topPanel
    if currentDirection == "left" then
        parent = leftPanel
    elseif currentDirection == "right" then
        parent = rightPanel
    end

    if not parent then
        g_logger.warning("Unable to setup top bar parent for direction: " .. tostring(currentDirection))
        if topBar and topBar:getParent() then
            topBar:destroy()
        end
        clearTopBarWidgetRefs()
        return false
    end

    if topBar and topBar:getParent() then
        topBar:destroy()
    end
    clearTopBarWidgetRefs()

    local ok, widget = pcall(function()
        return g_ui.loadUI(layout, parent)
    end)
    if not ok or not widget then
        g_logger.warning("Unable to load top bar layout: " .. tostring(layout))
        clearTopBarWidgetRefs()
        return false
    end

    topBar = widget
    topBar:setId(layout)

    local topbarBackground = topBar:recursiveGetChildById('topbarBackground')
    local healthContainer = topBar:recursiveGetChildById('healthContainer')
    local manaContainer = topBar:recursiveGetChildById('manaContainer')
    local skillsPanel = topBar:recursiveGetChildById('skills')

    healthBar = healthContainer and healthContainer:recursiveGetChildById('healthBar') or nil
    manaBar = manaContainer and manaContainer:recursiveGetChildById('manaBar') or nil
    manaBarSecond = manaContainer and manaContainer:recursiveGetChildById('manaBarSecond') or nil
    manaShieldBar = manaContainer and manaContainer:recursiveGetChildById('manaShield') or nil
    manaShieldText = manaContainer and manaContainer:recursiveGetChildById('statusManaShield') or nil
    manaText = manaContainer and manaContainer:recursiveGetChildById('statusMana') or nil

    if not topbarBackground or not healthBar or not manaBar or not manaBarSecond or not manaShieldBar or not manaShieldText or not manaText or not skillsPanel then
        g_logger.warning("Unable to setup top bar layout: " .. tostring(layout))
        topBar:destroy()
        clearTopBarWidgetRefs()
        return false
    end

    topBar.topbarBackground = topbarBackground
    topBar.skills = skillsPanel

    local statsPanel = topBar:recursiveGetChildById('stats')
    states = statsPanel and statsPanel:recursiveGetChildById('box') or nil

    if states and m_settings and m_settings.ConditionsHUD and m_settings.ConditionsHUD.startTopPanel then
        m_settings.ConditionsHUD:startTopPanel(states)
    end

    topBar.onMouseRelease = function(widget, mousePos, mouseButton)
        menu(mouseButton)
    end

    topBar:show()
    m_interface.updateTopBar(currentDirection)

    return true
end

local function getDefaultStatusBarData()
    return {
        ["position"] = "top",
        ["showAxeFighting"] = false,
        ["showClubFighting"] = false,
        ["showDistanceFighting"] = false,
        ["showExperience"] = true,
        ["showFishing"] = false,
        ["showFistFighting"] = false,
        ["showMagicLevel"] = false,
        ["showShielding"] = false,
        ["showSwordFighting"] = false,
        ["style"] = "default"
    }
end

local function loadStatusBarData()
    statusBarData = loadJsonStruct("/characterdata/" .. LoadedPlayer:getId() .. "/statusBarData.json") or {}
    if type(statusBarData) ~= 'table' or table.empty(statusBarData) then
        statusBarData = getDefaultStatusBarData()
    end

    currentLayout = statusBarData["style"]
    currentDirection = statusBarData["position"]
    normalizeStatusBarData()
    lastProficiencyCache = {}
end

local function ensureTopBarInitialized()
    if topBar then
        return true
    end
    if not g_game.isOnline() or not ensureLoadedPlayer() then
        return false
    end

    loadStatusBarData()
    if not setupTopBar() then
        return false
    end
    if not topBar then
        return false
    end

    setupSkills()
    refreshVisibleBars()
    return true
end

local function scheduleTopBarLayoutRefresh()
    clearTopBarLayoutEvents()

    for _, delay in ipairs({50, 150, 350, 750, 1500, 3000, 5000}) do
        table.insert(topBarLayoutEvents, scheduleEvent(function()
            if not g_game.isOnline() then
                return
            end

            reloadFromSettings()

            if modules.game_healthcircle and modules.game_healthcircle.scheduleMapResizeUpdates then
                modules.game_healthcircle.scheduleMapResizeUpdates()
            end
        end, delay))
    end
end

local function retryOnline(attempt)
    clearTopBarLoadEvent()

    if not g_game.isOnline() or attempt >= 120 then
        return
    end

    topBarLoadEvent = scheduleEvent(function()
        topBarLoadEvent = nil
        online(attempt + 1)
    end, 100)
end

function online(attempt)
    local benchmark = g_clock.millis()
    attempt = attempt or 0
    local visibility = pendingVisibility

    if not ensureLoadedPlayer() then
        retryOnline(attempt)
        return
    end

    clearTopBarLoadEvent()
    loadStatusBarData()
    if not refresh(nil, nil, visibility) then
        return
    end

    pendingVisibility = nil
    scheduleTopBarLayoutRefresh()
    consoleln("TopBar loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

local function refreshTopBarValues(player)
    if not topBar or not player then return end
    setupSkills()
    refreshVisibleBars()

    useManaShield = canUseManaShield()

    onLevelChange(player, player:getLevel(), player:getLevelPercent())
    onHealthChange(player, player:getHealth(), player:getMaxHealth())
    onManaChange(player, player:getMana(), player:getMaxMana())
    onMagicLevelChange(player, player:getMagicLevel(), player:getMagicLevelPercent())
    onManaShieldChange(player, player:getMagicShield(), player:getMaxMagicShield())
    onHarmonyChange(player, player.getHarmony and player:getHarmony() or 0)
    onSerenityChange(player, player.isSerenity and player:isSerenity() or false)

    for i = Skill.Fist, Skill.ManaLeechAmount do
        onSkillChange(player, i, player:getSkillLevel(i), player:getSkillLevelPercent(i))
        onBaseSkillChange(player, i, player:getSkillBaseLevel(i))
    end

    topBar.skills:insertLuaCall("onGeometryChange")
    topBar.skills.onGeometryChange = setSkillsLayout
end

function refresh(profileChange, skipSetup, visibility)
    local player = g_game.getLocalPlayer()
    if not player then return false end

    if not skipSetup then
        if not setupTopBar() then
            retryOnline(0)
            return false
        end
    end

    show()
    refreshTopBarValues(player)
    if visibility == nil then
        visibility = isCustomisableBarsEnabled()
    end
    return toggle(visibility)
end

function refreshVisibleBars()
    local ids = {"Experience", "Magic", "Axe", "Club", "Distance", "Fist", "Shielding", "Sword", "Fishing"}

    for i, id in ipairs(ids) do
        local panel = topBar[id] or topBar.skills[id]

        if panel then
            panel:setVisible(statusBarData[translateID[id]])
        end
    end
end

function setSkillsLayout()
    local visible = 0
    local skills = topBar.skills
    local width = skills:getWidth()

    for i, child in ipairs(skills:getChildren()) do
        visible = child:isVisible() and visible + 1 or visible
    end

    local many = visible > 1
    width = many and (width / 2) or width

    if skills:getLayout().setCellSize then
        skills:getLayout():setCellSize({width = width, height = 19})
    end
end

function offline()
    clearTopBarLoadEvent()
    clearTopBarLayoutEvents()
    pendingVisibility = nil

    local player = g_game.getLocalPlayer()
    useManaShield = false

    if not LoadedPlayer:isLoaded() then return end
    if table.empty(statusBarData) then return end
    saveJsonStruct("/characterdata/" .. LoadedPlayer:getId() .. "/statusBarData.json", statusBarData)
end

function toggleIcon(bitChanged)
    local content = states
    if not content then return end

    local icon = content:getChildById(Icons[bitChanged].id)
    if icon then
        icon:destroy()
        if bitChanged == PlayerStates.NewMagicShield then
            local player = g_game.getLocalPlayer()
            if not player then return end
            onManaShieldChange(player, player:getMagicShield(), player:getMaxMagicShield())
        end
    else
        icon = loadIcon(bitChanged)
        icon:setParent(content)
        if bitChanged == PlayerStates.NewMagicShield then
            local player = g_game.getLocalPlayer()
            if not player then return end
            onManaShieldChange(player, player:getMagicShield(), player:getMaxMagicShield())
        end
    end
    moveHungryToLast()
end

function loadIcon(bitChanged, message)
    local icon = g_ui.createWidget('ConditionWidget', content)
    icon:setId(Icons[bitChanged].id)
    icon:setActionId(bitChanged)
    icon:setImageSource(Icons[bitChanged].path)
    icon:setTooltip(message and message or Icons[bitChanged].tooltip)
    moveHungryToLast()
    return icon
end

function onHealthChange(localPlayer, health, maxHealth)
    if not healthBar then return end

    local healthPercent = (health / maxHealth) * 100
    local verticalSideBar = (currentDirection == 'left' or currentDirection == 'right')
    local healthBarType = verticalSideBar and "-vertical" or ""
    local largeSuffix = (verticalSideBar and currentLayout == 'large') and "wide-" or ""

    local function getImageSource(healthPercent, largeSuffix)
        if healthPercent > 99 then
            return largeSuffix .. 'progressbar-large-100'
        elseif healthPercent > 70 then
            return largeSuffix .. 'progressbar-large-95'
        elseif healthPercent > 30 then
            return largeSuffix .. 'progressbar-large-60'
        elseif healthPercent > 10 then
            return largeSuffix .. 'progressbar-large-30'
        elseif healthPercent > 5 then
            return largeSuffix .. 'progressbar-large-10'
        else
            return largeSuffix .. 'progressbar-large-4'
        end
    end

    local imageSource = progressPath .. getImageSource(healthPercent, largeSuffix) .. healthBarType

    local layoutDimensions = {
        compact = verticalSideBar and { width = 12, height = 803 } or { width = 803, height = 12 },
        default = verticalSideBar and { width = 12, height = 864 } or { width = 864, height = 12 },
        parallel = verticalSideBar and { width = 12, height = 1720 } or { width = 1720, height = 12 },
        large = verticalSideBar and { width = 25, height = 700 } or { width = 700, height = 12 }
    }

    local healthClip = layoutDimensions[currentLayout] or { width = 0, height = 0 }
    healthClip.x, healthClip.y = 0, 0
    local imageRect = { x = 0, y = 0, width = math.floor(healthClip.width * (healthPercent / 100)), height = healthClip.height}

    healthBar:setImageSource(imageSource)
    healthBar:setImageClip(healthClip)
    healthBar:setImageRect(imageRect)
    healthBar:setFont("Verdana Bold-11px")
    healthBar:setColor("#ffffff")
    healthBar:setValue(health, 0, maxHealth)
    if healthBar.statusHealth then
        healthBar.statusHealth:setText(string.format("%d / %d", health, maxHealth))
    else
        healthBar:setText(string.format("%d / %d", health, maxHealth))
    end
end

function onManaShieldChange(localPlayer, mana, maxMana)
    if not manaBar or not manaShieldBar or not manaBarSecond or not manaShieldText then
        return
    end

    if not localPlayer:useMagicShield() then
        manaBar:setVisible(true)
        manaBarSecond:setVisible(false)
        manaShieldBar:setVisible(false)
        manaShieldText:setVisible(false)
        return
    end

    maxMana = math.max(mana, maxMana > 0 and maxMana or 100)

    manaBarSecond:setVisible(true)
    manaShieldBar:setVisible(true)
    manaBar:setVisible(false)
    manaShieldText:setVisible(true)

    local manaPercent = (mana / maxMana) * 100
    if manaPercent < 0 then return end

    local verticalSideBar = (currentDirection == 'left' or currentDirection == 'right')
    local barType = "shieldmana"
    local barSuffix = verticalSideBar and "-vertical" or ""

    local imageSource = string.format("/images/game/topbar/progress/%s-progressbar-large-100%s", barType, barSuffix)

    local layoutDimensions = {
        compact = verticalSideBar and { width = 5, height = 803 } or { width = 803, height = 5 },
        sidecompact = verticalSideBar and { width = 5, height = 803 } or { width = 803, height = 5 },
        default = verticalSideBar and { width = 5, height = 862 } or { width = 862, height = 5 },
        parallel = verticalSideBar and { width = 5, height = 1720 } or { width = 1720, height = 5 },
        large = verticalSideBar and { width = 11, height = 827 } or { width = 827, height = 11 }
    }

    local imageClip = layoutDimensions[currentLayout] or { width = 0, height = 0 }
    imageClip.x, imageClip.y = 0, 0

    if currentLayout == 'large' then
        topBar.topbarBackground.manaContainer:setImageSource('/images/game/topbar/large/large-container-mana' .. barSuffix)
        manaText:setMarginBottom(7)
    end

    local imageRect = {
        x = 0,
        y = 0,
        width = math.floor(imageClip.width * (manaPercent / 100)),
        height = imageClip.height
    }

    manaShieldBar:setImageSource(imageSource)
    manaShieldBar:setImageClip(imageClip)
    manaShieldBar:setImageRect(imageRect)

    local shieldTextFormat = currentLayout == 'large' and "%d / %d@" or "(%d / %d@)"
    manaShieldText:setText(shieldTextFormat:format(mana, maxMana))
    manaShieldText:setFont("Icon-VBold-11px")
    manaShieldText:setColor("#ffffff")
    manaShieldBar:setValue(mana, 0, maxMana)
end

function onManaChange(localPlayer, mana, maxMana)
    if not manaBar or not manaBarSecond then return end

    maxMana = math.max(mana, maxMana)

    local manaPercent = (mana / maxMana) * 100
    local useShield = localPlayer:useMagicShield()
    local verticalSideBar = (currentDirection == 'left' or currentDirection == 'right')
    local barType = useShield and "manashield" or "mana"
    local barSuffix = verticalSideBar and "-vertical" or ""
    if not useShield and verticalSideBar and currentLayout == 'large' then
        barType = "wide-" .. barType
    end
    
    local layoutDimensions = {
        compact = verticalSideBar and { width = 12, height = 803 } or { width = 803, height = 12 },
        default = verticalSideBar and { width = 12, height = 862 } or { width = 862, height = 12 },
        parallel = verticalSideBar and { width = 12, height = 1720 } or { width = 1720, height = 12 },
        large = verticalSideBar and { width = 25, height = 827 } or { width = 827, height = 25 }
    }

    if useShield then
        local dimensionKey = verticalSideBar and "width" or "height"
        for _, layout in pairs(layoutDimensions) do
            layout[dimensionKey] = 11
        end
    end

    local imageSource = string.format("/images/game/topbar/progress/%s-progressbar-large-100%s", barType, barSuffix)
    local imageClip = layoutDimensions[currentLayout] or { width = 0, height = 0 }
    imageClip.x, imageClip.y = 0, 0

    local manaBarToUpdate = useShield and manaBarSecond or manaBar
    manaBar:setVisible(not useShield)

    manaBarToUpdate:setImageSource(imageSource)
    manaBarToUpdate:setImageClip(imageClip)
    local imageRect = { x = 0, y = 0, width = math.floor(imageClip.width * (manaPercent / 100)), height = imageClip.height }
    manaBarToUpdate:setImageRect(imageRect)

    manaText:setText(string.format("%d / %d", mana, maxMana))
    manaText:setFont("Verdana Bold-11px")
    manaText:setColor("#ffffff")
    manaBarToUpdate:setValue(mana, 0, maxMana)
    manaText:setMarginBottom(currentLayout == 'large' and (useShield and 7 or 0) or 0)
end

function onLevelChange(localPlayer, value, percent)
    if not topBar then return end

    local experienceBar = topBar.Experience.progress
    local levelLabel = topBar.Experience.level
    local text = tr("%s XP for next level", comma_value(modules.game_skills.expToAdvance(localPlayer:getLevel(), localPlayer:getExperience())))

    if localPlayer.expSpeed ~= nil then
        local expPerHour = math.floor(localPlayer.expSpeed * 3600)
        if expPerHour > 0 then
            local nextLevelExp = modules.game_skills.expForLevel(localPlayer:getLevel()+1)
            local hoursLeft = (nextLevelExp - localPlayer:getExperience()) / expPerHour
            local minutesLeft = math.floor((hoursLeft - math.floor(hoursLeft))*60)
            hoursLeft = math.floor(hoursLeft)
            text = text .. '\n' .. tr('currently %s XP per hour, next level in %d hours and %d minutes', comma_value(expPerHour), hoursLeft, minutesLeft)
        end
    end

    experienceBar:setTooltip(text)
    experienceBar:setPercent(percent)
    if levelLabel then
        levelLabel:setText(value)
        levelLabel:setFont("Verdana Bold-11px")
        levelLabel:setColor("#c0c0c0")
        levelLabel:setTextAutoResize(true)
    end
end

function show()
    if not g_game.isOnline() or not topBar then return end
    topBar:setVisible(true)
end

function toggle(value)
    value = toboolean(value)
    pendingVisibility = value

    if not g_game.isOnline() then
        return false
    end

    if not ensureTopBarInitialized() then
        retryOnline(0)
        return false
    end

    pendingVisibility = nil
    topBar:setVisible(value)
    if value then
        refreshTopBarValues(g_game.getLocalPlayer())
    end

    if m_interface and m_interface.updateTopBar then
        m_interface.updateTopBar(value and currentDirection or "hidden")
    end

    local leftPanel = m_interface.getLeftActionPanel()
    local rightPanel = m_interface.getRightActionPanel()
    if not leftPanel or not rightPanel then
        return true
    end

    if value and currentDirection == "top" then
        leftPanel:setPaddingTop(1)
        rightPanel:setPaddingTop(1)
    else
        leftPanel:setPaddingTop(54)
        rightPanel:setPaddingTop(54)
    end

    return true
end

function reloadFromSettings(valueOverride)
    local value = valueOverride
    if value == nil then
        value = isCustomisableBarsEnabled()
    else
        value = toboolean(value)
    end
    pendingVisibility = value

    if not g_game.isOnline() then
        return
    end

    if not ensureLoadedPlayer() then
        retryOnline(0)
        return
    end

    local previousLayout = currentLayout
    local previousDirection = currentDirection
    loadStatusBarData()
    local skipSetup = topBar and previousLayout == currentLayout and previousDirection == currentDirection
    if not refresh(nil, skipSetup, value) then
        return false
    end

    pendingVisibility = nil
    return true
end

function setupSkillPanel(id, parent, experience, defaultOff)
    local widget = g_ui.createWidget('SkillPanel', parent)
    widget:setId(id)
    if widget.level then
        widget.level:setTooltip(id)
    end
    widget.icon:setTooltip(id)
    widget.icon:setImageClip({x = iconsTable[id]*9, y = 0, width = 9,height = 9})

    if not experience then
        widget.progress:setBackgroundColor('#00c000')
        widget.shop:setVisible(false)
        widget.shop:disable()
        widget.shop:setWidth(0)
        widget.progress:setMarginRight(1)
        if currentDirection == "left" or currentDirection == "right" then
            widget.progress:addAnchor(AnchorTop, 'parent', AnchorTop)
        end
    end

    if not statusBarData[translateID[id]] then
        widget:setVisible(false)
    end

    if id == "Experience" and ((currentDirection == "left" or currentDirection == "right") and currentLayout == "large") then
        widget:setMarginLeft(17)
    end

    -- breakers
    widget:insertLuaCall("onGeometryChange")
    widget.onGeometryChange = function()
        local left = widget.left
        local right = widget.right
        if currentDirection == "left" or  currentDirection == "right" then
            local margin = widget.progress:getHeight() / 4
            left:setMarginTop(margin)
            right:setMarginBottom(margin)
        else
            local margin = widget.progress:getWidth() / 4
            left:setMarginRight(margin)
            right:setMarginRight(margin)
        end
    end

end

function menu(mouseButton)
    if mouseButton ~= 2 then return end

    local menu = g_ui.createWidget('PopupMenu')
    menu:setId("topBarMenu")
    menu:setGameMenu(true)

    -- Position config
    local directionMappings = {
        top = { "left", "right", "bottom" },
        left = { "top", "right", "bottom" },
        right = { "top", "left", "bottom" },
        bottom = { "top", "left", "right" }
    }

    if not currentDirection then
        currentDirection = "top"
    end

    local currentTable = directionMappings[currentDirection]
    if not currentTable then
        currentTable = directionMappings["top"]
        currentDirection = "top"
    end

    local directionsOptions = {}
    for _, value in ipairs(currentTable) do
        table.insert(directionsOptions, { label = value:gsub("^%l", string.upper), value = value })
    end

    for _, option in ipairs(directionsOptions) do
        local text = "Switch to " .. option.label
        menu:addOption(text, function()
            currentDirection = option.value
            statusBarData["position"] = currentDirection
            if setupTopBar() then
                refresh(nil, true)
            end
        end)
    end

    menu:addSeparator()

    -- Layout config
    local layoutMappings = {
        compact = { "default", "large", "parallel" },
        default = { "compact", "large", "parallel" },
        large = { "default", "compact", "parallel" },
        parallel = { "default", "compact", "large" }
    }
    
    local layoutsOptions = {}
    for _, value in ipairs(layoutMappings[currentLayout]) do
        table.insert(layoutsOptions, { label = value:gsub("^%l", string.upper), value = value })
    end

    for _, option in ipairs(layoutsOptions) do
        local text = "Switch to " .. option.label
        menu:addOption(text, function()
            currentLayout = option.value
            statusBarData["style"] = currentLayout
            if setupTopBar() then
                refresh(nil, true)
                switchCurrentLayout()
            end
        end)
    end

    menu:addSeparator()

    local expPanel = topBar.Experience
    local start = expPanel:isVisible() and "Hide" or "Show"
    menu:addOption(start .. " Experience Level",
                   function() toggleSkillPanel("Experience") end)
    for i, child in ipairs(topBar.skills:getChildren()) do
        local id = child:getId()
        if id ~= "stats" then
            local start = child:isVisible() and "Hide" or "Show"
            menu:addOption(start .. " " .. id .. " Level",
                           function() toggleSkillPanel(id) end)
        end
    end

    menu:display(mousePos)
    return true
end

function setupSkills()
    local t = {
        "Experience", "Magic", "Axe", "Club", "Distance", "Fist", "Shielding",
        "Sword", "Fishing"
    }

    for i, id in ipairs(t) do
        if not topBar[id] and not topBar.skills[id] then
            setupSkillPanel(id, i == 1 and topBar or topBar.skills, i == 1, i == 1)
        end
    end

    local child = topBar.Experience
    topBar:moveChildToIndex(child, 2)
end

function toggleSkillPanel(id)
    if not topBar then return end

    local panel = topBar.skills[id]
    panel = panel or topBar.Experience
    if not panel then return end

    statusBarData[translateID[id]] = not panel:isVisible()
    panel:setVisible(not panel:isVisible())
    setSkillsLayout()
end

function setSkillValue(id, value)
    if not topBar then return end

    local panel = topBar.skills[id]
    if not panel then return end

    local levelLabel = panel.level
    if levelLabel then
        levelLabel:setText(value)
        levelLabel:setFont("Verdana Bold-11px")
        levelLabel:setColor("#c0c0c0")
        levelLabel:setTextAutoResize(true)
    end
end

function setSkillPercent(id, percent, tooltip)
    if not topBar or not topBar.skills[id] then return end

    local skillPanel = topBar.skills[id]
    local progressBar = skillPanel:recursiveGetChildById('progress')
    if not progressBar then return end
    progressBar:setPercent(percent)
    if tooltip then
        progressBar:setTooltip(tooltip)
    end
end

function setSkillBase(id, value, baseValue, loyalty)
    if not topBar then return end

    local panel = topBar.skills[id]
    if not panel then return end

    local progress = topBar.skills[id].progress
    local progressDesc = tr('You have %s percent to go', convertSkillPercent(10000 - (progress:getPercent() * 100), false))
    local level = topBar.skills[id].level

    if baseValue <= 0 or value < 0 then return end

    local realBase = baseValue + loyalty
    local realValue = value + loyalty

    if value > baseValue or (realBase > baseValue) then
        local tooltip = tr("%s = %s", realValue, baseValue)
        if value > baseValue then
            tooltip = tr("%s +%s", tooltip, (value - baseValue))
            if level then
                level:setColor('#44ad25') -- green
            end
        end

        if loyalty > 0 then
            tooltip = tr("%s (+%s Loyalty)", tooltip, loyalty)
        end

        tooltip = tooltip .. "\n" .. progressDesc
        progress:setTooltip(tooltip)
    elseif value < baseValue then
        if level then
            level:setColor('#c00000') -- red
        end
        progress:setTooltip(baseValue .. ' ' .. (value - baseValue) .. "\n" .. progressDesc)
    else
        if level then
            level:setColor('#bbbbbb') -- default
        end
        progress:setTooltip(progressDesc)
    end
end

function onMagicLevelChange(localPlayer, magiclevel, percent)
    setSkillValue('Magic', magiclevel + localPlayer:getMagicLoyalty())
    setSkillPercent('Magic', (percent / 100), tr('You have %s percent to go', convertSkillPercent(10000 - percent)))
    onBaseMagicLevelChange(localPlayer, localPlayer:getBaseMagicLevel())
end

function onBaseMagicLevelChange(localPlayer, baseMagicLevel)
    setSkillBase('Magic', localPlayer:getMagicLevel(), baseMagicLevel, localPlayer:getMagicLoyalty())
end

function onSkillChange(localPlayer, id, level, percent)
    id = id + 1
    local skillNames = {
        [1] = "Fist",
        [2] = "Club",
        [3] = "Sword",
        [4] = "Axe",
        [5] = "Distance",
        [6] = "Shielding",
        [7] = "Fishing"
    }

    if id > #skillNames then return end

    local skillName = skillNames[id]

    setSkillValue(skillNames[id], (level + localPlayer:getSkillLoyalty(id - 1)))
    setSkillPercent(skillNames[id], (percent / 100), tr('You have %s percent to go', convertSkillPercent(10000 - percent)))
    setSkillBase(skillNames[id], level, localPlayer:getSkillBaseLevel(id - 1), localPlayer:getSkillLoyalty(id - 1))
end

function onBaseSkillChange(localPlayer, id, baseLevel)
    id = id + 1
    local t = {
        "Fist", "Club", "Sword", "Axe", "Distance", "Shielding", "Fishing"
    }

    -- imbues, ignore
    if id > #t then return end

    setSkillBase(id, localPlayer:getSkillLevel(id), baseLevel, localPlayer:getSkillLoyalty(id - 1))
end

function canUseManaShield()
    local player = g_game.getLocalPlayer()
    if player and player:useMagicShield() then
        return true
    end
    return useManaShield
end

function onVocationChange(player, vocation, oldVocation)
    useManaShield = table.contains({3, 4, 7, 8}, vocation)
    refresh()
end

function updateLevelTooltip(text)
    if not topBar then return end
    local experienceBar = topBar.Experience.progress
    experienceBar:setTooltip(text)
end

function isBottomBarActive()
    return topBar and topBar:isVisible() and currentDirection == "bottom"
end

function getCurrentHeight()
    return topBar and topBar:getHeight() or 0
end

function isCustomisableBarVisible()
    return topBar and topBar:isVisible()
end

function shouldShowCustomisableBar()
    if pendingVisibility ~= nil then
        return pendingVisibility
    end
    return isCustomisableBarsEnabled()
end

function isTopBarActive()
    return isCustomisableBarVisible() and currentDirection == "top"
end

function getCurrentDirection()
    return currentDirection
end

function onHarmonyChange(localPlayer, value)
    if not topBar then return end

    local harmonyPanel = topBar:recursiveGetChildById('harmony')
    local manaContainer = topBar:recursiveGetChildById('manaContainer')
    local stats = topBar:recursiveGetChildById('stats')
    local isHarmonyVisible = localPlayer.isMonk and localPlayer:isMonk() or false

    if not harmonyPanel or not manaContainer or not stats then
        return
    end

    harmonyPanel:setVisible(isHarmonyVisible)

    if isHarmonyVisible then
        if currentDirection == "left" or currentDirection == "right" then
            harmonyPanel:setSize("13 96")
            stats:setMarginBottom((currentLayout == 'compact' or currentLayout == 'large') and -49 or -55)
        else
            harmonyPanel:setSize("96 13")
            stats:setMarginLeft((currentLayout == 'compact' or currentLayout == 'large') and -5 or -5)
            if currentLayout == 'compact' or currentLayout == 'large' then
                manaContainer:setMarginLeft(6)
            end
        end
    else
        harmonyPanel:setSize("0 0")

        if currentDirection == "left" or currentDirection == "right" then
            stats:setMarginBottom(0)
        else
            stats:setMarginLeft((currentLayout == 'compact' or currentLayout == 'large') and -1 or 45)
            manaContainer:setMarginLeft((currentLayout == 'compact' or currentLayout == 'large') and -1 or 3)
        end
    end

    for i = 1, 5 do
        local harmonyIcon = harmonyPanel:recursiveGetChildById('harmony' .. i - 1)
        if harmonyIcon then
            harmonyIcon:setImageSource(value >= i and '/images/game/topbar/icon-combopoint-filled' or '/images/game/topbar/icon-combopoint-empty')
            harmonyIcon:setTooltip(tr('%d/5 Harmony\n\nHarmony is generated by specific abilities of your character.', math.min(5, value)))
        end
    end
end

function onSerenityChange(localPlayer, value)
    if not topBar then return end

    local serenityIcon = topBar:recursiveGetChildById('serenity')
    if serenityIcon then
        serenityIcon:setImageSource(value and '/images/game/topbar/icon-serene-on' or '/images/game/topbar/icon-serene-off')
        serenityIcon:setTooltip(value and tr('Your are serene.\n\nYou are serene if no more than 5 monsters or characters are directly beside you.\nYou are serene if no party members are in sight.') or tr('Your are not serene.\n\nYou are serene if no more than 5 monsters or characters are directly beside you.\nYou are serene if no party members are in sight.'))
    end
end

function onUpdateProficiencyWidget(hidePercentBar)
    if not topBar then return end

    local statsPanel = topBar:recursiveGetChildById('stats')
    local proficiencyPanel = topBar:recursiveGetChildById('proficiencyPanel')
    local proficiencyButton = topBar:recursiveGetChildById('proficiencyButton')

    if not proficiencyPanel or not proficiencyButton then
        return
    end

    if currentLayout == 'parallel' or currentLayout == "default" then
        if hidePercentBar then
            statsPanel:setMarginRight(45)
            proficiencyPanel:setSize(tosize("0 13"))
            proficiencyButton:setMarginRight(-4)
        else
            statsPanel:setMarginRight(-14)
            proficiencyPanel:setSize(tosize("103 13"))
            proficiencyPanel:setMarginRight(8)
            proficiencyButton:setMarginRight(3)
        end
    end
end

function switchCurrentLayout()
    if table.empty(lastProficiencyCache) then
        return
    end

    onUpdateProficiencyData(lastProficiencyCache.itemCache, lastProficiencyCache.hasUnnusedPerk, lastProficiencyCache.thingType)
end

function onUpdateProficiencyData(itemCache, hasUnnusedPerk, thingType)
    if not topBar then return end
    if not itemCache or not thingType then return end

    local proficiencyId = nil
    if thingType.getProficiencyId then
        proficiencyId = thingType:getProficiencyId()
    end
    if not proficiencyId and modules.game_proficiency and modules.game_proficiency.ProficiencyData then
        proficiencyId = modules.game_proficiency.ProficiencyData:getProficiencyIdForItem(thingType, thingType)
    end
    if not proficiencyId or proficiencyId <= 0 then return end

    local highlightButton = topBar:recursiveGetChildById('highlightProficiencyButton')
    local percentBar = topBar:recursiveGetChildById('starProgress')
    local percentLabel = topBar:recursiveGetChildById('proficiencyLabel')
    local proficiencyIcon = topBar:recursiveGetChildById('proficiencyIcon')

    local maxAvailableLevel = modules.game_proficiency.ProficiencyData:getPerkLaneCount(proficiencyId) + 2
    local weaponLevel = modules.game_proficiency.ProficiencyData:getCurrentLevelByExp(thingType, itemCache.exp, true)
    local percent = modules.game_proficiency.ProficiencyData:getLevelPercent(itemCache.exp, math.min(maxAvailableLevel, weaponLevel + 1), thingType)
    local maxLevelExperience = modules.game_proficiency.ProficiencyData:getMaxExperienceByLevel(math.min(maxAvailableLevel, weaponLevel + 1), thingType)

    if percentBar then
        percentBar:setPercent(percent)
        percentBar:setTooltip(string.format("Proficiency Progress: %s / %s", comma_value(itemCache.exp), comma_value(maxLevelExperience)))
    end

    if percentLabel then
        percentLabel:setText(percent .. "%")
    end

    if highlightButton then
        highlightButton:setVisible(hasUnnusedPerk)
    end

    if proficiencyIcon then 
        proficiencyIcon:setOn(hasUnnusedPerk)
    end

    modules.game_sidebuttons.onProficiencyHighlight(hasUnnusedPerk)
    lastProficiencyCache = { itemCache = itemCache, hasUnnusedPerk = hasUnnusedPerk, thingType = thingType}
end
