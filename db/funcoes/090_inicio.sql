-- Início com dados reais (spec inicio-resumo). Recriado a cada deploy.
-- Devolve UMA linha com o JSON no formato que a tela já usa (ResumoInicio). Nunca número de exemplo (R14).

DROP FUNCTION IF EXISTS controle.sp_inicio_resumo(uuid);

-- "há X min / X h / X dias" (texto curto para a tela).
CREATE OR REPLACE FUNCTION controle.fn_ha(p_quando timestamptz)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT CASE
    WHEN p_quando IS NULL THEN NULL
    WHEN now() - p_quando < interval '1 minute' THEN 'há menos de 1 min'
    WHEN now() - p_quando < interval '1 hour' THEN 'há ' || floor(extract(epoch FROM now() - p_quando) / 60)::int || ' min'
    WHEN now() - p_quando < interval '2 days' THEN 'há ' || floor(extract(epoch FROM now() - p_quando) / 3600)::int || ' h'
    ELSE 'há ' || floor(extract(epoch FROM now() - p_quando) / 86400)::int || ' dias' END
$$;

-- R10: estado de uma fonte a partir de controle.credencial_status.
CREATE OR REPLACE FUNCTION controle.fn_estado_integracao(p_fonte text)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT CASE
    WHEN c.fonte IS NULL OR (c.ultimo_sucesso IS NULL AND c.ultimo_erro IS NULL) THEN 'inativa'
    WHEN c.senha_mudou THEN 'erro'
    WHEN c.ultimo_sucesso >= now() - make_interval(mins => coalesce(controle.fn_parametro_num('autotrac.alerta_sem_dados_min'), 30)::integer) THEN 'ok'
    WHEN c.ultimo_sucesso IS NOT NULL THEN 'atraso'
    ELSE 'erro' END
  FROM (SELECT p_fonte AS f) x LEFT JOIN controle.credencial_status c ON c.fonte = x.f
$$;

