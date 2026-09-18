#ifdef __EMSCRIPTEN__

#include "browserwindow.h"

#include <framework/core/application.h>
#include <framework/core/eventdispatcher.h>
#include <framework/graphics/image.h>

#include <emscripten/emscripten.h>
#include <emscripten/threading.h>
#include <GLES2/gl2.h>

namespace {
constexpr const char* CanvasSelector = "#canvas";

bool isSingleUtf8Character(const std::string& text)
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
    MAIN_THREAD_EM_ASM({
    if (Module.astraTextBridgeInstalled)
        return;
    Module.astraTextBridgeInstalled = true;

    Module.astraPasteHandler = function(event) {
        const text = event.clipboardData ? event.clipboardData.getData('text/plain') : String();
        if (text) {
            Module.ccall('astra_browser_paste', null, ['string'], [text]);
            event.preventDefault();
        }
    };
    document.addEventListener('paste', Module.astraPasteHandler);

    const editor = document.getElementById('astra-virtual-keyboard');
    if (!editor)
        return;

    editor.addEventListener('beforeinput', function(event) {
        if (event.inputType === 'deleteContentBackward') {
            Module.ccall('astra_browser_virtual_key', null, ['number'], [8]);
            event.preventDefault();
        }
    });
    editor.addEventListener('input', function(event) {
        if (event.data)
            Module.ccall('astra_browser_text_input', null, ['string'], [event.data]);
        editor.value = String();
    });
    editor.addEventListener('keydown', function(event) {
        if (event.key === 'Enter') {
            Module.ccall('astra_browser_virtual_key', null, ['number'], [13]);
            event.preventDefault();
        }
    });
    });
}

void browserRemoveTextBridge()
{
    MAIN_THREAD_EM_ASM({
    if (Module.astraPasteHandler)
        document.removeEventListener('paste', Module.astraPasteHandler);
    Module.astraPasteHandler = null;
    Module.astraTextBridgeInstalled = false;
    });
}

void browserSetTitle(const char* title)
{
    MAIN_THREAD_EM_ASM({ document.title = UTF8ToString($0); }, title);
}

void browserSetCursor(const char* cursor)
{
    MAIN_THREAD_EM_ASM({
    const canvas = document.getElementById('canvas');
    if (canvas)
        canvas.style.cursor = UTF8ToString($0);
    }, cursor);
}

void browserCreateCursor(int id, const unsigned char* pixels, int width, int height, int hotX, int hotY)
{
    MAIN_THREAD_EM_ASM({
    Module.astraCursors = Module.astraCursors || [];
    const surface = document.createElement('canvas');
    surface.width = $2;
    surface.height = $3;
    const context = surface.getContext('2d');
    const copy = new Uint8ClampedArray(HEAPU8.subarray($1, $1 + $2 * $3 * 4));
    context.putImageData(new ImageData(copy, $2, $3), 0, 0);
    Module.astraCursors[$0] = 'url(' + surface.toDataURL('image/png') + ') ' + $4 + ' ' + $5 + ', auto';
    }, id, pixels, width, height, hotX, hotY);
}

void browserUseCursor(int id)
{
    MAIN_THREAD_EM_ASM({
    const canvas = document.getElementById('canvas');
    if (canvas && Module.astraCursors && Module.astraCursors[$0])
        canvas.style.cursor = Module.astraCursors[$0];
    }, id);
}

void browserSetVisible(int visible)
{
    MAIN_THREAD_EM_ASM({
    const canvas = document.getElementById('canvas');
    if (canvas)
        canvas.style.visibility = $0 ? 'visible' : 'hidden';
    }, visible);
}

void browserShowFatalError(const char* message)
{
    MAIN_THREAD_EM_ASM({
    if (Module.astraShowError)
        Module.astraShowError(UTF8ToString($0));
    else
        console.error(UTF8ToString($0));
    }, message);
}

void browserShowVirtualKeyboard(const char* text)
{
    MAIN_THREAD_EM_ASM({
    const editor = document.getElementById('astra-virtual-keyboard');
    if (!editor)
        return;
    editor.value = UTF8ToString($0);
    editor.focus({preventScroll: true});
    editor.setSelectionRange(editor.value.length, editor.value.length);
    if (navigator.virtualKeyboard && navigator.virtualKeyboard.show)
        navigator.virtualKeyboard.show();
    }, text);
}

int browserVirtualKeyboardHasFocus()
{
    return MAIN_THREAD_EM_ASM_INT({
        return document.activeElement === document.getElementById('astra-virtual-keyboard');
    });
}
}

