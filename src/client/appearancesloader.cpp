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

#include "appearancesloader.h"
#include "animator.h"
#include "thingtypemanager.h"
#include "spritemanager.h"

#include "appearances.pb.h"

#include <framework/core/clock.h>
#include <framework/core/logger.h>
#include <framework/core/resourcemanager.h>
#include <framework/stdext/format.h>

#include <algorithm>
#include <fstream>

using namespace Crystal::protobuf::appearances;

// ----------------------------------------------------------------------------
// Public API
// ----------------------------------------------------------------------------

// Defined here (not in header) so the std::unique_ptr<Appearances> sees the
// full protobuf type when it instantiates its destructor.
AppearancesLoader::AppearancesLoader() = default;
AppearancesLoader::~AppearancesLoader() = default;

bool AppearancesLoader::load(const std::string& file)
{
    // Reset per-load state. We never throw; on any failure we log and return
    // false, mirroring the robustness contract (P1.2 robustness contract).
    // P1.2 fix: wrap the entire body in try/catch so any std::exception
    // (bad_alloc, ios_base::failure, protobuf::FatalException, ...) is caught
    // and logged — without this, exceptions bubble to luaCppFunctionCallback's
    // `catch(...)` which fires g_logger.fatal with no useful diagnostic.
    try {
        m_appearances.reset();
        for (int i = 0; i < ThingLastCategory; ++i)
            m_categoryCounts[i] = 0;

        // Read through PHYSFS (g_resources), NOT std::ifstream: appearances.dat
        // may live inside an in-memory encrypted data.zip with no real filesystem
        // path. readFileContents transparently decrypts per-file-encrypted assets
        // (and returns plaintext for an unencrypted dev tree).
        if (!g_resources.fileExists(file)) {
            g_logger.error(stdext::format("AppearancesLoader: cannot open '%s'", file));
            return false;
        }
        const std::string data = g_resources.readFileContents(file);

        GOOGLE_PROTOBUF_VERIFY_VERSION;

        auto appearances = std::make_unique<Appearances>();
        if (!appearances->ParseFromArray(data.data(), static_cast<int>(data.size()))) {
            g_logger.error(stdext::format("AppearancesLoader: failed to parse '%s' (corrupt protobuf?)", file));
            return false;
        }

        // Compute per-category capacities so g_things.m_thingTypes[]/findItemTypeByClientId
        // can index by app.id() without resizing in the inner loop.
        auto computeMaxId = [](const auto& repeated) {
            uint32_t maxId = 0;
            for (int i = 0, n = repeated.size(); i < n; ++i)
                if (repeated.Get(i).id() > maxId)
                    maxId = repeated.Get(i).id();
            return maxId;
        };

        const uint32_t maxItemId    = computeMaxId(appearances->object());
        const uint32_t maxOutfitId  = computeMaxId(appearances->outfit());
        const uint32_t maxEffectId  = computeMaxId(appearances->effect());
        const uint32_t maxMissileId = computeMaxId(appearances->missile());

        // Reuse the existing null-thingtype to fill the gaps, just like loadDat.
        const ThingTypePtr& nullType = g_things.getNullThingType();
        auto reset = [&](ThingCategory cat, uint32_t maxId) {
            // +1: arrays are indexed by id (1-based for items starting at 100, etc.).
            auto& vec = g_things.m_thingTypes[cat];
            vec.clear();
            vec.resize(maxId + 1, nullType);
        };

        reset(ThingCategoryItem,     maxItemId);
        reset(ThingCategoryCreature, maxOutfitId);
        reset(ThingCategoryEffect,   maxEffectId);
        reset(ThingCategoryMissile,  maxMissileId);

        // Cross-cuts loadDat: market categories are rebuilt during the load.
        auto& marketCategories = g_things.m_marketCategories;
        marketCategories.clear();

        auto populate = [&](const google::protobuf::RepeatedPtrField<Appearance>& repeated,
                            ThingCategory category) {
            const int n = repeated.size();
            m_categoryCounts[category] = n;
            auto& vec = g_things.m_thingTypes[category];
            for (int i = 0; i < n; ++i) {
                const Appearance& app = repeated.Get(i);
                const uint32_t id = app.id();
                if (id == 0 || id >= vec.size())
                    continue;

                ThingTypePtr type;
                if (!buildThingType(app, category, type))
                    continue;

                vec[id] = type;

                if (type->isMarketable()) {
                    MarketData md = type->getMarketData();
                    marketCategories.insert(md.category);
                }
            }
        };

        populate(appearances->object(),  ThingCategoryItem);
        populate(appearances->outfit(),  ThingCategoryCreature);
        populate(appearances->effect(),  ThingCategoryEffect);
        populate(appearances->missile(), ThingCategoryMissile);

        m_appearances = std::move(appearances);

        g_logger.info(stdext::format("Loaded %d items, %d outfits, %d effects, %d missiles from %s",
            m_categoryCounts[ThingCategoryItem],
            m_categoryCounts[ThingCategoryCreature],
            m_categoryCounts[ThingCategoryEffect],
            m_categoryCounts[ThingCategoryMissile],
            file));

        return true;
    } catch (const std::exception& e) {
        g_logger.error(stdext::format("AppearancesLoader: std::exception in load('%s'): %s", file, e.what()));
        m_appearances.reset();
        return false;
    } catch (...) {
        g_logger.error(stdext::format("AppearancesLoader: unknown exception in load('%s')", file));
        m_appearances.reset();
        return false;
    }
}

