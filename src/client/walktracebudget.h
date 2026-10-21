#ifndef ASTRA_WALKTRACEBUDGET_H
#define ASTRA_WALKTRACEBUDGET_H
#include <cstdint>

// Diagnostics must not become a source of movement stalls themselves.
class WalkTraceBudget {
public:
    void beginFrame() { m_frameCount = 0; }
    bool allow(int64_t now)
    {
        if (!m_initialized || now < m_windowStart || now - m_windowStart >= 1000) {
            m_initialized = true;
            m_windowStart = now;
            m_windowCount = 0;
        }
        if (m_frameCount >= 8 || m_windowCount >= 32) return false;
        ++m_frameCount;
        ++m_windowCount;
        return true;
    }
private:
    int64_t m_windowStart = 0;
    unsigned m_windowCount = 0;
    unsigned m_frameCount = 0;
    bool m_initialized = false;
};
#endif
