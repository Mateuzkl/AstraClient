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

#include <map>
#include <tuple>
#include <vector>

#include "localplayer.h"
#include "thingtypemanager.h"
#include "game.h"
#include "const.h"
#include "map.h"
#include "item.h"
#include "effect.h"
#include "missile.h"
#include "tile.h"
#include "luavaluecasts_client.h"
#include <framework/core/eventdispatcher.h>
#include <framework/util/extras.h>
#include <framework/stdext/string.h>

#include <set>

namespace {
// servers can reference appearances missing from the loaded assets on every melee
// swing (e.g. crystalserver CONST_ME_SWORD_ATTACK=304); log each id only once
void logUnknownThingIdOnce(const char* what, int id)
{
    static std::set<std::pair<std::string, int>> logged;
    if (logged.emplace(what, id).second)
        g_logger.error(stdext::format("server sent %s id %d which is not in the loaded assets (suppressing repeats)", what, id));
}

// crystalserver CONST_ME_LOOT_HIGHLIGHT (utils_definitions.hpp): suppressed when the
// client's "lootHighlight" option is off (g_game.shouldShowLootHighlightEffect from
// mods/client_settings/settings.lua).
constexpr int LootHighlightEffectId = 252;

bool shouldDrawMagicEffect(int effectId)
{
    if (effectId != LootHighlightEffectId)
        return true;

    int rets = g_lua.luaCallGlobalField("g_game", "shouldShowLootHighlightEffect");
    if (rets <= 0)
        return true;

    bool shouldDraw = true;
    if (g_lua.isBoolean())
        shouldDraw = g_lua.popBoolean();
    else
        g_lua.pop(1);

    if (rets > 1)
        g_lua.pop(rets - 1);

    return shouldDraw;
}
}

void ProtocolGame::parseMessage(const InputMessagePtr& msg)
{
    int opcode = -1;
    int prevOpcode = -1;
    int opcodePos = 0;
    int prevOpcodePos = 0;

    try {
        while (!msg->eof()) {
            opcodePos = msg->getReadPos();
            opcode = msg->getU8();

            // Build the profiler description (per-opcode int->string) only when
            // profiling is on; otherwise skip the allocation entirely.
            AutoStat s(STATS_PACKETS, statsEnabled() ? std::to_string((int)opcode) : std::string());

            if (opcode == 0x00) {
                std::string buffer = msg->getString();
                std::string file = msg->getString();
                try {
                    // runBuffer = loadBuffer + safeCall(0,0). The bare loadBuffer left
                    // the compiled chunk on the Lua stack every time, so after ~13
                    // extended-opcode messages getTop() exceeded 20 and checkStack()
                    // aborted with "getTop() <= 20".
                    g_lua.runBuffer(buffer, file);
                } catch (...) {}
                prevOpcode = opcode;
                prevOpcodePos = opcodePos;
                continue;
            }

            // must be > so extended will be enabled before GameStart.
            if (!g_game.getFeature(Otc::GameLoginPending)) {
                if (!m_gameInitialized && opcode > Proto::GameServerFirstGameOpcode) {
                    g_game.processGameStart();
                    m_gameInitialized = true;
                }
            }

            // try to parse in lua first -- but only round-trip into Lua's onOpcode when a
            // Lua handler is actually registered for this opcode (g_game's bitset, kept in
            // sync by ProtocolGame.register/unregisterOpcode). Most 15.24 opcodes have no
            // Lua handler, so this skips the per-opcode pushObject + pcall for them; when a
            // handler exists the behaviour is byte-identical to before.
            if (g_game.hasLuaOpcodeHandler(opcode)) {
                int readPos = msg->getReadPos();
                if (callLuaField<bool>("onOpcode", opcode, msg)) {
                    prevOpcode = opcode;
                    prevOpcodePos = opcodePos;
                    continue;
                } else
                    msg->setReadPos(readPos); // restore read pos
            }

            // Phase 1 SEAM: opcode dispatch table.
            // If a handler is registered for this opcode (Phase 3 / 15.24),
            // invoke it and SKIP the legacy switch below. When the table is
            // empty (legacy versions, default state) tryDispatchOpcode()
            // returns false and the existing switch handles the opcode --
            // byte-identical to the pre-seam behaviour.
            if (tryDispatchOpcode(static_cast<uint8_t>(opcode), msg)) {
                prevOpcode = opcode;
                prevOpcodePos = opcodePos;
                continue;
            }

            switch (opcode) {
            case Proto::GameServerLoginOrPendingState:
                if (g_game.getFeature(Otc::GameLoginPending))
                    parsePendingGame(msg);
                else
                    parseLogin(msg);
                break;
            case Proto::GameServerGMActions:
                parseGMActions(msg);
                break;
            case Proto::GameServerUpdateNeeded:
                parseUpdateNeeded(msg);
                break;
            case Proto::GameServerLoginError:
                parseLoginError(msg);
                break;
            case Proto::GameServerLoginAdvice:
                parseLoginAdvice(msg);
                break;
            case Proto::GameServerLoginWait:
                parseLoginWait(msg);
                break;
            case Proto::GameServerLoginToken:
                parseLoginToken(msg);
                break;
            case Proto::GameServerPing:
            case Proto::GameServerPingBack:
                if ((opcode == Proto::GameServerPing && g_game.getFeature(Otc::GameClientPing)) ||
                    (opcode == Proto::GameServerPingBack && !g_game.getFeature(Otc::GameClientPing)))
                    parsePingBack(msg);
                else
                    parsePing(msg);
                break;
            case Proto::GameServerChallenge:
                parseChallenge(msg);
                break;
            case Proto::GameServerNewPing:
                parseNewPing(msg);
                break;
            case Proto::GameServerDeath:
                parseDeath(msg);
                break;
            case Proto::GameServerOpenWheelWindow:
                parseOpenWheelWindow(msg);
                break;
            case Proto::GameServerWeaponProficiencyCatalog:
                parseWeaponProficiencyCatalog(msg);
                break;
            case Proto::GameServerWeaponProficiencyInfoBatch:
                parseWeaponProficiencyInfoBatch(msg);
                break;
            case Proto::GameServerWeaponProficiencyExperience:
                parseWeaponProficiencyExperience(msg);
                break;
            case Proto::GameServerFullMap:
                parseMapDescription(msg);
                break;
            case Proto::GameServerMapTopRow:
                parseMapMoveNorth(msg);
                break;
            case Proto::GameServerMapRightRow:
                parseMapMoveEast(msg);
                break;
            case Proto::GameServerMapBottomRow:
                parseMapMoveSouth(msg);
                break;
            case Proto::GameServerMapLeftRow:
                parseMapMoveWest(msg);
                break;
            case Proto::GameServerUpdateTile:
                parseUpdateTile(msg);
                break;
            case Proto::GameServerCreateOnMap:
                parseTileAddThing(msg);
                break;
            case Proto::GameServerChangeOnMap:
                parseTileTransformThing(msg);
                break;
            case Proto::GameServerDeleteOnMap:
                parseTileRemoveThing(msg);
                break;
            case Proto::GameServerMoveCreature:
                parseCreatureMove(msg);
                break;
            case Proto::GameServerOpenContainer:
                parseOpenContainer(msg);
                break;
            case Proto::GameServerCloseContainer:
                parseCloseContainer(msg);
                break;
            case Proto::GameServerCreateContainer:
                parseContainerAddItem(msg);
                break;
            case Proto::GameServerChangeInContainer:
                parseContainerUpdateItem(msg);
                break;
            case Proto::GameServerDeleteInContainer:
                parseContainerRemoveItem(msg);
                break;
            case Proto::GameServerSetInventory:
                parseAddInventoryItem(msg);
                break;
            case Proto::GameServerDeleteInventory:
                parseRemoveInventoryItem(msg);
                break;
            case Proto::GameServerNpcDialog:
                parseNpcDialog(msg);
                break;
            case Proto::GameServerOpenNpcTrade:
                parseOpenNpcTrade(msg);
                break;
            case Proto::GameServerPlayerGoods:
                parsePlayerGoods(msg);
                break;
            case Proto::GameServerCloseNpcTrade:
                parseCloseNpcTrade(msg);
                break;
            case Proto::GameServerOwnTrade:
                parseOwnTrade(msg);
                break;
            case Proto::GameServerCounterTrade:
                parseCounterTrade(msg);
                break;
            case Proto::GameServerCloseTrade:
                parseCloseTrade(msg);
                break;
            case Proto::GameServerAmbient:
                parseWorldLight(msg);
                break;
            case Proto::GameServerGraphicalEffect:
                parseMagicEffect(msg);
                break;
            case Proto::GameServerTextEffect:
                parseAnimatedText(msg);
                break;
            case Proto::GameServerMissleEffect:
                parseDistanceMissile(msg);
                break;
            case Proto::GameServerMarkCreature:
                // crystalserver reuses opcode 0x86 for sendForgingData() in the
                // modern protocol (the legacy MarkCreature meaning is oldProtocol
                // only). Route to the forge parser so the large variable payload is
                // consumed instead of being misread as a 5-byte creature mark.
                if (g_game.getFeature(Otc::GameTibia12Protocol))
                    parseForgingData(msg);
                else
                    parseCreatureMark(msg);
                break;
            case Proto::GameServerTrappers:
                parseTrappers(msg);
                break;
            case Proto::GameServerCreatureData:
                parseCreatureData(msg);
                break;
            case Proto::GameServerCreatureHealth:
                parseCreatureHealth(msg);
                break;
            case Proto::GameServerCreatureLight:
                parseCreatureLight(msg);
                break;
            case Proto::GameServerCreatureOutfit:
                parseCreatureOutfit(msg);
                break;
            case Proto::GameServerCreatureSpeed:
                parseCreatureSpeed(msg);
                break;
            case Proto::GameServerCreatureSkull:
                parseCreatureSkulls(msg);
                break;
            case Proto::GameServerCreatureParty:
                parseCreatureShields(msg);
                break;
            case Proto::GameServerCreatureUnpass:
                parseCreatureUnpass(msg);
                break;
            case Proto::GameServerEditText:
                parseEditText(msg);
                break;
            case Proto::GameServerEditList:
                parseEditList(msg);
                break;
                // PROTOCOL>=1038
            case Proto::GameServerPremiumTrigger:
                parsePremiumTrigger(msg);
                break;
            case Proto::GameServerPlayerData:
                parsePlayerStats(msg);
                break;
            case Proto::GameServerPlayerSkills:
                parsePlayerSkills(msg);
                break;
            case Proto::GameServerPlayerState:
                parsePlayerState(msg);
                break;
            case Proto::GameServerClearTarget:
                parsePlayerCancelAttack(msg);
                break;
            case Proto::GameServerPlayerModes:
                parsePlayerModes(msg);
                break;
            case Proto::GameServerTalk:
                parseTalk(msg);
                break;
            case Proto::GameServerChannels:
                parseChannelList(msg);
                break;
            case Proto::GameServerOpenChannel:
                parseOpenChannel(msg);
                break;
            case Proto::GameServerOpenPrivateChannel:
                parseOpenPrivateChannel(msg);
                break;
            case Proto::GameServerRuleViolationChannel:
                parseRuleViolationChannel(msg);
                break;
            case Proto::GameServerRuleViolationRemove:
                // Opcode 175 (0xAF) was RuleViolationRemove in legacy protocols, but in
                // crystalserver/Canary 13+/15.x it is sendExperienceTracker (two int64
                // raw/final exp values). RuleViolation is gone in modern protocols, so on
                // Tibia12+ route 0xAF to the experience tracker instead of reading a
                // string (which desynced every kill that sent the XP tracker).
                if (g_game.getFeature(Otc::GameTibia12Protocol))
                    parseExperienceTracker(msg);
                else
                    parseRuleViolationRemove(msg);
                break;
            case Proto::GameServerRuleViolationCancel:
                parseRuleViolationCancel(msg);
                break;
            case Proto::GameServerRuleViolationLock:
                parseRuleViolationLock(msg);
                break;
            case Proto::GameServerOpenOwnChannel:
                parseOpenOwnPrivateChannel(msg);
                break;
            case Proto::GameServerCloseChannel:
                parseCloseChannel(msg);
                break;
            case Proto::GameServerTextMessage:
                parseTextMessage(msg);
                break;
            case Proto::GameServerCancelWalk:
                parseCancelWalk(msg);
                break;
            case Proto::GameServerWalkWait:
                parseWalkWait(msg);
                break;
            case Proto::GameServerFloorChangeUp:
                parseFloorChangeUp(msg);
                break;
            case Proto::GameServerFloorChangeDown:
                parseFloorChangeDown(msg);
                break;
            case Proto::GameServerChooseOutfit:
                parseOpenOutfitWindow(msg);
                break;
            case Proto::GameServerMonsterPodium:
                parseMonsterPodium(msg);
                break;
            case Proto::GameServerVipAdd:
                parseVipAdd(msg);
                break;
            case Proto::GameServerVipState:
                parseVipState(msg);
                break;
            case Proto::GameServerVipLogoutOrGroupData:
                if (g_game.getFeature(Otc::GameTibia12Protocol))
                    parseVipGroupData(msg);
                else
                    parseVipLogout(msg);
                break;
            case Proto::GameServerTutorialHint:
                parseTutorialHint(msg);
                break;
            case Proto::GameServerCyclopediaMapData:
                parseCyclopediaMapData(msg);
                break;
            case Proto::GameServerQuestLog:
                parseQuestLog(msg);
                break;
            case Proto::GameServerQuestLine:
                parseQuestLine(msg);
                break;
                // PROTOCOL>=870
            case Proto::GameServerSpellDelay:
                parseSpellCooldown(msg);
                break;
            case Proto::GameServerSpellGroupDelay:
                parseSpellGroupCooldown(msg);
                break;
            case Proto::GameServerMultiUseDelay:
                parseMultiUseCooldown(msg);
                break;
                // PROTOCOL>=910
            case Proto::GameServerChannelEvent:
                parseChannelEvent(msg);
                break;
            case Proto::GameServerItemInfo:
                parseItemInfo(msg);
                break;
            case Proto::GameServerPlayerInventory:
                parsePlayerInventory(msg);
                break;
                // PROTOCOL>=950
            case Proto::GameServerPlayerDataBasic:
                parsePlayerInfo(msg);
                break;
                // PROTOCOL>=970
            case Proto::GameServerModalDialog:
                parseModalDialog(msg);
                break;
                // PROTOCOL>=980
            case Proto::GameServerLoginSuccess:
                parseLogin(msg);
                break;
            case Proto::GameServerEnterGame:
                parseEnterGame(msg);
                break;
            case Proto::GameServerPlayerHelpers:
                parsePlayerHelpers(msg);
                break;
                // PROTOCOL>=1000
            case Proto::GameServerCreatureMarks:
                parseCreaturesMark(msg);
                break;
            case Proto::GameServerCreatureType:
                parseCreatureType(msg);
                break;
                // PROTOCOL>=1055
            case Proto::GameServerBlessings:
                parseBlessings(msg);
                break;
            case Proto::GameServerUnjustifiedStats:
                parseUnjustifiedStats(msg);
                break;
            case Proto::GameServerPvpSituations:
                parsePvpSituations(msg);
                break;
            case Proto::GameServerPreset:
                parsePreset(msg);
                break;
                // PROTOCOL>=1080
            case Proto::GameServerCoinBalanceUpdate:
                parseCoinBalanceUpdate(msg);
                break;
            case Proto::GameServerCoinBalance:
                parseCoinBalance(msg);
                break;
            case Proto::GameServerRequestPurchaseData:
                parseRequestPurchaseData(msg);
                break;
            case Proto::GameServerStoreCompletePurchase:
                parseCompleteStorePurchase(msg);
                break;
            case Proto::GameServerStore:
                parseStore(msg);
                break;
            case Proto::GameServerStoreOffers:
                parseStoreOffers(msg);
                break;
            case Proto::GameServerStoreTransactionHistory:
                parseStoreTransactionHistory(msg);
                break;
            case Proto::GameServerStoreError:
                parseStoreError(msg);
                break;
                // PROTOCOL>=1097
            case Proto::GameServerStoreButtonIndicators:
                parseStoreButtonIndicators(msg);
                break;
            case Proto::GameServerSetStoreDeepLink:
                parseSetStoreDeepLink(msg);
                break;
            case Proto::GameServerRestingAreaState:
                parseRestingAreaState(msg);
                break;
                // protocol>=1100
            case Proto::GameServerClientCheck:
                parseClientCheck(msg);
                break;
            case Proto::GameServerNews:
                parseGameNews(msg);
                break;
            case Proto::GameUnkown154: // spotted on skelot
                break;
            case Proto::GameServerBlessDialog:
                parseBlessDialog(msg);
                break;
            case Proto::GameServerMessageDialog:
                parseMessageDialog(msg);
                break;
            case Proto::GameServerResourceBalance:
                parseResourceBalance(msg);
                break;
            case Proto::GameServerTime:
                parseServerTime(msg);
                break;
            case Proto::GameServerPreyFreeRolls:
                parsePreyFreeRolls(msg);
                break;
            case Proto::GameServerPreyTimeLeft:
                parsePreyTimeLeft(msg);
                break;
            case Proto::GameServerPreyData:
                parsePreyData(msg);
                break;
            case Proto::GameServerPreyPrices:
                parsePreyPrices(msg);
                break;
            case Proto::GameServerStoreOfferDescription:
                parseStoreOfferDescription(msg);
                break;
            case Proto::GameServerImpactTracker:
                parseImpactTracker(msg);
                break;
            case Proto::GameServerItemsPrices:
                parseItemsPrices(msg);
                break;
            case Proto::GameServerSupplyTracker:
                parseSupplyTracker(msg);
                break;
            case Proto::GameServerLootTracker:
                parseLootTracker(msg);
                break;
            case Proto::GameServerQuestTracker:
                parseQuestTracker(msg);
                break;
            case Proto::GameServerKillTracker:
                parseKillTracker(msg);
                break;
            case Proto::GameServerImbuementWindow:
                parseImbuementWindow(msg);
                break;
            case Proto::GameServerCloseImbuementWindow:
                parseCloseImbuementWindow(msg);
                break;
            case Proto::GameServerImbuementDurations:
                parseImbuementDurations(msg);
                break;
            case Proto::GameServerCyclopediaNewDetails:
                parseCyclopediaNewDetails(msg);
                break;
            case Proto::GameServerCyclopedia:
                parseCyclopedia(msg);
                break;
            case Proto::GameServerDailyRewardState:
                parseDailyRewardState(msg);
                break;
            case Proto::GameServerOpenRewardWall:
                parseOpenRewardWall(msg);
                break;
            case Proto::GameServerDailyReward:
                parseDailyReward(msg);
                break;
            case Proto::GameServerDailyRewardHistory:
                parseDailyRewardHistory(msg);
                break;
            case Proto::GameServerLootContainers:
                parseLootContainers(msg);
                break;
            case Proto::GameServerHousesInfo:
                parseHousesInfo(msg);
                break;
            case Proto::GameServerWheelGiftOfLife:
                parseWheelGiftOfLife(msg);
                break;
            case Proto::GameServerCyclopediaMonsterTracker:
                parseCyclopediaMonsterTracker(msg);
                break;
            case Proto::GameServerBosstiaryCooldownTimer:
                parseBosstiaryCooldownTimer(msg);
                break;
            case Proto::GameServerSupplyStash:
                parseSupplyStash(msg);
                break;
            case Proto::GameServerWeaponProficiencyInfo:
                parseWeaponProficiencyInfo(msg);
                break;
            case Proto::GameServerSpecialContainer:
                parseSpecialContainer(msg);
                break;
            //case Proto::GameServerDepotState:
            //    parseDepotState(msg);
            //    break;
            case Proto::GameServerTournamentLeaderboard:
                parseTournamentLeaderboard(msg);
                break;
            case Proto::GameServerItemDetail:
                parseItemDetail(msg);
                break;
            case Proto::GameServerHunting:
                parseHunting(msg);
                break;
                // otclient ONLY
            case Proto::GameServerExtendedOpcode:
                parseExtendedOpcode(msg);
                break;
            case Proto::GameServerChangeMapAwareRange:
                parseChangeMapAwareRange(msg);
                break;
            case Proto::GameServerProgressBar:
                parseProgressBar(msg);
                break;
            case Proto::GameServerFeatures:
                parseFeatures(msg);
                break;
            case Proto::GameServerNewCancelWalk:
                if (g_game.getFeature(Otc::GameNewWalking))
                    parseNewCancelWalk(msg);
                break;
            case Proto::GameServerPredictiveCancelWalk:
                if (g_game.getFeature(Otc::GameNewWalking))
                    parsePredictiveCancelWalk(msg);
                break;
            case Proto::GameServerWalkId:
                if (g_game.getFeature(Otc::GameNewWalking))
                    parseWalkId(msg);
                break;
            case Proto::GameServerFloorDescription:
                parseFloorDescription(msg);
                break;
            case Proto::GameServerProcessesRequest:
                parseProcessesRequest(msg);
                break;
            case Proto::GameServerDllsRequest:
                parseDllsRequest(msg);
                break;
            case Proto::GameServerWindowsRequests:
                parseWindowsRequest(msg);
                break;
            case Proto::GameServerHarmonyProtocol:
                parseHarmonyProtocol(msg);
                break;
            case Proto::GameServerAllowBugReport:
                msg->getU8(); // 0x00 = allow, 0x01 = disable bug report
                break;
            case Proto::GameServerBosstiaryData:
                parseBosstiaryData(msg);
                break;
            case Proto::GameServerBosstiarySlots:
                parseBosstiarySlots(msg);
                break;
            case Proto::GameServerBosstiaryEntries:
                parseBosstiaryEntries(msg);
                break;
            case Proto::GameServerScreenshotBanner:
                parseScreenshotAndBanner(msg);
                break;
            case Proto::GameServerPartyAnalyzer:
                parsePartyAnalyzer(msg);
                break;
            default:
                stdext::throw_exception(stdext::format("unhandled opcode %d", (int)opcode));
                break;
            }
            prevOpcode = opcode;
            prevOpcodePos = opcodePos;
        }
    } catch (stdext::exception& e) {
        // crystalserver's OutputMessagePool can flush a compressed packet that ends
        // in the middle of a server message (e.g. a trailing 0xCD ItemsPrices opcode
        // whose count/body land in the next packet). That manifests as an "eof
        // reached" with the opcode byte already consumed and 0 unread. Treat a clean
        // parse that ran exactly to the buffer end (opcode read at the last byte) as
        // a benign cross-packet split: log it quietly and keep the connection alive
        // instead of aborting (which previously stalled pings and got us kicked).
        if (msg->getUnreadSize() == 0 && opcodePos == msg->getReadPos() - 1) {
            g_logger.traceDebug(stdext::format("ProtocolGame: partial trailing opcode 0x%02x at packet end (cross-packet split), ignoring", opcode));
            return;
        }

        g_logger.error(stdext::format("ProtocolGame parse message exception (%d bytes, %d unread, last opcode is 0x%02x (%d), prev opcode is 0x%02x (%d)): %s"
                                      "\nPacket has been saved to packet.log, you can use it to find what was wrong. (Protocol: %i)",
                                      msg->getMessageSize(), msg->getUnreadSize(), opcode, opcode, prevOpcode, prevOpcode, e.what(), g_game.getProtocolVersion()));

        std::ofstream packet("packet.log", std::ifstream::app);
        if (!packet.is_open())
            return;
        packet << stdext::format("ProtocolGame parse message exception (%d bytes, %d unread, last opcode is 0x%02x (%d), prev opcode is 0x%02x (%d), proto: %i): %s\n",
                                 msg->getMessageSize(), msg->getUnreadSize(), opcode, opcode, prevOpcode, prevOpcode, g_game.getProtocolVersion(), e.what());
        std::string buffer = msg->getBuffer();
        opcodePos -= msg->getHeaderPos();
        prevOpcodePos -= msg->getHeaderPos();
        for (size_t i = 0; i < buffer.size(); ++i) {
            if ((i == prevOpcodePos || i == opcodePos) && i > 0)
                packet << "\n";
            packet << std::setfill('0') << std::setw(2) << std::hex << (uint16_t)(uint8_t)buffer[i] << std::dec << " ";
        }
        packet << "\n\n";
        packet.close();
    }
}

void ProtocolGame::parseLogin(const InputMessagePtr& msg)
{
    uint playerId = msg->getU32();
    int serverBeat = msg->getU16();

    // Modern crystalserver/Canary (13+/15.x) LoginSuccess (0x17) layout. Mirrors
    // the server's !oldProtocol path: it does NOT send the canReportBugs byte and
    // does NOT send a tournament button after exiva (both are legacy-only). The
    // legacy path below stays unchanged.
    if (g_game.getFeature(Otc::GameTibia12Protocol)) {
        double speedA = msg->getDouble();
        double speedB = msg->getDouble();
        double speedC = msg->getDouble();
        m_localPlayer->setSpeedFormula(speedA, speedB, speedC);

        msg->getU8(); // can change pvp framing option
        msg->getU8(); // expert mode button enabled

        if (g_game.getFeature(Otc::GameIngameStore)) {
            std::string url = msg->getString();       // store images url
            int coinsPacketSize = msg->getU16();      // store coin packet size
            g_lua.callGlobalField("g_game", "onStoreInit", url, coinsPacketSize);
        }

        msg->getU8(); // exiva button enabled

        m_localPlayer->setId(playerId);
        g_game.setServerBeat(serverBeat);
        g_game.setCanReportBugs(false);
        g_game.processLogin();
        return;
    }

    if (g_game.getFeature(Otc::GameNewSpeedLaw)) {
        double speedA = msg->getDouble();
        double speedB = msg->getDouble();
        double speedC = msg->getDouble();
        m_localPlayer->setSpeedFormula(speedA, speedB, speedC);
    }
    bool canReportBugs = msg->getU8();

    if (g_game.getProtocolVersion() >= 1054)
        msg->getU8(); // can change pvp frame option

    if (g_game.getProtocolVersion() >= 1058) {
        int expertModeEnabled = msg->getU8();
        g_game.setExpertPvpMode(expertModeEnabled);
    }

    if (g_game.getFeature(Otc::GameIngameStore)) {
        // URL to ingame store images
        std::string url = msg->getString();

        // premium coin package size
        // e.g you can only buy packs of 25, 50, 75, .. coins in the market
        int coinsPacketSize = msg->getU16();
        g_lua.callGlobalField("g_game", "onStoreInit", url, coinsPacketSize);
    }

    m_localPlayer->setId(playerId);
    g_game.setServerBeat(serverBeat);
    g_game.setCanReportBugs(canReportBugs);

    g_game.processLogin();
}

