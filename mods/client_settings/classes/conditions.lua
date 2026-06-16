-- data/images/arcs/conditions/player-state-flags.png
local EMBLEM_HUD_ICON_PATH = '/images/arcs/conditions/player-state-guildwar-flag'
local HUNGRY_HUD_ICON_PATH = '/images/arcs/conditions/player-state-flags-client-02'

local widgets = {
    [1] = {
        icon = Icons[PlayerStates.Poison].path,
        path = '/images/arcs/conditions/player-state-flags-00',
        name = "poisoned",
        id = Icons[PlayerStates.Poison].id,
        visibleHud = true,
        visibleBar = true,
        tooltipBar = tr('You are poisoned'),
        tooltip = tr(
            'This condition of the earth damage type can be caused by spells or\ncertain monsters. The total damage dealt by poisons can vary\ngreatly, but any poisoning can be easily removed by using the\n"Cure Poison" spell or the "Cure Poison Rune".'
        )
    },
    [2] = {
        icon = Icons[PlayerStates.Burn].path,
        name = "burning",
        path = '/images/arcs/conditions/player-state-flags-01',
        id = Icons[PlayerStates.Burn].id,
        visibleHud = true,
        visibleBar = true,
        tooltipBar = tr('You are burning'),
        tooltip = tr(
            "This is a harmful effect of the fire damage type that causes your\ncharacter to lose hit points over an extended period of time. Until it\nends, a searing flame will appear on your character at regular\nintervals. The damage dealt by the fire depends on its source.\nDruids have the magical ability to cure any burning."
        )
    },
    [3] = {
        icon = Icons[PlayerStates.Energy].path,
        name = "electrified",
        path = '/images/arcs/conditions/player-state-flags-02',
        id = Icons[PlayerStates.Energy].id,
        visibleHud = true,
        visibleBar = true,
        tooltipBar = tr('You are electrified'),
        tooltip = tr(
            'Electrified is a condition of the energy damage type that causes\nprolonged hit point loss, similar to the burning condition caused by\nfire. A flash of electrical energy will appear on your character at\nregular intervals, dealing damage each time it occurs. As with\nburning, only druids have the power to end this unpleasant\ncondition using the "Cure Electrification" spell.'
        )
    },
    [4] = {
        icon = Icons[PlayerStates.Bleeding].path,
        name = "bleeding",
        path = '/images/arcs/conditions/player-state-flags-15',
        id = Icons[PlayerStates.Bleeding].id,
        visibleHud = true,
        visibleBar = true,
        tooltipBar = tr('You are bleeding'),
        tooltip = tr(
            'Sometimes, creatures inflict heavy wounds on your character that\nbleed for a certain period of time. While losing blood, your\ncharacter becomes increasingly weak and loses health points over\ntime. Those who know the "Cure Bleeding" spell are fortunate, as\nthey can instantly force the gaping wound to close.'
        )
    },
    [5] = {
        icon = Icons[PlayerStates.Agony].path,
        name = "agony",
        path = '/images/arcs/conditions/player-state-flags-27',
        id = Icons[PlayerStates.Agony].id,
        visibleHud = true,
        visibleBar = true,
        tooltipBar = tr('You are in agony'),
        tooltip = tr(
            "If a character is afflicted with agony, they will continuously take\ndamage over time. There is no way to cure, block or resist this\neffect - the only option is to endure it until it fades."
        )
    },
    [6] = {
        icon = Icons[PlayerStates.Powerless].path,
        name = "powerless",
        id = Icons[PlayerStates.Powerless].id,
        path = '/images/arcs/conditions/player-state-flags-28',
        visibleHud = true,
        visibleBar = true,
        tooltipBar = tr('You are Powerless'),
        tooltip = tr(
            "If a character is affected by Powerless, they are unable to cast\nattack spells or use offensive runes."
        )
    },
    [7] = {
        icon = Icons[PlayerStates.Rooted].path,
        name = "rooted",
        id = Icons[PlayerStates.Rooted].id,
        path = '/images/arcs/conditions/player-state-flags-19',
        visibleHud = true,
        visibleBar = true,
        tooltipBar = tr('You are rooted'),
        tooltip = tr(
            "If a monster casts this powerful spell on your character, your\ncharacter will be unable to move for a few seconds. This effect\ncannot be removed."
        )
    },
    [8] = {
        icon = Icons[PlayerStates.Feared].path,
        name = "feared",
        id = Icons[PlayerStates.Feared].id,
        path = '/images/arcs/conditions/player-state-flags-20',
        visibleHud = true,
        visibleBar = true,
        tooltipBar = tr('You are feared'),
        tooltip = tr(
            "Feared is a condition that certain monsters can cast on you. If you\nare feared, you temporarily lose control of your character. During\nthis time, your character will run away from the creature that\ncaused the fear. In addition, you cannot cast spells or use any\nitems."
        )
    },
    [9] = {
        icon = Icons[PlayerStates.Drunk].path,
        name = "drunk",
        path = '/images/arcs/conditions/player-state-flags-03',
        id = Icons[PlayerStates.Drunk].id,
        visibleHud = true,
        visibleBar = true,
        tooltipBar = tr('You are drunk'),
        tooltip = tr(
            "Taverns in Astra are popular gathering places where many\nadventurers enjoy relaxing after their wearisome travels with a\npint of cool beer. However, Astra's beer is quite strong, so don't be\nsurprised if your character has trouble walking in a straight line for\na while."
        )
    },
    [10] = {
        icon = Icons[PlayerStates.NewMagicShield].path,
        name = "magic shield",
        id = Icons[PlayerStates.NewMagicShield].id,
        path = '/images/arcs/conditions/player-state-flags-26',
        visibleHud = true,
        visibleBar = true,
        tooltipBar = tr('You are protected by a magic shield'),
        tooltip = tr(
            "Another positive spell effect, magic shields protect characters from\nlosing hit points while active by reducing their mana instead.\nHowever, if a character's mana is reduced to zero, any further\ndamage will be deducted from their hit points as usual."
        )
    },
    [11] = {
        icon = Icons[PlayerStates.Paralyze].path,
        name = "slowed",
        path = '/images/arcs/conditions/player-state-flags-05',
        id = Icons[PlayerStates.Paralyze].id,
        visibleHud = true,
        visibleBar = true,
        tooltipBar = tr('You are paralysed'),
        tooltip = tr(
            "Some creatures or spells may slow your character down. Until the\neffect ends or is dispelled by healing magic, your character will\nmove much more slowly than usual. However, all other actions -\nsuch as casting spells - can still be performed normally."
        )
    },
    [12] = {
        icon = Icons[PlayerStates.Haste].path,
        name = "haste",
        path = '/images/arcs/conditions/player-state-flags-06',
        id = Icons[PlayerStates.Haste].id,
        visibleHud = true,
        visibleBar = true,
        tooltipBar = tr('You are hasted'),
        tooltip = tr(
            'This condition is the direct opposite of the "Slow" effect. While it is\nactive, your character will move significantly faster, although other\neffects - such as hit point regeneration or attack rate - will remain\nunaffected. Needless to say, this is a desirable condition.\nCharacters can be hasted by spells or special magical items.'
        )
    },
    [13] = {
        icon = Icons[PlayerStates.Swords].path,
        name = "logout block",
        path = '/images/arcs/conditions/player-state-flags-07',
        id = Icons[PlayerStates.Swords].id,
        visibleHud = false,
        visibleBar = true,
        tooltipBar = tr('You may not logout during a fight'),
        tooltip = tr(
            "Characters affected by a logout block cannot log out safely. It\noccurs when engaging in or being affected by combat actions like\nattacking, casting offensive spells, or taking damage. The block\nlasts 60 seconds from the last violent act. Killing another player\nextends the block to 15 minutes. Wait until the icon disappears\nbefore logging out to avoid leaving your character vulnerable."
        )
    },
    [14] = {
        icon = Icons[PlayerStates.Drowning].path,
        name = "drowning",
        id = Icons[PlayerStates.Drowning].id,
        path = '/images/arcs/conditions/player-state-flags-08',
        visibleHud = true,
        visibleBar = true,
        tooltipBar = tr('You are drowning'),
        tooltip = tr(
            "Astra features a special underwater area. Since no one can survive\nwithout fresh air, characters will take damage if they walk\nunderwater without the proper equipment. The only way to survive\nis to leave the water quickly or equip a life-saving diving helmet."
        )
    },
    [15] = {
        icon = Icons[PlayerStates.Freezing].path,
        name = "freezing",
        path = '/images/arcs/conditions/player-state-flags-09',
        id = Icons[PlayerStates.Freezing].id,
        visibleHud = true,
        visibleBar = true,
        tooltipBar = tr('You are freezing'),
        tooltip = tr(
            "This condition of the ice damage type is caused by the freezing\nbreath of certain monsters. It causes your character to lose hit\npoints at regular intervals over an extended period. There is no\nmedicine to cure it, but if you're near a priest, you can ask them to\nheal you."
        )
    },
    [16] = {
        icon = Icons[PlayerStates.Dazzled].path,
        name = "dazzled",
        path = '/images/arcs/conditions/player-state-flags-10',
        id = Icons[PlayerStates.Dazzled].id,
        visibleHud = true,
        visibleBar = true,
        tooltipBar = tr('You are dazzled'),
        tooltip = tr(
            "If your character is marked as dazzled, a holy light has just struck\nwith pitiless force. Similar to being electrified, your character will\nlose a decreasing amount of hit points a few times. This condition,\ncaused by the holy damage type, has no remedy - your only\noptions are to wait it out or seek healing from a nearby priest."
        )
    },
    [17] = {
        icon = Icons[PlayerStates.Cursed].path,
        name = "cursed",
        path = '/images/arcs/conditions/player-state-flags-11',
        id = Icons[PlayerStates.Cursed].id,
        visibleHud = true,
        visibleBar = true,
        tooltipBar = tr('You are cursed'),
        tooltip = tr(
            "Have your health potions and healing spells ready whenever a\ncreature curses you. If your character is affected by this special\ncondition of the death damage type, a black cloud will literally\nhang over their head. For a considerable time, they will lose an\nincreasing amount of hit points at regular intervals. Only paladins,\nas masters of holy magic, are able to cure a character of a curse."
        )
    },
    [18] = {
        icon = Icons[PlayerStates.Mentored].path,
        name = "mentor other",
        path = '/images/arcs/conditions/player-state-flags-29',
        id = Icons[PlayerStates.Mentored].id,
        visibleHud = false,
        visibleBar = true,
        tooltipBar = tr('You are empowered by Mentor Other'),
        tooltip = tr(
            "Mentor Other grants a shared buff to both the caster and the\ntarget. The effect adapts to the target's vocation, enhancing their\nprimary role - such as melee strength, ranged damage, elemental\nmagic or healing. Only one character can be mentored at a time."
        )
    },
    [19] = {
        icon = Icons[PlayerStates.PartyBuff].path,
        name = "strengthened",
        path = '/images/arcs/conditions/player-state-flags-12',
        id = Icons[PlayerStates.PartyBuff].id,
        visibleHud = false,
        visibleBar = true,
        tooltipBar = tr('You are strengthened'),
        tooltip = tr(
            "This condition is caused by various spells. Whenever such a spell is\ncast, one or more of the character's skills are temporarily\nincreased. This condition is commonly found in parties where\ncharacters, depending on their vocation, can raise the magic level,\nhit point regeneration, weapon skills or shielding of party\nmembers."
        )
    },
    [20] = {
        icon = Icons[PlayerStates.PzBlock].path,
        name = "protection zone block",
        path = '/images/arcs/conditions/player-state-flags-13',
        id = Icons[PlayerStates.PzBlock].id,
        visibleHud = false,
        visibleBar = true,
        tooltipBar = tr('You may not logout or enter a protection zone'),
        tooltip = tr(
            "A protection zone block is always accompanied by a logout block.\nIf your character attacks another character first, they will not only\nbe unable to log out but also unable to enter any protection zones.\nHowever, there is no protection zone block when you attack a\nmember of your own party."
        )
    },
    [21] = {
        icon = Icons[PlayerStates.Pz].path,
        name = "in protection zone",
        path = '/images/arcs/conditions/player-state-flags-14',
        id = Icons[PlayerStates.Pz].id,
        visibleHud = false,
        visibleBar = true,
        tooltipBar = tr('You are within a protection zone'),
        tooltip = tr(
            "Whenever characters are standing in a protection zone, they\ncannot perform any aggressive actions. At the same time, they are\nsafe there, as creatures and other characters cannot attack them."
        )
    },
    [22] = {
        icon = "/images/game/states/28",
        name = "resting area",
        path = '/images/arcs/conditions/player-state-flags-client-00',
        id = "condition_restingarea",
        visibleHud = false,
        visibleBar = true,
        tooltipBar = tr(''),
        tooltip = tr(
            "Certain protection areas, such as houses, temples, or depots, are\nalso considered resting areas. When a character is in a resting\narea, one of these small symbols will be active. Just like in a\nprotection zone, characters cannot perform any aggressive\nactions. In addition, they are safe from attacks by creatures or\nother characters.\n\nCharacters who have reached at least daily reward streak 2 will\nbenefit from a resting bonus, such as mana or hit point\nregeneration, while in a resting area."
        )
    },
    [23] = {
        icon = Icons[PlayerStates.SufferringLesserHex].path,
        name = "lesser hex",
        path = '/images/arcs/conditions/player-state-flags-16',
        id = Icons[PlayerStates.SufferringLesserHex].id,
        visibleHud = true,
        visibleBar = true,
        tooltipBar = tr('You are sufferring lesser hex'),
        tooltip = tr(
            "A character affected by a lesser hex receives reduced healing. This\nmakes it harder to recover hit points from spells, potions, or other\nsources."
        )
    },
    [24] = {
        icon = Icons[PlayerStates.SufferringIntenserHex].path,
        name = "intenser hex",
        path = '/images/arcs/conditions/player-state-flags-17',
        id = Icons[PlayerStates.SufferringIntenserHex].id,
        visibleHud = true,
        visibleBar = true,
        tooltipBar = tr('You are sufferring intenser hex'),
        tooltip = tr(
            "An intense hex reduces the healing a character receives and also\nlowers the damage they deal. This weakens both survivability and\ncombat performance."
        )
    },
    [25] = {
        icon = Icons[PlayerStates.SufferringGreaterHex].path,
        name = "greater hex",
        path = '/images/arcs/conditions/player-state-flags-18',
        id = Icons[PlayerStates.SufferringGreaterHex].id,
        visibleHud = true,
        visibleBar = true,
        tooltipBar = tr('You are sufferring greater hex'),
        tooltip = tr(
            "A greater hex significantly weakens a character by reducing their\nmaximum hit points, in addition to lowering healing received and\ndamage dealt, as with the lesser and intense hexes."
        )
    },
    [26] = {
        icon = "/images/game/states/cursev",
        name = "goshnar's taint",
        path = '/images/arcs/conditions/player-state-flags-25',
        id = "condition_curse",
        tooltipBar = tr('If you are in Goshnar\'s lairs, you are sufferring from the following penalty:\n- 10%% chance that a creature teleports near you\n 0.5%% chance that a new creature spawns near you if you hit another creature\n- received damage increased by 15%% \n - 10%% chance that a creature will fully heal itself instead of dying\n- loss of 10%% of your hit points and your mana every 10 seconds'),
        visibleHud = false,
        visibleBar = true,
        tooltip = tr(
            "Depending on how many bosses a character has defeated in\nGoshnar's Lair, they will suffer from one to five penalties:\n* There is a chance that a monster will teleport near you.\n* There is a small chance that a new creature will spawn near you\nwhen you hit another creature.\n* You receive increased damage.\n* There is a moderate chance that a creature will fully heal itself\ninstead of dying.\n* You lose 10%% of your hit points and mana every 5 seconds."
        )
    },
    [27] = {
        icon = "/images/game/states/39",
        name = "bakragore's taint",
        path = '/images/arcs/conditions/player-state-flags-rotten-blood-08',
        id = "condition_taints",
        tooltipBar = tr(''),
        visibleHud = false,
        visibleBar = true,
        tooltip = tr(
            "Depending on how many taints a character has in Bakragore's lairs,\nthey will suffer from up to four penalties:\n* Certain melee creatures may switch places with nearby\ncharacters.\n* Upon death, a monster may spawn a stronger foe from its\ncorpse.\n* Monsters gain additional abilities.\n* Characters take increased damage from all sources.\n\nA fifth taint can be gained by defeating Bakragore, granting\nenhanced experience and loot without penalties and enabling\nessence drops from his progeny.\n\nTaint level is based on the party member with the fewest taints. To\ngain a taint, a character must match this minimum, not yet have\nthe boss's taint and deal damage during the fight. Each taint also\nimproves loot and experience."
        )
    },
    [28] = {
        icon = "/images/game/states/skullyellow",
        name = "yellow skull",
        path = '/images/arcs/conditions/player-state-playerkiller-flags-00',
        id = "skullyellow",
        tooltipBar = tr('You have a yellow skull'),
        visibleHud = true,
        visibleBar = true,
        tooltip = tr(
            'This skull is somewhat special because it is not visible to all\nplayers on the screen. You will only see it if your character was\nattacked or damaged by another character while your own\ncharacter was marked with a skull. This indicates your right to\ndefend yourself, even while being marked.\nKilling a character with a yellow skull does not count as a\n"unjustified" kill, just like any other kill of a marked character.\nSimilar to a white skull, a yellow skull remains active as long as the\nlogout block is in effect. If the character continues to perform\noffensive actions while marked with a yellow skull, the duration of\nthe skull, the logout block and the connected protection zone block\nwill be extended.'
        )
    },
    [29] = {
        icon = SkullIcons[SkullGreen].path,
        name = "party mode",
        id = "skullgreen",
        tooltipBar = tr('You are a member of a party'),
        path = '/images/arcs/conditions/player-state-playerkiller-flags-01',
        visibleHud = true,
        visibleBar = true,
        tooltip = tr(
            "While in a party, your character cannot accidentally harm party\nmembers with any attacks, such as area spells. Party members can\nalso benefit from shared experience and access to certain party-\nexclusive spells."
        )
    },
    [30] = {
        icon = SkullIcons[SkullWhite].path,
        name = "white skull",
        id = "skullwhite",
        tooltipBar = tr('You have attacked an unmarked player'),
        path = '/images/arcs/conditions/player-state-playerkiller-flags-02',
        visibleHud = true,
        visibleBar = true,
        tooltip = tr(
            "A character marked with a white skull has recently attacked or\nkilled an unmarked character. This mark is visible to all players\nand remains active as long as the logout block is in effect. If the\ncharacter continues to perform offensive actions while marked, the\nduration of the white skull, the logout block and the protection\nzone block will be extended."
        )
    },
    [31] = {
        icon = SkullIcons[SkullRed].path,
        name = "red skull",
        id = "skullred",
        tooltipBar = tr('You have killed too many unmarked players'),
        path = '/images/arcs/conditions/player-state-playerkiller-flags-03',
        visibleHud = true,
        visibleBar = true,
        tooltip = tr(
            "A red skull marks a character who has killed or assisted in killing\ntoo many unmarked players. While marked, the character will drop\nall items upon death, even with blessings or an Amulet of Loss. The\nred skull lasts 30 days and resets if further unjustified kills occur\nduring this time."
        )
    },
    [32] = {
        icon = "/images/game/skulls/skull_black",
        name = "black skull",
        tooltipBar = tr(''),
        path = '/images/arcs/conditions/player-state-playerkiller-flags-04',
        id = "skullblack",
        visibleHud = true,
        visibleBar = true,
        tooltip = tr(
            "A character with a black skull has committed too many unjustified\nkills while already marked with a red skull. While marked, the\ncharacter drops all items upon death, cannot attack unmarked\ncharacters and cannot use the expert mode Red Fist. They receive\nfull damage in PvP and will revive with only 40 hit points and 0\nmana. The black skull lasts 45 days and is reset if the character\ncontinues to gain unjustified points during this time."
        )
    },
    [33] = {
        icon = SkullIcons[SkullOrange].path,
        name = "orange skull",
        path = '/images/arcs/conditions/player-state-playerkiller-flags-05',
        id = "skullorange",
        tooltipBar = tr('You may suffer revenge from your former victim'),
        visibleHud = true,
        visibleBar = true,
        tooltip = tr(
            "An orange skull is only visible to the character who was killed\nunjustified and to the killer. It appears when your character has\nbeen killed unjustified by another player and lasts for 7 days. If\nyou kill a character marked with an orange skull, the kill does not\ncount as unjustified. However, attacking them still results in a\nyellow skull and a protection zone block. The orange skull\ndisappears either after 7 days or once you have taken revenge for\neach unjustified kill received within that time."
        )
    },
    [34] = {
        icon = EMBLEM_HUD_ICON_PATH,
        path = EMBLEM_HUD_ICON_PATH,
        name = "in guild war",
        id = "emblem",
        visibleHud = false,
        visibleBar = true,
        tooltipBar = tr('You are in a guild war'),
        tooltip = tr(
            "If your character is part of an active guild war, they will receive a\nprotection zone block when attacking enemies. Kills against the\nsame enemy count up to five times within 24 hours. Characters not\ninvolved in the war cannot heal or buff your character if they were\nrecently damaged by a member of the opposing guild."
        )
    },
    [35] = {
        icon = Icons[PlayerStates.Hungry].path,
        name = "hungry",
        path = HUNGRY_HUD_ICON_PATH,
        id = Icons[PlayerStates.Hungry].id,
        visibleHud = false,
        visibleBar = true,
        tooltipBar = tr('You are hungry'),
        tooltip = tr(
            "Characters who are hungry do not regenerate mana or health. To\nfill up your character's stomach, look for something edible, such as\nan apple, bread, or ham. There are plenty of things in Astra that\nyour character can eat. Check out stores, search bushes, bake your\nown bread or cake, or defeat creatures to find some delicacies."
        )
    }
}


