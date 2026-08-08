forgeWindow = nil
fusionMenu = nil
transferMenu = nil
conversionMenu = nil
historyMenu = nil
resultWindow = nil
mainPanel = nil

selectedItemFusionRadio = nil
selectedConvergenceFusionRadio = nil
selectedItemFusionConvectionRadio = nil

local forgeProtocolGame = nil
local forgeProtocolRegistered = false
local forgeModuleActive = false
local forgeResourceRefreshEvent = nil
local previousForgeMethods = {}

local forgeResourceTypes = {
  [ResourceBank] = true,
  [ResourceInventary] = true,
  [ResourceForgeDust] = true,
  [ResourceForgeSlivers] = true,
  [ResourceForgeExaltedCore] = true
}

local ForgeOpcode = {
  Request = 0xE2,
  Send = 0xE3
}

local ForgeRequest = {
  Open = 1,
  Close = 2,
  Fusion = 3,
  Transfer = 4,
  Convert = 5,
  History = 6
}

local ForgeResponse = {
  Message = 0,
  Init = 1,
  Data = 2,
  Fusion = 3,
  Transfer = 4,
  History = 5,
  Close = 6
}

local function sendForgeMessage(msg)
  local protocolGame = forgeProtocolGame or g_game.getProtocolGame()
  if protocolGame then
    protocolGame:send(msg)
  end
end

local function refreshForgeResourceLabels()
  local player = g_game.getLocalPlayer()
  if not player or not forgeWindow then
    return
  end

  forgeWindow.sliversPanel.slivers:setText(player:getResourceValue(ResourceForgeSlivers))
  forgeWindow.exaltedcorePanel.exaltedcore:setText(player:getResourceValue(ResourceForgeExaltedCore))
  forgeWindow.dustPanel.dust:setText(player:getResourceValue(ResourceForgeDust) .. '/' .. ForgeSystem.maxPlayerDust)
  forgeWindow.moneyPanel.gold:setText(formatMoney(player:getResourceValue(ResourceBank) + player:getResourceValue(ResourceInventary), ","))
end

local function ensureForgeUI()
  if forgeWindow then
    return true
  end
  if not forgeModuleActive then
    return false
  end

  forgeWindow = g_ui.displayUI('forge')
  mainPanel = forgeWindow:getChildById('contentPanel')

  fusionMenu = g_ui.loadUI('styles/fusion', mainPanel)
  fusionMenu:hide()
  transferMenu = g_ui.loadUI('styles/transfer', mainPanel)
  transferMenu:hide()
  conversionMenu = g_ui.loadUI('styles/conversion', mainPanel)
  conversionMenu:hide()
  historyMenu = g_ui.loadUI('styles/history', mainPanel)
  historyMenu:hide()

  loadMenu('fusionMenu')
  hideForge()
  return true
end

function ensureForgeResultWindow()
  if resultWindow then
    return true
  end
  if not forgeModuleActive then
    return false
  end

  resultWindow = g_ui.displayUI('styles/result')
  resultWindow:hide()
  return true
end

local function readPriceTable(msg)
  local result = {}
  local classCount = msg:getU8()
  for i = 1, classCount do
    local classification = msg:getU8()
    local tierPrices = {}
    local tierCount = msg:getU8()
    for j = 1, tierCount do
      tierPrices[msg:getU8()] = msg:getU64()
    end
    result[classification] = { [2] = tierPrices }
  end
  return result
end

local function readNumberMap(msg)
  local result = {}
  local count = msg:getU8()
  for i = 1, count do
    result[msg:getU8()] = msg:getU64()
  end
  return result
end

local function readByteMap(msg)
  local result = {}
  local count = msg:getU8()
  for i = 1, count do
    result[msg:getU8()] = msg:getU8()
  end
  return result
end

local function readForgeItems(msg)
  local result = {}
  local count = msg:getU16()
  for i = 1, count do
    local entry = {
      msg:getU16(),
      msg:getU8(),
      msg:getU16(),
      {},
      msg:getU8(),
      msg:getU8()
    }

    local subItemCount = msg:getU16()
    for j = 1, subItemCount do
      entry[4][msg:getU16()] = msg:getU16()
    end
    table.insert(result, entry)
  end
  return result
end