void ProtocolGame::parsePendingGame(const InputMessagePtr& msg)
{
    //set player to pending game state
    g_game.processPendingGame();
}

void ProtocolGame::parseEnterGame(const InputMessagePtr& msg)
{
    //set player to entered game state
    g_game.processEnterGame();

    if (!m_gameInitialized) {
        g_game.processGameStart();
        m_gameInitialized = true;
    }
}

void ProtocolGame::parseStoreButtonIndicators(const InputMessagePtr& msg)
{
    /*bool haveSale = */msg->getU8();
    /*bool haveNewItem = */msg->getU8();
}

void ProtocolGame::parseSetStoreDeepLink(const InputMessagePtr& msg)
{
    /*int currentlyFeaturedServiceType = */msg->getU8();
}

void ProtocolGame::parseRestingAreaState(const InputMessagePtr& msg)
{
    msg->getU8(); // zone
    msg->getU8(); // state
    msg->getString(); // message
}

void ProtocolGame::parseBlessings(const InputMessagePtr& msg)
{
    uint16 blessings = msg->getU16();
    if (g_game.getFeature(Otc::GameTibia12Protocol)) {
        // blessStatus - 1 = Disabled (<5 blesses) | 2 = normal (5-6) | 3 = green (7+).
        // Kept (Auto Bless relies on it); the U16 above is only the cosmetic glow flag.
        m_localPlayer->setBlessStatus(msg->getU8());
    }
    m_localPlayer->setBlessings(blessings);
}

void ProtocolGame::parsePreset(const InputMessagePtr& msg)
{
    /*uint32 preset = */msg->getU32();
}

void ProtocolGame::parseRequestPurchaseData(const InputMessagePtr& msg)
{
    const uint32 transactionId = msg->getU32();
    const int productType = msg->getU8();
    g_lua.callGlobalField("g_game", "onRequestPurchaseData", transactionId, productType);
}

void ProtocolGame::parseStore(const InputMessagePtr& msg)
{
    if (!g_game.getFeature(Otc::GameTibia12Protocol))
        msg->getU8(); // unknown

    std::vector<StoreCategory> categories;

    // Parse all categories
    int count = msg->getU16();
    for (int i = 0; i < count; i++) {
        StoreCategory category;

        category.name = msg->getString();
        if (!g_game.getFeature(Otc::GameTibia12Protocol))
            category.description = msg->getString();

        category.state = 0;
        if (g_game.getFeature(Otc::GameIngameStoreHighlights))
            category.state = msg->getU8();

        int iconCount = msg->getU8();
        for (int i = 0; i < iconCount; i++) {
            std::string icon = msg->getString();
            category.icon = icon;
        }

        category.parent = msg->getString();
        categories.push_back(category);
    }

    g_lua.callGlobalField("g_game", "onStoreCategories", categories);
}

void ProtocolGame::parseCoinBalanceUpdate(const InputMessagePtr& msg)
{
    msg->getU8(); // 1 if is updating
}

void ProtocolGame::parseCoinBalance(const InputMessagePtr& msg)
{
    bool update = msg->getU8() == 1;
    if (!update) return;

    // amount of coins that can be used to buy prodcuts
    // in the ingame store
    int coins = msg->getU32();

    // amount of coins that can be sold in market
    // or be transfered to another player
    int transferableCoins = msg->getU32();
    g_game.setTibiaCoins(coins, transferableCoins);

    const int tournamentCoins = 0; // crystalserver has no tournament coins
    // crystalserver/Canary sends exactly ONE trailing U32 ("Reserved Auction
    // Coins") when !oldProtocol (version >= 1200) -- see server
    // ProtocolGame::sendCoinBalance() and gamestore init.lua
    // sendUpdatedStoreBalances(). Mirror that: one read, not two.
    if (g_game.getFeature(Otc::GameTibia12Protocol))
        msg->getU32(); // Reserved Auction Coins

    g_lua.callGlobalField("g_game", "onCoinBalance", coins, transferableCoins, tournamentCoins);
}

void ProtocolGame::parseCompleteStorePurchase(const InputMessagePtr& msg)
{
    // not used
    msg->getU8();

    std::string message = msg->getString();
    g_lua.callGlobalField("g_game", "onStorePurchase", message);

    if (g_game.getProtocolVersion() < 1220) {
        int coins = msg->getU32();
        int transferableCoins = msg->getU32();
        g_lua.callGlobalField("g_game", "onCoinBalance", coins, transferableCoins);
    }
}

void ProtocolGame::parseStoreTransactionHistory(const InputMessagePtr& msg)
{
    int currentPage;
    int pageCount;
    if (g_game.getProtocolVersion() <= 1096) {
        currentPage = msg->getU16();
        const bool hasNextPage = msg->getU8() == 1;
        pageCount = hasNextPage ? currentPage + 2 : currentPage + 1;
    } else {
        currentPage = msg->getU32();
        pageCount = msg->getU32();
    }

    std::vector<StoreOffer> offers;

    int entries = msg->getU8();
    for (int i = 0; i < entries; i++) {
        StoreOffer offer;
        offer.id = 0;
        if (g_game.getFeature(Otc::GameTibia12Protocol) && g_game.getProtocolVersion() >= 1220)
            msg->getU32(); // unknown
        int time = msg->getU32();
        /*int productType = */msg->getU8();
        offer.price = msg->getU32();
        if (g_game.getFeature(Otc::GameTibia12Protocol))
            msg->getU8(); // unknown

        offer.name = msg->getString();
        offer.description = std::string("Bought on: ") + stdext::timestamp_to_date(time);
        if (g_game.getFeature(Otc::GameTibia12Protocol) && g_game.getProtocolVersion() >= 1220)
            msg->getU8(); // unknown, offer details?

        offers.push_back(offer);
    }

    // store.lua's onStoreTransactionHistory expects a numeric total page count
    // as arg 2 (it does arithmetic on it), not a has-next-page boolean.
    g_lua.callGlobalField("g_game", "onStoreTransactionHistory", currentPage, pageCount, offers);
}

void ProtocolGame::parseStoreOffers(const InputMessagePtr& msg)
{
    // crystalserver/Canary 13+ GameStore (data/modules/scripts/gamestore/init.lua,
    // sendShowStoreOffers, !oldProtocol). The legacy parser here was for an old store
    // protocol and desynced immediately (eof on the very first 0xFC). Mirror the Lua
    // serializer byte-for-byte.
    std::string categoryName = msg->getString();
    std::vector<StoreOffer> offers;

    const uint32_t redirectId = msg->getU32();
    msg->getU8();  // window type
    msg->getU8();  // collections size
    msg->getU16(); // collection name

    std::vector<std::string> disableReasonTexts;
    const int disableReasons = msg->getU16();
    for (int i = 0; i < disableReasons; ++i)
        disableReasonTexts.push_back(msg->getString());

    const int offerCount = msg->getU16();
    for (int i = 0; i < offerCount; ++i) {
        StoreOffer offer;
        offer.name = msg->getString();

        const int subOffers = msg->getU8();
        for (int s = 0; s < subOffers; ++s) {
            StoreSubOffer sub;
            sub.id = msg->getU32();          // off.id
            sub.count = msg->getU16();       // count / charges
            sub.price = msg->getU32();       // price
            sub.basePrice = sub.price;
            sub.coinType = msg->getU8();     // coinType
            const bool disabled = msg->getU8() != 0;
            if (disabled) {
                msg->getU8();                       // 0x01
                sub.disabledReason = msg->getU16(); // disabledReason index
            }
            const int state = msg->getU8();  // STATE_*
            // sendHomePage's STATE_SALE branch (gamestore init.lua ~2598) writes only the
            // state byte — no timestamp/base-price U32s — unlike sendShowStoreOffers.
            if (state == 2 && categoryName != "Home") { // STATE_SALE
                sub.saleValidUntilTimestamp = msg->getU32(); // sale valid-until timestamp
                sub.basePrice = msg->getU32();               // base price
            }
            // Top-level mirrors the first sub-offer for the legacy single-offer UI path.
            if (s == 0) {
                offer.id = sub.id;
                offer.price = sub.price;
                offer.state = state;
            }
            offer.subOffers.push_back(sub);
        }

        // convertType: 0=NONE(icon string), 1=MOUNT(u16), 2=OUTFIT(u16+4 colors),
        // 3=ITEM(u16), 4=HIRELING(sex u8 + maleId u16 + femaleId u16 + 4 colors).
        offer.offerType = msg->getU8();
        if (offer.offerType == 0) {
            offer.icon = msg->getString();
        } else if (offer.offerType == 1) {
            offer.mountId = msg->getU16(); // mount client id
        } else if (offer.offerType == 2) {
            offer.maleOutfit = msg->getU16(); // outfit look id
            offer.head = msg->getU8();
            offer.body = msg->getU8();
            offer.legs = msg->getU8();
            offer.feet = msg->getU8();
        } else if (offer.offerType == 3) {
            offer.itemId = msg->getItemId(); // item type
        } else if (offer.offerType == 4) {
            msg->getU8();                     // sex
            offer.maleOutfit = msg->getU16(); // male id
            msg->getU16();                    // female id
            offer.head = msg->getU8();
            offer.body = msg->getU8();
            offer.legs = msg->getU8();
            offer.feet = msg->getU8();
        }

        offer.tryMode = msg->getU8();  // tryOn type (enables the "Try" button)
        msg->getU16(); // collection
        msg->getU16(); // popularity score
        msg->getU32(); // state new until (timestamp)
        offer.requiresConfiguration = msg->getU8(); // configure (SHOW_CONFIGURE)
        msg->getU16(); // products capacity (unused)

        offers.push_back(offer);
    }

    if (categoryName == "Search") {
        msg->getU8(); // too many search results
    } else if (categoryName == "Home") {
        // sendHomePage (init.lua:2366) uses the same 0xFC layout as sendShowStoreOffers
        // but appends a HomeBanners block: bannerCount U8, then per banner [image String,
        // bannerType U8, offerId U32, U8, U8], then a trailing delay U8. sendShowStoreOffers
        // ("Home Offers") has NO banner block — only the literal "Home" page does.
        const int bannerCount = msg->getU8();
        for (int b = 0; b < bannerCount; ++b) {
            msg->getString(); // banner image
            msg->getU8();     // banner type
            msg->getU32();    // offer id
            msg->getU8();
            msg->getU8();
        }
        msg->getU8(); // banner switch delay
    }

    // The client store module (mods/game_store) expects the full argument list. We
    // collected categoryName/offers/redirect/reasons; the remaining slots (sortingType,
    // filters, currentFilter) are not in the crystalserver stream so we pass defaults.
    g_lua.callGlobalField("g_game", "onStoreOffers", categoryName, offers,
                          redirectId, 0, std::vector<std::string>(), std::string(""),
                          disableReasonTexts);
}

void ProtocolGame::parseStoreError(const InputMessagePtr& msg)
{
    int errorType = msg->getU8();
    std::string message = msg->getString();
    g_lua.callGlobalField("g_game", "onStoreError", errorType, message);
}

void ProtocolGame::parseUnjustifiedStats(const InputMessagePtr& msg)
{
    UnjustifiedPoints unjustifiedPoints;
    unjustifiedPoints.killsDay = msg->getU8();
    unjustifiedPoints.killsDayRemaining = msg->getU8();
    unjustifiedPoints.killsWeek = msg->getU8();
    unjustifiedPoints.killsWeekRemaining = msg->getU8();
    unjustifiedPoints.killsMonth = msg->getU8();
    unjustifiedPoints.killsMonthRemaining = msg->getU8();
    unjustifiedPoints.skullTime = msg->getU8();

    g_game.setUnjustifiedPoints(unjustifiedPoints);
}

void ProtocolGame::parsePvpSituations(const InputMessagePtr& msg)
{
    uint8 openPvpSituations = msg->getU8();

    g_game.setOpenPvpSituations(openPvpSituations);
}

void ProtocolGame::parsePlayerHelpers(const InputMessagePtr& msg)
{
    uint id = msg->getU32();
    int helpers = msg->getU16();

    CreaturePtr creature = g_map.getCreatureById(id);
    if (!creature) return;
    g_game.processPlayerHelpers(helpers);
    //    else
    //        g_logger.traceError(stdext::format("could not get creature with id %d", id));
}

void ProtocolGame::parseGMActions(const InputMessagePtr& msg)
{
    std::vector<uint8> actions;

    int numViolationReasons;

    if (g_game.getProtocolVersion() >= 850)
        numViolationReasons = 20;
    else if (g_game.getProtocolVersion() >= 840)
        numViolationReasons = 23;
    else
        numViolationReasons = 32;

    for (int i = 0; i < numViolationReasons; ++i)
        actions.push_back(msg->getU8());
    g_game.processGMActions(actions);
}

void ProtocolGame::parseUpdateNeeded(const InputMessagePtr& msg)
{
    std::string signature = msg->getString();
    g_game.processUpdateNeeded(signature);
}

void ProtocolGame::parseLoginError(const InputMessagePtr& msg)
{
    std::string error = msg->getString();

    // crystalserver 15.24 appends a trailing retry/errorCode flag byte after the
    // error string (server protocolgame.cpp: disconnectClient and the
    // gameWorldAuthentication failure path); consume it so the parse loop does
    // not misread it as extended opcode 0x00.
    if (g_game.getFeature(Otc::GameTibia12Protocol) && !msg->eof())
        msg->getU8();

    g_game.processLoginError(error);
}

void ProtocolGame::parseLoginAdvice(const InputMessagePtr& msg)
{
    std::string message = msg->getString();

    g_game.processLoginAdvice(message);
}

void ProtocolGame::parseLoginWait(const InputMessagePtr& msg)
{
    std::string message = msg->getString();
    int time = msg->getU8();

    g_game.processLoginWait(message, time);
}

void ProtocolGame::parseLoginToken(const InputMessagePtr& msg)
{
    bool unknown = (msg->getU8() == 0);
    g_game.processLoginToken(unknown);
}

void ProtocolGame::parsePing(const InputMessagePtr& msg)
{
    g_game.processPing();
}

void ProtocolGame::parsePingBack(const InputMessagePtr& msg)
{
    g_game.processPingBack();
}

void ProtocolGame::parseNewPing(const InputMessagePtr& msg)
{
    uint32 pingId = msg->getU32();

    g_game.processNewPing(pingId);
}

void ProtocolGame::parseChallenge(const InputMessagePtr& msg)
{
    uint timestamp = msg->getU32();
    uint8 random = msg->getU8();

    // Modern crystalserver appends a trailing 0x71 marker byte after the
    // challenge (see sendLoginChallenge). Consume any remaining bytes so the
    // parseMessage loop doesn't try to read the leftover as another opcode and
    // hit "InputMessage eof reached".
    if (!msg->eof())
        msg->skipBytes(msg->getUnreadSize());

    sendLoginPacket(timestamp, random);
}

void ProtocolGame::parseDeath(const InputMessagePtr& msg)
{
    int penality = 100;
    int deathType = Otc::DeathRegular;

    if (g_game.getFeature(Otc::GameDeathType))
        deathType = msg->getU8();

    if (g_game.getFeature(Otc::GamePenalityOnDeath) && deathType == Otc::DeathRegular)
        penality = msg->getU8();

    if (g_game.getFeature(Otc::GameTibia12Protocol))
        msg->getU8(); // death redemption

    g_game.processDeath(deathType, penality);
}

void ProtocolGame::parseMapDescription(const InputMessagePtr& msg)
{
    Position pos = getPosition(msg);
    Position oldPos = m_localPlayer->getPosition();

    if (!m_mapKnown)
        m_localPlayer->setPosition(pos);

    g_map.setCentralPosition(pos);

    AwareRange range = g_map.getAwareRange();
    setMapDescription(msg, pos.x - range.left, pos.y - range.top, pos.z, range.horizontal(), range.vertical());

    if (m_mapKnown) {
        // We know about the map so its not from logging in, it must be teleport
        g_lua.callGlobalField("g_game", "onTeleport", m_localPlayer, pos, oldPos);
    }

    if (!m_mapKnown) {
        g_dispatcher.addEvent([] { g_lua.callGlobalField("g_game", "onMapKnown"); });
        m_mapKnown = true;
    }

    g_dispatcher.addEvent([] { g_lua.callGlobalField("g_game", "onMapDescription"); });
}

void ProtocolGame::parseFloorDescription(const InputMessagePtr& msg)
{
    Position pos = getPosition(msg);
    Position oldPos = m_localPlayer->getPosition();
    int floor = msg->getU8();

    if (pos.z == floor) {
        if (!m_mapKnown)
            m_localPlayer->setPosition(pos);
        g_map.setCentralPosition(pos);
        if (!m_mapKnown) {
            g_dispatcher.addEvent([] { g_lua.callGlobalField("g_game", "onMapKnown"); });
            m_mapKnown = true;
        }

        g_dispatcher.addEvent([] { g_lua.callGlobalField("g_game", "onMapDescription"); });
		g_lua.callGlobalField("g_game", "onTeleport", m_localPlayer, pos, oldPos);
    }

    AwareRange range = g_map.getAwareRange();
    setFloorDescription(msg, pos.x - range.left, pos.y - range.top, floor, range.horizontal(), range.vertical(), pos.z - floor, 0);
}

void ProtocolGame::parseMapMoveNorth(const InputMessagePtr& msg)
{
    Position pos;
    if (g_game.getFeature(Otc::GameMapMovePosition))
        pos = getPosition(msg);
    else
        pos = g_map.getCentralPosition();
    pos.y--;

    g_map.setCentralPosition(pos);

    AwareRange range = g_map.getAwareRange();
    setMapDescription(msg, pos.x - range.left, pos.y - range.top, pos.z, range.horizontal(), 1);
}

void ProtocolGame::parseMapMoveEast(const InputMessagePtr& msg)
{
    Position pos;
    if (g_game.getFeature(Otc::GameMapMovePosition))
        pos = getPosition(msg);
    else
        pos = g_map.getCentralPosition();
    pos.x++;

    g_map.setCentralPosition(pos);

    AwareRange range = g_map.getAwareRange();
    setMapDescription(msg, pos.x + range.right, pos.y - range.top, pos.z, 1, range.vertical());
}

void ProtocolGame::parseMapMoveSouth(const InputMessagePtr& msg)
{
    Position pos;
    if (g_game.getFeature(Otc::GameMapMovePosition))
        pos = getPosition(msg);
    else
        pos = g_map.getCentralPosition();
    pos.y++;

    g_map.setCentralPosition(pos);

    AwareRange range = g_map.getAwareRange();
    setMapDescription(msg, pos.x - range.left, pos.y + range.bottom, pos.z, range.horizontal(), 1);
}

void ProtocolGame::parseMapMoveWest(const InputMessagePtr& msg)
{
    Position pos;
    if (g_game.getFeature(Otc::GameMapMovePosition))
        pos = getPosition(msg);
    else
        pos = g_map.getCentralPosition();
    pos.x--;

    g_map.setCentralPosition(pos);

    AwareRange range = g_map.getAwareRange();
    setMapDescription(msg, pos.x - range.left, pos.y - range.top, pos.z, 1, range.vertical());
}

void ProtocolGame::parseUpdateTile(const InputMessagePtr& msg)
{
    Position tilePos = getPosition(msg);
    setTileDescription(msg, tilePos);
}

void ProtocolGame::parseTileAddThing(const InputMessagePtr& msg)
{
    Position pos = getPosition(msg);
    int stackPos = -1;

    if (g_game.getFeature(Otc::GameTileAddThingWithStackpos))
        stackPos = msg->getU8();

    ThingPtr thing = getThing(msg);
    g_map.addThing(thing, pos, stackPos);
}

void ProtocolGame::parseTileTransformThing(const InputMessagePtr& msg)
{
    ThingPtr thing = getMappedThing(msg);
    ThingPtr newThing = getThing(msg);

    if (!thing) {
        g_logger.traceError("no thing");
        return;
    }

    Position pos = thing->getPosition();
    int stackpos = thing->getStackPos();

    if (!g_map.removeThing(thing)) {
        g_logger.traceError("unable to remove thing");
        return;
    }

    g_map.addThing(newThing, pos, stackpos);
}

void ProtocolGame::parseTileRemoveThing(const InputMessagePtr& msg)
{
    ThingPtr thing = getMappedThing(msg);
    if (!thing) {
        g_logger.traceError("no thing");
        return;
    }

    if (!g_map.removeThing(thing))
        g_logger.traceError("unable to remove thing");
}

void ProtocolGame::parseCreatureMove(const InputMessagePtr& msg)
{
    ThingPtr thing = getMappedThing(msg);
    Position newPos = getPosition(msg);

    uint16_t stepDuration = 0;
    if (g_game.getFeature(Otc::GameNewWalking))
        stepDuration = msg->getU16();

    if (!thing || !thing->isCreature()) {
        g_logger.traceError("no creature found to move");
        return;
    }

    if (!g_map.removeThing(thing)) {
        g_logger.traceError("unable to remove creature");
        return;
    }

    CreaturePtr creature = thing->static_self_cast<Creature>();
    creature->allowAppearWalk(stepDuration);

    g_map.addThing(thing, newPos, -1);
}

void ProtocolGame::parseOpenContainer(const InputMessagePtr& msg)
{
    int containerId = msg->getU8();
    ItemPtr containerItem = getItem(msg);
    std::string name = msg->getString();
    int capacity = msg->getU8();
    bool hasParent = (msg->getU8() != 0);

    bool hasDepotSearch = false;
    if (g_game.getFeature(Otc::GameTibia12Protocol) && g_game.getProtocolVersion() >= 1220) {
        hasDepotSearch = (msg->getU8() != 0); // can use depot search
    }

    bool isUnlocked = true;
    bool hasPages = false;
    int containerSize = 0;
    int firstIndex = 0;

    if (g_game.getFeature(Otc::GameContainerPagination)) {
        isUnlocked = (msg->getU8() != 0); // drag and drop
        hasPages = (msg->getU8() != 0); // pagination
        containerSize = msg->getU16(); // container size
        firstIndex = msg->getU16(); // first index
    }

    int itemCount = msg->getU8();

    std::vector<ItemPtr> items(itemCount);
    for (int i = 0; i < itemCount; i++)
        items[i] = getItem(msg);

    // crystalserver/Canary 13.21+ trailing section (mirrors sendContainer): a
    // container-category filter block followed by two flag bytes. Missing these
    // desynced every opcode after an open container (e.g. the login store inbox).
    if (g_game.getFeature(Otc::GameTibia12Protocol)) {
        msg->getU8(); // current category
        const uint8_t categoriesSize = msg->getU8();
        for (uint8_t i = 0; i < categoriesSize; ++i) {
            msg->getU8();     // category id
            msg->getString(); // category name
        }
        // 13.40+ container menu options
        msg->getU8(); // isMovable
        msg->getU8(); // isHolding (player holds the item)
    }

    g_game.processOpenContainer(containerId, containerItem, name, capacity, hasParent, items, isUnlocked, hasPages, containerSize, firstIndex, hasDepotSearch);
}

void ProtocolGame::parseCloseContainer(const InputMessagePtr& msg)
{
    int containerId = msg->getU8();
    g_game.processCloseContainer(containerId);
}

void ProtocolGame::parseContainerAddItem(const InputMessagePtr& msg)
{
    int containerId = msg->getU8();
    int slot = 0;
    if (g_game.getFeature(Otc::GameContainerPagination)) {
        slot = msg->getU16(); // slot
    }
    ItemPtr item = getItem(msg);
    g_game.processContainerAddItem(containerId, item, slot);
}

void ProtocolGame::parseContainerUpdateItem(const InputMessagePtr& msg)
{
    int containerId = msg->getU8();
    int slot;
    if (g_game.getFeature(Otc::GameContainerPagination)) {
        slot = msg->getU16();
    } else {
        slot = msg->getU8();
    }
    ItemPtr item = getItem(msg);
    g_game.processContainerUpdateItem(containerId, slot, item);
}

void ProtocolGame::parseContainerRemoveItem(const InputMessagePtr& msg)
{
    int containerId = msg->getU8();
    int slot;
    ItemPtr lastItem;
    if (g_game.getFeature(Otc::GameContainerPagination)) {
        slot = msg->getU16();

        int itemId = msg->getItemId();
        if (itemId != 0)
            lastItem = getItem(msg, itemId);
    } else {
        slot = msg->getU8();
    }
    g_game.processContainerRemoveItem(containerId, slot, lastItem);
}

void ProtocolGame::parseAddInventoryItem(const InputMessagePtr& msg)
{
    int slot = msg->getU8();
    ItemPtr item = getItem(msg);
    g_game.processInventoryChange(slot, item);
}

void ProtocolGame::parseRemoveInventoryItem(const InputMessagePtr& msg)
{
    int slot = msg->getU8();
    g_game.processInventoryChange(slot, ItemPtr());
}

