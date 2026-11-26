-- 014 · Status da credencial separado por API da Autotrac (spec ingestao-autotrac R3).
-- A chave da Telemetria não vale para a ATIC (401 em 26/11/2026): um 401 da ATIC não pode bloquear a Telemetria.
ALTER TABLE controle.credencial_status DROP CONSTRAINT credencial_status_fonte_check;
ALTER TABLE controle.credencial_status ADD CONSTRAINT credencial_status_fonte_check
  CHECK (fonte IN ('autotrac', 'autotrac_atic', 'moovsec', 'datapar', 'portran', 'claude'));
INSERT INTO controle.credencial_status (fonte) VALUES ('autotrac_atic') ON CONFLICT (fonte) DO NOTHING;
