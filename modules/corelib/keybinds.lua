KeyBinds = {}
KeyBind = {}

local hotkeys = {}
local walkBinds = { "Go North", "Go South", "Go East", "Go West" }

local nextExecution = 0
function canPerformAction(ignoreRoot)
  if ignoreRoot == nil then
    ignoreRoot = false
  end

  if not ignoreRoot then
    if not rootWidget:getChildById("gameRootPanel"):isFocused() then
      return false
    end
  end

  if nextExecution > g_clock.millis() then
    return false
  end

  nextExecution = g_clock.millis() + 10
  return true
end

local function ifCanPerformAction(func)
  return function()
    if canPerformAction() then func() end
  end
end

local function toggleOption(optionKey)
  return ifCanPerformAction(function() 
    m_settings.toggleOption(optionKey) 
  end)
end

KeyBinds.Hotkeys = {
    ["Action Bar"] = {
      ["Show/hide Bottom Action Bar 1"] = {
        jsonName = "ToggleActionBar1",
        bindKeyDown = toggleOption("actionBarShowBottom1"),
      },
      ["Show/hide Bottom Action Bar 2"] = {
        jsonName = "ToggleActionBar2",
        bindKeyDown = toggleOption("actionBarShowBottom2"),
      },
      ["Show/hide Bottom Action Bar 3"] = {
        jsonName = "ToggleActionBar3",
        bindKeyDown = toggleOption("actionBarShowBottom3"),
      },
      ["Show/hide Bottom Action Bars"] = {
        jsonName = "ToggleBottomActionBars",
        bindKeyDown = toggleOption("allActionBar13"),
      },
      ["Show/hide Left Action Bar 1"] = {
        jsonName = "ToggleLeftActionBar1",
        bindKeyDown = toggleOption("actionBarShowLeft1"),
      },
      ["Show/hide Left Action Bar 2"] = {
        jsonName = "ToggleLeftActionBar2",
        bindKeyDown = toggleOption("actionBarShowLeft2"),
      },
      ["Show/hide Left Action Bar 3"] = {
        jsonName = "ToggleLeftActionBar3",
        bindKeyDown = toggleOption("actionBarShowLeft3"),
      },
      ["Show/hide Left Action Bars"] = {
        jsonName = "ToggleLeftActionBars",
        bindKeyDown = toggleOption("allActionBar46"),
      },
      ["Show/hide Right Bar 1"] = {
        jsonName = "ToggleRightActionBar1",
        bindKeyDown = toggleOption("actionBarShowRight1"),
      },
      ["Show/hide Right Bar 2"] = {
        jsonName = "ToggleRightActionBar2",
        bindKeyDown = toggleOption("actionBarShowRight2"),
      },
      ["Show/hide Right Bar 3"] = {
        jsonName = "ToggleRightActionBar3",
        bindKeyDown = toggleOption("actionBarShowRight3"),
      },
      ["Show/hide Right Bars"] = {
        jsonName = "ToggleRightActionBars",
        bindKeyDown = toggleOption("allActionBar79"),
      },
    },
    ["Battle List"] = {
      ["Attack Next Target"] = {
        jsonName = "AttackNextTarget",
        bindKeyDown = function() if nextExecution > g_clock.millis() then return end nextExecution = g_clock.millis() + 50 modules.game_battle.chooseNextCreature() end,
      },
      ["Attack Previous Target"] = {
        jsonName = "AttackPreviousTarget",
        bindKeyDown = function() if nextExecution > g_clock.millis() then return end nextExecution = g_clock.millis() + 50 modules.game_battle.choosePrevCreature() end,
      },
    },
    ["Chat Channel"] = {
      ["Close Current Channel"] = {
        jsonName = "CloseCurrentChannel",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_console.removeCurrentTab() end,
      },
      ["Next Channel"] = {
        jsonName = "NextChannel",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_console.nextChannel() end,
      },
      ["Open Channel List"] = {
        jsonName = "OpenChannelList",
        bindKeyDown = function() if not canPerformAction() then return end g_game.requestChannels() end,
      },
      ["Open Help Channel"] = {
        jsonName = "OpenHelpChannel",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_console.openHelp() end,
      },
      ["Open Loot Channel"] = {
        jsonName = "OpenLootChannel",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_console.openLootChannel() end,
      },
      ["Open NPC Channel"] = {
        jsonName = "OpenNPCChannel",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_console.openNPCChannel() end,
      },
      ["Open Server Channel"] = {
        jsonName = "OpenServerChannel",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_console.openServerChannel() end,
      },
      ["Previous Channel"] = {
        jsonName = "PreviousChannel",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_console.prevChannel() end,
      },
      ["Show Default Channel"] = {
        jsonName = "ShowDefaultChannel",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_console.selectDefault() end,
      },
    },
    ["Chat Mode"] = {
      ["Set To Chat Off"] = {
        jsonName = "ChatModeOff",
        bindKeyDown = function() if not canPerformAction() or modules.game_interface.isInternalLocked() then return end modules.game_console.toggleChat() end,
      },
      ["Set To Chat On"] = {
        jsonName = "ChatModeOn",
        bindKeyDown = function() if not canPerformAction() or modules.game_interface.isInternalLocked() then return end modules.game_console.toggleChat() end,
      },
      ["Set To Chat On*"] = {
        jsonName = "ChatModeTemporaryOnEnter",
        bindKeyDown = function()
          if not g_game.isOnline() then
            return
          end

          if nextExecution > g_clock.millis() or modules.game_interface.isInternalLocked() then
            return
          end
  
          nextExecution = g_clock.millis() + 50
          modules.game_console.onEnterPressed()
        end,
      },
    },
    ["Chat Text"] = {
      ["Copy to clipboard"] = {
        jsonName = "Copy",
        bindKeyDown = function() end,
      },
      ["Select All"] = {
        jsonName = "SelectAll",
        bindKeyPress = function(c, k, ticks) if not canPerformAction() then return end modules.game_console.clearOrSelectText() end,
      },
    },
    ["Chat"] = {
      ["Send current chat line"] = {
        jsonName = "PressEnterInChat",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_console.sendCurrentMessage(true) end,
      },
      ["Show/hide Show Server messages in current channel"] = {
        jsonName = "ToggleShowServermessagesInCurrentChannel",
        bindKeyDown = function() end,
      },
    },
    ["Combat Mode"] = {
      ["Set to Balanced"] = {
        jsonName = "SetCombatModeBalanced",
        bindKeyDown = function() g_game.setFightMode(FightBalanced) end,
      },
      ["Set to Defensise"] = {
        jsonName = "SetCombatModeDefensive",
        bindKeyDown = function() g_game.setFightMode(FightDefensive) end,
      },
      ["Set to Offensive"] = {
        jsonName = "SetCombatModeOffensive",
        bindKeyDown = function() g_game.setFightMode(FightOffensive) end,
      },
    },
    ["Combat"] = {
      ["Toggle Chase Mode"] = {
        jsonName = "ToggleChaseOpponents",
        bindKeyDown = function() local chaseMode = g_game.getChaseMode(); g_game.setChaseMode(chaseMode == ChaseOpponent and DontChase or ChaseOpponent) end,
      },
      ["Toggle Secure Mode"] = {
        jsonName = "ToggleSecureMode",
        bindKeyDown = function() g_game.setSafeFight(not g_game.isSafeFight()) end,
      },
    },
    ["Containers"] = {
      ["Toggle Manual Sort Mode"] = {
        jsonName = "ToggleManualSortMode",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_containers.toggleManualSort() end,
      },
    },
    ["Dialogs"] = {
      ["Open Bugreport"] = {
        jsonName = "Bugreport",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_bugreport.show(nil, 3) end,
      },
      ["Open Compendium"] = {
        jsonName = "ShowCompendium",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_compendium.show() end,
      },
      ["Open Cyclopedia - Bestiary"] = {
        jsonName = "ShowBestiary",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_cyclopedia.toggleRedirect("Bestiary") end,
      },
      ["Open Cyclopedia - Character"] = {
        jsonName = "ShowCharacterInfo",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_cyclopedia.toggleRedirect("Character") end,
      },
      ["Open Cyclopedia - Charms"] = {
        jsonName = "ShowCharms",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_cyclopedia.toggleRedirect("Charm") end,
      },
      ["Open Cyclopedia - Items"] = {
        jsonName = "ShowItemInformation",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_cyclopedia.toggleRedirect("Items") end,
      },
      ["Open Cyclopedia - Map"] = {
        jsonName = "ShowCyclopediaMap",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_cyclopedia.toggleRedirect("Map") end,
      },
      ["Open Exaltation Forge"] = {
        jsonName = "OpenExaltationForgeDialog",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_forge:toggle() end,
      },
      ["Open Exiva Options"] = {
        jsonName = "ShowExivaOptions",
        bindKeyDown = function() end,
      },
      ["Open Ignore List"] = {
        jsonName = "ShowIgnorelist",
        bindKeyDown = function()if not canPerformAction() then return end modules.game_console.Communication:onClickIgnoreButton() end,
      },
      ["Open Manage Containers"] = {
        jsonName = "OpenManageLootContainer",
        bindKeyDown = function() end,
      },
      ["Open Options"] = {
        jsonName = "ShowOptions",
        bindKeyDown = function()if not canPerformAction() then return end m_settings.openOptions() end,
      },
      ["Open Options - Custom Hotkeys"] = {
        jsonName = "ShowOptionsHotkeys",
        bindKeyDown = function()if not canPerformAction() then return end m_settings.toggleHotkeys() end,
      },
      ["Open Prey Dialog"] = {
        jsonName = "ShowPrey",
        bindKeyDown = function()if not canPerformAction() then return end modules.game_prey:show() end,
      },
      ["Open Questlog"] = {
        jsonName = "ShowQuestlog",
        bindKeyDown = function()if not canPerformAction() then return end modules.game_questlog:toggle() end,
      },
      ["Open Reward Wall"] = {
        jsonName = "OpenRewardWall",
        bindKeyDown = function()if not canPerformAction() then return end g_game.openDailyReward() end,
      },
      ["Open Social - Assemble Team"] = {
        jsonName = "AssembleTeam",
        bindKeyDown = function() end,
      },
      ["Open Social - Badges"] = {
        jsonName = "Badges",
        bindKeyDown = function() end,
      },
      ["Open Social - Friend List"] = {
        jsonName = "FriendList",
        bindKeyDown = function() end,
      },
      ["Open Social - Friend Config"] = {
        jsonName = "FriendsConfiguration",
        bindKeyDown = function() end,
      },
      ["Open Social - Friend Invitations"] = {
        jsonName = "FriendInvites",
        bindKeyDown = function() end,
      },
      ["Open Social - Friend Search"] = {
        jsonName = "AccountSearch",
        bindKeyDown = function() end,
      },
      ["Open Social - Join Team"] = {
        jsonName = "JoinTeam",
        bindKeyDown = function() end,
      },
      ["Open Wheel of Destiny"] = {
        jsonName = "OpenOwnSkillWheel",
        bindKeyDown = function()if not canPerformAction() then return end modules.game_wheel:toggle() end,
      },
    },
    ["Loot"] = {
      ["Quick Loot Nearby Corpses"] = {
        jsonName = "QuickLootAreaAtPlayer",
        bindKeyDown = function() if not canPerformAction() then return end g_game.quickLootArea() end,
      },
    },
    ["Minimap"] = {
      ["Center"] = {
        jsonName = "MinimapCenter",
        bindKeyDown = function() 
          if not canPerformAction() then return end

          local minimapWidget = modules.game_minimap.minimapWidget
          if minimapWidget then
            minimapWidget:center()
          end
        end,
      },
      ["One Floor Down"] = {
        jsonName = "MinimapFloorDown",
        bindKeyDown = function()
          if not canPerformAction() then return end
          local minimapWidget = modules.game_minimap.minimapWidget
          if minimapWidget then
            minimapWidget:floorDown(1)
          end
        end,
      },
      ["One Floor Up"] = {
        jsonName = "MinimapFloorUp",
        bindKeyDown = function()
          if not canPerformAction() then return end
          local minimapWidget = modules.game_minimap.minimapWidget
          if minimapWidget then
            minimapWidget:floorUp(1)
          end
        end,
      },
      ["Scroll East"] = {
        jsonName = "MinimapScrollEast",
        bindKeyPress = function()
          if not canPerformAction() then return end
          local minimapWidget = modules.game_minimap.minimapWidget
          if minimapWidget then
            minimapWidget:move(-1,0)
          end
        end,
      },
      ["Scroll North"] = {
        jsonName = "MinimapScrollNorth",
        bindKeyPress = function()
          if not canPerformAction() then return end
          local minimapWidget = modules.game_minimap.minimapWidget
          if minimapWidget then
            minimapWidget:move(0,1)
          end
        end,
      },
      ["Scroll South"] = {
        jsonName = "MinimapScrollSouth",
        bindKeyPress = function()
          if not canPerformAction() then return end
          local minimapWidget = modules.game_minimap.minimapWidget
          if minimapWidget then
            minimapWidget:move(0,-1)
          end
        end,
      },
      ["Scroll West"] = {
        jsonName = "MinimapScrollWest",
        bindKeyPress = function()
          if not canPerformAction() then return end
          local minimapWidget = modules.game_minimap.minimapWidget
          if minimapWidget then
            minimapWidget:move(1,0)
          end
        end,
      },
      ["Zoom In"] = {
        jsonName = "MinimapZoomIn",
        bindKeyDown = function()
          if not canPerformAction() then return end
          local minimapWidget = modules.game_minimap.minimapWidget
          if minimapWidget then
            minimapWidget:zoomIn()
          end
        end,
      },
      ["Zoom Out"] = {
        jsonName = "MinimapZoomOut",
        bindKeyDown = function()
          if not canPerformAction() then return end
          local minimapWidget = modules.game_minimap.minimapWidget
          if minimapWidget then
            minimapWidget:zoomOut()
          end
        end,
      },
      ["Show"] = {
        jsonName = "MinimapShow",
        bindKeyDown = function()if not canPerformAction() then return end modules.game_minimap:toggle() end,
      },
    },
    ["Helper"] = {
      ["Enable/Disable Helper"] = {
        jsonName = "HelperStatus",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_helper:botStatus() end,
      },
      ["Enable/Disable Auto Target"] = {
        jsonName = "HelperTarget",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_helper.toggleAutoTarget() end,
      },
      ["Enable/Disable Magic Shooter"] = {
        jsonName = "HelperShooter",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_helper.toggleMagicShooter() end,
      },
      ["Change Shooter Preset"] = {
        jsonName = "HelperPreset",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_helper.toggleShooterPreset() end,
      },
      ["Enable/Disable Target and Magic Shooter"] = {
        jsonName = "HelperTargetShooter",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_helper.toggleMagicShooter() modules.game_helper.toggleAutoTarget() end,
      },
      ["Show Helper"] = {
        jsonName = "ShowHelper",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_helper.toggle() end,
      },
    },
    ["Misc."] = {
      ["Activate Lenshelp"] = {
        jsonName = "ShowLenshelp",
        bindKeyDown = function() end,
      },
      ["Allow/disallow all character to Exiva me"] = {
        jsonName = "ToggleExiaAllowAll",
        bindKeyDown = function() end,
      },
      ["Change Character"] = {
        jsonName = "ChangeCharacter",
        bindKeyDown = function()if not canPerformAction() then return end modules.client_entergame.EnterGame.openWindow() end,
      },
      ["Clear oldest message from Game Window"] = {
        jsonName = "ClearOldestMessage",
        bindKeyDown = function()if not canPerformAction() then return end g_map.cleanTexts() modules.game_textmessage.clearMessages() end,
      },
      ["Customise Character"] = {
        jsonName = "RequestOutfitsFromServer",
        bindKeyDown = function() if not canPerformAction() then return end g_game.requestOutfit(0) end,
      },
      ["Logout"] = {
        jsonName = "Logout",
        bindKeyDown = function()if not canPerformAction() then return end m_interface.tryLogout(false) end,
      },
      ["Next Hotkey Preset"] = {
        jsonName = "NextHotkeyPreset",
        bindKeyDown = function() if not canPerformAction() then return end m_settings.toggleNextPreset() end,
      },
      ["Previous Hotkey Preset"] = {
        jsonName = "PreviousHotkeyPreset",
        bindKeyDown = function() if not canPerformAction() then return end m_settings.togglePreviousPreset() end,
      },
      ["Take Screenshot"] = {
        jsonName = "TakeScreenshot",
        bindKeyDown = function() if not canPerformAction() then return end m_settings.takeScreenshot(false) end,
      },
      ["Take Map Screenshot"] = {
        jsonName = "TakeMapScreenshot",
        bindKeyDown = function() if not canPerformAction() then return end m_settings.takeScreenshot(true) end,
      },
    },
    ["Movement"] = {
      ["Go East"] = {
        jsonName = "GoEast",
        dontBindChatoff = true,
        bindKeyDown = function(c, k)
          if modules.game_walking.isBlockWalk() then
            return
          end
          if g_keyboard.getModifiers() == KeyboardNoModifier then
            modules.game_walking.changeWalkDir(East)
          end
        end,
        bindKeyUp = function() modules.game_walking.changeWalkDir(East, true) end,
        bindKeyPress = function(c, k, ticks)
          if modules.game_walking.isBlockWalk() then
            return
          end
          modules.game_walking.smartWalk(East, ticks)
        end,
      },

      ["Go North"] = {
        jsonName = "GoNorth",
        dontBindChatoff = true,
        bindKeyDown = function(c, k)
          if modules.game_walking.isBlockWalk() then
            return
          end
          if g_keyboard.getModifiers() == KeyboardNoModifier then
            modules.game_walking.changeWalkDir(North)
          end
        end,
        bindKeyUp = function() modules.game_walking.changeWalkDir(North, true) end,
        bindKeyPress = function(c, k, ticks)
          if modules.game_walking.isBlockWalk() then
            return
          end
          modules.game_walking.smartWalk(North, ticks)
        end,
      },

      ["Go West"] = {
        jsonName = "GoWest",
        dontBindChatoff = true,
        bindKeyDown = function(c, k)
          if modules.game_walking.isBlockWalk() then
            return
          end
          if g_keyboard.getModifiers() == KeyboardNoModifier then
            modules.game_walking.changeWalkDir(West)
          end
        end,
        bindKeyUp = function() modules.game_walking.changeWalkDir(West, true) end,
        bindKeyPress = function(c, k, ticks)
          if modules.game_walking.isBlockWalk() then
            return
          end
          modules.game_walking.smartWalk(West, ticks)
        end,
      },

      ["Go South"] = {
        jsonName = "GoSouth",
        dontBindChatoff = true,
        bindKeyDown = function(c, k)
          if modules.game_walking.isBlockWalk() then
            return
          end
          if g_keyboard.getModifiers() == KeyboardNoModifier then
            modules.game_walking.changeWalkDir(South)
          end
        end,
        bindKeyUp = function() modules.game_walking.changeWalkDir(South, true) end,
        bindKeyPress = function(c, k, ticks)
          if modules.game_walking.isBlockWalk() then
            return
          end
          modules.game_walking.smartWalk(South, ticks)
        end,
      },

      ["Go North-East"] = {
        jsonName = "GoNorthEast",
        dontBindChatoff = true,
        bindKeyDown = function(c, k)
          if modules.game_walking.isBlockWalk() then
            return
          end
          if g_keyboard.getModifiers() == KeyboardNoModifier then
            modules.game_walking.changeWalkDir(NorthEast)
          end
        end,
        bindKeyUp = function() modules.game_walking.changeWalkDir(NorthEast, true) end,
        bindKeyPress = function(c, k, ticks)
          if modules.game_walking.isBlockWalk() then
            return
          end
          modules.game_walking.smartWalk(NorthEast, ticks)
        end,
      },

      ["Go North-West"] = {
        jsonName = "GoNorthWest",
        dontBindChatoff = true,
        bindKeyDown = function(c, k)
          if modules.game_walking.isBlockWalk() then
            return
          end
          if g_keyboard.getModifiers() == KeyboardNoModifier then
            modules.game_walking.changeWalkDir(NorthWest)
          end
        end,
        bindKeyUp = function() modules.game_walking.changeWalkDir(NorthWest, true) end,
        bindKeyPress = function(c, k, ticks)
          if modules.game_walking.isBlockWalk() then
            return
          end
          modules.game_walking.smartWalk(NorthWest, ticks)
        end,
      },

      ["Go South-East"] = {
        jsonName = "GoSouthEast",
        dontBindChatoff = true,
        bindKeyDown = function(c, k)
          if modules.game_walking.isBlockWalk() then
            return
          end
          if g_keyboard.getModifiers() == KeyboardNoModifier then
            modules.game_walking.changeWalkDir(SouthEast)
          end
        end,
        bindKeyUp = function() modules.game_walking.changeWalkDir(SouthEast, true) end,
        bindKeyPress = function(c, k, ticks)
          if modules.game_walking.isBlockWalk() then
            return
          end
          modules.game_walking.smartWalk(SouthEast, ticks)
        end,
      },

      ["Go South-West"] = {
        jsonName = "GoSouthWest",
        dontBindChatoff = true,
        bindKeyDown = function(c, k)
          if modules.game_walking.isBlockWalk() then
            return
          end
          if g_keyboard.getModifiers() == KeyboardNoModifier then
            modules.game_walking.changeWalkDir(SouthWest)
          end
        end,
        bindKeyUp = function() modules.game_walking.changeWalkDir(SouthWest, true) end,
        bindKeyPress = function(c, k, ticks)
          if modules.game_walking.isBlockWalk() then
            return
          end

          modules.game_walking.smartWalk(SouthWest, ticks)
        end,
      },
  
      ["Mount/dismount"] = {
        jsonName = "ToggleMounted",
        bindKeyDown = function(c, k, ticks)if not canPerformAction() then return end modules.game_playermount.toggleMount() end,
      },
      ["Stop All Actions"] = {
        jsonName = "StopPlayer",
        bindKeyDown = function() if not canPerformAction() or g_ui.isUsedCallEscapeKey() then return end m_interface.cancelAll() end,
      },
    },
    ["PvP Mode"] = {
      ["Set to Dove"] = {
        jsonName = "SetPvPModeDove",
        bindKeyDown = function() end,
      },
      ["Set to Red Fist"] = {
        jsonName = "SetPvPModeRedFist",
        bindKeyDown = function() end,
      },
      ["Set to White Hand"] = {
        jsonName = "SetPvPModeWhiteHand",
        bindKeyDown = function() end,
      },
      ["Set to Yellow Hand"] = {
        jsonName = "SetPvPModeYellowHand",
        bindKeyDown = function() end,
      },
    },
    ["Sound"] = {
      ["Mute/unmute"] = {
        jsonName = "ToggleSound",
        bindKeyDown = function() end,
      },
    },
    ["UI"] = {
      ["Show/hide Creature Names and Bars"] = {
        jsonName = "ToggleCreatureHudsVisible",
        bindKeyDown = function()if not canPerformAction() then return end m_settings:toggleDisplays() end,
      },
      ["Show/hide FPS / Lag indicator"] = {
        jsonName = "ToggleFPSLagIndicator",
        bindKeyDown = function()if not canPerformAction() then return end modules.game_stats:show() end,
      },
      ["Toggle Fullscreen"] = {
        jsonName = "ToggleFullscreen",
        bindKeyDown = function() if not canPerformAction() then return end g_window.setFullscreen(not g_window.isFullscreen()) end,
      },
    },
    ["Windows"] = {
      ["Open secondary battle list"] = {
        jsonName = "OpenSecondaryBattleList",
        bindKeyDown = function()if not canPerformAction() then return end modules.game_battle:addBattleWindow() end,
      },
      ["Show/hide VIP list"] = {
        jsonName = "ToggleVipWidget",
        bindKeyDown = function()if not canPerformAction() then return end modules.game_viplist.toggle() end,
      },
      ["Show/hide XP analyser"] = {
        jsonName = "ToggleXPAnalyserWidget",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_analyser.toggleAnalysers("xpButton") end,
      },
      ["Show/hide analytics selector"] = {
        jsonName = "ToggleAnalyticsSelectorWidget",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_analyser:toggle() end,
      },
      ["Show/hide battle list"] = {
        jsonName = "ToggleBattlelist",
        bindKeyDown = function()if not canPerformAction() then return end modules.game_battle.toggle() end,
      },
      ["Show/hide bestiary tracker"] = {
        jsonName = "ToggleBestiaryTrackerWidget",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_cyclopedia.toggleTracker() end,
      },
      ["Show/hide boss cooldowns"] = {
        jsonName = "ToggleBossCooldownsWidget",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_analyser.toggleAnalysers("bossButton") end,
      },
      ["Show/hide bosstiary tracker"] = {
        jsonName = "ToggleBosstiaryTrackerWidget",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_trackers.toggleBossTracker() end,
      },
      ["Show/hide drop tracker"] = {
        jsonName = "ToggleLootTrackerWidget",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_analyser.toggleAnalysers("dropButton") end,
      },
      ["Show/hide hunting analyser"] = {
        jsonName = "ToggleHuntingSessionAnalyserWidget",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_analyser.toggleAnalysers("huntingButton") end,
      },
      ["Show/hide imbuement tracker"] = {
        jsonName = "ImbuementTrackerWidget",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_trackers.toggleImbuementTracker() end,
      },
      ["Show/hide impact analyser"] = {
        jsonName = "ToggleImpactAnalyserWidget",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_analyser.toggleAnalysers("impactButton") end,
      },
      ["Show/hide input analyser"] = {
        jsonName = "ToggleDamageInputAnalyserWidget",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_analyser.toggleAnalysers("damageButton") end,
      },
      ["Show/hide loot analyser"] = {
        jsonName = "ToggleLootAnalyserWidget",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_analyser.toggleAnalysers("lootButton") end,
      },
      ["Show/hide party hunt analyser"] = {
        jsonName = "PartyHuntAnalyserWidget",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_analyser.toggleAnalysers("partyButton") end,
      },
      ["Show/hide party list"] = {
        jsonName = "TogglePartyBattlelist",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_party_list.toggle() end,
      },
      ["Show/hide kill tracker"] = {
        jsonName = "TogglePreyWidget",
        bindKeyDown = function()
          if not canPerformAction() then return end
          if modules.game_trackers and modules.game_trackers.toggleKillTracker then
            modules.game_trackers.toggleKillTracker()
          end
        end,
      },
      ["Show/hide quest tracker"] = {
        jsonName = "ToggleQuestTrackerWidget",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_questlog:toggleTracker() end,
      },
      ["Show/hide skills window"] = {
        jsonName = "ToggleSkillsWidget",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_skills.toggle() end,
      },
      ["Show/hide spell list"] = {
        jsonName = "ToggleSpellListWidget",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_spells.toggle() end,
      },
      ["Show/hide supply analyser"] = {
        jsonName = "ToggleSupplyAnalyserWidget",
        bindKeyDown = function() if not canPerformAction() then return end modules.game_analyser.toggleAnalysers("supplyButton") end,
      },
    },
    ["Recorder Viewer"] = {
      ["Increase speed"] = {
        jsonName = "IncreaseCamViewerSpeed",
        bindKeyDown = function()
          local speed = g_game.getCamViewerSpeed()
          g_game.setCamViewerSpeed(math.max(0.2, speed - 0.2))
        end,
      },
      ["Decrease speed"] = {
        jsonName = "DecreaseCamViewerSpeed",
        bindKeyDown = function()
          local speed = g_game.getCamViewerSpeed()
          g_game.setCamViewerSpeed(math.min(1.8, speed + 0.2))
        end,
      },
      ["Pause/Play"] = {
        jsonName = "PausePlayCamViewerSpeed",
        bindKeyDown = function()
          local speed = g_game.getCamViewerSpeed()
          g_game.setCamViewerSpeed(speed == 0 and 1 or 0)
        end,
      },
    },
}

