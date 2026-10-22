// Adapted from fellipealbuquerque/otclient-rmlui, MIT (see RMLUI_LICENSE.txt).
#include "rmlmanager.h"
#include "uirmlwidget.h"
#include <framework/luaengine/luainterface.h>
#include <RmlUi/Core/Context.h>
#include <RmlUi/Core/ElementDocument.h>
#include <RmlUi/Lua/LuaType.h>
namespace Rml::Lua {
    RMLUI_LUATYPE_DECLARE(Rml::Context)
    RMLUI_LUATYPE_DECLARE(Rml::ElementDocument)
}
void registerRmlLuaFunctions()
{
    // RmlUi (HTML/CSS documents inside OTUI), same API as Ninja World Online's client
    g_lua.registerSingletonClass("g_rml");
    g_lua.bindSingletonFunction("g_rml", "isReady", &RmlManager::isReady, &g_rml);
    g_lua.bindSingletonFunction("g_rml", "supportsAdvancedEffects", &RmlManager::supportsAdvancedEffects, &g_rml);
    g_lua.bindSingletonFunction("g_rml", "getBackendName", &RmlManager::getBackendName, &g_rml);
    g_lua.bindSingletonFunction("g_rml", "setReportEnabled", &RmlManager::setReportEnabled, &g_rml);
    g_lua.bindSingletonFunction("g_rml", "isReportEnabled", &RmlManager::isReportEnabled, &g_rml);
    g_lua.bindSingletonFunction("g_rml", "loadFontFace", &RmlManager::loadFontFace, &g_rml);
    g_lua.bindClassStaticFunction("g_rml", "utf8", [](const std::string& text) { return RmlManager::utf8(text); });
    g_lua.bindClassStaticFunction("g_rml", "latin1", [](const std::string& text) { return RmlManager::latin1(text); });
    g_lua.bindSingletonFunction("g_rml", "getWidgetCount", &RmlManager::getWidgetCount, &g_rml);
    g_lua.bindSingletonFunction("g_rml", "getContextCount", &RmlManager::getContextCount, &g_rml);
    g_lua.bindSingletonFunction("g_rml", "getWidgets", &RmlManager::getWidgets, &g_rml);

    g_lua.registerClass<UIRmlWidget, UIWidget>();
    g_lua.bindClassStaticFunction<UIRmlWidget>("create", [] { return std::make_shared<UIRmlWidget>(); });
    g_lua.bindClassMemberFunction<UIRmlWidget>("loadDocument", &UIRmlWidget::loadDocument);
    g_lua.bindClassMemberFunction<UIRmlWidget>("unloadDocument", &UIRmlWidget::unloadDocument);
    g_lua.bindClassMemberFunction<UIRmlWidget>("reloadDocument", &UIRmlWidget::reloadDocument);
    g_lua.bindClassMemberFunction<UIRmlWidget>("hasDocument", &UIRmlWidget::hasDocument);
    g_lua.bindClassMemberFunction<UIRmlWidget>("getDocumentPath", &UIRmlWidget::getDocumentPath);
    g_lua.bindClassMemberFunction<UIRmlWidget>("setDebuggerVisible", &UIRmlWidget::setDebuggerVisible);
    g_lua.bindClassMemberFunction<UIRmlWidget>("isDebuggerVisible", &UIRmlWidget::isDebuggerVisible);
    g_lua.bindClassMemberFunction<UIRmlWidget>("setExtraStyleSheet", &UIRmlWidget::setExtraStyleSheet);
    // these return objects of the RmlUi Lua plugin (Document / Context)
    g_lua.registerClassMemberFunction<UIRmlWidget>("getDocument", [](LuaInterface* lua) -> int {
        const auto widget = std::dynamic_pointer_cast<UIRmlWidget>(lua->popObject());
        auto* document = widget ? widget->getDocument() : nullptr;
        if (!document) {
            lua->pushNil();
            return 1;
        }
        Rml::Lua::LuaType<Rml::ElementDocument>::push(lua->getLuaState(), document, false);
        return 1;
    });
    g_lua.registerClassMemberFunction<UIRmlWidget>("getContext", [](LuaInterface* lua) -> int {
        const auto widget = std::dynamic_pointer_cast<UIRmlWidget>(lua->popObject());
        auto* context = widget ? widget->getContext() : nullptr;
        if (!context) {
            lua->pushNil();
            return 1;
        }
        Rml::Lua::LuaType<Rml::Context>::push(lua->getLuaState(), context, false);
        return 1;
    });

}
