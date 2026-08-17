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
#include <memory>
#include <vector>

enum {
    MMBLOCK_SIZE = 64,
    OTMM_SIGNATURE = 0x4D4d544F,
    OTMM_VERSION = 1
};

// ---------------------------------------------------------------------------
// HD minimap (optional layer, off by default)
//
// Blocks composited from the real item sprites instead of one colour per tile.
// It is strictly additive: MinimapTile, OTMM_VERSION, loadOtmm/saveOtmm and the
// whole base draw path are untouched, and if anything here fails the standard
// minimap keeps working.
//
// Sizing rationale (see astraclient_hd_minimap_audit.html): the UI draws a tile
// at `scale` screen pixels (zoom -5..+5 => scale 1/32..32). 8 texels per tile is
// 1:1 at scale 8 and oversamples 2x at scale 4, which covers the usable zoom
// range at 512*512*4 = 1 MiB per block.
// ---------------------------------------------------------------------------
enum {
    HD_TEXELS_PER_TILE = 8,
    HD_BLOCK_TEXTURE_SIZE = MMBLOCK_SIZE * HD_TEXELS_PER_TILE,  // 512
    HD_NO_RECORD = 0xFFFF,

    // Below this zoom a tile covers fewer than 2 screen pixels, so an HD texture
    // would just be downsampled back into the flat colour the base minimap already
    // draws. This is also what keeps the full map view cheap.
    HD_MIN_SCALE = 2,

    // Ring of blocks around the viewport that eviction leaves alone, so a step or
    // two of movement does not immediately re-render what just scrolled off.
    // Everything beyond it is evictable, including on the floor being explored.
    HD_PROTECT_MARGIN_BLOCKS = 1,

    // The one and only queue bound in the system.
    HD_MAX_QUEUED_JOBS = 12,

    // Separate HD sidecar format. minimap.otmm itself is never touched.
    OTMM_HD_SIGNATURE = 0x4844544F,
    OTMM_HD_VERSION = 2
};

// Budgets are expressed in bytes, not in block counts, because resources of very
// different sizes share them.
inline constexpr size_t HD_TEXTURE_BUDGET_BYTES = 64ull * 1024 * 1024;
inline constexpr size_t HD_PENDING_IMAGE_BUDGET_BYTES = 8ull * 1024 * 1024;
inline constexpr size_t HD_BLOCK_TEXTURE_BYTES =
    (size_t)HD_BLOCK_TEXTURE_SIZE * HD_BLOCK_TEXTURE_SIZE * 4;   // 1 MiB

// Defensive limits for the HD sidecar parser. Nothing read from a file is
// trusted before being checked against these.
inline constexpr uint32 HD_MAX_COMPRESSED_BYTES = 64u * 1024 * 1024;
inline constexpr uint32 HD_MAX_UNCOMPRESSED_BYTES = 256u * 1024 * 1024;
inline constexpr uint32 HD_MAX_BLOCKS_PER_FLOOR = 65536;
inline constexpr uint16 HD_MAX_TILES_PER_BLOCK = MMBLOCK_SIZE * MMBLOCK_SIZE;
inline constexpr uint16 HD_MAX_ITEMS_PER_TILE = 64;

// One drawable item of a tile. Explicitly typed: the subtype has its own field
// so it can never be mistaken for a client id (the old design pushed fluid
// subtypes into the same uint16 list as item ids).
struct HDMinimapItem
{
    uint16 id = 0;
    uint16 subtype = 0;
    bool operator==(const HDMinimapItem& o) const { return id == o.id && subtype == o.subtype; }
    bool operator!=(const HDMinimapItem& o) const { return !(*this == o); }
};

// A tile that has items, plus its span inside HDBlockData::m_items.
struct HDTileRecord
{
    uint16 tileIndex = 0;
    uint16 count = 0;
    uint32 offset = 0;
};

// Sparse, packed HD payload of one block.
//
// Only tiles that actually carry items exist here: the items of the whole block
// live in one contiguous pool, addressed by a record list, with a flat slot table
// for O(1) lookup. A 64x64 block therefore costs three allocations instead of the
// 4096 independent std::vector the old design embedded in every MinimapBlock.
class HDBlockData
{
public:
    // Replaces the items of a tile. Returns true when the content actually
    // changed, so callers only bump revisions on real changes.
    bool setTileItems(uint16 tileIndex, const HDMinimapItem* items, uint16 count);

    uint32 getContentRevision() const { return m_contentRevision; }
    uint32 getSavedRevision() const { return m_savedRevision; }
    void setSavedRevision(uint32 revision) { m_savedRevision = revision; }
    bool isDirty() const { return m_contentRevision != m_savedRevision; }

