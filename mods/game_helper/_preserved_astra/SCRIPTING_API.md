# AstraClient — Scripting API (`bot.*`)

The **Script** tab (in the Helper window) lets you write your own Lua scripts.

## How scripts run

- Each script's **file body runs exactly once** — the moment the script is **enabled** ("loaded"). Use it to set up state and register your timers.
- For recurring work, register a **`Timer(intervalMs, fn)`** (see below). It runs `fn` every `intervalMs` while the script stays loaded. There is **no** implicit 200 ms loop anymore.
- Each script has its own persistent table **`storage`** — use it to keep state between ticks (it is wiped on relog, not saved to disk).
- Errors are caught. A script that errors **5 times** is auto‑disabled (which also stops its timers, HUD icons and other resources) so it can't spam the console.
- Scripts run in a **restricted sandbox**. You get the `bot` API, the safe Lua standard library (`math`, `string`, `table`, `os.time/date/clock/difftime`, `pairs`, `pcall`, …) and **read access to the game** via `g_game`, `g_map`, `g_clock`. You do **not** get file access (`g_resources`), program/URL launching (`g_platform`), `os.execute`, `loadstring`/`dofile`/`require`, `package`/`modules`/`debug`, or networking — those are intentionally blocked so a (possibly shared) script can only automate the game, not touch your machine. The same sandbox applies to a cavebot **Lua waypoint**.

### Scheduling — `Timer`
`Timer(intervalMs, fn)` is a global available to every script.

```lua
print("loaded once")              -- body: runs a single time on load

Timer(1000, function()            -- runs every 1000 ms while loaded
  if bot.hpp() < 50 then bot.useItem(266) end
end)
```

- The first tick happens **after** one `intervalMs` (not immediately). Do anything you need right away in the body.
- Register **as many timers as you like** (e.g. one at 250 ms for healing, one at 2000 ms for looting).
- It returns a handle: call **`handle:stop()`** to cancel just that timer. All of a script's timers are cancelled automatically when it is unloaded, errors out, or you relog.

### Controls
Scripts are plain `.lua` **files** — edit them in your own editor.
- **Open Scripts Folder** — opens the `bot_scripts` folder where you drop your `.lua` files. New/edited files are picked up automatically while the tab is open.
- **Load / Unload** — move a script between the **Available** and **Running** lists (double‑click a row, or use the buttons / right‑click menu). Loading runs the body once and starts its timers/HUD; unloading stops them. The set of running scripts is remembered per character.
- **Debug** — opens the debug console (timestamped `print()`s and errors).

---

## API reference

`pos` is a table `{x=, y=, z=}`. `creature` is a Creature object (it has `:getName()`, `:getPosition()`, `:getHealthPercent()`, `:isMonster()`, `:isPlayer()`, …).

### Player / state
| Function | Returns | Description |
|---|---|---|
| `bot.player()` | LocalPlayer or nil | The local player object. |
| `bot.online()` | bool | True if in game with a player. |
| `bot.pos()` | pos or nil | Your current position. |
| `bot.name()` | string | Your character name. |
| `bot.hp()` / `bot.maxhp()` / `bot.hpp()` | number | Health / max health / health %. |
| `bot.mp()` / `bot.maxmp()` / `bot.mpp()` | number | Mana / max mana / mana %. |
| `bot.cap()` | number | Free capacity. |
| `bot.skull()` | number | Your skull id (see SkullRed/SkullBlack constants). |

### Movement
| Function | Returns | Description |
|---|---|---|
| `bot.walk(pos)` | — | Auto‑walk to `pos` (native pathfinder; same floor). |
| `bot.stopWalk()` | — | Stop auto‑walking. |
| `bot.walking()` | bool | True while auto‑walking. |
| `bot.dist(a, b)` | number | Chebyshev (tile) distance. `a` defaults to your position. |

### World
| Function | Returns | Description |
|---|---|---|
| `bot.tile(pos)` | Tile or nil | The tile at `pos`. |
| `bot.creatures(range)` | list | Living **monsters** within `range` tiles (default 7). |
| `bot.players(range)` | list | Other **players** within `range` tiles (default 7). |
| `bot.target()` | creature or nil | The creature you are currently attacking. |
| `bot.attack(creature)` | — | Start attacking `creature`. |

