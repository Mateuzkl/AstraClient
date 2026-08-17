# Plano tecnico de portabilidade do `game_minibot`

## 1. Objetivo e limites

Este documento registra o levantamento feito antes da primeira alteracao de codigo da portabilidade de `D:\game_minibot` para `D:\AstraClient`, com eventuais alteracoes de servidor restritas a `D:\forgottenserver-downgrade-1.8-8.60`.

Regras de execucao:

- `D:\game_minibot` e somente leitura e nao sera modificado.
- O bot existente `game_helper` sera preservado fisicamente, mas impedido de carregar e desacoplado dos demais modulos.
- A interface e os comportamentos expostos pelo modulo original serao preservados. Adaptacoes ficam limitadas a APIs que nao existem no AstraClient e a defeitos objetivos encontrados na origem.
- Nao serao copiados os snapshots completos de `corelib`, `images` e `resources` da origem. Somente dependencias realmente usadas serao incorporadas, evitando sobrescrever infraestrutura e arte global do AstraClient.
- Nao havera caminhos absolutos em runtime.
- O protocolo-alvo do client e do servidor e Tibia 8.60.

Nao foram fornecidos arquivos de imagem anexos junto ao briefing. A referencia visual verificavel e, portanto, a propria arvore OTUI e os PNGs de `D:\game_minibot`.

## 2. Inventario verificado da origem

### 2.1 Totais

`D:\game_minibot` nao e um repositorio Git. A arvore contem 1.607 arquivos e aproximadamente 181,52 MiB:

| Tipo | Quantidade | Tamanho aproximado |
| --- | ---: | ---: |
| PNG | 1.511 | 180,42 MiB |
| Lua | 71 | 0,85 MiB |
| OTUI | 22 | 0,25 MiB |
| OTMOD | 2 | menor que 2 KiB |
| RC | 1 | residual |

Distribuicao relevante:

| Diretorio | Arquivos | Tamanho | Classificacao |
| --- | ---: | ---: | --- |
| `pages` | 36 | 0,78 MiB | Codigo e UI do minibot |
| raiz | 6 | 0,05 MiB | Entrypoint, manifesto e modais |
| `corelib` | 53 | 0,27 MiB | Snapshot parcial do client de origem; nao e copiavel como modulo |
| `images` | 860 | 35,48 MiB | Predominantemente snapshot global do client |
| `resources` | 652 | 144,94 MiB | Predominantemente battlepass/tasks e outros recursos alheios ao minibot |

Os 1.511 PNG possuem cabecalho valido. Cerca de 179,92 MiB nao tem referencia literal no aplicativo do minibot e nao sera copiada sem evidencia de uso.

### 2.2 Entrypoint e ordem de carga

`D:\game_minibot\minibot.otmod` declara `game_minibot`, `sandboxed: true`, `init()` em `@onLoad` e `terminate()` em `@onUnload`. A ordem original carrega:

1. `minibot.lua`;
2. `combat_attack`, `combat_shooter`, `combat_pvp`;
3. `main_settings`, `main_defense`, `main_fortify`;
4. `healing_conditions`, `healing_group`, `healing_health`, `healing_mana`;
5. `support_general`, `support_manashield`;
6. `combat_timers`;
7. `hunting_groupFollow`, `hunting_recorder`, `hunting_explorer`;
8. `equipment_amulets`, `equipment_rings`.

`minibot.lua` cria a janela, presets, tabs, conexoes e botao principal. As paginas sao carregadas sob demanda por `/modules/game_minibot/pages/<pagina>`.

### 2.3 Paginas e estado original

A navegacao original efetivamente exposta e:

- Settings;
- Combat: Attack, Timers, Shooter, PvP;
- Equipment: Amulets, Rings;
- Cave Bot: Recorder, Explorer;
- Healing: Health, Mana, Group;
- Support: General, Mana Shield.

`hunting_groupFollow`, `healing_conditions`, `main_defense` e `main_fortify` sao somente Lua no-op/OTUI vazio e permanecem fora da carga. A decisao inicial de preservar `combat_pvp` inativo foi superada pelo requisito de completar tudo que faltava: a pagina foi finalizada com Tank Mode e Anti-Paralyze, recebeu runtime real nos tipos 16/17 e passou a integrar a navegacao.

### 2.4 Interface e recursos graficos