    bool isEmpty() const { return m_records.empty(); }
    size_t getTileCount() const { return m_records.size(); }
    const std::vector<HDTileRecord>& getRecords() const { return m_records; }
    const std::vector<HDMinimapItem>& getItemPool() const { return m_items; }

    // Approximate resident cost, used by the HD memory budget.
    size_t getByteSize() const;

    // --- render cache -------------------------------------------------------
    // The texture lives here rather than in MinimapBlock so that a block without
    // HD data carries no HD render state at all.
    const TexturePtr& getTexture() const { return m_texture; }
    void setTexture(const TexturePtr& texture, uint32 revision) {
        m_texture = texture;
        m_renderedRevision = revision;
    }
    void dropTexture() { m_texture = nullptr; m_renderedRevision = 0; }
    bool hasTexture() const { return m_texture != nullptr; }

    // Revision bookkeeping replaces re-hashing the block on every draw.
    uint32 getRenderedRevision() const { return m_renderedRevision; }
    bool needsRender() const { return m_renderedRevision != m_contentRevision; }

    ticks_t getLastUsed() const { return m_lastUsed; }
    void markUsed(ticks_t now) { m_lastUsed = now; }

private:
    void compact();

    TexturePtr m_texture;
    uint32 m_renderedRevision = 0;
    ticks_t m_lastUsed = 0;

    std::vector<HDTileRecord> m_records;   // one entry per non-empty tile
    std::vector<HDMinimapItem> m_items;    // packed item pool
    std::vector<uint16> m_slot;            // 4096 entries: tileIndex -> record index
    uint32 m_contentRevision = 0;
    uint32 m_savedRevision = 0;
    uint32 m_garbageItems = 0;
};

enum MinimapTileFlags {
    MinimapTileWasSeen = 1,
    MinimapTileNotPathable = 2,
    MinimapTileNotWalkable = 4,
    MinimapTileEmpty = 8
};

// A tile inside a render job's grid, pointing at a span of HDRenderJob::items.
struct HDJobTile
{
    int16 gx = 0;      // tile offset from the block origin, may be negative (margin)
    int16 gy = 0;
    uint32 first = 0;
    uint16 count = 0;
};

// Queued unit of work. Deliberately cheap: it holds no sprite images and, above
// all, no MinimapBlock_ptr — a queued render must never keep a region of the
// minimap alive.
struct HDRenderJob
{
    uint blockIndex = 0;
    Position blockPos;
    uint32 generation = 0;
    uint32 revision = 0;
    int priority = 0;                  // block distance to the viewport centre
    std::vector<HDJobTile> tiles;
    std::vector<HDMinimapItem> items;
};

// One resolved sprite blit. Produced on the dispatcher thread (where g_things and
// g_sprites may be touched) and consumed by a worker, which therefore needs no
// singleton at all.
struct HDBlit
{
    ImagePtr image;
    int16 destX = 0;   // texels in the target image
    int16 destY = 0;
    int16 width = 0;
    int16 height = 0;
};

// What a worker actually receives.
struct HDRenderTask
{
    uint blockIndex = 0;
    uint8 z = 0;
    uint32 generation = 0;
    uint32 revision = 0;
    std::vector<HDBlit> blits;
};

// What a worker hands back. A worker ALWAYS posts one of these, even when it
// cancelled early (image is then null), so the in-flight bookkeeping is symmetric
// and can never leak an entry.
struct HDRenderResult
{
    uint blockIndex = 0;
    uint8 z = 0;
    uint32 generation = 0;
    uint32 revision = 0;
    ImagePtr image;
};

// A block currently being rendered by a worker.
struct HDRunningJob
{
    uint blockIndex = 0;
    uint8 z = 0;
    uint32 revision = 0;
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

    // HD layer. Null unless HD mode has actually stored something for this block,
    // so a block without HD data costs exactly one pointer on top of the base one.
    HDBlockData* getHDData() const { return m_hd.get(); }
    HDBlockData& getOrCreateHDData() {
        if(!m_hd)
            m_hd = std::make_unique<HDBlockData>();
        return *m_hd;
    }
    void dropHDData() { m_hd.reset(); }

private:
    TexturePtr m_texture;
    // Kept next to m_texture (and before m_tiles) so it stays pointer-aligned
    // under the #pragma pack(1) this declaration lives in.
    std::unique_ptr<HDBlockData> m_hd;
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
    Point getTilePoint(const Position& pos, const Rect& screenRect, const Position& mapCenter, float scale);
    Position getTilePosition(const Point& point, const Rect& screenRect, const Position& mapCenter, float scale);
    Rect getTileRect(const Position& pos, const Rect& screenRect, const Position& mapCenter, float scale);

    void updateTile(const Position& pos, const TilePtr& tile);
    const MinimapTile& getTile(const Position& pos);
    std::pair<MinimapBlock_ptr, MinimapTile> threadGetTile(const Position& pos);

