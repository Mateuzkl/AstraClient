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
#include <list>
#include <unordered_set>

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
    size_t getImageCacheSize() const { return m_imageCache.size(); }
    size_t getImageCacheBytes() const { return m_imageCacheBytes; }
    size_t getCachedDataCount() const { return m_cachedData.size(); }
    size_t getCachedDataBytes() const {
        size_t bytes = 0;
        for (const auto& entry : m_cachedData) bytes += entry.second.size();
        return bytes;
    }

    int spriteSize() { return m_spriteSize; }
    float getOffsetFactor() const { return static_cast<float>(m_spriteSize) / 32.0f; }
    bool isHdMod() const { return m_isHdMod; }
    bool isIndexed() const { return m_isIndexed; }
    bool isPaged() const { return m_isPaged; }
    bool wasLastSpritePending() const { return m_lastSpritePending; }
    void onPagedSprPageLoaded(uint32 pageIndex, std::vector<uint8_t>&& bytes, bool ok);
    size_t getPagedCachePages() const { return m_pagedCache.size(); }
    size_t getPagedCacheBytes() const { return m_pagedCacheBytes; }
    bool isIndexedSource(const std::string& path) const;
    std::string resolveIndexedFolder(const std::string& path) const;
    int getPartsCount() const { return static_cast<int>(m_parts.size()); }
    void setScaleFactor(int factor);
    int getScaleFactor() { return m_scaleFactor; }

private:
    struct ImageCacheEntry
    {
        ImagePtr image;
        size_t bytes = 0;
        std::list<int>::iterator lruIt;
    };

    struct SprPart
    {
        uint32 signature = 0;
        uint32 spriteCount = 0;
        uint32 fileSize = 0;
        FileStreamPtr file;
        std::vector<uint32> addresses;
    };

    struct PagedPageEntry
    {
        std::vector<uint8_t> bytes;
        std::list<uint32>::iterator lruIt;
    };

    bool loadCasualSpr(std::string file);
    bool loadPagedSpr(std::string idxFile);
    bool loadCwmSpr(std::string file);
    bool loadIndexedSpr(std::string folder);

    ImagePtr getSpriteImageCasual(int id);
    ImagePtr getSpriteImagePaged(int id);
    bool readPagedBytes(uint32 offset, size_t length, uint8_t* out);
    void requestPagedSprPage(uint32 pageIndex);
    ImagePtr getSpriteImageIndexed(int id);
    ImagePtr getSpriteImageHd(int id);
    void clearImageCache();
    void updateSpriteSize();
    ImagePtr upscaleSprite(const ImagePtr& sprite, int scaleFactor) const;

    bool m_loaded = false;
    bool m_isHdMod = false;
    bool m_isIndexed = false;
    bool m_isPaged = false;
    bool m_lastSpritePending = false;
    uint32 m_signature = 0;
    int m_spritesCount = 0;
    int m_spritesOffset = 0;
    uint32 m_pagedFileSize = 0;
    int m_spriteSize = 32;
    int m_baseSpriteSize = 32;
    int m_scaleFactor = 1;
    FileStreamPtr m_spritesFile;
    std::vector<SprPart> m_parts;
    std::vector<uint32> m_index;
    std::vector<uint32> m_spriteAddresses;
    std::vector<std::vector<uint8_t>> m_sprites;
    std::unordered_map<uint32, std::string> m_cachedData;
    std::unordered_map<int, ImageCacheEntry> m_imageCache;
    std::list<int> m_imageCacheLru;
    size_t m_imageCacheBytes = 0;
    std::unordered_map<uint32, PagedPageEntry> m_pagedCache;
    std::list<uint32> m_pagedCacheLru;
    size_t m_pagedCacheBytes = 0;
    std::unordered_set<uint32> m_pendingPages;
    std::unordered_map<uint32, ticks_t> m_failedPages;
};

extern SpriteManager g_sprites;

#endif
