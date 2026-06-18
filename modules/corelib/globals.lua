-- @docvars @{

-- Compatibility with newer module packs. Older OTCv8 builds already call Lua
-- widget handlers directly, but do not expose insertLuaCall/removeLuaCall.
if UIWidget then
  UIWidget.insertLuaCall = UIWidget.insertLuaCall or function(self, name) return self end
  UIWidget.removeLuaCall = UIWidget.removeLuaCall or function(self, name) return self end
  UIWidget.setClickSound = UIWidget.setClickSound or function(self, sound) return self end
  UIWidget.addSound = UIWidget.addSound or function(self, soundType, sound) return self end
  UIWidget.setHTML = UIWidget.setHTML or function(self, html)
    if self.setText then
      local text = tostring(html or '')
      text = text:gsub('<br%s*/?>', '\n')
      text = text:gsub('</p>', '\n')
      text = text:gsub('<[^>]->', '')
      self:setText(text)
    end
    return self
  end
  UIWidget.setActionId = UIWidget.setActionId or function(self, actionId)
    self.actionId = actionId
    return self
  end
  UIWidget.getActionId = UIWidget.getActionId or function(self)
    return self.actionId or 0
  end
  UIWidget.setImageVisible = UIWidget.setImageVisible or function(self, visible)
    self.imageVisible = visible
    return self
  end
  UIWidget.isImageVisible = UIWidget.isImageVisible or function(self)
    return self.imageVisible ~= false
  end
  UIWidget.getImageVisible = UIWidget.getImageVisible or UIWidget.isImageVisible
  UIWidget.setImageShader = UIWidget.setImageShader or function(self, shader)
    self.imageShader = shader
    return self
  end
  UIWidget.getImageShader = UIWidget.getImageShader or function(self)
    return self.imageShader or ''
  end
  UIWidget.setShader = UIWidget.setShader or UIWidget.setImageShader
  UIWidget.start = UIWidget.start or function(self) return self end
  UIWidget.stop = UIWidget.stop or function(self) return self end
  UIWidget.setFlipDirection = UIWidget.setFlipDirection or function(self, direction)
    self.flipDirection = direction
    return self
  end
  UIWidget.getFlipDirection = UIWidget.getFlipDirection or function(self)
    return self.flipDirection
  end
  UIWidget.setDrawHUDStatus = UIWidget.setDrawHUDStatus or function(self, status)
    self.drawHUDStatus = status
    return self
  end
  UIWidget.setDrawOwnHealth = UIWidget.setDrawOwnHealth or function(self, value) self.drawOwnHealth = value; return self end
  UIWidget.setDrawNpcIcon = UIWidget.setDrawNpcIcon or function(self, value) self.drawNpcIcon = value; return self end
  UIWidget.setDrawPlayerBars = UIWidget.setDrawPlayerBars or function(self, value) self.drawPlayerBars = value; return self end
  UIWidget.setDrawHealthBarsOnTop = UIWidget.setDrawHealthBarsOnTop or function(self, value) self.drawHealthBarsOnTop = value; return self end
  UIWidget.setDrawOwnName = UIWidget.setDrawOwnName or function(self, value) self.drawOwnName = value; return self end
  UIWidget.setDrawOwnManaBar = UIWidget.setDrawOwnManaBar or function(self, value) self.drawOwnManaBar = value; return self end
  UIWidget.setDrawOwnManaShieldBar = UIWidget.setDrawOwnManaShieldBar or function(self, value) self.drawOwnManaShieldBar = value; return self end
  UIWidget.setDrawHarmonyBar = UIWidget.setDrawHarmonyBar or function(self, value) self.drawHarmonyBar = value; return self end
  UIWidget.setDrawOwnHUD = UIWidget.setDrawOwnHUD or function(self, value) self.drawOwnHUD = value; return self end
  UIWidget.setDrawOtherHUD = UIWidget.setDrawOtherHUD or function(self, value) self.drawOtherHUD = value; return self end
  UIWidget.setDrawOwnBars = UIWidget.setDrawOwnBars or function(self, value) self.drawOwnBars = value; return self end
  UIWidget.setShowArcs = UIWidget.setShowArcs or function(self, value) self.showArcs = value; return self end
  UIWidget.setHarmonyLeftDraw = UIWidget.setHarmonyLeftDraw or function(self, value) self.harmonyLeftDraw = value; return self end
  UIWidget.setCrosshairVisible = UIWidget.setCrosshairVisible or function(self, value) self.crosshairVisible = value; return self end
  UIWidget.setDrawWaypoints = UIWidget.setDrawWaypoints or function(self, value) self.drawWaypoints = value; return self end
  UIWidget.clearWaypoints = UIWidget.clearWaypoints or function(self) self.waypoints = {}; return self end
  UIWidget.clearRoutePath = UIWidget.clearRoutePath or function(self) self.routePath = {}; return self end
  UIWidget.makeWaypoints = UIWidget.makeWaypoints or function(self, coordinates, floor)
    self.waypoints = self.waypoints or {}
    self.waypoints[floor or 0] = coordinates or {}
    return self
  end
  UIWidget.makeRouth = UIWidget.makeRouth or function(self, coordinates, floor)
    self.routePath = self.routePath or {}
    self.routePath[floor or 0] = coordinates or {}
    return self
  end
  UIWidget.setDrawRegions = UIWidget.setDrawRegions or function(self, value) self.drawRegions = value; return self end
  UIWidget.setFilter = UIWidget.setFilter or function(self, filter, value)
    self.filters = self.filters or {}
    self.filters[filter] = value == nil and true or value
    return self
  end
  UIWidget.setSortType = UIWidget.setSortType or function(self, sortType)
    self.sortType = sortType
    return self
  end
  UIWidget.setIsParty = UIWidget.setIsParty or function(self, isParty)
    self.isParty = isParty
    return self
  end
  UIWidget.toggleManaBar = UIWidget.toggleManaBar or function(self, show)
    local manaBar = self.getChildById and self:getChildById('manaBar')
    if manaBar then
      manaBar:setVisible(show)
    end
    return self
  end
  UIWidget.setPriceable = UIWidget.setPriceable or function(self, priceable)
    self.priceable = priceable
    return self
  end
  UIWidget.isPriceable = UIWidget.isPriceable or function(self)
    return self.priceable == true
  end
  UIWidget.setPriceOffset = UIWidget.setPriceOffset or function(self, offset)
    self.priceOffset = offset
    return self
  end
  UIWidget.getPriceOffset = UIWidget.getPriceOffset or function(self)
    return self.priceOffset
  end
  UIWidget.setColorText = UIWidget.setColorText or function(self, text)
    text = tostring(text or '')
    if self.setColoredText then
      local colored = {}
      local defaultColor = '#ffffff'
      local current = 1
      while true do
        local tagStart, tagEnd, color = text:find('%[color=([^%]]+)%]', current)
        if not tagStart then
          local rest = text:sub(current):gsub('%[/color%]', '')
          if rest ~= '' then setStringColor(colored, rest, defaultColor) end
          break
        end

        local before = text:sub(current, tagStart - 1)
        if before ~= '' then setStringColor(colored, before, defaultColor) end

        local closeStart, closeEnd = text:find('%[/color%]', tagEnd + 1)
        local value = color:gsub('^[\'"]', ''):gsub('[\'"]$', '')
        if closeStart then
          setStringColor(colored, text:sub(tagEnd + 1, closeStart - 1), value)
          current = closeEnd + 1
        else
          setStringColor(colored, text:sub(tagEnd + 1), value)
          current = #text + 1
        end
      end

      self.coloredText = colored
      self:setColoredText(colored)
    elseif self.setText then
      self:setText(text:gsub('%[color=[^%]]+%]', ''):gsub('%[/color%]', ''))
    end
    return self
  end
  UIWidget.getColoredText = UIWidget.getColoredText or function(self)
    return self.coloredText
  end
  UIWidget.getVisibleCreatures = UIWidget.getVisibleCreatures or function(self)
    local creatures = {}
    for _, child in ipairs(self:getChildren()) do
      if (not child.isVisible or child:isVisible()) and child.getCreature then
        local creature = child:getCreature()
        if creature then
          table.insert(creatures, creature)
        end
      end
    end
    return creatures
  end
  UIWidget.getAttackableCreatures = UIWidget.getAttackableCreatures or function(self)
    local creatures = {}
    for _, creature in ipairs(self:getVisibleCreatures()) do
      if not creature.isNpc or not creature:isNpc() then
        table.insert(creatures, creature)
      end
    end
    return creatures
  end
end

g_client = g_client or {}
ESoundUI = ESoundUI or { SoundTypeClick = 0 }
ThingInvalidCategory = ThingInvalidCategory or 0
ThingCategoryItem = ThingCategoryItem or 1
ThingCategoryCreature = ThingCategoryCreature or 2
ThingCategoryEffect = ThingCategoryEffect or 3

local function noop() end

do
  local defaultClientVersion = 860
  GameInfo = GameInfo or {}
  GameInfo.version = GameInfo.version or defaultClientVersion
  GameInfo.strVersion = GameInfo.strVersion or tostring(GameInfo.version)
  GameInfo.CoinName = GameInfo.CoinName or 'Astra Coins'
end

consoleln = consoleln or function(...)
  local values = {}
  for i = 1, select('#', ...) do
    values[i] = tostring(select(i, ...))
  end
  print(table.concat(values, ' '))
end

AttachedEffect = AttachedEffect or {}
AttachedEffect.create = AttachedEffect.create or function(id, thingId, thingCategory)
  local effect = {
    id = id,
    thingId = thingId,
    thingCategory = thingCategory
  }
  function effect:getId() return self.id end
  effect.setSpeed = noop
  effect.setShader = noop
  effect.setOffset = noop
  effect.setOnTop = noop
  effect.setOnTopByDir = noop
  effect.setDirOffset = noop
  return effect
end

if Creature then
  Creature.clearAttachedEffects = Creature.clearAttachedEffects or noop
  Creature.attachEffect = Creature.attachEffect or noop
  Creature.getAttachedEffects = Creature.getAttachedEffects or function() return {} end
  Creature.setDisableWalkAnimation = Creature.setDisableWalkAnimation or noop
end

if LocalPlayer then
  LocalPlayer.clearAttachedEffects = LocalPlayer.clearAttachedEffects or noop
  LocalPlayer.attachEffect = LocalPlayer.attachEffect or noop
  LocalPlayer.getAttachedEffects = LocalPlayer.getAttachedEffects or function() return {} end
  LocalPlayer.setDisableWalkAnimation = LocalPlayer.setDisableWalkAnimation or noop
end

if ThingType then
  ThingType.setDrawOffset = ThingType.setDrawOffset or noop
  ThingType.setDrawInformationOffset = ThingType.setDrawInformationOffset or noop
  ThingType.setAnimatedTextOffset = ThingType.setAnimatedTextOffset or noop
  ThingType.setCanBeMarked = ThingType.setCanBeMarked or noop
  ThingType.setCircleTargetFrame = ThingType.setCircleTargetFrame or noop
  ThingType.setServerCollisionSquare = ThingType.setServerCollisionSquare or noop
end

if UIMinimap then
  UIMinimap.setPartyColorMode = UIMinimap.setPartyColorMode or function(self, mode)
    self.partyColorMode = mode
  end
  UIMinimap.getPartyColorMode = UIMinimap.getPartyColorMode or function(self)
    return self.partyColorMode or 1
  end
  UIMinimap.addWidget = UIMinimap.addWidget or function(self, imagePath, imageSize, pos, tooltip)
    if type(imagePath) == 'string' and imagePath:sub(1, 1) ~= '/' then
      imagePath = '/' .. imagePath
    end
    self._minimapWidgets = self._minimapWidgets or {}
    local id = #self._minimapWidgets + 1
    local widget = g_ui.createWidget('MinimapFlag', self)
    if widget then
      widget.widgetId = id
      widget.imagePath = imagePath
      widget.imageSize = imageSize
      widget.pos = pos
      widget.tooltip = tooltip
      if widget.setImageSource then
        widget:setImageSource(imagePath)
      elseif widget.setIcon then
        widget:setIcon(imagePath)
      end
      if imageSize and widget.setSize then
        widget:setSize(imageSize)
      end
      if pos and self.centerInPosition then
        self:centerInPosition(widget, pos)
      end
    end
    self._minimapWidgets[id] = widget
    return id
  end
  UIMinimap.removeWidget = UIMinimap.removeWidget or function(self, id)
    if self._minimapWidgets and self._minimapWidgets[id] then
      self._minimapWidgets[id]:destroy()
      self._minimapWidgets[id] = nil
    end
  end
  UIMinimap.moveWidget = UIMinimap.moveWidget or function(self, id, pos)
    local widget = self._minimapWidgets and self._minimapWidgets[id]
    if widget then
      widget.pos = pos
      if self.centerInPosition then
        self:centerInPosition(widget, pos)
      end
    end
  end
  UIMinimap.getWidgetInfoFromPoint = UIMinimap.getWidgetInfoFromPoint or function()
    return nil
  end
  UIMinimap.setCurrentView = UIMinimap.setCurrentView or function(self, view)
    self.currentView = view
  end
  UIMinimap.getCurrentView = UIMinimap.getCurrentView or function(self)
    return self.currentView
  end
  UIMinimap.setLevelSeparator = UIMinimap.setLevelSeparator or function(self, levelSeparator)
    self.levelSeparator = levelSeparator
  end
  UIMinimap.clearWaypoints = UIMinimap.clearWaypoints or function(self)
    self._minimapWaypoints = {}
    return self
  end
  UIMinimap.clearRoutePath = UIMinimap.clearRoutePath or function(self)
    self._minimapRoutePath = {}
    return self
  end
  UIMinimap.setDrawWaypoints = UIMinimap.setDrawWaypoints or function(self, enabled)
    self._drawWaypoints = enabled and true or false
    return self
  end
  UIMinimap.makeWaypoints = UIMinimap.makeWaypoints or function(self, coordinates, floor)
    self._minimapWaypoints = self._minimapWaypoints or {}
    self._minimapWaypoints[floor or 0] = coordinates or {}
    return self
  end
  UIMinimap.makeRouth = UIMinimap.makeRouth or function(self, coordinates, floor)
    self._minimapRoutePath = self._minimapRoutePath or {}
    self._minimapRoutePath[floor or 0] = coordinates or {}
    return self
  end
  UIMinimap.hasClickedRegion = UIMinimap.hasClickedRegion or function()
    return false
  end
end

if UIProgressRect then
  local updateProgressRectTimer

  UIProgressRect.showTime = UIProgressRect.showTime or function(self, show)
    self._showTime = show
    if not show and self.setText then
      self:setText('')
    end
  end

  UIProgressRect.showProgress = UIProgressRect.showProgress or function(self, show)
    self._showProgress = show
  end

  UIProgressRect.setDuration = UIProgressRect.setDuration or function(self, duration)
    self._duration = math.max(0, tonumber(duration) or 0)
    self._durationElapsed = 0
  end

  UIProgressRect.getDuration = UIProgressRect.getDuration or function(self)
    return self._duration or 0
  end

  UIProgressRect.getTimeElapsed = UIProgressRect.getTimeElapsed or function(self)
    if self._durationRunning then
      return math.min(self._duration or 0, math.max(0, g_clock.millis() - (self._durationStartedAt or g_clock.millis())))
    end
    return math.min(self._durationElapsed or 0, self._duration or 0)
  end

  updateProgressRectTimer = function(widget)
    if not widget or not widget._durationRunning then
      return
    end

    widget._durationElapsed = widget:getTimeElapsed()
    local remaining = math.max(0, (widget._duration or 0) - (widget._durationElapsed or 0))
    if widget.setPercent then
      widget:setPercent((widget._duration or 0) > 0 and widget._durationElapsed * 100 / widget._duration or 100)
    end
    if widget.setText and widget._showTime ~= false then
      widget:setText(remaining > 0 and tostring(math.ceil(remaining / 1000)) or '')
    end

    if remaining <= 0 then
      widget._durationRunning = false
      widget._durationEvent = nil
      if widget.onTimeEnd then
        widget.onTimeEnd()
      end
      return
    end

    widget._durationEvent = scheduleEvent(function() updateProgressRectTimer(widget) end, 250)
  end

  UIProgressRect.start = UIProgressRect.start or function(self)
    if self._durationEvent then
      removeEvent(self._durationEvent)
      self._durationEvent = nil
    end
    self._durationRunning = true
    self._durationStartedAt = g_clock.millis()
    self._durationElapsed = 0
    if self.setPercent then
      self:setPercent((self._duration or 0) > 0 and 0 or 100)
    end
    updateProgressRectTimer(self)
  end

  UIProgressRect.stop = UIProgressRect.stop or function(self)
    if self._durationEvent then
      removeEvent(self._durationEvent)
      self._durationEvent = nil
    end
    self._durationElapsed = self:getTimeElapsed()
    self._durationRunning = false
  end
end

if UIItem then
  UIItem.setVirtualCount = UIItem.setVirtualCount or function(self, count)
    if self.setItemCount then
      self:setItemCount(tonumber(tostring(count):match('%d+')) or 1)
    end
  end
end

if g_minimap then
  g_minimap.addWidget = g_minimap.addWidget or noop
  g_minimap.removeWidget = g_minimap.removeWidget or noop
end

g_realMinimap = g_realMinimap or {}
g_realMinimap.clean = g_realMinimap.clean or noop
g_realMinimap.loadImage = g_realMinimap.loadImage or function() return 0 end
g_realMinimap.loadRegion = g_realMinimap.loadRegion or function() return 0 end
g_realMinimap.enableRegion = g_realMinimap.enableRegion or noop
g_realMinimap.disableRegion = g_realMinimap.disableRegion or noop
g_realMinimap.addWidget = g_realMinimap.addWidget or noop
g_realMinimap.removeWidget = g_realMinimap.removeWidget or noop
g_realMinimap.getHousePosition = g_realMinimap.getHousePosition or function() return {x = 0, y = 0, z = 7} end

if g_shaders then
  g_shaders.setupMapShader = g_shaders.setupMapShader or noop
  g_shaders.setupOutfitShader = g_shaders.setupOutfitShader or noop
  g_shaders.createFragmentShader = g_shaders.createFragmentShader or noop
end

if g_ui then
  local inputLockWidget
  local diagonalKeys = {}
  local callEscapeKey = false
  local callEnterKey = false
  g_ui.getCustomInputWidget = g_ui.getCustomInputWidget or function()
    if inputLockWidget and inputLockWidget.isDestroyed and inputLockWidget:isDestroyed() then
      inputLockWidget = nil
    end
    return inputLockWidget
  end
  g_ui.setInputLockWidget = g_ui.setInputLockWidget or function(widget)
    inputLockWidget = widget
  end
  g_ui.addDiagonalKey = g_ui.addDiagonalKey or function(keyCode)
    diagonalKeys[keyCode] = true
  end
  g_ui.removeDiagonalKey = g_ui.removeDiagonalKey or function(keyCode)
    diagonalKeys[keyCode] = nil
  end
  g_ui.isDiagonalKey = g_ui.isDiagonalKey or function(keyCode)
    return diagonalKeys[keyCode] == true
  end
  g_ui.setCallEscapeKey = g_ui.setCallEscapeKey or function(value)
    callEscapeKey = value
  end
  g_ui.setCallEnterKey = g_ui.setCallEnterKey or function(value)
    callEnterKey = value
  end
  g_ui.isUsedCallEscapeKey = g_ui.isUsedCallEscapeKey or function()
    return callEscapeKey
  end
  g_ui.getActionTimer = g_ui.getActionTimer or function()
    return 0
  end
end

if g_window then
  g_window.setUseNativeCursor = g_window.setUseNativeCursor or noop
end

if g_map then
  local limitEffects = 400
  g_map.getLimitEffects = g_map.getLimitEffects or function()
    return limitEffects
  end
  g_map.setLimitEffects = g_map.setLimitEffects or function(value)
    limitEffects = value
  end
  g_map.setUnlimitEffects = g_map.setUnlimitEffects or noop
  g_map.enableStackEffects = g_map.enableStackEffects or noop
  g_map.setArcDistance = g_map.setArcDistance or noop
  g_map.setArcOpacity = g_map.setArcOpacity or noop
  g_map.setArcStyle = g_map.setArcStyle or noop
  g_map.setShowMessageEnabled = g_map.setShowMessageEnabled or noop
  g_map.setTextureTextEnabled = g_map.setTextureTextEnabled or noop
  g_map.isVisiblePosition = g_map.isVisiblePosition or function()
    return true
  end
end

if g_game then
  local gameNoops = {
    'bestiaryMonsterData', 'bestiaryOverview', 'bestiarySearch',
    'cancelNextWalk', 'cancelPushAction', 'changeHirelingOutfit',
    'changePodiumOutfit', 'charmRemove', 'charmSelect', 'charmUnlock',
    'chooseRsa', 'closeContainerByItemId', 'closeSearchLocker',
    'dailyRewardConfirm', 'dailyRewardHistory', 'doDonateMap', 'doThing',
    'enableShowPrestigeTexture', 'enableTimerContainer', 'enableTimerInventory',
    'enableTimerUnused', 'highscore', 'invokeOnGameEnd', 'invokeOnLogout',
    'obtainContainer', 'openBosstiarySlots', 'openBosstiaryWindow',
    'openContainer', 'openCyclopedia', 'openDailyReward', 'preyHuntingAction',
    'processPendingGame', 'questTrackerFlags', 'quickLoot', 'quickLootArea',
    'readAnnouncement', 'redeemBattlePass', 'removeLootContainer',
    'removeObtainContainer', 'requestBattlePass', 'requestBlessings',
    'requestCharacterCheckInformations', 'requestCharacterInformation',
    'requestCharacterRequeriments', 'requestCharmData', 'requestCollectAll',
    'requestCyclopediaData', 'requestForgeHistory', 'requestHirelingOutfit',
    'requestHotkeyItems',
    'requestImbuementTracker', 'requestLockerItem', 'requestOfferDescription',
    'requestPixPrice', 'requestPixURL', 'requestPodiumData', 'requestResource',
    'requestSearchLocker', 'rerollBattlePassMission', 'resetAllCharm',
    'resetExperienceData', 'retrieveDisplayed', 'selectImbuementItem',
    'selectImbuementScroll', 'sellAllItems', 'sendAnnouncement',
    'sendAnnouncementAction', 'sendApplyWheelPoints', 'sendAutoAimList',
    'sendAwnserMatchFound', 'sendBanPrestigeArenaMap',
    'sendBosstiarySlotAction', 'sendCharacterAuctionConfirm',
    'sendClosePrestigeBattle', 'sendEditAnnouncement', 'sendEquipmentPreset',
    'sendExivaOptions', 'sendForgeConverter', 'sendForgeFusion',
    'sendForgeTransfer', 'sendGemAtelierAction', 'sendHirelingNameChange',
    'sendHouseAction', 'sendInspectionNormalObject', 'sendInspectionObject',
    'sendManagePrestigeArenaQueue', 'sendManagePrestigeEmblem',
    'sendMarketAcceptOffer', 'sendMarketAction', 'sendMarketCancelOffer',
    'sendMarketCreateOffer', 'sendMarketLeave', 'sendMonsterPodiumOutfit',
    'sendMonsterTracker', 'sendNPCTalk', 'sendOpenDestinyWheel',
    'sendPartyLootPrice', 'sendPartyLootType', 'sendPartyResetSession',
    'sendPollAnnouncement', 'sendPrestigeArenaLeaderboard',
    'sendRequestPrestigeArenaData', 'sendRequestPrestigeArenaHistory',
    'sendRequestPrestigeArenaLiveMatches', 'sendRequestPrestigeInspect',
    'sendTeleport', 'sendUpdateAutoAimList', 'sendVipGroup',
    'sendWatchPrestigeArenaLiveMatch', 'sendWeaponProficiencyAction',
    'sendWeaponProficiencyApply', 'setCamViewerSpeed', 'setDead',
    'setFramingTarget', 'setHighlightingTarget', 'setLootValueState',
    'setRsa', 'setStringVersion', 'setWalkProtection', 'sortContainer',
    'stashWithdraw', 'stowItem', 'stowItemContainerStack',
    'updateCharacterTitle', 'updateLootContainer', 'updateLootWhiteList',
    'voteAnnouncement'
  }
  for _, name in ipairs(gameNoops) do
    g_game[name] = g_game[name] or noop
  end

  local gameFalse = {
    'canUseExivaRestrictions', 'getCanChangePvpFrameOption',
    'isNpcOrSafeFight', 'isOfficialTibia', 'isRecord', 'playerInGroup'
  }
  for _, name in ipairs(gameFalse) do
    g_game[name] = g_game[name] or function() return false end
  end

  g_game.findItems = g_game.findItems or function() return {} end
  g_game.findPlayerItem = g_game.findPlayerItem or function() return nil end
  g_game.getBoostedAreas = g_game.getBoostedAreas or function() return {} end
  g_game.getCamViewerSpeed = g_game.getCamViewerSpeed or function() return 1 end
  g_game.getClientProtocolVersion = g_game.getClientProtocolVersion or function()
    return g_game.getProtocolVersion and g_game.getProtocolVersion() or 0
  end
  g_game.getHourExperience = g_game.getHourExperience or function() return 0 end
  g_game.getHourRawExperience = g_game.getHourRawExperience or function() return 0 end
  g_game.getMapBoostPrice = g_game.getMapBoostPrice or function() return 0 end
  g_game.getRecordCurrentFrame = g_game.getRecordCurrentFrame or function() return 0 end
  g_game.getRecordDuration = g_game.getRecordDuration or function() return 0 end
  g_game.getRsa = g_game.getRsa or function() return nil end
  g_game.getSupportedClients = g_game.getSupportedClients or function() return {} end
  g_game.getUnsortedCyclopediaItems = g_game.getUnsortedCyclopediaItems or function() return {} end
  g_game.getVocationName = g_game.getVocationName or function() return '' end
  g_game.getVocationNameBase = g_game.getVocationNameBase or function() return '' end
end

g_client.clearHudConfigs = g_client.clearHudConfigs or noop
g_client.addHudConfig = g_client.addHudConfig or noop
g_client.updateHudPath = g_client.updateHudPath or noop
g_client.setMissileAlpha = g_client.setMissileAlpha or noop
g_client.setEffectAlpha = g_client.setEffectAlpha or noop
g_client.setIgnoreSpecialEffects = g_client.setIgnoreSpecialEffects or noop

local function moduleProxy(moduleName)
  return setmetatable({}, {
    __index = function(_, key)
      local module = package.loaded[moduleName]
      return module and module[key]
    end,
    __newindex = function(proxy, key, value)
      local module = package.loaded[moduleName]
      if module then
        module[key] = value
      else
        rawset(proxy, key, value)
      end
    end
  })
end

m_interface = m_interface or moduleProxy('game_interface')
m_settings = m_settings or moduleProxy('client_settings')

-- root widget
rootWidget = g_ui.getRootWidget()
rootWidget:insertLuaCall("onGeometryChange")
modules = package.loaded

-- G is used as a global table to save variables in memory between reloads
G = G or {}

-- @}

