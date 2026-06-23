-- Info Banner - OTUI-based popup for client events (level up, skill, achievement, etc.)
-- Ported from mehah PR #1604, adapted for AstraClient

local CONTAINER_W = 420
local CONTAINER_H = 110
local ICON_SIZE = 72
local ICON_X = 50
local ICON_Y = 8
local PAPER_X = 52
local PAPER_Y = 16
local PAPER_W = 355
local PAPER_H = 80
local ANIM_W = 21
local TITLE_X = 136
local TITLE_Y = 27
local TITLE_W = 235
local TITLE_H = 18
local DESC_X = 126
local DESC_Y = 47
local DESC_W = 235
local DESC_H = 40
local FRAME_MS = 40
local HOLD_MS = 3500
local FADE_MS = 300
local FADE_INTERVAL = 20
local MARGIN_TOP = 45

local ASSETS = "/modules/game_notifications/assets/images"

local OPEN_FRAMES = {}
for i = 0, 7 do
    OPEN_FRAMES[i + 1] = ASSETS .. "/infobanner/backdrop-infobanner-anim" .. i .. ".png"
end
local TOTAL_FRAMES = #OPEN_FRAMES

local SkillId = { Magic = 1, Sword = 2, Club = 3, Axe = 4, Fist = 5, Distance = 6, Shielding = 7, Fishing = 8 }
local skillNames = {
    [SkillId.Magic]    = { name = "Magic Level",       icon = "magic" },
    [SkillId.Sword]    = { name = "Sword Fighting",    icon = "sword" },
    [SkillId.Club]     = { name = "Club Fighting",     icon = "club" },
    [SkillId.Axe]      = { name = "Axe Fighting",      icon = "axe" },
    [SkillId.Fist]     = { name = "Fist Fighting",     icon = "fist" },
    [SkillId.Distance] = { name = "Distance Fighting", icon = "distance" },
    [SkillId.Shielding]= { name = "Shielding",         icon = "shielding" },
    [SkillId.Fishing]  = { name = "Fishing",           icon = "fishing" },
}

local Cat = {
    SIMPLE = 1, ACHIEVEMENT = 2, TITLE = 3, LEVEL = 4, SKILL = 5,
    BESTIARY = 6, BOSSTIARY = 7, QUEST = 8, COSMETIC = 9, PROFICIENCY = 10,
}
local Evt = {
    ATTACKSTOPPED = 9, CAPACITYLIMIT = 10, OUTOFAMMO = 11,
    TARGETTOOCLOSE = 12, OUTOFSOULPOINTS = 13, TUTORIALCOMPLETE = 14,
}

local popups = {
    [Cat.SIMPLE] = {
        [Evt.CAPACITYLIMIT]  = { title = "Capacity Limit",   desc = "Remove items before adding new ones.", ico = "icon-infobanner-hint" },
        [Evt.OUTOFAMMO]      = { title = "Out of Ammunition",desc = "You have no arrow or bolt equipped.", ico = "icon-infobanner-hint" },
        [Evt.TARGETTOOCLOSE] = { title = "Target Too Close",  desc = "You are using ranged attack at melee distance.", ico = "icon-infobanner-hint" },
        [Evt.OUTOFSOULPOINTS]= { title = "Out of Soul Points",desc = "You don't have enough soul points.", ico = "icon-infobanner-hint" },
        [Evt.TUTORIALCOMPLETE]= { title = "Off to New Shores",desc = "Leave the village to start your adventure.", ico = "icon-infobanner-offtonewshores" },
    },
    [Cat.LEVEL]       = { title = "Level %d!", desc = "You gained hit points, mana, and capacity.", ico = "icon-infobanner-levelup" },
    [Cat.SKILL]       = { title = "%s",         desc = "Your skill advanced to level %d.",           ico = "icon-infobanner-skill-%s" },
    [Cat.ACHIEVEMENT] = { title = "New Achievement", desc = "You have earned '%s'",                ico = "icon-infobanner-achievements" },
    [Cat.TITLE]       = { title = "Title Gained",    desc = "You have earned '%s'",                ico = "icon-infobanner-title" },
    [Cat.QUEST] = {
        completed = { title = "Quest Completed", desc = "You have finished '%s'", ico = "icon-infobanner-quests" },
        started   = { title = "Quest Started",   desc = "You have begun '%s'",     ico = "icon-infobanner-quests" },
    },
    [Cat.BESTIARY]    = { title = "Bestiary",   desc = "Progress: %s",            ico = "icon-infobanner-bestiary" },
    [Cat.BOSSTIARY]   = { title = "Bosstiary",  desc = "Progress: %s",            ico = "icon-infobanner-bosstiary" },
    [Cat.COSMETIC]    = { title = "Outfit Unlocked",  desc = "You have unlocked '%s'",          ico = "icon-infobanner-unlock" },
    [Cat.PROFICIENCY] = { title = "Proficiency",      desc = "You have improved '%s'",           ico = "icon-infobanner-unlock" },
}

