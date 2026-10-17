-- Bounded event history; collection does not depend on an open HUD.
ElfBotHistory = {}

function ElfBotHistory.new(maxAge, capacity)
  local queue = {samples = {}, size = 0, total = 0, first = 1}
  local function pop()
    local sample = queue.samples[queue.first]
    queue.total = queue.total - sample.amount
    queue.samples[queue.first] = nil
    queue.first = queue.first % capacity + 1
    queue.size = queue.size - 1
  end
  function queue:prune(now)
    while self.size > 0 and now - self.samples[self.first].time > maxAge do pop() end
  end
  function queue:add(now, amount)
    self:prune(now)
    if self.size == capacity then pop() end
    local index = (self.first + self.size - 1) % capacity + 1
    self.samples[index] = {time = now, amount = amount}
    self.size = self.size + 1
    self.total = self.total + amount
  end
  return queue
end

function ElfBotHistory.prune(map, now, lifetime, capacity)
  local kept = 0
  for key, value in pairs(map) do
    local time = type(value) == 'number' and value or type(value) == 'table' and (value.time or value.updated)
    if type(time) ~= 'number' or time > now or now - time > lifetime or kept >= capacity then
      map[key] = nil
    else
      kept = kept + 1
    end
  end
end