BrowserWindow& g_browserWindow = static_cast<BrowserWindow&>(g_window);

BrowserWindow::BrowserWindow()
{
    m_minimumSize = Size(640, 360);
    m_size = Size(1280, 720);

    const std::pair<const char*, Fw::Key> keys[] = {
        {"Backspace", Fw::KeyBackspace}, {"Tab", Fw::KeyTab}, {"Enter", Fw::KeyEnter},
        {"ShiftLeft", Fw::KeyShift}, {"ShiftRight", Fw::KeyShift},
        {"ControlLeft", Fw::KeyCtrl}, {"ControlRight", Fw::KeyCtrl},
        {"AltLeft", Fw::KeyAlt}, {"AltRight", Fw::KeyAlt},
        {"MetaLeft", Fw::KeyMeta}, {"MetaRight", Fw::KeyMeta},
        {"Pause", Fw::KeyPause}, {"CapsLock", Fw::KeyCapsLock},
        {"Escape", Fw::KeyEscape}, {"Space", Fw::KeySpace},
        {"PageUp", Fw::KeyPageUp}, {"PageDown", Fw::KeyPageDown},
        {"End", Fw::KeyEnd}, {"Home", Fw::KeyHome},
        {"ArrowLeft", Fw::KeyLeft}, {"ArrowUp", Fw::KeyUp},
        {"ArrowRight", Fw::KeyRight}, {"ArrowDown", Fw::KeyDown},
        {"PrintScreen", Fw::KeyPrintScreen}, {"Insert", Fw::KeyInsert},
        {"Delete", Fw::KeyDelete}, {"NumLock", Fw::KeyNumLock},
        {"ScrollLock", Fw::KeyScrollLock},
        {"Semicolon", Fw::KeySemicolon}, {"Equal", Fw::KeyEqual},
        {"Comma", Fw::KeyComma}, {"Minus", Fw::KeyMinus},
        {"Period", Fw::KeyPeriod}, {"Slash", Fw::KeySlash},
        {"Backquote", Fw::KeyGrave}, {"BracketLeft", Fw::KeyLeftBracket},
        {"Backslash", Fw::KeyBackslash}, {"BracketRight", Fw::KeyRightBracket},
        {"Quote", Fw::KeyApostrophe}, {"NumpadMultiply", Fw::KeyAsterisk},
        {"NumpadAdd", Fw::KeyPlus}, {"NumpadSubtract", Fw::KeyMinus},
        {"NumpadDecimal", Fw::KeyPeriod}, {"NumpadDivide", Fw::KeySlash}
    };
    for (const auto& entry : keys)
        m_webKeyMap.emplace(entry.first, entry.second);
    for (int i = 0; i <= 9; ++i) {
        m_webKeyMap.emplace("Digit" + std::to_string(i), static_cast<Fw::Key>(Fw::Key0 + i));
        m_webKeyMap.emplace("Numpad" + std::to_string(i), static_cast<Fw::Key>(Fw::KeyNumpad0 + i));
    }
    for (int i = 0; i < 26; ++i)
        m_webKeyMap.emplace("Key" + std::string(1, static_cast<char>('A' + i)), static_cast<Fw::Key>(Fw::KeyA + i));
    const Fw::Key functionKeys[] = {
        Fw::KeyF1, Fw::KeyF2, Fw::KeyF3, Fw::KeyF4, Fw::KeyF5, Fw::KeyF6,
        Fw::KeyF7, Fw::KeyF8, Fw::KeyF9, Fw::KeyF10, Fw::KeyF11, Fw::KeyF12
    };
    for (int i = 0; i < 12; ++i)
        m_webKeyMap.emplace("F" + std::to_string(i + 1), functionKeys[i]);
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

    updateCanvasSize();
    installCallbacks();
    browserInstallTextBridge();
    m_created = true;
    m_visible = true;
    m_focused = true;
    m_verticalSync = true;
    m_verticalSyncApplied = true;
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
        [](int type, const EmscriptenMouseEvent* event, void* data) -> EM_BOOL {
            static_cast<BrowserWindow*>(data)->dispatchMouseButton(type, *event);
            return EM_TRUE;
        });
    emscripten_set_mouseup_callback(CanvasSelector, this, EM_TRUE,
        [](int type, const EmscriptenMouseEvent* event, void* data) -> EM_BOOL {
            static_cast<BrowserWindow*>(data)->dispatchMouseButton(type, *event);
            return EM_TRUE;
        });
    emscripten_set_mousemove_callback(CanvasSelector, this, EM_TRUE,
        [](int, const EmscriptenMouseEvent* event, void* data) -> EM_BOOL {
            static_cast<BrowserWindow*>(data)->dispatchMouseMove(event->targetX, event->targetY);
            return EM_TRUE;
        });
    emscripten_set_wheel_callback(CanvasSelector, this, EM_TRUE,
        [](int, const EmscriptenWheelEvent* event, void* data) -> EM_BOOL {
            static_cast<BrowserWindow*>(data)->dispatchWheel(event->deltaY, event->mouse.targetX, event->mouse.targetY);
            return EM_TRUE;
        });
    emscripten_set_keydown_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, this, EM_TRUE,
        [](int type, const EmscriptenKeyboardEvent* event, void* data) -> EM_BOOL {
            static_cast<BrowserWindow*>(data)->dispatchKeyboard(type, event->code, event->key, event->repeat,
                                                                 event->ctrlKey, event->altKey, event->shiftKey, event->metaKey);
            return (event->ctrlKey && (std::strcmp(event->code, "KeyV") == 0 || std::strcmp(event->code, "KeyC") == 0)) ? EM_FALSE : EM_TRUE;
        });
    emscripten_set_keyup_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, this, EM_TRUE,
        [](int type, const EmscriptenKeyboardEvent* event, void* data) -> EM_BOOL {
            static_cast<BrowserWindow*>(data)->dispatchKeyboard(type, event->code, event->key, event->repeat,
                                                                 event->ctrlKey, event->altKey, event->shiftKey, event->metaKey);
            return EM_TRUE;
        });
    emscripten_set_resize_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, this, EM_TRUE,
        [](int, const EmscriptenUiEvent*, void* data) -> EM_BOOL {
            static_cast<BrowserWindow*>(data)->updateCanvasSize();
            return EM_TRUE;
        });
    emscripten_set_focus_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, this, EM_TRUE,
        [](int, const EmscriptenFocusEvent*, void* data) -> EM_BOOL {
            static_cast<BrowserWindow*>(data)->dispatchFocus(true);
            return EM_TRUE;
        });
    emscripten_set_blur_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, this, EM_TRUE,
        [](int, const EmscriptenFocusEvent*, void* data) -> EM_BOOL {
            static_cast<BrowserWindow*>(data)->dispatchFocus(false);
            return EM_TRUE;
        });
    emscripten_set_touchstart_callback(CanvasSelector, this, EM_TRUE,
        [](int type, const EmscriptenTouchEvent* event, void* data) -> EM_BOOL {
            if (event->numTouches > 0)
                static_cast<BrowserWindow*>(data)->dispatchTouch(type, event->touches[0].targetX, event->touches[0].targetY);
            return EM_TRUE;
        });
    emscripten_set_touchmove_callback(CanvasSelector, this, EM_TRUE,
        [](int type, const EmscriptenTouchEvent* event, void* data) -> EM_BOOL {
            if (event->numTouches > 0)
                static_cast<BrowserWindow*>(data)->dispatchTouch(type, event->touches[0].targetX, event->touches[0].targetY);
            return EM_TRUE;
        });
    emscripten_set_touchend_callback(CanvasSelector, this, EM_TRUE,
        [](int type, const EmscriptenTouchEvent* event, void* data) -> EM_BOOL {
            int x = 0;
            int y = 0;
            for (int i = 0; i < event->numTouches; ++i) {
                if (event->touches[i].isChanged) {
                    x = event->touches[i].targetX;
                    y = event->touches[i].targetY;
                    break;
                }
            }
            static_cast<BrowserWindow*>(data)->dispatchTouch(type, x, y);
            return EM_TRUE;
        });
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
    emscripten_set_keydown_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, nullptr, EM_TRUE, nullptr);
    emscripten_set_keyup_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, nullptr, EM_TRUE, nullptr);
    emscripten_set_resize_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, nullptr, EM_TRUE, nullptr);
    emscripten_set_focus_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, nullptr, EM_TRUE, nullptr);
    emscripten_set_blur_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, nullptr, EM_TRUE, nullptr);
    emscripten_set_touchstart_callback(CanvasSelector, nullptr, EM_TRUE, nullptr);
    emscripten_set_touchmove_callback(CanvasSelector, nullptr, EM_TRUE, nullptr);
    emscripten_set_touchend_callback(CanvasSelector, nullptr, EM_TRUE, nullptr);
}

