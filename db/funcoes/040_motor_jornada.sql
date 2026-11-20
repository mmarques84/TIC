-- Motor de jornada (spec motor-jornada). Recriado a cada deploy. Sem IA: só regra e parâmetro.
-- Entrada: bruto.autotrac_macro, bruto.autotrac_posicao, derivado.sessao_motorista.
-- Saída: derivado.jornada, derivado.parada, derivado.motorista_situacao, derivado.evento.

-- ===================== domínio (funções puras ou de leitura) =====================

CREATE OR REPLACE FUNCTION derivado.fn_minutos(p_de timestamptz, p_ate timestamptz)
RETURNS integer LANGUAGE sql IMMUTABLE AS $$
  SELECT greatest(0, floor(extract(epoch FROM (p_ate - p_de)) / 60))::integer
$$;

-- Parâmetro numérico da operação do motorista (ou global), já em minutos quando a unidade é hora.
CREATE OR REPLACE FUNCTION derivado.fn_limite_min(p_chave text, p_operacao uuid)
RETURNS integer LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v numeric := controle.fn_parametro_num(p_chave, p_operacao); u text;
BEGIN
  SELECT unidade INTO u FROM controle.parametro
  WHERE chave = p_chave AND vigencia @> now() AND (operacao_id = p_operacao OR operacao_id IS NULL)
  ORDER BY operacao_id IS NULL LIMIT 1;
  RETURN round(CASE WHEN u = 'h' THEN v * 60 ELSE v END)::integer;
END $$;

