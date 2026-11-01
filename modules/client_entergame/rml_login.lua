-- Baiak Black login. The legacy OTUI window remains as a fallback and as the
-- transport for the existing TCP/HTTP login flow; it is never duplicated.
RmlLogin = {}

local window, model, homeRequest, homeRefreshEvent, selectionRetryEvent
local reopenAfterClose, reopenSelectionAfterClose = false, false
local legacyVisibility
local boostedFromServer = false
local settingsKey = 'baiak-saved-accounts-v1'
local boostCacheKey = 'baiak-boosted-cache-v1'

local function hideLegacyLoginScene()
  local background = modules.client_background and modules.client_background.getBackground()
  local oldPanels = background and background.loadAfter
  local topMenu = modules.client_topmenu and modules.client_topmenu.getTopMenu()
  if not legacyVisibility then
    legacyVisibility = {
      background = background,
      backgroundVisible = background and background:isVisible(),
      oldPanels = oldPanels,
      panelsVisible = oldPanels and oldPanels:isVisible(),
      topMenu = topMenu,
      topMenuVisible = topMenu and topMenu:isVisible(),
    }
  end
  -- Some disconnect paths re-enable these widgets asynchronously. Keep them
  -- hidden every time the Rml portal takes ownership of the screen.
  if oldPanels then oldPanels:hide() end
  if background then background:hide() end
  if topMenu then topMenu:hide() end
end

local function restoreLegacyLoginScene()
  local previous = legacyVisibility
  legacyVisibility = nil
  if not previous then return end
  -- The old OTUI widgets remain loaded only because the existing protocol
  -- login code uses their fields. Never expose their visual scene while RmlUi
  -- is available; all normal login and reconnect paths belong to RmlLogin.
  if Rml and Rml.isAvailable and Rml.isAvailable() then
    if previous.oldPanels and not previous.oldPanels:isDestroyed() then previous.oldPanels:hide() end
    if previous.background and not previous.background:isDestroyed() then previous.background:hide() end
    if previous.topMenu and not previous.topMenu:isDestroyed() then previous.topMenu:hide() end
    return
  end
  if previous.oldPanels and not previous.oldPanels:isDestroyed() then
    previous.oldPanels:setVisible(previous.panelsVisible)
  end
  if previous.background and not previous.background:isDestroyed() and not g_game.isOnline() then
    previous.background:setVisible(previous.backgroundVisible)
  end
  if previous.topMenu and not previous.topMenu:isDestroyed() then
    previous.topMenu:setVisible(previous.topMenuVisible)
  end
end

function RmlLogin.prepare()
  if not Rml or not Rml.isAvailable() then return false end
  if rootWidget:getWidth() < 1020 or rootWidget:getHeight() < 600 then return false end
  hideLegacyLoginScene()
  return true
end

