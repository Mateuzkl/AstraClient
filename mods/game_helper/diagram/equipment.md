# Equipment Helper Module Documentation

## Overview

The Equipment Helper module automatically equips and unequips rings and amulets based on player health/mana conditions and game states. It supports unlimited rules with dual conditions and player state filters.

## Architecture

```
+------------------+     +---------------------+     +------------------+
|   helper.otmod   | --> | equip_panel.lua     | <-- |   helper.lua     |
|  (script loader) |     | (game_helper.equip)|     | (checkEquipItems)|
+------------------+     +---------------------+     +------------------+
                                   |
                                   v
                         +-------------------+
                         | equip_panel.otui  |
                         | (UI form & rules) |
                         +-------------------+
```

## Module Structure

### File: `equip_panel.lua`

Contains all equipment logic under the `modules.game_helper.equip` namespace.

### Exposed Functions

| Function                                     | Description                               |
| -------------------------------------------- | ----------------------------------------- |
| `equip.init(helperWindow)`                   | Initialize panel and setup event handlers |
| `equip.terminate()`                          | Cleanup on module unload                  |
| `equip.getPanel()`                           | Returns the equipment panel widget        |
| `equip.checkEquipItems()`                    | Main check loop - evaluates and executes  |
| `equip.toggleEquipment(enabled)`             | Enable/disable equipment system           |
| `equip.isEnabled()`                          | Returns if system is enabled              |
| `equip.clearForm()`                          | Reset form to default values              |
| `equip.addOrUpdateRule()`                    | Add new or update existing rule           |
| `equip.removeRule(ruleId)`                   | Remove rule with confirmation dialog      |
| `equip.updateRulesList()`                    | Refresh visual rules list                 |
| `equip.selectItem(targetButton, targetType)` | Start item selection from game            |
| `equip.loadConfig(savedConfig)`              | Load saved configuration                  |
| `equip.saveConfig()`                         | Save configuration to JSON                |
| `equip.updateUI()`                           | Update UI elements after config load      |

## Rule Configuration

### Rule Structure

```lua
{
  id = 1,                      -- Unique rule identifier
  itemId = 3051,               -- Item ID (unequipped version)
  equippedId = 3088,           -- Item ID when equipped (for decay items)
  name = "Energy Ring",        -- Item display name
  slotType = "ring",           -- "ring" or "amulet"

  -- Condition 1 (required)
  cond1Resource = "hp%",       -- "hp%", "mp%", "hp", "mp"
  cond1Operator = "<=",        -- "<=", ">=", "<", ">"
  cond1Value = 50,             -- Threshold value

  -- Logic between conditions
  condLogic = "and",           -- "and" or "or"

  -- Condition 2 (optional)
  cond2Enabled = false,        -- Enable second condition
  cond2Resource = "mp%",
  cond2Operator = ">=",
  cond2Value = 20,

  -- Action
  action = "equip",            -- "equip" or "unequip"

  -- Skip if equipped
  skipIfEquipped = false,      -- Skip rule if specific item equipped
  skipItemId = 0,              -- Item ID to check
  skipItemName = "",
  skipItemSlotType = "",

  -- Player state conditions (OR logic)
  conditions = {
    rooted = false,            -- Only when rooted
    feared = false,            -- Only when feared
    pz = false,                -- Only in Protection Zone
    nonPz = false,             -- Only outside PZ
    utamoVita = false          -- Only with Mana Shield active
  },

  enabled = true               -- Rule active/inactive
}
```

## UI Components

### Configuration Form

```
+----------------------------------------------------------+
|                    Equip Helper                          |
+----------------------------------------------------------+
| Item: [🔲] (click to select)                 [Clear]     |
|                                                          |
| When: [HP%] [<=] [50]                                    |
|       [AND] ☐ 2nd condition                              |
|             [MP%] [>=] [20]                              |
|                                                          |
| Action: ☑ Equip  ☐ Unequip                              |
|                                                          |
| ☐ Skip if equipped: [🔲]                                |
|                                                          |
| Conditions:                                              |
| ☐ Rooted  ☐ Feared  ☐ PZ                                |
| ☐ non-PZ  ☐ Utamo Vita                                  |
+----------------------------------------------------------+
| Rules:                                            [Add]   |
| +------------------------------------------------------+ |
| | 🔲 Energy Ring - Equip if HP%<=50    ☑        [X]  | |
| | 🔲 Life Ring - Equip if HP%<=30      ☑        [X]  | |
| +------------------------------------------------------+ |
+----------------------------------------------------------+
| ☑ Enable Equipment                        [Set Key]     |
+----------------------------------------------------------+
```

