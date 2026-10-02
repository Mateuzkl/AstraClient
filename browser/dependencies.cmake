include(FetchContent)

# LuaJIT cannot target WebAssembly reliably. Browser builds use the official
# Lua 5.1.5 release and keep LuaJIT untouched for native targets.
FetchContent_Declare(lua51_source
    URL https://www.lua.org/ftp/lua-5.1.5.tar.gz
    URL_HASH SHA256=2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333
    DOWNLOAD_EXTRACT_TIMESTAMP FALSE
    PATCH_COMMAND
        "${CMAKE_COMMAND}"
        "-DLUA51_SOURCE_DIR=<SOURCE_DIR>/src"
        -P "${CMAKE_CURRENT_LIST_DIR}/lua51/apply_patch.cmake"
)
FetchContent_MakeAvailable(lua51_source)

set(ASTRA_LUA51_SOURCES
    ${lua51_source_SOURCE_DIR}/src/lapi.c
    ${lua51_source_SOURCE_DIR}/src/lcode.c
    ${lua51_source_SOURCE_DIR}/src/ldebug.c
    ${lua51_source_SOURCE_DIR}/src/ldo.c
    ${lua51_source_SOURCE_DIR}/src/ldump.c
    ${lua51_source_SOURCE_DIR}/src/lfunc.c
    ${lua51_source_SOURCE_DIR}/src/lgc.c
    ${lua51_source_SOURCE_DIR}/src/llex.c
    ${lua51_source_SOURCE_DIR}/src/lmem.c
    ${lua51_source_SOURCE_DIR}/src/lobject.c
    ${lua51_source_SOURCE_DIR}/src/lopcodes.c
    ${lua51_source_SOURCE_DIR}/src/lparser.c
    ${lua51_source_SOURCE_DIR}/src/lstate.c
    ${lua51_source_SOURCE_DIR}/src/lstring.c
    ${lua51_source_SOURCE_DIR}/src/ltable.c
    ${lua51_source_SOURCE_DIR}/src/ltm.c
    ${lua51_source_SOURCE_DIR}/src/lundump.c
    ${lua51_source_SOURCE_DIR}/src/lvm.c
    ${lua51_source_SOURCE_DIR}/src/lzio.c
    ${lua51_source_SOURCE_DIR}/src/lauxlib.c
    ${lua51_source_SOURCE_DIR}/src/lbaselib.c
    ${lua51_source_SOURCE_DIR}/src/ldblib.c
    ${lua51_source_SOURCE_DIR}/src/liolib.c
    ${lua51_source_SOURCE_DIR}/src/lmathlib.c
    ${lua51_source_SOURCE_DIR}/src/loslib.c
    ${lua51_source_SOURCE_DIR}/src/ltablib.c
    ${lua51_source_SOURCE_DIR}/src/lstrlib.c
    ${lua51_source_SOURCE_DIR}/src/loadlib.c
    ${lua51_source_SOURCE_DIR}/src/linit.c
)
add_library(astra-lua51 STATIC ${ASTRA_LUA51_SOURCES})
target_include_directories(astra-lua51 PUBLIC ${lua51_source_SOURCE_DIR}/src)
target_include_directories(astra-lua51 PRIVATE ${CMAKE_CURRENT_LIST_DIR}/lua51)
target_compile_definitions(astra-lua51 PRIVATE LUA_ANSI)
target_compile_options(astra-lua51 PRIVATE -pthread)

# PhysicsFS is the only non-Emscripten-port dependency needed by the browser
# resource layer. Pin the exact reviewed 3.2.0 commit instead of using a local
# precompiled archive or a machine-specific path.
set(PHYSFS_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(PHYSFS_BUILD_STATIC ON CACHE BOOL "" FORCE)
set(PHYSFS_BUILD_TEST OFF CACHE BOOL "" FORCE)
set(PHYSFS_BUILD_DOCS OFF CACHE BOOL "" FORCE)
set(PHYSFS_DISABLE_INSTALL ON CACHE BOOL "" FORCE)
set(PHYSFS_ARCHIVE_7Z OFF CACHE BOOL "" FORCE)
set(PHYSFS_ARCHIVE_GRP OFF CACHE BOOL "" FORCE)
set(PHYSFS_ARCHIVE_WAD OFF CACHE BOOL "" FORCE)
set(PHYSFS_ARCHIVE_HOG OFF CACHE BOOL "" FORCE)
set(PHYSFS_ARCHIVE_MVL OFF CACHE BOOL "" FORCE)
set(PHYSFS_ARCHIVE_QPAK OFF CACHE BOOL "" FORCE)
set(PHYSFS_ARCHIVE_SLB OFF CACHE BOOL "" FORCE)
set(PHYSFS_ARCHIVE_ISO9660 OFF CACHE BOOL "" FORCE)
set(PHYSFS_ARCHIVE_VDF OFF CACHE BOOL "" FORCE)
FetchContent_Declare(physfs
    GIT_REPOSITORY https://github.com/icculus/physfs.git
    GIT_TAG eb3383b532c5f74bfeb42ec306ba2cf80eed988c
    GIT_PROGRESS TRUE
)
FetchContent_MakeAvailable(physfs)
target_compile_options(physfs-static PRIVATE -pthread)
