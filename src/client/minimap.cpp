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
#include <framework/platform/platformwindow.h>
#include <zlib.h>

#include <framework/util/stats.h>
#include <algorithm>
#include <chrono>
#include <climits>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <sstream>
#include <thread>
#include <unordered_map>

#ifdef WIN32
#include <windows.h>
#endif

Minimap g_minimap;

namespace {

// Match the texture resolution to the number of pixels the block occupies on
// screen. Powers of two make zoom transitions stable and prevent a rebuild for
// tiny scale changes. At the farthest zoom a block costs only a few dozen bytes
// instead of the old fixed 4 MiB; across a viewport the total stays close to the
// actual screen-pixel area rather than the number of world blocks.
uint16 chooseHDTextureSize(float scale)
{
    const int blockPixels = std::max(1, (int)std::ceil(MMBLOCK_SIZE * scale));
    const int maxTextureSize = static_cast<int>(HD_CANONICAL_BLOCK_TEXTURE_SIZE);
    const int wanted = std::clamp(blockPixels, 2, maxTextureSize);
    int side = 2;
    while(side < wanted)
        side <<= 1;
    return (uint16)std::min(side, maxTextureSize);
}
int chooseHDBaseLoadsPerFrame(uint16 textureSize)
{
    if(textureSize <= 16) return 32;
    if(textureSize <= 32) return 16;
    if(textureSize <= 64) return 8;
    if(textureSize <= 128) return 4;
    return HD_BASE_LOADS_PER_FRAME;
}

ImagePtr downsampleHDImage(const ImagePtr& source, uint16 side)
{
    if(!source || side == 0 || source->getWidth() != source->getHeight() ||
       source->getWidth() % side != 0)
        return nullptr;
    if(source->getWidth() == side)
        return source;

    const int factor = source->getWidth() / side;
    auto output = std::make_shared<Image>(Size(side, side));
    for(int y = 0; y < side; ++y) {
        for(int x = 0; x < side; ++x) {
            uint64 alpha = 0, red = 0, green = 0, blue = 0;
            for(int sy = 0; sy < factor; ++sy) {
                for(int sx = 0; sx < factor; ++sx) {
                    const uint8* pixel = source->getPixel(x * factor + sx, y * factor + sy);
                    const uint64 a = pixel[3];
                    alpha += a;
                    red += (uint64)pixel[0] * a;
                    green += (uint64)pixel[1] * a;
                    blue += (uint64)pixel[2] * a;
                }
            }

            const uint64 samples = (uint64)factor * factor;
            Color color((uint8)0, (uint8)0, (uint8)0, (uint8)(alpha / samples));
            if(alpha != 0) {
                color.setRed((uint8)(red / alpha));
                color.setGreen((uint8)(green / alpha));
                color.setBlue((uint8)(blue / alpha));
            }
            output->setPixel(x, y, color);
        }
    }
    return output;
}

// Some valid server tiles do not produce a sprite in the offline
// raster (legacy/custom item definitions are the usual cause). Leaving their
// alpha at zero exposes the flat classic minimap underneath as bright squares.
// Complete only tiles known by the authenticated normal minimap, copying the
// nearest already-rendered tile as a visual fallback. The result remains a
// raster photograph: no coordinates or item ids are introduced.
void completeHDRasterImage(const ImagePtr& image, uint16 side,
                           const std::array<uint8, MMBLOCK_SIZE * MMBLOCK_SIZE>& classicColors)
{
    if(!image || side == 0 || side % MMBLOCK_SIZE != 0)
        return;

    const int cell = side / MMBLOCK_SIZE;
    uint8* pixels = image->getPixelData();
    std::array<bool, MMBLOCK_SIZE * MMBLOCK_SIZE> rendered{};
    std::array<int16, MMBLOCK_SIZE * MMBLOCK_SIZE> nearest;
    std::array<std::vector<uint16>, 256> renderedByClassicColor;
    nearest.fill(-1);
    std::vector<uint16> queue;
    queue.reserve(MMBLOCK_SIZE * MMBLOCK_SIZE);

    for(int ty = 0; ty < MMBLOCK_SIZE; ++ty) {
        for(int tx = 0; tx < MMBLOCK_SIZE; ++tx) {
            const int tileIndex = ty * MMBLOCK_SIZE + tx;
            uint64 red = 0, green = 0, blue = 0, alpha = 0;
            for(int py = 0; py < cell; ++py) {
                for(int px = 0; px < cell; ++px) {
                    const uint8* pixel = pixels +
                        ((size_t)(ty * cell + py) * side + tx * cell + px) * 4;
                    const uint64 a = pixel[3];
                    alpha += a;
                    red += (uint64)pixel[0] * a;
                    green += (uint64)pixel[1] * a;
                    blue += (uint64)pixel[2] * a;
                }
            }
            if(alpha == 0)
                continue;

            rendered[tileIndex] = true;
            nearest[tileIndex] = (int16)tileIndex;
            queue.push_back((uint16)tileIndex);
            if(classicColors[tileIndex] != 255)
                renderedByClassicColor[classicColors[tileIndex]].push_back((uint16)tileIndex);

            // A partially transparent sprite must not reveal the colored map
            // beneath it. Composite its gaps over its own representative color.
            const uint8 baseR = (uint8)(red / alpha);
            const uint8 baseG = (uint8)(green / alpha);
            const uint8 baseB = (uint8)(blue / alpha);
            for(int py = 0; py < cell; ++py) {
                for(int px = 0; px < cell; ++px) {
                    uint8* pixel = pixels +
                        ((size_t)(ty * cell + py) * side + tx * cell + px) * 4;
                    const int a = pixel[3];
                    const int inv = 255 - a;
                    pixel[0] = (uint8)((pixel[0] * a + baseR * inv) / 255);
                    pixel[1] = (uint8)((pixel[1] * a + baseG * inv) / 255);
                    pixel[2] = (uint8)((pixel[2] * a + baseB * inv) / 255);
                    pixel[3] = 255;
                }
            }
        }
    }

    // Multi-source flood fill resolves a nearest real raster tile in linear
    // time, so repairing a block stays cheap on the background decoder.
    for(size_t head = 0; head < queue.size(); ++head) {
        const int tileIndex = queue[head];
        const int tx = tileIndex % MMBLOCK_SIZE;
        const int ty = tileIndex / MMBLOCK_SIZE;
        const int neighbours[4] = {
            tx > 0 ? tileIndex - 1 : -1,
            tx + 1 < MMBLOCK_SIZE ? tileIndex + 1 : -1,
            ty > 0 ? tileIndex - MMBLOCK_SIZE : -1,
            ty + 1 < MMBLOCK_SIZE ? tileIndex + MMBLOCK_SIZE : -1
        };
        for(const int neighbour : neighbours) {
            if(neighbour < 0 || nearest[neighbour] >= 0)
                continue;
            nearest[neighbour] = nearest[tileIndex];
            queue.push_back((uint16)neighbour);
        }
    }

    for(int tileIndex = 0; tileIndex < MMBLOCK_SIZE * MMBLOCK_SIZE; ++tileIndex) {
        if(rendered[tileIndex] || classicColors[tileIndex] == 255 || nearest[tileIndex] < 0)
            continue;

        int sourceTile = nearest[tileIndex];
        const int tx = tileIndex % MMBLOCK_SIZE;
        const int ty = tileIndex / MMBLOCK_SIZE;

        // Prefer the nearest rendered tile with the same classic terrain class,
        // even when the matching sample is farther away inside this block. A
        // short radius left large imported regions borrowing an unrelated dark
        // floor texture merely because their valid sample was a few tiles away.
        const uint8 wantedColor = classicColors[tileIndex];
        int bestDistance = INT_MAX;
        for(const uint16 candidate : renderedByClassicColor[wantedColor]) {
            const int sx = candidate % MMBLOCK_SIZE;
            const int sy = candidate / MMBLOCK_SIZE;
            const int distance = std::abs(sx - tx) + std::abs(sy - ty);
            if(distance < bestDistance) {
                bestDistance = distance;
                sourceTile = candidate;
                if(distance == 1)
                    break;
            }
        }

        const int sourceX = (sourceTile % MMBLOCK_SIZE) * cell;
        const int sourceY = (sourceTile / MMBLOCK_SIZE) * cell;
        const int destX = tx * cell;
        const int destY = ty * cell;
        for(int py = 0; py < cell; ++py) {
            for(int px = 0; px < cell; ++px) {
                const uint8* source = pixels +
                    ((size_t)(sourceY + py) * side + sourceX + px) * 4;
                uint8* dest = pixels +
                    ((size_t)(destY + py) * side + destX + px) * 4;
                memcpy(dest, source, 4);
                dest[3] = 255;
            }
        }
    }
}

std::string encodeHDRasterImage(const ImagePtr& image)
{
    if(!image)
        return {};
    const ulong plainSize = (ulong)image->getWidth() * image->getHeight() * image->getBpp();
    ulong compressedSize = compressBound(plainSize);
    std::string compressed(compressedSize, '\0');
    if(compress2(reinterpret_cast<Bytef*>(compressed.data()), &compressedSize,
                 reinterpret_cast<const Bytef*>(image->getPixelData()), plainSize, 3) != Z_OK)
        return {};
    compressed.resize(compressedSize);
    return compressed;
}

}

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
        m_lastContentChange = stdext::millis();
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
        m_lastContentChange = stdext::millis();
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
    m_lastContentChange = stdext::millis();
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

