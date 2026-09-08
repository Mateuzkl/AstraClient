-- ===== HELPER MAGIC SHOOTER =====
-- Modulo separado para gerenciar o Magic Shooter (Auxiliador) do Helper

-- Garante que _Helper existe (sera definido em helper.lua, mas pode ser carregado antes)
if not _Helper then
  _Helper = {}
end

_Helper.MagicShooter = {}
_Helper.MagicShooter._isLoadingUI = false

-- Optimization Caches
local unifiedListCache = {}
local reusableCreatureList = {}
local reusableEntries = {}
for i = 1, 100 do reusableEntries[i] = { position = { x = 0, y = 0, z = 0 }, creature = nil } end

-- ===== CONFIGURACOES LOCAIS =====

local auxiliadorPreCooldown = 200
local activeBuffs = {} -- spellId -> expiration timestamp (ms)
local OPCODE_CAST_ON_FOOT = 211

-- spells that can be cast on both targets and self (CAST ON FOOT)
local bothCastTypeSpells = {
  258 -- exevo tempo mas san, granada RP
}

local function isExposeWeaknessSpell(spellId)
  if not spellId then return false end
  return HelperSpellData.isExposeWeaknessSpell(spellId)
end

local function isSapStrengthSpell(spellId)
  if not spellId then return false end
  return HelperSpellData.isSapStrengthSpell(spellId)
end

-- Check if a spell uses the rangedMonsterNames filter (loaded from spelldata.json)
local function isRangedMonsterSpell(spellId)
  if not spellId then return false end
  return HelperSpellData.isRangedMonsterSpell(spellId)
end

-- Parse rangedMonsterNames string into a table of lowercase names
local function parseRangedMonsterNames(namesString)
  local namesTable = {}
  if not namesString or namesString == "" then
    return namesTable
  end

  for name in string.gmatch(namesString, "([^,]+)") do
    -- Trim whitespace and convert to lowercase
    name = name:match("^%s*(.-)%s*$"):lower()
    if name ~= "" then
      namesTable[name] = true
    end
  end

  return namesTable
end

-- ===== FUNCOES DO MAGIC SHOOTER =====

-- Verifica se um tile tem criatura bloqueando (exceto o LocalPlayer)
local function tileHasBlockingCreature(tile, localPlayer)
  local creatures = tile:getCreatures()
  if not creatures or #creatures == 0 then
    return false
  end

  for _, creature in ipairs(creatures) do
    -- Ignora o proprio player
    if creature ~= localPlayer then
      -- Se tem qualquer outra criatura visivel, considera como bloqueando
      -- (a maioria das criaturas bloqueia passagem)
      if creature:canBeSeen() then
        return true
      end
    end
  end

  return false
end

-- Verifica se o player esta "trapped" (nao pode andar em nenhuma direcao)
_Helper.MagicShooter.isPlayerTrapped = function()
  local player = g_game.getLocalPlayer()
  if not player then return false end

  local playerPos = player:getPosition()
  if not playerPos then return false end

  -- Verifica as 8 direcoes
  local directions = {
    { x = 0,  y = -1, z = 0 }, -- N
    { x = 0,  y = 1,  z = 0 }, -- S
    { x = 1,  y = 0,  z = 0 }, -- E
    { x = -1, y = 0,  z = 0 }, -- W
    { x = -1, y = -1, z = 0 }, -- NW
    { x = 1,  y = -1, z = 0 }, -- NE
    { x = -1, y = 1,  z = 0 }, -- SW
    { x = 1,  y = 1,  z = 0 }  -- SE
  }

  for _, dir in ipairs(directions) do
    local targetPos = {
      x = playerPos.x + dir.x,
      y = playerPos.y + dir.y,
      z = playerPos.z + dir.z
    }

    local tile = g_map.getTile(targetPos)
    if not tile then
      -- Se o tile nao foi carregado no mapa, assumir que e um espaco livre
      -- Isso evita falsos positivos de "trapped" quando o mapa nao carregou completamente
      return false
    end

    -- Verifica se o tile base e andavel (sem considerar criaturas)
    -- isWalkable(true) ignora criaturas e verifica apenas bloqueios estaticos (paredes, items, etc)
    local isStaticWalkable = tile:isWalkable(true)

    if isStaticWalkable then
      -- Tile e andavel estaticamente, agora verifica se tem criatura bloqueando
      -- Exclui o LocalPlayer da verificacao
      if not tileHasBlockingCreature(tile, player) then
        -- Tile e livre para andar (sem bloqueio estatico e sem criatura bloqueando)
        return false
      end
    end
    -- Se nao e walkable ou tem bloqueador, continua verificando outras direcoes
  end

  -- Todas as direcoes estao bloqueadas, player esta trapped
  return true
end

-- Retorna se o magic shooter esta ativo
_Helper.MagicShooter.isActive = function()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    return helperConfig.magicShooterEnabled
  end
  return false
end

-- Toggle para habilitar/desabilitar o Magic Shooter
_Helper.MagicShooter.toggle = function(widget, message)
  local helper = _Helper.getHelper and _Helper.getHelper()
  local shooterPanel = _Helper.getShooterPanel and _Helper.getShooterPanel()

  if not helper or not shooterPanel then return end

  if not widget then
    widget = shooterPanel:recursiveGetChildById("enableMagicShooter")
    if widget then widget:setChecked(not widget:isChecked()) end
  end

  if not widget then return end


  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.magicShooterEnabled = widget:isChecked()
  end

  if not _Helper._suppressMessages then
    modules.game_textmessage.displayGameMessage(message and message or
      string.format("Magic Shooter is %s.",
        (helperConfig and helperConfig.magicShooterEnabled and "enabled" or "disabled")))
  end

  -- Sincronizar com shortcut panel
  if _Helper.Shortcut and _Helper.Shortcut.syncButton then
    _Helper.Shortcut.syncButton('shortcutShooter', helperConfig and helperConfig.magicShooterEnabled)
  end

  -- Salvar configuracao
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
end

-- Hold system - pausa a cast de runas
_Helper.MagicShooter.hold = function()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.magicShooterOnHold = true
  end
end

_Helper.MagicShooter.release = function()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.magicShooterOnHold = false
  end
end

