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

#include "atlas.h"
#include "bitmapfont.h"
#include "fontmanager.h"
#include "texturemanager.h"
#include "graphics.h"
#include "image.h"
#include "truetypefont.h"

#include <framework/core/eventdispatcher.h>
#include <framework/core/resourcemanager.h>
#include <framework/otml/otml.h>
#include <framework/util/extras.h>

#include <algorithm>
#include <cmath>

void BitmapFont::load(const OTMLNodePtr& fontNode)
{
    OTMLNodePtr textureNode = fontNode->at("texture");
    std::string textureFile = stdext::resolve_path(textureNode->value(), textureNode->source());
    Size glyphSize = fontNode->valueAt<Size>("glyph-size");
    m_glyphHeight = fontNode->valueAt<int>("height");
    m_yOffset = fontNode->valueAt("y-offset", 0);
    m_firstGlyph = fontNode->valueAt("first-glyph", 32);
    m_glyphSpacing = fontNode->valueAt("spacing", Size(0,0));
    m_underlineOffset = fontNode->valueAt("underline-offset", 0);
    int spaceWidth = fontNode->valueAt("space-width", glyphSize.width());

    // Guard a malformed/empty glyph-size: numHorizontalGlyphs below divides by
    // glyphSize.width(); a zero width/height would divide-by-zero (the
    // fixed-glyph-width path also bypasses calculateGlyphsWidthsAutomatically's
    // own isEmpty() guard).
    if(glyphSize.width() <= 0 || glyphSize.height() <= 0)
        return;

    if(OTMLNodePtr node = fontNode->get("fixed-glyph-width")) {
        for(int glyph = m_firstGlyph; glyph < 256; ++glyph)
            m_glyphsSize[glyph] = Size(node->value<int>(), m_glyphHeight);
    } else {
        if (!calculateGlyphsWidthsAutomatically(Image::load(textureFile), glyphSize))
            return;
    }

    // 32 is space
    m_glyphsSize[32].setWidth(spaceWidth);

    // use 127 as spacer [Width: 1], Important for the current NPC highlighting system
    m_glyphsSize[127].setWidth(1);

    // new line actually has a size that will be useful in multiline algorithm
    m_glyphsSize[(uchar)'\n'] = Size(1, m_glyphHeight);

    // read custom widths
    /*
    if(OTMLNodePtr node = fontNode->get("glyph-widths")) {
        for(const OTMLNodePtr& child : node->children())
            m_glyphsSize[stdext::safe_cast<int>(child->tag())].setWidth(child->value<int>());
    }
    */

    // load font texture
    m_texture = g_textures.getTexture(textureFile);
    if (!m_texture)
        return;
    m_texture->update();

    int numHorizontalGlyphs = m_texture->getSize().width() / glyphSize.width();
    if (numHorizontalGlyphs <= 0)
        return;
#ifdef DONT_CACHE_FONTS
    Point offset(0, 0);
#else
    Point offset = g_atlas.cacheFont(m_texture);
    m_texture = g_atlas.get(1);
#endif
    for (int glyph = m_firstGlyph; glyph < 256; ++glyph) {
        m_glyphsTextureCoords[glyph].setRect(((glyph - m_firstGlyph) % numHorizontalGlyphs) * glyphSize.width() + offset.x,
                                                ((glyph - m_firstGlyph) / numHorizontalGlyphs) * glyphSize.height() + offset.y,
                                                m_glyphsSize[glyph].width(),
                                                m_glyphHeight);
    }
}

