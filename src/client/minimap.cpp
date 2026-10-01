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


#include "minimap.h"
#include "tile.h"
#include "item.h"
#include "map.h"
#include "game.h"
#include "gameconfig.h"
#include "spritemanager.h"
#include "thingtypemanager.h"
#include "thingtype.h"
#include "itemtype.h"

#include <framework/core/binarytree.h>

#include <framework/graphics/image.h>
#include <framework/graphics/texture.h>
#include <framework/graphics/painter.h>
#include <framework/graphics/image.h>
#include <framework/graphics/framebuffermanager.h>
#include <framework/core/resourcemanager.h>
#include <framework/core/filestream.h>
#include <framework/core/asyncdispatcher.h>
#include <framework/core/eventdispatcher.h>
#include <zlib.h>

#include <framework/util/stats.h>
#include <algorithm>
#include <climits>
#include <cstring>
#include <sstream>
#include <thread>
#include <unordered_map>

Minimap g_minimap;

// ---------------------------------------------------------------------------
// HDBlockData
// ---------------------------------------------------------------------------

bool HDBlockData::setTileItems(uint16 tileIndex, const HDMinimapItem* items, uint16 count)
{
    if(tileIndex >= MMBLOCK_SIZE * MMBLOCK_SIZE)
        return false;

    if(m_slot.empty()) {
        if(count == 0)
            return false;   // nothing to store, stay unallocated
        m_slot.assign(MMBLOCK_SIZE * MMBLOCK_SIZE, HD_NO_RECORD);
    }

    const uint16 recordIndex = m_slot[tileIndex];

    if(recordIndex == HD_NO_RECORD) {
        if(count == 0)
            return false;

        HDTileRecord record;
        record.tileIndex = tileIndex;
        record.count = count;
        record.offset = (uint32)m_items.size();
        m_items.insert(m_items.end(), items, items + count);

        m_slot[tileIndex] = (uint16)m_records.size();
        m_records.push_back(record);
        ++m_contentRevision;
        return true;
    }

    HDTileRecord& record = m_records[recordIndex];

    if(count == record.count &&
       std::equal(items, items + count, m_items.begin() + record.offset)) {
        return false;   // unchanged, the common case while walking
    }

    if(count == 0) {
        // Drop the record; swap-erase and repair the slot of the moved entry.
        m_garbageItems += record.count;
        m_slot[tileIndex] = HD_NO_RECORD;

        const uint16 lastIndex = (uint16)(m_records.size() - 1);
        if(recordIndex != lastIndex) {
            m_records[recordIndex] = m_records[lastIndex];
            m_slot[m_records[recordIndex].tileIndex] = recordIndex;
        }
        m_records.pop_back();
        ++m_contentRevision;
        compact();
        return true;
    }

    if(count == record.count) {
        std::copy(items, items + count, m_items.begin() + record.offset);
    } else {
        // Size changed: the old span becomes garbage and the new one is appended.
        m_garbageItems += record.count;
        record.offset = (uint32)m_items.size();
        record.count = count;
        m_items.insert(m_items.end(), items, items + count);
    }

    ++m_contentRevision;
    compact();
    return true;
}

void HDBlockData::compact()
{
    // Only worth it once the dead span outweighs the live data.
    if(m_garbageItems <= 1024 || m_garbageItems * 2 <= m_items.size())
        return;

    std::vector<HDMinimapItem> packed;
    packed.reserve(m_items.size() - m_garbageItems);

    for(HDTileRecord& record : m_records) {
        const uint32 offset = (uint32)packed.size();
        packed.insert(packed.end(),
                      m_items.begin() + record.offset,
                      m_items.begin() + record.offset + record.count);
        record.offset = offset;
    }

    m_items.swap(packed);
    m_items.shrink_to_fit();
    m_garbageItems = 0;
}

size_t HDBlockData::getByteSize() const
{
    return m_records.capacity() * sizeof(HDTileRecord) +
           m_items.capacity() * sizeof(HDMinimapItem) +
           m_slot.capacity() * sizeof(uint16);
}

// ---------------------------------------------------------------------------

void MinimapBlock::clean()
{
    m_tiles.fill(MinimapTile());
    m_texture.reset();
    m_hd.reset();
    m_mustUpdate = false;
}

void MinimapBlock::update()
{
    if(!m_mustUpdate)
        return;

    auto image = std::make_shared<Image>(Size(MMBLOCK_SIZE, MMBLOCK_SIZE));

    bool shouldDraw = false;
    for(int x=0;x<MMBLOCK_SIZE;++x) {
        for(int y=0;y<MMBLOCK_SIZE;++y) {
            uint8 c = getTile(x, y).color;
            Color col = Color::alpha;
            if(c != 255) {
                col = Color::from8bit(c);
                shouldDraw = true;
            }
            image->setPixel(x, y, col);
        }
    }

    if(shouldDraw) {
        m_texture = std::make_shared<Texture>(image);
    } else
        m_texture.reset();

    m_mustUpdate = false;
}

void MinimapBlock::updateTile(int x, int y, const MinimapTile& tile)
{
    if(m_tiles[getTileIndex(x,y)].color != tile.color)
        m_mustUpdate = true;

    m_tiles[getTileIndex(x,y)] = tile;
}

void Minimap::init()
{
    m_tileBlocks.resize(g_gameConfig.getMapMaxZ() + 1);

    // The HD minimap is a secondary feature: it never gets more than two workers,
    // and on anything but a clearly wide machine it gets one. Gameplay owns the
    // remaining cores.
    const unsigned cores = std::thread::hardware_concurrency();
    m_hdMaxWorkers = (cores > 8) ? 2 : 1;
}

void Minimap::terminate()
{
    // Invalidate first: any worker still running observes the new generation and
    // throws its result away instead of touching state that is being torn down.
    m_hdGeneration.fetch_add(1, std::memory_order_release);
    m_hdMode.store(false, std::memory_order_relaxed);

    {
        std::lock_guard<std::mutex> lock(m_hdResultLock);
        m_hdResults.clear();
    }
    m_hdPendingImageBytes.store(0, std::memory_order_release);
    m_hdQueue.clear();
    m_hdRunning.clear();
    closeHDBase();

    clean();

    // g_asyncDispatcher is joined by the framework during shutdown, so there is no
    // detached thread and no this-capturing work left behind.
}

void Minimap::clean()
{
    std::lock_guard<std::mutex> lock(m_lock);
    for (auto& tileBlocks : m_tileBlocks)
        tileBlocks.clear();

    // Dropping every block also drops their HD payloads; the generation bump is
    // what stops async work started before the clean from touching new state.
    m_hdDataBytes = 0;
    m_hdGeneration.fetch_add(1, std::memory_order_release);
}

void Minimap::draw(const Rect& screenRect, const Position& mapCenter, float scale, const Color& color)
{
    if(screenRect.isEmpty())
        return;

    Rect mapRect = calcMapRect(screenRect, mapCenter, scale);
    g_drawQueue->addFilledRect(screenRect, color);

    if(MMBLOCK_SIZE*scale <= 1 || !mapCenter.isMapPosition()) {
        return;
    }

    size_t drawQueueStart = g_drawQueue->size();
    Point blockOff = getBlockOffset(mapRect.topLeft());
    Point off = Point((mapRect.size() * scale).toPoint() - screenRect.size().toPoint())/2;
    Point start = screenRect.topLeft() -(mapRect.topLeft() - blockOff)*scale - off;

    for(int y = blockOff.y, ys = start.y;ys<screenRect.bottom();y += MMBLOCK_SIZE, ys += MMBLOCK_SIZE*scale) {
        if(y < 0 || y >= 65536)
            continue;

        for(int x = blockOff.x, xs = start.x;xs<screenRect.right();x += MMBLOCK_SIZE, xs += MMBLOCK_SIZE*scale) {
            if(x < 0 || x >= 65536)
                continue;

            Position blockPos(x, y, mapCenter.z);
            if(!hasBlock(blockPos))
                continue;

            MinimapBlock& block = getBlock(Position(x, y, mapCenter.z));
            block.update();

            const TexturePtr& tex = block.getTexture();
            if(tex) {
                Rect src(0, 0, MMBLOCK_SIZE, MMBLOCK_SIZE);
                Rect dest(xs, ys, MMBLOCK_SIZE * scale, MMBLOCK_SIZE * scale);

                g_drawQueue->addTexturedRect(dest, tex, src);
            }
        }
    }

    // HD is drawn over the base layer, never instead of it. A block whose HD
    // texture is missing, still rendering or evicted simply shows the standard
    // minimap underneath: no holes, no flicker, and any HD failure degrades to
    // exactly the behaviour of a client without the feature.
    if(m_hdMode.load(std::memory_order_relaxed) && scale >= HD_MIN_SCALE)
        drawHD(screenRect, mapCenter, scale, blockOff, start);

    g_drawQueue->setClip(drawQueueStart, screenRect);
}

