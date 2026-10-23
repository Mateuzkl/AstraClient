--[[
  Rml - helpers para usar RmlUi (HTML/CSS) a partir do Lua do OTClient
  =====================================================================

  Este arquivo é a referência de uso. Todos os módulos de exemplo (client_rmldemo,
  client_rmlshowcase, client_rmloptions, game_rmloutfit) usam apenas estas funções.

  Conceitos (para quem vem do OTUI)
  ---------------------------------
  OTUI                                   RmlUi
  -------------------------------------  ---------------------------------------------
  arquivo .otui (árvore de widgets)      arquivo .rml (HTML) + .rcss (CSS)
  g_ui.createWidget('MainWindow')        Rml.createWindow{ document = 'x.rml', ... }
  anchors.top: parent.top                display: flex / flex-direction / gap (CSS)
  $hover: / $pressed: / $checked:        :hover / :active / :checked (CSS)
  !text: tr('Olá')                       {{texto}} ligado a um data model
  @onClick: modules.x.fazer()            data-event-click="Fazer()"
  widget:setText('a')                    model.texto = 'a'   (a tela atualiza sozinha)
  widget:setVisible(cond)                data-if="cond"  /  data-visible="cond"
  widget:setOn(true) / estilos           data-class-ativo="cond"
  UIItem / UICreature                    <img src="item/123.png"> / <img src="outfit/...">
  UIMinimap, UIMap e outros nativos      Rml.host(janela, 'idDoElemento', widgetOtui)
                                         (o elemento só reserva o espaço; o widget fica por cima,
                                          some com data-if e é recortado pela área rolável)

  Data model
  ----------
  O "data model" é uma tabela Lua compartilhada com o documento. Campos viram variáveis
  ({{campo}}, data-if="campo", data-value="campo") e funções viram eventos
  (data-event-click="Funcao(arg)"). Escrever em model.campo atualiza a tela; quando o
  usuário mexe num <input data-value="campo">, model.campo muda.

  O modelo precisa ser aberto ANTES de carregar o documento que o usa (data-model="nome").
  Rml.createWindow já faz isso na ordem certa.

  Texto e acentos
  ---------------
  O RmlUi trabalha em UTF-8; o protocolo e os .otui usam Latin-1. Passe textos do jogo por
  Rml.text() antes de colocá-los no modelo e use Rml.fromRml() no caminho contrário.

  Imagens do jogo
  ---------------
  item/<id>.png, effect/<id>.png, outfit/<looktype>-<head>-<body>-<legs>-<feet>-<addons>-<dir>.png
  e o sufixo @2x..@8x para ampliar sem borrar: item/2160@2x.png. Os helpers Rml.itemImage,
  Rml.effectImage e Rml.outfitImage montam esses caminhos.

  Efeitos
  -------
  Com o backend completo (OpenGL 3.3) o tema "efeitos" fica ativo; use no RCSS:
      @media (theme: efeitos) { .x { box-shadow: ...; filter: blur(2dp); } }
  Rml.hasEffects() informa o mesmo no Lua.
]]

Rml = {}
local stylesLoaded = false

-- Disponibilidade -------------------------------------------------------------------------

--- true se o cliente tem RmlUi e o backend gráfico está funcionando.
-- Chame antes de criar janelas RML e ofereça uma alternativa OTUI quando for false.
function Rml.isAvailable()
    if not g_rml or not g_rml.isReady() then return false end
    if not stylesLoaded then
        g_ui.importStyle('/styles/rml/widgets.otui')
        stylesLoaded = true
    end
    return true
end

--- true quando filtros, sombras, gradientes e máscaras estão disponíveis (tema "efeitos").
function Rml.hasEffects()
    return Rml.isAvailable() and g_rml.supportsAdvancedEffects()
end

-- Janelas ---------------------------------------------------------------------------------

--- Cria uma janela solta desenhada por um documento RML.
-- @param opts tabela:
--   document  caminho do .rml (obrigatório), ex.: '/modules/meu/janela.rml'
--   id        id do widget OTUI (opcional)
--   width, height  tamanho em pixels (padrão 520 x 360)
--   model     nome do data model usado no documento (data-model="...")
--   data      tabela inicial do modelo (campos e funções)
--   parent    widget pai (padrão rootWidget)
--   onClose   função chamada ao fechar (Esc, Rml.close ou botão que chame Close())
-- @return window (UIRmlWidget), model (tabela viva do data model) ou nil se falhar
-- Exemplo:
--   local win, model = Rml.createWindow{
--       document = '/modules/meu/janela.rml', model = 'meu',
--       data = { nome = '', Salvar = function() print(model.nome) end },
--   }
function Rml.createWindow(opts)
    if not Rml.isAvailable() then
        g_logger.warning('[Rml] RmlUi indisponível neste cliente')
        return nil
    end

    local window = g_ui.createWidget('RmlWindow', opts.parent or rootWidget)
    if opts.id then window:setId(opts.id) end
    window:setSize({ width = opts.width or 520, height = opts.height or 360 })

    local model
    if opts.model then
        local context = window:getContext()
        if not context then window:destroy() return nil end
        local data = opts.data or {}
        -- Close() fica disponível para data-event-click em qualquer janela
        if data.Close == nil then
            data.Close = function() Rml.close(window) end
        end
        model = context:OpenDataModel(opts.model, data)
        if not model then window:destroy() return nil end
    end

    window.onEscape = function() Rml.close(window) end
    window.rmlOnClose = opts.onClose

    if not window:loadDocument(opts.document) then
        window:destroy()
        return nil
    end
    window:raise()
    window:focus()
    return window, model
