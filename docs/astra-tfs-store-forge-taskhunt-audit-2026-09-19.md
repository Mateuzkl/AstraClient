# Auditoria AstraClient + TFS 1.8 — Store, Forge e Task Hunt

Data: 2026-09-19  
Branch (ambos os repositórios): `fix/store-forge-taskhunt-audit-2026-09-19`

## Resultado executivo

Foram corrigidos os defeitos reproduzíveis encontrados na integração entre o AstraClient e o TFS 1.8 nas áreas solicitadas:

- a API de índice do `UIComboBox` voltou a oferecer `getCurrentIndex()` com o contrato já usado pelos módulos;
- o histórico da Forge agora lê exatamente o layout escrito pelo servidor e ganhou paginação funcional;
- a Forge deixou de disputar os opcodes nativos `0xE2`/`0xE3` e passou a usar `0x38` nas duas direções;
- pacotes da Forge e do Task Board agora validam ação, tamanho, limites e bytes excedentes;
- pagamentos da Forge são ressarcidos quando a mutação do item falha, com tentativa de restauração do estado anterior;
- a sincronização de recursos deixou de publicar Forge Dust também como `ResourceReward`;
- a home da Store não mistura ofertas `SALE`/`TIMED` na seção “Recently Added”;
- ofertas diárias carregam preço efetivo e preço-base separadamente, permitindo mostrar desconto e preço riscado corretamente;
- ações mutáveis do Task Board têm limitação curta por jogador, sem penalizar consultas;
- foi adicionado um teste automatizado para o layout de preço da Store.

As compilações e verificações estáticas passaram. A matriz de testes dentro do jogo ainda precisa ser executada em um ambiente com cliente, servidor e banco ativos; portanto, este relatório não declara validação completa de runtime.

## Causas-raiz e correções

### UIComboBox

O widget mantinha `currentIndex` e expunha `setCurrentIndex()`, mas não possuía o getter simétrico esperado por Task Hunt e Soul Seal. Foi adicionado `getCurrentIndex()`, preservando o índice baseado em 1 e o valor `-1` quando não há seleção.

### Forge History

O servidor escrevia `page`, `pageCount` e `count` como `U16`, mas o cliente interpretava o primeiro campo como a quantidade de registros. Isso deslocava toda a leitura e podia deixar bytes no pacote, culminando em opcode seguinte interpretado incorretamente. O leitor foi sincronizado, recebeu limites defensivos e a tela passou a exibir navegação anterior/próxima.

### Colisão de opcode da Forge

A Forge usava `0xE2` para requisição e `0xE3` para resposta. Esses valores já pertencem ao Reward Wall no protocolo nativo do cliente, e o módulo Lua ainda removia o handler existente antes de registrar o próprio. A integração Forge foi migrada para `0x38` nas duas direções e o registro deixa de sobrescrever silenciosamente um proprietário anterior.

### Store Home e preço diário

A seção “Recently Added” aceitava qualquer destaque e ainda tinha fallback para ofertas normais, contaminando o conjunto com promoções diárias. Agora a seção contém apenas ofertas `NEW`.

O servidor enviava apenas o preço diário efetivo. Como o cliente não recebia o preço-base, comparava dois valores equivalentes e não conseguia desenhar um desconto verdadeiro. No protocolo aprimorado, o servidor agora envia `effectivePrice` e `basePrice`; o cliente usa o primeiro para compra e o segundo para a exibição riscada. Clientes no layout legado continuam recebendo somente o preço efetivo.

### Forge: atomicidade e recursos

O pagamento era debitado antes de todas as alterações no item terminarem. Falhas intermediárias podiam consumir saldo sem concluir a operação. A cobrança agora gera um recibo, as mutações críticas são verificadas e, em falha, o valor é devolvido e o estado anterior do item é restaurado quando aplicável.

A atualização de saldo emitia Forge Dust corretamente no subtipo `23`, mas também repetia o mesmo número como `ResourceReward` no subtipo `20`. O envio incorreto foi removido; o limite de proficiência/Forge no subtipo `88` foi mantido.

### Task Board / Task Hunt

O mapeamento de tamanhos e tipos entre cliente e servidor estava alinhado, porém o parser aceitava ações desconhecidas e dados extras. O servidor agora usa uma lista explícita de ações válidas, rejeita payload residual e aplica cooldown de 150 ms apenas às ações mutáveis. Abrir telas e consultar informações permanece sem throttle.

## Contratos de protocolo afetados

