---------------------------
-- Lua code author: R1ck --
-- Company: VICTOR HUGO PERENHA - JOGOS ON LINE --
---------------------------

Trackers = {}
Trackers.__index = Trackers

bossTrackerWindow = nil
bestiaryTrackerWindow = nil
imbuementTrackerWindow = nil

local openWindowEvent = nil


function init()
	connect(g_game, {
		onMonsterTrackerData = Trackers.onMonsterTrackerData,
		onUpdateImbuementTracker = ImbuementTracker.onReceiveData,
		onGameStart = online,
		onGameEnd = offline
	})

	-- init boss tracker
	bossTrackerWindow = g_ui.loadUI('styles/boss_tracker', m_interface.getRightPanel())
	local scrollbar = bossTrackerWindow:getChildById('miniwindowScrollBar')
	scrollbar:mergeStyle({ ['$!on'] = { }})

	local redirectButton = bossTrackerWindow:getRedirectButton()
	redirectButton:setTooltip("Open the entry of a boss in the Bossitary to add it to this list")

	local sortButton = bossTrackerWindow:getExtraButton()
	sortButton:setTooltip("Show sort options")

	bossTrackerWindow:setup()
	bossTrackerWindow:close()

	-- init bestiary tracker
	bestiaryTrackerWindow = g_ui.loadUI('styles/bestiary_tracker', m_interface.getRightPanel())
	local scrollbar = bestiaryTrackerWindow:getChildById('miniwindowScrollBar')
	scrollbar:mergeStyle({ ['$!on'] = { }})

	local redirectButton = bestiaryTrackerWindow:getRedirectButton()
	redirectButton:setTooltip("Open the entry of a boss in the Bestiary to add it to this list")

	local sortButton = bestiaryTrackerWindow:getExtraButton()
	sortButton:setTooltip("Show sort options")

	bestiaryTrackerWindow:setup()
	bestiaryTrackerWindow:close()

	-- init imbuement tracker
	imbuementTrackerWindow = g_ui.loadUI('styles/imbui_tracker', m_interface.getRightPanel())
	local scrollbar = imbuementTrackerWindow:getChildById('miniwindowScrollBar')
	scrollbar:mergeStyle({ ['$!on'] = { }})

	local sortButton = imbuementTrackerWindow:getExtraButton()
	sortButton:setTooltip("Click here to configure the Imbuement Tracker.")

	imbuementTrackerWindow:setup()
	imbuementTrackerWindow:close()
end

function terminate()
	BestiaryTracker.cancelRender()
	disconnect(g_game, {
		onMonsterTrackerData = Trackers.onMonsterTrackerData,
		onUpdateImbuementTracker = ImbuementTracker.onReceiveData,
		onGameStart = online,
		onGameEnd = offline
	})

end

function online()
	local benchmark = g_clock.millis()
	ImbuementTracker.online()
	if g_game.isOnline() then
		g_game.openBosstiaryWindow()
	end
	consoleln("Trackers loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function offline()
	BestiaryTracker.cancelRender()
	ImbuementTracker.offline()
	BossTracker.resetWindow()
	if openWindowEvent then
		removeEvent(openWindowEvent)
		openWindowEvent = nil
	end
end

function Trackers.onMonsterTrackerData(trackerType, monsterData)
	if trackerType == 0 then
		BestiaryTrackerList = monsterData
		if KillPerf then
			KillPerf.measure("BestiaryTracker.render", BestiaryTracker.showTrackerData)
		else
			BestiaryTracker.showTrackerData()
		end
	else
		BossTrackerList = monsterData
		if KillPerf then
			KillPerf.measure("BossTracker.render", BossTracker.showTrackerData)
		else
			BossTracker.showTrackerData()
		end
	end
end

function toggleBossTracker()
	if bossTrackerWindow:isVisible() then
		bossTrackerWindow:close()
	else
		bossTrackerWindow:open()
		if m_interface.addToPanels(bossTrackerWindow) then
			bossTrackerWindow:getParent():moveChildToIndex(bossTrackerWindow, #bossTrackerWindow:getParent():getChildren())
			BossTracker.initSortFields()
		end
		-- Rendering is skipped while the window is closed, so it has to happen on every open,
		-- not only the first one that adds the window to a panel.
		BossTracker.showTrackerData()
	end
end

function toggleBestiaryTracker()
	if bestiaryTrackerWindow:isVisible() then
		bestiaryTrackerWindow:close()
    	modules.game_sidebuttons.setButtonVisible("bestiaryTrackerWidget", false)
	else
		bestiaryTrackerWindow:open()
		if m_interface.addToPanels(bestiaryTrackerWindow) then
			bestiaryTrackerWindow:getParent():moveChildToIndex(bestiaryTrackerWindow, #bestiaryTrackerWindow:getParent():getChildren())
			BestiaryTracker.initSortFields()
    		modules.game_sidebuttons.setButtonVisible("bestiaryTrackerWidget", true)
		end
		-- Rendering is skipped while the window is closed, so it has to happen on every open,
		-- not only the first one that adds the window to a panel.
		BestiaryTracker.showTrackerData()
	end
end

function toggleImbuementTracker()
	if imbuementTrackerWindow:isVisible() then
		imbuementTrackerWindow:close()
    	modules.game_sidebuttons.setButtonVisible("imbuementTrackerWidget", false)
		g_game.imbuementDurations(false)
	else
		imbuementTrackerWindow:open()
		if m_interface.addToPanels(imbuementTrackerWindow) then
			imbuementTrackerWindow:getParent():moveChildToIndex(imbuementTrackerWindow, #imbuementTrackerWindow:getParent():getChildren())
			ImbuementTracker.initSortFields()
			g_game.imbuementDurations(true)
			openWindowEvent = scheduleEvent(showTracker, 50)
		end
	end
end

function showTracker()
	ImbuementTracker.showTrackerData()
	modules.game_sidebuttons.setButtonVisible("imbuementTrackerWidget", true)
end

function moveTracker(type, panel, height, minimized)
  local windowByType = {
    ["bestiaryTracker"] = bestiaryTrackerWindow,
    ["bosstiaryTracker"] = bossTrackerWindow,
    ["imbuementTracker"] = imbuementTrackerWindow
  }
  local window = windowByType[type]

  window:setParent(panel)
  window:open()

  if minimized then
    window:setHeight(height)
    window:minimize()
  else
    window:maximize()
    window:setHeight(height)
  end

  if type == "imbuementTracker" then
    ImbuementTracker.initSortFields()
    g_game.doThing(false)
    g_game.imbuementDurations(true)
    g_game.doThing(true)
    if not minimized then
      openWindowEvent = scheduleEvent(showTracker, 50)
    end
  end

  return window
end

function onPlayerUnload()
	BestiaryTracker.onLogout()
	BossTracker.onLogout()
end

function onPlayerLoad(bestiaryTrackerWidgetOptions, bossTrackerWidgetOptions)
	if bestiaryTrackerWidgetOptions then
		BestiaryTracker.onLogin(bestiaryTrackerWidgetOptions)
	end

	if bossTrackerWidgetOptions then
		BossTracker.onLogin(bossTrackerWidgetOptions)
	end
end

function reopenImbuementPanel()
	if imbuementTrackerWindow:isVisible() then
		g_game.doThing(false)
		g_game.imbuementDurations(true)
		g_game.doThing(true)
	end
end
