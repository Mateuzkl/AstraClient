imageSizeBroad = 0
imageSizeThin = 0

healthCircle = nil
manaCircle = nil
manaShieldCircle = nil
manaShieldCircleFront = nil
expCircle = nil
skillCircle = nil

healthCircleFront = nil
manaCircleFront = nil
expCircleFront = nil
skillCircleFront = nil

manaShieldImageSizeBroad = 0
manaShieldImageSizeThin = 0
manaShieldCircleOffsetX = -52
manaShieldCircleOffsetY = 7

optionPanel = nil

isHealthCircle = not g_settings.getBoolean('healthcircle_hpcircle')
isManaCircle = not g_settings.getBoolean('healthcircle_mpcircle')
isExpCircle = g_settings.getBoolean('healthcircle_expcircle')
isSkillCircle = g_settings.getBoolean('healthcircle_skillcircle')
skillTypes = g_settings.getNode('healthcircle_skilltypes')
skillsLoaded = false
local mapResizeEvents = {}
local healthCirclePositioned = false

if not skillTypes then
    skillTypes = {}
end

distanceFromCenter = g_settings.getNumber('healthcircle_distfromcenter') or 0
opacityCircle = g_settings.getNumber('healthcircle_opacity') or 0.35

local function normalizeShowOverride(value)
    return type(value) == 'boolean' and value or nil
end

local function getShowHealthManaCircleSetting(showOverride)
    showOverride = normalizeShowOverride(showOverride)
    if showOverride ~= nil then
        return showOverride
    end

    if TempOptions and type(TempOptions.getOption) == 'function' then
        local value = TempOptions:getOption('showHealthManaCircle')
        if value ~= nil then
            return toboolean(value)
        end
    end

    if GameOptions and type(GameOptions.getOption) == 'function' then
        local ok, value = pcall(GameOptions.getOption, GameOptions, 'showHealthManaCircle')
        if ok and value ~= nil then
            return toboolean(value)
        end
    end

    if m_settings and type(m_settings.getOption) == 'function' then
        local ok, value = pcall(m_settings.getOption, m_settings, 'showHealthManaCircle')
        if ok and value ~= nil then
            return toboolean(value)
        end
    end

    return g_settings.getBoolean('showHealthManaCircle')
end

local function disableMapNativeArcs()
    local mapPanel = modules.game_interface and modules.game_interface.getMapPanel and modules.game_interface.getMapPanel()
    if mapPanel and mapPanel.setShowArcs then
        mapPanel:setShowArcs(false)
    end
end

local function getMapPanel()
    return modules.game_interface and modules.game_interface.getMapPanel and modules.game_interface.getMapPanel()
end

local function hasValidMapGeometry(mapPanel)
    return mapPanel
        and mapPanel:getWidth() > 0
        and mapPanel:getHeight() > 0
        and imageSizeBroad > 0
        and imageSizeThin > 0
end

local function getBarDistance(mapHeight)
    local barDistance = 90
    if not (math.floor(mapHeight / 2 * 0.2) < 100) then
        barDistance = math.floor(mapHeight / 2 * 0.2)
    end
    return barDistance
end

local function hasStableMapGeometry(mapPanel)
    return hasValidMapGeometry(mapPanel)
end

local function hideHealthCircleWidgets()
    if healthCircle then healthCircle:setVisible(false) end
    if healthCircleFront then healthCircleFront:setVisible(false) end
    if type(setMonkWidgetsVisible) == 'function' then
        setMonkWidgetsVisible(false)
    end
end

local function hideManaCircleWidgets()
    if manaCircle then manaCircle:setVisible(false) end
    if manaCircleFront then manaCircleFront:setVisible(false) end
    if manaShieldCircle then manaShieldCircle:setVisible(false) end
    if manaShieldCircleFront then manaShieldCircleFront:setVisible(false) end
end

local function hideExtraCircleWidgets()
    if expCircle then expCircle:setVisible(false) end
    if expCircleFront then expCircleFront:setVisible(false) end
    if skillCircle then skillCircle:setVisible(false) end
    if skillCircleFront then skillCircleFront:setVisible(false) end
end

