#pragma once
#ifndef __EMSCRIPTEN__
#include <asio.hpp>
#include <curl/curl.h>
#include <chrono>
#include <memory>
#include <string>
namespace HttpTls
{
CURLcode configure(CURL* handle);
}

// Runs only on Http's I/O thread; callbacks retain ownership until completion.
// No blocking easy_perform or per-request thread is used.
class CurlTransfer : public std::enable_shared_from_this<CurlTransfer>
{
  public:
    explicit CurlTransfer(asio::io_context& service) : m_service(service), m_pollTimer(service) {}
    virtual ~CurlTransfer() { closeTransfer(); }

  protected:
    template <class T> bool option(CURLoption name, T value)
    {
        const auto code = curl_easy_setopt(m_easy, name, value);
        if (code != CURLE_OK)
            m_setupError = curl_easy_strerror(code);
        return code == CURLE_OK;
    }
    bool setup(const std::string& url, const std::string& agent, int timeout, const char* protocols)
    {
        static const CURLcode initialized = curl_global_init(CURL_GLOBAL_DEFAULT);
        if (initialized != CURLE_OK)
        {
            m_setupError = curl_easy_strerror(initialized);
            return false;
        }
        m_easy = curl_easy_init();
        m_multi = curl_multi_init();
        if (!m_easy || !m_multi)
        {
            m_setupError = "Unable to allocate HTTP transport";
            return false;
        }
        option(CURLOPT_URL, url.c_str());
        option(CURLOPT_USERAGENT, agent.c_str());
        option(CURLOPT_NOSIGNAL, 1L);
        option(CURLOPT_CONNECTTIMEOUT, static_cast<long>(timeout));
        option(CURLOPT_LOW_SPEED_LIMIT, 1L);
        option(CURLOPT_LOW_SPEED_TIME, static_cast<long>(timeout));
        option(CURLOPT_PROTOCOLS_STR, protocols);
        option(CURLOPT_ERRORBUFFER, m_errorBuffer);
        const auto tls = HttpTls::configure(m_easy);
        if (tls != CURLE_OK)
            m_setupError = curl_easy_strerror(tls);
        return m_setupError.empty();
    }
    bool header(const std::string& value)
    {
        auto* next = curl_slist_append(m_headers, value.c_str());
        if (!next)
        {
            m_setupError = "Unable to allocate HTTP headers";
            return false;
        }
        m_headers = next;
        return true;
    }
    void launch()
    {
        if (!m_setupError.empty() || !m_easy || !m_multi)
        {
            const auto self = shared_from_this();
            asio::post(m_service, [self] { self->completed(CURLE_FAILED_INIT); });
            return;
        }
        option(CURLOPT_HTTPHEADER, m_headers);
        if (!m_setupError.empty() || curl_multi_add_handle(m_multi, m_easy) != CURLM_OK)
        {
            const auto self = shared_from_this();
            asio::post(m_service, [self] { self->completed(CURLE_FAILED_INIT); });
            return;
        }
        m_added = true;
        pump();
    }
    std::string error(CURLcode code) const
    {
        if (!m_setupError.empty())
            return m_setupError;
        return m_errorBuffer[0] ? m_errorBuffer : curl_easy_strerror(code);
    }
    void closeTransfer()
    {
        std::error_code ignored;
        m_pollTimer.cancel(ignored);
        if (m_multi && m_easy && m_added)
            curl_multi_remove_handle(m_multi, m_easy);
        m_added = false;
        if (m_easy)
            curl_easy_cleanup(m_easy);
        if (m_multi)
            curl_multi_cleanup(m_multi);
        if (m_headers)
            curl_slist_free_all(m_headers);
        m_easy = nullptr;
        m_multi = nullptr;
        m_headers = nullptr;
    }
    virtual void completed(CURLcode code) = 0;
    virtual void progressed() {}
    virtual void connectedPoll() {}
    asio::io_context& m_service;
    CURL* m_easy = nullptr;

  private:
    void pump()
    {
        const auto self = shared_from_this();
        if (!m_multi)
            return;
        int running = 0;
        const auto code = curl_multi_perform(m_multi, &running);
        if (code != CURLM_OK)
        {
            m_setupError = curl_multi_strerror(code);
            completed(CURLE_FAILED_INIT);
            return;
        }
        // Deliver progress only after libcurl returns. A callback may cancel
        // the transfer; cleaning up a handle from a curl callback is unsafe.
        progressed();
        int remaining = 0;
        while (m_multi)
        {
            auto* message = curl_multi_info_read(m_multi, &remaining);
            if (!message)
                break;
            if (message->msg == CURLMSG_DONE)
                completed(message->data.result);
        }
        if (!m_multi)
            return;
        connectedPoll();
        if (!m_multi)
            return;
        // Active transfers only. The main/render thread never polls this transport.
        m_pollTimer.expires_after(std::chrono::milliseconds(10));
        m_pollTimer.async_wait(
            [self](const std::error_code& ec)
            {
                if (!ec)
                    self->pump();
            });
    }
    CURLM* m_multi = nullptr;
    curl_slist* m_headers = nullptr;
    asio::steady_timer m_pollTimer;
    bool m_added = false;
    char m_errorBuffer[CURL_ERROR_SIZE] = {};
    std::string m_setupError;
};
#endif
