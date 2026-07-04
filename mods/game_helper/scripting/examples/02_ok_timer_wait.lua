--[[ TESTE OK -- Timer + wait() cooperativo ------------------------------------
  Esperado: "tick N" a cada 3s; e um loop `while true` que roda PARA SEMPRE mas
  cede o controle com wait(1s) -> imprime "loop vivo" e NUNCA congela o cliente.
  Prova que o loop cooperativo funciona E que o watchdog NAO aborta um loop que
  cede com wait() (so mata os que nao cedem -- ver 12_fail_infinite_loop).
  Deixe ligado ~10s. Para parar: desabilite o script (os Timers param sozinhos).
  Seguro: so imprime.
--]]
local ticks = 0
Timer('t02_tick', function()
  ticks = ticks + 1
  print('[02] tick ' .. ticks)
end, 3000, true)

Timer('t02_coop', function()
  print('[02] loop cooperativo iniciado (cede com wait, nao congela)')
  local i = 0
  while true do
    i = i + 1
    if i % 5 == 0 then print('[02] loop vivo, i=' .. i) end
    wait(1000)
  end
end, 100, false)
