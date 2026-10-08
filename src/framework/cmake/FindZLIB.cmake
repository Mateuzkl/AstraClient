# Use CMake's version-aware finder and its ZLIB::ZLIB target. libcurl's
# exported target needs it; the legacy finder only supplied path variables.
set(ZLIB_USE_STATIC_LIBS ${USE_STATIC_LIBS})
include("${CMAKE_ROOT}/Modules/FindZLIB.cmake")
