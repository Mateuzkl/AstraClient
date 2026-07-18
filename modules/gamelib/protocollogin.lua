-- @docclass
ProtocolLogin = extends(Protocol, "ProtocolLogin")

LoginServerError = 10
LoginServerTokenSuccess = 12
LoginServerTokenError = 13
LoginServerUpdate = 17
LoginServerMotd = 20
LoginServerUpdateNeeded = 30
LoginServerSessionKey = 40
LoginServerCharacterList = 100
LoginServerExtendedCharacterList = 101
LoginServerProxyList = 110
LoginServerAstraBoostedInfo = 0xA1
LoginServerAstraCastList = 0xA2

local AstraCastListVersion = 1
local AstraCastListLimit = 255

local AstraClientMarker = "A"

local function rotateLeft(value, bits)
  return bit32.bor(bit32.lshift(value, bits), bit32.rshift(value, 32 - bits))
end

local function mixAstraClientSignature(hash, value)
  hash = bit32.bxor(hash, (value + 0x9E3779B9 + bit32.lshift(hash, 6) + bit32.rshift(hash, 2)) % 0x100000000)
  return bit32.bxor(rotateLeft(hash, 7), bit32.rshift(value, 3))
end

local function generateAstraClientSignature(os, version, xteaKey, challengeTimestamp, challengeRandom)
  local hash = 0xA57AC11E
  hash = mixAstraClientSignature(hash, 0x41737472)
  hash = mixAstraClientSignature(hash, 0x61436C69)
  hash = mixAstraClientSignature(hash, os)
  hash = mixAstraClientSignature(hash, version)
  for i = 1, 4 do
    hash = mixAstraClientSignature(hash, xteaKey[i] or 0)
  end
  hash = mixAstraClientSignature(hash, challengeTimestamp or 0)
  hash = mixAstraClientSignature(hash, challengeRandom or 0)
  return bit32.bxor(hash, 0x4D415354)
end

-- Since 10.76
LoginServerRetry = 10
LoginServerErrorNew = 11

function ProtocolLogin:login(host, port, accountName, accountPassword, authenticatorToken, stayLogged)
  if string.len(host) == 0 or port == nil or port == 0 then
    signalcall(self.onLoginError, self, tr("You must enter a valid server address and port."))
    return
  end

  self.accountName = accountName
  self.accountPassword = accountPassword
  self.authenticatorToken = authenticatorToken
  self.stayLogged = stayLogged
  self.connectCallback = self.sendLoginPacket

  self:connect(host, port)
end

function ProtocolLogin:cancelLogin()
  self:disconnect()
end

function ProtocolLogin:sendLoginPacket()
  local msg = OutputMessage.create()
  msg:addU8(ClientOpcodes.ClientEnterAccount)
  local operatingSystem = g_game.getOs()
  msg:addU16(operatingSystem)
  local protocolVersion
  if g_game.getCustomProtocolVersion() > 0 then
    protocolVersion = g_game.getCustomProtocolVersion()
  else
    protocolVersion = g_game.getProtocolVersion()
  end
  msg:addU16(protocolVersion)

  if g_game.getFeature(GameClientVersion) then
    msg:addU32(g_game.getClientVersion())
  end

  if g_game.getFeature(GameContentRevision) then
    msg:addU16(g_things.getContentRevision())
    msg:addU16(0)
  else
    msg:addU32(g_things.getDatSignature())
  end
  msg:addU32(g_sprites.getSprSignature())
  msg:addU32(PIC_SIGNATURE)

  if g_game.getFeature(GamePreviewState) then
    msg:addU8(0)
  end

  local offset = msg:getMessageSize()
  if g_game.getFeature(GameLoginPacketEncryption) then
    -- first RSA byte must be 0
    msg:addU8(0)

    -- xtea key
    self:generateXteaKey()
    local xteaKey = self:getXteaKey()
    msg:addU32(xteaKey[1])
    msg:addU32(xteaKey[2])
    msg:addU32(xteaKey[3])
    msg:addU32(xteaKey[4])
  end

  if g_game.getFeature(GameAccountNames) then
    msg:addString(self.accountName)
  else
    msg:addU32(tonumber(self.accountName))
  end

  local accountPassword = self.accountPassword
  if not g_game.getFeature(GameAuthenticator) then
    local token = tostring(self.authenticatorToken or ""):gsub("%D", "")
    if token:len() > 0 then
      accountPassword = accountPassword .. "\n" .. token
    end
  end

  msg:addString(accountPassword)

  msg:addString(AstraClientMarker)
  msg:addU32(generateAstraClientSignature(operatingSystem, protocolVersion, self:getXteaKey(), 0, 0))

