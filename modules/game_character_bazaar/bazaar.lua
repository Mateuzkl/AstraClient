local bazaarWindow
local bazaarButton
local canAuction = false
local pendingRequest = false
local requirementsTimeout
local createTimeout
local hideEvent

local RESPONSE_TIMEOUT_MS = 15000

local function widget(id)
  return bazaarWindow and bazaarWindow:recursiveGetChildById(id)
end

local function setStatus(message, color)
  local status = widget('statusLabel')
  if status then
    status:setText(message or '')
    status:setColor(color or '$var-text-cip-color')
  end
end

local function setSubmitEnabled(enabled)
  local submit = widget('submitButton')
  if submit then
    submit:setEnabled(enabled)
  end
end

local function setRefreshEnabled(enabled)
  local refresh = widget('refreshButton')
  if refresh then
    refresh:setEnabled(enabled)
  end
end

local function cancelEventReference(event)
  if event then
    removeEvent(event)
  end
  return nil
end

local function cancelRequirementsTimeout()
  requirementsTimeout = cancelEventReference(requirementsTimeout)
end

local function cancelCreateTimeout()
  createTimeout = cancelEventReference(createTimeout)
end

local function formatCoins(value)
  return comma_value(tonumber(value) or 0)
end

function init()
  bazaarWindow = g_ui.displayUI('bazaar')
  if bazaarWindow then
    bazaarWindow:hide()
    if UIModalOverlay then
      UIModalOverlay.register(bazaarWindow)
    end

    local priceEdit = widget('priceEdit')
    local durationEdit = widget('durationEdit')
    if priceEdit then priceEdit:setValidCharacters('0123456789') end
    if durationEdit then durationEdit:setValidCharacters('0123456789') end
  else
    g_logger.error('Unable to load the Character Bazaar interface.')
  end

  if modules.game_mainpanel and modules.game_mainpanel.addToggleButton then
    bazaarButton = modules.game_mainpanel.addToggleButton(
      'characterBazaarButton', tr('Character Bazaar'), '/images/options/button_taskboard', toggle, false, 1007)
  end

  connect(g_game, {
    onCharacterBazaarRequirements = onRequirements,
    onCharacterBazaarCreateResult = onCreateResult,
    onGameEnd = hide,
  })
end

function terminate()
  cancelRequirementsTimeout()
  cancelCreateTimeout()
  if hideEvent then
    removeEvent(hideEvent)
    hideEvent = nil
  end
  disconnect(g_game, {
    onCharacterBazaarRequirements = onRequirements,
    onCharacterBazaarCreateResult = onCreateResult,
    onGameEnd = hide,
  })

  if bazaarButton then
    bazaarButton:destroy()
    bazaarButton = nil
  end
  if bazaarWindow then
    bazaarWindow:destroy()
    bazaarWindow = nil
  end
end

function show()
  if not bazaarWindow or not g_game.isOnline() then return end
  bazaarWindow:show()
  bazaarWindow:raise()
  bazaarWindow:focus()
  if bazaarButton then bazaarButton:setOn(true) end
  requestRequirements()
end

function hide()
  if not bazaarWindow then return end
  if hideEvent then
    removeEvent(hideEvent)
    hideEvent = nil
  end
  cancelRequirementsTimeout()
  cancelCreateTimeout()
  bazaarWindow:hide()
  pendingRequest = false
  if bazaarButton then bazaarButton:setOn(false) end
end

function toggle()
  if not bazaarWindow then return end
  if bazaarWindow:isVisible() then
    hide()
  else
    show()
  end
end

function requestRequirements()
  if not g_game.isOnline() then return end
  if pendingRequest then return end
  cancelRequirementsTimeout()
  pendingRequest = false
  canAuction = false
  setSubmitEnabled(false)
  setRefreshEnabled(false)
  setStatus(tr('Loading Character Bazaar requirements...'))
  g_game.characterBazaarRequest()
  requirementsTimeout = scheduleEvent(function()
    requirementsTimeout = nil
    if bazaarWindow and bazaarWindow:isVisible() then
      canAuction = false
      setSubmitEnabled(false)
      setRefreshEnabled(true)
      setStatus(tr('The server did not respond. Click Refresh to try again.'), '#FF7777')
    end
  end, RESPONSE_TIMEOUT_MS)
