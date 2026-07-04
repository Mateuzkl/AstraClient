--[[
  scripting/api/hud.lua  ->  class `HUD`  (Zerobot dialect)
  ============================================================================
  On-screen, draggable, clickable overlay elements placed over the game map.

  Zerobot's HUD is a class wrapping a NATIVE hud element (text / item / spell icon
  / outfit). KoliseuClient has no immediate-mode drawing and no native HUD layer
  (engine-capabilities.md S7), so each HUD instance is instead a composite UIWidget
  (`ScriptHudIcon`, styles/scripting.otui) parented to the game map panel -- the
  exact mechanic already proven by `_preserved_astra/scripting.lua`'s `bot.hud`.
  This file re-exposes that mechanic on the Zerobot `HUD` surface.

  Constructors (metatable; callable HUD(...) == HUD.new(...)):
    HUD.new(x, y, value, newFeatures?)   text HUD when `value` is a string;
                                         item HUD when `value` is a number (itemId).
    HUD.newSpellIcon(x, y, spellId, nf?) spell-icon HUD (rendered via UISprite).
    HUD.newOutfit(x, y, outfitId, nf?)   outfit HUD (rendered via UICreature, animated).

  Instance methods (~24, all chainable + safe after destroy / after the game UI is
  torn down):
    setText / setColor(r,g,b) / setFontSize
    getPos / setPos(x,y) / getMargins
    setSize(w,h) / setScale / setOpacity
    setVisible / show / hide / setPhantom / setZIndex
    setDraggable / setLocked / isLocked
    setHorizontalAlignment / setVerticalAlignment
    setItemId / setImage
    setSpellIconId
    setOutfitId / setOutfit / setOutfitAddons / setOutfitColors /
      setOutfitDirection / setOutfitMoving
    setCallback(fn) / getId / destroy

  Click / drag (Zerobot event bridge):
    * On click  -> api.Game.executeEvents(api.Game.Events.HUD_CLICK, id)
    * On drag   -> api.Game.executeEvents(api.Game.Events.HUD_DRAG, id, x, y)
      (both resolved LAZILY through `api.Game` at fire time, since game.lua may be
       built after this module; a missing Game just skips the dispatch.)
    * A per-instance onClick callback (HUD.new(... ) / :setCallback(fn)) is wrapped
      with ctx.wrap at store time so it runs in the owning script's context with
      error accounting.

  Persistence: each element's dragged position + lock state is saved per character
  in /characterdata/<id>/hud.json, keyed by the owning script name + the element id,
  so a HUD returns where the player left it (reused from the preserved design).

  Cleanup: every instance registers ctx.onCleanup so all of a script's HUDs are
  destroyed when it unloads / errors / relogs.

  Style note (memory runtime-style-wiped): border/background colors set at runtime
  are wiped by the style re-apply on hover/focus. ScriptHudIcon keeps border-color
  OUT of the style and reacts only to $on/$pressed in the .otui, so we drive the
  border from Lua via setOn + an explicit setBorderColor after each state change.
]]

