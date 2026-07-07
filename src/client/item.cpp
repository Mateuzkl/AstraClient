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

#include "item.h"
#include "thingtypemanager.h"
#include "spritemanager.h"
#include "thing.h"
#include "tile.h"
#include "container.h"
#include "map.h"
#include "houses.h"
#include "game.h"
#include "outfit.h"

#include <framework/core/clock.h>
#include <framework/core/eventdispatcher.h>
#include <framework/graphics/graphics.h>
#include <framework/core/filestream.h>
#include <framework/core/binarytree.h>
#include <framework/graphics/shadermanager.h>

#include <framework/util/stats.h>

Item::Item() :
    m_clientId(0),
    m_serverId(0),
    m_countOrSubType(1),
    m_color(Color::alpha),
    m_async(true),
    m_quickLootFlags(0),
    m_obtainFlags(0),
    m_charges(0),
    m_tier(0),
    m_upgradeLevel(0),
    m_dummyLevel(0),
    m_phase(0),
    m_lastPhase(0),
    m_durationTime(0),
    m_durationTimePaused(0),
    m_durationIsPaused(false),
    m_podiumDirection(2),
    m_podiumVisible(true)
{
    if (g_game.getFeature(Otc::GameEnhancedAnimations)) {
        m_animator = std::make_shared<Animator>();
        m_idleAnimator = std::make_shared<Animator>();
    }
}

Item::~Item() = default;

void Item::setPodiumOutfit(const Outfit& outfit, int direction, bool visible)
{
    m_podiumOutfit = std::make_shared<Outfit>(outfit);
    m_podiumDirection = direction;
    m_podiumVisible = visible;
}

void Item::clearPodiumOutfit()
{
    m_podiumOutfit.reset();
}

ItemPtr Item::create(int id, int countOrSubtype)
{
    auto item = std::make_shared<Item>();
    item->setId(id);
    item->setCountOrSubType(countOrSubtype);
    return item;
}

ItemPtr Item::createFromOtb(int id)
{
    auto item = std::make_shared<Item>();
    item->setOtbId(id);
    return item;
}

std::string Item::getName()
{
    return g_things.findItemTypeByClientId(m_clientId)->getName();
}

