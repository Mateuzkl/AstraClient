--[[============================================================================
  test_sound_modal.lua — Sound.play + CustomModalWindow (Zerobot dialect).
  ============================================================================
  *** PERCEPTIBLE EFFECTS WARNING ***
  Unlike the other example scripts, the two features here are USER-VISIBLE/AUDIBLE
  when enabled: Sound.play makes a NOISE and CustomModalWindow pops a dialog that
  LOCKS input until dismissed. They are inocuous but noticeable, so BOTH are gated
  behind RUN_MUTATIONS (default false). With the gate off this script only does
  the safe checks (function existence, modal construction WITHOUT showing) and
  prints "would call X".

  When RUN_MUTATIONS=true:
    * Sound.play plays a short bundled sound (best-effort; false if audio is off).
    * A CustomModalWindow is shown AND auto-closed after a brief delay, and is
      also dismissable by its button — it never gets stuck on screen.

  Exercises:
    * Sound.play(filePath, isDefaultSound[, gain, fadeTime]) -> bool
        (scripting/api/sound.lua)
    * CustomModalWindow(caption, desc) + :addButton + :setCallback + :show/:destroy
        (scripting/api/custommodalwindow.lua)
============================================================================]]

local RUN_MUTATIONS = false   -- keep false: makes sound + shows an input-locking modal.

local pass, fail = 0, 0
local function check(name, cond, extra)
  if cond then
    pass = pass + 1
    print('[PASS] ' .. name .. (extra and (' = ' .. tostring(extra)) or ''))
  else
    fail = fail + 1
    print('[FAIL] ' .. name)
  end
end

print('=== Sound: existence + gated play ===')
check('Sound.play exists', type(Sound.play) == 'function')
-- Guard: a bad/empty path returns false WITHOUT the gate (no actual playback).
check('Sound.play("") returns false (bad arg)', Sound.play('') == false)
check('Sound.play(nil) returns false (bad arg)', Sound.play(nil) == false)

if RUN_MUTATIONS then
  -- Play a bundled default sound at a modest gain. Returns true if handed to the
  -- player, false if audio is disabled / file missing (both are acceptable).
  local played = Sound.play('alarm.ogg', true, 0.5)
  print('[MUTATE] Sound.play("alarm.ogg", true, 0.5) -> ' .. tostring(played))
  check('Sound.play returns boolean', type(played) == 'boolean', played)
else
  print('[SKIP] would call Sound.play("alarm.ogg", true, 0.5) (RUN_MUTATIONS=false)')
end

print('=== CustomModalWindow: construction (no show) ===')
-- Building a modal does NOT display it — safe even with the gate off.
local modal = CustomModalWindow('Scripting Test', 'This is a self-closing test dialog.')
check('CustomModalWindow(...) builds an instance', type(modal) == 'table')
check('modal:getId() is a number', type(modal:getId()) == 'number', modal:getId())

-- addButton returns a 0-based id; first button is 0.
local okBtn = modal:addButton('OK')
check('modal:addButton("OK") returns id 0', okBtn == 0, okBtn)
local okBtn2 = modal:addButton('Cancel')
check('modal:addButton("Cancel") returns id 1', okBtn2 == 1, okBtn2)

-- setCallback accepts a function and is chainable (returns the modal). The
-- callback only fires on a real button click (won't happen while gated); it just
-- reports which button was pressed.
local chained = modal:setCallback(function(buttonId)
  print('[modal] button clicked: ' .. tostring(buttonId))
end)
check('modal:setCallback returns the modal (chainable)', chained == modal)

print('=== CustomModalWindow: gated show + auto-close ===')
if RUN_MUTATIONS then
  modal:show()
  print('[MUTATE] modal:show() — auto-closing shortly')
  -- Auto-dismiss so the dialog can never stay stuck (defensive, in addition to
  -- the button/escape paths). The sandbox exposes the Timer class (its per-tick
  -- loop primitive); we keep the instance so the callback can stop it (there is
  -- no module-level destroyTimer in this port — use Timer:stop()).
  local autoclose
  autoclose = Timer('test_modal_autoclose', function()
    if autoclose then autoclose:stop() end   -- one-shot: cancel before acting
    if modal and not modal._destroyed then
      modal:destroy()
      print('[MUTATE] modal auto-closed by Timer')
    end
  end, 1500, true)
else
  print('[SKIP] would call modal:show() + auto-close (RUN_MUTATIONS=false)')
  -- With the gate off we never showed it; destroy the (unshown) instance so we
  -- leave no tracked modal behind.
  modal:destroy()
  check('modal:destroy() on unshown instance is safe', true)
end

print(('--- Sound/Modal: %d passed, %d failed ---'):format(pass, fail))
