-- Real native RmlUi rendering and DOM events; never load a server or user mods.
assert(Rml.isAvailable())
g_window.resize({width=1920,height=1080})
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
local function bounds()
    local size=window:getSize()
    local root=rootWidget:getSize()
    assert(size.width <= root.width-20 and size.height <= root.height-20, 'window exceeds usable client area')
    for _,id in ipairs({'upgrade','reset','close-tree','refill','help','build-info','resize-tree'}) do
        local rect=assert(Rml.elementRect(window,id),id)
        local clip=Rml.clipRect(window,id)
        assert(rect.x >= clip.x-1 and rect.y >= clip.y-1 and rect.x+rect.width <= clip.x+clip.width+1 and rect.y+rect.height <= clip.y+clip.height+1, 'essential action clipped: ' .. id)
    end
    assert(#element('tree-canvas'):QuerySelectorAll('.skill-node:not([data-for])') == 22)
end
local function resolutions(done,index)
    local sizes={{1366,768},{1280,720},{1024,768},{800,600}}
    local target=sizes[index]
    if not target then done();return end
    g_window.resize({width=target[1],height=target[2]})
    scheduleEvent(function()
        local actual=rootWidget:getSize()
        print(string.format('[SKILLTREE VIEWPORT] requested=%dx%d actual=%dx%d window=%dx%d',target[1],target[2],actual.width,actual.height,window:getWidth(),window:getHeight()))
        bounds()
        screenshot('compact-' .. target[1],function() resolutions(done,index+1) end)
    end,500)
end
local steps={
    function(next)
        bounds()
        print(string.format('[SKILLTREE VIEWPORT] requested=1920x1080 actual=%dx%d window=%dx%d',rootWidget:getWidth(),rootWidget:getHeight(),window:getWidth(),window:getHeight()))
        assert(points() == 9999 and element('selected-title').inner_rml == 'Golpe Brutal')
        assert(element('skill-11'):IsClassSet('on-path') and element('skill-1'):IsClassSet('on-path'))
        assert(not element('skill-3'):IsClassSet('on-path'))
        assert(element('tree-canvas'):QuerySelector('.connection.active.on-path'),'connected path did not light up')
        -- Clip only the sprite's circular parent: the outer rank/glow must remain visible.
        local node=element('skill-11')
        local inner=node:QuerySelector('.node-inner')
        local portrait=window:getDocument():QuerySelector('.portrait-rim')
        assert(inner.style['overflow-x'] == 'hidden' and inner.style['overflow-y'] == 'hidden','sprite escaped the node circle')
        assert(portrait.style['overflow-x'] == 'hidden' and portrait.style['overflow-y'] == 'hidden','detail sprite escaped its circle')
        assert(node.style['overflow-x'] == 'visible' and node:QuerySelector('.rank'),'circular clipping hid the outer rank/glow')
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
        assert(element('build-dialog'):QuerySelector('.build-scroll').client_height > 100,'build summary collapsed')
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
    function(next) assert(element('skill-22'));click('resize-tree');next() end,
    function(next) bounds();click('help');next() end,
    function(next) click('help');click('resize-tree');next() end,
    function(next) bounds();resolutions(next,1) end,
    function(next) click('build-info');next() end,
    function(next)
        assert(element('build-dialog'):QuerySelector('.build-scroll').client_height > 100,'small viewport collapsed the build summary')
        local r,c=Rml.elementRect(window,'close-build'),Rml.clipRect(window,'close-build')
        assert(r.y+r.height <= c.y+c.height+1,'build close action clipped')
        click('close-build');click('close-tree');next()
    end,
    function(next)
        assert(window:isDestroyed() and g_rml.getContextCount() == 0,'closing retained the RmlUi context')
        toggle();window=assert(rootWidget:getChildById('rmlSkillTreeDemo'));next()
    end,
    function(next) assert(points() == 9999,'reopening lost the local allocation');click('close-tree');next() end,
    function()
        assert(window:isDestroyed() and g_rml.getContextCount() == 0)
        -- Empty contexts/Lua models do not exercise cached atlas textures. Let
        -- the real document render on each reopen before retiring its renderer.
        local cycle = 0
        local function reopen()
            cycle = cycle+1
            toggle()
            window = assert(rootWidget:getChildById('rmlSkillTreeDemo'))
            scheduleEvent(function()
                assert(window:getDocument() and Rml.element(window,'skill-22'))
                click('close-tree')
                scheduleEvent(function()
                    assert(window:isDestroyed() and g_rml.getContextCount() == 0, 'reopen retained a context')
                    if cycle < 30 then reopen() else
                        print('[RMLUI TEST] PASS: skill tree render, 9999 points, connected allocation, build info, refunds and 30 rendered atlas reopens')
                        g_app.exit()
                    end
                end,40)
            end,120)
        end
        reopen()
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