CREATE FUNCTION controle.sp_inicio_resumo(p_usuario uuid)
RETURNS TABLE (resumo jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE
  v_hoje date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  v_mes  date := date_trunc('month', now() AT TIME ZONE 'America/Sao_Paulo')::date;
  v_alerta boolean := acesso.fn_pode(p_usuario, 'alerta.ver');
  v_jornada boolean := acesso.fn_pode(p_usuario, 'jornada.ver');
  v_opi boolean := acesso.fn_pode(p_usuario, 'opi.ver');
  v_consumo boolean := acesso.fn_pode(p_usuario, 'consumo_ia.ver');
  v_integ boolean := acesso.fn_pode(p_usuario, 'integracao.ver');
  ind jsonb := '[]'; v_alertas jsonb := '[]'; v_jlin jsonb := '[]'; v_opilin jsonb := '[]'; v_conslin jsonb := '[]'; v_integ_lin jsonb := '[]';
  n1 integer; n2 integer; n3 integer; v_pct numeric; v_teto numeric; v_gasto numeric; v_txt text;
  v_correlacao boolean := EXISTS (SELECT 1 FROM derivado.alerta);
  v_jornada_dados boolean := EXISTS (SELECT 1 FROM derivado.jornada WHERE fonte = 'autotrac');
BEGIN
  IF NOT EXISTS (SELECT 1 FROM acesso.usuario WHERE id = p_usuario AND ativo) THEN RAISE EXCEPTION 'SEM_PERMISSAO' USING ERRCODE = 'P0001'; END IF;

  -- ===== alertas (R3, R4, R11) =====
  IF v_alerta THEN
    SELECT count(*), count(*) FILTER (WHERE a.nivel = 'critico') INTO n1, n2
    FROM derivado.alerta a JOIN derivado.evento e ON e.id = a.evento_id JOIN cadastro.veiculo v ON v.id = e.veiculo_id
    WHERE a.estado IN ('aberto', 'em_tratamento') AND acesso.fn_ve_operacao(p_usuario, v.operacao_id);
    ind := ind || jsonb_build_object('codigo', 'alertas', 'rotulo', 'Alertas abertos', 'valor', n1::text,
      'nota', CASE WHEN NOT v_correlacao THEN 'aguardando a correlação de alertas' WHEN n2 > 0 THEN n2 || ' crítico(s)' ELSE 'nenhum crítico' END,
      'nivelNota', CASE WHEN n2 > 0 THEN 'critico' END);

    SELECT count(*), (SELECT count(*) FROM derivado.acao ac WHERE ac.tipo = 'sirene' AND ac.solicitada_em >= now() - interval '1 hour')
    INTO n1, n2
    FROM derivado.alerta a JOIN derivado.evento e ON e.id = a.evento_id JOIN cadastro.veiculo v ON v.id = e.veiculo_id
    WHERE e.tipo = 'fadiga' AND a.criado_em >= now() - interval '1 hour' AND acesso.fn_ve_operacao(p_usuario, v.operacao_id);
    ind := ind || jsonb_build_object('codigo', 'fadiga', 'rotulo', 'Fadiga na última hora', 'valor', n1::text,
      'nota', CASE WHEN NOT v_correlacao THEN 'aguardando a correlação de alertas' ELSE n2 || ' sirene(s) acionada(s)' END,
      'nivelNota', CASE WHEN n1 > 0 THEN 'critico' END);

    -- R7: falsos positivos evitados hoje (triagem da IA)
    SELECT count(*), count(*) FILTER (WHERE t.resultado = 'falso') INTO n1, n2
    FROM ia.triagem t JOIN derivado.evento e ON e.id = t.evento_id JOIN cadastro.veiculo v ON v.id = e.veiculo_id
    WHERE t.rodada = 1 AND (t.criado_em AT TIME ZONE 'America/Sao_Paulo')::date = v_hoje AND acesso.fn_ve_operacao(p_usuario, v.operacao_id);
    ind := ind || jsonb_build_object('codigo', 'falsos_evitados', 'rotulo', 'Falsos positivos evitados',
      'valor', CASE WHEN n1 = 0 THEN '—' ELSE round(100.0 * n2 / n1) || '%' END,
      'nota', CASE WHEN n1 = 0 THEN 'sem triagem hoje' ELSE 'de ' || n1 || ' alarme(s) de hoje' END, 'nivelNota', CASE WHEN n1 > 0 THEN 'ok' END);

    SELECT coalesce(jsonb_agg(x.j ORDER BY x.ord, x.criado_em), '[]') INTO v_alertas FROM (
      SELECT jsonb_build_object('id', a.id, 'nivel', a.nivel,
               'rotuloNivel', CASE a.nivel WHEN 'critico' THEN 'Crítico' WHEN 'grave' THEN 'Grave' WHEN 'medio' THEN 'Médio' ELSE 'Leve' END,
               'titulo', coalesce(a.titulo, initcap(replace(e.tipo, '_', ' '))),
               'detalhe', concat_ws(' · ', CASE a.estado WHEN 'em_tratamento' THEN 'Em tratamento' END,
                                    (SELECT 'IA: ' || t.resultado || ' (' || t.confianca || ')' FROM ia.triagem t WHERE t.evento_id = e.id ORDER BY t.rodada DESC LIMIT 1)),
               'placa', v.placa, 'motorista', coalesce(m.nome, 'ninguém logado'), 'ha', controle.fn_ha(e.horario)) AS j,
             derivado.fn_nivel_ordem(a.nivel) AS ord, a.criado_em
      FROM derivado.alerta a JOIN derivado.evento e ON e.id = a.evento_id JOIN cadastro.veiculo v ON v.id = e.veiculo_id
      LEFT JOIN cadastro.motorista m ON m.id = e.motorista_id
      WHERE a.estado IN ('aberto', 'em_tratamento') AND acesso.fn_ve_operacao(p_usuario, v.operacao_id)
      ORDER BY derivado.fn_nivel_ordem(a.nivel), a.criado_em LIMIT 5) x;
  END IF;

  -- ===== jornada (R5, R6, R13) =====
  IF v_jornada THEN
    SELECT count(*) FILTER (WHERE s.jornada_atual_id IS NOT NULL), count(*) INTO n1, n2
    FROM cadastro.motorista m LEFT JOIN derivado.motorista_situacao s ON s.motorista_id = m.id
    WHERE m.ativo AND NOT m.sem_controle_jornada AND acesso.fn_ve_operacao(p_usuario, m.operacao_id);
    ind := ind || jsonb_build_object('codigo', 'em_jornada', 'rotulo', 'Motoristas em jornada', 'valor', n1::text,
      'nota', CASE WHEN NOT v_jornada_dados THEN 'aguardando a API ATIC' ELSE 'de ' || n2 || ' com controle de jornada' END, 'nivelNota', NULL);

    SELECT count(DISTINCT j.id), count(DISTINCT j.id) FILTER (WHERE EXISTS (SELECT 1 FROM derivado.tratativa t WHERE t.jornada_id = j.id)) INTO n1, n2
    FROM derivado.jornada j JOIN cadastro.motorista m ON m.id = j.motorista_id
    WHERE j.dia = v_hoje AND j.nivel = 'violacao' AND acesso.fn_ve_operacao(p_usuario, m.operacao_id);
    ind := ind || jsonb_build_object('codigo', 'violacoes', 'rotulo', 'Violações de jornada hoje', 'valor', n1::text,
      'nota', CASE WHEN NOT v_jornada_dados THEN 'aguardando a API ATIC' ELSE n2 || ' com tratativa' END,
      'nivelNota', CASE WHEN n1 > n2 THEN 'grave' END);

    SELECT coalesce(jsonb_agg(x.j ORDER BY x.ord, x.dias DESC), '[]') INTO v_jlin FROM (
      SELECT jsonb_build_object('id', m.id, 'titulo', m.nome,
               'detalhe', coalesce((SELECT string_agg(al->>'texto', ' · ') FROM jsonb_array_elements(s.alertas) al), 'ver detalhe na Jornada'),
               'selo', CASE s.nivel WHEN 'violacao' THEN 'Violação' ELSE 'Conferir' END,
               'nivel', CASE s.nivel WHEN 'violacao' THEN 'critico' ELSE 'leve' END) AS j,
             CASE s.nivel WHEN 'violacao' THEN 0 ELSE 1 END AS ord, s.dias_sem_dsr AS dias
      FROM derivado.motorista_situacao s JOIN cadastro.motorista m ON m.id = s.motorista_id
      WHERE s.nivel IN ('violacao', 'conferir') AND m.ativo AND acesso.fn_ve_operacao(p_usuario, m.operacao_id)
      ORDER BY 2, 3 DESC LIMIT 5) x;
  END IF;

  -- ===== OPI (R8, R13) =====
  IF v_opi THEN
    SELECT count(*) FILTER (WHERE o.estado = 'validada'), count(*) FILTER (WHERE o.estado = 'aguardando_validacao'), count(*) INTO n1, n2, n3
    FROM ia.opi o JOIN cadastro.motorista m ON m.id = o.motorista_id
    WHERE o.mes = v_mes AND o.estado <> 'cancelada' AND acesso.fn_ve_operacao(p_usuario, m.operacao_id);
    ind := ind || jsonb_build_object('codigo', 'opi_mes', 'rotulo', 'OPIs do mês', 'valor', CASE WHEN n3 = 0 THEN '—' ELSE n1 || '/' || n3 END,
      'nota', CASE WHEN n3 = 0 THEN 'nenhuma OPI no mês' ELSE n2 || ' aguardando validação' END, 'nivelNota', CASE WHEN n2 > 0 THEN 'medio' END);
    SELECT coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'titulo', m.nome, 'detalhe', 'OPI de ' || to_char(o.mes, 'MM/YYYY') || ' aguardando validação',
             'selo', 'Validar', 'nivel', 'medio') ORDER BY o.criado_em), '[]') INTO v_opilin
    FROM (SELECT * FROM ia.opi WHERE estado = 'aguardando_validacao' ORDER BY criado_em LIMIT 5) o
    JOIN cadastro.motorista m ON m.id = o.motorista_id WHERE acesso.fn_ve_operacao(p_usuario, m.operacao_id);
  END IF;

  -- ===== consumo de IA (R9, R13) =====
  IF v_consumo THEN
    v_teto := nullif(controle.fn_parametro('ia.teto_mensal') #>> '{}', 'null')::numeric;  -- ainda sem valor (aguarda o André)
    SELECT coalesce(sum(custo_usd), 0) INTO v_gasto FROM ia.consumo WHERE (em AT TIME ZONE 'America/Sao_Paulo')::date >= v_mes;
    ind := ind || jsonb_build_object('codigo', 'consumo_ia', 'rotulo', 'Consumo de IA no mês',
      'valor', CASE WHEN coalesce(v_teto, 0) <= 0 THEN '—' ELSE round(100 * v_gasto / v_teto) || '%' END,
      'nota', CASE WHEN coalesce(v_teto, 0) <= 0 THEN 'teto não definido · US$ ' || round(v_gasto, 2) || ' no mês' ELSE 'US$ ' || round(v_gasto, 2) || ' de ' || round(v_teto, 2) END,
      'nivelNota', CASE WHEN v_teto > 0 AND v_gasto / v_teto >= 0.8 THEN 'medio' END);
    SELECT coalesce(jsonb_agg(jsonb_build_object('id', x.agente, 'titulo', initcap(x.agente), 'detalhe', x.chamadas || ' chamada(s) no mês',
             'selo', 'US$ ' || round(x.custo, 2), 'nivel', 'neutro') ORDER BY x.custo DESC), '[]') INTO v_conslin
    FROM (SELECT agente, count(*) AS chamadas, sum(custo_usd) AS custo FROM ia.consumo
          WHERE (em AT TIME ZONE 'America/Sao_Paulo')::date >= v_mes GROUP BY agente) x;
  END IF;

  -- ===== integrações (R10, R12) =====
  IF v_integ THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object('fonte', f.nome, 'estado', controle.fn_estado_integracao(f.fonte),
             'texto', CASE controle.fn_estado_integracao(f.fonte)
               WHEN 'inativa' THEN 'não configurada'
               WHEN 'erro' THEN coalesce(CASE WHEN c.senha_mudou THEN 'credencial recusada' END, left(c.ultimo_erro, 80), 'com erro')
               ELSE concat_ws(' · ', 'último dado ' || controle.fn_ha(c.ultimo_sucesso),
                              CASE WHEN f.fonte = 'autotrac' THEN
                                (SELECT count(*) || ' eventos hoje' FROM bruto.autotrac_evento e
                                 WHERE e.horario >= (v_hoje::timestamp AT TIME ZONE 'America/Sao_Paulo')) END) END)
           ORDER BY f.ordem), '[]') INTO v_integ_lin
    FROM (VALUES (1, 'autotrac', 'Autotrac · Telemetria'), (2, 'autotrac_atic', 'Autotrac · ATIC'), (3, 'moovsec', 'Moovsec'),
                 (4, 'claude', 'IA (Claude)'), (5, 'datapar', 'Datapar')) f(ordem, fonte, nome)
    LEFT JOIN controle.credencial_status c ON c.fonte = f.fonte;

    SELECT count(*) FILTER (WHERE i->>'estado' = 'ok'), count(*) FILTER (WHERE i->>'estado' <> 'inativa') INTO n1, n2
    FROM jsonb_array_elements(v_integ_lin) i;
    SELECT i->>'fonte' || CASE i->>'estado' WHEN 'atraso' THEN ' com atraso' ELSE ' com erro' END INTO v_txt
    FROM jsonb_array_elements(v_integ_lin) i WHERE i->>'estado' IN ('erro', 'atraso') LIMIT 1;
    ind := ind || jsonb_build_object('codigo', 'integracoes', 'rotulo', 'Integrações', 'valor', n1 || '/' || n2,
      'nota', coalesce(v_txt, CASE WHEN n2 = 0 THEN 'nenhuma configurada' ELSE 'todas funcionando' END),
      'nivelNota', CASE WHEN v_txt IS NOT NULL THEN 'medio' WHEN n2 > 0 THEN 'ok' END);
  END IF;

  RETURN QUERY SELECT jsonb_build_object('geradoEm', now(), 'indicadores', ind, 'alertas', v_alertas, 'jornada', v_jlin,
    'opi', v_opilin, 'consumo', v_conslin, 'integracoes', v_integ_lin);
END $$;
