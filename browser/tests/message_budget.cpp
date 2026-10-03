#ifdef NDEBUG
#undef NDEBUG
#endif
#include <framework/net/browsermessagebudget.h>
#include <cassert>
#include <cstdio>
#include <limits>
#include <thread>
#include <vector>

int main()
{
    auto budget = std::make_shared<astra_browser::MessageBudget>(1024, 4);
    assert(!budget->reserve(std::numeric_limits<size_t>::max()));
    auto first = budget->reserve(600);
    assert(first && !budget->reserve(425));
    auto second = budget->reserve(424);
    assert(second && !budget->reserve(1));
    first.reset(); // Dispatcher cancellation releases the frame's bytes.
    assert(budget->reserve(600));
    second.reset();
    std::vector<std::shared_ptr<astra_browser::MessageBudget::Reservation>> tiny;
    for (int i = 0; i < 4; ++i)
        tiny.push_back(budget->reserve(0));
    assert(!budget->reserve(0)); // Empty-frame floods cannot bypass the queue bound.
    tiny.clear();
    assert(budget->reserve(1024));
    assert(budget->failOnce() && !budget->failOnce());
    assert(!budget->reserve(1));
    auto replacement = std::make_shared<astra_browser::MessageBudget>(1024, 4);
    assert(replacement->reserve(1024)); // Reconnect has an independent budget.
    std::weak_ptr<astra_browser::MessageBudget> weak = replacement;
    auto queued = replacement->reserve(1);
    replacement.reset();
    assert(!weak.expired());
    queued.reset();
    assert(weak.expired());

    auto concurrent = std::make_shared<astra_browser::MessageBudget>(4096, 16);
    std::vector<std::thread> threads;
    for (int i = 0; i < 8; ++i) {
        threads.emplace_back([concurrent] {
            for (int j = 0; j < 1000; ++j) {
                const auto reservation = concurrent->reserve(16);
                assert(reservation);
            }
        });
    }
    for (auto &thread : threads)
        thread.join();
    assert(concurrent->reserve(4096));
    std::puts("Browser message queue bounds, cancellation, reconnect and concurrent reservations: PASS");
}
