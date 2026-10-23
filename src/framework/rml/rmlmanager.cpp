/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
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

#include "rmlmanager.h"
#include "rmlrenderer.h"
#include "rmlbackend.h"
#include "uirmlwidget.h"

#include <framework/core/eventdispatcher.h>
#include <framework/core/resourcemanager.h>
#include <framework/graphics/image.h>
#include <framework/graphics/graphics.h>
#include <framework/graphics/glutil.h>
#include <framework/luaengine/luainterface.h>
#include <framework/platform/platformwindow.h>
#include <framework/stdext/string.h>
#include <framework/stdext/time.h>

#include <RmlUi/Core.h>
#include <RmlUi/Debugger.h>
#include <RmlUi/Lua.h>
#include <RmlUi/Lua/IncludeLua.h>

#include <regex>
#include <unordered_set>

RmlManager g_rml;

namespace
{
    // RmlUi resolves "/styles/x.rcss" to "styles/x.rcss"; g_resources wants the leading slash
    std::string resourcePath(const std::string& path)
    {
        return !path.empty() && path.front() != '/' ? '/' + path : path;
    }

    class OtSystemInterface final : public Rml::SystemInterface
    {
    public:
        double GetElapsedTime() override { return static_cast<double>(stdext::micros()) / 1000000.0; }

        bool LogMessage(const Rml::Log::Type type, const Rml::String& message) override
        {
            switch (type) {
                case Rml::Log::LT_ERROR:
                case Rml::Log::LT_ASSERT:
                    g_logger.error(stdext::format("[rmlui] %s", message));
                    break;
                case Rml::Log::LT_WARNING:
                    g_logger.warning(stdext::format("[rmlui] %s", message));
                    break;
                case Rml::Log::LT_INFO:
                    g_logger.info(stdext::format("[rmlui] %s", message));
                    break;
                default:
                    g_logger.debug(stdext::format("[rmlui] %s", message));
                    break;
            }
            return true;
        }

        void SetClipboardText(const Rml::String& text) override { g_window.setClipboardText(text); }
        void GetClipboardText(Rml::String& text) override { text = g_window.getClipboardText(); }
    };

    // Reads through g_resources, so documents, stylesheets and fonts come from the same
    // (possibly packed/encrypted) archives as the rest of the client.
    class OtFileInterface final : public Rml::FileInterface
    {
        struct File
        {
            std::string data;
            size_t position{ 0 };
        };

    public:
        Rml::FileHandle Open(const Rml::String& rmlPath) override
        {
            const auto path = resourcePath(rmlPath);
            try {
                if (!g_resources.fileExists(path))
                    return 0;
                return reinterpret_cast<Rml::FileHandle>(new File{ g_resources.readFileContents(path) });
            } catch (const std::exception& e) {
                g_logger.error(stdext::format("[rmlui] unable to read '%s': %s", path, e.what()));
                return 0;
            }
        }

        void Close(const Rml::FileHandle handle) override { delete reinterpret_cast<File*>(handle); }

        size_t Read(void* buffer, const size_t size, const Rml::FileHandle handle) override
        {
            auto* file = reinterpret_cast<File*>(handle);
            const size_t count = std::min(size, file->data.size() - file->position);
            std::memcpy(buffer, file->data.data() + file->position, count);
            file->position += count;
            return count;
        }

        bool Seek(const Rml::FileHandle handle, const long offset, const int origin) override
        {
            auto* file = reinterpret_cast<File*>(handle);
            size_t base = 0;
            if (origin == SEEK_CUR)
                base = file->position;
            else if (origin == SEEK_END)
                base = file->data.size();
            else if (origin != SEEK_SET)
                return false;
            if (offset >= 0) {
                const auto distance = static_cast<unsigned long>(offset);
                if (distance > file->data.size() - base) return false;
                file->position = base + distance;
            } else {
                const auto distance = static_cast<unsigned long>(-(offset + 1)) + 1;
                if (distance > base) return false;
                file->position = base - distance;
            }
            return true;
        }

