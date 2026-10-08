#include <framework/http/session.h>
#include <framework/http/websocket.h>
#include <framework/http/tls.h>
#include <framework/http/redirectpolicy.h>
#include <cstdlib>
#include <iostream>
#ifdef WIN32
#include <psapi.h>
#endif

// Only UI logging is stubbed; networking and TLS are production implementations.
Logger g_logger;
void Logger::log(Fw::LogLevel, const std::string& message)
{
    std::cerr << message << '\n';
}
static void checked(bool value, const char* expression, int line)
{
    if (!value)
    {
        std::cerr << "Native networking check failed at line " << line << ": " << expression << '\n';
        std::abort();
    }
}
#define check(value) checked(static_cast<bool>(value), #value, __LINE__)

static void lifecycle(const std::string& base, int cycles)
{
    check(cycles >= 100 && cycles <= 1000);
    asio::io_context service;
#ifdef WIN32
    DWORD baselineHandles = 0;
    check(GetProcessHandleCount(GetCurrentProcess(), &baselineHandles));
#endif
    for (int cycle = 0; cycle < cycles; ++cycle)
    {
        service.restart();
        const int scenario = cycle % 7;
        const bool isWebsocket = scenario >= 3;
        const std::string url = isWebsocket ? "ws" + base.substr(4) + (scenario == 6 ? "/drop" : "/echo")
                                            : base + (scenario == 1 ? "/slow" : "/ok");
        auto result = std::make_shared<HttpResult>(url, cycle);
        std::shared_ptr<HttpSession> http;
        std::shared_ptr<WebsocketSession> websocket;
        std::weak_ptr<CurlTransfer> lifetime;
        int finished = 0, messages = 0, errors = 0;
        if (isWebsocket)
        {
            websocket = std::make_shared<WebsocketSession>(
                service, url, "Astra lifecycle", 5, result, [&](WebsocketCallbackType type, std::string message) {
                    check(finished == 0);
                    if (type == WEBSOCKET_OPEN)
                    {
                        if (scenario == 4)
                            websocket->close();
                        else
                            websocket->send("lifecycle");
                    }
                    else if (type == WEBSOCKET_MESSAGE)
                    {
                        check(scenario == 3 && message == "lifecycle");
                        ++messages;
                        websocket->close();
                    }
                    else if (type == WEBSOCKET_ERROR)
                    {
                        check(scenario == 6);
                        ++errors;
                        websocket->close();
                    }
                    else if (type == WEBSOCKET_CLOSE)
                    {
                        ++finished;
                        websocket.reset(); // Match Http's owner-map erasure inside the final callback.
                    }
                });
            lifetime = websocket;
            websocket->start();
            if (scenario == 5)
                websocket->close();
        }
        else
        {
            auto request = std::make_shared<HttpRequest>(url, 5);
            http = std::make_shared<HttpSession>(service, url, "Astra lifecycle", request, result,
                                                 [&](HttpResult_ptr value) {
                                                     check(finished == 0);
                                                     if (value->finished)
                                                     {
                                                         ++finished;
                                                         http.reset();
                                                     }
                                                     else if (scenario == 1 && value->progress > 0)
                                                         http->cancel();
                                                 });
            lifetime = http;
            http->start();
            if (scenario == 2)
                http->cancel();
        }
        service.run(); // Drain canceled waits/posts before inspecting ownership and handles.
        check(finished == 1 && messages == (scenario == 3 ? 1 : 0) && errors == (scenario == 6 ? 1 : 0));
        check(result->finished && result->error.empty() == (scenario != 1 && scenario != 2 && scenario != 6));
        check(!http && !websocket && lifetime.expired());
        if ((cycle + 1) % 100 == 0)
        {
#ifdef WIN32
            DWORD handles = 0;
            PROCESS_MEMORY_COUNTERS_EX memory{};
            memory.cb = sizeof(memory);
            check(GetProcessHandleCount(GetCurrentProcess(), &handles));
            check(K32GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&memory),
                                          sizeof(memory)));
            std::cout << "Lifecycle " << cycle + 1 << ": handles=" << handles << " (baseline=" << baselineHandles
                      << "), RSS=" << memory.WorkingSetSize << ", private=" << memory.PrivateUsage << std::endl;
            // Measure after warmup: Windows TLS/DNS/Asio can allocate process-lifetime handles on first use.
            if (cycle == 99)
                baselineHandles = handles;
            else
                check(handles <= baselineHandles + 16);
#endif
        }
    }
    std::cout << "Native lifecycle " << cycles << " cycles: PASS\n";
}

