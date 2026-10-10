# Benchmark — PR #204

## O que foi e não foi medido

**FPS, frametime, CPU, RAM e VRAM A/B: NÃO MEDIDO.** As suites nativas foram
ocultas, sem login e sem renderização visual; não usar seu tempo total como FPS,
1% low ou custo de frame. Nenhuma alegação de "não pesa nada" foi demonstrada.

| Métrica | A: clássico | B: live HD | C: pack HD | Full map |
| --- | --- | --- | --- | --- |
| FPS médio / 1% / 0,1% low | NÃO MEDIDO | NÃO MEDIDO | NÃO MEDIDO | NÃO MEDIDO |
| Frametime p50/p95/p99 | NÃO MEDIDO | NÃO MEDIDO | NÃO MEDIDO | NÃO MEDIDO |
| CPU total / por thread | NÃO MEDIDO | NÃO MEDIDO | NÃO MEDIDO | NÃO MEDIDO |
| RAM / alocações por frame | NÃO MEDIDO | NÃO MEDIDO | NÃO MEDIDO | NÃO MEDIDO |
| VRAM / tempo de upload | NÃO MEDIDO | NÃO MEDIDO | NÃO MEDIDO | NÃO MEDIDO |
| Lock wait / fila global async | NÃO MEDIDO | NÃO MEDIDO | NÃO MEDIDO | NÃO MEDIDO |
| Reconexões reais / combate | NÃO EXECUTADO | NÃO EXECUTADO | NÃO EXECUTADO | NÃO EXECUTADO |

Invariantes observadas em **cada** backend (não são um benchmark A/B):

| Cenário isolado | Resultado |
| --- | --- |
| View vazia 256x192, escala 8 | 1008 consultas `Map::getTile` no primeiro warm-up |
| Próximas 100 preparações da mesma view | 0 consultas adicionais |
| Novo ground recebido em posição com sentinela | Snapshot real imediato, item count = 1 |
| 100 ciclos pan/reset/off, 80 posições distintas | Slots de decode sempre <=4; imagem visível volta a carregar |
| 100 destroys com child Lua retido | View count retorna a zero a cada ciclo |
| 100 pares on/off | Exatamente 200 callbacks do controlador |
| 4K LOD lógico / texture cache | Seleção cabe em <=32 entradas; não foi benchmark renderizado 4K |

Os contadores não medem duração: `getSatelliteDecodeCount()` inclui slots prontos
não coletados; `getSpriteCacheTileCount()` inclui entradas negativas. A fila
global pode conter tarefas de outros sistemas além dessas quatro do minimapa.

## Ambiente observado

- Windows 11 Pro, versão 10.0.26300; PowerShell; Visual Studio 18 Community/MSBuild.
- Intel Core i5-10300H, 4 núcleos / 8 threads, RAM visível ~15,87 GiB.
- Intel UHD, driver 27.20.100.9664; NVIDIA GTX 1650, driver 32.0.16.1742.
- OpenGL dos testes: Intel UHD, OpenGL 4.6; DirectX: ANGLE 2.1.5414,
  D3D11 Intel, OpenGL ES 3.0. Não presumir que os testes usaram NVIDIA.
- Assets 8.60, pacote local com 4.702 PNGs, 11 LODs, floors 0–13.
- Baseline source SHA `1d40ea3f5fc7519a995f0bde68913187507fabc2` + fixes deste commit.

## Procedimento reproduzível pendente

1. Usar builds baseline/corrigido separados, mesmos assets/mapa/perfil de teste,
   GPU/backend, resolução, escala do sistema, VSync, FPS cap e câmera. Não sobrescrever
   perfil do jogador. Encerrar compilações e outras cargas antes da captura.
2. Para cada backend, executar A clássico; B HD live sem pacote; C HD com pacote
   frio e aquecido; D Ctrl+Shift+M. Separar custo de cold IO/decode do steady state.
3. Repetir em 1080p, 1440p e 4K, janela real renderizando. Usar rota determinística:
   60 s parado, 3 min andando, 1 min pan rápido, 1 min zoom/floors/transições,
   10–30 min longa duração. Repetir ao menos três vezes cada combinação.
4. Medir tempos de presents com ferramenta apropriada ao backend (por exemplo
   PresentMon, quando instalada/compatível); CPU e espera/alloc com ETW/WPA ou
   profiler Visual Studio; RAM/VRAM com contadores/processo corretos. Registrar
   comandos, versões, CSV/traces brutos, timestamps e configuração de captura.
5. Calcular FPS médio, 1%/0,1% low e frametime p50/p95/p99 a partir de frames
   realmente capturados, explicando descarte de warm-up. Não misturar fontes com
   unidades/amostragem diferentes. Registrar trajetórias e eventos dos picos.
6. Capturar getters de cache/jobs/views antes e depois de pan/toggle/reset e
   observar tendência de RAM/VRAM após repouso, sem tratar retenção temporária de
   frames/futures como leak confirmado. Profiling e sanitizers têm execuções próprias.
7. Atribuir otimizações somente após identificar hotspot: cópias de `FrameTile`,
   overlap dos passes, upload inicial, lock/contention ou fila compartilhada.
   Manter pixel, clássico e shutdown regressions após mudanças.

Nenhum profiler acima foi instalado/executado por esta auditoria; são instruções
para uma rodada futura. Sem dados, não há gráfico de desempenho nem conclusão
quantitativa de melhoria. Ver [evidências dos testes](TESTES_PR204.md).
