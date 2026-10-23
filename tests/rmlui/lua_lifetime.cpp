#include <RmlUi/Core.h>
#include <RmlUi/Lua.h>
#include <RmlUi/Lua/LuaType.h>
#include <RmlUi/Lua/IncludeLua.h>
#include <cstdio>
#include <memory>
#include <stdexcept>
#include <utility>

namespace Rml::Lua { RMLUI_LUATYPE_DECLARE(Rml::Context) }
namespace {
class NullRenderer final : public Rml::RenderInterface {
    Rml::CompiledGeometryHandle CompileGeometry(Rml::Span<const Rml::Vertex>, Rml::Span<const int>) override { return 0; }
    void RenderGeometry(Rml::CompiledGeometryHandle, Rml::Vector2f, Rml::TextureHandle) override {}
    void ReleaseGeometry(Rml::CompiledGeometryHandle) override {}
    Rml::TextureHandle LoadTexture(Rml::Vector2i&, const Rml::String&) override { return 0; }
    Rml::TextureHandle GenerateTexture(Rml::Span<const Rml::byte>, Rml::Vector2i) override { return 0; }
    void ReleaseTexture(Rml::TextureHandle) override {}
    void EnableScissorRegion(bool) override {}
    void SetScissorRegion(Rml::Rectanglei) override {}
};
struct RmlScope {
    bool active = true;
    void shutdown() { if (std::exchange(active, false)) Rml::Shutdown(); }
    ~RmlScope() { shutdown(); }
};
void run(lua_State* state, const char* source)
{
    if (luaL_dostring(state, source) != 0)
        throw std::runtime_error(lua_tostring(state, -1));
}
void expose(lua_State* state, const char* name, Rml::Context* context)
{
    if (!context) throw std::runtime_error("Could not create test context");
    Rml::Lua::LuaType<Rml::Context>::push(state, context, false);
    lua_setglobal(state, name);
}
}
int main()
{
    try {
        std::unique_ptr<lua_State, decltype(&lua_close)> state(luaL_newstate(), lua_close);
        luaL_openlibs(state.get());
        NullRenderer renderer;
        Rml::SetRenderInterface(&renderer);
        if (!Rml::Initialise()) throw std::runtime_error("RmlUi initialise failed");
        RmlScope scope;
        Rml::Lua::Initialise(state.get());
        expose(state.get(), "a", Rml::CreateContext("a", {1, 1}));
        expose(state.get(), "b", Rml::CreateContext("b", {1, 1}));
        run(state.get(), R"(
            local ma = a:OpenDataModel('shared', {value=1})
            local mb = b:OpenDataModel('shared', {value=2})
            assert(a:OpenDataModel('shared', {}) == ma)
            a:CloseDataModel('shared')
            a:CloseDataModel('shared')
            assert(not pcall(function() return ma.value end))
            assert(mb.value == 2, 'closing one context closed another context model')
            assert(a:OpenDataModel('shared', {value=3}).value == 3)
        )");
        Rml::RemoveContext("a");
        Rml::RemoveContext("b");
        run(state.get(), "a=nil; b=nil; payloads=setmetatable({}, {__mode='k'})");
        for (int cycle = 0; cycle < 1000; ++cycle) {
            expose(state.get(), "ctx", Rml::CreateContext("cycle", {1, 1}));
            run(state.get(), R"(
                local payload = {bytes=string.rep('x', 16384)}
                payloads[payload] = true
                model = ctx:OpenDataModel('cycle', {rows={{value=1}}, Hold=function() return payload end})
                child = model.rows[1]
                model = nil -- a nested proxy alone must keep the model userdata alive
                collectgarbage('collect')
                assert(child.value == 1)
            )");
            Rml::RemoveContext("cycle");
            run(state.get(), R"(
                ctx=nil
                collectgarbage('collect'); collectgarbage('collect')
                assert(next(payloads) == nil, 'destroyed context retained Lua callback payload')
                assert(not pcall(function() return child.value end))
                assert(not pcall(function() child.value=2 end))
                child=nil
                collectgarbage('collect'); collectgarbage('collect')
                assert(next(debug.getregistry().datamodels) == nil, 'context registry entry survived teardown')
            )");
        }
        expose(state.get(), "ctx", Rml::CreateContext("shutdown", {1, 1}));
        run(state.get(), R"(
            local payload = {}
            payloads[payload] = true
            model = ctx:OpenDataModel('shutdown', {Hold=function() return payload end})
        )");
        scope.shutdown(); // Close models before the external Lua VM is destroyed.
        run(state.get(), R"(
            ctx=nil
            collectgarbage('collect'); collectgarbage('collect')
            assert(next(payloads) == nil and next(debug.getregistry().datamodels) == nil)
            assert(not pcall(function() return model.Hold end))
        )");
        std::puts("RmlUi Lua lifetime: PASS (1000 cycles, shared names, duplicate opens, explicit close, nested proxy GC, shutdown)");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "RmlUi Lua lifetime: FAIL: %s\n", error.what());
        return 1;
    }
}
