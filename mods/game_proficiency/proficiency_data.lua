-- chunkname: @/mods/game_proficiency/proficiency_data.lua

if not ProficiencyData then
	ProficiencyData = {}
	ProficiencyData.__index = ProficiencyData
	ProficiencyData.content = {}
	ProficiencyData.catalogProficiencyByItem = {}
	ProficiencyData.proficiencyByName = {}
	ProficiencyData.proficiencyByWeaponItem = {}
	ProficiencyData.proficiencyByUniqueItemName = {}
	ProficiencyData.duplicateProficiencyItemNames = {}
end

local modifierLookupCache

-- Astra's global SpellIcons table is keyed by icon name. Proficiency modifier
-- packets use numeric spell ids, so keep the small protocol-specific mapping
-- local instead of indexing the incompatible global table.
local PROFICIENCY_SPELL_ICON_BY_ID = {
	[13] = 43, [23] = 42, [24] = 49, [43] = 46, [57] = 59, [59] = 20,
	[80] = 21, [105] = 22, [106] = 25, [120] = 47, [122] = 39, [124] = 40,
	[240] = 103, [258] = 153, [260] = 155, [261] = 150, [262] = 151, [263] = 152,
	[287] = 173, [288] = 174, [289] = 175, [290] = 176, [294] = 180, [301] = 185,
	[302] = 186, [303] = 187, [310] = 193, [316] = 197, [317] = 198, [318] = 199
}

local PROFICIENCY_SPELL_NAME_BY_ID = {
	[301] = "Thousand Fist Blows",
	[302] = "Divine Barrage",
	[303] = "Ethereal Barrage",
	[310] = "Death Echo",
	[316] = "Shield Slam",
	[317] = "Forked Glacier",
	[318] = "Forked Thorns"
}

local function makeRange(min, max)
	return {
		min = min,
		max = max,
		step = (max - min) / 10
	}
end

local function getModifierLookupCache()
	if modifierLookupCache then
		return modifierLookupCache
	end

	modifierLookupCache = {
		vocationSpells = {
			{
				80,
				105,
				106,
				59,
				316,
				261
			},
			[51] = {
				124,
				302,
				303,
				258,
				57,
				122
			},
			[101] = {
				13,
				24,
				240,
				260,
				310,
				23
			},
			[151] = {
				43,
				120,
				262,
				263,
				317,
				318
			},
			[201] = {
				289,
				288,
				294,
				287,
				301,
				290
			}
		},
		spellGroups = {
			[0] = {
				augmentType = PERK_AUGMENT_CRITICAL_HIT_CHANCE,
				range = makeRange(100, 300)
			},
			{
				augmentType = PERK_AUGMENT_CRITICAL_EXTRA_DAMAGE,
				range = makeRange(500, 2000)
			},
			{
				augmentType = PERK_AUGMENT_BASE_DAMAGE,
				range = makeRange(100, 300)
			},
			{
				augmentType = PERK_AUGMENT_MANA_LEECH,
				range = makeRange(100, 600)
			},
			{
				augmentType = PERK_AUGMENT_LIFE_LEECH,
				range = makeRange(100, 1200)
			}
		},
		bestiaryRange = makeRange(50, 250),
		bestiaryNames = {
			"Amphibic",
			"Aquatic",
			"Bird",
			"Construct",
			"Demon",
			"Dragon",
			"Elemental",
			"Fey",
			"Giant",
			"Human",
			"Humanoid",
			"Lycanthrope",
			"Magical",
			"Mammal",
			"Plant",
			"Reptile",
			"Slime",
			"Undead",
			"Vermin",
			"Extra Dimensional",
			"Inkborn"
		},
		directPerks = {
			[281] = {
				perkType = PERK_MANA_LEECH,
				range = makeRange(100, 800)
			},
			[282] = {
				perkType = PERK_LIFE_LEECH,
				range = makeRange(100, 1600)
			},
			[283] = {
				perkType = PERK_MANA_GAIN_ON_HIT,
				range = makeRange(2, 12)
			},
			[284] = {
				perkType = PERK_LIFE_GAIN_ON_HIT,
				range = makeRange(5, 25)
			},
			[285] = {
				perkType = PERK_MANA_GAIN_ON_KILL,
				range = makeRange(4, 24)
			},
			[286] = {
				perkType = PERK_LIFE_GAIN_ON_KILL,
				range = makeRange(10, 50)
			},
			[287] = {
				perkType = PERK_ALPHA_STRIKE_EXTRA_DAMAGE,
				range = makeRange(200, 1000)
			},
			[288] = {
				perkType = PERK_OMEGA_STRIKE_EXTRA_DAMAGE,
				range = makeRange(100, 400)
			},
			[321] = {
				perkType = PERK_ARMOR_PENETRATION,
				range = makeRange(500, 1500)
			},
			[322] = {
				perkType = PERK_ELEMENTAL_PIERCING,
				range = makeRange(500, 1500),
				allElements = true
			},
			[323] = {
				perkType = PERK_POWERFUL_FOE_DAMAGE,
				range = makeRange(100, 500)
			}
		},
		skillIds = { 1, 6, 7, 8, 9, 10, 11 },
		skillRanges = {
			[PERK_SKILL_PERCENTAGE_AUTO_ATTACK] = makeRange(200, 1000),
			[PERK_SKILL_PERCENTAGE_SPELL_DAMAGE] = makeRange(100, 800),
			[PERK_SKILL_PERCENTAGE_SPELL_HEALING] = makeRange(200, 1000)
		},
		integerPerkTypes = {
			[PERK_LIFE_GAIN_ON_HIT] = true,
			[PERK_MANA_GAIN_ON_HIT] = true,
			[PERK_LIFE_GAIN_ON_KILL] = true,
			[PERK_MANA_GAIN_ON_KILL] = true
		}
	}

	return modifierLookupCache
