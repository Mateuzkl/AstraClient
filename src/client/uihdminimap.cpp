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

#include "uihdminimap.h"
#include "map.h"
#include "tile.h"
#include "game.h"
#include <framework/graphics/graphics.h>
#include <framework/otml/otml.h>

UIHDMinimap::UIHDMinimap()
{
    m_draggable = false;
    m_cameraPosition = Position(0, 0, 7);
}

void UIHDMinimap::drawSelf(Fw::DrawPane drawPane)
{
    UIWidget::drawSelf(drawPane);

    if(drawPane != Fw::ForegroundPane)
        return;

    Rect rect = getPaddingRect();
    if(rect.isEmpty())
        return;

    g_drawQueue->addFilledRect(rect, Color::black);

    int tileW = rect.width() / m_visibleW;
    int tileH = rect.height() / m_visibleH;
    if(tileW < 1 || tileH < 1)
        return;

    int startX = m_cameraPosition.x - m_visibleW / 2;
    int startY = m_cameraPosition.y - m_visibleH / 2;
    int z = m_cameraPosition.z;

    for(int ty = 0; ty < m_visibleH; ++ty) {
        for(int tx = 0; tx < m_visibleW; ++tx) {
            Position pos(startX + tx, startY + ty, z);
            if(!pos.isMapPosition()) continue;

            uint8 color = 255;
            TilePtr tile = g_map.getTile(pos);
            if(tile) {
                color = tile->getMinimapColorByte();
            }

            if(color == 255) continue;

            Rect tileRect(rect.left() + tx * tileW, rect.top() + ty * tileH, tileW, tileH);
            g_drawQueue->addFilledRect(tileRect, Color::from8bit(color));
        }
    }
}

void UIHDMinimap::onStyleApply(const std::string& styleName, const OTMLNodePtr& styleNode)
{
    UIWidget::onStyleApply(styleName, styleNode);
    for(const auto& node : styleNode->children()) {
        if(node->tag() == "animated")
            setAnimated(node->value<bool>());
    }
}
