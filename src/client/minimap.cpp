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
#include "game.h"
#include "map.h"
#include "spritemanager.h"
#include "thingtype.h"
#include "thingtypemanager.h"

#include <framework/graphics/image.h>
#include <framework/graphics/texture.h>
#include <framework/graphics/painter.h>
#include <framework/graphics/image.h>
#include <framework/graphics/framebuffermanager.h>
#include <framework/core/resourcemanager.h>
#include <framework/core/filestream.h>
#include <zlib.h>

#include <framework/util/stats.h>

#include <sstream>
#include <chrono>
#include <unordered_set>

Minimap g_minimap;

void MinimapBlock::clean()
{
    m_tiles.fill(MinimapTile());
    m_tileItems.fill(std::vector<uint16>());
    m_extendedTileItems.clear();
    m_texture.reset();
    m_hdTexture.reset();
    setPendingHDImage(nullptr);
    m_isRendering.store(false);
    m_mustUpdate = false;
    m_hdNeedsUpdate = true;
    m_itemsHash = 0;
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
    if(m_tiles[getTileIndex(x,y)].color != tile.color) {
        m_mustUpdate = true;
        m_hdNeedsUpdate = true;
        m_needsSave = true;
    }

    m_tiles[getTileIndex(x,y)] = tile;
}

void Minimap::init()
{
    m_hdMode = false;

    m_renderThreadRunning = true;
    for(int i = 0; i < NUM_RENDER_THREADS; ++i) {
        m_renderThreads[i] = std::thread(&Minimap::renderThreadFunc, this);
    }
}

void Minimap::terminate()
{
    {
        std::lock_guard<std::mutex> lock(m_renderMutex);
        m_renderThreadRunning = false;
        m_renderCondition.notify_all();
    }

    for(int i = 0; i < NUM_RENDER_THREADS; ++i) {
        if(m_renderThreads[i].joinable()) {
            m_renderThreads[i].join();
        }
    }

    if(m_saveThread.joinable()) {
        m_saveThread.join();
    }

    clean();
}

void Minimap::clean()
{
    std::lock_guard<std::mutex> lock(m_lock);
    for(int i=0;i<=Otc::MAX_Z;++i)
        m_tileBlocks[i].clear();
}

void Minimap::setHDMode(bool enabled)
{
    if(m_hdMode == enabled)
        return;

    m_hdMode = enabled;

    // Drop any queued work; the per-block fields a worker would touch are reset below.
    {
        std::lock_guard<std::mutex> qlock(m_renderMutex);
        while(!m_renderQueue.empty()) {
            HDRenderJob& job = m_renderQueue.front();
            if(job.block)
                job.block->setRendering(false);
            m_renderQueue.pop();
        }
        m_renderQueueSize.store(0);
    }

    // Reset per-block textures. m_lock guards the block map / base texture; the HD
    // hand-off fields (m_hdTexture/m_pendingHDImage) are additionally guarded by
    // m_renderMutex so this cannot race a worker's final hand-off.
    std::lock_guard<std::mutex> lock(m_lock);
    std::lock_guard<std::mutex> rlock(m_renderMutex);
    for(int z = 0; z <= Otc::MAX_Z; ++z) {
        for(auto& pair : m_tileBlocks[z]) {
            if(!pair.second)
                continue;
            pair.second->m_hdNeedsUpdate = true;
            pair.second->m_mustUpdate = true;
            if(enabled) {
                pair.second->m_texture.reset();
            } else {
                pair.second->m_hdTexture.reset();
                pair.second->setPendingHDImage(nullptr);
                pair.second->setRendering(false);
            }
        }
    }
}