-- Rebuild the cache of unified spells/runes
_Helper.MagicShooter.rebuildCache = function()
  unifiedListCache = {}

  local getShooterProfile = _Helper.getShooterProfile
  local profile = getShooterProfile and getShooterProfile()
  if not profile then return end

  -- New format: rules array (unified spells and runes)
  if profile.rules and #profile.rules > 0 then
    for ruleIndex, rule in ipairs(profile.rules) do
      if rule.enabled ~= false then
        if rule.type == "spell" and rule.spellId and rule.spellId > 0 then
          local spell = Spells.getSpellByClientId(rule.spellId)
          if spell then
            local config = {
              id = rule.spellId,
              percent = rule.manaPercent or 0,
              healthPercent = rule.healthPercent or 0,
              creatures = rule.creatures or 1,
              priority = ruleIndex,
              selfCast = rule.selfCast or false,
              harmonyThreshold = 0,
              castIfTrapped = rule.castIfTrapped or false,
              countLowerThan = rule.countLowerThan or false,
              extendedArea = rule.extendedArea or false,
              extendedArea2 = rule.extendedArea2 or false,
              forceOnTarget = rule.forceOnTarget or false,
              rangedMonsterNames = rule.rangedMonsterNames or "",
              extraDelay = rule.extraDelay or 0,
              hpMin = rule.hpMin or 0,
              hpMax = rule.hpMax or 0
            }
            table.insert(unifiedListCache, { type = "spell", spell = spell, config = config })
          end
        elseif rule.type == "rune" and rule.itemId and rule.itemId > 0 then
          local runeSpell = Spells.getRuneSpellByItem(rule.itemId)
          if not runeSpell and CustomRuneIds then runeSpell = CustomRuneIds[rule.itemId] end
          _Helper.resolveCustomRuneArea(runeSpell)
          if runeSpell then
            local config = {
              id = rule.itemId,
              healthPercent = rule.healthPercent or 0,
              creatures = rule.creatures or 1,
              priority = ruleIndex,
              castIfTrapped = rule.castIfTrapped or false,
              countLowerThan = rule.countLowerThan or false,
              extraDelay = rule.extraDelay or 0,
              hpMin = rule.hpMin or 0,
              hpMax = rule.hpMax or 0
            }
            table.insert(unifiedListCache, { type = "rune", rune = runeSpell, config = config })
          end
        end
      end
    end
  else
    -- Old format: separate spells and runes arrays
    if profile.spells then
      for i, shooter in ipairs(profile.spells) do
        if shooter.id and shooter.id ~= 0 then
          local spell = Spells.getSpellByClientId(shooter.id)
          if spell then
            table.insert(unifiedListCache, { type = "spell", spell = spell, config = shooter })
          end
        end
      end
    end

    if profile.runes then
      for i, runeConfig in ipairs(profile.runes) do
        if runeConfig.id and runeConfig.id ~= 0 then
          local runeSpell = Spells.getRuneSpellByItem(runeConfig.id)
          if not runeSpell and CustomRuneIds then runeSpell = CustomRuneIds[runeConfig.id] end
          _Helper.resolveCustomRuneArea(runeSpell)
          if runeSpell then
            table.insert(unifiedListCache, { type = "rune", rune = runeSpell, config = runeConfig })
          end
        end
      end
    end
  end

  -- Sort by priority
  if #unifiedListCache > 0 then
    unifiedListCache = _Helper.MagicShooter.sortByPriority(unifiedListCache)
  end
end

-- Ordena a lista de spells/runas por prioridade (com logica de harmony spender)
_Helper.MagicShooter.sortByPriority = function(list)
  table.sort(list, function(a, b)
    if a.config.priority and b.config.priority then
      return a.config.priority < b.config.priority
    else
      return false
    end
  end)

  local player = g_game.getLocalPlayer()
  if not player then return list end

  local harmonyCount = player:getHarmony() or 0

  if harmonyCount >= 5 then
    local spenderIndex = nil
    for i, item in ipairs(list) do
      if item.spell and item.spell.spender then
        spenderIndex = i
        break
      end
    end

    if spenderIndex then
      local spenderSpell = table.remove(list, spenderIndex)
      table.insert(list, 1, spenderSpell)
    end
  end
  return list
end

