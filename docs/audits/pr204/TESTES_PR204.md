# Testes e evidências — PR #204

Data: 10/10/2026. Código corrigido a partir de `1d40ea3`; relatórios e fontes
estão no mesmo commit de auditoria. Perfil `astra_hd_minimap_smoke`, fixtures em
diretórios temporários, DAT/SPR 8.60 real, **sem login/servidor/janela renderizada**.

## Matriz final local

| Verificação | OpenGL x64 | DirectX x64 |
| --- | --- | --- |
| MSBuild final, incluindo atomic ENC3 | PASS, 0 warnings/0 errors | PASS, 0 warnings/0 errors |
| Native default | PASS | PASS |
| Satellite | PASS | PASS |
| Export + composição independente Pillow | PASS | PASS |
| Audit lifecycle/negativos/ENC3 | PASS | PASS |

Lua options/syntax: PASS. Python pyramid positivos/negativos: PASS.
`git diff --check`: PASS. Linux local, WebAssembly local, ASan/TSan/LSan,
benchmark real e 100 reconexões/hot-reloads: **NÃO EXECUTADO**.

CI consultado do baseline `1d40ea3` (não confundir com novo commit):
[WebAssembly](https://github.com/Mateuzkl/AstraClient/actions/runs/38053686915),
[Content validation](https://github.com/Mateuzkl/AstraClient/actions/runs/38053686726),
[vcpkg](https://github.com/Mateuzkl/AstraClient/actions/runs/38053686761): success.
CI das novas correções precisa ser conferido após o push; não foi presumido verde.

## Comandos

Na raiz do checkout, usando as dependências locais já instaladas:

```powershell
& 'C:/Program Files/Microsoft Visual Studio/18/Community/MSBuild/Current/Bin/MSBuild.exe' `
  vc23/otclient.vcxproj /t:Build /m:2 /nologo /v:minimal `
  /p:Configuration=OpenGL /p:Platform=x64 /p:VcpkgEnableManifest=false `
  '/p:VcpkgInstalledDir=C:/path/to/AstraClient/vcpkg_installed/x64-windows-static/' `
  '/p:OutDir=C:/path/to/AstraClient/build/hd-minimap/bin/' `
  '/p:IntDir=C:/path/to/AstraClient/build/hd-minimap/obj/'
```

O build DirectX usa `Configuration=DirectX` e pastas `build/hd-minimap-dx/{bin,obj}`.
Não usar OutDir/IntDir iguais para compilações simultâneas.
Logs locais: `build/hd-minimap-audit-gl.log`, `build/hd-minimap-audit-dx.log`.

```powershell
./vcpkg_installed/x64-windows-static/x64-windows-static/tools/luajit/luajit.exe tests/minimap_hd/options_test.lua
python tests/minimap_hd/pyramid_test.py
./tests/minimap_hd/Run-Smoke.ps1 -BinaryPath ./build/hd-minimap/bin/otclient_gl_x64.exe
./tests/minimap_hd/Run-Smoke.ps1 -BinaryPath ./build/hd-minimap/bin/otclient_gl_x64.exe -Satellite
./tests/minimap_hd/Run-Smoke.ps1 -BinaryPath ./build/hd-minimap/bin/otclient_gl_x64.exe -Export
./tests/minimap_hd/Run-Smoke.ps1 -BinaryPath ./build/hd-minimap/bin/otclient_gl_x64.exe -Audit
```

Repetir os quatro modos com `./build/hd-minimap-dx/bin/otclient_dx_x64.exe`.
Satellite/Audit dependem do pacote completo local, não incluído no Git;
Export cria OTB/OTBM sintéticos. Python precisa de Pillow. Cada execução usa
recursos de leitura via junctions e fixtures próprias, não modifica origem.

## Cobertura positiva e negativa

- Native: bindings, posição/label do botão HD, checkbox, default, persistência,
  zooms, atualizações, limites tile/item, resets, markers/clicks e full-map round trips.
- Satellite: index lazy, cobertura sem explorar, clássico pessoal/revelado merge,
  futuro abandonado recuperado, LOD lógico 4K <=32, limpeza e reload do disco.
  Reload simula reset; não é login de rede nem benchmark 4K.
- Export: ServerID literal 20026, OTMM revelado em duas floors, pixels top/common
  comparados com composição independente. Não valida todo DAT nem paridade universal.
- Pyramid: placement/gaps/floors, OTMM, manifesto, destino existente, total final
  excedido, OTMM ausente e copy failure sem publicar index.
- Audit: 100 destroyed children com Lua retido, 200 callbacks, 100 ciclos rápidos,
  <=4 slots, recuperação visível, ausência cacheada e recebimento de novo terreno.
- Negativos Audit: índice truncado/inconsistente e signature errada preservam pack
  anterior; oversized PNG, APNG, PNG truncado, ENC3 bomb, arquivo ausente e seed
  conflitante rejeitados. PNG comum, ENC3 normal e custom seed corretos aceitos.
- OTMM corrupto: primeiro bloco Zlib inválido retorna false e preserva célula
  conhecida da fixture. Não prova rollback se houver prefixo válido.

## Logs da rodada final

Pastas sob `%TEMP%`; `stdout.log`, `stderr.log`, script e fixtures ficam retidos.
Excertos publicados em [evidence/windows-2026-10-10.txt](evidence/windows-2026-10-10.txt).

| Backend/modo | Diretório `astra-hd-minimap-...` |
| --- | --- |
| GL Audit | `4d166331a40b4bdba19cfa678bc494a7` |
| GL Native | `bba49cd8e9f84379bbe12137fcd60e07` |
| GL Satellite | `a5a45a2fe05f4173b12fce78df427d1b` |
| GL Export | `3183508c30ef4c418e7d447d33ba0c6f` |
| DX Audit | `f9f34aa994044d02937f8a490809ecc0` |
| DX Native | `87243eba448043e38503687116a1b374` |
| DX Satellite | `bd5e20324d9248548c37d60447244427` |
| DX Export | `3255db9565a84199a58105de26d04e8d` |

SHA-256 dos binários finais testados (não versionados):

```text
OpenGL  66BCAA2183A34800D3D9CEA9139AA666206C63545822E9BE9F75D8B95B99D85D
DirectX E487FED6FB154C3F3B41931D943F2124F5F6BBAB8476D6A99602670781013CBB
```

Uma tentativa intermediária do Audit terminou no erro OTMM **esperado** porque
`--test` encerra no primeiro log ERROR. Foi corrigido o harness: opção explícita
`--test-expected-errors`, mensagens fixture-specific allowlisted, exit zero e
PASS obrigatório. Qualquer outro ERROR falha. A rodada final passou. Uma tentativa
antes do término do link teve arquivo em uso e não executou cliente; não foi
interpretada como falha do renderizador. Nenhuma dessas tentativas é ocultada
como benchmark/validação positiva.
