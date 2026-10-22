-- Real native RmlUi rendering and DOM events; never load a server or user mods.
assert(Rml.isAvailable())
g_window.resize({width=1480,height=1000})
local window,activeBefore
local function element(id) return assert(Rml.element(window,id),id) end
local function click(id) element(id):DispatchEvent('click',{}) end
local function points() return tonumber(element('available-points').inner_rml) end
local function waitPng(file,done,attempts)
    if g_resources.fileExists(file) then
        local ok,data=pcall(g_resources.readFileContents,file)
        if ok and #data > 20000 and data:sub(-12) == string.char(0,0,0,0,73,69,78,68,174,66,96,130) then done();return end
    end
    assert(attempts > 0,'skill tree screenshot did not complete')
    scheduleEvent(function() waitPng(file,done,attempts-1) end,100)
end
local function screenshot(name,done)
    local file='astra-skilltree-' .. name .. '-' .. g_clock.millis() .. '.png'
    g_app.doScreenshot(file)
    waitPng(file,function()
        print('[SKILLTREE SCREENSHOT] ' .. g_resources.getWriteDir() .. '/' .. file)
        done()
    end,50)
end
local steps={
    function(next)
        assert(points() == 9999 and element('selected-title').inner_rml == 'Golpe Brutal')
        assert(element('skill-11'):IsClassSet('on-path') and element('skill-1'):IsClassSet('on-path'))
        assert(not element('skill-3'):IsClassSet('on-path'))
        assert(element('tree-canvas'):QuerySelector('.connection.active.on-path'),'connected path did not light up')
        screenshot('tree',next)
    end,
    function(next) click('upgrade');next() end,
    function(next)
        assert(points() == 9998,'local upgrade did not spend one point')
        click('skill-6');next()
    end,
    function(next)
        assert(element('upgrade'):HasAttribute('disabled'),'disconnected talent is enabled')
        assert(points() == 9998,'selecting a blocked talent spent points')
        assert(element('skill-3'):IsClassSet('on-path') and not element('skill-2'):IsClassSet('on-path'))
        click('upgrade');next() -- Bypass hit-testing to verify the callback also enforces prerequisites.
    end,
    function(next)
        assert(points() == 9998,'a disconnected allocation was accepted')
        click('next-required');next()
    end,
    function(next)
        assert(element('selected-title').inner_rml == 'Instinto de Batalha','guide skipped an earlier prerequisite')
        click('upgrade');next()
    end,
    function(next)
        assert(points() == 9997)
        click('skill-6');next()
    end,
    function(next)
        assert(not element('upgrade'):HasAttribute('disabled'),'completed prerequisites did not unlock the talent')
        activeBefore=#element('tree-canvas'):QuerySelectorAll('.connection.active')
        click('upgrade');next()
    end,
    function(next)
        assert(points() == 9996 and element('skill-6'):IsClassSet('owned'))
        assert(#element('tree-canvas'):QuerySelectorAll('.connection.active') > activeBefore,'new connection did not glow')
        click('build-info');next()
    end,
    function(next)
        screenshot('build',function()
            local count=#element('build-skill-list'):QuerySelectorAll('.build-skill:not([data-for])')
            assert(count == 11,'build omitted allocated talents: ' .. count)
            next()
        end)
    end,
    function(next) click('close-build');click('category-2');next() end,
    function(next) click('upgrade');next() end,
    function(next) assert(points() == 9995);click('reset');next() end,
    function(next) click('confirm-reset');next() end,
    function(next) assert(points() == 9996,'category refund was incorrect');click('refill');next() end,
    function(next) assert(points() == 9999);click('category-3');next() end,
    function(next) assert(element('skill-22'));click('category-4');next() end,
    function(next) assert(element('skill-22'));click('category-5');next() end,
    function(next) assert(element('skill-22'));click('close-tree');next() end,
    function(next)
        assert(window:isDestroyed() and g_rml.getContextCount() == 0,'closing retained the RmlUi context')
        toggle();window=assert(rootWidget:getChildById('rmlSkillTreeDemo'));next()
    end,
    function(next) assert(points() == 9999,'reopening lost the local allocation');click('close-tree');next() end,
    function()
        assert(window:isDestroyed() and g_rml.getContextCount() == 0)
        print('[RMLUI TEST] PASS: skill tree render, 9999 points, connected allocation, glowing edges, build info, refunds and safe close/reopen')
        g_app.exit()
    end,
}
local function run(index)
    steps[index](function() scheduleEvent(function() run(index+1) end,120) end)
end
local function openWhenSized(attempts)
    local size,actual=rootWidget:getSize(),g_window.getSize()
    if size.width < 1000 or size.height < 600 or size.width ~= actual.width or size.height ~= actual.height then
        assert(attempts > 0,'test viewport did not resize')
        scheduleEvent(function() openWhenSized(attempts-1) end,100)
        return
    end
    dofile('/spell-catalog.lua')
    dofile('/modules/game_rmlskilltree/model.lua')
    dofile('/modules/game_rmlskilltree/skilltree.lua')
    toggle()
    window=assert(rootWidget:getChildById('rmlSkillTreeDemo'))
    scheduleEvent(function() run(1) end,400)
end
scheduleEvent(function() openWhenSized(30) end,180)
