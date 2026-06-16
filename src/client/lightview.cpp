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

#include "lightview.h"
#include "spritemanager.h"
#include <framework/core/clock.h>
#include <framework/graphics/painter.h>
#include <unordered_map>

namespace {
constexpr ticks_t LIGHT_UPLOAD_INTERVAL_US = 33333;
constexpr ticks_t LIGHT_UPLOAD_CACHE_MAX_IDLE_US = 10 * 1000 * 1000;
constexpr size_t LIGHT_UPLOAD_CACHE_MAX_ENTRIES = 16;

struct LightUploadCache {
    Size mapSize;
    uint64_t signature = 0;
    ticks_t lastUpload = 0;
    ticks_t lastAccess = 0;
    bool uploaded = false;
    std::vector<uint8_t> buffer;
};

void hashCombine(uint64_t& hash, uint64_t value)
{
    hash ^= value + 0x9e3779b97f4a7c15ULL + (hash << 6) + (hash >> 2);
}

void pruneLightUploadCaches(std::unordered_map<uint, LightUploadCache>& uploadCaches, uint activeTextureId, ticks_t now)
{
    for (auto it = uploadCaches.begin(); it != uploadCaches.end();) {
        if (it->first != activeTextureId && it->second.lastAccess > 0 && now - it->second.lastAccess > LIGHT_UPLOAD_CACHE_MAX_IDLE_US)
            it = uploadCaches.erase(it);
        else
            ++it;
    }

    while (uploadCaches.size() > LIGHT_UPLOAD_CACHE_MAX_ENTRIES) {
        auto oldest = uploadCaches.end();
        for (auto it = uploadCaches.begin(); it != uploadCaches.end(); ++it) {
            if (it->first == activeTextureId)
                continue;
            if (oldest == uploadCaches.end() || it->second.lastAccess < oldest->second.lastAccess)
                oldest = it;
        }
        if (oldest == uploadCaches.end())
            break;
        uploadCaches.erase(oldest);
    }
}
}

void LightView::addLight(const Point& pos, uint8_t color, uint8_t intensity)
{
    if (!m_lights.empty()) {
        Light& prevLight = m_lights.back();
        if (prevLight.pos == pos && prevLight.color == color) {
            prevLight.intensity = std::max(prevLight.intensity, intensity);
            return;
        }
    }
    m_lights.push_back(Light{ pos, color, intensity });
}

void LightView::setFieldBrightness(const Point& pos, size_t start, uint8_t color)
{
    size_t index = (pos.y / g_sprites.spriteSize()) * m_mapSize.width() + (pos.x / g_sprites.spriteSize());
    if (index >= m_tiles.size()) return;
    m_tiles[index].start = start;
    m_tiles[index].color = color;
}

uint64_t LightView::buildSignature() const
{
    uint64_t hash = 1469598103934665603ULL;
    hashCombine(hash, static_cast<uint64_t>(m_mapSize.width()));
    hashCombine(hash, static_cast<uint64_t>(m_mapSize.height()));
    hashCombine(hash, static_cast<uint64_t>(m_globalLight.r()));
    hashCombine(hash, static_cast<uint64_t>(m_globalLight.g()));
    hashCombine(hash, static_cast<uint64_t>(m_globalLight.b()));
    hashCombine(hash, static_cast<uint64_t>(m_lights.size()));
    for (const Light& light : m_lights) {
        hashCombine(hash, static_cast<uint64_t>(light.pos.x));
        hashCombine(hash, static_cast<uint64_t>(light.pos.y));
        hashCombine(hash, static_cast<uint64_t>(light.color));
        hashCombine(hash, static_cast<uint64_t>(light.intensity));
    }
    for (const TileLight& tile : m_tiles) {
        hashCombine(hash, static_cast<uint64_t>(tile.start));
        hashCombine(hash, static_cast<uint64_t>(tile.color));
    }
    return hash;
}