### Items / actions
| Function | Returns | Description |
|---|---|---|
| `bot.itemCount(id)` | number | How many of item `id` you carry. |
| `bot.useItem(id)` | — | Use an inventory item (e.g. a potion). |
| `bot.useItemOn(id, target)` | — | Use inventory item `id` on a creature/thing. |
| `bot.use(pos)` | — | Use the top usable object at `pos` (lever, ladder…). |
| `bot.say(text)` | — | Say text / cast a spell by words (e.g. `bot.say("exura")`). |

### Timing / logging
| Function | Returns | Description |
|---|---|---|
| `bot.now()` | number | Monotonic milliseconds (for your own timing math). |
| `Timer(ms, fn)` | handle | **Global.** Run `fn` every `ms` while loaded. `handle:stop()` cancels it. See *Scheduling* above. |
| `bot.log(...)` | — | Print to the console, prefixed with the script name. (`print` also works.) |

### Cavebot control — `bot.cavebot.*`
| Function | Returns | Description |
|---|---|---|
| `bot.cavebot.enabled()` | bool | Is the cavebot running? |
| `bot.cavebot.enable()` / `disable()` / `toggle()` | — | Turn the cavebot on/off. |
| `bot.cavebot.gotoTab(name)` | bool | Switch to waypoint tab `name` (e.g. `"Refill"`); restarts that tab's loop. |
| `bot.cavebot.tab()` | string | Current waypoint tab name. |
| `bot.cavebot.tabs()` | list | All waypoint tab names. |
| `bot.cavebot.status()` | string | The cavebot status text (e.g. `"Running 3/12"`). |

### Helper control — `bot.helper.*`
| Function | Returns | Description |
|---|---|---|
| `bot.helper.enabled()` | bool | Is the Helper (healing/etc.) master switch on? |
| `bot.helper.enable()` / `disable()` / `toggle()` | — | Turn the Helper master switch on/off (same as the Pause/Break hotkey). |
| `bot.helper.shooter()` / `target()` | bool | Is the magic shooter / auto‑target on? |
| `bot.helper.setShooter(on)` / `setTarget(on)` | — | Turn the magic shooter / auto‑target on/off. |

### Forge — `bot.forge.*`
Thin wrappers over the exalted‑forge conversion actions (the same buttons in the Forge
window) plus your current forge balances. The **server validates every action**: each
conversion costs dust/slivers and the dust limit is capped, so an action simply has **no
effect** server‑side when you can't afford it (or aren't allowed to forge right now).

| Function | Returns | Description |
|---|---|---|
| `bot.forge.increaseDustLimit()` | — | Spend dust to raise your max dust limit (stops at the server cap). |
| `bot.forge.dustToSlivers()` | — | Convert dust → slivers. |
| `bot.forge.sliversToCores()` | — | Convert slivers → exalted cores. |
| `bot.forge.dust()` / `bot.forge.maxDust()` | number | Current dust / your current dust limit. |
| `bot.forge.slivers()` / `bot.forge.cores()` | number | Current slivers / exalted cores. |

```lua
-- AFK: tenta subir o limite de dust de tempos em tempos. O servidor recusa
-- sozinho quando você não tem dust suficiente ou já está no teto.
Timer(60000, function()
  if not bot.online() then return end
  if bot.forge.dust() < bot.forge.maxDust() then return end  -- só vale a pena com o pote cheio
  bot.forge.increaseDustLimit()
  bot.log("dust:", bot.forge.dust() .. "/" .. bot.forge.maxDust())
end)
```

