#include <framework/global.h>
#include "proxy.h"
#include <framework/stdext/stdext.h>

ProxyManager g_proxy;

#ifndef __EMSCRIPTEN__

void ProxyManager::init()
{
    if (m_working)
        return;
    m_working = true;
    m_thread = std::thread([&] {
        m_io.run();
    });
}

void ProxyManager::terminate()
{
    if (!m_working)
        return;
    m_working = false;
    clear();
    m_guard.reset();
    if (m_thread.joinable())
        m_thread.join();
    m_io.stop();
}

void ProxyManager::clear()
{
    for (auto& session_weak : m_sessions) {
        if (auto session = session_weak.lock()) {
            session->terminate();
        }
    }
    m_sessions.clear();
    for (auto& proxy_weak : m_proxies) {
        if (auto proxy = proxy_weak.lock()) {
            proxy->terminate();
        }
    }
    m_proxies.clear();
}

bool ProxyManager::isActive()
{
    return m_proxies.size() > 0;
}

void ProxyManager::addProxy(const std::string& host, uint16_t port, int priority)
{
    for (auto& proxy_weak : m_proxies) {
        if (auto proxy = proxy_weak.lock()) {
            if (proxy->getHost() == host && proxy->getPort() == port) {
                return; // already exist
            }
        }
    }

    auto proxy = std::make_shared<Proxy>(m_io, host, port, priority);
    proxy->start();
    m_proxies.push_back(proxy);
}

void ProxyManager::addExtendedProxy(const std::string& host, uint16_t port, uint16_t destinationPort, int priority)
{
    for (auto& proxy_weak : m_proxies) {
        if (auto proxy = proxy_weak.lock()) {
            if (proxy->getHost() == host && proxy->getPort() == port && proxy->getDestinationPort() == destinationPort) {
                return; // already exist
            }
        }
    }

    auto proxy = std::make_shared<Proxy>(m_io, host, port, destinationPort, priority);
    proxy->start();
    m_proxies.push_back(proxy);
}

void ProxyManager::removeProxy(const std::string& host, uint16_t port)
{
    for (auto it = m_proxies.begin(); it != m_proxies.end(); ) {
        if (auto proxy = it->lock()) {
            if (proxy->getHost() == host && proxy->getPort() == port) {
                proxy->terminate();
                it = m_proxies.erase(it);
            } else {
                ++it;
            }
            continue;
        }
        it = m_proxies.erase(it);
    }
}

uint32_t ProxyManager::addSession(uint16_t port, std::function<void(ProxyPacketPtr)> recvCallback, std::function<void(boost::system::error_code)> disconnectCallback)
{
    VALIDATE(recvCallback && disconnectCallback);
    auto session = std::make_shared<Session>(m_io, port, recvCallback, disconnectCallback);
    session->start(m_maxActiveProxies);
    m_sessions.push_back(session);
    return session->getId();
}

void ProxyManager::removeExtendedProxy(const std::string& host, uint16_t port, uint16_t destinationPort)
{
    for (auto it = m_proxies.begin(); it != m_proxies.end(); ) {
        if (auto proxy = it->lock()) {
            if (proxy->getHost() == host && proxy->getPort() == port && proxy->getDestinationPort() == destinationPort) {
                proxy->terminate();
                it = m_proxies.erase(it);
            }
            else {
                ++it;
            }
            continue;
        }
        it = m_proxies.erase(it);
    }
}

void ProxyManager::removeSession(uint32_t sessionId)
{
    if (!m_working)
        return;
    for (auto it = m_sessions.begin(); it != m_sessions.end(); ) {
        if (auto session = it->lock()) {
            if (session->getId() == sessionId) {
                session->terminate();
                it = m_sessions.erase(it);
            } else {
                ++it;
            }
            continue;
        }
        it = m_sessions.erase(it);
    }
}

void ProxyManager::send(uint32_t sessionId, ProxyPacketPtr packet)
{
    SessionPtr session = nullptr;
    for (auto& session_weak : m_sessions) {
        if (auto tsession = session_weak.lock()) {
            if (tsession->getId() == sessionId) {
                session = tsession;
                break;
            }
        }
    }

    if (!session)
        return;

    session->onPacket(packet);
}

std::map<std::string, uint32_t> ProxyManager::getProxies()
{
    std::map<std::string, uint32_t> ret;
    for (auto& proxy_weak : m_proxies) {
        if (auto proxy = proxy_weak.lock()) {
            ret[proxy->getHost() + ":" + std::to_string(proxy->getPort())] = proxy->getRealPing();
        }
    }
    return ret;
}

std::map<std::string, std::string> ProxyManager::getProxiesDebugInfo()
{
    std::map<std::string, std::string> ret;
    for (auto& proxy_weak : m_proxies) {
        if (auto proxy = proxy_weak.lock()) {
            ret[proxy->getHost() + ":" + std::to_string(proxy->getPort())] = proxy->getDebugInfo();
        }
    }
    return ret;
}

int ProxyManager::getPing()
{
    uint32_t ret = 0;
    for (auto& proxy_weak : m_proxies) {
        if (auto proxy = proxy_weak.lock()) {
            if ((proxy->getRealPing() < ret || ret == 0) && proxy->getRealPing() > 0)
                ret = proxy->getRealPing();
        }
    }
    return ret;
}

#else

void ProxyManager::init()
{
    // Native TCP proxy sessions are unavailable in a browser. Keeping a
    // no-op manager preserves the Lua/API surface without starting a thread.
    m_working = true;
}

void ProxyManager::terminate()
{
    clear();
    m_working = false;
}

void ProxyManager::clear()
{
    m_sessions.clear();
    m_proxies.clear();
}

bool ProxyManager::isActive() { return false; }
void ProxyManager::addProxy(const std::string&, uint16_t, int) {}
void ProxyManager::addExtendedProxy(const std::string&, uint16_t, uint16_t, int) {}
void ProxyManager::removeProxy(const std::string&, uint16_t) {}
void ProxyManager::removeExtendedProxy(const std::string&, uint16_t, uint16_t) {}
uint32_t ProxyManager::addSession(uint16_t, std::function<void(ProxyPacketPtr)>, std::function<void(boost::system::error_code)>) { return 0; }
void ProxyManager::removeSession(uint32_t) {}
void ProxyManager::send(uint32_t, ProxyPacketPtr) {}
std::map<std::string, uint32_t> ProxyManager::getProxies() { return {}; }
std::map<std::string, std::string> ProxyManager::getProxiesDebugInfo() { return {}; }
int ProxyManager::getPing() { return 0; }

#endif
