--[[
  HTML/CSS Handlers para OrigenOTClient V8
  Implementa __scriptHtml, __applyOrBindHtmlAttribute, __childFor
  Conforme CURSOR_PROMPT_v8_HTMLCSS.md
]]

-- ============================================================
-- HELPER: Avaliar expressão Lua no contexto do controller
-- ============================================================
local function evalExpr(expr, controller, extraVars)
    extraVars = extraVars or (controller and rawget(controller, '__current_for_ctx'))
    local env = setmetatable({}, {
        __index = function(_, k)
            if k == 'self' then return controller end
            if extraVars and extraVars[k] ~= nil then return extraVars[k] end
            local v = controller and rawget(controller, k)
            if v ~= nil then return v end
            return _G[k]
        end
    })
    local fn, err = load('return (' .. expr .. ')', '@html_eval', 't', env)
    if not fn then
        if g_logger then g_logger.error('[HTML] evalExpr erro em "' .. expr .. '": ' .. tostring(err))
        else print('[HTML] evalExpr erro: ' .. tostring(err)) end
        return nil
    end
    local ok, result = pcall(fn)
    if not ok then
        if g_logger then g_logger.error('[HTML] evalExpr falhou "' .. expr .. '": ' .. tostring(result))
        else print('[HTML] evalExpr falhou: ' .. tostring(result)) end
        return nil
    end
    return result
end

-- ============================================================
-- HELPER: Executar statement Lua no contexto do controller
-- ============================================================
local function execStmt(stmt, controller, extraVars)
    extraVars = extraVars or (controller and rawget(controller, '__current_for_ctx'))
    local env = setmetatable({}, {
        __index = function(_, k)
            if k == 'self' then return controller end
            if extraVars and extraVars[k] ~= nil then return extraVars[k] end
            local v = controller and rawget(controller, k)
            if v ~= nil then return v end
            return _G[k]
        end,
        __newindex = function(_, k, v)
            if k ~= 'self' and controller then controller[k] = v end
        end
    })
    local fn, err = load(stmt, '@html_stmt', 't', env)
    if not fn then
        if g_logger then g_logger.error('[HTML] execStmt erro em "' .. stmt .. '": ' .. tostring(err))
        else print('[HTML] execStmt erro: ' .. tostring(err)) end
        return
    end
    local ok, execErr = pcall(fn)
    if not ok then
        if g_logger then g_logger.error('[HTML] execStmt falhou "' .. stmt .. '": ' .. tostring(execErr))
        else print('[HTML] execStmt falhou: ' .. tostring(execErr)) end
    end
end

-- ============================================================
-- HELPER: Processar {{ expr }} em texto puro
-- ============================================================
local function processTemplateText(text, controller, extraVars)
    if not text or type(text) ~= 'string' then return '' end
    return (text:gsub('{{(.-)}}', function(expr)
        expr = expr:match('^%s*(.-)%s*$') or expr
        local v = evalExpr(expr, controller, extraVars)
        return tostring(v ~= nil and v or '')
    end))
end

-- ============================================================
-- HELPER: Processar {{ expr }} em string HTML completa
-- ============================================================
local function processTemplateHtml(html, controller, extraVars)
    if not html or type(html) ~= 'string' then return '' end
    return (html:gsub('{{(.-)}}', function(expr)
        expr = expr:match('^%s*(.-)%s*$') or expr
        local v = evalExpr(expr, controller, extraVars)
        return tostring(v ~= nil and v or '')
    end))
end

