--[[ TESTE DE FALHA -- loop infinito SEM wait() (watchdog) ---------------------
  Esperado: o corpo entra num `while true` que NUNCA cede. Sem defesa isto
  CONGELARIA o cliente. Com o watchdog, e abortado em ~1s -> "travou >1000ms sem
  wait()" (vermelho) no Debug. O linter tambem avisa em amarelo ao carregar.
  NAO crasha; so aborta o script. Compare com 02_ok_timer_wait (que usa wait e
  roda para sempre sem problema).
--]]
print('[12] entrando em while true SEM wait -- o watchdog deve abortar em ~1s')
while true do
  -- sem wait(), sem break: monopoliza o dispatcher ate o watchdog matar
end
