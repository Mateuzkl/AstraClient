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

#include "texturemanager.h"
#include "animatedtexture.h"
#include "graphics.h"
#include "image.h"

#include <framework/core/config.h>
#include <framework/core/configmanager.h>
#include <framework/core/resourcemanager.h>
#include <framework/core/clock.h>
#include <framework/core/eventdispatcher.h>
#include <framework/graphics/apngloader.h>
#include <framework/util/stats.h>

TextureManager g_textures;

void TextureManager::init()
{
    scheduleCleanup();
}

void TextureManager::terminate()
{
    if (m_cleanupEvent) {
        m_cleanupEvent->cancel();
        m_cleanupEvent = nullptr;
    }

    m_textures.clear();
    m_animatedTextures.clear();
}

void TextureManager::clearCache()
{
    m_animatedTextures.clear();
    m_textures.clear();
}

void TextureManager::reload()
{
    for(auto& it : m_textures) {
        const std::string& path = g_resources.guessFilePath(it.first, "png");
        const TexturePtr& tex = it.second;

        ImagePtr image = Image::load(path);
        if(!image)
            continue;
        tex->replace(image);
        tex->setTime(stdext::time());
    }
}

TexturePtr TextureManager::getTexture(const std::string& fileName)
{
    auto it = m_textures.find(fileName);
    if (it != m_textures.end()) {
        it->second->setTime(stdext::time());
        return it->second;
    }

    TexturePtr texture;

    // before must resolve filename to full path
    std::string filePath = g_resources.resolvePath(fileName);

    // check if the texture is already loaded
    it = m_textures.find(filePath);
    if(it != m_textures.end()) {
        texture = it->second;
        texture->setTime(stdext::time());
    }

    // texture not found, load it
    if(!texture) {
        try {
            std::string filePathEx = g_resources.guessFilePath(filePath, "png");

            // load texture file data
            std::stringstream fin;
            g_resources.readFileStream(filePathEx, fin);
            texture = loadTexture(fin, filePath);
        } catch(stdext::exception& e) {
            g_logger.error(stdext::format("Unable to load texture '%s': %s", fileName, e.what()));
            texture = nullptr;
        }

        if(texture) {
            texture->setTime(stdext::time());
            texture->setSmooth(true);
            m_textures[filePath] = texture;
            m_textures[fileName] = texture;
        }
    }

    return texture;
}

TexturePtr TextureManager::loadTexture(std::stringstream& file, const std::string& source)
{
    TexturePtr texture;

    apng_data apng;
    if(load_apng(file, &apng) == 0) {
        Size imageSize(apng.width, apng.height);
#ifndef NDEBUG
        if ((apng.width > 512 || apng.height > 512) && source.find("background") == std::string::npos) {
            // this warnining is disabled for background image
            g_logger.warning(stdext::format("Texture %s has size %ix%i. Too keep highest performance you shouldn't use textures bigger than 512x512 (they can't be cached)", source, apng.width, apng.height));
        }
#endif
        if(apng.num_frames > 1) { // animated texture
            std::vector<ImagePtr> frames;
            std::vector<int> framesDelay;
            for(uint i=0;i<apng.num_frames;++i) {
                uchar *frameData = apng.pdata + ((apng.first_frame+i) * imageSize.area() * apng.bpp);
                int frameDelay = apng.frames_delay[i];

                framesDelay.push_back(frameDelay);
                frames.emplace_back(std::make_shared<Image>(imageSize, apng.bpp, frameData));
            }
            auto animatedTexture = std::make_shared<AnimatedTexture>(imageSize, frames, framesDelay);
            m_animatedTextures.push_back(animatedTexture);
            texture = animatedTexture;
        } else {
            auto image = std::make_shared<Image>(imageSize, apng.bpp, apng.pdata);
            if (!image) {
                g_logger.error(stdext::format("Can't load texture: %s", source));
            } else {
                texture = std::make_shared<Texture>(image);
            }
        }
        free_apng(&apng);
    }

    return texture;
}

void TextureManager::loadTextureTransparentPixels(const std::string& fileName)
{
    TexturePtr texture;

    std::string filePath = g_resources.resolvePath(fileName);

    auto it = m_textures.find(fileName);
    if (it != m_textures.end()) {
        texture = it->second;
    }

    if (!texture) {
        return;
    }

    std::string filePathEx = g_resources.guessFilePath(filePath, "png");

    // load texture file data
    std::stringstream file;
    g_resources.readFileStream(filePathEx, file);

    apng_data apng;
    if (load_apng(file, &apng) == 0) {
        Size imageSize(apng.width, apng.height);
        auto image = std::make_shared<Image>(imageSize, apng.bpp, apng.pdata);
        if (!image) {
            g_logger.error(stdext::format("Can't load texture: %s", filePath));
        }
        else {
            texture->loadTransparentPixels(image);
            image = nullptr;
        }
        free_apng(&apng);
    }
}

size_t TextureManager::getLoadedTexturesCount() const
{
    std::unordered_set<const Texture*> uniqueTextures;
    uniqueTextures.reserve(m_textures.size());
    for (const auto& it : m_textures) {
        if (it.second)
            uniqueTextures.insert(it.second.get());
    }
    return uniqueTextures.size();
}

size_t TextureManager::getEstimatedMemoryUsage() const
{
    std::unordered_set<const Texture*> uniqueTextures;
    uniqueTextures.reserve(m_textures.size());

    size_t bytes = 0;
    for (const auto& it : m_textures) {
        const TexturePtr& texture = it.second;
        if (!texture || !uniqueTextures.insert(texture.get()).second)
            continue;
        bytes += texture->getEstimatedMemoryUsage();
    }
    return bytes;
}