-- @docfuncs @{

function scheduleEvent(callback, delay, print)
  local desc = "lua"
  local info = debug.getinfo(2, "Sl")
  if info then
    desc = info.short_src .. ":" .. info.currentline
  end
  local event = g_dispatcher.scheduleEvent(desc, callback, delay, print)
  -- must hold a reference to the callback, otherwise it would be collected
  event._callback = callback
  return event
end

function addEvent(callback, front)
  local desc = "lua"
  local info = debug.getinfo(2, "Sl")
  if info then
    desc = info.short_src .. ":" .. info.currentline
  end
  local event = g_dispatcher.addEvent(desc, callback, front)
  -- must hold a reference to the callback, otherwise it would be collected
  event._callback = callback
  return event
end

function cycleEvent(callback, interval)
  local desc = "lua"
  local info = debug.getinfo(2, "Sl")
  if info then
    desc = info.short_src .. ":" .. info.currentline
  end
  local event = g_dispatcher.cycleEvent(desc, callback, interval)
  -- must hold a reference to the callback, otherwise it would be collected
  event._callback = callback
  return event
end

function periodicalEvent(eventFunc, conditionFunc, delay, autoRepeatDelay)
  delay = delay or 30
  autoRepeatDelay = autoRepeatDelay or delay

  local func
  func = function()
    if conditionFunc and not conditionFunc() then
      func = nil
      return
    end
    eventFunc()
    scheduleEvent(func, delay)
  end

  scheduleEvent(function()
    func()
  end, autoRepeatDelay)
end

function removeEvent(event)
  if event then
    event:cancel()
    event._callback = nil
  end
end

-- @}