end

local function computeRangeValue(range, refineLevel)
	local level = refineLevel or 0

	if level <= 0 then
		return range.min
	end

	if level >= 10 then
		return range.max
	end

	return range.min + math.floor(range.step * level)
end

local function convertModifierRawValue(lookup, perkType, rawValue)
	if lookup.integerPerkTypes[perkType] then
		return rawValue
	end

	return rawValue / 10000
end

function ProficiencyData:loadProficiencyJsonContentOnly()
	self.content = {}
	self.proficiencyByName = {}
	self.proficiencyByWeaponItem = {}
	self.proficiencyByUniqueItemName = {}
	self.duplicateProficiencyItemNames = {}

	local file = "/json/proficiencies.json"

	if not g_resources.fileExists(file) then
		g_logger.error("Hunt config file not found: " .. file)

		return false
	end

	local status, result = pcall(function()
		return json.decode(g_resources.readFileContents(file))
	end)

	if not status then
		g_logger.error("Error while reading characterdata file. Details: " .. result)

		return false
	end

	for _, data in pairs(result) do
		local ProficiencyId = data.ProficiencyId

		self.content[ProficiencyId] = data

		local name = tostring(data.Name or ""):lower()
		if name ~= "" then
			self.proficiencyByName[name] = ProficiencyId

			local weaponType, handedness, itemName = name:match("^(%a+) ([12]h) (.+)$")
			if weaponType == "sword" or weaponType == "axe" or weaponType == "club"
				or weaponType == "wand" or weaponType == "rod" or weaponType == "caster"
				or weaponType == "distance" or weaponType == "bow" or weaponType == "crossbow"
				or weaponType == "fist" then
				self.proficiencyByWeaponItem[string.format("%s:%s:%s", weaponType, handedness, itemName)] = ProficiencyId
				if self.proficiencyByUniqueItemName[itemName]
					and self.proficiencyByUniqueItemName[itemName] ~= ProficiencyId then
					self.duplicateProficiencyItemNames[itemName] = true
				else
					self.proficiencyByUniqueItemName[itemName] = ProficiencyId
				end
			end

			local thrownItemName = name:match("^throw %- (.+)$")
			if thrownItemName then
				self.proficiencyByWeaponItem["throw:2h:" .. thrownItemName] = ProficiencyId
				if self.proficiencyByUniqueItemName[thrownItemName]
					and self.proficiencyByUniqueItemName[thrownItemName] ~= ProficiencyId then
					self.duplicateProficiencyItemNames[thrownItemName] = true
				else
					self.proficiencyByUniqueItemName[thrownItemName] = ProficiencyId
				end
			end
		end
	end

	return true
