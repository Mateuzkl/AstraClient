local reloadEvents = {}
local otmlReloadEvent = nil

local function stopReloadEvents()
    if otmlReloadEvent then
        removeEvent(otmlReloadEvent)
        otmlReloadEvent = nil
    end

    for _, event in ipairs(reloadEvents) do
        removeEvent(event)
    end
    reloadEvents = {}
end

function init()
    if not AUTO_RELOAD_MODULE then
        return
    end

    stopReloadEvents()

    for _, module in ipairs(g_modules.getModules()) do
        local event = live_module_reload(module)
        if event then
            reloadEvents[#reloadEvents + 1] = event
        end
    end

    local otmlPath = '/data/game.otml';
    local otmlTime = g_resources.getFileTime(otmlPath)

    -- otml auto reload
    otmlReloadEvent = cycleEvent(function()
        local newtime = g_resources.getFileTime(otmlPath)
        if newtime > otmlTime then
            pcolored('Reloading Game OTML')
            g_things.loadOtml(otmlPath)
            otmlTime = newtime
        end
    end, 1000)
end

function terminate()
    stopReloadEvents()
end

function live_module_reload(module)
    if not module:isReloadble() or not module:canReload() then
        return
    end

    local name = module:getName()

    local files = {}
    local hasFile = false
    for _, file in pairs(g_resources.listDirectoryFiles('/' .. name, true, false, true)) do
        local time = g_resources.getFileTime(file)
        if time > 0 then
            files[file] = time
            hasFile = true
        end
    end

    if not hasFile then
        pcolored('ERROR: unable to find any file for module(' .. name .. ')', 'red')
        return
    end

    return cycleEvent(function()
        for filepath, time in pairs(files) do
            local newtime = g_resources.getFileTime(filepath)
            if newtime > time then
                pcolored('Reloading ' .. name, 'green')
                modules.client_terminal.flushLines()
                module:reload()
                files[filepath] = newtime

                if name == 'client_terminal' then
                    modules.client_terminal.show()
                end
                break
            end
        end
    end, 1000)
end
