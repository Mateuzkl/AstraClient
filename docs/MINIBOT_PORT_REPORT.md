# Relatório técnico da portabilidade do MiniBot

Data da consolidação: 20/07/2026  
Origem somente leitura: `D:\game_minibot`  
Cliente de destino: `D:\AstraClient`  
Servidor de destino: `D:\forgottenserver-downgrade-1.8-8.60`  
Protocolo-alvo: Tibia 8.60

## 1. Estado da entrega

A portabilidade de código, interface, recursos, persistência, runtime e integração de servidor está implementada. O bot anterior do AstraClient, `game_helper`, foi preservado no disco e retirado da carga, dos atalhos e das integrações globais. O botão `helperDialog` foi restaurado como entrada visual do Assistant e agora chama exclusivamente `modules.game_minibot.toggle()`. O novo módulo `game_minibot` passou a ser o módulo carregado pelo `game_interface`.

Foram transportadas 14 páginas, incluindo a conclusão da página PvP que estava interrompida na origem, criada uma implementação funcional da ABI `g_minibot` que não existia nem no doador nem no AstraClient e implementado o serviço autoritativo de Cave Bot no servidor. Também foram criadas as dependências que faltavam para som, ícones de spell, sinais de protocolo, timer, Task, renovação, pausa AFK, bot-check e persistência segura.

Uma validação real posterior, conduzida no cliente Windows já aberto pelo usuário, encontrou uma regressão transversal que os smokes anteriores não capturaram: o Astra dispara `onClick`, enquanto a interface doadora registra suas ações em `onLeftClick`. Por isso as abas renderizavam, mas botões, `New Entry`, seletores e ações de configuração não respondiam. A investigação também encontrou o launcher do Assistant ausente, `Player:getVocationName()` inexistente, chamadas `getName()` incompatíveis em itens/tipos, `isMarketable()` sendo chamado sobre `ItemType`, referências de hotkey a widgets já destruídos e avisos de widgets destruídos duas vezes.

As incompatibilidades foram corrigidas no código: o encaminhamento `onClick` → `onLeftClick` passou a fazer parte do Lua-base de `UIWidget`, `UICheckBox` e `UIItem`, sem substituir dinamicamente a identidade de `onClick`; o teardown das páginas foi centralizado; a vocação ganhou resolução compatível; itens encontrados como `ItemType` são convertidos para `ThingType` antes das APIs de mercado; `ThingType:getName()` e `Item:getName()` ganharam fallback seguro; e o lifecycle da tela de hotkeys limpa o último foco antes de reconstruir ou destruir linhas. `helperDialog` voltou a abrir somente o MiniBot. Também foram adicionadas as compatibilidades restantes dos campos numéricos e da navegação de listas por teclado.

Na auditoria interativa desta rodada, as 14 páginas ativas foram abertas e inspecionadas no cliente, com interações seguras em listas, entradas e seletores; desde o baseline adotado, o log permaneceu com **zero `ERROR`**. A inspeção visual revelou ajustes adicionais no Cave Recorder/Explorer, na ancoragem da configuração de Mana Shield, na mensagem de toggle de Settings e nos frames usados globalmente. Esses ajustes mais recentes estão gravados no disco, mas ainda não foram carregados pelo processo atual: o cliente aguarda reinício manual do usuário e nova inspeção antes do aceite final. Por solicitação expressa, nenhum build, Docker ou servidor foi iniciado nesta rodada.

Nenhum mundo, banco, conta ou personagem de produção foi alterado. Antes da solicitação para interromper execuções, foi usado um ambiente estritamente descartável com MariaDB 11.4 em container, schema completo do projeto e `tests/minibot_boot_config.lua` herdando os defaults. Naquela revisão o servidor carregou scripts e mapa, chegou a `SERVER ONLINE`, aceitou conexões nas três portas e encerrou graciosamente. O usuário fará os builds Release e a validação Linux; execução funcional das automações em gameplay, regressão gráfica final pós-reinício e soak prolongado continuam no roteiro manual da seção 12.

## 2. Inventário e fidelidade da origem

A árvore `D:\game_minibot` foi mantida sem alterações e, na conferência final, continuava com os mesmos totais levantados antes da implementação:

| Tipo | Quantidade |
| --- | ---: |
| PNG | 1.511 |
| Lua | 71 |
| OTUI | 22 |
| OTMOD | 2 |
| RC residual | 1 |
| **Total** | **1.607 arquivos / 190.337.184 bytes** |

O doador contém snapshots globais de `corelib`, `images` e `resources` que não pertencem ao MiniBot. Eles não foram despejados sobre o AstraClient. Foram levados apenas os scripts, as telas e os recursos comprovadamente usados, evitando sobrescrever estilos e arte globais.

No levantamento inicial, a referência visual verificável era a própria interface OTUI e os PNGs do doador. As capturas enviadas depois pelo usuário mostraram a janela renderizada no Astra e foram usadas para diagnosticar a ausência do launcher, os controles sem ação e os avisos de lifecycle. Dimensões, hierarquia, tabs, clips, cores e estados foram preservados por portabilidade direta dos OTUI, com adaptação de namespaces e APIs incompatíveis.

### 2.1 Páginas ativas portadas

| Grupo | Páginas |
| --- | --- |
| Principal | Settings |
| Combat | Attack, Timers, Shooter, PvP |
| Equipment | Amulets, Rings |
| Cave Bot | Recorder, Explorer |
| Healing | Health, Mana, Group |
| Support | General, Mana Shield |

### 2.2 Arquivos preservados, mas não carregados

`hunting_groupFollow`, `healing_conditions`, `main_defense` e `main_fortify` continuam preservados para rastreabilidade e fora da navegação porque são no-op/OTUI vazio sem comportamento útil. `select.otui` também foi preservado como artefato órfão da origem: não há `MiniBotSystem` nem qualquer chamador/carregamento no doador ou no port, portanto ele não pertence às 14 páginas/modais ativos. `combat_pvp`, ao contrário, foi completado, carregado e exposto com Tank Mode e Anti-Paralyze funcionais.

## 3. Arquivos criados, portados, modificados e desativados

### 3.1 Cliente: módulo criado/portado

O diretório `modules/game_minibot` contém 45 arquivos, totalizando 1.001.806 bytes:

- 21 arquivos Lua;
- 22 arquivos OTUI;
- 1 manifesto OTMOD;
- 1 manifesto de assets em Markdown.

Arquivos-base:

- `modules/game_minibot/minibot.otmod`;
- `modules/game_minibot/minibot.lua`;
- `modules/game_minibot/compat.lua`;
- `modules/game_minibot/runtime.lua`;
- `modules/game_minibot/minibot.otui`;
- `modules/game_minibot/minibot_editpreset.otui`;
- `modules/game_minibot/minibot_importpreset.otui`;
- `modules/game_minibot/select.otui`;
- `modules/game_minibot/ASSET_MANIFEST.md`.

Pares Lua/OTUI portados para `modules/game_minibot/pages`:

