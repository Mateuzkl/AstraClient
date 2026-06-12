#ifndef DRAW_CACHE
#define DRAW_CACHE

#include "atlas.h"
#include "coordsbuffer.h"
#include "graphics.h"
#include "painter.h"

class DrawCache {
public:
    static const int MAX_SIZE = 65536;
    static const int HALF_MAX_SIZE = MAX_SIZE / 2;

    void draw();
    void bind();
    void release();
    bool hasSpace(int size) {
        return size + m_size < MAX_SIZE;
    }
    inline int getSize() { return m_size; }
    void addRect(const Rect& dest, const Color& color);
    void addTexturedRect(const Rect& dest, const Rect& src, const Color& color);
    void addTexturedRect(const Rect& dest, const Rect& src, const Color& color, uint8_t flipDirection);
    void addCoords(CoordsBuffer& coords, const Color& color);
    void addTexturedCoords(CoordsBuffer& coords, const Point& offset, const Color& color);

private:
    inline void addRectRaw(float* dest, const Rect& rect)
    {
        dest[0] = dest[4] = dest[6] = rect.left();
        dest[1] = dest[3] = dest[9] = rect.top();
        dest[2] = dest[8] = dest[10] = rect.right() + 1;
        dest[5] = dest[7] = dest[11] = rect.bottom() + 1;
    }
    inline void addFlippedRectRaw(float* dest, const Rect& rect, uint8_t flipDirection)
    {
        if (flipDirection == 1) {
            const float top = rect.top();
            const float right = rect.right() + 1;
            const float bottom = rect.bottom() + 1;
            const float left = rect.left();

            dest[0] = right; dest[1] = top;
            dest[2] = left; dest[3] = top;
            dest[4] = right; dest[5] = bottom;
            dest[6] = right; dest[7] = bottom;
            dest[8] = left; dest[9] = top;
            dest[10] = left; dest[11] = bottom;
            return;
        }

        if (flipDirection == 2) {
            const float top = rect.top();
            const float right = rect.right() + 1;
            const float bottom = rect.bottom() + 1;
            const float left = rect.left();

            dest[0] = left; dest[1] = bottom;
            dest[2] = right; dest[3] = bottom;
            dest[4] = left; dest[5] = top;
            dest[6] = left; dest[7] = top;
            dest[8] = right; dest[9] = bottom;
            dest[10] = right; dest[11] = top;
            return;
        }

        addRectRaw(dest, rect);
    }
    inline void addColorRaw(const Color& color, int count)
    {
        static float c[4];
        c[0] = color.rF();
        c[1] = color.gF();
        c[2] = color.bF();
        c[3] = color.aF();
        for (int start = m_size * 4, end = (m_size + count) * 4; start < end; start += 4) {
            memcpy(m_color.data() + start, c, 4 * sizeof(float));
        }
    }

    std::vector<float> m_destCoord = std::vector<float>(MAX_SIZE * 2);
    std::vector<float> m_srcCoord = std::vector<float>(MAX_SIZE * 2);
    std::vector<float> m_color = std::vector<float>(MAX_SIZE * 4);
    bool m_bound = false;
    int m_size = 0;
};

extern DrawCache g_drawCache;

#endif
