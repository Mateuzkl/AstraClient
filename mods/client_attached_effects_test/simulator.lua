-- Opt-in: Ctrl+T, then g_modules.ensureModuleLoaded('client_attached_effects_test')
-- Reopen with Ctrl+Alt+E. DAT/SPR must already be loaded (no login required).
local window, button, scene, metricEvent, stressEvent, stress
local fields, views = {}, {}
local Model = AttachedEffectsTestModel

local function status(text, failed)
  if not window then return end
  local label = window:getChildById('status')
  label:setText(text)
  label:setColor(failed and '#ff7777' or '#b8d8a8')
end

local function place(widget, row, column, span, input)
  widget:addAnchor(AnchorTop, 'parent', AnchorTop)
  widget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  widget:setMarginTop(row * 44 + (input and 18 or 0))
  widget:setMarginLeft(column * 82)
  widget:setSize({width = 82 * span - 6, height = input and 20 or 16})
end

local function field(id, title, row, column, span, value, minimum, maximum, options)
  local parent = window:getChildById('controls')
  local label = g_ui.createWidget('Label', parent)
  label:setText(title)
  place(label, row, column, span, false)
  local widget = g_ui.createWidget(options and 'ComboBox' or minimum and 'AETestSpinBox' or 'TextEdit', parent)
  widget:setId(id)
  place(widget, row, column, span, true)
  if options then
    for _, option in ipairs(options) do widget:addOption(option[1], option[2], true) end
    widget:setCurrentOptionByData(value, true)
  elseif minimum then
    widget:setMinimum(minimum)
    widget:setMaximum(maximum)
    widget:setValue(value, true)
  else
    widget:setText(value)
  end
  fields[id] = widget
end

function refreshPlayback()
  local direction = fields.direction:getCurrentOption().data
  for _, view in ipairs(views) do
    view:setDirection(direction)
    view:setAnimate(not fields.pause:isChecked())
    view:setStaticWalking(fields.walking:isChecked())
    view:setAutoRotating(fields.rotate:isChecked() and not fields.pause:isChecked())
  end
end

local function check(id, title, row, column)
  local widget = g_ui.createWidget('CheckBox', window:getChildById('controls'))
  widget:setId(id)
  widget:setText(title)
  widget:addAnchor(AnchorTop, 'parent', AnchorTop)
  widget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  widget:setMarginTop(314 + row * 26)
  widget:setMarginLeft(column * 164)
  widget:setWidth(158)
  fields[id] = widget
  if id == 'pause' or id == 'walking' or id == 'rotate' then widget.onCheckChange = refreshPlayback end
end

local function readConfig()
  local config = {}
  for _, id in ipairs({'outfit', 'mount', 'wings', 'aura', 'source', 'copies', 'x', 'y',
                       'duration', 'loop', 'order', 'count'}) do config[id] = fields[id]:getValue() end
  for _, id in ipairs({'onTop', 'nested', 'imageChild', 'bounce', 'hideOwner'}) do
    config[id] = fields[id]:isChecked()
  end
  config.speed = fields.speed:getValue() / 100
  config.opacity = fields.opacity:getValue() / 100
  config.shader = fields.shader:getText():match('^%s*(.-)%s*$')
  config.imagePath = Model.normalizeImagePath(fields.imagePath:getText())
  config.category = fields.category:getCurrentOption().data
  local _, preset = Model.findImagePreset(config.imagePath)
  if preset and config.category == ThingExternalTexture then
    config.imagePath, config.size = preset.path, preset.size
  end
  return config
end

local function applyImagePreset(preset)
  fields.category:setCurrentOptionByData(ThingExternalTexture, true)
  fields.x:setValue(preset.x, true)
  fields.y:setValue(preset.y, true)
  fields.onTop:setChecked(preset.onTop)
  fields.loop:setValue(preset.loop, true)
  fields.duration:setValue(0, true)
  status(preset.name .. ' selected with the reference size and offsets. Click Apply / Restart to preview.')
end

local function selectImagePreset()
  local preset = Model.imagePresets[fields.imagePreset:getCurrentOption().data]
  if not preset then return end
  applyImagePreset(preset)
  fields.imagePath:setText(preset.path)
end

local function syncImagePreset()
  local index, preset = Model.findImagePreset(fields.imagePath:getText())
  fields.imagePreset:setCurrentOptionByData(index, true)
  -- Typing/pasting a shipped image is equivalent to selecting its preset. Do
  -- not reset offsets on Apply, so subsequent manual placement edits still work.
  if preset then applyImagePreset(preset) end
end

local function stopStress()
  removeEvent(stressEvent)
  stressEvent = nil
  if stress then stress.owner:clearAttachedEffects(true) end
  stress = nil