### On‑screen HUD — `bot.hud.*`
Create draggable, clickable HUD elements over the game map (e.g. a button to toggle one of
your script's features, or a live readout). The icon can be an image **or a real game item
sprite** (by item id), with the text shown as a caption **below** it. An element is
**destroyed automatically** when its script is unloaded, errors out, or you relog, and its
**dragged position + lock state are remembered per character**.

The player can **right‑click** any element to **Lock/Unlock** its position (a locked element
can't be dragged); the lock is saved per character.

`bot.hud.create(opts)` → **handle**. `opts` fields (all optional except you'll usually want `id`):

| Field | Type | Description |
|---|---|---|
| `id` | string | Stable id used to remember the element's position + lock. Re‑creating the same `id` replaces the old one. |
| `item` | number | Item id to render as the icon (the real game sprite). Takes priority over `image`. |
| `image` | string | Image path, e.g. `"/images/topbuttons/shop"` (no extension). Used when no `item` is given. |
| `text` | string | Caption drawn directly **below** the icon. |
| `color` | string | Caption text color, e.g. `'#ffcc00'`. |
| `borderColor` | string | Border color in the **off** state (default transparent). |
| `borderColorOn` | string | Border color in the **on** state (default green `#44ad25`). |
| `x`, `y` | number | Initial position (pixels, relative to the map). A saved position overrides this. |
| `width`, `height` | number | Element size (default 40×52). |
| `on` | bool | Initial lit/active state. |
| `tooltip` | string | Hover tooltip. |
| `draggable` | bool | Allow dragging to reposition (default `true`). The player's lock overrides this. |
| `locked` | bool | Start locked in place (drag disabled). |
| `onClick` | function | Called as `onClick(handle)` when the element is clicked (a drag does **not** fire it). |

Handle methods (all chainable / safe after destroy):

| Method | Description |
|---|---|
| `h:setText(t)` / `h:setImage(path)` / `h:setItem(id)` / `h:setColor(c)` / `h:setTooltip(t)` | Update the icon / caption. `setItem(0)` clears the item. |
| `h:setBorderColor(c)` / `h:setBorderColorOn(c)` | Set the off / on border color. |
| `h:setOn(bool)` / `h:isOn()` | Set / read the lit (active) visual state. |
| `h:setDraggable(bool)` | Enable / disable dragging from the script. |
| `h:setLocked(bool)` / `h:isLocked()` | Lock / unlock (and save) the position; mirrors the right‑click menu. |
| `h:show()` / `h:hide()` / `h:setVisible(bool)` | Show or hide the element. |
| `h:setPos(x, y)` / `h:getPos()` | Move (and save) / read the position. |
| `h:destroy()` | Remove the element now. |

```lua
-- A draggable button that toggles the magic shooter and reflects its state.
local btn = bot.hud.create({
  id = 'shooter', text = 'Caster', x = 20, y = 120, on = bot.helper.shooter(),
  tooltip = 'Click to toggle the caster (drag to move)',
  onClick = function(self)
    bot.helper.setShooter(not bot.helper.shooter())
    self:setOn(bot.helper.shooter())
  end,
})
-- keep it in sync if something else toggles the shooter
Timer(500, function() btn:setOn(bot.helper.shooter()) end)
```

```lua
-- A live mana-potion counter: shows the potion's real item sprite with the count below.
local POT = 268 -- mana potion item id
local pots = bot.hud.create({ id = 'pots', item = POT, x = 20, y = 180, text = '0' })
Timer(500, function() pots:setText(bot.itemCount(POT)) end)
-- (the player can right-click it to Lock it in place)
```

---

## Examples

**Re‑pot mana when low (every 800 ms):**
```lua
Timer(800, function()
  if bot.mpp() < 40 and bot.itemCount(268) > 0 then
    bot.useItem(268)        -- mana potion
  end
end)
```

**Switch the cavebot to a "Refill" tab when out of potions, back to "Hunt" otherwise:**
```lua
Timer(1000, function()
  if bot.itemCount(268) == 0 then
    if bot.cavebot.tab() ~= "Refill" then bot.cavebot.gotoTab("Refill") end
  elseif bot.cavebot.tab() ~= "Hunt" then
    bot.cavebot.gotoTab("Hunt")
  end
end)
```

**Turn off the shooter while a player is on screen (anti‑PK), re‑enable when clear:**
```lua
Timer(500, function()
  local pk = #bot.players(8) > 0
  bot.helper.setShooter(not pk)
  if pk then
    bot.log("player nearby!", bot.players(8)[1]:getName())
  end
end)
```

**Count kills using `storage` (persists between ticks). Two timers, different rates:**
```lua
storage.kills = storage.kills or 0

Timer(250, function()
  local t = bot.target()
  if t and t:getHealthPercent() <= 0 then storage.kills = storage.kills + 1 end
end)

Timer(10000, function()
  bot.log("kills so far:", storage.kills)
end)
```
