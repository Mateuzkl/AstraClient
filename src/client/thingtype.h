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

#ifndef THINGTYPE_H
#define THINGTYPE_H

#include "declarations.h"
#include "animator.h"

#include <framework/core/declarations.h>
#include <framework/otml/declarations.h>
#include <framework/graphics/texture.h>
#include <framework/graphics/coordsbuffer.h>
#include <framework/graphics/drawqueue.h>
#include <framework/luaengine/luaobject.h>
#include <framework/net/server.h>

#include <map>

enum NewDrawType : uint8 {
    NewDrawNormal = 0,
    NewDrawMount = 5,
    NewDrawOutfit = 6,
    NewDrawOutfitLayers = 7,
    NewDrawMissle = 10
};

enum FrameGroupType : uint8 {
    FrameGroupDefault = 0,
    FrameGroupIdle = FrameGroupDefault,
    FrameGroupMoving
};

enum ThingCategory : uint8 {
    ThingCategoryItem = 0,
    ThingCategoryCreature,
    ThingCategoryEffect,
    ThingCategoryMissile,
    ThingInvalidCategory,
    ThingLastCategory = ThingInvalidCategory
};

enum ThingAttr : uint8 {
    ThingAttrGround           = 0,
    ThingAttrGroundBorder     = 1,
    ThingAttrOnBottom         = 2,
    ThingAttrOnTop            = 3,
    ThingAttrContainer        = 4,
    ThingAttrStackable        = 5,
    ThingAttrForceUse         = 6,
    ThingAttrMultiUse         = 7,
    ThingAttrWritable         = 8,
    ThingAttrWritableOnce     = 9,
    ThingAttrFluidContainer   = 10,
    ThingAttrSplash           = 11,
    ThingAttrNotWalkable      = 12,
    ThingAttrNotMoveable      = 13,
    ThingAttrBlockProjectile  = 14,
    ThingAttrNotPathable      = 15,
    ThingAttrPickupable       = 16,
    ThingAttrHangable         = 17,
    ThingAttrHookSouth        = 18,
    ThingAttrHookEast         = 19,
    ThingAttrRotateable       = 20,
    ThingAttrLight            = 21,
    ThingAttrDontHide         = 22,
    ThingAttrTranslucent      = 23,
    ThingAttrDisplacement     = 24,
    ThingAttrElevation        = 25,
    ThingAttrLyingCorpse      = 26,
    ThingAttrAnimateAlways    = 27,
    ThingAttrMinimapColor     = 28,
    ThingAttrLensHelp         = 29,
    ThingAttrFullGround       = 30,
    ThingAttrLook             = 31,
    ThingAttrCloth            = 32,
    ThingAttrMarket           = 33,
    ThingAttrUsable           = 34,
    ThingAttrWrapable         = 35,
    ThingAttrUnwrapable       = 36,
    ThingAttrTopEffect        = 37,
    ThingAttrBones            = 38,

    // additional
    ThingAttrOpacity          = 100,
    ThingAttrNotPreWalkable   = 101,

    // 15.24 item flags consumed by ProtocolGame::getItem (AddItem schema)
    ThingAttrExpire           = 110,
    ThingAttrExpireStop       = 111,
    ThingAttrClockExpire      = 112,
    ThingAttrWearOut          = 113,
    ThingAttrWrapKit          = 114,
    ThingAttrPodium           = 115,
    ThingAttrAmmo             = 116,

    ThingAttrFloorChange      = 252,
    ThingAttrNoMoveAnimation  = 253, // 10.10: real value is 16, but we need to do this for backwards compatibility
    ThingAttrChargeable       = 254, // deprecated
    ThingLastAttr             = 255
};

enum SpriteMask {
    SpriteMask = 1,
};

struct MarketData {
    std::string name;
    int category;
    uint16 requiredLevel;
    // Legacy single-vocation field kept for the old .dat serialization path
    // (thingtype.cpp unserialize/serialize). Lua-facing code uses the full list.
    uint16 restrictVocation;
    // Full restriction list from the appearances protobuf. Pushed to Lua as the
    // `restrictVocation` TABLE the CIP-style mods expect (#list / table.contains).
    std::vector<uint16> restrictVocations;
    uint16 showAs;
    uint16 tradeAs;
};

struct StoreCategory {
    std::string name;
    std::string description;
    int state;
    std::string icon;
    std::string parent;
};

