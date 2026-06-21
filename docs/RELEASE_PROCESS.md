# Processo de Release — KoliseuClient (Test e Prod)

Documento autoritativo para gerar e publicar o client **OTC** (KoliseuClient) nos
ambientes de **teste** e **produção**. Cobre build, criptografia, empacotamento por
ambiente e publicação pelo Launcher.

---

## 1. Visão geral

- **Um binário, dois ambientes.** O `KoliseuClient.exe` é o mesmo; o que muda por ambiente é
  o **config** (URLs do server) e o **canal de publicação**. O `DEVELOPERMODE` é desligado
  automaticamente no empacotamento de release.
- **Distribuição pelo Launcher externo** (`KoliseuOT-Launcher`). O player nunca baixa o zip à
  mão: o Launcher instala/atualiza por canal (`testServer/otc` ou `production/otc`) e lança o
  client. O botão "Change Client" da tela de login está escondido (o Launcher sempre aparece
  antes do client).
- **O que difere test × prod:**

  | | Teste | Produção |
  |---|---|---|
  | Config | `config.test.lua` → `gameteste.koliseuot.com.br` | `config.prod.lua` → host de prod |
  | Comando | `make_release.ps1 -Env test -Encrypt` | `make_release.ps1 -Env prod -Encrypt` |
  | Canal no `/admin/client` | `testServer` / `otc` | `production` / `otc` |
  | Tabela de versão | `client_version` test/otc | `client_version` prod/otc |

- **O que NÃO muda:** o exe, o `init.lua` (compartilhado; `DEVELOPERMODE` é trocado no build),
  o esquema de criptografia e a assinatura de protocolo.

---

## 2. Pré-requisitos (uma vez)

- Build DirectX funcionando: `.\compile.ps1 -Config DirectX`.
- Python no PATH (para gerar a chave e, opcionalmente, o `update.json`).
- Os assets 15.24 em `data/things/1524/` (gitignored; user-supplied).
- `config.test.lua` na raiz (já existe). `config.prod.lua` na raiz (criar — ver §3).

---

## 3. Configs por ambiente

Cada ambiente tem um `config.<env>.lua` na raiz do repo. Ele é **empacotado cifrado como
`/config.lua` dentro do `data.zip`** (NÃO fica solto ao lado do exe — ver §8). Só contém
endpoints públicos (sem `AUTO_LOGIN`, sem localhost), então é seguro versionar no git.

`config.test.lua` (existe) aponta para `https://gameteste.koliseuot.com.br`.

`config.prod.lua` (criar, espelhando o de teste com o host de produção):

```lua
local HOST = "https://<HOST-DE-PRODUCAO>"   -- ex.: https://game.koliseuot.com.br

return {
  Services = {
    website          = HOST,
    updater          = "",                       -- versão é gerida pelo Launcher
    stats            = "",
    crash            = HOST .. "/api/client/crash",
    feedback         = "",
    status           = { HOST .. "/api/status" },  -- LISTA de urls
    createAccount    = HOST .. "/account/register",
    recoveryPassword = HOST .. "/account/recover",
    Coins            = HOST .. "/donate",
  },
  Servers = {
    Koliseu = {
      name               = "Koliseu",
      loginLink          = HOST .. "/api/login",
      clientServicesLink = HOST .. "/api/status",
    },
  },
}
```

> O `-Env` também aceita um `init.<env>.lua` opcional (se existir, é usado no lugar do
> `init.lua` compartilhado). Normalmente NÃO é preciso — o env vive no config.

---

## 4. Procedimento de release (passo a passo)

A sequência é idêntica para os dois ambientes; muda só o `-Env`.

### 1. Gerar a chave de criptografia desta release
```powershell
python .\tools\gen_asset_key.py --force
```
Gera `src/framework/core/keymaterial.gen.h` (gitignored). **Uma chave nova por release** — se
um build vazar, só aquela versão fica exposta.

### 2. Rebuild (a chave precisa estar compilada no exe)
```powershell
.\compile.ps1 -Config DirectX
```
> **Arquive `keymaterial.gen.h` + o `.pdb`** deste build num cofre privado, marcados pela
> versão. Sem eles você não decifra/symboliza essa release depois.

### 3. Empacotar
```powershell
# Teste
.\tools\make_release.ps1 -Env test -Encrypt

# Produção
.\tools\make_release.ps1 -Env prod -Encrypt
```
Saída em `release\`: `KoliseuClient.exe` + 4 DLLs + `data.zip` (init.lua + config.lua +
modules + mods + data, `DEVELOPERMODE=false`, cada arquivo cifrado per-file).

> Flags úteis: `-SkipBuild` (remontar sem recompilar) · `-Container` (camada opaca extra, mais
> RAM no boot, ver §6) · `-ConfigFile <arquivo>` (sobrescreve o do `-Env`).

### 4. Smoke test
Idealmente **pelo Launcher** (fluxo real), não só rodando a pasta `release\`. No
`KoliseuClient.log` confira:
- `Active login endpoint: https://<host do ambiente>/api/login` (o host certo!)
- sem `unable to decrypt file`, sem `Exiting application`, assets carregam
- sem terminal PumpkinBot / Draw / Debug / "Debug Info"

