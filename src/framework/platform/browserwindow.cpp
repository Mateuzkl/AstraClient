#ifdef __EMSCRIPTEN__

#include "browserwindow.h"
#include "browsercursor.h"
#include "browserkeyboard.h"

#include <framework/core/application.h>
#include <framework/core/clock.h>
#include <framework/core/eventdispatcher.h>
#include <framework/graphics/image.h>
#include <framework/ui/uimanager.h>
#include <framework/ui/uitextedit.h>

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <emscripten/emscripten.h>
#include <emscripten/threading.h>
#include <functional>
#include <GLES2/gl2.h>
#include <sstream>

namespace
{
constexpr const char *CanvasSelector = "#canvas";

bool isSingleUtf8Character(const std::string &text)
{
    if (text.empty())
        return false;
    size_t characters = 0;
    for (const unsigned char value : text) {
        if ((value & 0xc0) != 0x80)
            ++characters;
    }
    return characters == 1;
}

void browserInstallTextBridge()
{
    // clang-format off
    MAIN_THREAD_EM_ASM({
    if (!Module.astraRemoveTextBridge)
        Module.astraRemoveTextBridge = AstraBrowser.installTextBridge(Module);
    });
    // clang-format on
}

void browserRemoveTextBridge()
{
    // clang-format off
    MAIN_THREAD_EM_ASM({
    if (Module.astraRemoveTextBridge)
        Module.astraRemoveTextBridge();
    Module.astraRemoveTextBridge = null;
    if (Module.astraCursorManager)
        Module.astraCursorManager.dispose();
    Module.astraCursorManager = null;
    });
    // clang-format on
}

void browserSetTitle(const char *title)
{
    // clang-format off
    MAIN_THREAD_EM_ASM({ document.title = UTF8ToString($0); }, title);
    // clang-format on
}

void browserSetCursor(const char *cursor)
{
    // clang-format off
    MAIN_THREAD_EM_ASM({
    const cursors = Module.astraCursorManager ||
        (Module.astraCursorManager = AstraBrowser.createCursorManager());
    cursors.setSystemCursor(UTF8ToString($0));
    }, cursor);
    // clang-format on
}

bool browserCreateCursor(int id, const unsigned char *pixels, int width, int height, int hotX, int hotY)
{
    // clang-format off
    return MAIN_THREAD_EM_ASM_INT({
    const cursors = Module.astraCursorManager ||
        (Module.astraCursorManager = AstraBrowser.createCursorManager());
    return cursors.createCursor($0, HEAPU8.subarray($1, $1 + $2 * $3 * 4), $2, $3, $4, $5) ? 1 : 0;
    }, id, pixels, width, height, hotX, hotY) != 0;
    // clang-format on
}

void browserUseCursor(int id)
{
    // clang-format off
    MAIN_THREAD_EM_ASM({
    const cursors = Module.astraCursorManager ||
        (Module.astraCursorManager = AstraBrowser.createCursorManager());
    cursors.useCursor($0);
    }, id);
    // clang-format on
}

void browserSetVisible(int visible)
{
    // clang-format off
    MAIN_THREAD_EM_ASM({
    const canvas = document.getElementById('canvas');
    if (canvas)
        canvas.style.visibility = $0 ? 'visible' : 'hidden';
    }, visible);
    // clang-format on
}

void browserShowFatalError(const char *message)
{
    // clang-format off
    MAIN_THREAD_EM_ASM({
    if (Module.astraShowError)
        Module.astraShowError(UTF8ToString($0));
    else
        console.error(UTF8ToString($0));
    }, message);
    // clang-format on
}

std::string jsonEscape(const std::string &input)
{
    std::string out;
    out.reserve(input.size() + 8);
    for (const unsigned char ch : input) {
        switch (ch) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (ch < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", static_cast<unsigned int>(ch));
                    out += buf;
                } else {
                    out.push_back(static_cast<char>(ch));
                }
                break;
        }
    }
    return out;
}

