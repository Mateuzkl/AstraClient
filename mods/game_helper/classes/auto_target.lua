-- ===== HELPER AUTO TARGET =====
-- Modulo separado para gerenciar o Auto Target do Helper

-- Garante que _Helper existe (sera definido em helper.lua, mas pode ser carregado antes)
if not _Helper then
  _Helper = {}
end

_Helper.AutoTarget = {}
_Helper.AutoTarget.monsterCount = 0

-- ===== CONFIGURACOES LOCAIS =====

local autoTargetModes = {
  ["A"] = 1, -- Closest
  ["B"] = 2, -- Farthest
  ["C"] = 3, -- Lowest Health
  ["D"] = 4, -- Highest Health
  ["E"] = 5, -- Best (most creatures in area)
  ["F"] = 6, -- Closest + Lowest Health (default)
  ["G"] = 7, -- Closest + Highest Health
  ["H"] = 8, -- Farthest + Lowest Health
  ["I"] = 9, -- Farthest + Highest Health
  ["J"] = 10 -- My Priority and Ordered List
}

-- Optimization Caches
local reusableCreatureList = {}
local reusableMonsters = {}
local reusableEntries = {}
for i=1,100 do reusableEntries[i] = {position={x=0,y=0,z=0}, creature=nil} end
local reusableTargets = {
  closest = { id = nil, distance = 99 },
  farthest = { id = nil, distance = -1 },
  lowestHealth = { id = nil, health = 100 },
  highestHealth = { id = nil, health = -1 },
  best = { id = nil, creatures = 0 },
  closestLowestHealth = { id = nil, distance = 99, health = 100 },
  closestHighestHealth = { id = nil, distance = 99, health = -1 },
  farthestLowestHealth = { id = nil, distance = -1, health = 100 },
  farthestHighestHealth = { id = nil, distance = -1, health = -1 }
}

-- ===== FUNCOES DO AUTO TARGET =====

-- Retorna se o auto target esta ativo
_Helper.AutoTarget.isActive = function()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    return helperConfig.autoTargetEnabled
  end
  return false
end

-- Toggle para habilitar/desabilitar o Auto Target
_Helper.AutoTarget.toggle = function(widget)
  local shooterPanel = _Helper.getShooterPanel and _Helper.getShooterPanel()
  local enableButtons = _Helper.getEnableButtons and _Helper.getEnableButtons()

  if not widget then
    if shooterPanel then
      widget = shooterPanel:recursiveGetChildById("enableAutoTarget")
    elseif enableButtons then
      widget = enableButtons:recursiveGetChildById("enableAutoTarget")
    end
    if not widget then
      return
    end
    widget:setChecked(not widget:isChecked())
  end


  -- Se estiver tentando ativar e autoTargetOnHold esta travado, destrava
  local autoTargetOnHold = _Helper.getAutoTargetOnHold and _Helper.getAutoTargetOnHold()
  if widget:isChecked() and autoTargetOnHold then
    if _Helper.setAutoTargetOnHold then
      _Helper.setAutoTargetOnHold(false)
    end
  end

  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.autoTargetEnabled = widget:isChecked()

    if not helperConfig.autoTargetEnabled then
      helperConfig.currentLockedTargetId = 0
      g_game.cancelAttack()
    else
      -- Quando ativar, buscar e atacar um alvo imediatamente
      scheduleEvent(function()
        _Helper.AutoTarget.check()
      end, 1000)
    end
  end

  if not _Helper._suppressMessages then
    modules.game_textmessage.displayGameMessage(
      string.format("Auto Target is %s.", (helperConfig and helperConfig.autoTargetEnabled and "enabled" or "disabled"))
    )
  end

  -- Sincronizar com shortcut panel
  if _Helper.Shortcut and _Helper.Shortcut.syncButton then
    _Helper.Shortcut.syncButton('shortcutAutoTarget', helperConfig and helperConfig.autoTargetEnabled)
  end

  -- Salvar configuracao
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
end