local function setForgeResourceBalances(balances)
  local player = g_game.getLocalPlayer()
  if not player or not player.setResourceValue then
    return
  end
  for resourceType, amount in pairs(balances) do
    player:setResourceValue(resourceType, amount)
    signalcall(g_game.onResourceBalance, resourceType, amount)
  end
end

local function parseForgeInit(msg)
  ForgeSystem.init(
    readPriceTable(msg),
    readByteMap(msg),
    readNumberMap(msg),
    readNumberMap(msg),
    msg:getU16(),
    msg:getU16(),
    msg:getU16(),
    msg:getU16(),
    msg:getU16(),
    msg:getU16(),
    msg:getU16(),
    msg:getU16(),
    msg:getU16(),
    msg:getU16(),
    msg:getU8(),
    msg:getU8(),
    msg:getU8()
  )
end

local function parseForgeData(msg)
  local maxPlayerDust = msg:getU16()
  setForgeResourceBalances({
    [ResourceBank] = msg:getU64(),
    [ResourceInventary] = msg:getU64(),
    [ResourceForgeDust] = msg:getU64(),
    [ResourceForgeSlivers] = msg:getU64(),
    [ResourceForgeExaltedCore] = msg:getU64()
  })

  ForgeSystem.onForgeData(
    readForgeItems(msg),
    readForgeItems(msg),
    readForgeItems(msg),
    readForgeItems(msg),
    maxPlayerDust
  )
end

local function parseForgeFusion(msg)
  ForgeSystem.onForgeFusion(
    msg:getU8() ~= 0,
    msg:getU8() ~= 0,
    msg:getU16(),
    msg:getU8(),
    msg:getU16(),
    msg:getU8(),
    msg:getU8(),
    msg:getU16(),
    msg:getU8(),
    msg:getU16()
  )
end

local function parseForgeTransfer(msg)
  ForgeSystem.onForgeTransfer(
    msg:getU8() ~= 0,
    msg:getU8() ~= 0,
    msg:getU16(),
    msg:getU8(),
    msg:getU16(),
    msg:getU8()
  )
end

local function parseForgeHistory(msg)
  local history = {}
  local count = msg:getU16()
  for i = 1, count do
    table.insert(history, {
      msg:getU32(),
      msg:getU8(),
      msg:getString()
    })
  end
  ForgeSystem.onForgeHistory(history)
end

local function parseForgeMessage(protocolGame, msg)
  local response = msg:getU8()
  if response == ForgeResponse.Message then
    displayInfoBox(tr("Forge"), msg:getString())
  elseif response == ForgeResponse.Init then
    parseForgeInit(msg)
  elseif response == ForgeResponse.Data then
    parseForgeData(msg)
  elseif response == ForgeResponse.Fusion then
    parseForgeFusion(msg)
  elseif response == ForgeResponse.Transfer then
    parseForgeTransfer(msg)
  elseif response == ForgeResponse.History then
    parseForgeHistory(msg)
  elseif response == ForgeResponse.Close then
    offlineForge()
  end
  return true
end

local function registerForgeProtocol()
  if forgeProtocolRegistered then
    return
  end
  ProtocolGame.unregisterOpcode(ForgeOpcode.Send)
  ProtocolGame.registerOpcode(ForgeOpcode.Send, parseForgeMessage)
  forgeProtocolGame = g_game.getProtocolGame()
  forgeProtocolRegistered = true
end

local function unregisterForgeProtocol()
  if not forgeProtocolRegistered then
    return
  end
  ProtocolGame.unregisterOpcode(ForgeOpcode.Send)
  forgeProtocolGame = nil
  forgeProtocolRegistered = false
end

local function sendForgeRequest(action)
  local msg = OutputMessage.create()
  msg:addU8(ForgeOpcode.Request)
  msg:addU8(action)
  sendForgeMessage(msg)
end

local function sendForgeOpen()
  sendForgeRequest(ForgeRequest.Open)
end

local function sendForgeClose()
  sendForgeRequest(ForgeRequest.Close)
end

local function sendForgeHistory()
  sendForgeRequest(ForgeRequest.History)
end

