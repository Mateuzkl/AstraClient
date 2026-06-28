--[[
  scripting/api/timer.lua  ->  class `Timer`  (Zerobot dialect)
  ----------------------------------------------------------------------------
  Timer(name, fn, delayMs, autoStart) -> Timer        (Timer.new == Timer(...))

  Zerobot's per-tick loop primitive. A Timer fires `fn` every `delayMs` while
  active. In Zerobot a single native dispatcher (`processTimer`) round-robins a
  global `Timers.list`; KoliseuClient instead has a real recurring scheduler
  (`cycleEvent`), so each Timer owns ONE cycleEvent rather than sharing a global
  ticker. The observable contract is the same: create -> it runs every delay;
  :stop() pauses it; :start() resumes; recreating a same-named timer replaces it.

  Methods (Zerobot surface + the task spec):
    Timer:run()              invoke the callback once, now (manual fire).
    Timer:name()             the timer's name.
    Timer:start()            (re)activate; first tick after one full delay.
    Timer:stop()             deactivate (cancels the underlying cycleEvent).
    Timer:isActive()         active state (bool).
    Timer:setInterval(ms)    change the delay; if running, re-arm with the new ms.
    Timer:getInterval()      current delay (ms).
    Timer:update(delayMs)    Zerobot internal: reschedule next tick to now+delay.
    Timer:destroy()          stop + drop (alias of stop, kept for symmetry).

  ctx integration (CRITICAL):
    * The callback is wrapped with ctx.wrap(fn) AT CREATION time. This captures the
      owning script and routes every later tick through pcall + error-accounting
      (auto-disable after 5 errors) and makes the tick a no-op once the script is
      disabled. Storing a raw closure would bypass all of that.
    * ctx.onCleanup(stop) is registered so the timer is cancelled when the script
      unloads / errors out / relogs. The handle lives for the timer's whole life
      (stop() is idempotent), so stop()+start() never loses teardown or leaks the
      underlying cycleEvent. :destroy() releases it.
]]

return function(api, ctx)
  -- DEFAULTS (Zerobot): delay 100ms, autoStart true.
  local DEFAULT_DELAY = 100

  local Timer = {}
  Timer.__index = Timer

  -- Registry of timers by owning script so creating a same-named timer replaces the
  -- previous one (Zerobot semantics). Weak keys: when a script record is collected,
  -- its whole bucket goes with it.
  local byOwner = setmetatable({}, { __mode = "k" })

  -- Internal: cancel the live cycleEvent (if any) without touching `active`.
  local function killEvent(self)
    if self._ev then
      pcall(removeEvent, self._ev)
      self._ev = nil
    end
  end

  -- Internal: (re)arm the recurring event. The wrapped callback is invoked every
  -- `delay` ms WITH THE TIMER INSTANCE AS ITS FIRST ARGUMENT -- this matches
  -- Zerobot, whose Timer:run() does `self:_function()` (i.e. fn(self)), so a script
  -- written as `Timer('t', function(t) t:stop() end, 500)` works unchanged.
  -- cycleEvent fires the FIRST tick after one interval (matches Zerobot's
  -- "next trigger = now + delay" semantics). The per-tick guard skips firing while
  -- the timer is paused or the script went offline; ctx.wrap already handles
  -- "script disabled" + error accounting.
  local function arm(self)
    killEvent(self)
    local fn = self._wrapped
    local delay = self._delay
    self._ev = cycleEvent(function()
      if not self._active then return end
      fn(self)
    end, delay)
  end

  -- Constructor. `fn` may be a function or (Zerobot allows) a string naming a
  -- global function; since scripts run sandboxed we only accept an actual function
  -- here (string lookup into a global table has no meaning in the closed env).
  function Timer.new(name, fn, delayMs, autoStart)
    if type(fn) ~= 'function' then
      error('Timer(name, fn, delayMs, autoStart): fn must be a function', 2)
    end
    delayMs = tonumber(delayMs) or DEFAULT_DELAY
    if delayMs < 1 then delayMs = 1 end
    if autoStart == nil then autoStart = true end  -- Zerobot default

    local self = setmetatable({}, Timer)
    self._name    = tostring(name or 'timer')
    self._raw     = fn
    self._delay   = delayMs
    self._active  = false
    self._ev      = nil
    self._owner   = (ctx.runningScript and ctx.runningScript()) or nil
    -- Capture the owning script NOW so deferred ticks run in its context with
    -- pcall + auto-disable. Must be done at creation (we are inside the load body).
    self._wrapped = ctx.wrap(fn)

    -- Replace a same-named timer owned by the same script (Zerobot semantics):
    -- Timer("tick",...) created twice must not leave two cycleEvents firing together.
    if self._owner then
      local bucket = byOwner[self._owner]
      if not bucket then bucket = {}; byOwner[self._owner] = bucket end
      local prev = bucket[self._name]
      if prev and prev ~= self then prev:destroy() end
      bucket[self._name] = self
    end

    -- Tear the timer down when the script unloads/errors/relogs. The cleanup stays
    -- registered for the timer's whole life and just calls :stop() (idempotent), so
    -- a stop()+start() cycle never loses its teardown (no leaked cycleEvent).
    self._cleanup = ctx.onCleanup(function() self:stop() end)

    if autoStart then self:start() end
    return self
  end

  -- Invoke the callback once, immediately, in the owning script's context, passing
  -- the timer instance as the first arg (Zerobot's `self:_function()` parity).
  -- Returns whatever the callback returns (after ctx's ok flag is stripped by wrap).
  function Timer:run()
    return self._wrapped(self)
  end

  function Timer:name()
    return self._name
  end

  -- (Re)activate and (re)arm the recurring event; next tick is one full delay away.
  function Timer:start()
    self._active = true
    arm(self)
    return self
  end

  -- Deactivate and cancel the underlying event. Idempotent. Does NOT drop the
  -- onCleanup handle: it stays registered for the timer's life, and re-calling stop
  -- on an already-stopped timer is a harmless no-op, so start() after stop() keeps
  -- working without re-registering (and never leaks the cycleEvent on unload).
  function Timer:stop()
    self._active = false
    killEvent(self)
    return self
  end

  function Timer:isActive()
    return self._active == true
  end

  -- Change the interval. If the timer is currently running, re-arm immediately so
  -- the new cadence takes effect from the next tick.
  function Timer:setInterval(delayMs)
    delayMs = tonumber(delayMs) or self._delay
    if delayMs < 1 then delayMs = 1 end
    self._delay = delayMs
    if self._active then arm(self) end
    return self
  end

  function Timer:getInterval()
    return self._delay
  end

  -- Zerobot internal "reschedule next trigger to now + delay". With cycleEvent the
  -- cleanest equivalent is to re-arm with the (optionally new) delay.
  function Timer:update(delayMs)
    if delayMs ~= nil then
      delayMs = tonumber(delayMs)
      if delayMs and delayMs >= 1 then self._delay = delayMs end
    end
    if self._active then arm(self) end
    return self
  end

  -- Terminal teardown: stop, drop from the name registry, and release the cleanup
  -- handle (a destroyed timer won't be restarted).
  function Timer:destroy()
    self:stop()
    if self._owner then
      local bucket = byOwner[self._owner]
      if bucket and bucket[self._name] == self then bucket[self._name] = nil end
    end
    if self._cleanup then
      pcall(function() self._cleanup.cancel() end)
      self._cleanup = nil
    end
  end

  -- Make the namespace callable: Timer(...) == Timer.new(...).
  return setmetatable(Timer, { __call = function(_, ...) return Timer.new(...) end })
end