bool isNumericTextEdit(UITextEdit *edit)
{
    if (!edit)
        return false;
    const std::string &valid = edit->getValidCharacters();
    if (!valid.empty()) {
        bool hasDigit = false;
        for (unsigned char c : valid) {
            if (std::isdigit(c)) {
                hasDigit = true;
            } else if (c != '-' && c != '.' && c != ',') {
                return false;
            }
        }
        if (hasDigit)
            return true;
    }
    std::string id = edit->getId();
    std::transform(id.begin(), id.end(), id.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return id.find("token") != std::string::npos || id.find("number") != std::string::npos;
}

bool isEmailTextEdit(UITextEdit *edit)
{
    if (!edit)
        return false;
    std::string id = edit->getId();
    std::transform(id.begin(), id.end(), id.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return id.find("email") != std::string::npos || id.find("accountname") != std::string::npos;
}

void browserShowVirtualKeyboard(const char *metaJson)
{
    // clang-format off
    MAIN_THREAD_EM_ASM({
    const json = UTF8ToString($0);
    if (window.AstraBrowser && typeof window.AstraBrowser.showMobileKeyboard === 'function') {
        window.AstraBrowser.showMobileKeyboard(json);
        return;
    }
    const editor = document.getElementById('astra-virtual-keyboard');
    if (!editor)
        return;
    let text = json;
    try {
        const parsed = JSON.parse(json);
        if (parsed && typeof parsed.text === 'string') text = parsed.text;
    } catch (_) {}
    editor.value = text;
    editor.focus({preventScroll: true});
    editor.setSelectionRange(editor.value.length, editor.value.length);
    if (navigator.virtualKeyboard && navigator.virtualKeyboard.show)
        navigator.virtualKeyboard.show();
    }, metaJson);
    // clang-format on
}

void browserSyncFocusedTextInput(const char *metaJson)
{
    // clang-format off
    MAIN_THREAD_EM_ASM({
    if (window.AstraBrowser && typeof window.AstraBrowser.syncFocusedTextInput === 'function') {
        window.AstraBrowser.syncFocusedTextInput(UTF8ToString($0));
    }
    }, metaJson);
    // clang-format on
}

void browserHideVirtualKeyboard()
{
    // clang-format off
    MAIN_THREAD_ASYNC_EM_ASM({
    if (window.AstraBrowser && typeof window.AstraBrowser.hideMobileKeyboard === 'function') {
        window.AstraBrowser.hideMobileKeyboard();
    }
    });
    // clang-format on
}

void browserUpdateTextInputRects(const char *rectsJson)
{
    // clang-format off
    MAIN_THREAD_EM_ASM({
    if (window.AstraBrowser && typeof window.AstraBrowser.updateTextInputRects === 'function') {
        window.AstraBrowser.updateTextInputRects(UTF8ToString($0));
    }
    }, rectsJson);
    // clang-format on
}

} // namespace

BrowserWindow &g_browserWindow = static_cast<BrowserWindow &>(g_window);

BrowserWindow::BrowserWindow() : m_webKeyMap(astra_browser::createKeyMap())
{
    m_minimumSize = Size(640, 360);
    m_size = Size(1280, 720);

}

void BrowserWindow::init()
{
    EmscriptenWebGLContextAttributes attributes;
    emscripten_webgl_init_context_attributes(&attributes);
    attributes.alpha = EM_TRUE;
    attributes.depth = EM_FALSE;
    attributes.stencil = EM_FALSE;
    attributes.antialias = EM_FALSE;
    attributes.premultipliedAlpha = EM_TRUE;
    attributes.preserveDrawingBuffer = EM_FALSE;
    attributes.enableExtensionsByDefault = EM_TRUE;
    attributes.majorVersion = 2;
    attributes.minorVersion = 0;
    attributes.explicitSwapControl = EM_TRUE;

    m_context = emscripten_webgl_create_context(CanvasSelector, &attributes);
    if (m_context <= 0)
        g_logger.fatal("Unable to create a WebGL2 context. WebGL2 may be unavailable or disabled.");
    if (emscripten_webgl_make_context_current(m_context) != EMSCRIPTEN_RESULT_SUCCESS)
        g_logger.fatal("Unable to activate the browser WebGL2 context.");

    if (g_app.isMobile() && m_maxPixelRatio <= 0.0f)
        m_maxPixelRatio = 1.75f;

    updateCanvasSize();
    installCallbacks();
    browserInstallTextBridge();
    restoreMouseCursor();
    m_created = true;
    m_visible = true;
    m_focused = true;
    m_verticalSync = true;
    m_verticalSyncApplied = true;
    m_contextLost = false;
}

void BrowserWindow::terminate()
{
    if (!m_created)
        return;
    removeCallbacks();
    browserRemoveTextBridge();
    if (m_context > 0) {
        emscripten_webgl_destroy_context(m_context);
        m_context = 0;
    }
    m_visible = false;
    m_focused = false;
    m_created = false;
}

void BrowserWindow::installCallbacks()
{
    if (m_callbacksInstalled)
        return;
    m_callbacksInstalled = true;

    emscripten_set_mousedown_callback(CanvasSelector, this, EM_TRUE,
                                      [](int type, const EmscriptenMouseEvent *event, void *data) -> EM_BOOL {
                                          static_cast<BrowserWindow *>(data)->dispatchMouseButton(type, *event);
                                          return EM_TRUE;
                                      });
    emscripten_set_mouseup_callback(CanvasSelector, this, EM_TRUE,
                                    [](int type, const EmscriptenMouseEvent *event, void *data) -> EM_BOOL {
                                        static_cast<BrowserWindow *>(data)->dispatchMouseButton(type, *event);
                                        return EM_TRUE;
                                    });
    emscripten_set_mousemove_callback(
        CanvasSelector, this, EM_TRUE, [](int, const EmscriptenMouseEvent *event, void *data) -> EM_BOOL {
            static_cast<BrowserWindow *>(data)->dispatchMouseMove(event->targetX, event->targetY);
            return EM_TRUE;
        });
    emscripten_set_wheel_callback(CanvasSelector, this, EM_TRUE,
                                  [](int, const EmscriptenWheelEvent *event, void *data) -> EM_BOOL {
                                      static_cast<BrowserWindow *>(data)->dispatchWheel(
                                          event->deltaY, event->mouse.targetX, event->mouse.targetY);
                                      return EM_TRUE;
                                  });
    astra_browser::installKeyboardCallbacks(
        this,
        [](int type, const EmscriptenKeyboardEvent *event, void *data) -> EM_BOOL {
            auto *window = static_cast<BrowserWindow *>(data);
            const int policy = astra_browser::keyboardPolicy(*event, window->m_webKeyMap.count(event->code) != 0);
            if (policy & astra_browser::DispatchKey)
                window->dispatchKeyboard(type, event->code, event->key, event->repeat, event->ctrlKey,
                                         event->altKey, event->shiftKey, event->metaKey);
            return (policy & astra_browser::ConsumeKey) != 0;
        });
    emscripten_set_resize_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, this, EM_TRUE,
                                   [](int, const EmscriptenUiEvent *, void *data) -> EM_BOOL {
                                       static_cast<BrowserWindow *>(data)->updateCanvasSize();
                                       return EM_TRUE;
                                   });
    emscripten_set_focus_callback_on_thread(EMSCRIPTEN_EVENT_TARGET_WINDOW, this, EM_TRUE,
                                  [](int, const EmscriptenFocusEvent *, void *data) -> EM_BOOL {
                                      static_cast<BrowserWindow *>(data)->dispatchFocus(true);
                                      return EM_TRUE;
                                  }, EM_CALLBACK_THREAD_CONTEXT_MAIN_RUNTIME_THREAD);
    emscripten_set_blur_callback_on_thread(EMSCRIPTEN_EVENT_TARGET_WINDOW, this, EM_TRUE,
                                 [](int, const EmscriptenFocusEvent *, void *data) -> EM_BOOL {
                                     static_cast<BrowserWindow *>(data)->dispatchFocus(false);
                                     return EM_TRUE;
                                 }, EM_CALLBACK_THREAD_CONTEXT_MAIN_RUNTIME_THREAD);
    auto forwardTouch = [](int type, const EmscriptenTouchEvent *event, void *data) -> EM_BOOL {
        std::vector<TouchSample> samples;
        samples.reserve(static_cast<size_t>(std::max(0, event->numTouches)));
        for (int i = 0; i < event->numTouches; ++i) {
            const auto &touch = event->touches[i];
            samples.push_back(TouchSample{touch.identifier, static_cast<double>(touch.targetX),
                                          static_cast<double>(touch.targetY), touch.isChanged != 0});
        }
        static_cast<BrowserWindow *>(data)->dispatchTouchEvent(type, std::move(samples));
        return EM_TRUE;
    };
    emscripten_set_touchstart_callback(CanvasSelector, this, EM_TRUE, forwardTouch);
    emscripten_set_touchmove_callback(CanvasSelector, this, EM_TRUE, forwardTouch);
    emscripten_set_touchend_callback(CanvasSelector, this, EM_TRUE, forwardTouch);
    emscripten_set_touchcancel_callback(CanvasSelector, this, EM_TRUE, forwardTouch);
}