if not SpecialConditionHUD then
    SpecialConditionHUD = {
        internalId = 0,
        icon = '',
        path = '',
        name = '',
        id = '0',
        tooltip = '',
        tooltipBar = '',
    }
end

function SpecialConditionHUD:new(dataset)
    local instance = setmetatable({}, { __index = self })
    instance.internalId = dataset.internalId
    instance.icon = dataset.icon
    instance.path = dataset.path
    instance.name = string.capitalize(dataset.name)
    instance.id = dataset.id
    instance.tooltip = dataset.tooltip
    instance.visibleHud = dataset.visibleHud -- default to true if not specified
    instance.visibleBar = dataset.visibleBar -- default to true if not specified
    instance.tooltipBar = dataset.tooltipBar
    return instance
end

-- getters and setters
function SpecialConditionHUD:getInternalId() return self.internalId end

function SpecialConditionHUD:getIcon() return self.icon end
function SpecialConditionHUD:getPath() return self.path end

function SpecialConditionHUD:getName() return self.name end

function SpecialConditionHUD:getId() return self.id end

function SpecialConditionHUD:getTooltip() return self.tooltip end
function SpecialConditionHUD:getTooltipBar() return self.tooltipBar end
function SpecialConditionHUD:setTooltipBar(tooltipBar)
    self.tooltipBar = tooltipBar
