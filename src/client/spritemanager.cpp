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
#include "spritedecoder.h"
#include "indexedspr.h"
#include "game.h"
#include "thingtypemanager.h"
#include <framework/core/resourcemanager.h>
#include <framework/core/filestream.h>
#ifdef __EMSCRIPTEN__
#include <framework/core/startuptimer.h>
#endif
#include <framework/graphics/image.h>
#include <framework/graphics/atlas.h>
#include <framework/core/eventdispatcher.h>
#include <framework/graphics/xbrz.h>
#include <framework/util/crypt.h>
#include <framework/util/pngunpacker.h>

#include <algorithm>
#include <new>

SpriteManager g_sprites;

namespace
{
constexpr int MinScaleFactor = 1;
constexpr int MaxScaleFactor = 4;
constexpr size_t MaxImageCacheEntries = 2000;
constexpr size_t MaxImageCacheBytes = 32 * 1024 * 1024;
}

SpriteManager::SpriteManager()
{
    m_spritesCount = 0;
    m_signature = 0;
    updateSpriteSize();
}

void SpriteManager::terminate()
{
    unload();
}

std::string SpriteManager::resolveIndexedFolder(const std::string& path) const
{
    return IndexedSpr::resolveFolder(path, [](const std::string& candidate) {
        return g_resources.fileExists(candidate);
    });
}

bool SpriteManager::isIndexedSource(const std::string& path) const
{
    return !resolveIndexedFolder(path).empty();
}

