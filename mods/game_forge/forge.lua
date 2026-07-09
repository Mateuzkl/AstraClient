forgeWindow = nil
fusionMenu = nil
transferMenu = nil
conversionMenu = nil
historyMenu = nil
resultWindow = nil

selectedItemFusionRadio = nil
selectedConvergenceFusionRadio = nil
selectedItemFusionConvectionRadio = nil

local forgeProtocolRegistered = false

-- crystalserver native Exalted Forge protocol (13.30+ / 15.24).
-- Validated byte-for-byte against the server source
-- (src/server/network/protocol/protocolgame.cpp) and the reference client
-- (koliseu-otc src/client/protocolgameparse.cpp).
--
-- client -> server
local ForgeClient = {
  Enter = 0xBF,        -- parseForgeEnter
  BrowseHistory = 0xC0 -- parseForgeBrowseHistory
}
-- ForgeAction_t (src/enums/forge_conversion.hpp)
local ForgeAction = {
  Fusion = 0,
  Transfer = 1,
  DustToSlivers = 2,
  SliversToCores = 3,
  IncreaseLimit = 4
}
-- server -> client. NOTE: the 0x86/0x87 bytes are reused: in the modern protocol the
-- server sends forge data on these opcodes, while the C++ switch maps 0x86 to
-- parseForgingData (a no-op stub) and 0x87 to parseTrappers (a dead legacy opcode that
-- crystalserver never sends). 0x88/0x89/0x8A have NO GameServer enum entry in this
-- client, so without a Lua handler they crash the parser with "unhandled opcode".
-- ProtocolGame:onOpcode runs BEFORE the C++ switch and consumes the message whenever a
-- handler is registered, so these handlers fully shadow the C++ path.
local ForgeServer = {
  Data = 0x86,    -- sendForgingData  (classification price table + config)
  Open = 0x87,    -- sendOpenForge    (fusion/transfer item lists)
  History = 0x88, -- sendForgeHistory
  Close = 0x89,   -- closeForgeWindow
  Result = 0x8A   -- sendForgeResult  (fusion/transfer result)
}

local function getForgeProtocol()
  return g_game.getProtocolGame()
end

local function sendForgeMessage(msg)
  local protocolGame = getForgeProtocol()
  if protocolGame then
    protocolGame:send(msg)
  end
end

-- The footer balances (gold, dust, slivers, exalted cores) are read straight from the
-- LocalPlayer resource cache, which only the server's 0xEE pushes keep current. The forge
-- tried to refresh them with g_game.requestResource(...), but that binding is a no-op in
-- this client (globals.lua stubs it), so the values were never actually re-requested.
-- Worse, after every fusion/transfer/conversion the server pushes a dust-only balance
-- (Player::setForgeDusts -> sendResourcesBalance with forgeSliver/forgeCores left at their
-- default 0), which ZEROES the cached sliver/core counts -- so the readouts collapsed to 0
-- on return, even after a convergence that never touched them. Mirror prey.lua: ask the
-- server for the authoritative values with the raw 0xED resource-balance request; each
-- reply re-fires onResourceBalance -> updateResourceBar and repaints. The Resource_t values
-- (const.lua) MUST equal the server's server_definitions.hpp enum.
local RESOURCE_BALANCE_REQUEST = 0xED
local function requestResourceBalance(resourceType)
  local protocolGame = getForgeProtocol()
  if not protocolGame then
    return
  end
  local msg = OutputMessage.create()
  msg:addU8(RESOURCE_BALANCE_REQUEST)
  msg:addU8(resourceType)
  protocolGame:send(msg)
end

-- Global in the module env so classes/Forge.lua (same sandbox) can call it too.
function requestForgeResources()
  requestResourceBalance(ResourceBank)
  requestResourceBalance(ResourceInventary)
  requestResourceBalance(ResourceForgeDust)
  requestResourceBalance(ResourceForgeSlivers)
  requestResourceBalance(ResourceForgeExaltedCore)
end

