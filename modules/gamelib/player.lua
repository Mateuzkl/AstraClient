-- @docclass Player

PlayerStates = {
  Hungry = -1,
  None = 0,
  Poison = 1,
  Burn = 2,
  Energy = 4,
  Drunk = 8,
  ManaShield = 16,
  Paralyze = 32,
  Haste = 64,
  Swords = 128,
  Drowning = 256,
  Freezing = 512,
  Dazzled = 1024,
  Cursed = 2048,
  PartyBuff = 4096,
  PzBlock = 8192,
  Pz = 16384,
  Bleeding = 32768,
  --Hungry = 65536,
  SufferringLesserHex = 65536,
  SufferringIntenserHex = 131072,
  SufferringGreaterHex = 262144,
  Rooted = 524288,
  Feared = 1048576,
  CurseI = 2097152,
  CurseII = 4194304,
  CurseIII = 8388608,
  CurseIV = 16777216,
  CurseV = 33554432,
  NewMagicShield = 67108864,
  Agony = 134217728,
  Powerless = 268435456,
  Mentored = 536870912,
}

TaintsDescriptions = {
  [1] = "Since you are in Bakragore's lairs, you are suffering from the following penalties:\n* 6% chance that a melee foe will switch positions with a nearby character.",
  [2] = "Since you are in Bakragore's lairs, you are suffering from the following penalties:\n* 6% chance that a melee foe will switch positions with a nearby character.\n* 6.25% chance that an even more powerful foe will rise from the corpse of a killed monster.",
  [3] = "Since you are in Bakragore's lairs, you are suffering from the following penalties:\n* 6% chance that a melee foe will switch positions with a nearby character.\n* 6.25% chance that an even more powerful foe will rise from the corpse of a killed monster.\n* Monsters gain additional abilities.",
  [4] = "Since you are in Bakragore's lairs, you are suffering from the following penalties:\n* 6% chance that a melee foe will switch positions with a nearby character.\n* 6.25% chance that an even more powerful foe will rise from the corpse of a killed monster.\n* Monsters gain additional abilities.\n* Total damage taken by characters is increased by 14%.",
  [5] = "Since you are in Bakragore's lairs, you are suffering from the following penalties:\n* Due to the influence of Bakragore, all penalties are increased, but in return, the loot is improved.",
  [6] = "Since you are in Bakragore's lairs, you are suffering from the following penalties:\n* Due to the influence of Bakragore, all penalties are increased, but in return, the loot is improved.\n* 9% chance that a melee foe will switch positions with a nearby character.",
  [7] = "Since you are in Bakragore's lairs, you are suffering from the following penalties:\n* Due to the influence of Bakragore, all penalties are increased, but in return, the loot is improved.\n* 9% chance that a melee foe will switch positions with a nearby character.\n* 9.375% chance that an even more powerful foe will rise from the corpse of a killed monster.",
  [8] = "Since you are in Bakragore's lairs, you are suffering from the following penalties:\n* Due to the influence of Bakragore, all penalties are increased, but in return, the loot is improved.\n* 9% chance that a melee foe will switch positions with a nearby character.\n* 9.375% chance that an even more powerful foe will rise from the corpse of a killed monster.\n* Monsters gain additional abilities.",
  [9] = "Since you are in Bakragore's lairs, you are suffering from the following penalties:\n* Due to the influence of Bakragore, all penalties are increased, but in return, the loot is improved.\n* 9% chance that a melee foe will switch positions with a nearby character.\n* 9.375% chance that an even more powerful foe will rise from the corpse of a killed monster.\n* Monsters gain additional abilities.\n* Total damage taken by characters is increased by 21%.",
}

