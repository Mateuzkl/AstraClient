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

#include "uiitem.h"
#include "spritemanager.h"
#include "game.h"
#include <framework/core/graphicalapplication.h>
#include <framework/otml/otml.h>
#include <framework/graphics/graphics.h>
#include <framework/graphics/fontmanager.h>

#include <cctype>

namespace
{
bool isInventoryItemStyle(const std::string& styleName)
{
    return styleName == "InventoryItem" || styleName == "NoneInventoryItem" ||
        styleName == "HeadSlot" || styleName == "NeckSlot" || styleName == "BodySlot" ||
        styleName == "LegSlot" || styleName == "FeetSlot" || styleName == "LeftSlot" ||
        styleName == "FingerSlot" || styleName == "BackSlot" || styleName == "RightSlot" ||
        styleName == "AmmoSlot";
}

bool isContainerItemId(const std::string& id)
{
    if(id.size() <= 4 || id.compare(0, 4, "item") != 0)
        return false;

    for(std::size_t i = 4; i < id.size(); ++i) {
        if(!std::isdigit(static_cast<unsigned char>(id[i])))
            return false;
    }
    return true;
}
}

UIItem::UIItem()
{
    m_draggable = true;
    m_color = Color(231, 231, 231);
    m_itemColor = Color::white;
    m_lastDecayUpdate = 0;
    m_decayColor = Color::white;
    m_decayPausedColor = Color::red;
}

void UIItem::drawSelf(Fw::DrawPane drawPane)
{
    if(drawPane != Fw::ForegroundPane)
        return;
    // draw style components in order
    if(m_backgroundColor.aF() > Fw::MIN_ALPHA) {
        Rect backgroundDestRect = m_rect;
        backgroundDestRect.expand(-m_borderWidth.top, -m_borderWidth.right, -m_borderWidth.bottom, -m_borderWidth.left);
        drawBackground(m_rect);
    }

    drawImage(m_rect);

    if(m_itemVisible && m_item) {
        Rect drawRect = getPaddingRect();

        int exactSize = std::max<int>(g_sprites.spriteSize(), m_item->getExactSize());
        if(exactSize == 0)
            return;

        m_item->setColor(m_itemColor);
        const auto itemDrawQueueStart = g_drawQueue->size();
        m_item->draw(drawRect);
        if (m_flipDirection != 0) {
            g_drawQueue->setFlip(itemDrawQueueStart, drawRect.center(), m_flipDirection);
        }

        const bool showExpiryState = shouldDrawExpiryState();
        const bool astraItemStateEnabled = g_game.isAstraItemStateEnabled();
        const uint32_t itemCharges = showExpiryState && astraItemStateEnabled &&
            g_game.getFeature(Otc::GameDisplayItemCharges) && m_item->hasDisplayCharges() ? m_item->getCharges() : 0;
        bool drewCount = false;

        if(m_font && (m_showCount || itemCharges > 1)) {
            std::string countText = m_virtualCount.empty() ? m_countText : m_virtualCount;
            bool shouldDrawCount = !m_virtualCount.empty() || m_showCountAlways ||
                ((m_item->isStackable() || m_item->isChargeable() || m_item->isQuiver()) && m_item->getCountOrSubType() > 1);

            if(!shouldDrawCount && itemCharges > 1) {
                countText = std::to_string(itemCharges);
                shouldDrawCount = true;
            }

            if(shouldDrawCount) {
                g_drawQueue->addText(m_font, countText, Rect(drawRect.topLeft(), drawRect.bottomRight() - Point(3, 0)), Fw::AlignBottomRight, m_color);
                drewCount = true;
            }
        }

        if (m_showId) {
            g_drawQueue->addText(m_font, std::to_string(m_item->getServerId()), drawRect, Fw::AlignBottomRight, m_color);
        }

        const uint64_t durationTime = m_item->getDurationTime();
        if(showExpiryState && astraItemStateEnabled && m_item->hasDisplayDuration() && durationTime > 0 && g_game.getFeature(Otc::GameDisplayItemDuration)) {
            auto isPaused = m_item->isDurationPaused();
            const uint64_t now = static_cast<uint64_t>(stdext::unixtimeMs());
            uint64 duration = durationTime > now ? durationTime - now : 0;
            if(isPaused && durationTime > 0) {
                const uint64_t pausedAt = static_cast<uint64_t>(m_item->getDurationTimePaused());
                duration = durationTime > pausedAt ? durationTime - pausedAt : 0;
            }

            if(m_lastDecayUpdate + 1000 < stdext::millis()) {
                m_decayText = stdext::secondsToDuration(duration / 1000);
                m_lastDecayUpdate = stdext::millis();
            }

            const bool isExpiring = duration > 0 && duration < 60 * 1000;
            const auto decayAlign = (drewCount || m_showId) ? Fw::AlignTopRight : Fw::AlignBottomRight;
            g_drawQueue->addText(m_font, m_decayText, drawRect, decayAlign, isExpiring ? m_decayPausedColor : m_decayColor);
        }
    }

    drawBorder(m_rect);
    drawIcon(m_rect);
    drawText(m_rect);
}

