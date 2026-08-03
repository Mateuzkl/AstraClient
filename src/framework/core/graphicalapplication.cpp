/*
 * Copyright (c) 2010-2017 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */


#include "graphicalapplication.h"
#include <framework/core/adaptiverenderer.h>
#include <framework/core/clock.h>
#include <framework/core/eventdispatcher.h>
#include <framework/core/asyncdispatcher.h>
#include <framework/platform/platformwindow.h>
#include <framework/ui/uimanager.h>
#include <framework/graphics/graph.h>
#include <framework/graphics/graphics.h>
#include <framework/graphics/texturemanager.h>
#include <framework/graphics/painter.h>
#include <framework/graphics/framebuffermanager.h>
#include <framework/graphics/fontmanager.h>
#include <framework/graphics/atlas.h>
#include <framework/graphics/image.h>
#include <framework/graphics/textrender.h>
#include <framework/graphics/shadermanager.h>
#include <framework/input/mouse.h>
#include <framework/html/htmlmanager.h>
#include <framework/util/extras.h>
#include <framework/util/stats.h>
#include <mutex>

#ifdef FW_SOUND
#include <framework/sound/soundmanager.h>
#endif

GraphicalApplication g_app;

namespace {
    // Fallback FPS used when VSync is requested but could not be applied by the driver.
    // This prevents an unbounded render loop when swapBuffers() does not block.
    constexpr int VSYNC_FALLBACK_FPS = 100;
    // Target FPS when the window is visible but does not have focus.
    constexpr int UNFOCUSED_FPS = 30;
    // Target FPS when the window is minimized or hidden.
    constexpr int HIDDEN_FPS = 10;
    // Maximum extra sleep between frames to keep latency low.
    constexpr ticks_t MAX_FRAME_SLEEP_US = 2000;

    int effectiveFpsCap(const GraphicalApplication& app)
    {
        if (!g_window.isVisible())
            return HIDDEN_FPS;
        if (!g_window.hasFocus())
            return UNFOCUSED_FPS;
        if (app.isUnlimitedFps())
            return 0;
        if (app.isVerticalSyncRequested()) {
            // If the driver did not apply VSync, use a software fallback cap.
            return g_window.hasVerticalSyncApplied() ? 0 : VSYNC_FALLBACK_FPS;
        }
        const int maxFps = app.getMaxFps();
        return maxFps > 0 ? maxFps : VSYNC_FALLBACK_FPS;
    }

    ticks_t frameDelayForCap(int cap)
    {
        if (cap <= 0)
            return 0;
        return 1000000 / cap;
    }

    bool shouldThrottleFrame(ticks_t lastRender, ticks_t frameDelay, ticks_t now)
    {
        return frameDelay > 0 && lastRender + frameDelay > now;
    }

    ticks_t sleepUntilRender(ticks_t lastRender, ticks_t frameDelay, ticks_t now)
    {
        const ticks_t remaining = lastRender + frameDelay - now;
        return std::min(remaining, MAX_FRAME_SLEEP_US);
    }
}

void GraphicalApplication::init(std::vector<std::string>& args)
{
    Application::init(args);

    // setup platform window
    g_window.init();
    g_graphics.checkForError(__FUNCTION__, __FILE__, __LINE__);
    g_window.hide();
    g_window.setOnResize(std::bind(&GraphicalApplication::resize, this, std::placeholders::_1));
    g_window.setOnInputEvent(std::bind(&GraphicalApplication::inputEvent, this, std::placeholders::_1));
    g_window.setOnClose(std::bind(&GraphicalApplication::close, this));
    g_graphics.checkForError(__FUNCTION__, __FILE__, __LINE__);

    g_mouse.init();

    // initialize ui
    g_ui.init();

    // initialize graphics
    g_graphics.init();

    // fire first resize event
    resize(g_window.getSize());

#ifdef FW_SOUND
    // initialize sound
    g_sounds.init();
#endif
}

void GraphicalApplication::deinit()
{
    // hide the window because there is no render anymore
    g_window.hide();
    g_asyncDispatcher.terminate();

    Application::deinit();
}

void GraphicalApplication::terminate()
{
    // destroy any remaining widget
    g_html.terminate();
    g_ui.terminate();

    Application::terminate();
    m_terminated = false;

#ifdef FW_SOUND
    // terminate sound
    g_sounds.terminate();
#endif

    g_mouse.terminate();

    // terminate graphics
    g_graphicsDispatcher.shutdown();
    g_graphics.terminate();
    g_window.terminate();

    m_terminated = true;
}

