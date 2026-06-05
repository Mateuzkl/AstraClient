#ifndef DRAWQUEUE_H
#define DRAWQUEUE_H

#include <memory>
#include <vector>
#include <framework/graphics/declarations.h>
#include <framework/graphics/coordsbuffer.h>
#include <framework/graphics/paintershaderprogram.h>
#include <framework/graphics/texture.h>
#include <framework/graphics/colorarray.h>
#include <framework/graphics/deptharray.h>
#include <framework/ui/uiwidget.h>

class DrawQueue;
struct DrawQueueItem;

enum DrawType : uint8_t {
    DRAW_ALL = 0,
    DRAW_BEFORE_MAP = 1,
    DRAW_AFTER_MAP = 2
};

struct DrawQueueItem {
    DrawQueueItem(const TexturePtr& texture, const Color& color = Color::white) : 
        m_texture(texture), m_color(color) {}
    virtual ~DrawQueueItem() = default;
    virtual void draw() {}
    virtual void draw(const Point& pos) {}
    virtual bool cache() { return false; }
    virtual void setFlipDirection(uint8_t, const Point&)
    {
        // Non-textured queue items do not own texture coordinates to flip.
    }

    TexturePtr m_texture;
    Color m_color;
};

struct DrawQueueItemTexturedRect : public DrawQueueItem {
    DrawQueueItemTexturedRect() : DrawQueueItem(nullptr) {}
    DrawQueueItemTexturedRect(const Rect& dest, const TexturePtr& texture, const Rect& src, const Color& color) :
        DrawQueueItem(texture, color), m_dest(dest), m_src(src) {};
    virtual ~DrawQueueItemTexturedRect() = default;

    virtual void draw();
    virtual void draw(const Point& pos);
    virtual bool cache();
    void setFlipDirection(uint8_t direction, const Point& center) override
    {
        m_flipDirection = direction;
        if (direction == 1) {
            m_dest.moveLeft(2 * center.x - m_dest.right() + 1);
        } else if (direction == 2) {
            m_dest.moveTop(2 * center.y - m_dest.bottom() + 1);
        }
    }
    uint8_t getFlipDirection() const { return m_flipDirection; }

    Rect m_dest;
    Rect m_src;
    uint8_t m_flipDirection = 0;
};

struct DrawQueueItemTextureCoords : public DrawQueueItem {
    DrawQueueItemTextureCoords(CoordsBuffer& coordsBuffer, const TexturePtr& texture, const Color& color) :
        DrawQueueItem(texture, color), m_coordsBuffer(std::move(coordsBuffer))
    {};

    void draw();
    void draw(const Point& pos);
    bool cache();
    void setFlipDirection(uint8_t direction, const Point& center) override
    {
        m_flipDirection = direction;
        m_flipCenter = center;
    }

    CoordsBuffer m_coordsBuffer;
    uint8_t m_flipDirection = 0;
    Point m_flipCenter;
};

struct DrawQueueItemColoredTextureCoords : public DrawQueueItem {
    DrawQueueItemColoredTextureCoords(CoordsBuffer& coordsBuffer, const TexturePtr& texture, const std::vector<std::pair<int, Color>>& colors) :
        DrawQueueItem(texture), m_coordsBuffer(std::move(coordsBuffer)), m_colors(colors)
    {};

    void draw();
    bool cache() override
    {
        return false;
    }
    void setFlipDirection(uint8_t direction, const Point& center) override
    {
        m_flipDirection = direction;
        m_flipCenter = center;
    }

    CoordsBuffer m_coordsBuffer;
    std::vector<std::pair<int, Color>> m_colors;
    uint8_t m_flipDirection = 0;
    Point m_flipCenter;
};

struct DrawQueueItemImageWithShader : public DrawQueueItemTextureCoords {
    DrawQueueItemImageWithShader(CoordsBuffer& coords, const TexturePtr& texture, const Color& color, const std::string& shader) :
        DrawQueueItemTextureCoords(coords, texture, color), m_shader(shader)
    {};

    void draw() override;
    void draw(const Point& pos) override;
    bool cache() override {
        return false;
    }

    std::string m_shader;
};

struct DrawQueueItemFilledRect : public DrawQueueItem {
    DrawQueueItemFilledRect(const Rect& rect, const Color& color) :
        DrawQueueItem(nullptr, color), m_dest(rect) {};
    bool cache();

    Rect m_dest;
};