int AppearancesLoader::getCategoryCount(ThingCategory category) const
{
    if (category >= ThingLastCategory)
        return 0;
    return m_categoryCounts[category];
}

// ----------------------------------------------------------------------------
// Per-appearance build
// ----------------------------------------------------------------------------

bool AppearancesLoader::buildThingType(const Appearance& app, ThingCategory category, ThingTypePtr& out)
{
    auto type = std::make_shared<ThingType>();
    type->m_null = false;
    type->m_id = app.id(); // 32-bit client id; do NOT truncate to uint16 (ids > 65535 exist)
    type->m_category = category;

    // Bytes-typed in proto, std::string in C++ — direct assignment is safe.
    const std::string name = app.has_name() ? app.name() : std::string();
    type->setAppearanceName(name);

    if (app.has_flags())
        applyFlags(app.flags(), name, *type);

    int totalSpritesCount = 0;
    std::vector<FrameGroupLayout> groupLayouts;
    const int groupCount = app.frame_group_size();
    for (int g = 0; g < groupCount; ++g)
        applyFrameGroup(app.frame_group(g), category, *type, totalSpritesCount, groupLayouts);

    // Some multi-group outfits ship idle/moving groups with DIFFERENT dims
    // (e.g. outfit 267: idle 4x2x1x1, moving 4x1x1x1). applyFrameGroup writes
    // last-group-wins dims while appending each group's sprites flat, but
    // getSpriteIndex indexes the whole concatenated phase axis with ONE stride
    // from the final dims — so divergent groups render scrambled (or clamp +
    // traceError-spam past the vector end). Re-layout every phase to the
    // per-dimension maxima, mirroring the legacy .dat correction block
    // (thingtype.cpp:364-400) that the proto path lacked.
    bool dimsDiverge = false;
    for (size_t i = 1; i < groupLayouts.size(); ++i) {
        const FrameGroupLayout& a = groupLayouts[0];
        const FrameGroupLayout& b = groupLayouts[i];
        if (b.layers != a.layers || b.patternX != a.patternX
            || b.patternY != a.patternY || b.patternZ != a.patternZ) {
            dimsDiverge = true;
            break;
        }
    }
    if (dimsDiverge) {
        int maxL = 1, maxX = 1, maxY = 1, maxZ = 1;
        int maxCellW = 1, maxCellH = 1, maxRealSize = 0;
        for (const FrameGroupLayout& gl : groupLayouts) {
            maxL = std::max(maxL, gl.layers);
            maxX = std::max(maxX, gl.patternX);
            maxY = std::max(maxY, gl.patternY);
            maxZ = std::max(maxZ, gl.patternZ);
            maxCellW = std::max(maxCellW, gl.cellW);
            maxCellH = std::max(maxCellH, gl.cellH);
            maxRealSize = std::max(maxRealSize, gl.realSize);
        }
        const int totalPhases = type->m_animationPhases;
        std::vector<int> newIndex(static_cast<size_t>(maxL) * maxX * maxY * maxZ * totalPhases, 0);
        int phaseBase = 0;
        for (const FrameGroupLayout& gl : groupLayouts) {
            for (int p = 0; p < gl.phases; ++p) {
                const int a = phaseBase + p;
                for (int z = 0; z < maxZ; ++z) {
                    for (int y = 0; y < maxY; ++y) {
                        for (int x = 0; x < maxX; ++x) {
                            for (int l = 0; l < maxL; ++l) {
                                const int dst = (((a * maxZ + z) * maxY + y) * maxX + x) * maxL + l;
                                // Duplicate the nearest real sprite (modulo patterns,
                                // clamp layers) rather than 0-fill: getSpriteIndex wraps
                                // the same way, and 0-fill would blank e.g. an idle group
                                // with Z=1 drawn at zPattern=1 (mounted).
                                const int src = gl.spriteOffset
                                    + (((p * gl.patternZ + (z % gl.patternZ)) * gl.patternY + (y % gl.patternY))
                                        * gl.patternX + (x % gl.patternX)) * gl.layers
                                    + std::min(l, gl.layers - 1);
                                newIndex[dst] = type->m_spritesIndex[src];
                            }
                        }
                    }
                }
            }
            phaseBase += gl.phases;
        }
        type->m_spritesIndex = std::move(newIndex);
        type->m_layers = maxL;
        type->m_numPatternX = maxX;
        type->m_numPatternY = maxY;
        type->m_numPatternZ = maxZ;
        // m_size/m_realSize were also last-group-wins; getTexture uses m_size as
        // the atlas frame cell for ALL phases, so normalize the footprint too
        // (same as the legacy correction at thingtype.cpp:364-369).
        const int spriteSize = g_sprites.getBaseSpriteSize(); // native: exact size is UI/Lua-facing, must not scale with HD
        type->m_size = Size(maxCellW, maxCellH);
        type->m_realSize = maxRealSize;
        type->m_exactSize = std::min<int>(maxRealSize, std::max<int>(maxCellW * spriteSize, maxCellH * spriteSize));
    }

    // Mirror legacy ThingType::unserialize line 387: if only an idle animator
    // exists, promote it to m_animator (the moving slot is the "default").
    if (type->m_idleAnimator && !type->m_animator) {
        type->m_animator = type->m_idleAnimator;
        type->m_idleAnimator = nullptr;
    }

    // Mirror legacy lines 392–395: the texture lazy-load caches are sized by
    // the final animationPhases count of the merged groups.
    if (type->m_animationPhases > 0) {
        type->m_textures.resize(type->m_animationPhases);
        type->m_texturesFramesRects.resize(type->m_animationPhases);
        type->m_texturesFramesOriginRects.resize(type->m_animationPhases);
        type->m_texturesFramesOffsets.resize(type->m_animationPhases);
    }

    type->m_lastUsage = g_clock.seconds();

    out = type;
    return true;
}

