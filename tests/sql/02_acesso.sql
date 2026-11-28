-- Login e sessão (spec seguranca-acesso). Transação desfeita no fim. Dados fictícios.
BEGIN;
SET ROLE tic_dono;

INSERT INTO acesso.usuario (id, nome, email, perfil, senha_hash) VALUES
  ('00000000-0000-7000-8000-00000000aa01', 'Operação Teste', 'op@exemplo.com', 'operacao', 'pbkdf2$sha512$1000$x$y'),
  ('00000000-0000-7000-8000-00000000aa02', 'Inativo Teste', 'inativo@exemplo.com', 'central', 'pbkdf2$sha512$1000$x$y');
UPDATE acesso.usuario SET ativo = false WHERE email = 'inativo@exemplo.com';

DO $$
DECLARE r record; s record; t record;
BEGIN
  -- R3: e-mail inexistente ainda devolve uma linha (sem usuário)
  SELECT * INTO r FROM acesso.sp_login_buscar('naoexiste@exemplo.com');
  ASSERT r.usuario_id IS NULL AND r.bloqueado = false, 'inexistente';
  -- e-mail é comparado em minúsculas
  SELECT * INTO r FROM acesso.sp_login_buscar('  OP@Exemplo.com ');
  ASSERT r.usuario_id = '00000000-0000-7000-8000-00000000aa01', 'busca por e-mail';
  -- inativo aparece como bloqueado
  SELECT * INTO r FROM acesso.sp_login_buscar('inativo@exemplo.com');
  ASSERT r.bloqueado, 'inativo bloqueado';

  -- R5: 5 erros seguidos bloqueiam
  FOR i IN 1..5 LOOP PERFORM acesso.sp_login_falha('op@exemplo.com', '10.0.0.1'); END LOOP;
  SELECT * INTO r FROM acesso.sp_login_buscar('op@exemplo.com');
  ASSERT r.bloqueado, 'deveria bloquear após 5 falhas';
  BEGIN
    PERFORM acesso.sp_sessao_criar('00000000-0000-7000-8000-00000000aa01', repeat('a', 64), repeat('b', 64), NULL, 'teste');
    RAISE EXCEPTION 'não deveria criar sessão bloqueado';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'USUARIO_INATIVO' THEN RAISE; END IF;
  END;
  UPDATE acesso.usuario SET bloqueado_ate = NULL WHERE email = 'op@exemplo.com';

  -- Sessão nova e autorização
  SELECT * INTO s FROM acesso.sp_sessao_criar('00000000-0000-7000-8000-00000000aa01', repeat('a', 64), repeat('b', 64), '10.0.0.1', 'teste');
  ASSERT s.sessao_id IS NOT NULL, 'sessão criada';
  ASSERT (SELECT tentativas_falhas FROM acesso.usuario WHERE email = 'op@exemplo.com') = 0, 'zera tentativas';

  SELECT * INTO t FROM acesso.sp_autorizar(repeat('a', 64), '', 'GET', 'jornada.ver');
  ASSERT t.status = 'ok' AND t.perfil = 'operacao', 'GET com permissão';
  SELECT * INTO t FROM acesso.sp_autorizar(repeat('a', 64), '', 'GET', 'usuario.gerir');
  ASSERT t.status = 'proibido', 'sem permissão = proibido';
  SELECT * INTO t FROM acesso.sp_autorizar(repeat('a', 64), repeat('c', 64), 'POST', NULL);
  ASSERT t.status = 'csrf', 'POST sem CSRF certo';
  SELECT * INTO t FROM acesso.sp_autorizar(repeat('a', 64), repeat('b', 64), 'POST', NULL);
  ASSERT t.status = 'ok', 'POST com CSRF';
  SELECT * INTO t FROM acesso.sp_autorizar(repeat('f', 64), '', 'GET', NULL);
  ASSERT t.status = 'sem_sessao', 'token desconhecido';

  -- Me
  ASSERT (SELECT usuario->>'perfil' FROM acesso.sp_auth_me('00000000-0000-7000-8000-00000000aa01')) = 'operacao', 'me';
  ASSERT jsonb_array_length((SELECT usuario->'permissoes' FROM acesso.sp_auth_me('00000000-0000-7000-8000-00000000aa01'))) = 10, 'me permissões'; -- 9 + conducao.ver (migration 018)

  -- Logout derruba a sessão
  PERFORM acesso.sp_logout(s.sessao_id, NULL);
  SELECT * INTO t FROM acesso.sp_autorizar(repeat('a', 64), '', 'GET', NULL);
  ASSERT t.status = 'sem_sessao', 'depois do logout';

  -- Auditoria registrou
  ASSERT (SELECT count(*) FROM controle.auditoria WHERE acao = 'acesso.login_falha') >= 5, 'audita falhas';
  ASSERT EXISTS (SELECT 1 FROM controle.auditoria WHERE acao = 'acesso.bloqueio'), 'audita bloqueio';
  ASSERT EXISTS (SELECT 1 FROM controle.auditoria WHERE acao = 'acesso.login'), 'audita login';
  ASSERT EXISTS (SELECT 1 FROM controle.auditoria WHERE acao = 'acesso.logout'), 'audita logout';
END $$;

RESET ROLE;
DO $$ BEGIN
  ASSERT has_function_privilege('tic_n8n', 'acesso.sp_login_buscar(text)', 'EXECUTE'), 'n8n executa sp_login_buscar';
  ASSERT has_function_privilege('tic_n8n', 'acesso.sp_autorizar(text,text,text,text)', 'EXECUTE'), 'n8n executa sp_autorizar';
  ASSERT NOT has_function_privilege('tic_n8n', 'controle.fn_parametro(text,uuid,timestamptz)', 'EXECUTE'), 'n8n não executa fn_*';
END $$;
ROLLBACK;
