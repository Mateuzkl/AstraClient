#pragma once

#ifdef __EMSCRIPTEN__
#include "graphicalapplication.h"

// Browser startup-only, opt-in timings. No JS bridge when disabled.
class StartupTimer
{
public:
    explicit StartupTimer(const char* name) : m_name(name), m_enabled(g_app.isStartupDiagnosticsEnabled())
    {
        if (m_enabled)
            m_begin = std::chrono::steady_clock::now();
    }
    ~StartupTimer()
    {
        if (m_enabled)
            g_app.recordStartupPhase(m_name, std::chrono::duration<double, std::milli>(
                std::chrono::steady_clock::now() - m_begin).count());
    }
    StartupTimer(const StartupTimer&) = delete;
    StartupTimer& operator=(const StartupTimer&) = delete;

private:
    const char* m_name;
    bool m_enabled;
    std::chrono::steady_clock::time_point m_begin;
};
#endif
