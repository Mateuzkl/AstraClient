#ifndef __EMSCRIPTEN__
#include "session.h"
#include "tls.h"
#include "redirectpolicy.h"
#include <algorithm>
#include <limits>
#include <string_view>

void HttpSession::start()
{
    setup(m_url, m_agent, m_request->timeout, "http,https");
    const auto redirectCode = HttpRedirectPolicy::configure(m_easy, m_url, !m_request->body.empty());
    if (redirectCode != CURLE_OK)
        m_result->error = curl_easy_strerror(redirectCode);
    option(CURLOPT_WRITEFUNCTION, &HttpSession::receive);
    option(CURLOPT_WRITEDATA, this);
    option(CURLOPT_HEADERFUNCTION, &HttpSession::receiveHeader);
    option(CURLOPT_HEADERDATA, this);
    option(CURLOPT_NOPROGRESS, 0L);
    option(CURLOPT_XFERINFOFUNCTION, &HttpSession::progress);
    option(CURLOPT_XFERINFODATA, this);
    for (const auto& entry : m_request->headers)
    {
        if (entry.first.find_first_of("\r\n") != std::string::npos ||
            entry.second.find_first_of("\r\n") != std::string::npos)
        {
            m_result->error = "Invalid HTTP header";
            break;
        }
        header(entry.first + ": " + entry.second);
    }
    if (!m_request->body.empty())
    {
        option(CURLOPT_POSTFIELDS, m_request->body.data());
        option(CURLOPT_POSTFIELDSIZE_LARGE, static_cast<curl_off_t>(m_request->body.size()));
    }
    m_result->session = std::static_pointer_cast<HttpSession>(shared_from_this());
    if (!m_result->error.empty())
    {
        const auto self = std::static_pointer_cast<HttpSession>(shared_from_this());
        asio::post(m_service, [self] { self->completed(CURLE_FAILED_INIT); });
    }
    else
    {
        launch();
    }
}
size_t HttpSession::receive(char* data, size_t size, size_t count, void* context)
{
    auto& self = *static_cast<HttpSession*>(context);
    const auto bytes = size * count;
    constexpr size_t limit = 512ULL * 1024 * 1024;
    if (self.m_result->canceled || bytes > limit - self.m_result->body.size())
        return 0;
    try
    {
        self.m_result->body.insert(self.m_result->body.end(), data, data + bytes);
    }
    catch (...)
    {
        return 0;
    }
    return bytes;
}
size_t HttpSession::receiveHeader(char* data, size_t size, size_t count, void* context)
{
    auto& self = *static_cast<HttpSession*>(context);
    const auto bytes = size * count;
    constexpr size_t limit = 4ULL * 1024 * 1024;
    if (bytes > limit - self.m_headerBytes)
        return 0;
    self.m_headerBytes += bytes;
    try
    {
        const std::string_view line(data, bytes);
        if (line.substr(0, 5) == "HTTP/")
        {
            self.m_result->headers.clear();
            self.m_result->body.clear();
        }
        else if (const auto colon = line.find(':'); colon != std::string_view::npos)
        {
            auto value = line.substr(colon + 1);
            const auto first = value.find_first_not_of(" \t\r\n");
            value = first == std::string_view::npos ? std::string_view() : value.substr(first);
            const auto last = value.find_last_not_of(" \t\r\n");
            if (last != std::string_view::npos)
                value = value.substr(0, last + 1);
            self.m_result->headers[std::string(line.substr(0, colon))] = std::string(value);
        }
    }
    catch (...)
    {
        return 0;
    }
    return bytes;
}
int HttpSession::progress(void* context, curl_off_t total, curl_off_t now, curl_off_t, curl_off_t)
{
    auto& self = *static_cast<HttpSession*>(context);
    if (self.m_result->canceled)
        return 1;
    self.m_result->size = static_cast<int>(std::min<curl_off_t>(total, std::numeric_limits<int>::max()));
    const int value =
        total > 0 ? static_cast<int>(std::min<long double>(100, static_cast<long double>(now) * 100 / total)) : 0;
    if (!self.m_result->finished && value != self.m_result->progress)
    {
        self.m_result->progress = value;
        self.m_progressPending = true;
    }
    return 0;
}
void HttpSession::progressed()
{
    if (!m_progressPending || m_result->finished)
        return;
    m_progressPending = false;
    m_callback(m_result);
}
void HttpSession::completed(CURLcode code)
{
    if (m_result->finished)
    {
        closeTransfer();
        return;
    }
    long status = 0, redirects = 0;
    if (m_easy)
    {
        curl_easy_getinfo(m_easy, CURLINFO_RESPONSE_CODE, &status);
        curl_easy_getinfo(m_easy, CURLINFO_REDIRECT_COUNT, &redirects);
    }
    m_result->status = static_cast<int>(status);
    m_result->redirects = static_cast<int>(redirects);
    m_result->finished = true;
    if (m_result->error.empty())
    {
        if (code != CURLE_OK)
            m_result->error = error(code);
        else if (!m_request->body.empty() && HttpRedirectPolicy::isRedirect(status))
            m_result->error = "POST redirect blocked; configure the final endpoint URL";
        else if (status < 200 || status >= 300)
            m_result->error = "HTTP error " + std::to_string(status);
        else
            m_result->progress = 100;
    }
    closeTransfer();
    m_callback(m_result);
}
void HttpSession::cancel()
{
    if (m_result->finished)
        return;
    m_result->canceled = true;
    m_result->error = "canceled";
    completed(CURLE_ABORTED_BY_CALLBACK);
}
#endif