void BrowserWindow::removeCallbacks()
{
    if (!m_callbacksInstalled)
        return;
    m_callbacksInstalled = false;
    emscripten_set_mousedown_callback(CanvasSelector, nullptr, EM_TRUE, nullptr);
    emscripten_set_mouseup_callback(CanvasSelector, nullptr, EM_TRUE, nullptr);
    emscripten_set_mousemove_callback(CanvasSelector, nullptr, EM_TRUE, nullptr);
    emscripten_set_wheel_callback(CanvasSelector, nullptr, EM_TRUE, nullptr);
    astra_browser::installKeyboardCallbacks(nullptr, nullptr);
    emscripten_set_resize_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, nullptr, EM_TRUE, nullptr);
    emscripten_set_focus_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, nullptr, EM_TRUE, nullptr);
    emscripten_set_blur_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, nullptr, EM_TRUE, nullptr);
    emscripten_set_touchstart_callback(CanvasSelector, nullptr, EM_TRUE, nullptr);
    emscripten_set_touchmove_callback(CanvasSelector, nullptr, EM_TRUE, nullptr);
    emscripten_set_touchend_callback(CanvasSelector, nullptr, EM_TRUE, nullptr);
    emscripten_set_touchcancel_callback(CanvasSelector, nullptr, EM_TRUE, nullptr);
}

void BrowserWindow::setMaxPixelRatio(float maxRatio)
{
    const float clamped = maxRatio > 0.0f ? std::clamp(maxRatio, 0.5f, 4.0f) : 0.0f;
    if (std::fabs(clamped - m_maxPixelRatio) < 0.001f)
        return;
    m_maxPixelRatio = clamped;
    if (m_created) {
        g_graphicsDispatcher.addEvent([this] { updateCanvasSize(); });
    }
}

void BrowserWindow::updateCanvasSize()
{
    double cssWidth = 0;
    double cssHeight = 0;
    if (emscripten_get_element_css_size(CanvasSelector, &cssWidth, &cssHeight) != EMSCRIPTEN_RESULT_SUCCESS)
        return;
    if (cssWidth <= 0.0 || cssHeight <= 0.0)
        return;
    const double rawDensity = std::max(1.0, emscripten_get_device_pixel_ratio());
    const double density =
        (m_maxPixelRatio > 0.0f) ? std::min<double>(rawDensity, static_cast<double>(m_maxPixelRatio)) : rawDensity;
    const Size size(std::max(1, static_cast<int>(std::lround(cssWidth * density))),
                    std::max(1, static_cast<int>(std::lround(cssHeight * density))));
    m_cssWidth = cssWidth;
    m_cssHeight = cssHeight;
    // Zoom or pixel ratio cap can change CSS coordinates/DPI while keeping the backing size equal.
    if (m_created && size == m_size && std::fabs(static_cast<float>(density) - m_displayDensity) < 0.001f)
        return;
    setDisplayDensity(static_cast<float>(density));
    emscripten_set_canvas_element_size(CanvasSelector, size.width(), size.height());
    m_size = size;
    if (!m_contextLost.load())
        glViewport(0, 0, size.width(), size.height());
    if (m_onResize) {
        g_graphicsDispatcher.addEvent([this, size] {
            if (m_onResize)
                m_onResize(size);
        });
    }
}

Point BrowserWindow::cssToWindowPos(double targetX, double targetY) const
{
    const double scaleX =
        m_cssWidth > 0.0 ? (static_cast<double>(m_size.width()) / m_cssWidth) : static_cast<double>(m_displayDensity);
    const double scaleY =
        m_cssHeight > 0.0 ? (static_cast<double>(m_size.height()) / m_cssHeight) : static_cast<double>(m_displayDensity);
    const double invScale = m_scaling > 0.0f ? (1.0 / static_cast<double>(m_scaling)) : 1.0;
    const int maxX = std::max(0, static_cast<int>(std::lround(m_size.width() * invScale)));
    const int maxY = std::max(0, static_cast<int>(std::lround(m_size.height() * invScale)));
    const int x = std::clamp(static_cast<int>(std::lround(targetX * scaleX * invScale)), 0, maxX);
    const int y = std::clamp(static_cast<int>(std::lround(targetY * scaleY * invScale)), 0, maxY);
    return Point(x, y);
}

