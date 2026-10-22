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

#include <framework/ui/uiwidget.h>

#include "rmlrenderer.h"

namespace Rml { class Context; class ElementDocument; class StyleSheetContainer; }

// An OTUI widget hosting one RmlUi document (HTML/CSS).
//
// Lua:   widget:loadDocument('/modules/x/x.rml'), widget:getContext():OpenDataModel(...)
// OTUI:  rml-source: /modules/x/x.rml      rml-debugger: true
// Events called on the widget: onRmlDocumentLoaded(path), onRmlUpdate(), onRmlLayout()
// RML:   data-drag="window" turns an element into a handle that moves this widget,
//        data-drag="none" opts a descendant out (buttons inside a title bar).
// @bindclass
class UIRmlWidget : public UIWidget
{
public:
    UIRmlWidget();
    ~UIRmlWidget() override;

    bool loadDocument(const std::string& path);
    void unloadDocument();
    bool reloadDocument();
    bool hasDocument() { return !isDestroyed() && m_document != nullptr; }
    std::string getDocumentPath() { return m_documentPath; }

    void setDebuggerVisible(bool visible);
    bool isDebuggerVisible() { return m_debuggerVisible; }

    // Extra RCSS applied over the document's own stylesheets (themes); "" removes it.
    bool setExtraStyleSheet(const std::string& rcss);

    Rml::Context* getContext();
    Rml::ElementDocument* getDocument() { return isDestroyed() ? nullptr : m_document; }

    void tick();

protected:
    void onDestroy() override;
    void drawSelf(Fw::DrawPane drawPane) override;
    void onStyleApply(const std::string& styleName, const OTMLNodePtr& styleNode) override;
    void onHoverChange(bool hovered) override;
    void onFocusChange(bool focused, Fw::FocusReason reason) override;
    bool onMousePress(const Point& mousePos, Fw::MouseButton button) override;
    bool onMouseRelease(const Point& mousePos, Fw::MouseButton button) override;
    bool onMouseMove(const Point& mousePos, const Point& mouseMoved) override;
    bool onMouseWheel(const Point& mousePos, Fw::MouseWheelDirection direction) override;
    bool onKeyText(const std::string& keyText) override;
    bool onKeyDown(uint8_t keyCode, int keyboardModifiers) override;
    bool onKeyPress(uint8_t keyCode, int keyboardModifiers, int autoRepeatTicks) override;
    bool onKeyUp(uint8_t keyCode, int keyboardModifiers) override;

private:
    friend class RmlManager;
    // Keep the native host alive across reentrant script callbacks.
    struct CallScope {
        explicit CallScope(UIRmlWidget& widget);
        ~CallScope();
        UIRmlWidget& widget;
        std::shared_ptr<UIRmlWidget> owner;
        std::unique_lock<std::recursive_mutex> lock;
    };
    bool m_releaseQueued{false};
    bool ensureContext();
    void releaseContext();
    void applyStyleSheet();
    Size contextSize() const;
    int localX(const Point& pos) const { return pos.x - m_rect.x(); }
    int localY(const Point& pos) const { return pos.y - m_rect.y(); }
    std::string findDragMode() const;

    Rml::Context* m_context{ nullptr };
    Rml::ElementDocument* m_document{ nullptr };
    std::string m_contextName;
    std::string m_documentPath;
    std::string m_extraStyleSheet;
    std::shared_ptr<Rml::StyleSheetContainer> m_baseStyleSheet;

    RmlRendererPtr m_renderer;
    RmlTargetTexturePtr m_target;

    bool m_debuggerVisible{ false };
    bool m_effectsTheme{ false };
    bool m_dragging{ false };
    Point m_dragOffset;
};
