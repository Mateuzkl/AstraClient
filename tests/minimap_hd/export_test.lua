-- Synthetic OTB/OTBM and real DAT/SPR: no server files or login are required.
scheduleEvent(function()
  g_game.setProtocolVersion(860)
  g_game.setClientVersion(860)
  g_modules.ensureModuleLoaded('game_things')
  modules.game_things.load()
  local ground, common, top
  for _, thing in pairs(g_things.getThingTypes(ThingCategoryItem)) do
    if not ground and thing:isGround() and thing:getMinimapColor() > 0 and thing:getMinimapColor() ~= 255 then ground = thing end
    if not common and not thing:isGround() and not thing:isGroundBorder() and
       not thing:isOnBottom() and not thing:isOnTop() and thing:getElevation() > 0 and
       thing:getWidth() == 1 and thing:getHeight() == 1 then common = thing end
    if not top and thing:isOnTop() and thing:getWidth() == 1 and thing:getHeight() == 1 then top = thing end
  end
  assert(ground and common and top, 'Assets need ground, elevated common and top items')
  local function le(value, size)
    local bytes = {}
    for i = 1, size do bytes[i] = string.char(value % 256); value = math.floor(value / 256) end
    return table.concat(bytes)
  end
  local function node(props, children)
    props = props:gsub('[\253-\255]', function(byte) return '\253' .. byte end)
    return '\254' .. props .. (children or '') .. '\255'
  end
  local prefix = '/export-regression-' .. os.time() .. '-' .. g_clock.millis()
  local rootProps = '\0' .. le(0, 4) .. '\1' .. le(140, 2) .. le(3, 4) .. le(20, 4) .. le(0, 4) .. string.rep('\0', 128)
  local itemProps = '\1' .. le(0, 4) .. '\16' .. le(2, 2) .. le(20026, 2) .. '\17' .. le(2, 2) .. le(ground:getId(), 2)
  assert(g_resources.writeFileContents(prefix .. '.otb', le(0, 4) .. node(rootProps, node(itemProps))))
  g_things.loadOtbForMap(prefix .. '.otb')
  assert(g_things.isOtbLoaded())
  local areas = {}
  for i = 0, 63 do
    local area = '\4' .. le(96 + i * 64, 2) .. le(96, 2) .. string.char(7 + i % 2)
    local tile = '\5\12\12\9' .. le(20026, 2) -- OTBM_ATTR_ITEM: literal ServerID.
    areas[#areas + 1] = node(area, node(tile))
  end
  local header = '\0' .. le(2, 4) .. le(65535, 2) .. le(65535, 2) .. le(3, 4) .. le(20, 4)
  assert(g_resources.writeFileContents(prefix .. '.otbm', le(0, 4) .. node(header, node('\2', table.concat(areas)))))
  g_map.clean()
  g_minimap.clean()
  g_map.loadOtbm(prefix .. '.otbm')
  local pos = {x = 108, y = 108, z = 7}
  local otherFloor = {x = 172, y = 108, z = 8}
  local color = g_map.getMinimapColor(pos)
  assert(color ~= 255 and g_map.getMinimapColor(otherFloor) ~= 255,
         'OTBM loading did not reveal classic coverage on both floors')
  g_minimap.saveOtmm(prefix .. '.otmm')
  assert(g_resources.fileExists(prefix .. '.otmm'))
  g_map.clean()
  g_minimap.clean()
  assert(g_minimap.loadOtmm(prefix .. '.otmm'))
  assert(g_map.getMinimapColor(pos) == color and g_map.getMinimapColor(otherFloor) ~= 255,
         'Exported OTMM lost classic coverage')
  local paths = {}
  for _, kind in ipairs({'background', 'top', 'combined'}) do
    g_map.clean()
    if kind ~= 'top' then
      g_map.addThing(Item.create(ground:getId(), 1), pos, -1)
      g_map.addThing(Item.create(common:getId(), 1), pos, -1)
    end
    if kind ~= 'background' then g_map.addThing(Item.create(top:getId(), 1), pos, -1) end
    local directory = prefix .. '-' .. kind
    assert(g_minimap.exportSatelliteBase(directory) > 0)
    paths[kind] = g_resources.getWriteDir() .. directory .. '/satellite-1-96-96-7.png'
  end
  paths.elevation = math.min(24, ground:getElevation() + common:getElevation()) * g_sprites.spriteSize() / 32
  local fixture = prefix .. '.json'
  assert(g_resources.writeFileContents(fixture, json.encode(paths)))
  g_logger.info('[HD MINIMAP TEST] EXPORT FIXTURE: ' .. g_resources.getWriteDir() .. fixture)
  g_logger.info('[HD MINIMAP TEST] PASS: synthetic OTB/OTBM, literal ServerID 20026, classic OTMM coverage, exported terrain layers')
  scheduleEvent(g_app.exit, 500)
end, 1000)