- `combat_attack`, `combat_pvp`, `combat_shooter`, `combat_timers`;
- `equipment_amulets`, `equipment_rings`;
- `healing_conditions`, `healing_group`, `healing_health`, `healing_mana`;
- `hunting_explorer`, `hunting_groupFollow`, `hunting_recorder`;
- `main_defense`, `main_fortify`, `main_settings`;
- `support_general`, `support_manashield`.

Os seguintes arquivos de verificação também foram criados:

- `test.lua`, smoke offline executado pelo próprio OTClient;
- `tests/minibot_runtime_smoke.lua`;
- `tests/minibot_executors_smoke.lua`;
- `tests/minibot_botcheck_smoke.lua`;
- `tests/minibot_config_hardening_smoke.lua`;
- `docs/MINIBOT_PORT_PLAN.md`;
- `docs/MINIBOT_PORT_REPORT.md`.

### 3.2 Cliente: arquivos modificados

| Arquivo | Alteração |
| --- | --- |
| `data/json/default-options.json` | Mantém `helperDialog` como botão do Assistant, remove ações `Helper*` e migra o atalho padrão `Ctrl+H` para `ShowMiniBot`. |
| `mods/game_compendium/compendium.lua` | Atualiza a descrição do recurso para Astra Assistant. |
| `mods/game_helper/helper.otmod` | Define `autoload: false`, preservando o código antigo inativo. |
| `mods/game_tibia_spelllist/t_spelllist.lua` | Remove o callback residual de drop de spell no helper aposentado. |
| `mods/client_settings/settings.lua` | Valida widgets ainda vivos e limpa `lastFocusHK` antes de teardown, rebuild, busca e troca de perfil/chat, evitando acesso a `firstKey`/`actionEdit` já destruídos. |
| `modules/client_options/options.lua` | Migra configurações antigas, reinsere `helperDialog` exatamente uma vez em instalações já migradas e preserva a escolha enabled/disabled. |
| `modules/corelib/keybinds.lua` | Substitui a categoria Helper por Assistant e cria hotkeys reais para janela e toggles do MiniBot. |
| `modules/corelib/ui/uiwidget.lua` | Implementa `dispatchLeftClick` e encaminha o clique nativo do Astra para callbacks `onLeftClick` importados, preservando a identidade de `onClick`. |
| `modules/corelib/ui/uicheckbox.lua` | Mantém o toggle nativo e, com o widget ainda vivo, despacha o callback `onLeftClick`. |
| `modules/game_battle/battle.lua` | Move o target lock para a API neutra de `game_interface`. |
| `modules/game_interface/gameinterface.lua` | Implementa target lock, painel compacto, nome do preset, timer de Cave Bot e cleanup correspondente. |
| `modules/game_interface/interface.otmod` | Retira `game_helper` do `load-later` e carrega `game_minibot`. |
| `modules/game_mainpanel/mainpanel.lua` | Hospeda a função neutra para mover janelas entre painéis. |
| `modules/game_playerdeath/playerdeath.lua` | Desliga Shooter e Auto Attack do MiniBot na morte, sem chamar o helper antigo. |
| `modules/game_sidebuttons/sidebuttons.lua` | Mantém `helperDialog` configurável e direciona seu clique ao toggle do MiniBot. |
| `modules/gamelib/const.lua` | Define o tooltip `Assistant` para `helperDialog`. |
| `modules/gamelib/ui/uiitem.lua` | Preserva o seletor nativo de item editável e também despacha `onLeftClick` para as telas portadas. |
| `src/client/protocolgameparse.cpp` | Publica `g_game.onMissileTo` e `g_game.onPlayerInfo`, sinais necessários ao módulo. |

Dentro do próprio módulo portado, `compat.lua` passou a normalizar `ItemType` para `ThingType`, a usar explicitamente `ThingCategoryItem` e a fornecer nomes por metadata de mercado, registro nativo ou fallback por ID. `main_settings.lua` resolve a vocação sem depender de `Player:getVocationName()` e chama `displayGameMessage` com a assinatura disponível no Astra. Os OTUIs de Mana Shield, Recorder e Explorer também receberam correções de ancoragem e limites descritas nas seções 4, 8 e 9.

### 3.3 Cliente: arquivos copiados e dependências criadas

Os Lua/OTUI acima foram portados do doador e adaptados em namespace, lifecycle e APIs. Os PNGs foram copiados para `data/images/game_minibot`, sem alterar arte global. A seção 4 registra os hashes.

Para permitir inicialização real do cliente 8.60 no ambiente de teste, também foi disponibilizado `data/things/860` com:

- `Tibia.dat` — 5.407.372 bytes;
- `Tibia.spr` — 452.750.765 bytes;
- `Tibia.otfi` — 186 bytes.

O checkout local `vcpkg/` foi usado para resolver dependências de compilação. Ele é infraestrutura de build, não código de produção nem dependência distribuída do módulo.

### 3.4 Cliente: bot anterior desativado

Nenhum arquivo de `mods/game_helper` foi apagado. A desativação foi deliberadamente reversível:

- `autoload: false` no manifesto antigo;
- remoção do `game_helper` da lista de carga do `game_interface`;
- manutenção de `helperDialog` apenas como botão do novo Assistant, sem callback ao helper antigo;
- remoção dos mapeamentos `HelperStatus`, `HelperTarget`, `HelperShooter` e `ShowHelper` dos defaults;
- migração de configurações antigas para `ShowMiniBot`, sem duplicar `Ctrl+H`;
- remoção de chamadas externas ao namespace antigo em battle list, spell list, player death e UI;
- migração de target lock e movimentação de painéis para APIs neutras.

Uma busca final fora de `mods/game_helper` encontra `ShowHelper` somente no migrador de configurações antigas. As referências operacionais a `helperDialog` pertencem ao side button do novo Assistant e chamam somente `modules.game_minibot.toggle()`.

### 3.5 Servidor: arquivos criados

- `data/scripts/talkactions/god/moderation/minibot_admin.lua`;
- `tests/minibot_server_state_smoke.lua`;
- `tests/minibot_task_rewards_smoke.lua`;
- `tests/minibot_boot_config.lua`, configuração somente de teste para o boot isolado.

### 3.6 Servidor: arquivos modificados

| Arquivo | Alteração |
| --- | --- |
| `data/lib/core/storages.lua` | Reserva e documenta storages do estado MiniBot. |
| `data/lib/functions/astra_helper.lua` | Implementa serviço autoritativo, timer, renovação, Task, AFK, ban, bot-check, rate limit e serialização do estado. |
| `data/scripts/creaturescripts/others/extendedopcode.lua` | Roteia opcodes 210/213, sincroniza login/logout e publica estado a cada 30 segundos. |
| `data/scripts/eventcallbacks/monster/default_onDropLoot.lua` | Aplica multiplicador Task a loot normal, Prey e Bounty sem alterar o RNG no baseline. |
| `data/scripts/eventcallbacks/player/default_onGainExperience.lua` | Aplica XP Task com prioridade 50, antes de Weapon Proficiency e mensagens. |
| `data/scripts/globalevents/influenced_spawn.lua` | Aplica Task a Forge Dust/Sliver e informa a XP extra realmente concedida. |
| `data/scripts/quests/soulpit/ondroploot_soul_core.lua` | Aplica Task a Soul Core e Soul Prism preservando o caminho RNG normal. |
| `src/game.h` | Persiste no score de reward boss o multiplicador mais restritivo observado. |
| `src/game.cpp` | Registra o modo de recompensa em dano causado, dano recebido e cura relevante. |
| `src/monster.cpp` | Aplica o multiplicador congelado no payout de reward boss, inclusive itens únicos. |
| `src/protocolgame.cpp` | Remove a antiga autoridade C++ duplicada do opcode 210; Lua passa a ser a única autoridade. |
| `vc18/theforgottenserver.vcxproj` | Adiciona `/bigobj /FS` às quatro configurações para compilação estável. |