- Janela principal: 600 x 550, com presets no topo, navegacao lateral e conteudo dinamico.
- Modais de editar/importar preset: 400 x 122.
- Foram encontrados 37 caminhos visuais literais; 35 existem na origem e somam aproximadamente 0,50 MiB.
- `/images/ui/window_light` e `/images/ui/miniwindow_gray` sao referenciados, mas nao existem na propria origem.
- Dependencias de fonte: `cipsoftFont`, `verdana-11px-antialised`, `verdana-11px-rounded` e `verdana-11px-monochrome`.

Recursos customizados usados:

- `border_minibot_dropdown`;
- `button_phantom`;
- `button_shortcut_minibot`;
- `buttons_flags_minibot`;
- `gifs/manashield_minibot`;
- `icon_attack_spell_minibot`;
- `icon_new_entry_minibot`;
- `icon_shortcut_highlight`;
- `icon_source_frame_minibot`;
- `icon_thumbs_minibot`;
- `icons_actions_minibot`;
- `icons_button_change_minibot`;
- `icons_currency`;
- `icons_harmony_minibot`;
- `icons_minibot`;
- `manashield_off_minibot`;
- `minibot_outift_frame`;
- `minibot_spell_block`.

Tambem sao usados controles genericos de automap, actionbar, spells, store e UI. Para evitar regressao visual global, as versoes da origem que forem necessarias ao minibot serao colocadas em namespace proprio dentro de `data/images/game_minibot`, e as referencias OTUI serao ajustadas. Os dois arquivos ausentes na origem serao substituidos por equivalentes reais do tema do AstraClient, sem criar arquivos vazios.

### 2.5 Persistencia

O no persistente original e `Minibot_Settings`, armazenado por `g_settings`:

- Global: idioma, contador/lista de presets, sessoes do recorder e configuracoes das sessoes.
- Por personagem: preset selecionado, nome do preset na game window, painel e atalhos visiveis, sessao selecionada.
- Por preset: metadados e configuracoes de attack, shooter, timers, amuletos, aneis, healing, group healing, support, mana shield e explorer.
- Export/import de preset: marcador `DeusOT_Assistant_Preset_Export`, versao numerica `1002002`.
- Export/import do recorder: versao `1`.

`table.obscure`/`table.unobscure` implementam serializacao ofuscada, nao criptografia. A compatibilidade sera mantida para round-trip e importacao de codigos existentes, acrescida de validacao de tamanho, profundidade, tipo e intervalos antes de aplicar dados externos.

## 3. Funcionalidades identificadas

### 3.1 Modulos de execucao

O modulo original delegava a um singleton nativo `g_minibot`, ausente tanto da pasta fornecida quanto do AstraClient. A ABI inferida dos chamadores e:

- `reset`, `resetModule`, `addModule`, `cycle`;
- `setModuleToggle`, `isModuleToggle`, `setModuleTimeTick`;
- `setAutoAttack`, `getAutoAttack`;
- `getAreaCoordinates`;
- `registerWalkWaypoint`, `resetRecorderSession`;
- `setCurrentWalkIndex`, `getCurrentWalkIndex`;
- `setExplorerWalker`;
- sinais `onWalkToNextNode` e `onWalkFailed`.

Tipos de executor identificados:

| ID | Funcao |
| ---: | --- |
| 0 | shooter por item/spell, alvo e area |
| 1 | healing de vida |
| 2 | healing de mana |
| 3 | timers de combate |
| 4 | haste automatico |
| 5 | cavebot/recorder |
| 6 | group healing |
| 7 | troca de gold |
| 8 | auto eat |
| 9 | reposicao de ammunition |
| 10 | amuletos |
| 11 | aneis |
| 12 | auto training |
| 13 | mana shield por spell |
| 14 | mana shield por item |
| 15 | remocao de mana shield |
| 16 | tank mode, nao exposto pela origem |
| 17 | anti-paralyze, nao exposto pela origem |
| 18 | selecao custom de group healing |
| 19 | selecao de party |
| 20 | selecao de guild |
| 21 | explorer |
| 22 | auto mount |

Auto attack usa `0` desligado, `1` mais proximo/distancia, `2` menor HP, `3` maior HP e `200` smart arrow; o modificador `+100` seleciona logica melee para knight/monk.

### 3.2 Recursos de usuario

