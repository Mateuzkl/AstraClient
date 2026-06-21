# Gerar o client de TESTE

> Este guia foi consolidado em **[RELEASE_PROCESS.md](RELEASE_PROCESS.md)**, que cobre os
> ambientes de **teste e produção** num único documento autoritativo.

Resumo do fluxo de teste (detalhes e referência completa no doc acima):

```powershell
python .\tools\gen_asset_key.py --force      # chave nova por release (arquive + o .pdb)
.\compile.ps1 -Config DirectX                # rebuild (chave compilada no exe)
.\tools\make_release.ps1 -Env test -Encrypt  # config.test.lua (gameteste) cifrado dentro do data.zip
```
Depois: smoke test pelo Launcher → subir em `/admin/client` (`testServer`/`otc`) + bump da
versão `client_version` test/otc.