std::string TextureManager::getCacheStats()
{
    const double mb = static_cast<double>(getEstimatedMemoryUsage()) / (1024.0 * 1024.0);
    return stdext::format("textures=%zu animated=%zu approx=%.2f MB mapEntries=%zu",
                          getLoadedTexturesCount(),
                          getAnimatedTexturesCount(),
                          mb,
                          m_textures.size());
}

void TextureManager::logCacheStats()
{
    g_logger.info(stdext::format("[TextureManager] %s", getCacheStats()));
}

int TextureManager::clearUnusedTextures()
{
    return clearUnusedTexturesImpl(true);
}

int TextureManager::clearUnusedTexturesImpl(bool forceLog)
{
    configureUnusedTextureCleanupFromSettings();

    const ticks_t now = stdext::time();
    const int maxAgeSeconds = std::max(m_unusedTextureMaxAgeSeconds, 0);

    std::unordered_map<Texture*, size_t> managerRefs;
    managerRefs.reserve(m_textures.size() + m_animatedTextures.size());

    for (const auto& it : m_textures) {
        if (it.second)
            ++managerRefs[it.second.get()];
    }

    for (const AnimatedTexturePtr& texture : m_animatedTextures) {
        if (texture)
            ++managerRefs[texture.get()];
    }

    std::unordered_set<Texture*> removable;
    size_t freedBytes = 0;
    for (const auto& it : m_textures) {
        const TexturePtr& texture = it.second;
        if (!texture || !texture->canCache())
            continue;

        Texture* raw = texture.get();
        if (removable.find(raw) != removable.end())
            continue;

        if (texture->getTime() + maxAgeSeconds >= now)
            continue;

        auto refsIt = managerRefs.find(raw);
        const size_t internalRefs = refsIt == managerRefs.end() ? 0 : refsIt->second;
        if (texture.use_count() <= internalRefs) {
            removable.insert(raw);
            freedBytes += texture->getEstimatedMemoryUsage();
        }
    }

    if (removable.empty()) {
        logUnusedTextureCleanup(0, 0, 0, forceLog);
        return 0;
    }

    size_t removedEntries = 0;
    for (auto it = m_textures.begin(); it != m_textures.end();) {
        if (it->second && removable.find(it->second.get()) != removable.end()) {
            it = m_textures.erase(it);
            ++removedEntries;
        } else {
            ++it;
        }
    }

    m_animatedTextures.erase(std::remove_if(m_animatedTextures.begin(), m_animatedTextures.end(),
                                            [&removable](const AnimatedTexturePtr& texture) {
                                                return texture && removable.find(texture.get()) != removable.end();
                                            }),
                             m_animatedTextures.end());

    logUnusedTextureCleanup(removable.size(), removedEntries, freedBytes, forceLog);
    return static_cast<int>(removable.size());
}

void TextureManager::setUnusedTextureCleanupConfig(int maxAgeSeconds, int logIntervalSeconds)
{
    m_unusedTextureMaxAgeSeconds = std::max(maxAgeSeconds, 0);
    m_unusedTextureCleanupLogIntervalSeconds = std::max(logIntervalSeconds, 0);
}

void TextureManager::configureUnusedTextureCleanupFromSettings()
{
    ConfigPtr settings = g_configs.getSettings();
    if (!settings)
        return;

    int maxAgeSeconds = m_unusedTextureMaxAgeSeconds;
    int logIntervalSeconds = m_unusedTextureCleanupLogIntervalSeconds;

    if (settings->exists("textureCacheMaxSeconds"))
        maxAgeSeconds = stdext::from_string<int>(settings->getValue("textureCacheMaxSeconds"), maxAgeSeconds);
    if (settings->exists("textureCleanupLogSeconds"))
        logIntervalSeconds = stdext::from_string<int>(settings->getValue("textureCleanupLogSeconds"), logIntervalSeconds);

    setUnusedTextureCleanupConfig(maxAgeSeconds, logIntervalSeconds);
}

void TextureManager::scheduleCleanup()
{
    if (m_cleanupEvent)
        return;

    m_cleanupEvent = g_dispatcher.scheduleEvent(std::bind(&TextureManager::scheduledCleanup, &g_textures), 30000);
}

void TextureManager::scheduledCleanup()
{
    m_cleanupEvent = nullptr;
    clearUnusedTexturesImpl(false);
    scheduleCleanup();
}

void TextureManager::logUnusedTextureCleanup(size_t removedTextures, size_t removedEntries, size_t freedBytes, bool forceLog)
{
    if (removedTextures == 0 && !forceLog)
        return;

    const ticks_t now = stdext::time();
    if (!forceLog && m_unusedTextureCleanupLogIntervalSeconds > 0 &&
        m_lastUnusedTextureCleanupLog + m_unusedTextureCleanupLogIntervalSeconds > now) {
        return;
    }

    m_lastUnusedTextureCleanupLog = now;
    const double mb = static_cast<double>(freedBytes) / (1024.0 * 1024.0);
    g_logger.info(stdext::format("[TextureManager] cleanup removedTextures=%zu removedEntries=%zu freed=%.2f MB maxAge=%ds",
                                 removedTextures,
                                 removedEntries,
                                 mb,
                                 m_unusedTextureMaxAgeSeconds));
}
