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

#ifndef MAP_H
#define MAP_H

#include "creature.h"
#include "houses.h"
#include "towns.h"
#include "creatures.h"
#include "animatedtext.h"
#include "statictext.h"
#include "tile.h"

#include <framework/core/clock.h>

#include <unordered_map>
#include <unordered_set>

enum OTBM_ItemAttr
{
    OTBM_ATTR_DESCRIPTION = 1,
    OTBM_ATTR_EXT_FILE = 2,
    OTBM_ATTR_TILE_FLAGS = 3,
    OTBM_ATTR_ACTION_ID = 4,
    OTBM_ATTR_UNIQUE_ID = 5,
    OTBM_ATTR_TEXT = 6,
    OTBM_ATTR_DESC = 7,
    OTBM_ATTR_TELE_DEST = 8,
    OTBM_ATTR_ITEM = 9,
    OTBM_ATTR_DEPOT_ID = 10,
    OTBM_ATTR_SPAWN_FILE = 11,
    OTBM_ATTR_RUNE_CHARGES = 12,
    OTBM_ATTR_HOUSE_FILE = 13,
    OTBM_ATTR_HOUSEDOORID = 14,
    OTBM_ATTR_COUNT = 15,
    OTBM_ATTR_DURATION = 16,
    OTBM_ATTR_DECAYING_STATE = 17,
    OTBM_ATTR_WRITTENDATE = 18,
    OTBM_ATTR_WRITTENBY = 19,
    OTBM_ATTR_SLEEPERGUID = 20,
    OTBM_ATTR_SLEEPSTART = 21,
    OTBM_ATTR_CHARGES = 22,
    OTBM_ATTR_CONTAINER_ITEMS = 23,
    OTBM_ATTR_ATTRIBUTE_MAP = 128,
    /// just random numbers, they're not actually used by the binary reader...
    OTBM_ATTR_WIDTH = 129,
    OTBM_ATTR_HEIGHT = 130
};

enum OTBM_NodeTypes_t
{
    OTBM_ROOTV2 = 1,
    OTBM_MAP_DATA = 2,
    OTBM_ITEM_DEF = 3,
    OTBM_TILE_AREA = 4,
    OTBM_TILE = 5,
    OTBM_ITEM = 6,
    OTBM_TILE_SQUARE = 7,
    OTBM_TILE_REF = 8,
    OTBM_SPAWNS = 9,
    OTBM_SPAWN_AREA = 10,
    OTBM_MONSTER = 11,
    OTBM_TOWNS = 12,
    OTBM_TOWN = 13,
    OTBM_HOUSETILE = 14,
    OTBM_WAYPOINTS = 15,
    OTBM_WAYPOINT = 16
};

enum {
    OTCM_SIGNATURE = 0x4D43544F,
    OTCM_VERSION = 1
};

enum {
    BLOCK_SIZE = 32
};

enum : uint8 {
    Animation_Force,
    Animation_Show
};

class TileBlock {
public:
    TileBlock() { m_tiles.fill(nullptr); }

    const TilePtr& create(const Position& pos) {
        TilePtr& tile = m_tiles[getTileIndex(pos)];
        tile = std::make_shared<Tile>(pos);
        return tile;
    }
    const TilePtr& getOrCreate(const Position& pos) {
        TilePtr& tile = m_tiles[getTileIndex(pos)];
        if(!tile)
            tile = std::make_shared<Tile>(pos);
        return tile;
    }
    const TilePtr& get(const Position& pos) { return m_tiles[getTileIndex(pos)]; }
    void remove(const Position& pos) { m_tiles[getTileIndex(pos)] = nullptr; }

    uint getTileIndex(const Position& pos) { return ((pos.y % BLOCK_SIZE) * BLOCK_SIZE) + (pos.x % BLOCK_SIZE); }

    const std::array<TilePtr, BLOCK_SIZE*BLOCK_SIZE>& getTiles() const { return m_tiles; }

private:
    std::array<TilePtr, BLOCK_SIZE*BLOCK_SIZE> m_tiles;
};