void BrowserWindow::dispatchMouseButton(int eventType, const EmscriptenMouseEvent &event)
{
    if (m_usingTouch && (event.button == 0 || (stdext::millis() - m_lastTouchTicks) < 600))
        return;
    const int targetX = event.targetX;
    const int targetY = event.targetY;
    Fw::MouseButton button = Fw::MouseNoButton;
    if (event.button == 0)
        button = Fw::MouseLeftButton;
    else if (event.button == 1)
        button = Fw::MouseMidButton;
    else if (event.button == 2)
        button = Fw::MouseRightButton;
    else if (event.button == 3)
        button = Fw::MouseButton4;
    else if (event.button == 4)
        button = Fw::MouseButton5;
    if (button == Fw::MouseNoButton)
        return;

    g_dispatcher.addEvent([this, eventType, targetX, targetY, button] {
        const Point position = cssToWindowPos(targetX, targetY);
        m_inputEvent.reset(eventType == EMSCRIPTEN_EVENT_MOUSEDOWN ? Fw::MousePressInputEvent
                                                                   : Fw::MouseReleaseInputEvent);
        m_inputEvent.mousePos = position;
        m_inputEvent.mouseButton = button;
        m_mouseButtonStates[button] = eventType == EMSCRIPTEN_EVENT_MOUSEDOWN;
        if (m_onInputEvent)
            m_onInputEvent(m_inputEvent);
    });
}

void BrowserWindow::dispatchMouseMove(int targetX, int targetY)
{
    if (m_usingTouch) {
        if ((stdext::millis() - m_lastTouchTicks) < 600)
            return;
        m_usingTouch = false;
    }
    g_dispatcher.addEvent([this, targetX, targetY] {
        const Point position = cssToWindowPos(targetX, targetY);
        m_inputEvent.reset(Fw::MouseMoveInputEvent);
        m_inputEvent.mouseMoved = position - m_inputEvent.mousePos;
        m_inputEvent.mousePos = position;
        if (m_onInputEvent)
            m_onInputEvent(m_inputEvent);
    });
}

void BrowserWindow::dispatchWheel(double deltaY, int targetX, int targetY)
{
    g_dispatcher.addEvent([this, deltaY, targetX, targetY] {
        m_inputEvent.reset(Fw::MouseWheelInputEvent);
        m_inputEvent.mousePos = cssToWindowPos(targetX, targetY);
        m_inputEvent.mouseButton = Fw::MouseMidButton;
        m_inputEvent.wheelDirection = deltaY > 0 ? Fw::MouseWheelDown : Fw::MouseWheelUp;
        if (m_onInputEvent)
            m_onInputEvent(m_inputEvent);
    });
}

void BrowserWindow::dispatchTouchEvent(int eventType, std::vector<TouchSample> touches)
{
    m_usingTouch = true;
    m_lastTouchTicks = stdext::millis();
    g_dispatcher.addEvent([this, eventType, touches = std::move(touches)] {
        if (!m_onInputEvent)
            return;
        constexpr int DragThresholdPx = 16;
        constexpr ticks_t LongPressMs = 450;

        auto findSlotById = [this](long id) -> int {
            for (size_t i = 0; i < m_touchSlots.size(); ++i) {
                if (m_touchSlots[i].active && m_touchSlots[i].identifier == id)
                    return static_cast<int>(i);
            }
            return -1;
        };

        auto allocateSlot = [this](long id) -> int {
            for (size_t i = 0; i < m_touchSlots.size(); ++i) {
                if (!m_touchSlots[i].active) {
                    m_touchSlots[i] = TouchSlot{};
                    m_touchSlots[i].active = true;
                    m_touchSlots[i].identifier = id;
                    return static_cast<int>(i);
                }
            }
            return -1;
        };

        for (const auto &sample : touches) {
            if (!sample.isChanged)
                continue;
            const Point pos = cssToWindowPos(sample.targetX, sample.targetY);

            if (eventType == EMSCRIPTEN_EVENT_TOUCHSTART) {
                int slotIdx = findSlotById(sample.identifier);
                if (slotIdx < 0)
                    slotIdx = allocateSlot(sample.identifier);
                if (slotIdx < 0)
                    continue;
                auto &slot = m_touchSlots[slotIdx];
                slot.startPos = pos;
                slot.lastPos = pos;
                slot.dragged = false;
                slot.pressTime = stdext::millis();

                if (slotIdx == 0) {
                    m_inputEvent.reset(Fw::MouseMoveInputEvent);
                    m_inputEvent.mouseMoved = pos - m_inputEvent.mousePos;
                    m_inputEvent.mousePos = pos;
                    m_onInputEvent(m_inputEvent);

                    m_inputEvent.reset(Fw::MousePressInputEvent);
                    m_inputEvent.mousePos = pos;
                    m_inputEvent.mouseButton = Fw::MouseTouch;
                    m_mouseButtonStates[Fw::MouseTouch] = true;
                    m_onInputEvent(m_inputEvent);
                } else {
                    const Fw::MouseButton btn = (slotIdx == 1) ? Fw::MouseTouch2 : Fw::MouseTouch3;
                    InputEvent multi;
                    multi.reset(Fw::MousePressInputEvent);
                    multi.mousePos = pos;
                    multi.mouseButton = btn;
                    m_mouseButtonStates[btn] = true;
                    m_onInputEvent(multi);
                }
            } else if (eventType == EMSCRIPTEN_EVENT_TOUCHMOVE) {
                const int slotIdx = findSlotById(sample.identifier);
                if (slotIdx < 0)
                    continue;
                auto &slot = m_touchSlots[slotIdx];
                const Point prevPos = slot.lastPos;
                slot.lastPos = pos;

                if (slotIdx == 0) {
                    const int dist = std::max(std::abs(pos.x - slot.startPos.x), std::abs(pos.y - slot.startPos.y));
                    if (!slot.dragged && dist > DragThresholdPx) {
                        slot.dragged = true;
                        m_inputEvent.reset(Fw::MouseMoveInputEvent);
                        m_inputEvent.mouseMoved = slot.startPos - m_inputEvent.mousePos;
                        m_inputEvent.mousePos = slot.startPos;
                        m_onInputEvent(m_inputEvent);

                        m_inputEvent.reset(Fw::MousePressInputEvent);
                        m_inputEvent.mousePos = slot.startPos;
                        m_inputEvent.mouseButton = Fw::MouseLeftButton;
                        m_mouseButtonStates[Fw::MouseLeftButton] = true;
                        m_onInputEvent(m_inputEvent);
                    }
                    m_inputEvent.reset(Fw::MouseMoveInputEvent);
                    m_inputEvent.mouseMoved = pos - prevPos;
                    m_inputEvent.mousePos = pos;
                    m_onInputEvent(m_inputEvent);
                }
            } else if (eventType == EMSCRIPTEN_EVENT_TOUCHEND || eventType == EMSCRIPTEN_EVENT_TOUCHCANCEL) {
                const int slotIdx = findSlotById(sample.identifier);
                if (slotIdx < 0)
                    continue;
                const TouchSlot slot = m_touchSlots[slotIdx];
                m_touchSlots[slotIdx] = TouchSlot{};
                const bool cancelled = (eventType == EMSCRIPTEN_EVENT_TOUCHCANCEL);

                if (slotIdx == 0) {
                    m_inputEvent.reset(Fw::MouseMoveInputEvent);
                    m_inputEvent.mouseMoved = pos - m_inputEvent.mousePos;
                    m_inputEvent.mousePos = pos;
                    m_onInputEvent(m_inputEvent);

                    m_inputEvent.reset(Fw::MouseReleaseInputEvent);
                    m_inputEvent.mousePos = pos;
                    m_inputEvent.mouseButton = Fw::MouseTouch;
                    m_mouseButtonStates[Fw::MouseTouch] = false;
                    m_onInputEvent(m_inputEvent);

                    if (slot.dragged) {
                        if (cancelled) {
                            // Cancel active drag cleanly without executing onDrop on a target slot.
                            g_ui.updateDraggingWidget(nullptr, Point());
                        }
                        m_inputEvent.reset(Fw::MouseReleaseInputEvent);
                        m_inputEvent.mousePos = cancelled ? Point(-1, -1) : pos;
                        m_inputEvent.mouseButton = Fw::MouseLeftButton;
                        m_mouseButtonStates[Fw::MouseLeftButton] = false;
                        m_onInputEvent(m_inputEvent);
                    } else if (!cancelled && !slot.consumed) {
                        const bool longPress = (stdext::millis() - slot.pressTime) >= LongPressMs;
                        const Fw::MouseButton clickBtn = longPress ? Fw::MouseRightButton : Fw::MouseLeftButton;
                        m_inputEvent.reset(Fw::MousePressInputEvent);
                        m_inputEvent.mousePos = pos;
                        m_inputEvent.mouseButton = clickBtn;
                        m_mouseButtonStates[clickBtn] = true;
                        m_onInputEvent(m_inputEvent);

                        m_inputEvent.reset(Fw::MouseReleaseInputEvent);
                        m_inputEvent.mousePos = pos;
                        m_inputEvent.mouseButton = clickBtn;
                        m_mouseButtonStates[clickBtn] = false;
                        m_onInputEvent(m_inputEvent);
                    }
                } else {
                    const Fw::MouseButton btn = (slotIdx == 1) ? Fw::MouseTouch2 : Fw::MouseTouch3;
                    InputEvent multi;
                    multi.reset(Fw::MouseReleaseInputEvent);
                    multi.mousePos = cancelled ? Point(-1, -1) : pos;
                    multi.mouseButton = btn;
                    m_mouseButtonStates[btn] = false;
                    m_onInputEvent(multi);
                }
            }
        }
    });
}

