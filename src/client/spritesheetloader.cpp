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

#include "spritesheetloader.h"

#include <framework/graphics/image.h>
#include <framework/core/logger.h>
#include <framework/core/resourcemanager.h>
#include <framework/stdext/format.h>

#include <nlohmann/json.hpp>

#include <lzma.h>

#include <algorithm>
#include <cstring>
#include <fstream>
#include <iterator>

namespace {

// All sheets are 384x384, RGBA. Cell width/height per spritetype:
//   0  = 32x32   (12 cols * 12 rows = 144 sprites)  classic
//   1  = 32x64   (12 cols *  6 rows =  72 sprites)  classic (vertical)
//   2  = 64x32   ( 6 cols * 12 rows =  72 sprites)  classic (horizontal)
//   3  = 64x64   ( 6 cols *  6 rows =  36 sprites)  classic
//   11 = 96x96   ( 4 cols *  4 rows =  16 sprites)  deusOT/Astra extension (medium mounts/outfits)
//   16 = 128x128 ( 3 cols *  3 rows =   9 sprites)  deusOT/Astra extension (large mounts/outfits)
// Sheets may carry fewer than the grid maximum (the catalog's lastspriteid
// is the truth; trailing cells are unused). The proto SpriteInfo's pixel-size
// derivation in appearancesloader.cpp (cellW = cell.first / spriteSize) treats
// 96x96 sprites as 3x3 SQMs and 128x128 as 4x4 SQMs — drawOutfit/draw handle
// any m_size as long as cellDimsForType returns the real tile dims.
constexpr int SHEET_PIXEL_W = 384;
constexpr int SHEET_PIXEL_H = 384;
constexpr int SHEET_BYTES   = SHEET_PIXEL_W * SHEET_PIXEL_H * 4;
constexpr int SHEET_ROW_BYTES = SHEET_PIXEL_W * 4;

struct CellDims { int w; int h; };

CellDims cellDimsForType(int spriteType)
{
    switch (spriteType) {
        case 0:  return {  32,  32 };
        case 1:  return {  32,  64 };
        case 2:  return {  64,  32 };
        case 3:  return {  64,  64 };
        case 11: return {  96,  96 };  // deusOT extension
        case 16: return { 128, 128 };  // deusOT extension (outfit 1002, etc)
        case 22: return { 160, 160 };  // KoliseuOT extension (RubinOT 5x5 outfits, e.g. 2595)
        default:
            // Unknown spritetype: fall back to 32x32 and let the caller log.
            return { 32, 32 };
    }
}

// Read an entire sheet through PHYSFS (g_resources), NOT std::ifstream: sheets
// may live inside an in-memory encrypted data.zip with no real filesystem path.
// readFileContents transparently decrypts per-file-encrypted assets (and returns
// plaintext for an unencrypted dev tree).
bool readFileBinary(const std::string& path, std::vector<uint8_t>& out)
{
    if (!g_resources.fileExists(path))
        return false;
    const std::string data = g_resources.readFileContents(path);
    if (data.empty())
        return false;
    out.assign(data.begin(), data.end());
    return true;
}

} // namespace

// ----------------------------------------------------------------------------
// Public API
// ----------------------------------------------------------------------------

SpriteSheetLoader::SpriteSheetLoader() = default;
SpriteSheetLoader::~SpriteSheetLoader() = default;