local function sendForgeFusion(convergence, itemId, tier, secondItemId, boostSuccess, protectTierLoss)
  local msg = OutputMessage.create()
  msg:addU8(ForgeOpcode.Request)
  msg:addU8(ForgeRequest.Fusion)
  msg:addU8(convergence and 1 or 0)
  msg:addU16(itemId)
  msg:addU8(tier)
  msg:addU16(secondItemId)
  msg:addU8(boostSuccess and 1 or 0)
  msg:addU8(protectTierLoss and 1 or 0)
  sendForgeMessage(msg)
end

local function sendForgeTransfer(convergence, itemId, tier, secondItemId)
  local msg = OutputMessage.create()
  msg:addU8(ForgeOpcode.Request)
  msg:addU8(ForgeRequest.Transfer)
  msg:addU8(convergence and 1 or 0)
  msg:addU16(itemId)
  msg:addU8(tier)
  msg:addU16(secondItemId)
  sendForgeMessage(msg)
end

local function sendForgeConverter(action)
  local msg = OutputMessage.create()
  msg:addU8(ForgeOpcode.Request)
  msg:addU8(ForgeRequest.Convert)
  msg:addU8(action)
  sendForgeMessage(msg)
end

local function onForgeGameEnd()
  unregisterForgeProtocol()
  offlineForge()
end

function init()
  forgeModuleActive = true

  connect(g_game, {
    onGameStart = registerForgeProtocol,
    onGameEnd = onForgeGameEnd,
    onForgeInit = ForgeSystem.init,
    onForgeData = ForgeSystem.onForgeData,
    onForgeFusion = ForgeSystem.onForgeFusion,
    onForgeTransfer = ForgeSystem.onForgeTransfer,
    onForgeHistory = ForgeSystem.onForgeHistory,
    onResourceBalance = onResourceBalance,
  })

  previousForgeMethods.requestForgeHistory = g_game.requestForgeHistory
  previousForgeMethods.sendForgeFusion = g_game.sendForgeFusion
  previousForgeMethods.sendForgeTransfer = g_game.sendForgeTransfer
  previousForgeMethods.sendForgeConverter = g_game.sendForgeConverter
  g_game.requestForgeHistory = sendForgeHistory
  g_game.sendForgeFusion = sendForgeFusion
  g_game.sendForgeTransfer = sendForgeTransfer
  g_game.sendForgeConverter = sendForgeConverter

  if g_game.isOnline() then
    registerForgeProtocol()
  end
end

function terminate()
  forgeModuleActive = false
  if forgeResourceRefreshEvent then
    removeEvent(forgeResourceRefreshEvent)
    forgeResourceRefreshEvent = nil
  end
  if ForgeSystem.cancelPendingEvents then
    ForgeSystem.cancelPendingEvents()
  end
  if ForgeSystem.destroyRadioGroups then
    ForgeSystem.destroyRadioGroups()
  end
  if forgeWindow then
    forgeWindow:destroy()
    forgeWindow = nil
  end
  if resultWindow then
    resultWindow:destroy()
    resultWindow = nil
  end
  mainPanel = nil
  fusionMenu = nil
  transferMenu = nil
  conversionMenu = nil
  historyMenu = nil
  disconnect(g_game, {
    onGameStart = registerForgeProtocol,
    onGameEnd = onForgeGameEnd,
    onForgeInit = ForgeSystem.init,
    onForgeData = ForgeSystem.onForgeData,
    onForgeFusion = ForgeSystem.onForgeFusion,
    onForgeTransfer = ForgeSystem.onForgeTransfer,
    onForgeHistory = ForgeSystem.onForgeHistory,
    onResourceBalance = onResourceBalance,
  })
  unregisterForgeProtocol()

  if g_game.requestForgeHistory == sendForgeHistory then
    g_game.requestForgeHistory = previousForgeMethods.requestForgeHistory
  end
  if g_game.sendForgeFusion == sendForgeFusion then
    g_game.sendForgeFusion = previousForgeMethods.sendForgeFusion
  end
  if g_game.sendForgeTransfer == sendForgeTransfer then
    g_game.sendForgeTransfer = previousForgeMethods.sendForgeTransfer
  end
  if g_game.sendForgeConverter == sendForgeConverter then
    g_game.sendForgeConverter = previousForgeMethods.sendForgeConverter
  end
  previousForgeMethods = {}
end

