local _Position = {}
local structPos = {
  x = 0,
  y = 0,
  z = 0,
  stakpos = 0,
}

function _Position.create(pdata)
  local obj = structPos
  obj.x = pdata.x
  obj.y = pdata.y
  obj.z = pdata.z
  return setmetatable(obj, { __index = _Position })
end

function printPosBuff(self)
  return string.format("Position(%d, %d, %d)", self.x, self.y, self.z)
end

function NetPosition(tb)
  return _Position.create(tb)
end

-- tamanho da tabela
local NETWORKMESSAGE_MAXSIZE = 34590
local NETWORKMESSAGE_INPUT_MAXSIZE = 1000

-- buffer que comeca a contar
local INITIAL_BUFFER_POSITION = 8
local HEADER_LENGTH = 2
local CHECKSUM_LENGTH = 4
local XTEA_MULTIPLE = 8
local MAX_BODY_LENGTH = NETWORKMESSAGE_MAXSIZE - HEADER_LENGTH - CHECKSUM_LENGTH - XTEA_MULTIPLE
local MAX_PROTOCOL_BODY_LENGTH = MAX_BODY_LENGTH - 10

-- criando a metatable//class
NetworkMessage = {}
local struct = {
  position = 1,
  length = 0,
  overrun = false,
  buffer = {},
}
function NetworkMessage.create(pdata)
  local obj = struct
  obj.buffer = pdata
  obj.length = #pdata
  return setmetatable(obj, { __index = NetworkMessage })
end

-- resetando a classe
function NetworkMessage:reset()
  self.position = struct.position
  self.length = struct.length
  self.buffer = struct.buffer
  self.overrun = struct.overrun
end

-- obtendo o primeiro byte
function NetworkMessage:getByte()
  if (not self:canRead(1)) then
    return 0
  end
  local pos = self.position
  self.position = self.position + 1

  return self.buffer[pos]
end

-- pulando bytes
function NetworkMessage:skipBytes(count)
  self.position = self.position + count
end

-- retornando a posicao do byte atual
function NetworkMessage:getBufferPosition()
  return self.position
end

-- pegando o byte uint16_t
function NetworkMessage:getU16()
  if (not self:canRead(2)) then
    return 0
  end
  local pos = self.position
  self.position = self.position + 2
  local value = 0x00
  for i = pos, self.position - 1, 1 do
    value = self.buffer[i] + value
  end

  return value
end

-- pegando qualquet tamanho de bytes
--[[
  1 = uint8
  2 = uint16
  4 = uint32
  8 = uint64
]]
function NetworkMessage:readBytes(size)
  if (not self:canRead(size - 1)) then
    return 0
  end
  local pos = self.position
  self.position = self.position + size
  local value = 0x00
  local byte = 0
  for i = pos, self.position - 1, 1 do
    byte = byte + 1
    value = value + (self.buffer[i] * (256 ^ (byte - 1)))
  end

  return value
end

-- pegando uma string
--[[
  na tabela
  {byte1_tamanho, byte2_tamanho, ...(conteudo)}
  exemplo
  {0x01, 0x0, 0x61}
  0x01 + 0x0 = o tamanho da string = 1
  como o tamanho da string é 1, vai pegar o valor dps delas, no caso 0x61, que convertendo para string = 'A'
]]
function NetworkMessage:getString()
  local size = self:getU16()
  if size == 0 or not self:canRead(size - 1) then
    print(size)
    return false
  end
  local str = ''

  for byte = 0, size - 1 do
    str = string.format("%s%s", str, string.char(self.buffer[self.position + byte]))
  end

  self.position = self.position + size
  return str
end

function NetworkMessage:addString(str)
  if not self:addBytes(#str, 2, false) then
    return false
  end

  local size = str:len()
  for i = 1, size do
    local _str = string.sub(str, i, i)
    local bt = _str:byte()
    self.position = self.position + 1
    self.buffer[self.position] = bt
  end
  self.length = self.length + #str
  return true
end

function NetworkMessage:addBytes(value, count, signed)
  if signed then
    value = value * 2
  end

  if value >= (256 ^ count) then
    return false
  end

  for byte = count, 1, -1 do
    local power = (256 ^ (byte - 1))
    self.position = self.position + 1
    self.buffer[self.position] = math.floor(value / power)
    value = value % power
  end

  self.length = self.length + count
  return true
end

function NetworkMessage:getRanges(byteCount, signed)
  local min, max = 0, ((256 ^ byteCount) - 1)
  if (signed) then
    max = math.floor(max / 2)
    min = -max - 1
  end
  return -min, max
end

function NetworkMessage:canRead(size)
  if ((self.position + size) > (self.length + 8) or size >= (NETWORKMESSAGE_MAXSIZE - self.position)) then
    self.overrun = true
    return false
  end
  return true
end

-- readBs
--unsigned int -- somente numeros positivos
function NetworkMessage:getU8()
  return self:readBytes(1, false)
end

function NetworkMessage:getU16()
  return self:readBytes(2, false)
end

function NetworkMessage:getU32()
  return self:readBytes(4, false)
end

function NetworkMessage:getU64()
  return self:readBytes(8, false)
end

-- contando numeros positivos e negativos
function NetworkMessage:getI8()
  return self:readBytes(1, true)
end

function NetworkMessage:getI16()
  return self:readBytes(2, true)
end

function NetworkMessage:getI32()
  return self:readBytes(4, true)
end

function NetworkMessage:getI64()
  return self:readBytes(8, true)
end

function NetworkMessage:addPosition(position)
  self:addU16(position.x)
  self:addU16(position.y)
  self:addU8(position.z)
end

function NetworkMessage:getPosition()
  local tmp = {}
  tmp.x = self:getU16()
  tmp.y = self:getU16()
  tmp.z = self:getU8()
  return NetPosition(tmp)
end

-- AddBytes
-- unsigned
function NetworkMessage:addU8(value)
  return self:addBytes(value, 1, false)
end

function NetworkMessage:addU16(value)
  return self:addBytes(value, 2, false)
end

function NetworkMessage:addU32(value)
  return self:addBytes(value, 4, false)
end

function NetworkMessage:addU64(value)
  return self:addBytes(value, 8, false)
end

-- signed
function NetworkMessage:addI8(value)
  return self:addBytes(value, 1, true)
end

function NetworkMessage:addI16(value)
  return self:addBytes(value, 2, true)
end

function NetworkMessage:addI32(value)
  return self:addBytes(value, 4, true)
end

function NetworkMessage:addI64(value)
  return self:addBytes(value, 8, true)
end
