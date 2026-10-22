#pragma once

#include <limits>
#include <stdexcept>
#include <vector>

namespace LineGeometry {
template<class Point>
std::vector<float> vertices(const std::vector<Point>& points)
{
    // glDrawArrays takes GLsizei; every point needs two coordinates, not one.
    if (points.size() > static_cast<size_t>(std::numeric_limits<int>::max()) ||
        points.size() > std::vector<float>().max_size() / 2)
        throw std::length_error("line has too many vertices");
    std::vector<float> result;
    result.reserve(points.size() * 2);
    for (const auto& point : points) {
        result.push_back(static_cast<float>(point.x));
        result.push_back(static_cast<float>(point.y));
    }
    return result;
}
}
