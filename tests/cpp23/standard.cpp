#include <framework/stdext/cxx23.h>
#include <cstdio>
#include <type_traits>
#include <utility>

enum class Probe : unsigned { value = 23 };
static_assert(std::to_underlying(Probe::value) == 23);
constexpr int mode() {
    if consteval { return 23; } else { return 23; }
}
static_assert(mode() == 23);

int main() {
    std::printf("C++23 probe: __cplusplus=%ld", long(__cplusplus));
#ifdef _MSVC_LANG
    std::printf(" _MSVC_LANG=%ld _MSC_VER=%d", long(_MSVC_LANG), _MSC_VER);
#endif
    std::puts("; to_underlying + if consteval: PASS");
    return mode() == 23 ? 0 : 1;
}
