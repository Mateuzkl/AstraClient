include(FetchContent)
if(NOT TARGET LuaJIT::LuaJIT)
    add_library(LuaJIT::LuaJIT INTERFACE IMPORTED)
    set_target_properties(LuaJIT::LuaJIT PROPERTIES
        INTERFACE_LINK_LIBRARIES "${LUA_LIBRARY}"
        INTERFACE_INCLUDE_DIRECTORIES "${LUA_INCLUDE_DIR}")
endif()
# Options are scoped: do not alter the client's runtime or shared-library policy.
function(astra_fetch_rmlui)
    set(BUILD_SHARED_LIBS OFF)
    set(RMLUI_LUA_BINDINGS ON CACHE BOOL "" FORCE)
    set(RMLUI_LUA_BINDINGS_LIBRARY luajit CACHE STRING "" FORCE)
    set(RMLUI_SAMPLES OFF CACHE BOOL "" FORCE)
    set(RMLUI_FONT_ENGINE freetype CACHE STRING "" FORCE)
    set(RMLUI_COMPILER_OPTIONS OFF CACHE BOOL "" FORCE)
    set(RMLUI_INSTALL_RUNTIME_DEPENDENCIES OFF CACHE BOOL "" FORCE)
    FetchContent_Declare(rmlui
        GIT_REPOSITORY https://github.com/mikke89/RmlUi.git
        GIT_TAG ba95ffe8bfb6370efb2cdcca927eaad4710c5413) # 6.3
    FetchContent_MakeAvailable(rmlui)
    include(${CMAKE_CURRENT_FUNCTION_LIST_DIR}/PatchRmlUiLua.cmake)
    astra_patch_rmlui_lua("${rmlui_SOURCE_DIR}")
    include(${CMAKE_CURRENT_FUNCTION_LIST_DIR}/PatchRmlUiTextures.cmake)
    astra_patch_rmlui_textures("${rmlui_SOURCE_DIR}")
endfunction()
astra_fetch_rmlui()
