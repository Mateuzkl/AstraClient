#include "adaptativeframecounter.h"
#include <algorithm>

bool AdaptativeFrameCounter::update()
{
    const auto maxFps = m_targetFps == 0 ? m_maxFps : std::max<uint16_t>(m_maxFps, m_targetFps);
    if (maxFps > 0) {
        const int32_t sleepPeriod = static_cast<int32_t>(getMaxPeriod(maxFps)) - 1000 - static_cast<int32_t>(m_timer.elapsed_micros());
        if (sleepPeriod > 0)
            stdext::microsleep(std::min<int32_t>(sleepPeriod, 1000000)); // max 1s
    }

    m_timer.restart();
    ++m_fpsCount;

    if (m_fps == m_fpsCount)
        return false;

    const uint32_t tickCount = stdext::millis();
    if (tickCount - m_interval <= 1000)
        return false;

    m_fps = m_fpsCount;
    m_fpsCount = 0;
    m_interval = tickCount;
    return true;
}
