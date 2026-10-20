// Exercise the native reader used by ProtocolGame, without Lua, sockets or assets.
#include "src/client/customitemprotocol.h"
#include <cassert>
#include <stdexcept>

struct Message {
    std::string bytes;
    size_t offset = 0;
    uint8_t getU8() {
        if (offset == bytes.size()) throw std::runtime_error("truncated message");
        return static_cast<uint8_t>(bytes[offset++]);
    }
    uint16_t getU16() { const auto low = getU8(); return low | (uint16_t(getU8()) << 8); }
    uint32_t getU32() { const auto low = getU16(); return low | (uint32_t(getU16()) << 16); }
    std::string getString() {
        const auto size = getU16();
        if (size > bytes.size() - offset) throw std::runtime_error("truncated string");
        const auto value = bytes.substr(offset, size);
        offset += size;
        return value;
    }
    void add(uint32_t value, unsigned size) {
        for (unsigned i = 0; i < size; ++i) bytes += char((value >> (i * 8)) & 255);
    }
    void text(const std::string& value) { add(uint32_t(value.size()), 2); bytes += value; }
};

int main()
{
    Message payload;
    payload.add(2160, 2);
    payload.add(77, 4); payload.add(55, 4); payload.add(33, 4);
    payload.add(2, 1);
    payload.text("Name"); payload.text("Test Sword");
    payload.text("Weight"); payload.text("35.00 oz");
    payload.add(2, 2);
    for (unsigned i = 0; i < 2; ++i) {
        payload.text("Florentine"); payload.text("Carlin");
        payload.add(100 + i, 4); payload.add(200 + i, 4); payload.text("");
    }
    const auto detailsSize = payload.bytes.size();
    payload.add(0x6d, 1); payload.add(32341, 2); payload.add(31789, 2);
    payload.add(7, 1); payload.add(1, 1);
    payload.add(32342, 2); payload.add(31789, 2); payload.add(7, 1);
    const auto data = CustomItemProtocol::readDetails(payload);
    assert(data.itemId == 2160 && data.defaultValue == 77);
    assert(data.defaultBuyPrice == 55 && data.averageMarketValue == 33);
    assert(data.descriptions[0].first == "Name" && data.descriptions[0].second == "Test Sword");
    assert(data.npcSaleData.size() == 2 && std::get<2>(data.npcSaleData[1]) == 101);
    assert(payload.offset == detailsSize && payload.getU8() == 0x6d);
    assert(payload.getU16() == 32341 && payload.getU16() == 31789);
    for (size_t length = 0; length < detailsSize; ++length) {
        Message truncated{payload.bytes.substr(0, length)};
        bool rejected = false;
        try { CustomItemProtocol::readDetails(truncated); }
        catch (const std::runtime_error&) { rejected = true; }
        assert(rejected);
    }
    Message empty;
    empty.add(1, 2);
    empty.add(0, 4); empty.add(0, 4); empty.add(0, 4);
    empty.add(0, 1); empty.add(0, 2); empty.add(0x6d, 1);
    assert(CustomItemProtocol::readDetails(empty).npcSaleData.empty());
    assert(empty.getU8() == 0x6d);
}