function toggle()
  if not ensureForgeUI() then
    return
  end
  ForgeSystem.fusionData = {}
  ForgeSystem.fusionConvergenceData = {}
  ForgeSystem.transferData = {}
  ForgeSystem.transferConvergenceData = {}
  if forgeWindow:isVisible() then
    sendForgeClose()
    forgeWindow:hide()
    g_client.setInputLockWidget(nil)
  else
    sendForgeOpen()
    forgeWindow:show(true)
    g_client.setInputLockWidget(forgeWindow)
    ForgeSystem.sideButton = true
    loadMenu('conversionMenu')
    forgeWindow:raise()
    forgeWindow:focus()
  end
end

function hideForge()
  if forgeWindow then
    forgeWindow:hide()
  end
  g_client.setInputLockWidget(nil)
end

function show()
  if not ensureForgeUI() then
    return
  end
  if not forgeWindow:isVisible() then
    forgeWindow:show(true)
    forgeWindow:raise()
    forgeWindow:focus()
    loadMenu('fusionMenu')
  end
  g_client.setInputLockWidget(forgeWindow)

  refreshForgeResourceLabels()
end

function loadMenu(menuId)
  --mainPanel:destroyChildren()

  if fusionMenu:isVisible() then
    fusionMenu:hide()
  end

  if transferMenu:isVisible() then
    transferMenu:hide()
  end

  if conversionMenu:isVisible() then
    conversionMenu:hide()
  end

  if historyMenu:isVisible() then
    historyMenu:hide()
  end

  local fusionMenuButton = forgeWindow.panelButtons:getChildById('fusionButton')
  local transferMenuButton = forgeWindow.panelButtons:getChildById('transferButton')
  local conversionMenuButton = forgeWindow.panelButtons:getChildById('conversionButton')
  local historyMenuButton = forgeWindow.panelButtons:getChildById('historyButton')

  transferMenuButton:setChecked(false)
  conversionMenuButton:setChecked(false)
  historyMenuButton:setChecked(false)
  fusionMenuButton:setChecked(false)
  if menuId == 'fusionMenu' then
    fusionMenu:show(true)
    ForgeSystem.updateFusion()
    fusionMenuButton:setChecked(true)
  elseif menuId == 'transferMenu' then
    transferMenu:show(true)
    ForgeSystem.updateTransfer()
    transferMenuButton:setChecked(true)
  elseif menuId == 'conversionMenu' then
    conversionMenu:show(true)
    ForgeSystem.updateConversion()
    conversionMenuButton:setChecked(true)
  elseif menuId == 'historyMenu' then
    historyMenu:show(true)
    historyMenuButton:setChecked(true)
    g_game.requestForgeHistory()
  end

  refreshForgeResourceLabels()
end

function offlineForge()
  if ForgeSystem.cancelPendingEvents then
    ForgeSystem.cancelPendingEvents()
  end
  if forgeResourceRefreshEvent then
    removeEvent(forgeResourceRefreshEvent)
    forgeResourceRefreshEvent = nil
  end
  if forgeWindow then
    forgeWindow:hide()
  end
  if resultWindow then
    resultWindow:hide()
  end
  g_client.setInputLockWidget(nil)
  if forgeWindow then
    ForgeSystem.destroyRadioGroups()
    fusionMenu.itemFusionPanel.itemsPanel:destroyChildren()
    transferMenu.itemTransferPanel.itemsPanel:destroyChildren()
    ForgeSystem.clearFusion()
    ForgeSystem.clearTransfer()
  end

  ForgeSystem.fusionData = {}
  ForgeSystem.fusionConvergenceData = {}
  ForgeSystem.transferData = {}
  ForgeSystem.transferConvergenceData = {}
end

function onResourceBalance(type, amount)
  local player = g_game.getLocalPlayer()
  if not player then
    return
  end

  if forgeResourceTypes[type] and forgeWindow and not forgeResourceRefreshEvent then
    forgeResourceRefreshEvent = addEvent(function()
      forgeResourceRefreshEvent = nil
      if not forgeModuleActive or not forgeWindow then
        return
      end
      if forgeWindow:isVisible() then
        refreshForgeResourceLabels()
      end
      ForgeSystem.checkFusionButton()
      ForgeSystem.checkFusionConversionButton()
      ForgeSystem.checkFusionButtons()
      ForgeSystem.checkTransferButton()
      ForgeSystem.checkTransferConvergenceButton()
      ForgeSystem.updateConversion()
    end)
  end
end