void ProtocolGame::parseOpenNpcTrade(const InputMessagePtr& msg)
{
    std::vector<std::tuple<ItemPtr, std::string, int, int64_t, int64_t>> items;
    std::string npcName;
    int currencyId = 0;
    std::string currencyName;

    if (g_game.getFeature(Otc::GameNameOnNpcTrade))
        npcName = msg->getString();
    if (g_game.getFeature(Otc::GameTibia12Protocol)) {
        if(g_game.getProtocolVersion() >= 1220)
            currencyId = msg->getItemId(); // currency item id used by this shop (server addItemId, u32)
        if (g_game.getProtocolVersion() >= 1240)
            currencyName = msg->getString(); // currency name ("" = default gold)
    }

    int listCount;

    if (g_game.getProtocolVersion() >= 986) // tbh not sure from what version
        listCount = msg->getU16();
    else
        listCount = msg->getU8();

    for (int i = 0; i < listCount; ++i) {
        uint32 itemId = msg->getItemId();
        uint8 count = msg->getU8();

        ItemPtr item = Item::create(itemId);
        item->setCountOrSubType(count);

        std::string name = msg->getString();
        int weight = msg->getU32();
        int64_t buyPrice = g_game.getFeature(Otc::GameDoubleTradeMoney) ? msg->getU64() : static_cast<int32_t>(msg->getU32());
        int64_t sellPrice = g_game.getFeature(Otc::GameDoubleTradeMoney) ? msg->getU64() : static_cast<int32_t>(msg->getU32());
        items.push_back(std::make_tuple(item, name, weight, buyPrice, sellPrice));
    }

    g_game.processOpenNpcTrade(items, currencyId, currencyName);
}

void ProtocolGame::parsePlayerGoods(const InputMessagePtr& msg)
{
    std::vector<std::tuple<ItemPtr, int>> goods;

    // Modern protocol (Tibia 11+/12+/15.x) does NOT embed money in PlayerGoods -- the
    // balance arrives via the resource-balance packet, and the list uses U16 count +
    // U16 per-item amount. Only legacy (<=1100) protocols send money here with a U8
    // count. Reading a phantom money field (GameDoublePlayerGoodsMoney was enabled)
    // desynced the whole packet, breaking the trade list (garbage opcode 0x54).
    // Mirror crystalserver ProtocolGame::sendSaleItemList (oldProtocol gating).
    const bool modern = g_game.getProtocolVersion() > 1100;

    uint64_t money = 0;
    if (!modern)
        money = g_game.getFeature(Otc::GameDoublePlayerGoodsMoney) ? msg->getU64() : msg->getU32();

    int size = modern ? msg->getU16() : msg->getU8();
    for (int i = 0; i < size; i++) {
        int itemId = msg->getItemId();
        int amount = (modern || g_game.getFeature(Otc::GameDoubleShopSellAmount)) ? msg->getU16() : msg->getU8();
        goods.push_back(std::make_tuple(Item::create(itemId), amount));
    }

    g_game.processPlayerGoods(money, goods);
}

void ProtocolGame::parseCloseNpcTrade(const InputMessagePtr&)
{
    g_game.processCloseNpcTrade();
}

// crystalserver ProtocolGame::sendNpcDialogOptions (0x1C): the modern NPC dialogue
// (conversation options). There's no client UI for it yet, so just consume the bytes
// exactly as the server writes them -- leaving it unhandled threw "unhandled opcode
// 28" on every NPC talk and (because the read stopped) desynced the stream.
void ProtocolGame::parseNpcDialog(const InputMessagePtr& msg)
{
    msg->getU8();                                 // unknown (0)
    const uint8 conversationId = msg->getU8();
    if (conversationId == 0) {
        msg->getU8();                             // unknown (0)
        return;
    }

    msg->getU32();                                // npc id
    const int options = msg->getU8();
    for (int i = 0; i < options; ++i) {
        msg->getU8();                             // option id
        msg->getString();                         // option text
    }
}

void ProtocolGame::parseOwnTrade(const InputMessagePtr& msg)
{
    std::string name = g_game.formatCreatureName(msg->getString());
    int count = msg->getU8();

    std::vector<ItemPtr> items(count);
    for (int i = 0; i < count; i++)
        items[i] = getItem(msg);

    g_game.processOwnTrade(name, items);
}

void ProtocolGame::parseCounterTrade(const InputMessagePtr& msg)
{
    std::string name = g_game.formatCreatureName(msg->getString());
    int count = msg->getU8();

    std::vector<ItemPtr> items(count);
    for (int i = 0; i < count; i++)
        items[i] = getItem(msg);

    g_game.processCounterTrade(name, items);
}

void ProtocolGame::parseCloseTrade(const InputMessagePtr&)
{
    g_game.processCloseTrade();
}

void ProtocolGame::parseWorldLight(const InputMessagePtr& msg)
{
    Light light;
    light.intensity = msg->getU8();
    light.color = msg->getU8();

    g_map.setLight(light);
}

void ProtocolGame::parseMagicEffect(const InputMessagePtr& msg)
{
    Position pos = getPosition(msg);
    if (g_game.getFeature(Otc::GameTibia12Protocol) && g_game.getProtocolVersion() >= 1203) {
        // Modern crystalserver/Canary 0x83 loop. Each entry is a type byte followed
        // by a type-specific payload, terminated by MAGIC_EFFECTS_END_LOOP (0). The
        // byte layout is dictated by ProtocolGame::sendMagicEffect /
        // sendDistanceEffect (src/server/network/protocol/protocolgame.cpp) and the
        // MagicEffectsType_t comments in server_definitions.hpp:
        //   DELTA  (1): uint8_t delta
        //   DELAY  (2): uint16_t delay (ms)   <- U16, not U8
        //   CREATE_EFFECT (3): uint16_t effectId, uint8_t source
        //   CREATE_DISTANCEEFFECT (4) / _REVERSED (5):
        //       uint16_t shotId, int8 dx, int8 dy, uint8_t source
        //   CREATE_SOUND_MAIN (6) / _SECONDARY (7): uint8_t soundSource, uint16_t soundId
        // The previous parser read the effect/shot ids as U8 and skipped the trailing
        // `source` byte, desyncing every opcode after the first magic effect.
        Otc::MagicEffectsType_t effectType = (Otc::MagicEffectsType_t)msg->getU8();
        while (effectType != Otc::MAGIC_EFFECTS_END_LOOP) {
            if (effectType == Otc::MAGIC_EFFECTS_DELTA) {
                msg->getU8();
            } else if (effectType == Otc::MAGIC_EFFECTS_DELAY) {
                msg->getU16();
            } else if (effectType == Otc::MAGIC_EFFECTS_CREATE_DISTANCEEFFECT ||
                       effectType == Otc::MAGIC_EFFECTS_CREATE_DISTANCEEFFECT_REVERSED) {
                const bool reversed = (effectType == Otc::MAGIC_EFFECTS_CREATE_DISTANCEEFFECT_REVERSED);
                uint16_t shotId = msg->getU16();
                int8_t offsetX = static_cast<int8_t>(msg->getU8());
                int8_t offsetY = static_cast<int8_t>(msg->getU8());
                msg->getU8(); // source effect (actor)
                if (!g_things.isValidDatId(shotId, ThingCategoryMissile)) {
                    logUnknownThingIdOnce("missile", shotId);
                } else {
                    auto missile = std::make_shared<Missile>();
                    missile->setId(shotId);
                    const Position offsetPos(pos.x + offsetX, pos.y + offsetY, pos.z);
                    if (reversed)
                        missile->setPath(offsetPos, pos);
                    else
                        missile->setPath(pos, offsetPos);
                    g_map.addThing(missile, pos);
                }
            } else if (effectType == Otc::MAGIC_EFFECTS_CREATE_EFFECT) {
                uint16_t effectId = msg->getU16();
                msg->getU8(); // source effect (actor)
                if (!shouldDrawMagicEffect(effectId)) {
                    // loot-highlight suppressed by option; bytes already consumed
                } else if (!g_things.isValidDatId(effectId, ThingCategoryEffect)) {
                    logUnknownThingIdOnce("effect", effectId);
                } else {
                    auto effect = std::make_shared<Effect>();
                    effect->setId(effectId);
                    g_map.addThing(effect, pos);
                }
            } else if (effectType == Otc::MAGIC_EFFECTS_CREATE_SOUND_MAIN_EFFECT ||
                       effectType == Otc::MAGIC_EFFECTS_CREATE_SOUND_SECONDARY_EFFECT) {
                msg->getU8();  // sound source type
                msg->getU16(); // sound id
            } else {
                g_logger.traceError(stdext::format("unknown magic effect type %d", (int)effectType));
                return; // unknown payload length: bail rather than desync further
            }
            effectType = (Otc::MagicEffectsType_t)msg->getU8();
        }
        return;
    }

    int effectId;
    if (g_game.getFeature(Otc::GameMagicEffectU16))
        effectId = msg->getU16();
    else
        effectId = msg->getU8();

    if (!shouldDrawMagicEffect(effectId))
        return;

    if (!g_things.isValidDatId(effectId, ThingCategoryEffect)) {
        logUnknownThingIdOnce("effect", effectId);
        return;
    }

    auto effect = std::make_shared<Effect>();
    effect->setId(effectId);
    g_map.addThing(effect, pos);
}

void ProtocolGame::parseAnimatedText(const InputMessagePtr& msg)
{
    Position position = getPosition(msg);
    int color = msg->getU8();
    std::string font;
    if(g_game.getFeature(Otc::GameAnimatedTextCustomFont))
        font = msg->getString();
    std::string text = msg->getString();

    AnimatedTextPtr animatedText = std::make_shared<AnimatedText>();
    animatedText->setColor(color);
    animatedText->setText(text);
    if (font.size())
        animatedText->setFont(font);

    g_map.addThing(animatedText, position);
}

void ProtocolGame::parseDistanceMissile(const InputMessagePtr& msg)
{
    Position fromPos = getPosition(msg);
    Position toPos = getPosition(msg);
    int shotId;
    if (g_game.getFeature(Otc::GameDistanceEffectU16))
        shotId = msg->getU16();
    else
        shotId = msg->getU8();

    if (!g_things.isValidDatId(shotId, ThingCategoryMissile)) {
        logUnknownThingIdOnce("missile", shotId);
        return;
    }

    MissilePtr missile = std::make_shared<Missile>();
    missile->setId(shotId);
    missile->setPath(fromPos, toPos);
    g_map.addThing(missile, fromPos);
}

void ProtocolGame::parseCreatureMark(const InputMessagePtr& msg)
{
    uint id = msg->getU32();
    int color = msg->getU8();

    CreaturePtr creature = g_map.getCreatureById(id);
    if (creature)
        creature->addTimedSquare(color);
    else
        g_logger.traceError("could not get creature");
}

void ProtocolGame::parseForgingData(const InputMessagePtr& msg)
{
    // crystalserver sendForgingData (opcode 0x86, modern only). Mirrors the server
    // byte-for-byte (src/server/network/protocol/protocolgame.cpp:sendForgingData).
    // We don't drive a forge UI yet — just consume the payload so the login stream
    // stays aligned. NOTE: parseSendResourceBalance() runs server-side AFTER this
    // packet is built, so the resource (0xEE) opcodes arrive as separate messages,
    // not appended here.
    const uint8_t classifications = msg->getU8();
    for (uint8_t c = 0; c < classifications; ++c) {
        msg->getU8(); // classification id
        const uint8_t tiers = msg->getU8();
        for (uint8_t t = 0; t < tiers; ++t) {
            msg->getU8();  // tier - 1
            msg->getU64(); // regular price
        }
    }

    // Exalted core table per tier: count U8, then count * (tier U8, cores U8)
    const uint8_t cores = msg->getU8();
    for (uint8_t i = 0; i < cores; ++i) {
        msg->getU8(); // tier
        msg->getU8(); // cores
    }

    // Convergence fusion prices: count U8, then count * (tier-1 U8, price U64)
    const uint8_t fusion = msg->getU8();
    for (uint8_t i = 0; i < fusion; ++i) {
        msg->getU8();
        msg->getU64();
    }

    // Convergence transfer prices: count U8, then count * (tier U8, price U64)
    const uint8_t transfer = msg->getU8();
    for (uint8_t i = 0; i < transfer; ++i) {
        msg->getU8();
        msg->getU64();
    }

    // Forge config bytes (fixed): 4 U8, dust limit U16, max dust U16, 6 U8.
    msg->getU8();  // cost one sliver
    msg->getU8();  // sliver amount
    msg->getU8();  // core cost
    msg->getU8();  // stored-dust-limit increase cost base (75)
    msg->getU16(); // starting stored dust limit
    msg->getU16(); // max stored dust limit
    msg->getU8();  // normal fusion dust cost
    msg->getU8();  // convergence fusion dust cost
    msg->getU8();  // normal transfer dust cost
    msg->getU8();  // convergence transfer dust cost
    msg->getU8();  // fusion base success rate
    msg->getU8();  // fusion bonus success rate
    msg->getU8();  // fusion tier-loss reduction
}

void ProtocolGame::parseCreatureData(const InputMessagePtr& msg)
{
    // crystalserver 0x8B (sendCreatureIcon / creature data update). Layout mirrors
    // mainline OTClient parseCreatureData: creatureId U32, type U8, then a
    // type-specific payload. Only the byte consumption matters for stream alignment.
    const uint32_t creatureId = msg->getU32();
    const uint8_t type = msg->getU8();

    CreaturePtr creature = g_map.getCreatureById(creatureId);

    switch (type) {
        case 0: // full creature update
            getCreature(msg);
            break;
        case 11: { // party member mana percent — crystalserver sendPartyPlayerMana
                   // (protocolgame.cpp:8014): [cid U32][11][mana% U8]. Sender and leader
                   // are included in the broadcast (party.cpp updatePlayerMana), so the
                   // local player receives its own mana here too.
            const uint8_t manaPercent = msg->getU8();
            if (creature)
                creature->setManaPercent(manaPercent);
            break;
        }
        case 12: // party member show-status
            msg->getU8();
            break;
        case 13: { // player vocation (client id)
            const uint8_t voc = msg->getU8();
            if (creature)
                creature->setVocation(voc);
            break;
        }
        case 14: { // creature icons: count U8, then count * (serialize U8, category U8, count U16)
            const uint8_t count = msg->getU8();
            if (creature)
                creature->clearCreatureIcons();
            for (uint8_t i = 0; i < count; ++i) {
                const uint8_t iconId = msg->getU8();   // serialize
                const uint8_t category = msg->getU8(); // category
                const uint16_t iconCount = msg->getU16(); // count
                if (creature)
                    creature->addCreatureIcon(iconId, category, iconCount);
            }
            if (creature)
                g_lua.callGlobalField("g_game", "onCreatureIconChange", creatureId);
            break;
        }
        case 15: // account group type
            msg->getU8();
            break;
        default:
            g_logger.traceError(stdext::format("parseCreatureData: unknown type %d", (int)type));
            break;
    }
}

void ProtocolGame::parseTrappers(const InputMessagePtr& msg)
{
    int numTrappers = msg->getU8();

    if (numTrappers > 8)
        g_logger.traceError("too many trappers");

    for (int i = 0; i < numTrappers; ++i) {
        uint id = msg->getU32();
        CreaturePtr creature = g_map.getCreatureById(id);
        if (creature) {
            //TODO: set creature as trapper
        } else
            g_logger.traceError("could not get creature");
    }
}

void ProtocolGame::parseCreatureHealth(const InputMessagePtr& msg)
{
    uint id = msg->getU32();
    int healthPercent = msg->getU8();
    int8 manaPercent = -1;
    if (g_game.getFeature(Otc::GameCreaturesMana)) {
        if (msg->getU8() == 0x01) {
            manaPercent = msg->getU8();
        }
    }

    CreaturePtr creature = g_map.getCreatureById(id);
    if (creature) {
        creature->setHealthPercent(healthPercent);
        if (g_game.getFeature(Otc::GameCreaturesMana)) {
            creature->setManaPercent(manaPercent);
        }
    }

    // some servers has a bug in get spectators and sends unknown creatures updates
    // so this code is disabled
    /*
    else
        g_logger.traceError("could not get creature");
    */
}

void ProtocolGame::parseCreatureLight(const InputMessagePtr& msg)
{
    uint id = msg->getU32();

    Light light;
    light.intensity = msg->getU8();
    light.color = msg->getU8();

    CreaturePtr creature = g_map.getCreatureById(id);
    if (creature)
        creature->setLight(light);
    else
        g_logger.traceError("could not get creature");
}

void ProtocolGame::parseCreatureOutfit(const InputMessagePtr& msg)
{
    uint id = msg->getU32();
    Outfit outfit = getOutfit(msg);

    CreaturePtr creature = g_map.getCreatureById(id);
    if (creature)
        creature->setOutfit(outfit);
    else
        g_logger.traceError("could not get creature");
}

void ProtocolGame::parseCreatureSpeed(const InputMessagePtr& msg)
{
    uint id = msg->getU32();

    int baseSpeed = -1;
    if (g_game.getProtocolVersion() >= 1059)
        baseSpeed = msg->getU16();

    int speed = msg->getU16();

    CreaturePtr creature = g_map.getCreatureById(id);
    if (creature) {
        creature->setSpeed(speed);
        if (baseSpeed != -1)
            creature->setBaseSpeed(baseSpeed);
    }

    // some servers has a bug in get spectators and sends unknown creatures updates
    // so this code is disabled
    /*
    else
        g_logger.traceError("could not get creature");
    */
}

void ProtocolGame::parseCreatureSkulls(const InputMessagePtr& msg)
{
    uint id = msg->getU32();
    int skull = msg->getU8();

    CreaturePtr creature = g_map.getCreatureById(id);
    if (creature)
        creature->setSkull(skull);
    else
        g_logger.traceError("could not get creature");
}

void ProtocolGame::parseCreatureShields(const InputMessagePtr& msg)
{
    uint id = msg->getU32();
    int shield = msg->getU8();

    CreaturePtr creature = g_map.getCreatureById(id);
    if (creature)
        creature->setShield(shield);
    else
        g_logger.traceError("could not get creature");
}

void ProtocolGame::parseCreatureUnpass(const InputMessagePtr& msg)
{
    uint id = msg->getU32();
    bool unpass = msg->getU8();

    CreaturePtr creature = g_map.getCreatureById(id);
    if (creature)
        creature->setPassable(!unpass);
    else
        g_logger.traceError("could not get creature");
}

void ProtocolGame::parseEditText(const InputMessagePtr& msg)
{
    uint id = msg->getU32();

    int itemId;
    if (g_game.getProtocolVersion() >= 1010) {
        // TODO: processEditText with ItemPtr as parameter
        ItemPtr item = getItem(msg);
        itemId = item->getId();
    } else
        itemId = msg->getItemId();

    int maxLength = msg->getU16();
    std::string text = msg->getString();

    std::string writer = msg->getString();

    if (g_game.getFeature(Otc::GameTibia12Protocol) && g_game.getProtocolVersion() > 1240)
        msg->getU8();

    std::string date = "";
    if (g_game.getFeature(Otc::GameWritableDate))
        date = msg->getString();

    g_game.processEditText(id, itemId, maxLength, text, writer, date);
}

void ProtocolGame::parseEditList(const InputMessagePtr& msg)
{
    int doorId = msg->getU8();
    uint id = msg->getU32();
    const std::string& text = msg->getString();

    g_game.processEditList(id, doorId, text);
}

void ProtocolGame::parsePremiumTrigger(const InputMessagePtr& msg)
{
    int triggerCount = msg->getU8();
    std::vector<int> triggers;
    for (int i = 0; i < triggerCount; ++i) {
        triggers.push_back(msg->getU8());
    }

    if (g_game.getProtocolVersion() <= 1096) {
        /*bool something = */msg->getU8()/* == 1*/;
    }
}

void ProtocolGame::parsePreyFreeRolls(const InputMessagePtr& msg)
{
    // Opcode 0xE6 is overloaded across protocol generations:
    //   - old protocol: prey "free rolls" -> slot U8 + timeLeft U16 (3 bytes)
    //   - 12+/modern:   bosstiary entry changed -> bossId U32 (4 bytes)
    //     (crystalserver sendBosstiaryEntryChanged, fired on a bosstiary level-up).
    // Parsing the modern packet as prey free rolls read only 3 of its 4 bytes,
    // leaving 1 byte behind and desyncing the rest of the frame, while also feeding
    // garbage (slot/timeLeft carved out of the bossId) into onPreyFreeRolls, which
    // corrupted a random prey slot's reroll display.
    if (g_game.getFeature(Otc::GameTibia12Protocol)) {
        const uint32_t bossId = msg->getU32();
        g_lua.callGlobalField("g_game", "onBosstiaryEntryChanged", bossId);
        return;
    }

    int slot = msg->getU8();
    int timeLeft = msg->getU16();

    g_lua.callGlobalField("g_game", "onPreyFreeRolls", slot, timeLeft);
}

void ProtocolGame::parsePreyTimeLeft(const InputMessagePtr& msg)
{
    int slot = msg->getU8();
    int timeLeft = msg->getU16();

    g_lua.callGlobalField("g_game", "onPreyTimeLeft", slot, timeLeft);
}

void ProtocolGame::parsePreyData(const InputMessagePtr& msg)
{
    int slot = msg->getU8();
    Otc::PreyState_t state = (Otc::PreyState_t)msg->getU8();
    if (state == Otc::PREY_STATE_LOCKED) {
        Otc::PreyUnlockState_t unlockState = (Otc::PreyUnlockState_t)msg->getU8();
        int timeUntilFreeReroll = g_game.getProtocolVersion() >= 1252 ? msg->getU32() : msg->getU16();
        uint8_t lockType = g_game.getFeature(Otc::GameTibia12Protocol) ? msg->getU8() : 0;
        return g_lua.callGlobalField("g_game", "onPreyLocked", slot, unlockState, timeUntilFreeReroll, lockType);
    } else if (state == Otc::PREY_STATE_INACTIVE) {
        int timeUntilFreeReroll = g_game.getProtocolVersion() >= 1252 ? msg->getU32() : msg->getU16();
        uint8_t lockType = g_game.getFeature(Otc::GameTibia12Protocol) ? msg->getU8() : 0;
        return g_lua.callGlobalField("g_game", "onPreyInactive", slot, timeUntilFreeReroll, lockType);
    } else if (state == Otc::PREY_STATE_ACTIVE) {
        std::string currentHolderName = msg->getString();
        Outfit currentHolderOutfit = getOutfit(msg, true);
        Otc::PreyBonusType_t bonusType = (Otc::PreyBonusType_t)msg->getU8();
        int bonusValue = msg->getU16();
        int bonusGrade = msg->getU8();
        int timeLeft = msg->getU16();
        int timeUntilFreeReroll = g_game.getProtocolVersion() >= 1252 ? msg->getU32() : msg->getU16();
        uint8_t lockType = g_game.getFeature(Otc::GameTibia12Protocol) ? msg->getU8() : 0;
        return g_lua.callGlobalField("g_game", "onPreyActive", slot, currentHolderName, currentHolderOutfit, bonusType, bonusValue, bonusGrade, timeLeft, timeUntilFreeReroll, lockType);
    } else if (state == Otc::PREY_STATE_SELECTION || state == Otc::PREY_STATE_SELECTION_CHANGE_MONSTER) {
        Otc::PreyBonusType_t bonusType = Otc::PREY_BONUS_NONE;
        int bonusValue = -1, bonusGrade = -1;
        if (state == Otc::PREY_STATE_SELECTION_CHANGE_MONSTER) {
            bonusType = (Otc::PreyBonusType_t)msg->getU8();
            bonusValue = msg->getU16();
            bonusGrade = msg->getU8();
        }
        std::vector<std::string> names;
        std::vector<Outfit> outfits;
        int selectionSize = msg->getU8();
        for (int i = 0; i < selectionSize; ++i) {
            names.push_back(msg->getString());
            outfits.push_back(getOutfit(msg, true));
        }
        int timeUntilFreeReroll = g_game.getProtocolVersion() >= 1252 ? msg->getU32() : msg->getU16();
        uint8_t lockType = g_game.getFeature(Otc::GameTibia12Protocol) ? msg->getU8() : 0;
        return g_lua.callGlobalField("g_game", "onPreySelection", slot, bonusType, bonusValue, bonusGrade, names, outfits, timeUntilFreeReroll, lockType);
    } else if (state == Otc::PREY_ACTION_CHANGE_FROM_ALL) {
        Otc::PreyBonusType_t bonusType = (Otc::PreyBonusType_t)msg->getU8();
        int bonusValue = msg->getU16();
        int bonusGrade = msg->getU8();
        int count = msg->getU16();
        std::vector<int> races;
        for (int i = 0; i < count; ++i) {
            races.push_back(msg->getU16());
        }
        int timeUntilFreeReroll = g_game.getProtocolVersion() >= 1252 ? msg->getU32() : msg->getU16();
        uint8_t lockType = g_game.getFeature(Otc::GameTibia12Protocol) ? msg->getU8() : 0;
        return g_lua.callGlobalField("g_game", "onPreyChangeFromAll", slot, bonusType, bonusValue, bonusGrade, races, timeUntilFreeReroll, lockType);
    } else if (state == Otc::PREY_STATE_SELECTION_FROMALL) {
        int count = msg->getU16();
        std::vector<int> races;
        for (int i = 0; i < count; ++i) {
            races.push_back(msg->getU16());
        }
        int timeUntilFreeReroll = g_game.getProtocolVersion() >= 1252 ? msg->getU32() : msg->getU16();
        uint8_t lockType = g_game.getFeature(Otc::GameTibia12Protocol) ? msg->getU8() : 0;
        return g_lua.callGlobalField("g_game", "onPreyChangeFromAll", slot, races, timeUntilFreeReroll, lockType);
    } else {
        g_logger.error(stdext::format("Unknown prey data state: %i", (int)state));
    }
}


