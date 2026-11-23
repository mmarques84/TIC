-- Dados FICTÍCIOS para a Central de alertas (testes e desenvolvimento local). Nada real: placas TST, "Motorista A…".
-- Idempotente (ids fixos + ON CONFLICT). Uso local:
--   docker compose exec -T postgres psql -U tic_admin -d tic -v ON_ERROR_STOP=1 -c "SET ROLE tic_dono" -f - < tests/dados/central-ficticio.sql

INSERT INTO cadastro.veiculo (id, placa, tipo, origem, id_autotrac) VALUES
  ('00000000-0000-7000-8000-00000000c101', 'TST1A01', 'cavalo', 'manual', 'AT-TESTE-1'),
  ('00000000-0000-7000-8000-00000000c102', 'TST2B02', 'cavalo', 'manual', 'AT-TESTE-2'),
  ('00000000-0000-7000-8000-00000000c103', 'TST3C03', 'cavalo', 'manual', 'AT-TESTE-3'),
  ('00000000-0000-7000-8000-00000000c104', 'TST4D04', 'cavalo', 'manual', 'AT-TESTE-4'),
  ('00000000-0000-7000-8000-00000000c105', 'TST5E05', 'cavalo', 'manual', 'AT-TESTE-5')
ON CONFLICT (id) DO NOTHING;

INSERT INTO cadastro.motorista (id, nome, origem) VALUES
  ('00000000-0000-7000-8000-00000000c201', 'Motorista A', 'manual'),
  ('00000000-0000-7000-8000-00000000c202', 'Motorista B', 'manual'),
  ('00000000-0000-7000-8000-00000000c204', 'Motorista D', 'manual'),
  ('00000000-0000-7000-8000-00000000c205', 'Motorista E', 'manual')
ON CONFLICT (id) DO NOTHING;

INSERT INTO derivado.evento (id, veiculo_id, motorista_id, horario, tipo, origem, gravidade, local, velocidade, dados, chave) VALUES
  ('00000000-0000-7000-8000-00000000c301', '00000000-0000-7000-8000-00000000c101', '00000000-0000-7000-8000-00000000c201', now() - interval '3 min', 'fadiga', 'moovsec', 'critico',
   'SRID=4326;POINT(-49.62 -25.48)', 71, '{"local_texto": "BR-277, Balsa Nova/PR", "link_clipe": "https://exemplo.invalid/clipe/1"}', 'ficticio:c301'),
  ('00000000-0000-7000-8000-00000000c302', '00000000-0000-7000-8000-00000000c102', '00000000-0000-7000-8000-00000000c202', now() - interval '9 min', 'freada_brusca', 'autotrac', 'grave',
   'SRID=4326;POINT(-49.22 -25.45)', 64, '{"local_texto": "Contorno Leste, Curitiba/PR"}', 'ficticio:c302'),
  ('00000000-0000-7000-8000-00000000c303', '00000000-0000-7000-8000-00000000c103', NULL, now() - interval '15 min', 'sem_cinto', 'moovsec', 'grave',
   'SRID=4326;POINT(-48.66 -26.91)', 48, '{"local_texto": "Itajaí/SC"}', 'ficticio:c303'),
  ('00000000-0000-7000-8000-00000000c304', '00000000-0000-7000-8000-00000000c104', '00000000-0000-7000-8000-00000000c204', now() - interval '22 min', 'velocidade', 'autotrac', 'medio',
   'SRID=4326;POINT(-48.65 -27.49)', 85, '{"local_texto": "BR-101, Biguaçu/SC"}', 'ficticio:c304'),
  ('00000000-0000-7000-8000-00000000c305', '00000000-0000-7000-8000-00000000c105', '00000000-0000-7000-8000-00000000c205', now() - interval '31 min', 'fadiga', 'moovsec', 'leve',
   'SRID=4326;POINT(-49.41 -25.59)', 62, '{"local_texto": "Araucária/PR"}', 'ficticio:c305'),
  ('00000000-0000-7000-8000-00000000c306', '00000000-0000-7000-8000-00000000c101', '00000000-0000-7000-8000-00000000c201', now() - interval '35 min', 'fadiga', 'moovsec', 'leve',
   'SRID=4326;POINT(-49.70 -25.47)', 70, '{"local_texto": "BR-277, Campo Largo/PR"}', 'ficticio:c306')
