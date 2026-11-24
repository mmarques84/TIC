-- Dados FICTÍCIOS para a tela de Jornada (testes e desenvolvimento local). Placas TST, "Motorista X".
-- Usa códigos de macro FICTÍCIOS 901–906 e 931 (sem mapa), que não colidem com os da Autotrac.
-- Refaz do zero só os registros destes motoristas/veículos fictícios e roda o motor de jornada no fim.
-- Uso local:  docker compose exec -T postgres psql -U tic_admin -d tic -c "SET ROLE tic_dono" -f - < tests/dados/jornada-ficticio.sql

INSERT INTO controle.macro_mapa (fonte, numero, significado, descricao) VALUES
  ('autotrac', 901, 'inicio_jornada', 'FICTÍCIO (dev)'), ('autotrac', 902, 'inicio_refeicao', 'FICTÍCIO (dev)'),
  ('autotrac', 903, 'fim_refeicao', 'FICTÍCIO (dev)'), ('autotrac', 904, 'fim_jornada', 'FICTÍCIO (dev)'),
  ('autotrac', 905, 'inicio_parada', 'FICTÍCIO (dev)'), ('autotrac', 906, 'fim_parada', 'FICTÍCIO (dev)')
ON CONFLICT (fonte, numero) DO NOTHING;

INSERT INTO cadastro.veiculo (id, placa, tipo, origem) VALUES
  ('00000000-0000-7000-8000-00000000c101', 'TST1A01', 'cavalo', 'manual'),
  ('00000000-0000-7000-8000-00000000c102', 'TST2B02', 'cavalo', 'manual'),
  ('00000000-0000-7000-8000-00000000c105', 'TST5E05', 'cavalo', 'manual'),
  ('00000000-0000-7000-8000-00000000c107', 'TST6F06', 'cavalo', 'manual'),
  ('00000000-0000-7000-8000-00000000c108', 'TST9H09', 'cavalo', 'manual'),
  ('00000000-0000-7000-8000-00000000c109', 'TST7G07', 'cavalo', 'manual')
ON CONFLICT (id) DO NOTHING;

INSERT INTO cadastro.motorista (id, nome, origem) VALUES
  ('00000000-0000-7000-8000-00000000c201', 'Motorista A', 'manual'),
  ('00000000-0000-7000-8000-00000000c202', 'Motorista B', 'manual'),
  ('00000000-0000-7000-8000-00000000c205', 'Motorista E', 'manual'),
  ('00000000-0000-7000-8000-00000000c207', 'Motorista H', 'manual'),
  ('00000000-0000-7000-8000-00000000c208', 'Motorista J', 'manual'),
  ('00000000-0000-7000-8000-00000000c209', 'Motorista G', 'manual')
ON CONFLICT (id) DO NOTHING;

-- Limpa o que é destes fictícios (só eles).
CREATE TEMP TABLE IF NOT EXISTS ficticio_m (id uuid);
TRUNCATE ficticio_m;
INSERT INTO ficticio_m VALUES ('00000000-0000-7000-8000-00000000c201'), ('00000000-0000-7000-8000-00000000c202'), ('00000000-0000-7000-8000-00000000c205'),
  ('00000000-0000-7000-8000-00000000c207'), ('00000000-0000-7000-8000-00000000c208'), ('00000000-0000-7000-8000-00000000c209');
DELETE FROM derivado.tratativa WHERE motorista_id IN (SELECT id FROM ficticio_m);
UPDATE derivado.motorista_situacao SET jornada_atual_id = NULL WHERE motorista_id IN (SELECT id FROM ficticio_m);
DELETE FROM derivado.motorista_situacao WHERE motorista_id IN (SELECT id FROM ficticio_m);
DELETE FROM derivado.parada WHERE motorista_id IN (SELECT id FROM ficticio_m);
DELETE FROM derivado.evento WHERE origem = 'regra' AND motorista_id IN (SELECT id FROM ficticio_m);
DELETE FROM derivado.jornada WHERE motorista_id IN (SELECT id FROM ficticio_m);
DELETE FROM derivado.sessao_motorista WHERE motorista_id IN (SELECT id FROM ficticio_m);
DELETE FROM bruto.autotrac_macro WHERE motorista_id IN (SELECT id FROM ficticio_m);
DELETE FROM bruto.autotrac_posicao WHERE veiculo_id IN ('00000000-0000-7000-8000-00000000c101', '00000000-0000-7000-8000-00000000c102',
  '00000000-0000-7000-8000-00000000c105', '00000000-0000-7000-8000-00000000c107', '00000000-0000-7000-8000-00000000c108', '00000000-0000-7000-8000-00000000c109')
  AND horario >= now() - interval '9 days';