void BrowserWindow::releaseAllTouches()
{
    for (size_t i = 0; i < m_touchSlots.size(); ++i) {
        if (!m_touchSlots[i].active)
            continue;
        const TouchSlot slot = m_touchSlots[i];
        m_touchSlots[i] = TouchSlot{};
        if (!m_onInputEvent)
            continue;
        if (i == 0) {
            m_inputEvent.reset(Fw::MouseReleaseInputEvent);
            m_inputEvent.mousePos = Point(-1, -1);
            m_inputEvent.mouseButton = Fw::MouseTouch;
            m_mouseButtonStates[Fw::MouseTouch] = false;
            m_onInputEvent(m_inputEvent);
            if (slot.dragged) {
                g_ui.updateDraggingWidget(nullptr, Point());
                m_inputEvent.reset(Fw::MouseReleaseInputEvent);
                m_inputEvent.mousePos = Point(-1, -1);
                m_inputEvent.mouseButton = Fw::MouseLeftButton;
                m_mouseButtonStates[Fw::MouseLeftButton] = false;
                m_onInputEvent(m_inputEvent);
            }
        } else {
            const Fw::MouseButton btn = (i == 1) ? Fw::MouseTouch2 : Fw::MouseTouch3;
            InputEvent multi;
            multi.reset(Fw::MouseReleaseInputEvent);
            multi.mousePos = Point(-1, -1);
            multi.mouseButton = btn;
            m_mouseButtonStates[btn] = false;
            m_onInputEvent(multi);
        }
    }
}

void BrowserWindow::dispatchKeyboard(int eventType, std::string code, std::string key, bool repeat, bool ctrl, bool alt,
                                     bool shift, bool meta)
{
    g_dispatcher.addEvent(
        [this, eventType, code = std::move(code), key = std::move(key), repeat, ctrl, alt, shift, meta] {
            if (!m_created)
                return;
            const auto it = m_webKeyMap.find(code);
            const Fw::Key keyCode = it == m_webKeyMap.end() ? Fw::KeyUnknown : it->second;
            // Recover modifier state even if focus was gained with a modifier
            // already held. Left/right modifier releases use the DOM snapshot.
            m_inputEvent.keyboardModifiers = (ctrl ? Fw::KeyboardCtrlModifier : 0) |
                                             (alt ? Fw::KeyboardAltModifier : 0) |
                                             (shift ? Fw::KeyboardShiftModifier : 0);
            if (keyCode == Fw::KeyCtrl || keyCode == Fw::KeyAlt || keyCode == Fw::KeyShift)
                return;
            if (eventType == EMSCRIPTEN_EVENT_KEYDOWN) {
                if (!repeat)
                    processKeyDown(keyCode);
                if (!ctrl && !alt && !meta && isSingleUtf8Character(key) && m_onInputEvent) {
                    m_inputEvent.reset(Fw::KeyTextInputEvent);
                    m_inputEvent.keyText = key;
                    m_onInputEvent(m_inputEvent);
                }
            } else if (eventType == EMSCRIPTEN_EVENT_KEYUP) {
                processKeyUp(keyCode);
            }
        });
}

