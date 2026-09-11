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

#include "connection.h"

#include <framework/core/application.h>
#include <framework/core/eventdispatcher.h>
#include <boost/asio.hpp>
#include <framework/util/stats.h>
#include <framework/util/extras.h>
#include <chrono>

#ifdef __EMSCRIPTEN__
#include <emscripten/emscripten.h>
#include <mutex>
#include <unordered_map>
#endif

asio::io_service g_ioService;

#ifndef __EMSCRIPTEN__
std::list<std::shared_ptr<asio::streambuf>> Connection::m_outputStreams;

Connection::Connection() :
        m_readTimer(g_ioService),
        m_writeTimer(g_ioService),
        m_delayedWriteTimer(g_ioService),
        m_resolver(g_ioService),
        m_socket(g_ioService)
{
    m_connected = false;
    m_connecting = false;
}

Connection::~Connection()
{
    VALIDATE(!g_app.isTerminated());
    close();
}

void Connection::poll()
{
    AutoStat s(STATS_MAIN, "PollConnection");
    // reset must always be called prior to poll
    g_ioService.reset();
    g_ioService.poll();
}

void Connection::terminate()
{
    // Canceled Asio operations keep their shared handlers alive until the
    // completion queue is drained. Release them before service teardown.
    g_ioService.stop();
    g_ioService.reset();
    while (g_ioService.poll() != 0) {
    }
    g_ioService.stop();
    m_outputStreams.clear();
}

void Connection::close()
{
    if(!m_connected && !m_connecting) {
        // a connection built but never connected still holds whatever was
        // installed through setErrorCallback(), so release it here too
        m_connectCallback = nullptr;
        m_errorCallback = nullptr;
        m_recvCallback = nullptr;
        return;
    }

    // flush send data before disconnecting on clean connections
    if(m_connected && !m_error && m_outputStream)
        internal_write();

    m_connecting = false;
    m_connected = false;
    m_connectCallback = nullptr;
    m_errorCallback = nullptr;
    m_recvCallback = nullptr;

    m_resolver.cancel();
    m_readTimer.cancel();
    m_writeTimer.cancel();
    m_delayedWriteTimer.cancel();

    if(m_socket.is_open()) {
        boost::system::error_code ec;
        m_socket.shutdown(boost::asio::ip::tcp::socket::shutdown_both, ec);
        m_socket.close();
    }
}

void Connection::connect(const std::string& host, uint16 port, const std::function<void()>& connectCallback)
{
    m_connected = false;
    m_connecting = true;
    m_error.clear();
    m_connectCallback = connectCallback;

    asio::ip::tcp::resolver::query query(host, stdext::unsafe_cast<std::string>(port));
    m_resolver.async_resolve(query, std::bind(&Connection::onResolve, asConnection(), std::placeholders::_1, std::placeholders::_2));

    m_readTimer.cancel();
    m_readTimer.expires_from_now(std::chrono::seconds(READ_TIMEOUT));
    m_readTimer.async_wait(std::bind(&Connection::onTimeout, asConnection(), std::placeholders::_1));
}

void Connection::internal_connect(asio::ip::basic_resolver<asio::ip::tcp>::iterator endpointIterator)
{
    m_socket.async_connect(*endpointIterator, std::bind(&Connection::onConnect, asConnection(), std::placeholders::_1));

    m_readTimer.cancel();
    m_readTimer.expires_from_now(std::chrono::seconds(READ_TIMEOUT));
    m_readTimer.async_wait(std::bind(&Connection::onTimeout, asConnection(), std::placeholders::_1));
}

void Connection::write(uint8* buffer, size_t size)
{
    if(!m_connected)
        return;

    // we can't send the data right away, otherwise we could create tcp congestion
    if(!m_outputStream) {
        if(!m_outputStreams.empty()) {
            m_outputStream = m_outputStreams.front();
            m_outputStreams.pop_front();
        } else
            m_outputStream = std::make_shared<asio::streambuf>();

        m_delayedWriteTimer.cancel();
        m_delayedWriteTimer.expires_from_now(std::chrono::milliseconds(0));
        m_delayedWriteTimer.async_wait(std::bind(&Connection::onCanWrite, asConnection(), std::placeholders::_1));
    }

    std::ostream os(m_outputStream.get());
    os.write((const char*)buffer, size);
    os.flush();
}

