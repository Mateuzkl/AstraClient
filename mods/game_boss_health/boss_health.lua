local bossUIHealth = nil
local bossHealthEvent = nil
local bossHealthTimerEvent = nil
local g_timer = 0

function init()
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
  if bossHealthEvent then
    removeEvent(bossHealthEvent)
    bossHealthEvent = nil
  end

  if bossUIHealth then
      bossUIHealth:destroy()
      bossUIHealth = nil
  end

  if bossHealthTimerEvent then
    bossHealthTimerEvent:cancel()
    bossHealthTimerEvent = nil
  end

  disconnect(g_game, {
    onMonsterHealth = onMonsterHealth,
    onMonsterHealthHide = onMonsterHealthHide,
    onGameStart = hide,
    onGameEnd = hide
  })
end

function toggle()
  if bossUIHealth:isVisible() then
      bossUIHealth:hide()
  else
      bossUIHealth:show()
  end
end

function show()
  bossUIHealth:show()
end

function hide()
  bossUIHealth:hide()

  if bossHealthEvent then
    removeEvent(bossHealthEvent)
    bossHealthEvent = nil
  end

  if bossHealthTimerEvent then
    removeEvent(bossHealthTimerEvent)
    bossHealthTimerEvent = nil
  end
  g_timer = 0
end

function decrementBossHealth()
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
  -- Trackers.getMonsterList() caches the ~2-3k monster map (keyed by client
  -- version) instead of remarshalling it on every boss-HP packet. Fall back to
  -- the raw call if the trackers module isn't loaded so behavior is identical.
  local trackers = modules.game_trackers
  local monsterList = (trackers and trackers.Trackers and trackers.Trackers.getMonsterList())
                      or g_things.getMonsterList()
  local monster = monsterList[monsterId]
  if bossHealthEvent then
    removeEvent(bossHealthEvent)
    bossHealthEvent = nil
    g_timer = 0
  end

  if not monster then return end
  show()

  bossUIHealth:recursiveGetChildById('nameLabel'):setText(string.capitalize(monster[1]))
  bossUIHealth:recursiveGetChildById("outfit"):setOutfit({type = monster[2], auxType = monster[3], head = monster[4], body = monster[5], legs = monster[6], feet = monster[7], addons = monster[8]})

  local percent = health / maxhealth * 100
  bossUIHealth:recursiveGetChildById('monsterLife'):setPercent(percent)
  bossUIHealth:recursiveGetChildById('healthLabel'):setText(string.format("%.2f%%", percent))

  g_timer = timer
  bossHealthEvent = cycleEvent(decrementBossHealth, 1000)

  local restingTime = g_timer
  if restingTime > 0 then
    bossUIHealth:recursiveGetChildById('timeLabel'):setText(os.date("%M:%S", restingTime))
  else
    bossUIHealth:recursiveGetChildById('timeLabel'):setText("")
  end
end

function onMonsterHealthHide()
  if bossHealthEvent then
    removeEvent(bossHealthEvent)
    bossHealthEvent = nil
    g_timer = 0
  end
  bossHealthEvent = scheduleEvent(hide, 5000)
end
