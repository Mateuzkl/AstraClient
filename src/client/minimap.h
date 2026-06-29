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
#include <thread>
#include <mutex>
#include <condition_variable>
#include <queue>
#include <atomic>
#include <map>
#include <unordered_map>

enum {
    MMBLOCK_SIZE = 64,
    OTMM_SIGNATURE = 0x4D4d544F,
    OTMM_VERSION = 1,
    // HD minimap: a separate per-floor file format that stores the real item ids
    // of each tile so the HD textures (rendered from item sprites) can be rebuilt
    // offline. Independent of the base OTMM format above.
    OTMM_HD_SIGNATURE = 0x4844544F,
    OTMM_HD_VERSION = 1
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
#pragma pack(pop)

class MinimapBlock : public std::enable_shared_from_this<MinimapBlock>
{
    friend class Minimap;
public:
    void clean();
    void update();
    void updateTile(int x, int y, const MinimapTile& tile);
    // HD: the real item ids of each tile, used to composite the HD texture. A small
    // negative/over-range margin (neighbouring blocks) is kept in m_extendedTileItems.
    // All access to these containers is serialised by Minimap::m_lock (the snapshot
    // builder, the async saver and updateTile all hold it).
    void setTileItems(int x, int y, const std::vector<uint16>& items, bool markDirty = true) {
        std::vector<uint16>* target = nullptr;
        if(x >= 0 && x < MMBLOCK_SIZE && y >= 0 && y < MMBLOCK_SIZE) {
            target = &m_tileItems[getTileIndex(x,y)];
        } else {
            uint64_t key = ((uint64_t)(int16_t)x << 32) | (uint64_t)(uint16_t)(int16_t)y;
            target = &m_extendedTileItems[key];
        }

        if(*target == items)
            return;

        *target = items;
        if(markDirty) {
            m_hdNeedsUpdate = true;
            m_needsSave = true;
            ++m_saveRevision;
        }
    }
    const std::vector<uint16>& getTileItems(int x, int y) {
        if(x >= 0 && x < MMBLOCK_SIZE && y >= 0 && y < MMBLOCK_SIZE) {
            return m_tileItems[getTileIndex(x,y)];
        } else {
            uint64_t key = ((uint64_t)(int16_t)x << 32) | (uint64_t)(uint16_t)(int16_t)y;
            static std::vector<uint16> emptyVec;
            auto it = m_extendedTileItems.find(key);
            return (it != m_extendedTileItems.end()) ? it->second : emptyVec;
        }
    }
    MinimapTile& getTile(int x, int y) { return m_tiles[getTileIndex(x,y)]; }
    void resetTile(int x, int y) { m_tiles[getTileIndex(x,y)] = MinimapTile(); }
    uint getTileIndex(int x, int y) { return ((y % MMBLOCK_SIZE) * MMBLOCK_SIZE) + (x % MMBLOCK_SIZE); }
    const TexturePtr& getTexture() { return m_texture; }
    const TexturePtr& getHDTexture() { return m_hdTexture; }
    std::array<MinimapTile, MMBLOCK_SIZE * MMBLOCK_SIZE>& getTiles() { return m_tiles; }
    void mustUpdate() { m_mustUpdate = true; }
    void justSaw() { m_wasSeen = true; }
    bool wasSeen() { return m_wasSeen; }
    void markUsed() { m_lastUsedTime = stdext::millis(); }
    ticks_t getLastUsedTime() const { return m_lastUsedTime; }
    bool needsHDUpdate() const { return m_hdNeedsUpdate; }

    // Render hand-off flags. m_isRendering/m_hasPendingHD are atomic so the draw
    // thread can test them lock-free; m_pendingHDImage itself is only ever touched
    // while Minimap::m_renderMutex is held (worker, processCompletedRenders, the
    // draw-thread cleanup and setHDMode).
    bool isRendering() const { return m_isRendering.load(); }
    void setRendering(bool rendering) { m_isRendering.store(rendering); }
    bool hasPendingHD() const { return m_hasPendingHD.load(); }
    ImagePtr getPendingHDImage() const { return m_pendingHDImage; }
    void setPendingHDImage(ImagePtr img) { m_pendingHDImage = img; m_hasPendingHD.store(img != nullptr); }

private:
    TexturePtr m_texture;
    TexturePtr m_hdTexture;
    std::array<MinimapTile, MMBLOCK_SIZE * MMBLOCK_SIZE> m_tiles;
    std::array<std::vector<uint16>, MMBLOCK_SIZE * MMBLOCK_SIZE> m_tileItems;
    std::map<uint64_t, std::vector<uint16>> m_extendedTileItems;
    size_t m_itemsHash = 0;
    ticks_t m_lastUsedTime = 0;
    ticks_t m_lastRenderTime = 0;
    stdext::boolean<true> m_mustUpdate;
    stdext::boolean<true> m_hdNeedsUpdate;
    stdext::boolean<false> m_wasSeen;
    stdext::boolean<false> m_needsSave;
    uint32 m_saveRevision = 0;

