local camViewerWindow
local availableCamsList
local confirmDeleteWindow
local errorWindow

local function getEnterGame()
  return modules.client_entergame and modules.client_entergame.EnterGame or nil
end

local function closeConfirmDeleteWindow()
  if not confirmDeleteWindow then
    return
  end

  confirmDeleteWindow:destroy()
  confirmDeleteWindow = nil
end

local function closeErrorWindow()
  if not errorWindow then
    return
  end

  errorWindow:destroy()
  errorWindow = nil
end

local function isSafeRecordName(fileName)
  return type(fileName) == 'string'
    and fileName ~= ''
    and fileName ~= '.'
    and fileName ~= '..'
    and not fileName:find('[\\/\r\n]')
end

local function listRecordFiles()
  local command
  if g_app.getOs() == 'windows' then
    command = 'dir "records" /B /O:N /A:-D 2>NUL'
  else
    command = 'find records -maxdepth 1 -type f -printf "%f\\n" 2>/dev/null | sort'
  end

  local pipe = io.popen(command)
  if not pipe then
    g_logger.warning('Unable to open the records directory.')
    return {}
  end

  local files = {}
  for fileName in pipe:lines() do
    if isSafeRecordName(fileName) then
      files[#files + 1] = fileName
    end
  end
  pipe:close()

  return files
end

function init()
  camViewerWindow = g_ui.displayUI('client_camviewer')
  if not camViewerWindow then
    g_logger.error('Unable to load client_camviewer.otui.')
    return
  end

  camViewerWindow:hide()
  availableCamsList = camViewerWindow.contentPanel:getChildById('availableCams')

  connect(g_game, {
    onRecordEnd = onRecordEnd
  })
end

function terminate()
  disconnect(g_game, {
    onRecordEnd = onRecordEnd
  })

  closeConfirmDeleteWindow()
  closeErrorWindow()

  if camViewerWindow then
    camViewerWindow:destroy()
    camViewerWindow = nil
  end

  availableCamsList = nil
end

function show()
  if not camViewerWindow then
    return
  end

  load()
  camViewerWindow:show()
  camViewerWindow:raise()
  camViewerWindow:focus()
end

function toggle()
  if not camViewerWindow then
    return
  end

  if camViewerWindow:isVisible() then
    hide()
  else
    show()
  end
end

function hide()
  if camViewerWindow then
    camViewerWindow:hide()
  end
end

function onRecordEnd()
  local enterGame = getEnterGame()
  if enterGame then
    enterGame.show()
  end
end

function load()
  if not availableCamsList then
    return
  end

  availableCamsList:destroyChildren()

  for _, fileName in ipairs(listRecordFiles()) do
    local label = g_ui.createWidget('CamListLabel', availableCamsList)
    label:setText(short_text(formatCamName(fileName), 34))
    label.camName = fileName
  end
end

function formatCamName(fileName)
  if type(fileName) ~= 'string' or fileName == '' then
    return ''
  end

  local nameWithoutExtension = fileName:match('^(.*)%.[^%.]+$') or fileName
  local charName, worldName, year, month, day, hour, min = nameWithoutExtension:match(
    '^(.-)_(.-)_(%d%d%d%d)(%d%d)(%d%d)(%d%d)(%d%d)%d%d$'
  )

  if not charName then
    return nameWithoutExtension
  end

  return string.format(
    '%s | %s [%s/%s/%s | %s:%s]',
    charName,
    worldName,
    day,
    month,
    year,
    hour,
    min
  )
end

function renameCam()
  if not availableCamsList then
    return
  end

  local cam = availableCamsList:getFocusedChild()
  if not cam then
    displayErrorBox(tr('Error'), tr('You must select a recording to rename.'))
    return
  end

  -- Rename logic has not been implemented yet.
end

function deleteCam()
  if not availableCamsList then
    return
  end

  local cam = availableCamsList:getFocusedChild()
  if not cam then
    displayErrorBox(tr('Error'), tr('You must select a recording to delete.'))
    return
  end

  local camName = cam.camName
  if not isSafeRecordName(camName) then
    displayErrorBox(tr('Error'), tr('Invalid recording filename.'))
    return
  end

  closeConfirmDeleteWindow()

  local function cancelDelete()
    closeConfirmDeleteWindow()
  end

  local function confirmDelete()
    closeConfirmDeleteWindow()

    local removed, err = os.remove('records/' .. camName)
    if not removed then
      displayErrorBox(
        tr('Error'),
        tr('Could not delete the recording: %s', tostring(err or 'unknown error'))
      )
      return
    end

    load()
  end

  confirmDeleteWindow = displayGeneralBox(
    tr('Confirm Deletion'),
    tr('Are you sure you want to delete this recording?'),
    {
      { text = tr('Yes'), callback = confirmDelete },
      { text = tr('No'), callback = cancelDelete }
    },
    confirmDelete,
    cancelDelete
  )
end

function playCam()
  if not availableCamsList then
    return
  end

  local cam = availableCamsList:getFocusedChild()
  if not cam then
    closeErrorWindow()
    errorWindow = displayErrorBox(tr('Error'), tr('You must select a recording.'))
    errorWindow.onOk = function()
      errorWindow = nil
      local enterGame = getEnterGame()
      if enterGame then
        enterGame.show()
      end
    end
    return
  end

  local camName = cam.camName
  if not isSafeRecordName(camName) then
    displayErrorBox(tr('Error'), tr('Invalid recording filename.'))
    return
  end

  g_settings.setNode('things', {})
  g_game.playRecord(camName)
end
