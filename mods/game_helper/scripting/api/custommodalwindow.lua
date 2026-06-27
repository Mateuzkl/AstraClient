--[[============================================================================
  scripting/api/custommodalwindow.lua  ->  class `CustomModalWindow`
  (Zerobot dialect)
  ============================================================================
  A SCRIPT-CREATED modal dialog (NOT the server's modal window -- that one is
  Game.Events.MODAL_WINDOW + Game.modalWindowAnswer). This is the small "title +
  message + up to 20 buttons" popup a script throws up to ask the player
  something; clicking a button fires CUSTOM_MODAL_WINDOW_BUTTON_CLICK and the
  per-instance callback, then the dialog closes.

  Builder module (see scripting/CONTRACT.md and the header of scripting.lua):
  returns `function(api, ctx) ... return CustomModalWindow end` and is injected
  into every sandboxed script as the global `CustomModalWindow`.

  ----------------------------------------------------------------------------
  Zerobot native vs. KoliseuClient
  ----------------------------------------------------------------------------
  Zerobot wraps a NATIVE scriptable modal (customModalCreate / customModalSet*
  / customModalAddButton / customModalDestroy). KoliseuClient has no such native
  surface, but it already ships the canonical engine modal: UIMessageBox.display
  (modules/corelib/ui/uimessagebox.lua) builds a centered, input-locking
  `MainWindow`-styled dialog (data/styles/10-windows.otui) with a wrapped/
  auto-sized message label (`MessageBoxLabel`) and a row of `MessageBoxButton`s
  -- exactly the widget tree Zerobot's native modal renders. So NO new .otui is
  needed: each CustomModalWindow instance materializes as one UIMessageBox.

  Because UIMessageBox.display constructs the whole window (title + message +
  ALL buttons) in a single call, the Zerobot "create, then addButton repeatedly"
  flow is BUFFERED in Lua: caption/description/buttons accumulate on the
  instance, and the real widget is built on :show()/:display() (and lazily auto-
  shown once a button exists, so a script that forgets to call show() still gets
  a visible dialog). Re-showing rebuilds the widget with the current buffer, so
  you may add buttons or change the caption and call :show() again.

  ----------------------------------------------------------------------------
  Constructor (metatable; callable CustomModalWindow(...) == .new(...)):
    CustomModalWindow(caption?, description?)   create a modal (caption/title +
                                                description/message). description
                                                is stripped of '\n' and truncated
                                                to 54 chars, matching Zerobot.

  Instance methods (~6, all chainable + safe after destroy):
    getId()                  -> stable per-script modal id (0-based)
    setCaption(caption)      set/replace the title
    setDescription(desc)     set/replace the message (\n-stripped, <=54 chars)
    addButton(text) -> idx   append a button (max 20); returns its 0-based index
    setCallback(fn)          on-click handler fn(buttonId); wrapped via ctx.wrap
    show() / display()       build + present the dialog (idempotent: rebuilds)
    destroy()                close the dialog + drop it from the owning script

  Click bridge (Zerobot semantics):
    On a button click  -> api.Game.executeEvents(
                            api.Game.Events.CUSTOM_MODAL_WINDOW_BUTTON_CLICK,
                            modalId, buttonIndex)            (lazy via api.Game)
                       -> AND the per-instance callback fn(buttonIndex), wrapped
                          with ctx.wrap at store time so it runs in the owning
                          script's context with pcall + error accounting.
    A click closes the dialog (UIMessageBox destroys itself on a button press),
    so the widget reference is cleared; the instance stays reusable via :show().

  Cleanup: every instance registers ctx.onCleanup so a script's modals are
  destroyed when it unloads / errors / relogs (no leaked window).

  CONTRACT notes honoured:
    * No globals: only locals + the returned table (the C++ engine already has
      no CustomModalWindow global, but we still keep _G clean).
    * Cross-namespace refs are LAZY (api.Game.* resolved at fire time).
    * Runs OUTSIDE the sandbox: full access to g_ui / UIMessageBox / rootWidget.
============================================================================]]

