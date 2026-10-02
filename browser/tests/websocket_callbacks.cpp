#include <framework/net/browserwebsocket.h>
#include <emscripten/emscripten.h>
#include <cassert>
#include <cstdio>

namespace {
int deliveredEvents = 0;
template<typename Event>
EM_BOOL countEvent(int, const Event*, void*)
{
    ++deliveredEvents;
    return EM_TRUE;
}

void registerCallbacks(EMSCRIPTEN_WEBSOCKET_T socket)
{
    emscripten_websocket_set_onopen_callback(socket, nullptr, &countEvent<EmscriptenWebSocketOpenEvent>);
    emscripten_websocket_set_onerror_callback(socket, nullptr, &countEvent<EmscriptenWebSocketErrorEvent>);
    emscripten_websocket_set_onclose_callback(socket, nullptr, &countEvent<EmscriptenWebSocketCloseEvent>);
    emscripten_websocket_set_onmessage_callback(socket, nullptr, &countEvent<EmscriptenWebSocketMessageEvent>);
}
}

int main()
{
    EmscriptenWebSocketCreateAttributes attributes{};
    attributes.url = "ws://localhost:8816/test";
    const auto original = emscripten_websocket_new(&attributes);
    assert(original > 0);
    registerCallbacks(original);
    EM_ASM({ globalThis.astraTestSockets[0].emitEvents(); });
    assert(deliveredEvents == 4);

    astra_browser::detachWebSocketCallbacks(original);
    emscripten_websocket_close(original, 1000, "test disconnect");
    emscripten_websocket_delete(original);

    const auto replacement = emscripten_websocket_new(&attributes);
    assert(replacement == original); // The SDK recycles the released handle.
    registerCallbacks(replacement);
    EM_ASM({ globalThis.astraTestSockets[0].emitEvents(); });
    assert(deliveredEvents == 4); // Late events must not reach the replacement.
    EM_ASM({ globalThis.astraTestSockets[1].emitEvents(); });
    assert(deliveredEvents == 8);
    astra_browser::detachWebSocketCallbacks(replacement);
    emscripten_websocket_close(replacement, 1000, "test disconnect");
    emscripten_websocket_delete(replacement);
    std::puts("WebSocket callback teardown and handle reuse: PASS");
}
