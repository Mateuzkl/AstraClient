#pragma once
#ifndef __EMSCRIPTEN__
#include "curltransfer.h"
#include "result.h"
class HttpSession : public CurlTransfer
{
  public:
    HttpSession(asio::io_context& service, const std::string& url, const std::string& agent, HttpRequest_ptr request,
                HttpResult_ptr result, HttpResult_cb callback)
        : CurlTransfer(service), m_url(url), m_agent(agent), m_request(std::move(request)), m_result(std::move(result)),
          m_callback(std::move(callback))
    {
    }
    void start();
    void cancel();

  private:
    static size_t receive(char* data, size_t size, size_t count, void* context);
    static size_t receiveHeader(char* data, size_t size, size_t count, void* context);
    static int progress(void* context, curl_off_t total, curl_off_t now, curl_off_t, curl_off_t);
    void completed(CURLcode code) override;
    void progressed() override;
    std::string m_url, m_agent;
    HttpRequest_ptr m_request;
    HttpResult_ptr m_result;
    HttpResult_cb m_callback;
    size_t m_headerBytes = 0;
    bool m_progressPending = false;
};
#endif