local function savedAccounts()
  if ClientSecurity.isBrowser() then return {} end
  local stored = g_settings.getNode(settingsKey)
  if type(stored) ~= 'table' then return {} end
  local result = {}
  for _, entry in ipairs(stored) do
    if type(entry) == 'table' and type(entry.name) == 'string' and
        type(entry.password) == 'string' and #entry.name > 0 then
      result[#result + 1] = entry
    end
  end
  return result
end

local function accountCards()
  local cards = {}
  for i, entry in ipairs(savedAccounts()) do
    cards[#cards + 1] = { id = i, name = Rml.text(entry.name) }
  end
  return cards
end

local function safeString(value, fallback, limit)
  if type(value) ~= 'string' or value == '' then return fallback end
  return Rml.text(value:sub(1, limit or 180))
end

local function resolveOutfit(entry, name)
  if type(entry) == 'table' and type(entry.outfit) == 'table' then
    local outfit = entry.outfit
    if (tonumber(outfit.type or outfit.lookType) or 0) > 0 then return outfit end
  end
  if type(entry) == 'table' and entry.raceId and g_things.getRaceData then
    local race = g_things.getRaceData(entry.raceId)
    if race and race.outfit and (tonumber(race.outfit.type) or 0) > 0 then
      return race.outfit
    end
  end
  if type(name) ~= 'string' or not g_things.getMonsterList then return nil end
  local ok, monsters = pcall(g_things.getMonsterList)
  if not ok or type(monsters) ~= 'table' then return nil end
  local target = name:lower()
  for _, monster in pairs(monsters) do
    if type(monster) == 'table' and type(monster[1]) == 'string' and
        monster[1]:lower() == target and (tonumber(monster[2]) or 0) > 0 then
      return { type = monster[2], head = monster[4], body = monster[5],
        legs = monster[6], feet = monster[7], addons = monster[8] }
    end
  end
  return nil
end

local function imageFor(entry, name)
  local outfit = resolveOutfit(entry, name)
  if not outfit then return '', false end
  return Rml.outfitImage(outfit, 2, 2), true
end

local function refreshHome()
  local url = Services and Services.clientHome
  if type(url) ~= 'string' or not url:match('^https://[^%s]+$') then return end
  if not model or homeRequest then return end
  homeRequest = HTTP.getJSON(url, function(data, err)
    homeRequest = nil
    if model then
      homeRefreshEvent = scheduleEvent(function()
        homeRefreshEvent = nil
        refreshHome()
      end, 60000)
    end
    if not model or err or type(data) ~= 'table' then return end
    local online = tonumber(data.playersOnline)
    model.playersOnline = online and tostring(math.max(0, math.floor(online))) or '—'
    local news = data.latest
    if type(news) == 'table' then
      model.newsTitle = safeString(news.title, 'Changelog', 100)
      model.newsDate = safeString(news.date, '', 30)
      model.newsCategory = safeString(news.category, 'ATUALIZAÇÃO', 20):upper()
      local lines = {}
      if type(news.entries) == 'table' then
        for i = 1, math.min(#news.entries, 3) do
          lines[#lines + 1] = { text = safeString(news.entries[i], '', 170) }
        end
      end
      model.newsLines = lines
      model.newsOffline = false
    end
    if not boostedFromServer and type(data.creatures) == 'table' then
      RmlLogin.updateBoosted(data.creatures, data.boss)
    end
  end)
end

function RmlLogin.updateBoosted(creatures, boss)
  if not model then return end
  if type(creatures) ~= 'table' or creatures.name or creatures.raceId then
    creatures = { creatures }
  end
  local cards = {}
  for i = 1, 4 do
    local entry = creatures[i]
    local name = type(entry) == 'table' and entry.name or
        (type(entry) == 'string' and entry or nil)
    local image, hasImage = imageFor(entry, name)
    cards[i] = { number = string.format('%02d', i), image = image,
      hasImage = hasImage, name = safeString(name, 'Aguardando destaque', 48),
      active = name ~= nil }
  end
  model.creatures = cards
  local bossName = type(boss) == 'table' and boss.name or boss
  model.bossName = safeString(bossName, 'Aguardando destaque', 48)
  model.bossImage, model.bossHasImage = imageFor(boss, bossName)
end

function RmlLogin.cacheBoosted(creatures, boss)
  boostedFromServer = true
  local entries = {}
  for i = 1, math.min(4, #creatures) do
    local entry = creatures[i]
    if entry and type(entry.name) == 'string' then entries[#entries + 1] = entry end
  end
  g_settings.setNode(boostCacheKey, { date = os.date('%Y-%m-%d'), entries = entries,
    boss = boss or '' })
  g_settings.save()
  RmlLogin.updateBoosted(entries, boss)
end

function RmlLogin.updateCasts(casters, viewers)
  if not model then return end
  model.castsActive = tostring(math.max(0, tonumber(casters) or 0))
  model.castViewers = tostring(math.max(0, tonumber(viewers) or 0))
end

function RmlLogin.isVisible()
  return window ~= nil and not window:isDestroyed() and window:isVisible()
end

function RmlLogin.suspend()
  if window and not window:isDestroyed() then window:hide() end
end

function RmlLogin.showSelection()
  -- onGameEnd can be emitted a frame before the game state becomes offline.
  -- Wait only for an actual online session. A login attempt may remain in the
  -- "logging" state while it is being retried; waiting for that state used to
  -- leave the old hidden scene visible as a black screen after a death.
  if g_game.isOnline() then
    if not selectionRetryEvent then
      selectionRetryEvent = scheduleEvent(function()
        selectionRetryEvent = nil
        if not g_game.isOnline() and CharacterList and G.characters then
          CharacterList.show()
        end
      end, 100)
    end
    return false
  end
  if not RmlLogin.show() then return false end
  if window and window.rmlClosing then reopenSelectionAfterClose = true end
  if model then model.loggingIn = true end
  return true
end

function RmlLogin.show()
  if not RmlLogin.prepare() then return false end
  if window and not window:isDestroyed() and window.rmlClosing then
    reopenAfterClose = true
    return true
  end
  if window and not window:isDestroyed() then
    if model then model.loggingIn = false end
    window:show()
    window:raise()
    window:focus()
    hideLegacyLoginScene()
    return true
  end
  local initialAccount = g_crypt.decrypt(g_settings.get('account')) or ''
  local initialPassword = not ClientSecurity.isBrowser() and
      (g_crypt.decrypt(g_settings.get('password')) or '') or ''
  window, model = Rml.createWindow{
    id = 'baiakBlackLogin',
    document = '/modules/client_entergame/rml_login.rml',
    model = 'baiaklogin',
    width = rootWidget:getWidth(), height = rootWidget:getHeight(),
    data = {
      account = Rml.text(initialAccount), password = Rml.text(initialPassword), token = '',
      remember = #initialPassword > 0 and not ClientSecurity.isBrowser(),
      canSave = not ClientSecurity.isBrowser(),
      status = '', loggingIn = false, selected = 0, accounts = accountCards(),
      hasAccounts = #accountCards() > 0,
      creatures = {}, bossName = 'Aguardando destaque', bossImage = '',
      bossHasImage = false, playersOnline = '—', castsActive = '—', castViewers = '—',
      newsTitle = 'Novidades do Baiak Black', newsDate = '20/10/2026',
      newsCategory = 'CLIENTE', newsOffline = true,
      newsLines = {
        { text = 'Passe de Batalha e SuperUP no Astra.' },
        { text = 'Histórico local; a atualização ao vivo estará disponível quando o site voltar.' },
      },
      Login = function()
        local account = Rml.fromRml(model.account):trim()
        local password = Rml.fromRml(model.password)
        if account == '' or password == '' then
          model.status = 'Informe sua conta e senha para entrar.'
          return
        end
        local legacy = EnterGame and EnterGame.getLoginWidgets and EnterGame.getLoginWidgets()
        if not legacy then return end
        legacy.account:setText(account)
        legacy.password:setText(password)
        legacy.token:setText(Rml.fromRml(model.token))
        legacy.rememberAccount:setChecked(true)
        legacy.rememberPassword:setChecked(model.remember and not ClientSecurity.isBrowser())
        model.status = 'Conectando ao servidor...'
        model.loggingIn = true
        EnterGame.doLogin(account, password)
      end,
      Save = function()
        if ClientSecurity.isBrowser() then return end
        local account = Rml.fromRml(model.account):trim()
        local password = Rml.fromRml(model.password)
        if account == '' or password == '' then
          model.status = 'Preencha conta e senha antes de salvar.'
          return
        end
        local entries = savedAccounts()
        local encrypted = g_crypt.encrypt(password)
        local found = false
        for _, entry in ipairs(entries) do
          if entry.name == account then
            entry.password = encrypted
            found = true
            break
          end
        end
        if not found then entries[#entries + 1] = { name = account, password = encrypted } end
        g_settings.setNode(settingsKey, entries)
        g_settings.save()
        model.accounts = accountCards()
        model.hasAccounts = true
        model.status = 'Conta salva neste dispositivo.'
      end,
      Select = function(id)
        local entry = savedAccounts()[tonumber(id)]
        if not entry then return end
        model.account = Rml.text(entry.name)
        model.password = Rml.text(g_crypt.decrypt(entry.password) or '')
        model.selected = tonumber(id)
        model.remember = true
        model.status = 'Conta carregada. Clique em Entrar quando quiser.'
      end,
      Remove = function()
        local id = tonumber(model.selected)
        local entries = savedAccounts()
        if not id or not entries[id] then return end
        table.remove(entries, id)
        g_settings.setNode(settingsKey, entries)
        g_settings.save()
        model.accounts = accountCards()
        model.hasAccounts = #entries > 0
        model.selected = 0
        model.status = 'Conta removida deste dispositivo.'
      end,
      Create = function()
        if Services and type(Services.createAccount) == 'string' and
            Services.createAccount:match('^https://') then
          g_platform.openUrl(Services.createAccount)
        else model.status = 'O site de criação de conta está temporariamente offline.' end
      end,
      Recover = function()
        if Services and type(Services.recoveryPassword) == 'string' and
            Services.recoveryPassword:match('^https://') then
          g_platform.openUrl(Services.recoveryPassword)
        else model.status = 'A recuperação estará disponível quando o site voltar.' end
      end,
      News = function()
        if Services and type(Services.website) == 'string' and
            Services.website:match('^https://') then g_platform.openUrl(Services.website .. '/?p=changelog') end
      end,
      Watch = function()
        if modules.client_background and modules.client_background.openCastList then
          modules.client_background.openCastList()
        end
      end,
    },
    onClose = function()
      window, model = nil, nil
      if reopenAfterClose then
        local showSelection = reopenSelectionAfterClose
        reopenAfterClose, reopenSelectionAfterClose = false, false
        addEvent(function()
          -- Rendering the portal while a reconnect is pending is safe and
          -- prevents a closing Rml document from leaving a black legacy scene.
          if g_game.isOnline() then return end
          if showSelection and CharacterList and G.characters then
            CharacterList.show()
          else
            RmlLogin.show()
          end
        end)
      else
        restoreLegacyLoginScene()
      end
    end,
  }
  if not window then return false end
  window:fill('parent')
  hideLegacyLoginScene()
  -- Login is a persistent scene, not a dismissible dialog.
  window.onEscape = function() end
  local cache = g_settings.getNode(boostCacheKey)
  boostedFromServer = type(cache) == 'table' and cache.date == os.date('%Y-%m-%d')
      and type(cache.entries) == 'table' and #cache.entries > 0
  if type(cache) == 'table' and cache.date == os.date('%Y-%m-%d') then
    RmlLogin.updateBoosted(cache.entries or cache.names or {}, cache.boss)
  else
    RmlLogin.updateBoosted({}, nil)
  end
  refreshHome()
  if modules.client_background and modules.client_background.Cast then
    local cast = modules.client_background.Cast
    RmlLogin.updateCasts(#(cast.list or {}), cast.totalViewers or 0)
    if cast.serverInfo then cast.updateStatus() end
  end
  return true
end

function RmlLogin.hide()
  reopenAfterClose, reopenSelectionAfterClose = false, false
  if selectionRetryEvent then removeEvent(selectionRetryEvent) selectionRetryEvent = nil end
  RmlLogin.suspend()
  if homeRequest then HTTP.cancel(homeRequest) homeRequest = nil end
  if homeRefreshEvent then removeEvent(homeRefreshEvent) homeRefreshEvent = nil end
  if window and not window:isDestroyed() then
    Rml.close(window)
  else
    restoreLegacyLoginScene()
  end
end

function RmlLogin.terminate()
  RmlLogin.hide()
  RmlLogin = nil
end
