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
        history.setThreshold(10 * 1024 * 1024);
        int alerts = 0;
        for (int i = 0; i < 140; ++i)
        {
            // One +20 MiB step, then flat beyond the entire rolling window.
            history.add((100 + (i >= 9 ? 20 : 0)) * 1024 * 1024, 200, i * 2000);
            if (history.checkAlert())
                ++alerts;
        }
        check(alerts == 1, "a one-time jump must not repeat alerts during a plateau");
        history.clear();
        for (int i = 0; i < 10; ++i)
            history.add((100 + (i >= 9 ? 20 : 0)) * 1024 * 1024, 200, i * 2000);
        check(history.checkAlert(), "new session resets the acknowledged baseline");
        history.clearAlert();
        history.add(120 * 1024 * 1024, 200, 50000);
        check(!history.checkAlert(), "Clear Alerts must not repeat an acknowledged jump");
        history.add(125 * 1024 * 1024, 200, 52000);
        check(!history.checkAlert(), "new growth must exceed the threshold since acknowledgment");
        history.add(131 * 1024 * 1024, 200, 54000);
        check(history.checkAlert(), "new above-threshold growth can alert again");
        history.clearAlert();
        history.add(151 * 1024 * 1024, 200, 83999);
        check(!history.checkAlert(), "acknowledging must preserve the previous cooldown");
        history.add(151 * 1024 * 1024, 200, 84000);
        check(history.checkAlert(), "new growth alerts at the preserved cooldown boundary");
        history.clear();
        for (int i = 0; i < 10; ++i)
            history.add((100 + (i >= 9 ? 20 : 0)) * 1024 * 1024, 200, i * 2000);
        history.clearAlert();
        check(!history.checkAlert(), "Clear Alerts can acknowledge growth before its first alert");
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
