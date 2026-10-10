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
#include "game.h"
#include "gameconfig.h"
#include "spritemanager.h"
#include "item.h"
#include "map.h"

#include <framework/graphics/image.h>
#include <framework/graphics/texture.h>
#include <framework/graphics/painter.h>
#include <framework/graphics/framebuffermanager.h>
#include <framework/core/resourcemanager.h>
#include <framework/core/filestream.h>
#include <framework/core/asyncdispatcher.h>
#include <sstream>
#include <chrono>
#include <cmath>
#include <zlib.h>

#include <framework/util/stats.h>

Minimap g_minimap;

void MinimapBlock::clean()
{
    m_tiles.fill(MinimapTile());
    m_texture.reset();
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
}

void Minimap::terminate()
{
    clean();
    clearSatellitePack();
    // Application deinit has already joined the async worker before client teardown.
    std::lock_guard<std::mutex> lock(m_satelliteLock);
    m_satelliteDecodes.clear();
}

void Minimap::clean()
{
    clearSpriteCache();
    clearSatelliteTextures(); // Keep the disk index: logout must not erase HD coverage.
    std::lock_guard<std::mutex> lock(m_lock);
    for (auto& tileBlocks : m_tileBlocks)
        tileBlocks.clear();
}

void Minimap::draw(const Rect& screenRect, const Position& mapCenter, float scale, const Color& color)
{
    if(screenRect.isEmpty())
        return;

    Rect mapRect = calcMapRect(screenRect, mapCenter, scale);
    g_drawQueue->addFilledRect(screenRect, color);

    if(MMBLOCK_SIZE*scale <= 1 || !mapCenter.isMapPosition() || mapCenter.z > g_gameConfig.getMapMaxZ()) {
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

    g_drawQueue->setClip(drawQueueStart, screenRect);
}

bool Minimap::loadSatellitePack(const std::string& directory)
{
    const std::string index = directory + "/index.txt";
    if (!g_resources.fileExists(index) || !g_things.isDatLoaded() || !g_sprites.isLoaded())
        return false;
    try {
        auto file = g_resources.openFile(index, true);
        if (file->size() > 8 * 1024 * 1024)
            stdext::throw_exception("satellite index exceeds its size limit");
        std::string contents(file->size(), '\0');
        if (file->read(contents.data(), contents.size()) != contents.size())
            stdext::throw_exception("truncated satellite index");
        std::istringstream input(contents);
        std::string magic;
        int version, chunkSize, pixelsPerTile;
        uint32 datSignature, sprSignature;
        size_t count;
        if (!(input >> magic >> version >> chunkSize >> pixelsPerTile >> datSignature >> sprSignature >> count) ||
            magic != "ASTRAHD" || version != 1 || chunkSize != 16 || pixelsPerTile != 32 || count == 0 || count > 100000)
            stdext::throw_exception("invalid satellite index header");
        if (datSignature != g_things.getDatSignature() || sprSignature != g_sprites.getSignature())
            stdext::throw_exception("satellite pack was generated with different DAT/SPR assets");
        std::unordered_map<uint64_t, SatelliteChunk> chunks;
        std::set<int> levels;
        for (size_t i = 0; i < count; ++i) {
            int level, x, y, z;
            std::string fileName;
            if (!(input >> level >> x >> y >> z >> fileName) || level < 1 || level > 1024 || (level & (level - 1)) ||
                x < 0 || y < 0 || x > 65535 || y > 65535 || z < 0 || z > g_gameConfig.getMapMaxZ() ||
                x % (16 * level) || y % (16 * level))
                stdext::throw_exception("invalid satellite chunk coordinates");
            const auto expected = stdext::format("satellite-%d-%d-%d-%d.png", level, x, y, z);
            if (fileName != expected || !chunks.emplace(satelliteKey(level, x, y, z), SatelliteChunk{directory + "/" + fileName}).second)
                stdext::throw_exception("invalid or duplicate satellite filename");
            levels.insert(level);
        }
        std::string extra;
        if (input >> extra)
            stdext::throw_exception("trailing satellite index data");
        std::lock_guard<std::mutex> lock(m_satelliteLock);
        cancelSatelliteDecodes();
        m_satelliteTextures.clear();
        m_satelliteOrder.clear();
        m_satelliteChunks = std::move(chunks);
        m_satelliteLevels = std::move(levels);
        m_satelliteDatSignature = datSignature;
        m_satelliteSprSignature = sprSignature;
        g_logger.info(stdext::format("[HD Minimap] Indexed %u persistent satellite chunks (textures loaded on demand)", m_satelliteChunks.size()));
        return true;
    } catch (const std::exception& e) {
        g_logger.error(stdext::format("[HD Minimap] Could not load '%s': %s", index, e.what()));
        return false; // Preserve a previously valid index on failed replacement.
    }
}

void Minimap::clearSatelliteTextures()
{
    std::lock_guard<std::mutex> lock(m_satelliteLock);
    cancelSatelliteDecodes();
    m_satelliteTextures.clear();
    m_satelliteOrder.clear();
}

void Minimap::clearSatellitePack()
{
    std::lock_guard<std::mutex> lock(m_satelliteLock);
    cancelSatelliteDecodes();
    m_satelliteTextures.clear();
    m_satelliteOrder.clear();
    m_satelliteChunks.clear();
    m_satelliteLevels.clear();
}

bool Minimap::hasSatellitePack()
{
    std::lock_guard<std::mutex> lock(m_satelliteLock);
    return !m_satelliteChunks.empty() && m_satelliteDatSignature == g_things.getDatSignature() &&
        m_satelliteSprSignature == g_sprites.getSignature();
}

size_t Minimap::getSatelliteChunkCount()
{
    std::lock_guard<std::mutex> lock(m_satelliteLock);
    return m_satelliteChunks.size();
}

size_t Minimap::getSatelliteTextureCount()
{
    std::lock_guard<std::mutex> lock(m_satelliteLock);
    return m_satelliteTextures.size();
}

size_t Minimap::getSatelliteDecodeCount()
{
    std::lock_guard<std::mutex> lock(m_satelliteLock);
    return m_satelliteDecodes.size(); // Includes completed results not collected yet.
}

int Minimap::satelliteLevel(float scale)
{
    if (m_satelliteLevels.empty() || scale <= 0 || !std::isfinite(scale))
        return 0;
    // Use the coarsest pre-rendered image that is not stretched past 1:1.
    int result = *m_satelliteLevels.begin();
    for (int level : m_satelliteLevels) {
        if (level > 32.f / scale)
            break;
        result = level;
    }
    return result;
}

int Minimap::satelliteViewLevel(const Rect& mapRect, float scale)
{
    int level = satelliteLevel(scale);
    if (!level) return 0;
    // Reserve for partially visible chunks too. A view must fit the same cache
    // used by satelliteTexture, or its own chunks churn on every frame.
    while (int64_t(mapRect.width() / (16 * level) + 2) *
           (mapRect.height() / (16 * level) + 2) > SatelliteTextureLimit) {
        const auto next = m_satelliteLevels.upper_bound(level);
        if (next == m_satelliteLevels.end()) return 0;
        level = *next;
    }
    return level;
}

int Minimap::getSatelliteViewLevel(const Size& viewSize, float scale)
{
    if (viewSize.isEmpty() || scale <= 0 || !std::isfinite(scale)) return 0;
    std::lock_guard<std::mutex> lock(m_satelliteLock);
    return satelliteViewLevel(calcMapRect(Rect(0, 0, viewSize.width(), viewSize.height()),
                                         Position(32768, 32768, 0), scale), scale);
}

size_t Minimap::finishSatelliteDecodes()
{
    for (auto it = m_satelliteDecodes.begin(); it != m_satelliteDecodes.end();) {
        if (it->image.wait_for(std::chrono::seconds(0)) != std::future_status::ready) {
            ++it;
            continue;
        }
        ImagePtr image;
        try {
            image = it->image.get(); // Ready only: never waits in the draw path.
        } catch (const std::exception& e) {
            if (!*it->cancelled)
                g_logger.error(stdext::format("[HD Minimap] Decode task failed: %s", e.what()));
        }
        const auto cached = m_satelliteTextures.find(it->key);
        if (!*it->cancelled && cached != m_satelliteTextures.end()) {
            if (image)
                cached->second.texture = std::make_shared<Texture>(image, false, false, true);
            else if (auto failed = m_satelliteChunks.find(it->key); failed != m_satelliteChunks.end())
                failed->second.failed = true;
        }
        it = m_satelliteDecodes.erase(it);
    }
    return m_satelliteDecodes.size();
}

void Minimap::cancelSatelliteDecodes()
{
    for (const auto& decode : m_satelliteDecodes)
        *decode.cancelled = true;
    finishSatelliteDecodes(); // Discard already-completed results immediately.
    // Keep ownership/admission slots until each task finishes. Erasing a future
    // does not remove its promise/closure from the dispatcher's global queue.
}

TexturePtr Minimap::satelliteTexture(uint64_t key)
{
    // Harvest completed work even after its chunk leaves the viewport. A ready
    // future must not permanently occupy one of the four pending decode slots.
    const size_t pending = finishSatelliteDecodes();
    auto chunk = m_satelliteChunks.find(key);
    if (chunk == m_satelliteChunks.end() || chunk->second.failed)
        return nullptr;
    auto cached = m_satelliteTextures.find(key);
    if (cached == m_satelliteTextures.end()) {
        if (pending >= SatelliteDecodeLimit)
            return nullptr; // Never enqueue an entire world of background work.
        while (m_satelliteTextures.size() >= SatelliteTextureLimit) {
            const auto evicted = m_satelliteOrder.front();
            for (const auto& decode : m_satelliteDecodes)
                if (decode.key == evicted) *decode.cancelled = true;
            m_satelliteTextures.erase(evicted);
            m_satelliteOrder.pop_front();
        }
        m_satelliteOrder.push_back(key);
        const auto path = chunk->second.file;
        const auto cancelled = std::make_shared<std::atomic<bool>>(false);
        // The worker owns only a path, never a Map/Minimap/GL object. Clearing
        // or replacing the index during logout cannot expose freed state.
        auto future = g_asyncDispatcher.schedule([path, cancelled]() -> ImagePtr {
            try {
                if (*cancelled) return nullptr;
                // Reject oversized/corrupt image headers before allocating decoded pixels.
                const auto data = g_resources.readFileContentsBounded(path, 4 * 1024 * 1024);
                if (*cancelled) return nullptr;
                if (data.size() < 24 || data.size() > 4 * 1024 * 1024 ||
                    data.compare(0, 8, "\x89PNG\r\n\x1a\n", 8) != 0 || data.compare(12, 4, "IHDR") != 0 ||
                    data.compare(16, 8, "\0\0\2\0\0\0\2\0", 8) != 0)
                    stdext::throw_exception("expected a bounded 512x512 PNG header");
                // The APNG loader allocates frames before isAnimated() can reject
                // them. Reject animation/truncated chunks before entering it.
                size_t offset = 8;
                bool ended = false;
                while (offset + 12 <= data.size()) {
                    const auto* bytes = reinterpret_cast<const uint8_t*>(data.data() + offset);
                    const uint32_t length = (uint32_t(bytes[0]) << 24) | (uint32_t(bytes[1]) << 16) |
                                            (uint32_t(bytes[2]) << 8) | bytes[3];
                    if (length > data.size() - offset - 12 ||
                        data.compare(offset + 4, 4, "acTL") == 0 ||
                        data.compare(offset + 4, 4, "fcTL") == 0 ||
                        data.compare(offset + 4, 4, "fdAT") == 0 ||
                        (data.compare(offset + 4, 4, "IHDR") == 0 && (offset != 8 || length != 13)))
                        stdext::throw_exception("expected a complete static PNG");
                    offset += size_t(length) + 12;
                    if (data.compare(offset - length - 8, 4, "IEND") == 0) {
                        ended = length == 0 && offset == data.size();
                        break;
                    }
                }
                if (!ended) stdext::throw_exception("missing PNG end marker");
                auto image = Image::loadPNG(data.data(), data.size());
                if (!image || image->getSize() != Size(512, 512) || image->isAnimated())
                    stdext::throw_exception("expected a static 512x512 PNG");
                return *cancelled ? nullptr : image;
            } catch (const std::exception& e) {
                g_logger.error(stdext::format("[HD Minimap] Cannot decode '%s': %s", path, e.what()));
                return nullptr;
            }
        });
        m_satelliteDecodes.push_back({key, std::move(future), cancelled});
        cached = m_satelliteTextures.emplace(key, SatelliteTexture{nullptr, std::prev(m_satelliteOrder.end())}).first;
    }
    auto& value = cached->second;
    m_satelliteOrder.splice(m_satelliteOrder.end(), m_satelliteOrder, value.order);
    return value.texture;
}

bool Minimap::hasSatelliteTile(const Position& pos)
{
    if (!pos.isMapPosition()) return false;
    std::lock_guard<std::mutex> lock(m_satelliteLock);
    return m_satelliteChunks.count(satelliteKey(1, pos.x - pos.x % 16, pos.y - pos.y % 16, pos.z)) != 0;
}

bool Minimap::preloadSatelliteTile(const Position& pos, float scale)
{
    if (!pos.isMapPosition()) return false;
    std::lock_guard<std::mutex> lock(m_satelliteLock);
    const auto level = satelliteLevel(scale);
    if (!level) return false;
    const auto size = 16 * level;
    return bool(satelliteTexture(satelliteKey(level, pos.x - pos.x % size, pos.y - pos.y % size, pos.z)));
}

void Minimap::drawSatellite(const Rect& screenRect, const Position& mapCenter, float scale)
{
    if (screenRect.isEmpty() || !mapCenter.isMapPosition() || mapCenter.z > g_gameConfig.getMapMaxZ())
        return;
    std::lock_guard<std::mutex> lock(m_satelliteLock);
    if (m_satelliteDatSignature != g_things.getDatSignature() || m_satelliteSprSignature != g_sprites.getSignature())
        return;
    const auto mapRect = calcMapRect(screenRect, mapCenter, scale);
    const int level = satelliteViewLevel(mapRect, scale);
    if (!level) return;
    const auto size = 16 * level;
    const int left = std::max(0, mapRect.left()) / size * size;
    const int top = std::max(0, mapRect.top()) / size * size;
    const int right = std::min(65535, mapRect.right());
    const int bottom = std::min(65535, mapRect.bottom());
    const Point off = Point((mapRect.size() * scale).toPoint() - screenRect.size().toPoint()) / 2;
    const Point origin = screenRect.topLeft() - off;
    const auto start = g_drawQueue->size();
    for (int y = top; y <= bottom; y += size) {
        for (int x = left; x <= right; x += size) {
            auto texture = satelliteTexture(satelliteKey(level, x, y, mapCenter.z));
            if (!texture) continue;
            const int dx = origin.x + std::lround((x - mapRect.left()) * scale);
            const int dy = origin.y + std::lround((y - mapRect.top()) * scale);
            const int endX = origin.x + std::lround((x + size - mapRect.left()) * scale);
            const int endY = origin.y + std::lround((y + size - mapRect.top()) * scale);
            g_drawQueue->addTexturedRect(Rect(dx, dy, endX - dx, endY - dy), texture, Rect(0, 0, 512, 512));
        }
    }
    g_drawQueue->setClip(start, screenRect);
}

int Minimap::exportSatelliteBase(const std::string& directory)
{
    if (g_game.isOnline() || !g_things.isDatLoaded() || !g_things.isOtbLoaded() || !g_sprites.isLoaded())
        stdext::throw_exception("satellite export requires offline mode and the matching DAT/SPR/OTB");
    if (g_resources.directoryExists(directory))
        stdext::throw_exception("satellite export destination already exists; use a new directory");
    if (!g_resources.makeDir(directory))
        stdext::throw_exception("cannot create satellite export directory");
    constexpr int chunkSize = 16;
    const int pixels = g_sprites.spriteSize();
    std::set<uint64_t> chunks;
    int leftExtent = 0, topExtent = 0, rightExtent = 0, bottomExtent = 0;
    for (const auto& tile : g_map.getTiles()) {
        const auto pos = tile->getPosition();
        if (!pos.isMapPosition() || tile->getItems().empty()) continue;
        chunks.insert(satelliteKey(1, pos.x / chunkSize * chunkSize, pos.y / chunkSize * chunkSize, pos.z));
        for (const auto& item : tile->getItems()) {
            if (!item->getId()) stdext::throw_exception("invalid item in offline map");
            const auto disp = item->getDisplacement() * g_sprites.getOffsetFactor();
            const int itemLeft = (item->getWidth() - 1) * pixels + disp.x + std::ceil(Otc::MAX_ELEVATION * g_sprites.getOffsetFactor());
            const int itemTop = (item->getHeight() - 1) * pixels + disp.y + std::ceil(Otc::MAX_ELEVATION * g_sprites.getOffsetFactor());
            leftExtent = std::max(leftExtent, itemLeft);
            topExtent = std::max(topExtent, itemTop);
            rightExtent = std::max(rightExtent, -disp.x);
            bottomExtent = std::max(bottomExtent, -disp.y);
            const int minX = std::max(0, pos.x - (std::max(0, itemLeft) + pixels - 1) / pixels);
            const int minY = std::max(0, pos.y - (std::max(0, itemTop) + pixels - 1) / pixels);
            const int maxX = std::min(65535, pos.x + (std::max(0, -disp.x) + pixels - 1) / pixels);
            const int maxY = std::min(65535, pos.y + (std::max(0, -disp.y) + pixels - 1) / pixels);
            for (int y = minY / chunkSize * chunkSize; y <= maxY; y += chunkSize)
                for (int x = minX / chunkSize * chunkSize; x <= maxX; x += chunkSize)
                    chunks.insert(satelliteKey(1, x, y, pos.z));
        }
    }
    if (chunks.empty()) stdext::throw_exception("offline map contains no renderable tiles");
    // A bounded halo covers displaced/oversized sprites across chunk borders.
    const int haloRight = (leftExtent + pixels - 1) / pixels;
    const int haloBottom = (topExtent + pixels - 1) / pixels;
    const int haloLeft = (rightExtent + pixels - 1) / pixels;
    const int haloTop = (bottomExtent + pixels - 1) / pixels;
    if (std::max({haloLeft, haloTop, haloRight, haloBottom}) > 32)
        stdext::throw_exception("sprite displacement exceeds the satellite export halo limit");
    std::ostringstream index;
    index << "ASTRAHDBASE 1 16 " << pixels << ' ' << g_things.getDatSignature() << ' ' << g_sprites.getSignature() << ' ' << chunks.size() << '\n';
    int written = 0;
    for (const auto key : chunks) {
        const int x = key & 0xffff, y = (key >> 16) & 0xffff, z = (key >> 32) & 0xff;
        auto image = std::make_shared<Image>(Size(chunkSize * pixels, chunkSize * pixels));
        std::vector<TilePtr> tiles;
        for (int ty = std::max(0, y - haloTop); ty <= std::min(65535, y + chunkSize - 1 + haloBottom); ++ty)
            for (int tx = std::max(0, x - haloLeft); tx <= std::min(65535, x + chunkSize - 1 + haloRight); ++tx)
                if (auto tile = g_map.getTile(Position(tx, ty, z))) tiles.push_back(tile);
        for (int pass = 0; pass < 3; ++pass) {
            for (const auto& tile : tiles) {
                const auto pos = tile->getPosition();
                const Point dest((pos.x - x) * pixels, (pos.y - y) * pixels);
                int elevation = 0;
                const auto items = tile->getItems();
                if (pass == 2) {
                    // Top items precede common items in the tile's stack order.
                    // Calculate the complete underlying elevation before drawing.
                    for (const auto& item : items)
                        if (!item->isHidden() && !item->isOnTop())
                            elevation = std::min<int>(elevation + item->getElevation(), Otc::MAX_ELEVATION);
                }
                for (const auto& item : items) {
                    if (item->isHidden()) continue;
                    const bool base = item->isGround() || item->isGroundBorder() || item->isOnBottom();
                    const bool drawItem = (pass == 0 && item->isGround()) || (pass == 1 && base && !item->isGround()) || (pass == 2 && item->isOnTop());
                    if (drawItem) item->drawToImage(dest - elevation * g_sprites.getOffsetFactor(), image);
                    if (base && pass != 2)
                        elevation = std::min<int>(elevation + item->getElevation(), Otc::MAX_ELEVATION);
                }
                if (pass == 1) {
                    for (auto it = items.rbegin(); it != items.rend(); ++it) {
                        const auto& item = *it;
                        if (item->isHidden() || item->isGround() || item->isGroundBorder() || item->isOnBottom() || item->isOnTop()) continue;
                        item->drawToImage(dest - elevation * g_sprites.getOffsetFactor(), image);
                        elevation = std::min<int>(elevation + item->getElevation(), Otc::MAX_ELEVATION);
                    }
                }
            }
        }
        const auto name = stdext::format("satellite-1-%d-%d-%d.png", x, y, z);
        image->savePNG(directory + "/" + name);
        index << "1 " << x << ' ' << y << ' ' << z << ' ' << name << '\n';
        if (++written % 100 == 0 || written == chunks.size())
            g_logger.info(stdext::format("[HD EXPORT] Base chunks: %d/%u", written, chunks.size()));
    }
    if (!g_resources.writeFileContents(directory + "/index.base.txt", index.str()))
        stdext::throw_exception("could not write satellite export index");
    return written;
}

void Minimap::clearSpriteCacheLocked()
{
    m_spriteTiles.clear();
    m_spriteOrder.clear();
    m_spriteItemCount = 0;
}

void Minimap::clearSpriteCache()
{
    std::lock_guard<std::mutex> lock(m_spriteLock);
    clearSpriteCacheLocked();
}

size_t Minimap::getSpriteCacheTileCount()
{
    std::lock_guard<std::mutex> lock(m_spriteLock);
    return m_spriteTiles.size();
}

size_t Minimap::getSpriteCacheItemCount()
{
    std::lock_guard<std::mutex> lock(m_spriteLock);
    return m_spriteItemCount;
}

uint64_t Minimap::getSpriteTileLookupCount()
{
    std::lock_guard<std::mutex> lock(m_spriteLock);
    return m_spriteTileLookupCount;
}

unsigned Minimap::getSpriteViewCount()
{
    std::lock_guard<std::mutex> lock(m_spriteLock);
    return m_spriteViews;
}

void Minimap::addSpriteView()
{
    std::lock_guard<std::mutex> lock(m_spriteLock);
    ++m_spriteViews;
    m_spriteCacheEnabled = true;
}

void Minimap::removeSpriteView()
{
    bool stopped;
    {
        std::lock_guard<std::mutex> lock(m_spriteLock);
        if (m_spriteViews > 0)
            --m_spriteViews;
        stopped = m_spriteViews == 0;
        if (stopped) {
            m_spriteCacheEnabled = false;
            clearSpriteCacheLocked();
        }
    }
    if (stopped) clearSatelliteTextures(); // Off means no retained HD image cache.
}

void Minimap::eraseSpriteTile(uint64_t key)
{
    const auto found = m_spriteTiles.find(key);
    if (found == m_spriteTiles.end())
        return;
    m_spriteItemCount -= found->second.items.size();
    m_spriteOrder.erase(found->second.order);
    m_spriteTiles.erase(found);
}

void Minimap::updateSpriteTile(const Position& pos, const TilePtr& tile)
{
    // No cloning/allocation in classic mode. Keep explored terrain when the
    // server removes a tile from awareness; a real empty tile clears its snapshot.
    if (!m_spriteCacheEnabled)
        return;

    std::vector<ItemPtr> source;
    if (tile)
        for (const auto& thing : tile->getThings()) {
            if (thing->isItem() && !thing->isHidden())
                source.push_back(thing->static_self_cast<Item>());
        }

    const auto key = spriteTileKey(pos);
    std::lock_guard<std::mutex> lock(m_spriteLock);
    if (!m_spriteCacheEnabled)
        return;
    constexpr size_t maxTiles = 8192;
    constexpr size_t maxItems = 32768;
    constexpr size_t maxItemsPerTile = 64;
    const auto found = m_spriteTiles.find(key);
    if (!tile && found != m_spriteTiles.end())
        return; // Preserve explored terrain after leaving server awareness.
    if (source.size() > maxItemsPerTile)
        source.clear(); // Bounded absence sentinel, not an oversized snapshot.
    if (found != m_spriteTiles.end() && found->second.items.size() == source.size()) {
        const auto& previous = found->second.items;
        bool unchanged = true;
        for (size_t i = 0; i < source.size(); ++i) {
            if (previous[i]->getId() != source[i]->getId() ||
                previous[i]->getCountOrSubType() != source[i]->getCountOrSubType()) {
                unchanged = false;
                break;
            }
        }
        if (unchanged) {
            m_spriteOrder.splice(m_spriteOrder.end(), m_spriteOrder, found->second.order);
            return; // Creature movement does not require new terrain snapshots.
        }
    }

    std::vector<ItemPtr> snapshots;
    snapshots.reserve(source.size());
    for (const auto& item : source) {
        auto snapshot = Item::create(item->getId(), item->getCountOrSubType());
        snapshot->setPosition(pos); // Ground and fluid patterns use tile position/subtype.
        snapshots.push_back(std::move(snapshot));
    }
    eraseSpriteTile(key);
    while (m_spriteTiles.size() >= maxTiles || m_spriteItemCount + snapshots.size() > maxItems)
        eraseSpriteTile(m_spriteOrder.front()); // O(1) LRU eviction.
    m_spriteOrder.push_back(key);
    m_spriteItemCount += snapshots.size();
    m_spriteTiles.emplace(key, SpriteTile{std::move(snapshots), std::prev(m_spriteOrder.end())});
}

void Minimap::drawSprites(const Rect& screenRect, const Position& mapCenter, float scale, const Color& color, bool liveTerrain)
{
    // OTMM remains the background, pathfinding source and distant/unexplored fallback.
    draw(screenRect, mapCenter, scale, color);
    drawSatellite(screenRect, mapCenter, scale);
    if (screenRect.isEmpty() || !mapCenter.isMapPosition() ||
        mapCenter.z > g_gameConfig.getMapMaxZ() || scale < 2 || !m_spriteCacheEnabled || !liveTerrain)
        return;

    const auto mapRect = calcMapRect(screenRect, mapCenter, scale);
    // Include neighbors whose oversized sprites extend into the viewport.
    const int left = std::max(0, mapRect.left());
    const int top = std::max(0, mapRect.top());
    const int right = std::min(65535, mapRect.right() + 4);
    const int bottom = std::min(65535, mapRect.bottom() + 4);
    if (int64_t(right - left + 1) * (bottom - top + 1) > 4096)
        return; // Wide views stay cheap instead of rendering the entire world.

    prepareSpriteView(screenRect.size(), mapCenter, scale);

    struct FrameTile { Point dest; std::vector<ItemPtr> items; };
    std::vector<FrameTile> tiles;
    const int spriteSize = g_sprites.spriteSize();
    if (spriteSize <= 0)
        return;
    {
        std::lock_guard<std::mutex> lock(m_spriteLock);
        size_t itemCount = 0;
        for (int y = top; y <= bottom; ++y) {
            for (int x = left; x <= right; ++x) {
                const auto found = m_spriteTiles.find(spriteTileKey(Position(x, y, mapCenter.z)));
                if (found == m_spriteTiles.end() || found->second.items.empty())
                    continue;
                itemCount += found->second.items.size();
                if (itemCount > 8192)
                    return; // Bound draw work even for unusually dense maps.
                tiles.push_back({Point((x - mapRect.left()) * spriteSize,
                                           (y - mapRect.top()) * spriteSize), found->second.items});
                m_spriteOrder.splice(m_spriteOrder.end(), m_spriteOrder, found->second.order);
            }
        }
    }

    const size_t start = g_drawQueue->size();
    // Match Tenkaiser's terrain layers: ground, borders/bottom/common, then top.
    // Independent item snapshots never draw creatures, effects, lights or animations.
    for (int pass = 0; pass < 3; ++pass) {
        for (const auto& tile : tiles) {
            int elevation = 0;
            if (pass == 2) {
                for (const auto& item : tile.items)
                    if (!item->isOnTop())
                        elevation = std::min<int>(elevation + item->getElevation(), Otc::MAX_ELEVATION);
            }
            for (const auto& item : tile.items) {
                const bool base = item->isGround() || item->isGroundBorder() || item->isOnBottom();
                const bool drawItem = (pass == 0 && item->isGround()) ||
                    (pass == 1 && base && !item->isGround()) || (pass == 2 && item->isOnTop());
                if (drawItem)
                    item->draw(tile.dest - elevation * g_sprites.getOffsetFactor(), false, nullptr);
                if (base && pass != 2)
                    elevation = std::min<int>(elevation + item->getElevation(), Otc::MAX_ELEVATION);
            }
            if (pass == 1) {
                for (auto it = tile.items.rbegin(); it != tile.items.rend(); ++it) {
                    const auto& item = *it;
                    if (item->isGround() || item->isGroundBorder() || item->isOnBottom() || item->isOnTop())
                        continue;
                    item->draw(tile.dest - elevation * g_sprites.getOffsetFactor(), false, nullptr);
                    elevation = std::min<int>(elevation + item->getElevation(), Otc::MAX_ELEVATION);
                }
            }
        }
    }
    const Point off = Point((mapRect.size() * scale).toPoint() - screenRect.size().toPoint()) / 2;
    g_drawQueue->scaleTexturedRects(start, screenRect.topLeft() - off, scale / spriteSize);
    g_drawQueue->setClip(start, screenRect);
}

void Minimap::prepareSpriteView(const Size& viewSize, const Position& mapCenter, float scale)
{
    if (viewSize.isEmpty() || !mapCenter.isMapPosition() ||
        mapCenter.z > g_gameConfig.getMapMaxZ() || !std::isfinite(scale) || scale < 2 || !m_spriteCacheEnabled)
        return;
    const auto mapRect = calcMapRect(Rect(0, 0, viewSize.width(), viewSize.height()), mapCenter, scale);
    const int left = std::max(0, mapRect.left()), top = std::max(0, mapRect.top());
    const int right = std::min(65535, mapRect.right() + 4), bottom = std::min(65535, mapRect.bottom() + 4);
    if (int64_t(right - left + 1) * (bottom - top + 1) > 4096) return;
    std::vector<Position> missing;
    {
        std::lock_guard<std::mutex> lock(m_spriteLock);
        for (int y = top; y <= bottom; ++y) {
            for (int x = left; x <= right; ++x) {
                const Position pos(x, y, mapCenter.z);
                if (m_spriteTiles.find(spriteTileKey(pos)) == m_spriteTiles.end())
                    missing.push_back(pos);
            }
        }
    }
    // Enabling HD while standing still (or cleaning OTMM on login) needs no step.
    for (const auto& pos : missing)
        updateSpriteTile(pos, g_map.getTile(pos));
    {
        std::lock_guard<std::mutex> lock(m_spriteLock);
        m_spriteTileLookupCount += missing.size();
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
    if (!pos.isMapPosition() || pos.z > g_gameConfig.getMapMaxZ())
        return;
    updateSpriteTile(pos, tile);
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
    }
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
    return loadOtmmImpl(fileName, false);
}

bool Minimap::mergeOtmm(const std::string& fileName)
{
    return loadOtmmImpl(fileName, true);
}

bool Minimap::loadOtmmImpl(const std::string& fileName, bool preserveUnknown)
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
                stdext::throw_exception("corrupt compressed minimap block");

            if (preserveUnknown) {
                for (size_t i = 0; i < block.getTiles().size(); ++i) {
                    MinimapTile incoming;
                    memcpy(&incoming, decompressBuffer.data() + i * sizeof(MinimapTile), sizeof(MinimapTile));
                    if (incoming.hasFlag(MinimapTileWasSeen) || incoming.color != 255)
                        block.getTiles()[i] = incoming;
                }
            } else {
                memcpy((uchar*)&block.getTiles(), decompressBuffer.data(), blockSize);
            }
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
