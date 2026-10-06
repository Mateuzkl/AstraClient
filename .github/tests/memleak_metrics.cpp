#include "../../src/framework/util/stats.h"
#include <iostream>
#include <stdexcept>
#include <thread>
#include <vector>

void check(bool ok, const char *message)
{
    if (!ok)
        throw std::runtime_error(message);
}

int main()
{
    try
    {
        Stats stats;
        const auto empty = stats.getObjectCounts();
        check(empty.widgets.alive() == 0 && empty.textures.alive() == 0 && empty.things.alive() == 0 &&
                  empty.creatures.alive() == 0,
              "empty counters");
        stats.addTexture();
        stats.addTexture();
        stats.removeTexture();
        stats.addThing();
        stats.addCreature();
        auto counts = stats.getObjectCounts();
        check(counts.textures.created == 2 && counts.textures.destroyed == 1 && counts.textures.alive() == 1,
              "production texture counters");
        check(counts.things.created == 1 && counts.creatures.created == 1, "distinct production counters");

        // Texture lifetime accounting runs on both dispatcher and graphics threads.
        std::vector<std::thread> workers;
        for (int i = 0; i < 4; ++i)
            workers.emplace_back(
                [&stats]
                {
                    for (int j = 0; j < 10000; ++j)
                    {
                        stats.addTexture();
                        stats.removeTexture();
                        stats.getObjectCounts();
                    }
                });
        for (auto &worker : workers)
            worker.join();
        counts = stats.getObjectCounts();
        check(counts.textures.created == 40002 && counts.textures.destroyed == 40001 && counts.textures.alive() == 1,
              "concurrent counter updates must not be lost");
        stats.removeThing();
        stats.removeCreature();
        counts = stats.getObjectCounts();
        check(counts.things.alive() == 0 && counts.creatures.alive() == 0, "object release counters");
        std::cout << "Memory monitor: production object counters and concurrent sampling passed.\n";
        return 0;
    }
    catch (const std::exception &error)
    {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
