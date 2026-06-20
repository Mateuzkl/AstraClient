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

#ifndef THINGTYPEMANAGER_H
#define THINGTYPEMANAGER_H

#include <framework/global.h>
#include <framework/core/declarations.h>
#include <framework/core/eventdispatcher.h>

#include "thingtype.h"
#include "itemtype.h"

#include <memory>

// === Tibia 12+ protobuf path ===
// Phase 0 P0.8: forward decls. AppearancesLoader is a friend so it can write
// directly into the per-category vectors during parse. SpriteSheetLoader is
// held via std::unique_ptr below — declaring it here (instead of including
// spritesheetloader.h) keeps the header lightweight and avoids transitively
// pulling in <nlohmann/json.hpp> + LZMA headers everywhere.
class AppearancesLoader;
class SpriteSheetLoader;
// === end protobuf path ===

class ThingTypeManager
{
    // === Tibia 12+ protobuf path ===
    // Phase 0 #9 / P0.8: AppearancesLoader writes parsed thingtypes back into
    // m_thingTypes[] / m_marketCategories during load(). Granting friendship
    // (rather than exposing setters) keeps the public surface unchanged for
    // the legacy 8.60 path and matches the pattern in koliseu-otcv8.
    friend class AppearancesLoader;
    // === end protobuf path ===

public:
    // === Tibia 12+ protobuf path ===
    // Phase 0 P0.8: ctor/dtor declared out-of-line (not =default-in-class) so
    // the std::unique_ptr<SpriteSheetLoader> member below can hold a
    // forward-declared type in this header. Bodies live in the .cpp where
    // spritesheetloader.h is in scope; without this, every TU that includes
    // thingtypemanager.h would have to see the full SpriteSheetLoader.
    ThingTypeManager();
    ~ThingTypeManager();
    // === end protobuf path ===

    void init();
    void terminate();
    void check();

    bool loadDat(std::string file);
    // === Tibia 12+ protobuf path ===
    // Phase 0 #9 / P0.8: modern protobuf appearances loader. Thin wrapper
    // over AppearancesLoader so Lua (modules/game_things/things.lua) can
    // pick the modern path when data/things/<version>/catalog-content.json
    // exists. Legacy 8.60 boot never touches this — see loadDat above.
    //
    // CRITICAL ordering: loadSpriteSheets() MUST be called before
    // loadAppearances(). ThingType::m_size derives from the sprite SHEET's
    // spritetype (32x32 / 32x64 / 64x32 / 64x64), NOT from the proto
    // bounding_square. Enforced at runtime by a VALIDATE() inside
    // loadAppearances(). See memory note: project_proto_sprite_size.
    bool loadAppearances(const std::string& file);
    // Phase 0 P0.8: parse catalog-content.json and own the sheet LRU. The
    // actual per-sheet LZMA + BMP decode is lazy (paid on first sprite
    // request); this call only validates the catalog. Returns false on any
    // I/O / json error — the SpriteSheetLoader logs the diagnostic.
    bool loadSpriteSheets(const std::string& assetsDir);
    // Phase 0 P0.8: read `<assetsDir>/catalog-content.json` and return the
    // absolute path to the entry marked "type":"appearances". Returns an
    // empty string on any error. Used by the Lua boot path to discover the
    // hashed appearances-<sha>.dat filename without globbing.
    std::string getAppearancesPath(const std::string& assetsDir);
    // Same catalog scan for the "type":"staticdata" entry (monsters/bosses
    // with bestiary race ids). The actual loader lives in
    // CreatureManager::loadStaticData — keeping staticdata.pb.h confined to
    // creatures.cpp avoids the include cycle the koliseu-otcv8 pimpl existed
    // to break.
    std::string getStaticDataPath(const std::string& assetsDir);
    // === end protobuf path ===
    bool loadOtml(std::string file);
    void loadOtb(const std::string& file);
    void loadXml(const std::string& file);
    void parseItemType(uint16 id, TiXmlElement *elem);

#ifdef WITH_ENCRYPTION
    void saveDat(std::string fileName);
    void dumpTextures(std::string dir);
    void replaceTextures(std::string dir);
#endif