void GraphicalApplication::run()
{
    m_running = true;
    m_windowPollTimer.restart();

    // first clock update
    g_clock.update();

    // run the first poll
    poll();
    pollGraphics();
    g_clock.update();

    // show window
    g_window.show();

    // run the second poll
    poll();
    pollGraphics();
    g_clock.update();

    g_lua.callGlobalField("g_app", "onRun");

    m_framebuffer = g_framebuffers.createFrameBuffer();
    m_framebuffer->resize(g_painter->getResolution());
    m_mapFramebuffer = g_framebuffers.createFrameBuffer();
    m_mapFramebuffer->resize(g_painter->getResolution());
    m_mapFramebuffer->setSmooth(m_mapSmooth.load());
    m_uiFramebuffer = g_framebuffers.createFrameBuffer();
    m_uiFramebuffer->resize(g_painter->getResolution());
    m_uiFramebuffer->setSmooth(false);

    ticks_t lastRender = stdext::micros();

    std::shared_ptr<DrawQueue> drawQueue;
    std::shared_ptr<DrawQueue> drawMapQueue;
    std::shared_ptr<DrawQueue> drawMapForegroundQueue;
    bool isOnline = false;
    size_t totalFrames = 0;

    std::mutex mutex;
    std::thread worker([&] {
        g_dispatcherThreadId = std::this_thread::get_id();

        ticks_t uiBuildLast = 0;
        ticks_t mapBuildLast = 0;
        ticks_t logicPollLast = 0;

        while (!m_stopping) {
            m_processingFrames.addFrame();

            // Logic/network polling should continue at a steady rate independent of rendering.
            const ticks_t now = stdext::micros();
            if (now - logicPollLast >= 1000) {
                g_clock.update();
                poll();
                g_clock.update();
                logicPollLast = now;
            }

            const bool visible = g_window.isVisible();
            const bool focused = g_window.hasFocus();
            const bool online = isOnline;

            // Throttle visual work when hidden or unfocused, but never stop logic polling.
            const int visualCap = !visible ? HIDDEN_FPS : (!focused ? UNFOCUSED_FPS : (m_maxFps.load() > 0 ? m_maxFps.load() : 0));
            const ticks_t visualDelay = frameDelayForCap(visualCap);
            if (visualDelay > 0 && now - uiBuildLast < visualDelay && now - mapBuildLast < visualDelay && !m_mustRepaint.load()) {
                AutoStat s(STATS_MAIN, "Sleep");
                const ticks_t sleepUs = std::min(visualDelay - std::min(now - uiBuildLast, now - mapBuildLast), MAX_FRAME_SLEEP_US);
                stdext::microsleep(sleepUs);
                continue;
            }

            {
                std::unique_lock<std::mutex> lock(mutex);
                const bool cacheUI = m_cacheUI.load();
                const bool queuesPending = cacheUI ? drawMapQueue != nullptr : drawQueue && drawMapQueue;
                if (queuesPending && (m_maxFps.load() > 0 || g_window.hasVerticalSync())) {
                    lock.unlock();
                    AutoStat s(STATS_MAIN, "Sleep");
                    stdext::millisleep(1);
                    continue;
                }
                lock.unlock();
            }

            // Build map queues only when useful: online and not throttled.
            if (online && (visualDelay == 0 || now - mapBuildLast >= visualDelay || m_mustRepaint.load())) {
                ticks_t renderStart = stdext::millis();
                std::shared_ptr<DrawQueue> mapBackgroundQueue;
                {
                    AutoStat s(STATS_MAIN, "DrawMapBackground");
                    g_drawQueue = std::make_shared<DrawQueue>();
                    g_ui.render(Fw::MapBackgroundPane);
                    mapBackgroundQueue = g_drawQueue;
                }
                std::shared_ptr<DrawQueue> mapForegroundQueue;
                {
                    AutoStat s(STATS_MAIN, "DrawMapForeground");
                    g_drawQueue = std::make_shared<DrawQueue>();
                    g_ui.render(Fw::MapForegroundPane);
                    mapForegroundQueue = g_drawQueue;
                }

                {
                    std::unique_lock<std::mutex> lock(mutex);
                    drawMapQueue = mapBackgroundQueue;
                    drawMapForegroundQueue = mapForegroundQueue;
                }
                mapBuildLast = now;
                g_graphs[GRAPH_CPU_FRAME_TIME].addValue(stdext::millis() - renderStart);
            }

            // Build foreground UI queue at its own cadence.
            const bool buildForeground = !m_cacheUI.load() || m_mustRepaint.load() || now - uiBuildLast >= 16666;
            if (buildForeground) {
                ticks_t renderStart = stdext::millis();
                std::shared_ptr<DrawQueue> foregroundQueue;
                {
                    AutoStat s(STATS_MAIN, "DrawForeground");
                    g_drawQueue = std::make_shared<DrawQueue>();
                    g_ui.render(Fw::ForegroundPane);
                    foregroundQueue = g_drawQueue;
                }

                {
                    std::unique_lock<std::mutex> lock(mutex);
                    drawQueue = foregroundQueue;
                    g_drawQueue = nullptr;
                }
                uiBuildLast = now;
                g_graphs[GRAPH_CPU_FRAME_TIME].addValue(stdext::millis() - renderStart);
            }

            if (visualDelay > 0) {
                AutoStat s(STATS_MAIN, "Sleep");
                stdext::microsleep(std::min(visualDelay, MAX_FRAME_SLEEP_US));
            }
        }
        g_dispatcher.poll(); // last poll
        g_dispatcherThreadId = g_mainThreadId;
    });

    std::shared_ptr<DrawQueue> toDrawQueue, toDrawMapQueue, toDrawMapForegroundQueue;
    ticks_t lastFrame = stdext::millis();
    ticks_t uiCacheLastRender = 0;
    Size uiCacheSize;
    while (!m_stopping) {
        m_iteration += 1;

        g_clock.update();
        pollGraphics();

        const bool visible = g_window.isVisible();
        const bool focused = g_window.hasFocus();

        // Even when invisible we need to keep processing graphics events and avoid busy waiting.
        if (!visible) {
            AutoStat s(STATS_RENDER, "Sleep");
            const int cap = HIDDEN_FPS;
            const ticks_t delay = frameDelayForCap(cap);
            const ticks_t now = stdext::micros();
            if (shouldThrottleFrame(lastRender, delay, now)) {
                stdext::microsleep(sleepUntilRender(lastRender, delay, now));
            } else {
                g_adaptiveRenderer.refresh();
                lastRender = now;
            }
            continue;
        }

        const int cap = effectiveFpsCap(*this);
        const ticks_t frameDelay = frameDelayForCap(cap);
        ticks_t now = stdext::micros();
        if (shouldThrottleFrame(lastRender, frameDelay, now) && !m_mustRepaint.load()) {
            AutoStat s(STATS_RENDER, "Sleep");
            stdext::microsleep(sleepUntilRender(lastRender, frameDelay, now));
            continue;
        }

        {
            std::unique_lock<std::mutex> lock(mutex);
            const bool cacheUI = m_cacheUI.load();
            if ((!drawQueue && !toDrawQueue) || 
                ((!drawMapQueue || !drawMapForegroundQueue) && isOnline) || 
                (m_mustRepaint.load() && !drawQueue && !cacheUI)) {
                lock.unlock();
                AutoStat s(STATS_RENDER, "Wait");
                stdext::millisleep(1);
                continue;
            }
            toDrawQueue = drawQueue ? drawQueue : toDrawQueue;
            toDrawMapQueue = drawMapQueue;
            toDrawMapForegroundQueue = drawMapForegroundQueue;
            drawQueue = drawMapQueue = drawMapForegroundQueue = nullptr;
        }

        g_adaptiveRenderer.newFrame();
        m_graphicsFrames.addFrame();
        const bool repaintRequested = m_mustRepaint.exchange(false);

        // Advance the render deadline by frameDelay to keep a steady cadence and avoid drift.
        if (frameDelay > 0) {
            lastRender += frameDelay;
            const ticks_t now = stdext::micros();
            if (now > lastRender + frameDelay)
                lastRender = now;
        } else {
            lastRender = stdext::micros();
        }

        g_painter->resetDraws();
        if (m_scaling > 1.0f) {
            AutoStat s(STATS_RENDER, "SetupScaling");
            g_painter->setResolution(g_graphics.getViewportSize() / m_scaling);
            m_framebuffer->resize(g_painter->getResolution());
            m_framebuffer->bind();
        }

        if (toDrawMapQueue && toDrawMapQueue->hasFrameBuffer()) {
            AutoStat s(STATS_RENDER, "UpdateMap");
            m_mapFramebuffer->resize(toDrawMapQueue->getFrameBufferSize());
            m_mapFramebuffer->bind();
            g_painter->clear(Color::black);
            toDrawMapQueue->draw(DRAW_ALL);
            m_mapFramebuffer->release();
        }

        {
            AutoStat s(STATS_RENDER, "Clear");
            g_painter->clear(Color::alpha);
        }

        {
            AutoStat s(STATS_RENDER, "DrawFirstForeground");
            if (toDrawQueue)
                toDrawQueue->draw(DRAW_BEFORE_MAP);
        }

        if(toDrawMapQueue) {
            isOnline = toDrawMapQueue->hasFrameBuffer();
            if(isOnline) {
                AutoStat s(STATS_RENDER, "DrawMapBackground");
                PainterShaderProgramPtr shader = nullptr;
                if (!toDrawMapQueue->getShader().empty()) {
                    shader = g_shaders.getShader(toDrawMapQueue->getShader());
                    
                    if(shader) {
                        auto walkOffset = toDrawMapQueue->getWalkOffset();
                        shader->updateWalkOffset(walkOffset);
                    }
                }
                if (shader) {
                    g_painter->setShaderProgram(shader);
                    shader->bindMultiTextures();
                    shader->setCenter(toDrawMapQueue->getFrameBufferDest().center());
                    shader->setOffset(toDrawMapQueue->getFrameBufferSrc().topLeft());
                }
                m_mapFramebuffer->draw(toDrawMapQueue->getFrameBufferDest(), toDrawMapQueue->getFrameBufferSrc());
                if (shader) {
                    g_painter->resetShaderProgram();
                }
            }
            if(toDrawMapForegroundQueue) {
                AutoStat s(STATS_RENDER, "DrawMapForeground");
                toDrawMapForegroundQueue->draw();
            }
        }

        {
            AutoStat s(STATS_RENDER, "DrawSecondForeground");
            const bool cacheUI = m_cacheUI.load();
            if (cacheUI) {
                const Size uiResolution = g_painter->getResolution();
                const ticks_t uiNow = stdext::micros();

                if (uiResolution != uiCacheSize || repaintRequested || uiNow - uiCacheLastRender >= 16666) {
                    m_uiFramebuffer->resize(uiResolution);
                    m_uiFramebuffer->bind();
                    g_painter->clear(Color::alpha);
                    toDrawQueue->draw(DRAW_AFTER_MAP);
                    m_uiFramebuffer->release();
                    uiCacheLastRender = uiNow;
                    uiCacheSize = uiResolution;
                }

                g_painter->resetState();
                m_uiFramebuffer->draw(Rect(0, 0, uiResolution));
            } else {
                toDrawQueue->draw(DRAW_AFTER_MAP);
            }
        }

        {
            if (g_extras.debugRender) {
                AutoStat s(STATS_RENDER, "DrawGraphs");
                for (int i = 0, x = 60, y = 30; i <= GRAPH_LAST; ++i) {
                    g_graphs[i].draw(Rect(x, y, Size(200, 60)));
                    y += 70;
                    if (y + 70 > g_painter->getResolution().height()) {
                        x += 220;
                        y = 30;
                    }
                }
            }
        }

        if (m_scaling > 1.0f) {
            AutoStat s(STATS_RENDER, "DrawScaled");
            m_framebuffer->release();
            g_painter->setResolution(g_graphics.getViewportSize());
            g_painter->clear(Color::alpha);
            m_framebuffer->draw(Rect(0, 0, g_painter->getResolution()));
        }

        g_graphs[GRAPH_GPU_CALLS].addValue(g_painter->calls());
        g_graphs[GRAPH_GPU_DRAWS].addValue(g_painter->draws());

        AutoStat s(STATS_RENDER, "SwapBuffers");
        g_window.swapBuffers();
        g_graphics.checkForError(__FUNCTION__, __FILE__, __LINE__);
        g_graphs[GRAPH_TOTAL_FRAME_TIME].addValue(stdext::millis() - lastFrame);
        lastFrame = stdext::millis();
        totalFrames += 1;
    }

    worker.join();
    g_graphicsDispatcher.poll();

    m_framebuffer = nullptr;
    m_mapFramebuffer = nullptr;
    m_uiFramebuffer = nullptr;
    g_drawQueue = nullptr;
    m_stopping = false;
    m_running = false;
}

