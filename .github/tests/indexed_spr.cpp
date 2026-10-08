#include "src/client/indexedspr.h"
#include "src/client/spritedecoder.h"

#include <array>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <set>

static void check(bool value)
{
    if (!value) {
        std::cerr << "Indexed SPR regression check failed\n";
        std::exit(1);
    }
}

int main()
{
    std::set<std::string> files { "/pack/spr_parts.dat", "/pack/spr_index.dat", "/pack/Tibia.spr", "/pack/Tibia.cwm",
        "/pack/custom.spr", "/pack/custom.cwm", "/spr_parts.dat", "/spr_index.dat" };
    const auto exists = [&](const std::string& path) { return files.count(path) != 0; };
    for (const std::string path : { "/pack", "/pack/", "/pack/Tibia", "/pack/Tibia.spr", "\\pack\\Tibia" })
        check(IndexedSpr::resolveFolder(path, exists) == "/pack");
    check(IndexedSpr::resolveFolder("/pack/custom.spr", exists).empty());
    check(IndexedSpr::resolveFolder("/pack/custom.cwm", exists).empty());
    check(IndexedSpr::resolveFolder("/pack/Tibia.cwm", exists).empty());
    for (const std::string path : { "/", "Tibia", "Tibia.spr", "/Tibia.spr" })
        check(IndexedSpr::resolveFolder(path, exists) == "/");
    check(IndexedSpr::resolveFolder("", exists).empty());
    files.erase("/pack/spr_index.dat");
    check(IndexedSpr::resolveFolder("/pack/Tibia", exists).empty());

    check(IndexedSpr::rangeFits(12, 5, 17));
    check(!IndexedSpr::rangeFits(12, 5, 16));
    check(!IndexedSpr::rangeFits(18, 0, 17));
    const auto max = std::numeric_limits<uint32_t>::max();
    check(!IndexedSpr::rangeFits(max - 2, 5, max));
    check(IndexedSpr::rangeFits(max - 5, 5, max));

    // Exercise the same decoder as getSpriteImageIndexed, with guard bytes.
    std::array<uint8_t, 24> guarded { };
    guarded.fill(0xcc);
    auto* pixels = guarded.data() + 4;
    const uint8_t rgb[] = { 0, 0, 1, 0, 10, 20, 30 };
    check(SpriteDecoder::decode(rgb, sizeof(rgb), pixels, 16, false));
    check(pixels[0] == 10 && pixels[3] == 0xff);
    const uint8_t rgba[] = { 0, 0, 1, 0, 10, 20, 30, 40 };
    check(SpriteDecoder::decode(rgba, sizeof(rgba), pixels, 16, true));
    check(pixels[3] == 40);
    const uint8_t partial[] = { 0, 0, 1, 0, 10, 20, 30, 0 };
    check(!SpriteDecoder::decode(partial, sizeof(partial), pixels, 16, false));
    const uint8_t transparentOverflow[] = { 5, 0, 0, 0 };
    check(!SpriteDecoder::decode(transparentOverflow, sizeof(transparentOverflow), pixels, 16, true));
    const uint8_t coloredOverflow[] = { 0, 0, 5, 0 };
    check(!SpriteDecoder::decode(coloredOverflow, sizeof(coloredOverflow), pixels, 16, false));
    check(!SpriteDecoder::decode(rgba, sizeof(rgba) - 1, pixels, 16, true));
    const uint8_t afterFull[] = { 4, 0, 0, 0, 1 };
    check(!SpriteDecoder::decode(afterFull, sizeof(afterFull), pixels, 16, false));
    check(SpriteDecoder::decode(nullptr, 0, pixels, 16, false));
    const uint8_t implicitTail[] = { 1, 0, 1, 0, 10, 20, 30 };
    check(SpriteDecoder::decode(implicitTail, sizeof(implicitTail), pixels, 16, false));
    for (size_t i = 0; i < 4; ++i)
        check(guarded[i] == 0xcc && guarded[20 + i] == 0xcc);
    std::cout << "Indexed SPR source selection, record bounds and RLE: OK\n";
}
