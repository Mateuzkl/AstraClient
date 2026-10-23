// Native, driver-free integration test. Uses the actual engine event handlers,
// Lua fields, DOM dispatch, deferred context retirement and RmlUi 6.3.
#include <framework/global.h>
#include <RmlUi/Core.h>
#include <functional>
#include <framework/luaengine/luaobject.h>
#include <framework/graphics/bitmapfont.h>
#include <framework/core/eventdispatcher.h>
#include <framework/core/clock.h>
#define private public
#include <framework/graphics/fontmanager.h>
#include <framework/rml/uirmlwidget.h>
#include <framework/rml/rmlmanager.h>
#undef private
#include <cstdio>
#include <stdexcept>

namespace {
struct Host : UIRmlWidget {
    using UIRmlWidget::onMousePress;
    using UIRmlWidget::onMouseRelease;
    using UIRmlWidget::onMouseMove;
    using UIRmlWidget::onMouseWheel;
    using UIRmlWidget::onKeyText;
    using UIRmlWidget::onKeyPress;
    using UIRmlWidget::onKeyUp;
    using UIRmlWidget::onHoverChange;
    using UIRmlWidget::onFocusChange;
};
struct Listener : Rml::EventListener {
    std::function<void()> callback;
    void ProcessEvent(Rml::Event&) override { callback(); }
};
void check(bool value, const char* message) { if (!value) throw std::runtime_error(message); }

void inputCase(int kind)
{
    check(Rml::Initialise(), "RmlUi initialization failed");
    g_rml.m_initialized = true; // Fixture: no graphics context/shader initialization.
    g_rml.m_initFailed = false;
    auto host = std::make_shared<Host>();
    host->setRect(Rect(0, 0, 420, 280));
    auto* context = host->getContext();
    check(context != nullptr, "host context missing");
    // No draw/replay in this suite. All renderer release work must stay driver-free.
    host->m_renderer->m_glFailed = true;
    auto* doc = context->LoadDocumentFromMemory(R"(<rml><head><style>
        body { display: block; width: 420px; height: 280px; }
        input { display: block; width: 100px; height: 24px; }
        </style></head><body><input id="field" /></body></rml>)");
    check(doc != nullptr, "input document missing");
    host->m_document = doc;
    doc->Show(); context->Update();
    if (kind == 0) {
        for (int id = 0; id < 10000; ++id)
            check(bool(g_rml.loadImage("item/" + std::to_string(900000000 + id) + ".png")), "missing image placeholder failed");
        check(g_rml.m_virtualSources.size() == 10000 && g_rml.m_pendingImages.size() == 10000,
            "virtual image fixture did not exercise unique pending sources");
    }
    doc->GetElementById("field")->Focus();
    if (kind == 1 || kind >= 6) context->ProcessMouseMove(10, 10, 0);
    if (kind == 1) context->ProcessMouseButtonDown(0, 0);

    int closes = 0, late = 0;
    const char* event = kind == 1 ? "mouseup" : kind == 3 ? "keydown" :
        kind == 4 ? "keyup" : kind == 5 ? "textinput" : "mousemove";
    const char* base = kind == 0 ? "onMousePress" : kind == 1 ? "onMouseRelease" :
        kind == 2 ? "onMouseWheel" : kind == 3 ? "onKeyPress" : kind == 4 ? "onKeyUp" :
        kind == 5 ? "onKeyText" : "onMouseMove";
    Listener close;
    close.callback = [&] {
        ++closes;
        host->destroy();
        // destroy clears Lua fields; reattach a trap to catch native continuation.
        host->setLuaField(base, std::function<bool()>([&] { ++late; return false; }));
    };
    Listener afterBase;
    afterBase.callback = [&] { ++late; };
    if (kind >= 7) {
        doc->AddEventListener(kind == 7 ? "blur" : "mouseout", &afterBase, true);
        host->setLuaField(kind == 7 ? "onFocusChange" : "onHoverChange", close.callback);
    } else doc->AddEventListener(event, &close, true);
    switch (kind) {
        case 0: host->onMousePress({11,11}, Fw::MouseLeftButton); break;
        case 1: host->onMouseRelease({11,11}, Fw::MouseLeftButton); break;
        case 2: host->onMouseWheel({11,11}, Fw::MouseWheelDown); break;
        case 3: host->onKeyPress(Fw::KeyA, 0, 0); break;
        case 4: host->onKeyUp(Fw::KeyA, 0); break;
        case 5: host->onKeyText("a"); break;
        case 6: host->onMouseMove({11,11}, {1,1}); break;
        case 7: host->onFocusChange(false, Fw::OtherFocusReason); break;
        case 8: host->onHoverChange(false); break;
    }
    check(closes == 1 && host->isDestroyed(), "native input did not reach the destroy listener");
    check(late == 0, "native input called the base Lua handler after destruction");
    for (int tick = 0; tick < 100 && g_rml.getContextCount(); ++tick) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
        g_clock.update(); g_dispatcher.poll();
    }
    check(g_rml.getContextCount() == 0, "input destruction retained context");
    check(g_rml.m_virtualSources.empty() && g_rml.m_pendingImages.empty(), "closed renderer retained virtual sources/retries");
    g_rml.terminate();
    host->releaseLuaFieldsTable();
}
}
int main()
{
    g_fonts.m_fonts.push_back(std::make_shared<BitmapFont>("verdana-11px-rounded"));
    g_lua.init();
    g_lua.registerClass<UIWidget>();
    g_lua.registerClass<UIRmlWidget, UIWidget>();
    g_lua.registerClass<Host, UIRmlWidget>();
    try {
        for (int kind = 0; kind < 9; ++kind) inputCase(kind);
        g_lua.terminate();
        std::puts("RmlUi native input lifetime: PASS (9 real dispatch paths, 10000 missing image sources retired)");
        return 0;
    } catch (const std::exception& error) {
        std::fprintf(stderr, "RmlUi native input lifetime: FAIL: %s\n", error.what());
        g_rml.terminate();
        g_lua.terminate();
        return 1;
    }
}
