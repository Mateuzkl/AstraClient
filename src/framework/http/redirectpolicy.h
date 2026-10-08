#pragma once
#ifndef __EMSCRIPTEN__
#include <curl/curl.h>
#include <algorithm>
#include <cctype>
#include <string>

namespace HttpRedirectPolicy
{
inline bool isRedirect(long status)
{
    return status == 301 || status == 302 || status == 303 || status == 307 || status == 308;
}
inline CURLcode configure(CURL* handle, const std::string& url, bool post)
{
    // POST may contain login credentials. A scheme filter alone does not
    // prevent 307/308 from forwarding its body to an unrelated origin.
    auto code = curl_easy_setopt(handle, CURLOPT_FOLLOWLOCATION, post ? 0L : 1L);
    if (code != CURLE_OK)
        return code;
    code = curl_easy_setopt(handle, CURLOPT_MAXREDIRS, 10L);
    if (code != CURLE_OK)
        return code;
    const bool secure =
        url.size() >= 6 && std::equal(url.begin(), url.begin() + 6,
                                      "https:", [](unsigned char a, char b) { return std::tolower(a) == b; });
    return curl_easy_setopt(handle, CURLOPT_REDIR_PROTOCOLS_STR, secure ? "https" : "http,https");
}
} // namespace HttpRedirectPolicy
#endif
