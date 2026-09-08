# Magic Shooter - Unified Panel Architecture

## Overview

The Magic Shooter system combines spells and runes into a single unified panel with:

- Dynamic rules list (unlimited entries)
- Preset/profile management
- Harmony threshold support for Monk vocation
- Priority determined by list order (top = highest priority)

---

## System Architecture

```mermaid
graph TB
    subgraph "UI Layer"
        MP[magic_shooter_panel.lua] -->|manages| UI[magic_shooter_panel.otui]
        UI --> PRS[Presets Section]
        UI --> FRM[Config Form]
        UI --> LST[Rules List]
        UI --> BTN[Enable Buttons]
    end

    subgraph "Logic Layer"
        MS[classes/magic_shooter.lua] -->|check()| PROC[Process Rules]
        PROC --> SPELL[Cast Spell]
        PROC --> RUNE[Use Rune]
    end

    subgraph "Data Layer"
        CFG[helperConfig] --> PRF[shooterProfiles]
        PRF --> RULES[rules array]
    end

    MP -->|saves/loads| CFG
    MS -->|reads| PRF
```

---

## Data Structure

```mermaid
classDiagram
    class HelperConfig {
        +magicShooterEnabled bool
        +autoTargetEnabled bool
        +autoTargetMode int
        +selectedShooterProfile string
        +shooterProfiles map~string,Profile~
        +ignoreMonsterList string
        +priorityMonsterList string
    }

    class ShooterProfile {
        +rules[] Rule
        +autoTargetMode string
    }

    class Rule {
        +id int
        +type string
        +spellId int
        +itemId int
        +name string
        +words string
        +manaPercent int
        +healthPercent int
        +creatures int
        +harmonyThreshold int
        +selfCast bool
        +castIfTrapped bool
        +rangedMonsterNames string
        +enabled bool
    }

    HelperConfig "1" *-- "*" ShooterProfile
    ShooterProfile "1" *-- "*" Rule

    note for Rule "type: 'spell' or 'rune'\nspellId: for spells\nitemId: for runes\nwords: spell incantation\nharmonyThreshold: 0-5 (Monk only)\ncastIfTrapped: only cast when player cannot walk\nrangedMonsterNames: comma-separated monster names (ranged spells only)"
```

---

## UI Panel Layout

```
+------------------------------------------+
|          Magic Shooter Helper            |
+------------------------------------------+
| Presets: [Default v] [Set Key] [?]       |
|          [Remove] [Rename] [New Preset]  |
+------------------------------------------+
| Select: [Spell][Rune]  Spell Name [Clear]|
+------------------------------------------+
| Creatures  Mana %    Harmony             |  <- Labels Row
| [1+ v]   [-80%+]   [-0+]                 |  <- Controls Row
+------------------------------------------+
| Ranged Monster Names:                    |
| [minotaur archer, minotaur mage   ]      |  <- Only for ranged spells
+------------------------------------------+
| Rules:              [_] Cast If Trapped [Add]  |
| +--------------------------------------+ |
| |[S][icon] exori gran  M:80% C:1+ [v][x]| |  <- Shows words
| |[S][icon] exori mas   M:80% C:2+ T [v][x]| |  <- T = trapped
| |[R][icon] SD Rune     C:1+       [v][x]| |
| +--------------------------------------+ |
+------------------------------------------+
| Ignore Monster List                      |
| [rat, bug, snake...            ] [Apply] |
+------------------------------------------+
| My Priority List In Order                |  <- Only visible when
| [dragon, dragon lord, demon    ] [Apply] |     Mode J is selected
+------------------------------------------+
| [ ] Auto Target [A v] [?]       [Set Key]|
| [ ] Enable Shooter              [Set Key]|
| [    Set Key (Target/Shooter)          ] |
+------------------------------------------+
```

### UI Elements

