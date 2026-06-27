--[[============================================================================
  scripting/api/hotkeymanager.lua — Zerobot-compatible `HotkeyManager` namespace.
  ============================================================================

  Builder module (see scripting/scripting.lua header + scripting/CONTRACT.md).
  Returns `function(api, ctx) ... return HotkeyManager end` and is injected into
  every sandboxed script as the global `HotkeyManager`.

  Plain namespace (NOT a class). PURE-LUA helper (no native bindings): it turns a
  human-readable key combo ("Ctrl+Alt+G", "shift + f1") into the
  (modifiers, keyCode) pair the engine's keyboard layer understands. In Zerobot
  this feeds Client.sendHotkey / Client.isKeyPressed; here it produces the same
  pair so a future Client namespace (or g_keyboard) can consume it directly.

  Public surface (Zerobot spec §10):
    * HotkeyManager.keyMapping
        table<string, number> — key NAME (lower-cased) -> engine key code.
    * HotkeyManager.parseKeyCombination(combination)
        -> ok:bool, modifiers:number, key:number
        Parse a "+"-separated combo. OR-folds ctrl/alt/shift/numlock into
        `modifiers` (Enums.FlagModifiers bitmask) and resolves the non-modifier
        token to a key code. Returns false, nil, nil on an unknown/empty key.

  KEY CODE SOURCE (verified — corelib/const.lua):
    The engine defines its keys as the GLOBAL `Key*` constants (KeyA=65, KeyF1=128,
    KeyEnter=5, KeyNumpad0=141, KeyMouse4=202, ...) and a `KeyCodeDescs[code]=name`
    table. These are the actual `Fw::Key` values (src/framework/const.h), NOT Qt
    codes. enums.lua's translate.keyToEngine is the IDENTITY (its comment says the
    hotkeymanager must EMIT Fw::Key codes built from KeyCodeDescs), so we map names
    straight to these engine codes — no cross-walk needed. We run OUTSIDE the
    sandbox, so the Key* globals and KeyCodeDescs are directly in scope.

  MODIFIER SOURCE (verified — enums.lua:408):
    Enums.FlagModifiers = { CONTROL=0x1, ALT=0x2, SHIFT=0x4, NUMLOCK=0x8 } and are
    OR-folded (ZB convention). We use api.Enums.FlagModifiers lazily so we share
    the single source of truth. To convert the folded ZB bitmask to the engine's
    COMBINED Keyboard*Modifier value, callers use
    api.Enums.translate.flagModifiersToEngine (NOT done here — ZB returns the ZB
    bitmask).

  RULES (CONTRACT): no globals; cross-namespace refs (api.Enums) are lazy; runs
  OUTSIDE the sandbox (Key* globals + KeyCodeDescs in scope).
============================================================================]]