bool Minimap::drawHD(const Rect& screenRect, const Position& mapCenter, float scale,
                     const Point& blockOff, const Point& start)
{
    if(mapCenter.z >= m_tileBlocks.size())
        return false;

    const ticks_t now = stdext::millis();
    const int blockPixels = (int)(MMBLOCK_SIZE * scale);
    if(blockPixels <= 0)
        return false;

    const Rect hdSrc(0, 0, HD_BLOCK_TEXTURE_SIZE, HD_BLOCK_TEXTURE_SIZE);
    const int centerBlockX = mapCenter.x / MMBLOCK_SIZE;
    const int centerBlockY = mapCenter.y / MMBLOCK_SIZE;

    // Block-space rectangle of what is on screen, resolved up front with the same
    // stepping the draw loop uses. Everything outside it (plus the protection
    // margin) is eligible for eviction, including on the active floor.
    int minBlockX = INT_MAX, minBlockY = INT_MAX, maxBlockX = INT_MIN, maxBlockY = INT_MIN;
    for(int y = blockOff.y, ys = start.y; ys < screenRect.bottom(); y += MMBLOCK_SIZE, ys += blockPixels) {
        if(y < 0 || y >= 65536)
            continue;
        for(int x = blockOff.x, xs = start.x; xs < screenRect.right(); x += MMBLOCK_SIZE, xs += blockPixels) {
            if(x < 0 || x >= 65536)
                continue;
            const int bx = x / MMBLOCK_SIZE;
            const int by = y / MMBLOCK_SIZE;
            minBlockX = std::min(minBlockX, bx); maxBlockX = std::max(maxBlockX, bx);
            minBlockY = std::min(minBlockY, by); maxBlockY = std::max(maxBlockY, by);
        }
    }

    if(minBlockX == INT_MAX)
        return false;

    const Rect visibleBlocks(minBlockX, minBlockY,
                             maxBlockX - minBlockX + 1, maxBlockY - minBlockY + 1);

    // One-shot fill so switching HD on shows the current surroundings immediately
    // instead of waiting for the player to walk into new updateTile() calls.
    if(m_hdBootstrapPending) {
        m_hdBootstrapPending = false;
        bootstrapHDFromMap(mapCenter, visibleBlocks);
    }

    int baseLoadsLeft = HD_BASE_LOADS_PER_FRAME;

    {
        std::lock_guard<std::mutex> lock(m_lock);
        auto& blocks = m_tileBlocks[mapCenter.z];

        for(int y = blockOff.y, ys = start.y; ys < screenRect.bottom(); y += MMBLOCK_SIZE, ys += blockPixels) {
            if(y < 0 || y >= 65536)
                continue;

            for(int x = blockOff.x, xs = start.x; xs < screenRect.right(); x += MMBLOCK_SIZE, xs += blockPixels) {
                if(x < 0 || x >= 65536)
                    continue;

                const int bx = x / MMBLOCK_SIZE;
                const int by = y / MMBLOCK_SIZE;
                const Position blockPos(x, y, mapCenter.z);
                const uint blockIndex = getBlockIndex(blockPos);

                auto it = blocks.find(blockIndex);
                HDBlockData* hd = (it != blocks.end() && it->second) ? it->second->getHDData() : nullptr;

                // Nothing decoded yet: pull this block out of the baseline archive.
                // Rate limited so entering a new region cannot turn into a long
                // synchronous read, and the rest arrives over the next frames.
                if(!hd && baseLoadsLeft > 0) {
                    if(loadHDBaseBlockLocked((uint8)mapCenter.z, blockIndex, blockPos)) {
                        --baseLoadsLeft;
                        it = blocks.find(blockIndex);
                        hd = (it != blocks.end() && it->second) ? it->second->getHDData() : nullptr;
                    }
                }

                if(!hd)
                    continue;

                hd->markUsed(now);

                if(hd->hasTexture()) {
                    g_drawQueue->addTexturedRect(Rect(xs, ys, blockPixels, blockPixels),
                                                hd->getTexture(), hdSrc);
                    if(!hd->needsRender()) {
                        ++m_hdCacheHits;
                        continue;
                    }
                    // Stale but drawable: keep showing it while the new one builds.
                }
                ++m_hdCacheMisses;

                const int priority = std::abs(bx - centerBlockX) + std::abs(by - centerBlockY);
                queueHDBlock(*it->second, blockPos, blockIndex, priority);
            }
        }
    }

    dispatchHDJobs();
    collectHDResults();
    enforceHDTextureBudget(mapCenter, visibleBlocks);

    {
        std::lock_guard<std::mutex> lock(m_lock);
        enforceHDDataBudgetLocked(mapCenter, visibleBlocks);
    }

    return true;
}

void Minimap::enforceHDDataBudgetLocked(const Position& mapCenter, const Rect& visibleBlocks)
{
    // Without a baseline archive the decoded data IS the only copy, so there is
    // nothing safe to drop and the budget does not apply.
    if(!m_hdBaseFile || m_hdDataBytes <= HD_DATA_BUDGET_BYTES)
        return;

    // If the overage is all player data there is nothing to evict, and rescanning
    // every frame would reintroduce exactly the per-frame full walk this design
    // set out to remove. Back off after a scan that could not free anything.
    const ticks_t now = stdext::millis();
    if(now < m_hdDataBudgetNextScan)
        return;

    const Rect protectedBlocks(visibleBlocks.x() - HD_PROTECT_MARGIN_BLOCKS,
                               visibleBlocks.y() - HD_PROTECT_MARGIN_BLOCKS,
                               visibleBlocks.width() + 2 * HD_PROTECT_MARGIN_BLOCKS,
                               visibleBlocks.height() + 2 * HD_PROTECT_MARGIN_BLOCKS);

    struct Candidate { uint8 z; uint blockIndex; ticks_t lastUsed; bool otherFloor; };
    std::vector<Candidate> candidates;

    for(uint8 z = 0; z < (uint8)m_tileBlocks.size(); ++z) {
        for(auto& pair : m_tileBlocks[z]) {
            if(!pair.second)
                continue;
            const HDBlockData* hd = pair.second->getHDData();
            // Only baseline-sourced, non-dirty data is reloadable. Anything the
            // player collected stays until it has been written to the sidecar.
            if(!hd || !hd->isReloadable())
                continue;

            const bool sameFloor = (z == mapCenter.z);
            if(sameFloor) {
                const Position blockPos = getIndexPosition(pair.first, z);
                if(protectedBlocks.contains(Point(blockPos.x / MMBLOCK_SIZE, blockPos.y / MMBLOCK_SIZE)))
                    continue;
            }

            candidates.push_back({ z, pair.first, hd->getLastUsed(), !sameFloor });
        }
    }

    // Other floors first, then least recently used.
    std::sort(candidates.begin(), candidates.end(),
        [](const Candidate& a, const Candidate& b) {
            if(a.otherFloor != b.otherFloor) return a.otherFloor;
            return a.lastUsed < b.lastUsed;
        });

    for(const Candidate& candidate : candidates) {
        if(m_hdDataBytes <= HD_DATA_BUDGET_BYTES)
            break;

        auto it = m_tileBlocks[candidate.z].find(candidate.blockIndex);
        if(it == m_tileBlocks[candidate.z].end() || !it->second)
            continue;

        HDBlockData* hd = it->second->getHDData();
        if(!hd || !hd->isReloadable())
            continue;

        const size_t bytes = hd->getByteSize();
        // Dropping the payload releases its texture with it, so the texture
        // accounting has to follow.
        if(hd->hasTexture()) {
            if(m_hdTextureBytes >= HD_BLOCK_TEXTURE_BYTES)
                m_hdTextureBytes -= HD_BLOCK_TEXTURE_BYTES;
            for(size_t i = 0; i < m_hdResident.size(); ++i) {
                if(m_hdResident[i].first == candidate.z && m_hdResident[i].second == candidate.blockIndex) {
                    m_hdResident.erase(m_hdResident.begin() + i);
                    break;
                }
            }
        }

        it->second->dropHDData();
        m_hdDataBytes -= std::min(m_hdDataBytes, bytes);
        ++m_hdBaseDataEvictions;
    }

    // Still over after evicting everything reloadable: the rest is player data
    // that must not be dropped, so stop scanning for a while.
    m_hdDataBudgetNextScan = (m_hdDataBytes > HD_DATA_BUDGET_BYTES) ? now + 2000 : 0;
}

void Minimap::bootstrapHDFromMap(const Position& mapCenter, const Rect& visibleBlocks)
{
    // Bounded by construction: the scan is the intersection of what the server has
    // actually sent us (the aware range, a small window around the player) with the
    // visible blocks plus one block of margin. It never walks the block map and
    // never touches the OTMM data.
    //
    // Regions that exist only in the base minimap.otmm are deliberately left alone:
    // that format stores one colour per tile and carries no item ids, so there is
    // nothing there to rebuild sprites from. Those keep the standard minimap until
    // the player walks through them.
    const Position center = g_map.getCentralPosition();
    if(!center.isValid() || center.z != mapCenter.z)
        return;

    const AwareRange range = g_map.getAwareRange();

    const int blockMinX = (visibleBlocks.left() - HD_PROTECT_MARGIN_BLOCKS) * MMBLOCK_SIZE;
    const int blockMaxX = (visibleBlocks.right() + HD_PROTECT_MARGIN_BLOCKS) * MMBLOCK_SIZE + MMBLOCK_SIZE - 1;
    const int blockMinY = (visibleBlocks.top() - HD_PROTECT_MARGIN_BLOCKS) * MMBLOCK_SIZE;
    const int blockMaxY = (visibleBlocks.bottom() + HD_PROTECT_MARGIN_BLOCKS) * MMBLOCK_SIZE + MMBLOCK_SIZE - 1;

    const int minX = std::max({ 0, center.x - range.left, blockMinX });
    const int maxX = std::min({ 65535, center.x + range.right, blockMaxX });
    const int minY = std::max({ 0, center.y - range.top, blockMinY });
    const int maxY = std::min({ 65535, center.y + range.bottom, blockMaxY });

    if(minX > maxX || minY > maxY)
        return;

    for(int y = minY; y <= maxY; ++y) {
        for(int x = minX; x <= maxX; ++x) {
            const Position pos(x, y, mapCenter.z);
            const TilePtr& tile = g_map.getTile(pos);
            if(!tile)
                continue;

            // Reuses the normal collection path, so bootstrapped tiles are
            // identical to walked ones and bump the same revision counters. The
            // draw loop right after this picks the dirty blocks up and queues them
            // with viewport priority, which is already the highest there is.
            collectHDTile(pos, tile);
        }
    }
}

void Minimap::queueHDBlock(MinimapBlock& block, const Position& blockPos, uint blockIndex, int priority)
{
    HDBlockData* hd = block.getHDData();
    if(!hd || hd->isEmpty())
        return;

    const uint32 revision = hd->getContentRevision();

    // A worker is already producing exactly this revision.
    for(const HDRunningJob& running : m_hdRunning) {
        if(running.blockIndex == blockIndex && running.z == blockPos.z && running.revision == revision)
            return;
    }

    // One entry per block, always the newest revision. This is the only place a
    // job enters the queue, and the only bound that exists.
    for(size_t i = 0; i < m_hdQueue.size(); ++i) {
        if(m_hdQueue[i].blockIndex == blockIndex && m_hdQueue[i].blockPos.z == blockPos.z) {
            if(m_hdQueue[i].revision == revision)
                return;
            m_hdQueue.erase(m_hdQueue.begin() + i);
            break;
        }
    }

    if(m_hdQueue.size() >= HD_MAX_QUEUED_JOBS) {
        // Drop the worst queued job rather than the oldest: what matters is being
        // close to the viewport, not arrival order.
        auto worst = std::max_element(m_hdQueue.begin(), m_hdQueue.end(),
            [](const HDRenderJob& a, const HDRenderJob& b) { return a.priority < b.priority; });
        if(worst == m_hdQueue.end() || worst->priority <= priority)
            return;   // the new job is not better than anything queued
        m_hdQueue.erase(worst);
    }

    HDRenderJob job;
    job.blockIndex = blockIndex;
    job.blockPos = blockPos;
    job.generation = m_hdGeneration.load(std::memory_order_acquire);
    job.revision = revision;
    job.priority = priority;

    // Snapshot this block's tiles, plus the tiles of the neighbouring blocks that
    // can spill sprites across the border. Only tiles that carry items are copied,
    // so this stays proportional to real content.
    const int margin = 3;
    const int elevationMargin = 2;

    for(int nby = -1; nby <= 1; ++nby) {
        for(int nbx = -1; nbx <= 1; ++nbx) {
            const int nx = blockPos.x + nbx * MMBLOCK_SIZE;
            const int ny = blockPos.y + nby * MMBLOCK_SIZE;
            if(nx < 0 || ny < 0 || nx >= 65536 || ny >= 65536)
                continue;

            const Position nbPos(nx, ny, blockPos.z);
            auto nit = m_tileBlocks[blockPos.z].find(getBlockIndex(nbPos));
            if(nit == m_tileBlocks[blockPos.z].end() || !nit->second)
                continue;

            const HDBlockData* nhd = nit->second->getHDData();
            if(!nhd)
                continue;

            for(const HDTileRecord& record : nhd->getRecords()) {
                const int localX = record.tileIndex % MMBLOCK_SIZE;
                const int localY = record.tileIndex / MMBLOCK_SIZE;
                const int gx = localX + nbx * MMBLOCK_SIZE;
                const int gy = localY + nby * MMBLOCK_SIZE;

                // Keep only what can actually touch this block's 512x512 target.
                if(gx < -margin || gx >= MMBLOCK_SIZE + margin ||
                   gy < -margin - elevationMargin || gy >= MMBLOCK_SIZE + margin)
                    continue;

                HDJobTile jobTile;
                jobTile.gx = (int16)gx;
                jobTile.gy = (int16)gy;
                jobTile.first = (uint32)job.items.size();
                jobTile.count = record.count;

                const HDMinimapItem* src = nhd->getItemPool().data() + record.offset;
                job.items.insert(job.items.end(), src, src + record.count);
                job.tiles.push_back(jobTile);
            }
        }
    }

    if(job.tiles.empty())
        return;

    m_hdQueue.push_back(std::move(job));
}

