# Plano - Popups e Idioma (Helper)

## Objetivo
- Garantir que, no **helper**, qualquer popup/janela de confirmacao/selecao/configuracao esconda a janela principal (`helperWindow`) enquanto estiver aberto.
- Ao fechar popup por `Esc`, `Confirmar`, `Selecionar`, `Cancelar` (ou `X`), voltar para a janela principal correta.
- Criar opcao de idioma **PT-BR / EN** selecionavel, alterando textos/tooltips/mensagens **somente no helper**.

## O que foi entendido
- Escopo e somente `modules/game_helper` (helper e sub-UIs dele).
- Nao pode afetar idioma do cliente inteiro.
- A UX desejada e modal: foco total no popup aberto, sem `helperWindow` visivel por tras.
- Pedido atual e **planejamento apenas** (sem alterar codigo neste momento).

## Estado atual mapeado
- Ja existe comportamento parcial de `helper:hide()/helper:show()` em alguns fluxos (ex.: seletores de spell e alguns pickers), mas nao e consistente.
- Varias janelas/popup sao abertas sem esconder helper (ex.: `openHealingSettingsPopup`, `openShooterSettingsPopup`, `openTimerSettingsPopup`, `openEquipmentSettingsPopup`, janelas do `hunting_recorder`).
- Ha muitos fluxos de popup aninhado (popup dentro de popup), ex.: equipment -> assign item.
- O modulo global de locale (`modules/client_locales/locales.lua`) esta forcando `en`; entao nao da para depender de locale global para ter PT-BR so no helper.

## Direcao tecnica recomendada

### 1) Modal manager unico para o helper
Criar um gerenciador central de modais no `game_helper` para padronizar open/close.

API sugerida:
- `modules.game_helper.modalEnter(window, opts)`
- `modules.game_helper.modalExit(window, reason)`
- `modules.game_helper.withModal(openFn, opts)` (wrapper opcional)

Estado interno sugerido:
- `modalStack` (pilha de janelas modais abertas)
- Cada item: `{ window, restoreHelper, helperWasVisible, parentWindow, lockInput }`

Regras:
- Ao abrir modal:
  - Se helper estava visivel, esconder helper.
  - Aplicar input lock (`safeSetInputLockWidget(window)`) quando fizer sentido.
  - Registrar `onDestroy` (obrigatorio) para sempre limpar estado.
- Ao fechar modal:
  - Tirar da pilha.
  - Se houver modal anterior na pilha, reexibir/focar esse modal anterior.
  - Se nao houver modal restante e `helperWasVisible == true`, reabrir helper (mesma aba/posicao).

Beneficio:
- Evita buracos de fluxo (janela fica escondida para sempre, ou reaparece errado).
- Resolve comportamento de `Esc`, `Cancelar`, `Confirmar`, `Selecionar` via fechamento unificado.

### 2) I18N local do helper (sem depender do locale global)
Criar camada de traducao propria do helper.

Estrutura sugerida:
- Novo arquivo: `modules/game_helper/helper_i18n.lua`
- Config persistida: `helperConfig.helperLanguage = "en" | "ptbr"`
- Funcoes:
  - `modules.game_helper.htr(keyOrText, ...)`
  - `modules.game_helper.applyTranslationsToWidgetTree(rootWidget)`
  - `modules.game_helper.setHelperLanguage(lang)`

Abordagem recomendada:
- Manter idioma padrao `en`.
- Traduzir no helper por dicionario local (EN -> PTBR), com fallback para EN.
- Aplicar traducao em:
  - Textos estaticos de OTUI (percorrendo arvore de widgets apos abrir janela).
  - Textos dinamicos em Lua (`setText`, `setTooltip`, mensagens `displayGameMessage/displayFailureMessage`).

Observacao importante:
- Como existe muito texto legacy hardcoded, sera necessario fasear cobertura para evitar regressao.

## Plano de implementacao por fases

### Fase 1 - Infra modal
- Implementar modal manager base no `helper.lua`.
- Integrar nos pontos principais de abertura/fechamento:
  - `openHealingSettingsPopup`
  - `openShooterSettingsPopup`
  - `openTimerSettingsPopup`
  - `openEquipmentSettingsPopup`
  - `openAssignItemIdWindow`
  - `openAssignItemListWindow`
  - janelas de `hunting_recorder` (edit session, cavebot settings, supplies, lure, cavebots manager, goto/check supply e janelas `MainWindow` fallback).
- Garantir que fechamento por `onDestroy` sempre restaure estado.

### Fase 2 - Fluxos aninhados e selecao por mouse
- Tratar casos em cascata (popup filho volta para popup pai, nao para helper direto).
- Tratar fluxo de selecao com `mouseGrabberWidget` (target cursor), incluindo cancelamento.
- Definir regra para `HelperPopupMenu`:
  - recomendacao: nao tratar como modal de tela cheia (menu contextual rapido).

### Fase 3 - Infra i18n helper-only
- Criar `helper_i18n.lua` e persistencia `helperLanguage` no `config.json`.
- Adicionar seletor de idioma na aba Settings do helper (PT-BR / EN).
- Ao trocar idioma:
  - salvar config
  - reaplicar textos na janela helper e popups abertos.

### Fase 4 - Cobertura de textos
- Migrar textos nao traduzidos em OTUI/Lua do helper para chave traducivel.
- Padronizar mensagens de erro/feedback do helper para passar por `htr`.
- Cobrir tooltips do helper (incluindo os que hoje estao em `tooltip:` sem `tr`).

### Fase 5 - Validacao
- Teste manual dos fluxos principais:
  - abrir popup -> helper some
  - fechar popup (Esc/Cancel/OK/Save/X) -> retorno correto
  - popup dentro de popup -> retorno para pai
  - trocar idioma com janelas abertas
  - relog/restart preservando idioma helper

## Arquivos que devem ser tocados na implementacao (futura)
- `modules/game_helper/helper.lua`
- `modules/game_helper/hunting_recorder.lua`
- `modules/game_helper/styles/helper.otui` (combo de idioma)
- `modules/game_helper/assign_item_id.otui` (se ajuste de texto)
- `modules/game_helper/assign_item_list.otui` (se ajuste de texto)
- `modules/game_helper/custom_spell.otui` (se ajuste de texto)
- `modules/game_helper/styles/*.otui` (apenas helper)
- Novo: `modules/game_helper/helper_i18n.lua`

## Criterios de aceite
- Nenhum popup alvo deixa `helperWindow` visivel enquanto aberto.
- Fechamento de popup sempre retorna para estado correto (pai ou helper).
- Idioma do helper alterna entre EN/PT-BR sem alterar idioma global do cliente.
- Textos/tooltips/mensagens do helper seguem idioma selecionado.
- Estado persiste apos reiniciar cliente.

## Riscos e mitigacoes
- Risco: fluxo modal quebrar em popups aninhados.
  - Mitigacao: pilha modal + fechamento central em `onDestroy`.
- Risco: traducao parcial (muitos textos legacy).
  - Mitigacao: checklist de cobertura por arquivo + faseamento.
- Risco: impacto em UI nao-helper.
  - Mitigacao: manter funcoes e dicionario restritos a `modules/game_helper`.
