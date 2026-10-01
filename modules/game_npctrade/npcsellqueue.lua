-- Uses the real sale packet, one chunk at a time. PlayerGoods is the only
-- acknowledgment; a timer is a failure timeout, never permission to sell more.
NpcSellQueue = {}
NpcSellQueue.__index = NpcSellQueue

function NpcSellQueue.new(options)
  return setmetatable({ options = options, entries = {}, index = 1,
    sold = 0, proceeds = 0, packets = 0 }, NpcSellQueue)
end

function NpcSellQueue:cancel()
  self.active = false
  if self.timeout then
    self.options.cancel(self.timeout)
    self.timeout = nil
  end
  self.pending = nil
  self.entries = {}
end

function NpcSellQueue:fail(message)
  self:cancel()
  self.options.onError(message)
end

function NpcSellQueue:start(entries)
  self.entries = entries
  self.active = true
  self:advance()
end

function NpcSellQueue:advance()
  if not self.active or not self.options.isValid() then
    self:cancel()
    return
  end
  local entry = self.entries[self.index]
  while entry and self.options.quantity(entry) <= 0 do
    self.index = self.index + 1
    entry = self.entries[self.index]
  end
  if not entry then
    local sold, proceeds = self.sold, self.proceeds
    self:cancel()
    self.options.onFinish(sold, proceeds)
    return
  end
  if self.packets >= 1000 then
    self:fail('Sale stopped: too many chunks. Please refresh the shop.')
    return
  end
  local quantity = self.options.quantity(entry)
  local amount = math.min(100, quantity)
  self.pending = { entry = entry, quantity = quantity, amount = amount,
    money = self.options.money(), capped = self.options.capped and self.options.capped(entry) }
  self.packets = self.packets + 1
  self.timeout = self.options.schedule(function()
    self.timeout = nil
    if self.active and self.pending then
      self:fail('Sale stopped: the server did not confirm the sale. Please refresh the shop.')
    end
  end, 5000)
  self.options.sell(entry, amount)
end

function NpcSellQueue:onGoods()
  local pending = self.pending
  if not self.active or not pending or not self.options.isValid() then
    return
  end
  local quantity = self.options.quantity(pending.entry)
  local proceeds = self.options.money() - pending.money
  -- Legacy PlayerGoods caps quantities at 255. A successful sale can leave
  -- that capped count unchanged, but must still credit the quoted price.
  local countMatches = quantity == pending.quantity - pending.amount or
    (pending.capped and quantity >= pending.quantity - pending.amount)
  if proceeds ~= pending.entry.price * pending.amount or not countMatches then
    return -- an unrelated inventory/money update is not a sale acknowledgment
  end
  self.options.cancel(self.timeout)
  self.timeout = nil
  self.pending = nil
  self.sold = self.sold + pending.amount
  self.proceeds = self.proceeds + proceeds
  self.options.schedule(function() self:advance() end, 0)
end
