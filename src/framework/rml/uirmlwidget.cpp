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

#include "uirmlwidget.h"
#include "rmlmanager.h"

#include <framework/graphics/drawqueue.h>
#include <framework/graphics/painter.h>
#include <framework/platform/platformwindow.h>
#include <framework/otml/otmlnode.h>

#include <RmlUi/Core.h>
#include <RmlUi/Debugger.h>

namespace
{
    // The debugger can only be attached to one context at a time.
    UIRmlWidget* g_debuggerOwner = nullptr;
    bool g_debuggerInitialised = false;

    int toRmlModifiers(const int modifiers)
    {
        int state = 0;
        if (modifiers & Fw::KeyboardCtrlModifier) state |= Rml::Input::KM_CTRL;
        if (modifiers & Fw::KeyboardShiftModifier) state |= Rml::Input::KM_SHIFT;
        if (modifiers & Fw::KeyboardAltModifier) state |= Rml::Input::KM_ALT;
        return state;
    }

    Rml::Input::KeyIdentifier toRmlKey(const uint8_t key)
    {
        using namespace Rml::Input;
        if (key >= Fw::KeyA && key <= Fw::KeyZ)
            return static_cast<KeyIdentifier>(KI_A + (key - Fw::KeyA));
        if (key >= Fw::Key0 && key <= Fw::Key9)
            return static_cast<KeyIdentifier>(KI_0 + (key - Fw::Key0));
        if (key >= Fw::KeyF1 && key <= Fw::KeyF5)
            return static_cast<KeyIdentifier>(KI_F1 + (key - Fw::KeyF1));
        if (key >= Fw::KeyF6 && key <= Fw::KeyF12)
            return static_cast<KeyIdentifier>(KI_F6 + (key - Fw::KeyF6));
        if (key >= Fw::KeyNumpad0 && key <= Fw::KeyNumpad9)
            return static_cast<KeyIdentifier>(KI_NUMPAD0 + (key - Fw::KeyNumpad0));

        switch (key) {
            case Fw::KeyEscape: return KI_ESCAPE;
            case Fw::KeyTab: return KI_TAB;
            case Fw::KeyBackspace: return KI_BACK;
            case Fw::KeyEnter: return KI_RETURN;
            case Fw::KeyInsert: return KI_INSERT;
            case Fw::KeyDelete: return KI_DELETE;
            case Fw::KeyPause: return KI_PAUSE;
            case Fw::KeyHome: return KI_HOME;
            case Fw::KeyEnd: return KI_END;
            case Fw::KeyPageUp: return KI_PRIOR;
            case Fw::KeyPageDown: return KI_NEXT;
            case Fw::KeyUp: return KI_UP;
            case Fw::KeyDown: return KI_DOWN;
            case Fw::KeyLeft: return KI_LEFT;
            case Fw::KeyRight: return KI_RIGHT;
            case Fw::KeyCtrl: return KI_LCONTROL;
            case Fw::KeyShift: return KI_LSHIFT;
            case Fw::KeyAlt: return KI_LMENU;
            case Fw::KeySpace: return KI_SPACE;
            case Fw::KeyComma: return KI_OEM_COMMA;
            case Fw::KeyMinus: return KI_OEM_MINUS;
            case Fw::KeyPeriod: return KI_OEM_PERIOD;
            case Fw::KeyPlus: return KI_OEM_PLUS;
            case Fw::KeySlash: return KI_OEM_2;
            case Fw::KeySemicolon: return KI_OEM_1;
            case Fw::KeyLeftBracket: return KI_OEM_4;
            case Fw::KeyBackslash: return KI_OEM_5;
            case Fw::KeyRightBracket: return KI_OEM_6;
            case Fw::KeyApostrophe: return KI_OEM_7;
            case Fw::KeyGrave: return KI_OEM_3;
            default: return KI_UNKNOWN;
        }
    }

