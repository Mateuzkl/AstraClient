--[[============================================================================
  test_enums.lua  --  value + translation checks for the `Enums` namespace.
  ============================================================================
  WHAT IT TESTS
    PART 1: that key enum GROUPS carry the exact Zerobot values
    (Directions/Vocations/InventorySlot/States/Skulls/CreatureTypes/FightMode/
    ChaseMode/PartyIcons/GuildEmblem/MessageTypes/BlessingState/AlarmType...).
    PART 2: that the Enums.translate.* converters return the right NUMBERS
    (directionToEngine remaps diagonals; vocationFromEngine collapses
    promotions; stateToEngine = 2^index; talk/message/flag-modifier remaps).
    This is a PURE DATA test: it never touches the game, so it gives identical
    results online or offline.

  HOW TO READ THE OUTPUT
    "[PASS] <name> = <value>" / "[FAIL] <name>". Any FAIL means an enum value or
    a translator drifted from the Zerobot contract -- a real regression.
    Summary at the end: "--- enums: N passed, M failed ---".

  SAFE TO RUN ON THE LIVE CLIENT: pure data, no side effects.
============================================================================]]

local pass, fail = 0, 0
local function check(name, cond, extra)
  if cond then
    pass = pass + 1
    print('[PASS] ' .. name .. (extra ~= nil and (' = ' .. tostring(extra)) or ''))
  else
    fail = fail + 1
    print('[FAIL] ' .. name)
  end
end

-- equality helper that also prints the offending value on failure
local function eq(name, got, want)
  check(name .. ' (want ' .. tostring(want) .. ')', got == want, got)
end

--==========================================================================
-- PART 1 -- group values (verbatim Zerobot)
--==========================================================================
print('== PART 1: enum group values ==')

-- Directions: cardinals 0..3, diagonals via DIAGONAL_MASK (4..7), INVALID=8.
eq('Directions.NORTH', Enums.Directions.NORTH, 0)
eq('Directions.EAST', Enums.Directions.EAST, 1)
eq('Directions.SOUTH', Enums.Directions.SOUTH, 2)
eq('Directions.WEST', Enums.Directions.WEST, 3)
eq('Directions.SOUTHWEST', Enums.Directions.SOUTHWEST, 4)
eq('Directions.SOUTHEAST', Enums.Directions.SOUTHEAST, 5)
eq('Directions.NORTHWEST', Enums.Directions.NORTHWEST, 6)
eq('Directions.NORTHEAST', Enums.Directions.NORTHEAST, 7)
eq('Directions.INVALIDDIRECTION', Enums.Directions.INVALIDDIRECTION, 8)

-- Vocations
eq('Vocations.NONE', Enums.Vocations.NONE, 0)
eq('Vocations.KNIGHT', Enums.Vocations.KNIGHT, 1)
eq('Vocations.PALADIN', Enums.Vocations.PALADIN, 2)
eq('Vocations.SORCERER', Enums.Vocations.SORCERER, 3)
eq('Vocations.DRUID', Enums.Vocations.DRUID, 4)
eq('Vocations.MONK', Enums.Vocations.MONK, 5)

-- InventorySlot (+ plural alias points to the same table)
eq('InventorySlot.CONST_SLOT_HEAD', Enums.InventorySlot.CONST_SLOT_HEAD, 1)
eq('InventorySlot.CONST_SLOT_BACKPACK', Enums.InventorySlot.CONST_SLOT_BACKPACK, 3)
eq('InventorySlot.CONST_SLOT_LEFT', Enums.InventorySlot.CONST_SLOT_LEFT, 6)
eq('InventorySlot.CONST_SLOT_AMMO', Enums.InventorySlot.CONST_SLOT_AMMO, 10)
eq('InventorySlot.CONST_SLOT_STORE_INBOX', Enums.InventorySlot.CONST_SLOT_STORE_INBOX, 11)
check('InventorySlots (plural) aliases InventorySlot',
      Enums.InventorySlots == Enums.InventorySlot)

-- States (bit INDICES, 0-based)
eq('States.STATE_POISON', Enums.States.STATE_POISON, 0)
eq('States.STATE_ENERGY', Enums.States.STATE_ENERGY, 2)
eq('States.STATE_MANASHIELD', Enums.States.STATE_MANASHIELD, 4)
eq('States.STATE_ROOTED', Enums.States.STATE_ROOTED, 19)
eq('States.STATE_FEARED', Enums.States.STATE_FEARED, 20)
eq('States.STATE_AGONY', Enums.States.STATE_AGONY, 27)

