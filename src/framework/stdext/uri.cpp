#include <regex>
#include <algorithm>

#include "uri.h"

ParsedURI parseURI(const std::string& url)
{
    ParsedURI result;
    auto value_or = [](const std::string& value, std::string&& deflt) -> std::string {
        return (value.empty() ? deflt : value);
    };
    // Note: only "http", "https", "ws", and "wss" protocols are supported
    static const std::regex PARSE_URL{ R"((([httpsw]{2,5})://)?([^/ :]+)(:(\d+))?(/(.+)?))",
                                       std::regex_constants::ECMAScript | std::regex_constants::icase };
    std::smatch match;
    if (std::regex_match(url, match, PARSE_URL) && match.size() == 8) {
        std::string proto = match[2];
        std::transform(proto.begin(), proto.end(), proto.begin(), [](unsigned char c) { return std::tolower(c); });
        result.protocol = value_or(proto, "http");
        result.domain = match[3];
        const bool is_sequre_protocol = (result.protocol == "https" || result.protocol == "wss");
        result.port = value_or(match[5], (is_sequre_protocol) ? "443" : "80");
        result.query = value_or(match[6], "/");
    }
    return result;
}