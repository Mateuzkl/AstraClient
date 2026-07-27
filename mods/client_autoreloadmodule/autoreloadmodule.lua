local moduleReloadEvents = {}
local otmlReloadEvent

local function removeTrackedEvent(event)
  if event then
    removeEvent(event)
  end
end

local function stopReloadEvents()
  for _, event in pairs(moduleReloadEvents) do
    removeTrackedEvent(event)
  end

  moduleReloadEvents = {}

  removeTrackedEvent(otmlReloadEvent)
  otmlReloadEvent = nil
end

local function printReloadError(message)
  pcolored(message, 'red')
end

local function refreshFileTimes(files)
  for filepath in pairs(files) do
    local fileTime = g_resources.getFileTime(filepath)
    if fileTime > 0 then
      files[filepath] = fileTime
    end
  end
end

local function liveModuleReload(module)
  if not module or not module:isReloadble() or not module:canReload() then
    return nil
  end

  local name = module:getName()
  local files = {}

  for _, filepath in pairs(g_resources.listDirectoryFiles('/' .. name, true, false, true)) do
    local fileTime = g_resources.getFileTime(filepath)
    if fileTime > 0 then
      files[filepath] = fileTime
    end
  end

  if not next(files) then
    printReloadError('ERROR: unable to find any file for module(' .. name .. ')')
    return nil
  end

  return cycleEvent(function()
    for filepath, previousTime in pairs(files) do
      local currentTime = g_resources.getFileTime(filepath)

      if currentTime > 0 and currentTime ~= previousTime then
        pcolored('Reloading ' .. name, 'green')

        local terminal = modules.client_terminal
        if terminal and terminal.flushLines then
          terminal.flushLines()
        end

        local ok, err = pcall(function()
          module:reload()
        end)

        if not ok then
          printReloadError('ERROR: unable to reload module(' .. name .. '): ' .. tostring(err))
          files[filepath] = currentTime
          return
        end

        -- Refresh every timestamp so multiple files changed together trigger
        -- only one module reload.
        refreshFileTimes(files)

        if name == 'client_terminal' then
          terminal = modules.client_terminal
          if terminal and terminal.show then
            terminal.show()
          end
        end

        return
      end
    end
  end, 1000)
end

function init()
  stopReloadEvents()

  if not AUTO_RELOAD_MODULE then
    return
  end

  for _, module in ipairs(g_modules.getModules()) do
    local event = liveModuleReload(module)
    if event then
      moduleReloadEvents[module:getName()] = event
    end
  end

  local otmlPath = '/data/game.otml'
  local otmlTime = g_resources.getFileTime(otmlPath)

  otmlReloadEvent = cycleEvent(function()
    local currentTime = g_resources.getFileTime(otmlPath)

    if currentTime > 0 and currentTime ~= otmlTime then
      pcolored('Reloading Game OTML')

      local ok, err = pcall(function()
        g_things.loadOtml(otmlPath)
      end)

      if not ok then
        printReloadError('ERROR: unable to reload Game OTML: ' .. tostring(err))
      end

      otmlTime = currentTime
    end
  end, 1000)
end

function terminate()
  stopReloadEvents()
end
