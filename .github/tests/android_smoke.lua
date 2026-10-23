local runId, priorCaptures = 0, {['android-heap.png']=true, ['android-pool.png']=true}
local function run(mode)
    runId = runId+1
    g_crypt = {genUUID=function() return 'test-run-' .. runId end}
    local pending, captures, pooling, exited = {}, {}, {}, false
    local widget = setmetatable({}, {__index=function() return function() end end})
    g_ui={getRootWidget=function() return widget end,createWidget=function() return widget end}
    g_modules={discoverModules=function() end,ensureModuleLoaded=function(name) assert(name=='corelib') end}
    local reads={}
    local png=string.char(137,80,78,71,13,10,26,10)..string.rep('p',2048)..
        string.char(0,0,0,0,73,69,78,68,174,66,96,130)
    g_app={
        setDrawCommandPooling=function(value) pooling[#pooling+1]=value end,
        doScreenshot=function(file)
            assert(file:find('android-test-run-' .. runId .. '-',1,true)==1, 'capture lacks a per-run name')
            assert(not priorCaptures[file], 'capture reused a previous run filename')
            captures[file]=true;reads[file]=0
        end,
        exit=function() exited=true end
    }
    g_resources={
        fileExists=function(file) return priorCaptures[file] or (mode~='missing' and captures[file]) end,
        readFileContents=function(file)
            if priorCaptures[file] then return png end
            reads[file]=reads[file]+1
            if reads[file]==1 then error('PNG still being written') end
            if reads[file]==2 then return png:sub(1,80) end
            if mode=='different' and file:match('%-pool%.png$') then return png:gsub('p','q') end
            return png
        end
    }
    scheduleEvent=function(callback) pending[#pending+1]=callback end
    local ok,err=pcall(function()
        dofile('tests/android/init.lua')
        local i=1
        while i<=#pending do pending[i]();i=i+1;assert(i<250,'unbounded Android smoke polling') end
    end)
    if mode=='ok' then
        assert(ok,err)
        assert(exited and #pooling==2 and pooling[1]==false and pooling[2]==true)
        for _,count in pairs(reads) do assert(count>=3,'partial PNG accepted') end
        for file in pairs(captures) do priorCaptures[file]=true end
    else
        assert(not ok and not exited)
        assert(tostring(err):find(mode=='missing' and 'timed out' or 'changed rendered pixels',1,true),err)
    end
end
run('ok');run('ok');run('missing');run('different')
print('Android APK fixture: PASS (unique runs, stale/partial PNG rejection, identical pixels and bounded negative cases)')