local function applyHealthManaCircleVisibility(showOverride)
    local mapPanel = getMapPanel()
    if not g_game.isOnline() or not healthCirclePositioned or not hasStableMapGeometry(mapPanel) or not getShowHealthManaCircleSetting(showOverride) then
        hideHealthCircleWidgets()
        hideManaCircleWidgets()
        return false
    end

    local useMonkWidgets = false
    if isHealthCircle and type(checkMonkVocation) == 'function' then
        useMonkWidgets = checkMonkVocation()
    end

    if healthCircle then healthCircle:setVisible(isHealthCircle and not useMonkWidgets) end
    if healthCircleFront then healthCircleFront:setVisible(isHealthCircle and not useMonkWidgets) end
    if type(setMonkWidgetsVisible) == 'function' then
        setMonkWidgetsVisible(isHealthCircle and useMonkWidgets)
    end

    if manaCircle then manaCircle:setVisible(isManaCircle) end
    if manaCircleFront then manaCircleFront:setVisible(isManaCircle) end
    if not isManaCircle then
        if manaShieldCircle then manaShieldCircle:setVisible(false) end
        if manaShieldCircleFront then manaShieldCircleFront:setVisible(false) end
    end

    return true
end

function init()
    g_ui.importStyle("game_healthcircle.otui")
    local mapPanel = modules.game_interface.getMapPanel()
    healthCircle = g_ui.createWidget('HealthCircle', mapPanel)
    manaCircle = g_ui.createWidget('ManaCircle', mapPanel)
    manaShieldCircle = g_ui.createWidget('ManaShieldCircle', mapPanel)
    expCircle = g_ui.createWidget('ExpCircle', mapPanel)
    skillCircle = g_ui.createWidget('SkillCircle', mapPanel)

    healthCircleFront = g_ui.createWidget('HealthCircleFront', mapPanel)
    manaCircleFront = g_ui.createWidget('ManaCircleFront', mapPanel)
    manaShieldCircleFront = g_ui.createWidget('ManaShieldCircleFront', mapPanel)
    expCircleFront = g_ui.createWidget('ExpCircleFront', mapPanel)
    skillCircleFront = g_ui.createWidget('SkillCircleFront', mapPanel)

    imageSizeBroad = healthCircle:getHeight()
    imageSizeThin = healthCircle:getWidth()
    manaShieldImageSizeBroad = manaShieldCircle:getHeight()
    manaShieldImageSizeThin = manaShieldCircle:getWidth()
    manaShieldCircle:setVisible(false)
    manaShieldCircleFront:setVisible(false)
    hideHealthCircleWidgets()
    hideManaCircleWidgets()

    initMonkWidgets()

    scheduleMapResizeUpdates()
    initOnHpAndMpChange()
    initOnGeometryChange()
    initOnLoginChange()

    if not isHealthCircle then
        healthCircle:setVisible(false)
        healthCircleFront:setVisible(false)
    end

    if not isManaCircle then
        manaCircle:setVisible(false)
        manaCircleFront:setVisible(false)
        manaShieldCircle:setVisible(false)
        manaShieldCircleFront:setVisible(false)
    end

    if not isExpCircle then
        expCircle:setVisible(false)
        expCircleFront:setVisible(false)
    end

    if not isSkillCircle then
        skillCircle:setVisible(false)
        skillCircleFront:setVisible(false)
    end

    handleShowArc(getShowHealthManaCircleSetting())

    addToOptionsModule()

    connect(g_game, {
        onGameStart = setPlayerValues,
        onGameEnd = resetHealthCircleLayout
    })

    if StatusIconBar and StatusIconBar.init then
        StatusIconBar.init()
    end
end

function terminate()
    healthCircle:destroy()
    healthCircle = nil
    manaCircle:destroy()
    manaCircle = nil
    manaShieldCircle:destroy()
    manaShieldCircle = nil
    expCircle:destroy()
    expCircle = nil
    skillCircle:destroy()
    skillCircle = nil

    healthCircleFront:destroy()
    healthCircleFront = nil
    manaCircleFront:destroy()
    manaCircleFront = nil
    manaShieldCircleFront:destroy()
    manaShieldCircleFront = nil
    expCircleFront:destroy()
    expCircleFront = nil
    skillCircleFront:destroy()
    skillCircleFront = nil

    terminateMonkWidgets()

    resetHealthCircleLayout()
    terminateOnHpAndMpChange()
    terminateOnGeometryChange()
    terminateOnLoginChange()

    destroyOptionsModule()

    disconnect(g_game, {
        onGameStart = setPlayerValues,
        onGameEnd = resetHealthCircleLayout
    })

    if StatusIconBar and StatusIconBar.terminate then
        StatusIconBar.terminate()
    end