local state = "idle"
local queue = {}
local bannerEvent = nil
local ui = {}

local function cancelEvent()
    if bannerEvent then removeEvent(bannerEvent); bannerEvent = nil end
end

local function hideBanner()
    if ui.container then ui.container:hide() end
end

local function showBanner()
    if ui.container then ui.container:show() end
end

local function updatePosition()
    if not ui.container then return end
    local mp = modules.game_interface.getMapPanel()
    if not mp then return end
    local x = math.floor((mp:getWidth() - CONTAINER_W) / 2)
    ui.container:setMarginLeft(x)
    ui.container:setMarginTop(MARGIN_TOP)
end

local function icon(path)
    return ASSETS .. "/nodo/" .. path .. ".png"
end

local function createUI()
    local mp = modules.game_interface.getMapPanel()
    if not mp then return end

    ui.container = g_ui.createWidget('UIWidget', mp)
    ui.container:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    ui.container:addAnchor(AnchorTop, 'parent', AnchorTop)
    ui.container:setWidth(CONTAINER_W)
    ui.container:setHeight(CONTAINER_H)
    ui.container:setPhantom(true)
    ui.container:hide()

    ui.paper = g_ui.createWidget('UIWidget', ui.container)
    ui.paper:setImageSource(ASSETS .. "/infobanner/backdrop-infobanner-bottom")
    ui.paper:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    ui.paper:addAnchor(AnchorTop, 'parent', AnchorTop)
    ui.paper:setMarginLeft(PAPER_X)
    ui.paper:setMarginTop(PAPER_Y)
    ui.paper:setWidth(0)
    ui.paper:setHeight(PAPER_H)

    ui.anim = g_ui.createWidget('UIWidget', ui.container)
    ui.anim:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    ui.anim:addAnchor(AnchorTop, 'parent', AnchorTop)
    ui.anim:setMarginLeft(PAPER_X)
    ui.anim:setMarginTop(0)
    ui.anim:setWidth(ANIM_W)
    ui.anim:setHeight(CONTAINER_H)
    ui.anim:setImageSource(OPEN_FRAMES[1])

    ui.iconW = g_ui.createWidget('UIWidget', ui.container)
    ui.iconW:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    ui.iconW:addAnchor(AnchorTop, 'parent', AnchorTop)
    ui.iconW:setMarginLeft(ICON_X)
    ui.iconW:setMarginTop(ICON_Y)
    ui.iconW:setWidth(ICON_SIZE)
    ui.iconW:setHeight(ICON_SIZE)
    ui.iconW:setOpacity(0)

    ui.titleW = g_ui.createWidget('UILabel', ui.container)
    ui.titleW:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    ui.titleW:addAnchor(AnchorTop, 'parent', AnchorTop)
    ui.titleW:setMarginLeft(TITLE_X)
    ui.titleW:setMarginTop(TITLE_Y)
    ui.titleW:setWidth(TITLE_W)
    ui.titleW:setHeight(TITLE_H)
    ui.titleW:setTextAlign(AlignCenter)
    ui.titleW:setColor('#FFE1B5')
    ui.titleW:setOpacity(0)
    if ui.titleW.setFont then ui.titleW:setFont("terminus-14px-bold") end

    ui.descW = g_ui.createWidget('UILabel', ui.container)
    ui.descW:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    ui.descW:addAnchor(AnchorTop, 'parent', AnchorTop)
    ui.descW:setMarginLeft(DESC_X)
    ui.descW:setMarginTop(DESC_Y)
    ui.descW:setWidth(DESC_W)
    ui.descW:setHeight(DESC_H)
    ui.descW:setTextAlign(AlignCenter)
    ui.descW:setColor('#c0c0c0')
    ui.descW:setOpacity(0)
    if ui.descW.setTextWrap then ui.descW:setTextWrap(true) end

    updatePosition()
