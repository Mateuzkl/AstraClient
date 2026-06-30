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
#include "fontmanager.h"
#include "texture.h"
#include "texturemanager.h"
#include "truetypefont.h"

#include <framework/core/eventdispatcher.h>
#include <framework/core/resourcemanager.h>
#include <framework/otml/otml.h>

#include <algorithm>
#include <cctype>
#include <cstdlib>

FontManager g_fonts;

namespace {
// Parse a dynamic TTF request "file.ttf@SIZE" (or .otf). Returns false for any
// name that is not such a request, so normal named fonts are unaffected.
bool parseDynamicTtfRequest(const std::string& req, std::string& ttfFile, int& size)
{
    const size_t at = req.rfind('@');
    if (at == std::string::npos || at + 1 >= req.size())
        return false;

    const std::string base = req.substr(0, at);
    const std::string num = req.substr(at + 1);

    std::string lower = base;
    std::transform(lower.begin(), lower.end(), lower.begin(),
                   [](unsigned char c) { return (char)std::tolower(c); });
    if (lower.size() < 4)
        return false;
    const std::string ext = lower.substr(lower.size() - 4);
    if (ext != ".ttf" && ext != ".otf")
        return false;

    for (const char c : num)
        if (!std::isdigit((unsigned char)c))
            return false;

    ttfFile = base;
    size = std::max(1, std::atoi(num.c_str()));
    return true;
}
}

FontManager::FontManager()
{
    truetypefont::init();
    m_defaultFont = std::make_shared<BitmapFont>("emptyfont");
}

void FontManager::terminate()
{
    m_fonts.clear();
    m_defaultFont = nullptr;
    truetypefont::terminate();
}

void FontManager::clearFonts()
{
    m_fonts.clear();
    m_defaultFont = std::make_shared<BitmapFont>("emptyfont");
}

void FontManager::importFont(std::string file)
{
    if (g_graphicsThreadId != std::this_thread::get_id()) {
        g_graphicsDispatcher.addEvent(std::bind(&FontManager::importFont, this, file));
        return;
    }
    try {
        file = g_resources.guessFilePath(file, "otfont");

        OTMLDocumentPtr doc = OTMLDocument::parse(file);
        OTMLNodePtr fontNode = doc->at("Font");

        std::string name = fontNode->valueAt("name");
        if (fontExists(name))
            return;

        // remove any font with the same name
        for(auto it = m_fonts.begin(); it != m_fonts.end(); ++it) {
            if((*it)->getName() == name) {
                m_fonts.erase(it);
                break;
            }
        }

        auto font = std::make_shared<BitmapFont>(name);
        // KoliseuOT: an .otfont may rasterize from a .ttf instead of a bitmap
        // atlas (ttf-file + size [+ ttf-outline]). importFont runs on the
        // graphics thread, so the texture upload is safe here.
        const std::string ttfFile = fontNode->valueAt<std::string>("ttf-file", "");
        if (!ttfFile.empty()) {
            const std::string resolvedTtf = stdext::resolve_path(ttfFile, fontNode->source());
            const int size = fontNode->valueAt<int>("size", 12);
            const bool outline = fontNode->valueAt<bool>("ttf-outline", false);
            // ttf-mono: crisp 1-bit body without an outline (thicker than grayscale AA,
            // matches the old pixel-art UI bitmaps). Ignored when ttf-outline is set.
            const bool mono = fontNode->valueAt<bool>("ttf-mono", false);
            // letter-spacing may be fractional (e.g. -0.5) for sub-pixel horizontal advance.
            // line-spacing trims the gap BETWEEN lines of multi-line text (defaults to a
            // small negative so all wrapped/multi-line text reads tighter); it never touches
            // single-line widgets (only the per-newline vertical step uses it).
            const float letterSpacing = fontNode->valueAt<float>("letter-spacing", 0.0f);
            const int lineSpacing = fontNode->valueAt<int>("line-spacing", -2);
            const int yOffset = fontNode->valueAt<int>("y-offset", 0);
            const int heightOverride = fontNode->valueAt<int>("height", 0);
            const int baselineOverride = fontNode->valueAt<int>("baseline", 0);
            font->loadTTF(resolvedTtf, size, outline, mono, letterSpacing, lineSpacing, yOffset, heightOverride, baselineOverride);
        } else {
            font->load(fontNode);
        }
        m_fonts.push_back(font);

        // set as default if needed
        if(!m_defaultFont || fontNode->valueAt<bool>("default", false))
            m_defaultFont = font;

    } catch(stdext::exception& e) {
        g_logger.error(stdext::format("Unable to load font from file '%s': %s", file, e.what()));
    }
}

