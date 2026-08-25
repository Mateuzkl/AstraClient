-- chunkname: @/mods/game_proficiency/const.lua

PERK_ATTACK_DAMAGE = 0
PERK_DEFENSE = 1
PERK_DEFENSE_MODIFIER = 2
PERK_SKILL_BONUS = 3
PERK_SPECIAL_MAGIC_BOOST = 4
PERK_SPELL_AUGMENT = 5
PERK_BESTIARY_DAMAGE = 6
PERK_POWERFUL_FOE_DAMAGE = 7
PERK_CRITICAL_HIT_CHANCE = 8
PERK_ELEMENTAL_CRITICAL_HIT_CHANCE = 9
PERK_RUNE_CRITICAL_HIT_CHANCE = 10
PERK_AUTO_ATTACK_CRITICAL_HIT_CHANCE = 11
PERK_CRITICAL_EXTRA_DAMAGE = 12
PERK_ELEMENTAL_CRITICAL_EXTRA_DAMAGE = 13
PERK_RUNE_CRITICAL_EXTRA_DAMAGE = 14
PERK_AUTO_ATTACK_CRITICAL_EXTRA_DAMAGE = 15
PERK_MANA_LEECH = 16
PERK_LIFE_LEECH = 17
PERK_MANA_GAIN_ON_HIT = 18
PERK_LIFE_GAIN_ON_HIT = 19
PERK_MANA_GAIN_ON_KILL = 20
PERK_LIFE_GAIN_ON_KILL = 21
PERK_PERFECT_SHOT = 22
PERK_RANGED_HIT_CHANCE = 23
PERK_ATTACK_RANGE = 24
PERK_SKILL_PERCENTAGE_AUTO_ATTACK = 25
PERK_SKILL_PERCENTAGE_SPELL_DAMAGE = 26
PERK_SKILL_PERCENTAGE_SPELL_HEALING = 27
PERK_ALPHA_STRIKE_EXTRA_DAMAGE = 28
PERK_OMEGA_STRIKE_EXTRA_DAMAGE = 29
PERK_ARMOR_PENETRATION = 30
PERK_ELEMENTAL_PIERCING = 31
PERK_HOMING_MISSILE = 32
PERK_HIGHEST_COMBAT_SKILL_EXTRA_DAMAGE_AUTO_ATTACK = 33
PERK_HIGHEST_COMBAT_SKILL_EXTRA_DAMAGE_SPELLS = 34
PERK_HIGHEST_COMBAT_SKILL_HEALING_SPELLS = 35
PERK_AUGMENT_BASE_DAMAGE = 2
PERK_AUGMENT_HEALING = 3
PERK_AUGMENT_CHAIN_LENGTH = 5
PERK_AUGMENT_COOLDOWN_REDUCTION = 6
PERK_AUGMENT_LIFE_LEECH = 14
PERK_AUGMENT_MANA_LEECH = 15
PERK_AUGMENT_CRITICAL_EXTRA_DAMAGE = 16
PERK_AUGMENT_CRITICAL_HIT_CHANCE = 17
PROFICIENCY_IMAGE_PATH = "/images/game/proficiency/"
SKILLWHEEL_SMALLPERKS_PATH = "/images/game/wheel/icons-skillwheel-smallperks"

function getIconOffset(index, iconSize)
	return string.format("%d 0", index * (iconSize or 32))
end