-- 0x86 sendForgingData: classification price table + forge config bytes.
-- Maps onto ForgeSystem.init(classPrice, transferMap, fusionPrices, transferPrices,
-- baseMultipier, slivers, totalSlivers, dustCost, dustPrice, maxDust, dustFusion,
-- convergenceDustFusion, dustTransfer, convergenceDustTransfer, success,
-- improveRateSuccess, tierLoss).
local function parseForgingData(protocolGame, msg)
  -- classification table: [U8 count]{ [U8 id][U8 tierCount]{ [U8 tier-1][U64 price] } }
  local classPrice = {}
  local classCount = msg:getU8()
  for i = 1, classCount do
    local classId = msg:getU8()
    local tierPrices = {}
    local tierCount = msg:getU8()
    for j = 1, tierCount do
      tierPrices[msg:getU8()] = msg:getU64() -- key = tier-1 (server-sent)
    end
    classPrice[classId] = { [2] = tierPrices }
  end

  -- exalted core table per tier: [U8 count]{ [U8 tier][U8 cores] }
  local transferMap = {}
  local coreCount = msg:getU8()
  for i = 1, coreCount do
    transferMap[msg:getU8()] = msg:getU8()
  end

  -- convergence fusion prices: [U8 count]{ [U8 tier-1][U64 price] }
  local fusionPrices = {}
  local fusionCount = msg:getU8()
  for i = 1, fusionCount do
    fusionPrices[msg:getU8()] = msg:getU64()
  end

  -- convergence transfer prices: [U8 count]{ [U8 tier][U64 price] }
  local transferPrices = {}
  local transferCount = msg:getU8()
  for i = 1, transferCount do
    transferPrices[msg:getU8()] = msg:getU64()
  end

  -- config bytes (fixed order):
  local costOneSliver = msg:getU8()  -- dust to make 1 sliver
  local sliverAmount = msg:getU8()   -- slivers produced
  local coreCost = msg:getU8()       -- slivers to make 1 core
  local increaseBase = msg:getU8()   -- 75 (dust-limit increase base)
  local dustLevel = msg:getU16()     -- player's current stored dust limit
  local maxDust = msg:getU16()       -- max stored dust limit (cap)
  local dustFusion = msg:getU8()
  local convergenceDustFusion = msg:getU8()
  local dustTransfer = msg:getU8()
  local convergenceDustTransfer = msg:getU8()
  local success = msg:getU8()
  local improveRateSuccess = msg:getU8()
  local tierLoss = msg:getU8()

  ForgeSystem.init(
    classPrice,
    transferMap,
    fusionPrices,
    transferPrices,
    costOneSliver,          -- baseMultipier (dust per sliver)
    sliverAmount,           -- slivers produced
    coreCost,               -- totalSlivers (slivers per core)
    increaseBase,           -- dustCost (limit-increase base, 75)
    dustLevel,              -- dustPrice (current dust limit; sets maxPlayerDust)
    maxDust,                -- maxDust (cap)
    dustFusion,
    convergenceDustFusion,
    dustTransfer,
    convergenceDustTransfer,
    success,
    improveRateSuccess,
    tierLoss
  )
end