end

function ProficiencyData:loadProficiencyJson()
	if not self:loadProficiencyJsonContentOnly() then
		return false, "unable to load proficiency JSON"
	end

	if WeaponProficiency and WeaponProficiency.createItemCache then
		return pcall(function()
			WeaponProficiency:createItemCache()
		end)
	end

	return true
end

function ProficiencyData:isValidProfiencyId(id)
	return self.content[id] ~= nil
end

local DEFAULT_PROFICIENCY_BY_CATEGORY = {
	[MarketCategory.Axes] = 8,
	[MarketCategory.Clubs] = 9,
	[MarketCategory.DistanceWeapons] = 13,
	[MarketCategory.Swords] = 6,
	[MarketCategory.WandsRods] = 15,
	[MarketCategory.FistWeapons] = 14
}

local PROFICIENCY_TIER_PATTERNS = {
	"siphoning inferniarch",
	"draining inferniarch",
	"rending inferniarch",
	"stellar moonsilver",
	"gilded eldritch",
	"grand sanguine",
	"master umbral",
	"crude umbral",
	"destruction",
	"inferniarch",
	"moonsilver",
	"sanguine",
	"eldritch",
	"umbral",
	"jungle",
	"falcon",
	"glooth",
	"crypt",
	"amber",
	"cobra",
	"lion",
	"naga",
	"soul"
}

local function findCatalogProficiency(self, candidates)
	for _, candidate in ipairs(candidates) do
		local proficiencyId = self.proficiencyByName[candidate]
			or self.proficiencyByWeaponItem[candidate]
		if proficiencyId then
			return proficiencyId
		end
	end
	return nil
end

