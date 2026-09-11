cmake_minimum_required(VERSION 3.20)
cmake_policy(VERSION 3.20)
project(AstraClient LANGUAGES C CXX)

if(EMSCRIPTEN OR CMAKE_SYSTEM_NAME STREQUAL "Emscripten")
    set(WASM ON)
    message(STATUS "Browser/WebAssembly target: ON")
endif()

set(CMAKE_CXX_STANDARD 17)

# default build type
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release")
endif()

option(FRAMEWORK_SOUND "Use SOUND " OFF)
option(FRAMEWORK_GRAPHICS "Use GRAPHICS " ON)
option(FRAMEWORK_XML "Use XML " ON)
option(FRAMEWORK_NET "Use NET " ON)

include(src/framework/CMakeLists.txt)
include(src/client/CMakeLists.txt)

# functions map for reading backtraces (flags do linker GNU; nao aplicar no MSVC)
if(NOT APPLE AND NOT WASM AND NOT MSVC)
    set(CMAKE_CXX_LINK_FLAGS "${CMAKE_CXX_LINK_FLAGS} -no-pie -Wl,-Map=${PROJECT_NAME}.map")
endif()

set(executable_SOURCES
    src/main.cpp
)

# add executable icon for win32 platforms
if(WIN32)
    if(MSVC)
        # MSVC: o CMake compila o .rc direto com rc.exe (windres nao existe aqui)
        set(executable_SOURCES ${executable_SOURCES} ${CMAKE_CURRENT_SOURCE_DIR}/src/otcicon.rc)
    else()
        # MinGW: compila o resource com windres
        add_custom_command(OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/otcicon.o
                           COMMAND ${CMAKE_RC_COMPILER}
                           -I${CMAKE_CURRENT_SOURCE_DIR}/src
                           -i${CMAKE_CURRENT_SOURCE_DIR}/src/otcicon.rc
                           -o ${CMAKE_CURRENT_BINARY_DIR}/otcicon.o)
        set(executable_SOURCES ${executable_SOURCES} otcicon.o)
    endif()
endif()

if(VERSION)
    add_definitions(-D"VERSION=\\"${VERSION}\\"")
endif()

# add client executable
add_executable(${PROJECT_NAME} ${framework_SOURCES} ${client_SOURCES} ${executable_SOURCES})
target_link_libraries(${PROJECT_NAME} ${framework_LIBRARIES})

if(WASM)
    set(ASTRA_WASM_PTHREAD_POOL_SIZE "4" CACHE STRING "Number of worker threads created before main()")
    set(ASTRA_WASM_INITIAL_MEMORY "805306368" CACHE STRING "Initial WebAssembly memory in bytes")
    set(ASTRA_WASM_MAXIMUM_MEMORY "2147483648" CACHE STRING "Maximum WebAssembly memory in bytes")

    target_compile_options(${PROJECT_NAME} PRIVATE
        -pthread
        -fexceptions
        -sUSE_BOOST_HEADERS=1
        -sUSE_LIBPNG=1
        -sUSE_ZLIB=1
    )
    target_compile_definitions(${PROJECT_NAME} PRIVATE
        BOOST_ALL_NO_LIB
        BOOST_ERROR_CODE_HEADER_ONLY
        BOOST_SYSTEM_NO_DEPRECATED
    )

    target_link_options(${PROJECT_NAME} PRIVATE
        -pthread
        -fexceptions
        -sUSE_BOOST_HEADERS=1
        -sUSE_LIBPNG=1
        -sUSE_ZLIB=1
        -sFETCH=1
        -sFORCE_FILESYSTEM=1
        -sALLOW_MEMORY_GROWTH=1
        -sINITIAL_MEMORY=${ASTRA_WASM_INITIAL_MEMORY}
        -sMAXIMUM_MEMORY=${ASTRA_WASM_MAXIMUM_MEMORY}
        -sMIN_WEBGL_VERSION=2
        -sMAX_WEBGL_VERSION=2
        -sFULL_ES2=1
        -sPROXY_TO_PTHREAD=1
        -sOFFSCREENCANVAS_SUPPORT=1
        -sOFFSCREEN_FRAMEBUFFER=1
        -sPTHREAD_POOL_SIZE=${ASTRA_WASM_PTHREAD_POOL_SIZE}
        -sEXIT_RUNTIME=1
        -sENVIRONMENT=web,worker
        -sEXPORTED_RUNTIME_METHODS=ccall
        -lidbfs.js
        -lwebsocket.js
        --shell-file=${CMAKE_SOURCE_DIR}/browser/shell.html
        --preload-file=${CMAKE_SOURCE_DIR}/init.lua@/init.lua
        --preload-file=${CMAKE_SOURCE_DIR}/data@/data
        --preload-file=${CMAKE_SOURCE_DIR}/layouts@/layouts
        --preload-file=${CMAKE_SOURCE_DIR}/mods@/mods
        --preload-file=${CMAKE_SOURCE_DIR}/modules@/modules
        --use-preload-cache
    )

    # Ninja does not infer dependencies hidden inside --preload-file. Track
    # every packaged asset so an incremental build cannot serve stale Lua,
    # shaders or UI files after a source edit.
    file(GLOB_RECURSE ASTRA_WASM_ASSET_FILES CONFIGURE_DEPENDS LIST_DIRECTORIES false
        "${CMAKE_SOURCE_DIR}/data/*"
        "${CMAKE_SOURCE_DIR}/layouts/*"
        "${CMAKE_SOURCE_DIR}/mods/*"
        "${CMAKE_SOURCE_DIR}/modules/*"
    )
    list(APPEND ASTRA_WASM_ASSET_FILES "${CMAKE_SOURCE_DIR}/init.lua")
    set_property(TARGET ${PROJECT_NAME} APPEND PROPERTY LINK_DEPENDS ${ASTRA_WASM_ASSET_FILES})

    if(CMAKE_BUILD_TYPE STREQUAL "Debug")
        target_link_options(${PROJECT_NAME} PRIVATE
            -sASSERTIONS=2
            -sSAFE_HEAP=1
            -sSTACK_OVERFLOW_CHECK=2
        )
    endif()

    set_target_properties(${PROJECT_NAME} PROPERTIES
        OUTPUT_NAME "astraclient"
        SUFFIX ".html"
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/dist"
    )
endif()

if(WIN32 AND NOT WINDOWS_CONSOLE AND FRAMEWORK_GRAPHICS)
    set_target_properties(${PROJECT_NAME} PROPERTIES WIN32_EXECUTABLE TRUE)
    if(MSVC)
        set_property(TARGET ${PROJECT_NAME} APPEND_STRING PROPERTY LINK_FLAGS " /ENTRY:mainCRTStartup")
    endif()
endif()

if(APPLE AND USE_STATIC_LIBS)
    target_link_libraries(${PROJECT_NAME} "-framework Foundation" "-framework IOKit")
endif()
