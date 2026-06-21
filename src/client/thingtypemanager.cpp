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

#include "thingtypemanager.h"
#include "spritemanager.h"
#include "thing.h"
#include "thingtype.h"
#include "itemtype.h"
#include "creature.h"
#include "creatures.h"
#include "game.h"
#include "const.h"

#include <framework/core/resourcemanager.h>
#include <framework/core/filestream.h>
#include <framework/core/binarytree.h>
#include <framework/xml/tinyxml.h>
#include <framework/otml/otml.h>
#include <framework/util/stats.h>

ThingTypeManager g_things;

namespace {
constexpr uint16 ItemSlotHead = 1 << 0;
constexpr uint16 ItemSlotNecklace = 1 << 1;
constexpr uint16 ItemSlotBackpack = 1 << 2;
constexpr uint16 ItemSlotArmor = 1 << 3;
constexpr uint16 ItemSlotRight = 1 << 4;
constexpr uint16 ItemSlotLeft = 1 << 5;
constexpr uint16 ItemSlotLegs = 1 << 6;
constexpr uint16 ItemSlotFeet = 1 << 7;
constexpr uint16 ItemSlotRing = 1 << 8;
constexpr uint16 ItemSlotAmmo = 1 << 9;
constexpr uint16 ItemSlotTwoHand = 1 << 10;

int parseWeaponType(std::string value)
{
    stdext::tolower(value);

    if(value == "sword")
        return 1;
    if(value == "axe")
        return 2;
    if(value == "club")
        return 3;
    if(value == "fist")
        return 4;
    if(value == "bow" || value == "distance")
        return 5;
    if(value == "crossbow")
        return 6;
    if(value == "wand" || value == "rod" || value == "wandrod")
        return 7;
    if(value == "throw" || value == "throwing")
        return 8;
    if(value == "quiver")
        return Otc::ITEM_WEAPON_TYPE_QUIVER;

    return 0;
}

uint16 parseSlotPosition(std::string value)
{
    stdext::tolower(value);

    if(value == "head")
        return ItemSlotHead;
    if(value == "necklace")
        return ItemSlotNecklace;
    if(value == "backpack")
        return ItemSlotBackpack;
    if(value == "armor" || value == "body")
        return ItemSlotArmor;
    if(value == "right-hand")
        return ItemSlotRight;
    if(value == "left-hand")
        return ItemSlotLeft;
    if(value == "hand" || value == "shield")
        return ItemSlotRight | ItemSlotLeft;
    if(value == "legs")
        return ItemSlotLegs;
    if(value == "feet")
        return ItemSlotFeet;
    if(value == "ring")
        return ItemSlotRing;
    if(value == "ammo")
        return ItemSlotAmmo;
    if(value == "two-handed")
        return ItemSlotTwoHand;

    return 0;
}

bool hasScriptToken(std::string value, const std::string& token)
{
    stdext::tolower(value);
    return value.find(token) != std::string::npos;
}

void applySlotPosition(const ItemTypePtr& itemType, const std::string& value)
{
    if(value.empty())
        return;

    const uint16 slotPosition = parseSlotPosition(value);
    if(slotPosition != 0)
        itemType->setSlotPosition(slotPosition);
}
}

void ThingTypeManager::init()
{
    m_nullThingType = std::make_shared<ThingType>();
    m_nullItemType = std::make_shared<ItemType>();
    m_datSignature = 0;
    m_contentRevision = 0;
    m_otbMinorVersion = 0;
    m_otbMajorVersion = 0;
    m_datLoaded = false;
    m_xmlLoaded = false;
    m_otbLoaded = false;
    for (int i = 0; i < ThingLastCategory; ++i) {
        m_thingTypes[i].resize(1, m_nullThingType);
        m_checkIndex[i] = 0;
    }
    m_itemTypes.resize(1, m_nullItemType);

    check();
}

