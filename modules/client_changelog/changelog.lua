-- "What's New" changelog popup (native OTUI).
-- On client open it fetches Services.website .. "/api/changelog"; if the active
-- changelog id differs from the one this install last acknowledged
-- (g_settings 'changelog-seen-id') and we're not in-game, it shows a modal over
-- the LOGIN SCREEN. The modal input-locks the client (must be acknowledged before
-- logging in). The OK button is disabled for a 5s countdown.
--
-- Plain table (NOT a Controller): the in-memory Controller in a long-running
-- client can predate clearEvents() and crash on unload. Timers use the GLOBAL
-- scheduleEvent/cycleEvent/removeEvent. Rendering is native widgets (the g_html
-- engine overlapped everything).
Changelog = {}

local SEEN_KEY = 'changelog-seen-id'
local COOLDOWN_SECONDS = 5

function Changelog:onInit()
  self.window = nil
  self.okButton = nil
  self._data = nil
  self._cooldown = 0
  self._cooldownEvent = nil
  self._shown = false

  if not g_ui then
    return
  end

  local base = Services and Services.website
  if type(base) ~= 'string' or #base < 4 then
    return
  end
  if not HTTP or not HTTP.getJSON then
    return
  end

  HTTP.getJSON(base .. '/api/changelog', function(data, err)
    if err then
      return -- never block the client on a changelog fetch failure
    end
    self:onChangelogData(data)
  end)
end

function Changelog:onChangelogData(data)
  if self._shown then
    return
  end
  -- Only on the login screen, never over a live game session.
  if g_game and g_game.isOnline and g_game.isOnline() then
    return
  end
  if type(data) ~= 'table' then
    return
  end

  local id = tonumber(data.id)
  if not id or id <= 0 then
    return
  end

  local seen = g_settings.get(SEEN_KEY)
  if seen ~= nil and tostring(id) == tostring(seen) then
    return -- already acknowledged this changelog on this install
  end

  -- The changelog text arrives as UTF-8 from the aac, but the body is rendered with
  -- native bitmap-font Labels (byte-per-glyph = Latin-1), so accents would show up as
  -- mojibake ("Ã§", "Ãµ", "Ã­"). Fold UTF-8 down to Latin-1 once, here at the boundary.
  if type(data.markdown) == 'string' then
    data.markdown = string.utf8_to_latin1(data.markdown)
  end
  if type(data.title) == 'string' then
    data.title = string.utf8_to_latin1(data.title)
  end

  self._data = data
  self:show()
end

function Changelog:show()
  if self.window then
    return
  end
  self._shown = true
  local d = self._data or {}

  -- Import the OTUI styles lazily, by ABSOLUTE path: at module load time the
  -- base styles (Label, Button, ...) defined by client_styles don't exist yet
  -- (this module autoloads earlier). By show() time everything is loaded.
  if not self._styleImported then
    pcall(function() g_ui.importStyle('/modules/client_changelog/changelog.otui') end)
    self._styleImported = true
  end

  self.window = g_ui.createWidget('ChangelogWindow', rootWidget)
  if not self.window then
    self._shown = false -- style missing; bail without crashing
    return
  end
  -- Block Escape so it can't bypass the cooldown.
  self.window.onEscape = function() return true end

  -- Subtitle: the entry's own title + version.
  local subtitle = self.window:getChildById('subtitle')
  if subtitle then
    local t = (type(d.title) == 'string' and #d.title > 0) and d.title or ''
    local v = (d.version ~= nil and tostring(d.version) ~= '') and ('v' .. tostring(d.version)) or ''
    if t ~= '' and v ~= '' then
      subtitle:setText(t .. '  (' .. v .. ')')
    else
      subtitle:setText(t .. v)
    end
  end

  -- Body: one native Label per markdown block.
  local list = self.window:getChildById('contentList')
  if list then
    list:destroyChildren()
    for _, b in ipairs(ChangelogMd.parse(d.markdown)) do
      self:addBlock(list, b)
    end
  end

  self.okButton = self.window:getChildById('okButton')
  if self.okButton then
    self.okButton.onClick = function() self:onOk() end
  end

  if g_client and g_client.setInputLockWidget then
    g_client.setInputLockWidget(self.window)
  end
  self:bringToFront()
  -- EnterGame.show() re-raises the login panel on several boot-time callbacks
  -- (server list / status load), which can land AFTER this modal appears and
  -- cover it. Re-raise a few times over the first ~2s to win that race.
  self._raiseEvents = {
    scheduleEvent(function() self:bringToFront() end, 50),
    scheduleEvent(function() self:bringToFront() end, 200),
    scheduleEvent(function() self:bringToFront() end, 500),
    scheduleEvent(function() self:bringToFront() end, 1000),
    scheduleEvent(function() self:bringToFront() end, 1800),
  }

  self:startCooldown(COOLDOWN_SECONDS)
end

function Changelog:bringToFront()
  if self.window and not self.window:isDestroyed() then
    self.window:show()
    self.window:raise()
    self.window:focus()
  end
end

function Changelog:addBlock(list, b)
  if b.kind == 'hr' then
    local sep = g_ui.createWidget('HorizontalSeparator', list)
    sep:setMarginTop(6)
    sep:setMarginBottom(6)
    return
  end

  local style = 'ChangelogParagraph'
  if b.kind == 'heading' then
    style = 'ChangelogHeading'
  elseif b.kind == 'quote' then
    style = 'ChangelogQuote'
  elseif b.kind == 'code' then
    style = 'ChangelogCode'
  end

  local text = b.text or ''
  if b.kind == 'bullet' then
    text = '- ' .. text
  elseif b.kind == 'ol' then
    text = (b.num or 1) .. '. ' .. text
  end

  local label = g_ui.createWidget(style, list)
  label:setText(text)
end

function Changelog:updateOkButton()
  local btn = self.okButton
  if not btn or btn:isDestroyed() then
    return
  end
  if (self._cooldown or 0) > 0 then
    btn:setEnabled(false)
    btn:setText(string.format('OK (%d)', self._cooldown))
  else
    btn:setEnabled(true)
    btn:setText('OK')
  end
end

function Changelog:startCooldown(seconds)
  self._cooldown = seconds
  self:updateOkButton()
  -- Global cycleEvent: repeats every second until the callback returns false.
  self._cooldownEvent = cycleEvent(function() return self:tickCooldown() end, 1000)
end

function Changelog:tickCooldown()
  self._cooldown = (self._cooldown or 0) - 1
  self:updateOkButton()
  if self._cooldown <= 0 then
    self._cooldown = 0
    return false -- stop the cycle
  end
end

function Changelog:onOk()
  if (self._cooldown or 0) > 0 then
    return -- still on cooldown (button is disabled, but guard anyway)
  end
  if self._data and self._data.id then
    g_settings.set(SEEN_KEY, tostring(self._data.id))
    g_settings.save()
  end
  self:dismiss()
end

function Changelog:dismiss()
  if self._cooldownEvent then
    removeEvent(self._cooldownEvent)
    self._cooldownEvent = nil
  end
  if self._raiseEvents then
    for _, e in ipairs(self._raiseEvents) do
      removeEvent(e)
    end
    self._raiseEvents = nil
  end
  if g_client and g_client.setInputLockWidget then
    g_client.setInputLockWidget(nil)
  end
  if self.window and not self.window:isDestroyed() then
    self.window:destroy()
  end
  self.window = nil
  self.okButton = nil
  self._cooldown = 0
end

function Changelog:onTerminate()
  self:dismiss()
end
