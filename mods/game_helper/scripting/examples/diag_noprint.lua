--[[ DIAGNOSTICO -- corpo SEM print e SEM API ---------------------------------
  Objetivo: separar "o problema e o resume/setup do script" de "o problema e o
  print -> ctx.log -> escrita no console Debug".
  Este corpo so faz aritmetica pura -- nao chama print nem nenhuma API do cliente.
    * Se ISTO crasha  -> o problema esta no resume/setup (nao no print).
    * Se carrega OK   -> o problema esta no print/console (o createWidget do Debug).
  Seguro: nao toca em nada.
--]]
local x = 1 + 1
local y = x * 2
local z = y - 1
-- termina sem chamar nada
