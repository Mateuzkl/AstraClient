#pragma once
#include <cstdint>

namespace RmlPixels {
// Straight-alpha source-over for CPU sprite composition. Preserve partial alpha
// until the renderer converts the final image to RmlUi's premultiplied format.
inline void over(std::uint8_t* out, const std::uint8_t* in) noexcept
{
    const unsigned sa = in[3], da = out[3];
    if (sa == 0) return;
    const unsigned alpha = sa * 255 + da * (255 - sa);
    for (int c = 0; c < 3; ++c) {
        const unsigned value = in[c] * sa * 255 + out[c] * da * (255 - sa);
        out[c] = static_cast<std::uint8_t>((value + alpha / 2) / alpha);
    }
    out[3] = static_cast<std::uint8_t>((alpha + 127) / 255);
}
}