void ThingTypeManager::terminate()
{
    for(int i = 0; i < ThingLastCategory; ++i)
        m_thingTypes[i].clear();
    m_itemTypes.clear();
    m_reverseItemTypes.clear();
    m_marketCategories.clear();
    m_nullThingType = nullptr;
    m_nullItemType = nullptr;

    if (m_checkEvent) {
        m_checkEvent->cancel();
        m_checkEvent = nullptr;
    }
}

void ThingTypeManager::unloadTextures()
{
    for (int category = 0; category < ThingLastCategory; ++category) {
        for (const ThingTypePtr& thingType : m_thingTypes[category]) {
            if (thingType)
                thingType->unload();
        }
    }
}

void ThingTypeManager::check()
{    
    // removes unused textures from memory after 60s, 500 checks / s
    m_checkEvent = g_dispatcher.scheduleEvent(std::bind(&ThingTypeManager::check, &g_things), 1000);

    for (size_t i = 0; i < ThingLastCategory; ++i) {
        size_t limit = std::min<size_t>(m_checkIndex[i] + 100, m_thingTypes[i].size());
        for (size_t j = m_checkIndex[i]; j < limit; ++j) {
            if (m_thingTypes[i][j]->isLoaded() && m_thingTypes[i][j]->getLastUsage() + 60 < g_clock.seconds()) {
                m_thingTypes[i][j]->unload();
            }
        }
        m_checkIndex[i] = limit;
        if (m_checkIndex[i] >= m_thingTypes[i].size()) {
            m_checkIndex[i] = 0;
        }
    }
}

#ifdef WITH_ENCRYPTION
void ThingTypeManager::saveDat(std::string fileName)
{
    if(!m_datLoaded)
        stdext::throw_exception("failed to save, dat is not loaded");

    try {
        FileStreamPtr fin = g_resources.createFile(fileName);
        if(!fin)
            stdext::throw_exception(stdext::format("failed to open file '%s' for write", fileName));

        fin->addU32(m_datSignature);

        for(int category = 0; category < ThingLastCategory; ++category)
            fin->addU16(m_thingTypes[category].size() - 1);

        for(int category = 0; category < ThingLastCategory; ++category) {
            uint16 firstId = 1;
            if(category == ThingCategoryItem)
                firstId = 100;

            for(uint16 id = firstId; id < m_thingTypes[category].size(); ++id)
                m_thingTypes[category][id]->serialize(fin);
        }


        fin->flush();
        fin->close();
    } catch(std::exception& e) {
        g_logger.error(stdext::format("Failed to save '%s': %s", fileName, e.what()));
    }
}

void ThingTypeManager::dumpTextures(std::string dir) 
{
    if (dir.empty()) {
        g_logger.error("Empty dir for sprites dump");
        return;
    }
    g_resources.makeDir(dir);
    for (int category = 0; category < ThingLastCategory; ++category) {
        g_resources.makeDir(dir + "/" + std::to_string((int)category));

        uint16 firstId = 1;
        if (category == ThingCategoryItem)
            firstId = 100;

        for (uint16 id = firstId; id < m_thingTypes[category].size(); ++id)
            m_thingTypes[category][id]->exportImage(dir + "/" + std::to_string((int)category) + "/" + std::to_string(id) + ".png");
    }
}

void ThingTypeManager::replaceTextures(std::string dir) {
    if (dir.empty()) {
        g_logger.error("Empty dir for sprites dump");
        return;
    }

    std::map<uint32_t, ImagePtr> replacements;
    for (int category = 0; category < ThingLastCategory; ++category) {
        uint16 firstId = 1;
        if (category == ThingCategoryItem)
            firstId = 100;

        for (uint16 id = firstId; id < m_thingTypes[category].size(); ++id) {
            std::string fileName = dir + "/" + std::to_string((int)category) + "/" + std::to_string(id) + "_[][x2.000000].png";
            m_thingTypes[category][id]->replaceSprites(replacements, fileName);
        }
    }
    //g_sprites.saveReplacedSpr(dir + "/sprites.spr", replacements);
}

#endif