void Connection::internal_write()
{
    if(!m_connected)
        return;

    std::shared_ptr<asio::streambuf> outputStream = m_outputStream;
    m_outputStream = nullptr;

    asio::async_write(m_socket,
                      *outputStream,
                      std::bind(&Connection::onWrite, asConnection(), std::placeholders::_1, std::placeholders::_2, outputStream));

    m_writeTimer.cancel();
    m_writeTimer.expires_from_now(std::chrono::seconds(WRITE_TIMEOUT));
    m_writeTimer.async_wait(std::bind(&Connection::onTimeout, asConnection(), std::placeholders::_1));
}

void Connection::read(uint32 bytes, const RecvCallback& callback)
{
    if(!m_connected)
        return;

    m_recvCallback = callback;

    asio::async_read(m_socket,
                     asio::mutable_buffer(m_inputStream.prepare(bytes)),
                     std::bind(&Connection::onRecv, asConnection(), std::placeholders::_1, std::placeholders::_2));

    m_readTimer.cancel();
    m_readTimer.expires_from_now(std::chrono::seconds(READ_TIMEOUT));
    m_readTimer.async_wait(std::bind(&Connection::onTimeout, asConnection(), std::placeholders::_1));
}

void Connection::read_until(const std::string& what, const RecvCallback& callback)
{
    if(!m_connected)
        return;

    m_recvCallback = callback;

    asio::async_read_until(m_socket,
                           m_inputStream,
                           what.c_str(),
                           std::bind(&Connection::onRecv, asConnection(), std::placeholders::_1, std::placeholders::_2));

    m_readTimer.cancel();
    m_readTimer.expires_from_now(std::chrono::seconds(READ_TIMEOUT));
    m_readTimer.async_wait(std::bind(&Connection::onTimeout, asConnection(), std::placeholders::_1));
}

void Connection::read_some(const RecvCallback& callback)
{
    if(!m_connected)
        return;

    m_recvCallback = callback;

    m_socket.async_read_some(asio::mutable_buffer(m_inputStream.prepare(RECV_BUFFER_SIZE)),
                             std::bind(&Connection::onRecv, asConnection(), std::placeholders::_1, std::placeholders::_2));

    m_readTimer.cancel();
    m_readTimer.expires_from_now(std::chrono::seconds(READ_TIMEOUT));
    m_readTimer.async_wait(std::bind(&Connection::onTimeout, asConnection(), std::placeholders::_1));
}

void Connection::onResolve(const boost::system::error_code& error, asio::ip::basic_resolver<asio::ip::tcp>::iterator endpointIterator)
{
    m_readTimer.cancel();

    if(error == asio::error::operation_aborted)
        return;

    if(!error)
        internal_connect(endpointIterator);
    else
        handleError(error);
}

void Connection::onConnect(const boost::system::error_code& error)
{
    m_readTimer.cancel();
    m_activityTimer.restart();

    if(error == asio::error::operation_aborted)
        return;

    if(!error) {
        m_connected = true;

        // disable nagle's algorithm, this make the game play smoother
        boost::asio::ip::tcp::no_delay option(true);
        m_socket.set_option(option);
        boost::system::error_code ecc;
        m_socket.set_option(boost::asio::socket_base::send_buffer_size(524288), ecc);
        m_socket.set_option(boost::asio::socket_base::receive_buffer_size(524288), ecc);

        if(m_connectCallback)
            m_connectCallback();
    } else
        handleError(error);

    m_connecting = false;
}

void Connection::onCanWrite(const boost::system::error_code& error)
{
    m_delayedWriteTimer.cancel();

    if(error == asio::error::operation_aborted)
        return;

    if(m_connected)
        internal_write();
}

void Connection::onWrite(const boost::system::error_code& error, size_t writeSize, std::shared_ptr<asio::streambuf> outputStream)
{
    m_writeTimer.cancel();

    if(error == asio::error::operation_aborted)
        return;

    // free output stream and store for using it again later
    outputStream->consume(outputStream->size());
    m_outputStreams.push_back(outputStream);

    if(m_connected && error)
        handleError(error);
}

void Connection::onRecv(const boost::system::error_code& error, size_t recvSize)
{
    m_readTimer.cancel();
    m_activityTimer.restart();

    if(error == asio::error::operation_aborted)
        return;

    if(m_connected) {
        if(!error) {
            if(m_recvCallback) {
                const char* header = boost::asio::buffer_cast<const char*>(m_inputStream.data());
                m_recvCallback((uint8*)header, recvSize);
            }
        } else
            handleError(error);
    }

    if(!error)
        m_inputStream.consume(recvSize);
}