// ----------------------------------------------------------------------------
// Flags -> ThingAttr mapping
// ----------------------------------------------------------------------------

void AppearancesLoader::applyFlags(const AppearanceFlags& f, const std::string& name, ThingType& t)
{
    // The mapping below is derived from src/client/proto/appearances.proto
    // (AppearanceFlags) cross-referenced with src/client/thingtype.cpp's
    // legacy unserialize(). Each ThingAttr matches the legacy storage shape
    // so downstream code (tile rendering, market UI, light view, etc.) works
    // unchanged.

    // bank.waypoints -> ThingAttrGround (uint16 walking speed of ground tile).
    // Legacy thingtype.cpp:255 reads U16 into ThingAttrGround.
    if (f.has_bank() && f.bank().has_waypoints())
        t.m_attribs.set<uint16>(ThingAttrGround, static_cast<uint16>(f.bank().waypoints()));

    if (f.clip())                  t.m_attribs.set(ThingAttrGroundBorder, true);
    if (f.bottom())                t.m_attribs.set(ThingAttrOnBottom, true);
    if (f.top())                   t.m_attribs.set(ThingAttrOnTop, true);
    if (f.container())             t.m_attribs.set(ThingAttrContainer, true);
    if (f.cumulative())            t.m_attribs.set(ThingAttrStackable, true);

    // P1.2: `usable` is the proto's standalone "default action allowed" bool
    // (proto field 7). In the legacy unserialize ThingAttrUsable carries a
    // U16 payload (thingtype.cpp:254-261); for protobuf we only have the bool
    // bit so we store it without a value. Distinct from `multiuse`/`forceuse`.
    if (f.usable())                t.m_attribs.set(ThingAttrUsable, true);
    if (f.forceuse())              t.m_attribs.set(ThingAttrForceUse, true);
    if (f.multiuse())              t.m_attribs.set(ThingAttrMultiUse, true);

    // write/write_once carry a max-text-length U16. Legacy thingtype.cpp:256.
    if (f.has_write() && f.write().has_max_text_length())
        t.m_attribs.set<uint16>(ThingAttrWritable, static_cast<uint16>(f.write().max_text_length()));
    if (f.has_write_once() && f.write_once().has_max_text_length_once())
        t.m_attribs.set<uint16>(ThingAttrWritableOnce, static_cast<uint16>(f.write_once().max_text_length_once()));

    if (f.liquidpool())            t.m_attribs.set(ThingAttrSplash, true);
    if (f.unpass())                t.m_attribs.set(ThingAttrNotWalkable, true);
    if (f.unmove())                t.m_attribs.set(ThingAttrNotMoveable, true);
    if (f.unsight())               t.m_attribs.set(ThingAttrBlockProjectile, true);
    if (f.avoid())                 t.m_attribs.set(ThingAttrNotPathable, true);
    if (f.no_movement_animation()) t.m_attribs.set(ThingAttrNoMoveAnimation, true);
    if (f.take())                  t.m_attribs.set(ThingAttrPickupable, true);
    if (f.liquidcontainer())       t.m_attribs.set(ThingAttrFluidContainer, true);
    if (f.hang())                  t.m_attribs.set(ThingAttrHangable, true);

    // hook is a sub-message with a direction enum (south=1, east=2).
    if (f.has_hook() && f.hook().has_direction()) {
        if (f.hook().direction() == HOOK_TYPE_SOUTH)
            t.m_attribs.set(ThingAttrHookSouth, true);
        else if (f.hook().direction() == HOOK_TYPE_EAST)
            t.m_attribs.set(ThingAttrHookEast, true);
    }

    if (f.rotate())                t.m_attribs.set(ThingAttrRotateable, true);

    // light is a sub-message: brightness=intensity, color=color (1 byte each
    // in legacy, but proto uses uint32). Light.pos defaults to {0,0}.
    // Legacy thingtype.cpp:231-237: intensity = U16, color = U16; we mirror.
    if (f.has_light()) {
        Light l;
        l.pos = Point(0, 0);
        l.intensity = static_cast<uint8_t>(f.light().brightness());
        l.color     = static_cast<uint8_t>(f.light().color());
        t.m_attribs.set<Light>(ThingAttrLight, l);
    }

    if (f.dont_hide())             t.m_attribs.set(ThingAttrDontHide, true);
    if (f.translucent())           t.m_attribs.set(ThingAttrTranslucent, true);

    // shift -> displacement Point + flag (legacy thingtype.cpp:220-230).
    if (f.has_shift()) {
        t.m_displacement = Point(
            static_cast<int>(f.shift().has_x() ? f.shift().x() : 0),
            static_cast<int>(f.shift().has_y() ? f.shift().y() : 0));
        t.m_attribs.set(ThingAttrDisplacement, true);
    }

    // height -> elevation U16 + flag (legacy thingtype.cpp:249-253).
    if (f.has_height() && f.height().has_elevation()) {
        t.m_elevation = static_cast<int>(f.height().elevation());
        t.m_attribs.set<uint16>(ThingAttrElevation, static_cast<uint16>(t.m_elevation));
    }

    if (f.lying_object())          t.m_attribs.set(ThingAttrLyingCorpse, true);
    if (f.animate_always())        t.m_attribs.set(ThingAttrAnimateAlways, true);

    // automap.color -> ThingAttrMinimapColor U16 (legacy thingtype.cpp:258).
    if (f.has_automap() && f.automap().has_color())
        t.m_attribs.set<uint16>(ThingAttrMinimapColor, static_cast<uint16>(f.automap().color()));

    // lenshelp.id -> ThingAttrLensHelp U16 (legacy thingtype.cpp:260).
    if (f.has_lenshelp() && f.lenshelp().has_id())
        t.m_attribs.set<uint16>(ThingAttrLensHelp, static_cast<uint16>(f.lenshelp().id()));

    if (f.fullbank())              t.m_attribs.set(ThingAttrFullGround, true);
    // ignore_look -> ThingAttrLook (legacy mapping is "look ignored" via
    // ThingAttrLook; isIgnoreLook() in thingtype.h:254 checks this bit).
    if (f.ignore_look())           t.m_attribs.set(ThingAttrLook, true);

    // clothes.slot -> ThingAttrCloth U16 (legacy thingtype.cpp:259).
    if (f.has_clothes() && f.clothes().has_slot())
        t.m_attribs.set<uint16>(ThingAttrCloth, static_cast<uint16>(f.clothes().slot()));

    // proficiency: weapon proficiency id (15.x weapon mastery). Feeds
    // g_things.getProficiencyThings() used by mods/game_proficiency.
    if (f.has_proficiency() && f.proficiency().has_proficiency_id())
        t.setProficiencyId(static_cast<uint16_t>(f.proficiency().proficiency_id()));

    // weapon_type: WEAPON_TYPE_* enum, same numbering as the gamelib WEAPON_* Lua
    // constants. Replaces the legacy OTB weapon-type lookup on 15.x setups.
    if (f.has_weapon_type())
        t.setWeaponType(static_cast<int>(f.weapon_type()));

    // restrict_to_vocation (field 62) + minimum_level (field 63): the weapon-USE
    // requirements. Unlike the market block below (restrict_to_profession, whose
    // PLAYER_PROFESSION enum has no monk, plus its own minimum_level field 6), these
    // use the VOCATION enum (monk=5, matching gamelib translateWheelVocation) and the
    // real equip-level gate. mods/game_proficiency reads them for its "requirements"
    // warning. VOCATION_ANY (-1) means "no restriction" -> empty list.
    {
        std::vector<uint16> restrictVocations;
        for (int v = 0; v < f.restrict_to_vocation_size(); ++v) {
            const int vocation = static_cast<int>(f.restrict_to_vocation(v));
            if (vocation >= 0)
                restrictVocations.push_back(static_cast<uint16>(vocation));
        }
        t.setRestrictVocations(std::move(restrictVocations));
    }
    if (f.has_minimum_level())
        t.setMinimumLevel(static_cast<uint16>(f.minimum_level()));

    // npcsaledata: NPC trade list (who buys/sells this item and prices). Feeds the
    // cyclopedia "sell to / buy from" panels and Item::getDefaultValue/BuyPrice.
    for (int i = 0; i < f.npcsaledata_size(); ++i) {
        const auto& npc = f.npcsaledata(i);
        ThingType::NpcSaleInfo info;
        info.name      = npc.has_name() ? npc.name() : std::string();
        info.location  = npc.has_location() ? npc.location() : std::string();
        info.salePrice = npc.has_sale_price() ? npc.sale_price() : 0;
        info.buyPrice  = npc.has_buy_price() ? npc.buy_price() : 0;
        info.currencyObjectTypeId = npc.has_currency_object_type_id() ? npc.currency_object_type_id() : 0;
        info.currencyQuestFlagDisplayName = npc.has_currency_quest_flag_display_name() ? npc.currency_quest_flag_display_name() : std::string();
        t.addNpcSaleData(std::move(info));
    }

    // market: build MarketData with name (from Appearance.name) + category,
    // tradeAs, showAs, restrictVocation (first vocation if present),
    // requiredLevel. Legacy thingtype.cpp:239-247.
    if (f.has_market()) {
        const AppearanceFlagMarket& m = f.market();
        MarketData md;
        md.name           = name;
        md.category       = m.has_category() ? static_cast<int>(m.category()) : 0;
        md.tradeAs        = m.has_trade_as_object_id()
                              ? m.trade_as_object_id() // u32: item ids > 65535 must not truncate
                              : 0;
        md.showAs         = m.has_show_as_object_id()
                              ? m.show_as_object_id()
                              : 0;
        // Legacy stores a single restrictVocation U16. Proto sends a repeated
        // list; keep the legacy collapse for the .dat path AND the full list for
        // Lua (mods iterate it: #list / table.contains). PROFESSION_ANY (-1)
        // means "no restriction" -> empty list.
        md.restrictVocation = (m.restrict_to_profession_size() > 0)
                                ? static_cast<uint16>(m.restrict_to_profession(0))
                                : 0;
        for (int v = 0; v < m.restrict_to_profession_size(); ++v) {
            const int profession = static_cast<int>(m.restrict_to_profession(v));
            if (profession >= 0)
                md.restrictVocations.push_back(static_cast<uint16>(profession));
        }
        md.requiredLevel  = m.has_minimum_level()
                              ? static_cast<uint16>(m.minimum_level())
                              : 0;
        t.m_attribs.set<MarketData>(ThingAttrMarket, md);
    }

    if (f.wrap())                  t.m_attribs.set(ThingAttrWrapable, true);
    if (f.unwrap())                t.m_attribs.set(ThingAttrUnwrapable, true);
    if (f.topeffect())             t.m_attribs.set(ThingAttrTopEffect, true);

    // 15.25 item flags consumed by ProtocolGame::getItem (server AddItem schema):
    // these gate optional bytes (decay/charges/podium/wrapkit/classification),
    // so they MUST be loaded or the map/inventory parse desyncs.
    if (f.expire())                t.m_attribs.set(ThingAttrExpire, true);
    if (f.expirestop())            t.m_attribs.set(ThingAttrExpireStop, true);
    if (f.clockexpire())           t.m_attribs.set(ThingAttrClockExpire, true);
    if (f.wearout())               t.m_attribs.set(ThingAttrWearOut, true);
    if (f.wrapkit())               t.m_attribs.set(ThingAttrWrapKit, true);
    if (f.has_upgradeclassification())
        t.setClassification(static_cast<uint16>(f.upgradeclassification().upgrade_classification()));

    // show_off_socket (proto field 46) is how 13+/15.x marks a podium. The server
    // (items.cpp: iType.isPodium = flags().show_off_socket()) serializes an 8-byte
    // outfit/mount/direction/visible block for podium items in AddItem; getItem()
    // only consumes it when isPodium() is true, so without this flag a "podium of
    // vigour" (id 38707) on the ground desynced the whole map slice into
    // "invalid thing id (0)" on walk.
    if (f.show_off_socket())       t.m_attribs.set(ThingAttrPodium, true);

    // ammo-slot equipables; consumed by game_actionbar canEquipItem via Item:isAmmo().
    if (f.ammo())                  t.m_attribs.set(ThingAttrAmmo, true);

    // Proto fields still NOT mapped (no consumer yet in 15.25 client):
    //   default_action, changedtoexpire, corpse, player_corpse,
    //   cyclopediaitem, reportable, reverse_addons_*, skillwheel_gem,
    //   dual_wielding, imbueable. Expose later if a handler needs them.
}

