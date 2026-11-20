-- Motor de jornada (spec motor-jornada V1–V11). Transação desfeita no fim. Tudo fictício (placas TST, motoristas "Teste").
BEGIN;
SET ROLE tic_dono;

-- Códigos de macro de TESTE para a fonte autotrac (os reais vêm da documentação).
INSERT INTO controle.macro_mapa (fonte, numero, significado) VALUES
  ('autotrac', 1, 'inicio_jornada'), ('autotrac', 2, 'inicio_refeicao'), ('autotrac', 3, 'fim_refeicao'),
  ('autotrac', 4, 'fim_jornada'), ('autotrac', 5, 'inicio_parada'), ('autotrac', 6, 'fim_parada');

INSERT INTO cadastro.operacao (id, codigo, nome, tipo) VALUES ('00000000-0000-7000-8000-0000000000f1', 'ipiranga_teste', 'Ipiranga (teste)', 'entrega');
-- R14: Ipiranga com limites próprios
INSERT INTO controle.parametro (chave, valor, unidade, descricao, operacao_id) VALUES
  ('jornada.atencao_dia', '9', 'h', 'teste', '00000000-0000-7000-8000-0000000000f1'),
  ('jornada.limite_dia', '10', 'h', 'teste', '00000000-0000-7000-8000-0000000000f1');

-- Veículos e motoristas de teste: um por cenário.
INSERT INTO cadastro.veiculo (id, placa, tipo, origem)
SELECT ('00000000-0000-7000-8000-0000000001' || lpad(i::text, 2, '0'))::uuid, 'TST' || (i % 10) || chr(65 + i - 10) || lpad(i::text, 2, '0'), 'cavalo', 'manual'
FROM generate_series(10, 30) i;
INSERT INTO cadastro.motorista (id, nome, origem, operacao_id)
SELECT ('00000000-0000-7000-8000-0000000002' || lpad(i::text, 2, '0'))::uuid, 'Motorista Teste ' || i, 'manual',
       CASE WHEN i = 15 THEN '00000000-0000-7000-8000-0000000000f1'::uuid END
FROM generate_series(10, 30) i;

CREATE TEMP TABLE t AS SELECT (date_trunc('day', now() AT TIME ZONE 'America/Sao_Paulo') - interval '3 days') AT TIME ZONE 'America/Sao_Paulo' AS t0;

CREATE FUNCTION pg_temp.mac(p_mot integer, p_vei integer, p_quando timestamptz, p_num integer) RETURNS void LANGUAGE sql AS $$
  INSERT INTO bruto.autotrac_macro (veiculo_id, motorista_id, horario, numero)
  VALUES (('00000000-0000-7000-8000-0000000001' || lpad(p_vei::text, 2, '0'))::uuid,
          ('00000000-0000-7000-8000-0000000002' || lpad(p_mot::text, 2, '0'))::uuid, p_quando, p_num)
$$;
CREATE FUNCTION pg_temp.pos(p_vei integer, p_quando timestamptz, p_vel numeric, p_lon numeric, p_lat numeric) RETURNS void LANGUAGE sql AS $$
  INSERT INTO bruto.autotrac_posicao (veiculo_id, horario, local, velocidade)
  VALUES (('00000000-0000-7000-8000-0000000001' || lpad(p_vei::text, 2, '0'))::uuid, p_quando,
          ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography, p_vel)
$$;
CREATE FUNCTION pg_temp.jor(p_mot integer) RETURNS SETOF derivado.jornada LANGUAGE sql AS $$
  SELECT * FROM derivado.jornada WHERE motorista_id = ('00000000-0000-7000-8000-0000000002' || lpad(p_mot::text, 2, '0'))::uuid ORDER BY inicio
$$;
CREATE FUNCTION pg_temp.sit(p_mot integer) RETURNS derivado.motorista_situacao LANGUAGE sql AS $$
  SELECT * FROM derivado.motorista_situacao WHERE motorista_id = ('00000000-0000-7000-8000-0000000002' || lpad(p_mot::text, 2, '0'))::uuid
