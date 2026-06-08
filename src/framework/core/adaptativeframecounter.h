#pragma once

#include <framework/global.h>

class AdaptativeFrameCounter
{
public:
    AdaptativeFrameCounter() : m_interval(stdext::millis()) {}

    void init() { m_timer.restart(); }
    bool update();

    uint16_t getFps() const { return m_fps; }
    uint16_t getMaxFps() const { return m_maxFps; }
    uint16_t getTargetFps() const { return m_targetFps; }

    void setMaxFps(const uint16_t max) { m_maxFps = max; }
    void setTargetFps(const uint16_t target) { if (m_targetFps != target) m_targetFps = target; }
    void resetTargetFps() { m_targetFps = 0; }

    float getPercent() const {
        const float maxFps = static_cast<float>(std::max<uint16_t>(m_targetFps, m_maxFps));
        if (maxFps == 0) return 0.f;
        return ((maxFps - m_fps) / maxFps) * 100.f;
    }

private:
    static uint32_t getMaxPeriod(uint16_t fps) { return fps > 0 ? 1000000u / fps : 0u; }

    uint16_t m_maxFps{};
    uint16_t m_targetFps{ 60u };
    uint16_t m_fps{};
    uint16_t m_fpsCount{};
    uint32_t m_interval{};
    stdext::timer m_timer;
};