end

function onRequirements(allowed, minimumLevel, minimumPrice, minimumDuration, maximumDuration, auctionFee, commissionPercent, transferableCoins, reason)
  cancelRequirementsTimeout()
  canAuction = allowed
  pendingRequest = false
  setRefreshEnabled(true)

  local priceEdit = widget('priceEdit')
  if priceEdit and priceEdit:getText() == '' then priceEdit:setText(tostring(minimumPrice)) end
  local durationEdit = widget('durationEdit')
  if durationEdit and durationEdit:getText() == '' then durationEdit:setText(tostring(math.floor(minimumDuration / 3600))) end

  local rules = widget('rulesLabel')
  if rules then
    local function formatHours(seconds)
      local hours = seconds / 3600
      return hours == math.floor(hours) and tostring(hours) or string.format('%.2f', hours)
    end
    rules:setText(tr('Minimum level: %d | Price: %d | Duration: %s-%s hours', minimumLevel, minimumPrice,
      formatHours(minimumDuration), formatHours(maximumDuration)))
  end
  local balance = widget('balanceLabel')
  if balance then
    balance:setText(tr('Transferable Tibia Coins: %s | Creation fee: %s | Commission: %d%%',
      formatCoins(transferableCoins), formatCoins(auctionFee), commissionPercent))
  end

  setSubmitEnabled(allowed)
  if allowed then
    -- The server always serializes an empty reason for accepted requirements.
    setStatus(tr('Your character meets the current auction requirements.'), '#7DFF7D')
  else
    setStatus(reason ~= '' and reason or tr('Your character cannot be listed.'), '#FF7777')
  end
end

function submit()
  if pendingRequest or not canAuction then return end

  local priceEdit = widget('priceEdit')
  local durationEdit = widget('durationEdit')
  local descriptionEdit = widget('descriptionEdit')
  if not priceEdit or not durationEdit or not descriptionEdit then
    g_logger.error('Character Bazaar interface is missing required input fields.')
    return
  end

  local price = tonumber(priceEdit:getText())
  local durationHours = tonumber(durationEdit:getText())
  local description = descriptionEdit:getText() or ''
  if not price or price < 1 or price > 4294967295 or math.floor(price) ~= price then
    setStatus(tr('Enter a valid starting price.'), '#FF7777')
    return
  end
  if not durationHours or durationHours < 1 or durationHours > 4294967295 or math.floor(durationHours) ~= durationHours then
    setStatus(tr('Enter a valid duration in hours.'), '#FF7777')
    return
  end
  if #description > 512 then
    setStatus(tr('The description may contain at most 512 characters.'), '#FF7777')
    return
  end

  pendingRequest = true
  setSubmitEnabled(false)
  setStatus(tr('Creating auction. The server is validating your character...'))
  g_game.characterBazaarCreate(price, durationHours * 60 * 60, description)
  cancelCreateTimeout()
  createTimeout = scheduleEvent(function()
    createTimeout = nil
    if pendingRequest and bazaarWindow and bazaarWindow:isVisible() then
      pendingRequest = false
      setSubmitEnabled(canAuction)
      setStatus(tr('The server did not respond. Please try again.'), '#FF7777')
    end
  end, RESPONSE_TIMEOUT_MS)
end

function onCreateResult(success, message)
  cancelCreateTimeout()
  pendingRequest = false
  if success then
    setStatus(message, '#7DFF7D')
    if hideEvent then
      removeEvent(hideEvent)
    end
    hideEvent = scheduleEvent(function()
      hideEvent = nil
      hide()
    end, 500)
  else
    setStatus(message ~= '' and message or tr('The auction could not be created.'), '#FF7777')
    setSubmitEnabled(canAuction)
  end
end
