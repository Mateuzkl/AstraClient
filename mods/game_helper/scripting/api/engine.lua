--[[
  scripting/api/engine.lua  ->  namespace `Engine`

  Zerobot-dialect `Engine.*` surface, mapped onto the Amon game_helper combat
  features (master on/off + Targeting / Healing / MagicShooter / Equipment /
  Friend Healing, plus the per-module preset "profiles" 0-9).

  In Zerobot every `engineXxx` is a C++ binding. Here there is NO native binding:
  the helper exposes its combat features as MODULE-GLOBAL Lua functions
  (`botStatus`, `toggleAutoTarget`, `toggleMagicShooter`, `activateModulePresetBySlot`,
  `captureModulePresetData`, `applyModulePresetData`, `getShooterProfile`, ...) and a
  global `helperConfig` table. This module runs OUTSIDE the sandbox (CONTRACT §3), so
  it reaches those globals directly. See scratchpad analysis/amon-combat-surface.md
  for the full mapping (§5) and gotchas (§6).

  Status of each function:
    VIABLE  -> real, functional equivalent.
    PARTIAL -> best-effort with a documented adaptation.
    STUB    -> no Amon backing; returns a benign default and logs once via ctx.log.

  KEY GOTCHAS honored here:
    1. Toggles FLIP, they don't SET. `botStatus`, `toggleAutoTarget`,
       `toggleMagicShooter` invert state with no argument. For `enableX(bool)` SET
       semantics we read the current flag first and only flip on mismatch.
       Healing / FriendHealing / Equipment use the proper `onEnableX(bool)` setters.
    2. Active config is FLAT; presets are snapshots. setProfileSettings(active) writes
       the FLAT helperConfig fields (via applyModulePresetData) + refreshes + saves;
       writing only the slot changes nothing until re-activated. Inactive slot writes
       go to helperConfig.<profilesKey>["Preset N"] + saveSettings().
    3. ZB profile index i (0-9) <-> Amon slot name "Preset "..(i+1) (1-10).
    4. Shooter is special: its active config is NOT flat -> read via getShooterProfile(),
       write helperConfig.shooterProfiles[selected].{spells,runes} + loadShooterProfileByName.
    5. Applying a preset / writing profile settings re-renders the UI and re-saves.
       These are CONFIG-EDIT operations -- do NOT call them every tick from a script.
]]