    // Typing in a text field must not trigger OTClient hotkeys (walking, spells...).
    bool isTextField(Rml::Element* element)
    {
        if (!element)
            return false;
        const auto& tag = element->GetTagName();
        if (tag == "textarea")
            return true;
        if (tag != "input")
            return false;
        const auto type = element->GetAttribute<Rml::String>("type", "text");
        return type == "text" || type == "password" || type == "number" || type == "search";
    }

    int toRmlButton(const Fw::MouseButton button)
    {
        switch (button) {
            case Fw::MouseLeftButton: return 0;
            case Fw::MouseRightButton: return 1;
            case Fw::MouseMidButton: return 2;
            default: return 3;
        }
    }
}

UIRmlWidget::UIRmlWidget()
{
    setFocusable(true);
    g_rml.registerWidget(this);
}

UIRmlWidget::~UIRmlWidget()
{
    releaseContext();
    g_rml.unregisterWidget(this);
}

UIRmlWidget::CallScope::CallScope(UIRmlWidget& widget) :
    widget(widget), owner(widget.static_self_cast<UIRmlWidget>()), lock(g_rml.mutex())
{
}

UIRmlWidget::CallScope::~CallScope() = default;

void UIRmlWidget::onDestroy()
{
    m_dragging = false;
    // Lua may retain a destroyed widget indefinitely; it must not keep the tick alive.
    g_rml.unregisterWidget(this);
    if (m_context && !m_releaseQueued) {
        m_releaseQueued = true;
        g_rml.deferContextRelease(static_self_cast<UIRmlWidget>());
    }
}

Size UIRmlWidget::contextSize() const
{
    return { std::clamp(m_rect.width(), 1, 4096), std::clamp(m_rect.height(), 1, 4096) };
}

bool UIRmlWidget::ensureContext()
{
    if (isDestroyed())
        return false;
    if (m_context)
        return true;

    if (!g_rml.isReady())
        return false;

    CallScope scope(*this);

    m_renderer = std::make_shared<RmlRenderer>();
    m_contextName = stdext::format("astra_rml_%d", g_rml.nextContextId());

    const auto size = contextSize();
    m_context = Rml::CreateContext(m_contextName, { size.width(), size.height() }, m_renderer.get());
    if (!m_context) {
        g_logger.error(stdext::format("[rmlui] unable to create context '%s'", m_contextName));
        m_renderer = nullptr;
        return false;
    }

    // RCSS can offer a light and a full version: @media (theme: efeitos) { ... }
    m_effectsTheme = g_rml.supportsAdvancedEffects();
    m_context->ActivateTheme("efeitos", m_effectsTheme);
    return true;
}

void UIRmlWidget::releaseContext()
{
    if (!m_context)
        return;

    {
        std::scoped_lock lock(g_rml.mutex());

        if (g_debuggerOwner == this) {
            Rml::Debugger::SetVisible(false);
            Rml::Debugger::Shutdown();
            g_debuggerInitialised = false;
            g_debuggerOwner = nullptr;
        }

        m_document = nullptr;
        m_baseStyleSheet = nullptr;
        Rml::RemoveContext(m_contextName);
        m_context = nullptr;
    }

    g_rml.retireRenderer(m_renderer);
    m_renderer = nullptr;
    m_target = nullptr;
}

Rml::Context* UIRmlWidget::getContext()
{
    return ensureContext() ? m_context : nullptr;
}

bool UIRmlWidget::loadDocument(const std::string& path)
{
    if (!ensureContext())
        return false;

    {
        CallScope scope(*this);

        if (m_document) {
            auto* previous = std::exchange(m_document, nullptr);
            previous->Close();
            // Unload listeners can destroy the host or load a replacement.
            if (isDestroyed() || !m_context || m_document) return false;
        }

        m_document = m_context->LoadDocument(path);
        if (isDestroyed() || !m_context) return false;
        if (!m_document) {
            g_logger.error(stdext::format("[rmlui] unable to load '%s'", path));
            m_documentPath.clear();
            return false;
        }

        m_documentPath = path;

        // Keep the already compiled document sheet unless an override is requested.
        // Cloning/reapplying it here invalidates all computed styles before Show().
        m_baseStyleSheet = nullptr;
        applyStyleSheet();
        m_document->Show();
    }

    if (isDestroyed() || !m_document) return false;
    callLuaField("onRmlDocumentLoaded", path);
    return true;
}