end

local function setPaperWidth(w)
    if not ui.paper then return end
    ui.paper:setWidth(w)
end

local function setContentOpacity(op)
    if ui.titleW then ui.titleW:setOpacity(op) end
    if ui.descW then ui.descW:setOpacity(op) end
end

local function setIconOpacity(op)
    if ui.iconW then ui.iconW:setOpacity(op) end
end

local function processNext()
    cancelEvent()
    if #queue == 0 then state = "idle"; hideBanner(); return end
    local d = table.remove(queue, 1)
    if not ui.container or ui.container:isDestroyed() then state = "idle"; return end

    updatePosition()
    showBanner()
    setPaperWidth(0)
    setContentOpacity(0)
    setIconOpacity(0)
    ui.anim:show()
    ui.anim:setMarginLeft(PAPER_X)
    ui.anim:setImageSource(OPEN_FRAMES[1])
    if ui.iconW and d.icon then ui.iconW:setImageSource(d.icon) end
    if ui.titleW    then ui.titleW:setText(d.title or "") end
    if ui.descW     then ui.descW:setText(d.desc or "") end

    state = "opening"
    animateOpen(d.holdMs)
end

function animateOpen(holdMs)
    local frame = 1
    local iconShown = false

    local function step()
        if not ui.container or ui.container:isDestroyed() then cancelEvent(); return end
        frame = frame + 1
        if frame > TOTAL_FRAMES then
            setPaperWidth(PAPER_W)
            ui.anim:hide()
            state = "holding"
            local t0 = g_clock.millis()
            local function fadeIn()
                if not ui.container or ui.container:isDestroyed() then return end
                local t = math.min(1, (g_clock.millis() - t0) / FADE_MS)
                setContentOpacity(t)
                if t < 1 then bannerEvent = scheduleEvent(fadeIn, FADE_INTERVAL)
                else bannerEvent = scheduleEvent(close, holdMs) end
            end
            bannerEvent = scheduleEvent(fadeIn, FADE_INTERVAL)
            return
        end
        local p = (frame - 1) / (TOTAL_FRAMES - 1)
        local w = math.floor(PAPER_W * p)
        setPaperWidth(w)
        ui.anim:setMarginLeft(PAPER_X + w - ANIM_W + 5)
        ui.anim:setImageSource(OPEN_FRAMES[frame])
        if not iconShown and p >= 0.15 then setIconOpacity(1); iconShown = true end
        bannerEvent = scheduleEvent(step, FRAME_MS)
    end
    bannerEvent = scheduleEvent(step, FRAME_MS)
end

function close()
    if not ui.container or ui.container:isDestroyed() then return end
    cancelEvent()
    state = "closing"
    local t0 = g_clock.millis()
    local function fadeOut()
        if not ui.container or ui.container:isDestroyed() then return end
        local t = math.min(1, (g_clock.millis() - t0) / FADE_MS)
        setContentOpacity(1 - t)
        if t < 1 then bannerEvent = scheduleEvent(fadeOut, FADE_INTERVAL)
        else animateClose() end
    end
    bannerEvent = scheduleEvent(fadeOut, FADE_INTERVAL)
end