| Element               | Description                                                                |
| --------------------- | -------------------------------------------------------------------------- |
| `[S]` / `[R]`         | Type indicator (Spell=blue, Rune=orange)                                   |
| `[icon]`              | Spell icon or rune item                                                    |
| `words`               | Spell incantation (e.g., "exori gran")                                     |
| `M:X%`                | Minimum mana percentage                                                    |
| `HP:X%`               | Minimum health percentage                                                  |
| `C:X+`                | Minimum creatures count (around player for all spell types)                |
| `H:X`                 | Harmony threshold (Monk only, shown if > 0)                                |
| `T`                   | Cast If Trapped indicator (shown when enabled)                             |
| `R`                   | Ranged Monster Names configured (shown when set)                           |
| `[v]`                 | Enable/disable checkbox                                                    |
| `[x]`                 | Remove button                                                              |
| `[_] Cast If Trapped` | Checkbox to only cast when player cannot walk in any direction             |
| Ignore Monster List   | Comma-separated list of monsters to ignore when targeting                  |
| Priority List         | Comma-separated ordered list for Mode J targeting (highest priority first) |
| Ranged Monster Names  | Only for ranged spells (237, 238, 280) - filters creatures by name         |

---

## Rule Processing Flow

```mermaid
flowchart TD
    START([MagicShooter.check]) --> A{Helper Enabled?}
    A -->|No| RET1([Return])
    A -->|Yes| PZ{PZ Handler}

    PZ -->|In PZ| RET_PZ([Return - Blocked])
    PZ -->|Not in PZ| B{Shooter Enabled?}

    B -->|No| RET2([Return])
    B -->|Yes| C{Profile Exists?}

    C -->|No| RET3([Return])
    C -->|Yes| D[Get Rules from Profile]

    D --> E{Has Rules?}
    E -->|No| RET4([Return])
    E -->|Yes| F[Build Unified List]

    F --> G[Sort by Priority<br>index in array]
    G --> H[For Each Rule]

    H --> I{Rule Type?}
    I -->|Spell| J[Process Spell]
    I -->|Rune| K[Process Rune]

    J --> L{Cast Success?}
    K --> L

    L -->|Yes| RET5([Return - Done])
    L -->|No| M{More Rules?}

    M -->|Yes| H
    M -->|No| RET6([Return])
```

---

## Spell Processing

```mermaid
flowchart TD
    START([Process Spell]) --> A{Has Enough Mana?}
    A -->|No| SKIP1([Skip])
    A -->|Yes| B{Valid Vocation?}

    B -->|No| SKIP2([Skip])
    B -->|Yes| C{Player Has Spell?}

    C -->|No| SKIP3([Skip])
    C -->|Yes| D{Harmony Check}

    D --> E{harmonyThreshold > 0?}
    E -->|No| F[Continue]
    E -->|Yes| G{Current Harmony >= Threshold?}

    G -->|No| SKIP4([Skip - Not Enough Harmony])
    G -->|Yes| F

    F --> H{Health % >= Config?}
    H -->|No| SKIP5([Skip])
    H -->|Yes| H2{Mana % >= Config?}

    H2 -->|No| SKIP5B([Skip])
    H2 -->|Yes| H3{Cast If Trapped Check}

    H3 --> H4{castIfTrapped enabled?}
    H4 -->|No| I[Continue to Target/Area]
    H4 -->|Yes| H5{Player is Trapped?}

    H5 -->|No| SKIP5C([Skip - Not Trapped])
    H5 -->|Yes| I

    I --> J{Creatures Around >= Config?}
    J -->|No| SKIP6([Skip])
    J -->|Yes| K{On Cooldown?}

    K -->|Yes| SKIP7([Skip])
    K -->|No| L[CAST SPELL]

    L --> END([Success])
```

### Creatures Threshold Behavior

The creatures threshold now works consistently for **all spell types**:

| Spell Type        | Creatures Check     | Behavior                             |
| ----------------- | ------------------- | ------------------------------------ |
| Area spells       | Count in area       | Cast when X+ creatures in spell area |
| Targetable spells | Count around player | Cast when X+ creatures around player |
| Support spells    | Count around player | Cast when X+ creatures around player |
| Self-cast spells  | Count around player | Cast when X+ creatures around player |

**Note:** The creatures dropdown is always enabled for all spell types, allowing users to configure when spells should be cast based on how many creatures are nearby.

---

## Harmony System (Monk Only)

```mermaid
flowchart TD
    subgraph "UI Visibility"
        A{Is Monk Vocation?} -->|Yes| B[Show Harmony Controls]
        A -->|No| C[Hide Harmony Controls]
    end

    subgraph "Spell Selection"
        SEL[Spell Selected] --> SP{Is Spender Spell?}
        SP -->|Yes| MIN[Prefill Harmony = 1 default, 0 still allowed]
        SP -->|No| DEF[Allow Harmony 0-5]
    end

    subgraph "Spell Evaluation"
        D[Read harmonyThreshold] --> E{Threshold > 0?}
        E -->|No| F[Cast normally]
        E -->|Yes| G[Get player:getHarmony]
        G --> H{Harmony >= Threshold?}
        H -->|Yes| F
        H -->|No| I[Skip spell]
    end
```

