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
#include <framework/core/declarations.h>
#include <framework/graphics/declarations.h>
#include <atomic>
#include <list>
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
// Render jobs use a canonical 16-texel-per-tile coordinate system, but their
// output texture is selected from 2..1024 pixels according to the current zoom.
// This keeps close views crisp while allowing the complete downloaded baseline
// to remain visible in overview mode without a 4 MiB texture per map block.
// ---------------------------------------------------------------------------
enum {
    HD_TEXELS_PER_TILE = 16,
    HD_CANONICAL_BLOCK_TEXTURE_SIZE = MMBLOCK_SIZE * HD_TEXELS_PER_TILE,  // 1024
    HD_NO_RECORD = 0xFFFF,

    // Ring of blocks around the viewport that eviction leaves alone, so a step or
    // two of movement does not immediately re-render what just scrolled off.
    // Everything beyond it is evictable, including on the floor being explored.
    HD_PROTECT_MARGIN_BLOCKS = 1,

    // The one and only queue bound in the system.
    HD_MAX_QUEUED_JOBS = 6,

    // Walking sends a fresh edge of map tiles on every step. Rebuilding a full
    // 1024x1024 block for each edge stalls the dispatcher, so stale textures stay
    // drawable until tile updates have settled and are then rebuilt only once.
    HD_RENDER_SETTLE_DELAY_MS = 400,

    // Separate HD sidecar format. minimap.otmm itself is never touched.
    OTMM_HD_SIGNATURE = 0x4844544F,
    OTMM_HD_VERSION = 2,

    // Baseline archive generated offline from the server's .otbm. Unlike the
    // player sidecar it is indexed and read one block at a time, because it covers
    // the whole world and must never be resident in full.
    OTMM_HD_BASE_SIGNATURE = 0x42445448,
    OTMM_HD_BASE_VERSION = 3,

    // Distributed whole-world baseline. Every payload is a pre-rendered,
    // compressed RGBA photograph; item ids and tile stacks never leave the
    // server build environment.
    OTMM_HD_RASTER_SIGNATURE = 0x42524448, // "HDRB"
    OTMM_HD_RASTER_VERSION = 1,
    OTMM_HD_RASTER_LOD_COUNT = 3
};

// Budgets are expressed in bytes, not in block counts, because resources of very
// different sizes share them.
inline constexpr size_t HD_TEXTURE_BUDGET_BYTES = 16ull * 1024 * 1024;
inline constexpr size_t HD_PENDING_IMAGE_BUDGET_BYTES = 4ull * 1024 * 1024;
inline constexpr size_t HD_SPRITE_IMAGE_BUDGET_BYTES = 8ull * 1024 * 1024;
inline constexpr size_t HD_SPRITE_IMAGE_MAX_ENTRIES = 512;
inline constexpr size_t hdBlockTextureBytes(uint16 side) {
    return (size_t)side * side * 4;
}

// Defensive limits for the HD sidecar parser. Nothing read from a file is
// trusted before being checked against these.
inline constexpr uint32 HD_MAX_COMPRESSED_BYTES = 2u * 1024 * 1024;
inline constexpr uint32 HD_MAX_UNCOMPRESSED_BYTES = 2u * 1024 * 1024;
inline constexpr uint32 HD_MAX_BLOCKS_PER_FLOOR = 65536;
inline constexpr uint16 HD_MAX_TILES_PER_BLOCK = MMBLOCK_SIZE * MMBLOCK_SIZE;
inline constexpr uint16 HD_MAX_ITEMS_PER_TILE = 64;
inline constexpr uint32 HD_MAX_BASE_BLOCKS = 256u * 1024;
inline constexpr std::array<uint16, OTMM_HD_RASTER_LOD_COUNT> HD_RASTER_LOD_SIDES = { 64, 256, 512 };
inline constexpr uint32 HD_RASTER_MAX_PNG_BYTES = 16u * 1024 * 1024;
inline constexpr size_t HD_RASTER_TEXTURE_BUDGET_BYTES = 32ull * 1024 * 1024;
inline constexpr size_t HD_RASTER_QUEUE_BUDGET_BYTES = 24ull * 1024 * 1024;
inline constexpr size_t HD_RASTER_MAX_QUEUED_JOBS = 32;