void Connection::onTimeout(const boost::system::error_code& error)
{
    if(error == asio::error::operation_aborted)
        return;

    handleError(asio::error::timed_out);
}

void Connection::handleError(const boost::system::error_code& error)
{
    if(error == asio::error::operation_aborted)
        return;

    m_error = error;
    if(m_errorCallback)
        m_errorCallback(error);
    if(m_connected || m_connecting)
        close();
}

int Connection::getIp()
{
    boost::system::error_code error;
    const boost::asio::ip::tcp::endpoint ip = m_socket.remote_endpoint(error);
    if(!error)
        return boost::asio::detail::socket_ops::host_to_network_long(ip.address().to_v4().to_ulong());

    g_logger.error("Getting remote ip");
    return 0;
}
#else

#include <limits>

namespace {
constexpr size_t WEB_MAX_INPUT_BUFFER = 327680U * 4U;

std::mutex webConnectionsMutex;
std::unordered_map<EMSCRIPTEN_WEBSOCKET_T, std::weak_ptr<Connection>> webConnections;

ConnectionPtr findWebConnection(EMSCRIPTEN_WEBSOCKET_T socket)
{
    std::lock_guard<std::mutex> lock(webConnectionsMutex);
    const auto it = webConnections.find(socket);
    return it == webConnections.end() ? nullptr : it->second.lock();
}

void registerWebConnection(EMSCRIPTEN_WEBSOCKET_T socket, const ConnectionPtr& connection)
{
    std::lock_guard<std::mutex> lock(webConnectionsMutex);
    webConnections[socket] = connection;
}

void unregisterWebConnection(EMSCRIPTEN_WEBSOCKET_T socket)
{
    std::lock_guard<std::mutex> lock(webConnectionsMutex);
    webConnections.erase(socket);
}

std::vector<ConnectionPtr> snapshotWebConnections()
{
    std::vector<ConnectionPtr> result;
    std::lock_guard<std::mutex> lock(webConnectionsMutex);
    for (auto it = webConnections.begin(); it != webConnections.end();) {
        if (auto connection = it->second.lock()) {
            result.push_back(std::move(connection));
            ++it;
        } else {
            it = webConnections.erase(it);
        }
    }
    return result;
}

int resolveAstraWebSocketUrl(const char* host, int port, char* output, int outputSize)
{
    return MAIN_THREAD_EM_ASM_INT({
      try {
        const originalHost = UTF8ToString($0);
        const resolver = Module.astraResolveWebSocketUrl;
        const resolved = resolver ? resolver(originalHost, $1) : null;
        let url = resolved;
        if (!url) {
            const lowerHost = originalHost.toLowerCase();
            if (lowerHost.startsWith('ws:') || lowerHost.startsWith('wss:')) {
                url = originalHost;
            } else {
                const scheme = window.location.protocol === 'https:' ? 'wss' : 'ws';
                url = scheme + '://' + originalHost + ':' + $1 + '/';
            }
        }
        if (window.location.protocol === 'https:' && url.toLowerCase().startsWith('ws:')) {
            Module.astraLastEndpointError = 'Mixed content blocked: an HTTPS page must use a wss:// game endpoint.';
            return -1;
        }
        const required = lengthBytesUTF8(url) + 1;
        if (required > $3)
            return required;
        stringToUTF8(url, $2, $3);
        return required;
      } catch (error) {
        Module.astraLastEndpointError = error && error.message ? error.message : String(error);
        return -1;
      }
    }, host, port, output, outputSize);
}

void logAstraEndpointError()
{
    MAIN_THREAD_EM_ASM({
        console.error(Module.astraLastEndpointError || 'Invalid WebSocket endpoint configuration.');
    });
}
}

Connection::Connection() : m_connected(false), m_connecting(false) {}

Connection::~Connection()
{
    VALIDATE(!g_app.isTerminated());
    close();
}

void Connection::poll()
{
    AutoStat stat(STATS_MAIN, "PollConnection");
    g_ioService.reset();
    g_ioService.poll();
    for (const auto& connection : snapshotWebConnections())
        connection->checkWebTimeout();
}