void Item::draw(const Point& dest, bool animate, LightView* lightView)
{
    if (m_clientId == 0)
        return;

    // determine animation phase
    int animationPhase = calculateAnimationPhase(animate);

    // determine x,y,z patterns
    int xPattern = 0, yPattern = 0, zPattern = 0;
    calculatePatterns(xPattern, yPattern, zPattern);

    Color color(Color::white);
    if (m_color != Color::alpha)
        color = m_color;

    // Dummy Level System (data-koliseu/lib/dummy/dummy_level_lib.lua): draw a
    // level-coloured halo behind a levelled training dummy. The level (1..10) rides on
    // the item via the custom AddItem byte (see ProtocolGame::getItem); the colour ramp
    // white->green->blue->red lives in the dummy_halo_<level> shaders registered in
    // modules/game_shaders/shaders.lua, so C++ only needs the level here. Eight offset
    // silhouettes are enqueued FIRST (same draw order) so they land behind the real
    // sprite -- once the sprite covers the centre, what shows around it is a coloured
    // outline. Done before drawQueueSize is captured so the selection mark still targets
    // the pedestal, and with a null LightView so the copies never add light.
    if (m_dummyLevel > 0) {
        int lvl = m_dummyLevel;
        if (lvl > 10) lvl = 10;
        const std::string haloShader = "dummy_halo_" + std::to_string(lvl);
        int o = g_sprites.spriteSize() / 32; // ~1px at 32px sprites (thin outline), scales with HD
        if (o < 1) o = 1;
        static const Point haloDirs[8] = {
            Point(-1, 0), Point(1, 0), Point(0, -1), Point(0, 1),
            Point(-1, -1), Point(1, -1), Point(-1, 1), Point(1, 1)
        };
        for (const Point& d : haloDirs) {
            rawGetThingType()->drawWithShader(dest + d * o, 0, xPattern, yPattern, zPattern,
                animationPhase, haloShader, color, nullptr, m_drawOrder);
        }
    }

    size_t drawQueueSize = g_drawQueue->size();

    // The monster podium (Podium of Vigour/Tenacity + the Astra custom one) exposes two
    // independent toggles in its window: "Show Podium" and "Show Creature". Unlike the
    // renown podium -- where the socket is always drawn and m_podiumVisible only gates the
    // displayed outfit -- here "Show Podium" (m_podiumVisible) hides the pedestal itself,
    // while "Show Creature" is expressed server-side by whether an outfit was stored
    // (m_podiumOutfit). So the two podium families need different draw rules (client ids
    // mirror gamelib/const.lua VIGOUR/TENACITY/ASTRA_MONSTER_PODIUM).
    static constexpr uint32 PODIUM_OF_VIGOUR = 38707;
    static constexpr uint32 PODIUM_OF_TENACITY = 42367;
    static constexpr uint32 ASTRA_MONSTER_PODIUM = 42368;
    const bool isMonsterPodium = m_clientId == PODIUM_OF_VIGOUR || m_clientId == PODIUM_OF_TENACITY || m_clientId == ASTRA_MONSTER_PODIUM;

    // Pedestal (this item's own sprite). Regular items and the renown podium always draw it;
    // a monster podium draws it only when "Show Podium" is enabled.
    if (!isMonsterPodium || m_podiumVisible) {
        if (!m_shader.empty()) {
            rawGetThingType()->drawWithShader(dest, 0, xPattern, yPattern, zPattern, animationPhase, m_shader, color, lightView, m_drawOrder);
        }
        else {
            rawGetThingType()->draw(dest, 0, xPattern, yPattern, zPattern, animationPhase, color, lightView, m_drawOrder);
        }
    }
    // Podium: render the displayed creature/outfit standing on the socket. The look is
    // parsed from the server AddItem podium block (see ProtocolGame::getItem). A monster
    // podium shows the creature whenever one is set ("Show Creature"); the renown podium
    // keeps gating the outfit behind m_podiumVisible ("Show Outfit").
    if (m_podiumOutfit && (isMonsterPodium || m_podiumVisible)) {
        m_podiumOutfit->draw(dest, static_cast<Otc::Direction>(m_podiumDirection), 0, animate, lightView, false);
    }
    if (m_marked) {
        g_drawQueue->setMark(drawQueueSize, updatedMarkedColor());
    }
}

void Item::draw(const Rect& dest, bool animate)
{
    if (m_clientId == 0)
        return;

    // determine animation phase
    int animationPhase = calculateAnimationPhase(animate);

    // determine x,y,z patterns
    int xPattern = 0, yPattern = 0, zPattern = 0;
    calculatePatterns(xPattern, yPattern, zPattern);

    Color color(Color::white);
    if (m_color != Color::alpha)
        color = m_color;

    if (!m_shader.empty()) {
        rawGetThingType()->drawWithShader(dest, 0, xPattern, yPattern, zPattern, animationPhase, m_shader, color);
    }
    else {
        rawGetThingType()->draw(dest, 0, xPattern, yPattern, zPattern, animationPhase, color);
    }
}

bool Item::drawToImage(const Point& dest, ImagePtr image)
{
    if (m_clientId == 0)
        return false;

    int xPattern = 0, yPattern = 0, zPattern = 0;
    calculatePatterns(xPattern, yPattern, zPattern);

    return rawGetThingType()->drawToImage(dest, xPattern, yPattern, zPattern, image);
}

