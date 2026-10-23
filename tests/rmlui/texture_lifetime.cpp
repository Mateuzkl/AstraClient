#include <RmlUi/Core.h>
#include <cstdio>
#include <optional>
#include <stdexcept>
#include <unordered_set>

namespace {
void check(bool value, const char* message)
{
    if (!value) throw std::runtime_error(message);
}
class TestRenderer final : public Rml::RenderInterface {
public:
    explicit TestRenderer(unsigned id) : nextHandle(uintptr_t(id) * 1000000) {}
    std::unordered_set<uintptr_t> textures, geometries;
    unsigned loads = 0, draws = 0;
    Rml::CompiledGeometryHandle CompileGeometry(Rml::Span<const Rml::Vertex>, Rml::Span<const int>) override
    {
        const auto handle = ++nextHandle;
        geometries.insert(handle);
        return handle;
    }
    void RenderGeometry(Rml::CompiledGeometryHandle geometry, Rml::Vector2f, Rml::TextureHandle texture) override
    {
        check(geometries.contains(geometry), "geometry belongs to a different renderer");
        check(!texture || textures.contains(texture), "texture belongs to a retired/different renderer");
        ++draws;
    }
    void ReleaseGeometry(Rml::CompiledGeometryHandle handle) override
    {
        check(geometries.erase(handle) == 1, "geometry released twice/by the wrong renderer");
    }
    Rml::TextureHandle LoadTexture(Rml::Vector2i& size, const Rml::String&) override
    {
        ++loads;
        size = {32, 32};
        const auto handle = ++nextHandle;
        textures.insert(handle);
        return handle;
    }
    Rml::TextureHandle GenerateTexture(Rml::Span<const Rml::byte>, Rml::Vector2i) override
    {
        const auto handle = ++nextHandle;
        textures.insert(handle);
        return handle;
    }
    void ReleaseTexture(Rml::TextureHandle handle) override
    {
        check(textures.erase(handle) == 1, "texture released twice/by the wrong renderer");
    }
    void EnableScissorRegion(bool) override {}
    void SetScissorRegion(Rml::Rectanglei) override {}
private:
    uintptr_t nextHandle;
};
struct RmlScope { ~RmlScope() { Rml::Shutdown(); } };
}

int main()
{
    try {
        TestRenderer first(1), second(2);
        Rml::SetRenderInterface(&first);
        check(Rml::Initialise(), "RmlUi initialise failed");
        RmlScope scope;
        {
            Rml::TextureSource source("atlas.png", "/test.rml");
            // Deliberately reuse the exact manager address, independently of the
            // allocator. A pointer-keyed cache must not return the previous index.
            std::optional<Rml::RenderManager> manager;
            for (int cycle = 0; cycle < 1000; ++cycle) {
                manager.emplace(&first);
                check(source.GetTexture(*manager).GetDimensions() == Rml::Vector2i(32, 32), "stale texture source entry");
                manager.reset();
                check(first.textures.empty(), "texture survived manager destruction");
            }
        }
        auto* a = Rml::CreateContext("a", {64, 64}, &first);
        auto* b = Rml::CreateContext("b", {64, 64}, &second);
        check(a && b, "contexts not created");
        auto sheet = Rml::Factory::InstanceStyleSheetString(R"(
            @spritesheet test { src: atlas.png; icon: 0px 0px 32px 32px; }
            body { display: block; width: 64px; height: 64px; }
            div { display: block; width: 32px; height: 32px; decorator: image(icon); }
        )");
        check(bool(sheet), "stylesheet not created");
        constexpr auto document = "<rml><head></head><body><div/></body></rml>";
        auto* docA = a->LoadDocumentFromMemory(document);
        auto* docB = b->LoadDocumentFromMemory(document);
        check(docA && docB, "documents not created");
        docA->SetStyleSheetContainer(sheet);
        docB->SetStyleSheetContainer(sheet);
        docA->Show(); docB->Show();
        const auto loadsBeforeA = first.loads;
        a->Update(); a->Render();
        b->Update(); b->Render();
        check(first.loads > loadsBeforeA && second.loads == 1, "shared decorator crossed renderer ownership");
        check(first.draws > 0 && second.draws > 0, "decorators did not render");
        Rml::RemoveContext("a");
        Rml::ReleaseRenderManagers();
        check(first.textures.empty() && first.geometries.empty(), "closed context retained GPU resources");
        // Closing A must not invalidate the same atlas in the surviving B.
        b->Update(); b->Render();
        Rml::RemoveContext("b");
        Rml::ReleaseRenderManagers();
        check(second.textures.empty() && second.geometries.empty(), "second context retained GPU resources");
        for (int cycle = 0; cycle < 100; ++cycle) {
            auto* context = Rml::CreateContext("reopen", {64, 64}, &first);
            auto* doc = context->LoadDocumentFromMemory(document);
            check(doc != nullptr, "reopened document missing");
            doc->SetStyleSheetContainer(sheet); // Keep the spritesheet cached across closes.
            doc->Show(); context->Update(); context->Render();
            Rml::RemoveContext("reopen");
            Rml::ReleaseRenderManagers();
            check(first.textures.empty() && first.geometries.empty(), "reopen retained GPU resources");
        }
        sheet.reset();
        std::puts("RmlUi texture lifetime: PASS (1000 same-address managers, shared styles, 100 rendered reopens, resource balance)");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "RmlUi texture lifetime: FAIL: %s\n", error.what());
        return 1;
    }
}
