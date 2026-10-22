#include <framework/graphics/drawcommandpool.h>
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <stdexcept>

namespace {
void check(bool value) { if (!value) std::abort(); }
struct CountMemory : std::pmr::memory_resource {
    size_t allocations = 0, bytes = 0;
    void* do_allocate(size_t size, size_t alignment) override {
        ++allocations; bytes += size;
        return std::pmr::new_delete_resource()->allocate(size, alignment);
    }
    void do_deallocate(void* p, size_t size, size_t alignment) override {
        bytes -= size;
        std::pmr::new_delete_resource()->deallocate(p, size, alignment);
    }
    bool do_is_equal(const std::pmr::memory_resource& other) const noexcept override { return this == &other; }
};
struct Command {
    explicit Command(int id) : id(id) { ++alive; }
    virtual ~Command() { --alive; }
    virtual int execute() const { return id; }
    static inline int alive = 0;
    int id;
};
struct alignas(128) Aligned : Command { using Command::Command; };
struct Throwing : Command { Throwing() : Command(0) { throw std::runtime_error("expected"); } };
struct Primitive : Command {
    Primitive(int id, std::shared_ptr<int> resource) : Command(id), resource(std::move(resource)) {}
    std::shared_ptr<int> resource;
    int coords[8]{};
};

void regressions(bool pooled)
{
    CountMemory memory;
    std::weak_ptr<int> texture;
    {
        DrawCommandPool<Command> commands(pooled, &memory);
        check(commands.empty());
        auto owner = std::make_shared<int>(42);
        texture = owner;
        auto* first = commands.emplace<Primitive>(0, owner);
        owner.reset();
        for (int i = 1; i <= 10000; ++i) commands.emplace<Command>(i);
        check(commands[0].get() == first && *first->resource == 42);
        for (int i = 0; i <= 10000; ++i) check(commands[i]->execute() == i);
        auto* aligned = commands.emplace<Aligned>(10001);
        check(reinterpret_cast<uintptr_t>(aligned) % alignof(Aligned) == 0);
        commands.push_back(std::make_unique<Command>(10002));
        commands.push_back(nullptr);
        check(commands.size() == 10003);
        const auto before = commands.size();
        try { commands.emplace<Throwing>(); check(false); } catch (const std::runtime_error&) {}
        check(commands.size() == before && Command::alive == static_cast<int>(before));
        // Rendering conditions may sort handles; stable command addresses must survive.
        std::sort(commands.begin(), commands.end(), [](const auto& a, const auto& b) { return a->id > b->id; });
        check(commands[commands.size() - 1].get() == first);
        if (pooled) check(memory.allocations < 100);
    }
    check(texture.expired() && Command::alive == 0 && memory.bytes == 0);
}

double benchmark(bool pooled, size_t& pages)
{
    constexpr int frames = 120, count = 10000;
    CountMemory memory;
    auto texture = std::make_shared<int>(1);
    volatile uint64_t checksum = 0;
    const auto start = std::chrono::steady_clock::now();
    for (int frame = 0; frame < frames; ++frame) {
        DrawCommandPool<Command> commands(pooled, &memory);
        for (int i = 0; i < count; ++i) commands.emplace<Primitive>(i, texture);
        for (const auto& command : commands) checksum = checksum + command->execute();
    }
    const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    check(checksum == uint64_t(frames) * count * (count - 1) / 2);
    pages = memory.allocations / frames;
    check(memory.bytes == 0);
    return ms;
}
}

int main(int argc, char**)
{
    regressions(false);
    regressions(true);
    if (argc > 1) {
        size_t oldPages = 0, pages = 0;
        const auto oldMs = benchmark(false, oldPages);
        const auto poolMs = benchmark(true, pages);
        std::printf("120 frames x 10000 commands: heap %.2f ms; pool %.2f ms; %.2fx; pool pages/frame %zu\n",
            oldMs, poolMs, oldMs / poolMs, pages);
    }
    std::puts("Command pool: PASS (order, stable addresses, ownership, exceptions, alignment, custom actions)");
}
