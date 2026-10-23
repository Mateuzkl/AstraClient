local originalPrint = print
assert(Rml.isAvailable(), 'native RmlUi missing')
assert(print == originalPrint, 'RmlUi replaced the client logger')
-- Startup already loaded this variable font. Its resource aliases must not
-- re-enter RmlUi's duplicate-face loader or invalidate FreeType face memory.
for i=1,20 do
    assert(g_rml.loadFontFace('/fonts/rml/Cinzel.ttf'))
    assert(g_rml.loadFontFace('/data/fonts/rml/Cinzel.ttf'))
    assert(g_rml.loadFontFace('fonts/rml/Cinzel.ttf'))
end
local initialContexts = g_rml.getContextCount()
local initialWidgets = g_rml.getWidgetCount()
local function testUnloadReentrancy(done)
    local w = Rml.createWindow {
        document='/smoke.rml', model='smoke', width=420, height=280,
        data={title='Unload replacement', shown=true, name=''},
    }
    local old = w:getDocument()
    local unloaded = 0
    old:AddEventListener('unload', function()
        unloaded=unloaded+1
        assert(w:getDocument() == nil, 'unload exposed a document being closed')
        w:unloadDocument() -- Nested unload must not dispatch the old document again.
        assert(w:loadDocument('/smoke.rml'), 'unload listener could not load its replacement')
    end, false)
    w:unloadDocument()
    assert(unloaded == 1 and w:hasDocument(), 'outer unload discarded the replacement document')
    w:destroy()
    local closing = Rml.createWindow {
        document='/smoke.rml', model='smoke', width=420, height=280,
        data={title='Destroy during unload', shown=true, name=''},
    }
    closing:getDocument():AddEventListener('unload', function() closing:destroy() end, false)
    assert(not closing:loadDocument('/smoke.rml'), 'load continued after unload destroyed the host')
    scheduleEvent(function()
        assert(g_rml.getContextCount() == initialContexts and g_rml.getWidgetCount() == initialWidgets)
        print('[RMLUI TEST] reentrant unload preserved replacement/retired destroyed host')
        done()
    end, 100)
end
local function testDestroyFromUnload(done)
    local first = Rml.createWindow {
        document='/smoke.rml', model='smoke', width=420, height=280,
        data={title='First', shown=true, name=''},
    }
    local second = Rml.createWindow {
        document='/smoke.rml', model='smoke', width=420, height=280,
        data={title='Second', shown=true, name=''},
    }
    first:getDocument():AddEventListener('unload', function() second:destroy() end, false)
    first:destroy()
    scheduleEvent(function()
        assert(second:isDestroyed(), 'unload callback did not destroy the second host')
        assert(g_rml.getContextCount() == initialContexts, 'unload callback stranded a deferred context release')
        assert(g_rml.getWidgetCount() == initialWidgets)
        done()
    end, 100)
end
local function testModelLifetime(done)
    local payloads = setmetatable({}, {__mode='k'})
    local models, children = {}, {}
    -- Two live contexts must be allowed to use the same document/model name.
    for i=1,2 do
        local payload = {bytes=string.rep('x', 65536)}
        payloads[payload] = true
        local w, m = Rml.createWindow {
            document='/smoke.rml', model='smoke', width=420, height=280,
            data={title='Lifetime '..i, shown=true, name='', rows={{value=i}},
                Hold=function() return payload end},
        }
        assert(w and m)
        models[i], children[i] = m, m.rows
        -- Reopening an existing model must not orphan its original registry refs.
        assert(w:getContext():OpenDataModel('smoke', {}) == m, 'duplicate open replaced a live data model')
        if i == 1 then
            w:getContext():CloseDataModel('smoke')
            assert(not pcall(function() return m.title end), 'explicit close retained a live model')
            local reopened = w:getContext():OpenDataModel('smoke', {title='Reopened', shown=true, name=''})
            assert(reopened and reopened ~= m)
        end
        w:destroy()
    end
    scheduleEvent(function()
        collectgarbage('collect'); collectgarbage('collect')
        assert(next(payloads) == nil, 'closed RmlUi contexts retained Lua callback payloads')
        for i=1,2 do
            assert(not pcall(function() return models[i].title end), 'destroyed context left a live model')
            assert(not pcall(function() return children[i][1] end), 'closed nested proxy remained usable')
        end
        assert(g_rml.getContextCount() == initialContexts and g_rml.getWidgetCount() == initialWidgets)
        print('[RMLUI TEST] model callbacks released; retained model/proxy access safely rejected')
        done()
    end, 100)
end
local function testDestroyDuringUpdate(done)
    local closing = Rml.createWindow {
        document='/smoke.rml', model='smoke', width=420, height=280,
        data={title='Destroy during update', shown=true, name=''},
    }
    assert(closing)
    local updates, lateLayouts = 0, 0
    connect(closing, {onRmlUpdate=function()
        updates=updates+1
        closing:destroy()
        -- destroy clears the Lua field table. Reattach a trap so the test detects
        -- a native post-destroy call even when the old handler was already cleared.
        closing.onRmlLayout=function() lateLayouts=lateLayouts+1 end
    end})
    scheduleEvent(function()
        assert(updates == 1 and closing:isDestroyed(), 'destroy-on-update did not execute')
        assert(lateLayouts == 0, 'layout callback ran after destruction in onRmlUpdate')
        assert(g_rml.getContextCount() == initialContexts and g_rml.getWidgetCount() == initialWidgets)
        done()
    end, 100)
end
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
                    testDestroyDuringUpdate(function()
                        testDestroyFromUnload(function()
                            testModelLifetime(function()
                                testUnloadReentrancy(function() testRenderPooling(function()
                                    print('[RMLUI TEST] PASS: render, models, reload, host visibility, reentrant destruction, timers and 30 close cycles')
                                    g_app.exit()
                                end) end)
                            end)
                        end)
                    end)
                end, 80)
            end, 80)
        end, 120)
    end, 120)
end, 250)
