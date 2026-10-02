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

## Ambiente já preparado nesta máquina (WSL Ubuntu-24.04)

O SDK Emscripten 6.0.8 está em `/home/mateus/astra-wasm-v2/emsdk`.
O build fica em `/home/mateus/astra-wasm-v2/build-release`.
O pack separado está em `/home/mateus/astra-wasm-v2/assets/860`.
Esse pack não sobrescreve o DAT/SPR personalizado do repositório.

No PowerShell, para recompilar código alterado:

```powershell
wsl -d Ubuntu-24.04 --cd "C:/Users/Mateus/Desktop/DLL and Server/AstraClient" -- bash -lc 'source /home/mateus/astra-wasm-v2/emsdk/emsdk_env.sh && cmake --build /home/mateus/astra-wasm-v2/build-release --parallel 6'
```

Para configurar e compilar do início usando esse mesmo SDK e pack:

```powershell
wsl -d Ubuntu-24.04 --cd "C:/Users/Mateus/Desktop/DLL and Server/AstraClient" -- bash -lc 'source /home/mateus/astra-wasm-v2/emsdk/emsdk_env.sh && bash browser/build-wasm.sh Release /home/mateus/astra-wasm-v2/build-release -DASTRA_WASM_THINGS_DIR=/home/mateus/astra-wasm-v2/assets/860'
```

Uma configuração completa pode repor o `config.js` padrão. Confira a
configuração local abaixo **depois** de configurar/compilar.

## Configurar as duas pontes

Edite o arquivo gerado, fora da branch:

```text
\\wsl.localhost\Ubuntu-24.04\home\mateus\astra-wasm-v2\build-release\dist\config.js
```

Use:

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

Nesta máquina, durante o teste, o gateway foi `172.27.176.1`. Se mudar, troque
esse endereço nos dois comandos seguintes. O TFS precisa ouvir em uma interface
acessível ao WSL; não desative o firewall para contornar problemas de acesso.

Abra **três terminais**, mantendo os processos abertos:

Terminal 1 — ponte do login:

```powershell
wsl -d Ubuntu-24.04 -- websockify 127.0.0.1:8815 172.27.176.1:7171
```

Terminal 2 — ponte do jogo:

```powershell
wsl -d Ubuntu-24.04 -- websockify 127.0.0.1:8817 172.27.176.1:7172
```

Terminal 3 — site:

```powershell
wsl -d Ubuntu-24.04 --cd "C:/Users/Mateus/Desktop/DLL and Server/AstraClient" -- python3 browser/serve.py /home/mateus/astra-wasm-v2/build-release/dist --port 8080
```

Abra **http://127.0.0.1:8080/astraclient.html** no navegador. Para usar a porta
8814, troque somente `--port 8080` por `--port 8814` e use essa porta na URL.
Não é necessário recompilar para mudar a porta HTTP ou o `config.js`.

Se a porta estiver ocupada por um teste já aberto, use-o ou encerre apenas
o terminal desse teste com Ctrl+C antes de iniciar outro processo na mesma porta.

## Conferir o resultado

1. Aguarde a carga inicial dos assets; o pacote completo é grande.
2. Selecione o servidor local, versão/protocolo 860.
3. Entre com sua conta e selecione um personagem.
4. Confira o mapa, teclado, cliques e redimensionamento da janela.
5. Saia e entre novamente; depois confira um refresh da página.
6. Abra o console do navegador para verificar erros reais de WebGL/WASM/rede.

`Connecting to: 127.0.0.1:7171` é normal: o log mostra o destino TCP original,
que o `config.js` encaminha à ponte WebSocket. Um aviso `SlowLua` informa tempo
de execução; sozinho ele não prova falha de rede.

O cliente deve manter RSA/XTEA/checksum. Não remova assertions ou criptografia
para fazer o login passar. Produção exige HTTPS/WSS, configuração confiável,
cabeçalhos de isolamento e, se necessário, CORS no servidor HTTP.

Para preparar outra máquina ou usar Emscripten nativo no Windows, consulte
[o guia geral](browser-wasm.md).
