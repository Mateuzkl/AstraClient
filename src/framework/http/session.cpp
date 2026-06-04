#ifndef __EMSCRIPTEN__

#include <framework/stdext/uri.h>
#include <chrono>
#include <algorithm>
#include <sstream>

#include "session.h"
#include <string_view>

void HttpSession::start() {
    if (m_result->redirects >= 10) {
        auto self(shared_from_this());
        asio::post(m_service, [self] {
            self->onError("Too many redirects");
        });
        return;
    }
    auto parsedUrl = parseURI(m_url);
    if (parsedUrl.domain.empty()) {
        auto self(shared_from_this());
        asio::post(m_service, [self] {
            self->onError("Invalid url", self->m_url);
        });
        return;
    }

    m_domain = parsedUrl.domain;
    try {
        m_port = parsedUrl.port.empty() ? 0 : std::stoi(parsedUrl.port);
    } catch (std::exception&) {
    }
    if (!m_port) {
        m_port = parsedUrl.protocol == "https" ? 443 : 80;
    }

    m_timer.expires_after(std::chrono::seconds(m_timeout));
    m_timer.async_wait(std::bind(&HttpSession::onTimeout, shared_from_this(), std::placeholders::_1));

    // Construct HTTP request string
    std::string method = m_requestData->body.empty() ? "GET" : "POST";
    std::string target = parsedUrl.query;
    if (target.empty()) target = "/";

    std::ostringstream request_stream;
    request_stream << method << " " << target << " HTTP/1.1\r\n";
    request_stream << "Host: " << m_domain;
    if (m_port != 80 && m_port != 443) {
        request_stream << ":" << m_port;
    }
    request_stream << "\r\n";
    request_stream << "User-Agent: " << m_agent << "\r\n";
    request_stream << "Connection: close\r\n";

    // Set custom headers
    std::map<std::string, std::string> custom_headers = m_requestData->headers;
    for (const auto& header : custom_headers) {
        request_stream << header.first << ": " << header.second << "\r\n";
    }

    if (!m_requestData->body.empty()) {
        if (custom_headers.find("Content-Length") == custom_headers.end() &&
            custom_headers.find("content-length") == custom_headers.end()) {
            request_stream << "Content-Length: " << m_requestData->body.size() << "\r\n";
        }
    }
    request_stream << "\r\n";
    if (!m_requestData->body.empty()) {
        request_stream << m_requestData->body;
    }

    m_requestStr = request_stream.str();
    m_result->session = weak_from_this();

    m_resolver.async_resolve(m_domain, std::to_string(m_port), std::bind(&HttpSession::on_resolve, shared_from_this(), std::placeholders::_1, std::placeholders::_2));
}

void HttpSession::on_resolve(const asio::error_code& ec, asio::ip::tcp::resolver::iterator iterator) {
    if (ec)
        return onError("resolve error", ec.message());
    iterator->endpoint().port(m_port);
    m_socket.async_connect(*iterator, std::bind(&HttpSession::on_connect, shared_from_this(), std::placeholders::_1));
}

void HttpSession::on_connect(const asio::error_code& ec) {
    if (ec)
        return onError("connection error", ec.message());

    if (m_url.find("https") == 0 || m_url.find("HTTPS") == 0)
    {
        m_context = std::make_shared< asio::ssl::context >(asio::ssl::context::tlsv12_client);
        m_ssl = std::make_shared<asio::ssl::stream<asio::ip::tcp::socket&>>(m_socket, *m_context);
        m_ssl->set_verify_mode(asio::ssl::verify_peer);
        m_ssl->set_verify_callback([](bool, asio::ssl::verify_context&) { return true; });         

        if(!SSL_set_tlsext_host_name(m_ssl->native_handle(), m_domain.c_str()))
        {
            asio::error_code ec2(static_cast<int>(::ERR_get_error()), asio::error::get_ssl_category());
            return onError("HTTPS error", ec2.message());
        }

        auto self(shared_from_this());
        m_ssl->async_handshake(asio::ssl::stream_base::client, [&, self] (const asio::error_code& ec) {
            if (ec)
                return onError("HTTPS handshake error", ec.message());

            self->on_handshake(ec);
        });
    }
    else
    {
        asio::async_write(m_socket, asio::buffer(m_requestStr), 
                          std::bind(&HttpSession::on_request_sent, shared_from_this(), std::placeholders::_1));
    }
}