function KeyBinds:getOptionType(name)
	for k, v in pairs(KeyBinds.Hotkeys) do
		for typo, data in pairs(v) do
			if data.jsonName and data.jsonName == name then
				return k
			end
		end
	end
	return nil
end

function KeyBinds:getActionName(name)
	for k, v in pairs(KeyBinds.Hotkeys) do
		for typo, data in pairs(v) do
			if data.jsonName and data.jsonName == name then
				return typo
			end
		end
	end
	return nil
end

function KeyBinds:getBindFunction(name)
	for k, v in pairs(KeyBinds.Hotkeys) do
		for typo, data in pairs(v) do
			if data.jsonName and data.jsonName == name then
				return data
			end
		end
	end
	return nil
end

function KeyBinds:reset()
	for k, v in pairs(KeyBinds.Hotkeys) do
		for typo, data in pairs(v) do
			if data.firstKey and data.firstKey ~= "" then
			  local find = table.find(walkBinds, typo)
			  if find then
			    updateTurnKey(typo, data.firstKey, true)
			  end

			  g_keyboard.unbindKeyDown(data.firstKey, nil)
			  g_keyboard.unbindKeyUp(data.firstKey, nil)
			  g_keyboard.unbindKeyPress(data.firstKey, nil)

			  data.firstKey = ''
			end

      if data.secondKey and data.secondKey ~= "" then
        local find = table.find(walkBinds, typo)
        if find then
          updateTurnKey(typo, data.secondKey, true)
        end

        g_keyboard.unbindKeyDown(data.secondKey, nil)
        g_keyboard.unbindKeyUp(data.secondKey, nil)
        g_keyboard.unbindKeyPress(data.secondKey, nil)
        data.secondKey = ''
      end
		end
	end
