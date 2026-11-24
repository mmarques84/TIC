-- Tela de Jornada (spec jornada-painel). Recriadas a cada deploy. Leitura do que o motor de jornada calculou.
-- Listas devolvem UMA linha com jsonb (o nó Postgres do n8n não emite item sem linha).

DROP FUNCTION IF EXISTS derivado.sp_jornada_listar(uuid, text, text, text, boolean);
DROP FUNCTION IF EXISTS derivado.sp_jornada_resumo(uuid);
DROP FUNCTION IF EXISTS derivado.sp_jornada_detalhe(uuid, uuid);

CREATE OR REPLACE FUNCTION derivado.fn_nivel_jornada_ordem(p_nivel text)
RETURNS integer LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_nivel WHEN 'violacao' THEN 0 WHEN 'conferir' THEN 1 WHEN 'atencao' THEN 2 ELSE 3 END
$$;

-- R6: a linha de um motorista.
CREATE OR REPLACE FUNCTION derivado.int_jornada_linha(p_motorista uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT jsonb_build_object(
    'id', m.id, 'nome', m.nome, 'semControle', m.sem_controle_jornada,
    'placa', (SELECT v.placa FROM cadastro.veiculo v WHERE v.id = s.veiculo_id),
    'status', coalesce(s.status, 'sem_eventos'),
    'nivel', coalesce(s.nivel, 'dentro'),
    'jornadaAtual', (SELECT jsonb_build_object('inicio', j.inicio, 'trabalhoMin', j.trabalho_min, 'amplitudeMin', j.amplitude_min,
                                               'nivel', j.nivel, 'maxContinuaMin', j.max_direcao_continua_min)
                     FROM derivado.jornada j WHERE j.id = s.jornada_atual_id),
    'paradoDesde', s.parado_desde,
    'local', (SELECT a.local_texto FROM bruto.autotrac_macro a WHERE a.motorista_id = m.id AND a.local_texto IS NOT NULL ORDER BY a.horario DESC LIMIT 1),
    'diasSemDsr', coalesce(s.dias_sem_dsr, 0),
    'ultimoDsr', s.ultimo_dsr,
    'semanaMin', coalesce(s.trabalho_semana_min, 0),
    'alertas', coalesce(s.alertas, '[]'),
    'macrosDesconhecidas', coalesce(s.macros_desconhecidas, 0),
    'tratativa', (SELECT jsonb_build_object('tipo', t.tipo, 'observacao', t.observacao, 'em', t.criado_em, 'por', u.nome)
                  FROM derivado.tratativa t JOIN acesso.usuario u ON u.id = t.criado_por
                  WHERE t.motorista_id = m.id ORDER BY t.criado_em DESC, t.id DESC LIMIT 1),
    'atualizadoEm', s.atualizado_em
  )
  FROM cadastro.motorista m
  LEFT JOIN derivado.motorista_situacao s ON s.motorista_id = m.id
  WHERE m.id = p_motorista
$$;

-- Apoio: o motorista entra na faixa? (R3)
CREATE OR REPLACE FUNCTION derivado.fn_jornada_na_faixa(p_faixa text, s derivado.motorista_situacao, p_motorista uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT CASE coalesce(nullif(p_faixa, ''), 'todos')
    WHEN 'todos' THEN true
    WHEN 'violacao' THEN s.nivel = 'violacao'
    WHEN 'conferir' THEN s.nivel = 'conferir'
    WHEN 'atencao' THEN s.nivel = 'atencao'
    WHEN 'dsr' THEN s.parado_desde IS NOT NULL AND s.parado_desde <= now() - interval '35 hours'
    WHEN 'jornada' THEN s.jornada_atual_id IS NOT NULL
    WHEN 'tratados' THEN EXISTS (SELECT 1 FROM derivado.tratativa t WHERE t.motorista_id = p_motorista AND t.criado_em >= now() - interval '24 hours')
    ELSE false END
$$;

-- R2–R5: lista com faixa, dias sem DSR, busca e "sem controle".
CREATE FUNCTION derivado.sp_jornada_listar(p_usuario uuid, p_faixa text, p_dias text, p_q text, p_semcontrole boolean)
RETURNS TABLE (motoristas jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_q text := '%' || lower(btrim(coalesce(p_q, ''))) || '%';
BEGIN
  PERFORM acesso.int_exigir(p_usuario, 'jornada.ver');
  RETURN QUERY
    SELECT coalesce(jsonb_agg(derivado.int_jornada_linha(x.id) ORDER BY x.o1, x.o2 DESC, x.nome), '[]')
    FROM (
      SELECT m.id, m.nome, derivado.fn_nivel_jornada_ordem(s.nivel) AS o1, coalesce(s.dias_sem_dsr, 0) AS o2
      FROM cadastro.motorista m
      LEFT JOIN derivado.motorista_situacao s ON s.motorista_id = m.id
      LEFT JOIN cadastro.veiculo v ON v.id = s.veiculo_id
      WHERE m.ativo
        AND acesso.fn_ve_operacao(p_usuario, m.operacao_id)
        AND (coalesce(p_semcontrole, false) OR NOT m.sem_controle_jornada)
        AND (m.sem_controle_jornada OR s.motorista_id IS NOT NULL)          -- só quem o motor já calculou
        AND derivado.fn_jornada_na_faixa(p_faixa, s, m.id)
        AND CASE coalesce(nullif(p_dias, ''), 'todos')
              WHEN '0-2' THEN coalesce(s.dias_sem_dsr, 0) BETWEEN 0 AND 2
              WHEN '3-5' THEN s.dias_sem_dsr BETWEEN 3 AND 5
              WHEN '6' THEN s.dias_sem_dsr = 6
              WHEN '7+' THEN s.dias_sem_dsr >= 7
              ELSE true END
        AND (nullif(btrim(coalesce(p_q, '')), '') IS NULL OR lower(m.nome) LIKE v_q OR lower(coalesce(v.placa, '')) LIKE v_q
             OR EXISTS (SELECT 1 FROM bruto.autotrac_macro a WHERE a.motorista_id = m.id AND lower(coalesce(a.local_texto, '')) LIKE v_q
                        AND a.horario >= now() - interval '2 days'))
      ORDER BY 3, 4 DESC, 2
      LIMIT 500
    ) x;
END $$;

-- R3, R13: contagens das faixas e hora do retrato.
CREATE FUNCTION derivado.sp_jornada_resumo(p_usuario uuid)
RETURNS TABLE (resumo jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  PERFORM acesso.int_exigir(p_usuario, 'jornada.ver');
  RETURN QUERY
    SELECT jsonb_build_object(
      'todos', count(*),
      'violacao', count(*) FILTER (WHERE derivado.fn_jornada_na_faixa('violacao', s, m.id)),
      'conferir', count(*) FILTER (WHERE derivado.fn_jornada_na_faixa('conferir', s, m.id)),
      'atencao', count(*) FILTER (WHERE derivado.fn_jornada_na_faixa('atencao', s, m.id)),
      'dsr', count(*) FILTER (WHERE derivado.fn_jornada_na_faixa('dsr', s, m.id)),
      'jornada', count(*) FILTER (WHERE derivado.fn_jornada_na_faixa('jornada', s, m.id)),
      'tratados', count(*) FILTER (WHERE derivado.fn_jornada_na_faixa('tratados', s, m.id)),
      'retrato', max(s.atualizado_em))
    FROM cadastro.motorista m
    JOIN derivado.motorista_situacao s ON s.motorista_id = m.id
    WHERE m.ativo AND NOT m.sem_controle_jornada AND acesso.fn_ve_operacao(p_usuario, m.operacao_id);
END $$;

-- R8, R9: detalhe (8 dias de jornadas, paradas 11 h+, 20 macros, tratativas).
CREATE FUNCTION derivado.sp_jornada_detalhe(p_usuario uuid, p_motorista uuid)
RETURNS TABLE (motorista jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_op uuid; v_existe boolean;
BEGIN
  PERFORM acesso.int_exigir(p_usuario, 'jornada.ver');
  SELECT true, operacao_id INTO v_existe, v_op FROM cadastro.motorista WHERE id = p_motorista;
  IF v_existe IS NULL OR NOT acesso.fn_ve_operacao(p_usuario, v_op) THEN RAISE EXCEPTION 'NAO_ENCONTRADO' USING ERRCODE = 'P0001'; END IF;
  RETURN QUERY SELECT derivado.int_jornada_linha(p_motorista) || jsonb_build_object(
    'jornadas', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id', j.id, 'dia', j.dia, 'inicio', j.inicio, 'fim', j.fim, 'situacao', j.situacao, 'nivel', j.nivel,
        'trabalhoMin', j.trabalho_min, 'refeicaoMin', j.refeicao_min, 'direcaoMin', j.direcao_min,
        'maxContinuaMin', j.max_direcao_continua_min, 'interjornadaMin', j.interjornada_min,
        'motivos', (SELECT coalesce(jsonb_agg(e || jsonb_build_object('texto', derivado.fn_texto_alerta(e->>'codigo', e->>'valor'))), '[]')
                    FROM jsonb_array_elements(j.motivos) e)) ORDER BY j.inicio DESC)
      FROM derivado.jornada j WHERE j.motorista_id = p_motorista AND j.inicio >= now() - interval '8 days'), '[]'),
    'paradas', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'inicio', lower(p.periodo), 'fim', upper(p.periodo), 'minutos', derivado.fn_minutos(lower(p.periodo), upper(p.periodo)),
        'contaDsr', p.conta_dsr, 'kmTelemetria', p.km_telemetria, 'houveJornadaAberta', p.houve_jornada_aberta, 'local', p.local_texto,
        'motivo', CASE WHEN p.conta_dsr THEN 'contou como DSR'
                       WHEN derivado.fn_minutos(lower(p.periodo), upper(p.periodo)) < 35 * 60 THEN 'não é DSR (menos de 35 h)'
                       WHEN p.km_telemetria > 50 THEN 'não é DSR (rodou ' || p.km_telemetria || ' km logado)'
                       ELSE 'não é DSR' END) ORDER BY lower(p.periodo) DESC)
      FROM derivado.parada p WHERE p.motorista_id = p_motorista AND upper(p.periodo) >= now() - interval '8 days'), '[]'),
    'macros', coalesce((SELECT jsonb_agg(x ORDER BY x->>'horario' DESC) FROM (
        SELECT jsonb_build_object('horario', a.horario, 'numero', a.numero, 'local', a.local_texto,
                                  'significado', mm.significado, 'desconhecida', mm.significado IS NULL) AS x
        FROM bruto.autotrac_macro a LEFT JOIN controle.macro_mapa mm ON mm.fonte = 'autotrac' AND mm.numero = a.numero
        WHERE a.motorista_id = p_motorista ORDER BY a.horario DESC LIMIT 20) z), '[]'),
    'tratativas', coalesce((SELECT jsonb_agg(jsonb_build_object('tipo', t.tipo, 'observacao', t.observacao, 'em', t.criado_em, 'por', u.nome,
                                                                'jornadaId', t.jornada_id) ORDER BY t.criado_em DESC, t.id DESC)
      FROM derivado.tratativa t JOIN acesso.usuario u ON u.id = t.criado_por WHERE t.motorista_id = p_motorista), '[]'));