return function(api, ctx)
  local HUD = {}
  HUD.__index = HUD

  -- ---- small helpers ------------------------------------------------------
  local function alive(w) return w ~= nil and (not w.isDestroyed or not w:isDestroyed()) end
  local function clampInt(v, d) v = tonumber(v); return v and math.floor(v) or d end

  -- The game map panel (overlay parent); nil when not in game.
  local function hudParent()
    local gi = modules.game_interface
    return (gi and gi.getMapPanel) and gi.getMapPanel() or nil
  end

  -- Resolve `json` once (same source as api/json.lua; it is a boot global). Used
  -- only for the per-character hud.json position store -- no I/O is exposed to
  -- scripts, this runs OUTSIDE the sandbox.
  local jsonLib = json
  if type(jsonLib) ~= 'table' or type(jsonLib.encode) ~= 'function' then
    pcall(dofile, '/corelib/json.lua')
    if type(json) == 'table' then jsonLib = json end
  end

  -- ---- per-character position/lock persistence ----------------------------
  --   hudData = scriptName -> elemId -> { x, y, locked }
  local hudData = {}
  local hudLoadedFor = nil   -- player id the cache was loaded for (reload on relog)

  local function hudPath()
    if not LoadedPlayer or not LoadedPlayer:isLoaded() then return nil end
    return '/characterdata/' .. LoadedPlayer:getId() .. '/hud.json'
  end

  -- Load the saved layout lazily (and re-load when the character changes), so a HUD
  -- created right after login restores its last position without a separate hook.
  local function ensureHudLoaded()
    local pid = (LoadedPlayer and LoadedPlayer:isLoaded()) and LoadedPlayer:getId() or nil
    if pid == hudLoadedFor then return end
    hudLoadedFor = pid
    hudData = {}
    local p = hudPath()
    if p and g_resources.fileExists(p) then
      local ok, res = pcall(function() return jsonLib.decode(g_resources.readFileContents(p)) end)
      if ok and type(res) == 'table' then hudData = res end
    end
  end

  local function saveHud()
    local p = hudPath()
    if not p then return end
    local ok, res = pcall(function() return jsonLib.encode(hudData) end)
    if ok and res then pcall(function() g_resources.writeFileContents(p, res) end) end
  end

  -- ---- construction core --------------------------------------------------
  -- All four constructors funnel here. `kind` selects which child renders the icon:
  --   'text'   -> caption only
  --   'item'   -> UIItem (iconItem) with item id = value
  --   'sprite' -> UISprite (created on demand) with sprite id = value (spell icon)
  --   'outfit' -> UICreature (created on demand) with outfit type = value
  local function build(kind, x, y, value)
    -- A HUD must be owned by a running script (so cleanup/persist key resolve).
    local owner = ctx.runningScript()
    if not owner then
      error('HUD(...) can only be created while a script is running', 2)
    end
    local parent = hudParent()
    if not parent then
      error('HUD(...): the game map is not available yet', 2)
    end
    ensureHudLoaded()

    -- Stable element id, scoped to the owning script (for persistence + events).
    owner.hudSeq = (owner.hudSeq or 0) + 1
    local elemId = owner.hudSeq

    local self = setmetatable({}, HUD)
    self._owner   = owner
    self._id      = elemId
    self._kind    = kind
    self._wantDrag = true
    self._borderOff = '#00000000'
    self._borderOn  = '#44ad25'
    self._onClick = nil

    local w = g_ui.createWidget('ScriptHudIcon', parent)
    w.scriptName, w.elemId = owner.name, elemId
    self._w = w

    -- Children from the style. iconItem/iconImage/caption always exist; the sprite
    -- and outfit widgets are created on demand so a text/item HUD stays light.
    local iconImage = w:getChildById('iconImage')
    local iconItem  = w:getChildById('iconItem')
    local caption   = w:getChildById('caption')
    self._caption   = caption
    self._iconImage = iconImage
    self._iconItem  = iconItem

    -- Caption sits BELOW the icon when there is one, else fills the widget (centered).
    local function layoutCaption(hasIcon)
      if not caption then return end
      if hasIcon then
        caption:addAnchor(AnchorTop, 'iconImage', AnchorBottom)
        caption:setMarginTop(1)
      else
        caption:addAnchor(AnchorTop, 'parent', AnchorTop)
        caption:setMarginTop(0)
      end
    end
    self._layoutCaption = layoutCaption

    -- Lazily create the sprite/outfit child the first time it is needed, anchored
    -- over the icon slot (iconImage) and phantom so it never eats the widget's mouse.
    local function ensureSprite()
      if alive(self._sprite) then return self._sprite end
      local s = g_ui.createWidget('UISprite', w)
      s:setPhantom(true)
      pcall(function() s:fill('iconImage') end)   -- cover the icon slot
      self._sprite = s
      return s
    end
    local function ensureOutfit()
      if alive(self._outfit) then return self._outfit end
      local c = g_ui.createWidget('UICreature', w)
      c:setPhantom(true)
      pcall(function() c:fill('iconImage') end)   -- cover the icon slot
      pcall(function() c:setAnimate(true) end)    -- outfit HUDs animate by default
      self._outfit = c
      return c
    end
    self._ensureSprite = ensureSprite
    self._ensureOutfit = ensureOutfit

    -- Initial render per kind.
    w:setSize({ width = 40, height = 52 })
    if kind == 'item' then
      local id = tonumber(value) or 0
      if iconItem then pcall(function() iconItem:setItemId(id) end); iconItem:setVisible(id ~= 0) end
      if iconImage then iconImage:setVisible(false) end
      layoutCaption(id ~= 0)
    elseif kind == 'sprite' then
      local sp = ensureSprite()
      pcall(function() sp:setSpriteId(tonumber(value) or 0) end)
      if iconImage then iconImage:setVisible(false) end
      if iconItem then iconItem:setVisible(false) end
      layoutCaption(true)
    elseif kind == 'outfit' then
      local oc = ensureOutfit()
      pcall(function() oc:setOutfit({ type = tonumber(value) or 0, addons = 0 }) end)
      if iconImage then iconImage:setVisible(false) end
      if iconItem then iconItem:setVisible(false) end
      layoutCaption(true)
    else -- text
      if iconImage then iconImage:setVisible(false) end
      if iconItem then iconItem:setVisible(false) end
      if caption and type(value) == 'string' then caption:setText(value) end
      layoutCaption(false)
    end

    -- Border driven from Lua (style keeps border-color out; see header).
    local function applyBorder()
      if alive(w) then pcall(function() w:setBorderColor(w:isOn() and self._borderOn or self._borderOff) end) end
    end
    self._applyBorder = applyBorder
    w:setOn(false)
    applyBorder()

    -- Position: a saved per-character position overrides the constructor default.
    local saved = hudData[owner.name] and hudData[owner.name][elemId]
    local rx = saved and clampInt(saved.x, 100) or clampInt(x, 100)
    local ry = saved and clampInt(saved.y, 100) or clampInt(y, 100)
    w:setPosition({ x = parent:getX() + rx, y = parent:getY() + ry })
    pcall(function() w:bindRectToParent() end)

    -- Persist this element's position/lock by MERGING (writing one field never wipes
    -- the other). Coordinates are stored relative to the map panel.
    local function persistField(k, v)
      local pr = hudParent()
      if not pr then return end
      ensureHudLoaded()
      hudData[owner.name] = hudData[owner.name] or {}
      local e = hudData[owner.name][elemId] or {}
      if k then e[k] = v end
      if alive(w) then e.x = w:getX() - pr:getX(); e.y = w:getY() - pr:getY() end
      hudData[owner.name][elemId] = e
      saveHud()
    end
    self._persistField = persistField

    -- Lock = player froze this element (drag disabled), persisted + toggleable from a
    -- right-click menu. `setDraggable(false)` is the script's own default off-switch.
    self._locked = (saved and saved.locked == true) or false
    local function applyDraggable()
      if alive(w) then w:setDraggable(self._wantDrag and not self._locked) end
    end
    self._applyDraggable = applyDraggable
    applyDraggable()

    -- Drag to reposition. On drop we persist AND fire HUD_DRAG with the new
    -- map-relative position. A drag never also triggers onClick.
    w.onDragEnter = function(self2, mousePos)
      self2.movingReference = { x = mousePos.x - self2:getX(), y = mousePos.y - self2:getY() }
      return true
    end
    w.onDragMove = function(self2, mousePos)
      if not self2.movingReference then return end
      self2:setPosition({ x = mousePos.x - self2.movingReference.x, y = mousePos.y - self2.movingReference.y })
      self2:bindRectToParent()
    end
    w.onDragLeave = function(self2)
      persistField()
      self2.movingReference = nil
      -- Fire HUD_DRAG (lazy via api.Game) with the dropped, map-relative coords.
      local pr = hudParent()
      if pr and api.Game and api.Game.executeEvents and api.Game.Events then
        local gx = w:getX() - pr:getX()
        local gy = w:getY() - pr:getY()
        pcall(function() api.Game.executeEvents(api.Game.Events.HUD_DRAG, elemId, gx, gy) end)
      end
      return true
    end

    -- Left click  -> per-instance callback (if any) + HUD_CLICK event.
    -- Right click -> Lock/Unlock position menu (player-side, no script needed).
    w.onMousePress = function(_, mp, btn)
      if btn == MouseRightButton then
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)
        menu:addOption(self._locked and tr('Unlock position') or tr('Lock position'), function()
          self._locked = not self._locked
          applyDraggable()
          persistField('locked', self._locked)
        end)
        menu:display(mp)
        return true
      end
      return false
    end
    w.onClick = function()
      -- Per-instance stored callback (already wrapped in ctx.wrap at set time).
      if self._onClick then self._onClick(self) end
      -- Global HUD_CLICK dispatch (lazy via api.Game).
      if api.Game and api.Game.executeEvents and api.Game.Events then
        pcall(function() api.Game.executeEvents(api.Game.Events.HUD_CLICK, elemId) end)
      end
    end

    -- Track on the owning script + register teardown (destroyed on unload/relog).
    owner.huds = owner.huds or {}
    owner.huds[elemId] = self
    self._cleanup = ctx.onCleanup(function() self:destroy() end)

    return self
  end

  -- ---- constructors -------------------------------------------------------
  -- HUD.new(x, y, value, newFeatures?): text HUD if value is a string, item HUD if
  -- value is a number (itemId) -- mirrors Zerobot's overloaded hudTextCreate/
  -- hudItemCreate. `newFeatures` is accepted for signature parity (our widget-based
  -- HUD always supports alignment/scale/opacity, so the flag is a no-op here).
  function HUD.new(x, y, value, _newFeatures)
    local kind = (type(value) == 'number') and 'item' or 'text'
    return build(kind, x, y, value)
  end

  function HUD.newSpellIcon(x, y, spellId, _newFeatures)
    return build('sprite', x, y, spellId)
  end

  function HUD.newOutfit(x, y, outfitId, _newFeatures)
    return build('outfit', x, y, outfitId)
  end

  -- ---- instance methods ---------------------------------------------------
  function HUD:getId() return self._id end

  -- Current map-relative position (0,0 if the panel/widget is gone).
  function HUD:getPos()
    local pr = hudParent()
    if pr and alive(self._w) then
      return { x = self._w:getX() - pr:getX(), y = self._w:getY() - pr:getY() }
    end
    return { x = 0, y = 0 }
  end

  -- Set map-relative position (persisted, like a drag drop).
  function HUD:setPos(x, y)
    local pr = hudParent()
    if pr and alive(self._w) then
      x, y = clampInt(x, 0), clampInt(y, 0)
      self._w:setPosition({ x = pr:getX() + x, y = pr:getY() + y })
      pcall(function() self._w:bindRectToParent() end)
      if self._persistField then self._persistField() end
    end
    return self
  end

  -- Alignment margins are 0,0 in this widget-based HUD (we have no native margin
  -- offsets); returned for Zerobot parity.
  function HUD:getMargins() return { x = 0, y = 0 } end

  function HUD:setSize(width, height)
    if alive(self._w) then
      self._w:setSize({ width = clampInt(width, 40), height = clampInt(height, 52) })
    end
    return self
  end

  -- Scale the icon renderers that support a real transform (sprite/outfit/item all
  -- have UIWidget-C++ setScale). Text has no widget-level transform in the engine, so
  -- for a text HUD we approximate scale by re-rasterizing the caption font from the
  -- 11px base -- keeping setScale meaningful for every HUD kind instead of a silent
  -- no-op on text.
  function HUD:setScale(value)
    value = tonumber(value) or 1
    if alive(self._sprite) then pcall(function() self._sprite:setScale(value) end) end
    if alive(self._outfit) then pcall(function() self._outfit:setScale(value) end) end
    if alive(self._iconItem) then pcall(function() self._iconItem:setScale(value) end) end
    if self._caption and alive(self._caption) then self:setFontSize(11 * value) end
    return self
  end

  function HUD:setOpacity(value)
    if alive(self._w) then pcall(function() self._w:setOpacity(tonumber(value) or 1) end) end
    return self
  end

  function HUD:setVisible(v)
    if alive(self._w) then self._w:setVisible(v and true or false) end
    return self
  end
  function HUD:show() return self:setVisible(true) end
  function HUD:hide() return self:setVisible(false) end

  function HUD:setPhantom(phantom)
    if alive(self._w) then self._w:setPhantom(phantom and true or false) end
    return self
  end

  -- Draw order within the map panel.
  function HUD:setZIndex(z)
    if alive(self._w) then pcall(function() self._w:raise() end) end -- raise to top
    -- (UIWidget has no absolute z-index setter; raising is the supported control.)
    return self
  end

  function HUD:setDraggable(on)
    self._wantDrag = on and true or false
    if self._applyDraggable then self._applyDraggable() end
    return self
  end

  function HUD:setLocked(on)
    self._locked = on and true or false
    if self._applyDraggable then self._applyDraggable() end
    if self._persistField then self._persistField('locked', self._locked) end
    return self
  end
  function HUD:isLocked() return self._locked == true end

  -- Alignment: ScriptHudIcon centers its caption; we map the ZB alignment enum onto
  -- the caption's text alignment (the meaningful target in a widget-based HUD).
  function HUD:setHorizontalAlignment(alignment)
    if not (self._caption and alive(self._caption)) then return self end
    local A = api.Enums and api.Enums.HorizontalAlign
    local name = 'center'
    if A then
      if alignment == A.Left then name = 'left'
      elseif alignment == A.Right then name = 'right'
      elseif alignment == A.Center then name = 'center' end
    end
    self._hAlign = name
    pcall(function() self._caption:setTextAlign(self:_composeAlign()) end)
    return self
  end

  function HUD:setVerticalAlignment(alignment)
    if not (self._caption and alive(self._caption)) then return self end
    local A = api.Enums and api.Enums.VerticalAlign
    local name = 'center'
    if A then
      if alignment == A.Top then name = 'top'
      elseif alignment == A.Bottom then name = 'bottom'
      elseif alignment == A.Center then name = 'center' end
    end
    self._vAlign = name
    pcall(function() self._caption:setTextAlign(self:_composeAlign()) end)
    return self
  end

  -- Combine the stored h/v alignment into an OTML text-align token (e.g. "topLeft",
  -- "center", "bottomRight").
  function HUD:_composeAlign()
    local v = self._vAlign or 'center'
    local h = self._hAlign or 'center'
    if v == 'center' and h == 'center' then return 'center' end
    if v == 'center' then return h end
    if h == 'center' then return v end
    -- v + Capitalized h, e.g. "top" + "Left" -> "topLeft".
    return v .. h:sub(1, 1):upper() .. h:sub(2)
  end

  -- Text HUD: set caption text.
  function HUD:setText(t)
    if self._caption and alive(self._caption) then self._caption:setText(tostring(t)) end
    return self
  end

  -- Text color. Accepts Zerobot's (r,g,b) triple OR a single color string/table.
  function HUD:setColor(r, g, b)
    if not (self._caption and alive(self._caption)) then return self end
    local color
    if type(r) == 'number' and type(g) == 'number' and type(b) == 'number' then
      color = { r = r, g = g, b = b, a = 255 }
    else
      color = r  -- a "#rrggbb"/named string or a {r,g,b,a} table
    end
    pcall(function() self._caption:setColor(color) end)
    return self
  end

  -- Rasterize the caption's TTF (verdanab.ttf) at the requested pixel size. The
  -- caption is NOT a fixed pixel-art font -- it's Verdana Bold TTF, and the engine's
  -- g_fonts.getFont("file.ttf@N") path renders any integer px size on demand into its
  -- OWN texture (not the shared glyph atlas, so no atlas-overflow risk) and caches it.
  -- Size 11 reuses the exact bold-mono default; other sizes use the antialiased
  -- dynamic path. Clamped to a sane 6..48 range.
  function HUD:setFontSize(fontSize)
    fontSize = math.max(6, math.min(48, clampInt(fontSize, 11)))
    if self._caption and alive(self._caption) then
      if fontSize == 11 then
        pcall(function() self._caption:setFont('Verdana Bold-11px') end)
      else
        pcall(function() self._caption:setFont('verdanab.ttf@' .. fontSize) end)
      end
    end
    self._fontSize = fontSize
    return self
  end

  -- Item HUD: swap the rendered item id (also flips this HUD into item mode).
  function HUD:setItemId(id)
    id = tonumber(id) or 0
    if self._iconItem and alive(self._iconItem) then
      pcall(function() self._iconItem:setItemId(id) end)
      self._iconItem:setVisible(id ~= 0)
    end
    if self._iconImage and alive(self._iconImage) then self._iconImage:setVisible(false) end
    if self._layoutCaption then self._layoutCaption(id ~= 0) end
    return self
  end

  -- Image HUD: render an image-source path in the icon slot (script asset). Hides
  -- the item sprite (mutually exclusive). Not a Zerobot native, but the natural
  -- analogue of the preserved bot.hud `image` option and useful for custom icons.
  function HUD:setImage(path)
    if self._iconImage and alive(self._iconImage) then
      self._iconImage:setImageSource(tostring(path))
      self._iconImage:setVisible(true)
    end
    if self._iconItem and alive(self._iconItem) then self._iconItem:setVisible(false) end
    if self._layoutCaption then self._layoutCaption(true) end
    return self
  end

  -- Spell-icon HUD: set the sprite id.
  function HUD:setSpellIconId(id)
    local sp = self._ensureSprite and self._ensureSprite()
    if sp and alive(sp) then pcall(function() sp:setSpriteId(tonumber(id) or 0) end) end
    return self
  end

  -- Outfit HUD: replace the whole outfit table ({type, addons, head, body, legs,
  -- feet, mount, ...}) or, via the helpers below, individual facets.
  function HUD:setOutfit(outfit)
    local oc = self._ensureOutfit and self._ensureOutfit()
    if oc and alive(oc) and type(outfit) == 'table' then
      pcall(function() oc:setOutfit(outfit) end)
    end
    return self
  end

  function HUD:setOutfitId(id)
    local oc = self._ensureOutfit and self._ensureOutfit()
    if oc and alive(oc) then pcall(function() oc:setOutfitId(tonumber(id) or 0) end) end
    return self
  end

  function HUD:setOutfitAddons(addons)
    local oc = self._ensureOutfit and self._ensureOutfit()
    if oc and alive(oc) then
      local cur = {}
      pcall(function() cur = oc:getOutfit() or {} end)
      cur.addons = tonumber(addons) or 0
      pcall(function() oc:setOutfit(cur) end)
    end
    return self
  end

  function HUD:setOutfitColors(head, body, legs, feet)
    local oc = self._ensureOutfit and self._ensureOutfit()
    if oc and alive(oc) then
      -- Native helper takes the four color indices directly.
      pcall(function() oc:setOutfitColors(head or 0, body or 0, legs or 0, feet or 0) end)
    end
    return self
  end

  -- Outfit facing. Accepts a Zerobot direction; converts to the engine direction
  -- (diagonals are remapped) via api.Enums.translate before applying.
  function HUD:setOutfitDirection(direction)
    local oc = self._ensureOutfit and self._ensureOutfit()
    if oc and alive(oc) then
      local engDir = direction
      if api.Enums and api.Enums.translate and api.Enums.translate.directionToEngine then
        engDir = api.Enums.translate.directionToEngine(direction) or direction
      end
      pcall(function() oc:setDirection(engDir) end)
    end
    return self
  end

  -- Idle vs walking animation (Zerobot setOutfitMoving) -> UICreature:setAnimate.
  function HUD:setOutfitMoving(moving)
    local oc = self._ensureOutfit and self._ensureOutfit()
    if oc and alive(oc) then pcall(function() oc:setAnimate(moving and true or false) end) end
    return self
  end

  -- Store an on-click callback. Wrapped with ctx.wrap so it runs in the owning
  -- script's context with pcall + error accounting (the script that OWNS this HUD).
  -- Must be wrapped while that script is the running one; for a HUD created and
  -- configured inside the load body that holds. A nil clears the callback.
  function HUD:setCallback(fn)
    if fn == nil then
      self._onClick = nil
    elseif type(fn) == 'function' then
      self._onClick = ctx.wrap(fn)
    else
      error('HUD:setCallback(fn): fn must be a function or nil', 2)
    end
    return self
  end

  -- Destroy the widget + drop it from the owning script + cancel its cleanup.
  function HUD:destroy()
    if alive(self._w) then pcall(function() self._w:destroy() end) end
    self._w, self._caption, self._iconItem, self._iconImage = nil, nil, nil, nil
    self._sprite, self._outfit = nil, nil
    if self._owner and self._owner.huds then self._owner.huds[self._id] = nil end
    if self._cleanup then
      pcall(function() self._cleanup.cancel() end)
      self._cleanup = nil
    end
  end

  -- ---- constructor sugar: HUD(...) and HUD.new(...) ------------------------
  -- HUD(x, y, value, nf?) == HUD.new(...). Also allow HUD:setCallback(fn) as the
  -- 4th positional arg form used by some Zerobot scripts: HUD(x,y,text, onClick).
  -- We detect a function in the 4th slot and bind it as the callback.
  local function callConstructor(_, x, y, value, fourth)
    local inst = HUD.new(x, y, value)
    if type(fourth) == 'function' then inst:setCallback(fourth) end
    return inst
  end

  return setmetatable(HUD, { __call = callConstructor })
end
