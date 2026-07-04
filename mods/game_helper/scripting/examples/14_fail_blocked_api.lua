--[[ TESTE DE FALHA -- API bloqueada pelo sandbox ------------------------------
  Esperado: ao carregar, o LINTER avisa em amarelo ("io nao esta disponivel no
  sandbox"). Ao rodar, `io` e nil dentro do sandbox -> runtime error "index nil".
  Prova que o sandbox bloqueia I/O e que o linter avisa antes. NAO crasha.
--]]
print('[14] tentando usar io.* (bloqueado no sandbox)')
io.write('isto nao deveria funcionar')   -- io == nil no sandbox -> erro de runtime