        size_t Tell(const Rml::FileHandle handle) override { return reinterpret_cast<File*>(handle)->position; }
        size_t Length(const Rml::FileHandle handle) override { return reinterpret_cast<File*>(handle)->data.size(); }

        bool LoadFile(const Rml::String& rmlPath, Rml::String& out_data) override
        {
            const auto path = resourcePath(rmlPath);
            try {
                if (!g_resources.fileExists(path))
                    return false;
                out_data = g_resources.readFileContents(path);
                return true;
            } catch (const std::exception& e) {
                g_logger.error(stdext::format("[rmlui] unable to read '%s': %s", path, e.what()));
                return false;
            }
        }
    };
}

RmlManager::RmlManager() = default;
RmlManager::~RmlManager() = default;

bool RmlManager::init()
{
    if (m_initialized)
        return true;
    if (m_initFailed)
        return false;

    std::scoped_lock lock(m_mutex);

#ifdef OPENGL_ES
    const bool supported = RmlBackend::supportsGles3(g_graphics.getVersion());
#else
    const bool supported = GLEW_VERSION_3_3;
#endif
    if (!g_graphics.ok() || !supported) {
        m_initFailed = true;
        m_backendFailed = true;
        m_advancedEffects = false;
        g_logger.warning("[rmlui] OpenGL 3.3 / ANGLE ES 3.0 is unavailable; keeping the standard OTUI interface");
        return false;
    }

    m_systemInterface = std::make_unique<OtSystemInterface>();
    m_fileInterface = std::make_unique<OtFileInterface>();
    Rml::SetSystemInterface(m_systemInterface.get());
    Rml::SetFileInterface(m_fileInterface.get());

    // No global render interface: every UIRmlWidget gives its own RmlRenderer to its context.
    if (!Rml::Initialise()) {
        g_logger.error("[rmlui] Rml::Initialise failed");
        m_initFailed = true;
        return false;
    }

    // The plugin replaces _G.print; keep Astra's existing logger semantics.
    auto* state = g_lua.getLuaState();
    lua_getglobal(state, "print");
    const int printRef = luaL_ref(state, LUA_REGISTRYINDEX);
    Rml::Lua::Initialise(state);
    lua_rawgeti(state, LUA_REGISTRYINDEX, printRef);
    lua_setglobal(state, "print");
    luaL_unref(state, LUA_REGISTRYINDEX, printRef);
    loadFonts();

    m_initialized = true;

    g_logger.info(stdext::format("[rmlui] ready - RmlUi %s (backend %s)", Rml::GetVersion(), getBackendName()));
    return true;
}

void RmlManager::terminate()
{
    if (!m_initialized)
        return;

    std::scoped_lock lock(m_mutex);

    if (m_tickEvent) {
        m_tickEvent->cancel();
        m_tickEvent = nullptr;
    }

    releasePendingContexts();
    for (const auto& widget : getWidgets())
        widget->releaseContext();

    Rml::Shutdown();
    m_loadedFonts.clear();
    // GraphicalApplication calls terminate on the graphics thread, before Lua/GL die.
    // Drain retained renderers now rather than leaving GL destructors to late Lua GC.
    g_graphicsDispatcher.poll();
    m_virtualSources.clear();
    m_pendingImages.clear();
    m_imageProvider = {};
    m_assetsReady = {};
    m_systemInterface.reset();
    m_fileInterface.reset();
    m_initFailed = true; // shutdown is terminal; never initialise after Lua/GL termination
    m_widgets.clear();
    m_initialized = false;
}

bool RmlManager::isReady()
{
    return init() && !m_backendFailed;
}

std::string RmlManager::getBackendName() const
{
    if (m_backendFailed)
        return "unavailable";
#ifdef OPENGL_ES
    return m_advancedEffects ? "ANGLE ES 3.0 (full effects)" : "ANGLE ES 3.0";
#else
    return m_advancedEffects ? "OpenGL 3.3 (full effects)" : "OpenGL 3.3";
#endif
}

void RmlManager::onBackendResult(const bool advanced)
{
    if (!advanced) {
        m_backendFailed = true;
        m_advancedEffects = false;
    }
}