// One purchasable variant of a store offer (offer.offers[] in the Lua UI module).
struct StoreSubOffer {
    int id = 0;
    int count = 1;
    int price = 0;
    int basePrice = 0;
    int coinType = 0;
    int disabledReason = -1;        // index into the category's reason list, -1 = enabled
    int saleValidUntilTimestamp = 0;
};

struct StoreOffer {
    int id = 0;
    std::string name;
    std::string description;
    int price = 0;
    int state = 0;
    std::string icon;
    // crystalserver/Canary 13+ fields consumed by mods/game_store (Offers/Home Lua UI).
    int offerType = 0;              // 0=none/icon 1=mount 2=outfit 3=item 4=hireling
    int itemId = 0;                 // SHOW_ITEM type
    int mountId = 0;                // SHOW_MOUNT type (client id)
    int maleOutfit = 0;             // SHOW_OUTFIT look id
    int head = 0, body = 0, legs = 0, feet = 0; // outfit colors
    int tryMode = 0;                // tryOn type: enables the "Try" button in the store UI
    int requiresConfiguration = 0;  // SHOW_CONFIGURE: button reads "Configure" instead of "Buy"
    std::vector<StoreSubOffer> subOffers;
};

struct Imbuement {
    int id;
    std::string name;
    std::string description;
    std::string group;
    uint8_t tier = 0;
    int imageId;
    int duration;
    bool premiumOnly;
    std::vector<std::pair<ItemPtr, std::string>> sources;
    int cost;
    int successRate;
    int protectionCost;
};

struct ImbuementSlot
{
    ImbuementSlot(const uint8_t id) : id(id) {}

    uint8_t id;
    std::string name;
    uint16_t iconId = 0;
    uint32_t duration = 0;
    bool state = false;
};

struct ImbuementTrackerItem
{
    ImbuementTrackerItem() : slot(0) {}
    ImbuementTrackerItem(const uint8_t slot) : slot(slot) {}

    uint8_t slot;
    uint8_t totalSlots = 0;
    ItemPtr item;
    std::map<uint8_t, ImbuementSlot> slots;
};

struct Light {
    Point pos;
    uint8_t color = 215;
    uint8_t intensity = 0;
};

struct DrawOutfitParams {
    Rect dest;
    TexturePtr texture;
    Rect src;
    Point offset;
    Color color;
};

class AppearancesLoader;
class SpritesheetLoader;

class ThingType : public LuaObject
{
    friend class AppearancesLoader;
    friend class SpritesheetLoader;
public:
    ThingType();

    void unserialize(uint16 clientId, ThingCategory category, const FileStreamPtr& fin);
    void unserializeOtml(const OTMLNodePtr& node);
    void unload();

    void serialize(const FileStreamPtr& fin);
    void exportImage(std::string fileName);
    void replaceSprites(std::map<uint32_t, ImagePtr>& replacements, std::string fileName);

    DrawQueueItem* draw(const Point& dest, int layer, int xPattern, int yPattern, int zPattern, int animationPhase, Color color = Color::white, LightView* lightView = nullptr, uint8_t order = DRAW_ORDER_THIRD);
    DrawQueueItem* draw(const Rect& dest, int layer, int xPattern, int yPattern, int zPattern, int animationPhase, Color color = Color::white);
    std::shared_ptr<DrawOutfitParams> drawOutfit(const Point& dest, int maskLayer, int xPattern, int yPattern, int zPattern, int animationPhase, Color color = Color::white, LightView* lightView = nullptr);
    Rect getDrawSize(const Point& dest, int layer, int xPattern, int yPattern, int zPattern, int animationPhase);
    void drawWithShader(const Point& dest, int layer, int xPattern, int yPattern, int zPattern, int animationPhase, const std::string& shader, Color color = Color::white, LightView* lightView = nullptr, uint8_t order = DRAW_ORDER_THIRD);
    void drawWithShader(const Rect& dest, int layer, int xPattern, int yPattern, int zPattern, int animationPhase, const std::string& shader, Color color = Color::white);
    bool drawToImage(const Point& dest, int xPattern, int yPattern, int zPattern, ImagePtr image);

    uint16 getId() { return m_id; }
    ThingCategory getCategory() { return m_category; }
    bool isNull() { return m_null; }
    bool hasAttr(ThingAttr attr) { return m_attribs.has(attr); }
    bool isLoaded() { return m_loaded; }
    ticks_t getLastUsage() { return m_lastUsage; }

