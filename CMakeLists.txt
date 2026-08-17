cmake_minimum_required(VERSION 3.16)
cmake_policy(VERSION 3.16)
project(AstraClient)

if(CMAKE_BASE_NAME STREQUAL "em++")
    set(WASM ON)
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

if(WIN32 AND NOT WINDOWS_CONSOLE)
    set_target_properties(${PROJECT_NAME} PROPERTIES WIN32_EXECUTABLE TRUE)
    if(MSVC)
        set_property(TARGET ${PROJECT_NAME} APPEND_STRING PROPERTY LINK_FLAGS " /ENTRY:mainCRTStartup")
    endif()
endif()

if(APPLE AND USE_STATIC_LIBS)
    target_link_libraries(${PROJECT_NAME} "-framework Foundation" "-framework IOKit")
endif()