struct DrawQueueItemClearRect : public DrawQueueItem {
    DrawQueueItemClearRect(const Rect& rect, const Color& color) :
        DrawQueueItem(nullptr, color), m_dest(rect)
    {};
    void draw();

    Rect m_dest;
};

struct DrawQueueItemFillCoords : public DrawQueueItem {
    DrawQueueItemFillCoords(CoordsBuffer& coordsBuffer, const Color& color) :
        DrawQueueItem(nullptr, color), m_coordsBuffer(std::move(coordsBuffer))
    {};
    bool cache();

    CoordsBuffer m_coordsBuffer;
};

struct DrawQueueItemText : public DrawQueueItem {
    DrawQueueItemText(const Point& point, const TexturePtr& texture, uint64_t hash, const Color& color, bool shadow = false) :
        DrawQueueItem(texture, color), m_point(point), m_hash(hash), m_shadow(shadow)
    {};
    void draw();

    Point m_point;
    uint64_t m_hash;
    bool m_shadow = false;
};

struct DrawQueueItemTextColored : public DrawQueueItem {
    DrawQueueItemTextColored(const Point& point, const TexturePtr& texture, uint64_t hash, const std::vector<std::pair<int, Color>>& colors, bool shadow = false) :
        DrawQueueItem(texture), m_point(point), m_hash(hash), m_colors(colors), m_shadow(shadow)
    {};
    void draw();

    Point m_point;
    uint64_t m_hash;
    std::vector<std::pair<int, Color>> m_colors;
    bool m_shadow = false;
};

struct DrawQueueItemLine : public DrawQueueItem {
    DrawQueueItemLine(const std::vector<Point>& points, int width, const Color& color) :
        DrawQueueItem(nullptr, color), m_points(points), m_width(width)
    {};
    void draw();

    std::vector<Point> m_points;
    int m_width;
};

struct DrawQueueCondition {
    DrawQueueCondition(size_t start, size_t end) :
        m_start(start), m_end(end) {}
    virtual ~DrawQueueCondition() = default;

    virtual void start(DrawQueue*) = 0;
    virtual void end(DrawQueue*) = 0;

    size_t m_start;
    size_t m_end;
};

struct DrawQueueConditionClip : public DrawQueueCondition {
    DrawQueueConditionClip(size_t start, size_t end, const Rect& rect) :
        DrawQueueCondition(start, end), m_rect(rect) {}

    void start(DrawQueue* queue) override;
    void end(DrawQueue* queue) override;

    Rect m_rect;
    Rect m_prevClip;
};

struct DrawQueueConditionRotation : public DrawQueueCondition {
    DrawQueueConditionRotation(size_t start, size_t end, const Point& center, float angle) :
        DrawQueueCondition(start, end), m_center(center), m_angle(angle) {}

    void start(DrawQueue* queue) override;
    void end(DrawQueue* queue) override;

    Point m_center;
    float m_angle;
};

struct DrawQueueConditionMark : public DrawQueueCondition {
    DrawQueueConditionMark(size_t start, size_t end, const Color& color) :
        DrawQueueCondition(start, end), m_color(color)
    {}

    void start(DrawQueue* queue) override;
    void end(DrawQueue* queue) override;

    Color m_color;
};

class DrawQueue {
public:
    DrawQueue() = default;
    DrawQueue(const DrawQueue&) = delete;
    DrawQueue& operator= (const DrawQueue&) = delete;
    ~DrawQueue() = default;

    void draw(DrawType drawType = DRAW_ALL);

    void add(std::unique_ptr<DrawQueueItem> item)
    {
        if (!item) return;
        m_queue.push_back(std::move(item));
    }
    DrawQueueItemTexturedRect* addTexturedRect(const Rect& dest, const TexturePtr& texture, const Rect& src, const Color& color = Color::white)
    {
        auto item = std::make_unique<DrawQueueItemTexturedRect>(dest, texture, src, color);
        auto* itemPtr = item.get();
        m_queue.push_back(std::move(item));
        return itemPtr;
    }
    void addTextureCoords(CoordsBuffer& coords, const TexturePtr& texture, const Color& color = Color::white)
    {
        m_queue.push_back(std::make_unique<DrawQueueItemTextureCoords>(coords, texture, color));
    }
    void addColoredTextureCoords(CoordsBuffer& coords, const TexturePtr& texture, const std::vector<std::pair<int, Color>>& colors)
    {
        m_queue.push_back(std::make_unique<DrawQueueItemColoredTextureCoords>(coords, texture, colors));
    }
    void addFilledRect(const Rect& dest, const Color& color = Color::white)
    {
        m_queue.push_back(std::make_unique<DrawQueueItemFilledRect>(dest, color));
    }
    void addFillCoords(CoordsBuffer& coords, const Color& color = Color::white)
    {
        m_queue.push_back(std::make_unique<DrawQueueItemFillCoords>(coords, color));
    }
    void addClearRect(const Rect& dest, const Color& color = Color::white)
    {
        m_queue.push_back(std::make_unique<DrawQueueItemClearRect>(dest, color));
    }
    void addText(BitmapFontPtr font, const std::string& text, const Rect& screenCoords, Fw::AlignmentFlag align = Fw::AlignTopLeft, const Color& color = Color::white, bool shadow = false);
    void addColoredText(BitmapFontPtr font, const std::string& text, const Rect& screenCoords, Fw::AlignmentFlag align, const std::vector<std::pair<int, Color>>& colors, bool shadow = false);

