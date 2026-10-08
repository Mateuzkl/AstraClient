#pragma once
#include <stdexcept>
#include <string>
#include <vector>
#include <utility>

namespace stdext
{
inline std::vector<std::string> parseList(const std::string& text)
{
    std::vector<std::string> result;
    if (text.empty())
        return result;
    std::string value;
    bool quoted = false;
    for (size_t i = 0; i < text.size(); ++i)
    {
        const char c = text[i];
        if (c == '\\')
        {
            if (++i == text.size())
                throw std::runtime_error("Trailing escape in OTML list");
            if (text[i] == 'n')
                value += '\n';
            else if (text[i] == ',' || text[i] == '"' || text[i] == '\\')
                value += text[i];
            else
                throw std::runtime_error("Invalid escape in OTML list");
        }
        else if (c == '"')
            quoted = !quoted;
        else if (c == ',' && !quoted)
        {
            result.push_back(std::move(value));
            value.clear();
        }
        else
            value += c;
    }
    result.push_back(std::move(value));
    return result;
}
} // namespace stdext
