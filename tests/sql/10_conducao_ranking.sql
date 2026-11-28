-- Condução, segunda entrega (spec relatorio-conducao V1–V6). Transação desfeita no fim. Tudo fictício.
BEGIN;
SET ROLE tic_dono;

INSERT INTO cadastro.operacao (id, codigo, nome, tipo) VALUES
  ('00000000-0000-7000-8000-0000000001a1', 'op_ca', 'Operação CA (teste)', 'entrega'),
  ('00000000-0000-7000-8000-0000000001a2', 'op_cb', 'Operação CB (teste)', 'entrega');
INSERT INTO cadastro.veiculo (id, placa, tipo, origem, operacao_id) VALUES
  ('00000000-0000-7000-8000-0000000002a1', 'TST1C11', 'cavalo', 'manual', '00000000-0000-7000-8000-0000000001a1'),
  ('00000000-0000-7000-8000-0000000002a2', 'TST2C22', 'cavalo', 'manual', '00000000-0000-7000-8000-0000000001a2');
INSERT INTO cadastro.motorista (id, nome, codigo_autotrac, origem, operacao_id) VALUES
  ('00000000-0000-7000-8000-0000000003a1', 'Motorista Cadastrado', '7001', 'manual', '00000000-0000-7000-8000-0000000001a1');

-- Eventos de hoje (dia de São Paulo), em horários do passado próximo.
CREATE FUNCTION pg_temp.ev(p_vei text, p_min integer, p_tipo text, p_cod text, p_nome text, p_extra jsonb DEFAULT '{}') RETURNS void LANGUAGE sql AS $$
  INSERT INTO bruto.autotrac_evento (veiculo_id, horario, tipo, codigo_motorista, dados)
  VALUES (p_vei::uuid, date_trunc('minute', now()) - make_interval(mins => p_min), p_tipo, p_cod,
          jsonb_build_object('DriverName', p_nome, 'fonte', 'autotrac_telemetria') || p_extra)
$$;

DO $$
DECLARE v1 text := '00000000-0000-7000-8000-0000000002a1'; v2 text := '00000000-0000-7000-8000-0000000002a2';
BEGIN
  -- motorista cadastrado (7001) no TST1C11: 100 km rodados, 4 eventos de condução
  PERFORM pg_temp.ev(v1, 50, 'temporizado', '7001', 'MOTORISTA CADASTRADO', '{"HodometerStart": 1000, "HodometerEnd": 1060}');
  PERFORM pg_temp.ev(v1, 40, 'temporizado', '7001', 'MOTORISTA CADASTRADO', '{"HodometerStart": 1060, "HodometerEnd": 1100}');
  PERFORM pg_temp.ev(v1, 30, 'velocidade_excessiva', '7001', 'MOTORISTA CADASTRADO');
  PERFORM pg_temp.ev(v1, 29, 'rpm_excessiva', '7001', 'MOTORISTA CADASTRADO');
  PERFORM pg_temp.ev(v1, 28, 'marcha_lenta_excessiva', '7001', 'MOTORISTA CADASTRADO',
    jsonb_build_object('EventDateTimeEnd', to_char(date_trunc('minute', now()) - interval '18 min', 'YYYY-MM-DD"T"HH24:MI:SSOF')));
  PERFORM pg_temp.ev(v1, 27, 'pressao_oleo_baixa', '7001', 'MOTORISTA CADASTRADO');
  PERFORM pg_temp.ev(v1, 26, 'ignicao_ligada', '7001', 'MOTORISTA CADASTRADO');
  PERFORM pg_temp.ev(v1, 25, 'desconhecido', '7001', 'MOTORISTA CADASTRADO');
  -- motorista sem cadastro (8002) no TST2C22: 100 km, 10 eventos de velocidade
  PERFORM pg_temp.ev(v2, 60, 'temporizado', '8002', 'FULANO AUTOTRAC', '{"HodometerStart": 500, "HodometerEnd": 600}');
  FOR i IN 1..10 LOOP PERFORM pg_temp.ev(v2, 10 + i, 'velocidade_excessiva', '8002', 'FULANO AUTOTRAC'); END LOOP;
  -- motorista com pouco km (9003): 10 km, 2 eventos → taxa "—"
  PERFORM pg_temp.ev(v2, 5, 'temporizado', '9003', 'POUCO KM', '{"HodometerStart": 600, "HodometerEnd": 610}');
  PERFORM pg_temp.ev(v2, 3, 'banguela', '9003', 'POUCO KM');
  PERFORM pg_temp.ev(v2, 2, 'freada_brusca', '9003', 'POUCO KM');
END $$;