struct AwareRange
{
    int top;
    int right;
    int bottom;
    int left;

    int horizontal() { return left + right + 1; }
    int vertical() { return top + bottom + 1; }
};

struct PathFindResult     
{
    Otc::PathFindResult status = Otc::PathFindResultNoWay;
    std::vector<Otc::Direction> path;
    int complexity = 0;
    Position start;
    Position destination;
};
using PathFindResult_ptr = std::shared_ptr<PathFindResult>;

struct Node {
    float cost;
    float totalCost;
    Position pos;
    Node *prev;
    int distance;
    int unseen;
};

//@bindsingleton g_map
class Map
{
public:
    void init();
    void terminate();

    void addMapView(const MapViewPtr& mapView);
    void removeMapView(const MapViewPtr& mapView);
    void notificateTileUpdate(const Position& pos, bool updateMinimap = false);

    void requestVisibleTilesCacheUpdate();

    bool loadOtcm(const std::string& fileName);
    void saveOtcm(const std::string& fileName);

    void loadOtbm(const std::string& fileName);
    void saveOtbm(const std::string& fileName);

    void saveImage(const std::string& fileName, int minX, int minY, int maxX, int maxY, short z, bool drawLowerFloors);
    uint8 getLowerFloorsShadowPercent() { return lowerFloorsShadowPercent; }
    void setLowerFloorsShadowPercent(uint8 newLowerFloorsShadowPercent) { lowerFloorsShadowPercent = newLowerFloorsShadowPercent; }

    // otbm attributes (description, size, etc.)
    void setHouseFile(const std::string& file) { m_attribs.set(OTBM_ATTR_HOUSE_FILE, file); }
    void setSpawnFile(const std::string& file) { m_attribs.set(OTBM_ATTR_SPAWN_FILE, file); }
    void setDescription(const std::string& desc) { m_attribs.set(OTBM_ATTR_DESCRIPTION, desc); }

    void clearDescriptions() { m_attribs.remove(OTBM_ATTR_DESCRIPTION); }
    void setWidth(uint16 w) { m_attribs.set(OTBM_ATTR_WIDTH, w); }
    void setHeight(uint16 h) { m_attribs.set(OTBM_ATTR_HEIGHT, h); }

    std::string getHouseFile() { return m_attribs.get<std::string>(OTBM_ATTR_HOUSE_FILE); }
    std::string getSpawnFile() { return m_attribs.get<std::string>(OTBM_ATTR_SPAWN_FILE); }
    Size getSize() { return Size(m_attribs.get<uint16>(OTBM_ATTR_WIDTH), m_attribs.get<uint16>(OTBM_ATTR_HEIGHT)); }
    std::vector<std::string> getDescriptions() { return stdext::split(m_attribs.get<std::string>(OTBM_ATTR_DESCRIPTION), "\n"); }

    void clean();
    void cleanDynamicThings();
    void cleanTexts();

    // thing related
    void addThing(const ThingPtr& thing, const Position& pos, int stackPos = -1);
    void setTileSpeed(const Position & pos, uint16_t speed, uint8_t blocking);
    ThingPtr getThing(const Position& pos, int stackPos);
    bool removeThing(const ThingPtr& thing);
    bool removeThingByPos(const Position& pos, int stackPos);
    void colorizeThing(const ThingPtr& thing, const Color& color);
    void removeThingColor(const ThingPtr& thing);

    StaticTextPtr getStaticText(const Position& pos);

    // tile related
    const TilePtr& createTile(const Position& pos);
    template <typename... Items>
    const TilePtr& createTileEx(const Position& pos, const Items&... items);
    const TilePtr& getOrCreateTile(const Position& pos);
    const TilePtr& getTile(const Position& pos);
    const TileList getTiles(int floor = -1);
    void cleanTile(const Position& pos);

    // tile zone related
    void setShowZone(tileflags_t zone, bool show);
    void setShowZones(bool show);
    void setZoneColor(tileflags_t flag, const Color& color);
    void setZoneOpacity(float opacity) { m_zoneOpacity = opacity; }

    float getZoneOpacity() { return m_zoneOpacity; }