end

function KeyBinds:setupAndReset(profile, chatType)
  hotkeys = {}
  KeyBinds:reset()

  if not Options.hotkeySets or not Options.hotkeySets[profile] or not Options.hotkeySets[profile][chatType] then
    return
  end

  for _, data in pairs(Options.hotkeySets[profile][chatType]) do
    local setting = data["actionsetting"] and data["actionsetting"]["action"]
    local hotkey = data["keysequence"]
    local secondary = data["secondary"]

    if hotkey == "Return" then
      hotkey = "Enter"
    elseif hotkey == "Esc" then
      hotkey = "Escape"
    elseif hotkey == "Shift+Backtab" then
      hotkey = "Shift+Tab"
    end

    local optionType = setting and KeyBinds:getOptionType(setting)
    local actionName = setting and KeyBinds:getActionName(setting)

    local find = table.find(walkBinds, actionName)
    if find then
      updateTurnKey(actionName, hotkey, false)
    end

    if optionType and actionName then
      if secondary ~= nil and secondary == true then
        KeyBinds.Hotkeys[optionType][actionName].secondKey = hotkey
        hotkeys[hotkey] = {option = optionType, action = actionName}
      else
        KeyBinds.Hotkeys[optionType][actionName].firstKey = hotkey
        hotkeys[hotkey] = {option = optionType, action = actionName}
      end

      local bindData = KeyBinds:getBindFunction(setting)
      local canBind = true
      if bindData.dontBindChatoff and chatType == 'chatOff' then
        canBind = false
      end

      if bindData.bindKeyDown and canBind then
        g_keyboard.bindKeyDown(hotkey, bindData.bindKeyDown)
      end
      if bindData.bindKeyUp and canBind then
        g_keyboard.bindKeyUp(hotkey, bindData.bindKeyUp)
      end
      if bindData.bindKeyPress and canBind then
        g_keyboard.bindKeyPress(hotkey, bindData.bindKeyPress)
      end
    end
  end

  if modules.client_terminal and modules.client_terminal.bindHotkey then
    modules.client_terminal.bindHotkey()
  end