void BitmapFont::loadTTF(const std::string& ttfFile, int size, bool outline, bool mono, float letterSpacing, int lineSpacing, int yOffset, int heightOverride, int baselineOverride)
{
    const std::string data = g_resources.readFileContents(ttfFile);
    if (data.empty())
        stdext::throw_exception(stdext::format("unable to read ttf file '%s'", ttfFile));

    TtfAtlas atlas;
    if (!truetypefont::rasterize(data, size, outline, mono, atlas))
        stdext::throw_exception(stdext::format("unable to rasterize ttf file '%s'", ttfFile));

    m_firstGlyph = 32;
    m_underlineOffset = 0;
    // Horizontal advance may be fractional (.otfont 'letter-spacing: -0.5'): the floor
    // becomes the integer per-glyph spacing and the remainder is dithered at layout
    // time so the average advance lands on the fractional target. Vertical 'line-spacing'
    // folds straight into glyphSpacing.height (only affects multi-line line stepping).
    const float totalSpacing = static_cast<float>(atlas.glyphSpacing.width()) + letterSpacing;
    const int intSpacing = static_cast<int>(std::floor(totalSpacing));
    m_glyphSpacing = Size(intSpacing, atlas.glyphSpacing.height() + lineSpacing);
    m_glyphSpacingFrac = totalSpacing - static_cast<float>(intSpacing); // [0, 1)

    const int cellHeight = atlas.glyphHeight;
    // m_glyphHeight is the line box widgets align to: keep the original bitmap's
    // height when the .otfont provides it, so existing layouts/alignments stay put.
    m_glyphHeight = (heightOverride > 0) ? heightOverride : cellHeight;
    // Shift the glyph so its baseline lands where the old bitmap's did (then top/
    // center/bottom alignments all match); otherwise center the cell in the box.
    const int shift = (baselineOverride > 0) ? (baselineOverride - atlas.baseline)
                                             : (m_glyphHeight - cellHeight) / 2;
    m_yOffset = yOffset + shift;

    for (int i = 0; i < 256; ++i) {
        m_glyphsTextureCoords[i] = atlas.coords[i];
        m_glyphsSize[i] = atlas.sizes[i];
    }

    // Mirror BitmapFont::load()'s special glyphs.
    if (m_glyphsSize[32].width() <= 0)
        m_glyphsSize[32] = Size(std::max(1, size / 3), m_glyphHeight);
    m_glyphsSize[127] = Size(1, m_glyphHeight);
    m_glyphsSize[(uchar)'\n'] = Size(1, m_glyphHeight);

    // Own texture, NOT the shared glyph atlas: the glyph coords are already in
    // this texture's own space (no atlas offset). Upload is lazy (first draw),
    // which keeps loadTTF safe to call from any thread.
    m_texture = TexturePtr(new Texture(atlas.image));
}

void BitmapFont::drawText(const std::string& text, const Point& startPos, const Color& color, bool shadow)
{
    Size boxSize = g_painter->getResolution() - startPos.toSize();
    Rect screenCoords(startPos, boxSize);
    drawText(text, screenCoords, Fw::AlignTopLeft, shadow);
}

void BitmapFont::drawText(const std::string& text, const Rect& screenCoords, Fw::AlignmentFlag align, const Color& color, bool shadow)
{
    g_drawQueue->addText(shared_from_this(), text, screenCoords, align, color, shadow);
}

void BitmapFont::drawColoredText(const std::string& text, const Rect& screenCoords, Fw::AlignmentFlag align, const std::vector<std::pair<int, Color>>& colors, bool shadow)
{
    g_drawQueue->addColoredText(shared_from_this(), text, screenCoords, align, colors, shadow);
}

