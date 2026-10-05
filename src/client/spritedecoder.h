#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>

namespace SpriteDecoder
{
// Destination pixels are initially transparent, including the implicit tail.
inline bool decode(const uint8_t* data, size_t length, uint8_t* pixels, size_t capacity, bool alpha)
{
    size_t read = 0;
    size_t write = 0;
    const size_t channels = alpha ? 4 : 3;
    while (read < length) {
        if (length - read < 4)
            return false;
        const size_t transparent = data[read] | (static_cast<size_t>(data[read + 1]) << 8);
        const size_t colored = data[read + 2] | (static_cast<size_t>(data[read + 3]) << 8);
        read += 4;
        if (transparent > (capacity - write) / 4)
            return false;
        write += transparent * 4;
        if (colored > (capacity - write) / 4 || colored > (length - read) / channels)
            return false;
        if (alpha) {
            if (colored > 0)
                std::memcpy(pixels + write, data + read, colored * 4);
            read += colored * 4;
            write += colored * 4;
        } else {
            for (size_t i = 0; i < colored; ++i) {
                pixels[write++] = data[read++];
                pixels[write++] = data[read++];
                pixels[write++] = data[read++];
                pixels[write++] = 0xff;
            }
        }
    }
    return true;
}
}
