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

#ifndef UISPRITE_H
#define UISPRITE_H

#include "declarations.h"
#include <framework/ui/uiwidget.h>

class UISprite : public UIWidget
{
public:
    UISprite();
    void drawSelf(Fw::DrawPane drawPane);

    void setSpriteId(uint32 id);
    uint32 getSpriteId() { return m_spriteId; }
    void clearSprite() { setSpriteId(0); }

    void setSpriteColor(Color color) { m_spriteColor = color; }

    bool isSpriteVisible() { return m_spriteVisible; }
    void setSpriteVisible(bool visible) { m_spriteVisible = visible; }

    bool hasSprite() { return m_sprite != nullptr; }

    // Uniform draw scale (mirrors UICreature). 1.0 = fill the padding rect; the
    // sprite is drawn from the padding rect's top-left scaled by this factor, so
    // HUD:setScale on a sprite icon grows it in place. Bound in luafunctions_client.
    void setScale(float scale) { m_scale = scale; }
    float getScale() { return m_scale; }

protected:
    void onStyleApply(const std::string& styleName, const OTMLNodePtr& styleNode);

    TexturePtr m_sprite;
    uint32 m_spriteId;
    Color m_spriteColor;

    stdext::boolean<true> m_spriteVisible;
    float m_scale = 1.0f;
};

#endif