## 4. Recursos gráficos e hashes

Foram instalados 39 PNGs em `data/images/game_minibot`, somando 609.358 bytes. A verificação final releu as 39 linhas do manifesto, calculou SHA-256 do arquivo instalado e do arquivo doador correspondente e obteve `BAD=0`.

Das 37 referências visuais literais do MiniBot, 35 existiam no caminho original e foram copiadas byte a byte. As duas referências que faltavam no próprio doador foram resolvidas com assets reais do mesmo tema:

- `images/ui/miniwindow_gray.png` usa `images/ui/miniwindow.png`;
- `images/ui/window_light.png` usa `images/ui/window.png`.

`button_blue.png` e `button_yellow.png` são as duas dependências adicionais do adapter de `UIStoreButton`. Nenhum caminho absoluto foi usado em runtime.

Como esses dois aliases têm geometria de nine-slice diferente daquela declarada no OTUI doador, todas as referências também foram normalizadas: os **25 usos** de `window_light` usam bordas esquerda/direita/superior/inferior **4/4/25/4**, e os **17 usos** de `miniwindow_gray` usam `image-border: 4`. A correção é global no namespace do MiniBot e elimina a deformação/corte dos frames observada na inspeção visual; o aceite visual final depende do próximo reinício manual.

| Caminho instalado sob `data/images/game_minibot` | SHA-256 |
| --- | --- |
| `images/automap/automap_indicator_maplayers.png` | `847595b2acd672e26ee7c37d4f8197e00b103e8152bf3efbab820af21a5a7906` |
| `images/automap/automap_indicator_slider_left.png` | `9cbfd48ea00396becc2097e4e0213c735049950111305c1c50a4e9c53d04e3f4` |
| `images/automap/automap_phantom.png` | `67798d969f6f7ed4d64bfdb24e16b103c73e1588e1f1560c22a8129667785839` |
| `images/game/actionbar/actionbarslot.png` | `b23941e9eb3112b639301d9e5a79f2a340e73da5a82a2579fb7ac6b58b25df88` |
| `images/game/spells/spell_regular_icons.png` | `5f8d63d03c72131979bd53c6994d3e3e083ae5a439ea862a26b40a7d865e5ed1` |
| `images/icons/show_gui_help_grey.png` | `2ef93d83b3595cafa256d02b0c1cbb533b7723298b02d925eda8f1cd19744ec3` |
| `images/options/button_clipboard.png` | `6687ddacd3c86f9929d73baf471e0a56420cee28673d315319f5ee459d705c00` |
| `images/store/button_blue.png` | `1e4b016d7b129c2263eac89a81248c784278cd5faa8790ac5041b6e5fc3bff23` |
| `images/store/button_green.png` | `5c43fce26ebf48ee2326d353db12b373ad12434c2b5f592d7158ed1274037e88` |
| `images/store/button_red.png` | `e295b71287b7817146c57867260e3fcec747c05df09845f7e791f7ed70ceeca1` |
| `images/store/button_yellow.png` | `cf950ddd70d90cdc58eced4296c056588ec2ea560f8dbf0a3002ba53b31c8052` |
| `images/store/downarrow.png` | `4ddc8b6f084d6c8fb4c59725d98a1a3f9594b883821a120cdbc0bc4b5759bd4e` |
| `images/store/selector_right.png` | `3680ff0b7f6f148c60a96e5b9c813aad4ea3ffb1491a4ac751884f10a1c45d2a` |
| `images/ui/1pixel_down_frame.png` | `954d62fb3da0b093f5eee1555be26fd6d8bfddafd7cb6320c3eafae4063fa780` |
| `images/ui/2pixel_up_frame_borderimage.png` | `bcdc632538c1d9c4c61775292959913738f8c6f780bd3d53cb1b478db69c6ff3` |
| `images/ui/2pixel_up_frame_borderimage_dark.png` | `c0c1dbc81037d36ea6b0c462f767d0e1cc950678c8a569f44e0c56c29fa307ad` |
| `images/ui/button.png` | `f4ceddfeba47795fd41a99732c267918fddcf20f8202f3dde84c8b311e1e7191` |
| `images/ui/containerslot.png` | `eabae2ae278748bf852596671f33829d966925054dc5b3641d4be6b25ff5a3ec` |
| `images/ui/miniwindow_gray.png` | `17748fc378ece6def9f23f5ffc1ebdc7bcd70c5193ac87f21ae4001afd8876fa` |
| `images/ui/vertical_line_dark.png` | `612bac8f07a1f9184cd834bf10ea8da9954fa2a51d9c37fd33fdaa75042ef4cc` |
| `images/ui/window_light.png` | `d81d52d06cadd8c352ae1d8865a167d2c14d74aab1565e18df7c8783f9b9e3af` |
| `resources/border_minibot_dropdown.png` | `baad7b80536543bab353a775505ea568613cb266ce6e28a649c5c139eac43551` |
| `resources/button_phantom.png` | `0552bce0e5cc94745631bd28a26a3a8af7478fe591cd1c60ae9c68f8fc3dfb10` |
| `resources/button_shortcut_minibot.png` | `d0886073b86619c945ec70a7acdb7d12c6c4dbe1357834c6593483377afd38f9` |
| `resources/buttons_flags_minibot.png` | `04b1166bfcc724f6b3b8f749a83e9540ea8900955fafef7ebbf5177c89b7c627` |
| `resources/gifs/manashield_minibot.png` | `41536fd2f105cdd405c5bde0a1a8b00117ba1acfb7a1cfc1144a83d667ba8163` |
| `resources/icon_attack_spell_minibot.png` | `8add26e71afcfa06c1447b54c72582dcf4e4ce42e13a3a7eaaf418b2c7bafe53` |
| `resources/icon_new_entry_minibot.png` | `d49f5cc0cbad77629fb43f71f10b69cb1a47c2da63ea3d0b56bc1637830a90e4` |
| `resources/icon_shortcut_highlight.png` | `dc5c6cf9f43f5573ca8bda463869bd2c08b2226607fdbe7dc8ffbc536edcaa71` |
| `resources/icon_source_frame_minibot.png` | `fc0851a0dafaa5ae89ecc285b82d35155c7a3abe1a94719bbaf377fd5b110a6b` |
| `resources/icon_thumbs_minibot.png` | `488068f177d53a7efd109414965f098a331f23608118d8f1a4e81fc05a93c448` |
| `resources/icons_actions_minibot.png` | `e1b8e66e9843a27989101838f18366e13c2af1300cda6b5f5e12808e654928a5` |
| `resources/icons_button_change_minibot.png` | `a0357eeeff4d5b2398e3cf0968efc2b83a403e001230e60e0d6a005997f6dfea` |
| `resources/icons_currency.png` | `2e3f026420f5ea6230a2d55f56bd8bc5622e73f3d499463ae116fbb41b421e23` |
| `resources/icons_harmony_minibot.png` | `3959bec3512a42dbd5a40087de292a95101a5ac0695c7c20c999c50267ecd87b` |
| `resources/icons_minibot.png` | `69e8a76f6c4dd53a649e6ed4c17190ea432bd9ef7a8cec4cec37c4215f82056a` |
| `resources/manashield_off_minibot.png` | `fa0556087f1ca451dd4ad9dbf9e03e86f36ff4d40bb3e2e41b21480ace88713c` |
| `resources/minibot_outift_frame.png` | `9629242c2ef5134c61eca35fa3efe0b7d72794d1b7c780bf5135b9c5e8009cb8` |
| `resources/minibot_spell_block.png` | `6ddad8eae5ab359feba061d47b2c073b368cf2a6e51fcb2fb6f1667ca4d788b1` |

