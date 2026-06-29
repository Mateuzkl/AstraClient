/*
 * Copyright (c) 2010-2017 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "mapview.h"

#include "creature.h"
#include "map.h"
#include "tile.h"
#include "statictext.h"
#include "animatedtext.h"
#include "missile.h"
#include "lightview.h"
#include "localplayer.h"
#include "game.h"
#include "spritemanager.h"

#include <framework/graphics/graphics.h>
#include <framework/graphics/image.h>
#include <framework/graphics/framebuffermanager.h>
#include <framework/core/eventdispatcher.h>
#include <framework/core/application.h>
#include <framework/core/resourcemanager.h>
#include <framework/graphics/texturemanager.h>
#include <framework/graphics/atlas.h>
#include <framework/graphics/shadermanager.h>
#include <framework/graphics/fontmanager.h>

#include <framework/util/extras.h>
#include <framework/core/adaptiverenderer.h>
#include <cmath>

MapView::MapView()
{
    m_lockedFirstVisibleFloor = -1;
    m_cachedFirstVisibleFloor = 7;
    m_cachedLastVisibleFloor = 7;
    m_minimumAmbientLight = 0;
    m_optimizedSize = Size(g_map.getAwareRange().horizontal(), g_map.getAwareRange().vertical()) * g_sprites.spriteSize();

    setVisibleDimension(Size(15, 11));
}

MapView::~MapView()
{
    VALIDATE(!g_app.isTerminated());
}

void MapView::drawTileTexts(const Rect& rect, const Rect& srcRect)
{
    Position cameraPosition = getCameraPosition();
    Point drawOffset = srcRect.topLeft();
    float horizontalStretchFactor = rect.width() / (float)srcRect.width();
    float verticalStretchFactor = rect.height() / (float)srcRect.height();

    auto player = g_game.getLocalPlayer();
    auto floor = player->getPosition().z;
    for (auto& tile : m_cachedVisibleTiles[floor]) {
        Position tilePos = tile->getPosition();
        Point p = transformPositionTo2D(tilePos, cameraPosition) - drawOffset;
        p.x *= horizontalStretchFactor;
        p.y *= verticalStretchFactor;
        p += rect.topLeft();
        p.y += 5;

        tile->drawTexts(p);
    }
}

void MapView::drawTileWidget(const Rect& rect, const Rect& srcRect)
{
    Position cameraPosition = getCameraPosition();
    Point drawOffset = srcRect.topLeft();
    float horizontalStretchFactor = rect.width() / (float)srcRect.width();
    float verticalStretchFactor = rect.height() / (float)srcRect.height();

    auto player = g_game.getLocalPlayer();
    auto floor = player->getPosition().z;
    for (auto& tile : m_cachedVisibleTiles[floor]) {
        Position tilePos = tile->getPosition();
        if (tilePos.z != player->getPosition().z) continue;

        Point p = transformPositionTo2D(tilePos, cameraPosition) - drawOffset;
        p.x *= horizontalStretchFactor;
        p.y *= verticalStretchFactor;
        p += rect.topLeft();

        size_t drawQueueStart = g_drawQueue->size();
        tile->drawWidget(p);
        g_drawQueue->setClip(drawQueueStart, rect);
    }
}

void MapView::drawMapBackground(const Rect& rect, const TilePtr& crosshairTile) {
    Position cameraPosition = getCameraPosition();

    if (m_mustUpdateVisibleTilesCache) {
        updateVisibleTilesCache();
    }

    if (g_game.getFeature(Otc::GameForceLight)) {
        m_drawLight = true;
        m_minimumAmbientLight = 0.05f;
    }

    Rect srcRect = calcFramebufferSource(rect.size());
    g_drawQueue->setFrameBuffer(rect, m_optimizedSize, srcRect);

    if (m_drawLight) {
        Light ambientLight;
        if (cameraPosition.z <= Otc::SEA_FLOOR)
            ambientLight = g_map.getLight();
        if (!m_lightTexture || m_lightTexture->getSize() != m_drawDimension)
            m_lightTexture = std::make_shared<Texture>(m_drawDimension, false, true);
        m_lightView = std::make_unique<LightView>(m_lightTexture, m_drawDimension, rect, srcRect, ambientLight.color,
                                                  std::max<int>(m_minimumAmbientLight * 255, ambientLight.intensity));
    }

    for (int z = m_cachedLastVisibleFloor; z >= m_cachedFirstFadingFloor; --z) {
        float fading = 1.0;
        if (m_floorFading > 0) {
            fading = 0.;
            if (m_floorFading > 0) {
                fading = stdext::clamp<float>((float)m_fadingFloorTimers[z].elapsed_millis() / (float)m_floorFading, 0.f, 1.f);
                if (z < m_cachedFirstVisibleFloor)
                    fading = 1.0 - fading;
            }
            if (fading == 0) break;
        }

        if (g_game.getFeature(Otc::GameDrawFloorShadow)) {
            if (cameraPosition.z >= Otc::UNDERGROUND_FLOOR && cameraPosition.z == z) {
                g_drawQueue->addFilledRect(srcRect, m_floorShadow);
            }
        }
        size_t floorStart = g_drawQueue->size();
        drawFloor(z, cameraPosition, crosshairTile);

        // Sort THIS floor's submissions by draw-order layer (ground<border<items) so
        // sprites stack correctly within the floor, without interleaving across floors
        // (which would put an upper floor's ground under a lower floor's items). The
        // range is per-floor so the deep-floor-first iteration above and the per-floor
        // opacity range below both stay correct.
        g_drawQueue->sortRangeByOrder(floorStart);

        if (fading < 0.99)
            g_drawQueue->setOpacity(floorStart, fading);
    }

    // Mouse-target crosshair: drawn LAST, after every floor/tile, so it always sits on
    // top of all items, creatures and taller sprites from adjacent tiles/upper floors.
    // (It used to be drawn mid-tile inside drawFloor and got covered by drawTop/creatures.)
    if (m_crosshair && crosshairTile) {
        Point tileDrawPos = transformPositionTo2D(crosshairTile->getPosition(), cameraPosition);
        g_drawQueue->addTexturedRect(Rect(tileDrawPos, tileDrawPos + g_sprites.spriteSize() - 1),
                                     m_crosshair, Rect(0, 0, m_crosshair->getSize()));
    }

    if(!m_shader.empty() && isFollowingCreature()) {
        g_drawQueue->setShader(m_shader);

        Point walkOffset = transformPositionTo2D(getCameraPosition(), m_shaderPosition);
        walkOffset.y = -walkOffset.y;

        g_drawQueue->setWalkOffset(
            PointF(
                (walkOffset.x / static_cast<float>(m_optimizedSize.width())),
                (walkOffset.y / static_cast<float>(m_optimizedSize.height()))
            )
        );
    }
}

void MapView::setShader(const std::string& shader)
{
    m_shader = shader;
    if (!m_shader.empty())
        m_shaderPosition = getCameraPosition();
}

void MapView::drawFloor(short floor, const Position& cameraPosition, const TilePtr& crosshairTile)
{
    if (floor < 0 || floor > Otc::MAX_Z)
        return;

    auto& tiles = m_cachedVisibleTiles[floor];
    size_t lightFloorStart = m_lightView ? m_lightView->size() : 0;

    // light
    if (m_lightView) {
        for (auto& tile : tiles) {
            Point tileDrawPos = transformPositionTo2D(tile->getPosition(), cameraPosition);
            ItemPtr ground = tile->getGround();
            if (ground && ground->isGround() && !ground->isTranslucent()) {
                m_lightView->setFieldBrightness(tileDrawPos, lightFloorStart, 0);
            }
        }
    }

    if (g_game.getFeature(Otc::GameMapDrawGroundFirst)) {
        // ground
        for (auto& tile : tiles) {
            Point tileDrawPos = transformPositionTo2D(tile->getPosition(), cameraPosition);
            tile->drawGround(tileDrawPos, m_lightView.get());
        }
        // bottom, creatures, top
        for (auto& tile : tiles) {
            Point tileDrawPos = transformPositionTo2D(tile->getPosition(), cameraPosition);

            tile->drawBottom(tileDrawPos, m_lightView.get());

            tile->drawCreatures(tileDrawPos, m_lightView.get());
            tile->drawTop(tileDrawPos, m_lightView.get());
        }
    } else {
        // ground, bottom, creatures, top
        for (auto& tile : tiles) {
            Point tileDrawPos = transformPositionTo2D(tile->getPosition(), cameraPosition);

            if (m_lightView) {
                ItemPtr ground = tile->getGround();
                if (ground && ground->isGround() && !ground->isTranslucent()) {
                    m_lightView->setFieldBrightness(tileDrawPos, lightFloorStart, 0);
                }
            }

            tile->drawGround(tileDrawPos, m_lightView.get());

            tile->drawBottom(tileDrawPos, m_lightView.get());

            tile->drawCreatures(tileDrawPos, m_lightView.get());
            tile->drawTop(tileDrawPos, m_lightView.get());
        }
    }

    for (const MissilePtr& missile : g_map.getFloorMissiles(floor)) {
        missile->draw(transformPositionTo2D(missile->getPosition(), cameraPosition), true, m_lightView.get());
    }
}


void MapView::drawMapForeground(const Rect& rect)
{
    // this could happen if the player position is not known yet
    Position cameraPosition = getCameraPosition();
    if (!cameraPosition.isValid())
        return;

    Rect srcRect = calcFramebufferSource(rect.size());
    Point drawOffset = srcRect.topLeft();
    float horizontalStretchFactor = rect.width() / (float)srcRect.width();
    float verticalStretchFactor = rect.height() / (float)srcRect.height();

    // creatures
    std::vector<std::pair<CreaturePtr, Point>> creatures;
    for (const CreaturePtr& creature : g_map.getSpectatorsInRangeEx(cameraPosition, false, m_visibleDimension.width() / 2, m_visibleDimension.width() / 2 + 1, m_visibleDimension.height() / 2, m_visibleDimension.height() / 2 + 1)) {
        if (!creature->canBeSeen())
            continue;

        PointF jumpOffset = creature->getJumpOffset();
        Point creatureOffset = Point(16 * g_sprites.getOffsetFactor() - creature->getDisplacementX(), -creature->getDisplacementY() - 2 * g_sprites.getOffsetFactor());
        Position pos = creature->getPrewalkingPosition();
        Point p = transformPositionTo2D(pos, cameraPosition) - drawOffset;
        p += (creature->getDrawOffset() + creatureOffset) - Point(jumpOffset.x, jumpOffset.y);
        p.x = p.x * horizontalStretchFactor;
        p.y = p.y * verticalStretchFactor;
        p += rect.topLeft();
        creatures.push_back(std::make_pair(creature, p));
    }

    for (auto& c : creatures) {
        int flags = Otc::DrawIcons;
        if (m_drawNames) { flags |= Otc::DrawNames; }
        if ((!c.first->isLocalPlayer() || m_drawPlayerBars) && !m_drawHealthBarsOnTop) {
            if (m_drawHealthBars) { flags |= Otc::DrawBars; }
            if (m_drawManaBar) { flags |= Otc::DrawManaBar; }
        }
        c.first->drawInformation(c.second, g_map.isCovered(c.first->getPrewalkingPosition(), m_cachedFirstVisibleFloor), rect, flags);
    }

    // Player health/mana/utamo-vita arcs ("Show Arcs"): a stable HUD ring anchored
    // to the viewport center (the followed player sits there), so it doesn't jitter
    // with every walk step.
    if (g_map.isShowingArcs())
        drawPlayerArcs(rect);

    // Condition HUD ("Show in HUD"): a vertical bar anchored to the left of the life arc
    // (same viewport-center anchor as the arc), so the two track together.
    if (g_map.isDrawingHUDStatus())
        drawPlayerHudConditions(rect);

    if (m_lightView) {
        g_drawQueue->add(m_lightView.release());
    }

    // texts
    int limit = g_adaptiveRenderer.textsLimit();
    for (int i = 0; i < 2; ++i) {
        for (const StaticTextPtr& staticText : g_map.getStaticTexts()) {
            Position pos = staticText->getPosition();

            if (pos.z != cameraPosition.z && staticText->getMessageMode() == Otc::MessageNone)
                continue;
            if ((staticText->getMessageMode() != Otc::MessageSay && staticText->getMessageMode() != Otc::MessageYell)) {
                if (i == 0)
                    continue;
            } else if (i == 1)
                continue;

            Point p = transformPositionTo2D(pos, cameraPosition) - drawOffset + Point(8, 0) * g_sprites.getOffsetFactor();
            p.x *= horizontalStretchFactor;
            p.y *= verticalStretchFactor;
            p += rect.topLeft();
            staticText->drawText(p, rect);
            if (--limit == 0)
                break;
        }
    }

    limit = g_adaptiveRenderer.textsLimit();
    for (const AnimatedTextPtr& animatedText : g_map.getAnimatedTexts()) {
        Position pos = animatedText->getPosition();

        if (pos.z != cameraPosition.z)
            continue;

        Point p = transformPositionTo2D(pos, cameraPosition) - drawOffset + Point(16, 8) * g_sprites.getOffsetFactor();
        p.x *= horizontalStretchFactor;
        p.y *= verticalStretchFactor;
        p += rect.topLeft();
        animatedText->drawText(p, rect);
        if (--limit == 0)
            break;
    }

    // cavebot waypoint overlay: tile-anchored markers (fill + border + "N. Type" label)
    // drawn here so they sit ON TOP of the map tiles/borders but UNDER the UI windows,
    // and follow the smooth map scroll. Fed from Lua via g_map.addCavebotMark.
    // Threading: this draw and the cavebot Lua that fills m_cavebotMarks both run on the
    // dispatcher/worker thread (render() and poll() in the same producer cycle), so the
    // vector is never touched concurrently -- no lock needed (same as m_staticTexts).
    const auto& cbMarks = g_map.getCavebotMarks();
    if (!cbMarks.empty()) {
        static auto cbFont = g_fonts.getFont("verdana-11px-rounded");
        if (!cbFont) cbFont = g_fonts.getFont("verdana-11px-rounded"); // retry if not loaded yet
        const int ss = g_sprites.spriteSize();
        const int tw = std::max<int>(1, (int)(ss * horizontalStretchFactor));
        const int th = std::max<int>(1, (int)(ss * verticalStretchFactor));
        int drawn = 0;
        for (const auto& mark : cbMarks) {
            if (mark.pos.z != cameraPosition.z)
                continue;
            Point mp = transformPositionTo2D(mark.pos, cameraPosition) - drawOffset;
            mp.x *= horizontalStretchFactor;
            mp.y *= verticalStretchFactor;
            mp += rect.topLeft();
            // Reach square: radius tiles of half-extent around the waypoint tile (0 = 1x1,
            // 1 = 3x3, 2 = 5x5). Centered on the waypoint tile; the label stays on it.
            const int r = std::max<int>(0, mark.radius);
            const int side = 2 * r + 1;
            Rect tileRect(mp.x - r * tw, mp.y - r * th, side * tw, side * th);
            g_drawQueue->addFilledRect(tileRect, mark.color.opacity(0.30f));
            g_drawQueue->addBoundingRect(tileRect, 2, mark.color);
            if (cbFont && !mark.text.empty())
                g_drawQueue->addText(cbFont, mark.text, Rect(mp.x - tw, mp.y - 13, tw * 3, 13),
                                     Fw::AlignBottomCenter, mark.color, true);
            if (++drawn >= 96) break; // safety cap; the Lua side already bounds to near-screen
        }
    }

    // tile texts
    drawTileTexts(rect, srcRect);

    // bars on top
    if (m_drawHealthBarsOnTop) {
        for (auto& c : creatures) {
            int flags = 0;
            if ((!c.first->isLocalPlayer() || m_drawPlayerBars)) {
                if (m_drawHealthBars) { flags |= Otc::DrawBars; }
                if (m_drawManaBar) { flags |= Otc::DrawManaBar; }
            }
            c.first->drawInformation(c.second, g_map.isCovered(c.first->getPrewalkingPosition(), m_cachedFirstVisibleFloor), rect, flags);
        }
    }
	
	drawTileWidget(rect, srcRect);
}

// Draws the colored fill of one player-arc half (sprite-clip technique, like
// OTClientV8's health-circle): the white "_full" sprite is tinted by `color` and
// clipped from the top so it fills bottom->top in proportion to `ratio`.
static void drawArcFill(const Rect& dest, const TexturePtr& fill, double ratio,
                        const Color& color, float opacity)
{
    if (!fill || ratio <= 0.0)
        return;

    const Size fs = fill->getSize();
    const int h = fs.height();
    const int cut = (int)((1.0 - ratio) * h);
    if (cut >= h)
        return;

    // dest may be scaled down (e.g. the nested inner lane), so scale the dest top
    // offset by dest.height()/nativeH to keep the clipped fill registered with it.
    const float sy = dest.height() / (float)h;
    Rect src(0, cut, fs.width(), h - cut);
    Rect d(dest.x(), dest.y() + (int)(cut * sy), dest.width(), dest.height() - (int)(cut * sy));
    g_drawQueue->addTexturedRect(d, fill, src, color.opacity(opacity));
}

// Tibia-style health palette (green when healthy -> red when low).
static Color arcHealthColor(double health)
{
    const int p = (int)(health * 100);
    if (p > 92) return Color(0x00, 0xBC, 0x00);
    if (p > 60) return Color(0x50, 0xA1, 0x50);
    if (p > 30) return Color(0xA1, 0xA1, 0x00);
    if (p > 8)  return Color(0xBF, 0x0A, 0x0A);
    if (p > 3)  return Color(0x91, 0x0F, 0x0F);
    return Color(0x85, 0x0C, 0x0C);
}

// Filled rounded rectangle composed from primitives (the draw queue has no native
// rounded-rect): a cross of filled rects + four quarter-circle corner triangle-fans.
static void drawRoundedRect(const Rect& r, int radius, const Color& color)
{
    const int x = r.x(), y = r.y(), w = r.width(), h = r.height();
    radius = std::max<int>(0, std::min<int>(radius, std::min<int>(w, h) / 2));
    if (radius <= 0) {
        g_drawQueue->addFilledRect(r, color);
        return;
    }

    g_drawQueue->addFilledRect(Rect(x, y + radius, w, h - 2 * radius), color);                   // middle band
    g_drawQueue->addFilledRect(Rect(x + radius, y, w - 2 * radius, radius), color);              // top edge
    g_drawQueue->addFilledRect(Rect(x + radius, y + h - radius, w - 2 * radius, radius), color); // bottom edge

    const float pi = 3.14159265358979f;
    const int seg = 6;
    auto corner = [&](int cx, int cy, float a0, float a1) {
        for (int i = 0; i < seg; ++i) {
            const float t0 = a0 + (a1 - a0) * i / seg;
            const float t1 = a0 + (a1 - a0) * (i + 1) / seg;
            Point p0(cx + (int)(std::cos(t0) * radius), cy + (int)(std::sin(t0) * radius));
            Point p1(cx + (int)(std::cos(t1) * radius), cy + (int)(std::sin(t1) * radius));
            g_drawQueue->addFilledTriangle(Point(cx, cy), p0, p1, color);
        }
    };
    corner(x + radius,     y + radius,     pi,        pi * 1.5f);  // top-left
    corner(x + w - radius, y + radius,     pi * 1.5f, pi * 2.0f);  // top-right
    corner(x + w - radius, y + h - radius, 0.0f,      pi * 0.5f);  // bottom-right
    corner(x + radius,     y + h - radius, pi * 0.5f, pi);         // bottom-left
}

// On-screen rect of the health ("left") arc for the current style/distance, anchored to
// the viewport center (the followed player sits there). Shared by drawPlayerArcs and the
// condition HUD bar, which sits just to the LEFT of this arc and must track it when the
// arc distance/style changes. Returns false if the arc texture is unavailable.
bool MapView::getHealthArcRect(const Rect& rect, Rect& out)
{
    std::string style = "default";
    switch (g_map.getArcStyle()) {
        case 0: style = "small"; break;
        case 2: style = "large"; break;
        default: style = "default"; break;
    }
    TexturePtr leftFull = g_textures.getTexture("/images/arcs/" + style + "-left_full");
    if (!leftFull)
        return false;

    const int hw = leftFull->getSize().width();
    const int hh = leftFull->getSize().height();

    // EgzoT barDistance: ~panelHeight/2 * 0.2, floored at 90; the "distance" slider
    // (0..1) then widens the central gap on each side.
    int barDistance = 90;
    const int computed = (int)(rect.height() / 2.0f * 0.2f);
    if (computed > barDistance)
        barDistance = computed;
    const int half = barDistance + (int)(g_map.getArcDistance() * hh);

    const Point ctr = rect.center();
    out = Rect(ctr.x - half - hw, ctr.y - hh / 2, hw, hh); // health "(" lane
    return true;
}

void MapView::drawPlayerArcs(const Rect& rect)
{
    LocalPlayerPtr player = g_game.getLocalPlayer();
    if (!player)
        return;

    double maxHealth = player->getMaxHealth();
    double health = maxHealth > 0 ? std::min<double>(1.0, player->getHealth() / maxHealth) : 1.0;
    double maxMana = player->getMaxMana();
    double mana = maxMana > 0 ? std::min<double>(1.0, player->getMana() / maxMana) : 1.0;
    double maxShield = player->getMaxManaShield();
    double shield = maxShield > 0 ? std::min<double>(1.0, player->getManaShield() / maxShield) : 0.0;

    // Arc sprite set by size (matches the "sizeBox" Small/Default/Large option).
    std::string style = "default";
    switch (g_map.getArcStyle()) {
        case 0: style = "small"; break;
        case 2: style = "large"; break;
        default: style = "default"; break;
    }
    const std::string base = "/images/arcs/" + style + "-";
    TexturePtr leftEmpty  = g_textures.getTexture(base + "left_empty");
    TexturePtr leftFull   = g_textures.getTexture(base + "left_full");
    TexturePtr rightBg    = g_textures.getTexture(base + "bg-full");       // grey double-band track
    TexturePtr manaBand   = g_textures.getTexture(base + "maximal_white"); // outer band = mana
    TexturePtr shieldBand = g_textures.getTexture(base + "minimal_white"); // inner band = utamo vita
    if (!leftEmpty || !leftFull || !rightBg || !manaBand || !shieldBand)
        return;

    const float opacity = std::min<float>(1.0f, std::max<float>(0.0f, g_map.getArcOpacity()));

    // Geometry (anchored to the viewport center) shared with the condition HUD bar.
    Rect leftDest;
    if (!getHealthArcRect(rect, leftDest))
        return;
    const int hw = leftDest.width();
    const int hh = leftDest.height();
    const Point ctr = rect.center();
    Rect rightDest(2 * ctr.x - leftDest.x() - hw, leftDest.y(), hw, hh); // mana ")" mirrored about center

    const Color hpColor = arcHealthColor(health);
    const Color manaColor(0x00, 0x36, 0x78);   // topbar mana blue
    const Color shieldColor(0x8f, 0x00, 0xb7); // topbar utamo-vita purple

    // HEALTH: left single lane (grey "_empty" track, then tinted clipped fill).
    g_drawQueue->addTexturedRect(leftDest, leftEmpty, Rect(0, 0, leftEmpty->getSize()), Color::white.opacity(opacity));
    drawArcFill(leftDest, leftFull, health, hpColor, opacity);

    // MANA + UTAMO VITA: right double-band lane, DIVIDED. The grey double-band track
    // (bg-full) is always shown; the OUTER band = MANA (blue), the INNER band = UTAMO
    // VITA (purple). The utamo band is always present -- it just shows the empty grey
    // track when the player has no magic shield active.
    g_drawQueue->addTexturedRect(rightDest, rightBg, Rect(0, 0, rightBg->getSize()), Color::white.opacity(opacity));
    drawArcFill(rightDest, manaBand, mana, manaColor, opacity);
    drawArcFill(rightDest, shieldBand, shield, shieldColor, opacity);
}

void MapView::drawPlayerHudConditions(const Rect& rect)
{
    LocalPlayerPtr player = g_game.getLocalPlayer();
    if (!player)
        return;

    const std::set<std::string>& active = player->getHUDConditions();
    if (active.empty())
        return;

    const std::map<std::string, std::string>& configs = g_map.getHudConfigs();
    if (configs.empty())
        return;

    // Collect the icons of the active "Show in HUD" conditions.
    std::vector<TexturePtr> icons;
    for (const std::string& id : active) {
        auto it = configs.find(id);
        if (it == configs.end())
            continue;
        // Skip blank paths: g_textures.getTexture("") fails AND is never cached,
        // so it would log "Unable to load texture ''" every single frame.
        if (it->second.empty())
            continue;
        TexturePtr tex = g_textures.getTexture(it->second);
        if (tex)
            icons.push_back(tex);
    }
    if (icons.empty())
        return;

    // Native base size (NOT spriteSize(), which DOUBLES in HD mode): this is a
    // screen-space UI column, not world geometry, so it must not scale with the
    // HD framebuffer or the icons bloat to 2x.
    int sprite = g_sprites.getBaseSpriteSize();
    int iconSize = std::max<int>(14, (int)(sprite * 0.5f));
    int gap = std::max<int>(1, iconSize / 8);
    int pad = 6;
    int n = (int)icons.size();

    // Cap to what fits the viewport height so the column never overflows off-screen
    // (the lower icons would otherwise be clipped with no indication).
    int maxIcons = std::max<int>(1, (rect.height() - 2 * pad) / (iconSize + gap));
    if (n > maxIcons) {
        icons.resize(maxIcons);
        n = maxIcons;
    }
    int totalH = n * iconSize + (n - 1) * gap;

    // VERTICAL column placed just to the LEFT of the health arc, vertically centered on
    // it, so it tracks the arc when its distance/style changes (instead of piling on the
    // character). Falls back to the left of the viewport center if the arc is unavailable.
    int rightEdge, vcenter;
    Rect arcRect;
    if (getHealthArcRect(rect, arcRect)) {
        rightEdge = arcRect.x();          // left edge of the health "(" arc
        vcenter = arcRect.center().y;
    } else {
        const Point ctr = rect.center();
        rightEdge = ctr.x - 100;
        vcenter = ctr.y;
    }

    const int margin = 8; // gap between the condition bar and the arc
    int x = rightEdge - margin - iconSize;
    int y0 = vcenter - totalH / 2;

    // Keep the column on-screen on the left (tiny viewports / large arc style).
    if (x - pad < rect.left())
        x = rect.left() + pad;

    // Keep the column inside the viewport vertically.
    if (y0 - pad < rect.top())
        y0 = rect.top() + pad;
    if (y0 + totalH + pad > rect.bottom())
        y0 = std::max<int>(rect.top() + pad, rect.bottom() - pad - totalH);

    Rect bg(x - pad, y0 - pad, iconSize + 2 * pad, totalH + 2 * pad);
    drawRoundedRect(bg, 6, Color(0x20, 0x20, 0x20).opacity(0.78f));

    int y = y0;
    for (int i = 0; i < n; ++i) {
        Rect dest(x, y, iconSize, iconSize);
        g_drawQueue->addTexturedRect(dest, icons[i], Rect(0, 0, icons[i]->getSize()));
        y += iconSize + gap;
    }
}


void MapView::updateVisibleTilesCache()
{
    int prevFirstVisibleFloor = m_cachedFirstVisibleFloor;
    m_cachedFirstVisibleFloor = calcFirstVisibleFloor(false);
    m_cachedFirstFadingFloor = calcFirstVisibleFloor(true);
    m_cachedLastVisibleFloor = calcLastVisibleFloor();

    VALIDATE(m_cachedFirstVisibleFloor >= 0 && m_cachedLastVisibleFloor >= 0 &&
            m_cachedFirstVisibleFloor <= Otc::MAX_Z && m_cachedLastVisibleFloor <= Otc::MAX_Z);

    if(m_cachedLastVisibleFloor < m_cachedFirstVisibleFloor)
        m_cachedLastVisibleFloor = m_cachedFirstVisibleFloor;

    m_mustUpdateVisibleTilesCache = false;

    // there is no tile to render on invalid positions
    Position cameraPosition = getCameraPosition();
    if (!cameraPosition.isValid()) {
        return;
    }

    // fading
    if (!m_lastCameraPosition.isValid() || m_lastCameraPosition.z != cameraPosition.z || m_lastCameraPosition.distance(cameraPosition) >= 3) { 
        for (int iz = m_cachedLastVisibleFloor; iz >= m_cachedFirstFadingFloor; --iz) {
            m_fadingFloorTimers[iz].restart(m_floorFading * 1000);
        }
    } else if (prevFirstVisibleFloor < m_cachedFirstVisibleFloor) { // showing new floor
        for (int iz = prevFirstVisibleFloor; iz < m_cachedFirstVisibleFloor; ++iz) {
            int shift = std::max<int>(0, m_floorFading - m_fadingFloorTimers[iz].elapsed_millis());
            m_fadingFloorTimers[iz].restart(shift * 1000);
        }
    } else if (prevFirstVisibleFloor > m_cachedFirstVisibleFloor) { // hiding floor
        for (int iz = m_cachedFirstVisibleFloor; iz < prevFirstVisibleFloor; ++iz) {
            int shift = std::max<int>(0, m_floorFading - m_fadingFloorTimers[iz].elapsed_millis());
            m_fadingFloorTimers[iz].restart(shift * 1000);
        }
    }

    m_lastCameraPosition = cameraPosition;

    const int numDiagonals = m_drawDimension.width() + m_drawDimension.height() - 1;
    for (auto& cachedVisibleTiles : m_cachedVisibleTiles) {
        cachedVisibleTiles.clear();
    }

    // draw from last floor (the lower) to first floor (the higher)
    for(int iz = m_cachedLastVisibleFloor; iz >= (m_floorFading ? m_cachedFirstFadingFloor : m_cachedFirstVisibleFloor); --iz) {
        for (int diagonal = 0; diagonal < numDiagonals; ++diagonal) {
            // loop current diagonal tiles
            int advance = std::max<int>(diagonal - m_drawDimension.height(), 0);
            for (int iy = diagonal - advance, ix = advance; iy >= 0 && ix < m_drawDimension.width(); --iy, ++ix) {
                // position on current floor
                //TODO: check position limits
                Position tilePos = cameraPosition.translated(ix - m_virtualCenterOffset.x, iy - m_virtualCenterOffset.y);
                // adjust tilePos to the wanted floor
                tilePos.coveredUp(cameraPosition.z - iz);
                if (const TilePtr& tile = g_map.getTile(tilePos)) {
                    if (!tile->isDrawable())
                        continue;
                    m_cachedVisibleTiles[tilePos.z].push_back(tile);
                    tile->calculateCorpseCorrection();
                }
            }
        }
    }
}

void MapView::updateGeometry(const Size& visibleDimension, const Size& optimizedSize)
{
    m_multifloor = true;
    m_visibleDimension = visibleDimension;
    m_drawDimension = visibleDimension + Size(3, 3);
    m_virtualCenterOffset = (m_drawDimension / 2 - Size(1, 1)).toPoint();
    m_visibleCenterOffset = m_virtualCenterOffset;
    m_optimizedSize = m_drawDimension * g_sprites.spriteSize();
    requestVisibleTilesCacheUpdate();
}

void MapView::onTileUpdate(const Position& pos)
{
    requestVisibleTilesCacheUpdate();
}

void MapView::onMapCenterChange(const Position& pos)
{
    requestVisibleTilesCacheUpdate();
}

void MapView::lockFirstVisibleFloor(int firstVisibleFloor)
{
    m_lockedFirstVisibleFloor = firstVisibleFloor;
    requestVisibleTilesCacheUpdate();
}

void MapView::unlockFirstVisibleFloor()
{
    m_lockedFirstVisibleFloor = -1;
    requestVisibleTilesCacheUpdate();
}

void MapView::setVisibleDimension(const Size& visibleDimension)
{
    //if(visibleDimension == m_visibleDimension)
    //    return;

    if(visibleDimension.width() % 2 != 1 || visibleDimension.height() % 2 != 1) {
        g_logger.traceError("visible dimension must be odd");
        return;
    }

    if(visibleDimension < Size(3,3)) {
        g_logger.traceError("reach max zoom in");
        return;
    }

    updateGeometry(visibleDimension, m_optimizedSize);
}

void MapView::optimizeForSize(const Size& visibleSize)
{
    updateGeometry(m_visibleDimension, visibleSize);
}

void MapView::followCreature(const CreaturePtr& creature)
{
    m_follow = true;
    m_followingCreature = creature;
    requestVisibleTilesCacheUpdate();
}

void MapView::setCameraPosition(const Position& pos)
{
    m_follow = false;
    m_customCameraPosition = pos;
    requestVisibleTilesCacheUpdate();
}

Position MapView::getPosition(const Point& point, const Size& mapSize)
{
    Position cameraPosition = getCameraPosition();

    // if we have no camera, its impossible to get the tile
    if(!cameraPosition.isValid())
        return Position();

    Rect srcRect = calcFramebufferSource(mapSize);
    float sh = srcRect.width() / (float)mapSize.width();
    float sv = srcRect.height() / (float)mapSize.height();

    Point framebufferPos = Point(point.x * sh, point.y * sv);
    Point realPos = (framebufferPos + srcRect.topLeft());
    Point centerOffset = realPos / g_sprites.spriteSize();

    Point tilePos2D = getVisibleCenterOffset() - m_drawDimension.toPoint() + centerOffset + Point(2,2);
    if(tilePos2D.x + cameraPosition.x < 0 && tilePos2D.y + cameraPosition.y < 0)
        return Position();

    Position position = Position(tilePos2D.x, tilePos2D.y, 0) + cameraPosition;

    if(!position.isValid())
        return Position();

    return position;
}

Point MapView::getPositionOffset(const Point& point, const Size& mapSize)
{
    Position cameraPosition = getCameraPosition();

    // if we have no camera, its impossible to get the tile
    if (!cameraPosition.isValid())
        return Point(0, 0);

    Rect srcRect = calcFramebufferSource(mapSize);
    float sh = srcRect.width() / (float)mapSize.width();
    float sv = srcRect.height() / (float)mapSize.height();

    Point framebufferPos = Point(point.x * sh, point.y * sv);
    Point realPos = (framebufferPos + srcRect.topLeft());
    return Point(realPos.x % g_sprites.spriteSize(), realPos.y % g_sprites.spriteSize());
}

void MapView::move(int x, int y)
{
    m_moveOffset.x += x;
    m_moveOffset.y += y;

    int32_t tmp = m_moveOffset.x / g_sprites.spriteSize();
    bool requestTilesUpdate = false;
    if(tmp != 0) {
        m_customCameraPosition.x += tmp;
        m_moveOffset.x %= g_sprites.spriteSize();
        requestTilesUpdate = true;
    }

    tmp = m_moveOffset.y / g_sprites.spriteSize();
    if(tmp != 0) {
        m_customCameraPosition.y += tmp;
        m_moveOffset.y %= g_sprites.spriteSize();
        requestTilesUpdate = true;
    }

    if(requestTilesUpdate)
        requestVisibleTilesCacheUpdate();
}

Rect MapView::calcFramebufferSource(const Size& destSize, bool inNextFrame)
{
    Point drawOffset = ((m_drawDimension - m_visibleDimension - Size(1,1)).toPoint()/2) * g_sprites.spriteSize();
    if(isFollowingCreature())
        drawOffset += m_followingCreature->getWalkOffset(inNextFrame);

    Size srcSize = destSize;
    Size srcVisible = m_visibleDimension * g_sprites.spriteSize();
    srcSize.scale(srcVisible, Fw::KeepAspectRatio);
    drawOffset.x += (srcVisible.width() - srcSize.width()) / 2;
    drawOffset.y += (srcVisible.height() - srcSize.height()) / 2;

    return Rect(drawOffset, srcSize);
}

int MapView::calcFirstVisibleFloor(bool forFading)
{
    int z = 7;
    // return forced first visible floor
    if(m_lockedFirstVisibleFloor != -1) {
        z = m_lockedFirstVisibleFloor;
    } else {
        Position cameraPosition = getCameraPosition();

        // this could happens if the player is not known yet
        if(cameraPosition.isValid()) {
            // avoid rendering multifloors in far views
            if(!m_multifloor) {
                z = cameraPosition.z;
            } else {
                // if nothing is limiting the view, the first visible floor is 0
                int firstFloor = 0;

                // limits to underground floors while under sea level
                if(cameraPosition.z > Otc::SEA_FLOOR)
                    firstFloor = std::max<int>(cameraPosition.z - Otc::AWARE_UNDEGROUND_FLOOR_RANGE, (int)Otc::UNDERGROUND_FLOOR);

                // loop in 3x3 tiles around the camera
                for(int ix = -1; ix <= 1 && firstFloor < cameraPosition.z && !forFading; ++ix) {
                    for(int iy = -1; iy <= 1 && firstFloor < cameraPosition.z; ++iy) {
                        Position pos = cameraPosition.translated(ix, iy);

                        // process tiles that we can look through, e.g. windows, doors
                        if((ix == 0 && iy == 0) || ((std::abs(ix) != std::abs(iy)) && g_map.isLookPossible(pos))) {
                            Position upperPos = pos;
                            Position coveredPos = pos;

                            while(coveredPos.coveredUp() && upperPos.up() && upperPos.z >= firstFloor) {
                                // check tiles physically above
                                TilePtr tile = g_map.getTile(upperPos);
                                if(tile && tile->limitsFloorsView(!g_map.isLookPossible(pos))) {
                                    firstFloor = upperPos.z + 1;
                                    break;
                                }

                                // check tiles geometrically above
                                tile = g_map.getTile(coveredPos);
                                if(tile && tile->limitsFloorsView(g_map.isLookPossible(pos))) {
                                    firstFloor = coveredPos.z + 1;
                                    break;
                                }
                            }
                        }
                    }
                }
                z = firstFloor;
            }
        }
    }

    // just ensure the that the floor is in the valid range
    z = stdext::clamp<int>(z, 0, (int)Otc::MAX_Z);
    return z;
}

int MapView::calcLastVisibleFloor()
{
    if(!m_multifloor)
        return calcFirstVisibleFloor();

    int z = 7;

    Position cameraPosition = getCameraPosition();
    // this could happens if the player is not known yet
    if(cameraPosition.isValid()) {
        // view only underground floors when below sea level
        if(cameraPosition.z > Otc::SEA_FLOOR)
            z = cameraPosition.z + Otc::AWARE_UNDEGROUND_FLOOR_RANGE;
        else
            z = Otc::SEA_FLOOR;
    }

    if(m_lockedFirstVisibleFloor != -1)
        z = std::max<int>(m_lockedFirstVisibleFloor, z);

    // just ensure the that the floor is in the valid range
    z = stdext::clamp<int>(z, 0, (int)Otc::MAX_Z);
    return z;
}

Point MapView::transformPositionTo2D(const Position& position, const Position& relativePosition) {
    return Point((m_virtualCenterOffset.x + (position.x - relativePosition.x) - (relativePosition.z - position.z)) * g_sprites.spriteSize(),
        (m_virtualCenterOffset.y + (position.y - relativePosition.y) - (relativePosition.z - position.z)) * g_sprites.spriteSize());
}


Position MapView::getCameraPosition()
{
    if (isFollowingCreature()) {
        return m_followingCreature->getPrewalkingPosition();
    }

    return m_customCameraPosition;
}

void MapView::setDrawLights(bool enable)
{
    m_drawLight = enable;
}

void MapView::setCrosshair(const std::string& file)     
{
    if (file == "")
        m_crosshair = nullptr;
    else
        m_crosshair = g_textures.getTexture(file);
}

/* vim: set ts=4 sw=4 et: */