    // Global opacity applied when drawing magic effects / missiles (0.0 - 1.0).
    // Driven by the "Opacity Effects" / "Opacity Missiles" sliders in the client
    // settings (see client_settings dataset.lua -> g_client.setEffectAlpha/setMissileAlpha).
    void setEffectAlpha(float alpha) { m_effectAlpha = std::min<float>(1.0f, std::max<float>(0.0f, alpha)); }
    float getEffectAlpha() { return m_effectAlpha; }
    void setMissileAlpha(float alpha) { m_missileAlpha = std::min<float>(1.0f, std::max<float>(0.0f, alpha)); }
    float getMissileAlpha() { return m_missileAlpha; }
    // Driven by the "Opacity Damage Text" slider -- dims every floating combat number
    // (damage/heal/exp animated texts). See dataset.lua -> g_client.setAnimatedTextAlpha.
    void setAnimatedTextAlpha(float alpha) { m_animatedTextAlpha = std::min<float>(1.0f, std::max<float>(0.0f, alpha)); }
    float getAnimatedTextAlpha() { return m_animatedTextAlpha; }

    // When disabled (default), a new effect of the same type replaces an existing
    // one on a tile instead of piling up. Driven by the "Stack Effects" client
    // setting (client_settings dataset.lua -> g_map.enableStackEffects).
    void enableStackEffects(bool enable) { m_stackEffects = enable; }
    bool isStackEffectsEnabled() { return m_stackEffects; }

    // "Ignore opacity on Special Effects": when enabled, effects whose id is in the
    // special-effects set (Critical/Fatal/Ruse/Momentum/Transcendence) are drawn at
    // full opacity, ignoring the Opacity Effects slider. The id set is supplied from
    // Lua (g_map.setSpecialEffectIds) so it can be tuned without recompiling.
    void setIgnoreSpecialEffects(bool enable) { m_ignoreSpecialEffects = enable; }
    bool isIgnoreSpecialEffects() { return m_ignoreSpecialEffects; }
    void setSpecialEffectIds(const std::vector<int>& ids) {
        m_specialEffectIds.clear();
        for (int id : ids) m_specialEffectIds.insert((uint16)id);
    }
    bool isSpecialEffect(uint16 id) { return m_specialEffectIds.find(id) != m_specialEffectIds.end(); }

    // "Only Show Own Effects": when enabled, magic/distance effects whose server-sent
    // source byte is not Otc::SOURCE_EFFECT_OWN are dropped at parse time (see
    // ProtocolGame::parseMagicEffect). Driven by the client_settings dataset.lua option
    // (g_map.setShowOwnEffectsOnly). Lets the player mute other players'/creatures'
    // effect clutter while keeping their own spells and runes visible.
    void setShowOwnEffectsOnly(bool enable) { m_showOwnEffectsOnly = enable; }
    bool isShowOwnEffectsOnly() { return m_showOwnEffectsOnly; }

    // Player health/mana/utamo-vita arcs, driven by the HUD "Show Arcs" controls
    // (dataset.lua -> g_map.setArcStyle/setArcDistance/setArcOpacity). The actual
    // arcs are rendered by MapView::drawPlayerArcs.
    // Arc/HUD draw-state is kept on the Map singleton (not UIMap) so the Lua
    // options drive it via g_map.* — a clean singleton binding that can't be
    // shadowed by the modules/corelib/globals.lua UIWidget fallback stubs.
    void setShowArcs(bool enable) { m_showArcs = enable; }
    bool isShowingArcs() { return m_showArcs; }
    void setHarmonyLeftDraw(bool healthOnLeft) { m_harmonyLeftDraw = healthOnLeft; }
    bool isHarmonyLeftDraw() { return m_harmonyLeftDraw; }
    void setDrawHUDStatus(bool enable) { m_drawHUDStatus = enable; }
    bool isDrawingHUDStatus() { return m_drawHUDStatus; }
    void setArcStyle(int style) { m_arcStyle = style; }
    int getArcStyle() { return m_arcStyle; }
    void setArcDistance(float distance) { m_arcDistance = distance; }
    float getArcDistance() { return m_arcDistance; }
    void setArcOpacity(float opacity) { m_arcOpacity = opacity; }
    float getArcOpacity() { return m_arcOpacity; }