void Item::setId(uint32 id)
{
    if(!g_things.isValidDatId(id, ThingCategoryItem))
        id = 0;
    m_serverId = g_things.findItemTypeByClientId(id)->getServerId();
    m_clientId = id;

    if (g_game.getFeature(Otc::GameEnhancedAnimations)) {
        if (auto thingType = rawGetThingType()) {
            if (auto animator = thingType->getAnimator()) {
                if (!m_animator)
                    m_animator = std::make_shared<Animator>();

                m_animator->copy(animator);
            }

            if (auto animator = thingType->getIdleAnimator()) {
                if (!m_idleAnimator)
                    m_idleAnimator = std::make_shared<Animator>();

                m_idleAnimator->copy(animator);
            }
        }
    }
}

void Item::setOtbId(uint16 id)
{
    if(!g_things.isValidOtbId(id))
        id = 0;
    auto itemType = g_things.getItemType(id);
    m_serverId = id;

    id = itemType->getClientId();
    if(!g_things.isValidDatId(id, ThingCategoryItem))
        id = 0;
    m_clientId = id;

    if (g_game.getFeature(Otc::GameEnhancedAnimations)) {
        if (auto thingType = rawGetThingType()) {
            if (auto animator = thingType->getAnimator()) {
                m_animator->copy(animator);
            }

            if (auto animator = thingType->getIdleAnimator())
                m_idleAnimator->copy(animator);
        }
    }
}

bool Item::isValid()
{
    return g_things.isValidDatId(m_clientId, ThingCategoryItem);
}

void Item::unserializeItem(const BinaryTreePtr &in)
{
    try {
        while(in->canRead()) {
            int attrib = in->getU8();
            if(attrib == 0)
                break;

            switch(attrib) {
                case ATTR_COUNT:
                case ATTR_RUNE_CHARGES:
                    setCount(in->getU8());
                    break;
                case ATTR_CHARGES:
                    setCount(in->getU16());
                    break;
                case ATTR_HOUSEDOORID:
                case ATTR_SCRIPTPROTECTED:
                case ATTR_DUALWIELD:
                case ATTR_DECAYING_STATE:
                    m_attribs.set(attrib, in->getU8());
                    break;
                case ATTR_ACTION_ID:
                case ATTR_UNIQUE_ID:
                case ATTR_DEPOT_ID:
                    m_attribs.set(attrib, in->getU16());
                    break;
                case ATTR_CONTAINER_ITEMS:
                case ATTR_ATTACK:
                case ATTR_EXTRAATTACK:
                case ATTR_DEFENSE:
                case ATTR_EXTRADEFENSE:
                case ATTR_ARMOR:
                case ATTR_ATTACKSPEED:
                case ATTR_HITCHANCE:
                case ATTR_DURATION:
                case ATTR_WRITTENDATE:
                case ATTR_SLEEPERGUID:
                case ATTR_SLEEPSTART:
                case ATTR_ATTRIBUTE_MAP:
                    m_attribs.set(attrib, in->getU32());
                    break;
                case ATTR_TELE_DEST: {
                    Position pos;
                    pos.x = in->getU16();
                    pos.y = in->getU16();
                    pos.z = in->getU8();
                    m_attribs.set(attrib, pos);
                    break;
                }
                case ATTR_NAME:
                case ATTR_TEXT:
                case ATTR_DESC:
                case ATTR_ARTICLE:
                case ATTR_WRITTENBY:
                    m_attribs.set(attrib, in->getString());
                    break;
                default:
                    stdext::throw_exception(stdext::format("invalid item attribute %d", attrib));
            }
        }
    } catch(stdext::exception& e) {
        g_logger.error(stdext::format("Failed to unserialize OTBM item: %s", e.what()));
    }
}

