#include <framework/global.h>
#include <framework/core/clock.h>

#include "packet_player.h"

#include <stdexcept>
#include <string_view>

namespace {
int hexValue(char c)
{
    if (c >= '0' && c <= '9')
        return c - '0';
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    if (c >= 'A' && c <= 'F')
        return c - 'A' + 10;
    throw std::runtime_error("Invalid packet record hex data");
}

std::string decodeHex(std::string_view hex)
{
    if (hex.size() % 2 != 0)
        throw std::runtime_error("Invalid packet record hex length");

    std::string decoded;
    decoded.reserve(hex.size() / 2);
    for (size_t i = 0; i < hex.size(); i += 2) {
        decoded.push_back(static_cast<char>((hexValue(hex[i]) << 4) | hexValue(hex[i + 1])));
    }
    return decoded;
}
}

PacketPlayer::~PacketPlayer()
{
    if (m_event)
        m_event->cancel();
}

PacketPlayer::PacketPlayer(const std::string& file)
{
    static uint32_t sessionId = 1;
#ifdef ANDROID
    std::ifstream f(std::string("records/") + file);
#else
    std::ifstream f(std::filesystem::path("records") / file);
#endif
    if (!f.is_open())
        return;
    std::string type, packetHex;
    ticks_t time;
    while (f >> type >> time >> packetHex) {
        std::string packetStr = decodeHex(packetHex);
        auto packet = std::make_shared<std::vector<uint8_t>>(packetStr.begin(), packetStr.end());
        if (type == "<") {
            m_input.push_back(std::make_pair(time, packet));
        } else if (type == ">") {
            m_output.push_back(std::make_pair(time, packet));
        }
    }
}

void PacketPlayer::start(std::function<void(std::shared_ptr<std::vector<uint8_t>>)> recvCallback,
                         std::function<void(boost::system::error_code)> disconnectCallback)
{
    m_start = g_clock.millis();
    m_recvCallback = recvCallback;
    m_disconnectCallback = disconnectCallback;
    m_event = g_dispatcher.scheduleEvent(std::bind(&PacketPlayer::process, this), 50);
}

void PacketPlayer::stop()
{
    if (m_event)
        m_event->cancel();
    m_event = nullptr;
}

void PacketPlayer::onOutputPacket(const OutputMessagePtr& packet)
{
    if (packet->getDataBuffer()[0] == 0x14) { // logout
        m_disconnectCallback(boost::asio::error::eof);
        stop();
    }
}


void PacketPlayer::process()
{
    ticks_t nextPacket = 1;
    while (!m_input.empty()) {
        auto& packet = m_input.front();
        nextPacket = (packet.first + m_start) - g_clock.millis();
        if (nextPacket > 1)
            break;
        m_recvCallback(packet.second);
        m_input.pop_front();
    }

    if (!m_input.empty() && nextPacket > 1) {
        m_event = g_dispatcher.scheduleEvent(std::bind(&PacketPlayer::process, this), nextPacket);
    } else {
        m_disconnectCallback(boost::asio::error::eof);
        stop();
    }
}