local function startsWith(value, prefix)
    return type(value) == 'string' and value:sub(1, #prefix) == prefix
end

local function isAbsoluteResource(value)
    if type(value) ~= 'string' or value == '' then return true end
    if startsWith(value, '/') or startsWith(value, '\\') then return true end
    if startsWith(value, 'http://') or startsWith(value, 'https://') then return true end
    if startsWith(value, 'data:') then return true end
    return value:match('^%a[%w+.-]*:') ~= nil
end

local function normalizeHtmlResourcePath(value, moduleName)
    if type(value) ~= 'string' or value == '' or isAbsoluteResource(value) then
        return value
    end
    return '/modules/' .. tostring(moduleName or 'corelib') .. '/' .. value
end

local function kebabToCamel(s)
    s = tostring(s or ''):gsub('^%-%-', '')
    return (s:gsub('-(%a)', function(c) return c:upper() end))
end

local function kebabToSetter(s)
    local camel = kebabToCamel(s)
    return 'set' .. camel:sub(1,1):upper() .. camel:sub(2)
end

local function applyHtmlAttributeValue(widget, attrName, value, controller, moduleName)
    if not widget or not attrName then return end

    if attrName == 'image-source' and type(value) == 'string' then
        if (startsWith(value, 'http://') or startsWith(value, 'https://')) and HTTP and HTTP.downloadImage then
            HTTP.downloadImage(value, function(path, err)
                if err then
                    if g_logger then g_logger.warning('HTTP error: ' .. tostring(err) .. ' - ' .. value) end
                    return
                end
                if widget and (not widget.isDestroyed or not widget:isDestroyed()) then
                    widget:setImageSource(path)
                end
            end)
            return
        end
        value = normalizeHtmlResourcePath(value, moduleName or (controller and controller.name))
    end

    local setter = kebabToSetter(attrName)
    if widget[setter] then
        local ok, err = pcall(function() widget[setter](widget, value) end)
        if not ok and g_logger then
            g_logger.warning('[HTML] OTML setter ' .. setter .. ' falhou: ' .. tostring(err))
        end
        return
    end

    widget[kebabToCamel(attrName)] = value
end

local function applyHtmlVisible(widget, value)
    if not widget then return end
    if widget.setOpacity then
        widget:setOpacity(value and 1 or 0)
    elseif widget.setVisible then
        widget:setVisible(value and true or false)
    end
end

local function registerHtmlBinding(widget, controller, attrName, expr, moduleName, applyFn, extraVars, methodName)
    if not WidgetWatch or type(WidgetWatch.register) ~= 'function' or not widget or not controller then
        return
    end

    local ok, initial = pcall(function()
        return evalExpr(expr, controller, extraVars)
    end)
    if not ok then
        return
    end

    WidgetWatch.register({
        widget = widget,
        res = initial,
        attr = attrName,
        methodName = methodName,
        htmlId = widget.getHtmlId and widget:getHtmlId() or nil,
        fnc = function(self)
            local value = evalExpr(expr, controller, extraVars)
            if value ~= self.res then
                applyFn(self.widget, value, controller, moduleName)
                self.res = value
            end
        end
    })
end

-- ============================================================
-- HELPER: Construir objeto event correto por tipo de widget
-- ============================================================
local function buildEvent(widget, defaultName, ...)
    local args = {...}
    local wtype = (widget.getStyleName and widget:getStyleName()) or (widget.getStyle and widget:getStyle() and widget:getStyle().__class) or ''
    local event = { name = defaultName }

    if wtype == 'UIComboBox' or wtype:find('ComboBox') then
        event.name  = 'onOptionChange'
        event.text  = args[1] or ''
        event.data  = args[2] or ''
        event.value = event.text
    elseif wtype == 'UICheckBox' or wtype == 'QtCheckBox' or wtype:find('CheckBox') then
        event.name    = 'onCheckChange'
        event.checked = args[1] or false
        event.value   = event.checked
    elseif wtype == 'UIScrollBar' or wtype:find('ScrollBar') then
        event.name  = 'onValueChange'
        event.value = args[1] or 0
        event.delta = args[2] or 0
    elseif wtype == 'UIRadioGroup' or wtype:find('RadioGroup') then
        event.name                   = 'onSelectionChange'
        event.selectedWidget         = args[1]
        event.previousSelectedWidget = args[2]
        event.value                  = event.selectedWidget
    else
        local firstArg = args[1]
        if firstArg ~= nil and type(firstArg) == 'number' then
            event.name  = 'onValueChange'
            event.value = firstArg
        else
            event.name  = 'onTextChange'
            event.value = firstArg
            if event.value == nil then
                event.value = ''
            end
        end
    end
    return event
end

local function getWidgetForContext(widget)
    local current = widget
    while current do
        if current.__html_for_ctx then
            return current.__html_for_ctx
        end
        current = current.getParent and current:getParent() or nil
    end
    return nil
end

local function buildEventVars(widget, event, args)
    local vars = { target = widget, event = event }
    if args then
        local eventName = (event and event.name and tostring(event.name):lower()) or ''
        if eventName:find('mouse', 1, true) or eventName:find('click', 1, true) or eventName:find('touch', 1, true) then
            vars.mousePos = args[1]
            vars.mouseButton = args[2]
            vars.autoRepeatTicks = args[3]
        elseif eventName:find('key', 1, true) then
            vars.keyCode = args[1]
            vars.keyboardModifiers = args[2]
            vars.autoRepeatTicks = args[3]
        end
    end
    local ctx = getWidgetForContext(widget)
    if ctx then
        for key, value in pairs(ctx) do
            if key ~= 'keys' and key ~= 'values' and vars[key] == nil then
                vars[key] = value
            end
        end
    end
    return vars
end

-- ============================================================
-- TABELA: HTML event name → UIWidget callback name
-- ============================================================
local HTML_EVENTS = {
    onstyleapply     = 'onStyleApply',
    ondestroy        = 'onDestroy',
    onidchange       = 'onIdChange',
    onwidthchange    = 'onWidthChange',
    onheightchange   = 'onHeightChange',
    onresize         = 'onResize',
    onenabled        = 'onEnabled',
    onpropertychange = 'onPropertyChange',
    ongeometrychange = 'onGeometryChange',
    onlayoutupdate   = 'onLayoutUpdate',
    oncreate         = 'onCreate',
    onsetup          = 'onSetup',
    onfocus          = 'onFocusChange',
    onchildfocus     = 'onChildFocusChange',
    onhover          = 'onHoverChange',
    onvisibility     = 'onVisibilityChange',
    ondragenter      = 'onDragEnter',
    ondragleave      = 'onDragLeave',
    ondragmove       = 'onDragMove',
    ondrop           = 'onDrop',
    onkeytext        = 'onKeyText',
    onkeydown        = 'onKeyDown',
    onkeypress       = 'onKeyPress',
    onkeyup          = 'onKeyUp',
    onescape         = 'onEscape',
    onmousepress     = 'onMousePress',
    onmouserelease   = 'onMouseRelease',
    onmousemove      = 'onMouseMove',
    onmousewheel     = 'onMouseWheel',
    onclick          = 'onClick',
    ondoubleclick    = 'onDoubleClick',
    ontextareaupdate = 'onTextAreaUpdate',
    onfontchange     = 'onFontChange',
    ontextchange     = 'onTextChange',
}

-- ============================================================
-- __scriptHtml — Executar <script type="text"> no contexto do controller
-- Assinatura C++: widget->callLuaField("__scriptHtml", moduleName, script, scriptStr)
-- ============================================================
function UIWidget:__scriptHtml(moduleName, scriptContent, scriptStr)
    local controller = G_CONTROLLER_CALLED and G_CONTROLLER_CALLED[moduleName]
    if not controller then
        if g_logger then g_logger.warning('[HTML] __scriptHtml: controller não encontrado para módulo "' .. tostring(moduleName) .. '"')
        else print('[HTML] controller não encontrado: ' .. tostring(moduleName)) end
        return
    end
    local env = setmetatable({}, {
        __index = function(_, k)
            if k == 'self' then return controller end
            local v = rawget(controller, k)
            if v ~= nil then return v end
            return _G[k]
        end,
        __newindex = function(_, k, v)
            if k ~= 'self' then controller[k] = v end
        end
    })
    local fn, err = load(scriptContent, '@html_script', 't', env)
    if not fn then
        if g_logger then g_logger.error('[HTML] <script> parse error: ' .. tostring(err))
        else print('[HTML] <script> parse error: ' .. tostring(err)) end
        return
    end
    local ok, execErr = pcall(fn)
    if not ok then
        if g_logger then g_logger.error('[HTML] <script> runtime error: ' .. tostring(execErr))
        else print('[HTML] <script> runtime error: ' .. tostring(execErr)) end
    end
end

-- ============================================================
-- __applyOrBindHtmlAttribute — Handler central para cada atributo HTML
-- Assinatura C++: widget->callLuaField("__applyOrBindHtmlAttribute", attr, value, isInheritable, moduleName, nodeStr)
-- ============================================================
function UIWidget:__applyOrBindHtmlAttribute(attrName, attrValue, isInheritable, moduleName, nodeStr)
    if not self or (self.isDestroyed and self:isDestroyed()) then return end
    if not attrName then return end

    local controller = G_CONTROLLER_CALLED and G_CONTROLLER_CALLED[moduleName]
    if not controller then return end

    -- C++ traduz *if → *condition-if; tratar ambos
    if attrName == '*condition-if' then attrName = '*if' end

    -- Texto de nó (expressões {{ }} convertidas em *text pelo parser)
    if attrName == '#text' or attrName == 'textContent' then
        local processed = processTemplateText(attrValue, controller)
        if self.setText then self:setText(processed) end
        return
    end

    -- *text: Lua → Widget. C++ traduz *value→*text em inputs (htmlmanager.cpp translateAttribute,
    -- styleName != "CheckBox" && styleName != "ComboBox"): nesse caso fazer bidirecional.
    if attrName == '*text' then
        local isTextInput = (self.onTextChange and self.setText)
        local isSimplePath = attrValue:match('^%s*self%.[%w_.]+%s*$')
        if isTextInput and isSimplePath then
            -- Era *value no HTML (C++ traduziu): Widget → Lua bidirecional
            local varPath = attrValue:match('^%s*(.-)%s*$')
            local initVal = evalExpr(varPath, controller)
            if initVal ~= nil and self.setText then self:setText(tostring(initVal)) end
            if self.onTextChange then
                self.onTextChange = function(_, newText)
                    execStmt(varPath .. ' = ' .. string.format('%q', tostring(newText or '')), controller)
                end
            end
        else
            -- *text normal: Lua → Widget
            local v = evalExpr(attrValue, controller)
            if v ~= nil and self.setText then self:setText(tostring(v)) end
        end
        return
    end

    -- *if / *condition-if: false = remove do layout (setDisplay('none') ou setVisible(false))
    if attrName == '*if' then
        local v = evalExpr(attrValue, controller)
        if not v then
            if self.setDisplay then
                self:setDisplay('none')
            elseif self.setVisible then
                self:setVisible(false)
            end
        end
        return
    end

    -- *visible: false = invisível mas ocupa espaço (setOpacity(0))
    if attrName == '*visible' then
        local extraVars = controller and rawget(controller, '__current_for_ctx')
        local v = evalExpr(attrValue, controller, extraVars)
        applyHtmlVisible(self, v)
        registerHtmlBinding(self, controller, attrName, attrValue, moduleName, function(widget, value)
            applyHtmlVisible(widget, value)
        end, extraVars, 'visible')
        return
    end

    -- *value: Widget → Lua (bidirecional) — para CheckBox/ComboBox o C++ mantém *value
    if attrName == '*value' then
        local varPath = attrValue:match('^%s*(.-)%s*$')
        local initVal = evalExpr(varPath, controller)
        if initVal ~= nil and self.setText then
            self:setText(tostring(initVal))
        end
        if self.onTextChange then
            self.onTextChange = function(_, newText)
                execStmt(varPath .. ' = ' .. string.format('%q', tostring(newText or '')), controller)
            end
        end
        return
    end

    -- *checked: Widget → Lua (bidirecional)
    if attrName == '*checked' then
        local varPath = attrValue:match('^%s*(.-)%s*$')
        local initVal = evalExpr(varPath, controller)
        if initVal ~= nil and self.setChecked then
            self:setChecked(initVal == true)
        end
        if self.onCheckChange then
            self.onCheckChange = function(_, checked)
                execStmt(varPath .. ' = ' .. tostring(checked), controller)
            end
        end
        return
    end

    -- *outfit: Lua → UICreature
    if attrName == '*outfit' then
        local outfit = evalExpr(attrValue, controller)
        if outfit and self.setOutfit then
            self:setOutfit(outfit)
        end
        return
    end

    -- Bindings dinamicos genericos: *width, *tooltip, *item, *trade-item,
    -- *icon-clip, *color, *class-foo, etc.
    if attrName:sub(1, 1) == '*' then
        local dynamicName = attrName:sub(2)
        local extraVars = controller and rawget(controller, '__current_for_ctx')
        local value = evalExpr(attrValue, controller, extraVars)

        if dynamicName:sub(1, 6) == 'class-' then
            if value then
                local className = dynamicName:sub(7)
                local style = g_ui and g_ui.getStyle and g_ui.getStyle(className)
                if style and self.mergeStyle then
                    self:mergeStyle(style)
                end
            end
            return
        end

        applyHtmlAttributeValue(self, dynamicName, value, controller, moduleName)
        registerHtmlBinding(self, controller, attrName, attrValue, moduleName, function(widget, boundValue, boundController, boundModuleName)
            applyHtmlAttributeValue(widget, dynamicName, boundValue, boundController, boundModuleName)
        end, extraVars)
        return
    end

    -- onchange: objeto event varia por tipo de widget
    if attrName == 'onchange' then
        local stmt = attrValue:match('^%s*(.-)%s*$')
        local wtype = (self.getStyleName and self:getStyleName()) or (self.getStyle and self:getStyle() and self:getStyle().__class) or ''
        self.__html_handler_event_attrs = self.__html_handler_event_attrs or {}
        self.__html_handler_event_attrs[attrName] = 'html'

        if wtype == 'UIComboBox' or wtype:find('ComboBox') then
            self.onOptionChange = function(_, text, data)
                local event = buildEvent(self, 'onOptionChange', text, data)
                execStmt(stmt, controller, buildEventVars(self, event))
            end
        elseif wtype == 'UICheckBox' or wtype == 'QtCheckBox' or wtype:find('CheckBox') then
            self.onCheckChange = function(_, checked)
                local event = buildEvent(self, 'onCheckChange', checked)
                execStmt(stmt, controller, buildEventVars(self, event))
            end
        elseif wtype == 'UIScrollBar' or wtype:find('ScrollBar') then
            self.onValueChange = function(_, value, delta)
                local event = buildEvent(self, 'onValueChange', value, delta)
                execStmt(stmt, controller, buildEventVars(self, event))
            end
        elseif wtype == 'UIRadioGroup' or wtype:find('RadioGroup') then
            self.onSelectionChange = function(_, sel, prev)
                local event = buildEvent(self, 'onSelectionChange', sel, prev)
                execStmt(stmt, controller, buildEventVars(self, event))
            end
        else
            self.onTextChange = function(_, text)
                local event = buildEvent(self, 'onTextChange', text)
                execStmt(stmt, controller, buildEventVars(self, event))
            end
        end
        return
    end

    -- Eventos genéricos (onclick, onmousepress, etc.)
    local cbName = HTML_EVENTS[attrName]
    if cbName then
        local stmt = attrValue:match('^%s*(.-)%s*$')
        self.__html_handler_event_attrs = self.__html_handler_event_attrs or {}
        self.__html_handler_event_attrs[attrName] = 'html'
        self[cbName] = function(target, ...)
            local args = {...}
            local event = buildEvent(target, cbName, unpack(args))
            execStmt(stmt, controller, buildEventVars(target, event, args))
        end
        return
    end

    -- Atributos OTML (kebab-case → setXxxYyy)
    local val = attrValue
    if val == 'true' then val = true
    elseif val == 'false' then val = false
    else
        local n = tonumber(val)
        if n then val = n end
    end
    applyHtmlAttributeValue(self, attrName, val, controller, moduleName)
end

-- ============================================================
-- __onHtmlProcessFinished — Chamado ao terminar processamento (compatibilidade)
-- ============================================================
function UIWidget:__onHtmlProcessFinished(inheritedStyles)
    self.inheritedStyles = inheritedStyles or {}
end

-- ============================================================
-- __childFor — Loop reativo *for
-- Assinatura C++: parent->callLuaField("__childFor", moduleName, forExpr, templateHtml, childIndex)
-- ============================================================
local _forBindings = setmetatable({}, { __mode = 'k' })

local function _matchesForSelector(container, b, selector)
    if not selector then return true end
    if selector == container then return true end

    local selectorType = type(selector)
    if selectorType == 'function' then
        return selector(container, b) == true
    end

    if selectorType ~= 'string' then
        return false
    end

    local id = selector
    if id:sub(1, 1) == '#' then
        id = id:sub(2)
    end

    return container.getId and container:getId() == id
end

local function _resetForBinding(container, b)
    if not b or (container.isDestroyed and container:isDestroyed()) then return end

    if container.destroyChildren then
        container:destroyChildren()
    else
        for _, entry in ipairs(b.rendered or {}) do
            local widget = entry and entry.widget
            if widget and (not widget.isDestroyed or not widget:isDestroyed()) then
                widget:destroy()
            end
        end
    end

    b.rendered = {}
end

local function _refreshFor(container)
    local b = _forBindings[container]
    if not b or (container.isDestroyed and container:isDestroyed()) then return end

    local controller   = b.controller
    local varName      = b.varName
    local tablePath    = b.tablePath
    local aliases      = b.aliases
    local templateHtml = b.templateHtml
    local onFinished   = b.onFinished

    local list = evalExpr(tablePath, controller)
    if type(list) ~= 'table' then list = {} end

    local newCount = #list
    local oldCount = #b.rendered

    for i = 1, math.min(newCount, oldCount) do
        local entry = b.rendered[i]
        if entry and entry.item ~= list[i] then
            for j = i, oldCount do
                local oldEntry = b.rendered[j]
                if oldEntry and oldEntry.widget and (not oldEntry.widget.isDestroyed or not oldEntry.widget:isDestroyed()) then
                    oldEntry.widget:destroy()
                end
                b.rendered[j] = nil
            end
            oldCount = i - 1
            break
        end
    end

    -- Diff: adicionar itens novos no final
    for i = oldCount + 1, newCount do
        local item  = list[i]
        local index = i - 1

        local extraVars = { [varName] = item, index = index }
        local forKeys = { varName, 'index' }
        local forValues = { item, index }
        for aliasName, aliasExpr in pairs(aliases) do
            if aliasExpr == 'index' then
                extraVars[aliasName] = index
            else
                extraVars[aliasName] = evalExpr(aliasExpr, controller, extraVars)
            end
            forKeys[#forKeys + 1] = aliasName
            forValues[#forValues + 1] = extraVars[aliasName]
        end
        extraVars.keys = table.concat(forKeys, ',')
        extraVars.values = forValues

        local processedHtml = processTemplateHtml(templateHtml, controller, extraVars)

        -- Passar contexto do *for para __applyOrBindHtmlAttribute/onCreateByHTML.
        local previousForCtx = controller.__current_for_ctx
        controller.__current_for_ctx = extraVars
        local htmlId = container.getHtmlRootId and container:getHtmlRootId() or 0
        local newWidget = g_html.createWidgetFromHTML(processedHtml, container, htmlId)
        controller.__current_for_ctx = previousForCtx
        if newWidget then
            newWidget.__html_for_ctx = extraVars
            newWidget.__for_keys = extraVars.keys
            newWidget.__for_values = extraVars.values
            b.rendered[i] = { widget = newWidget, item = item }
        end
    end

    -- Diff: remover itens excedentes do final
    for i = newCount + 1, oldCount do
        local entry = b.rendered[i]
        if entry and entry.widget and (not entry.widget.isDestroyed or not entry.widget:isDestroyed()) then
            entry.widget:destroy()
        end
        b.rendered[i] = nil
    end

    if onFinished and onFinished ~= '' then
        execStmt(onFinished, controller)
    end
end

function UIWidget:__childFor(moduleName, forExpr, templateHtml, childIndex, onFinished)
    if not self or (self.isDestroyed and self:isDestroyed()) then return end

    local controller = G_CONTROLLER_CALLED and G_CONTROLLER_CALLED[moduleName]
    if not controller then
        if g_logger then
            g_logger.warning('[HTML] __childFor: controller não encontrado para "' .. tostring(moduleName) .. '"')
        end
        return
    end

    local varName, tablePath, rest = forExpr:match('^%s*local%s+(%w+)%s+in%s+([^;]+)(.*)')
    if not varName then
        if g_logger then
            g_logger.error('[HTML] *for: expressão inválida: "' .. tostring(forExpr) .. '"')
        end
        return
    end
    tablePath = tablePath:match('^%s*(.-)%s*$') or tablePath
    rest = rest or ''

    local aliases = {}
    for aliasName, aliasExpr in rest:gmatch('local%s+(%w+)%s*=%s*([^;]+)') do
        aliases[aliasName] = (aliasExpr:match('^%s*(.-)%s*$') or aliasExpr)
    end

    local existingBinding = _forBindings[self]
    if existingBinding then
        _resetForBinding(self, existingBinding)
    end

    _forBindings[self] = {
        varName      = varName,
        tablePath    = tablePath,
        aliases      = aliases,
        templateHtml = templateHtml,
        controller   = controller,
        rendered     = {},
        onFinished   = onFinished and onFinished:match('^%s*(.-)%s*$') or nil,
    }

    _refreshFor(self)

    -- Cleanup: destruir widgets filhos quando o container for destruído
    local oldOnDestroy = self.onDestroy
    self.onDestroy = function(widget, ...)
        local b = _forBindings[self]
        if b then
            for _, entry in ipairs(b.rendered) do
                if entry and entry.widget and not entry.widget:isDestroyed() then
                    entry.widget:destroy()
                end
            end
            _forBindings[self] = nil
        end
        if type(oldOnDestroy) == 'function' then
            return oldOnDestroy(widget or self, ...)
        end
    end
end

-- Chamar após modificar listas usadas em *for (ex: addPlayer, removePlayer)
function resetHtmlFor(controller, selector)
    for container, b in pairs(_forBindings) do
        if b.controller == controller and _matchesForSelector(container, b, selector) then
            _resetForBinding(container, b)
        end
    end
end

function refreshHtmlFor(controller, selector)
    for container, b in pairs(_forBindings) do
        if b.controller == controller and _matchesForSelector(container, b, selector) then
            _refreshFor(container)
        end
    end
end
