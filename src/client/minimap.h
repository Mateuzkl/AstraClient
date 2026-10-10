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


#ifndef MINIMAP_H
#define MINIMAP_H

#include "declarations.h"
#include <framework/graphics/declarations.h>
#include <atomic>
#include <list>
#include <future>
#include <set>

enum {
    MMBLOCK_SIZE = 64,
    OTMM_SIGNATURE = 0x4D4d544F,
    OTMM_VERSION = 1
};

enum MinimapTileFlags {
    MinimapTileWasSeen = 1,
    MinimapTileNotPathable = 2,
    MinimapTileNotWalkable = 4,
    MinimapTileEmpty = 8
};

#pragma pack(push,1) // disable memory alignment
struct MinimapTile
{
    MinimapTile() : flags(0), color(255), speed(10) { }
    uint8 flags;
    uint8 color;
    uint8 speed;
    bool hasFlag(MinimapTileFlags flag) const { return flags & flag; }
    int getSpeed() const { return speed * 10; }
    bool operator==(const MinimapTile& other) const { return color == other.color && flags == other.flags && speed == other.speed; }
    bool operator!=(const MinimapTile& other) const { return !(*this == other); }
};

class MinimapBlock
{
public:
    void clean();
    void update();
    void updateTile(int x, int y, const MinimapTile& tile);
    MinimapTile& getTile(int x, int y) { return m_tiles[getTileIndex(x,y)]; }
    void resetTile(int x, int y) { m_tiles[getTileIndex(x,y)] = MinimapTile(); }
    uint getTileIndex(int x, int y) { return ((y % MMBLOCK_SIZE) * MMBLOCK_SIZE) + (x % MMBLOCK_SIZE); }
    const TexturePtr& getTexture() { return m_texture; }
    std::array<MinimapTile, MMBLOCK_SIZE * MMBLOCK_SIZE>& getTiles() { return m_tiles; }
    void mustUpdate() { m_mustUpdate = true; }
    void justSaw() { m_wasSeen = true; }
    bool wasSeen() { return m_wasSeen; }
private:
    TexturePtr m_texture;
    std::array<MinimapTile, MMBLOCK_SIZE * MMBLOCK_SIZE> m_tiles;
    stdext::boolean<true> m_mustUpdate;
    stdext::boolean<false> m_wasSeen;
};

#pragma pack(pop)

using MinimapBlock_ptr = std::shared_ptr<MinimapBlock>;

class Minimap
{

public:
    void init();
    void terminate();

    void clean();

    void draw(const Rect& screenRect, const Position& mapCenter, float scale, const Color& color);
    void drawSprites(const Rect& screenRect, const Position& mapCenter, float scale, const Color& color, bool liveTerrain = true);
    bool loadSatellitePack(const std::string& directory);
    void clearSatellitePack();
    bool hasSatellitePack();
    bool hasSatelliteTile(const Position& pos);
    bool preloadSatelliteTile(const Position& pos, float scale);
    size_t getSatelliteChunkCount();
    size_t getSatelliteTextureCount();
    size_t getSatelliteDecodeCount();
    int getSatelliteViewLevel(const Size& viewSize, float scale);
    int exportSatelliteBase(const std::string& directory);
    void addSpriteView();
    void removeSpriteView();
    void clearSpriteCache();
    size_t getSpriteCacheTileCount();
    size_t getSpriteCacheItemCount();
    uint64_t getSpriteTileLookupCount();
    unsigned getSpriteViewCount();
    void prepareSpriteView(const Size& viewSize, const Position& mapCenter, float scale);
    Point getTilePoint(const Position& pos, const Rect& screenRect, const Position& mapCenter, float scale);
    Position getTilePosition(const Point& point, const Rect& screenRect, const Position& mapCenter, float scale);
    Rect getTileRect(const Position& pos, const Rect& screenRect, const Position& mapCenter, float scale);

    void updateTile(const Position& pos, const TilePtr& tile);
    const MinimapTile& getTile(const Position& pos);
    std::pair<MinimapBlock_ptr, MinimapTile> threadGetTile(const Position& pos);