Icons = {}
Icons[PlayerStates.Poison] = { tooltip = tr('You are poisoned'), path = '/images/game/states/poisoned', id = 'condition_poisoned' }
Icons[PlayerStates.Burn] = { tooltip = tr('You are burning'), path = '/images/game/states/burning', id = 'condition_burning' }
Icons[PlayerStates.Energy] = { tooltip = tr('You are electrified'), path = '/images/game/states/electrified', id = 'condition_electrified' }
Icons[PlayerStates.Drunk] = { tooltip = tr('You are drunk'), path = '/images/game/states/drunk', id = 'condition_drunk' }
Icons[PlayerStates.ManaShield] = { tooltip = tr('You are protected by a magic shield'), path = '/images/game/states/magic_shield', id = 'condition_magic_shield' }
Icons[PlayerStates.Paralyze] = { tooltip = tr('You are paralysed'), path = '/images/game/states/slowed', id = 'condition_slowed' }
Icons[PlayerStates.Haste] = { tooltip = tr('You are hasted'), path = '/images/game/states/haste', id = 'condition_haste' }
Icons[PlayerStates.Swords] = { tooltip = tr('You may not logout during a fight'), path = '/images/game/states/logout_block', id = 'condition_logout_block' }
Icons[PlayerStates.Drowning] = { tooltip = tr('You are drowning'), path = '/images/game/states/drowning', id = 'condition_drowning' }
Icons[PlayerStates.Freezing] = { tooltip = tr('You are freezing'), path = '/images/game/states/freezing', id = 'condition_freezing' }
Icons[PlayerStates.Dazzled] = { tooltip = tr('You are dazzled'), path = '/images/game/states/dazzled', id = 'condition_dazzled' }
Icons[PlayerStates.Cursed] = { tooltip = tr('You are cursed'), path = '/images/game/states/cursed', id = 'condition_cursed' }
Icons[PlayerStates.PartyBuff] = { tooltip = tr('You are strengthened'), path = '/images/game/states/strengthened', id = 'condition_strengthened' }
Icons[PlayerStates.PzBlock] = { tooltip = tr('You may not logout or enter a protection zone'), path = '/images/game/states/protection_zone_block', id = 'condition_protection_zone_block' }
Icons[PlayerStates.Pz] = { tooltip = tr('You are within a protection zone'), path = '/images/game/states/protection_zone', id = 'condition_protection_zone' }
Icons[PlayerStates.Bleeding] = { tooltip = tr('You are bleeding'), path = '/images/game/states/bleeding', id = 'condition_bleeding' }
Icons[PlayerStates.Hungry] = { tooltip = tr('You are hungry'), path = '/images/game/states/hungry', id = 'condition_hungry' }
Icons[PlayerStates.SufferringLesserHex] = { tooltip = tr('You are sufferring lesser hex'), path = '/images/game/states/sufferringlesserhex', id = 'condition_sufferringlesserhex' }
Icons[PlayerStates.SufferringIntenserHex] = { tooltip = tr('You are sufferring intenser hex'), path = '/images/game/states/sufferringintenserhex', id = 'condition_sufferringintenserhex' }
Icons[PlayerStates.SufferringGreaterHex] = { tooltip = tr('You are sufferring greater hex'), path = '/images/game/states/sufferringgreaterhex', id = 'condition_sufferringgreaterhex' }
Icons[PlayerStates.Rooted] = { tooltip = tr('You are rooted'), path = '/images/game/states/rooted', id = 'condition_rooted' }
Icons[PlayerStates.Feared] = { tooltip = tr('You are feared'), path = '/images/game/states/feared', id = 'condition_feared' }
Icons[PlayerStates.CurseI] = { tooltip = tr('If you are in Goshnar\'s lairs, you are sufferring from the following penalty:\n- 10%% chance that a creature teleports near you'), path = '/images/game/states/cursei', id = 'condition_cursei' }
Icons[PlayerStates.CurseII] = { tooltip = tr('If you are in Goshnar\'s lairs, you are sufferring from the following penalty:\n- 10%% chance that a creature teleports near you\n 0.5%% chance that a new creature spawns near you if you hit another creature'), path = '/images/game/states/curseii', id = 'condition_curseii' }
Icons[PlayerStates.CurseIII] = { tooltip = tr('If you are in Goshnar\'s lairs, you are sufferring from the following penalty:\n- 10%% chance that a creature teleports near you\n 0.5%% chance that a new creature spawns near you if you hit another creature\n- received damage increased by 15%%'), path = '/images/game/states/curseiii', id = 'condition_curseiii' }
Icons[PlayerStates.CurseIV] = { tooltip = tr('If you are in Goshnar\'s lairs, you are sufferring from the following penalty:\n- 10%% chance that a creature teleports near you\n 0.5%% chance that a new creature spawns near you if you hit another creature\n- received damage increased by 15%%\n - 10%% chance that a creature will fully heal itself instead of dying'), path = '/images/game/states/curseiv', id = 'condition_curseiv' }
Icons[PlayerStates.CurseV] = { tooltip = tr('If you are in Goshnar\'s lairs, you are sufferring from the following penalty:\n- 10%% chance that a creature teleports near you\n 0.5%% chance that a new creature spawns near you if you hit another creature\n- received damage increased by 15%% \n - 10%% chance that a creature will fully heal itself instead of dying\n- loss of 10%% of your hit points and your mana every 10 seconds'), path = '/images/game/states/cursev', id = 'condition_cursev' }
Icons[PlayerStates.NewMagicShield] = { tooltip = tr('You are protected by a magic shield'), path = '/images/game/states/magic_shield', id = 'condition_new_magic_shield' }
Icons[PlayerStates.Agony] = { tooltip = tr('You are in agony'), path = '/images/game/states/agony', id = 'condition_agony' }
Icons[PlayerStates.Powerless] = { tooltip = tr('You are Powerless'), path = '/images/game/states/sufferringpowerless', id = 'condition_powerless' }
Icons[PlayerStates.Mentored] = { tooltip = tr('You are empowered by Mentor Other'), path = '/images/game/states/mentored', id = 'condition_mentored' }