end

function SpecialConditionHUD:setIcon(icon) self.icon = icon end
function SpecialConditionHUD:setPath(path) self.path = path end

function SpecialConditionHUD:setName(name) self.name = name end

function SpecialConditionHUD:setId(id) self.id = id end

function SpecialConditionHUD:setTooltip(tooltip) self.tooltip = tooltip end

function SpecialConditionHUD:isVisibleHud() return self.visibleHud end
function SpecialConditionHUD:setVisibleHud(v)
    self.visibleHud = v
end

function SpecialConditionHUD:isVisibleBar() return self.visibleBar end
function SpecialConditionHUD:setVisibleBar(visibleBar)
    self.visibleBar = visibleBar
end

function SpecialConditionHUD:getIndex()
    return ConditionsHUD:getIndexById(self:getId())
end

if not ConditionsHUD then
    ConditionsHUD = {
        specialConditionsOrder = {},
        defaultHuds = {},
        hud = {},
        inventoryBar = {},
        topbarWidgets = {},

        widgets = {},

        actives = {},
        selectedWidget = nil,
        settings = {},

        zone = 0, state = 0, message = ''
    }
    ConditionsHUD.__index = ConditionsHUD
end

local function refreshStatusIconBar()
    local refreshed = false

    if StatusIconBar and type(StatusIconBar.refreshIcons) == 'function' then
        refreshed = true
        addEvent(function()
            StatusIconBar.refreshIcons()
        end)
    end

    local healthCircle = modules and modules.game_healthcircle
    if healthCircle and type(healthCircle.refreshStatusIcons) == 'function' then
        refreshed = true
        addEvent(function()
            healthCircle.refreshStatusIcons()
        end)
    end

    local statusIconBar = modules and modules.game_statusiconbar
    if statusIconBar and type(statusIconBar.refreshStatusIcons) == 'function' then
        refreshed = true
        addEvent(function()
            statusIconBar.refreshStatusIcons()
        end)
    end

    return refreshed