bool SpriteSheetLoader::loadCatalog(const std::string& assetsDir)
{
    // Robustness contract: never throw out of this function — same shape as
    // AppearancesLoader::load (appearancesloader.cpp:56). Errors are logged
    // and we surface false to the caller.
    try {
        m_assetsDir = assetsDir;
        if (!m_assetsDir.empty()) {
            const char last = m_assetsDir.back();
            if (last != '/' && last != '\\')
                m_assetsDir.push_back('/');
        }
        m_sheets.clear();
        m_lruList.clear();
        m_lruIndex.clear();
        m_spritesCount = 0;
        m_spriteSize   = 32;

        const std::string catalogPath = m_assetsDir + "catalog-content.json";
        // PHYSFS + decrypt (see getCatalogEntryPath): assets may be inside an
        // in-memory encrypted data.zip with no real filesystem path.
        if (!g_resources.fileExists(catalogPath)) {
            g_logger.error(stdext::format("SpriteSheetLoader: cannot open '%s'", catalogPath));
            return false;
        }
        nlohmann::json catalog = nlohmann::json::parse(g_resources.readFileContents(catalogPath));

        if (!catalog.is_array()) {
            g_logger.error(stdext::format(
                "SpriteSheetLoader: catalog '%s' is not a JSON array", catalogPath));
            return false;
        }

        m_sheets.reserve(catalog.size());

        int maxLastId = -1;
        for (const auto& entry : catalog) {
            // Filter strictly to "type":"sprite". Other types
            // (appearances, staticdata, map, proficiencies, ...) are handled
            // elsewhere.
            auto typeIt = entry.find("type");
            if (typeIt == entry.end() || !typeIt->is_string())
                continue;
            if (typeIt->get<std::string>() != "sprite")
                continue;

            SheetEntry sheet;
            auto fileIt           = entry.find("file");
            auto spriteTypeIt     = entry.find("spritetype");
            auto firstSpriteIdIt  = entry.find("firstspriteid");
            auto lastSpriteIdIt   = entry.find("lastspriteid");
            auto areaIt           = entry.find("area");
            if (fileIt == entry.end()       || !fileIt->is_string()         ||
                firstSpriteIdIt == entry.end() || !firstSpriteIdIt->is_number() ||
                lastSpriteIdIt  == entry.end() || !lastSpriteIdIt->is_number()) {
                g_logger.error("SpriteSheetLoader: malformed sprite catalog entry; skipping");
                continue;
            }

            sheet.file          = fileIt->get<std::string>();
            sheet.firstSpriteId = firstSpriteIdIt->get<int>();
            sheet.lastSpriteId  = lastSpriteIdIt->get<int>();
            sheet.spriteType    = (spriteTypeIt != entry.end() && spriteTypeIt->is_number())
                                      ? spriteTypeIt->get<int>() : 0;
            sheet.area          = (areaIt != entry.end() && areaIt->is_number())
                                      ? areaIt->get<int>() : 0;

            if (sheet.lastSpriteId < sheet.firstSpriteId) {
                g_logger.error(stdext::format(
                    "SpriteSheetLoader: sheet '%s' has lastId(%d) < firstId(%d); skipping",
                    sheet.file, sheet.lastSpriteId, sheet.firstSpriteId));
                continue;
            }

            if (sheet.lastSpriteId > maxLastId)
                maxLastId = sheet.lastSpriteId;

            m_sheets.push_back(std::move(sheet));
        }

        // Sort by firstSpriteId so findSheetIndex() can use lower_bound.
        // The catalog file is already mostly sorted (R&D: 11 gaps but
        // monotonically increasing), but we don't rely on that.
        std::sort(m_sheets.begin(), m_sheets.end(),
                  [](const SheetEntry& a, const SheetEntry& b) {
                      return a.firstSpriteId < b.firstSpriteId;
                  });

        // Deduplicate overlapping ranges instead of aborting the whole sprite
        // system. Real catalogs (e.g. crystalserver's 15.24 assets) sometimes ship
        // several sheets claiming the SAME spriteId range (regenerated/superseded
        // sheets the pipeline never pruned). Bailing here left findSheetIndex() with
        // no sheets at all -> every sprite blank -> fully black game screen. Since
        // the sheets are sorted by firstSpriteId, we keep the first sheet of each
        // range and drop any later sheet that overlaps the previous kept one, so
        // findSheetIndex() stays unambiguous and the rest of the catalog still loads.
        {
            std::vector<SheetEntry> kept;
            kept.reserve(m_sheets.size());
            int dropped = 0;
            for (auto& sheet : m_sheets) {
                if (!kept.empty() && sheet.firstSpriteId <= kept.back().lastSpriteId) {
                    if (dropped < 5) {
                        g_logger.warning(stdext::format(
                            "SpriteSheetLoader: dropping overlapping sheet '%s' [%d..%d] "
                            "(already covered by '%s' [%d..%d])",
                            sheet.file, sheet.firstSpriteId, sheet.lastSpriteId,
                            kept.back().file, kept.back().firstSpriteId, kept.back().lastSpriteId));
                    }
                    ++dropped;
                    continue;
                }
                kept.push_back(std::move(sheet));
            }
            if (dropped > 0)
                g_logger.warning(stdext::format(
                    "SpriteSheetLoader: dropped %d overlapping/duplicate sheet(s) from catalog", dropped));
            m_sheets = std::move(kept);
        }

        m_spritesCount = (maxLastId >= 0) ? (maxLastId + 1) : 0;

        g_logger.info(stdext::format(
            "SpriteSheetLoader: parsed %d sheets (spriteId range 0..%d) from %s",
            getSheetCount(), maxLastId, catalogPath));
        return true;
    } catch (const std::exception& e) {
        g_logger.error(stdext::format("SpriteSheetLoader: std::exception in loadCatalog('%s'): %s",
            assetsDir, e.what()));
        m_sheets.clear();
        m_lruList.clear();
        m_lruIndex.clear();
        m_spritesCount = 0;
        return false;
    } catch (...) {
        g_logger.error(stdext::format("SpriteSheetLoader: unknown exception in loadCatalog('%s')",
            assetsDir));
        m_sheets.clear();
        m_lruList.clear();
        m_lruIndex.clear();
        m_spritesCount = 0;
        return false;
    }
}

