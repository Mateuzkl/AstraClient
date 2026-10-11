# The application policy is centralized here; C libraries and vendor targets
# keep their own language rules. Never substitute c++latest for C++23 on MSVC.
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(MSVC AND CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
    if(CMAKE_CXX_COMPILER_VERSION VERSION_LESS 19.43)
        message(FATAL_ERROR "C++23 requires MSVC 19.43+ (/std:c++23preview); update Visual Studio. No latest/20/17 fallback is allowed.")
    endif()
    # Inspected CMake 3.31.6 / 4.1 and local 4.3.1 map CXX23 to latest.
    # Replace the dialect mapping, not target flags, so exactly one /std switch
    # is emitted, including in try_compile and with either generator.
    set(CMAKE_CXX23_STANDARD_COMPILE_OPTION "-std:c++23preview")
    set(CMAKE_CXX23_EXTENSION_COMPILE_OPTION "-std:c++23preview")
endif()

include(CheckCXXSourceCompiles)
check_cxx_source_compiles("#include \"${CMAKE_CURRENT_LIST_DIR}/../src/framework/stdext/cxx23.h\"
int main() { return 0; }" ASTRA_COMPILER_HAS_CXX23_MODE)
if(NOT ASTRA_COMPILER_HAS_CXX23_MODE)
    message(FATAL_ERROR "The actual compiler mode is not C++23. See CMakeConfigureLog.yaml; a compiler accepting C++23 is required.")
endif()
message(STATUS "Astra C++23: ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}; required=ON, extensions=OFF")
