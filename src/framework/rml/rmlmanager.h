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

#pragma once

#include <framework/core/declarations.h>
#include <framework/graphics/declarations.h>

#include <atomic>
#include <functional>
#include <mutex>
#include <set>
#include <unordered_map>

class UIRmlWidget;
class RmlRenderer;
using UIRmlWidgetPtr = std::shared_ptr<UIRmlWidget>;

namespace Rml { class SystemInterface; class FileInterface; }

// RmlUi (HTML/CSS) integration, exposed to Lua as g_rml.
//
// Same model as Ninja World Online's RmlManager: one Rml::Context per UIRmlWidget, documents
// loaded through g_resources, fonts from /fonts/rml, a theme "efeitos" active whenever the
// OpenGL 3.3 backend (filters, shadows, gradients, masks) is available, virtual images
// item/<id>.png, effect/<id>.png and outfit/<looktype>-<head>-<body>-<legs>-<feet>-<addons>-<dir>.png.
class RmlManager
{
public:
    // kind = "item" | "effect" | "outfit", args = numbers of the path
    using ImageProvider = std::function<ImagePtr(std::string_view kind, const std::vector<int>& args)>;

    RmlManager();
    ~RmlManager();

    bool init();
    void terminate();

    bool isReady();
    bool supportsAdvancedEffects() const { return m_advancedEffects; }
    std::string getBackendName() const;

    void setReportEnabled(bool enabled) { m_reportEnabled = enabled; }
    bool isReportEnabled() const { return m_reportEnabled; }

    bool loadFontFace(const std::string& path, bool fallback = false);

    static std::string utf8(std::string_view latin1Text);
    static std::string latin1(std::string_view utf8Text);

    int getWidgetCount() const { return static_cast<int>(m_widgets.size()); }
    int getContextCount();
    std::vector<UIRmlWidgetPtr> getWidgets();

    void setImageProvider(ImageProvider provider) { m_imageProvider = std::move(provider); }
    // Tells when the game assets (.dat/.spr or appearances) are usable; when it turns true, every
    // virtual image is reloaded (an image requested before login would otherwise stay empty).
    void setAssetsReadyCheck(std::function<bool()> check) { m_assetsReady = std::move(check); }
    void invalidateVirtualImages();
    ImagePtr loadImage(const std::string& source);

    // RmlUi itself is not thread safe: every call into it goes through this lock.
    std::recursive_mutex& mutex() { return m_mutex; }

    void registerWidget(UIRmlWidget* widget);
    void unregisterWidget(UIRmlWidget* widget);
    void retireRenderer(const std::shared_ptr<RmlRenderer>& renderer);
    void deferContextRelease(const UIRmlWidgetPtr& widget);
    void onBackendResult(bool advanced);
    int nextContextId() { return ++m_lastContextId; }

private:
    void loadFonts();
    bool loadFontFaceOnce(const std::string& path, bool fallback);
    void tick();
    void retryPendingImages();
    void releasePendingContexts();

    std::unique_ptr<Rml::SystemInterface> m_systemInterface;
    std::unique_ptr<Rml::FileInterface> m_fileInterface;

    std::recursive_mutex m_mutex;
    std::vector<UIRmlWidget*> m_widgets;
    std::vector<UIRmlWidgetPtr> m_pendingContextReleases;
    ImageProvider m_imageProvider;
    std::function<bool()> m_assetsReady;
    bool m_lastAssetsReady{ false };
    std::set<std::string> m_virtualSources;
    std::unordered_map<std::string, int> m_pendingImages;
    int m_ticks{ 0 };
    ScheduledEventPtr m_tickEvent;

    std::atomic_bool m_advancedEffects{ true }; // optimistic until the first frame reaches the GPU
    std::atomic_bool m_backendFailed{ false };
    bool m_initialized{ false };
    bool m_initFailed{ false };
    bool m_reportEnabled{ false };
    int m_lastContextId{ 0 };
    std::set<std::string> m_loadedFonts;
};

extern RmlManager g_rml;