    // Condition HUD overlay config: condition id -> arc image path. Fed from Lua
    // (g_client.addHudConfig -> g_map.addHudConfig) and consumed by MapView to draw
    // the active conditions around the local character ("Show in HUD" option).
    void addHudConfig(const std::string& id, const std::string& path) { m_hudConfigs[id] = path; }
    void updateHudPath(const std::string& id, const std::string& path) { m_hudConfigs[id] = path; }
    void clearHudConfigs() { m_hudConfigs.clear(); }
    const std::map<std::string, std::string>& getHudConfigs() { return m_hudConfigs; }

    Color getZoneColor(tileflags_t flag);
    tileflags_t getZoneFlags() { return (tileflags_t)m_zoneFlags; }
    bool showZones() { return m_zoneFlags != 0; }
    bool showZone(tileflags_t zone) { return (m_zoneFlags & zone) == zone; }

    void setForceShowAnimations(bool force);
    bool isForcingAnimations();
    bool isShowingAnimations();
    void setShowAnimations(bool show);

    std::map<Position, ItemPtr> findItemsById(uint32 clientId, uint32 max);

    // known creature related
    void addCreature(const CreaturePtr& creature);
    CreaturePtr getCreatureById(uint32 id);
    void removeCreatureById(uint32 id);
    std::vector<CreaturePtr> getSightSpectators(const Position& centerPos, bool multiFloor);
    std::vector<CreaturePtr> getSpectators(const Position& centerPos, bool multiFloor);
    std::vector<CreaturePtr> getSpectatorsInRange(const Position& centerPos, bool multiFloor, int xRange, int yRange);
    std::vector<CreaturePtr> getSpectatorsInRangeEx(const Position& centerPos, bool multiFloor, int minXRange, int maxXRange, int minYRange, int maxYRange);
    // Same as getSpectatorsInRangeEx but fills the caller's buffer (cleared first),
    // reusing its capacity to avoid a per-frame result allocation, and appends
    // creatures without a temporary vector per tile. getSpectatorsInRangeEx() delegates
    // here. Distinct name (not an overload) so &Map::getSpectatorsInRangeEx stays
    // unambiguous for the Lua binding.
    void collectSpectatorsInRangeEx(std::vector<CreaturePtr>& out, const Position& centerPos, bool multiFloor, int minXRange, int maxXRange, int minYRange, int maxYRange);
    std::vector<CreaturePtr> getSpectatorsByPattern(const Position& centerPos, const std::string& pattern, Otc::Direction direction);

    void setLight(const Light& light) { m_light = light; }
    void setCentralPosition(const Position& centralPosition);

    bool isLookPossible(const Position& pos);
    bool isCovered(const Position& pos, int firstFloor = 0);
    bool isCompletelyCovered(const Position& pos, int firstFloor = 0);
    bool isAwareOfPosition(const Position& pos, bool extended = false);
    bool isAwareOfPositionForClean(const Position& pos, bool extended = false);

    void setAwareRange(const AwareRange& range);
    void resetAwareRange();
    AwareRange getAwareRange() { return m_awareRange; }
    Size getAwareRangeAsSize() { return Size(m_awareRange.horizontal(), m_awareRange.vertical()); }

    Light getLight() { return m_light; }
    Position getCentralPosition() { return m_centralPosition; }
    int getFirstAwareFloor();
    int getLastAwareFloor();
    const std::vector<MissilePtr>& getFloorMissiles(int z) { return m_floorMissiles[z]; }

    // Const refs: iterated read-only every frame in MapView::drawMapForeground;
    // returning by value copied the whole vector each frame (not bound to Lua).
    const std::vector<AnimatedTextPtr>& getAnimatedTexts() { return m_animatedTexts; }
    const std::vector<StaticTextPtr>& getStaticTexts() { return m_staticTexts; }