void BrowserWindow::updateCanvasSize()
{
    double cssWidth = 0;
    double cssHeight = 0;
    if (emscripten_get_element_css_size(CanvasSelector, &cssWidth, &cssHeight) != EMSCRIPTEN_RESULT_SUCCESS)
        return;
    const double density = std::max(1.0, emscripten_get_device_pixel_ratio());
    const Size size(std::max(1, static_cast<int>(std::lround(cssWidth * density))),
                    std::max(1, static_cast<int>(std::lround(cssHeight * density))));
    if (size == m_size)
        return;
    setDisplayDensity(static_cast<float>(density));
    emscripten_set_canvas_element_size(CanvasSelector, size.width(), size.height());
    m_size = size;
    glViewport(0, 0, size.width(), size.height());
    if (m_onResize) {
        g_graphicsDispatcher.addEvent([this, size] {
            if (m_onResize)
                m_onResize(size);
        });
    }
}

void BrowserWindow::dispatchMouseButton(int eventType, const EmscriptenMouseEvent& event)
{
    if (m_usingTouch && event.button == 0)
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
        const Point position(static_cast<int>(targetX * m_displayDensity / m_scaling),
                             static_cast<int>(targetY * m_displayDensity / m_scaling));
        m_inputEvent.reset(eventType == EMSCRIPTEN_EVENT_MOUSEDOWN ? Fw::MousePressInputEvent : Fw::MouseReleaseInputEvent);
        m_inputEvent.mousePos = position;
        m_inputEvent.mouseButton = button;
        m_mouseButtonStates[button] = eventType == EMSCRIPTEN_EVENT_MOUSEDOWN;
        if (m_onInputEvent)
            m_onInputEvent(m_inputEvent);
    });
}

