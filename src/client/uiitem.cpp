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
#include <framework/otml/otml.h>
#include <framework/graphics/graphics.h>
#include <framework/graphics/fontmanager.h>
#include <framework/graphics/texturemanager.h>

UIItem::UIItem()
{
    m_draggable = true;
    m_color = Color(231, 231, 231);
    m_itemColor = Color::white;
    m_lastDecayUpdate = 0;
    m_decayColor = Color(127, 255, 212);
    m_decayPausedColor = Color(222, 109, 109);
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
        m_item->draw(drawRect);

        if(m_font && m_showCount && (m_showCountAlways || (m_item->isStackable() || m_item->isChargeable() || m_item->isQuiver()) && m_item->getCountOrSubType() > 1)) {
            g_drawQueue->addText(m_font, m_countText, Rect(drawRect.topLeft(), drawRect.bottomRight() - Point(3, 0)), Fw::AlignBottomRight, m_color);
        }

        if (m_showId) {
            g_drawQueue->addText(m_font, std::to_string(m_item->getServerId()), drawRect, Fw::AlignBottomRight, m_color);
        }

        // Item decay time / charge count overlay, controlled by the client options
        // timeInventory / timeContainers / timeUnnused (Game::isDrawingItemTimers). The
        // server (crystalserver AddItem) sends a duration for expiring items and a charge
        // count for wearOut items; show whichever the item carries.
        if (m_font && g_game.isDrawingItemTimers()) {
            if (m_item->getDurationTime() > 0) {
                auto isPaused = m_item->isDurationPaused();
                if (m_lastDecayUpdate + 1000 < stdext::millis()) {
                    uint64 duration = m_item->getDurationTime() - (isPaused ? m_item->getDurationTimePaused() : stdext::unixtimeMs());
                    m_decayText = stdext::secondsToDuration(duration / 1000);
                    m_lastDecayUpdate = stdext::millis();
                }
                g_drawQueue->addText(m_font, m_decayText, drawRect, Fw::AlignBottomRight, isPaused ? m_decayPausedColor : m_decayColor);
            } else if (m_item->getCharges() > 0) {
                g_drawQueue->addText(m_font, std::to_string(m_item->getCharges()), drawRect, Fw::AlignBottomRight, m_decayColor);
            }
        }

        // Tier badge: the small orange classification badge with the tier number,
        // drawn at the top-right of the slot. Artwork:
        // data/images/game/items/tier-<n>.png with n = 1..10 (the "big" variant is
        // for detail views and is far too large for an inventory slot).
        if (m_item->getTier() > 0) {
            int tier = std::min<int>(m_item->getTier(), 10);
            const TexturePtr& tierTexture = g_textures.getTexture("/images/game/items/tier-" + std::to_string(tier));
            if (tierTexture) {
                Size tierSize = tierTexture->getSize();
                Rect tierRect(drawRect.topRight() - Point(tierSize.width() - 1, 0), tierSize);
                g_drawQueue->addTexturedRect(tierRect, tierTexture, Rect(0, 0, tierSize));
            }
        }

        // Custom server upgrade level shown as a "+N" tag at the TOP-LEFT corner.
        // GREEN for weapon attack upgrades (weapon_upgrade.lua), BLUE for set-piece skill
        // upgrades (skill_gems.lua). Drawn with a black outline so it reads on any item.
        // Placed top-left to avoid colliding with the stack count (bottom-right) and the
        // tier badge (top-right): the count is now drawn for non-stackables too (action
        // bar / stash), so the old bottom-right placement overlapped the owned amount.
        if (m_item->getUpgradeLevel() > 0) {
            ThingType* tt = m_item->rawGetThingType();
            bool isSetPiece = false;
            if (tt) {
                const int slot = tt->getClothSlot();
                isSetPiece = (slot == Otc::InventorySlotHead || slot == Otc::InventorySlotArmor ||
                              slot == Otc::InventorySlotLegs || slot == Otc::InventorySlotFeet);
            }
            static const BitmapFontPtr upgradeFont = g_fonts.getFont("verdana-8px-rounded");
            const BitmapFontPtr& tagFont = upgradeFont ? upgradeFont : m_font;
            if (tagFont) {
                const Color tagColor = isSetPiece ? Color(0x4c, 0x9f, 0xff) : Color(0x4c, 0xd9, 0x4c);
                const std::string tagText = "+" + std::to_string(m_item->getUpgradeLevel());
                g_drawQueue->addText(tagFont, tagText,
                                     Rect(drawRect.topLeft() + Point(1, 0), drawRect.bottomRight()),
                                     Fw::AlignTopLeft, tagColor, true);
            }
        }

        // Loot-value highlight (client option colouriseLootColor): overlay the
        // rarity_{square,corner}_<color> texture (data/images/ui) on opted-in widgets
        // (containers / loot / market / cyclopedia) via setDrawLootValue. State 0 = Frames
        // (square), 1 = Corners. Value->color tiers mirror gamelib getItemColor.
        if (m_drawLootValue) {
            const double value = m_item->getPriceValue();
            const char* lvColor = nullptr;
            if (value >= 1000000) lvColor = "gold";
            else if (value >= 100000) lvColor = "purple";
            else if (value >= 10000) lvColor = "blue";
            else if (value >= 1000) lvColor = "green";
            else if (value >= 1) lvColor = "white";

            if (lvColor) {
                const std::string shape = (g_game.getLootValueState() == 1) ? "corner" : "square";
                const TexturePtr& lvTexture = g_textures.getTexture("/images/ui/rarity_" + shape + "_" + lvColor);
                if (lvTexture)
                    g_drawQueue->addTexturedRect(drawRect, lvTexture, Rect(0, 0, lvTexture->getSize()));
            }
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

void UIItem::setItemShader(const std::string& str)
{
    m_shader = str;

    if (m_item) {
        m_item->setShader(m_shader);
        callLuaField("onItemChange");
    }
}

void UIItem::onStyleApply(const std::string& styleName, const OTMLNodePtr& styleNode)
{
    UIWidget::onStyleApply(styleName, styleNode);

    for(const OTMLNodePtr& node : styleNode->children()) {
        if(node->tag() == "item-id")
            setItemId(node->value<int>());
        else if(node->tag() == "item-count")
            setItemCount(node->value<int>());
        else if(node->tag() == "item-visible")
            setItemVisible(node->value<bool>());
        else if(node->tag() == "virtual")
            setVirtual(node->value<bool>());
        else if(node->tag() == "hotkey-item")
            setHotkeyItem(node->value<bool>());
        else if(node->tag() == "show-id")
            m_showId = node->value<bool>();
        else if(node->tag() == "shader")
            setItemShader(node->value());
        else if(node->tag() == "item-color")
            setItemColor(node->value<Color>());
        else if(node->tag() == "item-always-show-count")
            setShowCountAlways(node->value<bool>());
        // "priceable" (already set on market/cyclopedia/bestiary/quickloot/stash/... item
        // widgets) opts a slot into the loot-value frame/corner highlight.
        else if(node->tag() == "priceable")
            setDrawLootValue(node->value<bool>());
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