return function(api, ctx)
  local Engine = {}

  -- -------------------------------------------------------------------------
  -- small utilities
  -- -------------------------------------------------------------------------
  local function bool(v) return v == true end

  -- one-time "not supported" logging so stubs don't spam the console per call.
  local warned = {}
  local function unsupported(name, retval)
    if not warned[name] then
      warned[name] = true
      if ctx and ctx.log then
        ctx.log(string.format("[Engine.%s] nao suportado neste engine", name))
      end
    end
    return retval
  end

  -- read a boolean feature flag straight off helperConfig.
  local function flag(field)
    local cfg = _G.helperConfig
    return (type(cfg) == "table" and cfg[field]) == true
  end

  -- write a boolean feature flag + persist (used where no clean setter exists).
  local function setFlagPersisted(field, value)
    local cfg = _G.helperConfig
    if type(cfg) ~= "table" then return false end
    cfg[field] = bool(value)
    if type(_G.saveSettings) == "function" then
      pcall(_G.saveSettings)
    end
    return true
  end

  -- read-before-toggle: only invoke an arg-less FLIP toggle when the current
  -- state differs from the desired one (gotcha #1). `getCur` returns current
  -- bool, `toggleFn` is the flip function (called with no args).
  local function setViaToggle(getCur, toggleFn, desired)
    desired = bool(desired)
    if type(toggleFn) ~= "function" then return end
    local cur = getCur() == true
    if cur ~= desired then
      pcall(toggleFn)
    end
  end

  -- =========================================================================
  -- 3.A  Feature state queries (is...Enabled)  -- all read helperConfig flags
  -- =========================================================================

  -- VIABLE: autoHealing is the runtime worker flag.
  function Engine.isHealingEnabled() return flag("autoHealingEnabled") end

  -- VIABLE
  function Engine.isHealFriendEnabled() return flag("healFriendEnabled") end

  -- VIABLE: clean public getter exists.
  function Engine.isBotEnabled()
    local gh = modules and modules.game_helper
    if gh and type(gh.getHotkeyHelperStatus) == "function" then
      return gh.getHotkeyHelperStatus() == true
    end
    return _G.hotkeyHelperStatus == true
  end

  -- VIABLE
  function Engine.isTargetingEnabled() return flag("autoTargetEnabled") end

  -- VIABLE
  function Engine.isMagicShooterEnabled() return flag("magicShooterEnabled") end

  -- PARTIAL: cavebot lives in its own module surface (CaveBot.*), not in the
  -- helperConfig combat flags. Report what we can from the flag if present.
  function Engine.isCaveBotEnabled() return flag("cavebotHelperEnabled") end

  -- VIABLE: prefer the swap flag (the ring/amulet engine checks this one).
  function Engine.isEquipmentEnabled() return flag("equipmentSwapEnabled") end

  -- VIABLE
  function Engine.isTimerEnabled() return flag("timerEnabled") end

  -- --- Tank Mode wiring (Auto SSA + Auto Might Ring) -----------------------
  -- The old helperConfig.autoSSA / mightRingEnabled flags are DEAD (no worker reads
  -- them). The real worker is checkTankMode() in helper.lua, gated by
  -- helperConfig.tankModeEnabled and, per accessory, tankModeAmuletEnabled /
  -- tankModeRingEnabled (~= false) re-equipping tankModeAmuletId (default 3081=SSA,
  -- 3082 its charged pair) / tankModeRingId (default 3048=Might Ring). We drive
  -- those fields + the master via modules.game_helper.onEnableTankMode (which ticks
  -- the checkbox + icon stats but does NOT save, so we saveSettings ourselves).
  local TANK_ACCESSORY = {
    amulet = { id = "tankModeAmuletId", en = "tankModeAmuletEnabled",
               sibling = "tankModeRingEnabled", default = 3081,
               valid = { [3081] = true, [3082] = true } },
    ring   = { id = "tankModeRingId", en = "tankModeRingEnabled",
               sibling = "tankModeAmuletEnabled", default = 3048,
               valid = { [3048] = true } },
  }
  -- Is this tank accessory's auto-swap effectively ON? Mirrors checkTankMode's
  -- gates: master on + this half not disabled + the effective id is the tank one.
  local function tankIsEnabled(kind)
    local cfg = _G.helperConfig
    local t = TANK_ACCESSORY[kind]
    if type(cfg) ~= "table" or not t then return false end
    if cfg.tankModeEnabled ~= true then return false end
    if cfg[t.en] == false then return false end
    local id = tonumber(cfg[t.id]) or t.default -- default mirrors "id or 3081/3048"
    return t.valid[id] == true
  end
  -- Enable forces the canonical id + turns the master on (leaving the sibling half
  -- off unless already set). Disable clears this half and only tears the master
  -- down if the sibling isn't wanted. true when applied, false if no helperConfig.
  local function tankEnable(kind, enable)
    local cfg = _G.helperConfig
    local t = TANK_ACCESSORY[kind]
    if type(cfg) ~= "table" or not t then return false end
    local gh = modules and modules.game_helper
    if bool(enable) then
      cfg[t.id] = t.default
      cfg[t.en] = true
      if cfg[t.sibling] == nil then cfg[t.sibling] = false end
      if gh and type(gh.onEnableTankMode) == "function" then
        pcall(gh.onEnableTankMode, true)
      else
        cfg.tankModeEnabled = true
      end
    else
      cfg[t.en] = false
      if cfg[t.sibling] ~= true then
        if gh and type(gh.onEnableTankMode) == "function" then
          pcall(gh.onEnableTankMode, false)
        else
          cfg.tankModeEnabled = false
        end
      end
    end
    if type(_G.saveSettings) == "function" then pcall(_G.saveSettings) end
    return true
  end

  -- VIABLE: Auto SSA == the Tank Mode amulet auto-swap (default SSA 3081).
  function Engine.isAutoSSAEnabled() return tankIsEnabled("amulet") end

  -- VIABLE: Auto Might Ring == the Tank Mode ring auto-swap (default 3048).
  function Engine.isAutoMightRingEnabled() return tankIsEnabled("ring") end

  -- VIABLE: Hold Attack IS the ZB hold-target. helperConfig.holdAttack + the
  -- checkHoldAttack worker (helper.lua) re-attacks the locked creature. Two nuances
  -- vs ZB: (a) mutually EXCLUSIVE with autoTarget -- checkHoldAttack returns early
  -- while helperConfig.autoTargetEnabled is on (hold stays inert by design);
  -- (b) only ESC clears the lock (no per-call unlock).
  function Engine.isHoldTargetEnabled() return flag("holdAttack") end
  -- STUB: no anti-push.
  function Engine.isAntiPushEnabled() return unsupported("isAntiPushEnabled", false) end
  -- STUB: no rune-max.
  function Engine.isRuneMaxEnabled() return unsupported("isRuneMaxEnabled", false) end
  -- VIABLE: read the entergame auto-reconnect preference (per-char node when online,
  -- else the global g_settings flag). getAutoReconnect is a characterlist.lua global.
  function Engine.isReconnectEnabled()
    if g_game.isOnline() and type(_G.getAutoReconnect) == "function"
        and type(g_game.getCharacterName) == "function" then
      local ok, v = pcall(_G.getAutoReconnect, g_game.getCharacterName())
      if ok then return v == true end
    end
    if g_settings and type(g_settings.getBoolean) == "function" then
      return g_settings.getBoolean("autoReconnect", false) == true
    end
    return false
  end

  -- =========================================================================
  -- 3.B  Feature toggles (enable... / setters)
  -- =========================================================================

  -- PARTIAL: toggleAutoTarget is an arg-less FLIP (it also clears the locked
  -- target + cancels attack on disable, so we route through it rather than a raw
  -- field write). Wrapped to honor the boolean (gotcha #1).
  function Engine.enableTargeting(enable)
    setViaToggle(Engine.isTargetingEnabled, _G.toggleAutoTarget, enable)
  end

  -- PARTIAL: toggleMagicShooter is an arg-less FLIP (also starts/stops the custom
  -- spell timer + updates tracker/iconstats). Wrapped to honor the boolean.
  function Engine.enableMagicShooter(enable)
    setViaToggle(Engine.isMagicShooterEnabled, _G.toggleMagicShooter, enable)
  end

  -- VIABLE: clean setter that takes a bool + syncs UI/iconstats.
  function Engine.enableHealFriend(enable)
    local gh = modules and modules.game_helper
    if gh and type(gh.onEnableAllFriendHealing) == "function" then
      gh.onEnableAllFriendHealing(bool(enable))
    else
      setFlagPersisted("healFriendEnabled", enable)
    end
  end

  -- VIABLE: clean setter (autoHealing = the runtime worker).
  function Engine.enableHealing(enable)
    local gh = modules and modules.game_helper
    if gh and type(gh.onEnableAutoHealing) == "function" then
      gh.onEnableAutoHealing(bool(enable))
    else
      setFlagPersisted("autoHealingEnabled", enable)
    end
  end

  -- VIABLE: equipment SWAP is the actual worker; its setter also saves.
  function Engine.enableEquipment(enable)
    local gh = modules and modules.game_helper
    if gh and type(gh.onEnableEquipmentSwap) == "function" then
      gh.onEnableEquipmentSwap(bool(enable))
    else
      setFlagPersisted("equipmentSwapEnabled", enable)
    end
  end

  -- PARTIAL: there is a module setter (onEnableTimerModule) that also starts/stops
  -- the individual timers; prefer it, else field-write + save.
  function Engine.enableTimer(enable)
    local gh = modules and modules.game_helper
    if gh and type(gh.onEnableTimerModule) == "function" then
      gh.onEnableTimerModule(bool(enable))
    else
      setFlagPersisted("timerEnabled", enable)
    end
  end

  -- VIABLE: route through the real toggle (toggleCavebotHelper -> EnableCavebotReal),
  -- which validates waypoints/area, ticks the checkbox, starts the map + minimap
  -- updates and shows the status message. A bare flag write skips all that (the
  -- cavebot may not walk). setViaToggle flips only on mismatch; we then report the
  -- REAL outcome (EnableCavebotReal can REFUSE -- e.g. <2 waypoints or a restricted
  -- area -- leaving the flag false). Falls back to a flag write if absent.
  function Engine.enableCaveBot(enable)
    if type(_G.toggleCavebotHelper) == "function" then
      setViaToggle(Engine.isCaveBotEnabled, _G.toggleCavebotHelper, enable)
      return Engine.isCaveBotEnabled()
    end
    return setFlagPersisted("cavebotHelperEnabled", enable)
  end

  -- PARTIAL: botStatus is an arg-less FLIP of the master switch. Wrapped to honor
  -- the boolean (gotcha #1). Needs the helper UI to be present (botStatus no-ops
  -- if the status widget is missing).
  function Engine.enableBot(enable)
    setViaToggle(Engine.isBotEnabled, _G.botStatus, enable)
  end

  -- VIABLE: Auto SSA -> Tank Mode amulet auto-swap (see isAutoSSAEnabled).
  function Engine.autoSSAEnable(enable)
    return tankEnable("amulet", enable)
  end

  -- VIABLE: Auto Might Ring -> Tank Mode ring auto-swap.
  function Engine.autoMightRingEnable(enable)
    return tankEnable("ring", enable)
  end

  -- VIABLE: Hold Attack setter (toggleHoldAttack takes a bool + sets/clears the
  -- locked target). See isHoldTargetEnabled for the 2 nuances vs ZB.
  function Engine.holdTargetEnable(enable)
    local gh = modules and modules.game_helper
    if gh and type(gh.toggleHoldAttack) == "function" then
      gh.toggleHoldAttack(bool(enable))
      return
    end
    return setFlagPersisted("holdAttack", enable)
  end

  -- STUB group: anti-push / rune-max have no Amon backing.
  function Engine.antiPushEnable(_) return unsupported("antiPushEnable") end
  function Engine.setFirstAntiPushId(_) return unsupported("setFirstAntiPushId") end
  function Engine.setSecondAntiPushId(_) return unsupported("setSecondAntiPushId") end
  function Engine.runeMaxEnable(_) return unsupported("runeMaxEnable") end
  function Engine.getRuneMaxId() return unsupported("getRuneMaxId", 0) end
  function Engine.setRuneMaxId(_) return unsupported("setRuneMaxId") end

  -- VIABLE: Auto Reconnect via the entergame engine. toggleAutoReconnect drives
  -- both sources it reads (the g_settings 'autoReconnect' flag + the per-char node).
  function Engine.reconnectEnable(enable)
    local gh = modules and modules.game_helper
    if gh and type(gh.toggleAutoReconnect) == "function" then
      gh.toggleAutoReconnect(bool(enable))
      return
    end
    return unsupported("reconnectEnable")
  end

  -- =========================================================================
  -- 3.C  Profiles (per module, ZB index 0..9  <->  Amon "Preset "..(i+1))
  -- =========================================================================
  -- These re-render the UI + save when activating/writing -- treat as CONFIG-EDIT
  -- operations, NOT per-tick calls (gotcha #5).

  -- VIABLE: switch to ZB profile index `i` for a module type.
  local function switchProfile(moduleType, i)
    local slot = (tonumber(i) or 0) + 1 -- ZB 0-based -> Amon 1-based
    if type(_G.activateModulePresetBySlot) == "function" then
      pcall(_G.activateModulePresetBySlot, moduleType, slot, true) -- 3rd arg hideMessage: no chat spam
    end
  end

  -- VIABLE: current active ZB profile index (or -1 if unresolved).
  local function getProfile(moduleType)
    local meta = _G.modulePresetMeta and _G.modulePresetMeta[moduleType]
    local cfg = _G.helperConfig
    if not meta or type(cfg) ~= "table" then return -1 end
    local name = cfg[meta.selectedKey]
    local slot = type(_G.getModulePresetSlotIndex) == "function"
      and _G.getModulePresetSlotIndex(name) or nil
    if not slot then return -1 end
    return slot - 1 -- Amon 1-based -> ZB 0-based
  end

  -- VIABLE: user-facing display name of ZB profile index `i`.
  local function getProfileName(moduleType, i)
    local slot = (tonumber(i) or 0) + 1
    local slotName = type(_G.getModulePresetSlotName) == "function"
      and _G.getModulePresetSlotName(slot) or ("Preset " .. slot)
    if type(_G.getModulePresetUiName) == "function" then
      return _G.getModulePresetUiName(moduleType, slotName)
    end
    return slotName
  end

  -- Is ZB index `i` the currently-active slot for this module type?
  local function isActiveProfile(moduleType, i)
    return getProfile(moduleType) == (tonumber(i) or -999)
  end

  -- shallow deep-copy fallback (helper has deepCopy global; use it when present).
  local function copyTable(t)
    if type(t) ~= "table" then return t end
    if type(_G.deepCopy) == "function" then
      local ok, res = pcall(_G.deepCopy, t)
      if ok then return res end
    end
    local out = {}
    for k, v in pairs(t) do out[k] = (type(v) == "table") and copyTable(v) or v end
    return out
  end

  -- ---- generic (flat) settings get/set for healing / equipment / targeting ----

  -- VIABLE: read the "Advanced Settings" snapshot for ZB index `i`.
  --   active slot  -> snapshot of FLAT helperConfig fields (captureModulePresetData)
  --   inactive     -> the stored slot helperConfig.<profilesKey>["Preset N"]
  local function getProfileSettingsFlat(moduleType, i)
    local cfg = _G.helperConfig
    if type(cfg) ~= "table" then return nil end
    if isActiveProfile(moduleType, i) and type(_G.captureModulePresetData) == "function" then
      return _G.captureModulePresetData(moduleType)
    end
    local meta = _G.modulePresetMeta and _G.modulePresetMeta[moduleType]
    if not meta then return nil end
    local slot = (tonumber(i) or 0) + 1
    local slotName = "Preset " .. slot
    if type(_G.ensureModulePresetConfig) == "function" then
      pcall(_G.ensureModulePresetConfig, moduleType)
    end
    local profiles = cfg[meta.profilesKey]
    local preset = profiles and profiles[slotName]
    if type(preset) ~= "table" then return nil end
    return copyTable(preset)
  end

  -- VIABLE: write the "Advanced Settings" for ZB index `i`.
  --   active slot  -> apply into FLAT fields + refresh UI + onLoadHelperData + save
  --                   (mirrors loadModulePresetByName's non-shooter branch, gotcha #2/#5)
  --   inactive     -> merge into the stored slot + save (no UI refresh needed)
  local function setProfileSettingsFlat(moduleType, i, settings)
    local cfg = _G.helperConfig
    if type(cfg) ~= "table" or type(settings) ~= "table" then return end
    local meta = _G.modulePresetMeta and _G.modulePresetMeta[moduleType]
    if not meta then return end

    if isActiveProfile(moduleType, i) then
      -- write FLAT active fields, then run the same refresh path activation uses.
      if type(_G.applyModulePresetData) == "function" then
        _G.applyModulePresetData(moduleType, settings)
      end
      local refreshed = false
      if type(_G.refreshModulePresetUi) == "function" then
        local ok, res = pcall(_G.refreshModulePresetUi, moduleType)
        refreshed = ok and res
      end
      if (moduleType == "healing" or not refreshed)
          and type(_G.onLoadHelperData) == "function" then
        pcall(_G.onLoadHelperData)
      end
      if type(_G.saveSettings) == "function" then pcall(_G.saveSettings) end
    else
      -- inactive slot: merge into the stored snapshot + persist.
      if type(_G.ensureModulePresetConfig) == "function" then
        pcall(_G.ensureModulePresetConfig, moduleType)
      end
      local profiles = cfg[meta.profilesKey]
      if type(profiles) ~= "table" then
        profiles = {}; cfg[meta.profilesKey] = profiles
      end
      local slotName = "Preset " .. ((tonumber(i) or 0) + 1)
      local slot = profiles[slotName]
      if type(slot) ~= "table" then slot = {}; profiles[slotName] = slot end
      local fields = _G.modulePresetFields and _G.modulePresetFields[moduleType]
      if type(fields) == "table" then
        for _, key in ipairs(fields) do
          if settings[key] ~= nil then slot[key] = copyTable(settings[key]) end
        end
      else
        for k, v in pairs(settings) do slot[k] = copyTable(v) end
      end
      if type(_G.saveSettings) == "function" then pcall(_G.saveSettings) end
    end
  end

  -- ---- shooter settings (special: active config is NOT flat) -- gotcha #4 ----

  -- read spells/runes for ZB index `i`.
  local function getShooterSettings(i)
    local cfg = _G.helperConfig
    if type(cfg) ~= "table" then return nil end
    if isActiveProfile("shooter", i) and type(_G.getShooterProfile) == "function" then
      return copyTable(_G.getShooterProfile())
    end
    if type(_G.ensureModulePresetConfig) == "function" then
      pcall(_G.ensureModulePresetConfig, "shooter")
    end
    local slotName = "Preset " .. ((tonumber(i) or 0) + 1)
    local preset = cfg.shooterProfiles and cfg.shooterProfiles[slotName]
    if type(preset) ~= "table" then return nil end
    return copyTable(preset)
  end

  -- write spells/runes for ZB index `i`.
  local function setShooterSettings(i, settings)
    local cfg = _G.helperConfig
    if type(cfg) ~= "table" or type(settings) ~= "table" then return end
    if type(_G.ensureModulePresetConfig) == "function" then
      pcall(_G.ensureModulePresetConfig, "shooter")
    end
    if type(cfg.shooterProfiles) ~= "table" then cfg.shooterProfiles = {} end
    local slotName = "Preset " .. ((tonumber(i) or 0) + 1)
    local preset = cfg.shooterProfiles[slotName]
    if type(preset) ~= "table" then preset = {}; cfg.shooterProfiles[slotName] = preset end
    if settings.spells ~= nil then preset.spells = copyTable(settings.spells) end
    if settings.runes ~= nil then preset.runes = copyTable(settings.runes) end
    if settings.navigationEnabled ~= nil then preset.navigationEnabled = settings.navigationEnabled end
    -- if writing the ACTIVE shooter slot, re-load it so the runtime/UI picks it up.
    if isActiveProfile("shooter", i) and type(_G.loadShooterProfileByName) == "function" then
      pcall(_G.loadShooterProfileByName, slotName)
    end
    if type(_G.saveSettings) == "function" then pcall(_G.saveSettings) end
  end

  -- ----- public profile API (4 module types; ZB only specs targeting settings,
  --       but Amon's machinery supports all four, so we offer the superset) -----

  -- Magic shooter
  function Engine.magicShooterSwitchProfile(i) switchProfile("shooter", i) end
  function Engine.magicShooterGetProfile() return getProfile("shooter") end
  function Engine.magicShooterGetProfileName(i) return getProfileName("shooter", i) end
  function Engine.magicShooterGetProfileSettings(i) return getShooterSettings(i) end       -- superset
  function Engine.magicShooterSetProfileSettings(i, t) return setShooterSettings(i, t) end  -- superset

  -- Targeting (ZB specs get/set settings here)
  function Engine.targetingSwitchProfile(i) switchProfile("targeting", i) end
  function Engine.targetingGetProfile() return getProfile("targeting") end
  function Engine.targetingGetProfileName(i) return getProfileName("targeting", i) end
  function Engine.targetingGetProfileSettings(i) return getProfileSettingsFlat("targeting", i) end
  function Engine.targetingSetProfileSettings(i, t) return setProfileSettingsFlat("targeting", i, t) end

  -- Equipment
  function Engine.equipmentSwitchProfile(i) switchProfile("equipment", i) end
  function Engine.equipmentGetProfile() return getProfile("equipment") end
  function Engine.equipmentGetProfileName(i) return getProfileName("equipment", i) end
  function Engine.equipmentGetProfileSettings(i) return getProfileSettingsFlat("equipment", i) end       -- superset
  function Engine.equipmentSetProfileSettings(i, t) return setProfileSettingsFlat("equipment", i, t) end -- superset

  -- Healing
  function Engine.healingSwitchProfile(i) switchProfile("healing", i) end
  function Engine.healingGetProfile() return getProfile("healing") end
  function Engine.healingGetProfileName(i) return getProfileName("healing", i) end
  function Engine.healingGetProfileSettings(i) return getProfileSettingsFlat("healing", i) end       -- superset
  function Engine.healingSetProfileSettings(i, t) return setProfileSettingsFlat("healing", i, t) end -- superset

  -- =========================================================================
  -- 3.D  Environment / identity / alarms / scripts
  -- =========================================================================

  -- PARTIAL: no Amon "bot version" -> report the client/app version string.
  function Engine.getBotVersion()
    if g_app and type(g_app.getVersion) == "function" then
      local ok, v = pcall(function() return g_app.getVersion() end)
      if ok and v then return tostring(v) end
    end
    return "KoliseuClient"
  end

  -- PARTIAL: the scripts directory belongs to the scripting engine. Surface the
  -- virtual module-root path; the real OS path is not exposed to scripts.
  function Engine.getScriptsDirectory()
    if ctx and type(ctx.resolvePath) == "function" then
      local ok, p = pcall(ctx.resolvePath, "bot_scripts")
      if ok and p then return tostring(p) end
    end
    return unsupported("getScriptsDirectory", "")
  end
  function Engine.getScriptsDirectoryUtf8() return Engine.getScriptsDirectory() end

  -- STUB: no hashed-email user identity in this engine.
  function Engine.getUserId(_) return unsupported("getUserId", "") end
  -- STUB: no license system.
  function Engine.getLicenseTime() return unsupported("getLicenseTime", nil) end

  -- Alarms.  The alarm FIRE path in helper.lua reads the LIVE checkbox
  -- (getAlarmCheckbox:isChecked), which is file-local -- so writing only
  -- helperConfig.alarms desyncs and the alarm never triggers (gotcha #6). We reach
  -- the same checkbox widget via the (global) `helper` root and setChecked it: that
  -- fires the OTUI @onCheckChange -> modules.game_helper.onAlarmCheckboxChange
  -- (which writes helperConfig.alarms + updateAlarmSettings). We ALSO write the flag
  -- directly for the no-flip path (setChecked only fires the callback on a change).
  -- Amon alarm ids are NOT the ZB AlarmType enum; we accept the Amon string id
  -- ("alarmLowHealth") and stub unknown/ZB-int ids.
  local function alarmsTable()
    local cfg = _G.helperConfig
    if type(cfg) ~= "table" then return nil end
    if type(cfg.alarms) ~= "table" then cfg.alarms = {} end
    return cfg.alarms
  end

  -- Resolve the live alarm checkbox widget by id (or nil if the helper UI/panel is
  -- absent). Mirrors helper.lua's getAlarmCheckbox (alarmsPanel-scoped, recursive).
  local function alarmCheckbox(id)
    local h = _G.helper
    local panel = h and h.contentPanel and h.contentPanel:recursiveGetChildById("alarmsPanel")
    if not panel then return nil end
    return panel:recursiveGetChildById(id)
  end

  -- Sync one alarm: flag write (idempotent) + live checkbox setChecked (fires the
  -- helper callback only when it actually flips).
  local function applyAlarm(a, id, val)
    a[id] = val
    local cb = alarmCheckbox(id)
    if cb and type(cb.setChecked) == "function" then
      pcall(function() cb:setChecked(val) end)
    end
  end

  -- PARTIAL: enable/disable an Amon alarm by its string id; unknown/ZB-int ids stub.
  function Engine.setAlarm(alarmType, enable)
    local a = alarmsTable()
    if a and type(alarmType) == "string" then
      applyAlarm(a, alarmType, bool(enable))
      if type(_G.saveSettings) == "function" then pcall(_G.saveSettings) end
      return
    end
    return unsupported("setAlarm")
  end

  -- PARTIAL: query an Amon alarm by its string id. Prefer the live checkbox (the
  -- state the fire path reads); fall back to the stored flag when the UI is absent.
  function Engine.isAlarmEnabled(alarmType)
    if type(alarmType) == "string" then
      local cb = alarmCheckbox(alarmType)
      if cb and type(cb.isChecked) == "function" then
        local ok, v = pcall(function() return cb:isChecked() end)
        if ok then return v == true end
      end
      local a = alarmsTable()
      if a then return a[alarmType] == true end
    end
    return unsupported("isAlarmEnabled", false)
  end

  -- PARTIAL: derive "all alarms off" from the alarm flags (no single flag exists).
  function Engine.isAllAlarmsDisabled()
    local a = alarmsTable()
    if not a then return true end
    for _, v in pairs(a) do
      if v == true then return false end
    end
    return true
  end

  -- PARTIAL: bulk enable/disable the boolean alarm flags (+ sync each checkbox).
  function Engine.allAlarmsEnable(enable)
    local a = alarmsTable()
    if not a then return end
    local val = bool(enable)
    for k, v in pairs(a) do
      if type(v) == "boolean" then applyAlarm(a, k, val) end
    end
    if type(_G.saveSettings) == "function" then pcall(_G.saveSettings) end
  end

  -- Script lifecycle.  Delegate to the game_helper Scripting tab. Its public API is
  -- selection-based (selectScript + loadSelected/unloadSelected/reloadSelected), so
  -- these select the named script then act. There is no public by-name "is loaded"
  -- query, so isScriptLoaded is a stub.
  local function scriptingModule()
    local s = rawget(_G, "Scripting")
    return (type(s) == "table") and s or nil
  end

  -- PARTIAL: load (enable) a script by name.
  function Engine.loadScript(name)
    local S = scriptingModule()
    if not (S and type(S.selectScript) == "function" and type(S.loadSelected) == "function") then
      return unsupported("loadScript", false)
    end
    -- Guard: an unknown name would leave the PREVIOUS selection active (selectScript
    -- no-ops on unknown names) and act on the wrong script. Bail honestly instead.
    if type(S.hasScript) == "function" and not S.hasScript(name) then return false end
    local ok = pcall(function() S.selectScript(name); S.loadSelected() end)
    return ok and true or false
  end

  -- PARTIAL: unload (disable) a script by name.
  function Engine.unloadScript(name)
    local S = scriptingModule()
    if not (S and type(S.selectScript) == "function" and type(S.unloadSelected) == "function") then
      return unsupported("unloadScript", false)
    end
    if type(S.hasScript) == "function" and not S.hasScript(name) then return false end
    local ok = pcall(function() S.selectScript(name); S.unloadSelected() end)
    return ok and true or false
  end

  -- PARTIAL: reload a running script by name.
  function Engine.reloadScript(name)
    local S = scriptingModule()
    if not (S and type(S.selectScript) == "function" and type(S.reloadSelected) == "function") then
      return unsupported("reloadScript", false)
    end
    if type(S.hasScript) == "function" and not S.hasScript(name) then return false end
    local ok = pcall(function() S.selectScript(name); S.reloadSelected() end)
    return ok and true or false
  end

  -- VIABLE now: the scripting module exposes Scripting.isLoaded(name).
  function Engine.isScriptLoaded(name)
    local S = scriptingModule()
    if S and type(S.isLoaded) == "function" then return S.isLoaded(name) end
    return unsupported("isScriptLoaded", false)
  end

  -- PARTIAL: ZB loads a saved config by name. Amon's named full-config profiles are
  -- a different (coarser) layer with different semantics; no safe by-name apply is
  -- exposed, so this is a stub for now.
  function Engine.loadConfig(_) return unsupported("loadConfig", false) end

  return Engine
end