function animateClose()
    local frame = TOTAL_FRAMES
    local iconHidden = false
    ui.anim:show()
    local function step()
        if not ui.container or ui.container:isDestroyed() then return end
        frame = frame - 1
        if frame < 1 then
            setPaperWidth(0)
            ui.anim:setMarginLeft(PAPER_X)
            ui.anim:setImageSource(OPEN_FRAMES[1])
            hideBanner()
            state = "idle"
            processNext()
            return
        end
        local p = (frame - 1) / (TOTAL_FRAMES - 1)
        local w = math.floor(PAPER_W * p)
        setPaperWidth(w)
        ui.anim:setMarginLeft(PAPER_X + w - ANIM_W + 5)
        ui.anim:setImageSource(OPEN_FRAMES[frame])
        if not iconHidden and p <= 0.15 then setIconOpacity(0); iconHidden = true end
        bannerEvent = scheduleEvent(step, FRAME_MS)
    end
    bannerEvent = scheduleEvent(step, FRAME_MS)
end

function show(title, desc, iconSrc, holdMs)
    if not ui.container then createUI() end
    if not ui.container then return end
    table.insert(queue, {title=title, desc=desc, icon=iconSrc, holdMs=holdMs or HOLD_MS})
    if state == "idle" then processNext() end
end

-- Event handler
local function onClientEvent(cat, ...)
    g_logger.info('[infobanner] onClientEvent cat=' .. tostring(cat))
    local args = {...}
    local bestiary = modules.game_cyclopedia and modules.game_cyclopedia.Bestiary
    if bestiary and bestiary.onClientEvent then
        bestiary.onClientEvent(cat, args[1], args[2])
    end

    local tpl
    if cat == Cat.SIMPLE then tpl = popups[Cat.SIMPLE][args[1]]
    elseif cat == Cat.QUEST then tpl = popups[Cat.QUEST][(args[2] == 1 or args[2] == true) and 'completed' or 'started']
    else tpl = popups[cat] end
    if not tpl then return end

    local title = tpl.title or ""
    local desc = tpl.desc or ""
    local iconName = tpl.ico or "icon-infobanner-achievements"

    if cat == Cat.SKILL then
        local data = skillNames[args[1]] or {name="Skill",icon="fist"}
        title = data.name
        desc = string.format(tpl.desc, tonumber(args[2]) or 0)
        iconName = "icon-infobanner-skill-" .. data.icon
    elseif cat == Cat.LEVEL then
        title = string.format(tpl.title, tonumber(args[1]) or 0)
    elseif cat == Cat.QUEST then
        title = string.format(tpl.title, tostring(args[1] or ""))
        desc  = string.format(tpl.desc, tostring(args[1] or ""))
    elseif cat == Cat.ACHIEVEMENT or cat == Cat.TITLE then
        desc = string.format(tpl.desc, tostring(args[1] or ""))
    elseif cat == Cat.COSMETIC then
        desc = string.format(tpl.desc, tostring(args[2] or ""))
    elseif cat == Cat.PROFICIENCY then
        desc = string.format(tpl.desc, tostring(args[2] or ""))
    elseif cat == Cat.BESTIARY or cat == Cat.BOSSTIARY then
        desc = string.format(tpl.desc, tostring(args[2] or ""))
    end

    show(title, desc, icon(iconName))
end

-- Module
infobanner = {}

function infobanner.init()
    createUI()
    g_game.onClientEvent = onClientEvent
end

function infobanner.terminate()
    cancelEvent()
    g_game.onClientEvent = nil
    queue = {}
    state = "idle"
    if ui.container then ui.container:destroy(); ui.container = nil end
    ui = {}
end

function infobanner.show(title, desc, iconPath)
    show(title, desc, iconPath)
end

function infobanner.testpopup(eventType)
    eventType = eventType or 'level'
    if eventType == 'level' then onClientEvent(Cat.LEVEL, 100)
    elseif eventType == 'skill' then onClientEvent(Cat.SKILL, SkillId.Sword, 80)
    elseif eventType == 'achievement' then onClientEvent(Cat.ACHIEVEMENT, 'Test Achievement')
    elseif eventType == 'title' then onClientEvent(Cat.TITLE, 'Test Title')
    elseif eventType == 'quest' then onClientEvent(Cat.QUEST, 'Test Quest', 1)
    elseif eventType == 'simple' then onClientEvent(Cat.SIMPLE, Evt.CAPACITYLIMIT)
    else onClientEvent(Cat.LEVEL, 100) end
end
