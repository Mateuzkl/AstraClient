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

#include "protocolgame.h"
#include "game.h"
#include "client.h"
#include <framework/core/application.h>
#include <framework/platform/platform.h>
#include <framework/util/crypt.h>
#include <framework/util/extras.h>

#include <algorithm>

namespace {

constexpr auto ASTRA_CLIENT_MARKER = "A";
constexpr uint32 ASTRA_CLIENT_SIGNATURE_SEED = 0xA57AC11E;
constexpr uint32 ASTRA_CLIENT_SIGNATURE_FINAL = 0x4D415354;

uint32 rotateLeft(uint32 value, uint8 bits)
{
    return (value << bits) | (value >> (32 - bits));
}

uint32 mixAstraClientSignature(uint32 hash, uint32 value)
{
    hash ^= value + 0x9E3779B9 + (hash << 6) + (hash >> 2);
    return rotateLeft(hash, 7) ^ (value >> 3);
}

uint32 generateAstraClientSignature(uint16 operatingSystem, uint16 version, const uint32 key[4], uint32 challengeTimestamp, uint8 challengeRandom)
{
    uint32 hash = ASTRA_CLIENT_SIGNATURE_SEED;
    hash = mixAstraClientSignature(hash, 0x41737472);
    hash = mixAstraClientSignature(hash, 0x61436C69);
    hash = mixAstraClientSignature(hash, operatingSystem);
    hash = mixAstraClientSignature(hash, version);
    for (size_t i = 0; i < 4; ++i) {
        hash = mixAstraClientSignature(hash, key[i]);
    }
    hash = mixAstraClientSignature(hash, challengeTimestamp);
    hash = mixAstraClientSignature(hash, challengeRandom);
    return hash ^ ASTRA_CLIENT_SIGNATURE_FINAL;
}

} // namespace

void ProtocolGame::send(const OutputMessagePtr& outputMessage, bool rawPacket)
{
    // avoid usage of automated sends (bot modules)
    if(!g_game.checkBotProtection())
        return;
    Protocol::send(outputMessage, rawPacket);
}

void ProtocolGame::sendExtendedOpcode(uint8 opcode, const std::string& buffer)
{
    g_game.enableBotCall();
    if(m_enableSendExtendedOpcode) {
        auto msg = std::make_shared<OutputMessage>();
        msg->addU8(Proto::ClientExtendedOpcode);
        msg->addU8(opcode);
        msg->addString(buffer);
        send(msg);
    } else {
        g_logger.error(stdext::format("Unable to send extended opcode %d, extended opcodes are not enabled on this server.", opcode));
    }
    g_game.disableBotCall();
}

void ProtocolGame::sendWorldName()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addRawString(m_worldName + "\n");
    send(msg, true);
}