ImagePtr SpriteSheetLoader::getSpriteImage(int spriteId)
{
    try {
        if (spriteId <= 0) // id 0 = "no sprite" sentinel (appearances pad m_spritesIndex with zeros)
            return nullptr;

        const int sheetIndex = findSheetIndex(spriteId);
        if (sheetIndex < 0)
            return nullptr;

        const std::vector<uint8_t>* rgba = loadSheet(sheetIndex);
        if (!rgba)
            return nullptr;

        const SheetEntry& sheet = m_sheets[sheetIndex];
        const CellDims dims = cellDimsForType(sheet.spriteType);
        const int cols = SHEET_PIXEL_W / dims.w;
        const int localIndex = spriteId - sheet.firstSpriteId;
        const int col = localIndex % cols;
        const int row = localIndex / cols;

        // Guard: even though catalog ranges should never overflow the grid,
        // a future spritetype with smaller grid could trip this. Better to
        // log and return nullptr than to memcpy past the sheet end.
        if ((row + 1) * dims.h > SHEET_PIXEL_H || (col + 1) * dims.w > SHEET_PIXEL_W) {
            g_logger.error(stdext::format(
                "SpriteSheetLoader: spriteId %d resolves to cell (%d,%d) which exceeds "
                "the 384x384 grid for sheet '%s' (spritetype=%d)",
                spriteId, col, row, sheet.file, sheet.spriteType));
            return nullptr;
        }

        auto image = std::make_shared<Image>(Size(dims.w, dims.h));
        uint8_t* dst = image->getPixelData();
        const uint8_t* src = rgba->data();
        const int dstRowBytes = dims.w * 4;
        const int srcXOffset  = col * dims.w * 4;
        for (int y = 0; y < dims.h; ++y) {
            const int srcRow = row * dims.h + y;
            std::memcpy(dst + y * dstRowBytes,
                        src + srcRow * SHEET_ROW_BYTES + srcXOffset,
                        dstRowBytes);
        }
        return image;
    } catch (const std::exception& e) {
        g_logger.error(stdext::format(
            "SpriteSheetLoader: std::exception in getSpriteImage(%d): %s", spriteId, e.what()));
        return nullptr;
    } catch (...) {
        g_logger.error(stdext::format(
            "SpriteSheetLoader: unknown exception in getSpriteImage(%d)", spriteId));
        return nullptr;
    }
}