$$;

DO $$
DECLARE t0 timestamptz := (SELECT t0 FROM t); i integer;
BEGIN
  -- V1: 06:00 início, 12–13 refeição, 17:00 fim → 11 h de amplitude, 10 h líquidas, dentro
  PERFORM pg_temp.mac(10, 10, t0 + interval '6 h', 1);  PERFORM pg_temp.mac(10, 10, t0 + interval '12 h', 2);
  PERFORM pg_temp.mac(10, 10, t0 + interval '13 h', 3); PERFORM pg_temp.mac(10, 10, t0 + interval '17 h', 4);
  -- V2a: refeição de 3 h → 1 h volta para a jornada (06–18, 11–14)
  PERFORM pg_temp.mac(11, 11, t0 + interval '6 h', 1);  PERFORM pg_temp.mac(11, 11, t0 + interval '11 h', 2);
  PERFORM pg_temp.mac(11, 11, t0 + interval '14 h', 3); PERFORM pg_temp.mac(11, 11, t0 + interval '18 h', 4);
  -- V2b: refeição de 40 min → violação
  PERFORM pg_temp.mac(12, 12, t0 + interval '6 h', 1);  PERFORM pg_temp.mac(12, 12, t0 + interval '12 h', 2);
  PERFORM pg_temp.mac(12, 12, t0 + interval '12 h 40 min', 3); PERFORM pg_temp.mac(12, 12, t0 + interval '15 h', 4);
  -- V3: em curso (há 10 h), sem fim (há 20 h), inconsistente (19 h)
  PERFORM pg_temp.mac(13, 13, now() - interval '10 h', 1);
  PERFORM pg_temp.mac(14, 14, now() - interval '20 h', 1);
  PERFORM pg_temp.mac(16, 16, t0 + interval '5 h', 1);  PERFORM pg_temp.mac(16, 16, t0 + interval '24 h', 4);
  -- V4: 13h30 sem refeição no global → violação; 9h30 na Ipiranga → atenção; 9h30 no global → dentro
  PERFORM pg_temp.mac(17, 17, t0 + interval '5 h', 1);  PERFORM pg_temp.mac(17, 17, t0 + interval '18 h 30 min', 4);
  PERFORM pg_temp.mac(15, 15, t0 + interval '6 h', 1);  PERFORM pg_temp.mac(15, 15, t0 + interval '15 h 30 min', 4);
  PERFORM pg_temp.mac(18, 18, t0 + interval '6 h', 1);  PERFORM pg_temp.mac(18, 18, t0 + interval '15 h 30 min', 4);
  -- V5: 6 h seguidas em movimento → direção contínua
  PERFORM pg_temp.mac(19, 19, t0 + interval '6 h', 1);  PERFORM pg_temp.mac(19, 19, t0 + interval '13 h', 4);
  FOR i IN 0..72 LOOP PERFORM pg_temp.pos(19, t0 + interval '6 h 10 min' + i * interval '5 min', 70, -49.27 + i * 0.005, -25.43); END LOOP;
  PERFORM pg_temp.pos(19, t0 + interval '12 h 15 min', 0, -48.9, -25.43);
  -- V6: fim 22:00, início 06:00 do dia seguinte → interjornada 8 h
  PERFORM pg_temp.mac(20, 20, t0 + interval '12 h', 1); PERFORM pg_temp.mac(20, 20, t0 + interval '22 h', 4);
  PERFORM pg_temp.mac(20, 20, t0 + interval '30 h', 1); PERFORM pg_temp.mac(20, 20, t0 + interval '38 h', 4);
  -- V7a: 36 h parado no mesmo lugar → DSR
  PERFORM pg_temp.mac(21, 21, t0, 1); PERFORM pg_temp.mac(21, 21, t0 + interval '1 h', 4);
  FOR i IN 0..72 LOOP PERFORM pg_temp.pos(21, t0 + interval '2 h' + i * interval '30 min', 0, -49.27, -25.43); END LOOP;
  PERFORM pg_temp.pos(21, t0 + interval '38 h 30 min', 60, -49.20, -25.43);
  -- V7b: 36 h parado, mas o motorista rodou ~87 km logado em outro veículo → não é DSR
  PERFORM pg_temp.mac(22, 22, t0, 1); PERFORM pg_temp.mac(22, 22, t0 + interval '1 h', 4);
  FOR i IN 0..72 LOOP PERFORM pg_temp.pos(22, t0 + interval '2 h' + i * interval '30 min', 0, -49.27, -25.43); END LOOP;
  PERFORM pg_temp.pos(22, t0 + interval '38 h 30 min', 60, -49.20, -25.43);
  INSERT INTO derivado.sessao_motorista (motorista_id, veiculo_id, periodo)
  VALUES ('00000000-0000-7000-8000-000000000222', '00000000-0000-7000-8000-000000000123', tstzrange(t0 + interval '5 h', t0 + interval '10 h'));
  PERFORM pg_temp.pos(23, t0 + interval '6 h', 80, -49.27, -25.43); PERFORM pg_temp.pos(23, t0 + interval '8 h', 80, -48.40, -25.43);
  -- V8a: 30 km hoje sem jornada aberta
  PERFORM pg_temp.mac(24, 24, t0 + interval '6 h', 1); PERFORM pg_temp.mac(24, 24, t0 + interval '8 h', 4);
  INSERT INTO derivado.sessao_motorista (motorista_id, veiculo_id, periodo)
  VALUES ('00000000-0000-7000-8000-000000000224', '00000000-0000-7000-8000-000000000125', tstzrange(now() - interval '40 min', NULL));
  PERFORM pg_temp.pos(25, now() - interval '30 min', 60, -49.27, -25.43); PERFORM pg_temp.pos(25, now() - interval '5 min', 60, -48.97, -25.43);
  -- V8b: jornada aberta no veículo 26 e outro motorista logado nele
  PERFORM pg_temp.mac(26, 26, now() - interval '2 h', 1);
  INSERT INTO derivado.sessao_motorista (motorista_id, veiculo_id, periodo)
  VALUES ('00000000-0000-7000-8000-000000000227', '00000000-0000-7000-8000-000000000126', tstzrange(now() - interval '1 h', NULL));
  -- V10: macro sem mapa
  PERFORM pg_temp.mac(28, 28, t0 + interval '6 h', 1); PERFORM pg_temp.mac(28, 28, t0 + interval '7 h', 99);
  PERFORM pg_temp.mac(28, 28, t0 + interval '9 h', 4);
