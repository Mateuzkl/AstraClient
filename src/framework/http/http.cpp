#include <framework/global.h>
#include <framework/luaengine/luainterface.h>
#include <framework/util/crypt.h>
#include <framework/util/stats.h>
#include <framework/core/eventdispatcher.h>

#include "http.h"
#ifndef __EMSCRIPTEN__
#include "session.h"
#include "websocket.h"
#endif

Http g_http;

void Http::init() {
    m_working = true;
    m_thread = std::thread([this] {
        m_ios.run();
    });
}

void Http::terminate() {
    if (!m_working)
        return;
    m_working = false;
#ifndef __EMSCRIPTEN__
    if (m_thread.joinable()) {
        boost::asio::post(m_ios, [this] {
            for (auto& op : m_operations)
                op.second->canceled = true;

            std::vector<std::shared_ptr<WebsocketSession>> websockets;
            websockets.reserve(m_websockets.size());
            for (auto& ws : m_websockets)
                websockets.push_back(ws.second);
            for (auto& ws : websockets)
                ws->close();
        });
        m_guard.reset();
        m_thread.join();
    } else {
        for (auto& op : m_operations)
            op.second->canceled = true;
    }
    m_ios.stop();
    m_websockets.clear();
#else
    for (auto& op : m_operations)
        op.second->canceled = true;
    m_guard.reset();
    m_ios.stop();
    if (m_thread.joinable())
        m_thread.join();
#endif
    m_operations.clear();
}

int Http::get(const std::string& url, int timeout, const std::map<std::string, std::string>& headers) {
    if (!timeout) // lua is not working with default values
        timeout = DefaultTimeout;
    int operationId = m_operationId++;

    boost::asio::post(m_ios, [this, url, timeout, operationId, headers] {
        auto request = std::make_shared<HttpRequest>(url, headers, timeout);
        auto result = std::make_shared<HttpResult>(url, operationId);
        m_operations[operationId] = result;
#ifndef __EMSCRIPTEN__
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
#endif
    });

    return operationId;
}

int Http::post(const std::string& url, const std::string& data, int timeout, const std::map<std::string, std::string>& headers) {
    if (!timeout) // lua is not working with default values
        timeout = DefaultTimeout;
    if (data.empty()) {
        g_logger.error(stdext::format("Invalid post request for %s, empty data, use get instead", url));
        return -1;
    }

    int operationId = m_operationId++;
    boost::asio::post(m_ios, [this, url, data, timeout, operationId, headers] {
        auto request = std::make_shared<HttpRequest>(url, headers, data, timeout);
        auto result = std::make_shared<HttpResult>(url, operationId);
        m_operations[operationId] = result;
#ifndef __EMSCRIPTEN__
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
#endif
    });
    return operationId;
}

int Http::download(const std::string& url, std::string path, int timeout, const std::map<std::string, std::string>& headers) {
    if (!timeout) // lua is not working with default values
        timeout = DefaultTimeout;

    int operationId = m_operationId++;
    boost::asio::post(m_ios, [this, url, path, timeout, operationId, headers] {
        auto request = std::make_shared<HttpRequest>(url, headers, timeout);
        auto result = std::make_shared<HttpResult>(url, operationId);
        m_operations[operationId] = result;
#ifndef __EMSCRIPTEN__
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
#endif
    });
    return operationId;
}

int Http::ws(const std::string& url, int timeout)
{
    if (!timeout) // lua is not working with default values
        timeout = DefaultTimeout;
    int operationId = m_operationId++;

    boost::asio::post(m_ios, [this, url, timeout, operationId] {
        auto result = std::make_shared<HttpResult>();
        result->url = url;
        result->operationId = operationId;
        m_operations[operationId] = result;
#ifndef __EMSCRIPTEN__
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
#endif
    });

    return operationId;
}

bool Http::wsSend(int operationId, std::string message)
{
#ifndef __EMSCRIPTEN__
    boost::asio::post(m_ios, [this, operationId, message] {
        auto wit = m_websockets.find(operationId);
        if (wit == m_websockets.end()) {
            return;
        }
        wit->second->send(message);
    });
#endif
    return true;
}

bool Http::wsClose(int operationId)
{
    cancel(operationId);
    return true;
}


bool Http::cancel(int id) {
#ifndef __EMSCRIPTEN__
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
#endif
    return true;
}