end

function initOnHpAndMpChange()
    connect(LocalPlayer, {
        onHealthChange = whenHealthChange,
        onManaChange = whenManaChange,
        onSkillChange = whenSkillsChange,
        onManaShieldChange = whenManaShieldChange,
        onMagicLevelChange = whenSkillsChange,
        onLevelChange = whenSkillsChange,
    })
end

function terminateOnHpAndMpChange()
    disconnect(LocalPlayer, {
        onHealthChange = whenHealthChange,
        onManaChange = whenManaChange,
        onSkillChange = whenSkillsChange,
        onManaShieldChange = whenManaShieldChange,
        onMagicLevelChange = whenSkillsChange,
        onLevelChange = whenSkillsChange,
    })
end

function initOnGeometryChange()
    local mapPanel = modules.game_interface.getMapPanel()
    connect(mapPanel, {
        onGeometryChange = whenMapResizeChange,
        onVisibleDimensionChange = whenMapResizeChange
    })
end

function terminateOnGeometryChange()
    local mapPanel = modules.game_interface.getMapPanel()
    disconnect(mapPanel, {
        onGeometryChange = whenMapResizeChange,
        onVisibleDimensionChange = whenMapResizeChange
    })
end

function initOnLoginChange()
    connect(g_game, {
        onGameStart = scheduleMapResizeUpdates
    })
end

function terminateOnLoginChange()
    disconnect(g_game, {
        onGameStart = scheduleMapResizeUpdates
    })
end

function clearScheduledMapResizeUpdates()
    for _, event in pairs(mapResizeEvents) do
        removeEvent(event)
    end
    mapResizeEvents = {}
end

function resetHealthCircleLayout()
    clearScheduledMapResizeUpdates()
    healthCirclePositioned = false
    hideHealthCircleWidgets()
    hideManaCircleWidgets()
    hideExtraCircleWidgets()
end

function scheduleMapResizeUpdates(showOverride)
    clearScheduledMapResizeUpdates()
    whenMapResizeChange(showOverride)

    for _, delay in ipairs({50, 150, 350, 750, 1500, 3000, 5000, 8000, 12000}) do
        table.insert(mapResizeEvents, scheduleEvent(function()
            whenMapResizeChange(showOverride)
        end, delay))
    end
end

function whenHealthChange(showOverride)
    if not g_game.isOnline() or not healthCirclePositioned or not getShowHealthManaCircleSetting(showOverride) or not hasStableMapGeometry(getMapPanel()) then
        hideHealthCircleWidgets()
        return
    end

    if isMonkMode then
        whenMonkHealthChange()
        return
    end

    local player = g_game.getLocalPlayer()
    if not player then return end
    local maxHp = player:getMaxHealth()
    if maxHp <= 0 then return end
    local healthPercent = math.floor(player:getHealth() / maxHp * 100)

    local yhppc = math.floor(imageSizeBroad * (1 - (healthPercent / 100)))
    local restYhppc = imageSizeBroad - yhppc

    healthCircleFront:setY(healthCircle:getY() + yhppc)
    healthCircleFront:setHeight(restYhppc)
    healthCircleFront:setImageClip({
        x = 0,
        y = yhppc,
        width = imageSizeThin,
        height = restYhppc
    })

    healthCircle:setHeight(yhppc)
    healthCircle:setImageClip({
        x = 0,
        y = 0,
        width = imageSizeThin,
        height = yhppc
    })

    if healthPercent > 92 then
        healthCircleFront:setImageColor('#00BC00')
    elseif healthPercent > 60 then
        healthCircleFront:setImageColor('#50A150')
    elseif healthPercent > 30 then
        healthCircleFront:setImageColor('#A1A100')
    elseif healthPercent > 8 then
        healthCircleFront:setImageColor('#BF0A0A')
    elseif healthPercent > 3 then
        healthCircleFront:setImageColor('#910F0F')
    else
        healthCircleFront:setImageColor('#850C0C')
    end
