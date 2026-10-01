local bossUIHealth = nil
local bossHealthEvent = nil
local g_timer = 0
local active = false
local generation = 0

local function cancelHealthEvent()
  generation = generation + 1
  if bossHealthEvent then removeEvent(bossHealthEvent) end
  bossHealthEvent = nil
  g_timer = 0
end

function init()
  active = true
  bossUIHealth = g_ui.displayUI('boss_health')
  bossUIHealth:hide()

  connect(g_game, {
    onMonsterHealth = onMonsterHealth,
    onMonsterHealthHide = onMonsterHealthHide,
    onGameStart = hide,
    onGameEnd = hide
  })
end

function terminate()
  active = false
  cancelHealthEvent()

  if bossUIHealth then
      bossUIHealth:destroy()
      bossUIHealth = nil
  end

  disconnect(g_game, {
    onMonsterHealth = onMonsterHealth,
    onMonsterHealthHide = onMonsterHealthHide,
    onGameStart = hide,
    onGameEnd = hide
  })
end

function toggle()
  if not active or not bossUIHealth then return end
  if bossUIHealth:isVisible() then
      bossUIHealth:hide()
  else
      bossUIHealth:show()
  end
end

function show()
  if active and bossUIHealth then bossUIHealth:show() end
end

function hide()
  cancelHealthEvent()
  if bossUIHealth then bossUIHealth:hide() end
end

function decrementBossHealth()
  if not active or not bossUIHealth then return end
  if g_timer > 0 then
    g_timer = g_timer - 1
    local restingTime = g_timer
    if restingTime > 0 then
      bossUIHealth:recursiveGetChildById('timeLabel'):setText(os.date("%M:%S", restingTime))
    else
      bossUIHealth:recursiveGetChildById('timeLabel'):setText("")
    end
  end
end

function onMonsterHealth(monsterId, health, maxhealth, timer)
  if not active or not bossUIHealth then return end
  local monster = g_things.getMonsterList()[monsterId]
  cancelHealthEvent()

  if not monster then return end
  show()

  bossUIHealth:recursiveGetChildById('nameLabel'):setText(string.capitalize(monster[1]))
  bossUIHealth:recursiveGetChildById("outfit"):setOutfit({type = monster[2], auxType = monster[3], head = monster[4], body = monster[5], legs = monster[6], feet = monster[7], addons = monster[8]})

  local percent = health / maxhealth * 100
  bossUIHealth:recursiveGetChildById('monsterLife'):setPercent(percent)
  bossUIHealth:recursiveGetChildById('healthLabel'):setText(string.format("%.2f%%", percent))

  g_timer = timer
  local currentGeneration = generation
  bossHealthEvent = cycleEvent(function()
    if active and currentGeneration == generation then decrementBossHealth() end
  end, 1000)

  local restingTime = g_timer
  if restingTime > 0 then
    bossUIHealth:recursiveGetChildById('timeLabel'):setText(os.date("%M:%S", restingTime))
  else
    bossUIHealth:recursiveGetChildById('timeLabel'):setText("")
  end
end

function onMonsterHealthHide()
  if not active or not bossUIHealth then return end
  cancelHealthEvent()
  local currentGeneration = generation
  bossHealthEvent = scheduleEvent(function()
    if active and currentGeneration == generation then hide() end
  end, 5000)
end
