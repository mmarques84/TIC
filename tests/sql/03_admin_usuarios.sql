-- Admin · Usuários e perfis (spec admin-usuarios). Transação desfeita no fim. Dados fictícios.
BEGIN;
SET ROLE tic_dono;

INSERT INTO acesso.usuario (id, nome, email, perfil, senha_hash) VALUES
  ('00000000-0000-7000-8000-00000000ad01', 'Admin Teste', 'admin.teste@exemplo.com', 'admin', 'pbkdf2$sha512$1000$x$y'),
  ('00000000-0000-7000-8000-00000000ad02', 'Operação Teste', 'op.teste@exemplo.com', 'operacao', 'pbkdf2$sha512$1000$x$y');

DO $$
DECLARE
  adm uuid := '00000000-0000-7000-8000-00000000ad01';
  op  uuid := '00000000-0000-7000-8000-00000000ad02';
  novo jsonb; r record; t record; v_id uuid; n integer;
BEGIN
  -- V1 (R1): sem a permissão → SEM_PERMISSAO
  BEGIN PERFORM acesso.sp_usuario_listar(op); RAISE EXCEPTION 'deveria negar';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'SEM_PERMISSAO' THEN RAISE; END IF; END;

  -- V3 (R4, R5): e-mail normalizado, nasce ativo e sem senha
  SELECT usuario INTO novo FROM acesso.sp_usuario_criar(adm, ' João Exemplo ', ' Joao@Exemplo.com ', 'central', true, NULL, NULL);
  ASSERT novo->>'email' = 'joao@exemplo.com' AND (novo->>'ativo')::boolean AND NOT (novo->>'temSenha')::boolean, 'cadastro';
  v_id := (novo->>'id')::uuid;
  BEGIN PERFORM acesso.sp_usuario_criar(adm, 'Outro', 'JOAO@exemplo.com', 'central', true, NULL, NULL); RAISE EXCEPTION 'deveria recusar repetido';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'EMAIL_JA_CADASTRADO' THEN RAISE; END IF; END;
  -- V4 (R6)
  BEGIN PERFORM acesso.sp_usuario_criar(adm, 'Outro', 'outro@exemplo.com', 'chefe', true, NULL, NULL); RAISE EXCEPTION 'deveria recusar perfil';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'PERFIL_INVALIDO' THEN RAISE; END IF; END;

  -- V2 (R2, R3): ativos primeiro
  SELECT jsonb_array_length(usuarios) INTO n FROM acesso.sp_usuario_listar(adm);
  ASSERT n >= 3, 'lista';
  ASSERT (SELECT (usuarios->0->>'ativo')::boolean FROM acesso.sp_usuario_listar(adm)), 'ativos primeiro';
  ASSERT (SELECT jsonb_array_length(perfis) FROM acesso.sp_perfil_listar(adm)) = 6, 'perfis';

  -- V7 (R11–R14): link → validar → definir senha → link queimado
  PERFORM acesso.sp_definicao_criar(adm, v_id, repeat('1', 64), NULL);
  SELECT * INTO r FROM acesso.sp_definicao_validar(repeat('1', 64));
  ASSERT r.valido AND r.email = 'joao@exemplo.com', 'link válido';
  -- link novo invalida o anterior
  PERFORM acesso.sp_definicao_criar(adm, v_id, repeat('2', 64), NULL);
  SELECT * INTO r FROM acesso.sp_definicao_validar(repeat('1', 64));
  ASSERT NOT r.valido, 'link antigo invalidado';
  PERFORM acesso.sp_senha_definir(repeat('2', 64), 'pbkdf2$sha512$1000$a$b', NULL);
  ASSERT (SELECT senha_hash FROM acesso.usuario WHERE id = v_id) = 'pbkdf2$sha512$1000$a$b', 'senha gravada';
  BEGIN PERFORM acesso.sp_senha_definir(repeat('2', 64), 'pbkdf2$sha512$1000$c$d', NULL); RAISE EXCEPTION 'link usado de novo';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'LINK_INVALIDO' THEN RAISE; END IF; END;
  ASSERT NOT EXISTS (SELECT 1 FROM controle.auditoria WHERE depois::text LIKE '%' || repeat('2', 64) || '%'), 'link/token fora da auditoria';

  -- V5 (R8): trocar perfil derruba as sessões
  PERFORM acesso.sp_sessao_criar(v_id, repeat('a', 64), repeat('b', 64), NULL, 't');
  SELECT * INTO t FROM acesso.sp_usuario_atualizar(adm, v_id, NULL, NULL, 'operacao', NULL, NULL, NULL, NULL);
  ASSERT t.sessoes_encerradas = 1 AND t.usuario->>'perfil' = 'operacao', 'troca de perfil';
  SELECT * INTO r FROM acesso.sp_autorizar(repeat('a', 64), '', 'GET', NULL);
  ASSERT r.status = 'sem_sessao', 'sessão caiu';

  -- V8 (R13): inativo não recebe link
  PERFORM acesso.sp_usuario_atualizar(adm, v_id, NULL, NULL, NULL, false, NULL, NULL, NULL);
  BEGIN PERFORM acesso.sp_definicao_criar(adm, v_id, repeat('3', 64), NULL); RAISE EXCEPTION 'inativo';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'USUARIO_INATIVO' THEN RAISE; END IF; END;
  -- R9: reativar
  SELECT * INTO t FROM acesso.sp_usuario_atualizar(adm, v_id, NULL, NULL, NULL, true, NULL, NULL, NULL);
  ASSERT (t.usuario->>'ativo')::boolean, 'reativado';

  -- V6 (R10): não desativa a si mesmo; não rebaixa o último admin
  BEGIN PERFORM acesso.sp_usuario_atualizar(adm, adm, NULL, NULL, NULL, false, NULL, NULL, NULL); RAISE EXCEPTION 'a si mesmo';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'PROPRIO_USUARIO' THEN RAISE; END IF; END;
  UPDATE acesso.usuario SET ativo = false WHERE perfil = 'admin' AND id <> adm;  -- só ele de admin ativo
  PERFORM acesso.sp_usuario_atualizar(adm, v_id, NULL, NULL, 'admin', NULL, NULL, NULL, NULL);  -- agora são dois
  UPDATE acesso.usuario SET ativo = false WHERE id = adm;  -- simula: só o v_id de admin ativo
  BEGIN PERFORM acesso.sp_usuario_atualizar(v_id, v_id, NULL, NULL, NULL, false, NULL, NULL, NULL); RAISE EXCEPTION 'último admin';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT IN ('PROPRIO_USUARIO', 'ULTIMO_ADMIN') THEN RAISE; END IF; END;
  UPDATE acesso.usuario SET ativo = true WHERE id = adm;

  -- V9 (R15): encerrar uma / todas
  PERFORM acesso.sp_sessao_criar(op, repeat('c', 64), repeat('d', 64), NULL, 't1');
  PERFORM acesso.sp_sessao_criar(op, repeat('e', 64), repeat('f', 64), NULL, 't2');
  SELECT jsonb_array_length(sessoes) INTO n FROM acesso.sp_sessao_listar(adm, op);
  ASSERT n = 2, 'duas sessões';
  PERFORM acesso.sp_sessao_revogar(adm, (SELECT id FROM acesso.sessao WHERE token_hash = repeat('c', 64)), NULL);
  ASSERT (SELECT status FROM acesso.sp_autorizar(repeat('c', 64), '', 'GET', NULL)) = 'sem_sessao', 'uma caiu';
  ASSERT (SELECT status FROM acesso.sp_autorizar(repeat('e', 64), '', 'GET', NULL)) = 'ok', 'a outra segue';
  SELECT encerradas INTO n FROM acesso.sp_sessao_revogar_todas(adm, op, NULL);
  ASSERT n = 1, 'encerrar todas';

  -- V10 (R16): autoria na auditoria
  ASSERT EXISTS (SELECT 1 FROM controle.auditoria WHERE acao = 'usuario.criar' AND usuario_id = adm), 'audita criar';
  ASSERT EXISTS (SELECT 1 FROM controle.auditoria WHERE acao = 'usuario.editar' AND usuario_id = adm AND antes IS NOT NULL), 'audita editar';
  ASSERT EXISTS (SELECT 1 FROM controle.auditoria WHERE acao = 'senha.link_criado' AND usuario_id = adm), 'audita link';
  ASSERT EXISTS (SELECT 1 FROM controle.auditoria WHERE acao = 'senha.definida'), 'audita senha';
  ASSERT EXISTS (SELECT 1 FROM controle.auditoria WHERE acao = 'sessao.revogar' AND usuario_id = adm), 'audita sessão';
END $$;

RESET ROLE;
DO $$ BEGIN
  ASSERT has_function_privilege('tic_n8n', 'acesso.sp_usuario_criar(uuid,text,text,text,boolean,uuid[],inet)', 'EXECUTE'), 'n8n cria';
  ASSERT NOT has_function_privilege('tic_n8n', 'acesso.int_exigir(uuid,text)', 'EXECUTE'), 'int_* fechado';
END $$;
ROLLBACK;
