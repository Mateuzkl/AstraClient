#include "../../src/framework/core/scheduledeventqueue.h"
#include <iostream>
#include <memory>
#include <stdexcept>

namespace {
void check(bool value, const char* message)
{
    if (!value)
        throw std::runtime_error(message);
}
struct Event {
    std::string function;
    int64_t deadline;
    bool canceled = false;
    bool isCanceled() const { return canceled; }
    const std::string& getFunction() const { return function; }
    int64_t ticks() const { return deadline; }
};
using Ptr = std::shared_ptr<Event>;
struct Compare {
    bool operator()(const Ptr& a, const Ptr& b) const { return b->ticks() < a->ticks(); }
};
using Queue = ScheduledEventQueue<Ptr, Compare>;
Ptr event(const std::string& source, int64_t deadline, bool canceled = false)
{
    return std::make_shared<Event>(Event{source, deadline, canceled});
}
} // namespace

int main()
{
    try {
        Queue queue;
        queue.push(event("live/future", 20000));
        queue.push(event("live/due", 500));
        auto dead = event("canceled/long-delay", 3600000, true);
        std::weak_ptr<Event> weak = dead;
        queue.push(dead);
        dead.reset();
        for (int i = 1; i < 5000; ++i)
            queue.push(event("canceled/long-delay", 3600000 + i, true));
        auto info = queue.diagnostics(1000, 2);
        check(info.active == 2 && info.canceled == 5000 && info.due == 1, "distinct active/canceled/due counts");
        check(info.sources.size() == 2 && info.sources[0].function == "canceled/long-delay" &&
                  info.sources[0].canceled == 5000, "largest scheduled source first with bounded report");
        check(queue.size() == 5002 && !weak.expired(), "diagnostics must not mutate or retain event owners");
        check(queue.compactCanceled(999) == 0, "do not scan on every frame");
        check(queue.compactCanceled(1000) == 5000, "release canceled far-future timers behind live timers");
        check(weak.expired() && queue.size() == 2, "heap must release the canceled native event shells");
        check(queue.top()->getFunction() == "live/due", "compaction preserves earliest live deadline");
        queue.pop();
        check(queue.top()->ticks() == 20000, "compaction must not change live deadlines");
        info = queue.diagnostics(1000, 0);
        check(info.active == 1 && info.canceled == 0 && info.due == 0 && info.sources.empty(), "zero-limit diagnostics");

        // Repeated cancellation must not grow a large queue across sweeps.
        Queue churn;
        for (int i = 0; i < 20; ++i)
            churn.push(event("live", 100000 + 20 - i));
        for (int cycle = 1; cycle <= 20; ++cycle) {
            for (int i = 0; i < 5000; ++i)
                churn.push(event("canceled", 3600000 + i, true));
            check(churn.compactCanceled(cycle * 1000) == 5000 && churn.size() == 20,
                  "repeated cancellation must leave all live timers and no canceled backlog");
        }
        for (int i = 1; i <= 20; ++i) {
            check(churn.top()->ticks() == 100000 + i, "live heap ordering after repeated rebuilds");
            churn.pop();
        }

        Queue throttled;
        for (int i = 0; i < 256; ++i)
            throttled.push(event("first-wave", 50000, true));
        check(throttled.compactCanceled(1000) == 256, "threshold cleanup");
        for (int i = 0; i < 256; ++i)
            throttled.push(event("second-wave", 50000, true));
        check(throttled.compactCanceled(1999) == 0 && throttled.size() == 256, "one-second sweep throttle");
        check(throttled.compactCanceled(2000) == 256 && throttled.empty(), "all-canceled heap may become empty");
        check(throttled.diagnostics(2000, 5).sources.empty(), "empty diagnostics");

        Queue small;
        small.push(event("small-canceled", 10000, true));
        check(small.compactCanceled(2000) == 0, "small heaps avoid periodic scanning");
        check(small.removeCanceled() == 1 && small.empty(), "explicit compaction of small queues");
        std::cout << "Scheduled queue: cancellation compaction, throttling, source diagnostics and live deadlines passed.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