O mapeamento completo entre caminho instalado, caminho doador e hash também está em `modules/game_minibot/ASSET_MANIFEST.md`.

## 5. Funcionalidades portadas no cliente

### 5.1 Interface, presets e persistência

- Janela principal de 600 x 550, navegação lateral, páginas filhas e modais de editar/importar.
- Abertura por `Ctrl+H`, toggle pela categoria Assistant e integração com o botão de opções.
- Presets com criar, renomear, remover, selecionar, próximo/anterior, importar e exportar por clipboard.
- Estado global e estado por personagem em `Minibot_Settings`.
- Nome do preset e timer de Cave Bot opcionais sobre a game window.
- Painel compacto com toggles sincronizados com as páginas.
- Português e inglês, tooltips, menus, dropdowns, listas e estados visuais da origem.
- Recorder com sessões próprias e configurações/waypoints independentes.

### 5.2 Runtime funcional

Foi implementada a ABI real `g_minibot`, cobrindo todos os tipos 0–22 usados pelas páginas ativas. Os tipos 16/17 executam, respectivamente, Tank Mode e Anti-Paralyze da página PvP concluída.

O runtime executa:

- Health e Mana Healing por spell ou item, com limites e cooldowns;
- Group Healing customizado, party e guild, com filtro de vocação e suporte à preparação por Virtue;
- Shooter single target, item, spell, AoE centrada no alvo e áreas direcionais;
- matrizes de área originais, incluindo círculos, cruz, anel, hammer, wave, beam e spear;
- Combat Timers por quantidade de criaturas e intervalo configurado;
- Tank Mode com Stone Skin Amulet/Might Ring e Anti-Paralyze ordenado por prioridade, mana, PZ e cooldowns;
- Auto Attack nos modos de seleção expostos, incluindo proximidade, menor HP, cluster e restrição melee;
- equipar/desequipar amuletos e anéis, com prioridades, limites e lista de itens ignorados;
- refill de munição a partir de containers abertos;
- haste, troca de moedas, auto eat, exercise training e auto mount;
- ativação de Mana Shield por spell/item, fallback, Fear e remoção condicionada;
- Recorder com avanço de waypoint, autowalk, pausa/retomada por monstros, mudança de andar e falhas controladas;
- Explorer com seleção de destino, pausa/retomada e o mesmo scheduler controlado do runtime.

Entradas inválidas, recursos ausentes, target removido, container fechado, PZ, cooldown e logout resultam em bloqueio seguro da ação, não em chamadas fictícias.

### 5.3 Lifecycle e estabilidade

- Um único scheduler recursivo, sem loops paralelos de página.
- `init`, `start`, `stop` e `terminate` idempotentes.
- Handles de eventos, animações, missiles, reloads e recorder removidos no encerramento.
- Generation tokens impedem callbacks antigos de atuar depois de reload/reconnect.
- O runtime não inicia offline nem antes de `onPlayerInfo` confirmar que a sessão está pronta.
- Logout para todos os módulos, toggles, Auto Attack e estado transitório, impedindo vazamento entre personagens.
- Recorder e Explorer são mutuamente exclusivos.
- O teardown de páginas cancela eventos e catchers antes de o contêiner pai destruir a árvore uma única vez, evitando destruição duplicada e overlays interceptando cliques.
- A tela global de hotkeys invalida `lastFocusHK` de forma segura antes de destruir/recriar linhas, trocar perfil, alternar chat, buscar, resetar, sair do jogo ou terminar o módulo.
- Desabilitação autoritativa do Cave Bot interrompe autowalk somente quando havia uma transição ativa; estados repetidos não interrompem movimento alheio.
- Bot-check desliga Cave Bot, Explorer, Auto Attack e ataque atual antes de disparar alarme, flash e repetição sonora.
- Logs temporários de implementação não ficaram no runtime; os avisos de produção remanescentes identificam somente erro real de página, configuração ou adapter.

### 5.4 Persistência endurecida

A configuração é validada antes de persistir ou importar. O saneador:

- repara raízes antigas/corrompidas quando a recuperação é determinística;
- descarta entradas individuais inválidas sem destruir coleções válidas;
- rejeita importações com schema incorreto antes de qualquer escrita;
- rejeita ciclos, `NaN`, infinito, UID inválido e posições/índices inválidos;
- limita profundidade a 16, nós a 20.000, entradas de tabela a 4.096, coleções a 256, listas a 512, waypoints a 4.096 e import a 1 MiB;
- repara metadata ausente, contadores e nós por personagem;
- remove configurações órfãs de sessões apagadas.

## 6. Camadas de compatibilidade criadas

| Superfície ausente/diferente | Solução implementada |
| --- | --- |
| ABI nativa `g_minibot` ausente | `runtime.lua` implementa estado, executores, áreas, recorder, explorer e lifecycle reais. |
| Recursos/timer customizados do doador | Adapter de `LocalPlayer` usa estado local e opcode JSON 213 autoritativo. |
| `afkPause` sem wire format | Ação versionada `pause` no opcode 213, validada pelo servidor. |
| API de spells diferente | Adapter normaliza dados, busca e grupos; converte ID de spell do servidor para ID/clip do cliente e faz o caminho reverso. |
| Cooldowns de spell/actionbar | Adapter consulta o estado real do actionbar. |
| Busca de itens/market categories | Adapters sobre `g_things` e catálogos existentes. |
| `ThingType:getName()` ausente e `Item:getName()` vazio sem OTB/XML | Adapter preserva nome nativo não vazio, consulta metadata de mercado e usa fallback estável por ID sem recursão. |
| Busca textual retorna `ItemType`, sem `isMarketable()` | Conversão explícita pelo client ID para `ThingType`/`ThingCategoryItem` antes de consultar mercado. |
| `UIStoreButton`/estilos ausentes | Superfície compatível e quatro cores com assets isolados. |
| Foco do chat diferente | `focusChat` seguro, apenas quando o console existe e está habilitado. |
| Som de alarme diferente | `playAlarm`/`stopAlarm` sobre o canal Bot, com preload e restauração no terminate. |
| Missile callback ausente | Sinal C++ `g_game.onMissileTo`. |
| Momento confiável pós-login ausente | Sinal C++ `g_game.onPlayerInfo`; runtime aguarda esse ponto. |
| Target lock dependia do helper | API neutra `clearLockedTarget`, `setLockedTarget` e `attackCreature` em `game_interface`. |
| Movimento entre painéis dependia do helper | Função neutra em `game_mainpanel`. |
| Painel compacto e timer | Widgets com ownership e cleanup em `game_interface`. |
| Bot-check antigo | Adapter do opcode 230 com som, flash, cleanup, generation token e reconciliação pelo estado 213. |

