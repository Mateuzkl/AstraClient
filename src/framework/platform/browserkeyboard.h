#pragma once

#ifdef __EMSCRIPTEN__
#include <framework/const.h>
#include <emscripten/emscripten.h>
#include <emscripten/html5.h>
#include <string>
#include <unordered_map>

namespace astra_browser
{
inline std::unordered_map<std::string, Fw::Key> createKeyMap()
{
    std::unordered_map<std::string, Fw::Key> map;
    const std::pair<const char*, Fw::Key> keys[] = {
        {"Backspace", Fw::KeyBackspace}, {"Tab", Fw::KeyTab}, {"Enter", Fw::KeyEnter},
        {"NumpadEnter", Fw::KeyEnter}, {"ShiftLeft", Fw::KeyShift}, {"ShiftRight", Fw::KeyShift},
        {"ControlLeft", Fw::KeyCtrl}, {"ControlRight", Fw::KeyCtrl}, {"AltLeft", Fw::KeyAlt},
        {"AltRight", Fw::KeyAlt}, {"MetaLeft", Fw::KeyMeta}, {"MetaRight", Fw::KeyMeta},
        {"Pause", Fw::KeyPause}, {"CapsLock", Fw::KeyCapsLock}, {"Escape", Fw::KeyEscape},
        {"Space", Fw::KeySpace}, {"PageUp", Fw::KeyPageUp}, {"PageDown", Fw::KeyPageDown},
        {"End", Fw::KeyEnd}, {"Home", Fw::KeyHome}, {"ArrowLeft", Fw::KeyLeft},
        {"ArrowUp", Fw::KeyUp}, {"ArrowRight", Fw::KeyRight}, {"ArrowDown", Fw::KeyDown},
        {"PrintScreen", Fw::KeyPrintScreen}, {"Insert", Fw::KeyInsert}, {"Delete", Fw::KeyDelete},
        {"NumLock", Fw::KeyNumLock}, {"ScrollLock", Fw::KeyScrollLock}, {"Semicolon", Fw::KeySemicolon},
        {"Equal", Fw::KeyEqual}, {"Comma", Fw::KeyComma}, {"Minus", Fw::KeyMinus},
        {"Period", Fw::KeyPeriod}, {"Slash", Fw::KeySlash}, {"Backquote", Fw::KeyGrave},
        {"BracketLeft", Fw::KeyLeftBracket}, {"Backslash", Fw::KeyBackslash}, {"BracketRight", Fw::KeyRightBracket},
        {"Quote", Fw::KeyApostrophe}, {"NumpadMultiply", Fw::KeyAsterisk}, {"NumpadAdd", Fw::KeyPlus},
        {"NumpadSubtract", Fw::KeyMinus}, {"NumpadDecimal", Fw::KeyPeriod}, {"NumpadDivide", Fw::KeySlash}
    };
    for (const auto& entry : keys)
        map.emplace(entry.first, entry.second);
    for (int i = 0; i <= 9; ++i) {
        map.emplace("Digit" + std::to_string(i), static_cast<Fw::Key>(Fw::Key0 + i));
        map.emplace("Numpad" + std::to_string(i), static_cast<Fw::Key>(Fw::KeyNumpad0 + i));
    }
    for (int i = 0; i < 26; ++i)
        map.emplace("Key" + std::string(1, static_cast<char>('A' + i)), static_cast<Fw::Key>(Fw::KeyA + i));
    const Fw::Key functionKeys[] = {Fw::KeyF1, Fw::KeyF2, Fw::KeyF3, Fw::KeyF4, Fw::KeyF5, Fw::KeyF6,
                                   Fw::KeyF7, Fw::KeyF8, Fw::KeyF9, Fw::KeyF10, Fw::KeyF11, Fw::KeyF12};
    for (int i = 0; i < 12; ++i)
        map.emplace("F" + std::to_string(i + 1), functionKeys[i]);
    return map;
}

enum KeyboardPolicy { DispatchKey = 1, ConsumeKey = 2 };

inline int keyboardPolicy(const EmscriptenKeyboardEvent& event, bool mapped)
{
    // This must be decided synchronously, while the DOM event is cancellable.
    // Copying/dispatching to the owning application thread happens afterwards.
    // clang-format off
    return MAIN_THREAD_EM_ASM_INT({
        return AstraBrowser.keyboardPolicy({code: UTF8ToString($0), key: UTF8ToString($1),
            ctrlKey: !!$2, altKey: !!$3, metaKey: !!$4}, !!$5);
    }, event.code, event.key, event.ctrlKey, event.altKey, event.metaKey, mapped);
    // clang-format on
}

inline void installKeyboardCallbacks(void* data, em_key_callback_func callback)
{
    // SDK 6.0.8 ignores the return value when back-proxying to a pthread.
    // On the browser thread it invokes preventDefault() for a true return.
    emscripten_set_keydown_callback_on_thread(EMSCRIPTEN_EVENT_TARGET_WINDOW, data, EM_TRUE, callback,
                                             EM_CALLBACK_THREAD_CONTEXT_MAIN_RUNTIME_THREAD);
    emscripten_set_keyup_callback_on_thread(EMSCRIPTEN_EVENT_TARGET_WINDOW, data, EM_TRUE, callback,
                                           EM_CALLBACK_THREAD_CONTEXT_MAIN_RUNTIME_THREAD);
}
} // namespace astra_browser
#endif