void Item::serializeItem(const OutputBinaryTreePtr& out)
{
    out->startNode(OTBM_ITEM);
    out->addU16(getServerId());

    out->addU8(ATTR_COUNT);
    out->addU8(getCount());

    out->addU8(ATTR_CHARGES);
    out->addU16(getCountOrSubType());

    Position dest = m_attribs.get<Position>(ATTR_TELE_DEST);
    if(dest.isValid()) {
        out->addU8(ATTR_TELE_DEST);
        out->addPos(dest.x, dest.y, dest.z);
    }

    if(isDepot()) {
        out->addU8(ATTR_DEPOT_ID);
        out->addU16(getDepotId());
    }

    if(isHouseDoor()) {
        out->addU8(ATTR_HOUSEDOORID);
        out->addU8(getDoorId());
    }

    uint16 aid = m_attribs.get<uint16>(ATTR_ACTION_ID);
    uint16 uid = m_attribs.get<uint16>(ATTR_UNIQUE_ID);
    if(aid) {
        out->addU8(ATTR_ACTION_ID);
        out->addU16(aid);
    }

    if(uid) {
        out->addU8(ATTR_UNIQUE_ID);
        out->addU16(uid);
    }

    std::string text = getText();
    if(g_things.getItemType(m_serverId)->isWritable() && !text.empty()) {
        out->addU8(ATTR_TEXT);
        out->addString(text);
    }
    std::string desc = getDescription();
    if(!desc.empty()) {
        out->addU8(ATTR_DESC);
        out->addString(desc);
    }

    out->endNode();
    for(auto i : m_containerItems)
        i->serializeItem(out);
}

int Item::getSubType()
{
    if(isSplash() || isFluidContainer())
        return m_countOrSubType;
    if(g_game.getClientVersion() >= 860)
        return 0;
    return 1;
}

int Item::getCount()
{
    if(isStackable())
        return m_countOrSubType;
    return 1;
}

bool Item::isQuiver()
{
    switch (getId()) {
    case 35524: // jungle quiver
    case 35562: // quiver
    case 35848: // blue quiver
    case 35849: // red quiver
    case 36666: // eldritch quiver
    case 39150: // alicorn quiver
    case 39160: // naga quiver
    case 45644: // candy-coated quiver
        return true;
    default:
        return false;
    }
}

bool Item::isMoveable()
{
    return !rawGetThingType()->isNotMoveable();
}

bool Item::isGround()
{
    return rawGetThingType()->isGround();
}

bool Item::inCorpse()
{
    const auto& container = getParentContainer();
    if (!container)
        return false;

    const auto& containerItem = container->getContainerItem();
    return containerItem && containerItem->isCorpse();
}

int Item::getWeaponType()
{
    // ThingType::getWeaponType prefers the appearances weapon_type and falls back
    // to the OTB silently; going through getItemType(m_serverId) spammed
    // "invalid thing type, server id: 0" on appearances-based setups (no OTB
    // loaded, so m_serverId is always 0) and always returned 0.
    return rawGetThingType()->getWeaponType();
}

ItemPtr Item::clone()
{
    auto item = std::make_shared<Item>();
    *(item.get()) = *this;
    return item;
}