    Size getSize() { return m_size; }
    int getWidth() { return m_size.width(); }
    int getHeight() { return m_size.height(); }
    int getExactSize(int layer = 0, int xPattern = 0, int yPattern = 0, int zPattern = 0, int animationPhase = 0);
    int getRealSize() { return m_realSize; }
    int getLayers() { return m_layers; }
    // clamped to >=1: callers use these as divisors (e.g. pos % getNumPatternX());
    // null/unloaded appearance ids would otherwise crash with integer division by zero
    int getNumPatternX() { return m_numPatternX > 0 ? m_numPatternX : 1; }
    int getNumPatternY() { return m_numPatternY > 0 ? m_numPatternY : 1; }
    int getNumPatternZ() { return m_numPatternZ > 0 ? m_numPatternZ : 1; }
    int getAnimationPhases() { return m_animationPhases > 0 ? m_animationPhases : 1; }
    AnimatorPtr getAnimator() { return m_animator; }
    AnimatorPtr getIdleAnimator() { return m_idleAnimator; }
    Point getDisplacement() { return m_displacement; }
    int getDisplacementX() { return getDisplacement().x; }
    int getDisplacementY() { return getDisplacement().y; }
    // Extra per-thing draw offset applied on top of the .dat displacement.
    // Driven from data/json/offsets.json (modules/game_offsets) so oversized
    // mounts can be re-centered under the rider without a client rebuild.
    // Defaults to (0,0); only the mount draw path in Outfit::draw consumes it.
    Point getDrawOffset() { return m_drawOffset; }
    void setDrawOffset(const Point& offset) { m_drawOffset = offset; }
    int getElevation() { return m_elevation; }
    const Point& getBones(int direction) { return m_bones[direction]; }

