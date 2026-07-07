if not Shaders then
  Shaders = {
    shader = 'map_default',
    positions = {
      {fromPos = {x = 30879, y = 33641, z = 7}, toPos = {x = 30915, y = 33677, z = 7}, shader = "heat_distortion"}, -- lab1
      {fromPos = {x = 30952, y = 33643, z = 5}, toPos = {x = 30988, y = 33679, z = 5}, shader = "heat_distortion"}, -- lever

      {fromPos = {x = 30887, y = 33649, z = 2}, toPos = {x = 30909, y = 33671, z = 2}, shader = "heat_distortion"}, -- boss1
      {fromPos = {x = 30959, y = 33585, z = 2}, toPos = {x = 30982, y = 33608, z = 2}, shader = "heat_distortion"}, -- boss2
      {fromPos = {x = 31030, y = 33649, z = 2}, toPos = {x = 31052, y = 33671, z = 2}, shader = "heat_distortion"}, -- boss3
    }
  }
end

function init()
  -- add manually your shaders from /data/shaders

  -- image shaders
  g_shaders.createShader("image_black_white", "/shaders/image_black-white_vertex", "/shaders/image_black-white_fragment")
  g_shaders.createShader("image_disabled", "/shaders/image_black-white_vertex", "/shaders/image-disabled")
  g_shaders.createShader("outfit_disable", "/shaders/outfit-disable_vertex", "/shaders/outfit-disable_fragment")

  -- map shaders
  g_shaders.createShader("map_default", "/shaders/map_default_vertex", "/shaders/map_default_fragment")
  g_shaders.setupMapShader("map_default")

  g_shaders.createShader("map_rainbow", "/shaders/map_rainbow_vertex", "/shaders/map_rainbow_fragment")
  g_shaders.addTexture("map_rainbow", "/images/shaders/rainbow.png")
  g_shaders.setupMapShader("map_rainbow")

  -- outfit shaders
  g_shaders.createOutfitShader("outfit_default", "/shaders/outfit_default_vertex", "/shaders/outfit_default_fragment")
  g_shaders.setupOutfitShader("outfit_default")

  g_shaders.createOutfitShader("outfit_rainbow", "/shaders/outfit_rainbow_vertex", "/shaders/outfit_rainbow_fragment")
  g_shaders.addTexture("outfit_rainbow", "/images/shaders/rainbow.png")
  g_shaders.setupOutfitShader("outfit_rainbow")

  g_shaders.createOutfitShader("outfit_black", "/shaders/outfit_black_vertex", "/shaders/outfit_black_fragment")
  g_shaders.addTexture("outfit_black", "/images/shaders/black.png")
  g_shaders.setupOutfitShader("outfit_black")

  -- item shaders
  g_shaders.createShader("item_black", "/shaders/image_black-white_vertex", "/shaders/image_black_fragment")
  g_shaders.createShader("item_red", "/shaders/image_black-white_vertex", "/shaders/image_red_fragment")
  g_shaders.createShader("item_green", "/shaders/image_black-white_vertex", "/shaders/image_green_fragment")
  g_shaders.createShader("item_black_white", "/shaders/image_black-white_vertex", "/shaders/image_black_white_fragment")
  g_shaders.createShader("item_print_white", "/shaders/image_black-white_vertex", "/shaders/item_print_fragment")
  g_shaders.createShader("item_print_print_black_white", "/shaders/image_black-white_vertex", "/shaders/item_print_black_white_fragment.frag")

  -- Dummy Level System halo shaders (see src/client/item.cpp Item::draw and the server
  -- lib data-koliseu/lib/dummy/dummy_level_lib.lua). One silhouette shader per dummy
  -- level 1..10: it paints the whole sprite shape in a single flat colour while keeping
  -- the sprite's own alpha, and Item::draw stamps it 8x offset behind the real sprite so
  -- what shows around the dummy is a level-coloured outline/halo. Colour ramp requested:
  -- white -> green -> blue -> red, with the odd levels 3/6/9 sitting halfway between the
  -- two neighbouring anchor colours.
  local dummyHaloAnchors = {
    white = { 1.00, 1.00, 1.00 },
    green = { 0.16, 0.90, 0.24 },
    blue  = { 0.18, 0.42, 1.00 },
    red   = { 1.00, 0.18, 0.15 },
  }
  local function dummyHaloMix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
  end
  local w, gr, bl, rd = dummyHaloAnchors.white, dummyHaloAnchors.green, dummyHaloAnchors.blue, dummyHaloAnchors.red
  local dummyHaloRamp = {
    w, w,                    -- 1, 2  white
    dummyHaloMix(w, gr, 0.5), -- 3     white <-> green
    gr, gr,                  -- 4, 5  green
    dummyHaloMix(gr, bl, 0.5),-- 6     green <-> blue
    bl, bl,                  -- 7, 8  blue
    dummyHaloMix(bl, rd, 0.5),-- 9     blue  <-> red
    rd,                      -- 10    red
  }
  for level = 1, 10 do
    local c = dummyHaloRamp[level]
    local frag = string.format([[
varying vec2 v_TexCoord;
uniform sampler2D u_Tex0;
uniform float u_Time;
void main() {
    float a = texture2D(u_Tex0, v_TexCoord).a;
    if (a < 0.3) discard;
    // Blink: pulse the halo alpha between ~0.15 and 1.0 at ~1 Hz. u_Time (seconds) is
    // fed every frame by Painter::drawCoords -> PainterShaderProgram::updateTime().
    float pulse = 0.15 + 0.85 * (0.5 + 0.5 * sin(u_Time * 6.0));
    gl_FragColor = vec4(%.4f, %.4f, %.4f, a * pulse);
}
]], c[1], c[2], c[3])
    g_shaders.createShader("dummy_halo_" .. level, "/shaders/image_black-white_vertex", frag)
  end

  -- text
  g_shaders.createShader("text_golden_shadow_bold", "/shaders/text_golden_shadow_bold_vertex", "/shaders/text_golden_shadow_bold_fragment")
  g_shaders.createShader("text_golden_shadow_solid", "/shaders/text_golden_shadow_solid_vertex", "/shaders/text_golden_shadow_solid_fragment")
  
  g_shaders.createShader("text_staff", "/shaders/text_staff_vertex", "/shaders/text_staff_fragment")
  g_shaders.addTexture("text_staff", "/images/shaders/gold-monochrome.png")

  g_shaders.createShader("text_blue", "/shaders/text_staff_vertex", "/shaders/text_staff_fragment")
  g_shaders.addTexture("text_blue", "/images/shaders/blue-monochrome.png")

  g_shaders.createShader("text_coming", "/shaders/text_staff_vertex", "/shaders/text_staff_fragment")
  g_shaders.addTexture("text_coming", "/images/shaders/gold-monochrome.png")

  g_shaders.createShader("text_green", "/shaders/text_staff_vertex", "/shaders/text_staff_fragment")
  g_shaders.addTexture("text_green", "/images/shaders/green-monochrome.png")

  g_shaders.createShader("text_light_red", "/shaders/text_staff_vertex", "/shaders/text_staff_fragment")
  g_shaders.addTexture("text_light_red", "/images/shaders/midred-monochrome.png")

  -- Prestige Arena text shaders
  g_shaders.createShader("text_newbie", "/shaders/text_staff_vertex", "/shaders/text_staff_fragment")
  g_shaders.addTexture("text_newbie", "/images/shaders/newbie-monochrome.png")
  g_shaders.createShader("text_wooden", "/shaders/text_staff_vertex", "/shaders/text_staff_fragment")
  g_shaders.addTexture("text_wooden", "/images/shaders/wooden-monochrome.png")
  g_shaders.createShader("text_gold", "/shaders/text_staff_vertex", "/shaders/text_staff_fragment")
  g_shaders.addTexture("text_gold", "/images/shaders/gold-monochrome2.png")
  g_shaders.createShader("text_platinum", "/shaders/text_staff_vertex", "/shaders/text_staff_fragment")
  g_shaders.addTexture("text_platinum", "/images/shaders/platinum-monochrome.png")
  g_shaders.createShader("text_crystal", "/shaders/text_staff_vertex", "/shaders/text_staff_fragment")
  g_shaders.addTexture("text_crystal", "/images/shaders/crystal-monochrome.png")
  g_shaders.createShader("text_terror", "/shaders/text_staff_vertex", "/shaders/text_staff_fragment")
  g_shaders.addTexture("text_terror", "/images/shaders/terror-monochrome.png")
  g_shaders.createShader("text_champion", "/shaders/text_staff_vertex", "/shaders/text_staff_fragment")
  g_shaders.addTexture("text_champion", "/images/shaders/champion-monochrome.png")
  g_shaders.createShader("text_exalted", "/shaders/text_staff_vertex", "/shaders/text_staff_fragment")
  g_shaders.addTexture("text_exalted", "/images/shaders/exalted-monochrome.png")
  g_shaders.createShader("text_megalomaniac", "/shaders/text_staff_vertex", "/shaders/text_staff_fragment")
  g_shaders.addTexture("text_megalomaniac", "/images/shaders/megalomaniac-monochrome.png")
  g_shaders.createShader("text_sanguinum", "/shaders/text_staff_vertex", "/shaders/text_staff_fragment")
  g_shaders.addTexture("text_sanguinum", "/images/shaders/sanguinum-monochrome.png")
  g_shaders.createShader("text_warlord", "/shaders/text_staff_vertex", "/shaders/text_staff_fragment")
  g_shaders.addTexture("text_warlord", "/images/shaders/warlord-monochrome.png")

  -- UI
  -- g_shaders.createShader("draw_arcs", "/shaders/draw_vertex", "/shaders/draw_fragment")

  g_shaders.createShader("heat_distortion", "shaders/map/heat_distortion_vertex", "shaders/map/heat_distortion_fragment")
  g_shaders.setupMapShader("heat_distortion")


  g_shaders.createFragmentShader("item_mirror", "shaders/item/item_mirror_fragment")

  connect(g_game, { onChangeArea = onChangeArea })
  connect(LocalPlayer, { onPositionChange = onPositionChange })