-- R7: minutos de direção e maior direção contínua de um veículo num intervalo.
-- Segmento = de uma posição até a próxima; anda se a velocidade passa de telemetria.parado_kmh.
-- Buraco maior que telemetria.intervalo_max não conta como direção. Pausa ≥ jornada.pausa_direcao zera a contínua.
CREATE OR REPLACE FUNCTION derivado.fn_direcao(p_veiculo uuid, p_de timestamptz, p_ate timestamptz, p_operacao uuid)
RETURNS TABLE (direcao_min integer, max_continua_min integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE
  v_parado numeric := controle.fn_parametro_num('telemetria.parado_kmh', p_operacao);
  v_gap integer := derivado.fn_limite_min('telemetria.intervalo_max', p_operacao) * 60;
  v_pausa integer := derivado.fn_limite_min('jornada.pausa_direcao', p_operacao) * 60;
  s record; v_total numeric := 0; v_run numeric := 0; v_max numeric := 0; v_parada numeric := 0;
BEGIN
  FOR s IN
    SELECT p.velocidade,
           extract(epoch FROM (least(coalesce(lead(p.horario) OVER (ORDER BY p.horario), p_ate), p_ate) - p.horario)) AS dur
    FROM bruto.autotrac_posicao p
    WHERE p.veiculo_id = p_veiculo AND p.horario >= p_de AND p.horario < p_ate
    ORDER BY p.horario
  LOOP
    IF coalesce(s.velocidade, 0) > v_parado AND s.dur <= v_gap THEN
      v_total := v_total + s.dur; v_run := v_run + s.dur; v_parada := 0;
      v_max := greatest(v_max, v_run);
    ELSE
      v_parada := v_parada + s.dur;
      IF v_parada >= v_pausa THEN v_run := 0; END IF;
    END IF;
  END LOOP;
  RETURN QUERY SELECT floor(v_total / 60)::integer, floor(v_max / 60)::integer;
END $$;

-- Km rodados por um veículo num intervalo (soma das distâncias entre posições).
CREATE OR REPLACE FUNCTION derivado.fn_km(p_veiculo uuid, p_de timestamptz, p_ate timestamptz)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT coalesce(round((sum(d) / 1000)::numeric, 1), 0) FROM (
    SELECT ST_Distance(local, lag(local) OVER (ORDER BY horario)) AS d
    FROM bruto.autotrac_posicao
    WHERE veiculo_id = p_veiculo AND horario >= p_de AND horario <= p_ate AND local IS NOT NULL
  ) x
$$;

-- Km rodados por um motorista (pelos veículos em que estava logado) num intervalo.
CREATE OR REPLACE FUNCTION derivado.fn_km_motorista(p_motorista uuid, p_de timestamptz, p_ate timestamptz)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT coalesce(sum(derivado.fn_km(s.veiculo_id, greatest(lower(s.periodo), p_de), least(coalesce(upper(s.periodo), p_ate), p_ate))), 0)
  FROM derivado.sessao_motorista s
  WHERE s.motorista_id = p_motorista AND s.periodo && tstzrange(p_de, p_ate)
$$;

CREATE OR REPLACE FUNCTION derivado.fn_texto_alerta(p_codigo text, p_valor text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_codigo
    WHEN 'jornada_excedida' THEN 'Jornada acima do limite do dia (' || p_valor || ')'
    WHEN 'jornada_aberta_longa' THEN 'Jornada aberta há ' || p_valor
    WHEN 'direcao_continua' THEN 'Direção contínua de ' || p_valor || ' (máx. 5h30)'
    WHEN 'refeicao_curta' THEN 'Refeição de ' || p_valor || ' (mín. 1 h)'
    WHEN 'interjornada_curta' THEN 'Interjornada de ' || p_valor || ' (mín. 11 h)'
    WHEN 'atencao_dia' THEN 'Perto do limite do dia (' || p_valor || ')'
    WHEN 'sem_fim' THEN 'Jornada sem fim lançado: conferir macro'
    WHEN 'inconsistente' THEN 'Início e fim com mais de 18 h: conferir'
    WHEN 'dsr' THEN p_valor || ' dias sem descanso semanal de 35 h'
    WHEN 'semana' THEN 'Semana com ' || p_valor || ' de trabalho'
    WHEN 'parado_35h_jornada_aberta' THEN 'Parado ' || p_valor || ' com jornada aberta: DSR ou espera?'
    WHEN 'parado_jornada_aberta' THEN 'Parado ' || p_valor || ' com jornada aberta'
    WHEN 'km_sem_jornada' THEN 'Rodou ' || p_valor || ' km hoje sem jornada aberta'
    WHEN 'outro_login' THEN 'Outro motorista logado no veículo (' || p_valor || ')'
    ELSE p_codigo END
$$;

CREATE OR REPLACE FUNCTION derivado.fn_hm(p_min integer)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT (p_min / 60) || 'h' || lpad((p_min % 60)::text, 2, '0')
$$;

-- ===================== gravação de uma jornada =====================

CREATE OR REPLACE FUNCTION derivado.int_gravar_jornada(p_motorista uuid, p_operacao uuid, p_veiculo uuid, p_inicio timestamptz,
  p_fim timestamptz, p_situacao text, p_refeicao integer, p_descanso integer, p_espera integer)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE
  v_ate timestamptz := coalesce(p_fim, now());
  v_amp integer := derivado.fn_minutos(p_inicio, v_ate);
  v_sit text := p_situacao;
  v_trab integer; v_dir integer := NULL; v_cont integer := NULL; v_mot jsonb := '[]'; v_id uuid;
BEGIN
  IF p_fim IS NOT NULL AND v_amp > derivado.fn_limite_min('jornada.inconsistente', p_operacao) THEN v_sit := 'inconsistente'; END IF;

  IF v_sit IN ('ok', 'em_curso') THEN
    -- R5, R6: líquido = amplitude − refeição (até o máximo) − descanso. Espera conta como jornada.
    v_trab := greatest(0, v_amp - least(p_refeicao, derivado.fn_limite_min('jornada.refeicao_max', p_operacao)) - p_descanso);
    IF p_veiculo IS NOT NULL THEN
      SELECT d.direcao_min, d.max_continua_min INTO v_dir, v_cont FROM derivado.fn_direcao(p_veiculo, p_inicio, v_ate, p_operacao) d;
    END IF;
    IF v_trab > derivado.fn_limite_min('jornada.limite_dia', p_operacao) THEN
      v_mot := v_mot || jsonb_build_object('codigo', 'jornada_excedida', 'nivel', 'violacao', 'valor', derivado.fn_hm(v_trab));
    ELSIF v_trab > derivado.fn_limite_min('jornada.atencao_dia', p_operacao) THEN
      v_mot := v_mot || jsonb_build_object('codigo', 'atencao_dia', 'nivel', 'atencao', 'valor', derivado.fn_hm(v_trab));
    END IF;
    IF v_sit = 'em_curso' AND v_amp > derivado.fn_limite_min('jornada.aberta_max', p_operacao) THEN
      v_mot := v_mot || jsonb_build_object('codigo', 'jornada_aberta_longa', 'nivel', 'violacao', 'valor', derivado.fn_hm(v_amp));
    END IF;
    IF v_cont IS NOT NULL AND v_cont > derivado.fn_limite_min('jornada.direcao_continua_max', p_operacao) THEN
      v_mot := v_mot || jsonb_build_object('codigo', 'direcao_continua', 'nivel', 'violacao', 'valor', derivado.fn_hm(v_cont));
    END IF;
    IF p_refeicao > 0 AND p_refeicao < derivado.fn_limite_min('jornada.refeicao_min', p_operacao) THEN
      v_mot := v_mot || jsonb_build_object('codigo', 'refeicao_curta', 'nivel', 'violacao', 'valor', derivado.fn_hm(p_refeicao));
    END IF;
  ELSE
    -- R8, R9: sem fim ou inconsistente não somam horas; pedem conferência.
    v_trab := NULL; v_amp := CASE WHEN v_sit = 'inconsistente' THEN v_amp ELSE NULL END;
    v_mot := v_mot || jsonb_build_object('codigo', v_sit, 'nivel', 'atencao', 'valor', '');
  END IF;

  INSERT INTO derivado.jornada (motorista_id, fonte, inicio, fim, amplitude_min, direcao_min, refeicao_min, descanso_min, trabalho_min,
                                max_direcao_continua_min, situacao, veiculo_id, dia, espera_min, motivos, calculado_em)
  VALUES (p_motorista, 'autotrac', p_inicio, p_fim, v_amp, v_dir, p_refeicao, p_descanso, v_trab,
          v_cont, v_sit, p_veiculo, (p_inicio AT TIME ZONE 'America/Sao_Paulo')::date, p_espera, v_mot, now())
  ON CONFLICT (motorista_id, fonte, inicio) DO UPDATE SET
    fim = EXCLUDED.fim, amplitude_min = EXCLUDED.amplitude_min, direcao_min = EXCLUDED.direcao_min,
    refeicao_min = EXCLUDED.refeicao_min, descanso_min = EXCLUDED.descanso_min, trabalho_min = EXCLUDED.trabalho_min,
    max_direcao_continua_min = EXCLUDED.max_direcao_continua_min, situacao = EXCLUDED.situacao, veiculo_id = EXCLUDED.veiculo_id,
    dia = EXCLUDED.dia, espera_min = EXCLUDED.espera_min, motivos = EXCLUDED.motivos, calculado_em = now()
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- ===================== cálculo de um motorista =====================

CREATE OR REPLACE FUNCTION derivado.int_jornada_motorista(p_motorista uuid, p_desde timestamptz)
RETURNS TABLE (jornadas integer, eventos integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE
  v_op uuid := (SELECT operacao_id FROM cadastro.motorista WHERE id = p_motorista);
  v_tz constant text := 'America/Sao_Paulo';
  mc record; j record; pa record;
  v_ini timestamptz; v_vei uuid; v_ref integer := 0; v_par integer := 0; v_esp integer := 0;
  v_ref_ini timestamptz; v_par_ini timestamptz; v_esp_ini timestamptz;
  v_mantidas uuid[] := '{}'; v_desconhecidas integer := 0; v_ultimo_vei uuid; v_tem_macro boolean := false;
  v_prev_fim timestamptz; v_inter integer; v_nivel text;
  v_atual uuid; v_status text; v_parado_desde timestamptz; v_ult_dsr timestamptz; v_dias integer; v_semana integer;
  v_alertas jsonb := '[]'; v_nivel_mot text := 'dentro'; v_hoje timestamptz; v_km numeric; v_outro text;
  v_ev integer := 0; v_n integer := 0; v_parado_kmh numeric; v_raio integer;
  v_viol constant text[] := ARRAY['jornada_excedida', 'jornada_aberta_longa', 'direcao_continua', 'refeicao_curta', 'interjornada_curta'];
BEGIN
  -- 1) Jornadas a partir das macros (R4–R9). Começa no primeiro início de jornada da janela.
  FOR mc IN
    SELECT a.horario, a.veiculo_id, m.significado
    FROM bruto.autotrac_macro a
    LEFT JOIN controle.macro_mapa m ON m.fonte = 'autotrac' AND m.numero = a.numero
    WHERE a.motorista_id = p_motorista AND a.horario >= p_desde
    ORDER BY a.horario
  LOOP
    v_tem_macro := true; v_ultimo_vei := mc.veiculo_id;
    IF mc.significado IS NULL THEN v_desconhecidas := v_desconhecidas + 1; CONTINUE; END IF;  -- R2
    CASE mc.significado
      WHEN 'inicio_jornada' THEN
        IF v_ini IS NOT NULL THEN  -- início sem fim do anterior
          v_mantidas := v_mantidas || derivado.int_gravar_jornada(p_motorista, v_op, v_vei, v_ini, NULL, 'sem_fim', v_ref, v_par, v_esp);
        END IF;
        v_ini := mc.horario; v_vei := mc.veiculo_id; v_ref := 0; v_par := 0; v_esp := 0;
        v_ref_ini := NULL; v_par_ini := NULL; v_esp_ini := NULL;
      WHEN 'inicio_refeicao' THEN IF v_ini IS NOT NULL THEN v_ref_ini := mc.horario; END IF;
      WHEN 'fim_refeicao' THEN
        IF v_ref_ini IS NOT NULL THEN v_ref := v_ref + derivado.fn_minutos(v_ref_ini, mc.horario); v_ref_ini := NULL; END IF;
      WHEN 'inicio_parada' THEN
        IF v_ini IS NOT NULL THEN
          IF v_ref_ini IS NOT NULL THEN v_ref := v_ref + derivado.fn_minutos(v_ref_ini, mc.horario); v_ref_ini := NULL; END IF;
          v_par_ini := mc.horario;
        END IF;
      WHEN 'fim_parada' THEN
        IF v_par_ini IS NOT NULL THEN v_par := v_par + derivado.fn_minutos(v_par_ini, mc.horario); v_par_ini := NULL; END IF;
      WHEN 'inicio_espera' THEN IF v_ini IS NOT NULL THEN v_esp_ini := mc.horario; END IF;
      WHEN 'fim_espera' THEN
        IF v_esp_ini IS NOT NULL THEN v_esp := v_esp + derivado.fn_minutos(v_esp_ini, mc.horario); v_esp_ini := NULL; END IF;
      WHEN 'fim_jornada' THEN
        IF v_ini IS NOT NULL THEN
          -- refeição/parada sem fim lançado terminam com a jornada
          IF v_ref_ini IS NOT NULL THEN v_ref := v_ref + derivado.fn_minutos(v_ref_ini, mc.horario); END IF;
          IF v_par_ini IS NOT NULL THEN v_par := v_par + derivado.fn_minutos(v_par_ini, mc.horario); END IF;
          IF v_esp_ini IS NOT NULL THEN v_esp := v_esp + derivado.fn_minutos(v_esp_ini, mc.horario); END IF;
          v_mantidas := v_mantidas || derivado.int_gravar_jornada(p_motorista, v_op, v_vei, v_ini, mc.horario, 'ok', v_ref, v_par, v_esp);
          v_ini := NULL; v_ref_ini := NULL; v_par_ini := NULL; v_esp_ini := NULL;
        END IF;
      ELSE NULL;  -- ignorar
    END CASE;
  END LOOP;

  IF v_ini IS NOT NULL THEN  -- R8: aberta
    v_mantidas := v_mantidas || derivado.int_gravar_jornada(p_motorista, v_op, v_vei, v_ini, NULL,
      CASE WHEN derivado.fn_minutos(v_ini, now()) <= derivado.fn_limite_min('jornada.em_curso_max', v_op) THEN 'em_curso' ELSE 'sem_fim' END,
      v_ref + CASE WHEN v_ref_ini IS NOT NULL THEN derivado.fn_minutos(v_ref_ini, now()) ELSE 0 END,
      v_par + CASE WHEN v_par_ini IS NOT NULL THEN derivado.fn_minutos(v_par_ini, now()) ELSE 0 END, v_esp);
  END IF;

  -- Jornadas antigas da janela que não existem mais (macro corrigida): apaga se nada aponta para elas.
  UPDATE derivado.motorista_situacao SET jornada_atual_id = NULL WHERE motorista_id = p_motorista;
  DELETE FROM derivado.jornada jj
  WHERE jj.motorista_id = p_motorista AND jj.fonte = 'autotrac' AND jj.inicio >= p_desde AND NOT (jj.id = ANY (v_mantidas))
    AND NOT EXISTS (SELECT 1 FROM derivado.tratativa t WHERE t.jornada_id = jj.id);

  -- 2) Interjornada e nível de cada jornada (R13, R10).
  v_prev_fim := (SELECT max(fim) FROM derivado.jornada WHERE motorista_id = p_motorista AND fonte = 'autotrac' AND inicio < p_desde);
  FOR j IN SELECT id, inicio, fim, motivos FROM derivado.jornada
           WHERE motorista_id = p_motorista AND fonte = 'autotrac' AND inicio >= p_desde ORDER BY inicio LOOP
    v_inter := CASE WHEN v_prev_fim IS NOT NULL AND v_prev_fim <= j.inicio THEN derivado.fn_minutos(v_prev_fim, j.inicio) END;
    IF v_inter IS NOT NULL AND v_inter < derivado.fn_limite_min('jornada.interjornada_min', v_op) THEN
      j.motivos := j.motivos || jsonb_build_object('codigo', 'interjornada_curta', 'nivel', 'violacao', 'valor', derivado.fn_hm(v_inter));
    END IF;
    v_nivel := CASE
      WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(j.motivos) e WHERE e->>'nivel' = 'violacao') THEN 'violacao'
      WHEN jsonb_array_length(j.motivos) > 0 THEN 'atencao' ELSE 'dentro' END;
    UPDATE derivado.jornada SET interjornada_min = v_inter, motivos = j.motivos, nivel = v_nivel WHERE id = j.id;
    IF j.fim IS NOT NULL THEN v_prev_fim := j.fim; END IF;
    v_n := v_n + 1;
  END LOOP;

  -- 3) Paradas longas pelas posições (R15–R17).
  v_parado_kmh := controle.fn_parametro_num('telemetria.parado_kmh', v_op);
  v_raio := controle.fn_parametro_num('parada.raio', v_op)::integer;
  DELETE FROM derivado.parada WHERE motorista_id = p_motorista AND lower(periodo) >= p_desde;
  FOR pa IN
    WITH p AS (
      SELECT po.horario, po.local, coalesce(po.velocidade, 0) <= v_parado_kmh AS parado
      FROM bruto.autotrac_posicao po
      WHERE po.veiculo_id = v_ultimo_vei AND po.horario >= p_desde
    ), g AS (
      SELECT *, sum(CASE WHEN parado THEN 0 ELSE 1 END) OVER (ORDER BY horario) AS grp FROM p
    ), s AS (
      SELECT grp, min(horario) AS ini, max(horario) AS fim, (array_agg(local ORDER BY horario))[1] AS ancora,
             bool_and(local IS NOT NULL) AS tem_local
      FROM g WHERE parado GROUP BY grp
    )
    SELECT s.ini, s.fim, s.ancora,
           (SELECT max(ST_Distance(g2.local, s.ancora)) FROM g g2 WHERE g2.grp = s.grp AND g2.parado) AS espalhamento,
           (s.fim = (SELECT max(horario) FROM p)) AS atual
    FROM s
    WHERE s.tem_local AND derivado.fn_minutos(s.ini, s.fim) >= derivado.fn_limite_min('parada.minima', v_op)
  LOOP
    CONTINUE WHEN pa.espalhamento > v_raio;
    v_km := derivado.fn_km_motorista(p_motorista, pa.ini, pa.fim);
    INSERT INTO derivado.parada (motorista_id, veiculo_id, periodo, local, houve_jornada_aberta, km_telemetria, conta_dsr)
    VALUES (p_motorista, v_ultimo_vei, tstzrange(pa.ini, pa.fim, '[]'), pa.ancora,
      EXISTS (SELECT 1 FROM derivado.jornada jj WHERE jj.motorista_id = p_motorista AND jj.situacao IN ('ok', 'em_curso')
              AND tstzrange(jj.inicio, coalesce(jj.fim, now())) && tstzrange(pa.ini, pa.fim)
              AND derivado.fn_minutos(greatest(jj.inicio, pa.ini), least(coalesce(jj.fim, now()), pa.fim)) >= 60),
      v_km,
      derivado.fn_minutos(pa.ini, pa.fim) >= derivado.fn_limite_min('jornada.dsr', v_op)
        AND v_km <= controle.fn_parametro_num('parada.km_invalida_dsr', v_op));
    IF pa.atual THEN v_parado_desde := pa.ini; END IF;
  END LOOP;

  -- 4) Retrato atual (R16–R21).
  SELECT id INTO v_atual FROM derivado.jornada WHERE motorista_id = p_motorista AND situacao = 'em_curso' ORDER BY inicio DESC LIMIT 1;
  v_ult_dsr := (SELECT max(upper(periodo)) FROM derivado.parada WHERE motorista_id = p_motorista AND conta_dsr);
  v_dias := (SELECT count(DISTINCT dia) FROM derivado.jornada
             WHERE motorista_id = p_motorista AND situacao IN ('ok', 'em_curso') AND inicio > coalesce(v_ult_dsr, p_desde));
  v_semana := coalesce((SELECT sum(trabalho_min) FROM derivado.jornada
              WHERE motorista_id = p_motorista AND dia >= date_trunc('week', now() AT TIME ZONE v_tz)::date), 0);
  v_hoje := date_trunc('day', now() AT TIME ZONE v_tz) AT TIME ZONE v_tz;

  IF NOT v_tem_macro THEN v_status := 'sem_eventos';
  ELSIF v_atual IS NULL THEN v_status := 'fora_jornada';
  ELSIF v_ref_ini IS NOT NULL THEN v_status := 'refeicao';
  ELSIF v_par_ini IS NOT NULL THEN v_status := 'parada_descanso';
  ELSIF coalesce((SELECT velocidade FROM bruto.autotrac_posicao WHERE veiculo_id = v_ultimo_vei ORDER BY horario DESC LIMIT 1), 0) > v_parado_kmh
    THEN v_status := 'dirigindo';
  ELSE v_status := 'em_jornada';
  END IF;

  -- alertas: jornada atual e jornadas de hoje
  SELECT coalesce(jsonb_agg(DISTINCT e), '[]') INTO v_alertas
  FROM derivado.jornada jj, jsonb_array_elements(jj.motivos) e
  WHERE jj.motorista_id = p_motorista AND (jj.id = v_atual OR jj.inicio >= v_hoje)
    AND NOT (e->>'codigo' IN ('sem_fim', 'inconsistente')
             AND EXISTS (SELECT 1 FROM derivado.tratativa t WHERE t.jornada_id = jj.id));  -- R24
  IF v_dias >= derivado.fn_limite_min('jornada.dias_sem_dsr.alerta', v_op) THEN
    v_alertas := v_alertas || jsonb_build_object('codigo', 'dsr', 'nivel', 'violacao', 'valor', v_dias::text);
  ELSIF v_dias >= derivado.fn_limite_min('jornada.dias_sem_dsr.atencao', v_op) THEN
    v_alertas := v_alertas || jsonb_build_object('codigo', 'dsr', 'nivel', 'atencao', 'valor', v_dias::text);
  END IF;
  IF v_semana > derivado.fn_limite_min('jornada.limite_semana', v_op) THEN
    v_alertas := v_alertas || jsonb_build_object('codigo', 'semana', 'nivel', 'violacao', 'valor', derivado.fn_hm(v_semana));
  ELSIF v_semana >= derivado.fn_limite_min('jornada.atencao_semana', v_op) THEN
    v_alertas := v_alertas || jsonb_build_object('codigo', 'semana', 'nivel', 'atencao', 'valor', derivado.fn_hm(v_semana));
  END IF;
  -- parado agora com jornada aberta (R17, R20)
  IF v_parado_desde IS NOT NULL AND v_atual IS NOT NULL THEN
    IF derivado.fn_minutos(v_parado_desde, now()) >= derivado.fn_limite_min('jornada.dsr', v_op) THEN
      IF NOT EXISTS (SELECT 1 FROM derivado.tratativa t WHERE t.motorista_id = p_motorista AND t.criado_em >= v_parado_desde) THEN
        v_alertas := v_alertas || jsonb_build_object('codigo', 'parado_35h_jornada_aberta', 'nivel', 'conferir', 'valor', derivado.fn_hm(derivado.fn_minutos(v_parado_desde, now())));
      END IF;
    ELSIF derivado.fn_minutos(v_parado_desde, now()) >= derivado.fn_limite_min('jornada.parado_sem_descarga', v_op) THEN
      v_alertas := v_alertas || jsonb_build_object('codigo', 'parado_jornada_aberta', 'nivel', 'atencao', 'valor', derivado.fn_hm(derivado.fn_minutos(v_parado_desde, now())));
    END IF;
  END IF;
  -- R18: km hoje fora de jornada
  SELECT coalesce(sum(derivado.fn_km(s.veiculo_id, greatest(lower(s.periodo), v_hoje), least(coalesce(upper(s.periodo), now()), now()))), 0) INTO v_km
  FROM derivado.sessao_motorista s
  WHERE s.motorista_id = p_motorista AND s.periodo && tstzrange(v_hoje, now())
    AND NOT EXISTS (SELECT 1 FROM derivado.jornada jj WHERE jj.motorista_id = p_motorista
                    AND tstzrange(jj.inicio, coalesce(jj.fim, now())) && s.periodo);
  IF v_km > controle.fn_parametro_num('telemetria.km_sem_jornada', v_op)
     AND NOT EXISTS (SELECT 1 FROM derivado.tratativa t WHERE t.motorista_id = p_motorista AND t.criado_em >= v_hoje) THEN
    v_alertas := v_alertas || jsonb_build_object('codigo', 'km_sem_jornada', 'nivel', 'conferir', 'valor', v_km::text);
  END IF;
  -- R19: outro motorista logado no veículo da jornada aberta
  IF v_atual IS NOT NULL THEN
    SELECT mo.nome INTO v_outro FROM derivado.sessao_motorista s JOIN cadastro.motorista mo ON mo.id = s.motorista_id
    WHERE s.veiculo_id = (SELECT veiculo_id FROM derivado.jornada WHERE id = v_atual)
      AND s.motorista_id <> p_motorista AND s.periodo @> now() LIMIT 1;
    IF v_outro IS NOT NULL THEN
      v_alertas := v_alertas || jsonb_build_object('codigo', 'outro_login', 'nivel', 'conferir', 'valor', v_outro);
    END IF;
  END IF;

  SELECT coalesce(jsonb_agg(a || jsonb_build_object('texto', derivado.fn_texto_alerta(a->>'codigo', a->>'valor'))), '[]') INTO v_alertas
  FROM jsonb_array_elements(v_alertas) a;
  v_nivel_mot := CASE
    WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(v_alertas) a WHERE a->>'nivel' = 'violacao') THEN 'violacao'
    WHEN EXISTS (SELECT 1 FROM jsonb_array_elements(v_alertas) a WHERE a->>'nivel' = 'conferir') THEN 'conferir'
    WHEN jsonb_array_length(v_alertas) > 0 THEN 'atencao' ELSE 'dentro' END;

  INSERT INTO derivado.motorista_situacao (motorista_id, status, veiculo_id, parado_desde, ultimo_dsr, dias_sem_dsr, alertas,
    jornada_atual_id, trabalho_semana_min, macros_desconhecidas, nivel, atualizado_em)
  VALUES (p_motorista, v_status, v_ultimo_vei, v_parado_desde, v_ult_dsr, v_dias, v_alertas, v_atual, v_semana, v_desconhecidas, v_nivel_mot, now())
  ON CONFLICT (motorista_id) DO UPDATE SET status = EXCLUDED.status, veiculo_id = coalesce(EXCLUDED.veiculo_id, derivado.motorista_situacao.veiculo_id),
    parado_desde = EXCLUDED.parado_desde, ultimo_dsr = EXCLUDED.ultimo_dsr, dias_sem_dsr = EXCLUDED.dias_sem_dsr, alertas = EXCLUDED.alertas,
    jornada_atual_id = EXCLUDED.jornada_atual_id, trabalho_semana_min = EXCLUDED.trabalho_semana_min,
    macros_desconhecidas = EXCLUDED.macros_desconhecidas, nivel = EXCLUDED.nivel, atualizado_em = now();

  -- 5) Eventos de violação, um por ocorrência (R22).
  WITH novos AS (
    INSERT INTO derivado.evento (veiculo_id, motorista_id, horario, tipo, origem, gravidade, regra, dados, chave)
    SELECT jj.veiculo_id, p_motorista, coalesce(jj.fim, now()), 'jornada_' || (e->>'codigo'), 'regra', 'grave',
           'jornada.' || (e->>'codigo'), jsonb_build_object('jornada_id', jj.id, 'valor', e->>'valor'),
           'jornada:' || jj.id || ':' || (e->>'codigo')
    FROM derivado.jornada jj, jsonb_array_elements(jj.motivos) e
    WHERE jj.motorista_id = p_motorista AND jj.inicio >= p_desde AND jj.veiculo_id IS NOT NULL AND (e->>'codigo') = ANY (v_viol)
    ON CONFLICT (chave) WHERE chave IS NOT NULL DO NOTHING
    RETURNING 1
  ) SELECT count(*) INTO v_ev FROM novos;
  IF v_dias >= derivado.fn_limite_min('jornada.dias_sem_dsr.alerta', v_op) AND v_ultimo_vei IS NOT NULL THEN
    INSERT INTO derivado.evento (veiculo_id, motorista_id, horario, tipo, origem, gravidade, regra, dados, chave)
    VALUES (v_ultimo_vei, p_motorista, now(), 'jornada_dsr', 'regra', 'grave', 'jornada.dias_sem_dsr.alerta',
            jsonb_build_object('dias', v_dias), 'dsr:' || p_motorista || ':' || coalesce(to_char(v_ult_dsr, 'YYYYMMDDHH24MI'), 'nunca'))
    ON CONFLICT (chave) WHERE chave IS NOT NULL DO NOTHING;
    IF FOUND THEN v_ev := v_ev + 1; END IF;
  END IF;

  RETURN QUERY SELECT v_n, v_ev;
