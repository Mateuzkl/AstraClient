#include <framework/global.h>
#include <framework/core/clock.h>

#include "packet_player.h"

PacketPlayer::~PacketPlayer()
{
    if (m_event)
        m_event->cancel();
}

static std::string custom_unhex(const std::string& hex) {
    if (hex.length() % 2 != 0) {
        throw std::runtime_error("Invalid hex length");
    }
    std::string result;
    result.reserve(hex.length() / 2);
    for (size_t i = 0; i < hex.length(); i += 2) {
        std::string byteString = hex.substr(i, 2);
        char* endptr = nullptr;
        long val = std::strtol(byteString.c_str(), &endptr, 16);
        if (endptr != byteString.c_str() + 2) {
            throw std::runtime_error("Invalid hex character");
        }
        result.push_back((char)val);
    }
    return result;
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
    try {
        while (f >> type >> time >> packetHex) {
            std::string packetStr = custom_unhex(packetHex);
            auto packet = std::make_shared<std::vector<uint8_t>>(packetStr.begin(), packetStr.end());
            if (type == "<") {
                m_input.push_back(std::make_pair(time, packet));
            } else if (type == ">") {
                m_output.push_back(std::make_pair(time, packet));
            }
        }
    } catch (const std::exception& e) {
        g_logger.error(std::string("Error parsing replay packets: ") + e.what());
        m_input.clear();
        m_output.clear();
    }
}

void PacketPlayer::start(std::function<void(std::shared_ptr<std::vector<uint8_t>>)> recvCallback,
                         std::function<void(asio::error_code)> disconnectCallback)
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
        m_disconnectCallback(asio::error::eof);
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
        m_disconnectCallback(asio::error::eof);
        stop();
    }
}
