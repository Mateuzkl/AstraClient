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

#include "spritemanager.h"
#include "game.h"
#include <framework/core/config.h>
#include <framework/core/configmanager.h>
#include <framework/core/resourcemanager.h>
#include <framework/core/filestream.h>
#include <framework/graphics/image.h>
#include <framework/graphics/atlas.h>
#include <framework/util/crypt.h>
#include <exception>

SpriteManager g_sprites;

SpriteManager::SpriteManager()
{
    m_spritesCount = 0;
    m_signature = 0;
    m_spritesOffset = 0;
    m_spriteSize = 32;
}

void SpriteManager::terminate()
{
    unload();
}

bool SpriteManager::loadSpr(std::string file)
{
    configureSpriteCacheFromSettings();
    clearSpriteCache();

    m_spritesCount = 0;
    m_signature = 0;
    m_loaded = false;
    m_isHdMod = false;
    m_spritesFile = nullptr;
    m_spriteMode = SpriteMode::None;
    m_spriteData.clear();
    m_cachedData.clear();

    auto cwmFile = g_resources.guessFilePath(file, "cwm");
    if (g_resources.fileExists(cwmFile)) {
        return loadCwmSpr(cwmFile);
    }

    auto sprFile = g_resources.guessFilePath(file, "spr");
    if (g_resources.fileExists(sprFile)) {
        return loadCasualSpr(sprFile);
    }

    return false;
}

#ifdef WITH_ENCRYPTION

void SpriteManager::saveSpr(std::string fileName)
{
    if (!m_loaded)
        stdext::throw_exception("failed to save, spr is not loaded");
    if (!m_spritesFile || m_spriteMode != SpriteMode::SprLegacy)
        stdext::throw_exception("not allowed");

    try {
        FileStreamPtr fin = g_resources.createFile(fileName);
        if (!fin)
            stdext::throw_exception(stdext::format("failed to open file '%s' for write", fileName));

        fin->addU32(m_signature);
        if (g_game.getFeature(Otc::GameSpritesU32))
            fin->addU32(m_spritesCount);
        else
            fin->addU16(m_spritesCount);

        uint32 offset = fin->tell();
        uint32 spriteAddress = offset + 4 * m_spritesCount;
        for (int i = 1; i <= m_spritesCount; i++)
            fin->addU32(0);

        for (int i = 1; i <= m_spritesCount; i++) {
            m_spritesFile->seek((i - 1) * 4 + m_spritesOffset);
            uint32 fromAdress = m_spritesFile->getU32();
            if (fromAdress != 0) {
                fin->seek(offset + (i - 1) * 4);
                fin->addU32(spriteAddress);
                fin->seek(spriteAddress);

                m_spritesFile->seek(fromAdress);
                fin->addU8(m_spritesFile->getU8());
                fin->addU8(m_spritesFile->getU8());
                fin->addU8(m_spritesFile->getU8());

                uint16 dataSize = m_spritesFile->getU16();
                fin->addU16(dataSize);
                std::vector<char> spriteData(m_spriteSize * m_spriteSize);
                m_spritesFile->read(spriteData.data(), dataSize);
                fin->write(spriteData.data(), dataSize);

                spriteAddress = fin->tell();
            }
            //TODO: Check for overwritten sprites.
        }

        fin->flush();
        fin->close();
    } catch (std::exception& e) {
        g_logger.error(stdext::format("Failed to save '%s': %s", fileName, e.what()));
    }
}