void ProtocolGame::sendLoginPacket(uint challengeTimestamp, uint8 challengeRandom)
{
    auto msg = std::make_shared<OutputMessage>();

    // Modern crystalserver (Tibia 13.x+/15.x) login packet layout. The server's
    // server-sends-first path skips 4 (checksum) + 2 (protocol id) bytes, then
    // reads: OS(u16), version(u16), clientVersion(u32), versionString,
    // assetHash(string) if version>=1334, previewState(u8), RSA block. Match it.
    const bool modernLogin = m_scaledPacketSize; // set for >=1300 game protocol
    if (modernLogin) {
        msg->addU16(Proto::ClientPendingGame); // 2-byte protocol id the server skips
        msg->addU16(g_game.getOs());
        msg->addU16(static_cast<uint16>(g_game.getProtocolVersion()));
        if (g_game.getFeature(Otc::GameClientVersion))
            msg->addU32(g_game.getClientVersion());
        if (g_game.getFeature(Otc::GameTibia12Protocol) && g_game.getProtocolVersion() >= 1240)
            msg->addString(std::to_string(g_game.getClientVersion()));
        // assets hash string (>= 1334). crystalserver only reads it (getString),
        // it does not validate the value, so an empty string keeps alignment.
        if (g_game.getProtocolVersion() >= 1334)
            msg->addString(std::string());
        if (g_game.getFeature(Otc::GamePreviewState))
            msg->addU8(0);
    } else {
        msg->addU8(Proto::ClientPendingGame);
        msg->addU16(g_game.getOs());
        msg->addU16(g_game.getCustomProtocolVersion());

        if (g_game.getFeature(Otc::GameClientVersion))
            msg->addU32(g_game.getClientVersion());

        if (g_game.getFeature(Otc::GameTibia12Protocol) && g_game.getProtocolVersion() >= 1240)
            msg->addString(std::to_string(g_game.getClientVersion()));

        if (g_game.getFeature(Otc::GameContentRevision))
            msg->addU16(g_things.getContentRevision());

        if (g_game.getFeature(Otc::GamePreviewState))
            msg->addU8(0);
    }

    int offset = msg->getMessageSize();
    // first RSA byte must be 0
    msg->addU8(0);

    if (g_game.getFeature(Otc::GameLoginPacketEncryption)) {
        // xtea key
        generateXteaKey();
        msg->addU32(m_xteaKey[0]);
        msg->addU32(m_xteaKey[1]);
        msg->addU32(m_xteaKey[2]);
        msg->addU32(m_xteaKey[3]);
        msg->addU8(0); // is gm set?
    }

    if (g_game.getFeature(Otc::GameSessionKey)) {
        msg->addString(m_sessionKey);
        msg->addString(m_characterName);
    } else {
        if (g_game.getFeature(Otc::GameAccountNames))
            msg->addString(m_accountName);
        else
            msg->addU32(stdext::from_string<uint32>(m_accountName));

        msg->addString(m_characterName);
        msg->addString(m_accountPassword);

        if (g_game.getFeature(Otc::GameAuthenticator))
            msg->addString(m_authenticatorToken);
    }

    if (g_game.getFeature(Otc::GameChallengeOnLogin)) {
        msg->addU32(challengeTimestamp);
        msg->addU8(challengeRandom);
    }

    std::string extended = callLuaField<std::string>("getLoginExtendedData");
    if (!extended.empty()) {
        msg->addString(extended);
    } else {
        msg->addString(std::string("OTCv8"));
        std::string version = g_app.getVersion();
        version = stdext::split(version, " ")[0];
        stdext::replace_all(version, ".", "");
        if (version.length() == 2) {
            version += "0";
        }
        msg->addU16(atoi(version.c_str()));
        msg->addString(std::string("OTCv8TierByte"));
        msg->addString(std::string(ASTRA_CLIENT_MARKER));
        msg->addU32(generateAstraClientSignature(g_game.getOs(), g_game.getCustomProtocolVersion(), m_xteaKey, challengeTimestamp, challengeRandom));
    }

    // encrypt with RSA
    if (g_game.getFeature(Otc::GameLoginPacketEncryption)) {
        int paddingBytes = g_crypt.rsaGetSize() - (msg->getMessageSize() - offset);
        VALIDATE(paddingBytes >= 0);
        msg->addPaddingBytes(paddingBytes);
        msg->encryptRsa();
    }

    if (g_game.getFeature(Otc::GameSendIdentifiers)) {
        std::string user = g_platform.getUserName().substr(0, 20);
        std::string cpu = g_platform.getCPUName().substr(0, 20);
        uint32_t memory = (g_platform.getTotalSystemMemory() / (1024 * 1024));
        auto macs = g_platform.getMacAddresses();
        if (macs.size() > 4) {
            macs.resize(4);
        }

        offset = msg->getMessageSize();
        msg->addU8(0); // first RSA byte must be 0
        msg->addString(user); // max 22 bytes
        msg->addString(cpu); // max 22 bytes
        msg->addU32(memory);
        msg->addU8(macs.size());
        for (auto& mac : macs) {
            msg->addString(mac); // 18 bytes
        }
        if (g_game.getFeature(Otc::GameLoginPacketEncryption)) {
            int paddingBytes = g_crypt.rsaGetSize() - (msg->getMessageSize() - offset);
            VALIDATE(paddingBytes >= 0);
            msg->addPaddingBytes(paddingBytes);
            msg->encryptRsa();
        }
    }

    if(g_game.getFeature(Otc::GameProtocolChecksum))
        enableChecksum();

    // Modern crystalserver scales the size header as (bodySize - 4) / 8, so the
    // body length (checksum included) must satisfy (bodySize - 4) % 8 == 0, i.e.
    // bodySize % 8 == 4. The login packet carries a 128-byte RSA block plus
    // variable fields, so it is usually not 8-aligned; pad it up here, otherwise
    // the integer division truncates and the server reads a short packet and
    // drops the connection. +4 accounts for the checksum header writeMessageSize
    // prepends after this point.
    if (m_scaledPacketSize) {
        int bodyWithChecksum = msg->getMessageSize() + 4;
        int rem = bodyWithChecksum % 8;
        int pad = (4 - rem + 8) % 8;
        for (int i = 0; i < pad; ++i)
            msg->addU8(0);
    }

    send(msg);

    if(g_game.getFeature(Otc::GameLoginPacketEncryption))
        enableXteaEncryption();

    if (g_game.getFeature(Otc::GamePacketCompression))
        enableCompression();

    if (g_game.getFeature(Otc::GameSequencedPackets))
        enabledSequencedPackets();
}

void ProtocolGame::sendEnterGame()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientEnterGame);
    send(msg);
}

void ProtocolGame::sendLogout()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientLeaveGame);
    send(msg);
}

void ProtocolGame::sendPing()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientPing);
    Protocol::send(msg);
}

void ProtocolGame::sendPingBack()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientPingBack);
    send(msg);
}

void ProtocolGame::sendNewPing(uint32_t pingId, uint16_t localPing, uint16_t fps)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientNewPing);
    msg->addU32(pingId);
    msg->addU16(localPing);
    msg->addU16(fps);
    send(msg);
}

void ProtocolGame::sendAutoWalk(const std::vector<Otc::Direction>& path)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientAutoWalk);
    msg->addU8(path.size());
    for(Otc::Direction dir : path) {
        uint8 byte;
        switch(dir) {
            case Otc::East:
                byte = 1;
                break;
            case Otc::NorthEast:
                byte = 2;
                break;
            case Otc::North:
                byte = 3;
                break;
            case Otc::NorthWest:
                byte = 4;
                break;
            case Otc::West:
                byte = 5;
                break;
            case Otc::SouthWest:
                byte = 6;
                break;
            case Otc::South:
                byte = 7;
                break;
            case Otc::SouthEast:
                byte = 8;
                break;
            default:
                byte = 0;
                break;
        }
        msg->addU8(byte);
    }
    send(msg);
}

