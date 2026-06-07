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

#ifndef UIHDMINIMAP_H
#define UIHDMINIMAP_H

#include "declarations.h"
#include <framework/ui/uiwidget.h>
#include <framework/graphics/framebuffer.h>
#include <framework/graphics/texture.h>
#include <unordered_map>

 // 8x8 tiles per cache chunk
static constexpr int HD_CHUNK_SIZE = 8;

struct HDChunk {
    TexturePtr texture;       // snapshot baked dos sprites
    ticks_t    lastSeen = 0;  // para LRU eviction
    bool       dirty    = true;
};

class UIHDMinimap : public UIWidget
{
public:
    UIHDMinimap();
    ~UIHDMinimap();

    void drawSelf(Fw::DrawPane drawPane) override;

    void setCameraPosition(const Position& pos);
    Position getCameraPosition() { return m_cameraPosition; }

    void setVisibleDimension(int width, int height) { m_visibleW = width; m_visibleH = height; }
    int getVisibleWidth() { return m_visibleW; }
    int getVisibleHeight() { return m_visibleH; }

    void setAnimated(bool enable) { m_animated = enable; }
    bool isAnimated() { return m_animated; }

    void setLiveRadius(int radius) { m_liveRadius = radius; }
    int  getLiveRadius() { return m_liveRadius; }

    void setMaxCacheChunks(int max) { m_maxCacheChunks = max; }
    int  getMaxCacheChunks() { return m_maxCacheChunks; }

    void clearCache();

protected:
    void onStyleApply(const std::string& styleName, const OTMLNodePtr& styleNode) override;

private:
    static uint64_t chunkKey(int cx, int cy, int z) {
        return ((uint64_t)(uint16_t)cx)       |
               ((uint64_t)(uint16_t)cy << 16) |
               ((uint64_t)(uint8_t)z   << 32);
    }

    void bakeChunk(int cx, int cy, int z, HDChunk& chunk);
    void evictLRU();

    Position m_cameraPosition;
    int m_visibleW = 9;
    int m_visibleH = 7;
    bool m_animated = false;

    // Live + Cache zone config
    int m_liveRadius     = 9;   // mesmo viewport do servidor por padrao
    int m_maxCacheChunks = 512; // LRU limit

    // FBO shared for baking chunks
    FrameBufferPtr m_bakeFramebuffer;

    std::unordered_map<uint64_t, HDChunk> m_hdCache;
};

#endif