static void cancelBatch(const std::string& base)
{
    asio::io_context service;
    std::vector<std::shared_ptr<HttpSession>> requests;
    std::vector<std::shared_ptr<WebsocketSession>> websockets;
    std::vector<std::weak_ptr<CurlTransfer>> lifetimes;
    std::vector<HttpResult_ptr> results;
    std::vector<int> finished(100, 0);
    for (int i = 0; i < 100; ++i)
    {
        const std::string url = i % 2 ? "ws" + base.substr(4) + "/idle" : base + "/slow";
        auto result = std::make_shared<HttpResult>(url, i);
        results.push_back(result);
        if (i % 2)
        {
            auto session = std::make_shared<WebsocketSession>(
                service, url, "Astra batch", 5, result, [&, i](WebsocketCallbackType type, std::string) {
                    check(finished[i] == 0 && type != WEBSOCKET_ERROR && type != WEBSOCKET_MESSAGE);
                    if (type == WEBSOCKET_CLOSE)
                        ++finished[i];
                });
            lifetimes.push_back(session);
            websockets.push_back(session);
            session->start();
        }
        else
        {
            auto request = std::make_shared<HttpRequest>(url, 5);
            auto session = std::make_shared<HttpSession>(service, url, "Astra batch", request, result,
                                                         [&, i](HttpResult_ptr value) {
                                                             check(finished[i] == 0);
                                                             if (value->finished)
                                                                 ++finished[i];
                                                         });
            lifetimes.push_back(session);
            requests.push_back(session);
            session->start();
        }
    }
    // Cancel on the I/O executor with socket/timer completions already pending.
    asio::post(service, [&] {
        for (auto& session : requests)
            session->cancel();
        for (auto& session : websockets)
            session->close();
        requests.clear();
        websockets.clear();
    });
    service.run();
    for (int i = 0; i < 100; ++i)
        check(finished[i] == 1 && results[i]->finished && lifetimes[i].expired());
    std::cout << "Native cancellation batch: 100 final callbacks, all session owners released: PASS\n";
}