// Resident budget for decoded tile data. The baseline archive covers the entire
// world, so payloads are streamed in and dropped again; only blocks carrying
// unsaved player data are exempt from eviction.
inline constexpr size_t HD_DATA_BUDGET_BYTES = 12ull * 1024 * 1024;
// Blocks pulled from the baseline archive per frame, so entering a new region
// cannot turn into a long synchronous read.
inline constexpr int HD_BASE_LOADS_PER_FRAME = 1;

// Where a block lives inside the baseline archive.
struct HDBaseEntry
{
    uint32 offset = 0;
    uint32 compressedSize = 0;
    uint32 plainSize = 0;
};

struct HDRasterPayloadEntry
{
    uint32 offset = 0;
    uint32 size = 0;
};

struct HDRasterBaseEntry
{
    std::array<HDRasterPayloadEntry, OTMM_HD_RASTER_LOD_COUNT> lods;
};

struct HDRasterTextureCache
{
    std::array<TexturePtr, OTMM_HD_RASTER_LOD_COUNT> textures;
    std::array<ticks_t, OTMM_HD_RASTER_LOD_COUNT> lastUsed{};
    std::array<ticks_t, OTMM_HD_RASTER_LOD_COUNT> retryAfter{};
    std::array<bool, OTMM_HD_RASTER_LOD_COUNT> queued{};
};

struct HDRasterDecodeJob
{
    uint blockIndex = 0;
    uint8 z = 0;
    uint8 lod = 0;
    uint32 generation = 0;
    int priority = 0;
    std::vector<uint8> png;
};

struct HDRasterDecodeResult
{
    uint blockIndex = 0;
    uint8 z = 0;
    uint8 lod = 0;
    uint32 generation = 0;
    ImagePtr image;
};

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

    // Content that came from the read-only baseline archive can be thrown away and
    // read again, so it is what the data budget evicts. Player data never is,
    // until it has been saved.
    void setFromBaseline(bool fromBaseline) { m_fromBaseline = fromBaseline; }
    bool isReloadable() const { return m_fromBaseline && !isDirty(); }

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
    void setTexture(const TexturePtr& texture, uint32 revision, uint16 textureSize) {
        m_texture = texture;
        m_renderedRevision = revision;
        m_textureSize = textureSize;
    }
    void dropTexture() { m_texture = nullptr; m_renderedRevision = 0; m_textureSize = 0; }
    bool hasTexture() const { return m_texture != nullptr; }
    bool hasTextureFor(uint16 textureSize) const {
        return m_texture != nullptr && m_textureSize == textureSize;
    }
    uint16 getTextureSize() const { return m_textureSize; }
    size_t getTextureBytes() const { return hdBlockTextureBytes(m_textureSize); }

    // Revision bookkeeping replaces re-hashing the block on every draw.
    uint32 getRenderedRevision() const { return m_renderedRevision; }
    uint32 getFailedRevision() const { return m_failedRevision; }
    void markRenderFailed(uint32 revision, uint16 textureSize) {
        m_failedRevision = revision;
        m_failedTextureSize = textureSize;
    }
    bool needsRender(ticks_t now, uint16 textureSize) const {
        if((m_renderedRevision == m_contentRevision && m_textureSize == textureSize) ||
           (m_failedRevision == m_contentRevision && m_failedTextureSize == textureSize))
            return false;

        // The first texture must appear immediately. Once a drawable texture
        // exists, coalesce the strip of tile changes produced by walking instead
        // of rebuilding this whole block once per step.
        return !m_texture || m_lastContentChange == 0 ||
               now - m_lastContentChange >= HD_RENDER_SETTLE_DELAY_MS;
    }

    ticks_t getLastUsed() const { return m_lastUsed; }
    void markUsed(ticks_t now) { m_lastUsed = now; }