void BitmapFont::calculateDrawTextCoords(CoordsBuffer& coordsBuffer, const std::string& textIn, const Rect& screenCoords, Fw::AlignmentFlag align, std::vector<InlineImageDrawCmd>* outImages, std::vector<std::unique_ptr<StyledTextRun>>* outRuns)
{
    // prevent glitches from invalid rects
    if (!screenCoords.isValid() || !m_texture)
        return;

    const bool hasInline = outImages && g_fonts.hasInlineImages();
    const bool hasStyles = outRuns && g_fonts.hasStyleFonts();

    // Current font for the run we are emitting. Style-marker bytes (see below)
    // flip this to an alternate font; glyphs then come from that font's texture.
    BitmapFont* curFont = this;
    int curRunIdx = -1;   // index into *outRuns for the open alternate-font run
    int glyphIndex = 0;   // drawable glyph counter (matches color positions)

    // Truncate pathologically long strings BEFORE any layout. A desynced packet
    // can hand us a garbage label thousands of chars long; laying it out and
    // building a vertex buffer that big has overrun ANGLE/D3D11 vertex storage
    // and corrupted the heap. No real in-game label is anywhere near this.
    static const size_t MAX_DRAW_GLYPHS = 1024;
    std::string truncated;
    if (textIn.size() > MAX_DRAW_GLYPHS)
        truncated = textIn.substr(0, MAX_DRAW_GLYPHS);
    const std::string& text = (textIn.size() > MAX_DRAW_GLYPHS) ? truncated : textIn;

    int textLenght = text.length();

    // map glyphs positions
    Size textBoxSize;
    const std::vector<Point>& glyphsPositions = calculateGlyphsPositions(text, align, &textBoxSize);

    for (int i = 0; i < textLenght; ++i) {
        int glyph = (uchar)text[i];

        // Style-marker bytes (zero width) switch the current font for the glyphs
        // that follow: an <i>/<b> open flips to italic/bold, the reset closes it.
        if (hasStyles && glyph < 32) {
            if (g_fonts.isStyleReset(glyph)) {
                curFont = this;
                curRunIdx = -1;
                continue;
            }
            if (const BitmapFontPtr& styleFont = g_fonts.getStyleFont(glyph)) {
                curFont = styleFont.get();
                curRunIdx = -1; // a fresh run opens on the next glyph
                continue;
            }
        }

        // Control bytes are normally skipped, but a registered inline-image code
        // is laid out and drawn as a picture (from its own texture) instead.
        const InlineTextImage* inlineImg = nullptr;
        if (glyph < 32) {
            if (hasInline)
                inlineImg = g_fonts.getInlineImage(glyph);
            if (!inlineImg)
                continue;
        }

        // Advance the drawable-glyph counter for every real glyph (matching the
        // color-position convention, which counts chars >= 32 regardless of
        // clipping below). Inline images are < 32 and do not count.
        const int thisGlyphIndex = glyphIndex;
        if (glyph >= 32)
            ++glyphIndex;

        // The glyph is drawn from the current font (base, italic or bold). Layout
        // positions came from the base font (markers are zero width), so alternate
        // glyphs ride the base advances -- exact for italic, marginally tight for bold.
        BitmapFont* glyphFont = inlineImg ? this : curFont;

        // calculate initial glyph rect and texture coords (font glyph or image)
        const Size drawSize = inlineImg ? Size(inlineImg->width, inlineImg->height) : glyphFont->m_glyphsSize[glyph];
        Rect glyphScreenCoords(glyphsPositions[i], drawSize);
        Rect glyphTextureCoords = inlineImg ? inlineImg->srcRect : glyphFont->m_glyphsTextureCoords[glyph];

        // center the icon on the text line, then apply its fine-tune offset
        if (inlineImg)
            glyphScreenCoords.translate(0, (m_glyphHeight - inlineImg->height) / 2 + inlineImg->yOffset);

        // first translate to align position
        if (align & Fw::AlignBottom) {
            glyphScreenCoords.translate(0, screenCoords.height() - textBoxSize.height());
        } else if (align & Fw::AlignVerticalCenter) {
            glyphScreenCoords.translate(0, (screenCoords.height() - textBoxSize.height()) / 2);
        } else { // AlignTop
            // nothing to do
        }

        if (align & Fw::AlignRight) {
            glyphScreenCoords.translate(screenCoords.width() - textBoxSize.width(), 0);
        } else if (align & Fw::AlignHorizontalCenter) {
            glyphScreenCoords.translate((screenCoords.width() - textBoxSize.width()) / 2, 0);
        } else { // AlignLeft
            // nothing to do
        }

        // only render glyphs that are after 0, 0
        if (glyphScreenCoords.bottom() < 0 || glyphScreenCoords.right() < 0)
            continue;

        // bound glyph topLeft to 0,0 if needed
        if (glyphScreenCoords.top() < 0) {
            glyphTextureCoords.setTop(glyphTextureCoords.top() - glyphScreenCoords.top());
            glyphScreenCoords.setTop(0);
        }
        if (glyphScreenCoords.left() < 0) {
            glyphTextureCoords.setLeft(glyphTextureCoords.left() - glyphScreenCoords.left());
            glyphScreenCoords.setLeft(0);
        }

        // translate rect to screen coords
        glyphScreenCoords.translate(screenCoords.topLeft());

        // only render if glyph rect is visible on screenCoords
        if (!screenCoords.intersects(glyphScreenCoords))
            continue;

        // bound glyph bottomRight to screenCoords bottomRight
        if (glyphScreenCoords.bottom() > screenCoords.bottom()) {
            glyphTextureCoords.setBottom(glyphTextureCoords.bottom() + (screenCoords.bottom() - glyphScreenCoords.bottom()));
            glyphScreenCoords.setBottom(screenCoords.bottom());
        }
        if (glyphScreenCoords.right() > screenCoords.right()) {
            glyphTextureCoords.setRight(glyphTextureCoords.right() + (screenCoords.right() - glyphScreenCoords.right()));
            glyphScreenCoords.setRight(screenCoords.right());
        }

        // Route the quad. Inline images go to their own list. A base-font glyph --
        // or an alternate-font glyph whose texture is the SAME atlas as the base --
        // joins the shared buffer: one batch, exact positional colors. Only an
        // alternate font on a DIFFERENT texture needs its own per-run batch.
        if (inlineImg) {
            outImages->push_back(InlineImageDrawCmd{ inlineImg->texture, glyphScreenCoords, glyphTextureCoords });
        } else if (glyphFont == this || glyphFont->m_texture == m_texture || !outRuns) {
            coordsBuffer.addRect(glyphScreenCoords, glyphTextureCoords);
        } else {
            // Heap-stored so the CoordsBuffer is never moved (its move ctor aliases
            // the vertex arrays); the unique_ptr is what the vector relocates.
            if (curRunIdx < 0) {
                outRuns->push_back(std::make_unique<StyledTextRun>());
                StyledTextRun& run = *outRuns->back();
                run.texture = glyphFont->m_texture;
                run.firstGlyphIndex = thisGlyphIndex;
                curRunIdx = (int)outRuns->size() - 1;
            }
            (*outRuns)[curRunIdx]->coords.addRect(glyphScreenCoords, glyphTextureCoords);
        }
    }
}

