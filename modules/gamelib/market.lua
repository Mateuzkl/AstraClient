MarketCategory = {
	All = 0,
	Armors = 1,
	Amulets = 2,
	Boots = 3,
	Containers = 4,
	Decoration = 5,
	Food = 6,
	HelmetsHats = 7,
	Legs = 8,
	Others = 9,
	Potions = 10,
	Rings = 11,
	Runes = 12,
	Shields = 13,
	Tools = 14,
	Valuables = 15,
	Ammunition = 16,
	Axes = 17,
	Clubs = 18,
	DistanceWeapons = 19,
	Swords = 20,
	WandsRods = 21,
	PremiumScrolls = 22,
	TibiaCoins = 23,
	CreatureProducs = 24,
	Quivers = 25,
	SoulCore = 26,
	FistWeapons = 27,
	Unknown3 = 28,
	Unknown4 = 29,
	Gold = 30,
	Unassigned = 31,
	WeaponsAll = 32,
	MetaWeapons = 255
}

MarketCategory.First = MarketCategory.Armors
MarketCategory.Last = MarketCategory.Unassigned

MarketDetailNames = {
	[1] = "Armor: ",
	[2] = "Attack: ",
	[3] = "Container: ",
	[4] = "Defense: ",
	[5] = "Description: ",
	[6] = "Use Time: ",
	[7] = "Combat: ",
	[8] = "Min Level: ",
	[9] = "Min Magic Level: ",
	[10] = "Vocation: ",
	[11] = "Rune: ",
	[12] = "Ability: ",
	[13] = "Charges: ",
	[14] = "Weapon Type: ",
	[15] = "Weight: ",
	[16] = "Imbuement Slots: ",
	[17] = "Classification: ",
	[18] = "Tier: ",
	[19] = "Skill Bonus: ",
	[20] = "Protection: ",
	[21] = "Augments: ",
}

MarketSellStatus = {
	"cancelled",
	"expired",
	"sold"
}

MarketBuyStatus = {
	"cancelled",
	"expired",
	"bought"
}

function getCoinStepValue(itemId)
	if itemId == 22118 then
		return 25 -- need packet
	end
	return 1
end

function getCoinMultiply(value)
    if value % 25 == 0 then
        return value
	end

	local nextBigger = math.ceil(value / 25) * 25
	local nextLower = math.floor(value / 25) * 25

	if math.abs(nextBigger - value) < math.abs(nextLower - value) then
		return nextBigger
	else
		return nextLower
	end
end