    void addItemType(const ItemTypePtr& itemType);
    const ItemTypePtr& findItemTypeByClientId(uint16 id);
    const ItemTypePtr& findItemTypeByName(std::string name);
    ItemTypeList findItemTypesByName(std::string name);
    ItemTypeList findItemTypesByString(std::string str);

    std::set<int> getMarketCategories()
    {
        return m_marketCategories;
    }

    const ThingTypePtr& getNullThingType() { return m_nullThingType; }
    const ItemTypePtr& getNullItemType() { return m_nullItemType; }

    const ThingTypePtr& getThingType(uint16 id, ThingCategory category);
    const ItemTypePtr& getItemType(uint16 id);
    ThingType* rawGetThingType(uint16 id, ThingCategory category) { 
        VALIDATE(id < m_thingTypes[category].size());
        return m_thingTypes[category][id].get(); 
    }
    ItemType* rawGetItemType(uint16 id) { 
        VALIDATE(id < m_itemTypes.size());
        return m_itemTypes[id].get();
    }

    ThingTypeList findThingTypeByAttr(ThingAttr attr, ThingCategory category);
    ItemTypeList findItemTypeByCategory(ItemCategory category);

    const ThingTypeList& getThingTypes(ThingCategory category);
    const ItemTypeList& getItemTypes() { return m_itemTypes; }
    ThingTypeList getProficiencyThings();
    std::string getCyclopediaItemName(uint16 id);

    uint32 getDatSignature() { return m_datSignature; }
    uint32 getOtbMajorVersion() { return m_otbMajorVersion; }
    uint32 getOtbMinorVersion() { return m_otbMinorVersion; }
    uint16 getContentRevision() { return m_contentRevision; }

    bool isDatLoaded() { return m_datLoaded; }
    // Discard every ThingType's cached textures so they rebuild on next draw.
    // Used when the sprite texture scale changes (HD-sprite toggle).
    void unloadTextures();
    bool isXmlLoaded() { return m_xmlLoaded; }
    bool isOtbLoaded() { return m_otbLoaded; }

    // an id inside the range can still be a hole in the appearances file (nullType);
    // treating it as valid lets Effect/Missile/Item draw a ThingType with zeroed
    // pattern dimensions, which crashes on integer division
    bool isValidDatId(uint16 id, ThingCategory category) {
        return id >= 1 && id < m_thingTypes[category].size()
            && m_thingTypes[category][id] && !m_thingTypes[category][id]->isNull();
    }
    bool isValidOtbId(uint16 id) { return id >= 1 && id < m_itemTypes.size(); }

private:
    ThingTypeList m_thingTypes[ThingLastCategory];
    ItemTypeList m_reverseItemTypes;
    ItemTypeList m_itemTypes;
    std::set<int> m_marketCategories;

    ThingTypePtr m_nullThingType;
    ItemTypePtr m_nullItemType;

    bool m_datLoaded;
    bool m_xmlLoaded;
    bool m_otbLoaded;

    uint32 m_otbMinorVersion;
    uint32 m_otbMajorVersion;
    uint32 m_datSignature;
    uint16 m_contentRevision;

    ScheduledEventPtr m_checkEvent;
    size_t m_checkIndex[ThingLastCategory];

    // === Tibia 12+ protobuf path ===
    // Phase 0 P0.8: owns the sprite-sheet LRU for Tibia 15.24 assets. Held
    // by unique_ptr so this header does not need to include
    // spritesheetloader.h (which would drag <nlohmann/json.hpp> + LZMA in).
    // Allocated by loadSpriteSheets(); checked by loadAppearances() to
    // enforce the sheet-before-appearances ordering required by
    // project_proto_sprite_size.
    std::unique_ptr<SpriteSheetLoader> m_spriteSheetLoader;
    // === end protobuf path ===
};

extern ThingTypeManager g_things;

#endif
