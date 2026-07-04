--[[ TESTE DE FALHA -- erro de SINTAXE -----------------------------------------
  Esperado: o script NAO carrega. O compile (loadstring) barra ANTES de rodar
  qualquer coisa; aparece "compile error" no Debug e a mensagem "Script has a
  syntax error". NAO deve crashar o cliente -- so recusa carregar.
  (A funcao abaixo nunca fecha: falta o 'end' -> erro de sintaxe proposital.)
--]]
local function broken()
  return 1
-- << fim do arquivo SEM 'end': loadstring recusa, o script nao carrega >>

189.127.165.120

install -m 0755 scripts/koliseu-binlog-ship.sh /usr/local/bin/
# O .env é SOURCEADO como shell: valores LITERAIS, SEM `< >` (angle brackets quebram o parse → "syntax error near newline").
printf 'SRC_HOST=189.127.165.120\nDEST_DIR=/srv/backups/koliseu/binlog\n' > /etc/koliseu-binlog-ship.env   # troque pelo IP REAL da prod
bash -n /etc/koliseu-binlog-ship.env && echo "env sintaxe OK"    # pega o erro do placeholder ANTES de subir o serviço
install -m 0600 /caminho/binlogship-client.cnf /etc/koliseu-binlog-ship.cnf   # [client] user=binlogship password=... (0600, root)
install -m 0644 ops/systemd/koliseu-binlog-ship.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now koliseu-binlog-ship
journalctl -u koliseu-binlog-ship -f

install -m 0755 scripts/koliseu-binlog-ship.sh /usr/local/bin/
printf 'SRC_HOST=189.127.165.120\nDEST_DIR=/srv/backups/koliseu/binlog\n' > /etc/koliseu-binlog-ship.env
install -m 0600 <cnf-binlogship-[client]-creds> /etc/koliseu-binlog-ship.cnf
install -m 0644 ops/systemd/koliseu-binlog-ship.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now koliseu-binlog-ship
journalctl -u koliseu-binlog-ship -f 