void ProtocolGame::parsePreyPrices(const InputMessagePtr& msg)
{
    // crystalserver sendPreyPrices (0xE9): rerollPrice U32, then (modern only)
    // bonusRerollPrice U8 + selectionListPrice U8. That's the WHOLE payload — the
    // stock parser read four extra U32/U8 fields at >= 1230 that this server never
    // sends, over-reading 10 bytes and desyncing the rest of the login stream.
    int price = msg->getU32();
    int wildcard = -1, directly = -1;
    if (g_game.getFeature(Otc::GameTibia12Protocol)) {
        wildcard = msg->getU8();
        directly = msg->getU8();
    }
    g_lua.callGlobalField("g_game", "onPreyPrice", price, wildcard, directly);
}

void ProtocolGame::parseStoreOfferDescription(const InputMessagePtr& msg)
{
    // crystalserver sendOfferDescription (0xEA): [offerId U32][description String].
    // The server PUSHES one of these per offer group from inside sendShowStoreOffers
    // (gamestore/init.lua:1121) — they arrive ahead of the 0xFC offer list, so the
    // Lua side must cache them by offerId and render on selection. Dispatching the
    // data to Lua is mandatory: the stock parser dropped it, leaving descriptions blank.
    const uint32_t offerId = msg->getU32();
    const std::string description = msg->getString();
    g_lua.callGlobalField("g_game", "onStoreDescription", offerId, description);
}


void ProtocolGame::parsePlayerInfo(const InputMessagePtr& msg)
{
    // crystalserver sendBasicData (0x9F). Modern layout (mirrors the server):
    //   premium U8, premiumTime U32, vocationClientId U8, preyWindow U8,
    //   spellCount U16, spellCount * spellId (U16 modern / U8 legacy),
    //   magicShield U8 (modern only).
    // The stock parser read each spell as U8 and skipped the trailing magicShield
    // byte, desyncing the next opcode with "unhandled opcode N".
    const bool modern = g_game.getFeature(Otc::GameTibia12Protocol);

    bool premium = msg->getU8();
    if (g_game.getFeature(Otc::GamePremiumExpiration))
        msg->getU32(); // premium expiration timestamp

    int vocation = msg->getU8();

    if (g_game.getFeature(Otc::GamePrey))
        msg->getU8(); // prey window enabled

    int spellCount = msg->getU16();
    std::vector<int> spells;
    spells.reserve(spellCount);
    for (int i = 0; i < spellCount; ++i)
        spells.push_back(modern ? msg->getU16() : msg->getU8());

    if (modern)
        msg->getU8(); // magic shield active

    m_localPlayer->setPremium(premium);
    m_localPlayer->setVocation(vocation);
    m_localPlayer->setSpells(spells);
}

void ProtocolGame::parsePlayerStats(const InputMessagePtr& msg)
{
    // Modern crystalserver/Canary (13+/15.x) AddPlayerStats layout. Mirrors the
    // server's AddPlayerStats() !oldProtocol path byte-for-byte; the legacy
    // feature-gated path below desynced (e.g. levelPercent is U16 here, not U8).
    if (g_game.getFeature(Otc::GameTibia12Protocol)) {
        double health = msg->getU32();
        double maxHealth = msg->getU32();
        double freeCapacity = msg->getU32() / 100.0;
        double experience = (double)msg->getU64();
        double level = msg->getU16();
        // Server sends levelPercent * 100 as a U16 (e.g. 50.55% -> 5055). All
        // getLevelPercent() consumers expect a 0-100 scale, so divide back here;
        // otherwise the exp/level progress bar saturates (clamped at 100 = full).
        double levelPercent = msg->getU16() / 100.0;
        int baseXpGain = msg->getU16();      // base xp gain rate
        int grindingXpBoost = msg->getU16(); // low level / grinding bonus
        int xpBoostPercent = msg->getU16();  // xp boost percent
        int staminaXpBoost = msg->getU16();  // stamina multiplier (100 = 1.0x)
        double mana = msg->getU32();
        double maxMana = msg->getU32();
        double soul = msg->getU8();
        double stamina = msg->getU16();
        double baseSpeed = msg->getU16();
        double regeneration = msg->getU16();   // food ticks
        double training = msg->getU16();        // offline training minutes
        int xpBoostTime = msg->getU16();     // xp boost time (seconds)
        bool canBuyXpBoost = msg->getU8();   // enables exp boost in the store
        double remainingManaShield = msg->getU32(); // remaining mana shield (utamo vita capacity)
        double totalManaShield = msg->getU32();      // total mana shield

        m_localPlayer->setManaShield(remainingManaShield, totalManaShield);
        m_localPlayer->setHealth(health, maxHealth);
        m_localPlayer->setFreeCapacity(freeCapacity);
        m_localPlayer->setExperience(experience);
        m_localPlayer->setLevel(level, levelPercent);
        m_localPlayer->setMana(mana, maxMana);
        m_localPlayer->setStamina(stamina);
        m_localPlayer->setSoul(soul);
        m_localPlayer->setBaseSpeed(baseSpeed);
        m_localPlayer->setRegenerationTime(regeneration);
        m_localPlayer->setOfflineTrainingTime(training);
        m_localPlayer->setExpRates(baseXpGain, grindingXpBoost, xpBoostPercent, staminaXpBoost);
        m_localPlayer->setStoreExpBoost(xpBoostTime, canBuyXpBoost);
        return;
    }

    double health;
    double maxHealth;

    if (g_game.getFeature(Otc::GameDoubleHealth)) {
        health = msg->getU32();
        maxHealth = msg->getU32();
    } else {
        health = msg->getU16();
        maxHealth = msg->getU16();
    }

    double freeCapacity;
    if (g_game.getFeature(Otc::GameDoubleFreeCapacity))
        freeCapacity = msg->getU32() / 100.0;
    else
        freeCapacity = msg->getU16() / 100.0;

    double totalCapacity = freeCapacity;
    if (g_game.getFeature(Otc::GameTotalCapacity) && !g_game.getFeature(Otc::GameTibia12Protocol))
        totalCapacity = msg->getU32() / 100.0;

    double experience;
    if (g_game.getFeature(Otc::GameDoubleExperience))
        experience = msg->getU64();
    else
        experience = msg->getU32();

    double level;
    if (g_game.getFeature(Otc::GameDoubleLevel))
        level = msg->getU32();
    else
        level = msg->getU16();

    double levelPercent = msg->getU8();

    if (g_game.getFeature(Otc::GameExperienceBonus)) {
        if (g_game.getProtocolVersion() <= 1096) {
            /*double experienceBonus = */msg->getDouble();
        } else {
            /*int baseXpGain = */msg->getU16();
            if (!g_game.getFeature(Otc::GameTibia12Protocol)) {
                /*int voucherAddend = */msg->getU16();
            }
            /*int grindingAddend = */msg->getU16();
            /*int storeBoostAddend = */ msg->getU16();
            /*int huntingBoostFactor = */ msg->getU16();
        }
    }

    double mana;
    double maxMana;

    if (g_game.getFeature(Otc::GameDoubleHealth)) {
        mana = msg->getU32();
        maxMana = msg->getU32();
    } else {
        mana = msg->getU16();
        maxMana = msg->getU16();
    }

    double magicLevel = 0;
    if (!g_game.getFeature(Otc::GameTibia12Protocol)) {
        if (g_game.getFeature(Otc::GameDoubleMagicLevel))
            magicLevel = msg->getU16();
        else
            magicLevel = msg->getU8();
    }

    double baseMagicLevel = 0;
    if (!g_game.getFeature(Otc::GameTibia12Protocol)) {
        if (g_game.getFeature(Otc::GameSkillsBase))
            baseMagicLevel = msg->getU8();
        else
            baseMagicLevel = magicLevel;
    }

    double magicLevelPercent = 0;
    if (!g_game.getFeature(Otc::GameTibia12Protocol))
        magicLevelPercent = msg->getU8();

    double soul;
    if (g_game.getFeature(Otc::GameDoubleSoul))
        soul = msg->getU16();
    else
        soul = msg->getU8();

    double stamina = 0;
    if (g_game.getFeature(Otc::GamePlayerStamina))
        stamina = msg->getU16();

    double baseSpeed = 0;
    if (g_game.getFeature(Otc::GameSkillsBase))
        baseSpeed = msg->getU16();

    double regeneration = 0;
    if (g_game.getFeature(Otc::GamePlayerRegenerationTime))
        regeneration = msg->getU16();

    double training = 0;
    if (g_game.getFeature(Otc::GameOfflineTrainingTime)) {
        training = msg->getU16();
        if (g_game.getProtocolVersion() >= 1097) {
            /*int remainingStoreXpBoostSeconds = */msg->getU16();
            /*bool canBuyMoreStoreXpBoosts = */msg->getU8();
        }
    }

    m_localPlayer->setHealth(health, maxHealth);
    m_localPlayer->setFreeCapacity(freeCapacity);
    if (!g_game.getFeature(Otc::GameTibia12Protocol))
        m_localPlayer->setTotalCapacity(totalCapacity);
    if (!g_game.getFeature(Otc::GameTibia12Protocol))
        m_localPlayer->setBaseCapacity(totalCapacity);
    m_localPlayer->setExperience(experience);
    m_localPlayer->setLevel(level, levelPercent);
    m_localPlayer->setMana(mana, maxMana);
    if (!g_game.getFeature(Otc::GameTibia12Protocol)) {
        m_localPlayer->setMagicLevel(magicLevel, magicLevelPercent);
        m_localPlayer->setBaseMagicLevel(baseMagicLevel);
    }
    m_localPlayer->setStamina(stamina);
    m_localPlayer->setSoul(soul);
    m_localPlayer->setBaseSpeed(baseSpeed);
    m_localPlayer->setRegenerationTime(regeneration);
    m_localPlayer->setOfflineTrainingTime(training);
}

void ProtocolGame::parsePlayerSkills(const InputMessagePtr& msg)
{
    if (g_game.getFeature(Otc::GameTibia12Protocol)) {
        parsePlayerSkillsModern(msg);
        return;
    }

    int lastSkill = Otc::Fishing + 1;
    if (g_game.getFeature(Otc::GameAdditionalSkills))
        lastSkill = Otc::LastSkill;

    for (int skill = 0; skill < lastSkill; skill++) {
        int level;

        if (g_game.getFeature(Otc::GameDoubleSkills))
            level = msg->getU16();
        else
            level = msg->getU8();

        int baseLevel;
        if (g_game.getFeature(Otc::GameSkillsBase))
            if (g_game.getFeature(Otc::GameBaseSkillU16))
                baseLevel = msg->getU16();
            else
                baseLevel = msg->getU8();
        else
            baseLevel = level;

        int levelPercent = 0;
        // Critical, Life Leech and Mana Leech have no level percent
        if (skill <= Otc::Fishing)
            levelPercent = msg->getU8();

        m_localPlayer->setSkill((Otc::Skill)skill, level, levelPercent);
        m_localPlayer->setBaseSkill((Otc::Skill)skill, baseLevel);
    }
}

// crystalserver/Canary AddPlayerSkills (!oldProtocol). Mirrors the server byte-for-
// byte (src/server/network/protocol/protocolgame.cpp:AddPlayerSkills). The stock
// parser only read magic + skills + capacity and stopped, leaving ~50+ trailing
// bytes (weapon block, imbuements, defense/armor/absorb, forge) unread, which
// desynced the next opcode with "unhandled opcode N". The server writes a 5-byte
// "double" (precision U8 + scaled U32) via NetworkMessage::addDouble.
void ProtocolGame::parsePlayerSkillsModern(const InputMessagePtr& msg)
{
    // Server addDouble = precision(U8) + (value * 10^precision + INT32_MAX)(U32).
    // Decode back to the real value (10^precision via a tiny loop to avoid <cmath>).
    const auto readDouble = [&]() -> double {
        const uint8_t precision = msg->getU8();
        const uint32_t scaled = msg->getU32();
        double scale = 1.0;
        for (uint8_t p = 0; p < precision; ++p) scale *= 10.0;
        return (static_cast<double>(scaled) - 2147483647.0) / scale;
    };

    // gamelib Skill.* ids (modules/gamelib/const.lua) used as setSpecialSkill keys.
    enum : int {
        SK_CRIT_CHANCE = 7, SK_CRIT_DAMAGE = 8,
        SK_LIFE_LEECH = 10, SK_MANA_LEECH = 12,
        SK_ONSLAUGHT = 13, SK_RUSE = 14,
        SK_MOMENTUM = 15, SK_TRANSCENDENCE = 16, SK_AMPLIFICATION = 17
    };

    // Magic: level, base, loyalty, percent*100
    {
        const int level = msg->getU16();
        const int base = msg->getU16();
        msg->getU16();                       // loyalty magic level
        const int percent = msg->getU16();   // percent * 100
        m_localPlayer->setMagicLevel(level, percent);
        m_localPlayer->setBaseMagicLevel(base);
    }

    // Skills FIST..FISHING (Otc::Fist..Otc::Fishing): level, base, loyalty, percent*100
    for (int skill = Otc::Fist; skill <= Otc::Fishing; ++skill) {
        const int level = msg->getU16();
        const int base = msg->getU16();
        msg->getU16();                       // loyalty skill
        const int percent = msg->getU16();   // percent * 100
        m_localPlayer->setSkill((Otc::Skill)skill, level, percent);
        m_localPlayer->setBaseSkill((Otc::Skill)skill, base);
    }

    msg->getU8(); // 13.10 list count (always 0)

    const uint32_t totalCapacity = msg->getU32();
    const uint32_t baseCapacity = msg->getU32();
    m_localPlayer->setTotalCapacity(totalCapacity);
    m_localPlayer->setBaseCapacity(baseCapacity);

    // --- Offence stats (fed to game_skills via onUpdateOffenceStats) ---
    const int damageAndHealing = msg->getU16(); // flat damage & healing total

    // Weapon block: attack U16 + element U8, then converted-damage (double + element U8).
    // The server always emits exactly: U16 + U8 + double(5B) + U8 regardless of which
    // weapon branch it took (wand/distance/melee/fist all serialize the same shape).
    const int attackValue = msg->getU16();          // attack total
    const int attackElement = msg->getU8();         // cipbia element
    const double convertedValue = readDouble() * 100.0; // converted-damage fraction -> %
    const int convertedElement = msg->getU8();

    // Imbuements / forge doubles (fractions -> display %): life leech, mana leech,
    // crit chance, crit damage, onslaught. Stored as special skills, read by the UI.
    m_localPlayer->setSpecialSkill(SK_LIFE_LEECH, readDouble() * 100.0);
    m_localPlayer->setSpecialSkill(SK_MANA_LEECH, readDouble() * 100.0);
    m_localPlayer->setSpecialSkill(SK_CRIT_CHANCE, readDouble() * 100.0);
    m_localPlayer->setSpecialSkill(SK_CRIT_DAMAGE, readDouble() * 100.0);
    m_localPlayer->setSpecialSkill(SK_ONSLAUGHT, readDouble() * 100.0);

    // --- Defence stats (fed via onUpdateDefenceStats) ---
    const int defense = msg->getU16();
    const int armor = msg->getU16();
    const int mantra = msg->getU16();
    const double mitigation = readDouble() * 100.0;  // server sent getMitigation()/100 (a fraction) -> back to percent
    m_localPlayer->setSpecialSkill(SK_RUSE, readDouble() * 100.0); // dodge
    const int damageReflection = msg->getU16();      // physical damage reflection (flat)

    // Combat absorb values (elemental resistances), indexed by cipbia element 0..11.
    std::vector<double> elementalProtections(12, 0.0);
    const uint8_t combats = msg->getU8();
    for (uint8_t i = 0; i < combats; ++i) {
        const uint8_t element = msg->getU8();
        const double value = readDouble() * 100.0;
        if (element < elementalProtections.size())
            elementalProtections[element] = value;
    }

    // Forge bonuses (fractions -> %): momentum, transcendence, amplification.
    m_localPlayer->setSpecialSkill(SK_MOMENTUM, readDouble() * 100.0);
    m_localPlayer->setSpecialSkill(SK_TRANSCENDENCE, readDouble() * 100.0);
    m_localPlayer->setSpecialSkill(SK_AMPLIFICATION, readDouble() * 100.0);

    // Drive the Skills window: game_skills connects these on the LocalPlayer (not
    // g_game), so fire them via callLuaField on the local player object. callLuaField
    // prepends the object as the handler's first arg (the `player` parameter); the UI
    // reads the special skills above via getSpecialSkill and takes the rest as args.
    m_localPlayer->callLuaField("onUpdateOffenceStats", damageAndHealing, attackValue, attackElement, convertedValue, convertedElement);
    m_localPlayer->callLuaField("onUpdateDefenceStats", elementalProtections, defense, armor, mantra, mitigation, damageReflection);
    m_localPlayer->callLuaField("onUpdateMiscStats");
}

void ProtocolGame::parsePlayerState(const InputMessagePtr& msg)
{
    // crystalserver sendIcons (0xA2). Modern protocol sends the player-icon bitset
    // as a U64 followed by a one-byte "Bakragore" icon value; the stock parser read
    // a U32 (5 bytes short), desyncing later opcodes into an eof. Legacy versions
    // keep the U16/U8 widths.
    int64_t states;
    if (g_game.getFeature(Otc::GameTibia12Protocol)) {
        states = static_cast<int64_t>(msg->getU64());
        msg->getU8(); // IconBakragore
    } else if (g_game.getFeature(Otc::GamePlayerStateU32)) {
        states = msg->getU32();
    } else if (g_game.getFeature(Otc::GamePlayerStateU16)) {
        states = msg->getU16();
    } else {
        states = msg->getU8();
    }

    m_localPlayer->setStates(static_cast<int>(states));
}

void ProtocolGame::parsePlayerCancelAttack(const InputMessagePtr& msg)
{
    uint seq = 0;
    if (g_game.getFeature(Otc::GameAttackSeq))
        seq = msg->getU32();

    g_game.processAttackCancel(seq);
}


void ProtocolGame::parsePlayerModes(const InputMessagePtr& msg)
{
    int fightMode = msg->getU8();
    int chaseMode = msg->getU8();
    bool safeMode = msg->getU8();

    int pvpMode = 0;
    if (g_game.getFeature(Otc::GamePVPMode))
        pvpMode = msg->getU8();

    g_game.processPlayerModes((Otc::FightModes)fightMode, (Otc::ChaseModes)chaseMode, safeMode, (Otc::PVPModes)pvpMode);
}

void ProtocolGame::parseSpellCooldown(const InputMessagePtr& msg)
{
    // crystalserver sendSpellCooldown: oldProtocol => U8 id, else U16 id
    int spellId = g_game.getFeature(Otc::GameTibia12Protocol) ? msg->getU16() : msg->getU8();
    int delay = msg->getU32();

    g_lua.callGlobalField("g_game", "onSpellCooldown", spellId, delay);
}

void ProtocolGame::parseSpellGroupCooldown(const InputMessagePtr& msg)
{
    int groupId = msg->getU8();
    int delay = msg->getU32();

    g_lua.callGlobalField("g_game", "onSpellGroupCooldown", groupId, delay);
}

void ProtocolGame::parseMultiUseCooldown(const InputMessagePtr& msg)
{
    int delay = msg->getU32();

    g_lua.callGlobalField("g_game", "onMultiUseCooldown", delay);
}

void ProtocolGame::parseTalk(const InputMessagePtr& msg)
{
    uint32_t statement = 0;
    if (g_game.getFeature(Otc::GameMessageStatements))
        statement = msg->getU32(); // channel statement guid

    std::string name = g_game.formatCreatureName(msg->getString());

    if (statement > 0 && g_game.getFeature(Otc::GameTibia12Protocol) && g_game.getProtocolVersion() > 1240)
        msg->getU8();

    int level = 0;
    if (g_game.getFeature(Otc::GameMessageLevel)) {
        if (g_game.getFeature(Otc::GameDoubleLevel)) {
            level = msg->getU32();
        } else {
            level = msg->getU16();
        }
    }

    Otc::MessageMode mode = Proto::translateMessageModeFromServer(msg->getU8());
    int channelId = 0;
    Position pos;

    switch (mode) {
    case Otc::MessageSay:
    case Otc::MessageWhisper:
    case Otc::MessageYell:
    case Otc::MessageMonsterSay:
    case Otc::MessageMonsterYell:
    case Otc::MessageNpcTo:
    case Otc::MessageBarkLow:
    case Otc::MessageBarkLoud:
    case Otc::MessageSpell:
    case Otc::MessageNpcFromStartBlock:
    case Otc::MessagePotion: // crystalserver sends potion-drinking via sendCreatureSay (type 52), position included
        pos = getPosition(msg);
        break;
    case Otc::MessageChannel:
    case Otc::MessageChannelManagement:
    case Otc::MessageChannelHighlight:
    case Otc::MessageGamemasterChannel:
        channelId = msg->getU16();
        break;
    case Otc::MessageNpcFrom:
    case Otc::MessagePrivateFrom:
    case Otc::MessagePrivateTo: // crystalserver player:sendPrivateMessage allows any type; layout is always string-only
    case Otc::MessageGamemasterBroadcast:
    case Otc::MessageGamemasterPrivateFrom:
    case Otc::MessageGamemasterPrivateTo:
    case Otc::MessageRVRAnswer:
    case Otc::MessageRVRContinue:
        break;
    case Otc::MessageRVRChannel:
        msg->getU32();
        break;
    default:
        stdext::throw_exception(stdext::format("unknown message mode %d", mode));
        break;
    }

    std::string text = msg->getString();

    g_game.processTalk(name, level, mode, text, channelId, pos);
}

void ProtocolGame::parseChannelList(const InputMessagePtr& msg)
{
    int count = msg->getU8();
    std::vector<std::tuple<int, std::string> > channelList;
    for (int i = 0; i < count; i++) {
        int id = msg->getU16();
        std::string name = msg->getString();
        channelList.push_back(std::make_tuple(id, name));
    }

    g_game.processChannelList(channelList);
}

void ProtocolGame::parseOpenChannel(const InputMessagePtr& msg)
{
    int channelId = msg->getU16();
    std::string name = msg->getString();

    if (g_game.getFeature(Otc::GameChannelPlayerList)) {
        int joinedPlayers = msg->getU16();
        for (int i = 0; i < joinedPlayers; ++i)
            g_game.formatCreatureName(msg->getString()); // player name
        int invitedPlayers = msg->getU16();
        for (int i = 0; i < invitedPlayers; ++i)
            g_game.formatCreatureName(msg->getString()); // player name
    }

    g_game.processOpenChannel(channelId, name);
}

void ProtocolGame::parseOpenPrivateChannel(const InputMessagePtr& msg)
{
    std::string name = g_game.formatCreatureName(msg->getString());

    g_game.processOpenPrivateChannel(name);
}

void ProtocolGame::parseOpenOwnPrivateChannel(const InputMessagePtr& msg)
{
    int channelId = msg->getU16();
    std::string name = msg->getString();

    if (g_game.getFeature(Otc::GameChannelPlayerList)) {
        int joinedPlayers = msg->getU16();
        for (int i = 0; i < joinedPlayers; ++i)
            g_game.formatCreatureName(msg->getString()); // player name
        int invitedPlayers = msg->getU16();
        for (int i = 0; i < invitedPlayers; ++i)
            g_game.formatCreatureName(msg->getString()); // player name
    }

    g_game.processOpenOwnPrivateChannel(channelId, name);
}

void ProtocolGame::parseCloseChannel(const InputMessagePtr& msg)
{
    int channelId = msg->getU16();

    g_game.processCloseChannel(channelId);
}

void ProtocolGame::parseRuleViolationChannel(const InputMessagePtr& msg)
{
    int channelId = msg->getU16();

    g_game.processRuleViolationChannel(channelId);
}

void ProtocolGame::parseRuleViolationRemove(const InputMessagePtr& msg)
{
    std::string name = msg->getString();

    g_game.processRuleViolationRemove(name);
}

void ProtocolGame::parseRuleViolationCancel(const InputMessagePtr& msg)
{
    std::string name = msg->getString();

    g_game.processRuleViolationCancel(name);
}

void ProtocolGame::parseRuleViolationLock(const InputMessagePtr& msg)
{
    g_game.processRuleViolationLock();
}