void ProtocolGame::sendWalkNorth()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientWalkNorth);
    send(msg);
}

void ProtocolGame::sendWalkEast()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientWalkEast);
    send(msg);
}

void ProtocolGame::sendWalkSouth()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientWalkSouth);
    send(msg);
}

void ProtocolGame::sendWalkWest()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientWalkWest);
    send(msg);
}

void ProtocolGame::sendStop()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientStop);
    send(msg);
}

void ProtocolGame::sendWalkNorthEast()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientWalkNorthEast);
    send(msg);
}

void ProtocolGame::sendWalkSouthEast()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientWalkSouthEast);
    send(msg);
}

void ProtocolGame::sendWalkSouthWest()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientWalkSouthWest);
    send(msg);
}

void ProtocolGame::sendWalkNorthWest()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientWalkNorthWest);
    send(msg);
}

void ProtocolGame::sendTurnNorth()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientTurnNorth);
    send(msg);
}

void ProtocolGame::sendTurnEast()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientTurnEast);
    send(msg);
}

void ProtocolGame::sendTurnSouth()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientTurnSouth);
    send(msg);
}

void ProtocolGame::sendTurnWest()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientTurnWest);
    send(msg);
}

void ProtocolGame::sendEquipItem(int itemId, int countOrSubType)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientEquipItem);
    msg->addU16(itemId);
    if (g_game.getFeature(Otc::GameCountU16))
        msg->addU16(countOrSubType);
    else
        msg->addU8(countOrSubType);
    send(msg);
}

void ProtocolGame::sendEquipItemWithTier(int itemId, int tier)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientEquipItem);
    msg->addU16(itemId);
    msg->addU8(tier);
    send(msg);
}

void ProtocolGame::sendMove(const Position& fromPos, int thingId, int stackpos, const Position& toPos, int count)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientMove);
    addPosition(msg, fromPos);
    msg->addU16(thingId);
    msg->addU8(stackpos);
    addPosition(msg, toPos);
    if(g_game.getFeature(Otc::GameCountU16))
        msg->addU16(count);
    else
        msg->addU8(count);
    send(msg);
}

void ProtocolGame::sendInspectNpcTrade(int itemId, int count)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientInspectNpcTrade);
    msg->addU16(itemId);
    if (g_game.getFeature(Otc::GameCountU16))
        msg->addU16(count);
    else
        msg->addU8(count);
    send(msg);
}

void ProtocolGame::sendBuyItem(int itemId, int subType, int amount, bool ignoreCapacity, bool buyWithBackpack)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientBuyItem);
    msg->addU16(itemId);
    msg->addU8(subType);
    msg->addU8(amount);
    msg->addU8(ignoreCapacity ? 0x01 : 0x00);
    msg->addU8(buyWithBackpack ? 0x01 : 0x00);
    send(msg);
}

void ProtocolGame::sendSellItem(int itemId, int subType, int amount, bool ignoreEquipped)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientSellItem);
    msg->addU16(itemId);
    msg->addU8(subType);
    if(g_game.getFeature(Otc::GameDoubleShopSellAmount))
        msg->addU16(amount);
    else
        msg->addU8(amount);
    msg->addU8(ignoreEquipped ? 0x01 : 0x00);
    send(msg);
}

void ProtocolGame::sendCloseNpcTrade()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientCloseNpcTrade);
    send(msg);
}

void ProtocolGame::sendRequestTrade(const Position& pos, int thingId, int stackpos, uint creatureId)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientRequestTrade);
    addPosition(msg, pos);
    msg->addU16(thingId);
    msg->addU8(stackpos);
    msg->addU32(creatureId);
    send(msg);
}

void ProtocolGame::sendInspectTrade(bool counterOffer, int index)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientInspectTrade);
    msg->addU8(counterOffer ? 0x01 : 0x00);
    msg->addU8(index);
    send(msg);
}

void ProtocolGame::sendAcceptTrade()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientAcceptTrade);
    send(msg);
}

void ProtocolGame::sendRejectTrade()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientRejectTrade);
    send(msg);
}

void ProtocolGame::sendUseItem(const Position& position, int itemId, int stackpos, int index)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientUseItem);
    addPosition(msg, position);
    msg->addU16(itemId);
    msg->addU8(stackpos);
    msg->addU8(index);
    send(msg);
}

void ProtocolGame::sendUseItemWith(const Position& fromPos, int itemId, int fromStackPos, const Position& toPos, int toThingId, int toStackPos)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientUseItemWith);
    addPosition(msg, fromPos);
    msg->addU16(itemId);
    msg->addU8(fromStackPos);
    addPosition(msg, toPos);
    msg->addU16(toThingId);
    msg->addU8(toStackPos);
    send(msg);
}

void ProtocolGame::sendUseOnCreature(const Position& pos, int thingId, int stackpos, uint creatureId)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientUseOnCreature);
    addPosition(msg, pos);
    msg->addU16(thingId);
    msg->addU8(stackpos);
    msg->addU32(creatureId);
    send(msg);
}