const std::vector<Point>& BitmapFont::calculateGlyphsPositions(const std::string& text,
                                                         Fw::AlignmentFlag align,
                                                         Size *textBoxSize)
{
    // for performance reasons we use statics vectors that are allocated on demand
    static thread_local std::vector<Point> glyphsPositions(1);
    static thread_local std::vector<int> lineWidths(1);

    int textLength = text.length();
    int maxLineWidth = 0;
    int lines = 0;
    int glyph;
    int i;

    // return if there is no text
    if(textLength == 0) {
        if(textBoxSize)
            textBoxSize->resize(0,m_glyphHeight);
        return glyphsPositions;
    }

    // resize glyphsPositions vector when needed
    if(textLength > (int)glyphsPositions.size())
        glyphsPositions.resize(textLength);

    // calculate lines width
    if((align & Fw::AlignRight || align & Fw::AlignHorizontalCenter) || textBoxSize) {
        lineWidths[0] = 0;
        float spacingErr = 0.0f; // sub-pixel advance dithering; MUST mirror the positioning loop
        for(i = 0; i< textLength; ++i) {
            glyph = (uchar)text[i];

            const InlineTextImage* inlineImg = (glyph < 32 && g_fonts.hasInlineImages()) ? g_fonts.getInlineImage(glyph) : nullptr;
            if(glyph == (uchar)'\n') {
                lines++;
                if(lines+1 > (int)lineWidths.size())
                    lineWidths.resize(lines+1);
                lineWidths[lines] = 0;
                spacingErr = 0.0f;
            } else if(glyph >= 32 || inlineImg) {
                lineWidths[lines] += inlineImg ? inlineImg->width : m_glyphsSize[glyph].width();
                if((i+1 != textLength && text[i+1] != '\n')) { // only add space if letter is not the last or before a \n.
                    lineWidths[lines] += m_glyphSpacing.width();
                    if(m_glyphSpacingFrac != 0.0f && (spacingErr += m_glyphSpacingFrac) >= 1.0f) {
                        lineWidths[lines] += 1;
                        spacingErr -= 1.0f;
                    }
                }
                maxLineWidth = std::max<int>(maxLineWidth, lineWidths[lines]);
            }
        }
    }

    Point virtualPos(0, m_yOffset);
    lines = 0;
    float spacingErr = 0.0f; // sub-pixel advance dithering, reset per line
    for(i = 0; i < textLength; ++i) {
        glyph = (uchar)text[i];

        // new line or first glyph
        if(glyph == (uchar)'\n' || i == 0) {
            if(glyph == (uchar)'\n') {
                virtualPos.y += m_glyphHeight + m_glyphSpacing.height();
                lines++;
            }
            spacingErr = 0.0f;

            // calculate start x pos
            if(align & Fw::AlignRight) {
                virtualPos.x = (maxLineWidth - lineWidths[lines]);
            } else if(align & Fw::AlignHorizontalCenter) {
                virtualPos.x = (maxLineWidth - lineWidths[lines]) / 2;
            } else { // AlignLeft
                virtualPos.x = 0;
            }
        }

        // store current glyph topLeft
        glyphsPositions[i] = virtualPos;

        // advance by the glyph width, or by an inline image's reserved width
        if(glyph >= 32 && glyph != (uchar)'\n') {
            virtualPos.x += m_glyphsSize[glyph].width() + m_glyphSpacing.width();
            if(m_glyphSpacingFrac != 0.0f && (spacingErr += m_glyphSpacingFrac) >= 1.0f) {
                virtualPos.x += 1;
                spacingErr -= 1.0f;
            }
        } else if(glyph < 32 && glyph != (uchar)'\n' && g_fonts.hasInlineImages()) {
            if(const InlineTextImage* inlineImg = g_fonts.getInlineImage(glyph)) {
                virtualPos.x += inlineImg->width + m_glyphSpacing.width();
                if(m_glyphSpacingFrac != 0.0f && (spacingErr += m_glyphSpacingFrac) >= 1.0f) {
                    virtualPos.x += 1;
                    spacingErr -= 1.0f;
                }
            }
        }
    }

    if(textBoxSize) {
        textBoxSize->setWidth(maxLineWidth);
        textBoxSize->setHeight(virtualPos.y + m_glyphHeight);
    }

    return glyphsPositions;
}