int main(int argc, char** argv)
{
    check(argc >= 4);
    const std::string mode = argv[1], url = argv[2];
    const bool expected = std::string(argv[3]) == "success";
    if (mode == "lifecycle")
    {
        lifecycle(url, argc > 4 ? std::stoi(argv[4]) : 200);
        return 0;
    }
    if (mode == "cancel-batch")
    {
        cancelBatch(url);
        return 0;
    }
    if (mode == "tls" || mode == "tls-get" || mode == "tls-post" || mode == "tls-ws")
    {
        check(curl_global_init(CURL_GLOBAL_DEFAULT) == CURLE_OK);
        auto* handle = curl_easy_init();
        check(handle);
        check(HttpTls::configure(handle) == CURLE_OK);
        char error[CURL_ERROR_SIZE] = {};
        curl_easy_setopt(handle, CURLOPT_ERRORBUFFER, error);
        curl_easy_setopt(handle, CURLOPT_URL, url.c_str());
        curl_easy_setopt(handle, CURLOPT_TIMEOUT, 10L);
        curl_easy_setopt(handle, CURLOPT_NOPROXY, "*");
        curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, +[](char*, size_t s, size_t n, void*) { return s * n; });
        if (mode == "tls-get" || mode == "tls-post")
        {
            check(HttpRedirectPolicy::configure(handle, url, mode == "tls-post") == CURLE_OK);
            if (mode == "tls-post")
                curl_easy_setopt(handle, CURLOPT_POSTFIELDS, "Astra HTTP test");
        }
        if (mode == "tls-ws")
            curl_easy_setopt(handle, CURLOPT_CONNECT_ONLY, 2L);
        if (argc > 4)
            curl_easy_setopt(handle, CURLOPT_CAINFO, argv[4]); // Test CA only; no system-store mutation.
        const auto code = curl_easy_perform(handle);
        std::cout << "TLS result: " << curl_easy_strerror(code) << std::endl;
        if (code != CURLE_OK)
            std::cerr << error << '\n';
        long status = 0;
        check(curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE, &status) == CURLE_OK);
        const bool accepted = code == CURLE_OK && !(mode == "tls-post" && HttpRedirectPolicy::isRedirect(status));
        check(accepted == expected);
        curl_easy_cleanup(handle);
        return 0;
    }
    asio::io_context service;
    auto result = std::make_shared<HttpResult>(url, 1);
    int finished = 0, messages = 0, errors = 0;
    asio::steady_timer websocketTimer(service);
    const std::string websocketPayload = mode == "ws-backpressure" ? std::string(8 * 1024 * 1024, 'x')
                                      : mode == "ws-large" ? std::string(128 * 1024, 'x') : "Astra WebSocket test";
    std::shared_ptr<HttpSession> http;
    std::shared_ptr<WebsocketSession> websocket;
    std::weak_ptr<CurlTransfer> lifetime;
    const bool isWebsocket = mode.compare(0, 2, "ws") == 0;
    if (isWebsocket)
    {
        websocket = std::make_shared<WebsocketSession>(
            service, url, "Astra test", mode == "ws-timeout" ? 1 : 5, result,
            [&](WebsocketCallbackType type, std::string message) {
                if (type == WEBSOCKET_OPEN)
                {
                    if (mode == "ws-close-open")
                    {
                        websocket->close();
                        return;
                    }
                    if (mode == "ws-send-limit")
                    {
                        websocket->send(std::string(16 * 1024 * 1024 + 1, 'x'));
                        return;
                    }
                    if (mode == "ws-idle" || mode == "ws-late")
                    {
                        websocketTimer.expires_after(std::chrono::milliseconds(mode == "ws-idle" ? 500 : 50));
                        websocketTimer.async_wait([&](const std::error_code& ec) {
                            if (!ec)
                            {
                                if (mode == "ws-idle")
                                    websocket->close();
                                else
                                    websocket->send(websocketPayload);
                            }
                        });
                    }
                    else if (mode != "ws-timeout")
                    {
                        websocket->send(websocketPayload);
                        if (mode == "ws-backpressure")
                            websocket->send(websocketPayload);
                    }
                }
                if (type == WEBSOCKET_MESSAGE)
                {
                    check(!result->finished);
                    if (mode == "ws-multiple" && messages == 0)
                        check(message.empty());
                    else
                        check(message == websocketPayload);
                    ++messages;
                    if ((mode != "ws-multiple" && mode != "ws-backpressure") ||
                        messages == (mode == "ws-multiple" ? 3 : 2))
                        websocket->close();
                }
                if (type == WEBSOCKET_ERROR)
                {
                    ++errors;
                    if (mode == "ws-close-error")
                        websocket->close();
                }
                if (type == WEBSOCKET_CLOSE)
                    ++finished;
            });
        lifetime = websocket;
        websocket->start();
        if (mode == "ws-cancel-handshake")
            websocket->close();
    }
    else
    {
        auto request = std::make_shared<HttpRequest>(url, 5);
        if (mode == "post")
        {
            request->body = "Astra HTTP test";
            request->headers["Content-Type"] = "text/plain";
        }
        if (mode == "bad-header")
            request->headers["X-Test"] = "injected\r\nHeader: value";
        http = std::make_shared<HttpSession>(service, url, "Astra test", request, result, [&](HttpResult_ptr value) {
            if (value->finished)
                ++finished;
            else if (mode == "cancel-progress" && value->progress > 0)
                http->cancel();
        });
        lifetime = http;
        http->start();
        if (mode == "cancel")
            http->cancel();
    }
    if (mode == "ws-idle")
    {
        size_t dispatched = 0;
        while (!finished)
        {
            check(service.run_one() == 1);
            ++dispatched;
        }
        check(dispatched < 20); // A fixed 10 ms poll would wake at least 50 times.
        std::cout << "Idle WebSocket: " << dispatched << " handlers including handshake/close over 500 ms\n";
    }
    service.run();
    if (mode == "ws-reconnect")
    {
        check(finished == 1 && messages == 1 && errors == 0 && result->error.empty());
        const auto previousLifetime = lifetime;
        websocket.reset();
        check(previousLifetime.expired());
        service.restart();
        result = std::make_shared<HttpResult>(url, 2);
        finished = messages = errors = 0;
        websocket = std::make_shared<WebsocketSession>(service, url, "Astra test", 5, result,
                                                       [&](WebsocketCallbackType type, std::string message) {
                                                           if (type == WEBSOCKET_OPEN)
                                                               websocket->send(websocketPayload);
                                                           if (type == WEBSOCKET_MESSAGE)
                                                           {
                                                               check(!result->finished && message == websocketPayload);
                                                               ++messages;
                                                               websocket->close();
                                                           }
                                                           if (type == WEBSOCKET_ERROR)
                                                               ++errors;
                                                           if (type == WEBSOCKET_CLOSE)
                                                               ++finished;
                                                       });
        lifetime = websocket;
        websocket->start();
        service.run();
    }
    check(finished == 1);
    if (!result->error.empty())
        std::cerr << "Transport result: " << result->error << '\n';
    check(result->error.empty() == expected);
    if (isWebsocket)
        check(errors == (expected ? 0 : 1));
    if (isWebsocket && expected)
        check(messages == (mode == "ws-idle" || mode == "ws-close-open" || mode == "ws-cancel-handshake" ? 0
                           : mode == "ws-multiple"                                                       ? 3
                           : mode == "ws-backpressure"                                                   ? 2
                                                                                                         : 1));
    if (mode == "post" && !expected && HttpRedirectPolicy::isRedirect(result->status))
        check(result->redirects == 0 && result->error == "POST redirect blocked; configure the final endpoint URL");
    if (mode == "post" && expected)
        check(std::string(result->body.begin(), result->body.end()) == "Astra HTTP test");
    if (mode == "get" && expected)
    {
        const auto body = std::string(result->body.begin(), result->body.end());
        check(body == "Astra HTTP test" || (result->status == 204 && body.empty()));
    }
    const auto savedError = result->error;
    const auto savedCanceled = result->canceled;
    if (http)
        http->cancel(); // Late/repeated cancellation must not mutate a completed result.
    if (websocket)
        websocket->close(); // Repeated close must not deliver another final callback.
    check(result->error == savedError && result->canceled == savedCanceled);
    check(finished == 1);
    http.reset();
    websocket.reset();
    check(lifetime.expired());
    std::cout << "Native " << mode << " status " << result->status << ": PASS\n";
}
