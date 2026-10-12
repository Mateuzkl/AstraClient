#ifndef STDEXT_FILESYSTEM_H
#define STDEXT_FILESYSTEM_H

#include <filesystem>
#include <string>

namespace stdext {
// u8string is basic_string<char8_t> since C++20. Copy UTF-8 code units
// explicitly for C APIs (e.g. libzip); do not use path.string(), which uses
// the local Windows code page, or disable char8_t for the whole application.
inline std::string path_to_utf8(const std::filesystem::path& path)
{
    const auto utf8 = path.u8string();
    return std::string(utf8.begin(), utf8.end());
}
}

#endif