void BrowserWindow::dispatchMouseMove(int targetX, int targetY)
{
    if (m_usingTouch)
        m_usingTouch = false;
    g_dispatcher.addEvent([this, targetX, targetY] {
        const Point position(static_cast<int>(targetX * m_displayDensity / m_scaling),
                             static_cast<int>(targetY * m_displayDensity / m_scaling));
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
        m_inputEvent.mousePos = Point(static_cast<int>(targetX * m_displayDensity / m_scaling),
                                      static_cast<int>(targetY * m_displayDensity / m_scaling));
        m_inputEvent.mouseButton = Fw::MouseMidButton;
        m_inputEvent.wheelDirection = deltaY > 0 ? Fw::MouseWheelDown : Fw::MouseWheelUp;
        if (m_onInputEvent)
            m_onInputEvent(m_inputEvent);
    });
}

void BrowserWindow::dispatchTouch(int eventType, int targetX, int targetY)
{
    m_usingTouch = true;
    g_dispatcher.addEvent([this, eventType, targetX, targetY] {
        const Point position(static_cast<int>(targetX * m_displayDensity / m_scaling),
                             static_cast<int>(targetY * m_displayDensity / m_scaling));
        if (eventType == EMSCRIPTEN_EVENT_TOUCHSTART) {
            m_touchStart = position;
            m_touchMoved = false;
            m_touchTimer.restart();
        } else if (eventType == EMSCRIPTEN_EVENT_TOUCHMOVE && (position - m_touchStart).length() > 8) {
            m_touchMoved = true;
        }

        if (eventType == EMSCRIPTEN_EVENT_TOUCHMOVE) {
            m_inputEvent.reset(Fw::MouseMoveInputEvent);
            m_inputEvent.mouseMoved = position - m_inputEvent.mousePos;
            m_inputEvent.mousePos = position;
        } else {
            const bool pressed = eventType == EMSCRIPTEN_EVENT_TOUCHSTART;
            m_inputEvent.reset(pressed ? Fw::MousePressInputEvent : Fw::MouseReleaseInputEvent);
            m_inputEvent.mousePos = position;
            m_inputEvent.mouseButton = Fw::MouseLeftButton;
            m_mouseButtonStates[Fw::MouseLeftButton] = pressed;
        }
        if (m_onInputEvent)
            m_onInputEvent(m_inputEvent);

        if (eventType == EMSCRIPTEN_EVENT_TOUCHEND) {
            const bool longPress = !m_touchMoved && m_touchTimer.running() && m_touchTimer.ticksElapsed() >= 500;
            m_touchTimer.stop();
            if (longPress && m_onInputEvent) {
                m_inputEvent.reset(Fw::MousePressInputEvent);
                m_inputEvent.mousePos = position;
                m_inputEvent.mouseButton = Fw::MouseRightButton;
                m_onInputEvent(m_inputEvent);
                m_inputEvent.reset(Fw::MouseReleaseInputEvent);
                m_inputEvent.mousePos = position;
                m_inputEvent.mouseButton = Fw::MouseRightButton;
                m_onInputEvent(m_inputEvent);
            }
        }
    });
}

