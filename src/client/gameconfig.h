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

#ifndef GAMECONFIG_H
#define GAMECONFIG_H

#include <cstdint>

#include <framework/otml/declarations.h>
#include <framework/util/size.h>

// @bindsingleton g_gameConfig
class GameConfig
{
public:
    void init();

    Size getMapViewPort() const { return m_mapViewPort; }
    uint8_t getMapMaxZ() const { return m_mapMaxZ; }
    uint8_t getMapSeaFloor() const { return m_mapSeaFloor; }
    uint8_t getMapUndergroundFloor() const { return m_mapUndergroundFloor; }
    uint8_t getMapAwareUndergroundFloorRange() const { return m_mapAwareUndergroundFloorRange; }
    bool isExtendedViewUI() const { return m_extendedViewUI; }

private:
    void loadMapNode(const OTMLNodePtr& node);

    Size m_mapViewPort{8, 6};
    uint8_t m_mapMaxZ{15};
    uint8_t m_mapSeaFloor{7};
    uint8_t m_mapUndergroundFloor{8};
    uint8_t m_mapAwareUndergroundFloorRange{2};
    bool m_extendedViewUI{false};
};

extern GameConfig g_gameConfig;

#endif
