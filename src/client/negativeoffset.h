#ifndef NEGATIVEOFFSET_H
#define NEGATIVEOFFSET_H

#include <cstdint>
#include <string>

namespace NegativeOffset
{
inline bool hasNegativeDisplacement(const int x, const int y)
{
    return x < 0 || y < 0;
}

inline bool usesNegativeDisplacement(const bool outfitNegative, const bool mountNegative)
{
    return outfitNegative || mountNegative;
}

inline bool supportsSerializedDisplacement(const int clientVersion)
{
    return clientVersion >= 755;
}

inline bool useGroundFirstPass(const bool mapDrawGroundFirst, const bool negativeOffsets)
{
    return mapDrawGroundFirst || negativeOffsets;
}

inline bool isFlatGround(const bool ground, const int width, const int height, const bool displaced)
{
    return ground && width == 1 && height == 1 && !displaced;
}

inline uint32_t shiftFileOffset(
    const uint32_t offset, const std::size_t changedOffset, const int amount, const bool inclusive)
{
    if(offset == 0 || (inclusive ? offset < changedOffset : offset <= changedOffset))
        return offset;

    const int64_t shifted = static_cast<int64_t>(offset) + amount;
    return shifted > 0 ? static_cast<uint32_t>(shifted) : 0;
}

template <typename Stream>
int32_t readDisplacement(Stream& stream, const bool signedOffsets)
{
    return signedOffsets ? stream.get16() : stream.getU16();
}

template <typename LightViewType>
LightViewType* baseCreatureLightView(LightViewType* lightView, const bool negativeDisplacement, const bool creatureOutfit)
{
    return negativeDisplacement && creatureOutfit ? nullptr : lightView;
}

inline bool patchDisplacement(std::string& contents, const std::size_t offset, const int x, const int y)
{
    if(offset == 0 || offset + 4 > contents.size())
        return false;

    const auto writeCoordinate = [&](const std::size_t position, const int value) {
        const uint16_t encoded = static_cast<uint16_t>(value);
        contents[position] = static_cast<char>(encoded & 0xff);
        contents[position + 1] = static_cast<char>((encoded >> 8) & 0xff);
    };
    writeCoordinate(offset, x);
    writeCoordinate(offset + 2, y);
    return true;
}

inline bool insertDisplacement(
    std::string& contents, const std::size_t terminatorOffset, const uint8_t serializedAttr, const int x, const int y)
{
    if(terminatorOffset == 0 || terminatorOffset >= contents.size())
        return false;

    std::string attribute(5, '\0');
    attribute[0] = static_cast<char>(serializedAttr);
    if(!patchDisplacement(attribute, 1, x, y))
        return false;
    contents.insert(terminatorOffset, attribute);
    return true;
}

inline bool removeDisplacement(std::string& contents, const std::size_t valueOffset)
{
    constexpr std::size_t serializedSize = 5;
    if(valueOffset == 0 || valueOffset + 4 > contents.size())
        return false;

    contents.erase(valueOffset - 1, serializedSize);
    return true;
}
}

#endif
