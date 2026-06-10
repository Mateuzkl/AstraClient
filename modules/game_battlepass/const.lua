MissionsDisplacement = {
    1, 2, 14, 15, -- First week [2 de 100 pontos e 2 de 200 pontos]
    3, 4, 16, 17, -- Second week [2 de 100 pontos e 2 de 200 pontos]
    5, 6, 7, 18, 19, 20, -- Third week [3 de 100 pontos, 2 de 200 pontos e 1 de 300 pontos]
    8, 9, 10, 21, 22, 23, -- Fourth week [2 de 100 pontos, 3 de 200 pontos e 1 de 300 pontos]
    11, 12, 13, 24, 25, 26 -- Fifth week [2 de 100 pontos, 2 de 200 pontos e 2 de 300 pontos]
}

MissionTypesOrder = {
    "bronze", "bronze", "silver", "silver", -- First week
    "bronze", "bronze", "silver", "silver", -- Second week
    "bronze", "bronze", "bronze", "silver", "silver", "gold", -- Third week
    "bronze", "bronze", "silver", "silver", "silver", "gold", -- Fourth week
    "bronze", "bronze", "silver", "silver", "gold", "gold" -- Fifth week
}

MissionRankIcons = {
    [100] = "bronze-icon",
    [150] = "silver-icon",
    [200] = "silver-icon",
    [300] = "gold-icon",
}

BattleRewardTypes = {
    "Item",             -- índice 1
    "Random Item",      -- índice 2
    "Random Mount",     -- índice 3
    "Exercise Item",    -- índice 4
    "Double Skill",     -- índice 5
    "Level",            -- índice 6
    "Prey",             -- índice 7
    "Exp Boost",        -- índice 8
    "Regen",            -- índice 9
    "Overload Forge",   -- índice 10
    "Instant Reward",   -- índice 11
    "Boosted Exercise", -- índice 12
    "Charms",           -- índice 13
    "Outfit",           -- índice 14
    "Extra Skill",      -- índice 15
    "Elemental Outfit", -- índice 16
    "Multi Items",      -- índice 17
    "Choosable Item",   -- índice 18
}

RewardWidgetOrder = {
    "rewardSlot4", "rewardSlot2", "rewardSlot0", "rewardSlot1", "rewardSlot3",
    "rewardSlot5", "rewardSlot10", "rewardSlot8", "rewardSlot6", "rewardSlot7",
    "rewardSlot9", "rewardSlot11"
}