void SpriteManager::saveSpr64(std::string fileName)
{
    if (!m_loaded)
        stdext::throw_exception("failed to save, spr is not loaded");
    if (!m_spritesFile || m_spriteSize != 32)
        stdext::throw_exception("not allowed");

    try {
        FileStreamPtr fin = g_resources.createFile(fileName);
        if (!fin)
            stdext::throw_exception(stdext::format("failed to open file '%s' for write", fileName));

        fin->addU32(m_signature);
        if (g_game.getFeature(Otc::GameSpritesU32))
            fin->addU32(m_spritesCount);
        else
            fin->addU16(m_spritesCount);

        uint32 offset = fin->tell();
        for (int i = 1; i <= m_spritesCount; i++)
            fin->addU32(0);

        for (int i = 1; i <= m_spritesCount; i++) {
            ImagePtr sprite = getSpriteImage(i);
            if (!sprite) {
                continue;
            }
            sprite = sprite->upscale();

            uint32 spriteAddress = fin->tell();
            fin->seek(offset + (i - 1) * 4);
            fin->addU32(spriteAddress);
            fin->seek(spriteAddress);

            fin->addU8(0xff);
            fin->addU8(0x00);
            fin->addU8(0xff);

            uint8_t* pixels = sprite->getPixelData();
            int pixelCount = sprite->getPixelCount() * 4;
            std::vector<uint8_t> buffer(pixelCount + 1024, 0);
            int bufferPos = 0;

            int skipedPixels = 0;
            for (int i = 0; i < pixelCount; ) {
                int transparent = 0, colored = 0;
                for (int j = i; j < pixelCount; j += 4) {
                    if (pixels[j + 3] == 0x00) {
                        if (colored != 0) break;
                        transparent += 1;
                    } else {
                        colored += 1;
                    }
                }

                *(uint16_t*)(buffer.data() + bufferPos) = transparent;
                bufferPos += 2;
                *(uint16_t*)(buffer.data() + bufferPos) = colored;
                bufferPos += 2;

                i += transparent * 4;

                for (int c = 0; c < colored; ++c) {
                    buffer[bufferPos++] = pixels[i];
                    buffer[bufferPos++] = pixels[i + 1];
                    buffer[bufferPos++] = pixels[i + 2];
                    i += 4;
                }
            }

            fin->addU16(bufferPos);
            fin->write(buffer.data(), bufferPos);
        }

        fin->flush();
        fin->close();
    } catch (std::exception& e) {
        g_logger.error(stdext::format("Failed to save '%s': %s", fileName, e.what()));
    }
}

void SpriteManager::encryptSprites(std::string fileName)
{
    if (!m_loaded)
        stdext::throw_exception("failed to save, spr is not loaded");

    try {
        FileStreamPtr fin = g_resources.createFile(fileName);
        if (!fin)
            stdext::throw_exception(stdext::format("failed to open file '%s' for write", fileName));

        const char otcv8Signature[] = "OTV8";
        fin->addU32(*((uint32_t*)otcv8Signature));
        fin->addU32(m_signature);
        fin->addU32(m_spritesCount);

        for (int i = 1; i <= m_spritesCount; i++) {
            ImagePtr sprite = getSpriteImage(i);
            if (!sprite) {
                fin->addU16(0);
                continue;
            }
            uint8_t* pixels = sprite->getPixelData();
            int pixelCount = sprite->getPixelCount() * 4;
            std::vector<uint8_t> buffer(pixelCount + 1024, 0);
            int bufferPos = 0;

            bool hasAlpha = false;
            for (int i = 3; i < pixelCount; i += 4) {
                if (pixels[i] != 0x00 && pixels[i] != 0xFF) {
                    hasAlpha = true;
                    break;
                }
            }

            buffer[bufferPos++] = (hasAlpha ? 1 : 0);
            int skipedPixels = 0;
            for (int i = 0; i < pixelCount; ) {
                int transparent = 0, colored = 0;
                for (int j = i; j < pixelCount; j += 4) {
                    if (pixels[j + 3] == 0x00) {
                        if (colored != 0) break;
                        transparent += 1;
                    } else {
                        colored += 1;
                    }
                }

                *(uint16_t*)(buffer.data() + bufferPos) = transparent;
                bufferPos += 2;
                *(uint16_t*)(buffer.data() + bufferPos) = colored;
                bufferPos += 2;

                i += transparent * 4;

                for (int c = 0; c < colored; ++c) {
                    buffer[bufferPos++] = pixels[i];
                    buffer[bufferPos++] = pixels[i + 1];
                    buffer[bufferPos++] = pixels[i + 2];
                    if (hasAlpha) {
                        buffer[bufferPos++] = pixels[i + 3];
                    }
                    i += 4;
                }
            }

            g_crypt.bencrypt(buffer.data(), bufferPos, (uint64_t)m_signature + i);
            fin->addU16(bufferPos);
            fin->write(buffer.data(), bufferPos);
        }

        fin->flush();
        fin->close();
    }
    catch (std::exception& e) {
        g_logger.error(stdext::format("Failed to save '%s': %s", fileName, e.what()));
    }
}

