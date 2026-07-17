local highscoresWindow
local gameworldbox
local vocationbox
local categorybox
local highscoreTable
local renderEvent
local renderGeneration = 0
local worldOptionsSignature
local vocationOptionsSignature
local categoryOptionsSignature

local pvpTypesById = {
  ["openPvpCheck"] = 0,
  ["optionalPvpCheck"] = 1,
  ["hardcorePvpCheck"] = 2,
  ["retroOpenPvpCheck"] = 3,
  ["retroHardcorePvpCheck"] = 4,
}

local function cancelRender()
  renderGeneration = renderGeneration + 1
  if renderEvent then
    removeEvent(renderEvent)
    renderEvent = nil
  end
end

local function scheduleRender(generation, callback)
  renderEvent = scheduleEvent(function()
    renderEvent = nil
    if generation ~= renderGeneration or not highscoresWindow or highscoresWindow:isDestroyed() then
      return
    end
    callback()
  end, 1)
end

local function getOptionsSignature(options, prefix)
  local values = {}
  for id, name in pairs(options) do
    values[#values + 1] = tostring(id) .. "=" .. tostring(name)
  end
  table.sort(values)
  return (prefix or "") .. table.concat(values, "\31")
end

local function syncOptions(widget, options, signature, includeAll)
  local nextSignature = getOptionsSignature(options, includeAll and "all:" or "")
  if signature ~= nextSignature then
    widget:clearOptions()
    if includeAll then
      widget:addOption("All Game Worlds")
    end
    for _, option in pairs(options) do
      widget:addOption(option)
    end
  end
  return nextSignature
end

function init()
  highscoresWindow = g_ui.displayUI('highscores')
  highscoresWindow:hide()

  connect(g_game, {
    onGameEnd = offline,
    onHighscores = onHighscores,
  })

  initInterface()
end

function terminate()
  cancelRender()
  disconnect(g_game, {
    onGameEnd = offline,
    onHighscores = onHighscores,
  })

  if highscoresWindow then
    highscoresWindow:destroy()
    highscoresWindow = nil
  end
end

function hide()
  highscoresWindow:hide()
  g_client.setInputLockWidget(nil)
  modules.game_sidebuttons.setButtonVisible("highscoresDialog", false)
end

function show()
  highscoresWindow:show(true)
  highscoresWindow:focus()
  g_client.setInputLockWidget(highscoresWindow)
  modules.game_sidebuttons.setButtonVisible("highscoresDialog", true)
  g_game.highscore(0, 0, 0xFFFFFFFF, g_game.getWorldName(), 1, 20)
end

function offline()
  cancelRender()
  if modules.game_sidebuttons.isButtonVisible("highscoresDialog") then
    modules.game_sidebuttons.setButtonVisible("highscoresDialog", false)
  end
  hide()
end

function initInterface()
  highscoreTable = highscoresWindow.highscoreList
  gameworldbox = highscoresWindow.filters.gameworldbox
  vocationbox = highscoresWindow.filters.vocationbox
  categorybox = highscoresWindow.filters.categorybox
end

local function getHours(seconds)
  return math.floor((seconds/60)/60)
end

local function getMinutes(seconds)
  return math.floor(seconds/60)
end

local function getSeconds(seconds)
  return seconds%60
end

local function getTimeinWords(secs)
  local hours, minutes, seconds = getHours(secs), getMinutes(secs), getSeconds(secs)
  if (minutes > 59) then
    minutes = minutes-hours*60
  end

  local timeStr = ''

  if hours > 0 then
    timeStr = timeStr .. ' hours '
  end

  if minutes > 0 then
    timeStr = timeStr .. minutes .. ' minutes'
  elseif seconds > 0 then
    timeStr =  seconds .. ' seconds'
  end

  return timeStr
end

local function getIndex(tb, value)
  for index, name in pairs(tb) do
    if name == value then
      return index
    end
  end
  return 1
end

function onHighscores(worlds, selectedWorld, vocations, selectedVocation, categories, selectedCategory, page, pages, characters, lastUpdate)
  cancelRender()
  worldOptionsSignature = syncOptions(gameworldbox, worlds, worldOptionsSignature, true)
  gameworldbox:setCurrentOption(selectedWorld, false)

  vocationOptionsSignature = syncOptions(vocationbox, vocations, vocationOptionsSignature, false)
  vocationbox:setCurrentOption(vocations[selectedVocation], false)

  categoryOptionsSignature = syncOptions(categorybox, categories, categoryOptionsSignature, false)
  categorybox:setCurrentOption(categories[selectedCategory], false)

  local generation = renderGeneration
  local rowIndex = 1
  local totalRows = math.max(20, #characters)
  local function renderRow()
    local widget = highscoreTable:getChildByIndex(rowIndex)
    if not widget then
      widget = g_ui.createWidget('ListHighscore', highscoreTable)
    end

    local character = characters[rowIndex]
    local color = "#c0c0c0"
    if character then
      widget.rank:setText(character[1])
      widget.name:setText(character[2])
      widget.vocation:setText(g_game.getVocationName(character[3]))
      widget.gameworld:setText(short_text(character[4], 8))
      widget.level:setText(character[5])
      widget.points:setText(comma_value(character[7]))
      if character[6] then
        color = "#60f860"
      end
    else
      widget.rank:setText("")
      widget.name:setText("")
      widget.vocation:setText("")
      widget.gameworld:setText("")
      widget.level:setText("")
      widget.points:setText("")
    end

    widget.rank:setColor(color)
    widget.name:setColor(color)
    widget.vocation:setColor(color)
    widget.gameworld:setColor(color)
    widget.level:setColor("#c0c0c0")
    widget.points:setColor(color)
    widget:setBackgroundColor((rowIndex % 2 == 0 and '#484848' or '#414141'))

    rowIndex = rowIndex + 1
    if rowIndex <= totalRows then
      scheduleRender(generation, renderRow)
      return
    end

    local function removeExtraRow()
      if highscoreTable:getChildCount() <= totalRows then
        return
      end
      highscoreTable:getChildByIndex(-1):destroy()
      scheduleRender(generation, removeExtraRow)
    end
    removeExtraRow()
  end
  scheduleRender(generation, renderRow)

  highscoresWindow.page:setText(string.format("%d / %d", page, pages))
  highscoresWindow.page:setColor("#c0c0c0")
  highscoresWindow.lastUpdate:setText("Last Update: "..getTimeinWords(os.time() - lastUpdate) .. " ago")
  highscoresWindow.lastUpdate:setColor("#909090")

  -- buttons
  local m_seletecdWorld = selectedWorld
  if m_seletecdWorld == "All Game Worlds" then
    m_seletecdWorld = ""
  end

  local stringPvpTypes = ""
  for checkboxId, typeId in pairs(pvpTypesById) do
    local checkbox = highscoresWindow:recursiveGetChildById(checkboxId)
    if checkbox and checkbox:isChecked() then
      if stringPvpTypes ~= "" then
        stringPvpTypes = stringPvpTypes .. ","
      end
      stringPvpTypes = stringPvpTypes .. typeId
    end
  end

  highscoresWindow.showOwnRank.onClick = function()
    g_game.highscore(1, getIndex(categories, categorybox:getCurrentOption().text), getIndex(vocations, vocationbox:getCurrentOption().text), m_seletecdWorld, 1, 20, stringPvpTypes)
  end
  highscoresWindow.first.onClick = function()
    g_game.highscore(0, selectedCategory, selectedVocation, m_seletecdWorld, 1, 20, stringPvpTypes)
  end
  highscoresWindow.prevButton.onClick = function()
    g_game.highscore(0, selectedCategory, selectedVocation, m_seletecdWorld, math.max(1, page -1), 20, stringPvpTypes)
  end
  highscoresWindow.nextButton.onClick = function()
    g_game.highscore(0, selectedCategory, selectedVocation, m_seletecdWorld, math.min(pages, page +1), 20, stringPvpTypes)
  end
  highscoresWindow.last.onClick = function()
    g_game.highscore(0, selectedCategory, selectedVocation, m_seletecdWorld, pages, 20, stringPvpTypes)
  end


  highscoresWindow.filters.submit.onClick = function()
    local m_seletecdWorld = gameworldbox:getCurrentOption().text
    if m_seletecdWorld == "All Game Worlds" then
      m_seletecdWorld = ""
    end
    g_game.highscore(0, getIndex(categories, categorybox:getCurrentOption().text), getIndex(vocations, vocationbox:getCurrentOption().text), m_seletecdWorld, 1, 20, stringPvpTypes)
  end
end