RewardPositions = {
    [0] = {stepsTo = 0, scrollPosition = 0},
    [1] = {stepsTo = 8, scrollPosition = 107, positions = {premium = {marginLeft = 430, marginTop = 60}}},
    [2] = {stepsTo = 6, scrollPosition = 292, positions = {premium = {marginLeft = 622, marginTop = 60}}},
    [3] = {stepsTo = 6, scrollPosition = 480, positions = {premium = {marginLeft = 808, marginTop = 55}, free = {marginLeft = 808, marginTop = 310}}},
    [4] = {stepsTo = 14, scrollPosition = 930, positions = {premium = {marginLeft = 1255, marginTop = 55}}},
    [5] = {stepsTo = 7, scrollPosition = 1150, positions = {premium = {marginLeft = 1480, marginTop = 55}}},
    [6] = {stepsTo = 7, scrollPosition = 1380, positions = {premium = {marginLeft = 1705, marginTop = 55}, free = {marginLeft = 1705, marginTop = 275}}},
    [7] = {stepsTo = 11, scrollPosition = 1730, positions = {premium = {marginLeft = 2065, marginTop = 60}}},
    [8] = {stepsTo = 6, scrollPosition = 1930, positions = {premium = {marginLeft = 2255, marginTop = 60}}},
    [9] = {stepsTo = 9, scrollPosition = 2210, positions = {premium = {marginLeft = 2541, marginTop = 60}, free = {marginLeft = 2541, marginTop = 310}}},
    [10] = {stepsTo = 9, scrollPosition = 2500, positions = {premium = {marginLeft = 2830, marginTop = 60}}},
    [11] = {stepsTo = 6, scrollPosition = 2698, positions = {premium = {marginLeft = 3023, marginTop = 60}}},
    [12] = {stepsTo = 31, scrollPosition = 3665, positions = {premium = {marginLeft = 4010, marginTop = 55}, free = {marginLeft = 4006, marginTop = 275}}},
    [13] = {stepsTo = 8, scrollPosition = 3925, positions = {premium = {marginLeft = 4265, marginTop = 55}}},
    [14] = {stepsTo = 8, scrollPosition = 4185, positions = {premium = {marginLeft = 4520, marginTop = 55}}},
    [15] = {stepsTo = 19, scrollPosition = 4800, positions = {premium = {marginLeft = 5136, marginTop = 60}, free = {marginLeft = 5130, marginTop = 275}}},
    [16] = {stepsTo = 11, scrollPosition = 5145, positions = {premium = {marginLeft = 5486, marginTop = 60}}},
    [17] = {stepsTo = 11, scrollPosition = 5505, positions = {premium = {marginLeft = 5840, marginTop = 60}}},
    [18] = {stepsTo = 11, scrollPosition = 5820, positions = {premium = {marginLeft = 6155, marginTop = 55}, free = {marginLeft = 6155, marginTop = 275}}},
    [19] = {stepsTo = 10, scrollPosition = 6145, positions = {premium = {marginLeft = 6478, marginTop = 60}}},
    [20] = {stepsTo = 10, scrollPosition = 6460, positions = {premium = {marginLeft = 6830, marginTop = 60}}},
    [21] = {stepsTo = 11, scrollPosition = 6855, positions = {premium = {marginLeft = 7182, marginTop = 60}, free = {marginLeft = 7177, marginTop = 275}}},
    [22] = {stepsTo = 14, scrollPosition = 7300, positions = {premium = {marginLeft = 7625, marginTop = 55}}},
    [23] = {stepsTo = 5, scrollPosition = 7460, positions = {premium = {marginLeft = 7784, marginTop = 85}}},
    [24] = {stepsTo = 5, scrollPosition = 7620, positions = {premium = {marginLeft = 7945, marginTop = 55}, free = {marginLeft = 7945, marginTop = 275}}},
    [25] = {stepsTo = 22, scrollPosition = 8325, positions = {premium = {marginLeft = 8640, marginTop = 80}}},
    [26] = {stepsTo = 8, scrollPosition = 8570, positions = {premium = {marginLeft = 8895, marginTop = 80}}},
    [27] = {stepsTo = 8, scrollPosition = 8835, positions = {premium = {marginLeft = 9151, marginTop = 80}, free = {marginLeft = 9156, marginTop = 275}}},
    [28] = {stepsTo = 8, scrollPosition = 9090, positions = {premium = {marginLeft = 9406, marginTop = 80}}},
    [29] = {stepsTo = 7, scrollPosition = 9310, positions = {premium = {marginLeft = 9640, marginTop = 80}}},
    [30] = {stepsTo = 7, scrollPosition = 9530, positions = {premium = {marginLeft = 9857, marginTop = 80}, free = {marginLeft = 9862, marginTop = 275}}},
    [31] = {stepsTo = 8, scrollPosition = 9785, positions = {premium = {marginLeft = 10112, marginTop = 80}}},
    [32] = {stepsTo = 8, scrollPosition = 10045, positions = {premium = {marginLeft = 10367, marginTop = 80}}},
    [33] = {stepsTo = 8, scrollPosition = 10300, positions = {premium = {marginLeft = 10622, marginTop = 80}, free = {marginLeft = 10629, marginTop = 275}}},
    [34] = {stepsTo = 18, scrollPosition = 10880, positions = {premium = {marginLeft = 11212, marginTop = 95}}},
    [35] = {stepsTo = 8, scrollPosition = 11135, positions = {premium = {marginLeft = 11466, marginTop = 95}}},
    [36] = {stepsTo = 8, scrollPosition = 11390, positions = {premium = {marginLeft = 11722, marginTop = 95}, free = {marginLeft = 11718, marginTop = 275}}},
    [37] = {stepsTo = 27, scrollPosition = 12255, positions = {premium = {marginLeft = 12575, marginTop = 80}}},
    [38] = {stepsTo = 9, scrollPosition = 12540, positions = {premium = {marginLeft = 12861, marginTop = 80}}},
    [39] = {stepsTo = 9, scrollPosition = 12830, positions = {premium = {marginLeft = 13150, marginTop = 80}, free = {marginLeft = 13158, marginTop = 275}}},
    [40] = {stepsTo = 9, scrollPosition = 13115, positions = {premium = {marginLeft = 13439, marginTop = 80}}},
    [41] = {stepsTo = 11, scrollPosition = 13465, positions = {premium = {marginLeft = 13792, marginTop = 80}}},
    [42] = {stepsTo = 12, scrollPosition = 13850, positions = {premium = {marginLeft = 14175, marginTop = 80}, free = {marginLeft = 14180, marginTop = 275}}},
    [43] = {stepsTo = 9, scrollPosition = 14140, positions = {premium = {marginLeft = 14462, marginTop = 80}}},
    [44] = {stepsTo = 9, scrollPosition = 14425, positions = {premium = {marginLeft = 14750, marginTop = 80}}},
    [45] = {stepsTo = 9, scrollPosition = 14715, positions = {premium = {marginLeft = 15040, marginTop = 80}, free = {marginLeft = 15045, marginTop = 275}}},
    [46] = {stepsTo = 32, scrollPosition = 15740, positions = {premium = {marginLeft = 16078, marginTop = 90}}},
    [47] = {stepsTo = 8, scrollPosition = 15995, positions = {premium = {marginLeft = 16335, marginTop = 90}}},
    [48] = {stepsTo = 29, scrollPosition = 16925, positions = {premium = {marginLeft = 17256, marginTop = 87}, free = {marginLeft = 17256, marginTop = 275}}},
    [49] = {stepsTo = 4, scrollPosition = 17050, positions = {premium = {marginLeft = 17384, marginTop = 87}, free = {marginLeft = 17384, marginTop = 275}}},
    [50] = {stepsTo = 11, scrollPosition = 17278, positions = {premium = {marginLeft = 17734, marginTop = 87}, free = {marginLeft = 17734, marginTop = 245}}}
}