bool ThingTypeManager::loadDat(std::string file)
{
    m_datLoaded = false;
    m_datSignature = 0;
    m_contentRevision = 0;
    try {
        file = g_resources.guessFilePath(file, "dat");

        FileStreamPtr fin = g_resources.openFile(file, g_game.getFeature(Otc::GameDontCacheFiles));

        m_datSignature = fin->getU32();
        m_contentRevision = static_cast<uint16_t>(m_datSignature);

        for(int category = 0; category < ThingLastCategory; ++category) {
            int count = fin->getU16() + 1;
            m_thingTypes[category].clear();
            m_thingTypes[category].resize(count, m_nullThingType);
        }

        m_marketCategories.clear();
        for(int category = 0; category < ThingLastCategory; ++category) {
            uint16 firstId = 1;
            if(category == ThingCategoryItem)
                firstId = 100;
            for(uint16 id = firstId; id < m_thingTypes[category].size(); ++id) {
                auto type = std::make_shared<ThingType>();
                type->unserialize(id, (ThingCategory)category, fin);
                m_thingTypes[category][id] = type;
                if (type->isMarketable()) {
                    auto marketData = type->getMarketData();
                    m_marketCategories.insert(marketData.category);
                }
            }
        }

        m_datLoaded = true;
        g_lua.callGlobalField("g_things", "onLoadDat", file);
        return true;
    } catch(stdext::exception& e) {
        g_logger.error(stdext::format("Failed to read dat '%s': %s'", file, e.what()));
        return false;
    }
}

bool ThingTypeManager::loadOtml(std::string file)
{
    try {
        file = g_resources.guessFilePath(file, "otml");

        OTMLDocumentPtr doc = OTMLDocument::parse(file);
        for(const OTMLNodePtr& node : doc->children()) {
            ThingCategory category;
            if(node->tag() == "creatures")
                category = ThingCategoryCreature;
            else if(node->tag() == "items")
                category = ThingCategoryItem;
            else if(node->tag() == "effects")
                category = ThingCategoryEffect;
            else if(node->tag() == "missiles")
                category = ThingCategoryMissile;
            else {
                throw OTMLException(node, "not a valid thing category");
            }

            for(const OTMLNodePtr& node2 : node->children()) {
                uint16 id = stdext::safe_cast<uint16>(node2->tag());
                ThingTypePtr type = getThingType(id, category);
                if(!type)
                    throw OTMLException(node2, "thing not found");
                type->unserializeOtml(node2);
            }
        }
        return true;
    } catch(std::exception& e) {
        g_logger.error(stdext::format("Failed to read dat otml '%s': %s'", file, e.what()));
        return false;
    }
}

void ThingTypeManager::loadOtb(const std::string& file)
{
    try {
        FileStreamPtr fin = g_resources.openFile(file, g_game.getFeature(Otc::GameDontCacheFiles));

        uint signature = fin->getU32();
        if (signature != 0)
            stdext::throw_exception("invalid otb file");

        BinaryTreePtr root = fin->getBinaryTree();
        root->skip(1); // otb first byte is always 0

        signature = root->getU32();
        if (signature != 0)
            stdext::throw_exception("invalid otb file");

        uint8 rootAttr = root->getU8();
        if (rootAttr == 0x01) { // OTB_ROOT_ATTR_VERSION
            uint16 size = root->getU16();
            if (size != 4 + 4 + 4 + 128)
                stdext::throw_exception("invalid otb root attr version size");

            m_otbMajorVersion = root->getU32();
            m_otbMinorVersion = root->getU32();
            root->skip(4); // buildNumber
            root->skip(128); // description
        }

        BinaryTreeVec children = root->getChildren();
        m_reverseItemTypes.clear();
        m_itemTypes.resize(children.size() + 1, m_nullItemType);
        m_reverseItemTypes.resize(children.size() + 1, m_nullItemType);

        for (const BinaryTreePtr& node : children) {
            auto itemType = std::make_shared<ItemType>();
            itemType->unserialize(node);
            addItemType(itemType);

            uint16 clientId = itemType->getClientId();
            if (unlikely(clientId >= m_reverseItemTypes.size()))
                m_reverseItemTypes.resize(clientId + 1);
            m_reverseItemTypes[clientId] = itemType;
        }

        m_otbLoaded = true;
        g_lua.callGlobalField("g_things", "onLoadOtb", file);
    } catch (std::exception& e) {
        g_logger.error(stdext::format("Failed to load '%s' (OTB file): %s", file, e.what()));
    }
}


