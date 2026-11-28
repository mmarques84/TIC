CREATE OR REPLACE FUNCTION derivado.fn_tipos_conducao()
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
  SELECT ARRAY[
    'aceleracao_brusca', 'freada_brusca', 'banguela', 'fora_faixa_verde',
    'rpm_excessiva', 'velocidade_excessiva', 'velocidade_excessiva_chuva',
    'marcha_lenta_excessiva', 'pressao_oleo_baixa', 'pressao_oleo_alta'
  ]
$$;

CREATE OR REPLACE FUNCTION derivado.fn_periodo_conducao(p_periodo text)
RETURNS TABLE (inicio date, fim date) LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_hoje date := (now() AT TIME ZONE 'America/Sao_Paulo')::date;
  v_mes date := date_trunc('month', v_hoje::timestamp)::date;
BEGIN
  fim := v_hoje + 1;
  CASE coalesce(nullif(p_periodo, ''), '7')
    WHEN '7' THEN inicio := v_hoje - 6;
    WHEN 'hoje' THEN inicio := v_hoje;
    WHEN 'mes' THEN inicio := v_mes;
    WHEN 'anterior' THEN inicio := (v_mes - interval '1 month')::date; fim := v_mes;
    ELSE RAISE EXCEPTION 'TIPO_INVALIDO' USING ERRCODE = 'P0001';
  END CASE;
  RETURN NEXT;
END $$;

CREATE OR REPLACE FUNCTION derivado.sp_conducao_eventos(
  p_usuario uuid, p_periodo text, p_placa text, p_tipo text, p_cursor text,
  p_motorista text, p_operacao uuid
)
RETURNS TABLE (resultado jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_inicio date;
  v_fim date;
  v_cursor text[] := string_to_array(p_cursor, '|');
  v_limite integer := controle.fn_parametro_num('conducao.eventos_por_pagina')::integer;
  v_tipos constant text[] := derivado.fn_tipos_conducao();
BEGIN
  PERFORM acesso.int_exigir(p_usuario, 'conducao.ver');
  SELECT inicio, fim INTO v_inicio, v_fim FROM derivado.fn_periodo_conducao(p_periodo);

  IF (p_tipo <> '' AND NOT (p_tipo = ANY(v_tipos)))
     OR (p_placa <> '' AND p_placa !~ '^[A-Za-z0-9-]{1,8}$')
     OR (p_cursor <> '' AND cardinality(v_cursor) <> 3) THEN
    RAISE EXCEPTION 'TIPO_INVALIDO' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY
  WITH pagina AS (
    SELECT e.horario, e.veiculo_id, e.tipo, v.placa,
      coalesce(m.nome, nullif(btrim(e.dados->>'DriverName'), '')) AS motorista
    FROM bruto.autotrac_evento e
    JOIN cadastro.veiculo v ON v.id = e.veiculo_id
    LEFT JOIN cadastro.motorista atual ON e.motorista_id IS NULL AND atual.codigo_autotrac = nullif(nullif(btrim(e.codigo_motorista), ''), '0')
    LEFT JOIN cadastro.motorista m ON m.id = coalesce(e.motorista_id, atual.id)
    WHERE e.horario >= v_inicio::timestamp AT TIME ZONE 'America/Sao_Paulo'
      AND e.horario < v_fim::timestamp AT TIME ZONE 'America/Sao_Paulo'
      AND e.tipo = ANY(v_tipos)
      AND (p_tipo = '' OR e.tipo = p_tipo)
      AND (p_placa = '' OR v.placa LIKE '%' || replace(upper(p_placa), '-', '') || '%')
      AND acesso.fn_ve_operacao(p_usuario, v.operacao_id)
      AND (p_operacao IS NULL OR v.operacao_id = p_operacao)
      AND (coalesce(p_motorista, '') = '' OR
           p_motorista = coalesce(m.id::text, 'autotrac:' || nullif(nullif(btrim(e.codigo_motorista), ''), '0')))
      AND (p_cursor = '' OR
           (e.horario, e.veiculo_id, e.tipo) < (v_cursor[1]::timestamptz, v_cursor[2]::uuid, v_cursor[3]))
    ORDER BY e.horario DESC, e.veiculo_id DESC, e.tipo DESC
    LIMIT v_limite + 1
  ), linhas AS (
    SELECT *, concat_ws('|', horario, veiculo_id, tipo) AS cursor
    FROM pagina ORDER BY horario DESC, veiculo_id DESC, tipo DESC LIMIT v_limite
  )
  SELECT jsonb_build_object(
    'eventos', coalesce((SELECT jsonb_agg(jsonb_build_object(
      'horario', horario, 'placa', placa, 'motorista', motorista, 'tipo', tipo
    ) ORDER BY horario DESC, veiculo_id DESC, tipo DESC) FROM linhas), '[]'::jsonb),
    'proximo', CASE WHEN (SELECT count(*) FROM pagina) > v_limite
      THEN (SELECT cursor FROM linhas ORDER BY horario, veiculo_id, tipo LIMIT 1) END,
    'atualizadoEm', (SELECT max(fim) FROM bruto.ingestao_lote WHERE fonte = 'autotrac_evento' AND estado = 'ok'),
    'estado', controle.fn_estado_integracao('autotrac')
  );
EXCEPTION WHEN invalid_text_representation OR invalid_datetime_format OR datetime_field_overflow THEN
  RAISE EXCEPTION 'TIPO_INVALIDO' USING ERRCODE = 'P0001';
END $$;

CREATE OR REPLACE FUNCTION derivado.sp_conducao_eventos(
  p_usuario uuid, p_periodo text, p_placa text, p_tipo text, p_cursor text
)
RETURNS TABLE (resultado jsonb)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT * FROM derivado.sp_conducao_eventos(p_usuario, p_periodo, p_placa, p_tipo, p_cursor, '', NULL)
$$;
