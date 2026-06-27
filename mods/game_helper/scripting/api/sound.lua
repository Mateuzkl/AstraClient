--[[============================================================================
  scripting/api/sound.lua — Zerobot-compatible `Sound` namespace.
  ============================================================================

  Builder module (see scripting/scripting.lua header + scripting/CONTRACT.md).
  Returns `function(api, ctx) ... return Sound end` and is injected into every
  sandboxed script as the global `Sound`.

  Plain namespace (NOT a class). Plays a sound file through the engine sound
  manager. Zerobot exposes a single function:

      Sound.play(filePath, isDefaultSound = false) -> bool

  where `isDefaultSound` means `filePath` is a bare filename living in Zerobot's
  bundled sounds folder. We honor that signature and additionally accept two
  optional engine-level args BEYOND the ZB spec (the task's `[, ...]`):

      Sound.play(filePath, isDefaultSound, gain, fadeTime)

  Return semantics (ZB): true = the sound was handed to the player; false = it
  was not (audio disabled, file missing/failed to load, or a bad argument).

  Engine mapping (verified — luafunctions.cpp:1027 + soundmanager.cpp:174):
    * g_sounds.play(filename, fadetime = 0, gain = 0) -> SoundSourcePtr | nil
      NOTE there are only THREE params (filename, fadetime, gain); the engine
      has NO `pitch` arg despite older notes. It returns a SoundSource on
      success or nil (audio disabled / file not found).
    * g_sounds.preload(filename) — caches small buffers; we preload once per
      file so repeated short SFX don't re-read from disk.

  *** CRITICAL GOTCHA (memory helper-alarms-sound + soundmanager.cpp:50) ***
  The engine default `gain` is 0.0, i.e. SILENT. If you call g_sounds.play with
  no gain the sound plays muted. We therefore ALWAYS pass an explicit gain,
  defaulting to 1.0 (full volume) — exactly what the helper alarm path does
  (helper.lua:3067 -> g_sounds.play(file, 0, 1.0)).

  Path resolution: the engine's resolveSoundFile() already guesses the .ogg/.wav
  extension and runs resolvePath() (which searches /data, /mods, /modules for
  leading-slash paths). For `isDefaultSound` we prefix the bundled sounds dir
  ("/sounds/", resolved under /data/sounds) so a bare filename Just Works.

  RULES (CONTRACT): no globals; cross-namespace refs are lazy; runs OUTSIDE the
  sandbox (full g_sounds access).
============================================================================]]

return function(api, ctx)
  local Sound = {}

  -- bundled-sounds virtual folder. resolvePath() prepends /data, so this lands
  -- on <client>/data/sounds (the engine's own sound directory). Kept as a local
  -- so a future dedicated bot-sounds folder is a one-line change.
  local DEFAULT_SOUND_DIR = "/sounds/"

  -- remember which files we've preloaded this session (avoid redundant disk
  -- reads for short, repeatedly-played SFX). Keyed by the string passed to play.
  local preloaded = {}

  -- guard so the "audio disabled" notice is logged at most once per script run
  -- (the script keeps working — play just returns false — but the author should
  -- know why nothing is audible).
  local warnedAudioOff = false

  -- Sound.play(filePath, isDefaultSound, gain, fadeTime) -> bool
  --   filePath      : string sound file (relative or absolute virtual path).
  --   isDefaultSound: if truthy, resolve filePath inside the bundled sounds dir.
  --   gain          : optional 0..1 volume (default 1.0 — NEVER pass nil/0 to
  --                   the engine or the sound is muted). Clamped to [0, 1].
  --   fadeTime      : optional fade-in seconds (default 0 = play immediately).
  function Sound.play(filePath, isDefaultSound, gain, fadeTime)
    if type(filePath) ~= "string" or filePath == "" then return false end

    -- audio off => nothing to do; surface the reason once, then no-op.
    if g_sounds.isAudioEnabled and g_sounds.isAudioEnabled() == false then
      if not warnedAudioOff then
        warnedAudioOff = true
        ctx.log("[Sound] audio is disabled in the client; Sound.play is a no-op")
      end
      return false
    end

    local file = filePath
    if isDefaultSound then
      -- treat filePath as a bare filename under the bundled sounds folder.
      file = DEFAULT_SOUND_DIR .. tostring(filePath):gsub("^/+", "")
    end

    -- normalize gain: default full volume, clamp to a sane [0,1]. The explicit
    -- value is the whole point (engine default 0 = silent).
    gain = tonumber(gain)
    if gain == nil then gain = 1.0 end
    if gain < 0 then gain = 0 elseif gain > 1 then gain = 1 end

    fadeTime = tonumber(fadeTime) or 0
    if fadeTime < 0 then fadeTime = 0 end

    -- preload once (best-effort; safe to skip if it fails — play resolves the
    -- file again itself).
    if not preloaded[file] then
      preloaded[file] = true
      pcall(function() g_sounds.preload(file) end)
    end

    -- play with EXPLICIT gain (fadetime, gain) — order per soundmanager.cpp:174.
    local ok, source = pcall(function() return g_sounds.play(file, fadeTime, gain) end)
    -- ZB returns a boolean; g_sounds.play returns a SoundSource (truthy) or nil.
    return (ok and source ~= nil) and true or false
  end

  return Sound
end
