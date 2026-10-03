# Compilar e testar o AstraClient no navegador

O navegador executa **WebAssembly**, não o `.exe` produzido pelo Visual Studio.
O build nativo e o build do navegador são diferentes.

## Portas: site, ponte e TFS

| Serviço | Porta usada neste teste |
| --- | --- |
| Site HTTP | 8814 (pode ser 8080) |
| Ponte WebSocket de login | 8815 |
| Ponte WebSocket do jogo | 8817 |
| TFS TCP de login | 7171 |
| TFS TCP do jogo | 7172 |

`localhost:8080` na imagem é apenas a porta do site. Isso não significa que o
TFS use 8080. `localhost` e `127.0.0.1` apontam para a máquina local; escolha
um endereço e mantenha-o, pois cada origem tem seu próprio armazenamento.

Não abra o HTML com duplo clique (`file://`). Use `browser/serve.py`, que envia
os cabeçalhos necessários aos threads do WebAssembly.

## Ambiente WSL (Ubuntu-24.04)

No PowerShell, abra o WSL com `wsl -d Ubuntu-24.04`. Nos comandos Bash abaixo,
substitua o caminho do repositório e escolha sua pasta de trabalho:

```bash
export ASTRA_REPO='/mnt/c/path/to/AstraClient'
export ASTRA_WASM_ROOT="$HOME/astra-wasm"
cd "$ASTRA_REPO"
source "$ASTRA_WASM_ROOT/emsdk/emsdk_env.sh"
```

Use Emscripten 6.0.8 (instalação no guia geral). Extraia o pack para
`$ASTRA_WASM_ROOT/assets/860`, sem sobrescrever o DAT/SPR personalizado.
Para configurar e compilar do início:

```bash
bash browser/build-wasm.sh Release "$ASTRA_WASM_ROOT/build-release" \
  -DASTRA_WASM_THINGS_DIR="$ASTRA_WASM_ROOT/assets/860"
```

Para apenas recompilar código alterado, no mesmo terminal WSL:

```bash
cmake --build "$ASTRA_WASM_ROOT/build-release" --parallel 6
```

Uma configuração completa pode repor o `config.js` padrão. Confira a
configuração local abaixo **depois** de configurar/compilar.

## Configurar as duas pontes

Edite o arquivo gerado, fora da branch:

```text
$ASTRA_WASM_ROOT/build-release/dist/config.js
```

Use:

Esses endpoints `ws://` são somente para testes HTTP locais. Em produção,
sirva o site por HTTPS e use `wss://`.

```js
window.ASTRA_CONFIG = {
  websocketOverrides: {
    '127.0.0.1:7171': 'ws://127.0.0.1:8815/',
    '127.0.0.1:7172': 'ws://127.0.0.1:8817/'
  }
};
```

Os nomes à esquerda precisam coincidir com o login configurado em `init.lua`
e com o IP/porta do mundo anunciado pelo TFS. Não coloque senha nesse arquivo.
Não configure destinos de credenciais por parâmetros da URL.

Deixe o TFS aberto. No modo NAT do WSL, `127.0.0.1` dentro do Linux não é o
Windows. Confira o gateway com:

```powershell
wsl -d Ubuntu-24.04 -- ip route show default
```

Substitua `<GATEWAY_WSL>` pelo gateway exibido no comando anterior, nos dois
comandos seguintes. O TFS precisa ouvir em uma interface
acessível ao WSL; não desative o firewall para contornar problemas de acesso.

Abra **três terminais**, mantendo os processos abertos:

Terminal 1 — ponte do login:

```powershell
wsl -d Ubuntu-24.04 -- websockify 127.0.0.1:8815 <GATEWAY_WSL>:7171
```

Terminal 2 — ponte do jogo:

```powershell
wsl -d Ubuntu-24.04 -- websockify 127.0.0.1:8817 <GATEWAY_WSL>:7172
```

Terminal 3 — site:

No WSL, com as variáveis do início do guia:

```bash
cd "$ASTRA_REPO"
python3 browser/serve.py "$ASTRA_WASM_ROOT/build-release/dist" --port 8080
```

Abra **http://127.0.0.1:8080/astraclient.html** no navegador. Para usar a porta
8814, troque somente `--port 8080` por `--port 8814` e use essa porta na URL.
Não é necessário recompilar para mudar a porta HTTP ou o `config.js`.

Se a porta estiver ocupada por um teste já aberto, use-o ou encerre apenas
o terminal desse teste com Ctrl+C antes de iniciar outro processo na mesma porta.

## Conferir o resultado

1. Na tela Astra Web, use Install ou Play. O pacote completo é grande; Play
   verifica o cache ou instala os dados antes de abrir o cliente.
2. Selecione o servidor local, versão/protocolo 860.
3. Entre com sua conta e selecione um personagem.
4. Confira o mapa, teclado, cliques e redimensionamento da janela.
5. Saia e entre novamente; depois confira um refresh da página.
6. Abra o console do navegador para verificar erros reais de WebGL/WASM/rede.

Para ligar/desligar o painel de desempenho, clique em **Web options** no canto
inferior direito e marque/desmarque **Performance diagnostics**. O botão × do
painel também desliga os diagnósticos. A opção é lembrada neste navegador.

`Connecting to: 127.0.0.1:7171` é normal: o log mostra o destino TCP original,
que o `config.js` encaminha à ponte WebSocket. Um aviso `SlowLua` informa tempo
de execução; sozinho ele não prova falha de rede.

O cliente deve manter RSA/XTEA/checksum. Não remova assertions ou criptografia
para fazer o login passar. Produção exige HTTPS/WSS, configuração confiável,
cabeçalhos de isolamento e, se necessário, CORS no servidor HTTP.

Para preparar outra máquina ou usar Emscripten nativo no Windows, consulte
[o guia geral](browser-wasm.md).