END $$;

-- R10–R12, R14: tratativa. Não muda o cálculo; recalcula a situação para o "conferir" sumir na hora.
CREATE OR REPLACE FUNCTION derivado.sp_tratativa_criar(p_usuario uuid, p_motorista uuid, p_jornada uuid, p_tipo text, p_observacao text, p_ip inet)
RETURNS TABLE (motorista jsonb)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE v_op uuid; v_existe boolean; v_obs text := nullif(left(btrim(coalesce(p_observacao, '')), 1000), ''); v_id uuid;
BEGIN
  PERFORM acesso.int_exigir(p_usuario, 'jornada.tratar');
  SELECT true, operacao_id INTO v_existe, v_op FROM cadastro.motorista WHERE id = p_motorista;
  IF v_existe IS NULL OR NOT acesso.fn_ve_operacao(p_usuario, v_op) THEN RAISE EXCEPTION 'NAO_ENCONTRADO' USING ERRCODE = 'P0001'; END IF;
  IF coalesce(p_tipo, '') NOT IN ('dsr_confirmado', 'tempo_espera', 'macro_errada', 'jornada_correta', 'orientado_advertido', 'outro') THEN
    RAISE EXCEPTION 'TIPO_INVALIDO' USING ERRCODE = 'P0001';
  END IF;
  IF p_tipo = 'outro' AND v_obs IS NULL THEN RAISE EXCEPTION 'OBSERVACAO_OBRIGATORIA' USING ERRCODE = 'P0001'; END IF;
  IF p_jornada IS NOT NULL AND NOT EXISTS (SELECT 1 FROM derivado.jornada WHERE id = p_jornada AND motorista_id = p_motorista) THEN
    RAISE EXCEPTION 'NAO_ENCONTRADO' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO derivado.tratativa (motorista_id, jornada_id, tipo, observacao, criado_por)
  VALUES (p_motorista, p_jornada, p_tipo, v_obs, p_usuario) RETURNING id INTO v_id;
  INSERT INTO controle.auditoria (usuario_id, acao, entidade, entidade_id, depois, ip)
  VALUES (p_usuario, 'jornada.tratativa', 'derivado.tratativa', v_id::text,
          jsonb_build_object('motorista', p_motorista, 'jornada', p_jornada, 'tipo', p_tipo, 'observacao', v_obs), p_ip);

  PERFORM derivado.int_jornada_motorista(p_motorista, now() - interval '8 days');
  RETURN QUERY SELECT derivado.int_jornada_linha(p_motorista);
END $$;