    int getGroundSpeed() { return m_attribs.get<uint16>(ThingAttrGround); }
    int getMaxTextLength() { return m_attribs.has(ThingAttrWritableOnce) ? m_attribs.get<uint16>(ThingAttrWritableOnce) : m_attribs.get<uint16>(ThingAttrWritable); }
    Light getLight() { return m_attribs.get<Light>(ThingAttrLight); }
    int getMinimapColor() { return m_attribs.get<uint16>(ThingAttrMinimapColor); }
    int getLensHelp() { return m_attribs.get<uint16>(ThingAttrLensHelp); }
    int getClothSlot() { return m_attribs.get<uint16>(ThingAttrCloth); }
    MarketData getMarketData() { return m_attribs.get<MarketData>(ThingAttrMarket); }
    int getWeaponType();
    bool isGround() { return m_attribs.has(ThingAttrGround); }
    bool isGroundBorder() { return m_attribs.has(ThingAttrGroundBorder); }
    // A "single" ground/border is a 1x1 (32x32) tile piece. Only those belong in the
    // FIRST/SECOND map draw-order layers (below everything). A multi-tile ground sprite
    // (e.g. a 2x2 stone wall flagged as ground) must composite as normal content (THIRD),
    // otherwise it is hoisted UNDER the player and the player draws on top of the wall —
    // mirrors mehah's isSingleGround/isSingleGroundBorder gating.
    bool isSingleDimension() { return m_size.width() == 1 && m_size.height() == 1; }
    bool isSingleGround() { return isGround() && isSingleDimension(); }
    bool isSingleGroundBorder() { return isGroundBorder() && isSingleDimension(); }
    bool isOnBottom() { return m_attribs.has(ThingAttrOnBottom); }
    bool isOnTop() { return m_attribs.has(ThingAttrOnTop); }
    bool isContainer() { return m_attribs.has(ThingAttrContainer); }
    bool isStackable() { return m_attribs.has(ThingAttrStackable); }
    bool isForceUse() { return m_attribs.has(ThingAttrForceUse); }
    bool isMultiUse() { return m_attribs.has(ThingAttrMultiUse); }
    bool isWritable() { return m_attribs.has(ThingAttrWritable); }
    bool isChargeable() { return m_attribs.has(ThingAttrChargeable); }
    bool isWritableOnce() { return m_attribs.has(ThingAttrWritableOnce); }
    bool isFluidContainer() { return m_attribs.has(ThingAttrFluidContainer); }
    bool isSplash() { return m_attribs.has(ThingAttrSplash); }
    bool isNotWalkable() { return m_attribs.has(ThingAttrNotWalkable); }
    bool isNotMoveable() { return m_attribs.has(ThingAttrNotMoveable); }
    bool blockProjectile() { return m_attribs.has(ThingAttrBlockProjectile); }
    bool isNotPathable() { return m_attribs.has(ThingAttrNotPathable); }
    bool isPickupable() { return m_attribs.has(ThingAttrPickupable); }
    bool isHangable() { return m_attribs.has(ThingAttrHangable); }
    bool isHookSouth() { return m_attribs.has(ThingAttrHookSouth); }
    bool isHookEast() { return m_attribs.has(ThingAttrHookEast); }
    bool isRotateable() { return m_attribs.has(ThingAttrRotateable); }
    bool hasLight() { return m_attribs.has(ThingAttrLight); }
    bool isDontHide() { return m_attribs.has(ThingAttrDontHide); }
    bool isTranslucent() { return m_attribs.has(ThingAttrTranslucent); }
    bool hasDisplacement() { return m_attribs.has(ThingAttrDisplacement); }
    bool hasElevation() { return m_attribs.has(ThingAttrElevation); }
    bool isLyingCorpse() { return m_attribs.has(ThingAttrLyingCorpse); }
    bool isCorpse() { return isLyingCorpse(); }
    bool isPlayerCorpse() { return false; }
    bool isAnimateAlways() { return m_attribs.has(ThingAttrAnimateAlways); }
    bool hasMiniMapColor() { return m_attribs.has(ThingAttrMinimapColor); }
    bool hasLensHelp() { return m_attribs.has(ThingAttrLensHelp); }
    bool isFullGround() { return m_attribs.has(ThingAttrFullGround); }
    bool isIgnoreLook() { return m_attribs.has(ThingAttrLook); }
    bool isCloth() { return m_attribs.has(ThingAttrCloth); }
    bool isMarketable() { return m_attribs.has(ThingAttrMarket); }
    bool isUsable() { return m_attribs.has(ThingAttrUsable); }
    bool isWrapable() { return m_attribs.has(ThingAttrWrapable); }
    bool isUnwrapable() { return m_attribs.has(ThingAttrUnwrapable); }
    bool isTopEffect() { return m_attribs.has(ThingAttrTopEffect); }
    bool hasBones() { return m_attribs.has(ThingAttrBones); }
    // 15.24 item flags (AddItem optional fields)
    bool hasExpire() { return m_attribs.has(ThingAttrExpire); }
    bool hasExpireStop() { return m_attribs.has(ThingAttrExpireStop); }
    bool hasClockExpire() { return m_attribs.has(ThingAttrClockExpire); }
    bool hasWearOut() { return m_attribs.has(ThingAttrWearOut); }
    bool isWrapKit() { return m_attribs.has(ThingAttrWrapKit); }
    bool isPodium() { return m_attribs.has(ThingAttrPodium); }
    bool isAmmo() { return m_attribs.has(ThingAttrAmmo); }
    uint16 getClassification() { return m_classification; }
    void setClassification(uint16 c) { m_classification = c; }
    // Base (tier-0/unit) market price pushed by the server via 0xCD ItemsPrices.
    // Consumed by Item::getPriceValue() for loot-value coloring and the analysers.
    uint64_t getPriceValue() { return m_priceValue; }
    void setPriceValue(uint64_t price) { m_priceValue = price; }

    // NPC trade data from the appearances protobuf (npcsaledata): which NPCs buy/sell
    // this item and for how much. salePrice = the NPC sells for (player buys),
    // buyPrice = the NPC pays (player sells).
    struct NpcSaleInfo {
        std::string name;
        std::string location;
        uint32_t salePrice = 0;
        uint32_t buyPrice = 0;
        // alternative currency (protobuf currency_object_type_id /
        // currency_quest_flag_display_name); empty/0 = plain gold
        uint32_t currencyObjectTypeId = 0;
        std::string currencyQuestFlagDisplayName;
    };
    // Appearance display name (protobuf Appearance.name); used by the cyclopedia mods
    // when an item has no market data name.
    const std::string& getAppearanceName() { return m_appearanceName; }
    void setAppearanceName(std::string name) { m_appearanceName = std::move(name); }