CREATE OR REPLACE FUNCTION pg_temp.mac(p_m text, p_v text, p_h timestamptz, p_n integer, p_local text) RETURNS void LANGUAGE sql AS $$
  INSERT INTO bruto.autotrac_macro (veiculo_id, motorista_id, horario, numero, local_texto)
  VALUES (('00000000-0000-7000-8000-00000000c1' || p_v)::uuid, ('00000000-0000-7000-8000-00000000c2' || p_m)::uuid, p_h, p_n, p_local)
  ON CONFLICT DO NOTHING
$$;
CREATE OR REPLACE FUNCTION pg_temp.pos(p_v text, p_h timestamptz, p_vel numeric, p_lon numeric, p_lat numeric) RETURNS void LANGUAGE sql AS $$
  INSERT INTO bruto.autotrac_posicao (veiculo_id, horario, local, velocidade)
  VALUES (('00000000-0000-7000-8000-00000000c1' || p_v)::uuid, p_h, ST_SetSRID(ST_MakePoint(p_lon, p_lat), 4326)::geography, p_vel)
  ON CONFLICT DO NOTHING
$$;

DO $$
DECLARE
  h0 timestamptz := date_trunc('day', now() AT TIME ZONE 'America/Sao_Paulo') AT TIME ZONE 'America/Sao_Paulo';  -- hoje 00:00 SP
  k integer; i integer;
