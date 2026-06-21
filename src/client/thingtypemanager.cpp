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
#include "appearancesloader.h"
#include "spritemanager.h"
#include "spritesheetloader.h"
#include "thing.h"
#include "thingtype.h"
#include "itemtype.h"
#include "creature.h"
#include "creatures.h"
#include "game.h"

#include <framework/core/resourcemanager.h>
#include <framework/core/filestream.h>
#include <framework/core/binarytree.h>
#include <framework/xml/tinyxml.h>
#include <framework/otml/otml.h>
#include <framework/util/stats.h>

// === Tibia 12+ protobuf path ===
// Phase 0 P0.8: nlohmann/json for getAppearancesPath() catalog scan + fstream
// for the same. The SpriteSheetLoader pulls these in too — including them
// here keeps the .cpp self-contained even if loadSpriteSheets is excluded.
#include <nlohmann/json.hpp>
#include <fstream>
// === end protobuf path ===

ThingTypeManager g_things;

// === Tibia 12+ protobuf path ===
// Phase 0 P0.8: ctor/dtor defined here (not =default-in-class) so the
// std::unique_ptr<SpriteSheetLoader> member sees the complete type when it
// instantiates its destructor. Header carries only a forward declaration.
ThingTypeManager::ThingTypeManager() = default;
ThingTypeManager::~ThingTypeManager() = default;
// === end protobuf path ===

namespace {
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

