-- 012 · Ingestão da Autotrac: endereço da API como parâmetro (produção na VPS; sandbox no computador do dev).
INSERT INTO controle.parametro (chave, valor, unidade, descricao, motivo) VALUES
  ('autotrac.url_telemetria', '"https://aapi4.autotrac-online.com.br/telemetryapi"', NULL,
   'Endereço da API de Telemetria da Autotrac (no computador do dev: o sandbox)', 'Spec ingestao-autotrac'),
  ('autotrac.url_atic', '"https://aapi3.autotrac-online.com.br/aticapi"', NULL,
   'Endereço da API ATIC da Autotrac (fase B)', 'Spec ingestao-autotrac R16');