void Connection::terminate()
{
    const auto connections = snapshotWebConnections();
    for (const auto& connection : connections)
        connection->close();
    {
        std::lock_guard<std::mutex> lock(webConnectionsMutex);
        webConnections.clear();
    }
    g_ioService.stop();
    g_ioService.reset();
    while (g_ioService.poll() != 0) {
    }
    g_ioService.stop();
}

void Connection::connect(const std::string& host, uint16 port, const std::function<void()>& connectCallback)
{
    if (m_connected || m_connecting || m_websocket > 0) {
        const auto errorCallback = m_errorCallback;
        close();
        m_errorCallback = errorCallback;
    }
    m_error.clear();
    m_connecting = true;
    m_connected = false;
    m_connectCallback = connectCallback;
    ++m_webGeneration;

    std::array<char, 2048> urlBuffer{};
    const int resolvedLength = resolveAstraWebSocketUrl(host.c_str(), port, urlBuffer.data(), static_cast<int>(urlBuffer.size()));
    if (resolvedLength < 0 || resolvedLength > static_cast<int>(urlBuffer.size())) {
        logAstraEndpointError();
        handleError(boost::system::errc::make_error_code(boost::system::errc::invalid_argument));
        return;
    }

    EmscriptenWebSocketCreateAttributes attributes{};
    attributes.url = urlBuffer.data();
    // Binary is the frame type, not a WebSocket subprotocol. Requiring a
    // "binary" subprotocol would make otherwise compatible bridges reject
    // the opening handshake when they do not echo that protocol.
    attributes.protocols = nullptr;
    attributes.createOnMainThread = EM_TRUE;
    m_websocket = emscripten_websocket_new(&attributes);
    if (m_websocket <= 0) {
        m_websocket = 0;
        handleError(boost::system::errc::make_error_code(boost::system::errc::network_unreachable));
        return;
    }

    registerWebConnection(m_websocket, asConnection());
    emscripten_websocket_set_onopen_callback(m_websocket, nullptr, &Connection::onWebSocketOpen);
    emscripten_websocket_set_onerror_callback(m_websocket, nullptr, &Connection::onWebSocketError);
    emscripten_websocket_set_onclose_callback(m_websocket, nullptr, &Connection::onWebSocketClose);
    emscripten_websocket_set_onmessage_callback(m_websocket, nullptr, &Connection::onWebSocketMessage);

    m_webConnectTimer.restart();
    m_webConnectTimerActive = true;
}

void Connection::close()
{
    ++m_webGeneration;
    const EMSCRIPTEN_WEBSOCKET_T socket = m_websocket;
    m_websocket = 0;
    m_connecting = false;
    m_connected = false;
    m_webConnectTimerActive = false;
    m_webReadTimerActive = false;
    m_webReadMode = WebReadMode::None;
    m_webReadBytes = 0;
    m_webReadUntil.clear();
    m_webInput.clear();
    m_webInputOffset = 0;
    m_connectCallback = nullptr;
    m_errorCallback = nullptr;
    m_recvCallback = nullptr;

    if (socket > 0) {
        unregisterWebConnection(socket);
        emscripten_websocket_set_onopen_callback(socket, nullptr, nullptr);
        emscripten_websocket_set_onerror_callback(socket, nullptr, nullptr);
        emscripten_websocket_set_onclose_callback(socket, nullptr, nullptr);
        emscripten_websocket_set_onmessage_callback(socket, nullptr, nullptr);
        EMSCRIPTEN_WEBSOCKET_T readySocket = socket;
        unsigned short readyState = 0;
        if (emscripten_websocket_get_ready_state(readySocket, &readyState) == EMSCRIPTEN_RESULT_SUCCESS &&
            readyState != 2 && readyState != 3) {
            emscripten_websocket_close(readySocket, 1000, "client disconnect");
        }
        emscripten_websocket_delete(readySocket);
    }
}

void Connection::write(uint8* buffer, size_t size)
{
    if (!m_connected || m_websocket <= 0 || !buffer || size == 0)
        return;
    if (size > static_cast<size_t>(std::numeric_limits<uint32_t>::max()) ||
        emscripten_websocket_send_binary(m_websocket, buffer, static_cast<uint32_t>(size)) != EMSCRIPTEN_RESULT_SUCCESS) {
        handleError(boost::system::errc::make_error_code(boost::system::errc::io_error));
    }
}