void GraphicalApplication::poll() {
    ticks_t start = stdext::millis();
#ifdef FW_SOUND
    g_sounds.poll();
#endif
    Application::poll();
    g_graphs[GRAPH_PROCESSING_POLL].addValue(stdext::millis() - start, true);
}

void GraphicalApplication::pollGraphics()
{
    ticks_t start = stdext::millis();
    g_graphicsDispatcher.poll();
    g_text.poll();
    if (m_windowPollTimer.elapsed_millis() > 10) {
        g_window.poll();
        m_windowPollTimer.restart();
    }
    g_graphs[GRAPH_GRAPHICS_POLL].addValue(stdext::millis() - start, true);
}

void GraphicalApplication::close()
{
    VALIDATE(std::this_thread::get_id() == g_dispatcherThreadId);
    m_onInputEvent = true;
    Application::close();
    m_onInputEvent = false;
}

void GraphicalApplication::resize(const Size& size)
{
    VALIDATE(std::this_thread::get_id() == g_mainThreadId);
    g_graphics.resize(size); // uses painter
    scale(m_scaling); // thread safe
}

void GraphicalApplication::inputEvent(InputEvent event)
{
    VALIDATE(std::this_thread::get_id() == g_dispatcherThreadId);
    m_onInputEvent = true;
    g_ui.inputEvent(event);
    m_onInputEvent = false;
    if (m_cacheUI.load() && event.type != Fw::MouseMoveInputEvent)
        m_mustRepaint = true;
}

