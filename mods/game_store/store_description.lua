StoreDescription = {}

local STORE_DESC_FONT = 'verdana-11px-rounded'
local STORE_DESC_ITALIC_FONT = 'verdana-11px-antialised-italic'
local STORE_DESC_COLOR = '#f7f7f7'
local STORE_INLINE_ICON_SHEET = '/images/store/store-icons-inline'
local STORE_DESC_ICON_GAP = 17
local styleImported = false

local STORE_INLINE_ICONS = {
  ['{vocationlevelcheckicon}'] = '104 0 13 13',
  ['{info}'] = '0 0 13 13',
  ['{speedboosticon}'] = '117 0 13 13',
  ['{backtoinboxicon}'] = '91 0 13 13',
  ['{activatedicon}'] = '130 0 13 13',
  ['{limiticon}'] = '78 0 13 13',
  ['{battlesignicon}'] = '143 0 13 13',
  ['{houseicon}'] = '65 0 13 13',
  ['{capacityicon}'] = '156 0 13 13',
  ['{storeinboxicon}'] = '52 0 13 13',
  ['{useicon}'] = '169 0 13 13',
  ['{boxicon}'] = '39 0 13 13',
  ['{transferablepriceicon}'] = '182 0 13 13',
  ['{usablebyallicon}'] = '26 0 13 13',
  ['{accounticon}'] = '195 0 13 13',
  ['{charactericon}'] = '13 0 13 13',
}

local STORE_DESCRIPTION_HINTS = {
  { keyword = 'character', text = 'only usable by purchasing character', icon = '{charactericon}' },
  { keyword = 'usablebyall', text = 'can be used by all characters that have access to the house', icon = '{usablebyallicon}' },
  { keyword = 'box', text = 'comes in a box which can only be unwrapped by purchasing character', icon = '{boxicon}' },
  { keyword = 'storeinbox', text = 'will be sent to your Store inbox and can only be stored there and in depot box', icon = '{storeinboxicon}' },
  { keyword = 'house', text = 'can only be unwrapped in a house owned by the purchasing character', icon = '{houseicon}' },
  { keyword = 'limit', text = 'maximum amount that can be owned by character: %s', icon = '{limiticon}', dynamic = true },
  { keyword = 'backtoinbox', text = 'will be wrapped back and sent to inbox if the purchasing character is no longer the house owner', icon = '{backtoinboxicon}' },
  { keyword = 'vocationlevelcheck', text = 'only buyable if fitting vocation and level of purchasing character', icon = '{vocationlevelcheckicon}' },
  { keyword = 'speedboost', text = 'provides character with a speed boost', icon = '{speedboosticon}' },
  { keyword = 'activated', text = 'activated at purchase', icon = '{activatedicon}' },
  { keyword = 'battlesign', text = 'cannot be purchased by characters with protection zone block or battle sign', icon = '{battlesignicon}' },
  { keyword = 'capacity', text = 'cannot be purchased if capacity is exceeded', icon = '{capacityicon}' },
  { keyword = 'transferableprice', text = 'can only be purchased with transferable Tibia Coins', icon = '{transferablepriceicon}' },
  { keyword = 'account', text = 'usable by all characters of the account', icon = '{accounticon}' },
  { keyword = 'use', text = '', icon = '{useicon}' },
  { keyword = 'once', text = 'can only be purchased once', icon = '{limiticon}' },
}

local STORE_DESCRIPTION_HINTS_BY_KEYWORD = {}

for _, hint in ipairs(STORE_DESCRIPTION_HINTS) do
  STORE_DESCRIPTION_HINTS_BY_KEYWORD[hint.keyword] = hint
end

local function ensureStyle()
  if styleImported then
    return
  end
  g_ui.importStyle('styles/store_description')
  styleImported = true
end

local function decodeEntities(text)
  text = text:gsub('&nbsp;', ' ')
  text = text:gsub('&lt;', '<')
  text = text:gsub('&gt;', '>')
  text = text:gsub('&quot;', '"')
  text = text:gsub('&#10;', '\n')
  text = text:gsub('&amp;', '&')
  return text
end

local function matchIconTag(text, pos)
  if text:byte(pos) ~= 123 then
    return nil
  end

  local tail = text:sub(pos)
  local limitTag = tail:match('^(%{limit|%d+%})')
  if limitTag then
    return STORE_INLINE_ICONS['{limiticon}'], pos + #limitTag
  end

  local close = text:find('}', pos + 1, true)
  if not close then
    return nil
  end

  local clip = STORE_INLINE_ICONS[text:sub(pos, close)]
  if clip then
    return clip, close + 1
  end

  return nil
end

