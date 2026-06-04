#pragma once

#include <framework/global.h>
#include <iostream>
#include <string>
#include <memory>
#include <functional>
#include <future>
#include <map>
#include <vector>

#include <asio.hpp>
#include <asio/ssl.hpp>

#include "result.h"

class HttpSession : public std::enable_shared_from_this<HttpSession>
{
public:
    HttpSession(asio::io_context& service, const std::string& url, const std::string& agent,
        HttpRequest_ptr request, HttpResult_ptr result, HttpResult_cb callback) :
        m_service(service), m_url(url), m_agent(agent), m_socket(service), m_resolver(service),
        m_callback(callback), m_result(result), m_requestData(request), m_timer(service), m_timeout(request->timeout)
    {
        VALIDATE(m_callback);
        VALIDATE(m_result);
        VALIDATE(m_requestData);
    };

    void start();
    void cancel() { onError("canceled"); }
    
private:
    asio::io_context& m_service;
    std::string m_url;
    std::string m_agent;
    int m_port = 0;
    asio::ip::tcp::socket m_socket;
    asio::ip::tcp::resolver m_resolver;
    HttpResult_cb m_callback;
    HttpResult_ptr m_result;
    HttpRequest_ptr m_requestData;
    asio::steady_timer m_timer;
    int m_timeout;

    std::string m_domain;
    std::shared_ptr<asio::ssl::stream<asio::ip::tcp::socket&>> m_ssl;
    std::shared_ptr<asio::ssl::context> m_context;

    asio::streambuf m_streambuf;
    std::string m_requestStr;
    std::vector<uint8_t> m_responseRawBody;

    // HTTP Parser State
    bool m_headersParsed = false;
    int m_statusCode = 0;
    size_t m_contentLength = 0;
    bool m_chunked = false;
    std::map<std::string, std::string> m_headers;
    std::string m_statusReason;
    size_t m_chunkedParsedOffset = 0;

    void on_resolve(const asio::error_code& ec, const asio::ip::tcp::resolver::results_type& results);
    void on_connect(const asio::error_code& ec);
    void on_handshake(const asio::error_code& ec);
    void on_request_sent(const asio::error_code& ec);
    void read_response();
    void on_read_headers(const asio::error_code& ec, size_t bytes_transferred);
    void on_read_body(const asio::error_code& ec, size_t bytes_transferred);
    void parse_headers();
    void process_finished_response();
    void close();
    void onTimeout(const asio::error_code& error);
    void onError(const std::string& error, const std::string& details = "");
};