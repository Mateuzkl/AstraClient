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

#ifndef LOCALPLAYER_H
#define LOCALPLAYER_H

#include "player.h"
#include "walkmatrix.h"

#include <map>
#include <set>

// @bindclass
class LocalPlayer : public Player
{
    enum {
        PREWALK_TIMEOUT = 1000
    };

public:
    LocalPlayer();

    void draw(const Point& dest, bool animate = true, LightView* lightView = nullptr) override;

    void unlockWalk() { m_walkLockExpiration = 0; }
    void lockWalk(int millis = 200);
    void stopAutoWalk();
    bool autoWalk(Position destination, bool retry = false);
    bool canWalk(Otc::Direction direction, bool ignoreLock = false);
    bool isWalkLocked() {
        return (m_walkLockExpiration != 0 && g_clock.millis() < m_walkLockExpiration);
    }
    int getPreWalkLockedDelay() { return m_walkLockExpiration; }
    void setTeleportWalkDelay(int delay) { m_teleportWalkDelay = delay; }
    int getTeleportWalkDelay() { return m_teleportWalkDelay; }
    bool isParalyzed() { return m_speed == 0 || (m_states & Otc::IconParalyze) != 0; }
    bool isRooted() { return (m_states & 524288) != 0; }
    void turn(Otc::Direction) override;

    void setStates(int states);
    void setSkill(uint8_t skill, int level, int levelPercent);
    void setBaseSkill(uint8_t skill, int baseLevel);
    void setHealth(double health, double maxHealth);
    void setFreeCapacity(double freeCapacity);
    void setTotalCapacity(double totalCapacity);
    void setBaseCapacity(double baseCapacity);
    void setExperience(double experience);
    void setLevel(double level, double levelPercent);
    void setMana(double mana, double maxMana);
    void setMagicLevel(double magicLevel, double magicLevelPercent);
    void setBaseMagicLevel(double baseMagicLevel);
    void setSoul(double soul);
    void setStamina(double stamina);
    void setExpRates(int base, int lowLevel, int storeBoost, int staminaMulti);
    void setStoreExpBoost(int seconds, bool canBuy);
    void setKnown(bool known) { m_known = known; }
    void setPendingGame(bool pending) { m_pending = pending; }
    void setInventoryItem(Otc::InventorySlot inventory, const ItemPtr& item);
    void setVocation(int vocation);
    void setPremium(bool premium);
    void setRegenerationTime(double regenerationTime);
    void setOfflineTrainingTime(double offlineTrainingTime);
    void setSpells(const std::vector<int>& spells);
    void setBlessings(int blessings);
    void setTaints(int taints);
    void setResourceValue(int resource, uint64 amount);