void SpriteManager::dumpSprites(std::string dir)
{
    if (dir.empty()) {
        g_logger.error("Empty dir for sprites dump");
        return;
    }
    g_resources.makeDir(dir);
    for (int i = 1; i <= m_spritesCount; i++) {
        auto img = getSpriteImage(i);
        if (!img) continue;
        img->savePNG(dir + "/" + std::to_string(i) + ".png");
    }
}

#endif

void SpriteManager::unload()
{
    clearSpriteCache();

    m_spritesCount = 0;
    m_signature = 0;
    m_loaded = false;
    m_isHdMod = false;
    m_spritesFile = nullptr;
    m_spriteMode = SpriteMode::None;
    m_spriteData.clear();
    m_cachedData.clear();
}

ImagePtr SpriteManager::getSpriteImage(int id)
{
    if (m_spriteMode == SpriteMode::SprOtv8 || m_spriteMode == SpriteMode::Cwm) {
        if (ImagePtr cachedImage = getCachedSpriteImage(id))
            return cachedImage;

        ImagePtr image = m_isHdMod ? getSpriteImageHd(id) : getSpriteImageCasual(id);
        cacheSpriteImage(id, image);
        return image;
    }

    if (m_isHdMod) {
        return getSpriteImageHd(id);
    }
    else {
        return getSpriteImageCasual(id);
    }
}

bool SpriteManager::loadCasualSpr(std::string file)
{
    m_spriteSize = 32u;
    try {
        file = g_resources.guessFilePath(file, "spr");

        m_spritesFile = g_resources.openFile(file, true);

        m_signature = m_spritesFile->getU32();
        if (m_signature == *((uint32_t*)"OTV8")) {
            m_spriteMode = SpriteMode::SprOtv8;
            m_signature = m_spritesFile->getU32();
            m_spritesCount = m_spritesFile->getU32();
            m_spriteData.assign(m_spritesCount + 1, CachedSpriteData());
            const uint fileSize = m_spritesFile->size();
            for (int i = 1; i <= m_spritesCount; ++i) {
                uint16 bufferSize = m_spritesFile->getU16();
                const uint32 dataOffset = m_spritesFile->tell();
                if (bufferSize > 0) {
                    if (dataOffset > fileSize || bufferSize > fileSize - dataOffset)
                        stdext::throw_exception(stdext::format("corrupt OTV8 sprite index at sprite %d", i));
                    m_spriteData[i] = CachedSpriteData{ dataOffset, bufferSize };
                }
                m_spritesFile->skip(bufferSize);
            }
        }
        else {
            m_spriteMode = SpriteMode::SprLegacy;
            m_spritesCount = g_game.getFeature(Otc::GameSpritesU32) ? m_spritesFile->getU32() : m_spritesFile->getU16();
            m_spritesOffset = m_spritesFile->tell();
        }
        m_loaded = true;
        logCacheStats();
        g_lua.callGlobalField("g_sprites", "onLoadSpr", file);
        return true;
    }
    catch (stdext::exception& e) {
        g_logger.error(stdext::format("Failed to load sprites from '%s': %s", file, e.what()));
        return false;
    }
}

