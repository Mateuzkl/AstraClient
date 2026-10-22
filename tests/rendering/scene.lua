-- Compare rendered pixels, not just command counts. No server/assets/user mods.
function testRenderPooling(done)
    print('[RENDER POOL TEST] creating overlapping scene')
    local panel = g_ui.createWidget('UIWidget', rootWidget)
    panel:setRect({x=40,y=40,width=560,height=360})
    panel:setBackgroundColor('#102030')
    panel:setClipping(true)
    for i = 1, 240 do
        local child = g_ui.createWidget('UIWidget', panel)
        child:setRect({x=20+(i*31)%600,y=20+(i*17)%400,width=75,height=65})
        child:setBackgroundColor(string.format('#%02x%02x%02x99', i%256, (i*3)%256, (i*7)%256))
        child:setBorderWidth(2)
        child:setBorderColor('#d0c080bb')
        if i % 3 == 0 then child:setOpacity(0.6) end
        if i % 7 == 0 then child:setRotation(15) end
        if i % 5 == 0 then
            child:setImageSource('/images/ui/background.png')
            child:setImageRepeated(true)
        end
    end
    local function waitFile(file, callback, attempts)
        if g_resources.fileExists(file) then callback(); return end
        assert(attempts > 0, 'screenshot did not complete: ' .. file)
        scheduleEvent(function() waitFile(file, callback, attempts-1) end, 100)
    end
    local prefix = 'render-' .. tostring(g_clock.millis())
    print('[RENDER POOL TEST] scene ready')
    local heap, pool = prefix .. '-heap.png', prefix .. '-pool.png'
    g_app.setDrawCommandPooling(false)
    scheduleEvent(function()
        g_app.doScreenshot(heap)
        waitFile(heap, function()
            g_app.setDrawCommandPooling(true)
            scheduleEvent(function()
                g_app.doScreenshot(pool)
                waitFile(pool, function()
                    local original = g_resources.readFileContents(heap)
                    assert(#original > 1024, 'render test captured an empty scene')
                    assert(original == g_resources.readFileContents(pool), 'pool changed rendered pixels/order/clipping/opacity')
                    panel:destroy()
                    print('[RENDER POOL TEST] PASS: identical pixels with heap and pooled commands')
                    done()
                end, 50)
            end, 350)
        end, 50)
    end, 350)
end
