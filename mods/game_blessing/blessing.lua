blessingWindow = nil

local blessingIcons = {
  ["2"] = "/images/game/blessings/blessings-icons_9",
  ["4"] = "/images/game/blessings/blessings-icons_4",
  ["8"] = "/images/game/blessings/blessings-icons_6",
  ["16"] = "/images/game/blessings/blessings-icons_3",
  ["32"] = "/images/game/blessings/blessings-icons_5",
  ["64"] = "/images/game/blessings/blessings-icons_2",
  ["128"] = "/images/game/blessings/blessings-icons_7",
  ["256"] = "/images/game/blessings/blessings-icons_8"
}

function init()
  blessingWindow = g_ui.displayUI('blessing')
  historyWindow = g_ui.displayUI('history')
  blessingWindow:hide()
  historyWindow:hide()

  connect(g_game, {
    onGameEnd = offline,
    onBlessingDialog = onBlessingDialog,
  })
end

function history()
  if blessingWindow:isVisible() then
    g_client.setInputLockWidget(nil)
    blessingWindow:hide()
    historyWindow:show()
    g_client.setInputLockWidget(historyWindow)
  else
    g_client.setInputLockWidget(nil)
    historyWindow:hide()
    blessingWindow:show()
    g_client.setInputLockWidget(blessingWindow)

  end
end

function terminate()
  disconnect(g_game, {
    onGameEnd = offline,
  })

  blessingWindow:destroy()
end

function show()
  g_game.requestBlessings()
end

function closeBlessing()
  blessingWindow:hide()
  g_client.setInputLockWidget(nil)
end

function closeBlessHistory()
  historyWindow:hide()
  g_client.setInputLockWidget(nil)
end

function offline()
  blessingWindow:hide()
  g_client.setInputLockWidget(nil)
end

function onBlessingDialog()
  local data = blessDialogData or {}
  if type(data) ~= "table" then
    return
  end

  local blesses = data.blesses or {}
  local premium = tonumber(data.premium) or 0
  local promotion = tonumber(data.promotion) or 0
  local pvpMinXpLoss = tonumber(data.pvpMinXpLoss) or 0
  local pvpMaxXpLoss = tonumber(data.pvpMaxXpLoss) or 0
  local pveExpLoss = tonumber(data.pveExpLoss) or 0
  local equipPvpLoss = tonumber(data.equipPvpLoss) or 0
  local equipPveLoss = tonumber(data.equipPveLoss) or 0
  local skull = tonumber(data.skull) or 0
  local aol = tonumber(data.aol) or 0

  blessingWindow:show(true)
  blessingWindow:focus()
  g_client.setInputLockWidget(blessingWindow)
  blessingWindow.miniWindowBlessing.blessings:destroyChildren()
  for i, content in pairs(blesses) do
    local widget = g_ui.createWidget('BlessingWidget', blessingWindow.miniWindowBlessing.blessings)

    widget.containerImage.image:setImageSource(blessingIcons[tostring(content[1])])
    widget.containerCount:setText(string.format('%d (0)', content[2]))
    if content[2] < 1 then
      widget.containerCount:setVisible(false)
      widget.storeButton:setVisible(true)
    end
  end

  blessingWindow.miniWindowPromotion.label:setColorText('\nYour character is promoted and your account has Premium\nstatus. As a result, your XP loss is reduced by [color="#f75f5f"]' .. promotion .. "%[/color]")


  local messageT = "- Depending on the fair fight rules, you will lose between [color=#f75f5f]" .. pvpMinXpLoss .. "%[/color] and [color=#f75f5f]" .. pvpMaxXpLoss .. "%[/color] less XP and skill points upon your next PvP death.\n- You will lose " ..
  "[color=#f75f5f]" .. pvpMinXpLoss .. "%[/color] less XP and skill points upon you next PvP death.\n- You will lose [color=#f75f5f]" .. pveExpLoss .. "%[/color] less XP and skill points upon you next PvE death.\n- There is a " ..
  "[color=#f75f5f]" .. equipPvpLoss .. "%[/color] chance that you will lose your equipped container on your next\n  death.\n- There is a [color=#f75f5f]" .. equipPveLoss .. "%[/color] chance that you will lose items upon your next death."


  blessingWindow.miniWindowInfo.label:setColorText(messageT)
end