void GraphicalApplication::doScreenshot(std::string file)
{
    if (g_mainThreadId != std::this_thread::get_id()) {
        g_graphicsDispatcher.addEvent(std::bind(&GraphicalApplication::doScreenshot, this, file));
        return;
    }

    if (file.empty()) {
        file = "screenshot.png";
    }
    auto resolution = g_graphics.getViewportSize();
    int width = resolution.width();
    int height = resolution.height();
    auto pixels = std::make_shared<std::vector<uint8_t>>(width * height * 4 * sizeof(GLubyte), 0);
    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, (GLubyte*)(pixels->data()));

    g_asyncDispatcher.dispatch([resolution, pixels, file] {
        for (int line = 0, h = resolution.height(), w = resolution.width(); line != h / 2; ++line) {
            std::swap_ranges(
                pixels->begin() + 4 * w * line,
                pixels->begin() + 4 * w * (line + 1),
                pixels->begin() + 4 * w * (h - line - 1));
        }
        try {
            Image image(resolution, 4, pixels->data());
            image.savePNG(file);
        } catch (stdext::exception& e) {
            g_logger.error(std::string("Can't do screenshot: ") + e.what());
        }
    });
}

void GraphicalApplication::scaleUp()
{
    if (g_mainThreadId != std::this_thread::get_id()) {
        g_graphicsDispatcher.addEvent(std::bind(&GraphicalApplication::scaleUp, this));
        return;
    }
    scale(m_scaling + 0.5);
}

