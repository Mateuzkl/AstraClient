-- Shared inside the client_background sandbox and used by background.lua.
-- This global is intentional; it is not an uncontrolled process-wide table.
EventSchedule = EventSchedule or {}
EventSchedule.__index = EventSchedule
EventSchedule.events = {}

local function convertStringToTime(dateString)
  if type(dateString) ~= 'string' then
    return nil
  end

  local year, month, day, hour, min, sec = dateString:match(
    '^(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+)$'
  )
  if not year then
    return nil
  end

  local ok, timestamp = pcall(os.time, {
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(min),
    sec = tonumber(sec)
  })

  if not ok then
    return nil
  end

  return timestamp
end

local function getEventInterval(event)
  if type(event) ~= 'table' then
    return nil, nil
  end

  local startDate = type(event.startdate) == 'table' and event.startdate.date or nil
  local endDate = type(event.enddate) == 'table' and event.enddate.date or nil
  return convertStringToTime(startDate), convertStringToTime(endDate)
end

local function appendTooltip(tooltip, event)
  local name = tostring(event.name or '?')
  local description = tostring(event.description or '')
  local entry = name .. ':\n' .. string.todivide(description, 10)

  if tooltip == '' then
    return entry
  end

  return tooltip .. '\n\n' .. entry
end

local function configureEventLabel(parent, data, tooltip, color)
  local ui = g_ui.createWidget('EventsScheduleLabel', parent)
  ui:setText(tostring(data.name or '?'))

  if color then
    ui:setBackgroundColor(color)
  end

  ui:setTooltip(tooltip)
  if modules.game_schedule then
    ui.onClick = modules.game_schedule.toggle
  end
end

function EventSchedule:configureEvent(widget)
  if not widget or not widget.panel1 or not widget.panel2 then
    return
  end

  local activeContainer = widget.panel1.activeEvent
  local upcomingContainer = widget.panel2.upcomingEvent
  if not activeContainer or not upcomingContainer then
    return
  end

  local activeEvents = {}
  local upcomingEvents = {}
  local activeTooltip = ''
  local upcomingTooltip = ''
  local currentTime = os.time()
  local upcomingLimit = currentTime + (5 * 24 * 60 * 60)

  for _, event in ipairs(self.events or {}) do
    local startDate, endDate = getEventInterval(event)
    if startDate and endDate then
      if currentTime >= startDate and currentTime <= endDate then
        activeEvents[#activeEvents + 1] = event
        activeTooltip = appendTooltip(activeTooltip, event)
      elseif currentTime < startDate and upcomingLimit >= startDate then
        upcomingEvents[#upcomingEvents + 1] = event
        upcomingTooltip = appendTooltip(upcomingTooltip, event)
      end
    end
  end

  -- Rebuild both containers. Old widgets and their callbacks are destroyed here,
  -- so these local arrays do not accumulate between calls.
  activeContainer:destroyChildren()
  for _, data in ipairs(activeEvents) do
    configureEventLabel(activeContainer, data, activeTooltip, data.colorlight)
  end

  upcomingContainer:destroyChildren()
  for _, data in ipairs(upcomingEvents) do
    configureEventLabel(upcomingContainer, data, upcomingTooltip, data.colordark)
  end
end

function EventSchedule:clear()
  self.events = {}
end

function getEventByDay(time)
  local activeEvents = {}
  local activeTooltip = ''
  if not time then
    return activeEvents, activeTooltip
  end

  for _, event in ipairs(EventSchedule.events or {}) do
    local startDate, endDate = getEventInterval(event)
    if startDate and endDate and time >= startDate and time <= endDate then
      activeEvents[#activeEvents + 1] = event
      activeTooltip = appendTooltip(activeTooltip, event)
    end
  end

  return activeEvents, activeTooltip
end
