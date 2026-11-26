#!/bin/sh
# Cria (ou atualiza) no n8n a credencial "Autotrac (API)" usada pelos workflows ing-autotrac-*.
# É um Custom Auth com os dois cabeçalhos da Autotrac: Authorization "Basic usuário:senha" (texto puro, sem base64)
# e Ocp-Apim-Subscription-Key. Os valores vêm do .env (AUTOTRAC_USUARIO, AUTOTRAC_SENHA, AUTOTRAC_CHAVE) e não aparecem na tela.
#   sh scripts/n8n-credencial-autotrac.sh             # produção (VPS): valores reais do .env
#   sh scripts/n8n-credencial-autotrac.sh --sandbox   # computador do dev: valores fictícios (o sandbox aceita qualquer um)
# No modo --sandbox o parâmetro autotrac.url_telemetria do banco deve apontar para o sandbox (ver docs/montagem.md).
set -eu
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."

if [ "${1:-}" = "--sandbox" ]; then
  usuario="sandbox"; senha="sandbox"; chave="sandbox"
else
  ler() { sed -n "s/^$1=//p" .env | tr -d '\r' | head -1; }
  usuario=$(ler AUTOTRAC_USUARIO); senha=$(ler AUTOTRAC_SENHA); chave=$(ler AUTOTRAC_CHAVE)
  [ -n "$usuario" ] && [ -n "$senha" ] && [ -n "$chave" ] || { echo "AUTOTRAC_USUARIO, AUTOTRAC_SENHA ou AUTOTRAC_CHAVE vazio no .env"; exit 1; }
fi

# JSON montado dentro do container (node do n8n), lendo os valores do ambiente: nada passa pela linha de comando visível.
docker compose exec -T -e U="$usuario" -e S="$senha" -e K="$chave" n8n sh -c '
umask 077
node -e "
const h = { Authorization: \"Basic \" + process.env.U + \":\" + process.env.S, \"Ocp-Apim-Subscription-Key\": process.env.K };
process.stdout.write(JSON.stringify([{ id: \"TicAutotracApi01\", name: \"Autotrac (API)\", type: \"httpCustomAuth\",
  data: { json: JSON.stringify({ headers: h }) } }]));
" > /tmp/cred-autotrac.json
n8n import:credentials --input=/tmp/cred-autotrac.json > /dev/null; rc=$?
rm -f /tmp/cred-autotrac.json; exit $rc'
echo "credencial Autotrac (API) importada${1:+ ($1)}"