END $$;

SELECT * FROM derivado.job_jornada((SELECT t0 FROM t) - interval '1 day');

DO $$
DECLARE j record; s derivado.motorista_situacao; n1 integer; n2 integer;
BEGIN
  SELECT * INTO j FROM pg_temp.jor(10) LIMIT 1;
  ASSERT j.amplitude_min = 660 AND j.trabalho_min = 600 AND j.nivel = 'dentro', format('V1: %s %s %s', j.amplitude_min, j.trabalho_min, j.nivel);
  SELECT * INTO j FROM pg_temp.jor(11) LIMIT 1;
  ASSERT j.trabalho_min = 600 AND j.refeicao_min = 180, format('V2a: %s', j.trabalho_min);
  SELECT * INTO j FROM pg_temp.jor(12) LIMIT 1;
  ASSERT j.nivel = 'violacao' AND j.motivos @> '[{"codigo":"refeicao_curta"}]', 'V2b refeição curta';
  SELECT * INTO j FROM pg_temp.jor(13) LIMIT 1;  ASSERT j.situacao = 'em_curso', 'V3 em curso ' || j.situacao;
  SELECT * INTO j FROM pg_temp.jor(14) LIMIT 1;  ASSERT j.situacao = 'sem_fim' AND j.trabalho_min IS NULL, 'V3 sem fim ' || j.situacao;
  SELECT * INTO j FROM pg_temp.jor(16) LIMIT 1;  ASSERT j.situacao = 'inconsistente', 'V3 inconsistente ' || j.situacao;
  SELECT * INTO j FROM pg_temp.jor(17) LIMIT 1;  ASSERT j.nivel = 'violacao' AND j.motivos @> '[{"codigo":"jornada_excedida"}]', 'V4 global 13h30';
  SELECT * INTO j FROM pg_temp.jor(15) LIMIT 1;  ASSERT j.nivel = 'atencao', 'V4/V11 Ipiranga 9h30 ' || j.nivel;
  SELECT * INTO j FROM pg_temp.jor(18) LIMIT 1;  ASSERT j.nivel = 'dentro', 'V4/V11 global 9h30 ' || j.nivel;
  SELECT * INTO j FROM pg_temp.jor(19) LIMIT 1;
  ASSERT j.max_direcao_continua_min >= 331 AND j.motivos @> '[{"codigo":"direcao_continua"}]', format('V5: contínua %s', j.max_direcao_continua_min);
  SELECT * INTO j FROM pg_temp.jor(20) OFFSET 1 LIMIT 1;
  ASSERT j.interjornada_min = 480 AND j.motivos @> '[{"codigo":"interjornada_curta"}]', format('V6: %s', j.interjornada_min);

  ASSERT (SELECT conta_dsr FROM derivado.parada WHERE motorista_id = '00000000-0000-7000-8000-000000000221'), 'V7a DSR';
  ASSERT (SELECT NOT conta_dsr AND km_telemetria > 50 FROM derivado.parada WHERE motorista_id = '00000000-0000-7000-8000-000000000222'), 'V7b não é DSR';
  ASSERT (pg_temp.sit(21)).ultimo_dsr IS NOT NULL, 'V7a último DSR';

  s := pg_temp.sit(24); ASSERT s.alertas @> '[{"codigo":"km_sem_jornada"}]', 'V8a km sem jornada: ' || s.alertas;
  s := pg_temp.sit(26); ASSERT s.alertas @> '[{"codigo":"outro_login"}]' AND s.nivel = 'conferir', 'V8b outro login: ' || s.alertas;
  ASSERT s.status IN ('em_jornada', 'dirigindo'), 'status ' || s.status;
  ASSERT (pg_temp.sit(28)).macros_desconhecidas = 1, 'V10 macro desconhecida';
  ASSERT (SELECT trabalho_min FROM pg_temp.jor(28)) = 180, 'V10 cálculo segue';

  -- V9 (R3, R22): rodar de novo não duplica nada
  SELECT count(*) INTO n1 FROM derivado.evento WHERE origem = 'regra';
  ASSERT n1 > 0, 'gera eventos de violação';
  PERFORM derivado.job_jornada((SELECT t0 FROM t) - interval '1 day');
  SELECT count(*) INTO n2 FROM derivado.evento WHERE origem = 'regra';
  ASSERT n1 = n2, format('V9 eventos %s → %s', n1, n2);
  ASSERT (SELECT count(*) FROM pg_temp.jor(20)) = 2, 'V9 jornadas não duplicam';
END $$;

RESET ROLE;
DO $$ BEGIN
  ASSERT has_function_privilege('tic_n8n', 'derivado.job_jornada(timestamptz,uuid)', 'EXECUTE'), 'n8n executa job_jornada';
  ASSERT NOT has_function_privilege('tic_n8n', 'derivado.int_jornada_motorista(uuid,timestamptz)', 'EXECUTE'), 'int_* fechado';
END $$;
ROLLBACK;