end

function KeyBinds:setup()
	for _, data in pairs(Options.currentHotkeySet["chatOn"]) do
		local setting = data["actionsetting"]["action"]
		local hotkey = data["keysequence"]

		-- fazer um translate []
		if hotkey == "Return" then
			hotkey = "Enter"
		elseif hotkey == "Esc" then
			hotkey = "Escape"
		end

		local optionType = KeyBinds:getOptionType(setting)
		local actionName = KeyBinds:getActionName(setting)
		if optionType and actionName then
			KeyBinds.Hotkeys[optionType][actionName].firstKey = hotkey
			hotkeys[hotkey] = {option = optionType, action = actionName, firstKey = hotkey, secondKey = ''}

			local bindData = KeyBinds:getBindFunction(setting)
      local canBind = true
      if bindData.dontBindChatoff and chatType == 'chatOff' then
        canBind = false
      end

			if bindData.bindKeyDown and canBind then
			  g_keyboard.bindKeyDown(hotkey, bindData.bindKeyDown)
			end
			if bindData.bindKeyUp and canBind then
		  	g_keyboard.bindKeyUp(hotkey, bindData.bindKeyUp)
			end
			if bindData.bindKeyPress and canBind then
	  		g_keyboard.bindKeyPress(hotkey, bindData.bindKeyPress)
			end
		end
	end

  if modules.client_terminal and modules.client_terminal.bindHotkey then
    modules.client_terminal.bindHotkey()
  end