Todos os adapters são removidos ou restaurados em `terminate`; não foram deixados mocks, TODOs funcionais ou funções vazias substituindo produção.

## 7. Integração e alterações do servidor

### 7.1 Contrato de protocolo

| Opcode | Direção | Função |
| ---: | --- | --- |
| 210 | cliente → servidor | Toggle canônico de Cave Bot, payload estrito `0` ou `1`. |
| 213 | bidirecional | JSON versionado para `query`, `pause`, `task`, `renew` e resposta `state`. |
| 230 | servidor → cliente | Iniciar/parar alarme de bot-check. |

Os opcodes existentes 211 (Cast on Foot) e 212 (Smart Follow) foram preservados. O 210 deixou de ser tratado pelo caminho genérico em C++ para não haver duas autoridades; toda validação e persistência dele está em Lua.

O payload 213 é limitado a 4.096 bytes, exige versão 1 e action conhecida. O servidor aceita no máximo oito solicitações MiniBot por jogador por segundo. Tráfego excedente é descartado antes de JSON, storage e resposta. Saldos enviados ao JSON são limitados a `9.007.199.254.740.991`, evitando perda de precisão no cliente.

### 7.2 Storages

| Storage | ID | Uso |
| --- | ---: | --- |
| Cavebot | 99997 | Estado autoritativo ligado/desligado. |
| Smart Follow | 99998 | Compatibilidade já existente. |
| Astra/Mehah client | 99999 | Detecção de cliente já existente. |
| Time Left | 100020 | Segundos restantes. |
| Total Time | 100021 | Capacidade total da sessão. |
| Started At | 100022 | Âncora para consumo do relógio. |
| Task | 100023 | Modo Task. |
| Renewals | 100024 | Contador para preço progressivo. |
| Banned Until | 100025 | Suspensão temporária. |
| AFK Pause Until | 100026 | Fim da pausa ativa. |
| AFK Available At | 100027 | Cooldown da próxima pausa. |

### 7.3 Política implementada

- tempo padrão: 3 horas;
- renovação: 1 hora;
- uso mínimo antes de renovar: 15 minutos;
- preço inicial: 5.000.000;
- incremento por renovação: 5.000.000;
- pausa AFK: 5 minutos;
- cooldown da pausa AFK: 2 horas;
- multiplicadores Task de XP e loot: 20%;
- ticker de reconciliação de estado: 30 segundos.

O servidor contabiliza o intervalo final antes de desligar, força Cave Bot off ao expirar ou banir e não deixa Task contornar ban/tempo. O indicador de pausa AFK usa o ícone Dove com minutos restantes e é removido ao expirar.

A compra é permitida depois do uso mínimo de 15 minutos e sempre consome o preço informado, conforme o aviso da UI original. A hora completa só é reposta quando pelo menos uma hora já foi consumida; antes disso, a compra apenas avança o contador/preço.

### 7.4 XP, loot e reward boss

O multiplicador de XP roda depois da fórmula padrão e antes de Weapon Proficiency e da mensagem final, de forma que todos observem o mesmo valor realmente concedido.

O loot Task cobre:

- loot normal;
- Prey e Bounty;
- Soul Core e Soul Prism;
- Forge Dust e Forge Sliver;
- reward boss, incluindo item único.

Quando o multiplicador é 1, os caminhos normais preservam as chamadas RNG do servidor. Para reward boss, o multiplicador mais restritivo observado durante dano causado, dano recebido ou cura fica congelado no score. Logout, toggle de Task ou ausência do jogador no momento do payout não podem elevar uma contribuição já adquirida sob Task.

### 7.5 Bot-check e administração

O servidor só inicia bot-check em clientes Astra compatíveis. Uma sessão ativa:

- fica registrada no servidor;
- força Cave Bot off;
- rejeita tentativa posterior de reativação, inclusive por cliente modificado;
- bloqueia pausa AFK;
- é encerrada por stop, ban ou logout;
- é refletida em `botCheckActive` no estado 213, recuperando o alarme após reconnect/hot reload.

Comandos GOD criados:

```text
/minibotadmin check-start, Player Name
/minibotadmin check-stop, Player Name
/minibotadmin ban, Player Name, Minutes
/minibotadmin unban, Player Name
/minibotadmin status, Player Name
```

A TalkAction valida acesso e account type, jogador online, duração inteira de 1 minuto a 365 dias e retorna motivos objetivos.

## 8. Conflitos encontrados e soluções aplicadas