void HttpSession::on_handshake(const asio::error_code& ec) {
    asio::async_write(*m_ssl, asio::buffer(m_requestStr), 
                      std::bind(&HttpSession::on_request_sent, shared_from_this(), std::placeholders::_1));
}

void HttpSession::on_request_sent(const asio::error_code& ec) {
    if (ec)
        return onError("request sending error", ec.message());
    if(m_result->canceled)
        return onError("canceled");

    read_response();
}

void HttpSession::read_response() {
    auto self(shared_from_this());
    if (m_ssl) {
        asio::async_read_until(*m_ssl, m_streambuf, "\r\n\r\n", 
                               std::bind(&HttpSession::on_read_headers, shared_from_this(),
                                         std::placeholders::_1, std::placeholders::_2));
    } else {
        asio::async_read_until(m_socket, m_streambuf, "\r\n\r\n", 
                               std::bind(&HttpSession::on_read_headers, shared_from_this(),
                                         std::placeholders::_1, std::placeholders::_2));
    }
}

void HttpSession::on_read_headers(const asio::error_code& ec, size_t bytes_transferred) {
    if (ec)
        return onError("read header error", ec.message());
    if(m_result->canceled)
        return onError("canceled", ec.message());

    parse_headers();

    std::string location = m_headers["Location"];
    if (location.empty()) {
        location = m_headers["location"];
    }

    if ((m_result->status >= 300 && m_result->status < 400) && !location.empty()) {
        m_result->redirects++;
        auto session = std::make_shared<HttpSession>(m_service, std::string(location), m_agent, m_requestData, m_result, m_callback);
        session->start();
        return close();
    }

    // Now start reading the body
    on_read_body(asio::error_code(), 0);
}

