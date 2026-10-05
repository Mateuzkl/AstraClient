#include "../../src/client/memleakhistory.h"
#include <cmath>
#include <iostream>
#include <stdexcept>

void check(bool ok, const char *message)
{
    if (!ok)
        throw std::runtime_error(message);
}
int main()
{
    try
    {
        MemLeakHistory history;
        check(history.bytesPerSecond() == 0 && history.delta() == 0 && !history.checkAlert(), "empty history");
        check(history.add(1000, 200, 0), "first sample");
        check(!history.add(2000, 200, 0) && !history.add(2000, 200, -1), "duplicate/old timestamps");
        check(!history.add(-1, 200, 1000) && !history.add(1000, -1, 1000), "invalid memory values");
        check(history.add(3048, 200, 2000), "second sample");
        check(history.span() == 2000 && history.delta() == 2048, "bytes and millisecond units");
        check(std::abs(history.bytesPerSecond() - 1024.0) < 0.001, "trend is bytes per second");
        history.clear();
        history.setThreshold(1000);
        history.setCooldown(30000);
        for (int i = 0; i < 9; ++i)
            history.add(i * 1024, 200, i * 2000);
        check(!history.checkAlert(), "need ten observations");
        history.add(9 * 1024, 200, 18000);
        check(history.checkAlert(), "first growth alert does not need an initial cooldown");
        check(!history.checkAlert(), "duplicate alert");
        history.add(24000, 200, 47999);
        check(!history.checkAlert(), "cooldown just below boundary");
        history.add(24576, 200, 48000);
        check(history.checkAlert(), "cooldown boundary");
        history.clear();
        for (int i = 0; i < 1000; ++i)
            history.add(i * 1024, 200, i * 2000);
        check(history.size() == 120 && history.span() == 238000, "bounded history window");
        history.clear();
        for (int i = 0; i < 10; ++i)
            history.add(10000 - i * 1024, 200, i * 2000);
        check(history.delta() < 0 && !history.checkAlert(), "falling memory is not growth");
        history.clear();
        history.setThreshold(-1);
        history.setCooldown(-1);
        check(history.threshold() == 0 && history.cooldown() == 0, "negative config is clamped");
        std::cout << "Memory monitor history: units, growth/cooldown, bounds and reset passed.\n";
        return 0;
    }
    catch (const std::exception &error)
    {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
