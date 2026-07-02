-- KoliseuClient targets a SINGLE protocol/asset era: Tibia 12.40+/15.x (client
-- version 1524, crystalserver/Canary). The old per-version feature ladder
-- (`if version >= 770/780/.../1100/1200/...`) was removed together with
-- legacy-protocol support; what remains is the fixed 1524 feature profile below.
--
-- `version` is still received because updateFeatures is wired to
-- onClientVersionChange, but it only guards the reset (version <= 0) — the enabled
-- set is constant. This list is the cumulative union of every `if version >= N`
-- block up to 1524 from the previous laddered features.lua, MINUS
-- GameMessageSizeCheck: the old code enabled it at >= 841 and then disabled it at
-- >= 1200 (the modern framing has no inner U16 message-size field), so for 1524 it
-- was effectively OFF. resetFeatures() below leaves it off, so it is simply not
-- listed here — do NOT add it back.

function init()
    connect(g_game, { onClientVersionChange = updateFeatures })
end

function terminate()
    disconnect(g_game, { onClientVersionChange = updateFeatures })
end

function updateFeatures(version)
    g_game.resetFeatures()
    if version <= 0 then
        return
    end

    -- "Ignore opacity on Special Effects" (client_settings > Effects) keeps these
    -- magic-effect ids at full opacity, ignoring the Opacity Effects slider. These
    -- are crystalserver magic-effect ids (src/utils/utils_definitions.hpp) for the
    -- special combat procs that should stay fully visible. Read by g_map at runtime.
    local specialEffects = {
        Critical = 173, -- CONST_ME_CRITICAL_DAMAGE
        Fatal    = 230, -- CONST_ME_FATAL
        Dodge    = 231, -- CONST_ME_DODGE (Ruse proc)
        Agony    = 249, -- CONST_ME_AGONY
    }
    local specialEffectIds = {}
    for _, id in pairs(specialEffects) do
        if id and id > 0 then specialEffectIds[#specialEffectIds + 1] = id end
    end
    g_map.setSpecialEffectIds(specialEffectIds)

    -- ------------------------------------------------------------------------
    -- Fixed 1524 feature profile (alphabetical; was the 770 -> 1524 version
    -- ladder). Kept sorted so the enabled set is trivial to audit against the
    -- previous features.lua.
    -- ------------------------------------------------------------------------
    g_game.enableFeature(GameAccountNames)
    g_game.enableFeature(GameAdditionalSkills)
    g_game.enableFeature(GameAdditionalVipInfo)
    g_game.enableFeature(GameAttackSeq)
    g_game.enableFeature(GameAuthenticator)
    g_game.enableFeature(GameBaseSkillU16)
    g_game.enableFeature(GameBot)
    g_game.enableFeature(GameBrowseField)
    g_game.enableFeature(GameChallengeOnLogin)
    g_game.enableFeature(GameChannelPlayerList)
    g_game.enableFeature(GameClientPing)
    g_game.enableFeature(GameClientVersion)
    g_game.enableFeature(GameContainerPagination)
    g_game.enableFeature(GameContentRevision)
    g_game.enableFeature(GameCreatureEmblems)
    g_game.enableFeature(GameCreatureIcons)
    g_game.enableFeature(GameDeathType)
    g_game.enableFeature(GameDistanceEffectU16)
    g_game.enableFeature(GameDontMergeAnimatedText) -- do not stack damage/heal numbers in a short window
    g_game.enableFeature(GameDoubleExperience)
    g_game.enableFeature(GameDoubleFreeCapacity)
    g_game.enableFeature(GameDoubleHealth)
    g_game.enableFeature(GameDoublePlayerGoodsMoney)
    g_game.enableFeature(GameDoubleSkills)
    g_game.enableFeature(GameEnhancedAnimations)
    g_game.enableFeature(GameEnvironmentEffect)
    g_game.enableFeature(GameExperienceBonus)
    g_game.enableFeature(GameExtendedOpcode)
    g_game.enableFeature(GameHideNpcNames)
    g_game.enableFeature(GameIdleAnimations)
    g_game.enableFeature(GameIngameStore)
    g_game.enableFeature(GameIngameStoreHighlights)
    g_game.enableFeature(GameIngameStoreServiceType)
    g_game.enableFeature(GameItemAnimationPhase)
    g_game.enableFeature(GameItemTierByte)
    g_game.enableFeature(GameLoginPacketEncryption)
    g_game.enableFeature(GameLoginPending)
    g_game.enableFeature(GameLooktypeU16)
    g_game.enableFeature(GameMagicEffectU16)
    g_game.enableFeature(GameMessageLevel)
    g_game.enableFeature(GameMessageStatements)
    g_game.enableFeature(GameNameOnNpcTrade)
    g_game.enableFeature(GameNewFluids)
    g_game.enableFeature(GameNewOutfitProtocol)
    g_game.enableFeature(GameNewSpeedLaw)
    g_game.enableFeature(GameOGLInformation)
    g_game.enableFeature(GameOfflineTrainingTime)
    g_game.enableFeature(GamePVPMode)
    g_game.enableFeature(GamePenalityOnDeath)
    g_game.enableFeature(GamePlayerAddons)
    g_game.enableFeature(GamePlayerMarket)
    g_game.enableFeature(GamePlayerMounts)
    g_game.enableFeature(GamePlayerRegenerationTime)
    g_game.enableFeature(GamePlayerStamina)
    g_game.enableFeature(GamePlayerStateU16)
    g_game.enableFeature(GamePlayerStateU32)
    g_game.enableFeature(GamePremiumExpiration)
    g_game.enableFeature(GamePreviewState)
    g_game.enableFeature(GamePrey)
    g_game.enableFeature(GameProtocolChecksum)
    g_game.enableFeature(GamePurseSlot)
    g_game.enableFeature(GameSessionKey)
    g_game.enableFeature(GameSkillsBase)
    g_game.enableFeature(GameSpellList)
    g_game.enableFeature(GameSpritesAlphaChannel)
    g_game.enableFeature(GameSpritesU32)
    g_game.enableFeature(GameThingMarks)
    g_game.enableFeature(GameThingUpgradeClassification)
    g_game.enableFeature(GameTileAddThingWithStackpos)
    g_game.enableFeature(GameTotalCapacity)
    g_game.enableFeature(GameUnjustifiedPoints)
    g_game.enableFeature(GameWritableDate)

    -- Modern protocol framing (Tibia 12+/15.x, Canary/crystalserver). The login
    -- CHALLENGE (0x1F) still arrives adler32-checksummed (GameProtocolChecksum
    -- above); after the client sends the login packet it switches to a 32-bit
    -- SEQUENCE number + zlib compression. See the protocol pipeline memo.
    g_game.enableFeature(GameSequencedPackets)
    g_game.enableFeature(GameTibia12Protocol)
    g_game.enableFeature(GamePacketCompression)
    g_game.enableFeature(GameTibia13Protocol)
    g_game.enableFeature(GameTibia15Protocol)
    g_game.enableFeature(GameModernClient)

    -- Custom server upgrade system: per-item upgrade level badge. crystalserver's
    -- ProtocolGame::AddItem() appends a U8 (upgrade_level) for !oldProtocol; with
    -- this on the client reads that byte for every item, so both sides ship together.
    g_game.enableFeature(GameItemUpgradeSystem)

    -- KoliseuOT 32-bit item ids: read/write item ids as 32-bit on the wire (item ids
    -- > 65535). Must match the koliseuserver 32-bit build.
    g_game.enableFeature(GameU32ItemIds)

    modules.game_things.load()
end
