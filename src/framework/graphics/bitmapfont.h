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

#ifndef BITMAPFONT_H
#define BITMAPFONT_H

#include "declarations.h"
#include "texture.h"

#include <framework/otml/declarations.h>
#include <framework/graphics/coordsbuffer.h>

// Inline text images let a single byte in a text string render as a little
// picture instead of a font glyph (e.g. the store description icons). A byte
// whose code is registered in the FontManager registry is laid out as a
// fixed-width box during wrapping/positioning, but drawn from its own texture
// instead of the font atlas. Codes are control bytes (< 32) that normal text
// never contains, so unregistered text is unaffected.
struct InlineTextImage {
    TexturePtr texture;
    Rect srcRect;     // region of texture to sample
    int width = 0;    // layout advance width (0 == code not registered)
    int height = 0;   // draw height
    int yOffset = 0;  // extra vertical nudge on top of line-centering
};

// A resolved inline image draw command produced by calculateDrawTextCoords,
// in the same box-relative space as the glyph coords buffer.
struct InlineImageDrawCmd {
    TexturePtr texture;
    Rect dest;
    Rect src;
};

// A contiguous run of glyphs that uses an ALTERNATE font (e.g. an <i> italic or
// <b> bold segment in a store description). Glyphs from a non-base font live in
// a different texture, so they cannot share the base coords buffer; each run is
// batched on its own texture and drawn with a single color resolved from the
// run's first glyph position. See bitmapfont.cpp / fontmanager (style fonts).
struct StyledTextRun {
    TexturePtr texture;
    CoordsBuffer coords;
    int firstGlyphIndex = 0; // index among drawable glyphs (matches color positions)
};

class BitmapFont : public std::enable_shared_from_this<BitmapFont>
{
public:
    BitmapFont(const std::string& name) : m_name(name) {
        static int id = 1;
        m_id = id++;
    }

    /// Load font from otml node
    void load(const OTMLNodePtr& fontNode);

    /// KoliseuOT: build this font by rasterizing a .ttf at an exact pixel size
    /// (native FreeType hinting). Populates the same glyph arrays as load(), so
    /// the render pipeline is unchanged. outline=true adds a 1px black contour
    /// (legible over sprites, e.g. the count badge); false = smooth anti-aliased.
    /// letterSpacing nudges the horizontal advance (.otfont 'letter-spacing');
    /// yOffset shifts the text vertically (.otfont 'y-offset') to match old bitmaps.
    void loadTTF(const std::string& ttfFile, int size, bool outline, bool mono, float letterSpacing, int lineSpacing, int yOffset, int heightOverride, int baselineOverride);

    /// Simple text render starting at startPos
    void drawText(const std::string& text, const Point& startPos, const Color& color = Color::white, bool shadow = false);

    /// Advanced text render delimited by a screen region and alignment
    void drawText(const std::string& text, const Rect& screenCoords, Fw::AlignmentFlag align = Fw::AlignTopLeft, const Color& color = Color::white, bool shadow = false);
    void drawColoredText(const std::string& text, const Rect& screenCoords, Fw::AlignmentFlag align, const std::vector<std::pair<int, Color>>& colors, bool shadow = false);

    void calculateDrawTextCoords(CoordsBuffer& coordsBuffer, const std::string& text, const Rect& screenCoords, Fw::AlignmentFlag align = Fw::AlignTopLeft, std::vector<InlineImageDrawCmd>* outImages = nullptr, std::vector<std::unique_ptr<StyledTextRun>>* outRuns = nullptr);

    /// Calculate glyphs positions to use on render, also calculates textBoxSize if wanted
    const std::vector<Point>& calculateGlyphsPositions(const std::string& text,
                                                       Fw::AlignmentFlag align = Fw::AlignTopLeft,
                                                       Size* textBoxSize = NULL);

    /// Simulate render and calculate text size
    Size calculateTextRectSize(const std::string& text);

    std::string wrapText(const std::string& text, int maxWidth, std::vector<std::pair<int, Color>>* colors = nullptr);

    int getId() { return m_id; }
    std::string getName() { return m_name; }
    int getGlyphHeight() { return m_glyphHeight; }
    const Rect* getGlyphsTextureCoords() { return m_glyphsTextureCoords; }
    const Size* getGlyphsSize() { return m_glyphsSize; }
    const TexturePtr& getTexture() { return m_texture; }
    int getYOffset() { return m_yOffset; }
    Size getGlyphSpacing() { return m_glyphSpacing; }
    int getUnderlineOffset() { return m_underlineOffset; }

private:
    /// Calculates each font character by inspecting font bitmap
    bool calculateGlyphsWidthsAutomatically(const ImagePtr& image, const Size& glyphSize);
    void updateColors(std::vector<std::pair<int, Color>>* colors, int pos, int newTextLen);

    std::string m_name;
    int m_glyphHeight;
    int m_firstGlyph;
    int m_yOffset;
    int m_id;
    int m_underlineOffset;
    Size m_glyphSpacing;
    // Fractional remainder of the per-glyph horizontal advance ([0,1)). Non-zero
    // means the spacing target is sub-pixel: layout dithers a +1px every time this
    // accumulates past 1, so a run's AVERAGE advance hits the fractional value.
    float m_glyphSpacingFrac = 0.0f;
    TexturePtr m_texture;
    Rect m_glyphsTextureCoords[256];
    Size m_glyphsSize[256];
};


#endif

