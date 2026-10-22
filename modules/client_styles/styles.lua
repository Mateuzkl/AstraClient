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
    end)
end

function terminate()
end

function importResources(dir, type)
    local loader = resourceLoaders[type]
    if not loader then
        return
    end
    local path = '/' .. dir .. '/'
    if not g_resources.directoryExists(path) then
        return
    end

    local function importFrom(path)
        local files = g_resources.listDirectoryFiles(path, true)
        for _, file in pairs(files) do
            if g_resources.isFileType(file, type) then
                loader(file)
            elseif g_resources.directoryExists(file) then
                importFrom(file)
            end
        end
    end

    importFrom(path)
end

function reloadParticles()
    g_particles.terminate()
    importResources("particles", "otps")
end