bool SpriteManager::loadCwmSpr(std::string file)
{
    try {
        auto inFilePath = g_resources.guessFilePath(file, "cwm");
        m_spritesFile = g_resources.openFile(inFilePath, true);

        uint8_t version = m_spritesFile->getU8();
        if (version != 0x01) {
            g_logger.error(stdext::format("Invalid CWM file version - %s", file));
            m_spritesFile = nullptr;
            return false;
        }

        m_spriteSize = m_spritesFile->getU16();

        uint32_t entries = m_spritesFile->getU32();
        struct SpriteMetadata {
            uint32 offset = 0;
            uint32 size = 0;
            std::string name;
        };

        std::vector<SpriteMetadata> metadata;
        metadata.reserve(entries);
        for (uint32_t i = 0; i < entries; ++i) {
            metadata.push_back(SpriteMetadata{
                m_spritesFile->getU32(),
                m_spritesFile->getU32(),
                m_spritesFile->getString()
            });
        }

        uint dataStart = m_spritesFile->tell();
        uint fileSize = m_spritesFile->size();
        m_cachedData.clear();
        m_cachedData.reserve(entries);
        for (const auto& entry : metadata) {
            uint32 imageID = stdext::safe_cast<uint32>(entry.name);
            uint32 absoluteOffset = dataStart + entry.offset;
            if (entry.size == 0 || absoluteOffset > fileSize || entry.size > fileSize - absoluteOffset)
                continue;
            m_cachedData.emplace(imageID, CachedSpriteData{ absoluteOffset, entry.size });
        }

        m_spritesCount = m_cachedData.size();

        if (m_spritesCount == 0) {
            g_logger.error(stdext::format("Failed to load sprites from '%s' - no sprites", file));
            m_spritesFile = nullptr;
            m_cachedData.clear();
            return false;
        }

        m_isHdMod = true;
        m_spriteMode = SpriteMode::Cwm;
        m_loaded = true;
        logCacheStats();
        return true;
    }
    catch (stdext::exception& e) {
        m_spritesFile = nullptr;
        m_cachedData.clear();
        g_logger.error(stdext::format("Failed to load sprites from '%s': %s", file, e.what()));
        return false;
    }
}

ImagePtr SpriteManager::getSpriteImageCasual(int id)
{
    try {
        int spriteDataSize = m_spriteSize * m_spriteSize * 4;

        if (m_spriteMode == SpriteMode::SprOtv8) {
            if (id <= 0 || id >= (int)m_spriteData.size() || !m_spritesFile)
                return nullptr;

            const CachedSpriteData& spriteData = m_spriteData[id];
            if (spriteData.size < 5)
                return nullptr;

            std::vector<uint8_t> buffer(spriteData.size);
            {
                std::lock_guard<std::mutex> lock(m_fileMutex);
                m_spritesFile->seek(spriteData.offset);
                m_spritesFile->read(buffer.data(), spriteData.size);
            }

            g_crypt.bdecrypt(buffer.data(), buffer.size(), (uint64_t)m_signature + id);

            if (buffer[0] > 1) {
                stdext::throw_exception("Invalid sprite encryption");
            }

            bool hasAlpha = (buffer[0] == 1);

            auto image = std::make_shared<Image>(Size(m_spriteSize, m_spriteSize));
            uint8* pixels = image->getPixelData();
            int writePos = 0;

            size_t bufferPos = 1;
            while (bufferPos + 4 <= buffer.size() && writePos < spriteDataSize) {
                uint16_t transparentPixels = *(uint16_t*)(&buffer[bufferPos]);
                bufferPos += 2;
                uint16_t coloredPixels = *(uint16_t*)(&buffer[bufferPos]);
                bufferPos += 2;

                writePos += transparentPixels * 4;
                for (int i = 0; i < coloredPixels && writePos < spriteDataSize && bufferPos < buffer.size(); ++i) {
                    if ((!hasAlpha && bufferPos + 3 > buffer.size()) || (hasAlpha && bufferPos + 4 > buffer.size()))
                        break;
                    pixels[writePos++] = buffer[bufferPos++];
                    pixels[writePos++] = buffer[bufferPos++];
                    pixels[writePos++] = buffer[bufferPos++];
                    if (hasAlpha) {
                        pixels[writePos] = buffer[bufferPos++];
                    }
                    else {
                        pixels[writePos] = 0xFF;
                    }
                    writePos += 1;
                }
            }

            return image;
        }

        if (id <= 0 || id > m_spritesCount || !m_spritesFile)
            return nullptr;

        std::lock_guard<std::mutex> lock(m_fileMutex);

        m_spritesFile->seek(((id - 1) * 4) + m_spritesOffset);

        uint32 spriteAddress = m_spritesFile->getU32();

        // no sprite? return an empty texture
        if (spriteAddress == 0)
            return nullptr;

        m_spritesFile->seek(spriteAddress);

        // color key
        m_spritesFile->getU8();
        m_spritesFile->getU8();
        m_spritesFile->getU8();

        uint16 pixelDataSize = m_spritesFile->getU16();

        auto image = std::make_shared<Image>(Size(m_spriteSize, m_spriteSize));

        uint8* pixels = image->getPixelData();
        int writePos = 0;
        int read = 0;
        bool useAlpha = g_game.getFeature(Otc::GameSpritesAlphaChannel);

        // decompress pixels
        while (read < pixelDataSize && writePos < spriteDataSize) {
            uint16 transparentPixels = m_spritesFile->getU16();
            uint16 coloredPixels = m_spritesFile->getU16();

            writePos += transparentPixels * 4;

            if (useAlpha) {
                m_spritesFile->read(&pixels[writePos], std::min<uint16>(coloredPixels * 4, spriteDataSize - writePos));
                writePos += coloredPixels * 4;
                read += 4 + (4 * coloredPixels);
            }
            else {
                for (int i = 0; i < coloredPixels && writePos < spriteDataSize; i++) {
                    pixels[writePos + 0] = m_spritesFile->getU8();
                    pixels[writePos + 1] = m_spritesFile->getU8();
                    pixels[writePos + 2] = m_spritesFile->getU8();
                    pixels[writePos + 3] = 0xFF;
                    writePos += 4;
                }
                read += 4 + (3 * coloredPixels);
            }
        }

        return image;
    }
    catch (stdext::exception& e) {
        g_logger.error(stdext::format("Failed to get sprite id %d: %s", id, e.what()));
        return nullptr;
    }
}