end

function KeyBinds:offline()

end

function KeyBind:getKeyBind(option, action)
    local obj = KeyBinds.Hotkeys[option][action]
    if not obj then
      return false
    end

    obj.option = option
    obj.action = action
    return setmetatable(obj, { __index = self })
end

function KeyBind:getKeyBindByHotkey(key)
  if not hotkeys[key] then
    return false
  end

  return KeyBind:getKeyBind(hotkeys[key].option, hotkeys[key].action)
end

function KeyBind:getKeyBindBySecondHotkey(key)
  for k, v in pairs(KeyBinds.Hotkeys) do
		for typo, data in pairs(v) do
			if data.secondKey and data.secondKey == key then
        return KeyBind:getKeyBind(k, typo)
      end
    end
  end
  return false
end

function KeyBind:getbindKeyDown() return self.bindKeyDown end
function KeyBind:getFirstKey() return self.firstKey end
function KeyBind:getSecondKey() return self.secondKey end

function KeyBind:setFirstKey(key)
  if self.action == "Go North-East" or self.action == "Go North-West" or self.action == "Go South-East" or self.action == "Go South-West" then
    if self.firstKey then
      g_ui.removeDiagonalKey(getKeyCode(self.firstKey))
    end
  end
  if self.called then
    -- unbind keys
    if self.parent then
      if self.bindKeyDown and self.firstKey and self.firstKey ~= "" then
        g_keyboard.unbindKeyDown(self.firstKey, self.bindKeyDown, self.parent)
      end

      if self.bindKeyUp and self.firstKey and self.firstKey ~= "" then
        g_keyboard.unbindKeyUp(self.firstKey, self.bindKeyUp, self.parent, true)
      end
      if self.bindKeyPress and self.firstKey and self.firstKey ~= "" then
        g_keyboard.unbindKeyPress(self.firstKey, self.bindKeyPress, self.parent)
      end
    else
      if self.bindKeyDown and self.firstKey and self.firstKey ~= "" then
        g_keyboard.unbindKeyDown(self.firstKey, self.bindKeyDown)
      end
    end
  end

  self.firstKey = key

  if self.action == "Go North-East" or self.action == "Go North-West" or self.action == "Go South-East" or self.action == "Go South-West" then
    if self.firstKey then
      g_ui.addDiagonalKey(getKeyCode(self.firstKey))
    end
  end

  if key ~= '' then
    hotkeys[key] = {option = self.option, action = self.action}
  else
    hotkeys[key] = nil
  end

  KeyBinds.Hotkeys[self.option][self.action].firstKey = key

  local general = m_settings.getGeneralHotkeyWidget(self.option .. "." .. self.action)
  if general and general.firstKey then
    general.firstKey:setText(key)
  end

  if not self.called then
    return
  end

  -- call bind
  if not self.parent then
    if self.bindKeyDown and self.firstKey and self.firstKey ~= "" then
      g_keyboard.bindKeyDown(self.firstKey, self.bindKeyDown)
    end

    if self.bindKeyUp and self.firstKey and self.firstKey ~= "" then
      g_keyboard.bindKeyUp(self.firstKey, self.bindKeyUp)
    end
    if self.bindKeyPress and self.firstKey and self.firstKey ~= "" then
      g_keyboard.bindKeyPress(self.firstKey, self.bindKeyPress)
    end
    return
  end

  if self.bindKeyDown and self.firstKey and self.firstKey ~= "" then
    g_keyboard.bindKeyDown(self.firstKey, self.bindKeyDown, self.parent, self.repeatable)
  end

  if self.bindKeyUp and self.firstKey and self.firstKey ~= "" then
    g_keyboard.bindKeyUp(self.firstKey, self.bindKeyUp, self.parent, self.repeatable)
  end
  if self.bindKeyPress and self.firstKey and self.firstKey ~= "" then
    g_keyboard.bindKeyPress(self.firstKey, self.bindKeyPress, self.parent, self.repeatable)
  end
