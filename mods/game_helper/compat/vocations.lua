-- compat/vocations.lua — Amon VocationsClient shim (data-only extract)
--
-- Ported from Amon gamelib/creature.lua. Only the VocationsClient lookup table
-- is provided: Astra's own gamelib/creature.lua ALREADY defines the
-- Creature:isKnight/isDruid/isSorcerer/isPaladin/isMonk methods, so re-defining
-- them here would shadow/duplicate the engine module. The helper references the
-- VocationsClient table directly (per-vocation healing/haste logic) but uses the
-- engine's vocation predicate methods.
--
-- Guarded with `or` so it never clobbers an existing VocationsClient and stays
-- idempotent across reloads.

VocationsClient = VocationsClient or {
    None = 0,
    Knight = 1,
    Paladin = 2,
    Sorcerer = 3,
    Druid = 4,
    Monk = 5,

    EliteKnight = 11,
    RoyalPaladin = 12,
    MasterSorcerer = 13,
    ElderDruid = 14,
    ExaltedMonk = 15,
}

return VocationsClient
