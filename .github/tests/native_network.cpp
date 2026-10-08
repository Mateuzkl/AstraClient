#include <framework/http/session.h>
#include <framework/http/websocket.h>
#include <framework/http/tls.h>
#include <cstdlib>
#include <iostream>

// Only UI logging is stubbed; networking and TLS are production implementations.
Logger g_logger;
void Logger::log(Fw::LogLevel, const std::string& message) { std::cerr << message << '\n'; }
static void check(bool value)
{
    if (!value)
        std::abort();
}

int main(int argc, char** argv)
{
    check(argc >= 4);
    const std::string mode = argv[1], url = argv[2];
    const bool expected = std::string(argv[3]) == "success";
    if (mode == "tls")
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
        if (argc > 4)
            curl_easy_setopt(handle, CURLOPT_CAINFO, argv[4]); // Test CA only; no system-store mutation.
        const auto code = curl_easy_perform(handle);
        std::cout << "TLS result: " << curl_easy_strerror(code) << std::endl;
        if (code != CURLE_OK)
            std::cerr << error << '\n';
        curl_easy_cleanup(handle);
        check((code == CURLE_OK) == expected);
        return 0;
    }
    asio::io_context service;
    auto result = std::make_shared<HttpResult>(url, 1);
    int finished = 0, messages = 0;
    const std::string websocketPayload = mode == "ws-large" ? std::string(128 * 1024, 'x') : "Astra WebSocket test";
    std::shared_ptr<HttpSession> http;
    std::shared_ptr<WebsocketSession> websocket;
    std::weak_ptr<CurlTransfer> lifetime;
    if (mode == "ws" || mode == "ws-large")
    {
        websocket = std::make_shared<WebsocketSession>(service, url, "Astra test", 5, result,
                                                       [&](WebsocketCallbackType type, std::string message)
                                                       {
                                                           if (type == WEBSOCKET_OPEN)
                                                               websocket->send(websocketPayload);
                                                           if (type == WEBSOCKET_MESSAGE)
                                                           {
                                                               check(message == websocketPayload);
                                                               ++messages;
                                                               websocket->close();
                                                           }
                                                           if (type == WEBSOCKET_CLOSE)
                                                               ++finished;
                                                       });
        lifetime = websocket;
        websocket->start();
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
        http = std::make_shared<HttpSession>(service, url, "Astra test", request, result,
                                             [&](HttpResult_ptr value)
                                             {
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
    service.run();
    check(finished == 1);
    check(result->error.empty() == expected);
    if ((mode == "ws" || mode == "ws-large") && expected)
        check(messages == 1);
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
    check(result->error == savedError && result->canceled == savedCanceled);
    check(finished == 1);
    http.reset();
    websocket.reset();
    check(lifetime.expired());
    std::cout << "Native " << mode << " status " << result->status << ": PASS\n";
}
