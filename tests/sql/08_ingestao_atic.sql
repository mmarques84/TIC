-- Ingestão da Autotrac, fase B: API ATIC (spec ingestao-autotrac V14). Transação desfeita no fim. Tudo fictício.
BEGIN;
SET ROLE tic_dono;

INSERT INTO cadastro.veiculo (id, placa, tipo, origem, id_autotrac) VALUES
  ('00000000-0000-7000-8000-00000000d001', 'TST1A01', 'cavalo', 'manual', '700001'),
  ('00000000-0000-7000-8000-00000000d002', 'TST2B02', 'cavalo', 'manual', NULL);
INSERT INTO cadastro.motorista (id, nome, origem) VALUES
  ('00000000-0000-7000-8000-00000000e001', 'Motorista  Teste Um', 'manual'),
  ('00000000-0000-7000-8000-00000000e002', 'Motorista Repetido', 'manual'),
  ('00000000-0000-7000-8000-00000000e003', 'motorista repetido', 'manual');
-- macro de TESTE no mapa (os números reais vêm da tabela de macros da TIC)
INSERT INTO controle.macro_mapa (fonte, numero, significado) VALUES ('autotrac', 61, 'inicio_jornada'), ('autotrac', 62, 'fim_jornada');

DO $$
DECLARE r jsonb; l uuid; t0 timestamptz := date_trunc('minute', now()) - interval '6 h'; iso text;
BEGIN
  -- frota ATIC: placa do campo LicensePlate; liga id_autotrac_atic sem mexer no id_autotrac
  l := (bruto.job_lote_abrir('autotrac_atic_cadastro'))->>'lote';
  r := cadastro.job_autotrac_veiculos(l, '[{"Code": 51, "Name": "Cavalo 1", "LicensePlate": "TST1A01"},
                                           {"Code": 52, "Name": "TST2B02", "LicensePlate": null}]', 'atic');
  ASSERT (r->>'ligados')::int = 2, 'ligou os dois: ' || r;
  ASSERT (SELECT id_autotrac = '700001' AND id_autotrac_atic = '51' FROM cadastro.veiculo WHERE placa = 'TST1A01'), 'códigos separados por API';
  ASSERT (SELECT id_autotrac_atic FROM cadastro.veiculo WHERE placa = 'TST2B02') = '52', 'placa pelo nome quando falta LicensePlate';
  PERFORM bruto.job_lote_fechar(l);

  -- lote ATIC: chamadas pelo código da ATIC, url e conta da ATIC
  r := bruto.job_lote_abrir('autotrac_atic');
  l := r->>'lote';
  ASSERT r->>'url' LIKE '%aticapi%' AND (r->>'conta')::bigint = 10534, 'url e conta da ATIC: ' || r;
  ASSERT (SELECT bool_and(c->>'codigo' IN ('51', '52')) FROM jsonb_array_elements(r->'chamadas') c), 'códigos da ATIC';

  -- R18: login (nome com espaço duplo e caixa diferente liga), logout de 1970 não grava
  iso := to_char(t0, 'YYYY-MM-DD"T"HH24:MI:SSOF');
  r := bruto.job_autotrac_atic(l, '00000000-0000-7000-8000-00000000d001', 'driverlogs', jsonb_build_array(
    jsonb_build_object('LoginTime', iso, 'LogoutTime', '1970-01-01T00:00:00+00:00', 'DriverName', 'MOTORISTA TESTE UM', 'DriverCPF', '00000000000')));
  ASSERT (r->>'gravados')::int = 1, 'login gravado: ' || r;
  ASSERT (SELECT count(*) FROM bruto.autotrac_login WHERE veiculo_id = '00000000-0000-7000-8000-00000000d001') = 1, 'sem logout de 1970';
  ASSERT (SELECT motorista_id FROM bruto.autotrac_login WHERE veiculo_id = '00000000-0000-7000-8000-00000000d001') = '00000000-0000-7000-8000-00000000e001', 'ligou pelo nome';
  ASSERT (SELECT upper_inf(periodo) FROM derivado.sessao_motorista WHERE veiculo_id = '00000000-0000-7000-8000-00000000d001'), 'sessão aberta';
  -- nome repetido no cadastro não liga e vai para o saneamento
  r := bruto.job_autotrac_atic(l, '00000000-0000-7000-8000-00000000d002', 'driverlogs', jsonb_build_array(
    jsonb_build_object('LoginTime', iso, 'LogoutTime', to_char(t0 + interval '2 h', 'YYYY-MM-DD"T"HH24:MI:SSOF'), 'DriverName', 'Motorista Repetido')));
  ASSERT (SELECT count(*) FROM bruto.autotrac_login WHERE veiculo_id = '00000000-0000-7000-8000-00000000d002' AND motorista_id IS NULL) = 2, 'login e logout sem motorista';
  ASSERT EXISTS (SELECT 1 FROM controle.saneamento WHERE motivo = 'motorista_sem_cadastro' AND chave = 'nome:MOTORISTA REPETIDO'), 'homônimo no saneamento';

  -- R16: posições (hodômetro ÷ 100, ignição, canal), idempotente
  r := bruto.job_autotrac_atic(l, '00000000-0000-7000-8000-00000000d001', 'positions', jsonb_build_array(
    jsonb_build_object('PositionTime', to_char(t0 + interval '1 h', 'YYYY-MM-DD"T"HH24:MI:SSOF'), 'Velocity', 70, 'VehicleIgnition', 1,
      'Odometer', 54251050, 'Latitude', -25.5, 'Longitude', -49.3, 'TransmissionChannel', 33),
    jsonb_build_object('PositionTime', '2024-01-01T00:00:00+00:00', 'Velocity', 10)));
  ASSERT (r->>'gravados')::int = 1 AND (r->>'fora_do_periodo')::int = 1, 'posição gravada, a de 2024 não: ' || r;
  ASSERT (SELECT odometro_km = 542510.5 AND ignicao AND canal = 'satelite' AND velocidade = 70 FROM bruto.autotrac_posicao
          WHERE veiculo_id = '00000000-0000-7000-8000-00000000d001'), 'campos da posição';
  r := bruto.job_autotrac_atic(l, '00000000-0000-7000-8000-00000000d001', 'positions', jsonb_build_array(
    jsonb_build_object('PositionTime', to_char(t0 + interval '1 h', 'YYYY-MM-DD"T"HH24:MI:SSOF'), 'Velocity', 70)));
  ASSERT (r->>'repetidos')::int = 1, 'posição repetida não duplica';

  -- R17: macro 0 (mensagem livre) não entra; macro com mapa ganha o motorista da sessão; sem mapa vai para o saneamento
  r := bruto.job_autotrac_atic(l, '00000000-0000-7000-8000-00000000d001', 'returnmessages', jsonb_build_array(
    jsonb_build_object('MacroNumber', 0, 'MessageTime', to_char(t0 + interval '10 min', 'YYYY-MM-DD"T"HH24:MI:SSOF'), 'MessageText', 'oi'),
    jsonb_build_object('MacroNumber', 61, 'MacroVersion', 1, 'MessageTime', to_char(t0 + interval '5 min', 'YYYY-MM-DD"T"HH24:MI:SSOF'), 'Landmark', 'Curitiba/PR'),
    jsonb_build_object('MacroNumber', 99, 'MessageTime', to_char(t0 + interval '3 h', 'YYYY-MM-DD"T"HH24:MI:SSOF'))));
  ASSERT (r->>'gravados')::int = 2 AND (r->>'ignorados')::int = 1, 'macro 0 ignorada: ' || r;
  ASSERT (SELECT motorista_id FROM bruto.autotrac_macro WHERE numero = 61) = '00000000-0000-7000-8000-00000000e001', 'macro com o motorista logado';
  ASSERT EXISTS (SELECT 1 FROM controle.saneamento WHERE motivo = 'macro_sem_mapa' AND chave = '99'), 'macro sem mapa no saneamento';

  -- macro que chegou antes do login: o fim do ciclo liga ao motorista e recalcula a jornada (R19)
  INSERT INTO bruto.autotrac_macro (veiculo_id, horario, numero, lote_id) VALUES ('00000000-0000-7000-8000-00000000d001', t0 + interval '5 h', 62, l);
  r := derivado.job_autotrac_atic_fim(l);
  ASSERT (r->>'macros_ligadas')::int = 1 AND (r->>'motoristas_recalculados')::int = 1, 'fim do ciclo: ' || r;
  ASSERT EXISTS (SELECT 1 FROM derivado.jornada WHERE motorista_id = '00000000-0000-7000-8000-00000000e001'), 'jornada calculada';
  ASSERT NOT EXISTS (SELECT 1 FROM bruto.autotrac_login l2 WHERE l2.codigo_motorista ~ '[0-9]{11}'), 'sem CPF';
  PERFORM bruto.job_lote_fechar(l);
END $$;

DO $$ BEGIN
  ASSERT has_function_privilege('tic_n8n', 'bruto.job_autotrac_atic(uuid,uuid,text,jsonb)', 'EXECUTE'), 'n8n grava ATIC';
  ASSERT has_function_privilege('tic_n8n', 'derivado.job_autotrac_atic_fim(uuid)', 'EXECUTE'), 'n8n fecha ATIC';
  ASSERT NOT has_function_privilege('tic_n8n', 'derivado.int_sessoes_veiculo(uuid)', 'EXECUTE'), 'int_* fechado';
END $$;
ROLLBACK;
