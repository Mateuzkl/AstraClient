// Exercise the pinned SDK's timers on an application pthread, independently
// of a cancelled render loop. No cross-thread Lua/UI ownership is introduced.
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <cassert>
#include <cstdio>
#include <emscripten/emscripten.h>
#include <emscripten/eventloop.h>
#include <pthread.h>

static pthread_t owner;
static int timer;
static int polls = 0;
static bool rendered = false;

int main()
{
    owner = pthread_self();
    timer = emscripten_set_interval(
        [](void*) {
            assert(pthread_equal(owner, pthread_self()));
            if (!rendered)
                return;
            if (++polls == 5) {
                emscripten_clear_interval(timer);
                std::puts("Independent application-pthread logic timer after render cancellation PASS");
                emscripten_force_exit(0);
            }
        },
        10, nullptr);
    emscripten_set_main_loop(
        []() {
            assert(pthread_equal(owner, pthread_self()));
            rendered = true;
            emscripten_cancel_main_loop();
        },
        30, true);
}
