schedule = {}
scheduleWindow = nil
local step = 0

function getFirstDay(time)
  local d = os.date("*t", time)
  return d.wday
end

function dayExistsInMonth(day, month, year)
    local date = os.time({year = year, month = month, day = day})

    -- Use the os.date function to check if the date is valid
    local t = os.date("*t", date)

    -- If the year, month, and day fields in the table t match the provided values, the day is valid
    return t.year == year and t.month == month and t.day == day
end

function destroyCalendary()
  for widgetId, child in pairs(scheduleWindow.listOfDays.itemsPanel:getChildren()) do
    child:destroy()
  end
end

function makeCalendar(newTime)
  local time = os.date("*t", newTime)

  -- like the tibia calendar, the week starts on monday, subtract the numbered value of the week by -1
  local firstDay = getFirstDay(os.time{year = time.year, month = time.month, day = 1}) - 1

  -- Note: if the month starts on Monday, it skips 7 days
  if firstDay <= 1 then
    firstDay = firstDay + 7
  end

  scheduleWindow:recursiveGetChildById('DayButton'):destroyChildren()
  scheduleWindow:recursiveGetChildById('month'):setText(os.date("%B %Y", newTime))

  local data_formatada = os.date("%Y-%m-%d, %H:%M GMT+3")
  scheduleWindow:recursiveGetChildById('hour'):setText(data_formatada)

  local currentDay = 1
  local recount = 1
  local month = time.month
  local year = time.year

  -- calendar accepts 42 days
  for i = 1, 42 do
    local widgetDay = g_ui.createWidget("DayButton", scheduleWindow:recursiveGetChildById('DayButton'))

    -- if the month is in the selected month and the day exists in the month, set the day with the designated functions
    if month == time.month and dayExistsInMonth(currentDay, month, year) then
      widgetDay:setImageClip("0 69 107 69")
      if i == firstDay then
        widgetDay.day:setText(currentDay)
        widgetDay.time = os.time{year = time.year, month = month, day = currentDay, hour = 13, min = 0, sec = 0}
        currentDay = currentDay+1

        configureWidget(widgetDay)
      elseif currentDay ~= 1 and dayExistsInMonth(currentDay, month, year) then
        widgetDay.time = os.time{year = time.year, month = month, day = currentDay, hour = 13, min = 0, sec = 0}
        widgetDay.day:setText(currentDay)
        configureWidget(widgetDay)
        currentDay = currentDay+1
      else
        -- Equivalent to the previous month
        local otherMonth = os.time{year = time.year, month = month, day = 1, hour = 13, min = 0, sec = 0} - ((firstDay - i) * 86400)
        widgetDay.day:setText(os.date("%d", otherMonth))
        widgetDay:setImageClip("0 0 107 69")
        widgetDay:setEnabled(false)
      end
    else
      -- setting later month
      if not dayExistsInMonth(currentDay, month, year) then
        currentDay = currentDay - 1
        month = month + 1
        if month > 12 then
          month = 1
          year = year + 1
        end
      end

      local otherMonth = os.time{year = time.year, month = time.month, day = currentDay, hour = 13, min = 0, sec = 0} + (recount * 86400)
      widgetDay.day:setText(os.date("%d", otherMonth))
      recount = recount + 1
      widgetDay:setImageClip("0 0 107 69")
      widgetDay:setEnabled(false)
    end
  end
end

function init()
  scheduleWindow = g_ui.displayUI('schedule')
	scheduleWindow:hide()
	monthsSchedule =   scheduleWindow.contentPanel:getChildById('month')
	timeDaySchedule =   scheduleWindow.contentPanel:getChildById('hour')

  local time = os.date("*t")
  makeCalendar(os.time())
  connect(g_game, { onGameStart = offline })
end

function nextMonth()
	local time = os.date("*t")
	step = step + 1
  local month = time.month + step
  local year = time.year
  if month > 12 then
    month = 1
    year = year + 1
  end
  local newTime = os.time{day = 1, year = year, month = month}
  makeCalendar(newTime)
end

function backMonth()
	 local time = os.date("*t")
	 step = step - 1
   local month = time.month + step
   local year = time.year
   if month < 1 then
     month = 12
     year = year - 1
   end
   local newTime = os.time{day = time.day, year = time.year, month = time.month + step}

  makeCalendar(newTime)
end

function terminate()
  disconnect(g_game, { onGameStart = offline })

  g_client.setInputLockWidget(nil)

  if scheduleWindow then
    scheduleWindow:destroy()
    scheduleWindow = nil
  end
  monthsSchedule = nil
  timeDaySchedule = nil
end


function offline()
  local benchmark = g_clock.millis()
	scheduleWindow:hide()
  g_client.setInputLockWidget(nil)
  consoleln("Schedule loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end


function toggle()
  if scheduleWindow:isVisible() then
    scheduleWindow:hide()
    g_client.setInputLockWidget(nil)
  else
    scheduleWindow:show()
    scheduleWindow:focus()
    g_client.setInputLockWidget(scheduleWindow)
    -- configure event
    for i, widget in pairs(scheduleWindow:recursiveGetChildById('DayButton'):getChildren()) do
      configureWidget(widget)
    end
  end
end

function configureWidget(widget)
  local events, tooltip = modules.client_background.getEventByDay(widget.time)
  if tooltip ~= '' then
    widget:setTooltip(tooltip)
  end

  widget:recursiveGetChildById('event'):destroyChildren()
  for _, event in pairs(events) do
    local eventWidget = g_ui.createWidget('EventsScheduleLabel', widget:recursiveGetChildById('event'))
    eventWidget:setText(event.name)
    eventWidget:setBackgroundColor(event.colorlight)
    eventWidget:setTooltip(tooltip)
  end
end