void BrowserWindow::dispatchFocus(bool focused)
{
    g_dispatcher.addEvent([this, focused] {
        m_focused = focused;
        if (!focused) {
            releaseAllKeys();
            releaseAllTouches();
        }
    });
}

void BrowserWindow::handleVisibilityChange(bool visible)
{
    g_dispatcher.addEvent([this, visible] {
        if (!m_created)
            return;
        m_visible = visible;
        if (!visible) {
            releaseAllKeys();
            releaseAllTouches();
        } else {
            g_app.repaint();
        }
    });
}

void BrowserWindow::handleViewportChanged()
{
    g_graphicsDispatcher.addEvent([this] {
        if (!m_created)
            return;
        updateCanvasSize();
        g_app.repaint();
    });
}

void BrowserWindow::handleContextLost(bool lost)
{
    if (lost) {
        m_contextLostGeneration.fetch_add(1, std::memory_order_acq_rel);
        m_contextLost = true;
        g_dispatcher.addEvent([this] {
            releaseAllKeys();
            releaseAllTouches();
        });
        return;
    }
    const uint64_t generation = m_contextLostGeneration.load(std::memory_order_acquire);
    g_graphicsDispatcher.addEvent([this, generation] {
        if (!m_created || m_contextLostGeneration.load(std::memory_order_acquire) != generation)
            return;
        if (m_context > 0)
            emscripten_webgl_make_context_current(m_context);
        m_contextLost = false;
        updateCanvasSize();
        g_app.onBrowserContextRestored();
    });
}

void BrowserWindow::handlePaste(std::string text)
{
    g_dispatcher.addEvent([this, text = std::move(text)] {
        m_clipboardText = text;
        if (m_onInputEvent && !text.empty()) {
            m_inputEvent.reset(Fw::KeyTextInputEvent);
            m_inputEvent.keyText = text;
            m_onInputEvent(m_inputEvent);
        }
    });
}

void BrowserWindow::handleVirtualText(std::string text) { handlePaste(std::move(text)); }

void BrowserWindow::handleVirtualTextReplace(std::string text, int selStart, int selEnd)
{
    g_dispatcher.addEvent([this, text = std::move(text), selStart, selEnd] {
        if (!m_created)
            return;
        UIWidgetPtr current = g_ui.getKeyboardReceiver();
        while (current) {
            UIWidgetPtr focusedChild = current->getFocusedChild();
            if (!focusedChild)
                break;
            current = focusedChild;
        }
        auto edit = std::dynamic_pointer_cast<UITextEdit>(current);
        if (!edit || !edit->isEditable())
            return;

        m_syncingFromBrowser = true;
        std::string applied = text;
        const uint maxLen = edit->getMaxLength();
        if (maxLen > 0 && applied.size() > maxLen)
            applied.resize(maxLen);
        const std::string &validChars = edit->getValidCharacters();
        if (!validChars.empty()) {
            std::string filtered;
            filtered.reserve(applied.size());
            for (char ch : applied) {
                if (validChars.find(ch) != std::string::npos)
                    filtered.push_back(ch);
            }
            applied = std::move(filtered);
        }
        edit->setText(applied);
        const int len = static_cast<int>(applied.size());
        const int start = std::clamp(selStart >= 0 ? selStart : len, 0, len);
        const int end = std::clamp(selEnd >= 0 ? selEnd : start, 0, len);
        edit->setCursorPos(end);
        if (edit->isSelectable())
            edit->setSelection(start, end);
        m_syncingFromBrowser = false;
        g_app.repaint();
    });
}

void BrowserWindow::handleVirtualKey(Fw::Key key)
{
    g_dispatcher.addEvent([this, key] {
        processKeyDown(key);
        processKeyUp(key);
    });
}

extern "C" {
EMSCRIPTEN_KEEPALIVE void astra_browser_paste(const char *text) { g_browserWindow.handlePaste(text ? text : ""); }

EMSCRIPTEN_KEEPALIVE void astra_browser_text_input(const char *text)
{
    g_browserWindow.handleVirtualText(text ? text : "");
}

EMSCRIPTEN_KEEPALIVE void astra_browser_set_text(const char *text, int selStart, int selEnd)
{
    g_browserWindow.handleVirtualTextReplace(text ? text : "", selStart, selEnd);
}

EMSCRIPTEN_KEEPALIVE void astra_browser_virtual_key(int key)
{
    if (key == 8)
        g_browserWindow.handleVirtualKey(Fw::KeyBackspace);
    else if (key == 9)
        g_browserWindow.handleVirtualKey(Fw::KeyTab);
    else if (key == 13)
        g_browserWindow.handleVirtualKey(Fw::KeyEnter);
    else if (key == 27)
        g_browserWindow.handleVirtualKey(Fw::KeyEscape);
}

EMSCRIPTEN_KEEPALIVE void astra_browser_set_visibility(int visible)
{
    g_browserWindow.handleVisibilityChange(visible != 0);
}

EMSCRIPTEN_KEEPALIVE void astra_browser_viewport_changed()
{
    g_browserWindow.handleViewportChanged();
}

EMSCRIPTEN_KEEPALIVE void astra_browser_context_lost(int lost)
{
    g_browserWindow.handleContextLost(lost != 0);
}
}

void BrowserWindow::poll()
{
    fireKeysPress();
    if (m_created && (g_app.isMobile() || m_usingTouch)) {
        const ticks_t now = stdext::millis();
        if (now - m_lastTextRectSyncTicks >= 120) {
            m_lastTextRectSyncTicks = now;
            syncTextInputRects(false);
        }
    }
}

void BrowserWindow::swapBuffers()
{
    if (m_context > 0)
        emscripten_webgl_commit_frame();
}

void BrowserWindow::move(const Point &) {}

void BrowserWindow::resize(const Size &) { updateCanvasSize(); }

