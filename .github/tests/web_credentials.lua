-- Exercita funcoes reais do login, nao reproducoes da politica no teste.
assert(loadfile('modules/corelib/security.lua'))()
g_platform = { isBrowser = function() return true end }
ASTRA_ALLOW_LOCAL_HTTP_LOGIN = false
assert(ClientSecurity.canSendCredentials('https://login.example/login'))
for _, url in ipairs({'http://remote.example/login', 'javascript:alert(1)', 'file:///x',
    'https://user:fake@server/login', 'https://server/login#fragment', 'http://127.0.0.1:9000/login'}) do
  assert(not ClientSecurity.canSendCredentials(url), url)
end
ASTRA_ALLOW_LOCAL_HTTP_LOGIN = true
assert(ClientSecurity.canSendCredentials('http://127.0.0.1:9000/login'))
assert(not ClientSecurity.canSendCredentials('http://localhost.evil.example/login'))
ASTRA_ALLOW_LOCAL_HTTP_LOGIN = false
local settings, encrypted, queue, errors, requests = {}, {}, {}, {}, 0
g_settings = { set = function(k, v) settings[k] = v end, get = function(k) return settings[k] end,
  remove = function(k) settings[k] = nil end, save = function() end }
settings.password, settings.gtoken, settings.autologin, settings.hotkeys = 'fake', 'fake', true, 'keep'
ClientSecurity.clearSavedCredentials()
assert(not settings.password and not settings.gtoken and not settings.autologin and settings.hotkeys == 'keep')
g_crypt = { encrypt = function(v) encrypted[#encrypted+1] = v; return 'encoded:' .. v end }
g_clock = { millis = function() return 1 end }
KeyBind = { getKeyBind = function() return {} end }
G = { password = 'fictitious-password', account = 'identifier', gtoken = '' }
GameInfo = { version = 860 }; APP_VERSION = 1
local online, logging = false, false
g_game = { isOnline = function() return online end, isLogging = function() return logging end }
local checked = false
local box = { isChecked = function() return checked end }
local passwordBox = { isChecked = function() return true end } -- programmatic bypass must still be blocked
local selector = { getText = function() return 'Test' end }
tr = function(s) return s end
connect = function() end
string.trim = function(s) return s:match('^%s*(.-)%s*$') end
string.split = function(s, separator)
  local result = {}; for part in s:gmatch('[^' .. separator .. ']+') do result[#result+1] = part end
  return result
end
scheduleEvent = function(f) queue[#queue+1] = f; return f end
removeEvent = function() end
modules = { game_things = { isLoaded = function() return true end },
  client_background = { toggleLogo = function() end } }
CharacterList = { create = function() end, show = function() end }
HTTP = { postJSON = function() requests = requests + 1 end, cancel = function() end }
assert(loadfile('modules/client_entergame/entergame.lua'))()
local function upvalue(fn, wanted, value, write)
  for i = 1, 100 do
    local name, current = debug.getupvalue(fn, i)
    if not name then break end
    if name == wanted then if write then debug.setupvalue(fn, i, value) end; return current end
  end
  error('missing production upvalue: ' .. wanted)
end
local finish = upvalue(upvalue(EnterGame.doLogin, 'performLogin'), 'onCharacterList')
finish = upvalue(finish, 'finishCharacterList')
upvalue(finish, 'rememberEmailBox', box, true)
upvalue(finish, 'rememberPasswordBox', passwordBox, true)
for _, browser in ipairs({true, false}) do
  g_platform.isBrowser = function() return browser end
  for _, remember in ipairs({false, true}) do
    checked = remember; settings.account = 'old'; settings.password = nil
    G.password, G.account, G.gtoken = 'fictitious-password', 'identifier', ''
    finish({}, {})
    assert(settings.account == (remember and 'encoded:identifier' or nil))
    if browser then assert(settings.password == nil)
    else assert(settings.password == 'encoded:fictitious-password') end
  end
end
g_platform.isBrowser = function() return true end
local perform = upvalue(EnterGame.doLogin, 'performLogin')
upvalue(perform, 'serverSelector', selector, true)
upvalue(perform, 'enterGame', { accountNameTextEdit = { isTextHidden = function() return false end } }, true)
Servers = {{ name = 'Test', loginLink = 'http://remote.example/login', version = 860 }}
EnterGame.onError = function(error) errors[#errors+1] = error end
for _, remember in ipairs({true, false}) do
  checked = remember; settings.account = 'old'; settings.password = nil
  perform('identifier', 'fictitious-password', '')
  assert(settings.account == (remember and 'encoded:identifier' or nil))
  assert(settings.password == nil and requests == 0)
end
assert(#errors == 2 and not errors[1]:find('fictitious', 1, true))
EnterGame.addTestServer(); assert(#Servers == 1)
local nonce = upvalue(EnterGame.onGoogleClick, 'newGoogleSessionId')
assert(nonce() == nil)
g_crypt.genUUID = function() error('entropy unavailable') end
assert(nonce() == nil)
g_crypt.genUUID = function() return '00112233-4455-4677-8899-aabbccddeeff' end
assert(nonce() == 'google_00112233445546778899aabbccddeeff')
-- Google credentials are session-only; remember-account still follows the checkbox.
local googleResult = upvalue(upvalue(EnterGame.onGoogleClick, 'pollGoogleAuth'), 'onGoogleLoginResult')
local originalHttpLogin = EnterGame.doLoginHttp
EnterGame.doLoginHttp = function() end
checked = true
googleResult(0, { success = true, account = { email = 'identifier', ptoken = 'fictitious-password', gtoken = 'fictitious-token' } })
assert(settings.gtoken == nil and G.gtoken == 'fictitious-token')
EnterGame.doLoginHttp = originalHttpLogin
-- Initialisation removes legacy state and disables both controls in Web only.
local widgets = {}
local function widget(id)
  if widgets[id] then return widgets[id] end
  local w = { checked = false, enabled = true, text = '', count = 0 }
  widgets[id] = w
  function w:getChildById(child) return widget(child) end
  function w:getParent() return widget('parent') end
  function w:addOption() self.count = self.count + 1 end
  function w:getOptionsCount() return self.count end
  function w:isOption() return false end
  function w:setOption() end
  function w:getText() return self.text end
  function w:setText(text) self.text = text end
  function w:setCursorPos() end
  function w:setChecked(value) self.checked = value end
  function w:isChecked() return self.checked end
  function w:setEnabled(value) self.enabled = value end
  function w:setTooltip() end
  function w:show() end
  function w:raise() end
  function w:focus() end
  function w:destroy() end
  w.accountNameTextEdit = { setTextHidden = function() end }
  return w
end
g_ui = { displayUI = function() return widget('login') end }
keybind = upvalue(EnterGame.init, 'keybindChangeChar')
keybind.active = function() end
g_crypt.decrypt = function(value) return value or '' end
g_settings.getBoolean = function(key) return settings[key] == true end
for _, browser in ipairs({true, false}) do
  widgets = {}; queue = {}; settings.password, settings.autologin = 'fictitious-password', true
  g_platform.isBrowser = function() return browser end
  EnterGame.init()
  assert(widgets.rememberPasswordBox.enabled == not browser)
  if browser then
    assert(not widgets.rememberPasswordBox.checked and not widgets.autoLoginBox.checked and not widgets.autoLoginBox.enabled)
    assert(settings.password == nil and settings.autologin == nil)
    assert(widgets.accountPasswordTextEdit.text == '')
  else assert(widgets.accountPasswordTextEdit.text == 'fictitious-password') end
end
-- Offline/reload clears session credentials; active world/reconnect and native are preserved.
for _, scenario in ipairs({{true, false, false}, {true, true, false}, {true, false, true}, {false, false, false}}) do
  local browser = scenario[1]; online, logging = scenario[2], scenario[3]
  g_platform.isBrowser = function() return browser end
  G.password, G.gtoken, G.authenticatorToken, G.sessionKey = 'fake', 'fake', 'fake', 'fake'
  EnterGame.show()
  local expected = browser and not online and not logging and '' or 'fake'
  assert(G.password == expected and G.gtoken == expected and G.authenticatorToken == expected and G.sessionKey == expected)
end
online, logging = false, false
g_platform.isBrowser = function() return true end
-- Local bot features are untouched; insecure sharing stops before reading/archiving files.
assert(loadfile('modules/game_bot/bot.lua'))()
local sharingErrors = 0
displayErrorBox = function() sharingErrors = sharingErrors + 1 end
uploadConfig(); downloadConfig()
assert(sharingErrors == 2)
-- HTTP errors cannot disclose parser diagnostics or response text.
g_http = { post = function() return 1 end, setUserAgent = function() end }; json = { encode = function() return '{}' end,
  decode = function() error('fictitious-secret-response') end }
assert(loadfile('modules/corelib/http.lua'))()
HTTP.postJSON('https://test.example/login', {}, function(data, err)
  assert(data == nil and err == 'JSON ERROR: invalid server response')
end)
HTTP.onPost(1, '', '', 'fictitious-secret-response')
assert(HTTP.pendingCount() == 0)
disconnect = function() end
g_keyboard = { unbindKeyDown = function() end }
keybind.deactive = function() end
G.password, G.gtoken, G.authenticatorToken, G.sessionKey = 'fake', 'fake', 'fake', 'fake'
EnterGame.terminate()
assert(G.password == '' and G.gtoken == '' and G.authenticatorToken == '' and G.sessionKey == '')
print('web credential policy and native login preferences: PASS')