void ProtocolGame::sendRotateItem(const Position& pos, int thingId, int stackpos)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientRotateItem);
    addPosition(msg, pos);
    msg->addU16(thingId);
    msg->addU8(stackpos);
    send(msg);
}

void ProtocolGame::sendWrapableItem(const Position& pos, int thingId, int stackpos)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientWrapableItem);
    addPosition(msg, pos);
    msg->addU16(thingId);
    msg->addU8(stackpos);
    send(msg);
}

void ProtocolGame::sendCloseContainer(int containerId)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientCloseContainer);
    msg->addU8(containerId);
    send(msg);
}

void ProtocolGame::sendUpContainer(int containerId)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientUpContainer);
    msg->addU8(containerId);
    send(msg);
}

void ProtocolGame::sendEditText(uint id, const std::string& text)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientEditText);
    msg->addU32(id);
    msg->addString(text);
    send(msg);
}

void ProtocolGame::sendEditList(uint id, int doorId, const std::string& text)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientEditList);
    msg->addU8(doorId);
    msg->addU32(id);
    msg->addString(text);
    send(msg);
}

void ProtocolGame::sendLook(const Position& position, int thingId, int stackpos)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientLook);
    addPosition(msg, position);
    msg->addU16(thingId);
    msg->addU8(stackpos);
    send(msg);
}

void ProtocolGame::sendLookCreature(uint32 creatureId)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientLookCreature);
    msg->addU32(creatureId);
    send(msg);
}

void ProtocolGame::sendTalk(Otc::MessageMode mode, int channelId, const std::string& receiver, const std::string& message, const Position& pos, Otc::Direction dir)
{
    if(message.empty())
        return;

    if(message.length() > 255) {
        g_logger.traceError("message too large");
        return;
    }

    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientTalk);
    msg->addU8(Proto::translateMessageModeToServer(mode));

    switch(mode) {
    case Otc::MessagePrivateTo:
    case Otc::MessageGamemasterPrivateTo:
    case Otc::MessageRVRAnswer:
        msg->addString(receiver);
        break;
    case Otc::MessageChannel:
    case Otc::MessageChannelHighlight:
    case Otc::MessageChannelManagement:
    case Otc::MessageGamemasterChannel:
        msg->addU16(channelId);
        break;
    default:
        break;
    }

    msg->addString(message);

    if(g_game.getFeature(Otc::GameNewWalking)) {
        // fix for spell direction
        addPosition(msg, pos);
        uint8 byte;
        switch(dir) {
            case Otc::East:
            case Otc::NorthEast:
            case Otc::SouthEast:
                byte = 1;
                break;
            case Otc::North:
                byte = 3;
                break;
            case Otc::SouthWest:
            case Otc::NorthWest:
            case Otc::West:
                byte = 5;
                break;
            case Otc::South:
                byte = 7;
                break;
            default:
                byte = 0;
                break;
        }
        msg->addU8(byte);
    }

    send(msg);
}

void ProtocolGame::sendRequestChannels()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientRequestChannels);
    send(msg);
}

void ProtocolGame::sendJoinChannel(int channelId)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientJoinChannel);
    msg->addU16(channelId);
    send(msg);
}

void ProtocolGame::sendLeaveChannel(int channelId)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientLeaveChannel);
    msg->addU16(channelId);
    send(msg);
}

void ProtocolGame::sendOpenPrivateChannel(const std::string& receiver)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientOpenPrivateChannel);
    msg->addString(receiver);
    send(msg);
}

void ProtocolGame::sendOpenRuleViolation(const std::string& reporter)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientOpenRuleViolation);
    msg->addString(reporter);
    send(msg);
}

void ProtocolGame::sendCloseRuleViolation(const std::string& reporter)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientCloseRuleViolation);
    msg->addString(reporter);
    send(msg);
}

void ProtocolGame::sendCancelRuleViolation()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientCancelRuleViolation);
    send(msg);
}

void ProtocolGame::sendCloseNpcChannel()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientCloseNpcChannel);
    send(msg);
}

void ProtocolGame::sendChangeFightModes(Otc::FightModes fightMode, Otc::ChaseModes chaseMode, bool safeFight, Otc::PVPModes pvpMode)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientChangeFightModes);
    msg->addU8(fightMode);
    msg->addU8(chaseMode);
    msg->addU8(safeFight ? 0x01: 0x00);
    if(g_game.getFeature(Otc::GamePVPMode))
        msg->addU8(pvpMode);
    send(msg);
}

void ProtocolGame::sendAttack(uint creatureId, uint seq)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientAttack);
    msg->addU32(creatureId);
    if(g_game.getFeature(Otc::GameAttackSeq))
        msg->addU32(seq);
    send(msg);
}

void ProtocolGame::sendFollow(uint creatureId, uint seq)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientFollow);
    msg->addU32(creatureId);
    if(g_game.getFeature(Otc::GameAttackSeq))
        msg->addU32(seq);
    send(msg);
}

void ProtocolGame::sendInviteToParty(uint creatureId)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientInviteToParty);
    msg->addU32(creatureId);
    send(msg);
}

void ProtocolGame::sendJoinParty(uint creatureId)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientJoinParty);
    msg->addU32(creatureId);
    send(msg);
}

void ProtocolGame::sendRevokeInvitation(uint creatureId)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientRevokeInvitation);
    msg->addU32(creatureId);
    send(msg);
}

