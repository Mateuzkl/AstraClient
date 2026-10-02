#include "src/client/pingtracker.h"

#include <cassert>
#include <iostream>
#include <limits>
#include <vector>

using namespace std::chrono_literals;
using Clock = PingTracker::Clock;
const auto epoch = Clock::time_point{};

struct Reader
{
    std::vector<uint8_t> bytes;
    size_t position = 0;
    int getUnreadSize() const { return static_cast<int>(bytes.size() - position); }
    uint32_t getU32()
    {
        assert(getUnreadSize() >= 4);
        uint32_t value = 0;
        for (unsigned i = 0; i < 4; ++i)
            value |= static_cast<uint32_t>(bytes[position++]) << (8 * i);
        return value;
    }
};

int main()
{
    PingTracker p;
    const auto id = *p.begin(epoch);
    assert(id != 0 && p.pendingCount() == 1);
    assert(p.consume(id, epoch + 100ms, 82000));
    assert(p.pendingCount() == 0 && p.stats().latest == 100ms);
    assert(p.stats().smoothed == 100ms && p.stats().jitter == 50ms);
    assert(p.stats().serverQueueMicros == 82000);
    assert(!p.consume(id, epoch + 300ms, 90000));
    assert(p.stats().duplicateReplies == 1 && p.stats().received == 1);
    assert(p.stats().latest == 100ms && p.stats().serverQueueMicros == 82000);
    assert(!p.consume(0, epoch + 300ms) && !p.consume(9000, epoch + 300ms));
    assert(p.stats().unknownReplies == 2 && p.pendingCount() == 0);
    const auto next = *p.begin(epoch + 1s);
    assert(p.consume(next, epoch + 1140ms));
    assert(p.stats().smoothed == 105ms && p.stats().jitter == 47500us);
    assert(!p.stats().serverQueueMicros); // No fake queue value for legacy replies.
    assert(p.lossPercent() == 0.0);
    const auto missing = *p.begin(epoch + 2s);
    p.expire(epoch + 11999ms);
    assert(p.pendingCount() == 1);
    p.expire(epoch + 12s);
    assert(p.pendingCount() == 0 && p.stats().timedOut == 1);
    assert(p.lossPercent() > 33.3 && p.lossPercent() < 33.4);
    assert(!p.consume(missing, epoch + 13s));

    const auto generation = p.generation();
    p.reset();
    assert(!p.isCurrentGeneration(generation)); // Scheduler uses this same guard.
    assert(p.isCurrentGeneration(p.generation()));
    assert(p.pendingCount() == 0 && p.stats().sent == 0 && p.stats().received == 0);
    assert(p.stats().timedOut == 0 && p.stats().duplicateReplies == 0 && p.stats().unknownReplies == 0);
    assert(p.stats().latest == 0us && p.lossPercent() == 0 && !p.stats().serverQueueMicros);
    assert(*p.begin(epoch) != id); // Late prior-session ID cannot consume a new request.
    assert(!p.consume(id, epoch + 1ms));

    PingTracker full;
    for (size_t i = 0; i < PingTracker::Capacity; ++i)
        assert(full.begin(epoch));
    assert(!full.begin(epoch + 1ms));
    assert(full.pendingCount() == PingTracker::Capacity && full.stats().sent == PingTracker::Capacity);
    assert(full.begin(epoch + PingTracker::Timeout));
    assert(full.pendingCount() == 1 && full.stats().timedOut == PingTracker::Capacity);

    PingTracker wrap{std::numeric_limits<uint32_t>::max() - 1};
    assert(*wrap.begin(epoch) == std::numeric_limits<uint32_t>::max());
    assert(*wrap.begin(epoch) == 1 && *wrap.begin(epoch) == 2);
    // Long sessions retain fixed-size storage and only outstanding requests.
    for (int i = 0; i < 100000; ++i)
    {
        const auto when = epoch + std::chrono::seconds(i);
        const auto request = *wrap.begin(when);
        assert(wrap.consume(request, when + 1ms));
        assert(wrap.pendingCount() <= 3);
    }

    Reader legacy{{0x78, 0x56, 0x34, 0x12, 0xAA}};
    const auto oldReply = readPingReply(legacy, false);
    assert(oldReply && oldReply->id == 0x12345678 && !oldReply->serverQueueMicros && legacy.position == 4);
    Reader modern{{0x78, 0x56, 0x34, 0x12, 0xE8, 0x03, 0x00, 0x00, 0xAA}};
    const auto newReply = readPingReply(modern, true);
    assert(newReply && newReply->id == 0x12345678 && newReply->serverQueueMicros == 1000 && modern.position == 8);
    for (size_t length = 0; length < 8; ++length)
    {
        Reader shortReply{std::vector<uint8_t>(length)};
        assert(!readPingReply(shortReply, true) && shortReply.position == 0);
        if (length < 4)
            assert(!readPingReply(shortReply, false) && shortReply.position == 0);
    }
    std::cout << "Ping tracker/decoder: all deterministic checks passed\n";
}
