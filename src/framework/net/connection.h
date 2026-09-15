/*
 * Copyright (c) 2010-2017 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#ifndef CONNECTION_H
#define CONNECTION_H

#include "declarations.h"
#include <framework/luaengine/luaobject.h>
#include <framework/core/timer.h>
#include <framework/core/declarations.h>

#ifdef __EMSCRIPTEN__
#include <emscripten/websocket.h>
#endif

class Connection : public LuaObject
{
    typedef std::function<void(const boost::system::error_code&)> ErrorCallback;
    typedef std::function<void(uint8*, uint32)> RecvCallback;

    static constexpr int32_t READ_TIMEOUT = 30;
    static constexpr int32_t WRITE_TIMEOUT = 30;

    enum {
        SEND_BUFFER_SIZE = 327680,
        RECV_BUFFER_SIZE = 327680
    };

public:
    Connection();
    ~Connection();

    static void poll();
    static void terminate();

    void connect(const std::string& host, uint16 port, const std::function<void()>& connectCallback);
    void close();

    void write(uint8* buffer, size_t size);
    void read(uint32 bytes, const RecvCallback& callback);
    void read_until(const std::string& what, const RecvCallback& callback);
    void read_some(const RecvCallback& callback);

    void setErrorCallback(const ErrorCallback& errorCallback) { m_errorCallback = errorCallback; }

    int getIp();
    boost::system::error_code getError() { return m_error; }
    bool isConnecting() { return m_connecting; }
    bool isConnected() { return m_connected; }
    ticks_t getElapsedTicksSinceLastRead() { return m_connected ? m_activityTimer.elapsed_millis() : -1; }

    ConnectionPtr asConnection() { return static_self_cast<Connection>(); }

protected:
#ifndef __EMSCRIPTEN__
    void internal_connect(asio::ip::basic_resolver<asio::ip::tcp>::iterator endpointIterator);
    void internal_write();
    void onResolve(const boost::system::error_code& error, asio::ip::tcp::resolver::iterator endpointIterator);
    void onConnect(const boost::system::error_code& error);
    void onCanWrite(const boost::system::error_code& error);
    void onWrite(const boost::system::error_code& error, size_t writeSize, std::shared_ptr<asio::streambuf> outputStream);
    void onRecv(const boost::system::error_code& error, size_t recvSize);
    void onTimeout(const boost::system::error_code& error);
    void handleError(const boost::system::error_code& error);
#else
    enum class WebReadMode {
        None,
        Exact,
        Until,
        Some
    };

    static EM_BOOL onWebSocketOpen(int eventType, const EmscriptenWebSocketOpenEvent* event, void* userData);
    static EM_BOOL onWebSocketError(int eventType, const EmscriptenWebSocketErrorEvent* event, void* userData);
    static EM_BOOL onWebSocketClose(int eventType, const EmscriptenWebSocketCloseEvent* event, void* userData);
    static EM_BOOL onWebSocketMessage(int eventType, const EmscriptenWebSocketMessageEvent* event, void* userData);

    void handleWebOpen(uint64_t generation);
    void handleWebFailure(uint64_t generation, const boost::system::error_code& error);
    void handleWebClose(uint64_t generation, uint16_t code, std::string reason);
    void handleWebMessage(uint64_t generation, std::vector<uint8> bytes, bool textFrame);
    void trySatisfyWebRead();
    void checkWebTimeout();
    void compactWebInput();
    void handleError(const boost::system::error_code& error);
#endif

    std::function<void()> m_connectCallback;
    ErrorCallback m_errorCallback;
    RecvCallback m_recvCallback;

#ifndef __EMSCRIPTEN__
    asio::steady_timer m_readTimer;
    asio::steady_timer m_writeTimer;
    asio::steady_timer m_delayedWriteTimer;
    asio::ip::tcp::resolver m_resolver;
    asio::ip::tcp::socket m_socket;

    static std::list<std::shared_ptr<asio::streambuf>> m_outputStreams;
    std::shared_ptr<asio::streambuf> m_outputStream;
    asio::streambuf m_inputStream;
#else
    EMSCRIPTEN_WEBSOCKET_T m_websocket = 0;
    uint64_t m_webGeneration = 0;
    std::vector<uint8> m_webInput;
    size_t m_webInputOffset = 0;
    WebReadMode m_webReadMode = WebReadMode::None;
    uint32 m_webReadBytes = 0;
    std::string m_webReadUntil;
    bool m_webConnectTimerActive = false;
    bool m_webReadTimerActive = false;
    stdext::timer m_webConnectTimer;
    stdext::timer m_webReadTimer;
#endif
    bool m_connected;
    bool m_connecting;
    boost::system::error_code m_error;
    stdext::timer m_activityTimer;

    friend class Server;
};

#endif