bool FontManager::fontExists(const std::string& fontName)
{
    for(const BitmapFontPtr& font : m_fonts) {
        if(font->getName() == fontName)
            return true;
    }
    return false;
}

BitmapFontPtr FontManager::getFont(const std::string& fontName)
{
    // find font by name
    for(const BitmapFontPtr& font : m_fonts) {
        if(font->getName() == fontName)
            return font;
    }

    // KoliseuOT: dynamic TTF request "file.ttf@SIZE" -> rasterize on demand and
    // cache under the full request name (so the loop above hits it next time).
    // Smooth (no outline); for an outlined TTF use a .otfont with ttf-outline.
    // Safe on any thread: the Texture upload is lazy (first draw).
    std::string ttfFile;
    int ttfSize = 12;
    if (parseDynamicTtfRequest(fontName, ttfFile, ttfSize)) {
        try {
            std::string resolved = g_resources.resolvePath(ttfFile);
            if (!g_resources.fileExists(resolved)) {
                const std::string inFonts = g_resources.resolvePath("/data/fonts/" + ttfFile);
                if (g_resources.fileExists(inFonts))
                    resolved = inFonts;
            }
            if (g_resources.fileExists(resolved)) {
                auto font = std::make_shared<BitmapFont>(fontName);
                font->loadTTF(resolved, ttfSize, false, false, 0.0f, -2, 0, 0, 0);
                m_fonts.push_back(font);
                return font;
            }
        } catch (stdext::exception& e) {
            g_logger.error(stdext::format("font '%s' failed: %s", fontName, e.what()));
            return getDefaultFont();
        }
    }

    // when not found, fallback to default font
    g_logger.error(stdext::format("font '%s' not found", fontName));
    return getDefaultFont();
}

void FontManager::registerInlineImage(int code, const std::string& file, int srcX, int srcY, int srcW, int srcH, int yOffset)
{
    // Only control bytes are valid: they must not collide with real glyphs
    // (>= 32) or with whitespace control codes (\t \n \v \f \r). The latter is
    // important because Lua's setHTML/setColorText shims trim and collapse with
    // the %s class, which would silently eat \v (11) and \f (12) placeholders.
    if (code <= 0 || code >= 32 || code == '\t' || code == '\n' ||
        code == '\v' || code == '\f' || code == '\r')
        return;

    TexturePtr tex = g_textures.getTexture(file);
    if (!tex)
        return;
    // NOTE: do not call tex->update() here. This runs on the Lua thread; the GL
    // upload happens lazily on the graphics thread via Painter::setTexture when
    // the icon is first drawn.

    InlineTextImage& img = m_inlineImages[code];
    const bool wasEmpty = img.width == 0;
    img.texture = tex;
    img.srcRect = Rect(srcX, srcY, srcW, srcH);
    img.width = srcW;   // drawn 1:1 with the source region
    img.height = srcH;
    img.yOffset = yOffset;
    if (wasEmpty)
        m_inlineImageCount++;
}

void FontManager::registerStyleFont(int code, const std::string& fontName)
{
    // Same control-byte rules as inline images: never collide with real glyphs
    // (>= 32) or whitespace control codes the text layout treats specially.
    if (code <= 0 || code >= 32 || code == '\t' || code == '\n' ||
        code == '\v' || code == '\f' || code == '\r')
        return;

    const bool wasEmpty = !m_styleFonts[code] && !m_styleReset[code];
    if (fontName.empty()) {
        m_styleReset[code] = true;
        m_styleFonts[code] = nullptr;
    } else {
        m_styleReset[code] = false;
        m_styleFonts[code] = getFont(fontName); // falls back to default if missing
    }
    if (wasEmpty)
        m_styleCount++;
}

const BitmapFontPtr& FontManager::getStyleFont(int code) const
{
    static const BitmapFontPtr none;
    return (code > 0 && code < 256) ? m_styleFonts[code] : none;
}
