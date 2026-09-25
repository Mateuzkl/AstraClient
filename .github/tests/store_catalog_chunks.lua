local scriptPath = assert(arg[1], "missing storeprotocol.lua path")
local callback
local completedCategories
local displayedOffers
local lastError
local chunkTimeout

OFFER_STATE_NONE = 0
OFFER_STATE_NEW = 1
OFFER_STATE_SALE = 2
OFFER_STATE_TIMED = 3
CATEGORY_ITEM = 0
CATEGORY_MOUNT = 1
CATEGORY_OUTFIT = 2
CATEGORY_HIRELING = 3
COIN_TYPE_DEFAULT = 0
OPEN_HOME = 0
OPEN_SEARCH = 1
OPEN_OFFER = 2
SERVICE_OFFER_ID = 3
GameIngameStoreHighlights = 100
GameAstraStoreBasePrice = 101
DEVELOPERMODE = false

Store = { profileStep = function() end }
StoreWindow = nil
Offers = nil
g_clock = { millis = function() return 1 end }
g_game = {
  getFeature = function(feature)
    return feature == GameIngameStoreHighlights or feature == GameAstraStoreBasePrice
  end,
  isOnline = function() return true end,
  getProtocolGame = function() return nil end,
  onStoreInit = function() end,
  onCoinBalance = function() end,
  onStoreHomeOffers = function() end,
  onStoreCategories = function(value) completedCategories = value end,
  onStoreOffers = function(_, offers) displayedOffers = offers end,
  onStoreError = function(_, message) lastError = message end
}
OutputMessage = {
  create = function()
    return { addU8 = function() end }
  end
}
ProtocolGame = {
  unregisterOpcode = function() end,
  registerOpcode = function(_, handler) callback = handler end
}
removeEvent = function() end
scheduleEvent = function(handler, delay)
  if delay == 10000 then
    chunkTimeout = handler
  end
  return handler
end
connect = function() end
disconnect = function() end
signalcall = function(handler, ...)
  if handler then
    return handler(...)
  end
end

local function makeMessage(tokens)
  local index = 1
  local function read(expected)
    local token = assert(tokens[index], "unexpected end of message")
    assert(token[1] == expected, string.format("expected %s, got %s at token %d", expected, token[1], index))
    index = index + 1
    return token[2]
  end

  return {
    getU8 = function() return read("u8") end,
    getU16 = function() return read("u16") end,
    getU32 = function() return read("u32") end,
    getString = function() return read("string") end,
    getUnreadSize = function() return #tokens - index + 1 end,
    skipBytes = function(_, count) index = math.min(#tokens + 1, index + count) end
  }
end

local function appendCategoryPart(tokens, offerId, name, lookType)
  local function add(kind, value) tokens[#tokens + 1] = { kind, value } end
  add("string", "Outfits")
  add("string", "store_outfits")
  add("string", "Cosmetics")
  add("string", "Outfit offers")
  add("u8", OFFER_STATE_NONE)
  add("u16", 1)
  add("u32", offerId)
  add("string", name)
  add("string", "")
  add("u32", 100)
  add("u32", 100)
  add("u16", lookType)
  add("u16", 1)
  add("string", name .. " description")
  add("string", "outfit")
  add("u8", OFFER_STATE_NONE)
end

assert(loadfile(scriptPath))()
initStoreProtocol()
assert(callback, "store opcode callback was not registered")

local first = {
  { "u8", 4 },
  { "u8", 1 },
  { "u32", 999 },
  { "u16", 1 },
  { "u16", 1 }
}
appendCategoryPart(first, 70001, "First Outfit", 1001)
callback(nil, makeMessage(first))
assert(completedCategories == nil, "partial catalog emitted categories")
g_game.requestStoreOffers("Outfits", "", 0)
assert(displayedOffers == nil, "partial catalog displayed offers")
assert(chunkTimeout, "partial catalog did not arm a recovery timeout")

local last = {
  { "u8", 4 },
  { "u8", 2 },
  { "u32", 999 },
  { "u16", 1 },
  { "u16", 2 }
}
appendCategoryPart(last, 70001, "First Outfit Updated", 1001)
appendCategoryPart(last, 70002, "Second Outfit", 1002)
last[#last + 1] = { "u8", 0 }
last[#last + 1] = { "u8", 10 }
callback(nil, makeMessage(last))

assert(#completedCategories == 1, "repeated category parts created duplicate categories")
g_game.requestStoreOffers("Outfits", "", 0)
assert(#displayedOffers == 2, "offers from catalog chunks were not merged")
assert(displayedOffers[1].id == 70001 and displayedOffers[2].id == 70002, "catalog chunk order changed")
assert(displayedOffers[1].name == "First Outfit Updated", "replayed offer did not replace its existing entry")

lastError = nil
callback(nil, makeMessage({
  { "u8", 4 },
  { "u8", 4 },
  { "u32", 999 },
  { "u16", 0 },
  { "u16", 0 }
}))
assert(lastError == "Invalid Store catalog chunk flags.", "unknown chunk flags were accepted")

completedCategories = nil
lastError = nil
local interrupted = {
  { "u8", 4 },
  { "u8", 1 },
  { "u32", 999 },
  { "u16", 1 },
  { "u16", 1 }
}
appendCategoryPart(interrupted, 70003, "Interrupted Outfit", 1003)
callback(nil, makeMessage(interrupted))
callback(nil, makeMessage({ { "u8", 0 }, { "string", "Catalog failed." } }))
assert(lastError == "Catalog failed.", "catalog error was not reported")

lastError = nil
callback(nil, makeMessage({
  { "u8", 4 },
  { "u8", 2 },
  { "u32", 999 },
  { "u16", 1 },
  { "u16", 0 }
}))
assert(lastError == "Invalid Store catalog chunk sequence.", "late chunk was accepted after an error")
assert(completedCategories == nil, "failed catalog was published by a late chunk")

lastError = nil
callback(nil, makeMessage(interrupted))
assert(chunkTimeout, "restarted catalog did not arm a recovery timeout")
chunkTimeout()
assert(lastError == "Store catalog transfer timed out. Please reopen the Store.", "chunk timeout did not abort the catalog")

completedCategories = nil
lastError = nil
callback(nil, makeMessage({
  { "u8", 4 },
  { "u8", 3 },
  { "u32", 999 },
  { "u16", 0 },
  { "u16", 0 },
  { "u8", 0 },
  { "u8", 10 }
}))
assert(completedCategories and #completedCategories == 0, "catalog did not recover after timeout")
assert(lastError == nil, "catalog recovery reported an unexpected error")

print("store catalog chunks: OK")
