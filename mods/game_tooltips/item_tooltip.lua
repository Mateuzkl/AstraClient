-- Astra server-authoritative item tooltip (binary ProtocolGame transport).
--
-- This module ONLY: detects hover, asks C++ for the tooltip, receives an already
-- parsed data table, and draws the window. There is NO JSON and NO binary parsing
-- in Lua — g_game.requestAstraItemTooltip() sends the request and the C++ layer
-- raises g_game.onAstraItemTooltip(data) with the decoded payload.

-- Request source types — must match AstraItemTooltip::SourceType on the server.
local SOURCE_INVENTORY = 1
local SOURCE_CONTAINER = 2
local SOURCE_ACTIONBAR = 3
local SOURCE_GENERIC = 4

-- Hover dwell before we bother the server (also throttles flicking across slots).
local HOVER_DELAY = 90

local tooltipWindow = nil
local itemSprite = nil
local itemWeightLabel = nil
local labels = nil

local optionEnabled = true
local currentWidget = nil
local currentItem = nil
local pendingRequestId = nil
local requestCounter = 0
local tooltipDelayEvent = nil

local BASE_WIDTH = 170
local BASE_HEIGHT = 0

local tooltipWidth = 0
local tooltipWidthBase = BASE_WIDTH
local tooltipHeight = BASE_HEIGHT
local longestString = 0

local Colors = {
  Default = "#ffffff",
  Title = "#ffffff",
  Requirement = "#abface",
  Description = "#8080ff",
  Implicit = "#ffbb22",
  Imbuement = "#44ccff",
  Augment = "#d7a0ff",
  Charges = "#cccccc",
  Tier = "#dca01e"
}

-- ─── helpers ────────────────────────────────────────────────────────────────

local function isEnabled()
  return optionEnabled and g_game.isOnline() and g_game.getFeature(GameAstraItemTooltip)
end

local function getTier(item)
  if item and item.getTier then
    return item:getTier() or 0
  end
  return 0
end

local function cancelDelay()
  if tooltipDelayEvent then
    removeEvent(tooltipDelayEvent)
    tooltipDelayEvent = nil
  end
end

local function hideTooltip()
  if tooltipWindow then
    tooltipWindow:hide()
  end
end

-- Map a hovered widget back to (sourceType + ids). The server re-validates and
-- cross-checks the client id, so a misclassified source is harmless (denied).
local function resolveSource(widget, item)
  local id = widget:getId()

  -- inventory equipment slot: ids 'slot1'..'slot10' map 1:1 to CONST_SLOT_*.
  if id then
    local invSlot = id:match("^slot(%d+)$")
    if invSlot then
      invSlot = tonumber(invSlot)
      if invSlot >= 1 and invSlot <= 10 then
        return { type = SOURCE_INVENTORY, clientId = item:getId(), arg0 = invSlot, tier = getTier(item) }
      end
    end

    -- container slot: ids 'item0'..'itemN' under a 'containerN' window (.instance).
    local containerSlot = id:match("^item(%d+)$")
    if containerSlot then
      local parent = widget:getParent()
      local depth = 0
      while parent and depth < 6 do
        if parent.instance ~= nil then
          return { type = SOURCE_CONTAINER, clientId = item:getId(),
                   arg0 = tonumber(parent.instance), arg1 = tonumber(containerSlot), tier = getTier(item) }
        end
        local pid = parent:getId()
        if pid then
          local cid = pid:match("^container(%d+)$")
          if cid then
            return { type = SOURCE_CONTAINER, clientId = item:getId(),
                     arg0 = tonumber(cid), arg1 = tonumber(containerSlot), tier = getTier(item) }
          end
        end
        parent = parent:getParent()
        depth = depth + 1
      end
    end
  end

  -- everything else (actionbar buttons, market/forge previews, npc/trade slots):
  -- static ItemType data only, keyed by the client id the widget is showing.
  return { type = SOURCE_GENERIC, clientId = item:getId(), tier = getTier(item) }
end

-- ─── transport ──────────────────────────────────────────────────────────────

local function onItemHover(widget)
  if not isEnabled() or not widget then
    return
  end

  local item = widget:getItem()
  if not item then
    return
  end

  currentWidget = widget
  currentItem = item

  cancelDelay()
  requestCounter = (requestCounter % 250) + 1
  local reqId = requestCounter
  pendingRequestId = reqId
  local capturedWidget = widget

  tooltipDelayEvent = scheduleEvent(function()
    tooltipDelayEvent = nil
    if not isEnabled() then return end
    if currentWidget ~= capturedWidget then return end
    if capturedWidget:isDestroyed() then return end
    if not g_game.isOnline() then return end

    local liveItem = capturedWidget:getItem()
    if not liveItem then return end

    local source = resolveSource(capturedWidget, liveItem)
    g_game.requestAstraItemTooltip(reqId, source.type, source.clientId,
      source.arg0 or 0, source.arg1 or 0, source.fallbackClientId or 0, source.tier or 0)
  end, HOVER_DELAY)