std::pair<int,int> SpriteSheetLoader::getSpriteCellSize(int spriteId) const
{
    const int idx = findSheetIndex(spriteId);
    if (idx < 0) return { 32, 32 };
    const CellDims d = cellDimsForType(m_sheets[idx].spriteType);
    return { d.w, d.h };
}

void SpriteSheetLoader::setCacheCapacity(int capacity)
{
    if (capacity < 1)
        capacity = 1;
    m_cacheCapacity = capacity;
    while (static_cast<int>(m_lruList.size()) > m_cacheCapacity)
        evictIfNeeded();
}

// ----------------------------------------------------------------------------
// Lookup
// ----------------------------------------------------------------------------

int SpriteSheetLoader::findSheetIndex(int spriteId) const
{
    if (m_sheets.empty())
        return -1;

    // lower_bound on firstSpriteId: find the first sheet whose firstSpriteId
    // is > spriteId, then step back one. Equivalent to upper_bound - 1.
    auto it = std::upper_bound(
        m_sheets.begin(), m_sheets.end(), spriteId,
        [](int id, const SheetEntry& s) { return id < s.firstSpriteId; });
    if (it == m_sheets.begin())
        return -1;
    --it;
    if (spriteId < it->firstSpriteId || spriteId > it->lastSpriteId)
        return -1;
    return static_cast<int>(std::distance(m_sheets.begin(), it));
}

// ----------------------------------------------------------------------------
// LRU cache
// ----------------------------------------------------------------------------

const std::vector<uint8_t>* SpriteSheetLoader::loadSheet(int sheetIndex)
{
    auto cacheIt = m_lruIndex.find(sheetIndex);
    if (cacheIt != m_lruIndex.end()) {
        // Move to front (MRU end). std::list::splice doesn't invalidate
        // iterators, so the stored iterator stays valid.
        m_lruList.splice(m_lruList.begin(), m_lruList, cacheIt->second);
        return &cacheIt->second->data;
    }

    const SheetEntry& sheet = m_sheets[sheetIndex];
    const std::string path = m_assetsDir + sheet.file;

    std::vector<uint8_t> rgba;
    if (!decodeSheet(path, rgba))
        return nullptr;

    evictIfNeeded();

    m_lruList.push_front(CacheNode{ sheetIndex, std::move(rgba) });
    m_lruIndex[sheetIndex] = m_lruList.begin();
    return &m_lruList.front().data;
}

void SpriteSheetLoader::evictIfNeeded()
{
    while (static_cast<int>(m_lruList.size()) >= m_cacheCapacity) {
        if (m_lruList.empty())
            return;
        const int victim = m_lruList.back().sheetIndex;
        m_lruIndex.erase(victim);
        m_lruList.pop_back();
    }
}

// ----------------------------------------------------------------------------
// Sheet decompression
// ----------------------------------------------------------------------------
//
// The Tibia client packages each sprite sheet as:
//
//   [ CIP wrapper (32 bytes) ] [ LZMA1 raw stream ] -> [ BMP file ]
//
// CIP wrapper layout (peeked from Mehah's spriteappearances.cpp:131-161 — the
// values themselves come from CIP, not Mehah, but the framing trick of using
// the magic 0x70 0x0A 0xFA 0x80 0x24 and the 7-bit varint for size is not
// documented in any spec we have; this is the only published prior art):
//
//   [0x00 ... X)            NUL pad bytes. Variable length, terminated by the
//                           first non-zero byte.
//   [X ... X+5)             Constant magic: 0x70 0x0A 0xFA 0x80 0x24
//   [X+5 ... 0x20)          File size as 7-bit-encoded varint (each byte's
//                           high bit set = "more"). Read until we see a byte
//                           with the high bit cleared.
//   [0x20 ...]              LZMA1 raw stream (no .xz container, no .lzma
//                           Alone header — raw filter). The next byte is the
//                           encoded lc/lp/pb properties; four bytes after that
//                           are the dictionary size; then eight bytes of CIP's
//                           "compressed size" we skip.
//
// After lzma_raw_decoder + lzma_code yield LZMA_STREAM_END, the output buffer
// holds a BMP file:
//   - Pixel data offset is at byte 10 (32-bit little-endian, BMP FILEHEADER).
//   - The image stored there is 384x384 BGRA, bottom-up (BMP convention).
//   - Magenta (0xFF, 0x00, 0xFF, *) marks transparent pixels (CIP convention).
//
// Output of decodeSheet() is RGBA, top-down, 384*384*4 bytes.