    return 0;
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
            if (thingType && !thingType->isNull())
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

// === Tibia 12+ protobuf path ===
// Phase 0 P0.8: protobuf entry points. All three bodies below are isolated in
// this marker block so the legacy loadDat() above stays clearly reviewable as
// the 8.60 path. None of these touch loadDat / loadOtb / loadXml / loadOtml.

bool ThingTypeManager::loadAppearances(const std::string& file)
{
    // Phase 0 #9 / P0.8: thin delegation to AppearancesLoader. The loader owns
    // all the protobuf parsing logic and writes the result back into this
    // manager's per-category vectors (it is a friend of ThingTypeManager).
    // Lua picks this entry point only when catalog-content.json is present
    // alongside the assets — the legacy 8.60 boot path keeps calling
    // loadDat() above unchanged.
    //
    // Ordering guard per project_proto_sprite_size memo: ThingType::m_size
    // is derived from the sprite SHEET's spritetype (32x32 / 32x64 / 64x32 /
    // 64x64), NOT from the proto's bounding_square. If the sheets aren't
    // ready when AppearancesLoader runs, any future P1.x revision that
    // consults SpriteSheetLoader::getSpriteCellSize() during appearance
    // parsing will silently fall back to (32,32) and corrupt the atlas. We
    // accept either the modern sheet loader OR the legacy g_sprites being
    // live, since both ship the same spriteId -> dimensions truth.
    VALIDATE(m_spriteSheetLoader != nullptr || g_sprites.isLoaded());

    AppearancesLoader loader;
    if (!loader.load(file))
        return false;

    m_datLoaded = true;
    g_lua.callGlobalField("g_things", "onLoadDat", file);
    return true;
}

bool ThingTypeManager::loadSpriteSheets(const std::string& assetsDir)
{
    // Phase 0 P0.8: parse catalog-content.json and stash the LRU loader on
    // the manager. Per-sheet LZMA decompression is lazy — happens the first
    // time a sprite is requested. The boot path is free to wire
    // g_sprites.loadSpr through this same SpriteSheetLoader later (mirrors
    // the koliseu-otcv8 P1.4 wiring); this entry point is also useful for
    // tooling that wants to inspect the catalog without touching g_sprites.
    auto loader = std::make_unique<SpriteSheetLoader>();
    if (!loader->loadCatalog(assetsDir))
        return false;
    m_spriteSheetLoader = std::move(loader);
    return true;
}

// Phase 0 P0.8 (generalized): read catalog-content.json, find the entry with
// the requested "type", and return its path. Used by the Lua boot path to
// discover hashed <type>-<sha>.dat filenames without globbing or hardcoding.
//
// `assetsDir` may be a PHYSFS virtual path (e.g. "/things/1524"); Lua's
// resolvepath returns those. Everything below reads through PHYSFS (g_resources)
// so it works from an in-memory (possibly encrypted) data.zip, not just a real dir.
static std::string getCatalogEntryPath(const std::string& assetsDir, const std::string& entryType)
{
    if (assetsDir.empty()) {
        g_logger.error(stdext::format("getCatalogEntryPath(%s): empty assetsDir", entryType));
        return std::string();
    }

    try {
        // Normalize to a VIRTUAL PHYSFS path with a trailing slash. The returned
        // entry path stays virtual so the PHYSFS-aware loaders open it directly.
        std::string virtualDir = g_resources.resolvePath(assetsDir);
        if (virtualDir.empty())
            virtualDir = assetsDir;
        if (virtualDir.back() != '/' && virtualDir.back() != '\\')
            virtualDir.push_back('/');

        // Read the catalog through PHYSFS (g_resources), NOT std::ifstream: the
        // assets can live inside an in-memory data.zip (encrypted container),
        // which has no real filesystem path. readFileContents also transparently
        // decrypts per-file-encrypted assets (plaintext for an unencrypted dev tree).
        const std::string catalogPath = virtualDir + "catalog-content.json";
        if (!g_resources.fileExists(catalogPath)) {
            g_logger.error(stdext::format(
                "getCatalogEntryPath(%s): catalog not found at '%s'", entryType, catalogPath));
            return std::string();
        }
        nlohmann::json catalog = nlohmann::json::parse(g_resources.readFileContents(catalogPath));

        if (!catalog.is_array()) {
            g_logger.error(stdext::format(
                "getCatalogEntryPath(%s): catalog '%s' is not a JSON array",
                entryType, catalogPath));
            return std::string();
        }

        for (const auto& entry : catalog) {
            auto typeIt = entry.find("type");
            auto fileIt = entry.find("file");
            if (typeIt == entry.end() || !typeIt->is_string())
                continue;
            if (fileIt == entry.end() || !fileIt->is_string())
                continue;
            if (typeIt->get<std::string>() != entryType)
                continue;
            // Return VIRTUAL path so PHYSFS-aware loaders (loadAppearances)
            // can open it directly. Callers that need a real FS path should
            // run PHYSFS_getRealDir on the returned virtual path.
            return virtualDir + fileIt->get<std::string>();
        }

        g_logger.error(stdext::format(
            "getCatalogEntryPath(%s): no matching entry in '%s'",
            entryType, catalogPath));
        return std::string();
    } catch (const std::exception& e) {
        g_logger.error(stdext::format(
            "getCatalogEntryPath(%s): exception parsing catalog in '%s': %s",
            entryType, assetsDir, e.what()));
        return std::string();
    }
}

std::string ThingTypeManager::getAppearancesPath(const std::string& assetsDir)
{
    return getCatalogEntryPath(assetsDir, "appearances");
}

std::string ThingTypeManager::getStaticDataPath(const std::string& assetsDir)
{
    return getCatalogEntryPath(assetsDir, "staticdata");
}

// === end protobuf path ===

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
    // 0 is the "no OTB entry" sentinel (findItemTypeByClientId returns the null
    // item type whose server id is 0); on appearances-based setups no OTB is
    // ever loaded, so don't log it as a missing entry.
    if(id == 0)
        return m_nullItemType;
    if(id >= m_itemTypes.size() || m_itemTypes[id] == m_nullItemType) {
        g_logger.error(stdext::format("invalid thing type, server id: %d", id));
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

ThingTypeList ThingTypeManager::getProficiencyThings()
{
    // All item types carrying a weapon-proficiency id (appearances proficiency flag).
    // Consumed by mods/game_proficiency to build its weapon catalog.
    ThingTypeList ret;
    for (const ThingTypePtr& type : m_thingTypes[ThingCategoryItem]) {
        if (type && type->getProficiencyId() > 0)
            ret.push_back(type);
    }
    return ret;
}

std::string ThingTypeManager::getCyclopediaItemName(uint16 id)
{
    // Display name from the appearances protobuf (fallback used by the cyclopedia
    // mods when an item has no market-data name).
    if (!isValidDatId(id, ThingCategoryItem))
        return {};
    return m_thingTypes[ThingCategoryItem][id]->getAppearanceName();
}

/* vim: set ts=4 sw=4 et: */
