#include "src/client/spellcooldown.h"

#include <cassert>
#include <cstdint>
#include <initializer_list>
#include <stdexcept>
#include <vector>

namespace
{
class Packet
{
  public:
    Packet(std::initializer_list<uint8_t> bytes) : m_bytes(bytes) {}

    uint8_t getU8()
    {
        if (m_cursor == m_bytes.size())
            throw std::runtime_error("packet eof");
        return m_bytes[m_cursor++];
    }

    uint16_t getU16()
    {
        const uint16_t low = getU8();
        return low | (static_cast<uint16_t>(getU8()) << 8);
    }

    uint32_t getU32()
    {
        const uint32_t low = getU16();
        return low | (static_cast<uint32_t>(getU16()) << 16);
    }

    std::size_t unread() const { return m_bytes.size() - m_cursor; }

  private:
    std::vector<uint8_t> m_bytes;
    std::size_t m_cursor = 0;
};

void checkPacket(std::initializer_list<uint8_t> bytes, bool extended, int id, int delay)
{
    Packet packet(bytes);
    assert(packet.getU8() == 0xA4);
    const auto cooldown = SpellCooldownProtocol::read(packet, extended);
    assert(cooldown.spellId == id && cooldown.delay == delay);
    assert(packet.unread() == 0);
}
} // namespace

int main()
{
    checkPacket({0xA4, 0x2A, 0xE8, 0x03, 0x00, 0x00}, false, 42, 1000);
    checkPacket({0xA4, 0xFF, 0xE8, 0x03, 0x00, 0x00}, false, 255, 1000);
    checkPacket({0xA4, 0x2A, 0x00, 0xE8, 0x03, 0x00, 0x00}, true, 42, 1000);
    checkPacket({0xA4, 0x00, 0x01, 0xE8, 0x03, 0x00, 0x00}, true, 256, 1000);
    checkPacket({0xA4, 0x13, 0x01, 0xE8, 0x03, 0x00, 0x00}, true, 275, 1000);
    checkPacket({0xA4, 0xFF, 0xFF, 0xE8, 0x03, 0x00, 0x00}, true, 65535, 1000);
    checkPacket({0xA4, 0x2A, 0x00, 0x00, 0x00, 0x00}, false, 42, 0);
    checkPacket({0xA4, 0x13, 0x01, 0x00, 0x00, 0x00, 0x00}, true, 275, 0);

    // The old desync pattern must leave the next real opcode, not a stray 0x00.
    Packet sequence({0xA4, 0x04, 0x00, 0xE8, 0x03, 0x00, 0x00, 0xA5, 0x02, 0xD0, 0x07, 0x00, 0x00});
    assert(sequence.getU8() == 0xA4);
    const auto cooldown = SpellCooldownProtocol::read(sequence, true);
    assert(cooldown.spellId == 4 && cooldown.delay == 1000);
    assert(sequence.unread() == 6 && sequence.getU8() == 0xA5);
    assert(sequence.getU8() == 2 && sequence.getU32() == 2000);
    assert(sequence.unread() == 0);

    Packet truncated({0x13, 0x01, 0xE8, 0x03, 0x00});
    bool rejected = false;
    try
    {
        SpellCooldownProtocol::read(truncated, true);
    }
    catch (const std::runtime_error&)
    {
        rejected = true;
    }
    assert(rejected);
}