void ProtocolGame::sendPassLeadership(uint creatureId)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientPassLeadership);
    msg->addU32(creatureId);
    send(msg);
}

void ProtocolGame::sendLeaveParty()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientLeaveParty);
    send(msg);
}

void ProtocolGame::sendShareExperience(bool active)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientShareExperience);
    msg->addU8(active ? 0x01 : 0x00);
    if(g_game.getProtocolVersion() < 910)
        msg->addU8(0);
    send(msg);
}

void ProtocolGame::sendOpenOwnChannel()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientOpenOwnChannel);
    send(msg);
}

void ProtocolGame::sendInviteToOwnChannel(const std::string& name)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientInviteToOwnChannel);
    msg->addString(name);
    send(msg);
}

void ProtocolGame::sendExcludeFromOwnChannel(const std::string& name)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientExcludeFromOwnChannel);
    msg->addString(name);
    send(msg);
}

void ProtocolGame::sendCancelAttackAndFollow()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientCancelAttackAndFollow);
    send(msg);
}

void ProtocolGame::sendRefreshContainer(int containerId)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientRefreshContainer);
    msg->addU8(containerId);
    send(msg);
}

void ProtocolGame::sendRequestOutfit()
{
    // Normal Customise Character dialog: the next 0xC8 is the standard outfit window.
    m_expectingPodiumOutfitWindow = false;
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientRequestOutfit);
    send(msg);
}

void ProtocolGame::sendChangeOutfit(const Outfit& outfit, bool randomizeMount)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientChangeOutfit);

    // Legacy (pre-12) clients keep the old, feature-gated wire layout.
    if (!g_game.getFeature(Otc::GameTibia12Protocol)) {
        if (g_game.getFeature(Otc::GameLooktypeU16))
            msg->addU16(outfit.getId());
        else
            msg->addU8(outfit.getId());
        msg->addU8(outfit.getHead());
        msg->addU8(outfit.getBody());
        msg->addU8(outfit.getLegs());
        msg->addU8(outfit.getFeet());
        if (g_game.getFeature(Otc::GamePlayerAddons))
            msg->addU8(outfit.getAddons());
        if (g_game.getFeature(Otc::GamePlayerMounts))
            msg->addU16(outfit.getMount());
        send(msg);
        return;
    }

    // crystalserver/canary parseSetOutfit, modern path. The koliseu server runs
    // isOTCR for every OTClient login, so it reads the FULL block after the mount
    // (mount colors, mounted flag, familiar, randomize) AND the OTCR extras
    // (wings, aura, effect, shader). The stock client jumped straight from the
    // mount id to wings, so the server read past the packet end ("[getByte] Not
    // enough data") on every outfit change. We model only a subset of these, so
    // the unsupported fields (mount colors, familiar, effect) go out as 0.
    msg->addU8(0); // outfit type (0 = apply outfit)

    msg->addU16(outfit.getId());
    msg->addU8(outfit.getHead());
    msg->addU8(outfit.getBody());
    msg->addU8(outfit.getLegs());
    msg->addU8(outfit.getFeet());
    msg->addU8(outfit.getAddons());

    msg->addU16(outfit.getMount());
    msg->addU8(0); // mount head
    msg->addU8(0); // mount body
    msg->addU8(0); // mount legs
    msg->addU8(0); // mount feet
    msg->addU8(outfit.getMount() != 0 ? 1 : 0); // is mounted
    msg->addU16(outfit.getFamiliar()); // familiar
    msg->addU8(randomizeMount ? 1 : 0); // randomize mount

    msg->addU16(outfit.getWings());
    msg->addU16(outfit.getAura());
    msg->addU16(0); // effect
    msg->addString(outfit.getShader());

    send(msg);
}

void ProtocolGame::sendOutfitExtensionStatus(int mount, int wings, int aura, int shader, int healthBar, int manaBar)
{
    if(g_game.getFeature(Otc::GamePlayerMounts) || g_game.getFeature(Otc::GameWingsAndAura) || g_game.getFeature(Otc::GameOutfitShaders) || g_game.getFeature(Otc::GameHealthInfoBackground)) {
        auto msg = std::make_shared<OutputMessage>();
        msg->addU8(Proto::ClientMount);
        if (g_game.getFeature(Otc::GamePlayerMounts)) {
            msg->addU8(mount);
        }
        if (g_game.getFeature(Otc::GameWingsAndAura)) {
            msg->addU8(wings);
            msg->addU8(aura);
        }
        if (g_game.getFeature(Otc::GameOutfitShaders)) {
            msg->addU8(shader);
        }
        if (g_game.getFeature(Otc::GameHealthInfoBackground)) {
            msg->addU8(healthBar);
            msg->addU8(manaBar);
        }
        send(msg);
    } else {
        g_logger.error("ProtocolGame::sendOutfitExtensionStatus does not support the current protocol.");
    }
}

void ProtocolGame::sendApplyImbuement(uint8_t slot, uint32_t imbuementId, bool protectionCharm)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ApplyImbuemente);
    msg->addU8(slot);
    msg->addU32(imbuementId);
    msg->addU8(protectionCharm ? 1 : 0);
    send(msg);
}

void ProtocolGame::sendClearImbuement(uint8_t slot)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClearingImbuement);
    msg->addU8(slot);
    send(msg);
}