ON CONFLICT (id) DO NOTHING;

INSERT INTO derivado.evento_frame (evento_id, camera, instante, arquivo)
SELECT e.id, c.camera, e.horario, 'ficticio/' || e.id || '/' || c.camera || '.jpg'
FROM derivado.evento e
CROSS JOIN (VALUES ('fadiga'), ('frontal'), ('interna'), ('lateral_esquerda'), ('lateral_direita')) AS c(camera)
WHERE e.chave LIKE 'ficticio:c30%' AND e.origem = 'moovsec'
ON CONFLICT DO NOTHING;

INSERT INTO ia.triagem (evento_id, resultado, confianca, evidencia, modelo, prompt_versao)
SELECT id, r.resultado, r.confianca, r.evidencia, 'ficticio', 'v0'
FROM (VALUES
  ('00000000-0000-7000-8000-00000000c301'::uuid, 'verdadeiro', 'alta', 'Olhos fechados por 2 s em 3 das 5 fotos; boca aberta em bocejo.'),
  ('00000000-0000-7000-8000-00000000c302'::uuid, 'verdadeiro', 'media', 'Olhar para o celular 1 s antes da freada de 22 km/h.'),
  ('00000000-0000-7000-8000-00000000c303'::uuid, 'inconclusivo', 'baixa', 'Imagem escura; não dá para ver o cinto.'),
  ('00000000-0000-7000-8000-00000000c305'::uuid, 'verdadeiro', 'alta', 'Bocejos longos em 4 fotos.'),
  ('00000000-0000-7000-8000-00000000c306'::uuid, 'falso', 'media', 'Motorista coçando o rosto, olhos abertos.')
) AS r(id, resultado, confianca, evidencia)
ON CONFLICT (evento_id, rodada) DO NOTHING;

INSERT INTO derivado.alerta (id, evento_id, nivel, titulo, estado, tratado_por, tratado_em, motivo_falso) VALUES
  ('00000000-0000-7000-8000-00000000c401', '00000000-0000-7000-8000-00000000c301', 'critico', 'Fadiga: 11 bocejos em 1 h', 'aberto', NULL, NULL, NULL),
  ('00000000-0000-7000-8000-00000000c402', '00000000-0000-7000-8000-00000000c302', 'grave', 'Freada brusca + distração', 'aberto', NULL, NULL, NULL),
  ('00000000-0000-7000-8000-00000000c403', '00000000-0000-7000-8000-00000000c303', 'grave', 'Sem cinto há 14 s', 'aberto', NULL, NULL, NULL),
  ('00000000-0000-7000-8000-00000000c404', '00000000-0000-7000-8000-00000000c304', 'medio', 'Velocidade 85 km/h, pista molhada', 'aberto', NULL, NULL, NULL),
  ('00000000-0000-7000-8000-00000000c405', '00000000-0000-7000-8000-00000000c305', 'leve', 'Fadiga: 5 bocejos em 1 h', 'aberto', NULL, NULL, NULL),
  ('00000000-0000-7000-8000-00000000c406', '00000000-0000-7000-8000-00000000c306', 'leve', 'Fadiga: 4 bocejos em 1 h', 'falso_positivo', NULL, now() - interval '30 min', 'gesto')
ON CONFLICT (id) DO NOTHING;

INSERT INTO derivado.acao (alerta_id, tipo, texto, estado, enviada_em)
SELECT '00000000-0000-7000-8000-00000000c401', 'mensagem_terminal', 'Atenção: sinais de sono detectados. Pare no próximo local seguro e descanse.', 'confirmada', now() - interval '3 min'
WHERE NOT EXISTS (SELECT 1 FROM derivado.acao WHERE alerta_id = '00000000-0000-7000-8000-00000000c401');
