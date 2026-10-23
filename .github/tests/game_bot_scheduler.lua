local executorScript = assert(arg[1], "missing executor.lua path")
local mainScript = assert(arg[2], "missing functions/main.lua path")
local expectLiveDrain = arg[3] == "--expect-live-drain"

-- Load the real executor and scheduling API with only client/UI/clock stubs.
local now, context, messages
---Provide the corelib extension for the fixture's only mocked config filename.
function string:split(separator)
  assert(self == "fixture.lua" and separator == ".")
  return { "fixture", "lua" }
end
g_clock = { millis = function() return now end, realMillis = function() return now end }
g_game = { getLocalPlayer = function() return {} end }
g_app, g_platform, G = {}, {}, {}
g_ui = { createWidget = function() return {} end, importStyle = function() end }
g_resources = {
  listDirectoryFiles = function() return { "fixture.lua" } end,
  readFileContents = function() return "" end
}
---Load the actual scheduling API while omitting unrelated panels and functions.
function dofiles(directory)
  if directory == "functions" then
    context = G.botContext
    assert(loadfile(mainScript))()
  else
    assert(directory == "panels")
  end
end

---Create a fresh real executor with an isolated context and a controlled clock.
local function newBot()
  now, messages = 1000, {}
  assert(loadfile(executorScript))()
  local tabs = { addTab = function() return { tabPanel = { content = {} } } end }
  local websockets = {}
  local bot = executeBot("fixture", {}, tabs, function(level, text)
    messages[#messages + 1] = { level = level, text = text }
  end, function() end, function() end, websockets)
  assert(context._websockets == websockets, "websocket context must be preserved")
  return context, bot
end

---Assert exact identity or value equality with a readable failure label.
local function equal(actual, expected, message)
  assert(actual == expected, string.format("%s: expected %s, got %s",
    message or "value", tostring(expected), tostring(actual)))
end

local passed = 0
---Run a scenario synchronously and count it only after every assertion passes.
local function test(name, callback)
  callback()
  passed = passed + 1
  print("PASS " .. name)
end

---Count interpreted Lua instructions regardless of the queue's iterator style.
---Suspend counting only inside the measured queue's real table.remove: some
---LuaJIT builds implement its inherited array shift in bytecode. Other queues
---remain counted. Restore hooks, removal and JIT state
---before propagating a failure; no instruction limit interrupts the callback.
local function countLuaInstructions(queue, callback)
  local previousHook, previousMask, previousCount = debug.gethook()
  local jitEnabled = jit and jit.status()
  if jit then jit.off(); jit.flush() end
  local instructions = 0
  local hook = function() instructions = instructions + 100 end
  local originalRemove = table.remove
  table.remove = function(list, ...)
    if list ~= queue then return originalRemove(list, ...) end
    debug.sethook()
    local ok, removed = pcall(originalRemove, list, ...)
    debug.sethook(hook, "", 100)
    assert(ok, removed)
    return removed
  end
  debug.sethook(hook, "", 100)
  local ok, result = pcall(callback)
  table.remove = originalRemove
  debug.sethook(previousHook, previousMask, previousCount)
  if jitEnabled then jit.on() end
  assert(ok, result)
  return instructions
end

---Contrast a finite same-pass baseline chain with progress across generations.
local function finiteChain()
  local c, bot = newBot()
  local calls = 0
  local callback
  callback = function()
    calls = calls + 1
    assert(calls <= 32, "finite chain must stop")
    if calls < 32 then c.schedule(0, callback) end
  end
  c.schedule(0, callback)
  bot.script()
  if expectLiveDrain then
    equal(calls, 32, "baseline chain consumed in one pass")
    equal(#c._scheduler, 0, "baseline queue drained")
  else
    equal(calls, 1, "one generation per pass")
    for pass = 2, 32 do bot.script(); equal(calls, pass, "chain progress") end
    equal(#c._scheduler, 0, "finite chain eventually completes")
  end
end

if expectLiveDrain then
  test("baseline finite same-pass chain", finiteChain)
  print("game_bot scheduler baseline reproduced: OK")
  return
end

test("finite chain progresses across passes", finiteChain)

test("continuous chain stays bounded across 10000 passes", function()
  local c, bot = newBot()
  local calls = 0
  local callback
  callback = function() calls = calls + 1; c.schedule(0, callback) end
  c.schedule(0, callback)
  for pass = 1, 10000 do
    bot.script()
    equal(calls, pass, "one execution per pass")
    equal(#c._scheduler, 1, "one pending continuation")
    now = now + 10
  end
end)

test("previous deadlines and advancing clock preserve order", function()
  local c, bot = newBot()
  local seen = {}
  c.schedule(20, function() seen[#seen + 1] = "future" end)
  c.schedule(0, function() seen[#seen + 1] = "first"; now = now + 15 end)
  c.schedule(10, function() seen[#seen + 1] = "old" end)
  bot.script()
  equal(table.concat(seen, ","), "first,old")
  equal(#c._scheduler, 1)
  now = 1020; bot.script()
  equal(table.concat(seen, ","), "first,old,future")
end)

test("equal deadline FIFO remains unchanged", function()
  local c, bot = newBot()
  local seen = {}
  for index = 1, 40 do
    local id = index
    c.schedule(0, function() seen[#seen + 1] = id end)
  end
  bot.script()
  for index = 1, 40 do equal(seen[index], index, "same deadline FIFO") end
end)

test("new earlier task cannot replace the current removal", function()
  local c, bot = newBot()
  local seen = {}
  c.schedule(0, function()
    seen[#seen + 1] = "current"
    c.schedule(-10, function() seen[#seen + 1] = "new" end)
  end)
  c.schedule(1, function() seen[#seen + 1] = "old" end)
  now = 1001; bot.script()
  equal(table.concat(seen, ","), "current,old")
  equal(#c._scheduler, 1)
  bot.script()
  equal(table.concat(seen, ","), "current,old,new")
end)

test("multiple new deadlines are retained in sorted order", function()
  local c, bot = newBot()
  local seen = {}
  c.schedule(0, function()
    c.schedule(10, function() seen[#seen + 1] = "future" end)
    c.schedule(0, function() seen[#seen + 1] = "zero" end)
    c.schedule(-1, function() seen[#seen + 1] = "negative" end)
  end)
  bot.script(); equal(#seen, 0); equal(#c._scheduler, 3)
  bot.script(); equal(table.concat(seen, ","), "negative,zero")
  now = 1010; bot.script()
  equal(table.concat(seen, ","), "negative,zero,future")
end)

test("callback error clears execution context and preserves following work", function()
  local c, bot = newBot()
  local calls = 0
  c.schedule(0, function()
    c._currentExecution = {}
    error("expected scheduled callback failure")
  end)
  c.schedule(1, function()
    equal(c._currentExecution, nil, "error cleanup before following callback")
    calls = calls + 1
  end)
  now = 1001; bot.script()
  equal(calls, 1); equal(#messages, 1); equal(#c._scheduler, 0)
  equal(c._currentExecution, nil)
end)

test("throwing error reporter leaves unexecuted tasks queued", function()
  local c, bot = newBot()
  local calls = 0
  c.schedule(0, function() c._currentExecution = {}; error("expected failure") end)
  c.schedule(1, function() calls = calls + 1 end)
  c.schedule(2, function() calls = calls + 1 end)
  c.error = function() error("expected reporter failure") end
  now = 1002
  equal(pcall(bot.script), false)
  equal(c._currentExecution, nil); equal(#c._scheduler, 2); equal(calls, 0)
  bot.script(); equal(calls, 2); equal(#c._scheduler, 0)
end)

test("successful task also clears execution context", function()
  local c, bot = newBot()
  c.schedule(0, function() c._currentExecution = {} end)
  bot.script(); equal(c._currentExecution, nil)
end)

test("macro work enters this pass with unchanged intervals", function()
  local c, bot = newBot()
  local calls = 0
  local macro = c.macro(75, function()
    c.schedule(0, function() calls = calls + 1 end)
  end)
  macro.lastExecution = 0
  bot.script()
  equal(calls, 1); equal(macro.timeout, 75); equal(macro.lastExecution, 1000)
  bot.script(); equal(calls, 1, "macro must wait for its existing interval")
  local minimum = c.macro(1, function() end)
  equal(minimum.timeout, 50, "existing macro minimum")
end)

test("macro error cleanup still precedes scheduler", function()
  local c, bot = newBot()
  local macro = c.macro(50, function() error("expected macro failure") end)
  macro.lastExecution = 0
  c.schedule(0, function() equal(c._currentExecution, nil) end)
  bot.script(); equal(c._currentExecution, nil); equal(#messages, 1)
end)

test("future-only queue remains untouched", function()
  local c, bot = newBot()
  c.schedule(100, function() end)
  local queue, task = c._scheduler, c._scheduler[1]
  for _ = 1, 100 do bot.script() end
  equal(c._scheduler, queue); equal(c._scheduler[1], task); equal(#queue, 1)
end)

test("due work does not scan a growing future backlog in Lua", function()
  ---Build the queue before measuring its one due callback and future boundary.
  local function measureDuePass(futureCount)
    local c, bot = newBot()
    local calls = 0
    local future = function() error("future callback must not run") end
    for index = 1, futureCount do c.schedule(100000 + index, future) end
    local firstFuture, lastFuture = c._scheduler[1], c._scheduler[futureCount]
    c.schedule(0, function() calls = calls + 1 end)
    local instructions = countLuaInstructions(c._scheduler, bot.script)
    equal(calls, 1); equal(#c._scheduler, futureCount)
    equal(c._scheduler[1], firstFuture); equal(c._scheduler[futureCount], lastFuture)
    return instructions
  end
  local small = measureDuePass(100)
  local large = measureDuePass(10000)
  -- A generous relative budget accommodates hook granularity and runtime
  -- differences while rejecting linear Lua scans via ipairs, pairs or indexing.
  assert(large <= small + 1000, string.format(
    "future backlog Lua instructions grew with queue size: small=%d, large=%d", small, large))
end)

test("instruction measurement restores instrumentation after failure", function()
  local originalHook, originalMask, originalCount = debug.gethook()
  local originalRemove = table.remove
  local originalJit = jit and jit.status()
  local previousHook = function() end
  debug.sethook(previousHook, "", 1000000)
  if jit then jit.off() end
  local queue = { "removed" }
  local ok, result = pcall(countLuaInstructions, queue, function()
    equal(table.remove(queue, 1), "removed")
    error("expected instruction measurement failure")
  end)
  local restoredHook, restoredMask, restoredCount = debug.gethook()
  local restoredRemove = table.remove
  local restoredJit = jit and jit.status()
  -- Restore the fixture's own state even if an assertion detects bad cleanup.
  debug.sethook(originalHook, originalMask, originalCount)
  table.remove = originalRemove
  if originalJit then jit.on() end
  equal(ok, false); assert(result:find("expected instruction measurement failure", 1, true))
  equal(#queue, 0); equal(restoredRemove, originalRemove)
  equal(restoredHook, previousHook); equal(restoredMask, ""); equal(restoredCount, 1000000)
  if jit then equal(restoredJit, false, "previous disabled JIT state") end
end)

test("tasks without a generation remain eligible", function()
  local c, bot = newBot()
  local calls = 0
  c.schedule(0, function()
    calls = calls + 1
    c.schedule(0, function() calls = calls + 1 end)
  end)
  c._scheduler[1].generation = nil
  bot.script(); equal(calls, 1)
  bot.script(); equal(calls, 2)
end)

test("reporter failure retains new and old generations", function()
  local c, bot = newBot()
  local seen = {}
  c.schedule(0, function()
    c.schedule(-10, function() seen[#seen + 1] = "new" end)
    error("expected callback failure")
  end)
  c.schedule(1, function() seen[#seen + 1] = "old" end)
  c.error = function() error("expected reporter failure") end
  now = 1001
  equal(pcall(bot.script), false)
  equal(#c._scheduler, 2)
  bot.script()
  equal(table.concat(seen, ","), "new,old"); equal(#c._scheduler, 0)
end)

test("finite reentrant passes do not repeat removed tasks", function()
  local c, bot = newBot()
  local seen = {}
  c.schedule(0, function()
    seen[#seen + 1] = "outer"
    c.schedule(0, function()
      seen[#seen + 1] = "inner"
      c.schedule(0, function() seen[#seen + 1] = "next" end)
    end)
    bot.script()
    seen[#seen + 1] = "outer-end"
  end)
  c.schedule(0, function() seen[#seen + 1] = "old" end)
  bot.script()
  equal(table.concat(seen, ","), "outer,old,inner,outer-end")
  equal(#c._scheduler, 1)
  bot.script()
  equal(table.concat(seen, ","), "outer,old,inner,outer-end,next")
end)

test("callback-first scheduleEvent shares the generation boundary", function()
  local c, bot = newBot()
  local calls = 0
  c.scheduleEvent(function()
    calls = calls + 1
    c.scheduleEvent(function() calls = calls + 1 end, 0)
  end, 0)
  bot.script(); equal(calls, 1)
  bot.script(); equal(calls, 2)
end)

test("duplicate callback functions remain separate tasks", function()
  local c, bot = newBot()
  local calls = 0
  local callback = function() calls = calls + 1 end
  c.schedule(0, callback); c.schedule(0, callback)
  bot.script(); equal(calls, 2); equal(#c._scheduler, 0)
end)

test("separate bot contexts keep their own pending continuations", function()
  local old, oldBot = newBot()
  local oldCalls, newCalls = 0, 0
  old.schedule(0, function() oldCalls = oldCalls + 1 end)
  local current, currentBot = newBot()
  current.schedule(0, function() newCalls = newCalls + 1 end)
  currentBot.script(); equal(oldCalls, 0); equal(newCalls, 1)
  oldBot.script(); equal(oldCalls, 1)
end)

test("script compiler retains its bot environment", function()
  local c = newBot()
  local storage, websockets = c.load("return storage, _websockets", "fixture")()
  equal(storage, c.storage); equal(websockets, c._websockets)
end)

print(string.format("game_bot scheduler: %d tests OK", passed))