    void addFilledTriangle(const Point& a, const Point& b, const Point& c, const Color& color = Color::white)
    {
        if (a == b || a == c || b == c)
            return;

        CoordsBuffer coordsBuffer;
        coordsBuffer.addTriangle(a, b, c);
        addFillCoords(coordsBuffer, color);
    }
    void addBoundingRect(const Rect& dest, int innerLineWidth, const Color& color = Color::white)
    {
        if (dest.isEmpty() || innerLineWidth == 0)
            return;

        CoordsBuffer coordsBuffer;
        coordsBuffer.addBoudingRect(dest, innerLineWidth);
        addFillCoords(coordsBuffer, color);
    }

    void addLine(const std::vector<Point>& points, int width, const Color& color = Color::white)
    {
        if (points.empty() || width < 0)
            return;

        m_queue.push_back(std::make_unique<DrawQueueItemLine>(points, width, color));
    }

    void setFrameBuffer(const Rect& dest, const Size& size, const Rect& src);
    bool hasFrameBuffer()
    {
        return m_useFrameBuffer;
    }
    Rect getFrameBufferDest()
    {
        return m_frameBufferDest;
    }
    Size getFrameBufferSize()
    {
        return m_frameBufferSize;
    }
    Rect getFrameBufferSrc()
    {
        return m_frameBufferSrc;
    }

    size_t size()
    {
        return m_queue.size();
    }

    void setOpacity(size_t start, float opacity)
    {
        for (size_t i = start; i < m_queue.size(); ++i) {
            m_queue[i]->m_color = m_queue[i]->m_color.opacity(opacity);
        }
    }

    void setClip(size_t start, const Rect& clip)
    {
        if (start == m_queue.size()) return;
        m_conditions.push_back(std::make_unique<DrawQueueConditionClip>(start, m_queue.size(), clip));
    }

    void setRotation(size_t start, const Point& center, float angle)
    {
        if (start == m_queue.size() || angle == 0) return;
        m_conditions.push_back(std::make_unique<DrawQueueConditionRotation>(start, m_queue.size(), center, angle));
    }

    void setFlip(size_t start, const Point& center, uint8_t direction)
    {
        if (start == m_queue.size()) return;
        for (size_t i = start; i < m_queue.size(); ++i) {
            m_queue[i]->setFlipDirection(direction, center);
        }
    }

    void setMark(size_t start, const Color& color)
    {
        if (start == m_queue.size()) return;
        m_conditions.push_back(std::make_unique<DrawQueueConditionMark>(start, m_queue.size(), color));
    }

    void markMapPosition()
    {
        mapPosition = m_queue.size();
    }
    void correctOutfit(const Rect& dest, int fromPos, bool oldScaling, bool center);

    void setShader(const std::string& shader)
    {
        m_shader = shader;
    }

    std::string getShader()
    {
        return m_shader;
    }

    void setWalkOffset(const PointF& offset)
    {
        m_walkOffset = offset;
    }

    const PointF& getWalkOffset()
    {
        return m_walkOffset;
    }

private:
    std::vector<std::unique_ptr<DrawQueueItem>> m_queue;
    std::vector<std::unique_ptr<DrawQueueCondition>> m_conditions;
    Size m_frameBufferSize;
    Rect m_frameBufferDest, m_frameBufferSrc;
    size_t mapPosition = 0;
    bool m_useFrameBuffer = false;
    float m_scaling = 1.f;
    std::string m_shader;
    PointF m_walkOffset;

    friend struct DrawQueueConditionMark;
};

extern std::shared_ptr<DrawQueue> g_drawQueue;

#endif
