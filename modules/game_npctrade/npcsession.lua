-- Owns delayed work for one shop. A callback from shop A must never touch B.
NpcTradeSession = {}
NpcTradeSession.__index = NpcTradeSession

function NpcTradeSession.new(schedule, cancel)
  return setmetatable({ generation = 0, open = false, events = {},
    scheduleEvent = schedule, cancelEvent = cancel }, NpcTradeSession)
end

function NpcTradeSession:finish()
  self.open = false
  self.generation = self.generation + 1
  if self.sellQueue then
    self.sellQueue:cancel()
    self.sellQueue = nil
  end
  for event in pairs(self.events) do
    self.cancelEvent(event)
  end
  self.events = {}
end

function NpcTradeSession:begin()
  self:finish()
  self.open = true
end

function NpcTradeSession:schedule(callback, delay)
  local generation = self.generation
  local event
  event = self.scheduleEvent(function()
    self.events[event] = nil
    if self.open and self.generation == generation then
      callback()
    end
  end, delay or 0)
  self.events[event] = true
  return event
end
