-- Casos de uso de login e sessão (spec seguranca-acesso). Recriadas a cada deploy.
-- O n8n (tic_n8n) só executa sp_*. Senha e token nunca chegam aqui em claro: só hashes.
-- Toda função devolve exatamente UMA linha (o nó Postgres do n8n para o fluxo quando não há linha).

-- Busca para o login. Devolve uma linha mesmo se o e-mail não existir (usuario_id NULL),
-- para o n8n conferir um hash fictício e o tempo de resposta não revelar se o e-mail existe.
CREATE OR REPLACE FUNCTION acesso.sp_login_buscar(p_email text)
RETURNS TABLE (usuario_id uuid, senha_hash text, bloqueado boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT u.id, u.senha_hash, (u.id IS NOT NULL AND (NOT u.ativo OR coalesce(u.bloqueado_ate > now(), false)))
  FROM (SELECT 1) AS x
  LEFT JOIN acesso.usuario u ON u.email = lower(btrim(p_email))
$$;

-- Senha errada: conta a tentativa e bloqueia ao atingir o limite.
CREATE OR REPLACE FUNCTION acesso.sp_login_falha(p_email text, p_ip inet)
RETURNS TABLE (ok boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE
  v_id uuid; v_tent smallint;
  v_max integer := controle.fn_parametro_num('acesso.tentativas_max');
  v_bloq integer := controle.fn_parametro_num('acesso.bloqueio');
BEGIN
  UPDATE acesso.usuario SET tentativas_falhas = tentativas_falhas + 1
  WHERE email = lower(btrim(p_email))
  RETURNING id, tentativas_falhas INTO v_id, v_tent;

  IF v_id IS NOT NULL AND v_tent >= v_max THEN
    UPDATE acesso.usuario SET bloqueado_ate = now() + make_interval(mins => v_bloq), tentativas_falhas = 0 WHERE id = v_id;
    INSERT INTO controle.auditoria (usuario_id, acao, entidade, entidade_id, depois, ip)
    VALUES (NULL, 'acesso.bloqueio', 'acesso.usuario', v_id::text, jsonb_build_object('minutos', v_bloq), p_ip);
  END IF;

  INSERT INTO controle.auditoria (usuario_id, acao, entidade, entidade_id, ip)
  VALUES (NULL, 'acesso.login_falha', 'acesso.usuario', v_id::text, p_ip);
  RETURN QUERY SELECT true;
END $$;

-- Login certo: cria a sessão, zera as tentativas e audita.
CREATE OR REPLACE FUNCTION acesso.sp_sessao_criar(p_usuario_id uuid, p_token_hash text, p_csrf_hash text, p_ip inet, p_user_agent text)
RETURNS TABLE (sessao_id uuid, expira_em timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE
  v_sessao uuid; v_expira timestamptz := now() + make_interval(hours => controle.fn_parametro_num('acesso.sessao_maxima')::integer);
BEGIN
  IF NOT EXISTS (SELECT 1 FROM acesso.usuario WHERE id = p_usuario_id AND ativo AND coalesce(bloqueado_ate <= now(), true)) THEN
    RAISE EXCEPTION 'USUARIO_INATIVO' USING ERRCODE = 'P0001';
  END IF;
  INSERT INTO acesso.sessao (usuario_id, token_hash, csrf_hash, expira_em, ip, user_agent)
  VALUES (p_usuario_id, p_token_hash, p_csrf_hash, v_expira, p_ip, left(p_user_agent, 400))
  RETURNING id INTO v_sessao;
  UPDATE acesso.usuario SET tentativas_falhas = 0, bloqueado_ate = NULL WHERE id = p_usuario_id;
  INSERT INTO controle.auditoria (usuario_id, acao, entidade, entidade_id, ip)
  VALUES (p_usuario_id, 'acesso.login', 'acesso.sessao', v_sessao::text, p_ip);
  RETURN QUERY SELECT v_sessao, v_expira;
END $$;

-- Primeiro passo de toda rota com sessão (sub-autorizar):
-- status ok | sem_sessao (401) | csrf (403) | proibido (403).
CREATE OR REPLACE FUNCTION acesso.sp_autorizar(p_token_hash text, p_csrf_hash text, p_metodo text, p_permissao text)
RETURNS TABLE (status text, usuario_id uuid, sessao_id uuid, perfil text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE
  s record;
  v_inativ integer := controle.fn_parametro_num('acesso.sessao_inatividade');
BEGIN
  SELECT se.id, se.csrf_hash, se.ultimo_uso_em, u.id AS uid, u.perfil AS uperfil
  INTO s
  FROM acesso.sessao se JOIN acesso.usuario u ON u.id = se.usuario_id
  WHERE se.token_hash = p_token_hash
    AND se.revogada_em IS NULL
    AND se.expira_em > now()
    AND se.ultimo_uso_em > now() - make_interval(mins => v_inativ)
    AND u.ativo;

  IF s.id IS NULL THEN
    RETURN QUERY SELECT 'sem_sessao'::text, NULL::uuid, NULL::uuid, NULL::text; RETURN;
  END IF;
  IF upper(coalesce(p_metodo, 'GET')) NOT IN ('GET', 'HEAD') AND coalesce(p_csrf_hash, '') <> s.csrf_hash THEN
    RETURN QUERY SELECT 'csrf'::text, s.uid, s.id, s.uperfil; RETURN;
  END IF;
  IF nullif(p_permissao, '') IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM acesso.perfil_permissao WHERE perfil = s.uperfil AND permissao = p_permissao) THEN
    RETURN QUERY SELECT 'proibido'::text, s.uid, s.id, s.uperfil; RETURN;
  END IF;

  IF s.ultimo_uso_em < now() - interval '1 minute' THEN
    UPDATE acesso.sessao SET ultimo_uso_em = now() WHERE id = s.id;
  END IF;
  RETURN QUERY SELECT 'ok'::text, s.uid, s.id, s.uperfil;
END $$;

-- Quem está logado e o que pode (formato que o front espera).
CREATE OR REPLACE FUNCTION acesso.sp_auth_me(p_usuario_id uuid)
RETURNS TABLE (usuario jsonb)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT jsonb_build_object(
    'id', u.id,
    'nome', u.nome,
    'email', u.email,
    'perfil', u.perfil,
    'permissoes', coalesce((SELECT jsonb_agg(pp.permissao ORDER BY pp.permissao) FROM acesso.perfil_permissao pp WHERE pp.perfil = u.perfil), '[]'),
    'operacoes', coalesce((SELECT jsonb_agg(o.nome ORDER BY o.nome) FROM acesso.usuario_operacao uo JOIN cadastro.operacao o ON o.id = uo.operacao_id WHERE uo.usuario_id = u.id), '[]'),
    'todasOperacoes', u.todas_operacoes
  )
  FROM acesso.usuario u
  WHERE u.id = p_usuario_id AND u.ativo
$$;

CREATE OR REPLACE FUNCTION acesso.sp_logout(p_sessao_id uuid, p_ip inet)
RETURNS TABLE (ok boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE v_usuario uuid;
BEGIN
  UPDATE acesso.sessao SET revogada_em = now() WHERE id = p_sessao_id AND revogada_em IS NULL RETURNING usuario_id INTO v_usuario;
  IF v_usuario IS NOT NULL THEN
    INSERT INTO controle.auditoria (usuario_id, acao, entidade, entidade_id, ip)
    VALUES (v_usuario, 'acesso.logout', 'acesso.sessao', p_sessao_id::text, p_ip);
  END IF;
  RETURN QUERY SELECT true;
END $$;