BEGIN
  -- Motorista A: 7 dias sem DSR, ontem perto do limite, anteontem acima de 12 h; hoje dirigindo há 6h10 sem parar e refeição curta.
  FOR k IN 3..6 LOOP
    PERFORM pg_temp.mac('01', '01', h0 - k * interval '1 day' + interval '6 h', 901, 'Curitiba/PR');
    PERFORM pg_temp.mac('01', '01', h0 - k * interval '1 day' + interval '14 h', 904, 'Ponta Grossa/PR');
  END LOOP;
  PERFORM pg_temp.mac('01', '01', h0 - interval '2 days' + interval '6 h', 901, 'Curitiba/PR');
  PERFORM pg_temp.mac('01', '01', h0 - interval '2 days' + interval '12 h', 902, 'Guarapuava/PR');
  PERFORM pg_temp.mac('01', '01', h0 - interval '2 days' + interval '13 h 20 min', 903, 'Guarapuava/PR');
  PERFORM pg_temp.mac('01', '01', h0 - interval '2 days' + interval '19 h 40 min', 904, 'Cascavel/PR');
  PERFORM pg_temp.mac('01', '01', h0 - interval '1 day' + interval '6 h 20 min', 901, 'Cascavel/PR');
  PERFORM pg_temp.mac('01', '01', h0 - interval '1 day' + interval '12 h', 902, 'Toledo/PR');
  PERFORM pg_temp.mac('01', '01', h0 - interval '1 day' + interval '13 h', 903, 'Toledo/PR');
  PERFORM pg_temp.mac('01', '01', h0 - interval '1 day' + interval '17 h 30 min', 904, 'Curitiba/PR');
  PERFORM pg_temp.mac('01', '01', now() - interval '12 h 40 min', 901, 'Curitiba/PR');
  PERFORM pg_temp.mac('01', '01', now() - interval '7 h', 902, 'Balsa Nova/PR');
  PERFORM pg_temp.mac('01', '01', now() - interval '6 h 20 min', 903, 'Balsa Nova/PR');
  PERFORM pg_temp.mac('01', '01', now() - interval '5 h', 931, 'BR-277, Palmeira/PR');  -- macro sem mapa
  FOR i IN 0..74 LOOP PERFORM pg_temp.pos('01', now() - interval '6 h 10 min' + i * interval '5 min', 70, -49.40 - i * 0.004, -25.43); END LOOP;

  -- Motorista B: dirigindo há pouco, dentro do limite.
  PERFORM pg_temp.mac('02', '02', now() - interval '4 h 50 min', 901, 'Curitiba/PR');
  FOR i IN 0..4 LOOP PERFORM pg_temp.pos('02', now() - interval '20 min' + i * interval '5 min', 64, -49.22 + i * 0.005, -25.45); END LOOP;

  -- Motorista H: jornada aberta há 40 h e parado no mesmo lugar há 36 h (DSR ou espera?).
  PERFORM pg_temp.mac('07', '07', now() - interval '40 h', 901, 'Itajaí/SC');
  PERFORM pg_temp.pos('07', now() - interval '37 h', 60, -48.70, -26.90);
  FOR i IN 0..72 LOOP PERFORM pg_temp.pos('07', now() - interval '36 h 10 min' + i * interval '30 min', 0, -48.66, -26.91); END LOOP;

  -- Motorista J: ontem normal; hoje rodou ~34 km logado sem abrir jornada.
  PERFORM pg_temp.mac('08', '08', h0 - interval '1 day' + interval '7 h', 901, 'Araucária/PR');
  PERFORM pg_temp.mac('08', '08', h0 - interval '1 day' + interval '16 h', 904, 'Araucária/PR');
  INSERT INTO derivado.sessao_motorista (motorista_id, veiculo_id, periodo)
  VALUES ('00000000-0000-7000-8000-00000000c208', '00000000-0000-7000-8000-00000000c108', tstzrange(greatest(h0, now() - interval '3 h'), NULL));
  PERFORM pg_temp.pos('08', greatest(h0, now() - interval '3 h') + interval '10 min', 60, -49.41, -25.59);
  PERFORM pg_temp.pos('08', greatest(h0, now() - interval '3 h') + interval '50 min', 60, -49.07, -25.59);

  -- Motorista G: 6 dias seguidos; hoje 11 h de jornada e em refeição agora.
  FOR k IN 1..5 LOOP
    PERFORM pg_temp.mac('09', '09', h0 - k * interval '1 day' + interval '6 h', 901, 'Biguaçu/SC');
    PERFORM pg_temp.mac('09', '09', h0 - k * interval '1 day' + interval '11 h', 902, 'Biguaçu/SC');
    PERFORM pg_temp.mac('09', '09', h0 - k * interval '1 day' + interval '12 h', 903, 'Biguaçu/SC');
    PERFORM pg_temp.mac('09', '09', h0 - k * interval '1 day' + interval '15 h', 904, 'Biguaçu/SC');
  END LOOP;
  PERFORM pg_temp.mac('09', '09', now() - interval '11 h', 901, 'Biguaçu/SC');
  PERFORM pg_temp.mac('09', '09', now() - interval '35 min', 902, 'Posto BR-101, Biguaçu/SC');
  PERFORM pg_temp.pos('09', now() - interval '35 min', 0, -48.65, -27.49);

  -- Motorista E: descansou 36 h na matriz (DSR) e está fora de jornada.
  PERFORM pg_temp.mac('05', '05', now() - interval '60 h', 901, 'Curitiba/PR');
  PERFORM pg_temp.mac('05', '05', now() - interval '51 h', 904, 'Matriz TIC, Curitiba/PR');
  FOR i IN 0..72 LOOP PERFORM pg_temp.pos('05', now() - interval '50 h' + i * interval '30 min', 0, -49.27, -25.43); END LOOP;
  PERFORM pg_temp.pos('05', now() - interval '13 h 30 min', 50, -49.20, -25.43);
END $$;

SELECT * FROM derivado.job_jornada(now() - interval '8 days');
