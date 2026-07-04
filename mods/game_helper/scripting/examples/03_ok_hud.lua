--[[ TESTE OK -- HUD de texto --------------------------------------------------
  Esperado (EM JOGO): aparece um texto no topo-esquerdo do mapa; ele muda de
  texto/cor, se move, e some sozinho em ~6s. Testa criacao + cleanup de HUD.
  Requer estar logado (o HUD precisa do painel do mapa). Seguro: so pixels, nao
  afeta o mundo; o engine tambem limpa HUDs do script ao desabilitar.
--]]
local h = HUD(60, 60, '[03] HUD OK')
if h then
  h:setColor(0, 255, 0)
  print('[03] HUD criado, id=' .. tostring(h:getId()))
  Timer('t03_update', function() h:setText('[03] HUD vivo'):setColor(255, 220, 0):setPos(90, 80) end, 2000, false)
  Timer('t03_kill', function() h:destroy(); print('[03] HUD destruido -- teste OK') end, 6000, false)
else
  print('[03] HUD() retornou nil (esta offline? o HUD precisa do mapa)')
end