- Presets: criar, selecionar, renomear, remover, importar, exportar e persistir por personagem.
- Attack/targeting: prioridades, auto attack e ammunition.
- Shooter: itens/spells, cooldown, mana, HP, hits, area, alvo, PZ e vocacao.
- Timers: regras condicionais de item/spell por HP/mana.
- Healing: vida, mana e grupo, incluindo filtros custom/party/guild/vocacao.
- Equipment: amuletos e aneis com equip/unequip e thresholds.
- Support: haste, change gold, auto eat, auto training, auto mount e tres modos de mana shield.
- Cavebot recorder: sessoes, gravacao, edicao/import/export de waypoints, pathfinding, estados e indicador no minimapa.
- Explorer: configuracao existente na origem, mantida com o mesmo gate visual original.
- Painel compacto na game window, nome do preset e atalhos configuraveis.
- Idiomas PT-BR e EN-US.

Nao ha targeting/looting/supply/alarme/macro genericos separados na origem fornecida. Eles nao serao inventados ou atribuidos ao port.

## 4. Dependencias e compatibilidade

### 4.1 Camada Lua a implementar

Sera criado um runtime real do minibot, com fila unica e ownership explicito de eventos. Ele usara APIs existentes do AstraClient para:

- localizar criaturas, ordenar alvos, atacar e seguir;
- usar itens no proprio jogador, criaturas, tiles e inventario;
- falar spells respeitando cooldown/mana/PZ;
- percorrer containers e slots de equipamento;
- auto-walk/pathfinding e waypoints;
- enviar/receber o estado autorizado de cavebot pelo protocolo de compatibilidade.

Tambem serao implementados adapters para:

- `g_spells` sobre o catalogo `Spells` de `modules/gamelib/spells.lua`;
- busca de itens sobre as funcoes `g_things` realmente registradas no AstraClient;
- `UIWidget:constructEnviorementVariables`, GIF e cor de `UIStoreButton`, somente se ausentes;
- `rgbToHex` e serializacao obscure/unobscure, sem sobrescrever implementacoes existentes;
- painel principal, painel compacto, preset label, timer panel e minimapa;
- opcoes/hotkeys sobre `KeyBinds`/`Options` do AstraClient;
- eventos ausentes do host (`onPlayerInfo`, missile, party e cavebot), substituindo os chamadores por sinais controlados pelo novo modulo onde nao houver equivalente nativo.

O snapshot `D:\game_minibot\corelib` nao sera carregado integralmente: ele redefiniria infraestrutura global do AstraClient e ainda possui dependencias ausentes.

### 4.2 Compatibilidade 8.60

A origem contem IDs de itens/spells e conceitos modernos que podem nao existir no DAT/items/spells 8.60 (itens acima de 28 mil, harmony, monk e cosmeticos). A UI e os presets serao preservados, mas cada regra sera validada contra os catalogos reais antes da execucao. Entradas indisponiveis permanecerao editaveis/importaveis e serao marcadas como invalidas, nunca executadas como outro item/spell.

## 5. Bot atual do AstraClient e plano de desativacao

O bot existente e `D:\AstraClient\mods\game_helper`, com manifesto `helper.otmod` e 27 scripts. Ele e carregado por `modules/game_interface/interface.otmod` em `load-later: game_helper`.

A desativacao controlada tera os seguintes passos:

1. Definir `autoload: false` no manifesto antigo e remover `game_helper` do `load-later` da interface.
2. Nao apagar `mods/game_helper`, seus assets nem configuracoes antigas.
3. Remover as acoes `Helper*`, manter `helperDialog` como launcher do novo Assistant e impedir hotkeys ou botoes orfaos do helper antigo.
4. Substituir referencias globais em:
   - `modules/corelib/keybinds.lua`;
   - `modules/game_sidebuttons/sidebuttons.lua`;
   - `modules/game_interface/gameinterface.lua`;
   - `modules/game_battle/battle.lua`;
   - `modules/game_playerdeath/playerdeath.lua`;
   - `mods/game_tibia_spelllist/t_spelllist.lua`.
5. Migrar o estado compartilhado de target lock para uma API neutra do `game_interface`/novo minibot.
6. Migrar a funcao de layout `game_helper.move`, que nao e comportamento de bot, para um helper neutro do painel.
7. Remover a chamada de drop de spell do helper antigo ou encaminha-la ao novo editor quando houver alvo valido.
8. Garantir que nenhum extended opcode 210/211/212/230 continue sendo enviado pelo modulo antigo.

O `game_helper` nao e seguro para hot-unload: possui monitor recursivo sem handle persistido, callback anonimo, hooks em `g_game.use/useWith` e cleanup incompleto. Por isso a transicao suportada e desativacao no startup seguida de reinicio limpo, nao unload em uma sessao que ja o carregou.