void ThingTypeManager::loadXml(const std::string& file)
{
    try {
        if(!isOtbLoaded())
            stdext::throw_exception("OTB must be loaded before XML");

        TiXmlDocument doc;
        doc.Parse(g_resources.readFileContents(file).c_str());
        if(doc.Error())
            stdext::throw_exception(stdext::format("failed to parse '%s': '%s'", file, doc.ErrorDesc()));

        TiXmlElement* root = doc.FirstChildElement();
        if(!root || root->ValueTStr() != "items")
            stdext::throw_exception("invalid root tag name");

        for(TiXmlElement *element = root->FirstChildElement(); element; element = element->NextSiblingElement()) {
            if(unlikely(element->ValueTStr() != "item"))
                continue;

            uint16 id = element->readType<uint16>("id");
            if(id != 0) {
                std::vector<std::string> s_ids = stdext::split(element->Attribute("id"), ";");
                for(const std::string& s : s_ids) {
                    std::vector<int32> ids = stdext::split<int32>(s, "-");
                    if(ids.size() > 1) {
                        int32 i = ids[0];
                        while(i <= ids[1])
                            parseItemType(i++, element);
                    } else
                        parseItemType(atoi(s.c_str()), element);
                }
            } else {
                std::vector<int32> begin = stdext::split<int32>(element->Attribute("fromid"), ";");
                std::vector<int32> end   = stdext::split<int32>(element->Attribute("toid"), ";");
                if(begin[0] && begin.size() == end.size()) {
                    size_t size = begin.size();
                    for(size_t i = 0; i < size; ++i)
                        while(begin[i] <= end[i])
                            parseItemType(begin[i]++, element);
                }
            }
        }

        doc.Clear();
        m_xmlLoaded = true;
        g_logger.debug("items.xml read successfully.");
    } catch(std::exception& e) {
        g_logger.error(stdext::format("Failed to load '%s' (XML file): %s", file, e.what()));
    }
}

void ThingTypeManager::parseItemType(uint16 serverId, TiXmlElement* elem)
{
    ItemTypePtr itemType = nullptr;

    bool s;
    int d;

    if(g_game.getClientVersion() < 960) {
        s = serverId > 20000 && serverId < 20100;
        d = 20000;
    } else {
        s = serverId > 30000 && serverId < 30100;
        d = 30000;
    }

    if(s) {
        serverId -= d;
        itemType = std::make_shared<ItemType>();
        itemType->setServerId(serverId);
        addItemType(itemType);
    } else
        itemType = getItemType(serverId);

    itemType->setName(elem->Attribute("name"));
    for(TiXmlElement* attrib = elem->FirstChildElement(); attrib; attrib = attrib->NextSiblingElement()) {
        std::string key = attrib->Attribute("key");
        if(key.empty())
            continue;

        stdext::tolower(key);
        if(key == "description")
            itemType->setDesc(attrib->Attribute("value"));
        else if(key == "weapontype") {
            itemType->setCategory(ItemCategoryWeapon);
            std::string value = attrib->Attribute("value");
            itemType->setWeaponType(parseWeaponType(value));
        }
        else if(key == "ammotype")
            itemType->setCategory(ItemCategoryAmmunition);
        else if(key == "armor")
            itemType->setCategory(ItemCategoryArmor);
        else if(key == "charges")
            itemType->setCategory(ItemCategoryCharges);
        else if(key == "slottype") {
            std::string value = attrib->Attribute("value");
            if(!value.empty())
                applySlotPosition(itemType, value);
        }
        else if(key == "script") {
            std::string value = attrib->Attribute("value");
            if(!value.empty() && hasScriptToken(value, "moveevent")) {
                for(TiXmlElement* subAttrib = attrib->FirstChildElement(); subAttrib; subAttrib = subAttrib->NextSiblingElement()) {
                    std::string subKeyAttribute = subAttrib->Attribute("key");
                    if(subKeyAttribute.empty())
                        continue;

                    std::string subKey = subKeyAttribute;
                    stdext::tolower(subKey);
                    if(subKey == "slot") {
                        std::string subValue = subAttrib->Attribute("value");
                        if(!subValue.empty())
                            applySlotPosition(itemType, subValue);
                    }
                }
            }
        }
        else if(key == "type") {
            std::string value = attrib->Attribute("value");
            stdext::tolower(value);

            if(value == "key")
                itemType->setCategory(ItemCategoryKey);
            else if(value == "magicfield")
                itemType->setCategory(ItemCategoryMagicField);
            else if(value == "teleport")
                itemType->setCategory(ItemCategoryTeleport);
            else if(value == "door")
                itemType->setCategory(ItemCategoryDoor);
        }
    }
}