private:
    void compact();

    TexturePtr m_texture;
    uint16 m_textureSize = 0;
    uint32 m_renderedRevision = 0;
    uint32 m_failedRevision = 0;
    uint16 m_failedTextureSize = 0;
    ticks_t m_lastUsed = 0;

    std::vector<HDTileRecord> m_records;   // one entry per non-empty tile
    std::vector<HDMinimapItem> m_items;    // packed item pool
    std::vector<uint16> m_slot;            // 4096 entries: tileIndex -> record index
    uint32 m_contentRevision = 0;
    uint32 m_savedRevision = 0;
    uint32 m_garbageItems = 0;
    ticks_t m_lastContentChange = 0;
    bool m_fromBaseline = false;
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
// all, no MinimapBlock_ptr â€” a queued render must never keep a region of the
// minimap alive.
struct HDRenderJob
{
    uint blockIndex = 0;
    Position blockPos;
    uint32 generation = 0;
    uint32 revision = 0;
    uint16 textureSize = 0;
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
    uint32 spriteAddress = 0;
    int spriteId = 0;
    int16 destX = 0;   // canonical texels; scaled to the selected output LOD
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
    uint16 textureSize = 0;
    FileStreamPtr spriteFile;
    int spriteSize = 32;
    bool spritesHaveAlpha = false;
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
    uint16 textureSize = 0;
    ImagePtr image;
};

// A block currently being rendered by a worker.
struct HDRunningJob
{
    uint blockIndex = 0;
    uint8 z = 0;
    uint32 revision = 0;
    uint16 textureSize = 0;
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
    void cleanClassic();
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
    void cleanClassic();

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

    // Offline tool: reads a server .otbm and writes the whole-world HD baseline.
    // The base minimap.otmm cannot feed HD because it stores one colour per tile
    // and no item ids, so this is the only way to cover unexplored regions.
    bool generateHDFromOtbm(const std::string& otbmFile, const std::string& outputFile);

    // Attaches the generated baseline. Only its index becomes resident; block
    // payloads are streamed on demand and evicted under the data budget.
    bool openHDBase(const std::string& fileName);
    void closeHDBase();
    bool hasHDBase() const { return m_hdBaseFile != nullptr; }

    // Debug instrumentation. Cheap enough to call from Lua on demand; never logged
    // on its own.
    std::string getHDStats();

private:
    // Records the drawable items of one tile. Only ever called with HD mode on.
    void collectHDTile(const Position& pos, const TilePtr& tile);
    // Drops all HD payloads and bumps the generation. Caller must hold m_lock.
    void invalidateHDLocked();

