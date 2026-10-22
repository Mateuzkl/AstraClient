-- Minimapa em RmlUi: a moldura e os controles são RML; o mapa é o UIMinimap nativo
-- hospedado sobre #minimap-slot com Rml.host (técnica para qualquer widget OTUI pronto).

local M = {}
local SHORTCUT = 'Ctrl+Shift+J' -- Ctrl+Shift+M belongs to the existing full map.

-- área com bastante mapa no minimapa do NWO usado nos testes; troque pela do seu servidor
local DEFAULT_POSITION = { x = 1856, y = 1024, z = 7 }

-- primeiro o minimapa que acompanha os assets, depois o que game_minimap salva ao sair do jogo
-- (esse último só tem o que o seu personagem já explorou)
local function minimapFiles()
    return { string.format('/things/%d/minimap.otmm', g_settings.getInteger('client-version')), '/minimap.otmm' }
end

local function loadMinimap()
    for _, file in ipairs(minimapFiles()) do
        if g_resources.fileExists(file) then
            g_minimap.clean()
            if g_minimap.loadOtmm(file) then return file end
        end
    end
end

local function open()
    local window, model, minimap

    local function startPosition()
        local player = g_game.isOnline() and g_game.getLocalPlayer()
        return player and player:getPosition() or DEFAULT_POSITION
    end

    local function moveTo(pos)
        minimap:setCameraPosition(pos)
        model.goX, model.goY, model.goZ = tostring(pos.x), tostring(pos.y), tostring(pos.z)
    end

    window, model = Rml.createWindow{
        id = 'rmlMinimap',
        document = '/modules/game_rmlminimap/rmlminimap.rml',
        model = 'minimap',
        width = 620,
        height = 520,
        data = {
            loaded = g_game.isOnline(),
            hint = Rml.text(string.format('Sem minimapa: entre no jogo ou coloque um minimap.otmm em data/things/%d/ e clique em Carregar minimapa.',
                g_settings.getInteger('client-version'))),
            position = '', zoom = 0,
            goX = '', goY = '', goZ = '',
            Zoom = function(_, delta)
                if delta > 0 then minimap:zoomIn() else minimap:zoomOut() end
            end,
            Floor = function(_, delta)
                if delta < 0 then minimap:floorUp(1) else minimap:floorDown(1) end
            end,
            Center = function() moveTo(startPosition()) end,
            Go = function()
                local pos = { x = tonumber(model.goX), y = tonumber(model.goY), z = tonumber(model.goZ) }
                if pos.x and pos.y and pos.z then moveTo(pos) end
            end,
            Load = function()
                -- no jogo o game_minimap já carregou e mantém o minimapa atualizado
                if g_game.isOnline() then
                    model.loaded = true
                    moveTo(startPosition())
                    return
                end
                local file = loadMinimap()
                model.loaded = file ~= nil
                if file then moveTo(startPosition()) end
            end,
        },
        onClose = function() M.window = nil end,
    }
    if not window then return nil end

    -- created in Lua (not from a .otui style), so run the class setup ourselves
    minimap = UIMinimap.create()
    minimap:onSetup()
    minimap:setColor('black')
    minimap:setZoom(1) -- starts at the minimum zoom otherwise (1/32 px per tile)
    -- clicking walks the player there; outside the game there is no player
    minimap.onMouseRelease = function(self, pos, button)
        if not g_game.isOnline() then return false end
        return UIMinimap.onMouseRelease(self, pos, button)
    end
    Rml.host(window, 'minimap-slot', minimap)

    if not g_game.isOnline() and loadMinimap() then model.loaded = true end
    moveTo(startPosition())

    -- o rodapé acompanha o minimapa (arrastar com o mouse, roda do mouse)
    connect(window, {
        onRmlUpdate = function()
            local pos = minimap:getCameraPosition()
            if pos then
                local text = string.format('%d, %d, %d', pos.x, pos.y, pos.z)
                if model.position ~= text then model.position = text end
            end
            local zoom = minimap:getZoom()
            if model.zoom ~= zoom then model.zoom = zoom end
        end
    })
    return window
end

function toggle()
    Rml.toggle(M, 'window', open)
end

function init()
    if Rml.isAvailable() then g_keyboard.bindKeyDown(SHORTCUT, toggle) end
end

function terminate()
    g_keyboard.unbindKeyDown(SHORTCUT, toggle)
    if M.window then M.window:destroy() M.window = nil end
end