end

local defaultManaCircleEmpty = '/data/images/game/healthcircle/right_empty'
local defaultManaCircleFull = '/data/images/game/healthcircle/right_full'
local defaultManaWithManaShieldCircleEmpty = '/data/images/game/healthcircle/right_tiny_empty'
local defaultManaWithManaShieldCircleFull = '/data/images/game/healthcircle/right_tiny_full'
local manaShieldManaCircleEmpty = '/data/images/game/healthcircle/right_extra_empty'
local manaShieldManaCircleFull = '/data/images/game/healthcircle/right_extra_full'

local function resetManaCircleImages()
    if manaCircle then
        manaCircle:setImageSource(defaultManaCircleEmpty)
    end
    if manaCircleFront then
        manaCircleFront:setImageSource(defaultManaCircleFull)
    end
end

local function updateManaShieldDisplay(showOverride)
    if not manaShieldCircle or not manaShieldCircleFront or not manaCircle or not manaCircleFront then
        return
    end

    if not g_game.isOnline() or not healthCirclePositioned or not isManaCircle or not getShowHealthManaCircleSetting(showOverride) or not hasStableMapGeometry(getMapPanel()) then
        manaShieldCircle:setVisible(false)
        manaShieldCircleFront:setVisible(false)
        resetManaCircleImages()
        return
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local remainingShield = player:getMagicShield() or 0
    local maxShield = player:getMaxMagicShield() or 0

    if remainingShield <= 0 then
        manaShieldCircle:setVisible(false)
        manaShieldCircleFront:setVisible(false)
        resetManaCircleImages()
        return
    end

    if maxShield <= 0 then
        maxShield = remainingShield
    end

    manaCircle:setImageSource(defaultManaWithManaShieldCircleEmpty)
    manaCircleFront:setImageSource(defaultManaWithManaShieldCircleFull)
    manaShieldCircle:setImageSource(manaShieldManaCircleEmpty)
    manaShieldCircleFront:setImageSource(manaShieldManaCircleFull)
    local geometryReady = hasStableMapGeometry(getMapPanel())
    manaShieldCircle:setVisible(geometryReady)
    manaShieldCircleFront:setVisible(geometryReady)

    local clampedShield = math.max(math.min(remainingShield, maxShield), 0)
    local shieldPercent = clampedShield / maxShield

    local emptyPixels = math.floor(manaShieldImageSizeBroad * (1 - shieldPercent))
    if emptyPixels < 0 then
        emptyPixels = 0
    end
    if emptyPixels > manaShieldImageSizeBroad then
        emptyPixels = manaShieldImageSizeBroad
    end

    local filledPixels = manaShieldImageSizeBroad - emptyPixels

    manaShieldCircleFront:setY(manaShieldCircle:getY() + emptyPixels)
    manaShieldCircleFront:setHeight(filledPixels)
    manaShieldCircleFront:setImageClip({
        x = 0,
        y = emptyPixels,
        width = manaShieldImageSizeThin,
        height = filledPixels
    })

    manaShieldCircle:setHeight(emptyPixels)
    manaShieldCircle:setImageClip({
        x = 0,
        y = 0,
        width = manaShieldImageSizeThin,
        height = emptyPixels
    })
end

function whenManaShieldChange()
    updateManaShieldDisplay()
end

