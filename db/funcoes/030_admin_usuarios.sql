-- Casos de uso do Admin · Usuários e perfis e da criação de senha pelo link (spec admin-usuarios).
-- Recriadas a cada deploy. Toda função devolve exatamente uma linha (ou um conjunto, na listagem).
-- Erros de regra: RAISE EXCEPTION '<CODIGO>' (o n8n traduz em HTTP).

-- Apoio (não exposto ao n8n): exige a permissão ou levanta SEM_PERMISSAO.
CREATE OR REPLACE FUNCTION acesso.int_exigir(p_usuario_id uuid, p_permissao text)
RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM acesso.usuario u JOIN acesso.perfil_permissao pp ON pp.perfil = u.perfil
    WHERE u.id = p_usuario_id AND u.ativo AND pp.permissao = p_permissao) THEN
    RAISE EXCEPTION 'SEM_PERMISSAO' USING ERRCODE = 'P0001';
  END IF;
END $$;

-- Apoio: encerra todas as sessões abertas de uma pessoa.
CREATE OR REPLACE FUNCTION acesso.int_revogar_sessoes(p_usuario_id uuid)
RETURNS integer
LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  WITH r AS (UPDATE acesso.sessao SET revogada_em = now() WHERE usuario_id = p_usuario_id AND revogada_em IS NULL RETURNING 1)
  SELECT count(*)::integer FROM r
$$;

-- Apoio: o retrato de uma pessoa como a tela mostra.
CREATE OR REPLACE FUNCTION acesso.int_usuario_json(p_id uuid)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT jsonb_build_object(
    'id', u.id, 'nome', u.nome, 'email', u.email, 'perfil', u.perfil, 'perfilNome', p.nome,
    'todasOperacoes', u.todas_operacoes,
    'operacoes', coalesce((SELECT jsonb_agg(jsonb_build_object('id', o.id, 'nome', o.nome) ORDER BY o.nome)
                           FROM acesso.usuario_operacao uo JOIN cadastro.operacao o ON o.id = uo.operacao_id WHERE uo.usuario_id = u.id), '[]'),
    'ativo', u.ativo,
    'temSenha', u.senha_hash IS NOT NULL,
    'bloqueado', coalesce(u.bloqueado_ate > now(), false),
    'ultimoAcesso', (SELECT max(s.ultimo_uso_em) FROM acesso.sessao s WHERE s.usuario_id = u.id),
    'sessoesAbertas', (SELECT count(*) FROM acesso.sessao s WHERE s.usuario_id = u.id AND s.revogada_em IS NULL AND s.expira_em > now())
  )
  FROM acesso.usuario u JOIN acesso.perfil p ON p.codigo = u.perfil
  WHERE u.id = p_id
$$;

-- Listas devolvem UMA linha com a lista em jsonb (lista vazia = []), porque o nó Postgres do n8n
-- não emite item quando não há linha e a rota ficaria sem resposta.
DROP FUNCTION IF EXISTS acesso.sp_usuario_listar(uuid);
DROP FUNCTION IF EXISTS acesso.sp_perfil_listar(uuid);
DROP FUNCTION IF EXISTS acesso.sp_sessao_listar(uuid, uuid);