    bool loadImage(const std::string& fileName, const Position& topLeft, float colorFactor);
    void saveImage(const std::string& fileName, int minX, int minY, int maxX, int maxY, short z);
    bool loadOtmm(const std::string& fileName);
    void saveOtmm(const std::string& fileName);

    // --- HD minimap ---------------------------------------------------------
    // Turning HD off releases every HD allocation and invalidates outstanding
    // async work through the generation counter.
    void setHDMode(bool enabled);
    bool isHDMode() const { return m_hdMode.load(std::memory_order_relaxed); }

    // Every async HD result must belong to the current generation to be applied.
    // Bumped on: HD on/off, clean(), map load, and shutdown.
    uint32 getHDGeneration() const { return m_hdGeneration.load(std::memory_order_acquire); }

    // HD sidecar persistence. Never touches minimap.otmm.
    bool loadOtmmHD(const std::string& fileName);
    void saveOtmmHD(const std::string& fileName);
    bool isSavingHD() const { return m_hdSaving.load(std::memory_order_acquire); }

    // Debug instrumentation. Cheap enough to call from Lua on demand; never logged
    // on its own.
    std::string getHDStats();

private:
    // Records the drawable items of one tile. Only ever called with HD mode on.
    void collectHDTile(const Position& pos, const TilePtr& tile);
    // Drops all HD payloads and bumps the generation. Caller must hold m_lock.
    void invalidateHDLocked();

    // --- HD render pipeline (dispatcher thread unless noted) ----------------
    // Draws the HD layer for the visible area and keeps the cache fed. Falls back
    // to the caller's base path by returning false when HD cannot be used.
    bool drawHD(const Rect& screenRect, const Position& mapCenter, float scale,
                const Point& blockOff, const Point& start);
    // Builds the sparse snapshot of a block and inserts it into the bounded queue,
    // replacing any older entry for the same block.
    void queueHDBlock(MinimapBlock& block, const Position& blockPos, uint blockIndex, int priority);
    // Pops the best queued jobs and starts them on the async dispatcher.
    void dispatchHDJobs();
    // Turns a snapshot into blits. Reads g_things/g_sprites, so dispatcher only.
    bool buildHDTask(const HDRenderJob& job, HDRenderTask& task);
    // Uploads finished images into textures.
    void collectHDResults();
    // Frees textures until the budget is respected. Protects only the viewport.
    void enforceHDTextureBudget(const Position& mapCenter, const Rect& visibleBlocks);
    void dropHDTextureAt(uint8 z, uint blockIndex);
    // Worker entry point. Touches nothing but its own task.
    static ImagePtr composeHDImage(const HDRenderTask& task, const std::atomic<uint32>& generation);

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

    // Read on the hot updateTile path with a relaxed load, so HD off costs one
    // atomic read and nothing else.
    std::atomic<bool> m_hdMode{false};
    std::atomic<uint32> m_hdGeneration{1};
    size_t m_hdDataBytes = 0;   // guarded by m_lock
    // Scratch buffer for collectHDTile, reused so per-tile collection does not
    // allocate. Dispatcher thread only.
    std::vector<HDMinimapItem> m_hdScratch;

    // Bounded priority queue, deduplicated by block. Dispatcher thread only.
    std::vector<HDRenderJob> m_hdQueue;
    // Blocks handed to a worker and not yet collected. Together with m_hdQueue this
    // is the complete "already being worked on" set, so a dropped job can never
    // leave a block permanently unqueueable. Dispatcher thread only.
    std::vector<HDRunningJob> m_hdRunning;
    // Blocks that currently hold an HD texture, so the budget never has to scan
    // the whole block map (the old design walked every floor every frame).
    std::vector<std::pair<uint8, uint>> m_hdResident;

    // Worker hand-off.
    std::mutex m_hdResultLock;
    std::vector<HDRenderResult> m_hdResults;
    std::atomic<int> m_hdRunningJobs{0};
    std::atomic<size_t> m_hdPendingImageBytes{0};
    int m_hdMaxWorkers = 1;
    size_t m_hdTextureBytes = 0;

    // Save coalescing: a request arriving while a save runs sets the pending flag
    // instead of blocking or spawning a second save.
    std::atomic<bool> m_hdSaving{false};
    bool m_hdSavePending = false;
    std::string m_hdSavePendingFile;

    // Counters for getHDStats(). Only the stale counter is written by workers.
    uint64 m_hdCacheHits = 0;
    uint64 m_hdCacheMisses = 0;
    uint64 m_hdEvictions = 0;
    std::atomic<uint64> m_hdStaleDropped{0};
};

extern Minimap g_minimap;

#endif
