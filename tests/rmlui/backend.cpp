#include <framework/rml/rmlbackend.h>
#include <cstdlib>
#include <initializer_list>

int main()
{
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
