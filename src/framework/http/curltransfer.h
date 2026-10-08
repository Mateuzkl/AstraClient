#pragma once
#ifndef __EMSCRIPTEN__
#include <asio.hpp>
#include <curl/curl.h>
#include <chrono>
#include <map>
#include <memory>
#include <string>
#ifndef WIN32
#include <fcntl.h>
#include <unistd.h>
#endif
namespace HttpTls
{
CURLcode configure(CURL* handle);
}

// Runs only on Http's I/O thread; callbacks retain ownership until completion.
// No blocking easy_perform or per-request thread is used.
class CurlTransfer : public std::enable_shared_from_this<CurlTransfer>
{
  public:
    explicit CurlTransfer(asio::io_context& service) : m_service(service), m_timer(service) {}
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
        curl_multi_setopt(m_multi, CURLMOPT_SOCKETFUNCTION, &CurlTransfer::socketChanged);
        curl_multi_setopt(m_multi, CURLMOPT_SOCKETDATA, this);
        curl_multi_setopt(m_multi, CURLMOPT_TIMERFUNCTION, &CurlTransfer::timerChanged);
        curl_multi_setopt(m_multi, CURLMOPT_TIMERDATA, this);
        option(CURLOPT_URL, url.c_str());
        option(CURLOPT_USERAGENT, agent.c_str());
        option(CURLOPT_NOSIGNAL, 1L);
        option(CURLOPT_CONNECTTIMEOUT, static_cast<long>(timeout));
        option(CURLOPT_LOW_SPEED_LIMIT, 1L);
        option(CURLOPT_LOW_SPEED_TIME, static_cast<long>(timeout));
        option(CURLOPT_PROTOCOLS_STR, protocols);
        option(CURLOPT_ERRORBUFFER, m_errorBuffer);
        option(CURLOPT_CLOSESOCKETFUNCTION, &CurlTransfer::socketClosed);
        option(CURLOPT_CLOSESOCKETDATA, this);
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
        m_closing = true;
        std::error_code ignored;
        m_timer.cancel(ignored);
        for (auto& entry : m_sockets)
        {
            entry.second->active = false;
            entry.second->socket.close(ignored);
        }
        m_sockets.clear();
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
    void wakeConnected()
    {
        if (m_wakePending || !m_multi)
            return;
        m_wakePending = true;
        const auto self = shared_from_this();
        asio::post(m_service, [self] {
            self->m_wakePending = false;
            if (self->m_multi)
                self->connectedPoll();
        });
    }
    void waitConnected(bool writing, std::chrono::steady_clock::time_point deadline)
    {
        if (!m_multi)
            return;
        m_connected = true;
        curl_socket_t socket = CURL_SOCKET_BAD;
        const auto code = curl_easy_getinfo(m_easy, CURLINFO_ACTIVESOCKET, &socket);
        if (code != CURLE_OK || socket == CURL_SOCKET_BAD ||
            !watchSocket(socket, writing ? CURL_POLL_INOUT : CURL_POLL_IN))
        {
            completed(CURLE_FAILED_INIT);
            return;
        }
        // CONNECT_ONLY sockets are no longer serviced by curl's multi timers.
        // Wait for readiness or the actual idle deadline, not a periodic poll.
        m_timer.expires_at(deadline);
        const auto self = shared_from_this();
        m_timer.async_wait([self](const std::error_code& ec) {
            if (!ec && self->m_multi)
                self->connectedPoll();
        });
    }
    asio::io_context& m_service;
    CURL* m_easy = nullptr;