### Spender Spells

Spender spells are Monk-specific spells that consume Harmony points. They **default** to a Harmony threshold of 1, but **0 is allowed** and means "no Harmony requirement":

| Spell Name           | Words              | Type    |
| -------------------- | ------------------ | ------- |
| Tiger Clash          | exori infir nia    | Spender |
| Greater Tiger Clash  | exori nia          | Spender |
| Devastating Knockout | exori gran nia     | Spender |
| Sweeping Takedown    | exori mas nia      | Spender |
| Spiritual Outburst   | exori gran mas nia | Spender |

When a Monk selects a spender spell:

- The Harmony input is prefilled with "1" only when it is currently 0/empty
- Setting Harmony to "0" is kept as-is -- the spell is then cast with no Harmony
  requirement, exactly like a non-spender
- Values 0-5 are allowed (max 5)

### Harmony Configuration Examples

| Spell        | Harmony Threshold | Behavior                       |
| ------------ | ----------------- | ------------------------------ |
| Basic Attack | 0                 | Always cast                    |
| Tiger Clash  | 0                 | Always cast (no Harmony gate)  |
| Tiger Clash  | 1 (default)       | Cast with 1+ Harmony           |
| Medium Spell | 3                 | Only cast with 3+ Harmony      |
| Strong Spell | 5                 | Only cast at max Harmony       |

---

## Panel Functions (magic_shooter_panel.lua)

```mermaid
graph TD
    subgraph "Form Management"
        CF[clearForm] --> GF[getFormData]
        GF --> SF[setFormData]
    end

    subgraph "Spell/Rune Selection"
        SS[selectSpell] -->|callback| HSS[handleSpellSelection]
        SR[selectRune] -->|callback| HSR[handleRuneSelection]
    end

    subgraph "Rules Management"
        AUR[addOrUpdateRule] --> URL[updateRulesList]
        RR[removeRule] --> URL
        MU[moveRuleUp] --> URL
        MD[moveRuleDown] --> URL
        TRE[toggleRuleEnabled] --> SS2[saveSettings]
    end

    subgraph "Presets Management"
        LPO[loadProfileOptions] --> OPC[onPresetChange]
        OPC --> URL
    end

    subgraph "Initialization"
        INIT[init] --> SH[setupHandlers]
        SH --> LPO
        SH --> URL
    end
```

---

## Event Handlers

```mermaid
sequenceDiagram
    participant User
    participant Panel as magic_shooter_panel
    participant Profile as shooterProfile
    participant Logic as magic_shooter.lua

    User->>Panel: Click Spell Slot
    Panel->>Panel: selectSpell()
    Panel->>User: Show Spell Selector

    User->>Panel: Select Spell
    Panel->>Panel: handleSpellSelection()
    Panel->>Panel: Update form fields

    User->>Panel: Click Add
    Panel->>Panel: addOrUpdateRule()
    Panel->>Panel: Validate (no duplicates)
    Panel->>Profile: Save rule to profile.rules[]
    Panel->>Panel: updateRulesList()
    Panel->>Panel: clearForm()

    Note over Logic: On game tick...
    Logic->>Profile: Read rules
    Logic->>Logic: Process by priority (index)
    Logic->>Logic: Cast first valid spell/rune
```

---

## Duplicate Prevention

```mermaid
flowchart TD
    A[addOrUpdateRule called] --> B{Editing existing?}
    B -->|Yes| C[Get editingRuleId]
    B -->|No| D[New rule]

    C --> E[Loop through rules]
    D --> E

    E --> F{Same type?}
    F -->|No| G[Continue loop]
    F -->|Yes| H{Same ID?}

    H -->|No| G
    H -->|Yes| I{Is editing this rule?}

    I -->|Yes| G
    I -->|No| J[Show error message]

    G --> K{More rules?}
    K -->|Yes| E
    K -->|No| L[Proceed with add/update]

    J --> M([Return - Duplicate found])
```

---

## Selection Highlight