// ----------------------------------------------------------------------------
// FrameGroup -> sprite layout
// ----------------------------------------------------------------------------

void AppearancesLoader::applyFrameGroup(const FrameGroup& fg, ThingCategory category,
                                        ThingType& t, int& totalSpritesCount,
                                        std::vector<FrameGroupLayout>& groupLayouts)
{
    if (!fg.has_sprite_info())
        return;

    const SpriteInfo& si = fg.sprite_info();

    // Legacy thingtype.cpp:300-317: width/height/layers/numPatternX/Y/Z come
    // from the same SpriteInfo fields in protobuf land.
    // max(1,...): an explicit 0 in the protobuf would zero totalSprites below and
    // turn every pattern getter into a division-by-zero divisor at draw time
    const int patternX = si.has_pattern_width()  ? std::max(1, static_cast<int>(si.pattern_width()))  : 1;
    const int patternY = si.has_pattern_height() ? std::max(1, static_cast<int>(si.pattern_height())) : 1;
    const int patternZ = si.has_pattern_depth()  ? std::max(1, static_cast<int>(si.pattern_depth()))  : 1;
    const int layers   = si.has_layers()         ? std::max(1, static_cast<int>(si.layers()))         : 1;

    // m_size is the sprite's SQM footprint (in 32px cells). It MUST come from the
    // owning sprite sheet's "spritetype" (0=32x32→1x1, 1=32x64→1x2, 2=64x32→2x1,
    // 3=64x64→2x2), NOT from bounding_square. bounding_square is only the visible
    // bbox of the artwork; using bsq/spriteSize collapsed every 64x64 sprite to a
    // 1x1 cell, so getTexture stored a 64x64 sprite in a 32x32 atlas cell and the
    // draw path clipped it to a single SQM — exactly the "sprites quebradas / tudo
    // no mesmo SQM" bug. In Tibia's 45° projection a 2x2 sprite anchors at its tile
    // (bottom-right) and extends into the 3 SQMs above/left, which only works when
    // m_size reports the true 2x2 footprint.
    const int spriteSize = g_sprites.getBaseSpriteSize(); // native cell base: footprint is in SQM, must not scale with HD
    int square = si.has_bounding_square() ? static_cast<int>(si.bounding_square()) : 1;
    if (square <= 0)
        square = 1;

    int cellW = 1;
    int cellH = 1;
    if (si.sprite_id_size() > 0) {
        const auto cell = g_sprites.getSpriteCellSize(static_cast<int>(si.sprite_id(0)));
        cellW = std::max(1, cell.first / spriteSize);
        cellH = std::max(1, cell.second / spriteSize);
    } else {
        // No sprites (rare); fall back to the bounding-box heuristic.
        cellW = std::max(1, square / spriteSize);
        cellH = std::max(1, square / spriteSize);
    }
    t.m_size = Size(cellW, cellH);
    t.m_realSize = square;
    t.m_exactSize = std::min<int>(t.m_realSize, std::max<int>(cellW * spriteSize, cellH * spriteSize));

    t.m_layers      = layers;
    t.m_numPatternX = patternX;
    t.m_numPatternY = patternY;
    t.m_numPatternZ = patternZ;

    // Phase count comes from the animation's sprite_phase array (legacy
    // thingtype.cpp:319 reads it as U8). Without animation we assume 1 phase.
    int groupPhases = 1;
    if (si.has_animation()) {
        const SpriteAnimation& sa = si.animation();
        groupPhases = sa.sprite_phase_size();
        if (groupPhases < 1)
            groupPhases = 1;

        // Mirror legacy thingtype.cpp:322-334: build per-group Animator and
        // place into m_animator (moving) vs m_idleAnimator (idle) based on
        // fixed_frame_group. For non-outfit appearances (items, effects,
        // missiles), use the FrameGroupDefault slot (m_animator).
        if (groupPhases > 1) {
            AnimatorPtr animator = buildAnimator(sa, groupPhases);
            if (animator) {
                if (category == ThingCategoryCreature && fg.has_fixed_frame_group()) {
                    switch (fg.fixed_frame_group()) {
                        case FIXED_FRAME_GROUP_OUTFIT_IDLE:
                            t.m_idleAnimator = animator;
                            break;
                        case FIXED_FRAME_GROUP_OUTFIT_MOVING:
                            t.m_animator = animator;
                            break;
                        default:
                            t.m_animator = animator;
                            break;
                    }
                } else {
                    t.m_animator = animator;
                }
            }
        }
    }
    t.m_animationPhases += groupPhases;

    // Flat sprite-index vector indexed by getSpriteIndex(). For proto
    // (Tibia 12+), one sprite covers the entire bounding_square — drop
    // the m_size.area() factor that the legacy .dat reader needed.
    // koliseu-client thingtype.cpp uses the same formula for proto:
    //   total = layers * patternX * patternY * patternZ * phases
    const int totalSprites = t.m_layers * t.m_numPatternX
                           * t.m_numPatternY * t.m_numPatternZ * groupPhases;

    // Record this group's layout (spriteOffset = start of its block) so
    // buildThingType can re-layout when groups diverge on dims.
    groupLayouts.push_back({ layers, patternX, patternY, patternZ,
                             groupPhases, totalSpritesCount, cellW, cellH, square });

    const int newSize = totalSpritesCount + totalSprites;
    t.m_spritesIndex.resize(newSize);

    // The proto's sprite_id[] is a flat U32 list in the same order the legacy
    // reader expects (row-major over w, h, l, x, y, z, a — see
    // ThingType::getSpriteIndex thingtype.cpp:862).
    const int available = si.sprite_id_size();
    for (int i = 0; i < totalSprites; ++i) {
        const int dst = totalSpritesCount + i;
        t.m_spritesIndex[dst] = (i < available) ? static_cast<int>(si.sprite_id(i)) : 0;
    }
    totalSpritesCount = newSize;
}