void Connection::read(uint32 bytes, const RecvCallback& callback)
{
    if (!m_connected || !callback)
        return;
    if (bytes == 0) {
        static uint8 emptyByte = 0;
        callback(&emptyByte, 0);
        return;
    }
    if (bytes > RECV_BUFFER_SIZE) {
        handleError(boost::system::errc::make_error_code(boost::system::errc::message_size));
        return;
    }
    if (m_webReadMode != WebReadMode::None) {
        handleError(boost::system::errc::make_error_code(boost::system::errc::operation_in_progress));
        return;
    }
    m_recvCallback = callback;
    m_webReadMode = WebReadMode::Exact;
    m_webReadBytes = bytes;
    m_webReadTimer.restart();
    m_webReadTimerActive = true;
    trySatisfyWebRead();
}

void Connection::read_until(const std::string& what, const RecvCallback& callback)
{
    if (!m_connected || !callback || what.empty())
        return;
    if (m_webReadMode != WebReadMode::None) {
        handleError(boost::system::errc::make_error_code(boost::system::errc::operation_in_progress));
        return;
    }
    m_recvCallback = callback;
    m_webReadMode = WebReadMode::Until;
    m_webReadUntil = what;
    m_webReadTimer.restart();
    m_webReadTimerActive = true;
    trySatisfyWebRead();
}

void Connection::read_some(const RecvCallback& callback)
{
    if (!m_connected || !callback)
        return;
    if (m_webReadMode != WebReadMode::None) {
        handleError(boost::system::errc::make_error_code(boost::system::errc::operation_in_progress));
        return;
    }
    m_recvCallback = callback;
    m_webReadMode = WebReadMode::Some;
    m_webReadTimer.restart();
    m_webReadTimerActive = true;
    trySatisfyWebRead();
}

EM_BOOL Connection::onWebSocketOpen(int, const EmscriptenWebSocketOpenEvent* event, void*)
{
    const EMSCRIPTEN_WEBSOCKET_T socket = event->socket;
    if (const auto connection = findWebConnection(socket)) {
        const uint64_t generation = connection->m_webGeneration;
        const std::weak_ptr<Connection> weak = connection;
        g_dispatcher.addEvent([weak, generation] {
            if (const auto self = weak.lock())
                self->handleWebOpen(generation);
        });
    }
    return EM_TRUE;
}

EM_BOOL Connection::onWebSocketError(int, const EmscriptenWebSocketErrorEvent* event, void*)
{
    const EMSCRIPTEN_WEBSOCKET_T socket = event->socket;
    if (const auto connection = findWebConnection(socket)) {
        const uint64_t generation = connection->m_webGeneration;
        const std::weak_ptr<Connection> weak = connection;
        g_dispatcher.addEvent([weak, generation] {
            if (const auto self = weak.lock())
                self->handleWebFailure(generation, boost::system::errc::make_error_code(boost::system::errc::connection_aborted));
        });
    }
    return EM_TRUE;
}

EM_BOOL Connection::onWebSocketClose(int, const EmscriptenWebSocketCloseEvent* event, void*)
{
    const EMSCRIPTEN_WEBSOCKET_T socket = event->socket;
    if (const auto connection = findWebConnection(socket)) {
        const uint64_t generation = connection->m_webGeneration;
        const uint16_t code = event->code;
        const std::string reason = event->reason;
        const std::weak_ptr<Connection> weak = connection;
        g_dispatcher.addEvent([weak, generation, code, reason] {
            if (const auto self = weak.lock())
                self->handleWebClose(generation, code, reason);
        });
    }
    return EM_TRUE;
}

EM_BOOL Connection::onWebSocketMessage(int, const EmscriptenWebSocketMessageEvent* event, void*)
{
    const EMSCRIPTEN_WEBSOCKET_T socket = event->socket;
    if (const auto connection = findWebConnection(socket)) {
        const uint64_t generation = connection->m_webGeneration;
        std::vector<uint8> bytes;
        if (event->numBytes > 0)
            bytes.assign(event->data, event->data + event->numBytes);
        const bool textFrame = event->isText;
        const std::weak_ptr<Connection> weak = connection;
        g_dispatcher.addEvent([weak, generation, bytes = std::move(bytes), textFrame]() mutable {
            if (const auto self = weak.lock())
                self->handleWebMessage(generation, std::move(bytes), textFrame);
        });
    }
    return EM_TRUE;
}

void Connection::handleWebOpen(uint64_t generation)
{
    if (generation != m_webGeneration || !m_connecting)
        return;
    m_connecting = false;
    m_connected = true;
    m_webConnectTimerActive = false;
    m_activityTimer.restart();
    const auto callback = m_connectCallback;
    if (callback)
        callback();
}