void BrowserWindow::dispatchKeyboard(int eventType, std::string code, std::string key, bool repeat,
                                     bool ctrl, bool alt, bool shift, bool meta)
{
    if (ctrl && code == "KeyV")
        return;
    if (!ctrl && !alt && !meta && browserVirtualKeyboardHasFocus() &&
        (code == "Backspace" || code == "Enter" || isSingleUtf8Character(key)))
        return;
    g_dispatcher.addEvent([this, eventType, code = std::move(code), key = std::move(key), repeat, ctrl, alt, shift, meta] {
        const auto it = m_webKeyMap.find(code);
        const Fw::Key keyCode = it == m_webKeyMap.end() ? Fw::KeyUnknown : it->second;
        if (eventType == EMSCRIPTEN_EVENT_KEYDOWN) {
            if (!repeat)
                processKeyDown(keyCode);
            if (!repeat && !ctrl && !alt && !meta && isSingleUtf8Character(key) && m_onInputEvent) {
                m_inputEvent.reset(Fw::KeyTextInputEvent);
                m_inputEvent.keyText = key;
                m_onInputEvent(m_inputEvent);
            }
        } else if (eventType == EMSCRIPTEN_EVENT_KEYUP) {
            processKeyUp(keyCode);
        }
        (void)shift;
    });
}

void BrowserWindow::dispatchFocus(bool focused)
{
    g_dispatcher.addEvent([this, focused] {
        m_focused = focused;
        if (!focused)
            releaseAllKeys();
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

void BrowserWindow::handleVirtualText(std::string text)
{
    handlePaste(std::move(text));
}

void BrowserWindow::handleVirtualKey(Fw::Key key)
{
    g_dispatcher.addEvent([this, key] {
        processKeyDown(key);
        processKeyUp(key);
    });
}

extern "C" {
EMSCRIPTEN_KEEPALIVE void astra_browser_paste(const char* text)
{
    g_browserWindow.handlePaste(text ? text : "");
}

EMSCRIPTEN_KEEPALIVE void astra_browser_text_input(const char* text)
{
    g_browserWindow.handleVirtualText(text ? text : "");
}

EMSCRIPTEN_KEEPALIVE void astra_browser_virtual_key(int key)
{
    if (key == 8)
        g_browserWindow.handleVirtualKey(Fw::KeyBackspace);
    else if (key == 13)
        g_browserWindow.handleVirtualKey(Fw::KeyEnter);
}
}

void BrowserWindow::poll()
{
    fireKeysPress();
}

void BrowserWindow::swapBuffers()
{
    if (m_context > 0)
        emscripten_webgl_commit_frame();
}

void BrowserWindow::move(const Point&) {}

void BrowserWindow::resize(const Size&) { updateCanvasSize(); }

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

void BrowserWindow::hideMouse() { browserSetCursor("none"); }

void BrowserWindow::displayFatalError(const std::string& message) { browserShowFatalError(message.c_str()); }

int BrowserWindow::internalLoadMouseCursor(const ImagePtr& image, const Point& hotSpot)
{
    if (!image || image->getBpp() != 4)
        return -1;
    const int id = m_cursorCount++;
    browserCreateCursor(id, image->getPixelData(), image->getWidth(), image->getHeight(), hotSpot.x, hotSpot.y);
    return id;
}

void BrowserWindow::setMouseCursor(int cursorId) { browserUseCursor(cursorId); }

void BrowserWindow::restoreMouseCursor() { browserSetCursor("auto"); }

void BrowserWindow::setSystemCursor(const std::string& cursorName) { browserSetCursor(cursorName.c_str()); }

void BrowserWindow::setTitle(const std::string& title) { browserSetTitle(title.c_str()); }

void BrowserWindow::setMinimumSize(const Size& minimumSize) { m_minimumSize = minimumSize; }

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

void BrowserWindow::setIcon(const std::string&) {}

void BrowserWindow::setClipboardText(const std::string& text)
{
    m_clipboardText = text;
    MAIN_THREAD_EM_ASM({
        if (navigator.clipboard && navigator.clipboard.writeText)
            navigator.clipboard.writeText(UTF8ToString($0)).catch(function(error) {
                console.warn('AstraClient clipboard write was rejected:', error);
            });
    }, text.c_str());
}

Size BrowserWindow::getDisplaySize() { return m_size; }

std::string BrowserWindow::getClipboardText() { return m_clipboardText; }

std::string BrowserWindow::getPlatformType() { return "BROWSER-WEBGL2"; }

void BrowserWindow::showTextEditor(const std::string&, const std::string&, const std::string& text, int)
{
    browserShowVirtualKeyboard(text.c_str());
}

#endif