function whenManaChange(showOverride)
    if not g_game.isOnline() or not healthCirclePositioned or not getShowHealthManaCircleSetting(showOverride) or not hasStableMapGeometry(getMapPanel()) then
        hideManaCircleWidgets()
        resetManaCircleImages()
        return
    end

    if g_game.isOnline() then
        local player = g_game.getLocalPlayer()
        if not player then return end
        local maxMana = player:getMaxMana()
        if maxMana <= 0 then
            manaCircle:setVisible(false)
            manaCircleFront:setVisible(false)
            if manaShieldCircle and manaShieldCircleFront then
                manaShieldCircle:setVisible(false)
                manaShieldCircleFront:setVisible(false)
            end
            resetManaCircleImages()
            return
        elseif isManaCircle then
            manaCircle:setVisible(true)
            manaCircleFront:setVisible(true)
        end

        updateManaShieldDisplay(showOverride)

        local manaPercent = math.floor(player:getMana() / maxMana * 100)

        local ymppc = math.floor(imageSizeBroad * (1 - (manaPercent / 100)))
        local restYmppc = imageSizeBroad - ymppc
        if restYmppc <= 0 then
            manaCircleFront:setVisible(false)
        else
            manaCircleFront:setVisible(isManaCircle)

            if isManaCircle then
                manaCircleFront:setY(manaCircle:getY() + ymppc)
                manaCircleFront:setHeight(restYmppc)
                manaCircleFront:setImageClip({
                    x = 0,
                    y = ymppc,
                    width = imageSizeThin,
                    height = restYmppc
                })
            end
        end

        manaCircle:setHeight(ymppc)
        manaCircle:setImageClip({
            x = 0,
            y = 0,
            width = imageSizeThin,
            height = ymppc
        })
    end
end

function whenSkillsChange()
    if g_game.isOnline() then
        if isExpCircle then
            local player = g_game.getLocalPlayer()
            if not player then return end
            local Xexpc = math.floor(imageSizeBroad * (1 - player:getLevelPercent() / 100))

            expCircleFront:setImageClip({
                x = 0,
                y = 0,
                width = imageSizeBroad - Xexpc,
                height = imageSizeThin
            })
            expCircleFront:setWidth(imageSizeBroad - Xexpc)

            expCircle:setImageClip({
                x = imageSizeBroad - Xexpc,
                y = 0,
                width = Xexpc,
                height = imageSizeThin
            })
            expCircle:setWidth(Xexpc)
            expCircle:setX(expCircleFront:getX() + expCircleFront:getWidth())
        end

        if isSkillCircle then
            local player = g_game.getLocalPlayer()
            if not player then return end

            local skillPercent
            local skillColor
            local skillType = skillTypes[player:getName()]

            if skillType == 'fist' then
                skillPercent = player:getSkillLevelPercent(0)
                skillColor = '#9900cc'
            elseif skillType == 'club' then
                skillPercent = player:getSkillLevelPercent(1)
                skillColor = '#cc3399'
            elseif skillType == 'sword' then
                skillPercent = player:getSkillLevelPercent(2)
                skillColor = '#FF7F00'
            elseif skillType == 'axe' then
                skillPercent = player:getSkillLevelPercent(3)
                skillColor = '#696969'
            elseif skillType == 'distance' then
                skillPercent = player:getSkillLevelPercent(4)
                skillColor = '#A62A2A'
            elseif skillType == 'shielding' then
                skillPercent = player:getSkillLevelPercent(5)
                skillColor = '#663300'
            elseif skillType == 'fishing' then
                skillPercent = player:getSkillLevelPercent(6)
                skillColor = '#ffff33'
            else
                skillPercent = player:getMagicLevelPercent()
                skillColor = '#00ffcc'
            end

            local Xskpc = math.floor(imageSizeBroad * (1 - skillPercent / 100))
            skillCircleFront:setImageColor(skillColor)

            skillCircleFront:setImageClip({
                x = 0,
                y = 0,
                width = imageSizeBroad - Xskpc,
                height = imageSizeThin
            })
            skillCircleFront:setWidth(imageSizeBroad - Xskpc)

            skillCircle:setImageClip({
                x = imageSizeBroad - Xskpc,
                y = 0,
                width = Xskpc,
                height = imageSizeThin
            })
            skillCircle:setWidth(Xskpc)
            skillCircle:setX(skillCircleFront:getX() + skillCircleFront:getWidth())
        end
    end
end

