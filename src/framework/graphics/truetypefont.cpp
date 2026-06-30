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

#include "truetypefont.h"
#include "image.h"

#include <ft2build.h>
#include FT_FREETYPE_H

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <vector>

namespace {
FT_Library g_ftLib = nullptr;
int g_ftUsers = 0;
std::mutex g_ftMutex;

int nextPow2(int v) { int o = 1; while (o < v) o <<= 1; return o; }

// cp1252 high range 0x80..0x9F -> Unicode codepoint (0 = undefined, no glyph).
const int CP1252_HIGH[32] = {
    0x20AC, 0,      0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0,      0x017D, 0,
    0,      0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0,      0x017E, 0x0178
};

int cp1252ToUnicode(int code) {
    if (code >= 0x80 && code <= 0x9F)
        return CP1252_HIGH[code - 0x80];
    return code; // 0x00..0x7F and 0xA0..0xFF map identically (Latin-1)
}

struct Glyph {
    int code = 0;
    int advance = 1;
    int bearingX = 0, bearingY = 0;
    int bw = 0, bh = 0;
    std::vector<uint8> alpha; // bw*bh grayscale coverage
    int atlasX = 0, atlasY = 0;
};
}

namespace truetypefont {

bool init()
{
    std::lock_guard<std::mutex> lock(g_ftMutex);
    if (g_ftLib) { ++g_ftUsers; return true; }
    if (FT_Init_FreeType(&g_ftLib) != 0) { g_ftLib = nullptr; return false; }
    g_ftUsers = 1;
    return true;
}

void terminate()
{
    std::lock_guard<std::mutex> lock(g_ftMutex);
    if (g_ftUsers > 0) --g_ftUsers;
    if (g_ftUsers == 0 && g_ftLib) { FT_Done_FreeType(g_ftLib); g_ftLib = nullptr; }
}

bool rasterize(const std::string& ttfData, int pixelSize, bool outline, bool mono, TtfAtlas& out)
{
    if (!g_ftLib && !init())
        return false;
    if (ttfData.empty())
        return false;

    pixelSize = std::max(1, pixelSize);

    FT_Face face = nullptr;
    if (FT_New_Memory_Face(g_ftLib, reinterpret_cast<const FT_Byte*>(ttfData.data()),
                           static_cast<FT_Long>(ttfData.size()), 0, &face) != 0)
        return false;

    if (FT_Set_Pixel_Sizes(face, 0, pixelSize) != 0) {
        FT_Done_Face(face);
        return false;
    }

    int ascender = static_cast<int>(face->size->metrics.ascender >> 6);
    if (ascender <= 0)
        ascender = pixelSize;

    // Outline grows each cell by 1px on every side.
    const int pad = outline ? 1 : 0;

    std::vector<Glyph> glyphs;
    glyphs.reserve(224);

    for (int code = 32; code < 256; ++code) {
        if (code == 127)            // 127 stays a 1px spacer (NPC highlight system)
            continue;
        const int cp = cp1252ToUnicode(code);
        if (cp == 0)                // cp1252 undefined slot
            continue;

        // MONO rendering (FT_LOAD_TARGET_MONO): native 1-bit hinting snaps every stem to
        // the pixel grid -> UNIFORM, slightly bolder strokes matching the old pixel-art
        // bitmaps. Used for outlined fonts AND for plain 'mono' fonts (crisp body, no
        // outline) -- e.g. UI Verdana Bold that looked too thin in grayscale AA. The body
        // loop below is shared: with a MONO bitmap the coverage alpha is already 0/255, so
        // the smooth path paints a crisp white body. Plain smooth (neither flag) stays AA.
        const FT_Int32 loadFlags = (outline || mono) ? (FT_LOAD_RENDER | FT_LOAD_TARGET_MONO)
                                                      : FT_LOAD_RENDER;
        if (FT_Load_Char(face, cp, loadFlags) != 0)
            continue;

        const FT_GlyphSlot slot = face->glyph;
        Glyph g;
        g.code = code;
        g.advance = std::max(1, static_cast<int>(slot->advance.x >> 6));
        g.bearingX = slot->bitmap_left;
        g.bearingY = slot->bitmap_top;
        g.bw = static_cast<int>(slot->bitmap.width);
        g.bh = static_cast<int>(slot->bitmap.rows);
        if (g.bw > 0 && g.bh > 0 && slot->bitmap.buffer) {
            g.alpha.assign(static_cast<size_t>(g.bw) * g.bh, 0);
            const int pitch = std::abs(slot->bitmap.pitch);
            if (slot->bitmap.pixel_mode == FT_PIXEL_MODE_MONO) {
                for (int y = 0; y < g.bh; ++y) {
                    const uint8* row = slot->bitmap.buffer + static_cast<size_t>(y) * pitch;
                    for (int x = 0; x < g.bw; ++x)
                        g.alpha[static_cast<size_t>(y) * g.bw + x] =
                            ((row[x >> 3] >> (7 - (x & 7))) & 1) ? 255 : 0;
                }
            } else {
                for (int y = 0; y < g.bh; ++y)
                    std::memcpy(&g.alpha[static_cast<size_t>(y) * g.bw],
                                slot->bitmap.buffer + static_cast<size_t>(y) * pitch, g.bw);
            }
        }
        glyphs.push_back(std::move(g));
    }

    // Center the glyph in the cell like the old bitmaps: equal space above the cap
    // (maxDescent) and below the baseline (maxDescent), so vertically-centered UI
    // text lands correctly AND top-aligned names keep a small top padding. capHeight
    // is the tallest uppercase top; the baseline sits maxDescent below it.
    // (Tall accents may lose ~1px at the very top — acceptable for game text.)
    int capHeight = 0, maxDescent = 0;
    for (const auto& g : glyphs) {
        if (g.bh <= 0)
            continue;
        if (g.code >= 'A' && g.code <= 'Z')
            capHeight = std::max(capHeight, g.bearingY);
        maxDescent = std::max(maxDescent, g.bh - g.bearingY);
    }
    if (capHeight <= 0)
        capHeight = ascender;
    const int baselineRel = pad + maxDescent + capHeight;
    const int cellHeight = baselineRel + maxDescent + pad;

    // Pack cells left-to-right, wrapping rows; 1px gap absorbs outline overflow.
    const int atlasWidth = 256;
    const int rowH = cellHeight + 1;
    int penX = 1, penY = 1;
    for (auto& g : glyphs) {
        const int cellW = std::max(std::max(1, g.advance), g.bearingX + g.bw) + pad * 2;
        if (penX + cellW + 1 > atlasWidth) { penX = 1; penY += rowH; }
        g.atlasX = penX;
        g.atlasY = penY;
        penX += cellW + 1;
    }
    const int neededH = penY + rowH + 1;
    const int atlasHeight = nextPow2(std::max(16, neededH));

    ImagePtr image(new Image(Size(atlasWidth, atlasHeight), 4));
    auto& px = image->getPixels();
    std::fill(px.begin(), px.end(), static_cast<uint8>(0));

    auto setPx = [&](int x, int y, uint8 r, uint8 g, uint8 b, uint8 a) {
        if (x < 0 || y < 0 || x >= atlasWidth || y >= atlasHeight)
            return;
        const size_t i = (static_cast<size_t>(y) * atlasWidth + x) * 4;
        px[i + 0] = r; px[i + 1] = g; px[i + 2] = b; px[i + 3] = a;
    };

    for (int i = 0; i < 256; ++i) {
        out.coords[i] = Rect(0, 0, 0, 0);
        out.sizes[i] = Size(0, 0);
    }

    for (const auto& g : glyphs) {
        const int cellW = std::max(std::max(1, g.advance), g.bearingX + g.bw) + pad * 2;
        const int baselineY = g.atlasY + baselineRel;
        const int drawX = g.atlasX + pad + g.bearingX;
        const int drawY = baselineY - g.bearingY;

        if (g.bw > 0 && g.bh > 0) {
            if (!outline) {
                // smooth: white body keyed by coverage alpha
                for (int yy = 0; yy < g.bh; ++yy)
                    for (int xx = 0; xx < g.bw; ++xx) {
                        const uint8 a = g.alpha[static_cast<size_t>(yy) * g.bw + xx];
                        if (a)
                            setPx(drawX + xx, drawY + yy, 255, 255, 255, a);
                    }
            } else {
                // crisp: 1-bit body (>=128) + 1px black outline (8-connected dilation)
                auto isBody = [&](int xx, int yy) {
                    if (xx < 0 || yy < 0 || xx >= g.bw || yy >= g.bh)
                        return false;
                    return g.alpha[static_cast<size_t>(yy) * g.bw + xx] >= 128;
                };
                for (int yy = -1; yy <= g.bh; ++yy)
                    for (int xx = -1; xx <= g.bw; ++xx) {
                        if (isBody(xx, yy))
                            continue;
                        bool touches = false;
                        for (int dy = -1; dy <= 1 && !touches; ++dy)
                            for (int dx = -1; dx <= 1; ++dx)
                                if (isBody(xx + dx, yy + dy)) { touches = true; break; }
                        if (touches)
                            setPx(drawX + xx, drawY + yy, 0, 0, 0, 255);
                    }
                for (int yy = 0; yy < g.bh; ++yy)
                    for (int xx = 0; xx < g.bw; ++xx)
                        if (isBody(xx, yy))
                            setPx(drawX + xx, drawY + yy, 236, 236, 236, 255);
            }
        }

        out.coords[g.code] = Rect(g.atlasX, g.atlasY, cellW, cellHeight);
        out.sizes[g.code] = Size(cellW, cellHeight);
    }

    out.image = image;
    out.glyphHeight = cellHeight;
    out.baseline = baselineRel;
    // Advance = cellW - 1 for outlined fonts: matches the measured width of the old
    // bitmaps (which were ~1.5px tighter than the cell). Smooth fonts keep the full
    // cell advance. Fine-tune per font via the .otfont 'letter-spacing'.
    out.glyphSpacing = Size(outline ? -1 : 0, 0);

    FT_Done_Face(face);
    return true;
}

}