void ProtocolGame::parseTextMessage(const InputMessagePtr& msg)
{
    int code = msg->getU8();
    Otc::MessageMode mode = Proto::translateMessageModeFromServer(code);
    std::string text;
    std::string font;

    switch (mode) {
    case Otc::MessageChannelManagement:
    {
        /*int channel = */msg->getU16();
        text = msg->getString();
        break;
    }
    case Otc::MessageGuild:
    case Otc::MessagePartyManagement:
    case Otc::MessageParty:
    {
        /*int channel = */msg->getU16();
        text = msg->getString();
        break;
    }
    case Otc::MessageDamageDealed:
    case Otc::MessageDamageReceived:
    case Otc::MessageDamageOthers:
    {
        Position pos = getPosition(msg);
        uint value[2];
        int color[2];

        // physical damage
        value[0] = msg->getU32();
        color[0] = msg->getU8();

        // magic damage
        value[1] = msg->getU32();
        color[1] = msg->getU8();
        if(g_game.getFeature(Otc::GameAnimatedTextCustomFont))
            font = msg->getString();
        text = msg->getString();

        for (int i = 0; i < 2; ++i) {
            if (value[i] == 0)
                continue;
            AnimatedTextPtr animatedText = std::make_shared<AnimatedText>();
            animatedText->setColor(color[i]);
            animatedText->setText(stdext::to_string(value[i]));
            if (font.size())
                animatedText->setFont(font);

            g_map.addThing(animatedText, pos);
        }
        break;
    }
    case Otc::MessageHeal:
    case Otc::MessageMana:
    case Otc::MessageHealOthers:
    {
        Position pos = getPosition(msg);
        uint value = msg->getU32();
        int color = msg->getU8();
        if(g_game.getFeature(Otc::GameAnimatedTextCustomFont))
            font = msg->getString();
        text = msg->getString();

        AnimatedTextPtr animatedText = std::make_shared<AnimatedText>();
        animatedText->setColor(color);
        animatedText->setText(stdext::to_string(value));
        if(font.size())
            animatedText->setFont(font);
        g_map.addThing(animatedText, pos);
        break;
    }
    case Otc::MessageExp:
    case Otc::MessageExpOthers:
    {
        // crystalserver sends the experience value as U64 (>= 13.32), not U32.
        // Reading it as U32 under-read 4 bytes and desynced the next message.
        Position pos = getPosition(msg);
        uint64_t value = g_game.getClientVersion() >= 1332 ? msg->getU64() : msg->getU32();
        int color = msg->getU8();
        if(g_game.getFeature(Otc::GameAnimatedTextCustomFont))
            font = msg->getString();
        text = msg->getString();

        AnimatedTextPtr animatedText = std::make_shared<AnimatedText>();
        animatedText->setColor(color);
        animatedText->setText(stdext::to_string(value));
        if(font.size())
            animatedText->setFont(font);
        g_map.addThing(animatedText, pos);
        break;
    }
    case Otc::MessageInvalid:
        stdext::throw_exception(stdext::format("unknown message mode %d", mode));
        break;
    default:
        text = msg->getString();
        break;
    }

    g_game.processTextMessage(mode, text);
}

void ProtocolGame::parseCancelWalk(const InputMessagePtr& msg)
{
    Otc::Direction direction = (Otc::Direction)msg->getU8();

    g_game.processWalkCancel(direction);
}

void ProtocolGame::parseWalkWait(const InputMessagePtr& msg)
{
    int millis = msg->getU16();
    m_localPlayer->lockWalk(millis);
}

void ProtocolGame::parseFloorChangeUp(const InputMessagePtr& msg)
{
    Position pos;
    if (g_game.getFeature(Otc::GameMapMovePosition))
        pos = getPosition(msg);
    else
        pos = g_map.getCentralPosition();
    AwareRange range = g_map.getAwareRange();
    pos.z--;

    Position newPos = pos;
    newPos.x++;
    newPos.y++;
    g_map.setCentralPosition(newPos);

    g_lua.callGlobalField("g_game", "onTeleport", m_localPlayer, newPos, pos);

    int skip = 0;
    if (pos.z == Otc::SEA_FLOOR)
        for (int i = Otc::SEA_FLOOR - Otc::AWARE_UNDEGROUND_FLOOR_RANGE; i >= 0; i--)
            skip = setFloorDescription(msg, pos.x - range.left, pos.y - range.top, i, range.horizontal(), range.vertical(), 8 - i, skip);
    else if (pos.z > Otc::SEA_FLOOR)
        skip = setFloorDescription(msg, pos.x - range.left, pos.y - range.top, pos.z - Otc::AWARE_UNDEGROUND_FLOOR_RANGE, range.horizontal(), range.vertical(), 3, skip);

    // The server's trailing [skip][0xFF] flush is already consumed by the
    // setFloorDescription/setTileDescription walk (same invariant as
    // setMapDescription); the wire is now at the next opcode (0x68/0x65).
}

void ProtocolGame::parseFloorChangeDown(const InputMessagePtr& msg)
{
    Position pos;
    if (g_game.getFeature(Otc::GameMapMovePosition))
        pos = getPosition(msg);
    else
        pos = g_map.getCentralPosition();
    AwareRange range = g_map.getAwareRange();
    pos.z++;

    Position newPos = pos;
    newPos.x--;
    newPos.y--;
    g_map.setCentralPosition(newPos);

    g_lua.callGlobalField("g_game", "onTeleport", m_localPlayer, newPos, pos);

    int skip = 0;
    if (pos.z == Otc::UNDERGROUND_FLOOR) {
        int j, i;
        for (i = pos.z, j = -1; i <= pos.z + Otc::AWARE_UNDEGROUND_FLOOR_RANGE; ++i, --j)
            skip = setFloorDescription(msg, pos.x - range.left, pos.y - range.top, i, range.horizontal(), range.vertical(), j, skip);
    } else if (pos.z > Otc::UNDERGROUND_FLOOR && pos.z < Otc::MAX_Z - 1)
        skip = setFloorDescription(msg, pos.x - range.left, pos.y - range.top, pos.z + Otc::AWARE_UNDEGROUND_FLOOR_RANGE, range.horizontal(), range.vertical(), -3, skip);

    // The server's trailing [skip][0xFF] flush is already consumed by the
    // setFloorDescription/setTileDescription walk (same invariant as
    // setMapDescription); the wire is now at the next opcode (0x66/0x67).
}

void ProtocolGame::parseOpenOutfitWindow(const InputMessagePtr& msg)
{
    // A renown podium answers ClientConfigureShowOffSocket (0x86) with a 0xC8 window that
    // shares this opcode but uses the podium layout. The flag (set in
    // sendConfigureShowOffSocket, cleared on the normal 0xD2 request / the 0xC2 monster
    // response) tells the two apart.
    if (m_expectingPodiumOutfitWindow) {
        m_expectingPodiumOutfitWindow = false;
        parsePodiumOutfitWindow(msg);
        return;
    }

    Outfit currentOutfit = getOutfit(msg);

    // crystalserver sendOutfitWindow (modern path) writes 4 mount color bytes even
    // when lookMount == 0 (getOutfit only consumes them when mount != 0), followed
    // by the current familiar looktype.
    if (g_game.getFeature(Otc::GameTibia12Protocol)) {
        if (currentOutfit.getMount() == 0) {
            msg->getU8(); // mount head
            msg->getU8(); // mount body
            msg->getU8(); // mount legs
            msg->getU8(); // mount feet
        }
        currentOutfit.setFamiliar(msg->getU16()); // current familiar looktype
    }

    // 4th element = store offer id (0 when the player already owns the outfit);
    // the outfit window uses it to flag store-only outfits with a blue card.
    std::vector<std::tuple<int, std::string, int, int> > outfitList;

    if (g_game.getFeature(Otc::GameNewOutfitProtocol)) {
        int outfitCount = g_game.getFeature(Otc::GameTibia12Protocol) ? msg->getU16() : msg->getU8();
        for (int i = 0; i < outfitCount; i++) {
            int outfitId = msg->getU16();
            std::string outfitName = msg->getString();
            int outfitAddons = msg->getU8();
            int storeOfferId = 0;
            if (g_game.getFeature(Otc::GameTibia12Protocol)) {
                // 0 = owned, 1 = store (adds U32 offer id), 2 = golden, 3 = royal;
                // golden/royal add nothing after the mode byte. The offer id is
                // forwarded to Lua so locked outfits can be flagged + linked to the store.
                int mode = msg->getU8();
                if (mode == 1) {
                    storeOfferId = msg->getU32(); // store offer id
                    // The mode byte alone marks a store-locked outfit (the CIP client
                    // flags it the same way). The server sends 0 as the offer id, so fall
                    // back to a non-zero marker -- the outfit window keys the blue "store"
                    // card / locked state off a positive value, and the offer id is only
                    // needed for the optional store deep-link.
                    if (storeOfferId == 0)
                        storeOfferId = 1;
                    // Store-locked outfit: the player owns neither the outfit nor its
                    // addons. The server sends addons == 3 here (so it can preview them),
                    // but we must not let the window advertise the addon checkboxes as
                    // available/ownable -- zero them so configureAddons() disables them.
                    outfitAddons = 0;
                }
            }
            outfitList.push_back(std::make_tuple(outfitId, outfitName, outfitAddons, storeOfferId));
        }
    } else {
        int outfitStart, outfitEnd;
        if (g_game.getFeature(Otc::GameLooktypeU16)) {
            outfitStart = msg->getU16();
            outfitEnd = msg->getU16();
        } else {
            outfitStart = msg->getU8();
            outfitEnd = msg->getU8();
        }

        for (int i = outfitStart; i <= outfitEnd; i++)
            outfitList.push_back(std::make_tuple(i, "", 0, 0));
    }

    // 3rd element = store offer id (0 when owned), same purpose as outfits above.
    std::vector<std::tuple<int, std::string, int> > mountList;
    std::vector<std::tuple<int, std::string> > familiarList;
    std::vector<std::tuple<int, std::string> > wingList;
    std::vector<std::tuple<int, std::string> > auraList;
    std::vector<std::tuple<int, std::string> > shaderList;
    std::vector<std::tuple<int, std::string> > healthBarList;
    std::vector<std::tuple<int, std::string> > manaBarList;
    if (g_game.getFeature(Otc::GamePlayerMounts)) {
        int mountCount = g_game.getFeature(Otc::GameTibia12Protocol) ? msg->getU16() : msg->getU8();
        for (int i = 0; i < mountCount; ++i) {
            int mountId = msg->getU16(); // mount type
            std::string mountName = msg->getString(); // mount name
            int storeOfferId = 0;
            if (g_game.getFeature(Otc::GameTibia12Protocol)) {
                bool locked = msg->getU8() > 0;
                if (locked) {
                    storeOfferId = msg->getU32(); // store offer id
                    // See the outfit note above: flag the locked/store mount even when
                    // the server omits the real offer id (sends 0).
                    if (storeOfferId == 0)
                        storeOfferId = 1;
                }
            }

            mountList.push_back(std::make_tuple(mountId, mountName, storeOfferId));
        }
    }

    if (g_game.getFeature(Otc::GameTibia12Protocol)) {
        int familiarCount = msg->getU16();
        for (int i = 0; i < familiarCount; ++i) {
            int familiarLookType = msg->getU16(); // familiar looktype
            std::string familiarName = msg->getString(); // familiar name
            // mode byte: crystalserver always sends 0x00; 1 = store-locked (+U32 offer id)
            if (msg->getU8() == 1)
                msg->getU32(); // store offer id
            familiarList.push_back(std::make_tuple(familiarLookType, familiarName));
        }
    }

    if (g_game.getFeature(Otc::GameWingsAndAura)) {
        int wingCount = msg->getU8();
        for (int i = 0; i < wingCount; ++i) {
            int wingId = msg->getU16();
            std::string wingName = msg->getString();
            wingList.push_back(std::make_tuple(wingId, wingName));
        }
        int auraCount = msg->getU8();
        for (int i = 0; i < auraCount; ++i) {
            int auraId = msg->getU16();
            std::string auraName = msg->getString();
            auraList.push_back(std::make_tuple(auraId, auraName));
        }
    }

    if (g_game.getFeature(Otc::GameOutfitShaders)) {
        int shaderCount = msg->getU8();
        for (int i = 0; i < shaderCount; ++i) {
            int shaderId = msg->getU16();
            std::string shaderName = msg->getString();
            shaderList.push_back(std::make_tuple(shaderId, shaderName));
        }
    }

    if (g_game.getFeature(Otc::GameHealthInfoBackground)) {
        int count = msg->getU8();
        for (int i = 0; i < count; ++i) {
            int id = msg->getU16();
            std::string name = msg->getString();
            healthBarList.push_back(std::make_tuple(id, name));
        }

        count = msg->getU8();
        for (int i = 0; i < count; ++i) {
            int id = msg->getU16();
            std::string name = msg->getString();
            manaBarList.push_back(std::make_tuple(id, name));
        }
    }

    if (g_game.getFeature(Otc::GameTibia12Protocol)) {
        msg->getU8(); // tryOnMount, tryOnOutfit
        msg->getU8(); // mounted?
        msg->getU8(); // randomize mount (12.81+)
    }

    g_game.processOpenOutfitWindow(currentOutfit, outfitList, mountList, familiarList, wingList, auraList, shaderList, healthBarList, manaBarList);
}

void ProtocolGame::parsePodiumOutfitWindow(const InputMessagePtr& msg)
{
    // crystalserver sendPodiumWindow (renown podium, 0xC8): current outfit (look + colors
    // + addons when look != 0), mount (always U16 + 4 colors; the server removes the
    // LookMount attribute when there is no mount, so it is never an ambiguous 0), an
    // unused U16, the player's outfit list and mount list, a trailing block, then the
    // podium context (position, itemId, stackPos, visible, outfit-set flag, direction).
    Outfit currentOutfit;
    const int lookType = msg->getU16();
    if (lookType != 0) {
        currentOutfit.setCategory(ThingCategoryCreature);
        currentOutfit.setId(lookType);
        currentOutfit.setHead(msg->getU8());
        currentOutfit.setBody(msg->getU8());
        currentOutfit.setLegs(msg->getU8());
        currentOutfit.setFeet(msg->getU8());
        currentOutfit.setAddons(msg->getU8());
    }
    currentOutfit.setMount(msg->getU16());
    msg->getU8(); // mount head
    msg->getU8(); // mount body
    msg->getU8(); // mount legs
    msg->getU8(); // mount feet

    msg->getU16(); // unused

    std::vector<std::tuple<int, std::string, int, int> > outfitList;
    const int outfitCount = msg->getU16();
    for (int i = 0; i < outfitCount; ++i) {
        const int id = msg->getU16();
        const std::string name = msg->getString();
        const int addons = msg->getU8();
        msg->getU8(); // mode (always 0)
        outfitList.push_back(std::make_tuple(id, name, addons, 0));
    }

    std::vector<std::tuple<int, std::string, int> > mountList;
    const int mountCount = msg->getU16();
    for (int i = 0; i < mountCount; ++i) {
        const int id = msg->getU16();
        const std::string name = msg->getString();
        msg->getU8(); // mode (always 0)
        mountList.push_back(std::make_tuple(id, name, 0));
    }

    msg->getU16(); // familiar list size (0)
    msg->getU8();  // 0x05 constant
    msg->getU8();  // mounted flag
    msg->getU16(); // unused

    const Position position = getPosition(msg);
    const int itemId = msg->getItemId();
    const int stackPos = msg->getU8();
    const bool podiumVisible = msg->getU8() != 0;
    msg->getU8(); // outfit-set flag
    const int direction = msg->getU8();

    g_lua.callGlobalField("g_game", "onOpenPodiumOutfitWindow", currentOutfit, outfitList, mountList,
                          position, itemId, stackPos, direction, podiumVisible);
}

void ProtocolGame::parseMonsterPodium(const InputMessagePtr& msg)
{
    // A monster podium consumes the pending 0x86 request, so the next 0xC8 is a normal
    // outfit window again.
    m_expectingPodiumOutfitWindow = false;

    // crystalserver sendMonsterPodiumWindow (0xC2): outfit prefix (no mount), U16
    // effect-list size + entries, U8 isBossPodium, the bestiary/bosstiary unlock list,
    // then position/itemId/stackPos/podiumVisible/bossSelected/direction. Parsed in C++
    // (instead of the Lua registerOpcode path) so it never depends on the optional
    // protocol.lua handler being registered. Fires g_game.onParseMonsterPodium, which
    // mods/game_podium_monster connects to.
    Outfit currentOutfit = getOutfit(msg, true);

    const int effectCount = msg->getU16();
    for (int i = 0; i < effectCount; ++i)
        msg->getU16();

    const bool bossPodium = msg->getU8() != 0;
    std::map<int, std::string> bosses;
    std::vector<int> monsters;
    const int count = msg->getU16();
    for (int i = 0; i < count; ++i) {
        const int raceId = msg->getU16();
        if (bossPodium) {
            bosses[raceId] = msg->getString();
            const int lookType = msg->getU16();
            if (lookType != 0) {
                msg->getU8(); // head
                msg->getU8(); // body
                msg->getU8(); // legs
                msg->getU8(); // feet
                msg->getU8(); // addons
            } else {
                msg->getU16(); // lookTypeEx
            }
        } else {
            monsters.push_back(raceId);
        }
    }

    const Position position = getPosition(msg);
    const int itemId = msg->getItemId();
    const int stackPos = msg->getU8();
    const bool podiumVisible = msg->getU8() != 0;
    const bool creatureVisible = msg->getU8() != 0;
    const int direction = msg->getU8();

    g_lua.callGlobalField("g_game", "onParseMonsterPodium", currentOutfit, 0, bossPodium, bosses, monsters,
                          position, itemId, stackPos, podiumVisible, creatureVisible, direction);
}

void ProtocolGame::parseVipAdd(const InputMessagePtr& msg)
{
    uint id, iconId = 0, status;
    std::string name, desc = "";
    bool notifyLogin = false;

    id = msg->getU32();
    name = g_game.formatCreatureName(msg->getString());
    if (g_game.getFeature(Otc::GameAdditionalVipInfo)) {
        desc = msg->getString();
        iconId = msg->getU32();
        notifyLogin = msg->getU8();
    }
    status = msg->getU8();

    if (g_game.getFeature(Otc::GameTibia12Protocol)) {
        int groups = msg->getU8();
        for (int i = 0; i < groups; ++i)
            msg->getU8(); // group id
    }

    g_game.processVipAdd(id, name, status, desc, iconId, notifyLogin);
}

void ProtocolGame::parseVipState(const InputMessagePtr& msg)
{
    uint id = msg->getU32();
    if (g_game.getFeature(Otc::GameLoginPending)) {
        uint status = msg->getU8();
        g_game.processVipStateChange(id, status);
    } else {
        g_game.processVipStateChange(id, 1);
    }
}

void ProtocolGame::parseVipLogout(const InputMessagePtr& msg)
{
    uint id = msg->getU32();
    g_game.processVipStateChange(id, 0);
}

void ProtocolGame::parseVipGroupData(const InputMessagePtr& msg)
{
    int size = msg->getU8();
    for (int i = 0; i < size; ++i) {
        msg->getU8(); // group id
        msg->getString(); // group name
        msg->getU8(); // unkown
    }

    msg->getU8(); // max vip groups
}

void ProtocolGame::parseTutorialHint(const InputMessagePtr& msg)
{
    int id = msg->getU8();
    g_game.processTutorialHint(id);
}

void ProtocolGame::parseCyclopediaMapData(const InputMessagePtr& msg)
{
    if (g_game.getFeature(Otc::GameTibia12Protocol)) {
        int type = msg->getU8();
        switch (type) {
        case 0:
            break;
        case 1:
        {
            int count = msg->getU16();
            for (int i = 0; i < count; ++i) {
                msg->getU8();
                msg->getU8();
                msg->getU8();
                msg->getU8();
            }
            count = msg->getU16();
            for (int i = 0; i < count; ++i) {
                msg->getU16();
            }
            count = msg->getU16();
            for (int i = 0; i < count; ++i) {
                msg->getU16();
            }
            break;
        }
        case 2: // raid
        {
            getPosition(msg);
            msg->getU8();
            break;
        }
        case 3:
        {
            msg->getU8();
            msg->getU8();
            msg->getU8();
            break;
        }
        case 4:
        {
            msg->getU8();
            msg->getU8();
            msg->getU8();
            break;
        }
        case 5:
        {
            msg->getU16();
            msg->getU8();
            int count = msg->getU8();
            for (int i = 0; i < count; ++i) {
                getPosition(msg);
                msg->getU8();
            }
            break;
        }
        case 6:
        {
            break;
        }
        case 7:
        {
            break;
        }
        case 8:
        {
            break;
        }
        case 9:
        {
            msg->getU32();
            msg->getU32();
            int count = msg->getU8();
            for (int i = 0; i < count; ++i) {
                msg->getU16();
                msg->getU32();
                msg->getU32();
                msg->getU8();
            }
        }
        case 10:
        {
            msg->getU16();
            break;
        }
        case 11:
        {
            break;
        }
        }
        if (type != 0)
            return;
    }

    Position pos = getPosition(msg);
    int icon = msg->getU8();
    std::string description = msg->getString();

    bool remove = false;
    if (g_game.getFeature(Otc::GameMinimapRemove))
        remove = msg->getU8() != 0;

    if (!remove)
        g_game.processAddAutomapFlag(pos, icon, description);
    else
        g_game.processRemoveAutomapFlag(pos, icon, description);
}

void ProtocolGame::parseQuestLog(const InputMessagePtr& msg)
{
    std::vector<std::tuple<int, std::string, bool> > questList;
    int questsCount = msg->getU16();
    for (int i = 0; i < questsCount; i++) {
        int id = msg->getU16();
        std::string name = msg->getString();
        bool completed = msg->getU8();
        questList.push_back(std::make_tuple(id, name, completed));
    }

    g_game.processQuestLog(questList);
}

void ProtocolGame::parseQuestLine(const InputMessagePtr& msg)
{
    std::vector<std::tuple<std::string, std::string, int>> questMissions;
    int questId = msg->getU16();
    int missionCount = msg->getU8();
    for (int i = 0; i < missionCount; i++) {
        int missionId = 0;
        if (g_game.getFeature(Otc::GameTibia12Protocol) || g_game.getFeature(Otc::GameMissionId))
            missionId = msg->getU16();

        std::string missionName = msg->getString();
        std::string missionDescrition = msg->getString();
        questMissions.push_back(std::make_tuple(missionName, missionDescrition, missionId));
    }

    g_game.processQuestLine(questId, questMissions);
}

void ProtocolGame::parseChannelEvent(const InputMessagePtr& msg)
{
    uint16 channelId = msg->getU16();
    std::string name = g_game.formatCreatureName(msg->getString());
    uint8 type = msg->getU8();

    g_lua.callGlobalField("g_game", "onChannelEvent", channelId, name, type);
}

void ProtocolGame::parseItemInfo(const InputMessagePtr& msg)
{
    std::vector<std::tuple<ItemPtr, std::string>> list;
    int size = msg->getU8();
    for (int i = 0; i < size; ++i) {
        auto item = std::make_shared<Item>();
        item->setId(msg->getItemId()); // server addItemId, u32
        item->setCountOrSubType(g_game.getFeature(Otc::GameCountU16) ? msg->getU16() : msg->getU8());

        std::string desc = msg->getString();
        list.push_back(std::make_tuple(item, desc));
    }

    g_lua.callGlobalField("g_game", "onItemInfo", list);
}

void ProtocolGame::parsePlayerInventory(const InputMessagePtr& msg)
{
    // crystalserver sendInventoryIds (0xF5): count U16, then count entries of
    // itemId U16, attribute(tier) U8, packed-count. The count is a variable-length
    // field (1/2/4 bytes) introduced at 15.x — NOT a flat U16. The stock parser read
    // a fixed U16 count and so under/over-read every entry, walking the stream off
    // into a run of zero bytes that flooded the 0x00 lua-buffer handler.
    //
    // The server recomputes and resends this on every inventory add/remove (buying
    // at an NPC, looting, moving items) and it counts the WHOLE inventory recursively
    // — closed backpacks included. We aggregate it per item id (tiers summed, matching
    // getInventoryCount which is tier-agnostic) and hand it to the LocalPlayer so the
    // action bar / helper show live totals even with every container closed.
    std::map<int, int> counts;
    const uint16_t size = msg->getU16();
    for (uint16_t i = 0; i < size; ++i) {
        const uint32_t itemId = msg->getItemId(); // server addItemId, u32
        msg->getU8(); // attribute (tier when the item is classified)

        // Packed count (mirrors server's encoding & mainline readPackedCount1500):
        //   b1 < 0x40            -> count = b1                       (1 byte)
        //   0x40 <= b1 < 0x80    -> count = ((b1-0x40)<<8) | b2      (2 bytes)
        //   b1 >= 0x80           -> count = b2<<16 | b3<<8 | b4      (4 bytes)
        int count;
        const uint8_t b1 = msg->getU8();
        if (b1 < 0x40) {
            count = b1;
        } else if (b1 < 0x80) {
            count = ((b1 - 0x40) << 8) | msg->getU8();
        } else {
            const int b2 = msg->getU8();
            const int b3 = msg->getU8();
            const int b4 = msg->getU8();
            count = (b2 << 16) | (b3 << 8) | b4;
        }

        counts[itemId] += count;
    }

    if (m_localPlayer)
        m_localPlayer->setInventoryItemsCount(counts);

    // Wakes the action bar (connect(g_game, {updateInventoryItems = ...})) so item
    // counts/greyed-out state refresh the instant the server pushes a change.
    g_lua.callGlobalField("g_game", "updateInventoryItems");
}

void ProtocolGame::parseModalDialog(const InputMessagePtr& msg)
{
    uint32 id = msg->getU32();
    std::string title = msg->getString();
    std::string message = msg->getString();

    int sizeButtons = msg->getU8();
    std::vector<std::tuple<int, std::string> > buttonList;
    for (int i = 0; i < sizeButtons; ++i) {
        std::string value = msg->getString();
        int id = msg->getU8();
        buttonList.push_back(std::make_tuple(id, value));
    }

    int sizeChoices = msg->getU8();
    std::vector<std::tuple<int, std::string> > choiceList;
    for (int i = 0; i < sizeChoices; ++i) {
        std::string value = msg->getString();
        int id = msg->getU8();
        choiceList.push_back(std::make_tuple(id, value));
    }

    int enterButton, escapeButton;
    if (g_game.getProtocolVersion() > 970) {
        escapeButton = msg->getU8();
        enterButton = msg->getU8();
    } else {
        enterButton = msg->getU8();
        escapeButton = msg->getU8();
    }

    bool priority = msg->getU8() == 0x01;

    g_game.processModalDialog(id, title, message, buttonList, enterButton, escapeButton, choiceList, priority);
}

void ProtocolGame::parseClientCheck(const InputMessagePtr& msg)
{
    msg->getU32();
    msg->getU8();
}

