#if defined(__EMSCRIPTEN__)

#include <framework/core/eventdispatcher.h>
#include "sdlwindow.h"

SDLWindow::SDLWindow()
{
    m_minimumSize = Size(640, 360);
    m_size = Size(640, 360);
    m_eglDisplay = EGL_NO_DISPLAY;
    m_eglContext = EGL_NO_CONTEXT;
    m_eglSurface = EGL_NO_SURFACE;
}

SDLWindow::~SDLWindow()
{
    internalDestroyGL();
}


void SDLWindow::internalInitGL()
{

}

void SDLWindow::internalDestroyGL()
{

}

void SDLWindow::internalCheckGL()
{

}

void SDLWindow::internalChooseGL()
{

}

void SDLWindow::internalCreateGLContext()
{

}

void SDLWindow::internalDestroyGLContext()
{
    /*
    if (m_window == NULL)
        return;

    if(m_eglDisplay) {
        eglMakeCurrent(m_eglDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);

        if (m_eglSurface) {
            eglDestroySurface(m_eglDisplay, m_eglSurface);
            m_eglSurface = EGL_NO_SURFACE;
        }

        if(m_eglContext) {
            eglDestroyContext(m_eglDisplay, m_eglContext);
            m_eglContext = EGL_NO_CONTEXT;
        }

        eglTerminate(m_eglDisplay);
        m_eglDisplay = EGL_NO_DISPLAY;
    } */
}

void SDLWindow::internalConnectGLContext()
{
    /*
    m_eglSurface = eglCreateWindowSurface(m_eglDisplay, m_eglConfig, m_window, NULL);
    if(m_eglSurface == EGL_NO_SURFACE)
        g_logger.fatal(stdext::format("Unable to create EGL surface: %s", eglGetError())); */
}

void SDLWindow::terminate()
{
    //nativePause();
}

void SDLWindow::poll()
{

}

void SDLWindow::swapBuffers()
{

}

void SDLWindow::setVerticalSync(bool enable)
{
    m_verticalSync = enable;
    const int result = SDL_GL_SetSwapInterval(enable ? 1 : 0);
    m_verticalSyncApplied = (result == 0);
}

std::string SDLWindow::getClipboardText()
{
    // TODO
    return "";
}

void SDLWindow::setClipboardText(const std::string& text)
{
    // TODO
}

Size SDLWindow::getDisplaySize()
{
    return m_size;
}

std::string SDLWindow::getPlatformType()
{
    return "WASM";
}

void SDLWindow::init()
{
    // The Emscripten canvas is available as soon as the backend is set up.
    // Keep the frame policy out of the minimized path until the browser
    // explicitly hides the canvas.
    m_visible = true;
    m_focused = true;
}

void SDLWindow::show()
{
    m_visible = true;
    m_focused = true;
}

void SDLWindow::hide()
{
    m_visible = false;
    m_focused = false;
}

void SDLWindow::maximize() {}

void SDLWindow::minimize()
{
    m_visible = false;
    m_focused = false;
}

void SDLWindow::move(const Point& pos) {}

void SDLWindow::resize(const Size& size) {}

void SDLWindow::showMouse() {}

void SDLWindow::hideMouse() {}

void SDLWindow::setMouseCursor(int cursorId) {}

void SDLWindow::restoreMouseCursor() {}

void SDLWindow::setTitle(const std::string& title) {}

void SDLWindow::setMinimumSize(const Size& minimumSize) {}

void SDLWindow::setFullscreen(bool fullscreen) {}

void SDLWindow::setIcon(const std::string& iconFile) {}


void SDLWindow::updateSize()
{

}


void SDLWindow::handleTextInput(std::string text)
{

}

void SDLWindow::showTextEditor(const std::string& title, const std::string& description, const std::string& text, int flags)
{

}

void SDLWindow::displayFatalError(const std::string& message)
{

}

void SDLWindow::openUrl(std::string url)
{

}

#endif