void MinimapBlock::cleanClassic()
{
    m_tiles.fill(MinimapTile());
    m_texture.reset();
    m_mustUpdate = false;
    m_wasSeen = false;
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

    // Sprite snapshots are prepared on the render thread. Dispatching only one
    // composition at a time bounds both the frame cost and pending image memory.
    m_hdMaxWorkers = 1;
}

void Minimap::terminate()
{
    // A final Lua-side save may still be writing. Give it a short, bounded chance
    // to finish before invalidating its generation during process shutdown.
    const auto saveDeadline = std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while(m_hdSaving.load(std::memory_order_acquire) &&
          std::chrono::steady_clock::now() < saveDeadline)
        std::this_thread::sleep_for(std::chrono::milliseconds(10));

    m_hdDisablePending.store(false, std::memory_order_release);
    m_hdSavePending = false;
    m_hdSavePendingFile.clear();
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

    // A map reset is also an HD lifecycle boundary. The old implementation only
    // cleared tile blocks, leaving queued snapshots, result images, resident
    // bookkeeping and the sprite cache alive across reloads/logins.
    invalidateHDLocked();
    for (auto& tileBlocks : m_tileBlocks)
        tileBlocks.clear();
    m_hdBootstrapPending = false;
}

void Minimap::cleanClassic()
{
    std::lock_guard<std::mutex> lock(m_lock);
    for(auto& tileBlocks : m_tileBlocks) {
        for(auto it = tileBlocks.begin(); it != tileBlocks.end();) {
            if(it->second && it->second->getHDData()) {
                it->second->cleanClassic();
                ++it;
            } else {
                it = tileBlocks.erase(it);
            }
        }
    }
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
    if(m_hdMode.load(std::memory_order_relaxed))
        drawHD(screenRect, mapCenter, scale, blockOff, start);

    g_drawQueue->setClip(drawQueueStart, screenRect);
}

void Minimap::drawHD(const Rect& screenRect, const Position& mapCenter, float scale,
                     const Point& blockOff, const Point& start)
{
    if(mapCenter.z >= m_tileBlocks.size())
        return;

    // A raster baseline is already the final visual representation.
    // Do not rebuild it from item ids or mix it with exploration sidecars.
    if(m_hdBaseRaster) {
        drawHDRaster(screenRect, mapCenter, scale, blockOff, start);
        return;
    }

    const ticks_t now = stdext::millis();
    const int blockPixels = (int)(MMBLOCK_SIZE * scale);
    if(blockPixels <= 0)
        return;

    const uint16 textureSize = chooseHDTextureSize(scale);
    const Rect hdSrc(0, 0, textureSize, textureSize);
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
        return;

    const Rect visibleBlocks(minBlockX, minBlockY,
                             maxBlockX - minBlockX + 1, maxBlockY - minBlockY + 1);

    // One-shot fill so switching HD on shows the current surroundings immediately
    // instead of waiting for the player to walk into new updateTile() calls.
    if(m_hdBootstrapPending) {
        m_hdBootstrapPending = false;
        bootstrapHDFromMap(mapCenter, visibleBlocks);
    }

    int baseLoadsLeft = chooseHDBaseLoadsPerFrame(textureSize);

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

                if(hd->hasTextureFor(textureSize)) {
                    g_drawQueue->addTexturedRect(Rect(xs, ys, blockPixels, blockPixels),
                                                hd->getTexture(), hdSrc);
                    if(!hd->needsRender(now, textureSize)) {
                        ++m_hdCacheHits;
                        continue;
                    }
                    // Stale but drawable: keep showing it while the new one builds.
                }
                ++m_hdCacheMisses;

                const int priority = std::abs(bx - centerBlockX) + std::abs(by - centerBlockY);
                queueHDBlock(*it->second, blockPos, blockIndex, priority, textureSize);
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

    // Opt-in runtime audit used by the owner's performance harness. It is inert
    // in distributed clients and avoids a permanent per-frame logging cost.
    static ticks_t nextAudit = 0;
    if(std::getenv("ASTRA_HD_DIAGNOSTICS") && now >= nextAudit) {
        nextAudit = now + 2000;
        g_logger.info(std::string("[HD-AUDIT] ") + getHDStats());
    }

}

