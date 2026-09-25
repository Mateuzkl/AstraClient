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
    assert(!NegativeOffset::useGroundFirstPass(false, false));
    assert(NegativeOffset::useGroundFirstPass(true, false));
    assert(NegativeOffset::useGroundFirstPass(false, true));

    assert(NegativeOffset::isFlatGround(true, 1, 1, false));
    assert(!NegativeOffset::isFlatGround(true, 1, 1, true));
    assert(!NegativeOffset::isFlatGround(true, 2, 2, false));
    assert(!NegativeOffset::isFlatGround(true, 3, 3, false));
    assert(!NegativeOffset::isFlatGround(true, 4, 4, false));
    assert(!NegativeOffset::isFlatGround(false, 1, 1, false));

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
}