### 5. Publicar no Launcher
1. Zipe o conteúdo de `release\` (exe + DLLs + data.zip — o config já está no data.zip).
2. Suba em `koliseu-aac` → `/admin/client`, selecionando o ambiente (`testServer` ou
   `production`) e `otc`.
3. Faça o **bump da versão** na tabela `client_version` (env/otc) batendo com o upload.
4. O Launcher (aba do ambiente + toggle **OTC**) baixa/atualiza e lança `KoliseuClient.exe`.
   Ele seta `KOLISEU_CLIENT_VERSION` + `KOLISEU_CLIENT_ENV` ao lançar; o `entergame.lua` usa
   isso pro gate de versão no login.

---

## 5. O que o `make_release.ps1` faz (referência)

Tudo numa **cópia** em `release\_stage` — a árvore de dev nunca é tocada:
1. Copia `init.lua` (ou `init.<env>.lua`), `modules`, `mods`, `data`.
2. Troca `DEVELOPERMODE = true → false` no `init.lua` empacotado.
3. Empacota `config.<env>.lua` como `/config.lua` dentro do stage.
4. Com `-Encrypt`: roda `KoliseuClient.exe --encrypt --quiet` (per-file, in place).
5. Zipa em `data.zip`. Com `-Container`: também `--pack` (blob opaco AES-GCM).
6. Copia exe + 4 DLLs para `release\`.

---

## 6. Criptografia

- **Per-file** (`-Encrypt`, padrão): cada arquivo (init.lua, config.lua, modules, mods, data)
  vira bytecode/AES-GCM. O `data.zip` continua um ZIP normal (nomes de pasta visíveis), mas o
  **conteúdo** de cada arquivo é ilegível.
- **Container** (`-Encrypt -Container`, opcional): cifra o `data.zip` inteiro num blob opaco
  (sem `PK`, não abre em 7-Zip). Mais pesado (o zip inteiro é decifrado pra RAM no boot) e
  incompatível com o updater in-client. Off por padrão.
- **Chave**: derivada por HKDF do `keymaterial.gen.h` (gitignored, **uma por release**).
- **`config.lua` é cifrado junto** (como source, igual init.lua). Ele NÃO pode ficar em texto
  puro dentro do zip — ver §8.

---

## 7. `DEVELOPERMODE` (o que some no release)

O `make_release` desliga `DEVELOPERMODE`, escondendo (todos gateados por essa flag, exceto o
terminal que ganhou gate próprio):
- Terminal **PumpkinBot** (Ctrl+T não vinculado, janela escondida)
- Overlay **Draw / Debug** (canto inferior direito)
- Botão **"Debug Info"** + profiler dumps
- Ferramenta de **offset** e o reload de módulos (Ctrl+R)

Nenhum afeta gameplay.

---

## 8. Notas técnicas / gotchas

- **`config.lua` vai DENTRO do `data.zip`, cifrado.** Dois motivos: (1) no modo data.zip o
  client só mantém montados o write dir (`%APPDATA%\KoliseuClient\KoliseuClient\`) + o archive
  em memória — um config solto ao lado do exe **nunca é lido**; (2) em texto puro daria
  `unable to decrypt file: config.lua` assim que `m_customEncryption` liga (no primeiro decrypt
  bem-sucedido, todo arquivo não-cifrado vira fatal). Override avançado do operador: dropar um
  `config.lua` (também cifrado) no write dir, que tem precedência.
- **Loaders de asset leem via PHYSFS + decrypt**, não `std::ifstream` (thingtypemanager /
  spritesheetloader / appearancesloader / creatures / spritemanager). É o que permite
  catalog/appearances/sprites/staticdata carregarem de um `data.zip` cifrado em memória.
- **Ordem crítica**: chave (passo 1) ANTES do rebuild (passo 2). Encrypt/pack usam a chave
  compilada no exe; se não baterem, o client não decifra e não boota.
- **Custo de RAM**: o `data.zip` inteiro (~460MB) é lido pra RAM e montado da memória — inerente
  ao modo data.zip (o `-Container` só adiciona o decrypt do blob).
- **Updater in-client desligado** (`Services.updater = ""`): quem versiona é o Launcher.
- **Botão "Change Client"** da tela de login está escondido (`visible: false`) — o Launcher já
  aparece antes do client. A função `openLauncher()` segue viva para o gate de versão.

---

## 9. Checklist de pré-publicação (beta/comunidade)

- [ ] `keymaterial.gen.h` + `.pdb` arquivados, marcados pela versão.
- [ ] `config.<env>.lua` com o host certo (confirme no log: `Active login endpoint`).
- [ ] Smoke test **pelo Launcher**, numa máquina limpa se possível.
- [ ] Bump de `client_version` (env/otc) batendo com o upload.
- [ ] Endpoints do host existem (`/api/login`, `/api/status`, `/api/client/crash`).
- [ ] **SmartScreen/AV**: exe não-assinado + assets cifrados disparam aviso do Windows e
      falso-positivo de AV. Assine o exe (code-signing) ou documente no anúncio como liberar.
- [ ] Considere carimbar o commit/rev no build (hoje sai `rev 0 (dev)`) para correlacionar
      reportes de bug/crash.

---

## 10. Resumo rápido (cola)

```powershell
# === RELEASE DE TESTE ===
python .\tools\gen_asset_key.py --force
.\compile.ps1 -Config DirectX
.\tools\make_release.ps1 -Env test -Encrypt
#   -> arquivar keymaterial.gen.h + .pdb; smoke test; subir em /admin/client (testServer/otc) + bump versão

# === RELEASE DE PRODUÇÃO ===   (precisa config.prod.lua com o host real)
python .\tools\gen_asset_key.py --force
.\compile.ps1 -Config DirectX
.\tools\make_release.ps1 -Env prod -Encrypt
#   -> arquivar keymaterial.gen.h + .pdb; smoke test; subir em /admin/client (production/otc) + bump versão
```
