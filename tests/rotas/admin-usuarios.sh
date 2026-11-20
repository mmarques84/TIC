#!/bin/sh
# Teste de ponta a ponta das rotas do Admin · Usuários (spec admin-usuarios) contra o ambiente LOCAL.
#   ADMIN_EMAIL=... ADMIN_SENHA=... sh tests/rotas/admin-usuarios.sh
# Cria um usuário fictício com e-mail único (teste.<hora>@exemplo.com) e o desativa no fim.
set -eu
API="${API:-http://localhost:8088/api}"
: "${ADMIN_EMAIL:?informe ADMIN_EMAIL}"; : "${ADMIN_SENHA:?informe ADMIN_SENHA}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
falhas=0
ok()  { echo "   ok:    $1"; }
nok() { echo "   FALHA: $1 ($2)"; falhas=$((falhas + 1)); }
confere() { [ "$2" = "$3" ] && ok "$1" || nok "$1" "esperado $3, veio $2"; }
xsrf() { awk '$6=="XSRF-TOKEN"{print $7}' "$1"; }
pedir() { # pedir <jar> <metodo> <rota> [corpo] → grava corpo em $T/r e devolve o status
  jar=$1; m=$2; r=$3; corpo=${4:-}
  if [ -n "$corpo" ]; then
    curl -s -o "$T/r" -w '%{http_code}' -b "$jar" -c "$jar" -X "$m" "$API/$r" -H 'Content-Type: application/json' -H "X-XSRF-TOKEN: $(xsrf "$jar")" -H 'Origin: http://127.0.0.1:4317' -d "$corpo"
  else
    curl -s -o "$T/r" -w '%{http_code}' -b "$jar" -c "$jar" -X "$m" "$API/$r" -H "X-XSRF-TOKEN: $(xsrf "$jar")"
  fi
}
campo() { node -e "const j=JSON.parse(require('fs').readFileSync(0,'utf8'));const v=($1);process.stdout.write(String(v))" < "$T/r"; }

echo "== Admin · Usuários (rotas) =="
A="$T/admin"; : > "$A"
confere "sem sessão → 401" "$(pedir "$A" GET admin/usuarios)" 401
confere "login do admin" "$(pedir "$A" POST auth/login "{\"email\":\"$ADMIN_EMAIL\",\"senha\":\"$ADMIN_SENHA\"}")" 200
confere "listar" "$(pedir "$A" GET admin/usuarios)" 200
confere "perfis (6)" "$(pedir "$A" GET admin/perfis >/dev/null; campo 'j.length')" 6

EMAIL="teste.$(date +%H%M%S)@exemplo.com"
st=$(pedir "$A" POST admin/usuarios "{\"nome\":\" Pessoa Teste \",\"email\":\" $(echo "$EMAIL" | tr a-z A-Z) \",\"perfil\":\"central\"}")
confere "criar → 201" "$st" 201
confere "e-mail normalizado" "$(campo 'j.email')" "$EMAIL"
ID=$(campo 'j.id')
confere "repetido → 409" "$(pedir "$A" POST admin/usuarios "{\"nome\":\"Outra\",\"email\":\"$EMAIL\",\"perfil\":\"central\"}")" 409
confere "perfil inválido → 400" "$(pedir "$A" POST admin/usuarios "{\"nome\":\"Outra\",\"email\":\"x$EMAIL\",\"perfil\":\"chefe\"}")" 400
confere "criar sem CSRF → 403" "$(curl -s -o /dev/null -w '%{http_code}' -b "$A" -X POST "$API/admin/usuarios" -H 'Content-Type: application/json' -d '{}')" 403

confere "gerar link" "$(pedir "$A" POST admin/usuarios/link-senha "{\"id\":\"$ID\"}")" 200
TOKEN=$(campo "j.link.split('token=')[1]")
U="$T/usuario"; : > "$U"; : > "$T/x"
confere "link válido" "$(pedir "$U" POST auth/senha/link "{\"token\":\"$TOKEN\"}")" 200
confere "senha fraca → 400" "$(pedir "$U" POST auth/senha/definir "{\"token\":\"$TOKEN\",\"senha\":\"curta\"}")" 400
confere "definir senha → entra" "$(pedir "$U" POST auth/senha/definir "{\"token\":\"$TOKEN\",\"senha\":\"Caminhao-Azul-2026!\"}")" 200
confere "já logado (me)" "$(pedir "$U" GET auth/me)" 200
confere "link usado de novo → 400" "$(pedir "$T/x" POST auth/senha/definir "{\"token\":\"$TOKEN\",\"senha\":\"Outra-Senha-2026!\"}")" 400
confere "central em admin → 403" "$(pedir "$U" GET admin/usuarios)" 403

confere "sessões da pessoa" "$(pedir "$A" GET "admin/sessoes?usuario=$ID" >/dev/null; campo 'j.length')" 1
confere "trocar perfil" "$(pedir "$A" PATCH "admin/usuarios?id=$ID" '{"perfil":"operacao"}')" 200
confere "sessão dela caiu → 401" "$(pedir "$U" GET auth/me)" 401
confere "desativar" "$(pedir "$A" PATCH "admin/usuarios?id=$ID" '{"ativo":false}')" 200
confere "link p/ inativo → 409" "$(pedir "$A" POST admin/usuarios/link-senha "{\"id\":\"$ID\"}")" 409
ME=$(pedir "$A" GET auth/me >/dev/null; campo 'j.id')
confere "desativar a si mesmo → 409" "$(pedir "$A" PATCH "admin/usuarios?id=$ME" '{"ativo":false}')" 409

echo "== rotas: $falhas falha(s) =="
[ "$falhas" -eq 0 ]
