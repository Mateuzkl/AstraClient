worldTransfer = nil

worldTransferStep1 = nil
worldTransferStep2 = nil

worldTransferVar = {}
worldTransferVar.transactionId = 0
worldTransferVar.productType = 0
worldTransferVar.worlds = {}
worldTransferVar.hasRedSkull = false
worldTransferVar.hasBlackSkull = false
worldTransferVar.hasGuild = false
worldTransferVar.hasHouse = false
worldTransferVar.hasMarketCoin = false


function init()
  worldTransfer = g_ui.displayUI('worldTransfer')
  hide()

  worldTransferStep1 = worldTransfer:recursiveGetChildById('stepOne')
  worldTransferStep2 = worldTransfer:recursiveGetChildById('stepTwo')

  worldTransfer.onEnter = function() local s = worldTransferStep1:isVisible() and worldTransferStep1 or worldTransferStep2; local btn = s:recursiveGetChildById('buttonNext'); if btn and btn:isEnabled() then signalcall(btn.onClick) end end

  connect(g_game, {
    onGameEnd = onGameEnd
  })
end

function terminate()
  if worldTransfer then
    worldTransfer:destroy()
    worldTransfer = nil
  end
  disconnect(g_game, {
    onGameEnd = onGameEnd
  })
end

function toggle()
  if worldTransfer:isVisible() then
    hide()
  else
    show()
  end
end

function onGameEnd()
  hide()
end

function hide()
  worldTransfer:hide()
  g_client.setInputLockWidget(nil)
end

function closeTranfer()
  hide()
  g_client.setInputLockWidget(nil)
  modules.game_store.showStoreWindow()
end

function show()
  worldTransfer:show()
  g_client.setInputLockWidget(worldTransfer)
end

function configure(transactionId, productType, worlds, hasRedSkull, hasBlackSkull, hasGuild, hasHouse, hasMarketCoin)
  show()
  worldTransfer:setSize(tosize("450 356"))
  worldTransferStep1:setVisible(true)
  worldTransferStep2:setVisible(false)
  worldTransfer:setText(tr('Set Up a Character World Transfer - Step 1 of 2'))

  worldTransferVar.transactionId = transactionId
  worldTransferVar.productType = productType
  worldTransferVar.worlds = worlds
  worldTransferVar.hasRedSkull = hasRedSkull
  worldTransferVar.hasBlackSkull = hasBlackSkull
  worldTransferVar.hasGuild = hasGuild
  worldTransferVar.hasHouse = hasHouse
  worldTransferVar.hasMarketCoin = hasMarketCoin


  local player = g_game.getLocalPlayer()

  worldTransferStep1:recursiveGetChildById('characterName'):setText(player and player:getName() or '')
  worldTransferStep1:recursiveGetChildById('checkRed'):setImageSource('/images/store/icon-' .. (hasRedSkull and 'no' or 'yes'))
  worldTransferStep1:recursiveGetChildById('checkBlack'):setImageSource('/images/store/icon-' .. (hasBlackSkull and 'no' or 'yes'))
  worldTransferStep1:recursiveGetChildById('checkGuildLeader'):setImageSource('/images/store/icon-' .. (hasGuild and 'no' or 'yes'))
  worldTransferStep1:recursiveGetChildById('checkHouse'):setImageSource('/images/store/icon-' .. (hasHouse and 'no' or 'yes'))
  worldTransferStep1:recursiveGetChildById('checkTC'):setImageSource('/images/store/icon-' .. (hasMarketCoin and 'no' or 'yes'))

  local worldToTransfer = worldTransferStep1:recursiveGetChildById('worldToTransfer')
  worldToTransfer:clearOptions()
  local wordType = {
    [0] = 'Open PvP',
    [1] = 'Optional PvP',
    [2] = 'Open PvP',
    [3] = 'Retro-PvP',
  }
  for _, world in pairs(worlds) do
    worldToTransfer:addOption(world[1] .. ' (' .. (wordType[world[4]] or 'Unknow') ..')')
  end

  local enabled = not hasRedSkull and not hasBlackSkull and not hasGuild and not hasHouse and not hasMarketCoin
  worldTransferStep1:recursiveGetChildById('buttonNext'):setEnabled(enabled)
  worldTransferStep1:recursiveGetChildById('buttonNext').onClick = function()
    setupWorldTransferTwo()
  end
end

function setupWorldTransferTwo()
  worldTransferStep1:setVisible(false)
  worldTransferStep2:setVisible(true)
  worldTransfer:setSize(tosize("450 430"))
  worldTransfer:setText(tr('Set Up a Character World Transfer - Step 2 of 2'))

  local player = g_game.getLocalPlayer()

  worldTransferStep2:recursiveGetChildById('characterName'):setText(player and player:getName() or '')

  local worldToTransfer = worldTransferStep1:recursiveGetChildById('worldToTransfer')
  local selected = worldToTransfer:getCurrentOption()

  worldTransferStep2:recursiveGetChildById('worldName'):setText(selected.text)
  worldTransferStep2:recursiveGetChildById('backNext').onClick = function()
    configure(worldTransferVar.transactionId, worldTransferVar.productType, worldTransferVar.worlds, worldTransferVar.hasRedSkull, worldTransferVar.hasBlackSkull, worldTransferVar.hasGuild, worldTransferVar.hasHouse, worldTransferVar.hasMarketCoin)
  end
  worldTransferStep2:recursiveGetChildById('buttonNext').onClick = function()
    local worldName = string.gsub(selected.text, " %b()", "")
    g_game.buyStoreOffer(worldTransferVar.transactionId, worldTransferVar.productType, worldName)
    closeTranfer()
  end
end

function setUpdateTerms(checked)
  worldTransferStep2:recursiveGetChildById('buttonNext'):setEnabled(checked)
end