--[[  if self.getLoginExtendedData then
    local data = self:getLoginExtendedData()
    msg:addString(data)
  else
    msg:addString("OTCv8")
    local version = g_app.getVersion():split(" ")[1]:gsub("%.", "")
    if version:len() == 2 then
      version = version .. "0"
    end
    msg:addU16(tonumber(version))
  end--]]

  local paddingBytes = g_crypt.rsaGetSize() - (msg:getMessageSize() - offset)
  assert(paddingBytes >= 0)
  for i = 1, paddingBytes do
    msg:addU8(math.random(0, 0xff))
  end

  if g_game.getFeature(GameLoginPacketEncryption) then
    msg:encryptRsa()
  end

  if g_game.getFeature(GameOGLInformation) then
    msg:addU8(1) --unknown
    msg:addU8(1) --unknown

    if g_game.getProtocolVersion() >= 1072 then
      msg:addString(string.format('%s %s', g_graphics.getVendor(), g_graphics.getRenderer()))
    else
      msg:addString(g_graphics.getRenderer())
    end
    msg:addString(g_graphics.getVersion())
  end

  -- add RSA encrypted auth token
  if g_game.getFeature(GameAuthenticator) then
    offset = msg:getMessageSize()

    -- first RSA byte must be 0
    msg:addU8(0)
    msg:addString(self.authenticatorToken)

    if g_game.getFeature(GameSessionKey) then
      msg:addU8(booleantonumber(self.stayLogged))
    end

    paddingBytes = g_crypt.rsaGetSize() - (msg:getMessageSize() - offset)
    assert(paddingBytes >= 0)
    for i = 1, paddingBytes do
      msg:addU8(math.random(0, 0xff))
    end

    msg:encryptRsa()
  end

  if g_game.getFeature(GamePacketSizeU32) then
    self:enableBigPackets()
  end

  if g_game.getFeature(GameProtocolChecksum) then
    self:enableChecksum()
  end

  self:send(msg)
  if g_game.getFeature(GameLoginPacketEncryption) then
    self:enableXteaEncryption()
  end
  self:recv()
end

function ProtocolLogin:onConnect()
  self.gotConnection = true
  self:connectCallback()
  self.connectCallback = nil
end

function ProtocolLogin:onRecv(msg)
  while not msg:eof() do
    local opcode = msg:getU8()
    if opcode == LoginServerErrorNew then
      self:parseError(msg)
    elseif opcode == LoginServerError then
      self:parseError(msg)
    elseif opcode == LoginServerMotd then
      self:parseMotd(msg)
    elseif opcode == LoginServerUpdateNeeded then
      signalcall(self.onLoginError, self, tr("Client needs update."))
    elseif opcode == LoginServerTokenSuccess then
      local unknown = msg:getU8()
    elseif opcode == LoginServerTokenError then
      -- TODO: prompt for token here
      local unknown = msg:getU8()
      signalcall(self.onLoginError, self, tr("Invalid authentification token."))
    elseif opcode == LoginServerCharacterList then
      self:parseCharacterList(msg)
    elseif opcode == LoginServerExtendedCharacterList then
      self:parseExtendedCharacterList(msg)
    elseif opcode == LoginServerUpdate then
      local signature = msg:getString()
      signalcall(self.onUpdateNeeded, self, signature)
    elseif opcode == LoginServerSessionKey then
      self:parseSessionKey(msg)
    elseif opcode == LoginServerProxyList then
      local proxies = {}
      local proxiesCount = msg:getU8()
      for i=1, proxiesCount do
        local host = msg:getString()
        local port = msg:getU16()
        local priority = msg:getU16()
        table.insert(proxies, {host=host, port=port, priority=priority})
      end
      signalcall(self.onProxyList, self, proxies)
    elseif opcode == LoginServerAstraCastList then
      self:parseAstraCastList(msg)
    else
      self:parseOpcode(opcode, msg)
    end
  end
  self:disconnect()
end

function ProtocolLogin:parseError(msg)
  local errorMessage = msg:getString()
  signalcall(self.onLoginError, self, errorMessage)
end

function ProtocolLogin:parseMotd(msg)
  local motd = msg:getString()
  signalcall(self.onMotd, self, motd)
end

function ProtocolLogin:parseSessionKey(msg)
  local sessionKey = msg:getString()
  signalcall(self.onSessionKey, self, sessionKey)
end

local function readLoginBoostedEntry(msg)
  if msg:getU8() == 0 then
    return nil
  end

  return {
    raceId = msg:getU32(),
    name = msg:getString(),
    outfit = {
      type = msg:getU16(),
      auxType = 0,
      head = msg:getU8(),
      body = msg:getU8(),
      legs = msg:getU8(),
      feet = msg:getU8(),
      addons = msg:getU8()
    }
  }
end

local function parseAstraBoostedInfo(msg, account)
  if msg:getUnreadSize() < 1 then
    return
  end

  local marker = msg:getU8()
  if marker ~= LoginServerAstraBoostedInfo then
    return
  end

  account.boostedCreature = readLoginBoostedEntry(msg)
  account.boostedBoss = readLoginBoostedEntry(msg)
