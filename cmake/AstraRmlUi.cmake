# RmlUi is additive: desktop GL and Windows ANGLE are supported; Web/mobile keep OTUI.
option(FRAMEWORK_RMLUI "Enable desktop RmlUi documents inside OTUI widgets" ON)
set(ASTRA_RMLUI_ENABLED OFF)
if(FRAMEWORK_RMLUI AND FRAMEWORK_GRAPHICS AND NOT WASM AND NOT ANDROID AND
        (NOT OPENGLES OR (WIN32 AND OPENGLES STREQUAL "2.0")))
    if(NOT LUAJIT)
        message(WARNING "Astra RmlUi requires the client LuaJIT ABI; keeping OTUI only (enable LUAJIT for RmlUi)")
    else()
        include(${CMAKE_CURRENT_LIST_DIR}/FetchRmlUi.cmake)
        list(APPEND framework_SOURCES
            ${CMAKE_CURRENT_SOURCE_DIR}/src/framework/rml/rmlbindings.cpp
            ${CMAKE_CURRENT_SOURCE_DIR}/src/framework/rml/rmlmanager.cpp
            ${CMAKE_CURRENT_SOURCE_DIR}/src/framework/rml/rmlrenderer.cpp
            ${CMAKE_CURRENT_SOURCE_DIR}/src/framework/rml/uirmlwidget.cpp
            ${CMAKE_CURRENT_SOURCE_DIR}/src/framework/rml/RmlUi_Renderer_GL3.cpp
            ${CMAKE_CURRENT_SOURCE_DIR}/src/client/rmlimages.cpp)
        list(APPEND framework_LIBRARIES RmlUi::RmlUi)
        add_definitions(-DFW_RMLUI)
        set(ASTRA_RMLUI_ENABLED ON)
    endif()
endif()
