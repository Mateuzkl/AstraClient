-- Regression: handlers must preserve the next opcode in a shared frame.
-- Run: luajit .github/tests/item_details_opcode_framing.lua modules/game_protocol/protocol.lua src/client/protocolgameparse.cpp
local luaPath, cppPath = ...
assert(luaPath and cppPath, "usage: <protocol.lua> <protocolgameparse.cpp>")

local function u16(n)
  return string.char(n % 256, math.floor(n / 256) % 256)
end

local function u32(n)
  return u16(n % 65536) .. u16(math.floor(n / 65536))
end

local function str(v)
  return u16(#v) .. v
end

local Message = {}
Message.__index = Message

function Message:new(payload)
  return setmetatable({payload = payload, position = 1}, self)
end

function Message:getU8()
  local b = self.payload:byte(self.position)
  assert(b, "truncated U8")
  self.position = self.position + 1
  return b
end

function Message:getU16()
  return self:getU8() + self:getU8() * 256
end

function Message:getU32()
  return self:getU16() + self:getU16() * 65536
end

function Message:getString()
  local length = self:getU16()
  assert(self.position + length - 1 <= #self.payload, "truncated string")
  local value = self.payload:sub(self.position, self.position + length - 1)
  self.position = self.position + length
  return value
end

function Message:getUnreadSize()
  return #self.payload - self.position + 1
end

function Message:peekU16()
  local p = self.position
  local n = self:getU16()
  self.position = p
  return n
end

function Message:skipBytes(count)
  assert(count >= 0 and count <= self:getUnreadSize(), "invalid skip")
  self.position = self.position + count
end

local callbacks = {}
local registeredDetails
local values = {}
ProtocolGame = {
  registerOpcode = function(opcode, callback) callbacks[opcode] = callback end,
  unregisterOpcode = function(opcode) callbacks[opcode] = nil end
}
g_game = { onItemDetails = function() end, getFeature = function() return false end }
signalcall = function() end
ItemsDatabase = {
  registerServerItemDetails = function(itemId, data)
    registeredDetails = {itemId = itemId, data = data}
  end,
  registerServerItemValue = function(itemId, value)
    values[itemId] = value
  end
}

assert(loadfile(luaPath))()
registerProtocol()
assert(callbacks[0xC6] and callbacks[0xC7], "missing item handlers")

-- An ordinary 8.60 creature move: opcode, old position, stackpos, new position.
local move = string.char(0x6D) .. u16(32341) .. u16(31789) ..
             string.char(7, 1) .. u16(32342) .. u16(31789) .. string.char(7)

local details = string.char(0xC7) .. u16(2160) ..
                u32(77) .. u32(55) .. u32(33) .. string.char(1) ..
                str("Name") .. str("Test Sword") .. u16(1) ..
                str("Florentine") .. str("Carlin") .. u32(100) .. u32(200) .. str("")

local msg = Message:new(details .. move)
assert(msg:getU8() == 0xC7)
callbacks[0xC7](nil, msg)
assert(registeredDetails and registeredDetails.itemId == 2160)
assert(registeredDetails.data.name == "Test Sword")
assert(msg:getUnreadSize() == #move, "0xC7 consumed part of next movement")
assert(msg:getU8() == 0x6D, "movement opcode lost after 0xC7")
assert(msg:getU16() == 32341)

local batch = string.char(0xC6) .. u16(2) ..
              u16(2160) .. u32(60) .. u16(3000) .. u32(100)
local valueMsg = Message:new(batch .. move)
assert(valueMsg:getU8() == 0xC6)
callbacks[0xC6](nil, valueMsg)
assert(values[2160] == 60 and values[3000] == 100)
assert(valueMsg:getUnreadSize() == #move, "0xC6 consumed part of next movement")
assert(valueMsg:getU8() == 0x6D)

-- Several independent item opcodes and a large values batch share one frame.
local entries = {}
for i = 1, 200 do entries[i] = u16(4000 + i) .. u32(i) end
local largeValues = string.char(0xC6) .. u16(#entries) .. table.concat(entries)
local chain = Message:new(details .. largeValues .. details .. move)
for _, opcode in ipairs({0xC7, 0xC6, 0xC7}) do
  assert(chain:getU8() == opcode)
  callbacks[opcode](nil, chain)
end
assert(values[4200] == 200)
assert(chain:getUnreadSize() == #move and chain:getU8() == 0x6D,
       "coalesced metadata handlers lost the following movement")

local empty = Message:new(u16(1) .. u32(0) .. u32(0) .. u32(0) .. string.char(0) .. u16(0) .. move)
callbacks[0xC7](nil, empty)
assert(empty:getUnreadSize() == #move and empty:getU8() == 0x6D)

local f = assert(io.open(cppPath, "rb"))
local native = assert(f:read("*a"))
f:close()
local startAt = assert(native:find("void ProtocolGame::parseCustomItemDetails", 1, true))
local endAt = assert(native:find("void ProtocolGame::parseKillTracker", startAt, true))
local detailParser = native:sub(startAt, endAt - 1)
assert(not detailParser:find("skipBytes(msg->getUnreadSize())", 1, true),
       "native 0xC7 still drains the shared frame")
assert(not detailParser:find("peekU16()", 1, true),
       "native 0xC7 still guesses an unframed optional string")

print("item values/details coalesced-frame regression: OK")
