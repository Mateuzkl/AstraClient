-- compat/items.lua — Amon ItemsDatabase shim (data-only extract)
--
-- The Amon helper only consumes ItemsDatabase.RARITY_NAMES and
-- ItemsDatabase.RARITY_COLORS (always guarded with `ItemsDatabase and ...`).
-- The full Amon gamelib/items.lua additionally runs rarity/ancient-chest GLOW
-- SHADER initialisation at load time (g_shaders.createFragmentShaderFromCode +
-- Item.setGlobalRarityGlow), which would collide with Astra's own rarity-glow
-- pipeline. So we port ONLY the two pure-data tables the port needs — no engine
-- side effects, no external deps.
--
-- Guarded with `or` so this never clobbers a real ItemsDatabase that Astra might
-- introduce later, and stays idempotent across reloads.

ItemsDatabase = ItemsDatabase or {}

-- ASCII-only names: OTClient bitmap fonts mangle accented/Unicode glyphs.
-- Index 0 = "no rarity" (a plain item).
ItemsDatabase.RARITY_NAMES = ItemsDatabase.RARITY_NAMES or {
    [0] = "No rarity",
    [1] = "Uncommon",
    [2] = "Rare",
    [3] = "Epic",
    [4] = "Legendary",
    [5] = "Mythical",
}

ItemsDatabase.RARITY_COLORS = ItemsDatabase.RARITY_COLORS or {
    [0] = "#c0c0c0",
    [1] = "#5d8a3c",
    [2] = "#3c6ea5",
    [3] = "#8a3ca5",
    [4] = "#c89000",
    [5] = "#c83c3c",
}

return ItemsDatabase
