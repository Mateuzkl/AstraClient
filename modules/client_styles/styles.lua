local resourceLoaders = {
    ["otui"] = g_ui.importStyle,
    ["otfont"] = g_fonts.importFont,
    ["otps"] = g_particles.importParticle,
}

function init()
    local function safeCall(name, callback)
        local ok, err = pcall(callback)
        if not ok then
            g_logger.warning("[client_styles] " .. name .. ": " .. tostring(err))
        end
    end

    safeCall("import otfonts", function()
        importResources("fonts", "otfont")
    end)
    -- Outline fonts (.ttf/.otf) belong to RmlUi, not the OTUI bitmap loader.
    safeCall("import styles", function()
        importResources("styles", "otui")
    end)
    safeCall("import particles", function()
        importResources("particles", "otps")
    end)
    safeCall("load cursors", function()
        g_mouse.loadCursors('/data/cursors/cursors')
        local layout = g_resources.getLayout()
        if layout and layout:len() > 0 and g_resources.fileExists('/layouts/' .. layout .. '/cursors/cursors.otml') then
            g_mouse.loadCursors('/layouts/' .. layout .. '/cursors/cursors')
        end
    end)
end

function terminate()
end

function importResources(dir, type)
    local loader = resourceLoaders[type]
    if not loader then
        return
    end

    local dataByRel = {}
    local layoutByRel = {}
    local seenRel = {}
    local orderedRel = {}

    local function collectFrom(baseRoot, currentDir, targetMap)
        if not g_resources.directoryExists(currentDir) then
            return
        end
        local files = g_resources.listDirectoryFiles(currentDir, true, true)
        for _, file in pairs(files) do
            if g_resources.isFileType(file, type) then
                local rel = file:sub(#baseRoot + 1)
                if not seenRel[rel] then
                    seenRel[rel] = true
                    table.insert(orderedRel, rel)
                end
                targetMap[rel] = file
            elseif g_resources.directoryExists(file) then
                collectFrom(baseRoot, file, targetMap)
            end
        end
    end

    -- Load base /data/<dir> first, then apply /layouts/<layout>/<dir> overrides on top
    -- so styles added to /data/styles remain available while layout overrides still win.
    local dataRoot = '/data/' .. dir
    collectFrom(dataRoot, dataRoot, dataByRel)

    local layout = g_resources.getLayout()
    if layout and layout:len() > 0 then
        local layoutRoot = '/layouts/' .. layout .. '/' .. dir
        collectFrom(layoutRoot, layoutRoot, layoutByRel)
    end

    table.sort(orderedRel)
    for _, rel in ipairs(orderedRel) do
        if dataByRel[rel] then
            loader(dataByRel[rel])
        end
        if layoutByRel[rel] then
            loader(layoutByRel[rel])
        end
    end
end

function reloadParticles()
    g_particles.terminate()
    importResources("particles", "otps")
end
