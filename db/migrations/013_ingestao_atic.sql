-- 013 · Ingestão da Autotrac, fase B: API ATIC (spec ingestao-autotrac R16–R19). Posições, macros e login do motorista.

-- Cada API da Autotrac tem o seu código de veículo: o da ATIC fica separado do da Telemetria (id_autotrac).
ALTER TABLE cadastro.veiculo ADD COLUMN id_autotrac_atic text NULL UNIQUE;

ALTER TABLE bruto.ingestao_lote DROP CONSTRAINT ingestao_lote_fonte_check;
ALTER TABLE bruto.ingestao_lote ADD CONSTRAINT ingestao_lote_fonte_check
  CHECK (fonte IN ('autotrac_posicao', 'autotrac_evento', 'autotrac_macro', 'autotrac_login', 'autotrac_cadastro',
                   'autotrac_atic', 'autotrac_atic_cadastro', 'moovsec_alarme', 'datapar'));

-- Macro sem significado no mapa (R17) vai para o saneamento com motivo próprio.
ALTER TABLE controle.saneamento DROP CONSTRAINT saneamento_motivo_check;
ALTER TABLE controle.saneamento ADD CONSTRAINT saneamento_motivo_check
  CHECK (motivo IN ('placa_sem_cadastro', 'veiculo_sem_placa', 'veiculo_anotado', 'placa_duplicada', 'codigo_em_conflito',
                    'tipo_evento_sem_mapa', 'motorista_sem_cadastro', 'macro_sem_mapa'));

INSERT INTO controle.parametro (chave, valor, unidade, descricao, motivo) VALUES
  ('autotrac.conta_atic',        '10534', NULL,  'Código da conta da TIC na API ATIC (a confirmar no primeiro acesso)', 'Spec ingestao-autotrac R16'),
  ('autotrac.atic.intervalo_min', '5',    'min', 'De quanto em quanto tempo posições, macros e logins são buscados', 'Spec ingestao-autotrac R16');