end

function KeyBind:setSecondKey(key)
  if self.action == "Go North-East" or self.action == "Go North-West" or self.action == "Go South-East" or self.action == "Go South-West" then
    if self.secondKey then
      g_ui.removeDiagonalKey(getKeyCode(self.secondKey))
    end
  end

  if self.called then
    -- unbind keys
    if self.parent then
        if self.bindKeyDown and self.secondKey ~= "" then
          g_keyboard.unbindKeyDown(self.secondKey, self.bindKeyDown, self.parent)
        end

      if self.bindKeyUp and self.secondKey ~= "" then
        g_keyboard.unbindKeyUp(self.secondKey, self.bindKeyUp, self.parent, true)
      end
      if self.bindKeyPress and self.secondKey ~= "" then
        g_keyboard.unbindKeyPress(self.secondKey, self.bindKeyPress, self.parent)
      end
    else
      g_keyboard.unbindKeyDown(self.secondKey, self.bindKeyDown)
    end
  end
  self.secondKey = key

  if self.action == "Go North-East" or self.action == "Go North-West" or self.action == "Go South-East" or self.action == "Go South-West" then
    if self.secondKey then
      g_ui.addDiagonalKey(getKeyCode(self.secondKey))
    end
  end

  if key ~= '' then
    hotkeys[key] = {option = self.option, action = self.action}
  else
    hotkeys[key] = nil
  end

  KeyBinds.Hotkeys[self.option][self.action].secondKey = key
  if not self.called then
    return
  end

  -- call bind
  if not self.parent then
    if self.bindKeyDown and self.secondKey ~= "" then
      g_keyboard.bindKeyDown(self.secondKey, self.bindKeyDown)
    end

    if self.bindKeyUp and self.secondKey ~= "" then
      g_keyboard.bindKeyUp(self.secondKey, self.bindKeyUp)
    end
    if self.bindKeyPress and self.secondKey ~= "" then
      g_keyboard.bindKeyPress(self.secondKey, self.bindKeyPress)
    end
    return
  end

  if self.bindKeyDown and self.secondKey ~= "" then
    g_keyboard.bindKeyDown(self.secondKey, self.bindKeyDown, self.parent, self.repeatable)
  end

  if self.bindKeyUp and self.secondKey ~= "" then
    g_keyboard.bindKeyUp(self.secondKey, self.bindKeyUp, self.parent, self.repeatable)
  end
  if self.bindKeyPress and self.secondKey ~= "" then
    g_keyboard.bindKeyPress(self.secondKey, self.bindKeyPress, self.parent, self.repeatable)
  end