    bool loadImage(const std::string& fileName, const Position& topLeft, float colorFactor);
    void saveImage(const std::string& fileName, int minX, int minY, int maxX, int maxY, short z);
    bool loadOtmm(const std::string& fileName);
    bool mergeOtmm(const std::string& fileName);
    void saveOtmm(const std::string& fileName);

private:
    bool loadOtmmImpl(const std::string& fileName, bool preserveUnknown);
    struct SatelliteChunk { std::string file; bool failed = false; };
    struct SatelliteTexture {
        TexturePtr texture;
        std::list<uint64_t>::iterator order;
    };
    struct SatelliteDecode {
        uint64_t key;
        std::shared_future<ImagePtr> image;
        std::shared_ptr<std::atomic<bool>> cancelled;
    };
    static uint64_t satelliteKey(int level, int x, int y, int z) {
        return (uint64_t(level) << 40) | (uint64_t(z) << 32) | (uint64_t(y) << 16) | x;
    }
    int satelliteLevel(float scale); // Requires m_satelliteLock.
    int satelliteViewLevel(const Rect& mapRect, float scale); // Requires m_satelliteLock.
    static constexpr size_t SatelliteTextureLimit = 32;
    static constexpr size_t SatelliteDecodeLimit = 4;
    size_t finishSatelliteDecodes(); // Requires m_satelliteLock; returns active jobs.
    void cancelSatelliteDecodes(); // Requires m_satelliteLock; never drops pending jobs.
    TexturePtr satelliteTexture(uint64_t key); // Requires m_satelliteLock.
    void drawSatellite(const Rect& screenRect, const Position& mapCenter, float scale);
    void clearSatelliteTextures();
    std::unordered_map<uint64_t, SatelliteChunk> m_satelliteChunks;
    std::unordered_map<uint64_t, SatelliteTexture> m_satelliteTextures;
    std::vector<SatelliteDecode> m_satelliteDecodes; // Independent of texture LRU and pack lifetime; at most four.
    std::list<uint64_t> m_satelliteOrder;
    std::set<int> m_satelliteLevels;
    uint32 m_satelliteDatSignature = 0;
    uint32 m_satelliteSprSignature = 0;
    std::mutex m_satelliteLock;
    struct SpriteTile {
        std::vector<ItemPtr> items;
        std::list<uint64_t>::iterator order;
    };
    static uint64_t spriteTileKey(const Position& pos) {
        return (uint64_t(pos.z) << 32) | (uint64_t(pos.y) << 16) | pos.x;
    }
    void updateSpriteTile(const Position& pos, const TilePtr& tile);
    void eraseSpriteTile(uint64_t key); // Requires m_spriteLock.
    void clearSpriteCacheLocked();
    std::unordered_map<uint64_t, SpriteTile> m_spriteTiles;
    std::list<uint64_t> m_spriteOrder;
    size_t m_spriteItemCount = 0;
    uint64_t m_spriteTileLookupCount = 0;
    unsigned m_spriteViews = 0;
    std::atomic<bool> m_spriteCacheEnabled{false};
    std::mutex m_spriteLock;

    Rect calcMapRect(const Rect& screenRect, const Position& mapCenter, float scale);
    bool hasBlock(const Position& pos) { return m_tileBlocks[pos.z].find(getBlockIndex(pos)) != m_tileBlocks[pos.z].end(); }
    MinimapBlock& getBlock(const Position& pos) { 
        std::lock_guard<std::mutex> lock(m_lock);
        auto& ptr = m_tileBlocks[pos.z][getBlockIndex(pos)];
        if (!ptr)
            ptr = std::make_shared<MinimapBlock>();
        return *ptr;
    }
    Point getBlockOffset(const Point& pos) { return Point(pos.x - pos.x % MMBLOCK_SIZE,
                                                          pos.y - pos.y % MMBLOCK_SIZE); }
    Position getIndexPosition(int index, int z) { return Position((index % (65536 / MMBLOCK_SIZE))*MMBLOCK_SIZE,
                                                                  (index / (65536 / MMBLOCK_SIZE))*MMBLOCK_SIZE, z); }
    uint getBlockIndex(const Position& pos) { return ((pos.y / MMBLOCK_SIZE) * (65536 / MMBLOCK_SIZE)) + (pos.x / MMBLOCK_SIZE); }
    std::vector<std::unordered_map<uint, MinimapBlock_ptr>> m_tileBlocks;
    std::mutex m_lock;
};

extern Minimap g_minimap;

#endif