end

--- Cria um documento RML embutido dentro de um widget OTUI existente (painel, aba, etc.).
-- O widget criado ocupa todo o pai (fill parent).
-- @return widget (UIRmlWidget), model
function Rml.createPanel(parent, document, modelName, data)
    if not Rml.isAvailable() then return nil end
    local widget = g_ui.createWidget('RmlWidget', parent)
    widget:fill('parent')
    local model
    if modelName then
        local context = widget:getContext()
        if not context then widget:destroy() return nil end
        model = context:OpenDataModel(modelName, data or {})
        if not model then widget:destroy() return nil end
    end
    if not widget:loadDocument(document) then
        widget:destroy()
        return nil
    end
    return widget, model
end

--- Fecha uma janela criada por Rml.createWindow com segurança.
-- A destruição é adiada um ciclo: pode ser chamada de dentro de um evento do próprio documento.
function Rml.close(window)
    if not window or window:isDestroyed() then return end
    if window.rmlClosing then return end
    window.rmlClosing = true
    Rml.defer(window, function()
        if window:isDestroyed() then return end
        local onClose = window.rmlOnClose
        window:destroy()
        if onClose then onClose() end
    end)
end

--- Liga/desliga uma janela: cria com `create()` se não existir, senão fecha.
-- @param holder tabela onde a janela fica guardada (ex.: o próprio módulo)
-- @param key campo da tabela (ex.: 'window')
-- Exemplo: function toggle() Rml.toggle(M, 'window', abrir) end
function Rml.toggle(holder, key, create)
    local window = holder[key]
    if window and not window:isDestroyed() then
        Rml.close(window)
        -- Keep ownership until destruction: a second toggle must not create a
        -- replacement that the previous window's deferred onClose could clear.
        return
    end
    holder[key] = create()
end

-- Texto -----------------------------------------------------------------------------------

local function isUtf8(text)
    local i, n = 1, #text
    while i <= n do
        local c = text:byte(i)
        local len = c < 0x80 and 1 or (c >= 0xC2 and c <= 0xDF) and 2 or (c >= 0xE0 and c <= 0xEF) and 3
            or (c >= 0xF0 and c <= 0xF4) and 4 or 0
        if len == 0 or i + len - 1 > n then return false end
        for j = i + 1, i + len - 1 do
            local b = text:byte(j)
            if b < 0x80 or b > 0xBF then return false end
        end
        i = i + len
    end
    return true
end

--- Prepara texto para o RmlUi (UTF-8). Aceita nil.
-- Texto do jogo/servidor/OTUI vem em Latin-1 e é convertido; texto que já é UTF-8 (como as
-- strings escritas nos próprios .lua) passa direto.
function Rml.text(value)
    if value == nil then return '' end
    value = tostring(value)
    if isUtf8(value) then return value end
    return g_rml.utf8(value)
end

--- Converte texto vindo do RmlUi (UTF-8) para o jogo (Latin-1).
function Rml.fromRml(value)
    if value == nil then return '' end
    return g_rml.latin1(tostring(value))
end

