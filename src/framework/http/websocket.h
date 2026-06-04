#pragma once

#include <framework/global.h>

#include <iostream>
#include <string>
#include <memory>
#include <functional>
#include <future>
#include <queue>
#include <vector>

#include <asio.hpp>
#include <asio/ssl.hpp>

#include "result.h"

enum WebsocketCallbackType {
    WEBSOCKET_OPEN,
    WEBSOCKET_MESSAGE,
    WEBSOCKET_ERROR,
    WEBSOCKET_CLOSE
};

using WebsocketSession_cb = std::function<void(WebsocketCallbackType, std::string message)>;

class WebsocketSession : public std::enable_shared_from_this<WebsocketSession>
{
public:

    WebsocketSession(asio::io_context& service, const std::string& url, const std::string& agent, int timeout, HttpResult_ptr result, WebsocketSession_cb callback) :
        m_service(service), m_url(url), m_agent(agent), m_resolver(service), m_callback(callback), m_result(result), m_timer(service), m_timeout(timeout)
    {
        VALIDATE(m_callback);
        VALIDATE(m_result);
    };

    void start();
    void send(std::string data);
    void close();

private:
    asio::io_context& m_service;
    std::string m_url;
    std::string m_agent;
    asio::ip::tcp::resolver m_resolver;
    WebsocketSession_cb m_callback;
    HttpResult_ptr m_result;
    asio::steady_timer m_timer;
    int m_timeout;
    bool m_closed = false;
    std::string m_domain;
    int m_port = 0;

    asio::ip::tcp::socket m_socket{ m_service };
    std::shared_ptr<asio::ssl::stream<asio::ip::tcp::socket&>> m_ssl;
    std::shared_ptr<asio::ssl::context> m_context;

    asio::streambuf m_streambuf;
    std::vector<uint8_t> m_receiveBuffer;
    size_t m_parsedOffset = 0;
    std::queue<std::string> m_sendQueue;
    std::string m_expectedAccept;

    void on_resolve(const asio::error_code& ec, const asio::ip::tcp::resolver::results_type& results);
    void on_connect(const asio::error_code& ec);
    void do_handshake();
    void on_handshake_sent(const asio::error_code& ec);
    void read_handshake_response();
    void on_read_handshake(const asio::error_code& ec, size_t bytes);
    void do_read();
    void on_read(const asio::error_code& ec, size_t bytes_transferred);
    void do_write();
    void on_write(const asio::error_code& ec);
    void onTimeout(const asio::error_code& error);
    void onError(const std::string& error, const std::string& details = "");
};