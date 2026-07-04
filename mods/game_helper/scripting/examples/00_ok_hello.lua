--[[ TESTE OK -- diagnostico minimo -------------------------------------------
  Esperado: carrega e escreve UMA linha no Debug, sem erro nenhum.
  Para que serve: se ATE este script (que so faz print) crashar/quebrar, o
  problema NAO esta nas APIs do jogo -- esta no proprio pipeline de carga
  (sandbox / print / compile). Comece SEMPRE por ele ao diagnosticar.
  Seguro: nao toca em nada do jogo.
--]]
print('[00_ok_hello] carregado com sucesso -- pipeline de scripting OK')
