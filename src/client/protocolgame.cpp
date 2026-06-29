/*
 * Copyright (c) 2010-2017 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
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

#include <framework/core/application.h>

#include "protocolgame.h"
#include "game.h"
#include "player.h"
#include "item.h"
#include "localplayer.h"
#include <framework/net/inputmessage.h>
#include <framework/net/outputmessage.h>

void ProtocolGame::login(const std::string& accountName, const std::string& accountPassword, const std::string& host, uint16 port, const std::string& characterName, const std::string& authenticatorToken, const std::string& sessionKey, const std::string& worldName)
{
    m_accountName = accountName;
    m_accountPassword = accountPassword;
    m_authenticatorToken = authenticatorToken;
    m_sessionKey = sessionKey;
    m_characterName = characterName;
    m_worldName = worldName;

    connect(host, port);
}

void ProtocolGame::onConnect()
{
    m_firstRecv = true;

    // KoliseuOT: choose the 16/32-bit item-id wire width for this connection from the
    // feature (default off = 16-bit, vanilla-compatible). Must be set before any map parse.
    InputMessage::s_use32BitItemId = g_game.getFeature(Otc::GameU32ItemIds);
    OutputMessage::s_use32BitItemId = g_game.getFeature(Otc::GameU32ItemIds);

    Protocol::onConnect();

    m_localPlayer = g_game.getLocalPlayer();

    if (g_game.getFeature(Otc::GameSendWorldName))
        sendWorldName();

    if (g_game.getFeature(Otc::GamePacketSizeU32))
        enableBigPackets();

    if(g_game.getFeature(Otc::GameProtocolChecksum))
        enableChecksum();

    // Tibia 13.x+/crystalserver scales the ProtocolGame 2-byte size header by 8
    // ((realSize-4)/8 on the wire). The server applies this to EVERY game packet
    // (Connection::parseHeader), so enable it for the whole game connection on
    // modern clients — including the very first login packet we send.
    if(g_game.getFeature(Otc::GameSequencedPackets))
        enableScaledPacketSize();

    if(!g_game.getFeature(Otc::GameChallengeOnLogin))
        sendLoginPacket(0, 0);

    recv();
}

void ProtocolGame::onRecv(const InputMessagePtr& inputMessage)
{
    m_recivedPackeds += 1;
    m_recivedPackedsSize += inputMessage->getMessageSize();
    if(m_firstRecv) {
        m_firstRecv = false;

        if (m_scaledPacketSize) {
            // Modern crystalserver framing: the first game packet (the login
            // challenge and the first post-login burst) is prefixed with a
            // single-byte message count (0x01 = "one message follows"), see
            // ProtocolGame::sendLoginChallenge ("Packet length & type"). It is
            // not an opcode, so consume it before dispatching, otherwise the
            // parser reads 0x01 as an unknown opcode.
            inputMessage->getU8();
        } else if(g_game.getFeature(Otc::GameMessageSizeCheck)) {
            int size = g_game.getFeature(Otc::GamePacketSizeU32) ? inputMessage->getU32() : inputMessage->getU16();
            if(size != inputMessage->getUnreadSize()) {
                g_logger.traceError("invalid message size");
                return;
            }
        }
    }

    parseMessage(inputMessage);
    recv();
}

void ProtocolGame::onError(const boost::system::error_code& error)
{
    // Keep ourselves alive for the duration of this handler: processConnectionError
    // -> Game::processDisconnect() resets g_game.m_protocolGame, which may be the
    // last shared_ptr to this object. Without this local ref, `this` (and the
    // referenced error_code, owned by the connection) would be freed mid-call and
    // the following disconnect() would crash with an access violation
    // (Protocol::disconnect+0x44, seen on WSAECONNREFUSED before first recv).
    auto self = static_self_cast<ProtocolGame>();

    // Copy the error before processConnectionError can tear down the connection.
    const auto err = error;
    g_game.processConnectionError(err);

    // processConnectionError -> processDisconnect already calls disconnect() on
    // us, so only disconnect here if that path didn't run (no protocol/offline).
    if (!m_disconnected)
        disconnect();
}

// ---------------------------------------------------------------------------
// Phase 1 SEAM: opcode dispatch table.
// ---------------------------------------------------------------------------
// The default state is an EMPTY table. parseMessage() consults the table
// first; if no handler is registered for the incoming opcode, control falls
// through to the legacy case-switch -- so legacy versions behave exactly as
// before. Phase 3 will register 15.24-specific handlers via Lua / C++.

void ProtocolGame::registerOpcodeHandler(uint8_t opcode, OpcodeHandler fn)
{
    if (!fn) {
        // Allow erase by passing an empty std::function (e.g. for hot reload).
        m_opcodeDispatch.erase(opcode);
        return;
    }
    m_opcodeDispatch[opcode] = std::move(fn);
}

bool ProtocolGame::tryDispatchOpcode(uint8_t opcode, const InputMessagePtr& msg)
{
    auto it = m_opcodeDispatch.find(opcode);
    if (it == m_opcodeDispatch.end())
        return false;
    it->second(msg);
    return true;
}
