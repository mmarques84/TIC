#!/bin/sh
# Publica os workflows de n8n/workflows/ no n8n do docker compose (local ou VPS) e reinicia o n8n.
#   sh scripts/publicar-n8n.sh                 # todos
#   sh scripts/publicar-n8n.sh api-auth        # só um
# Antes: node scripts/montar-workflows.mjs e sh scripts/n8n-credencial-postgres.sh.
# Ordem importa: sub-workflows primeiro (o api-auth chama o sub-autorizar pelo id).
set -eu
export MSYS_NO_PATHCONV=1 # Git Bash no Windows: não converter /tmp em caminho do Windows
cd "$(dirname "$0")/.."

lista="${*:-sub-autorizar api-auth api-admin api-central api-jornada api-inicio api-conducao api-cockpit sub-autotrac-get ing-autotrac-cadastro ing-autotrac-telemetria ing-autotrac-atic-cadastro ing-autotrac-atic}"
for nome in $lista; do
  arq="n8n/workflows/$nome.json"
  [ -f "$arq" ] || { echo "não existe: $arq"; exit 1; }
  id=$(sed -n 's/^  "id": "\([^"]*\)".*/\1/p' "$arq" | head -1)
  docker compose exec -T n8n sh -c "cat > /tmp/$nome.json" < "$arq"
  docker compose exec -T n8n n8n import:workflow --input="/tmp/$nome.json" > /dev/null
  docker compose exec -T n8n n8n publish:workflow --id="$id" > /dev/null
  docker compose exec -T n8n rm -f "/tmp/$nome.json"
  echo "publicado: $nome ($id)"
done
docker compose restart n8n > /dev/null
echo "n8n reiniciado"