-- 0x87 sendOpenForge: fusion items, convergence fusion items, transfer items,
-- convergence transfer items, dust level. Built into the {id, tier, count, subItems}
-- entries ForgeSystem expects.
local function parseOpenForge(protocolGame, msg)
  -- fusion items: [U16 count]{ [U8 friendCount=1][U16 id][U8 tier][U16 count] }
  local fusionData = {}
  local fusionCount = msg:getU16()
  for i = 1, fusionCount do
    msg:getU8() -- friend-item count (always 1)
    local id = msg:getItemId()
    local tier = msg:getU8()
    local count = msg:getU16()
    table.insert(fusionData, { id, tier, count, {} })
  end

  -- convergence fusion: [U16 slotCount]{ [U8 itemCount]{ [U16 id][U8 tier][U16 count] } }
  -- ForgeSystem.fusionConvergenceData is a flat list of {id, tier, count} entries.
  local fusionConvergenceData = {}
  local convFusionCount = msg:getU16()
  for i = 1, convFusionCount do
    local items = msg:getU8()
    for j = 1, items do
      local id = msg:getItemId()
      local tier = msg:getU8()
      local count = msg:getU16()
      table.insert(fusionConvergenceData, { id, tier, count, {} })
    end
  end

  -- transfer items: [U8 donorGroups]{ [U16 donorCount]{ [U16 id][U8 tier][U16 count] }
  --   [U16 receiverCount]{ [U16 id][U16 count] } }
  -- ForgeSystem.transferData is a flat list of donor {id, tier, count, subItems} where
  -- subItems is a map receiverId->count (the items that can receive this tier).
  local function readTransferGroups(groupCount)
    local result = {}
    for i = 1, groupCount do
      local donors = {}
      local donorCount = msg:getU16()
      for j = 1, donorCount do
        local id = msg:getItemId()
        local tier = msg:getU8()
        local count = msg:getU16()
        table.insert(donors, { id, tier, count })
      end
      local receivers = {}
      local receiverCount = msg:getU16()
      for j = 1, receiverCount do
        local id = msg:getItemId()
        local count = msg:getU16()
        receivers[id] = count
      end
      -- attach the same receiver map to every donor in this group
      for _, donor in ipairs(donors) do
        table.insert(result, { donor[1], donor[2], donor[3], receivers })
      end
    end
    return result
  end

  local transferData = readTransferGroups(msg:getU8())
  local transferConvergenceData = readTransferGroups(msg:getU8())

  local maxPlayerDust = msg:getU16()

  ForgeSystem.onForgeData(
    fusionData,
    fusionConvergenceData,
    transferData,
    transferConvergenceData,
    maxPlayerDust
  )
end

-- 0x88 sendForgeHistory: [U16 page][U16 lastPage][U8 count]{ [U32 createdAt]
--   [U8 actionType][String description][U8 bonusFlag] }
local function parseForgeHistory(protocolGame, msg)
  msg:getU16() -- current page (0-based)
  msg:getU16() -- last page
  local count = msg:getU8()
  local history = {}
  for i = 1, count do
    local createdAt = msg:getU32()
    local actionType = msg:getU8()
    local description = msg:getString()
    msg:getU8() -- bonus flag (1 if forge bonus rolled)
    table.insert(history, { createdAt, actionType, description })
  end
  ForgeSystem.onForgeHistory(history)
end

-- 0x89 closeForgeWindow: empty payload.
local function parseCloseForge(protocolGame, msg)
  offlineForge()
end

-- 0x8A sendForgeResult: [U8 actionType][U8 convergence][U8 success][U16 leftItemId]
--   [U8 leftTier][U16 rightItemId][U8 rightTier] then per action a bonus block.
local function parseForgeResult(protocolGame, msg)
  local actionType = msg:getU8()
  local convergence = msg:getU8() ~= 0
  local success = msg:getU8() ~= 0
  local leftItemId = msg:getItemId()
  local leftTier = msg:getU8()
  local rightItemId = msg:getItemId()
  local rightTier = msg:getU8()

  local bonus = 0
  local bonusItem = 0
  local bonusTier = 0
  local coreCount = 0

  if actionType == ForgeAction.Transfer then
    msg:getU8() -- bonus type is always 0x00 for transfer
    ForgeSystem.onForgeTransfer(convergence, success, leftItemId, leftTier, rightItemId, rightTier)
    return
  end

  -- fusion
  bonus = msg:getU8()
  if bonus == 2 then
    coreCount = msg:getU8()
  elseif bonus >= 4 and bonus <= 8 then
    bonusItem = msg:getItemId()
    bonusTier = msg:getU8()
  end

  ForgeSystem.onForgeFusion(
    convergence,
    success,
    leftItemId,   -- otherItem (donor / source, drawn white)
    leftTier,
    rightItemId,  -- itemId (receiver / result, drawn black)
    rightTier,
    bonus,        -- resultType
    bonusItem,    -- itemResult (only for bonus 4-8)
    bonusTier,    -- tierResult
    coreCount     -- count (kept cores, only for bonus 2)
  )
end

local forgeOpcodeHandlers = {
  [ForgeServer.Data] = parseForgingData,
  [ForgeServer.Open] = parseOpenForge,
  [ForgeServer.History] = parseForgeHistory,
  [ForgeServer.Close] = parseCloseForge,
  [ForgeServer.Result] = parseForgeResult
}

