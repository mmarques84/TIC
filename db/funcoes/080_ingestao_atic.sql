-- Ingestão da Autotrac, fase B: API ATIC (spec ingestao-autotrac R16–R19). Recriado a cada deploy.
-- Posições → bruto.autotrac_posicao · macros → bruto.autotrac_macro · login/logout → bruto.autotrac_login
-- → derivado.sessao_motorista (quem dirigia) → motor de jornada (job_jornada) só para os motoristas afetados.

-- ===================== domínio =====================

-- O login da ATIC não traz código do motorista, só nome e CPF. O CPF não é guardado (em aberto na spec);
-- liga pelo nome: só quando há exatamente um motorista ativo com aquele nome (sem diferença de maiúscula/espaço).
CREATE OR REPLACE FUNCTION cadastro.fn_motorista_por_nome(p_nome text)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, public AS $$
  SELECT CASE WHEN count(*) = 1 THEN min(id::text)::uuid END
  FROM cadastro.motorista
  WHERE ativo AND lower(regexp_replace(btrim(nome), '\s+', ' ', 'g')) = lower(regexp_replace(btrim(coalesce(p_nome, '')), '\s+', ' ', 'g'))
$$;

-- ===================== internos =====================

-- Refaz as sessões (quem estava logado) de um veículo a partir dos logins e logouts recebidos.
-- Cada login vale até o próximo logout ou o próximo login do mesmo veículo; sem fim = ainda logado.
CREATE OR REPLACE FUNCTION derivado.int_sessoes_veiculo(p_veiculo uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
DECLARE v_n integer;
BEGIN
  DELETE FROM derivado.sessao_motorista WHERE veiculo_id = p_veiculo;
  INSERT INTO derivado.sessao_motorista (motorista_id, veiculo_id, periodo)
  SELECT x.motorista_id, p_veiculo, tstzrange(x.horario, x.fim, '[)')
  FROM (
    SELECT l.tipo, l.motorista_id, l.horario,
           lead(l.horario) OVER (ORDER BY l.horario, l.tipo DESC) AS fim
    FROM bruto.autotrac_login l
    WHERE l.veiculo_id = p_veiculo
  ) x
  WHERE x.tipo = 'login' AND x.motorista_id IS NOT NULL AND (x.fim IS NULL OR x.fim > x.horario);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;

-- ===================== casos de uso do lote (n8n) =====================

-- R16–R18: grava o que veio de um recurso da ATIC para um veículo. Idempotente (chaves únicas das tabelas bruto.*).
-- p_recurso: 'driverlogs' (vem primeiro no ciclo), 'positions' ou 'returnmessages'. Nunca guarda CPF.
CREATE OR REPLACE FUNCTION bruto.job_autotrac_atic(p_lote uuid, p_veiculo uuid, p_recurso text, p_itens jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE
  i jsonb; v_h timestamptz; v_fim timestamptz; v_n integer; v_mot uuid; v_cod text; v_mapa text;
  v_gravados integer := 0; v_repetidos integer := 0; v_ignorados integer := 0; v_fora integer := 0;
  v_min timestamptz := now() - make_interval(days => controle.fn_parametro_num('autotrac.retencao_dias')::integer + 1);
  v_max timestamptz := now() + interval '1 day';
BEGIN
  IF p_recurso NOT IN ('driverlogs', 'positions', 'returnmessages') THEN RAISE EXCEPTION 'RECURSO_INVALIDO' USING ERRCODE = 'P0001'; END IF;
  IF NOT EXISTS (SELECT 1 FROM cadastro.veiculo WHERE id = p_veiculo) THEN RAISE EXCEPTION 'VEICULO_INEXISTENTE' USING ERRCODE = 'P0001'; END IF;

  FOR i IN SELECT * FROM jsonb_array_elements(coalesce(p_itens, '[]')) LOOP
    IF p_recurso = 'positions' THEN
      v_h := nullif(i->>'PositionTime', '')::timestamptz;
      IF v_h IS NULL THEN v_ignorados := v_ignorados + 1; CONTINUE; END IF;
      IF v_h < v_min OR v_h > v_max THEN v_fora := v_fora + 1; CONTINUE; END IF;
      INSERT INTO bruto.autotrac_posicao (veiculo_id, horario, local, velocidade, ignicao, odometro_km, canal, lote_id)
      VALUES (p_veiculo, v_h,
              bruto.fn_ponto(nullif(i->>'Latitude', '')::numeric, nullif(i->>'Longitude', '')::numeric),
              bruto.fn_velocidade(nullif(i->>'Velocity', '')::numeric),
              CASE i->>'VehicleIgnition' WHEN '1' THEN true WHEN '2' THEN false END,
              -- R16: a ATIC manda o hodômetro × 100
              CASE WHEN nullif(i->>'Odometer', '')::numeric / 100 BETWEEN 0 AND 999999999 THEN round(nullif(i->>'Odometer', '')::numeric / 100, 1) END,
              CASE i->>'TransmissionChannel' WHEN '32' THEN 'celular' WHEN '33' THEN 'satelite' END,
              p_lote)
      ON CONFLICT (veiculo_id, horario) DO NOTHING;

    ELSIF p_recurso = 'returnmessages' THEN
      -- R17: só macro (MacroNumber > 0); mensagem livre (0) não entra.
      IF coalesce(nullif(i->>'MacroNumber', '')::integer, 0) <= 0 THEN v_ignorados := v_ignorados + 1; CONTINUE; END IF;
      v_h := nullif(i->>'MessageTime', '')::timestamptz;
      IF v_h IS NULL THEN v_ignorados := v_ignorados + 1; CONTINUE; END IF;
      IF v_h < v_min OR v_h > v_max THEN v_fora := v_fora + 1; CONTINUE; END IF;
      -- quem dirigia: a sessão aberta naquele instante (os logins do ciclo são gravados antes das macros)
      SELECT s.motorista_id INTO v_mot FROM derivado.sessao_motorista s WHERE s.veiculo_id = p_veiculo AND s.periodo @> v_h LIMIT 1;
      SELECT significado INTO v_mapa FROM controle.macro_mapa WHERE fonte = 'autotrac' AND numero = (i->>'MacroNumber')::smallint;
      IF v_mapa IS NULL THEN
        PERFORM controle.int_saneamento('autotrac', 'macro_sem_mapa', i->>'MacroNumber',
          'Macro nº ' || (i->>'MacroNumber') || ' da Autotrac sem significado no mapa de macros (o motor de jornada não a entende)',
          jsonb_build_object('numero', (i->>'MacroNumber')::integer, 'versao', i->>'MacroVersion'));
      END IF;
      INSERT INTO bruto.autotrac_macro (veiculo_id, motorista_id, horario, numero, descricao, local_texto, local, lote_id)
      VALUES (p_veiculo, v_mot, v_h, (i->>'MacroNumber')::smallint, left(nullif(i->>'MessageText', ''), 200),
              left(nullif(i->>'Landmark', ''), 200),
              bruto.fn_ponto(nullif(i->>'Latitude', '')::numeric, nullif(i->>'Longitude', '')::numeric), p_lote)
      ON CONFLICT (veiculo_id, horario, numero) DO NOTHING;

    ELSE -- driverlogs
      v_h := nullif(i->>'LoginTime', '')::timestamptz;
      IF v_h IS NULL THEN v_ignorados := v_ignorados + 1; CONTINUE; END IF;
      IF v_h < v_min - interval '30 days' OR v_h > v_max THEN v_fora := v_fora + 1; CONTINUE; END IF;
      v_cod := 'nome:' || upper(regexp_replace(btrim(coalesce(i->>'DriverName', '?')), '\s+', ' ', 'g'));
      v_mot := cadastro.fn_motorista_por_nome(i->>'DriverName');
      IF v_mot IS NULL THEN
        PERFORM controle.int_saneamento('autotrac', 'motorista_sem_cadastro', v_cod,
          'Motorista "' || coalesce(i->>'DriverName', '?') || '" logado na Autotrac não está no cadastro do painel (ou há mais de um com esse nome)',
          jsonb_build_object('nome', i->>'DriverName'));
      END IF;
      INSERT INTO bruto.autotrac_login (veiculo_id, motorista_id, codigo_motorista, horario, tipo, lote_id)
      VALUES (p_veiculo, v_mot, v_cod, v_h, 'login', p_lote)
      ON CONFLICT (veiculo_id, horario, tipo) DO NOTHING;
      GET DIAGNOSTICS v_n = ROW_COUNT;
      IF v_n = 1 THEN v_gravados := v_gravados + 1; ELSE v_repetidos := v_repetidos + 1; END IF;
      -- R18: logout em 1970 = ainda logado (não grava)
      v_fim := nullif(i->>'LogoutTime', '')::timestamptz;
      IF v_fim IS NOT NULL AND v_fim > '1971-01-01' AND v_fim > v_h THEN
        INSERT INTO bruto.autotrac_login (veiculo_id, motorista_id, codigo_motorista, horario, tipo, lote_id)
        VALUES (p_veiculo, v_mot, v_cod, v_fim, 'logout', p_lote)
        ON CONFLICT (veiculo_id, horario, tipo) DO NOTHING;
      END IF;
      CONTINUE;
    END IF;

    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n = 1 THEN v_gravados := v_gravados + 1; ELSE v_repetidos := v_repetidos + 1; END IF;
  END LOOP;

  IF p_recurso = 'driverlogs' THEN PERFORM derivado.int_sessoes_veiculo(p_veiculo); END IF;
  UPDATE bruto.ingestao_lote SET linhas = linhas + v_gravados WHERE id = p_lote;
  RETURN jsonb_build_object('recurso', p_recurso, 'gravados', v_gravados, 'repetidos', v_repetidos,
                            'ignorados', v_ignorados, 'fora_do_periodo', v_fora);
END $$;

-- R19: depois do ciclo, liga ao motorista as macros que chegaram antes do login e recalcula a jornada
-- só dos motoristas afetados (macros ou logins deste lote).
CREATE OR REPLACE FUNCTION derivado.job_autotrac_atic_fim(p_lote uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS $$
#variable_conflict use_column
DECLARE m uuid; v_ligadas integer; v_mot integer := 0; v_desde timestamptz := now() - interval '8 days';
BEGIN
  UPDATE bruto.autotrac_macro a SET motorista_id = s.motorista_id
  FROM derivado.sessao_motorista s
  WHERE a.lote_id = p_lote AND a.motorista_id IS NULL AND s.veiculo_id = a.veiculo_id AND s.periodo @> a.horario;
  GET DIAGNOSTICS v_ligadas = ROW_COUNT;

  FOR m IN
    SELECT DISTINCT motorista_id FROM bruto.autotrac_macro WHERE lote_id = p_lote AND motorista_id IS NOT NULL
    UNION
    SELECT DISTINCT motorista_id FROM bruto.autotrac_login WHERE lote_id = p_lote AND motorista_id IS NOT NULL
  LOOP
    PERFORM derivado.job_jornada(v_desde, m);
    v_mot := v_mot + 1;
  END LOOP;
  RETURN jsonb_build_object('macros_ligadas', v_ligadas, 'motoristas_recalculados', v_mot);
END $$;
