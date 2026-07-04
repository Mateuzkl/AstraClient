--[[ TESTE DE FALHA -- loop que tenta ENGOLIR o watchdog com pcall -------------
  Esperado: `while true do pcall(...) end` tenta capturar e ignorar o abort do
  watchdog. Com a blindagem (o pcall/xpcall do sandbox re-lancam o sentinela do
  watchdog), o abort NAO e engolido: mata em ~1s igual ao 12. SEM a blindagem,
  congelaria para sempre. Este e o teste-chave do "pcall a prova de watchdog".
  NAO crasha.
--]]
print('[13] while true do pcall(noop) end -- o watchdog deve vencer o pcall')
while true do
  pcall(function() end)   -- tenta engolir o abort; a blindagem re-lanca o sentinela
end