uint8 Minimap::chooseHDRasterLod(int blockPixels) const
{
    const int wanted = std::max(1, blockPixels);
    for(uint8 lod = 0; lod < OTMM_HD_RASTER_LOD_COUNT; ++lod) {
        if(HD_RASTER_LOD_SIDES[lod] >= wanted)
            return lod;
    }
    return OTMM_HD_RASTER_LOD_COUNT - 1;
}

void Minimap::requestHDRasterBlock(uint8 z, uint blockIndex, uint8 lod, int priority)
{
    if(!m_hdBaseRaster || !m_hdBaseFile || z >= m_hdRasterIndex.size() ||
       lod >= OTMM_HD_RASTER_LOD_COUNT)
        return;

    auto indexIt = m_hdRasterIndex[z].find(blockIndex);
    if(indexIt == m_hdRasterIndex[z].end())
        return;

    HDRasterTextureCache& cache = m_hdRasterCache[z][blockIndex];
    if(cache.textures[lod] || cache.queued[lod] ||
       stdext::millis() < cache.retryAfter[lod])
        return;

    const HDRasterPayloadEntry payload = indexIt->second.lods[lod];
    if(payload.size == 0 || payload.size > HD_RASTER_MAX_PNG_BYTES)
        return;

    if(m_hdRasterQueue.size() >= HD_RASTER_MAX_QUEUED_JOBS) {
        auto worst = std::max_element(m_hdRasterQueue.begin(), m_hdRasterQueue.end(),
            [](const HDRasterDecodeJob& a, const HDRasterDecodeJob& b) {
                return a.priority < b.priority;
            });
        if(worst == m_hdRasterQueue.end() || worst->priority <= priority)
            return;
        if(worst->z < m_hdRasterCache.size()) {
            auto dropped = m_hdRasterCache[worst->z].find(worst->blockIndex);
            if(dropped != m_hdRasterCache[worst->z].end())
                dropped->second.queued[worst->lod] = false;
        }
        m_hdRasterQueuedBytes -= std::min(m_hdRasterQueuedBytes, worst->png.size());
        m_hdRasterQueue.erase(worst);
    }

    if(m_hdRasterQueuedBytes + payload.size > HD_RASTER_QUEUE_BUDGET_BYTES)
        return;

    try {
        HDRasterDecodeJob job;
        job.blockIndex = blockIndex;
        job.z = z;
        job.lod = lod;
        job.generation = m_hdGeneration.load(std::memory_order_acquire);
        job.priority = priority;
        job.png.resize(payload.size);
        m_hdBaseFile->seek(payload.offset);
        if(m_hdBaseFile->read(job.png.data(), 1, payload.size) != (int)payload.size)
            stdext::throw_exception("truncated raster payload");

        cache.queued[lod] = true;
        m_hdRasterQueuedBytes += job.png.size();
        m_hdRasterQueue.push_back(std::move(job));
    } catch(std::exception& e) {
        m_hdRasterIndex[z].erase(blockIndex);
        g_logger.error(stdext::format("HD raster block %d/%d failed: %s",
                                      (int)z, (int)blockIndex, e.what()));
    }
}

void Minimap::dispatchHDRasterJobs()
{
    while(m_hdRasterRunningJobs.load(std::memory_order_acquire) < 1) {
        HDRasterDecodeJob job;
        {
            std::lock_guard<std::mutex> lock(m_lock);
            if(m_hdRasterQueue.empty())
                break;
            auto best = std::min_element(m_hdRasterQueue.begin(), m_hdRasterQueue.end(),
                [](const HDRasterDecodeJob& a, const HDRasterDecodeJob& b) {
                    return a.priority < b.priority;
                });
            job = std::move(*best);
            m_hdRasterQueuedBytes -= std::min(m_hdRasterQueuedBytes, job.png.size());
            m_hdRasterQueue.erase(best);
        }

        m_hdRasterRunningJobs.fetch_add(1, std::memory_order_release);
        g_asyncDispatcher.dispatch([this, job = std::move(job)]() mutable {
            HDRasterDecodeResult result;
            result.blockIndex = job.blockIndex;
            result.z = job.z;
            result.lod = job.lod;
            result.generation = job.generation;
            if(job.generation == m_hdGeneration.load(std::memory_order_acquire)) {
                try {
                    const uint16 side = HD_RASTER_LOD_SIDES[job.lod];
                    const ulong plainSize = (ulong)side * side * 4;
                    std::vector<uint8> pixels(plainSize);
                    ulong decodedSize = plainSize;
                    if(uncompress(pixels.data(), &decodedSize, job.png.data(),
                                  (ulong)job.png.size()) == Z_OK && decodedSize == plainSize) {
                        result.image = std::make_shared<Image>(Size(side, side), 4, pixels.data());
                    }
                } catch(...) {
                    result.image = nullptr;
                }
            }
            {
                std::lock_guard<std::mutex> lock(m_hdRasterResultLock);
                m_hdRasterResults.push_back(std::move(result));
            }
            m_hdRasterRunningJobs.fetch_sub(1, std::memory_order_release);
            g_dispatcher.addEvent([this] { collectHDRasterResults(); });
        });
    }
}

void Minimap::collectHDRasterResults()
{
    std::vector<HDRasterDecodeResult> results;
    {
        std::lock_guard<std::mutex> lock(m_hdRasterResultLock);
        results.swap(m_hdRasterResults);
    }
    if(results.empty())
        return;

    const uint32 generation = m_hdGeneration.load(std::memory_order_acquire);
    std::lock_guard<std::mutex> lock(m_lock);
    for(HDRasterDecodeResult& result : results) {
        if(result.z >= m_hdRasterCache.size() || result.lod >= OTMM_HD_RASTER_LOD_COUNT)
            continue;
        auto cacheIt = m_hdRasterCache[result.z].find(result.blockIndex);
        if(cacheIt == m_hdRasterCache[result.z].end())
            continue;
        cacheIt->second.queued[result.lod] = false;
        if(result.generation != generation || !m_hdBaseRaster)
            continue;

        if(!result.image ||
           result.image->getWidth() != HD_RASTER_LOD_SIDES[result.lod] ||
           result.image->getHeight() != HD_RASTER_LOD_SIDES[result.lod]) {
            // A damaged payload must not become a permanent decode/retry loop on
            // the render thread. The classic minimap remains visible underneath.
            cacheIt->second.retryAfter[result.lod] = stdext::millis() + 30000;
            continue;
        }

        if(cacheIt->second.textures[result.lod])
            m_hdRasterTextureBytes -= std::min(m_hdRasterTextureBytes,
                hdBlockTextureBytes(HD_RASTER_LOD_SIDES[result.lod]));
        auto texture = std::make_shared<Texture>(result.image, false, false, false);
        texture->setSmooth(false);
        cacheIt->second.textures[result.lod] = texture;
        cacheIt->second.lastUsed[result.lod] = stdext::millis();
        cacheIt->second.retryAfter[result.lod] = 0;
        m_hdRasterTextureBytes += hdBlockTextureBytes(HD_RASTER_LOD_SIDES[result.lod]);
    }
}

