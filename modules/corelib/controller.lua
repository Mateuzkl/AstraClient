-- Controller base class for HTML/CSS modules (PASSO 6 - CURSOR_PROMPT_HTML_CSS_OTClientV8_v5)
Controller = {}
Controller.__index = Controller

-- Registro global para handlers HTML obterem o controller pelo moduleName
if not G_CONTROLLER_CALLED then
    G_CONTROLLER_CALLED = {}
end

function Controller:new()
    local module = g_modules.getCurrentModule()
    local instance = setmetatable({}, self)
    instance._htmlWidgets = {}
    instance._htmlPath    = nil
    instance._moduleName  = module and module:getName() or nil
    instance._htmlModuleName = nil
    instance.name = instance._moduleName
    instance.ui = nil
    instance.htmlId = nil
    instance._events = {}
    return instance
end

-- Ciclo de vida (sem-op por padrão — sobrescreva nos módulos)
function Controller:onInit()     end
function Controller:onTerminate() end
function Controller:onGameStart() end
function Controller:onGameEnd()   end

function Controller:init()
    if self.onInit then
        self:onInit()
    end
end

function Controller:terminate()
    self:clearEvents()

    if self.onTerminate then
        self:onTerminate()
    end
end

function Controller:clearEvents()
    for _, event in pairs(self._events or {}) do
        removeEvent(event)
    end
    self._events = {}
end

function Controller:scheduleEvent(callback, delay, name)
    local event = scheduleEvent(callback, delay)
    if name then
        self._events[name] = event
    else
        table.insert(self._events, event)
    end
    return event
end

function Controller:cycleEvent(callback, delay, name)
    local event = cycleEvent(callback, delay)
    if name then
        self._events[name] = event
    else
        table.insert(self._events, event)
    end
    return event
end

function Controller:removeEvent(event)
    if not event then
        return
    end

    removeEvent(event)
    for key, value in pairs(self._events or {}) do
        if value == event then
            self._events[key] = nil
        end
    end
end

-- Carrega HTML relativo ao diretório do módulo atual
-- path = nome do arquivo, ex: "janela.html" (NÃO caminho absoluto)
function Controller:loadHtml(path)
    self._htmlPath = path
    local module = g_modules.getCurrentModule()
    local moduleName = self._moduleName or (module and module:getName()) or "corelib"
    if path:sub(-5) ~= '.html' then
        path = path .. '.html'
    end
    -- Registrar controller para handlers HTML (__scriptHtml, __applyOrBindHtmlAttribute, __childFor)
    G_CONTROLLER_CALLED[moduleName] = self
    self._htmlModuleName = moduleName
    self._htmlId = g_html.load(moduleName, path, nil)
    self.htmlId = self._htmlId
    local widget = self._htmlId and g_html.getRootWidget(self._htmlId) or nil
    if widget then
        self.ui = widget
        table.insert(self._htmlWidgets, widget)
    end
    return widget
end

-- Remove todos os widgets criados por este controller
function Controller:unloadHtml()
    local moduleName = self._htmlModuleName
    if moduleName then
        G_CONTROLLER_CALLED[moduleName] = nil
        self._htmlModuleName = nil
    end
    if self._htmlId then
        g_html.destroy(self._htmlId)
        self._htmlId = nil
        self.htmlId = nil
        self.ui = nil
    end
    for _, w in ipairs(self._htmlWidgets) do
        if w and not w:isDestroyed() then
            w:destroy()
        end
    end
    self._htmlWidgets = {}
    self._htmlPath    = nil
end

-- Cria widget de string HTML (parent=nil → cria na raiz)
function Controller:createWidgetFromHTML(html, parent)
    if not self._htmlId then return nil end
    return g_html.createWidgetFromHTML(html, parent or g_ui.getRootWidget(), self._htmlId)
end

-- Primeiro widget que casa com o seletor CSS
function Controller:findWidget(cssQuery)
    for _, w in ipairs(self._htmlWidgets) do
        if w and not w:isDestroyed() then
            local found = w:querySelector(cssQuery)
            if found then return found end
        end
    end
    return nil
end

-- Atualiza *for após modificar listas (ex: addPlayer, removePlayer)
function Controller:refreshFor()
    if type(refreshHtmlFor) == 'function' then
        refreshHtmlFor(self)
    end
end

-- Todos os widgets que casam com o seletor CSS
function Controller:findWidgets(cssQuery)
    local results = {}
    for _, w in ipairs(self._htmlWidgets) do
        if w and not w:isDestroyed() then
            local all = w:querySelectorAll(cssQuery)
            for _, f in ipairs(all) do
                table.insert(results, f)
            end
        end
    end
    return results
end