void Item::calculatePatterns(int& xPattern, int& yPattern, int& zPattern)
{
    // Avoid crashes with invalid items
    if(!isValid())
        return;

    if(isStackable() && getNumPatternX() == 4 && getNumPatternY() == 2) {
        if(m_countOrSubType <= 0) {
            xPattern = 0;
            yPattern = 0;
        } else if(m_countOrSubType < 5) {
            xPattern = m_countOrSubType-1;
            yPattern = 0;
        } else if(m_countOrSubType < 10) {
            xPattern = 0;
            yPattern = 1;
        } else if(m_countOrSubType < 25) {
            xPattern = 1;
            yPattern = 1;
        } else if(m_countOrSubType < 50) {
            xPattern = 2;
            yPattern = 1;
        } else {
            xPattern = 3;
            yPattern = 1;
        }
    } else if(isHangable()) {
        const TilePtr& tile = getTile();
        if(tile) {
            if(tile->mustHookSouth())
                xPattern = getNumPatternX() >= 2 ? 1 : 0;
            else if(tile->mustHookEast())
                xPattern = getNumPatternX() >= 3 ? 2 : 0;
        }
    } else if(isSplash() || isFluidContainer()) {
        int color = Otc::FluidTransparent;
        if(g_game.getFeature(Otc::GameNewFluids)) {
            switch(m_countOrSubType) {
                case Otc::FluidNone:
                    color = Otc::FluidTransparent;
                    break;
                case Otc::FluidWater:
                    color = Otc::FluidBlue;
                    break;
                case Otc::FluidMana:
                    color = Otc::FluidPurple;
                    break;
                case Otc::FluidBeer:
                    color = Otc::FluidBrown;
                    break;
                case Otc::FluidOil:
                    color = Otc::FluidBrown;
                    break;
                case Otc::FluidBlood:
                    color = Otc::FluidRed;
                    break;
                case Otc::FluidSlime:
                    color = Otc::FluidGreen;
                    break;
                case Otc::FluidMud:
                    color = Otc::FluidBrown;
                    break;
                case Otc::FluidLemonade:
                    color = Otc::FluidYellow;
                    break;
                case Otc::FluidMilk:
                    color = Otc::FluidWhite;
                    break;
                case Otc::FluidWine:
                    color = Otc::FluidPurple;
                    break;
                case Otc::FluidHealth:
                    color = Otc::FluidRed;
                    break;
                case Otc::FluidUrine:
                    color = Otc::FluidYellow;
                    break;
                case Otc::FluidRum:
                    color = Otc::FluidBrown;
                    break;
                case Otc::FluidFruidJuice:
                    color = Otc::FluidYellow;
                    break;
                case Otc::FluidCoconutMilk:
                    color = Otc::FluidWhite;
                    break;
                case Otc::FluidTea:
                    color = Otc::FluidBrown;
                    break;
                case Otc::FluidMead:
                    color = Otc::FluidBrown;
                    break;
                default:
                    color = Otc::FluidTransparent;
                    break;
            }
        } else
            color = m_countOrSubType;

        xPattern = (color % 4) % getNumPatternX();
        yPattern = (color / 4) % getNumPatternY();
    } else {
        xPattern = m_position.x % std::max<int>(1, getNumPatternX());
        yPattern = m_position.y % std::max<int>(1, getNumPatternY());
        zPattern = m_position.z % std::max<int>(1, getNumPatternZ());
    }
}

int Item::calculateAnimationPhase(bool animate)
{
    if(getAnimationPhases() > 1) {
        if(animate) {
            if(getAnimator() != nullptr)
                return getAnimator()->getPhase();

            const int ticksPerFrame = g_game.getFeature(Otc::GameEnhancedAnimations) ? Otc::ITEM_TICKS_PER_FRAME_FAST : Otc::ITEM_TICKS_PER_FRAME;
            if(m_async)
                return (g_clock.millis() % (ticksPerFrame * getAnimationPhases())) / ticksPerFrame;
            else {
                if(g_clock.millis() - m_lastPhase >= ticksPerFrame) {
                    m_phase = (m_phase + 1) % getAnimationPhases();
                    m_lastPhase = g_clock.millis();
                }
                return m_phase;
            }
        } else
            return getAnimationPhases()-1;
    }
    return 0;
}

int Item::getExactSize(int layer, int xPattern, int yPattern, int zPattern, int animationPhase)
{
    calculatePatterns(xPattern, yPattern, zPattern);
    animationPhase = calculateAnimationPhase(true);
    return Thing::getExactSize(layer, xPattern, yPattern, zPattern, animationPhase);
}

const ThingTypePtr& Item::getThingType()
{
    return g_things.getThingType(m_clientId, ThingCategoryItem);
}

ThingType* Item::rawGetThingType()
{
    return g_things.rawGetThingType(m_clientId, ThingCategoryItem);
}
