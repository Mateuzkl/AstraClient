-- ============================================================================
-- HELPER TEXT (i18n removed) - the game_helper UI is English-only.
-- htr() is kept as a thin passthrough that applies string.format when called
-- with extra arguments, so existing call sites keep working without changes.
-- ============================================================================

--- Return the (English) text. When extra arguments are passed, applies
--- string.format. Example: htr("Cloned: %s -> %s", a, b)
function htr(key, ...)
  if not key then return "" end
  if select('#', ...) > 0 then
    local ok, formatted = pcall(string.format, key, ...)
    if ok then return formatted end
  end
  return key
end

_G.htr = htr