end

local function syncStatusIconBarHudVisibility(id, visible)
    if StatusIconBar and type(StatusIconBar.setNativeHudConditionVisible) == 'function' then
        StatusIconBar.setNativeHudConditionVisible(id, visible)
    end

    local healthCircle = modules and modules.game_healthcircle
    if healthCircle and type(healthCircle.setNativeHudConditionVisible) == 'function' then
        healthCircle.setNativeHudConditionVisible(id, visible)
    end

    local statusIconBar = modules and modules.game_statusiconbar
    if statusIconBar and type(statusIconBar.setNativeHudConditionVisible) == 'function' then
        statusIconBar.setNativeHudConditionVisible(id, visible)
    end
end

local function syncStatusIconBarHudMaster(value)
    if StatusIconBar and type(StatusIconBar.setNativeHudMasterEnabled) == 'function' then
        StatusIconBar.setNativeHudMasterEnabled(value)
    end

    local healthCircle = modules and modules.game_healthcircle
    if healthCircle and type(healthCircle.setNativeHudMasterEnabled) == 'function' then
        healthCircle.setNativeHudMasterEnabled(value)
    end

    local statusIconBar = modules and modules.game_statusiconbar
    if statusIconBar and type(statusIconBar.setNativeHudMasterEnabled) == 'function' then
        statusIconBar.setNativeHudMasterEnabled(value)
    end
end

local emblemIcons = {
    [EmblemGreen or 1] = '/images/game/emblems/emblem_green',
    [EmblemRed or 2] = '/images/game/emblems/emblem_red',
    [EmblemBlue or 3] = '/images/game/emblems/emblem_blue',
    [EmblemMember or 4] = '/images/game/emblems/emblem_member',
    [EmblemOther or 5] = '/images/game/emblems/emblem_other'
}

local emblemTooltips = {
    [EmblemGreen or 1] = tr('Green Emblem'),
    [EmblemRed or 2] = tr('Red Emblem'),
    [EmblemBlue or 3] = tr('Blue Emblem'),
    [EmblemMember or 4] = tr('Member Emblem'),
    [EmblemOther or 5] = tr('Other Emblem')
}

local function getEmblemIconPath(emblem)
    if type(getEmblemImagePath) == 'function' then
        local path = getEmblemImagePath(emblem)
        if path then return path end
    end
    return emblemIcons[emblem]
end

local function getEmblemTooltip(emblem)
    return emblemTooltips[emblem] or tr('Guild Emblem')
end

local function isEmblemActive(emblem)
    return emblem ~= nil and emblem ~= (EmblemNone or 0)
end

local function applyEmblemStyle(specialCondition, emblem)
    local iconPath = getEmblemIconPath(emblem)
    if not specialCondition or not iconPath then
        return false
    end

    local tooltip = getEmblemTooltip(emblem)
    specialCondition:setIcon(iconPath)
    specialCondition:setPath(EMBLEM_HUD_ICON_PATH)
    specialCondition:setTooltipBar(tooltip)

    if g_client and type(g_client.updateHudPath) == 'function' then
        g_client.updateHudPath(specialCondition:getId(), EMBLEM_HUD_ICON_PATH)
    end

    local inventoryWidget = ConditionsHUD.inventoryBar[specialCondition:getId()]
    if inventoryWidget then
        inventoryWidget:setImageSource(iconPath)
        inventoryWidget:setTooltip(tooltip)
    end

    local topbarWidget = ConditionsHUD.topbarWidgets[specialCondition:getId()]
    if topbarWidget then
        topbarWidget:setImageSource(iconPath)
        topbarWidget:setTooltip(tooltip)
    end

    local settingsWidget = ConditionsHUD.widgets[specialCondition:getId()]
    if settingsWidget and settingsWidget.icon then
        settingsWidget.icon:setImageSource(EMBLEM_HUD_ICON_PATH)
    end

    return true
end

function ConditionsHUD:load()
  ConditionsHUD.settings = {
    ordenered = {},
    visibleHud = {},
    visibleBar = {}
  }

  local file = "/settings.json"
  if g_resources.fileExists(file) then
    local status, result = pcall(function()
      return json.decode(g_resources.readFileContents(file))
    end)

    if not status then
      return false
    end

    ConditionsHUD.settings = result
    if not ConditionsHUD.settings.visibleHud then
      ConditionsHUD.settings.visibleHud = {}
    end
    if not ConditionsHUD.settings.visibleBar then
      ConditionsHUD.settings.visibleBar = {}
    end
    if not ConditionsHUD.settings.ordenered then
      ConditionsHUD.settings.ordenered = {}
    end
  end
end

function ConditionsHUD:addHUDCondition(localPlayer, id)
    if not localPlayer or not localPlayer.addHUDCondition then
        return
    end

    local conditionId = tonumber(id)
    if conditionId then
        localPlayer:addHUDCondition(conditionId)
    end
end

function ConditionsHUD:removeHUDCondition(localPlayer, id)
    if not localPlayer or not localPlayer.removeHUDCondition then
        return
    end

    local conditionId = tonumber(id)
    if conditionId then
        localPlayer:removeHUDCondition(conditionId)
    end
end

function ConditionsHUD:save()
  local settings = {}
  settings.ordenered = {}
  for i, condition in ipairs(ConditionsHUD.specialConditionsOrder) do
    if condition then
      settings.ordenered[i] = condition:getId()
    end
  end

  settings.visibleHud = {}
  settings.visibleBar = {}
    for id, widget in pairs(ConditionsHUD.widgets) do
        local condition = ConditionsHUD:getSpecialConditionById(id)
        if condition then
            settings.visibleHud[id] = condition:isVisibleHud()
            settings.visibleBar[id] = condition:isVisibleBar()
        end
    end

    local file = "/settings.json"
    local status, result = pcall(function() return json.encode(settings) end)
    if not status then
        return g_logger.error("Error while saving profile characterdata sidebars. Data won't be saved. Details: " .. result)
    end

    if result:len() > 100 * 1024 * 1024 then
        return g_logger.error("Something went wrong, file is above 100MB, won't be saved")
    end
    g_resources.writeFileContents(file, result)
end

