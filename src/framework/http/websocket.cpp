#ifndef __EMSCRIPTEN__

#include <framework/stdext/uri.h>
#include <chrono>
#include <sstream>
#include <algorithm>
#include <random>
#include <openssl/sha.h>
#include <openssl/rand.h>
#include <framework/util/crypt.h>

#include "websocket.h"

void WebsocketSession::start() {
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
        m_port = parsedUrl.protocol == "wss" ? 443 : 80;
    }

    m_closed = false;
    m_timer.expires_after(std::chrono::seconds(m_timeout));
    m_timer.async_wait(std::bind(&WebsocketSession::onTimeout, shared_from_this(), std::placeholders::_1));

    if (m_url.find("wss") == 0 || m_url.find("WSS") == 0) {
        m_context = std::make_shared< asio::ssl::context >(asio::ssl::context::tlsv12_client);
        m_context->set_default_verify_paths();
        m_ssl = std::make_shared<asio::ssl::stream<asio::ip::tcp::socket&>>(m_socket, *m_context);
        m_ssl->set_verify_mode(asio::ssl::verify_peer);
        m_ssl->set_verify_callback(asio::ssl::rfc2818_verification(m_domain));
        if (!SSL_set_tlsext_host_name(m_ssl->native_handle(), m_domain.c_str())) {
            asio::error_code ec2(static_cast<int>(::ERR_get_error()), asio::error::get_ssl_category());
            return onError("WSS error", ec2.message());
        }
    }

    m_resolver.async_resolve(m_domain, std::to_string(m_port), std::bind(&WebsocketSession::on_resolve, shared_from_this(), std::placeholders::_1, std::placeholders::_2));
}

void WebsocketSession::send(std::string data)
{
    if (m_closed)
        return;

    bool sendNow = m_result->connected && m_sendQueue.empty();
    m_sendQueue.push(data);
    if (sendNow) {
        do_write();
    }
}

void WebsocketSession::on_resolve(const asio::error_code& ec, const asio::ip::tcp::resolver::results_type& results) {
    if (ec)
        return onError("resolve error", ec.message());
    asio::async_connect(m_socket, results, std::bind(&WebsocketSession::on_connect, shared_from_this(), std::placeholders::_1));
}

void WebsocketSession::on_connect(const asio::error_code& ec) {
    if (ec)
        return onError("connection error", ec.message());

    if (m_ssl) {
        auto self(shared_from_this());
        m_ssl->async_handshake(asio::ssl::stream_base::client, [self](const asio::error_code& ec) {
            if (ec)
                return self->onError("WSS handshake error", ec.message());

            self->do_handshake();
        });
    } else {
        do_handshake();
    }
}

void WebsocketSession::do_handshake() {
    auto parsedUrl = parseURI(m_url);
    std::string path = parsedUrl.query;
    if (path.empty()) path = "/";

    std::string nonce;
    nonce.resize(16);
    if (RAND_bytes(reinterpret_cast<unsigned char*>(&nonce[0]), 16) != 1) {
        std::random_device rd;
        for (int i = 0; i < 16; ++i) {
            nonce[i] = static_cast<char>(rd() & 0xFF);
        }
    }
    std::string key = g_crypt.base64Encode(nonce);

    std::string accept_input = key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    unsigned char obuf[20];
    SHA1((const unsigned char*)accept_input.c_str(), accept_input.size(), obuf);
    m_expectedAccept = g_crypt.base64Encode(std::string((const char*)obuf, 20));

    std::ostringstream req;
    req << "GET " << path << " HTTP/1.1\r\n";
    req << "Host: " << m_domain;
    if (m_port != 80 && m_port != 443) {
        req << ":" << m_port;
    }
    req << "\r\n";
    req << "Upgrade: websocket\r\n";
    req << "Connection: Upgrade\r\n";
    req << "Sec-WebSocket-Key: " << key << "\r\n";
    req << "Sec-WebSocket-Version: 13\r\n";
    req << "User-Agent: " << m_agent << "\r\n\r\n";

    auto req_ptr = std::make_shared<std::string>(req.str());
    auto self(shared_from_this());
    if (m_ssl) {
        asio::async_write(*m_ssl, asio::buffer(*req_ptr),
            [self, req_ptr](const asio::error_code& ec, size_t) {
                self->on_handshake_sent(ec);
            });
    } else {
        asio::async_write(m_socket, asio::buffer(*req_ptr),
            [self, req_ptr](const asio::error_code& ec, size_t) {
                self->on_handshake_sent(ec);
            });
    }
}