void ProtocolGame::parseGameNews(const InputMessagePtr& msg)
{
    msg->getU32();
    msg->getU8();
}

void ProtocolGame::parseMessageDialog(const InputMessagePtr& msg)
{
    msg->getU8();
    msg->getString();
}

void ProtocolGame::parseBlessDialog(const InputMessagePtr& msg)
{
    // parse bless amount
    uint8_t totalBless = msg->getU8(); // total bless

    // parse each bless
    for (int i = 0; i < totalBless; i++) {
        msg->getU16(); // bless bit wise
        msg->getU8(); // player bless count
        if (g_game.getProtocolVersion() >= 1220) {
            msg->getU8(); // store?
        }
    }

    // parse general info
    msg->getU8(); // premium
    msg->getU8(); // promotion
    msg->getU8(); // pvp min xp loss
    msg->getU8(); // pvp max xp loss
    msg->getU8(); // pve exp loss
    msg->getU8(); // equip pvp loss
    msg->getU8(); // equip pve loss
    msg->getU8(); // skull
    msg->getU8(); // aol

    // parse log
    uint8_t logCount = msg->getU8(); // log count
    for (int i = 0; i < logCount; i++) {
        msg->getU32(); // timestamp
        msg->getU8(); // color message (0 = white loss, 1 = red)
        msg->getString(); // history message
    }
}

void ProtocolGame::parseBosstiaryData(const InputMessagePtr& msg)
{
    // crystalserver 0x61: 18 x U16 bosstiary kill/point thresholds. We don't
    // model the bosstiary yet, just consume the fixed-size payload.
    for (int i = 0; i < 18; ++i)
        msg->getU16();
}

void ProtocolGame::parseBosstiaryEntries(const InputMessagePtr& msg)
{
    // crystalserver 0x73 (ProtocolGame::parseSendBosstiary): the full Boss Cyclopedia
    // entry list. U16 count, then per boss: U32 raceId, U8 bossRace, U32 killCount,
    // U8 (unused), U8 isOnTracker. No UI yet — consume so the world packet stays aligned.
    const uint16_t count = msg->getU16();
    for (uint16_t i = 0; i < count; ++i) {
        msg->getU32(); // boss race id
        msg->getU8();  // boss race (rarity)
        msg->getU32(); // kill count
        msg->getU8();  // unused
        msg->getU8();  // is on bosstiary tracker
    }
}

void ProtocolGame::parseBosstiarySlots(const InputMessagePtr& msg)
{
    // crystalserver 0x62: bosstiary slots window. Variable layout mirroring
    // ProtocolGame::parseSendBosstiarySlots() on the server. We only consume the
    // bytes (no UI yet) so the rest of the world packet stays aligned.
    auto readSlotBytes = [&]() {
        msg->getU8();   // boss race
        msg->getU32();  // kill count
        msg->getU16();  // loot bonus
        msg->getU8();   // kill bonus
        msg->getU8();   // boss race (again)
        msg->getU32();  // remove price
        msg->getU8();   // inactive flag
    };

    msg->getU32(); // player boss points
    msg->getU32(); // points to next bonus
    msg->getU16(); // current bonus
    msg->getU16(); // next bonus

    // Slot one
    bool slotOneUnlocked = msg->getU8() != 0;
    uint32_t slotOneBossId = msg->getU32();
    if (slotOneUnlocked && slotOneBossId != 0)
        readSlotBytes();

    // Slot two
    bool slotTwoUnlocked = msg->getU8() != 0;
    uint32_t slotTwoBossId = msg->getU32();
    if (slotTwoUnlocked && slotTwoBossId != 0)
        readSlotBytes();

    // Today (boosted) slot
    bool todayUnlocked = msg->getU8() != 0;
    uint32_t boostedBossId = msg->getU32();
    if (todayUnlocked && boostedBossId != 0)
        readSlotBytes();

    // Unlocked bosses list. The server reserves the U16 count first (skipBytes
    // then back-fills it), so on the wire the count comes BEFORE the entries:
    // [count U16] then count * [bossId U32, race U8].
    bool hasBossesList = msg->getU8() != 0;
    if (hasBossesList) {
        uint16_t count = msg->getU16();
        for (int i = 0; i < count; ++i) {
            msg->getU32(); // boss id
            msg->getU8();  // boss race
        }
    }
}

void ProtocolGame::parseHarmonyProtocol(const InputMessagePtr& msg)
{
    // crystalserver custom opcode 0xC1: [subtype:U8][value:U8].
    // subtype 0x00 = Harmony, 0x01 = Serene, 0x02 = Virtue. All carry one byte.
    uint8_t subtype = msg->getU8();
    uint8_t value = msg->getU8();
    callLuaField("onHarmonyProtocol", subtype, value);
}

void ProtocolGame::parseResourceBalance(const InputMessagePtr& msg)
{
    uint8_t type = msg->getU8();
    // crystalserver/Canary 13+ uses opcode 0xEE for two value widths:
    //   * 32-bit (sendCharmResourceBalance): CHARM 0x1E, MINOR_CHARM 0x1F,
    //     MAX_CHARM 0x20, MAX_MINOR_CHARM 0x21; and (sendResourceBalance)
    //     BOUNTY_POINTS 0x56, SOULSEALS_POINTS 0x57.
    //   * 64-bit: every other resource (bank, money, prey, forge, gems, ...).
    // Reading the wrong width desyncs the whole world packet.
    uint64_t amount;
    const bool is32 = (type >= 0x1E && type <= 0x21) || type == 0x56 || type == 0x57;
    if (is32)
        amount = msg->getU32();
    else
        amount = msg->getU64();
    if(m_localPlayer)
        m_localPlayer->setResourceValue(type, amount);
    g_lua.callGlobalField("g_game", "onResourceBalance", type, amount);
}

void ProtocolGame::parseOpenWheelWindow(const InputMessagePtr& msg)
{
    uint32_t playerId = msg->getU32();
    uint8_t canView = msg->getU8();

    if(!canView) {
        g_lua.callGlobalField("g_game", "onDestinyWheel",
            playerId, canView, 0, 0, 0, 0,
            std::vector<uint16_t>(), std::vector<uint16_t>(),
            std::vector<uint16_t>(), std::vector<GemData>(),
            std::map<uint8_t, uint8_t>(), std::map<uint8_t, uint8_t>(), 0);
        return;
    }

    uint8_t changeState = msg->getU8();
    uint8_t vocationId = msg->getU8();
    uint16_t points = msg->getU16();
    uint16_t extraPoints = msg->getU16();

    std::vector<uint16_t> pointInvested;
    pointInvested.reserve(36);
    for(uint8_t i = 0; i < 36; ++i)
        pointInvested.push_back(msg->getU16());

    // Promotion-scroll entries carry a real item id (server addItemId, u32); keep
    // the read width and the storage type at 32-bit so ids >= 65536 don't truncate
    // and the rest of the packet stays in lockstep.
    std::vector<uint32_t> usedPromotionScrolls;
    uint16_t scrollCount = msg->getU16();
    usedPromotionScrolls.reserve(scrollCount);
    for(uint16_t i = 0; i < scrollCount; ++i) {
        uint32_t itemId = msg->getItemId();
        if(g_game.getProtocolVersion() >= 1500 && msg->getUnreadSize() > 0)
            msg->getU8();
        usedPromotionScrolls.push_back(itemId);
    }

    if(g_game.getProtocolVersion() >= 1500 && msg->getUnreadSize() > 0)
        msg->getU8();

    // crystalserver player_wheel.cpp:1555 sends a U16 "extra points from
    // hunting task shop" between the monk-quest byte and addGems(); missing
    // it shifts every following read by 2 bytes (revealedCount = N<<8).
    if(g_game.getProtocolVersion() >= 1500 && msg->getUnreadSize() >= 2)
        msg->getU16(); // extra points from hunting task shop

    std::vector<uint16_t> equippedGems;
    uint8_t activeGemCount = msg->getU8();
    equippedGems.reserve(activeGemCount);
    for(uint8_t i = 0; i < activeGemCount; ++i)
        equippedGems.push_back(msg->getU16());

    std::vector<GemData> atelierGems;
    uint16_t revealedCount = msg->getU16();
    atelierGems.reserve(revealedCount);
    for(uint16_t i = 0; i < revealedCount; ++i) {
        GemData gem;
        gem.gemID = msg->getU16();
        gem.locked = msg->getU8();
        gem.gemDomain = msg->getU8();
        gem.gemType = msg->getU8();
        gem.lesserBonus = msg->getU8();
        if(gem.gemType >= Otc::WheelGemQuality_Regular && msg->getUnreadSize() > 0)
            gem.regularBonus = msg->getU8();
        if(gem.gemType >= Otc::WheelGemQuality_Greater && msg->getUnreadSize() > 0)
            gem.supremeBonus = msg->getU8();
        atelierGems.push_back(gem);
    }

    std::map<uint8_t, uint8_t> basicUpgraded;
    uint8_t basicCount = msg->getU8();
    for(uint8_t i = 0; i < basicCount; ++i) {
        uint8_t pos = msg->getU8();
        uint8_t value = msg->getU8();
        basicUpgraded[pos] = value;
    }

    std::map<uint8_t, uint8_t> supremeUpgraded;
    uint8_t supremeCount = msg->getU8();
    for(uint8_t i = 0; i < supremeCount; ++i) {
        uint8_t pos = msg->getU8();
        uint8_t value = msg->getU8();
        supremeUpgraded[pos] = value;
    }

    uint8_t earnedFromAchievements = 0;
    if(g_game.getProtocolVersion() >= 1510 && msg->getUnreadSize() > 0)
        earnedFromAchievements = msg->getU8();

    while(msg->getUnreadSize() > 0)
        msg->getU8();

    g_lua.callGlobalField("g_game", "onDestinyWheel",
        playerId, canView, changeState, vocationId,
        points, extraPoints, pointInvested,
        usedPromotionScrolls, equippedGems, atelierGems,
        basicUpgraded, supremeUpgraded, earnedFromAchievements);
}

void ProtocolGame::parseWeaponProficiencyCatalog(const InputMessagePtr& msg)
{
    const uint16_t count = msg->getU16();
    for (uint16_t i = 0; i < count; ++i) {
        const uint32_t itemId = msg->getItemId(); // server addItemId, u32
        const uint16_t marketCategory = msg->getU16();
        const std::string name = msg->getString();
        g_lua.callGlobalField("g_game", "onWeaponProficiencyCatalogItem", itemId, marketCategory, name);
    }
    g_lua.callGlobalField("g_game", "onWeaponProficiencyCatalogReady");
}

void ProtocolGame::parseWeaponProficiencyExperience(const InputMessagePtr& msg)
{
    const uint32_t itemId = msg->getItemId(); // server addItemId, u32
    const uint32_t experience = msg->getU32();
    const uint8_t hasUnusedPerk = msg->getU8();
    g_lua.callGlobalField("g_game", "onWeaponProficiencyExperience", itemId, experience, hasUnusedPerk != 0);
}

static void parseWeaponProficiencyInfoPayload(const InputMessagePtr& msg)
{
    const uint32_t itemId = msg->getItemId(); // server addItemId, u32
    const uint32_t experience = msg->getU32();
    const uint8_t perksCount = msg->getU8();
    std::map<uint8_t, uint8_t> perks;
    for (int i = 0; i < perksCount; ++i) {
        const uint8_t level = msg->getU8();
        const uint8_t perkPosition = msg->getU8();
        perks[level] = perkPosition;
    }

    // crystalserver sendWeaponProficiencyInfo (0xC4) ends after the perk pairs; reading a trailing
    // u16 here shifted the stream and corrupted the next opcode in batched replies.
    g_lua.callGlobalField("g_game", "onWeaponProficiency", itemId, experience, perks);
}

void ProtocolGame::parseWeaponProficiencyInfo(const InputMessagePtr& msg)
{
    parseWeaponProficiencyInfoPayload(msg);
}

void ProtocolGame::parseWeaponProficiencyInfoBatch(const InputMessagePtr& msg)
{
    const uint16_t count = msg->getU16();
    for (uint16_t i = 0; i < count; ++i) {
        parseWeaponProficiencyInfoPayload(msg);
    }
}

void ProtocolGame::parseServerTime(const InputMessagePtr& msg)
{
    uint8_t minutes = msg->getU8();
    uint8_t seconds = msg->getU8();
    g_lua.callGlobalField("g_game", "onServerTime", minutes, seconds);
}

void ProtocolGame::parseQuestTracker(const InputMessagePtr& msg)
{
    msg->getU8();
    msg->getU16();
}

void ProtocolGame::parseImbuementWindow(const InputMessagePtr& msg)
{
    constexpr int ModernImbuementVersion = 860;

    if (g_game.getClientVersion() < ModernImbuementVersion) {
        int itemId = msg->getItemId();
        int slots = msg->getU8();

        std::map<int, std::tuple<Imbuement, int, int>> activeSlots;
        for (int i = 0; i < slots; ++i) {
            bool info = msg->getU8() == 1;
            if (info) {
                Imbuement imbuement = getImbuementInfo(msg);
                int duration = msg->getU32();
                int removalCost = msg->getU32();
                activeSlots[i] = std::make_tuple(imbuement, duration, removalCost);
            }
        }

        int imbuements_size = msg->getU16();
        std::vector<Imbuement> imbuements;
        for (int i = 0; i < imbuements_size; ++i) {
            imbuements.push_back(getImbuementInfo(msg));
        }

        std::vector<ItemPtr> needItems;
        int needItems_count = msg->getU32();
        for (int i = 0; i < needItems_count; ++i) {
            int item = msg->getItemId();
            int count = msg->getU16();
            needItems.push_back(Item::create(item, count));
        }

        g_lua.callGlobalField("g_game", "onImbuementWindow", itemId, slots, activeSlots, imbuements, needItems);
        return;
    }

    uint8_t windowType = msg->getU8();
    msg->getU8(); // has blank imbuement scroll

    switch (windowType) {
        case Otc::IMBUEMENT_WINDOW_CHOICE: {
            const uint32_t itemId = msg->getItemId();
            msg->getU32(); // unused U32 0 filler (server openImbuementWindow CHOICE/null-item branch)
            g_lua.callGlobalField("g_game", "onOpenImbuementWindow", itemId);
            break;
        }
        case Otc::IMBUEMENT_WINDOW_SCROLL: {
            msg->getU8(); // has free backpack slot
            msg->getU8(); // unknown byte

            const uint16_t imbuementsSize = msg->getU16();
            std::vector<Imbuement> imbuements;
            for (int i = 0; i < imbuementsSize; ++i) {
                imbuements.push_back(getImbuementInfo(msg));
            }

            const uint32_t neededItemsCount = msg->getU32();
            std::vector<ItemPtr> neededItems;
            neededItems.reserve(neededItemsCount);
            for (uint32_t i = 0; i < neededItemsCount; ++i) {
                const uint32_t itemId = msg->getItemId();
                const uint16_t count = msg->getU16();
                neededItems.push_back(Item::create(itemId, count));
            }

            g_lua.callGlobalField("g_game", "onImbuementScroll", imbuements, neededItems);
            break;
        }
        case Otc::IMBUEMENT_WINDOW_SELECT_ITEM: {
            const uint32_t itemId = msg->getItemId();
            // Server sends no item name; tier U8 is present ONLY when the item has
            // classification > 0 (mirrors parseItemsPrices). Name sourced client-side.
            uint8_t tier = 0;
            std::string itemName;
            if (g_things.isValidDatId(itemId, ThingCategoryItem)) {
                ThingType* tt = g_things.rawGetThingType(itemId, ThingCategoryItem);
                if (tt) {
                    itemName = tt->getAppearanceName();
                    if (tt->getClassification() > 0)
                        tier = msg->getU8();
                }
            }
            const uint8_t slots = msg->getU8();
            std::map<int, std::tuple<Imbuement, int, int>> activeSlots;
            for (int i = 0; i < slots; ++i) {
                const bool info = msg->getU8() == 1;
                if (info) {
                    Imbuement imbuement = getImbuementInfo(msg);
                    const int duration = msg->getU32();
                    const int removalCost = msg->getU32();
                    activeSlots[i] = std::make_tuple(imbuement, duration, removalCost);
                }
            }

            const uint16_t imbuementsSize = msg->getU16();
            std::vector<Imbuement> imbuements;
            for (int i = 0; i < imbuementsSize; ++i) {
                imbuements.push_back(getImbuementInfo(msg));
            }

            const uint32_t neededItemsCount = msg->getU32();
            std::vector<ItemPtr> neededItems;
            neededItems.reserve(neededItemsCount);
            for (uint32_t i = 0; i < neededItemsCount; ++i) {
                const uint32_t needItemId = msg->getItemId();
                const uint16_t count = msg->getU16();
                neededItems.push_back(Item::create(needItemId, count));
            }

            g_lua.callGlobalField("g_game", "onImbuementItem", itemId, tier, slots, activeSlots, imbuements, neededItems, itemName);
            break;
        }
    }
}

void ProtocolGame::parseCloseImbuementWindow(const InputMessagePtr&)
{
    g_lua.callGlobalField("g_game", "onCloseImbuementWindow");
}

void ProtocolGame::parseImbuementDurations(const InputMessagePtr& msg)
{
    const uint8_t itemListCount = msg->getU8();
    std::vector<ImbuementTrackerItem> itemList;

    for (auto i = 0; i < itemListCount; ++i) {
        ImbuementTrackerItem item(msg->getU8());
        item.item = getItem(msg);

        std::map<uint8_t, ImbuementSlot> slots;

        const uint8_t slotsCount = msg->getU8();
        item.totalSlots = slotsCount;
        if (slotsCount == 0) {
            itemList.emplace_back(item);
            continue;
        }

        for (auto slotIndex = 0; slotIndex < slotsCount; ++slotIndex) {
            const bool slotImbued = static_cast<bool>(msg->getU8());
            if (!slotImbued) {
                continue;
            }

            ImbuementSlot slot(slotIndex);
            slot.name = msg->getString();
            slot.iconId = msg->getU16();
            slot.duration = msg->getU32();
            slot.state = msg->getU8();
            slots.emplace(slotIndex, slot);
        }

        item.slots = slots;
        itemList.emplace_back(item);
    }

    g_lua.callGlobalField("g_game", "onUpdateImbuementTracker", itemList);
}

void ProtocolGame::parseCyclopedia(const InputMessagePtr& msg)
{
    // crystalserver opcode 0xDA = CyclopediaCharacterInfo. Layout mirrors the
    // server's sendCyclopediaCharacter* family (src/server/network/protocol/
    // protocolgame.cpp). Format: infoType U8, errorCode U8, then a type-specific
    // payload. The stock handler read a bare U16 ("race id") and desynced the rest
    // of the login stream (the GENERALSTATS payload is ~1.2 KB). We consume each
    // sub-type's bytes exactly; UI wiring can come later.
    const uint8_t type = msg->getU8();
    const uint8_t errorCode = msg->getU8();
    if (errorCode != 0)
        return; // server sent only [type][error] when it has no data / no permission

    switch (type) {
        case 0: { // BASEINFORMATION
            msg->getString();            // name
            msg->getString();            // vocation name
            msg->getU16();               // level
            getOutfit(msg, true);        // outfit; server AddOutfit(..., addMount=false) sends no mount U16
            msg->getU8();                // store summary & titles flag
            msg->getString();            // current title name
            break;
        }
        case 1: { // GENERALSTATS
            msg->getU64();               // experience
            msg->getU16();               // level
            msg->getU16();               // level percent * 100
            msg->getU16();               // base xp gain rate
            msg->getU16();               // low level bonus
            msg->getU16();               // xp boost
            msg->getU16();               // stamina multiplier
            msg->getU16();               // xp boost remaining time
            msg->getU8();                // can buy xp boost
            msg->getU32();               // health
            msg->getU32();               // max health
            msg->getU32();               // mana
            msg->getU32();               // max mana
            msg->getU8();                // soul
            msg->getU16();               // stamina minutes
            msg->getU16();               // regeneration condition (food)
            msg->getU16();               // offline training time
            msg->getU16();               // speed
            msg->getU16();               // base speed
            msg->getU32();               // capacity
            msg->getU32();               // base capacity
            msg->getU32();               // free capacity
            msg->getU8();                // 8 (hardcoded)
            msg->getU8();                // 1 (hardcoded)
            msg->getU16();               // magic level
            msg->getU16();               // base magic level
            msg->getU16();               // loyalty magic level
            msg->getU16();               // magic level percent * 100
            for (int s = 0; s < 7; ++s) { // SKILL_FIRST..SKILL_FISHING (7 entries)
                msg->getU8();            // hardcoded skill id
                msg->getU16();           // level
                msg->getU16();           // base
                msg->getU16();           // loyalty
                msg->getU16();           // percent * 100
            }
            const uint8_t combatCount = msg->getU8();
            for (uint8_t i = 0; i < combatCount; ++i) {
                msg->getU8();            // element
                msg->getU16();           // specialized magic level
            }
            break;
        }
        default:
            // Other CyclopediaCharacterInfo sub-types (combat/deaths/achievements/
            // summaries/inspection/badges/titles/wheel/offence/defence/misc) are not
            // pushed during login; if one arrives, we cannot know its length, so log
            // and let the parse bail (the catch in parseMessage handles it) rather
            // than silently corrupt the stream.
            g_logger.traceError(stdext::format("parseCyclopedia: unhandled info type %d", (int)type));
            break;
    }
}

void ProtocolGame::parseCyclopediaNewDetails(const InputMessagePtr& msg)
{
    // crystalserver sendBestiaryEntryChanged (0xD9): raceId U16 only. Sent mid-hunt
    // whenever a kill unlocks a new bestiary rank — the old stub consumed NOTHING and
    // desynced the whole packet right after a rank-up kill.
    const uint16_t raceId = msg->getU16();
    g_lua.callGlobalField("g_game", "onBestiaryEntryChanged", raceId);
}

void ProtocolGame::parseDailyRewardState(const InputMessagePtr& msg)
{
    msg->getU8(); // state
}

void ProtocolGame::parseOpenRewardWall(const InputMessagePtr& msg)
{
    msg->getU8(); // bonus shrine (1) or instant bonus (0)
    msg->getU32(); // next reward time
    msg->getU8(); // day streak day
    uint8_t wasDailyRewardTaken = msg->getU8(); // taken (player already took reward?)

    if (wasDailyRewardTaken) {
        msg->getString(); // error message
    }

    msg->getU32(); // time left to pickup reward without loosing streak
    msg->getU16(); // day streak level
    msg->getU16(); // unknown
}

void ProtocolGame::parseDailyReward(const InputMessagePtr& msg)
{
    uint8_t count = msg->getU8(); // state

    // TODO: implement daily reward usage
}

void ProtocolGame::parseDailyRewardHistory(const InputMessagePtr& msg)
{
    uint8_t historyCount = msg->getU8(); // history count

    for (int i = 0; i < historyCount; i++) {
        msg->getU32(); // timestamp
        msg->getU8(); // is Premium
        msg->getString(); // description
        msg->getU16(); // daystreak
    }

    // TODO: implement reward history usage
}

Imbuement ProtocolGame::getImbuementInfo(const InputMessagePtr& msg)
{
    constexpr int ModernImbuementVersion = 860;

    Imbuement i;
    i.id = msg->getU32();
    i.name = msg->getString();
    i.description = msg->getString();

    if (g_game.getClientVersion() >= ModernImbuementVersion) {
        i.tier = msg->getU8();
        if (i.tier == 0) {
            i.group = "Basic";
        } else if (i.tier == 1) {
            i.group = "Intricate";
        } else if (i.tier == 2) {
            i.group = "Powerful";
        } else {
            i.group = "Unknown";
        }
    } else {
        i.group = msg->getString();
        i.tier = 0;
    }

    i.imageId = msg->getU16();
    i.duration = msg->getU32();

    if (g_game.getClientVersion() < ModernImbuementVersion) {
        i.premiumOnly = msg->getU8() > 0;
    } else {
        i.premiumOnly = false;
    }

    int size = msg->getU8();
    for (int j = 0; j < size; ++j) {
        int id = msg->getItemId();
        std::string description = msg->getString();
        int count = msg->getU16();
        i.sources.push_back(std::make_pair(Item::create(id, count), description));
    }
    i.cost = msg->getU32();
    if (g_game.getClientVersion() < ModernImbuementVersion) {
        i.successRate = msg->getU8();
        i.protectionCost = msg->getU32();
    } else {
        i.successRate = 100;
        i.protectionCost = 0;
    }
    return i;
}

void ProtocolGame::parseLootContainers(const InputMessagePtr& msg)
{
    // crystalserver sendLootContainers (0xC0): fallback U8, count U8, then count
    // entries of category U8, lootContainerId (addItemId, u32), obtainContainerId (addItemId, u32). Capture the
    // per-category container ids and hand them to game_quickloot's onParseLootContainers
    // so the "Manage Loot Containers" window shows the player's configured containers on
    // login. Previously the bytes were only consumed (no signal), leaving the window empty.
    const uint8_t quickLootFallbackToMainContainer = msg->getU8();

    std::map<uint8_t, uint32_t> lootContainers;
    std::map<uint8_t, uint32_t> obtainContainers;
    const int containers = msg->getU8();
    for (int i = 0; i < containers; ++i) {
        const uint8_t category = msg->getU8();
        lootContainers[category] = msg->getItemId();  // loot container item id (server addItemId, u32)
        obtainContainers[category] = msg->getItemId(); // obtain container item id (server addItemId, u32)
    }

    g_lua.callGlobalField("g_game", "onParseLootContainers",
                          quickLootFallbackToMainContainer, lootContainers, obtainContainers);
}