function ProficiencyData:resolveCatalogProficiency(itemId, marketCategory, itemName)
	local normalizedName = tostring(itemName or ""):lower()
	local itemType = g_things.getThingType(itemId, ThingCategoryItem)
	local slotPosition = itemType and itemType.getSlotPosition and tonumber(itemType:getSlotPosition()) or 0
	local handedness = math.floor(slotPosition / 1024) % 2 == 1 and "2h" or "1h"
	local weaponTypes = {}

	if marketCategory == MarketCategory.Axes then
		weaponTypes = { "axe" }
	elseif marketCategory == MarketCategory.Clubs then
		weaponTypes = { "club" }
	elseif marketCategory == MarketCategory.DistanceWeapons then
		handedness = "2h"
		weaponTypes = normalizedName:find("crossbow", 1, true) and { "crossbow", "distance", "bow" }
			or { "bow", "distance", "crossbow", "throw" }
	elseif marketCategory == MarketCategory.Swords then
		weaponTypes = { "sword" }
	elseif marketCategory == MarketCategory.WandsRods then
		if normalizedName:find("rod", 1, true) then
			weaponTypes = { "rod", "caster", "wand" }
		elseif normalizedName:find("wand", 1, true) then
			weaponTypes = { "wand", "caster", "rod" }
		else
			weaponTypes = { "caster", "wand", "rod" }
		end
	elseif marketCategory == MarketCategory.FistWeapons then
		handedness = "2h"
		weaponTypes = { "fist" }
	end

	local exactCandidates = { normalizedName }
	for _, weaponType in ipairs(weaponTypes) do
		exactCandidates[#exactCandidates + 1] = string.format("%s:%s:%s", weaponType, handedness, normalizedName)
	end
	local proficiencyId = findCatalogProficiency(self, exactCandidates)
	if proficiencyId then
		return proficiencyId
	end
	if not self.duplicateProficiencyItemNames[normalizedName]
		and self.proficiencyByUniqueItemName[normalizedName] then
		return self.proficiencyByUniqueItemName[normalizedName]
	end

	local tier
	for _, pattern in ipairs(PROFICIENCY_TIER_PATTERNS) do
		if normalizedName:find(pattern, 1, true) then
			tier = pattern
			break
		end
	end
	if tier then
		local tierCandidates = {}
		for _, weaponType in ipairs(weaponTypes) do
			tierCandidates[#tierCandidates + 1] = string.format("%s %s %s", tier, handedness, weaponType)
		end
		proficiencyId = findCatalogProficiency(self, tierCandidates)
		if proficiencyId then
			return proficiencyId
		end
	end

	return DEFAULT_PROFICIENCY_BY_CATEGORY[marketCategory]
end

function ProficiencyData:registerCatalogItem(itemId, marketCategory, itemName, serverProficiencyId)
	itemId = tonumber(itemId) or 0
	marketCategory = tonumber(marketCategory) or 0
	serverProficiencyId = tonumber(serverProficiencyId) or 0
	local proficiencyId = self:isValidProfiencyId(serverProficiencyId) and serverProficiencyId
		or self:resolveCatalogProficiency(itemId, marketCategory, itemName)

	if itemId > 0 and proficiencyId and self:isValidProfiencyId(proficiencyId) then
		self.catalogProficiencyByItem[itemId] = proficiencyId
		return proficiencyId
	end

	return 0
end

function ProficiencyData:getProficiencyIdForItem(itemOrType, marketData, itemName)
	if not itemOrType then
		return 0
	end

	local itemId = itemOrType.getId and tonumber(itemOrType:getId()) or 0
	local cached = itemId > 0 and self.catalogProficiencyByItem[itemId] or nil

	if cached then
		return cached
	end

	if not marketData and itemOrType.getMarketData then
		marketData = itemOrType:getMarketData()
	end

	local category = marketData and marketData.category or 0
	local name = itemName or (marketData and marketData.name) or ""

	return self:registerCatalogItem(itemId, category, name)
end

function ProficiencyData:getEntryProficiencyId(entry)
	if not entry then
		return 0
	end

	return entry.proficiencyId
		or self:getProficiencyIdForItem(entry.thingType or entry.displayItem, entry.marketData)
end

local PROFICIENCY_WEAPON_TOKENS = {
	Sword = MarketCategory.Swords,
	Axe = MarketCategory.Axes,
	Club = MarketCategory.Clubs,
	Bow = MarketCategory.DistanceWeapons,
	Crossbow = MarketCategory.DistanceWeapons,
	Fist = MarketCategory.FistWeapons,
	Wand = MarketCategory.WandsRods,
	Rod = MarketCategory.WandsRods
}
local PROFICIENCY_WEAPON_CATEGORIES = {
	[MarketCategory.Axes] = true,
	[MarketCategory.Clubs] = true,
	[MarketCategory.DistanceWeapons] = true,
	[MarketCategory.Swords] = true,
	[MarketCategory.WandsRods] = true,
	[MarketCategory.FistWeapons] = true
}

function ProficiencyData:getMarketCategoryFromName(name)
	if not name or name == "" then
		return nil
	end

	if name:find("Crossbow", 1, true) then
		return MarketCategory.DistanceWeapons
	end

	local firstToken = string.match(name, "^(%S+)")

	if firstToken and PROFICIENCY_WEAPON_TOKENS[firstToken] then
		return PROFICIENCY_WEAPON_TOKENS[firstToken]
	end

	local lastToken = string.match(name, "(%S+)$")

	if lastToken and PROFICIENCY_WEAPON_TOKENS[lastToken] then
		return PROFICIENCY_WEAPON_TOKENS[lastToken]
	end

	return nil
end

function ProficiencyData:resolveMarketCategory(itemType, proficiencyId)
	if not itemType then
		return nil
	end

	local marketData = itemType:getMarketData()

	if marketData and PROFICIENCY_WEAPON_CATEGORIES[marketData.category] then
		return marketData.category
	end

	local entry = self:getContentById(proficiencyId)

	if entry and entry.Name then
		return self:getMarketCategoryFromName(entry.Name)
	end

	return nil
end

function ProficiencyData:buildMarketDataForItem(itemType, proficiencyId)
	local category = self:resolveMarketCategory(itemType, proficiencyId)

	if not category then
		return nil
	end

	local itemId = itemType:getId()
	local rawMarket = itemType:getMarketData()
	local marketData = {}

	if rawMarket and not table.empty(rawMarket) then
		for key, value in pairs(rawMarket) do
			marketData[key] = value
		end
	end

	marketData.category = category
	marketData.showAs = marketData.showAs or itemId
	marketData.clientId = itemId

	if (not marketData.name or string.empty(marketData.name)) and g_things.getCyclopediaItemName then
		marketData.name = g_things.getCyclopediaItemName(itemId)
	end

	-- Astra does not expose ThingType:getName() to Lua. The previous fallback
	-- raised inside the protected cache build and left the entire weapon list
	-- empty without a visible error. The proficiency JSON always has a stable
	-- display name for entries accepted above, so use it as the local fallback.
	if not marketData.name or string.empty(marketData.name) then
		local entry = self:getContentById(proficiencyId)
		marketData.name = entry and entry.Name or string.format("Item %d", itemId)
	end

	marketData.requiredLevel = marketData.requiredLevel or 0
	marketData.restrictVocation = marketData.restrictVocation or 0

	return marketData
end

function ProficiencyData:getServerClientId(entry)
	return entry and entry.marketData and entry.marketData.clientId or 0
end

function ProficiencyData:getContentById(id)
	return self.content[id]
end

function ProficiencyData:getPerkLaneCount(id)
	local content = self.content[id]

	if not content then
		return 0
	end

	return table.size(content.Levels)
end

function ProficiencyData:formatFloatValue(value, roundFloat, perkType)
	if value == nil then
		return "0"
	end

	local isInteger = math.floor(value) == value

	if not isInteger or isInteger and PercentageTypesSet[perkType] then
		local percentage = math.floor(value * 10000 + 0.5) / 100
		local intPart = math.floor(percentage)
		local decimal1 = math.floor(percentage * 10 + 0.5) / 10

		if percentage == intPart then
			return tostring(intPart)
		elseif percentage == decimal1 then
			return string.format("%.1f", percentage)
		else
			return string.format("%.2f", percentage)
		end
	else
		return tostring(value)
	end
end

local function buildImagePath(sheet)
	return PROFICIENCY_IMAGE_PATH .. sheet
end

function ProficiencyData:getImageSourceAndClip(perkData)
	local perkType = perkData.Type

	if perkType == PERK_SPELL_AUGMENT then
		local iconIndex = PROFICIENCY_SPELL_ICON_BY_ID[perkData.SpellId] or 1
		local row = math.floor((iconIndex - 1) / 20)
		local column = (iconIndex - 1) % 20

		return SpelllistSettings.Default.iconsFolder, string.format("%d %d", column * 32, row * 32)
	end

	local sheetData = PerkMasteryIcons[perkType]

	if not sheetData then
		return buildImagePath("icons-weaponmastery"), "0 0"
	end

	if perkType == PERK_BESTIARY_DAMAGE then
		local bd = BestiaryCategories[perkData.BestiaryName]

		return buildImagePath(sheetData.sheet), getIconOffset(bd and bd.index or 0)
	end

	if perkType == PERK_SPECIAL_MAGIC_BOOST then
		local ed = MagicBoostMask[perkData.DamageType]

		return buildImagePath(sheetData.sheet), getIconOffset(ed and ed.index or 0)
	end

	if ElementalMaskPerk_t[perkType] then
		local ed = ElementalMask[perkData.ElementId]

		return buildImagePath(sheetData.sheet), getIconOffset(ed and ed.index or 0)
	end

	if FlatDamageBonus_t[perkType] then
		local sd = SkillTypes[perkData.SkillId]

		return buildImagePath(sheetData.sheet), getIconOffset(sd and sd.index or 0)
	end

	return buildImagePath(sheetData.sheet), getIconOffset(sheetData.index)
end

function ProficiencyData:getBonusNameAndTooltip(perkData)
	local perkType = perkData.Type
	local data = PerkTextData[perkType]
	local bonusName = data and data.name or "Empty"

	if not data then
		return bonusName, "Empty"
	end

	local value = self:formatFloatValue(perkData.Value, false, perkType)

	if perkType == PERK_SPELL_AUGMENT then
		local spellData = Spells.getSpellDataById(perkData.SpellId)
		local augmentData = AugmentPerkIcons[perkData.AugmentType]

		if not augmentData then
			return "Spell Augment", "Unknown spell augment"
		end
		local spellName = spellData and spellData.name
			or PROFICIENCY_SPELL_NAME_BY_ID[perkData.SpellId]
			or string.format("Spell %d", tonumber(perkData.SpellId) or 0)

		value = self:formatFloatValue(perkData.Value, true, perkType)

		if perkData.AugmentType == PERK_AUGMENT_COOLDOWN_REDUCTION then
			value = value / 100
		end

		local description = string.format(augmentData.desc, value, spellName)

		return bonusName, description
	end

	if perkType == PERK_BESTIARY_DAMAGE then
		local description = string.format(data.desc, value, perkData.BestiaryName or "Unknown")

		return bonusName, description
	end

	if perkType == PERK_SPECIAL_MAGIC_BOOST then
		local elementData = MagicBoostMask[perkData.DamageType]
		local description = string.format(data.desc, value, elementData and elementData.name or "Unknown")

		return bonusName, description
	end

	if perkType == PERK_PERFECT_SHOT then
		local description = string.format(data.desc, value, perkData.Range or 0)

		return bonusName, description
	end

	if perkType == PERK_ELEMENTAL_PIERCING then
		local elementData = ElementalMask[perkData.ElementId]
		local elementName = perkData.AllElements and "all elements" or (elementData and elementData.name or "Unknown")
		local description = string.format(data.desc, value, elementName)

		return bonusName, description
	end

	if perkType == PERK_HOMING_MISSILE then
		local elementData = ElementalMask[perkData.ElementId]
		local probability = self:formatFloatValue(perkData.Probability, false, perkType)
		local multiplier = self:formatFloatValue(perkData.Multiplier, false, perkType)
		local description = string.format(data.desc, probability, elementData and elementData.name or "Unknown", multiplier)

		return bonusName, description
	end

	if ElementalCritical_t[perkType] then
		local elementData = ElementalMask[perkData.ElementId]
		local description = string.format(data.desc, value, elementData and elementData.name or "Unknown")

		return bonusName, description
	end

	if FlatDamageBonus_t[perkType] then
		local skillData = SkillTypes[perkData.SkillId]
		local description = string.format(data.desc, value, skillData and skillData.name or "Unknown Skill")

		return bonusName, description
	end

	return bonusName, string.format(data.desc, value)
end

function ProficiencyData:getAugmentIconClip(perkData)
	local augmentData = AugmentPerkIcons[perkData.AugmentType]

	if not augmentData then
		g_logger.warning(string.format("Missing augmentId %d data", perkData.AugmentType))

		return string.format("0 0 %d %d", 16, 16)
	end

	return string.format("%d 0 %d %d", augmentData.index * 16, 16, 16)
end

function ProficiencyData:getModifierPerkData(modifierEnum, refineLevel)
	if not modifierEnum or modifierEnum == 0 then
		return nil
	end

	local lookup = getModifierLookupCache()

	if modifierEnum <= 250 and modifierEnum >= 1 then
		local blockStart = math.floor((modifierEnum - 1) / 50) * 50 + 1
		local spells = lookup.vocationSpells[blockStart]

		if not spells then
			return nil
		end

		local offset = modifierEnum - blockStart
		local sub = offset % 10

		if sub >= 6 then
			return nil
		end

		local spellId = spells[sub + 1]

		if not spellId then
			return nil
		end

		local groupInfo = lookup.spellGroups[math.floor(offset / 10)]

		if not groupInfo then
			return nil
		end

		local rawValue = computeRangeValue(groupInfo.range, refineLevel)

		return {
			Type = PERK_SPELL_AUGMENT,
			SpellId = spellId,
			AugmentType = groupInfo.augmentType,
			Value = convertModifierRawValue(lookup, PERK_SPELL_AUGMENT, rawValue)
		}
	end

	if modifierEnum <= 271 and modifierEnum >= 251 then
		local rawValue = computeRangeValue(lookup.bestiaryRange, refineLevel)

		return {
			Type = PERK_BESTIARY_DAMAGE,
			BestiaryName = lookup.bestiaryNames[modifierEnum - 250] or "Unknown",
			Value = convertModifierRawValue(lookup, PERK_BESTIARY_DAMAGE, rawValue)
		}
	end

	local skillRangeStart
	local skillPerkType
	local skillRange
	if modifierEnum >= 291 and modifierEnum <= 297 then
		skillRangeStart = 291
		skillPerkType = PERK_SKILL_PERCENTAGE_AUTO_ATTACK
	elseif modifierEnum >= 301 and modifierEnum <= 307 then
		skillRangeStart = 301
		skillPerkType = PERK_SKILL_PERCENTAGE_SPELL_DAMAGE
	elseif modifierEnum >= 311 and modifierEnum <= 317 and modifierEnum ~= 313 then
		skillRangeStart = 311
		skillPerkType = PERK_SKILL_PERCENTAGE_SPELL_HEALING
	end

	if skillRangeStart then
		skillRange = lookup.skillRanges[skillPerkType]
		local rawValue = computeRangeValue(skillRange, refineLevel)
		return {
			Type = skillPerkType,
			SkillId = lookup.skillIds[modifierEnum - skillRangeStart + 1],
			Value = convertModifierRawValue(lookup, skillPerkType, rawValue)
		}
	end

	local entry = lookup.directPerks[modifierEnum]

	if not entry then
		return nil
	end

	local rawValue = computeRangeValue(entry.range, refineLevel)

	return {
		Type = entry.perkType,
		Value = convertModifierRawValue(lookup, entry.perkType, rawValue),
		AllElements = entry.allElements
	}
end

function ProficiencyData:getCurrentCeilExperience(exp, displayItem)
	local best
	local vocation = self:getWeaponProfessionType(displayItem)
	local lastExp
	local perkLanes = self:getPerkLaneCount(self:getProficiencyIdForItem(displayItem))
	local limitIndex = perkLanes + 2
	local skipIndex = perkLanes > 0 and perkLanes + 1 or nil

	for index, stage in ipairs(ExperienceTable) do
		if limitIndex < index then
			break
		end

		if not skipIndex or index ~= skipIndex then
			local stageExp = stage[vocation]

			if stageExp then
				if exp < stageExp and (not best or stageExp < best) then
					best = stageExp
				end

				lastExp = stageExp
			end
		end
	end

	return best or lastExp
end

function ProficiencyData:getMaxExperience(perkCount, displayItem)
	local vocation = self:getWeaponProfessionType(displayItem)
	local lastLevel = ExperienceTable[perkCount + 2]

	return lastLevel[vocation] or 0
end

function ProficiencyData:getLevelXpRange(level, displayItem)
	local vocation = self:getWeaponProfessionType(displayItem)
	local prevLevel = math.max(level - 1, 0)
	local xpMin = prevLevel == 0 and 0 or ExperienceTable[prevLevel][vocation]
	local xpMax = ExperienceTable[level][vocation] or xpMin + 1

	return xpMin, xpMax
end

function ProficiencyData:getLevelPercent(currentExperience, level, displayItem)
	local xpMin, xpMax = self:getLevelXpRange(level, displayItem)
	local progress = math.max(0, math.min(1, (currentExperience - xpMin) / (xpMax - xpMin)))

	return math.floor(progress * 100)
end

function ProficiencyData:getTopBarProficiencyPercent(currentExp, displayItem)
	local profId = self:getProficiencyIdForItem(displayItem)

	if not profId or not self:isValidProfiencyId(profId) then
		return 0
	end

	local perkLanes = self:getPerkLaneCount(profId)

	if perkLanes <= 0 then
		return 0
	end

	local vocation = self:getWeaponProfessionType(displayItem)
	local floorLastPerk = ExperienceTable[perkLanes][vocation]
	local masteryXp = ExperienceTable[perkLanes + 2][vocation]

	if not floorLastPerk or not masteryXp or masteryXp <= floorLastPerk then
		return 0
	end

	if masteryXp <= currentExp then
		return 100
	end

	if floorLastPerk <= currentExp then
		local numer = currentExp - floorLastPerk
		local denom = masteryXp - floorLastPerk

		return math.floor(math.max(0, math.min(1, numer / denom)) * 100)
	end

	local maxAvailableLevel = perkLanes + 2
	local weaponLevel = self:getCurrentLevelByExp(displayItem, currentExp, true)
	local nextBracket = math.min(maxAvailableLevel, weaponLevel + 1)

	return self:getLevelPercent(currentExp, nextBracket, displayItem)
end

function ProficiencyData:getTotalPercent(currentExperience, perkCount, displayItem)
	local vocation = self:getWeaponProfessionType(displayItem)
	local maxExperience = ExperienceTable[perkCount + 2][vocation] or 1
	local progress = math.max(0, math.min(1, currentExperience / maxExperience))

	return math.floor(progress * 100)
end

function ProficiencyData:getMaxExperienceByLevel(level, displayItem)
	local vocation = self:getWeaponProfessionType(displayItem)

	return ExperienceTable[level][vocation] or 0
end

function ProficiencyData:getCurrentLevelByExp(displayItem, currentExperience, includeMastery)
	local vocation = self:getWeaponProfessionType(displayItem)
	local currentLevel = 0
	local skipLevel
	local profId = self:getProficiencyIdForItem(displayItem)

	if profId and self:isValidProfiencyId(profId) then
		local n = self:getPerkLaneCount(profId)

		if n > 0 then
			skipLevel = n + 1
		end
	end

	for level, data in ipairs(ExperienceTable) do
		if skipLevel and level == skipLevel then
			-- block empty
		else
			local requiredExp = data[vocation]

			if requiredExp then
				if requiredExp <= currentExperience then
					if currentLevel < level then
						currentLevel = level
					end
				else
					break
				end
			end
		end
	end

	local level = math.min(7, currentLevel)

	if includeMastery then
		level = currentLevel
	end

	return level
end

function ProficiencyData:getWeaponProfessionType(displayItem)
	local cached = displayItem._proficiencyVocation

	if cached then
		return cached
	end

	local vocation
	local marketData = displayItem:getMarketData()

	vocation = marketData.restrictVocation == 1 and "knight" or displayItem:getWeaponType() == WEAPON_CROSSBOW and "crossbow" or "regular"
	displayItem._proficiencyVocation = vocation

	return vocation
end
