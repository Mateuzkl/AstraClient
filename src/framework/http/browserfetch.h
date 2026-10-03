#pragma once

#ifdef __EMSCRIPTEN__
#include <emscripten/fetch.h>
#include <cstdint>
#include <limits>

namespace astra_browser
{
constexpr uint64_t MaxHttpBody = 512ULL * 1024 * 1024; // Match native HttpSession.

constexpr int timeoutMilliseconds(int seconds)
{
    return seconds <= 0                                       ? 1000
           : seconds > std::numeric_limits<int>::max() / 1000 ? std::numeric_limits<int>::max()
                                                              : seconds * 1000;
}

inline uint64_t receivedBytes(const emscripten_fetch_t *fetch)
{
    // Non-streaming XHR progress has numBytes == 0 and loaded bytes in dataOffset.
    return fetch->dataOffset > std::numeric_limits<uint64_t>::max() - fetch->numBytes
               ? std::numeric_limits<uint64_t>::max()
               : fetch->dataOffset + fetch->numBytes;
}

template <typename Queue, typename Callback>
void deferFetchCallback(emscripten_fetch_t *fetch, Queue queue, Callback callback)
{
    // fetch_close frees the SDK pointer immediately and may synchronously call
    // onerror. Carry only the stable operation ID into the dispatcher.
    if (fetch) {
        const int id = static_cast<int>(reinterpret_cast<intptr_t>(fetch->userData));
        queue([id, callback] { callback(id); });
    }
}
} // namespace astra_browser
#endif
