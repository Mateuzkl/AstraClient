--[[ TESTE OK -- leitura de Player.* -------------------------------------------
  Esperado: imprime vitals do personagem (offline mostra 0/nil, e correto).
  Para que serve: se 00_ok_hello passa mas ESTE crasha, o problema esta numa
  API Player.* (binding C++). Somente leitura, nao altera nada.
--]]
print('[01] id=' .. tostring(Player.getId()))
print('[01] nome=' .. tostring(Player.getName()))
print('[01] level=' .. tostring(Player.getLevel()))
print('[01] hp=' .. tostring(Player.getHealth()) .. ' (' .. tostring(Player.getHealthPercent()) .. '%)')
print('[01] mana=' .. tostring(Player.getMana()))
print('[01] leitura de Player.* OK')