void BrowserWindow::show()
{
    m_visible = true;
    browserSetVisible(1);
}

void BrowserWindow::hide()
{
    m_visible = false;
    browserSetVisible(0);
}

void BrowserWindow::minimize() { hide(); }

void BrowserWindow::maximize() { setFullscreen(true); }

void BrowserWindow::showMouse() { restoreMouseCursor(); }

// Native cursor hiding has no software-cursor substitute on the browser canvas.
void BrowserWindow::hideMouse() { restoreMouseCursor(); }

void BrowserWindow::displayFatalError(const std::string &message) { browserShowFatalError(message.c_str()); }

int BrowserWindow::internalLoadMouseCursor(const ImagePtr &image, const Point &hotSpot)
{
    const auto cursorImage = astra_browser::selectCursorImage(image);
    if (!cursorImage) {
        restoreMouseCursor();
        return -1;
    }
    const int id = m_cursorCount++;
    if (!browserCreateCursor(id, cursorImage->getPixelData(), cursorImage->getWidth(), cursorImage->getHeight(),
                             hotSpot.x, hotSpot.y)) {
        restoreMouseCursor();
        return -1;
    }
    return id;
}

void BrowserWindow::setMouseCursor(int cursorId) { browserUseCursor(cursorId); }

void BrowserWindow::restoreMouseCursor() { browserSetCursor("auto"); }

void BrowserWindow::setSystemCursor(const std::string &cursorName) { browserSetCursor(cursorName.c_str()); }

void BrowserWindow::setTitle(const std::string &title) { browserSetTitle(title.c_str()); }

void BrowserWindow::setMinimumSize(const Size &minimumSize) { m_minimumSize = minimumSize; }

void BrowserWindow::setFullscreen(bool fullscreen)
{
    if (fullscreen) {
        EmscriptenFullscreenStrategy strategy{};
        strategy.scaleMode = EMSCRIPTEN_FULLSCREEN_SCALE_STRETCH;
        strategy.canvasResolutionScaleMode = EMSCRIPTEN_FULLSCREEN_CANVAS_SCALE_HIDEF;
        strategy.filteringMode = EMSCRIPTEN_FULLSCREEN_FILTERING_DEFAULT;
        emscripten_request_fullscreen_strategy(CanvasSelector, EM_TRUE, &strategy);
    } else {
        emscripten_exit_fullscreen();
    }
    m_fullscreen = fullscreen;
}

void BrowserWindow::setVerticalSync(bool enable)
{
    m_verticalSync = enable;
    m_verticalSyncApplied = true;
}

void BrowserWindow::setIcon(const std::string &) {}

void BrowserWindow::setClipboardText(const std::string &text)
{
    m_clipboardText = text;
    // clang-format off
    MAIN_THREAD_EM_ASM({
        if (navigator.clipboard && navigator.clipboard.writeText)
            navigator.clipboard.writeText(UTF8ToString($0)).catch(function(error) {
                console.warn('AstraClient clipboard write was rejected:', error);
            });
    }, text.c_str());
    // clang-format on
}

Size BrowserWindow::getDisplaySize() { return m_size; }

std::string BrowserWindow::getClipboardText() { return m_clipboardText; }

std::string BrowserWindow::getPlatformType() { return "BROWSER-WEBGL2"; }

void BrowserWindow::showTextEditor(const std::string &title, const std::string &, const std::string &text, int flags)
{
    if (!m_usingTouch && !g_app.isMobile())
        return;
    std::ostringstream oss;
    oss << "{\"text\":\"" << jsonEscape(text) << "\",\"placeholder\":\"" << jsonEscape(title)
        << "\",\"multiline\":" << ((flags & 1) ? "true" : "false")
        << ",\"password\":" << ((flags & 2) ? "true" : "false")
        << ",\"numeric\":" << ((flags & 4) ? "true" : "false")
        << ",\"email\":false,\"maxLen\":0,\"cursor\":" << text.size()
        << ",\"selStart\":" << text.size() << ",\"selEnd\":" << text.size() << "}";
    browserShowVirtualKeyboard(oss.str().c_str());
}

void BrowserWindow::hideTextEditor()
{
    browserHideVirtualKeyboard();
}

void BrowserWindow::consumeTouchGesture()
{
    if (m_touchSlots[0].active)
        m_touchSlots[0].consumed = true;
}

void BrowserWindow::openWebProfile(const std::string &profile)
{
    // clang-format off
    MAIN_THREAD_EM_ASM({
    if (window.AstraLauncher && typeof window.AstraLauncher.switchProfile === 'function')
        window.AstraLauncher.switchProfile(UTF8ToString($0));
    }, profile.c_str());
    // clang-format on
}

void BrowserWindow::toggleWebDiagnostics()
{
    // clang-format off
    MAIN_THREAD_EM_ASM({
    if (window.AstraLauncher && typeof window.AstraLauncher.toggleDiagnostics === 'function')
        window.AstraLauncher.toggleDiagnostics();
    });
    // clang-format on
}

void BrowserWindow::requestWebFullscreen()
{
    // clang-format off
    MAIN_THREAD_EM_ASM({
    if (window.AstraLauncher && typeof window.AstraLauncher.requestFullscreen === 'function')
        window.AstraLauncher.requestFullscreen();
    });
    // clang-format on
}

