--[[ TESTE DE AVISO -- numero gigante (linter), sem alocar --------------------
  Esperado: ao carregar, o LINTER avisa em amarelo ("numero muito grande ...").
  Este script NAO executa nenhuma alocacao perigosa -- so tem o literal no codigo
  para exercer o aviso do linter. Carrega e roda normal. Seguro.
  NOTA: OOM de verdade via Lua puro (string.rep gigante) vira um erro Lua
  recuperavel (o LuaJIT trata "not enough memory") -- ja cai no error-accounting,
  NAO crasha, mesmo sem o patch C++. O catch(std::exception&) do C++ so e
  acionado por um BINDING C++ do cliente estourando -- para reproduzir ISSO
  precisamos do log/dump do player que aponte qual binding, nao da para forjar
  de forma confiavel em Lua puro.
--]]
local BIG = 100000000   -- 100 milhoes: o linter deve avisar sobre este literal
print('[15] literal grande (' .. BIG .. ') declarado mas NAO alocado -- so testa o aviso do linter')
