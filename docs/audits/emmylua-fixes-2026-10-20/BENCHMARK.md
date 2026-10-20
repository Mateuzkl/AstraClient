# Microbenchmark do dispatcher Lua

Ambiente: WSL Ubuntu em Windows, LuaJIT 2.1.1703358377. Os processos JIT e sem JIT foram executados sequencialmente na medição registrada abaixo. Resultados dependem de CPU, carga do host e traces do JIT.

O script usa 40 handlers registrados, as mesmas funções de callback, 20.000 chamadas de aquecimento e cinco amostras de 300.000 chamadas. Registra a mediana de tempo de CPU com `os.clock`. Compara a reprodução literal do algoritmo anterior com `pairs` ao método novo carregado de `modules/gamelib/protocolgame.lua`. Também verifica argumentos, substituição/desregistro e o retorno de opcode tratado independentemente do retorno do callback.

| Opcode | JIT antigo (ms) | JIT novo (ms) | Sem JIT antigo (ms) | Sem JIT novo (ms) |
|---|---:|---:|---:|---:|
| 1 | 8,750 | 4,372 | 11,936 | 11,311 |
| 20 | 27,824 | 4,673 | 47,805 | 8,216 |
| 40 | 50,479 | 4,608 | 75,259 | 8,415 |
| 255 (não registrado) | 66,874 | 4,834 | 79,224 | 7,022 |

Comandos:

```sh
luajit .github/tests/protocol_dispatch.lua --bench
luajit -joff .github/tests/protocol_dispatch.lua --bench
```

Checksum em ambas as execuções: 9.120.000. O teste com `-joff` é do interpretador LuaJIT, não uma execução do cliente Web. Não houve medição de FPS, latência de ação, tráfego ou CPU total do jogo. Os intervalos de Bot e Battle permanecem iguais.

A montagem JSON agora armazena fragmentos e usa `table.concat` uma vez ao terminar. Essa alteração remove a cópia cumulativa de prefixos por chunk; seus limites, expiração e limpeza foram verificados por testes, sem anunciar uma porcentagem de ganho de CPU/RAM do cliente real.
