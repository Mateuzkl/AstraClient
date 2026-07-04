if not Imbuement then
  Imbuement = {
    window = nil,
    selectItemOrScroll = nil,
    scrollImbue = nil,
    selectImbue = nil,
    clearImbue = nil,

    messageWindow = nil,

    bankGold = 0,
    inventoryGold = 0,
  }
  Imbuement.__index = Imbuement
end

Imbuement.MessageDialog = {
	ImbuementSuccess = 0,
	ImbuementError = 1,
	ImbuementRollFailed = 2,
	ImbuingStationNotFound = 3,
	ClearingCharmSuccess = 10,
	ClearingCharmError = 11,
	PreyMessage = 20,
	PreyError = 21,
}

local self = Imbuement
function Imbuement.init()
  self.window = g_ui.displayUI('t_imbui')
  self:hide()

  ImbuementSelection:startUp()

  self.selectItemOrScroll = self.window:recursiveGetChildById('selectItemOrScroll')
  self.scrollImbue = self.window:recursiveGetChildById('scrollImbue')
  self.selectImbue = self.window:recursiveGetChildById('selectImbue')
  self.clearImbue = self.window:recursiveGetChildById('clearImbue')

  connect(g_game, {
    onGameStart = self.offline,
    onGameEnd = self.offline,
    onOpenImbuementWindow = self.onOpenImbuementWindow,
    onImbuementItem = self.onImbuementItem,
    onImbuementScroll = self.onImbuementScroll,
    onResourceBalance = self.onResourceBalance,
    onCloseImbuementWindow = self.offline,
    onMessageDialog = self.onMessageDialog,
  })
end

function Imbuement.terminate()
  disconnect(g_game, {
    onGameStart = self.offline,
    onGameEnd = self.offline,
    onOpenImbuementWindow = self.onOpenImbuementWindow,
    onImbuementItem = self.onImbuementItem,
    onImbuementScroll = self.onImbuementScroll,
    onResourceBalance = self.onResourceBalance,
    onCloseImbuementWindow = self.offline,
    onMessageDialog = self.onMessageDialog,
  })

  if self.messageWindow then
    self.messageWindow:destroy()
    self.messageWindow = nil
  end

  ImbuementItem:shutdown()
  ImbuementSelection:shutdown()
  ImbuementScroll:shutdown()
  if self.selectItemOrScroll then
    self.selectItemOrScroll:destroy()
    self.selectItemOrScroll = nil
  end

  if self.scrollImbue then
    self.scrollImbue:destroy()
    self.scrollImbue = nil
  end

  if self.selectImbue then
    self.selectImbue:destroy()
    self.selectImbue = nil
  end

  if self.clearImbue then
    self.clearImbue:destroy()
    self.clearImbue = nil
  end

  if self.window then
    self.window:destroy()
    self.window = nil
  end
end

function Imbuement.online()
 self:hide()
 if self.messageWindow then
   self.messageWindow:destroy()
   self.messageWindow = nil
 end
end

function Imbuement.offline()
  self:hide()
  ImbuementItem:shutdown()
  ImbuementScroll:shutdown()
  if self.messageWindow then
    self.messageWindow:destroy()
    self.messageWindow = nil
  end
  g_client.setInputLockWidget(nil)
end

function Imbuement.show()
  self.window:show(true)
  self.window:raise()
  self.window:focus()
  if self.messageWindow then
    self.messageWindow:destroy()
    self.messageWindow = nil
  end
  g_client.setInputLockWidget(self.window)
end

function Imbuement.hide()
  self.window:hide()
  g_client.setInputLockWidget(nil)
end

function Imbuement.close()
  if g_game.isOnline() then
    g_game.closeImbuingWindow()
  end

  self.window:hide()
  g_client.setInputLockWidget(nil)
end

function Imbuement:toggleMenu(menu)
  for key, value in pairs(self) do
    if type(value) ~= 'userdata' or key == 'window' then
      goto continue
    end

    if key == menu then
      value:show()
      if value.main_window_size then
        self.window:setSize(value.main_window_size)
      end

    else
      value:hide()
    end

    ::continue::
  end
end

function Imbuement.notifyTrackerRefresh()
  -- Nudge the Imbuement Tracker (separate game_trackers module) to re-request
  -- durations right after an apply/clear, bypassing the server's 10s tracker
  -- throttle. game_trackers owns the window and the "is it open?" gate, so
  -- delegate there; guard in case the module isn't loaded.
  local trackers = modules.game_trackers
  if trackers and trackers.ImbuementTracker then
    trackers.ImbuementTracker.requestRefresh()
  end
end

function Imbuement.onOpenImbuementWindow()
  self:show()
  g_game.doThing(false)
  g_game.requestResource(ResourceBank)
  g_game.doThing(true)
  g_game.doThing(false)
  g_game.requestResource(ResourceInventary)
  g_game.doThing(true)
  self:toggleMenu("selectItemOrScroll")
end

function Imbuement.onImbuementItem(itemId, tier, slots, activeSlots, availableImbuements, needItems)
  self:toggleMenu("selectImbue")
  ImbuementItem.setup(itemId, tier, slots, activeSlots, availableImbuements, needItems)
end

function Imbuement.onImbuementScroll(availableImbuements, needItems)
  self:toggleMenu("scrollImbue")
  ImbuementScroll.setup(availableImbuements, needItems)
end

function Imbuement.onSelectItem()
  self:hide()
  ImbuementSelection:selectItem()
end

function Imbuement.onSelectScroll()
  g_game.selectImbuementScroll()
end

function Imbuement.onResourceBalance(type, balance)
  local player = g_game.getLocalPlayer()
  local bankMoney = player:getResourceValue(ResourceBank)
  local characterMoney = player:getResourceValue(ResourceInventary)

  self.bankGold = bankMoney or 0
  self.inventoryGold = characterMoney or 0

  if type == 0 or type == 1 then
    -- text grows left of the coin icon; budget = panel width minus the icon and a small gap
    local goldPanel = self.window.contentPanel.gold
    setMoneyAutoFit(goldPanel.text, self.bankGold + self.inventoryGold,
      goldPanel:getWidth() - goldPanel.gold:getWidth() - 4)
  end
end

function Imbuement.onMessageDialog(type, content)
  if type > Imbuement.MessageDialog.ImbuingStationNotFound or not self.window:isVisible() then
    return
  end

  self:hide()
  local message = content or ""
  if self.messageWindow then
    self.messageWindow:destroy()
    self.messageWindow = nil
  end

  local function confirm()
      self.messageWindow:destroy()
      self.messageWindow = nil

      Imbuement.show()
  end

  self.messageWindow = displayGeneralBox(tr('Message Dialog'), content,
    { { text=tr('Ok'), callback=confirm },
    }, confirm, confirm)


  g_client.setInputLockWidget(self.messageWindow)
end