DO $$
DECLARE adm uuid; ti uuid; opa uuid; r jsonb; l jsonb;
BEGIN
  INSERT INTO acesso.usuario (nome, email, perfil, todas_operacoes) VALUES ('Admin C', 'admc@teste.local', 'admin', true) RETURNING id INTO adm;
  INSERT INTO acesso.usuario (nome, email, perfil, todas_operacoes) VALUES ('TI C', 'tic@teste.local', 'ti', true) RETURNING id INTO ti;
  INSERT INTO acesso.usuario (nome, email, perfil, todas_operacoes) VALUES ('Operação CA', 'opca@teste.local', 'operacao', false) RETURNING id INTO opa;
  INSERT INTO acesso.usuario_operacao (usuario_id, operacao_id) VALUES (opa, '00000000-0000-7000-8000-0000000001a1');

  -- V1 (R1): TI sem permissão
  BEGIN PERFORM derivado.sp_conducao_ranking(ti, 'hoje', 'motorista', '', ''); RAISE EXCEPTION 'TI viu';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'SEM_PERMISSAO' THEN RAISE; END IF; END;

  -- V2, V3, V5 (R5–R9): contagens, minutos, km, por 100 km e ordem
  SELECT ranking INTO r FROM derivado.sp_conducao_ranking(adm, 'hoje', 'motorista', '', '');
  ASSERT jsonb_array_length(r->'linhas') = 3, 'três motoristas: ' || (r->'linhas');
  l := r->'linhas'->0;
  ASSERT l->>'nome' = 'FULANO AUTOTRAC' AND (l->>'taxa')::numeric = 10 AND (l->>'velocidade')::int = 10, 'primeiro: 10/100 km: ' || l;
  ASSERT l->>'sub' = 'cód. Autotrac 8002 · não cadastrado' AND NOT (l->>'cadastrado')::boolean, 'V4: não cadastrado';
  l := r->'linhas'->1;
  ASSERT l->>'nome' = 'Motorista Cadastrado' AND (l->>'total')::int = 3, 'cadastrado: 3 eventos (sem óleo, ignição, desconhecido): ' || l;
  ASSERT (l->>'km')::int = 100 AND (l->>'taxa')::numeric = 3 AND (l->>'lentaMin')::int = 10, 'km, taxa e minutos: ' || l;
  ASSERT (r->'linhas'->2->>'taxa') IS NULL AND (r->'linhas'->2->>'total')::int = 2, 'pouco km = —';
  ASSERT (r->'resumo'->>'eventos')::int = 15 AND (r->'resumo'->>'km')::int = 210, 'resumo: ' || (r->'resumo');
  ASSERT (r->'resumo'->>'acimaDe2x')::int = 0 OR (r->'resumo'->>'acimaDe2x')::int = 1, 'acima de 2x calculado';

  -- R11: por caminhão inclui pressão do óleo
  SELECT ranking INTO r FROM derivado.sp_conducao_ranking(adm, 'hoje', 'caminhao', '', '');
  ASSERT (SELECT (x->>'oleo')::int FROM jsonb_array_elements(r->'linhas') x WHERE x->>'nome' = 'TST1C11') = 1, 'óleo no caminhão';

  -- R4: filtro de tipo e busca
  SELECT ranking INTO r FROM derivado.sp_conducao_ranking(adm, 'hoje', 'motorista', 'banguela', '');
  ASSERT (SELECT (x->>'total')::int FROM jsonb_array_elements(r->'linhas') x WHERE x->>'nome' = 'POUCO KM') = 1, 'só banguela';
  SELECT ranking INTO r FROM derivado.sp_conducao_ranking(adm, 'hoje', 'motorista', '', 'fulano');
  ASSERT jsonb_array_length(r->'linhas') = 1, 'busca por nome';

  -- V1 (R2): operação CA não vê o caminhão da operação CB
  SELECT ranking INTO r FROM derivado.sp_conducao_ranking(opa, 'hoje', 'caminhao', '', '');
  ASSERT jsonb_array_length(r->'linhas') = 1 AND r->'linhas'->0->>'nome' = 'TST1C11', 'escopo: ' || (r->'linhas');

  -- R12: detalhe do motorista cadastrado
  SELECT detalhe INTO r FROM derivado.sp_conducao_detalhe(adm, 'hoje', 'motorista', '00000000-0000-7000-8000-0000000003a1');
  ASSERT jsonb_array_length(r->'ultimos') = 3 AND r->'outros'->>0 = 'TST1C11', 'detalhe: ' || r;

  -- V6 (R13): exportar audita
  PERFORM derivado.sp_conducao_exportar(adm, 'hoje', 'motorista', '', '', '10.0.0.1');
  ASSERT EXISTS (SELECT 1 FROM controle.auditoria WHERE acao = 'conducao.exportar' AND usuario_id = adm AND (depois->>'linhas')::int = 3), 'auditado';

  -- entrada inválida
  BEGIN PERFORM derivado.sp_conducao_ranking(adm, 'hoje', 'outra', '', ''); RAISE EXCEPTION 'aceitou visão inválida';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'TIPO_INVALIDO' THEN RAISE; END IF; END;
END $$;

DO $$ BEGIN
  ASSERT has_function_privilege('tic_n8n', 'derivado.sp_conducao_ranking(uuid,text,text,text,text)', 'EXECUTE'), 'n8n: ranking';
  ASSERT has_function_privilege('tic_n8n', 'derivado.sp_conducao_exportar(uuid,text,text,text,text,inet)', 'EXECUTE'), 'n8n: exportar';
  ASSERT NOT has_function_privilege('tic_n8n', 'derivado.int_conducao_base(uuid,text)', 'EXECUTE'), 'int_* fechado';
END $$;
ROLLBACK;