Size BitmapFont::calculateTextRectSize(const std::string& text)
{
    Size size;
    calculateGlyphsPositions(text, Fw::AlignTopLeft, &size);
    return size;
}

std::string BitmapFont::wrapText(const std::string& text, int maxWidth, std::vector<std::pair<int, Color>>* colors)
{
    std::string outText;
    outText.reserve(text.size() * 2); // string append optimization

    int lastSeparator = 0, lastColorSeparator = 0, lineLength = 0, wordLength = 0;
    // Wrapping must not UNDER-estimate the drawn width or the line overflows: a sub-pixel
    // advance (frac > 0) draws at intSpacing+frac on average, so round the spacing UP here.
    const int wrapSpacing = m_glyphSpacing.width() + (m_glyphSpacingFrac > 0.0f ? 1 : 0);
    for (size_t i = 0, c = 0; i < text.size(); ++i) {
        uchar glyph = (uchar)text[i];
        if (text[i] == '\n' || text[i] == ' ') {
            lineLength += wordLength;
            if (lineLength > maxWidth) { // too long line with this word
                if (text[lastSeparator] == ' ') {
                    c -= 1;
                    updateColors(colors, lastColorSeparator, -1);
                    lastSeparator += 1;
                    lastColorSeparator += 1;
                }
                outText += '\n';
                lineLength = wordLength;
            }
            for (size_t j = lastSeparator; j < i; ++j) { // copy word
                outText += text[j];
            }
            if (text[i] == '\n') { // if new line was added reset line length
                outText += '\n';
                wordLength = 0;
                lineLength = 0;
                lastSeparator = i + 1;
                lastColorSeparator = c;
            } else { // space
                wordLength = m_glyphsSize[glyph].width() + wrapSpacing; // space
                lastSeparator = i;
                lastColorSeparator = c;
                c += 1;
            }
            continue;
        }

        if (glyph < 32) { // control byte: invalid, unless it is an inline image
            // Reserve the icon's width in the current word, but never let it count
            // toward the colorable index c (color positions track only glyphs >= 32).
            if (g_fonts.hasInlineImages()) {
                if (const InlineTextImage* inlineImg = g_fonts.getInlineImage(glyph))
                    wordLength += inlineImg->width + wrapSpacing;
            }
            continue;
        }

        wordLength += m_glyphsSize[glyph].width() + wrapSpacing;
        if (wordLength > maxWidth) { // too long word, split it
            if (lineLength != 0) { // add new line if current one is not empty
                outText += '\n';
            }
            if (text[lastSeparator] == ' ') { // ignore space if it's first character in new line
                c -= 1;
                lastSeparator += 1;
                lastColorSeparator += 1;
            }
            for (size_t j = lastSeparator; j < i; ++j) { // copy word
                outText += text[j];
            }
            updateColors(colors, lastColorSeparator, 1);
            outText += '-'; // word continuation
            outText += '\n'; // new line

            wordLength = m_glyphsSize[glyph].width() + wrapSpacing;
            lineLength = 0;
            lastSeparator = i;
            lastColorSeparator = c;
        }
        c += 1;
    }

    lineLength += wordLength;
    if (lineLength > maxWidth) { // too long line with this word
        if (text[lastSeparator] == ' ') { // ignore space if it's first character in new line
            lastSeparator += 1;
            lastColorSeparator += 1;
        }

        updateColors(colors, lastColorSeparator, 1);
        outText += '\n';
        lineLength = wordLength;
    }
    for (size_t j = lastSeparator; j < text.size(); ++j) { // copy word
        outText += text[j];
    }
    return outText;
}