    int getStates() { return m_states; }
    std::vector<int> getStatesList();
    int getSkillLevel(uint8_t skill) { return skill < m_skillsLevel.size() ? m_skillsLevel[skill] : 0; }
    int getSkillBaseLevel(uint8_t skill) { return skill < m_skillsBaseLevel.size() ? m_skillsBaseLevel[skill] : 0; }
    int getSkillLevelPercent(uint8_t skill) { return skill < m_skillsLevelPercent.size() ? m_skillsLevelPercent[skill] : 0; }
    // Combat "special" skills (life/mana leech, crit, onslaught, ruse, momentum,
    // transcendence, ...) keyed by the gamelib Skill.* ids. Stored as the display
    // percent (e.g. 35.7 for 35.7%) and fed to the Skills window via getSpecialSkill.
    void setSpecialSkill(int id, double value) { m_specialSkills[id] = value; }
    double getSpecialSkill(int id) { const auto it = m_specialSkills.find(id); return it != m_specialSkills.end() ? it->second : 0.0; }
    int getVocation() { return m_vocation; }
    double getHealth() { return m_health; }
    double getMaxHealth() { return m_maxHealth; }
    double getFreeCapacity() { return m_freeCapacity; }
    double getTotalCapacity() { return m_totalCapacity; }
    double getBaseCapacity() { return m_baseCapacity >= 0 ? m_baseCapacity : m_totalCapacity; }
    double getExperience() { return m_experience; }
    double getLevel() { return m_level; }
    double getLevelPercent() { return m_levelPercent; }
    double getMana() { return m_mana; }
    double getMaxMana() { return std::max<double>(m_mana, m_maxMana); }
    // Magic shield (utamo vita) capacity from AddPlayerStats. remaining>0 == shield active.
    double getManaShield() { return m_manaShield; }
    double getMaxManaShield() { return m_maxManaShield; }
    // Defined in localplayer.cpp so it can fire onManaShieldChange (like setMana),
    // letting the topbar / healthinfo update the utamo vita bar live.
    void setManaShield(double remaining, double total);
    double getMagicLevel() { return m_magicLevel; }
    double getMagicLevelPercent() { return m_magicLevelPercent; }
    double getBaseMagicLevel() { return m_baseMagicLevel; }
    double getSoul() { return m_soul; }
    double getStamina() { return m_stamina; }
    int getBaseExpRate() { return m_baseXpGain; }
    int getLowLevelRate() { return m_grindingXpBoost; }
    int getExpBoostRate() { return m_storeXpBoostPercent; }
    int getStaminaRate() { return m_staminaXpBoost; }
    int getStoreExpBoostTime() { return m_storeXpBoostTime; }
    double getRegenerationTime() { return m_regenerationTime; }
    double getOfflineTrainingTime() { return m_offlineTrainingTime; }
    std::vector<int> getSpells() { return m_spells; }
    ItemPtr getInventoryItem(Otc::InventorySlot inventory) { return m_inventoryItems[inventory]; }
    int getBlessings() { return m_blessings; }
    // Reliable "do I have the 5 blesses?" signal from the 0x9C packet's status byte
    // (1 = Disabled/<5 blesses, 2 = normal/5-6, 3 = green/7+). getBlessings() only
    // carries the cosmetic glow flag, which is NOT a dependable blessed indicator.
    void setBlessStatus(int status);
    int getBlessStatus() { return m_blessStatus; }
    int getTaints() { return m_taints; }
    int getGroupType() { return m_groupType; }
    int getMagicLoyalty() { return m_magicLoyalty; }
    int getSkillLoyalty(uint8_t skill) { return skill < m_skillsLoyalty.size() ? m_skillsLoyalty[skill] : 0; }
    int getMonkPassive() { return m_monkPassive; }
    void setMonkPassive(int monkPassive) { m_monkPassive = monkPassive; }
    std::map<int, int> getMagicBoosts() { return m_magicBoosts; }
    void setMagicBoost(int combatType, int value) { m_magicBoosts[combatType] = value; }
    int getInventoryCount(int itemId, int upgradeTier = 0);
    bool hasEquippedItemId(int itemId, int upgradeTier = 0);
    // Authoritative per-item totals pushed by the server via the 0xF5 packet
    // (parsePlayerInventory). The server counts the WHOLE inventory recursively,
    // including closed containers, so this is the only source that stays correct
    // when a backpack is shut. getInventoryCount() prefers it once received and
    // falls back to the open-container scan only until the first 0xF5 arrives.
    void setInventoryItemsCount(const std::map<int, int>& counts);
    bool hasServerInventoryCount() { return m_inventoryIdsReceived; }
    uint64 getResourceValue(int resource);
    // Active "Show in HUD" conditions, keyed by the Lua condition id (string, so
    // both numeric state ids and named ids like skulls/emblems are supported).
    // Consumed by MapView::drawPlayerHudConditions to draw the HUD ring.
    void addHUDCondition(const std::string& condition) { m_hudConditions.insert(condition); }
    void removeHUDCondition(const std::string& condition) { m_hudConditions.erase(condition); }
    bool hasHUDCondition(const std::string& condition) { return m_hudConditions.find(condition) != m_hudConditions.end(); }
    const std::set<std::string>& getHUDConditions() { return m_hudConditions; }

    bool hasSight(const Position& pos);
    bool isKnown() { return m_known; }
    bool isAutoWalking() { return m_autoWalkDestination.isValid(); }
    bool isServerWalking() override { return m_serverWalking; }
    bool isPremium() { return m_premium; }
    bool isPendingGame() { return m_pending; }

