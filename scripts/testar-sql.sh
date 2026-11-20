#!/bin/sh
# Recria o banco de teste (tic_teste), aplica tudo do zero e roda tests/sql/*.sql.
# Uso (do computador do dev): docker compose run --rm --entrypoint sh migrador /tic/scripts/testar-sql.sh
# Nunca roda no banco "tic".
set -eu
export PGDATABASE=tic_teste
psql -v ON_ERROR_STOP=1 -q -X -d postgres -c "DROP DATABASE IF EXISTS tic_teste WITH (FORCE)" -c "CREATE DATABASE tic_teste"
sh /tic/scripts/migrar.sh
ok=0; falhas=0
for f in $(ls /tic/tests/sql/*.sql | sort); do
  if psql -v ON_ERROR_STOP=1 -q -X -f "$f" > /tmp/saida.txt 2>&1; then
    echo "   ok:    $(basename "$f")"; ok=$((ok + 1))
  else
    echo "   FALHA: $(basename "$f")"; sed 's/^/          /' /tmp/saida.txt; falhas=$((falhas + 1))
  fi
done
echo "== testes: $ok ok, $falhas falha(s) =="
[ "$falhas" -eq 0 ]
