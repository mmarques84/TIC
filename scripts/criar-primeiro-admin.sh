#!/bin/sh
# Cria o PRIMEIRO administrador de um banco novo (VPS) e devolve um link de uso único para ele criar a própria senha.
# Nenhuma senha passa por aqui: o banco guarda só o hash do link (como o "Gerar link de senha" do Admin).
#   sh scripts/criar-primeiro-admin.sh admin@mxmidas.com "Administrador" https://paineldigital.tic.com.br
# Só funciona se ainda não houver nenhum usuário admin ativo (para não virar porta dos fundos).
set -eu
export MSYS_NO_PATHCONV=1
cd "$(dirname "$0")/.."
email="${1:?informe o e-mail}"; nome="${2:-Administrador}"; site="${3:?informe o endereço do painel}"
case "$email" in *\'*|*\ *) echo "e-mail inválido"; exit 1;; esac
case "$nome" in *\'*) echo "nome inválido"; exit 1;; esac

token=$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '=\n')
hash=$(printf '%s' "$token" | openssl dgst -sha256 -r | cut -d' ' -f1)

docker compose exec -T postgres psql -U tic_admin -d tic -v ON_ERROR_STOP=1 -q -t -A <<SQL
BEGIN;
SET ROLE tic_dono;
DO \$\$
DECLARE v uuid;
BEGIN
  IF EXISTS (SELECT 1 FROM acesso.usuario WHERE perfil = 'admin' AND ativo) THEN
    RAISE EXCEPTION 'Já existe administrador ativo: use o Admin do painel para criar usuários.';
  END IF;
  INSERT INTO acesso.usuario (nome, email, perfil, todas_operacoes, ativo)
  VALUES ('$nome', lower('$email'), 'admin', true, true) RETURNING id INTO v;
  INSERT INTO acesso.definicao_senha (usuario_id, token_hash, tipo, criado_por, expira_em)
  VALUES (v, '$hash', 'convite', NULL, now() + interval '48 hours');
  INSERT INTO controle.auditoria (usuario_id, acao, entidade, entidade_id, antes, depois)
  VALUES (NULL, 'usuario.criar', 'acesso.usuario', v::text, NULL,
          jsonb_build_object('email', lower('$email'), 'perfil', 'admin', 'origem', 'scripts/criar-primeiro-admin.sh'));
END \$\$;
COMMIT;
SQL
echo "Administrador $email criado. Link para criar a senha (uso único, vale 48 h):"
echo "$site/definir-senha?token=$token"