END $$;

-- ===================== job (chamado pelo n8n depois de cada ingestão) =====================

CREATE OR REPLACE FUNCTION derivado.job_jornada(p_desde timestamptz DEFAULT NULL, p_motorista uuid DEFAULT NULL)
RETURNS TABLE (motoristas integer, jornadas integer, eventos integer)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE
  v_desde timestamptz := coalesce(p_desde, now() - interval '8 days');
  m record; r record; v_m integer := 0; v_j integer := 0; v_e integer := 0;
BEGIN
  FOR m IN
    SELECT mo.id FROM cadastro.motorista mo
    WHERE mo.ativo AND NOT mo.sem_controle_jornada  -- R23
      AND (p_motorista IS NULL OR mo.id = p_motorista)
      AND (p_motorista IS NOT NULL OR EXISTS (SELECT 1 FROM bruto.autotrac_macro a WHERE a.motorista_id = mo.id AND a.horario >= v_desde))
  LOOP
    SELECT * INTO r FROM derivado.int_jornada_motorista(m.id, v_desde);
    v_m := v_m + 1; v_j := v_j + r.jornadas; v_e := v_e + r.eventos;
  END LOOP;
  RETURN QUERY SELECT v_m, v_j, v_e;
END $$;

-- ===================== mapa de macros (admin; R1) =====================