local function registerForgeProtocol()
  if forgeProtocolRegistered then
    return
  end
  for opcode, handler in pairs(forgeOpcodeHandlers) do
    ProtocolGame.unregisterOpcode(opcode)
    ProtocolGame.registerOpcode(opcode, handler)
  end
  forgeProtocolRegistered = true
end

local function unregisterForgeProtocol()
  if not forgeProtocolRegistered then
    return
  end
  for opcode in pairs(forgeOpcodeHandlers) do
    ProtocolGame.unregisterOpcode(opcode)
  end
  forgeProtocolRegistered = false
end

-- KoliseuOT extension: ask the server to (re)push the forge data on demand. The native
-- crystalserver protocol has NO "open forge" request opcode -- the forge item lists
-- (0x87 sendOpenForge) + config (0x86 sendForgingData) are only pushed when the player
-- uses a forge object in-game. So the sidebutton adds a tiny bridge over extended opcode
-- 212 (server: data-koliseu/scripts/custom/forge_otc_bridge.lua). The server replies with
-- sendOpenForge ONLY for VIP players; a non-VIP gets no reply, so the fusion/transfer tabs
-- stay gated (see ForgeSystem.sideButton) and they must walk to a real forge in a city.
-- Resource conversion works for everyone (it needs only the 0xEE balances).
local FORGE_OPEN_OPCODE = 212
local function sendForgeOpen()
  local protocolGame = getForgeProtocol()
  if protocolGame then
    pcall(function() protocolGame:sendExtendedOpcode(FORGE_OPEN_OPCODE, "open") end)
  end
end

local function sendForgeClose()
  -- No close packet in the native protocol; the window is closed locally.
end

local function sendForgeHistory(page)
  local msg = OutputMessage.create()
  msg:addU8(ForgeClient.BrowseHistory)
  msg:addU8(page or 0)
  sendForgeMessage(msg)
end

-- 0xBF parseForgeEnter. The first byte is the ForgeAction_t. Fusion/Transfer carry the
-- item payload; conversions (dust->sliver / sliver->core / increase-limit) carry only
-- the action byte.
local function sendForgeFusion(convergence, itemId, tier, secondItemId, boostSuccess, protectTierLoss)
  local msg = OutputMessage.create()
  msg:addU8(ForgeClient.Enter)
  msg:addU8(ForgeAction.Fusion)
  msg:addU8(convergence and 1 or 0)
  msg:addItemId(itemId)
  msg:addU8(tier)
  msg:addItemId(secondItemId)
  -- server only reads usedCore/reduceTierLoss when NOT convergence
  if not convergence then
    msg:addU8(boostSuccess and 1 or 0)
    msg:addU8(protectTierLoss and 1 or 0)
  end
  sendForgeMessage(msg)
end

local function sendForgeTransfer(convergence, itemId, tier, secondItemId)
  local msg = OutputMessage.create()
  msg:addU8(ForgeClient.Enter)
  msg:addU8(ForgeAction.Transfer)
  msg:addU8(convergence and 1 or 0)
  msg:addItemId(itemId)
  msg:addU8(tier)
  msg:addItemId(secondItemId)
  sendForgeMessage(msg)
end

-- action: ForgeRequest legacy values (2=dust->sliver, 3=sliver->core, 4=increase limit)
-- map straight onto ForgeAction_t (DustToSlivers/SliversToCores/IncreaseLimit).
local function sendForgeConverter(action)
  local msg = OutputMessage.create()
  msg:addU8(ForgeClient.Enter)
  msg:addU8(action)
  sendForgeMessage(msg)
end

local function onForgeGameEnd()
  unregisterForgeProtocol()
  offlineForge()
end

