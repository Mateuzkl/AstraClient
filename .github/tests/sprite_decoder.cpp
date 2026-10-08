#include "src/client/spritedecoder.h"

#include <array>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <vector>

static void check(bool value)
{
    if (!value) {
        std::cerr << "Sprite decoder check failed\n";
        std::exit(1);
    }
}

static uint32_t u32(const uint8_t* bytes)
{
    return bytes[0] | (uint32_t(bytes[1]) << 8) | (uint32_t(bytes[2]) << 16) | (uint32_t(bytes[3]) << 24);
}

int main(int argc, char** argv)
{
    std::array<uint8_t, 16> pixels{};
    const uint8_t rgb[] = {1, 0, 1, 0, 10, 20, 30, 1, 0, 1, 0, 40, 50, 60};
    check(SpriteDecoder::decode(rgb, sizeof(rgb), pixels.data(), pixels.size(), false));
    check(pixels[0] == 0 && pixels[4] == 10 && pixels[7] == 255 && pixels[8] == 0 && pixels[12] == 40);
    pixels.fill(0);
    const uint8_t rgba[] = {0, 0, 1, 0, 10, 20, 30, 40};
    check(SpriteDecoder::decode(rgba, sizeof(rgba), pixels.data(), pixels.size(), true));
    check(pixels[0] == 10 && pixels[3] == 40 && pixels[4] == 0);
    check(SpriteDecoder::decode(nullptr, 0, pixels.data(), pixels.size(), false));
    check(!SpriteDecoder::decode(rgb, 3, pixels.data(), pixels.size(), false));
    check(!SpriteDecoder::decode(rgb, 6, pixels.data(), pixels.size(), false));
    check(!SpriteDecoder::decode(rgb, sizeof(rgb), pixels.data(), 4, false));
    const uint8_t overflow[] = {255, 255, 1, 0, 10, 20, 30};
    check(!SpriteDecoder::decode(overflow, sizeof(overflow), pixels.data(), pixels.size(), false));
    const uint8_t tooMany[] = {0, 0, 255, 255, 10, 20, 30};
    check(!SpriteDecoder::decode(tooMany, sizeof(tooMany), pixels.data(), pixels.size(), false));

    if (argc > 1) {
        // Optional streaming validation of an actual plain U32 SPR pack.
        std::ifstream file(argv[1], std::ios::binary);
        check(bool(file));
        std::array<uint8_t, 8> header{};
        check(bool(file.read(reinterpret_cast<char*>(header.data()), header.size())));
        const uint32_t count = u32(header.data() + 4);
        check(count < 10000000);
        std::vector<std::array<uint8_t, 4>> addresses(count);
        check(bool(file.read(reinterpret_cast<char*>(addresses.data()), count * 4)));
        std::array<uint8_t, 4096> spritePixels{};
        size_t checked = 0;
        for (const auto& addressBytes : addresses) {
            const uint32_t address = u32(addressBytes.data());
            if (!address) continue;
            file.seekg(address);
            std::array<uint8_t, 5> record{};
            check(bool(file.read(reinterpret_cast<char*>(record.data()), record.size())));
            const size_t length = record[3] | (size_t(record[4]) << 8);
            std::vector<uint8_t> bytes(length);
            check(bool(file.read(reinterpret_cast<char*>(bytes.data()), length)));
            spritePixels.fill(0);
            check(SpriteDecoder::decode(bytes.data(), bytes.size(), spritePixels.data(), spritePixels.size(), false));
            ++checked;
        }
        std::cout << "Validated " << checked << " sprite records\n";
    }
    std::cout << "Sprite decoder: OK (checks remain active with NDEBUG)\n";
}