ImagePtr SpriteManager::getSpriteImageHd(int id)
{
    if (id == 0 || !m_loaded)
        return nullptr;

    auto it = m_cachedData.find(id);
    if (it == m_cachedData.end() || !m_spritesFile)
        return nullptr;

    try {
        std::string data(it->second.size, '\0');
        {
            std::lock_guard<std::mutex> lock(m_fileMutex);
            m_spritesFile->seek(it->second.offset);
            m_spritesFile->read(data.data(), it->second.size);
        }
        return Image::loadPNG(data.data(), data.size());
    } catch (const std::exception& e) {
        g_logger.error(stdext::format("Failed to get HD sprite id %d at offset %u size %u: %s",
                                      id,
                                      static_cast<uint>(it->second.offset),
                                      static_cast<uint>(it->second.size),
                                      e.what()));
    }
    return nullptr;
}

ImagePtr SpriteManager::getCachedSpriteImage(uint32 id)
{
    std::lock_guard<std::mutex> lock(m_cacheMutex);

    auto it = m_spriteCache.find(id);
    if (it == m_spriteCache.end())
        return nullptr;

    m_spriteCacheLru.splice(m_spriteCacheLru.begin(), m_spriteCacheLru, it->second.lruIt);
    return it->second.image;
}

void SpriteManager::cacheSpriteImage(uint32 id, const ImagePtr& image)
{
    if (!image)
        return;

    std::lock_guard<std::mutex> lock(m_cacheMutex);
    if (m_spriteCacheMaxSprites == 0 || m_spriteCacheMaxBytes == 0) {
        clearSpriteCacheLocked();
        return;
    }

    const size_t bytes = estimateImageMemoryUsage(image);
    auto it = m_spriteCache.find(id);
    if (it != m_spriteCache.end()) {
        m_spriteCacheBytes -= it->second.bytes;
        it->second.image = image;
        it->second.bytes = bytes;
        m_spriteCacheBytes += bytes;
        m_spriteCacheLru.splice(m_spriteCacheLru.begin(), m_spriteCacheLru, it->second.lruIt);
    } else {
        m_spriteCacheLru.push_front(id);
        m_spriteCache.emplace(id, SpriteCacheEntry{ image, bytes, m_spriteCacheLru.begin() });
        m_spriteCacheBytes += bytes;
    }

    enforceSpriteCacheLimits();
}

void SpriteManager::clearSpriteCache()
{
    std::lock_guard<std::mutex> lock(m_cacheMutex);
    clearSpriteCacheLocked();
}

void SpriteManager::clearSpriteCacheLocked()
{
    m_spriteCache.clear();
    m_spriteCacheLru.clear();
    m_spriteCacheBytes = 0;
}