local function enrichLine(line)
  if not line or not line:match('%S') then
    return line
  end

  local content = line:match('^%s*(.*)$') or line
  if matchIconTag(content, 1) then
    return line
  end

  local plain = content:gsub('^-%s*', '')
  local tagBody = plain:match('^%{([^}]+)}%s*$') or plain:match('^%{([^}]+)}%s+')
  if not tagBody then
    return line
  end

  local keyword, amount = tagBody:match('^([^|]+)|(%d+)$')
  keyword = (keyword or tagBody):lower()
  local hint = STORE_DESCRIPTION_HINTS_BY_KEYWORD[keyword]
  if not hint then
    return line
  end

  if hint.dynamic and amount then
    return '{limit|' .. amount .. '} ' .. string.format(hint.text, amount)
  end

  if hint.text == '' then
    return hint.icon .. ' ' .. plain:gsub('^%{[^}]+}%s*', '')
  end

  return hint.icon .. ' ' .. hint.text
end

local function descriptionToLines(description)
  if not description or description == '' then
    return {}
  end

  description = decodeEntities(description:gsub('\r', ''))
  description = description:gsub('<[bB][rR]%s*/?>', '\n')
  description = description:gsub('<[lL][iI]>%s*', '- ')
  description = description:gsub('</[lL][iI]>%s*', '\n')
  description = description:gsub('<[uUoO][lL]>%s*', '')
  description = description:gsub('</[uUoO][lL]>%s*', '\n')
  description = description:gsub('<[pP]>%s*', '')
  description = description:gsub('</[pP]>%s*', '\n')

  local lines = {}
  local from = 1
  for i = 1, #description do
    if description:byte(i) == 10 then
      table.insert(lines, enrichLine(description:sub(from, i - 1)))
      from = i + 1
    end
  end
  if from <= #description then
    table.insert(lines, enrichLine(description:sub(from)))
  end

  return lines
end

local function stripTags(text)
  text = text:gsub('<[^>]+>', '')
  text = text:gsub('{%w+}', '')
  return text:match('^%s*(.-)%s*$') or text
end

local function applyLineText(textWidget, lineText, color)
  local trimmed = lineText:match('^%s*(.-)%s*$') or lineText
  local hasItalic = trimmed:find('<[iI]>') ~= nil
  local plainText = stripTags(trimmed)

  if plainText == '' then
    textWidget:setText('')
    return
  end

  textWidget:setFont(hasItalic and STORE_DESC_ITALIC_FONT or STORE_DESC_FONT)
  textWidget:setText(plainText)
  textWidget:setColor(color or STORE_DESC_COLOR)
end

local function getTextWidth(container, hasIcon)
  local width = container:getWidth()
  if width <= 0 then
    width = 240
  end
  if hasIcon then
    return math.max(1, width - STORE_DESC_ICON_GAP)
  end
  return width
end

local function renderLine(container, lineText, color, iconClip)
  local widget = g_ui.createWidget('StoreDescriptionLine', container)
  if not widget then
    return false
  end

  local iconWidget = widget.icon or widget:getChildById('icon')
  local textWidget = widget.text or widget:getChildById('text')
  if not textWidget then
    widget:destroy()
    return false
  end

  local hasIcon = iconClip and iconWidget
  if hasIcon then
    iconWidget:setVisible(true)
    iconWidget:setImageSource(STORE_INLINE_ICON_SHEET)
    iconWidget:setImageClip(iconClip)
    textWidget:setMarginLeft(STORE_DESC_ICON_GAP)
  elseif iconWidget then
    iconWidget:setVisible(false)
    textWidget:setMarginLeft(0)
  end

  textWidget:setWidth(getTextWidth(container, hasIcon))
  textWidget:setTextWrap(true)
  applyLineText(textWidget, lineText, color)
  widget:setHeight(math.max(14, textWidget:getTextSize().height + 2))
  return textWidget:getText() ~= '' or hasIcon
end

local function addLine(container, lineText, color)
  if lineText == nil then
    return false
  end

  if not lineText:match('%S') then
    local widget = g_ui.createWidget('StoreDescriptionLine', container)
    if widget then
      widget:setHeight(8)
    end
    return widget ~= nil
  end

  local clip, nextPos = matchIconTag(lineText, 1)
  if clip then
    return renderLine(container, lineText:sub(nextPos), color, clip)
  end

  return renderLine(container, lineText, color, nil)
end

function initStoreDescription()
  ensureStyle()
end

function terminateStoreDescription()
  styleImported = false
end

function StoreDescription.render(hostWidget, description)
  if not hostWidget then
    return false
  end

  ensureStyle()
  hostWidget:destroyChildren()

  local lineCount = 0
  for _, line in ipairs(descriptionToLines(description or '')) do
    if addLine(hostWidget, line) then
      lineCount = lineCount + 1
    end
  end

  hostWidget:updateLayout()
  return lineCount > 0
end