-- Skulls / CreatureTypes / GuildEmblem / PartyIcons
eq('Skulls.SKULL_RED', Enums.Skulls.SKULL_RED, 4)
eq('Skulls.SKULL_ORANGE', Enums.Skulls.SKULL_ORANGE, 6)
eq('CreatureTypes.CREATURETYPE_MONSTER', Enums.CreatureTypes.CREATURETYPE_MONSTER, 1)
eq('CreatureTypes.CREATURETYPE_NPC', Enums.CreatureTypes.CREATURETYPE_NPC, 2)
eq('GuildEmblem.GUILDEMBLEM_ENEMY', Enums.GuildEmblem.GUILDEMBLEM_ENEMY, 2)
eq('PartyIcons.SHIELD_GRAY', Enums.PartyIcons.SHIELD_GRAY, 11)

-- FightMode / ChaseMode (+ plural aliases)
eq('FightMode.FIGHTMODE_ATTACK', Enums.FightMode.FIGHTMODE_ATTACK, 1)
eq('FightMode.FIGHTMODE_DEFENSE', Enums.FightMode.FIGHTMODE_DEFENSE, 3)
check('FightModes (plural) aliases FightMode', Enums.FightModes == Enums.FightMode)
eq('ChaseMode.STAND', Enums.ChaseMode.STAND, 0)
eq('ChaseMode.CHASE', Enums.ChaseMode.CHASE, 1)
check('ChaseModes (plural) aliases ChaseMode', Enums.ChaseModes == Enums.ChaseMode)

-- Assorted singletons used by events / scripts
eq('BlessingState.UNDEFINED', Enums.BlessingState.UNDEFINED, -1)
eq('BlessingState.FULL', Enums.BlessingState.FULL, 2)
eq('AlarmType.LOW_HEALTH', Enums.AlarmType.LOW_HEALTH, 2)
eq('AlarmType.PLAYER_IDLE', Enums.AlarmType.PLAYER_IDLE, 16)
eq('MessageTypes.MESSAGE_LOOT', Enums.MessageTypes.MESSAGE_LOOT, 31)
eq('MessageTypes.MESSAGE_POTION', Enums.MessageTypes.MESSAGE_POTION, 52)
eq('TalkTypes.TALKTYPE_SAY', Enums.TalkTypes.TALKTYPE_SAY, 1)
eq('TalkTypes.TALKTYPE_PRIVATE_PN', Enums.TalkTypes.TALKTYPE_PRIVATE_PN, 12)

--==========================================================================
-- PART 2 -- translate.* converters (the result must be a NUMBER, and correct)
--==========================================================================
print('== PART 2: translate.* converters ==')
local T = Enums.translate
check('Enums.translate exists', type(T) == 'table')

-- Directions: cardinals identity, diagonals remap to engine order.
eq('directionToEngine(NORTH)', T.directionToEngine(Enums.Directions.NORTH), 0)
eq('directionToEngine(SOUTHWEST)->6', T.directionToEngine(Enums.Directions.SOUTHWEST), 6)
eq('directionToEngine(NORTHEAST)->4', T.directionToEngine(Enums.Directions.NORTHEAST), 4)
eq('directionToEngine(SOUTHEAST)->5', T.directionToEngine(Enums.Directions.SOUTHEAST), 5)
eq('directionToEngine(NORTHWEST)->7', T.directionToEngine(Enums.Directions.NORTHWEST), 7)
eq('directionToEngine(INVALID=8)->nil', T.directionToEngine(8), nil)
-- round-trips
eq('dir round-trip SOUTHWEST',
   T.directionFromEngine(T.directionToEngine(Enums.Directions.SOUTHWEST)), Enums.Directions.SOUTHWEST)
eq('dir round-trip NORTHEAST',
   T.directionFromEngine(T.directionToEngine(Enums.Directions.NORTHEAST)), Enums.Directions.NORTHEAST)
check('directionToEngine returns a number for a cardinal',
      type(T.directionToEngine(Enums.Directions.EAST)) == 'number')