end

function KeyBind:active(parent, repeatable)
  if self.firstKey == '' then
    return
  end

  if parent then
    self.parent = parent
  end

  if repeatable then
    self.repeatable = repeatable
  end

  if self.action == "Go North-East" or self.action == "Go North-West" or self.action == "Go South-East" or self.action == "Go South-West" then
    if self.firstKey then
      g_ui.addDiagonalKey(getKeyCode(self.firstKey))
    end
    if self.secondKey then
      g_ui.addDiagonalKey(getKeyCode(self.secondKey))
    end
  end

  self.called = true
  if not self.parent then
    if self.bindKeyDown then
      g_keyboard.bindKeyDown(self.firstKey, self.bindKeyDown)
      if self.secondKey then
        g_keyboard.bindKeyDown(self.secondKey, self.bindKeyDown)
      end
    end

    if self.bindKeyUp then
      g_keyboard.bindKeyUp(self.firstKey, self.bindKeyUp)
      if self.secondKey then
        g_keyboard.bindKeyUp(self.secondKey, self.bindKeyUp)
      end
    end
    if self.bindKeyPress then
      g_keyboard.bindKeyPress(self.firstKey, self.bindKeyPress)
      if self.secondKey then
        g_keyboard.bindKeyPress(self.secondKey, self.bindKeyPress)
      end
    end
    return
  end

  if self.bindKeyDown then
    g_keyboard.bindKeyDown(self.firstKey, self.bindKeyDown, self.parent, self.repeatable)
    if self.secondKey then
      g_keyboard.bindKeyDown(self.secondKey, self.bindKeyDown, self.parent, self.repeatable)
    end
  end

  if self.bindKeyUp then
    g_keyboard.bindKeyUp(self.firstKey, self.bindKeyUp, self.parent, self.repeatable)
    if self.secondKey then
      g_keyboard.bindKeyUp(self.secondKey, self.bindKeyUp, self.parent, self.repeatable)
    end
  end
  if self.bindKeyPress then
    g_keyboard.bindKeyPress(self.firstKey, self.bindKeyPress, self.parent, self.repeatable)
    if self.secondKey then
      g_keyboard.bindKeyPress(self.secondKey, self.bindKeyPress, self.parent, self.repeatable)
    end
  end