## 6. Plano de portabilidade no client

1. Criar `modules/game_minibot` com os Lua/OTUI efetivamente usados e manifesto adaptado ao carregamento do AstraClient.
2. Preservar a estrutura visual, dimensoes, estilos, callbacks e navegacao da origem.
3. Copiar os 35 assets existentes realmente referenciados para `data/images/game_minibot`, mantendo um manifesto de origem/hash.
4. Corrigir as referencias OTUI aos dois assets inexistentes usando equivalentes reais e isolados.
5. Implementar `compat.lua` com os adapters verificados.
6. Implementar `runtime.lua` para todos os executores expostos, sem loops duplicados e sem mocks.
7. Adaptar o painel compacto e os hotkeys ao sistema nativo do AstraClient.
8. Preservar `Minibot_Settings` e a compatibilidade de import/export.
9. Corrigir defeitos objetivos da origem:
   - variavel `spellsSelfPlayerParam` indefinida em mana healing;
   - evento de recorder sobrevivendo ao terminate;
   - eventos de animacao nested nao removidos;
   - race entre reload agendado e `cycle`;
   - referencias OTUI a IDs inexistentes e `pixel-scroll` invalido;
   - colisao/vazamento de `combatShooterWindow`;
   - conflito do type 9 entre auto attack e ammunition;
   - shortcut de haste sem setter;
   - sessoes removidas deixando settings orfaos;
   - callbacks que capturam widgets destruidos.
10. Validar todos os IDs de item/spell no carregamento e na edicao.
11. Centralizar todos os event handles e remove-los em logout, reconnect, reload e unload.

## 7. Plano de integracao com o servidor

### 7.1 Estado atual verificado

Client e servidor ja suportam extended opcodes. O servidor possui handler de extended opcode e os codigos existentes do helper (`210` cavebot, `211` cast-on-foot, `212` smart-follow, `230` botcheck). O AstraClient 8.60 habilita `GameExtendedOpcode`.

A origem nao contem o wire format de `resourceRequest`, `afkPause`, timer/renew/task do cavebot ou nomes da party. Esses contratos eram APIs custom do client/servidor de origem e nao podem ser copiados diretamente.

### 7.2 Alteracao prevista e criterio

Para manter os controles de cavebot/timer operacionais sem adivinhar packets nativos, sera usado um extended opcode versionado e dedicado, livre no target, com payload JSON limitado e validado. O servidor sera autoritativo para:

- consulta de estado;
- habilitar/desabilitar a sessao de cavebot;
- pausar/retomar quando aplicavel;
- timestamp/tempo restante;
- preco e renovacao;
- flag de task;
- saldo necessario exibido pela UI.

Antes de reservar o numero, sera feita nova busca global no client e servidor. O handler validara opcode, tipo de acao, tamanho, estado do jogador, saldo e intervalos; respostas desconhecidas ou malformadas nao alterarao estado. Se a auditoria de implementacao demonstrar que os controles de timer nao sao habilitados no servidor alvo, o protocolo sera reduzido ao estado booleano 210 ja existente em vez de duplicar responsabilidade.

Nenhuma logica de ataque, healing, targeting, pathfinding ou inventario sera transferida ao servidor.

## 8. Estrategia de testes

### 8.1 Testes estaticos

- Parse de todos os Lua e OTUI do modulo.
- Resolucao de todos os estilos, fontes, widgets, callbacks e caminhos de imagem.
- Busca de referencias residuais a `modules.game_helper` e a acoes `Helper*`.
- Matriz de IDs de item/spell da origem contra catalogos 8.60 do client e servidor.
- Verificacao do manifesto, ordem de carga e dependencias.
- Validacao de payloads/persistencia/importacao com limites.

### 8.2 Inicializacao e ciclo de vida

- Client offline inicia sem erro Lua/OTUI/recurso ausente.
- Login, logout, reconnect e troca de personagem.
- Modulo antigo nao e carregado e seus hooks/opcodes nao aparecem.
- Novo modulo abre/fecha repetidamente e pode ser recarregado sem duplicar signals/timers.
- Pagina ativa e todos os eventos recursivos sao encerrados no unload.

### 8.3 Interface e persistencia

- Abrir todas as 14 paginas expostas e os dois modais.
- Acionar todos os botoes, menus, tooltips, listas e dropdowns.
- Criar/editar/remover/trocar presets e sessoes.
- Round-trip de configuracao global, por personagem, por preset e por sessao.
- Import/export valido, invalido, antigo, grande, profundo e corrompido.
- Dois personagens com selecoes independentes.
- Painel compacto, nome do preset e hotkeys.