end

local function clearScene()
  Model.destroy(scene)
  scene = nil
  views = {}
  if window then window:recursiveGetChildById('previews'):destroyChildren() end
end

local function metrics()
  metricEvent = nil
  if not window or not window:isVisible() then return end
  local active = 0
  for _, owner in ipairs(scene and scene.owners or {}) do active = active + #owner:getAttachedEffects() end
  local memory = g_platform.getMemoryUsage()
  local memoryLabel = ''
  if memory > 0 then
    local browser = g_platform.getOSName():find('Browser', 1, true)
    memoryLabel = string.format(' | %s %.1f MiB', browser and 'WASM capacity' or 'Working set', memory / 1048576)
  end
  window:recursiveGetChildById('metrics'):setText(string.format(
    'Previews: %d | Active root effects: %d\nFPS: %d | Lua: %.2f MiB%s\nUI load only; not a map/server benchmark.',
    scene and #scene.owners or 0, active, g_app.getFps(), collectgarbage('count') / 1024, memoryLabel))
  metricEvent = scheduleEvent(metrics, 1000)
end

function apply()
  if not window then return end
  stopStress()
  local config = readConfig()
  local ok, result = pcall(Model.create, config)
  if not ok then status(tostring(result), true); return end
  clearScene()
  scene = result
  local panel = window:recursiveGetChildById('previews')
  local size = panel:getSize()
  local columns = math.min(config.count, math.max(1, math.ceil(math.sqrt(config.count * size.width / math.max(1, size.height)))))
  local rows = math.ceil(config.count / columns)
  local cell = {width = math.max(1, math.floor((size.width - 2 * (columns - 1)) / columns)),
                height = math.max(1, math.floor((size.height - 2 * (rows - 1)) / rows))}
  panel:getLayout():setNumColumns(columns)
  panel:getLayout():setCellSize(cell)
  for _, owner in ipairs(scene.owners) do
    local view = g_ui.createWidget('AETestPreview', panel)
    view:setCreature(owner)
    view:setCenter(true)
    views[#views + 1] = view
  end
  refreshPlayback()
  status(string.format('%d previews x %d root effects. Nested children use order 5; roots use order %d. ' ..
                       'Finite effects continue expiring while animation is paused.', config.count, config.copies, config.order))
end

function copyPlayer()
  local player = g_game.getLocalPlayer()
  if not player then status('No player is logged in. Enter the local DAT outfit IDs manually.', true); return end
  local outfit = player:getOutfit()
  fields.outfit:setValue(outfit.type, true)
  for _, id in ipairs({'mount', 'wings', 'aura'}) do fields[id]:setValue(outfit[id] or 0, true) end
  apply() -- Copies IDs to fresh previews; never changes the actual player.
end

local function stressStep(state, waiting)
  stressEvent = nil
  if stress ~= state or not window or not window:isVisible() then return end
  local ok, failure = pcall(function()
    if waiting then
      if #state.owner:getAttachedEffects() ~= 0 then
        assert(g_clock.millis() < state.deadline, 'Timed expiration did not detach the effects.')
        stressEvent = scheduleEvent(function() stressStep(state, true) end, 25)
        return
      end
      state.completed = state.completed + state.batch
    elseif not state.expiration then
      for _ = 1, state.batch do
        local effect = Model.probe(state.config, 0)
        state.owner:attachEffect(effect)
        assert(#state.owner:getAttachedEffects() == 1, 'Attach failed.')
        assert(state.owner:detachEffect(effect), 'Detach failed.')
        assert(#state.owner:getAttachedEffects() == 0, 'Detach retained an effect.')
      end
      state.completed = state.completed + state.batch
    end
    if state.completed >= 1000 then
      stopStress()
      status('Completed 1000 native ' .. (state.expiration and 'timed expirations' or 'attach/detach cycles') ..
             '. This checks lifecycle behavior, not leak freedom.')
      return
    end
    status(string.format('Running native %s: %d / 1000. Close or Stop cancels this test.',
                         state.expiration and 'expirations' or 'attach/detach cycles', state.completed))
    if state.expiration then
      for _ = 1, state.batch do state.owner:attachEffect(Model.probe(state.config, 25)) end
      assert(#state.owner:getAttachedEffects() == state.batch, 'Expiration batch attach failed.')
      state.deadline = g_clock.millis() + 2000
      stressEvent = scheduleEvent(function() stressStep(state, true) end, 60)
    else
      stressEvent = scheduleEvent(function() stressStep(state, false) end, 10)
    end
  end)
  if not ok then stopStress(); status(tostring(failure), true) end
end

function runCycles(expiration)
  if not window then return end
  stopStress()
  local config = readConfig()
  local ok, owner = pcall(Model.newOwner, config)
  if not ok then status(tostring(owner), true); return end
  stress = {owner = owner, config = config, completed = 0, batch = 25, expiration = expiration}
  stressStep(stress, false)
end

function clear()
  stopStress()
  clearScene()
  status('Local previews cleared and simulator events stopped. No server or asset data was changed.')
end

function hide()
  removeEvent(metricEvent)
  metricEvent = nil
  clear()
  if window then window:hide() end
  if button then button:setOn(false) end
end

function show()
  if not window then return end
  window:show()
  window:raise()
  window:focus()
  button:setOn(true)
  removeEvent(metricEvent)
  metrics()
end

function toggle()
  if window and window:isVisible() then hide() else show() end
end

local function onAssetsReload()
  clear()
  status('DAT reloaded. Verify IDs and click Apply again.')
end

function init()
  window = g_ui.displayUI('simulator')
  field('outfit', 'Outfit ID', 0, 0, 1, 128, 1, 65535)
  field('mount', 'Mount ID', 0, 1, 1, 0, 0, 65535)
  field('wings', 'Wings ID', 0, 2, 1, 0, 0, 65535)
  field('aura', 'Aura ID', 0, 3, 1, 0, 0, 65535)
  field('category', 'Source', 1, 0, 2, ThingCategoryEffect, nil, nil,
        {{'Effect (DAT)', ThingCategoryEffect}, {'Creature (DAT)', ThingCategoryCreature},
         {'Missile (DAT)', ThingCategoryMissile}, {'Item (DAT)', ThingCategoryItem},
         {'PNG / APNG', ThingExternalTexture}})
  field('source', 'Source ID', 1, 2, 1, 12, 1, 65535)
  field('copies', 'Effects each', 1, 3, 1, 1, 1, 8)
  field('x', 'Offset X', 2, 0, 1, 0, -32768, 32767)
  field('y', 'Offset Y', 2, 1, 1, 0, -32768, 32767)
  field('speed', 'Speed %', 2, 2, 1, 100, 1, 1000)
  field('opacity', 'Opacity %', 2, 3, 1, 100, 0, 100)
  field('duration', 'Duration ms', 3, 0, 1, 3000, 0, 60000)
  field('loop', 'Loops (-1=inf)', 3, 1, 1, -1, -1, 65535)
  field('order', 'Root order', 3, 2, 1, 1, 0, 5)
  field('count', 'Previews', 3, 3, 1, 1, 1, 500)
  field('direction', 'Direction', 4, 0, 2, Directions.South, nil, nil,
        {{'North', Directions.North}, {'East', Directions.East}, {'South', Directions.South},
         {'West', Directions.West}, {'North East', Directions.NorthEast}, {'South East', Directions.SouthEast},
         {'South West', Directions.SouthWest}, {'North West', Directions.NorthWest}})
  field('shader', 'Shader (optional)', 4, 2, 2, '')
  local presetOptions = {{'Custom / DAT', 0}}
  for index, preset in ipairs(Model.imagePresets) do
    presetOptions[#presetOptions + 1] = {preset.name, index}
  end
  field('imagePreset', 'OpenTibiaBR image preset', 5, 0, 4, 0, nil, nil, presetOptions)
  field('imagePath', 'PNG/APNG resource path', 6, 0, 4, '/images/animations/animation-fire-bowl.png')
  check('onTop', 'On top of outfit', 0, 0)
  check('nested', 'Nested DAT child', 0, 1)
  check('imageChild', 'PNG/APNG child', 1, 0)
  check('bounce', 'Bounce', 1, 1)
  check('rotate', 'Auto rotate', 2, 0)
  check('walking', 'Walking animation', 2, 1)
  check('pause', 'Pause animation', 3, 0)
  check('hideOwner', 'Hide owner outfit', 3, 1)
  fields.direction.onOptionChange = refreshPlayback
  fields.imagePreset.onOptionChange = selectImagePreset
  fields.imagePath.onTextChange = syncImagePreset
  button = modules.client_topmenu.addLeftToggleButton('attachedEffectsTestButton',
             'Attached Effects Simulator (Ctrl+Alt+E)', '/images/topbuttons/debug', toggle)
  g_keyboard.bindKeyDown('Ctrl+Alt+E', toggle)
  connect(g_things, {onLoadDat = onAssetsReload})
  connect(g_game, {onGameEnd = hide})
  show()
end

function terminate()
  disconnect(g_things, {onLoadDat = onAssetsReload})
  disconnect(g_game, {onGameEnd = hide})
  g_keyboard.unbindKeyDown('Ctrl+Alt+E')
  hide()
  if window then window:destroy(); window = nil end
  if button then button:destroy(); button = nil end
  fields = {}
end