--- Escapa texto para inserir em inner_rml (evita que '<' vire uma tag).
function Rml.escape(value)
    return (Rml.text(value):gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'))
end

-- Imagens do jogo -------------------------------------------------------------------------

local function scaleSuffix(scale)
    scale = tonumber(scale)
    if scale and scale >= 2 and scale <= 8 then
        return '@' .. math.floor(scale) .. 'x'
    end
    return ''
end

--- Caminho da imagem de um item: Rml.itemImage(2160) -> 'item/2160.png'
-- @param scale 2..8 para ampliar sem borrar (opcional)
function Rml.itemImage(id, scale)
    return string.format('item/%d%s.png', tonumber(id) or 0, scaleSuffix(scale))
end

--- Caminho da imagem de um efeito (primeiro quadro).
function Rml.effectImage(id, scale)
    return string.format('effect/%d%s.png', tonumber(id) or 0, scaleSuffix(scale))
end

--- Caminho da imagem de um outfit.
-- @param outfit tabela como creature:getOutfit() ({type, head, body, legs, feet, addons})
-- @param direction 0 norte, 1 leste, 2 sul (padrão), 3 oeste
-- @param scale 2..8 (opcional)
function Rml.outfitImage(outfit, direction, scale)
    outfit = outfit or {}
    return string.format('outfit/%d-%d-%d-%d-%d-%d-%d%s.png',
        tonumber(outfit.type) or 0, tonumber(outfit.head) or 0, tonumber(outfit.body) or 0,
        tonumber(outfit.legs) or 0, tonumber(outfit.feet) or 0, tonumber(outfit.addons) or 0,
        tonumber(direction) or 2, scaleSuffix(scale))
end

--- Cor em hexadecimal para usar no RCSS ou em data-style-*.
-- @param color tabela {r, g, b} (como getOutfitColor devolve) ou índice da paleta de outfits
function Rml.colorHex(color)
    if type(color) == 'number' then
        color = getOutfitColor(color)
    end
    return string.format('#%02x%02x%02x', color.r or 0, color.g or 0, color.b or 0)
end

--- Paleta de cores de outfit (133 cores): lista de { id = n, hex = '#rrggbb' }.
function Rml.outfitPalette()
    local palette = {}
    for id = 0, 132 do
        palette[#palette + 1] = { id = id, hex = Rml.colorHex(id) }
    end
    return palette
end

-- DOM -------------------------------------------------------------------------------------

--- Elemento do documento pelo id (equivale a widget:getChildById no OTUI). Pode ser nil.
function Rml.element(window, id)
    local document = window and not window:isDestroyed() and window:getDocument()
    return document and document:GetElementById(id) or nil
end

--- Troca o conteúdo de um elemento por texto puro.
function Rml.setText(window, id, text)
    local element = Rml.element(window, id)
    if element then element.inner_rml = Rml.escape(text) end
end

--- Liga/desliga uma classe CSS num elemento (equivale a trocar o estado/estilo no OTUI).
function Rml.setClass(window, id, class, enabled)
    local element = Rml.element(window, id)
    if element then element:SetClass(class, enabled and true or false) end
end

--- Registra um ouvinte de evento num elemento: Rml.on(win, 'botao', 'click', function(event) ... end)
-- Eventos comuns: click, dblclick, mouseover, mouseout, mousemove, change, submit, keydown, focus, blur
function Rml.on(window, id, eventName, callback)
    local element = Rml.element(window, id)
    if element then element:AddEventListener(eventName, callback, false) end
    return element
end

local function isDisplayed(element)
    -- data-if/data-visible não removem o elemento: aplicam display:none/visibility:hidden
    local node = element
    while node do
        local style = node.style
        if style.display == 'none' or style.visibility == 'hidden' then
            return false
        end
        node = node.parent_node
    end
    return true
end

local function absoluteRect(window, element)
    local x, y = 0, 0
    local node = element
    while node do
        x = x + node.offset_left
        y = y + node.offset_top
        node = node.offset_parent
    end
    node = element.parent_node
    while node do
        x = x - (node.scroll_left or 0)
        y = y - (node.scroll_top or 0)
        node = node.parent_node
    end
    return {
        x = window:getX() + math.floor(x + 0.5),
        y = window:getY() + math.floor(y + 0.5),
        width = math.floor(element.offset_width + 0.5),
        height = math.floor(element.offset_height + 0.5),
    }
end

--- Retângulo de um elemento em coordenadas de tela (as mesmas do OTUI).
-- Útil para posicionar widgets OTUI, tooltips ou menus sobre o documento.
-- @return {x, y, width, height} ou nil se o elemento não existe ou não está visível
function Rml.elementRect(window, id)
    local element = Rml.element(window, id)
    if not element or not isDisplayed(element) then return nil end
    local rect = absoluteRect(window, element)
    if rect.width <= 0 or rect.height <= 0 then return nil end
    return rect
end

--- Área visível que recorta um elemento: o retângulo do ancestral rolável/recortado mais
-- próximo (overflow diferente de visible), ou a janela inteira.
function Rml.clipRect(window, id)
    local clip = window:getRect()
    local element = Rml.element(window, id)
    local node = element and element.parent_node
    while node do
        local style = node.style
        local overflowX, overflowY = style['overflow-x'], style['overflow-y']
        if (overflowX and overflowX ~= 'visible') or (overflowY and overflowY ~= 'visible') then
            local rect = absoluteRect(window, node)
            rect.width = math.floor(node.client_width + 0.5)
            rect.height = math.floor(node.client_height + 0.5)
            local x, y = math.max(clip.x, rect.x), math.max(clip.y, rect.y)
            local right = math.min(clip.x + clip.width, rect.x + rect.width)
            local bottom = math.min(clip.y + clip.height, rect.y + rect.height)
            clip = { x = x, y = y, width = math.max(0, right - x), height = math.max(0, bottom - y) }
        end
        node = node.parent_node
    end
    return clip
end

-- Widgets OTUI dentro do documento --------------------------------------------------------

--- Hospeda um widget OTUI nativo sobre um elemento do documento.
-- O widget acompanha posição/tamanho do elemento a cada layout, some quando o elemento
-- some (data-if, outra aba) e é recortado pela área rolável que contém o elemento.
-- É assim que se usa minimapa, mapa, UIItem/UICreature animados ou qualquer widget OTUI
-- pronto dentro de uma tela RML.
-- No RML basta reservar o espaço: <div id="minimap-slot" style="height: 160dp;"></div>
-- @param window janela/painel RML
-- @param elementId id do elemento que reserva o espaço
-- @param widget widget OTUI já criado (ex.: g_ui.createWidget('Minimap'))
-- @return o widget
function Rml.host(window, elementId, widget)
    -- painel invisível que recorta o widget na área rolável do documento
    local clip = g_ui.createWidget('UIWidget', window)
    clip:setPhantom(true)
    clip:setClipping(true)
    clip:setFocusable(false)
    clip:setVisible(false)

    widget:setParent(clip)
    widget:breakAnchors()

    window.rmlHosted = window.rmlHosted or {}
    window.rmlHosted[#window.rmlHosted + 1] = { id = elementId, widget = widget, clip = clip }

    if not window.rmlHostConnected then
        window.rmlHostConnected = true
        connect(window, {
            onRmlLayout = function(self)
                for _, hosted in ipairs(self.rmlHosted or {}) do
                    if not hosted.widget:isDestroyed() then
                        local rect = Rml.elementRect(self, hosted.id)
                        if rect then
                            hosted.clip:setRect(Rml.clipRect(self, hosted.id))
                            hosted.widget:setRect(rect)
                            hosted.clip:setVisible(true)
                        else
                            hosted.clip:setVisible(false)
                        end
                    end
                end
            end
        })
    end
    return widget
end

-- Modelos ---------------------------------------------------------------------------------

--- Observa campos do modelo e chama onChange(chave, valorNovo, valorAntigo) quando o usuário
-- os altera no documento. Ideal para formulários ligados a estado externo (opções, configs).
-- Os valores de <input type="range"> e <select> chegam como texto: use `numbers` para
-- convertê-los, e `booleans` para checkboxes.
-- @param window janela RML
-- @param model data model
-- @param keys lista de campos observados
-- @param onChange função(chave, novo, antigo)
-- @param kinds opcional: { numbers = {campo=true}, booleans = {campo=true} }
function Rml.watch(window, model, keys, onChange, kinds)
    kinds = kinds or {}
    local numbers, booleans = kinds.numbers or {}, kinds.booleans or {}
    local function read(key)
        local value = model[key]
        if numbers[key] then return tonumber(value) end
        if booleans[key] then return value == true or value == 'true' end
        return value
    end

    local last = {}
    for _, key in ipairs(keys) do last[key] = read(key) end

    connect(window, {
        onRmlUpdate = function()
            for _, key in ipairs(keys) do
                if window:isDestroyed() then return end
                local value = read(key)
                if value ~= last[key] then
                    local old = last[key]
                    last[key] = value
                    onChange(key, value, old)
                end
            end
        end
    })
end

local function trackWindowEvents(window)
    if not window or window:isDestroyed() then return false end
    window.rmlTimers = window.rmlTimers or {}
    if not window.rmlTimersConnected then
        window.rmlTimersConnected = true
        connect(window, { onDestroy = function(self)
            for timer in pairs(self.rmlTimers or {}) do removeEvent(timer) end
            self.rmlTimers = nil
        end })
    end
    return true
end

--- Agenda um callback de uso único e cancela-o se a janela for destruída.
function Rml.defer(window, callback)
    if not trackWindowEvents(window) then return nil end
    local event
    event = addEvent(function()
        if window:isDestroyed() then return end
        if window.rmlTimers then window.rmlTimers[event] = nil end
        callback()
    end)
    window.rmlTimers[event] = true
    return event
end

--- Executa `callback` periodicamente enquanto a janela existir (animações simples, relógios).
-- @param interval milissegundos
function Rml.every(window, interval, callback)
    if not trackWindowEvents(window) then return nil end
    local event
    event = cycleEvent(function()
        if not window or window:isDestroyed() then
            removeEvent(event)
            return
        end
        callback()
    end, interval)
    window.rmlTimers[event] = true
    return event
end
