-- Opções do cliente em RmlUi: mesmas chaves de client_options (getOption/setOption).
-- Para acrescentar uma opção basta uma linha em SECTIONS.

local M = {}

local function bool(key, label) return { key = key, label = label, kind = 'bool' } end
local function range(key, label, min, max, step, suffix)
    return { key = key, label = label, kind = 'range', min = min, max = max, step = step or 1, suffix = suffix or '' }
end
local function choice(key, label, choices)
    local list = {}
    for i, text in ipairs(choices) do list[#list + 1] = { value = tostring(i - 1), label = text } end
    return { key = key, label = label, kind = 'select', choices = list }
end

local SECTIONS = {
    {
        id = 'graphics', label = 'Gráficos', hint = 'Janela, sincronização e desempenho.',
        options = {
            bool('vsync', 'Sincronização vertical (vsync)'),
            bool('fullscreen', 'Tela cheia'),
            bool('showFps', 'Mostrar FPS'),
            bool('showPing', 'Mostrar ping'),
            bool('optimizeFps', 'Otimizar FPS'),
            range('backgroundFrameRate', 'Limite de FPS (501 = sem limite)', 10, 501, 1, ' fps'),
            choice('antialiasingMode', 'Antialiasing', { 'Nenhum', 'Antialiasing', 'Smooth Retro' }),
        },
    },
    {
        id = 'effects', label = 'Efeitos', hint = 'Luz, sombras e andares.',
        options = {
            bool('enableLights', 'Luzes'),
            range('ambientLight', 'Luz ambiente mínima', 0, 100, 1, '%'),
            range('shadowFloorIntensity', 'Intensidade da sombra do andar', 0, 100, 1, '%'),
            choice('floorViewMode', 'Visão de andares', { 'Normal', 'Fade', 'Travado', 'Sempre', 'Sempre com transparência' }),
            range('floorFading', 'Fade entre andares', 0, 1000, 10, ' ms'),
            bool('drawEffectOnTop', 'Efeitos por cima das criaturas'),
            bool('floatingEffect', 'Efeitos flutuantes'),
        },
    },
    {
        id = 'sound', label = 'Som', hint = 'Volumes por canal.',
        options = {
            range('soundMaster', 'Volume geral', 0, 100, 1, '%'),
            range('soundMusic', 'Música', 0, 100, 1, '%'),
            range('soundAmbience', 'Ambiente', 0, 100, 1, '%'),
            range('soundItems', 'Itens', 0, 100, 1, '%'),
            range('soundUI', 'Interface', 0, 100, 1, '%'),
        },
    },
    {
        id = 'interface', label = 'Interface', hint = 'O que aparece sobre o mapa e no console.',
        options = {
            bool('displayNames', 'Nomes das criaturas'),
            bool('displayHealth', 'Barras de vida'),
            bool('displayMana', 'Barras de mana'),
            bool('displayText', 'Textos animados'),
            bool('showTimestampsInConsole', 'Horário no console'),
            bool('showLevelsInConsole', 'Nível no console'),
        },
    },
    {
        id = 'game', label = 'Jogo', hint = 'Controles e comportamento.',
        options = {
            bool('smartWalk', 'Andar inteligente'),
            bool('autoChaseOverride', 'Seguir ao atacar'),
            bool('moveStack', 'Mover pilha inteira'),
            bool('returnDisablesChat', 'Enter desativa o chat'),
            bool('talkOnRightClick', 'Falar com clique direito'),
        },
    },
}

local function options() return modules.client_settings end

local function readValue(opt)
    local value = options().getOption(opt.key)
    if opt.kind == 'bool' then return value == true end
    if opt.kind == 'select' then return tostring(value or 0) end
    return tonumber(value) or 0
end

-- converte o valor que veio do documento para o tipo que client_options espera
local function normalize(opt, value)
    if opt.kind == 'bool' then return value == true or value == 'true' end
    return tonumber(value) or 0
end

local function buildSections()
    local sections = {}
    for _, section in ipairs(SECTIONS) do
        local list = {}
        for _, opt in ipairs(section.options) do
          if GameOptions and GameOptions:getDataSet(opt.key) then
            -- every option exposes every field the document reads (min/max/step/suffix/choices)
            local copy = { min = 0, max = 0, step = 1, suffix = '', choices = {} }
            for k, v in pairs(opt) do copy[k] = v end
            copy.label = Rml.text(opt.label)
            copy.value = readValue(opt)
            if opt.choices then
                copy.choices = {}
                for _, c in ipairs(opt.choices) do copy.choices[#copy.choices + 1] = { value = c.value, label = Rml.text(c.label) } end
            end
            list[#list + 1] = copy
          end
        end
        sections[#sections + 1] = { id = section.id, label = Rml.text(section.label), hint = Rml.text(section.hint), options = list }
    end
    return sections
end

local function open()
    if not Rml.isAvailable() or not options() then return nil end
    local window, model
    -- the data model hands nested tables back as proxies; read the user's changes from this table
    local sections = buildSections()
    window, model = Rml.createWindow{
        id = 'rmlOptions',
        document = '/modules/client_rmloptions/rmloptions.rml',
        model = 'options',
        width = 640,
        height = 470,
        data = {
            tab = 'graphics',
            sections = sections,
            status = '',
            OpenClassic = function() options().toggle() end,
        },
        onClose = function() M.window = nil end,
    }
    if not window then return nil end

    -- aplica cada mudança feita no documento com setOption (o mesmo caminho da janela OTUI).
    -- Nos primeiros quadros os sliders ainda não têm min/max e cortam o valor: esses quadros
    -- só ressincronizam com as opções reais, nada é gravado.
    local applied, warmup = {}, 3
    connect(window, {
        onRmlUpdate = function()
            if warmup > 0 then
                warmup = warmup - 1
                for _, section in ipairs(sections) do
                    for _, opt in ipairs(section.options) do
                        opt.value = readValue(opt)
                        applied[opt.key] = normalize(opt, opt.value)
                    end
                end
                model.sections = sections
                return
            end
            for _, section in ipairs(sections) do
                for _, opt in ipairs(section.options) do
                    local value = normalize(opt, opt.value)
                    if value ~= applied[opt.key] then
                        applied[opt.key] = value
                        options().setOption(opt.key, value)
                        model.status = Rml.text(string.format('%s = %s', opt.key, tostring(value)))
                    end
                end
            end
        end
    })
    return window
end

function toggle()
    Rml.toggle(M, 'window', open)
end

function init()
    g_keyboard.bindKeyDown('Ctrl+Shift+O', toggle)
end

function terminate()
    g_keyboard.unbindKeyDown('Ctrl+Shift+O', toggle)
    if M.window then M.window:destroy() M.window = nil end
end
