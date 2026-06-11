#include "painter.h"
#include "textrender.h"
#include <framework/graphics/atlas.h>
#include <framework/graphics/drawcache.h>
#include <framework/core/logger.h>
#include <framework/core/eventdispatcher.h>

TextRender g_text;

void TextRender::init()
{

}

void TextRender::terminate()
{
    for (auto& cache : m_cache) {
        cache.clear();
    }
}

void TextRender::poll()
{
    static int iteration = 0;
    int index = (iteration++) % INDEXES;
    std::lock_guard<std::mutex> lock(m_mutex[index]);
    auto& cache = m_cache[index];
    if (cache.size() < 100)
        return;

    ticks_t dropPoint = g_clock.millis();
    if (cache.size() > 500)
        dropPoint -= 10;
    else if (cache.size() > 250)
        dropPoint -= 100;
    else
        dropPoint -= 1000;

    for (auto it = cache.begin(); it != cache.end(); ) {
        if (it->second->lastUse < dropPoint) {
            it = cache.erase(it);
            continue;
        }
        ++it;
    }
}

uint64_t TextRender::addText(BitmapFontPtr font, const std::string& text, const Size& size, Fw::AlignmentFlag align)
{
    if (!font || text.empty() || !size.isValid()) 
        return 0;
    uint64_t hash = 1125899906842597ULL;
    for (size_t i = 0; i < text.length(); ++i) {
        hash = hash * 31 + text[i];
    }
    hash = hash * 31 + size.width();
    hash = hash * 31 + size.height();
    hash = hash * 31 + (uint64_t)align;
    hash = hash * 31 + (uint64_t)font->getId();

    int index = hash % INDEXES;
    m_mutex[index].lock();
    auto it = m_cache[index].find(hash);
    if (it == m_cache[index].end()) {
        m_cache[index][hash] = std::make_shared<TextRenderCache>(TextRenderCache{ font, text, size, align, font->getTexture(), CoordsBuffer(), g_clock.millis() });
    }
    m_mutex[index].unlock();
    return hash;
}

std::shared_ptr<TextRenderCache> TextRender::getTextCache(uint64_t hash)
{
    int index = hash % INDEXES;
    std::lock_guard<std::mutex> lock(m_mutex[index]);
    auto it = m_cache[index].find(hash);
    if (it == m_cache[index].end())
        return nullptr;

    it->second->lastUse = g_clock.millis();
    return it->second;
}

void TextRender::prepareCoords(const std::shared_ptr<TextRenderCache>& cache)
{
    if (!cache || !cache->font)
        return;

    cache->font->calculateDrawTextCoords(cache->coords, cache->text, Rect(0, 0, cache->size), cache->align);
    cache->coords.cache();
    cache->text.clear();
    cache->font.reset();
}

bool TextRender::cacheFontTexture(const TexturePtr& texture, Point& atlasPos)
{
    if (!texture || !texture->canCache())
        return false;

    texture->update();
    uint64_t hash = 1469598103934665603ULL ^ texture->getUniqueId();
    bool drawNow = false;
    atlasPos = g_atlas.cache(hash, texture->getSize(), drawNow);
    if (atlasPos.x < 0)
        return false;

    if (drawNow) {
        g_drawCache.bind();
        g_painter->resetColor();
        g_painter->drawTexturedRect(Rect(atlasPos, texture->getSize()), texture, Rect(Point(0, 0), texture->getSize()));
    }

    return true;
}

bool TextRender::cacheText(const Point& pos, uint64_t hash, const Color& color, bool shadow)
{
    auto cache = getTextCache(hash);
    if (!cache)
        return true;

    prepareCoords(cache);

    Point atlasPos;
    if (!cacheFontTexture(cache->texture, atlasPos))
        return false;

    const int vertexCount = cache->coords.getVertexCount();
    const int requiredVertices = vertexCount * (shadow ? 2 : 1);
    if (!g_drawCache.hasSpace(requiredVertices))
        return false;

    if (shadow)
        g_drawCache.addTexturedCoords(cache->coords, Point(pos.x + 1, pos.y + 1), atlasPos, Color::black);

    g_drawCache.addTexturedCoords(cache->coords, pos, atlasPos, color);
    return true;
}

bool TextRender::cacheColoredText(const Point& pos, uint64_t hash, const std::vector<std::pair<int, Color>>& colors, bool shadow)
{
    if (colors.empty())
        return cacheText(pos, hash, Color::white, shadow);

    auto cache = getTextCache(hash);
    if (!cache)
        return true;

    prepareCoords(cache);

    Point atlasPos;
    if (!cacheFontTexture(cache->texture, atlasPos))
        return false;

    const int vertexCount = cache->coords.getVertexCount();
    if (!g_drawCache.hasSpace(vertexCount))
        return false;

    int startChar = 0;
    for (const auto& colorRange : colors) {
        const int endChar = colorRange.first;
        const int firstVertex = startChar * 6;
        const int rangeVertexCount = (endChar - startChar) * 6;
        if (rangeVertexCount > 0)
            g_drawCache.addTexturedCoordsRange(cache->coords, pos, atlasPos, colorRange.second, firstVertex, rangeVertexCount);
        startChar = endChar;
    }
    return true;
}

void TextRender::drawText(const Rect& rect, const std::string& text, BitmapFontPtr font, const Color& color, Fw::AlignmentFlag align, bool shadow)
{
    VALIDATE_GRAPHICS_THREAD();
    uint64_t hash = addText(font, text, rect.size(), align);
    drawText(rect.topLeft(), hash, color, shadow);
}

void TextRender::drawText(const Point& pos, uint64_t hash, const Color& color, bool shadow)
{
    VALIDATE_GRAPHICS_THREAD();
    auto it = getTextCache(hash);
    if (!it)
        return;

    prepareCoords(it);

    if (shadow) {
        auto shadowPos = Point(pos);
        shadowPos.x += 1;
        shadowPos.y += 1;
        g_painter->drawText(shadowPos, it->coords, Color::black, it->texture);
    }

    g_painter->drawText(pos, it->coords, color, it->texture);
}

void TextRender::drawColoredText(const Point& pos, uint64_t hash, const std::vector<std::pair<int, Color>>& colors, bool shadow)
{
    VALIDATE_GRAPHICS_THREAD();
    if (colors.empty())
        return drawText(pos, hash, Color::white);
    auto it = getTextCache(hash);
    if (!it)
        return;

    prepareCoords(it);
    g_painter->drawText(pos, it->coords, colors, it->texture);
}