void Minimap::dispatchHDJobs()
{
    while(m_hdRunningJobs.load(std::memory_order_acquire) < m_hdMaxWorkers && !m_hdQueue.empty()) {
        // Do not start work whose output has nowhere to go yet.
        if(m_hdPendingImageBytes.load(std::memory_order_acquire) + HD_BLOCK_TEXTURE_BYTES
           > HD_PENDING_IMAGE_BUDGET_BYTES)
            break;

        auto best = std::min_element(m_hdQueue.begin(), m_hdQueue.end(),
            [](const HDRenderJob& a, const HDRenderJob& b) { return a.priority < b.priority; });

        HDRenderJob job = std::move(*best);
        m_hdQueue.erase(best);

        if(job.generation != m_hdGeneration.load(std::memory_order_acquire)) {
            m_hdStaleDropped.fetch_add(1, std::memory_order_relaxed);
            continue;
        }

        HDRenderTask task;
        if(!buildHDTask(job, task))
            continue;

        m_hdRunningJobs.fetch_add(1, std::memory_order_release);
        m_hdPendingImageBytes.fetch_add(HD_BLOCK_TEXTURE_BYTES, std::memory_order_release);
        m_hdRunning.push_back({ task.blockIndex, task.z, task.revision });

        // g_asyncDispatcher owns joinable threads and is stopped by the framework
        // during shutdown, so nothing here can outlive the process teardown.
        // Capturing g_minimap's `this` is safe: it is a global with static storage.
        g_asyncDispatcher.dispatch([this, task = std::move(task)]() mutable {
            // Always posts a result, even a cancelled one with a null image, so
            // collectHDResults is the single place that retires in-flight state.
            HDRenderResult result;
            result.blockIndex = task.blockIndex;
            result.z = task.z;
            result.generation = task.generation;
            result.revision = task.revision;
            result.image = composeHDImage(task, m_hdGeneration);

            {
                std::lock_guard<std::mutex> lock(m_hdResultLock);
                m_hdResults.push_back(std::move(result));
            }

            m_hdRunningJobs.fetch_sub(1, std::memory_order_release);
        });
    }
}

bool Minimap::buildHDTask(const HDRenderJob& job, HDRenderTask& task)
{
    task.blockIndex = job.blockIndex;
    task.z = (uint8)job.blockPos.z;
    task.generation = job.generation;
    task.revision = job.revision;

    // Protobuf (15.x) assets store the whole bounding square per layer; legacy .spr
    // splits it into 32px cells.
    const bool protobuf = g_sprites.isHdMod();
    const int spriteSize = g_sprites.spriteSize() > 0 ? g_sprites.spriteSize() : 32;

    // Sprite images and thing types are resolved HERE, on the dispatcher thread.
    // SpriteManager decrypts in place and mutates an LRU, and ThingTypeManager has
    // no synchronisation at all, so a worker must never reach either of them.
    // Deduplicated so a wall repeated across a block decodes once.
    std::unordered_map<int, ImagePtr> resolved;
    auto spriteImage = [&](int spriteId) -> const ImagePtr& {
        auto it = resolved.find(spriteId);
        if(it == resolved.end())
            it = resolved.emplace(spriteId, g_sprites.getSpriteImage(spriteId)).first;
        return it->second;
    };

    // Two passes so full-ground tiles land under everything else, matching the
    // stacking the game view uses.
    for(int pass = 0; pass < 2; ++pass) {
        for(const HDJobTile& jobTile : job.tiles) {
            for(uint16 i = 0; i < jobTile.count; ++i) {
                const HDMinimapItem& entry = job.items[jobTile.first + i];

                if(!g_things.isValidDatId(entry.id, ThingCategoryItem))
                    continue;

                // Non-owning observer into g_things' own storage; valid for this
                // synchronous scope only, which is why nothing here escapes to a worker.
                ThingType* thingType = g_things.rawGetThingType(entry.id, ThingCategoryItem);
                if(!thingType || !thingType->isLoaded())
                    continue;

                const bool fullGround = thingType->isFullGround();
                if((pass == 0) != fullGround)
                    continue;

                const int layers = thingType->getLayers();
                const int npx = std::max(1, thingType->getNumPatternX());
                const int npy = std::max(1, thingType->getNumPatternY());
                const int npz = std::max(1, thingType->getNumPatternZ());

                int xPattern = 0, yPattern = 0;
                if(thingType->isSplash() || thingType->isFluidContainer()) {
                    int color = Otc::FluidTransparent;
                    switch(entry.subtype) {
                        case Otc::FluidNone:        color = Otc::FluidTransparent; break;
                        case Otc::FluidWater:       color = Otc::FluidBlue;   break;
                        case Otc::FluidMana:        color = Otc::FluidPurple; break;
                        case Otc::FluidBeer:        color = Otc::FluidBrown;  break;
                        case Otc::FluidOil:         color = Otc::FluidBrown;  break;
                        case Otc::FluidBlood:       color = Otc::FluidRed;    break;
                        case Otc::FluidSlime:       color = Otc::FluidGreen;  break;
                        case Otc::FluidMud:         color = Otc::FluidBrown;  break;
                        case Otc::FluidLemonade:    color = Otc::FluidYellow; break;
                        case Otc::FluidMilk:        color = Otc::FluidWhite;  break;
                        case Otc::FluidWine:        color = Otc::FluidPurple; break;
                        case Otc::FluidHealth:      color = Otc::FluidRed;    break;
                        case Otc::FluidUrine:       color = Otc::FluidYellow; break;
                        case Otc::FluidRum:         color = Otc::FluidBrown;  break;
                        case Otc::FluidFruidJuice:  color = Otc::FluidYellow; break;
                        case Otc::FluidCoconutMilk: color = Otc::FluidWhite;  break;
                        case Otc::FluidTea:         color = Otc::FluidBrown;  break;
                        case Otc::FluidMead:        color = Otc::FluidBrown;  break;
                        default:                    color = Otc::FluidTransparent; break;
                    }
                    xPattern = (color % 4) % npx;
                    yPattern = (color / 4) % npy;
                }

                const std::vector<int> sprites = thingType->getSprites();
                const int numSprites = (int)sprites.size();
                if(numSprites <= 0)
                    continue;

                const int width = thingType->getWidth();
                const int height = thingType->getHeight();

                if(protobuf) {
                    for(int l = 0; l < layers; ++l) {
                        const int spriteIndex = ((0 * npy + yPattern) * npx + xPattern) * layers + l;
                        if(spriteIndex < 0 || spriteIndex >= numSprites)
                            continue;

                        const ImagePtr& img = spriteImage(sprites[spriteIndex]);
                        if(!img)
                            continue;

                        int cellsW = std::max(1, img->getWidth() / spriteSize);
                        int cellsH = std::max(1, img->getHeight() / spriteSize);

                        HDBlit blit;
                        blit.image = img;
                        // The tile is the bottom-right cell; the thing extends up/left.
                        blit.destX = (int16)((jobTile.gx - (cellsW - 1)) * HD_TEXELS_PER_TILE);
                        blit.destY = (int16)((jobTile.gy - (cellsH - 1)) * HD_TEXELS_PER_TILE);
                        blit.width = (int16)(cellsW * HD_TEXELS_PER_TILE);
                        blit.height = (int16)(cellsH * HD_TEXELS_PER_TILE);
                        task.blits.push_back(std::move(blit));
                    }
                } else {
                    for(int l = 0; l < layers; ++l) {
                        for(int h = 0; h < height; ++h) {
                            for(int w = 0; w < width; ++w) {
                                const int spriteIndex =
                                    ((((l * npz + 0) * npy + yPattern) * npx + xPattern)
                                     * height + (height - h - 1)) * width + (width - w - 1);
                                if(spriteIndex < 0 || spriteIndex >= numSprites)
                                    continue;

                                const ImagePtr& img = spriteImage(sprites[spriteIndex]);
                                if(!img)
                                    continue;

                                HDBlit blit;
                                blit.image = img;
                                blit.destX = (int16)((jobTile.gx - (width - 1) + w) * HD_TEXELS_PER_TILE);
                                blit.destY = (int16)((jobTile.gy - (height - 1) + h) * HD_TEXELS_PER_TILE);
                                blit.width = HD_TEXELS_PER_TILE;
                                blit.height = HD_TEXELS_PER_TILE;
                                task.blits.push_back(std::move(blit));
                            }
                        }
                    }
                }
            }
        }
    }

    return !task.blits.empty();
}

