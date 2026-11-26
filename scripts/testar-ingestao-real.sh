#!/bin/sh
# Teste ponta a ponta da ingestão da Autotrac com a CONTA REAL, no computador do dev (spec ingestao-autotrac V13).
# Quem roda é o Marcus (usa AUTOTRAC_* do .env). Mostra só contagens; no fim APAGA tudo o que veio de real
# e volta o banco e a credencial para o sandbox (regra do projeto: dado real não fica no computador do dev).
#   sh scripts/testar-ingestao-real.sh [quantos veículos, padrão 3]
set -eu
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
N="${1:-3}"

# SQL sempre pela entrada padrão (heredoc).
sql() { docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -q -X'; }
valor() { docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -q -X -t -A' | tr -d '\r'; }
executar() { docker compose exec -T -e N8N_RUNNERS_BROKER_PORT=5699 -e N8N_PORT=5690 n8n n8n execute --id="$1" > /dev/null 2>&1 || true; }

conta=$(sed -n 's/^AUTOTRAC_CONTA=//p' .env | tr -d '\r' | head -1); conta="${conta:-10534}"
inicio=$(echo "SELECT now();" | valor)
# Veículos fictícios ligados ao sandbox: desligados durante o teste e religados no fim.
ligados=$(echo "SELECT coalesce(string_agg(placa || '=' || id_autotrac, ' '), '') FROM cadastro.veiculo WHERE id_autotrac IS NOT NULL;" | valor)

voltar() {
  echo "== limpando o que veio da conta real e voltando para o sandbox"
  sql <<SQL
DELETE FROM bruto.autotrac_evento WHERE recebido_em >= '$inicio';
DELETE FROM controle.saneamento WHERE fonte = 'autotrac' AND primeiro_em >= '$inicio';
DELETE FROM cadastro.veiculo WHERE frota = 'TESTE-REAL' AND criado_em >= '$inicio';
DELETE FROM bruto.ingestao_lote WHERE inicio >= '$inicio';
UPDATE controle.parametro SET valor = '"https://wapi.autotrac-online.com.br/sandboxtelemetryapi"' WHERE chave = 'autotrac.url_telemetria';
UPDATE controle.parametro SET valor = '3253' WHERE chave = 'autotrac.conta_telemetria';
UPDATE controle.credencial_status SET senha_mudou = false WHERE fonte = 'autotrac';
SQL
  for par in $ligados; do
    echo "UPDATE cadastro.veiculo SET id_autotrac = '${par#*=}' WHERE placa = '${par%%=*}';" | sql
  done
  sh scripts/n8n-credencial-autotrac.sh --sandbox > /dev/null
  echo "== pronto: computador de volta ao sandbox; nada da conta real ficou no banco"
}
trap voltar EXIT

echo "== 1. apontando para a API real (conta $conta) e carregando a credencial do .env"
sql <<SQL
UPDATE controle.parametro SET valor = '"https://aapi4.autotrac-online.com.br/telemetryapi"' WHERE chave = 'autotrac.url_telemetria';
UPDATE controle.parametro SET valor = '$conta' WHERE chave = 'autotrac.conta_telemetria';
UPDATE cadastro.veiculo SET id_autotrac = NULL WHERE id_autotrac IS NOT NULL;
SQL
sh scripts/n8n-credencial-autotrac.sh > /dev/null

echo "== 2. buscando a frota real"
executar TicIngAutotracCa
sql <<SQL
SELECT estado AS "lote da frota", coalesce(erro, '') AS erro FROM bruto.ingestao_lote WHERE fonte = 'autotrac_cadastro' AND inicio >= '$inicio';
SELECT motivo, count(*) AS itens FROM controle.saneamento WHERE fonte = 'autotrac' AND primeiro_em >= '$inicio' GROUP BY motivo ORDER BY 2 DESC;
SQL

echo "== 3. ligando $N veículos reais (temporários) e buscando os eventos das últimas 24 h"
sql <<SQL
INSERT INTO cadastro.veiculo (placa, tipo, frota, origem, id_autotrac)
SELECT s.dados->>'placa', 'cavalo', 'TESTE-REAL', 'manual', s.dados->>'codigo'
FROM controle.saneamento s
WHERE s.fonte = 'autotrac' AND s.motivo = 'placa_sem_cadastro' AND s.primeiro_em >= '$inicio'
  AND s.dados->>'placa' ~ '^[A-Z]{3}[0-9][A-Z0-9][0-9]{2}$'
ORDER BY s.chave LIMIT $N
ON CONFLICT (placa) DO NOTHING;
SQL
executar TicIngAutotracEv
sql <<SQL
SELECT estado AS "lote de eventos", linhas AS "eventos gravados", coalesce(erro, '') AS erro FROM bruto.ingestao_lote WHERE fonte = 'autotrac_evento' AND inicio >= '$inicio';
SELECT e.dados->>'fonte' AS api, e.tipo, count(*) AS eventos, count(e.motorista_id) AS com_motorista, count(e.codigo_motorista) AS com_codigo_motorista
FROM bruto.autotrac_evento e WHERE e.recebido_em >= '$inicio' GROUP BY 1, 2 ORDER BY 1, 3 DESC;
SELECT ultimo_sucesso, ultimo_http, coalesce(ultimo_erro, '') AS ultimo_erro, senha_mudou FROM controle.credencial_status WHERE fonte = 'autotrac';
SQL