end

function ProtocolLogin:parseCharacterList(msg)
  local characters = {}

  if g_game.getProtocolVersion() > 1010 then
    local worlds = {}

    local worldsCount = msg:getU8()
    for i=1, worldsCount do
      local world = {}
      local worldId = msg:getU8()
      world.worldName = msg:getString()
      world.worldIp = msg:getString()
      world.worldPort = msg:getU16()
      world.previewState = msg:getU8()
      worlds[worldId] = world
    end

    local charactersCount = msg:getU8()
    for i=1, charactersCount do
      local character = {}
      local worldId = msg:getU8()
      character.name = msg:getString()
      character.worldName = worlds[worldId].worldName
      character.worldIp = worlds[worldId].worldIp
      character.worldPort = worlds[worldId].worldPort
      character.previewState = worlds[worldId].previewState
      characters[i] = character
    end

  else
    local charactersCount = msg:getU8()
    for i=1,charactersCount do
      local character = {}
      character.name = msg:getString()
      character.worldName = msg:getString()
      character.worldIp = iptostring(msg:getU32())
      character.worldPort = msg:getU16()

      if g_game.getFeature(GamePreviewState) then
        character.previewState = msg:getU8()
      end

      characters[i] = character
    end
  end

  local account = {}
  if g_game.getProtocolVersion() > 1077 then
    account.status = msg:getU8()
    account.subStatus = msg:getU8()

    account.premDays = msg:getU32()
    if account.premDays ~= 0 and account.premDays ~= 65535 then
      account.premDays = math.floor((account.premDays - os.time()) / 86400)
    end
  else
    account.status = AccountStatus.Ok
    account.premDays = msg:getU16()
    account.subStatus = account.premDays > 0 and SubscriptionStatus.Premium or SubscriptionStatus.Free
  end

  signalcall(self.onCharacterList, self, characters, account)
end

function ProtocolLogin:parseExtendedCharacterList(msg)
  if g_game.getProtocolVersion() <= 1010 then
    local characters = {}
    local charactersCount = msg:getU8()

    for i = 1, charactersCount do
      local character = {}
      character.name = msg:getString()
      character.worldName = msg:getString()
      character.worldIp = iptostring(msg:getU32())
      character.worldHost = character.worldIp
      character.worldPort = msg:getU16()
      character.worldId = 0
      character.pvpType = 0
      character.outfit = {
        type = msg:getU16(),
        head = msg:getU8(),
        body = msg:getU8(),
        legs = msg:getU8(),
        feet = msg:getU8(),
        addons = msg:getU8()
      }
      character.level = msg:getU32()
      character.vocation = msg:getString()
      characters[i] = character
    end

    local account = {}
    account.status = AccountStatus.Ok
    account.premDays = msg:getU16()
    account.subStatus = account.premDays > 0 and SubscriptionStatus.Premium or SubscriptionStatus.Free
    parseAstraBoostedInfo(msg, account)
    signalcall(self.onCharacterList, self, characters, account)
    return
  end

  local characters = msg:getTable()
  local account = msg:getTable()
  local otui = msg:getString()
  signalcall(self.onCharacterList, self, characters, account, otui)
end

-- Direct login-server response used by the Astra login screen. It deliberately
-- contains no cast passwords: only the protected flag and the game-world endpoint.
function ProtocolLogin:parseAstraCastList(msg)
  local ok, response = pcall(function()
    local version = msg:getU8()
    if version ~= AstraCastListVersion then
      error(string.format('unsupported cast list version: %d', version))
    end

    local world = msg:getString()
    local host = iptostring(msg:getU32())
    local port = msg:getU16()
    local count = msg:getU16()
    local totalViewers = msg:getU32()

    if count > AstraCastListLimit then
      error(string.format('cast list is too large: %d', count))
    end
    if port == 0 then
      error('cast game-world port is invalid')
    end

    local casts = {}
    for i = 1, count do
      casts[i] = {
        name = msg:getString(),
        viewers = msg:getU16(),
        haspassword = bit32.band(msg:getU8(), 1) ~= 0,
        world = world,
        host = host,
        port = port
      }
    end

    return {
      casts = casts,
      totalViewers = totalViewers
    }
  end)

  if not ok then
    signalcall(self.onLoginError, self, tr('Invalid cast list received from the server.'))
    g_logger.warning('Invalid Astra cast list packet: ' .. tostring(response))
    return
  end

  signalcall(self.onCastList, self, response.casts, response.totalViewers)
end

function ProtocolLogin:parseOpcode(opcode, msg)
  signalcall(self.onOpcode, self, opcode, msg)
end

function ProtocolLogin:onError(msg, code)
  local text = translateNetworkError(code, self:isConnecting(), msg)
  signalcall(self.onLoginError, self, text)
end
