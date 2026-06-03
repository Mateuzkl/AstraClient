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

#ifndef SPRITEMANAGER_H
#define SPRITEMANAGER_H

#include "const.h"
#include <framework/core/declarations.h>
#include <framework/graphics/declarations.h>

//@bindsingleton g_sprites
class SpriteManager
{
public:
    SpriteManager();

    void terminate();

    bool loadSpr(std::string file);
    void unload();

#ifdef WITH_ENCRYPTION
    void saveSpr(std::string fileName);
    void saveSpr64(std::string fileName);
    void encryptSprites(std::string fileName);
    void dumpSprites(std::string dir);
#endif

    uint32 getSignature() { return m_signature; }
    int getSpritesCount() { return m_spritesCount; }

    ImagePtr getSpriteImage(int id);
    bool isLoaded() { return m_loaded; }

    int spriteSize() { return m_spriteSize; }
    float getOffsetFactor() const { return static_cast<float>(m_spriteSize) / 32.0f; }
    bool isHdMod() const { return m_isHdMod; }
    size_t getIndexMemoryUsage() const;
    size_t getSpriteCacheMemoryUsage() const;
    size_t getSpriteCacheMemoryLimit() const;
    size_t getSpriteCacheSize() const;
    size_t getSpriteCacheMaxSprites() const;
    std::string getSpriteModeName() const;
    std::string getCacheStats();
    void logCacheStats();
    void setSpriteCacheLimits(int maxSprites, int maxMegabytes);
    void clearSpriteCache();

private:
    enum class SpriteMode {
        None,
        SprLegacy,
        SprOtv8,
        Cwm
    };

    struct CachedSpriteData
    {
        uint32 offset = 0;
        uint32 size = 0;
    };

    struct SpriteCacheEntry
    {
        ImagePtr image;
        size_t bytes = 0;
        std::list<uint32>::iterator lruIt;
    };

    bool loadCasualSpr(std::string file);
    bool loadCwmSpr(std::string file);

    ImagePtr getSpriteImageCasual(int id);
    ImagePtr getSpriteImageHd(int id);
    ImagePtr getCachedSpriteImage(uint32 id);
    void cacheSpriteImage(uint32 id, const ImagePtr& image);
    void clearSpriteCacheLocked();
    void enforceSpriteCacheLimits();
    void configureSpriteCacheFromSettings();
    size_t estimateImageMemoryUsage(const ImagePtr& image) const;

    bool m_loaded = false;
    bool m_isHdMod = false;
    uint32 m_signature;
    int m_spritesCount;
    int m_spritesOffset;
    int m_spriteSize;
    FileStreamPtr m_spritesFile;
    SpriteMode m_spriteMode = SpriteMode::None;
    std::vector<CachedSpriteData> m_spriteData;
    std::unordered_map<uint32, CachedSpriteData> m_cachedData;
    std::mutex m_fileMutex;
    std::unordered_map<uint32, SpriteCacheEntry> m_spriteCache;
    std::list<uint32> m_spriteCacheLru;
    size_t m_spriteCacheBytes = 0;
    size_t m_spriteCacheMaxBytes = 64 * 1024 * 1024;
    size_t m_spriteCacheMaxSprites = 4096;
    mutable std::mutex m_cacheMutex;
};

extern SpriteManager g_sprites;

#endif
