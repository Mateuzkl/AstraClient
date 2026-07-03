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

#ifndef CREATURES_H
#define CREATURES_H

#include "declarations.h"
#include <framework/luaengine/luaobject.h>
#include "outfit.h"

#include <map>
#include <tuple>

enum CreatureAttr : uint8
{
    CreatureAttrPosition  = 0,
    CreatureAttrName      = 1,
    CreatureAttrOutfit    = 2,
    CreatureAttrSpawnTime = 3,
    CreatureAttrDir       = 4,
    CreatureAttrRace      = 5,
    CreatureAttrRaceId    = 6,
    CreatureAttrIsBoss    = 7
};

enum CreatureRace : uint8
{
    CreatureRaceNpc     = 0,
    CreatureRaceMonster = 1
};

enum SpawnAttr : uint8
{
    SpawnAttrRadius  = 0,
    SpawnAttrCenter  = 1,
};

class Spawn : public LuaObject
{
public:
    Spawn() = default;
    Spawn(int32 radius) { setRadius(radius); }

    void setRadius(int32 r) { m_attribs.set(SpawnAttrRadius, r) ;}
    int32 getRadius() { return m_attribs.get<int32>(SpawnAttrRadius); }

    void setCenterPos(const Position& pos) { m_attribs.set(SpawnAttrCenter, pos); }
    Position getCenterPos() { return m_attribs.get<Position>(SpawnAttrCenter); }

    std::vector<CreatureTypePtr> getCreatures();
    void addCreature(const Position& placePos, const CreatureTypePtr& cType);
    void removeCreature(const Position& pos);
    void clear() { m_creatures.clear(); }

protected:
    void load(TiXmlElement* node);
    void save(TiXmlElement* node);

private:
    stdext::dynamic_storage<uint8> m_attribs;
    std::unordered_map<Position, CreatureTypePtr, PositionHasher> m_creatures;
    friend class CreatureManager;
};

class CreatureType : public LuaObject
{
public:
    CreatureType() = default;
    CreatureType(const std::string& name) { setName(name); }

    void setSpawnTime(int32 spawnTime) { m_attribs.set(CreatureAttrSpawnTime, spawnTime); }
    int32 getSpawnTime() { return m_attribs.get<int32>(CreatureAttrSpawnTime); }

    void setName(const std::string& name) { m_attribs.set(CreatureAttrName, name); }
    std::string getName() { return m_attribs.get<std::string>(CreatureAttrName); }

    void setOutfit(const Outfit& o) { m_attribs.set(CreatureAttrOutfit, o); }
    Outfit getOutfit() { return m_attribs.get<Outfit>(CreatureAttrOutfit); }

    void setDirection(Otc::Direction dir) { m_attribs.set(CreatureAttrDir, dir); }
    Otc::Direction getDirection() { return m_attribs.get<Otc::Direction>(CreatureAttrDir); }

    void setRace(CreatureRace race) { m_attribs.set(CreatureAttrRace, race); }
    CreatureRace getRace() { return m_attribs.get<CreatureRace>(CreatureAttrRace); }

    // bestiary race id from staticdata.dat; 0 for legacy XML-loaded creatures
    void setRaceId(int32 raceId) { m_attribs.set(CreatureAttrRaceId, raceId); }
    int32 getRaceId() { return m_attribs.get<int32>(CreatureAttrRaceId); }

    // true when this entry came from staticdata's separate "bosses" list; false for
    // regular monsters and legacy XML creatures. Surfaced as the appended 9th field
    // of the getMonsterList tuple (append-only, so [1..8] consumers are unaffected).
    void setBoss(bool boss) { m_attribs.set(CreatureAttrIsBoss, boss); }
    bool isBoss() { return m_attribs.get<bool>(CreatureAttrIsBoss); }

    CreaturePtr cast();

private:
    stdext::dynamic_storage<uint8> m_attribs;
};

// staticdata.dat achievement entry. Plain struct (no protobuf types) so
// staticdata.pb.h stays confined to creatures.cpp — see the include-cycle
// note on ThingTypeManager::getStaticDataPath.
struct StaticAchievement
{
    int id = 0;
    std::string name;
    std::string description;
    int grade = 0;
};

class CreatureManager
{
public:
    CreatureManager();
    void clear() { m_creatures.clear(); }
    void clearSpawns();
    void terminate();

    void loadMonsters(const std::string& file);
    // populate m_creatures from the Tibia 12+ staticdata protobuf (monsters +
    // bosses with their real bestiary race ids); used by the modern asset boot
    bool loadStaticData(const std::string& file);
    void loadSingleCreature(const std::string& file);
    void loadNpcs(const std::string& folder);
    void loadCreatureBuffer(const std::string& buffer);
    void loadSpawns(const std::string& fileName);
    void saveSpawns(const std::string& fileName);

    const CreatureTypePtr& getCreatureByName(std::string name);
    const CreatureTypePtr& getCreatureByLook(int look);

    std::vector<SpawnPtr> getSpawns();
    SpawnPtr getSpawn(const Position& centerPos);
    SpawnPtr getSpawnForPlacePos(const Position& pos);
    SpawnPtr addSpawn(const Position& centerPos, int radius);
    void deleteSpawn(const SpawnPtr& spawn);

    bool isLoaded() { return m_loaded; }
    bool isSpawnLoaded() { return m_spawnLoaded; }

    const std::vector<CreatureTypePtr>& getCreatures() { return m_creatures; }
    // tuple layout (Lua-1-indexed): [1]=name, [2]=lookType, [3]=lookTypeEx,
    // [4]=head, [5]=body, [6]=legs, [7]=feet, [8]=addons, [9]=isBoss (0/1).
    // The 9th field is append-only: existing consumers reading [1..8] keep working.
    std::map<int, std::tuple<std::string, int, int, int, int, int, int, int, int>> getMonsterList();
    // staticdata achievements keyed by id; cyclopedia 0xDA/5 sends only
    // id+timestamp for non-secret entries, the rest is resolved from here
    std::map<int, StaticAchievement> getAchievementList() { return m_achievements; }

protected:
    void internalLoadCreatureBuffer(TiXmlElement* elem, const CreatureTypePtr& m);

private:
    std::vector<CreatureTypePtr> m_creatures;
    std::map<int, StaticAchievement> m_achievements;
    std::unordered_map<Position, SpawnPtr, PositionHasher> m_spawns;
    stdext::boolean<false> m_loaded, m_spawnLoaded;
    CreatureTypePtr m_nullCreature;
};

extern CreatureManager g_creatures;

#endif