-- Atualiza o modo de auto target
_Helper.AutoTarget.updateMode = function(mode)
  local modeId = autoTargetModes[mode]
  if not modeId then
    return
  end

  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.autoTargetMode = modeId
  end

  local getShooterProfile = _Helper.getShooterProfile
  if getShooterProfile then
    local profile = getShooterProfile()
    if profile then
      profile.autoTargetMode = modeId
    end
  end

  -- Priority list visibility, the enableAutoTarget anchor and the panel height
  -- are one decision, and it also depends on whether the Advanced block is
  -- open -- which this module cannot see. The targeting panel owns it.
  local magicShooter = modules.game_helper and modules.game_helper.magicShooter
  if magicShooter and magicShooter.applyTargetingLayout then
    magicShooter.applyTargetingLayout(mode)
  end

  -- Salvar configuracao
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
end

-- Valida se uma criatura pode ser alvo do auto target
_Helper.AutoTarget.isValidCreature = function(creature)
  if not creature:isMonster() then return false end
  if creature:getMasterId() ~= 0 then return false end
  if creature:getHealthPercent() <= 0 then return false end
  return true
end

-- O servidor manda o nome com o nivel colado: AddCreature envia
-- "Nameless Woe [25]" para qualquer monstro com level > 0, e o nome puro para os
-- de level 0. Comparar o nome cru contra a lista digitada pelo jogador so batia
-- nos monstros sem level, entao qualquer conteudo com level (custom da Eloria,
-- bosses) nunca entrava nem na whitelist nem na lista de ignorados.
_Helper.AutoTarget.stripCreatureLevel = function(name)
  if not name then return nil end
  return (name:gsub("%s*%[%d+%]%s*$", ""))
end

-- Verifica se uma criatura está na lista de ignorados (centralized check)
-- Deve ser chamada ANTES de qualquer seleção/validação de alvo
_Helper.AutoTarget.isIgnoredCreature = function(creature, ignoreTable)
  if not creature then return true end
  local creatureName = _Helper.AutoTarget.stripCreatureLevel(creature:getName())
  if not creatureName then return false end
  -- Use provided table or fetch fresh one
  ignoreTable = ignoreTable or (_Helper.getIgnoreMonsterTable and _Helper.getIgnoreMonsterTable() or {})
  return ignoreTable[creatureName:lower()] == true
end

-- Verifica se a criatura esta na whitelist de alvos.
-- targetTable == nil significa "atacar todos os monstros" (modo simples, "*").
_Helper.AutoTarget.isTargetedCreature = function(creature, targetTable)
  if not creature then return false end
  if targetTable == nil then return true end

  local creatureName = _Helper.AutoTarget.stripCreatureLevel(creature:getName())
  if not creatureName then return false end
  return targetTable[creatureName:lower()] == true
end

