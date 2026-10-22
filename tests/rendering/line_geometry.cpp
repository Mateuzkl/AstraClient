#include <framework/graphics/linegeometry.h>
#include <cstdlib>

struct Point { int x, y; };
int main()
{
    for (const size_t count : {size_t(0), size_t(1), size_t(512), size_t(513), size_t(1024), size_t(100000)}) {
        std::vector<Point> points;
        for (size_t i = 0; i < count; ++i) points.push_back({int(i), -int(i)});
        const auto data = LineGeometry::vertices(points);
        if (data.size() != count * 2) return EXIT_FAILURE;
        for (size_t i = 0; i < count; ++i) {
            if (data[i * 2] != static_cast<float>(points[i].x) || data[i * 2 + 1] != static_cast<float>(points[i].y))
                return EXIT_FAILURE;
        }
    }
    return EXIT_SUCCESS;
}
