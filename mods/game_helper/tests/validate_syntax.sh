#!/usr/bin/env bash
# ============================================================================
# validate_syntax.sh
# Valida a sintaxe Lua (via luajit == Lua 5.1, o mesmo runtime do cliente) de
# todos os arquivos do game_helper tocados pela limpeza + o teste de runtime.
#
# COMO RODAR (no WSL):
#   bash mods/game_helper/tests/validate_syntax.sh
# Sai 0 se tudo compila; !=0 se algum arquivo tem erro de sintaxe.
# ============================================================================
set -u
ROOT="/mnt/c/Users/joaoc/KoliseuOT/AstraClient"
FILES=(
  "mods/game_helper/helper.lua"
  "mods/game_helper/hunting_recorder.lua"
  "mods/game_helper/cavebots/actions.lua"
  "mods/game_helper/cavebots/recorder.lua"
  "mods/game_helper/cavebots/core.lua"
  "mods/game_helper/tests/test_helper_cleanup.lua"
)
fail=0
for f in "${FILES[@]}"; do
  if luajit -bl "$ROOT/$f" >/dev/null 2>/tmp/luaerr; then
    echo "OK   $f"
  else
    echo "ERRO $f:"
    sed 's/^/     /' /tmp/luaerr
    fail=1
  fi
done
if [ "$fail" -eq 0 ]; then
  echo "== Sintaxe: TODOS OK =="
else
  echo "== Sintaxe: FALHAS acima =="
fi
exit "$fail"
