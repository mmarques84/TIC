#!/bin/sh
# Roda DENTRO do container "migrador" (docker compose run --rm migrador).
# 0) papéis do banco (tic_dono, tic_n8n, tic_leitura) e senhas de login
# 1) aplica cada migration nova UMA vez, em ordem, registrando em controle.schema_migracao
# 2) recria funções (db/funcoes: fn_*, sp_*, job_*, int_*), que são código, não dado
# 3) permissões: tic_n8n só EXECUTA sp_* e job_*; tic_leitura só lê
# Migration já aplicada nunca roda de novo; se o arquivo mudou depois de aplicado, avisa e para.
set -eu

DIR=/tic/db
P="psql -v ON_ERROR_STOP=1 -q -X"

echo "== TIC · migrador ($PGDATABASE) =="

$P -v n8n_senha="$TIC_N8N_SENHA" -v leitura_senha="$TIC_LEITURA_SENHA" -f "$DIR/seguranca/papeis.sql"

$P -c "CREATE SCHEMA IF NOT EXISTS controle AUTHORIZATION tic_dono;
CREATE TABLE IF NOT EXISTS controle.schema_migracao (
  versao      text PRIMARY KEY,
  checksum    char(64) NOT NULL,
  aplicada_em timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE controle.schema_migracao OWNER TO tic_dono;"

# 1) Migrations (como tic_dono: tudo que é criado pertence a ele)
novas=0
for f in $(ls "$DIR/migrations"/*.sql 2>/dev/null | sort); do
  v=$(basename "$f")
  soma=$(sha256sum "$f" | cut -d' ' -f1)
  registrada=$($P -A -t -c "SELECT checksum FROM controle.schema_migracao WHERE versao = '$v'")
  if [ -n "$registrada" ]; then
    if [ "$registrada" != "$soma" ]; then
      echo "ERRO: $v já foi aplicada e o arquivo mudou depois. Migrations aplicadas não podem ser editadas: crie uma nova." >&2
      exit 1
    fi
    continue
  fi
  echo "   aplicando: $v"
  $P -1 -c "SET ROLE tic_dono" -f "$f" -c "INSERT INTO controle.schema_migracao (versao, checksum) VALUES ('$v', '$soma')"
  novas=$((novas + 1))
done

# 2) Funções
for f in $(ls "$DIR/funcoes"/*.sql 2>/dev/null | sort); do
  echo "   código: funcoes/$(basename "$f")"
  $P -1 -c "SET ROLE tic_dono" -f "$f"
done

# 3) Permissões
$P -f "$DIR/seguranca/permissoes.sql"
qtd=$($P -A -t -c "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname IN ('acesso','cadastro','bruto','derivado','ia','controle') AND (p.proname LIKE 'sp\_%' OR p.proname LIKE 'job\_%')")
echo "   permissões: tic_n8n pode executar $qtd função(ões) sp_*/job_*"

echo "== pronto: $novas migration(s) nova(s) =="