void LightView::buildLightBuffer(std::vector<uint8_t>& buffer) const
{
    if (buffer.size() < 4u * m_mapSize.area())
        buffer.resize(m_mapSize.area() * 4);

    const int spriteSize = g_sprites.spriteSize();
    const float invSpriteSize = 1.f / static_cast<float>(spriteSize);

    for (int y = 0; y < m_mapSize.height(); ++y) {
        for (int x = 0; x < m_mapSize.width(); ++x) {
            Point pos(x * spriteSize + spriteSize / 2, y * spriteSize + spriteSize / 2);
            int index = (y * m_mapSize.width() + x);
            int colorIndex = index * 4;
            buffer[colorIndex] = m_globalLight.r();
            buffer[colorIndex + 1] = m_globalLight.g();
            buffer[colorIndex + 2] = m_globalLight.b();
            buffer[colorIndex + 3] = 255; // alpha channel
            for (size_t i = m_tiles[index].start; i < m_lights.size(); ++i) {
                const Light& light = m_lights[i];
                const float dx = pos.x - light.pos.x;
                const float dy = pos.y - light.pos.y;
                const float maxDistance = light.intensity * spriteSize;
                const float distanceSquared = dx * dx + dy * dy;
                if (distanceSquared >= maxDistance * maxDistance)
                    continue;

                float distance = std::sqrt(distanceSquared) * invSpriteSize;
                float intensity = (-distance + light.intensity) * 0.2f;
                if (intensity < 0.01f) continue;
                if (intensity > 1.0f) intensity = 1.0f;
                Color lightColor = Color::from8bit(light.color) * intensity;
                buffer[colorIndex] = std::max<int>(buffer[colorIndex], lightColor.r());
                buffer[colorIndex + 1] = std::max<int>(buffer[colorIndex + 1], lightColor.g());
                buffer[colorIndex + 2] = std::max<int>(buffer[colorIndex + 2], lightColor.b());
            }
        }
    }
}

void LightView::draw() // render thread
{
    static std::unordered_map<uint, LightUploadCache> uploadCaches;
    const ticks_t now = stdext::micros();
    const uint textureId = m_lightTexture->getUniqueId();
    LightUploadCache& cache = uploadCaches[textureId];
    cache.lastAccess = now;
    pruneLightUploadCaches(uploadCaches, textureId, now);

    const uint64_t signature = buildSignature();
    const bool sizeChanged = cache.mapSize != m_mapSize;
    const bool signatureChanged = cache.signature != signature;
    const bool intervalElapsed = now - cache.lastUpload >= LIGHT_UPLOAD_INTERVAL_US;
    const bool shouldUpload = !cache.uploaded || sizeChanged || (signatureChanged && intervalElapsed);

    if (shouldUpload) {
        buildLightBuffer(cache.buffer);
        m_lightTexture->update();
        glBindTexture(GL_TEXTURE_2D, m_lightTexture->getId());
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, m_mapSize.width(), m_mapSize.height(), GL_RGBA, GL_UNSIGNED_BYTE, cache.buffer.data());

        cache.mapSize = m_mapSize;
        cache.signature = signature;
        cache.lastUpload = now;
        cache.uploaded = true;
    }

    Point offset = m_src.topLeft();
    Size size = m_src.size();
    CoordsBuffer coords;
    coords.addRect(RectF(m_dest.left(), m_dest.top(), m_dest.width(), m_dest.height()),
                   RectF((float)offset.x / g_sprites.spriteSize(), (float)offset.y / g_sprites.spriteSize(),
                         (float)size.width() / g_sprites.spriteSize(), (float)size.height() / g_sprites.spriteSize()));

    g_painter->resetColor();
    g_painter->setCompositionMode(Painter::CompositionMode_Multiply);
    g_painter->drawTextureCoords(coords, m_lightTexture);
    g_painter->resetCompositionMode();
}