### 8.4 Testes funcionais

- Cada executor exposto, thresholds inclusivos e prioridades.
- Sem target, target removido, PZ, cooldown, sem mana, sem item, container fechado e item invalido.
- Auto attack nos cinco modos e modificador melee.
- Shooter single/AoE, healing proprio/grupo, timers, equipment e support.
- Recorder: gravar, reordenar, remover, importar/exportar, andar, mudar de andar, teleport e falha de path.
- Explorer sob o mesmo gate da origem.

### 8.5 Client-servidor e estabilidade

- Handshake/estado de cavebot, payload valido/malformado, ordem de mensagens e permissao.
- Nenhuma desconexao por opcode invalido.
- Builds do client e servidor e smoke startup quando o ambiente fornecer dados/configuracao.
- Soak dos loops, recorder e animacoes; monitorar CPU, memoria e spam de log.
- Regressao de battle list, target lock, movimentacao de paineis, player death e spell list.

Testes que exigem um servidor configurado, credenciais, personagem, mapa ou DAT/SPR compativel serao identificados explicitamente como validacao manual, nunca reportados como executados se o ambiente nao os fornecer.

## 9. Criterios de aceite

- `game_helper` permanece no disco, mas nao carrega e nao deixa botao, hotkey, evento, hook ou opcode ativo.
- `game_minibot` carrega sem erro e disponibiliza 14 paginas, incluindo PvP concluido.
- Todos os assets referenciados resolvem, sem sobrescrever arte global do AstraClient.
- Todos os controles expostos executam uma acao real e persistem quando aplicavel.
- Todos os executores expostos tem implementacao real ou bloqueiam uma entrada comprovadamente invalida com feedback; nao existem stubs de producao.
- Presets/sessoes sobrevivem a logout, reconnect e troca de personagem segundo o escopo original.
- Eventos e timers possuem ownership e cleanup comprovados.
- Integracao de cavebot respeita o protocolo 8.60 e nao aceita payload/estado invalido.
- Client e servidor compilam nos targets disponiveis.
- Testes automaticos/estaticos passam e os testes manuais dependentes de jogo ficam documentados passo a passo.
- O relatorio final lista arquivos criados/modificados/copiados, hashes dos recursos, testes, limitacoes reais e rollback.

## 10. Riscos e mitigacoes

| Risco | Evidencia | Mitigacao |
| --- | --- | --- |
| Runtime original ausente | `g_minibot` nao esta na origem nem no AstraClient | Reimplementar ABI a partir de todos os chamadores e testar cada executor |
| Backend custom ausente | `resourceRequest`/`afkPause` sem wire format | Protocolo de compatibilidade versionado e minimo, somente para estado autoritativo |
| Assets incompletos | Dois paths inexistentes na propria origem | Equivalentes reais isolados e teste de resolucao |
| Snapshot alheio de 181 MiB | 1.476 PNG sem referencia literal | Copiar somente recursos comprovados e registrar hashes |
| Conflito com bot antigo | Referencias unguarded em sete areas do client | Remover/migrar todas antes de desabilitar carga |
| Hot-unload inseguro do helper | Eventos/hooks sem cleanup | Exigir startup limpo apos desativacao |
| IDs modernos em 8.60 | Itens/spells fora do catalogo target | Validacao estrita, feedback visual e nunca remapear silenciosamente |
| Vazamentos/races na origem | Recorder/animacoes/reload agendado | Registry central de eventos, generation token e cleanup idempotente |
| Import malicioso/corrompido | Parser recursivo sem limites | Limites de bytes/profundidade/itens e schema antes de aplicar |
| Ausencia de ambiente de jogo | Testes end-to-end exigem login/mapa | Automatizar o verificavel e documentar claramente o gate manual restante |

## 11. Rollback planejado

O rollback do client consistira em remover `game_minibot` da carga, restaurar as referencias neutras conforme o diff e recolocar `game_helper` no `load-later`/defaults. Como `mods/game_helper` e suas configuracoes nao serao apagados, seus dados permanecerao recuperaveis. O no novo `Minibot_Settings` e independente e pode permanecer sem afetar o helper antigo.

No servidor, o handler/opcode novo, se necessario, sera isolado em script proprio e em um unico registro de evento, permitindo rollback sem migracao destrutiva de schema. Storages eventualmente criados serao documentados e nao reutilizarao os IDs atuais do helper.
