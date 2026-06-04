cmake_minimum_required(VERSION 2.6)
project(AstraClient)

if(CMAKE_BASE_NAME STREQUAL "em++")
    set(WASM ON)
endif()

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# default build type
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release")
endif()

option(FRAMEWORK_SOUND "Use SOUND " OFF)
option(FRAMEWORK_GRAPHICS "Use GRAPHICS " ON)
option(FRAMEWORK_XML "Use XML " ON)
option(FRAMEWORK_NET "Use NET " ON)
option(SPEED_UP_BUILD_UNITY "Compile AstraClient with CMake unity build for faster local builds" ON)

include(src/framework/CMakeLists.txt)
include(src/client/CMakeLists.txt)

# functions map for reading backtraces
if(NOT APPLE AND NOT WASM)
    set(CMAKE_CXX_LINK_FLAGS "${CMAKE_CXX_LINK_FLAGS} -no-pie -Wl,-Map=${PROJECT_NAME}.map")
endif()

set(executable_SOURCES
    src/main.cpp
)

# add executable icon for win32 platforms
if(WIN32)
    add_custom_command(OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/otcicon.o
                       COMMAND ${CMAKE_RC_COMPILER}
                       -I${CMAKE_CURRENT_SOURCE_DIR}/src
                       -i${CMAKE_CURRENT_SOURCE_DIR}/src/otcicon.rc
                       -o ${CMAKE_CURRENT_BINARY_DIR}/otcicon.o)
    set(executable_SOURCES ${executable_SOURCES} otcicon.o)
endif()

if(VERSION)
    add_definitions(-D"VERSION=\\"${VERSION}\\"")
endif()

# add client executable
add_executable(${PROJECT_NAME} ${framework_SOURCES} ${client_SOURCES} ${executable_SOURCES})
target_link_libraries(${PROJECT_NAME} ${framework_LIBRARIES})

if(SPEED_UP_BUILD_UNITY)
    set_target_properties(${PROJECT_NAME} PROPERTIES UNITY_BUILD ON)
    
    # Exclude luainterface.cpp from unity build to avoid undefined reference to g_lua
    set_source_files_properties(
        src/framework/luaengine/luainterface.cpp
        PROPERTIES SKIP_UNITY_BUILD_INCLUSION ON
    )
endif()

if(APPLE AND USE_STATIC_LIBS)
    target_link_libraries(${PROJECT_NAME} "-framework Foundation" "-framework IOKit")
endif()
