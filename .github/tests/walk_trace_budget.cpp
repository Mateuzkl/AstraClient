#include "src/client/walktracebudget.h"
#include <cassert>
int main()
{
    WalkTraceBudget budget;
    unsigned total = 0;
    for (unsigned frame = 0; frame < 1000; ++frame) {
        budget.beginFrame();
        unsigned perFrame = 0;
        for (unsigned opcode = 0; opcode < 1000; ++opcode)
            if (budget.allow(100)) { ++total; ++perFrame; }
        assert(perFrame <= 8);
    }
    assert(total == 32);
    budget.beginFrame();
    assert(budget.allow(1100));
    budget.beginFrame();
    assert(budget.allow(50)); // A clock reset does not disable all future traces.
}
