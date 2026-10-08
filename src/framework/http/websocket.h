#pragma once
#ifndef __EMSCRIPTEN__
#include "curltransfer.h"
#include "result.h"
#include <deque>
#include <functional>
enum WebsocketCallbackType
{
    WEBSOCKET_OPEN,
    WEBSOCKET_MESSAGE,
    WEBSOCKET_ERROR,
    WEBSOCKET_CLOSE
};
using WebsocketSession_cb = std::function<void(WebsocketCallbackType, std::string)>;
class WebsocketSession : public CurlTransfer
{
  public:
    WebsocketSession(asio::io_context& service, const std::string& url, const std::string& agent, int timeout,
                     HttpResult_ptr result, WebsocketSession_cb callback)
        : CurlTransfer(service), m_url(url), m_agent(agent), m_timeout(timeout), m_result(std::move(result)),
          m_callback(std::move(callback))
    {
    }
    void start();
    void send(std::string data);
    void close();

  private:
    void completed(CURLcode code) override;
    void connectedPoll() override;
    void fail(const std::string& message);
    std::string m_url, m_agent, m_received;
    int m_timeout;
    HttpResult_ptr m_result;
    WebsocketSession_cb m_callback;
    std::deque<std::string> m_sendQueue;
    size_t m_sendOffset = 0, m_queuedBytes = 0;
    bool m_closed = false;
    std::chrono::steady_clock::time_point m_lastRead;
    static constexpr size_t MaxMessageBytes = 16U * 1024 * 1024;
};
#endif
