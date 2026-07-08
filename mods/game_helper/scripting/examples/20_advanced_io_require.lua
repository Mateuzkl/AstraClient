--[[ MODO AVANCADO (opt-in) -- io / require / ffi ------------------------------
  SO FAZ ALGO UTIL COM O "MODO AVANCADO" LIGADO.
  Ligue na aba Scripting -> checkbox "Advanced mode (io / require / native DLL)" e aceite o
  aviso. Com o modo DESLIGADO (padrao) o sandbox continua fechado: io, require e
  ffi sao nil, entao cada teste abaixo apenas reporta FALHA -- NAO crasha.

  Modelo Zerobot: com o modo ligado o script ganha poder total na SUA maquina
  (I/O de arquivo, os completo, carregar DLLs nativas via ffi). O risco e seu --
  so ligue e rode scripts avancados em que voce confia.

  O que este script valida (cada teste imprime OK ou FALHA):
    1) io.open  -- escreve e le de volta um arquivo texto (round-trip). Tenta a
                   pasta 'bot_scripts/' primeiro (o diretorio de scripts, quando
                   o diretorio de trabalho do cliente e o writeDir) e, se nao der,
                   cai para o diretorio de trabalho. Apaga o arquivo no fim com
                   os.remove (que o os RESTRITO do sandbox nao expoe).
    2) require  -- require('string'): prova que require() esta exposto.
    3) ffi      -- pcall(require, 'ffi') + um uso seguro (ffi.sizeof), SEM
                   carregar nenhuma DLL. A partir daqui daria para ffi.load(...) e
                   chamar codigo nativo -- este exemplo NAO faz isso de proposito.
  Seguro/didatico: nao toca em nada do jogo; so stdlib + um arquivo temporario.
--]]

local ok_n, fail_n = 0, 0
local function report(ok, name, detail)
  if ok then ok_n = ok_n + 1 else fail_n = fail_n + 1 end
  print('[20] ' .. (ok and '[OK]' or '[FALHA]') .. ' ' .. name
    .. (detail and (' -- ' .. detail) or ''))
end

print('[20] Modo Avancado -- validando io / require / ffi')

-- Deteccao rapida: com o modo desligado estas libs sao nil dentro do sandbox.
if type(io) ~= 'table' or type(require) ~= 'function' then
  print('[20] AVISO: io/require indisponiveis -- o MODO AVANCADO parece DESLIGADO.')
  print('[20] Ligue "Advanced mode" na aba Scripting e recarregue este script.')
end

-- 1) io.open: escreve e le de volta (round-trip) ------------------------------
if type(io) ~= 'table' or type(io.open) ~= 'function' then
  report(false, 'io.open write+read', 'io indisponivel (Modo Avancado desligado?)')
else
  local FNAME    = 'koliseu_advanced_test.txt'
  local payload  = 'KoliseuClient advanced I/O test @ ' .. tostring(os.date('%Y-%m-%d %H:%M:%S'))
  local usedPath = nil
  -- 'bot_scripts/' cai na pasta de scripts quando o CWD e o writeDir; senao usa o CWD.
  for _, path in ipairs({ 'bot_scripts/' .. FNAME, FNAME }) do
    local fh = io.open(path, 'w')
    if fh then
      fh:write(payload)
      fh:write('\n')
      fh:close()
      usedPath = path
      break
    end
  end
  if not usedPath then
    report(false, 'io.open write', 'nao consegui escrever em nenhum caminho candidato')
  else
    local rh = io.open(usedPath, 'r')
    if not rh then
      report(false, 'io.open read', 'escreveu mas nao releu ' .. usedPath)
    else
      local content = rh:read('*a')
      rh:close()
      local matched = type(content) == 'string'
        and string.find(content, payload, 1, true) ~= nil
      report(matched, 'io.open write+read',
        usedPath .. ' (' .. tostring(#(content or '')) .. ' bytes lidos)')
    end
    -- Limpeza com os COMPLETO (o os restrito do sandbox nao expoe os.remove).
    if type(os.remove) == 'function' then
      pcall(os.remove, usedPath)
      report(true, 'os.remove (os completo)', 'arquivo de teste removido')
    else
      report(false, 'os.remove', 'os.remove indisponivel (os restrito)')
    end
  end
end

-- 2) require: prova que require() esta exposto --------------------------------
if type(require) ~= 'function' then
  report(false, 'require("string")', 'require indisponivel (Modo Avancado desligado?)')
else
  -- require de uma lib ja carregada: barato e sem efeitos colaterais.
  local ok, mod = pcall(require, 'string')
  report(ok and type(mod) == 'table', 'require("string")',
    ok and ('tipo=' .. type(mod)) or ('erro: ' .. tostring(mod)))
end

-- 3) ffi: require('ffi') + uso seguro (sem carregar DLL) ----------------------
do
  local ok, ffiMod = pcall(require, 'ffi')
  if not (ok and type(ffiMod) == 'table') then
    report(false, 'ffi (require)', 'ffi indisponivel: ' .. tostring(ffiMod))
  else
    -- Uso minimo e seguro: so consulta o proprio FFI, nao abre DLL nenhuma.
    local okSz, sz = pcall(function() return ffiMod.sizeof('int') end)
    report(okSz and type(sz) == 'number', 'ffi (require)',
      'os=' .. tostring(ffiMod.os) .. ' arch=' .. tostring(ffiMod.arch)
      .. ' sizeof(int)=' .. tostring(sz))
  end
end

print(('[20] === %d OK / %d FALHA ==='):format(ok_n, fail_n))
if fail_n > 0 then
  print('[20] Se TUDO deu FALHA, o Modo Avancado esta desligado -- ligue e recarregue.')
end
