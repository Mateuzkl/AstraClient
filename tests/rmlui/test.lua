local originalPrint = print
assert(Rml.isAvailable(), 'native RmlUi missing')
assert(print == originalPrint, 'RmlUi replaced the client logger')
local initialContexts = g_rml.getContextCount()
local initialWidgets = g_rml.getWidgetCount()
local timerCalls = 0
local window, model = Rml.createWindow {
    document = '/smoke.rml', model = 'smoke', width = 420, height = 280,
    data = {title = 'Astra C++23 RmlUi', shown = true, name = ''},
}
assert(window and model, 'RML/data model did not load')
print('[RMLUI TEST] document loaded')
local extraStyle = '#caption { height: 37dp; }'
assert(window:setExtraStyleSheet(extraStyle))
assert(window:setExtraStyleSheet(extraStyle), 'repeated identical stylesheet rejected')
local native = g_ui.createWidget('UIWidget')
Rml.host(window, 'slot', native)
local ticks = 0
connect(window, {onRmlUpdate = function() ticks = ticks + 1 end})
Rml.every(window, 10, function() timerCalls = timerCalls + 1 end)

scheduleEvent(function()
    print('[RMLUI TEST] validating initial layout')
    assert(Rml.element(window, 'caption').offset_height == 37, 'extra stylesheet was not applied')
    assert(window:setExtraStyleSheet(''))
    assert(g_rml.supportsAdvancedEffects(), 'GL3 backend failed')
    assert(g_rml.getContextCount() == initialContexts + 1)
    if not native:isVisible() then
        local e = Rml.element(window, 'slot')
        local rect = window:getRect()
        local dimensions = window:getContext().dimensions
        local parent = e
        while parent do
            print(string.format('[RMLUI box] %s offset=%sx%s client=%sx%s width=%s display=%s', tostring(parent.tag_name),
                tostring(parent.offset_width), tostring(parent.offset_height), tostring(parent.client_width), tostring(parent.client_height),
                tostring(parent.style.width), tostring(parent.style.display)))
            parent = parent.parent_node
        end
        print(string.format('[RMLUI diagnostic] ticks=%d dimensions=%dx%d body-width=%s root=%s', ticks, dimensions.x, dimensions.y,
            tostring(window:getDocument().offset_width), tostring(window:getDocument().style.width)))
        print(string.format('[RMLUI diagnostic] window=%s rect=%d,%d %dx%d model=%s element=%s size=%sx%s display=%s visibility=%s',
            tostring(window:isVisible()), rect.x, rect.y, rect.width, rect.height, tostring(model.shown), tostring(e),
            tostring(e and e.offset_width), tostring(e and e.offset_height), tostring(e and e.style.display), tostring(e and e.style.visibility)))
    end
    assert(native:isVisible(), 'hosted OTUI widget not visible')
    assert(native:getParent():isClipping(), 'host clipping missing')
    model.shown = false
    scheduleEvent(function()
        assert(Rml.element(window, 'caption').offset_height ~= 37, 'base stylesheet was not restored')
        assert(not native:isVisible(), 'data-if did not hide native widget')
        model.shown = true
        assert(window:setExtraStyleSheet('#caption { height: 41dp; }'))
        assert(window:reloadDocument(), 'RML reload failed')
        scheduleEvent(function()
            assert(Rml.element(window, 'caption').offset_height == 41, 'reload lost extra stylesheet')
            assert(native:isVisible(), 'host not restored after reload')
            -- Direct DOM dispatch from Lua bypasses the native widget's input hook.
            local document = window:getDocument()
            document:AddEventListener('keydown', function() window:destroy() end, false)
            document:DispatchEvent('keydown', {})
            local callsAtDestroy = timerCalls
            -- Keep the Lua owner alive: destruction, not GC, must retire the tick.
            assert(g_rml.getWidgetCount() == initialWidgets, 'destroyed widget retained native tick registration')
            assert(window:getDocument() == nil, 'destroyed document was exposed')
            assert(window:getContext() == nil, 'destroyed context was recreated')
            scheduleEvent(function()
                assert(timerCalls == callsAtDestroy, 'timer survived widget destruction')
                assert(g_rml.getContextCount() == initialContexts, 'context retained after destroy')
                -- Repeated open/close must not retain native contexts/render managers.
                for i = 1, 30 do
                    local w = g_ui.createWidget('UIRmlWidget', rootWidget)
                    assert(w:getContext())
                    w:destroy()
                end
                scheduleEvent(function()
                    print('[RMLUI TEST] contexts released')
                    assert(g_rml.getContextCount() == initialContexts)
                    assert(g_rml.getWidgetCount() == initialWidgets)
                    collectgarbage('collect')
                    dofile('/render-scene.lua')
                    testRenderPooling(function()
                        print('[RMLUI TEST] PASS: render, models, reload, host visibility, timers and 30 close cycles')
                        g_app.exit()
                    end)
                end, 80)
            end, 80)
        end, 120)
    end, 120)
end, 250)
