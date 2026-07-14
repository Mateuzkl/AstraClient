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

#include "gameconfig.h"

#include <framework/core/resourcemanager.h>
#include <framework/otml/otml.h>

GameConfig g_gameConfig;

namespace {
constexpr const char* MAP_CONFIG_FILE = "/data/default-config";
constexpr int MAX_CONFIGURABLE_Z = 254;
constexpr int MAX_VIEWPORT_RANGE = 127;
}

void GameConfig::init()
{
    try {
        const std::string file = g_resources.guessFilePath(MAP_CONFIG_FILE, "otml");
        const OTMLDocumentPtr document = OTMLDocument::parse(file);

        bool foundMapNode = false;
        for (const OTMLNodePtr& node : document->children()) {
            if (node->tag() == "map") {
                loadMapNode(node);
                foundMapNode = true;
                break;
            }

            // Also accept the Mehah setup.otml shape: game -> map.
            if (node->tag() == "game") {
                for (const OTMLNodePtr& gameNode : node->children()) {
                    if (gameNode->tag() == "map") {
                        loadMapNode(gameNode);
                        foundMapNode = true;
                        break;
                    }
                }
            }
        }

        if (!foundMapNode) {
            g_logger.warning(stdext::format("Map config not found in '%s.otml'; using defaults.", MAP_CONFIG_FILE));
        }
    } catch (const std::exception& e) {
        g_logger.warning(stdext::format("Unable to load map config '%s.otml': %s. Using defaults.", MAP_CONFIG_FILE, e.what()));
    }

    g_logger.info(stdext::format(
        "Map config: viewport=%dx%d, aware-range=%dx%d, extended-view-ui=%s, max-z=%d, sea-floor=%d, underground-floor=%d, aware-underground-floor-range=%d",
        m_mapViewPort.width(), m_mapViewPort.height(), m_mapViewPort.width() * 2 + 2,
        m_mapViewPort.height() * 2 + 2, m_extendedViewUI ? "true" : "false", m_mapMaxZ, m_mapSeaFloor,
        m_mapUndergroundFloor, m_mapAwareUndergroundFloorRange));
}

void GameConfig::loadMapNode(const OTMLNodePtr& mainNode)
{
    Size viewPort = m_mapViewPort;
    int maxZ = m_mapMaxZ;
    int seaFloor = m_mapSeaFloor;
    int undergroundFloor = m_mapUndergroundFloor;
    int awareUndergroundFloorRange = m_mapAwareUndergroundFloorRange;
    bool extendedViewUI = m_extendedViewUI;

    for (const OTMLNodePtr& node : mainNode->children()) {
        if (node->tag() == "viewport")
            viewPort = node->value<Size>();
        else if (node->tag() == "extended-view-ui")
            extendedViewUI = node->value<bool>();
        else if (node->tag() == "max-z")
            maxZ = node->value<int>();
        else if (node->tag() == "sea-floor")
            seaFloor = node->value<int>();
        else if (node->tag() == "underground-floor")
            undergroundFloor = node->value<int>();
        else if (node->tag() == "aware-underground-floor-range")
            awareUndergroundFloorRange = node->value<int>();
    }

    if (viewPort.width() < 1 || viewPort.height() < 1 ||
        viewPort.width() > MAX_VIEWPORT_RANGE || viewPort.height() > MAX_VIEWPORT_RANGE) {
        g_logger.warning(stdext::format(
            "Invalid map viewport %dx%d; keeping %dx%d.", viewPort.width(), viewPort.height(),
            m_mapViewPort.width(), m_mapViewPort.height()));
    } else {
        m_mapViewPort = viewPort;
    }

    if (maxZ < 1 || maxZ > MAX_CONFIGURABLE_Z || seaFloor < 0 ||
        undergroundFloor <= seaFloor || undergroundFloor > maxZ) {
        g_logger.warning(stdext::format(
            "Invalid map floor configuration (max-z=%d, sea-floor=%d, underground-floor=%d); keeping %d/%d/%d.",
            maxZ, seaFloor, undergroundFloor, m_mapMaxZ, m_mapSeaFloor, m_mapUndergroundFloor));
        maxZ = m_mapMaxZ;
        seaFloor = m_mapSeaFloor;
    } else {
        m_mapMaxZ = static_cast<uint8_t>(maxZ);
        m_mapSeaFloor = static_cast<uint8_t>(seaFloor);
        m_mapUndergroundFloor = static_cast<uint8_t>(undergroundFloor);
    }

    if (awareUndergroundFloorRange < 0 || awareUndergroundFloorRange > seaFloor) {
        g_logger.warning(stdext::format(
            "Invalid aware-underground-floor-range %d; keeping %d.",
            awareUndergroundFloorRange, m_mapAwareUndergroundFloorRange));
    } else {
        m_mapAwareUndergroundFloorRange = static_cast<uint8_t>(awareUndergroundFloorRange);
    }

    m_extendedViewUI = extendedViewUI;
}
