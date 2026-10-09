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

if(WIN32)
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:${PROJECT_NAME}>/data/json"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CMAKE_SOURCE_DIR}/data/json/default-options.json"
            "$<TARGET_FILE_DIR:${PROJECT_NAME}>/data/json/default-options.json"
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
