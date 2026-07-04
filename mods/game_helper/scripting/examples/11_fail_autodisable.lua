--[[ TESTE DE FALHA -- erro repetido -> AUTO-DISABLE ---------------------------
  Esperado: carrega OK, mas um Timer erra a cada 1s. O error-accounting conta os
  erros e, apos 5, DESABILITA o script sozinho -> "disabled after 5 errors" no
  Debug (e some da lista Running). Prova que um script quebrado nao fica errando
  para sempre. NAO crasha o cliente.
--]]
print('[11] Timer que erra a cada 1s -- deve auto-desabilitar apos 5 erros')
Timer('t11_boom', function()
  local nao_existe = nil
  return nao_existe.campo   -- runtime error a cada tick (index em nil)
end, 1000, true)