void UIItem::setItemId(int id)
{
    if (!m_item && id != 0)
        m_item = Item::create(id);
    else {
        // remove item
        if (id == 0)
            m_item = nullptr;
        else
            m_item->setId(id);
    }

    if (m_item)
        m_item->setShader(m_shader);

    m_lastDecayUpdate = 0;

    callLuaField("onItemChange");
}

void UIItem::setItemCount(int count)
{
    if (m_item) {
        m_item->setCount(count);
        callLuaField("onItemChange");
        cacheCountText();
    }
}

void UIItem::setItemSubType(int subType)
{
    if (m_item) {
        m_item->setSubType(subType);
        callLuaField("onItemChange");
    }
}

void UIItem::setItem(const ItemPtr& item)
{
    m_item = item;
    if (m_item) {
        m_item->setShader(m_shader);

        m_lastDecayUpdate = 0;

        cacheCountText();
        callLuaField("onItemChange");
    }
}

void UIItem::setVirtualCount(const std::string& count)
{
    if (m_virtualCount == count)
        return;

    m_virtualCount = count;
    g_app.repaint();
}

void UIItem::setItemShader(const std::string& str)
{
    m_shader = str;

    if (m_item) {
        m_item->setShader(m_shader);
        callLuaField("onItemChange");
    }
}

void UIItem::setFlipDirection(uint8_t direction)
{
    if (m_flipDirection == direction)
        return;

    m_flipDirection = direction;
    g_app.repaint();
}

void UIItem::onStyleApply(const std::string& styleName, const OTMLNodePtr& styleNode)
{
    UIWidget::onStyleApply(styleName, styleNode);

    if(isInventoryItemStyle(styleName))
        m_expiryDisplayContext = ExpiryDisplayContext::Inventory;
    else if(styleName == "Item")
        m_expiryDisplayContext = isContainerItemId(m_id) ? ExpiryDisplayContext::Container : ExpiryDisplayContext::Unused;

    for(const OTMLNodePtr& node : styleNode->children()) {
        if(node->tag() == "item-id")
            setItemId(node->value<int>());
        else if(node->tag() == "item-count")
            setItemCount(node->value<int>());
        else if(node->tag() == "item-visible")
            setItemVisible(node->value<bool>());
        else if(node->tag() == "virtual")
            setVirtual(node->value<bool>());
        else if(node->tag() == "show-id")
            m_showId = node->value<bool>();
        else if(node->tag() == "shader")
            setItemShader(node->value());
        else if(node->tag() == "item-color")
            setItemColor(node->value<Color>());
        else if(node->tag() == "show-count")
            setShowCount(node->value<bool>());
        else if(node->tag() == "item-always-show-count" || node->tag() == "always-show-count")
            setShowCountAlways(node->value<bool>());
        else if(node->tag() == "hotkey-item" && node->value<bool>())
            m_expiryDisplayContext = ExpiryDisplayContext::ActionBar;
        else if(node->tag() == "flip-direction")
            setFlipDirection(node->value<uint8_t>());
    }
}

bool UIItem::shouldDrawExpiryState() const
{
    switch(m_expiryDisplayContext) {
        case ExpiryDisplayContext::Inventory:
            return g_game.isInventoryTimerEnabled();
        case ExpiryDisplayContext::Container:
            return g_game.isContainerTimerEnabled();
        case ExpiryDisplayContext::ActionBar:
            return false;
        case ExpiryDisplayContext::Unused:
        default:
            return g_game.isUnusedTimerEnabled();
    }
}

void UIItem::cacheCountText()
{
    int count = m_item->getCountOrSubType();
    if (!g_game.getFeature(Otc::GameCountU16) || count < 1000) {
        m_countText = std::to_string(count);
        return;
    }

    m_countText = stdext::format("%.0fk", count / 1000.0);
}
