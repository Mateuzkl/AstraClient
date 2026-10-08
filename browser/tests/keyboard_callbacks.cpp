#ifdef NDEBUG
#undef NDEBUG
#endif
#include <framework/platform/browserkeyboard.h>
#include <emscripten/threading.h>
#include <atomic>
#include <cassert>
#include <cstdio>

static std::atomic<int> delivered{0};
static std::atomic<int> lastKey{Fw::KeyUnknown};

static EM_BOOL callback(int, const EmscriptenKeyboardEvent* event, void* data)
{
    assert(emscripten_is_main_browser_thread());
    const auto& keys = *static_cast<std::unordered_map<std::string, Fw::Key>*>(data);
    const auto key = keys.find(event->code);
    const int policy = astra_browser::keyboardPolicy(*event, key != keys.end());
    if (policy & astra_browser::DispatchKey) {
        ++delivered;
        lastKey = key == keys.end() ? Fw::KeyUnknown : key->second;
    }
    return (policy & astra_browser::ConsumeKey) != 0;
}

int main()
{
    assert(!emscripten_is_main_browser_thread()); // Same PROXY_TO_PTHREAD as the client.
    auto keys = astra_browser::createKeyMap();
    const Fw::Key functions[] = {Fw::KeyF1, Fw::KeyF2, Fw::KeyF3, Fw::KeyF4, Fw::KeyF5, Fw::KeyF6,
                                 Fw::KeyF7, Fw::KeyF8, Fw::KeyF9, Fw::KeyF10, Fw::KeyF11, Fw::KeyF12};
    astra_browser::installKeyboardCallbacks(&keys, callback);
    for (int i = 0; i < 12; ++i) {
        const auto code = "F" + std::to_string(i + 1);
        for (const char* modifier : {"", "ctrlKey", "shiftKey", "altKey"}) {
            const int before = delivered;
            assert(MAIN_THREAD_EM_ASM_INT({
                return astraKeyboardTest.emit('keydown', UTF8ToString($0), UTF8ToString($0), UTF8ToString($1));
            }, code.c_str(), modifier));
            assert(delivered == before + 1 && lastKey == functions[i]);
            assert(MAIN_THREAD_EM_ASM_INT({
                return astraKeyboardTest.emit('keyup', UTF8ToString($0), UTF8ToString($0), UTF8ToString($1));
            }, code.c_str(), modifier));
            assert(delivered == before + 2); // No duplicated SDK callbacks.
        }
    }
    for (const char* code : {"ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Space", "Tab", "Backspace",
                             "Insert", "Delete", "Home", "End", "PageUp", "PageDown", "NumpadEnter"}) {
        assert(MAIN_THREAD_EM_ASM_INT({ return astraKeyboardTest.emit('keydown', UTF8ToString($0)); }, code));
        assert(lastKey == keys.at(code));
        assert(MAIN_THREAD_EM_ASM_INT({ return astraKeyboardTest.emit('keyup', UTF8ToString($0)); }, code));
    }
    const int before = delivered;
    assert(!MAIN_THREAD_EM_ASM_INT({ return astraKeyboardTest.emit('keydown', 'KeyV', 'v', 'ctrlKey'); }));
    assert(delivered == before);
    assert(!MAIN_THREAD_EM_ASM_INT({ return astraKeyboardTest.emit('keydown', 'KeyC', 'c', 'ctrlKey'); }));
    assert(delivered == before + 1 && lastKey == Fw::KeyC);
    MAIN_THREAD_EM_ASM({ document.activeElement = astraKeyboardTest.control; });
    assert(!MAIN_THREAD_EM_ASM_INT({ return astraKeyboardTest.emit('keydown', 'F5'); }));
    assert(!MAIN_THREAD_EM_ASM_INT({ return astraKeyboardTest.emit('keydown', 'KeyA', 'a'); }));
    assert(delivered == before + 1);
    MAIN_THREAD_EM_ASM({ document.activeElement = astraKeyboardTest.editor; });
    assert(!MAIN_THREAD_EM_ASM_INT({ return astraKeyboardTest.emit('keydown', 'KeyA', 'a'); }));
    assert(!MAIN_THREAD_EM_ASM_INT({ return astraKeyboardTest.emit('keydown', 'Enter'); }));
    assert(delivered == before + 1);
    assert(MAIN_THREAD_EM_ASM_INT({ return astraKeyboardTest.emit('keydown', 'F5'); }));
    assert(delivered == before + 2 && lastKey == Fw::KeyF5);
    for (int cycle = 0; cycle < 10; ++cycle) {
        astra_browser::installKeyboardCallbacks(nullptr, nullptr);
        assert(MAIN_THREAD_EM_ASM_INT({ return astraKeyboardTest.count(); }) == 0);
        astra_browser::installKeyboardCallbacks(&keys, callback);
        assert(MAIN_THREAD_EM_ASM_INT({ return astraKeyboardTest.count(); }) == 2);
    }
    astra_browser::installKeyboardCallbacks(nullptr, nullptr);
    assert(!MAIN_THREAD_EM_ASM_INT({ return astraKeyboardTest.emit('keydown', 'F5'); }));
    assert(delivered == before + 2);
    std::puts("Pinned-SDK synchronous keyboard cancellation, Fw mapping, focus, clipboard and teardown: PASS");
    emscripten_force_exit(0);
}