void Minimap::queueBlockHD(const MinimapBlock_ptr& block, const Position& blockPos, bool processLiveTiles)
{
    if(!block)
        return;

    // Already busy with this block, or a finished image is awaiting upload.
    if(block->isRendering() || block->hasPendingHD())
        return;

    // Throttle: don't pile work on the render threads.
    if(m_renderQueueSize.load() > 8) {
        block->m_hdNeedsUpdate = true;
        return;
    }

    // Up-to-date texture, nothing to do.
    if(block->m_hdTexture && !block->m_hdNeedsUpdate) {
        block->markUsed();
        return;
    }

    if(!block->m_hdTexture)
        block->m_hdNeedsUpdate = true;

    // While moving, the block being traversed gets dirtied every step. Don't rebuild its
    // (expensive 2048x2048) texture more than a few times a second — this is what keeps
    // running smooth. New blocks (no texture yet) are never throttled, so they still
    // appear immediately.
    if(block->m_hdTexture && (stdext::millis() - block->m_lastRenderTime) < 350)
        return;

    const int margin = 3;
    const int elevationMargin = 2;
    const int side = MMBLOCK_SIZE + margin * 2;
    const int height = side + elevationMargin;

    HDRenderJob job;
    job.blockPos = blockPos;
    job.block = block;
    job.side = side;
    job.height = height;
    job.protobuf = g_sprites.isUsingProtobuf();
    job.spriteSize = g_sprites.spriteSize();
    job.items.assign((size_t)side * height, {});
    job.hook.assign((size_t)side * height, 0);

    // 1) Snapshot the item ids of this block plus its neighbour margin straight from the
    //    stored per-tile data (kept current by Minimap::updateTile). The old per-frame
    //    g_map re-scan here was redundant with updateTile and a major CPU cost.
    size_t newHash = 0;
    {
        std::lock_guard<std::mutex> lock(m_lock);
        for(int y = -margin - elevationMargin; y < MMBLOCK_SIZE + margin; ++y) {
            for(int x = -margin; x < MMBLOCK_SIZE + margin; ++x) {
                std::vector<uint16> ids;
                if(x < 0 || x >= MMBLOCK_SIZE || y < 0 || y >= MMBLOCK_SIZE) {
                    int boX = (x < 0) ? -1 : (x >= MMBLOCK_SIZE) ? 1 : 0;
                    int boY = (y < 0) ? -1 : (y >= MMBLOCK_SIZE) ? 1 : 0;
                    Position nb(blockPos.x + boX * MMBLOCK_SIZE, blockPos.y + boY * MMBLOCK_SIZE, blockPos.z);
                    auto it = m_tileBlocks[nb.z].find(getBlockIndex(nb));
                    if(it != m_tileBlocks[nb.z].end() && it->second)
                        ids = it->second->getTileItems(x - boX * MMBLOCK_SIZE, y - boY * MMBLOCK_SIZE);
                } else {
                    ids = block->getTileItems(x, y);
                }

                if(!ids.empty()) {
                    for(uint16 itemId : ids)
                        newHash ^= std::hash<uint16>{}(itemId) + 0x9e3779b9 + (newHash << 6) + (newHash >> 2);
                    job.items[(y + margin + elevationMargin) * side + (x + margin)] = std::move(ids);
                }
            }
        }
    }

    // Nothing changed since the existing texture was built — bail BEFORE any g_map or
    // sprite work. This is the common case while moving and is what keeps HD cheap.
    if(newHash == block->m_itemsHash && block->m_hdTexture) {
        block->m_hdNeedsUpdate = false;
        return;
    }

    // 2) Resolve hangable hook orientation from the live map (main thread only), and only
    //    for tiles that actually have items — far fewer g_map lookups than the full grid.
    if(processLiveTiles) {
        for(int y = -margin - elevationMargin; y < MMBLOCK_SIZE + margin; ++y) {
            for(int x = -margin; x < MMBLOCK_SIZE + margin; ++x) {
                int gi = (y + margin + elevationMargin) * side + (x + margin);
                if(job.items[gi].empty())
                    continue;
                TilePtr mapTile = g_map.getTile(Position(blockPos.x + x, blockPos.y + y, blockPos.z));
                if(!mapTile)
                    continue;
                if(mapTile->mustHookSouth())
                    job.hook[gi] = 1;
                else if(mapTile->mustHookEast())
                    job.hook[gi] = 2;
            }
        }
    }

    block->m_itemsHash = newHash;
    block->m_hdNeedsUpdate = false;
    block->setRendering(true);

    // 3) Pre-fetch each sprite the worker may need, on the main thread (g_sprites is not
    //    thread-safe). Dedupe item ids so a wall repeated across the block resolves its
    //    sprites once instead of once per tile.
    {
        std::unordered_set<uint16> seenItems;
        for(const std::vector<uint16>& tileItems : job.items) {
            for(uint16 itemId : tileItems) {
                if(!seenItems.insert(itemId).second)
                    continue;
                ThingTypePtr thingType = g_things.getThingType(itemId, ThingCategoryItem);
                if(!thingType)
                    continue;
                for(int spriteId : thingType->getSprites()) {
                    if(job.spriteImages.find(spriteId) == job.spriteImages.end())
                        job.spriteImages.emplace(spriteId, g_sprites.getSpriteImage(spriteId));
                }
            }
        }
    }

    {
        std::lock_guard<std::mutex> qlock(m_renderMutex);
        if((int)m_renderQueue.size() < 15) {
            block->m_lastRenderTime = stdext::millis();
            m_renderQueue.push(std::move(job));
            m_renderQueueSize.store((int)m_renderQueue.size());
            m_renderCondition.notify_one();
        } else {
            block->setRendering(false);
            block->m_hdNeedsUpdate = true;
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

    if(!m_hdMode) {
        // Standard single-colour minimap (unchanged behaviour).
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

        g_drawQueue->setClip(drawQueueStart, screenRect);
        return;
    }

    // ---- HD minimap mode ----

    // Drop stale work if the render queue is backing up.
    {
        std::unique_lock<std::mutex> lock(m_renderMutex, std::try_to_lock);
        if(lock.owns_lock() && m_renderQueue.size() > 20) {
            int toRemove = std::min(5, (int)m_renderQueue.size() - 15);
            for(int i = 0; i < toRemove && !m_renderQueue.empty(); ++i) {
                HDRenderJob& item = m_renderQueue.front();
                if(item.block) {
                    item.block->setRendering(false);
                }
                m_renderQueue.pop();
            }
            m_renderQueueSize.store((int)m_renderQueue.size());
        }
    }

    // Upload any HD images finished by the render threads (GL upload must run here).
    processCompletedRenders();

    // HD textures are large (2048x2048); periodically free far-away/old ones.
    static int cleanupCounter = 0;
    if(++cleanupCounter > 300) {
        cleanupCounter = 0;

        // Take m_lock (block map / base texture) and m_renderMutex (HD hand-off
        // fields) together so resetting m_hdTexture/m_pendingHDImage cannot race a
        // worker's final hand-off. Skip this frame if either is contended.
        std::unique_lock<std::mutex> cleanupLock(m_lock, std::try_to_lock);
        std::unique_lock<std::mutex> cleanupRenderLock(m_renderMutex, std::try_to_lock);
        if(cleanupLock.owns_lock() && cleanupRenderLock.owns_lock()) {
            const ticks_t currentTime = stdext::millis();
            const ticks_t maxAge = 20000;
            const int maxDistance = MMBLOCK_SIZE * 12;

            int totalHDBlocks = 0;
            int blocksWithData = 0;

            if(mapCenter.z <= Otc::MAX_Z) {
                for(auto& pair : m_tileBlocks[mapCenter.z]) {
                    if(pair.second) {
                        if(pair.second->wasSeen()) blocksWithData++;
                        if(pair.second->m_hdTexture) totalHDBlocks++;
                    }
                }
            }

            const int maxAllowedHD = 250;
            const int maxAllowedBase = 3500;
            bool aggressiveCleanup = totalHDBlocks > maxAllowedHD || blocksWithData > maxAllowedBase;

            int maxCleanupsPerFrame = aggressiveCleanup ? 8 : 4;
            int cleanupsDone = 0;

            for(uint8_t z = 0; z <= Otc::MAX_Z && cleanupsDone < maxCleanupsPerFrame; ++z) {
                if(std::abs((int)z - (int)mapCenter.z) <= 1) continue;

                for(auto& pair : m_tileBlocks[z]) {
                    if(cleanupsDone >= maxCleanupsPerFrame) break;
                    if(!pair.second) continue;

                    // Don't disturb a block being rendered or awaiting upload.
                    if(pair.second->isRendering() || pair.second->hasPendingHD()) continue;

                    Position blockPos = getIndexPosition(pair.first, z);
                    int dx = std::abs(blockPos.x - mapCenter.x);
                    int dy = std::abs(blockPos.y - mapCenter.y);
                    ticks_t age = currentTime - pair.second->getLastUsedTime();

                    bool isFarAway = (dx > maxDistance || dy > maxDistance);

                    if(pair.second->m_hdTexture) {
                        bool shouldCleanHD = (isFarAway && age > maxAge) ||
                                            (aggressiveCleanup && age > 8000);

                        if(shouldCleanHD) {
                            pair.second->m_hdTexture.reset();
                            pair.second->setPendingHDImage(nullptr);
                            pair.second->m_hdNeedsUpdate = true;
                            cleanupsDone++;
                        }
                    }

                    if(pair.second->m_texture && cleanupsDone < maxCleanupsPerFrame) {
                        bool shouldCleanBase = (isFarAway && age > maxAge) ||
                                              (aggressiveCleanup && age > 8000);

                        if(shouldCleanBase) {
                            pair.second->m_texture.reset();
                            cleanupsDone++;
                        }
                    }
                }
            }
        }
    }

    // Stack the floors above (surface) with a slight offset, then dim them.
    if(mapCenter.z < 7) {
        for(int floorOffset = (7 - mapCenter.z); floorOffset >= 1; --floorOffset) {
            int floorZ = mapCenter.z + floorOffset;
            int offsetPixels = (int)(floorOffset * scale);

            for(int y = blockOff.y, ys = start.y; ys < screenRect.bottom(); y += MMBLOCK_SIZE, ys += MMBLOCK_SIZE*scale) {
                if(y < 0 || y >= 65536)
                    continue;

                for(int x = blockOff.x, xs = start.x; xs < screenRect.right(); x += MMBLOCK_SIZE, xs += MMBLOCK_SIZE*scale) {
                    if(x < 0 || x >= 65536)
                        continue;

                    Position blockPos(x, y, floorZ);
                    if(!hasBlock(blockPos))
                        continue;

                    MinimapBlock& block = getBlock(blockPos);
                    block.markUsed();

                    Rect dest(xs + offsetPixels, ys + offsetPixels, MMBLOCK_SIZE * scale, MMBLOCK_SIZE * scale);

                    queueBlockHD(block.shared_from_this(), blockPos, false);
                    const TexturePtr& tex = block.getHDTexture();
                    if(tex) {
                        Rect src(0, 0, MMBLOCK_SIZE * 32, MMBLOCK_SIZE * 32);
                        g_drawQueue->addTexturedRect(dest, tex, src);
                    }
                }
            }
        }

        Rect darkOverlayRect = screenRect;
        Color darknessOverlay = Color::black;
        darknessOverlay.setAlpha(120);
        g_drawQueue->addFilledRect(darkOverlayRect, darknessOverlay);
    }

    // Hint the floor directly below (underground) with a small offset.
    if(mapCenter.z >= 8 && mapCenter.z < 15) {
        int belowFloorZ = mapCenter.z + 1;
        int offsetPixels = (int)scale;

        for(int y = blockOff.y, ys = start.y; ys < screenRect.bottom(); y += MMBLOCK_SIZE, ys += MMBLOCK_SIZE*scale) {
            if(y < 0 || y >= 65536)
                continue;

            for(int x = blockOff.x, xs = start.x; xs < screenRect.right(); x += MMBLOCK_SIZE, xs += MMBLOCK_SIZE*scale) {
                if(x < 0 || x >= 65536)
                    continue;

                Position blockPos(x, y, belowFloorZ);
                if(!hasBlock(blockPos))
                    continue;

                MinimapBlock& block = getBlock(blockPos);
                block.markUsed();

                bool hasValidHDTexture = block.getHDTexture() != nullptr;
                bool needsRender = !hasValidHDTexture || block.needsHDUpdate();

                if(needsRender) {
                    queueBlockHD(block.shared_from_this(), blockPos, false);
                }

                const TexturePtr& tex = block.getHDTexture();
                if(tex) {
                    Rect src(0, 0, MMBLOCK_SIZE * 32, MMBLOCK_SIZE * 32);
                    Rect dest(xs + offsetPixels, ys + offsetPixels, MMBLOCK_SIZE * scale, MMBLOCK_SIZE * scale);
                    g_drawQueue->addTexturedRect(dest, tex, src);
                }
            }
        }
    }

    // Current floor.
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
            block.markUsed();

            int dx = std::abs(blockPos.x - mapCenter.x);
            int dy = std::abs(blockPos.y - mapCenter.y);

            bool processLive = (dx < MMBLOCK_SIZE / 2 && dy < MMBLOCK_SIZE / 2);

            bool hasValidHDTexture = block.getHDTexture() != nullptr;
            bool needsRender = !hasValidHDTexture || block.needsHDUpdate();

            if(needsRender) {
                queueBlockHD(block.shared_from_this(), blockPos, processLive);
            }

            const TexturePtr& tex = block.getHDTexture();
            if(tex) {
                Rect src(0, 0, MMBLOCK_SIZE * 32, MMBLOCK_SIZE * 32);
                Rect dest(xs, ys, MMBLOCK_SIZE * scale, MMBLOCK_SIZE * scale);
                g_drawQueue->addTexturedRect(dest, tex, src);
            }
        }
    }

    g_drawQueue->setClip(drawQueueStart, screenRect);
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
    std::vector<uint16> itemIds;

    if(tile) {
        minimapTile.color = tile->getMinimapColorByte();
        minimapTile.flags |= MinimapTileWasSeen;
        if(!tile->isWalkable(true))
            minimapTile.flags |= MinimapTileNotWalkable;
        if(!tile->isPathable())
            minimapTile.flags |= MinimapTileNotPathable;
        minimapTile.speed = std::min<int>((int)std::ceil(tile->getGroundSpeed() / 10.0f), 255);

        // HD: remember the real item ids of this tile so the HD texture can be
        // composited from their sprites. Does not affect the base MinimapTile/OTMM.
        auto things = tile->getThings();
        for(const ThingPtr& thing : things) {
            if(thing && thing->isItem()) {
                ItemPtr item = thing->static_self_cast<Item>();
                itemIds.push_back(item->getId());

                if(item->isSplash() || item->isFluidContainer()) {
                    itemIds.push_back(item->getSubType());
                }
            }
        }
    } else {
        minimapTile.color = 255;
        minimapTile.flags |= MinimapTileEmpty;
        minimapTile.speed = 1;
    }

    if(minimapTile != MinimapTile()) {
        Point offsetPos = getBlockOffset(Point(pos.x, pos.y));
        int tileX = pos.x - offsetPos.x;
        int tileY = pos.y - offsetPos.y;

        // Hold m_lock across the block mutation so the per-tile item data writes are
        // serialised with the async HD saver and the snapshot builder, which read it
        // under the same lock.
        std::lock_guard<std::mutex> lock(m_lock);
        auto& ptr = m_tileBlocks[pos.z][getBlockIndex(pos)];
        if(!ptr)
            ptr = std::make_shared<MinimapBlock>();
        ptr->updateTile(tileX, tileY, minimapTile);
        if(!itemIds.empty())
            ptr->setTileItems(tileX, tileY, itemIds);
        ptr->justSaw();
    }
}

