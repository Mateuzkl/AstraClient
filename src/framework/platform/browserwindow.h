#pragma once

#ifdef __EMSCRIPTEN__

#include "platformwindow.h"

#include <emscripten/html5.h>

class BrowserWindow final : public PlatformWindow
{
public:
    BrowserWindow();

    void init() override;
    void terminate() override;
    void move(const Point& pos) override;
    void resize(const Size& size) override;
    void show() override;
    void hide() override;
    void minimize() override;
    void maximize() override;
    void poll() override;
    void swapBuffers() override;
    void showMouse() override;
    void hideMouse() override;
    void displayFatalError(const std::string& message) override;

    void setMouseCursor(int cursorId) override;
    void restoreMouseCursor() override;
    void setSystemCursor(const std::string& cursorName) override;
    void setTitle(const std::string& title) override;
    void setMinimumSize(const Size& minimumSize) override;
    void setFullscreen(bool fullscreen) override;
    void setVerticalSync(bool enable) override;
    void setIcon(const std::string& iconFile) override;
    void setClipboardText(const std::string& text) override;

    Size getDisplaySize() override;
    std::string getClipboardText() override;
    std::string getPlatformType() override;

    void showTextEditor(const std::string& title, const std::string& description,
                        const std::string& text, int flags) override;
    void handlePaste(std::string text);
    void handleVirtualText(std::string text);
    void handleVirtualKey(Fw::Key key);

private:
    int internalLoadMouseCursor(const ImagePtr& image, const Point& hotSpot) override;
    void installCallbacks();
    void removeCallbacks();
    void updateCanvasSize();
    void dispatchMouseButton(int eventType, const EmscriptenMouseEvent& event);
    void dispatchMouseMove(int targetX, int targetY);
    void dispatchWheel(double deltaY, int targetX, int targetY);
    void dispatchTouch(int eventType, int targetX, int targetY);
    void dispatchKeyboard(int eventType, std::string code, std::string key, bool repeat,
                          bool ctrl, bool alt, bool shift, bool meta);
    void dispatchFocus(bool focused);

    EMSCRIPTEN_WEBGL_CONTEXT_HANDLE m_context = 0;
    std::unordered_map<std::string, Fw::Key> m_webKeyMap;
    std::string m_clipboardText;
    int m_cursorCount = 0;
    bool m_callbacksInstalled = false;
    bool m_usingTouch = false;
    bool m_touchMoved = false;
    Point m_touchStart;
    Timer m_touchTimer;
};

extern BrowserWindow& g_browserWindow;

#endif
