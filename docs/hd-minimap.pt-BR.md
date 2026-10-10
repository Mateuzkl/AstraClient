# Tutorial: gerar e instalar o minimapa HD do AstraClient

## Como as imagens são feitas

O HD usa os sprites reais do jogo. Não é uma imagem gerada por IA nem uma foto
de satélite: o exportador abre uma cópia do mapa `.otbm` offline, usa o
`items.otb` para transformar os ServerIDs em ClientIDs e desenha os itens com o
DAT/SPR do próprio cliente.

Ele desenha chão, bordas, paredes, objetos e camadas superiores. Não inclui
personagens, criaturas, efeitos, iluminação ou animações. Padrões dos itens,
fluidos, deslocamentos e elevação são considerados na renderização.

Cada imagem base cobre 16×16 tiles e é salva em PNG de 512×512 pixels. O gerador
também produz versões para zoom distante: níveis 1, 2, 4, 8, 16, 32, 64, 128,
256, 512 e 1024. Cada andar é tratado separadamente.

O cliente carrega apenas as imagens necessárias à região visível, com cache
limitado. O pacote completo permanece no disco depois de fechar o cliente, por
isso não é necessário andar novamente para revelar o HD. Sem o pacote, o HD ao
vivo só consegue desenhar terreno recebido do servidor naquela sessão.
Há no máximo quatro decodificações simultâneas e 32 texturas em cache. Vistas
grandes escolhem imagens de zoom mais distante para caber nesse limite; se nenhum
nível couber, usam o mapa clássico. Arrastar para outra região não deixa as
decodificações já concluídas bloqueando o carregamento de novas imagens.

Ao mudar o zoom ou abrir o mapa completo, o cliente mantém um nível HD já
completo até que todos os chunks necessários do novo nível estejam prontos.
A visão geral da região e as imagens da transição ficam protegidas no cache,
evitando retângulos coloridos temporários do mapa clássico. O nível desejado
reserva até 24 posições do cache; a visão geral e a transição continuam dentro
do limite total de 32. Depois de atender a área visível, podem ser antecipados
até quatro chunks vizinhos, sem carregar o mapa inteiro na RAM.