void WebsocketSession::on_handshake_sent(const asio::error_code& ec) {
    if (ec)
        return onError("handshake send error", ec.message());

    read_handshake_response();
}

void WebsocketSession::read_handshake_response() {
    if (m_ssl) {
        asio::async_read_until(*m_ssl, m_streambuf, "\r\n\r\n",
            std::bind(&WebsocketSession::on_read_handshake, shared_from_this(), std::placeholders::_1, std::placeholders::_2));
    } else {
        asio::async_read_until(m_socket, m_streambuf, "\r\n\r\n",
            std::bind(&WebsocketSession::on_read_handshake, shared_from_this(), std::placeholders::_1, std::placeholders::_2));
    }
}

void WebsocketSession::on_read_handshake(const asio::error_code& ec, size_t bytes) {
    if (ec)
        return onError("handshake read error", ec.message());

    std::string headers(asio::buffers_begin(m_streambuf.data()), asio::buffers_begin(m_streambuf.data()) + bytes);
    m_streambuf.consume(bytes);

    std::string lower_headers = headers;
    std::transform(lower_headers.begin(), lower_headers.end(), lower_headers.begin(), ::tolower);

    if (lower_headers.find("http/1.1 101") == std::string::npos && lower_headers.find("http/1.0 101") == std::string::npos) {
        return onError("handshake rejected - invalid status code", headers);
    }

    if (lower_headers.find("upgrade: websocket") == std::string::npos) {
        return onError("handshake rejected - missing Upgrade", headers);
    }

    if (lower_headers.find("connection: upgrade") == std::string::npos) {
        return onError("handshake rejected - missing Connection", headers);
    }

    size_t accept_pos = lower_headers.find("sec-websocket-accept:");
    if (accept_pos == std::string::npos) {
        return onError("handshake rejected - missing Sec-WebSocket-Accept", headers);
    }

    size_t val_start = accept_pos + std::string("sec-websocket-accept:").length();
    size_t line_end = headers.find("\r\n", val_start);
    if (line_end == std::string::npos) line_end = headers.length();
    std::string accept_val = headers.substr(val_start, line_end - val_start);
    accept_val.erase(accept_val.find_last_not_of(" \t\r\n") + 1);
    accept_val.erase(0, accept_val.find_first_not_of(" \t\r\n"));

    if (accept_val != m_expectedAccept) {
        return onError("handshake rejected - Sec-WebSocket-Accept mismatch", headers);
    }

    m_result->connected = true;
    m_callback(WEBSOCKET_OPEN, "");

    // Start reading WebSocket frames
    do_read();

    // If there were already queued messages to send, send them now
    if (!m_sendQueue.empty()) {
        do_write();
    }
}

static std::vector<uint8_t> buildWebSocketFrame(const std::string& message) {
    std::vector<uint8_t> frame;
    frame.push_back(0x81); // FIN = 1, Opcode = 1 (Text)

    size_t len = message.size();
    if (len < 126) {
        frame.push_back(0x80 | static_cast<uint8_t>(len));
    } else if (len <= 65535) {
        frame.push_back(0x80 | 126);
        frame.push_back((len >> 8) & 0xFF);
        frame.push_back(len & 0xFF);
    } else {
        frame.push_back(0x80 | 127);
        for (int i = 7; i >= 0; --i) {
            frame.push_back((len >> (i * 8)) & 0xFF);
        }
    }

    uint8_t mask[4] = { 0x12, 0x34, 0x56, 0x78 };
    frame.insert(frame.end(), mask, mask + 4);

    for (size_t i = 0; i < len; ++i) {
        frame.push_back(message[i] ^ mask[i % 4]);
    }
    return frame;
}

