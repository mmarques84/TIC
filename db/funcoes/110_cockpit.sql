CREATE OR REPLACE FUNCTION derivado.sp_cockpit_resumo(
  p_usuario uuid, p_periodo text, p_operacao uuid, p_placa text, p_tipo text
)
RETURNS TABLE (resultado jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_inicio date;
  v_fim date;
  v_tipos constant text[] := derivado.fn_tipos_conducao();
  v_limite integer;
BEGIN
  PERFORM acesso.int_exigir(p_usuario, 'cockpit.ver');
  SELECT inicio, fim INTO v_inicio, v_fim FROM derivado.fn_periodo_conducao(p_periodo);
  v_limite := controle.fn_parametro_num('cockpit.motoristas_no_ranking')::integer;

  IF (p_tipo <> '' AND NOT (p_tipo = ANY(v_tipos)))
     OR (p_placa <> '' AND p_placa !~ '^[A-Za-z0-9-]{1,8}$') THEN
    RAISE EXCEPTION 'TIPO_INVALIDO' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY
  WITH veiculos AS MATERIALIZED (
    SELECT v.id, v.placa
    FROM cadastro.veiculo v
    WHERE (p_placa = '' OR v.placa LIKE '%' || replace(upper(p_placa), '-', '') || '%')
      AND (p_operacao IS NULL OR v.operacao_id = p_operacao)
      AND acesso.fn_ve_operacao(p_usuario, v.operacao_id)
  ), eventos AS MATERIALIZED (
    SELECT (e.horario AT TIME ZONE 'America/Sao_Paulo')::date AS dia, e.tipo, v.placa,
           e.motorista_id, nullif(nullif(btrim(e.codigo_motorista), ''), '0') AS codigo,
           nullif(btrim(e.dados->>'DriverName'), '') AS nome
    FROM bruto.autotrac_evento e
    JOIN veiculos v ON v.id = e.veiculo_id
    WHERE e.horario >= v_inicio::timestamp AT TIME ZONE 'America/Sao_Paulo'
      AND e.horario < v_fim::timestamp AT TIME ZONE 'America/Sao_Paulo'
      AND e.tipo = ANY(v_tipos)
      AND (p_tipo = '' OR e.tipo = p_tipo)
  ), agrupado AS (
    SELECT dia, tipo, count(*) AS total FROM eventos
    GROUP BY 1, 2
  ), diarios AS (
    SELECT v_inicio + d AS dia, coalesce(sum(a.total), 0) AS total
    FROM generate_series(0, v_fim - v_inicio - 1) d
    LEFT JOIN agrupado a ON a.dia = v_inicio + d
    GROUP BY d
  ), tipos AS (
    SELECT tipo, sum(total) AS total FROM agrupado GROUP BY tipo
  ), identificados AS (
    SELECT coalesce(m.id::text, 'autotrac:' || e.codigo) AS id,
           m.nome AS nome_cadastro, e.nome AS nome_autotrac, e.codigo, e.placa
    FROM eventos e
    LEFT JOIN cadastro.motorista atual ON atual.codigo_autotrac = e.codigo AND e.motorista_id IS NULL
    LEFT JOIN cadastro.motorista m ON m.id = coalesce(e.motorista_id, atual.id)
    WHERE e.motorista_id IS NOT NULL OR e.codigo IS NOT NULL
  ), motoristas AS (
    SELECT id, coalesce(nome_cadastro, max(nome_autotrac), 'Autotrac ' || max(codigo)) AS nome,
           nome_cadastro IS NOT NULL AS cadastrado,
           array_agg(DISTINCT placa ORDER BY placa) AS placas, count(*) AS total
    FROM identificados
    GROUP BY id, nome_cadastro
    ORDER BY total DESC, id
  ), frota AS (
    SELECT placa, count(*) AS total FROM eventos GROUP BY placa
  )
  SELECT jsonb_build_object(
    'total', coalesce((SELECT sum(total) FROM agrupado), 0),
    'dias', (SELECT jsonb_agg(to_jsonb(d) ORDER BY dia) FROM diarios d),
    'tipos', coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY total DESC, tipo) FROM tipos t), '[]'::jsonb),
    'motoristas', coalesce((SELECT jsonb_agg(to_jsonb(m) ORDER BY total DESC, id) FROM motoristas m), '[]'::jsonb),
    'veiculos', coalesce((SELECT jsonb_agg(to_jsonb(v) ORDER BY total DESC, placa) FROM frota v), '[]'::jsonb),
    'limiteDestaques', v_limite,
    'semMotorista', (SELECT count(*) FROM eventos WHERE motorista_id IS NULL AND codigo IS NULL),
    'operacoes', coalesce((SELECT jsonb_agg(jsonb_build_object('id', o.id, 'nome', o.nome) ORDER BY o.nome)
      FROM cadastro.operacao o WHERE acesso.fn_ve_operacao(p_usuario, o.id)), '[]'::jsonb),
    'atualizadoEm', (SELECT max(fim) FROM bruto.ingestao_lote WHERE fonte = 'autotrac_evento' AND estado = 'ok'),
    'estado', controle.fn_estado_integracao('autotrac')
  );
END $$;