void UIRmlWidget::unloadDocument()
{
    if (isDestroyed() || !m_document)
        return;

    CallScope scope(*this);
    auto* document = std::exchange(m_document, nullptr);
    m_baseStyleSheet = nullptr;
    m_documentPath.clear();
    document->Close();
    if (!isDestroyed() && m_context)
        m_context->Update();
}

bool UIRmlWidget::reloadDocument()
{
    if (m_documentPath.empty())
        return false;

    const std::string path = m_documentPath;
    {
        CallScope scope(*this);
        Rml::Factory::ClearStyleSheetCache();
        Rml::Factory::ClearTemplateCache();
    }
    return loadDocument(path);
}

void UIRmlWidget::setDebuggerVisible(const bool visible)
{
    m_debuggerVisible = visible;
    if (!ensureContext())
        return;

    CallScope scope(*this);

    if (visible) {
        if (!g_debuggerInitialised) {
            g_debuggerInitialised = Rml::Debugger::Initialise(m_context);
        } else {
            Rml::Debugger::SetContext(m_context);
        }
        g_debuggerOwner = this;
        Rml::Debugger::SetVisible(true);
    } else if (g_debuggerOwner == this) {
        Rml::Debugger::SetVisible(false);
    }
}

bool UIRmlWidget::setExtraStyleSheet(const std::string& rcss)
{
    if (m_extraStyleSheet == rcss)
        return true;
    m_extraStyleSheet = rcss;
    CallScope scope(*this);
    applyStyleSheet();
    return true;
}

void UIRmlWidget::applyStyleSheet()
{
    if (!m_document)
        return;

    if (m_extraStyleSheet.empty()) {
        if (m_baseStyleSheet)
            m_document->SetStyleSheetContainer(m_baseStyleSheet);
        return;
    }

    const auto extra = Rml::Factory::InstanceStyleSheetString(m_extraStyleSheet);
    if (!extra) {
        g_logger.warning(stdext::format("[rmlui] extra stylesheet rejected for '%s'", m_documentPath));
        return;
    }
    if (!m_baseStyleSheet) {
        const auto* base = m_document->GetStyleSheetContainer();
        m_baseStyleSheet = base ? base->CombineStyleSheetContainer(Rml::StyleSheetContainer{}) :
            Rml::Factory::InstanceStyleSheetString("");
    }
    if (!m_baseStyleSheet)
        return;
    m_document->SetStyleSheetContainer(m_baseStyleSheet->CombineStyleSheetContainer(*extra));
}

void UIRmlWidget::tick()
{
    if (isDestroyed() || !m_context || !isVisible())
        return;

    callLuaField("onRmlUpdate");

    if (isDestroyed() || !m_context) // context release is deferred after destroy()
        return;

    {
        CallScope scope(*this);

        const auto size = contextSize();
        const Rml::Vector2i dimensions{ size.width(), size.height() };
        if (m_context->GetDimensions() != dimensions)
            m_context->SetDimensions(dimensions);
        if (isDestroyed()) // SetDimensions can dispatch a Lua resize listener.
            return;

        const bool effects = g_rml.supportsAdvancedEffects();
        if (effects != m_effectsTheme) {
            m_effectsTheme = effects;
            m_context->ActivateTheme("efeitos", effects);
        }

        m_context->Update();
    }

    if (!isDestroyed() && m_context)
        callLuaField("onRmlLayout");
}