void Minimap::enforceHDRasterTextureBudget()
{
    std::lock_guard<std::mutex> lock(m_lock);
    if(m_hdRasterTextureBytes <= HD_RASTER_TEXTURE_BUDGET_BYTES)
        return;

    struct Candidate { uint8 z; uint blockIndex; uint8 lod; ticks_t lastUsed; };
    std::vector<Candidate> candidates;
    const ticks_t now = stdext::millis();
    // Zoom transitions can briefly keep two LODs resident. Do not rescan every
    // cache entry on every frame while the still-visible working set is above
    // budget; one bounded cleanup pass four times per second is sufficient.
    if(now < m_hdRasterBudgetNextScan)
        return;
    m_hdRasterBudgetNextScan = now + 250;
    for(uint8 z = 0; z < m_hdRasterCache.size(); ++z) {
        for(const auto& pair : m_hdRasterCache[z]) {
            for(uint8 lod = 0; lod < OTMM_HD_RASTER_LOD_COUNT; ++lod) {
                if(pair.second.textures[lod] && now - pair.second.lastUsed[lod] > 1000)
                    candidates.push_back({ z, pair.first, lod, pair.second.lastUsed[lod] });
            }
        }
    }
    std::sort(candidates.begin(), candidates.end(),
        [](const Candidate& a, const Candidate& b) { return a.lastUsed < b.lastUsed; });
    for(const Candidate& candidate : candidates) {
        if(m_hdRasterTextureBytes <= HD_RASTER_TEXTURE_BUDGET_BYTES)
            break;
        auto cacheIt = m_hdRasterCache[candidate.z].find(candidate.blockIndex);
        if(cacheIt == m_hdRasterCache[candidate.z].end() || !cacheIt->second.textures[candidate.lod])
            continue;
        cacheIt->second.textures[candidate.lod] = nullptr;
        m_hdRasterTextureBytes -= std::min(m_hdRasterTextureBytes,
            hdBlockTextureBytes(HD_RASTER_LOD_SIDES[candidate.lod]));
    }
}

void Minimap::drawHDRaster(const Rect& screenRect, const Position& mapCenter, float scale,
                           const Point& blockOff, const Point& start)
{
    collectHDRasterResults();
    const int blockPixels = std::max(1, (int)std::ceil(MMBLOCK_SIZE * scale));
    const uint8 lod = chooseHDRasterLod(blockPixels);
    const uint16 side = HD_RASTER_LOD_SIDES[lod];
    const Rect source(0, 0, side, side);
    const int centerBlockX = mapCenter.x / MMBLOCK_SIZE;
    const int centerBlockY = mapCenter.y / MMBLOCK_SIZE;
    const ticks_t now = stdext::millis();

    {
        std::lock_guard<std::mutex> lock(m_lock);
        if(mapCenter.z >= m_hdRasterIndex.size())
            return;
        int readsLeft = 2;
        const int blocksPerAxis = 65536 / MMBLOCK_SIZE;

        // The complete world is sparse. At distant zoom, walking the rectangular
        // 65k coordinate grid every frame costs far more than walking the actual
        // raster index (626 entries on the busiest floor).
        for(const auto& indexed : m_hdRasterIndex[mapCenter.z]) {
            const uint blockIndex = indexed.first;
            const int bx = blockIndex % blocksPerAxis;
            const int by = blockIndex / blocksPerAxis;
            const int x = bx * MMBLOCK_SIZE;
            const int y = by * MMBLOCK_SIZE;
            const int xs = start.x + ((x - blockOff.x) / MMBLOCK_SIZE) * blockPixels;
            const int ys = start.y + ((y - blockOff.y) / MMBLOCK_SIZE) * blockPixels;
            const Rect destination(xs, ys, blockPixels, blockPixels);
            if(!destination.intersects(screenRect))
                continue;

            HDRasterTextureCache& cache = m_hdRasterCache[mapCenter.z][blockIndex];
            if(cache.textures[lod]) {
                cache.lastUsed[lod] = now;
                g_drawQueue->addTexturedRect(destination, cache.textures[lod], source);
            } else {
                // Keep another decoded HD LOD visible while zooming. If this is
                // the first load, cover the classic layer until the raster is
                // ready so colored squares can never flash through.
                int fallbackLod = -1;
                int fallbackDistance = INT_MAX;
                for(uint8 candidate = 0; candidate < OTMM_HD_RASTER_LOD_COUNT; ++candidate) {
                    if(!cache.textures[candidate])
                        continue;
                    const int distance = std::abs((int)HD_RASTER_LOD_SIDES[candidate] - blockPixels);
                    if(distance < fallbackDistance) {
                        fallbackDistance = distance;
                        fallbackLod = candidate;
                    }
                }
                if(fallbackLod >= 0) {
                    const uint16 fallbackSide = HD_RASTER_LOD_SIDES[fallbackLod];
                    cache.lastUsed[fallbackLod] = now;
                    g_drawQueue->addTexturedRect(destination, cache.textures[fallbackLod],
                                                 Rect(0, 0, fallbackSide, fallbackSide));
                } else {
                    g_drawQueue->addFilledRect(destination, Color(18, 18, 18, 255));
                }

                if(!cache.queued[lod] && now >= cache.retryAfter[lod] && readsLeft > 0) {
                    --readsLeft;
                    requestHDRasterBlock((uint8)mapCenter.z, blockIndex, lod,
                        std::abs(bx - centerBlockX) + std::abs(by - centerBlockY));
                }
            }
        }
    }
    dispatchHDRasterJobs();
    enforceHDRasterTextureBudget();
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
            const size_t textureBytes = hd->getTextureBytes();
            m_hdTextureBytes -= std::min(m_hdTextureBytes, textureBytes);
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

void Minimap::queueHDBlock(MinimapBlock& block, const Position& blockPos, uint blockIndex,
                           int priority, uint16 textureSize)
{
    HDBlockData* hd = block.getHDData();
    if(!hd || hd->isEmpty())
        return;

    const uint32 revision = hd->getContentRevision();
    if(!hd->needsRender(stdext::millis(), textureSize))
        return;

    // A worker is already producing exactly this revision.
    for(const HDRunningJob& running : m_hdRunning) {
        if(running.blockIndex == blockIndex && running.z == blockPos.z &&
           running.revision == revision && running.textureSize == textureSize)
            return;
    }

    // One entry per block, always the newest revision. This is the only place a
    // job enters the queue, and the only bound that exists.
    for(size_t i = 0; i < m_hdQueue.size(); ++i) {
        if(m_hdQueue[i].blockIndex == blockIndex && m_hdQueue[i].blockPos.z == blockPos.z) {
            if(m_hdQueue[i].revision == revision && m_hdQueue[i].textureSize == textureSize)
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
    job.textureSize = textureSize;
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
        auto best = std::min_element(m_hdQueue.begin(), m_hdQueue.end(),
            [](const HDRenderJob& a, const HDRenderJob& b) { return a.priority < b.priority; });

        const size_t pendingBytes = hdBlockTextureBytes(best->textureSize);
        // Do not start work whose output has nowhere to go yet.
        if(m_hdPendingImageBytes.load(std::memory_order_acquire) + pendingBytes
           > HD_PENDING_IMAGE_BUDGET_BYTES)
            break;

        HDRenderJob job = std::move(*best);
        m_hdQueue.erase(best);

        if(job.generation != m_hdGeneration.load(std::memory_order_acquire)) {
            m_hdStaleDropped.fetch_add(1, std::memory_order_relaxed);
            continue;
        }

        HDRenderTask task;
        if(!buildHDTask(job, task)) {
            // Some invalid assets cannot be rendered. Remember that revision so
            // the same bad block does not get rebuilt on every frame forever.
            std::lock_guard<std::mutex> lock(m_lock);
            if(job.blockPos.z < m_tileBlocks.size()) {
                auto it = m_tileBlocks[job.blockPos.z].find(job.blockIndex);
                if(it != m_tileBlocks[job.blockPos.z].end() && it->second) {
                    if(HDBlockData* hd = it->second->getHDData()) {
                        if(hd->getContentRevision() == job.revision)
                            hd->markRenderFailed(job.revision, job.textureSize);
                    }
                }
            }
            continue;
        }

        m_hdRunningJobs.fetch_add(1, std::memory_order_release);
        m_hdPendingImageBytes.fetch_add(pendingBytes, std::memory_order_release);
        m_hdRunning.push_back({ task.blockIndex, task.z, task.revision, task.textureSize });

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
            result.textureSize = task.textureSize;
#ifdef WIN32
            // Composition is intentionally best-effort background work. Never let
            // a 1024x1024 minimap rebuild compete at equal priority with input and
            // the render thread while the player is walking.
            const int previousPriority = GetThreadPriority(GetCurrentThread());
            SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_BELOW_NORMAL);
#endif
            result.image = composeHDImage(task, m_hdGeneration);
#ifdef WIN32
            SetThreadPriority(GetCurrentThread(), previousPriority);
#endif

            {
                std::lock_guard<std::mutex> lock(m_hdResultLock);
                m_hdResults.push_back(std::move(result));
            }

            m_hdRunningJobs.fetch_sub(1, std::memory_order_release);
            // A logout can stop minimap drawing before the result is collected.
            // Retire it on the main thread as well so its image cannot stay
            // referenced until the next login.
            g_dispatcher.addEvent([this] { collectHDResults(); });
        });
    }
}

