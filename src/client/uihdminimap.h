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

#ifndef UIHDMINIMAP_H
#define UIHDMINIMAP_H

#include "declarations.h"
#include <framework/ui/uiwidget.h>

class UIHDMinimap : public UIWidget
{
public:
    UIHDMinimap();

    void drawSelf(Fw::DrawPane drawPane) override;

    void setCameraPosition(const Position& pos) { m_cameraPosition = pos; }
    Position getCameraPosition() const { return m_cameraPosition; }

    void setVisibleDimension(int width, int height) { m_visibleW = width; m_visibleH = height; }
    int getVisibleWidth() const { return m_visibleW; }
    int getVisibleHeight() const { return m_visibleH; }

    void setAnimated(bool enable) { m_animated = enable; }
    bool isAnimated() const { return m_animated; }

protected:
    void onStyleApply(const std::string& styleName, const OTMLNodePtr& styleNode) override;

private:
    Position m_cameraPosition;
    int m_visibleW = 15;
    int m_visibleH = 11;
    bool m_animated = true;
};

#endif