end

local function onItemUnhover(widget)
  if currentWidget == widget then
    currentWidget = nil
    currentItem = nil
    pendingRequestId = nil
    cancelDelay()
    hideTooltip()
  end
end

function onHoverChange(widget, hovered)
  if hovered then
    onItemHover(widget)
  else
    onItemUnhover(widget)
  end
end

-- C++ raises this with the fully parsed payload (see ProtocolGame::parseAstraItemTooltip).
function onAstraItemTooltip(data)
  if not data or data.requestId ~= pendingRequestId then
    return -- stale / belongs to an item the mouse already left
  end
  if data.status ~= 0 then
    hideTooltip()
    return
  end
  if not currentWidget or currentWidget:isDestroyed() then
    return
  end

  local liveItem = currentWidget:getItem()
  if not liveItem or liveItem:getId() ~= data.clientId then
    return -- the item under the mouse changed since the request
  end

  buildItemTooltip(data)
end

function onGameEnd()
  cancelDelay()
  currentWidget = nil
  currentItem = nil
  pendingRequestId = nil
  hideTooltip()
end

-- ─── option (game options checkbox) ─────────────────────────────────────────

function setEnabled(value)
  optionEnabled = value
  if not value then
    cancelDelay()
    hideTooltip()
  end
end

function isOptionEnabled()
  return optionEnabled
end

-- ─── rendering ──────────────────────────────────────────────────────────────

local function tierColor(tier)
  return Colors.Tier
end

local function formatDuration(seconds)
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  local s = seconds % 60
  if h > 0 then return string.format("%dh %02dm", h, m) end
  if m > 0 then return string.format("%dm %02ds", m, s) end
  return string.format("%ds", s)
end

