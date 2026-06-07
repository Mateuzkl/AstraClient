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

#include "uihdminimap.h"
#include "map.h"
#include "tile.h"
#include "item.h"
#include "creature.h"
#include "game.h"
#include <framework/graphics/graphics.h>
#include <framework/graphics/framebuffermanager.h>
#include <framework/core/clock.h>
#include <framework/otml/otml.h>

UIHDMinimap::UIHDMinimap()
{
    m_draggable = false;
    m_cameraPosition = Position(0, 0, 7);
}

UIHDMinimap::~UIHDMinimap()
{
}

void UIHDMinimap::setCameraPosition(const Position& pos)
{
    // Marcar como dirty os chunks que o player esta entrando
    int cx = pos.x / HD_CHUNK_SIZE;
    int cy = pos.y / HD_CHUNK_SIZE;

    for (int dy = -1; dy <= 1; ++dy) {
        for (int dx = -1; dx <= 1; ++dx) {
            auto key = chunkKey(cx + dx, cy + dy, pos.z);
            auto it = m_hdCache.find(key);
            if (it != m_hdCache.end())
                it->second.dirty = true;
        }
    }

    m_cameraPosition = pos;
}

void UIHDMinimap::drawSelf(Fw::DrawPane drawPane)
{
    UIWidget::drawSelf(drawPane);

    if (drawPane != Fw::ForegroundPane)
        return;

    Rect rect = getPaddingRect();
    if (rect.isEmpty())
        return;

    g_drawQueue->addFilledRect(rect, Color::black);

    if (m_visibleW <= 0 || m_visibleH <= 0)
        return;

    float tileWf = static_cast<float>(rect.width()) / m_visibleW;
    float tileHf = static_cast<float>(rect.height()) / m_visibleH;
    if (tileWf < 2.0f || tileHf < 2.0f)
        return;

    int startX = m_cameraPosition.x - m_visibleW / 2;
    int startY = m_cameraPosition.y - m_visibleH / 2;
    int z = m_cameraPosition.z;

    for (int ty = 0; ty < m_visibleH; ++ty) {
        int y1 = rect.top() + static_cast<int>(std::round(ty * tileHf));
        int y2 = rect.top() + static_cast<int>(std::round((ty + 1) * tileHf));

        for (int tx = 0; tx < m_visibleW; ++tx) {
            Position pos(startX + tx, startY + ty, z);
            if (!pos.isMapPosition()) continue;

            int x1 = rect.left() + static_cast<int>(std::round(tx * tileWf));
            int x2 = rect.left() + static_cast<int>(std::round((tx + 1) * tileWf));
            Rect tileRect(x1, y1, x2 - x1, y2 - y1);

            int distX = std::abs(pos.x - m_cameraPosition.x);
            int distY = std::abs(pos.y - m_cameraPosition.y);

            // ================================================================
            //  LIVE ZONE - tiles within server viewport radius
            // ================================================================
            if (distX <= m_liveRadius && distY <= m_liveRadius) {
                TilePtr tile = g_map.getTile(pos);
                if (!tile) continue;

                uint8 groundColor = tile->getMinimapColorByte();
                if (groundColor != 255)
                    g_drawQueue->addFilledRect(tileRect, Color::from8bit(groundColor));

                for (const auto& thing : tile->getThings()) {
                    if (!thing->isItem()) continue;
                    auto item = std::static_pointer_cast<Item>(thing);
                    item->draw(tileRect, m_animated);
                }

                for (const auto& creature : tile->getCreatures()) {
                    creature->drawOutfit(tileRect, Otc::South, Color::white, m_animated, false, false);
                }
            }
            // ================================================================
            //  CACHE ZONE - beyond live radius, use baked TexturePtr chunks
            // ================================================================
            else {
                int cx = pos.x / HD_CHUNK_SIZE;
                int cy = pos.y / HD_CHUNK_SIZE;
                auto key = chunkKey(cx, cy, z);

                auto it = m_hdCache.find(key);
                if (it != m_hdCache.end()) {
                    if (it->second.dirty)
                        bakeChunk(cx, cy, z, it->second);

                    it->second.lastSeen = g_clock.millis();

                    int lx = pos.x % HD_CHUNK_SIZE;
                    int ly = pos.y % HD_CHUNK_SIZE;
                    Rect srcRect(lx * tileWf, ly * tileHf, tileWf, tileHf);
                    g_drawQueue->addTexturedRect(tileRect, it->second.texture, srcRect);
                } else {
                    // UNSEEN ZONE - fallback color map classico
                    uint8_t color = g_minimap.getTile(pos).color;
                    if (color != 255)
                        g_drawQueue->addFilledRect(tileRect, Color::from8bit(color));
                }
            }
        }
    }
}

void UIHDMinimap::bakeChunk(int cx, int cy, int z, HDChunk& chunk)
{
    int spriteSize = g_sprites.spriteSize();
    Size chunkSize(HD_CHUNK_SIZE * spriteSize, HD_CHUNK_SIZE * spriteSize);

    if (!m_bakeFramebuffer)
        m_bakeFramebuffer = g_framebuffers.createFrameBuffer();
    if (m_bakeFramebuffer->getSize() != chunkSize)
        m_bakeFramebuffer->resize(chunkSize);

    m_bakeFramebuffer->bind();
    g_painter->clear(Color::black);

    for (int ty = 0; ty < HD_CHUNK_SIZE; ++ty) {
        for (int tx = 0; tx < HD_CHUNK_SIZE; ++tx) {
            Position pos(cx * HD_CHUNK_SIZE + tx, cy * HD_CHUNK_SIZE + ty, z);
            if (!pos.isMapPosition()) continue;

            TilePtr tile = g_map.getTile(pos);
            if (!tile || tile->isEmpty()) continue;

            Point dest(tx * spriteSize, ty * spriteSize);

            // Static structure only - no creatures/effects in cache
            tile->drawGround(dest);
            tile->drawBottom(dest);
        }
    }

    m_bakeFramebuffer->release();

    chunk.texture = m_bakeFramebuffer->getTexture();
    chunk.dirty = false;

    if (static_cast<int>(m_hdCache.size()) > m_maxCacheChunks)
        evictLRU();
}

void UIHDMinimap::evictLRU()
{
    if (m_hdCache.empty()) return;

    uint64_t oldestKey = 0;
    ticks_t  minTime = std::numeric_limits<ticks_t>::max();

    for (const auto& pair : m_hdCache) {
        if (pair.second.lastSeen < minTime) {
            minTime = pair.second.lastSeen;
            oldestKey = pair.first;
        }
    }

    if (oldestKey != 0)
        m_hdCache.erase(oldestKey);
}

void UIHDMinimap::clearCache()
{
    m_hdCache.clear();
}

void UIHDMinimap::onStyleApply(const std::string& styleName, const OTMLNodePtr& styleNode)
{
    UIWidget::onStyleApply(styleName, styleNode);
    for (const auto& node : styleNode->children()) {
        if (node->tag() == "animated")
            setAnimated(node->value<bool>());
    }
}