```mermaid
stateDiagram-v2
    [*] --> NoSelection: Form cleared

    NoSelection --> ItemSelected: Click on list item
    ItemSelected --> NoSelection: clearForm() called
    ItemSelected --> ItemSelected: Click different item

    state ItemSelected {
        [*] --> Highlighted
        Highlighted: background-color: #3a6a3a88
        Highlighted: button shows "UPDATE"
    }

    state NoSelection {
        [*] --> Normal
        Normal: background-color: #00000022
        Normal: button shows "ADD"
    }
```

---

## Delete Confirmation

```mermaid
sequenceDiagram
    participant User
    participant Panel
    participant Dialog as displayGeneralBox
    participant Profile

    User->>Panel: Click remove button
    Panel->>Dialog: Show confirmation
    Dialog->>User: "Are you sure you want to remove X?"

    alt User clicks Yes
        User->>Dialog: Click Yes
        Dialog->>Panel: confirmCallback()
        Panel->>Profile: Remove rule
        Panel->>Panel: updateRulesList()
        Panel->>Panel: clearForm() if editing
        Panel->>Panel: saveSettings()
    else User clicks No
        User->>Dialog: Click No
        Dialog->>Panel: cancelCallback()
        Note over Panel: No action taken
    end
```

---

## Module Dependencies

```mermaid
graph TD
    subgraph "Panel Module"
        MSP[magic_shooter_panel.lua]
    end

    subgraph "Logic Module"
        MS[classes/magic_shooter.lua]
    end

    subgraph "Helper Core"
        H[helper.lua]
        HC[helperConfig]
    end

    subgraph "Spell Data"
        HSD[HelperSpellData]
        SDJ[spelldata.json]
        SDL[spelldata.lua]
    end

    subgraph "UI Files"
        OTUI[styles/magic_shooter_panel.otui]
        HW[helper_window.otui]
    end

    subgraph "External APIs"
        SP[Spells API]
        GM[g_game]
        UI[g_ui]
        MO[g_mouse]
        CR[Creature API]
    end

    MSP --> HC
    MSP --> SP
    MSP --> UI
    MSP --> MO
    MSP --> OTUI
    MSP --> HSD

    MS --> HC
    MS --> SP
    MS --> GM
    MS --> HSD
    MS --> CR

    SDL --> SDJ
    HSD --> SDL

    H --> MSP
    H --> MS
    HW --> OTUI
```

---

## Files Structure

| File                              | Purpose                                                   |
| --------------------------------- | --------------------------------------------------------- |
| `magic_shooter_panel.lua`         | UI panel logic, form handling, rules list                 |
| `styles/magic_shooter_panel.otui` | OTUI layout definitions                                   |
| `classes/magic_shooter.lua`       | Core logic, spell/rune casting                            |
| `helper.lua`                      | Integration, event binding                                |
| `helper_window.otui`              | Main window with ShooterPanel                             |
| `spelldata.json`                  | Spell configuration data (rangedMonsterSpells, etc.)      |
| `spelldata.lua`                   | HelperSpellData module for loading/accessing spell config |
| `../gamelib/creature.lua`         | Creature class with hasIcon() method                      |

---

## Key Features Summary

1. **Unified List**: Spells and runes in same list, ordered by priority
2. **Dynamic Rules**: Add/remove unlimited rules
3. **Presets**: Multiple profiles with hotkey support
4. **Harmony Support**: Threshold configuration for Monk spells
5. **Visual Feedback**: Selected item highlighting, words display
6. **Duplicate Prevention**: Cannot add same spell/rune twice
7. **Confirmation Dialog**: Safe deletion with Yes/No prompt
8. **Context Menu**: Right-click for Edit/Move Up/Move Down/Delete
9. **Ignore Monster List**: Exclude specific monsters from auto targeting
10. **Priority Monster List**: Mode J allows user-defined targeting priority order
11. **Cast If Trapped**: Only cast spell/rune when player cannot walk in any cardinal direction
12. **Creatures Threshold for All Spells**: Creatures dropdown enabled for all spell types (area, targetable, support) - counts creatures around player
13. **Ranged Monster Spells**: Filter creatures by name for specific spells (exana amp res, exeta amp res, exori mas res) with auto-direction for exori mas res
14. **Turned Melee Icon Filter**: Automatically excludes creatures that already have the turned_melee icon (icon 3) from ranged spell creature counting
15. **Summon Filter**: Automatically excludes summoned creatures (creatures with a master) from targeting - same logic as Auto Target

---

## Monster List Features

### Ignore Monster List

Monsters in this list will be excluded from auto targeting:

```
+------------------------------------------+
| Ignore Monster List                      |
| [rat, bug, snake              ] [Apply]  |
+------------------------------------------+
```

- Comma-separated list of monster names (case-insensitive)
- Apply button saves to `helperConfig.ignoreMonsterList`
- Apply button disabled until text changes
- Monsters matching names in list are skipped during targeting

### Priority Monster List (Mode J)

When Auto Target mode "J" is selected, this list defines targeting priority:

```
+------------------------------------------+
| My Priority List In Order                |
| [dragon, dragon lord, demon    ] [Apply] |
+------------------------------------------+
```

- Only visible when Mode J is selected
- Panel height adjusts dynamically (115px → 155px when visible)
- First monster in list has highest priority
- If same priority, closest monster is selected
- If no priority monsters found, falls back to closest target
- Apply button disabled until text changes
- Numbers are automatically removed from input

### Dynamic Layout Adjustment

```mermaid
flowchart TD
    A[Mode Changed] --> B{Mode == J?}
    B -->|Yes| C[Show Priority List Widgets]
    B -->|No| D[Hide Priority List Widgets]

    C --> E[Change enableAutoTarget anchor<br>from ignoreMonsterInput.bottom<br>to priorityMonsterInput.bottom]
    D --> F[Change enableAutoTarget anchor<br>from priorityMonsterInput.bottom<br>to ignoreMonsterInput.bottom]

    E --> G[Set panel height to 155px]
    F --> H[Set panel height to 115px]
```

---

## Cast If Trapped Feature

The "Cast If Trapped" feature allows a spell or rune to only be cast when the player is unable to walk in any of the 4 cardinal directions (North, South, East, West).

### Use Cases

- **Emergency spells**: Cast powerful area spells only when surrounded by monsters
- **Defensive runes**: Use area runes when trapped to clear a path
- **Situational attacks**: Reserve specific spells for dangerous trapped situations

### How It Works

```mermaid
flowchart TD
    A[isPlayerTrapped called] --> B[Get player position]
    B --> C[Check 4 cardinal directions]

    C --> D{North tile walkable?}
    D -->|Yes| FREE([Return false - Not Trapped])
    D -->|No| E{South tile walkable?}

    E -->|Yes| FREE
    E -->|No| F{East tile walkable?}

    F -->|Yes| FREE
    F -->|No| G{West tile walkable?}

    G -->|Yes| FREE
    G -->|No| TRAPPED([Return true - Player is Trapped])
```

### UI Integration

The checkbox "Cast If Trapped" appears next to the "Add" button in the rules panel:

```
| Rules:              [_] Cast If Trapped [Add]  |
```

- Check the box before clicking Add/Update to enable this restriction
- When a rule has `castIfTrapped` enabled, a "T" indicator appears in the rule summary

### Summary Display

| Indicator | Meaning                                  |
| --------- | ---------------------------------------- |
| `T`       | Cast If Trapped is enabled for this rule |

Example rule summary: `C:2+ MP:80% HP:100% T` (Creatures 2+, Mana 80%+, Health 100%+, Trapped only)

---

## Ranged Monster Spells Feature

The "Ranged Monster Names" feature allows specific spells to filter creatures by name and automatically turn the player toward the direction with most matching creatures.

### Supported Spells

| Spell ID | Spell Name           | Words         | Auto Direction |
| -------- | -------------------- | ------------- | -------------- |
| 237      | Chivalrous Challenge | exeta amp res | No             |
| 238      | Divine Dazzle        | exana amp res | No             |
| 280      | Balanced Brawl       | exori mas res | **Yes**        |

### Configuration (spelldata.json)

The list of ranged monster spells is configured in `spelldata.json`:

```json
{
  "rangedMonsterSpells": [237, 238, 280]
}
```

### UI Integration

When one of these spells is selected, a new row appears in the config form:

```
+------------------------------------------+
| Ranged Monster Names: [minotaur archer, minotaur mage   ] |
+------------------------------------------+
```

- **Input field**: Accepts comma-separated monster names (case-insensitive)
- **Placeholder**: Shows "minotaur archer, minotaur mage" as example
- **Panel height**: Expands from 90px to 116px when visible

### How It Works

