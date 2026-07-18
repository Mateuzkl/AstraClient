if not LoginEvent then
    LoginEvent = {
        event = nil,
        charInfo = {},
        loginTries = 0,
        internalTries = 1,
        loadBox = nil
    }
    LoginEvent.__index = LoginEvent
end

local self = LoginEvent

-- getters
function LoginEvent:getLoadBox() return self.loadBox end

function LoginEvent:setCharInfo(charInfo) self.charInfo = charInfo end

function LoginEvent:reset()
  consoleln("[+] LoginEvent.reset()")
  if self.event then
    removeEvent(self.event)
    self.event = nil
  end
  self.charInfo = {}
  self.internalTries = 1
  if self.loadBox then
    self:destroyLoadBox()
  end
end

function LoginEvent:tryLogin()
  consoleln("[+] LoginEvent.tryLogin()")
    local autoReconnect = getAutoReconnect(self.charInfo.characterName)

    -- Validate and sanitize character info
    local function validateField(field, fieldName)
        if type(field) ~= "string" or field == '' then
            g_logger.error(string.format("Invalid %s: %s", fieldName, tostring(field)))
            onGameConnectionError("", 16655)
            return false
        end
        return true
    end

    if not validateField(self.charInfo.characterName, "character name") or
        not validateField(self.charInfo.worldName, "world name") or
        not validateField(self.charInfo.worldHost, "world host") then
        return
    end

    if not self.charInfo.worldPort or not tonumber(self.charInfo.worldPort) or tonumber(self.charInfo.worldPort) <= 0 then
        g_logger.error(string.format("Invalid world port: %s", tostring(self.charInfo.worldPort)))
        onGameConnectionError("", 16655)
        return
    end

    if not validateField(G.account, "account name") or
        not validateField(G.password, "password") then
        return
    end

  if self.internalTries > 100 then
    onGameConnectionError("", 16654 )
    return
  end

  self.loginTries = self.loginTries + 1
  if autoReconnect == false and self.loginTries > 10 and not CharacterList.waiting then
    consoleln("LoginEvent.tryLogin() - Too many login attempts, stopping further attempts.")
    onGameConnectionError("", 16654 )
    return
  end

  if g_game.isOnline() then
    consoleln("[-] LoginEvent.tryLogin() - Already online, skipping login attempt.")
    if self.internalTries == 1 then
      g_game.doThing(false)
      g_game.safeLogout()
      g_game.doThing(true)
    end
    self.event = scheduleEvent(function() self.internalTries = self.internalTries + 1;self:tryLogin() end, 100)
    return
  end

    CharacterList.hide()

    local recordName = nil
    if CharacterList.camRecordCheck and CharacterList.camRecordCheck:isChecked() then
        recordName = string.format("%s_%s_%s.rec", self.charInfo.characterName, self.charInfo.worldName, os.date("%Y%m%d%H%M%S"))
    end

    local world = Worlds:getWorldByName(self.charInfo.worldName)
    if world then
        Proxies:changePort(world:getProtectedPort())
    end

    local gamePassword = G.password
    if not g_game.getFeature(GameAuthenticator) then
        local token = tostring(G.authenticatorToken or ""):gsub("%D", "")
        if token:len() > 0 then
            gamePassword = gamePassword .. "\n" .. token
        end
    end

    if modules.client_background and modules.client_background.clearExpectedCastCancelError then
        modules.client_background.clearExpectedCastCancelError()
    end

    local ok, err = pcall(function()
        g_game.loginWorld(
            G.account,
            gamePassword,
            self.charInfo.worldName,
            self.charInfo.worldHost,
            tonumber(self.charInfo.worldPort),
            self.charInfo.characterName,
            G.authenticatorToken,
            G.sessionKey,
            recordName
        )
    end)

    if not ok then
        g_logger.error(string.format("Game login failed: %s", tostring(err)))
        onGameConnectionError("", 16655)
        return
    end

    if not recordName then
        g_logger.info('\n----------------------------------------------------------------------------')
        g_logger.info(os.date("\n> Session started at %b %d %Y %X"))
        g_logger.info(string.format("\n> Login to the World: %s - (%s:%d)\n> Character Name: %s", 
            self.charInfo.worldName, self.charInfo.worldHost, self.charInfo.worldPort, self.charInfo.characterName))
        g_logger.info('\n> Starting Log ...\n')
        g_logger.info('-----------------------------------LOG--------------------------------------\n')
    end

  self:destroyLoadBox()

  -- save last used character
  g_settings.set('last-used-character', self.charInfo.characterName)
  g_settings.set('last-used-world', self.charInfo.worldName)
  g_settings.set('last-vocation', self.charInfo.vocation)
end

function LoginEvent:setNewEvent(charInfo)
    self:reset()
    self.charInfo = charInfo
    self:tryLogin()
end

function LoginEvent:cancelLogin()
    consoleln("[+] LoginEvent.cancelLogin()")
    if self.event then
        removeEvent(self.event)
        self.event = nil
    end

    if self.loadBox then
        self:destroyLoadBox()
    end

    if not g_game.isLogging() then
        return
    end

    local ok, err = pcall(function()
        g_game.doThing(false)
        g_game.cancelLogin()
        g_game.doThing(true)
    end)
    if not ok then
        g_logger.warning(string.format("Unable to cancel pending login: %s", tostring(err)))
        pcall(function() g_game.doThing(true) end)
    end
end

function LoginEvent:destroyLoadBox()
    if self.loadBox then
        disconnect(self.loadBox, { onCancel = function() end })
        self.loadBox:destroy()
        self.loadBox = nil
    end
end