Ao abrir um cache vazio, o clássico pode aparecer inicialmente enquanto a
visão geral carrega. Regiões sem PNG ou com transparência continuam usando o
OTMM como fundo. Esses limites não são uma promessa de FPS ou memória total.
O teste `Run-Smoke.ps1 -Glitches` compara pixels reais em OpenGL e DirectX,
inclusive com carregamento lento e zoom fracionário. Detalhes e evidências:
[correção visual do PR #204](audits/pr204/VISUAL_GLITCHES_PR204.md).

## 1. Separe os arquivos corretos

Você precisa de:

- AstraClient compilado a partir desta branch e os módulos Lua correspondentes.
- Mapa `.otbm` realmente usado pelo servidor. Confira `mapName` no `config.lua`.
- `data/items/items.otb` correspondente a esse mapa.
- DAT/SPR correspondente aos ClientIDs desse OTB, no cliente em
  `data/things/860/`. Normalmente são `Tibia.dat` e `Tibia.spr`.
- Arquivos auxiliares de assets, caso esse DAT/SPR use OTFI, OTML ou sprites
  divididos/indexados.
- Windows/PowerShell, Python 3.11 ou mais recente e Pillow para a geração offline.

O script seleciona versão/protocolo 860 e carrega os assets pelo `game_things`.
`items.xml` não é necessário para gerar essas imagens. Não use um OTB de outra
base ou imagens de outro mapa: aparência, coordenadas e andares precisam combinar.

## 2. Prepare o Python

Abra PowerShell na raiz do AstraClient. Exemplo de pasta; ajuste para a sua:

```powershell
Set-Location -LiteralPath 'C:/Games/AstraClient'
python --version
python -m venv .venv
./.venv/Scripts/python.exe -m pip install Pillow
```

A `.venv` é somente uma ferramenta local de geração. Jogadores não precisam de
Python nem Pillow para usar o HD. Se já tiver Pillow em outro Python, pode
informar esse interpretador no parâmetro `-Python`.

## 3. Execute o exportador

Use um executável novo que contenha o HD. O caminho abaixo é um exemplo do
build local OpenGL; ajuste se seu executável estiver em outra pasta.

Escolha uma pasta de saída que **ainda não exista**. Não aponte diretamente para
um pacote instalado que você quer preservar.

```powershell
./tools/minimap_hd/Export-Pack.ps1 `
  -BinaryPath './build/hd-minimap/bin/otclient_gl_x64.exe' `
  -WorldPath 'C:/Servers/MyServer/data/world/world.otbm' `
  -ItemsPath 'C:/Servers/MyServer/data/items/items.otb' `
  -OutputPath 'C:/HD-Packs/astra-world-v2' `
  -Python './.venv/Scripts/python.exe'
```

Troque os caminhos pelos seus arquivos reais. O programa de exportação roda
oculto, com perfil separado e sem login. Ele copia/lê os arquivos de origem;
não altera o mapa, o OTB, o servidor ou seu perfil normal do cliente.

Espere a mensagem `Persistent HD pack ready`. O tempo e o espaço necessário
dependem do tamanho e da densidade do mapa. O script mostra progresso e o
caminho dos logs. Se houver erro, mantém os logs e a saída incompleta para
diagnóstico; não instale um pacote incompleto.
O processo nativo tem limite de 30 minutos. Para mapas maiores, acrescente
`-TimeoutSeconds 3600` para permitir uma hora. Se o tempo acabar, somente o
processo de exportação é encerrado; os logs e arquivos de origem são preservados.

## 4. Confira o pacote

A pasta gerada deve conter:

```text
astra-world-v2/
  index.txt
  source.json
  minimap.otmm
  satellite-1-<x>-<y>-<z>.png
  satellite-2-<x>-<y>-<z>.png
  ...demais imagens e níveis de zoom...
```

`index.txt` lista as imagens. `source.json` registra os hashes SHA-256 do mapa e
OTB, as assinaturas dos assets, andares e níveis de zoom. `minimap.otmm` fornece
o mapa clássico revelado e suas informações de tiles. As imagens HD não mudam
as regras de movimento/autowalk: os dados do mapa continuam sendo usados.
O gerador exige um OTMM não vazio e aceita até 100.000 imagens contando todos
os níveis. Só publica o `index.txt` depois de gerar as imagens, metadados e OTMM
com sucesso.

## 5. Instale no cliente

1. Feche o cliente normal.
2. Se `data/minimap_hd` já existir, guarde uma cópia de segurança fora dessa pasta.
3. Coloque a pasta completa gerada em `AstraClient/data/minimap_hd`.
4. Confira se o caminho é `data/minimap_hd/index.txt`, sem uma pasta extra no meio.
5. Reabra o executável atualizado.
6. Clique no botão **HD**, à esquerda de **Go to Cyclopedia Map**, ou marque
   **Options → Graphics → HD Minimap (Satellite View)**.

O botão fica verde quando HD está ativo. Clique novamente para usar o minimapa
clássico. Botão e checkbox ficam sincronizados, a escolha fica salva e cada modo
mantém seu zoom. Essa opção não liga o xBRZ/HD Sprite Upscaling.
Ao abrir e fechar o mapa completo com `Ctrl+Shift+M`, os controles HD, Cyclopedia,
zoom e andar continuam por cima do mapa, visíveis e clicáveis.

O pacote local já gerado nesta implementação tem 4.702 imagens PNG, 11 níveis
de zoom e os andares populados de 0 a 13, usando `world.otbm` da base escolhida
em `DLL and Server/forgottenserver-downgrade-1.8-8.60`. Esses números são desse
mapa, não um requisito para outros mapas.

## 6. Teste e distribua

Consulte também a [auditoria do PR #204](audits/pr204/AUDITORIA_PR204_FULL.md),
com achados, testes executados e limitações de desempenho ainda não medidas.

Na raiz do repositório, com o pacote instalado:

```powershell
./tests/minimap_hd/Run-Smoke.ps1 `
  -BinaryPath './build/hd-minimap/bin/otclient_gl_x64.exe'

./tests/minimap_hd/Run-Smoke.ps1 `
  -BinaryPath './build/hd-minimap/bin/otclient_gl_x64.exe' -Satellite

./tests/minimap_hd/Run-Smoke.ps1 `
  -BinaryPath './build/hd-minimap/bin/otclient_gl_x64.exe' -Export

./tests/minimap_hd/Run-Smoke.ps1 `
  -BinaryPath './build/hd-minimap/bin/otclient_gl_x64.exe' -Audit
```

Esses testes usam um perfil separado, janela oculta e nenhum login no servidor.
Conferem controles, sincronização, zoom, persistência, cache e carregamento das
imagens. Também confira visualmente no jogo, troque andares, afaste o zoom e
feche/reabra o cliente: os testes ocultos não medem FPS nem garantem aparência.
O teste nativo repete a abertura/fechamento do mapa completo nos dois modos e
troca HD/clássico dentro dessa vista para conferir controles e zoom. `-Satellite`
também testa carregamentos abandonados e o orçamento de cache em vistas 4K.
`-Export` usa OTB/OTBM sintéticos, confere cobertura clássica em dois andares e
compara pixels dos PNGs para validar a elevação das camadas superiores. Este
último precisa de Python/Pillow, mas não de arquivos do servidor nem do pacote
instalado.

`-Audit` precisa do pacote instalado e de Python/Pillow. Testa destruição de
widgets ainda referenciados pelo Lua, callbacks, alternâncias/resets rápidos,
cache de posições vazias e arquivos inválidos isolados. Também valida PNG/ENC3
válidos e rejeita uma chave de configuração conflitante. Os erros dessas
fixtures são esperados; qualquer erro inesperado faz o runner falhar.

O limite de quatro jobs agora permanece válido mesmo após expulsão do cache,
troca de pacote ou desligamento do HD. O cancelamento é cooperativo: um decode
já iniciado pode terminar, mas seu resultado cancelado não entra no novo pacote.
Esse limite não inclui tarefas de outros sistemas na fila global do cliente.
Posições sem terreno entram no mesmo cache limitado e são substituídas quando
chegam itens; o contador de tiles inclui essas entradas vazias. Leituras PNG e
o tamanho declarado da descompressão ENC3 são limitados antes da alocação;
animações APNG são rejeitadas antes do decode. OTMM corrompido retorna falha,
mas a leitura ainda pode ter aplicado blocos válidos anteriores ao erro.

Distribua o executável atualizado, os módulos correspondentes, os assets e a
pasta **inteira** `data/minimap_hd`. Ela fica ignorada no Git por ser um pacote
grande e específico do mapa. Fazer `git pull` não gera nem baixa essas imagens.

## Atualização e problemas comuns

- **Mudou o mapa ou o DAT/SPR?** Gere outro pacote em uma pasta nova, faça backup
  do anterior e substitua a pasta instalada. Regere mesmo que as assinaturas no
  cabeçalho dos assets não tenham mudado.
- **Pacote gerado antes da correção de elevação:** regere para que as imagens
  também usem a elevação de chão/objetos ao desenhar a camada superior.
- **Botão/checkbox desabilitado:** está usando executável antigo. Compile a
  versão que contém as novas funções nativas e use os módulos correspondentes.
- **Só aparece HD depois de andar:** confira se o pacote completo está instalado,
  se o `index.txt` está no caminho correto e se os assets correspondem.
- **Mapa HD de outro servidor:** gere com o mapa correto. O cliente confere as
  assinaturas DAT/SPR, mas não detecta automaticamente qual mundo está no servidor.
- **Erro de item inválido:** o mapa, OTB e DAT não combinam. Corrija os arquivos
  de entrada; renomear PNGs ou adivinhar deslocamentos não resolve.
- **Output already exists:** escolha uma pasta nova; o script não sobrescreve.
- **Pillow não encontrado:** passe em `-Python` o interpretador em que ele foi instalado.
- **Export timed out:** confira os logs antes de aumentar `-TimeoutSeconds`.
- **PNG faltando/corrompido:** confira o log e reinstale o pacote completo.

Diagnóstico no terminal Lua, depois de os assets serem carregados:

```lua
g_minimap.hasSatellitePack()
g_minimap.getSatelliteChunkCount()
g_minimap.getSatelliteTextureCount()
g_minimap.getSatelliteDecodeCount() -- Inclui resultados concluídos ainda não coletados.
g_minimap.getSpriteViewCount()
g_minimap.getSpriteTileLookupCount() -- Consultas acumuladas; não mede FPS.
```

Detalhes técnicos, limites e testes adicionais:
[documentação em inglês](hd-minimap.md).

## Surface View da Cyclopedia

Abra **Map** pelo botão da Cyclopedia e selecione **Surface View**. Ele usa o
mesmo pacote PNG/cache do HD, mas não muda a opção HD do minimapa do HUD.
**Map View** continua sendo OTMM clássico. Surface funciona nos pisos 0-7;
no subsolo volta para Map, preservando a preferência Surface.

O **Level Separator** (0-100) muda a transparência dos andares de fundo,
desenhados do 7 até o andar selecionado. O terreno do andar selecionado fica
opaco; a transparência original dos PNGs preserva os espaços vazios.
No piso 7 o slider fica desabilitado. Alternar vistas, zoom e pisos não pede
dados novos ao servidor.

Exportações novas geram `cities.json` a partir das towns do `.otbm` correto.
Para acrescentar nomes a um pacote existente, com o mesmo hash de mapa:

```powershell
python tools/minimap_hd/city_labels.py 'C:/Servidor/data/world/world.otbm' data/minimap_hd
```

O exportador recusa outro mapa e não sobrescreve um `cities.json` existente.
As posições iniciais são os templos reais, não centros adivinhados. É possível
ajustar os rótulos para seu mapa, mantendo o hash. **City names** mostra/esconde
os nomes; no máximo 32 rótulos são reutilizados, sem sobreposições.

Os marcadores da Cyclopedia agora são indexados como dados, sem criar milhares
de widgets fora da tela. O pool tem até 128 ícones visíveis, priorizando flags
do jogador e os mais próximos. Se houver mais que isso na vista, aproxime o
zoom para ver os demais. Filtros, edição de flags e estado da janela continuam
disponíveis. O mapa não recarrega o OTMM global ao abrir.

Veja os [testes](audits/cyclopedia-surface-view/TESTES.md) e
[medições/limitações](audits/cyclopedia-surface-view/BENCHMARK.md).
