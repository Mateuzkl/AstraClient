-- Visual-only fixture for the real login document. No account or network access.
assert(Rml.isAvailable())
g_window.resize({width = 1366, height = 768})
local window
local function waitPng(file, attempts)
  if g_resources.fileExists(file) then
    local ok, data = pcall(g_resources.readFileContents, file)
    if ok and #data > 20000 and data:sub(-12) == string.char(0,0,0,0,73,69,78,68,174,66,96,130) then
      print('[LOGIN SCREENSHOT] ' .. g_resources.getWriteDir() .. '/' .. file)
      print('[RMLUI TEST] PASS: login document, model and visual screenshot')
      g_app.exit()
      return
    end
  end
  assert(attempts > 0, 'login screenshot did not complete')
  scheduleEvent(function() waitPng(file, attempts - 1) end, 100)
end
local function openWhenSized(attempts)
  local size = rootWidget:getSize()
  if size.width < 1300 or size.height < 700 then
    assert(attempts > 0, 'login viewport did not resize')
    scheduleEvent(function() openWhenSized(attempts - 1) end, 100)
    return
  end
  window = assert(Rml.createWindow{
    document = '/modules/client_entergame/rml_login.rml', model = 'baiaklogin',
    width = size.width, height = size.height,
    data = {
      account = '', password = '', token = '', remember = false, canSave = true,
      status = '', selected = 0, hasAccounts = true,
      accounts = {{id = 1, name = 'Herói do Norte'}, {id = 2, name = 'Guardião Negro'}},
      creatures = {
        {number = '01', name = 'Dragon', active = true, hasImage = true, image = '/images/ui/unknownoutfit.png'},
        {number = '02', name = 'Hydra', active = true, hasImage = true, image = '/images/ui/unknownoutfit.png'},
        {number = '03', name = 'Demon', active = true, hasImage = true, image = '/images/ui/unknownoutfit.png'},
        {number = '04', name = 'Medusa', active = true, hasImage = true, image = '/images/ui/unknownoutfit.png'},
      },
      bossName = 'Magma Bubble', bossHasImage = true, bossImage = '/images/ui/unknownoutfit.png',
      playersOnline = '184', castsActive = '3', castViewers = '8',
      newsTitle = 'Passe de Batalha e SuperUP no Astra',
      newsDate = '20/10/2026', newsCategory = 'CLIENTE', newsOffline = false,
      newsLines = {
        {text = 'Bônus de XP agora detalhados na lista de Skills.'},
        {text = 'Três missões diárias no Passe de Batalha.'},
      },
      Login = function() end, Save = function() end, Select = function() end,
      Remove = function() end, Create = function() end, Recover = function() end,
      News = function() end, Watch = function() end,
    },
  })
  window:fill('parent')
  scheduleEvent(function()
    assert(window:getDocument() and window:getDocument().offset_width > 900)
    assert(math.abs(window:getWidth() - rootWidget:getWidth()) <= 1, 'login width does not fill viewport')
    assert(math.abs(window:getHeight() - rootWidget:getHeight()) <= 1, 'login height does not fill viewport')
    for _, id in ipairs({'login-account','login-password','login-submit','login-save','login-news','login-watch'}) do
      local rect, clip = assert(Rml.elementRect(window, id), id), assert(Rml.clipRect(window, id), id)
      assert(rect.width > 0 and rect.height > 0, id .. ' collapsed')
      assert(rect.x >= clip.x - 1 and rect.y >= clip.y - 1 and
        rect.x + rect.width <= clip.x + clip.width + 1 and
        rect.y + rect.height <= clip.y + clip.height + 1, id .. ' clipped')
    end
    local file = 'astra-login-layout-' .. g_clock.millis() .. '.png'
    g_app.doScreenshot(file)
    waitPng(file, 50)
  end, 900)
end
scheduleEvent(function() openWhenSized(30) end, 180)