function ConditionsHUD:configure()
    ConditionsHUD.specialConditionsOrder = {}
    ConditionsHUD.actives = {}
    ConditionsHUD.selectedWidget = nil
    g_client.clearHudConfigs()
    for i = 1, #widgets do
        local widget = widgets[i]
        local dataset = {
            internalId = i,
            icon = widget.icon,
            path = widget.path,
            name = widget.name,
            id = widget.id,
            tooltip = widget.tooltip,
            tooltipBar = widget.tooltipBar,
            visibleHud = widget.visibleHud,
            visibleBar = widget.visibleBar
        }
        local specialconditionhud = SpecialConditionHUD:new(dataset)
        ConditionsHUD.hud[specialconditionhud:getId()] = specialconditionhud
        ConditionsHUD.specialConditionsOrder[i] = specialconditionhud
    end

    -- load json config file??
    ConditionsHUD:load()

    -- create labels
    local hudWindow = GameOptions:getLoadedWindow("hud")
    if not hudWindow then
        return
    end

    local conditionList = hudWindow:recursiveGetChildById('conditionsList')
    conditionList:destroyChildren()

    for i, condition in ipairs(ConditionsHUD.specialConditionsOrder) do
        if condition then
            local widget = g_ui.createWidget('ConditionLabelSettings', conditionList)
            widget:setId(condition:getId())
            widget.label:setText(condition:getName())
            widget:setTooltip(condition:getTooltip())
            widget.icon:setImageSource(condition:getIcon())
            widget.showInHudCheckBox.onCheckChange = function(widget, checked)
                ConditionsHUD:changeVisibilityInHud(condition:getId(), checked)
            end

            local visibleHud = ConditionsHUD.settings.visibleHud[condition:getId()]
            if visibleHud == nil then
                visibleHud = condition:isVisibleHud()
            end
            condition:setVisibleHud(visibleHud)
            syncStatusIconBarHudVisibility(condition:getId(), visibleHud)
            widget.showInHudCheckBox:setChecked(visibleHud)
            widget.showInBarCheckBox.onCheckChange = function(widget, checked)
                ConditionsHUD:changeVisibilityInBar(condition:getId(), checked)
            end
            local visibleBar = ConditionsHUD.settings.visibleBar[condition:getId()]
            if visibleBar == nil then
                visibleBar = condition:isVisibleBar()
            end
            condition:setVisibleBar(visibleBar)
            widget.showInBarCheckBox:setChecked(visibleBar)

            widget.bgcolor = i % 2 == 0 and "#414141" or "#484848"
            widget:setBackgroundColor(widget.bgcolor)
            ConditionsHUD.widgets[condition:getId()] = widget

            if i == 1 then
                ConditionsHUD:onFocusChanged(ConditionsHUD.selectedWidget, true)
                ConditionsHUD.selectedWidget = widget
            end

            widget.onClick = function() ConditionsHUD:onFocusChanged(widget, widget:isFocused()) end

            g_client.addHudConfig(condition:getId(), condition:getPath())
        end
    end

    syncStatusIconBarHudMaster(m_settings.getOption('showInHudCheckBox'))
    refreshStatusIconBar()
end

function ConditionsHUD:startInventoryPanel(inventoryPanel)
    for i, condition in ipairs(ConditionsHUD.specialConditionsOrder) do
        local widget = g_ui.createWidget('ConditionWidget', inventoryPanel)
        widget:setId(condition:getId())
        widget:setTooltip(condition:getTooltipBar())
        widget:setImageSource(condition:getIcon())
        widget:setVisible(false)

        ConditionsHUD.inventoryBar[condition:getId()] = widget
    end
end

function ConditionsHUD:startTopPanel(panel)
    ConditionsHUD.topbarWidgets = {}

    panel:destroyChildren()
    for i, condition in ipairs(ConditionsHUD.specialConditionsOrder) do
        local widget = g_ui.createWidget('ConditionWidget', panel)
        widget:setId(condition:getId())
        widget:setTooltip(condition:getTooltipBar())
        widget:setImageSource(condition:getIcon())
        widget:setVisible(ConditionsHUD.actives[condition:getId()] and condition:isVisibleBar())

        ConditionsHUD.topbarWidgets[condition:getId()] = widget
    end
end

function ConditionsHUD:reset()
    ConditionsHUD.specialConditionsOrder = {}
    local localPlayer = g_game.getLocalPlayer()
    for _, condition in ipairs(ConditionsHUD.actives) do
        if localPlayer then
            ConditionsHUD:removeHUDCondition(localPlayer, condition:getId())
        end
    end
    ConditionsHUD.actives = {}
    g_client.clearHudConfigs()
    ConditionsHUD.hud = {}
    ConditionsHUD.selectedWidget = nil

    for i = 1, #widgets do
        local widget = widgets[i]
        local dataset = {
            internalId = i,
            icon = widget.icon,
            path = widget.path,
            name = widget.name,
            id = widget.id,
            tooltipBar = widget.tooltipBar,
            tooltip = widget.tooltip,
            visibleHud = widget.visibleHud,
            visibleBar = widget.visibleBar
        }
        local specialconditionhud = SpecialConditionHUD:new(dataset)
        ConditionsHUD.hud[specialconditionhud:getId()] = specialconditionhud
        ConditionsHUD.specialConditionsOrder[i] = specialconditionhud
    end

    ConditionsHUD:updateOrder(true)
end

function ConditionsHUD:changeVisibilityInHud(id, visible)
    local condition = ConditionsHUD:getSpecialConditionById(id)
    if not condition then
        return
    end

    condition:setVisibleHud(visible)
    ConditionsHUD.settings.visibleHud[id] = visible
    syncStatusIconBarHudVisibility(id, visible)
    -- notifier
    if visible and ConditionsHUD.actives[condition:getId()] then
        -- if condition is active, add it to the hud
        local localPlayer = g_game.getLocalPlayer()
        if localPlayer then
            if id == Icons[PlayerStates.Swords].id then
                local conditionPz = ConditionsHUD:getSpecialConditionById(Icons[PlayerStates.Pz].id)
                local conditionPzBlock = ConditionsHUD:getSpecialConditionById(Icons[PlayerStates.PzBlock].id)
                -- if condition is Pz or PzBlock, we need to check if they are already active
                -- and if they are visible in the hud
                -- if they are, we don't need to add the condition again
                -- this is to avoid adding the condition twice in the hud
                if ConditionsHUD.actives[conditionPz:getId()] or ConditionsHUD.actives[conditionPzBlock:getId()] then
                    ConditionsHUD:removeSwordBattle(true, false)
                    refreshStatusIconBar()
                    return
                end
            end

            ConditionsHUD:addHUDCondition(localPlayer, condition:getId())
        end
    else
        -- if condition is not active, remove it from the hud
        local localPlayer = g_game.getLocalPlayer()
        if localPlayer then
            ConditionsHUD:removeHUDCondition(localPlayer, condition:getId())
        end
    end

    refreshStatusIconBar()
end

function ConditionsHUD:changeVisibilityInBar(id, visible)
    local condition = ConditionsHUD:getSpecialConditionById(id)
    if not condition then
        return
    end

    condition:setVisibleBar(visible)
    ConditionsHUD.settings.visibleBar[id] = visible
    local removeNormalBattle = false
    -- notifier
    if visible and ConditionsHUD.actives[condition:getId()] then
        if id == Icons[PlayerStates.Swords].id then
            local conditionPz = ConditionsHUD:getSpecialConditionById(Icons[PlayerStates.Pz].id)
            local conditionPzBlock = ConditionsHUD:getSpecialConditionById(Icons[PlayerStates.PzBlock].id)
            -- if condition is Pz or PzBlock, we need to check if they are already active
            -- and if they are visible in the hud
            -- if they are, we don't need to add the condition again
            -- this is to avoid adding the condition twice in the hud
            if ConditionsHUD.actives[conditionPz:getId()] or ConditionsHUD.actives[conditionPzBlock:getId()] then
                ConditionsHUD:removeSwordBattle(false, true)
                return
            end
        end


        -- if condition is active, add it to the inventory bar
        local widget = ConditionsHUD.inventoryBar[condition:getId()]
        if widget then
            widget:setVisible(true)
        end
        local widget = ConditionsHUD.topbarWidgets[condition:getId()]
        if widget then
            widget:setVisible(true)
        end

        if condition:getId() == Icons[PlayerStates.PzBlock].id or condition:getId() == Icons[PlayerStates.Pz].id then
            -- this is a special case, we need to remove the normal battle condition
            removeNormalBattle = true
        end

    else
        -- if condition is not active, remove it from the inventory bar
        local widget = ConditionsHUD.inventoryBar[condition:getId()]
        if widget then
            widget:setVisible(false)
        end
        local widget = ConditionsHUD.topbarWidgets[condition:getId()]
        if widget then
            widget:setVisible(false)
        end
    end

    if visible and removeNormalBattle then
        ConditionsHUD:removeSwordBattle(false, true)
    end

    refreshStatusIconBar()
end