bool RmlManager::loadFontFace(const std::string& path, const bool fallback)
{
    if (!init())
        return false;

    std::scoped_lock lock(m_mutex);
    return loadFontFaceOnce(path, fallback);
}

bool RmlManager::loadFontFaceOnce(const std::string& path, const bool fallback)
{
    // Resolve aliases such as /fonts/rml and /data/fonts/rml to the same key.
    // Re-loading a variable font can invalidate FreeType's shared face data in
    // RmlUi 6.3; successful loads must be idempotent for this RmlUi lifetime.
    const auto resolved = g_resources.resolvePath(resourcePath(path));
    if (m_loadedFonts.contains(resolved))
        return true;
    if (!Rml::LoadFontFace(resolved, fallback)) {
        g_logger.warning(stdext::format("[rmlui] font '%s' could not be loaded", path));
        return false;
    }
    m_loadedFonts.insert(resolved);
    return true;
}

void RmlManager::loadFonts()
{
    int loaded = 0;
    for (const char* dir : { "/fonts/rml", "/data/fonts/rml" }) {
        std::list<std::string> files;
        try {
            files = g_resources.listDirectoryFiles(dir, true);
        } catch (...) {
            continue;
        }

        for (const auto& file : files) {
            auto ext = file.size() > 4 ? file.substr(file.size() - 4) : std::string();
            stdext::tolower(ext);
            if (ext != ".ttf" && ext != ".otf")
                continue;
            // the first face loaded becomes the fallback for missing glyphs
            if (loadFontFaceOnce(file, loaded == 0))
                ++loaded;
        }
        if (loaded > 0)
            break;
    }

    if (loaded == 0)
        g_logger.warning("[rmlui] no font found in /fonts/rml - documents will have no text until g_rml.loadFontFace() is called");
}

std::string RmlManager::utf8(const std::string_view latin1Text)
{
    return stdext::latin1_to_utf8(std::string(latin1Text));
}

std::string RmlManager::latin1(const std::string_view utf8Text)
{
    return stdext::utf8_to_latin1(std::string(utf8Text));
}

std::vector<UIRmlWidgetPtr> RmlManager::getWidgets()
{
    std::vector<UIRmlWidgetPtr> widgets;
    widgets.reserve(m_widgets.size());
    for (auto* widget : m_widgets) {
        if (auto owner = widget->weak_from_this().lock())
            widgets.emplace_back(std::static_pointer_cast<UIRmlWidget>(owner));
    }
    return widgets;
}

int RmlManager::getContextCount()
{
    std::scoped_lock lock(m_mutex);
    return m_initialized ? Rml::GetNumContexts() : 0;
}

void RmlManager::registerWidget(UIRmlWidget* widget)
{
    m_widgets.emplace_back(widget);
    if (!m_tickEvent)
        m_tickEvent = g_dispatcher.cycleEventEx("RmlManager::tick", [this] { tick(); }, 16);
}

void RmlManager::unregisterWidget(UIRmlWidget* widget)
{
    std::erase(m_widgets, widget);
}

void RmlManager::retireRenderer(const std::shared_ptr<RmlRenderer>& renderer)
{
    if (!renderer)
        return;

    {
        std::scoped_lock lock(m_mutex);
        Rml::ReleaseTextures(renderer.get());
        Rml::ReleaseCompiledGeometry(renderer.get());
        Rml::ReleaseRenderManagers();
        renderer->retire();
        const auto sources = Rml::GetTextureSourceList();
        const std::unordered_set<std::string> active(sources.begin(), sources.end());
        std::erase_if(m_virtualSources, [&](const auto& source) { return !active.contains(source); });
        std::erase_if(m_pendingImages, [&](const auto& entry) { return !active.contains(entry.first); });
    }

    // RemoveContext + ReleaseRenderManagers release the library's reference first.
    // The graphics dispatcher and draw items retain this renderer until GL cleanup.
    g_graphicsDispatcher.addEvent([renderer] { renderer->releaseGl(); });
}