PerkMasterySheetOrder = {
	["icons-weaponmastery"] = {
		PERK_ATTACK_DAMAGE,
		PERK_DEFENSE,
		PERK_DEFENSE_MODIFIER,
		PERK_POWERFUL_FOE_DAMAGE,
		PERK_CRITICAL_HIT_CHANCE,
		PERK_RUNE_CRITICAL_HIT_CHANCE,
		PERK_AUTO_ATTACK_CRITICAL_HIT_CHANCE,
		PERK_CRITICAL_EXTRA_DAMAGE,
		PERK_RUNE_CRITICAL_EXTRA_DAMAGE,
		PERK_AUTO_ATTACK_CRITICAL_EXTRA_DAMAGE,
		PERK_LIFE_LEECH,
		PERK_MANA_LEECH,
		PERK_LIFE_GAIN_ON_HIT,
		PERK_MANA_GAIN_ON_HIT,
		PERK_LIFE_GAIN_ON_KILL,
		PERK_MANA_GAIN_ON_KILL,
		PERK_PERFECT_SHOT,
		PERK_RANGED_HIT_CHANCE,
		PERK_ATTACK_RANGE,
		PERK_ALPHA_STRIKE_EXTRA_DAMAGE,
		PERK_OMEGA_STRIKE_EXTRA_DAMAGE,
		PERK_ARMOR_PENETRATION
	},
	["icons-weaponmastery-criticalExtraDamageElement"] = {
		PERK_ELEMENTAL_CRITICAL_EXTRA_DAMAGE
	},
	["icons-weaponmastery-criticalHitChanceElement"] = {
		PERK_ELEMENTAL_CRITICAL_HIT_CHANCE
	},
	["icons-weaponmastery-damagaAgainstBestiary"] = {
		PERK_BESTIARY_DAMAGE
	},
	["icons-weaponmastery-elementalPiercing"] = {
		PERK_ELEMENTAL_PIERCING
	},
	["icons-weaponmastery-gainExtraDamageAutoAttack"] = {
		PERK_SKILL_PERCENTAGE_AUTO_ATTACK
	},
	["icons-weaponmastery-gainExtraDamageSpells"] = {
		PERK_SKILL_PERCENTAGE_SPELL_DAMAGE
	},
	["icons-weaponmastery-gainExtraHealingSpells"] = {
		PERK_SKILL_PERCENTAGE_SPELL_HEALING
	},
	["icons-weaponmastery-homingMissile"] = {
		PERK_HOMING_MISSILE
	},
	["icons-weaponmastery-offensiveBonusSkill"] = {
		PERK_SKILL_BONUS
	},
	["icons-weaponmastery-specializedMagicLevel"] = {
		PERK_SPECIAL_MAGIC_BOOST
	}
}
PerkMasteryIcons = {}

for sheet, perks in pairs(PerkMasterySheetOrder) do
	for i, perkType in ipairs(perks) do
		PerkMasteryIcons[perkType] = {
			sheet = sheet,
			index = i - 1
		}
	end
end

