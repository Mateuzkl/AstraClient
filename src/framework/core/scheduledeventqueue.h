#ifndef FRAMEWORK_SCHEDULEDEVENTQUEUE_H
#define FRAMEWORK_SCHEDULEDEVENTQUEUE_H

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <map>
#include <queue>
#include <string>
#include <utility>
#include <vector>

// Inspect/compact the underlying heap without copying or executing callbacks.
// The dispatcher owns synchronization; only canceled events may be discarded.
template <typename EventPtr, typename Compare>
class ScheduledEventQueue : public std::priority_queue<EventPtr, std::vector<EventPtr>, Compare>
{
public:
    struct Source {
        std::string function;
        size_t active = 0, canceled = 0, due = 0;
    };
    struct Diagnostics {
        size_t active = 0, canceled = 0, due = 0;
        std::vector<Source> sources;
    };

    size_t removeCanceled()
    {
        const auto before = this->c.size();
        this->c.erase(std::remove_if(this->c.begin(), this->c.end(),
                                    [](const EventPtr& event) { return event->isCanceled(); }), this->c.end());
        const auto removed = before - this->c.size();
        if (removed)
            std::make_heap(this->c.begin(), this->c.end(), this->comp);
        return removed;
    }

    // Small queues drain naturally. Sweep a large heap at most once per second,
    // not on every frame, to release canceled far-future entries behind live timers.
    size_t compactCanceled(int64_t now)
    {
        if (this->c.size() < 256 || now - m_lastCleanup < 1000)
            return 0;
        m_lastCleanup = now;
        return removeCanceled();
    }

    Diagnostics diagnostics(int64_t now, size_t limit) const
    {
        Diagnostics result;
        std::map<std::string, Source> sources;
        for (const auto& event : this->c) {
            auto& source = sources[event->getFunction()];
            if (event->isCanceled()) {
                ++result.canceled;
                ++source.canceled;
            } else {
                ++result.active;
                ++source.active;
                if (event->ticks() <= now) {
                    ++result.due;
                    ++source.due;
                }
            }
        }
        for (auto& entry : sources) {
            entry.second.function = entry.first;
            result.sources.push_back(std::move(entry.second));
        }
        std::sort(result.sources.begin(), result.sources.end(), [](const Source& a, const Source& b) {
            const auto totalA = a.active + a.canceled, totalB = b.active + b.canceled;
            return totalA != totalB ? totalA > totalB : a.function < b.function;
        });
        if (result.sources.size() > limit)
            result.sources.resize(limit);
        return result;
    }

private:
    int64_t m_lastCleanup = 0;
};

#endif