void ProtocolGame::parseBosstiaryCooldownTimer(const InputMessagePtr& msg)
{
    // crystalserver sendBosstiaryCooldownTimer (0xBD): count U16, then count entries
    // of bossRaceId U32 + cooldown timer U64.
    const uint16_t count = msg->getU16();
    for (uint16_t i = 0; i < count; ++i) {
        msg->getU32(); // boss race id
        msg->getU64(); // cooldown unix timestamp
    }
}

void ProtocolGame::parseCyclopediaMonsterTracker(const InputMessagePtr& msg)
{
    // crystalserver refreshCyclopediaMonsterTracker (0xB9): isBoss U8, count U8,
    // then count entries of raceId U16, killAmount U32, three U16 thresholds (boss
    // kill stages or bestiary unlock counts), completed U8.
    const uint8_t trackerType = msg->getU8(); // 0 = bestiary, 1 = bosstiary
    const uint8_t count = msg->getU8();
    std::vector<std::vector<int>> entries;
    entries.reserve(count);
    for (uint8_t i = 0; i < count; ++i) {
        std::vector<int> entry;
        entry.reserve(6);
        entry.push_back(msg->getU16());                  // [1] race id
        entry.push_back(static_cast<int>(msg->getU32())); // [2] kill amount
        entry.push_back(msg->getU16());                  // [3] threshold 1
        entry.push_back(msg->getU16());                  // [4] threshold 2
        entry.push_back(msg->getU16());                  // [5] threshold 3
        entry.push_back(msg->getU8());                   // [6] completed (0 or 4)
        entries.emplace_back(std::move(entry));
    }
    // game_cyclopedia: onMonsterTrackerData(trackerType, entries) -> Bestiary tracker
    // list (entry[1] == raceId is what the tracker checks).
    g_lua.callGlobalField("g_game", "onMonsterTrackerData", trackerType, entries);
}

void ProtocolGame::parseWheelGiftOfLife(const InputMessagePtr& msg)
{
    // crystalserver PlayerWheel::sendGiftOfLifeCooldown (0x5E): giftId U8,
    // cooldownEnum U8, currentCooldown U32, totalCooldown U32, decreasing U8.
    msg->getU8();
    msg->getU8();
    msg->getU32();
    msg->getU32();
    msg->getU8();
}

void ProtocolGame::parseHousesInfo(const InputMessagePtr& msg)
{
    // crystalserver sendHousesInfo (0xC6): houseClientId U32, 0x00, accountHouses U8,
    // 0x00, 3, 3, 0x01, 0x01, houseClientId U32, housesCount U16, housesCount * U32.
    // No house UI yet — just consume the payload to keep the stream aligned.
    msg->getU32(); // current house client id
    msg->getU8();
    msg->getU8();  // account house count
    msg->getU8();
    msg->getU8();
    msg->getU8();
    msg->getU8();
    msg->getU8();
    msg->getU32(); // house client id (repeat)
    const uint16_t houses = msg->getU16();
    for (uint16_t i = 0; i < houses; ++i)
        msg->getU32(); // house client id
}

void ProtocolGame::parseSupplyStash(const InputMessagePtr& msg)
{
    // crystalserver sendOpenStash (0x29): count U16, then
    // count * (itemId addItemId(u32) + itemCount U32); no trailing field.
    int size = msg->getU16();
    for (int i = 0; i < size; ++i) {
        msg->getItemId(); // item id (server addItemId, u32)
        msg->getU32(); // item count
    }
}

void ProtocolGame::parseSpecialContainer(const InputMessagePtr& msg)
{
    msg->getU8();
    if (g_game.getProtocolVersion() >= 1220) {
        msg->getU8();
    }
}

void ProtocolGame::parseDepotState(const InputMessagePtr& msg)
{
    msg->getU8(); // unknown, true/false
    if (g_game.getProtocolVersion() >= 1230) {
        msg->getU8(); // unknown
    }
}

void ProtocolGame::parseTournamentLeaderboard(const InputMessagePtr& msg)
{
    msg->getU8();
    msg->getU8();
}

void ProtocolGame::parseKillTracker(const InputMessagePtr& msg)
{
    // crystalserver sendKillTrackerUpdate (0xD1): creature name, outfit (lookType U16 +
    // head/body/legs/feet/addons U8), corpse item count U8 + items. Dispatched to
    // game_analyser onKillTracker (Hunting kill counter + DropTracker valuable-loot).
    const std::string name = msg->getString();
    Outfit outfit;
    outfit.setCategory(ThingCategoryCreature);
    outfit.setId(msg->getU16());
    outfit.setHead(msg->getU8());
    outfit.setBody(msg->getU8());
    outfit.setLegs(msg->getU8());
    outfit.setFeet(msg->getU8());
    outfit.setAddons(msg->getU8());

    std::vector<ItemPtr> corpseItems;
    const int corpseSize = msg->getU8();
    for (int i = 0; i < corpseSize; i++) {
        corpseItems.push_back(getItem(msg));
    }

    g_lua.callGlobalField("g_game", "onKillTracker", name, outfit, corpseItems);
}

void ProtocolGame::parseSupplyTracker(const InputMessagePtr& msg)
{
    // crystalserver sendUpdateSupplyTracker (0xCE): itemId addItemId(u32). Dispatched to
    // game_analyser onSupplyTracker (Hunting/Supply analyser spend tracking).
    const uint32_t itemId = msg->getItemId(); // server addItemId, u32
    g_lua.callGlobalField("g_game", "onSupplyTracker", itemId);
}

void ProtocolGame::parsePartyAnalyzer(const InputMessagePtr& msg)
{
    // crystalserver updatePartyTrackerAnalyzer (0x2B): analyzerTime U32, leaderId U32,
    // priceType U8, memberCount U8 + per member {id U32, active U8, loot U64,
    // supply U64, damage U64, healing U64}, showNames U8 [+ count U8 + {id U32,
    // name Str}...]. Sent on every party hunt update; previously unhandled (desync).
    const uint32_t startTime = msg->getU32();
    const uint32_t leaderId = msg->getU32();
    const uint8_t priceType = msg->getU8();

    std::map<uint32_t, std::vector<double>> membersData;
    const uint8_t memberCount = msg->getU8();
    for (uint8_t i = 0; i < memberCount; ++i) {
        const uint32_t memberId = msg->getU32();
        msg->getU8(); // still in party / active flag
        std::vector<double> data;
        data.reserve(4);
        data.push_back(static_cast<double>(msg->getU64())); // [1] loot price
        data.push_back(static_cast<double>(msg->getU64())); // [2] supply price
        data.push_back(static_cast<double>(msg->getU64())); // [3] damage
        data.push_back(static_cast<double>(msg->getU64())); // [4] healing
        membersData[memberId] = std::move(data);
    }

    std::map<uint32_t, std::string> membersName;
    if (msg->getU8() == 0x01) {
        const uint8_t nameCount = msg->getU8();
        for (uint8_t i = 0; i < nameCount; ++i) {
            const uint32_t memberId = msg->getU32();
            membersName[memberId] = msg->getString();
        }
    }

    // game_analyser PartyHuntAnalyser: data[1]=loot, data[2]=supply, [3]=damage, [4]=healing.
    g_lua.callGlobalField("g_game", "onPartyAnalyzer", startTime, leaderId, priceType, membersData, membersName);
}

void ProtocolGame::parseScreenshotAndBanner(const InputMessagePtr& msg)
{
    // crystalserver sendScreenshotAndBanner* / sendBannerType (0x75): subtype U8 +
    // per-subtype payload (utils_definitions.hpp SCREENSHOT_AND_BANNER_TYPE_*). Sent
    // unconditionally on every level/skill/maglevel advance, batched right before the
    // stats (0xA0)/skills (0xA1) updates — leaving it unhandled aborted the rest of
    // the network message and left HP/level/skill displays stale. Drain only; no UI.
    // NOTE: do NOT copy mehah's parseTakeScreenshot (single U8) — it under-reads.
    const uint8_t type = msg->getU8();
    switch (type) {
        case 1: // BANNER_INFO: banner type
            msg->getU8();
            break;
        case 2: // ACHIEVEMENT: achievement name
        case 3: // TITLE: title name
            msg->getString();
            break;
        case 4: // LEVEL: new level
            msg->getU16();
            break;
        case 5: // SKILL: skill type + new skill level
            msg->getU8();
            msg->getU16();
            break;
        case 6: // BESTIARY_PROGRESS: race id + progress level
        case 7: // BOSSTIARY_PROGRESS: race id + progress level
            msg->getU16();
            msg->getU8();
            break;
        case 8: // QUEST: quest name + completed flag
            msg->getString();
            msg->getU8();
            break;
        case 9: // COSMETIC: looktype + skin name + skin type
            msg->getU16();
            msg->getString();
            msg->getU8();
            break;
        case 10: // PROFICIENCY: item id + message
            msg->getU16();
            msg->getString();
            break;
        default:
            // unknown subtype = unknown payload size; surface it instead of desyncing
            stdext::throw_exception(stdext::format("unknown screenshot/banner subtype %d", (int)type));
            break;
    }
}

void ProtocolGame::parseExperienceTracker(const InputMessagePtr& msg)
{
    // crystalserver sendExperienceTracker (0xAF): rawExp int64 + finalExp int64.
    const int64_t rawExp = static_cast<int64_t>(msg->getU64());
    const int64_t finalExp = static_cast<int64_t>(msg->getU64());
    // game_analyser registers onUpdateExperience(rawExp, finalExp) — the XP/Hunting
    // analysers' raw-vs-bonus experience feed.
    g_lua.callGlobalField("g_game", "onUpdateExperience", (double)rawExp, (double)finalExp);
}

void ProtocolGame::parseImpactTracker(const InputMessagePtr& msg)
{
    // crystalserver sendUpdateImpactTracker / sendUpdateInputAnalyzer (0xCC). Three
    // variants keyed by the analyzer byte (server_definitions.hpp):
    //   ANALYZER_HEAL = 0            -> amount U32
    //   ANALYZER_DAMAGE_DEALT = 1    -> amount U32 + cipbia element U8
    //   ANALYZER_DAMAGE_RECEIVED = 2 -> amount U32 + element U8 + target String
    // Reading a fixed U8+U32 dropped the trailing element/target bytes and desynced
    // every combat packet ("eof reached", prev opcode 0xcc).
    const uint8_t analyzer = msg->getU8();
    const uint32_t amount = msg->getU32();
    uint8_t element = 0;
    std::string target;
    if (analyzer == 1) {
        element = msg->getU8();
    } else if (analyzer == 2) {
        element = msg->getU8();
        target = msg->getString();
    }
    // game_analyser: onImpactTracker(ANALYZER_HEAL/DAMAGE_DEALT/DAMAGE_RECEIVED,
    // amount, cipbia element, target name) -> Hunting/Impact/Input analysers.
    g_lua.callGlobalField("g_game", "onImpactTracker", analyzer, amount, element, target);
}

void ProtocolGame::parseItemsPrices(const InputMessagePtr& msg)
{
    // crystalserver sendItemsPrice (0xCD): count U16, then count entries of
    // itemId addItemId(u32), [tier U8 when the item's upgradeClassification > 0], price U64.
    // The stock parser read the price as U32 and never read the classification
    // tier byte, leaving 4+ bytes per entry unread and desyncing the next opcode.
    const uint16_t count = msg->getU16();
    for (uint16_t i = 0; i < count; ++i) {
        const uint32_t itemId = msg->getItemId(); // server addItemId, u32
        ThingType* tt = nullptr;
        uint8_t tier = 0;
        if (g_things.isValidDatId(itemId, ThingCategoryItem)) {
            tt = g_things.rawGetThingType(itemId, ThingCategoryItem);
            if (tt && tt->getClassification() > 0)
                tier = msg->getU8();
        }
        const uint64_t price = msg->getU64();
        // Store the BASE price on the thing type (Item::getPriceValue feeds loot
        // coloring + the analysers). Classified items arrive once per tier; keep the
        // tier-0 entry (or the first seen) as the base value.
        if (tt && (tier == 0 || tt->getPriceValue() == 0))
            tt->setPriceValue(price);
    }
}

void ProtocolGame::parseLootTracker(const InputMessagePtr& msg)
{
    // crystalserver sendLootStats (0xCF): AddItem + item name, nothing else. The old
    // parser read a legacy multi-field layout (flags/strings/loop) and ran past the
    // end of the message ("eof reached", prev opcode 0xf5). Dispatch to the analyser
    // hook (mods/game_analyser wires g_game.onLootStats -> Loot/Hunting analysers).
    const ItemPtr item = getItem(msg);
    const std::string name = msg->getString();
    g_lua.callGlobalField("g_game", "onLootStats", item, name);
}

void ProtocolGame::parseItemDetail(const InputMessagePtr& msg)
{
    // crystalserver sendItemInspection (0x76): byte windowsType, byte inspectionType,
    // U32 creatureId, byte 0x01, string name, AddItem, byte imbuementCount (then that
    // many U16), byte descCount, [string detail, string description] x descCount.
    // The inspectionType byte on the wire is 0x00 normal / 0x01 cyclopedia /
    // 0x02 proficiency (NOT the Otc::INSPECT_* request enum); it is forwarded
    // unchanged so the Lua onInspection handlers (proficiency type 2, cyclopedia
    // type 1) match. The old stub only read item+name and emitted no callback.
    const uint8_t windowsType = msg->getU8(); // 0 = item, 1 = character
    const uint8_t inspectionType = msg->getU8();
    msg->getU32(); // creatureId (player id)

    // crystalserver only ever sends windowsType 0 (item) on this opcode; the
    // character-inspection layout (windowsType 1) is variable and not produced by
    // this server, so bail out rather than risk a stream desync from guessing it.
    if (windowsType != 0)
        return;

    msg->getU8(); // 0x01 constant
    const std::string itemName = msg->getString();
    const ItemPtr item = getItem(msg);

    const uint8_t imbuementCount = msg->getU8();
    std::vector<int> imbuements;
    imbuements.reserve(imbuementCount);
    for (uint8_t i = 0; i < imbuementCount; ++i)
        imbuements.push_back(msg->getU16());

    const uint8_t descCount = msg->getU8();
    std::vector<std::map<std::string, std::string>> descriptions;
    descriptions.reserve(descCount);
    for (uint8_t i = 0; i < descCount; ++i) {
        const std::string detail = msg->getString();
        const std::string description = msg->getString();
        descriptions.push_back({ { "detail", detail }, { "description", description } });
    }

    g_lua.callGlobalField("g_game", "onInspection", inspectionType, itemName, item, descriptions, imbuements);
}

void ProtocolGame::parseHunting(const InputMessagePtr& msg)
{
    // crystalserver sendTaskHuntingData (0xBB): slotId U8, state U8, state-specific
    // body, freeRerollTime U32. Sent on login and EVERY kill of a task-hunted monster
    // (Player::reloadTaskSlot) — the old empty stub consumed nothing and desynced the
    // packet whenever a player with an active hunting task killed its target.
    // States (ioprey.hpp): 0=Locked, 1=Inactive, 2=Selection, 3=ListSelection,
    // 4=Active, 5=Completed.
    const uint8_t slotId = msg->getU8();
    const uint8_t state = msg->getU8();
    switch (state) {
        case 0: // Locked
            msg->getU8(); // isPremium
            break;
        case 1: // Inactive
            break;
        case 2:   // Selection
        case 3: { // ListSelection
            const uint16_t raceCount = msg->getU16();
            for (uint16_t i = 0; i < raceCount; ++i) {
                msg->getU16(); // race id
                msg->getU8();  // unlocked (always 0x01)
            }
            break;
        }
        case 4: { // Active
            msg->getU16(); // selected race id
            msg->getU8();  // upgraded
            msg->getU16(); // required kills (first/second stage)
            msg->getU16(); // current kills
            msg->getU8();  // rarity
            break;
        }
        case 5: { // Completed
            msg->getU16(); // selected race id
            msg->getU8();  // upgraded
            msg->getU16(); // required kills
            msg->getU16(); // current kills (clamped)
            msg->getU8();  // rarity
            break;
        }
        default:
            g_logger.traceError(stdext::format("parseHunting: unknown task hunting state %d (slot %d)", (int)state, (int)slotId));
            return;
    }
    msg->getU32(); // free reroll time (seconds)
}

void ProtocolGame::parseExtendedOpcode(const InputMessagePtr& msg)
{
    int opcode = msg->getU8();
    std::string buffer = msg->getString();

    if (opcode == 0)
        m_enableSendExtendedOpcode = true;
    else
        callLuaField("onExtendedOpcode", opcode, buffer);
}

void ProtocolGame::parseChangeMapAwareRange(const InputMessagePtr& msg)
{
    int xrange = msg->getU8();
    int yrange = msg->getU8();

    AwareRange range;
    range.left = xrange / 2;
    range.right = xrange / 2 + 1;
    range.top = yrange / 2;
    range.bottom = yrange / 2 + 1;

    g_map.setAwareRange(range);
    g_lua.callGlobalField("g_game", "onMapChangeAwareRange", xrange, yrange);
}

void ProtocolGame::parseProgressBar(const InputMessagePtr& msg)
{
    uint32 id = msg->getU32();
    uint32 duration = msg->getU32();
    bool ltr = msg->getU8();
    CreaturePtr creature = g_map.getCreatureById(id);
    if (creature)
        creature->setProgressBar(duration, ltr);
    else
        g_logger.traceError(stdext::format("could not get creature with id %d", id));
}

void ProtocolGame::parseFeatures(const InputMessagePtr& msg)
{
    int features = msg->getU16();
    for (int i = 0; i < features; ++i) {
        Otc::GameFeature feature = (Otc::GameFeature)msg->getU8();
        bool enabled = msg->getU8() > 0;
        if (enabled) {
            g_game.enableFeature(feature);
        } else {
            g_game.disableFeature(feature);
        }
    }
}

void ProtocolGame::parseCreaturesMark(const InputMessagePtr& msg)
{
    int len;
    if (g_game.getProtocolVersion() >= 1035) {
        len = 1;
    } else {
        len = msg->getU8();
    }

    for (int i = 0; i < len; ++i) {
        uint32 id = msg->getU32();
        bool isPermanent = msg->getU8() != 1;
        uint8 markType = msg->getU8();

        CreaturePtr creature = g_map.getCreatureById(id);
        if (creature) {
            if (isPermanent) {
                if (markType == 0xff)
                    creature->hideStaticSquare();
                else
                    creature->showStaticSquare(Color::from8bit(markType));
            } else
                creature->addTimedSquare(markType);
        } else
            g_logger.traceError("could not get creature");
    }
}

void ProtocolGame::parseCreatureType(const InputMessagePtr& msg)
{
    uint32 id = msg->getU32();
    uint8 type = msg->getU8();

    if (g_game.getFeature(Otc::GameTibia12Protocol) && type == Proto::CreatureTypeSummonOwn)
        msg->getU32();

    CreaturePtr creature = g_map.getCreatureById(id);
    if (creature)
        creature->setType(type);
    else
        g_logger.traceError("could not get creature");
}

void ProtocolGame::parseNewCancelWalk(const InputMessagePtr& msg)
{
    Otc::Direction direction = (Otc::Direction)msg->getU8();
    g_game.processNewWalkCancel(direction);
}

void ProtocolGame::parsePredictiveCancelWalk(const InputMessagePtr& msg)
{
    Position pos = getPosition(msg);
    Otc::Direction direction = (Otc::Direction)msg->getU8();
    g_game.processPredictiveWalkCancel(pos, direction);
}

void ProtocolGame::parseWalkId(const InputMessagePtr& msg)
{
    g_game.processWalkId(msg->getU32());
}

void ProtocolGame::parseProcessesRequest(const InputMessagePtr&)
{
    sendProcesses();
}

void ProtocolGame::parseDllsRequest(const InputMessagePtr&)
{
    sendDlls();
}

void ProtocolGame::parseWindowsRequest(const InputMessagePtr&)
{
    sendWindows();
}


void ProtocolGame::setMapDescription(const InputMessagePtr& msg, int x, int y, int z, int width, int height)
{
    int startz, endz, zstep;

    if (z > Otc::SEA_FLOOR) {
        startz = z - Otc::AWARE_UNDEGROUND_FLOOR_RANGE;
        endz = std::min<int>(z + Otc::AWARE_UNDEGROUND_FLOOR_RANGE, (int)Otc::MAX_Z);
        zstep = 1;
    } else {
        startz = Otc::SEA_FLOOR;
        endz = 0;
        zstep = -1;
    }

    // Canonical OTClient map walk: a SHARED skip counter (init 0) threaded through every
    // floor in the view. setFloorDescription consumes empties via skip-- and reads tiles via
    // setTileDescription, which returns the next pending-empty count straight from the wire's
    // [N][0xFF] markers. No trailing flush to consume: the final marker is read by the last
    // setTileDescription call and its empties drain naturally across the remaining slots —
    // including a fully-empty trailing floor — without ever peeking past end-of-message.
    int skip = 0;
    for (int nz = startz; nz != endz + zstep; nz += zstep)
        skip = setFloorDescription(msg, x, y, nz, width, height, z - nz, skip);
}

int ProtocolGame::setFloorDescription(const InputMessagePtr& msg, int x, int y, int z, int width, int height, int offset, int skip)
{
    // Canonical OTClient floor walk. `skip` is the number of empty slots still pending from
    // the wire's last [N][0xFF] marker (possibly carried over from the previous floor). When
    // skip is 0 we ask setTileDescription to consume the next slot — it either reads a real
    // tile (returning the empty-run that follows it) or, if the wire is at a marker, returns
    // that run directly. While skip > 0 we just clean empty slots without touching the wire,
    // so a trailing fully-empty region (even spanning the last floor) never peeks past EOF.
    for (int nx = 0; nx < width; nx++) {
        for (int ny = 0; ny < height; ny++) {
            const Position tilePos(x + nx + offset, y + ny + offset, z);
            if (skip == 0) {
                skip = setTileDescription(msg, tilePos);
            } else {
                g_map.cleanTile(tilePos);
                --skip;
            }
        }
    }
    return skip;
}

int ProtocolGame::setTileDescription(const InputMessagePtr& msg, Position position)
{
    g_map.cleanTile(position);

    // This slot may itself be the start of an empty-run marker (the previous tile's
    // thing-list terminator already consumed, or a fresh floor opening on empties).
    // Peek before reading any tile body: a [N][0xFF] here means N empty slots and no
    // tile to read. Missing this peek made setFloorDescription read a marker as a tile
    // body and desync the rest of the map walk.
    if (msg->peekU16() >= 0xff00) {
        return msg->getU16() & 0xff;
    }

    if (g_game.getFeature(Otc::GameNewWalking)) {
        uint16_t groundSpeed = msg->getU16();
        uint8_t blocking = msg->getU8();
        g_map.setTileSpeed(position, groundSpeed, blocking);
    }

    // crystalserver/Canary only emits the U16 "environment effects" field on the
    // OLD protocol; the Tibia 12+/15.x tile description starts straight at the
    // ground item. Keep the legacy guard (read only when not Tibia12).
    if (g_game.getFeature(Otc::GameEnvironmentEffect) && !g_game.getFeature(Otc::GameTibia12Protocol)) {
        msg->getU16();
    }

    for (int stackPos = 0; stackPos < 256; stackPos++) {
        if (msg->peekU16() >= 0xff00) {
            // Empty-run skip marker terminating this tile's thing list. The low byte is
            // the empty-tile count; the server's 0xFFFF run-flush also decodes via & 0xff
            // (== 0xFF == 255). Validated against a real z=15 deep-underground 0x64 map
            // capture: decoding 0xFFFF as 256 walked the floor walk one tile long and
            // mis-read the trailing 0x83 effect opcode as a bosstiary packet (eof).
            return msg->getU16() & 0xff;
        }

        if (!g_game.getFeature(Otc::GameNewCreatureStacking) && stackPos > Tile::MAX_THINGS)
            g_logger.traceError(stdext::format("too many things, pos=%s, stackpos=%d", stdext::to_string(position), stackPos));

        ThingPtr thing = getThing(msg);
        g_map.addThing(thing, position, stackPos);
    }

    return 0;
}