function init()
  forgeWindow = g_ui.displayUI('forge')
  mainPanel = forgeWindow:getChildById('contentPanel')

  fusionMenu = g_ui.loadUI('styles/fusion',  mainPanel)
  fusionMenu:hide()

  transferMenu = g_ui.loadUI('styles/transfer',  mainPanel)
  transferMenu:hide()

  conversionMenu = g_ui.loadUI('styles/conversion',  mainPanel)
  conversionMenu:hide()

  historyMenu = g_ui.loadUI('styles/history',  mainPanel)
  historyMenu:hide()

  resultWindow = g_ui.displayUI('styles/result')
  resultWindow:hide()

  loadMenu('fusionMenu')
  hideForge()

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

  g_game.requestForgeHistory = sendForgeHistory
  g_game.sendForgeFusion = sendForgeFusion
  g_game.sendForgeTransfer = sendForgeTransfer
  g_game.sendForgeConverter = sendForgeConverter

  if g_game.isOnline() then
    registerForgeProtocol()
  end
end

function terminate()
  if forgeWindow then
    forgeWindow:destroy()
    forgeWindow = nil
  end
  if resultWindow then
    resultWindow:destroy()
    resultWindow = nil
  end
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
end

function toggle()
  if forgeWindow:isVisible() then
    sendForgeClose()
    forgeWindow:hide()
    g_client.setInputLockWidget(nil)
  else
    -- crystalserver has no "open forge" request opcode: the fusion/transfer item lists
    -- (0x86/0x87) are pushed only when the player uses a forge object in-game, which
    -- auto-opens the window via ForgeSystem.onForgeData -> show(). The sidebutton just
    -- re-shows the window so the player can browse the last received data and use the
    -- resource conversion tab (which only needs the 0xEE resource balances).
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
  forgeWindow:hide()
  g_client.setInputLockWidget(nil)
end

-- exported so game_sidebuttons' forceCloseButton can close us before opening
-- the next exclusive dialog (sendForgeClose is only sent on user-initiated
-- toggle; forge traffic stays choked off for crystalserver)
function hide()
  if forgeWindow and forgeWindow:isVisible() then
    hideForge()
  end
end

function show()
  if not forgeWindow:isVisible() then
    forgeWindow:show(true)
    forgeWindow:raise()
    forgeWindow:focus()
    loadMenu('fusionMenu')
  end
  g_client.setInputLockWidget(forgeWindow)


  ForgeSystem.updateResourceBar()
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

  g_game.doThing(false)
  requestForgeResources()
  g_game.doThing(false)

  local fusionMenuButton = forgeWindow.panelButtons:getChildById('fusionButton')
  local transferMenuButton = forgeWindow.panelButtons:getChildById('transferButton')
  local conversionMenuButton = forgeWindow.panelButtons:getChildById('conversionButton')
  local historyMenuButton = forgeWindow.panelButtons:getChildById('historyButton')

  transferMenuButton:setChecked(false)
  conversionMenuButton:setChecked(false)
  historyMenuButton:setChecked(false)
  fusionMenuButton:setChecked(false)
  -- Check the active tab BEFORE running the (heavier) content update. If updateFusion/
  -- updateTransfer ever errors, the tab highlight must still have been applied, otherwise
  -- the window looks like no tab is selected.
  if menuId == 'fusionMenu' then
    fusionMenuButton:setChecked(true)
    fusionMenu:show(true)
    ForgeSystem.updateFusion()
  elseif menuId == 'transferMenu' then
    transferMenuButton:setChecked(true)
    transferMenu:show(true)
    ForgeSystem.updateTransfer()
  elseif menuId == 'conversionMenu' then
    conversionMenuButton:setChecked(true)
    conversionMenu:show(true)
    ForgeSystem.updateConversion()
  elseif menuId == 'historyMenu' then
    historyMenuButton:setChecked(true)
    historyMenu:show(true)
    g_game.requestForgeHistory()
  end

  ForgeSystem.updateResourceBar()
end

function offlineForge()
  forgeWindow:hide()
  resultWindow:hide()
  g_client.setInputLockWidget(nil)
  ForgeSystem.clearFusion()
  ForgeSystem.clearTransfer()

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

  if table.contains({ResourceBank, ResourceInventary, ResourceForgeDust, ResourceForgeSlivers, ResourceForgeExaltedCore}, type) then
    ForgeSystem.updateResourceBar()

    ForgeSystem.checkFusionButton()
    ForgeSystem.updateConversion()
  end
end
