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
#include <memory>

// Forward decl so the unique_ptr<SpriteSheetLoader> field below doesn't drag
// the loader's full header (and protobuf) into every TU that pulls in
// SpriteManager. Defaulted ctor/dtor live in the .cpp for the same reason.
class SpriteSheetLoader;

//@bindsingleton g_sprites
class SpriteManager
{
public:
    SpriteManager();
    ~SpriteManager();

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

    // Pixel cell dimensions (w,h) of the sprite that owns `spriteId`, taken from
    // the owning sheet's catalog "spritetype" (0=32x32, 1=32x64, 2=64x32, 3=64x64).
    // This is the AUTHORITATIVE storage size for proto (15.x) assets — needed so a
    // ThingType's m_size matches the real sprite footprint (a 2x2/64x64 sprite that
    // extends into the 3 SQMs above/left of its tile). Falls back to (spriteSize,
    // spriteSize) on the legacy .spr path or when the id is unmapped.
    std::pair<int, int> getSpriteCellSize(int spriteId) const;

    // True when sprites come from the 15.x protobuf sheet pipeline (catalog +
    // LZMA sheets) rather than the legacy .spr/.cwm. In protobuf mode one sprite
    // image is the full cell (e.g. 64x64) instead of being split into 32x32 sub-
    // sprites, so ThingType::getTexture must blit it whole.
    bool isUsingProtobuf() const { return m_sheetLoader != nullptr; }

    // Optional HD sprite mode. When enabled the texture scale becomes 2 and the
    // ThingType atlas builds from xBRZ-upscaled cells (getUpscaledSpriteImage),
    // giving sharper world sprites at the SAME on-screen size (spriteSize() stays
    // 32; only the texture is denser). UI sprites / tile-image pre-render / offline
    // tools keep using the native getSpriteImage path.
    void setHdSprites(bool enabled);
    int getTextureScale() const { return m_textureScale; }
    ImagePtr getUpscaledSpriteImage(int id);

private:
    bool loadCasualSpr(std::string file);
    bool loadCwmSpr(std::string file);

    ImagePtr getSpriteImageCasual(int id);
    ImagePtr getSpriteImageHd(int id);
    bool m_loaded = false;
    bool m_isHdMod = false;
    uint32 m_signature;
    int m_spritesCount;
    int m_spritesOffset;
    int m_spriteSize;
    FileStreamPtr m_spritesFile;
    std::vector<std::vector<uint8_t>> m_sprites;
    std::unordered_map<uint32, std::string> m_cachedData;

    // 15.24 protobuf path: when loadSpr is called with a directory containing
    // catalog-content.json, we own a SpriteSheetLoader that decompresses and
    // caches LZMA sheets on demand. Null when running the legacy .spr/.cwm path.
    std::unique_ptr<SpriteSheetLoader> m_sheetLoader;

    // HD sprite mode (optional). 1 = native, 2 = xBRZ 2x. m_upscaledCache memoizes
    // the upscaled cell per sprite id; cleared on toggle / unload.
    int m_textureScale = 1;
    std::unordered_map<int, ImagePtr> m_upscaledCache;
};

extern SpriteManager g_sprites;

#endif
