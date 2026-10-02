#ifndef ASTRA_PINGTRACKER_H
#define ASTRA_PINGTRACKER_H

#include <algorithm>
#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <optional>

// Game-owned, fixed-size state. Times are monotonic and stored in microseconds.
class PingTracker
{
  public:
    using Clock = std::chrono::steady_clock;
    using TimePoint = Clock::time_point;
    using Micros = std::chrono::microseconds;
    static constexpr size_t Capacity = 64;
    static constexpr auto Timeout = std::chrono::seconds(10);

    struct Stats
    {
        Micros latest{}, smoothed{}, jitter{};
        std::optional<uint32_t> serverQueueMicros;
        uint64_t sent = 0, received = 0, timedOut = 0;
        uint64_t unknownReplies = 0, duplicateReplies = 0;
    };

    explicit PingTracker(uint32_t lastId = 0) : m_lastId(lastId) {}

    void reset()
    {
        m_pending = {};
        m_answered = {};
        m_answeredIndex = 0;
        m_stats = {};
        ++m_generation;
        // Keep the ID sequence across sessions: late replies cannot match the
        // next session's first requests. The sequence is still owned by Game.
    }

    uint64_t generation() const { return m_generation; }
    bool isCurrentGeneration(uint64_t value) const { return value == m_generation; }
    const Stats &stats() const { return m_stats; }
    size_t pendingCount() const
    {
        return std::count_if(m_pending.begin(), m_pending.end(), [](const auto &p) { return p.has_value(); });
    }
    double lossPercent() const
    {
        const auto completed = m_stats.received + m_stats.timedOut;
        return completed ? 100.0 * m_stats.timedOut / completed : 0.0;
    }

    void expire(TimePoint now)
    {
        for (auto &request : m_pending)
        {
            if (request && now - request->sentAt >= Timeout)
            {
                request.reset();
                ++m_stats.timedOut;
            }
        }
    }

    std::optional<uint32_t> begin(TimePoint now)
    {
        expire(now);
        const auto slot = std::find_if(m_pending.begin(), m_pending.end(), [](const auto &p) { return !p; });
        if (slot == m_pending.end())
            return std::nullopt;
        do
        {
            if (++m_lastId == 0)
                ++m_lastId;
        } while (
            std::any_of(m_pending.begin(), m_pending.end(), [this](const auto &p) { return p && p->id == m_lastId; }));
        *slot = Request{m_lastId, now};
        ++m_stats.sent;
        return m_lastId;
    }

    bool consume(uint32_t id, TimePoint now, std::optional<uint32_t> queueMicros = std::nullopt)
    {
        expire(now);
        const auto it =
            std::find_if(m_pending.begin(), m_pending.end(), [id](const auto &p) { return p && p->id == id; });
        if (it == m_pending.end())
        {
            if (id != 0 && std::find(m_answered.begin(), m_answered.end(), id) != m_answered.end())
                ++m_stats.duplicateReplies;
            else
                ++m_stats.unknownReplies;
            return false;
        }
        const auto rtt = std::max(Micros::zero(), std::chrono::duration_cast<Micros>(now - (*it)->sentAt));
        it->reset(); // Consume before notifying Lua or updating the graph.
        m_answered[m_answeredIndex++ % Capacity] = id;
        if (m_stats.received == 0)
        {
            m_stats.smoothed = rtt;
            m_stats.jitter = rtt / 2;
        }
        else
        {
            // RFC-style EWMA: deviation uses the PREVIOUS smoothed RTT.
            const auto deviation = Micros{std::chrono::abs(rtt - m_stats.smoothed).count()};
            m_stats.jitter += (deviation - m_stats.jitter) / 4;
            m_stats.smoothed += (rtt - m_stats.smoothed) / 8;
        }
        m_stats.latest = rtt;
        m_stats.serverQueueMicros = queueMicros;
        ++m_stats.received;
        return true;
    }

  private:
    struct Request
    {
        uint32_t id;
        TimePoint sentAt;
    };
    std::array<std::optional<Request>, Capacity> m_pending{};
    std::array<uint32_t, Capacity> m_answered{};
    size_t m_answeredIndex = 0;
    uint32_t m_lastId = 0;
    uint64_t m_generation = 0;
    Stats m_stats;
};

struct PingReply
{
    uint32_t id;
    std::optional<uint32_t> serverQueueMicros;
};

// Used by the production decoder and deterministic tests. Validate the entire
// feature-gated payload before consuming any fields from an untrusted frame.
template <typename Message> std::optional<PingReply> readPingReply(Message &msg, bool telemetry)
{
    if (msg.getUnreadSize() < (telemetry ? 8 : 4))
        return std::nullopt;
    PingReply result{msg.getU32(), std::nullopt};
    if (telemetry)
        result.serverQueueMicros = msg.getU32();
    return result;
}

#endif