    // Cavebot waypoint overlay: tile-anchored markers drawn in MapView::drawMapForeground
    // (on top of the map tiles/borders, under the UI). Fed from Lua by the cavebot HUD.
    // radius = tiles of half-extent for the on-map square (0 = single tile, 1 = 3x3, 2 = 5x5).
    // Mirrors the cavebot reach radius so the HUD shows the actual acceptance area.
    struct CavebotMark { Position pos; Color color; std::string text; int radius; };
    void addCavebotMark(const Position& pos, const Color& color, const std::string& text, int radius = 0) { m_cavebotMarks.push_back({ pos, color, text, radius }); }
    void clearCavebotMarks() { m_cavebotMarks.clear(); }
    const std::vector<CavebotMark>& getCavebotMarks() { return m_cavebotMarks; }

    std::tuple<std::vector<Otc::Direction>, Otc::PathFindResult> findPath(const Position& start, const Position& goal, int maxComplexity, int flags = 0);
    PathFindResult_ptr newFindPath(const Position& start, const Position& goal, std::shared_ptr<std::list<Node*>> visibleNodes);
    void findPathAsync(const Position & start, const Position & goal, std::function<void(PathFindResult_ptr)> callback);

    // tuple = <cost, distance, prevPos>
    std::map<std::string, std::tuple<int, int, int, std::string>> findEveryPath(const Position& start, int maxDistance, const std::map<std::string, std::string>& params);

    int getMinimapColor(const Position& pos);
    bool isPatchable(const Position& pos);
    bool isWalkable(const Position& pos, bool ignoreCreatures);
    bool isSightClear(const Position& fromPos, const Position& toPos);
    bool checkSightLine(const Position& fromPos, const Position& toPos);

private:
    void removeUnawareThings();
    uint getBlockIndex(const Position& pos) { return ((pos.y / BLOCK_SIZE) * (65536 / BLOCK_SIZE)) + (pos.x / BLOCK_SIZE); }

    std::unordered_map<uint, TileBlock> m_tileBlocks[Otc::MAX_Z+1];
    std::unordered_map<uint32, CreaturePtr> m_knownCreatures;
    std::array<std::vector<MissilePtr>, Otc::MAX_Z+1> m_floorMissiles;
    std::vector<AnimatedTextPtr> m_animatedTexts;
    std::vector<StaticTextPtr> m_staticTexts;
    std::vector<CavebotMark> m_cavebotMarks;
    std::vector<MapViewPtr> m_mapViews;
    std::unordered_map<Position, std::string, PositionHasher> m_waypoints;

    uint8 m_animationFlags;
    uint32 m_zoneFlags;
    std::map<uint32, Color> m_zoneColors;
    float m_zoneOpacity;
    float m_effectAlpha = 1.0f;
    float m_missileAlpha = 1.0f;
    float m_animatedTextAlpha = 1.0f;
    bool m_stackEffects = false; // default: effects do NOT stack on a tile
    bool m_ignoreSpecialEffects = false; // "Ignore opacity on Special Effects" toggle
    std::unordered_set<uint16> m_specialEffectIds; // effect ids exempt from opacity
    bool m_showOwnEffectsOnly = false; // "Only Show Own Effects" toggle (default off)
    bool m_showArcs = false;     // "Show Arcs" toggle (default off)
    bool m_harmonyLeftDraw = true; // health arc on the left, mana on the right
    bool m_drawHUDStatus = true; // "Show in HUD" master toggle
    int m_arcStyle = 1;          // 0 = small, 1 = default, 2 = large
    float m_arcDistance = 0.15f; // distanceArc / 100
    float m_arcOpacity = 0.70f;  // opacityArc / 100
    std::map<std::string, std::string> m_hudConfigs; // condition id -> arc image path

    Light m_light;
    Position m_centralPosition;
    Rect m_tilesRect;

    stdext::packed_storage<uint8> m_attribs;
    AwareRange m_awareRange;
    static TilePtr m_nulltile;

    // only for map PNG image generator
    uint8 lowerFloorsShadowPercent = 0;
};

extern Map g_map;

#endif