AnimatorPtr AppearancesLoader::buildAnimator(const SpriteAnimation& sa, int phases)
{
    if (phases <= 0)
        return nullptr;

    auto animator = std::make_shared<Animator>();
    animator->m_animationPhases = phases;
    // Legacy thingtype.cpp / animator.cpp:49 reads `m_async = fin->getU8() == 0;`
    // i.e. the U8 0 means async. In protobuf, `synchronized=true` is the
    // explicit synchronous case, so async = !synchronized.
    animator->m_async = sa.has_synchronized() ? !sa.synchronized() : true;

    // loop_count + loop_type: legacy stores loop_count<0 as pingpong (see
    // animator.cpp:116-119 `if (m_loopCount < 0) getPingPongPhase()`). The
    // proto separates them; collapse back to legacy convention.
    int loopCount = sa.has_loop_count() ? static_cast<int>(sa.loop_count()) : 0;
    if (sa.has_loop_type() && sa.loop_type() == ANIMATION_LOOP_TYPE_PINGPONG)
        loopCount = -1;
    animator->m_loopCount = loopCount;

    // default_start_phase: legacy reads int8 (animator.cpp:51). The proto's
    // random_start_phase=true overrides start phase to -1, matching the legacy
    // sentinel that triggers a random pick in Animator::getStartPhase().
    int startPhase = sa.has_default_start_phase() ? static_cast<int>(sa.default_start_phase()) : 0;
    if (sa.has_random_start_phase() && sa.random_start_phase())
        startPhase = -1;
    animator->m_startPhase = startPhase;

    animator->m_phaseDurations->clear();
    animator->m_phaseDurations->reserve(phases);
    for (int i = 0; i < phases; ++i) {
        const SpritePhase& p = sa.sprite_phase(i);
        const int minimum = static_cast<int>(p.has_duration_min() ? p.duration_min() : 0);
        const int maximum = static_cast<int>(p.has_duration_max() ? p.duration_max() : 0);
        // Legacy animator.cpp:56 stores (min, max - min) — the second element
        // is the random *range*, not the absolute max.
        animator->m_phaseDurations->emplace_back(minimum, std::max(0, maximum - minimum));
    }

    animator->m_phase = animator->getStartPhase();
    return animator;
}