void GraphicalApplication::scaleDown()
{
    if (g_mainThreadId != std::this_thread::get_id()) {
        g_graphicsDispatcher.addEvent(std::bind(&GraphicalApplication::scaleDown, this));
        return;
    }
    scale(m_scaling - 0.5);
}

void GraphicalApplication::scale(float value)
{
    if (g_mainThreadId != std::this_thread::get_id()) {
        g_graphicsDispatcher.addEvent(std::bind(&GraphicalApplication::scale, this, value));
        return;
    }

    float maxScale = std::min<float>((g_graphics.getViewportSize().height() / 180),
                                        g_graphics.getViewportSize().width() / 280);
    if (maxScale < 2.0)
        maxScale = 2.0;
    maxScale /= 2;

    if (m_scaling == value) {
        value = m_lastScaling;
    } else {
        m_lastScaling = std::max<float>(1.0, std::min<float>(maxScale, value));
    }

    m_scaling = std::max<float>(1.0, std::min<float>(maxScale, value));
    g_window.setScaling(m_scaling);

    g_dispatcher.addEvent([&] {
        m_onInputEvent = true;
        g_ui.resize(g_graphics.getViewportSize() / m_scaling);
        m_onInputEvent = false;
        m_mustRepaint = true;
    });
}

void GraphicalApplication::setSmooth(bool value)
{
    m_mapSmooth = value;
    const FrameBufferPtr mapFramebuffer = m_mapFramebuffer;
    if (!mapFramebuffer)
        return;

    g_graphicsDispatcher.addEvent([mapFramebuffer, value] {
        mapFramebuffer->setSmooth(value);
    });
}

void GraphicalApplication::doMapScreenshot(std::string fileName)
{
    if (!m_mapFramebuffer) return;

    m_mapFramebuffer->doScreenshot(fileName);
}
