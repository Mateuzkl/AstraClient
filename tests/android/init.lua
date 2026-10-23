-- Isolated APK fixture: no server, account, production init or personal modules.
APP_NAME = 'astra_android_build_smoke'
g_modules.discoverModules()
g_modules.ensureModuleLoaded('corelib')
local panel = g_ui.createWidget('UIWidget', g_ui.getRootWidget())
panel:setRect({x=20,y=20,width=300,height=220})
panel:setBackgroundColor('#203040')
panel:setClipping(true)
for i=1,80 do
    local child = g_ui.createWidget('UIWidget',panel)
    child:setRect({x=(i*17)%350,y=(i*23)%250,width=50,height=40})
    child:setBackgroundColor(string.format('#%02x%02x%02x99',i*3,i*2,i))
    child:setOpacity(0.7)
end
local function waitPng(file,done,remaining)
    if g_resources.fileExists(file) then
        local ok,data=pcall(g_resources.readFileContents,file)
        local signature=string.char(137,80,78,71,13,10,26,10)
        local ending=string.char(0,0,0,0,73,69,78,68,174,66,96,130)
        if ok and #data>1024 and data:sub(1,8)==signature and data:sub(-12)==ending then done(data); return end
    end
    assert(remaining>0,'Android screenshot timed out')
    scheduleEvent(function() waitPng(file,done,remaining-1) end,100)
end
-- A complete PNG from an earlier app launch must never satisfy this run's wait.
local capturePrefix = 'android-' .. g_crypt.genUUID()
local heapFile, poolFile = capturePrefix .. '-heap.png', capturePrefix .. '-pool.png'
g_app.setDrawCommandPooling(false)
scheduleEvent(function()
    g_app.doScreenshot(heapFile)
    waitPng(heapFile,function(heap)
        g_app.setDrawCommandPooling(true)
        scheduleEvent(function()
            g_app.doScreenshot(poolFile)
            waitPng(poolFile,function(pool)
                assert(heap==pool,'Android pooling changed rendered pixels')
                panel:destroy()
                print('[ANDROID SMOKE] PASS: startup, OTUI, C++23 and identical pooled pixels')
                g_app.exit()
            end,100)
        end,500)
    end,100)
end,1000)