void SpriteManager::enforceSpriteCacheLimits()
{
    while (!m_spriteCacheLru.empty() &&
           (m_spriteCache.size() > m_spriteCacheMaxSprites || m_spriteCacheBytes > m_spriteCacheMaxBytes)) {
        uint32 id = m_spriteCacheLru.back();
        m_spriteCacheLru.pop_back();

        auto it = m_spriteCache.find(id);
        if (it == m_spriteCache.end())
            continue;

        m_spriteCacheBytes -= it->second.bytes;
        m_spriteCache.erase(it);
    }
}

void SpriteManager::setSpriteCacheLimits(int maxSprites, int maxMegabytes)
{
    std::lock_guard<std::mutex> lock(m_cacheMutex);
    m_spriteCacheMaxSprites = static_cast<size_t>(std::max(maxSprites, 0));
    m_spriteCacheMaxBytes = static_cast<size_t>(std::max(maxMegabytes, 0)) * 1024 * 1024;

    if (m_spriteCacheMaxSprites == 0 || m_spriteCacheMaxBytes == 0)
        clearSpriteCacheLocked();
    else
        enforceSpriteCacheLimits();
}

void SpriteManager::configureSpriteCacheFromSettings()
{
    ConfigPtr settings = g_configs.getSettings();
    if (!settings)
        return;

    int maxSprites = static_cast<int>(m_spriteCacheMaxSprites);
    int maxMegabytes = static_cast<int>(m_spriteCacheMaxBytes / (1024 * 1024));

    if (settings->exists("spriteCacheMaxSprites"))
        maxSprites = stdext::from_string<int>(settings->getValue("spriteCacheMaxSprites"), maxSprites);
    if (settings->exists("spriteCacheMaxMegabytes"))
        maxMegabytes = stdext::from_string<int>(settings->getValue("spriteCacheMaxMegabytes"), maxMegabytes);

    setSpriteCacheLimits(maxSprites, maxMegabytes);
}

size_t SpriteManager::estimateImageMemoryUsage(const ImagePtr& image) const
{
    if (!image)
        return 0;
    return static_cast<size_t>(image->getPixelCount()) * image->getBpp();
}

size_t SpriteManager::getIndexMemoryUsage() const
{
    size_t bytes = m_cachedData.size() * sizeof(CachedSpriteData);
    bytes += m_spriteData.capacity() * sizeof(CachedSpriteData);
    return bytes;
}

size_t SpriteManager::getSpriteCacheMemoryUsage() const
{
    std::lock_guard<std::mutex> lock(m_cacheMutex);
    return m_spriteCacheBytes;
}

size_t SpriteManager::getSpriteCacheMemoryLimit() const
{
    std::lock_guard<std::mutex> lock(m_cacheMutex);
    return m_spriteCacheMaxBytes;
}

size_t SpriteManager::getSpriteCacheSize() const
{
    std::lock_guard<std::mutex> lock(m_cacheMutex);
    return m_spriteCache.size();
}

size_t SpriteManager::getSpriteCacheMaxSprites() const
{
    std::lock_guard<std::mutex> lock(m_cacheMutex);
    return m_spriteCacheMaxSprites;
}

std::string SpriteManager::getSpriteModeName() const
{
    switch (m_spriteMode) {
    case SpriteMode::SprLegacy:
        return "spr normal";
    case SpriteMode::SprOtv8:
        return "spr OTV8";
    case SpriteMode::Cwm:
        return "cwm";
    default:
        return "unloaded";
    }
}

std::string SpriteManager::getCacheStats()
{
    const double indexMb = static_cast<double>(getIndexMemoryUsage()) / (1024.0 * 1024.0);
    const double cacheMb = static_cast<double>(getSpriteCacheMemoryUsage()) / (1024.0 * 1024.0);
    const double cacheLimitMb = static_cast<double>(getSpriteCacheMemoryLimit()) / (1024.0 * 1024.0);
    return stdext::format("mode=%s sprites=%d index=%.2f MB cache=%.2f/%.2f MB cachedSprites=%zu/%zu",
                          getSpriteModeName(),
                          m_spritesCount,
                          indexMb,
                          cacheMb,
                          cacheLimitMb,
                          getSpriteCacheSize(),
                          getSpriteCacheMaxSprites());
}

void SpriteManager::logCacheStats()
{
    g_logger.info(stdext::format("[SpriteManager] %s", getCacheStats()));
}
