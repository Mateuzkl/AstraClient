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
        -- savePNG creates the file before encoding/writing it on another thread.
        -- Consume the bytes only after both the signature and final IEND are present.
        if g_resources.fileExists(file) then
            local ok, data = pcall(g_resources.readFileContents, file)
            local signature = string.char(137, 80, 78, 71, 13, 10, 26, 10)
            local ending = string.char(0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130)
            if ok and data:sub(1, 8) == signature and data:sub(-12) == ending then
                callback(data)
                return
            end
        end
        assert(attempts > 0, 'screenshot did not complete: ' .. file)
        scheduleEvent(function() waitFile(file, callback, attempts-1) end, 100)
    end
    local prefix = 'render-' .. g_crypt.genUUID()
    print('[RENDER POOL TEST] scene ready')
    local pool = prefix .. '-pool.png'
    g_app.setDrawCommandPooling(false)
    local function comparePool(original)
            g_app.setDrawCommandPooling(true)
            scheduleEvent(function()
                g_app.doScreenshot(pool)
                waitFile(pool, function(pooled)
                    assert(#original > 1024, 'render test captured an empty scene')
                    assert(original == pooled, 'pool changed rendered pixels/order/clipping/opacity')
                    -- Hidden desktop windows must capture now, not on restore.
                    g_window.hide()
                    local hidden=prefix .. '-hidden.png'
                    scheduleEvent(function()
                        assert(not g_window.isVisible(), 'test window did not hide')
                        g_app.doScreenshot(hidden)
                        waitFile(hidden,function(hiddenImage)
                            assert(hiddenImage == pooled, 'hidden capture was lost or captured a different scene')
                            g_window.show()
                            panel:destroy()
                            print('[RENDER POOL TEST] PASS: identical pixels with heap/pooled/hidden captures')
                            done()
                        end,50)
                    end,150)
                end, 50)
            end, 350)
    end
    -- Startup resize/viewport events can reach the graphics thread after the
    -- first UI queue. Require two identical heap frames before changing mode;
    -- otherwise a projection change is falsely attributed to command pooling.
    local function stableHeap(previous, attempts)
        local heap=prefix .. '-heap-' .. attempts .. '.png'
        g_app.doScreenshot(heap)
        waitFile(heap,function(frame)
            if previous == frame then comparePool(frame); return end
            assert(attempts > 0, 'heap scene did not stabilize before pooling comparison')
            scheduleEvent(function() stableHeap(frame,attempts-1) end,350)
        end,50)
    end
    scheduleEvent(function() stableHeap(nil,4) end,350)
end
