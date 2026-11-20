#!/bin/sh
# Cria (ou atualiza) no n8n a credencial Postgres usada pelos workflows, com a senha do .env.
# O usuário tic_n8n só pode executar sp_* e job_* (decisão 002). A senha não aparece na tela nem fica em arquivo.
#   sh scripts/n8n-credencial-postgres.sh
set -eu
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."

senha=$(sed -n 's/^TIC_N8N_SENHA=//p' .env | tr -d '\r')
[ -n "$senha" ] || { echo "TIC_N8N_SENHA vazio no .env"; exit 1; }
esc=$(printf '%s' "$senha" | sed 's/\\/\\\\/g; s/"/\\"/g')

printf '[{"id":"TicPostgresN8n01","name":"Postgres TIC (n8n)","type":"postgres","data":{"host":"postgres","port":5432,"database":"tic","user":"tic_n8n","password":"%s","ssl":"disable","allowUnauthorizedCerts":false}}]' "$esc" \
  | docker compose exec -T n8n sh -c 'umask 077; cat > /tmp/cred.json && n8n import:credentials --input=/tmp/cred.json > /dev/null; rc=$?; rm -f /tmp/cred.json; exit $rc'
echo "credencial Postgres TIC (n8n) importada"