### Rule List Item

Each rule displays:

- Item icon (24x24)
- Rule summary text (e.g., "Equip if HP%<=50 AND MP%>=20")
- Enable/disable checkbox
- Remove button (X)

## Decay Item Mapping

The system handles items that change ID when equipped:

```lua
-- Rings
[3051] = 3088,   -- Energy Ring
[3052] = 3093,   -- Life Ring
[3053] = 3091,   -- Time Ring
[3006] = 3083,   -- Ring of Healing
[3098] = 3099,   -- Ring of the Sky
[3048] = 3049,   -- Might Ring
[3050] = 3097,   -- Stealth Ring
[3007] = 3084,   -- Dwarven Ring
[16114] = 16264, -- Prismatic Ring
[23529] = 23530, -- Ring of Souls

-- Amulets
[3056] = 3086,   -- Amulet of Loss
[3057] = 3085,   -- Stone Skin Amulet
[3081] = 3082,   -- Amulet of Life
[3089] = 3094,   -- Elven Amulet
[3095] = 3096,   -- Dragon Necklace
[16115] = 16116, -- Prismatic Necklace
[23542] = 23526, -- Amulet of the Cobra
```

## Execution Flow

```
checkEquipItems() called by helper event system
         |
         v
+------------------+
| Pre-conditions   |
| - Game online?   |
| - Helper enabled?|
| - Equip enabled? |
+------------------+
         |
    All passed?
    /        \
  No          Yes
   |           |
   v           v
 Return   +--------------------------+
          | Process UNEQUIP rules    |
          | (priority: first)        |
          +--------------------------+
                     |
              Found & executed?
                /        \
              Yes         No
               |           |
               v           v
            Return   +--------------------------+
                     | Process EQUIP rules      |
                     | (with unequip blocking)  |
                     +--------------------------+
                              |
                       Found & executed?
                         /        \
                       Yes         No
                        |           |
                        v           v
                     Return      Return
```

### Rule Evaluation (tryExecuteRule)

```
+---------------------------+
| 1. Check player conditions|
|    (rooted, feared, etc.) |
+---------------------------+
         |
    Conditions met?
    /        \
  No          Yes
   |           |
   v           v
 Skip     +---------------------------+
          | 2. Check skip if equipped |
          +---------------------------+
                     |
              Should skip?
              /        \
            Yes         No
             |           |
             v           v
           Skip    +--------------------------+
                   | 3. For EQUIP: Check if   |
                   |    unequip rule active   |
                   +--------------------------+
                              |
                       Blocked by unequip?
                          /        \
                        Yes         No
                         |           |
                         v           v
                       Skip    +--------------------+
                               | 4. Check HP/MP     |
                               |    conditions      |
                               +--------------------+
                                        |
                                  Conditions met?
                                   /        \
                                 No          Yes
                                  |           |
                                  v           v
                                Skip    +-----------------+
                                        | 5. Execute      |
                                        |    action       |
                                        +-----------------+
                                              |
                                              v
                                        +---------------+
                                        | equipItem()   |
                                        | or            |
                                        | unequipItem() |
                                        +---------------+
```

## Rule Priority System

### Unequip Priority

UNEQUIP rules are processed **before** EQUIP rules to ensure:

- Unequipping takes priority when conditions are met
- Prevents unwanted re-equipping in same cycle

### Equip Blocking

When processing EQUIP rules, the system checks if any UNEQUIP rule for the same item is currently active:

- If yes: Block the equip action
- If no: Allow equip if conditions met

This prevents conflicts between equip/unequip rules for the same item.

## Condition Checking

### Resource Conditions

```lua
-- Percentage-based
hp% = (currentHP / maxHP) * 100
mp% = (currentMP / maxMP) * 100

-- Absolute values
hp = currentHP
mp = currentMP
```

### Operators

- `<=` : Less than or equal
- `>=` : Greater than or equal
- `<` : Less than
- `>` : Greater than

### Dual Conditions

When `cond2Enabled = true`:

- **AND**: Both conditions must be true
- **OR**: At least one condition must be true

### Player State Conditions

Multiple state conditions use **OR logic**:

- If ANY selected state is active, rule can proceed
- If NONE selected, rule always proceeds

Available states:

- **Rooted**: Player is rooted (cannot move)
- **Feared**: Player is feared
- **PZ**: Player in Protection Zone
- **non-PZ**: Player NOT in Protection Zone
- **Utamo Vita**: legacy Mana Shield active (`PlayerStates.ManaShield`)

## Item Selection

### Item Selection Flow

