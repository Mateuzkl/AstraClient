# Use CMake's version-aware finder and its ZLIB::ZLIB target. libcurl's
# exported target needs it; the legacy finder only supplied path variables.
if(USE_STATIC_LIBS)
    set(ZLIB_USE_STATIC_LIBS ON)
endif()
include("${CMAKE_ROOT}/Modules/FindZLIB.cmake")