    // --- HD render pipeline (main/render thread unless noted) ----------------
    // Draws the optional HD layer over the standard minimap and keeps the cache fed.
    void drawHD(const Rect& screenRect, const Position& mapCenter, float scale,
                const Point& blockOff, const Point& start);
    void drawHDRaster(const Rect& screenRect, const Position& mapCenter, float scale,
                      const Point& blockOff, const Point& start);
    uint8 chooseHDRasterLod(int blockPixels) const;
    void requestHDRasterBlock(uint8 z, uint blockIndex, uint8 lod, int priority);
    void dispatchHDRasterJobs();
    void collectHDRasterResults();
    void enforceHDRasterTextureBudget();
    void clearHDRasterState();
    // One-shot fill from the tiles g_map currently holds, bounded to the viewport
    // plus the protection margin. Runs once after HD is switched on.
    void bootstrapHDFromMap(const Position& mapCenter, const Rect& visibleBlocks);
    // Pulls one block's tile data out of the baseline archive. Caller holds m_lock.
    bool loadHDBaseBlockLocked(uint8 z, uint blockIndex, const Position& blockPos);
    // Frees decoded tile data until HD_DATA_BUDGET_BYTES is respected. Blocks with
    // unsaved player edits are never dropped. Caller holds m_lock.
    void enforceHDDataBudgetLocked(const Position& mapCenter, const Rect& visibleBlocks);
    // Builds the sparse snapshot of a block and inserts it into the bounded queue,
    // replacing any older entry for the same block.
    void queueHDBlock(MinimapBlock& block, const Position& blockPos, uint blockIndex,
                      int priority, uint16 textureSize);
    // Pops the best queued jobs and starts them on the async dispatcher.
    void dispatchHDJobs();
    // Turns a snapshot into blits. Reads g_things/g_sprites, so dispatcher only.
    bool buildHDTask(const HDRenderJob& job, HDRenderTask& task, bool pumpNativeMessages = false);
    // Small HD-only decoded sprite cache. It avoids decompressing the same nearby
    // .spr entries whenever a walked tile invalidates its block, without growing
    // the general sprite cache or retaining an unbounded region.
    ImagePtr getHDSpriteImage(int spriteId);
    void clearHDSpriteImageCache();
    // Uploads finished images into textures.
    void collectHDResults();
    // Frees textures until the budget is respected. Protects only the viewport.
    void enforceHDTextureBudget(const Position& mapCenter, const Rect& visibleBlocks);
    void dropHDTextureAt(uint8 z, uint blockIndex);
    // Worker entry point. Touches nothing but its own task.
    static ImagePtr composeHDImage(const HDRenderTask& task, const std::atomic<uint32>& generation,
                                   bool pumpNativeMessages = false);

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
    // Set when HD is switched on, consumed by the next draw. Dispatcher thread only.
    bool m_hdBootstrapPending = false;
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
    // Used by the single HD worker only. Reusing it preserves the authenticated
    // DKA2 chunk cache instead of reopening and reallocating it for every block.
    FileStreamPtr m_hdWorkerSpriteFile;

    struct HDSpriteImageCacheEntry {
        ImagePtr image;
        size_t bytes = 0;
        std::list<int>::iterator lruIt;
    };
    std::unordered_map<int, HDSpriteImageCacheEntry> m_hdSpriteImageCache;
    std::list<int> m_hdSpriteImageLru;
    size_t m_hdSpriteImageBytes = 0;

    // Baseline archive: index resident, payloads streamed. Dispatcher thread only.
    std::vector<std::unordered_map<uint, HDBaseEntry>> m_hdBaseIndex;
    FileStreamPtr m_hdBaseFile;
    std::string m_hdBaseFileName;
    bool m_hdBaseRaster = false;
    std::vector<std::unordered_map<uint, HDRasterBaseEntry>> m_hdRasterIndex;
    std::vector<std::unordered_map<uint, HDRasterTextureCache>> m_hdRasterCache;
    std::vector<HDRasterDecodeJob> m_hdRasterQueue;
    std::mutex m_hdRasterResultLock;
    std::vector<HDRasterDecodeResult> m_hdRasterResults;
    std::atomic<int> m_hdRasterRunningJobs{0};
    size_t m_hdRasterQueuedBytes = 0;
    size_t m_hdRasterTextureBytes = 0;
    ticks_t m_hdRasterBudgetNextScan = 0;
    uint64 m_hdBaseLoads = 0;
    uint64 m_hdBaseDataEvictions = 0;
    ticks_t m_hdDataBudgetNextScan = 0;

    // Save coalescing: a request arriving while a save runs sets the pending flag
    // instead of blocking or spawning a second save.
    std::atomic<bool> m_hdSaving{false};
    bool m_hdSavePending = false;
    std::string m_hdSavePendingFile;
    // Disabling is deferred while an async save is active, otherwise incrementing
    // the generation would cancel the save and silently lose the newest map data.
    std::atomic<bool> m_hdDisablePending{false};

    // Counters for getHDStats(). Only the stale counter is written by workers.
    uint64 m_hdCacheHits = 0;
    uint64 m_hdCacheMisses = 0;
    uint64 m_hdEvictions = 0;
    std::atomic<uint64> m_hdStaleDropped{0};
};

extern Minimap g_minimap;

#endif