end

function terminate()
  disconnect(g_game, { onChangeArea = onChangeArea })
  disconnect(LocalPlayer, { onPositionChange = onPositionChange })
end

function clearMapShader()
  local gameMapPanel = m_interface.getMapPanel()
  if gameMapPanel then
    gameMapPanel:setShader('')
  end
end

function onChangeArea(areaID, subAreaID)
  if not m_settings.getOption('enableShaders') then
    return
  end
  -- local gameMapPanel = m_interface.getMapPanel()
  -- if gameMapPanel then
  --   gameMapPanel:setShader('heat_distortion')
  -- end
end

function onPositionChange(localPlayer, newPos, oldPos)
  if not m_settings.getOption('enableShaders') then
    return
  end

  for i = 1, #Shaders.positions do
    local pos = Shaders.positions[i]
    if newPos.x >= pos.fromPos.x and newPos.y >= pos.fromPos.y and newPos.x <= pos.toPos.x and newPos.y <= pos.toPos.y then
      if Shaders.shader ~= pos.shader then
        Shaders.shader = pos.shader
        local gameMapPanel = m_interface.getMapPanel()
        if gameMapPanel then
          gameMapPanel:setShader(Shaders.shader)
        end
      end
      return
    end
  end

  if Shaders.shader ~= 'map_default' then
    Shaders.shader = 'map_default'
    local gameMapPanel = m_interface.getMapPanel()
    if gameMapPanel then
      gameMapPanel:setShader('')
    end
  end
end