    ImagePtr m_pendingHDImage;
    std::atomic<bool> m_isRendering{false};
    std::atomic<bool> m_hasPendingHD{false};
};

using MinimapBlock_ptr = std::shared_ptr<MinimapBlock>;

// Self-contained unit of work handed to the HD render threads. It carries an
// immutable snapshot of everything a worker needs (the item ids of the block and
// its neighbour margin, plus the hook orientation resolved from the live map on the
// main thread), so the worker never touches g_map, m_tileBlocks or live block data.
struct HDRenderJob
{
    Position blockPos;
    MinimapBlock_ptr block;                  // result delivery target only
    int side = 0;                            // grid width  (MMBLOCK_SIZE + 2*margin)
    int height = 0;                          // grid height (side + elevationMargin)
    bool protobuf = false;                   // g_sprites.isUsingProtobuf() (full-square sprites)
    int spriteSize = 0;                      // g_sprites.spriteSize() (HD-scaled cell size)
    std::vector<std::vector<uint16>> items;  // size side*height, idx = gy*side + gx
    std::vector<uint8_t> hook;               // size side*height: 0 none, 1 south, 2 east
    // Sprite images pre-fetched on the main thread (g_sprites is not thread-safe).
    std::unordered_map<int, ImagePtr> spriteImages;
};

class Minimap
{
    friend class MinimapBlock;

public:
    void init();
    void terminate();

    void clean();

    void draw(const Rect& screenRect, const Position& mapCenter, float scale, const Color& color);
    Point getTilePoint(const Position& pos, const Rect& screenRect, const Position& mapCenter, float scale);
    Position getTilePosition(const Point& point, const Rect& screenRect, const Position& mapCenter, float scale);
    Rect getTileRect(const Position& pos, const Rect& screenRect, const Position& mapCenter, float scale);

    void updateTile(const Position& pos, const TilePtr& tile);
    const MinimapTile& getTile(const Position& pos);
    std::pair<MinimapBlock_ptr, MinimapTile> threadGetTile(const Position& pos);

    // HD minimap mode: render blocks from real item sprites instead of a single
    // colour per tile. Heavy (large textures + background render threads), so it is
    // off by default and toggled from the minimap UI.
    void setHDMode(bool enabled);
    bool isHDMode() { return m_hdMode; }

    bool loadImage(const std::string& fileName, const Position& topLeft, float colorFactor);
    void saveImage(const std::string& fileName, int minX, int minY, int maxX, int maxY, short z);
    bool loadOtmm(const std::string& fileName);
    void saveOtmm(const std::string& fileName);
    bool loadOtmmHD(const std::string& fileName);
    void saveOtmmHD(const std::string& fileName);
    void saveOtmmHDAsync(const std::string& fileName);
    bool isSavingHD() { return m_isSavingHD.load(); }

    void renderThreadFunc();
    void processCompletedRenders();

private:
    // Builds the immutable snapshot for an HD block render on the main thread and
    // enqueues it for the worker pool. Handles the busy/throttle/no-change early-outs.
    void queueBlockHD(const MinimapBlock_ptr& block, const Position& blockPos, bool processLiveTiles);

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
    std::unordered_map<uint, MinimapBlock_ptr> m_tileBlocks[Otc::MAX_Z+1];
    std::mutex m_lock;
    bool m_hdMode = false;

    static constexpr int NUM_RENDER_THREADS = 6;
    std::thread m_renderThreads[NUM_RENDER_THREADS];
    std::mutex m_renderMutex;
    std::condition_variable m_renderCondition;
    std::queue<HDRenderJob> m_renderQueue;
    std::atomic<int> m_renderQueueSize{0};       // mirrors m_renderQueue.size() for lock-free reads
    std::atomic<bool> m_renderThreadRunning{false};
    std::atomic<bool> m_isSavingHD{false};
    std::thread m_saveThread;
};

extern Minimap g_minimap;

#endif
