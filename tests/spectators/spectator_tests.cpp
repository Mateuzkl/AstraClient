// Native, asset-free regression/benchmark harness. No sockets, login or window.
#include <framework/global.h>
#include <new>
#include <stdexcept>
#include <framework/luaengine/luaobject.h>
#define private public
#include <client/thingtype.h>
#undef private
#include <framework/graphics/bitmapfont.h>
#include <client/mapview.h>

// Fixture access only, following upstream tests. Standard headers are already
// loaded above; no production friendship or Lua API is added.
#define private public
#include <client/map.h>
#include <client/tile.h>
#include <client/game.h>
#include <client/gameconfig.h>
#undef private

// Exercise the actual anonymous cleanup helper, not a reimplemented algorithm.
// Test build files exclude map.cpp as a separate translation unit.
#include "../../src/client/map.cpp"

namespace {
thread_local bool countAllocations = false;
thread_local size_t allocationCount = 0;
size_t checks = 0;
volatile size_t resultSink = 0;
void check(bool value, const char* expression, int line)
{
    ++checks;
    if (!value) throw std::runtime_error(std::string(expression) + " at line " + std::to_string(line));
}
#define CHECK(...) check((__VA_ARGS__), #__VA_ARGS__, __LINE__)

ThingTypePtr fixtureType(int attr = -1)
{
    auto type = std::make_shared<ThingType>();
    type->m_null = false;
    type->m_size = Size(1, 1);
    if (attr >= 0) type->m_attribs.set<uint16>(attr, 0);
    return type;
}

class TestCreature final : public Creature
{
public:
    TestCreature() : type(fixtureType()) { m_removed = false; }
    ThingType* rawGetThingType() override { return type.get(); }
    const ThingTypePtr& getThingType() override { return type; }
    void onPositionChange(const Position&, const Position&) override { }
    void onAppear() override { m_removed = false; }
    void onDisappear() override { m_removed = true; }
    void setFixtureOutfitId(int id) { m_outfit.setId(id); }
    ThingTypePtr type;
};

class TestItem final : public Item
{
public:
    explicit TestItem(int attr = -1) : type(fixtureType(attr)) { }
    ThingType* rawGetThingType() override { return type.get(); }
    const ThingTypePtr& getThingType() override { return type; }
    ThingTypePtr type;
};

class TestEffect final : public Effect
{
public:
    ThingType* rawGetThingType() override { return type.get(); }
    const ThingTypePtr& getThingType() override { return type; }
    void onAppear() override { }
    void onDisappear() override { }
    ThingTypePtr type = fixtureType();
};

CreaturePtr creature(uint32 id)
{
    auto c = std::make_shared<TestCreature>();
    c->setId(id);
    return c;
}
ThingPtr item(int attr = -1) { return std::make_shared<TestItem>(attr); }

void reset(int z = 7)
{
    g_map.m_knownCreatures.clear();
    g_map.m_tileBlocks.clear();
    g_map.init();
    g_map.m_centralPosition = Position(1000, 1000, z);
    g_game.m_clientVersion = 860;
    g_game.enableFeature(Otc::GameNewCreatureStacking);
}

std::vector<CreaturePtr> oldSpectators(const Position& center, bool multi, int minX, int maxX, int minY, int maxY)
{
    // Exact pre-port Astra traversal used as the comparison/benchmark baseline.
    std::vector<CreaturePtr> out;
    const int firstZ = multi ? g_map.getFirstAwareFloor() : center.z;
    const int lastZ = multi ? g_map.getLastAwareFloor() : center.z;
    for (int z = firstZ; z <= lastZ; ++z)
        for (int y = center.y - minY; y <= center.y + maxY; ++y)
            for (int x = center.x - minX; x <= center.x + maxX; ++x) {
                const auto tile = g_map.getTile(Position(x, y, z));
                if (!tile) continue;
                auto temporary = tile->getCreatures();
                out.insert(out.end(), temporary.rbegin(), temporary.rend());
            }
    return out;
}

void verifyTile(Tile& tile)
{
    std::vector<CreaturePtr> forward;
    int first = -1, last = -1;
    for (size_t i = 0; i < tile.m_things.size(); ++i)
        if (tile.m_things[i]->isCreature()) {
            if (first == -1) first = static_cast<int>(i);
            last = static_cast<int>(i);
            forward.push_back(tile.m_things[i]->static_self_cast<Creature>());
        }
    CHECK(tile.m_firstCreatureIndex == first);
    CHECK(tile.m_lastCreatureIndex == last);
    CHECK(tile.hasCreatures() == !forward.empty());
    CHECK(tile.hasCreature() == !forward.empty());
    CHECK(tile.getCreatures() == forward);
    std::vector<CreaturePtr> out{creature(900000)};
    const auto sentinel = out.front();
    tile.appendSpectators(out);
    CHECK(out.front() == sentinel);
    CHECK(std::vector<CreaturePtr>(out.begin() + 1, out.end()) == std::vector<CreaturePtr>(forward.rbegin(), forward.rend()));
}

void tileMutations()
{
    reset();
    Tile tile(Position(1000, 1000, 7));
    verifyTile(tile);
    tile.addThing(nullptr, 0);
    CHECK(!tile.removeThing(nullptr));
    const auto a = creature(1), b = creature(2), c = creature(3);
    tile.addThing(item(ThingAttrGround), -1);
    tile.addThing(a, -1);
    tile.addThing(b, 255);
    tile.addThing(item(), 1);
    tile.addThing(c, 2);
    tile.addThing(item(), 100);
    verifyTile(tile);
    const auto effect = std::make_shared<TestEffect>();
    tile.addThing(effect, -1); verifyTile(tile);
    CHECK(tile.removeThing(effect)); verifyTile(tile);
    CHECK(tile.removeThing(tile.getThing(1))); verifyTile(tile);
    CHECK(tile.removeThing(b)); verifyTile(tile);
    CHECK(tile.removeThing(a)); verifyTile(tile);
    CHECK(tile.removeThing(c)); verifyTile(tile);
    tile.clean(); verifyTile(tile);
    std::mt19937 rng(1319);
    for (int i = 0; i < 5000; ++i) {
        if (tile.m_things.empty() || (rng() % 2 == 0 && tile.m_things.size() < 80))
            tile.addThing(rng() % 2 ? creature(100 + i) : item(), static_cast<int>(rng() % (tile.m_things.size() + 1)));
        else
            CHECK(tile.removeThing(tile.m_things[rng() % tile.m_things.size()]));
        verifyTile(tile);
    }
    tile.clean(); verifyTile(tile);
    // Stack trimming recursively removes a thing and must update the span too.
    g_game.disableFeature(Otc::GameNewCreatureStacking);
    for (int i = 0; i < 30; ++i) { tile.addThing(creature(20000 + i), -1); verifyTile(tile); }
    CHECK(tile.m_things.size() == Tile::MAX_THINGS);
    tile.clean();
    for (int version : {853, 860}) {
        g_game.m_clientVersion = version;
        tile.addThing(a, -1); tile.addThing(b, -1);
        CHECK(tile.getCreatures() == (version >= 854 ? std::vector<CreaturePtr>{a,b} : std::vector<CreaturePtr>{b,a}));
        verifyTile(tile); tile.clean(); verifyTile(tile);
    }
}

void traversal()
{
    for (int floor : {0, 7, 8, 14, 15}) {
        reset(floor);
        const Position center(1000, 1000, floor);
        uint32 id = 1;
        for (int z = 0; z <= 15; ++z)
            for (int y = 998; y <= 1002; ++y)
                for (int x = 997; x <= 1003; ++x) {
                    if ((x + y) % 3 == 0) continue; // missing tiles
                    const auto tile = g_map.getOrCreateTile(Position(x, y, z));
                    tile->addThing(item(), -1); // populated but creature-free tiles
                    if ((x + y) % 2 == 0) continue;
                    for (int n = 0; n < 2; ++n) { const auto c = creature(id++); tile->addThing(c, -1); g_map.addCreature(c); }
                }
        for (bool multi : {false, true})
            for (const auto& ranges : {std::array<int,4>{0,0,0,0}, {2,2,1,1}, {3,1,0,2}}) {
                const auto expected = oldSpectators(center, multi, ranges[0], ranges[1], ranges[2], ranges[3]);
                const auto actual = g_map.getSpectatorsInRangeEx(center, multi, ranges[0], ranges[1], ranges[2], ranges[3]);
                CHECK(actual == expected); // Ordered pointers, not counts or ID sets.
                CHECK(actual == g_map.getSpectatorsInRangeEx(center, multi, ranges[0], ranges[1], ranges[2], ranges[3]));
            }
    }
    // Multi-floor bounds belong to the map's aware range, even when the query
    // center is above or below it. Unsigned margins would wrap negative gaps.
    for (int floor : {0, 7, 8, 14, 15}) {
        reset(floor);
        std::vector<CreaturePtr> perFloor;
        for (int z = 0; z <= 15; ++z) {
            const auto c = creature(z + 1);
            g_map.getOrCreateTile(Position(1000, 1000, z))->addThing(c, -1);
            g_map.addCreature(c);
            perFloor.push_back(c);
        }
        const std::vector<CreaturePtr> expected(perFloor.begin() + g_map.getFirstAwareFloor(),
                                                perFloor.begin() + g_map.getLastAwareFloor() + 1);
        for (int z = 0; z <= 15; ++z) {
            const Position center(1000, 1000, z);
            CHECK(g_map.getSpectatorsInRangeEx(center, true, 0,0,0,0) == expected);
            CHECK(g_map.getSpectatorsInRangeEx(center, true, 0,0,0,0) == oldSpectators(center, true, 0,0,0,0));
            CHECK(g_map.getSpectatorsInRangeEx(center, false, 0,0,0,0) == std::vector<CreaturePtr>({perFloor[z]}));
        }
    }
    reset();
    CHECK(g_map.getSpectatorsInRangeEx(Position(0,0,7), false, 1,1,1,1).empty());
    CHECK(g_map.getSpectatorsInRangeEx(Position(65535,65535,15), false, 1,1,1,1).empty());
}

void duplicatesAndWalking()
{
    reset();
    const auto left = g_map.getOrCreateTile(Position(999,1000,7));
    const auto right = g_map.getOrCreateTile(Position(1000,1000,7));
    const auto first = creature(10), duplicateInstance = creature(10), other = creature(11), walking = creature(12);
    left->addThing(first, -1);
    right->addThing(first, -1);
    right->addThing(duplicateInstance, -1);
    right->addThing(other, -1);
    left->addWalkingCreature(first);
    right->addWalkingCreature(walking);
    CHECK(g_map.getSpectatorsInRangeEx(Position(1000,1000,7), false, 1,0,0,0) == std::vector<CreaturePtr>({first, other}));
    CHECK(right->hasCreature());
    verifyTile(*right);
    CHECK(right->removeThing(first));
    CHECK(right->removeThing(duplicateInstance));
    CHECK(right->removeThing(other));
    CHECK(!right->hasCreatures()); // walking-only tile is not a stack spectator
    CHECK(g_map.getSpectatorsInRangeEx(Position(1000,1000,7), false, 0,0,0,0).empty());
    right->addThing(other, -1); left->removeThing(first);
    CHECK(g_map.getSpectatorsInRangeEx(Position(1000,1000,7), false, 1,0,0,0) == std::vector<CreaturePtr>({other}));
    std::vector<CreaturePtr> out{first, nullptr, duplicateInstance, other, nullptr};
    std::unordered_set<uint32_t> seen{10};
    cleanNewSpectators(out, seen, 1);
    CHECK(out == std::vector<CreaturePtr>({first, other}));
}

void customSystems()
{
    reset();
    const auto tile = g_map.getOrCreateTile(Position(1000,1000,7));
    tile->addThing(item(ThingAttrGround), -1);
    const auto corpse = std::make_shared<TestItem>(ThingAttrLyingCorpse);
    corpse->setLootHighlight(true);
    tile->addThing(corpse, -1);
    CHECK(tile->m_hasLootHighlightItem);
    const auto c = std::make_shared<TestCreature>();
    g_game.enableFeature(Otc::GameNegativeOffset);
    c->setId(1); CHECK(c->type->setDisplacement(Point(-16,-8)));
    c->setFixtureOutfitId(1);
    const auto oldTypes = g_things.m_thingTypes[ThingCategoryCreature];
    g_things.m_thingTypes[ThingCategoryCreature].resize(2);
    g_things.m_thingTypes[ThingCategoryCreature][1] = c->type;
    tile->addThing(c, -1);
    CHECK(tile->hasNegativeDisplacementCreature());
    CHECK(!tile->isWalkable());
    CHECK(tile->getTopCreature() == c);
    CHECK(g_map.getSpectatorsInRangeEx(Position(1000,1000,7), false, 0,0,0,0) == std::vector<CreaturePtr>({c}));
    CHECK(tile->removeThing(c));
    CHECK(!tile->hasNegativeDisplacementCreature());
    CHECK(tile->isWalkable());
    CHECK(tile->m_hasLootHighlightItem);
    tile->removeThing(corpse);
    CHECK(!tile->m_hasLootHighlightItem);
    tile->clean(); verifyTile(*tile);
    g_things.m_thingTypes[ThingCategoryCreature] = oldTypes;
}

void benchmark()
{
    std::cout << "dataset,multi,known,visible,algorithm,median_us,p95_us,calls_per_s,allocations_per_call\n";
    for (const auto& scene : {std::pair<const char*,int>{"empty",0}, {"tiny",3}, {"normal",40}, {"dense",400}, {"tiny-large-known",3}})
        for (bool multi : {false, true}) {
            reset(); const Position center(1000,1000,7);
            const int known = std::string(scene.first) == "tiny-large-known" ? 10000 : scene.second;
            for (int i = 0; i < known; ++i) {
                const auto c = creature(i + 1); g_map.addCreature(c);
                if (i >= scene.second) continue;
                const int z = multi ? 7 - i % 8 : 7;
                const auto tile = g_map.getOrCreateTile(Position(992 + (i / 4) % 18, 994 + (i / 72) % 14, z));
                tile->addThing(item(), -1); tile->addThing(c, -1);
            }
            for (bool optimized : {false,true}) {
                const auto run = [&] { return optimized ? g_map.getSpectatorsInRangeEx(center,multi,8,9,6,7) : oldSpectators(center,multi,8,9,6,7); };
                CHECK(run().size() == static_cast<size_t>(scene.second));
                for (int i = 0; i < 100; ++i) resultSink = run().size();
                std::vector<double> times; times.reserve(1001);
                allocationCount = 0;
                for (int i = 0; i < 1001; ++i) {
                    const auto start = std::chrono::steady_clock::now();
                    countAllocations = true;
                    { const auto result = run(); resultSink = result.size(); }
                    countAllocations = false;
                    times.push_back(std::chrono::duration<double,std::micro>(std::chrono::steady_clock::now() - start).count());
                }
                std::sort(times.begin(), times.end());
                std::cout << scene.first << ',' << multi << ',' << known << ',' << scene.second << ',' << (optimized ? "mehah" : "baseline") << ','
                    << times[500] << ',' << times[950] << ',' << 1000000.0/times[500] << ',' << static_cast<double>(allocationCount)/1001 << '\n';
            }
        }
}
}

void* operator new(std::size_t size)
{
    if (countAllocations) ++allocationCount;
    if (void* p = std::malloc(size ? size : 1)) return p;
    throw std::bad_alloc();
}
void* operator new[](std::size_t size) { return ::operator new(size); }
void operator delete(void* p) noexcept { std::free(p); }
void operator delete[](void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }
void operator delete[](void* p, std::size_t) noexcept { std::free(p); }

int main(int argc, char** argv)
{
    // A named empty font avoids asset lookups; no graphics context is created.
    g_fonts.m_fonts.push_back(std::make_shared<BitmapFont>("verdana-11px-rounded"));
    try {
        tileMutations(); traversal(); duplicatesAndWalking(); customSystems();
        std::cout << "PASS: 4 native regression groups, " << checks << " ordered/state checks\n";
        if (argc > 1 && std::string(argv[1]) == "--benchmark") benchmark();
        reset();
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "FAIL: " << e.what() << '\n';
        return 1;
    }
}