void UIRmlWidget::drawSelf(const Fw::DrawPane drawPane)
{
    UIWidget::drawSelf(drawPane);

    if (drawPane != Fw::ForegroundPane || isDestroyed() || !m_context || !m_renderer || m_rect.width() <= 0 || m_rect.height() <= 0)
        return;

    const auto size = contextSize();
    if (!m_renderer->hasPendingFrame() && (!m_target || m_target->getSize() != size))
        m_target = std::make_shared<RmlTargetTexture>(size);

    {
        CallScope scope(*this);
        if (m_renderer->beginFrame(m_target)) {
            m_context->Render();
            m_renderer->endFrame();
        }
    }

    // One queue item replays GL work and composites it in Astra's normal clip/opacity order.
    struct RmlDrawItem final : DrawQueueItem {
        RmlDrawItem(RmlRendererPtr renderer, RmlTargetTexturePtr target, const Rect& rect) :
            DrawQueueItem(target), renderer(std::move(renderer)), target(std::move(target)), rect(rect) {}
        void draw() override {
            renderer->replay();
            g_painter->refreshState();
            const auto composition = g_painter->getCompositionMode();
            g_painter->setCompositionMode(Painter::CompositionMode_Premultiplied);
            // A premultiplied texture needs opacity applied to RGB as well as alpha.
            const float opacity = m_color.aF();
            g_painter->setColor(Color(opacity, opacity, opacity, opacity));
            g_painter->drawTexturedRect(rect, target, Rect(Point(0, 0), target->getSize()));
            g_painter->setCompositionMode(composition);
        }
        RmlRendererPtr renderer;
        RmlTargetTexturePtr target;
        Rect rect;
    };
    if (m_target)
        g_drawQueue->add(std::make_unique<RmlDrawItem>(m_renderer, m_target, m_rect));
}

void UIRmlWidget::onStyleApply(const std::string& styleName, const OTMLNodePtr& styleNode)
{
    UIWidget::onStyleApply(styleName, styleNode);

    for (const auto& node : styleNode->children()) {
        if (node->tag() == "rml-source")
            loadDocument(node->value());
        else if (node->tag() == "rml-debugger")
            setDebuggerVisible(node->value<bool>());
    }
}

std::string UIRmlWidget::findDragMode() const
{
    for (auto* element = m_context ? m_context->GetHoverElement() : nullptr; element; element = element->GetParentNode()) {
        if (const auto* value = element->GetAttribute("data-drag"))
            return value->Get<Rml::String>();
    }
    return {};
}

void UIRmlWidget::onHoverChange(const bool hovered)
{
    UIWidget::onHoverChange(hovered);
    if (!isDestroyed() && !hovered && m_context && !m_dragging) {
        CallScope scope(*this);
        m_context->ProcessMouseLeave();
    }
}

void UIRmlWidget::onFocusChange(const bool focused, const Fw::FocusReason reason)
{
    UIWidget::onFocusChange(focused, reason);
    if (!isDestroyed() && !focused && m_context) {
        CallScope scope(*this);
        if (auto* focus = m_context->GetFocusElement())
            focus->Blur();
    }
}

bool UIRmlWidget::onMousePress(const Point& mousePos, const Fw::MouseButton button)
{
    if (isDestroyed()) return true;
    bool consumed = false;
    if (m_context) {
        CallScope scope(*this);
        m_context->ProcessMouseMove(localX(mousePos), localY(mousePos), 0);
        if (isDestroyed() || !m_context) return true;
        consumed = !m_context->ProcessMouseButtonDown(toRmlButton(button), 0);
        if (isDestroyed()) return true;

        if (button == Fw::MouseLeftButton && findDragMode() == "window") {
            // anchors (e.g. RmlWindow's centerIn) would put the widget back on the next layout
            breakAnchors();
            m_dragging = true;
            grabMouse();
            m_dragOffset = mousePos - getPosition();
            consumed = true;
        }
    }

    // a document fills the widget: presses on it belong to it (OTUI focus, raise, etc.)
    return UIWidget::onMousePress(mousePos, button) || consumed || hasDocument();
}

bool UIRmlWidget::onMouseRelease(const Point& mousePos, const Fw::MouseButton button)
{
    if (isDestroyed()) return true;
    bool consumed = false;
    if (m_context) {
        CallScope scope(*this);
        consumed = !m_context->ProcessMouseButtonUp(toRmlButton(button), 0);
        if (isDestroyed() || !m_context) return true;
    }

    if (button == Fw::MouseLeftButton && m_dragging) {
        m_dragging = false;
        ungrabMouse();
        consumed = true;
    }

    return UIWidget::onMouseRelease(mousePos, button) || consumed;
}