function ConditionsHUD:getSpecialConditionById(id)
    local newpath = ''
    local tooltip = ''
    local suffix = id:match("^condition_curse([iv]*)$")
    if suffix then
        id = 'condition_curse'
        local romanToImage = {
            i    = "/images/arcs/conditions/player-state-flags-21",
            ii   = "/images/arcs/conditions/player-state-flags-22",
            iii  = "/images/arcs/conditions/player-state-flags-23",
            iv   = "/images/arcs/conditions/player-state-flags-24",
            v    = "/images/arcs/conditions/player-state-flags-25",
        }

        local tooltipMessage = {
            i    = Icons[PlayerStates.CurseI].tooltip,
            ii   = Icons[PlayerStates.CurseII].tooltip,
            iii  = Icons[PlayerStates.CurseIII].tooltip,
            iv   = Icons[PlayerStates.CurseIV].tooltip,
            v    = Icons[PlayerStates.CurseV].tooltip,
        }

        newpath = romanToImage[suffix]
        tooltip = tooltipMessage[suffix]
    end

    suffix = id:match("^condition_taints(.+)$")
    if suffix then
        id = "condition_taints"

        local romanToImage = {
            i    = "/images/arcs/conditions/player-state-flags-rotten-blood-00",
            ii   = "/images/arcs/conditions/player-state-flags-rotten-blood-01",
            iii  = "/images/arcs/conditions/player-state-flags-rotten-blood-02",
            iv   = "/images/arcs/conditions/player-state-flags-rotten-blood-03",
            v    = "/images/arcs/conditions/player-state-flags-rotten-blood-04",
            vi   = "/images/arcs/conditions/player-state-flags-rotten-blood-05",
            vii  = "/images/arcs/conditions/player-state-flags-rotten-blood-06",
            viii = "/images/arcs/conditions/player-state-flags-rotten-blood-07",
            ix   = "/images/arcs/conditions/player-state-flags-rotten-blood-08",
        }

        local tooltipMessage = {
            i    = TaintsDescriptions[1],
            ii   = TaintsDescriptions[2],
            iii  = TaintsDescriptions[3],
            iv   = TaintsDescriptions[4],
            v    = TaintsDescriptions[5],
            vi   = TaintsDescriptions[6],
            vii  = TaintsDescriptions[7],
            viii = TaintsDescriptions[8],
            ix   = TaintsDescriptions[9],
        }

        newpath = romanToImage[suffix]
        tooltip = tooltipMessage[suffix]
    end

    if id == Icons[PlayerStates.ManaShield].id then
        id = Icons[PlayerStates.NewMagicShield].id
    end

    for conditionId, condition in pairs(ConditionsHUD.hud) do
        if conditionId == id then
            if newpath ~= '' then
                condition:setPath(newpath)
                g_client.updateHudPath(condition:getId(), newpath)

                local inventoryBar = ConditionsHUD.inventoryBar[condition:getId()]
                if inventoryBar then
                    inventoryBar:setImageSource(newpath)
                end
                local topbarWidget = ConditionsHUD.topbarWidgets[condition:getId()]
                if topbarWidget then
                    topbarWidget:setImageSource(newpath)
                end
            end

            if tooltip ~= '' then
                condition:setTooltipBar(tooltip)
            end

            return condition
        end
    end
end

function ConditionsHUD:setShowInHudEnabled(value)
    local localPlayer = g_game.getLocalPlayer()
    syncStatusIconBarHudMaster(value)

    local removeNormalBattle = false
    for _, condition in pairs(ConditionsHUD.hud) do
        local widget = ConditionsHUD.widgets[condition:getId()]
        if widget then
            widget.showInHudCheckBox:setEnabled(value)

            if not value then
                -- if we disable the checkbox, we also remove the condition from the hud
                if localPlayer then
                    ConditionsHUD:removeHUDCondition(localPlayer, condition:getId())
                end
            else
                -- if we enable the checkbox, we add the condition to the hud if it is active
                if ConditionsHUD.actives[condition:getId()] and condition:isVisibleHud() and localPlayer then
                    ConditionsHUD:addHUDCondition(localPlayer, condition:getId())

                    if condition:getId() == Icons[PlayerStates.PzBlock].id or condition:getId() == Icons[PlayerStates.Pz].id then
                        -- this is a special case, we need to remove the normal battle condition
                        removeNormalBattle = true
                    end
                end
            end
        end
    end

    if value and removeNormalBattle then
        ConditionsHUD:removeSwordBattle(true, false)
    end

    refreshStatusIconBar()
end

function ConditionsHUD:setShowInBarEnabled(value)
    for _, condition in pairs(ConditionsHUD.hud) do
        local widget = ConditionsHUD.widgets[condition:getId()]
        if widget then
            widget.showInBarCheckBox:setEnabled(value)
        end
    end

    -- disable inventory bar
    if not value then
        for id, widget in pairs(ConditionsHUD.inventoryBar) do
            widget:setVisible(false)
        end

        for id, widget in pairs(ConditionsHUD.topbarWidgets) do
            widget:setVisible(false)
        end
    end

    if value then
        local removeNormalBattle = false
        -- update visibility of topbar widgets
        for _, condition in pairs(ConditionsHUD.specialConditionsOrder) do
            local widget = ConditionsHUD.topbarWidgets[condition:getId()]
            if widget and ConditionsHUD.actives[condition:getId()] then
                widget:setVisible(condition:isVisibleBar())
                if condition:getId() == Icons[PlayerStates.PzBlock].id or condition:getId() == Icons[PlayerStates.Pz].id then
                    -- this is a special case, we need to remove the normal battle condition
                    removeNormalBattle = true
                end
            end
        end

        -- update visibility of inventory bar widgets
        for _, condition in pairs(ConditionsHUD.specialConditionsOrder) do
            local widget = ConditionsHUD.inventoryBar[condition:getId()]
            if widget and ConditionsHUD.actives[condition:getId()] then
                widget:setVisible(condition:isVisibleBar())
                if condition:getId() == Icons[PlayerStates.PzBlock].id or condition:getId() == Icons[PlayerStates.Pz].id then
                    -- this is a special case, we need to remove the normal battle condition
                    removeNormalBattle = true
                end
            end
        end

        if removeNormalBattle then
            -- remove normal battle condition
            ConditionsHUD:removeSwordBattle(false, true)
        end
    end

    refreshStatusIconBar()
end

function ConditionsHUD:updateOrder(reset)
    g_client.clearHudConfigs()
    for i, condition in ipairs(ConditionsHUD.specialConditionsOrder) do
        local widget = ConditionsHUD.widgets[condition:getId()]
        if widget then
            widget:getParent():moveChildToIndex(widget, condition:getIndex())
            widget.bgcolor = i % 2 == 0 and "#414141" or "#484848"
            widget:setBackgroundColor(widget.bgcolor)
            if reset then
                widget.showInHudCheckBox:setChecked(condition.visibleHud)
                widget.showInBarCheckBox:setChecked(condition.visibleBar)
            end

            if ConditionsHUD.selectedWidget == widget then
                ConditionsHUD:onFocusChanged(widget, true)
            end

            g_client.addHudConfig(condition:getId(), condition:getPath())
        end

        local inventoryWidget = ConditionsHUD.inventoryBar[condition:getId()]
        if inventoryWidget then
            inventoryWidget:getParent():moveChildToIndex(inventoryWidget, condition:getIndex())
        end
        local topbarWidget = ConditionsHUD.topbarWidgets[condition:getId()]
        if topbarWidget then
            topbarWidget:getParent():moveChildToIndex(topbarWidget, condition:getIndex())
        end
    end

    refreshStatusIconBar()
end