const MinimapTile& Minimap::getTile(const Position& pos)
{
    static MinimapTile nulltile;
    if(pos.z <= Otc::MAX_Z && hasBlock(pos)) {
        MinimapBlock& block = getBlock(pos);
        Point offsetPos = getBlockOffset(Point(pos.x, pos.y));
        return block.getTile(pos.x - offsetPos.x, pos.y - offsetPos.y);
    }
    return nulltile;
}

std::pair<MinimapBlock_ptr, MinimapTile> Minimap::threadGetTile(const Position& pos) {
    std::lock_guard<std::mutex> lock(m_lock);
    static MinimapTile nulltile;

    if (pos.z <= Otc::MAX_Z && hasBlock(pos)) {
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
                Color color = *(uint32*)image->getPixel(x,y);
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
            if(!pos.isValid() || pos.z >= Otc::MAX_Z+1)
                break;

            MinimapBlock& block = getBlock(pos);
            ulong len = fin->getU16();
            ulong destLen = blockSize;
            fin->read(compressBuffer.data(), len);
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

        for(uint8_t z = 0; z <= Otc::MAX_Z; ++z) {
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

void Minimap::saveOtmmHD(const std::string& fileName)
{
    try {
        size_t minimapPos = fileName.find("/minimap/");
        if(minimapPos == std::string::npos) {
            minimapPos = fileName.find("\\minimap\\");
        }

        std::string baseName;
        std::string minimapDir = "/minimap";

        if(minimapPos != std::string::npos) {
            baseName = fileName.substr(minimapPos + 9);
        } else {
            baseName = fileName;
            size_t lastSlash = fileName.find_last_of("/\\");
            if(lastSlash != std::string::npos) {
                baseName = fileName.substr(lastSlash + 1);
            }
        }

        if(!baseName.empty() && baseName[0] == '/') {
            baseName = baseName.substr(1);
        }

        baseName = baseName.substr(0, baseName.find("_hd.otmm"));

        g_resources.makeDir("minimap");

        struct BlockData {
            Position pos;
            std::vector<uint16> tileItems[MMBLOCK_SIZE * MMBLOCK_SIZE];
            std::map<uint64_t, std::vector<uint16>> extendedItems;
        };

        for(uint8_t z = 0; z <= Otc::MAX_Z; ++z) {
            std::vector<BlockData> blocksToSave;
            bool floorHasDirtyBlocks = false;

            {
                std::lock_guard<std::mutex> lock(m_lock);

                for(auto& it : m_tileBlocks[z]) {
                    if(!it.second) continue;

                    MinimapBlock& block = *it.second;
                    if(!block.wasSeen())
                        continue;

                    int tilesWithItems = 0;
                    for(int i = 0; i < MMBLOCK_SIZE * MMBLOCK_SIZE; ++i) {
                        if(!block.m_tileItems[i].empty())
                            tilesWithItems++;
                    }
                    for(const auto& e : block.m_extendedTileItems)
                        if(!e.second.empty()) tilesWithItems++;

                    if(tilesWithItems == 0)
                        continue;

                    if(block.m_needsSave) {
                        floorHasDirtyBlocks = true;
                    }

                    BlockData data;
                    data.pos = getIndexPosition(it.first, z);
                    for(int i = 0; i < MMBLOCK_SIZE * MMBLOCK_SIZE; ++i) {
                        data.tileItems[i] = block.m_tileItems[i];
                    }
                    data.extendedItems = block.m_extendedTileItems;
                    blocksToSave.push_back(data);

                    if(block.m_needsSave) {
                        block.m_needsSave = false;
                    }
                }
            }

            if(blocksToSave.empty()) {
                continue;
            }

            if(!floorHasDirtyBlocks) {
                continue;
            }

            std::string floorFileName = minimapDir + "/" + baseName + "_floor" + std::to_string((int)z) + "_hd.otmm";

            FileStreamPtr fin;
            int retryCount = 0;
            const int MAX_RETRIES = 3;

            while(retryCount < MAX_RETRIES) {
                try {
                    fin = g_resources.createFile(floorFileName);
                    break;
                } catch(...) {
                    retryCount++;
                    if(retryCount >= MAX_RETRIES) {
                        throw;
                    }
                    std::this_thread::sleep_for(std::chrono::milliseconds(200));
                }
            }

            fin->addU32(OTMM_HD_SIGNATURE);
            fin->addU16(0);
            fin->addU16(OTMM_HD_VERSION);
            fin->addU32(0);

            fin->addString("OTMM HD 1.0");

            uint32 start = fin->tell();
            fin->seek(4);
            fin->addU16(start);
            fin->seek(start);

            std::ostringstream uncompressedStream;

            for(auto& blockData : blocksToSave) {
                int tilesWithItems = 0;
                for(int i = 0; i < MMBLOCK_SIZE * MMBLOCK_SIZE; ++i) {
                    if(!blockData.tileItems[i].empty())
                        tilesWithItems++;
                }
                // Count must match the write predicate below (which skips empty
                // vectors); otherwise the header over-counts and desyncs the stream.
                for(const auto& e : blockData.extendedItems)
                    if(!e.second.empty()) tilesWithItems++;

                uint16 bx = blockData.pos.x;
                uint16 by = blockData.pos.y;
                uint8 bz = blockData.pos.z;
                uint16 tilesWithItems16 = (uint16)tilesWithItems;
                uncompressedStream.write((char*)&bx, sizeof(uint16));
                uncompressedStream.write((char*)&by, sizeof(uint16));
                uncompressedStream.write((char*)&bz, sizeof(uint8));
                uncompressedStream.write((char*)&tilesWithItems16, sizeof(uint16));

                for(int ty = 0; ty < MMBLOCK_SIZE; ++ty) {
                    for(int tx = 0; tx < MMBLOCK_SIZE; ++tx) {
                        const std::vector<uint16>& items = blockData.tileItems[ty * MMBLOCK_SIZE + tx];
                        if(!items.empty()) {
                            uint8 xu8 = (uint8)tx;
                            uint8 yu8 = (uint8)ty;
                            uint16 size = (uint16)items.size();
                            uncompressedStream.write((char*)&xu8, sizeof(uint8));
                            uncompressedStream.write((char*)&yu8, sizeof(uint8));
                            uncompressedStream.write((char*)&size, sizeof(uint16));
                            for(uint16 itemId : items) {
                                uncompressedStream.write((char*)&itemId, sizeof(uint16));
                            }
                        }
                    }
                }

                for(const auto& extPair : blockData.extendedItems) {
                    uint64_t key = extPair.first;
                    const std::vector<uint16>& items = extPair.second;
                    if(!items.empty()) {
                        int16_t ex = (int16_t)(key >> 32);
                        int16_t ey = (int16_t)(key & 0xFFFF);
                        uint8 xu8 = (uint8_t)ex;
                        uint8 yu8 = (uint8_t)ey;
                        uint16 size = (uint16)items.size();
                        uncompressedStream.write((char*)&xu8, sizeof(uint8));
                        uncompressedStream.write((char*)&yu8, sizeof(uint8));
                        uncompressedStream.write((char*)&size, sizeof(uint16));
                        for(uint16 itemId : items) {
                            uncompressedStream.write((char*)&itemId, sizeof(uint16));
                        }
                    }
                }
            }

            std::string uncompressed = uncompressedStream.str();
            uLongf uncompressedSize = uncompressed.size();
            uLongf compressedSize = compressBound(uncompressedSize);
            std::vector<uint8_t> compressed(compressedSize);

            int result = compress2(compressed.data(), &compressedSize,
                                  (const Bytef*)uncompressed.data(), uncompressedSize,
                                  Z_DEFAULT_COMPRESSION);

            if(result != Z_OK) {
                throw stdext::exception("Compression failed");
            }

            fin->addU32(uncompressedSize);
            fin->addU32(compressedSize);
            fin->write(compressed.data(), compressedSize);

            fin->flush();
            fin->close();
        }

    } catch (stdext::exception& e) {
        g_logger.error(stdext::format("failed to save OTMM HD minimap: %s", e.what()));
    } catch (std::exception& e) {
        g_logger.error(stdext::format("failed to save OTMM HD minimap: %s", e.what()));
    }
}

void Minimap::saveOtmmHDAsync(const std::string& fileName)
{
    if(m_isSavingHD.exchange(true)) {
        return;
    }

    if(m_saveThread.joinable()) {
        m_saveThread.detach();
    }

    m_saveThread = std::thread([this, fileName]() {
        try {
            saveOtmmHD(fileName);
        } catch(std::exception& e) {
            g_logger.error(stdext::format("failed to save OTMM HD minimap: %s", e.what()));
        } catch(...) {
            g_logger.error("failed to save OTMM HD minimap: unknown error");
        }
        m_isSavingHD = false;
    });
}

bool Minimap::loadOtmmHD(const std::string& fileName)
{
    int waitCount = 0;
    while(m_isSavingHD && waitCount < 50) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        waitCount++;
    }

    if(m_isSavingHD) {
        return false;
    }

    size_t minimapPos = fileName.find("/minimap/");
    if(minimapPos == std::string::npos) {
        minimapPos = fileName.find("\\minimap\\");
    }

    std::string baseName;
    std::string minimapDir = "/minimap";

    if(minimapPos != std::string::npos) {
        baseName = fileName.substr(minimapPos + 9);
    } else {
        baseName = fileName;
        size_t lastSlash = fileName.find_last_of("/\\");
        if(lastSlash != std::string::npos) {
            baseName = fileName.substr(lastSlash + 1);
        }
    }

    if(!baseName.empty() && baseName[0] == '/') {
        baseName = baseName.substr(1);
    }

    baseName = baseName.substr(0, baseName.find("_hd.otmm"));

    bool loadedAny = false;

    for(uint8_t z = 0; z <= Otc::MAX_Z; ++z) {
        std::string floorFileName = minimapDir + "/" + baseName + "_floor" + std::to_string((int)z) + "_hd.otmm";

        try {
            FileStreamPtr fin = g_resources.openFile(floorFileName, g_game.getFeature(Otc::GameDontCacheFiles));
            if(!fin) {
                continue;
            }

            uint32 signature = fin->getU32();
            if(signature != OTMM_HD_SIGNATURE)
                stdext::throw_exception("invalid OTMM HD file");

            uint16 start = fin->getU16();
            uint16 version = fin->getU16();
            fin->getU32();

            if(version != OTMM_HD_VERSION)
                stdext::throw_exception("OTMM HD version not supported");

            fin->getString();
            fin->seek(start);

            uint32 uncompressedSize = fin->getU32();
            uint32 compressedSize = fin->getU32();
            std::vector<uint8_t> compressed(compressedSize);
            fin->read((char*)compressed.data(), compressedSize);

            std::vector<uint8_t> uncompressed(uncompressedSize);
            uLongf destLen = uncompressedSize;
            int result = uncompress(uncompressed.data(), &destLen,
                                   compressed.data(), compressedSize);

            if(result != Z_OK) {
                continue;
            }
            std::istringstream dataStream(std::string((char*)uncompressed.data(), uncompressedSize));

            while(dataStream.tellg() < (std::streampos)uncompressedSize) {
                Position pos;
                uint16 x, y;
                uint8 bz;
                dataStream.read((char*)&x, sizeof(uint16));
                dataStream.read((char*)&y, sizeof(uint16));
                dataStream.read((char*)&bz, sizeof(uint8));
                pos.x = x;
                pos.y = y;
                pos.z = bz;

                if(!pos.isValid() || pos.z >= Otc::MAX_Z+1)
                    break;

                uint16 tilesWithItems;
                dataStream.read((char*)&tilesWithItems, sizeof(uint16));

                MinimapBlock& block = getBlock(pos);

                for(uint16 i = 0; i < tilesWithItems; ++i) {
                    uint8 xu8, yu8;
                    uint16 itemCount;
                    dataStream.read((char*)&xu8, sizeof(uint8));
                    dataStream.read((char*)&yu8, sizeof(uint8));
                    dataStream.read((char*)&itemCount, sizeof(uint16));

                    int8_t tx = (int8_t)xu8;
                    int8_t ty = (int8_t)yu8;

                    std::vector<uint16> items;
                    items.reserve(itemCount);
                    for(uint16 j = 0; j < itemCount; ++j) {
                        uint16 itemId;
                        dataStream.read((char*)&itemId, sizeof(uint16));
                        items.push_back(itemId);
                    }

                    block.setTileItems(tx, ty, items, false);
                }

                if(tilesWithItems > 0) {
                    // Mark seen so a later saveOtmmHD re-emits these blocks
                    // (getBlock does not flag seen on its own).
                    block.justSaw();
                    block.m_hdNeedsUpdate = true;
                }
            }

            fin->close();

            loadedAny = true;

        } catch(stdext::exception&) {
            continue;
        }
    }

    return loadedAny;
}

void Minimap::renderThreadFunc()
{
    while(m_renderThreadRunning) {
        HDRenderJob job;
        {
            std::unique_lock<std::mutex> lock(m_renderMutex);

            m_renderCondition.wait(lock, [this] {
                return !m_renderQueue.empty() || !m_renderThreadRunning;
            });

            if(!m_renderThreadRunning)
                break;

            if(m_renderQueue.empty())
                continue;

            job = std::move(m_renderQueue.front());
            m_renderQueue.pop();
            m_renderQueueSize.store((int)m_renderQueue.size());
        }

        // From here the worker reads ONLY the immutable snapshot (job.items/job.hook)
        // plus read-only sprite/thingtype data — never g_map, m_tileBlocks or live
        // MinimapBlock data.
        const int tilePixelsHD = 32;
        const int margin = 3;
        const int elevationMargin = 2;
        const int gridSide = job.side;       // MMBLOCK_SIZE + 2*margin
        const int gridHeight = job.height;   // gridSide + elevationMargin

        ImagePtr imageHD(new Image(Size(gridSide * tilePixelsHD, gridHeight * tilePixelsHD)));

        // Box-filter downsample a source sprite image into the [baseX,baseX+regionW) x
        // [baseY,baseY+regionH) tile-aligned region of imageHD, alpha-compositing
        // (source-over) over whatever is already there. Premultiplied-alpha averaging
        // preserves anti-aliased edges so adjacent tiles connect instead of seaming.
        auto blitScaled = [&](const ImagePtr& src, int baseX, int baseY, int regionW, int regionH) {
            if(!src || regionW <= 0 || regionH <= 0)
                return;
            int fw = src->getWidth();
            int fh = src->getHeight();
            if(fw <= 0 || fh <= 0)
                return;
            for(int oy = 0; oy < regionH; ++oy) {
                int dY = baseY + oy;
                if(dY < 0 || dY >= gridHeight * tilePixelsHD)
                    continue;
                int sy0 = (oy * fh) / regionH;
                int sy1 = ((oy + 1) * fh) / regionH;
                if(sy1 <= sy0) sy1 = sy0 + 1;
                if(sy1 > fh) sy1 = fh;
                for(int ox = 0; ox < regionW; ++ox) {
                    int dX = baseX + ox;
                    if(dX < 0 || dX >= gridSide * tilePixelsHD)
                        continue;
                    int sx0 = (ox * fw) / regionW;
                    int sx1 = ((ox + 1) * fw) / regionW;
                    if(sx1 <= sx0) sx1 = sx0 + 1;
                    if(sx1 > fw) sx1 = fw;

                    uint32_t accR = 0, accG = 0, accB = 0, accA = 0;
                    int samples = 0;
                    for(int sy = sy0; sy < sy1; ++sy) {
                        for(int sx = sx0; sx < sx1; ++sx) {
                            uint8_t* p = src->getPixel(sx, sy);
                            if(!p) continue;
                            accR += (uint32_t)p[0] * p[3];
                            accG += (uint32_t)p[1] * p[3];
                            accB += (uint32_t)p[2] * p[3];
                            accA += p[3];
                            ++samples;
                        }
                    }
                    if(samples == 0 || accA == 0) continue;
                    uint8_t outA = (uint8_t)(accA / samples);
                    if(outA == 0) continue;
                    uint8_t outR = (uint8_t)(accR / accA);
                    uint8_t outG = (uint8_t)(accG / accA);
                    uint8_t outB = (uint8_t)(accB / accA);

                    uint8_t* dst = imageHD->getPixel(dX, dY);
                    if(!dst) continue;
                    int inv = 255 - outA;
                    dst[0] = (uint8_t)((outR * outA + dst[0] * inv) / 255);
                    dst[1] = (uint8_t)((outG * outA + dst[1] * inv) / 255);
                    dst[2] = (uint8_t)((outB * outA + dst[2] * inv) / 255);
                    dst[3] = (uint8_t)(outA + (dst[3] * inv) / 255);
                }
            }
        };

        for(int y = -margin - elevationMargin; y < MMBLOCK_SIZE + margin; ++y) {
            for(int x = -margin; x < MMBLOCK_SIZE + margin; ++x) {
                int gi = (y + margin + elevationMargin) * gridSide + (x + margin);
                if(gi < 0 || gi >= (int)job.items.size())
                    continue;

                const std::vector<uint16>& itemIds = job.items[gi];
                if(itemIds.empty()) continue;

                uint8_t tileHook = job.hook[gi];

                for(int pass = 0; pass < 2; ++pass) {
                    for(size_t idx = 0; idx < itemIds.size(); ++idx) {
                        uint16 itemId = itemIds[idx];

                        ThingTypePtr thingType = g_things.getThingType(itemId, ThingCategoryItem);
                        if(!thingType) continue;

                        bool isFullGround = thingType->isFullGround();

                        if(pass == 0 && !isFullGround) continue;
                        if(pass == 1 && isFullGround) continue;

                    int width = thingType->getWidth();
                    int height = thingType->getHeight();
                    int layers = thingType->getLayers();

                    int xPattern = 0, yPattern = 0, zPattern = 0;

                    if(thingType->isHangable()) {
                        // Hook orientation was resolved from the live map on the main
                        // thread (job.hook); the worker never touches g_map.
                        if(tileHook == 1) {
                            xPattern = thingType->getNumPatternX() >= 2 ? 1 : 0;
                        } else if(tileHook == 2) {
                            xPattern = thingType->getNumPatternX() >= 3 ? 2 : 0;
                        }
                    } else if(thingType->isSplash() || thingType->isFluidContainer()) {
                        if(idx + 1 < itemIds.size()) {
                            uint16 fluidType = itemIds[idx + 1];
                            int color = Otc::FluidTransparent;

                            switch(fluidType) {
                                case Otc::FluidNone: color = Otc::FluidTransparent; break;
                                case Otc::FluidWater: color = Otc::FluidBlue; break;
                                case Otc::FluidMana: color = Otc::FluidPurple; break;
                                case Otc::FluidBeer: color = Otc::FluidBrown; break;
                                case Otc::FluidOil: color = Otc::FluidBrown; break;
                                case Otc::FluidBlood: color = Otc::FluidRed; break;
                                case Otc::FluidSlime: color = Otc::FluidGreen; break;
                                case Otc::FluidMud: color = Otc::FluidBrown; break;
                                case Otc::FluidLemonade: color = Otc::FluidYellow; break;
                                case Otc::FluidMilk: color = Otc::FluidWhite; break;
                                case Otc::FluidWine: color = Otc::FluidPurple; break;
                                case Otc::FluidHealth: color = Otc::FluidRed; break;
                                case Otc::FluidUrine: color = Otc::FluidYellow; break;
                                case Otc::FluidRum: color = Otc::FluidBrown; break;
                                case Otc::FluidFruidJuice: color = Otc::FluidYellow; break;
                                case Otc::FluidCoconutMilk: color = Otc::FluidWhite; break;
                                case Otc::FluidTea: color = Otc::FluidBrown; break;
                                case Otc::FluidMead: color = Otc::FluidBrown; break;
                                default: color = Otc::FluidTransparent; break;
                            }

                            xPattern = (color % 4) % thingType->getNumPatternX();
                            yPattern = (color / 4) % thingType->getNumPatternY();
                            ++idx;
                        }
                    }

                    std::vector<int> sprites = thingType->getSprites();
                    const int numSprites = (int)sprites.size();

                    if(job.protobuf) {
                        // Protobuf (15.x) assets: each layer's sprite IS the full bounding
                        // square (all cells of a multi-tile thing), exactly as
                        // ThingType::drawToImage uses it. The old legacy w/h sub-sprite
                        // indexing fetched the wrong cells — that is what made walls and
                        // multi-tile items render broken ("tile by tile").
                        const int ss = job.spriteSize > 0 ? job.spriteSize : tilePixelsHD;
                        const int npx = thingType->getNumPatternX();
                        const int npy = thingType->getNumPatternY();
                        const int npz = thingType->getNumPatternZ();
                        const int xp = xPattern % npx;
                        const int yp = yPattern % npy;
                        const int zp = zPattern % npz;
                        for(int l = 0; l < layers; ++l) {
                            // Protobuf full-square sprite index — matches ThingType::
                            // getSpriteIndex(w=-1, h=-1, l, x, y, z, a=0).
                            int spriteIndex = ((zp * npy + yp) * npx + xp) * layers + l;
                            if(spriteIndex < 0 || spriteIndex >= numSprites) continue;
                            auto sit = job.spriteImages.find(sprites[spriteIndex]);
                            if(sit == job.spriteImages.end() || !sit->second) continue;
                            ImagePtr spriteImg = sit->second;

                            int cellsW = spriteImg->getWidth() / ss;  if(cellsW < 1) cellsW = 1;
                            int cellsH = spriteImg->getHeight() / ss; if(cellsH < 1) cellsH = 1;
                            // tile (x,y) is the bottom-right cell; the thing extends up/left.
                            int baseX = ((x - (cellsW - 1)) + margin) * tilePixelsHD;
                            int baseY = ((y - (cellsH - 1)) + margin + elevationMargin) * tilePixelsHD;
                            blitScaled(spriteImg, baseX, baseY, cellsW * tilePixelsHD, cellsH * tilePixelsHD);
                        }
                    } else {
                        // Legacy .spr assets: the bounding square is split into w*h 32px
                        // sub-sprites placed individually.
                        for(int l = 0; l < layers; ++l) {
                            for(int h = 0; h < height; ++h) {
                                for(int w = 0; w < width; ++w) {
                                    int spriteIndex = ((((l * thingType->getNumPatternZ() + zPattern) *
                                                        thingType->getNumPatternY() + yPattern) *
                                                        thingType->getNumPatternX() + xPattern) *
                                                        height + (height - h - 1)) * width + (width - w - 1);
                                    if(spriteIndex < 0 || spriteIndex >= numSprites) continue;
                                    auto sit = job.spriteImages.find(sprites[spriteIndex]);
                                    if(sit == job.spriteImages.end() || !sit->second) continue;
                                    int destTileX = x + margin + (-(width - 1) + w);
                                    int destTileY = y + margin + elevationMargin + (-(height - 1) + h);
                                    blitScaled(sit->second, destTileX * tilePixelsHD, destTileY * tilePixelsHD,
                                               tilePixelsHD, tilePixelsHD);
                                }
                            }
                        }
                    }

                    }
                }
            }
        }

        {
            std::lock_guard<std::mutex> lock(m_renderMutex);
            job.block->setPendingHDImage(imageHD);
            job.block->setRendering(false);
        }
    }
}

void Minimap::processCompletedRenders()
{
    std::unique_lock<std::mutex> lock(m_renderMutex, std::try_to_lock);
    if(!lock.owns_lock()) {
        return;
    }

    // Each HD texture is 2048x2048 (~16 MB); uploading too many per frame stutters the
    // main thread while running. Spread them out — they appear over a few frames.
    const int MAX_BLOCKS_PER_FRAME = 2;
    int processedCount = 0;

    for(int z = 0; z <= Otc::MAX_Z && processedCount < MAX_BLOCKS_PER_FRAME; ++z) {
        for(auto& it : m_tileBlocks[z]) {
            if(processedCount >= MAX_BLOCKS_PER_FRAME) break;

            MinimapBlock_ptr block = it.second;
            if(!block || !block->hasPendingHD()) continue;

            ImagePtr pendingHDImage = block->getPendingHDImage();
            if(!pendingHDImage) continue;

            const int tilePixelsHD = 32;
            const int margin = 3;
            const int elevationMargin = 2;
            const int blockSizePixels = MMBLOCK_SIZE * tilePixelsHD;
            const int marginPixelsX = margin * tilePixelsHD;
            const int marginPixelsY = (margin + elevationMargin) * tilePixelsHD;

            ImagePtr croppedImage(new Image(Size(blockSizePixels, blockSizePixels)));

            const size_t bytesPerLine = blockSizePixels * 4;
            for(int y = 0; y < blockSizePixels; ++y) {
                uint8_t* srcLine = pendingHDImage->getPixel(marginPixelsX, y + marginPixelsY);
                uint8_t* dstLine = croppedImage->getPixel(0, y);
                if(srcLine && dstLine) {
                    memcpy(dstLine, srcLine, bytesPerLine);
                }
            }

            block->setPendingHDImage(nullptr);

            TexturePtr texture = TexturePtr(new Texture(croppedImage));
            texture->setSmooth(true);
            block->m_hdTexture = texture;
            block->m_hdNeedsUpdate = false;

            processedCount++;
        }
    }
}
