#ifdef NDEBUG
#undef NDEBUG
#endif
#include <framework/platform/browsercursor.h>
#include <framework/graphics/apngloader.h>
#include <cassert>
#include <cstdio>
#include <fstream>
#include <memory>
#include <string>
#include <utility>
#include <vector>

namespace
{
struct CursorImage {
    struct Frame {
        std::shared_ptr<CursorImage> image;
    };
    std::pair<unsigned, unsigned> size;
    std::vector<unsigned char> pixels;
    std::vector<Frame> frames;
    int getBpp() const { return 4; }
    const auto &getSize() const { return size; }
    const auto &getPixels() const { return pixels; }
    const auto &getAnimation() const { return frames; }
};

struct DecodedPng {
    apng_data data{};
    ~DecodedPng() { free_apng(&data); }
};

auto image(unsigned width, unsigned height, const unsigned char *pixels)
{
    auto result = std::make_shared<CursorImage>();
    result->size = {width, height};
    const std::size_t bytes = static_cast<std::size_t>(width) * height * 4;
    result->pixels.assign(pixels, pixels + bytes);
    return result;
}
} // namespace

int main(int argc, char **argv)
{
    const std::string directory = argc > 1 ? argv[1] : "data/cursors";
    for (const char *name : {"cip-default", "textcursor", "cip-targetcursor", "cip-horizontalcursor",
                             "cip-verticalcursor", "cip-pointing", "cursor-attack", "cursor-look", "cursor-open",
                             "cursor-quick-loot", "cursor-talk", "cursor-walk", "cursor-use"}) {
        std::ifstream file(directory + "/" + name + ".png", std::ios::binary);
        assert(file.good());
        std::stringstream contents;
        contents << file.rdbuf();
        DecodedPng png;
        assert(load_apng(contents, &png.data) == 0);
        assert(png.data.bpp == 4 && png.data.width == 32 && png.data.height == 32);
        auto base = image(png.data.width, png.data.height, png.data.pdata);
        if (png.data.num_frames > 1) {
            assert(!astra_browser::hasVisibleCursorPixels(base));
            const std::size_t frameBytes = static_cast<std::size_t>(png.data.width) * png.data.height * 4;
            for (unsigned i = png.data.first_frame; i <= png.data.last_frame; ++i)
                base->frames.push_back({image(png.data.width, png.data.height, png.data.pdata + i * frameBytes)});
        }
        const auto selected = astra_browser::selectCursorImage(base);
        assert(selected && astra_browser::hasVisibleCursorPixels(selected));
        if (png.data.num_frames == 1)
            assert(selected == base); // Static PNG behavior must stay unchanged.
    }
    const unsigned char transparent[4] = {};
    const unsigned char visible[4] = {255, 255, 255, 255};
    auto blank = image(1, 1, transparent);
    assert(!astra_browser::selectCursorImage(blank));
    assert(!astra_browser::selectCursorImage(std::shared_ptr<CursorImage>{}));
    blank->frames.push_back({image(1, 1, transparent)});
    auto frame = image(1, 1, visible);
    blank->frames.push_back({frame});
    assert(astra_browser::selectCursorImage(blank) == frame);
    auto staticImage = image(1, 1, visible);
    staticImage->frames.push_back({blank});
    assert(astra_browser::selectCursorImage(staticImage) == staticImage);
    std::puts("Browser cursor selection: all 13 shipped PNG/APNG cursors and transparent fallback PASS");
}
