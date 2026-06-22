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

-- Display names per category id. g_things.getMarketCategories() returns a set of
-- category ids (numbers); the market UI needs a readable label for each.
MarketCategoryNames = {
	[MarketCategory.Armors] = "Armors",
	[MarketCategory.Amulets] = "Amulets and Necklaces",
	[MarketCategory.Boots] = "Boots",
	[MarketCategory.Containers] = "Containers",
	[MarketCategory.Decoration] = "Decoration",
	[MarketCategory.Food] = "Food",
	[MarketCategory.HelmetsHats] = "Helmets and Hats",
	[MarketCategory.Legs] = "Legs",
	[MarketCategory.Others] = "Others",
	[MarketCategory.Potions] = "Potions",
	[MarketCategory.Rings] = "Rings",
	[MarketCategory.Runes] = "Runes",
	[MarketCategory.Shields] = "Shields",
	[MarketCategory.Tools] = "Tools",
	[MarketCategory.Valuables] = "Valuables",
	[MarketCategory.Ammunition] = "Ammunition",
	[MarketCategory.Axes] = "Axes",
	[MarketCategory.Clubs] = "Clubs",
	[MarketCategory.DistanceWeapons] = "Distance Weapons",
	[MarketCategory.Swords] = "Swords",
	[MarketCategory.WandsRods] = "Wands and Rods",
	[MarketCategory.PremiumScrolls] = "Premium Scrolls",
	[MarketCategory.TibiaCoins] = "Tibia Coins",
	[MarketCategory.CreatureProducs] = "Creature Products",
	[MarketCategory.Quivers] = "Quivers",
	[MarketCategory.SoulCore] = "Soul Cores",
	[MarketCategory.FistWeapons] = "Fist Weapons",
	[MarketCategory.Gold] = "Gold",
	[MarketCategory.Unassigned] = "Unassigned",
}

MarketDetailNames = {
	"Armor: ",
	"Attack: ",
	"Capacity: ",
	"Defence: ",
	"Description: ",
	"Expires after: ",
	"Protection: ",
	"Minimum Required Level: ",
	"Minimum Required Magic Level: ",
	"Vocations: ",
	"Spell: ",
	"Skill Boost: ",
	"Charges: ",
	"Weapon Type: ",
	"Weight: ",
	"Augments: ",
	"Imbuement Slots: ",
	"Magic Shield Capacity: ",
	"Cleave: ",
	"Damage Reflection: ",
	"Perfect Shot: ",
	"Classification: ",
	"Elemental Bond: ",
	"Mantra: ",
	"Tier: ",
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

-- Market gold formatting for Total / Total Price fields:
--   below 1 million  -> full comma-separated value (e.g. 999,999)
--   1 million and up -> value expressed in millions with a "kk" suffix, up to
--                       2 decimals (trailing zeros trimmed). So 1,000,000 -> "1 kk",
--                       1,500,000 -> "1.5 kk" and 1,000,000,000 -> "1,000 kk".
function formatMarketGold(value)
	value = tonumber(value) or 0
	if value < 1000000 then
		return comma_value(value)
	end

	local millions = string.format("%.2f", value / 1000000)
	local intPart, decPart = millions:match("^(%d+)%.(%d+)$")
	decPart = decPart:gsub("0+$", "")

	local text = comma_value(tonumber(intPart))
	if #decPart > 0 then
		text = text .. "." .. decPart
	end
	return text .. " kk"
end
