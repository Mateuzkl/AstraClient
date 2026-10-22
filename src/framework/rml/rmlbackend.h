#pragma once

#include <charconv>
#include <string_view>

namespace RmlBackend {
// Read the cached GL_VERSION string: the Lua/UI thread does not own the GL context.
inline bool supportsGles3(std::string_view version) noexcept
{
    constexpr std::string_view prefix = "OpenGL ES ";
    if (!version.starts_with(prefix))
        return false;
    version.remove_prefix(prefix.size());
    const char* const end = version.data() + version.size();
    int major = 0, minor = 0;
    const auto majorResult = std::from_chars(version.data(), end, major);
    if (majorResult.ec != std::errc{} || majorResult.ptr == end || *majorResult.ptr != '.')
        return false;
    const auto minorResult = std::from_chars(majorResult.ptr + 1, end, minor);
    return minorResult.ec == std::errc{} && major >= 3 && minor >= 0;
}
}