PerkMasteryIcons[PERK_HIGHEST_COMBAT_SKILL_EXTRA_DAMAGE_AUTO_ATTACK] = {
	sheet = "icons-weaponmastery-gainExtraDamageAutoAttack",
	index = 8
}
PerkMasteryIcons[PERK_HIGHEST_COMBAT_SKILL_EXTRA_DAMAGE_SPELLS] = {
	sheet = "icons-weaponmastery-gainExtraDamageSpells",
	index = 8
}
PerkMasteryIcons[PERK_HIGHEST_COMBAT_SKILL_HEALING_SPELLS] = {
	sheet = "icons-weaponmastery-gainExtraHealingSpells",
	index = 8
}
AugmentPerkIcons = {
	[PERK_AUGMENT_COOLDOWN_REDUCTION] = {
		index = 5,
		desc = "%ds cooldown for %s"
	},
	[PERK_AUGMENT_BASE_DAMAGE] = {
		index = 6,
		desc = "+%s%% base damage for %s"
	},
	[PERK_AUGMENT_HEALING] = {
		index = 6,
		desc = "+%s%% healing for %s"
	},
	[PERK_AUGMENT_CRITICAL_EXTRA_DAMAGE] = {
		index = 7,
		desc = "+%s%% critical extra damage for %s"
	},
	[PERK_AUGMENT_CRITICAL_HIT_CHANCE] = {
		index = 7,
		desc = "+%s%% critical hit chance for %s"
	},
	[PERK_AUGMENT_CHAIN_LENGTH] = {
		index = 10,
		desc = "+%s%% chain length for %s"
	},
	[PERK_AUGMENT_LIFE_LEECH] = {
		index = 11,
		desc = "+%s%% life leech for %s"
	},
	[PERK_AUGMENT_MANA_LEECH] = {
		index = 12,
		desc = "+%s%% mana leech for %s"
	}
}
ElementalMask = {
	[1] = {
		index = 0,
		name = "Physical"
	},
	[4] = {
		index = 0,
		name = "Physical"
	},
	[8] = {
		index = 1,
		name = "Fire"
	},
	[32] = {
		index = 2,
		name = "Energy"
	},
	[16] = {
		index = 3,
		name = "Earth"
	},
	[64] = {
		index = 4,
		name = "Ice"
	},
	[256] = {
		index = 5,
		name = "Death"
	},
	[128] = {
		index = 6,
		name = "Holy"
	}
}
MagicBoostMask = {
	[8] = {
		index = 0,
		name = "Fire"
	},
	[64] = {
		index = 1,
		name = "Ice"
	},
	[16] = {
		index = 2,
		name = "Earth"
	},
	[32] = {
		index = 3,
		name = "Energy"
	},
	[256] = {
		index = 4,
		name = "Death"
	},
	[128] = {
		index = 5,
		name = "Holy"
	},
	[1048576] = {
		index = 6,
		name = "Healing"
	}
}
SkillTypes = {
	[8] = {
		index = 0,
		name = "Sword Fighting"
	},
	[10] = {
		index = 1,
		name = "Axe Fighting"
	},
	[9] = {
		index = 2,
		name = "Club Fighting"
	},
	[11] = {
		index = 3,
		name = "Fist Fighting"
	},
	[1] = {
		index = 4,
		name = "Magic Level"
	},
	[6] = {
		index = 5,
		name = "Shielding"
	},
	[7] = {
		index = 6,
		name = "Distance Fighting"
	},
	[13] = {
		index = 7,
		name = "Fishing"
	}
}
BestiaryCategories = {
	Amphibic = {
		index = 0
	},
	Aquatic = {
		index = 1
	},
	Bird = {
		index = 2
	},
	Construct = {
		index = 3
	},
	Demon = {
		index = 4
	},
	Dragon = {
		index = 5
	},
	Elemental = {
		index = 6
	},
	Fey = {
		index = 7
	},
	Giant = {
		index = 8
	},
	Human = {
		index = 9
	},
	Humanoid = {
		index = 10
	},
	Lycanthrope = {
		index = 11
	},
	Magical = {
		index = 12
	},
	Mammal = {
		index = 13
	},
	Plant = {
		index = 14
	},
	Reptile = {
		index = 15
	},
	Slime = {
		index = 16
	},
	Undead = {
		index = 17
	},
	Vermin = {
		index = 18
	},
	["Extra Dimensional"] = {
		index = 19
	},
	Inkborn = {
		index = 20
	}
}
ExperienceTable = {
	{
		crossbow = 600,
		knight = 1250,
		regular = 1750
	},
	{
		crossbow = 8000,
		knight = 20000,
		regular = 25000
	},
	{
		crossbow = 30000,
		knight = 80000,
		regular = 100000
	},
	{
		crossbow = 150000,
		knight = 300000,
		regular = 400000
	},
	{
		crossbow = 650000,
		knight = 1500000,
		regular = 2000000
	},
	{
		crossbow = 2500000,
		knight = 6000000,
		regular = 8000000
	},
	{
		crossbow = 10000000,
		knight = 20000000,
		regular = 30000000
	},
	{
		crossbow = 30000000,
		knight = 60000000,
		regular = 90000000
	},
	{
		crossbow = 30000000,
		knight = 60000000,
		regular = 90000000
	}
}
PerkTextData = {
	[PERK_ATTACK_DAMAGE] = {
		desc = "+%d attack",
		name = "Attack Damage"
	},
	[PERK_DEFENSE] = {
		desc = "+%d defence",
		name = "Defence"
	},
	[PERK_DEFENSE_MODIFIER] = {
		desc = "+%d defence modifier",
		name = "Weapon Shield Mod"
	},
	[PERK_SKILL_BONUS] = {
		desc = "+%d %s",
		name = "Skill Bonus"
	},
	[PERK_SPECIAL_MAGIC_BOOST] = {
		desc = "+%d %s Magic Level",
		name = "Special Magic Boost"
	},
	[PERK_SPELL_AUGMENT] = {
		desc = "Variable...",
		name = "Spell Augment"
	},
	[PERK_BESTIARY_DAMAGE] = {
		desc = "+%s%% damage against %s",
		name = "Bestiary Damage"
	},
	[PERK_POWERFUL_FOE_DAMAGE] = {
		desc = "+%s%% damage against bosses and Sinister Embraced",
		name = "Powerful Foe Bonus"
	},
	[PERK_CRITICAL_HIT_CHANCE] = {
		desc = "+%s%% critical hit chance",
		name = "Critical Hit Chance"
	},
	[PERK_ELEMENTAL_CRITICAL_HIT_CHANCE] = {
		desc = "+%s%% critical hit chance for %s spells and runes",
		name = "Element Critical Hit Chance"
	},
	[PERK_RUNE_CRITICAL_HIT_CHANCE] = {
		desc = "+%s%% critical hit chance for offensive runes",
		name = "Rune Critical Hit Chance"
	},
	[PERK_AUTO_ATTACK_CRITICAL_HIT_CHANCE] = {
		desc = "+%s%% critical hit chance for auto-attacks",
		name = "Auto-Attack Critical Hit Chance"
	},
	[PERK_CRITICAL_EXTRA_DAMAGE] = {
		desc = "+%s%% critical extra damage",
		name = "Critical Extra Damage"
	},
	[PERK_ELEMENTAL_CRITICAL_EXTRA_DAMAGE] = {
		desc = "+%s%% critical extra damage for %s spells and runes",
		name = "Element Critical Extra Damage"
	},
	[PERK_RUNE_CRITICAL_EXTRA_DAMAGE] = {
		desc = "+%s%% critical extra damage for offensive runes",
		name = "Rune Critical Extra Damage"
	},
	[PERK_AUTO_ATTACK_CRITICAL_EXTRA_DAMAGE] = {
		desc = "+%s%% critical extra damage for auto-attacks",
		name = "Auto-Attack Critical Extra Damage"
	},
	[PERK_LIFE_LEECH] = {
		desc = "+%s%% life leech",
		name = "Life Leech"
	},
	[PERK_MANA_LEECH] = {
		desc = "+%s%% mana leech",
		name = "Mana Leech"
	},
	[PERK_LIFE_GAIN_ON_HIT] = {
		desc = "+%d hit points on hit",
		name = "Life Gain on Hit"
	},
	[PERK_MANA_GAIN_ON_HIT] = {
		desc = "+%d mana on hit",
		name = "Mana Gain on Hit"
	},
	[PERK_LIFE_GAIN_ON_KILL] = {
		desc = "+%d hit points on kill",
		name = "Life Gain on Kill"
	},
	[PERK_MANA_GAIN_ON_KILL] = {
		desc = "+%d mana on kill",
		name = "Mana Gain on Kill"
	},
	[PERK_PERFECT_SHOT] = {
		desc = "+%d damage at range %d",
		name = "Perfect Shot Damage"
	},
	[PERK_RANGED_HIT_CHANCE] = {
		desc = "+%s%% hit chance",
		name = "Ranged Hit Chance"
	},
	[PERK_ATTACK_RANGE] = {
		desc = "+%d range",
		name = "Attack Range"
	},
	[PERK_SKILL_PERCENTAGE_AUTO_ATTACK] = {
		desc = "+%s%% of your %s as extra damage for auto-attacks",
		name = "Skill Percentage Auto-Attack Damage"
	},
	[PERK_SKILL_PERCENTAGE_SPELL_DAMAGE] = {
		desc = "+%s%% of your %s as extra damage for your spells",
		name = "Skill Percentage Spell Damage"
	},
	[PERK_SKILL_PERCENTAGE_SPELL_HEALING] = {
		desc = "+%s%% of your %s as extra healing for your spells",
		name = "Skill Percentage Spell Healing"
	},
	[PERK_ALPHA_STRIKE_EXTRA_DAMAGE] = {
		desc = "+%s%% damage against targets above 95%% hit points",
		name = "Alpha Strike Extra Damage"
	},
	[PERK_OMEGA_STRIKE_EXTRA_DAMAGE] = {
		desc = "+%s%% damage against targets below 30%% hit points",
		name = "Omega Strike Extra Damage"
	},
	[PERK_ARMOR_PENETRATION] = {
		desc = "+%s%% armor penetration",
		name = "Armor Penetration"
	},
	[PERK_ELEMENTAL_PIERCING] = {
		desc = "+%s%% %s pierce",
		name = "Elemental Pierce"
	},
	[PERK_HOMING_MISSILE] = {
		desc = "Offensive spells have a %s%% chance to fire a homing missile that deals %s damage equal to %s%% of your level",
		name = "Homing Missile"
	},
	[PERK_HIGHEST_COMBAT_SKILL_EXTRA_DAMAGE_AUTO_ATTACK] = {
		desc = "+%s%% of your highest combat skill as extra damage for auto-attacks",
		name = "Highest Combat Skill Percentage Auto-Attack Damage"
	},
	[PERK_HIGHEST_COMBAT_SKILL_EXTRA_DAMAGE_SPELLS] = {
		desc = "+%s%% of your highest combat skill as extra damage for your spells",
		name = "Highest Combat Skill Percentage Spell Damage"
	},
	[PERK_HIGHEST_COMBAT_SKILL_HEALING_SPELLS] = {
		desc = "+%s%% of your highest combat skill as extra healing for your spells, except heal-over-time spells",
		name = "Highest Combat Skill Percentage Spell Healing"
	}
}
ElementalCritical_t = {
	[PERK_ELEMENTAL_CRITICAL_HIT_CHANCE] = true,
	[PERK_ELEMENTAL_CRITICAL_EXTRA_DAMAGE] = true
}
ElementalMaskPerk_t = {
	[PERK_ELEMENTAL_CRITICAL_HIT_CHANCE] = true,
	[PERK_ELEMENTAL_CRITICAL_EXTRA_DAMAGE] = true,
	[PERK_ELEMENTAL_PIERCING] = true,
	[PERK_HOMING_MISSILE] = true
}
FlatDamageBonus_t = {
	[PERK_SKILL_PERCENTAGE_AUTO_ATTACK] = true,
	[PERK_SKILL_PERCENTAGE_SPELL_DAMAGE] = true,
	[PERK_SKILL_PERCENTAGE_SPELL_HEALING] = true,
	[PERK_SKILL_BONUS] = true
}
PercentageTypes = {
	PERK_RANGED_HIT_CHANCE,
	PERK_SPELL_AUGMENT,
	PERK_HOMING_MISSILE,
	PERK_AUTO_ATTACK_CRITICAL_EXTRA_DAMAGE,
	PERK_SKILL_PERCENTAGE_SPELL_DAMAGE,
	PERK_SKILL_PERCENTAGE_AUTO_ATTACK,
	PERK_SKILL_PERCENTAGE_SPELL_HEALING,
	PERK_HIGHEST_COMBAT_SKILL_EXTRA_DAMAGE_AUTO_ATTACK,
	PERK_HIGHEST_COMBAT_SKILL_EXTRA_DAMAGE_SPELLS,
	PERK_HIGHEST_COMBAT_SKILL_HEALING_SPELLS
}
PercentageTypesSet = {}

for _, v in ipairs(PercentageTypes) do
	PercentageTypesSet[v] = true
end

WeaponCategoryMap = {
	["Weapons: All"] = 32,
	["Weapons: Wands"] = 21,
	["Weapons: Swords"] = 20,
	["Weapons: Fist"] = 27,
	["Weapons: Distance"] = 19,
	["Weapons: Clubs"] = 18,
	["Weapons: Axes"] = 17
}
WeaponStringToCategory = {}
WeaponCategoryToString = {}

for name, id in pairs(WeaponCategoryMap) do
	WeaponStringToCategory[name] = id
	WeaponCategoryToString[id] = name
end
