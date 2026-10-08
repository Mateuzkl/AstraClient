# Astra Web — auditoria e correcoes de seguranca

Data: 08/10/2026. Base: `042d144a708380b31172dafee2eb48f4d6a68f3b`.
Branch exclusiva: `fix/astra-web-security-hardening`. Nenhum merge automatico.

## Resumo executivo

Foram confirmados caminhos de persistencia insegura de credenciais no browser,
envio condicional por HTTP, diagnosticos que podiam incluir dados de login e
empacotamento amplo sem politica explicita de arquivos. As correcoes foram
implementadas, com testes positivos/negativos e auditoria dos bytes finais.
Nao foi demonstrada uma invasao, exfiltracao real ou vulnerabilidade P0.

O desktop continua usando suas preferencias existentes e o protocolo TCP
8.60/RSA/XTEA. As protecoes de armazenamento sao exclusivas do Web; bloqueios de
HTTP JSON confidencial tambem se aplicam ao desktop. Isso nao desabilita o bot
local: somente compartilhamento remoto plaintext deixa de ser permitido.

## Achados e decisoes

| Prioridade / estado | Evidencia e impacto | Correcao |
| --- | --- | --- |
| P1 confirmado | `entergame.lua` gravava senha/gtoken em settings persistidos por IDBFS; a codificacao recuperavel nao protegia esses segredos | Web nao lembra senha/autologin; todos os caminhos conhecidos de login/Google foram protegidos; limpeza em Lua, Config C++ e IDBFS |
| P1 condicional | Servidores de teste ativaveis por Ctrl+Alt+T enviavam JSON por HTTP | Atalho/lista inseguros retirados; politica HTTPS antes de montar/enviar o pedido; excecao loopback explicita, desligada por padrao |
| P1 condicional | Bot enviava configuracoes a servico HTTP | Upload/download inseguros bloqueados antes da leitura/compressao; configs locais preservadas; nenhum servidor alternativo foi escolhido |
| P1 confirmado no transporte | XHR/Fetch do SDK nao oferecia politica de recusa previa de redirects POST | Adaptador Fetch Web com `redirect: error`; 307/308 testados sem chegada do corpo ao destino de redirect |
| P1 lacuna de distribuicao | Preload de diretorios inteiros permitia inclusao involuntaria de novos arquivos | Lista exata de producao, staging externo e auditor do `.data`/webroot; CI falha para arquivos privados/inesperados |
| P2 confirmado | Condicao invertida de lembrar conta podia salvar identificador contra a escolha | Marcado salva formato compativel; desmarcado remove, inclusive antes de erro de login |
| P2 confirmado | Falhas de JSON/campos/URLs podiam incluir valores sensiveis em mensagens | Mensagens genericas, sem eco de corpo remoto, senha, token ou URL de credencial |
| P2 lacuna do exemplo | Nginx nao exigia Origin exato nem CSP/limites explicitos | HTTPS/WSS, Origin exato, rotas exatas, limites e CSP; isso nao prova nem altera a VPS real |
| P2 confirmado em primeira instalacao | Web Crypto recebia uma view do SharedArrayBuffer de pthreads e a geracao do UUID falhava | Entropia segura em Uint8Array nao compartilhado, copiada depois para o heap; sem fallback `math.random` |
| P2 integracao do pacote | O modulo `client` exigia autoreload de desenvolvimento mesmo quando o pacote Web o excluia | Exclusao declarada e aplicada somente no Web; a lista e comportamento nativos foram preservados |
| P2 confirmado pelo uso Web | Cam Viewer chamava `io.popen`, indisponivel em WASM | Listagem pelo filesystem virtual no browser; listagem nativa preservada, com fechamento dos pipes; listas vazias e nomes sem extensao tratados |
| Risco inerente, nao bug de sigilo | Lua/WASM/assets e manifest publico sao recuperaveis | Sem ofuscacao falsa; fontes necessarias continuam publicas; hash nao e criptografia nem assinatura independente |

## Dados e limites de confianca

