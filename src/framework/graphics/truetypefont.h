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

#ifndef TRUETYPEFONT_H
#define TRUETYPEFONT_H

#include "declarations.h"

// KoliseuOT TTF support (FreeType). This unit is the ONLY place that touches
// FreeType. It rasterizes a .ttf at an exact pixel size (native hinting -> crisp
// glyphs, unlike a downscaled bitmap) into the same atlas layout a BitmapFont
// already consumes, so the existing text pipeline renders TTF fonts unchanged.
//
// Scope is deliberately minimal: cp1252 glyphs (codes 32..255), no Unicode beyond
// Latin-1 / cp1252 high range, no color emoji, no fallback chain.
struct TtfAtlas {
    ImagePtr image;            // RGBA atlas (white body + alpha; black outline when requested)
    Rect coords[256] = {};     // texture sub-rect per glyph (cp1252 code 0..255)
    Size sizes[256] = {};      // per-glyph advance (cellW) x glyphHeight
    Size glyphSpacing;         // base font spacing
    int glyphHeight = 0;       // natural cell height
    int baseline = 0;          // baseline position within the cell, measured from its top
};

namespace truetypefont {
    // FT_Library lifecycle (ref-counted, thread-safe).
    bool init();
    void terminate();

    // Rasterize cp1252 glyphs (32..255) of an in-memory .ttf.
    //   pixelSize: FT_Set_Pixel_Sizes value (EM size in px).
    //   outline=false, mono=false: anti-aliased grayscale body (smooth UI text).
    //   outline=true            : 1-bit body + 1px black outline (legible over sprites; count badge).
    //   mono=true (no outline)  : 1-bit body, NO outline (crisp/bolder, matches old UI bitmaps).
    // outline wins if both are set. Returns false on any FreeType failure; `out` is filled on success.
    bool rasterize(const std::string& ttfData, int pixelSize, bool outline, bool mono, TtfAtlas& out);
}

#endif
