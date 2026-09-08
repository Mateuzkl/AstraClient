-- EloriaBot player scripting. User code runs in a restricted environment and
-- receives only the compatibility API assembled in buildEnvironment().
local scripting = {}

modules.game_helper = modules.game_helper or {}
modules.game_helper.scripting = scripting
_Helper = _Helper or {}
_Helper.Scripting = scripting

-- A single ZeroBot panel script routinely builds 100+ widgets (a row of
-- icon/label/status per feature), so the old cap of 100 rejected them outright.
local MAX_HUDS = 500
local MAX_TIMERS = 100
local MAX_CALLBACKS = 100
-- Loading a script builds its whole UI in one go, so it gets a much larger
-- budget than a per-tick callback does.
local LOAD_TIME_LIMIT = 5000
local CALL_TIME_LIMIT = 250
local MAX_TEXT_LENGTH = 4096
local MAX_SCRIPT_BYTES = 256 * 1024
local SCRIPT_SLOTS = 5

local panel = nil
local slots = {}
local updatingUI = false
local hudRecords = {}
local timerRecords = {}
local timersByName = {}
local eventCallbacks = {}
-- Numeric ids shared with scripting_compat.lua (ZeroBot's Game.Events).
local EVENT_HUD_CLICK = 2
local EVENT_HUD_DRAG = 15
local EVENT_CUSTOM_MODAL_CLICK = 6
local hudCount = 0
local timerCount = 0
local nextHudId = 1

local DEFAULT_SCRIPT = [[-- EloriaBot HUD example
local status = HUD(20, 20, "Eloria HUD", true)
status:setColor(80, 220, 120)
status:setFontSize(12)
status:setDraggable(true)

Timer("hud-status", function()
  status:setText(string.format("HP: %d%%  Mana: %d%%",
    Player.getHealthPercent(), Player.getManaPercent()))
end, 250)
]]

-- ZeroBot's HUD text defaults to 8.25px and accepts any size; this maps a
-- requested size onto the nearest face this client actually ships.
--
-- One family throughout, so changing size changes only the size. This is the
-- antialiased Verdana the rest of the client UI uses (verdana-11px-antialised
-- is the client's `default: true` font). The visually similar "rounded" faces
-- are deliberately avoided here: verdana-7px-rounded carries `spacing: -2 -3`
-- so its letters overlap, and verdana-8px-rounded is pointed at the smaller
-- action-bar glyph atlas rather than its own full sheet.
local HUD_FONT_LADDER = {
  { size = 8, font = 'Verdana-8px-antialiased' },
  { size = 9, font = 'Verdana-9px-antialiased' },
  { size = 10, font = 'Verdana-10px-antialiased' },
  { size = 11, font = 'verdana-11px-antialised' },
  { size = 13, font = 'Verdana Bold-13px' },
  { size = 16, font = 'sans-bold-16px' }
}
local HUD_DEFAULT_FONT_SIZE = 8.25

local function fontForSize(size)
  size = tonumber(size) or HUD_DEFAULT_FONT_SIZE
  local best, bestDistance = HUD_FONT_LADDER[1].font, math.huge
  for _, entry in ipairs(HUD_FONT_LADDER) do
    local distance = math.abs(entry.size - size)
    if distance < bestDistance then best, bestDistance = entry.font, distance end
  end
  return best
end

local function clamp(value, minimum, maximum)
  value = tonumber(value) or minimum
  return math.max(minimum, math.min(maximum, value))
end

local function showStatus(message, isError)
  message = tostring(message or ''):sub(1, 512)
  local label = panel and panel:recursiveGetChildById('scriptingStatus') or nil
  if label then
    label:setText(message)
    label:setColor(isError and '#d94a3a' or '#62c462')
  end
  if isError and g_logger and g_logger.error then
    g_logger.error('[EloriaBot Scripting] ' .. message)
  elseif g_logger and g_logger.info then
    g_logger.info('[EloriaBot Scripting] ' .. message)
  end
end

-- Script code runs directly on the main thread, guarded by a wall-clock
-- budget. It deliberately does NOT run in a coroutine: this client's Lua
-- binding layer (LuaInterface::luaCppFunctionCallback) ignores the lua_State
-- it is handed and always operates on the main thread's stack, so any bound
-- C++ call made from inside a coroutine corrupts that stack and takes the
-- client down. This is why wait() cannot suspend a script here.
local function protectedCall(budget, callback, ...)
  if not debug or not debug.sethook then
    return pcall(callback, ...)
  end

  local started = g_clock.realMillis()
  local overran = false
  debug.sethook(function()
    if g_clock.realMillis() - started > budget then
      overran = true
      error('script exceeded the ' .. budget .. ' ms execution limit')
    end
  end, '', 10000)
  local ok, result = pcall(callback, ...)
  debug.sethook()

  -- Report the overrun even when the script caught it with its own pcall, so
  -- a runaway loop cannot quietly hide behind a pcall and look healthy.
  if overran then
    return false, 'script exceeded the ' .. budget .. ' ms execution limit'
  end
  return ok, result
end

local function safeScriptCall(label, callback, ...)
  local ok, result = protectedCall(CALL_TIME_LIMIT, callback, ...)
  if not ok then
    showStatus(label .. ': ' .. tostring(result), true)
    return nil
  end
  return result
end

local function getMapPanel()
  return modules.game_interface and modules.game_interface.gameMapPanel
end

local function dispatchEvent(eventId, ...)
  -- The custom modal window class routes its own clicks first, exactly like
  -- ZeroBot registers onCustomModalButtonOnClick behind the scenes.
  if eventId == EVENT_CUSTOM_MODAL_CLICK and _Helper.ScriptingCompat then
    safeScriptCall('custom modal click', _Helper.ScriptingCompat.onCustomModalButtonClick, ...)
  end
  local callbacks = eventCallbacks[eventId]
  if not callbacks then return end
  -- Iterate a copy: a callback may register or unregister during dispatch.
  local snapshot = {}
  for index, callback in ipairs(callbacks) do snapshot[index] = callback end
  for _, callback in ipairs(snapshot) do
    safeScriptCall('event ' .. tostring(eventId), callback, ...)
  end
end

-- Entry point used by scripting_compat.lua's native game hooks.
function scripting.dispatch(eventId, ...)
  dispatchEvent(eventId, ...)
end

local function requireHud(object)
  local record = hudRecords[object]
  if not record or record.destroyed or not record.widget or record.widget:isDestroyed() then
    return nil
  end
  return record
end

local function applyHudPosition(record)
  local widget = record.widget
  local parentWidget = widget:getParent()
  if not parentWidget then return end
  local parentRect = parentWidget:getRect()
  local x, y = record.marginX, record.marginY

  if record.horizontalAlignment == 2 then
    x = math.floor(parentRect.width / 2 - widget:getWidth() / 2 + record.marginX)
  elseif record.horizontalAlignment == 3 then
    x = parentRect.width - widget:getWidth() - record.marginX
  end
  if record.verticalAlignment == 2 then
    y = math.floor(parentRect.height / 2 - widget:getHeight() / 2 + record.marginY)
  elseif record.verticalAlignment == 3 then
    y = parentRect.height - widget:getHeight() - record.marginY
  end

  widget:breakAnchors()
  widget:move(parentRect.x + x, parentRect.y + y)
end

local zOrderPending = false

local function refreshHudZOrder()
  local ordered = {}
  for _, record in pairs(hudRecords) do
    if not record.destroyed and record.widget and not record.widget:isDestroyed() then
      table.insert(ordered, record)
    end
  end
  table.sort(ordered, function(left, right)
    if left.zIndex == right.zIndex then return left.id < right.id end
    return left.zIndex < right.zIndex
  end)
  for _, record in ipairs(ordered) do
    local parentWidget = record.widget:getParent()
    if parentWidget then
      parentWidget:moveChildToIndex(record.widget, parentWidget:getChildCount())
    end
  end
end

-- Coalesce the re-sort to once per frame. A panel script that creates a
-- hundred widgets and sets a z-index on each would otherwise re-sort and
-- reparent every widget a hundred times over, which alone blew the execution
-- budget before the script had finished loading.
local function requestHudZOrder()
  if zOrderPending then return end
  zOrderPending = true
  scheduleEvent(function()
    zOrderPending = false
    refreshHudZOrder()
  end, 0)
end

local function updateSpellIcon(record, spellId)
  record.spellId = math.floor(tonumber(spellId) or 0)
  local spell, profile = Spells.getSpellByIcon(record.spellId)
  local icon = spell and spell.icon and SpellIcons[spell.icon]
  if not icon then
    record.widget:setImageSource('')
    return false
  end
  profile = profile or 'Default'
  record.widget:setImageSource(SpelllistSettings[profile].iconsFolder)
  record.widget:setImageClip(Spells.getImageClipNormal(icon[1], profile))
  return true
end

local HudMethods = {}
local HudMeta = { __index = HudMethods }

function HudMethods:getId()
  local record = hudRecords[self] or self.__hudId
  if type(record) == 'table' then return record.id end
  return record
end

function HudMethods:getPos()
  local record = requireHud(self)
  if not record then return nil end
  local parentRect = record.widget:getParent():getRect()
  return { x = record.widget:getX() - parentRect.x, y = record.widget:getY() - parentRect.y }
end

function HudMethods:setPos(x, y)
  local record = requireHud(self)
  if not record then return end
  record.marginX = math.floor(tonumber(x) or 0)
  record.marginY = math.floor(tonumber(y) or 0)
  applyHudPosition(record)
end

function HudMethods:getMargins()
  local record = requireHud(self)
  return record and record.newFeatures and { x = record.marginX, y = record.marginY } or nil
end

function HudMethods:hide()
  local record = requireHud(self)
  if record then record.widget:hide() end
end

function HudMethods:show()
  local record = requireHud(self)
  if record then record.widget:show() end
end

function HudMethods:setDraggable(value)
  local record = requireHud(self)
  if not record then return end
  record.draggable = value == true
  record.widget:setDraggable(record.draggable)
end

function HudMethods:setText(value)
  local record = requireHud(self)
  if not record or record.kind ~= 'text' then return end
  record.widget:setText(tostring(value or ''):sub(1, MAX_TEXT_LENGTH))
  record.widget:resizeToText()
  applyHudPosition(record)
end

function HudMethods:setHorizontalAlignment(value)
  local record = requireHud(self)
  if not record or not record.newFeatures then return end
  record.horizontalAlignment = math.floor(clamp(value, 0, 3))
  applyHudPosition(record)
end

function HudMethods:setVerticalAlignment(value)
  local record = requireHud(self)
  if not record or not record.newFeatures then return end
  record.verticalAlignment = math.floor(clamp(value, 0, 3))
  applyHudPosition(record)
end

function HudMethods:setColor(r, g, b)
  local record = requireHud(self)
  if not record or record.kind ~= 'text' then return end
  record.widget:setColor(string.format('#%02x%02x%02x',
    math.floor(clamp(r, 0, 255)), math.floor(clamp(g, 0, 255)), math.floor(clamp(b, 0, 255))))
end

function HudMethods:setFontSize(value)
  local record = requireHud(self)
  if not record or record.kind ~= 'text' then return end
  record.fontSize = clamp(value, 7, 16)
  record.widget:setFont(fontForSize(record.fontSize))
  record.widget:resizeToText()
  applyHudPosition(record)
end

function HudMethods:setItemId(value)
  local record = requireHud(self)
  if record and record.kind == 'item' then
    record.widget:setItemId(math.floor(clamp(value, 0, 65535)))
  end
end

function HudMethods:setSpellIconId(value)
  local record = requireHud(self)
  if record and record.kind == 'spell' and record.newFeatures then updateSpellIcon(record, value) end
end

local function applyOutfit(record)
  record.widget:setOutfit(record.outfit)
end

function HudMethods:setOutfitId(value)
  local record = requireHud(self)
  if not record or record.kind ~= 'outfit' or not record.newFeatures then return end
  record.outfit.type = math.floor(clamp(value, 0, 65535))
  applyOutfit(record)
end

function HudMethods:setOutfitAddons(value)
  local record = requireHud(self)
  if not record or record.kind ~= 'outfit' or not record.newFeatures then return end
  record.outfit.addons = math.floor(clamp(value, 0, 3))
  applyOutfit(record)
end

function HudMethods:setOutfitColors(head, body, legs, feet)
  local record = requireHud(self)
  if not record or record.kind ~= 'outfit' or not record.newFeatures then return end
  record.outfit.head = math.floor(clamp(head, 0, 132))
  record.outfit.body = math.floor(clamp(body, 0, 132))
  record.outfit.legs = math.floor(clamp(legs, 0, 132))
  record.outfit.feet = math.floor(clamp(feet, 0, 132))
  applyOutfit(record)
end

function HudMethods:setOutfitDirection(value)
  local record = requireHud(self)
  if record and record.kind == 'outfit' and record.newFeatures then
    record.widget:setDirection(math.floor(clamp(value, 0, 3)))
  end
end

function HudMethods:setOutfitMoving(value)
  local record = requireHud(self)
  if record and record.kind == 'outfit' and record.newFeatures and record.widget.setAnimate then
    record.widget:setAnimate(value == true)
  end
end

function HudMethods:setSize(width, height)
  local record = requireHud(self)
  if not record then return end
  record.baseWidth = math.floor(clamp(width, 1, 512))
  record.baseHeight = math.floor(clamp(height, 1, 512))
  record.widget:setSize({ width = math.floor(record.baseWidth * record.scale), height = math.floor(record.baseHeight * record.scale) })
  applyHudPosition(record)
end

function HudMethods:setScale(value)
  local record = requireHud(self)
  if not record or record.kind == 'text' or not record.newFeatures then return end
  record.scale = clamp(value, 0.1, 8)
  self:setSize(record.baseWidth, record.baseHeight)
end

function HudMethods:setOpacity(value)
  local record = requireHud(self)
  if record and record.newFeatures then record.widget:setOpacity(clamp(value, 0, 1)) end
end

function HudMethods:setBackgroundColor(r, g, b)
  local record = requireHud(self)
  if not record or not record.newFeatures then return end
  record.widget:setBackgroundColor(string.format('#%02x%02x%02x',
    math.floor(clamp(r, 0, 255)), math.floor(clamp(g, 0, 255)), math.floor(clamp(b, 0, 255))))
end

function HudMethods:setBorderColor(r, g, b)
  local record = requireHud(self)
  if not record or not record.newFeatures then return end
  record.widget:setBorderColor(string.format('#%02x%02x%02x',
    math.floor(clamp(r, 0, 255)), math.floor(clamp(g, 0, 255)), math.floor(clamp(b, 0, 255))))
end

function HudMethods:setBorderWidth(value)
  local record = requireHud(self)
  if record and record.newFeatures then record.widget:setBorderWidth(math.floor(clamp(value, 0, 8))) end
end

function HudMethods:setZIndex(value)
  local record = requireHud(self)
  if not record or not record.newFeatures then return end
  record.zIndex = math.floor(clamp(value, -10000, 10000))
  requestHudZOrder()
end

function HudMethods:setPhantom(value)
  local record = requireHud(self)
  if record and record.newFeatures then record.widget:setPhantom(value == true) end
end

function HudMethods:setCallback(callback)
  local record = requireHud(self)
  if record then record.callback = type(callback) == 'function' and callback or nil end
end

function HudMethods:destroy()
  local record = hudRecords[self]
  if not record or record.destroyed then return end
  record.destroyed = true
  self.__hudId = record.id
  if record.widget and not record.widget:isDestroyed() then record.widget:destroy() end
  hudRecords[self] = nil
  hudCount = math.max(0, hudCount - 1)
end

local function createHud(kind, x, y, value, newFeatures)
  if hudCount >= MAX_HUDS then error('HUD limit reached (' .. MAX_HUDS .. ')') end
  local parentWidget = getMapPanel()
  if not parentWidget then error('game window is not available') end

  local widgetType = kind == 'text' and 'UILabel' or
    (kind == 'item' and 'UIItem' or (kind == 'outfit' and 'UICreature' or 'UIWidget'))
  local widget = g_ui.createWidget(widgetType, parentWidget)
  widget.eloriaBotScriptWidget = true
  widget:setPhantom(false)
  widget:setFocusable(false)
  widget:setDraggable(false)

  local object = setmetatable({}, HudMeta)
  local size = kind == 'text' and 1 or (kind == 'outfit' and 48 or 32)
  local record = {
    id = nextHudId, kind = kind, widget = widget, newFeatures = newFeatures == true,
    marginX = math.floor(tonumber(x) or 0), marginY = math.floor(tonumber(y) or 0),
    horizontalAlignment = 0, verticalAlignment = 0, baseWidth = size, baseHeight = size,
    scale = 1, zIndex = 0, draggable = false, destroyed = false,
    outfit = { type = 0, head = 0, body = 0, legs = 0, feet = 0, addons = 0 }
  }
  nextHudId = nextHudId + 1
  hudCount = hudCount + 1
  hudRecords[object] = record

  widget:setSize({ width = size, height = size })
  if kind == 'text' then
    record.fontSize = HUD_DEFAULT_FONT_SIZE
    widget:setFont(fontForSize(HUD_DEFAULT_FONT_SIZE))
    widget:setTextAutoResize(true)
    object:setText(value)
  elseif kind == 'item' then
    widget:setVirtual(true)
    object:setItemId(value)
  elseif kind == 'spell' then
    updateSpellIcon(record, value)
  elseif kind == 'outfit' then
    record.newFeatures = true
    object:setOutfitId(value)
  end

  widget.onMouseRelease = function(_, _, button)
    if button ~= MouseLeftButton then return false end
    if record.dragMoved then
      record.dragMoved = false
      return true
    end
    if record.callback then safeScriptCall('HUD callback', record.callback) end
    dispatchEvent(EVENT_HUD_CLICK, record.id)
    return true
  end
  widget.onDragEnter = function(_, mousePos)
    if not record.draggable then return false end
    record.dragMoved = false
    record.dragOffset = { x = mousePos.x - widget:getX(), y = mousePos.y - widget:getY() }
    return true
  end
  widget.onDragMove = function(_, mousePos)
    if not record.draggable or not record.dragOffset then return false end
    widget:move(mousePos.x - record.dragOffset.x, mousePos.y - record.dragOffset.y)
    record.dragMoved = true
    local parentRect = parentWidget:getRect()
    local px, py = widget:getX() - parentRect.x, widget:getY() - parentRect.y
    record.marginX, record.marginY = math.floor(px), math.floor(py)
    record.horizontalAlignment, record.verticalAlignment = 0, 0
    dispatchEvent(EVENT_HUD_DRAG, record.id, px, py)
    return true
  end
  widget.onDragLeave = function()
    if not record.draggable then return false end
    local parentRect = parentWidget:getRect()
    local px, py = widget:getX() - parentRect.x, widget:getY() - parentRect.y
    record.marginX, record.marginY = math.floor(px), math.floor(py)
    record.horizontalAlignment, record.verticalAlignment = 0, 0
    record.dragOffset = nil
    dispatchEvent(EVENT_HUD_DRAG, record.id, px, py)
    return true
  end
  widget.onGeometryChange = function()
    if not widget:isDragging() then applyHudPosition(record) end
  end

  applyHudPosition(record)
  requestHudZOrder()
  return object
end

local function buildHudClass()
  local hud = {}
  hud.newPanel = function(x, y, width, height)
    local panel = createHud('panel', x, y, nil, true)
    panel:setSize(width, height)
    return panel
  end
  hud.new = function(x, y, value, newFeatures)
    return createHud(type(value) == 'number' and 'item' or 'text', x, y, value, newFeatures)
  end
  hud.newSpellIcon = function(x, y, spellId, newFeatures)
    return createHud('spell', x, y, spellId, newFeatures)
  end
  hud.newOutfit = function(x, y, outfitId, newFeatures)
    return createHud('outfit', x, y, outfitId, newFeatures)
  end
  return setmetatable(hud, { __call = function(_, ...) return hud.new(...) end })
end

local TimerMethods = {}
local TimerMeta = { __index = TimerMethods }

local function removeTimer(timer)
  local record = timerRecords[timer]
  if not record or record.destroyed then return end
  record.active = false
  record.destroyed = true
  record.generation = record.generation + 1
  if record.event then removeEvent(record.event); record.event = nil end
  if timersByName[record.timerName] == timer then timersByName[record.timerName] = nil end
  timerRecords[timer] = nil
  timerCount = math.max(0, timerCount - 1)
end

function TimerMethods:run()
  local record = timerRecords[self]
  if not record or record.destroyed then return nil end
  return safeScriptCall('timer ' .. record.timerName, record.callback)
end

function TimerMethods:name()
  local record = timerRecords[self]
  return record and record.timerName or nil
end

function TimerMethods:start()
  local record = timerRecords[self]
  if not record or record.destroyed then return end
  if record.event then removeEvent(record.event); record.event = nil end
  record.active = true
  record.generation = record.generation + 1
  local generation = record.generation
  local function tick()
    if record.destroyed or not record.active or record.generation ~= generation then return end
    self:run()
    record.event = scheduleEvent(tick, record.delay)
  end
  record.event = scheduleEvent(tick, record.delay)
end

function TimerMethods:stop()
  local record = timerRecords[self]
  if not record then return end
  record.active = false
  record.generation = record.generation + 1
  if record.event then removeEvent(record.event); record.event = nil end
end

function TimerMethods:isActive()
  local record = timerRecords[self]
  return record and record.active == true and not record.destroyed or false
end

function TimerMethods:update(delayTime)
  local record = timerRecords[self]
  if not record then return end
  record.delay = math.floor(clamp(delayTime, 10, 3600000))
  if record.active then self:stop(); self:start() end
end

local function buildTimerClass(environment)
  local timerClass = {}
  timerClass.new = function(name, callback, delayTime, autoStart)
    name = tostring(name or '')
    if name == '' then error('Timer name cannot be empty') end
    if type(callback) == 'string' then callback = environment[callback] end
    if type(callback) ~= 'function' then return timersByName[name] end
    if timersByName[name] then removeTimer(timersByName[name]) end
    if timerCount >= MAX_TIMERS then error('Timer limit reached (' .. MAX_TIMERS .. ')') end
    local timer = setmetatable({}, TimerMeta)
    timerRecords[timer] = {
      timerName = name, callback = callback, delay = math.floor(clamp(delayTime or 100, 10, 3600000)),
      active = false, generation = 0, destroyed = false, event = nil
    }
    timersByName[name] = timer
    timerCount = timerCount + 1
    if autoStart ~= false then timer:start() end
    return timer
  end
  return setmetatable(timerClass, { __call = function(_, ...) return timerClass.new(...) end })
end

local function copyPosition(position)
  return position and { x = position.x, y = position.y, z = position.z } or nil
end

local function buildEnvironment(scriptName)
  local safeMath, safeString, safeTable, safeBit, safeBit32 = {}, {}, {}, {}, {}
  for key, value in pairs(math) do safeMath[key] = value end
  for key, value in pairs(string) do safeString[key] = value end
  for key, value in pairs(table) do safeTable[key] = value end
  for key, value in pairs(bit or {}) do safeBit[key] = value end
  for key, value in pairs(bit32 or {}) do safeBit32[key] = value end

  local environment = {
    assert = assert, error = error, ipairs = ipairs, next = next, pairs = pairs,
    pcall = pcall, select = select, tonumber = tonumber, tostring = tostring,
    type = type, unpack = unpack, xpcall = xpcall, math = safeMath, string = safeString,
    table = safeTable, bit = safeBit, bit32 = safeBit32,
    os = { time = os.time, difftime = os.difftime, date = os.date, clock = os.clock },
    JSON = { encode = json.encode, decode = json.decode },
    Enums = {
      HorizontalAlign = { None = 0, Left = 1, Center = 2, Right = 3 },
      VerticalAlign = { None = 0, Top = 1, Center = 2, Bottom = 3 },
      Directions = {
        NORTH = 0, EAST = 1, SOUTH = 2, WEST = 3,
        NORTH_EAST = 4, SOUTH_EAST = 5, SOUTH_WEST = 6, NORTH_WEST = 7
      },
      TalkTypes = { SAY = 1, WHISPER = 2, YELL = 3, PRIVATE = 5, CHANNEL = 7, NPC = 11 },
      InventorySlot = {
        HEAD = 1, NECKLACE = 2, BACKPACK = 3, ARMOR = 4, RIGHT_HAND = 5,
        LEFT_HAND = 6, LEGS = 7, FEET = 8, RING = 9, AMMO = 10, PURSE = 11
      },
      PartyIcons = {
        SHIELD_NONE = 0,
        SHIELD_WHITEYELLOW = 1,
        SHIELD_WHITEBLUE = 2,
        SHIELD_BLUE = 3,
        SHIELD_YELLOW = 4,
        SHIELD_BLUE_SHAREDEXP = 5,
        SHIELD_YELLOW_SHAREDEXP = 6,
        SHIELD_BLUE_NOSHAREDEXP_BLINK = 7,
        SHIELD_YELLOW_NOSHAREDEXP_BLINK = 8,
        SHIELD_BLUE_NOSHAREDEXP = 9,
        SHIELD_YELLOW_NOSHAREDEXP = 10,
        SHIELD_GRAY = 11
      },
      FightMode = { OFFENSIVE = 1, BALANCED = 2, DEFENSIVE = 3 },
      ChaseMode = { STAND = 0, CHASE = 1 }
    }
  }

  -- ZeroBot gives each script its own thread, so its wait() simply blocks.
  -- There is no equivalent here: scripts share the client's main thread, and
  -- the only way to suspend one would be a coroutine, which this client's Lua
  -- bindings cannot survive (see protectedCall above). Blocking the thread
  -- instead would freeze the game. So wait() returns false without pausing,
  -- and says so once, rather than silently pretending the delay happened.
  local warnedAboutWait = false
  environment.wait = function()
    if not warnedAboutWait then
      warnedAboutWait = true
      showStatus('[' .. scriptName .. '] wait() does not pause here - use a Timer instead', true)
    end
    return false
  end
  environment.sleep = environment.wait
  environment.delay = environment.wait

  environment.print = function(...)
    local values = {}
    for index = 1, select('#', ...) do values[index] = tostring(select(index, ...)) end
    showStatus('[' .. scriptName .. '] ' .. table.concat(values, '\t'), false)
  end
  environment.HUD = buildHudClass()
  environment.Timer = buildTimerClass(environment)
  environment.destroyTimer = function(name) removeTimer(timersByName[tostring(name)]) end
  environment.Player = {
    getId = function() local p = g_game.getLocalPlayer(); return p and p:getId() or 0 end,
    getName = function() local p = g_game.getLocalPlayer(); return p and p:getName() or nil end,
    getHealth = function() local p = g_game.getLocalPlayer(); return p and p:getHealth() or 0 end,
    getMana = function() local p = g_game.getLocalPlayer(); return p and p:getMana() or 0 end,
    getHealthPercent = function() local p = g_game.getLocalPlayer(); return p and p:getHealthPercent() or 0 end,
    getManaPercent = function()
      local p = g_game.getLocalPlayer()
      if not p then return 0 end
      local maximum = p:getMaxMana()
      return maximum > 0 and math.floor(p:getMana() * 100 / maximum) or 100
    end,
    getCapacity = function() local p = g_game.getLocalPlayer(); return p and p:getFreeCapacity() or 0 end,
    getSoulPoints = function() local p = g_game.getLocalPlayer(); return p and p:getSoul() or 0 end,
    getStamina = function() local p = g_game.getLocalPlayer(); return p and p:getStamina() or 0 end,
    getLevel = function() local p = g_game.getLocalPlayer(); return p and p:getLevel() or 0 end,
    getExperience = function() local p = g_game.getLocalPlayer(); return p and p:getExperience() or 0 end,
    getTargetId = function() local c = g_game.getAttackingCreature(); return c and c:getId() or 0 end,
    getFollowId = function() local c = g_game.getFollowingCreature(); return c and c:getId() or 0 end,
    getPosition = function() local p = g_game.getLocalPlayer(); return p and copyPosition(p:getPosition()) or nil end
  }
  environment.Client = {
    isConnected = function() return g_game.isOnline() end,
    getLatency = function() return g_game.getPing() end,
    getServerLatency = function() return g_game.getPing() end,
    getFps = function() return g_app.getFps() end,
    getVersion = function() return tostring(g_game.getClientVersion()) end,
    getGameWindowDimensions = function()
      local mapPanel = getMapPanel()
      local rect = mapPanel and mapPanel:getRect() or { width = 0, height = 0 }
      return { x = 0, y = 0, width = rect.width, height = rect.height }
    end,
    showMessage = function(message)
      if modules.game_textmessage then
        modules.game_textmessage.displayGameMessage(tostring(message):sub(1, 512))
      end
    end
  }
  environment.Spells = {
    getIdByName = function(name)
      local wanted = tostring(name or ''):lower()
      for _, spell in ipairs(Spells.getSpellList()) do
        if tostring(spell.name or ''):lower() == wanted then return spell.id or -1 end
      end
      return -1
    end,
    getIdByWords = function(words)
      local spell = Spells.getSpellByWords(tostring(words or ''))
      return spell and spell.id or -1
    end,
    getDataById = function(id)
      local spell = Spells.getSpellByClientId(tonumber(id) or -1)
      if not spell then return nil end
      local vocations, groups = {}, {}
      for index, vocation in ipairs(spell.vocations or {}) do vocations[index] = vocation end
      for groupId in pairs(spell.group or {}) do table.insert(groups, groupId) end
      table.sort(groups)
      return {
        id = spell.id, name = spell.name, words = spell.words,
        primaryGroup = groups[1], secondaryGroup = groups[2], vocations = vocations
      }
    end,
    isInCooldown = function(id)
      return modules.game_cooldown and modules.game_cooldown.isCooldownIconActive and
        modules.game_cooldown.isCooldownIconActive(tonumber(id) or -1) or false
    end,
    getLeftCooldownTime = function() return -1 end,
    getLeftGroupCooldownTime = function() return -1 end,
    groupIsInCooldown = function() return false end
  }
  environment.Game = { Events = { HUD_CLICK = EVENT_HUD_CLICK, HUD_DRAG = EVENT_HUD_DRAG } }
  environment.Game.registerEvent = function(eventId, callback)
    eventId = tonumber(eventId)
    if not eventId or type(callback) ~= 'function' then return false end
    eventCallbacks[eventId] = eventCallbacks[eventId] or {}
    if #eventCallbacks[eventId] >= MAX_CALLBACKS then error('event callback limit reached') end
    table.insert(eventCallbacks[eventId], callback)
    if _Helper.ScriptingCompat then _Helper.ScriptingCompat.onEventRegistered(eventId) end
    -- ZeroBot returns the callback so scripts can hold on to it for
    -- unregisterEvent; returning true here would break that idiom.
    return callback
  end
  environment.Game.unregisterEvent = function(eventId, callback)
    local callbacks = eventCallbacks[tonumber(eventId) or -1]
    if not callbacks then return false end
    for index = #callbacks, 1, -1 do
      if callbacks[index] == callback then table.remove(callbacks, index) end
    end
    return true
  end
  if _Helper.ScriptingActions then _Helper.ScriptingActions.install(environment) end
  if _Helper.ScriptingCompat then _Helper.ScriptingCompat.install(environment) end
  return environment
end

local function runSandboxedScript(code, scriptName)
  if type(code) ~= 'string' or code:len() == 0 then return true end
  if code:len() > MAX_SCRIPT_BYTES then return false, 'script exceeds the 256 KB limit' end
  local environment = buildEnvironment(scriptName or 'Script')
  if code:byte(1) == 27 then return false, 'precompiled bytecode is not allowed' end
  local chunk, compileError = load(code, scriptName or 'Script', 't', environment)
  if not chunk then return false, compileError end
  return protectedCall(LOAD_TIME_LIMIT, chunk)
end

local function destroyRuntime()
  local timers = {}
  for timer in pairs(timerRecords) do table.insert(timers, timer) end
  for _, timer in ipairs(timers) do removeTimer(timer) end

  local huds = {}
  for object in pairs(hudRecords) do table.insert(huds, object) end
  for _, object in ipairs(huds) do object:destroy() end

  eventCallbacks = {}
  if _Helper.ScriptingCompat then _Helper.ScriptingCompat.reset() end
end

local function normalizeSlots(config)
  local normalized = {}
  for index = 1, SCRIPT_SLOTS do
    local saved = type(config) == 'table' and config[index] or nil
    normalized[index] = {
      name = type(saved) == 'table' and tostring(saved.name or ('Script ' .. index)):sub(1, 40) or ('Script ' .. index),
      enabled = type(saved) == 'table' and saved.enabled == true or false,
      code = type(saved) == 'table' and type(saved.code) == 'string' and saved.code or (index == 1 and DEFAULT_SCRIPT or '')
    }
  end
  return normalized
end

local function syncPanel()
  if not panel then return end
  updatingUI = true
  for index = 1, SCRIPT_SLOTS do
    local row = panel:recursiveGetChildById('scriptSlot' .. index)
    if row then
      local enabled = row:getChildById('enabled')
      local name = row:getChildById('name')
      if enabled then enabled:setChecked(slots[index].enabled) end
      if name then name:setText(slots[index].name) end
      local number = row:getChildById('slotNumber')
      local status = row:getChildById('slotStatus')
      local accent = row:getChildById('accent')
      local active = slots[index].enabled
      if number then number:setText(string.format('%02d', index)) end
      if status then
        status:setText(active and tr('Enabled') or tr('Disabled'))
        status:setColor(active and '#62c462' or '#aaaaaa')
      end
      if accent then accent:setVisible(false) end
    end
  end
  updatingUI = false
end

function scripting.reload()
  if not g_game.isOnline() then
    destroyRuntime()
    showStatus('Scripts stopped (offline).', false)
    return
  end

  local running = 0
  local firstError = nil
  -- Restart after a failure so any HUDs/timers created before that error are
  -- removed. Each failed slot is disabled, so this converges in at most 5 passes.
  for _ = 1, SCRIPT_SLOTS + 1 do
    destroyRuntime()
    running = 0
    local failedThisPass = false
    for _, slot in ipairs(slots) do
      if slot.enabled and slot.code ~= '' then
        local ok, scriptError = runSandboxedScript(slot.code, slot.name)
        if ok then
          running = running + 1
        else
          slot.enabled = false
          firstError = firstError or (slot.name .. ': ' .. tostring(scriptError))
          failedThisPass = true
          break
        end
      end
    end
    if not failedThisPass then break end
  end

  syncPanel()
  if firstError then
    local config = _Helper.getHelperConfig and _Helper.getHelperConfig() or nil
    if config then config.scriptingScripts = scripting.getConfig() end
    if _Helper.saveSettings then _Helper.saveSettings() end
    showStatus(firstError, true)
  elseif running > 0 then
    showStatus('Running ' .. running .. ' script(s).', false)
  else
    showStatus('No scripts enabled.', false)
  end
end

function scripting.stopAll()
  for _, slot in ipairs(slots) do slot.enabled = false end
  destroyRuntime()
  syncPanel()
  local config = _Helper.getHelperConfig and _Helper.getHelperConfig() or nil
  if config then config.scriptingScripts = scripting.getConfig() end
  if _Helper.saveSettings then _Helper.saveSettings() end
  showStatus('All scripts stopped.', false)
end

function scripting.getConfig()
  local result = {}
  for index, slot in ipairs(slots) do
    result[index] = { name = slot.name, enabled = slot.enabled == true, code = slot.code }
  end
  return result
end

function scripting.loadConfig(config)
  slots = normalizeSlots(config)
  syncPanel()
  scripting.reload()
end

local function persistAndReload()
  local config = _Helper.getHelperConfig and _Helper.getHelperConfig() or nil
  if config then config.scriptingScripts = scripting.getConfig() end
  if _Helper.saveSettings then _Helper.saveSettings() end
  scripting.reload()
end

local function editSlot(index)
  local slot = slots[index]
  if not slot or not modules.client_textedit then return end
  modules.client_textedit.edit(slot.code, {
    title = slot.name,
    description = 'EloriaBot script. Available: HUD, Timer, Game, Map, Player, Creature, Container, Inventory, Client and Spells.',
    multiline = true,
    width = 700
  }, function(text)
    if text:len() > MAX_SCRIPT_BYTES then
      showStatus('Script is larger than 256 KB and was not saved.', true)
      return
    end
    slot.code = text
    persistAndReload()
  end)
end

function scripting.init(widget)
  panel = widget
  slots = normalizeSlots(slots)
  if not panel then return end

  for index = 1, SCRIPT_SLOTS do
    local row = panel:recursiveGetChildById('scriptSlot' .. index)
    if row then
      local enabled = row:getChildById('enabled')
      local name = row:getChildById('name')
      local edit = row:getChildById('edit')
      if enabled then
        enabled.onCheckChange = function(widget)
          if updatingUI then return end
          slots[index].enabled = widget:isChecked()
          persistAndReload()
        end
      end
      if name then
        -- Keep the slot model current before Edit/Save, Reload or a checkbox
        -- rebuilds the rows. Focus-loss notifications alone are not reliable
        -- when opening the modal editor or hiding the parent window.
        name.onTextChange = function(widget)
          if updatingUI then return end
          local value = widget:getText():gsub('^%s+', ''):gsub('%s+$', '')
          slots[index].name = value ~= '' and value:sub(1, 40) or ('Script ' .. index)
        end
        name.onFocusChange = function(widget, focused)
          if updatingUI or focused then return end
          local value = widget:getText():gsub('^%s+', ''):gsub('%s+$', '')
          slots[index].name = value ~= '' and value:sub(1, 40) or ('Script ' .. index)
          widget:setText(slots[index].name)
          local config = _Helper.getHelperConfig and _Helper.getHelperConfig() or nil
          if config then config.scriptingScripts = scripting.getConfig() end
          if _Helper.saveSettings then _Helper.saveSettings() end
        end
      end
      if edit then edit.onClick = function() editSlot(index) end end
    end
  end

  local reloadButton = panel:recursiveGetChildById('scriptingReload')
  local stopButton = panel:recursiveGetChildById('scriptingStop')
  if reloadButton then reloadButton.onClick = scripting.reload end
  if stopButton then stopButton.onClick = scripting.stopAll end
  syncPanel()
end

function scripting.terminate()
  destroyRuntime()
  if _Helper.ScriptingCompat and _Helper.ScriptingCompat.terminate then
    _Helper.ScriptingCompat.terminate()
  end
  if _Helper.ScriptingActions then _Helper.ScriptingActions.reset() end
  panel = nil
end

function scripting.onGameEnd()
  destroyRuntime()
  if _Helper.ScriptingActions then _Helper.ScriptingActions.reset() end
  showStatus('Scripts stopped (offline).', false)
end