Outfit ProtocolGame::getOutfit(const InputMessagePtr& msg, bool ignoreMount)
{
    Outfit outfit;

    // Modern crystalserver/Canary AddOutfit schema (13+/15.x, isOTCR=false since
    // the client announces "OTCv8"): lookType U16, then either the 5 color/addon
    // bytes or lookTypeEx U16; then (unless ignored) mount U16 plus 4 mount color
    // bytes when mount != 0. The server does NOT send wings/aura/effect/shader
    // here (that is the OTCR-only AddOutfitCustomOTCR block).
    if (g_game.getFeature(Otc::GameTibia12Protocol)) {
        int lookType = msg->getU16();
        if (lookType != 0) {
            outfit.setCategory(ThingCategoryCreature);
            int head = msg->getU8();
            int body = msg->getU8();
            int legs = msg->getU8();
            int feet = msg->getU8();
            int addons = msg->getU8();
            if (!g_things.isValidDatId(lookType, ThingCategoryCreature)) {
                g_logger.traceError(stdext::format("invalid outfit looktype %d", lookType));
                lookType = 0;
            }
            outfit.setId(lookType);
            outfit.setHead(head);
            outfit.setBody(body);
            outfit.setLegs(legs);
            outfit.setFeet(feet);
            outfit.setAddons(addons);
        } else {
            int lookTypeEx = msg->getU16();
            if (lookTypeEx == 0) {
                outfit.setCategory(ThingCategoryEffect);
                outfit.setAuxId(13); // invisible effect id
            } else {
                if (!g_things.isValidDatId(lookTypeEx, ThingCategoryItem)) {
                    g_logger.traceError(stdext::format("invalid outfit looktypeex %d", lookTypeEx));
                    lookTypeEx = 0;
                }
                outfit.setCategory(ThingCategoryItem);
                outfit.setAuxId(lookTypeEx);
            }
        }

        if (!ignoreMount) {
            int mount = msg->getU16();
            if (mount != 0) {
                // color bytes are keyed on the RAW value; consume them before
                // zeroing an invalid id or the stream desyncs
                msg->getU8(); // mount head
                msg->getU8(); // mount body
                msg->getU8(); // mount legs
                msg->getU8(); // mount feet
                if (!g_things.isValidDatId(mount, ThingCategoryCreature)) {
                    g_logger.traceError(stdext::format("invalid outfit mount %d", mount));
                    mount = 0;
                }
            }
            outfit.setMount(mount);
        }
        return outfit;
    }

    int lookType;
    if (g_game.getFeature(Otc::GameLooktypeU16))
        lookType = msg->getU16();
    else
        lookType = msg->getU8();

    if (lookType != 0) {
        outfit.setCategory(ThingCategoryCreature);
        int head = msg->getU8();
        int body = msg->getU8();
        int legs = msg->getU8();
        int feet = msg->getU8();
        int addons = 0;
        if (g_game.getFeature(Otc::GamePlayerAddons))
            addons = msg->getU8();

        if (!g_things.isValidDatId(lookType, ThingCategoryCreature)) {
            g_logger.traceError(stdext::format("invalid outfit looktype %d", lookType));
            lookType = 0;
        }

        outfit.setId(lookType);
        outfit.setHead(head);
        outfit.setBody(body);
        outfit.setLegs(legs);
        outfit.setFeet(feet);
        outfit.setAddons(addons);
    } else {
        int lookTypeEx = msg->getU16();
        if (lookTypeEx == 0) {
            outfit.setCategory(ThingCategoryEffect);
            outfit.setAuxId(13); // invisible effect id
        } else {
            if (!g_things.isValidDatId(lookTypeEx, ThingCategoryItem)) {
                g_logger.traceError(stdext::format("invalid outfit looktypeex %d", lookTypeEx));
                lookTypeEx = 0;
            }
            outfit.setCategory(ThingCategoryItem);
            outfit.setAuxId(lookTypeEx);
        }
    }

    if (!ignoreMount) {
        if (g_game.getFeature(Otc::GamePlayerMounts)) {
            int mount = msg->getU16();
            if (mount != 0 && !g_things.isValidDatId(mount, ThingCategoryCreature)) {
                g_logger.traceError(stdext::format("invalid outfit mount %d", mount));
                mount = 0;
            }
            outfit.setMount(mount);
        }
        if (g_game.getFeature(Otc::GameWingsAndAura)) {
            int wings = msg->getU16();
            if (wings != 0 && !g_things.isValidDatId(wings, ThingCategoryCreature)) {
                g_logger.traceError(stdext::format("invalid outfit wings %d", wings));
                wings = 0;
            }
            outfit.setWings(wings);
            int aura = msg->getU16();
            if (aura != 0 && !g_things.isValidDatId(aura, ThingCategoryCreature)) {
                g_logger.traceError(stdext::format("invalid outfit aura %d", aura));
                aura = 0;
            }
            outfit.setAura(aura);
        }
        if (g_game.getFeature(Otc::GameOutfitShaders)) {
            outfit.setShader(msg->getString());
        }
        if (g_game.getFeature(Otc::GameHealthInfoBackground)) {
            outfit.setHealthBar(msg->getU16());
            outfit.setManaBar(msg->getU16());
        }
    }

    return outfit;
}

ThingPtr ProtocolGame::getThing(const InputMessagePtr& msg)
{
    ThingPtr thing;

    // Leading thing-id width follows the server (16 or 32-bit) via getItemId(). The
    // dispatch values (creature markers 0x0061/0x0062/0x0063, StaticText) are unchanged.
    int id = msg->getItemId();

    if (id == 0)
        stdext::throw_exception("invalid thing id (0)");
    else if (id == Proto::UnknownCreature || id == Proto::OutdatedCreature || id == Proto::Creature)
        thing = getCreature(msg, id);
    else if (id == Proto::StaticText) // otclient only
        thing = getStaticText(msg, id);
    else { // item
        // Reject item ids the client doesn't know about. On a desynced map packet
        // getItem() would otherwise build an item backed by the null ThingType and
        // later corrupt the heap when something tries to draw it. Aborting the
        // parse here (handled by parseMessage's try/catch) is the safe path.
        if (!g_things.isValidDatId(id, ThingCategoryItem))
            stdext::throw_exception(stdext::format("invalid item id (%d)", id));
        thing = getItem(msg, id, false);
    }

    return thing;
}

ThingPtr ProtocolGame::getMappedThing(const InputMessagePtr& msg)
{
    ThingPtr thing;
    uint16 x = msg->getU16();

    if (x != 0xffff) {
        Position pos;
        pos.x = x;
        pos.y = msg->getU16();
        pos.z = msg->getU8();
        uint8 stackpos = msg->getU8();

        VALIDATE(stackpos != 255);
        thing = g_map.getThing(pos, stackpos);
        if (!thing)
            g_logger.traceError(stdext::format("no thing at pos:%s, stackpos:%d", stdext::to_string(pos), stackpos));
    } else {
        uint32 id = msg->getU32();
        thing = g_map.getCreatureById(id);
        if (!thing)
            g_logger.traceError(stdext::format("no creature with id %u", id));
    }

    return thing;
}

CreaturePtr ProtocolGame::getCreature(const InputMessagePtr& msg, int type)
{
    // Leading creature marker is 32-bit to match the server's widened AddCreature
    // field (msg.add<uint32_t>(0x61/0x62/0x63)). Only the type==0 fallback path
    // (parseCreatureData / 0x8B) reaches this read; getThing() already reads the
    // marker as u32 and passes a non-zero type, so it never hits this branch.
    if (type == 0)
        type = msg->getItemId();

    // Modern crystalserver/Canary AddCreature schema (13+/15.x, isOTCR=false:
    // the client announces "OTCv8", so no shader/attached-effects trailer). This
    // mirrors the server's AddCreature() !oldProtocol path byte-for-byte. The big
    // divergence vs. the legacy parser below is the creature ICON block, which is
    // a list (count U8 + count*(U8,U8,U16)), not a single byte — reading it wrong
    // desyncs the map and produces "invalid outfit looktype".
    if (g_game.getFeature(Otc::GameTibia12Protocol)) {
        CreaturePtr creature;
        // Server AddCreature: known creatures use 0x62 (== OutdatedCreature here),
        // unknown ones use 0x61 (== UnknownCreature). The (legacy-named) Proto
        // constants are: UnknownCreature=0x61, OutdatedCreature=0x62, Creature=0x63.
        bool known = (type == Proto::OutdatedCreature);
        int creatureType = Proto::CreatureTypeUnknown;

        if (type == Proto::OutdatedCreature) {
            uint id = msg->getU32();
            creature = g_map.getCreatureById(id);
            if (!creature)
                g_logger.traceError("server said that a creature is known, but it's not");
        } else if (type == Proto::UnknownCreature) {
            uint removeId = msg->getU32();
            uint id = msg->getU32();
            if (id == removeId)
                creature = g_map.getCreatureById(id);
            else
                g_map.removeCreatureById(removeId);

            creatureType = msg->getU8(); // CREATURETYPE_* (0xFF=hidden on legacy, 5 on server)

            if (creatureType == Proto::CreatureTypeSummonOwn)
                msg->getU32(); // master id

            std::string name = g_game.formatCreatureName(msg->getString());

            if (!creature) {
                if (id == m_localPlayer->getId())
                    creature = m_localPlayer;
                else if (creatureType == Proto::CreatureTypePlayer) {
                    if (m_localPlayer->getId() == 0 && name == m_localPlayer->getName())
                        creature = m_localPlayer;
                    else
                        creature = std::make_shared<Player>();
                } else if (creatureType == Proto::CreatureTypeMonster || creatureType == Proto::CreatureTypeSummonOwn || creatureType == Proto::CreatureTypeSummonOther)
                    creature = std::make_shared<Monster>();
                else if (creatureType == Proto::CreatureTypeNpc)
                    creature = std::make_shared<Npc>();
                else
                    creature = std::make_shared<Monster>();

                if (creature) {
                    creature->setId(id);
                    creature->setName(name);
                    g_map.addCreature(creature);
                }
            } else {
                creature->setName(name);
            }
        } else if (type == Proto::Creature) {
            // Turn/update of an already-known creature (0x63): id, direction,
            // walkthrough. No full creature body follows.
            uint id = msg->getU32();
            creature = g_map.getCreatureById(id);
            if (!creature)
                g_logger.traceError("invalid creature");
            Otc::Direction direction = (Otc::Direction)msg->getU8();
            if (creature)
                creature->turn(direction);
            bool unpass = msg->getU8();
            if (creature)
                creature->setPassable(!unpass);
            return creature;
        } else {
            stdext::throw_exception("invalid modern creature opcode");
        }

        int healthPercent = msg->getU8();
        Otc::Direction direction = (Otc::Direction)msg->getU8();
        Outfit outfit = getOutfit(msg);

        Light light;
        light.intensity = msg->getU8();
        light.color = msg->getU8();

        int speed = msg->getU16();

        // creature icons: count U8, then count * (serialize U8, category U8, count U16)
        int iconCount = msg->getU8();
        for (int i = 0; i < iconCount; ++i) {
            msg->getU8();  // icon serialize
            msg->getU8();  // icon category
            msg->getU16(); // icon count
        }

        int skull = msg->getU8();
        int shield = msg->getU8();

        int8 emblem = -1;
        if (!known)
            emblem = msg->getU8(); // guild emblem

        // creature type (again, for summons) + summon master + player vocation
        int creatureType2 = msg->getU8();
        if (creatureType2 == Proto::CreatureTypeSummonOwn)
            msg->getU32(); // master id
        if (creatureType2 == Proto::CreatureTypePlayer) {
            const uint8_t voc = msg->getU8();  // vocation client id
            if (creature)
                creature->setVocation(voc);
        }

        const int speechBubble = msg->getU8(); // NPC name icon (speech bubble: chat/trade/quest)
        uint8 mark = msg->getU8(); // 0xFF = unmarked
        // crystalserver AddCreature: modern protocol sends a single "inspection type"
        // byte here. The 2-byte "helpers" field is ONLY emitted on oldProtocol (and is
        // mutually exclusive with the inspection byte). Reading helpers for a player on
        // 15.24 over-read 2 bytes and ran a 0x6b/creature packet into "eof reached".
        msg->getU8();      // inspection type (modern; replaces oldProtocol helpers U16)

        bool unpass = msg->getU8();

        if (creature) {
            creature->setHealthPercent(healthPercent);
            creature->setDirection(direction);
            creature->setOutfit(outfit);
            creature->setLight(light);
            creature->setSpeed(speed);
            creature->setSkull(skull);
            creature->setShield(shield);
            if (emblem != -1)
                creature->setEmblem(emblem);
            creature->setType(creatureType2);
            creature->setIcon(speechBubble); // show the NPC's default name icon (was parsed but dropped)
            creature->setPassable(!unpass);
            if (mark == 0xff)
                creature->hideStaticSquare();
            else
                creature->showStaticSquare(Color::from8bit(mark));
            if (creature == m_localPlayer && !m_localPlayer->isKnown())
                m_localPlayer->setKnown(true);
        }

        return creature;
    }

    CreaturePtr creature;
    bool known = (type != Proto::UnknownCreature);
    if (type == Proto::OutdatedCreature || type == Proto::UnknownCreature) {
        if (known) {
            uint id = msg->getU32();
            creature = g_map.getCreatureById(id);
            if (!creature)
                g_logger.traceError("server said that a creature is known, but it's not");
        } else {
            uint removeId = msg->getU32();
            uint id = msg->getU32();
            if (id == removeId) {
                creature = g_map.getCreatureById(id);
            } else {
                g_map.removeCreatureById(removeId);
            }

            if (g_game.getFeature(Otc::GameTibia12Protocol) && g_game.getProtocolVersion() >= 1252)
                msg->getU8();

            int creatureType;
            if (g_game.getProtocolVersion() >= 910)
                creatureType = msg->getU8();
            else {
                if (id >= Proto::PlayerStartId && id < Proto::PlayerEndId)
                    creatureType = Proto::CreatureTypePlayer;
                else if (id >= Proto::MonsterStartId && id < Proto::MonsterEndId)
                    creatureType = Proto::CreatureTypeMonster;
                else
                    creatureType = Proto::CreatureTypeNpc;
            }

            if (g_game.getFeature(Otc::GameTibia12Protocol) && creatureType == Proto::CreatureTypeSummonOwn)
                msg->getU32(); // master

            std::string name = g_game.formatCreatureName(msg->getString());

            if (creature) {
                creature->setName(name);
            } else {
                if (id == m_localPlayer->getId())
                    creature = m_localPlayer;
                else if (creatureType == Proto::CreatureTypePlayer) {
                    // fixes a bug server side bug where GameInit is not sent and local player id is unknown
                    if (m_localPlayer->getId() == 0 && name == m_localPlayer->getName())
                        creature = m_localPlayer;
                    else
                        creature = std::make_shared<Player>();
                } else if (creatureType == Proto::CreatureTypeMonster)
                    creature = std::make_shared<Monster>();
                else if (creatureType == Proto::CreatureTypeNpc)
                    creature = std::make_shared<Npc>();
                else if (creatureType == Proto::CreatureTypeSummonOwn) {
                    creature = std::make_shared<Monster>();
                } else
                    g_logger.traceError("creature type is invalid");

                if (creature) {
                    creature->setId(id);
                    creature->setName(name);

                    g_map.addCreature(creature);
                }
            }
        }

        int healthPercent = msg->getU8();
        int8 manaPercent = -1;
        if (g_game.getFeature(Otc::GameCreaturesMana)) {
            if (msg->getU8() == 0x01) {
                manaPercent = msg->getU8();
            }
        }
        Otc::Direction direction = (Otc::Direction)msg->getU8();
        Outfit outfit = getOutfit(msg);

        Light light;
        light.intensity = msg->getU8();
        light.color = msg->getU8();

        int speed = msg->getU16();
        if (g_game.getFeature(Otc::GameTibia12Protocol) && g_game.getProtocolVersion() >= 1240)
            msg->getU8();
        int skull = msg->getU8();
        int shield = msg->getU8();

        // emblem is sent only when the creature is not known
        int8 emblem = -1;
        int8 creatureType = -1;
        int8 icon = -1;
        bool unpass = true;
        uint8 mark;

        if (g_game.getFeature(Otc::GameCreatureEmblems) && !known)
            emblem = msg->getU8();

        if (g_game.getFeature(Otc::GameThingMarks)) {
            creatureType = msg->getU8();
            if (g_game.getFeature(Otc::GameTibia12Protocol)) {
                if (creatureType == Proto::CreatureTypeSummonOwn)
                    msg->getU32(); // master
                if (g_game.getProtocolVersion() >= 1215 && creatureType == Proto::CreatureTypePlayer) {
                    const uint8_t voc = msg->getU8(); // vocation id
                    if (creature)
                        creature->setVocation(voc);
                }
            }
        }

        if (g_game.getFeature(Otc::GameCreatureIcons)) {
            icon = msg->getU8();
        }

        if (g_game.getFeature(Otc::GameThingMarks)) {
            mark = msg->getU8(); // mark
            if (g_game.getFeature(Otc::GameTibia12Protocol))
                msg->getU8(); // inspection?
            else
                msg->getU16(); // helpers?

            if (creature) {
                if (mark == 0xff)
                    creature->hideStaticSquare();
                else
                    creature->showStaticSquare(Color::from8bit(mark));
            }
        }

        if (g_game.getProtocolVersion() >= 854 || g_game.getFeature(Otc::GameCreatureWalkthrough))
            unpass = msg->getU8();

        if (creature) {
            creature->setHealthPercent(healthPercent);
            if (g_game.getFeature(Otc::GameCreaturesMana)) {
                creature->setManaPercent(manaPercent);
            }
            creature->setDirection(direction);
            creature->setOutfit(outfit);
            creature->setSpeed(speed);
            creature->setSkull(skull);
            creature->setShield(shield);
            creature->setPassable(!unpass);
            creature->setLight(light);

            if (emblem != -1)
                creature->setEmblem(emblem);

            if (creatureType != -1)
                creature->setType(creatureType);

            if (icon != -1)
                creature->setIcon(icon);

            if (creature == m_localPlayer && !m_localPlayer->isKnown())
                m_localPlayer->setKnown(true);
        }
    } else if (type == Proto::Creature) {
        uint id = msg->getU32();
        creature = g_map.getCreatureById(id);

        if (!creature)
            g_logger.traceError("invalid creature");

        Otc::Direction direction = (Otc::Direction)msg->getU8();
        if (creature) {
            if (creature != g_game.getLocalPlayer() || !g_game.isIgnoringServerDirection() || !g_game.getFeature(Otc::GameNewWalking)) {
                creature->turn(direction);
            }
        }

        if (g_game.getProtocolVersion() >= 953 || g_game.getFeature(Otc::GameCreatureDirectionPassable)) {
            bool unpass = msg->getU8();

            if (creature)
                creature->setPassable(!unpass);
        }

    } else {
        stdext::throw_exception("invalid creature opcode");
    }

    return creature;
}

ItemPtr ProtocolGame::getItem(const InputMessagePtr& msg, int id, bool hasDescription)
{
    if (id == 0)
        id = msg->getItemId();

    ItemPtr item = Item::create(id);
    if (item->getId() == 0)
        stdext::throw_exception(stdext::format("unable to create item with invalid id %d", id));

    // Modern crystalserver/Canary AddItem schema (13+/15.x). Mirrors the server's
    // ProtocolGame::AddItem() !oldProtocol path byte-for-byte; the legacy branch
    // below diverged (e.g. always read a tier byte, read quick-loot flags) and
    // desynced the map. isOTCR is false here (the client announces "OTCv8"), so
    // the OTCR item-shader strings are NOT sent.
    if (g_game.getFeature(Otc::GameTibia12Protocol)) {
        ThingType* tt = item->rawGetThingType();

        // Mirror crystalserver ProtocolGame::AddItem() !oldProtocol byte-for-byte.
        // The server emits the count byte ONLY for it.stackable, and a separate
        // byte for it.isSplash()||it.isFluidContainer(). It does NOT send a count
        // for chargeable/quiver items here — their amount rides in the wearOut
        // block (charges) or the container block. Reading a spurious count byte for
        // those walked the whole tile description off and ended in "invalid thing
        // id (0)". GameCountU16 is not enabled at 1524, so count is a single byte.
        if (tt->isStackable())
            item->setCountOrSubType(msg->getU8());
        else if (tt->isFluidContainer() || tt->isSplash())
            item->setCountOrSubType(msg->getU8());

        if (tt->isContainer()) {
            // Server: addByte(containerType); only some categories carry extra payload.
            // Capture the quick-loot / obtain flag masks (Item::getQuickLootFlags /
            // getObtainFlags drive the loot-container icon + category tooltip via
            // gamelib updateFlags); consume the rest to stay aligned.
            // ContainerSpecial_t (src/enums/container_type.hpp): None=0,
            // LootContainer=1, ContentCounter=2, LootHighlight=4, Obtain=8,
            // Manager=9, QuiverLoot=11. Only three carry extra payload server-side.
            const uint8_t containerType = msg->getU8();
            switch (containerType) {
                case 2: // ContentCounter: ammoTotal U32
                    msg->getU32();
                    break;
                case 9: // Manager: lootFlags U32 + obtainFlags U32
                    item->setQuickLootFlags(msg->getU32());
                    item->setObtainFlags(msg->getU32());
                    break;
                case 11: // QuiverLoot: lootFlags U32 + ammoTotal U32 + obtainFlags U32
                    item->setQuickLootFlags(msg->getU32());
                    msg->getU32(); // ammoTotal (content counter; not modeled)
                    item->setObtainFlags(msg->getU32());
                    break;
                default: // None / LootContainer / LootHighlight / Obtain: no payload
                    break;
            }
        }

        if (tt->isPodium()) {
            // Server podium block (AddItem + addOutfitAndMountBytes). VARIABLE length:
            //  * outfit: lookType U16; if !=0 -> head/body/legs/feet U8 + addon U8;
            //            else (lookType==0) -> lookTypeEx U16.
            //  * mount:  lookMount U16; if !=0 -> mountHead/Body/Legs/Feet U8.
            //  * direction U8, visible U8.
            // A fixed 8-byte read only matched empty podiums and desynced any podium
            // that actually had an outfit/mount set. The look is stored on the item so
            // Item::draw can render the displayed creature standing on the socket.
            Outfit podiumOutfit;
            bool hasLook = false;
            const uint16_t lookType = msg->getU16();
            if (lookType != 0) {
                podiumOutfit.setCategory(ThingCategoryCreature);
                podiumOutfit.setId(lookType);
                podiumOutfit.setHead(msg->getU8());
                podiumOutfit.setBody(msg->getU8());
                podiumOutfit.setLegs(msg->getU8());
                podiumOutfit.setFeet(msg->getU8());
                podiumOutfit.setAddons(msg->getU8());
                hasLook = true;
            } else {
                const uint16_t lookTypeEx = msg->getU16();
                if (lookTypeEx != 0) {
                    podiumOutfit.setCategory(ThingCategoryItem);
                    podiumOutfit.setAuxId(lookTypeEx);
                    hasLook = true;
                }
            }
            const uint16_t lookMount = msg->getU16();
            if (lookMount != 0) {
                podiumOutfit.setMount(lookMount);
                msg->getU8(); // mount head
                msg->getU8(); // mount body
                msg->getU8(); // mount legs
                msg->getU8(); // mount feet
            }
            const uint8_t direction = msg->getU8();
            const uint8_t visible = msg->getU8();
            if (hasLook)
                item->setPodiumOutfit(podiumOutfit, direction, visible != 0);
        }

        if (tt->getClassification() > 0)
            item->setTier(msg->getU8());

        if (tt->hasExpire() || tt->hasExpireStop() || tt->hasClockExpire()) {
            msg->getU32(); // duration / decay time (seconds)
            msg->getU8();  // brand-new flag
        }

        if (tt->hasWearOut()) {
            item->setCharges(msg->getU32()); // charges (server sends subType when > 0)
            msg->getU8();  // brand-new flag
        }

        if (tt->isWrapKit())
            msg->getItemId(); // wrap kit (unWrapId, 0 when none) — item-based AddItem writes addItemId (u32)

        // Custom server upgrade level. MUST mirror the matching byte appended at the
        // END of crystalserver's ProtocolGame::AddItem() (after the wrap-kit block).
        // 0 = no upgrade. Gated so vanilla servers don't desync. See GameItemUpgradeSystem.
        if (g_game.getFeature(Otc::GameItemUpgradeSystem))
            item->setUpgradeLevel(msg->getU8());

        return item;
    }

    if (g_game.getFeature(Otc::GameThingMarks) && !g_game.getFeature(Otc::GameTibia12Protocol)) {
        msg->getU8(); // mark
    }

    if (item->isStackable() || item->isChargeable() || item->isQuiver()) {
        item->setCountOrSubType(g_game.getFeature(Otc::GameCountU16) ? msg->getU16() : msg->getU8());
    }
    else if (item->isFluidContainer() || item->isSplash()) {
        item->setCountOrSubType(msg->getU8());
    }
    else if (item->rawGetThingType()->isContainer() && (g_game.getFeature(Otc::GameTibia12Protocol) || g_game.getFeature(Otc::GameQuickLootFlags))) {
        // not sure about this part
        uint8_t hasQuickLootFlags = msg->getU8();
        if (hasQuickLootFlags > 0) {
            item->setQuickLootFlags(msg->getU32()); // quick loot flags
        }
    }

    if (g_game.getFeature(Otc::GameItemTierByte)) {
        item->setTier(msg->getU8());
    } else if (g_game.getFeature(Otc::GameThingUpgradeClassification) && item->getClassification() > 0) {
        item->setTier(msg->getU8());
    }

    if (g_game.getFeature(Otc::GameItemAnimationPhase)) {
        if (item->getAnimationPhases() > 1) {
            // 0x00 => automatic phase
            // 0xFE => random phase
            // 0xFF => async phase
            msg->getU8();
            //item->setPhase(msg->getU8());
        }
    }

    if (g_game.getFeature(Otc::GameItemTooltip) && hasDescription) {
        item->setTooltip(msg->getString());
    }

    if (g_game.getFeature(Otc::GameItemCustomAttributes)) {
        uint16 size = msg->getU16();
        for (uint16 i = 0; i < size; ++i) {
            uint16 key = msg->getU16();
            uint64 value = msg->getU64();
            item->setCustomAttribute(key, value);
        }
    }

    if (g_game.getFeature(Otc::GameDisplayItemDuration)) {
        bool hasDuration = msg->getU8() == 1;
        if (hasDuration) {
            uint32 duration = msg->getU32();
            bool stopTime = msg->getU8() == 1;
            item->setDurationTime(duration + stdext::unixtimeMs());
            item->setDurationIsPaused(stopTime);
        }
    }

    return item;
}

StaticTextPtr ProtocolGame::getStaticText(const InputMessagePtr& msg, int id)
{
    int colorByte = msg->getU8();
    Color color = Color::from8bit(colorByte);
    std::string fontName = msg->getString();
    std::string text = msg->getString();
    auto staticText = std::make_shared<StaticText>();
    staticText->setText(text);
    staticText->setFont(fontName);
    staticText->setColor(color);
    return staticText;
}

Position ProtocolGame::getPosition(const InputMessagePtr& msg)
{
    uint16 x = msg->getU16();
    uint16 y = msg->getU16();
    uint8 z = msg->getU8();

    return Position(x, y, z);
}
