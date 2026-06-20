#pragma once
// Compatibilidade C++17 para features C++20 usadas no sistema HTML
// NÃO inclua este header fora de src/framework/html/

#include <string>
#include <string_view>
#include <algorithm>
#include <memory>
#include <vector>
#include <unordered_map>

namespace html_compat {

// Substituto para std::string::starts_with (C++20)
inline bool starts_with(std::string_view str, std::string_view prefix) noexcept {
    return str.size() >= prefix.size() &&
           str.compare(0, prefix.size(), prefix) == 0;
}

inline bool starts_with(const std::string& str, const std::string& prefix) noexcept {
    return str.size() >= prefix.size() &&
           str.compare(0, prefix.size(), prefix) == 0;
}

inline bool starts_with(const std::string& str, const char* prefix) noexcept {
    std::string_view p(prefix);
    return str.size() >= p.size() &&
           str.compare(0, p.size(), p) == 0;
}

// Substituto para std::string::ends_with (C++20)
inline bool ends_with(std::string_view str, std::string_view suffix) noexcept {
    return str.size() >= suffix.size() &&
           str.compare(str.size() - suffix.size(), suffix.size(), suffix) == 0;
}

inline bool ends_with(const std::string& str, const std::string& suffix) noexcept {
    return str.size() >= suffix.size() &&
           str.compare(str.size() - suffix.size(), suffix.size(), suffix) == 0;
}

// Conversão segura string_view → string (para APIs que exigem const std::string&)
inline std::string to_string(std::string_view sv) {
    return std::string(sv);
}

} // namespace html_compat
