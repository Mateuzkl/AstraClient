# Astra Web: seguranca e deploy

## Politica de producao

- Servir o launcher por HTTPS com certificado valido. HTTP e WS sao permitidos
  pelo runtime somente em loopback; um site remoto HTTP nao pode iniciar o client.
- Usar WSS para login e jogo: navegador → WebSocket binario → bridge TCP → TFS.
  Nao ha conversao do protocolo 8.60 para JSON.
- Senha, 2FA, tokens Google e session keys nao sao lembrados no Web. A migracao
  limpa chaves antigas de `config.otml` antes do inicio e sincroniza IDBFS.
  Conta pode ser lembrada por escolha do jogador; hotkeys, minimapa e quickloot
  sao mantidos. Credenciais de world/reconnect permanecem apenas na RAM da sessao.
- POST Web usa Fetch com `redirect: error`, sem cookies automaticos, sem referrer
  e sem cache. Respostas POST sao limitadas a 16 MiB para evitar copias de corpos
  excessivos no heap; downloads GET/preload mantem seus limites existentes.
  Configure a URL HTTPS final, nao uma URL que redireciona.
- `ASTRA_ALLOW_LOCAL_HTTP_LOGIN = false` em `init.lua` e o padrao. Somente testes
  locais podem usar `true`: permite HTTP JSON em localhost/127.0.0.1/::1, nunca remoto.
  O login TCP/RSA e preferencias de senha do desktop nao foram redesenhados.
- Os servidores HTTP de teste/atalho foram retirados. Compartilhamento remoto do
  bot permanece desabilitado enquanto a URL configurada nao for HTTPS; o bot local
  permanece disponivel. Feedback, crash e estatisticas tambem exigem HTTPS.

## Pacote publico

`browser/production-assets.json` lista cada arquivo publicado no `.data`. Novos
arquivos exigem inclusao explicita. O build prepara staging fora da origem;
`tools/browser_bundle.cjs` verifica caminhos, segredos provaveis, bytes, offsets e
hashes contra as fontes e gera `dist/browser-bundle-audit.json`.

O editor OTUI/autoreload de desenvolvimento, PSD, documentos, backups e arquivos
privados nao entram no preload. Terminal, bot, diagnosticos, layouts e recursos
dinamicos usados continuam incluidos. Nao publicar o repositorio inteiro como
raiz HTTP: copiar somente o `dist` validado, para um diretorio limpo de deploy.
Nunca colocar chaves privadas, dumps, `.env`, config.otml de jogadores ou segredos
de infraestrutura em `dist`, `config.js` ou nos artefatos do CI.

Lua, WASM e assets enviados ao navegador continuam recuperaveis. Hashes verificam
consistencia/integridade, nao sigilo nem autenticidade contra comprometimento da
origem. Nao foi adicionado XOR/Base64 como protecao de senha no Web.

## Checklist da VPS

1. Escolher o dominio e obter certificado valido; substituir `play.example.com`,
   root, certificados e upstreams em `browser/nginx.conf.example`.
2. Incluir o exemplo dentro de `http {}`. Executar `nginx -t` antes de recarregar.
   HTTP/2 e opcional; `http2 on` exige nginx 1.25.1+.
3. Expor apenas HTTPS/WSS publicamente para o Web. Bridges escutam em loopback
   ou rede privada: game → TCP 7172; login → TCP 7171 (ajustar ao TFS real).
   Nao fechar as portas TCP que o client desktop ja usa.
4. Configurar os overrides em `dist/config.js` usando `/login` e `/game`. Chaves
   devem corresponder ao host/porta de init.lua e ao host anunciado pelo TFS.
   Query parameters nao podem configurar destinos de credenciais.
5. Ajustar a origem permitida **exata**: esquema HTTPS, host e porta. Bloquear
   origens diferentes/ausentes. Origin e uma barreira contra outros sites, nao
   autentica usuarios e pode ser falsificado por clientes nao-browser.
6. Ajustar rate/connections conforme NAT e capacidade. Nginx limita handshakes,
   conexoes e corpos HTTP; **nao** limita payloads apos Upgrade. A bridge deve ter
   limites de frames/filas, backpressure e timeouts e nunca registrar payloads.
7. Manter CSP, COOP, COEP, CORP, MIME Wasm e nosniff. Se login Google/API/updater
   usar outro dominio, adicionar apenas os destinos HTTPS/WSS verificados em
   `connect-src`; o backend deve permitir CORS para a origem exata do jogo.
   `style-src-attr` permite os estilos dinamicos do canvas; scripts inline/eval
   JS nao sao autorizados. Workers blob e `wasm-unsafe-eval` sao necessarios.
8. Nao registrar corpos, Authorization ou query strings de OAuth/login. O exemplo
   desliga access log; configure logs operacionais redigidos se forem necessarios.
   HSTS so deve ser ligado depois de validar TLS e o alcance de subdominios.
9. O backend de OAuth deve validar, expirar e consumir o state uma unica vez;
   session keys devem expirar e ser revogaveis. Isso nao pode ser garantido pelo client.
10. Validar Chrome/Firefox, Install/Play/Repair/Update, refresh, logout/reconnect,
    mouse/hotkeys, login real e origem proibida na VPS antes de publicar a versao.

## Testes reproduziveis

```sh
node --test browser/tests/*.test.cjs
luajit .github/tests/web_credentials.lua
luajit .github/tests/camviewer_files.lua
node tools/browser_bundle.cjs scan .
node tools/browser_bundle.cjs audit . browser/production-assets.json build-wasm-release/dist data/things/860
ASTRA_NGINX=nginx ASTRA_WEB_DIST="$PWD/build-wasm-release/dist" node --test browser/tests/nginx.test.cjs
# Com Emscripten 6.0.8 ativado e build preparado:
bash browser/tests/run-security.sh build-wasm-release/_deps/lua51_source-src/src
```

Os testes Nginx usam TLS local com CA explicita no processo de teste, nao alteram
o trust store do SO e nao acessam a VPS. ASan/UBSan cobrem parser/fila; SAFE_HEAP
cobre a fixture Fetch. Isso nao certifica ausencia de leaks/UAF em todo o jogo.
Scripts de bot instalados pelo jogador e a propria origem Web precisam ser
confiaveis: codigo hostil executado na mesma sessao pode acessar dados em RAM.