SkullIcons = {}
SkullIcons[SkullGreen] = { tooltip = tr('You are a member of a party'), path = '/images/game/states/skullgreen', id = 'skullIcon' }
SkullIcons[SkullWhite] = { tooltip = tr('You have attacked an unmarked player'), path = '/images/game/states/skullwhite', id = 'skullIcon' }
SkullIcons[SkullRed] = { tooltip = tr('You have killed too many unmarked players'), path = '/images/game/states/skullred', id = 'skullIcon' }
SkullIcons[SkullOrange] = { tooltip = tr('You may suffer revenge from your former victim'), path = '/images/game/states/skullorange', id = 'skullIcon' }

InventorySlotOther = 0
InventorySlotHead = 1
InventorySlotNeck = 2
InventorySlotBack = 3
InventorySlotBody = 4
InventorySlotRight = 5
InventorySlotLeft = 6
InventorySlotLeg = 7
InventorySlotFeet = 8
InventorySlotFinger = 9
InventorySlotAmmo = 10
InventorySlotPurse = 11
InventorySlotBattlePass = 12

InventorySlotFirst = 1
InventorySlotLast = 10

function Player:isPartyLeader()
  local shield = self:getShield()
  return (shield == ShieldYellow or
          shield == ShieldYellowSharedExp or
          shield == ShieldYellowNoSharedExpBlink or
          shield == ShieldYellowNoSharedExp)
end

function Player:isPartyMember()
  local shield = self:getShield()
  return (shield == ShieldYellow or
          shield == ShieldYellowSharedExp or
          shield == ShieldYellowNoSharedExpBlink or
          shield == ShieldYellowNoSharedExp or
          shield == ShieldBlueSharedExp or
          shield == ShieldBlueNoSharedExpBlink or
          shield == ShieldBlueNoSharedExp or
          shield == ShieldBlue)
end