-- Funcao principal que verifica e executa o magic shooter
_Helper.MagicShooter.check = function()
  if modules.game_helper and modules.game_helper.cavebot and
      modules.game_helper.cavebot.isCombatSuppressed and modules.game_helper.cavebot.isCombatSuppressed() then
    return
  end
  local helperAutomaticFunctionsEnabled = _Helper.isHelperAutomaticFunctionsEnabled and
      _Helper.isHelperAutomaticFunctionsEnabled()
  if not helperAutomaticFunctionsEnabled then
    return
  end

  -- PZ Guard: handles state transitions and blocks actions while in PZ
  -- Must be called before enabled check to detect PZ exit and restore state
  if _Helper.handlePZState then
    local shouldContinue = _Helper.handlePZState()
    if not shouldContinue then
      return
    end
  end

  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.magicShooterEnabled then
    return
  end

  local getShooterProfile = _Helper.getShooterProfile
  local profile = getShooterProfile and getShooterProfile()
  if not profile then
    return
  end

  local myCharacter = g_game.getLocalPlayer()
  if not myCharacter then
    return
  end

  -- Magic shooter so desliga via hotkey ou checkbox do usuario
  -- AFK e follow nativo nao desligam mais automaticamente

  local position, direction = myCharacter:getPosition(), myCharacter:getDirection()

  -- Use reusable table instead of creating new one
  for k in pairs(reusableCreatureList) do reusableCreatureList[k] = nil end
  local creatureList = reusableCreatureList

  local creaturesAround = 0

  local spectators = _Helper.getSpectators and _Helper.getSpectators() or {}
  local getDistanceBetween = _Helper.getDistanceBetween

  -- Obter lista de monstros a ignorar
  local ignoreMonsterTable = _Helper.getIgnoreMonsterTable and _Helper.getIgnoreMonsterTable() or {}

  for i, creature in pairs(spectators) do
    -- Verificar se é um monstro (ignorar players, NPCs, etc.)
    if not creature:isMonster() then
      goto continue
    end

    -- Ignorar criaturas invocadas (summons) - mesma lógica do Auto Target
    if creature:getMasterId() ~= 0 then
      goto continue
    end

    local creaturePos = creature:getPosition()
    if creaturePos then
      -- Verificar se o monstro está na lista de ignorados
      local creatureName = creature:getName()
      if creatureName and ignoreMonsterTable[creatureName:lower()] then
        goto continue
      end

      -- Verificar se o monstro está no mesmo andar
      if creaturePos.z ~= position.z then
        goto continue
      end

      local hasSightClear = g_map.isSightClear(position, creaturePos)

      if getDistanceBetween and getDistanceBetween(position, creaturePos) <= 6 then
        creaturesAround = creaturesAround + 1
      end

      local entry = reusableEntries[#creatureList + 1]
      if not entry then
        entry = { position = { x = 0, y = 0, z = 0 }, creature = nil }
        reusableEntries[#creatureList + 1] = entry
      end
      entry.position.x = creaturePos.x
      entry.position.y = creaturePos.y
      entry.position.z = creaturePos.z
      entry.creature = creature
      entry.hasSightClear = hasSightClear
      entry.turnedMelee = creature:hasIcon(MonsterIconTurnedMelee)
      entry.exposeWeakness = creature:hasIcon(MonsterIconExposeWeakness)
      entry.sapStrength = creature:hasIcon(MonsterIconSapStrength)
      table.insert(creatureList, entry)
    end
    ::continue::
  end

  local unifiedList = unifiedListCache
  if #unifiedList == 0 then
    -- Try to rebuild if empty (first run)
    _Helper.MagicShooter.rebuildCache()
    unifiedList = unifiedListCache

    if #unifiedList == 0 then
      return
    end
  end

  -- Note: Sorting is now done in rebuildCache

  local percentageMana = (myCharacter:getMana() / myCharacter:getMaxMana()) * 100
  local percentageHealth = (myCharacter:getHealth() / myCharacter:getMaxHealth()) * 100

  local autoTargetOnHold = _Helper.getAutoTargetOnHold and _Helper.getAutoTargetOnHold()
  if autoTargetOnHold then
    return
  end

  -- Flag: when a higher-priority rune is ready but waiting for object use cooldown,
  -- block lower-priority spells from stealing the turn
  local runeWaitingForObjectUse = false

  for _, entry in ipairs(unifiedList) do
    if autoTargetOnHold then
      goto continue
    end

    local target = g_game.getAttackingCreature()
    local positionTarget = target and target:getPosition() or { x = 0xFFFF, y = 0xFFFF, z = 0xFF }

    if entry.type == "spell" then
      -- If a higher-priority rune is waiting for object use cooldown, skip this spell
      if runeWaitingForObjectUse then
        goto continue
      end
      local castOnFoot = false
      local spell = entry.spell
      local config = entry.config
      local reachableCreatures = 0
      -- Use extendedArea2 if config.extendedArea2 is true, otherwise extendedArea if config.extendedArea is true
      local spellArea = (config.extendedArea2 and spell.extendedArea2) or (config.extendedArea and spell.extendedArea) or
      spell.area
      -- Spell é targetable se tem range > 0 E não é spell de área, OU se está na lista de bothCastTypeSpells
      local targetable = ((spell.range and spell.range > 0) and not spell.area) or
          table.contains(bothCastTypeSpells, spell.id)

      -- Verificar se é spell de suporte (deve respeitar quantidade mínima de monstros)
      local isSupportSpell = HelperSpellData and HelperSpellData.isSupportSpellAllowed and
          HelperSpellData.isSupportSpellAllowed(spell.id, myCharacter:getVocation())

      -- Magic Shield tem prioridade total sobre o support group:
      -- adia spells de suporte do shooter quando utamo/exana vita estao prestes a castar.
      if isSupportSpell then
        local toolsModule = modules.game_helper and modules.game_helper.tools
        if toolsModule and toolsModule.isMagicShieldPending and toolsModule.isMagicShieldPending() then
          goto continue
        end
      end

      -- ExposeWeakness and SapStrength spells don't require a target
      local requiresTarget = targetable and not target and not isExposeWeaknessSpell(spell.id) and
          not isSapStrengthSpell(spell.id)
      if myCharacter:getMana() < spell.mana or requiresTarget then
        goto continue
      elseif _Helper.canUseByServerVoc and not _Helper.canUseByServerVoc(spell.vocations, myCharacter:getVocation()) then
        goto continue
      elseif _Helper.playerHasSpell and not _Helper.playerHasSpell(myCharacter, spell.id) then
        goto continue
      end

      -- Check health percent requirement (only if configured > 0)
      local healthCheck = config.healthPercent or 0
      if healthCheck > 0 and percentageHealth < healthCheck then
        goto continue
      end

      -- Check mana percent requirement (only if configured > 0)
      local manaCheck = config.percent or 0
      if manaCheck > 0 and percentageMana < manaCheck then
        goto continue
      end

      -- Filter creature list by creature HP% range (hpMin/hpMax)
      local hpMin = config.hpMin or 0
      local hpMax = config.hpMax or 0
      local activeCreatureList = creatureList
      local activeCreaturesAround = creaturesAround
      if hpMin > 0 or hpMax > 0 then
        activeCreatureList = {}
        activeCreaturesAround = 0
        for _, cEntry in ipairs(creatureList) do
          local creature = cEntry.creature
          if creature then
            local cHp = creature:getHealthPercent()
            if cHp >= hpMin and (hpMax == 0 or cHp <= hpMax) then
              table.insert(activeCreatureList, cEntry)
              local cPos = cEntry.position
              if cPos and cPos.z == position.z and getDistanceBetween and getDistanceBetween(position, cPos) <= 6 then
                activeCreaturesAround = activeCreaturesAround + 1
              end
            end
          end
        end
        if #activeCreatureList == 0 then
          goto continue
        end
      end

      -- Check castIfTrapped requirement: skip this spell if it requires being trapped but player is not trapped
      if config.castIfTrapped and not _Helper.MagicShooter.isPlayerTrapped() then
        goto continue
      end

      -- Build ranged monster names table (merge defaults from spelldata.json + user names)
      local rangedNamesTable = nil
      if isRangedMonsterSpell(spell.id) then
        local defaultNames = HelperSpellData.getDefaultRangedMonsterNames(spell.id)
        if defaultNames then
          rangedNamesTable = {}
          for name, _ in pairs(defaultNames) do
            rangedNamesTable[name] = true
          end
        end
        if config.rangedMonsterNames and config.rangedMonsterNames ~= "" then
          local userNames = parseRangedMonsterNames(config.rangedMonsterNames)
          if not rangedNamesTable then
            rangedNamesTable = userNames
          else
            for name, _ in pairs(userNames) do
              rangedNamesTable[name] = true
            end
          end
        end
      end
      local useRangedFilter = rangedNamesTable ~= nil and next(rangedNamesTable) ~= nil

      -- Special handling for ranged monster spells (exana amp res, exeta amp res, exori mas res)
      -- These spells need to find the direction with most matching monsters
      -- Monsters with turned_melee icon (icon 3) are already converted and should be ignored
      if isRangedMonsterSpell(spell.id) then
        -- Skip ranged monster spells if there's no free space around the player
        -- These spells make monsters move towards the player, so they need at least 1 free tile
        if _Helper.MagicShooter.isPlayerTrapped() then
          goto continue
        end

        -- Filter creatures by name if rangedMonsterNames is set, otherwise use all creatures
        -- Also exclude creatures that already have the turned_melee icon (icon 3)
        local filteredCreatureList = {}
        local hasRangedNameFilter = useRangedFilter and rangedNamesTable and next(rangedNamesTable) ~= nil

        if hasRangedNameFilter then
          for _, entry in ipairs(activeCreatureList) do
            local creature = entry.creature
            if creature then
              local creatureName = creature:getName()
              -- Check if creature matches name filter AND doesn't have turned_melee icon
              if creatureName and rangedNamesTable[creatureName:lower()] then
                if not entry.turnedMelee then
                  table.insert(filteredCreatureList, entry)
                end
              end
            end
          end
        else
          -- No name filter, but still exclude creatures with turned_melee icon
          for _, entry in ipairs(activeCreatureList) do
            local creature = entry.creature
            if creature and not entry.turnedMelee then
              table.insert(filteredCreatureList, entry)
            end
          end
        end

        -- Count filtered creatures around player (within range 6)
        local filteredCreaturesAround = 0
        for _, entry in ipairs(filteredCreatureList) do
          local creaturePos = entry.position
          if creaturePos and creaturePos.z == position.z and getDistanceBetween and getDistanceBetween(position, creaturePos) <= 6 then
            filteredCreaturesAround = filteredCreaturesAround + 1
          end
        end

        -- Find the best direction with most creatures
        -- Only calculate direction for exori mas res (ID 280) which has aimAtTarget
        local bestDirection = direction
        if spell.aimAtTarget then
          local bestCreatureCount = 0
          local directions = { 0, 1, 2, 3 } -- North, East, South, West

          -- Determine which creature list to use for direction calculation:
          -- If rangedMonsterNames has entries AND there are matching monsters, use filteredCreatureList
          -- Otherwise (empty list OR no matching monsters), use all creatures (excluding turned_melee)
          local creaturesForDirection = filteredCreatureList
          if #filteredCreatureList == 0 then
            -- No matching monsters from the name filter (or filter is empty)
            -- Fall back to all creatures without turned_melee icon
            for _, entry in ipairs(activeCreatureList) do
              local creature = entry.creature
              if creature and not entry.turnedMelee then
                table.insert(creaturesForDirection, entry)
              end
            end
          end

          for _, dir in ipairs(directions) do
            local count = 0
            for _, entry in ipairs(creaturesForDirection) do
              local creaturePos = entry.position
              if creaturePos and creaturePos.z == position.z then
                local dx = creaturePos.x - position.x
                local dy = creaturePos.y - position.y
                local dist = getDistanceBetween and getDistanceBetween(position, creaturePos) or
                    math.max(math.abs(dx), math.abs(dy))

                -- Check if creature is in the direction (half-plane, more permissive)
                if dist > 0 and dist <= 6 then
                  local inDirection = false
                  if dir == 0 then     -- North (y < 0)
                    inDirection = dy < 0
                  elseif dir == 1 then -- East (x > 0)
                    inDirection = dx > 0
                  elseif dir == 2 then -- South (y > 0)
                    inDirection = dy > 0
                  elseif dir == 3 then -- West (x < 0)
                    inDirection = dx < 0
                  end

                  if inDirection then
                    count = count + 1
                  end
                end
              end
            end

            if count > bestCreatureCount then
              bestCreatureCount = count
              bestDirection = dir
            end
          end
        end

        reachableCreatures = filteredCreaturesAround
        config.bestDirection = bestDirection
      elseif isExposeWeaknessSpell(spell.id) or isSapStrengthSpell(spell.id) then
        -- For ExposeWeakness/SapStrength spells, filter creatures that don't have EITHER icon
        -- (they are mutually exclusive - if one is active, the other shouldn't be cast)

        -- If player has an active target, skip area check and just validate the target's icons
        if target then
          -- Find the target in activeCreatureList and check its icons
          for _, entry in ipairs(activeCreatureList) do
            if entry.creature and entry.creature == target then
              -- Skip if creature has ANY of the debuffs (exposeWeakness OR sapStrength)
              local hasAnyDebuff = entry.exposeWeakness or entry.sapStrength
              reachableCreatures = hasAnyDebuff and 0 or 1
              break
            end
          end
        else
          -- No target, use area-based counting with filtered creature list
          local filteredCreatureList = {}

          for _, entry in ipairs(activeCreatureList) do
            -- Only include creatures that have NEITHER exposeWeakness NOR sapStrength
            if entry.creature and not entry.exposeWeakness and not entry.sapStrength then
              table.insert(filteredCreatureList, entry)
            end
          end

          -- Use the area-based counting with the filtered list
          if spellArea and _Helper.countAttackableCreatures then
            reachableCreatures = _Helper.countAttackableCreatures(position, direction, spellArea, filteredCreatureList,
              false) or 0
          else
            reachableCreatures = #filteredCreatureList
          end
        end
      elseif targetable and not config.selfCast then
        if not positionTarget or positionTarget.z ~= position.z or not target:canBeSeen() then
          goto continue
        end
        -- Check if the target's HP% is within the configured range
        if target and (hpMin > 0 or hpMax > 0) then
          local tHp = target:getHealthPercent()
          if tHp < hpMin or (hpMax > 0 and tHp > hpMax) then
            goto continue
          end
        end
        local range = spell.range or 3

        if target and target.getCollisionSquare and target:getCollisionSquare() > 1 then
          positionTarget = _Helper.getRelativePosition and _Helper.getRelativePosition(positionTarget) or
              positionTarget
        end

        if target and getDistanceBetween and range >= getDistanceBetween(position, positionTarget) then
          if spellArea then
            reachableCreatures = _Helper.countAttackableCreatures and
                _Helper.countAttackableCreatures(positionTarget, 1, spellArea, activeCreatureList, true) or 0
          else
            -- For single target spells, count creatures around player to allow creatures threshold
            reachableCreatures = activeCreaturesAround
          end
        end
      elseif spellArea then
        if config.forceOnTarget and spell.aimAtTarget and target and positionTarget then
          -- Force spell direction towards the current target, skip area optimization
          local dx = positionTarget.x - position.x
          local dy = positionTarget.y - position.y
          local targetDir
          if math.abs(dx) > math.abs(dy) then
            targetDir = dx > 0 and Directions.East or Directions.West
          else
            targetDir = dy > 0 and Directions.South or Directions.North
          end
          config.bestDirection = targetDir
          reachableCreatures = _Helper.countAttackableCreatures and
              _Helper.countAttackableCreatures(position, targetDir, spellArea, activeCreatureList, false) or
              activeCreaturesAround
        else
          -- Encontrar a melhor direcao para maximizar o numero de criaturas atingidas
          local bestDirection, bestCreatureCount
          if _Helper.findBestDirectionForSpell then
            bestDirection, bestCreatureCount = _Helper.findBestDirectionForSpell(position, spellArea, activeCreatureList,
              false)
          else
            bestDirection = direction
            bestCreatureCount = _Helper.countAttackableCreatures and
                _Helper.countAttackableCreatures(position, direction, spellArea, activeCreatureList, false) or 0
          end
          reachableCreatures = bestCreatureCount
          -- Armazenar a melhor direcao para virar apenas antes de castar
          config.bestDirection = bestDirection
        end
        local bothCountToCheck = config.countLowerThan and activeCreaturesAround or reachableCreatures
        local bothCreaturesMet
        if config.countLowerThan then
          bothCreaturesMet = bothCountToCheck >= 1 and bothCountToCheck <= config.creatures
        else
          bothCreaturesMet = bothCountToCheck >= config.creatures
        end
        if table.contains(bothCastTypeSpells, spell.id) and bothCreaturesMet then
          castOnFoot = true
        end
      else
        -- Para spells de suporte, verificar quantidade de monstros ao redor
        -- Para outros spells sem área e não-targetable, usar 1
        if isSupportSpell then
          reachableCreatures = activeCreaturesAround
        else
          reachableCreatures = 1
        end
      end

      -- countLowerThan: usar activeCreaturesAround (total de monstros na tela filtrados por HP%) em vez de reachableCreatures (area-specific)
      local countToCheck = config.countLowerThan and activeCreaturesAround or reachableCreatures
      local creaturesMet
      if config.countLowerThan then
        creaturesMet = countToCheck >= 1 and countToCheck <= config.creatures
      else
        creaturesMet = countToCheck >= config.creatures
      end
      if creaturesMet then
        if _Helper.isSpellOnCooldown and _Helper.isSpellOnCooldown(spell) then
          goto continue
        end

        -- Extra delay: if configured, add delay to cooldown check
        local extraDelay = config.extraDelay or 0
        if extraDelay > 0 and _Helper.getSpellCooldown then
          local cdEnd = _Helper.getSpellCooldown(spell.id)
          local now = g_clock.millis()
          if cdEnd > 0 and (cdEnd + extraDelay) >= now then
            goto continue
          end
        end

        -- Check if buff is still active (e.g. utito tempo lasts 10s but cooldown is 2s)
        local buffDuration = HelperSpellData.getBuffDuration(spell.id)
        if buffDuration > 0 and activeBuffs[spell.id] and activeBuffs[spell.id] > g_clock.millis() then
          goto continue
        end

        if _Helper.safeDoThing then _Helper.safeDoThing(false) end
        -- Virar o personagem na direcao com mais criaturas para spells com aimAtTarget = true
        local shouldTurn = spell.aimAtTarget and config.bestDirection and config.bestDirection ~= direction
        if shouldTurn then
          g_game.turn(config.bestDirection)
        end
        if castOnFoot then
          local protocolGame = g_game.getProtocolGame()
          if protocolGame then
            protocolGame:sendExtendedOpcode(OPCODE_CAST_ON_FOOT, "1")
          end
        end
        g_game.talk(spell.words)
        if _Helper.safeDoThing then _Helper.safeDoThing(true) end

        -- Track buff expiration for spells with buff duration
        if buffDuration > 0 then
          activeBuffs[spell.id] = g_clock.millis() + buffDuration
        end

        if auxiliadorPreCooldown > 0 then
          if _Helper.onSpellCooldown then _Helper.onSpellCooldown(spell.id, auxiliadorPreCooldown) end
          for group, _ in pairs(spell.group) do
            if _Helper.onSpellGroupCooldown then _Helper.onSpellGroupCooldown(group, auxiliadorPreCooldown) end
          end
        end

        -- Spells don't have object use exhaustion, so try potion immediately (same turn)
        if _Helper.tryPotionAfterSpell then _Helper.tryPotionAfterSpell() end
      end
    elseif entry.type == "rune" then
      if helperConfig.magicShooterOnHold then
        goto continue
      end

      local runeSpell = entry.rune
      local config = entry.config

      -- Check health percent requirement (only if configured > 0)
      local healthCheck = config.healthPercent or 0
      if healthCheck > 0 and percentageHealth < healthCheck then
        goto continue
      end

      -- Filter creature list by creature HP% range (hpMin/hpMax)
      local hpMin = config.hpMin or 0
      local hpMax = config.hpMax or 0
      local activeCreatureList = creatureList
      local activeCreaturesAround = creaturesAround
      if hpMin > 0 or hpMax > 0 then
        activeCreatureList = {}
        activeCreaturesAround = 0
        for _, cEntry in ipairs(creatureList) do
          local creature = cEntry.creature
          if creature then
            local cHp = creature:getHealthPercent()
            if cHp >= hpMin and (hpMax == 0 or cHp <= hpMax) then
              table.insert(activeCreatureList, cEntry)
              local cPos = cEntry.position
              if cPos and cPos.z == position.z and getDistanceBetween and getDistanceBetween(position, cPos) <= 6 then
                activeCreaturesAround = activeCreaturesAround + 1
              end
            end
          end
        end
        if #activeCreatureList == 0 then
          goto continue
        end
      end

      -- Check castIfTrapped requirement: skip this rune if it requires being trapped but player is not trapped
      if config.castIfTrapped and not _Helper.MagicShooter.isPlayerTrapped() then
        goto continue
      end

      -- Usar getInventoryCount que funciona com containers fechados (igual potions)
      local runeCount = myCharacter:getInventoryCount(config.id, 0)

      if runeCount and runeCount > 0 then
        local bestTarget = nil
        local maxCreaturesHit = 0
        if runeSpell.area then
          -- Para runas de area, buscar o MELHOR TILE (nao creature) para maximizar dano
          -- Isso permite jogar a runa em tiles que atingem multiplas criaturas mesmo sem
          -- visao direta para nenhuma creature especifica
          local runeMinCreatures = config.countLowerThan and 1 or config.creatures
          bestTarget, maxCreaturesHit =
              _Helper.findBestTileForRune and
              _Helper.findBestTileForRune(position, direction, runeSpell.area, activeCreatureList, runeMinCreatures) or
              nil, 0
          -- countLowerThan: only cast if creatures hit is <= threshold
          if config.countLowerThan and maxCreaturesHit > config.creatures then
            bestTarget = nil
          end
        else
          -- Runas single-target nao precisam de visao clara (igual potions)
          -- O servidor valida a acao, o cliente so precisa verificar distancia
          bestTarget = target and _Helper.isWithinReach and _Helper.isWithinReach(position, positionTarget) and target or
              nil
          -- Check if the target's HP% is within the configured range
          if bestTarget and (hpMin > 0 or hpMax > 0) then
            local tHp = bestTarget:getHealthPercent()
            if tHp < hpMin or (hpMax > 0 and tHp > hpMax) then
              bestTarget = nil
            end
          end
          -- countLowerThan: verificar total de criaturas ao redor
          if config.countLowerThan and bestTarget and activeCreaturesAround > config.creatures then
            bestTarget = nil
          end
        end
        if bestTarget then
          if _Helper.isSpellOnCooldown and _Helper.isSpellOnCooldown(runeSpell) then
            goto continue
          end

          -- Extra delay: if configured, add delay to cooldown check
          local extraDelay = config.extraDelay or 0
          if extraDelay > 0 and _Helper.getSpellCooldown and runeSpell then
            local cdEnd = _Helper.getSpellCooldown(runeSpell.id)
            if cdEnd > 0 and (cdEnd + extraDelay) >= g_clock.millis() then
              goto continue
            end
          end

          -- Runes share object use exhaustion with potions
          if _Helper.isObjectUseOnCooldown and _Helper.isObjectUseOnCooldown() then
            -- Rune is ready (target, cooldown, inventory all OK) but blocked by object use cooldown (pot/rune)
            -- Block lower-priority spells from stealing this turn
            runeWaitingForObjectUse = true
            goto continue
          end
          if _Helper.safeDoThing then _Helper.safeDoThing(false) end
          g_game.useInventoryItemWith(config.id, bestTarget, 0, true)
          if _Helper.safeDoThing then _Helper.safeDoThing(true) end

          -- Set shared object use cooldown so potions know a rune was just used
          if _Helper.setObjectUseCooldown then _Helper.setObjectUseCooldown() end

          if auxiliadorPreCooldown > 0 then
            if _Helper.onSpellGroupCooldown then _Helper.onSpellGroupCooldown(runeSpell.group, auxiliadorPreCooldown) end
          end
        end
      end
    end
    ::continue::
  end

  -- Limpeza: remover referências a objetos C++ para permitir GC
  for i = 1, #reusableEntries do
    reusableEntries[i].creature = nil
  end
end

-- Returns true if any configured support spell would fire on this cycle.
-- Mirrors the gating logic of MagicShooter.check for support spells only,
-- so Auto Haste can yield the support-group cooldown to them.
_Helper.MagicShooter.hasPendingSupportSpell = function()
  if #unifiedListCache == 0 then return false end

  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.magicShooterEnabled then return false end

  local myCharacter = g_game.getLocalPlayer()
  if not myCharacter then return false end

  local vocation = myCharacter:getVocation()

  local hasAnySupport = false
  for _, entry in ipairs(unifiedListCache) do
    if entry.type == "spell" and entry.spell and HelperSpellData and HelperSpellData.isSupportSpellAllowed and
        HelperSpellData.isSupportSpellAllowed(entry.spell.id, vocation) then
      hasAnySupport = true
      break
    end
  end
  if not hasAnySupport then return false end

  local maxHp = myCharacter:getMaxHealth()
  local maxMana = myCharacter:getMaxMana()
  if maxHp == 0 or maxMana == 0 then return false end

  local position = myCharacter:getPosition()
  if not position then return false end

  local percentageHealth = (myCharacter:getHealth() / maxHp) * 100
  local percentageMana = (myCharacter:getMana() / maxMana) * 100
  local now = g_clock.millis()

  local creaturesAround = 0
  local spectators = _Helper.getSpectators and _Helper.getSpectators() or {}
  local getDistanceBetween = _Helper.getDistanceBetween
  for _, creature in pairs(spectators) do
    if creature and creature:isMonster() and creature:getMasterId() == 0 then
      local cPos = creature:getPosition()
      if cPos and cPos.z == position.z and getDistanceBetween and
          getDistanceBetween(position, cPos) <= 6 then
        creaturesAround = creaturesAround + 1
      end
    end
  end

  for _, entry in ipairs(unifiedListCache) do
    if entry.type == "spell" then
      local spell = entry.spell
      local config = entry.config
      if HelperSpellData and HelperSpellData.isSupportSpellAllowed and
          HelperSpellData.isSupportSpellAllowed(spell.id, vocation) then
        local skip = false

        if myCharacter:getMana() < spell.mana then skip = true end

        if not skip and _Helper.canUseByServerVoc and
            not _Helper.canUseByServerVoc(spell.vocations, vocation) then
          skip = true
        end

        if not skip and _Helper.playerHasSpell and
            not _Helper.playerHasSpell(myCharacter, spell.id) then
          skip = true
        end

        if not skip then
          local healthCheck = config.healthPercent or 0
          if healthCheck > 0 and percentageHealth < healthCheck then skip = true end
        end

        if not skip then
          local manaCheck = config.percent or 0
          if manaCheck > 0 and percentageMana < manaCheck then skip = true end
        end

        if not skip and _Helper.isSpellOnCooldown and _Helper.isSpellOnCooldown(spell) then
          skip = true
        end

        if not skip then
          local buffDuration = HelperSpellData.getBuffDuration and HelperSpellData.getBuffDuration(spell.id) or 0
          if buffDuration > 0 and activeBuffs[spell.id] and activeBuffs[spell.id] > now then
            skip = true
          end
        end

        if not skip then
          local creaturesNeeded = config.creatures or 0
          local creaturesMet
          if config.countLowerThan then
            creaturesMet = creaturesAround >= 1 and creaturesAround <= creaturesNeeded
          else
            creaturesMet = creaturesAround >= creaturesNeeded
          end
          if not creaturesMet then skip = true end
        end

        if not skip then
          return true
        end
      end
    end
  end

  return false
end

-- ===== FUNCOES DE ATUALIZACAO DE CONFIG =====

-- Atualiza o percentual de mana para spell
_Helper.MagicShooter.updatePercent = function(buttonId, newPercent)
  local buttonIndex = string.match(buttonId, "%d+")
  if not buttonIndex then
    return
  end

  local getShooterProfile = _Helper.getShooterProfile
  local profile = getShooterProfile and getShooterProfile()
  if not profile then return end

  local shooterPanel = _Helper.getShooterPanel and _Helper.getShooterPanel()
  if not shooterPanel then return end

  buttonIndex = tonumber(buttonIndex)
  local config = profile.spells[buttonIndex + 1]
  local label = shooterPanel:recursiveGetChildById("spellPercentLabel" .. buttonIndex)

  if string.find(buttonId, "add") then
    if config.percent >= 99 then
      shooterPanel:recursiveGetChildById("addPercentButton" .. buttonIndex):setEnabled(false)
      return
    end

    config.percent = config.percent + 1
    label:setText(config.percent .. "%")

    if config.percent >= 99 then
      shooterPanel:recursiveGetChildById("addPercentButton" .. buttonIndex):setEnabled(false)
    end

    shooterPanel:recursiveGetChildById("rmvPercentButton" .. buttonIndex):setEnabled(true)
  elseif string.find(buttonId, "rmv") then
    if config.percent <= 1 then
      shooterPanel:recursiveGetChildById("rmvPercentButton" .. buttonIndex):setEnabled(false)
      return
    end

    config.percent = config.percent - 1
    label:setText(config.percent .. "%")

    if config.percent <= 1 then
      shooterPanel:recursiveGetChildById("rmvPercentButton" .. buttonIndex):setEnabled(false)
    end

    shooterPanel:recursiveGetChildById("addPercentButton" .. buttonIndex):setEnabled(true)
  end
  _Helper.MagicShooter.rebuildCache()
end

-- Atualiza a prioridade de spell
_Helper.MagicShooter.updatePriority = function(index, priority)
  local getShooterProfile = _Helper.getShooterProfile
  local profile = getShooterProfile and getShooterProfile()
  if profile then
    profile.spells[index + 1].priority = tonumber(priority)
  end
  _Helper.MagicShooter.rebuildCache()
end

-- Atualiza a quantidade de criaturas para spell
_Helper.MagicShooter.updateCreatures = function(name, index, creatures)
  local getShooterProfile = _Helper.getShooterProfile
  local profile = getShooterProfile and getShooterProfile()
  if profile then
    profile.spells[index + 1].creatures = tonumber(creatures)
  end
  _Helper.MagicShooter.rebuildCache()
end

-- Toggle self cast
_Helper.MagicShooter.toggleSelfCast = function(index, checked)
  local getShooterProfile = _Helper.getShooterProfile
  local profile = getShooterProfile and getShooterProfile()
  if profile then
    profile.spells[index + 1].selfCast = checked
  end
  _Helper.MagicShooter.rebuildCache()
end

-- Atualiza a quantidade de criaturas para rune
_Helper.MagicShooter.updateRuneCreatures = function(name, index, creatures)
  local getShooterProfile = _Helper.getShooterProfile
  local profile = getShooterProfile and getShooterProfile()
  if profile then
    profile.runes[index + 1].creatures = tonumber(creatures)
  end
  _Helper.MagicShooter.rebuildCache()
end

-- Atualiza a prioridade de rune
_Helper.MagicShooter.updateRunePriority = function(index, priority)
  local getShooterProfile = _Helper.getShooterProfile
  local profile = getShooterProfile and getShooterProfile()
  if profile then
    profile.runes[index + 1].priority = tonumber(priority)
  end
  _Helper.MagicShooter.rebuildCache()
end

-- ===== FUNCOES DE PROFILE =====
-- loadProfileOptions, togglePreset, removeProfile now handled by presetManager
-- Only loadProfileByName remains here (module-specific logic)

-- Compatibility wrapper: delegates to presetManager
_Helper.MagicShooter.togglePreset = function(widget, hideMessage)
  local pm = modules.game_helper and modules.game_helper.presetManager
  if pm then
    local ctx = pm.getShooterContext() or pm.buildShooterContext()
    if ctx then pm.togglePreset(ctx, widget, hideMessage) end
  end
end

_Helper.MagicShooter.loadProfileOptions = function()
  local pm = modules.game_helper and modules.game_helper.presetManager
  if pm then
    local ctx = pm.getShooterContext() or pm.buildShooterContext()
    if ctx then pm.loadProfileOptions(ctx) end
  end
end

_Helper.MagicShooter.removeProfile = function()
  local pm = modules.game_helper and modules.game_helper.presetManager
  if pm then
    local ctx = pm.getShooterContext() or pm.buildShooterContext()
    if ctx then pm.removeProfile(ctx) end
  end
end

-- Carrega um profile pelo nome
_Helper.MagicShooter.loadProfileByName = function(profileName)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local getShooterProfile = _Helper.getShooterProfile
  local enableButtons = _Helper.getEnableButtons and _Helper.getEnableButtons()
  local shooterPanel = _Helper.getShooterPanel and _Helper.getShooterPanel()
  local runePanel = _Helper.getRunePanel and _Helper.getRunePanel()
  local numberToOrdinal = _Helper.numberToOrdinal
  local removeAction = _Helper.removeAction

  if not helperConfig then return end

  helperConfig.selectedShooterProfile = profileName
  local profile = getShooterProfile and getShooterProfile()
  if not profile then
    return
  end

  -- Rebuild cache for the loaded profile
  _Helper.MagicShooter.rebuildCache()

  -- Refresh the magic shooter panel UI (clear form + update rules list)
  local panelModule = modules.game_helper and modules.game_helper.magicShooter
  if panelModule then
    if panelModule.clearForm then panelModule.clearForm() end
    if panelModule.updateRulesList then panelModule.updateRulesList() end
    if panelModule.loadIgnoreMonsterList then panelModule.loadIgnoreMonsterList() end
    if panelModule.loadPriorityMonsterList then panelModule.loadPriorityMonsterList() end
  end

  local autoTargetModes = _Helper.AutoTarget and _Helper.AutoTarget.getModes and _Helper.AutoTarget.getModes() or {}

  if profile.autoTargetMode then
    helperConfig.autoTargetMode = profile.autoTargetMode
    if enableButtons then
      local autoTargetMode = enableButtons:recursiveGetChildById("autoTargetMode")
      if autoTargetMode then
        for k, v in pairs(autoTargetModes) do
          if v == profile.autoTargetMode then
            autoTargetMode:setCurrentOption(k)
            break
          end
        end
      end
    end
  end

  if not shooterPanel then return end

  for k, v in pairs(profile.spells) do
    if v.id <= 0 then
      if removeAction then
        removeAction("shooter", shooterPanel:recursiveGetChildById("attackSpellButton" .. k - 1))
      end
    else
      local button = shooterPanel:recursiveGetChildById("attackSpellButton" .. k - 1)
      local minCreatures = shooterPanel:recursiveGetChildById("countMinCreature" .. k - 1)
      local priority = shooterPanel:recursiveGetChildById("priority" .. k - 1)
      local selfCast = shooterPanel:recursiveGetChildById("selfCast" .. k - 1)
      if priority then priority:setCurrentOption(numberToOrdinal and numberToOrdinal(v.priority) or tostring(v.priority)) end
      if minCreatures then minCreatures:setCurrentOption(tostring(v.creatures) .. "+") end
      local spell = Spells.getSpellDataById(v.id)
      if spell and button then
        _Helper.setSpellIcon(button, spell.id)
        button:setBorderColorTop("#1b1b1b")
        button:setBorderColorLeft("#1b1b1b")
        button:setBorderColorRight("#757575")
        button:setBorderColorBottom("#757575")
        button:setBorderWidth(1)
        button:setTooltip("Spell: " .. Spells.getSpellNameByWords(spell.words) .. "\nWords: " .. spell.words)

        local bothCastTypeSpells = _Helper.MagicShooter.getBothCastTypeSpells()
        if table.contains(bothCastTypeSpells, spell.id) then
          if not selfCast then
            selfCast = g_ui.createWidget('CheckBox', minCreatures:getParent())
            if selfCast then
              local style = {
                ["width"] = 12,
                ["anchors.top"] = "countMinCreature" .. k - 1 .. ".top",
                ["anchors.left"] = "countMinCreature" .. k - 1 .. ".right",
                ["margin-top"] = 6,
                ["margin-left"] = 5
              }
              selfCast:mergeStyle(style)
              selfCast:setId('selfCast' .. k - 1)
              selfCast:setTooltip('Cast On Foot')
              selfCast:setVisible(true)
              selfCast:setChecked(v.selfCast)
              selfCast.onCheckChange = function()
                _Helper.MagicShooter.toggleSelfCast(selfCast:getId():match("%d+"),
                  selfCast:isChecked())
              end
            end
          end
        end
        if minCreatures and (spell.range > 0 or not spell.area) and not table.contains(bothCastTypeSpells, spell.id) then
          minCreatures:setCurrentOption("1+")
          minCreatures:disable()
          v.creatures = 1
        else
          minCreatures:setEnabled(true)
          minCreatures:setCurrentOption(tostring(v.creatures) .. "+")
        end
      end
      local percentOption = shooterPanel:recursiveGetChildById("spellPercentLabel" .. k - 1)
      if percentOption then
        percentOption:setText(tostring(v.percent) .. "%")
      end
      if v.percent <= 1 then
        local rmvBtn = shooterPanel:recursiveGetChildById("rmvPercentButton" .. k - 1)
        if rmvBtn then rmvBtn:setEnabled(false) end
      elseif v.percent >= 99 then
        local addBtn = shooterPanel:recursiveGetChildById("addPercentButton" .. k - 1)
        if addBtn then addBtn:setEnabled(false) end
      end
    end
  end

  if not runePanel then return end

  for k, v in pairs(profile.runes) do
    if v.id <= 0 then
      if removeAction then
        removeAction("rune", runePanel:recursiveGetChildById("runeShooterButton" .. k - 1))
      end
    else
      local button = runePanel:recursiveGetChildById("runeShooterButton" .. k - 1)
      if button.runeItem then
        button.runeItem:destroy()
      end
      local itemWidget = g_ui.createWidget('RuneItem', button)
      itemWidget:setItemId(v.id)
      itemWidget:setId('runeItem')
      local creaturesMin = runePanel:recursiveGetChildById("countMinCreature" .. k - 1)
      creaturesMin:setCurrentOption(tostring(v.creatures) .. "+")
      local rune = Spells.getRuneSpellByItem(v.id)
      if not rune and CustomRuneIds then rune = CustomRuneIds[v.id] end
      _Helper.resolveCustomRuneArea(rune)
      if rune then
        if not rune.area then
          creaturesMin:disable()
        else
          creaturesMin:setEnabled(true)
          creaturesMin:setCurrentOption(tostring(v.creatures) .. "+")
        end
        button:setTooltip(string.format(rune.name .. " %s", rune.area and "(Area Damage)" or "(Single Damage)"))
      end
      local priorityOption = runePanel:recursiveGetChildById("runePriority" .. k - 1)
      priorityOption:setCurrentOption(numberToOrdinal and numberToOrdinal(v.priority) or tostring(v.priority))
    end
  end

  -- Save the selected profile to persist across sessions
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
end

-- ===== GETTERS =====

-- Retorna bothCastTypeSpells
_Helper.MagicShooter.getBothCastTypeSpells = function()
  return bothCastTypeSpells
end

-- Expose pure helpers for tests (and any external caller that needs them).
_Helper.MagicShooter.parseRangedMonsterNames = parseRangedMonsterNames
_Helper.MagicShooter.isExposeWeaknessSpell   = isExposeWeaknessSpell
_Helper.MagicShooter.isSapStrengthSpell      = isSapStrengthSpell

-- Mirror the engine table into the shared `modules` namespace so test code
-- (running outside this sandbox) can reach it.
modules.game_helper = modules.game_helper or {}
modules.game_helper.magicShooterEngine = _Helper.MagicShooter

-- ===== FIM HELPER MAGIC SHOOTER =====
