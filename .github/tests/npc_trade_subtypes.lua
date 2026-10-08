local tradeScript = assert(arg[1], 'missing npctrade.lua')
local sessionScript = assert(arg[2], 'missing npcsession.lua')
local queueScript = assert(arg[3], 'missing npcsellqueue.lua')
local scheduled, sent, warnings = {}, {}, {}
scheduleEvent = function(callback)
  local event = { callback = callback }
  scheduled[#scheduled + 1] = event
  return event
end
removeEvent = function(event) if event then event.cancelled = true end end
GOLD_COINS, ThingCategoryItem = 2148, 0
tr = function(text, ...) return string.format(text, ...) end
short_text = function(text, length) return text:sub(1, length) end
displayInfoBox = function(_, text) warnings[#warnings + 1] = text end
local player = {
  getFreeCapacity = function() return 1000 end,
  getInventoryItem = function() return nil end
}
g_game = {
  isOnline = function() return true end,
  getLocalPlayer = function() return player end,
  sellItem = function(item, amount) sent[#sent + 1] = { id = item:getId(), amount = amount } end
}
local types = {}
g_things = { getThingType = function(id) return types[id] end }

local function item(id, subtype, flags)
  flags = flags or {}
  types[id] = {
    isFluidContainer = function() return flags.fluid == true end,
    isSplash = function() return flags.splash == true end,
    isChargeable = function() return flags.charges == true end
  }
  return {
    getId = function() return id end,
    getCountOrSubType = function() return subtype end,
    isStackable = function() return flags.stackable == true end,
    isFluidContainer = types[id].isFluidContainer,
    isChargeableByCategory = function() return flags.chargeCategory == true end
  }
end
assert(loadfile(sessionScript))()
assert(loadfile(queueScript))()
assert(loadfile(tradeScript))()
local currencyWidget = setmetatable({}, { __index = function() return function() end end })
currencyItem, itemBorder, currencyMoneyLabel, currencyLabel = currencyWidget, currencyWidget, currencyWidget, currencyWidget

local function shop(items)
  sent, warnings = {}, {}
  local offers, goods = {}, {}
  for _, ptr in ipairs(items) do
    offers[#offers + 1] = { ptr, 'Test item', 100, 0, 10 }
    goods[#goods + 1] = { ptr, 20 }
  end
  onOpenNpcTrade(offers)
  onPlayerGoods(0, goods)
end

-- Only one shop variant is listed. ID-only goods could include unseen variants
-- in closed containers, so there must be no outgoing automated sale packet.
for _, unsafe in ipairs({
  item(100, 5), -- non-fluid subtype
  item(101, 0, { charges = true }), -- legacy shop hides charges behind subtype 0
  item(102, 0, { chargeCategory = true }),
  item(103, 1, { fluid = true }),
  item(104, 0, { splash = true })
}) do
  shop({ unsafe })
  assert(not sellAll(), 'subtype-dependent inventory was accepted for bulk selling')
  assert(#sent == 0 and #warnings == 1, 'an ambiguous subtype generated a sale packet')
end

local ordinary = item(200, 0)
local stackable = item(201, 100, { stackable = true })
shop({ ordinary })
assert(sellAll() and #sent == 1 and sent[1].amount == 20, 'ordinary loot can no longer be sold')
shop({ stackable })
assert(sellAll() and #sent == 1, 'a stack count was mistaken for a subtype')

-- Preflight the entire selection: an unsafe later entry must not allow an
-- earlier safe entry to be sold before the batch is rejected.
local unsafe = item(300, 2)
shop({ ordinary, unsafe })
assert(not sellAll() and #sent == 0)
assert(sellAll({ 300 }) and #sent == 1, 'the caller cannot exclude an unsafe item')
print('NPC automated sale subtype safety: passed')