void Connection::handleWebFailure(uint64_t generation, const boost::system::error_code& error)
{
    if (generation != m_webGeneration)
        return;
    handleError(error);
}

void Connection::handleWebClose(uint64_t generation, uint16_t code, std::string reason)
{
    if (generation != m_webGeneration || (!m_connected && !m_connecting))
        return;
    if (code != 1000 && !reason.empty())
        g_logger.warning(stdext::format("Game WebSocket closed (%u): %s", code, reason));
    handleError(boost::asio::error::eof);
}

void Connection::handleWebMessage(uint64_t generation, std::vector<uint8> bytes, bool textFrame)
{
    if (generation != m_webGeneration || !m_connected)
        return;
    if (textFrame) {
        g_logger.warning("Ignoring a text WebSocket frame on the binary game transport.");
        return;
    }
    if (bytes.empty())
        return;
    compactWebInput();
    const size_t buffered = m_webInput.size() - m_webInputOffset;
    if (bytes.size() > WEB_MAX_INPUT_BUFFER || buffered > WEB_MAX_INPUT_BUFFER - bytes.size()) {
        handleError(boost::system::errc::make_error_code(boost::system::errc::message_size));
        return;
    }
    m_webInput.insert(m_webInput.end(), bytes.begin(), bytes.end());
    m_activityTimer.restart();
    trySatisfyWebRead();
}

void Connection::trySatisfyWebRead()
{
    if (!m_connected || m_webReadMode == WebReadMode::None || !m_recvCallback)
        return;
    const size_t available = m_webInput.size() - m_webInputOffset;
    size_t readSize = 0;
    if (m_webReadMode == WebReadMode::Exact) {
        if (available < m_webReadBytes)
            return;
        readSize = m_webReadBytes;
    } else if (m_webReadMode == WebReadMode::Some) {
        if (available == 0)
            return;
        readSize = std::min<size_t>(available, RECV_BUFFER_SIZE);
    } else if (m_webReadMode == WebReadMode::Until) {
        const auto begin = m_webInput.begin() + static_cast<std::ptrdiff_t>(m_webInputOffset);
        const auto found = std::search(begin, m_webInput.end(), m_webReadUntil.begin(), m_webReadUntil.end());
        if (found == m_webInput.end())
            return;
        readSize = static_cast<size_t>(std::distance(begin, found)) + m_webReadUntil.size();
    }

    std::vector<uint8> data(m_webInput.begin() + static_cast<std::ptrdiff_t>(m_webInputOffset),
                            m_webInput.begin() + static_cast<std::ptrdiff_t>(m_webInputOffset + readSize));
    m_webInputOffset += readSize;
    m_webReadMode = WebReadMode::None;
    m_webReadBytes = 0;
    m_webReadUntil.clear();
    m_webReadTimerActive = false;
    const auto callback = std::move(m_recvCallback);
    m_recvCallback = nullptr;
    m_activityTimer.restart();
    compactWebInput();
    callback(data.data(), static_cast<uint32>(data.size()));
}

void Connection::compactWebInput()
{
    if (m_webInputOffset == 0)
        return;
    if (m_webInputOffset == m_webInput.size()) {
        m_webInput.clear();
        m_webInputOffset = 0;
    } else if (m_webInputOffset >= m_webInput.size() / 2) {
        m_webInput.erase(m_webInput.begin(), m_webInput.begin() + static_cast<std::ptrdiff_t>(m_webInputOffset));
        m_webInputOffset = 0;
    }
}

void Connection::checkWebTimeout()
{
    if (m_webConnectTimerActive && m_webConnectTimer.elapsed_millis() >= READ_TIMEOUT * 1000) {
        m_webConnectTimerActive = false;
        handleError(boost::asio::error::timed_out);
        return;
    }
    if (m_webReadTimerActive && m_webReadTimer.elapsed_millis() >= READ_TIMEOUT * 1000) {
        m_webReadTimerActive = false;
        handleError(boost::asio::error::timed_out);
    }
}

void Connection::handleError(const boost::system::error_code& error)
{
    if (error == boost::asio::error::operation_aborted)
        return;
    m_error = error;
    const auto callback = m_errorCallback;
    if (callback)
        callback(error);
    if (m_connected || m_connecting)
        close();
}

int Connection::getIp() { return 0; }

#endif