-- Vocations: base identity; promotions (11..15) collapse to base.
eq('vocationFromEngine(1)->KNIGHT', T.vocationFromEngine(1), Enums.Vocations.KNIGHT)
eq('vocationFromEngine(11)->KNIGHT (Elite)', T.vocationFromEngine(11), Enums.Vocations.KNIGHT)
eq('vocationFromEngine(13)->SORCERER (Master)', T.vocationFromEngine(13), Enums.Vocations.SORCERER)
eq('vocationFromEngine(15)->MONK (Exalted)', T.vocationFromEngine(15), Enums.Vocations.MONK)
eq('vocationFromEngine(0)->0', T.vocationFromEngine(0), 0)
eq('vocationToEngine(DRUID)->base 4', T.vocationToEngine(Enums.Vocations.DRUID), 4)
check('vocationFromEngine returns a number', type(T.vocationFromEngine(2)) == 'number')
eq('isPromotedVocation(13)', T.isPromotedVocation(13), true)
eq('isPromotedVocation(3)', T.isPromotedVocation(3), false)

-- States: ZB index -> engine bitmask flag (2^index), and hasState helper.
eq('stateToEngine(STATE_POISON)->1', T.stateToEngine(Enums.States.STATE_POISON), 1)
eq('stateToEngine(STATE_ENERGY)->4', T.stateToEngine(Enums.States.STATE_ENERGY), 4)
check('stateToEngine(STATE_AGONY) == 2^27',
      T.stateToEngine(Enums.States.STATE_AGONY) == 2 ^ 27,
      T.stateToEngine(Enums.States.STATE_AGONY))
eq('stateFromEngine(1)->index 0', T.stateFromEngine(1), 0)
eq('stateFromEngine(2)->index 1', T.stateFromEngine(2), 1)
eq('stateFromEngine(4)->index 2', T.stateFromEngine(4), 2)
eq('stateFromEngine(0)->nil', T.stateFromEngine(0), nil)
eq('stateFromEngine(3 not power-of-2)->nil', T.stateFromEngine(3), nil)
-- hasState: build a mask containing ROOTED + FEARED
local rootFlag = T.stateToEngine(Enums.States.STATE_ROOTED)
local fearFlag = T.stateToEngine(Enums.States.STATE_FEARED)
local mask = rootFlag + fearFlag -- distinct single bits, sum == bitwise-or
eq('hasState(mask, ROOTED)', T.hasState(mask, Enums.States.STATE_ROOTED), true)
eq('hasState(mask, FEARED)', T.hasState(mask, Enums.States.STATE_FEARED), true)
eq('hasState(mask, POISON)', T.hasState(mask, Enums.States.STATE_POISON), false)

-- Talk: cardinals identity; PRIVATE_PN(12) -> engine NpcTo(11).
eq('talkTypeToEngine(SAY)->1', T.talkTypeToEngine(Enums.TalkTypes.TALKTYPE_SAY), 1)
eq('talkTypeToEngine(PRIVATE_PN)->11', T.talkTypeToEngine(Enums.TalkTypes.TALKTYPE_PRIVATE_PN), 11)
eq('talkTypeFromEngine(11)->PRIVATE_PN', T.talkTypeFromEngine(11), Enums.TalkTypes.TALKTYPE_PRIVATE_PN)

-- MessageTypes: engine MessageMode -> ZB protocol class id.
eq('messageTypeFromEngine(45=Red)->CONSOLE_RED',
   T.messageTypeFromEngine(45), Enums.MessageTypes.MESSAGE_STATUS_CONSOLE_RED)
eq('messageTypeFromEngine(29=Loot)->LOOT',
   T.messageTypeFromEngine(29), Enums.MessageTypes.MESSAGE_LOOT)
eq('messageTypeFromEngine(999 unknown)->nil', T.messageTypeFromEngine(999), nil)

-- Identity translators still return the same number.
eq('inventorySlotToEngine(AMMO) identity', T.inventorySlotToEngine(Enums.InventorySlot.CONST_SLOT_AMMO), 10)
eq('skullToEngine(RED) identity', T.skullToEngine(Enums.Skulls.SKULL_RED), 4)
eq('fightModeToEngine(DEFENSE) identity', T.fightModeToEngine(Enums.FightMode.FIGHTMODE_DEFENSE), 3)
eq('chaseModeToEngine(CHASE) identity', T.chaseModeToEngine(Enums.ChaseMode.CHASE), 1)

-- Flag modifiers: Ctrl/Alt/Shift pass through; NUMLOCK(0x8) is stripped.
eq('flagModifiersToEngine(CONTROL)->1', T.flagModifiersToEngine(Enums.FlagModifiers.CONTROL), 1)
eq('flagModifiersToEngine(SHIFT)->4', T.flagModifiersToEngine(Enums.FlagModifiers.SHIFT), 4)
eq('flagModifiersToEngine(0xF all)->7 (numlock stripped)', T.flagModifiersToEngine(0xF), 7)

print(('--- enums: %d passed, %d failed ---'):format(pass, fail))