bool SpriteSheetLoader::decodeSheet(const std::string& path,
                                    std::vector<uint8_t>& outRgba)
{
    try {
        std::vector<uint8_t> fileBytes;
        if (!readFileBinary(path, fileBytes)) {
            g_logger.error(stdext::format("SpriteSheetLoader: cannot read sheet '%s'", path));
            return false;
        }
        if (fileBytes.size() < 32) {
            g_logger.error(stdext::format("SpriteSheetLoader: sheet '%s' too small (%zu bytes)",
                path, fileBytes.size()));
            return false;
        }

        // --- CIP wrapper -----------------------------------------------------
        size_t pos = 0;
        // Skip leading NULs.
        while (pos < fileBytes.size() && fileBytes[pos] == 0x00)
            ++pos;
        if (pos == fileBytes.size()) {
            g_logger.error(stdext::format(
                "SpriteSheetLoader: sheet '%s' has no CIP magic (all-NUL header)", path));
            return false;
        }
        // Skip the 5-byte magic. We don't validate every byte; CIP can shift
        // by version, and the only failure mode is "LZMA error" later — which
        // we already log.
        pos += 5;
        if (pos >= fileBytes.size())
            return false;
        // Skip 7-bit varint size: read bytes until one has the high bit clear.
        while (pos < fileBytes.size() && (fileBytes[pos] & 0x80) != 0)
            ++pos;
        // Consume the final varint byte (the one with high bit clear).
        ++pos;
        if (pos >= fileBytes.size())
            return false;

        // --- LZMA1 raw stream header ----------------------------------------
        // One byte: properties = (pb * 5 + lp) * 9 + lc.
        const uint8_t lclppb = fileBytes[pos++];
        lzma_options_lzma options{};
        options.lc = lclppb % 9;
        const int remainder = lclppb / 9;
        options.lp = remainder % 5;
        options.pb = remainder / 5;
        if (pos + 4 > fileBytes.size())
            return false;
        uint32_t dictSize = 0;
        for (int i = 0; i < 4; ++i)
            dictSize |= static_cast<uint32_t>(fileBytes[pos + i]) << (i * 8);
        pos += 4;
        options.dict_size = dictSize;
        // CIP-specific: 8 bytes of "compressed size" we don't need.
        pos += 8;
        if (pos >= fileBytes.size()) {
            g_logger.error(stdext::format(
                "SpriteSheetLoader: sheet '%s' truncated before LZMA payload", path));
            return false;
        }

        // --- LZMA1 raw decode ------------------------------------------------
        // Target buffer must be large enough to hold the BMP. A 384x384 RGB
        // BMP has ~ 384*384*3 = 442368 image bytes + ~138 bytes of header
        // (BITMAPFILEHEADER + BITMAPINFOHEADER + masks). Allocate a safe
        // upper bound matching what Mehah uses (BYTES_IN_SPRITE_SHEET + 122).
        // We accept 4-byte (BGRA) or 3-byte (BGR) BMPs; in either case the
        // pixel data is at most 384*384*4 = 589824 bytes.
        constexpr size_t LZMA_OUT_CAP = static_cast<size_t>(SHEET_BYTES) + 256;
        std::vector<uint8_t> decompressed(LZMA_OUT_CAP);

        lzma_stream stream = LZMA_STREAM_INIT;
        lzma_filter filters[2] = {
            { LZMA_FILTER_LZMA1, &options },
            { LZMA_VLI_UNKNOWN, nullptr }
        };
        if (lzma_raw_decoder(&stream, filters) != LZMA_OK) {
            g_logger.error(stdext::format(
                "SpriteSheetLoader: lzma_raw_decoder init failed for '%s'", path));
            return false;
        }
        stream.next_in   = fileBytes.data() + pos;
        stream.avail_in  = fileBytes.size() - pos;
        stream.next_out  = decompressed.data();
        stream.avail_out = decompressed.size();

        const lzma_ret rc = lzma_code(&stream, LZMA_RUN);
        const size_t producedBytes = decompressed.size() - stream.avail_out;
        lzma_end(&stream);
        if (rc != LZMA_STREAM_END) {
            g_logger.error(stdext::format(
                "SpriteSheetLoader: LZMA decode failed for '%s' (lzma_ret=%d, produced=%zu)",
                path, static_cast<int>(rc), producedBytes));
            return false;
        }
        if (producedBytes < 14) {
            g_logger.error(stdext::format(
                "SpriteSheetLoader: decompressed BMP too small for '%s' (%zu bytes)",
                path, producedBytes));
            return false;
        }
        if (decompressed[0] != 'B' || decompressed[1] != 'M') {
            g_logger.error(stdext::format(
                "SpriteSheetLoader: decompressed payload of '%s' is not BMP (missing 'BM' magic)",
                path));
            return false;
        }

        // --- BMP fix-up ------------------------------------------------------
        // BITMAPFILEHEADER.bfOffBits is at byte 10 (LE uint32). That's the
        // start of the pixel array. We trust this offset rather than parsing
        // the DIB header in full because the BMPs CIP emits vary slightly
        // (V3 vs V5) but always set bfOffBits correctly.
        const uint32_t bmpOffset = static_cast<uint32_t>(decompressed[10])
                                 | (static_cast<uint32_t>(decompressed[11]) << 8)
                                 | (static_cast<uint32_t>(decompressed[12]) << 16)
                                 | (static_cast<uint32_t>(decompressed[13]) << 24);
        if (static_cast<size_t>(bmpOffset) + SHEET_BYTES > producedBytes) {
            g_logger.error(stdext::format(
                "SpriteSheetLoader: BMP pixel offset (%u) + sheet bytes (%d) exceeds "
                "decompressed size (%zu) for '%s'",
                bmpOffset, SHEET_BYTES, producedBytes, path));
            return false;
        }

        outRgba.resize(SHEET_BYTES);
        const uint8_t* src = decompressed.data() + bmpOffset;

        // BMP is bottom-up: row 0 of the file is the last visual row.
        // Combine the flip with the BGRA->RGBA swap + magenta keying into a
        // single pass to avoid an extra memcpy.
        for (int y = 0; y < SHEET_PIXEL_H; ++y) {
            const uint8_t* srcRow = src + (SHEET_PIXEL_H - 1 - y) * SHEET_ROW_BYTES;
            uint8_t* dstRow = outRgba.data() + y * SHEET_ROW_BYTES;
            for (int x = 0; x < SHEET_PIXEL_W; ++x) {
                const uint8_t b = srcRow[x * 4 + 0];
                const uint8_t g = srcRow[x * 4 + 1];
                const uint8_t r = srcRow[x * 4 + 2];
                const uint8_t a = srcRow[x * 4 + 3];
                // CIP uses magenta (0xFF00FF, in BGRA bytes: b=0xFF, g=0x00,
                // r=0xFF) as the transparency key.
                if (r == 0xFF && g == 0x00 && b == 0xFF) {
                    dstRow[x * 4 + 0] = 0x00;
                    dstRow[x * 4 + 1] = 0x00;
                    dstRow[x * 4 + 2] = 0x00;
                    dstRow[x * 4 + 3] = 0x00;
                } else {
                    dstRow[x * 4 + 0] = r;
                    dstRow[x * 4 + 1] = g;
                    dstRow[x * 4 + 2] = b;
                    dstRow[x * 4 + 3] = a;
                }
            }
        }
        return true;
    } catch (const std::exception& e) {
        g_logger.error(stdext::format(
            "SpriteSheetLoader: std::exception decoding '%s': %s", path, e.what()));
        return false;
    } catch (...) {
        g_logger.error(stdext::format(
            "SpriteSheetLoader: unknown exception decoding '%s'", path));
        return false;
    }
}