### Forge (`0x38`)

Requisição de histórico:

```text
U8 opcode=0x38
U8 action=6
U16 page
```

Resposta de histórico:

```text
U8 opcode=0x38
U8 response=5
U16 page
U16 pageCount
U16 count
repeat count times:
  U32 timestamp
  U8 result
  string details
```

O servidor também aceita o pedido legado de histórico sem o campo `page`, interpretando-o como página zero. Todas as outras ações da Forge exigem o tamanho exato de payload.

### Store — oferta com highlights

Trecho do layout após o ícone:

```text
U32 effectivePrice
U32 basePrice
U16 displayId
U16 count
string description
string type
U8 state
[U32 expiresAt quando SALE ou TIMED]
```

No layout legado, somente `effectivePrice` é enviado e os campos de highlight não são incluídos.

### OpCodes auditados nos sistemas afetados

| Direção | Opcode | Dono / finalidade |
|---|---:|---|
| cliente → servidor | `0x38` | Forge |
| servidor → cliente | `0x38` | Forge |
| cliente → servidor | `0x5F` | Task Board |
| servidor → cliente | `0x53` | Task Board |
| servidor → cliente | `0xEE` | saldos de recursos, multiplexado por subtipo |
| cliente → servidor | `0xF8`, `0xFA`, `0xFB`, `0xFC` | Store |
| servidor → cliente | `0xFD` | Store |
| nativo | `0xE2`, `0xE3` | Reward Wall, não mais sobrescrito pela Forge |

Os slots da Store são uma extensão coordenada deste par Astra/TFS 8.60. A compatibilidade com outros clientes ou servidores que reutilizem esses slots deve ser negociada separadamente.

## Arquivos alterados

### AstraClient

- `modules/corelib/ui/uicombobox.lua`
- `mods/game_forge/forge.lua`
- `mods/game_forge/classes/Forge.lua`
- `mods/game_forge/styles/history.otui`
- `mods/game_store/storeprotocol.lua`
- `mods/game_store/classes/Home.lua`
- `mods/game_store/styles/buttons.otui`
- `mods/game_store/styles/offers.otui`

### TFS 1.8

- `data/scripts/network/forge/forge.lua`
- `data/scripts/network/task_board/protocol.lua`
- `data/scripts/network/task_board/init.lua`
- `src/protocolgame.cpp`
- `src/store/store_protocol.h`
- `src/tests/test_store_service.cpp`

## Validação executada

- AstraClient `OpenGL|x64`: compilação concluída com sucesso.
- AstraClient `Debug|x64`: compilação concluída com sucesso.
- TFS target principal `tfs` em Release/WSL: compilação e link concluídos com sucesso.
- `test_store_service`: 12 testes aprovados, incluindo o novo contrato `effectivePrice`/`basePrice`.
- Sintaxe Lua dos arquivos alterados: aprovada com Lua 5.5.
- `git diff --check`: aprovado nos dois repositórios.

O build Debug do cliente ainda emite o aviso preexistente `LNK4075` sobre `/INCREMENTAL` ser ignorado por causa de `/OPT:ICF`; não foi introduzido por estas alterações.

## Validação manual pendente

Executar com banco descartável ou backup:

1. abrir a Forge, verificar preços, saldo, limites e todas as listas;
2. executar fusion e transfer com sucesso;
3. forçar saldo insuficiente, item removido e falha de mutação, confirmando que não há débito líquido;
4. abrir o histórico vazio, com uma página e com múltiplas páginas;
5. abrir Store Home e confirmar que “Recently Added” só contém `NEW`;
6. confirmar oferta diária com preço-base riscado, preço efetivo e compra pelo valor correto;
7. abrir Task Hunt, aceitar, cancelar e concluir tarefas, incluindo cliques rápidos repetidos;
8. observar o log do cliente e confirmar ausência de `unhandled opcode 5`, colisões de opcode e erros de payload.

## Riscos residuais

- A restauração de um item removido durante rollback da Forge recria o item e o tier; atributos customizados de terceiros além dos tratados pelo sistema devem ser validados em teste de injeção de falha.
- O ressarcimento de gold volta para o banco, preservando o valor total, mas não necessariamente a mesma divisão original entre inventário e banco.
- O novo campo `basePrice` exige que cliente e servidor atualizados sejam usados juntos quando highlights estiverem ativos.
- Não foi realizada uma prova exaustiva de todos os opcodes de módulos externos aos três sistemas auditados.
