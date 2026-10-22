#include <framework/stdext/cxx23.h>
#include <framework/rml/rmlpixels.h>
#include <array>
#include <cstdlib>

int main()
{
    std::array<std::uint8_t, 4> dest{0, 0, 255, 255};
    const std::array<std::uint8_t, 4> translucent{255, 0, 0, 128};
    RmlPixels::over(dest.data(), translucent.data());
    if (dest != std::array<std::uint8_t, 4>{128, 0, 127, 255}) return EXIT_FAILURE;
    const auto original = dest;
    const std::array<std::uint8_t, 4> transparent{255, 0, 255, 0};
    RmlPixels::over(dest.data(), transparent.data());
    if (dest != original) return EXIT_FAILURE;
    dest = {0, 0, 0, 0};
    RmlPixels::over(dest.data(), translucent.data());
    if (dest != translucent) return EXIT_FAILURE;
    const std::array<std::uint8_t, 4> opaque{5, 6, 7, 255};
    RmlPixels::over(dest.data(), opaque.data());
    return dest == opaque ? EXIT_SUCCESS : EXIT_FAILURE;
}
