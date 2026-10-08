#ifdef NDEBUG
#undef NDEBUG
#endif
#include <framework/http/browserfetch.h>
#include <cassert>
#include <cstdio>
#include <functional>
#include <map>
#include <vector>

namespace
{
std::map<int, emscripten_fetch_t *> operations;
std::vector<std::function<void()>> queued;
int completions = 0;

void onError(emscripten_fetch_t *fetch)
{
    astra_browser::deferFetchCallback(
        fetch, [](auto callback) { queued.push_back(callback); },
        [](int id) {
            const auto it = operations.find(id);
            if (it == operations.end())
                return;
            auto *current = it->second;
            operations.erase(it);
            ++completions;
            assert(emscripten_fetch_close(current) == EMSCRIPTEN_RESULT_SUCCESS);
        });
}

void pump()
{
    while (!queued.empty()) {
        auto callbacks = std::move(queued);
        queued.clear();
        for (const auto &callback : callbacks)
            callback();
    }
}

emscripten_fetch_t *start(int id, const char *url)
{
    emscripten_fetch_attr_t attributes;
    emscripten_fetch_attr_init(&attributes);
    attributes.attributes = EMSCRIPTEN_FETCH_REPLACE | EMSCRIPTEN_FETCH_LOAD_TO_MEMORY;
    attributes.userData = reinterpret_cast<void *>(static_cast<intptr_t>(id));
    attributes.onerror = onError;
    auto *fetch = emscripten_fetch(&attributes, url);
    assert(fetch);
    // Mirrors Http: the SDK may call onerror BEFORE this assignment.
    operations[id] = fetch;
    return fetch;
}
} // namespace

int main()
{
    assert(astra_browser::timeoutMilliseconds(-1) == 1000);
    assert(astra_browser::timeoutMilliseconds(5) == 5000);
    assert(astra_browser::timeoutMilliseconds(std::numeric_limits<int>::max()) == std::numeric_limits<int>::max());
    emscripten_fetch_t progress{};
    progress.dataOffset = 512;
    progress.numBytes = 0;
    assert(astra_browser::receivedBytes(&progress) == 512); // Non-streaming SDK progress.
    progress.numBytes = 128;
    assert(astra_browser::receivedBytes(&progress) == 640);
    progress.dataOffset = std::numeric_limits<uint64_t>::max();
    assert(astra_browser::receivedBytes(&progress) == std::numeric_limits<uint64_t>::max());
    start(1, "https://fixture.example/sync-error");
    assert(completions == 0 && queued.size() == 1);
    pump();
    assert(completions == 1 && operations.empty());
    auto *fetch = start(2, "https://fixture.example/pending");
    operations.erase(2); // Cancellation/termination erase ownership before close.
    assert(emscripten_fetch_close(fetch) == EMSCRIPTEN_RESULT_SUCCESS);
    pump(); // No raw pointer into the SDK's freed request is dereferenced.
    assert(completions == 1 && operations.empty());
    for (int id = 3; id < 103; ++id)
        start(id, "https://fixture.example/sync-error");
    pump();
    assert(completions == 101 && operations.empty());
    std::puts("Fetch synchronous errors, cancel, stale callbacks, progress and timeout bounds: PASS");
}