function whenMapResizeChange(showOverride)
    if g_game.isOnline() then
        local mapPanel = getMapPanel()
        if not hasStableMapGeometry(mapPanel) then
            healthCirclePositioned = false
            hideHealthCircleWidgets()
            hideManaCircleWidgets()
            hideExtraCircleWidgets()
            return false
        end

        local barDistance = getBarDistance(mapPanel:getHeight())
        local centerX = mapPanel:getX() + mapPanel:getWidth() / 2
        local centerY = mapPanel:getY() + mapPanel:getHeight() / 2

        local leftX = centerX - imageSizeThin - barDistance - distanceFromCenter
        local rightX = centerX + barDistance + distanceFromCenter
        local verticalY = centerY - imageSizeBroad / 2
        local horizontalX = centerX - imageSizeBroad / 2

        healthCircleFront:setX(leftX)
        manaCircleFront:setX(rightX)

        healthCircle:setX(leftX)
        manaCircle:setX(rightX)

        if manaShieldCircle and manaShieldCircleFront then
            manaShieldCircle:setX(manaCircle:getX() - manaShieldImageSizeThin - manaShieldCircleOffsetX)
            manaShieldCircleFront:setX(manaShieldCircle:getX())
        end

        healthCircle:setY(verticalY)
        manaCircle:setY(verticalY)

        if manaShieldCircle and manaShieldCircleFront then
            manaShieldCircle:setY(manaCircle:getY() + manaShieldCircleOffsetY)
            manaShieldCircleFront:setY(manaShieldCircle:getY())
        end

        if isExpCircle then
            local expY = centerY - imageSizeThin - barDistance - distanceFromCenter

            expCircleFront:setY(expY)
            expCircleFront:setX(horizontalX)
            expCircle:setX(horizontalX)
            expCircle:setY(expY)
        end
        if expCircle then expCircle:setVisible(isExpCircle) end
        if expCircleFront then expCircleFront:setVisible(isExpCircle) end

        if isSkillCircle then
            local skillY = centerY + barDistance + distanceFromCenter

            skillCircleFront:setY(skillY)
            skillCircleFront:setX(horizontalX)
            skillCircle:setX(horizontalX)
            skillCircle:setY(skillY)
        end
        if skillCircle then skillCircle:setVisible(isSkillCircle) end
        if skillCircleFront then skillCircleFront:setVisible(isSkillCircle) end

        healthCirclePositioned = true
        applyHealthManaCircleVisibility(showOverride)
        whenHealthChange(showOverride)
        whenManaChange(showOverride)
        if isExpCircle or isSkillCircle then
            whenSkillsChange()
        end

        positionMonkWidgets()
        return true
    end

    healthCirclePositioned = false
    hideHealthCircleWidgets()
    hideManaCircleWidgets()
    hideExtraCircleWidgets()
    updateManaShieldDisplay(showOverride)
    if StatusIconBar and StatusIconBar.updatePosition then
        StatusIconBar.updatePosition()
    end
    return false
end

function setHealthCircle(value)
    value = toboolean(value)
    isHealthCircle = value
    if value then
        if not whenMapResizeChange() then
            applyHealthManaCircleVisibility()
            scheduleMapResizeUpdates()
        end
        updateManaShieldDisplay()
    else
        hideHealthCircleWidgets()
    end

    g_settings.set('healthcircle_hpcircle', not value)
end

function setManaCircle(value)
    value = toboolean(value)
    isManaCircle = value
    if value then
        if not whenMapResizeChange() then
            applyHealthManaCircleVisibility()
            scheduleMapResizeUpdates()
        end
    else
        hideManaCircleWidgets()
        resetManaCircleImages()
    end

    g_settings.set('healthcircle_mpcircle', not value)
end

function handleShowArc(value)
    value = toboolean(value)
    disableMapNativeArcs()

    if value then
        isHealthCircle = true
        isManaCircle = true
        if healthCheckBox then healthCheckBox:setChecked(true) end
        if manaCheckBox then manaCheckBox:setChecked(true) end
        g_settings.set('healthcircle_hpcircle', false)
        g_settings.set('healthcircle_mpcircle', false)
    end

    whenMapResizeChange(value)
    applyHealthManaCircleVisibility(value)
    whenHealthChange(value)
    whenManaChange(value)
    updateManaShieldDisplay(value)
    scheduleMapResizeUpdates(value)
end

function setExpCircle(value)
    value = toboolean(value)
    isExpCircle = value

    if value then
        if not whenMapResizeChange() then
            scheduleMapResizeUpdates()
        end
    else
        expCircle:setVisible(false)
        expCircleFront:setVisible(false)
    end

    g_settings.set('healthcircle_expcircle', value)