ImagePtr Minimap::composeHDImage(const HDRenderTask& task, const std::atomic<uint32>& generation)
{
    // Rendered straight at its final size. There is no oversized intermediate and
    // no crop pass: peak memory for a render is exactly one 512x512 RGBA image.
    ImagePtr target = std::make_shared<Image>(Size(HD_BLOCK_TEXTURE_SIZE, HD_BLOCK_TEXTURE_SIZE));
    uint8* dstBase = target->getPixelData();

    int sinceCheck = 0;
    for(const HDBlit& blit : task.blits) {
        // Early cancellation: a job invalidated by a toggle, relog or clean stops
        // burning CPU instead of finishing and being thrown away at the end.
        if(++sinceCheck >= 32) {
            sinceCheck = 0;
            if(generation.load(std::memory_order_acquire) != task.generation)
                return nullptr;
        }

        const ImagePtr& src = blit.image;
        if(!src || blit.width <= 0 || blit.height <= 0)
            continue;

        const int srcW = src->getWidth();
        const int srcH = src->getHeight();
        if(srcW <= 0 || srcH <= 0)
            continue;

        uint8* srcBase = src->getPixelData();

        for(int oy = 0; oy < blit.height; ++oy) {
            const int dy = blit.destY + oy;
            if(dy < 0 || dy >= HD_BLOCK_TEXTURE_SIZE)
                continue;

            int sy0 = (oy * srcH) / blit.height;
            int sy1 = ((oy + 1) * srcH) / blit.height;
            if(sy1 <= sy0) sy1 = sy0 + 1;
            if(sy1 > srcH) sy1 = srcH;

            for(int ox = 0; ox < blit.width; ++ox) {
                const int dx = blit.destX + ox;
                if(dx < 0 || dx >= HD_BLOCK_TEXTURE_SIZE)
                    continue;

                int sx0 = (ox * srcW) / blit.width;
                int sx1 = ((ox + 1) * srcW) / blit.width;
                if(sx1 <= sx0) sx1 = sx0 + 1;
                if(sx1 > srcW) sx1 = srcW;

                // Box filter in premultiplied alpha so anti-aliased sprite edges
                // average correctly and adjacent tiles connect instead of seaming.
                uint32 accR = 0, accG = 0, accB = 0, accA = 0;
                int samples = 0;
                for(int sy = sy0; sy < sy1; ++sy) {
                    const uint8* row = srcBase + ((size_t)sy * srcW + sx0) * 4;
                    for(int sx = sx0; sx < sx1; ++sx, row += 4) {
                        accR += (uint32)row[0] * row[3];
                        accG += (uint32)row[1] * row[3];
                        accB += (uint32)row[2] * row[3];
                        accA += row[3];
                        ++samples;
                    }
                }
                if(samples == 0 || accA == 0)
                    continue;

                const uint8 outA = (uint8)(accA / samples);
                if(outA == 0)
                    continue;

                const uint8 outR = (uint8)(accR / accA);
                const uint8 outG = (uint8)(accG / accA);
                const uint8 outB = (uint8)(accB / accA);

                uint8* dst = dstBase + ((size_t)dy * HD_BLOCK_TEXTURE_SIZE + dx) * 4;
                const int inv = 255 - outA;
                dst[0] = (uint8)((outR * outA + dst[0] * inv) / 255);
                dst[1] = (uint8)((outG * outA + dst[1] * inv) / 255);
                dst[2] = (uint8)((outB * outA + dst[2] * inv) / 255);
                dst[3] = (uint8)(outA + (dst[3] * inv) / 255);
            }
        }
    }

    return target;
}

void Minimap::collectHDResults()
{
    std::vector<HDRenderResult> results;
    {
        std::lock_guard<std::mutex> lock(m_hdResultLock);
        results.swap(m_hdResults);
    }

    if(results.empty())
        return;

    const uint32 generation = m_hdGeneration.load(std::memory_order_acquire);
    std::lock_guard<std::mutex> lock(m_lock);

    for(HDRenderResult& result : results) {
        m_hdPendingImageBytes.fetch_sub(HD_BLOCK_TEXTURE_BYTES, std::memory_order_release);

        // Retire the in-flight entry first, whatever the outcome, so the block
        // becomes queueable again even if the render was cancelled or rejected.
        for(size_t i = 0; i < m_hdRunning.size(); ++i) {
            if(m_hdRunning[i].blockIndex == result.blockIndex &&
               m_hdRunning[i].z == result.z &&
               m_hdRunning[i].revision == result.revision) {
                m_hdRunning.erase(m_hdRunning.begin() + i);
                break;
            }
        }

        if(!result.image || result.generation != generation) {
            m_hdStaleDropped.fetch_add(1, std::memory_order_relaxed);
            continue;   // the image dies here; nothing live is touched
        }

        if(result.z >= m_tileBlocks.size())
            continue;

        auto& blocks = m_tileBlocks[result.z];
        auto it = blocks.find(result.blockIndex);
        if(it == blocks.end() || !it->second)
            continue;

        HDBlockData* hd = it->second->getHDData();
        if(!hd)
            continue;   // HD data dropped while the job ran

        const bool wasResident = hd->hasTexture();

        // Constructing a Texture performs no GL call: it only holds the image
        // until the main thread uploads it in Texture::update(). Marked
        // non-cacheable so these 512x512 blocks never enter g_atlas, which is
        // shared with the game view.
        TexturePtr texture = std::make_shared<Texture>(result.image);
        texture->setSmooth(true);
        texture->setCanCache(false);

        hd->setTexture(texture, result.revision);

        if(!wasResident) {
            m_hdTextureBytes += HD_BLOCK_TEXTURE_BYTES;
            m_hdResident.emplace_back(result.z, result.blockIndex);
        }
    }
}

void Minimap::dropHDTextureAt(uint8 z, uint blockIndex)
{
    if(z >= m_tileBlocks.size())
        return;

    auto& blocks = m_tileBlocks[z];
    auto it = blocks.find(blockIndex);
    if(it == blocks.end() || !it->second)
        return;

    if(HDBlockData* hd = it->second->getHDData()) {
        if(hd->hasTexture()) {
            hd->dropTexture();
            if(m_hdTextureBytes >= HD_BLOCK_TEXTURE_BYTES)
                m_hdTextureBytes -= HD_BLOCK_TEXTURE_BYTES;
            ++m_hdEvictions;
        }
    }
}

void Minimap::enforceHDTextureBudget(const Position& mapCenter, const Rect& visibleBlocks)
{
    std::lock_guard<std::mutex> lock(m_lock);

    // Forget entries whose texture is already gone before deciding anything.
    m_hdResident.erase(std::remove_if(m_hdResident.begin(), m_hdResident.end(),
        [this](const std::pair<uint8, uint>& entry) {
            if(entry.first >= m_tileBlocks.size())
                return true;
            auto& blocks = m_tileBlocks[entry.first];
            auto it = blocks.find(entry.second);
            if(it == blocks.end() || !it->second)
                return true;
            const HDBlockData* hd = it->second->getHDData();
            return !hd || !hd->hasTexture();
        }), m_hdResident.end());

    if(m_hdTextureBytes <= HD_TEXTURE_BUDGET_BYTES)
        return;

    const int centerBlockX = mapCenter.x / MMBLOCK_SIZE;
    const int centerBlockY = mapCenter.y / MMBLOCK_SIZE;

    // Protected set: the visible blocks plus one ring of prefetch. Deliberately
    // nothing else — the active floor gets no special treatment, which is exactly
    // where the previous implementation accumulated without bound.
    const Rect protectedBlocks(visibleBlocks.x() - HD_PROTECT_MARGIN_BLOCKS,
                               visibleBlocks.y() - HD_PROTECT_MARGIN_BLOCKS,
                               visibleBlocks.width() + 2 * HD_PROTECT_MARGIN_BLOCKS,
                               visibleBlocks.height() + 2 * HD_PROTECT_MARGIN_BLOCKS);

    struct Candidate { size_t residentIdx; int64_t score; };
    std::vector<Candidate> candidates;
    candidates.reserve(m_hdResident.size());

    for(size_t i = 0; i < m_hdResident.size(); ++i) {
        const uint8 z = m_hdResident[i].first;
        const uint blockIndex = m_hdResident[i].second;
        const Position blockPos = getIndexPosition(blockIndex, z);
        const int bx = blockPos.x / MMBLOCK_SIZE;
        const int by = blockPos.y / MMBLOCK_SIZE;

        const bool sameFloor = (z == mapCenter.z);
        if(sameFloor && protectedBlocks.contains(Point(bx, by)))
            continue;

        // Higher score evicts first: other floors go before the current one, then
        // distance from the viewport centre, then least recently used.
        int64_t score = 0;
        if(!sameFloor)
            score += 1000000;
        score += (int64_t)(std::abs(bx - centerBlockX) + std::abs(by - centerBlockY)) * 100;

        // find(), never operator[]: the latter would insert phantom null blocks.
        auto blockIt = m_tileBlocks[z].find(blockIndex);
        if(blockIt != m_tileBlocks[z].end() && blockIt->second) {
            if(const HDBlockData* hd = blockIt->second->getHDData())
                score += (int64_t)std::min<ticks_t>(stdext::millis() - hd->getLastUsed(), 60000) / 1000;
        }

        candidates.push_back({ i, score });
    }

    std::sort(candidates.begin(), candidates.end(),
        [](const Candidate& a, const Candidate& b) { return a.score > b.score; });

    std::vector<size_t> evicted;
    for(const Candidate& candidate : candidates) {
        if(m_hdTextureBytes <= HD_TEXTURE_BUDGET_BYTES)
            break;
        const auto& entry = m_hdResident[candidate.residentIdx];
        dropHDTextureAt(entry.first, entry.second);
        evicted.push_back(candidate.residentIdx);
    }

    if(!evicted.empty()) {
        std::sort(evicted.begin(), evicted.end(), std::greater<size_t>());
        for(size_t idx : evicted)
            m_hdResident.erase(m_hdResident.begin() + idx);
    }
}

Point Minimap::getTilePoint(const Position& pos, const Rect& screenRect, const Position& mapCenter, float scale)
{
    if(screenRect.isEmpty() || pos.z != mapCenter.z)
        return Point(-1,-1);

    Rect mapRect = calcMapRect(screenRect, mapCenter, scale);
    Point off = Point((mapRect.size() * scale).toPoint() - screenRect.size().toPoint())/2;
    Point posoff = (Point(pos.x,pos.y) - mapRect.topLeft())*scale;
    return posoff + screenRect.topLeft() - off + (Point(1,1)*scale)/2;
}

Position Minimap::getTilePosition(const Point& point, const Rect& screenRect, const Position& mapCenter, float scale)
{
    if(screenRect.isEmpty())
        return Position();

    Rect mapRect = calcMapRect(screenRect, mapCenter, scale);
    Point off = Point((mapRect.size() * scale).toPoint() - screenRect.size().toPoint())/2;
    Point pos2d = (point - screenRect.topLeft() + off)/scale + mapRect.topLeft();
    return Position(pos2d.x, pos2d.y, mapCenter.z);
}

Rect Minimap::getTileRect(const Position& pos, const Rect& screenRect, const Position& mapCenter, float scale)
{
    if(screenRect.isEmpty() || pos.z != mapCenter.z)
        return Rect();

    int tileSize = g_sprites.spriteSize() * scale;
    Rect tileRect(0,0,tileSize, tileSize);
    tileRect.moveCenter(getTilePoint(pos, screenRect, mapCenter, scale));
    return tileRect;
}

Rect Minimap::calcMapRect(const Rect& screenRect, const Position& mapCenter, float scale)
{
    int w = screenRect.width() / scale, h = std::ceil(screenRect.height() / scale);
    Rect mapRect(0,0,w,h);
    mapRect.moveCenter(Point(mapCenter.x, mapCenter.y));
    return mapRect;
}

