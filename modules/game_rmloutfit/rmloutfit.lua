-- Janela de outfit em RmlUi: preview girável, cores por parte, addons e lista de looktypes.
-- No jogo, "Aplicar" envia g_game.changeOutfit; fora dele é só pré-visualização.

local M = {}

local PARTS = { { id = 'head', label = 'Cabeça' }, { id = 'body', label = 'Corpo' },
    { id = 'legs', label = 'Pernas' }, { id = 'feet', label = 'Pés' } }
local DIRECTIONS = { [0] = 'Norte', [1] = 'Leste', [2] = 'Sul', [3] = 'Oeste' }
local palette

local function colorParts(outfit)
    local parts = {}
    for _, p in ipairs(PARTS) do
        parts[#parts + 1] = { id = p.id, label = Rml.text(p.label), hex = Rml.colorHex(outfit[p.id] or 0) }
    end
    return parts
end

local function currentOutfit()
    local player = g_game.isOnline() and g_game.getLocalPlayer()
    if player then return player:getOutfit() end
    local lookType = tonumber(g_settings.getString('rmldemo-looktype')) or 128
    return { type = lookType, head = 78, body = 69, legs = 58, feet = 76, addons = 0 }
end

local function defaultLooks()
    local saved = g_settings.getString('rmloutfit-looks')
    if saved ~= '' then return saved end
    local base = tonumber(g_settings.getString('rmldemo-looktype')) or 128
    local list = {}
    for i = 0, 7 do list[#list + 1] = tostring(base + i) end
    return table.concat(list, ', ')
end

local function parseLooks(text)
    local looks = {}
    for id in text:gmatch('%d+') do
        looks[#looks + 1] = { id = tonumber(id), src = Rml.outfitImage({ type = tonumber(id), head = 78, body = 69, legs = 58, feet = 76 }, 2, 2) }
        if #looks >= 16 then break end
    end
    return looks
end

local function open()
    local window, model
    local outfit = currentOutfit()
    local looksText = defaultLooks()
    palette = palette or Rml.outfitPalette()
    local lastColors = {head = outfit.head or 0, body = outfit.body or 0, legs = outfit.legs or 0, feet = outfit.feet or 0}

    local function outfitFromModel()
        local addons = (model.addon1 and 1 or 0) + (model.addon2 and 2 or 0)
        -- Preserve mount/familiar and server-specific fields, including changes
        -- received while this window was open. Only replace the controls we edit.
        local edited = {}
        for key, value in pairs(currentOutfit()) do edited[key] = value end
        edited.type, edited.head, edited.body = model.lookType, model.head, model.body
        edited.legs, edited.feet, edited.addons = model.legs, model.feet, addons
        return edited
    end

    local function refresh()
        local o = outfitFromModel()
        local preview = Rml.outfitImage(o, model.direction, 3)
        if model.preview ~= preview then model.preview = preview end
        local directionName = Rml.text(DIRECTIONS[model.direction])
        if model.directionName ~= directionName then model.directionName = directionName end
        local selectedColor = model[model.part]
        if model.selectedColor ~= selectedColor then model.selectedColor = selectedColor end
        local colorsChanged = false
        for _, p in ipairs(PARTS) do
            if lastColors[p.id] ~= o[p.id] then colorsChanged = true end
        end
        if colorsChanged then
            model.parts = colorParts(o)
            lastColors = o
        end
    end

    window, model = Rml.createWindow{
        id = 'rmlOutfit',
        document = '/modules/game_rmloutfit/rmloutfit.rml',
        model = 'outfit',
        width = 720,
        height = 500,
        data = {
            lookType = outfit.type, head = outfit.head or 0, body = outfit.body or 0,
            legs = outfit.legs or 0, feet = outfit.feet or 0,
            addon1 = (outfit.addons or 0) % 2 == 1, addon2 = (outfit.addons or 0) >= 2,
            direction = 2, directionName = Rml.text(DIRECTIONS[2]), preview = Rml.outfitImage(outfit, 2, 3),
            part = 'head', selectedColor = outfit.head or 0, parts = colorParts(outfit),
            palette = palette,
            looksText = looksText,
            looks = parseLooks(looksText),
            status = Rml.text(g_game.isOnline() and 'Escolha e clique em Aplicar.' or 'Fora do jogo: só pré-visualização.'),

            Turn = function(_, delta)
                model.direction = (model.direction + delta) % 4
                refresh()
            end,
            Pick = function(_, colorId)
                model[model.part] = colorId
                refresh()
            end,
            SetLook = function(_, id)
                model.lookType = id
                refresh()
            end,
            ApplyLooks = function()
                g_settings.set('rmloutfit-looks', model.looksText)
                model.looks = parseLooks(model.looksText)
            end,
            Randomize = function()
                for _, p in ipairs(PARTS) do model[p.id] = math.random(0, 132) end
                refresh()
            end,
            Apply = function()
                if g_game.isOnline() then
                    g_game.changeOutfit(outfitFromModel())
                    model.status = Rml.text('Outfit enviado ao servidor.')
                else
                    model.status = Rml.text('Fora do jogo: nada foi enviado.')
                end
            end,
        },
        onClose = function() M.window = nil end,
    }
    if not window then return nil end

    -- part e addons mudam pelo próprio documento; o preview acompanha
    Rml.watch(window, model, { 'part', 'addon1', 'addon2' }, refresh, { booleans = { addon1 = true, addon2 = true } })
    return window
end

function toggle()
    Rml.toggle(M, 'window', open)
end

function init()
    g_keyboard.bindKeyDown('Ctrl+Shift+F', toggle)
end

function terminate()
    g_keyboard.unbindKeyDown('Ctrl+Shift+F', toggle)
    if M.window then M.window:destroy() M.window = nil end
    palette = nil
end