void RmlManager::tick()
{
    releasePendingContexts();
    // Unloading one document can destroy another host and queue its release.
    // Keep the next tick alive until that reentrant cleanup has also drained.
    if (m_widgets.empty() && m_pendingContextReleases.empty()) {
        m_tickEvent->cancel();
        m_tickEvent = nullptr;
        return;
    }
    if (m_assetsReady) {
        const bool ready = m_assetsReady();
        if (ready != m_lastAssetsReady) {
            m_lastAssetsReady = ready;
            if (ready)
                invalidateVirtualImages();
        }
    }

    if (++m_ticks >= 60) {
        m_ticks = 0;
        retryPendingImages();
    }

    for (const auto& widget : getWidgets()) {
        if (!widget->isDestroyed())
            widget->tick();
    }
}

void RmlManager::deferContextRelease(const UIRmlWidgetPtr& widget)
{
    m_pendingContextReleases.push_back(widget);
}

void RmlManager::releasePendingContexts()
{
    // Called outside Lua/RmlUi dispatch, including direct DOM event dispatch from Lua.
    auto pending = std::exchange(m_pendingContextReleases, {});
    for (const auto& widget : pending)
        widget->releaseContext();
}

void RmlManager::invalidateVirtualImages()
{
    if (!m_initialized)
        return;

    std::scoped_lock lock(m_mutex);
    // RmlUi reloads a released texture the next time an element renders it
    for (const auto& source : m_virtualSources)
        Rml::ReleaseTexture(source);
    m_pendingImages.clear();
}

void RmlManager::retryPendingImages()
{
    std::scoped_lock lock(m_mutex);
    for (auto& [source, attempts] : m_pendingImages) {
        if (attempts > 0 && attempts <= 10)
            Rml::ReleaseTexture(source);
    }
}

namespace
{
    ImagePtr scaleNearest(const ImagePtr& image, const int factor)
    {
        const auto& size = image->getSize();
        if (size.width() > 4096 / factor || size.height() > 4096 / factor)
            throw std::runtime_error("RmlUi image exceeds 4096 pixels per axis");
        const int bpp = image->getBpp();
        auto scaled = std::make_shared<Image>(size * factor, bpp);
        const auto& in = image->getPixels();
        auto& out = scaled->getPixels();
        const int outWidth = size.width() * factor;
        for (int y = 0; y < size.height() * factor; ++y) {
            for (int x = 0; x < outWidth; ++x) {
                const auto* src = &in[(static_cast<size_t>(y / factor) * size.width() + x / factor) * bpp];
                std::copy_n(src, bpp, &out[(static_cast<size_t>(y) * outWidth + x) * bpp]);
            }
        }
        return scaled;
    }
}

ImagePtr RmlManager::loadImage(const std::string& source)
{
    // optional @2x..@8x: nearest-neighbour upscale, keeps pixel art sharp
    static const std::regex virtualImage(R"((?:^|/)(item|effect|outfit)/(\d+(?:-\d+)*)(?:@([2-8])x)?\.png$)");
    std::smatch match;
    if (!std::regex_search(source, match, virtualImage))
        return Image::load(resourcePath(source));

    std::scoped_lock lock(m_mutex);
    m_virtualSources.insert(source);

    ImagePtr image;
    if (m_imageProvider && (!m_assetsReady || m_assetsReady())) {
        try {
            image = m_imageProvider(match[1].str(), stdext::split<int>(match[2].str(), "-"));
        } catch (const std::exception& e) {
            g_logger.error(stdext::format("[rmlui] image '%s' could not be drawn: %s", source, e.what()));
        }
    }

    if (image) {
        m_pendingImages.erase(source);
        try {
            if (match[3].matched)
                image = scaleNearest(image, std::stoi(match[3].str()));
            return image;
        } catch (const std::exception& e) {
            // Permanent size errors must not escape RenderInterface or retry every second.
            g_logger.error(stdext::format("[rmlui] image '%s' could not be scaled: %s", source, e.what()));
            return std::make_shared<Image>(Size(32, 32));
        }
    }

    // Not available yet (assets not loaded, sprite file busy): a transparent placeholder keeps
    // the layout and avoids RmlUi's white box; the image is requested again later.
    ++m_pendingImages[source];
    return std::make_shared<Image>(Size(32, 32));
}