void Minimap::updateTile(const Position& pos, const TilePtr& tile)
{
    MinimapTile minimapTile;
    if(tile) {
        minimapTile.color = tile->getMinimapColorByte();
        minimapTile.flags |= MinimapTileWasSeen;
        if(!tile->isWalkable(true))
            minimapTile.flags |= MinimapTileNotWalkable;
        if(!tile->isPathable())
            minimapTile.flags |= MinimapTileNotPathable;
        minimapTile.speed = std::min<int>((int)std::ceil(tile->getGroundSpeed() / 10.0f), 255);
    } else {
        minimapTile.color = 255;
        minimapTile.flags |= MinimapTileEmpty;
        minimapTile.speed = 1;
    }

    if(minimapTile != MinimapTile()) {
        MinimapBlock& block = getBlock(pos);
        Point offsetPos = getBlockOffset(Point(pos.x, pos.y));
        block.updateTile(pos.x - offsetPos.x, pos.y - offsetPos.y, minimapTile);
        block.justSaw();

        // The whole cost of HD mode being off is this relaxed load. Nothing is
        // collected, allocated or hashed unless HD is actually on.
        if(m_hdMode.load(std::memory_order_relaxed))
            collectHDTile(pos, tile);
    }
}

void Minimap::collectHDTile(const Position& pos, const TilePtr& tile)
{
    // Reused across calls, so after warm-up this collects a tile without any
    // allocation. Safe as a member because updateTile only runs on the dispatcher
    // thread.
    std::vector<HDMinimapItem>& items = m_hdScratch;
    items.clear();

    if(tile) {
        for(const ThingPtr& thing : tile->getThingsRef()) {
            if(!thing || !thing->isItem())
                continue;

            const ItemPtr& item = thing->static_self_cast<Item>();
            HDMinimapItem entry;
            entry.id = (uint16)item->getId();
            if(item->isSplash() || item->isFluidContainer())
                entry.subtype = (uint16)item->getSubType();

            items.push_back(entry);
        }
    }

    const Point offsetPos = getBlockOffset(Point(pos.x, pos.y));
    const uint16 tileIndex = (uint16)(((pos.y - offsetPos.y) * MMBLOCK_SIZE) + (pos.x - offsetPos.x));

    std::lock_guard<std::mutex> lock(m_lock);

    if(pos.z >= m_tileBlocks.size())
        return;

    auto& blocks = m_tileBlocks[pos.z];
    auto it = blocks.find(getBlockIndex(pos));
    if(it == blocks.end() || !it->second)
        return;

    MinimapBlock& block = *it->second;

    // Never allocate an HD payload just to store "this tile is empty".
    if(items.empty() && !block.getHDData())
        return;

    HDBlockData& hd = block.getOrCreateHDData();
    const size_t before = hd.getByteSize();
    if(hd.setTileItems(tileIndex, items.data(), (uint16)items.size())) {
        // The player has changed this block, so it can no longer be restored by
        // re-reading the baseline archive: it stays resident even after a save.
        hd.setFromBaseline(false);
    }
    m_hdDataBytes += hd.getByteSize() - before;

    // A payload that emptied out is released instead of lingering as an 8 KiB
    // slot table.
    if(hd.isEmpty()) {
        m_hdDataBytes -= hd.getByteSize();
        block.dropHDData();
    }
}

void Minimap::setHDMode(bool enabled)
{
    if(m_hdMode.load(std::memory_order_relaxed) == enabled)
        return;

    std::lock_guard<std::mutex> lock(m_lock);
    m_hdMode.store(enabled, std::memory_order_relaxed);

    // Leaving HD mode returns every HD byte. Entering it starts from nothing, so
    // the next draw runs a one-shot bootstrap over the tiles g_map already holds
    // instead of making the player walk to reveal their own surroundings.
    if(!enabled) {
        m_hdBootstrapPending = false;
        invalidateHDLocked();
    } else {
        m_hdGeneration.fetch_add(1, std::memory_order_release);
        m_hdBootstrapPending = true;
    }
}

void Minimap::invalidateHDLocked()
{
    // Bumping first means any worker that finishes from here on discards its
    // result instead of writing into state we are about to reset.
    m_hdGeneration.fetch_add(1, std::memory_order_release);

    for(auto& blocks : m_tileBlocks) {
        for(auto& pair : blocks) {
            if(pair.second)
                pair.second->dropHDData();   // releases payload and texture together
        }
    }

    m_hdDataBytes = 0;
    m_hdTextureBytes = 0;
    m_hdResident.clear();
    m_hdResident.shrink_to_fit();
    m_hdQueue.clear();
    m_hdQueue.shrink_to_fit();
    // Jobs still executing will post results that the generation check rejects.
    m_hdRunning.clear();
    m_hdRunning.shrink_to_fit();

    // Images already produced are dropped; their reservation is released with them.
    {
        std::lock_guard<std::mutex> lock(m_hdResultLock);
        for(size_t i = 0; i < m_hdResults.size(); ++i)
            m_hdPendingImageBytes.fetch_sub(HD_BLOCK_TEXTURE_BYTES, std::memory_order_release);
        m_hdResults.clear();
    }
}

namespace {

// "/minimap/foo_hd.otmm" + z=7 -> "/minimap/foo_hd_floor7.otmm"
std::string hdFloorFileName(const std::string& baseName, int z)
{
    std::string stem = baseName;
    const std::string ext = ".otmm";
    if(stem.size() > ext.size() && stem.compare(stem.size() - ext.size(), ext.size(), ext) == 0)
        stem.resize(stem.size() - ext.size());
    return stem + "_floor" + std::to_string(z) + ext;
}

} // namespace

bool Minimap::generateHDFromOtbm(const std::string& otbmFile, const std::string& outputFile)
{
    // Offline tool, not a gameplay path. It still streams rather than loading the
    // world: OTBM tile areas are 256x256 and always aligned, so each one maps onto
    // exactly 16 whole 64x64 blocks with no sharing. That lets every area be
    // encoded and flushed immediately, keeping peak memory at roughly one area
    // instead of one floor, let alone the whole map.
    if(!g_things.isOtbLoaded()) {
        g_logger.error("HD baseline needs items.otb loaded to map server ids to client ids");
        return false;
    }

    try {
        FileStreamPtr fin = g_resources.openFile(otbmFile, true);
        if(!fin)
            stdext::throw_exception("unable to open otbm");

        const std::string tmpFile = outputFile + ".tmp";
        FileStreamPtr fout = g_resources.createFile(tmpFile);
        if(!fout)
            stdext::throw_exception("unable to create output file");

        fout->addU32(OTMM_HD_BASE_SIGNATURE);
        fout->addU16(OTMM_HD_BASE_VERSION);
        fout->addU32(0);   // flags
        fout->addU32(0);   // index offset, patched at the end
        fout->addU32(0);   // block count, patched at the end

        struct IndexRecord { uint16 bx, by; uint8 z; HDBaseEntry entry; };
        std::vector<IndexRecord> index;

        // Header layout mirrors Map::loadOtbm exactly.
        char identifier[4];
        if(fin->read(identifier, 1, 4) < 4)
            stdext::throw_exception("could not read otbm identifier");
        if(memcmp(identifier, "OTBM", 4) != 0 && memcmp(identifier, "\0\0\0\0", 4) != 0)
            stdext::throw_exception("invalid otbm identifier");

        BinaryTreePtr root = fin->getBinaryTree();
        if(root->getU8())
            stdext::throw_exception("could not read otbm root property");

        const uint32 headerVersion = root->getU32();
        if(headerVersion > 3)
            stdext::throw_exception("unknown otbm version");

        root->getU16();  // map width
        root->getU16();  // map height
        root->getU8();   // otb major
        root->skip(3);
        root->getU32();  // otb minor

        std::vector<uint8> plain;
        std::vector<uint8> compressed;
        uint64 tilesSeen = 0;

        BinaryTreePtr node = root->getChildren().at(0);
        if(node->getU8() != OTBM_MAP_DATA)
            stdext::throw_exception("could not read otbm root data node");

        while(node->canRead()) {
            node->getU8();       // attribute
            node->getString();   // description / spawn file / house file
        }

        {
            for(const BinaryTreePtr& nodeArea : node->getChildren()) {
                if(nodeArea->getU8() != OTBM_TILE_AREA)
                    continue;

                Position basePos;
                basePos.x = nodeArea->getU16();
                basePos.y = nodeArea->getU16();
                basePos.z = nodeArea->getU8();

                // Blocks of this area only. Freed when the area is done.
                std::unordered_map<uint, HDBlockData> areaBlocks;

                for(const BinaryTreePtr& nodeTile : nodeArea->getChildren()) {
                    const uint8 type = nodeTile->getU8();
                    if(type != OTBM_TILE && type != OTBM_HOUSETILE)
                        continue;

                    const Position pos = basePos + nodeTile->getPoint();
                    if(type == OTBM_HOUSETILE)
                        nodeTile->getU32();   // house id

                    std::vector<HDMinimapItem> items;

                    auto addItem = [&](uint16 serverId) {
                        if(serverId == 0 || !g_things.isValidOtbId(serverId))
                            return;
                        const uint16 clientId = g_things.getItemType(serverId)->getClientId();
                        if(clientId == 0 || !g_things.isValidDatId(clientId, ThingCategoryItem))
                            return;
                        if(items.size() >= HD_MAX_ITEMS_PER_TILE)
                            return;
                        HDMinimapItem entry;
                        entry.id = clientId;
                        items.push_back(entry);
                    };

                    // Inline tile attributes. Unknown ones stop the inline scan
                    // instead of aborting the whole generation: losing one ground
                    // item is better than failing on a map variant.
                    bool inlineOk = true;
                    while(inlineOk && nodeTile->canRead()) {
                        switch(nodeTile->getU8()) {
                            case OTBM_ATTR_TILE_FLAGS: nodeTile->getU32(); break;
                            case OTBM_ATTR_ITEM:       addItem(nodeTile->getU16()); break;
                            default:                   inlineOk = false; break;
                        }
                    }

                    // Item nodes. Each is its own subtree, so the id is all we read
                    // and the tree structure skips the rest, including containers.
                    for(const BinaryTreePtr& nodeItem : nodeTile->getChildren()) {
                        if(nodeItem->getU8() != OTBM_ITEM)
                            continue;
                        addItem(nodeItem->getU16());
                    }

                    if(items.empty())
                        continue;

                    ++tilesSeen;
                    const uint blockIndex = getBlockIndex(pos);
                    const Point blockOffset = getBlockOffset(Point(pos.x, pos.y));
                    const uint16 tileIndex =
                        (uint16)(((pos.y - blockOffset.y) * MMBLOCK_SIZE) + (pos.x - blockOffset.x));

                    areaBlocks[blockIndex].setTileItems(tileIndex, items.data(), (uint16)items.size());
                }

                // Encode and flush this area's blocks straight away.
                for(auto& pair : areaBlocks) {
                    HDBlockData& hd = pair.second;
                    if(hd.isEmpty())
                        continue;

                    plain.clear();
                    const std::vector<HDMinimapItem>& pool = hd.getItemPool();
                    for(const HDTileRecord& record : hd.getRecords()) {
                        const size_t at = plain.size();
                        plain.resize(at + 4 + (size_t)record.count * 4);
                        uint8* out = plain.data() + at;
                        stdext::writeULE16(out,     record.tileIndex);
                        stdext::writeULE16(out + 2, record.count);
                        out += 4;
                        for(uint16 i = 0; i < record.count; ++i) {
                            stdext::writeULE16(out,     pool[record.offset + i].id);
                            stdext::writeULE16(out + 2, pool[record.offset + i].subtype);
                            out += 4;
                        }
                    }

                    if(plain.empty())
                        continue;

                    ulong bound = compressBound((ulong)plain.size());
                    if(compressed.size() < bound)
                        compressed.resize(bound);

                    ulong compressedLen = bound;
                    if(compress2(compressed.data(), &compressedLen,
                                 plain.data(), (ulong)plain.size(), 6) != Z_OK)
                        continue;

                    IndexRecord record;
                    record.bx = (uint16)(basePos.x / MMBLOCK_SIZE);   // patched below
                    record.by = (uint16)(basePos.y / MMBLOCK_SIZE);
                    record.z = (uint8)basePos.z;
                    record.entry.offset = fout->tell();
                    record.entry.compressedSize = (uint32)compressedLen;
                    record.entry.plainSize = (uint32)plain.size();

                    // Recover the block's own coordinates from its index.
                    const Position blockPos = getIndexPosition(pair.first, basePos.z);
                    record.bx = (uint16)(blockPos.x / MMBLOCK_SIZE);
                    record.by = (uint16)(blockPos.y / MMBLOCK_SIZE);

                    fout->write(compressed.data(), (uint)compressedLen);
                    index.push_back(record);
                }
            }
        }

        // Index goes last so the data section can be written in one forward pass.
        const uint32 indexOffset = fout->tell();
        for(const IndexRecord& record : index) {
            fout->addU16(record.bx);
            fout->addU16(record.by);
            fout->addU8(record.z);
            fout->addU32(record.entry.offset);
            fout->addU32(record.entry.compressedSize);
            fout->addU32(record.entry.plainSize);
        }

        fout->seek(10);
        fout->addU32(indexOffset);
        fout->addU32((uint32)index.size());

        fout->flush();
        fout->close();

        std::filesystem::path finalPath(g_resources.getWriteDir());
        std::filesystem::path tmpPath(g_resources.getWriteDir());
        finalPath += outputFile;
        tmpPath += tmpFile;
        std::error_code ec;
        std::filesystem::rename(tmpPath, finalPath, ec);
        if(ec) {
            std::filesystem::remove(tmpPath, ec);
            stdext::throw_exception("unable to replace output file");
        }

        g_logger.info(stdext::format("HD baseline written: %d blocks, %d tiles",
                                     (int)index.size(), (int)tilesSeen));
        return true;
    } catch(std::exception& e) {
        g_logger.error(stdext::format("failed to generate HD baseline: %s", e.what()));
        return false;
    }
}