function buildItemTooltip(data)
  tooltipWidth = 0
  longestString = 0
  tooltipWidthBase = BASE_WIDTH
  tooltipHeight = BASE_HEIGHT
  tooltipWindow:setWidth(tooltipWidth)
  tooltipWindow:setHeight(tooltipHeight)

  labels:destroyChildren()

  itemWeightLabel:setText(formatWeight(data.weight or 0))
  itemSprite:setItemId(data.clientId)
  itemSprite:setItemCount(currentItem and currentItem:getCount() or 1)

  -- Title (+ forge tier).
  local title = data.name or ""
  if data.tier and data.tier > 0 then
    title = title .. " (Tier " .. data.tier .. ")"
    addString(title, tierColor(data.tier))
  else
    addString(title, Colors.Title)
  end

  -- Requirements.
  if data.requiredLevel and data.requiredLevel > 0 then
    addString("Required Level " .. data.requiredLevel, Colors.Requirement)
  end
  if data.requiredMagicLevel and data.requiredMagicLevel > 0 then
    addString("Required Magic Level " .. data.requiredMagicLevel, Colors.Requirement)
  end
  if data.vocation and #data.vocation > 0 then
    addString(data.vocation, Colors.Requirement)
  end

  -- Combat / defensive stats.
  local statLines = {}
  local function stat(label, value, suffix)
    if value and value ~= 0 then
      table.insert(statLines, label .. ": " .. (value > 0 and "" or "") .. value .. (suffix or ""))
    end
  end
  if data.isWeapon then
    stat("Attack", data.attack)
    stat("Defense", data.defense)
    stat("Extra Defense", data.extraDefense)
    stat("Hit Chance", data.hitChance, "%")
    if data.shootRange and data.shootRange > 1 then
      stat("Range", data.shootRange)
    end
  else
    stat("Armor", data.armor)
    stat("Defense", data.defense)
    stat("Extra Defense", data.extraDefense)
  end
  if #statLines > 0 then
    addSeparator()
    addEmpty(5)
    for _, line in ipairs(statLines) do
      addString(line, Colors.Default)
    end
  end

  -- Implicit ability lines (pre-formatted by the server).
  if data.implicits and #data.implicits > 0 then
    addSeparator()
    addEmpty(5)
    for _, line in ipairs(data.implicits) do
      addString(line, Colors.Implicit)
    end
  end

  -- Imbuements.
  if data.imbuementSlots and data.imbuementSlots > 0 then
    addSeparator()
    addEmpty(5)
    local applied = data.imbuements or {}
    addString("Imbuements (" .. #applied .. "/" .. data.imbuementSlots .. ")", Colors.Imbuement)
    for _, imb in ipairs(applied) do
      local line = "- " .. imb.name
      if imb.duration and imb.duration > 0 then
        line = line .. " (" .. formatDuration(imb.duration) .. ")"
      end
      addString(line, Colors.Imbuement)
    end
    for _ = #applied + 1, data.imbuementSlots do
      addString("- Empty Slot", Colors.Charges)
    end
  end

  -- Augments.
  if data.augments and #data.augments > 0 then
    addSeparator()
    addEmpty(5)
    addString("Augments", Colors.Augment)
    for _, line in ipairs(data.augments) do
      addString(line, Colors.Augment)
    end
  end

  -- Charges / duration / container capacity.
  local extra = {}
  if data.charges then
    table.insert(extra, { "Charges: " .. data.charges, Colors.Charges })
  end
  if data.duration then
    local text = "Duration: " .. formatDuration(data.duration)
    if data.durationPaused then
      text = text .. " (paused)"
    end
    table.insert(extra, { text, Colors.Charges })
  end
  if data.isContainer and data.containerCapacity then
    table.insert(extra, { "Capacity: " .. data.containerCapacity, Colors.Charges })
  end
  if #extra > 0 then
    addSeparator()
    addEmpty(5)
    for _, e in ipairs(extra) do
      addString(e[1], e[2])
    end
  end

  -- Flavor description.
  if data.description and #data.description > 0 then
    addEmpty(5)
    addString(data.description, Colors.Description, true)
  end

  shrinkSeparators()
  showItemTooltip()
end

function addString(text, color, resize)
  local label = g_ui.createWidget("TooltipLabel", labels)
  label:setColor(color)

  if resize then
    tooltipWindow:setWidth(tooltipWidth)
    label:setTextWrap(true)
    label:setTextAutoResize(true)
    label:setText(text)
    tooltipHeight = tooltipHeight + label:getTextSize().height + 4
  else
    label:setText(text)
    local textSize = label:getTextSize()
    if longestString == 0 then
      longestString = textSize.width + itemWeightLabel:getWidth()
      tooltipWidth = tooltipWidthBase + longestString
      label:addAnchor(AnchorTop, "parent", AnchorTop)
    elseif textSize.width > longestString then
      longestString = textSize.width
      tooltipWidth = tooltipWidthBase + longestString
    end
    tooltipHeight = tooltipHeight + textSize.height
  end
end

function shrinkSeparators()
  local children = labels:getChildren()
  local m = math.max(60, math.floor(tooltipWidth / 4))
  for _, child in ipairs(children) do
    if child:getStyleName() == "TooltipSeparator" then
      child:setMarginLeft(m)
      child:setMarginRight(m)
    end
  end
end

function addSeparator()
  local sep = g_ui.createWidget("TooltipSeparator", labels)
  tooltipHeight = tooltipHeight + sep:getHeight() + sep:getMarginTop() + sep:getMarginBottom()
end

function addEmpty(height)
  local empty = g_ui.createWidget("TooltipEmpty", labels)
  empty:setHeight(height)
  tooltipHeight = tooltipHeight + height
end

function showItemTooltip()
  local mousePos = g_window.getMousePosition()
  tooltipHeight = math.max(tooltipHeight, 40)
  tooltipWindow:setWidth(tooltipWidth)
  tooltipWindow:setHeight(tooltipHeight)

  local windowSize = g_window.getSize()
  if mousePos.x > windowSize.width / 2 then
    tooltipWindow:move(mousePos.x - (tooltipWidth + 2), math.min(windowSize.height - tooltipHeight, mousePos.y + 5))
  else
    tooltipWindow:move(mousePos.x + 5, mousePos.y + 10)
  end
  tooltipWindow:raise()
  tooltipWindow:show()
  g_effects.fadeIn(tooltipWindow, 100)
end

function formatWeight(weight)
  local ss
  if weight < 10 then
    ss = "0.0" .. weight
  elseif weight < 100 then
    ss = "0." .. weight
  else
    local weightString = tostring(weight)
    local len = weightString:len()
    ss = weightString:sub(1, len - 2) .. "." .. weightString:sub(len - 1, len)
  end
  return ss .. " oz."
end

-- ─── lifecycle ──────────────────────────────────────────────────────────────

function init()
  -- Register the default so the value is correct regardless of module load order.
  g_settings.setDefault("astraItemTooltips", true)
  optionEnabled = g_settings.getBoolean("astraItemTooltips")

  connect(UIItem, { onHoverChange = onHoverChange })
  connect(g_game, { onGameEnd = onGameEnd, onAstraItemTooltip = onAstraItemTooltip })

  tooltipWindow = g_ui.displayUI("item_tooltip")
  tooltipWindow:hide()

  labels = tooltipWindow:getChildById("labels")
  itemWeightLabel = tooltipWindow:getChildById("itemWeightLabel")
  itemSprite = tooltipWindow:getChildById("itemSprite")
end

function terminate()
  disconnect(UIItem, { onHoverChange = onHoverChange })
  disconnect(g_game, { onGameEnd = onGameEnd, onAstraItemTooltip = onAstraItemTooltip })

  cancelDelay()

  currentWidget = nil
  currentItem = nil
  pendingRequestId = nil

  if tooltipWindow then
    itemWeightLabel = nil
    itemSprite = nil
    labels = nil
    tooltipWindow:destroy()
    tooltipWindow = nil
  end
end