bool SpriteManager::loadSpr(std::string file)
{
#ifdef __EMSCRIPTEN__
    g_app.setStartupStage("Loading Tibia sprites...");
    StartupTimer timer("sprLoad");
#endif
    unload();

    // Detection and loading use the same rule, including packs which retain
    // a conventional Tibia.spr or Tibia.cwm alongside their manifests.
    const std::string indexedFolder = resolveIndexedFolder(file);
    if (!indexedFolder.empty())
        return loadIndexedSpr(indexedFolder);

    // 1. Explicit / Conventional CWM
    auto cwmFile = g_resources.guessFilePath(file, "cwm");
    if (g_resources.fileExists(cwmFile)) {
        m_isHdMod = true;
        return loadCwmSpr(cwmFile);
    }

    // 2. Explicit / Conventional Monolithic SPR
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
    if (!m_spritesFile)
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
                std::vector<char> spriteData(dataSize);
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
    if (!m_spritesFile || m_baseSpriteSize != 32)
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
            ImagePtr sprite = getSpriteImageCasual(i);
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

                stdext::writeULE16(buffer.data() + bufferPos, static_cast<uint16_t>(transparent));
                bufferPos += 2;
                stdext::writeULE16(buffer.data() + bufferPos, static_cast<uint16_t>(colored));
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
        fin->addU32(stdext::readULE32(reinterpret_cast<const uint8_t*>(otcv8Signature)));
        fin->addU32(m_signature);
        fin->addU32(m_spritesCount);

        for (int i = 1; i <= m_spritesCount; i++) {
            ImagePtr sprite = getSpriteImageCasual(i);
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

                stdext::writeULE16(buffer.data() + bufferPos, static_cast<uint16_t>(transparent));
                bufferPos += 2;
                stdext::writeULE16(buffer.data() + bufferPos, static_cast<uint16_t>(colored));
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
    m_spritesCount = 0;
    m_signature = 0;
    m_loaded = false;
    m_isHdMod = false;
    m_isIndexed = false;
    m_spritesFile = nullptr;
    m_parts.clear();
    // A large indexed pack must not retain its logical index after switching
    // back to a monolithic SPR or unloading the client assets.
    std::vector<uint32>().swap(m_index);
    m_spriteAddresses.clear();
    m_sprites.clear();
    m_cachedData.clear();
    clearImageCache();
    m_baseSpriteSize = 32;
    updateSpriteSize();
}

ImagePtr SpriteManager::getSpriteImage(int id)
{
    if (id <= 0 || !m_loaded)
        return nullptr;

    if (m_isHdMod) {
        return getSpriteImageHd(id);
    }

    auto it = m_imageCache.find(id);
    if (it != m_imageCache.end()) {
        m_imageCacheLru.splice(m_imageCacheLru.begin(), m_imageCacheLru, it->second.lruIt);
        return it->second.image;
    }

    ImagePtr baseSprite = getSpriteImageCasual(id);
    ImagePtr scaledSprite = m_scaleFactor > 1 ? upscaleSprite(baseSprite, m_scaleFactor) : baseSprite;
    if (!scaledSprite)
        return baseSprite;

    const size_t imageBytes = static_cast<size_t>(scaledSprite->getPixelCount()) * scaledSprite->getBpp();
    while (!m_imageCacheLru.empty() &&
           (m_imageCache.size() >= MaxImageCacheEntries || m_imageCacheBytes + imageBytes > MaxImageCacheBytes)) {
        const int oldestId = m_imageCacheLru.back();
        m_imageCacheLru.pop_back();

        auto oldest = m_imageCache.find(oldestId);
        if (oldest != m_imageCache.end()) {
            m_imageCacheBytes -= oldest->second.bytes;
            m_imageCache.erase(oldest);
        }
    }

    m_imageCacheLru.push_front(id);
    m_imageCache.emplace(id, ImageCacheEntry{ scaledSprite, imageBytes, m_imageCacheLru.begin() });
    m_imageCacheBytes += imageBytes;
    return scaledSprite;
}

void SpriteManager::setScaleFactor(int factor)
{
    factor = std::clamp(factor, MinScaleFactor, MaxScaleFactor);
    if (m_scaleFactor == factor)
        return;

    m_scaleFactor = factor;
    if (!m_isHdMod)
        updateSpriteSize();

    clearImageCache();
}

void SpriteManager::clearImageCache()
{
    m_imageCache.clear();
    m_imageCacheLru.clear();
    m_imageCacheBytes = 0;
}

void SpriteManager::updateSpriteSize()
{
    m_spriteSize = m_baseSpriteSize * std::max(MinScaleFactor, m_scaleFactor);
}

ImagePtr SpriteManager::upscaleSprite(const ImagePtr& sprite, int scaleFactor) const
{
    if (!sprite || scaleFactor <= 1)
        return sprite;

    scaleFactor = std::clamp(scaleFactor, MinScaleFactor, MaxScaleFactor);
    if (sprite->getBpp() != 4)
        return sprite;

    // Note: This try/catch protects against allocation or processing failures inside upscaleSprite().
    // It does not protect against subsequent RAM/VRAM allocation failures during Texture creation or atlas building.
    try {
        const int sourceWidth = sprite->getWidth();
        const int sourceHeight = sprite->getHeight();
        const int targetWidth = sourceWidth * scaleFactor;
        const int targetHeight = sourceHeight * scaleFactor;
        const int pixelCount = sourceWidth * sourceHeight;

        if (sourceWidth <= 0 || sourceHeight <= 0 || targetWidth <= 0 || targetHeight <= 0)
            return sprite;

        std::vector<uint32_t> sourcePixels(pixelCount);
        const std::vector<uint8>& sourceData = sprite->getPixels();
        for (int i = 0; i < pixelCount; ++i) {
            const int offset = i * 4;
            sourcePixels[i] = (static_cast<uint32_t>(sourceData[offset + 3]) << 24) |
                              (static_cast<uint32_t>(sourceData[offset + 0]) << 16) |
                              (static_cast<uint32_t>(sourceData[offset + 1]) << 8) |
                              static_cast<uint32_t>(sourceData[offset + 2]);
        }

        std::vector<uint32_t> targetPixels(static_cast<size_t>(targetWidth) * targetHeight);
        xbrz::scale(scaleFactor, sourcePixels.data(), targetPixels.data(), sourceWidth, sourceHeight, xbrz::ColorFormat::ARGB);

        auto upscaledImage = std::make_shared<Image>(Size(targetWidth, targetHeight));
        std::vector<uint8>& targetData = upscaledImage->getPixels();
        for (size_t i = 0; i < targetPixels.size(); ++i) {
            const uint32_t pixel = targetPixels[i];
            const size_t offset = i * 4;
            targetData[offset + 0] = static_cast<uint8>((pixel >> 16) & 0xFF);
            targetData[offset + 1] = static_cast<uint8>((pixel >> 8) & 0xFF);
            targetData[offset + 2] = static_cast<uint8>(pixel & 0xFF);
            targetData[offset + 3] = static_cast<uint8>((pixel >> 24) & 0xFF);
        }

        return upscaledImage;
    } catch (const std::bad_alloc&) {
        static bool s_warned = false;
        if (!s_warned) {
            s_warned = true;
            g_logger.warning("HD Sprite Upscaling: out of memory during xBRZ upscale — falling back to original sprite");
        }
        return sprite;
    } catch (const std::exception& e) {
        static bool s_warned = false;
        if (!s_warned) {
            s_warned = true;
            g_logger.warning(stdext::format("HD Sprite Upscaling: upscale failed (%s) — falling back to original sprite", e.what()));
        }
        return sprite;
    }
}

bool SpriteManager::loadCasualSpr(std::string file)
{
    m_baseSpriteSize = 32;
    updateSpriteSize();
    try {
        file = g_resources.guessFilePath(file, "spr");

        // SPR packs can be hundreds of MiB. Keep only their index and
        // stream individual records; ResourceManager still buffers encrypted
        // or compressed files when seeking requires it. Browser preload files
        // already live in MEMFS; buffering again only duplicates the whole pack.
        m_spritesFile = g_resources.openFile(file, true);

        m_signature = m_spritesFile->getU32();
        if (m_signature == *((uint32_t*)"OTV8")) {
            // This format already retains every encrypted record in m_sprites.
            // Preserve its sequential buffering policy rather than issuing one
            // filesystem read per length field during the entire-pack import.
            m_spritesFile = g_resources.openFile(file, g_game.getFeature(Otc::GameDontCacheFiles));
            m_spritesFile->getU32();
            m_signature = m_spritesFile->getU32();
            m_spritesCount = m_spritesFile->getU32();
            m_sprites.resize(m_spritesCount + 1);
            for (int i = 1; i <= m_spritesCount; ++i) {
                int bufferSize = m_spritesFile->getU16();
                if (bufferSize == 0) continue;
                m_sprites[i].resize(bufferSize + 1);
                m_sprites[i][0] = 0;
                m_spritesFile->read(m_sprites[i].data() + 1, bufferSize);
            }
            m_spritesFile = nullptr;
        }
        else {
            m_spritesCount = g_game.getFeature(Otc::GameSpritesU32) ? m_spritesFile->getU32() : m_spritesFile->getU16();
            const uint32 indexOffset = m_spritesFile->tell();
            m_spritesOffset = indexOffset;
            const uint32 fileSize = m_spritesFile->size();
            if (indexOffset > fileSize || static_cast<uint32>(m_spritesCount) > (fileSize - indexOffset) / 4)
                stdext::throw_exception("Invalid sprite address table");

            m_spriteAddresses.resize(m_spritesCount);
            const uint32 indexBytes = static_cast<uint32>(m_spritesCount) * 4;
            if (m_spritesFile->read(m_spriteAddresses.data(), 1, indexBytes) != indexBytes)
                stdext::throw_exception("Incomplete sprite address table");
            for (uint32& address : m_spriteAddresses)
                address = stdext::readULE32(reinterpret_cast<const uint8*>(&address));
        }
        m_loaded = true;
        g_lua.callGlobalField("g_sprites", "onLoadSpr", file);
        return true;
    }
    catch (stdext::exception& e) {
        g_logger.error(stdext::format("Failed to load sprites from '%s': %s", file, e.what()));
        m_spritesFile = nullptr;
        m_spriteAddresses.clear();
        return false;
    }
}

bool SpriteManager::loadCwmSpr(std::string file)
{
    try {
        auto inFilePath = g_resources.guessFilePath(file, "cwm");
        auto spritesFile = g_resources.openFile(inFilePath, g_game.getFeature(Otc::GameDontCacheFiles));

        uint8_t version = spritesFile->getU8();
        if (version != 0x01) {
            g_logger.error(stdext::format("Invalid CWM file version - %s", file));
            return false;
        }

        m_spriteSize = spritesFile->getU16();
        m_baseSpriteSize = m_spriteSize;
        m_cachedData = std::move(PngUnpacker::unpack(spritesFile));
        m_spritesCount = m_cachedData.size();

        if (m_spritesCount == 0) {
            g_logger.error(stdext::format("Failed to load sprites from '%s' - no sprites", file));
            return false;
        }

        m_loaded = true;
        return true;
    }
    catch (stdext::exception& e) {
        g_logger.error(stdext::format("Failed to load sprites from '%s': %s", file, e.what()));
        return false;
    }

    return false;
}

bool SpriteManager::loadIndexedSpr(std::string folder)
{
    try {
        // 1. Load spr_parts.dat ("SPMT")
        std::string partsPath = folder + "/spr_parts.dat";
        auto partsFile = g_resources.openFile(partsPath, g_game.getFeature(Otc::GameDontCacheFiles));
        if (!partsFile) {
            g_logger.error(stdext::format("Indexed SPR: Failed to open %s", partsPath));
            unload();
            return false;
        }

        uint32 partsFileSize = partsFile->size();
        if (partsFileSize < 8) {
            g_logger.error(stdext::format("Indexed SPR: %s is smaller than 8-byte header (%u bytes)", partsPath, partsFileSize));
            unload();
            return false;
        }

        uint32 partsMagic = partsFile->getU32();
        if (partsMagic != 0x544D5053) { // 'SPMT' in little-endian
            g_logger.error(stdext::format("Indexed SPR: Invalid magic in %s (expected 'SPMT')", partsPath));
            unload();
            return false;
        }

        uint32 partCount = partsFile->getU32();
        if (partCount == 0 || partCount > 10000) {
            g_logger.error(stdext::format("Indexed SPR: Invalid part count (%u) in %s", partCount, partsPath));
            unload();
            return false;
        }

        uint32 maxPartsByFile = (partsFileSize - 8) / (sizeof(uint32) * 2);
        if (partCount > maxPartsByFile) {
            g_logger.error(stdext::format("Indexed SPR: Truncated %s: declares %u parts but file only has room for %u",
                partsPath, partCount, maxPartsByFile));
            unload();
            return false;
        }

        m_parts.clear();
        m_parts.resize(partCount);
        uint64 totalManifestSprites = 0;
        for (uint32 i = 0; i < partCount; ++i) {
            m_parts[i].signature = partsFile->getU32();
            m_parts[i].spriteCount = partsFile->getU32();
            if (m_parts[i].spriteCount > IndexedSpr::MaxLocalSprites)
                stdext::throw_exception("Indexed SPR: Part count does not fit the 16-bit local sprite ID");
            m_parts[i].fileSize = 0;
            m_parts[i].file = nullptr;
            totalManifestSprites += m_parts[i].spriteCount;
        }

        if (totalManifestSprites > IndexedSpr::MaxSprites) {
            g_logger.error(stdext::format("Indexed SPR: Total manifest sprite count exceeds the supported limit (%llu)", totalManifestSprites));
            unload();
            return false;
        }

        // Open and strictly validate each part file
        for (uint32 i = 0; i < partCount; ++i) {
            std::string partNumStr = std::to_string(i + 1);
            std::string partPath = folder + "/FileParts/part_" + partNumStr + ".spr";
            if (!g_resources.fileExists(partPath)) {
                partPath = folder + "/part_" + partNumStr + ".spr";
            }

            if (!g_resources.fileExists(partPath)) {
                g_logger.error(stdext::format("Indexed SPR: Part file missing: %s", partPath));
                unload();
                return false;
            }

            // Keep the small offset table, not every part's pixel payload, in
            // RAM. Encrypted/compressed resources retain their normal buffering.
            auto partFile = g_resources.openFile(partPath, true);
            if (!partFile) {
                g_logger.error(stdext::format("Indexed SPR: Failed to open part file: %s", partPath));
                unload();
                return false;
            }

            uint32 partFileSize = partFile->size();
            if (partFileSize < 8) {
                g_logger.error(stdext::format("Indexed SPR: Part %u file %s is smaller than 8-byte header (%u bytes)",
                    i + 1, partPath, partFileSize));
                unload();
                return false;
            }

            uint32 sig = partFile->getU32();
            uint32 localCount = partFile->getU32();

            // Strict signature check: must be a hard error!
            if (sig != m_parts[i].signature) {
                g_logger.error(stdext::format("Indexed SPR: Part %u signature mismatch in %s (expected 0x%08X, got 0x%08X)",
                    i + 1, partPath, m_parts[i].signature, sig));
                unload();
                return false;
            }

            // Strict local count check: must be a hard error!
            if (localCount != m_parts[i].spriteCount) {
                g_logger.error(stdext::format("Indexed SPR: Part %u sprite count mismatch in %s (manifest declares %u, part header declares %u)",
                    i + 1, partPath, m_parts[i].spriteCount, localCount));
                unload();
                return false;
            }

            // Offset table bounds check: offset table must fit inside part file
            uint32 maxTableEntries = (partFileSize - 8) / sizeof(uint32);
            if (localCount > maxTableEntries) {
                g_logger.error(stdext::format("Indexed SPR: Part %u table truncated in %s: %u sprites declared but file capacity is %u",
                    i + 1, partPath, localCount, maxTableEntries));
                unload();
                return false;
            }

            m_parts[i].fileSize = partFileSize;
            auto& addresses = m_parts[i].addresses;
            addresses.resize(localCount);
            const uint32 tableBytes = localCount * sizeof(uint32);
            if (tableBytes > 0 && partFile->read(addresses.data(), 1, tableBytes) != static_cast<int>(tableBytes))
                stdext::throw_exception("Indexed SPR: Incomplete part address table");
            for (uint32& address : addresses) {
                address = stdext::readULE32(reinterpret_cast<const uint8*>(&address));
                if (address != 0 && (address < 8 + tableBytes || !IndexedSpr::rangeFits(address, 5, partFileSize)))
                    stdext::throw_exception("Indexed SPR: Invalid part sprite address");
            }
            m_parts[i].file = std::move(partFile);
        }

        // 2. Load spr_index.dat ("SPIX")
        std::string indexPath = folder + "/spr_index.dat";
        auto indexFile = g_resources.openFile(indexPath, g_game.getFeature(Otc::GameDontCacheFiles));
        if (!indexFile) {
            g_logger.error(stdext::format("Indexed SPR: Failed to open %s", indexPath));
            unload();
            return false;
        }

        uint32 indexFileSize = indexFile->size();
        if (indexFileSize < 12) {
            g_logger.error(stdext::format("Indexed SPR: %s is smaller than 12-byte header (%u bytes)", indexPath, indexFileSize));
            unload();
            return false;
        }

        uint32 indexMagic = indexFile->getU32();
        if (indexMagic != 0x58495053) { // 'SPIX' in little-endian
            g_logger.error(stdext::format("Indexed SPR: Invalid magic in %s (expected 'SPIX')", indexPath));
            unload();
            return false;
        }

        uint32 indexVersion = indexFile->getU32();
        if (indexVersion != 1) {
            g_logger.error(stdext::format("Indexed SPR: Unsupported index version (%u) in %s (expected 1)", indexVersion, indexPath));
            unload();
            return false;
        }

        uint32 logicalSpriteCount = indexFile->getU32();
        if (logicalSpriteCount == 0 || logicalSpriteCount > IndexedSpr::MaxSprites) {
            g_logger.error(stdext::format("Indexed SPR: Invalid logical sprite count (%u) in %s", logicalSpriteCount, indexPath));
            unload();
            return false;
        }

        uint32 remainingIndexBytes = indexFileSize - 12;
        if (logicalSpriteCount > remainingIndexBytes / sizeof(uint32)) {
            g_logger.error(stdext::format("Indexed SPR: Truncated %s: declares %u sprites but only %u entries remain",
                indexPath, logicalSpriteCount, remainingIndexBytes / sizeof(uint32)));
            unload();
            return false;
        }

        if (totalManifestSprites != logicalSpriteCount) {
            g_logger.warning(stdext::format("Indexed SPR: Manifest total sprites (%llu) does not match index count (%u)",
                totalManifestSprites, logicalSpriteCount));
        }

        // Pre-allocate index and validate every packed locator
        m_index.clear();
        m_index.resize(static_cast<size_t>(logicalSpriteCount) + 1, 0);
        const uint32 indexBytes = logicalSpriteCount * sizeof(uint32);
        if (indexFile->read(m_index.data() + 1, 1, indexBytes) != static_cast<int>(indexBytes))
            stdext::throw_exception("Indexed SPR: Incomplete logical sprite index");

        for (uint32 i = 1; i <= logicalSpriteCount; ++i) {
            uint32 packed = stdext::readULE32(reinterpret_cast<const uint8*>(&m_index[i]));
            uint32 partNumber = (packed >> 16) & 0xFFFF;
            uint32 localId = packed & 0xFFFF;

            if (packed == 0 || partNumber == 0 || partNumber > m_parts.size() || localId == 0 || localId > m_parts[partNumber - 1].spriteCount) {
                g_logger.error(stdext::format("Indexed SPR: Invalid locator 0x%08X at index %u (part %u/%u, local %u)",
                    packed, i, partNumber, (uint32)m_parts.size(), localId));
                unload();
                return false;
            }
            m_index[i] = packed;
        }

        m_spritesCount = static_cast<int>(logicalSpriteCount);
        m_signature = m_parts.empty() ? 0 : m_parts[0].signature;
        m_isIndexed = true;
        m_loaded = true;

        g_logger.info(stdext::format("Indexed SPR loaded successfully: %u sprites across %u parts from '%s'",
            logicalSpriteCount, (uint32)m_parts.size(), folder));

        g_lua.callGlobalField("g_sprites", "onLoadSpr", folder);
        return true;
    }
    catch (const std::bad_alloc&) {
        g_logger.error(stdext::format("Indexed SPR: Out of memory while loading from '%s'", folder));
        unload();
        return false;
    }
    catch (const std::exception& e) {
        g_logger.error(stdext::format("Failed to load indexed sprites from '%s': %s", folder, e.what()));
        unload();
        return false;
    }
}

ImagePtr SpriteManager::getSpriteImageCasual(int id)
{
    try {
        if (id <= 0)
            return nullptr;

        if (m_isIndexed) {
            return getSpriteImageIndexed(id);
        }

        int spriteDataSize = m_baseSpriteSize * m_baseSpriteSize * 4;

        if (!m_sprites.empty()) {
            if (id >= (int)m_sprites.size())
                return nullptr;
            auto& buffer = m_sprites[id];
            if (buffer.size() < 5)
                return nullptr;
            if (buffer[0] == 0) {
                buffer[0] = 1;
                g_crypt.bdecrypt(buffer.data() + 1, buffer.size() - 1, (uint64_t)m_signature + id);
            }

            if (buffer[1] > 1) {
                stdext::throw_exception("Invalid sprite encryption");
            }

            bool hasAlpha = (buffer[1] == 1);

            auto image = std::make_shared<Image>(Size(m_baseSpriteSize, m_baseSpriteSize));
            uint8* pixels = image->getPixelData();
            int writePos = 0;

            size_t bufferPos = 2;
            while (bufferPos < buffer.size()) {
                if (buffer.size() - bufferPos < 4)
                    stdext::throw_exception("Invalid sprite data header");

                uint16_t transparentPixels = stdext::readULE16(&buffer[bufferPos]);
                bufferPos += 2;
                uint16_t coloredPixels = stdext::readULE16(&buffer[bufferPos]);
                bufferPos += 2;

                const int remainingPixels = (spriteDataSize - writePos) / 4;
                if (writePos < 0 || writePos > spriteDataSize || transparentPixels > remainingPixels)
                    stdext::throw_exception("Invalid transparent sprite run");
                writePos += transparentPixels * 4;

                const int coloredCapacity = (spriteDataSize - writePos) / 4;
                const size_t bytesPerPixel = hasAlpha ? 4 : 3;
                if (coloredPixels > coloredCapacity ||
                    static_cast<size_t>(coloredPixels) > (buffer.size() - bufferPos) / bytesPerPixel)
                    stdext::throw_exception("Invalid colored sprite run");

                for (int i = 0; i < coloredPixels; ++i) {
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

            if (writePos != spriteDataSize)
                stdext::throw_exception("Incomplete sprite data");

            return image;
        }

        if (id <= 0 || id > m_spritesCount || !m_spritesFile)
            return nullptr;

        const uint32 spriteAddress = m_spriteAddresses[id - 1];

        // no sprite? return an empty texture
        if (spriteAddress == 0)
            return nullptr;

        m_spritesFile->seek(spriteAddress);

        // Read the record in bulk instead of doing filesystem I/O per channel.
        uint8 header[5];
        if (m_spritesFile->read(header, 1, sizeof(header)) != sizeof(header))
            stdext::throw_exception("Incomplete sprite header");
        const uint16 pixelDataSize = stdext::readULE16(header + 3);
        std::vector<uint8> data(pixelDataSize);
        if (m_spritesFile->read(data.data(), 1, pixelDataSize) != pixelDataSize)
            stdext::throw_exception("Incomplete sprite pixels");

        auto image = std::make_shared<Image>(Size(m_baseSpriteSize, m_baseSpriteSize));

        if (!SpriteDecoder::decode(data.data(), data.size(), image->getPixelData(), spriteDataSize,
                                   g_game.getFeature(Otc::GameSpritesAlphaChannel)))
            stdext::throw_exception("Invalid sprite pixel runs");

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

    if (m_cachedData.find(id) == m_cachedData.end())
    {
        return nullptr;
    }

    try {
        return Image::loadPNG(m_cachedData[id].data(), m_cachedData[id].size());
    } catch (...) {}
    return nullptr;
}

ImagePtr SpriteManager::getSpriteImageIndexed(int id)
{
    try {
        if (id <= 0 || (size_t)id >= m_index.size())
            return nullptr;

        uint32 packed = m_index[id];
        uint32 partNum = (packed >> 16) & 0xFFFF;
        uint32 localId = packed & 0xFFFF;

        if (partNum == 0 || partNum > m_parts.size() || localId == 0)
            return nullptr;

        const auto& part = m_parts[partNum - 1];
        if (!part.file || localId > part.addresses.size())
            return nullptr;

        const uint32 spriteAddress = part.addresses[localId - 1];
        if (spriteAddress == 0)
            return nullptr;

        // Validate address: must be past table and leave at least 5 bytes for color key (3) + size (2)
        const uint32 minDataOffset = 8 + (part.spriteCount * sizeof(uint32));
        if (spriteAddress < minDataOffset || !IndexedSpr::rangeFits(spriteAddress, 5, part.fileSize))
            stdext::throw_exception("Indexed SPR: Invalid sprite record address");

        // Retain stream ownership locally and read the record in two bounded
        // bulk operations, rather than performing filesystem I/O per channel.
        const FileStreamPtr partFile = part.file;
        partFile->seek(spriteAddress);
        uint8 header[5];
        if (partFile->read(header, 1, sizeof(header)) != sizeof(header))
            stdext::throw_exception("Indexed SPR: Incomplete sprite header");
        const uint16 pixelDataSize = stdext::readULE16(header + 3);
        if (!IndexedSpr::rangeFits(spriteAddress + 5, pixelDataSize, part.fileSize))
            stdext::throw_exception("Indexed SPR: Incomplete sprite payload");
        std::vector<uint8> data(pixelDataSize);
        if (pixelDataSize > 0 && partFile->read(data.data(), 1, pixelDataSize) != pixelDataSize)
            stdext::throw_exception("Indexed SPR: Incomplete sprite pixels");

        auto image = std::make_shared<Image>(Size(m_baseSpriteSize, m_baseSpriteSize));
        if (!SpriteDecoder::decode(data.data(), data.size(), image->getPixelData(),
                                   image->getPixels().size(), g_game.getFeature(Otc::GameSpritesAlphaChannel)))
            stdext::throw_exception("Indexed SPR: Invalid sprite pixel runs");

        return image;
    }
    catch (const std::exception& e) {
        g_logger.error(stdext::format("Failed to get indexed sprite id %d: %s", id, e.what()));
        return nullptr;
    }
    catch (...) {
        return nullptr;
    }
}