bool Minimap::openHDBase(const std::string& fileName)
{
    closeHDBase();

    if(fileName.empty() || !g_resources.fileExists(fileName))
        return false;

    try {
        FileStreamPtr fin = g_resources.openFile(fileName, true);
        if(!fin || fin->size() < 18)
            stdext::throw_exception("HD baseline too small");

        if(fin->getU32() != OTMM_HD_BASE_SIGNATURE)
            stdext::throw_exception("invalid HD baseline signature");
        if(fin->getU16() != OTMM_HD_BASE_VERSION)
            stdext::throw_exception("unsupported HD baseline version");

        fin->getU32();   // flags
        const uint32 indexOffset = fin->getU32();
        const uint32 blockCount = fin->getU32();

        if(blockCount > HD_MAX_BASE_BLOCKS)
            stdext::throw_exception("HD baseline block count out of range");
        if(indexOffset < 18 || indexOffset > fin->size())
            stdext::throw_exception("HD baseline index offset out of range");
        if((uint64)blockCount * 17ull > (uint64)(fin->size() - indexOffset))
            stdext::throw_exception("HD baseline index truncated");

        const int maxZ = (int)m_tileBlocks.size() - 1;
        m_hdBaseIndex.assign(maxZ + 1, {});

        fin->seek(indexOffset);
        uint32 accepted = 0;
        for(uint32 i = 0; i < blockCount; ++i) {
            const uint16 bx = fin->getU16();
            const uint16 by = fin->getU16();
            const uint8 z = fin->getU8();
            HDBaseEntry entry;
            entry.offset = fin->getU32();
            entry.compressedSize = fin->getU32();
            entry.plainSize = fin->getU32();

            if(z > maxZ)
                continue;
            if(entry.compressedSize == 0 || entry.compressedSize > HD_MAX_COMPRESSED_BYTES ||
               entry.plainSize == 0 || entry.plainSize > HD_MAX_UNCOMPRESSED_BYTES ||
               entry.plainSize % 4 != 0 ||
               entry.offset < 18 || entry.offset > indexOffset ||
               entry.compressedSize > indexOffset - entry.offset)
                continue;   // reject the entry, keep the archive usable

            const Position blockPos((int)bx * MMBLOCK_SIZE, (int)by * MMBLOCK_SIZE, z);
            m_hdBaseIndex[z][getBlockIndex(blockPos)] = entry;
            ++accepted;
        }

        m_hdBaseFile = fin;
        m_hdBaseFileName = fileName;
        g_logger.info(stdext::format("HD baseline attached: %d blocks", (int)accepted));
        return accepted > 0;
    } catch(std::exception& e) {
        g_logger.error(stdext::format("failed to open HD baseline: %s", e.what()));
        closeHDBase();
        return false;
    }
}

void Minimap::closeHDBase()
{
    m_hdBaseFile = nullptr;
    m_hdBaseFileName.clear();
    m_hdBaseIndex.clear();
}

bool Minimap::loadHDBaseBlockLocked(uint8 z, uint blockIndex, const Position& blockPos)
{
    if(!m_hdBaseFile || z >= m_hdBaseIndex.size())
        return false;

    auto entryIt = m_hdBaseIndex[z].find(blockIndex);
    if(entryIt == m_hdBaseIndex[z].end())
        return false;

    const HDBaseEntry entry = entryIt->second;

    try {
        std::vector<uint8> compressed(entry.compressedSize);
        m_hdBaseFile->seek(entry.offset);
        if(m_hdBaseFile->read(compressed.data(), 1, entry.compressedSize) != (int)entry.compressedSize)
            stdext::throw_exception("truncated baseline block");

        std::vector<uint8> plain(entry.plainSize);
        ulong destLen = entry.plainSize;
        if(uncompress(plain.data(), &destLen, compressed.data(), entry.compressedSize) != Z_OK ||
           destLen != entry.plainSize)
            stdext::throw_exception("corrupt baseline block");

        auto& ptr = m_tileBlocks[z][blockIndex];
        if(!ptr)
            ptr = std::make_shared<MinimapBlock>();

        HDBlockData& hd = ptr->getOrCreateHDData();
        const size_t bytesBefore = hd.getByteSize();
        std::vector<HDMinimapItem> items;

        size_t at = 0;
        while(at + 4 <= plain.size()) {
            const uint16 tileIndex = stdext::readULE16(plain.data() + at);
            const uint16 itemCount = stdext::readULE16(plain.data() + at + 2);
            at += 4;

            if(tileIndex >= HD_MAX_TILES_PER_BLOCK ||
               itemCount == 0 || itemCount > HD_MAX_ITEMS_PER_TILE ||
               at + (size_t)itemCount * 4 > plain.size())
                stdext::throw_exception("invalid baseline tile record");

            items.clear();
            items.reserve(itemCount);
            for(uint16 i = 0; i < itemCount; ++i) {
                HDMinimapItem item;
                item.id = stdext::readULE16(plain.data() + at);
                item.subtype = stdext::readULE16(plain.data() + at + 2);
                at += 4;
                items.push_back(item);
            }

            hd.setTileItems(tileIndex, items.data(), itemCount);
        }

        // Baseline content matches the archive, so it is not player data and may be
        // evicted and re-read freely.
        hd.setSavedRevision(hd.getContentRevision());
        hd.setFromBaseline(true);
        m_hdDataBytes += hd.getByteSize() - bytesBefore;
        ++m_hdBaseLoads;
        return true;
    } catch(std::exception& e) {
        // Drop this entry so a bad block is not retried every frame.
        m_hdBaseIndex[z].erase(blockIndex);
        g_logger.error(stdext::format("HD baseline block %d/%d failed: %s",
                                      (int)z, (int)blockIndex, e.what()));
        return false;
    }
}