function ConditionsHUD:notifierStatesChange(localPlayer, now, old, statesList, removedStates)
    if type(statesList) ~= "table" then
        statesList = {}
    end
    if type(removedStates) ~= "table" then
        removedStates = {}
    end

    local function buildStatesList(states)
        local list = {}
        if type(states) ~= "number" then
            return list
        end

        for state, _ in pairs(Icons) do
            if type(state) == "number" and bit.band(states, state) ~= 0 then
                table.insert(list, state)
            end
        end
        return list
    end

    if next(statesList) == nil then
        statesList = buildStatesList(now)
    end

    if next(removedStates) == nil and type(now) == "number" and type(old) == "number" then
        for state, _ in pairs(Icons) do
            if type(state) == "number" and bit.band(old, state) ~= 0 and bit.band(now, state) == 0 then
                table.insert(removedStates, state)
            end
        end
    end

    local function getConditionByState(state)
        local icon = Icons[state]
        if not icon then
            return nil
        end
        return ConditionsHUD:getSpecialConditionById(icon.id)
    end

    local function hideCondition(specialCondition)
        local conditionId = specialCondition:getId()
        ConditionsHUD:removeHUDCondition(localPlayer, conditionId)
        ConditionsHUD.actives[conditionId] = nil

        local inventoryWidget = ConditionsHUD.inventoryBar[conditionId]
        if inventoryWidget then
            inventoryWidget:setVisible(false)
        end
        local topbarWidget = ConditionsHUD.topbarWidgets[conditionId]
        if topbarWidget then
            topbarWidget:setVisible(false)
        end
    end

    local function showCondition(specialCondition)
        local conditionId = specialCondition:getId()
        ConditionsHUD.actives[conditionId] = true

        if specialCondition:isVisibleHud() and m_settings.getOption('showInHudCheckBox') then
            ConditionsHUD:addHUDCondition(localPlayer, conditionId)
        end

        if specialCondition:isVisibleBar() and m_settings.getOption('showInBarCheckBox') then
            local inventoryWidget = ConditionsHUD.inventoryBar[conditionId]
            if inventoryWidget then
                inventoryWidget:setVisible(true)
                inventoryWidget:setTooltip(specialCondition:getTooltipBar())
            end
            local topbarWidget = ConditionsHUD.topbarWidgets[conditionId]
            if topbarWidget then
                topbarWidget:setVisible(true)
                topbarWidget:setTooltip(specialCondition:getTooltipBar())
            end
        end
    end

    for _, state in pairs(removedStates) do
        local specialCondition = getConditionByState(state)
        if specialCondition then
            hideCondition(specialCondition)
        end
    end

    local removeNormalBattle = false
    local hasSwordBattle = false
    for _, state in pairs(statesList) do
        if state == PlayerStates.Paralyze and localPlayer then
            localPlayer:setPreWalkLockedDelay(g_clock.millis() + 2000)
        end

        local specialCondition = getConditionByState(state)
        if specialCondition then
            local conditionId = specialCondition:getId()
            if conditionId == Icons[PlayerStates.PzBlock].id or conditionId == Icons[PlayerStates.Pz].id then
                removeNormalBattle = true
            elseif conditionId == Icons[PlayerStates.Swords].id then
                hasSwordBattle = true
            end

            showCondition(specialCondition)
        end
    end

    if removeNormalBattle then
        ConditionsHUD:removeSwordBattle(true, true)
    elseif hasSwordBattle then
        local swordCondition = ConditionsHUD:getSpecialConditionById(Icons[PlayerStates.Swords].id)
        if swordCondition then
            showCondition(swordCondition)
        end
    end
end

function ConditionsHUD:notifierHungryChange(localPlayer, remove)
    local specialCondition = ConditionsHUD:getSpecialConditionById(Icons[PlayerStates.Hungry].id)
    if not specialCondition then
        return
    end

    local inventoryWidget = ConditionsHUD.inventoryBar[specialCondition:getId()]
    local topbarWidget = ConditionsHUD.topbarWidgets[specialCondition:getId()]
    if remove then
        -- remove condition
        ConditionsHUD:removeHUDCondition(localPlayer, specialCondition:getId())
        ConditionsHUD.actives[specialCondition:getId()] = nil
        if inventoryWidget then
            inventoryWidget:setVisible(false)
        end

        if topbarWidget then
            topbarWidget:setVisible(false)
        end
    else
        -- add condition
        ConditionsHUD.actives[specialCondition:getId()] = true
        if specialCondition:isVisibleHud() and m_settings.getOption('showInHudCheckBox') then
            ConditionsHUD:addHUDCondition(localPlayer, specialCondition:getId())
        end

        if specialCondition:isVisibleBar() and m_settings.getOption('showInBarCheckBox') then
            if inventoryWidget then
                inventoryWidget:setVisible(true)
                inventoryWidget:setTooltip(specialCondition:getTooltipBar())
                inventoryWidget:setImageSource(specialCondition:getIcon())
            end

            if topbarWidget then
                topbarWidget:setVisible(true)
                topbarWidget:setTooltip(specialCondition:getTooltipBar())
                topbarWidget:setImageSource(specialCondition:getIcon())
            end
        end
    end

    refreshStatusIconBar()
end

function ConditionsHUD:notifierRestingAreaState(zone, state, message)
    ConditionsHUD.zone = zone
    ConditionsHUD.state = state
    ConditionsHUD.message = message
    local localPlayer = g_game.getLocalPlayer()
    if not localPlayer then
        return
    end

    local specialCondition = ConditionsHUD:getSpecialConditionById('condition_restingarea')
    if not specialCondition then
        return
    end

    local inventoryWidget = ConditionsHUD.inventoryBar[specialCondition:getId()]
    local topbarWidget = ConditionsHUD.topbarWidgets[specialCondition:getId()]
    if zone == 0 then
        -- remove condition
        ConditionsHUD:removeHUDCondition(localPlayer, specialCondition:getId())
        ConditionsHUD.actives[specialCondition:getId()] = nil
        inventoryWidget:setVisible(false)
        if topbarWidget then
            topbarWidget:setVisible(false)
        end
    else
        -- add condition
        ConditionsHUD.actives[specialCondition:getId()] = true
        if state == 2 then
            specialCondition:setPath('/images/arcs/conditions/player-state-flags-client-00')
            inventoryWidget:setImageSource('/images/game/states/28')
            if topbarWidget then
                topbarWidget:setImageSource('/images/game/states/28')
            end
        else
            specialCondition:setPath('/images/arcs/conditions/player-state-flags-client-01')
            if topbarWidget then
                topbarWidget:setImageSource('/images/game/states/29')
            end
            inventoryWidget:setImageSource('/images/game/states/29')
        end
        g_client.updateHudPath(specialCondition:getId(), specialCondition:getPath())

        specialCondition:setTooltipBar(message or tr('You are in a resting area'))

        if specialCondition:isVisibleHud() and m_settings.getOption('showInHudCheckBox') then
            ConditionsHUD:addHUDCondition(localPlayer, specialCondition:getId())
        end

        if specialCondition:isVisibleBar() and m_settings.getOption('showInBarCheckBox') then
            inventoryWidget:setVisible(true)
            inventoryWidget:setTooltip(specialCondition:getTooltipBar())

            if topbarWidget then
                topbarWidget:setVisible(true)
                topbarWidget:setTooltip(specialCondition:getTooltipBar())
            end
        end
    end
end

function ConditionsHUD:notifierTaintsChange(localPlayer, now, old)
    local traints = {
        [1] = 'condition_taintsi',
        [2] = 'condition_taintsii',
        [3] = 'condition_taintsiii',
        [4] = 'condition_taintsiv',
        [5] = 'condition_taintsv',
        [6] = 'condition_taintsvi',
        [7] = 'condition_taintsvii',
        [8] = 'condition_taintsviii',
        [9] = 'condition_taintsix'
    }


    local specialCondition = ConditionsHUD:getSpecialConditionById(traints[now] or 'condition_taints')
    if not specialCondition then
        return
    end

    local inventoryWidget = ConditionsHUD.inventoryBar[specialCondition:getId()]
    local topbarWidget = ConditionsHUD.topbarWidgets[specialCondition:getId()]
    if now ~= 0 then
        -- add
        ConditionsHUD.actives[specialCondition:getId()] = true
        if specialCondition:isVisibleHud() and m_settings.getOption('showInHudCheckBox') then
            ConditionsHUD:addHUDCondition(localPlayer, specialCondition:getId())
        end

        if specialCondition:isVisibleBar() and m_settings.getOption('showInBarCheckBox') then
            inventoryWidget:setVisible(true)
            inventoryWidget:setTooltip(specialCondition:getTooltipBar())
            inventoryWidget:setTooltipFont("Verdana Bold-11px-wheel")

            if topbarWidget then
                topbarWidget:setVisible(true)
                topbarWidget:setTooltip(specialCondition:getTooltipBar())
                topbarWidget:setTooltipFont("Verdana Bold-11px-wheel")
            end
        end
    else
        -- remove condition
        ConditionsHUD:removeHUDCondition(localPlayer, specialCondition:getId())
        ConditionsHUD.actives[specialCondition:getId()] = nil
        inventoryWidget:setVisible(false)

        if topbarWidget then
            topbarWidget:setVisible(false)
        end
    end
end