| Entrada/saida | Politica |
| --- | --- |
| `config.js`, JS, WASM, `.data`, manifest | Publicos. Config pertence ao deploy, nunca a query string do visitante; nao podem conter segredos de infraestrutura |
| IndexedDB de game data | Assets publicos, formato/cache/Repair existentes preservados; nenhuma senha adicionada |
| IDBFS `/user/config.otml` | Preferencias mantidas; password, 2FA, tokens reutilizaveis, session key e autologin removidos antes de startup e antes de flush |
| Credenciais de world/reconnect | Somente RAM enquanto a sessao necessita delas; descartadas ao abrir uma nova tela de login offline |
| HTTP JSON / Google / feedback / crash / stats | TLS para dados do usuario; endpoints inseguros recusados; OAuth precisa de validacao/expiracao no backend |
| Login/jogo WebSocket | WSS de producao → bridge binaria → TCP TFS; bytes do protocolo nao viram JSON |
| Bot/terminal/codigo da propria origem | Devem ser confiaveis. Codigo hostil na mesma sessao pode ler RAM; uma lista de keys nao e sandbox para scripts maliciosos |

O adaptador POST tem limite de resposta de 16 MiB, timeout, cancelamento e entrega
unica. Remove ownership antes do callback, copia buffers antes da liberacao e
ignora resultados tardios apos cancel/terminate. Downloads/preload grandes mantem
os limites existentes. A migracao de IDBFS aguarda a gravacao da limpeza antes de
liberar a inicializacao; erro de storage nao reimporta silenciosamente segredos.

## Pacote publico: antes/depois e prova

Referencia local anterior: 5.053 arquivos, 632.153.900 bytes. Era um bundle
preexistente, nao um A/B limpo de startup da mesma main; nao serve para alegar
ganho de FPS, CPU ou tempo de carregamento.

Build auditado desta branch: 5.036 arquivos, 631.741.119 bytes (602,48 MiB).
O `Tibia.spr` selecionado sozinho tem 453.563.543 bytes; foi preservado.

A lista tem 5.033 entradas fixas, mais DAT/SPR/OTFI presentes do pack 8.60.
Tibia.otml e opcional, explicitamente permitido. Nenhum pack nao selecionado entra.
Foram excluidos do Web PSD, Markdown/diagramas, editor OTUI e autoreload de
desenvolvimento. As animacoes ranked sem uso e o splash exclusivo nativo continuam
excluidos. Terminal, diagnosticos, bot, layouts e recursos dinamicos usados foram
mantidos. Nenhum desses arquivos foi apagado do desktop.

`dist/browser-bundle-audit.json` registra somente nomes, tamanhos e SHA-256.
O auditor le o indice real do SDK, confere offsets contiguos, bytes totais,
duplicatas, nomes, lista permitida e hashes de cada arquivo contra a origem.
`init.lua` e `modules/client_entergame/entergame.lua` sao exemplos recuperaveis com
hash igual ao original; `modules/dev_otui/dev_otui.lua` nao consta no pacote.
Tambem rejeita arquivos extras na raiz publica e segredos provaveis em OTUI,
OTMOD, OTML, Lua, JS e demais formatos textuais. Valores encontrados nunca sao
impressos. O scanner desta arvore nao encontrou segredos pelos padroes verificados;
isso e uma verificacao heuristica, nao uma prova universal de ausencia de segredo.

O staging nao regrava os arquivos de dependencias/resposta quando seu conteudo
nao mudou, evitando reconfiguracoes CMake desnecessarias. Um teste confere a
preservacao de mtime; nao se trata de um benchmark de startup do jogo.

## Validacao executada

- Windows DirectX x64/MSVC: build completo e incremental aprovados.
- WASM Release, SDK Emscripten 6.0.8: build e auditoria final aprovados; permanece
  o aviso do SDK de pacote grande e `pthread + ALLOW_MEMORY_GROWTH`.
- Suite Node com Nginx habilitado: 70 testes aprovados, zero falhas/skips, incluindo
  as duas regressoes do provedor UUID com heap compartilhado.
- Testes Lua: politica real de login, marcado/desmarcado, erro, Google, init Web
  e nativo, autologin, bot inseguro e erros JSON; lifecycle startup/modulos e
  gravacao automatica local do bot aprovados. Limpeza de RAM offline/show/terminate
  tambem verificada, preservando sessao online, login em curso e comportamento nativo.
