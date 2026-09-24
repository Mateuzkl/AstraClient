#ifndef FRAMELIMITPOLICY_H
#define FRAMELIMITPOLICY_H

#include <algorithm>
#include <atomic>

enum class WindowFrameState {
    Foreground,
    Background,
    Minimized
};

class FrameLimitPolicy
{
public:
    static constexpr int VSyncFallbackFps = 100;

    void setForegroundLimit(int fps) { m_foregroundLimit = std::clamp(fps, 0, 1000); }
    void setBackgroundLimit(int fps) { m_backgroundLimit = std::clamp(fps, 1, 1000); }
    void setMinimizedLimit(int fps) { m_minimizedLimit = std::clamp(fps, 1, 1000); }
    void setUnlimitedForeground(bool enabled) { m_unlimitedForeground = enabled; }

    int getForegroundLimit() const { return m_foregroundLimit.load(); }
    int getBackgroundLimit() const { return m_backgroundLimit.load(); }
    int getMinimizedLimit() const { return m_minimizedLimit.load(); }
    bool isUnlimitedForeground() const { return m_unlimitedForeground.load(); }

    int getLimit(WindowFrameState state, bool vsyncRequested, bool vsyncApplied) const
    {
        if (state == WindowFrameState::Minimized)
            return getMinimizedLimit();
        if (state == WindowFrameState::Background)
            return getBackgroundLimit();

        const int configuredLimit = isUnlimitedForeground() ? 0 : getForegroundLimit();
        // V-Sync normally paces presentation itself. Keep a software fallback
        // when the selected backend cannot apply the requested swap interval.
        if (vsyncRequested && !vsyncApplied)
            return configuredLimit > 0 ? std::min(configuredLimit, VSyncFallbackFps) : VSyncFallbackFps;
        return configuredLimit;
    }

private:
    std::atomic_int m_foregroundLimit{200};
    std::atomic_int m_backgroundLimit{30};
    std::atomic_int m_minimizedLimit{5};
    std::atomic_bool m_unlimitedForeground{true};
};

#endif