```
Click "itemButton" or "skipItemButton"
         |
         v
+------------------+
| grabMouse()      |
| Hide helper      |
| Show crosshair   |
+------------------+
         |
    User clicks item
         |
         v
+------------------+
| Validate item    |
| - Is ring/amulet?|
| - Has cloth slot?|
+------------------+
         |
    Valid item?
    /        \
  No          Yes
   |           |
   v           v
 Error    +------------------+
          | Update UI        |
          | - Show icon      |
          | - Set name       |
          | - Show Clear btn |
          +------------------+
```

## Hotkey System

### Configuration

Equipment system supports hotkey toggle via `manageHotkeys("Enable/Disable Equipment")`.

### Hotkey Registration Flow

```
1. User sets hotkey in dialog
   ↓
2. Store in helperConfig.equipmentHotkeyCode
   ↓
3. Create toggle closure function
   ↓
4. Bind with g_keyboard.bindKeyDown()
   ↓
5. Save to helper.json
   ↓
6. On next login:
   - loadSettings()
   - registerSavedHotkeys()
   - Hotkey restored
```

### Toggle Function

```lua
-- When hotkey pressed:
1. Get current state via equip.isEnabled()
2. Toggle state via equip.toggleEquipment(!state)
3. Update checkbox in Equipment Panel
4. Sync with Shortcut Panel
```

## Shortcut Panel Integration

### Sync Flow

```
Equipment Panel Checkbox
         |
         v
   toggleEquipment(enabled)
         |
         v
  +----------------------------------+
  | _Helper.Shortcut.syncButton(    |
  |   'shortcutEquipment', enabled) |
  +----------------------------------+
         |
         v
   Update shortcut mark
```

### Bidirectional Sync

**Panel → Shortcut:**

- User clicks "Enable Equipment" checkbox
- Calls `toggleEquipment()`
- Syncs to shortcut panel

**Shortcut → Panel:**

- User clicks shortcut button
- Calls `toggleEquipment()`
- Updates panel checkbox

**Hotkey → Both:**

- User presses hotkey
- Calls `toggleEquipment()`
- Updates both UIs

## Configuration Storage

Settings are stored in `helper.json`:

```json
{
  "equipmentHelper": {
    "enabled": true,
    "rules": [
      {
        "id": 1,
        "itemId": 3051,
        "equippedId": 3088,
        "name": "Energy Ring",
        "slotType": "ring",
        "cond1Resource": "hp%",
        "cond1Operator": "<=",
        "cond1Value": 50,
        "condLogic": "and",
        "cond2Enabled": false,
        "cond2Resource": "mp%",
        "cond2Operator": ">=",
        "cond2Value": 20,
        "action": "equip",
        "skipIfEquipped": false,
        "skipItemId": 0,
        "skipItemName": "",
        "skipItemSlotType": "",
        "conditions": {
          "rooted": false,
          "feared": false,
          "pz": false,
          "nonPz": false,
          "utamoVita": false
        },
        "enabled": true
      }
    ]
  },
  "equipmentHotkeyCode": "Ctrl+E",
  "equipmentHotkeyFunc": null
}
```

## Save/Load Cycle

```
+----------------+
| User adds rule |
+----------------+
         |
         v
  equip.addOrUpdateRule()
         |
         v
    saveSettings()
         |
         v
  +-------------------+
  | Write helper.json |
  +-------------------+


On next login:

  +------------------+
  | Read helper.json |
  +------------------+
         |
         v
   loadSettings()
         |
         v
  equip.loadConfig(savedConfig)
         |
         v
  +------------------+
  | Restore rules    |
  | Restore enabled  |
  | Restore hotkey   |
  +------------------+
         |
         v
   equip.updateUI()
         |
         v
  +------------------+
  | Update checkbox  |
  | Update rules list|
  +------------------+
```

## Event System Integration

The Equipment system integrates with the Helper's event system:

### Registration

```lua
-- In helper.lua
eventTable.checkEquipItems = {
  minDelay = 100,
  maxDelay = 500,
  action = function()
    if modules.game_helper and modules.game_helper.equip then
      modules.game_helper.equip.checkEquipItems()
    end
  end
}
```

### Check Conditions

Before executing, `checkEquipItems()` verifies:

1. Game is online (`g_game.isOnline()`)
2. Helper automatic functions enabled
3. Equipment system enabled
4. Player exists

## Example Use Cases

### Use Case 1: Energy Ring Auto-Equip

**Goal**: Equip Energy Ring when HP drops below 50%

**Configuration**:

- Item: Energy Ring
- Condition 1: HP% <= 50
- Action: Equip

**Behavior**:

