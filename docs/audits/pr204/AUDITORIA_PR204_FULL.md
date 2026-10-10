# Auditoria do minimapa HD — PR #204

Data: 10/10/2026. [PR aberto](https://github.com/Mateuzkl/AstraClient/pull/204).
Branch: `feat/optional-sprite-hd-minimap`, mantida por solicitação do proprietário.
Não foi criada branch/PR adicional; não foi alterada nem mesclada a `main`.

Baseline auditado: `1d40ea3f5fc7519a995f0bde68913187507fabc2`.
As correções/testes deste relatório estão no commit que o adiciona à branch.
A comparação de feature usa o merge-base `6f0eeaea9ee15fee4089195b79da5faf0a523079`;
a base remota informada pelo GitHub era `25c2a710bd36e4c03d94921b448517e295088006`.
Usar merge-base evita atribuir mudanças posteriores da main, como CI, ao PR.

## Resultado executivo

Seis problemas comprovados por leitura de código receberam correções pequenas:
contabilidade de decodes após limpeza/eviction, consultas repetidas a terreno
ausente, inscrição de widgets destruídos, limites de leitura/decodificação de
PNG/ENC3, sucesso incorreto em OTMM corrompido e acesso concorrente ao seed de
criptografia. Builds Windows OpenGL/DirectX x64 e testes automatizados passaram.

Isso **não certifica ausência de vazamentos/UAF, paridade visual completa ou
impacto zero em FPS**. Benchmark A/B, sanitizers, partidas longas e testes reais
de reconexão permanecem NÃO VALIDADO. O pacote continua específico de um mundo;
o cliente não identifica automaticamente qual mapa está no servidor.

Índice: [achados](FINDINGS_PR204.md), [testes](TESTES_PR204.md),
[benchmark](BENCHMARK_PR204.md), [HTML](AUDITORIA_PR204_FULL.html),
[evidência de execução](evidence/windows-2026-10-10.txt).

## Método e escopo

Leitura do diff da feature e dos fluxos C++/Lua/offline relacionados; rastreamento
de chamadas, ownership, locks, destruição e shutdown; compilação local dos dois
backends; testes no engine real com perfil isolado e sem login. A validação
dinâmica cobre as invariantes abaixo, não todas as possíveis entradas de rede.
Não foram alterados servidor, protocolo, mapa/OTB original ou pacote PNG instalado.
Não foram instalados sanitizers/profilers nem executados builds locais Linux/Wasm.

O baseline não foi recompilado para uma comparação binária antes/depois desta
auditoria. As causas anteriores são provas estáticas, acompanhadas de regressões
executadas no código corrigido; não são medições de desempenho do baseline.

### H1–H9: classificação

| Hipótese | Classificação e evidência | Estado |
| --- | --- | --- |
| H1: LRU perde jobs | CONFIRMADO, HD-001: a fila possui a closure mesmo sem future no LRU | Corrigido; admissão independente <=4 |
| H2: terreno ausente repetido | CONFIRMADO, HD-002: ausência não tinha entrada; preparação repete `Map::getTile` | Corrigido; 100 preparações seguintes sem novas consultas |
| H3: upload sob lock no construtor | FALSO POSITIVO para upload imediato: `Texture(image)` retém pixels; `Texture::update()` faz upload depois | Picos de upload/latência são HIPÓTESE não medida |
| H4: cópias e passes | HIPÓTESE de impacto: `FrameTile` copia vetores, clássico/PNG/live se sobrepõem | Não otimizado sem profiling |
| H5: pacote de outro mundo | CONFIRMADO como limitação de identidade: DAT/SPR igual não prova mesmo mundo | Exige pacote correto; seleção automática não implementada |
| H6: async/shutdown | Worker não captura Map/Minimap/UI; deinit dá join antes de client/resources | HD-006 corrige seed; TSan e segurança global não certificados |
| H7: inscrição de views | CONFIRMADO, HD-003: destrutor C++ pode atrasar por referências Lua | Corrigido; 100 filhos destruídos sem depender de GC |
| H8: live/export | Elevação top/common JÁ CORRIGIDA em `1d40ea3`; pixels sintéticos passam | Paridade de todos os assets/cenários NÃO VALIDADO |
| H9: integridade de entrada/saída | Limite total/index-last/OTMM/timeout JÁ CORRIGIDOS; HD-004/005 adicionais confirmados | Negativos passam; leitura OTMM não transacional |

### Ownership e threads

| Objeto | Dono e consumidores | Liberação / sincronização |
| --- | --- | --- |
| Snapshots `ItemPtr` | Cache live possui clones; frame possui cópias dos shared_ptr | LRU/reset/última view; `m_spriteLock`; não retém Tile/Creature |
| `SatelliteDecode` | Vetor independente possui future + token; dispatcher possui promise/closure | Resultado pronto coletado; cancelamento mantém slot enquanto pendente |
| PNG `ImagePtr` | Worker cria; future entrega; thread de desenho cria Texture | Resultado cancelado descartado; até quatro slots podem aguardar coleta |
| `TexturePtr` | LRU e comandos de desenho | <=32 entradas no LRU; GPU delete via graphics dispatcher; refs do frame podem prolongar vida |
| `UIMinimap` | UI/Lua shared_ptr, subscription por modo | Hook nativo no destroy recursivo; destrutor é fallback sem duplo decremento |
| Arquivo PHYSFS | Leitura local com unique_ptr/deleter | Fechado em sucesso e exceção; limite antes de buffer |
| Seed ENC3 | ResourceManager global | Atomic compare-exchange preserva primeiro seed; não publica outros objetos |

`removeSpriteView` libera `m_spriteLock` antes de limpar texturas com
`m_satelliteLock`. O worker não adquire locks do minimapa, não cria texturas e
não chama Lua para os caminhos absolutos usados pelas fixtures/pacote padrão.
Coleta usa `wait_for(0)` e `get()` somente quando pronto. Desligar HD cancela
cooperativamente: não interrompe um decoder em andamento nem zera imediatamente
todo future pendente. O limite inclui resultados prontos ainda não coletados.
Não existe fila dedicada: outros sistemas ainda compartilham AsyncDispatcher.

Shutdown examinado: `g_app.deinit()` para/junta worker, depois HTTP, client e
application terminate. Minimap libera futures antes de resources/graphics final;
UI destrói widgets enquanto o objeto global do minimapa ainda existe. Isso reduz
o risco específico de resultado tardio; não equivale a prova por sanitizers.
Mudanças concorrentes de layout/mount ou outras APIs ResourceManager não foram
certificadas. O cancelamento de um job não cancela todo o dispatcher.

### Callbacks e Lua

Checkbox/botão passam pelo único controlador `client_settings.setOption`.
`setSpriteMode` é idempotente e rejeita widgets destruídos. Foram observados
200 callbacks para 100 pares on/off. `init/terminate` conectam/desconectam os
eventos de jogo/LocalPlayer e bind/unbind de Ctrl+Shift+M; a extensão da callback
de câmera mantém a implementação anterior no widget, não no global.
Eventos de restauração/download têm remoção/cancelamento nos caminhos existentes.
100 recargas completas de módulo e 100 reconexões reais NÃO foram executadas.

### Render, compatibilidade e ferramentas

HD continua off por padrão, independente de xBRZ, com fallback clássico e zooms
separados. A imagem não muda protocolo 8.60 nem regras de movimento. Há limites
de 8.192 entradas live (incluindo negativas), 32.768 itens, 64 itens/tile,
4.096 posições/view, 8.192 itens/view, 32 texturas e quatro jobs do minimapa.
São limites de estruturas/trabalho, **não um teto medido de RAM/VRAM total**.

PNG: arquivo/ENC3 limitados a 4 MiB antes de alocar/decomprimir; header 512x512;
chunks truncados/APNG rejeitados antes do loader. Índice valida assinatura,
contagem, coordenadas, nomes e duplicatas; substituição inválida preserva índice
anterior. O gerador recusa overwrite, exige OTMM, conta a pirâmide completa e
publica índice por último. Logs/saídas incompletas ficam para diagnóstico.
`source.json` registra hashes offline, não é um handshake de identidade de mundo.

Foi removido apenas um include duplicado. Não foram eliminadas APIs por ausência
de busca textual, reescritos renderizadores, trocados tipos de ownership ou
introduzidas mudanças no servidor. A API normal de leitura mantém sua assinatura;
o caminho bounded é nativo. O helper de preparação do teste só é bindado em
startup `--test`. Negativos usam `--test-expected-errors` e allowlist no runner;
o `--test` normal permanece fail-fast.

## Inventário revisado

37 arquivos da feature baseline, agrupados por função (não inclui alterações CI
posteriores na main):

- Integração: `.gitignore`, `readme.md`, `docs/hd-minimap.md`, `docs/hd-minimap.pt-BR.md`.
- Settings/UI: `mods/client_settings/classes/dataset.lua`, `mods/client_settings/options/graphics.otui`, `mods/client_settings/settings.lua`, `modules/game_minimap/minimap.lua`, `modules/game_minimap/minimap.otui`, `modules/gamelib/ui/uiminimap.lua`.
- C++: `src/client/itemtype.{cpp,h}`, `luafunctions_client.cpp`, `map.cpp`, `minimap.{cpp,h}`, `thingtype.cpp`, `thingtypemanager.{cpp,h}`, `uiminimap.{cpp,h}`, `src/framework/graphics/drawqueue.{cpp,h}`.
- Testes: `tests/minimap_hd/Run-Smoke.ps1`, `bootstrap.lua`, `export_pixels_test.py`, `export_test.lua`, `inspect_pack.py`, `native_test.lua`, `options_test.lua`, `otmm_fixture.py`, `pyramid_test.py`, `satellite_test.lua`.
- Offline: `tools/minimap_hd/Export-Pack.ps1`, `build_pyramid.py`, `export.lua`, `export_bootstrap.lua`.

Dependências: AsyncDispatcher, ResourceManager/PHYSFS, Image/APNG, Texture/Painter,
UIWidget, Map/Tile/Item/Thing e notificações, event dispatcher, main/application/
client shutdown. Correções adicionais tocam `src/main.cpp`, ResourceManager,
UIWidget e acrescentam `audit_test.lua`/`negative_fixture.py`. A inspeção textual
dessas áreas não substitui validação dinâmica de todos os seus caminhos.

## Checklist pré-merge

| Critério | Estado | Evidência / limite |
| --- | --- | --- |
| Decode admission/reset/LRU | PASS | Vetor independente; 100 ciclos, <=4, recuperação |
| View destroy e callback de opção | PASS | Referências Lua retidas, 100 destroys, 200 callbacks |
| Snapshots/entrada negativa invalidada | PASS | 1008 consultas iniciais, 0 adicionais, novo item visível |
| Clássico, opção, zoom e toolbar | PASS | Suites Lua/native nos dois backends |
| Pack/LOD/OTMM/export pixel sintético | PASS | Satellite/export/Python; índice inválido preservado |
| PNG/ENC3 bounded e seed | PASS | Fixtures positivas/negativas e atomic no acesso compartilhado |
| Builds locais Windows GL/DX x64 | PASS | Zero warnings/errors |
| Seed race em ThreadSanitizer | NÃO VALIDADO | Prova estática e atomic; sem TSan |
| Ausência global de leak/UAF/double-free | NÃO VALIDADO | Sem sanitizers/profiling de longa duração |
| Identidade automática de mundo | NÃO VALIDADO | Só assinaturas DAT/SPR; operador escolhe pacote correto |
| FPS/frametime/RAM/VRAM A/B | NÃO VALIDADO | NÃO MEDIDO; procedimento separado |
| Paridade visual completa, 64px/fluidos/seams | NÃO VALIDADO | Pixel test cobre apenas fixture de elevação |
| Linux/WebAssembly das novas correções | NÃO VALIDADO localmente | CI baseline distinto de commit novo |

Conclusão: alterações específicas prontas para revisão humana. O DoD completo
de performance/sanitizers não foi atingido; **não recomendar merge com alegação
de zero lag, zero vazamento ou paridade universal**. Nenhum merge automático.