function ConditionsHUD:notifierSkullChange(localPlayer, skull)
    local skullsName = {
        [SkullGreen] = 'skullgreen',
        [SkullWhite] = 'skullwhite',
        [SkullRed] = 'skullred',
        [SkullBlack] = 'skullblack',
        [SkullOrange] = 'skullorange',
        [SkullYellow] = 'skullyellow'
    }

    -- remove all skulls
    for skullId, skullName in pairs(skullsName) do
        local specialCondition = ConditionsHUD:getSpecialConditionById(skullName)
        if specialCondition then
            local inventoryWidget = ConditionsHUD.inventoryBar[skullName]
            local topbarWidget = ConditionsHUD.topbarWidgets[skullName]
            if inventoryWidget then
                inventoryWidget:setVisible(false)
            end
            if topbarWidget then
                topbarWidget:setVisible(false)
            end

            if localPlayer.removeHUDCondition then
                ConditionsHUD:removeHUDCondition(localPlayer, specialCondition:getId())
            end
            ConditionsHUD.actives[specialCondition:getId()] = nil
        end
    end

    if skull == SkullNone then
        -- no skull, nothing to do
        return
    end

    local specialCondition = ConditionsHUD:getSpecialConditionById(skullsName[skull])
    if not specialCondition then
        return
    end

    local inventoryWidget = ConditionsHUD.inventoryBar[specialCondition:getId()]
    local topbarWidget = ConditionsHUD.topbarWidgets[specialCondition:getId()]
    if ConditionsHUD.actives[specialCondition:getId()] then
        -- condition already active, remove it
        ConditionsHUD:removeHUDCondition(localPlayer, specialCondition:getId())
        ConditionsHUD.actives[specialCondition:getId()] = nil
        inventoryWidget:setVisible(false)

        if topbarWidget then
            topbarWidget:setVisible(false)
        end
    else
        -- condition not active, add it
        ConditionsHUD.actives[specialCondition:getId()] = true
        if specialCondition:isVisibleHud() and m_settings.getOption('showInHudCheckBox') then
            ConditionsHUD:addHUDCondition(localPlayer, specialCondition:getId())
        end

        if specialCondition:isVisibleBar() and m_settings.getOption('showInBarCheckBox') then
            inventoryWidget:setVisible(true)
            inventoryWidget:setTooltip(specialCondition:getTooltipBar())
            inventoryWidget:setImageSource(specialCondition:getIcon())

            if topbarWidget then
                topbarWidget:setVisible(true)
                topbarWidget:setTooltip(specialCondition:getTooltipBar())
                topbarWidget:setImageSource(specialCondition:getIcon())
            end
        end
    end
end

function ConditionsHUD:notifierEmblemChange(creature, emblem)
    local localPlayer = g_game.getLocalPlayer()
    if not localPlayer then
        return
    end

    if creature ~= localPlayer then
        return
    end

    local specialCondition = ConditionsHUD:getSpecialConditionById('emblem')
    if not specialCondition then
        return
    end

    local inventoryWidget = ConditionsHUD.inventoryBar[specialCondition:getId()]
    local topbarWidget = ConditionsHUD.topbarWidgets[specialCondition:getId()]

    if not isEmblemActive(emblem) then
        -- remove condition
        if localPlayer.removeHUDCondition then
            ConditionsHUD:removeHUDCondition(localPlayer, specialCondition:getId())
        end
        ConditionsHUD.actives[specialCondition:getId()] = nil
        if inventoryWidget then
            inventoryWidget:setVisible(false)
        end
        if topbarWidget then
            topbarWidget:setVisible(false)
        end
    else
        -- add condition
        applyEmblemStyle(specialCondition, emblem)
        ConditionsHUD.actives[specialCondition:getId()] = true
        if specialCondition:isVisibleHud() and m_settings.getOption('showInHudCheckBox') then
            ConditionsHUD:addHUDCondition(localPlayer, specialCondition:getId())
        end

        if specialCondition:isVisibleBar() and m_settings.getOption('showInBarCheckBox') then
            if inventoryWidget then
                inventoryWidget:setVisible(true)
                inventoryWidget:setTooltip(specialCondition:getTooltipBar())
                inventoryWidget:setImageSource(specialCondition:getIcon())
            end
            if topbarWidget then
                topbarWidget:setVisible(true)
                topbarWidget:setTooltip(specialCondition:getTooltipBar())
                topbarWidget:setImageSource(specialCondition:getIcon())
            end
        end
    end

    refreshStatusIconBar()
end

function ConditionsHUD:moveItem(tbl, fromIndex, direction)
    local toIndex = fromIndex + direction

    if toIndex < 1 or toIndex > #ConditionsHUD.specialConditionsOrder then
        return
    end

    ConditionsHUD.specialConditionsOrder[fromIndex], ConditionsHUD.specialConditionsOrder[toIndex] = ConditionsHUD.specialConditionsOrder[toIndex], ConditionsHUD.specialConditionsOrder[fromIndex]
end


function ConditionsHUD:onFocusChanged(widget, focused)
    if ConditionsHUD.selectedWidget then
        ConditionsHUD.selectedWidget:setBackgroundColor(ConditionsHUD.selectedWidget.bgcolor)
    end

    if widget then
        ConditionsHUD.selectedWidget = widget
        ConditionsHUD.selectedWidget:setBackgroundColor("#585858")

        local hudWindow = GameOptions:getLoadedWindow("hud")
        if not hudWindow then
            return
        end

        local upButton = hudWindow:recursiveGetChildById('upButton')
        local downButton = hudWindow:recursiveGetChildById('downButton')
        local currentIndex = ConditionsHUD:getIndexById(widget:getId())
        if not currentIndex then
            return
        end

        upButton:setEnabled(currentIndex > 1)
        downButton:setEnabled(currentIndex < #ConditionsHUD.specialConditionsOrder)

        downButton.onClick = function()
            ConditionsHUD:moveItem(ConditionsHUD.specialConditionsOrder, currentIndex, 1)
            ConditionsHUD:updateOrder()
        end

        upButton.onClick = function()
            ConditionsHUD:moveItem(ConditionsHUD.specialConditionsOrder, currentIndex, -1)
            ConditionsHUD:updateOrder()
        end
    end
end

function ConditionsHUD:getIndexById(id)
    local s_condition = ConditionsHUD:getSpecialConditionById(id)
    for i, condition in ipairs(ConditionsHUD.specialConditionsOrder) do
        if condition:getId() == s_condition:getId() then
            return i
        end
    end
    return nil
end

function ConditionsHUD:onGameStart()
    ConditionsHUD.actives = {}
    addEvent(function()
        local localPlayer = g_game.getLocalPlayer()
        if not localPlayer then
            return
        end
        
        local statesList = {}
        if localPlayer.getStatesList then
            statesList = localPlayer:getStatesList() or {}
        end
        
        ConditionsHUD:notifierStatesChange(localPlayer, localPlayer:getStates(), 0, statesList, {})
        ConditionsHUD:notifierTaintsChange(localPlayer, localPlayer:getTaints(), 0)
        ConditionsHUD:notifierSkullChange(localPlayer, localPlayer:getSkull())
        ConditionsHUD:notifierRestingAreaState(ConditionsHUD.zone, ConditionsHUD.state, ConditionsHUD.message)
        ConditionsHUD:notifierHungryChange(localPlayer, localPlayer:getRegenerationTime() > 0)
        ConditionsHUD:notifierEmblemChange(localPlayer, localPlayer:getEmblem())
        refreshStatusIconBar()
    end)
end

function ConditionsHUD:onGameEnd()
    local localPlayer = g_game.getLocalPlayer()
    if not localPlayer then
        return
    end
    ConditionsHUD.actives = {}
    ConditionsHUD:notifierStatesChange(localPlayer, 0, 0, {}, localPlayer:getStatesList())
    ConditionsHUD:save()
end

function ConditionsHUD:removeSwordBattle(inHud, inBar)
    local specialCondition = ConditionsHUD:getSpecialConditionById(Icons[PlayerStates.Swords].id)
    if specialCondition and inHud then
        local localPlayer = g_game.getLocalPlayer()
        if localPlayer then
            ConditionsHUD:removeHUDCondition(localPlayer, specialCondition:getId())
        end
    end

    if not inBar then
        return
    end

    local inventoryWidget = ConditionsHUD.inventoryBar[Icons[PlayerStates.Swords].id]
    if inventoryWidget then
        inventoryWidget:setVisible(false)
    end
    local topbarWidget = ConditionsHUD.topbarWidgets[Icons[PlayerStates.Swords].id]
    if topbarWidget then
        topbarWidget:setVisible(false)
    end
end
