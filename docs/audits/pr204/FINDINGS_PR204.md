# Achados — PR #204

Baseline `1d40ea3f5fc7519a995f0bde68913187507fabc2`; branch
`feat/optional-sprite-hd-minimap`. Links de linhas abaixo apontam a branch de
correção, não o baseline. Antes/depois é análise estática + execução corrigida;
**não houve execução dos novos testes em um binário recompilado do baseline**.

## HD-001 — P1 · CONFIRMADO · Corrigido

**Jobs sobrevivem à expulsão/limpeza do LRU sem continuar na contagem.**
[Código](https://github.com/Mateuzkl/AstraClient/blob/feat/optional-sprite-hd-minimap/src/client/minimap.cpp#L294).
Baseline: o future estava em `SatelliteTexture`; `finishSatelliteDecodes` contava
apenas futures ainda no LRU. `AsyncDispatcher::schedule` possui promise/closure
na fila global; destruir o future não remove a tarefa.

Percurso/reprodução: pedir quatro imagens lentas, desligar/resetar cache ou
expulsar entradas, pedir mais imagens antes de terminar as primeiras. Antes:
admissão esquecia jobs anteriores; esperado: contribuição do minimapa <=4.
Impacto possível: backlog/memória/trabalho tardio; lag real não foi medido.
Fix: vetor independente, tokens de cancelamento, retenção dos slots até coleta
pronta e descarte de resultados cancelados. Teste `-Audit`: 100 ciclos entre
80 posições distintas, <=4 slots e recuperação de imagem visível, GL/DX.
Risco residual: cancelamento não interrompe decode iniciado; até quatro resultados
podem aguardar coleta e outros sistemas usam a mesma fila global.

## HD-002 — P2 · CONFIRMADO · Corrigido

**Viewport vazio repete consultas a Map por não armazenar ausência.**
[Código](https://github.com/Mateuzkl/AstraClient/blob/feat/optional-sprite-hd-minimap/src/client/minimap.cpp#L614).
Antes, null/empty/>64 itens removiam ou não criavam snapshot. Cada preparação
via `drawSprites` reconstruía a lista missing e consultava essas posições.
Impacto: trabalho repetido comprovado, custo em milissegundos não medido.

Fix: sentinela vazia no mesmo LRU, substituída por notificações de itens. Null não
apaga snapshot explorado existente; tile realmente esvaziado vira entrada vazia.
Preparação extraída sem mudar limites do renderer e exposta ao Lua apenas em
`--test`. Reprodução/teste: view 256x192, escala 8, posição vazia (30000,30000,7);
1008 consultas de warm-up, zero novas consultas nas próximas 100 preparações;
receber ground cria imediatamente snapshot real. Sem medição FPS, sem promessa
de eliminar o scan da grade ou cópias de frames. Eviction pode exigir novo lookup.

## HD-003 — P2 · CONFIRMADO · Corrigido

**Widget destruído mantém subscription até C++ ser coletado.**
[Código](https://github.com/Mateuzkl/AstraClient/blob/feat/optional-sprite-hd-minimap/src/client/uiminimap.cpp#L47).
`UIWidget::internalDestroy` marca destruído; Lua pode reter o shared_ptr.
Antes, `UIMinimap::~UIMinimap` era o único caminho automático de unsubscribe.
Impacto: inscrição/cache ativos apesar de view morta; não prova leak permanente.

Fix: hook nativo em destroy recursivo, modo off e unsubscribe imediato; destrutor
fallback sem dupla remoção; impedir reativação de widget morto. Teste: 100 parents
destruídos mantendo child references sem GC; contador volta a zero sempre.
100 pares de opção resultam em 200 callbacks. Risco: novo hook default no-op no
framework; suites nos dois renderizadores cobrem destruição normal e recursiva.
100 logins reais e hot-reload completo ainda não executados.

## HD-004 — P2 · CONFIRMADO · Corrigido

**Limite de PNG aplicado após read e APNG rejeitado após alocar frames.**
[Minimap](https://github.com/Mateuzkl/AstraClient/blob/feat/optional-sprite-hd-minimap/src/client/minimap.cpp#L357),
[ResourceManager](https://github.com/Mateuzkl/AstraClient/blob/feat/optional-sprite-hd-minimap/src/framework/core/resourcemanager.cpp#L504).
Antes, `readFileContents` admitia até 512 MiB antes do limite minimap 4 MiB;
`Image::loadPNG` usa APNG loader, alocando frames antes de `isAnimated` rejeitar.
Impacto: alocações/CPU desnecessários para pacote adulterado/corrompido.

Fix: reader nativo bounded antes da alocação/IO/cópia, limite de tamanho declarado
ENC3 antes de descompressão, RAII do PHYSFS, varredura de chunks estáticos antes
do decoder. Teste: plain/encrypted PNG válidos aceitos; arquivo >4 MiB, APNG,
truncado, ENC3 de 25 bytes declarando 100 MiB e PNG ausente rejeitados, GL/DX.
Risco: restrição intencional a PNG estático completo; não reescreve libpng/APNG.
Não foram medidos picos RAM nem todas as possibilidades de PNG malformado.

## HD-005 — P2 · CONFIRMADO · Corrigido (preexistente)

**OTMM com bloco Zlib inválido retorna sucesso.**
[Código](https://github.com/Mateuzkl/AstraClient/blob/feat/optional-sprite-hd-minimap/src/client/minimap.cpp#L1037).
Antes, falha de `uncompress` ou tamanho incorreto saía do loop com `break`, mas
o reader retornava `true`. A nova merge API reutilizava esse reader preexistente.
Fix: exceção recuperável pelo catch, log e `false`. Fixture de primeiro bloco
inválido agora falha e não muda a célula conhecida de teste. Risco residual:
**OTMM não é transacional**; prefixo válido pode ser aplicado antes de erro
posterior. Não foi alterado o formato nem prometido rollback.

## HD-006 — P2 · CONFIRMADO estático · Corrigido

**Seed de criptografia compartilhado sem sincronização.**
[Código](https://github.com/Mateuzkl/AstraClient/blob/feat/optional-sprite-hd-minimap/src/framework/core/resourcemanager.cpp#L1657).
`decryptBuffer` pode descobrir/gravar `m_customEncryption`; leituras nativas na
thread principal e PNG/ENC3 no worker acessavam uint32_t não-atômico. A condição
de race é descoberta concorrente de custom seed, não todo PNG normal.
Impacto: data race C++ condicional; não foi reproduzido crash nem executado TSan.

Fix mínimo: atomic load + compare-exchange para preservar primeiro seed.
Sem mutex sobre IO, sem alterar ENC3/assinatura Lua. Fixtures no processo isolado
aceitam ENC3 normal/custom-seed e rejeitam seed conflitante. Essas fixtures testam
semântica funcional, **não são um teste de race por TSan**. Outros estados globais
do ResourceManager e mudanças concorrentes de mounts/layout não estão certificados.

## Hipóteses e falsos positivos restantes

| ID | Severidade candidata | Classificação | Estado e prova |
| --- | --- | --- | --- |
| H3-upload-imediato | P2 | FALSO POSITIVO parcial | `Texture::Texture(ImagePtr)` só guarda pixels; GL upload em `Texture::update`, não naquele construtor sob lock |
| H3-latência/H4-cópias | P2 | HIPÓTESE | Texture creation/first upload e cópias por frame existem; medir antes de reescrever |
| H5-mundo | P2 | CONFIRMADO como limitação | Assinatura de assets não identifica servidor/mapa; documentação exige pacote correto; sem seleção automática |
| H6-UAF-worker | P1 candidato | NÃO CONFIRMADO | Closure só path/token; join precede client/resources teardown; sem sanitizers |
| H8-paridade | P2 | HIPÓTESE residual | Elevação top/common JÁ CORRIGIDA em baseline, pixel regression passa; demais cenários pendentes |
| H9-publicação | P2 | JÁ CORRIGIDO | OTMM exigido, count total, índice final e timeout em `1d40ea3`; pyramid/export passam |
| OTMM-vazio | P2 | FALSO POSITIVO no fluxo testado | OTBM dispara atualização de minimapa; fixture cobre duas floors e reload OTMM |

Não há P0 identificado nem P1 confirmado deixado sem fix neste escopo. Isso não
equivale a garantir segurança/fluidez globais. Ver [checklist](AUDITORIA_PR204_FULL.md#checklist-pré-merge)
e [procedimento de benchmark](BENCHMARK_PR204.md) antes de conclusão pré-merge.
