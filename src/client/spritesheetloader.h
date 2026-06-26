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

#ifndef SPRITESHEETLOADER_H
#define SPRITESHEETLOADER_H

// Phase 1 P1.3: sprite-sheet loader for Tibia 15.24 assets.
//
// The Tibia 15.24 client receives sprites packaged as 384x384 BMP sheets,
// each sheet wrapped in CIP's LZMA framing (sprites-<hash>.bmp.lzma). The
// directory layout is described by a sibling catalog-content.json which
// lists, per sheet, the inclusive [firstspriteid, lastspriteid] range and a
// "spritetype" code that picks the cell size inside the sheet.
//
// This loader:
//   1. Parses catalog-content.json (nlohmann/json) into a sorted SheetEntry
//      vector — sheets are sorted by firstSpriteId so findSheet() is O(log N).
//   2. Lazily decompresses a sheet the first time a sprite from that sheet
//      is requested via getSpriteImage(). Decompressed RGBA bytes are cached
//      in an LRU keyed by sheet index; per-sheet decoding costs the LZMA
//      pass + a BMP fix-up, never charged again until the entry is evicted.
//   3. Per-sprite extraction is a memcpy from the cached sheet bytes into a
//      fresh Image, paid every getSpriteImage() call. The renderer already
//      caches Image -> Texture on its own.
//
// Memory bound: capacity * 384 * 384 * 4 bytes per cached sheet
//             = capacity * 576 KB ≈ 36 MB at capacity = 64.
//
// Robustness: loadCatalog() and getSpriteImage() never throw. Any I/O,
// json, LZMA or BMP error is logged via g_logger.error() and surfaces as
// false / nullptr to the caller — same contract as AppearancesLoader::load.
//
// This loader does not touch SpriteManager. P1.4 will replace the legacy
// g_sprites pipeline; P1.3 leaves both paths coexisting.

#include <framework/graphics/declarations.h>

#include <cstdint>
#include <list>
#include <string>
#include <unordered_map>
#include <vector>

class SpriteSheetLoader
{
public:
    SpriteSheetLoader();
    ~SpriteSheetLoader();

    // Parse catalog-content.json from the assets directory. After this
    // returns true, getSpriteImage() can be called to lazy-decompress
    // sheets on demand. `assetsDir` is the directory containing
    // catalog-content.json + the sheet files. The argument is taken as a
    // raw filesystem path (NOT a PHYSFS virtual path), mirroring how
    // AppearancesLoader::load consumes its argument.
    bool loadCatalog(const std::string& assetsDir);

    // Returns the decoded sprite as an ImagePtr (the same type the renderer
    // already consumes via the legacy g_sprites.getSpriteImage). Returns
    // nullptr if id is out of range, the catalog has no sheet for it, or
    // the containing sheet fails to decompress.
    ImagePtr getSpriteImage(int spriteId);

    // Pixel dimensions (width, height) of the sprite cell that owns spriteId.
    // For proto items this is the truth — bounding_square is just the visible
    // bbox INSIDE the cell; the actual atlas storage size is dictated by the
    // sheet's spritetype:
    //   0=32x32, 1=32x64, 2=64x32, 3=64x64, 11=96x96, 16=128x128.
    // Returns (32,32) if spriteId is unmapped, so callers can divide safely.
    std::pair<int,int> getSpriteCellSize(int spriteId) const;

    // Highest spriteId + 1, derived from catalog (max lastspriteid + 1).
    int getSpritesCount() const { return m_spritesCount; }

    // Pixel size of a 1x1 sprite cell. Tibia's canonical sprite size is
    // 32 (spritetype 0 = 32x32). g_sprites.spriteSize() should mirror
    // this value once P1.4 wires it in.
    int getSpriteSize() const { return m_spriteSize; }

    // Number of sheet entries parsed out of catalog-content.json. Useful
    // for logging at load time.
    int getSheetCount() const { return static_cast<int>(m_sheets.size()); }

    // LRU capacity tuning. Defaults to 64 sheets (~36 MB worst case).
    // Callers that know they will scan the entire item set in one pass can
    // bump this; the cache evicts least-recently-used.
    void setCacheCapacity(int capacity);
    int  getCacheCapacity() const { return m_cacheCapacity; }

private:
    struct SheetEntry
    {
        std::string file;         // e.g. "sprites-d656db4...bmp.lzma"
        int firstSpriteId = 0;
        int lastSpriteId  = 0;
        int spriteType    = 0;    // 0=32x32, 1=32x64, 2=64x32, 3=64x64
        int area          = 0;    // catalog field; stored verbatim
    };

    // Find the SheetEntry that owns spriteId via std::lower_bound on
    // m_sheets (sorted by firstSpriteId). Returns -1 if not mapped.
    int findSheetIndex(int spriteId) const;

    // Decompress sheet bytes into RGBA pixel data and place into the LRU
    // cache. Returns a pointer to the cached RGBA bytes
    // (size = SHEET_PIXEL_W * SHEET_PIXEL_H * 4 = 589824) or nullptr on
    // any error.
    const std::vector<uint8_t>* loadSheet(int sheetIndex);

    // Evict the least-recently-used sheet from the cache. No-op if cache
    // is under capacity.
    void evictIfNeeded();

    // Decompress an entire sprite sheet file from `path` into `outRgba`.
    // The output is exactly SHEET_PIXEL_W * SHEET_PIXEL_H * 4 bytes,
    // RGBA, top-down. Returns false on any error.
    bool decodeSheet(const std::string& path, std::vector<uint8_t>& outRgba);

    std::string m_assetsDir;
    int  m_spritesCount = 0;
    int  m_spriteSize   = 32;  // Tibia canonical cell size.

    // Sheets sorted by firstSpriteId; lookup via lower_bound + range
    // check (since the catalog has small gaps, see P1.3 R&D notes).
    std::vector<SheetEntry> m_sheets;

    // LRU: list holds (sheetIndex, decodedRgba); map for O(1) lookup.
    struct CacheNode
    {
        int sheetIndex = -1;
        std::vector<uint8_t> data;
    };
    using CacheList = std::list<CacheNode>;
    CacheList m_lruList;
    std::unordered_map<int, CacheList::iterator> m_lruIndex;
    int m_cacheCapacity = 64;
};

#endif
