#pragma once
#include <algorithm>
#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace astra_uuid
{
using Uuid = std::array<unsigned char, 16>;

inline Uuid name(const Uuid& space, const std::string& text)
{
    // RFC 4122 version 5. Used only to preserve the existing local settings key;
    // SHA-1 here is not a TLS signature or a password-authentication mechanism.
    std::vector<unsigned char> bytes(space.begin(), space.end());
    bytes.insert(bytes.end(), text.begin(), text.end());
    const uint64_t bits = static_cast<uint64_t>(bytes.size()) * 8;
    bytes.push_back(0x80);
    while (bytes.size() % 64 != 56)
        bytes.push_back(0);
    for (int i = 7; i >= 0; --i)
        bytes.push_back(static_cast<unsigned char>(bits >> (i * 8)));
    uint32_t h[] = {0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0xc3d2e1f0};
    const auto rotate = [](uint32_t x, unsigned n) { return (x << n) | (x >> (32 - n)); };
    for (size_t offset = 0; offset < bytes.size(); offset += 64)
    {
        uint32_t w[80] = {};
        for (size_t i = 0; i < 16; ++i)
            for (size_t j = 0; j < 4; ++j)
                w[i] = (w[i] << 8) | bytes[offset + i * 4 + j];
        for (size_t i = 16; i < 80; ++i)
            w[i] = rotate(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
        uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4];
        for (size_t i = 0; i < 80; ++i)
        {
            const uint32_t f = i < 20   ? (b & c) | (~b & d)
                               : i < 40 ? b ^ c ^ d
                               : i < 60 ? (b & c) | (b & d) | (c & d)
                                        : b ^ c ^ d;
            const uint32_t k = i < 20 ? 0x5a827999 : i < 40 ? 0x6ed9eba1 : i < 60 ? 0x8f1bbcdc : 0xca62c1d6;
            const uint32_t next = rotate(a, 5) + f + e + k + w[i];
            e = d;
            d = c;
            c = rotate(b, 30);
            b = a;
            a = next;
        }
        h[0] += a;
        h[1] += b;
        h[2] += c;
        h[3] += d;
        h[4] += e;
    }
    Uuid result{};
    for (size_t i = 0; i < result.size(); ++i)
        result[i] = static_cast<unsigned char>(h[i / 4] >> (24 - (i % 4) * 8));
    result[6] = (result[6] & 0x0f) | 0x50;
    result[8] = (result[8] & 0x3f) | 0x80;
    return result;
}

inline size_t settingsHash(const Uuid& value)
{
#ifdef __EMSCRIPTEN__
    // The previous Emscripten headers port used Boost UUID 1.83, whose
    // wasm32 hash differs from the native 1.86 hash. Preserve web settings too.
    // Copyright 2010 Andy Tompkins, BSL-1.0 (see LICENSE-UUID).
    uint32_t hash = 0;
    for (const auto byte : value)
        hash ^= uint32_t(byte) + 0x9e3779b9U + (hash << 6) + (hash >> 2);
    return hash;
#else
    // Compatibility with the UUID hash used by Astra's pinned Boost 1.86.
    // Mixing functions: Copyright 2024 Peter Dimov, BSL-1.0 (see LICENSE-UUID).
    uint64_t hash = 0;
    for (size_t i = 0; i < value.size(); i += 4)
    {
        const uint32_t word = uint32_t(value[i]) | (uint32_t(value[i + 1]) << 8) | (uint32_t(value[i + 2]) << 16) |
                              (uint32_t(value[i + 3]) << 24);
        hash = (hash + word) * 0xd96aaa55;
        hash ^= hash >> 16;
    }
    hash *= 0x7df954ab;
    hash ^= hash >> 16;
    return static_cast<size_t>(hash);
#endif
}

inline std::string toString(const Uuid& value)
{
    const char* digits = "0123456789abcdef";
    std::string text;
    text.reserve(36);
    for (size_t i = 0; i < value.size(); ++i)
    {
        if (i == 4 || i == 6 || i == 8 || i == 10)
            text += '-';
        text += digits[value[i] >> 4];
        text += digits[value[i] & 15];
    }
    return text;
}
} // namespace astra_uuid
