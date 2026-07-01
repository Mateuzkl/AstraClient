-- @docfuncs @{

function print(...)
  local msg = ""
  local args = {...}
  local appendSpace = #args > 1
  for i,v in ipairs(args) do
    msg = msg .. tostring(v)
    if appendSpace and i < #args then
      msg = msg .. '    '
    end
  end
  g_logger.log(LogInfo, msg)
end

function pinfo(msg)
  g_logger.log(LogInfo, msg)
end

function perror(msg)
  g_logger.log(LogError, msg)
end

function pwarning(msg)
  g_logger.log(LogWarning, msg)
end

pwarn = pwarning

function pdebug(msg)
  g_logger.log(LogDebug, msg)
end

function fatal(msg)
  g_logger.log(LogFatal, msg)
end

function exit()
  g_app.exit()
end

function quit()
  g_app.exit()
end

function connect(object, arg1, arg2, arg3)
  local signalsAndSlots
  local pushFront
  if type(arg1) == 'string' then
    signalsAndSlots = { [arg1] = arg2 }
    pushFront = arg3
  else
    signalsAndSlots = arg1
    pushFront = arg2
  end

  if not signalsAndSlots then
    signalsAndSlots = {}
  end

  for signal,slot in pairs(signalsAndSlots) do
    if not object[signal] then
      local mt = getmetatable(object)
      if mt and type(object) == 'userdata' then
        object[signal] = function(...)
          return signalcall(mt[signal], ...)
        end
      end
    end

    if not object[signal] then
      object[signal] = slot
    elseif type(object[signal]) == 'function' then
      object[signal] = { object[signal] }
    end

    if type(slot) ~= 'function' then
      perror(debug.traceback('unable to connect a non function value'))
    end

    if type(object[signal]) == 'table' then
      if pushFront then
        table.insert(object[signal], 1, slot)
      else
        table.insert(object[signal], #object[signal]+1, slot)
      end
    end
  end
end

function disconnect(object, arg1, arg2)
  if arg1 == nil then return true end
  local signalsAndSlots
  if type(arg1) == 'string' then
    if arg2 == nil then
      object[arg1] = nil
      return
    end
    signalsAndSlots = { [arg1] = arg2 }
  elseif type(arg1) == 'table' then
    signalsAndSlots = arg1
  else
	perror(debug.traceback('unable to disconnect'))
  end

  for signal,slot in pairs(signalsAndSlots) do
    if not object[signal] then
    elseif type(object[signal]) == 'function' then
      if object[signal] == slot then
        object[signal] = nil
      end
    elseif type(object[signal]) == 'table' then
      for k,func in pairs(object[signal]) do
        if func == slot then
          table.remove(object[signal], k)

          if #object[signal] == 1 then
            object[signal] = object[signal][1]
          end
          break
        end
      end
    end
  end
end

function newclass(name)
  if not name then
    perror(debug.traceback('new class has no name.'))
  end

  local class = {}
  function class.internalCreate()
    local instance = {}
    for k,v in pairs(class) do
      instance[k] = v
    end
    return instance
  end
  class.create = class.internalCreate
  class.__class = name
  class.getClassName = function() return name end
  return class
end

function extends(base, name)
  if not name then
    perror(debug.traceback('extended class has no name.'))
  end

  local derived = {}
  function derived.internalCreate()
    local instance = base.create()
    for k,v in pairs(derived) do
      instance[k] = v
    end
    return instance
  end
  derived.create = derived.internalCreate
  derived.__class = name
  derived.getClassName = function() return name end
  return derived
end

function runinsandbox(func, ...)
  if type(func) == 'string' then
    func, err = loadfile(resolvepath(func, 2))
    if not func then
      error(err)
    end
  end
  local env = { }
  local oldenv = getfenv(0)
  setmetatable(env, { __index = oldenv } )
  setfenv(0, env)
  func(...)
  setfenv(0, oldenv)
  return env
end

local function module_loader(modname)
  local module = g_modules.getModule(modname)
  if not module then
    return '\n\tno module \'' .. modname .. '\''
  end
  return function()
    if not module:load() then
      error('unable to load required module ' .. modname)
    end
    return module:getSandbox()
  end
end
table.insert(package.loaders, 1, module_loader)

function import(table)
  assert(type(table) == 'table')
  local env = getfenv(2)
  for k,v in pairs(table) do
    env[k] = v
  end
end

function export(what, key)
  if key ~= nil then
    _G[key] = what
  else
    for k,v in pairs(what) do
      _G[k] = v
    end
  end
end

function unexport(key)
  if type(key) == 'table' then
    for _k,v in pairs(key) do
      _G[v] = nil
    end
  else
    _G[key] = nil
  end
end

function getfsrcpath(depth)
  depth = depth or 2
  local info = debug.getinfo(1+depth, "Sn")
  local path
  if info.short_src then
    path = info.short_src:match("(.*)/.*")
  end
  if not path then
    path = '/'
  elseif path:sub(0, 1) ~= '/' then
    path = '/' .. path
  end
  return path
end

function resolvepath(filePath, depth)
  if not filePath then return nil end
  depth = depth or 1
  if filePath then
    if filePath:sub(0, 1) ~= '/' then
      local basepath = getfsrcpath(depth+1)
      if basepath:sub(#basepath) ~= '/' then basepath = basepath .. '/' end
      return  basepath .. filePath
    else
      return filePath
    end
  else
    local basepath = getfsrcpath(depth+1)
    if basepath:sub(#basepath) ~= '/' then basepath = basepath .. '/' end
    return basepath
  end
end

function toboolean(v)
  if type(v) == 'string' then
    v = v:trim():lower()
    if v == '1' or v == 'true' then
      return true
    end
  elseif type(v) == 'number' then
    if v == 1 then
      return true
    end
  elseif type(v) == 'boolean' then
    return v
  end
  return false
end

function fromboolean(boolean)
  if boolean then
    return 'true'
  else
    return 'false'
  end
end

function booleantonumber(boolean)
  if boolean then
    return 1
  else
    return 0
  end
end

function numbertoboolean(number)
  if number ~= 0 then
    return true
  else
    return false
  end
end

function protectedcall(func, ...)
  local status, ret = pcall(func, ...)
  if status then
    return ret
  end

  local desc = "lua"
  local info = debug.getinfo(2, "Sl")
  if info then
    desc = info.short_src .. ":" .. info.currentline
  end

  g_logger.error(debug.traceback("(protectedcall Lua Error): ") .. "\n" .. ret .. "\nOrigin: " .. desc)
  return false
end

function signalcall(param, ...)
  local desc = "lua"
  local info = debug.getinfo(2, "Sl")
  if info then
    desc = info.short_src .. ":" .. info.currentline
  end

  if type(param) == 'function' then
    local status, ret = pcall(param, ...)
    if status then
      return ret
    else
      g_logger.error(debug.traceback("(function signalcall Lua Error): ") .. "\n" .. ret .. "\nOrigin: " .. desc)
    end
  elseif type(param) == 'table' then
    for k,v in pairs(param) do
      local status, ret = pcall(v, ...)
      if status then
        if ret then return true end
      else
        g_logger.error(debug.traceback("(table signalcall Lua Error): ") .. "\n" .. ret .. "\nOrigin: " .. desc)
      end
    end
  elseif param ~= nil then
    error('attempt to call a non function value')
  end
  return false
end

function tr(s, ...)
  return string.format(s, ...)
end

function getOppositeAnchor(anchor)
  if anchor == AnchorLeft then
    return AnchorRight
  elseif anchor == AnchorRight then
    return AnchorLeft
  elseif anchor == AnchorTop then
    return AnchorBottom
  elseif anchor == AnchorBottom then
    return AnchorTop
  elseif anchor == AnchorVerticalCenter then
    return AnchorHorizontalCenter
  elseif anchor == AnchorHorizontalCenter then
    return AnchorVerticalCenter
  end
  return anchor
end

function makesingleton(obj)
  local singleton = {}
  if obj.getClassName then
    for key,value in pairs(_G[obj:getClassName()]) do
      if type(value) == 'function' then
        singleton[key] = function(...) return value(obj, ...) end
      end
    end
  end
  return singleton
end

function comma_value(amount)
  local formatted = tostring(amount or 0)
  while true do
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
    if (k==0) then
      break
    end
  end
  return formatted
end

-- Short, abbreviated number format (e.g. 12345 -> "12.3k", 1500000 -> "1.5kk").
-- Used by the inventory free-capacity label (and anywhere a compact value helps).
function tokformat(value)
  value = tonumber(value) or 0
  local abs = math.abs(value)
  local function trim(n)
    -- one decimal place, dropping a trailing ".0"
    local s = string.format('%.1f', n)
    return (s:gsub('%.0$', ''))
  end
  if abs >= 1000000000 then
    return trim(value / 1000000000) .. 'kkk'
  elseif abs >= 1000000 then
    return trim(value / 1000000) .. 'kk'
  elseif abs >= 1000 then
    return trim(value / 1000) .. 'k'
  end
  return tostring(math.floor(value))
end

-- Like tokformat but WITHOUT a decimal point (e.g. 20600 -> "21k"). The soul/cap
-- slot uses verdana-cap-bold, a digit-only bitmap font (it has no '.' glyph), so a
-- decimal would render as an empty gap. Keeps raw digits below 10000 since 4 digits
-- still fit the slot, then rounds to a whole k/kk.
function tokformatint(value)
  value = math.floor(tonumber(value) or 0)
  local abs = math.abs(value)
  if abs >= 1000000 then
    return math.floor(value / 1000000 + 0.5) .. 'kk'
  elseif abs >= 10000 then
    return math.floor(value / 1000 + 0.5) .. 'k'
  end
  return tostring(value)
end

-- Builds the gold notation ladder, most precise first, each tier keeping comma grouping
-- and appending one 'k' per thousand-fold:
--   1,000,000,000  ->  "1,000,000 k"  ->  "1,000 kk"  ->  "1 kkk"
local function moneyTiers(amount)
  amount = math.floor(tonumber(amount) or 0)
  local tiers = { comma_value(amount) }
  if amount >= 1000 then
    tiers[#tiers + 1] = comma_value(math.floor(amount / 1000)) .. ' k'
  end
  if amount >= 1000000 then
    tiers[#tiers + 1] = comma_value(math.floor(amount / 1000000)) .. ' kk'
  end
  if amount >= 1000000000 then
    tiers[#tiers + 1] = comma_value(math.floor(amount / 1000000000)) .. ' kkk'
  end
  return tiers
end

-- Fits a gold value into a fixed-width box by stepping down the notation ladder until
-- the rendered text stops overflowing. maxWidth is the pixel budget the text must fit
-- in; pass it when the widget has text-auto-resize (it grows to its own text, so it
-- never overflows itself) or when a sibling icon shares the box. Defaults to the
-- widget's own width otherwise. Returns the string that was set.
function setMoneyAutoFit(widget, amount, maxWidth)
  maxWidth = maxWidth or widget:getWidth()
  local tiers = moneyTiers(amount)
  for _, text in ipairs(tiers) do
    widget:setText(text)
    -- maxWidth <= 0 means the box isn't laid out yet: keep the most precise value.
    if maxWidth <= 0 or widget:getTextSize().width <= maxWidth then
      return text
    end
  end
  return tiers[#tiers]
end

-- Same as setMoneyAutoFit but renders through setColoredText, preserving an affordability
-- tint (e.g. red when unaffordable). `color` is any string setColoredText accepts, such
-- as "#d33c3c" or an OTUI $var color. Returns the string that was set.
function setMoneyAutoFitColored(widget, amount, color, maxWidth)
  maxWidth = maxWidth or widget:getWidth()
  local tiers = moneyTiers(amount)
  for _, text in ipairs(tiers) do
    widget:setColoredText({ text, color })
    if maxWidth <= 0 or widget:getTextSize().width <= maxWidth then
      return text
    end
  end
  return tiers[#tiers]
end

-- Builds an integer abbreviation ladder, most precise first, WITHOUT any separator so it's
-- safe for digit-only bitmap fonts (the soul/cap slot). Mirrors tokformatint's rounded
-- k/kk/kkk suffixes but keeps the full raw number as the first, preferred tier:
--   21350 -> {"21350", "21k"} ; 213500000 -> {"213500000", "213500k", "214kk"}
local function intTiers(value)
  value = math.floor(tonumber(value) or 0)
  local tiers = { tostring(value) }
  local abs = math.abs(value)
  if abs >= 1000 then
    tiers[#tiers + 1] = math.floor(value / 1000 + 0.5) .. 'k'
  end
  if abs >= 1000000 then
    tiers[#tiers + 1] = math.floor(value / 1000000 + 0.5) .. 'kk'
  end
  if abs >= 1000000000 then
    tiers[#tiers + 1] = math.floor(value / 1000000000 + 0.5) .. 'kkk'
  end
  return tiers
end

-- Auto-fit counterpart of tokformatint: renders the full integer and only steps down to a
-- k/kk/kkk abbreviation once the text overflows, instead of abbreviating past a hardcoded
-- threshold. Emits no comma, so it's safe for digit-only fonts. `prefix` (e.g. "Cap: ") is
-- prepended to every tier and counts toward the width. maxWidth defaults to the widget's own
-- width -- reliable here because these labels aren't text-auto-resize (they'd otherwise grow
-- to the text and never report overflow). Returns the string that was set.
function setIntAutoFit(widget, value, prefix, maxWidth)
  prefix = prefix or ''
  maxWidth = maxWidth or widget:getWidth()
  local tiers = intTiers(value)
  for _, text in ipairs(tiers) do
    widget:setText(prefix .. text)
    -- maxWidth <= 0 means the box isn't laid out yet: keep the most precise value.
    if maxWidth <= 0 or widget:getTextSize().width <= maxWidth then
      return prefix .. text
    end
  end
  return prefix .. tiers[#tiers]
end

-- Compact "cur / max" text for the narrow HP/mana status bars. Each side stays in full until
-- it reaches 6 digits, then switches to tokformat (e.g. 5000000 -> "5kk"); huge server pools
-- otherwise run past the screen edge. Abbreviating per-side keeps a low current value exact
-- (e.g. "1234 / 5kk") when it matters most. `template` is a 2-slot format (default "%s / %s");
-- pass e.g. "(%s / %s@)" for the mana-shield label. Returns the string that was set.
--
-- A measure-and-fit variant (getTextSize vs the bar width) was tried first, but the status bar
-- and its container can extend past the visible viewport, so getWidth() reports a budget wider
-- than where the text actually clips and it never abbreviated. A digit-count threshold is
-- layout-independent and reliable. THRESHOLD is the value at/above which a value is abbreviated.
BAR_ABBREVIATE_THRESHOLD = 100000

-- Abbreviates a single status-bar value (HP, mana, ...) with tokformat once it reaches
-- BAR_ABBREVIATE_THRESHOLD (6 digits), else returns it in full. Use for lone numeric labels;
-- setBarPair below is the "cur / max" version built on top of it.
function tokbar(value)
  value = math.floor(tonumber(value) or 0)
  return math.abs(value) >= BAR_ABBREVIATE_THRESHOLD and tokformat(value) or tostring(value)
end

function setBarPair(widget, cur, max, template)
  template = template or "%s / %s"
  local text = template:format(tokbar(cur), tokbar(max))
  widget:setText(text)
  return text
end

function countTableElements(t)
  local count = 0
  for _ in pairs(t) do
      count = count + 1
  end
  return count
end

-- Converte dicion�rio para array de valores
function getValues(t)
  if type(t) ~= "table" then return {} end  -- Evita erro caso t seja nil
  local values = {}
  for _, v in pairs(t) do
      table.insert(values, v)
  end
  return values
end

function convertGold(amount, shortValue)
  local formatType = 0
  if shortValue and amount > 9999999999 then
	  formatType = 1
    amount = math.floor(amount / 1000)
  end

  local formatted = amount
  while true do
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
    if (k==0) then
      break
    end
  end

  if formatType == 1 then
    formatted = formatted .. " k"
  end

  return formatted
end

function convertLongGold(amount, shortValue, normalized)
  local hasBillion = false
  local hasTrillion = false

  local fomarType = 0
  if normalized and amount >= 1000000 then
    amount = math.floor(amount / 1000000)
    fomarType = 1
  elseif normalized and amount >= 10000 then
    amount = math.floor(amount / 1000)
    fomarType = 2
  elseif shortValue and amount > 10000000 then
	  fomarType = 1
    amount = math.floor(amount / 1000000)
  elseif shortValue and amount > 1000000 then
	  fomarType = 2
    amount = math.floor(amount / 1000)
  elseif amount > 999999999 then
    fomarType = 1
    amount = math.floor(amount / 1000000)
  elseif amount > 99999999 then
    fomarType = 2
    amount = math.floor(amount / 1000)
  end

  local formatted = amount
  while true do
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
    if (k==0) then
      break
    end
  end

  if fomarType == 1 then
    formatted = formatted .. " kk"
  elseif fomarType == 2 then
    formatted = formatted .. " k"
  end

  return formatted
end

function getTotalMoney()
	return g_game.getLocalPlayer():getResourceValue(ResourceBank) + g_game.getLocalPlayer():getResourceValue(ResourceInventary)
end

function openPlataform(self)
  local selfId = self:getId()
  if selfId == 'clickSitePassword' then
    g_platform.openUrl(Services.recoveryPassword)
  elseif selfId == 'clickSiteCreateAccount' then
    g_platform.openUrl(Services.createAccount)
  elseif selfId == 'logo' then
    g_platform.openUrl(Services.website)
  elseif selfId == 'getCoins' then
    g_platform.openUrl(Services.Coins)
  end
end

function numberToStr(value)
  if value < 1000 then
      return tostring(value)
  end

  local formatted = string.format("%.1f", value / 1000)
  return formatted:gsub("%.?0+$", "") .. "k"
end

function aggresiveNumberToStr(value)
  if value < 10000 then
      return tostring(value)
  elseif value < 100000 then
      local formatted = string.format("%.0f", value / 1000)
      return formatted .. "k"
  elseif value < 1000000 then
      local formatted = string.format("%.0f", value / 1000)
      return formatted .. "k"
  else
    local millions = value / 1000000
      local truncated = math.floor(millions * 10) / 10
      local formatted = string.format("%.1f", truncated)
      if formatted:sub(-2) == ".0" then
          return formatted:sub(1, -3) .. "kk"
      else
          return formatted .. "kk"
      end
  end
end

-- Global typing animation system
TypingAnimation = {
    instances = {}
}

function TypingAnimation:create(id)
    if self.instances[id] then
        self:destroy(id)
    end
    
    self.instances[id] = {
        event = nil,
        targetLabel = nil,
        fullText = "",
        currentIndex = 0,
        speed = 50,
        parsedText = {}
    }
    
    return self.instances[id]
end

function TypingAnimation:destroy(id)
    local instance = self.instances[id]
    if not instance then return end
    
    if instance.event then
        removeEvent(instance.event)
    end
    
    self.instances[id] = nil
end

function TypingAnimation:start(id, label, text, speed)
    local instance = self:create(id)
    
    instance.targetLabel = label
    instance.fullText = text
    instance.currentIndex = 0
    instance.speed = speed or 50
    instance.parsedText = self:parseColorText(text)
    
    label:setText("")
    
    instance.event = cycleEvent(function()
        self:processAnimation(id)
    end, instance.speed)
end

function TypingAnimation:stop(id)
    self:destroy(id)
end

function TypingAnimation:hasEvent(id)
    return self.instances[id]
end

function TypingAnimation:parseColorText(text)
    local parsed = {}
    local i = 1
    local currentColor = nil
    local colorStack = {}
    
    while i <= string.len(text) do
        local colorStart = string.find(text, "%[color=#[%w]+%]", i)
        if colorStart == i then
            local colorEnd = string.find(text, "%]", colorStart)
            local colorTag = string.sub(text, colorStart, colorEnd)
            currentColor = string.match(colorTag, "#[%w]+")
            table.insert(colorStack, currentColor)
            i = colorEnd + 1
        elseif string.sub(text, i, i + 7) == "[/color]" then
            table.remove(colorStack)
            currentColor = colorStack[#colorStack]
            i = i + 8
        else
            local char = string.sub(text, i, i)
            table.insert(parsed, {
                char = char,
                color = currentColor
            })
            i = i + 1
        end
    end
    
    return parsed
end

function TypingAnimation:buildColoredText(parsedText, maxIndex)
    local result = ""
    local currentColor = nil
    local colorOpen = false
    
    for i = 1, math.min(maxIndex, #parsedText) do
        local charData = parsedText[i]
        if charData.color ~= currentColor then
            if colorOpen then
                result = result .. "[/color]"
                colorOpen = false
            end
            if charData.color then
                result = result .. "[color=" .. charData.color .. "]"
                colorOpen = true
                currentColor = charData.color
            else
                currentColor = nil
            end
        end
        result = result .. charData.char
    end

    if colorOpen then
        result = result .. "[/color]"
    end
    
    return result
end

function TypingAnimation:processAnimation(id)
    local instance = self.instances[id]
    if not instance or not instance.targetLabel or instance.currentIndex >= #instance.parsedText then
        self:destroy(id)
        return
    end
    
    instance.currentIndex = instance.currentIndex + 1
    local currentText = self:buildColoredText(instance.parsedText, instance.currentIndex)

    if instance.targetLabel.setColorText then
        instance.targetLabel:setColorText(currentText)
    else
        instance.targetLabel:setText(currentText)
    end
end

-- @}