- Player takes damage, HP drops to 48%
- System detects HP% <= 50
- Equips Energy Ring from backpack
- Next cycle: Player heals to 60%
- Ring remains equipped (no unequip rule)

### Use Case 2: SSA in PvP with Unequip

**Goal**: Equip SSA when low HP outside PZ, unequip inside PZ

**Rule 1 - Equip**:

- Item: Stone Skin Amulet
- Condition 1: HP% <= 70
- Player State: non-PZ
- Action: Equip

**Rule 2 - Unequip**:

- Item: Stone Skin Amulet
- Player State: PZ
- Action: Unequip

**Behavior**:

- Player in PvP zone, HP drops to 65%
- Rule 1 triggers: Equip SSA
- Player enters temple (PZ)
- Rule 2 triggers: Unequip SSA
- Saves SSA charges while safe

### Use Case 3: Ring Rotation with Skip

**Goal**: Equip Energy Ring low HP, but skip if Life Ring equipped

**Rule 1 - Life Ring (priority)**:

- Item: Life Ring
- Condition 1: HP% <= 30
- Action: Equip

**Rule 2 - Energy Ring (fallback)**:

- Item: Energy Ring
- Condition 1: HP% <= 50
- Skip if equipped: Life Ring
- Action: Equip

**Behavior**:

- HP drops to 45%
- Rule 2 wants to equip Energy Ring
- Life Ring not equipped
- Equips Energy Ring
- HP continues to drop to 28%
- Rule 1 triggers: Equip Life Ring (replaces Energy)
- HP recovers to 45%
- Rule 2 blocked: Life Ring equipped (skip active)
- Life Ring remains equipped

### Use Case 4: Utamo Vita Safety

**Goal**: Unequip Energy Ring when using Utamo Vita (avoid wasting charges)

**Rule**:

- Item: Energy Ring
- Player State: Utamo Vita
- Action: Unequip

**Behavior**:

- Player casts Utamo Vita
- System detects Mana Shield state
- Unequips Energy Ring
- Ring charges preserved while shielded

## Best Practices

### Rule Design

1. **Use Unequip for Safety**: Create unequip rules for scenarios where you don't need the item
2. **Leverage Skip**: Prevent lower-priority items from replacing higher-priority ones
3. **Player States**: Use PZ/non-PZ conditions to prevent wasting charges
4. **Dual Conditions**: Combine HP% and MP% for precise control

### Performance

- System runs in event cycle (100-500ms interval)
- Only ONE action per cycle (prevents spam)
- Rules evaluated in order: Unequip → Equip
- Efficient item lookup via container scanning

### Safety

- Confirmation dialog before deleting rules
- Clear button hidden until item selected
- Form validation before adding rules
- Hotkey conflicts prevented by system

## Common Issues & Solutions

### Issue: Hotkey doesn't work after restart

**Solution**: System auto-registers saved hotkeys

- Check `helper.json` contains `equipmentHotkeyCode`
- Verify `registerSavedHotkeys()` is called on login
- Check console for keyboard binding errors

### Issue: Rule not triggering

**Debug checklist**:

1. ✓ Equipment system enabled?
2. ✓ Helper automatic functions enabled?
3. ✓ Rule checkbox enabled?
4. ✓ Conditions actually met?
5. ✓ Skip condition not blocking?
6. ✓ Unequip rule not blocking equip?
7. ✓ Item exists in backpack?

### Issue: Wrong item equipped

**Likely causes**:

- Decay mapping incorrect
- Item ID changed between equipped/unequipped
- Multiple rules conflicting

**Solution**:

- Check `decayItemMapping` table
- Ensure only one rule per item/action combination
- Use skip conditions to prevent conflicts

## Integration Points

### With Helper Core

- `_Helper.isHelperAutomaticFunctionsEnabled()`: Master toggle check
- `_Helper.saveSettings()`: Configuration persistence
- Event system: Periodic execution

### With Shortcut Panel

- `_Helper.Shortcut.syncButton()`: State synchronization
- `_Helper.Shortcut.updateMark()`: Visual feedback
- Bidirectional toggle support

### With Hotkey System

- `manageHotkeys()`: Hotkey configuration dialog
- `registerSavedHotkeys()`: Restore on login
- `unregisterAllHelperHotkeys()`: Cleanup on logout

## Future Enhancements

Potential improvements:

- Support for other equipment slots (helm, armor, etc.)
- Time-based conditions (equip after X seconds)
- Monster count conditions (equip if 3+ monsters nearby)
- Cooldown between equip/unequip actions
- Rule templates/presets
- Import/export rules between characters
