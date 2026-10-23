#include <framework/rml/rmlbackend.h>
#include <framework/platform/eglcontext.h>
#include <cstdlib>
#include <initializer_list>

int main()
{
    for (const bool preferEs3 : {false, true}) {
        for (const bool es3 : {false, true}) {
            for (const bool es2 : {false, true}) {
                int attempts = 0;
                const auto result = AstraEgl::negotiateContext(preferEs3, [&](int version) {
                    ++attempts;
                    if (!preferEs3 && version == 3) std::abort();
                    return version == 3 ? es3 : es2;
                });
                const int expected = preferEs3 && es3 ? 3 : es2 ? 2 : 0;
                if (result != expected || attempts != (preferEs3 && !es3 ? 2 : 1)) return EXIT_FAILURE;
            }
        }
    }
    using RmlBackend::supportsGles3;
    if (!supportsGles3("OpenGL ES 3.0.0 (ANGLE 2.1.5414 git hash: aa63ea230e0c)") ||
        !supportsGles3("OpenGL ES 3.2 Mesa 25.0") || !supportsGles3("OpenGL ES 10.0"))
        return EXIT_FAILURE;
    for (const auto version : {"", "OpenGL ES 2.0 (ANGLE)", "3.3 NVIDIA", "OpenGL ES-CM 1.1",
             "OpenGL ES ", "OpenGL ES 3", "OpenGL ES 3.", "OpenGL ES 3.x", "OpenGL ES 3.-1",
             "OpenGL ES 999999999999999999.0"}) {
        if (supportsGles3(version))
            return EXIT_FAILURE;
    }
    return EXIT_SUCCESS;
}
