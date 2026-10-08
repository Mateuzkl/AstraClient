#!/usr/bin/env bash
set -euo pipefail
# Usa o SDK 6.0.8 ja ativado e um diretorio temporario fora do repositorio.
validation_dir="$(mktemp -d)"
test_node="${ASTRA_TEST_NODE:-node}"
for test in credentials rsa uuid; do
  em++ -std=c++17 -DNDEBUG -I src "browser/tests/${test}.cpp" \
    -sENVIRONMENT=node -sSINGLE_FILE=1 -sASSERTIONS=1 -o "${validation_dir}/${test}.js"
  "$test_node" "${validation_dir}/${test}.js"
done
em++ -std=c++17 -DNDEBUG -I src browser/tests/websocket_callbacks.cpp \
  -lwebsocket.js --pre-js browser/tests/mock-websocket.js \
  -sENVIRONMENT=node -sSINGLE_FILE=1 -sASSERTIONS=1 -o "${validation_dir}/websocket.js"
"$test_node" "${validation_dir}/websocket.js"
em++ -std=c++17 -DNDEBUG -I src browser/tests/fetch_callbacks.cpp \
  --pre-js browser/tests/mock-fetch.js -sFETCH=1 -sFETCH_SUPPORT_INDEXEDDB=0 \
  -sENVIRONMENT=node -sSINGLE_FILE=1 -sASSERTIONS=1 -sSAFE_HEAP=1 -o "${validation_dir}/fetch.js"
"$test_node" "${validation_dir}/fetch.js"
em++ -std=c++17 -DNDEBUG -pthread -I src browser/tests/keyboard_callbacks.cpp \
  --pre-js browser/tests/mock-keyboard.js --pre-js browser/runtime.js \
  -sPROXY_TO_PTHREAD=1 -sPTHREAD_POOL_SIZE=1 -sEXIT_RUNTIME=1 -sENVIRONMENT=node \
  -sASSERTIONS=1 -o "${validation_dir}/keyboard.js"
timeout 15 "$test_node" "${validation_dir}/keyboard.js"
em++ -std=c++17 -DNDEBUG -pthread browser/tests/logic_timer.cpp \
  -sPROXY_TO_PTHREAD=1 -sPTHREAD_POOL_SIZE=1 -sEXIT_RUNTIME=1 \
  -sENVIRONMENT=node -sASSERTIONS=1 -o "${validation_dir}/timer.js"
timeout 15 "$test_node" "${validation_dir}/timer.js"
g++ -std=c++17 -DNDEBUG -I src -O1 -g -pthread -fsanitize=address,undefined \
  -fno-omit-frame-pointer browser/tests/message_budget.cpp -o "${validation_dir}/budget"
"${validation_dir}/budget"
parser_dir="${1:?Informe o diretorio src da Lua 5.1 preparada pelo build WASM}"
mapfile -d '' parser_sources < <(find "$parser_dir" -maxdepth 1 -name '*.c' ! -name lua.c ! -name luac.c ! -name print.c -print0)
gcc -std=gnu99 -DNDEBUG -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer \
  -DLUA_ANSI -I "$parser_dir" -I browser/lua51 browser/tests/lua_parser.c \
  "${parser_sources[@]}" -lm -o "${validation_dir}/parser"
"${validation_dir}/parser"
echo "Browser ownership, RSA, keyboard, parser ASan/UBSan: PASS"