    LocalPlayerPtr asLocalPlayer() { return static_self_cast<LocalPlayer>(); }
    bool isLocalPlayer() override { return true; }

    void onAppear() override;
    void onPositionChange(const Position& newPos, const Position& oldPos) override;

    // pre walking
    void preWalk(Otc::Direction direction);
    bool isPreWalking() override { return !m_preWalking.empty(); }
    Position getPrewalkingPosition(bool beforePrewalk = false) override {
        if(m_preWalking.empty())
            return m_position;
        else if (!beforePrewalk && m_preWalking.size() == 1)
            return m_position;
        auto ret = m_preWalking.rbegin();
        if(!beforePrewalk)
            ret++;
        return *ret; 
    }

    uint32_t getWalkPrediction(const Position& pos)
    {
        return m_walkMatrix.get(pos);
    };

    std::string dumpWalkMatrix()
    {
        return m_walkMatrix.dump();
    }

    void startServerWalking() { m_serverWalking = true; }
    void finishServerWalking() { m_serverWalking = false; }

protected:
    void walk(const Position& oldPos, const Position& newPos) override;
    void cancelWalk(Otc::Direction direction = Otc::InvalidDirection);
    
    void cancelNewWalk(Otc::Direction dir);
    bool predictiveCancelWalk(const Position& pos, uint32_t predictionId, Otc::Direction dir);
    
    bool retryAutoWalk();
    void stopWalk() override;

    friend class Game;

protected:
    void updateWalkOffset(uint8 totalPixelsWalked, bool inNextFrame = false) override;
    void updateWalk() override;
    void terminateWalk() override;

private:
    // walk related
    Position m_autoWalkDestination;
    Position m_lastAutoWalkPosition;
    int m_lastAutoWalkRetries = 0;
    ScheduledEventPtr m_serverWalkEndEvent;
    ScheduledEventPtr m_autoWalkContinueEvent;
    ticks_t m_walkLockExpiration;
    ticks_t m_teleportWalkDelay;

    // walking and pre walking
    std::list<Position> m_preWalking;
    bool m_serverWalking = false;
    bool m_lastPrewalkDone = false;
    WalkMatrix m_walkMatrix;

    bool m_premium = false;
    bool m_known = false;
    bool m_pending = false;

    ItemPtr m_inventoryItems[Otc::LastInventorySlot];
    // Server-pushed inventory totals (itemId -> total count across the whole
    // inventory, all tiers aggregated). See setInventoryItemsCount / 0xF5.
    std::map<int, int> m_inventoryItemsCount;
    bool m_inventoryIdsReceived = false;
    Timer m_idleTimer;

    std::vector<int> m_skillsLevel;
    std::vector<int> m_skillsBaseLevel;
    std::vector<int> m_skillsLevelPercent;
    std::vector<int> m_skillsLoyalty;
    std::map<int, double> m_specialSkills;
    std::vector<int> m_spells;
    std::set<std::string> m_hudConditions;
    std::map<int, uint64> m_resources;

    int m_states;
    int m_vocation;
    // xp gain rates from 0xA0 (percent values; -1 = not received yet so the
    // first server update always fires the change events)
    int m_baseXpGain = -1;
    int m_grindingXpBoost = -1;
    int m_storeXpBoostPercent = -1;
    int m_staminaXpBoost = -1;
    int m_storeXpBoostTime = -1;
    int m_blessings;
    int m_blessStatus = 2; // default "blessed" so Auto Bless doesn't fire before the first 0x9C
    int m_taints;
    int m_groupType;
    int m_magicLoyalty;
    int m_monkPassive;
    std::map<int, int> m_magicBoosts;

    double m_health;
    double m_maxHealth;
    double m_freeCapacity;
    double m_totalCapacity;
    double m_baseCapacity;
    double m_experience;
    double m_level;
    double m_levelPercent;
    double m_mana;
    double m_maxMana;
    double m_manaShield = 0;
    double m_maxManaShield = 0;
    double m_magicLevel;
    double m_magicLevelPercent;
    double m_baseMagicLevel;
    double m_soul;
    double m_stamina;
    double m_regenerationTime;
    double m_offlineTrainingTime;
};

#endif
