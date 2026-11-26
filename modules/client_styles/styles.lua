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
        local layout = (g_resources.getLayout and g_resources.getLayout()) or ""
        if layout:len() > 0 and g_resources.fileExists and g_resources.fileExists('/layouts/' .. layout .. '/cursors/cursors.otml') then
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

    local function collectSorted(baseRoot)
        local collected = {}
        local function visit(currentDir)
            if not g_resources.directoryExists(currentDir) then
                return
            end
            local files = g_resources.listDirectoryFiles(currentDir, true, true)
            for _, file in pairs(files) do
                if g_resources.isFileType(file, type) then
                    table.insert(collected, file)
                elseif g_resources.directoryExists(file) then
                    visit(file)
                end
            end
        end
        visit(baseRoot)
        table.sort(collected)
        return collected
    end

    -- Prefer explicit /data/<dir>, falling back to /<dir>/ for mocked test environments.
    local dataRoot = '/data/' .. dir
    if not g_resources.directoryExists(dataRoot) then
        dataRoot = '/' .. dir .. '/'
    end

    -- Load all base /data/<dir> files first, then apply all /layouts/<layout>/<dir>
    -- overrides afterwards so layout definitions always take precedence regardless of filename.
    for _, file in ipairs(collectSorted(dataRoot)) do
        loader(file)
    end

    local layout = (g_resources.getLayout and g_resources.getLayout()) or ""
    if layout:len() > 0 then
        local layoutRoot = '/layouts/' .. layout .. '/' .. dir
        for _, file in ipairs(collectSorted(layoutRoot)) do
            loader(file)
        end
    end
end

function reloadParticles()
    g_particles.terminate()
    importResources("particles", "otps")
end