static std::string serializeTextEditMeta(UITextEdit *edit, double cssScaleX, double cssScaleY)
{
    const Rect r = edit->getRect();
    const std::string text = edit->getText();
    const int selStart = edit->hasSelection() ? edit->getSelectionStart() : edit->getCursorPos();
    const int selEnd = edit->hasSelection() ? edit->getSelectionEnd() : edit->getCursorPos();
    std::ostringstream oss;
    oss << "{\"id\":\"" << jsonEscape(edit->getId())
        << "\",\"x\":" << static_cast<int>(std::lround(r.left() * cssScaleX))
        << ",\"y\":" << static_cast<int>(std::lround(r.top() * cssScaleY))
        << ",\"w\":" << static_cast<int>(std::lround(r.width() * cssScaleX))
        << ",\"h\":" << static_cast<int>(std::lround(r.height() * cssScaleY))
        << ",\"text\":\"" << jsonEscape(text)
        << "\",\"placeholder\":\"" << jsonEscape(edit->getPlaceholder())
        << "\",\"cursor\":" << edit->getCursorPos()
        << ",\"selStart\":" << selStart
        << ",\"selEnd\":" << selEnd
        << ",\"maxLen\":" << edit->getMaxLength()
        << ",\"password\":" << (edit->isTextHidden() ? "true" : "false")
        << ",\"multiline\":" << (edit->isMultiline() ? "true" : "false")
        << ",\"numeric\":" << (isNumericTextEdit(edit) ? "true" : "false")
        << ",\"email\":" << (isEmailTextEdit(edit) ? "true" : "false")
        << ",\"focused\":" << (edit->isFocused() ? "true" : "false") << "}";
    return oss.str();
}

void BrowserWindow::onTextEditActivated(UITextEdit *edit)
{
    if (!edit || !edit->isEditable() || (!m_usingTouch && !g_app.isMobile()))
        return;
    const double cssScaleX = (m_size.width() > 0 && m_cssWidth > 0.0)
        ? (m_cssWidth * static_cast<double>(m_scaling) / static_cast<double>(m_size.width()))
        : (static_cast<double>(m_scaling) / static_cast<double>(m_displayDensity));
    const double cssScaleY = (m_size.height() > 0 && m_cssHeight > 0.0)
        ? (m_cssHeight * static_cast<double>(m_scaling) / static_cast<double>(m_size.height()))
        : (static_cast<double>(m_scaling) / static_cast<double>(m_displayDensity));
    syncTextInputRects(true);
    browserShowVirtualKeyboard(serializeTextEditMeta(edit, cssScaleX, cssScaleY).c_str());
}

void BrowserWindow::onTextEditFocusChanged(UITextEdit *edit, bool focused)
{
    if (!edit || (!m_usingTouch && !g_app.isMobile()))
        return;
    if (focused && edit->isEditable()) {
        const double cssScaleX = (m_size.width() > 0 && m_cssWidth > 0.0)
            ? (m_cssWidth * static_cast<double>(m_scaling) / static_cast<double>(m_size.width()))
            : (static_cast<double>(m_scaling) / static_cast<double>(m_displayDensity));
        const double cssScaleY = (m_size.height() > 0 && m_cssHeight > 0.0)
            ? (m_cssHeight * static_cast<double>(m_scaling) / static_cast<double>(m_size.height()))
            : (static_cast<double>(m_scaling) / static_cast<double>(m_displayDensity));
        browserSyncFocusedTextInput(serializeTextEditMeta(edit, cssScaleX, cssScaleY).c_str());
        syncTextInputRects(true);
    } else if (!focused) {
        g_dispatcher.addEvent([this] {
            UIWidgetPtr current = g_ui.getKeyboardReceiver();
            while (current) {
                UIWidgetPtr child = current->getFocusedChild();
                if (!child)
                    break;
                current = child;
            }
            auto activeEdit = std::dynamic_pointer_cast<UITextEdit>(current);
            if (!activeEdit || !activeEdit->isEditable())
                browserHideVirtualKeyboard();
        });
    }
}

void BrowserWindow::onTextEditChanged(UITextEdit *edit)
{
    if (m_syncingFromBrowser || !edit || !edit->isEditable() || !edit->isFocused())
        return;
    if (!m_usingTouch && !g_app.isMobile())
        return;
    const double cssScaleX = (m_size.width() > 0 && m_cssWidth > 0.0)
        ? (m_cssWidth * static_cast<double>(m_scaling) / static_cast<double>(m_size.width()))
        : (static_cast<double>(m_scaling) / static_cast<double>(m_displayDensity));
    const double cssScaleY = (m_size.height() > 0 && m_cssHeight > 0.0)
        ? (m_cssHeight * static_cast<double>(m_scaling) / static_cast<double>(m_size.height()))
        : (static_cast<double>(m_scaling) / static_cast<double>(m_displayDensity));
    browserSyncFocusedTextInput(serializeTextEditMeta(edit, cssScaleX, cssScaleY).c_str());
}

void BrowserWindow::syncTextInputRects(bool force)
{
    UIWidgetPtr root = g_ui.getRootWidget();
    if (!root || m_size.width() <= 0 || m_size.height() <= 0)
        return;
    const double cssScaleX = (m_cssWidth > 0.0)
        ? (m_cssWidth * static_cast<double>(m_scaling) / static_cast<double>(m_size.width()))
        : (static_cast<double>(m_scaling) / static_cast<double>(m_displayDensity));
    const double cssScaleY = (m_cssHeight > 0.0)
        ? (m_cssHeight * static_cast<double>(m_scaling) / static_cast<double>(m_size.height()))
        : (static_cast<double>(m_scaling) / static_cast<double>(m_displayDensity));

    std::vector<UITextEdit *> visibleEdits;
    std::function<void(const UIWidgetPtr &)> collect = [&](const UIWidgetPtr &widget) {
        if (!widget || !widget->isVisible() || !widget->isEnabled())
            return;
        if (auto edit = std::dynamic_pointer_cast<UITextEdit>(widget)) {
            if (edit->isEditable() && !edit->getRect().isEmpty())
                visibleEdits.push_back(edit.get());
        }
        for (const auto &child : widget->getChildren())
            collect(child);
    };
    collect(root);

    std::ostringstream oss;
    oss << "[";
    for (size_t i = 0; i < visibleEdits.size(); ++i) {
        if (i > 0)
            oss << ",";
        oss << serializeTextEditMeta(visibleEdits[i], cssScaleX, cssScaleY);
    }
    oss << "]";
    std::string json = oss.str();
    if (!force && json == m_lastTextRectsJson)
        return;
    m_lastTextRectsJson = std::move(json);
    browserUpdateTextInputRects(m_lastTextRectsJson.c_str());
}

#endif
