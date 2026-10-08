#ifndef  HTTP_H
#define HTTP_H

#include <framework/global.h>
#include <atomic>
#include "result.h"

#ifdef __EMSCRIPTEN__
#include <emscripten/fetch.h>
#include <emscripten/websocket.h>
#include <framework/net/browsermessagebudget.h>
#include <mutex>
#endif

class WebsocketSession;

class Http {
public:
    Http() : m_ios(), m_guard(asio::make_work_guard(m_ios)) {}

    void init();
    void terminate();
#ifdef __EMSCRIPTEN__
    // Entrega no dispatcher; dados ja copiados antes de liberar buffers do JS.
    void completeBrowserPost(int id, int status, std::string body, std::string headers, std::string error);
#endif

    static constexpr int DefaultTimeout = 5;

    int get(const std::string& url, int timeout = DefaultTimeout, const std::map<std::string, std::string>& headers = {});
    int post(const std::string& url, const std::string& data, int timeout = DefaultTimeout, const std::map<std::string, std::string>& headers = {});
    int download(const std::string& url, std::string path, int timeout = DefaultTimeout, const std::map<std::string, std::string>& headers = {});
    int ws(const std::string& url, int timeout = 5);
    bool wsSend(int operationId, std::string message);
    bool wsClose(int operationId);

    bool cancel(int id);

    const std::map<std::string, HttpResult_ptr>& downloads() {
        return m_downloads;
    }
    void clearDownloads() {
        m_downloads.clear();
    }

    // diagnostics: m_downloads is a process-lifetime cache holding the full body
    // of every downloaded file, and nothing currently calls clearDownloads().
    // Expose its footprint so the growth can be measured before deciding on an
    // eviction policy.
    size_t getDownloadCount() const {
        return m_downloads.size();
    }
    size_t getDownloadBytes() const {
        size_t total = 0;
        for (const auto& it : m_downloads) {
            if (it.second)
                total += it.second->body.size();
        }
        return total;
    }
    HttpResult_ptr getFile(std::string path) {
        if (!path.empty() && path[0] == '/')
            path = path.substr(1);
        auto it = m_downloads.find(path);
        if (it == m_downloads.end())
            return nullptr;
        return it->second;
    }

    void setUserAgent(const std::string& userAgent)
    {
        m_userAgent = userAgent;
    }

private:
    static constexpr int ShutdownTimeout = 5;

    bool m_working = false;
    int m_operationId = 1;
    int m_speed = 0;
    size_t m_lastSpeedUpdate = 0;
    std::thread m_thread;
    std::atomic_bool m_ioRunning{ false };
    asio::io_context m_ios;
    asio::executor_work_guard<asio::io_context::executor_type> m_guard;
    std::map<int, HttpResult_ptr> m_operations;
#ifndef __EMSCRIPTEN__
    std::map<int, std::shared_ptr<WebsocketSession>> m_websockets;
#else
    enum class BrowserFetchKind { Get, Post, Download };

    struct BrowserFetchOperation {
        BrowserFetchKind kind = BrowserFetchKind::Get;
        emscripten_fetch_t *fetch = nullptr;
        HttpResult_ptr result;
        std::string path;
        std::string requestBody;
        std::vector<std::string> headerStorage;
        std::vector<const char *> headerPointers;
    };

    struct BrowserWebSocketOperation {
        EMSCRIPTEN_WEBSOCKET_T socket = 0;
        HttpResult_ptr result;
    };

    int startBrowserFetch(BrowserFetchKind kind, const std::string &url, const std::string &data, std::string path,
                          int timeout, const std::map<std::string, std::string> &headers);
    void finishBrowserFetch(emscripten_fetch_t *fetch, bool succeeded);
    void reportBrowserFetchProgress(emscripten_fetch_t *fetch);
    static void onBrowserFetchSuccess(emscripten_fetch_t *fetch);
    static void onBrowserFetchError(emscripten_fetch_t *fetch);
    static void onBrowserFetchProgress(emscripten_fetch_t *fetch);
    static EM_BOOL onBrowserWebSocketOpen(int eventType, const EmscriptenWebSocketOpenEvent *event, void *userData);
    static EM_BOOL onBrowserWebSocketError(int eventType, const EmscriptenWebSocketErrorEvent *event, void *userData);
    static EM_BOOL onBrowserWebSocketClose(int eventType, const EmscriptenWebSocketCloseEvent *event, void *userData);
    static EM_BOOL onBrowserWebSocketMessage(int eventType, const EmscriptenWebSocketMessageEvent *event,
                                             void *userData);
    static void onBrowserWebSocketTimeout(void *userData);
    void closeBrowserWebSocket(int operationId, bool notify);

    std::map<int, BrowserFetchOperation> m_browserFetches;
    std::map<int, BrowserWebSocketOperation> m_browserWebsockets;
    // Only this callback handoff registry is shared with the browser thread.
    std::mutex m_browserMessageMutex;
    std::map<int, std::shared_ptr<astra_browser::MessageBudget>> m_browserMessageBudgets;
#endif
    std::map<std::string, HttpResult_ptr> m_downloads;
    std::string m_userAgent = "Mozilla/5.0";
};

extern Http g_http;

#endif // ! HTTP_H
