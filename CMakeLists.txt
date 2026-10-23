cmake_minimum_required(VERSION 3.24)
cmake_policy(VERSION 3.24)
project(AstraClient LANGUAGES C CXX)

if(EMSCRIPTEN OR CMAKE_SYSTEM_NAME STREQUAL "Emscripten")
    set(WASM ON)
    message(STATUS "Browser/WebAssembly target: ON")
endif()

include(cmake/AstraCxx23.cmake)

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
include(cmake/AstraRmlUi.cmake)

# functions map for reading backtraces (flags do linker GNU; nao aplicar no MSVC)
if(NOT APPLE AND NOT WASM AND NOT MSVC AND NOT ANDROID)
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
if(ANDROID)
    add_library(${PROJECT_NAME} SHARED ${framework_SOURCES} ${client_SOURCES} ${executable_SOURCES}
        src/android/android_native_app_glue.cpp)
    set_target_properties(${PROJECT_NAME} PROPERTIES OUTPUT_NAME otclientv8)
    target_compile_options(${PROJECT_NAME} PRIVATE
        "$<$<COMPILE_LANGUAGE:CXX>:-include;${CMAKE_SOURCE_DIR}/src/android/pch.h>")
    target_include_directories(${PROJECT_NAME} PRIVATE src/android)
    target_link_options(${PROJECT_NAME} PRIVATE -Wl,-u,ANativeActivity_onCreate)
    set_property(GLOBAL APPEND PROPERTY JOB_POOLS astra_android_compile=2)
    set_property(TARGET ${PROJECT_NAME} PROPERTY JOB_POOL_COMPILE astra_android_compile)
else()
    add_executable(${PROJECT_NAME} ${framework_SOURCES} ${client_SOURCES} ${executable_SOURCES})
endif()
set_target_properties(${PROJECT_NAME} PROPERTIES
    CXX_STANDARD 23 CXX_STANDARD_REQUIRED YES CXX_EXTENSIONS NO)
target_link_libraries(${PROJECT_NAME} ${framework_LIBRARIES})

include(CTest)