- Cam Viewer: caminho Web sem shell, lista vazia, arquivos/subpastas, recarga sem
  duplicacao e fechamento dos pipes Windows/Linux aprovados pelo codigo Lua real.
  O botao de gravacoes foi acionado no Chromium com o pacote final: a janela abriu
  sem erro `popen`; o startup tambem nao registrou mais a dependencia de autoreload.
- Assets: 931 arquivos textuais / 4.397 referencias com UTF-8/case corretos;
  testes de texto e manifest: 4 + 2 aprovados.
- SDK: RSA, UUID, politica de Config, WebSocket teardown/reuso de handle, Fetch
  com SAFE_HEAP, hotkeys e timer independente da pthread aprovados.
- ASan/UBSan: fila concorrente e parser Lua, incluindo 6.000 falhas de sintaxe
  com limpeza completa do allocator, aprovados.
- Rede Windows: HTTP/TLS/WSS, redirects POST 301/302/303/307/308 recusados,
  certificados validos/nao confiaveis/host incorreto/expirados, fragmentos/limites/
  backpressure/cancelamento aprovados. Em 200 ciclos, handles estabilizaram em
  141 e private bytes ficaram aproximadamente em 1,7 MiB. Nao e teste do jogo inteiro.
- Nginx 1.24 real: `nginx -t`, TLS, HTTP→HTTPS, Origin permitido/ausente/errado/
  spoofed, rotas login/game e bytes binarios intactos, CSP/isolation/MIME e 404
  para arquivos privados/subrotas aprovados. CA ficticia confiada apenas no teste;
  nenhum trust store do SO foi alterado.
- Chromium real: launcher e tela de login do motor abriram sob a CSP de producao.
  POST legitimo e recusas de 307/308 aprovados pelo caminho real
  Lua → C++ → browser Fetch → dispatcher → Lua; a fixture adicional confirmou
  zero corpos recebidos pelo destino do redirect e zero operacoes pendentes.
  Config C++ recusou gravacao de senha; os controles de lembrar senha/autologin
  estavam desabilitados. A verificacao pela skill computer-use encontrou a
  falha de UUID com heap compartilhado, corrigida e retestada, nao apenas simulada.

Os comandos reproduziveis estao em `astra-web-security-deployment.md`.
Testes automatizados de Install/Update/Repair/cache miss-hit/falhas e bfcache foram
mantidos. Nao foi executado Valgrind do jogo inteiro nem certificada ausencia
global de leaks/UAF. Testes do motor completo em Firefox, Android e Linux desktop
nao foram executados nesta maquina.

## Pendencias operacionais e riscos residuais

Aplicar o checklist de `astra-web-security-deployment.md` antes de publicar:
dominio/certificado/renovacao, DNS, root limpa, rotas WSS e overrides corretos,
Origin exato, CSP/CORS para APIs verificadas, limites ajustados a NAT, firewall,
bridges privadas, limites de frames/filas e logs sem corpos/tokens. Validar o
login real, logout/reconnect e browsers na VPS. Nao houve acesso nem pentest da VPS.

O TFS nao estava disponivel nas primeiras verificacoes e depois passou a escutar
nas portas locais 7171/7172. Entrada no mundo, logout e reconnect completos
com uma bridge configurada para esse servidor continuam pendentes;
as fixtures de transporte nao substituem esses cenarios. A consulta
HTTPS ao servico original de compartilhamento do bot validou TLS, mas retornou
502: nao foi comprovada uma API funcional, nem enviado qualquer arquivo do usuario.

O armazenamento legado de senha do desktop nao foi redesenhado: a sua codificacao
recuperavel continua um risco local e exige trabalho separado com armazenamento
seguro do SO/migracao. Nao foi apresentado XOR/Base64 como protecao segura.
Credenciais em RAM do browser nao podem ser tornadas invisiveis ao dono do browser
ou a codigo hostil da mesma origem. Segredos anteriormente publicados no GitHub
exigiriam revogacao/rotacao, nao apenas retirada do pacote. Hash/Repair nao protegem
contra um invasor que controla simultaneamente a origem e o manifest.