end

function KeyBind:deactive()
  if self.firstKey == '' then
    return
  end

  if self.action == "Go North-East" or self.action == "Go North-West" or self.action == "Go South-East" or self.action == "Go South-West" then
    if self.firstKey then
      g_ui.removeDiagonalKey(getKeyCode(self.firstKey))
    end
    if self.secondKey then
      g_ui.removeDiagonalKey(getKeyCode(self.secondKey))
    end
  end

  self.called = false
  if self.parent then
    g_keyboard.unbindKeyDown(self.firstKey, self.bindKeyDown, self.parent, self.repeatable)
    if self.secondKey then
      g_keyboard.unbindKeyDown(self.secondKey, self.bindKeyDown, self.parent, self.repeatable)
    end

    if self.bindKeyUp then
      g_keyboard.unbindKeyUp(self.firstKey, self.bindKeyUp, self.parent, self.repeatable)
      if self.secondKey then
        g_keyboard.unbindKeyUp(self.secondKey, self.bindKeyUp, self.parent, self.repeatable)
      end
    end
    if self.bindKeyPress then
      g_keyboard.unbindKeyPress(self.firstKey, self.bindKeyPress, self.parent, self.repeatable)
      if self.secondKey then
        g_keyboard.unbindKeyPress(self.secondKey, self.bindKeyPress, self.parent, self.repeatable)
      end
    end

    return
  end

  g_keyboard.unbindKeyDown(self.firstKey, self.bindKeyDown)
  if self.secondKey then
    g_keyboard.unbindKeyDown(self.secondKey, self.bindKeyDown)
  end
end

function KeyBinds:hotkeyIsUsed(key)
  return hotkeys[key] ~= nil
end

function KeyBinds:isUsedHotkey(key)
  if KeyBinds:hotkeyIsUsed(key) then
    return true
  end
  if modules.game_actionbar.isHotkeyUsed(key) then
    return true
  end
  if m_settings.hotkeyIsUsed(key) then
    return true
  end

  return false
end

function KeyBinds:getHotkeyByName(name)
   for k, v in pairs(KeyBinds.Hotkeys) do
		for typo, data in pairs(v) do
			if data.jsonName and data.jsonName == name then
				return data.firstKey
			end
		end
	end
end

function KeyBinds:removeHotkey(name)
  if KeyBinds:hotkeyIsUsed(text) then
    local key = KeyBind:getKeyBindByHotkey(name)
    if key then
      key:setFirstKey('')
      key:setSecondKey('')
    end
  end
end
