-- Execute the real smoke scene against a deliberately incomplete async PNG writer.
local sequence=0
local function run(missing)
  local tasks, files, reads, modes, completed = {}, {}, {}, {}, false
  local widget = setmetatable({}, {__index=function() return function() end end})
  rootWidget = widget
  g_ui = {createWidget=function() return widget end}
  g_clock = {millis=function() return 42 end}
  sequence=sequence+1
  g_crypt={genUUID=function() return 'fixture-'..sequence end}
  local visible=true
  g_window={hide=function() visible=false end,show=function() visible=true end,isVisible=function() return visible end}
  g_app = {
    setDrawCommandPooling=function(value) modes[#modes+1]=value end,
    doScreenshot=function(file) files[file]=true; reads[file]=0 end,
  }
  local png = string.char(137,80,78,71,13,10,26,10) .. string.rep('x', 2048) ..
    string.char(0,0,0,0,73,69,78,68,174,66,96,130)
  g_resources = {
    fileExists=function(file) return not missing and files[file] end,
    readFileContents=function(file)
      reads[file]=reads[file]+1
      if reads[file] == 1 then error('writer is still opening the file') end
      if reads[file] == 2 then return png:sub(1, 100) end
      return png
    end,
  }
  scheduleEvent=function(callback) tasks[#tasks+1]=callback end
  dofile('tests/rendering/scene.lua')
  local ok, err = pcall(function()
    testRenderPooling(function() completed=true end)
    local i=1
    while i <= #tasks do tasks[i](); i=i+1; assert(i < 200, 'unbounded screenshot polling') end
  end)
  if missing then
    assert(not ok and tostring(err):find('screenshot did not complete', 1, true))
    assert(not completed)
  else
    assert(ok, err)
    assert(completed and #modes == 2 and modes[1] == false and modes[2] == true)
    for _, count in pairs(reads) do assert(count >= 3, 'partial PNG was accepted') end
  end
end
run(false)
run(true)
local source=assert(io.open('src/framework/core/graphicalapplication.cpp','rb'))
local cpp=source:read('*a');source:close()
local request=assert(cpp:match('void GraphicalApplication::doScreenshot.-\n}'))
assert(not request:find('glReadPixels',1,true), 'screenshot reads the discarded post-swap buffer')
local swaps=0
for prefix in cpp:gmatch('(.-)g_window%.swapBuffers%(%);') do
  assert(prefix:find('capturePendingScreenshots();',1,true), 'a render loop swaps before capturing pending screenshots')
  swaps=swaps+1
end
assert(swaps == 2, 'both native and browser capture boundaries must be tested')
print('Render scene: PASS (partial/failed PNG reads and bounded timeout)')