-- Coleta e filtra monstros visiveis (reach, sight, ignore list, target list)
-- Reutilizada por check() e countVisibleMonsters()
_Helper.AutoTarget.gatherMonsters = function(playerPosition)
  local myCharacter = g_game.getLocalPlayer()
  if not myCharacter then
    for k in pairs(reusableCreatureList) do reusableCreatureList[k] = nil end
    for k in pairs(reusableMonsters) do reusableMonsters[k] = nil end
    _Helper.AutoTarget.monsterCount = 0
    return reusableMonsters, reusableCreatureList, nil
  end

  local position = playerPosition or myCharacter:getPosition()
  local spectators = _Helper.getSpectators and _Helper.getSpectators() or {}
  local ignoreTable = _Helper.getIgnoreMonsterTable and _Helper.getIgnoreMonsterTable() or {}
  local targetTable = _Helper.getTargetMonsterTable and _Helper.getTargetMonsterTable() or nil
  local isWithinReach = _Helper.isWithinReach

  -- Build creature list with positions
  for k in pairs(reusableCreatureList) do reusableCreatureList[k] = nil end
  local creatureList = reusableCreatureList

  -- Diagnostic: set _Helper.AutoTarget.debugTargetName to a monster name (lower
  -- case, no level suffix) and every rejection for it is printed with the exact
  -- gate that dropped it. Costs nothing while the field is nil.
  local debugName = _Helper.AutoTarget.debugTargetName
  if debugName then
    for _, creature in pairs(spectators) do
      local nm = _Helper.AutoTarget.stripCreatureLevel(creature:getName() or "")
      if nm and nm:lower() == debugName then
        local why
        if not creature:isMonster() then why = "isMonster()==false"
        elseif creature:getMasterId() ~= 0 then why = "masterId=" .. tostring(creature:getMasterId())
        elseif creature:getHealthPercent() <= 0 then why = "healthPercent=" .. tostring(creature:getHealthPercent())
        elseif not (isWithinReach and isWithinReach(position, creature:getPosition())) then why = "out of reach"
        elseif _Helper.AutoTarget.isIgnoredCreature(creature, ignoreTable) then why = "on ignore list"
        elseif not _Helper.AutoTarget.isTargetedCreature(creature, targetTable) then why = "not on target list"
        elseif not g_map.isSightClear(position, creature:getPosition()) then
          why = "PASSES (sight blocked, targeted anyway)"
        else why = "PASSES every gate" end
        print(string.format("[AutoTarget] %s (id=%d): %s", creature:getName(), creature:getId(), why))
      end
    end
  end

  for _, creature in pairs(spectators) do
    if _Helper.AutoTarget.isValidCreature(creature) then
      local creaturePos = creature:getPosition()
      if creaturePos then
        local entry = reusableEntries[#creatureList + 1]
        if not entry then
          entry = {position={x=0,y=0,z=0}, creature=nil}
          reusableEntries[#creatureList + 1] = entry
        end
        entry.position.x = creaturePos.x
        entry.position.y = creaturePos.y
        entry.position.z = creaturePos.z
        entry.creature = creature
        table.insert(creatureList, entry)
      end
    end
  end

  -- Filter by reach, sight, ignore list
  for k in pairs(reusableMonsters) do reusableMonsters[k] = nil end
  local monsters = reusableMonsters
  local totalOnScreen = 0

  for _, creatureData in pairs(creatureList) do
    if isWithinReach and isWithinReach(position, creatureData.position)
        and not _Helper.AutoTarget.isIgnoredCreature(creatureData.creature, ignoreTable)
        and _Helper.AutoTarget.isTargetedCreature(creatureData.creature, targetTable) then
      totalOnScreen = totalOnScreen + 1
      -- Line of sight decides whether a SPELL can reach something, not whether it
      -- is a valid melee target -- attacking makes the character walk to it. This
      -- used to drop sight-blocked monsters from the list entirely, so anything
      -- standing behind a wall, a platform edge or a pillar was silently never
      -- targeted while the same monster in the open worked fine. The magic shooter
      -- already keeps them and just records the flag (see magic_shooter.lua).
      creatureData.hasSightClear = g_map.isSightClear(position, creatureData.position)
      table.insert(monsters, creatureData.creature)
    end
  end

  _Helper.AutoTarget.monsterCount = totalOnScreen
  return monsters, creatureList, position
end

-- Funcao principal que verifica e seleciona alvo
_Helper.AutoTarget.check = function()
  if modules.game_helper and modules.game_helper.cavebot and
      modules.game_helper.cavebot.isCombatSuppressed and modules.game_helper.cavebot.isCombatSuppressed() then
    if g_game.getAttackingCreature and g_game.getAttackingCreature() then g_game.cancelAttack() end
    return
  end
  local helperAutomaticFunctionsEnabled = _Helper.isHelperAutomaticFunctionsEnabled and
      _Helper.isHelperAutomaticFunctionsEnabled()
  if not helperAutomaticFunctionsEnabled then return end

  -- PZ Guard: handles state transitions and blocks actions while in PZ
  -- Must be called before enabled check to detect PZ exit and restore state
  if _Helper.handlePZState then
    local shouldContinue = _Helper.handlePZState()
    if not shouldContinue then
      return
    end
  end

  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.autoTargetEnabled then return end

  local autoTargetOnHold = _Helper.getAutoTargetOnHold and _Helper.getAutoTargetOnHold()
  if autoTargetOnHold then return end

  -- Follow and attack are one and the same subscription on the wire: Game::attack()
  -- calls cancelFollow() and Game::follow() calls cancelAttack(). Letting both run
  -- would have them cancel each other several times a second and the character would
  -- neither follow nor fight, so Follow Friend wins for as long as it is switched on.
  if _Helper.FollowFriend and _Helper.FollowFriend.isActive and _Helper.FollowFriend.isActive() then
    return
  end

  local myCharacter = g_game.getLocalPlayer()
  if not myCharacter then return end

  local enableButtons = _Helper.getEnableButtons and _Helper.getEnableButtons()

  local afkTime = _Helper.getAfkTime and _Helper.getAfkTime() or 180
  local timer = 0
  if g_ui.getActionTimer then
    timer = g_ui.getActionTimer()
  end
  if timer > afkTime then
    if enableButtons then
      local widget = enableButtons:recursiveGetChildById("enableAutoTarget")
      if widget then
        widget:setChecked(false)
        _Helper.AutoTarget.toggle(widget)
        return
      end
    end
    return
  end

  local position = myCharacter:getPosition()

  -- Fetch ignore list once at the start for consistent use throughout
  local ignoreMonsterTable = _Helper.getIgnoreMonsterTable and _Helper.getIgnoreMonsterTable() or {}
  local isIgnoredCreature = _Helper.AutoTarget.isIgnoredCreature

  local currentLockedTarget = helperConfig.currentLockedTargetId ~= 0 and
      g_map.getCreatureById(helperConfig.currentLockedTargetId) or nil

  local targetMonsterTable = _Helper.getTargetMonsterTable and _Helper.getTargetMonsterTable() or nil
  local isTargetedCreature = _Helper.AutoTarget.isTargetedCreature

  local isWithinReach = _Helper.isWithinReach
  -- Validate current locked target: alive, in reach, not ignored, still on the
  -- target list (the list can change while we are already attacking something)
  if currentLockedTarget and not currentLockedTarget:isDead()
      and isWithinReach and isWithinReach(position, currentLockedTarget:getPosition())
      and not isIgnoredCreature(currentLockedTarget, ignoreMonsterTable)
      and isTargetedCreature(currentLockedTarget, targetMonsterTable) then
    -- Stick to this target until it dies, but never return without confirming we
    -- are really attacking it. The attack can be dropped without the lock being
    -- cleared (target left the screen for a moment, floor change, a cancelAttack
    -- from elsewhere) -- previously that left the lock pointing at a live monster
    -- while the character just stood there, and the bot never attacked again.
    local attacking = g_game.getAttackingCreature()
    if not attacking or attacking:getId() ~= currentLockedTarget:getId() then
      local safeDoThing = _Helper.safeDoThing
      if safeDoThing then safeDoThing(false) end
      g_game.attack(currentLockedTarget)
      if safeDoThing then safeDoThing(true) end
    end
    return
  end

  -- Target died or is gone: drop the lock so a new one can be picked below.
  if helperConfig.currentLockedTargetId ~= 0 then
    helperConfig.currentLockedTargetId = 0
  end

  -- If current target exists but is now ignored, clear it and cancel attack
  if currentLockedTarget and isIgnoredCreature(currentLockedTarget, ignoreMonsterTable) then
    helperConfig.currentLockedTargetId = 0
    g_game.cancelAttack()
  end

  -- Reset reusable targeting tables
  reusableTargets.closest.id = nil; reusableTargets.closest.distance = 99
  reusableTargets.farthest.id = nil; reusableTargets.farthest.distance = -1
  reusableTargets.lowestHealth.id = nil; reusableTargets.lowestHealth.health = 100
  reusableTargets.highestHealth.id = nil; reusableTargets.highestHealth.health = -1
  reusableTargets.best.id = nil; reusableTargets.best.creatures = 0
  reusableTargets.closestLowestHealth.id = nil; reusableTargets.closestLowestHealth.distance = 99; reusableTargets.closestLowestHealth.health = 100
  reusableTargets.closestHighestHealth.id = nil; reusableTargets.closestHighestHealth.distance = 99; reusableTargets.closestHighestHealth.health = -1
  reusableTargets.farthestLowestHealth.id = nil; reusableTargets.farthestLowestHealth.distance = -1; reusableTargets.farthestLowestHealth.health = 100
  reusableTargets.farthestHighestHealth.id = nil; reusableTargets.farthestHighestHealth.distance = -1; reusableTargets.farthestHighestHealth.health = -1

  local closestTarget = reusableTargets.closest
  local farthestTarget = reusableTargets.farthest
  local lowestHealthTarget = reusableTargets.lowestHealth
  local highestHealthTarget = reusableTargets.highestHealth
  local bestTarget = reusableTargets.best
  local closestLowestHealthTarget = reusableTargets.closestLowestHealth
  local closestHighestHealthTarget = reusableTargets.closestHighestHealth
  local farthestLowestHealthTarget = reusableTargets.farthestLowestHealth
  local farthestHighestHealthTarget = reusableTargets.farthestHighestHealth


  -- Gather and filter monsters (shared function)
  local monsters, creatureList = _Helper.AutoTarget.gatherMonsters(position)

  local area = SpellAreas.AREA_CIRCLE3X3
  if myCharacter:isPaladin() then
    area = SpellAreas.AREA_CIRCLE2X2
  end

  local getDistanceBetween = _Helper.getDistanceBetween
  local countAttackableCreatures = _Helper.countAttackableCreatures
  local maxCreaturesHit = 0

  -- Targeting calculations on filtered monsters
  for _, creature in ipairs(monsters) do
    local cPos = creature:getPosition()
    local health = creature:getHealthPercent()
    local creatureId = creature:getId()
    local creatureDistance = getDistanceBetween and getDistanceBetween(position, cPos) or 99

    if lowestHealthTarget.id == nil then
      lowestHealthTarget = { id = creatureId, health = health }
    end
    if health < lowestHealthTarget.health then
      lowestHealthTarget = { id = creatureId, health = health }
    end
    if health > highestHealthTarget.health then
      highestHealthTarget = { id = creatureId, health = health }
    end
    if creatureDistance < closestTarget.distance then
      closestTarget = { id = creatureId, distance = creatureDistance }
    end
    if creatureDistance > farthestTarget.distance then
      farthestTarget = { id = creatureId, distance = creatureDistance }
    end
    if (creatureDistance < closestLowestHealthTarget.distance) or
        (creatureDistance == closestLowestHealthTarget.distance and health < closestLowestHealthTarget.health) then
      closestLowestHealthTarget = { id = creatureId, distance = creatureDistance, health = health }
    end
    if (creatureDistance < closestHighestHealthTarget.distance) or
        (creatureDistance == closestHighestHealthTarget.distance and health > closestHighestHealthTarget.health) then
      closestHighestHealthTarget = { id = creatureId, distance = creatureDistance, health = health }
    end
    if (creatureDistance > farthestLowestHealthTarget.distance) or
        (creatureDistance == farthestLowestHealthTarget.distance and health < farthestLowestHealthTarget.health) then
      farthestLowestHealthTarget = { id = creatureId, distance = creatureDistance, health = health }
    end
    if (creatureDistance > farthestHighestHealthTarget.distance) or
        (creatureDistance == farthestHighestHealthTarget.distance and health > farthestHighestHealthTarget.health) then
      farthestHighestHealthTarget = { id = creatureId, distance = creatureDistance, health = health }
    end
    if countAttackableCreatures then
      local creaturesHit = countAttackableCreatures(cPos, 1, area, creatureList, true)
      if creaturesHit > maxCreaturesHit then
        maxCreaturesHit = creaturesHit
        bestTarget.id = creatureId
        bestTarget.creatures = creaturesHit
      end
    end
  end

  -- Mode J: Priority list targeting
  local priorityListTarget = nil
  if helperConfig.autoTargetMode == autoTargetModes["J"] then
    local priorityList = _Helper.AutoTarget.getPriorityMonsterList()
    local bestPriorityIndex = 999999
    local bestPriorityDistance = 999

    for _, monster in ipairs(monsters) do
      local monsterName = monster:getName()
      if monsterName then
        local lowerName = monsterName:lower()
        for priorityIndex, priorityName in ipairs(priorityList) do
          if lowerName == priorityName then
            local monsterDistance = getDistanceBetween and getDistanceBetween(position, monster:getPosition()) or 99
            -- Select monster with highest priority (lowest index)
            -- If same priority, select closest one
            if priorityIndex < bestPriorityIndex or
                (priorityIndex == bestPriorityIndex and monsterDistance < bestPriorityDistance) then
              bestPriorityIndex = priorityIndex
              bestPriorityDistance = monsterDistance
              priorityListTarget = monster
            end
            break
          end
        end
      end
    end

    -- If no priority monster found, fallback to closest target
    if not priorityListTarget and closestTarget.id then
      priorityListTarget = g_map.getCreatureById(closestTarget.id)
    end
  end

  local currentTarget = g_game.getAttackingCreature()
  local target = nil
  if helperConfig.autoTargetMode == autoTargetModes["A"] then
    target = g_map.getCreatureById(closestTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["B"] then
    target = g_map.getCreatureById(farthestTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["C"] then
    target = g_map.getCreatureById(lowestHealthTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["D"] then
    target = g_map.getCreatureById(highestHealthTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["E"] and bestTarget.id ~= nil then
    target = g_map.getCreatureById(bestTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["F"] then
    target = g_map.getCreatureById(closestLowestHealthTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["G"] then
    target = g_map.getCreatureById(closestHighestHealthTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["H"] then
    target = g_map.getCreatureById(farthestLowestHealthTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["I"] then
    target = g_map.getCreatureById(farthestHighestHealthTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["J"] then
    target = priorityListTarget
  end

  if target and not (currentTarget and currentTarget:getId() == target:getId()) then
    local safeDoThing = _Helper.safeDoThing
    if safeDoThing then safeDoThing(false) end
    g_game.attack(target)
    if safeDoThing then safeDoThing(true) end
  end

  -- Remember what we picked. Nothing used to write this field -- it was only ever
  -- reset to 0 -- so the "keep hitting the same monster" branch above could never
  -- trigger and every tick was free to switch targets.
  if target then
    helperConfig.currentLockedTargetId = target:getId()
  end

  -- Limpeza: remover referências a objetos C++ para permitir GC
  for i = 1, #reusableEntries do
    reusableEntries[i].creature = nil
  end
  for k in pairs(reusableMonsters) do reusableMonsters[k] = nil end
end

-- Reset do checkbox de auto target no UI
_Helper.AutoTarget.resetCheckbox = function()
  local enableButtons = _Helper.getEnableButtons and _Helper.getEnableButtons()
  if not enableButtons then return end

  local enableAutoTarget = enableButtons:recursiveGetChildById("enableAutoTarget")
  if enableAutoTarget then
    enableAutoTarget:setChecked(false)
  end
end

-- Carrega o estado do autoTarget para o UI
_Helper.AutoTarget.loadToUI = function()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local enableButtons = _Helper.getEnableButtons and _Helper.getEnableButtons()
  if not helperConfig or not enableButtons then return end

  local enableAutoTarget = enableButtons:recursiveGetChildById("enableAutoTarget")
  if enableAutoTarget then
    enableAutoTarget:setChecked(helperConfig.autoTargetEnabled or false)
  end

  local currentModeKey = "A"
  local autoTargetMode = enableButtons:recursiveGetChildById("autoTargetMode")
  if autoTargetMode then
    for k, v in pairs(autoTargetModes) do
      if v == helperConfig.autoTargetMode then
        currentModeKey = k
        autoTargetMode:setCurrentOption(k)
        break
      end
    end
  end

  -- See the note in updateMode: the panel owns this decision, because the
  -- priority list must stay hidden while the Advanced block is collapsed no
  -- matter which mode was saved.
  local magicShooter = modules.game_helper and modules.game_helper.magicShooter
  if magicShooter and magicShooter.applyTargetingLayout then
    magicShooter.applyTargetingLayout(currentModeKey)
  end

  -- Load priority monster list text
  local priorityMonsterInput = enableButtons:recursiveGetChildById("priorityMonsterInput")
  if priorityMonsterInput and helperConfig.priorityMonsterList then
    priorityMonsterInput:setText(helperConfig.priorityMonsterList)
  end
end

-- Getter para autoTargetModes (caso outros modulos precisem)
_Helper.AutoTarget.getModes = function()
  return autoTargetModes
end

-- Getter para um modo especifico
_Helper.AutoTarget.getModeId = function(modeKey)
  return autoTargetModes[modeKey]
end

-- Apply priority monster list
_Helper.AutoTarget.applyPriorityList = function()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local enableButtons = _Helper.getEnableButtons and _Helper.getEnableButtons()
  if not helperConfig or not enableButtons then return end

  local priorityMonsterInput = enableButtons:recursiveGetChildById("priorityMonsterInput")
  if not priorityMonsterInput then return end

  local text = priorityMonsterInput:getText() or ""

  -- Remove numbers from input (only letters, spaces and commas allowed)
  local sanitizedText = text:gsub("%d", "")

  -- Update the input field with sanitized text (without numbers)
  if sanitizedText ~= text then
    priorityMonsterInput:setText(sanitizedText)
    modules.game_textmessage.displayGameMessage("Numbers removed from priority list.")
  end

  -- Save the sanitized list
  helperConfig.priorityMonsterList = sanitizedText

  if _Helper.saveSettings then
    _Helper.saveSettings()
  end

  -- Update button state via magic_shooter_panel module
  if modules.game_helper and modules.game_helper.magicShooter and modules.game_helper.magicShooter.loadPriorityMonsterList then
    modules.game_helper.magicShooter.loadPriorityMonsterList()
  end

  modules.game_textmessage.displayGameMessage("Priority monster list applied.")
end

-- Parse priority monster list into ordered array (first = highest priority)
_Helper.AutoTarget.getPriorityMonsterList = function()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.priorityMonsterList then
    return {}
  end

  local priorityList = {}
  local text = helperConfig.priorityMonsterList or ""

  for monsterName in string.gmatch(text, "([^,]+)") do
    -- Trim whitespace and convert to lowercase
    monsterName = monsterName:match("^%s*(.-)%s*$"):lower()
    if monsterName ~= "" then
      table.insert(priorityList, monsterName)
    end
  end

  return priorityList
end

-- Conta monstros visiveis reutilizando gatherMonsters()
_Helper.AutoTarget.countVisibleMonsters = function()
  _Helper.AutoTarget.gatherMonsters()
  return _Helper.AutoTarget.monsterCount
end

-- ===== FIM HELPER AUTO TARGET =====
