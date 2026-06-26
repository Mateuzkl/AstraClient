# Helper UI Save/Load/Sync System

This document explains how the Helper module handles saving, loading, and syncing UI values with the configuration.

## Overview

The Helper uses a centralized configuration object (`helperConfig`) that stores all settings. The system has three main operations:

1. **Save** - UI changes → `helperConfig` → JSON file
2. **Load** - JSON file → `helperConfig` → UI widgets
3. **Sync** - `helperConfig` → UI widgets (without file operations)

## Core Components

### 1. helperConfig (Global Configuration Object)

Located at line ~1383 in `helper.lua`. This is the main configuration object that holds all settings:

```lua
helperConfig = {
    -- Healing settings
    spells = { { id = 0, percent = 80, priority = 1 }, ... },
    potions = { { id = 0, percent = 90, priority = 1 }, ... },
    healingEnabled = false,
    autoHealingEnabled = false,

    -- Friend healing
    friendhealing = { { name = "", percent = 0, enabled = false }, ... },
    friendhealingParty = false,
    friendhealingGuild = false,

    -- Party management
    partyManagement = {
        inviteParty = { all = false, vip = false, guild = false, friend = false },
        autoAcceptParty = { all = false, vip = false, guild = false, friend = false }
    },

    -- ... many more settings
}
```

### 2. Profile System

Profiles are stored as JSON files in `/helper/profiles/`:
- `saveProfileToFile(profileName, profileData)` - Saves to JSON
- `loadProfileFromFile(profileName)` - Loads from JSON
- Files use `json.encode()` and `json.decode()`

## How Save Works

### Widget → helperConfig

When a user interacts with a widget (checkbox, combobox, etc.), the `onCheckChange` or `onOptionChange` callback updates `helperConfig`:

```lua
checkbox.onCheckChange = function(self)
    helperConfig.someOption = self:isChecked()
end
```

### helperConfig → File

When user clicks "Save Profile":
1. Current `helperConfig` is copied to profile data
2. `saveProfileToFile(profileName, profileData)` is called
3. Data is encoded to JSON and written to `/helper/profiles/{name}.json`

```lua
function saveProfileToFile(profileName, profileData)
    local profilesDir = ensureProfilesDirectory()
    local profileFile = profilesDir .. "/" .. profileName .. ".json"
    local jsonData = json.encode(profileData, 2)
    g_resources.writeFileContents(profileFile, jsonData)
end
```

## How Load Works

### File → helperConfig

When loading a profile:
1. `loadProfileFromFile(profileName)` reads JSON file
2. JSON is decoded to Lua table
3. Values are copied to `helperConfig`

```lua
function loadProfileFromFile(profileName)
    local profileFile = "/helper/profiles/" .. profileName .. ".json"
    local fileContents = g_resources.readFileContents(profileFile)
    return json.decode(fileContents)
end
```

### helperConfig → UI (Sync)

After loading config, `onLoadHelperData()` syncs values to UI widgets:

```lua
function onLoadHelperData()
    -- Helper function to set checkbox without triggering callbacks
    local function setCheckboxState(widget, checked)
        if not widget or widget:isChecked() == checked then
            return
        end
        local oldCallback = widget.onCheckChange
        widget.onCheckChange = nil          -- Remove callback
        widget:setChecked(checked)          -- Set value
        widget.onCheckChange = oldCallback  -- Restore callback
    end

    -- Sync checkboxes
    setCheckboxState(panel:getChildById("enableHealing"), helperConfig.healingEnabled == true)

    -- Sync comboboxes
    local combo = panel:getChildById("someCombo")
    if combo then
        combo:setCurrentOption(tostring(helperConfig.someValue))
    end

    -- Sync text inputs
    local textInput = panel:getChildById("someInput")
    if textInput then
        textInput:setText(helperConfig.someText or "")
    end
end
```

## Key Pattern: setCheckboxState

The `setCheckboxState` helper is critical for avoiding infinite loops:

```lua
local function setCheckboxState(widget, checked)
    if not widget or widget:isChecked() == checked then
        return  -- Skip if already correct state
    end
    local oldCallback = widget.onCheckChange
    widget.onCheckChange = nil      -- Temporarily remove callback
    widget:setChecked(checked)       -- Set the value
    widget.onCheckChange = oldCallback  -- Restore callback
end
```

**Why?** Without this pattern:
1. Load sets checkbox → triggers `onCheckChange`
2. `onCheckChange` updates config → may trigger save
3. Save triggers load → infinite loop

## Sync Locations

There are two main sync functions:

### 1. `onLoadHelperData()` (line ~14602)
Called when:
- Profile is loaded
- Character logs in
- Settings are restored

Syncs ALL UI widgets from `helperConfig`.

### 2. Inline sync in profile loading (line ~4100)
Additional sync for specific sections like Party Management:

```lua
-- SYNC PARTY MANAGEMENT
if helper and helper.contentPanel then
    local partyContent = helper.contentPanel:recursiveGetChildById("partyManagementContent")
    if partyContent and helperConfig.partyManagement then
        setCheckboxState(partyContent:recursiveGetChildById("invitePartyAll"),
                        helperConfig.partyManagement.inviteParty.all == true)
        -- ... more checkboxes
    end
end
```

## Adding New Settings

### Step 1: Add to helperConfig defaults

```lua
helperConfig = {
    -- existing settings...
    myNewSetting = false,  -- Add default value
}
```

### Step 2: Add UI callback to save value

```lua
local myCheckbox = panel:getChildById("myNewCheckbox")
myCheckbox.onCheckChange = function(self)
    helperConfig.myNewSetting = self:isChecked()
end
```

### Step 3: Add to onLoadHelperData() to load value

```lua
function onLoadHelperData()
    -- existing code...
    setCheckboxState(panel:getChildById("myNewCheckbox"),
                    helperConfig.myNewSetting == true)
end
```

## Best Practices

1. **Always use `== true`** when checking booleans from config (handles nil/undefined)
2. **Use setCheckboxState()** when setting checkbox values programmatically
3. **Use recursiveGetChildById()** when widget is nested in panels
4. **Check widget exists** before calling methods: `if widget then ... end`
5. **Temporarily disable callbacks** when setting values from config to avoid loops

## File Locations

| File | Purpose |
|------|---------|
| `/helper/profiles/*.json` | Individual profile settings |
| `/helper/config.json` | Global settings (auto-load, profile list) |

## Snapshot System

For session continuity (reconnects), there's also a snapshot system:

- `captureSessionSnapshot()` - Saves current toggle states before logout
- `restoreSessionSnapshot()` - Restores states after reconnect

This preserves enabled/disabled states across disconnections without requiring full profile reload.