| Conflito/risco | Solução |
| --- | --- |
| O doador chamava `g_minibot`, mas não trazia a implementação | ABI reconstituída a partir de todos os chamadores e coberta por matriz de executores. |
| `game_helper` tinha hooks, eventos e timers sem hot-unload confiável | Desativação no startup; código preservado; transição exige reinício limpo. |
| Botão, hotkeys e chamadas globais ainda apontavam ao helper | Migração completa para Assistant/APIs neutras e saneamento automático de configurações antigas. |
| Dois assets referenciados não existiam nem no doador | Aliases documentados para assets reais do mesmo tema, com hashes. |
| Snapshot gráfico do doador tinha cerca de 180 MiB não usados | Somente 39 dependências comprovadas foram isoladas no namespace do MiniBot. |
| IDs de spell e clips não coincidiam | Mapa server-ID ↔ client-icon-ID construído pelo catálogo `Spells`; ida e volta testadas. |
| Página podia inicializar offline/antes de player info | Readiness explícita; página é reinicializada após `onPlayerInfo`. |
| Reconnect podia reativar um loop enfileirado antigo | Reset no logout, generation token e start somente pós-player-info. |
| Recorder, animações e reloads podiam sobreviver ao terminate | Ownership central de handles e cleanup recursivo/idempotente. |
| Explorer perdia o toggle em reload | Toggle 21 restaurado a partir dos shortcuts e reaplicado no reload. |
| Type 9 tinha colisão conceitual entre Auto Attack e ammunition | Auto Attack passou a estado próprio; módulo 9 ficou exclusivamente com refill de ammo. |
| Persistência/import aceitava árvores corrompidas ou hostis | Schema estrito, reparo seguro, limites, detecção de ciclos e rejeição antes de persistir. |
| Opcode 210 era tratado em C++ e Lua | Autoridade única em Lua; tratamento duplicado removido de `protocolgame.cpp`. |
| Bot-check podia depender da cooperação do cliente | Cave Bot é desativado e bloqueado no servidor durante a sessão. |
| Estado periódico podia reiniciar continuamente o som | Transição de `botCheckActive` é aplicada somente quando muda. |
| Saldos maiores que o inteiro seguro do JSON/Lua | Clamp server-side em `MaxSafeInteger`. |
| Reward boss podia pagar após logout/toggle fora de Task | Multiplicador mais restritivo congelado no score C++. |
| Unity build do servidor atingiu C1128/PDB concorrente | `/bigobj /FS` em todas as configurações e validação Debug x64 sem unity. |
| Páginas incompletas já ocultas na origem | Quatro stubs permanecem fora da carga; PvP foi concluído e só então exposto. |
| O Astra dispara `onClick`, mas 238 pontos do módulo doador usam `onLeftClick` | Ponte estável no Lua-base: `UIWidget:dispatchLeftClick()` encaminha o evento sem trocar dinamicamente a função `onClick`; `UICheckBox` preserva seu toggle e `UIItem` preserva o item selector antes do despacho. |
| Troca de página destruía linhas dinâmicas e depois o pai das mesmas linhas | Ownership do teardown foi centralizado: cada módulo libera estado, eventos/catchers são fechados e a árvore visual é destruída uma única vez pelo contêiner principal. |
| `Player:getVocationName()` não existe nesta base do Astra | Resolução compatível por `player:getVocation()`, `g_game.getVocationName()` quando disponível e fallback em `VocationNames`. |
| Páginas chamavam `getName()` em objetos sem esse método e `isMarketable()` em `ItemType` | Compatibilidade de nomes para `ThingType`/`Item` e normalização `ItemType` → `ThingType` antes de qualquer API de mercado. |
| A tela de hotkeys conservava `lastFocusHK` depois de destruir/recriar a linha | Verificação de widget vivo e limpeza central antes de rebuild, busca, reset, troca de perfil/chat, offline e terminate. |
| Toggle em Settings usava `displayGameMessage` com contrato incompatível | Mensagem passa a ser composta como uma única string (`<módulo> module enabled/disabled.`), compatível com `game_textmessage`. |
| Configuração de Mana Shield era ancorada a widgets internos de outra área | Painel de configuração passa a iniciar após a lista, e seu conteúdo é ancorado ao próprio contêiner. |
| Frames e conteúdos do Cave Bot apareciam cortados/sobrepostos | Recorder ancora Sessions após o mapa, limita corretamente a lista de waypoints e normaliza tabs; Explorer limita labels aos campos, usa edits numéricos e tooltips próprios. |
| `helperDialog` havia sido retirado e o estado visual podia divergir da janela | Launcher restaurado e deduplicado nas preferências; abrir, fechar, botão X e troca de side button sincronizam o toggle sem reabrir a janela. |
| `text-only-number` e navegação de `UIScrollArea` da origem não existem no host | Compatibilidade adicionada para aceitar somente dígitos nos 26 campos declarados e para Enter/Escape/Up/Down nas listas, sem duplicar o despacho de clique. |

## 9. Testes executados e resultados

### 9.1 Cliente

Os resultados de smoke e build marcados como históricos abaixo são anteriores ao diagnóstico interativo de 20/07/2026 e não foram repetidos nesta rodada. A auditoria manual do cliente Windows indicada separadamente é desta rodada; ela foi feita sobre um processo já compilado e não equivale a novo build nem ao aceite pós-reinício das últimas alterações.

| Teste | Cobertura | Resultado |
| --- | --- | --- |
| Sintaxe Lua | 27 arquivos de produção relevantes | **OK** |
| Manifesto de assets | 39 arquivos instalados e doadores, SHA-256 | **OK — 39/39, BAD=0** |
| `minibot_runtime_smoke.lua` | ABI, áreas, scheduler único, opcode 210, reset/logout/reconnect e teardown | **OK** — `minibot runtime smoke: OK` |
| `minibot_executors_smoke.lua` | Tipos 0–22, targeting, áreas, PvP, equipamentos, support, recorder, explorer e lifecycle | **OK** — `minibot executor matrix: OK (0-22, targeting, areas, recorder, explorer, lifecycle)` |
| `minibot_botcheck_smoke.lua` | Opcodes 230/213, alarme, flash, automações off, stale event, spell clips e restauração dos adapters | **OK** — `minibot bot-check smoke: OK` |
| `minibot_config_hardening_smoke.lua` | Reparos, schemas, imports válidos/inválidos, cycles, profundidade, finite numbers e não persistir antes de aceitar | **OK** — `minibot config hardening smoke: OK` |
| Build MSBuild `vc23/otclient.sln`, Debug x64 | Lua/C++ e os novos sinais de protocolo | **OK**, exit code 0 |
| Smoke dinâmico offline anterior | Startup, carga do módulo, 13 páginas então expostas, ABI, bot-check e dois ciclos terminate/init | **OK**, exit code 0; sem `ERROR`/`FATAL` do módulo |
| Smoke gráfico final pós-hardening/PvP | Fluxo sobre a revisão final | **NÃO EXECUTADO NESTA RODADA**, conforme solicitação de não iniciar o cliente |
| Sessão real reportada pelo usuário | Abertura da janela, navegação e tentativa de criar/configurar entradas | **FALHOU ANTES DAS CORREÇÕES** — ações `onLeftClick` não eram disparadas e houve avisos de double-destroy |
| Auditoria interativa atual | Navegação pelas 14 páginas ativas; layouts, listas, entradas e seletores seguros de Health, Mana, Group, Timers, Shooter, Amulets e Rings | **ZERO `ERROR` DESDE O BASELINE** — não implica que automações de combate/movimento tenham sido ativadas |
| Cave Recorder/Explorer | Inspeção visual no cliente e correção no OTUI de frames, ancoragens, tabs/lista de waypoints, labels e campos numéricos | **CORRIGIDO NO DISCO; RETESTE VISUAL PENDENTE DE REINÍCIO MANUAL** |
| Regressão final após ponte de clique, lifecycle, hotkeys e últimos ajustes visuais/API | Todas as 14 páginas e ações corrigidas | **PENDENTE DE REINÍCIO E ACEITE DO USUÁRIO** — o processo aberto ainda não carregou os últimos arquivos Lua/OTUI |

Artefato compilado do cliente:

- `D:\AstraClient\otclient_debug_x64.exe`;
- tamanho: 46.966.272 bytes;
- SHA-256: `C15398A6AE0354FD24641CBF2143FFFC86DD7C0706A8692BC974D537649B7EB0`.

Uma captura do smoke gráfico anterior mostrou a janela Assistant aberta e renderizada:

- `C:\Users\PreventWork\AppData\Roaming\AstraClient\otclientv8\1.png`;
- tamanho: 1.699.204 bytes;
- SHA-256: `688CB7D88D36D95B5DAA0E6B90433F4659591F83EE1467B04E2903F5F76E253C`.

