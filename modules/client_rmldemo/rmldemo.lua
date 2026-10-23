-- RmlUi demo (Ctrl+Shift+R): a free RmlWindow driven by a Lua data model.

local window, model

local function thingsLoaded()
    return g_things and g_things.isDatLoaded and g_things.isDatLoaded() or false
end

-- example ids: classic .dat/.spr (<= 10.x) and protobuf assets (12.x+) use different item ids
local CLASSIC_ITEMS = { { id = 2148, name = 'gold coin' }, { id = 2152, name = 'platinum coin' },
    { id = 2160, name = 'crystal coin' }, { id = 2400, name = 'magic sword' },
    { id = 2472, name = 'magic plate armor' }, { id = 2195, name = 'boots of haste' } }
local PROTOBUF_ITEMS = { { id = 3031, name = 'gold coin' }, { id = 3035, name = 'platinum coin' },
    { id = 3043, name = 'crystal coin' }, { id = 3288, name = 'magic sword' },
    { id = 3366, name = 'magic plate armor' }, { id = 3079, name = 'boots of haste' } }

local function selectedVersion()
    local version = g_game.getClientVersion()
    if version == 0 then version = g_settings.getInteger('client-version') end
    return version
end

local function defaultIds()
    local list = {}
    for _, item in ipairs(selectedVersion() >= 1100 and PROTOBUF_ITEMS or CLASSIC_ITEMS) do
        list[#list + 1] = tostring(item.id)
    end
    return table.concat(list, ', ')
end

local function savedIds()
    local text = g_settings.getString('rmldemo-items')
    return text ~= '' and text or defaultIds()
end

local function savedLookType()
    local text = g_settings.getString('rmldemo-looktype')
    return text ~= '' and text or (selectedVersion() >= 1100 and '128' or '128')
end

local function parseIds(text)
    local items = {}
    for id in text:gmatch('%d+') do
        items[#items + 1] = { id = tonumber(id), name = 'id ' .. id }
        if #items >= 12 then break end
    end
    return items
end

local function exampleItems()
    return parseIds(savedIds())
end

local function assetsHint()
    if thingsLoaded() then return '' end
    return g_rml.utf8(string.format('Sem assets carregados: coloque os arquivos do jogo em data/things/%d/ ' ..
        'e clique em Carregar assets (ou entre no jogo).', selectedVersion()))
end

local function close()
    if window then
        local closing = window
        window = nil
        model = nil
        closing:destroy()
    end
end

local function open()
    if window then
        window:raise()
        window:focus()
        return
    end

    if not Rml.isAvailable() then
        g_logger.warning('RmlUi is not available in this client build')
        return
    end

    window = g_ui.createWidget('RmlWindow', rootWidget)
    window:setId('rmlDemoWindow')
    window:setSize({ width = 600, height = 500 })
    window.onEscape = close
    local owner = window
    connect(owner, {onDestroy = function()
        if window == owner then window = nil; model = nil end
    end})

    -- The model must exist before the document that references it (data-model="demo").
    model = window:getContext():OpenDataModel('demo', {
        title = g_rml.utf8('RmlUi no OTClient'),
        count = 0,
        progress = 0,
        name = '',
        selected = 0,
        thingsLoaded = thingsLoaded(),
        assetsHint = assetsHint(),
        backend = g_rml.getBackendName(),
        items = exampleItems(),
        idsText = savedIds(),
        lookTypeText = savedLookType(),
        lookType = savedLookType(),
        ApplyIds = function()
            g_settings.set('rmldemo-items', model.idsText)
            g_settings.set('rmldemo-looktype', model.lookTypeText)
            model.items = parseIds(model.idsText)
            model.lookType = model.lookTypeText:match('%d+') or ''
        end,
        Add = function(event, delta)
            model.count = model.count + delta
            model.progress = math.max(0, math.min(10, model.count))
        end,
        Select = function(event, id) model.selected = id end,
        Close = function() Rml.close(owner) end,
        LoadAssets = function()
            -- same path as the login screen: game_things loads data/things/<version>/ on version change
            local version = selectedVersion()
            if version == 0 then return end
            Rml.defer(owner, function()
                g_game.setClientVersion(version)
                g_game.setProtocolVersion(version)
            end)
        end,
        ToggleDebugger = function() window:setDebuggerVisible(not window:isDebuggerVisible()) end,
        Reload = function() Rml.defer(owner, function() owner:reloadDocument() end) end,
    })

    window.onRmlUpdate = function()
        if model then
            local loaded = thingsLoaded()
            if model.thingsLoaded ~= loaded then
                model.thingsLoaded = loaded
                model.items = exampleItems()
            end
            local hint = assetsHint()
            if model.assetsHint ~= hint then model.assetsHint = hint end
            local backend = g_rml.getBackendName()
            if model.backend ~= backend then model.backend = backend end
        end
    end

    if not window:loadDocument('/modules/client_rmldemo/rmldemo.rml') then
        close()
        return
    end
    window:focus()
end

function toggle()
    if window then close() else open() end
end

function init()
    g_keyboard.bindKeyDown('Ctrl+Shift+R', toggle)
end

function terminate()
    g_keyboard.unbindKeyDown('Ctrl+Shift+R', toggle)
    close()
end
