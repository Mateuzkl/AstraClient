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

#ifndef UICREATURE_H
#define UICREATURE_H

#include "declarations.h"
#include <framework/ui/uiwidget.h>
#include "creature.h"

class UICreature : public UIWidget
{
public:
    void drawSelf(Fw::DrawPane drawPane);

    void setCreature(const CreaturePtr& creature) { m_creature = creature; }
    void setFixedCreatureSize(bool fixed) { m_scale = fixed ? 1.0 : 0; }
    void setOutfit(const Outfit& outfit);
    // cyclopedia appearances helpers (mehah parity): tweak the current outfit
    // in place; luabinder nil-fills a missing addons arg to 0 (familiar rows)
    void setOutfitId(int id, int addons) { Outfit o = getOutfit(); o.setId(id); o.setAddons(addons); setOutfit(o); }
    void setOutfitColors(int head, int body, int legs, int feet) { Outfit o = getOutfit(); o.setHead(head); o.setBody(body); o.setLegs(legs); o.setFeet(feet); setOutfit(o); }

    CreaturePtr getCreature() { return m_creature; }
    Outfit getOutfit() { return m_creature ? m_creature->getOutfit() : Outfit(); }
    bool isFixedCreatureSize() { return m_scale > 0; }
    bool isColoredMount() { return true; }

    void setAutoRotating(bool value) { m_autoRotating = value; }
    void setDirection(Otc::Direction direction) { m_direction = direction; }
    Otc::Direction getDirection() { return m_direction; }

    void setScale(float scale) { m_scale = scale; }
    float getScale() { return m_scale; }
    // Shifts the whole creature+mount preview inside the widget. Used by the
    // outfit window and Store to re-center oversized (4x4) mount previews.
    void setDrawOffset(int x, int y) { m_drawOffset = Point(x, y); }

    void setAnimate(bool value) { m_animate = value; }
    void setIdleAnimate(bool value) { m_idleAnimate = value; }
    void setStaticWalking(bool value) { m_staticWalking = value; }
    bool isAnimating() { return m_animate || m_idleAnimate; }

    void setCenter(bool value);

    void setOldScaling(bool value) { m_oldScaling = value; }

protected:
    void onStyleApply(const std::string& styleName, const OTMLNodePtr& styleNode);
    void onGeometryChange(const Rect& oldRect, const Rect& newRect) override;

    CreaturePtr m_creature;
    stdext::boolean<false> m_autoRotating;
    stdext::boolean<false> m_animate;
    stdext::boolean<false> m_idleAnimate;
    stdext::boolean<false> m_staticWalking;
    stdext::boolean<false> m_oldScaling;
    Otc::Direction m_direction = Otc::South;
    float m_scale = 1.0;
    Point m_drawOffset;
};

#endif