```mermaid
flowchart TD
    START([Ranged Spell Processing]) --> A{rangedMonsterNames set?}

    A -->|Yes| B[Parse comma-separated names]
    A -->|No| C[Use all creatures]

    B --> D[Filter creatures by name]
    C --> D2[Get all creatures in range]

    D --> E[Exclude creatures with turned_melee icon]
    D2 --> E

    E --> F[Count filtered creatures around player]

    F --> G{Spell has aimAtTarget?}
    G -->|Yes| H{Filtered list has creatures?}
    G -->|No| I[Use current direction]

    H -->|Yes| H2[Calculate best direction using filtered list]
    H -->|No| H3[Calculate best direction using ALL creatures]

    H2 --> J[Turn player to best direction]
    H3 --> J
    I --> K[Continue with spell cast]
    J --> K

    K --> L{filteredCreatures >= threshold?}
    L -->|Yes| M[Cast spell]
    L -->|No| N[Skip spell]
```

### Turned Melee Icon Filter

Creatures with the `turned_melee` icon (icon ID 3, category 1) are automatically excluded from the creature count. This is because the ranged spells convert creatures to melee for a few seconds, and creatures already converted should not be counted again.

```mermaid
flowchart TD
    A[For each creature in range] --> B{Has turned_melee icon?}
    B -->|Yes| C[Exclude from count]
    B -->|No| D[Include in count]

    C --> E[Continue to next creature]
    D --> E
```

The icon check uses `Creature:hasIcon(iconId, category)` method added to `creature.lua`:

```lua
-- Monster icon constants (category 1)
MonsterIconTurnedMelee = 3

function Creature:hasIcon(iconId, category)
    category = category or 1
    local icons = self:getIcons()
    if not icons then return false end

    for _, iconData in pairs(icons) do
        local id = iconData[1]       -- icon ID
        local cat = iconData[2]      -- category
        if id == iconId and cat == category then
            return true
        end
    end
    return false
end
```

### Direction Calculation (exori mas res only)

Only `exori mas res` (ID 280) has `aimAtTarget = true`, which triggers the direction calculation:

```mermaid
flowchart TD
    A[Get all 4 directions] --> B[For each direction]
    B --> C[Count creatures in half-plane]

    C --> D{Direction?}
    D -->|North| E[Count where dy < 0]
    D -->|East| F[Count where dx > 0]
    D -->|South| G[Count where dy > 0]
    D -->|West| H[Count where dx < 0]

    E --> I[Compare counts]
    F --> I
    G --> I
    H --> I

    I --> J[Select direction with most creatures]
    J --> K[Turn player to that direction]
```

### Summary Display

When a rule has `rangedMonsterNames` configured, an "R" indicator appears in the rule summary:

| Indicator | Meaning                                          |
| --------- | ------------------------------------------------ |
| `R`       | Ranged Monster Names is configured for this rule |

Example rule summary: `C:2+ MP:80% R` (Creatures 2+, Mana 80%+, Ranged filter active)

### Behavior Summary

| Scenario                                          | Creature Filter           | Direction                                  |
| ------------------------------------------------- | ------------------------- | ------------------------------------------ |
| Names set + matching creatures + exori mas res    | Filter by names           | Auto-turn to direction with most from list |
| Names set + NO matching creatures + exori mas res | All creatures (fallback)  | Auto-turn to direction with most creatures |
| Names set + other ranged spells                   | Filter by names           | Keep current direction                     |
| Names empty + exori mas res                       | All creatures (no filter) | Auto-turn to best direction                |
| Names empty + other ranged spells                 | All creatures (no filter) | Keep current direction                     |

**Note:** In all cases, creatures with the `turned_melee` icon are excluded from counting.

**Important:** When `rangedMonsterNames` is configured but no matching creatures are found on screen, the direction calculation falls back to using all creatures (excluding turned_melee). This ensures the player always turns toward the direction with the most monsters, even if none of them match the filter list.

---

## Summon Filter

The Magic Shooter automatically excludes summoned creatures from targeting, matching the behavior of Auto Target.

### How It Works

A creature is considered a summon if it has a master (owner). This is detected using `creature:getMasterId()`:

```lua
-- Ignorar criaturas invocadas (summons) - mesma lógica do Auto Target
if creature:getMasterId() ~= 0 then
  goto continue
end
```

### Detection Logic

