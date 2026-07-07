# Runbook de Deploy - Client 1.0.7

Passos manuais e dependencias de servidor que precisam estar prontos **ANTES** de
publicar este client. Complementa [`RELEASE_PROCESS.md`](RELEASE_PROCESS.md) (o
processo generico de build/empacotamento/publicacao).

> Contexto: esta build introduz features que dependem do servidor (crystalserver /
> data-koliseu) e do backend (koliseu-aac). Duas delas sao **bloqueantes**: a trava
> de versao no login e o byte novo de protocolo do Dummy Level. Leia a secao 1 e 2
> antes de rodar `make_release`.

---

## 1. Dependencias de servidor (crystalserver / koliseuot)

### 1.1 Dummy Level System -- CRITICO (pode dessincronizar o protocolo)
- O client passou a ler **um byte a mais** no stream de itens (o nivel do dummy),
  logo apos o byte de upgrade level, dentro do mesmo gate `isOTC` /
  `GameItemUpgradeSystem`.
- O servidor **DEVE** anexar esse byte em `ProtocolGame::AddItem()`
  (lib `data-koliseu/lib/dummy/dummy_level_lib.lua`).
- **Falha se nao fizer:** se o servidor enviar so o byte de upgrade e NAO o de
  dummy, o parsing de itens dessincroniza e corrompe a leitura dos itens
  seguintes (itens errados / crash).
- **Acao:** subir o servidor com o dummy byte **antes ou junto** deste client.
  Nao publicar este client num ambiente cujo servidor ainda nao envia o byte.

### 1.2 Addon/Mount Bonus (janela nova)
- Requer o bridge `data-koliseu/scripts/custom/addon_mount_otc_bridge.lua`
  (CommandBridge, extended opcode **211**, namespace `addonmount.*`).
- **Falha se nao fizer:** a janela abre mas fica vazia / sem acoes. Nao quebra o
  client (degrada com elegancia).

### 1.3 Auto Follow / Path Sharing (opcode 220) e Cavebot Z-Recovery (opcode 209)
- Auto Follow consome o stream de posicao do lider enviado pelo servidor (opcode
  **220**); Cavebot Z-Recovery consulta o servidor (opcode **209**).
- **Falha se nao fizer:** ambos tem fallback client-side, entao degradam em vez de
  quebrar. Recomendado ter os scripts server-side para a experiencia completa.

---

## 2. koliseu-aac (login gate + publish) -- OBRIGATORIO

A trava de versao no login e **server-authoritative** (ver `RELEASE_PROCESS.md`
secao 11). Antes de publicar, confirme no deploy alvo:
- `/api/login` valida `release_version` contra a versao publicada por ambiente
  (`client_type='otc'`, ativa).
- Endpoint `/api/client/publish` disponivel (o `-Publish` do `make_release` faz o
  upsert de `client_version`).
- `.env` do deploy: `CLIENT_ENV` (`production` | `testServer`) + `CLIENT_PUBLISH_TOKEN`.
- **ATENCAO ao 1o rollout:** clients ja distribuidos que nao mandam `release_version`
  serao **bloqueados** (fail-closed) e forcados a atualizar pelo Launcher. Testar em
  `testServer` (gameteste) antes de prod. Kill-switch: publicar versao vazia desliga
  a trava.

---

## 3. Changelog
- Colar o conteudo de [`changelog/1.0.7.md`](changelog/1.0.7.md) em koliseu-aac
  `/admin/changelog` como uma **nova entrada ativa** (version `1.0.7`).
- Uma entrada nova re-notifica todos; editar uma existente NAO re-notifica.

---

## 4. Sequencia de publicacao (resumo; detalhes em RELEASE_PROCESS.md secao 10)

1. Confirmar **1.1** (dummy byte) e **2** (aac login gate) prontos no ambiente alvo.
2. `python .\tools\gen_asset_key.py --force`
3. `.\compile.ps1 -Config DirectX`
4. `$env:KOLISEU_PUBLISH_TOKEN = "<token>"`  (= `CLIENT_PUBLISH_TOKEN` do deploy)
5. **TESTE:** `.\tools\make_release.ps1 -Env test -Encrypt -Publish`
   - bumpa `CLIENT_RELEASE_VERSION` no init.lua para `1.0.7` e publica em testServer/otc.
6. Smoke test **pelo Launcher** (testServer): login ok, assets, sem `unable to decrypt`.
7. **PROD:** `.\tools\make_release.ps1 -Env prod -Encrypt -Publish -NoBump`
   - `-NoBump` mantem a mesma versao/build do teste (senao re-bumpa para 1.0.8).
   - pede confirmacao `yes`.
8. Arquivar `keymaterial.gen.h` + `.pdb` marcados pela versao (secao 2/9 do RELEASE_PROCESS).
9. Publicar o changelog (secao 3).

---

## 5. Checklist rapido

- [ ] Servidor envia o byte de dummy level (`dummy_level_lib.lua`) no ambiente alvo.
- [ ] `addon_mount_otc_bridge.lua` (opcode 211) no servidor (opcional, mas a janela depende dele).
- [ ] koliseu-aac com `/api/login` validando `release_version` + `/api/client/publish` + `.env`.
- [ ] `KOLISEU_PUBLISH_TOKEN` setado + `gh` autenticado.
- [ ] Release de TESTE publicada e smoke-tested pelo Launcher.
- [ ] Release de PROD publicada (`-NoBump`).
- [ ] `keymaterial.gen.h` + `.pdb` arquivados por versao.
- [ ] Changelog 1.0.7 publicado no `/admin/changelog`.
