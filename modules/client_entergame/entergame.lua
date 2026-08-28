-- client_entergame: pixel-art login screen.
-- Widget styles live in data/styles/40-entergame.otui. No new sprites, no new fonts.

EnterGame = {}

local enterGame
local loginPanel
local emailInput, passwordInput
local emailEye, passwordEye
local rememberEmailBox, rememberPasswordBox, autoLoginBox
local loginButton
local autoLoginFired = false

local CLICK_SOUND = '/sounds/click.ogg'

local function playClick()
  -- setClickSound is a no-op in this fork (corelib/globals.lua stub); play it here.
  if g_sounds then
    local channel = g_sounds.getChannel(SoundChannels.Effect)
    if channel then channel:play(CLICK_SOUND) end
  end
end

local function saveSettings()
  g_settings.set('remember-email', rememberEmailBox:isChecked())
  g_settings.set('remember-password', rememberPasswordBox:isChecked())
  g_settings.set('auto-login', autoLoginBox:isChecked())

  if rememberEmailBox:isChecked() then
    g_settings.set('account-name', emailInput:getText())
  else
    g_settings.set('account-name', '')
  end

  if rememberPasswordBox:isChecked() then
    g_settings.set('account-password', g_crypt.encrypt(passwordInput:getText()))
  else
    g_settings.set('account-password', '')
  end

  g_settings.save()
end

local function loadSettings()
  rememberEmailBox:setChecked(g_settings.getBoolean('remember-email', true))
  rememberPasswordBox:setChecked(g_settings.getBoolean('remember-password', false))
  autoLoginBox:setChecked(g_settings.getBoolean('auto-login', false))

  if rememberEmailBox:isChecked() then
    emailInput:setText(g_settings.get('account-name', ''))
  end

  if rememberPasswordBox:isChecked() then
    local stored = g_settings.get('account-password', '')
    if stored ~= '' then
      passwordInput:setText(g_crypt.decrypt(stored))
    end
  end
end

local function updateLoginState()
  local ready = emailInput:getText() ~= '' and passwordInput:getText() ~= ''
  loginButton:setEnabled(ready)
end

local function tryAutoLogin()
  if autoLoginFired then return end
  if not autoLoginBox:isChecked() then return end
  if emailInput:getText() == '' or passwordInput:getText() == '' then return end
  autoLoginFired = true
  scheduleEvent(function() EnterGame.doLogin() end, 200)
end

function init()
  enterGame = g_ui.displayUI('entergame')
  loginPanel = enterGame:getChildById('loginPanel')

  emailInput = enterGame:recursiveGetChildById('emailInput')
  passwordInput = enterGame:recursiveGetChildById('passwordInput')
  emailEye = enterGame:recursiveGetChildById('emailEye')
  passwordEye = enterGame:recursiveGetChildById('passwordEye')
  rememberEmailBox = enterGame:recursiveGetChildById('rememberEmail')
  rememberPasswordBox = enterGame:recursiveGetChildById('rememberPassword')
  autoLoginBox = enterGame:recursiveGetChildById('autoLogin')
  loginButton = enterGame:recursiveGetChildById('loginButton')

  -- both fields start masked; the eye toggles reveal them independently
  emailInput:setTextHidden(true)
  passwordInput:setTextHidden(true)
  emailEye:setChecked(false)
  passwordEye:setChecked(false)

  emailInput.onTextChange = updateLoginState
  passwordInput.onTextChange = updateLoginState

  connect(enterGame, { onKeyPress = function(self, keyCode, keyboardModifiers)
    if keyCode == KeyEnter or keyCode == KeyNumpadEnter then
      EnterGame.doLogin()
      return true
    end
    return false
  end })

  loadSettings()
  updateLoginState()
  emailInput:focus()
  tryAutoLogin()
end

function terminate()
  saveSettings()
  if enterGame then
    enterGame:destroy()
    enterGame = nil
  end
end

function EnterGame.show()
  if enterGame then
    enterGame:show()
    enterGame:raise()
    enterGame:focus()
    emailInput:focus()
  end
end

function EnterGame.hide()
  if enterGame then enterGame:hide() end
end

function EnterGame.onEmailEyeChange(widget)
  emailInput:setTextHidden(not widget:isChecked())
  playClick()
end

function EnterGame.onPasswordEyeChange(widget)
  passwordInput:setTextHidden(not widget:isChecked())
  playClick()
end

function EnterGame.onRememberEmailChange(widget)
  if not widget:isChecked() and rememberPasswordBox:isChecked() then
    rememberPasswordBox:setChecked(false)
  end
  saveSettings()
  playClick()
end

function EnterGame.onRememberPasswordChange(widget)
  if widget:isChecked() and not rememberEmailBox:isChecked() then
    rememberEmailBox:setChecked(true)
  end
  saveSettings()
  playClick()
end

function EnterGame.onAutoLoginChange(widget)
  if widget:isChecked() then
    rememberEmailBox:setChecked(true)
    rememberPasswordBox:setChecked(true)
  end
  saveSettings()
  playClick()
end

function EnterGame.onForgotPassword()
  playClick()
  g_platform.openUrl(g_settings.get('forgot-password-url', ''))
end

function EnterGame.onForgotEmail()
  playClick()
  g_platform.openUrl(g_settings.get('forgot-email-url', ''))
end

function EnterGame.onCreateAccount()
  playClick()
  g_platform.openUrl(g_settings.get('create-account-url', ''))
end

function EnterGame.doLogin()
  local account = emailInput:getText()
  local password = passwordInput:getText()

  if account == '' or password == '' then
    emailInput:focus()
    return
  end

  playClick()
  saveSettings()
  EnterGame.hide()

  g_game.loginWorld(account, password,
    g_settings.get('world-name', ''),
    g_settings.get('world-host', ''),
    tonumber(g_settings.get('world-port', 7171)) or 7171)
end

-- kept so other modules calling the old entry point still work
doLogin = EnterGame.doLogin
onEmailEyeChange = EnterGame.onEmailEyeChange
onPasswordEyeChange = EnterGame.onPasswordEyeChange
onRememberEmailChange = EnterGame.onRememberEmailChange
onRememberPasswordChange = EnterGame.onRememberPasswordChange
onAutoLoginChange = EnterGame.onAutoLoginChange
onForgotPassword = EnterGame.onForgotPassword
onForgotEmail = EnterGame.onForgotEmail
onCreateAccount = EnterGame.onCreateAccount