bool Minimap::buildHDTask(const HDRenderJob& job, HDRenderTask& task, bool pumpNativeMessages)
{
    task.blockIndex = job.blockIndex;
    task.z = (uint8)job.blockPos.z;
    task.generation = job.generation;
    task.revision = job.revision;
    task.textureSize = job.textureSize;

    // Protobuf (15.x) assets store the whole bounding square per layer; legacy .spr
    // splits it into 32px cells.
    const bool protobuf = g_sprites.isHdMod();
    const int spriteSize = g_sprites.spriteSize() > 0 ? g_sprites.spriteSize() : 32;
    const bool independentSprites = !protobuf && g_sprites.canStreamSpritesIndependently();
    if(independentSprites) {
        if(!m_hdWorkerSpriteFile)
            m_hdWorkerSpriteFile = g_sprites.openIndependentSpriteStream();
        task.spriteFile = m_hdWorkerSpriteFile;
        task.spriteSize = g_sprites.baseSpriteSize();
        task.spritesHaveAlpha = g_game.getFeature(Otc::GameSpritesAlphaChannel);
        if(!task.spriteFile)
            return false;
    }

    // Sprite images and thing types are resolved HERE, on the dispatcher thread.
    // SpriteManager decrypts in place and mutates an LRU, and ThingTypeManager has
    // no synchronisation at all, so a worker must never reach either of them.
    // Deduplicated so a wall repeated across a block decodes once.
    std::unordered_map<int, ImagePtr> resolved;
    auto spriteImage = [&](int spriteId) -> const ImagePtr& {
        auto it = resolved.find(spriteId);
        if(it == resolved.end())
            it = resolved.emplace(spriteId, getHDSpriteImage(spriteId)).first;
        return it->second;
    };

    // Two passes so full-ground tiles land under everything else, matching the
    // stacking the game view uses.
    uint32 itemsVisited = 0;
    for(int pass = 0; pass < 2; ++pass) {
        for(const HDJobTile& jobTile : job.tiles) {
            for(uint16 i = 0; i < jobTile.count; ++i) {
                if(pumpNativeMessages && (++itemsVisited & 0x7Fu) == 0) {
                    g_window.poll();
                    std::this_thread::yield();
                }
                const HDMinimapItem& entry = job.items[jobTile.first + i];

                if(!g_things.isValidDatId(entry.id, ThingCategoryItem))
                    continue;

                // isLoaded() only reports whether the regular render texture is
                // resident. Most world items have never been drawn while this
                // offline builder runs, so filtering on it produced a raster with
                // almost every ground tile missing. The DAT definition and sprite
                // list are valid independently of that transient texture cache.
                ThingType* thingType = g_things.rawGetThingType(entry.id, ThingCategoryItem);
                if(!thingType)
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

                const std::vector<int>& sprites = thingType->getSpritesRef();
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

                                HDBlit blit;
                                const int spriteId = sprites[spriteIndex];
                                if(independentSprites) {
                                    blit.spriteId = spriteId;
                                    blit.spriteAddress = g_sprites.getSpriteAddress(spriteId);
                                    if(blit.spriteAddress == 0)
                                        continue;
                                } else {
                                    blit.image = spriteImage(spriteId);
                                    if(!blit.image)
                                        continue;
                                }
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

ImagePtr Minimap::getHDSpriteImage(int spriteId)
{
    auto it = m_hdSpriteImageCache.find(spriteId);
    if(it != m_hdSpriteImageCache.end()) {
        m_hdSpriteImageLru.splice(m_hdSpriteImageLru.begin(), m_hdSpriteImageLru, it->second.lruIt);
        return it->second.image;
    }

    ImagePtr image = g_sprites.getSpriteImage(spriteId);
    if(!image)
        return nullptr;

    const size_t bytes = (size_t)image->getPixelCount() * image->getBpp();
    if(bytes > HD_SPRITE_IMAGE_BUDGET_BYTES)
        return image;

    while(!m_hdSpriteImageLru.empty() &&
          (m_hdSpriteImageCache.size() >= HD_SPRITE_IMAGE_MAX_ENTRIES ||
           m_hdSpriteImageBytes + bytes > HD_SPRITE_IMAGE_BUDGET_BYTES)) {
        const int oldestId = m_hdSpriteImageLru.back();
        m_hdSpriteImageLru.pop_back();
        auto oldest = m_hdSpriteImageCache.find(oldestId);
        if(oldest != m_hdSpriteImageCache.end()) {
            m_hdSpriteImageBytes -= oldest->second.bytes;
            m_hdSpriteImageCache.erase(oldest);
        }
    }

    m_hdSpriteImageLru.push_front(spriteId);
    m_hdSpriteImageCache.emplace(spriteId,
        HDSpriteImageCacheEntry{ image, bytes, m_hdSpriteImageLru.begin() });
    m_hdSpriteImageBytes += bytes;
    return image;
}

void Minimap::clearHDSpriteImageCache()
{
    m_hdSpriteImageCache.clear();
    m_hdSpriteImageLru.clear();
    m_hdSpriteImageBytes = 0;
}

ImagePtr Minimap::composeHDImage(const HDRenderTask& task, const std::atomic<uint32>& generation,
                                bool pumpNativeMessages)
{
    if(task.textureSize < 2 || task.textureSize > HD_CANONICAL_BLOCK_TEXTURE_SIZE)
        return nullptr;

    // Render straight at the LOD selected by the current zoom. Blits remain in a
    // canonical 1024x1024 coordinate system so the same snapshot can represent
    // multi-tile sprites at every overview resolution.
    const int targetSize = task.textureSize;
    const double lodScale = (double)targetSize / HD_CANONICAL_BLOCK_TEXTURE_SIZE;
    ImagePtr target = std::make_shared<Image>(Size(targetSize, targetSize));
    uint8* dstBase = target->getPixelData();

    std::unordered_map<int, ImagePtr> decodedSprites;
    int sinceCheck = 0;
    for(const HDBlit& blit : task.blits) {
        // Early cancellation: a job invalidated by a toggle, relog or clean stops
        // burning CPU instead of finishing and being thrown away at the end.
        if(++sinceCheck >= 32) {
            sinceCheck = 0;
            if(generation.load(std::memory_order_acquire) != task.generation)
                return nullptr;
            if(pumpNativeMessages) {
                g_window.poll();
                std::this_thread::yield();
            }
        }

        ImagePtr src = blit.image;
        if(!src && task.spriteFile && blit.spriteAddress != 0) {
            auto it = decodedSprites.find(blit.spriteId);
            if(it == decodedSprites.end()) {
                try {
                    it = decodedSprites.emplace(blit.spriteId,
                        SpriteManager::decodeCasualSprite(task.spriteFile, blit.spriteAddress,
                            task.spriteSize, task.spritesHaveAlpha)).first;
                } catch(const stdext::exception&) {
                    it = decodedSprites.emplace(blit.spriteId, nullptr).first;
                }
            }
            src = it->second;
        }
        if(!src || blit.width <= 0 || blit.height <= 0)
            continue;

        const int srcW = src->getWidth();
        const int srcH = src->getHeight();
        if(srcW <= 0 || srcH <= 0)
            continue;

        uint8* srcBase = src->getPixelData();

        const int destLeft = (int)std::floor(blit.destX * lodScale);
        const int destTop = (int)std::floor(blit.destY * lodScale);
        const int destRight = (int)std::ceil((blit.destX + blit.width) * lodScale);
        const int destBottom = (int)std::ceil((blit.destY + blit.height) * lodScale);
        const int scaledWidth = std::max(1, destRight - destLeft);
        const int scaledHeight = std::max(1, destBottom - destTop);

        for(int dy = std::max(0, destTop); dy < std::min(targetSize, destBottom); ++dy) {
            const int oy = dy - destTop;

            int sy0 = (oy * srcH) / scaledHeight;
            int sy1 = ((oy + 1) * srcH) / scaledHeight;
            if(sy1 <= sy0) sy1 = sy0 + 1;
            if(sy1 > srcH) sy1 = srcH;

            for(int dx = std::max(0, destLeft); dx < std::min(targetSize, destRight); ++dx) {
                const int ox = dx - destLeft;

                int sx0 = (ox * srcW) / scaledWidth;
                int sx1 = ((ox + 1) * srcW) / scaledWidth;
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

                uint8* dst = dstBase + ((size_t)dy * targetSize + dx) * 4;
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
        const size_t resultBytes = hdBlockTextureBytes(result.textureSize);
        m_hdPendingImageBytes.fetch_sub(resultBytes, std::memory_order_release);

        // Retire the in-flight entry first, whatever the outcome, so the block
        // becomes queueable again even if the render was cancelled or rejected.
        for(size_t i = 0; i < m_hdRunning.size(); ++i) {
            if(m_hdRunning[i].blockIndex == result.blockIndex &&
               m_hdRunning[i].z == result.z &&
               m_hdRunning[i].revision == result.revision &&
               m_hdRunning[i].textureSize == result.textureSize) {
                m_hdRunning.erase(m_hdRunning.begin() + i);
                break;
            }
        }

        if(!result.image || result.generation != generation ||
           !m_hdMode.load(std::memory_order_relaxed)) {
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
        const size_t previousBytes = hd->getTextureBytes();

        // Constructing a Texture performs no GL call: it only holds the image
        // until the main thread uploads it in Texture::update(). Marked
        // non-cacheable so these 512x512 blocks never enter g_atlas, which is
        // shared with the game view.
        TexturePtr texture = std::make_shared<Texture>(result.image);
        // Minimap sprites are pixel art. Bilinear filtering made the nominal HD
        // layer visibly blurry, especially when the widget was between integer
        // zoom levels. Nearest sampling keeps item and wall edges crisp.
        texture->setSmooth(false);
        texture->setCanCache(false);

        hd->setTexture(texture, result.revision, result.textureSize);

        if(wasResident)
            m_hdTextureBytes -= std::min(m_hdTextureBytes, previousBytes);
        m_hdTextureBytes += resultBytes;

        if(!wasResident) {
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
            const size_t textureBytes = hd->getTextureBytes();
            hd->dropTexture();
            m_hdTextureBytes -= std::min(m_hdTextureBytes, textureBytes);
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
    // nothing else Ã¢â‚¬â€ the active floor gets no special treatment, which is exactly
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
        if(m_hdMode.load(std::memory_order_relaxed) && !m_hdBaseRaster)
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

    m_hdMode.store(enabled, std::memory_order_relaxed);

    if(!enabled) {
        // Do not invalidate the generation used by an active save. The final save
        // completion event performs this cleanup immediately afterwards.
        if(m_hdSaving.load(std::memory_order_acquire)) {
            m_hdDisablePending.store(true, std::memory_order_release);
            return;
        }

        std::lock_guard<std::mutex> lock(m_lock);
        m_hdBootstrapPending = false;
        invalidateHDLocked();
        closeHDBase();
    } else {
        // Re-enabling before the deferred cleanup ran can reuse the retained
        // payload safely; no generation bump or second bootstrap is necessary.
        if(m_hdDisablePending.exchange(false, std::memory_order_acq_rel))
            return;

        std::lock_guard<std::mutex> lock(m_lock);
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
    m_hdWorkerSpriteFile.reset();
    clearHDSpriteImageCache();

    // Images already produced are dropped; their reservation is released with them.
    {
        std::lock_guard<std::mutex> lock(m_hdResultLock);
        for(const HDRenderResult& result : m_hdResults)
            m_hdPendingImageBytes.fetch_sub(hdBlockTextureBytes(result.textureSize),
                                            std::memory_order_release);
        m_hdResults.clear();
        m_hdResults.shrink_to_fit();
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
    // Offline publication step. The OTBM is globally merged first: tile
    // areas are not guaranteed to align to 64x64 minimap blocks, so flushing each
    // area independently used to create duplicate index entries and silently lose
    // most of a block. The distributed result contains compressed RGBA photographs
    // only; it contains no tile coordinates inside blocks and no item identifiers.
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

        fout->addU32(OTMM_HD_RASTER_SIGNATURE);
        fout->addU16(OTMM_HD_RASTER_VERSION);
        for(uint16 side : HD_RASTER_LOD_SIDES)
            fout->addU16(side);
        fout->addU32(0);   // index offset, patched at the end
        fout->addU32(0);   // unique block count, patched at the end

        struct IndexRecord {
            uint16 bx = 0;
            uint16 by = 0;
            uint8 z = 0;
            HDRasterBaseEntry entry;
        };
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

        const int maxZ = g_gameConfig.getMapMaxZ();
        std::vector<std::unordered_map<uint, HDBlockData>> worldBlocks(maxZ + 1);
        uint64 tilesSeen = 0;
        uint64 tileNodesSeen = 0;

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

                for(const BinaryTreePtr& nodeTile : nodeArea->getChildren()) {
                    // This is an offline operation, but it still runs from the UI
                    // dispatcher because thing/sprite managers are not thread-safe.
                    // Pump only native window messages so Windows never treats the
                    // generator as hung; do not recursively poll the dispatcher.
                    if((++tileNodesSeen & 0x7FFu) == 0) {
                        g_window.poll();
                        std::this_thread::yield();
                    }
                    const uint8 type = nodeTile->getU8();
                    if(type != OTBM_TILE && type != OTBM_HOUSETILE)
                        continue;

                    const Position pos = basePos + nodeTile->getPoint();
                    if(pos.z < 0 || pos.z > maxZ)
                        continue;
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

                    worldBlocks[pos.z][blockIndex].setTileItems(tileIndex, items.data(), (uint16)items.size());
                }
            }
        }

        uint32 uniqueBlocks = 0;
        for(const auto& floor : worldBlocks)
            uniqueBlocks += (uint32)floor.size();
        g_logger.info(stdext::format(
            "HD raster baseline: parsed %d populated tiles into %d unique blocks",
            (int)tilesSeen, (int)uniqueBlocks));

        std::atomic<uint32> offlineGeneration{1};
        const uint32 generation = 1;
        uint32 rendered = 0;
        for(int z = 0; z <= maxZ; ++z) {
            std::vector<uint> blockIndices;
            blockIndices.reserve(worldBlocks[z].size());
            for(const auto& pair : worldBlocks[z]) {
                if(!pair.second.isEmpty())
                    blockIndices.push_back(pair.first);
            }
            std::sort(blockIndices.begin(), blockIndices.end());

            if(!blockIndices.empty())
                g_logger.info(stdext::format("HD raster baseline: rendering floor %d (%d blocks)",
                                             z, (int)blockIndices.size()));

            for(uint blockIndex : blockIndices) {
                g_window.poll();
                std::this_thread::yield();
                const Position blockPos = getIndexPosition(blockIndex, z);
                HDRenderJob job;
                job.blockIndex = blockIndex;
                job.blockPos = blockPos;
                job.generation = generation;
                job.revision = 1;
                job.textureSize = HD_RASTER_LOD_SIDES.back();

                const int margin = 3;
                const int elevationMargin = 2;
                for(int nby = -1; nby <= 1; ++nby) {
                    for(int nbx = -1; nbx <= 1; ++nbx) {
                        const int nx = blockPos.x + nbx * MMBLOCK_SIZE;
                        const int ny = blockPos.y + nby * MMBLOCK_SIZE;
                        if(nx < 0 || ny < 0 || nx >= 65536 || ny >= 65536)
                            continue;
                        const Position neighbourPos(nx, ny, z);
                        auto neighbour = worldBlocks[z].find(getBlockIndex(neighbourPos));
                        if(neighbour == worldBlocks[z].end())
                            continue;
                        const HDBlockData& hd = neighbour->second;
                        for(const HDTileRecord& tile : hd.getRecords()) {
                            const int gx = tile.tileIndex % MMBLOCK_SIZE + nbx * MMBLOCK_SIZE;
                            const int gy = tile.tileIndex / MMBLOCK_SIZE + nby * MMBLOCK_SIZE;
                            if(gx < -margin || gx >= MMBLOCK_SIZE + margin ||
                               gy < -margin - elevationMargin || gy >= MMBLOCK_SIZE + margin)
                                continue;
                            HDJobTile jobTile;
                            jobTile.gx = (int16)gx;
                            jobTile.gy = (int16)gy;
                            jobTile.first = (uint32)job.items.size();
                            jobTile.count = tile.count;
                            const HDMinimapItem* source = hd.getItemPool().data() + tile.offset;
                            job.items.insert(job.items.end(), source, source + tile.count);
                            job.tiles.push_back(jobTile);
                        }
                    }
                }

                HDRenderTask task;
                if(job.tiles.empty() || !buildHDTask(job, task, true))
                    continue;
                ImagePtr canonical = composeHDImage(task, offlineGeneration, true);
                if(!canonical)
                    continue;

                IndexRecord record;
                record.bx = (uint16)(blockPos.x / MMBLOCK_SIZE);
                record.by = (uint16)(blockPos.y / MMBLOCK_SIZE);
                record.z = (uint8)z;
                bool complete = true;
                for(uint8 lod = 0; lod < OTMM_HD_RASTER_LOD_COUNT; ++lod) {
                    ImagePtr image = downsampleHDImage(canonical, HD_RASTER_LOD_SIDES[lod]);
                    std::string raster = encodeHDRasterImage(image);
                    if(raster.empty() || raster.size() > HD_RASTER_MAX_PNG_BYTES ||
                       (uint64)fout->tell() + raster.size() > 512ull * 1024 * 1024) {
                        complete = false;
                        break;
                    }
                    record.entry.lods[lod].offset = fout->tell();
                    record.entry.lods[lod].size = (uint32)raster.size();
                    fout->write(raster.data(), (uint)raster.size());
                }
                if(!complete)
                    stdext::throw_exception("raster baseline exceeds its safe size limit");
                index.push_back(record);
                ++rendered;
                if(rendered % 10 == 0)
                    g_logger.info(stdext::format("HD raster baseline: %d blocks rendered", (int)rendered));
            }
        }

        // Index goes last so the data section can be written in one forward pass.
        const uint32 indexOffset = fout->tell();
        for(const IndexRecord& record : index) {
            fout->addU16(record.bx);
            fout->addU16(record.by);
            fout->addU8(record.z);
            for(const HDRasterPayloadEntry& payload : record.entry.lods) {
                fout->addU32(payload.offset);
                fout->addU32(payload.size);
            }
        }

        fout->seek(12);
        fout->addU32(indexOffset);
        fout->addU32((uint32)index.size());

        fout->flush();
        fout->close();

        std::filesystem::path finalPath(g_resources.getWriteDir());
        std::filesystem::path tmpPath(g_resources.getWriteDir());
        finalPath += outputFile;
        tmpPath += tmpFile;
        std::error_code ec;
        std::filesystem::remove(finalPath, ec);
        ec.clear();
        std::filesystem::rename(tmpPath, finalPath, ec);
        if(ec) {
            std::filesystem::remove(tmpPath, ec);
            stdext::throw_exception("unable to replace output file");
        }

        m_hdWorkerSpriteFile.reset();
        clearHDSpriteImageCache();
        g_logger.info(stdext::format("HD raster baseline written: %d unique blocks, %d tiles",
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

        const uint32 signature = fin->getU32();
        const uint16 version = fin->getU16();
        const int maxZ = (int)m_tileBlocks.size() - 1;

        if(signature == OTMM_HD_RASTER_SIGNATURE) {
            if(version != OTMM_HD_RASTER_VERSION || fin->size() < 20)
                stdext::throw_exception("unsupported HD raster baseline version");
            for(uint16 expected : HD_RASTER_LOD_SIDES) {
                if(fin->getU16() != expected)
                    stdext::throw_exception("unsupported HD raster resolution table");
            }
            const uint32 indexOffset = fin->getU32();
            const uint32 blockCount = fin->getU32();
            constexpr uint32 recordSize = 5 + OTMM_HD_RASTER_LOD_COUNT * 8;
            if(blockCount == 0 || blockCount > HD_MAX_BASE_BLOCKS)
                stdext::throw_exception("HD raster block count out of range");
            if(indexOffset < 20 || indexOffset > fin->size() ||
               (uint64)blockCount * recordSize > (uint64)(fin->size() - indexOffset))
                stdext::throw_exception("HD raster index is invalid or truncated");

            m_hdRasterIndex.assign(maxZ + 1, {});
            m_hdRasterCache.assign(maxZ + 1, {});
            fin->seek(indexOffset);
            uint32 accepted = 0;
            for(uint32 i = 0; i < blockCount; ++i) {
                const uint16 bx = fin->getU16();
                const uint16 by = fin->getU16();
                const uint8 z = fin->getU8();
                HDRasterBaseEntry entry;
                bool valid = z <= maxZ && bx < 1024 && by < 1024;
                for(HDRasterPayloadEntry& payload : entry.lods) {
                    payload.offset = fin->getU32();
                    payload.size = fin->getU32();
                    if(payload.size == 0 || payload.size > HD_RASTER_MAX_PNG_BYTES ||
                       payload.offset < 20 || payload.offset > indexOffset ||
                       payload.size > indexOffset - payload.offset)
                        valid = false;
                }
                if(!valid)
                    continue;
                const Position blockPos((int)bx * MMBLOCK_SIZE, (int)by * MMBLOCK_SIZE, z);
                const uint blockIndex = getBlockIndex(blockPos);
                if(m_hdRasterIndex[z].emplace(blockIndex, entry).second)
                    ++accepted;
            }
            if(accepted == 0)
                stdext::throw_exception("HD raster baseline contains no valid blocks");

            m_hdBaseFile = fin;
            m_hdBaseFileName = fileName;
            m_hdBaseRaster = true;
            g_logger.info(stdext::format("HD raster baseline attached: %d unique blocks",
                                         (int)accepted));
            return true;
        }

        stdext::throw_exception(
            "structured HD baselines are not supported; expected an HDRB raster archive");
    } catch(std::exception& e) {
        g_logger.error(stdext::format("failed to open HD baseline: %s", e.what()));
        closeHDBase();
        return false;
    }
}

void Minimap::closeHDBase()
{
    m_hdGeneration.fetch_add(1, std::memory_order_release);
    m_hdBaseFile = nullptr;
    m_hdBaseFileName.clear();
    m_hdBaseIndex.clear();
    m_hdBaseRaster = false;
    clearHDRasterState();
}

void Minimap::clearHDRasterState()
{
    m_hdRasterIndex.clear();
    m_hdRasterCache.clear();
    m_hdRasterQueue.clear();
    m_hdRasterQueuedBytes = 0;
    m_hdRasterTextureBytes = 0;
    m_hdRasterBudgetNextScan = 0;
    {
        std::lock_guard<std::mutex> lock(m_hdRasterResultLock);
        m_hdRasterResults.clear();
    }
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
                return;
            }

            if(m_hdDisablePending.exchange(false, std::memory_order_acq_rel) &&
               !m_hdMode.load(std::memory_order_relaxed)) {
                std::lock_guard<std::mutex> lock(m_lock);
                m_hdBootstrapPending = false;
                invalidateHDLocked();
                closeHDBase();
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
        << "pendingImages=" << m_hdRunningJobs.load(std::memory_order_acquire)
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