Os avisos visuais observados foram os avisos já existentes de texturas grandes, incluindo os sprite sheets grandes do próprio MiniBot; não houve referência a imagem ausente no smoke aprovado.

### 9.2 Servidor

| Teste | Cobertura | Resultado |
| --- | --- | --- |
| Sintaxe Lua | 11 arquivos alterados/criados relevantes, incluindo a configuração isolada | **OK** |
| `minibot_server_state_smoke.lua` | State, timer, Task puro, limites JSON, opcode estrito, rate limit, AFK, check, ban e renew | **OK** — `minibot server state smoke: OK` |
| `minibot_task_rewards_smoke.lua` | Ordem XP, Weapon Proficiency, loot normal/Prey/Bounty, Soul e Forge | **OK** — `minibot task rewards smoke: OK` |
| Build MSBuild `vc18/theforgottenserver.sln`, Debug x64, unity desabilitado | Lua/C++ final, incluindo reward boss | **OK**, exit code 0 e link concluído |
| Execução `--help` | Carregamento do executável e parser CLI | **OK**, exibiu `Usage` (exit 1 esperado para essa invocação) |
| Boot completo isolado | MariaDB 11.4 descartável, schema com 56 tabelas, 2.940 scripts Lua, mapa, houses, spawns e listeners | **OK** — `SERVER ONLINE`; TCP 37171/37172/37173; shutdown gracioso por `SIGINT` |

Artefato compilado do servidor:

- `D:\forgottenserver-downgrade-1.8-8.60\theforgottenserver-x64.exe`;
- tamanho: 17.536.000 bytes;
- SHA-256: `FBA0D45CF918FF4932B37B88DE0F849AF99E406A06AFAA41228984E95B366CB3`.

### 9.3 O que os testes não afirmam

Os smokes usam doubles somente nos arquivos de teste; o código de produção não contém mocks. Eles comprovam lógica, contratos, lifecycle e erros controlados, mas não substituem um login real com latência, mapa, criaturas, inventário, banco e dados de produção.

Não foi reportado como executado nesta rodada:

- reteste final após reiniciar o cliente com as últimas correções de API, hotkeys e layout carregadas;
- ativação funcional das automações de ataque, uso de item ou movimento durante a auditoria interativa;
- build Release do cliente e do servidor;
- compilação e execução em Linux;
- soak prolongado de várias horas em servidor de jogo;
- teste econômico destrutivo em dados reais.

O boot isolado exibiu um aviso basal e não relacionado ao MiniBot: a tabela opcional `player_hirelings` não existe no `schema.sql` do próprio checkout, embora o recurso de hirelings esteja habilitado na configuração-base. O aviso não impediu o mundo de ficar online e nenhuma alteração de schema alheia ao escopo foi introduzida.

## 10. Evidências de que o bot antigo não está ativo

| Evidência | Resultado |
| --- | --- |
| `mods/game_helper/helper.otmod` | `autoload: false`. |
| `modules/game_interface/interface.otmod` | Carrega `game_minibot`; não lista mais `game_helper`. |
| Defaults de hotkey | `ShowMiniBot` em `Ctrl+H`; ações `HelperStatus/Target/Shooter` removidas. |
| Side buttons/constantes | `helperDialog` existe como botão configurável do Assistant e chama apenas `modules.game_minibot.toggle()`. |
| Battle/player death/spell list | Nenhuma chamada operacional ao helper antigo. |
| Busca fora de `mods/game_helper` | `ShowHelper` resta somente como entrada legada de migração; `helperDialog` pertence ao launcher do MiniBot. |
| Código antigo | Continua no disco, permitindo rollback; não é carregado. |

A desativação foi desenhada para startup limpo. Se uma sessão do cliente já carregou o helper antes da troca, reinicie o cliente; hot-unload do helper antigo não é considerado seguro por causa dos hooks e timers que ele próprio não controla integralmente.

## 11. Limitações e decisões deliberadas

- A fidelidade foi comparada contra OTUI/PNG do doador, capturas reais e inspeção das 14 páginas no cliente; a confirmação dos últimos ajustes visuais depende da próxima sessão após reinício.
- As quatro páginas não funcionais da origem não foram inventadas. Seus arquivos estão presentes, mas fora da carga e da navegação, exatamente como o comportamento útil do doador.
- O checkout do servidor não oferece banco, `config.lua`, conta e personagem de produção prontos. O boot foi comprovado em MariaDB descartável; gameplay e soak ainda dependem da implantação real descrita abaixo.
- `data/things/860` é grande porque contém o DAT/SPR real usado para inicializar o cliente; não é duplicado em `data/images/game_minibot`.
- A troca do bot antigo deve ser feita com reinício do cliente, não hot-unload.
- O processo do cliente usado no diagnóstico não possui hot reload do módulo. Fechar e abrir somente a janela do Assistant não carrega os últimos Lua/OTUI; é necessário reiniciar o executável, operação que o usuário fará manualmente.
- O usuário reservou para si os testes, os builds Release e a compilação Linux. Nenhum processo, Docker ou servidor foi reiniciado depois dessa orientação.
- A auditoria atual cobriu as 14 páginas sem novo `ERROR`, mas a aceitação gráfica/funcional final das correções mais recentes permanece pendente; este relatório não declara a portabilidade 100% validada em jogo antes do reteste pós-reinício.

Não há botão, aba ou opção ativa deliberadamente deixado como placeholder; o funcionamento pós-correção, porém, ainda precisa ser confirmado na nova sessão do cliente.

## 12. Validação manual em ambiente de jogo

### 12.1 Preparação

1. Faça backup dos dois repositórios, do `config.lua`, banco e diretório de configuração local do cliente.
2. Instale os scripts do servidor e o `theforgottenserver-x64.exe` compilado.
3. Confirme que o servidor carrega `data/lib/functions/astra_helper.lua`, scripts revscripts e talkactions.
4. Inicie o servidor com o banco/mundo reais e confirme ausência de erro Lua ao registrar `ExtendedOpcode`, `MiniBotStateTicker` e `/minibotadmin`.
5. Inicie o AstraClient com `data/things/860` compatível e conecte um personagem de teste.

### 12.2 Interface e persistência

1. Pressione `Ctrl+H` e confirme a janela Assistant 600 x 550.
2. Abra todas as 14 páginas ativas e confira ícones, tooltips, listas, dropdowns e estados enabled/disabled.
3. Crie um preset, renomeie, configure pelo menos uma regra em cada página, exporte e reimporte.
4. Crie uma sessão de Recorder, adicione/reordene/remova waypoints e faça round-trip de import/export.
5. Feche e reabra a janela; depois faça logout/login e confirme persistência.
6. Entre com outro personagem e confirme que seleção e opções por personagem não vazaram.
7. Ative nome de preset, timer e toggles do painel compacto; confirme sincronização de mão dupla.

### 12.3 Funcionalidades

