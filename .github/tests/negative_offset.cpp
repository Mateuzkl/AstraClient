#include "src/client/negativeoffset.h"

#include <cassert>
#include <cstdint>
#include <string>

namespace
{
struct FakeStream
{
    int16_t signedValue = 0;
    uint16_t unsignedValue = 0;
    int signedReads = 0;
    int unsignedReads = 0;

    int16_t get16()
    {
        ++signedReads;
        return signedValue;
    }

    uint16_t getU16()
    {
        ++unsignedReads;
        return unsignedValue;
    }
};

struct FakeLightView
{
    int registrations = 0;
    int lastX = 0;
    int lastY = 0;

    void addLight(const int x, const int y)
    {
        ++registrations;
        lastX = x;
        lastY = y;
    }
};
}

int main()
{
    assert(!NegativeOffset::hasNegativeDisplacement(0, 0));
    assert(!NegativeOffset::hasNegativeDisplacement(8, 8));
    assert(!NegativeOffset::hasNegativeDisplacement(16, 4));
    assert(NegativeOffset::hasNegativeDisplacement(-1, 8));
    assert(NegativeOffset::hasNegativeDisplacement(8, -1));
    assert(NegativeOffset::hasNegativeDisplacement(-32, -16));

    assert(!NegativeOffset::usesNegativeDisplacement(false, false));
    assert(NegativeOffset::usesNegativeDisplacement(true, false));
    assert(NegativeOffset::usesNegativeDisplacement(false, true));
    assert(NegativeOffset::usesNegativeDisplacement(true, true));

    assert(!NegativeOffset::supportsSerializedDisplacement(754));
    assert(NegativeOffset::supportsSerializedDisplacement(755));
    assert(NegativeOffset::supportsSerializedDisplacement(860));

    assert(!NegativeOffset::useGroundFirstPass(false, false));
    assert(NegativeOffset::useGroundFirstPass(true, false));
    assert(NegativeOffset::useGroundFirstPass(false, true));

    assert(NegativeOffset::isFlatGround(true, 1, 1, false));
    assert(!NegativeOffset::isFlatGround(true, 1, 1, true));
    assert(!NegativeOffset::isFlatGround(true, 2, 2, false));
    assert(!NegativeOffset::isFlatGround(true, 3, 3, false));
    assert(!NegativeOffset::isFlatGround(true, 4, 4, false));
    assert(!NegativeOffset::isFlatGround(false, 1, 1, false));

    assert(NegativeOffset::shiftFileOffset(0, 10, 5, false) == 0);
    assert(NegativeOffset::shiftFileOffset(10, 10, 5, false) == 10);
    assert(NegativeOffset::shiftFileOffset(10, 10, 5, true) == 15);
    assert(NegativeOffset::shiftFileOffset(11, 10, 5, false) == 16);
    assert(NegativeOffset::shiftFileOffset(16, 10, -5, false) == 11);

    FakeStream negative{ -14, static_cast<uint16_t>(0xfff2) };
    assert(NegativeOffset::readDisplacement(negative, true) == -14);
    assert(negative.signedReads == 1);
    assert(negative.unsignedReads == 0);

    FakeStream legacy{ -14, static_cast<uint16_t>(0xfff2) };
    assert(NegativeOffset::readDisplacement(legacy, false) == 65522);
    assert(legacy.signedReads == 0);
    assert(legacy.unsignedReads == 1);

    FakeStream positiveSigned{ 14, 14 };
    FakeStream positiveUnsigned{ 14, 14 };
    assert(NegativeOffset::readDisplacement(positiveSigned, true) == 14);
    assert(NegativeOffset::readDisplacement(positiveUnsigned, false) == 14);

    FakeLightView lights;
    auto* baseView = NegativeOffset::baseCreatureLightView(&lights, true, true);
    assert(baseView == nullptr);

    // Creature::draw remains responsible for the one logical base light.
    lights.addLight(320, 240);
    assert(lights.registrations == 1);
    assert(lights.lastX == 320 && lights.lastY == 240);

    // Non-creature artwork and normal rendering retain their draw-time light view.
    assert(NegativeOffset::baseCreatureLightView(&lights, true, false) == &lights);
    assert(NegativeOffset::baseCreatureLightView(&lights, false, true) == &lights);

    std::string datBytes(12, static_cast<char>(0x5a));
    assert(NegativeOffset::patchDisplacement(datBytes, 4, -14, 11));
    assert(static_cast<uint8_t>(datBytes[4]) == 0xf2);
    assert(static_cast<uint8_t>(datBytes[5]) == 0xff);
    assert(static_cast<uint8_t>(datBytes[6]) == 0x0b);
    assert(static_cast<uint8_t>(datBytes[7]) == 0x00);
    for(std::size_t index = 0; index < datBytes.size(); ++index) {
        if(index < 4 || index > 7)
            assert(static_cast<uint8_t>(datBytes[index]) == 0x5a);
    }

    const std::string unchanged = datBytes;
    assert(!NegativeOffset::patchDisplacement(datBytes, 0, 1, 2));
    assert(!NegativeOffset::patchDisplacement(datBytes, datBytes.size() - 3, 1, 2));
    assert(datBytes == unchanged);

    std::string attributes{ static_cast<char>(0x15), static_cast<char>(0xff), 0x01 };
    assert(NegativeOffset::insertDisplacement(attributes, 1, 0x18, -6, 11));
    assert(attributes.size() == 8);
    assert(static_cast<uint8_t>(attributes[0]) == 0x15);
    assert(static_cast<uint8_t>(attributes[1]) == 0x18);
    assert(static_cast<uint8_t>(attributes[2]) == 0xfa);
    assert(static_cast<uint8_t>(attributes[3]) == 0xff);
    assert(static_cast<uint8_t>(attributes[4]) == 0x0b);
    assert(static_cast<uint8_t>(attributes[5]) == 0x00);
    assert(static_cast<uint8_t>(attributes[6]) == 0xff);
    assert(static_cast<uint8_t>(attributes[7]) == 0x01);

    assert(NegativeOffset::removeDisplacement(attributes, 2));
    assert(attributes.size() == 3);
    assert(static_cast<uint8_t>(attributes[0]) == 0x15);
    assert(static_cast<uint8_t>(attributes[1]) == 0xff);
    assert(static_cast<uint8_t>(attributes[2]) == 0x01);

    const std::string attributesWithoutDisplacement = attributes;
    assert(!NegativeOffset::removeDisplacement(attributes, 0));
    assert(!NegativeOffset::removeDisplacement(attributes, attributes.size()));
    assert(attributes == attributesWithoutDisplacement);

    // Insert/remove in entry A must keep the recorded offset for entry B valid.
    std::string twoEntries{static_cast<char>(0x15),
                           static_cast<char>(0xff),
                           static_cast<char>(0x18),
                           0x01,
                           0x00,
                           0x02,
                           0x00,
                           static_cast<char>(0xff)};
    uint32_t secondValueOffset = 3;
    assert(NegativeOffset::insertDisplacement(twoEntries, 1, 0x18, -7, 9));
    secondValueOffset =
        NegativeOffset::shiftFileOffset(secondValueOffset, 1, 5, false);
    assert(secondValueOffset == 8);
    assert(NegativeOffset::patchDisplacement(twoEntries, secondValueOffset, 21,
                                             -22));
    assert(static_cast<uint8_t>(twoEntries[8]) == 0x15);
    assert(static_cast<uint8_t>(twoEntries[9]) == 0x00);
    assert(static_cast<uint8_t>(twoEntries[10]) == 0xea);
    assert(static_cast<uint8_t>(twoEntries[11]) == 0xff);

    assert(NegativeOffset::removeDisplacement(twoEntries, 2));
    secondValueOffset =
        NegativeOffset::shiftFileOffset(secondValueOffset, 1, -5, false);
    assert(secondValueOffset == 3);
    assert(NegativeOffset::patchDisplacement(twoEntries, secondValueOffset, -31,
                                             32));
    assert(twoEntries.size() == 8);
    assert(static_cast<uint8_t>(twoEntries[3]) == 0xe1);
    assert(static_cast<uint8_t>(twoEntries[4]) == 0xff);
    assert(static_cast<uint8_t>(twoEntries[5]) == 0x20);
    assert(static_cast<uint8_t>(twoEntries[6]) == 0x00);
}