end

function setSkillCircle(value)
    value = toboolean(value)
    isSkillCircle = value

    if value then
        if not whenMapResizeChange() then
            scheduleMapResizeUpdates()
        end
    else
        skillCircle:setVisible(false)
        skillCircleFront:setVisible(false)
    end

    g_settings.set('healthcircle_skillcircle', value)
end

function setSkillType(skill)
    if not skillsLoaded then
        return
    end

    local char = g_game.getCharacterName()

    skillTypes[char] = skill
    whenMapResizeChange()
    g_settings.setNode('healthcircle_skilltypes', skillTypes)
end

function setDistanceFromCenter(value)
    distanceFromCenter = value
    whenMapResizeChange()

    g_settings.set('healthcircle_distfromcenter', value)
end

local arcStyleSizes = { "small", "", "large" }

function setArcStyle(value)
    local size = arcStyleSizes[value + 1] or ""
    local prefix = size ~= "" and (size .. "-") or ""
    local function setImages(widget, frontWidget, name, imagePrefix)
        if not widget then return end
        imagePrefix = imagePrefix or prefix
        widget:setImageSource("/data/images/game/healthcircle/" .. imagePrefix .. name .. "_empty")
        if frontWidget then
            frontWidget:setImageSource("/data/images/game/healthcircle/" .. imagePrefix .. name .. "_full")
        end
    end
    setImages(healthCircle, healthCircleFront, "left")
    setImages(manaCircle, manaCircleFront, "right")
    setImages(expCircle, expCircleFront, "top", "")
    setImages(skillCircle, skillCircleFront, "bottom", "")
    imageSizeBroad = healthCircle:getHeight()
    imageSizeThin = healthCircle:getWidth()
    whenMapResizeChange()
    g_settings.set('healthcircle_style', value)
end

function setCircleOpacity(value)
    healthCircle:setOpacity(value)
    healthCircleFront:setOpacity(value)
    manaCircle:setOpacity(value)
    manaCircleFront:setOpacity(value)
    if manaShieldCircle then
        manaShieldCircle:setOpacity(value)
    end
    if manaShieldCircleFront then
        manaShieldCircleFront:setOpacity(value)
    end
    expCircle:setOpacity(value)
    expCircleFront:setOpacity(value)
    skillCircle:setOpacity(value)
    skillCircleFront:setOpacity(value)
    setMonkCircleOpacity(value)
    g_settings.set('healthcircle_opacity', value)
end

optionPanel = nil
healthCheckBox = nil
manaCheckBox = nil
experienceCheckBox = nil
skillCheckBox = nil
chooseSkillComboBox = nil
distFromCenScrollbar = nil
opacityScrollbar = nil

