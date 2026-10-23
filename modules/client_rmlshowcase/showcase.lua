-- RmlUi showcase: uma janela com abas, cada uma ensinando um recurso.
-- Abre pelo botão "RmlUi" no menu superior ou Ctrl+Shift+U.

local M = {}

local OTUI_EXAMPLES = {
    {
        title = 'Janela com título e botão',
        otui = [[MainWindow
  id: myWindow
  !text: tr('Minha janela')
  size: 300 200

  Button
    id: okButton
    !text: tr('Ok')
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    @onClick: modules.meu.confirmar()]],
        rml = [[<div class="otc-window" data-model="meu">
  <header class="otc-header" data-drag="window">
    <span class="otc-title">Minha janela</span>
  </header>
  <footer class="otc-footer">
    <span class="spacer"></span>
    <button class="btn primary"
      data-event-click="Confirmar()">Ok</button>
  </footer>
</div>]],
    },
    {
        title = 'Texto que muda pelo Lua',
        otui = [[-- .otui
Label
  id: goldLabel

-- .lua
window:getChildById('goldLabel')
  :setText(tr('Ouro: %d', gold))]],
        rml = [[<!-- .rml -->
<span>Ouro: {{gold}}</span>

-- .lua
model.gold = gold   -- a tela atualiza sozinha]],
    },
    {
        title = 'Estados (hover, pressionado, ligado)',
        otui = [[Button
  image-color: #ffffffaa
  $hover:
    image-color: #ffffff
  $pressed:
    image-color: #cccccc
  $on:
    color: #ffd700]],
        rml = [[.btn { color: #ffffffaa; }
.btn:hover { color: #ffffff; }
.btn:active { color: #cccccc; }
.btn.on { color: #ffd700; }
<!-- classe ligada por expressão: -->
<button class="btn" data-class-on="ativo">]],
    },
    {
        title = 'Posicionamento',
        otui = [[Panel
  anchors.fill: parent
  layout: horizontalBox
  Label
    anchors.left: parent.left
    margin-left: 8]],
        rml = [[.painel {
  display: flex;
  gap: 8dp;
  padding: 8dp;
}
.painel .label { flex: 1; }]],
    },
    {
        title = 'Lista dinâmica',
        otui = [[-- .lua
for _, item in ipairs(itens) do
  local w = g_ui.createWidget('ListRow', list)
  w:setText(item.name)
end]],
        rml = [[<!-- .rml -->
<div data-for="item : itens">{{item.name}}</div>

-- .lua
model.itens = itens]],
    },
    {
        title = 'Item e outfit',
        otui = [[Item
  id: slot
  size: 34 34
-- slot:setItemId(2160)

Creature
  id: preview
-- preview:setOutfit(outfit)]],
        rml = [[<img src="item/2160.png"/>
<img data-attr-src="outfitSrc"/>

-- .lua
model.outfitSrc = Rml.outfitImage(outfit, 2, 3)]],
    },
    {
        title = 'Minimapa e widgets nativos',
        otui = [[Minimap
  id: minimap
  anchors.fill: parent]],
        rml = [[<!-- .rml: só reserva o espaço -->
<div id="minimap-slot" style="height: 160dp;"></div>

-- .lua
Rml.host(janela, 'minimap-slot',
  g_ui.createWidget('Minimap'))]],
    },
}

local TABS = {
    { id = 'home', label = 'Início' },
    { id = 'binding', label = 'Data binding' },
    { id = 'forms', label = 'Formulários' },
    { id = 'sprites', label = 'Sprites' },
    { id = 'native', label = 'OTUI no RML' },
    { id = 'images', label = 'Imagens' },
    { id = 'effects', label = 'Efeitos' },
    { id = 'otui', label = 'OTUI para RmlUi' },
    { id = 'dom', label = 'Lua e DOM' },
}

local function thingsLoaded()
    return g_things.isDatLoaded()
end

local function selectedVersion()
    local version = g_game.getClientVersion()
    if version == 0 then version = g_settings.getInteger('client-version') end
    return version
end

local function exampleIds()
    local text = g_settings.getString('rmldemo-items')
    if text == '' then
        text = selectedVersion() >= 1100 and '3031, 3035, 3043, 3288, 3366, 3079' or '2148, 2152, 2160, 2400, 2472, 2195'
    end
    local ids = {}
    for id in text:gmatch('%d+') do ids[#ids + 1] = tonumber(id) end
    return ids
end

local function exampleLookType()
    return tonumber(g_settings.getString('rmldemo-looktype')) or 128
end

local function spriteData()
    local items, bigItems = {}, {}
    for i, id in ipairs(exampleIds()) do
        items[#items + 1] = { src = Rml.itemImage(id) }
        if i <= 3 then bigItems[#bigItems + 1] = { src = Rml.itemImage(id, 3) } end
    end
    return items, bigItems
end

local SLIDE_WIDTH = 600

local function carouselSlides()
    local ids = exampleIds()
    local look = { type = exampleLookType(), head = 78, body = 69, legs = 58, feet = 76 }
    return {
        { src = '/images/splash.png', fit = 'cover', title = 'Fundo do cliente', text = 'arquivo de data/images, decorator: image(... cover)' },
        { src = Rml.outfitImage(look, 2, 4), fit = 'contain', title = 'Outfit do jogo', text = Rml.outfitImage(look, 2, 4) },
        { src = Rml.itemImage(ids[1] or 2160, 6), fit = 'contain', title = 'Item do jogo', text = Rml.itemImage(ids[1] or 2160, 6) },
        { src = '/images/clienticon.png', fit = 'contain', title = 'Ícone do cliente', text = '1024x1024 reduzido com contain' },
        { src = '/images/ui/background.png', fit = 'repeat', title = 'Textura repetida', text = 'decorator: image(... repeat)' },
    }
end

local function translate(examples)
    local out = {}
    for _, ex in ipairs(examples) do
        out[#out + 1] = { title = Rml.text(ex.title), otui = Rml.text(ex.otui), rml = Rml.text(ex.rml) }
    end
    return out
end

local function createNativeWidgets(window)
    local minimap = g_ui.createWidget('Minimap')
    minimap:setZoom(1)
    local player = g_game.isOnline() and g_game.getLocalPlayer()
    minimap:setCameraPosition(player and player:getPosition() or { x = 1856, y = 1024, z = 7 })
    minimap.onMouseRelease = function(self, pos, button)
        if not g_game.isOnline() then return false end
        return UIMinimap.onMouseRelease(self, pos, button)
    end
    Rml.host(window, 'minimap-slot', minimap)

    local item = g_ui.createWidget('Item')
    item:setVirtual(true)
    Rml.host(window, 'item-slot', item)

    local creature = g_ui.createWidget('Creature')
    Rml.host(window, 'creature-slot', creature)
    return item, creature
end

local function fillNativeWidgets(item, creature)
    if not thingsLoaded() then return end
    item:setItemId(exampleIds()[3] or 2160)
    if g_things.isValidDatId(exampleLookType(), ThingCategoryCreature) then
        creature:setOutfit({ type = exampleLookType(), head = 78, body = 69, legs = 58, feet = 76 })
    end
end

local function open()
    local model
    local todos = {
        { text = 'Ler modules/corelib/rml.lua', done = true },
        { text = 'Criar meu primeiro .rml', done = false },
        { text = 'Trocar uma janela OTUI por RmlUi', done = false },
    }
    local spritesReady, examplesReady = false, false
    local slides
    local window
    window, model = Rml.createWindow{
        id = 'rmlShowcase',
        document = '/modules/client_rmlshowcase/showcase.rml',
        model = 'showcase',
        width = 820,
        height = 540,
        data = {
            tabs = (function()
                local tabs = {}
                for _, t in ipairs(TABS) do tabs[#tabs + 1] = { id = t.id, label = Rml.text(t.label) } end
                return tabs
            end)(),
            tab = 'home',
            backend = g_rml.getBackendName(),
            effects = Rml.hasEffects(),
            online = g_game.isOnline(),

            -- data binding
            count = 0, meter = 0, name = '', nameLength = 0,
            todos = todos,
            newTodo = '',

            -- formulários
            sound = true, lights = false, mode = 'classic', volume = 60, quality = 'medium',
            notes = Rml.text('Escreva aqui...'), notesLength = 0,

            -- sprites
            thingsLoaded = thingsLoaded(),
            assetsHint = Rml.text(string.format('Sem assets: coloque os arquivos em data/things/%d/ e clique em Carregar assets.', selectedVersion())),
            items = {}, bigItems = {},
            direction = 2,
            outfitSrc = '',

            examples = {},
            flag = '/images/flags/pt.png',
            slides = {}, slide = 0, paused = false,
            trackTransform = 'translateX(0dp)',

            -- nested tables come back from the model as proxies: change the original
            -- table, then assign it again so the document refreshes
            AddTodo = function()
                if model.newTodo == '' then return end
                todos[#todos + 1] = { text = model.newTodo, done = false }
                model.todos = todos
                model.newTodo = ''
            end,
            Remove = function(_, index)
                table.remove(todos, index + 1)
                model.todos = todos
            end,
            LoadAssets = function()
                local version = selectedVersion()
                Rml.defer(window, function()
                    g_game.setClientVersion(version)
                    g_game.setProtocolVersion(version)
                end)
            end,
            Slide = function(_, delta)
                if not slides then return end
                model.slide = (model.slide + delta) % #slides
                model.trackTransform = string.format('translateX(%ddp)', -model.slide * SLIDE_WIDTH)
            end,
            GoSlide = function(_, index)
                model.slide = index
                model.trackTransform = string.format('translateX(%ddp)', -model.slide * SLIDE_WIDTH)
            end,
            NextFlag = function()
                local flags = { 'pt', 'en', 'es', 'de', 'pl' }
                local current = model.flag:match('flags/(%a+)%.png') or 'pt'
                local index = 1
                for i, f in ipairs(flags) do if f == current then index = i % #flags + 1 end end
                model.flag = '/images/flags/' .. flags[index] .. '.png'
            end,
            OpenMinimap = function() if modules.game_rmlminimap then modules.game_rmlminimap.toggle() end end,
            OpenSkillTree = function() if modules.game_rmlskilltree then modules.game_rmlskilltree.toggle() end end,
            OpenOptions = function() if modules.client_rmloptions then modules.client_rmloptions.toggle() end end,
            OpenOutfit = function() if modules.game_rmloutfit then modules.game_rmloutfit.toggle() end end,
            OpenDemo = function() if modules.client_rmldemo then modules.client_rmldemo.toggle() end end,
            DomText = function()
                Rml.setText(window, 'dom-box', 'Texto trocado pelo Lua às ' .. os.date('%H:%M:%S'))
            end,
            DomClass = function()
                local box = Rml.element(window, 'dom-box')
                if box then box:SetClass('destaque', not box:IsClassSet('destaque')) end
            end,
        },
        onClose = function() M.window = nil end,
    }
    if not window then return nil end

    local nativeItem, nativeCreature = createNativeWidgets(window)
    fillNativeWidgets(nativeItem, nativeCreature)

    -- valores derivados calculados no Lua (o documento só exibe)
    connect(window, {
        onRmlUpdate = function()
            -- data-if only hides nodes: don't instantiate lists/images in unopened tabs.
            if model.tab == 'sprites' and not spritesReady then
                spritesReady = true
                model.items, model.bigItems = spriteData()
                model.outfitSrc = Rml.outfitImage({ type = exampleLookType(), head = 78, body = 69, legs = 58, feet = 76 }, model.direction, 3)
            elseif model.tab == 'images' and not slides then
                slides = carouselSlides()
                model.slides = slides
            elseif model.tab == 'otui' and not examplesReady then
                examplesReady = true
                model.examples = translate(OTUI_EXAMPLES)
            end
            local meter = math.max(0, math.min(100, model.count * 5))
            if model.meter ~= meter then model.meter = meter end
            local nameLength = #Rml.fromRml(model.name)
            if model.nameLength ~= nameLength then model.nameLength = nameLength end
            local notesLength = #Rml.fromRml(model.notes)
            if model.notesLength ~= notesLength then model.notesLength = notesLength end
            local loaded = thingsLoaded()
            if model.thingsLoaded ~= loaded then
                model.thingsLoaded = loaded
                if spritesReady then model.items, model.bigItems = spriteData() end
            end
            if model.online ~= g_game.isOnline() then model.online = g_game.isOnline() end
            if loaded and not nativeCreature.filled then
                nativeCreature.filled = true
                fillNativeWidgets(nativeItem, nativeCreature)
            end
        end
    })

    -- animação feita pelo Lua: gira o outfit
    Rml.every(window, 600, function()
        if model.tab ~= 'sprites' then return end
        model.direction = (model.direction + 1) % 4
        model.outfitSrc = Rml.outfitImage({ type = exampleLookType(), head = 78, body = 69, legs = 58, feet = 76 }, model.direction, 3)
    end)

    -- carrossel: avança sozinho, exceto com o mouse em cima ou fora da aba
    Rml.every(window, 3000, function()
        if model.tab ~= 'images' or model.paused or not slides then return end
        model.slide = (model.slide + 1) % #slides
        model.trackTransform = string.format('translateX(%ddp)', -model.slide * SLIDE_WIDTH)
    end)

    Rml.on(window, 'mouse-pad', 'mousemove', function(event)
        local p = event.parameters
        Rml.setText(window, 'mouse-info', string.format('x = %d, y = %d', p.mouse_x or 0, p.mouse_y or 0))
    end)

    return window
end

function toggle()
    Rml.toggle(M, 'window', open)
end

function init()
    if not g_rml then return end
    g_keyboard.bindKeyDown('Ctrl+Shift+U', toggle)
    M.button = modules.client_topmenu.addLeftButton('rmlShowcaseButton', tr('RmlUi showcase') .. ' (Ctrl+Shift+U)',
        '/images/topbuttons/hotkeys', toggle)
end

function terminate()
    g_keyboard.unbindKeyDown('Ctrl+Shift+U', toggle)
    if M.window then M.window:destroy() M.window = nil end
    if M.button then M.button:destroy() M.button = nil end
end