option(ASTRA_BUILD_SPECTATOR_TESTS "Build focused native spectator regression/benchmark harness" OFF)
if(ASTRA_BUILD_SPECTATOR_TESTS AND NOT WASM)
    enable_testing()
    set(spectator_test_SOURCES ${client_SOURCES})
    list(REMOVE_ITEM spectator_test_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/src/client/map.cpp")
    add_executable(astra_spectator_tests ${framework_SOURCES} ${spectator_test_SOURCES} tests/spectators/spectator_tests.cpp)
    target_link_libraries(astra_spectator_tests ${framework_LIBRARIES})
    add_test(NAME spectators COMMAND astra_spectator_tests)
endif()

if(BUILD_TESTING)
    if(ASTRA_RMLUI_ENABLED)
        add_executable(astra_rmlui_lua_lifetime tests/rmlui/lua_lifetime.cpp)
        target_link_libraries(astra_rmlui_lua_lifetime PRIVATE RmlUi::Lua)
        add_test(NAME rmlui-lua-lifetime COMMAND astra_rmlui_lua_lifetime)
        add_executable(astra_rmlui_texture_lifetime tests/rmlui/texture_lifetime.cpp)
        target_link_libraries(astra_rmlui_texture_lifetime PRIVATE RmlUi::Core)
        add_test(NAME rmlui-texture-lifetime COMMAND astra_rmlui_texture_lifetime)
    endif()
    add_executable(astra_command_pool tests/rendering/command_pool.cpp)
    target_include_directories(astra_command_pool PRIVATE src)
    add_executable(astra_line_geometry tests/rendering/line_geometry.cpp)
    target_include_directories(astra_line_geometry PRIVATE src)
    if(MSVC)
        target_compile_options(astra_command_pool PRIVATE /Zc:__cplusplus)
        target_compile_options(astra_line_geometry PRIVATE /Zc:__cplusplus)
    endif()
    if(NOT WASM)
        add_test(NAME render-command-pool COMMAND astra_command_pool)
        add_test(NAME render-line-geometry COMMAND astra_line_geometry)
    endif()
    add_executable(astra_rmlui_backend tests/rmlui/backend.cpp)
    target_include_directories(astra_rmlui_backend PRIVATE src)
    add_executable(astra_rmlui_pixels tests/rmlui/pixels.cpp)
    target_include_directories(astra_rmlui_pixels PRIVATE src)
    add_executable(astra_rmlui_gl_state tests/rmlui/gl_state.cpp)
    target_include_directories(astra_rmlui_gl_state PRIVATE src)
    if(MSVC)
        target_compile_options(astra_rmlui_backend PRIVATE /Zc:__cplusplus)
        target_compile_options(astra_rmlui_pixels PRIVATE /Zc:__cplusplus)
    endif()
    if(NOT WASM)
        add_test(NAME rmlui-backend-capabilities COMMAND astra_rmlui_backend)
        add_test(NAME rmlui-alpha-composition COMMAND astra_rmlui_pixels)
        add_test(NAME rmlui-gl-state COMMAND astra_rmlui_gl_state)
        add_test(NAME rmlui-luajit-fallback COMMAND ${CMAKE_COMMAND} -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/rmlui/cmake-fallback.cmake)
    endif()
    add_executable(astra_cxx23_probe tests/cpp23/standard.cpp)
    target_include_directories(astra_cxx23_probe PRIVATE src)
    add_executable(astra_utf8_path_test tests/cpp23/utf8_path.cpp)
    target_include_directories(astra_utf8_path_test PRIVATE src)
    if(FRAMEWORK_XML)
        add_executable(astra_cpp23_compatibility tests/cpp23/compatibility.cpp
            src/framework/xml/tinyxml.cpp src/framework/xml/tinyxmlparser.cpp
            src/framework/xml/tinyxmlerror.cpp src/framework/xml/tinystr.cpp)
        target_include_directories(astra_cpp23_compatibility PRIVATE src)
        if(WASM)
            # TinyXML includes the framework's ASIO/thread declarations too.
            target_compile_options(astra_cpp23_compatibility PRIVATE -pthread)
            target_link_options(astra_cpp23_compatibility PRIVATE -pthread)
        endif()
        if(NOT WASM)
            add_test(NAME cxx23-tinyxml COMMAND astra_cpp23_compatibility)
        endif()
    endif()
    if(MSVC)
        target_compile_options(astra_cxx23_probe PRIVATE /Zc:__cplusplus)
        target_compile_options(astra_utf8_path_test PRIVATE /Zc:__cplusplus /utf-8)
    endif()
    if(NOT WASM)
        add_test(NAME cxx23-standard COMMAND astra_cxx23_probe)
        add_test(NAME cxx23-utf8-path COMMAND astra_utf8_path_test)
    endif()
endif()
if(MSVC)
    target_compile_options(${PROJECT_NAME} PRIVATE /Zc:__cplusplus)
endif()

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
    configure_file(browser/security.js "${CMAKE_BINARY_DIR}/dist/security.js" COPYONLY)
    configure_file(browser/bootstrap.js "${CMAKE_BINARY_DIR}/dist/bootstrap.js" COPYONLY)
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

    # Lista revisavel: um arquivo novo nunca entra automaticamente no pacote.
    find_program(ASTRA_NODE_EXECUTABLE NAMES node nodejs REQUIRED)
    set(ASTRA_WEB_POLICY "${CMAKE_SOURCE_DIR}/browser/production-assets.json")
    set(ASTRA_WEB_TOOL "${CMAKE_SOURCE_DIR}/tools/browser_bundle.cjs")
    execute_process(COMMAND "${ASTRA_NODE_EXECUTABLE}" "${ASTRA_WEB_TOOL}" stage-path
        "${CMAKE_SOURCE_DIR}" "${CMAKE_BINARY_DIR}"
        OUTPUT_VARIABLE ASTRA_WEB_STAGE OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE ASTRA_WEB_STAGE_PATH_RESULT)
    if(NOT ASTRA_WEB_STAGE_PATH_RESULT EQUAL 0)
        message(FATAL_ERROR "Nao foi possivel selecionar staging fora da origem")
    endif()
    execute_process(COMMAND "${ASTRA_NODE_EXECUTABLE}" "${ASTRA_WEB_TOOL}" stage
        "${CMAKE_SOURCE_DIR}" "${ASTRA_WEB_POLICY}" "${ASTRA_WEB_STAGE}" "${ASTRA_WASM_THINGS_DIR}"
        RESULT_VARIABLE ASTRA_WEB_STAGE_RESULT)
    if(NOT ASTRA_WEB_STAGE_RESULT EQUAL 0)
        message(FATAL_ERROR "A lista de assets Web falhou na validacao")
    endif()
    include("${ASTRA_WEB_STAGE}/dependencies.cmake")
    # Arquivos opcionais do pack escolhido podem aparecer numa compilacao incremental.
    file(GLOB ASTRA_SELECTED_THINGS CONFIGURE_DEPENDS
        "${ASTRA_WASM_THINGS_DIR}/Tibia.dat" "${ASTRA_WASM_THINGS_DIR}/Tibia.spr"
        "${ASTRA_WASM_THINGS_DIR}/Tibia.otfi" "${ASTRA_WASM_THINGS_DIR}/Tibia.otml")
    list(APPEND ASTRA_WASM_ASSET_FILES ${ASTRA_SELECTED_THINGS})
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${ASTRA_WEB_POLICY}" "${ASTRA_WEB_TOOL}")
    add_custom_target(astra_web_assets
        COMMAND "${ASTRA_NODE_EXECUTABLE}" "${ASTRA_WEB_TOOL}" stage
            "${CMAKE_SOURCE_DIR}" "${ASTRA_WEB_POLICY}" "${ASTRA_WEB_STAGE}" "${ASTRA_WASM_THINGS_DIR}"
        VERBATIM)
    add_dependencies(${PROJECT_NAME} astra_web_assets)
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
        "-sEXPORTED_FUNCTIONS=['_main','_malloc','_free']"
        -sDYNAMIC_EXECUTION=0
        -lidbfs.js
        -lwebsocket.js
        --shell-file=${CMAKE_SOURCE_DIR}/browser/shell.html
        "@${ASTRA_WEB_STAGE}/preload.rsp"
        # The launcher supplies the verified package through the SDK's public
        # getPreloadedPackage hook. It uses the same IndexedDB cache format;
        # enabling the SDK cache too would read/concatenate the assets twice.
    )
    # Dependencias exatas; packs nao selecionados nao provocam relink/reconfigure.
    list(APPEND ASTRA_WASM_ASSET_FILES "${CMAKE_SOURCE_DIR}/browser/shell.html"
        "${CMAKE_SOURCE_DIR}/tools/browser_manifest.py" "${ASTRA_WEB_TOOL}" "${ASTRA_WEB_POLICY}")
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
        COMMAND "${ASTRA_NODE_EXECUTABLE}" "${ASTRA_WEB_TOOL}" audit
            "${CMAKE_SOURCE_DIR}" "${ASTRA_WEB_POLICY}" "${CMAKE_BINARY_DIR}/dist" "${ASTRA_WASM_THINGS_DIR}"
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