  private:
    struct SocketWatch
    {
        explicit SocketWatch(asio::io_context& service) : socket(service) {}
        asio::ip::tcp::socket socket;
        int interest = CURL_POLL_NONE;
        size_t generation = 0;
        bool active = true, reading = false, writing = false;
    };
    static int socketChanged(CURL*, curl_socket_t socket, int interest, void* context, void*)
    {
        auto& self = *static_cast<CurlTransfer*>(context);
        if (self.m_closing)
            return 0;
        try
        {
            return self.watchSocket(socket, interest) ? 0 : -1;
        }
        catch (const std::exception& exception)
        {
            self.m_setupError = exception.what();
            return -1;
        }
        catch (...)
        {
            return -1;
        }
    }
    static int timerChanged(CURLM*, long timeout, void* context)
    {
        auto& self = *static_cast<CurlTransfer*>(context);
        if (self.m_closing || self.m_connected)
            return 0;
        try
        {
            std::error_code ignored;
            self.m_timer.cancel(ignored);
            if (timeout >= 0)
            {
                self.m_timer.expires_after(std::chrono::milliseconds(timeout));
                const auto owner = self.shared_from_this();
                // A zero timeout must be deferred, never recursively call curl.
                self.m_timer.async_wait([owner](const std::error_code& ec) {
                    if (!ec && owner->m_multi)
                        owner->pump();
                });
            }
            return 0;
        }
        catch (const std::exception& exception)
        {
            self.m_setupError = exception.what();
            return -1;
        }
        catch (...)
        {
            self.m_setupError = "Unable to schedule curl timer";
            return -1;
        }
    }
    bool watchSocket(curl_socket_t descriptor, int interest)
    {
        auto found = m_sockets.find(descriptor);
        if (found != m_sockets.end() && found->second->interest != interest)
        {
            // Windows IOCP association survives duplication. Keep one watcher
            // for the socket's lifetime; only cancel/rearm its readiness waits.
            ++found->second->generation;
            std::error_code ignored;
            found->second->socket.cancel(ignored);
            found->second->reading = found->second->writing = false;
            found->second->interest = interest;
        }
        if (interest == CURL_POLL_REMOVE || interest == CURL_POLL_NONE)
            return true;
        found = m_sockets.find(descriptor);
        auto watch = found == m_sockets.end() ? nullptr : found->second;
        if (!watch)
        {
            watch = std::make_shared<SocketWatch>(m_service);
            // Asio owns a duplicate, never libcurl's original socket. Closing a
            // canceled watcher must not close or double-close the curl handle.
#ifdef WIN32
            WSAPROTOCOL_INFOW info{};
            if (WSADuplicateSocketW(descriptor, GetCurrentProcessId(), &info) != 0)
            {
                m_setupError = "Unable to duplicate curl socket: " + std::to_string(WSAGetLastError());
                return false;
            }
            const auto duplicate =
                WSASocketW(FROM_PROTOCOL_INFO, FROM_PROTOCOL_INFO, FROM_PROTOCOL_INFO, &info, 0, WSA_FLAG_OVERLAPPED);
            if (duplicate == INVALID_SOCKET)
            {
                m_setupError = "Unable to create curl socket watcher: " + std::to_string(WSAGetLastError());
                return false;
            }
#else
            const auto duplicate = fcntl(descriptor, F_DUPFD_CLOEXEC, 0);
            if (duplicate < 0)
            {
                m_setupError = "Unable to duplicate curl socket: " + std::to_string(errno);
                return false;
            }
#endif
            std::error_code ec;
            watch->socket.assign(asio::ip::tcp::v4(), duplicate, ec);
            if (ec)
            {
                m_setupError = "Unable to assign curl socket watcher: " + ec.message();
#ifdef WIN32
                closesocket(duplicate);
#else
                ::close(duplicate);
#endif
                return false;
            }
            watch->interest = interest;
            m_sockets.emplace(descriptor, watch);
        }
        armSocket(descriptor, watch);
        return true;
    }
    static int socketClosed(void* context, curl_socket_t descriptor)
    {
        auto& self = *static_cast<CurlTransfer*>(context);
        const auto found = self.m_sockets.find(descriptor);
        if (found != self.m_sockets.end())
        {
            found->second->active = false;
            std::error_code ignored;
            found->second->socket.close(ignored);
            self.m_sockets.erase(found);
        }
#ifdef WIN32
        return closesocket(descriptor);
#else
        return ::close(descriptor);
#endif
    }
    void armSocket(curl_socket_t descriptor, const std::shared_ptr<SocketWatch>& watch)
    {
        const auto self = shared_from_this();
        auto wait = [&](bool reading) {
            (reading ? watch->reading : watch->writing) = true;
            watch->socket.async_wait(
                reading ? asio::ip::tcp::socket::wait_read : asio::ip::tcp::socket::wait_write,
                [self, watch, descriptor, reading, generation = watch->generation](const std::error_code& ec) {
                    if (generation != watch->generation)
                        return;
                    (reading ? watch->reading : watch->writing) = false;
                    if (!watch->active || !self->m_multi || ec == asio::error::operation_aborted)
                        return;
                    if (ec)
                    {
                        self->completed(CURLE_RECV_ERROR);
                        return;
                    }
                    if (self->m_connected)
                        self->connectedPoll();
                    else
                        self->pump(descriptor, reading ? CURL_CSELECT_IN : CURL_CSELECT_OUT);
                    if (watch->active && self->m_multi)
                        self->armSocket(descriptor, watch);
                });
        };
        if ((watch->interest == CURL_POLL_IN || watch->interest == CURL_POLL_INOUT) && !watch->reading)
            wait(true);
        if ((watch->interest == CURL_POLL_OUT || watch->interest == CURL_POLL_INOUT) && !watch->writing)
            wait(false);
    }
    void pump(curl_socket_t socket = CURL_SOCKET_TIMEOUT, int events = 0)
    {
        const auto self = shared_from_this();
        if (!m_multi)
            return;
        int running = 0;
        const auto code = curl_multi_socket_action(m_multi, socket, events, &running);
        if (code != CURLM_OK)
        {
            if (m_setupError.empty())
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
    }
    CURLM* m_multi = nullptr;
    curl_slist* m_headers = nullptr;
    asio::steady_timer m_timer;
    std::map<curl_socket_t, std::shared_ptr<SocketWatch>> m_sockets;
    bool m_added = false;
    bool m_closing = false, m_connected = false, m_wakePending = false;
    char m_errorBuffer[CURL_ERROR_SIZE] = {};
    std::string m_setupError;
};
#endif