1. Em área segura, teste Health/Mana Healing nos limites inclusivos e em falta de item/mana.
2. Teste Group Healing com alvo customizado, party, guild e filtros de vocação.
3. Teste Shooter por spell/item, target único, AoE e área direcional, incluindo cooldown/PZ.
4. Teste os modos de Auto Attack e cancelamento pela battle list.
5. Teste Timers com número de monstros abaixo, dentro e acima dos limites.
6. Teste amuletos, anéis e ammo com containers abertos/fechados e slots ocupados.
7. Teste haste, moedas, food, training, mount e os três fluxos de Mana Shield.
8. Grave uma rota curta com mudança de andar e valide pausa/retomada por monstros e erro de andar incorreto.
9. Ative Explorer e confirme que ele não roda junto com Recorder nem cria um segundo timer.

### 12.4 Integração de servidor

1. Ative Cave Bot e confirme opcode 210, storage 99997 e estado 213 coerentes.
2. Confirme timer inicial de 3 horas e consumo somente quando aplicável.
3. Depois do mínimo de 15 minutos, valide renew, débito de 5.000.000 e incremento de preço.
4. Ative Task e compare XP/loot com personagem controle; o esperado é 20%, incluindo Soul/Forge e reward boss.
5. Solicite pausa AFK e confirme 5 minutos, ícone Dove e cooldown de 2 horas.
6. Com GOD, rode `status`, `check-start` e `check-stop`; confirme alarme, flash, ataque/automação off e bloqueio de reativação.
7. Teste `ban`/`unban`, expiração e tentativa de Cave Bot por cliente modificado.
8. Envie payload 213 inválido/grande e bursts acima de oito por segundo; confirme rejeição sem disconnect.

### 12.5 Estabilidade e regressão

1. Abra/feche a janela e alterne cada função repetidamente.
2. Recarregue o módulo duas vezes e confirme um único scheduler/evento.
3. Faça logout, reconnect e troca de personagem repetidos.
4. Valide battle list, target lock, player death, spell list e movimentação entre painéis.
5. Execute soak de várias horas, acompanhando CPU, memória e logs de client/servidor.
6. Confirme que não aparecem chamadas, botões, atalhos nem opcodes originados por `game_helper`.

## 13. Rollback

### 13.1 Cliente

1. Feche completamente o cliente.
2. Restaure, a partir do commit/backup anterior, somente os 14 arquivos modificados listados na seção 3.2.
3. Remova da distribuição `modules/game_minibot`, `data/images/game_minibot`, os cinco arquivos de teste e os documentos da portabilidade, se o rollback precisar ser total.
4. Reative `game_helper` no `modules/game_interface/interface.otmod` e retire `autoload: false` apenas depois de restaurar defaults, opções, side buttons e callbacks antigos como um conjunto consistente.
5. Recompile o cliente se `src/client/protocolgameparse.cpp` tiver sido revertido.
6. O nó `Minibot_Settings` pode permanecer inerte; remova-o somente depois de exportar presets que precisem ser preservados.
7. `data/things/860` só deve ser removido se tiver sido criado exclusivamente para este cliente e houver outro DAT/SPR 8.60 validado.

Não reative apenas o OTMOD antigo sem restaurar suas integrações; isso produziria um helper parcialmente conectado.

### 13.2 Servidor

1. Pare o servidor e preserve backup de banco/configuração.
2. Restaure os 12 arquivos modificados listados na seção 3.6.
3. Remova `minibot_admin.lua`, os dois smokes e `tests/minibot_boot_config.lua` se eles não forem mais desejados.
4. Recompile o servidor para retirar as alterações de reward boss e do projeto C++.
5. Os storages 100020–100027 podem permanecer sem uso; não há migração destrutiva nem alteração de schema SQL.
6. Se for necessário limpar storages de jogadores, faça uma migração explícita e auditada no banco, nunca um update global sem backup.

Cliente e servidor devem ser revertidos juntos para evitar um cliente esperando o estado 213 de um servidor que já não o publica.

## 14. Matriz final de aceite

| Critério | Evidência/estado |
| --- | --- |
| Bot antigo desativado | Verificado por manifesto, carga, hotkeys, botões e busca de referências. |
| Páginas implementadas | 14 páginas ativas, incluindo PvP concluído; todas foram abertas na auditoria atual sem `ERROR`. Quatro stubs sem comportamento permanecem fora da carga; aceite final pós-reinício pendente. |
| Recursos gráficos | 39/39 presentes e com hash correto; 25 usos de `window_light` e 17 de `miniwindow_gray` tiveram nine-slice normalizado, com reteste visual pendente. |
| Funcionalidades do runtime | ABI 0–22 coberta por smoke de executores. |
| Persistência | Schema, reparo, round-trip e imports hostis cobertos por smoke. |
| Integração client-servidor | Contratos 210/213/230 implementados e testados isoladamente nos dois lados. |
| Lifecycle/cleanup | Cobertura offline histórica e auditoria atual sem `ERROR`; teardown de páginas e referências destruídas de hotkeys foram tratados, aguardando o reteste final em processo reiniciado. |
| Build do cliente | Debug x64 histórico aprovado; Release e Linux serão compilados pelo usuário. |
| Build do servidor | Debug x64 histórico aprovado; Release e Linux serão compilados pelo usuário. |
| Inicialização dinâmica do cliente | A sessão real percorreu as 14 páginas com zero `ERROR` desde o baseline; os últimos ajustes de API/layout estão no disco e exigem novo reinício manual porque não há hot reload. |
| Boot online do mundo | Aprovado com MariaDB/schema descartáveis; login, gameplay e soak de produção permanecem no roteiro manual. |
| Regressões observadas | Clique incompatível, launcher, vocação, `getName`, `isMarketable`, lifecycle de hotkeys, `displayGameMessage`, double-destroy e layouts Cave/Mana Shield foram diagnosticados e tratados; última validação pós-reinício pendente. |
| Caminhos absolutos em produção | Nenhum encontrado no módulo; apenas documentação/testes referenciam paths locais. |
| Código fictício | Nenhum mock/placeholder no runtime de produção; doubles restritos aos testes. |
| Origem preservada | Contagem e bytes finais iguais ao inventário inicial; assets copiados conferem com o doador. |

## 15. Artefatos de referência

- Planejamento: `D:\AstraClient\docs\MINIBOT_PORT_PLAN.md`;
- módulo: `D:\AstraClient\modules\game_minibot`;
- manifesto de assets: `D:\AstraClient\modules\game_minibot\ASSET_MANIFEST.md`;
- testes do cliente: `D:\AstraClient\tests` e `D:\AstraClient\test.lua`;
- serviço do servidor: `D:\forgottenserver-downgrade-1.8-8.60\data\lib\functions\astra_helper.lua`;
- testes do servidor: `D:\forgottenserver-downgrade-1.8-8.60\tests`;
- binário Debug histórico do cliente: SHA-256 `C15398A6AE0354FD24641CBF2143FFFC86DD7C0706A8692BC974D537649B7EB0`;
- binário Debug histórico do servidor: SHA-256 `FBA0D45CF918FF4932B37B88DE0F849AF99E406A06AFAA41228984E95B366CB3`.