return function(api, ctx)
  local HotkeyManager = {}

  -- ---------------------------------------------------------------------------
  -- keyMapping: name (lower-cased) -> engine key code.
  -- Built primarily by inverting the engine's KeyCodeDescs (code -> label) so it
  -- automatically tracks the real Fw::Key enum. We then add friendly aliases ZB
  -- users expect (e.g. "control"->Ctrl, "esc"->Escape, "pgup"->PageUp, single
  -- letters/digits, and the punctuation produced by typing). Modifier names are
  -- intentionally NOT in keyMapping as resolvable keys — they fold into the
  -- modifier bitmask in parseKeyCombination.
  -- ---------------------------------------------------------------------------
  local keyMapping = {}

  -- 1) invert KeyCodeDescs (skip empty/placeholder labels). Names lower-cased and
  --    de-spaced so "Page Up" / "PageUp" / "pageup" all collapse to one key.
  if type(KeyCodeDescs) == "table" then
    for code, label in pairs(KeyCodeDescs) do
      if type(label) == "string" and label ~= "" and label ~= "Unknown" then
        local norm = label:lower():gsub("%s+", "")
        if keyMapping[norm] == nil then
          keyMapping[norm] = code
        end
      end
    end
  end

  -- small helper: set an alias only if the target global key code exists and the
  -- alias isn't already taken. `globalName` is a Key* global from const.lua.
  local function alias(name, globalName)
    local code = _G[globalName]
    if type(code) == "number" and keyMapping[name] == nil then
      keyMapping[name] = code
    end
  end

  -- 2) letters a-z and digits 0-9 directly from the Key* globals (canonical).
  for i = 0, 25 do
    local ch = string.char(string.byte("a") + i)
    alias(ch, "Key" .. ch:upper())
  end
  for d = 0, 9 do
    alias(tostring(d), "Key" .. tostring(d))
  end

  -- 3) F1..F24 (KeyCodeDescs already covers these, but be explicit/robust).
  for f = 1, 24 do
    alias("f" .. f, "KeyF" .. f)
  end

  -- 4) numpad digits as "numpadN" / "numN" (descs label them NIns/NEnd/... which
  --    are unfriendly to type in a combo string).
  for n = 0, 9 do
    alias("numpad" .. n, "KeyNumpad" .. n)
    alias("num" .. n, "KeyNumpad" .. n)
  end

  -- 5) common friendly aliases / alternate spellings.
  local ALIASES = {
    escape = "KeyEscape", esc = "KeyEscape",
    enter = "KeyEnter", ["return"] = "KeyEnter",
    space = "KeySpace", spacebar = "KeySpace",
    tab = "KeyTab",
    backspace = "KeyBackspace", bksp = "KeyBackspace",
    delete = "KeyDelete", del = "KeyDelete",
    insert = "KeyInsert", ins = "KeyInsert",
    home = "KeyHome", ["end"] = "KeyEnd",
    pageup = "KeyPageUp", pgup = "KeyPageUp",
    pagedown = "KeyPageDown", pgdn = "KeyPageDown", pgdown = "KeyPageDown",
    up = "KeyUp", down = "KeyDown", left = "KeyLeft", right = "KeyRight",
    pause = "KeyPause", printscreen = "KeyPrintScreen", prtsc = "KeyPrintScreen",
    scrolllock = "KeyScrollLock", capslock = "KeyCapsLock",
    menu = "KeyMenu", meta = "KeyMeta",
    plus = "KeyPlus", minus = "KeyMinus", comma = "KeyComma", period = "KeyPeriod",
    slash = "KeySlash", backslash = "KeyBackSlash",
    semicolon = "KeySemicolon", apostrophe = "KeyApostrophe", quote = "KeyQuote",
    grave = "KeyGrave", tilde = "KeyTilde",
    leftbracket = "KeyLeftBracket", rightbracket = "KeyRightBracket",
    equal = "KeyEqual", equals = "KeyEqual",
    numenter = "KeyNumEnter", numdelete = "KeyNumpadDelete", numdel = "KeyNumpadDelete",
    numlock = "KeyNumLock",
    mouse4 = "KeyMouse4", mouse5 = "KeyMouse5", mousemiddle = "KeyMouseMiddle",
    mouseup = "KeyMouseUp", mousedown = "KeyMouseDown",
  }
  for name, globalName in pairs(ALIASES) do
    alias(name, globalName)
  end

  -- 6) single-character punctuation, mapped from its literal char (so a combo can
  --    say "Ctrl+/" or "Ctrl+-"). Pulled from KeyCodeDescs single-char labels.
  if type(KeyCodeDescs) == "table" then
    for code, label in pairs(KeyCodeDescs) do
      if type(label) == "string" and #label == 1 then
        local lc = label:lower()
        if keyMapping[lc] == nil then keyMapping[lc] = code end
      end
    end
  end

  HotkeyManager.keyMapping = keyMapping

  -- ---------------------------------------------------------------------------
  -- modifier name -> ZB FlagModifiers field name (folded via api.Enums.FlagModifiers).
  -- Resolved lazily inside parseKeyCombination so we share enums' single source.
  -- ---------------------------------------------------------------------------
  local MODIFIER_FIELD = {
    ctrl = "CONTROL", control = "CONTROL", ctl = "CONTROL",
    alt = "ALT",
    shift = "SHIFT",
    numlock = "NUMLOCK", num = "NUMLOCK",
  }

  -- HotkeyManager.parseKeyCombination(combination) -> ok, modifiers, key
  --   Splits on "+", trims/normalizes each token, OR-folds modifier tokens into
  --   `modifiers` (ZB FlagModifiers bitmask) and resolves the single remaining
  --   token to an engine key code via keyMapping. On success returns
  --   true, modifiers, keyCode. On any unknown key (or empty input / no
  --   non-modifier key) returns false, nil, nil — matching ZB's failure shape.
  function HotkeyManager.parseKeyCombination(combination)
    if type(combination) ~= "string" then return false, nil, nil end

    local flags = (api.Enums and api.Enums.FlagModifiers) or
                  { CONTROL = 0x1, ALT = 0x2, SHIFT = 0x4, NUMLOCK = 0x8 }

    local modifiers = 0
    local keyCode = nil

    for token in combination:gmatch("[^%+]+") do
      -- trim surrounding whitespace, lower-case, and de-space ("page up").
      local norm = token:gsub("^%s+", ""):gsub("%s+$", ""):lower():gsub("%s+", "")
      if norm ~= "" then
        local modField = MODIFIER_FIELD[norm]
        if modField then
          modifiers = bit.bor(modifiers, flags[modField] or 0)
        else
          -- a non-modifier token: it must resolve to a key. ZB combos hold a
          -- single key; if more than one appears, the last wins (lenient).
          local code = keyMapping[norm]
          if code == nil then
            -- unknown key token -> whole combo is invalid (ZB returns false).
            return false, nil, nil
          end
          keyCode = code
        end
      end
    end

    if keyCode == nil then
      -- modifiers only (or empty) -> no actual key to press.
      return false, nil, nil
    end

    -- emit Fw::Key code directly (translate.keyToEngine is identity; see header).
    return true, modifiers, keyCode
  end

  return HotkeyManager
end
