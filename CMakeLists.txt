cmake_minimum_required(VERSION 3.24)
cmake_policy(VERSION 3.24)
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

if(WIN32 AND EXISTS "${CMAKE_SOURCE_DIR}/data/images/splash.png")
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:${PROJECT_NAME}>/data/images"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/data/images/splash.png" "$<TARGET_FILE_DIR:${PROJECT_NAME}>/data/images/splash.png"
        VERBATIM)
endif()

if(WASM)
    configure_file(browser/config.js "${CMAKE_BINARY_DIR}/dist/config.js" COPYONLY)
    configure_file(browser/runtime.js "${CMAKE_BINARY_DIR}/dist/runtime.js" COPYONLY)
    configure_file(browser/asset-cache.js "${CMAKE_BINARY_DIR}/dist/asset-cache.js" COPYONLY)
    configure_file(browser/launcher.js "${CMAKE_BINARY_DIR}/dist/launcher.js" COPYONLY)
    configure_file(browser/launcher.css "${CMAKE_BINARY_DIR}/dist/launcher.css" COPYONLY)
    configure_file(data/images/title.png "${CMAKE_BINARY_DIR}/dist/launcher-background.png" COPYONLY)
    configure_file(data/images/astra-client-emblem.png "${CMAKE_BINARY_DIR}/dist/astra-client-emblem.png" COPYONLY)
    find_package(Python3 REQUIRED COMPONENTS Interpreter)
    set(ASTRA_WASM_THINGS_DIR "${CMAKE_SOURCE_DIR}/data/things/860" CACHE PATH
        "Asset pack containing Tibia.dat and Tibia.spr (only this pack is bundled)")
    foreach(asset Tibia.dat Tibia.spr)
        if(NOT EXISTS "${ASTRA_WASM_THINGS_DIR}/${asset}")
            message(FATAL_ERROR "Missing browser asset ${ASTRA_WASM_THINGS_DIR}/${asset}. Extract data/things/860.rar first, or set ASTRA_WASM_THINGS_DIR.")
        endif()
    endforeach()

    # Do not ship other packs, archives or private backups alongside the selected
    # DAT/SPR. Full-tree preloading can exceed the browser's 2 GB memory ceiling.
    file(GLOB ASTRA_WASM_DATA_ENTRIES CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/data/*")
    foreach(entry IN LISTS ASTRA_WASM_DATA_ENTRIES)
        get_filename_component(name "${entry}" NAME)
        if(NOT name STREQUAL "things")
            target_link_options(${PROJECT_NAME} PRIVATE "--preload-file=${entry}@/data/${name}")
        endif()
    endforeach()
    set(ASTRA_WASM_PTHREAD_POOL_SIZE "4" CACHE STRING "Number of worker threads created before main()")
    set(ASTRA_WASM_INITIAL_MEMORY "805306368" CACHE STRING "Initial WebAssembly memory in bytes")
    set(ASTRA_WASM_MAXIMUM_MEMORY "2147483648" CACHE STRING "Maximum WebAssembly memory in bytes")

    target_compile_options(${PROJECT_NAME} PRIVATE
        -pthread
        -fexceptions
        -sUSE_LIBPNG=1
        -sUSE_ZLIB=1
    )
    target_compile_definitions(${PROJECT_NAME} PRIVATE
        ASIO_STANDALONE
    )

    target_link_options(${PROJECT_NAME} PRIVATE
        -pthread
        -fexceptions
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
        --preload-file=${ASTRA_WASM_THINGS_DIR}/Tibia.dat@/data/things/860/Tibia.dat
        --preload-file=${ASTRA_WASM_THINGS_DIR}/Tibia.spr@/data/things/860/Tibia.spr
        --preload-file=${CMAKE_SOURCE_DIR}/layouts@/layouts
        --preload-file=${CMAKE_SOURCE_DIR}/mods@/mods
        --preload-file=${CMAKE_SOURCE_DIR}/modules@/modules
        --exclude-file=*.bak
        --exclude-file=*.backup
        --exclude-file=*.rar
        --exclude-file=*.log
        --exclude-file=Thumbs.db
        # Windows startup artwork is separate from the web launcher's emblem.
        --exclude-file=*/images/splash.png
        # No production module/style references these ranking animations. Keep
        # their static backgrounds and every ranked HUD/cast/rank icon; native
        # assets are untouched. This removes 64.7 MiB of unused preload bytes.
        --exclude-file=*/ranked-queue/backgrounds/*-anim.png
        # The launcher supplies the verified package through the SDK's public
        # getPreloadedPackage hook. It uses the same IndexedDB cache format;
        # enabling the SDK cache too would read/concatenate the assets twice.
    )
    foreach(asset Tibia.otfi Tibia.otml)
        if(EXISTS "${ASTRA_WASM_THINGS_DIR}/${asset}")
            target_link_options(${PROJECT_NAME} PRIVATE "--preload-file=${ASTRA_WASM_THINGS_DIR}/${asset}@/data/things/860/${asset}")
        endif()
    endforeach()

    # Ninja does not infer dependencies hidden inside --preload-file. Track
    # every packaged asset so an incremental build cannot serve stale Lua,
    # shaders or UI files after a source edit.
    file(GLOB_RECURSE ASTRA_WASM_ASSET_FILES CONFIGURE_DEPENDS LIST_DIRECTORIES false
        "${CMAKE_SOURCE_DIR}/layouts/*"
        "${CMAKE_SOURCE_DIR}/mods/*"
        "${CMAKE_SOURCE_DIR}/modules/*"
    )
    # Glob only the data entries actually passed to --preload-file. Excluding
    # things after a recursive CONFIGURE_DEPENDS glob would still reconfigure
    # when files were added to an unselected pack.
    foreach(entry IN LISTS ASTRA_WASM_DATA_ENTRIES)
        get_filename_component(name "${entry}" NAME)
        if(NOT name STREQUAL "things")
            if(IS_DIRECTORY "${entry}")
                file(GLOB_RECURSE entry_files CONFIGURE_DEPENDS LIST_DIRECTORIES false "${entry}/*")
                list(APPEND ASTRA_WASM_ASSET_FILES ${entry_files})
            else()
                list(APPEND ASTRA_WASM_ASSET_FILES "${entry}")
            endif()
        endif()
    endforeach()
    list(APPEND ASTRA_WASM_ASSET_FILES "${CMAKE_SOURCE_DIR}/init.lua")
    list(APPEND ASTRA_WASM_ASSET_FILES "${CMAKE_SOURCE_DIR}/browser/shell.html")
    list(APPEND ASTRA_WASM_ASSET_FILES "${CMAKE_SOURCE_DIR}/tools/browser_manifest.py")
    file(GLOB ASTRA_WASM_THINGS_FILES CONFIGURE_DEPENDS "${ASTRA_WASM_THINGS_DIR}/Tibia.*")
    list(APPEND ASTRA_WASM_ASSET_FILES ${ASTRA_WASM_THINGS_FILES})
    list(REMOVE_ITEM ASTRA_WASM_ASSET_FILES "${CMAKE_SOURCE_DIR}/data/images/splash.png")
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
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND "${Python3_EXECUTABLE}" "${CMAKE_SOURCE_DIR}/tools/browser_manifest.py" "${CMAKE_BINARY_DIR}/dist"
        VERBATIM
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