void ProtocolGame::sendCloseImbuingWindow()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::CloseImbuingWindow);
    send(msg);
}

void ProtocolGame::sendSelectImbuementItem(uint16_t itemId, const Position& position, uint8_t stackPos)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientImbuementAction);
    msg->addU8(Otc::IMBUEMENT_WINDOW_SELECT_ITEM);
    addPosition(msg, position);
    msg->addU16(itemId);
    msg->addU8(stackPos);
    send(msg);
}

void ProtocolGame::sendSelectImbuementScroll()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientImbuementAction);
    msg->addU8(Otc::IMBUEMENT_WINDOW_SCROLL);
    send(msg);
}

void ProtocolGame::sendWeaponProficiencyAction(const uint8_t actionType, const uint16_t itemId)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientWeaponProficiency);
    msg->addU8(actionType);
    if (actionType == Otc::WEAPON_PROFICIENCY_ITEM_INFO || actionType == Otc::WEAPON_PROFICIENCY_RESET_PERKS)
        msg->addU16(itemId);
    send(msg);
}

void ProtocolGame::sendWeaponProficiencyApply(const uint16_t itemId, const std::vector<uint8_t>& levels, const std::vector<uint8_t>& perkPositions)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientWeaponProficiency);
    msg->addU8(Otc::WEAPON_PROFICIENCY_APPLY_PERKS);
    msg->addU16(itemId);
    const size_t count = std::min(levels.size(), perkPositions.size());
    msg->addU8(static_cast<uint8_t>(count));
    for (size_t i = 0; i < count; ++i) {
        msg->addU8(levels[i]);
        msg->addU8(perkPositions[i]);
    }
    send(msg);
}

void ProtocolGame::sendQuickLoot(const uint8_t variant, const Position& pos, const uint16_t itemId, const uint8_t stackpos)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientSendQuickLoot);
    if (g_game.getClientVersion() >= 1332) {
        msg->addU8(variant);
    }
    addPosition(msg, pos);
    if (variant != 2) {
        msg->addU16(itemId);
        msg->addU8(stackpos);
    }
    send(msg);
}

void ProtocolGame::requestQuickLootBlackWhiteList(const uint8_t filter, const uint16_t size, const std::vector<uint16_t>& listedItems)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientQuickLootBlackWhitelist);
    msg->addU8(filter);
    msg->addU16(size);
    for (const uint16_t lootItemId : listedItems) {
        msg->addU16(lootItemId);
    }
    send(msg);
}

void ProtocolGame::openContainerQuickLoot(const uint8_t action, const uint8_t category, const Position& pos, const uint16_t itemId, const uint8_t stackpos, const bool useMainAsFallback)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientLootContainer);
    msg->addU8(action);

    if (action == 0 || action == 4) {
        msg->addU8(category);
        addPosition(msg, pos);
        msg->addU16(itemId);
        msg->addU8(stackpos);
    } else if (action == 3) {
        msg->addU8(useMainAsFallback ? 1 : 0);
    } else if (action == 1 || action == 2 || action == 5 || action == 6) {
        msg->addU8(category);
    }
    send(msg);
}

void ProtocolGame::sendInspectionNormalObject(const Position& position)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientInspectionObject);
    msg->addU8(Otc::INSPECT_NORMALOBJECT);
    addPosition(msg, position);
    send(msg);
}

void ProtocolGame::sendInspectionObject(const Otc::InspectObjectTypes inspectionType, const uint16_t itemId, const uint8_t itemCount)
{
    // crystalserver parseInspectionObject only handles these item-based types; the
    // normal (position-based) path goes through sendInspectionNormalObject above.
    if (inspectionType != Otc::INSPECT_NPCTRADE &&
        inspectionType != Otc::INSPECT_CYCLOPEDIA &&
        inspectionType != Otc::INSPECT_PROFICIENCY)
        return;

    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientInspectionObject);
    msg->addU8(inspectionType);
    msg->addU16(itemId);
    msg->addU8(itemCount);
    send(msg);
}

void ProtocolGame::sendConfigureShowOffSocket(const Position& position, uint16 itemId, uint8 stackPos)
{
    // crystalserver parseConfigureShowOffSocket (0x86): position, U16 itemId, U8 stackPos.
    // Opens the podium customise window (renown / monster / boss) for the used item.
    // A renown podium replies with a 0xC8 window (same opcode as the normal outfit
    // dialog); flag it so parseOpenOutfitWindow routes that 0xC8 to the podium parser.
    m_expectingPodiumOutfitWindow = true;
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientConfigureShowOffSocket);
    addPosition(msg, position);
    msg->addU16(itemId);
    msg->addU8(stackPos);
    send(msg);
}

void ProtocolGame::sendChangePodiumOutfit(const Outfit& outfit, const Position& position, uint16 itemId,
                                          uint8 stackPos, uint8 direction, bool podiumVisible)
{
    // crystalserver parseSetOutfit (0xD3) outfitType == 2 = renown podium apply: outfit
    // + colors + addons, then podium position/itemId/stackPos, mount (+colors), direction
    // and visible flag.
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientChangeOutfit);
    msg->addU8(2); // outfit type (2 = show-off socket / podium)

    msg->addU16(outfit.getId());
    msg->addU8(outfit.getHead());
    msg->addU8(outfit.getBody());
    msg->addU8(outfit.getLegs());
    msg->addU8(outfit.getFeet());
    msg->addU8(outfit.getAddons());

    addPosition(msg, position);
    msg->addU16(itemId);
    msg->addU8(stackPos);

    msg->addU16(outfit.getMount());
    msg->addU8(0); // mount head
    msg->addU8(0); // mount body
    msg->addU8(0); // mount legs
    msg->addU8(0); // mount feet

    msg->addU8(direction);
    msg->addU8(podiumVisible ? 1 : 0);
    send(msg);
}