void HttpSession::parse_headers() {
    std::string header_data(asio::buffers_begin(m_streambuf.data()), asio::buffers_begin(m_streambuf.data()) + m_streambuf.size());
    size_t header_end = header_data.find("\r\n\r\n");
    if (header_end == std::string::npos) {
        return; // Should not happen since async_read_until succeeded
    }

    std::string headers_str = header_data.substr(0, header_end);
    m_streambuf.consume(header_end + 4); // Consume headers plus \r\n\r\n

    std::istringstream iss(headers_str);
    std::string line;
    if (std::getline(iss, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        std::istringstream status_iss(line);
        std::string http_ver;
        status_iss >> http_ver >> m_statusCode;
        std::getline(status_iss, m_statusReason);
        if (!m_statusReason.empty() && m_statusReason[0] == ' ') {
            m_statusReason = m_statusReason.substr(1);
        }
    }

    while (std::getline(iss, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (line.empty()) continue;
        size_t colon = line.find(':');
        if (colon != std::string::npos) {
            std::string name = line.substr(0, colon);
            std::string val = line.substr(colon + 1);
            // trim
            name.erase(name.find_last_not_of(" \t\r\n") + 1);
            name.erase(0, name.find_first_not_of(" \t\r\n"));
            val.erase(val.find_last_not_of(" \t\r\n") + 1);
            val.erase(0, val.find_first_not_of(" \t\r\n"));
            m_headers[name] = val;

            std::string lower_name = name;
            std::transform(lower_name.begin(), lower_name.end(), lower_name.begin(), ::tolower);
            if (lower_name == "content-length") {
                try {
                    m_contentLength = std::stoull(val);
                } catch (...) {}
            } else if (lower_name == "transfer-encoding" && val == "chunked") {
                m_chunked = true;
            }
        }
    }

    m_result->status = m_statusCode;
    m_result->size = m_contentLength;
    m_headersParsed = true;
}

static bool parseChunked(const std::vector<uint8_t>& input, std::vector<uint8_t>& output, size_t& parsed_offset) {
    size_t offset = parsed_offset;
    while (offset < input.size()) {
        size_t line_end = 0;
        for (size_t i = offset; i < input.size() - 1; ++i) {
            if (input[i] == '\r' && input[i + 1] == '\n') {
                line_end = i;
                break;
            }
        }
        if (line_end == 0) return false;

        std::string size_str(reinterpret_cast<const char*>(&input[offset]), line_end - offset);
        size_t semi = size_str.find(';');
        if (semi != std::string::npos) {
            size_str = size_str.substr(0, semi);
        }

        size_t chunk_size = 0;
        try {
            chunk_size = std::stoul(size_str, nullptr, 16);
        } catch (...) {
            return true; 
        }

        size_t data_start = line_end + 2;
        if (chunk_size == 0) {
            if (data_start + 2 <= input.size()) {
                parsed_offset = data_start + 2;
                return true; 
            }
            return false;
        }

        if (data_start + chunk_size + 2 <= input.size()) {
            output.insert(output.end(), input.begin() + data_start, input.begin() + data_start + chunk_size);
            offset = data_start + chunk_size + 2; 
        } else {
            return false; 
        }
    }
    parsed_offset = offset;
    return false;
}

void HttpSession::on_read_body(const asio::error_code& ec, size_t bytes_transferred) {
    if (m_result->canceled)
        return onError("canceled");

    // Copy any bytes read into raw body buffer
    if (m_streambuf.size() > 0) {
        const uint8_t* data = asio::buffer_cast<const uint8_t*>(m_streambuf.data());
        m_responseRawBody.insert(m_responseRawBody.end(), data, data + m_streambuf.size());
        m_streambuf.consume(m_streambuf.size());
    }

    bool finished = false;
    if (ec) {
        if (ec == asio::error::eof || ec == asio::error::connection_reset) {
            finished = true;
        } else {
            return onError("read error", ec.message());
        }
    }

    if (!m_chunked && m_contentLength > 0 && m_responseRawBody.size() >= m_contentLength) {
        finished = true;
    }

    bool chunked_complete = false;
    if (m_chunked) {
        chunked_complete = parseChunked(m_responseRawBody, m_result->body, m_chunkedParsedOffset);
        if (chunked_complete) {
            finished = true;
        }
    }

    if (finished) {
        if (!m_chunked) {
            m_result->body = m_responseRawBody;
        }
        process_finished_response();
        return;
    }

    // Report progress
    if (m_contentLength > 0) {
        int new_progress = (int)std::min<int64_t>(100ll, (100ll * (int64_t)m_responseRawBody.size()) / (int64_t)m_contentLength);
        if (!m_result->finished && new_progress != m_result->progress) {
            m_result->progress = new_progress;
            m_callback(m_result);
        }
    }

    m_timer.expires_after(std::chrono::seconds(m_timeout));

    auto self(shared_from_this());
    if (m_ssl) {
        m_ssl->async_read_some(m_streambuf.prepare(16384),
            [this, self](const asio::error_code& ec, size_t bytes) {
                m_streambuf.commit(bytes);
                on_read_body(ec, bytes);
            });
    } else {
        m_socket.async_read_some(m_streambuf.prepare(16384),
            [this, self](const asio::error_code& ec, size_t bytes) {
                m_streambuf.commit(bytes);
                on_read_body(ec, bytes);
            });
    }
}

void HttpSession::process_finished_response() {
    if (!m_result->finished) {
        m_result->finished = true;
        m_result->progress = 100;
        m_result->headers = m_headers;

        if (m_statusCode < 200 || m_statusCode >= 300) {
            m_result->error = "HTTP error " + std::to_string(m_statusCode) + " " + m_statusReason;
        }
        m_callback(m_result);
    }
    close();
}

void HttpSession::close() {
    m_timer.cancel();
    asio::error_code ec;
    m_socket.close(ec);
}

void HttpSession::onTimeout(const asio::error_code& error) {
    if(error)
        return;
    return onError("timeout");
}

void HttpSession::onError(const std::string& error, const std::string& details) {
    asio::error_code ec;
    m_socket.close(ec);
    m_timer.cancel(ec);
    if (!m_result->finished) {
        m_result->finished = true;
        m_result->error = error;
        if (!details.empty()) {
            m_result->error += " (";
            m_result->error += details;
            m_result->error += ")";
        }
        m_callback(m_result);
    }
}

#endif