return function(api, ctx)
  local CustomModalWindow = {}
  CustomModalWindow.__index = CustomModalWindow

  -- Zerobot's hard cap on buttons.
  local MAX_BUTTONS = 20
  -- Zerobot truncates the description to 54 chars after removing newlines.
  local MAX_DESC = 54

  -- Is a widget still alive (not destroyed)?
  local function alive(w)
    return w ~= nil and (not w.isDestroyed or not w:isDestroyed())
  end

  -- Normalize a description exactly like Zerobot: drop newlines, cap length.
  local function normDesc(desc)
    if desc == nil then return nil end
    desc = tostring(desc):gsub('\n', '')
    if #desc > MAX_DESC then desc = desc:sub(1, MAX_DESC) end
    return desc
  end

  -- ---- constructor core ---------------------------------------------------
  -- A modal must be owned by a running script (so cleanup + the per-script id
  -- sequence resolve), mirroring how hud.lua gates HUD creation.
  local function build(caption, description)
    local owner = ctx.runningScript()
    if not owner then
      error('CustomModalWindow(...) can only be created while a script is running', 2)
    end

    -- Stable id, scoped to the owning script (used as the modalId in the event
    -- and as the CustomModalWindowList-style key). 0-based to match Zerobot.
    owner.modalSeq = owner.modalSeq or 0
    local modalId = owner.modalSeq
    owner.modalSeq = owner.modalSeq + 1

    local self = setmetatable({}, CustomModalWindow)
    self._owner    = owner
    self._id       = modalId
    self._caption  = caption ~= nil and tostring(caption) or ''
    self._desc     = normDesc(description) or ''
    self._buttons  = {}       -- 1..N button texts (index-1); ZB id = i-1
    self._onClick  = nil      -- wrapped per-instance callback fn(buttonId)
    self._box      = nil      -- the live UIMessageBox widget (nil until shown)
    self._destroyed = false

    -- Track on the owning script + register teardown (closed on unload/relog).
    owner.modals = owner.modals or {}
    owner.modals[modalId] = self
    self._cleanup = ctx.onCleanup(function() self:destroy() end)

    return self
  end

  -- ---- the actual click dispatch ------------------------------------------
  -- Fired when a button (0-based `buttonId`) is pressed. Mirrors Zerobot's
  -- onCustomModalButtonOnClick -> Game event + per-instance callback. UIMessageBox
  -- does NOT self-destroy on a button click (the button callback is responsible,
  -- like displayInfoBox's messageBox:ok()), so we close it here FIRST -- otherwise
  -- the modal lingers on screen with input LOCKED. Its onDestroy restores the lock.
  function CustomModalWindow:_fireClick(buttonId)
    local box = self._box
    self._box = nil
    if box then pcall(function() box:destroy() end) end
    -- Global event dispatch (lazy via api.Game; a not-yet-built Game just skips).
    if api.Game and api.Game.executeEvents and api.Game.Events then
      pcall(function()
        api.Game.executeEvents(api.Game.Events.CUSTOM_MODAL_WINDOW_BUTTON_CLICK, self._id, buttonId)
      end)
    end
    -- Per-instance callback (already wrapped with ctx.wrap at set time).
    if self._onClick then self._onClick(buttonId) end
  end

  -- ---- instance methods ---------------------------------------------------

  function CustomModalWindow:getId() return self._id end

  -- Set/replace the title. If the dialog is on screen, update it live.
  function CustomModalWindow:setCaption(caption)
    self._caption = caption ~= nil and tostring(caption) or ''
    if alive(self._box) then pcall(function() self._box:setText(self._caption) end) end
    return self
  end

  -- Set/replace the message (\n-stripped, <=54 chars, like Zerobot). A live
  -- dialog is rebuilt so the label re-wraps/re-sizes to the new text.
  function CustomModalWindow:setDescription(description)
    self._desc = normDesc(description) or ''
    if alive(self._box) then self:show() end
    return self
  end

  -- Append a button. Returns its 0-based index (Zerobot's button id), or nil if
  -- the 20-button cap is reached (honest nil = not added). Adding a button to a
  -- live dialog rebuilds it so the new button shows.
  function CustomModalWindow:addButton(buttonText)
    if #self._buttons >= MAX_BUTTONS then
      ctx.logColor('#ffaa55', 'CustomModalWindow:addButton: button limit (' .. MAX_BUTTONS .. ') reached')
      return nil
    end
    self._buttons[#self._buttons + 1] = buttonText ~= nil and tostring(buttonText) or ''
    local buttonId = #self._buttons - 1   -- 0-based, as in Zerobot
    if alive(self._box) then self:show() end
    return buttonId
  end

  -- Store the on-click callback fn(buttonId). Wrapped with ctx.wrap so the
  -- deferred call runs in the OWNING script's context with error accounting.
  -- A nil clears the callback.
  function CustomModalWindow:setCallback(callback)
    if callback == nil then
      self._onClick = nil
    elseif type(callback) == 'function' then
      self._onClick = ctx.wrap(callback)
    else
      error('CustomModalWindow:setCallback(fn): fn must be a function or nil', 2)
    end
    return self
  end

  -- Build + present the dialog. Idempotent: an existing window is closed first
  -- and a fresh one is built from the current caption/description/buttons (so
  -- callers may mutate the buffer and re-show). Safe after destroy (no-op).
  function CustomModalWindow:show()
    if self._destroyed then return self end

    -- Close any previous incarnation WITHOUT firing a click (just a rebuild).
    if alive(self._box) then
      local old = self._box
      self._box = nil
      pcall(function() old:destroy() end)
    end

    -- Map our buffered buttons onto UIMessageBox's {text, callback} list. Each
    -- button's callback fires our click dispatch with its 0-based id; _fireClick
    -- closes the box (UIMessageBox does not auto-close on a button press).
    local buttonDefs = {}
    if #self._buttons == 0 then
      -- A modal with no buttons would be impossible to dismiss; give it a
      -- default "Ok" (id 0) so it is always closeable. (Zerobot scripts always
      -- add at least one button; this is a safety net.)
      buttonDefs[1] = {
        text = 'Ok',
        callback = function() self:_fireClick(0) end,
      }
    else
      for i = 1, #self._buttons do
        local zbId = i - 1
        buttonDefs[i] = {
          text = self._buttons[i],
          callback = function() self:_fireClick(zbId) end,
        }
      end
    end

    -- UIMessageBox.display(title, message, buttons[, onEnter, onEscape]) builds
    -- the centered MainWindow, the wrapped message label and the button row, and
    -- locks input to the dialog. Escape maps to the LAST button (Zerobot's
    -- default-escape behaviour for a script modal); we close + fire it.
    local lastId = math.max(#self._buttons - 1, 0)
    local onEscape = function() self:_fireClick(lastId) end

    local ok, box = pcall(function()
      return UIMessageBox.display(self._caption, self._desc, buttonDefs, nil, onEscape)
    end)
    if ok and box then
      self._box = box
    else
      ctx.logColor('#ff6666', 'CustomModalWindow:show: failed to build dialog: ' .. tostring(box))
    end
    return self
  end

  -- Zerobot/ergonomic alias.
  function CustomModalWindow:display() return self:show() end

  -- Close the dialog + drop it from the owning script + cancel its cleanup.
  -- Closing here is silent (no click dispatched) -- a programmatic destroy is
  -- not a button press.
  function CustomModalWindow:destroy()
    if self._destroyed then return end
    self._destroyed = true
    if alive(self._box) then pcall(function() self._box:destroy() end) end
    self._box = nil
    if self._owner and self._owner.modals then self._owner.modals[self._id] = nil end
    if self._cleanup then
      pcall(function() self._cleanup.cancel() end)
      self._cleanup = nil
    end
  end

  -- ---- constructors -------------------------------------------------------
  -- CustomModalWindow.new(caption?, description?) == CustomModalWindow(...).
  function CustomModalWindow.new(caption, description)
    return build(caption, description)
  end

  -- CustomModalWindow(caption?, description?) sugar.
  return setmetatable(CustomModalWindow, {
    __call = function(_, caption, description)
      return CustomModalWindow.new(caption, description)
    end,
  })
end