    // Weapon proficiency id (protobuf AppearanceFlagProficiency); 0 = none.
    uint16_t getProficiencyId() { return m_proficiencyId; }
    void setProficiencyId(uint16_t id) { m_proficiencyId = id; }

    // Weapon type from the appearances protobuf (WEAPON_TYPE_*: 0=none, 1=sword, 2=axe,
    // 3=club, 4=fist, 5=bow, 6=crossbow, 7=wand/rod, 8=throw — same numbering as the
    // gamelib WEAPON_* Lua constants). getWeaponType() prefers this over the legacy OTB
    // lookup, which returns 0 on OTB-less 15.x setups.
    void setWeaponType(int type) { m_weaponType = type; }

    const std::vector<NpcSaleInfo>& getNpcSaleData() { return m_npcSaleData; }
    void addNpcSaleData(NpcSaleInfo info) {
        // Derived defaults: best player-sell value (max NPC buy price) and cheapest
        // player-buy cost (min non-zero NPC sale price).
        if (info.buyPrice > m_npcSellValue)
            m_npcSellValue = info.buyPrice;
        if (info.salePrice > 0 && (m_npcBuyValue == 0 || info.salePrice < m_npcBuyValue))
            m_npcBuyValue = info.salePrice;
        m_npcSaleData.emplace_back(std::move(info));
    }
    uint32_t getNpcSellValue() { return m_npcSellValue; }
    uint32_t getNpcBuyValue() { return m_npcBuyValue; }

    std::vector<int> getSprites() { return m_spritesIndex; }

    // additional
    float getOpacity() { return m_opacity; }
    bool isNotPreWalkable() { return m_attribs.has(ThingAttrNotPreWalkable); }
    void setPathable(bool var);

private:
    const TexturePtr& getTexture(int animationPhase);
    Size getBestTextureDimension(int w, int h, int count);
    uint getSpriteIndex(int w, int h, int l, int x, int y, int z, int a);
    uint getTextureIndex(int l, int x, int y, int z);

    ThingCategory m_category;
    uint16 m_id;
    bool m_null;
    stdext::dynamic_storage<uint8> m_attribs;

    Size m_size;
    Point m_displacement;
    Point m_drawOffset; // runtime-only, set from offsets.json; not serialized
    AnimatorPtr m_animator;
    AnimatorPtr m_idleAnimator;
    std::vector<Point> m_bones;
    int m_animationPhases;
    uint16 m_classification = 0; // 15.24 upgrade/tier classification
    uint64_t m_priceValue = 0; // unit price from server 0xCD ItemsPrices
    std::vector<NpcSaleInfo> m_npcSaleData; // appearances npcsaledata
    uint32_t m_npcSellValue = 0; // max NPC buy price (best value selling to NPC)
    uint32_t m_npcBuyValue = 0; // min NPC sale price (cheapest buying from NPC)
    std::string m_appearanceName; // protobuf Appearance.name
    uint16_t m_proficiencyId = 0; // appearances proficiency flag (0 = none)
    int m_weaponType = 0; // appearances weapon_type (0 = none/unset)
    int m_exactSize;
    int m_realSize;
    int m_numPatternX, m_numPatternY, m_numPatternZ;
    int m_layers;
    int m_elevation;
    float m_opacity;
    std::string m_customImage;

    std::vector<int> m_spritesIndex;
    std::vector<TexturePtr> m_textures;
    std::vector<std::vector<Rect>> m_texturesFramesRects;
    std::vector<std::vector<Rect>> m_texturesFramesOriginRects;
    std::vector<std::vector<Point>> m_texturesFramesOffsets;

    bool m_loaded = false;
    time_t m_lastUsage;
};

struct DrawQueueItemThingWithShader : public DrawQueueItemTexturedRect {
    DrawQueueItemThingWithShader(const Rect& rect, const TexturePtr& texture, const Rect& src, const Point& offset, const Point& center, int32_t colors, const std::string& shader) :
        DrawQueueItemTexturedRect(rect, texture, src, Color::white), m_offset(offset), m_center(center), m_colors(colors), m_shader(shader)
    {};

    void draw() override;
    void draw(const Point& pos) override
    {}
    bool cache() override
    {
        return false;
    }

    Point m_offset;
    Point m_center;
    int32_t m_colors;
    std::string m_shader;
};

#endif