static bool parseWebSocketFrame(const std::vector<uint8_t>& input, std::string& output_message, size_t& parsed_offset, bool& close_received) {
    if (input.size() - parsed_offset < 2) return false;
    size_t offset = parsed_offset;

    uint8_t byte0 = input[offset];
    uint8_t byte1 = input[offset + 1];
    uint8_t opcode = byte0 & 0x0F;
    bool mask = (byte1 & 0x80) != 0;
    size_t len = byte1 & 0x7F;

    offset += 2;
    if (len == 126) {
        if (input.size() - offset < 2) return false;
        len = (input[offset] << 8) | input[offset + 1];
        offset += 2;
    } else if (len == 127) {
        if (input.size() - offset < 8) return false;
        len = 0;
        for (int i = 0; i < 8; ++i) {
            len = (len << 8) | input[offset + i];
        }
        offset += 8;
    }

    uint8_t mask_key[4] = {0};
    if (mask) {
        if (input.size() - offset < 4) return false;
        std::copy(input.begin() + offset, input.begin() + offset + 4, mask_key);
        offset += 4;
    }

    if (input.size() - offset < len) return false;

    std::vector<uint8_t> payload(input.begin() + offset, input.begin() + offset + len);
    offset += len;

    if (mask) {
        for (size_t i = 0; i < len; ++i) {
            payload[i] ^= mask_key[i % 4];
        }
    }

    parsed_offset = offset;

    if (opcode == 8) {
        close_received = true;
        return true;
    }

    if (opcode == 1 || opcode == 2) {
        output_message = std::string(payload.begin(), payload.end());
        return true;
    }

    return true; 
}

void WebsocketSession::do_read() {
    auto self(shared_from_this());
    if (m_ssl) {
        m_ssl->async_read_some(m_streambuf.prepare(16384),
            [self](const asio::error_code& ec, size_t bytes) {
                self->m_streambuf.commit(bytes);
                self->on_read(ec, bytes);
            });
    } else {
        m_socket.async_read_some(m_streambuf.prepare(16384),
            [self](const asio::error_code& ec, size_t bytes) {
                self->m_streambuf.commit(bytes);
                self->on_read(ec, bytes);
            });
    }
}

void WebsocketSession::on_read(const asio::error_code& ec, size_t bytes_transferred) {
    if (m_result->canceled)
        return onError("canceled");
    if (ec)
        return onError("read error", ec.message());
    if (m_closed)
        return;

    m_timer.expires_after(std::chrono::seconds(m_timeout));
    m_timer.async_wait(std::bind(&WebsocketSession::onTimeout, shared_from_this(), std::placeholders::_1));

    if (m_streambuf.size() > 0) {
        const uint8_t* data = asio::buffer_cast<const uint8_t*>(m_streambuf.data());
        m_receiveBuffer.insert(m_receiveBuffer.end(), data, data + m_streambuf.size());
        m_streambuf.consume(m_streambuf.size());
    }

    std::string message;
    bool close_received = false;
    while (parseWebSocketFrame(m_receiveBuffer, message, m_parsedOffset, close_received)) {
        if (close_received) {
            close();
            return;
        }
        if (!message.empty()) {
            m_callback(WEBSOCKET_MESSAGE, message);
            message.clear();
        }
    }

    // Shrink the receive buffer to remove processed frames
    if (m_parsedOffset > 0) {
        m_receiveBuffer.erase(m_receiveBuffer.begin(), m_receiveBuffer.begin() + m_parsedOffset);
        m_parsedOffset = 0;
    }

    do_read();
}

void WebsocketSession::do_write() {
    if (m_closed || m_sendQueue.empty())
        return;

    auto frame_ptr = std::make_shared<std::vector<uint8_t>>(buildWebSocketFrame(m_sendQueue.front()));
    auto self(shared_from_this());

    if (m_ssl) {
        asio::async_write(*m_ssl, asio::buffer(*frame_ptr),
            [self, frame_ptr](const asio::error_code& ec, size_t) {
                self->on_write(ec);
            });
    } else {
        asio::async_write(m_socket, asio::buffer(*frame_ptr),
            [self, frame_ptr](const asio::error_code& ec, size_t) {
                self->on_write(ec);
            });
    }
}

void WebsocketSession::on_write(const asio::error_code& ec) {
    if (ec)
        return onError("send error", ec.message());

    m_sendQueue.pop();
    if (m_closed)
        return;

    if (!m_sendQueue.empty()) {
        do_write();
    }
}

void WebsocketSession::close() {
    m_timer.cancel();
    if (!m_closed) {
        m_closed = true;
        m_callback(WEBSOCKET_CLOSE, "");
    }
    asio::error_code ec;
    m_socket.close(ec);
}

void WebsocketSession::onTimeout(const asio::error_code& error)
{
    if(error)
        return;

    return onError("timeout");
}

void WebsocketSession::onError(const std::string& error, const std::string& details) {
    m_result->connected = false;
    if (!m_result->finished) {
        m_result->finished = true;
        std::string msg = error;
        if (!details.empty()) {
            msg += " (";
            msg += details;
            msg += ")";
        }
        if (!m_closed) {
            m_callback(WEBSOCKET_ERROR, msg);
        }
    }
    close();
}

#endif