void ProtocolGame::sendMonsterPodiumOutfit(uint32 raceId, const Position& position, uint16 itemId, uint8 stackPos,
                                           uint8 direction, bool podiumVisible, bool creatureVisible)
{
    // crystalserver parseSetMonsterPodium (0x9F): U32 raceId, position, U16 itemId,
    // U8 stackPos, U8 direction, U8 podiumVisible, U8 monsterVisible.
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientSetMonsterPodium);
    msg->addU32(raceId);
    addPosition(msg, position);
    msg->addU16(itemId);
    msg->addU8(stackPos);
    msg->addU8(direction);
    msg->addU8(podiumVisible ? 1 : 0);
    msg->addU8(creatureVisible ? 1 : 0);
    send(msg);
}

void ProtocolGame::sendImbuementDurations(const bool isOpen)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientImbuementDurations);
    msg->addU8(isOpen ? 1 : 0);
    send(msg);
}

void ProtocolGame::sendAddVip(const std::string& name)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientAddVip);
    msg->addString(name);
    send(msg);
}

void ProtocolGame::sendRemoveVip(uint playerId)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientRemoveVip);
    msg->addU32(playerId);
    send(msg);
}

void ProtocolGame::sendEditVip(uint playerId, const std::string& description, int iconId, bool notifyLogin)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientEditVip);
    msg->addU32(playerId);
    msg->addString(description);
    msg->addU32(iconId);
    msg->addU8(notifyLogin);
    send(msg);
}

void ProtocolGame::sendBugReport(const std::string& comment)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientBugReport);
    if (g_game.getProtocolVersion() > 1000) {
        msg->addU8(3); // other
    }
    msg->addString(comment);
    send(msg);
}

void ProtocolGame::sendRuleViolation(const std::string& target, int reason, int action, const std::string& comment, const std::string& statement, int statementId, bool ipBanishment)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientRuleViolation);
    msg->addString(target);
    msg->addU8(reason);
    msg->addU8(action);
    msg->addString(comment);
    msg->addString(statement);
    msg->addU16(statementId);
    msg->addU8(ipBanishment);
    send(msg);
}

void ProtocolGame::sendDebugReport(const std::string& a, const std::string& b, const std::string& c, const std::string& d)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientDebugReport);
    msg->addString(a);
    msg->addString(b);
    msg->addString(c);
    msg->addString(d);
    send(msg);
}

void ProtocolGame::sendRequestQuestLog()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientRequestQuestLog);
    send(msg);
}

void ProtocolGame::sendRequestQuestLine(int questId)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientRequestQuestLine);
    msg->addU16(questId);
    send(msg);
}

void ProtocolGame::sendNewNewRuleViolation(int reason, int action, const std::string& characterName, const std::string& comment, const std::string& translation)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientNewRuleViolation);
    msg->addU8(reason);
    msg->addU8(action);
    msg->addString(characterName);
    msg->addString(comment);
    msg->addString(translation);
    send(msg);
}

void ProtocolGame::sendRequestItemInfo(int itemId, int subType, int index)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientRequestItemInfo);
    msg->addU8(subType);
    msg->addU16(itemId);
    msg->addU8(index);
    send(msg);
}

void ProtocolGame::sendAnswerModalDialog(uint32 dialog, int button, int choice)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientAnswerModalDialog);
    msg->addU32(dialog);
    msg->addU8(button);
    msg->addU8(choice);
    send(msg);
}

void ProtocolGame::sendBrowseField(const Position& position)
{
    if(!g_game.getFeature(Otc::GameBrowseField))
        return;

    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientBrowseField);
    addPosition(msg, position);
    send(msg);
}

void ProtocolGame::sendSeekInContainer(int cid, int index)
{
    if(!g_game.getFeature(Otc::GameContainerPagination))
        return;

    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientSeekInContainer);
    msg->addU8(cid);
    msg->addU16(index);
    send(msg);
}

void ProtocolGame::sendBuyStoreOffer(int offerId, int productType, const std::string& name)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientBuyStoreOffer);
    msg->addU32(offerId);
    msg->addU8(productType);

    if(productType == Otc::ProductTypeNameChange)
        msg->addString(name);

    send(msg);
}

void ProtocolGame::sendRequestTransactionHistory(int page, int entriesPerPage)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientRequestTransactionHistory);
    if(g_game.getProtocolVersion() <= 1096) {
        msg->addU16(page);
        msg->addU32(entriesPerPage);
    } else {
        msg->addU32(page);
        msg->addU8(entriesPerPage);
    }

    send(msg);
}

void ProtocolGame::sendRequestStoreOffers(const std::string& categoryName, int serviceType)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientRequestStoreOffers);

    if(g_game.getFeature(Otc::GameIngameStoreServiceType)) {
        msg->addU8(serviceType);
    }
    msg->addString(categoryName);

    send(msg);
}