DROP FUNCTION IF EXISTS controle.sp_macro_mapa_listar(uuid);
CREATE FUNCTION controle.sp_macro_mapa_listar(p_usuario uuid)
RETURNS TABLE (macros jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
BEGIN
  PERFORM acesso.int_exigir(p_usuario, 'parametro.ver');
  RETURN QUERY SELECT coalesce(jsonb_agg(jsonb_build_object('fonte', fonte, 'numero', numero, 'significado', significado, 'descricao', descricao)
                 ORDER BY fonte, numero), '[]') FROM controle.macro_mapa;
END $$;

CREATE OR REPLACE FUNCTION controle.sp_macro_mapa_definir(p_usuario uuid, p_fonte text, p_numero smallint, p_significado text, p_descricao text, p_ip inet)
RETURNS TABLE (ok boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE v_antes jsonb;
BEGIN
  PERFORM acesso.int_exigir(p_usuario, 'parametro.editar');
  SELECT to_jsonb(m) INTO v_antes FROM controle.macro_mapa m WHERE fonte = p_fonte AND numero = p_numero;
  INSERT INTO controle.macro_mapa (fonte, numero, significado, descricao, alterado_por, alterado_em)
  VALUES (p_fonte, p_numero, p_significado, p_descricao, p_usuario, now())
  ON CONFLICT (fonte, numero) DO UPDATE SET significado = EXCLUDED.significado, descricao = EXCLUDED.descricao,
    alterado_por = EXCLUDED.alterado_por, alterado_em = now();
  INSERT INTO controle.auditoria (usuario_id, acao, entidade, entidade_id, antes, depois, ip)
  VALUES (p_usuario, 'macro.definir', 'controle.macro_mapa', p_fonte || ':' || p_numero, v_antes,
          jsonb_build_object('significado', p_significado, 'descricao', p_descricao), p_ip);
  RETURN QUERY SELECT true;
END $$;
