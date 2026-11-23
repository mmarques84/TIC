-- Central de alertas (spec central-alertas). Recriadas a cada deploy.
-- Listas devolvem UMA linha com jsonb (o nó Postgres do n8n não emite item sem linha).

DROP FUNCTION IF EXISTS derivado.sp_central_listar(uuid, text, text, text, text);
DROP FUNCTION IF EXISTS derivado.sp_central_resumo(uuid);
DROP FUNCTION IF EXISTS derivado.sp_alerta_detalhe(uuid, uuid, inet);

-- Apoio: a pessoa vê esta operação? (R2). Veículo sem operação aparece para todos.
CREATE OR REPLACE FUNCTION acesso.fn_ve_operacao(p_usuario uuid, p_operacao uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT p_operacao IS NULL
      OR EXISTS (SELECT 1 FROM acesso.usuario u WHERE u.id = p_usuario AND u.todas_operacoes)
      OR EXISTS (SELECT 1 FROM acesso.usuario_operacao uo WHERE uo.usuario_id = p_usuario AND uo.operacao_id = p_operacao)
$$;

CREATE OR REPLACE FUNCTION acesso.fn_pode(p_usuario uuid, p_permissao text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT EXISTS (SELECT 1 FROM acesso.usuario u JOIN acesso.perfil_permissao pp ON pp.perfil = u.perfil
                 WHERE u.id = p_usuario AND u.ativo AND pp.permissao = p_permissao)
$$;

CREATE OR REPLACE FUNCTION derivado.fn_nivel_ordem(p_nivel text)
RETURNS integer LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_nivel WHEN 'critico' THEN 0 WHEN 'grave' THEN 1 WHEN 'medio' THEN 2 WHEN 'leve' THEN 3 ELSE 9 END
$$;

-- Apoio: o alerta como a fila mostra (R4).
CREATE OR REPLACE FUNCTION derivado.int_alerta_json(p_alerta uuid, p_com_foto boolean)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT jsonb_build_object(
    'id', a.id, 'nivel', a.nivel, 'estado', a.estado,
    'titulo', coalesce(a.titulo, initcap(replace(e.tipo, '_', ' '))),
    'tipo', e.tipo, 'horario', e.horario, 'criadoEm', a.criado_em,
    'placa', v.placa, 'motorista', m.nome,
    'local', coalesce(e.dados->>'local_texto',
                      CASE WHEN e.local IS NOT NULL THEN round(ST_Y(e.local::geometry)::numeric, 4) || ', ' || round(ST_X(e.local::geometry)::numeric, 4) END),
    'velocidade', e.velocidade,
    'ia', (SELECT jsonb_build_object('resultado', t.resultado, 'confianca', t.confianca, 'evidencia', t.evidencia)
           FROM ia.triagem t WHERE t.evento_id = e.id ORDER BY t.rodada DESC LIMIT 1),
    'assumidoPor', (SELECT u.nome FROM acesso.usuario u WHERE u.id = a.assumido_por),
    'tratadoPor', (SELECT u.nome FROM acesso.usuario u WHERE u.id = a.tratado_por),
    'tratadoEm', a.tratado_em,
    'motivoFalso', a.motivo_falso,
    'ultimaAcao', (SELECT jsonb_build_object('tipo', ac.tipo, 'estado', ac.estado, 'automatica', ac.solicitada_por IS NULL)
                   FROM derivado.acao ac WHERE ac.alerta_id = a.id ORDER BY ac.solicitada_em DESC LIMIT 1),
    'fotoCapa', CASE WHEN p_com_foto THEN (SELECT f.id FROM derivado.evento_frame f WHERE f.evento_id = e.id
                                              ORDER BY (f.camera = 'fadiga') DESC, f.instante LIMIT 1) END,
    'cameraCapa', (SELECT f.camera FROM derivado.evento_frame f WHERE f.evento_id = e.id ORDER BY (f.camera = 'fadiga') DESC, f.instante LIMIT 1)
  )
  FROM derivado.alerta a
  JOIN derivado.evento e ON e.id = a.evento_id
  JOIN cadastro.veiculo v ON v.id = e.veiculo_id
  LEFT JOIN cadastro.motorista m ON m.id = e.motorista_id
  WHERE a.id = p_alerta
$$;

-- R3–R5: fila (aba abertos) ou tratados hoje, com filtros.
CREATE FUNCTION derivado.sp_central_listar(p_usuario uuid, p_aba text, p_nivel text, p_tipo text, p_q text)
RETURNS TABLE (alertas jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_foto boolean := acesso.fn_pode(p_usuario, 'imagem.ver');
  v_q text := '%' || lower(btrim(coalesce(p_q, ''))) || '%';
  v_hoje timestamptz := date_trunc('day', now() AT TIME ZONE 'America/Sao_Paulo') AT TIME ZONE 'America/Sao_Paulo';
BEGIN
  PERFORM acesso.int_exigir(p_usuario, 'alerta.ver');
  RETURN QUERY
    SELECT coalesce(jsonb_agg(derivado.int_alerta_json(x.id, v_foto) ORDER BY x.o1, x.o2 DESC), '[]')
    FROM (
      SELECT a.id,
             CASE WHEN coalesce(p_aba, 'abertos') = 'abertos' THEN derivado.fn_nivel_ordem(a.nivel) ELSE 0 END AS o1,
             CASE WHEN coalesce(p_aba, 'abertos') = 'abertos' THEN e.horario ELSE a.tratado_em END AS o2
      FROM derivado.alerta a
      JOIN derivado.evento e ON e.id = a.evento_id
      JOIN cadastro.veiculo v ON v.id = e.veiculo_id
      LEFT JOIN cadastro.motorista m ON m.id = e.motorista_id
      WHERE acesso.fn_ve_operacao(p_usuario, v.operacao_id)
        AND CASE WHEN coalesce(p_aba, 'abertos') = 'abertos' THEN a.estado IN ('aberto', 'em_tratamento')
                 ELSE a.estado IN ('confirmado', 'falso_positivo', 'encerrado') AND a.tratado_em >= v_hoje END
        AND (nullif(p_nivel, '') IS NULL OR a.nivel = p_nivel)
        AND (nullif(p_tipo, '') IS NULL OR e.tipo = p_tipo)
        AND (nullif(btrim(coalesce(p_q, '')), '') IS NULL OR lower(v.placa) LIKE v_q OR lower(coalesce(m.nome, '')) LIKE v_q)
      ORDER BY 2, 3 DESC
      LIMIT 200
    ) x;
END $$;

-- R7: contadores (também para a TV).
CREATE FUNCTION derivado.sp_central_resumo(p_usuario uuid)
RETURNS TABLE (resumo jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  PERFORM acesso.int_exigir(p_usuario, 'alerta.ver');
  RETURN QUERY
    SELECT jsonb_build_object(
      'critico', count(*) FILTER (WHERE a.nivel = 'critico'),
      'grave', count(*) FILTER (WHERE a.nivel = 'grave'),
      'medio', count(*) FILTER (WHERE a.nivel = 'medio'),
      'leve', count(*) FILTER (WHERE a.nivel = 'leve'),
      'abertos', count(*),
      'maisAntigo', min(e.horario),
      'geradoEm', now())
    FROM derivado.alerta a
    JOIN derivado.evento e ON e.id = a.evento_id
    JOIN cadastro.veiculo v ON v.id = e.veiculo_id
    WHERE a.estado IN ('aberto', 'em_tratamento') AND acesso.fn_ve_operacao(p_usuario, v.operacao_id);
END $$;

-- R8–R10: detalhe. Quem tem imagem.ver recebe as fotos e o acesso fica na auditoria.
CREATE FUNCTION derivado.sp_alerta_detalhe(p_usuario uuid, p_id uuid, p_ip inet)
RETURNS TABLE (alerta jsonb)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE
  v_foto boolean := acesso.fn_pode(p_usuario, 'imagem.ver');
  a record; v jsonb;
BEGIN
  PERFORM acesso.int_exigir(p_usuario, 'alerta.ver');
  SELECT al.id, al.evento_id, e.motorista_id, e.veiculo_id, e.horario, e.dados, ve.operacao_id
  INTO a
  FROM derivado.alerta al JOIN derivado.evento e ON e.id = al.evento_id JOIN cadastro.veiculo ve ON ve.id = e.veiculo_id
  WHERE al.id = p_id;
  IF a.id IS NULL OR NOT acesso.fn_ve_operacao(p_usuario, a.operacao_id) THEN
    RAISE EXCEPTION 'NAO_ENCONTRADO' USING ERRCODE = 'P0001';
  END IF;

  v := derivado.int_alerta_json(p_id, v_foto) || jsonb_build_object(
    'fotos', CASE WHEN v_foto THEN coalesce((SELECT jsonb_agg(jsonb_build_object('id', f.id, 'camera', f.camera, 'instante', f.instante)
                                             ORDER BY (f.camera = 'fadiga') DESC, f.camera, f.instante)
                                             FROM derivado.evento_frame f WHERE f.evento_id = a.evento_id), '[]') END,
    'podeVerFotos', v_foto,
    'linkClipe', a.dados->>'link_clipe',
    'limpador', (SELECT p.limpador FROM bruto.autotrac_posicao p WHERE p.veiculo_id = a.veiculo_id
                 AND p.horario BETWEEN a.horario - interval '5 min' AND a.horario + interval '1 min' ORDER BY p.horario DESC LIMIT 1),
    'jornada', (SELECT jsonb_build_object('status', s.status, 'nivel', s.nivel) FROM derivado.motorista_situacao s WHERE s.motorista_id = a.motorista_id),
    'acoes', coalesce((SELECT jsonb_agg(jsonb_build_object('tipo', ac.tipo, 'estado', ac.estado, 'texto', ac.texto, 'em', ac.solicitada_em,
                                                           'por', (SELECT u.nome FROM acesso.usuario u WHERE u.id = ac.solicitada_por))
                                        ORDER BY ac.solicitada_em)
                       FROM derivado.acao ac WHERE ac.alerta_id = p_id), '[]'),
    'historico', coalesce((SELECT jsonb_agg(jsonb_build_object('id', h.id, 'titulo', coalesce(h.titulo, he.tipo), 'horario', he.horario, 'estado', h.estado)
                                            ORDER BY he.horario DESC)
                           FROM derivado.alerta h JOIN derivado.evento he ON he.id = h.evento_id
                           WHERE a.motorista_id IS NOT NULL AND he.motorista_id = a.motorista_id AND h.id <> p_id
                             AND he.horario >= a.horario - interval '24 hours'), '[]'),
    'mensagemPadrao', coalesce(controle.fn_parametro('central.mensagem.' || (SELECT tipo FROM derivado.evento WHERE id = a.evento_id)) #>> '{}',
                               controle.fn_parametro('central.mensagem.padrao') #>> '{}')
  );

  IF v_foto AND jsonb_array_length(v->'fotos') > 0 THEN  -- R9
    INSERT INTO controle.auditoria (usuario_id, acao, entidade, entidade_id, depois, ip)
    VALUES (p_usuario, 'imagem.ver', 'derivado.alerta', p_id::text, jsonb_build_object('fotos', jsonb_array_length(v->'fotos')), p_ip);
  END IF;
  RETURN QUERY SELECT v;
END $$;

-- Apoio: carrega o alerta para escrita, conferindo escopo e se ainda está na fila.
CREATE OR REPLACE FUNCTION derivado.int_alerta_para_tratar(p_usuario uuid, p_id uuid)
RETURNS derivado.alerta LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE r derivado.alerta; v_op uuid;
BEGIN
  SELECT al.* INTO r FROM derivado.alerta al WHERE al.id = p_id FOR UPDATE;
  SELECT ve.operacao_id INTO v_op FROM derivado.evento e JOIN cadastro.veiculo ve ON ve.id = e.veiculo_id WHERE e.id = r.evento_id;
  IF r.id IS NULL OR NOT acesso.fn_ve_operacao(p_usuario, v_op) THEN RAISE EXCEPTION 'NAO_ENCONTRADO' USING ERRCODE = 'P0001'; END IF;
  IF r.estado NOT IN ('aberto', 'em_tratamento') THEN RAISE EXCEPTION 'ALERTA_JA_TRATADO' USING ERRCODE = 'P0001'; END IF;
  RETURN r;
END $$;

-- R11: assumir (assumir de novo troca o responsável).
CREATE OR REPLACE FUNCTION derivado.sp_alerta_pegar(p_usuario uuid, p_id uuid, p_ip inet)
RETURNS TABLE (alerta jsonb)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE r derivado.alerta;
BEGIN
  PERFORM acesso.int_exigir(p_usuario, 'alerta.tratar');
  r := derivado.int_alerta_para_tratar(p_usuario, p_id);
  UPDATE derivado.alerta SET estado = 'em_tratamento', assumido_por = p_usuario, assumido_em = now() WHERE id = p_id;
  INSERT INTO controle.auditoria (usuario_id, acao, entidade, entidade_id, antes, ip)
  VALUES (p_usuario, 'alerta.assumir', 'derivado.alerta', p_id::text, jsonb_build_object('assumido_por', r.assumido_por), p_ip);
  RETURN QUERY SELECT derivado.int_alerta_json(p_id, acesso.fn_pode(p_usuario, 'imagem.ver'));
END $$;

-- Apoio: registra a validação humana da triagem (R12, R13).
CREATE OR REPLACE FUNCTION ia.int_validar_triagem(p_usuario uuid, p_evento uuid, p_real boolean)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  UPDATE ia.triagem t SET validado_por = p_usuario, validado_em = now(),
    validacao = CASE WHEN (t.resultado = 'verdadeiro') = p_real THEN 'concordo' ELSE 'discordo' END
  WHERE t.id = (SELECT id FROM ia.triagem WHERE evento_id = p_evento ORDER BY rodada DESC LIMIT 1)
    AND t.resultado <> 'inconclusivo'  -- inconclusivo não conta como acerto nem erro da IA
$$;

CREATE OR REPLACE FUNCTION derivado.sp_alerta_confirmar(p_usuario uuid, p_id uuid, p_observacao text, p_ip inet)
RETURNS TABLE (alerta jsonb)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE r derivado.alerta;
BEGIN
  PERFORM acesso.int_exigir(p_usuario, 'alerta.tratar');
  r := derivado.int_alerta_para_tratar(p_usuario, p_id);
  UPDATE derivado.alerta SET estado = 'confirmado', tratado_por = p_usuario, tratado_em = now(),
    observacao = nullif(left(btrim(coalesce(p_observacao, '')), 1000), '') WHERE id = p_id;
  PERFORM ia.int_validar_triagem(p_usuario, r.evento_id, true);
  INSERT INTO controle.auditoria (usuario_id, acao, entidade, entidade_id, depois, ip)
  VALUES (p_usuario, 'alerta.confirmar', 'derivado.alerta', p_id::text, jsonb_build_object('observacao', p_observacao), p_ip);
  RETURN QUERY SELECT derivado.int_alerta_json(p_id, acesso.fn_pode(p_usuario, 'imagem.ver'));
END $$;

CREATE OR REPLACE FUNCTION derivado.sp_alerta_falso(p_usuario uuid, p_id uuid, p_motivo text, p_observacao text, p_ip inet)
RETURNS TABLE (alerta jsonb)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE r derivado.alerta;
BEGIN
  PERFORM acesso.int_exigir(p_usuario, 'alerta.tratar');
  IF coalesce(p_motivo, '') NOT IN ('gesto', 'objeto', 'imagem_ruim', 'camera_desalinhada', 'outro') THEN
    RAISE EXCEPTION 'MOTIVO_OBRIGATORIO' USING ERRCODE = 'P0001';
  END IF;
  r := derivado.int_alerta_para_tratar(p_usuario, p_id);
  UPDATE derivado.alerta SET estado = 'falso_positivo', motivo_falso = p_motivo, tratado_por = p_usuario, tratado_em = now(),
    observacao = nullif(left(btrim(coalesce(p_observacao, '')), 1000), '') WHERE id = p_id;
  PERFORM ia.int_validar_triagem(p_usuario, r.evento_id, false);
  INSERT INTO controle.auditoria (usuario_id, acao, entidade, entidade_id, depois, ip)
  VALUES (p_usuario, 'alerta.falso', 'derivado.alerta', p_id::text, jsonb_build_object('motivo', p_motivo, 'observacao', p_observacao), p_ip);
  RETURN QUERY SELECT derivado.int_alerta_json(p_id, acesso.fn_pode(p_usuario, 'imagem.ver'));
END $$;

-- R15, R16, R18: ação na cabine. Grava a ação e o item na fila de saída; o alerta continua aberto.
CREATE OR REPLACE FUNCTION derivado.int_alerta_acao(p_usuario uuid, p_id uuid, p_tipo text, p_texto text, p_ip inet)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE r derivado.alerta; v_acao uuid; v_vei record;
BEGIN
  r := derivado.int_alerta_para_tratar(p_usuario, p_id);
  SELECT ve.id, ve.placa, ve.id_autotrac INTO v_vei FROM derivado.evento e JOIN cadastro.veiculo ve ON ve.id = e.veiculo_id WHERE e.id = r.evento_id;
  INSERT INTO derivado.acao (alerta_id, tipo, texto, solicitada_por) VALUES (p_id, p_tipo, p_texto, p_usuario) RETURNING id INTO v_acao;
  INSERT INTO controle.fila_acao (tipo, referencia_id, payload)
  VALUES (p_tipo, v_acao, jsonb_build_object('acao_id', v_acao, 'alerta_id', p_id, 'veiculo_id', v_vei.id, 'placa', v_vei.placa,
                                             'id_autotrac', v_vei.id_autotrac, 'texto', p_texto));
  INSERT INTO controle.auditoria (usuario_id, acao, entidade, entidade_id, depois, ip)
  VALUES (p_usuario, 'alerta.' || CASE p_tipo WHEN 'mensagem_terminal' THEN 'mensagem' ELSE p_tipo END, 'derivado.alerta', p_id::text,
          jsonb_build_object('acao_id', v_acao, 'texto', p_texto), p_ip);
  RETURN v_acao;
END $$;

CREATE OR REPLACE FUNCTION derivado.sp_alerta_mensagem(p_usuario uuid, p_id uuid, p_texto text, p_ip inet)
RETURNS TABLE (alerta jsonb)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_texto text := btrim(coalesce(p_texto, ''));
BEGIN
  PERFORM acesso.int_exigir(p_usuario, 'alerta.acionar');
  IF length(v_texto) NOT BETWEEN 1 AND 200 THEN RAISE EXCEPTION 'TEXTO_INVALIDO' USING ERRCODE = 'P0001'; END IF;
  PERFORM derivado.int_alerta_acao(p_usuario, p_id, 'mensagem_terminal', v_texto, p_ip);
  RETURN QUERY SELECT derivado.int_alerta_json(p_id, acesso.fn_pode(p_usuario, 'imagem.ver'));
END $$;

CREATE OR REPLACE FUNCTION derivado.sp_alerta_sirene(p_usuario uuid, p_id uuid, p_ip inet)
RETURNS TABLE (alerta jsonb)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  PERFORM acesso.int_exigir(p_usuario, 'alerta.acionar');
  PERFORM derivado.int_alerta_acao(p_usuario, p_id, 'sirene', NULL, p_ip);
  RETURN QUERY SELECT derivado.int_alerta_json(p_id, acesso.fn_pode(p_usuario, 'imagem.ver'));
END $$;
