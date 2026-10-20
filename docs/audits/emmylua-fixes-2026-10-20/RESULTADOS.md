# Correções da auditoria EmmyLua — 20/10/2026

Base: `bee47373ebb03003750857b711111509c2f79389` (main).
Branch: `fix/emmylua-audit-20261020`. Cada correção foi registrada em commit separado; sem alteração no TFS ou no mod local MapTracker.

| Achado | Correção entregue | Commit |
|---|---|---|
| ASTRA-001 | ItemDetails Lua e fallback C++ terminam nos campos contados, preservando outros opcodes do frame; reader nativo também fixa a ordem das duas strings | `a379d92` |
| ASTRA-002 | HTTP do TopMenu com cancelamento, geração e um retry por rodada; timers de startup/ping/FPS encerrados; resposta de status agregada sem sobrescrever texto fornecido pelo serviço | `43aa2b4` |
| ASTRA-010 | Prey/Hunting cancelam reroll no unload; Hunting também libera a janela; referências de UI são limpas | `ed4409f` |
| ASTRA-003 | JSON em chunks com uma concatenação final; limpeza em unregister, logout, reload e expiração; validação de sequência e conexão dona | `c58150c` |
| ASTRA-005 | FollowFriend registra no init e retira no terminate, com verificação do callback proprietário; não toma o opcode de outro módulo | `9c94808` |
| ASTRA-006 | Eventos associados ao widget cancelados no destroy; substituição por chave; guardas de validade; migração dos pontos de Containers, Inventory, HealthInfo, TextWindow e Market | `67fdc8d` |
| ASTRA-007, parte mensurável | Dispatcher acessa diretamente a tabela de handlers, mantendo argumentos e retorno; sem mudar frequência de gameplay | `08e8330` |
| ASTRA-009 | Remoção só de cinco funções privadas sem consumidor e quatro tabelas privadas usadas apenas por código morto | `43af928` |
| Complemento ASTRA-003 | Limite de fragmentos impede que chunks vazios burlem o teto de memória do payload | `452c1ba` |

## Limites de extended JSON

Recepção aceita até 8 MiB de payload por montagem, 16 MiB de payload agregado pendente e 1.024 fragmentos por montagem. O prazo é de 30 segundos a partir do início. Esses números limitam montagem e retenção, não o RSS inteiro do cliente. O formato e o tamanho de chunk de envio (65.000 bytes) permanecem iguais. Mensagens fora dos limites/sequência são descartadas com aviso; o próximo opcode continua processável. Os limites cobrem até 130 chunks máximos para uma mensagem de 8 MiB, com margem no número de fragmentos.

Um novo início substitui uma montagem incompleta do mesmo opcode. P/E sem início ou de outra conexão são rejeitados. O cancelamento de um callback dono não remove um callback substituto de outro módulo.

## Validação executada

- Sintaxe de 460 fontes Lua rastreados: passou sob LuaJIT 2.1.1703358377.
- 23 suítes Lua: passaram, incluindo os 16 testes preexistentes e sete novas suítes de regressão.
- Reader nativo de ItemDetails: testes com GCC e Clang, C++17, `-Wall -Wextra -Werror -pedantic -fsanitize=address,undefined`: passaram. Incluem payload contado, movimento concatenado e truncamentos em cada offset.
- `git diff --check`: passou.
- EmmyLua 0.25.1 reexecutado com a biblioteca parcial da auditoria: 460 arquivos, 29.804 diagnósticos, saída 1 pela presença de diagnósticos. Esse resultado é anterior à correção de compatibilidade descrita abaixo. Permanecem avisos de bindings/OTUI; não é um resultado verde do linter. As novas referências a ProtocolGame foram conferidas como API nativa, não tratadas como globals inexistentes.

Comando para repetir os testes Lua:

```sh
luajit .github/tests/run_audit_regressions.lua
```

O workflow content-validation executa as novas suítes e o teste nativo com sanitizers. Não foi compilado o executável completo, executado login real, testada a UI num navegador ou medida memória/FPS do jogo em produção. As verificações de lifecycle usam código real com doubles de UI/rede. Não há alegação de ausência de todo UAF/leak nativo.

