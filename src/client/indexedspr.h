#pragma once

#include <algorithm>
#include <cstdint>
#include <string>

namespace IndexedSpr {
constexpr uint32_t MaxSprites = 10000000;
constexpr uint32_t MaxLocalSprites = 0xffff;

// The default Tibia basename and directory/extensionless inputs select the
// indexed pack. An explicitly named alternative .spr/.cwm remains explicit.
template <typename FileExists> std::string resolveFolder(std::string path, FileExists&& exists)
{
    if (path.empty())
        return { };
    std::replace(path.begin(), path.end(), '\\', '/');
    while (path.size() > 1 && path.back() == '/')
        path.pop_back();

    const auto hasManifest = [&](const std::string& folder) {
        const std::string prefix = folder == "/" ? folder : folder + '/';
        return exists(prefix + "spr_parts.dat") && exists(prefix + "spr_index.dat");
    };
    if (hasManifest(path))
        return path;

    const auto slash = path.find_last_of('/');
    const std::string name = slash == std::string::npos ? path : path.substr(slash + 1);
    if (name.find('.') != std::string::npos && name != "Tibia.spr" && name != "tibia.spr")
        return { };
    const std::string parent = slash == std::string::npos || slash == 0 ? "/" : path.substr(0, slash);
    return hasManifest(parent) ? parent : std::string { };
}

// Subtraction avoids wrapping an untrusted 32-bit address near UINT32_MAX.
inline bool rangeFits(uint32_t offset, uint32_t length, uint32_t fileSize)
{
    return offset <= fileSize && length <= fileSize - offset;
}
}