```mermaid
flowchart TD
    A[For each creature in spectators] --> B{Is monster?}
    B -->|No| SKIP1([Skip - Not a monster])
    B -->|Yes| C{getMasterId != 0?}

    C -->|Yes| SKIP2([Skip - Is a summon])
    C -->|No| D[Continue with other checks]

    D --> E{In ignore list?}
    E -->|Yes| SKIP3([Skip])
    E -->|No| F{Same floor?}

    F -->|No| SKIP4([Skip])
    F -->|Yes| G{Line of sight clear?}

    G -->|No| SKIP5([Skip])
    G -->|Yes| H[Add to creature list]
```

### Consistency with Auto Target

Both systems now use identical logic for summon detection:

| System        | Check                        | Location                  |
| ------------- | ---------------------------- | ------------------------- |
| Auto Target   | `creature:getMasterId() ~= 0` | `isValidCreature()` function |
| Magic Shooter | `creature:getMasterId() ~= 0` | Creature collection loop    |

### Behavior Summary

| Creature Type       | `getMasterId()` | Targeted? |
| ------------------- | --------------- | --------- |
| Regular monster     | 0               | ✅ Yes    |
| Player summon       | Player ID       | ❌ No     |
| Monster summon      | Monster ID      | ❌ No     |

This ensures that:
- Player summons (like fire elemental, demon skeleton) are never targeted
- Monster summons are never targeted
- Only independent monsters are considered valid targets

---

## Protection Zone (PZ) Behavior

The magic shooter system integrates with the centralized PZ handler (`_Helper.handlePZState`) to manage behavior when entering/leaving Protection Zones.

### PZ State Machine

```mermaid
stateDiagram-v2
    [*] --> OUTSIDE_PZ: Initial

    OUTSIDE_PZ --> ENTERING_PZ: Player enters PZ

    ENTERING_PZ --> IN_PZ_DISABLED: disableInProtectZone == true
    ENTERING_PZ --> IN_PZ_PAUSED: disableInProtectZone == false

    IN_PZ_DISABLED --> OUTSIDE_PZ: Player leaves PZ
    IN_PZ_PAUSED --> OUTSIDE_PZ: Player leaves PZ

    note right of IN_PZ_DISABLED
        Case A1: Permanent disable
        - UI checkbox unchecked
        - Config set to false
        - Settings saved
        - No auto-restore
    end note

    note right of IN_PZ_PAUSED
        Case A2: Temporary pause
        - UI checkbox stays checked
        - Config unchanged
        - Actions blocked by guard
        - Auto-restore on exit
    end note
```

### Behavior Summary

| Scenario            | `disableInProtectZone = true`        | `disableInProtectZone = false`           |
| ------------------- | ------------------------------------ | ---------------------------------------- |
| Enter PZ            | Permanently disable, uncheck UI      | Pause (block actions), show message      |
| In PZ               | Actions blocked                      | Actions blocked                          |
| Leave PZ            | Stay disabled                        | Resume automatically, show message       |
| Manual toggle in PZ | User can re-enable (not recommended) | User can disable (will not auto-restore) |

### PZ Handler Integration

The PZ handler is called at the **beginning** of `_Helper.MagicShooter.check()`, before the enabled check:

```lua
-- PZ Guard: handles state transitions and blocks actions while in PZ
-- Must be called before enabled check to detect PZ exit and restore state
if _Helper.handlePZState then
  local shouldContinue = _Helper.handlePZState()
  if not shouldContinue then
    return
  end
end
```

### Shared State with Auto Target

Both auto_target and magic_shooter share the same PZ state in `helper.lua`:

```lua
local pzState = {
  wasInPZ = false,                    -- Track previous PZ status for edge detection
  wasAutoTargetEnabled = false,       -- Auto target state before PZ entry
  wasMagicShooterEnabled = false,     -- Magic shooter state before PZ entry
}
```

### Related Functions

| Function                  | Description                                     |
| ------------------------- | ----------------------------------------------- |
| `_Helper.handlePZState()` | Main PZ handler, returns false to block actions |
| `_Helper.getPZState()`    | Getter for debugging/testing                    |
| `_Helper.resetPZState()`  | Reset on logout/character change                |

### Edge Cases Handled

| Edge Case                        | Behavior                                   |
| -------------------------------- | ------------------------------------------ |
| Rapid PZ enter/exit              | Edge detection prevents duplicate triggers |
| Checkbox changed while in PZ     | No effect until next PZ transition         |
| Manual disable while in PZ (A2)  | Will not auto-restore on exit              |
| Client reload in PZ              | Starts fresh, blocks actions until PZ exit |
| Both systems enabled at PZ entry | Both are handled together by same handler  |
