#pragma once

#ifdef __EMSCRIPTEN__
#include <emscripten/websocket.h>

namespace astra_browser
{
template <typename Event> inline EM_BOOL ignoreWebSocketEvent(int, const Event *, void *) { return EM_TRUE; }

inline void detachWebSocketCallbacks(EMSCRIPTEN_WEBSOCKET_T socket)
{
    // Emscripten 6.0.8 wraps even a null callback in a JS event handler. Use
    // no-ops so late close/error events neither call table entry 0 nor reach
    // a replacement connection after the socket handle has been reused.
    emscripten_websocket_set_onopen_callback(socket, nullptr, &ignoreWebSocketEvent<EmscriptenWebSocketOpenEvent>);
    emscripten_websocket_set_onerror_callback(socket, nullptr, &ignoreWebSocketEvent<EmscriptenWebSocketErrorEvent>);
    emscripten_websocket_set_onclose_callback(socket, nullptr, &ignoreWebSocketEvent<EmscriptenWebSocketCloseEvent>);
    emscripten_websocket_set_onmessage_callback(socket, nullptr,
                                                &ignoreWebSocketEvent<EmscriptenWebSocketMessageEvent>);
}
} // namespace astra_browser
#endif