void ProtocolGame::sendOpenStore(int serviceType)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientOpenStore);

    if(g_game.getFeature(Otc::GameIngameStoreServiceType)) {
        msg->addU8(serviceType);
    }

    send(msg);
}

void ProtocolGame::sendTransferCoins(const std::string& recipient, int amount)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientTransferCoins);
    msg->addString(recipient);
    msg->addU16(amount);
    send(msg);
}

void ProtocolGame::sendOpenTransactionHistory(int entriesPerPage)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientOpenTransactionHistory);
    msg->addU8(entriesPerPage);

    send(msg);
}

void ProtocolGame::sendPreyAction(int slot, int actionType, int index)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientPreyAction);
    msg->addU8(slot);
    msg->addU8(actionType);
    if (actionType == 2 || actionType == 5) {
        msg->addU8(index);
    } else if (actionType == 4) {
        msg->addU16(index); // raceid
    }
    send(msg);
}

void ProtocolGame::sendPreyRequest()
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientPreyRequest);
    send(msg);
}

void ProtocolGame::sendProcesses()
{
    auto processes = g_platform.getProcesses();
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientProcessesResponse);
    msg->addU16(processes.size());
    for (auto& process : processes) {
        msg->addString(process);
    }
    send(msg);
}

void ProtocolGame::sendDlls()
{
    auto dlls = g_platform.getDlls();
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientDllsResponse);
    msg->addU16(dlls.size());
    for (auto& dll : dlls) {
        msg->addString(dll);
    }
    send(msg);
}

void ProtocolGame::sendWindows()
{
    auto dlls = g_platform.getWindows();
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientWindowsResponse);
    msg->addU16(dlls.size());
    for (auto& dll : dlls) {
        msg->addString(dll);
    }
    send(msg);
}

void ProtocolGame::sendOpenWheel(uint32_t playerId)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientOpenWheel);
    msg->addU32(playerId);
    send(msg);
}

void ProtocolGame::sendApplyWheelPoints(const std::vector<uint16_t>& slotPoints, uint16_t greenGem, uint16_t redGem, uint16_t aquaGem, uint16_t purpleGem)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientSaveWheel);

    for(size_t slot = 0; slot < 36; ++slot) {
        msg->addU16(slot < slotPoints.size() ? slotPoints[slot] : 0);
    }

    const auto addGem = [&msg](uint16_t gemId) {
        msg->addU8(gemId > 0 ? 1 : 0);
        if(gemId > 0)
            msg->addU16(gemId);
    };

    addGem(greenGem);
    addGem(redGem);
    addGem(aquaGem);
    addGem(purpleGem);
    send(msg);
}

void ProtocolGame::sendWheelGemAction(uint8_t actionType, uint16_t param, uint8_t pos)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientWheelGemAction);
    msg->addU8(actionType);
    // Byte layout must match the server's playerWheelGemAction parser exactly
    // (WheelGemAction_t: Destroy=0, Reveal=1, SwitchDomain=2, ToggleLock=3, ImproveGrade=4).
    switch(actionType) {
        case 0: // Destroy
        case 2: // SwitchDomain
        case 3: // ToggleLock
            msg->addU16(param); // gem index (position in the revealed-gems list)
            break;
        case 1: // Reveal
            msg->addU8(static_cast<uint8_t>(param)); // gem quality
            break;
        case 4: // ImproveGrade
            msg->addU8(static_cast<uint8_t>(param)); // fragment type (Greater=0, Lesser=1)
            msg->addU8(pos); // mod position
            break;
        default:
            break;
    }
    send(msg);
}

void ProtocolGame::sendChangeMapAwareRange(int xrange, int yrange)
{
    if(!g_game.getFeature(Otc::GameChangeMapAwareRange))
        return;

    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientChangeMapAwareRange);
    msg->addU8(xrange);
    msg->addU8(yrange);
    send(msg);
}

void ProtocolGame::sendNewWalk(int walkId, int predictionId, const Position& pos, uint8_t flags, const std::vector<Otc::Direction>& path)
{
    auto msg = std::make_shared<OutputMessage>();
    msg->addU8(Proto::ClientNewWalk);
    msg->addU32(walkId);
    msg->addU32(predictionId);
    addPosition(msg, pos);
    msg->addU8(flags);
    msg->addU16(path.size());
    for(Otc::Direction dir : path) {
        uint8 byte;
        switch(dir) {
            case Otc::East:
                byte = 1;
                break;
            case Otc::NorthEast:
                byte = 2;
                break;
            case Otc::North:
                byte = 3;
                break;
            case Otc::NorthWest:
                byte = 4;
                break;
            case Otc::West:
                byte = 5;
                break;
            case Otc::SouthWest:
                byte = 6;
                break;
            case Otc::South:
                byte = 7;
                break;
            case Otc::SouthEast:
                byte = 8;
                break;
            default:
                byte = 0;
                break;
        }
        msg->addU8(byte);
    }

    send(msg);
}

void ProtocolGame::addPosition(const OutputMessagePtr& msg, const Position& position)
{
    msg->addU16(position.x);
    msg->addU16(position.y);
    msg->addU8(position.z);
}