-- g_minimap.getPartyMembersData() is a koliseu C++ binding not present in this
-- build (only clean/loadImage/saveImage/loadOtmm/saveOtmm are bound), so calling
-- it broke the VIP-list context menu for party leaders. Use it when available;
-- otherwise fall back to scanning on-screen creatures for a party-shielded
-- player with the given name (off-screen members simply aren't found).
local function findPartyMemberIdByName(localPlayer, name)
  if g_minimap.getPartyMembersData then
    for _, data in pairs(g_minimap.getPartyMembersData() or {}) do
      if data.name == name then
        return data.id
      end
    end
    return nil
  end
  local pos = localPlayer and localPlayer:getPosition()
  if not pos then
    return nil
  end
  for _, creature in ipairs(g_map.getSpectators(pos, true)) do
    if creature:isPlayer() and creature:getName() == name
        and creature.isPartyMember and creature:isPartyMember() then
      return creature:getId()
    end
  end
  return nil
end

function Player:isInSameParty(name)
  return findPartyMemberIdByName(self, name) ~= nil
end

function Player:getPartyCreatureId(name)
  return findPartyMemberIdByName(self, name) or 0
end

function Player:isPartySharedExperienceActive()
  local shield = self:getShield()
  return (shield == ShieldYellowSharedExp or
          shield == ShieldYellowNoSharedExpBlink or
          shield == ShieldYellowNoSharedExp or
          shield == ShieldBlueSharedExp or
          shield == ShieldBlueNoSharedExpBlink or
          shield == ShieldBlueNoSharedExp)
end

function Player:hasVip(creatureName)
  for id, vip in pairs(g_game.getVips()) do
    if (vip[1] == creatureName) then return true end
  end
  return false
end

-- isInMarket has no C++ binding; the market is purely a client window here, so
-- derive the state from the market module's window visibility. Used by the item
-- right-click menu (gameinterface "Show in Market") and textmessages.lua.
function Player:isInMarket()
  local market = modules.game_tibia_market
  return market ~= nil and market.marketWindow ~= nil and market.marketWindow:isVisible()
end

-- isInStash mirrors isInMarket: the C++ Thing::isInStash() is a hardcoded-false stub, so
-- define it on Player to win method resolution (Player sits above Thing in the class
-- chain). The depot-proximity flag is pushed by the server via the SpecialContainer
-- opcode (0x2A) and stored on the LocalPlayer as `inStash` by the game_stash module. This
-- gates the item right-click 'Stow' / 'Stow all items of this type' / 'Stow container'
-- options (gameinterface) so they only show when next to a depot.
function Player:isInStash()
  return self.inStash == true
end

-- canBuyExpBoost has no C++ binding (the daily store XP-boost availability is not
-- pushed to this client); default to false so the cyclopedia/stats store button
-- stays hidden instead of erroring. Wire to a real packet if/when one exists.
function Player:canBuyExpBoost()
  return false
end

function Player:isMounted()
  local outfit = self:getOutfit()
  return outfit.mount ~= nil and outfit.mount > 0
end

function Player:toggleMount()
  if g_game.getFeature(GamePlayerMounts) then
    g_game.mount(not self:isMounted())
  end
end

function Player:mount()
  if g_game.getFeature(GamePlayerMounts) then
    g_game.mount(true)
  end
end

function Player:dismount()
  if g_game.getFeature(GamePlayerMounts) then
    g_game.mount(false)
  end
end

function Player:getItem(itemId, subType)
  return g_game.findPlayerItem(itemId, subType or -1)
end

function Player:getItems(itemId, subType)
  local items = {}
  local result, _ = tryCatch(g_game.findItems, itemId, subType or -1)
  if result then
      items = result
  end
  return items
end

function Player:getItemsCount(itemId)
  local items, count = self:getItems(itemId), 0
  for i=1,#items do
    count = count + items[i]:getCount()
  end
  return count
end

function Player:hasState(state, states)
  if not states then
    states = self:getStates()
  end

  for i = 1, 32 do
    local pow = math.pow(2, i-1)
    if pow > states then break end

    local states = bit32.band(states, pow)
    if states == state then
      return true
    end
  end
  return false
end

function Player:isParalyzed()
  return self:hasState(PlayerStates.Paralyze)
end

function Player:isRooted()
  return self:hasState(PlayerStates.Rooted)
end

function Player:getPreWalkLockedDelay()
  return self.preWalkLockedDelay or 0
end

function Player:getTeleportWalkDelay()
  return self.teleportWalkDelay or 0
end

function Player:setTeleportWalkDelay(delay)
  self.teleportWalkDelay = delay or 0
end

function Player:getMonkPassive()
  return self.monkPassive or 0
end

function Player:setMonkPassive(monkPassive)
  self.monkPassive = monkPassive or 0
end

function Player:getMagicBoosts()
  return self.magicBoosts or {}
end

function Player:setMagicBoost(combatType, value)
  self.magicBoosts = self.magicBoosts or {}
  self.magicBoosts[combatType] = value or 0
end

-- Magic shield (mana shield) active state. The C++ LocalPlayer in this build does
-- not expose useMagicShield(), so several UI modules (topbar mana bar) crashed with
-- "attempt to call method 'useMagicShield' (a nil value)". Provide a Lua-side getter
-- (defaults to false) so those modules work; setUseMagicShield can flip it later.
-- The C++ LocalPlayer exposes getManaShield()/getMaxManaShield() (utamo vita
-- capacity from AddPlayerStats); remaining > 0 means the shield is active. Prefer
-- that real data so the topbar mana-shield bar shows live. Remote Players (no C++
-- getters) fall back to the Lua-backed field.
function Player:useMagicShield()
  if self.getManaShield then
    return self:getManaShield() > 0
  end
  return self.m_useMagicShield == true
end

function Player:setUseMagicShield(value)
  self.m_useMagicShield = value and true or false
end

-- ---------------------------------------------------------------------------
-- koliseu-client Player getters/setters not bound by this C++ build.
-- The UI modules (topbar, inventory, cyclopedia) call these directly and would
-- otherwise crash with "attempt to call method 'X' (a nil value)". Back them with
-- plain Lua fields and safe defaults; the protocol/UI layer can set them later.
-- ---------------------------------------------------------------------------

-- Mana shield / magic shield points (topbar mana-shield bar).
-- Prefer the real C++ LocalPlayer getters when present (getManaShield), so the
-- bar reflects the actual utamo vita capacity received from the server.
function Player:getMagicShield()
  if self.getManaShield then
    return self:getManaShield()
  end
  return self.m_magicShield or 0
end

function Player:setMagicShield(value)
  self.m_magicShield = value or 0
end

function Player:getMaxMagicShield()
  if self.getMaxManaShield then
    return self:getMaxManaShield()
  end
  return self.m_maxMagicShield or 0
end

function Player:setMaxMagicShield(value)
  self.m_maxMagicShield = value or 0
end

-- Harmony / Serenity (vocation resource bars).
function Player:getHarmony()
  return self.m_harmony or 0
end

function Player:setHarmony(value)
  self.m_harmony = value or 0
end

function Player:isSerenity()
  return self.m_serenity == true
end

function Player:setSerenity(value)
  self.m_serenity = value and true or false
end

-- Blessing window status (inventory blessed button): 0/nil = none, 1 = grey, 2 = gold.
function Player:getBlessingStatus()
  return self.m_blessingStatus or 0
end

function Player:setBlessingStatus(value)
  self.m_blessingStatus = value or 0
end

-- Cyclopedia market-price preferences (game_cyclopedia items.lua).
function Player:setCyclopediaMarketList(value)
  self.m_cyclopediaMarketList = value
end

function Player:getCyclopediaMarketList()
  return self.m_cyclopediaMarketList
end

function Player:setCyclopediaCustomPrice(value)
  self.m_cyclopediaCustomPrice = value
end

function Player:getCyclopediaCustomPrice()
  return self.m_cyclopediaCustomPrice
end

-- Market list holds itemIds as strings (loadJson fills it from JSON object
-- keys), while call sites pass numeric item:getId() — hence tostring below.
function Player:updateCyclopediaMarketList(itemId, remove)
  local list = self.m_cyclopediaMarketList or {}
  self.m_cyclopediaMarketList = list
  local key = tostring(itemId)
  for i = #list, 1, -1 do
    if tostring(list[i]) == key then
      table.remove(list, i)
    end
  end
  if not remove then
    table.insert(list, key)
  end
end

-- Custom price map is keyed by numeric itemId (mirrors loadJson's
-- customPrice[tonumber(k) or k] = v).
function Player:updateCyclopediaCustomPrice(itemId, price)
  local prices = self.m_cyclopediaCustomPrice or {}
  self.m_cyclopediaCustomPrice = prices
  prices[tonumber(itemId) or itemId] = price
end

if not Analyzer then
    Analyzer = {}
end

if not Analyzer.analyzers then
  Analyzer.analyzers = {
    trackedLoot = {},
    customPrices = {},
    lootChannel = true,
    rarityFrames = true
  }
end
