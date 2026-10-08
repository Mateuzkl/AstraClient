#ifndef __EMSCRIPTEN__
#include "websocket.h"
#include "tls.h"
#include <array>

void WebsocketSession::start()
{
    setup(m_url, m_agent, m_timeout, "ws,wss");
    option(CURLOPT_CONNECT_ONLY, 2L);
    // libcurl validates the HTTP upgrade, accept key, framing and TLS identity.
    launch();
}
void WebsocketSession::completed(CURLcode code)
{
    if (m_closed)
        return;
    if (code != CURLE_OK)
    {
        fail(error(code));
        return;
    }
    m_result->connected = true;
    m_lastRead = std::chrono::steady_clock::now();
    m_callback(WEBSOCKET_OPEN, "");
    // A CONNECT_ONLY easy handle must remain on its multi handle until close.
}
void WebsocketSession::send(std::string data)
{
    const auto self = shared_from_this();
    if (m_closed)
        return;
    if (data.size() > MaxMessageBytes - m_queuedBytes)
    {
        fail("WebSocket send queue limit exceeded");
        return;
    }
    m_queuedBytes += data.size();
    m_sendQueue.push_back(std::move(data));
    if (m_result->connected)
        wakeConnected();
}
void WebsocketSession::connectedPoll()
{
    if (m_closed || !m_result->connected)
        return;
    if (m_result->canceled)
    {
        close();
        return;
    }
    if (std::chrono::steady_clock::now() - m_lastRead >= std::chrono::seconds(m_timeout))
    {
        fail("timeout");
        return;
    }
    // Limit each turn so a busy socket cannot starve cancellation/other requests.
    for (int work = 0; work < 32 && !m_sendQueue.empty(); ++work)
    {
        auto& message = m_sendQueue.front();
        size_t sent = 0;
        const auto code =
            curl_ws_send(m_easy, message.data() + m_sendOffset, message.size() - m_sendOffset, &sent, 0, CURLWS_TEXT);
        m_sendOffset += sent;
        if (code == CURLE_AGAIN)
            break;
        if (code != CURLE_OK)
        {
            fail(error(code));
            return;
        }
        if (m_sendOffset == message.size())
        {
            m_queuedBytes -= message.size();
            m_sendQueue.pop_front();
            m_sendOffset = 0;
        }
        else
        {
            break;
        }
    }
    std::array<char, 16384> buffer;
    for (int work = 0; work < 32 && !m_closed; ++work)
    {
        size_t received = 0;
        const curl_ws_frame* metadata = nullptr;
        const auto code = curl_ws_recv(m_easy, buffer.data(), buffer.size(), &received, &metadata);
        if (code == CURLE_AGAIN)
        {
            waitConnected(!m_sendQueue.empty(), m_lastRead + std::chrono::seconds(m_timeout));
            return;
        }
        if (code != CURLE_OK)
        {
            fail(error(code));
            return;
        }
        m_lastRead = std::chrono::steady_clock::now();
        if (metadata->flags & CURLWS_CLOSE)
        {
            close();
            return;
        }
        if (!(metadata->flags & (CURLWS_TEXT | CURLWS_BINARY)))
            continue;
        if (received > MaxMessageBytes - m_received.size())
        {
            fail("WebSocket message limit exceeded");
            return;
        }
        m_received.append(buffer.data(), received);
        if (metadata->bytesleft == 0 && !(metadata->flags & CURLWS_CONT))
        {
            auto message = std::move(m_received);
            m_received.clear();
            m_callback(WEBSOCKET_MESSAGE, std::move(message));
        }
    }
    // curl may still have buffered frames after this bounded turn.
    if (!m_closed)
        wakeConnected();
}
void WebsocketSession::close()
{
    const auto self = shared_from_this();
    if (m_closed)
        return;
    m_closed = true;
    if (m_easy && m_result->connected && m_sendQueue.empty())
    {
        const unsigned char normalClose[] = {3, 232}; // RFC 6455 status 1000.
        size_t sent = 0;
        curl_ws_send(m_easy, normalClose, sizeof(normalClose), &sent, 0, CURLWS_CLOSE);
    }
    m_result->connected = false;
    m_result->finished = true;
    closeTransfer();
    m_sendQueue.clear();
    m_received.clear();
    m_callback(WEBSOCKET_CLOSE, "");
}
void WebsocketSession::fail(const std::string& message)
{
    const auto self = shared_from_this();
    if (m_closed)
        return;
    m_result->connected = false;
    m_result->error = message;
    m_callback(WEBSOCKET_ERROR, message);
    close();
}
#endif