void Minimap::saveOtmmHD(const std::string& fileName)
{
    if(fileName.empty())
        return;

    // Coalescing instead of waiting: a request arriving while a save runs simply
    // replaces the pending one. The main thread never sleeps or polls on I/O.
    if(m_hdSaving.exchange(true, std::memory_order_acq_rel)) {
        m_hdSavePending = true;
        m_hdSavePendingFile = fileName;
        return;
    }

    const uint32 generation = m_hdGeneration.load(std::memory_order_acquire);

    g_asyncDispatcher.dispatch([this, fileName, generation] {
        try {
            g_resources.makeDir("minimap");

            const int maxZ = (int)m_tileBlocks.size() - 1;
            for(int z = 0; z <= maxZ; ++z) {
                if(generation != m_hdGeneration.load(std::memory_order_acquire))
                    break;   // HD was reset under us; the file on disk stays as it was

                // Decide whether this floor needs rewriting, and grab its block
                // list, holding the lock only for that.
                std::vector<uint> blockIndices;
                bool floorDirty = false;
                {
                    std::lock_guard<std::mutex> lock(m_lock);
                    if(z >= (int)m_tileBlocks.size())
                        break;
                    for(auto& pair : m_tileBlocks[z]) {
                        if(!pair.second)
                            continue;
                        const HDBlockData* hd = pair.second->getHDData();
                        if(!hd || hd->isEmpty())
                            continue;
                        blockIndices.push_back(pair.first);
                        if(hd->isDirty())
                            floorDirty = true;
                    }
                }

                if(!floorDirty || blockIndices.empty())
                    continue;

                const std::string floorFile = hdFloorFileName(fileName, z);
                const std::string tmpFile = floorFile + ".tmp";

                FileStreamPtr fin = g_resources.createFile(tmpFile);
                if(!fin)
                    continue;

                fin->addU32(OTMM_HD_SIGNATURE);
                fin->addU16(0);                  // data start, patched below
                fin->addU16(OTMM_HD_VERSION);
                fin->addU32(0);                  // flags
                fin->addString("OTMM HD 2.0");

                const uint32 dataStart = fin->tell();
                fin->seek(4);
                fin->addU16(dataStart);
                fin->seek(dataStart);

                // Scratch buffers reused across every block: peak memory for the
                // whole save is one block, not the whole structure.
                std::vector<uint8> plain;
                std::vector<uint8> compressed;
                std::vector<std::pair<uint, uint32>> written;   // blockIndex, revision

                for(uint blockIndex : blockIndices) {
                    if(generation != m_hdGeneration.load(std::memory_order_acquire))
                        break;

                    uint32 revision = 0;
                    plain.clear();

                    // Serialise straight out of the packed pool while holding the
                    // lock for this one block only.
                    {
                        std::lock_guard<std::mutex> lock(m_lock);
                        if(z >= (int)m_tileBlocks.size())
                            break;
                        auto it = m_tileBlocks[z].find(blockIndex);
                        if(it == m_tileBlocks[z].end() || !it->second)
                            continue;
                        const HDBlockData* hd = it->second->getHDData();
                        if(!hd || hd->isEmpty())
                            continue;

                        revision = hd->getContentRevision();
                        const std::vector<HDMinimapItem>& pool = hd->getItemPool();

                        for(const HDTileRecord& record : hd->getRecords()) {
                            if(record.count == 0 || record.count > HD_MAX_ITEMS_PER_TILE)
                                continue;
                            const size_t at = plain.size();
                            plain.resize(at + 4 + (size_t)record.count * 4);
                            uint8* out = plain.data() + at;
                            stdext::writeULE16(out,     record.tileIndex);
                            stdext::writeULE16(out + 2, record.count);
                            out += 4;
                            for(uint16 i = 0; i < record.count; ++i) {
                                stdext::writeULE16(out,     pool[record.offset + i].id);
                                stdext::writeULE16(out + 2, pool[record.offset + i].subtype);
                                out += 4;
                            }
                        }
                    }

                    if(plain.empty())
                        continue;

                    ulong bound = compressBound((ulong)plain.size());
                    if(compressed.size() < bound)
                        compressed.resize(bound);

                    ulong compressedLen = bound;
                    if(compress2(compressed.data(), &compressedLen,
                                 plain.data(), (ulong)plain.size(), 3) != Z_OK)
                        continue;
                    if(compressedLen > 0xFFFFFFFFul || plain.size() > HD_MAX_UNCOMPRESSED_BYTES)
                        continue;

                    const Position blockPos = getIndexPosition(blockIndex, z);
                    fin->addU16(blockPos.x);
                    fin->addU16(blockPos.y);
                    fin->addU8((uint8)z);
                    fin->addU32((uint32)plain.size());
                    fin->addU32((uint32)compressedLen);
                    fin->write(compressed.data(), compressedLen);

                    written.emplace_back(blockIndex, revision);
                }

                // Terminator, mirroring the base OTMM format.
                Position invalidPos;
                fin->addU16(invalidPos.x);
                fin->addU16(invalidPos.y);
                fin->addU8(invalidPos.z);

                fin->flush();
                fin->close();

                // Atomic replace so a crash mid-write cannot leave a half file.
                std::filesystem::path finalPath(g_resources.getWriteDir());
                std::filesystem::path tmpPath(g_resources.getWriteDir());
                finalPath += floorFile;
                tmpPath += tmpFile;
                std::error_code ec;
                std::filesystem::rename(tmpPath, finalPath, ec);
                if(ec) {
                    std::filesystem::remove(tmpPath, ec);
                    continue;
                }

                // Only clear the dirty mark for blocks whose revision is still the
                // one we actually wrote.
                {
                    std::lock_guard<std::mutex> lock(m_lock);
                    if(generation != m_hdGeneration.load(std::memory_order_acquire))
                        break;
                    if(z >= (int)m_tileBlocks.size())
                        break;
                    for(const auto& entry : written) {
                        auto it = m_tileBlocks[z].find(entry.first);
                        if(it == m_tileBlocks[z].end() || !it->second)
                            continue;
                        if(HDBlockData* hd = it->second->getHDData()) {
                            if(hd->getContentRevision() == entry.second)
                                hd->setSavedRevision(entry.second);
                        }
                    }
                }
            }
        } catch(std::exception& e) {
            g_logger.error(stdext::format("failed to save HD minimap: %s", e.what()));
        }

        m_hdSaving.store(false, std::memory_order_release);

        // Run the coalesced request, if one arrived while we were writing.
        g_dispatcher.addEvent([this] {
            if(m_hdSavePending) {
                m_hdSavePending = false;
                const std::string pending = m_hdSavePendingFile;
                m_hdSavePendingFile.clear();
                saveOtmmHD(pending);
            }
        });
    });
}

bool Minimap::loadOtmmHD(const std::string& fileName)
{
    if(fileName.empty())
        return false;

    bool loadedAny = false;
    const int maxZ = (int)m_tileBlocks.size() - 1;

    for(int z = 0; z <= maxZ; ++z) {
        const std::string floorFile = hdFloorFileName(fileName, z);
        if(!g_resources.fileExists(floorFile))
            continue;

        try {
            FileStreamPtr fin = g_resources.openFile(floorFile, g_game.getFeature(Otc::GameDontCacheFiles));
            if(!fin)
                continue;

            // Nothing read below is trusted before being range-checked.
            if(fin->size() < 12)
                stdext::throw_exception("HD minimap file too small");

            if(fin->getU32() != OTMM_HD_SIGNATURE)
                stdext::throw_exception("invalid HD minimap signature");

            const uint16 dataStart = fin->getU16();
            const uint16 version = fin->getU16();
            fin->getU32();   // flags

            if(version != OTMM_HD_VERSION)
                stdext::throw_exception("unsupported HD minimap version");
            if(dataStart < 12 || dataStart > fin->size())
                stdext::throw_exception("invalid HD minimap data offset");

            fin->getString();   // description
            fin->seek(dataStart);

            std::vector<uint8> compressed;
            std::vector<uint8> plain;
            uint32 blocksRead = 0;

            while(true) {
                if(fin->tell() + 5 > fin->size())
                    stdext::throw_exception("truncated HD minimap block header");

                Position pos;
                pos.x = fin->getU16();
                pos.y = fin->getU16();
                pos.z = fin->getU8();

                if(!pos.isValid())
                    break;   // terminator

                if(pos.z != z || pos.z > maxZ)
                    stdext::throw_exception("HD minimap block on the wrong floor");
                if(++blocksRead > HD_MAX_BLOCKS_PER_FLOOR)
                    stdext::throw_exception("too many HD minimap blocks");

                if(fin->tell() + 8 > fin->size())
                    stdext::throw_exception("truncated HD minimap block sizes");

                const uint32 plainSize = fin->getU32();
                const uint32 compressedSize = fin->getU32();

                if(plainSize == 0 || compressedSize == 0 ||
                   plainSize > HD_MAX_UNCOMPRESSED_BYTES ||
                   compressedSize > HD_MAX_COMPRESSED_BYTES ||
                   plainSize % 4 != 0 ||
                   fin->tell() + compressedSize > fin->size())
                    stdext::throw_exception("invalid HD minimap block sizes");

                compressed.resize(compressedSize);
                if(fin->read(compressed.data(), 1, compressedSize) != (int)compressedSize)
                    stdext::throw_exception("truncated HD minimap payload");

                plain.resize(plainSize);
                ulong destLen = plainSize;
                if(uncompress(plain.data(), &destLen, compressed.data(), compressedSize) != Z_OK ||
                   destLen != plainSize)
                    stdext::throw_exception("corrupt HD minimap payload");

                // Decode into the block, validating every count against what is
                // actually left in the buffer.
                std::lock_guard<std::mutex> lock(m_lock);
                auto& ptr = m_tileBlocks[z][getBlockIndex(pos)];
                if(!ptr)
                    ptr = std::make_shared<MinimapBlock>();

                HDBlockData& hd = ptr->getOrCreateHDData();
                const size_t bytesBefore = hd.getByteSize();
                std::vector<HDMinimapItem> items;

                size_t at = 0;
                while(at + 4 <= plain.size()) {
                    const uint16 tileIndex = stdext::readULE16(plain.data() + at);
                    const uint16 itemCount = stdext::readULE16(plain.data() + at + 2);
                    at += 4;

                    if(tileIndex >= HD_MAX_TILES_PER_BLOCK ||
                       itemCount == 0 || itemCount > HD_MAX_ITEMS_PER_TILE ||
                       at + (size_t)itemCount * 4 > plain.size())
                        stdext::throw_exception("invalid HD minimap tile record");

                    items.clear();
                    items.reserve(itemCount);
                    for(uint16 i = 0; i < itemCount; ++i) {
                        HDMinimapItem entry;
                        entry.id = stdext::readULE16(plain.data() + at);
                        entry.subtype = stdext::readULE16(plain.data() + at + 2);
                        at += 4;
                        items.push_back(entry);
                    }

                    hd.setTileItems(tileIndex, items.data(), itemCount);
                }

                // Loaded content matches what is on disk, so it is not dirty.
                hd.setSavedRevision(hd.getContentRevision());
                ptr->justSaw();
                m_hdDataBytes += hd.getByteSize() - bytesBefore;
                loadedAny = true;
            }
        } catch(std::exception& e) {
            // A bad floor file is skipped, never fatal: the base minimap and the
            // other floors keep working.
            g_logger.error(stdext::format("failed to load HD minimap floor %d: %s", z, e.what()));
        }
    }

    return loadedAny;
}

