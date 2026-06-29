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

    -- you can add custom features here, list of them is in the modules\gamelib\const.lua
    --g_game.enableFeature(GameBot)
    --g_game.enableFeature(GameExtendedOpcode)
    --g_game.enableFeature(GameMinimapLimitedToSingleFloor) -- it will generate minimap only for current floor
    --g_game.enableFeature(GameSpritesAlphaChannel)
    --g_game.enableFeature(GameOutfitShaders)
    g_game.enableFeature(GameDontMergeAnimatedText) -- do not stack damage/heal numbers in a short time window

    -- "Ignore opacity on Special Effects" (client_settings > Effects) keeps these
    -- magic-effect ids at full opacity, ignoring the Opacity Effects slider. Fill in
    -- the effect id your server sends for each special effect. Edit freely - this is
    -- read by g_map at runtime, no client recompile needed.
    -- crystalserver magic-effect ids (src/utils/utils_definitions.hpp) for the special
    -- combat procs that should stay fully visible even with the Opacity Effects slider down.
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

    if (version >= 770) then
        g_game.enableFeature(GameLooktypeU16)
        g_game.enableFeature(GameMessageStatements)
        g_game.enableFeature(GameLoginPacketEncryption)
    end

    if (version >= 780) then
        g_game.enableFeature(GamePlayerAddons)
        g_game.enableFeature(GamePlayerStamina)
        g_game.enableFeature(GameNewFluids)
        g_game.enableFeature(GameMessageLevel)
        g_game.enableFeature(GamePlayerStateU16)
        g_game.enableFeature(GameNewOutfitProtocol)
    end

    if (version >= 790) then
        g_game.enableFeature(GameWritableDate)
    end

    if (version >= 840) then
        g_game.enableFeature(GameProtocolChecksum)
        g_game.enableFeature(GameAccountNames)
        g_game.enableFeature(GameDoubleFreeCapacity)
    end

    if (version >= 841) then
        g_game.enableFeature(GameChallengeOnLogin)
        g_game.enableFeature(GameMessageSizeCheck)
        g_game.enableFeature(GameTileAddThingWithStackpos)
    end

    if (version >= 854) then
        g_game.enableFeature(GameCreatureEmblems)
    end

    if (version >= 860) then
        g_game.enableFeature(GameAttackSeq)
        g_game.enableFeature(GameBot)
        g_game.enableFeature(GameExtendedOpcode)
        g_game.enableFeature(GameSkillsBase)
        g_game.enableFeature(GamePlayerMounts)
        g_game.enableFeature(GameMagicEffectU16)
        g_game.enableFeature(GameDistanceEffectU16)
        g_game.enableFeature(GameDoubleHealth)
        g_game.enableFeature(GameOfflineTrainingTime)
        --g_game.enableFeature(GameDoubleSkills)
        g_game.enableFeature(GameBaseSkillU16)
        --g_game.enableFeature(GameDoubleMagicLevel)
        g_game.enableFeature(GameAdditionalSkills)
        g_game.enableFeature(GameIdleAnimations)
        g_game.enableFeature(GameEnhancedAnimations)
        -- GameExtendedClientPing (NewPing, opcode 0x40) is NOT supported by
        -- crystalserver — it only understands the standard 0x1D/0x1E ping. With
        -- it on, the client spammed ~4 useless 0x40 packets/second that the
        -- server silently ignored; the real keepalive is the 0x1E pong sent in
        -- reply to the server's 0x1D ping. Leave it disabled for this server.
        -- g_game.enableFeature(GameExtendedClientPing)
        g_game.enableFeature(GameSpritesU32) -- Extended sprites
        --g_game.enableFeature(GameSpritesAlphaChannel) -- Transparency
        g_game.enableFeature(GameDoublePlayerGoodsMoney)
        g_game.enableFeature(GameCreatureIcons)
        g_game.enableFeature(GamePurseSlot)
        g_game.enableFeature(GameThingUpgradeClassification)
        g_game.enableFeature(GameItemTierByte)
        g_game.enableFeature(GamePrey)

        g_game.enableFeature(GameSpritesU32) -- Extended sprites
        --g_game.enableFeature(GameDoubleExperience) -- Extended sprites
        --g_game.enableFeature(GameSpritesAlphaChannel) -- Transparency
    end

    if (version >= 862) then
        g_game.enableFeature(GamePenalityOnDeath)
    end

    if (version >= 870) then
        g_game.enableFeature(GameDoubleExperience)
        g_game.enableFeature(GamePlayerMounts)
        g_game.enableFeature(GameSpellList)
    end

    if (version >= 910) then
        g_game.enableFeature(GameNameOnNpcTrade)
        g_game.enableFeature(GameTotalCapacity)
        g_game.enableFeature(GameSkillsBase)
        g_game.enableFeature(GamePlayerRegenerationTime)
        g_game.enableFeature(GameChannelPlayerList)
        g_game.enableFeature(GameEnvironmentEffect)
        g_game.enableFeature(GameItemAnimationPhase)
    end

    if (version >= 940) then
        g_game.enableFeature(GamePlayerMarket)
    end

    if (version >= 953) then
        g_game.enableFeature(GamePurseSlot)
        g_game.enableFeature(GameClientPing)
    end

    if (version >= 960) then
        g_game.enableFeature(GameSpritesU32)
        g_game.enableFeature(GameOfflineTrainingTime)
    end

    if (version >= 963) then
        g_game.enableFeature(GameAdditionalVipInfo)
    end

    if (version >= 972) then
        g_game.enableFeature(GameDoublePlayerGoodsMoney)
    end

    if (version >= 980) then
        g_game.enableFeature(GamePreviewState)
        g_game.enableFeature(GameClientVersion)
    end

    if (version >= 981) then
        g_game.enableFeature(GameLoginPending)
        g_game.enableFeature(GameNewSpeedLaw)
    end

    if (version >= 984) then
        g_game.enableFeature(GameContainerPagination)
        g_game.enableFeature(GameBrowseField)
    end

    if (version >= 1000) then
        g_game.enableFeature(GameThingMarks)
        g_game.enableFeature(GamePVPMode)
    end

    if (version >= 1035) then
        g_game.enableFeature(GameDoubleSkills)
        g_game.enableFeature(GameBaseSkillU16)
    end

    if (version >= 1036) then
        g_game.enableFeature(GameCreatureIcons)
        g_game.enableFeature(GameHideNpcNames)
    end

    if (version >= 1038) then
        g_game.enableFeature(GamePremiumExpiration)
    end

    if (version >= 1050) then
        g_game.enableFeature(GameEnhancedAnimations)
    end

    if (version >= 1053) then
        g_game.enableFeature(GameUnjustifiedPoints)
    end

    if (version >= 1054) then
        g_game.enableFeature(GameExperienceBonus)
    end

    if (version >= 1055) then
        g_game.enableFeature(GameDeathType)
    end

    if (version >= 1057) then
        g_game.enableFeature(GameIdleAnimations)
    end

    if (version >= 1061) then
        g_game.enableFeature(GameOGLInformation)
    end

    if (version >= 1071) then
        g_game.enableFeature(GameContentRevision)
    end

    if (version >= 1072) then
        g_game.enableFeature(GameAuthenticator)
    end

    if (version >= 1074) then
        g_game.enableFeature(GameSessionKey)
    end

    if (version >= 1080) then
        g_game.enableFeature(GameIngameStore)
    end

    if (version >= 1092) then
        g_game.enableFeature(GameIngameStoreServiceType)
    end

    if (version >= 1093) then
        g_game.enableFeature(GameIngameStoreHighlights)
    end

    if (version >= 1094) then
        g_game.enableFeature(GameAdditionalSkills)
        --g_game.enableFeature(GameSpritesAlphaChannel)
    end

    if (version >= 1100) then
        g_game.enableFeature(GamePrey)
        g_game.enableFeature(GameMagicEffectU16)
        --g_game.enableFeature(GameDisplayItemDuration)
        g_game.enableFeature(GameSpritesAlphaChannel)
    end

    if (version >= 1200) then
        g_game.enableFeature(GameSequencedPackets)
        --g_game.enableFeature(GameSendWorldName)
        g_game.enableFeature(GamePlayerStateU32)
        g_game.enableFeature(GameTibia12Protocol)
        -- Modern protocol (Tibia 12+/15.x, Canary/crystalserver) framing:
        --   * The initial login CHALLENGE (server-sends-first, 0x1F) still
        --     arrives with an adler32 checksum, so GameProtocolChecksum MUST stay
        --     enabled (set at >= 840) to decode that first packet. Do NOT disable
        --     it here.
        --   * After the client sends the login packet it calls
        --     enabledSequencedPackets(); from then on every packet is framed with
        --     a 32-bit SEQUENCE number + zlib compression. internalRecvData tests
        --     m_sequencedPackets before m_checksumEnabled, so sequencing takes
        --     over automatically once enabled — no need to clear the checksum.
        --   * The server only switches to SEQUENCE framing when the client
        --     announces an OTCLIENT_* OS (<= 12); see Game::getOs(). Compression
        --     is enabled server-side only in the SEQUENCE path, so enable it here.
        g_game.enableFeature(GamePacketCompression)
        -- GameMessageSizeCheck (enabled at >= 841) makes ProtocolGame::onRecv read
        -- a leading U16 "message size" from the first packet body. The modern
        -- crystalserver framing has no such inner size field (outer scaled size
        -- header + checksum + opcode), so it would consume two real content bytes
        -- and fail with "invalid message size". Disable it for the modern protocol.
        g_game.disableFeature(GameMessageSizeCheck)
    end

    if (version >= 1300) then
        g_game.enableFeature(GameTibia13Protocol)
    end

    if (version >= 1400) then
        -- no new feature flags introduced at 1400 (cumulative on 1300)
    end

    if (version >= 1500) then
        g_game.enableFeature(GameTibia15Protocol)
    end

    if (version >= 1524) then
        g_game.enableFeature(GameModernClient)

        -- Custom server upgrade system: per-item upgrade level badge (green=weapon,
        -- blue=set). Enabled now that crystalserver's ProtocolGame::AddItem() appends the
        -- matching U8 (upgrade_level) at the end for !oldProtocol. Both sides MUST ship
        -- together: with the feature on, the client reads that byte for every item, so a
        -- server without the append would desync every item parse.
        g_game.enableFeature(GameItemUpgradeSystem)

        -- KoliseuOT 32-bit item ids: read/write item ids as 32-bit on the wire (required for
        -- item ids > 65535). Default OFF (16-bit) so this client keeps working with the
        -- CURRENT u16 server. Both sides MUST match: ENABLE this ONLY after deploying the
        -- 32-bit (koliseuserver) build, otherwise every item parse desyncs.
        g_game.enableFeature(GameU32ItemIds)
    end

    modules.game_things.load()
end