-- R2, R3: lista completa, ativos primeiro e por nome (a busca é feita na tela).
CREATE FUNCTION acesso.sp_usuario_listar(p_admin uuid)
RETURNS TABLE (usuarios jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  PERFORM acesso.int_exigir(p_admin, 'usuario.gerir');
  RETURN QUERY
    SELECT coalesce(jsonb_agg(acesso.int_usuario_json(u.id) ORDER BY u.ativo DESC, lower(u.nome)), '[]')
    FROM acesso.usuario u;
END $$;

-- Perfis para o formulário (lista fechada, R6).
CREATE FUNCTION acesso.sp_perfil_listar(p_admin uuid)
RETURNS TABLE (perfis jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  PERFORM acesso.int_exigir(p_admin, 'usuario.gerir');
  RETURN QUERY SELECT jsonb_agg(jsonb_build_object('codigo', p.codigo, 'nome', p.nome, 'descricao', p.descricao)
      ORDER BY array_position(ARRAY['diretoria','operacao','frota_opi','central','ti','admin'], p.codigo))
    FROM acesso.perfil p;
END $$;

-- Apoio: valida e grava as operações do usuário (R7). NULL ou vazio com p_todas = true → todas.
CREATE OR REPLACE FUNCTION acesso.int_definir_operacoes(p_usuario uuid, p_todas boolean, p_operacoes uuid[])
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  IF NOT p_todas AND coalesce(cardinality(p_operacoes), 0) = 0 THEN
    RAISE EXCEPTION 'OPERACAO_OBRIGATORIA' USING ERRCODE = 'P0001';
  END IF;
  IF NOT p_todas AND EXISTS (SELECT 1 FROM unnest(p_operacoes) o WHERE NOT EXISTS (SELECT 1 FROM cadastro.operacao c WHERE c.id = o AND c.ativa)) THEN
    RAISE EXCEPTION 'OPERACAO_INVALIDA' USING ERRCODE = 'P0001';
  END IF;
  UPDATE acesso.usuario SET todas_operacoes = p_todas WHERE id = p_usuario;
  DELETE FROM acesso.usuario_operacao WHERE usuario_id = p_usuario;
  IF NOT p_todas THEN
    INSERT INTO acesso.usuario_operacao (usuario_id, operacao_id) SELECT p_usuario, DISTINCT_o FROM (SELECT DISTINCT unnest(p_operacoes) AS DISTINCT_o) x;
  END IF;
END $$;

-- R4–R7: cadastro. Nasce ativo e sem senha.
CREATE OR REPLACE FUNCTION acesso.sp_usuario_criar(p_admin uuid, p_nome text, p_email text, p_perfil text, p_todas boolean, p_operacoes uuid[], p_ip inet)
RETURNS TABLE (usuario jsonb)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE v_id uuid; v_email text := lower(btrim(p_email)); v_nome text := btrim(p_nome);
BEGIN
  PERFORM acesso.int_exigir(p_admin, 'usuario.gerir');
  IF coalesce(length(v_nome), 0) < 2 THEN RAISE EXCEPTION 'NOME_OBRIGATORIO' USING ERRCODE = 'P0001'; END IF;
  IF v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN RAISE EXCEPTION 'EMAIL_INVALIDO' USING ERRCODE = 'P0001'; END IF;
  IF NOT EXISTS (SELECT 1 FROM acesso.perfil WHERE codigo = p_perfil) THEN RAISE EXCEPTION 'PERFIL_INVALIDO' USING ERRCODE = 'P0001'; END IF;
  IF EXISTS (SELECT 1 FROM acesso.usuario WHERE email = v_email) THEN RAISE EXCEPTION 'EMAIL_JA_CADASTRADO' USING ERRCODE = 'P0001'; END IF;

  INSERT INTO acesso.usuario (nome, email, perfil) VALUES (v_nome, v_email, p_perfil) RETURNING id INTO v_id;
  PERFORM acesso.int_definir_operacoes(v_id, coalesce(p_todas, true), p_operacoes);

  INSERT INTO controle.auditoria (usuario_id, acao, entidade, entidade_id, depois, ip)
  VALUES (p_admin, 'usuario.criar', 'acesso.usuario', v_id::text, acesso.int_usuario_json(v_id), p_ip);
  RETURN QUERY SELECT acesso.int_usuario_json(v_id);
END $$;

-- R8–R10: edição. Parâmetro NULL = não muda. Perfil, operações ou desativar encerram as sessões.
CREATE OR REPLACE FUNCTION acesso.sp_usuario_atualizar(p_admin uuid, p_id uuid, p_nome text, p_email text, p_perfil text,
                                                        p_ativo boolean, p_todas boolean, p_operacoes uuid[], p_ip inet)
RETURNS TABLE (usuario jsonb, sessoes_encerradas integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE
  v_antes jsonb; u acesso.usuario%ROWTYPE; v_email text := lower(btrim(p_email)); v_nome text := btrim(p_nome);
  v_derruba boolean := false; v_encerradas integer := 0;
BEGIN
  PERFORM acesso.int_exigir(p_admin, 'usuario.gerir');
  SELECT * INTO u FROM acesso.usuario WHERE id = p_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'NAO_ENCONTRADO' USING ERRCODE = 'P0001'; END IF;
  v_antes := acesso.int_usuario_json(p_id);

  IF p_nome IS NOT NULL AND length(v_nome) < 2 THEN RAISE EXCEPTION 'NOME_OBRIGATORIO' USING ERRCODE = 'P0001'; END IF;
  IF p_email IS NOT NULL THEN
    IF v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN RAISE EXCEPTION 'EMAIL_INVALIDO' USING ERRCODE = 'P0001'; END IF;
    IF EXISTS (SELECT 1 FROM acesso.usuario WHERE email = v_email AND id <> p_id) THEN RAISE EXCEPTION 'EMAIL_JA_CADASTRADO' USING ERRCODE = 'P0001'; END IF;
  END IF;
  IF p_perfil IS NOT NULL AND NOT EXISTS (SELECT 1 FROM acesso.perfil WHERE codigo = p_perfil) THEN
    RAISE EXCEPTION 'PERFIL_INVALIDO' USING ERRCODE = 'P0001';
  END IF;

  -- R10: ninguém desativa a si mesmo nem deixa o portal sem admin ativo.
  IF p_id = p_admin AND (p_ativo IS FALSE OR (p_perfil IS NOT NULL AND p_perfil <> u.perfil)) THEN
    RAISE EXCEPTION 'PROPRIO_USUARIO' USING ERRCODE = 'P0001';
  END IF;
  IF u.perfil = 'admin' AND u.ativo AND (p_ativo IS FALSE OR (p_perfil IS NOT NULL AND p_perfil <> 'admin'))
     AND NOT EXISTS (SELECT 1 FROM acesso.usuario WHERE perfil = 'admin' AND ativo AND id <> p_id) THEN
    RAISE EXCEPTION 'ULTIMO_ADMIN' USING ERRCODE = 'P0001';
  END IF;

  v_derruba := (p_perfil IS NOT NULL AND p_perfil <> u.perfil) OR (p_ativo IS FALSE AND u.ativo) OR p_todas IS NOT NULL;

  UPDATE acesso.usuario SET
    nome = coalesce(v_nome, nome),
    email = coalesce(v_email, email),
    perfil = coalesce(p_perfil, perfil),
    ativo = coalesce(p_ativo, ativo),
    bloqueado_ate = CASE WHEN p_ativo IS TRUE THEN NULL ELSE bloqueado_ate END,
    tentativas_falhas = CASE WHEN p_ativo IS TRUE THEN 0 ELSE tentativas_falhas END,
    atualizado_em = now()
  WHERE id = p_id;

  IF p_todas IS NOT NULL THEN
    PERFORM acesso.int_definir_operacoes(p_id, p_todas, p_operacoes);
  END IF;
  IF v_derruba THEN
    v_encerradas := acesso.int_revogar_sessoes(p_id);
  END IF;

  INSERT INTO controle.auditoria (usuario_id, acao, entidade, entidade_id, antes, depois, ip)
  VALUES (p_admin, 'usuario.editar', 'acesso.usuario', p_id::text, v_antes, acesso.int_usuario_json(p_id), p_ip);
  RETURN QUERY SELECT acesso.int_usuario_json(p_id), v_encerradas;
END $$;

-- R11–R13: link de senha (o n8n gera o token; aqui chega só o hash). Novo link invalida os anteriores.
CREATE OR REPLACE FUNCTION acesso.sp_definicao_criar(p_admin uuid, p_id uuid, p_token_hash text, p_ip inet)
RETURNS TABLE (expira_em timestamptz, tipo text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE u acesso.usuario%ROWTYPE; v_tipo text; v_expira timestamptz := now() + interval '24 hours';
BEGIN
  PERFORM acesso.int_exigir(p_admin, 'usuario.gerir');
  SELECT * INTO u FROM acesso.usuario WHERE id = p_id;
  IF u.id IS NULL THEN RAISE EXCEPTION 'NAO_ENCONTRADO' USING ERRCODE = 'P0001'; END IF;
  IF NOT u.ativo THEN RAISE EXCEPTION 'USUARIO_INATIVO' USING ERRCODE = 'P0001'; END IF;
  v_tipo := CASE WHEN u.senha_hash IS NULL THEN 'convite' ELSE 'recuperacao' END;

  UPDATE acesso.definicao_senha SET usado_em = now() WHERE usuario_id = p_id AND usado_em IS NULL AND expira_em > now();
  INSERT INTO acesso.definicao_senha (usuario_id, token_hash, tipo, criado_por, expira_em)
  VALUES (p_id, p_token_hash, v_tipo, p_admin, v_expira);

  INSERT INTO controle.auditoria (usuario_id, acao, entidade, entidade_id, depois, ip)
  VALUES (p_admin, 'senha.link_criado', 'acesso.usuario', p_id::text, jsonb_build_object('tipo', v_tipo, 'expira_em', v_expira), p_ip);
  RETURN QUERY SELECT v_expira, v_tipo;
END $$;

-- Anônima: o link ainda vale? (para a tela de criar senha)
CREATE OR REPLACE FUNCTION acesso.sp_definicao_validar(p_token_hash text)
RETURNS TABLE (valido boolean, nome text, email text, perfil text, expira_em timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT (d.id IS NOT NULL), u.nome, u.email, u.perfil, d.expira_em
  FROM (SELECT 1) x
  LEFT JOIN acesso.definicao_senha d ON d.token_hash = p_token_hash AND d.usado_em IS NULL AND d.expira_em > now()
  LEFT JOIN acesso.usuario u ON u.id = d.usuario_id AND u.ativo
$$;

-- R14: grava a senha (hash já calculado pelo n8n), queima o link e encerra sessões antigas.
CREATE OR REPLACE FUNCTION acesso.sp_senha_definir(p_token_hash text, p_senha_hash text, p_ip inet)
RETURNS TABLE (usuario_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE d acesso.definicao_senha%ROWTYPE;
BEGIN
  SELECT * INTO d FROM acesso.definicao_senha
  WHERE token_hash = p_token_hash AND usado_em IS NULL AND expira_em > now() FOR UPDATE;
  IF d.id IS NULL OR NOT EXISTS (SELECT 1 FROM acesso.usuario WHERE id = d.usuario_id AND ativo) THEN
    RAISE EXCEPTION 'LINK_INVALIDO' USING ERRCODE = 'P0001';
  END IF;
  UPDATE acesso.definicao_senha SET usado_em = now() WHERE id = d.id;
  UPDATE acesso.usuario SET senha_hash = p_senha_hash, tentativas_falhas = 0, bloqueado_ate = NULL, atualizado_em = now() WHERE id = d.usuario_id;
  PERFORM acesso.int_revogar_sessoes(d.usuario_id);
  INSERT INTO controle.auditoria (usuario_id, acao, entidade, entidade_id, depois, ip)
  VALUES (d.usuario_id, 'senha.definida', 'acesso.usuario', d.usuario_id::text, jsonb_build_object('tipo', d.tipo), p_ip);
  RETURN QUERY SELECT d.usuario_id;
END $$;

-- R15: sessões abertas de uma pessoa.
CREATE FUNCTION acesso.sp_sessao_listar(p_admin uuid, p_usuario uuid)
RETURNS TABLE (sessoes jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  PERFORM acesso.int_exigir(p_admin, 'usuario.gerir');
  RETURN QUERY
    SELECT coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'criadaEm', s.criada_em, 'ultimoUsoEm', s.ultimo_uso_em,
                              'expiraEm', s.expira_em, 'ip', host(s.ip), 'userAgent', s.user_agent) ORDER BY s.ultimo_uso_em DESC), '[]')
    FROM acesso.sessao s
    WHERE s.usuario_id = p_usuario AND s.revogada_em IS NULL AND s.expira_em > now();
END $$;

CREATE OR REPLACE FUNCTION acesso.sp_sessao_revogar(p_admin uuid, p_sessao uuid, p_ip inet)
RETURNS TABLE (ok boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE v_usuario uuid;
BEGIN
  PERFORM acesso.int_exigir(p_admin, 'usuario.gerir');
  UPDATE acesso.sessao SET revogada_em = now() WHERE id = p_sessao AND revogada_em IS NULL RETURNING usuario_id INTO v_usuario;
  IF v_usuario IS NULL THEN RAISE EXCEPTION 'NAO_ENCONTRADO' USING ERRCODE = 'P0001'; END IF;
  INSERT INTO controle.auditoria (usuario_id, acao, entidade, entidade_id, depois, ip)
  VALUES (p_admin, 'sessao.revogar', 'acesso.sessao', p_sessao::text, jsonb_build_object('usuario', v_usuario), p_ip);
  RETURN QUERY SELECT true;
END $$;

CREATE OR REPLACE FUNCTION acesso.sp_sessao_revogar_todas(p_admin uuid, p_usuario uuid, p_ip inet)
RETURNS TABLE (encerradas integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE v integer;
BEGIN
  PERFORM acesso.int_exigir(p_admin, 'usuario.gerir');
  IF NOT EXISTS (SELECT 1 FROM acesso.usuario WHERE id = p_usuario) THEN RAISE EXCEPTION 'NAO_ENCONTRADO' USING ERRCODE = 'P0001'; END IF;
  v := acesso.int_revogar_sessoes(p_usuario);
  INSERT INTO controle.auditoria (usuario_id, acao, entidade, entidade_id, depois, ip)
  VALUES (p_admin, 'sessao.revogar', 'acesso.usuario', p_usuario::text, jsonb_build_object('todas', true, 'encerradas', v), p_ip);
  RETURN QUERY SELECT v;
END $$;