O JSON final do EmmyLua foi preservado localmente na pasta da auditoria original, sem acrescentar dezenas de MB de diagnósticos ao Git. SHA-256: `9FFA4C94EF915B6E665D97EB96A5F21CC4DD06B60CB765946051C736A681085C`.

## Otimização medida

Detalhes em [BENCHMARK.md](BENCHMARK.md). A mudança remove o scan de handlers por mensagem. No microbenchmark com JIT, a mediana para 300.000 despachos ficou entre 4,372 e 4,834 ms no método novo, contra 8,750–66,874 ms no algoritmo anterior, conforme o opcode. Essa diferença não é uma medição de FPS, CPU total ou latência de rede do cliente.

## Itens que permaneceram condicionais

ASTRA-004: BattlePass/Prey/Bosstiary inferem alguns campos opcionais pelos bytes restantes. A variante válida do servidor implantado ainda precisa ser confirmada. Não foi escolhido um formato novo nem suprimidos campos sem essa evidência. Os descartes de frame em erro de Market/Store também requerem uma decisão de protocolo/resincronização.

ASTRA-007: os intervalos do Bot/Battle e a coleta completa após logout não foram alterados sem profiling do cliente. O ganho entregue é o lookup de opcode e a eliminação de concatenações cumulativas/retencões na montagem JSON.

ASTRA-008: a biblioteca de análise continua parcial. Não foram mascarados warnings com `any`, globals genéricos ou supressões. Ela exige uma etapa própria de modelagem das interfaces e dos perfis de Bot; não é um defeito funcional para corrigir com alterações arbitrárias no runtime.

Não foram removidos módulos opcionais nem consolidadas as duas versões de StatusIconBar, pois não há prova de equivalência de todos os consumidores. A correção focal de ItemDetails coincide com trabalho já em revisão no PR #221; esta branch não inclui os diagnósticos de movimento daquele PR ou mudanças dos PRs #221/#222 fora do framing.

## Revisão posterior do PR #223

O log do GitHub Actions `39502731651` confirmou `unexpected symbol near 'goto'` no teste de sintaxe. O binário LuaJIT local aceitava a chave nua, mas essa observação não era uma prova de compatibilidade com o build usado pelo CI. A classificação anterior como falso positivo foi limitada demais. A chave agora usa `["goto"]`, preservando seu valor e permitindo o parsing nos dois ambientes.

O teardown de Hunting libera explicitamente o bloqueio de entrada antes de destruir sua janela ou mensagem, apenas quando uma delas é a dona atual. O fallback de corelib já limpa o lock em onDestroy; a liberação explícita também cancela a passagem de foco pendente de g_client. O teste verifica a ordem antes de destroy e que o lock de uma janela externa não é removido.

Toda movimentação de container cancela o `containerLock` anterior, incluindo uma nova movimentação com `locked=false`. O teste executa o callback antigo após essa troca, valida substituições locked→locked e preserva o cancelamento por destruição.

O teste de TextWindow carrega o módulo inteiro e chama `onGameEditText`/`onGameEditList`. O fechamento usa os callbacks reais do botão Cancel e Escape, chegando ao helper privado que agenda o foco. São verificados foco normal, substituição, logout, destruição do painel e painel ausente; não é mais um evento de foco criado artificialmente pelo teste.

### Identidade dos proxies de widget

Confirmado no binding: `LuaInterface::pushObject` cria um novo userdata por exposição, enquanto `LuaObject::luaGetField`/`luaSetField` acessam a tabela de campos do objeto C++. A tabela fraca de eventos por userdata não encontrava o grupo quando cancelamento ou `onDestroy` recebia outro proxy. O grupo agora fica no campo privado `_coreWidgetEventGroup`, compartilhado pelos proxies; cancelamento, substituição por chave e destruição usam esse mesmo estado. A destruição cancela os eventos e limpa o campo antes de `UIWidget::internalDestroy` liberar os campos Lua.

O teste de regressão usa dois userdata distintos (`newproxy`) com igualdade nativa simulada e campos compartilhados. Ele falhou antes da correção no cancelamento por outro proxy. Depois da correção, verifica cancelamento individual/em lote, substituição por chave, um único hook mesmo após recarregar o helper e destruição recebida pelo segundo proxy. Callbacks antigos também são invocados manualmente para confirmar que não executam. Esse double reproduz a identidade dos proxies; não substitui um teste interativo de janelas no executável.