std::string Minimap::getHDStats()
{
    std::lock_guard<std::mutex> lock(m_lock);

    size_t blocksWithData = 0;
    size_t tilesWithData = 0;
    size_t itemCount = 0;
    size_t dataBytes = 0;
    size_t dirtyBlocks = 0;

    for(auto& blocks : m_tileBlocks) {
        for(auto& pair : blocks) {
            if(!pair.second)
                continue;
            if(const HDBlockData* hd = pair.second->getHDData()) {
                ++blocksWithData;
                tilesWithData += hd->getTileCount();
                itemCount += hd->getItemPool().size();
                dataBytes += hd->getByteSize();
                if(hd->isDirty())
                    ++dirtyBlocks;
            }
        }
    }

    size_t baseIndexed = 0;
    for(const auto& floorIndex : m_hdBaseIndex)
        baseIndexed += floorIndex.size();

    const size_t pendingBytes = m_hdPendingImageBytes.load(std::memory_order_acquire);

    std::ostringstream out;
    out << "hdMode=" << (m_hdMode.load(std::memory_order_relaxed) ? 1 : 0)
        << " generation=" << m_hdGeneration.load(std::memory_order_acquire)
        << " texelsPerTile=" << (int)HD_TEXELS_PER_TILE << "\n"
        << "blocksWithData=" << blocksWithData
        << " tilesWithData=" << tilesWithData
        << " items=" << itemCount
        << " dataBytes=" << dataBytes << "\n"
        << "residentTextures=" << m_hdResident.size()
        << " textureBytes=" << m_hdTextureBytes
        << " textureBudget=" << HD_TEXTURE_BUDGET_BYTES << "\n"
        << "pendingImages=" << (pendingBytes / HD_BLOCK_TEXTURE_BYTES)
        << " pendingImageBytes=" << pendingBytes
        << " pendingBudget=" << HD_PENDING_IMAGE_BUDGET_BYTES << "\n"
        << "queuedJobs=" << m_hdQueue.size()
        << " runningJobs=" << m_hdRunningJobs.load(std::memory_order_acquire)
        << " maxWorkers=" << m_hdMaxWorkers << "\n"
        << "cacheHits=" << m_hdCacheHits
        << " cacheMisses=" << m_hdCacheMisses
        << " evictions=" << m_hdEvictions
        << " staleDropped=" << m_hdStaleDropped.load(std::memory_order_relaxed) << "\n"
        << "dirtyBlocks=" << dirtyBlocks
        << " saving=" << (isSavingHD() ? 1 : 0)
        << " savePending=" << (m_hdSavePending ? 1 : 0) << "\n"
        << "baseAttached=" << (m_hdBaseFile ? 1 : 0)
        << " baseIndexed=" << baseIndexed
        << " baseLoads=" << m_hdBaseLoads
        << " dataBudget=" << HD_DATA_BUDGET_BYTES
        << " dataEvictions=" << m_hdBaseDataEvictions;

    return out.str();
}

const MinimapTile& Minimap::getTile(const Position& pos)
{
    static MinimapTile nulltile;
    if(pos.z <= g_gameConfig.getMapMaxZ()) {
        std::lock_guard<std::mutex> lock(m_lock);
        if(hasBlock(pos)) {
            MinimapBlock_ptr blockPtr = m_tileBlocks[pos.z][getBlockIndex(pos)];
            if(blockPtr) {
                Point offsetPos = getBlockOffset(Point(pos.x, pos.y));
                return blockPtr->getTile(pos.x - offsetPos.x, pos.y - offsetPos.y);
            }
        }
    }
    return nulltile;
}

std::pair<MinimapBlock_ptr, MinimapTile> Minimap::threadGetTile(const Position& pos) {
    std::lock_guard<std::mutex> lock(m_lock);
    static MinimapTile nulltile;
    
    if (pos.z <= g_gameConfig.getMapMaxZ() && hasBlock(pos)) {
        MinimapBlock_ptr block = m_tileBlocks[pos.z][getBlockIndex(pos)];
        if (block) {
            Point offsetPos = getBlockOffset(Point(pos.x, pos.y));
            return std::make_pair(block, block->getTile(pos.x - offsetPos.x, pos.y - offsetPos.y));
        }
    }
    return std::make_pair(nullptr, nulltile);
}

bool Minimap::loadImage(const std::string& fileName, const Position& topLeft, float colorFactor)
{
    if(colorFactor <= 0.01f)
        colorFactor = 1.0f;

    try {
        ImagePtr image = Image::load(fileName);

        uint8 waterc = Color::to8bit(std::string("#3300cc"));

        // non pathable colors
        Color nonPathableColors[] = {
            std::string("#ffff00"), // yellow
        };

        // non walkable colors
        Color nonWalkableColors[] = {
            std::string("#000000"), // oil, black
            std::string("#006600"), // trees, dark green
            std::string("#ff3300"), // walls, red
            std::string("#666666"), // mountain, grey
            std::string("#ff6600"), // lava, orange
            std::string("#00ff00"), // positon
            std::string("#ccffff"), // ice, very light blue
        };

        for(int y=0;y<image->getHeight();++y) {
            for(int x=0;x<image->getWidth();++x) {
                Color color = stdext::readULE32(image->getPixel(x,y));
                uint8 c = Color::to8bit(color * colorFactor);
                int flags = 0;

                if(c == waterc || color.a() == 0) {
                    flags |= MinimapTileNotWalkable;
                    c = 255; // alpha
                }

                if(flags != 0) {
                    for(Color &col : nonWalkableColors) {
                        if(col == color) {
                            flags |= MinimapTileNotWalkable;
                            break;
                        }
                    }
                }

                if(flags != 0) {
                    for(Color &col : nonPathableColors) {
                        if(col == color) {
                            flags |= MinimapTileNotPathable;
                            break;
                        }
                    }
                }

                if(c == 255)
                    continue;

                Position pos(topLeft.x + x, topLeft.y + y, topLeft.z);
                MinimapBlock& block = getBlock(pos);
                Point offsetPos = getBlockOffset(Point(pos.x, pos.y));
                MinimapTile& tile = block.getTile(pos.x - offsetPos.x, pos.y - offsetPos.y);
                if(!(tile.flags & MinimapTileWasSeen)) {
                    tile.color = c;
                    tile.flags = flags;
                    block.mustUpdate();
                }
            }
        }
        return true;
    } catch(stdext::exception& e) {
        g_logger.error(stdext::format("failed to load OTMM minimap: %s", e.what()));
        return false;
    }
}

void Minimap::saveImage(const std::string& fileName, int minX, int minY, int maxX, int maxY, short z)
{
   ImagePtr image(new Image(Size(maxX - minX, maxY - minY)));

   for (int x = minX; x < maxX; x++) {
           for (int y = minY; y < maxY; y++) {
                   uint8 c = getTile(Position(x, y, z)).color;
                   Color col = Color::alpha;
                   if(c != 255) {
                           col = Color::from8bit(c);
                   }
                   col.setAlpha(255);
                   image->setPixel(x - minX, y - minY, col);

           }
   }

   image->savePNG(fileName);
}

bool Minimap::loadOtmm(const std::string& fileName)
{
    try {
        FileStreamPtr fin = g_resources.openFile(fileName, g_game.getFeature(Otc::GameDontCacheFiles));
        if(!fin)
            stdext::throw_exception("unable to open file");

        uint32 signature = fin->getU32();
        if(signature != OTMM_SIGNATURE)
            stdext::throw_exception("invalid OTMM file");

        uint16 start = fin->getU16();
        uint16 version = fin->getU16();
        fin->getU32(); // flags

        switch(version) {
            case 1: {
                fin->getString(); // description
                break;
            }
            default:
                stdext::throw_exception("OTMM version not supported");
        }

        fin->seek(start);

        uint blockSize = MMBLOCK_SIZE * MMBLOCK_SIZE * sizeof(MinimapTile);
        std::vector<uchar> compressBuffer(compressBound(blockSize));
        std::vector<uchar> decompressBuffer(blockSize);

        while(true) {
            Position pos;
            pos.x = fin->getU16();
            pos.y = fin->getU16();
            pos.z = fin->getU8();

            // end of file or file is corrupted
            if(!pos.isValid())
                break;

            ulong len = fin->getU16();
            ulong destLen = blockSize;
            if (len > compressBuffer.size() || fin->read(compressBuffer.data(), 1, len) != len)
                stdext::throw_exception("invalid compressed minimap block");

            // Skip blocks with Z beyond configured limit, but continue processing
            if(pos.z > g_gameConfig.getMapMaxZ())
                continue;

            MinimapBlock& block = getBlock(pos);
            int ret = uncompress(decompressBuffer.data(), &destLen, compressBuffer.data(), len);
            if(ret != Z_OK || destLen != blockSize)
                break;

            memcpy((uchar*)&block.getTiles(), decompressBuffer.data(), blockSize);
            block.mustUpdate();
            block.justSaw();
        }

        fin->close();
        return true;
    } catch(stdext::exception& e) {
        g_logger.error(stdext::format("failed to load OTMM minimap: %s", e.what()));
        return false;
    }
}

void Minimap::saveOtmm(const std::string& fileName)
{
    try {
        stdext::timer saveTimer;

#ifndef ANDROID
        std::string tmpFileName = fileName;
        tmpFileName += ".tmp";
        FileStreamPtr fin = g_resources.createFile(tmpFileName);
#else
        FileStreamPtr fin = g_resources.createFile(fileName);
#endif

        //TODO: compression flag with zlib
        uint32 flags = 0;

        // header
        fin->addU32(OTMM_SIGNATURE);
        fin->addU16(0); // data start, will be overwritten later
        fin->addU16(OTMM_VERSION);
        fin->addU32(flags);

        // version 1 header
        fin->addString("OTMM 1.0"); // description

        // go back and rewrite where the map data starts
        uint32 start = fin->tell();
        fin->seek(4);
        fin->addU16(start);
        fin->seek(start);

        uint blockSize = MMBLOCK_SIZE * MMBLOCK_SIZE * sizeof(MinimapTile);
        std::vector<uchar> compressBuffer(compressBound(blockSize));
        const int COMPRESS_LEVEL = 3;

        for (int z = 0; z <= g_gameConfig.getMapMaxZ(); ++z) {
            for(auto& it : m_tileBlocks[z]) {
                int index = it.first;
                MinimapBlock& block = *it.second;
                if(!block.wasSeen())
                    continue;

                Position pos = getIndexPosition(index, z);
                fin->addU16(pos.x);
                fin->addU16(pos.y);
                fin->addU8(pos.z);

                ulong len = blockSize;
                int ret = compress2(compressBuffer.data(), &len, (uchar*)&block.getTiles(), blockSize, COMPRESS_LEVEL);
                VALIDATE(ret == Z_OK);
                fin->addU16(len);
                fin->write(compressBuffer.data(), len);
            }
        }

        // end of file
        Position invalidPos;
        fin->addU16(invalidPos.x);
        fin->addU16(invalidPos.y);
        fin->addU8(invalidPos.z);

        fin->flush();

        fin->close();
#ifndef ANDROID
        std::filesystem::path filePath(g_resources.getWriteDir()), tmpFilePath(g_resources.getWriteDir());
        filePath += fileName;
        tmpFilePath += tmpFileName;
        if(std::filesystem::file_size(tmpFilePath) > 1024) {
            std::filesystem::rename(tmpFilePath, filePath);
        }
/*
        std::stringstream path;
        path << "exported_minimaps/"<< fileName;
        std::ofstream outfile(path.str(), std::ofstream::binary);
        if (!outfile.is_open() || !outfile.good()) {
            g_logger.error(stdext::format("Unable to save minimap to '%s'", path.str()));
            return;
        }

        std::string data = g_resources.readFileContents(fileName);
        outfile.write(data.c_str(), data.length());
        outfile.close();
*/
#endif
    } catch (stdext::exception& e) {
        g_logger.error(stdext::format("failed to save OTMM minimap: %s", e.what()));
    } catch (std::exception& e) {
        g_logger.error(stdext::format("failed to save OTMM minimap: %s", e.what()));
    }
}
