#ifndef ASTRACLIENT_MEMLEAKHISTORY_H
#define ASTRACLIENT_MEMLEAKHISTORY_H

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <optional>

// Bounded observations, not proof of a leak. Timestamps are monotonic milliseconds.
class MemLeakHistory
{
  public:
    struct Sample
    {
        int64_t process, lua, timestamp;
    };
    bool add(int64_t process, int64_t lua, int64_t timestamp)
    {
        if (process < 0 || lua < 0 || (!m_samples.empty() && timestamp <= m_samples.back().timestamp))
            return false;
        m_samples.push_back({process, lua, timestamp});
        if (m_samples.size() > 120)
            m_samples.pop_front();
        return true;
    }
    void clear()
    {
        m_samples.clear();
        m_lastAlert.reset();
        m_alertBaseline.reset();
    }
    size_t size() const { return m_samples.size(); }
    int64_t delta() const { return size() < 2 ? 0 : m_samples.back().process - m_samples.front().process; }
    int64_t span() const { return size() < 2 ? 0 : m_samples.back().timestamp - m_samples.front().timestamp; }
    double bytesPerSecond() const { return span() > 0 ? double(delta()) * 1000 / span() : 0; }
    int64_t alertGrowth() const
    {
        if (size() < 2)
            return 0;
        // Do not report the same jump again while it remains in the rolling window.
        const auto baseline = std::max(m_samples.front().process, m_alertBaseline.value_or(m_samples.front().process));
        return m_samples.back().process - baseline;
    }
    void setThreshold(int64_t bytes) { m_threshold = std::max<int64_t>(0, bytes); }
    int64_t threshold() const { return m_threshold; }
    void setCooldown(int milliseconds) { m_cooldown = std::max(0, milliseconds); }
    int cooldown() const { return m_cooldown; }
    bool checkAlert()
    {
        if (size() < 10 || alertGrowth() <= m_threshold)
            return false;
        const auto now = m_samples.back().timestamp;
        if (m_lastAlert && now - *m_lastAlert < m_cooldown)
            return false;
        m_lastAlert = now;
        m_alertBaseline = m_samples.back().process;
        return true;
    }
    void clearAlert()
    {
        // Acknowledge observed growth without resetting the cooldown or history.
        if (!m_samples.empty())
            m_alertBaseline = m_samples.back().process;
    }

  private:
    std::deque<Sample> m_samples;
    std::optional<int64_t> m_lastAlert;
    std::optional<int64_t> m_alertBaseline;
    int64_t m_threshold = 10 * 1024 * 1024;
    int m_cooldown = 30000;
};
#endif
