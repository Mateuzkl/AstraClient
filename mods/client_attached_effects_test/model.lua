-- Standalone UI owners only. Never attach to g_game.getLocalPlayer(), mutate
-- assets/features, send packets, or clear registrations belonging to another mod.
AttachedEffectsTestModel = {}
local Model = AttachedEffectsTestModel

-- Same image sizes/anchors as OpenTibiaBR's game_attachedeffects presets.
Model.imagePresets = {
  {name = 'Pentagram Aura', path = '/images/game/effects/pentagram.png',
   size = {width = 128, height = 128}, x = 50, y = 45, onTop = false, loop = -1},
  {name = 'Ki', path = '/images/game/effects/ki.png',
   size = {width = 140, height = 110}, x = 60, y = 75, onTop = true, loop = -1},
  {name = 'Thunder', path = '/images/game/effects/thunder.png',
   x = 215, y = 230, onTop = false, loop = 1}
}

function Model.normalizeImagePath(path)
  return (path or ''):match('^%s*(.-)%s*$')
end

function Model.findImagePreset(path)
  path = Model.normalizeImagePath(path)
  for index, preset in ipairs(Model.imagePresets) do
    if path == preset.path or path .. '.png' == preset.path then return index, preset end
  end
  return 0
end

local function validId(id, category, optional)
  return optional and id == 0 or g_things.isValidDatId(id, category)
end

function Model.newOwner(config)
  assert(g_things.isDatLoaded() and g_sprites.isLoaded(), 'Select/load DAT and SPR assets first.')
  for _, field in ipairs({'outfit', 'mount', 'wings', 'aura'}) do
    assert(validId(config[field], ThingCategoryCreature, field ~= 'outfit'),
           'Invalid ' .. field .. ' ID in the loaded DAT: ' .. tostring(config[field]))
  end
  local owner = Creature.create()
  owner:setName('Attached Effects Simulator')
  owner:setOutfit({type = config.outfit, mount = config.mount, wings = config.wings, aura = config.aura,
                  head = 78, body = 68, legs = 58, feet = 76, addons = 3})
  return owner
end

function Model.destroy(scene)
  if not scene then return end
  for _, owner in ipairs(scene.owners) do owner:clearAttachedEffects(true) end
  scene.owners = {}
end

local function configure(effect, config, child)
  effect:setSpeed(config.speed)
  effect:setOpacity(config.opacity)
  effect:setDuration(config.duration)
  effect:setLoop(config.loop)
  effect:setPermanent(false)
  effect:setCanDrawOnUI(true)
  effect:setDrawOrder(child and 5 or config.order)
  effect:setOnTop(config.onTop)
  effect:setOffset(config.x + (child and -12 or 0), config.y + (child and 12 or 0))
  if config.size and effect:getThingCategory() == ThingExternalTexture then effect:setSize(config.size) end
  effect:setShader(config.shader)
  effect:setHideOwner(not child and config.hideOwner)
  if config.bounce then effect:setBounce(0, 6, 1000) end
end

function Model.create(config)
  assert(config.count >= 1 and config.count <= 500 and config.count == math.floor(config.count),
         'Preview count must be between 1 and 500.')
  assert(config.copies >= 1 and config.copies <= 8 and config.copies == math.floor(config.copies),
         'Effects per preview must be between 1 and 8.')
  assert(AttachedEffect and AttachedEffect.create, 'This executable needs native Attached Effects support.')
  local scene, registrations = {owners = {}}, {}
  local function image(id)
    local imagePath = Model.normalizeImagePath(config.imagePath)
    local _, preset = Model.findImagePreset(imagePath)
    if preset then imagePath = preset.path end
    assert(imagePath:sub(1, 1) == '/' and g_resources.fileExists(imagePath),
           'Use an existing absolute resource path for PNG/APNG.')
    local effect = g_attachedEffects.registerByImage(id, 'Local simulator fixture', imagePath, true)
    assert(effect, 'Cannot load image or simulator ID ' .. id .. ' is already occupied.')
    registrations[#registrations + 1] = id
    return effect
  end
  local ok, failure = xpcall(function()
    -- Validate outfit IDs before allocating image registrations or many owners.
    scene.owners[1] = Model.newOwner(config)
    local templates = {}
    local imageChild = config.imageChild and image(65520) or nil
    for copy = 1, config.copies do
      local root
      if config.category == ThingExternalTexture then
        -- Distinct temporary IDs allow multiple image roots on one owner.
        root = image(65530 - copy)
      else
        assert(validId(config.source, config.category), 'Invalid DAT source ID/category.')
        root = assert(AttachedEffect.create(config.source, config.category), 'Cannot create DAT effect.')
      end
      configure(root, config, false)
      if config.nested then
        local category = config.category == ThingExternalTexture and ThingCategoryEffect or config.category
        local source = config.category == ThingExternalTexture and 1 or config.source
        local child = assert(AttachedEffect.create(source, category), 'Nested DAT source is unavailable.')
        configure(child, config, true)
        root:attachEffect(child)
      end
      if imageChild then
        local child = imageChild:clone()
        configure(child, config, true)
        root:attachEffect(child)
      end
      templates[copy] = root
    end
    for index = 1, config.count do
      local owner = scene.owners[index] or Model.newOwner(config)
      scene.owners[index] = owner
      for _, template in ipairs(templates) do owner:attachEffect(template:clone()) end
    end
  end, debug.traceback)
  -- Remove only registrations successfully created by this operation. Runtime
  -- clones keep their texture references; the manager is not cleared globally.
  for _, id in ipairs(registrations) do g_attachedEffects.remove(id) end
  if not ok then
    Model.destroy(scene)
    error(failure, 0)
  end
  return scene
end

function Model.probe(config, duration)
  local category = config.category == ThingExternalTexture and ThingCategoryEffect or config.category
  local source = config.category == ThingExternalTexture and 1 or config.source
  local effect = assert(AttachedEffect.create(source, category), 'Select a valid DAT source for cycles.')
  effect:setDuration(duration)
  effect:setLoop(-1)
  return effect -- Native ad-hoc ID zero: no registration and no deduplication.
end