void ThingTypeManager::addItemType(const ItemTypePtr& itemType)
{
    uint16 id = itemType->getServerId();
    if(unlikely(id >= m_itemTypes.size()))
        m_itemTypes.resize(id + 1, m_nullItemType);
    m_itemTypes[id] = itemType;
}

const ItemTypePtr& ThingTypeManager::findItemTypeByClientId(uint16 id)
{
    if(id == 0 || id >= m_reverseItemTypes.size())
        return m_nullItemType;

    if(m_reverseItemTypes[id])
        return m_reverseItemTypes[id];
    else
        return m_nullItemType;
}

const ItemTypePtr& ThingTypeManager::findItemTypeByName(std::string name)
{
    for(const ItemTypePtr& it : m_itemTypes)
        if(it->getName() == name)
            return it;
    return m_nullItemType;
}

ItemTypeList ThingTypeManager::findItemTypesByName(std::string name)
{
    ItemTypeList ret;
    for(const ItemTypePtr& it : m_itemTypes)
        if(it->getName() == name)
            ret.push_back(it);
    return ret;
}

ItemTypeList ThingTypeManager::findItemTypesByString(std::string name)
{
    ItemTypeList ret;
    for(const ItemTypePtr& it : m_itemTypes)
        if(it->getName().find(name) != std::string::npos)
            ret.push_back(it);
    return ret;
}

const ThingTypePtr& ThingTypeManager::getThingType(uint16 id, ThingCategory category)
{
    if(category >= ThingLastCategory || id >= m_thingTypes[category].size()) {
        g_logger.error(stdext::format("invalid thing type client id %d in category %d", id, category));
        return m_nullThingType;
    }
    return m_thingTypes[category][id];
}

const ItemTypePtr& ThingTypeManager::getItemType(uint16 id)
{
    if(id >= m_itemTypes.size() || m_itemTypes[id] == m_nullItemType) {
        if(id != 0) {
            g_logger.error(stdext::format("invalid thing type, server id: %d", id));
        }
        return m_nullItemType;
    }
    return m_itemTypes[id];
}

ThingTypeList ThingTypeManager::findThingTypeByAttr(ThingAttr attr, ThingCategory category)
{
    ThingTypeList ret;
    for(const ThingTypePtr& type : m_thingTypes[category])
        if(type->hasAttr(attr))
            ret.push_back(type);
    return ret;
}

ItemTypeList ThingTypeManager::findItemTypeByCategory(ItemCategory category)
{
    ItemTypeList ret;
    for(const ItemTypePtr& type : m_itemTypes)
        if(type->getCategory() == category)
            ret.push_back(type);
    return ret;
}

const ThingTypeList& ThingTypeManager::getThingTypes(ThingCategory category)
{
    ThingTypeList ret;
    if(category >= ThingLastCategory)
        stdext::throw_exception(stdext::format("invalid thing type category %d", category));
    return m_thingTypes[category];
}

/* vim: set ts=4 sw=4 et: */
