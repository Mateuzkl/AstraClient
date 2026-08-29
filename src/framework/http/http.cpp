#include <framework/global.h>
#include <framework/luaengine/luainterface.h>
#include <framework/util/crypt.h>
#include <framework/util/stats.h>
#include <framework/core/eventdispatcher.h>

#include <chrono>
#include <array>
#include <cstring>
#include <future>
#include <limits>

#include "http.h"
#ifndef __EMSCRIPTEN__
#include "session.h"
#include "websocket.h"
#else
#include <emscripten/emscripten.h>

namespace {
constexpr size_t BROWSER_MAX_URL = 16384;

int resolveAstraBrowserUrl(const char* value, int websocket, char* output, int outputSize)
{
    return MAIN_THREAD_EM_ASM_INT({
      try {
        const original = UTF8ToString($0);
        const resolver = $1 ? Module.astraResolveGenericWebSocketUrl : Module.astraResolveHttpUrl;
        const resolved = resolver ? resolver(original) : original;
        const url = new URL(resolved, window.location.href).href;
        if (window.location.protocol === 'https:' &&
            ((!$1 && url.startsWith('http:')) || ($1 && url.startsWith('ws:')))) {
            Module.astraLastEndpointError = 'Mixed content blocked for endpoint: ' + url;
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
    }, value, websocket, output, outputSize);
}

std::map<std::string, std::string> browserResponseHeaders(emscripten_fetch_t* fetch)
{
    std::map<std::string, std::string> result;
    const size_t length = emscripten_fetch_get_response_headers_length(fetch);
    if (length == 0)
        return result;
    std::vector<char> raw(length + 1, 0);
    emscripten_fetch_get_response_headers(fetch, raw.data(), raw.size());
    char** headers = emscripten_fetch_unpack_response_headers(raw.data());
    if (!headers)
        return result;
    for (size_t i = 0; headers[i] && headers[i + 1]; i += 2)
        result[headers[i]] = headers[i + 1];
    emscripten_fetch_free_unpacked_response_headers(headers);
    return result;
}
}
#endif

Http g_http;

void Http::init() {
    m_working = true;
#ifdef __EMSCRIPTEN__
    m_ioRunning = false;
#else
    m_ioRunning = true;
    try {
        m_thread = std::thread([this] {
            m_ios.run();
            m_ioRunning = false;
        });
    } catch (...) {
        m_ioRunning = false;
        m_working = false;
        throw;
    }
#endif
}

void Http::terminate() {
    if (!m_working)
        return;
    m_working = false;
#ifndef __EMSCRIPTEN__
    bool stopBeforeJoin = false;
    if (m_thread.joinable() && m_ioRunning) {
        auto shutdownPromise = std::make_shared<std::promise<void>>();
        auto shutdownComplete = shutdownPromise->get_future();
        try {
            boost::asio::post(m_ios, [this, shutdownPromise] {
                try {
                    std::vector<std::shared_ptr<HttpSession>> sessions;
                    sessions.reserve(m_operations.size());
                    for (auto& op : m_operations) {
                        op.second->canceled = true;
                        if (auto session = op.second->session.lock())
                            sessions.push_back(std::move(session));
                    }

                    std::vector<std::shared_ptr<WebsocketSession>> websockets;
                    websockets.reserve(m_websockets.size());
                    for (auto& ws : m_websockets)
                        websockets.push_back(ws.second);

                    for (auto& session : sessions) {
                        try {
                            session->cancel();
                        } catch (...) {
                        }
                    }
                    for (auto& ws : websockets) {
                        try {
                            ws->close();
                        } catch (...) {
                        }
                    }
                } catch (...) {
                }
                shutdownPromise->set_value();
            });
        } catch (...) {
            shutdownPromise->set_value();
            stopBeforeJoin = true;
        }
        if (shutdownComplete.wait_for(std::chrono::seconds(ShutdownTimeout)) != std::future_status::ready)
            stopBeforeJoin = true;
    } else {
        for (auto& op : m_operations)
            op.second->canceled = true;
        stopBeforeJoin = true;
    }
    m_guard.reset();
    if (stopBeforeJoin)
        m_ios.stop();
    if (m_thread.joinable())
        m_thread.join();
    m_websockets.clear();
#else
    while (!m_browserWebsockets.empty())
        closeBrowserWebSocket(m_browserWebsockets.begin()->first, false);
    while (!m_browserFetches.empty()) {
        auto it = m_browserFetches.begin();
        auto operation = std::move(it->second);
        if (operation.result)
            operation.result->canceled = true;
        m_browserFetches.erase(it);
        if (operation.fetch)
            emscripten_fetch_close(operation.fetch);
    }
    m_guard.reset();
    m_ios.stop();
#endif
    m_operations.clear();
}

int Http::get(const std::string& url, int timeout, const std::map<std::string, std::string>& headers) {
    if (!timeout) // lua is not working with default values
        timeout = DefaultTimeout;
#ifdef __EMSCRIPTEN__
    return startBrowserFetch(BrowserFetchKind::Get, url, {}, {}, timeout, headers);
#else
    int operationId = m_operationId++;

    boost::asio::post(m_ios, [this, url, timeout, operationId, headers] {
        auto request = std::make_shared<HttpRequest>(url, headers, timeout);
        auto result = std::make_shared<HttpResult>(url, operationId);
        m_operations[operationId] = result;
        auto session = std::make_shared<HttpSession>(m_ios, url, m_userAgent, request, result, [this, operationId](HttpResult_ptr result) {
            bool finished = result->finished;
            g_dispatcher.addEventEx("Http::onGet", [result, finished]() {
                if (!finished) {
                    g_lua.callGlobalField("g_http", "onGetProgress", result->operationId, result->url, result->progress);
                    return;
                }
                g_lua.callGlobalField("g_http", "onGet", result->operationId, result->url, result->error, result);
            });
            if (finished) {
                m_operations.erase(operationId);
            }
        });
        session->start();
    });

    return operationId;
#endif
}

int Http::post(const std::string& url, const std::string& data, int timeout, const std::map<std::string, std::string>& headers) {
    if (!timeout) // lua is not working with default values
        timeout = DefaultTimeout;
    if (data.empty()) {
        g_logger.error(stdext::format("Invalid post request for %s, empty data, use get instead", url));
        return -1;
    }

#ifdef __EMSCRIPTEN__
    return startBrowserFetch(BrowserFetchKind::Post, url, data, {}, timeout, headers);
#else
    int operationId = m_operationId++;
    boost::asio::post(m_ios, [this, url, data, timeout, operationId, headers] {
        auto request = std::make_shared<HttpRequest>(url, headers, data, timeout);
        auto result = std::make_shared<HttpResult>(url, operationId);
        m_operations[operationId] = result;
        auto session = std::make_shared<HttpSession>(m_ios, url, m_userAgent, request, result, [this, operationId](HttpResult_ptr result) {
            bool finished = result->finished;
            g_dispatcher.addEventEx("Http::onPost", [result, finished]() {
                if (!finished) {
                    g_lua.callGlobalField("g_http", "onPostProgress", result->operationId, result->url, result->progress);
                    return;
                }
                g_lua.callGlobalField("g_http", "onPost", result->operationId, result->url, result->error, result);
            });
            if (finished) {
                m_operations.erase(operationId);
            }
        });
        session->start();
    });
    return operationId;
#endif
}

int Http::download(const std::string& url, std::string path, int timeout, const std::map<std::string, std::string>& headers) {
    if (!timeout) // lua is not working with default values
        timeout = DefaultTimeout;

#ifdef __EMSCRIPTEN__
    return startBrowserFetch(BrowserFetchKind::Download, url, {}, std::move(path), timeout, headers);
#else
    int operationId = m_operationId++;
    boost::asio::post(m_ios, [this, url, path, timeout, operationId, headers] {
        auto request = std::make_shared<HttpRequest>(url, headers, timeout);
        auto result = std::make_shared<HttpResult>(url, operationId);
        m_operations[operationId] = result;
        auto session = std::make_shared<HttpSession>(m_ios, url, m_userAgent, request, result, [this, path, operationId](HttpResult_ptr result) {
            m_speed = ((result->size) * 10) / (1 + stdext::micros() - m_lastSpeedUpdate);
            m_lastSpeedUpdate = stdext::micros();

            if (!result->finished) {
                int speed = m_speed;
                g_dispatcher.addEventEx("Http::onDownloadProgress", [result, speed]() {
                    g_lua.callGlobalField("g_http", "onDownloadProgress", result->operationId, result->url, result->progress, speed);
                });
                return;
            }
            std::string checksum = g_crypt.crc32(std::string(result->body.begin(), result->body.end()), false);
            g_dispatcher.addEventEx("Http::onDownload", [this, result, path, checksum]() {
                if (result->error.empty()) {
                    if (!path.empty() && path[0] == '/')
                        m_downloads[path.substr(1)] = result;
                    else
                        m_downloads[path] = result;
                }
                g_lua.callGlobalField("g_http", "onDownload", result->operationId, result->url, result->error, path, checksum, result);
            });
            m_operations.erase(operationId);
        });
        session->start();
    });
    return operationId;
#endif
}

int Http::ws(const std::string& url, int timeout)
{
    if (!timeout) // lua is not working with default values
        timeout = DefaultTimeout;
    int operationId = m_operationId++;

#ifdef __EMSCRIPTEN__
    std::array<char, BROWSER_MAX_URL> urlBuffer{};
    const int resolvedLength = resolveAstraBrowserUrl(url.c_str(), 1, urlBuffer.data(), static_cast<int>(urlBuffer.size()));
    auto result = std::make_shared<HttpResult>(url, operationId);
    m_operations[operationId] = result;
    if (resolvedLength < 0 || resolvedLength > static_cast<int>(urlBuffer.size()) ||
        !emscripten_websocket_is_supported()) {
        result->finished = true;
        result->error = resolvedLength < 0 ? "Invalid or insecure WebSocket URL" : "WebSocket is not supported by this browser";
        m_operations.erase(operationId);
        g_dispatcher.addEventEx("Http::wsError", [result] {
            g_lua.callGlobalField("g_http", "onWsError", result->operationId, result->error);
            g_lua.callGlobalField("g_http", "onWsClose", result->operationId, result->error);
        });
        return operationId;
    }

    EmscriptenWebSocketCreateAttributes attributes{};
    attributes.url = urlBuffer.data();
    attributes.protocols = nullptr;
    attributes.createOnMainThread = EM_TRUE;
    const EMSCRIPTEN_WEBSOCKET_T socket = emscripten_websocket_new(&attributes);
    if (socket <= 0) {
        result->finished = true;
        result->error = "Unable to create WebSocket";
        m_operations.erase(operationId);
        g_dispatcher.addEventEx("Http::wsError", [result] {
            g_lua.callGlobalField("g_http", "onWsError", result->operationId, result->error);
            g_lua.callGlobalField("g_http", "onWsClose", result->operationId, result->error);
        });
        return operationId;
    }

    m_browserWebsockets[operationId] = { socket, result };
    m_browserWebSocketIds[socket] = operationId;
    emscripten_websocket_set_onopen_callback(socket, nullptr, &Http::onBrowserWebSocketOpen);
    emscripten_websocket_set_onerror_callback(socket, nullptr, &Http::onBrowserWebSocketError);
    emscripten_websocket_set_onclose_callback(socket, nullptr, &Http::onBrowserWebSocketClose);
    emscripten_websocket_set_onmessage_callback(socket, nullptr, &Http::onBrowserWebSocketMessage);
    emscripten_async_call(&Http::onBrowserWebSocketTimeout, reinterpret_cast<void*>(static_cast<intptr_t>(operationId)), timeout * 1000);
    return operationId;
#else
    boost::asio::post(m_ios, [this, url, timeout, operationId] {
        auto result = std::make_shared<HttpResult>();
        result->url = url;
        result->operationId = operationId;
        m_operations[operationId] = result;
        auto session = std::make_shared<WebsocketSession>(m_ios, url, m_userAgent, timeout, result, [this, result](WebsocketCallbackType type, std::string message) {
            g_dispatcher.addEventEx("Http::ws", [result, type, message]() {
                if (type == WEBSOCKET_OPEN) {
                    g_lua.callGlobalField("g_http", "onWsOpen", result->operationId, message);
                } else if (type == WEBSOCKET_MESSAGE) {
                    g_lua.callGlobalField("g_http", "onWsMessage", result->operationId, message);
                } else if (type == WEBSOCKET_CLOSE) {
                    g_lua.callGlobalField("g_http", "onWsClose", result->operationId, message);
                } else if (type == WEBSOCKET_ERROR) {
                    g_lua.callGlobalField("g_http", "onWsError", result->operationId, message);
                }
            });
            if (type == WEBSOCKET_CLOSE) {
                m_websockets.erase(result->operationId);
                m_operations.erase(result->operationId);
            }
        });
        m_websockets[result->operationId] = session;
        session->start();
    });

    return operationId;
#endif
}

bool Http::wsSend(int operationId, std::string message)
{
#ifdef __EMSCRIPTEN__
    const auto it = m_browserWebsockets.find(operationId);
    if (it == m_browserWebsockets.end() || !it->second.result->connected)
        return false;
    return emscripten_websocket_send_utf8_text(it->second.socket, message.c_str()) == EMSCRIPTEN_RESULT_SUCCESS;
#else
    boost::asio::post(m_ios, [this, operationId, message] {
        auto wit = m_websockets.find(operationId);
        if (wit == m_websockets.end()) {
            return;
        }
        wit->second->send(message);
    });
    return true;
#endif
}

bool Http::wsClose(int operationId)
{
    cancel(operationId);
    return true;
}


bool Http::cancel(int id) {
#ifdef __EMSCRIPTEN__
    if (m_browserWebsockets.find(id) != m_browserWebsockets.end()) {
        closeBrowserWebSocket(id, true);
        return true;
    }
    const auto it = m_browserFetches.find(id);
    if (it == m_browserFetches.end())
        return false;
    auto operation = std::move(it->second);
    m_browserFetches.erase(it);
    m_operations.erase(id);
    if (operation.result)
        operation.result->canceled = true;
    if (operation.fetch)
        emscripten_fetch_close(operation.fetch);
    return true;
#else
    boost::asio::post(m_ios, [this, id] {
        auto wit = m_websockets.find(id);
        if (wit != m_websockets.end()) {
            wit->second->close();
        }
        auto it = m_operations.find(id);
        if (it == m_operations.end())
            return;
        if (it->second->canceled)
            return;
        it->second->canceled = true;
        if (auto session = it->second->session.lock()) {
            session->cancel();
        }
    });
    return true;
#endif
}

#ifdef __EMSCRIPTEN__

int Http::startBrowserFetch(BrowserFetchKind kind, const std::string& url, const std::string& data,
                            std::string path, int timeout, const std::map<std::string, std::string>& headers)
{
    const int operationId = m_operationId++;
    auto result = std::make_shared<HttpResult>(url, operationId);
    m_operations[operationId] = result;

    std::array<char, BROWSER_MAX_URL> urlBuffer{};
    const int resolvedLength = resolveAstraBrowserUrl(url.c_str(), 0, urlBuffer.data(), static_cast<int>(urlBuffer.size()));
    if (resolvedLength < 0 || resolvedLength > static_cast<int>(urlBuffer.size())) {
        result->finished = true;
        result->error = "Invalid or insecure HTTP URL";
        m_operations.erase(operationId);
        g_dispatcher.addEventEx("Http::invalidUrl", [result, kind, path = std::move(path)] {
            if (kind == BrowserFetchKind::Get)
                g_lua.callGlobalField("g_http", "onGet", result->operationId, result->url, result->error, result);
            else if (kind == BrowserFetchKind::Post)
                g_lua.callGlobalField("g_http", "onPost", result->operationId, result->url, result->error, result);
            else
                g_lua.callGlobalField("g_http", "onDownload", result->operationId, result->url, result->error, path, std::string(), result);
        });
        return operationId;
    }

    auto [it, inserted] = m_browserFetches.emplace(operationId, BrowserFetchOperation{});
    auto& operation = it->second;
    operation.kind = kind;
    operation.result = result;
    operation.path = std::move(path);
    operation.requestBody = data;
    operation.headerStorage.reserve(headers.size() * 2);
    for (const auto& [name, value] : headers) {
        operation.headerStorage.push_back(name);
        operation.headerStorage.push_back(value);
    }
    operation.headerPointers.reserve(operation.headerStorage.size() + 1);
    for (const auto& value : operation.headerStorage)
        operation.headerPointers.push_back(value.c_str());
    operation.headerPointers.push_back(nullptr);

    emscripten_fetch_attr_t attributes;
    emscripten_fetch_attr_init(&attributes);
    std::strncpy(attributes.requestMethod, kind == BrowserFetchKind::Post ? "POST" : "GET", sizeof(attributes.requestMethod) - 1);
    attributes.attributes = EMSCRIPTEN_FETCH_LOAD_TO_MEMORY | EMSCRIPTEN_FETCH_REPLACE;
    attributes.timeoutMSecs = static_cast<uint32_t>(std::max(1, timeout)) * 1000U;
    attributes.userData = reinterpret_cast<void*>(static_cast<intptr_t>(operationId));
    attributes.onsuccess = &Http::onBrowserFetchSuccess;
    attributes.onerror = &Http::onBrowserFetchError;
    attributes.onprogress = &Http::onBrowserFetchProgress;
    attributes.requestHeaders = operation.headerPointers.data();
    if (!operation.requestBody.empty()) {
        attributes.requestData = operation.requestBody.data();
        attributes.requestDataSize = operation.requestBody.size();
    }

    operation.fetch = emscripten_fetch(&attributes, urlBuffer.data());
    if (!operation.fetch) {
        auto failed = std::move(operation);
        m_browserFetches.erase(it);
        m_operations.erase(operationId);
        result->finished = true;
        result->error = "Unable to start browser fetch";
        g_dispatcher.addEventEx("Http::fetchStartError", [result, kind, path = std::move(failed.path)] {
            if (kind == BrowserFetchKind::Get)
                g_lua.callGlobalField("g_http", "onGet", result->operationId, result->url, result->error, result);
            else if (kind == BrowserFetchKind::Post)
                g_lua.callGlobalField("g_http", "onPost", result->operationId, result->url, result->error, result);
            else
                g_lua.callGlobalField("g_http", "onDownload", result->operationId, result->url, result->error, path, std::string(), result);
        });
    }
    (void)inserted;
    return operationId;
}

void Http::onBrowserFetchSuccess(emscripten_fetch_t* fetch)
{
    g_http.finishBrowserFetch(fetch, true);
}

void Http::onBrowserFetchError(emscripten_fetch_t* fetch)
{
    g_http.finishBrowserFetch(fetch, false);
}

void Http::onBrowserFetchProgress(emscripten_fetch_t* fetch)
{
    g_http.reportBrowserFetchProgress(fetch);
}

void Http::reportBrowserFetchProgress(emscripten_fetch_t* fetch)
{
    if (!fetch)
        return;
    const int operationId = static_cast<int>(reinterpret_cast<intptr_t>(fetch->userData));
    const auto it = m_browserFetches.find(operationId);
    if (it == m_browserFetches.end() || !it->second.result || it->second.result->canceled)
        return;

    const auto result = it->second.result;
    result->connected = true;
    result->size = static_cast<int>(std::min<uint64_t>(fetch->totalBytes, std::numeric_limits<int>::max()));
    const int progress = fetch->totalBytes > 0
        ? static_cast<int>(std::min<uint64_t>(100, (fetch->numBytes * 100) / fetch->totalBytes))
        : 0;
    if (progress == result->progress)
        return;
    result->progress = progress;

    if (it->second.kind == BrowserFetchKind::Download) {
        const size_t now = stdext::micros();
        const size_t elapsed = now > m_lastSpeedUpdate ? now - m_lastSpeedUpdate : 1;
        m_speed = static_cast<int>(std::min<uint64_t>(std::numeric_limits<int>::max(), (fetch->numBytes * 1000000ULL) / elapsed));
        m_lastSpeedUpdate = now;
        const int speed = m_speed;
        g_dispatcher.addEventEx("Http::onDownloadProgress", [result, speed] {
            g_lua.callGlobalField("g_http", "onDownloadProgress", result->operationId, result->url, result->progress, speed);
        });
    } else {
        const auto kind = it->second.kind;
        g_dispatcher.addEventEx("Http::onProgress", [result, kind] {
            g_lua.callGlobalField("g_http", kind == BrowserFetchKind::Get ? "onGetProgress" : "onPostProgress",
                                  result->operationId, result->url, result->progress);
        });
    }
}

void Http::finishBrowserFetch(emscripten_fetch_t* fetch, bool succeeded)
{
    if (!fetch)
        return;
    const int operationId = static_cast<int>(reinterpret_cast<intptr_t>(fetch->userData));
    const auto it = m_browserFetches.find(operationId);
    if (it == m_browserFetches.end())
        return;

    auto operation = std::move(it->second);
    m_browserFetches.erase(it);
    m_operations.erase(operationId);
    const auto result = operation.result;
    if (!result) {
        emscripten_fetch_close(fetch);
        return;
    }

    result->connected = true;
    result->finished = true;
    result->status = fetch->status;
    result->size = static_cast<int>(std::min<uint64_t>(fetch->numBytes, std::numeric_limits<int>::max()));
    result->progress = 100;
    result->headers = browserResponseHeaders(fetch);
    if (fetch->data && fetch->numBytes > 0)
        result->body.assign(reinterpret_cast<const uint8_t*>(fetch->data), reinterpret_cast<const uint8_t*>(fetch->data) + fetch->numBytes);
    if (!succeeded || result->status < 200 || result->status >= 300) {
        result->error = result->status > 0
            ? stdext::format("HTTP error %d %s", result->status, fetch->statusText)
            : stdext::format("Browser fetch failed: %s", fetch->statusText);
    }

    emscripten_fetch_close(fetch);

    if (operation.kind == BrowserFetchKind::Download) {
        const std::string checksum = g_crypt.crc32(std::string(result->body.begin(), result->body.end()), false);
        g_dispatcher.addEventEx("Http::onDownload", [this, result, path = std::move(operation.path), checksum] {
            if (result->error.empty()) {
                if (!path.empty() && path[0] == '/')
                    m_downloads[path.substr(1)] = result;
                else
                    m_downloads[path] = result;
            }
            g_lua.callGlobalField("g_http", "onDownload", result->operationId, result->url, result->error, path, checksum, result);
        });
    } else {
        const auto kind = operation.kind;
        g_dispatcher.addEventEx(kind == BrowserFetchKind::Get ? "Http::onGet" : "Http::onPost", [result, kind] {
            g_lua.callGlobalField("g_http", kind == BrowserFetchKind::Get ? "onGet" : "onPost",
                                  result->operationId, result->url, result->error, result);
        });
    }
}

EM_BOOL Http::onBrowserWebSocketOpen(int, const EmscriptenWebSocketOpenEvent* event, void*)
{
    const auto idIt = g_http.m_browserWebSocketIds.find(event->socket);
    if (idIt == g_http.m_browserWebSocketIds.end())
        return EM_TRUE;
    const auto operationIt = g_http.m_browserWebsockets.find(idIt->second);
    if (operationIt == g_http.m_browserWebsockets.end())
        return EM_TRUE;
    const auto result = operationIt->second.result;
    result->connected = true;
    g_dispatcher.addEventEx("Http::wsOpen", [result] {
        g_lua.callGlobalField("g_http", "onWsOpen", result->operationId, std::string());
    });
    return EM_TRUE;
}

EM_BOOL Http::onBrowserWebSocketError(int, const EmscriptenWebSocketErrorEvent* event, void*)
{
    const auto idIt = g_http.m_browserWebSocketIds.find(event->socket);
    if (idIt == g_http.m_browserWebSocketIds.end())
        return EM_TRUE;
    const auto operationIt = g_http.m_browserWebsockets.find(idIt->second);
    if (operationIt == g_http.m_browserWebsockets.end())
        return EM_TRUE;
    const auto result = operationIt->second.result;
    result->error = "Browser WebSocket error";
    g_dispatcher.addEventEx("Http::wsError", [result] {
        g_lua.callGlobalField("g_http", "onWsError", result->operationId, result->error);
    });
    return EM_TRUE;
}

EM_BOOL Http::onBrowserWebSocketMessage(int, const EmscriptenWebSocketMessageEvent* event, void*)
{
    const auto idIt = g_http.m_browserWebSocketIds.find(event->socket);
    if (idIt == g_http.m_browserWebSocketIds.end())
        return EM_TRUE;
    const int operationId = idIt->second;
    std::string message;
    if (event->data && event->numBytes > 0)
        message.assign(reinterpret_cast<const char*>(event->data), event->numBytes);
    g_dispatcher.addEventEx("Http::wsMessage", [operationId, message = std::move(message)] {
        g_lua.callGlobalField("g_http", "onWsMessage", operationId, message);
    });
    return EM_TRUE;
}

EM_BOOL Http::onBrowserWebSocketClose(int, const EmscriptenWebSocketCloseEvent* event, void*)
{
    const auto idIt = g_http.m_browserWebSocketIds.find(event->socket);
    if (idIt == g_http.m_browserWebSocketIds.end())
        return EM_TRUE;
    const int operationId = idIt->second;
    const std::string reason = event->reason;
    const auto operationIt = g_http.m_browserWebsockets.find(operationId);
    if (operationIt == g_http.m_browserWebsockets.end())
        return EM_TRUE;
    auto operation = std::move(operationIt->second);
    g_http.m_browserWebsockets.erase(operationIt);
    g_http.m_browserWebSocketIds.erase(idIt);
    g_http.m_operations.erase(operationId);
    operation.result->connected = false;
    operation.result->finished = true;
    emscripten_websocket_delete(operation.socket);
    g_dispatcher.addEventEx("Http::wsClose", [operationId, reason] {
        g_lua.callGlobalField("g_http", "onWsClose", operationId, reason);
    });
    return EM_TRUE;
}

void Http::onBrowserWebSocketTimeout(void* userData)
{
    const int operationId = static_cast<int>(reinterpret_cast<intptr_t>(userData));
    const auto it = g_http.m_browserWebsockets.find(operationId);
    if (it == g_http.m_browserWebsockets.end() || it->second.result->connected)
        return;
    const auto result = it->second.result;
    result->error = "WebSocket connection timeout";
    g_dispatcher.addEventEx("Http::wsTimeout", [result] {
        g_lua.callGlobalField("g_http", "onWsError", result->operationId, result->error);
    });
    g_http.closeBrowserWebSocket(operationId, true);
}

void Http::closeBrowserWebSocket(int operationId, bool notify)
{
    const auto it = m_browserWebsockets.find(operationId);
    if (it == m_browserWebsockets.end())
        return;
    auto operation = std::move(it->second);
    m_browserWebsockets.erase(it);
    m_browserWebSocketIds.erase(operation.socket);
    m_operations.erase(operationId);
    operation.result->connected = false;
    operation.result->finished = true;
    operation.result->canceled = true;
    emscripten_websocket_set_onopen_callback(operation.socket, nullptr, nullptr);
    emscripten_websocket_set_onerror_callback(operation.socket, nullptr, nullptr);
    emscripten_websocket_set_onclose_callback(operation.socket, nullptr, nullptr);
    emscripten_websocket_set_onmessage_callback(operation.socket, nullptr, nullptr);
    unsigned short readyState = 0;
    if (emscripten_websocket_get_ready_state(operation.socket, &readyState) == EMSCRIPTEN_RESULT_SUCCESS && readyState < 2)
        emscripten_websocket_close(operation.socket, 1000, "client disconnect");
    emscripten_websocket_delete(operation.socket);
    if (notify) {
        g_dispatcher.addEventEx("Http::wsClose", [operationId] {
            g_lua.callGlobalField("g_http", "onWsClose", operationId, std::string());
        });
    }
}

#endif