bool BitmapFont::calculateGlyphsWidthsAutomatically(const ImagePtr& image, const Size& glyphSize)
{
    if (!image || glyphSize.isEmpty())
        return false;

    const Size& imageSize = image->getSize();
    const int imageWidth = imageSize.width();
    const int imageHeight = imageSize.height();
    const int bpp = image->getBpp();
    if (imageWidth <= 0 || imageHeight <= 0 || bpp <= 0)
        return false;

    const int numHorizontalGlyphs = imageWidth / glyphSize.width();
    const int numVerticalGlyphs = imageHeight / glyphSize.height();
    const int availableGlyphs = numHorizontalGlyphs * numVerticalGlyphs;
    if (numHorizontalGlyphs <= 0 || numVerticalGlyphs <= 0 || availableGlyphs <= 0)
        return false;

    const auto& texturePixels = image->getPixels();
    const size_t pixelBytes = texturePixels.size();

    for (int glyph = m_firstGlyph; glyph < 256; ++glyph)
        m_glyphsSize[glyph] = Size(0, m_glyphHeight);

    // small AI to auto calculate pixels widths
    for (int glyphOffset = 0; glyphOffset < availableGlyphs; ++glyphOffset) {
        const int glyph = m_firstGlyph + glyphOffset;
        if (glyph >= 256)
            break;

        Rect glyphCoords((glyphOffset % numHorizontalGlyphs) * glyphSize.width(),
                         (glyphOffset / numHorizontalGlyphs) * glyphSize.height(),
                         glyphSize.width(),
                         m_glyphHeight);
        const int scanRight = std::min(glyphCoords.right(), imageWidth - 1);
        const int scanBottom = std::min(glyphCoords.bottom(), imageHeight - 1);
        int width = glyphSize.width();
        for (int x = glyphCoords.left(); x <= scanRight; ++x) {
            int filledPixels = 0;
            for (int y = glyphCoords.top(); y <= scanBottom; ++y) {
                const size_t pixelOffset = (static_cast<size_t>(y) * imageWidth + x) * bpp;
                bool filled = false;
                if (bpp >= 4) {
                    filled = pixelOffset + 3 < pixelBytes && texturePixels[pixelOffset + 3] != 0;
                } else if (bpp >= 3) {
                    filled = pixelOffset + 2 < pixelBytes &&
                             (texturePixels[pixelOffset] != 0 ||
                              texturePixels[pixelOffset + 1] != 0 ||
                              texturePixels[pixelOffset + 2] != 0);
                } else if (bpp == 2) {
                    filled = pixelOffset + 1 < pixelBytes && texturePixels[pixelOffset + 1] != 0;
                } else {
                    filled = pixelOffset < pixelBytes && texturePixels[pixelOffset] != 0;
                }
                if (filled)
                    filledPixels++;
            }
            if (filledPixels > 0)
                width = x - glyphCoords.left() + 1;
        }
        // store glyph size
        m_glyphsSize[glyph].resize(width, m_glyphHeight);
    }
    return true;
}

void BitmapFont::updateColors(std::vector<std::pair<int, Color>>* colors, int pos, int newTextLen)
{
    if (!colors) return;
    for (auto& it : *colors) {
        if (it.first > pos) {
            it.first += newTextLen;
        }
    }
}