bool UIRmlWidget::onMouseMove(const Point& mousePos, const Point& mouseMoved)
{
    if (isDestroyed()) return true;
    if (m_dragging) {
        setPosition(mousePos - m_dragOffset);
        if (isDestroyed()) return true; // onGeometryChange can close the host.
        bindRectToParent();
        return true;
    }

    if (m_context) {
        CallScope scope(*this);
        m_context->ProcessMouseMove(localX(mousePos), localY(mousePos), 0);
        if (isDestroyed() || !m_context) return true;
    }

    return UIWidget::onMouseMove(mousePos, mouseMoved);
}

bool UIRmlWidget::onMouseWheel(const Point& mousePos, const Fw::MouseWheelDirection direction)
{
    if (isDestroyed()) return true;
    if (m_context && direction != Fw::MouseNoWheel) {
        CallScope scope(*this);
        m_context->ProcessMouseMove(localX(mousePos), localY(mousePos), 0);
        if (isDestroyed() || !m_context) return true;
        if (!m_context->ProcessMouseWheel(direction == Fw::MouseWheelUp ? -1.f : 1.f, 0))
            return true;
        if (isDestroyed() || !m_context) return true;
    }
    return UIWidget::onMouseWheel(mousePos, direction);
}

bool UIRmlWidget::onKeyText(const std::string& keyText)
{
    if (isDestroyed()) return true;
    if (m_context && !keyText.empty() && static_cast<uint8_t>(keyText.front()) >= 32 && static_cast<uint8_t>(keyText.front()) != 127) {
        CallScope scope(*this);
        if (auto* focus = m_context->GetFocusElement()) {
            // Input can remove the focused element or replace the entire document.
            const bool textField = isTextField(focus);
            const bool notConsumed = m_context->ProcessTextInput(RmlManager::utf8(keyText));
            if (isDestroyed() || !m_context || !notConsumed || textField)
                return true;
        }
    }
    return UIWidget::onKeyText(keyText);
}

bool UIRmlWidget::onKeyDown(const uint8_t keyCode, const int keyboardModifiers)
{
    if (isDestroyed()) return true;
    // Astra's walking/spell hotkeys run on key-down, before key-press.
    if (m_context && keyCode != Fw::KeyEscape) {
        CallScope scope(*this);
        if (isTextField(m_context->GetFocusElement())) return true;
    }
    return UIWidget::onKeyDown(keyCode, keyboardModifiers);
}

bool UIRmlWidget::onKeyPress(const uint8_t keyCode, const int keyboardModifiers, const int autoRepeatTicks)
{
    if (isDestroyed()) return true;
    if (m_context) {
        CallScope scope(*this);
        const auto key = toRmlKey(keyCode);
        if (auto* focus = m_context->GetFocusElement(); focus && key != Rml::Input::KI_UNKNOWN) {
            const bool textField = isTextField(focus);
            const bool notConsumed = m_context->ProcessKeyDown(key, toRmlModifiers(keyboardModifiers));
            if (isDestroyed() || !m_context || !notConsumed || (textField && key != Rml::Input::KI_ESCAPE))
                return true;
        }
    }
    return UIWidget::onKeyPress(keyCode, keyboardModifiers, autoRepeatTicks);
}

bool UIRmlWidget::onKeyUp(const uint8_t keyCode, const int keyboardModifiers)
{
    if (isDestroyed()) return true;
    if (m_context) {
        CallScope scope(*this);
        const auto key = toRmlKey(keyCode);
        if (key != Rml::Input::KI_UNKNOWN)
            m_context->ProcessKeyUp(key, toRmlModifiers(keyboardModifiers));
        if (isDestroyed() || !m_context) return true;
    }
    return UIWidget::onKeyUp(keyCode, keyboardModifiers);
}
