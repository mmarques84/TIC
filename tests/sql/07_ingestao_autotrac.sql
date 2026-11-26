-- Ingestão da Autotrac (spec ingestao-autotrac V1–V11). Transação desfeita no fim. Tudo fictício (placas TST, códigos 9xxxxx).
BEGIN;
SET ROLE tic_dono;

INSERT INTO cadastro.veiculo (id, placa, tipo, origem) VALUES
  ('00000000-0000-7000-8000-00000000a001', 'TST1A01', 'cavalo', 'manual'),
  ('00000000-0000-7000-8000-00000000a002', 'TST2B02', 'cavalo', 'manual'),
  ('00000000-0000-7000-8000-00000000a003', 'TST3C03', 'cavalo', 'manual'),
  ('00000000-0000-7000-8000-00000000a004', 'TST4D04', 'cavalo', 'manual'),
  ('00000000-0000-7000-8000-00000000a005', 'TST5E05', 'cavalo', 'manual');
INSERT INTO cadastro.motorista (id, nome, codigo_autotrac, origem) VALUES
  ('00000000-0000-7000-8000-00000000b001', 'Motorista Teste 1', '900444', 'manual');

DO $$
DECLARE r jsonb; l uuid; l2 uuid; n integer;
BEGIN
  -- V1 (R5): placa a partir do nome
  ASSERT cadastro.fn_placa_de_nome('ATG8098') = 'ATG8098', 'placa simples';
  ASSERT cadastro.fn_placa_de_nome('AUC5017 - VENDIDO') = 'AUC5017', 'placa com anotação';
  ASSERT cadastro.fn_placa_de_nome('AUT7540 UCC ANTIGA') = 'AUT7540', 'placa com UCC';
  ASSERT cadastro.fn_placa_de_nome('abc-1d23') = 'ABC1D23', 'Mercosul com hífen e minúscula';
  ASSERT cadastro.fn_placa_de_nome('340685') IS NULL, 'só número do equipamento';
  ASSERT cadastro.fn_placa_de_nome('XATG8098') IS NULL, 'não pega pedaço de palavra';

  -- V2, V3 (R6–R8): frota
  l := (bruto.job_lote_abrir('autotrac_cadastro'))->>'lote';
  r := cadastro.job_autotrac_veiculos(l, '[
    {"Code": 900001, "Name": "TST1A01", "Address": "1"},
    {"Code": 900002, "Name": "TST2B02 - VENDIDO", "Address": "2"},
    {"Code": 900003, "Name": "340685", "Address": "340685"},
    {"Code": 900004, "Name": "TST9Z99", "Address": "4"},
    {"Code": 900005, "Name": "TST3C03", "Address": "5"},
    {"Code": 900006, "Name": "TST3C03 cavalo", "Address": "6"},
    {"Code": 900007, "Name": "TST4D04", "Address": "7"}
  ]');
  ASSERT (r->>'ligados')::int = 2, 'ligou TST1A01 e TST4D04: ' || r;
  ASSERT (SELECT id_autotrac FROM cadastro.veiculo WHERE placa = 'TST1A01') = '900001', 'código ligado';
  ASSERT (SELECT id_autotrac FROM cadastro.veiculo WHERE placa = 'TST2B02') IS NULL, 'anotado não liga';
  ASSERT (SELECT id_autotrac FROM cadastro.veiculo WHERE placa = 'TST3C03') IS NULL, 'duplicada não liga';
  ASSERT (SELECT count(*) FROM cadastro.veiculo WHERE placa = 'TST9Z99') = 0, 'não cria veículo';
  ASSERT (SELECT count(*) FROM cadastro.veiculo WHERE ativo) = (SELECT count(*) FROM cadastro.veiculo), 'não desativa';
  SELECT count(*) INTO n FROM controle.saneamento WHERE estado = 'aberto'
    AND motivo IN ('veiculo_anotado', 'veiculo_sem_placa', 'placa_sem_cadastro', 'placa_duplicada');
  ASSERT n = 4, 'quatro itens no saneamento: ' || n;

  -- R8: código já usado por outro veículo → conflito, nada muda
  r := cadastro.job_autotrac_veiculos(l, '[{"Code": 900001, "Name": "TST5E05", "Address": "9"}]');
  ASSERT (SELECT id_autotrac FROM cadastro.veiculo WHERE placa = 'TST5E05') IS NULL, 'conflito não liga';
  ASSERT EXISTS (SELECT 1 FROM controle.saneamento WHERE motivo = 'codigo_em_conflito' AND chave = '900001'), 'conflito no saneamento';
  -- rodar de novo não duplica o saneamento: soma "vezes"
  r := cadastro.job_autotrac_veiculos(l, '[{"Code": 900003, "Name": "340685", "Address": "340685"}]');
  ASSERT (SELECT vezes FROM controle.saneamento WHERE motivo = 'veiculo_sem_placa' AND chave = '900003') = 2, 'vezes = 2';
  PERFORM bruto.job_lote_fechar(l);

  -- V4–V7 (R11–R14): eventos
  l := (bruto.job_lote_abrir('autotrac_evento'))->>'lote';
  r := bruto.job_autotrac_eventos(l, '00000000-0000-7000-8000-00000000a001', 'telemetria', jsonb_build_array(
    jsonb_build_object('Code', 1, 'EventNumberStart', 4, 'EventDateTimeStart', to_char(now() - interval '2 h', 'YYYY-MM-DD"T"HH24:MI:SSOF'),
      'DriverID', 900444, 'DriverName', 'Motorista Teste 1', 'DriverCPF', '00000000000', 'VelocityMax', 72,
      'StartLatitude', -25.5, 'StartLongitude', -49.3),
    jsonb_build_object('Code', 2, 'EventNumberStart', 77, 'EventDateTimeStart', to_char(now() - interval '1 h', 'YYYY-MM-DD"T"HH24:MI:SSOF'),
      'DriverID', 912345, 'VelocityMax', 40),
    jsonb_build_object('Code', 3, 'EventNumberStart', 16, 'EventDateTimeStart', '2024-07-04T14:06:00+00:00', 'DriverID', 900444)
  ));
  ASSERT (r->>'gravados')::int = 2 AND (r->>'fora_do_periodo')::int = 1, 'grava 2, descarta o de 2024: ' || r;
  ASSERT (SELECT tipo FROM bruto.autotrac_evento WHERE origem_id = '1') = 'freada_brusca', 'mapa 4 → freada_brusca';
  ASSERT (SELECT motorista_id FROM bruto.autotrac_evento WHERE origem_id = '1') = '00000000-0000-7000-8000-00000000b001', 'motorista ligado';
  ASSERT (SELECT local IS NOT NULL AND velocidade = 72 FROM bruto.autotrac_evento WHERE origem_id = '1'), 'local e velocidade';
  -- V5: sem mapa
  ASSERT (SELECT tipo = 'desconhecido' AND dados->>'chave' = '77' FROM bruto.autotrac_evento WHERE origem_id = '2'), 'desconhecido com o número';
  ASSERT EXISTS (SELECT 1 FROM controle.saneamento WHERE motivo = 'tipo_evento_sem_mapa' AND chave = 'autotrac_telemetria:77'), 'sem mapa no saneamento';
  -- V7: motorista desconhecido
  ASSERT (SELECT motorista_id IS NULL AND codigo_motorista = '912345' FROM bruto.autotrac_evento WHERE origem_id = '2'), 'sem motorista';
  ASSERT EXISTS (SELECT 1 FROM controle.saneamento WHERE motivo = 'motorista_sem_cadastro' AND chave = '912345'), 'motorista no saneamento';
  -- V6: nada de CPF
  ASSERT NOT EXISTS (SELECT 1 FROM bruto.autotrac_evento e, jsonb_object_keys(e.dados) k WHERE k ~* 'cpf'), 'sem CPF';
  -- V4: idempotente
  r := bruto.job_autotrac_eventos(l, '00000000-0000-7000-8000-00000000a001', 'telemetria', jsonb_build_array(
    jsonb_build_object('Code', 1, 'EventNumberStart', 4, 'EventDateTimeStart', to_char(now() - interval '2 h', 'YYYY-MM-DD"T"HH24:MI:SSOF'), 'DriverID', 900444)));
  ASSERT (r->>'gravados')::int = 0 AND (r->>'repetidos')::int = 1, 'repetido não grava: ' || r;
  -- câmera (SDS): tipo sem mapa entra como desconhecido, vídeo só o hash
  r := bruto.job_autotrac_eventos(l, '00000000-0000-7000-8000-00000000a001', 'sds', jsonb_build_array(
    jsonb_build_object('ID', 55, 'EventName', 'Motorista não detectado', 'EventTime', to_char(now() - interval '30 min', 'YYYY-MM-DD"T"HH24:MI:SSOF'),
      'Latitude', -25.4, 'Longitude', -49.2, 'Velocity', 45, 'HasVideo', true, 'VideoHash', 'HASHTESTE')));
  ASSERT (SELECT dados->>'VideoHash' = 'HASHTESTE' AND tipo = 'desconhecido' FROM bruto.autotrac_evento WHERE origem_id = '55'), 'sds gravado';
  ASSERT (SELECT linhas FROM bruto.ingestao_lote WHERE id = l) = 3, 'linhas do lote';

  -- V11 (R20): falha num veículo fecha como erro, citando a placa
  r := bruto.job_lote_fechar(l, '[{"placa": "TST4D04", "http": 500}]');
  ASSERT r->>'estado' = 'erro' AND (SELECT erro LIKE '%TST4D04 500%' FROM bruto.ingestao_lote WHERE id = l), 'lote com erro';

  -- V8 (R9, R10): janelas. Último evento do TST1A01 há 2 h → uma chamada desde 2h10.
  r := bruto.job_lote_abrir('autotrac_evento');
  ASSERT (SELECT count(*) FROM jsonb_array_elements(r->'chamadas') c WHERE c->>'veiculo' = '00000000-0000-7000-8000-00000000a001') = 1, 'uma janela';
  -- TST4D04 (ligado, sem evento): começa autotrac.telemetria.inicio_h (24 h) atrás → 1 janela de 24 h
  ASSERT (SELECT count(*) FROM jsonb_array_elements(r->'chamadas') c WHERE c->>'veiculo' = '00000000-0000-7000-8000-00000000a004') = 1, 'primeira vez: 24 h';
  ASSERT (r->>'conta')::bigint = 10534, 'conta da Telemetria';
  PERFORM bruto.job_lote_fechar((r->>'lote')::uuid);
  -- Último evento há 3 dias → 3 janelas de 24 h; há 9 dias → 7 janelas e perda registrada
  UPDATE bruto.autotrac_evento SET horario = horario - interval '3 days' WHERE veiculo_id = '00000000-0000-7000-8000-00000000a001';
  r := bruto.job_lote_abrir('autotrac_evento');
  ASSERT (SELECT count(*) FROM jsonb_array_elements(r->'chamadas') c WHERE c->>'veiculo' = '00000000-0000-7000-8000-00000000a001') = 4, '3 dias e 2 h → 4 janelas';
  PERFORM bruto.job_lote_fechar((r->>'lote')::uuid);
  UPDATE bruto.autotrac_evento SET horario = horario - interval '6 days' WHERE veiculo_id = '00000000-0000-7000-8000-00000000a001';
  r := bruto.job_lote_abrir('autotrac_evento');
  ASSERT jsonb_array_length(r->'perdas') = 1, 'perda registrada';
  ASSERT (SELECT count(*) FROM jsonb_array_elements(r->'chamadas') c WHERE c->>'veiculo' = '00000000-0000-7000-8000-00000000a001') = 7, '7 dias → 7 janelas';
  ASSERT (SELECT erro LIKE 'Dados perdidos%' FROM bruto.ingestao_lote WHERE id = (r->>'lote')::uuid), 'lote avisa a perda';
  PERFORM bruto.job_lote_fechar((r->>'lote')::uuid);

  -- V9 (R3): 401 bloqueia; sucesso libera; erro não guarda mais que 500 caracteres
  r := controle.job_credencial('autotrac', false, 401, 'HTTP 401 na API de Telemetria');
  ASSERT (r->>'interromper')::boolean, '401 interrompe';
  ASSERT (SELECT senha_mudou AND ultimo_http = 401 FROM controle.credencial_status WHERE fonte = 'autotrac'), 'senha_mudou';
  ASSERT ((bruto.job_lote_abrir('autotrac_evento'))->>'bloqueado')::boolean, 'ciclo bloqueado';
  PERFORM controle.job_credencial('autotrac', false, 500, repeat('x', 900));
  ASSERT (SELECT length(ultimo_erro) = 500 FROM controle.credencial_status WHERE fonte = 'autotrac'), 'erro cortado';
  PERFORM controle.job_credencial('autotrac', true);
  ASSERT (SELECT NOT senha_mudou AND ultimo_sucesso IS NOT NULL FROM controle.credencial_status WHERE fonte = 'autotrac'), 'sucesso libera';
END $$;

DO $$ BEGIN
  ASSERT has_function_privilege('tic_n8n', 'bruto.job_autotrac_eventos(uuid,uuid,text,jsonb)', 'EXECUTE'), 'n8n grava eventos';
  ASSERT has_function_privilege('tic_n8n', 'cadastro.job_autotrac_veiculos(uuid,jsonb,text)', 'EXECUTE'), 'n8n grava frota';
  ASSERT NOT has_function_privilege('tic_n8n', 'controle.int_saneamento(text,text,text,text,jsonb)', 'EXECUTE'), 'int_* fechado';
END $$;
ROLLBACK;
