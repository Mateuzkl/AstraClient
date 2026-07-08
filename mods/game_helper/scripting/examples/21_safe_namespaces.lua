--[[ NAMESPACES SEGUROS -- HTTP / File / Storage / import -----------------------
  Estas capabilities funcionam com o MODO AVANCADO DESLIGADO (o sandbox continua
  fechado): sao a alternativa CONTIDA ao io/require. Nenhuma delas roda codigo
  nativo -- HTTP usa o cliente (g_http), File/Storage usam o diretorio de scripts
  (jailed), e import compila outro .lua no MESMO sandbox.

  Ligar o modo avancado NAO e necessario para este exemplo.
--]]

print('[21] Namespaces seguros -- File / Storage / import / HTTP')

-- 1) File: escreve e le de volta (jailed em bot_scripts) ----------------------
local wok, werr = File.write('safe_test.txt', 'ola do namespace File!\n')
if wok then
  local content = File.read('safe_test.txt')
  print('[21] [OK] File.write+read -- ' .. tostring(#(content or '')) .. ' bytes lidos')
else
  print('[21] [FALHA] File.write -- ' .. tostring(werr))
end

-- 2) Storage: contador que PERSISTE entre reloads/relogs ----------------------
local runs = (Storage.get('runs', 0)) + 1
if Storage.set('runs', runs) then
  print('[21] [OK] Storage -- este script ja rodou ' .. runs .. ' vez(es) (persiste no disco)')
else
  print('[21] [FALHA] Storage.set')
end

-- 3) import: reusar codigo de outro .lua, contido no mesmo sandbox ------------
File.write('_import_demo.lua', 'return { hello = function(n) return "oi, " .. tostring(n) end }\n')
local iok, mod = pcall(import, '_import_demo')
if iok and type(mod) == 'table' and type(mod.hello) == 'function' then
  print('[21] [OK] import -- ' .. mod.hello('mundo'))
else
  print('[21] [FALHA] import -- ' .. tostring(mod))
end
File.delete('_import_demo')  -- limpeza (o modulo ja foi importado + cacheado)

-- 4) HTTP: requisicao ASSINCRONA (o resultado chega no callback) --------------
if type(HTTP) == 'table' and type(HTTP.getJSON) == 'function' then
  print('[21] HTTP.getJSON https://httpbin.org/get ... (resposta no callback)')
  HTTP.getJSON('https://httpbin.org/get', function(data, err)
    if err then
      print('[21] [FALHA] HTTP -- ' .. tostring(err))
    else
      local origin = (type(data) == 'table') and data.origin or '?'
      print('[21] [OK] HTTP -- resposta recebida (origin=' .. tostring(origin) .. ')')
    end
  end)
else
  print('[21] [FALHA] HTTP indisponivel')
end

print('[21] === testes sincronos concluidos; o HTTP responde em instantes ===')