function addToOptionsModule()
    optionPanel = g_ui.loadUI('option_healthcircle')
    optionPanel:setVisible(false)

    healthCheckBox = optionPanel:recursiveGetChildById('healthCheckBox')
    manaCheckBox = optionPanel:recursiveGetChildById('manaCheckBox')
    experienceCheckBox = optionPanel:recursiveGetChildById('experienceCheckBox')
    skillCheckBox = optionPanel:recursiveGetChildById('skillCheckBox')
    chooseSkillComboBox = optionPanel:recursiveGetChildById('chooseSkillComboBox')
    distFromCenScrollbar = optionPanel:recursiveGetChildById('distFromCenScrollbar')
    opacityScrollbar = optionPanel:recursiveGetChildById('opacityScrollbar')

    chooseSkillComboBox:addOption('Magic Level', 'magic')
    chooseSkillComboBox:addOption('Fist Fighting', 'fist')
    chooseSkillComboBox:addOption('Club Fighting', 'club')
    chooseSkillComboBox:addOption('Sword Fighting', 'sword')
    chooseSkillComboBox:addOption('Axe Fighting', 'axe')
    chooseSkillComboBox:addOption('Distance Fighting', 'distance')
    chooseSkillComboBox:addOption('Shielding', 'shielding')
    chooseSkillComboBox:addOption('Fishing', 'fishing')

    healthCheckBox:setChecked(isHealthCircle)
    manaCheckBox:setChecked(isManaCircle)
    experienceCheckBox:setChecked(isExpCircle)
    skillCheckBox:setChecked(isSkillCircle)

    skillsLoaded = true

    -- Event handlers
    healthCheckBox.onCheckChange = function(self, checked)
        modules.game_healthcircle.setHealthCircle(checked)
    end
    manaCheckBox.onCheckChange = function(self, checked)
        modules.game_healthcircle.setManaCircle(checked)
    end
    experienceCheckBox.onCheckChange = function(self, checked)
        modules.game_healthcircle.setExpCircle(checked)
    end
    skillCheckBox.onCheckChange = function(self, checked)
        modules.game_healthcircle.setSkillCircle(checked)
    end

    chooseSkillComboBox.onOptionChange = function(self, text, data)
        modules.game_healthcircle.setSkillType(data)
    end

    distFromCenScrollbar:setValue(distanceFromCenter)
    distFromCenScrollbar.onValueChange = function(self, value)
        local lbl = self:getParent():getChildById('distLabel')
        if lbl then lbl:setText('Distance: ' .. value) end
        modules.game_healthcircle.setDistanceFromCenter(value)
    end

    opacityScrollbar:setValue(opacityCircle * 100)
    opacityScrollbar.onValueChange = function(self, value)
        local lbl = self:getParent():getChildById('opacityLabel')
        if lbl then lbl:setText('Opacity: ' .. value) end
        modules.game_healthcircle.setCircleOpacity(value / 100)
    end

    -- Spell effect opacity sliders
    local function setupSpellSlider(id, label, sourceFunc, settingKey)
        local scroll = optionPanel:recursiveGetChildById(id)
        if not scroll then return end
        local lbl = optionPanel:recursiveGetChildById(label)
        local saved = g_settings.getNumber(settingKey, 100)
        scroll:setValue(saved)
        if lbl then lbl:setText(lbl:getText():gsub('%d+%%', saved .. '%')) end
        scroll.onValueChange = function(self, value)
            if lbl then lbl:setText(lbl:getText():gsub('%d+%%', value .. '%')) end
            g_settings.set(settingKey, value)
            sourceFunc(value / 100.0)
        end
        sourceFunc(saved / 100.0)
    end
    setupSpellSlider('ownSpellScrollbar', 'ownSpellLabel', g_client.setOwnSpellEffectAlpha, 'spellOpacityOwn')
    setupSpellSlider('otherSpellScrollbar', 'otherSpellLabel', g_client.setOtherPlayerSpellEffectAlpha, 'spellOpacityOther')
    setupSpellSlider('creatureSpellScrollbar', 'creatureSpellLabel', g_client.setCreatureSpellEffectAlpha, 'spellOpacityCreature')
    setupSpellSlider('bossSpellScrollbar', 'bossSpellLabel', g_client.setBossAreaCreatureEffectAlpha, 'spellOpacityBoss')

    if distanceFromCenter == 0 then
        toggleOptionsPanel()
    end
end

function toggleOptionsPanel()
    if optionPanel then
        if not optionPanel:isVisible() then
            local displaySize = g_window.getDisplaySize()
            optionPanel:setX((displaySize.width - optionPanel:getWidth()) / 2)
            optionPanel:setY((displaySize.height - optionPanel:getHeight()) / 2)
        end
        optionPanel:setVisible(not optionPanel:isVisible())
    end
end

function updateStatsBar()
    -- Statsbar handled by game_healthinfo in AstraClient - noop
end

function setPlayerValues()
    local skillType = skillTypes[g_game.getCharacterName()]
    if not skillType then
        skillType = 'magic'
    end
    if chooseSkillComboBox then
        chooseSkillComboBox:setCurrentOptionByData(skillType, true)
    end
    handleShowArc(getShowHealthManaCircleSetting())
end

function destroyOptionsModule()
    healthCheckBox = nil
    manaCheckBox = nil
    experienceCheckBox = nil
    skillCheckBox = nil
    chooseSkillComboBox = nil
    distFromCenScrollbar = nil
    opacityScrollbar = nil

    if optionPanel then
        optionPanel:destroy()
        optionPanel = nil
    end
end
