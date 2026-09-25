#ifndef NEGATIVEOFFSET_H
#define NEGATIVEOFFSET_H

#include <cstdint>
#include <string>

namespace NegativeOffset
{
template <typename Stream>
int32_t readDisplacement(Stream& stream, const bool signedOffsets)
{
    return signedOffsets ? stream.get16() : stream.getU16();
}

template <typename LightViewType>
LightViewType* baseCreatureLightView(LightViewType* lightView, const bool negativeOffsets, const bool creatureOutfit)
{
    return negativeOffsets && creatureOutfit ? nullptr : lightView;
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
}

#endif
