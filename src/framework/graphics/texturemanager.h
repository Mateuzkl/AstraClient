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

#ifndef TEXTUREMANAGER_H
#define TEXTUREMANAGER_H

#include "texture.h"
#include <framework/core/declarations.h>

class TextureManager
{
public:
    void init();
    void terminate();

    void clearCache();
    void reload();

    void preload(const std::string& fileName) { getTexture(fileName); }
    TexturePtr getTexture(const std::string& fileName);
    TexturePtr loadTexture(std::stringstream& file, const std::string& source);
    void loadTextureTransparentPixels(const std::string& fileName);
    size_t getLoadedTexturesCount() const;
    size_t getAnimatedTexturesCount() const { return m_animatedTextures.size(); }
    size_t getEstimatedMemoryUsage() const;
    std::string getCacheStats() const;
    void logCacheStats() const;
    int clearUnusedTextures();
    void setUnusedTextureCleanupConfig(int maxAgeSeconds, int logIntervalSeconds);

private:
    int clearUnusedTexturesImpl(bool forceLog);
    void configureUnusedTextureCleanupFromSettings();
    void scheduleCleanup();
    void scheduledCleanup();
    void logUnusedTextureCleanup(size_t removedTextures, size_t removedEntries, size_t freedBytes, bool forceLog);

    std::unordered_map<std::string, TexturePtr> m_textures;
    std::vector<AnimatedTexturePtr> m_animatedTextures;
    ScheduledEventPtr m_cleanupEvent;
    int m_unusedTextureMaxAgeSeconds = 120;
    int m_unusedTextureCleanupLogIntervalSeconds = 30;
    ticks_t m_lastUnusedTextureCleanupLog = 0;
};

extern TextureManager g_textures;

#endif
