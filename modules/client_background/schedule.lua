if not EventSchedule then
	EventSchedule = {}
	EventSchedule.__index = EventSchedule
end

EventSchedule.events = {}

local function convertStringToTime(date_string)
	local year, month, day, hour, min, sec = date_string:match("(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")

	-- Converte para timestamp usando os.time
	local timestamp = os.time({
		year = tonumber(year),
		month = tonumber(month),
		day = tonumber(day),
		hour = tonumber(hour),
		min = tonumber(min),
		sec = tonumber(sec)
	})

	return timestamp
end

function EventSchedule:configureEvent(widget)
	local activesEvents = {}
	local upcomingEvents = {}
	local activeTooltip = ''
	local upcomingTooltip = ''
	local time = os.time()

	for _, event in ipairs(EventSchedule.events or {}) do
		local startdate = convertStringToTime(event.startdate.date)
		local enddate = convertStringToTime(event.enddate.date)

		if time >= startdate and time <= enddate then
			table.insert(activesEvents, event)
			if activeTooltip ~= '' then
				activeTooltip = activeTooltip .. '\n\n'
			end
			activeTooltip = activeTooltip .. event.name ..":\n"..string.todivide(event.description, 10)
		elseif time < startdate and time + (5*24*60*60) >= startdate then
			table.insert(upcomingEvents, event)
			if upcomingTooltip ~= '' then
				upcomingTooltip = upcomingTooltip .. '\n\n'
			end
			upcomingTooltip = upcomingTooltip .. event.name ..":\n"..string.todivide(event.description, 10)
		end
	end

	widget.panel1.activeEvent:destroyChildren()
	for _, data in pairs(activesEvents) do
		local ui = g_ui.createWidget('EventsScheduleLabel', widget.panel1.activeEvent)
		ui:setText(data.name)
		ui:setBackgroundColor(data.colorlight)
		ui:setTooltip(activeTooltip)
		ui.onClick = function() if modules.game_schedule and modules.game_schedule.toggle then modules.game_schedule.toggle() end end
	end

	widget.panel2.upcomingEvent:destroyChildren()
	for _, data in pairs(upcomingEvents) do
		local ui = g_ui.createWidget('EventsScheduleLabel', widget.panel2.upcomingEvent)
		ui:setText(data.name)
		ui:setBackgroundColor(data.colordark)
		ui:setTooltip(upcomingTooltip)
		ui.onClick = function() if modules.game_schedule and modules.game_schedule.toggle then modules.game_schedule.toggle() end end
	end
end


function getEventByDay(time)
	local activesEvents = {}
	local activeTooltip = ''
	if not time then
		return activesEvents, activeTooltip
	end

	for _, event in ipairs(EventSchedule.events) do
		local startdate = convertStringToTime(event.startdate.date)
		local enddate = convertStringToTime(event.enddate.date)

		if time >= startdate and time <= enddate then
			table.insert(activesEvents, event)
			if activeTooltip ~= '' then
				activeTooltip = activeTooltip .. '\n\n'
			end
			activeTooltip = activeTooltip .. event.name ..":\n"..string.todivide(event.description, 10)
		end
	end

	return activesEvents, activeTooltip
end
